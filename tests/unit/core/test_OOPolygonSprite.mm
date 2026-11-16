/*	test_OOPolygonSprite.mm
	Unit tests for OOPolygonSprite (src/Core/OOPolygonSprite.h): bead oo-4111 (Phase 3, house style
	of proposed ADR-0056). Bead oo-9ht.30 deleted its Objective-C facade: the cases ask the C++
	class, and the facade's contract cases went with it (standing approval oo-9n5p9).

	It links the whole game but main (tests/unit/core/meson.build entry ['*']: the sprite reaches
	the graphics reset manager, the extension manager and, in debug builds, the resource manager).
	There is no GL context, so nothing is drawn: the sprite's tesselation (GLU) runs at creation and
	is observable as success or nil. The expectations were written against the Objective-C API and
	run on the unconverted class first: which data arrays make a sprite (flat pairs, arrays of
	contours, clockwise, duplicate and non-finite vertices) and which answer nil (no contours), the
	description (the debug name), and what the class answers to (the graphics reset client's
	-resetGraphicsState, and the HUD's beacon icon category; the C++ interfaces OOGraphicsResetClient
	and OOHUDBeaconIcon since beads oo-9ht.23 and oo-7ae4p).
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


oo::Ref<OOPolygonSprite> Sprite(const oo::PList &data, const char *name)
{
	return OOPolygonSprite::initWithDataArray(data, 0.5f, name);
}

}	// namespace


OO_TEST(dataArraysThatMakeASprite)
{
	@autoreleasepool
	{
		const oo::PList square = Numbers({ 0, 0, 1, 0, 1, 1, 0, 1 });
		OO_CHECK(Sprite(square, "flat") != nullptr);											// one contour as flat pairs
		OO_CHECK(Sprite(Contours({ square }), "contours") != nullptr);							// array of contours
		OO_CHECK(Sprite(Numbers({ 0, 0, 0, 1, 1, 1, 1, 0 }), "clockwise") != nullptr);			// flipped
		OO_CHECK(Sprite(Numbers({ 0, 0, 0, 0, 1, 0, 1, 1, 0, 1, 0, 0 }), "duplicates") != nullptr);
		const double nan = std::numeric_limits<double>::quiet_NaN();
		const double inf = std::numeric_limits<double>::infinity();
		OO_CHECK(Sprite(Numbers({ 0, 0, nan, 1, 1, 0, inf, 3, 1, 1, 0, 1 }), "non-finite") != nullptr);
		OO_CHECK(Sprite(Contours({ square, Numbers({ 0.25, 0.25, 0.75, 0.25, 0.75, 0.75 }) }), "two") != nullptr);
		OO_CHECK(Sprite(Numbers({ 0, 0, 1, 0 }), "degenerate") != nullptr);						// no area: nothing to fill
	}
}


OO_TEST(emptyDataAnswersNil)
{
	@autoreleasepool
	{
		OO_CHECK(Sprite(oo::PList(oo::PList::Array()), "empty") == nullptr);
		OO_CHECK(OOPolygonSprite::initWithDataArray(oo::PList(), 1.0f, "null") == nullptr);
	}
}


OO_TEST(descriptionAndProtocols)
{
	@autoreleasepool
	{
		oo::Ref<OOPolygonSprite> sprite = Sprite(Numbers({ 0, 0, 1, 0, 1, 1 }), "triangle");
		std::string text = sprite->description();
		OO_CHECK(text.starts_with("<OOPolygonSprite 0x"));
#ifndef NDEBUG
		OO_CHECK(text.ends_with(">{triangle}"));
#endif
		// The protocols are C++ interfaces (beads oo-9ht.23, oo-7ae4p); drawFilled/drawOutline are members.
		OO_CHECK(dynamic_cast<OOHUDBeaconIcon *>(sprite.get()) != nullptr);
		OOGraphicsResetClient *client = dynamic_cast<OOGraphicsResetClient *>(sprite.get());
		OO_CHECK(client != nullptr);
		client->resetGraphicsState();	// no buffers made yet: nothing to delete
	}
}


OO_TEST(cxxSprite)
{
	oo::Ref<OOPolygonSprite> sprite = OOPolygonSprite::initWithDataArray(Numbers({ 0, 0, 1, 0, 1, 1, 0, 1 }), 0.5f, "square");
	OO_CHECK(sprite.get() != nullptr);
#ifndef NDEBUG
	OO_CHECK(sprite->descriptionComponents() == std::optional<std::string>("square"));
#endif
	sprite->resetGraphicsState();
	OO_CHECK(OOPolygonSprite::initWithDataArray(oo::PList(oo::PList::Array()), 0.5f, "empty").get() == nullptr);
}


OO_TEST_MAIN()
