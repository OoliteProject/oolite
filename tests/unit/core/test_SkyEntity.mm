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
	relights) and refuses anything else. The distances are read through the one helper below. Since
	bead oo-9ht.109 deleted the class's Objective-C facade (ADR-0056 amendment oo-9ht.106) the sky
	is made as the universe makes it, in C++ with its object (the OOEntityWithDrawable facade, the
	root's since bead oo-9ht.40) made
	by oo::NewEntityFacade: the class's own selectors are member calls, the root's are still sent
	to the object, and the last test pins that the object is a C++ entity's.
	Run: bash tools/check-core-tests.sh
*/

#import "SkyEntity.h"
#import "PlayerEntity.h"	// PLAYER is C++ (bead oo-9ht.177)
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

class PlayerEntity;
extern PlayerEntity *gOOPlayer;
extern Universe *gSharedUniverse;


class TestPlayer : public PlayerEntity	// C++ since bead oo-9ht.177 deleted the Objective-C player
{
public:
	HPVector	_viewpoint = {};

	HPVector viewpointPosition() override	{ return _viewpoint; }
};




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
TestPlayer *sPlayer = nullptr;

// The drawable's star set-up's stand-in: the colours the sky passed.
oo::Ref<OOColor> sStarColor1;
oo::Ref<OOColor> sStarColor2;

void SetUpStars(OOSkyDrawable *, OOColor *color1, OOColor *color2)
{
	sStarColor1 = oo::Ref<OOColor>(color1);
	sStarColor2 = oo::Ref<OOColor>(color2);
}

}	// namespace


// The converted drawable's test seam for its star set-up (decision oo-jsx0h).
struct OOSkyDrawableTestAccess
{
	static void SetStarSetUpStandIn(void (*standIn)(OOSkyDrawable *, OOColor *, OOColor *))
	{
		OOSkyDrawable::sSetUpStarsStandIn = standIn;
	}
};

// [[TestPlayer alloc] init] (bead oo-9ht.177): a C++ player under the ship's facade, as
// PlayerEntity::sharedPlayer() makes the game's, retained (+1) as +alloc's object was.
template <class T>
T *NewTestPlayer()
{
	oo::Ref<T> player = oo::makeRef<T>();
	@autoreleasepool
	{
		[oo::NewEntityFacade(player) retain];
	}
	return player.get();
}


namespace {


void SetUp()
{
	if (sUniverse == nil)
	{
		sUniverse = (TestUniverse *)class_createInstance([TestUniverse class], 0);	// never released
		sUniverse->_cxxUniverse = oo::makeRef<cxx::Universe>(sUniverse);	// what -initWithGameView: makes first (ADR-0056 amendment oo-riqmz)
		sPlayer = NewTestPlayer<TestPlayer>();
		OOSkyDrawableTestAccess::SetStarSetUpStandIn(SetUpStars);
	}
	sUniverse->_lightings = 0;
	gSharedUniverse = sUniverse;
	gOOPlayer = sPlayer;
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
	color->getRed(&cr, &cg, &cb, &ca);
	return Near(cr, r) && Near(cg, g) && Near(cb, b) && Near(ca, a);
}


// [[[SkyEntity alloc] initWithColors:...] autorelease] until bead oo-9ht.109: the object first, then
// the initialiser's body, as the universe makes the sky.
Entity *Sky(const oo::PList &info)	// the root's facade since bead oo-9ht.40 deleted the drawable's
{
	const oo::Ref<SkyEntity> sky = oo::makeRef<SkyEntity>();
	Entity *object = oo::NewEntityFacade(sky);
	sky->initWithColors(OOColor::redColor().get(), OOColor::blueColor().get(), info);
	return object;
}

SkyEntity *SkyPart(Entity *object)	{ return dynamic_cast<SkyEntity *>(oo::ToCxx(object)); }

}	// namespace


OO_TEST(made)
{
	@autoreleasepool
	{
		SetUp();
		Entity *sky = Sky(Dict({ { "sky_n_stars", oo::PList(7) } }));
		OO_CHECK(sky != nil && SkyPart(sky) != nullptr && dynamic_cast<OOEntityWithDrawable *>(oo::ToCxx(sky)) != nullptr);	// -isKindOfClass:[OOEntityWithDrawable class] until bead oo-9ht.40
		OO_CHECK(dynamic_cast<OOSkyDrawable *>(SkyPart(sky)->getDrawable()) != nullptr);	// -drawable until bead oo-9ht.40
		OO_CHECK([sky status] == STATUS_EFFECT);
		OO_CHECK([sky isSky] && [sky isVisible] && ![sky canCollide]);
		OO_CHECK([sky cameraRangeFront] == (GLfloat)MAX_CLEAR_DEPTH && [sky cameraRangeBack] == (GLfloat)MAX_CLEAR_DEPTH);
		// No sun colour: the blend of the two.
		OO_CHECK(ColorIs(SkyPart(sky)->getSkyColor(), 0.5f, 0.0f, 0.5f, 1.0f));
		// The stars' colours are the ones given.
		OO_CHECK(ColorIs(sStarColor1.get(), 1, 0, 0, 1) && ColorIs(sStarColor2.get(), 0, 0, 1, 1));
	}
}


