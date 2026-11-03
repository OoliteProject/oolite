/*	test_OOPlasmaBurstEntity.mm
	Unit tests for OOPlasmaBurstEntity (src/Core/Entities/OOPlasmaBurstEntity.h), the burst a plasma
	shot leaves where it hits: bead oo-l2s5, a leaf of the Entities pattern seam (amendment oo-bj8
	item 12).

	Its object needs the game graph, so the test links the whole game but main (['*']) and uses a
	Universe that was never initialised, of a test subclass that answers the time the test sets and
	records what is removed, and a plain entity as PLAYER. The expectations were written against the
	Objective-C API and run on the unconverted class first: what the initialiser sets (position,
	size, red, status), the growth and fade with the time since it was spawned, and its removal after
	two seconds. Making a burst and reading its colour components go through the helpers below, the
	only lines the conversion ported: since then a burst is made by its factory and handed to
	Objective-C as its facade, an OOLightParticleEntity.
	Run: bash tools/check-core-tests.sh
*/

#import "OOPlasmaBurstEntity.h"
#import "OODescription.h"
#import "Universe.h"

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
@end


@implementation TestPlayer

- (HPVector) viewpointPosition	{ return kZeroHPVector; }

@end


static Entity *sRemoved = nil;
static OOTimeAbsolute sTime = 0;


// UNIVERSE: never initialised; answers the time the test sets and records what is removed.
@interface TestUniverse: Universe
@end


@implementation TestUniverse

- (OOTimeAbsolute) getTime				{ return sTime; }
- (BOOL) removeEntity:(Entity *)entity	{ sRemoved = entity; return YES; }

@end


namespace {

// --- How a burst is made, and its colour (a @protected ivar), and nothing else -------------------

OOLightParticleEntity *MakeBurst(HPVector position)
{
	return (OOLightParticleEntity *)oo::NewEntityFacade(OOPlasmaBurstEntity::burstWithPosition(position));
}

const GLfloat *ColorComponents(OOLightParticleEntity *e)	{ return oo::ToCxx(e)->_colorComponents; }

// --------------------------------------------------------------------------------------------------


void SetUp()
{
	static Universe *universe = nil;
	if (universe == nil)  universe = (Universe *)class_createInstance([TestUniverse class], 0);	// never released
	gSharedUniverse = universe;
	static TestPlayer *player = nil;
	if (player == nil)  player = [[TestPlayer alloc] init];
	gOOPlayer = (PlayerEntity *)player;
	sRemoved = nil;
	sTime = 0;
}


bool ComponentsAre(OOLightParticleEntity *e, GLfloat r, GLfloat g, GLfloat b, GLfloat a)
{
	const GLfloat *c = ColorComponents(e);
	return c[0] == r && c[1] == g && c[2] == b && c[3] == a;
}

}	// namespace


OO_TEST(initWithPosition)
{
	@autoreleasepool
	{
		SetUp();
		OOLightParticleEntity *burst = MakeBurst(make_HPvector(4, 5, 6));
		OO_CHECK(burst != nil);
		OO_CHECK(HPvector_equal([burst position], make_HPvector(4, 5, 6)));
		OO_CHECK([burst diameter] == 64.0f && [burst collisionRadius] == 2.0f);
		OO_CHECK([burst status] == STATUS_EFFECT && [burst scanClass] == CLASS_NO_DRAW && [burst isEffect]);
		OO_CHECK(ComponentsAre(burst, 1.0f, 0.0f, 0.0f, 1.0f));
		OO_CHECK(oo::DescriptionOf(burst).starts_with("<OOPlasmaBurstEntity 0x"));
	}
}


OO_TEST(growsFadesAndIsRemoved)
{
	@autoreleasepool
	{
		SetUp();
		OOLightParticleEntity *burst = MakeBurst(make_HPvector(4, 5, 6));

		sTime = 1.0;
		[burst update:0.1];
		OO_CHECK([burst diameter] == 128.0f);
		OO_CHECK(ComponentsAre(burst, 1.0f, 0.0f, 0.0f, 0.5f));
		OO_CHECK(sRemoved == nil);

		sTime = 2.5;
		[burst update:0.1];
		OO_CHECK([burst diameter] == 64.0f + 2.5f * 64.0f);
		OO_CHECK(ComponentsAre(burst, 1.0f, 0.0f, 0.0f, 0.0f));
		OO_CHECK(sRemoved == burst);
	}
}


OO_TEST_MAIN()
