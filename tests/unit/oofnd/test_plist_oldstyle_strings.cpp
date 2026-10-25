/*	test_plist_oldstyle_strings.cpp
	Cases 1-14 for the old-style scanner's strings, escapes and comments (bead oo-6ft):
	oo::parseOldStylePList on a top-level string. Every expected value and error message was
	captured from GNUstep base 1.31.1's +[NSPropertyListSerialization propertyListFromData:...]
	(the build the game links), through a throwaway harness that printed plist_dump.hpp's format;
	they pin GNUstep's behaviour, quirks included, not an idea of what a plist should do.
	meson test --suite oofnd-plist
*/

// Included as game code will include it, after OOCocoa.h's true/false macros (see test_plist.cpp).
#define true						1
#define false						0
#include "oofnd/PListOldStyle.hpp"
static_assert(std::is_same_v<decltype(true), int>, "PListOldStyle.hpp must restore OOCocoa.h's true macro");
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

} // namespace

// Bytes with embedded NULs or non-ASCII are spelled with std::string_view literals.
using namespace std::string_view_literals;

OO_TEST(case01_unquotedStrings)
{
	OO_CHECK_EQ(parsed("abc"), "S\"abc\"");
	// Everything outside GNUstep's quotables table is part of an unquoted string.
	OO_CHECK_EQ(parsed("a.b/c_d-e:f$g+h!#%&*?@^|~9"), "S\"a.b/c_d-e:f$g+h!#%&*?@^|~9\"");
	// "/" starts a comment only when followed by '/' or '*' at the START of an item.
	OO_CHECK_EQ(parsed("/"), "S\"/\"");
	OO_CHECK_EQ(parsed("a/b//c"), "S\"a/b//c\"");
	// Whitespace is GNUstep's fixed table: 0x08 (backspace) to 0x0D, and space.
	OO_CHECK_EQ(parsed("\x08\x0b\x0c" "abc\r\n"), "S\"abc\"");

	oo::PListFormat format = oo::PListFormat::XML;
	OO_CHECK(oo::parseOldStylePList("abc", &format).has_value());
	OO_CHECK(format == oo::PListFormat::OpenStep);
}

OO_TEST(case02_quotableCharactersEndAnUnquotedString)
{
	OO_CHECK_EQ(parsed("ab cd"), failure("line 1 (char 4) - extra data after parsed string"));
	OO_CHECK_EQ(parsed("'single'"), failure("line 1 (char 1) - extra data after parsed string"));
	// Bytes >= 0x80 are quotable, so non-ASCII (and a UTF-8 BOM) cannot start an unquoted string.
	OO_CHECK_EQ(parsed("\xc3\xa9"), failure("line 1 (char 1) - extra data after parsed string"));
	OO_CHECK_EQ(parsed("\xef\xbb\xbf" "abc"), failure("line 1 (char 1) - extra data after parsed string"));
}

OO_TEST(case03_anUnquotedStringMayBeEmpty)
{
	// '=' is quotable: the item is "" and the '=' is then extra data.
	OO_CHECK_EQ(parsed("="), failure("line 1 (char 1) - extra data after parsed string"));
	OO_CHECK_EQ(parsed(" ;"), failure("line 1 (char 2) - extra data after parsed string"));
}

OO_TEST(case04_quotedStrings)
{
	OO_CHECK_EQ(parsed("\"hello world\""), "S\"hello world\"");
	OO_CHECK_EQ(parsed("\"\""), "S\"\"");
	OO_CHECK_EQ(parsed("\"tab\there\""), "S\"tab\\u0009here\"");
	OO_CHECK_EQ(parsed("\"caf\xc3\xa9\""), "S\"caf\\u00E9\"");
	OO_CHECK_EQ(oo::parseOldStylePList("\"caf\xc3\xa9\"")->getIf<std::string>()[0], "caf\xc3\xa9");
}

OO_TEST(case05_simpleEscapes)
{
	OO_CHECK_EQ(parsed(R"("\a\b\t\r\n\v\f\"\\\q")"),
				"S\"\\u0007\\u0008\\u0009\\u000D\\u000A\\u000B\\u000C\\\"\\\\q\"");
	OO_CHECK_EQ(parsed(R"("\\")"), "S\"\\\\\"");
	// 8 and 9 are not octal digits: escaped, they are themselves.
	OO_CHECK_EQ(parsed(R"("\8\9")"), "S\"89\"");
}

OO_TEST(case06_octalEscapes)
{
	// Up to three octal digits; a fourth digit is an ordinary character.
	OO_CHECK_EQ(parsed(R"("\101\1012\7x\0")"), "S\"AA2\\u0007x\"");
	OO_CHECK_EQ(parsed(R"("\777\400")"), "S\"\\u01FF\\u0100\"");
}

OO_TEST(case07_hexEscapes)
{
	// \U and \u take up to four hex digits, either case; a surrogate pair becomes one character.
	OO_CHECK_EQ(parsed(R"("\U00e9\u20AC\UD83D\UDE00")"), "S\"\\u00E9\\u20AC\\uD83D\\uDE00\"");
	OO_CHECK_EQ(*oo::parseOldStylePList(R"("\UD83D\UDE00")")->getIf<std::string>(), "\xF0\x9F\x98\x80");
	OO_CHECK_EQ(parsed(R"("\u1234567")"), "S\"\\u1234567\"");
}

