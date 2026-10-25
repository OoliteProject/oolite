/*	oofnd/Scanner.hpp
	oo::str::CharacterSet and oo::str::Scanner: NSCharacterSet and NSScanner as Oolite uses them
	(bead oo-3rb.12, ADR-0029 Decision 5, proposed ADR-0039), over UTF-8 std::string with GNUstep base 1.31.1's
	answers: the character tables probed over the BMP, and NSScanner.m's scanning, skipping and
	failure rules. tests/unit/oofnd/test_scanner.cpp pins both against captured output.

	    Foundation                                    oo::str
	    --------------------------------------------  ----------------------------------------------
	    [NSCharacterSet whitespaceCharacterSet]       CharacterSet::whitespace()
	    ... whitespaceAndNewlineCharacterSet          CharacterSet::whitespaceAndNewline()
	    ... newlineCharacterSet                       CharacterSet::newline()
	    ... decimalDigitCharacterSet                  CharacterSet::decimalDigit()
	    ... alphanumericCharacterSet                  CharacterSet::alphanumeric()
	    [NSCharacterSet characterSetWithCharacters    CharacterSet::fromCharacters(s)
	        InString:s]
	    [set invertedSet]                             set.inverted()
	    [set characterIsMember:c]                     set.contains(c)   (c a UTF-16 unit)
	    [set longCharacterIsMember:c]  (c a UTF-16 unit)  set.contains(c)   (the same over the BMP)
	    [s stringByTrimmingCharactersInSet:set]       oo::str::trim(s, set)
	    [s rangeOfCharacterFromSet:set].location      oo::str::findFirstOf(s, set)   (npos: NSNotFound)
	    ... options:NSLiteralSearch range:{from, ...}  oo::str::findFirstOf(s, set, from)   (to the end)
	    ... options:NSBackwardsSearch                 oo::str::findLastOf(s, set)
	    [s componentsSeparatedByCharactersInSet:set]  oo::str::splitByCharacters(s, set)
	    [NSScanner scannerWithString:s]               Scanner scanner(s)
	    [sc scanInt:&i] / scanFloat: / scanDouble:    sc.scanInt(&i) / scanFloat(&f) / scanDouble(&d)
	    [sc scanString:t intoString:&r]               sc.scanString(t, &r)
	    [sc scanUpToString:t intoString:&r]           sc.scanUpToString(t, &r)
	    [sc scanCharactersFromSet:c intoString:&r]    sc.scanCharactersFromSet(c, &r)
	    [sc scanUpToCharactersFromSet:c intoString:]  sc.scanUpToCharactersFromSet(c, &r)
	    [sc ooliteScanCharactersFromSet:c ...]        sc.scanCharactersFromSetNoSkip(c, &r)
	    [sc ooliteScanUpToCharactersFromSet:c ...]    sc.scanUpToCharactersFromSetNoSkip(c, &r)
	        (NSScannerOOExtensions: no skipping)
	    [sc isAtEnd]                                  sc.isAtEnd()
	    [sc scanLocation] / setScanLocation:          sc.scanLocation() / setScanLocation(n)
	    [[sc string] substringFromIndex:              sc.remainder()
	        [sc scanLocation]]

	Locations are UTF-16 units, as NSScanner's are. Every scan first skips whitespace and newlines
	(NSScanner's default charactersToBeSkipped; Oolite never changes it) except the two NoSkip
	forms. Matching in scanString / scanUpToString is NSScanner's default: case-insensitive, and
	a match that a combining unit follows is part of a longer composed sequence (String.hpp's
	extendsSequence). Not reproduced, both absent from the game: a non-ASCII target matching
	a differently cased or decomposed non-ASCII text (GNUstep folds and decomposes both sides;
	here a non-ASCII unit matches only itself), and a target starting with a combining unit
	(GNUstep raises). The value out-parameters may be null, as in Foundation.

	Header-only, C++20, compiles with -fno-exceptions.
*/

#ifndef OOFND_SCANNER_HPP
#define OOFND_SCANNER_HPP

// Objective-C++ callers see OOCocoa.h's `#define true 1` / `#define false 0`; suspend them for
// this header (proposed ADR-0028).
#pragma push_macro("true")
#pragma push_macro("false")
#undef true
#undef false

#include "oofnd/String.hpp"

#include <algorithm>
#include <climits>
#include <cstddef>
#include <string>
#include <string_view>
#include <vector>

