/*	oofnd/String.hpp
        oo::str: string utilities over UTF-8 std::string (ADR-0013 decision 4), the C++ shape of the
        NSString methods Oolite relies on and of its own NSString categories (bead oo-dps, proposed
        ADR-0034). Every function reproduces what GNUstep base 1.31.1 does, character for character;
        tests/unit/oofnd/test_string.cpp pins each one against output captured from it.

            Foundation / Oolite category                  oo::str
            --------------------------------------------  ----------------------------------------------
            [s length] (UTF-16 units)                     oo::str::length(s)
            [s uppercaseString] / lowercaseString         oo::str::uppercase(s) / lowercase(s)
            [s capitalizedString]                         oo::str::capitalized(s)
            [s caseInsensitiveCompare:t] == NSOrderedSame oo::str::equalsIgnoringCaseAscii(s, t)  (t ASCII)
            [s stringByTrimmingLeadingWhitespace          oo::str::trimLeadingWhitespaceAndNewlines(s)
                AndNewlineCharacters]   (NSStringOOExtensions)
            ... TrailingWhitespaceAndNewlineCharacters    oo::str::trimTrailingWhitespaceAndNewlines(s)
            [s stringByTrimmingCharactersInSet:           oo::str::trimWhitespaceAndNewlines(s)
                whitespaceAndNewlineCharacterSet]
            [s oo_hash]                                   oo::str::ooHash(s)
            [s utf16DataWithBOM:b]                        oo::str::utf16Data(s, b)   (an oo::Data)
            +stringWithContentsOfUnicodeFile: (bytes)     oo::str::decodeUnicodeFile(data)
            +stringWithUTF16String:                       oo::utf16ToUtf8(u16string_view(chars))  (PList.hpp)
            OOTabString(n)                                oo::str::tabString(n)
            [m appendLine:l]                              oo::str::appendLine(m, l)
            [m deleteCharacterAtIndex:i]                  oo::str::deleteUnitAt(m, i)  (i in UTF-16 units)
            [s pathExtension]                             oo::str::pathExtension(s)
            [s pathHasExtension:e]  (OOStringParsing)     oo::str::pathHasExtension(s, e)
            [s pathHasExtensionInArray:a]                 oo::str::pathHasExtensionIn(s, a)
            [m replaceOccurrencesOfString:t withString:r  oo::str::replaceOccurrences(m, t, r)
        options:0 range:<all>]                    (NSLiteralSearch: ..., Search::literal)
    [s componentsSeparatedByString:sep]           oo::str::split(s, sep)
            ScanTokensFromString(s)                       oo::str::tokens(s)
            [s intValue] / longLongValue / doubleValue    oo::str::intValue(s) / longLongValue / doubleValue
            [s hasPrefix:p] / hasSuffix:                  oo::str::hasPrefix(s, p) / hasSuffix(s, p)
            [s compare:t] / [s caseInsensitiveCompare:t]  oo::str::compare(s, t) / caseInsensitiveCompare(s, t)  (<0, 0, >0)
            [s pathComponents] / +pathWithComponents:    oo::str::pathComponents(s) / pathWithComponents(v)
            [s lastPathComponent]                         oo::str::lastPathComponent(s)
            [s stringByDeletingLastPathComponent]         oo::str::deletingLastPathComponent(s)
            [s stringByAppendingPathComponent:c]          oo::str::appendingPathComponent(s, c)  (c: one component)
            [s stringByAppendingPathExtension:e]          oo::str::appendingPathExtension(s, e)
            %p in a format string                         %s with oo::str::pointerDescription(p).c_str()
            ComponentsFromVersionString(s)                oo::str::versionComponents(s)
            CompareVersions(a, b)                         oo::str::compareVersions(a, b)  (<0, 0, >0)
            [NSString stringWithFormat:f, ...] (no %@)    oo::str::format(f, ...)
            [NSString stringWithFormat:f, ...], f read    oo::str::formatRuntime(f, {args...})  (%@, %p,
                at run time (DESC, a plist template)      positional; FormatArg per argument)

        Strings are UTF-8 (WTF-8 for a lone surrogate, as oo::PList holds them). Where GNUstep's
        answer depends on UTF-16 (case tables, character sets, lengths and indices), the function
        works on the UTF-16 units exactly as NSString does and converts back.

        Header-only, C++20, compiles with -fno-exceptions.
*/

#ifndef OOFND_STRING_HPP
#define OOFND_STRING_HPP

// Objective-C++ callers see OOFoundation.h's `#define true 1` / `#define false 0`; suspend them for
// this header (proposed ADR-0028).
#pragma push_macro("true")
#pragma push_macro("false")
#undef true
#undef false

#include "oofnd/Data.hpp"
#include "oofnd/PList.hpp" // utf8ToUtf16 / utf16ToUtf8, and PListGet.hpp's GNUstep number readers
#include "oofnd/PrintfFormat.h"

#include <algorithm>
#include <charconv>
#include <cmath>
#include <cstdarg>
#include <cstdint>
#include <cstdio>
#include <initializer_list>
#include <iterator>
#include <memory>
#include <span>
#include <string>
#include <string_view>
#include <vector>

// ICU (C API), for localizedCompare: GNUstep-base already links it, so no new runtime dependency.
#include <unicode/ucol.h>
#include <unicode/uloc.h>

namespace oo::str {

// --- character classes and case, GNUstep 1.31.1's tables (probed over the BMP) ---------------

// +[NSCharacterSet whitespaceAndNewlineCharacterSet]. The set GNUstep's trimming, tokenising,
// NSScanner skipping and -capitalizedString word breaks all use.
constexpr bool isWhitespaceOrNewline(char16_t c) noexcept { return plist_get::isScannerWhitespace(c); }

namespace detail {

    // A run of units first..last (every stride-th one) whose case mapping is c + delta.
    struct CaseRun {
        char16_t first, last;
        std::int16_t delta;
        std::uint8_t stride;
    };

    // uni_toupper / uni_tolower as -uppercaseString / -lowercaseString apply them, one unit to one
    // unit (GNUstep maps no unit to several). Generated from the probe's full BMP table.
    inline constexpr CaseRun kUpper[] = {
        { 0x0061, 0x007A, -32, 1 },
        { 0x00B5, 0x00B5, 743, 1 },
        { 0x00E0, 0x00F6, -32, 1 },
        { 0x00F8, 0x00FE, -32, 1 },
        { 0x00FF, 0x00FF, 121, 1 },
        { 0x0101, 0x012F, -1, 2 },
        { 0x0131, 0x0131, -232, 1 },
        { 0x0133, 0x0137, -1, 2 },
        { 0x013A, 0x0148, -1, 2 },
        { 0x014B, 0x0177, -1, 2 },
        { 0x017A, 0x017E, -1, 2 },
        { 0x017F, 0x017F, -300, 1 },
        { 0x0183, 0x0185, -1, 2 },
        { 0x0188, 0x0188, -1, 1 },
        { 0x018C, 0x018C, -1, 1 },
        { 0x0192, 0x0192, -1, 1 },
        { 0x0195, 0x0195, 97, 1 },
        { 0x0199, 0x0199, -1, 1 },
        { 0x01A1, 0x01A5, -1, 2 },
        { 0x01A8, 0x01A8, -1, 1 },
        { 0x01AD, 0x01AD, -1, 1 },
        { 0x01B0, 0x01B0, -1, 1 },
        { 0x01B4, 0x01B6, -1, 2 },
        { 0x01B9, 0x01B9, -1, 1 },
        { 0x01BD, 0x01BD, -1, 1 },
        { 0x01BF, 0x01BF, 56, 1 },
        { 0x01C5, 0x01C5, -1, 1 },
        { 0x01C6, 0x01C6, -2, 1 },
        { 0x01C8, 0x01C8, -1, 1 },
        { 0x01C9, 0x01C9, -2, 1 },
        { 0x01CB, 0x01CB, -1, 1 },
        { 0x01CC, 0x01CC, -2, 1 },
        { 0x01CE, 0x01DC, -1, 2 },
        { 0x01DD, 0x01DD, -79, 1 },
        { 0x01DF, 0x01EF, -1, 2 },
        { 0x01F2, 0x01F2, -1, 1 },
        { 0x01F3, 0x01F3, -2, 1 },
        { 0x01F5, 0x01F5, -1, 1 },
        { 0x01F9, 0x021F, -1, 2 },
        { 0x0223, 0x0233, -1, 2 },
        { 0x0253, 0x0253, -210, 1 },
        { 0x0254, 0x0254, -206, 1 },
        { 0x0256, 0x0257, -205, 1 },
        { 0x0259, 0x0259, -202, 1 },
        { 0x025B, 0x025B, -203, 1 },
        { 0x0260, 0x0260, -205, 1 },
        { 0x0263, 0x0263, -207, 1 },
        { 0x0268, 0x0268, -209, 1 },
        { 0x0269, 0x0269, -211, 1 },
        { 0x026F, 0x026F, -211, 1 },
        { 0x0272, 0x0272, -213, 1 },
        { 0x0275, 0x0275, -214, 1 },
        { 0x0280, 0x0280, -218, 1 },
        { 0x0283, 0x0283, -218, 1 },
        { 0x0288, 0x0288, -218, 1 },
        { 0x028A, 0x028B, -217, 1 },
        { 0x0292, 0x0292, -219, 1 },
        { 0x0345, 0x0345, 84, 1 },
        { 0x03AC, 0x03AC, -38, 1 },
        { 0x03AD, 0x03AF, -37, 1 },
        { 0x03B1, 0x03C1, -32, 1 },
        { 0x03C2, 0x03C2, -31, 1 },
        { 0x03C3, 0x03CB, -32, 1 },
        { 0x03CC, 0x03CC, -64, 1 },
        { 0x03CD, 0x03CE, -63, 1 },
        { 0x03D0, 0x03D0, -62, 1 },
        { 0x03D1, 0x03D1, -57, 1 },
        { 0x03D5, 0x03D5, -47, 1 },
        { 0x03D6, 0x03D6, -54, 1 },
        { 0x03DB, 0x03EF, -1, 2 },
        { 0x03F0, 0x03F0, -86, 1 },
        { 0x03F1, 0x03F1, -80, 1 },
        { 0x03F2, 0x03F2, -79, 1 },
        { 0x0430, 0x044F, -32, 1 },
        { 0x0450, 0x045F, -80, 1 },
        { 0x0461, 0x0481, -1, 2 },
        { 0x048D, 0x04BF, -1, 2 },
        { 0x04C2, 0x04C4, -1, 2 },
        { 0x04C8, 0x04C8, -1, 1 },
        { 0x04CC, 0x04CC, -1, 1 },
        { 0x04D1, 0x04F5, -1, 2 },
        { 0x04F9, 0x04F9, -1, 1 },
        { 0x0561, 0x0586, -48, 1 },
        { 0x1E01, 0x1E95, -1, 2 },
        { 0x1E9B, 0x1E9B, -59, 1 },
        { 0x1EA1, 0x1EF9, -1, 2 },
        { 0x1F00, 0x1F07, 8, 1 },
        { 0x1F10, 0x1F15, 8, 1 },
        { 0x1F20, 0x1F27, 8, 1 },
        { 0x1F30, 0x1F37, 8, 1 },
        { 0x1F40, 0x1F45, 8, 1 },
        { 0x1F51, 0x1F57, 8, 2 },
        { 0x1F60, 0x1F67, 8, 1 },
        { 0x1F70, 0x1F71, 74, 1 },
        { 0x1F72, 0x1F75, 86, 1 },
        { 0x1F76, 0x1F77, 100, 1 },
        { 0x1F78, 0x1F79, 128, 1 },
        { 0x1F7A, 0x1F7B, 112, 1 },
        { 0x1F7C, 0x1F7D, 126, 1 },
        { 0x1F80, 0x1F87, 8, 1 },
        { 0x1F90, 0x1F97, 8, 1 },
        { 0x1FA0, 0x1FA7, 8, 1 },
        { 0x1FB0, 0x1FB1, 8, 1 },
        { 0x1FB3, 0x1FB3, 9, 1 },
        { 0x1FBE, 0x1FBE, -7205, 1 },
        { 0x1FC3, 0x1FC3, 9, 1 },
        { 0x1FD0, 0x1FD1, 8, 1 },
        { 0x1FE0, 0x1FE1, 8, 1 },
        { 0x1FE5, 0x1FE5, 7, 1 },
        { 0x1FF3, 0x1FF3, 9, 1 },
        { 0x2170, 0x217F, -16, 1 },
        { 0x24D0, 0x24E9, -26, 1 },
        { 0xFF41, 0xFF5A, -32, 1 },
    };

