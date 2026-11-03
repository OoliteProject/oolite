/*	test_OOColor.mm
	Unit tests for cxx::OOColor (src/Core/OOColor.h) and its Objective-C facade
	(OOColor+ObjCBridge.h): bead oo-11m, the Phase 3 house-style exemplar (proposed ADR-0056).

	A converted class's test lives in tests/unit/core/test_<Class>.mm and links the game's own
	objects for the class, its bridge and what they need (tests/unit/core/meson.build), so it
	tests exactly what the game runs. It pins what the class computed before the conversion, from
	the Objective-C bodies: component arithmetic, the four description forms, the text, and the
	facade's contract (the same selectors answer the same values, nil stays nil, one facade per
	C++ object so identity survives the round trip). Run: bash tools/check-core-tests.sh
*/

#import "OOColor.h"
#import "OOObjCPList.h"

#include "oo_test.hpp"

#include <cmath>


namespace {

bool Near(float a, float b)
{
	return std::fabs(a - b) < 1e-5f;
}


bool HasRGBA(cxx::OOColor *c, float r, float g, float b, float a)
{
	return c != nullptr && Near(c->redComponent(), r) && Near(c->greenComponent(), g) && Near(c->blueComponent(), b) && Near(c->alphaComponent(), a);
}


oo::PList Dict(std::initializer_list<std::pair<const char *, oo::PList>> entries)
{
	oo::PList::Dict dict;
	for (const auto &[key, value] : entries)  dict[key] = value;
	return oo::PList(std::move(dict));
}

}	// namespace


OO_TEST(factoriesAndComponents)
{
	OO_CHECK(HasRGBA(cxx::OOColor::colorWithRed(0.25f, 0.5f, 0.75f, 1.0f).get(), 0.25f, 0.5f, 0.75f, 1.0f));
	OO_CHECK(HasRGBA(cxx::OOColor::colorWithWhite(0.5f, 0.25f).get(), 0.5f, 0.5f, 0.5f, 0.25f));
	OO_CHECK(HasRGBA(cxx::OOColor::colorWithRGBAComponents({ 0.1f, 0.2f, 0.3f, 0.4f }).get(), 0.1f, 0.2f, 0.3f, 0.4f));
	OO_CHECK(HasRGBA(cxx::OOColor::colorWithHue(0.0f, 1.0f, 1.0f, 1.0f).get(), 1.0f, 0.0f, 0.0f, 1.0f));
	OO_CHECK(HasRGBA(cxx::OOColor::colorWithHue(0.5f, 1.0f, 1.0f, 0.5f).get(), 0.0f, 1.0f, 1.0f, 0.5f));
	OO_CHECK(HasRGBA(cxx::OOColor::colorWithHue(0.25f, 0.0f, 0.4f, 1.0f).get(), 0.4f, 0.4f, 0.4f, 1.0f));	// grey: s == 0
	OO_CHECK(HasRGBA(cxx::OOColor::colorWithHSBAComponents({ 240.0f, 1.0f, 1.0f, 1.0f }).get(), 0.0f, 0.0f, 1.0f, 1.0f));

	oo::Ref<cxx::OOColor> c = cxx::OOColor::colorWithRed(0.2f, 0.4f, 0.6f, 0.8f);
	float r, g, b, a;
	c->getRed(&r, &g, &b, &a);
	OO_CHECK(Near(r, 0.2f) && Near(g, 0.4f) && Near(b, 0.6f) && Near(a, 0.8f));
	OORGBAComponents rgba = c->rgbaComponents();
	OO_CHECK(rgba.r == r && rgba.g == g && rgba.b == b && rgba.a == a);
	std::vector<float> array = c->normalizedArray();
	OO_CHECK(array == std::vector<float>({ r, g, b, a }));
}


