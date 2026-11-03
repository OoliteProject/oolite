/*	test_plist.cpp
	Unit tests for oofnd/PList.hpp (bead oo-075): the oo::PList value type - the nine kinds a
	parsed property list can hold, their accessors, NSNumber's conversions, value semantics, and
	the UTF-16 <-> UTF-8 conversion the parsers and writers use for NSString's code units.
	meson test --suite oofnd-plist
*/

// PList.hpp is included by Objective-C++ game code after OOCocoa.h, which defines true/false as
// 1/0: it must compile under those macros and hand them back unchanged (as test_cocoa_macros.cpp
// checks for Data/FileSystem/ResourcePaths).
#define true						1
#define false						0
#include "oofnd/PList.hpp"
static_assert(std::is_same_v<decltype(true), int>, "PList.hpp must restore OOCocoa.h's true macro");
static_assert(std::is_same_v<decltype(false), int>, "PList.hpp must restore OOCocoa.h's false macro");
#undef true
#undef false

#include "oo_test.hpp"
#include "plist_dump.hpp"

#include <cmath>
#include <cstdint>
#include <initializer_list>
#include <limits>
#include <optional>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

using oo::PList;

namespace {

oo::Data bytes(std::initializer_list<std::uint8_t> b) { return oo::Data(std::vector<std::uint8_t>(b)); }

} // namespace

OO_TEST(defaultIsNull)
{
	PList p;
	OO_CHECK(p.isNull());
	OO_CHECK(p.type() == PList::Type::Null);
	OO_CHECK(!p);
	OO_CHECK(PList(nullptr).isNull());
	OO_CHECK_EQ(p.count(), 0u);
	OO_CHECK(p.find("x") == nullptr);
	OO_CHECK(p.at(0) == nullptr);
	OO_CHECK(p.getIf<std::string>() == nullptr);
	OO_CHECK_EQ(oo_test::dump(p), "nil");
}

OO_TEST(eachKindHasItsType)
{
	OO_CHECK(PList(true).type() == PList::Type::Bool);
	OO_CHECK(PList(42).type() == PList::Type::Integer);
	OO_CHECK(PList(std::uint64_t{42}).type() == PList::Type::Integer);
	OO_CHECK(PList(1.5).type() == PList::Type::Real);
	OO_CHECK(PList(1.5f).type() == PList::Type::Real);
	OO_CHECK(PList("s").type() == PList::Type::String);
	OO_CHECK(PList(std::string("s")).type() == PList::Type::String);
	OO_CHECK(PList(std::string_view("s")).type() == PList::Type::String);
	OO_CHECK(PList(bytes({1, 2})).type() == PList::Type::Data);
	OO_CHECK(PList(PList::Date{3.0}).type() == PList::Type::Date);
	OO_CHECK(PList(PList::Array{}).type() == PList::Type::Array);
	OO_CHECK(PList(PList::Dict{}).type() == PList::Type::Dict);
	OO_CHECK(PList(true).isNumber() && PList(1).isNumber() && PList(1.0).isNumber());
	OO_CHECK(!PList("1").isNumber());
	OO_CHECK_EQ(std::string(oo::typeName(PList::Type::Dict)), "dict");
	OO_CHECK_EQ(std::string(oo::typeName(PList::Type::Null)), "null");
}

OO_TEST(getIfReturnsPayloadOnlyForItsType)
{
	PList s("hello");
	OO_CHECK(s.getIf<std::string>() != nullptr && *s.getIf<std::string>() == "hello");
	OO_CHECK(s.getIf<PList::Dict>() == nullptr);
	OO_CHECK(s.getIf<bool>() == nullptr);

	PList b(false);
	OO_CHECK(b.getIf<bool>() != nullptr && *b.getIf<bool>() == false);
	OO_CHECK(b);   // a false boolean is still a value, not nil

	PList i(-7);
	OO_CHECK(i.getIf<PList::Integer>() != nullptr);
	OO_CHECK_EQ(i.getIf<PList::Integer>()->value, -7);
	OO_CHECK(!i.getIf<PList::Integer>()->isUnsigned);

	PList d(bytes({0xde, 0xad}));
	OO_CHECK(d.getIf<PList::Data>()->length() == 2 && d.getIf<PList::Data>()->bytes()[1] == 0xad);
	OO_CHECK_EQ(PList(PList::Date{12.5}).getIf<PList::Date>()->sinceReferenceDate, 12.5);
}