    inline constexpr CaseRun kLower[] = {
        { 0x0041, 0x005A, 32, 1 },
        { 0x00C0, 0x00D6, 32, 1 },
        { 0x00D8, 0x00DE, 32, 1 },
        { 0x0100, 0x012E, 1, 2 },
        { 0x0130, 0x0130, -199, 1 },
        { 0x0132, 0x0136, 1, 2 },
        { 0x0139, 0x0147, 1, 2 },
        { 0x014A, 0x0176, 1, 2 },
        { 0x0178, 0x0178, -121, 1 },
        { 0x0179, 0x017D, 1, 2 },
        { 0x0181, 0x0181, 210, 1 },
        { 0x0182, 0x0184, 1, 2 },
        { 0x0186, 0x0186, 206, 1 },
        { 0x0187, 0x0187, 1, 1 },
        { 0x0189, 0x018A, 205, 1 },
        { 0x018B, 0x018B, 1, 1 },
        { 0x018E, 0x018E, 79, 1 },
        { 0x018F, 0x018F, 202, 1 },
        { 0x0190, 0x0190, 203, 1 },
        { 0x0191, 0x0191, 1, 1 },
        { 0x0193, 0x0193, 205, 1 },
        { 0x0194, 0x0194, 207, 1 },
        { 0x0196, 0x0196, 211, 1 },
        { 0x0197, 0x0197, 209, 1 },
        { 0x0198, 0x0198, 1, 1 },
        { 0x019C, 0x019C, 211, 1 },
        { 0x019D, 0x019D, 213, 1 },
        { 0x019F, 0x019F, 214, 1 },
        { 0x01A0, 0x01A4, 1, 2 },
        { 0x01A6, 0x01A6, 218, 1 },
        { 0x01A7, 0x01A7, 1, 1 },
        { 0x01A9, 0x01A9, 218, 1 },
        { 0x01AC, 0x01AC, 1, 1 },
        { 0x01AE, 0x01AE, 218, 1 },
        { 0x01AF, 0x01AF, 1, 1 },
        { 0x01B1, 0x01B2, 217, 1 },
        { 0x01B3, 0x01B5, 1, 2 },
        { 0x01B7, 0x01B7, 219, 1 },
        { 0x01B8, 0x01B8, 1, 1 },
        { 0x01BC, 0x01BC, 1, 1 },
        { 0x01C4, 0x01C4, 2, 1 },
        { 0x01C5, 0x01C5, 1, 1 },
        { 0x01C7, 0x01C7, 2, 1 },
        { 0x01C8, 0x01C8, 1, 1 },
        { 0x01CA, 0x01CA, 2, 1 },
        { 0x01CB, 0x01DB, 1, 2 },
        { 0x01DE, 0x01EE, 1, 2 },
        { 0x01F1, 0x01F1, 2, 1 },
        { 0x01F2, 0x01F4, 1, 2 },
        { 0x01F6, 0x01F6, -97, 1 },
        { 0x01F7, 0x01F7, -56, 1 },
        { 0x01F8, 0x021E, 1, 2 },
        { 0x0222, 0x0232, 1, 2 },
        { 0x0386, 0x0386, 38, 1 },
        { 0x0388, 0x038A, 37, 1 },
        { 0x038C, 0x038C, 64, 1 },
        { 0x038E, 0x038F, 63, 1 },
        { 0x0391, 0x03A1, 32, 1 },
        { 0x03A3, 0x03AB, 32, 1 },
        { 0x03DA, 0x03EE, 1, 2 },
        { 0x0400, 0x040F, 80, 1 },
        { 0x0410, 0x042F, 32, 1 },
        { 0x0460, 0x0480, 1, 2 },
        { 0x048C, 0x04BE, 1, 2 },
        { 0x04C1, 0x04C3, 1, 2 },
        { 0x04C7, 0x04C7, 1, 1 },
        { 0x04CB, 0x04CB, 1, 1 },
        { 0x04D0, 0x04F4, 1, 2 },
        { 0x04F8, 0x04F8, 1, 1 },
        { 0x0531, 0x0556, 48, 1 },
        { 0x1E00, 0x1E94, 1, 2 },
        { 0x1EA0, 0x1EF8, 1, 2 },
        { 0x1F08, 0x1F0F, -8, 1 },
        { 0x1F18, 0x1F1D, -8, 1 },
        { 0x1F28, 0x1F2F, -8, 1 },
        { 0x1F38, 0x1F3F, -8, 1 },
        { 0x1F48, 0x1F4D, -8, 1 },
        { 0x1F59, 0x1F5F, -8, 2 },
        { 0x1F68, 0x1F6F, -8, 1 },
        { 0x1F88, 0x1F8F, -8, 1 },
        { 0x1F98, 0x1F9F, -8, 1 },
        { 0x1FA8, 0x1FAF, -8, 1 },
        { 0x1FB8, 0x1FB9, -8, 1 },
        { 0x1FBA, 0x1FBB, -74, 1 },
        { 0x1FBC, 0x1FBC, -9, 1 },
        { 0x1FC8, 0x1FCB, -86, 1 },
        { 0x1FCC, 0x1FCC, -9, 1 },
        { 0x1FD8, 0x1FD9, -8, 1 },
        { 0x1FDA, 0x1FDB, -100, 1 },
        { 0x1FE8, 0x1FE9, -8, 1 },
        { 0x1FEA, 0x1FEB, -112, 1 },
        { 0x1FEC, 0x1FEC, -7, 1 },
        { 0x1FF8, 0x1FF9, -128, 1 },
        { 0x1FFA, 0x1FFB, -126, 1 },
        { 0x1FFC, 0x1FFC, -9, 1 },
        { 0x2126, 0x2126, -7517, 1 },
        { 0x212A, 0x212A, -8383, 1 },
        { 0x212B, 0x212B, -8262, 1 },
        { 0x2160, 0x216F, 16, 1 },
        { 0x24B6, 0x24CF, 26, 1 },
        { 0xFF21, 0xFF3A, 32, 1 },
    };

    template <std::size_t N>
    constexpr char16_t mapCase(const CaseRun (&runs)[N], char16_t c) noexcept
    {
        std::size_t lo = 0, hi = N;
        while (lo < hi) {
            const std::size_t mid = (lo + hi) / 2;
            if (runs[mid].last < c)
                lo = mid + 1;
            else
                hi = mid;
        }
        if (lo == N || c < runs[lo].first || (c - runs[lo].first) % runs[lo].stride != 0)
            return c;
        return static_cast<char16_t>(c + runs[lo].delta);
    }