OO_TEST(namedColours)
{
	OO_CHECK(HasRGBA(cxx::OOColor::blackColor().get(), 0, 0, 0, 1));
	OO_CHECK(HasRGBA(cxx::OOColor::darkGrayColor().get(), 1.0f/3.0f, 1.0f/3.0f, 1.0f/3.0f, 1));
	OO_CHECK(HasRGBA(cxx::OOColor::lightGrayColor().get(), 2.0f/3.0f, 2.0f/3.0f, 2.0f/3.0f, 1));
	OO_CHECK(HasRGBA(cxx::OOColor::whiteColor().get(), 1, 1, 1, 1));
	OO_CHECK(HasRGBA(cxx::OOColor::grayColor().get(), 0.5f, 0.5f, 0.5f, 1));
	OO_CHECK(HasRGBA(cxx::OOColor::redColor().get(), 1, 0, 0, 1));
	OO_CHECK(HasRGBA(cxx::OOColor::greenColor().get(), 0, 1, 0, 1));
	OO_CHECK(HasRGBA(cxx::OOColor::blueColor().get(), 0, 0, 1, 1));
	OO_CHECK(HasRGBA(cxx::OOColor::cyanColor().get(), 0, 1, 1, 1));
	OO_CHECK(HasRGBA(cxx::OOColor::yellowColor().get(), 1, 1, 0, 1));
	OO_CHECK(HasRGBA(cxx::OOColor::magentaColor().get(), 1, 0, 1, 1));
	OO_CHECK(HasRGBA(cxx::OOColor::orangeColor().get(), 1, 0.5f, 0, 1));
	OO_CHECK(HasRGBA(cxx::OOColor::purpleColor().get(), 0.5f, 0, 0.5f, 1));
	OO_CHECK(HasRGBA(cxx::OOColor::brownColor().get(), 0.6f, 0.4f, 0.2f, 1));
	OO_CHECK(HasRGBA(cxx::OOColor::clearColor().get(), 0, 0, 0, 0));
	OO_CHECK(cxx::OOColor::blackColor()->isBlack());
	OO_CHECK(cxx::OOColor::clearColor()->isBlack());
	OO_CHECK(cxx::OOColor::whiteColor()->isWhite());
	OO_CHECK(!cxx::OOColor::colorWithWhite(1.0f, 0.5f)->isWhite());
}


OO_TEST(hueSaturationBrightness)
{
	oo::Ref<cxx::OOColor> c = cxx::OOColor::colorWithRed(0.0f, 0.5f, 1.0f, 0.25f);
	float h, s, b, a;
	c->getHue(&h, &s, &b, &a);
	OO_CHECK(Near(h, c->hueComponent()) && Near(s, c->saturationComponent()) && Near(b, c->brightnessComponent()));
	OO_CHECK(Near(a, 0.25f) && Near(s, 1.0f) && Near(b, 1.0f));
	OO_CHECK(std::fabs(h - 210.0f) < 0.05f);	// 0..360, with the 0.0001 delta bias
	OOHSBAComponents hsba = c->hsbaComponents();
	OO_CHECK(hsba.h == h && hsba.s == s && hsba.b == b && hsba.a == a);
	OO_CHECK_EQ(cxx::OOColor::blackColor()->saturationComponent(), 0.0f);
}


OO_TEST(colorFromString)
{
	OO_CHECK(HasRGBA(cxx::OOColor::colorFromString("1 0.5 0").get(), 1, 0.5f, 0, 1));
	OO_CHECK(HasRGBA(cxx::OOColor::colorFromString("0.1 0.2 0.3 0.4").get(), 0.1f, 0.2f, 0.3f, 0.4f));
	OO_CHECK(HasRGBA(cxx::OOColor::colorFromString("255 0 51").get(), 1, 0, 0.2f, 1));	// 0..255, alpha rescaled
	OO_CHECK(HasRGBA(cxx::OOColor::colorFromString("255 0 51 102").get(), 1, 0, 0.2f, 0.4f));
	OO_CHECK(cxx::OOColor::colorFromString("0.1 0.2") == nullptr);
	OO_CHECK(cxx::OOColor::colorFromString("red") == nullptr);
}


