/*	test_SkyEntity.mm
	Unit tests for SkyEntity (src/Core/Entities/SkyEntity.h), the star field and nebulae behind a
	system: bead oo-sxgm, a leaf of the Entities seam under OOEntityWithDrawable, with a facade
	(proposed ADR-0056, amendments oo-bj8 item 12 and oo-0mxi).

	The entity reads Universe and PLAYER, so the test links the whole game but main (['*']) and
	uses a Universe that was never initialised (minimum detail, so no nebulae), subclassed to count
	-setLighting, and an entity that answers the viewpoint the test sets as PLAYER. Its drawable,
	OOSkyDrawable, loads star textures from the game's resources, which the test has not; the
	test replaces the drawable's star set-up with a stand-in that records the two colours the sky
	passed (method_setImplementation, as test_OOParticleSystem does for the texture loader, until
	OOSkyDrawable became C++ with no facade in bead oo-4jjl: since then its test seam, ported with
	Jon's decision oo-jsx0h, expectations unchanged). The
	expectations were written against the Objective-C API and run on the unconverted class first:
	the sky colour is the system's sun colour, else the blend of the two colours; the sky's colours
	come from "sky_rgb_colors" (six numbers) or "sky_color_1"/"sky_color_2" (premultiplied); the
	star count, the drawable, the status and the flags; -update: puts it at the viewpoint with the
	clear depth as its distance; and -changeProperty:withDictionary: takes a new sun colour (and
	relights) and refuses anything else. The distances are read through the one helper below. The
	callers make it with alloc/initWithColors::andSystemInfo:, which the conversion kept on the
	facade: the last test pins that its object is a C++ entity whose Objective-C object is the
	SkyEntity facade.
	Run: bash tools/check-core-tests.sh
*/

#import "SkyEntity.h"
#import "OOSkyDrawable.h"
#import "OOColor.h"
#import "Universe.h"
#import "MyOpenGLView.h"

#include "oo_test.hpp"

#include <cmath>


// main.mm defines the debug flags, and the test has its own main.
#ifndef NDEBUG
uint32_t gDebugFlags = 0;
#endif

@class PlayerEntity;
extern PlayerEntity *gOOPlayer;
extern Universe *gSharedUniverse;


@interface TestPlayer: Entity
{
@public
	HPVector	_viewpoint;
}
@end


@implementation TestPlayer

- (HPVector) viewpointPosition	{ return _viewpoint; }

@end


// UNIVERSE: never initialised; counts -setLighting.
@interface TestUniverse: Universe
{
@public
	int			_lightings;
}
@end


@implementation TestUniverse

- (OOTimeAbsolute) getTime	{ return 0; }
- (void) setLighting		{ _lightings++; }

@end


namespace {

TestUniverse *sUniverse = nil;
TestPlayer *sPlayer = nil;

// The drawable's star set-up's stand-in: the colours the sky passed.
OOColor *sStarColor1 = nil;
OOColor *sStarColor2 = nil;

void SetUpStars(OOSkyDrawable *, cxx::OOColor *color1, cxx::OOColor *color2)
{
	[sStarColor1 release];
	[sStarColor2 release];
	sStarColor1 = [oo::ToObjC(color1) retain];
	sStarColor2 = [oo::ToObjC(color2) retain];
}

}	// namespace


// The converted drawable's test seam for its star set-up (decision oo-jsx0h).
struct OOSkyDrawableTestAccess
{
	static void SetStarSetUpStandIn(void (*standIn)(OOSkyDrawable *, cxx::OOColor *, cxx::OOColor *))
	{
		OOSkyDrawable::sSetUpStarsStandIn = standIn;
	}
};


namespace {


void SetUp()
{
	if (sUniverse == nil)
	{
		sUniverse = (TestUniverse *)class_createInstance([TestUniverse class], 0);	// never released
		sPlayer = [[TestPlayer alloc] init];
		OOSkyDrawableTestAccess::SetStarSetUpStandIn(SetUpStars);
	}
	sUniverse->_lightings = 0;
	gSharedUniverse = sUniverse;
	gOOPlayer = (PlayerEntity *)sPlayer;
}


// --- Ivars the test reads, and nothing else ---------------------------------------------------------

GLfloat ZeroDistance(Entity *e)		{ return e->_cxxEntity->zero_distance; }
GLfloat CamZeroDistance(Entity *e)	{ return e->_cxxEntity->cam_zero_distance; }

// --------------------------------------------------------------------------------------------------


oo::PList Dict(oo::PList::Dict entries)
{
	return oo::PList(std::move(entries));
}


bool Near(double a, double b)
{
	return std::fabs(a - b) < 1e-4;
}


bool ColorIs(OOColor *color, float r, float g, float b, float a)
{
	if (color == nil)  return false;
	float cr = -1, cg = -1, cb = -1, ca = -1;
	[color getRed:&cr green:&cg blue:&cb alpha:&ca];
	return Near(cr, r) && Near(cg, g) && Near(cb, b) && Near(ca, a);
}


SkyEntity *Sky(const oo::PList &info)
{
	return [[[SkyEntity alloc] initWithColors:[OOColor redColor] col2:[OOColor blueColor] andSystemInfo:info] autorelease];
}

}	// namespace