    template <class F>
    std::string mapUnits(std::string_view s, F f)
    {
        std::u16string u = utf8ToUtf16(s);
        for (char16_t& c : u)
            c = f(c);
        return utf16ToUtf8(u);
    }

} // namespace detail

constexpr char16_t toUpper(char16_t c) noexcept { return detail::mapCase(detail::kUpper, c); }
constexpr char16_t toLower(char16_t c) noexcept { return detail::mapCase(detail::kLower, c); }

// -[NSString length]: UTF-16 units.
inline std::size_t length(std::string_view s) { return utf8ToUtf16(s).size(); }

inline std::string uppercase(std::string_view s) { return detail::mapUnits(s, toUpper); }
inline std::string lowercase(std::string_view s) { return detail::mapUnits(s, toLower); }

// -capitalizedString: the first unit of each run of non-whitespace is upper-cased, the rest of
// the run lower-cased; whitespace (isWhitespaceOrNewline) is kept as it is.
inline std::string capitalized(std::string_view s)
{
    std::u16string u = utf8ToUtf16(s);
    bool wordStart = true;
    for (char16_t& c : u) {
        if (isWhitespaceOrNewline(c)) {
            wordStart = true;
            continue;
        }
        c = wordStart ? toUpper(c) : toLower(c);
        wordStart = false;
    }
    return utf16ToUtf8(u);
}

// -caseInsensitiveCompare: == NSOrderedSame, against an ASCII string: true exactly when <s> is
// ASCII too and equal ignoring ASCII case. (Captured: no non-ASCII unit, alone or in context,
// compares equal to any printable ASCII character, and none is ignored.) GNUstep's comparison of
// two non-ASCII strings also decomposes them, which this does not model: for a non-ASCII
// <ascii> argument only an identical <s> is equal.
inline bool equalsIgnoringCaseAscii(std::string_view s, std::string_view ascii) noexcept
{
    if (s.size() != ascii.size())
        return false;
    for (std::size_t i = 0; i < s.size(); ++i) {
        const unsigned char a = static_cast<unsigned char>(s[i]), b = static_cast<unsigned char>(ascii[i]);
        if (a >= 0x80 || b >= 0x80) {
            if (a != b)
                return false;
            continue;
        }
        const auto fold = [](unsigned char c) { return (c >= 'A' && c <= 'Z') ? c + 32 : c; };
        if (fold(a) != fold(b))
            return false;
    }
    return true;
}

// --- trimming -----------------------------------------------------------------------------

// NSStringOOExtensions' -stringByTrimmingLeading/TrailingCharactersInSet: for any unit predicate
// (the characterSet's -characterIsMember:). All-member input gives "".
template <class Pred>
std::string trimLeading(std::string_view s, Pred isMember)
{
    const std::u16string u = utf8ToUtf16(s);
    std::size_t i = 0;
    while (i < u.size() && isMember(u[i]))
        ++i;
    return utf16ToUtf8(std::u16string_view(u).substr(i));
}

template <class Pred>
std::string trimTrailing(std::string_view s, Pred isMember)
{
    const std::u16string u = utf8ToUtf16(s);
    std::size_t n = u.size();
    while (n > 0 && isMember(u[n - 1]))
        --n;
    return utf16ToUtf8(std::u16string_view(u).substr(0, n));
}

inline std::string trimLeadingWhitespaceAndNewlines(std::string_view s) { return trimLeading(s, isWhitespaceOrNewline); }
inline std::string trimTrailingWhitespaceAndNewlines(std::string_view s) { return trimTrailing(s, isWhitespaceOrNewline); }
inline std::string trimWhitespaceAndNewlines(std::string_view s)
{
    return trimTrailingWhitespaceAndNewlines(trimLeadingWhitespaceAndNewlines(s));
}

// --- hashing and UTF-16 data ----------------------------------------------------------------

// -oo_hash: djb2 with xor over the UTF-16 units, stable across platforms and versions.
inline std::uint32_t ooHash(std::string_view s)
{
    std::uint32_t hash = 5381;
    for (char16_t c : utf8ToUtf16(s))
        hash = ((hash << 5) + hash) ^ c;
    return hash;
}

// -utf16DataWithBOM: native-endian (little-endian here) UTF-16, optionally led by U+FEFF.
inline Data utf16Data(std::string_view s, bool includeByteOrderMark)
{
    std::u16string u = utf8ToUtf16(s);
    if (includeByteOrderMark)
        u.insert(u.begin(), char16_t(0xFEFF));
    return Data(u.data(), u.size() * sizeof(char16_t));
}

// --- decoding a text file -------------------------------------------------------------------

namespace detail {

    // One -stringWithCharacters: pass over native-endian units: a leading U+FEFF is dropped, a
    // leading U+FFFE is dropped and every unit after it byte-swapped.
    inline void dropUtf16ByteOrderMark(std::u16string& u)
    {
        if (u.empty())
            return;
        if (u[0] == 0xFEFF) {
            u.erase(0, 1);
        } else if (u[0] == 0xFFFE) {
            u.erase(0, 1);
            for (char16_t& c : u)
                c = static_cast<char16_t>((c << 8) | (c >> 8));
        }
    }

    // -initWithBytes:length:encoding:NSUTF8StringEncoding: strict UTF-8 (no overlong forms, no
    // encoded surrogates, nothing above U+10FFFF, no truncated sequence), else nothing.
    inline bool decodeStrictUtf8(const std::uint8_t* p, std::size_t n, std::u16string& out)
    {
        out.clear();
        out.reserve(n);
        std::size_t i = 0;
        const auto cont = [&](std::size_t k) { return i + k < n && (p[i + k] & 0xC0) == 0x80; };
        while (i < n) {
            const std::uint8_t b = p[i];
            if (b < 0x80) {
                out += static_cast<char16_t>(b);
                i += 1;
            } else if (b >= 0xC2 && b <= 0xDF && cont(1)) {
                out += static_cast<char16_t>(((b & 0x1F) << 6) | (p[i + 1] & 0x3F));
                i += 2;
            } else if (b >= 0xE0 && b <= 0xEF && cont(1) && cont(2) && !(b == 0xE0 && p[i + 1] < 0xA0)
                && !(b == 0xED && p[i + 1] >= 0xA0)) {
                out += static_cast<char16_t>(((b & 0x0F) << 12) | ((p[i + 1] & 0x3F) << 6) | (p[i + 2] & 0x3F));
                i += 3;
            } else if (b >= 0xF0 && b <= 0xF4 && cont(1) && cont(2) && cont(3) && !(b == 0xF0 && p[i + 1] < 0x90)
                && !(b == 0xF4 && p[i + 1] > 0x8F)) {
                const std::uint32_t c = ((b & 0x07u) << 18) | ((p[i + 1] & 0x3Fu) << 12) | ((p[i + 2] & 0x3Fu) << 6)
                    | (p[i + 3] & 0x3Fu);
                out += static_cast<char16_t>(0xD800 + ((c - 0x10000) >> 10));
                out += static_cast<char16_t>(0xDC00 + ((c - 0x10000) & 0x3FF));
                i += 4;
            } else {
                return false;
            }
        }
        return true;
    }

} // namespace detail

// +[NSString stringWithContentsOfUnicodeFile:] (NSStringOOExtensions) once the file's bytes are
// read: UTF-16 if the length is even and the first two bytes are either byte-order mark (the
// units after it are read little-endian whichever mark it was, as the category did), else UTF-8
// after an optional UTF-8 BOM, else ISO Latin-1 of the bytes after that BOM. GNUstep's own
// decoding is reproduced (probed on gnustep-base 1.31.1, tests/unit/oofnd/test_unicode_file.cpp):
// the UTF-16 path applies -stringWithCharacters:'s mark handling twice, the UTF-8 path drops up
// to two more leading U+FEFF. The category passed length + 3 instead of length - 3 after a UTF-8
// BOM, reading past the buffer (bead oo-3rb.62, proposed ADR-0038); this is the corrected length.
inline std::string decodeUnicodeFile(const std::uint8_t* bytes, std::size_t length)
{
    if (length >= 2 && length % 2 == 0) {
        const unsigned first = (unsigned(bytes[0]) << 8) | bytes[1];
        if (first == 0xFFFE || first == 0xFEFF) {
            std::u16string u(length / 2 - 1, u'\0');
            for (std::size_t k = 0; k < u.size(); ++k) {
                u[k] = static_cast<char16_t>(bytes[2 + 2 * k] | (bytes[3 + 2 * k] << 8));
            }
            detail::dropUtf16ByteOrderMark(u);
            detail::dropUtf16ByteOrderMark(u);
            return utf16ToUtf8(u);
        }
    }

    const std::size_t skip = (length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) ? 3 : 0;
    std::u16string u;
    if (detail::decodeStrictUtf8(bytes + skip, length - skip, u)) {
        for (int pass = 0; pass < 2 && !u.empty() && u[0] == 0xFEFF; ++pass)
            u.erase(0, 1);
        return utf16ToUtf8(u);
    }
    u.clear();
    for (std::size_t k = skip; k < length; ++k)
        u += static_cast<char16_t>(bytes[k]);
    return utf16ToUtf8(u);
}

inline std::string decodeUnicodeFile(const Data& data) { return decodeUnicodeFile(data.bytes(), data.length()); }

// --- building -------------------------------------------------------------------------------

// OOTabString(count): count tabs.
inline std::string tabString(std::size_t count) { return std::string(count, '\t'); }

// -[NSMutableString appendLine:]: the line and a "\n".
inline void appendLine(std::string& out, std::string_view line)
{
    out += line;
    out += '\n';
}

// -[NSMutableString deleteCharacterAtIndex:]: removes one UTF-16 unit. An index past the end is
// ignored here (GNUstep raised NSRangeException; oofnd does not throw).
inline void deleteUnitAt(std::string& s, std::size_t index)
{
    std::u16string u = utf8ToUtf16(s);
    if (index >= u.size())
        return;
    u.erase(index, 1);
    s = utf16ToUtf8(u);
}

// +[NSString stringWithFormat:] for formats without %@: vsnprintf into a std::string. GNUstep's
// formatter gave the same bytes for 2,102 of 2,183 captured (conversion, value) pairs, every
// conversion the game formats numbers with (test_string.cpp). Where they differ this follows C,
// deliberately (proposed ADR-0034): %s passes UTF-8 through (GNUstep decoded the bytes as
// Latin-1), %c / %lc above 0x7F, %p ("0x1234" / "(null)" in GNUstep), %hhd (GNUstep printed it
// unsigned) and %f of magnitudes from about 1e22 (GNUstep dropped trailing digits).
inline std::string vformat(const char* fmt, va_list args)
{
    va_list copy;
    va_copy(copy, args);
    char small[256];
    const int n = std::vsnprintf(small, sizeof small, fmt, copy);
    va_end(copy);
    if (n < 0)
        return std::string();
    if (static_cast<std::size_t>(n) < sizeof small)
        return std::string(small, static_cast<std::size_t>(n));
    std::string out(static_cast<std::size_t>(n), '\0');
    std::vsnprintf(out.data(), out.size() + 1, fmt, args);
    return out;
}

OO_PRINTF_FORMAT(1, 2)
inline std::string format(const char* fmt, ...)
{
    va_list args;
    va_start(args, fmt);
    std::string out = vformat(fmt, args);
    va_end(args);
    return out;
}

// --- paths ----------------------------------------------------------------------------------

namespace detail {