namespace oo::str {

namespace detail {

// +decimalDigitCharacterSet and +alphanumericCharacterSet as -characterIsMember: answers them
// for each BMP unit, GNUstep 1.31.1 (generated from the probe's sweep).
inline constexpr UnitRange kDecimalDigits[] = {
	{0x0030, 0x0039}, {0x0660, 0x0669}, {0x06F0, 0x06F9}, {0x07C0, 0x07C9}, {0x0966, 0x096F},
	{0x09E6, 0x09EF}, {0x0A66, 0x0A6F}, {0x0AE6, 0x0AEF}, {0x0B66, 0x0B6F}, {0x0BE6, 0x0BEF},
	{0x0C66, 0x0C6F}, {0x0CE6, 0x0CEF}, {0x0D66, 0x0D6F}, {0x0DE6, 0x0DEF}, {0x0E50, 0x0E59},
	{0x0ED0, 0x0ED9}, {0x0F20, 0x0F29}, {0x1040, 0x1049}, {0x1090, 0x1099}, {0x17E0, 0x17E9},
	{0x1810, 0x1819}, {0x1946, 0x194F}, {0x19D0, 0x19D9}, {0x1A80, 0x1A89}, {0x1A90, 0x1A99},
	{0x1B50, 0x1B59}, {0x1BB0, 0x1BB9}, {0x1C40, 0x1C49}, {0x1C50, 0x1C59}, {0xA620, 0xA629},
	{0xA8D0, 0xA8D9}, {0xA900, 0xA909}, {0xA9D0, 0xA9D9}, {0xA9F0, 0xA9F9}, {0xAA50, 0xAA59},
	{0xABF0, 0xABF9}, {0xFF10, 0xFF19},
};

inline constexpr UnitRange kAlphanumerics[] = {
	{0x0030, 0x0039}, {0x0041, 0x005A}, {0x0061, 0x007A}, {0x00AA, 0x00AA}, {0x00B2, 0x00B3},
	{0x00B5, 0x00B5}, {0x00B9, 0x00BA}, {0x00BC, 0x00BE}, {0x00C0, 0x00D6}, {0x00D8, 0x00F6},
	{0x00F8, 0x02C1}, {0x02C6, 0x02D1}, {0x02E0, 0x02E4}, {0x02EC, 0x02EC}, {0x02EE, 0x02EE},
	{0x0300, 0x0374}, {0x0376, 0x0377}, {0x037A, 0x037D}, {0x037F, 0x037F}, {0x0386, 0x0386},
	{0x0388, 0x038A}, {0x038C, 0x038C}, {0x038E, 0x03A1}, {0x03A3, 0x03F5}, {0x03F7, 0x0481},
	{0x0483, 0x052F}, {0x0531, 0x0556}, {0x0559, 0x0559}, {0x0560, 0x0588}, {0x0591, 0x05BD},
	{0x05BF, 0x05BF}, {0x05C1, 0x05C2}, {0x05C4, 0x05C5}, {0x05C7, 0x05C7}, {0x05D0, 0x05EA},
	{0x05EF, 0x05F2}, {0x0610, 0x061A}, {0x0620, 0x0669}, {0x066E, 0x06D3}, {0x06D5, 0x06DC},
	{0x06DF, 0x06E8}, {0x06EA, 0x06FC}, {0x06FF, 0x06FF}, {0x0710, 0x074A}, {0x074D, 0x07B1},
	{0x07C0, 0x07F5}, {0x07FA, 0x07FA}, {0x07FD, 0x07FD}, {0x0800, 0x082D}, {0x0840, 0x085B},
	{0x0860, 0x086A}, {0x08A0, 0x08B4}, {0x08B6, 0x08C7}, {0x08D3, 0x08E1}, {0x08E3, 0x0963},
	{0x0966, 0x096F}, {0x0971, 0x0983}, {0x0985, 0x098C}, {0x098F, 0x0990}, {0x0993, 0x09A8},
	{0x09AA, 0x09B0}, {0x09B2, 0x09B2}, {0x09B6, 0x09B9}, {0x09BC, 0x09C4}, {0x09C7, 0x09C8},
	{0x09CB, 0x09CE}, {0x09D7, 0x09D7}, {0x09DC, 0x09DD}, {0x09DF, 0x09E3}, {0x09E6, 0x09F1},
	{0x09F4, 0x09F9}, {0x09FC, 0x09FC}, {0x09FE, 0x09FE}, {0x0A01, 0x0A03}, {0x0A05, 0x0A0A},
	{0x0A0F, 0x0A10}, {0x0A13, 0x0A28}, {0x0A2A, 0x0A30}, {0x0A32, 0x0A33}, {0x0A35, 0x0A36},
	{0x0A38, 0x0A39}, {0x0A3C, 0x0A3C}, {0x0A3E, 0x0A42}, {0x0A47, 0x0A48}, {0x0A4B, 0x0A4D},
	{0x0A51, 0x0A51}, {0x0A59, 0x0A5C}, {0x0A5E, 0x0A5E}, {0x0A66, 0x0A75}, {0x0A81, 0x0A83},
	{0x0A85, 0x0A8D}, {0x0A8F, 0x0A91}, {0x0A93, 0x0AA8}, {0x0AAA, 0x0AB0}, {0x0AB2, 0x0AB3},
	{0x0AB5, 0x0AB9}, {0x0ABC, 0x0AC5}, {0x0AC7, 0x0AC9}, {0x0ACB, 0x0ACD}, {0x0AD0, 0x0AD0},
	{0x0AE0, 0x0AE3}, {0x0AE6, 0x0AEF}, {0x0AF9, 0x0AFF}, {0x0B01, 0x0B03}, {0x0B05, 0x0B0C},
	{0x0B0F, 0x0B10}, {0x0B13, 0x0B28}, {0x0B2A, 0x0B30}, {0x0B32, 0x0B33}, {0x0B35, 0x0B39},
	{0x0B3C, 0x0B44}, {0x0B47, 0x0B48}, {0x0B4B, 0x0B4D}, {0x0B55, 0x0B57}, {0x0B5C, 0x0B5D},
	{0x0B5F, 0x0B63}, {0x0B66, 0x0B6F}, {0x0B71, 0x0B77}, {0x0B82, 0x0B83}, {0x0B85, 0x0B8A},
	{0x0B8E, 0x0B90}, {0x0B92, 0x0B95}, {0x0B99, 0x0B9A}, {0x0B9C, 0x0B9C}, {0x0B9E, 0x0B9F},
	{0x0BA3, 0x0BA4}, {0x0BA8, 0x0BAA}, {0x0BAE, 0x0BB9}, {0x0BBE, 0x0BC2}, {0x0BC6, 0x0BC8},
	{0x0BCA, 0x0BCD}, {0x0BD0, 0x0BD0}, {0x0BD7, 0x0BD7}, {0x0BE6, 0x0BF2}, {0x0C00, 0x0C0C},
	{0x0C0E, 0x0C10}, {0x0C12, 0x0C28}, {0x0C2A, 0x0C39}, {0x0C3D, 0x0C44}, {0x0C46, 0x0C48},
	{0x0C4A, 0x0C4D}, {0x0C55, 0x0C56}, {0x0C58, 0x0C5A}, {0x0C60, 0x0C63}, {0x0C66, 0x0C6F},
	{0x0C78, 0x0C7E}, {0x0C80, 0x0C83}, {0x0C85, 0x0C8C}, {0x0C8E, 0x0C90}, {0x0C92, 0x0CA8},
	{0x0CAA, 0x0CB3}, {0x0CB5, 0x0CB9}, {0x0CBC, 0x0CC4}, {0x0CC6, 0x0CC8}, {0x0CCA, 0x0CCD},
	{0x0CD5, 0x0CD6}, {0x0CDE, 0x0CDE}, {0x0CE0, 0x0CE3}, {0x0CE6, 0x0CEF}, {0x0CF1, 0x0CF2},
	{0x0D00, 0x0D0C}, {0x0D0E, 0x0D10}, {0x0D12, 0x0D44}, {0x0D46, 0x0D48}, {0x0D4A, 0x0D4E},
	{0x0D54, 0x0D63}, {0x0D66, 0x0D78}, {0x0D7A, 0x0D7F}, {0x0D81, 0x0D83}, {0x0D85, 0x0D96},
	{0x0D9A, 0x0DB1}, {0x0DB3, 0x0DBB}, {0x0DBD, 0x0DBD}, {0x0DC0, 0x0DC6}, {0x0DCA, 0x0DCA},
	{0x0DCF, 0x0DD4}, {0x0DD6, 0x0DD6}, {0x0DD8, 0x0DDF}, {0x0DE6, 0x0DEF}, {0x0DF2, 0x0DF3},
	{0x0E01, 0x0E3A}, {0x0E40, 0x0E4E}, {0x0E50, 0x0E59}, {0x0E81, 0x0E82}, {0x0E84, 0x0E84},
	{0x0E86, 0x0E8A}, {0x0E8C, 0x0EA3}, {0x0EA5, 0x0EA5}, {0x0EA7, 0x0EBD}, {0x0EC0, 0x0EC4},
	{0x0EC6, 0x0EC6}, {0x0EC8, 0x0ECD}, {0x0ED0, 0x0ED9}, {0x0EDC, 0x0EDF}, {0x0F00, 0x0F00},
	{0x0F18, 0x0F19}, {0x0F20, 0x0F33}, {0x0F35, 0x0F35}, {0x0F37, 0x0F37}, {0x0F39, 0x0F39},
	{0x0F3E, 0x0F47}, {0x0F49, 0x0F6C}, {0x0F71, 0x0F84}, {0x0F86, 0x0F97}, {0x0F99, 0x0FBC},
	{0x0FC6, 0x0FC6}, {0x1000, 0x1049}, {0x1050, 0x109D}, {0x10A0, 0x10C5}, {0x10C7, 0x10C7},
	{0x10CD, 0x10CD}, {0x10D0, 0x10FA}, {0x10FC, 0x1248}, {0x124A, 0x124D}, {0x1250, 0x1256},
	{0x1258, 0x1258}, {0x125A, 0x125D}, {0x1260, 0x1288}, {0x128A, 0x128D}, {0x1290, 0x12B0},
	{0x12B2, 0x12B5}, {0x12B8, 0x12BE}, {0x12C0, 0x12C0}, {0x12C2, 0x12C5}, {0x12C8, 0x12D6},
	{0x12D8, 0x1310}, {0x1312, 0x1315}, {0x1318, 0x135A}, {0x135D, 0x135F}, {0x1369, 0x137C},
	{0x1380, 0x138F}, {0x13A0, 0x13F5}, {0x13F8, 0x13FD}, {0x1401, 0x166C}, {0x166F, 0x167F},
	{0x1681, 0x169A}, {0x16A0, 0x16EA}, {0x16EE, 0x16F8}, {0x1700, 0x170C}, {0x170E, 0x1714},
	{0x1720, 0x1734}, {0x1740, 0x1753}, {0x1760, 0x176C}, {0x176E, 0x1770}, {0x1772, 0x1773},
	{0x1780, 0x17D3}, {0x17D7, 0x17D7}, {0x17DC, 0x17DD}, {0x17E0, 0x17E9}, {0x17F0, 0x17F9},
	{0x180B, 0x180D}, {0x1810, 0x1819}, {0x1820, 0x1878}, {0x1880, 0x18AA}, {0x18B0, 0x18F5},
	{0x1900, 0x191E}, {0x1920, 0x192B}, {0x1930, 0x193B}, {0x1946, 0x196D}, {0x1970, 0x1974},
	{0x1980, 0x19AB}, {0x19B0, 0x19C9}, {0x19D0, 0x19DA}, {0x1A00, 0x1A1B}, {0x1A20, 0x1A5E},
	{0x1A60, 0x1A7C}, {0x1A7F, 0x1A89}, {0x1A90, 0x1A99}, {0x1AA7, 0x1AA7}, {0x1AB0, 0x1AC0},
	{0x1B00, 0x1B4B}, {0x1B50, 0x1B59}, {0x1B6B, 0x1B73}, {0x1B80, 0x1BF3}, {0x1C00, 0x1C37},
	{0x1C40, 0x1C49}, {0x1C4D, 0x1C7D}, {0x1C80, 0x1C88}, {0x1C90, 0x1CBA}, {0x1CBD, 0x1CBF},
	{0x1CD0, 0x1CD2}, {0x1CD4, 0x1CFA}, {0x1D00, 0x1DF9}, {0x1DFB, 0x1F15}, {0x1F18, 0x1F1D},
	{0x1F20, 0x1F45}, {0x1F48, 0x1F4D}, {0x1F50, 0x1F57}, {0x1F59, 0x1F59}, {0x1F5B, 0x1F5B},
	{0x1F5D, 0x1F5D}, {0x1F5F, 0x1F7D}, {0x1F80, 0x1FB4}, {0x1FB6, 0x1FBC}, {0x1FBE, 0x1FBE},
	{0x1FC2, 0x1FC4}, {0x1FC6, 0x1FCC}, {0x1FD0, 0x1FD3}, {0x1FD6, 0x1FDB}, {0x1FE0, 0x1FEC},
	{0x1FF2, 0x1FF4}, {0x1FF6, 0x1FFC}, {0x2070, 0x2071}, {0x2074, 0x2079}, {0x207F, 0x2089},
	{0x2090, 0x209C}, {0x20D0, 0x20F0}, {0x2102, 0x2102}, {0x2107, 0x2107}, {0x210A, 0x2113},
	{0x2115, 0x2115}, {0x2119, 0x211D}, {0x2124, 0x2124}, {0x2126, 0x2126}, {0x2128, 0x2128},
	{0x212A, 0x212D}, {0x212F, 0x2139}, {0x213C, 0x213F}, {0x2145, 0x2149}, {0x214E, 0x214E},
	{0x2150, 0x2189}, {0x2460, 0x249B}, {0x24EA, 0x24FF}, {0x2776, 0x2793}, {0x2C00, 0x2C2E},
	{0x2C30, 0x2C5E}, {0x2C60, 0x2CE4}, {0x2CEB, 0x2CF3}, {0x2CFD, 0x2CFD}, {0x2D00, 0x2D25},
	{0x2D27, 0x2D27}, {0x2D2D, 0x2D2D}, {0x2D30, 0x2D67}, {0x2D6F, 0x2D6F}, {0x2D7F, 0x2D96},
	{0x2DA0, 0x2DA6}, {0x2DA8, 0x2DAE}, {0x2DB0, 0x2DB6}, {0x2DB8, 0x2DBE}, {0x2DC0, 0x2DC6},
	{0x2DC8, 0x2DCE}, {0x2DD0, 0x2DD6}, {0x2DD8, 0x2DDE}, {0x2DE0, 0x2DFF}, {0x2E2F, 0x2E2F},
	{0x3005, 0x3007}, {0x3021, 0x302F}, {0x3031, 0x3035}, {0x3038, 0x303C}, {0x3041, 0x3096},
	{0x3099, 0x309A}, {0x309D, 0x309F}, {0x30A1, 0x30FA}, {0x30FC, 0x30FF}, {0x3105, 0x312F},
	{0x3131, 0x318E}, {0x3192, 0x3195}, {0x31A0, 0x31BF}, {0x31F0, 0x31FF}, {0x3220, 0x3229},
	{0x3248, 0x324F}, {0x3251, 0x325F}, {0x3280, 0x3289}, {0x32B1, 0x32BF}, {0x3400, 0x4DBE},
	{0x4E00, 0x9FFB}, {0xA000, 0xA48C}, {0xA4D0, 0xA4FD}, {0xA500, 0xA60C}, {0xA610, 0xA62B},
	{0xA640, 0xA672}, {0xA674, 0xA67D}, {0xA67F, 0xA6F1}, {0xA717, 0xA71F}, {0xA722, 0xA788},
	{0xA78B, 0xA7BF}, {0xA7C2, 0xA7CA}, {0xA7F5, 0xA827}, {0xA82C, 0xA82C}, {0xA830, 0xA835},
	{0xA840, 0xA873}, {0xA880, 0xA8C5}, {0xA8D0, 0xA8D9}, {0xA8E0, 0xA8F7}, {0xA8FB, 0xA8FB},
	{0xA8FD, 0xA92D}, {0xA930, 0xA953}, {0xA960, 0xA97C}, {0xA980, 0xA9C0}, {0xA9CF, 0xA9D9},
	{0xA9E0, 0xA9FE}, {0xAA00, 0xAA36}, {0xAA40, 0xAA4D}, {0xAA50, 0xAA59}, {0xAA60, 0xAA76},
	{0xAA7A, 0xAAC2}, {0xAADB, 0xAADD}, {0xAAE0, 0xAAEF}, {0xAAF2, 0xAAF6}, {0xAB01, 0xAB06},
	{0xAB09, 0xAB0E}, {0xAB11, 0xAB16}, {0xAB20, 0xAB26}, {0xAB28, 0xAB2E}, {0xAB30, 0xAB5A},
	{0xAB5C, 0xAB69}, {0xAB70, 0xABEA}, {0xABEC, 0xABED}, {0xABF0, 0xABF9}, {0xAC00, 0xD7A2},
	{0xD7B0, 0xD7C6}, {0xD7CB, 0xD7FB}, {0xF900, 0xFA6D}, {0xFA70, 0xFAD9}, {0xFB00, 0xFB06},
	{0xFB13, 0xFB17}, {0xFB1D, 0xFB28}, {0xFB2A, 0xFB36}, {0xFB38, 0xFB3C}, {0xFB3E, 0xFB3E},
	{0xFB40, 0xFB41}, {0xFB43, 0xFB44}, {0xFB46, 0xFBB1}, {0xFBD3, 0xFD3D}, {0xFD50, 0xFD8F},
	{0xFD92, 0xFDC7}, {0xFDF0, 0xFDFB}, {0xFE00, 0xFE0F}, {0xFE20, 0xFE2F}, {0xFE70, 0xFE74},
	{0xFE76, 0xFEFC}, {0xFF10, 0xFF19}, {0xFF21, 0xFF3A}, {0xFF41, 0xFF5A}, {0xFF66, 0xFFBE},
	{0xFFC2, 0xFFC7}, {0xFFCA, 0xFFCF}, {0xFFD2, 0xFFD7}, {0xFFDA, 0xFFDC},
};

template <std::size_t N>
constexpr bool inRanges(const UnitRange (&ranges)[N], char16_t c) noexcept
{
	std::size_t lo = 0, hi = N;
	while (lo < hi)
	{
		const std::size_t mid = (lo + hi) / 2;
		if (ranges[mid].last < c) lo = mid + 1;
		else hi = mid;
	}
	return lo < N && c >= ranges[lo].first;
}

// NSCaseInsensitiveSearch, unit against unit: equal once both are lower-cased by GNUstep's table,
// so U+0130 matches 'i' and U+212A KELVIN SIGN matches 'k' (probed: no other non-ASCII unit
// matches an ASCII character). GNUstep folds those two only for the first unit of the target.
constexpr bool unitsMatchIgnoringCase(char16_t text, char16_t target, bool first) noexcept
{
	if (text == target) return true;
	if (!first && (text == 0x0130 || text == 0x212A)) return false;
	return toLower(text) == toLower(target);
}

} // namespace detail

class CharacterSet
{
public:
	// +whitespaceCharacterSet: tab, space and the Unicode spaces, U+2028/U+2029 but no newlines.
	static CharacterSet whitespace() noexcept { return CharacterSet(Kind::whitespace); }
	// +whitespaceAndNewlineCharacterSet: what NSScanner skips (String.hpp's isWhitespaceOrNewline).
	static CharacterSet whitespaceAndNewline() noexcept { return CharacterSet(Kind::whitespaceAndNewline); }
	// +newlineCharacterSet: U+000A-U+000D and U+0085.
	static CharacterSet newline() noexcept { return CharacterSet(Kind::newline); }
	static CharacterSet decimalDigit() noexcept { return CharacterSet(Kind::decimalDigit); }
	static CharacterSet alphanumeric() noexcept { return CharacterSet(Kind::alphanumeric); }

