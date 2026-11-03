/*	test_OOColor.mm
	Unit tests for OOColor (src/Core/OOColor.h) and, until bead oo-9ht.1 deleted it, its
	Objective-C facade (OOColor+ObjCBridge.h): bead oo-11m, the Phase 3 house-style exemplar
	(proposed ADR-0056).

	A converted class's test lives in tests/unit/core/test_<Class>.mm and links the game's own
	objects for the class, its bridge and what they need (tests/unit/core/meson.build), so it
	tests exactly what the game runs. It pins what the class computed before the conversion, from
	the Objective-C bodies: component arithmetic, the four description forms, the text, and what
	the facade's selectors answered, now asked of the C++ colour (its crossing, nil and identity
	cases went with it). Run: bash tools/check-core-tests.sh
*/

#import "OOColor.h"

#include "oo_test.hpp"

#include <cmath>


namespace {

bool Near(float a, float b)
{
	return std::fabs(a - b) < 1e-5f;
}


bool HasRGBA(OOColor *c, float r, float g, float b, float a)
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
	OO_CHECK(HasRGBA(OOColor::colorWithRed(0.25f, 0.5f, 0.75f, 1.0f).get(), 0.25f, 0.5f, 0.75f, 1.0f));
	OO_CHECK(HasRGBA(OOColor::colorWithWhite(0.5f, 0.25f).get(), 0.5f, 0.5f, 0.5f, 0.25f));
	OO_CHECK(HasRGBA(OOColor::colorWithRGBAComponents({ 0.1f, 0.2f, 0.3f, 0.4f }).get(), 0.1f, 0.2f, 0.3f, 0.4f));
	OO_CHECK(HasRGBA(OOColor::colorWithHue(0.0f, 1.0f, 1.0f, 1.0f).get(), 1.0f, 0.0f, 0.0f, 1.0f));
	OO_CHECK(HasRGBA(OOColor::colorWithHue(0.5f, 1.0f, 1.0f, 0.5f).get(), 0.0f, 1.0f, 1.0f, 0.5f));
	OO_CHECK(HasRGBA(OOColor::colorWithHue(0.25f, 0.0f, 0.4f, 1.0f).get(), 0.4f, 0.4f, 0.4f, 1.0f));	// grey: s == 0
	OO_CHECK(HasRGBA(OOColor::colorWithHSBAComponents({ 240.0f, 1.0f, 1.0f, 1.0f }).get(), 0.0f, 0.0f, 1.0f, 1.0f));

	oo::Ref<OOColor> c = OOColor::colorWithRed(0.2f, 0.4f, 0.6f, 0.8f);
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
	OO_CHECK(HasRGBA(OOColor::blackColor().get(), 0, 0, 0, 1));
	OO_CHECK(HasRGBA(OOColor::darkGrayColor().get(), 1.0f/3.0f, 1.0f/3.0f, 1.0f/3.0f, 1));
	OO_CHECK(HasRGBA(OOColor::lightGrayColor().get(), 2.0f/3.0f, 2.0f/3.0f, 2.0f/3.0f, 1));
	OO_CHECK(HasRGBA(OOColor::whiteColor().get(), 1, 1, 1, 1));
	OO_CHECK(HasRGBA(OOColor::grayColor().get(), 0.5f, 0.5f, 0.5f, 1));
	OO_CHECK(HasRGBA(OOColor::redColor().get(), 1, 0, 0, 1));
	OO_CHECK(HasRGBA(OOColor::greenColor().get(), 0, 1, 0, 1));
	OO_CHECK(HasRGBA(OOColor::blueColor().get(), 0, 0, 1, 1));
	OO_CHECK(HasRGBA(OOColor::cyanColor().get(), 0, 1, 1, 1));
	OO_CHECK(HasRGBA(OOColor::yellowColor().get(), 1, 1, 0, 1));
	OO_CHECK(HasRGBA(OOColor::magentaColor().get(), 1, 0, 1, 1));
	OO_CHECK(HasRGBA(OOColor::orangeColor().get(), 1, 0.5f, 0, 1));
	OO_CHECK(HasRGBA(OOColor::purpleColor().get(), 0.5f, 0, 0.5f, 1));
	OO_CHECK(HasRGBA(OOColor::brownColor().get(), 0.6f, 0.4f, 0.2f, 1));
	OO_CHECK(HasRGBA(OOColor::clearColor().get(), 0, 0, 0, 0));
	OO_CHECK(OOColor::blackColor()->isBlack());
	OO_CHECK(OOColor::clearColor()->isBlack());
	OO_CHECK(OOColor::whiteColor()->isWhite());
	OO_CHECK(!OOColor::colorWithWhite(1.0f, 0.5f)->isWhite());
}