    constexpr bool isPathSeparator(char16_t c) noexcept { return c == u'/' || c == u'\\'; }

    // Where the last path component may start: past a "~user/" prefix (all of "~user" when it has
    // no separator) or a drive "X:" and its separator. UNC roots end in a separator, so the last
    // separator finds past them anyway.
    inline std::size_t pathRootLength(std::u16string_view u) noexcept
    {
        if (!u.empty() && u[0] == u'~') {
            std::size_t i = 1;
            while (i < u.size() && !isPathSeparator(u[i]))
                ++i;
            return i < u.size() ? i + 1 : i;
        }
        if (u.size() >= 2 && u[1] == u':' && ((u[0] >= u'A' && u[0] <= u'Z') || (u[0] >= u'a' && u[0] <= u'z'))) {
            return (u.size() >= 3 && isPathSeparator(u[2])) ? 3 : 2;
        }
        return 0;
    }

    // A unit that continues the composed character sequence before it, so that a '.' it follows
    // is not matched by -rangeOfString:@"." (non-literal search): combining and spacing marks,
    // modifier letters, variation selectors and low surrogates. Probed over the BMP.
    struct UnitRange {
        char16_t first, last;
    };

    inline constexpr UnitRange kSequenceExtenders[] = {
        { 0x02B0, 0x02C1 },
        { 0x02C6, 0x02D1 },
        { 0x02E0, 0x02E4 },
        { 0x02EC, 0x02EC },
        { 0x02EE, 0x02EE },
        { 0x0300, 0x036F },
        { 0x0374, 0x0374 },
        { 0x037A, 0x037A },
        { 0x0483, 0x0489 },
        { 0x0559, 0x0559 },
        { 0x0591, 0x05BD },
        { 0x05BF, 0x05BF },
        { 0x05C1, 0x05C2 },
        { 0x05C4, 0x05C5 },
        { 0x05C7, 0x05C7 },
        { 0x0610, 0x061A },
        { 0x0640, 0x0640 },
        { 0x064B, 0x065F },
        { 0x0670, 0x0670 },
        { 0x06D6, 0x06DC },
        { 0x06DF, 0x06E8 },
        { 0x06EA, 0x06ED },
        { 0x0711, 0x0711 },
        { 0x0730, 0x074A },
        { 0x07A6, 0x07B0 },
        { 0x07EB, 0x07F5 },
        { 0x07FA, 0x07FA },
        { 0x07FD, 0x07FD },
        { 0x0816, 0x082D },
        { 0x0859, 0x085B },
        { 0x08D3, 0x08E1 },
        { 0x08E3, 0x0903 },
        { 0x093A, 0x093C },
        { 0x093E, 0x094F },
        { 0x0951, 0x0957 },
        { 0x0962, 0x0963 },
        { 0x0971, 0x0971 },
        { 0x0981, 0x0983 },
        { 0x09BC, 0x09BC },
        { 0x09BE, 0x09C4 },
        { 0x09C7, 0x09C8 },
        { 0x09CB, 0x09CD },
        { 0x09D7, 0x09D7 },
        { 0x09E2, 0x09E3 },
        { 0x09FE, 0x09FE },
        { 0x0A01, 0x0A03 },
        { 0x0A3C, 0x0A3C },
        { 0x0A3E, 0x0A42 },
        { 0x0A47, 0x0A48 },
        { 0x0A4B, 0x0A4D },
        { 0x0A51, 0x0A51 },
        { 0x0A70, 0x0A71 },
        { 0x0A75, 0x0A75 },
        { 0x0A81, 0x0A83 },
        { 0x0ABC, 0x0ABC },
        { 0x0ABE, 0x0AC5 },
        { 0x0AC7, 0x0AC9 },
        { 0x0ACB, 0x0ACD },
        { 0x0AE2, 0x0AE3 },
        { 0x0AFA, 0x0AFF },
        { 0x0B01, 0x0B03 },
        { 0x0B3C, 0x0B3C },
        { 0x0B3E, 0x0B44 },
        { 0x0B47, 0x0B48 },
        { 0x0B4B, 0x0B4D },
        { 0x0B55, 0x0B57 },
        { 0x0B62, 0x0B63 },
        { 0x0B82, 0x0B82 },
        { 0x0BBE, 0x0BC2 },
        { 0x0BC6, 0x0BC8 },
        { 0x0BCA, 0x0BCD },
        { 0x0BD7, 0x0BD7 },
        { 0x0C00, 0x0C04 },
        { 0x0C3E, 0x0C44 },
        { 0x0C46, 0x0C48 },
        { 0x0C4A, 0x0C4D },
        { 0x0C55, 0x0C56 },
        { 0x0C62, 0x0C63 },
        { 0x0C81, 0x0C83 },
        { 0x0CBC, 0x0CBC },
        { 0x0CBE, 0x0CC4 },
        { 0x0CC6, 0x0CC8 },
        { 0x0CCA, 0x0CCD },
        { 0x0CD5, 0x0CD6 },
        { 0x0CE2, 0x0CE3 },
        { 0x0D00, 0x0D03 },
        { 0x0D3B, 0x0D3C },
        { 0x0D3E, 0x0D44 },
        { 0x0D46, 0x0D48 },
        { 0x0D4A, 0x0D4D },
        { 0x0D57, 0x0D57 },
        { 0x0D62, 0x0D63 },
        { 0x0D81, 0x0D83 },
        { 0x0DCA, 0x0DCA },
        { 0x0DCF, 0x0DD4 },
        { 0x0DD6, 0x0DD6 },
        { 0x0DD8, 0x0DDF },
        { 0x0DF2, 0x0DF3 },
        { 0x0E31, 0x0E31 },
        { 0x0E34, 0x0E3A },
        { 0x0E46, 0x0E4E },
        { 0x0EB1, 0x0EB1 },
        { 0x0EB4, 0x0EBC },
        { 0x0EC6, 0x0EC6 },
        { 0x0EC8, 0x0ECD },
        { 0x0F18, 0x0F19 },
        { 0x0F35, 0x0F35 },
        { 0x0F37, 0x0F37 },
        { 0x0F39, 0x0F39 },
        { 0x0F3E, 0x0F3F },
        { 0x0F71, 0x0F84 },
        { 0x0F86, 0x0F87 },
        { 0x0F8D, 0x0F97 },
        { 0x0F99, 0x0FBC },
        { 0x0FC6, 0x0FC6 },
        { 0x102B, 0x103E },
        { 0x1056, 0x1059 },
        { 0x105E, 0x1060 },
        { 0x1062, 0x1064 },
        { 0x1067, 0x106D },
        { 0x1071, 0x1074 },
        { 0x1082, 0x108D },
        { 0x108F, 0x108F },
        { 0x109A, 0x109D },
        { 0x10FC, 0x10FC },
        { 0x135D, 0x135F },
        { 0x1712, 0x1714 },
        { 0x1732, 0x1734 },
        { 0x1752, 0x1753 },
        { 0x1772, 0x1773 },
        { 0x17B4, 0x17D3 },
        { 0x17D7, 0x17D7 },
        { 0x17DD, 0x17DD },
        { 0x180B, 0x180D },
        { 0x1843, 0x1843 },
        { 0x1885, 0x1886 },
        { 0x18A9, 0x18A9 },
        { 0x1920, 0x192B },
        { 0x1930, 0x193B },
        { 0x1A17, 0x1A1B },
        { 0x1A55, 0x1A5E },
        { 0x1A60, 0x1A7C },
        { 0x1A7F, 0x1A7F },
        { 0x1AA7, 0x1AA7 },
        { 0x1AB0, 0x1AC0 },
        { 0x1B00, 0x1B04 },
        { 0x1B34, 0x1B44 },
        { 0x1B6B, 0x1B73 },
        { 0x1B80, 0x1B82 },
        { 0x1BA1, 0x1BAD },
        { 0x1BE6, 0x1BF3 },
        { 0x1C24, 0x1C37 },
        { 0x1C78, 0x1C7D },
        { 0x1CD0, 0x1CD2 },
        { 0x1CD4, 0x1CE8 },
        { 0x1CED, 0x1CED },
        { 0x1CF4, 0x1CF4 },
        { 0x1CF7, 0x1CF9 },
        { 0x1D2C, 0x1D6A },
        { 0x1D78, 0x1D78 },
        { 0x1D9B, 0x1DF9 },
        { 0x1DFB, 0x1DFF },
        { 0x2071, 0x2071 },
        { 0x207F, 0x207F },
        { 0x2090, 0x209C },
        { 0x20D0, 0x20F0 },
        { 0x2C7C, 0x2C7D },
        { 0x2CEF, 0x2CF1 },
        { 0x2D6F, 0x2D6F },
        { 0x2D7F, 0x2D7F },
        { 0x2DE0, 0x2DFF },
        { 0x2E2F, 0x2E2F },
        { 0x3005, 0x3005 },
        { 0x302A, 0x302F },
        { 0x3031, 0x3035 },
        { 0x303B, 0x303B },
        { 0x3099, 0x309A },
        { 0x309D, 0x309E },
        { 0x30FC, 0x30FE },
        { 0xA015, 0xA015 },
        { 0xA4F8, 0xA4FD },
        { 0xA60C, 0xA60C },
        { 0xA66F, 0xA672 },
        { 0xA674, 0xA67D },
        { 0xA67F, 0xA67F },
        { 0xA69C, 0xA69F },
        { 0xA6F0, 0xA6F1 },
        { 0xA717, 0xA71F },
        { 0xA770, 0xA770 },
        { 0xA788, 0xA788 },
        { 0xA7F8, 0xA7F9 },
        { 0xA802, 0xA802 },
        { 0xA806, 0xA806 },
        { 0xA80B, 0xA80B },
        { 0xA823, 0xA827 },
        { 0xA82C, 0xA82C },
        { 0xA880, 0xA881 },
        { 0xA8B4, 0xA8C5 },
        { 0xA8E0, 0xA8F1 },
        { 0xA8FF, 0xA8FF },
        { 0xA926, 0xA92D },
        { 0xA947, 0xA953 },
        { 0xA980, 0xA983 },
        { 0xA9B3, 0xA9C0 },
        { 0xA9CF, 0xA9CF },
        { 0xA9E5, 0xA9E6 },
        { 0xAA29, 0xAA36 },
        { 0xAA43, 0xAA43 },
        { 0xAA4C, 0xAA4D },
        { 0xAA70, 0xAA70 },
        { 0xAA7B, 0xAA7D },
        { 0xAAB0, 0xAAB0 },
        { 0xAAB2, 0xAAB4 },
        { 0xAAB7, 0xAAB8 },
        { 0xAABE, 0xAABF },
        { 0xAAC1, 0xAAC1 },
        { 0xAADD, 0xAADD },
        { 0xAAEB, 0xAAEF },
        { 0xAAF3, 0xAAF6 },
        { 0xAB5C, 0xAB5F },
        { 0xAB69, 0xAB69 },
        { 0xABE3, 0xABEA },
        { 0xABEC, 0xABED },
        { 0xDC00, 0xDFFF },
        { 0xFB1E, 0xFB1E },
        { 0xFE00, 0xFE0F },
        { 0xFE20, 0xFE2F },
        { 0xFF70, 0xFF70 },
        { 0xFF9E, 0xFF9F },
    };