OO_TEST(case08_shortAndEmptyHexEscapes)
{
	OO_CHECK_EQ(parsed(R"("\u4x\U")"), "S\"\\u0004x\"");
	OO_CHECK_EQ(parsed(R"("\u00zz")"), "S\"\\u0000zz\"");
	OO_CHECK_EQ(parsed(R"("\u")"), "S\"\"");
}

OO_TEST(case09_anEscapeStillOpenAtTheClosingQuoteIsDropped)
{
	OO_CHECK_EQ(parsed(R"("a\u12")"), "S\"a\"");
	OO_CHECK_EQ(parsed(R"("b\12")"), "S\"b\"");
	OO_CHECK_EQ(parsed(R"("\0")"), "S\"\"");
}

OO_TEST(case10_loneSurrogatesSurvive)
{
	OO_CHECK_EQ(parsed(R"("\UD800z")"), "S\"\\uD800z\"");
	OO_CHECK_EQ(parsed(R"("\uDE00\uD83D")"), "S\"\\uDE00\\uD83D\"");
}

OO_TEST(case11_quotedStringsMustBeStrictUtf8)
{
	OO_CHECK_EQ(parsed("\"\xff\""), failure("line 1 (char 3) - invalid utf8 data while parsing quoted string"));
	// An overlong '/' and a UTF-8-encoded surrogate are rejected too.
	OO_CHECK_EQ(parsed("\"\xc0\xaf\""), failure("line 1 (char 4) - invalid utf8 data while parsing quoted string"));
	OO_CHECK_EQ(parsed("\"\xed\xa0\x80\""), failure("line 1 (char 5) - invalid utf8 data while parsing quoted string"));
	// A raw NUL byte inside quotes is data, not an end.
	OO_CHECK_EQ(parsed("\"\0\""sv), "S\"\\u0000\"");
}

OO_TEST(case12_comments)
{
	OO_CHECK_EQ(parsed("// c\n /* multi\n line */ word // trailing"), "S\"word\"");
	// After the top-level item, running off the end inside a comment is fine...
	OO_CHECK_EQ(parsed("x /* never closed"), "S\"x\"");
	// ...before it, it is an error.
	OO_CHECK_EQ(parsed("/* x"), failure("line 1 (char 5) - reached end of string in comment"));
	OO_CHECK_EQ(parsed("// only a comment"), failure("line 1 (char 18) - reached end of string in comment"));
}

OO_TEST(case13_unterminatedAndEmptyInput)
{
	OO_CHECK_EQ(parsed("\"abc\ndef"), failure("line 2 (char 9) - reached end of string while parsing quoted string"));
	// \" does not close the string.
	OO_CHECK_EQ(parsed("\"a\\\""), failure("line 1 (char 5) - reached end of string while parsing quoted string"));
	OO_CHECK_EQ(parsed(" \t\n"), failure("line 2 (char 4) - reached end of string"));
	// (GNUstep's caller rejects empty data before scanning; the scanner itself says this.)
	OO_CHECK_EQ(parsed(""), failure("line 1 (char 1) - reached end of string"));
}

OO_TEST(byteOrderMarksInQuotedStrings)
{
	// The quoted string's units go through -initWithCharactersNoCopy:, which drops a leading
	// U+FEFF and byte-swaps after a leading U+FFFE - escaped or raw UTF-8 alike.
	OO_CHECK_EQ(parsed(R"("\UFEFFabc")"), "S\"abc\"");
	OO_CHECK_EQ(parsed(R"("a\UFEFF")"), "S\"a\\uFEFF\"");
	OO_CHECK_EQ(parsed(R"("\UFFFEx")"), "S\"\\u7800\"");
	OO_CHECK_EQ(parsed(R"("\uFEFF")"), "S\"\"");
	OO_CHECK_EQ(parsed(R"("x\uFFFE\uFEFFy")"), "S\"x\\uFFFE\\uFEFFy\"");
	OO_CHECK_EQ(parsed("\"\xef\xbb\xbf" "b\""), "S\"b\"");
	OO_CHECK_EQ(parsed("\"x\xef\xbb\xbf\""), "S\"x\\uFEFF\"");
	OO_CHECK_EQ(parsed("\"\xef\xbf\xbey\""), "S\"\\u7900\"");
	OO_CHECK_EQ(parsed(R"("\UFFFE\UFFFE\U2600")"), "S\"\\uFEFF&\"");
	OO_CHECK_EQ(parsed(R"("\UFFFE\UFEFF\U4100")"), "S\"\\uFFFEA\"");
}

OO_TEST(case14_lineNumbers)
{
	OO_CHECK_EQ(parsed("\n\n\"x\" y"), failure("line 3 (char 7) - extra data after parsed string"));
	// A newline that ends an octal escape is counted twice: GNUstep rescans it.
	OO_CHECK_EQ(parsed("\"\\1\nq\"\n\n!"), failure("line 5 (char 9) - extra data after parsed string"));
	OO_CHECK_EQ(parsed("\"\\12\n\" x"), failure("line 3 (char 8) - extra data after parsed string"));
}

OO_TEST_MAIN()