	// +characterSetWithCharactersInString:: the string's units. A surrogate pair adds a
	// supplementary character, which no single unit is a member of; a lone surrogate is a member.
	static CharacterSet fromCharacters(std::string_view characters)
	{
		CharacterSet set(Kind::custom);
		const std::u16string u = utf8ToUtf16(characters);
		for (std::size_t i = 0; i < u.size(); ++i)
		{
			if (u[i] >= 0xD800 && u[i] <= 0xDBFF && i + 1 < u.size() && u[i + 1] >= 0xDC00 && u[i + 1] <= 0xDFFF)
			{
				++i;
				continue;
			}
			set.custom_ += u[i];
		}
		std::sort(set.custom_.begin(), set.custom_.end());
		return set;
	}

	// -invertedSet.
	CharacterSet inverted() const
	{
		CharacterSet set(*this);
		set.inverted_ = !inverted_;
		return set;
	}

	// -characterIsMember:.
	bool contains(char16_t c) const noexcept { return member(c) != inverted_; }

private:
	enum class Kind
	{
		whitespace,
		whitespaceAndNewline,
		newline,
		decimalDigit,
		alphanumeric,
		custom,
	};

	explicit CharacterSet(Kind kind) noexcept : kind_(kind) {}

	bool member(char16_t c) const noexcept
	{
		switch (kind_)
		{
			case Kind::whitespace:
				return c == 0x09 || c == 0x20 || c == 0xA0 || c == 0x1680 || (c >= 0x2000 && c <= 0x200B) || c == 0x2028
					   || c == 0x2029 || c == 0x202F || c == 0x205F || c == 0x3000;
			case Kind::whitespaceAndNewline:
				return isWhitespaceOrNewline(c);
			case Kind::newline:
				return (c >= 0x0A && c <= 0x0D) || c == 0x85;
			case Kind::decimalDigit:
				return detail::inRanges(detail::kDecimalDigits, c);
			case Kind::alphanumeric:
				return detail::inRanges(detail::kAlphanumerics, c);
			case Kind::custom:
				return std::binary_search(custom_.begin(), custom_.end(), c);
		}
		return false;
	}