    inline bool extendsSequence(char16_t c) noexcept
    {
        std::size_t lo = 0, hi = std::size(kSequenceExtenders);
        while (lo < hi) {
            const std::size_t mid = (lo + hi) / 2;
            if (kSequenceExtenders[mid].last < c)
                lo = mid + 1;
            else
                hi = mid;
        }
        return lo < std::size(kSequenceExtenders) && c >= kSequenceExtenders[lo].first;
    }

    // [start, end) of the last path component, trailing separators dropped.
    inline std::pair<std::size_t, std::size_t> lastComponentRange(std::u16string_view u) noexcept
    {
        const std::size_t root = pathRootLength(u);
        std::size_t end = u.size();
        while (end > root && isPathSeparator(u[end - 1]))
            --end;
        std::size_t start = end;
        while (start > root && !isPathSeparator(u[start - 1]))
            --start;
        return { start, end };
    }

} // namespace detail

// -pathExtension: what follows the last '.' of the last component; "" when there is none or the
// dot starts the component (".plist"). Both separators count (GNUstep on Windows). A '.' that a
// combining unit follows is part of that composed sequence and is not a dot (see above).
inline std::string pathExtension(std::string_view path)
{
    const std::u16string u = utf8ToUtf16(path);
    const auto [start, end] = detail::lastComponentRange(u);
    for (std::size_t i = end; i > start; --i) {
        if (u[i - 1] == u'.' && !(i < u.size() && detail::extendsSequence(u[i]))) {
            if (i - 1 == start)
                return std::string();
            return utf16ToUtf8(std::u16string_view(u).substr(i, end - i));
        }
    }
    return std::string();
}

// -pathHasExtension: (OOStringParsing): pathExtension compared ignoring case.
inline bool pathHasExtension(std::string_view path, std::string_view extension)
{
    return equalsIgnoringCaseAscii(pathExtension(path), extension);
}

// -pathHasExtensionInArray:.
template <class Range>
bool pathHasExtensionIn(std::string_view path, const Range& extensions)
{
    const std::string ext = pathExtension(path);
    for (const auto& e : extensions) {
        if (equalsIgnoringCaseAscii(ext, e))
            return true;
    }
    return false;
}

// -[NSMutableString replaceOccurrencesOfString:t withString:r options:0 range:<all>] (t
// non-empty): left to right, non-overlapping, case-sensitive; an occurrence that a combining unit
// follows is inside a longer composed sequence and is left alone. With Search::literal
// (NSLiteralSearch) every occurrence is replaced. No canonical equivalence: "e"
// + U+0301 does not match U+00E9 (captured). GNUstep raises NSRangeException for a <target> that
// starts with a combining unit; this does not.
enum class Search {
    composed, // options:0 - an occurrence must end on a composed-sequence boundary
    literal, // NSLiteralSearch - unit-for-unit
};

inline std::string replaceOccurrences(std::string_view s, std::string_view target, std::string_view replacement,
    Search search = Search::composed)
{
    const std::u16string u = utf8ToUtf16(s), t = utf8ToUtf16(target), r = utf8ToUtf16(replacement);
    if (t.empty() || t.size() > u.size())
        return std::string(s);
    std::u16string out;
    out.reserve(u.size());
    std::size_t i = 0;
    while (i < u.size()) {
        const std::size_t end = i + t.size();
        if (end <= u.size() && std::u16string_view(u).substr(i, t.size()) == t
            && (search == Search::literal || !(end < u.size() && detail::extendsSequence(u[end])))) {
            out += r;
            i = end;
        } else {
            out += u[i++];
        }
    }
    return utf16ToUtf8(out);
}

// -hasPrefix: / -hasSuffix:: literal UTF-16 comparison (a prefix that ends inside a composed
// sequence or a surrogate pair still matches); an empty prefix or suffix never matches.
inline bool hasPrefix(std::string_view s, std::string_view prefix)
{
    const std::u16string u = utf8ToUtf16(s), p = utf8ToUtf16(prefix);
    return !p.empty() && p.size() <= u.size() && std::u16string_view(u).substr(0, p.size()) == p;
}

inline bool hasSuffix(std::string_view s, std::string_view suffix)
{
    const std::u16string u = utf8ToUtf16(s), x = utf8ToUtf16(suffix);
    if (x.empty() || x.size() > u.size())
        return false;
    return std::u16string_view(u).substr(u.size() - x.size()) == x;
}

// --- splitting ------------------------------------------------------------------------------

// -componentsSeparatedByString: (sep non-empty): n separators give n + 1 parts, empty ones kept.
inline std::vector<std::string> split(std::string_view s, std::string_view separator)
{
    std::vector<std::string> parts;
    std::size_t from = 0;
    for (;;) {
        const std::size_t at = separator.empty() ? std::string_view::npos : s.find(separator, from);
        if (at == std::string_view::npos) {
            parts.emplace_back(s.substr(from));
            return parts;
        }
        parts.emplace_back(s.substr(from, at - from));
        from = at + separator.size();
    }
}

// ScanTokensFromString(): the maximal runs of non-whitespace (isWhitespaceOrNewline), in order.
inline std::vector<std::string> tokens(std::string_view s)
{
    const std::u16string u = utf8ToUtf16(s);
    std::vector<std::string> result;
    std::size_t i = 0;
    while (i < u.size()) {
        while (i < u.size() && isWhitespaceOrNewline(u[i]))
            ++i;
        const std::size_t start = i;
        while (i < u.size() && !isWhitespaceOrNewline(u[i]))
            ++i;
        if (i > start)
            result.push_back(utf16ToUtf8(std::u16string_view(u).substr(start, i - start)));
    }
    return result;
}

// --- path components and pointers (the Foundation sweep, proposed ADR-0043) ------------------

// -pathComponents, +pathWithComponents:, -lastPathComponent, -stringByDeletingLastPathComponent
// and -stringByAppendingPathComponent: as GNUstep 1.31.1 answers them on Windows, where '/' and
// '\' both separate. A path may start with a ROOT, kept verbatim as its first component:
//   "\\host\share\" or "//host/share/" (UNC; the share must be followed by a separator),
//   a drive "X:" (ASCII letter) and at most one separator after it ("C:", "C:/", "C:\"),
//   "~user/" / "~/" (a tilde word WITH its separator; "~user" alone is an ordinary component),
//   or else one leading separator ("/", "\"; further leading separators are skipped).
// After the root, runs of separators split components; a path that ends in a separator after
// its root gets a final "/" component. Pinned by tests/unit/oofnd/test_string_sweep.cpp, whose
// rows are GNUstep's own answers for 71 paths and 33 component lists (captured on this
// toolchain). appendingPathComponent takes ONE component (no separators in it).
namespace detail {

    enum class PathRoot { none,
        separator,
        drive,
        driveSeparator,
        tilde,
        unc };

    struct PathParts {
        PathRoot rootKind = PathRoot::none;
        std::size_t rootLength = 0;
        std::vector<std::pair<std::size_t, std::size_t>> spans; // [begin, end) of each non-root component
        bool trailingSeparator = false; // after the root, the path ends in one
    };

