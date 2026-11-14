/*	test_OOEncodingConverter.mm
	Unit tests for OOEncodingConverter (src/Core/OOEncodingConverter.h): bead oo-demz, a Phase 3
	conversion in the house style of the OOColor exemplar (proposed ADR-0056).

	It pins what the converter computed before the conversion: the encoding read from a font
	property list (an unknown or missing name is no encoding), the substitutions (in key order; a
	value that is not a string substitutes ""; a substitutions entry that is not a dictionary is
	ignored), conversion with and without an encoding, a repeated conversion (the cache), the
	description and StringFromEncoding(). The expectations were written against the Objective-C API
	and run on the unconverted class first (commit 1e601c6d1); its one caller was adapted in the
	bead, so there is no facade and the calls here are the C++ class's.
	Run: bash tools/check-core-tests.sh
*/

#import "OOEncodingConverter.h"

#include "oo_test.hpp"


/*	The game's OOStringParsing.mm reaches the JavaScript engine, so it is not linked. The one
	function of it that OOCache names (in its DEBUG_GRAPHVIZ dump, which no test calls) is
	defined here instead.
*/
std::string cxx_EscapedGraphVizString(const std::string &string)
{
	return string;
}


namespace {

std::string Bytes(const oo::Data &data)
{
	return std::string(reinterpret_cast<const char *>(data.bytes()), data.length());
}


oo::PList FontPList(const oo::PList &encoding, const oo::PList &substitutions)
{
	oo::PList::Dict font;
	if (!encoding.isNull())  font.emplace("encoding", encoding);
	if (!substitutions.isNull())  font.emplace("substitutions", substitutions);
	return oo::PList(std::move(font));
}


oo::PList Substitutions(std::initializer_list<std::pair<const char *, oo::PList>> entries)
{
	oo::PList::Dict result;
	for (const auto &[key, value] : entries)  result.emplace(key, value);
	return oo::PList(std::move(result));
}


oo::Ref<OOEncodingConverter> ConverterForFont(const oo::PList &font)
{
	return oo::makeRef<OOEncodingConverter>(font);
}

}	// namespace


OO_TEST(fontPListLatin1)
{
	@autoreleasepool
	{
		oo::Ref<OOEncodingConverter> converter = ConverterForFont(FontPList("windows-latin-1", Substitutions({{"\xE2\x98\x85", "\b"}, {"q", "Q"}})));
		OO_CHECK(converter != nullptr);
		OO_CHECK(converter->encoding() == std::optional<oo::str::Encoding>(oo::str::Encoding::windowsCP1252));
		OO_CHECK_EQ(Bytes(converter->convertString("abc")), std::string("abc"));
		OO_CHECK_EQ(Bytes(converter->convertString("\xE2\x98\x85 q")), std::string("\b Q"));
		// The second conversion of a string is answered from the cache, with the same bytes.
		OO_CHECK_EQ(Bytes(converter->convertString("\xE2\x98\x85 q")), std::string("\b Q"));
		// U+00E9 is 0xE9 in code page 1252.
		OO_CHECK_EQ(Bytes(converter->convertString("caf\xC3\xA9")), std::string("caf\xE9"));
		OO_CHECK_EQ(Bytes(converter->convertString("")), std::string());
		OO_CHECK(converter->descriptionComponents() == std::optional<std::string>("encoding: 12"));
	}
}


OO_TEST(substitutionOrderAndValues)
{
	@autoreleasepool
	{
		// Applied in key order: "ab" before "b".
		oo::Ref<OOEncodingConverter> converter = ConverterForFont(FontPList("windows-latin-1", Substitutions({{"b", "Y"}, {"ab", "X"}})));
		OO_CHECK_EQ(Bytes(converter->convertString("abb")), std::string("XY"));

		// A value that is not a string substitutes "".
		converter = ConverterForFont(FontPList("windows-latin-1", Substitutions({{"x", oo::PList(5)}})));
		OO_CHECK_EQ(Bytes(converter->convertString("axb")), std::string("ab"));

		// Substitutions that are not a dictionary are ignored.
		converter = ConverterForFont(FontPList("windows-latin-1", oo::PList("x")));
		OO_CHECK_EQ(Bytes(converter->convertString("axb")), std::string("axb"));
	}
}


OO_TEST(otherEncodings)
{
	@autoreleasepool
	{
		oo::Ref<OOEncodingConverter> converter = ConverterForFont(FontPList("windows-cyrillic", oo::PList()));
		OO_CHECK(converter->encoding() == std::optional<oo::str::Encoding>(oo::str::Encoding::windowsCP1251));
		// U+0416 (Zhe) is 0xC6 in code page 1251.
		OO_CHECK_EQ(Bytes(converter->convertString("\xD0\x96")), std::string("\xC6"));
		OO_CHECK(converter->descriptionComponents() == std::optional<std::string>("encoding: 11"));

		converter = oo::makeRef<OOEncodingConverter>(oo::str::Encoding::windowsCP1253, Substitutions({{"a", "b"}}));
		OO_CHECK(converter->encoding() == std::optional<oo::str::Encoding>(oo::str::Encoding::windowsCP1253));
		OO_CHECK_EQ(Bytes(converter->convertString("aa")), std::string("bb"));
		OO_CHECK(converter->descriptionComponents() == std::optional<std::string>("encoding: 13"));

		converter = oo::makeRef<OOEncodingConverter>(oo::str::Encoding::windowsCP1254, oo::PList());
		OO_CHECK_EQ(Bytes(converter->convertString("abc")), std::string("abc"));
	}
}


OO_TEST(noEncoding)
{
	@autoreleasepool
	{
		// An unknown encoding name: no encoding, and every conversion is empty.
		oo::Ref<OOEncodingConverter> converter = ConverterForFont(FontPList("klingon", Substitutions({{"a", "b"}})));
		OO_CHECK(converter != nullptr);
		OO_CHECK(!converter->encoding().has_value());
		OO_CHECK_EQ(Bytes(converter->convertString("abc")), std::string());
		OO_CHECK_EQ(Bytes(converter->convertString("abc")), std::string());
		// (NSNotFound's low 32 bits)
		OO_CHECK(converter->descriptionComponents() == std::optional<std::string>("encoding: 4294967295"));

		// No encoding key, and an encoding that is not a string.
		converter = ConverterForFont(FontPList(oo::PList(), oo::PList()));
		OO_CHECK(!converter->encoding().has_value());
		OO_CHECK_EQ(Bytes(converter->convertString("abc")), std::string());
		converter = ConverterForFont(FontPList(oo::PList(12), oo::PList()));
		OO_CHECK(!converter->encoding().has_value());

		converter = oo::makeRef<OOEncodingConverter>(std::nullopt, oo::PList());
		OO_CHECK(!converter->encoding().has_value());
		OO_CHECK_EQ(Bytes(converter->convertString("abc")), std::string());
	}
}


OO_TEST(stringFromEncoding)
{
	OO_CHECK_EQ(std::string(StringFromEncoding(12)), std::string("windows-latin-1"));
	OO_CHECK_EQ(std::string(StringFromEncoding(15)), std::string("windows-latin-2"));
	OO_CHECK_EQ(std::string(StringFromEncoding(11)), std::string("windows-cyrillic"));
	OO_CHECK_EQ(std::string(StringFromEncoding(13)), std::string("windows-greek"));
	OO_CHECK_EQ(std::string(StringFromEncoding(14)), std::string("windows-turkish"));
	OO_CHECK(StringFromEncoding(1) == nullptr);
}


OO_TEST_MAIN()
