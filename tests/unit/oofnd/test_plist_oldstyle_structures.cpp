/*	test_plist_oldstyle_structures.cpp
	The old-style scanner's arrays, dictionaries, data and nesting (bead oo-6rj), including
	GNUstep's <*...> and <[...]> extensions. As in test_plist_oldstyle_strings.cpp, every expected
	value and message was captured from GNUstep base 1.31.1's NSPropertyListSerialization; the
	two tests marked ADR-0027 pin oofnd's documented differences instead.
	meson test --suite oofnd-plist
*/

// Included as game code will include it, after OOCocoa.h's true/false macros (see test_plist.cpp).
#define true						1
#define false						0
#include "oofnd/PListOldStyle.hpp"
static_assert(std::is_same_v<decltype(false), int>, "PListOldStyle.hpp must restore OOCocoa.h's false macro");
#undef true
#undef false

#include "oo_test.hpp"
#include "plist_dump.hpp"

#include <string>
#include <string_view>

namespace {

std::string parsed(std::string_view in)
{
	oo::Expected<oo::PList, oo::PListError> r = oo::parseOldStylePList(in);
	return r ? oo_test::dump(*r) : "ERROR " + r.error().message;
}

std::string failure(std::string_view detail) { return "ERROR Parse failed at " + std::string(detail); }

oo::PListFormat formatOf(std::string_view in)
{
	oo::PListFormat f = oo::PListFormat::XML;
	(void)oo::parseOldStylePList(in, &f);
	return f;
}

} // namespace

OO_TEST(arrays)
{
	OO_CHECK_EQ(parsed("()"), "[]");
	OO_CHECK_EQ(parsed("(a, \"b c\", (d), {e = f;})"), "[S\"a\",S\"b c\",[S\"d\"],{\"e\"=S\"f\";}]");
	OO_CHECK_EQ(parsed("(1 , 2 ,3)"), "[S\"1\",S\"2\",S\"3\"]");   // numbers are strings
	OO_CHECK_EQ(parsed("(a, b,)"), "[S\"a\",S\"b\"]");                // trailing comma
	OO_CHECK_EQ(parsed("(a,,b)"), "[S\"a\",S\"\",S\"b\"]");            // empty unquoted item
}

OO_TEST(arrayErrors)
{
	OO_CHECK_EQ(parsed("(a b)"), failure("line 1 (char 4) - unexpected character (wanted ',' or ')')"));
	OO_CHECK_EQ(parsed("(a, b"), failure("line 1 (char 6) - reached end of string"));
	OO_CHECK_EQ(parsed("("), failure("line 1 (char 2) - unexpected end of string when parsing array"));
	OO_CHECK_EQ(parsed("( a ) junk"), failure("line 1 (char 7) - extra data after parsed string"));
}

OO_TEST(dictionaries)
{
	OO_CHECK_EQ(parsed("{}"), "{}");
	OO_CHECK_EQ(parsed("{ a = b; \"c d\" = (1, 2); e = { f = g; }; }"),
				"{\"a\"=S\"b\";\"c d\"=[S\"1\",S\"2\"];\"e\"={\"f\"=S\"g\";};}");
	OO_CHECK_EQ(parsed("{ \"a\" = 1; b = 2 ; }"), "{\"a\"=S\"1\";\"b\"=S\"2\";}");
	// The last ';' may be missing (GSMacOSXCompatible is NO).
	OO_CHECK_EQ(parsed("{ a = b }"), "{\"a\"=S\"b\";}");
	OO_CHECK_EQ(parsed("{ a = b; c = d }"), "{\"a\"=S\"b\";\"c\"=S\"d\";}");
	// A repeated key keeps the last value; empty unquoted keys and values are allowed.
	OO_CHECK_EQ(parsed("{ a = b; a = c; }"), "{\"a\"=S\"c\";}");
	OO_CHECK_EQ(parsed("{ = b; }"), "{\"\"=S\"b\";}");
	OO_CHECK_EQ(parsed("{ a = ; }"), "{\"a\"=S\"\";}");
}

OO_TEST(dictionaryErrors)
{
	OO_CHECK_EQ(parsed("{ a b; }"), failure("line 1 (char 5) - unexpected character (wanted '=')"));
	OO_CHECK_EQ(parsed("{ a = b, }"), failure("line 1 (char 8) - unexpected character (wanted ';' or '}')"));
	OO_CHECK_EQ(parsed("{ a = b;"), failure("line 1 (char 9) - unexpected end of string when parsing dictionary"));
	OO_CHECK_EQ(parsed("{a=b;}{c=d;}"), failure("line 1 (char 7) - extra data after parsed string"));
	OO_CHECK_EQ(parsed("{ a = \"\xff\"; }"), failure("line 1 (char 9) - invalid utf8 data while parsing quoted string"));
}