OO_TEST(made)
{
	@autoreleasepool
	{
		SetUp();
		SkyEntity *sky = Sky(Dict({ { "sky_n_stars", oo::PList(7) } }));
		OO_CHECK(sky != nil && [sky isKindOfClass:[SkyEntity class]] && [sky isKindOfClass:[OOEntityWithDrawable class]]);
		OO_CHECK(dynamic_cast<OOSkyDrawable *>(oo::ToCxx([sky drawable])) != nullptr);
		OO_CHECK([sky status] == STATUS_EFFECT);
		OO_CHECK([sky isSky] && [sky isVisible] && ![sky canCollide]);
		OO_CHECK([sky cameraRangeFront] == (GLfloat)MAX_CLEAR_DEPTH && [sky cameraRangeBack] == (GLfloat)MAX_CLEAR_DEPTH);
		// No sun colour: the blend of the two.
		OO_CHECK(ColorIs([sky skyColor], 0.5f, 0.0f, 0.5f, 1.0f));
		// The stars' colours are the ones given.
		OO_CHECK(ColorIs(sStarColor1, 1, 0, 0, 1) && ColorIs(sStarColor2, 0, 0, 1, 1));
	}
}


OO_TEST(sunColour)
{
	@autoreleasepool
	{
		SetUp();
		SkyEntity *sky = Sky(Dict({ { "sun_color", oo::PList("greenColor") }, { "sky_n_stars", oo::PList(0) } }));
		OO_CHECK(ColorIs([sky skyColor], 0, 1, 0, 1));
	}
}


OO_TEST(rgbColours)
{
	@autoreleasepool
	{
		SetUp();
		Sky(Dict({ { "sky_rgb_colors", oo::PList("0.25 0.5 2 0 -1 0.75") }, { "sky_n_stars", oo::PList(0) } }));
		OO_CHECK(ColorIs(sStarColor1, 0.25f, 0.5f, 1.0f, 1.0f));	// clamped
		OO_CHECK(ColorIs(sStarColor2, 0.0f, 0.0f, 0.75f, 1.0f));

		// Not six numbers: the colours given.
		Sky(Dict({ { "sky_rgb_colors", oo::PList("0.25 0.5") }, { "sky_n_stars", oo::PList(0) } }));
		OO_CHECK(ColorIs(sStarColor1, 1, 0, 0, 1) && ColorIs(sStarColor2, 0, 0, 1, 1));
	}
}


OO_TEST(namedColours)
{
	@autoreleasepool
	{
		SetUp();
		// Premultiplied by alpha.
		Sky(Dict({
			{ "sky_color_1", oo::PList(oo::PList::Dict{ { "red", oo::PList(1.0) }, { "green", oo::PList(0.5) }, { "blue", oo::PList(0.0) }, { "alpha", oo::PList(0.5) } }) },
			{ "sky_color_2", oo::PList("whiteColor") },
			{ "sky_n_stars", oo::PList(0) },
		}));
		OO_CHECK(ColorIs(sStarColor1, 0.5f, 0.25f, 0.0f, 1.0f));
		OO_CHECK(ColorIs(sStarColor2, 1, 1, 1, 1));
	}
}


OO_TEST(update)
{
	@autoreleasepool
	{
		SetUp();
		SkyEntity *sky = Sky(Dict({ { "sky_n_stars", oo::PList(0) } }));
		sPlayer->_viewpoint = make_HPvector(5, 6, 7);
		[sky update:0.1];
		OO_CHECK(HPvector_equal([sky position], make_HPvector(5, 6, 7)));
		OO_CHECK(ZeroDistance(sky) == (GLfloat)(MAX_CLEAR_DEPTH * MAX_CLEAR_DEPTH));
		OO_CHECK(CamZeroDistance(sky) == ZeroDistance(sky));

		// No player: the position stays.
		gOOPlayer = nil;
		sPlayer->_viewpoint = make_HPvector(8, 8, 8);
		[sky update:0.1];
		OO_CHECK(HPvector_equal([sky position], make_HPvector(5, 6, 7)));
		gOOPlayer = (PlayerEntity *)sPlayer;
	}
}


OO_TEST(changeProperty)
{
	@autoreleasepool
	{
		SetUp();
		SkyEntity *sky = Sky(Dict({ { "sky_n_stars", oo::PList(0) } }));
		OO_CHECK([sky changeProperty:"sun_color" withDictionary:Dict({ { "sun_color", oo::PList("yellowColor") } })]);
		OO_CHECK(ColorIs([sky skyColor], 1, 1, 0, 1));
		OO_CHECK(sUniverse->_lightings == 1);

		// Not a colour: kept, no relighting, but answered YES.
		OO_CHECK([sky changeProperty:"sun_color" withDictionary:Dict({})]);
		OO_CHECK(ColorIs([sky skyColor], 1, 1, 0, 1));
		OO_CHECK(sUniverse->_lightings == 1);

		OO_CHECK(![sky changeProperty:"sky_n_stars" withDictionary:Dict({ { "sky_n_stars", oo::PList(3) } })]);
	}
}


OO_TEST(facade)
{
	@autoreleasepool
	{
		SetUp();
		SkyEntity *sky = Sky(Dict({ { "sky_n_stars", oo::PList(0) } }));
		OO_CHECK([sky class] == [SkyEntity class]);
		// A C++ entity (amendment oo-0mxi), not an Objective-C entity's adapter.
		OO_CHECK(dynamic_cast<cxx::SkyEntity *>(oo::ToCxx(sky)) != nullptr);
		OO_CHECK(oo::AsObjCEntity(oo::ToCxx(sky)) == nullptr);
		OO_CHECK(oo::ToObjC(oo::ToCxx(sky)) == sky);
	}
}


OO_TEST_MAIN()
