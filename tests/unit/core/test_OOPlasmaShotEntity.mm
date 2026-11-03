/*	test_OOPlasmaShotEntity.mm
	Unit tests for OOPlasmaShotEntity (src/Core/Entities/OOPlasmaShotEntity.h), a turret's plasma
	shot: bead oo-z9md, a leaf of the Entities seam under OOLightParticleEntity (proposed ADR-0056,
	amendments oo-bj8 item 12 and oo-peql).

	The entity reads Universe and PLAYER, so the test links the whole game but main (['*']) and
	uses a Universe that was never initialised, subclassed to answer the time the test sets and to
	record -addEntity: and -removeEntity:, and a plain entity as PLAYER. The ship that fired is a
	plain entity marked as a ship (so it is its own root ship entity), and the entity hit is an
	entity subclass that records the damage. The expectations were written against the Objective-C
	API and run on the unconverted class first: a shot is a no-draw effect of diameter 12 and
	collision radius 2 with the given position, velocity, energy and colour (always opaque); it
	cannot collide for its first 0.05 seconds; it collides with anything but an effect or its
	owner's ship; it damages what it collides with (unless that is its owner's ship), removes
	itself and leaves a plasma burst where it was; and it removes itself when its time is up. The
	shots are made, and their colour read, through the one block of helpers below, the only lines
	the conversion ported: the shot is now a C++ entity whose Objective-C object is the
	OOLightParticleEntity facade oo::NewEntityFacade made.
	Run: bash tools/check-core-tests.sh
*/

#import "OOPlasmaShotEntity.h"
#import "OOPlasmaBurstEntity.h"
#import "OOColor.h"
#import "Universe.h"

#include "oo_test.hpp"

#include <string>
#include <vector>


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


// UNIVERSE: never initialised; answers the test's time and records what is added and removed.
@interface TestUniverse: Universe
{
@public
	OOTimeAbsolute	_time;
	Entity			*_removed;
	Entity			*_added;
}
@end


@implementation TestUniverse

- (OOTimeAbsolute) getTime	{ return _time; }


- (BOOL) removeEntity:(Entity *)entity
{
	_removed = entity;
	return YES;
}


- (BOOL) addEntity:(Entity *)entity
{
	[_added release];
	_added = [entity retain];
	return YES;
}

@end


// What the shot hits: records the damage.
@interface TestTarget: Entity
{
@public
	double		_amount;
	Entity		*_from;
	Entity		*_becauseOf;
	std::string	_weapon;
	int			_hits;
}
@end


@implementation TestTarget

- (void) takeEnergyDamage:(double)amount from:(Entity *)ent becauseOf:(Entity *)other weaponIdentifier:(const std::string &)weaponIdentifier
{
	_hits++;
	_amount = amount;
	_from = ent;
	_becauseOf = other;
	_weapon = weaponIdentifier;
}

@end


// An effect, for the collision test.
@interface TestEffect: Entity
@end


@implementation TestEffect

- (BOOL) isEffect	{ return YES; }

@end


namespace {

TestUniverse *sUniverse = nil;


void SetUp(OOTimeAbsolute time)
{
	if (sUniverse == nil)
	{
		sUniverse = (TestUniverse *)class_createInstance([TestUniverse class], 0);	// never released
		sUniverse->_cxxUniverse = oo::makeRef<cxx::Universe>(sUniverse);	// what -initWithGameView: makes first (ADR-0056 amendment oo-riqmz)
	}
	sUniverse->_time = time;
	sUniverse->_removed = nil;
	[sUniverse->_added release];
	sUniverse->_added = nil;
	gSharedUniverse = sUniverse;
	static TestPlayer *player = nil;
	if (player == nil)  player = [[TestPlayer alloc] init];
	gOOPlayer = (PlayerEntity *)player;
}


// --- How the test makes a shot and reads its colour (ported by the conversion), and nothing else -

Entity *Shot(HPVector position, Vector velocity, float energy, OOTimeDelta duration, OOColor *color)
{
	return oo::NewEntityFacade(OOPlasmaShotEntity::shotWithPosition(position, velocity, energy, duration, oo::ToCxx(color)));
}

const GLfloat *ColorComponents(Entity *shot)	{ return oo::ToCxx((OOLightParticleEntity *)shot)->_colorComponents; }
void SetColliding(Entity *shot, Entity *other)	{ shot->_cxxEntity->collidingEntities.emplace_back(other); }
void SetIsShip(Entity *e)						{ e->_cxxEntity->isShip = true; }

// --------------------------------------------------------------------------------------------------


Entity *RedShot()
{
	return Shot(make_HPvector(1, 2, 3), make_vector(4, 5, 6), 7.0f, 2.0, [OOColor colorWithRed:1.0f green:0.0f blue:0.0f alpha:0.5f]);
}


Entity *Ship()
{
	Entity *ship = [[[Entity alloc] init] autorelease];
	SetIsShip(ship);
	return ship;
}

}	// namespace