OO_TEST(hueSaturationBrightness)
{
	oo::Ref<OOColor> c = OOColor::colorWithRed(0.0f, 0.5f, 1.0f, 0.25f);
	float h, s, b, a;
	c->getHue(&h, &s, &b, &a);
	OO_CHECK(Near(h, c->hueComponent()) && Near(s, c->saturationComponent()) && Near(b, c->brightnessComponent()));
	OO_CHECK(Near(a, 0.25f) && Near(s, 1.0f) && Near(b, 1.0f));
	OO_CHECK(std::fabs(h - 210.0f) < 0.05f);	// 0..360, with the 0.0001 delta bias
	OOHSBAComponents hsba = c->hsbaComponents();
	OO_CHECK(hsba.h == h && hsba.s == s && hsba.b == b && hsba.a == a);
	OO_CHECK_EQ(OOColor::blackColor()->saturationComponent(), 0.0f);
}


OO_TEST(colorFromString)
{
	OO_CHECK(HasRGBA(OOColor::colorFromString("1 0.5 0").get(), 1, 0.5f, 0, 1));
	OO_CHECK(HasRGBA(OOColor::colorFromString("0.1 0.2 0.3 0.4").get(), 0.1f, 0.2f, 0.3f, 0.4f));
	OO_CHECK(HasRGBA(OOColor::colorFromString("255 0 51").get(), 1, 0, 0.2f, 1));	// 0..255, alpha rescaled
	OO_CHECK(HasRGBA(OOColor::colorFromString("255 0 51 102").get(), 1, 0, 0.2f, 0.4f));
	OO_CHECK(OOColor::colorFromString("0.1 0.2") == nullptr);
	OO_CHECK(OOColor::colorFromString("red") == nullptr);
}


OO_TEST(colorWithDescription)
{
	OO_CHECK(OOColor::colorWithDescription(oo::PList()) == nullptr);
	OO_CHECK(OOColor::colorWithDescription(oo::PList(true)) == nullptr);

	// A string: a named colour, or components.
	OO_CHECK(HasRGBA(OOColor::colorWithDescription(oo::PList(std::string("magentaColor"))).get(), 1, 0, 1, 1));
	OO_CHECK(OOColor::colorWithDescription(oo::PList(std::string("fooColor"))) == nullptr);
	OO_CHECK(OOColor::colorWithDescription(oo::PList(std::string("Color"))) == nullptr);
	OO_CHECK(HasRGBA(OOColor::colorWithDescription(oo::PList(std::string("0 0 1"))).get(), 0, 0, 1, 1));

	// An array: its elements' descriptions joined with spaces.
	oo::PList::Array components = { oo::PList(std::string("0.5")), oo::PList(std::int64_t(1)), oo::PList(0.25) };
	OO_CHECK(HasRGBA(OOColor::colorWithDescription(oo::PList(components)).get(), 0.5f, 1, 0.25f, 1));

	// A dictionary: HSB(A) when it has a hue, else RGB(A); alpha, or else opacity.
	OO_CHECK(HasRGBA(OOColor::colorWithDescription(Dict({ { "hue", oo::PList(120.0) }, { "value", oo::PList(0.5) }, { "opacity", oo::PList(0.5) } })).get(), 0, 0.5f, 0, 0.5f));
	OO_CHECK(HasRGBA(OOColor::colorWithDescription(Dict({ { "red", oo::PList(0.5) }, { "blue", oo::PList(1.0) } })).get(), 0.5f, 0, 1, 1));
	OO_CHECK(HasRGBA(OOColor::colorWithDescription(Dict({ { "green", oo::PList(1.0) }, { "alpha", oo::PList(0.5) }, { "opacity", oo::PList(0.25) } })).get(), 0, 1, 0, 0.5f));

	// The saturation factor: applied to any description, and to a HSB dictionary's own saturation.
	oo::Ref<OOColor> desaturated = OOColor::colorWithDescription(oo::PList(std::string("redColor")), 0.5f);
	OO_CHECK(Near(desaturated->saturationComponent(), 0.5f) && Near(desaturated->brightnessComponent(), 1.0f));
	oo::Ref<OOColor> scaled = OOColor::colorWithDescription(Dict({ { "hue", oo::PList(0.0) }, { "saturation", oo::PList(0.8) } }), 0.5f);
	OO_CHECK(Near(scaled->saturationComponent(), 0.4f));

	// Bright: at least 0.5 brightness, alpha forced to 1; bright enough is returned as is.
	oo::Ref<OOColor> bright = OOColor::brightColorWithDescription(oo::PList(std::string("0 0 0.25 0.5")));
	OO_CHECK(Near(bright->brightnessComponent(), 0.5f) && Near(bright->alphaComponent(), 1.0f));
	OO_CHECK(HasRGBA(OOColor::brightColorWithDescription(oo::PList(std::string("0 0.75 0 0.5"))).get(), 0, 0.75f, 0, 0.5f));
	OO_CHECK(OOColor::brightColorWithDescription(oo::PList()) == nullptr);
}