OO_TEST(integerSignednessIsKept)
{
	PList u = PList::unsignedInteger(std::numeric_limits<std::uint64_t>::max());
	OO_CHECK(u.getIf<PList::Integer>()->isUnsigned);
	OO_CHECK_EQ(u.uint64Value(), std::numeric_limits<std::uint64_t>::max());
	OO_CHECK_EQ(u.int64Value(), -1);   // NSNumber longLongValue of ULLONG_MAX
	OO_CHECK_EQ(oo_test::dump(u), "U18446744073709551615");

	PList s = PList::signedInteger(std::numeric_limits<std::int64_t>::min());
	OO_CHECK(!s.getIf<PList::Integer>()->isUnsigned);
	OO_CHECK_EQ(oo_test::dump(s), "I-9223372036854775808");

	OO_CHECK(PList(5u).getIf<PList::Integer>()->isUnsigned);
	OO_CHECK(!PList(5).getIf<PList::Integer>()->isUnsigned);
	OO_CHECK_EQ(oo_test::dump(PList(5u)), "I5");   // small unsigned values read like GNUstep's
	OO_CHECK(PList::unsignedInteger(5) != PList::signedInteger(5));
}

OO_TEST(numberConversionsFollowNSNumber)
{
	OO_CHECK_EQ(PList(true).int64Value(), 1);
	OO_CHECK_EQ(PList(true).doubleValue(), 1.0);
	OO_CHECK_EQ(PList(false).uint64Value(), 0u);
	OO_CHECK(PList(2).boolValue());
	OO_CHECK(!PList(0).boolValue());
	OO_CHECK(PList(0.5).boolValue());
	OO_CHECK_EQ(PList(-3).doubleValue(), -3.0);
	OO_CHECK_EQ(PList::unsignedInteger(1ull << 63).doubleValue(), 9223372036854775808.0);
	OO_CHECK_EQ(PList(2.9).int64Value(), 2);
	OO_CHECK_EQ(PList(-2.9).int64Value(), -2);
	// Out-of-range and NaN reals saturate instead of hitting undefined behaviour.
	OO_CHECK_EQ(PList(1e300).int64Value(), std::numeric_limits<std::int64_t>::max());
	OO_CHECK_EQ(PList(-1e300).int64Value(), std::numeric_limits<std::int64_t>::min());
	OO_CHECK_EQ(PList(std::nan("")).int64Value(), 0);
	OO_CHECK_EQ(PList(1e300).uint64Value(), std::numeric_limits<std::uint64_t>::max());
	// Non-numbers answer 0, as a message to nil does.
	OO_CHECK_EQ(PList("12").int64Value(), 0);
	OO_CHECK_EQ(PList().doubleValue(), 0.0);
	OO_CHECK(!PList(PList::Array{1}).boolValue());
}

OO_TEST(arrayAccess)
{
	PList a(PList::Array{1, "two", 3.0});
	OO_CHECK_EQ(a.count(), 3u);
	OO_CHECK(a.at(1) != nullptr && a.at(1)->isString());
	OO_CHECK(a.at(3) == nullptr);
	OO_CHECK(a.find("two") == nullptr);   // not a dictionary
	a.getIf<PList::Array>()->push_back(PList(true));
	OO_CHECK_EQ(a.count(), 4u);
	OO_CHECK_EQ(oo_test::dump(a), "[I1,S\"two\",R3,B1]");
}

OO_TEST(dictAccess)
{
	PList d(PList::Dict{{"b", 2}, {"a", "x"}});
	OO_CHECK_EQ(d.count(), 2u);
	OO_CHECK(d.find("a") != nullptr && *d.find("a")->getIf<std::string>() == "x");
	OO_CHECK(d.find("c") == nullptr);
	OO_CHECK(d.at(0) == nullptr);   // not an array
	*d.find("b") = PList(PList::Array{});
	OO_CHECK(d.find("b")->isArray());
	(*d.getIf<PList::Dict>())["c"] = PList(false);
	OO_CHECK_EQ(oo_test::dump(d), "{\"a\"=S\"x\";\"b\"=[];\"c\"=B0;}");
	// Iteration is in byte order of the UTF-8 key: deterministic.
	std::string order;
	for (const auto& kv : *d.getIf<PList::Dict>()) order += kv.first;
	OO_CHECK_EQ(order, "abc");
}

OO_TEST(valueSemanticsDeepCopy)
{
	PList inner(PList::Dict{{"k", PList(PList::Array{1, 2})}});
	PList outer(PList::Array{inner, inner});
	PList copy = outer;
	OO_CHECK(copy == outer);
	copy.getIf<PList::Array>()->at(0).find("k")->getIf<PList::Array>()->push_back(3);
	OO_CHECK(copy != outer);
	OO_CHECK_EQ(outer.at(0)->find("k")->count(), 2u);
	OO_CHECK_EQ(copy.at(0)->find("k")->count(), 3u);
	OO_CHECK_EQ(copy.at(1)->find("k")->count(), 2u);

	PList moved = std::move(copy);
	OO_CHECK_EQ(moved.at(0)->find("k")->count(), 3u);
}