OO_TEST(colorWithDescription)
{
	OO_CHECK(cxx::OOColor::colorWithDescription(oo::PList()) == nullptr);
	OO_CHECK(cxx::OOColor::colorWithDescription(oo::PList(true)) == nullptr);

	// A string: a named colour, or components.
	OO_CHECK(HasRGBA(cxx::OOColor::colorWithDescription(oo::PList(std::string("magentaColor"))).get(), 1, 0, 1, 1));
	OO_CHECK(cxx::OOColor::colorWithDescription(oo::PList(std::string("fooColor"))) == nullptr);
	OO_CHECK(cxx::OOColor::colorWithDescription(oo::PList(std::string("Color"))) == nullptr);
	OO_CHECK(HasRGBA(cxx::OOColor::colorWithDescription(oo::PList(std::string("0 0 1"))).get(), 0, 0, 1, 1));

	// An array: its elements' descriptions joined with spaces.
	oo::PList::Array components = { oo::PList(std::string("0.5")), oo::PList(std::int64_t(1)), oo::PList(0.25) };
	OO_CHECK(HasRGBA(cxx::OOColor::colorWithDescription(oo::PList(components)).get(), 0.5f, 1, 0.25f, 1));

	// A dictionary: HSB(A) when it has a hue, else RGB(A); alpha, or else opacity.
	OO_CHECK(HasRGBA(cxx::OOColor::colorWithDescription(Dict({ { "hue", oo::PList(120.0) }, { "value", oo::PList(0.5) }, { "opacity", oo::PList(0.5) } })).get(), 0, 0.5f, 0, 0.5f));
	OO_CHECK(HasRGBA(cxx::OOColor::colorWithDescription(Dict({ { "red", oo::PList(0.5) }, { "blue", oo::PList(1.0) } })).get(), 0.5f, 0, 1, 1));
	OO_CHECK(HasRGBA(cxx::OOColor::colorWithDescription(Dict({ { "green", oo::PList(1.0) }, { "alpha", oo::PList(0.5) }, { "opacity", oo::PList(0.25) } })).get(), 0, 1, 0, 0.5f));

	// The saturation factor: applied to any description, and to a HSB dictionary's own saturation.
	oo::Ref<cxx::OOColor> desaturated = cxx::OOColor::colorWithDescription(oo::PList(std::string("redColor")), 0.5f);
	OO_CHECK(Near(desaturated->saturationComponent(), 0.5f) && Near(desaturated->brightnessComponent(), 1.0f));
	oo::Ref<cxx::OOColor> scaled = cxx::OOColor::colorWithDescription(Dict({ { "hue", oo::PList(0.0) }, { "saturation", oo::PList(0.8) } }), 0.5f);
	OO_CHECK(Near(scaled->saturationComponent(), 0.4f));

	// Bright: at least 0.5 brightness, alpha forced to 1; bright enough is returned as is.
	oo::Ref<cxx::OOColor> bright = cxx::OOColor::brightColorWithDescription(oo::PList(std::string("0 0 0.25 0.5")));
	OO_CHECK(Near(bright->brightnessComponent(), 0.5f) && Near(bright->alphaComponent(), 1.0f));
	OO_CHECK(HasRGBA(cxx::OOColor::brightColorWithDescription(oo::PList(std::string("0 0.75 0 0.5"))).get(), 0, 0.75f, 0, 0.5f));
	OO_CHECK(cxx::OOColor::brightColorWithDescription(oo::PList()) == nullptr);
}


OO_TEST(derivedColours)
{
	oo::Ref<cxx::OOColor> opaque = cxx::OOColor::colorWithRed(0.5f, 0.5f, 0.5f, 1.0f);
	OO_CHECK(opaque->premultipliedColor() == opaque);	// itself, as before
	OO_CHECK(HasRGBA(cxx::OOColor::colorWithRed(0.5f, 1.0f, 0.2f, 0.5f)->premultipliedColor().get(), 0.25f, 0.5f, 0.1f, 1.0f));
	OO_CHECK(HasRGBA(cxx::OOColor::colorWithRed(0.5f, 0.8f, 0.1f, 0.3f)->colorWithBrightnessFactor(2.0f).get(), 1.0f, 1.0f, 0.2f, 0.3f));
	OO_CHECK(HasRGBA(cxx::OOColor::blackColor()->blendedColorWithFraction(0.25f, cxx::OOColor::whiteColor().get()).get(), 0.25f, 0.25f, 0.25f, 1.0f));
}