OO_TEST(derivedColours)
{
	oo::Ref<OOColor> opaque = OOColor::colorWithRed(0.5f, 0.5f, 0.5f, 1.0f);
	OO_CHECK(opaque->premultipliedColor() == opaque);	// itself, as before
	OO_CHECK(HasRGBA(OOColor::colorWithRed(0.5f, 1.0f, 0.2f, 0.5f)->premultipliedColor().get(), 0.25f, 0.5f, 0.1f, 1.0f));
	OO_CHECK(HasRGBA(OOColor::colorWithRed(0.5f, 0.8f, 0.1f, 0.3f)->colorWithBrightnessFactor(2.0f).get(), 1.0f, 1.0f, 0.2f, 0.3f));
	OO_CHECK(HasRGBA(OOColor::blackColor()->blendedColorWithFraction(0.25f, OOColor::whiteColor().get()).get(), 0.25f, 0.25f, 0.25f, 1.0f));
}


OO_TEST(text)
{
	oo::Ref<OOColor> c = OOColor::colorWithRed(1.0f, 0.5f, 0.0f, 1.0f);
	OO_CHECK(c->descriptionComponents() == std::optional<std::string>("1, 0.5, 0, 1"));
	OO_CHECK(c->rgbaDescription() == std::optional<std::string>("{1, 0.5, 0, 1}"));
	OO_CHECK(OOColor::redColor()->hsbaDescription() == std::optional<std::string>("{0, 1, 1, 1}"));
	OO_CHECK_EQ(OORGBAComponentsDescription({ 0.12345f, 1, 0, 0.5f }), std::string("{0.123, 1, 0, 0.5}"));
	OO_CHECK_EQ(OOHSBAComponentsDescription({ 359.9f, 1, 0.5f, 1 }), std::string("{359, 1, 0.5, 1}"));
}


OO_TEST(facadeForwards)
{
	@autoreleasepool
	{
		// What the facade's selectors answered, asked of the C++ colour since bead oo-9ht.1 deleted
		// the facade (its -isKindOfClass: check went with it).
		oo::Ref<OOColor> red = OOColor::redColor();
		OO_CHECK(red->redComponent() == 1.0f && red->greenComponent() == 0.0f && red->alphaComponent() == 1.0f);
		OO_CHECK(red->normalizedArray() == std::vector<float>({ 1, 0, 0, 1 }));
		OO_CHECK(red->rgbaDescription() == std::optional<std::string>("{1, 0, 0, 1}"));
		OO_CHECK(HasRGBA(OOColor::colorWithDescription(oo::PList(std::string("0 1 0"))).get(), 0, 1, 0, 1));
		OO_CHECK(OOColor::colorWithDescription(oo::PList(std::string("nonsense"))) == nullptr);
		OO_CHECK(OOColor::colorWithDescription(oo::PList()) == nullptr);
		OO_CHECK(HasRGBA(red->blendedColorWithFraction(0.5f, OOColor::blueColor().get()).get(), 0.5f, 0, 0.5f, 1));

		std::string text = red->description();	// what "%@" printed for the facade
		OO_CHECK(text.starts_with("<OOColor 0x") && text.ends_with(">{1, 0, 0, 1}"));
	}
}


OO_TEST(facadeIdentity)
{
	@autoreleasepool
	{
		oo::Ref<OOColor> opaque = OOColor::colorWithRed(0.5f, 0.5f, 0.5f, 1.0f);
		OO_CHECK(opaque->premultipliedColor() == opaque);	// returned itself before the conversion

		// An Object node's colour comes back as the same object (the colour is the node's foreign
		// object since bead oo-9ht.1).
		oo::PList node = OOColorObjectNode(opaque.get());
		OO_CHECK(OOColor::colorWithDescription(node) == opaque);
		OO_CHECK(OOColor::colorWithDescription(node).get() == opaque.get());
		OO_CHECK(OOColorInObjectNode(node) == opaque.get());
		OO_CHECK(node.getIf<oo::PList::Object>()->get()->className() == "OOColor");
		OO_CHECK(OOColor::redColor() != OOColor::redColor());	// distinct objects, as before
	}
}


OO_TEST_MAIN()