	Kind kind_;
	bool inverted_ = false;
	std::u16string custom_;
};

// -stringByTrimmingCharactersInSet:: members removed from both ends.
inline std::string trim(std::string_view s, const CharacterSet& set)
{
	return trimTrailing(trimLeading(s, [&](char16_t c) { return set.contains(c); }), [&](char16_t c) { return set.contains(c); });
}

// -rangeOfCharacterFromSet:(.location): the UTF-16 index of the first member, npos if none.
inline std::size_t findFirstOf(std::string_view s, const CharacterSet& set)
{
	const std::u16string u = utf8ToUtf16(s);
	for (std::size_t i = 0; i < u.size(); ++i)
	{
		if (set.contains(u[i])) return i;
	}
	return std::string_view::npos;
}

// -rangeOfCharacterFromSet:options:NSLiteralSearch range:NSMakeRange(from, length - from)
// (.location): the UTF-16 index of the first member at or after <from>, npos if none. GNUstep
// searches unit by unit here as in the unranged form (bead oo-3rb.67, probed with a throwaway
// harness over quotes, newlines, backslashes, a combining mark and a surrogate pair).
inline std::size_t findFirstOf(std::string_view s, const CharacterSet& set, std::size_t from)
{
	const std::u16string u = utf8ToUtf16(s);
	for (std::size_t i = from; i < u.size(); ++i)
	{
		if (set.contains(u[i])) return i;
	}
	return std::string_view::npos;
}

// -rangeOfCharacterFromSet:options:NSBackwardsSearch: the index of the last member, npos if none.
inline std::size_t findLastOf(std::string_view s, const CharacterSet& set)
{
	const std::u16string u = utf8ToUtf16(s);
	for (std::size_t i = u.size(); i > 0; --i)
	{
		if (set.contains(u[i - 1])) return i - 1;
	}
	return std::string_view::npos;
}

// -componentsSeparatedByCharactersInSet:: every member separates; empty parts are kept.
inline std::vector<std::string> splitByCharacters(std::string_view s, const CharacterSet& set)
{
	const std::u16string u = utf8ToUtf16(s);
	std::vector<std::string> parts;
	std::size_t from = 0;
	for (std::size_t i = 0; i < u.size(); ++i)
	{
		if (set.contains(u[i]))
		{
			parts.push_back(utf16ToUtf8(std::u16string_view(u).substr(from, i - from)));
			from = i + 1;
		}
	}
	parts.push_back(utf16ToUtf8(std::u16string_view(u).substr(from)));
	return parts;
}

class Scanner
{
public:
	explicit Scanner(std::string_view string) : units_(utf8ToUtf16(string)) {}

