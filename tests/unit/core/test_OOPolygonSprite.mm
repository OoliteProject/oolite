/*	test_OOPolygonSprite.mm
	Unit tests for cxx::OOPolygonSprite (src/Core/OOPolygonSprite.h) and its Objective-C facade
	(OOPolygonSprite+ObjCBridge.h): bead oo-4111 (Phase 3, house style of proposed ADR-0056).

	It links the whole game but main (tests/unit/core/meson.build entry ['*']: the sprite reaches
	the graphics reset manager, the extension manager and, in debug builds, the resource manager).
	There is no GL context, so nothing is drawn: the sprite's tesselation (GLU) runs at creation and
	is observable as success or nil. The expectations were written against the Objective-C API and
	run on the unconverted class first: which data arrays make a sprite (flat pairs, arrays of
	contours, clockwise, duplicate and non-finite vertices) and which answer nil (no contours), the
	description (the debug name), and what the class answers to (the graphics reset client's
	-resetGraphicsState, and the HUD's beacon icon category). The last tests pin the facade's
	contract.
	Run: bash tools/check-core-tests.sh
*/

#import "OOPolygonSprite.h"
#import "OOGraphicsResetManager.h"
#import "OODescription.h"

#include "oo_test.hpp"

#include <cmath>
#include <limits>


// main.mm defines the debug flags, and the test has its own main.
#ifndef NDEBUG
uint32_t gDebugFlags = 0;
#endif


namespace {

oo::PList Numbers(std::initializer_list<double> values)
{
	oo::PList::Array array;
	for (double v : values)  array.push_back(oo::PList(v));
	return oo::PList(std::move(array));
}


oo::PList Contours(std::initializer_list<oo::PList> contours)
{
	return oo::PList(oo::PList::Array(contours));
}


OOPolygonSprite *Sprite(const oo::PList &data, const char *name)
{
	return [[[OOPolygonSprite alloc] initWithDataArray:data outlineWidth:0.5f name:name] autorelease];
}

}	// namespace


OO_TEST(dataArraysThatMakeASprite)
{
	@autoreleasepool
	{
		const oo::PList square = Numbers({ 0, 0, 1, 0, 1, 1, 0, 1 });
		OO_CHECK(Sprite(square, "flat") != nil);											// one contour as flat pairs
		OO_CHECK(Sprite(Contours({ square }), "contours") != nil);							// array of contours
		OO_CHECK(Sprite(Numbers({ 0, 0, 0, 1, 1, 1, 1, 0 }), "clockwise") != nil);			// flipped
		OO_CHECK(Sprite(Numbers({ 0, 0, 0, 0, 1, 0, 1, 1, 0, 1, 0, 0 }), "duplicates") != nil);
		const double nan = std::numeric_limits<double>::quiet_NaN();
		const double inf = std::numeric_limits<double>::infinity();
		OO_CHECK(Sprite(Numbers({ 0, 0, nan, 1, 1, 0, inf, 3, 1, 1, 0, 1 }), "non-finite") != nil);
		OO_CHECK(Sprite(Contours({ square, Numbers({ 0.25, 0.25, 0.75, 0.25, 0.75, 0.75 }) }), "two") != nil);
		OO_CHECK(Sprite(Numbers({ 0, 0, 1, 0 }), "degenerate") != nil);						// no area: nothing to fill
	}
}


OO_TEST(emptyDataAnswersNil)
{
	@autoreleasepool
	{
		OO_CHECK(Sprite(oo::PList(oo::PList::Array()), "empty") == nil);
		OO_CHECK([[OOPolygonSprite alloc] initWithDataArray:oo::PList() outlineWidth:1.0f name:"null"] == nil);
	}
}


OO_TEST(descriptionAndProtocols)
{
	@autoreleasepool
	{
		OOPolygonSprite *sprite = Sprite(Numbers({ 0, 0, 1, 0, 1, 1 }), "triangle");
		std::string text = oo::DescriptionOf(sprite);
		OO_CHECK(text.starts_with("<OOPolygonSprite 0x"));
#ifndef NDEBUG
		OO_CHECK(text.ends_with(">{triangle}"));
#endif
		OO_CHECK([sprite conformsToProtocol:@protocol(OOHUDBeaconIcon)]);
		OO_CHECK([sprite respondsToSelector:@selector(resetGraphicsState)]);
		OO_CHECK([sprite respondsToSelector:@selector(oo_drawHUDBeaconIconAt:size:alpha:z:)]);
		OO_CHECK([sprite respondsToSelector:@selector(drawFilled)] && [sprite respondsToSelector:@selector(drawOutline)]);
		[(id<OOGraphicsResetClient>)sprite resetGraphicsState];	// no buffers made yet: nothing to delete
	}
}


OO_TEST(cxxSprite)
{
	oo::Ref<cxx::OOPolygonSprite> sprite = cxx::OOPolygonSprite::initWithDataArray(Numbers({ 0, 0, 1, 0, 1, 1, 0, 1 }), 0.5f, "square");
	OO_CHECK(sprite.get() != nullptr);
#ifndef NDEBUG
	OO_CHECK(sprite->descriptionComponents() == std::optional<std::string>("square"));
#endif
	sprite->resetGraphicsState();
	OO_CHECK(cxx::OOPolygonSprite::initWithDataArray(oo::PList(oo::PList::Array()), 0.5f, "empty").get() == nullptr);
}


OO_TEST(facadeNilStaysNil)
{
	OOPolygonSprite *none = nil;
	OO_CHECK(oo::ToCxx(none) == nullptr);
	OO_CHECK(oo::ToObjC(static_cast<cxx::OOPolygonSprite *>(nullptr)) == nil);
	[none drawFilled];	// nothing, as a message to nil did
}


OO_TEST(facadeIdentity)
{
	@autoreleasepool
	{
		OOPolygonSprite *made = Sprite(Numbers({ 0, 0, 1, 0, 1, 1 }), "made");
		OO_CHECK(oo::ToCxx(made) != nullptr && oo::ToObjC(oo::ToCxx(made)) == made);

		oo::Ref<cxx::OOPolygonSprite> sprite = cxx::OOPolygonSprite::initWithDataArray(Numbers({ 0, 0, 1, 0, 1, 1 }), 0.5f, "crossed");
		OOPolygonSprite *facade = oo::ToObjC(sprite);
		OO_CHECK(facade != nil && facade == oo::ToObjC(sprite.get()));
		OO_CHECK(oo::ToCxx(facade) == sprite.get());
		OO_CHECK([facade respondsToSelector:@selector(oo_drawHUDBeaconIconAt:size:alpha:z:)]);
		OO_CHECK(Sprite(Numbers({ 0, 0, 1, 0, 1, 1 }), "a") != Sprite(Numbers({ 0, 0, 1, 0, 1, 1 }), "b"));
	}
}


OO_TEST_MAIN()