OO_TEST(shotIsMade)
{
	@autoreleasepool
	{
		SetUp(10.0);
		Entity *shot = RedShot();
		OO_CHECK(shot != nil && [shot isKindOfClass:[OOLightParticleEntity class]]);
		OO_CHECK(HPvector_equal([shot position], make_HPvector(1, 2, 3)));
		Vector v = [shot velocity];
		OO_CHECK(v.x == 4 && v.y == 5 && v.z == 6);
		OO_CHECK([shot energy] == 7.0f && [shot collisionRadius] == 2.0f);
		OO_CHECK([(OOLightParticleEntity *)shot diameter] == 12.0f);
		OO_CHECK([shot status] == STATUS_EFFECT && [shot scanClass] == CLASS_NO_DRAW && [shot isEffect]);
		OO_CHECK([shot spawnTime] == 10.0f);
		const GLfloat *c = ColorComponents(shot);
		OO_CHECK(c[0] == 1.0f && c[1] == 0.0f && c[2] == 0.0f && c[3] == 1.0f);	// always opaque
	}
}


OO_TEST(activationDelay)
{
	@autoreleasepool
	{
		SetUp(10.0);
		Entity *shot = RedShot();
		OO_CHECK(![shot canCollide]);
		sUniverse->_time = 10.04;
		OO_CHECK(![shot canCollide]);
		sUniverse->_time = 10.06;
		OO_CHECK([shot canCollide]);
	}
}


OO_TEST(collisions)
{
	@autoreleasepool
	{
		SetUp(0.0);
		Entity *shot = RedShot();
		Entity *plain = [[[Entity alloc] init] autorelease];
		Entity *effect = [[[TestEffect alloc] init] autorelease];

		// No owner: a plain entity's root ship is nil too.
		OO_CHECK(![shot checkCloseCollisionWith:plain]);

		Entity *ship = Ship();
		[shot setOwner:ship];
		OO_CHECK([shot checkCloseCollisionWith:plain]);
		OO_CHECK(![shot checkCloseCollisionWith:effect]);
		OO_CHECK(![shot checkCloseCollisionWith:ship]);	// its own ship
		OO_CHECK([shot checkCloseCollisionWith:Ship()]);
		OO_CHECK([shot checkCloseCollisionWith:nil]);
	}
}


OO_TEST(hitDamagesAndBursts)
{
	@autoreleasepool
	{
		SetUp(0.0);
		Entity *shot = RedShot();
		Entity *ship = Ship();
		[shot setOwner:ship];

		// Its own ship is not hit.
		SetColliding(shot, ship);
		sUniverse->_time = 0.1;
		[shot update:0.1];
		OO_CHECK(sUniverse->_removed == nil && sUniverse->_added == nil);

		TestTarget *target = [[[TestTarget alloc] init] autorelease];
		SetColliding(shot, target);
		[shot update:0.1];
		OO_CHECK(target->_hits == 1 && target->_amount == 7.0 && target->_from == shot && target->_becauseOf == ship);
		OO_CHECK(target->_weapon == "EQ_WEAPON_PLASMA_SHOT");
		OO_CHECK(sUniverse->_removed == shot);
		Entity *burst = sUniverse->_added;
		OO_CHECK(burst != nil && burst != shot && dynamic_cast<OOPlasmaBurstEntity *>(oo::ToCxx(burst)) != nullptr);	// a C++ entity (oo-l2s5)
		OO_CHECK(HPvector_equal([burst position], [shot position]));
	}
}


OO_TEST(expires)
{
	@autoreleasepool
	{
		SetUp(0.0);
		Entity *shot = RedShot();
		sUniverse->_time = 1.0;
		[shot update:1.0];
		OO_CHECK(sUniverse->_removed == nil);
		sUniverse->_time = 2.5;
		[shot update:1.5];
		OO_CHECK(sUniverse->_removed == shot);
	}
}


OO_TEST_MAIN()