	// -scanLocation / -setScanLocation: in UTF-16 units. A location past the end is clamped
	// (GNUstep raised NSRangeException).
	std::size_t scanLocation() const noexcept { return location_; }
	void setScanLocation(std::size_t location) noexcept { location_ = std::min(location, units_.size()); }

	// [[scanner string] substringFromIndex:[scanner scanLocation]].
	std::string remainder() const { return utf16ToUtf8(std::u16string_view(units_).substr(location_)); }

	// -isAtEnd: nothing but skippable characters left. Does not move the location.
	bool isAtEnd() const noexcept
	{
		std::size_t loc = location_;
		return !skip(loc);
	}

	// -scanInt:: an optional sign, then decimal digits. Out of range saturates to INT_MIN /
	// INT_MAX (GNUstep flags overflow once the magnitude reaches UINT_MAX / 10, and keeps
	// consuming digits). Without a digit it fails with the location unchanged.
	bool scanInt(int* value) noexcept
	{
		std::size_t loc = location_;
		if (!skip(loc)) return false;
		bool negative = false;
		if (units_[loc] == u'+') ++loc;
		else if (units_[loc] == u'-')
		{
			negative = true;
			++loc;
		}
		constexpr unsigned limit = UINT_MAX / 10;
		unsigned num = 0;
		bool overflow = false, digits = false;
		for (; loc < units_.size() && units_[loc] >= u'0' && units_[loc] <= u'9'; ++loc)
		{
			if (!overflow)
			{
				if (num >= limit) overflow = true;
				else num = num * 10 + unsigned(units_[loc] - u'0');
			}
			digits = true;
		}
		if (!digits) return false;
		if (value != nullptr)
		{
			if (overflow || num > (negative ? unsigned(INT_MAX) + 1u : unsigned(INT_MAX))) *value = negative ? INT_MIN : INT_MAX;
			else *value = negative ? static_cast<int>(0u - num) : static_cast<int>(num);
		}
		location_ = loc;
		return true;
	}