OO_TEST(nonStringKeysAreRejected_ADR0027)
{
	// GNUstep accepts these ({(x) = b;} is a dictionary keyed by an array); oofnd keys are strings.
	OO_CHECK_EQ(parsed("{ (x) = b; }"), failure("line 1 (char 6) - non-string key in dictionary"));
	OO_CHECK_EQ(parsed("{ <00> = b; }"), failure("line 1 (char 7) - non-string key in dictionary"));
}

OO_TEST(hexData)
{
	OO_CHECK_EQ(parsed("<0a0B ff>"), "D<0a0bff>");
	OO_CHECK_EQ(parsed("<>"), "D<>");
	OO_CHECK_EQ(parsed("< 01 02 >"), "D<0102>");
	// Comments count as the space between octets.
	OO_CHECK_EQ(parsed("<01 // x\n 02>"), "D<0102>");
	OO_CHECK(formatOf("<01>") == oo::PListFormat::OpenStep);
}

OO_TEST(hexDataErrors)
{
	OO_CHECK_EQ(parsed("<012>"), failure("line 1 (char 4) - unexpected character (wanted '>')"));
	OO_CHECK_EQ(parsed("<0g>"), failure("line 1 (char 2) - unexpected character (wanted '>')"));
	OO_CHECK_EQ(parsed("<01"), failure("line 1 (char 2) - unexpected end of string when parsing data"));
	// A comment may swallow the first '>'; scanning then stops at the next non-space.
	OO_CHECK_EQ(parsed("<01 /* > */ 02>"), failure("line 1 (char 13) - unexpected character (wanted '>')"));
	// A comment running to the end: GNUstep reads past the buffer here; oofnd reports the same
	// message GNUstep produced (ADR-0027 item 4).
	OO_CHECK_EQ(parsed("(<01 //>)"), failure("line 1 (char 10) - unexpected character (wanted '>')"));
}

OO_TEST(typedValueExtension)
{
	OO_CHECK_EQ(parsed("(<*I12>, <*I-5>, <*I18446744073709551615>, <*I99999999999999999999>, "
					   "<*I-99999999999999999999>, <*I\"7\">, <*Iabc>)"),
				"[I12,I-5,U18446744073709551615,U18446744073709551615,I-9223372036854775808,I7,I0]");
	OO_CHECK_EQ(parsed("(<*R1.5>, <*R-0.25e2>, <*Rjunk>, <*R\"2.5\">)"), "[R1.5,R-25,R0,R2.5]");
	OO_CHECK_EQ(parsed("(<*BY>, <*BN>, <*BYES>, <*BNO>)"), "[B1,B0,B1,B0]");
	OO_CHECK_EQ(parsed("<*I\"\">"), "I0");   // "" is too short to be unquoted
	OO_CHECK_EQ(parsed("{ key = <*D2001-01-01 00:00:00 +0000>; }"), "{\"key\"=T0.000;}");
	// Using an extension makes the format GNUstep rather than OpenStep.
	OO_CHECK(formatOf("<*I1>") == oo::PListFormat::GNUstep);
	OO_CHECK(formatOf("(a)") == oo::PListFormat::OpenStep);
	// Signedness is kept for the writers.
	OO_CHECK(oo::parseOldStylePList("<*I5>")->getIf<oo::PList::Integer>()->isUnsigned);
	OO_CHECK(!oo::parseOldStylePList("<*I-5>")->getIf<oo::PList::Integer>()->isUnsigned);
}

OO_TEST(typedValueErrors)
{
	OO_CHECK_EQ(parsed("<*Bx>"), failure("line 1 (char 5) - bad value for bool"));
	OO_CHECK_EQ(parsed("<*Q1>"), failure("line 1 (char 5) - unrecognized type code after '<*'"));
	OO_CHECK_EQ(parsed("<*I>"), failure("line 1 (char 4) - missing type code after '<*'"));
	OO_CHECK_EQ(parsed("<*>"), failure("line 1 (char 3) - missing type code after '<*'"));
	OO_CHECK_EQ(parsed("<*I12"), failure("line 1 (char 6) - unexpected end of string when parsing data"));
	OO_CHECK_EQ(parsed("( <*I12 )"), failure("line 1 (char 10) - unexpected end of string when parsing data"));
}

