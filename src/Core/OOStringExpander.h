/*

OOStringExpander.h

Functions for expanding escape codes and key references in strings.


Oolite
Copyright (C) 2004-2013 Giles C Williams and contributors

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the impllied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
MA 02110-1301, USA.

*/

#pragma once

#include "OOFoundation.h"
#include "OOMaths.h"

// Option flags for OOExpandDescriptionString().
enum {
    kOOExpandForJavaScript = 0x00000001, ///< Report warnings through JavaScript runtime system instead of normal logging.
    kOOExpandBackslashN = 0x00000002, ///< Convert literal "\\n"s to line breaks (used for missiontext.plist for historical reasons).
    kOOExpandGoodRNG = 0x00000004, ///< Use RANDROT for selecting from description arrays and for %N expansion.
    kOOExpandReseedRNG = 0x00000008, ///< Set "really random" seeds while expanding.
    kOOExpandKey = 0x00000010, ///< Treat string as a key. Expand(@"foo", kOOExpandKey) == Expand(@"[foo]", kOOExpandNoOptions).
    kOOExpandDisallowPercentI = 0x00000020, ///< Disallow %I expansion (used when expanding %I itself).

    kOOExpandNoOptions = 0
};
typedef NSUInteger OOExpandOptions;

/*
        OOExpandDescriptionString(string, seed, overrides, locals, systemName, recurse, options)

        Apply the following transformations to a string:
          * [commander_name] is replaced with the player character's name.
          * [commander_shipname] is replaced with the player ship's name.
          * [commander_shipdisplayname] is replaced with the player ship's display
            name.
          * [commander_rank] is replaced with the descriptive name of the player's
            kill rank.
          * [commander_legal_status] is replaced with the descriptive name for the
            player's bounty ("Clean" etc)
          * [commander_bounty] is replaced with the player's numerical bounty.
          * [credits_number] is replaced with the player's formatted credit balance.
          * [_oo_legacy_credits_number] is replaced with the player's credit balance
            in simple #.0 format (this is substituted for [credits_number] by the
                legacy script engine).
          * [N], where N is an integer, is looked up in system_description in
            descriptions.plist. This is an array of arrays of five strings each.
            Each [N] lookup selects entry N of the outer array, then selects a
            string from the Nth inner array at pseudo-random. The result is then
            expanded recursively.
          * [key], where key is any string not specified above, is handled as
            follows:
              - If it is found in <overrides>, use the corresponding value.
              - Otherwise, look it up in descriptions.plist. If a string or number
                is found, use that; if an array is found, select an item from it
                at random.
              - Otherwise, if it is a mission variable name (prefixed with
                mission_), use the value of the mission variable.
                  - Otherwise, if it is found in <legacyLocals>, use the corresponding
                        value.
                  - Otherwise, if it is a whitelisted legacy script property, look it
                    up and insert the value.
                  The resulting string is then recursively expanded.
          * %H is replaced with <planetName>. If systemName is nil, a planet name
                is retrieved through -[Universe getSystemName:], treating <seed> as a
            system seed.
          * %I is equivalent to "%H[planetname-derivative-suffix]".
          * %N is replaced with a random "alien" name using the planet name
            digraphs. If used more than once in the same string, it will produce
            the same name on each occurence.
          * %R is like %N but, due to a bug, misses some possibilities. Deprecated.
          * %JNNN, where NNN is a three-digit integer, is replaced with the name
            of system ID NNN in the current galaxy.
          * %GNNNNNN, where NNNNNN is a six-digit integer, is replaced with the
            name of system ID NNN (first triplet) in the specified galaxy
            (second triplet).
          * %% is replaced with %.
          * %[ is replaced with [.
          * %] is replaced with ].

        Syntax errors and, in non-Deployment builds, warnings may be generated. If
        <options & kOOExpandForJavaScript>, warnings are sent through
        OOJSReportWarning, otherwise they are logged.

        If <options & kOOExpandBackslashN>, literal \n in strings (i.e., "\\n") are
        converted to line breaks. This is used for expanding missiontext.plist
        entries, which may have literal \n especially in XML format.
*/
#ifdef __cplusplus
#include "oofnd/PList.hpp"
#include "oofnd/StdLib.hpp"

// C++ form (bead oo-3il6, chunk oo-3rb.145): overrides and legacyLocals are dictionaries of
// mixed values (oo::PList with Object nodes; null: none); nullopt where the string expanded to
// nothing. Game code calls this or the cxx_OOExpand* macros below.
std::optional<std::string> cxx_OOExpandDescriptionString(Random_Seed seed, const std::string& string, const oo::PList& overrides, const oo::PList& legacyLocals, const std::optional<std::string>& systemName, OOExpandOptions options);
#endif