	// -scanDouble: (PListGet.hpp's statement-for-statement port of NSScanner.m). Without a
	// mantissa digit, or with an exponent out of range, it fails with the location unchanged.
	bool scanDouble(double* value) noexcept
	{
		std::size_t loc = location_;
		if (!plist_get::scanDoubleAt(units_, loc, value)) return false;
		location_ = loc;
		return true;
	}

	// -scanFloat:: scanDouble, then the double narrowed to float.
	bool scanFloat(float* value) noexcept
	{
		double d = 0.0;
		if (!scanDouble(&d)) return false;
		if (value != nullptr) *value = static_cast<float>(d);
		return true;
	}

	// -scanString:intoString:: the target, ignoring ASCII case, right after the skipped
	// characters; <into> receives the text as the string has it. When nothing is left after
	// skipping it fails with the location past the skipped characters (GNUstep does not restore
	// it there); any other failure leaves the location unchanged.
	bool scanString(std::string_view target, std::string* into = nullptr)
	{
		const std::u16string t = utf8ToUtf16(target);
		std::size_t loc = location_;
		if (!skip(loc))
		{
			location_ = loc;
			return false;
		}
		if (t.empty() || loc + t.size() > units_.size())
		{
			location_ = loc;
			return false;
		}
		if (!matchesAt(loc, t)) return false;
		if (into != nullptr) *into = utf16ToUtf8(std::u16string_view(units_).substr(loc, t.size()));
		location_ = loc + t.size();
		return true;
	}