OO_TEST(base64Extension)
{
	OO_CHECK_EQ(parsed("(<[AAEC]>, <[]>, <[AAE=]>, <[AA==]>, <[ A A E C ]>, <[=]>)"),
				"[D<000102>,D<>,D<0001>,D<00>,D<000102>,D<00>]");
	OO_CHECK_EQ(parsed("(<[!!]>)"), "[D<>]");
	OO_CHECK(formatOf("<[AA==]>") == oo::PListFormat::GNUstep);
	OO_CHECK_EQ(parsed("<[AA"), failure("line 1 (char 5) - unexpected end of string when parsing data"));
	OO_CHECK_EQ(parsed("<[AA]"), failure("line 1 (char 6) - unexpected end of string when parsing ']>'"));
}

OO_TEST(undecodableExtensionsAreNilWithoutAnError)
{
	// GNUstep returns nil for the item and sets no error, so the whole plist is nil and
	// OOPropertyListFromData logs "<no error message>". oofnd: a null PList, not an error.
	OO_CHECK_EQ(parsed("<[AAE=A]>"), "nil");
	OO_CHECK_EQ(parsed("(<*Dgarbage>, x)"), "nil");
	OO_CHECK(oo::parseOldStylePList("{ a = (<[AAE=A]>); }").has_value());
}

OO_TEST(dateFieldsNSCalendarDateRejects)
{
	// Found by the GNUstep differential fuzzer (bead oo-g2k): -initWithString:calendarFormat:
	// is nil for a day or month of 0 ("Day of month is zero"), so the whole plist is nil.
	OO_CHECK_EQ(parsed("{ key = <*D2001-01-00 00:00:00 +0000>; }"), "nil");
	OO_CHECK_EQ(parsed("{ key = <*D2001-00-01 00:00:00 +0000>; }"), "nil");
	OO_CHECK_EQ(parsed("{ key = <*D2001-01- 00:00:00 +0000>; }"), "nil");   // " 0": the day is 0
	OO_CHECK_EQ(parsed("{ key = <*D2001-0-01 00:00:00 +0000>; }"), "nil");
	OO_CHECK_EQ(parsed("(<*D2001-13-01 00:00:00 +0000>)"), "[T31536000.000]");   // 13 rolls over
}

OO_TEST(dateZoneBeyondEighteenHoursIsUtc_ADR0027)
{
	// +timeZoneForSecondsFromGMT: is nil beyond 18 hours and the date falls back to the local
	// zone; oofnd reads it as UTC (ADR-0027 item 7), as the GNUstep oracle pinned to UTC does.
	OO_CHECK_EQ(parsed("{ key = <*D2001-01-01 00:00:00 +1800>; }"), "{\"key\"=T-64800.000;}");
	OO_CHECK_EQ(parsed("{ key = <*D2001-01-01 00:00:00 +1801>; }"), "{\"key\"=T0.000;}");
	OO_CHECK_EQ(parsed("{ key = <*D2001-01-01 00:00:00 -1801>; }"), "{\"key\"=T0.000;}");
	OO_CHECK_EQ(parsed("{ key = <*D2001-01-01 00:00:00 +0960>; }"), "{\"key\"=T-36000.000;}");
	OO_CHECK_EQ(parsed("{ key = <*D2001-01-01 00:00:00 +19>; }"), "{\"key\"=T0.000;}");
	OO_CHECK_EQ(parsed("{ key = <*D2001-01-01 00:00:005060708090a0b0c0d0e0f>; }"), "{\"key\"=T0.000;}");
}

OO_TEST(nestingAndComments)
{
	OO_CHECK_EQ(parsed("{a=(1,{b=<01>;c=({},());});d=\"x\";}"),
				"{\"a\"=[S\"1\",{\"b\"=D<01>;\"c\"=[{},[]];}];\"d\"=S\"x\";}");
	OO_CHECK_EQ(parsed("/*c*/ { /* k */ a /* e */ = /* v */ b /* s */ ; // x\n } // end"), "{\"a\"=S\"b\";}");
	OO_CHECK_EQ(parsed("(a) // trailing"), "[S\"a\"]");
}

OO_TEST(errorPositionsInNestedInput)
{
	OO_CHECK_EQ(parsed("\n{\n a = b;\n c = d e;\n}"), failure("line 4 (char 19) - unexpected character (wanted ';' or '}')"));
	OO_CHECK_EQ(parsed("(\n a,\n \"unterminated\n)"), failure("line 4 (char 23) - reached end of string while parsing quoted string"));
}

OO_TEST_MAIN()