/*
        OOGenerateSystemDescription(seed, name)

        Generates the default system description for the specified system seed.
        Equivalent to OOExpand(@"[system-description-string]"), except that it
        uses a special PRNG setting to tie the description to the seed.

        NOTE: this does not apply planetinfo overrides. To get the actual system
        description, use [UNIVERSE generateSystemData:].
*/
#ifdef __cplusplus
std::optional<std::string> cxx_OOGenerateSystemDescription(Random_Seed seed, const std::optional<std::string>& name);
#endif

// Equivalent to [[UNIVERSE systemManager] getRandomSeedForCurrentSystem], without pulling in Universe.h.
#ifdef __cplusplus
extern "C" {
#endif
Random_Seed OOStringExpanderDefaultRandomSeed(void);
#ifdef __cplusplus
}
#endif

/*
        Evil macro magic.

        OOEXPAND_ARGUMENT_COUNT returns the number of elements in a __VA_ARGS__
        list. Trivially modified from code by Laurent Deniau and
        "arpad.goret...@gmail.com" (full name not available). Source:
        https://groups.google.com/forum/?fromgroups=#!topic/comp.std.c/d-6Mj5Lko_s

        This version relies on the GCC/Clang ##__VA_ARGS__ extension to handle
        zero-length lists. It supports up to 62 arguments.

        OOEXPAND_MAP applies a unary macro or function to each element of a
        parameter or initializer list. For example, "OOEXPAND_MAP(foo, 1, 2, 3)"
        is equivalent to "foo(1), foo(2), foo(3)".
*/

#define OOEXPAND_ARGUMENT_COUNT(...) \
    OOEXPAND_ARGUMENT_COUNT_INNER(_0, ##__VA_ARGS__, OOEXPAND_ARGUMENT_COUNT_63_VALUES())
#define OOEXPAND_ARGUMENT_COUNT_INNER(...) \
    OOEXPAND_ARGUMENT_COUNT_EXTRACT_64TH_ARG(__VA_ARGS__)
#define OOEXPAND_ARGUMENT_COUNT_EXTRACT_64TH_ARG(     \
    _1, _2, _3, _4, _5, _6, _7, _8, _9, _10,          \
    _11, _12, _13, _14, _15, _16, _17, _18, _19, _20, \
    _21, _22, _23, _24, _25, _26, _27, _28, _29, _30, \
    _31, _32, _33, _34, _35, _36, _37, _38, _39, _40, \
    _41, _42, _43, _44, _45, _46, _47, _48, _49, _50, \
    _51, _52, _53, _54, _55, _56, _57, _58, _59, _60, \
    _61, _62, _63, N, ...) N
#define OOEXPAND_ARGUMENT_COUNT_63_VALUES()     \
    62, 61, 60,                                 \
        59, 58, 57, 56, 55, 54, 53, 52, 51, 50, \
        49, 48, 47, 46, 45, 44, 43, 42, 41, 40, \
        39, 38, 37, 36, 35, 34, 33, 32, 31, 30, \
        29, 28, 27, 26, 25, 24, 23, 22, 21, 20, \
        19, 18, 17, 16, 15, 14, 13, 12, 11, 10, \
        9, 8, 7, 6, 5, 4, 3, 2, 1, 0

#define OOEXPAND_MAP(F, ...) \
    OOEXPAND_MAP_INNER(F, OOEXPAND_ARGUMENT_COUNT(__VA_ARGS__), __VA_ARGS__)
#define OOEXPAND_MAP_INNER(F, COUNTEXPR, ...) \
    OOEXPAND_MAP_INNER2(F, COUNTEXPR, __VA_ARGS__)