OO_TEST(text)
{
	oo::Ref<cxx::OOColor> c = cxx::OOColor::colorWithRed(1.0f, 0.5f, 0.0f, 1.0f);
	OO_CHECK(c->descriptionComponents() == std::optional<std::string>("1, 0.5, 0, 1"));
	OO_CHECK(c->rgbaDescription() == std::optional<std::string>("{1, 0.5, 0, 1}"));
	OO_CHECK(cxx::OOColor::redColor()->hsbaDescription() == std::optional<std::string>("{0, 1, 1, 1}"));
	OO_CHECK_EQ(OORGBAComponentsDescription({ 0.12345f, 1, 0, 0.5f }), std::string("{0.123, 1, 0, 0.5}"));
	OO_CHECK_EQ(OOHSBAComponentsDescription({ 359.9f, 1, 0.5f, 1 }), std::string("{359, 1, 0.5, 1}"));
}


OO_TEST(facadeForwards)
{
	@autoreleasepool
	{
		OOColor *red = [OOColor redColor];
		OO_CHECK([red isKindOfClass:[OOColor class]]);
		OO_CHECK([red redComponent] == 1.0f && [red greenComponent] == 0.0f && [red alphaComponent] == 1.0f);
		OO_CHECK([red cxx_normalizedArray] == std::vector<float>({ 1, 0, 0, 1 }));
		OO_CHECK([red cxx_rgbaDescription] == std::optional<std::string>("{1, 0, 0, 1}"));
		OO_CHECK(HasRGBA(oo::ToCxx([OOColor cxx_colorWithDescription:oo::PList(std::string("0 1 0"))]), 0, 1, 0, 1));
		OO_CHECK([OOColor cxx_colorWithDescription:oo::PList(std::string("nonsense"))] == nil);
		OO_CHECK([OOColor cxx_colorWithDescription:oo::PList()] == nil);
		OO_CHECK(HasRGBA(oo::ToCxx([red blendedColorWithFraction:0.5f ofColor:[OOColor blueColor]]), 0.5f, 0, 0.5f, 1));

		std::string text = oo::DescriptionOf(red);
		OO_CHECK(text.starts_with("<OOColor 0x") && text.ends_with(">{1, 0, 0, 1}"));
	}
}


OO_TEST(facadeNilStaysNil)
{
	OOColor *none = nil;
	OO_CHECK(oo::ToCxx(none) == nullptr);
	OO_CHECK(oo::ToObjC(static_cast<cxx::OOColor *>(nullptr)) == nil);
	OO_CHECK([none redComponent] == 0.0f);
	OO_CHECK([none cxx_normalizedArray].empty());
	OO_CHECK(![none cxx_rgbaDescription].has_value());
	OO_CHECK([none premultipliedColor] == nil);
}


OO_TEST(facadeIdentity)
{
	@autoreleasepool
	{
		OOColor *opaque = [OOColor colorWithRed:0.5f green:0.5f blue:0.5f alpha:1.0f];
		OO_CHECK(oo::ToObjC(oo::ToCxx(opaque)) == opaque);
		OO_CHECK([opaque premultipliedColor] == opaque);	// returned itself before the conversion
		OO_CHECK([[opaque copy] autorelease] == opaque);	// copy is retain (immutable)

		// An Object node's colour comes back as the same object.
		oo::PList node = oo::PListObject(opaque);
		OO_CHECK([OOColor cxx_colorWithDescription:node] == opaque);
		OO_CHECK(cxx::OOColor::colorWithDescription(node).get() == oo::ToCxx(opaque));

		// A C++ colour crosses to one facade, and back to itself.
		oo::Ref<cxx::OOColor> cxxColor = cxx::OOColor::cyanColor();
		OOColor *facade = oo::ToObjC(cxxColor);
		OO_CHECK(facade != nil && facade == oo::ToObjC(cxxColor.get()));
		OO_CHECK(oo::ToCxx(facade) == cxxColor.get());
		OO_CHECK([OOColor redColor] != [OOColor redColor]);	// distinct objects, as before
	}
}


OO_TEST_MAIN()
