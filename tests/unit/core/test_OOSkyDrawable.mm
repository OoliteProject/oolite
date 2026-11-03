/*	test_OOSkyDrawable.mm
	Unit tests for OOSkyDrawable (src/Core/OOSkyDrawable.h), the drawable of the sky (the stars and
	nebulae behind a system): bead oo-4jjl, a Phase 3 class conversion (proposed ADR-0056).

	The drawable loads its star and nebula textures from the game's resources, which the test has
	not, so it links the whole game but main (['*']), uses a Universe that was never initialised
	(minimum detail, so the nebulae are not set up) and replaces the star set-up with a stand-in
	that records what the drawable passed it (as test_SkyEntity.mm does; decision oo-jsx0h). The
	expectations were written against the Objective-C API and run on the unconverted class first:
	the stand-in gets the two star colours and the drawable keeps the star and nebula counts it was
	given; the sky has opaque parts only and no draw distance limit; it has no quad sets, so no
	textures; and it is a graphics reset client, so a reset deletes its display list (the GL
	context is a hidden window's, oo_gl_test_context.hpp). The drawable's private state is read
	through the one block of helpers below, which is all the conversion changed.
	Run: bash tools/check-core-tests.sh
*/

#import "OOSkyDrawable.h"
#import "OOColor.h"
#import "OOGraphicsResetManager.h"
#import "Universe.h"

#include "oo_test.hpp"
#include "oo_gl_test_context.hpp"

#include <cmath>

#include <objc/runtime.h>


// main.mm defines the debug flags, and the test has its own main.
#ifndef NDEBUG
uint32_t gDebugFlags = 0;
#endif

extern Universe *gSharedUniverse;


namespace {

// What the star set-up's stand-in was given.
OOColor *sStarColor1 = nil;
OOColor *sStarColor2 = nil;
unsigned sStarSetUps = 0;


// --- The drawable, its star set-up's stand-in and its private state ----------------------------------

void SetUpStars(OOSkyDrawable *, cxx::OOColor *color1, cxx::OOColor *color2)
{
	[sStarColor1 release];
	[sStarColor2 release];
	sStarColor1 = [oo::ToObjC(color1) retain];
	sStarColor2 = [oo::ToObjC(color2) retain];
	sStarSetUps++;
}

}	// namespace


struct OOSkyDrawableTestAccess
{
	static void InstallStandIn()						{ OOSkyDrawable::sSetUpStarsStandIn = SetUpStars; }
	static OOSkyDrawable *Cxx(OODrawable *sky)			{ return dynamic_cast<OOSkyDrawable *>(oo::ToCxx(sky)); }
	static unsigned StarCount(OODrawable *sky)			{ return Cxx(sky)->_starCount; }
	static unsigned NebulaCount(OODrawable *sky)		{ return Cxx(sky)->_nebulaCount; }
	static GLint &DisplayListName(OODrawable *sky)		{ return Cxx(sky)->_displayListName; }
};


namespace {

void InstallStandIn()	{ OOSkyDrawableTestAccess::InstallStandIn(); }


// A sky drawable: the root facade of a new C++ drawable (autoreleased; it keeps the drawable).
OODrawable *Sky(OOColor *color1, OOColor *color2, unsigned starCount, unsigned nebulaCount)
{
	return oo::ToObjC(oo::makeRef<OOSkyDrawable>(oo::ToCxx(color1), oo::ToCxx(color2), oo::ToCxx([OOColor greenColor]),
												 oo::ToCxx([OOColor whiteColor]), starCount, nebulaCount, false, 0.5f, 1.0f, 1.0f).get());
}


unsigned StarCount(OODrawable *sky)			{ return OOSkyDrawableTestAccess::StarCount(sky); }
unsigned NebulaCount(OODrawable *sky)		{ return OOSkyDrawableTestAccess::NebulaCount(sky); }
GLint &DisplayListName(OODrawable *sky)		{ return OOSkyDrawableTestAccess::DisplayListName(sky); }

// ------------------------------------------------------------------------------------------------------


void SetUp()
{
	if (gSharedUniverse == nil)
	{
		gSharedUniverse = (Universe *)class_createInstance([Universe class], 0);	// never released
		InstallStandIn();
	}
}


bool ColorIs(OOColor *color, float r, float g, float b, float a)
{
	if (color == nil)  return false;
	float cr = -1, cg = -1, cb = -1, ca = -1;
	[color getRed:&cr green:&cg blue:&cb alpha:&ca];
	auto within = [](float x, float y) { return std::fabs(x - y) < 1e-4f; };
	return within(cr, r) && within(cg, g) && within(cb, b) && within(ca, a);
}

}	// namespace


OO_TEST(made)
{
	@autoreleasepool
	{
		SetUp();
		const unsigned setUpsBefore = sStarSetUps;
		OODrawable *sky = Sky([OOColor redColor], [OOColor blueColor], 7, 5);
		OO_CHECK(sky != nil);
		OO_CHECK(sStarSetUps == setUpsBefore + 1);
		OO_CHECK(ColorIs(sStarColor1, 1, 0, 0, 1) && ColorIs(sStarColor2, 0, 0, 1, 1));
		OO_CHECK(StarCount(sky) == 7);
		OO_CHECK(NebulaCount(sky) == 5);	// minimum detail: the nebulae were not set up
		OO_CHECK(DisplayListName(sky) == 0);
	}
}


OO_TEST(parts)
{
	@autoreleasepool
	{
		SetUp();
		OODrawable *sky = Sky([OOColor whiteColor], [OOColor yellowColor], 0, 0);
		OO_CHECK([sky hasOpaqueParts]);
		OO_CHECK(![sky hasTranslucentParts]);
		OO_CHECK(std::isinf([sky maxDrawDistance]) && [sky maxDrawDistance] > 0);
		OO_CHECK([sky collisionRadius] == 0);
#ifndef NDEBUG
		OO_CHECK([sky cxx_allTextures].empty());	// no quad sets
		OO_CHECK([sky totalSize] > 0);
#endif
	}
}


OO_TEST(resetDeletesTheDisplayList)
{
	OO_CHECK(OOTestGLContext());
	@autoreleasepool
	{
		SetUp();
		OODrawable *sky = Sky([OOColor redColor], [OOColor blueColor], 0, 0);
		const GLuint list = glGenLists(1);
		OO_CHECK(list != 0);
		DisplayListName(sky) = (GLint)list;
		OO_CHECK(glIsList(list));

		cxx::OOGraphicsResetManager::sharedManager()->resetGraphicsState();
		OO_CHECK(DisplayListName(sky) == 0);
		OO_CHECK(!glIsList(list));
	}
	// Released: no longer a client, so a reset does not reach it.
	cxx::OOGraphicsResetManager::sharedManager()->resetGraphicsState();
}


OO_TEST_MAIN()