    constexpr bool isPathSep(char c) noexcept { return c == '/' || c == '\\'; }
    constexpr bool isAsciiLetter(char c) noexcept { return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z'); }

    inline PathParts splitPath(std::string_view p)
    {
        PathParts parts;
        const std::size_t n = p.size();
        std::size_t i = 0;
        if (n >= 2 && isPathSep(p[0]) && isPathSep(p[1])) {
            // UNC: two separators, host, separator, share, separator.
            std::size_t h = 2;
            while (h < n && !isPathSep(p[h]))
                ++h;
            if (h > 2 && h < n) {
                std::size_t s = h + 1;
                while (s < n && !isPathSep(p[s]))
                    ++s;
                if (s > h + 1 && s < n) {
                    parts.rootKind = PathRoot::unc;
                    parts.rootLength = s + 1;
                }
            }
        }
        if (parts.rootKind == PathRoot::none) {
            if (n >= 1 && isPathSep(p[0])) {
                parts.rootKind = PathRoot::separator;
                parts.rootLength = 1;
            } else if (n >= 2 && p[1] == ':' && isAsciiLetter(p[0])) {
                const bool sep = n >= 3 && isPathSep(p[2]);
                parts.rootKind = sep ? PathRoot::driveSeparator : PathRoot::drive;
                parts.rootLength = sep ? 3 : 2;
            } else if (n >= 1 && p[0] == '~') {
                std::size_t t = 1;
                while (t < n && !isPathSep(p[t]))
                    ++t;
                if (t < n) {
                    parts.rootKind = PathRoot::tilde;
                    parts.rootLength = t + 1;
                }
            }
        }
        i = parts.rootLength;
        const std::size_t restBegin = i;
        while (i < n) {
            while (i < n && isPathSep(p[i]))
                ++i;
            const std::size_t begin = i;
            while (i < n && !isPathSep(p[i]))
                ++i;
            if (i > begin)
                parts.spans.emplace_back(begin, i);
        }
        parts.trailingSeparator = n > restBegin && isPathSep(p[n - 1]);
        return parts;
    }

    // Roots that survive -stringByDeletingLastPathComponent on their own.
    constexpr bool rootStandsAlone(PathRoot k) noexcept
    {
        return k == PathRoot::separator || k == PathRoot::driveSeparator || k == PathRoot::unc;
    }

} // namespace detail

inline std::vector<std::string> pathComponents(std::string_view path)
{
    const detail::PathParts parts = detail::splitPath(path);
    std::vector<std::string> result;
    if (parts.rootLength > 0)
        result.emplace_back(path.substr(0, parts.rootLength));
    for (const auto& [begin, end] : parts.spans)
        result.emplace_back(path.substr(begin, end - begin));
    if (parts.trailingSeparator)
        result.emplace_back("/");
    return result;
}

inline std::string pathWithComponents(const std::vector<std::string>& components)
{
    if (components.empty())
        return std::string();
    if (components.size() == 1)
        return components[0].empty() ? std::string("/") : components[0];
    std::string result;
    bool separatorNext = false; // whether the next component needs a "/" before it
    for (std::size_t c = 0; c < components.size(); ++c) {
        std::string_view s = components[c];
        if (c == 0) {
            const detail::PathParts parts = detail::splitPath(s);
            if (s.find_first_not_of("/\\") == std::string_view::npos) {
                result = "/"; // "", "/", "\\": the root
                continue;
            }
            if (parts.rootKind == detail::PathRoot::drive || parts.rootKind == detail::PathRoot::driveSeparator) {
                result = std::string(s.substr(0, 2));
                if (parts.rootKind == detail::PathRoot::driveSeparator)
                    result += '/';
                s = s.substr(parts.rootLength);
            }
            while (!s.empty() && detail::isPathSep(s.back()))
                s.remove_suffix(1);
            if (!s.empty()) {
                result += s;
                separatorNext = true;
            }
            continue;
        }
        while (!s.empty() && detail::isPathSep(s.front()))
            s.remove_prefix(1);
        while (!s.empty() && detail::isPathSep(s.back()))
            s.remove_suffix(1);
        if (s.empty())
            continue;
        if (separatorNext)
            result += '/';
        result += s;
        separatorNext = true;
    }
    return result;
}

inline std::string lastPathComponent(std::string_view path)
{
    const detail::PathParts parts = detail::splitPath(path);
    if (!parts.spans.empty()) {
        const auto [begin, end] = parts.spans.back();
        return std::string(path.substr(begin, end - begin));
    }
    if (parts.rootLength > 0) {
        std::string_view root = path.substr(0, parts.rootLength);
        if (parts.rootKind == detail::PathRoot::tilde)
            root.remove_suffix(1); // "~/" -> "~"
        return std::string(root);
    }
    return std::string();
}

inline std::string deletingLastPathComponent(std::string_view path)
{
    const detail::PathParts parts = detail::splitPath(path);
    const std::string_view root = path.substr(0, parts.rootLength);
    if (parts.spans.empty()) {
        return detail::rootStandsAlone(parts.rootKind) ? std::string(root) : std::string();
    }
    if (parts.spans.size() == 1)
        return std::string(root);
    const std::size_t from = parts.spans.front().first, to = parts.spans[parts.spans.size() - 2].second;
    return std::string(root) + std::string(path.substr(from, to - from));
}

inline std::string appendingPathComponent(std::string_view path, std::string_view component)
{
    const detail::PathParts parts = detail::splitPath(path);
    if (path.empty())
        return std::string(component);
    if (parts.spans.empty()) {
        switch (parts.rootKind) {
        case detail::PathRoot::separator:
            return "/" + std::string(component);
        case detail::PathRoot::drive:
            return std::string(path.substr(0, 2)) + std::string(component);
        case detail::PathRoot::driveSeparator:
            return std::string(path.substr(0, 2)) + "/" + std::string(component);
        case detail::PathRoot::tilde:
            return std::string(path.substr(0, parts.rootLength - 1)) + "/" + std::string(component);
        case detail::PathRoot::unc:
            return std::string(path.substr(0, parts.rootLength)) + std::string(component);
        case detail::PathRoot::none:
            break;
        }
        return std::string(component);
    }
    // The path up to the end of its first component verbatim; later components joined by "/".
    std::string result(path.substr(0, parts.spans.front().second));
    for (std::size_t c = 1; c < parts.spans.size(); ++c) {
        const auto [begin, end] = parts.spans[c];
        result += '/';
        result += path.substr(begin, end - begin);
    }
    result += '/';
    result += component;
    return result;
}

// -stringByAppendingPathExtension: as GNUstep 1.31.1 answers it on Windows: trailing separators
// ('/' and '\') are dropped, then "." and the extension are appended verbatim (an empty or
// dotted extension included: "a" + "" is "a.", "a" + ".x" is "a..x"). A path that is empty or a
// bare root ("/", "\", "//", "C:", "C:/", "~") once they are dropped comes back unchanged (GNUstep
// also logged "cannot append extension"). Pinned by tests/unit/oofnd/test_string_path_extension.cpp.
inline std::string appendingPathExtension(std::string_view path, std::string_view extension)
{
    std::string_view stem = path;
    while (!stem.empty() && detail::isPathSep(stem.back()))
        stem.remove_suffix(1);
    const bool isDrive = stem.size() == 2 && stem[1] == ':' && detail::isAsciiLetter(stem[0]);
    if (stem.empty() || stem == "~" || isDrive)
        return std::string(path);
    std::string result(stem);
    result += '.';
    result += extension;
    return result;
}

// "%p" as -[NSString stringWithFormat:] prints it (GNUstep 1.31.1, 64-bit Windows): "(null)" for
// NULL, otherwise the LOW 32 BITS as %#x ("0x1234"; "0" when they are all zero). Use it as a %s
// argument where a formatted string had %p: oo::str::format("%s", oo::str::pointerDescription(p).c_str()).
inline std::string pointerDescription(const void* pointer)
{
    if (pointer == nullptr)
        return "(null)";
    const auto low = static_cast<unsigned>(reinterpret_cast<std::uintptr_t>(pointer) & 0xFFFFFFFFu);
    return format("%#x", low);
}

// --- ordering -------------------------------------------------------------------------------

// -compare: and -caseInsensitiveCompare: as orderings: < 0, 0, > 0 for NSOrderedAscending, Same,
// Descending (the Foundation sweep, proposed ADR-0043; for sorting and ordered containers).
// Both walk the UTF-16 units as NSString does; the caseInsensitive form first maps each unit
// through toLower() (GNUstep folds to LOWER case: "_" sorts before "B", captured). Exact for every
// ASCII pair (tests/unit/oofnd/test_string_compare.cpp pins digests captured from GNUstep 1.31.1).
// Not modelled: GNUstep's composed-sequence equivalence between non-ASCII strings ("e" + U+0301
// equals U+00E9 there, and orders by it); here the units decide.
inline int compare(std::string_view a, std::string_view b)
{
    const std::u16string ua = utf8ToUtf16(a), ub = utf8ToUtf16(b);
    const int c = ua.compare(ub);
    return c < 0 ? -1 : (c > 0 ? 1 : 0);
}

inline int caseInsensitiveCompare(std::string_view a, std::string_view b)
{
    std::u16string ua = utf8ToUtf16(a), ub = utf8ToUtf16(b);
    for (char16_t& u : ua)
        u = toLower(u);
    for (char16_t& u : ub)
        u = toLower(u);
    const int c = ua.compare(ub);
    return c < 0 ? -1 : (c > 0 ? 1 : 0);
}

// -[NSString localizedCompare:] as an ordering (< 0, 0, > 0; bead oo-r4d6). GNUstep hands it to ICU:
// a collator for [NSLocale currentLocale] -- ICU's default locale, en_US on the fleet machine -- at
// its default attributes, comparing the strings as ICU does (so "a" < "A" < "b", "_x" < "1.10" <
// "a", accents after the base letter, "e" + U+0301 equal to U+00E9). Pinned against a table
// captured from GNUstep 1.31.1 in tests/unit/oofnd/test_localized_compare.cpp. The <locale> form
// names the locale (the test's, so it does not depend on the machine); the two-argument form
// uses ICU's default, as GNUstep does. If ICU cannot open a collator the literal order
// (compare) decides, rather than calling everything equal.
inline int localizedCompare(std::string_view a, std::string_view b, const char* locale)
{
    struct Closer {
        void operator()(UCollator* c) const noexcept { ucol_close(c); }
    };
    // One collator per thread (a UCollator is not shared across threads), reopened only when
    // the locale changes: ucol_open is far too slow to pay per comparison in a sort.
    thread_local std::unique_ptr<UCollator, Closer> collator;
    thread_local std::string openedFor;
    thread_local bool opened = false;
    const std::string wanted = (locale != nullptr) ? locale : "";
    if (!opened || openedFor != wanted) {
        UErrorCode status = U_ZERO_ERROR;
        collator.reset(ucol_open(wanted.c_str(), &status));
        if (U_FAILURE(status))
            collator.reset();
        openedFor = wanted;
        opened = true;
    }
    if (!collator)
        return compare(a, b);
    UErrorCode status = U_ZERO_ERROR;
    const UCollationResult r = ucol_strcollUTF8(collator.get(), a.data(), static_cast<int32_t>(a.size()),
        b.data(), static_cast<int32_t>(b.size()), &status);
    if (U_FAILURE(status))
        return compare(a, b);
    return r == UCOL_LESS ? -1 : (r == UCOL_GREATER ? 1 : 0);
}

inline int localizedCompare(std::string_view a, std::string_view b)
{
    return localizedCompare(a, b, uloc_getDefault());
}

// --- numbers --------------------------------------------------------------------------------

inline int intValue(std::string_view s) { return plist_get::intValue(utf8ToUtf16(s)); }
inline long long longLongValue(std::string_view s) { return plist_get::longLongValue(utf8ToUtf16(s)); }
inline double doubleValue(std::string_view s) { return plist_get::doubleValue(utf8ToUtf16(s)); }

// --- versions (OOStringParsing) -------------------------------------------------------------

// ComponentsFromVersionString(): "1.2.3-beta 4" -> {1, 2, 3}: up to the first space, then up to
// the first '-', then each '.'-separated part's -intValue, negatives as 0.
inline std::vector<unsigned> versionComponents(std::string_view s)
{
    std::string_view head = s.substr(0, s.find(' '));
    head = head.substr(0, head.find('-'));
    std::vector<unsigned> result;
    for (const std::string& part : split(head, ".")) {
        result.push_back(static_cast<unsigned>(std::max(intValue(part), 0)));
    }
    return result;
}

// CompareVersions(): most significant first, a missing component is 0 ("1.2.3.0" == "1.2.3").
// Negative if a < b, 0 if equal, positive if a > b (NSOrderedAscending / Same / Descending).
inline int compareVersions(const std::vector<unsigned>& a, const std::vector<unsigned>& b)
{
    const std::size_t n = std::max(a.size(), b.size());
    for (std::size_t i = 0; i < n; ++i) {
        const unsigned x = i < a.size() ? a[i] : 0u, y = i < b.size() ? b[i] : 0u;
        if (x < y)
            return -1;
        if (x > y)
            return 1;
    }
    return 0;
}

// --- runtime format strings ------------------------------------------------------------------

// One argument of formatRuntime(). A format string read at run time (a DESC(...) entry, a
// verifyOXP.plist template) cannot be checked against its arguments at compile time, so each
// argument carries its kind and every conversion reads it as -stringWithFormat: would have read
// the Objective-C value the old code passed:
//   text     an object for %@ (pass its -description: oo::DescriptionOf(obj) in game code) or a
//            C string for %s;
//   null     nil for %@ / NULL for %s and %p: "(null)";
//   signed / unsigned integers, reals (single() for a +numberWithFloat: value, whose %@ text is
//            %0.7g; a double prints %0.16g), pointer() for %p.
// A %@ given a number prints the NSNumber's description ("42", "0.1"), so an NSNumber argument
// may be passed as the number itself.
class FormatArg {
public:
    enum class Kind { Null,
        Text,
        Signed,
        Unsigned,
        Real,
        Pointer };