OO_TEST(equalityIsStructuralAndTypeStrict)
{
	OO_CHECK(PList("a") == PList(std::string("a")));
	OO_CHECK(PList("a") != PList("b"));
	OO_CHECK(PList(1) != PList(1.0));
	OO_CHECK(PList(1) != PList(true));
	OO_CHECK(PList() == PList(nullptr));
	OO_CHECK(PList(PList::Array{1, "x"}) == PList(PList::Array{1, "x"}));
	OO_CHECK(PList(PList::Array{1, "x"}) != PList(PList::Array{"x", 1}));
	OO_CHECK(PList(PList::Dict{{"a", 1}}) == PList(PList::Dict{{"a", 1}}));
	OO_CHECK(PList(PList::Dict{{"a", 1}}) != PList(PList::Dict{{"a", 2}}));
	OO_CHECK(PList(bytes({1})) != PList(bytes({1, 0})));
	OO_CHECK(PList(PList::Date{1.0}) == PList(PList::Date{1.0}));
}

OO_TEST(utf16RoundTripsThroughUtf8)
{
	// ASCII, 2-, 3- and 4-byte UTF-8.
	const std::u16string s = u"a\u00E9\u20AC\U0001F600z";
	const std::string u8 = oo::utf16ToUtf8(s);
	OO_CHECK_EQ(u8, std::string("a\xC3\xA9\xE2\x82\xAC\xF0\x9F\x98\x80z"));
	OO_CHECK(oo::utf8ToUtf16(u8) == s);
	// Embedded U+0000 survives.
	const std::u16string nul(u"x\0y", 3);
	OO_CHECK_EQ(oo::utf16ToUtf8(nul).size(), 3u);
	OO_CHECK(oo::utf8ToUtf16(oo::utf16ToUtf8(nul)) == nul);
}

OO_TEST(loneSurrogatesAreKeptAsWtf8)
{
	const std::u16string lone(1, static_cast<char16_t>(0xD800));
	const std::string w = oo::utf16ToUtf8(lone);
	OO_CHECK_EQ(w, std::string("\xED\xA0\x80"));
	OO_CHECK(oo::utf8ToUtf16(w) == lone);
	const std::u16string swapped{static_cast<char16_t>(0xDC00), static_cast<char16_t>(0xD800)};
	OO_CHECK(oo::utf8ToUtf16(oo::utf16ToUtf8(swapped)) == swapped);
	OO_CHECK_EQ(oo_test::dump(PList(w)), "S\"\\uD800\"");
}

OO_TEST(byteOrderMarksFollowNSString)
{
	// -initWithCharacters: drops a leading U+FEFF; a leading U+FFFE is dropped and the rest is
	// byte-swapped (GNUstep 1.31.1: "\UFFFEx" -> U+7800, "\UFFFE\UFFFE\U2600" -> U+FEFF '&').
	std::u16string a = u"﻿abc";
	oo::plist_detail::applyInitWithCharactersBOM(a);
	OO_CHECK(a == u"abc");
	std::u16string b = u"￾x";
	oo::plist_detail::applyInitWithCharactersBOM(b);
	OO_CHECK(b == std::u16string(1, static_cast<char16_t>(0x7800)));
	std::u16string c{static_cast<char16_t>(0xFFFE), static_cast<char16_t>(0xFFFE), static_cast<char16_t>(0x2600)};
	oo::plist_detail::applyInitWithCharactersBOM(c);
	OO_CHECK(c == (std::u16string{static_cast<char16_t>(0xFEFF), u'&'}));
	std::u16string d = u"a﻿";   // only a LEADING mark
	oo::plist_detail::applyInitWithCharactersBOM(d);
	OO_CHECK(d == u"a﻿");
	std::u16string e;
	oo::plist_detail::applyInitWithCharactersBOM(e);
	OO_CHECK(e.empty());
	// From UTF-8 bytes only U+FEFF goes.
	OO_CHECK_EQ(oo::plist_detail::utf8WithoutLeadingBOM("\xEF\xBB\xBFk"), "k");
	OO_CHECK_EQ(oo::plist_detail::utf8WithoutLeadingBOM("\xEF\xBF\xBEy"), "\xEF\xBF\xBEy");
	OO_CHECK_EQ(oo::plist_detail::utf8WithoutLeadingBOM("k\xEF\xBB\xBF"), "k\xEF\xBB\xBF");
}