#define OOEXPAND_MAP_INNER2(F, COUNT, ...) \
    OOEXPAND_MAP_INNER3(F, OOEXPAND_MAP_IMPL_##COUNT, __VA_ARGS__)
#define OOEXPAND_MAP_INNER3(F, IMPL, ...) \
    IMPL(F, __VA_ARGS__)

#define OOEXPAND_MAP_IMPL_0(F, HEAD)
#define OOEXPAND_MAP_IMPL_1(F, HEAD) F(HEAD)
#define OOEXPAND_MAP_IMPL_2(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_1(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_3(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_2(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_4(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_3(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_5(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_4(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_6(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_5(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_7(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_6(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_8(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_7(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_9(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_8(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_10(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_9(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_11(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_10(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_12(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_11(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_13(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_12(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_14(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_13(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_15(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_14(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_16(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_15(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_17(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_16(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_18(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_17(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_19(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_18(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_20(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_19(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_21(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_20(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_22(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_21(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_23(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_22(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_24(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_23(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_25(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_24(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_26(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_25(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_27(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_26(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_28(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_27(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_29(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_28(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_30(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_29(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_31(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_30(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_32(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_31(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_33(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_32(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_34(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_33(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_35(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_34(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_36(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_35(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_37(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_36(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_38(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_37(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_39(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_38(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_40(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_39(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_41(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_40(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_42(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_41(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_43(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_42(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_44(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_43(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_45(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_44(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_46(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_45(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_47(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_46(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_48(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_47(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_49(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_48(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_50(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_49(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_51(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_50(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_52(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_51(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_53(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_52(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_54(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_53(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_55(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_54(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_56(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_55(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_57(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_56(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_58(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_57(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_59(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_58(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_60(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_59(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_61(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_60(F, __VA_ARGS__)
#define OOEXPAND_MAP_IMPL_62(F, HEAD, ...) F(HEAD), OOEXPAND_MAP_IMPL_61(F, __VA_ARGS__)

#ifdef __cplusplus
/*
        C++ forms of the OOExpand* macros (bead oo-3rb.294, the seam for oo-m2nh). They take the string
        or key as a std::string and return cxx_OOExpandDescriptionString's std::optional<std::string>.
        As with the Foundation macros, each extra argument reaches the expander under its own spelling
        (#ITEM: OOExpandKey("x-[count]", count) makes [count] refer to the variable), boxed as
        OO_CAST_PARAMETER boxed it: signed integers (and char, bool and unscoped enums, which promote
        to int) as PList::signedInteger, unsigned integers as PList::unsignedInteger, float as
        PList::singleReal, double and long double as a double, strings as strings. A std::nullopt string
        is left out of the dictionary (the Foundation macro could not hold nil). No arguments passes
        the null PList, as the macro passed nil.
*/
#define cxx_OOExpand(string, ...) cxx_OOExpandWithSeed(OOStringExpanderDefaultRandomSeed(), string, __VA_ARGS__)

#define cxx_OOExpandKey(key, ...) cxx_OOExpandKeyWithSeed(OOStringExpanderDefaultRandomSeed(), key, __VA_ARGS__)

#define cxx_OOExpandKeyRandomized(key, ...) cxx_OOExpandWithOptions(OOStringExpanderDefaultRandomSeed(), kOOExpandKey | kOOExpandGoodRNG | kOOExpandReseedRNG, key, __VA_ARGS__)

#define cxx_OOExpandWithSeed(seed, string, ...) cxx_OOExpandWithOptions(seed, kOOExpandNoOptions, string, __VA_ARGS__)

#define cxx_OOExpandKeyWithSeed(seed, key, ...) cxx_OOExpandWithOptions(seed, kOOExpandKey, key, __VA_ARGS__)

#define cxx_OOExpandWithOptions(seed, options, string, ...) \
    cxx_OOExpandDescriptionString(seed, string, OOEXPAND_CXX_ARG_DICTIONARY(__VA_ARGS__), oo::PList(), std::nullopt, options)

#define OOEXPAND_CXX_ARG_DICTIONARY(...) cxx_OOExpandArgumentDictionary({ OOEXPAND_MAP(OOEXPAND_CXX_ARG_ENTRY, __VA_ARGS__) })
#define OOEXPAND_CXX_ARG_ENTRY(ITEM) oo::PList::Dict::value_type(#ITEM, cxx_OOCastParam(ITEM))

// cxx_OOCastParam() is OO_CAST_PARAMETER() for the C++ macros.
inline oo::PList cxx_OOCastParam(const std::string& value) { return oo::PList(value); }
inline oo::PList cxx_OOCastParam(const char* value) { return oo::PList(value); }
inline oo::PList cxx_OOCastParam(const std::optional<std::string>& value) { return value.has_value() ? oo::PList(*value) : oo::PList(); }
inline oo::PList cxx_OOCastParam(float value) { return oo::PList::singleReal(value); }
inline oo::PList cxx_OOCastParam(double value) { return oo::PList(value); }
inline oo::PList cxx_OOCastParam(long double value) { return oo::PList(static_cast<double>(value)); }

template <class I>
    requires std::integral<I>
oo::PList cxx_OOCastParam(I value)
{
    if constexpr (std::is_unsigned_v<I> && !std::same_as<I, bool>)
        return oo::PList::unsignedInteger(value);
    else
        return oo::PList::signedInteger(value);
}

template <class E>
    requires(std::is_enum_v<E> && std::is_convertible_v<E, std::underlying_type_t<E>>)
oo::PList cxx_OOCastParam(E value)
{
    return cxx_OOCastParam(+value); // the integral promotion OOCastParam's overload resolution made
}

// The argument dictionary: the null PList when there are no arguments; null values left out; a
// repeated name keeps its last value, as +dictionaryWithObjects:forKeys:count: did.
inline oo::PList cxx_OOExpandArgumentDictionary(std::initializer_list<oo::PList::Dict::value_type> entries)
{
    if (entries.size() == 0)
        return oo::PList();
    oo::PList::Dict dictionary;
    for (const auto& entry : entries) {
        if (!entry.second.isNull())
            dictionary.insert_or_assign(entry.first, entry.second);
    }
    return oo::PList(std::move(dictionary));
}
#endif