    FormatArg() noexcept = default;
    FormatArg(std::string_view text)
        : kind_(Kind::Text)
        , text_(text)
    {
    }
    FormatArg(const std::string& text)
        : kind_(Kind::Text)
        , text_(text)
    {
    }
    FormatArg(const char* text)
        : kind_(text != nullptr ? Kind::Text : Kind::Null)
        , text_(text != nullptr ? text : "")
    {
    }
    FormatArg(int v) noexcept
        : kind_(Kind::Signed)
        , signed_(v)
    {
    }
    FormatArg(long v) noexcept
        : kind_(Kind::Signed)
        , signed_(v)
    {
    }
    FormatArg(long long v) noexcept
        : kind_(Kind::Signed)
        , signed_(v)
    {
    }
    FormatArg(unsigned v) noexcept
        : kind_(Kind::Unsigned)
        , unsigned_(v)
    {
    }
    FormatArg(unsigned long v) noexcept
        : kind_(Kind::Unsigned)
        , unsigned_(v)
    {
    }
    FormatArg(unsigned long long v) noexcept
        : kind_(Kind::Unsigned)
        , unsigned_(v)
    {
    }
    FormatArg(double v) noexcept
        : kind_(Kind::Real)
        , real_(v)
    {
    }

    static FormatArg null() noexcept { return FormatArg(); }
    static FormatArg single(float v) noexcept
    {
        FormatArg a(static_cast<double>(v));
        a.single_ = true;
        return a;
    }
    static FormatArg pointer(const void* p) noexcept
    {
        FormatArg a;
        if (p != nullptr) {
            a.kind_ = Kind::Pointer;
            a.unsigned_ = reinterpret_cast<std::uintptr_t>(p);
        }
        return a;
    }

    Kind kind() const noexcept { return kind_; }
    const std::string& text() const noexcept { return text_; }
    bool isSingle() const noexcept { return single_; }

    long long asSigned() const noexcept
    {
        switch (kind_) {
        case Kind::Signed:
            return signed_;
        case Kind::Unsigned:
        case Kind::Pointer:
            return static_cast<long long>(unsigned_);
        case Kind::Real:
            return static_cast<long long>(real_);
        default:
            return 0;
        }
    }
    unsigned long long asUnsigned() const noexcept
    {
        return kind_ == Kind::Unsigned || kind_ == Kind::Pointer ? unsigned_ : static_cast<unsigned long long>(asSigned());
    }
    double asReal() const noexcept
    {
        switch (kind_) {
        case Kind::Real:
            return real_;
        case Kind::Signed:
            return static_cast<double>(signed_);
        case Kind::Unsigned:
            return static_cast<double>(unsigned_);
        default:
            return 0.0;
        }
    }

private:
    Kind kind_ = Kind::Null;
    bool single_ = false;
    std::string text_;
    long long signed_ = 0;
    unsigned long long unsigned_ = 0;
    double real_ = 0.0;
};

namespace detail {

    // Pads or truncates `text` to a width / precision counted in UTF-16 units, as GNUstep does for %@.
    inline std::string padUnits(const std::string& text, int width, int precision, bool left, bool countUnits)
    {
        std::string body = text;
        std::size_t length = countUnits ? utf8ToUtf16(body).size() : body.size();
        if (precision >= 0 && length > static_cast<std::size_t>(precision)) {
            if (countUnits) {
                std::u16string units = utf8ToUtf16(body);
                units.resize(static_cast<std::size_t>(precision));
                body = utf16ToUtf8(units);
            } else
                body.resize(static_cast<std::size_t>(precision));
            length = static_cast<std::size_t>(precision);
        }
        if (width > 0 && length < static_cast<std::size_t>(width)) {
            const std::string pad(static_cast<std::size_t>(width) - length, ' ');
            body = left ? body + pad : pad + body;
        }
        return body;
    }

    // The text %@ prints for an argument: an object's description, or an NSNumber's.
    inline std::string objectText(const FormatArg& a)
    {
        switch (a.kind()) {
        case FormatArg::Kind::Text:
            return a.text();
        case FormatArg::Kind::Signed:
            return format("%lld", a.asSigned());
        case FormatArg::Kind::Unsigned:
            return format("%llu", a.asUnsigned());
        case FormatArg::Kind::Real:
            return a.isSingle() ? format("%0.7g", a.asReal()) : format("%0.16g", a.asReal());
        case FormatArg::Kind::Pointer:
            return pointerDescription(reinterpret_cast<const void*>(static_cast<std::uintptr_t>(a.asUnsigned())));
        default:
            return "(null)";
        }
    }

    // The printf flags and field of one conversion, applied without a runtime printf format string.
    struct FormatSpec {
        bool left = false, plus = false, space = false, alternate = false, zero = false;
        int width = -1, precision = -1;
    };

    inline std::string padNumber(std::string_view sign, std::string_view prefix, std::string digits, const FormatSpec& f, bool zeroPadAllowed)
    {
        const std::size_t length = sign.size() + prefix.size() + digits.size();
        const std::size_t width = f.width > 0 ? static_cast<std::size_t>(f.width) : 0;
        if (length >= width)
            return std::string(sign) + std::string(prefix) + digits;
        const std::string pad(width - length, f.zero && zeroPadAllowed && !f.left ? '0' : ' ');
        if (f.left)
            return std::string(sign) + std::string(prefix) + digits + pad;
        if (pad[0] == '0')
            return std::string(sign) + std::string(prefix) + pad + digits;
        return pad + std::string(sign) + std::string(prefix) + digits;
    }