OO_TEST(sunColour)
{
	@autoreleasepool
	{
		SetUp();
		Entity *sky = Sky(Dict({ { "sun_color", oo::PList("greenColor") }, { "sky_n_stars", oo::PList(0) } }));
		OO_CHECK(ColorIs(SkyPart(sky)->getSkyColor(), 0, 1, 0, 1));
	}
}


OO_TEST(rgbColours)
{
	@autoreleasepool
	{
		SetUp();
		Sky(Dict({ { "sky_rgb_colors", oo::PList("0.25 0.5 2 0 -1 0.75") }, { "sky_n_stars", oo::PList(0) } }));
		OO_CHECK(ColorIs(sStarColor1.get(), 0.25f, 0.5f, 1.0f, 1.0f));	// clamped
		OO_CHECK(ColorIs(sStarColor2.get(), 0.0f, 0.0f, 0.75f, 1.0f));

		// Not six numbers: the colours given.
		Sky(Dict({ { "sky_rgb_colors", oo::PList("0.25 0.5") }, { "sky_n_stars", oo::PList(0) } }));
		OO_CHECK(ColorIs(sStarColor1.get(), 1, 0, 0, 1) && ColorIs(sStarColor2.get(), 0, 0, 1, 1));
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
		OO_CHECK(ColorIs(sStarColor1.get(), 0.5f, 0.25f, 0.0f, 1.0f));
		OO_CHECK(ColorIs(sStarColor2.get(), 1, 1, 1, 1));
	}
}


OO_TEST(update)
{
	@autoreleasepool
	{
		SetUp();
		Entity *sky = Sky(Dict({ { "sky_n_stars", oo::PList(0) } }));
		sPlayer->_viewpoint = make_HPvector(5, 6, 7);
		[sky update:0.1];
		OO_CHECK(HPvector_equal([sky position], make_HPvector(5, 6, 7)));
		OO_CHECK(ZeroDistance(sky) == (GLfloat)(MAX_CLEAR_DEPTH * MAX_CLEAR_DEPTH));
		OO_CHECK(CamZeroDistance(sky) == ZeroDistance(sky));

		// No player: the position stays.
		gOOPlayer = nullptr;
		sPlayer->_viewpoint = make_HPvector(8, 8, 8);
		[sky update:0.1];
		OO_CHECK(HPvector_equal([sky position], make_HPvector(5, 6, 7)));
		gOOPlayer = sPlayer;
	}
}


OO_TEST(changeProperty)
{
	@autoreleasepool
	{
		SetUp();
		Entity *sky = Sky(Dict({ { "sky_n_stars", oo::PList(0) } }));
		OO_CHECK(SkyPart(sky)->changeProperty("sun_color", Dict({ { "sun_color", oo::PList("yellowColor") } })));
		OO_CHECK(ColorIs(SkyPart(sky)->getSkyColor(), 1, 1, 0, 1));
		OO_CHECK(sUniverse->_lightings == 1);

		// Not a colour: kept, no relighting, but answered YES.
		OO_CHECK(SkyPart(sky)->changeProperty("sun_color", Dict({})));
		OO_CHECK(ColorIs(SkyPart(sky)->getSkyColor(), 1, 1, 0, 1));
		OO_CHECK(sUniverse->_lightings == 1);

		OO_CHECK(!SkyPart(sky)->changeProperty("sky_n_stars", Dict({ { "sky_n_stars", oo::PList(3) } })));
	}
}


OO_TEST(facade)
{
	@autoreleasepool
	{
		SetUp();
		Entity *sky = Sky(Dict({ { "sky_n_stars", oo::PList(0) } }));
		// A C++ entity (amendment oo-0mxi), not an Objective-C entity's adapter.
		OO_CHECK(dynamic_cast<SkyEntity *>(oo::ToCxx(sky)) != nullptr);
		OO_CHECK(oo::AsObjCEntity(oo::ToCxx(sky)) == nullptr);
		OO_CHECK(oo::ToObjC(oo::ToCxx(sky)) == sky);
	}
}


OO_TEST_MAIN()
