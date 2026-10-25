/*	test_plist_description.cpp
	oo::describe(const oo::PList &) (oofnd/PListDescription.hpp; proposed ADR-0055 item 1, bead
	oo-qps.32): the text gnustep-base's -description gave for the Foundation form of a PList.

	Every expectation is GNUstep base 1.31.1's own output on this toolchain, captured by
	tools/captures/plist-description/capture.sh (a probe linked against gnustep-base, run over
	tools/captures/plist-description/cases.txt with TZ=UTC) into plist_description_captured.inc,
	unedited. Each row's input is rebuilt here as the PList oo::PListFrom made of the same
	Foundation value: a GNUstep-format plist text through oo::parsePropertyList, a single-precision
	number as PList::singleReal, a non-plist object as a PList::Object node. Dates are described at
	UTC offset 0, the capture's time zone.
*/

#include "oofnd/PListDescription.hpp"
#include "oofnd/PListParsing.hpp"

#include "oo_test.hpp"

#include <cstdio>
#include <cstdlib>
#include <string>
#include <string_view>

namespace {

struct CapturedRow
{
	const char* kind;
	const char* name;
	const char* input;
	const char* description;
};

const CapturedRow kRows[] = {
#include "plist_description_captured.inc"
};

// A colour, a texture...: a non-plist object with a fixed description.
class Foreign final : public oo::PListForeign
{
public:
	explicit Foreign(std::string text) : text_(std::move(text)) {}
	std::string className() const override { return "Foreign"; }
	std::string description() const override { return text_; }

private:
	std::string text_;
};

oo::PList ForeignNode(const char* text)
{
	return oo::PList(oo::PList::Object(oo::makeRef<Foreign>(text)));
}

// The PList a row's input stands for; null (and a failed check) if the kind is unknown.
oo::PList InputOf(const CapturedRow& row)
{
	const std::string_view kind = row.kind;
	if (kind == "nil") return oo::PList();
	if (kind == "plist")
	{
		auto parsed = oo::parsePropertyList(row.input);
		OO_CHECK(parsed.has_value());
		return parsed.has_value() ? *parsed : oo::PList();
	}
	if (kind == "float") return oo::PList::singleReal(std::strtof(row.input, nullptr));
	if (kind == "float-array") return oo::PList(oo::PList::Array{oo::PList::singleReal(std::strtof(row.input, nullptr))});
	if (kind == "foreign") return ForeignNode(row.input);
	if (kind == "foreign-array") return oo::PList(oo::PList::Array{ForeignNode(row.input)});
	if (kind == "foreign-dict") return oo::PList(oo::PList::Dict{{"key", ForeignNode(row.input)}});
	std::printf("unknown captured kind %s\n", row.kind);
	OO_CHECK(false);
	return oo::PList();
}

} // namespace

OO_TEST(everyCapturedRowMatchesGNUstep)
{
	OO_CHECK(sizeof kRows / sizeof kRows[0] >= 40);
	for (const CapturedRow& row : kRows)
	{
		const std::string got = oo::describe(InputOf(row), 0);	// captured with TZ=UTC
		if (got != row.description) std::printf("  %s: got [%s]\n  %s: GNUstep [%s]\n", row.name, got.c_str(), row.name, row.description);
		OO_CHECK_EQ(got, std::string(row.description));
	}
}

OO_TEST(nullElementsAreLeftOutAsObjectFromPListDroppedThem)
{
	const oo::PList array(oo::PList::Array{oo::PList("a"), oo::PList(), oo::PList("b")});
	OO_CHECK_EQ(oo::describe(array), std::string("(a, b)"));
	const oo::PList dict(oo::PList::Dict{{"a", oo::PList()}, {"b", oo::PList("c")}});
	OO_CHECK_EQ(oo::describe(dict), std::string("{b = c; }"));
}

OO_TEST(keysSortByUtf16UnitsNotUtf8Bytes)
{
	// U+FF01 (UTF-8 EF BC 81) sorts after U+1F600 (F0 9F 98 80) by bytes, before it by UTF-16 units.
	const oo::PList dict(oo::PList::Dict{{"\xef\xbc\x81", oo::PList("x")}, {"\xf0\x9f\x98\x80", oo::PList("y")}});
	OO_CHECK_EQ(oo::describe(dict), std::string("{\"\\UD83D\\UDE00\" = y; \"\\UFF01\" = x; }"));
}

OO_TEST(aDateIsDescribedInTheLocalTimeZoneAsNSDateWas)
{
	const oo::PList::Date when{298297845.0};	// 2010-06-15 12:30:45 +0000
	const auto t = oo::date::dateWithTimeIntervalSinceReferenceDate(when.sinceReferenceDate);
	OO_CHECK_EQ(oo::describe(oo::PList(when)), oo::date::description(t));
	OO_CHECK_EQ(oo::describe(oo::PList(when), 0), std::string("2010-06-15 12:30:45 +0000"));
	OO_CHECK_EQ(oo::describe(oo::PList(when), -300), std::string("2010-06-15 07:30:45 -0500"));
}

OO_TEST_MAIN()