	// -scanUpToString:intoString:: everything up to the first occurrence of the target (ignoring
	// ASCII case), or to the end. Fails when that is nothing; the location as for scanString.
	bool scanUpToString(std::string_view target, std::string* into = nullptr)
	{
		const std::u16string t = utf8ToUtf16(target);
		std::size_t loc = location_;
		if (!skip(loc))
		{
			location_ = loc;
			return false;
		}
		// Starting inside a composed sequence (a unit that extends one, not at the start of the
		// string), GNUstep cannot match at the first unit after that sequence's remaining units.
		std::size_t blind = units_.size();
		if (loc > 0 && detail::extendsSequence(units_[loc]))
		{
			blind = loc;
			while (blind < units_.size() && detail::extendsSequence(units_[blind])) ++blind;
		}
		std::size_t end = units_.size();
		if (!t.empty())
		{
			for (std::size_t at = loc; at + t.size() <= units_.size(); ++at)
			{
				if (at != blind && matchesAt(at, t))
				{
					end = at;
					break;
				}
			}
		}
		if (end == loc) return false;
		if (into != nullptr) *into = utf16ToUtf8(std::u16string_view(units_).substr(loc, end - loc));
		location_ = end;
		return true;
	}

	// -scanCharactersFromSet:intoString: / -scanUpToCharactersFromSet:intoString:: after
	// skipping, the longest run of members (non-members). Fails, location unchanged, when empty.
	bool scanCharactersFromSet(const CharacterSet& set, std::string* into = nullptr) { return scanRun(set, true, true, into); }
	bool scanUpToCharactersFromSet(const CharacterSet& set, std::string* into = nullptr) { return scanRun(set, false, true, into); }