OO_TEST(malformedUtf8ReadsAsLatin1Units)
{
	// A stray continuation byte and a truncated sequence each become one code unit.
	const std::u16string u = oo::utf8ToUtf16(std::string("a\x80" "b\xC3", 4));
	OO_CHECK(u == (std::u16string{u'a', static_cast<char16_t>(0x80), u'b', static_cast<char16_t>(0xC3)}));
	// Overlong encodings are not decoded.
	OO_CHECK_EQ(oo::utf8ToUtf16(std::string("\xC0\xAF")).size(), 2u);
}

OO_TEST(errorDescriptionIsNSErrorsWording)
{
	const oo::PListError e{"Parse failed at line 1 (char 9) - reached end of string"};
	OO_CHECK_EQ(e.description(),
				"Error Domain=NSPropertyListSerialization Code=0 \"Parse failed at line 1 (char 9) - reached end of string\"");
	OO_CHECK(e == oo::PListError{e.message});
	OO_CHECK_EQ(static_cast<int>(oo::PListFormat::OpenStep), 1);
	OO_CHECK_EQ(static_cast<int>(oo::PListFormat::XML), 100);
	OO_CHECK_EQ(static_cast<int>(oo::PListFormat::GNUstep), 1000);
}

namespace {

double calendarDate(std::string_view s, bool zulu = false)
{
	std::optional<double> d = oo::plist_detail::parseCalendarDate(s, zulu);
	return d ? *d : -1e300;   // sentinel for "GNUstep returned nil"
}

} // namespace

// Expected values captured from GNUstep 1.31.1 (old-style <*D...> through NSPropertyListSerialization).
OO_TEST(calendarDatesParseLikeNSCalendarDate)
{
	OO_CHECK_EQ(calendarDate("2001-01-01 00:00:00 +0000"), 0.0);
	OO_CHECK_EQ(calendarDate("2001-01-01 00:00:00 +0130"), -5400.0);
	OO_CHECK_EQ(calendarDate("2024-02-29 12:34:56 -0800"), 730931696.0);
	OO_CHECK_EQ(calendarDate("1970-01-01 00:00:00 +0000"), -978307200.0);
	OO_CHECK_EQ(calendarDate("1600-03-01 00:00:00 +0000"), -12649219200.0);
	OO_CHECK_EQ(calendarDate("0001-01-01 00:00:00 +0000"), -63113904000.0);
	// Two zone digits are hours; one digit is minutes.
	OO_CHECK_EQ(calendarDate("2001-01-01 00:00:10 +00"), 10.0);
	OO_CHECK_EQ(calendarDate("2001-01-01 00:00:00 +1"), -60.0);
	OO_CHECK_EQ(calendarDate("2001-01-01 00:00:00 -0030"), 1800.0);
	// Short fields, runs of spaces, trailing junk and out-of-range fields are all accepted.
	OO_CHECK_EQ(calendarDate("2001-1-2 3:4:5 +0000"), 97445.0);
	OO_CHECK_EQ(calendarDate("2001-01-01   00:00:00+0000"), 0.0);
	OO_CHECK_EQ(calendarDate("2001-01-01 00:00:00 +0000 junk"), 0.0);
	OO_CHECK_EQ(calendarDate("2001-13-40 25:61:61 +0000"), 34999321.0);
}

OO_TEST(calendarDatesGNUstepRejects)
{
	OO_CHECK_EQ(calendarDate("2001-01-01 00:00:00"), -1e300);          // no zone digits
	OO_CHECK_EQ(calendarDate("2001-01-01T00:00:00 +0000"), -1e300);    // wrong literal
	OO_CHECK_EQ(calendarDate("12345-01-01 00:00:00 +0000"), -1e300);   // %Y reads 4 digits
	OO_CHECK_EQ(calendarDate(" 2001- 1- 1  0:0:0 +0000"), -1e300);     // " 200" then '1' != '-'
	OO_CHECK_EQ(calendarDate("garbage"), -1e300);
}

OO_TEST(zuluDatesAreUtc)
{
	// GNUstep reads this format in the machine's local zone (it captured 18000 on a UTC-5
	// machine); oofnd reads it as UTC (ADR-0027 item 7).
	OO_CHECK_EQ(calendarDate("2001-01-01T00:00:00Z", true), 0.0);
	OO_CHECK_EQ(calendarDate("2001-07-01T00:00:00Z", true), 15638400.0);
	OO_CHECK_EQ(calendarDate("2001-07-01 00:00:00Z", true), -1e300);
}

OO_TEST_MAIN()