    inline std::string formatInteger(unsigned long long magnitude, bool negative, bool isSigned, char conversion, const FormatSpec& f)
    {
        const int base = conversion == 'o' ? 8 : ((conversion == 'x' || conversion == 'X') ? 16 : 10);
        char buffer[32];
        const auto result = std::to_chars(buffer, buffer + sizeof buffer, magnitude, base);
        std::string digits(buffer, result.ptr);
        if (conversion == 'X')
            std::transform(digits.begin(), digits.end(), digits.begin(), [](char c) { return c >= 'a' && c <= 'f' ? static_cast<char>(c - 'a' + 'A') : c; });
        if (f.precision == 0 && magnitude == 0)
            digits.clear();
        if (f.precision > 0 && digits.size() < static_cast<std::size_t>(f.precision))
            digits.insert(0, static_cast<std::size_t>(f.precision) - digits.size(), '0');
        std::string_view prefix;
        if (f.alternate && magnitude != 0 && conversion == 'x')
            prefix = "0x";
        if (f.alternate && magnitude != 0 && conversion == 'X')
            prefix = "0X";
        if (f.alternate && conversion == 'o' && (digits.empty() || digits[0] != '0'))
            digits.insert(0, 1, '0');
        std::string_view sign;
        if (isSigned)
            sign = negative ? "-" : (f.plus ? "+" : (f.space ? " " : ""));
        return padNumber(sign, prefix, digits, f, f.precision < 0);
    }

    inline std::string formatReal(double value, char conversion, const FormatSpec& f)
    {
        const bool negative = std::signbit(value);
        const double magnitude = std::fabs(value);
        const bool upper = conversion == 'F' || conversion == 'E' || conversion == 'G';
        std::string digits;
        if (std::isnan(value))
            digits = "nan";
        else if (std::isinf(value))
            digits = "inf";
        else {
            const int precision = f.precision < 0 ? 6 : f.precision;
            const char lower = static_cast<char>(upper ? conversion - 'A' + 'a' : conversion);
            const std::chars_format format = lower == 'f' ? std::chars_format::fixed : (lower == 'e' ? std::chars_format::scientific : std::chars_format::general);
            char buffer[400];
            const auto result = std::to_chars(buffer, buffer + sizeof buffer, magnitude, format, lower == 'g' && precision == 0 ? 1 : precision);
            digits.assign(buffer, result.ptr);
            if (f.alternate && lower != 'g' && digits.find('.') == std::string::npos) {
                const std::size_t e = digits.find('e');
                digits.insert(e == std::string::npos ? digits.size() : e, 1, '.');
            }
        }
        if (upper)
            std::transform(digits.begin(), digits.end(), digits.begin(), [](char c) { return c >= 'a' && c <= 'z' ? static_cast<char>(c - 'a' + 'A') : c; });
        const std::string_view sign = negative ? "-" : (f.plus ? "+" : (f.space ? " " : ""));
        return padNumber(sign, "", digits, f, std::isfinite(value));
    }

} // namespace detail

// [NSString stringWithFormat:fmt, args...] for a format string known only at run time (GNUstep
// 1.31.1's GSFormat, captured: tests/unit/oofnd/test_string_format_runtime.cpp). Conversions:
// %@ (width and precision in UTF-16 units), %s, %p (pointerDescription, with width), %d %i %u %x
// %X %o %c with the length modifiers hh h l ll q z j t (h and hh truncate as C does), %f %F %e %E
// %g %G (no %a: no runtime string uses it; it is copied like an unknown conversion), %%, flags "-+ #0", widths and precisions including '*', and positional arguments
// ("%2$@", "%1$5d"). A conversion GNUstep does not know ("%k") and a lone '%' at the end are
// copied as they are, as GNUstep copies them; %n writes nothing. Where GNUstep reads memory that
// is not there (too few arguments, a string for %d), oofnd prints what a nil / zero argument
// prints ("(null)", "0") instead (ADR-0043 Amendment 3).
inline std::string formatRuntime(std::string_view fmt, std::span<const FormatArg> args)
{
    std::string out;
    std::size_t next = 0; // the next sequential argument
    const FormatArg missing;
    auto argAt = [&](std::size_t index) -> const FormatArg& { return index < args.size() ? args[index] : missing; };

    std::size_t i = 0;
    while (i < fmt.size()) {
        const char ch = fmt[i];
        if (ch != '%') {
            out += ch;
            ++i;
            continue;
        }
        const std::size_t start = i++;
        if (i >= fmt.size()) {
            out += '%';
            break;
        }
        if (fmt[i] == '%') {
            out += '%';
            ++i;
            continue;
        }

        // %[n$][flags][width][.precision][length]conversion
        auto readNumber = [&](std::size_t& p) -> int {
            int n = 0;
            while (p < fmt.size() && fmt[p] >= '0' && fmt[p] <= '9')
                n = n * 10 + (fmt[p++] - '0');
            return n;
        };
        std::size_t p = i;
        std::size_t position = 0; // 1-based, 0 = sequential
        {
            std::size_t q = p;
            const int n = readNumber(q);
            if (q > p && q < fmt.size() && fmt[q] == '$' && n > 0) {
                position = static_cast<std::size_t>(n);
                p = q + 1;
            }
        }
        std::string flags;
        while (p < fmt.size() && std::string_view("-+ #0").find(fmt[p]) != std::string_view::npos)
            flags += fmt[p++];
        int width = -1, precision = -1;
        bool left = flags.find('-') != std::string::npos;
        if (p < fmt.size() && fmt[p] == '*') {
            ++p;
            std::size_t q = p;
            const int n = readNumber(q);
            const std::size_t index = (q > p && q < fmt.size() && fmt[q] == '$') ? (p = q + 1, static_cast<std::size_t>(n - 1)) : next++;
            width = static_cast<int>(argAt(index).asSigned());
            if (width < 0) {
                left = true;
                width = -width;
            }
        } else if (p < fmt.size() && fmt[p] >= '0' && fmt[p] <= '9')
            width = readNumber(p);
        if (p < fmt.size() && fmt[p] == '.') {
            ++p;
            if (p < fmt.size() && fmt[p] == '*') {
                ++p;
                std::size_t q = p;
                const int n = readNumber(q);
                const std::size_t index = (q > p && q < fmt.size() && fmt[q] == '$') ? (p = q + 1, static_cast<std::size_t>(n - 1)) : next++;
                precision = static_cast<int>(argAt(index).asSigned());
                if (precision < 0)
                    precision = -1;
            } else
                precision = readNumber(p);
        }
        std::string length;
        while (p < fmt.size() && std::string_view("hlqLzjt").find(fmt[p]) != std::string_view::npos)
            length += fmt[p++];
        if (p >= fmt.size()) {
            out.append(fmt.substr(start));
            break;
        }
        const char conversion = fmt[p++];
        i = p;

        auto take = [&]() -> const FormatArg& { return position != 0 ? argAt(position - 1) : argAt(next++); };
        detail::FormatSpec spec;
        spec.left = left;
        spec.plus = flags.find('+') != std::string::npos;
        spec.space = flags.find(' ') != std::string::npos;
        spec.alternate = flags.find('#') != std::string::npos;
        spec.zero = flags.find('0') != std::string::npos;
        spec.width = width;
        spec.precision = precision;

        switch (conversion) {
        case '@':
            out += detail::padUnits(detail::objectText(take()), width, precision, left, true);
            break;
        case 's': {
            const FormatArg& a = take();
            out += detail::padUnits(a.kind() == FormatArg::Kind::Text ? a.text() : std::string("(null)"), width, precision, left, false);
            break;
        }
        case 'p': {
            const FormatArg& a = take();
            const void* ptr = reinterpret_cast<const void*>(static_cast<std::uintptr_t>(a.kind() == FormatArg::Kind::Null ? 0u : a.asUnsigned()));
            out += detail::padUnits(pointerDescription(ptr), width, -1, left, false);
            break;
        }
        case 'd':
        case 'i': {
            long long v = take().asSigned();
            if (length == "hh")
                v = static_cast<signed char>(v);
            else if (length == "h")
                v = static_cast<short>(v);
            else if (length.empty())
                v = static_cast<int>(v);
            const unsigned long long magnitude = v < 0 ? 0ull - static_cast<unsigned long long>(v) : static_cast<unsigned long long>(v);
            out += detail::formatInteger(magnitude, v < 0, true, 'd', spec);
            break;
        }
        case 'u':
        case 'x':
        case 'X':
        case 'o': {
            unsigned long long v = take().asUnsigned();
            if (length == "hh")
                v = static_cast<unsigned char>(v);
            else if (length == "h")
                v = static_cast<unsigned short>(v);
            else if (length.empty())
                v = static_cast<unsigned>(v);
            out += detail::formatInteger(v, false, false, conversion, spec);
            break;
        }
        case 'c':
            out += detail::padUnits(std::string(1, static_cast<char>(take().asSigned())), width, -1, left, false);
            break;
        case 'f':
        case 'F':
        case 'e':
        case 'E':
        case 'g':
        case 'G':
            out += detail::formatReal(take().asReal(), conversion, spec);
            break;
        case 'n':
            (void)take();
            break;
        default:
            out.append(fmt.substr(start, i - start)); // unknown: copied, as GNUstep does
            break;
        }
    }
    return out;
}

inline std::string formatRuntime(std::string_view fmt, std::initializer_list<FormatArg> args)
{
    return formatRuntime(fmt, std::span<const FormatArg>(args.begin(), args.size()));
}

inline std::string formatRuntime(std::string_view fmt)
{
    return formatRuntime(fmt, std::span<const FormatArg>());
}

} // namespace oo::str

#pragma pop_macro("false")
#pragma pop_macro("true")

#endif // OOFND_STRING_HPP
