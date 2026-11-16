/*	test_OORingEffectEntity.mm
	Unit tests for OORingEffectEntity (src/Core/Entities/OORingEffectEntity.h), the expanding ring
	of a big explosion or a witchspace jump: bead oo-peql, a leaf of the Entities seam (proposed
	ADR-0056, amendment oo-bj8 item 12).

	The entity reads Universe and PLAYER, so the test links the whole game but main (['*']) and
	uses a Universe that was never initialised, subclassed to record -removeEntity:, and a plain
	entity as PLAYER. The expectations were written against the Objective-C API and run on the
	unconverted class first (but for "no ring from nil", which crashed there in the Entity facade's
	-dealloc of an entity whose -init never ran, bead oo-s6ic6): no ring from nil; a ring takes the
	source's position, orientation and velocity, is an effect that cannot collide, owned by the
	source; its description counts the time passed; it removes itself after two seconds. The rings
	are made through the one block of helpers below, the only lines the conversion ported: the ring
	is now a C++ entity whose Objective-C object is the Entity facade oo::NewEntityFacade made.
	Run: bash tools/check-core-tests.sh
*/

#import "OORingEffectEntity.h"
#import "OODescription.h"
#import "Universe.h"

#include "oo_test.hpp"

#include <string>


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


// UNIVERSE: never initialised; records what is removed.
@interface TestUniverse: Universe
{
@public
	Entity	*_removed;
}
@end


@implementation TestUniverse

- (BOOL) removeEntity:(Entity *)entity
{
	_removed = entity;
	return YES;
}

@end


namespace {

TestUniverse *sUniverse = nil;


void SetUp()
{
	if (sUniverse == nil)  sUniverse = (TestUniverse *)class_createInstance([TestUniverse class], 0);	// never released
	sUniverse->_removed = nil;
	gSharedUniverse = sUniverse;
	static TestPlayer *player = nil;
	if (player == nil)  player = [[TestPlayer alloc] init];
	gOOPlayer = (PlayerEntity *)player;
}


// --- How the test makes a ring (ported by the conversion), and nothing else ----------------------

Entity *Ring(Entity *source)			{ return oo::NewEntityFacade(OORingEffectEntity::ringFromEntity(source)); }
Entity *ShrinkingRing(Entity *source)	{ return oo::NewEntityFacade(OORingEffectEntity::shrinkingRingFromEntity(source)); }

// --------------------------------------------------------------------------------------------------


Entity *Source()
{
	Entity *source = [[[Entity alloc] init] autorelease];
	[source setCollisionRadius:8.0f];
	[source setPosition:make_HPvector(1, 2, 3)];
	[source setOrientation:make_quaternion(0, 1, 0, 0)];
	[source setVelocity:make_vector(4, 5, 6)];
	return source;
}

}	// namespace


OO_TEST(noSourceNoRing)
{
	@autoreleasepool
	{
		SetUp();
		OO_CHECK(Ring(nil) == nil);
		OO_CHECK(ShrinkingRing(nil) == nil);
	}
}


OO_TEST(ringTakesTheSource)
{
	@autoreleasepool
	{
		SetUp();
		Entity *source = Source();
		for (Entity *ring : { Ring(source), ShrinkingRing(source) })
		{
			OO_CHECK(ring != nil && ring != source);
			OO_CHECK(HPvector_equal([ring position], make_HPvector(1, 2, 3)));
			Quaternion q = [ring orientation];
			OO_CHECK(q.w == 0 && q.x == 1 && q.y == 0 && q.z == 0);
			Vector v = [ring velocity];
			OO_CHECK(v.x == 4 && v.y == 5 && v.z == 6);
			OO_CHECK([ring status] == STATUS_EFFECT && [ring scanClass] == CLASS_NO_DRAW);
			OO_CHECK([ring owner] == source);
			OO_CHECK([ring isEffect] && ![ring canCollide]);
			OO_CHECK(![ring isShip] && ![ring isVisualEffect]);
			OO_CHECK(oo::DescriptionOf(ring).starts_with("<OORingEffectEntity 0x"));
			OO_CHECK(oo::DescriptionOf(ring).ends_with("{0.000000 seconds passed of 2.000000}"));
		}
	}
}


OO_TEST(updateCountsAndExpires)
{
	@autoreleasepool
	{
		SetUp();
		Entity *ring = Ring(Source());
		[ring update:0.5];
		OO_CHECK(oo::DescriptionOf(ring).ends_with("{0.500000 seconds passed of 2.000000}"));
		OO_CHECK(HPvector_equal([ring position], make_HPvector(3, 4.5, 6)));	// moved by its velocity
		OO_CHECK(sUniverse->_removed == nil);

		[ring update:1.5];
		OO_CHECK(sUniverse->_removed == nil);	// exactly two seconds: not yet
		[ring update:0.25];
		OO_CHECK(sUniverse->_removed == ring);
	}
}


OO_TEST_MAIN()
