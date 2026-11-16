/*	test_plist_carrier.cpp
	oo::PList as the Foundation sweep's carrier for mixed configuration dictionaries (proposed
	ADR-0043 Amendment 2): Type::Object (a foreign object, by identity) and single-precision reals
	(+numberWithFloat:).

	The single-precision text is GNUstep base 1.31.1's, captured on this toolchain by a throwaway
	probe: -[NSNumber stringValue] of +numberWithFloat: printed 0.1, 3.141593, 1e-07, 1.234568e+08,
	1e+30 where the same values as +numberWithDouble: printed 0.1000000014901161,
	3.141592741012573, 1.000000011686097e-07, 123456792, 1.000000015047466e+30.
*/

#include "oofnd/PList.hpp"
#include "oofnd/PListWriting.hpp"
#include "oofnd/Defaults.hpp"

#include "oo_test.hpp"

#include <string>

namespace {

int gLiveForeign = 0;

class TestForeign final : public oo::PListForeign
{
public:
	explicit TestForeign(std::string name) : name_(std::move(name)) { ++gLiveForeign; }
	~TestForeign() override { --gLiveForeign; }
	std::string className() const override { return "OOColor"; }
	std::string description() const override { return "<OOColor 0x1>{" + name_ + "}"; }

private:
	std::string name_;
};

oo::PList foreign(const char* name) { return oo::PList(oo::makeRef<TestForeign>(name)); }

} // namespace

OO_TEST(an_object_node_compares_by_identity_and_is_owned)
{
	gLiveForeign = 0;
	{
		const oo::PList a = foreign("red");
		const oo::PList b = foreign("red");
		OO_CHECK(a.isObject());
		OO_CHECK(a.type() == oo::PList::Type::Object);
		OO_CHECK(a == a);
		OO_CHECK(!(a == b));   // equal descriptions, different objects
		oo::PList::Dict d{{"diffuse_color", a}, {"name", oo::PList("hull.png")}};
		const oo::PList config(d);
		const oo::PList copy = config;   // copies the reference, not the object
		OO_CHECK(copy == config);
		OO_CHECK_EQ(gLiveForeign, 2);
		OO_CHECK(copy.find("diffuse_color")->getIf<oo::PList::Object>()->get() == a.getIf<oo::PList::Object>()->get());
	}
	OO_CHECK_EQ(gLiveForeign, 0);
}

OO_TEST(an_object_node_converts_to_nothing)
{
	const oo::PList config(oo::PList::Dict{{"gloss", foreign("x")}, {"shininess", oo::PList(3)}});
	OO_CHECK_EQ(config.get<float>("gloss", 0.375f), 0.375f);   // not a number: the fallback
	OO_CHECK_EQ(config.get<int>("shininess", -1), 3);
	OO_CHECK_EQ(config.get<std::string>("gloss", "fallback"), std::string("fallback"));
}

OO_TEST(writers_refuse_or_describe_an_object_node)
{
	const oo::PList config(oo::PList::Dict{{"c", foreign("x")}});
	const auto oldStyle = oo::writeOldStylePList(config);
	OO_CHECK(!oldStyle.has_value());
	OO_CHECK(!oldStyle.has_value() && oldStyle.error().message == "Class OOColor does not support OldSchoolPropertyListWriting");
}

OO_TEST(a_single_precision_real_is_a_different_number)
{
	const oo::PList f = oo::PList::singleReal(0.1f);
	const oo::PList d(static_cast<double>(0.1f));
	OO_CHECK(f.isReal() && f.isSinglePrecision());
	OO_CHECK(!d.isSinglePrecision());
	OO_CHECK(!(f == d));                       // type-strict, as float and double NSNumbers differ in type
	OO_CHECK_EQ(f.doubleValue(), d.doubleValue());   // same value
	OO_CHECK_EQ(oo::PList(oo::PList::Dict{{"k", f}}).get<float>("k"), 0.1f);
}

OO_TEST(a_single_precision_real_prints_as_gnustep_printed_the_float)
{
	struct Row { float value; const char* asFloat; const char* asDouble; };
	const Row rows[] = {
		{0.1f, "0.1", "0.1000000014901161"}, {0.5f, "0.5", "0.5"}, {1.0f, "1", "1"},
		{3.14159265f, "3.141593", "3.141592741012573"}, {1e-7f, "1e-07", "1.000000011686097e-07"},
		{123456789.0f, "1.234568e+08", "123456792"}, {-2.5f, "-2.5", "-2.5"}, {0.375f, "0.375", "0.375"},
		{1e30f, "1e+30", "1.000000015047466e+30"},
	};
	for (const Row& r : rows)
	{
		OO_CHECK_EQ(oo::plist_get::numberStringValue(oo::PList::singleReal(r.value)), std::string(r.asFloat));
		OO_CHECK_EQ(oo::plist_get::numberStringValue(oo::PList(static_cast<double>(r.value))), std::string(r.asDouble));
	}
}

OO_TEST(the_openstep_writer_uses_the_single_precision_flag)
{
	const oo::PList p(oo::PList::Dict{{"f", oo::PList::singleReal(0.1f)}, {"d", oo::PList(static_cast<double>(0.1f))}});
	const oo::Data out = oo::writeOpenStepPList(p);
	const std::string text(reinterpret_cast<const char*>(out.bytes()), out.length());
	OO_CHECK(text.find("f = \"0.1\";") != std::string::npos);
	OO_CHECK(text.find("d = \"0.1000000014901161\";") != std::string::npos);
}

OO_TEST(the_xml_writer_uses_the_single_precision_flag)
{
	// GNUstep 1.31.1 (captured): +dataFromPropertyList:format:NSPropertyListXMLFormat_v1_0 wrote
	// <real>0.1</real> for both 0.1f and 0.1, <real>3.141593</real> for 3.14159265f and
	// <real>1e+30</real> for 1e30f.
	const oo::PList p(oo::PList::Dict{{"f", oo::PList::singleReal(0.1f)}, {"d", oo::PList(0.1)},
									   {"pi", oo::PList::singleReal(3.14159265f)}, {"big", oo::PList::singleReal(1e30f)},
									   {"fd", oo::PList(static_cast<double>(0.1f))}});
	const auto out = oo::writeXMLPList(p);
	OO_CHECK(out.has_value());
	const std::string text = out.has_value() ? std::string(reinterpret_cast<const char*>(out->bytes()), out->length()) : std::string();
	OO_CHECK(text.find("<key>f</key>\n    <real>0.1</real>") != std::string::npos);
	OO_CHECK(text.find("<key>d</key>\n    <real>0.1</real>") != std::string::npos);
	OO_CHECK(text.find("<real>3.141593</real>") != std::string::npos);
	OO_CHECK(text.find("<real>1e+30</real>") != std::string::npos);
	OO_CHECK(text.find("<key>fd</key>\n    <real>0.1000000014901161</real>") != std::string::npos);   // a double stays a double
}

OO_TEST_MAIN()