	// NSScannerOOExtensions' -ooliteScanCharactersFromSet: / -ooliteScanUpToCharactersFromSet::
	// the same run with no skipping.
	bool scanCharactersFromSetNoSkip(const CharacterSet& set, std::string* into = nullptr) { return scanRun(set, true, false, into); }
	bool scanUpToCharactersFromSetNoSkip(const CharacterSet& set, std::string* into = nullptr) { return scanRun(set, false, false, into); }

private:
	// skipToNextField(): past whitespace and newlines; false if that reaches the end.
	bool skip(std::size_t& loc) const noexcept
	{
		while (loc < units_.size() && isWhitespaceOrNewline(units_[loc])) ++loc;
		return loc < units_.size();
	}

	// The target at <at>, not followed by a unit that extends the sequence (checked past the end
	// of the range scanString searches, too).
	bool matchesAt(std::size_t at, const std::u16string& t) const noexcept
	{
		for (std::size_t k = 0; k < t.size(); ++k)
		{
			if (!detail::unitsMatchIgnoringCase(units_[at + k], t[k], k == 0)) return false;
		}
		const std::size_t end = at + t.size();
		return !(end < units_.size() && detail::extendsSequence(units_[end]));
	}

	bool scanRun(const CharacterSet& set, bool members, bool skipFirst, std::string* into)
	{
		std::size_t loc = location_;
		if (skipFirst && !skip(loc))
		{
			if (!members) location_ = loc;   // GNUstep restores it for scanCharactersFromSet: only
			return false;
		}
		const std::size_t start = loc;
		while (loc < units_.size() && set.contains(units_[loc]) == members) ++loc;
		if (loc == start) return false;
		if (into != nullptr) *into = utf16ToUtf8(std::u16string_view(units_).substr(start, loc - start));
		location_ = loc;
		return true;
	}

	std::u16string units_;
	std::size_t location_ = 0;
};

} // namespace oo::str

#pragma pop_macro("false")
#pragma pop_macro("true")

#endif // OOFND_SCANNER_HPP
