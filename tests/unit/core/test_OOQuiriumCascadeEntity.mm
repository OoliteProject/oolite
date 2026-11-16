/*	test_OOQuiriumCascadeEntity.mm
	Unit tests for OOQuiriumCascadeEntity (src/Core/Entities/OOQuiriumCascadeEntity.h), the
	expanding sphere of a quirium cascade: bead oo-2c6g, a leaf of the Entities pattern seam
	(amendment oo-bj8 item 12).

	Its object needs the game graph, so the test links the whole game but main (['*']) and uses a
	Universe that was never initialised, of a test subclass that records what is removed, and a plain
	entity as PLAYER. The ship it is made from is a plain entity too: the class asks it only for its
	position and owner. The expectations were written against the Objective-C API and run on the
	unconverted class first: nil from a nil ship; what it takes from the ship; that it is the
	cascade weapon (and other entities are not); the collision delay, the expansion, the energy it
	deals to what it collides with, and its removal after twenty seconds; its description. Making
	a cascade goes through the helper below, the only line the conversion ported: since then it is
	made by its factory and handed to Objective-C as an Entity facade.
	Run: bash tools/check-core-tests.sh
*/

#import "OOQuiriumCascadeEntity.h"
#import "OODescription.h"
#import "Universe.h"

#include "oo_test.hpp"

#include <cmath>
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


static Entity *sRemoved = nil;


// UNIVERSE: never initialised; records what is removed.
@interface TestUniverse: Universe
@end


@implementation TestUniverse

- (OOTimeAbsolute) getTime				{ return 0; }
- (BOOL) removeEntity:(Entity *)entity	{ sRemoved = entity; return YES; }

@end


// What the cascade collides with: records the damage it is dealt.
@interface TestVictim: Entity
{
@public
	double			_damage;
	Entity			*_from;
	Entity			*_becauseOf;
	std::string		_weapon;
}
@end


@implementation TestVictim

- (void) takeEnergyDamage:(double)amount from:(Entity *)ent becauseOf:(Entity *)other weaponIdentifier:(const std::string &)weaponIdentifier
{
	_damage = amount;
	_from = ent;
	_becauseOf = other;
	_weapon = weaponIdentifier;
}

@end


namespace {

// --- How a cascade is made, and nothing else --------------------------------------------------------

Entity *MakeCascade(ShipEntity *ship)	{ return oo::NewEntityFacade(OOQuiriumCascadeEntity::quiriumCascadeFromShip(ship)); }

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
}

}	// namespace


OO_TEST(fromShip)
{
	@autoreleasepool
	{
		SetUp();
		OO_CHECK(MakeCascade(nil) == nil);

		Entity *ship = [[[Entity alloc] init] autorelease];
		Entity *shipOwner = [[[Entity alloc] init] autorelease];
		[ship setPosition:make_HPvector(5, 6, 7)];
		[ship setOwner:shipOwner];

		Entity *cascade = MakeCascade((ShipEntity *)ship);
		OO_CHECK(cascade != nil);
		OO_CHECK(HPvector_equal([cascade position], make_HPvector(5, 6, 7)));
		OO_CHECK([cascade status] == STATUS_EFFECT && [cascade scanClass] == CLASS_MINE);
		OO_CHECK([cascade owner] == shipOwner);
		OO_CHECK([cascade isEffect] && [cascade isCascadeWeapon]);
		OO_CHECK(![ship isCascadeWeapon]);
		OO_CHECK(![cascade canCollide] && [cascade checkCloseCollisionWith:nil] && [cascade checkCloseCollisionWith:ship]);
		OO_CHECK(oo::DescriptionOf(cascade).starts_with("<OOQuiriumCascadeEntity 0x"));
		OO_CHECK(oo::DescriptionOf(cascade).ends_with("{0.000000 seconds passed of 20.000000}"));

		// Nothing is drawn in the opaque pass.
		[cascade drawImmediate:false translucent:false];
	}
}


OO_TEST(update)
{
	@autoreleasepool
	{
		SetUp();
		Entity *ship = [[[Entity alloc] init] autorelease];
		Entity *shipOwner = [[[Entity alloc] init] autorelease];
		[ship setOwner:shipOwner];
		Entity *cascade = MakeCascade((ShipEntity *)ship);
		TestVictim *victim = [[[TestVictim alloc] init] autorelease];
		[cascade cxx_collidingEntities]->emplace_back(victim);

		// A tenth of a second: past the collision delay, expanding, and dealing energy.
		[cascade update:0.1];
		OO_CHECK([cascade canCollide]);
		OO_CHECK(fabs([cascade collisionRadius] - 100.0f) < 1e-3);
		const double energy = 0.1 * (100000 - 90000 * (0.1 / 20.0));
		OO_CHECK(fabs([cascade energy] - energy) < 1e-2);
		OO_CHECK(fabs(victim->_damage - energy) < 1e-2);
		OO_CHECK(victim->_from == cascade && victim->_becauseOf == shipOwner && victim->_weapon == "EQ_QC_MINE");
		OO_CHECK(oo::DescriptionOf(cascade).ends_with("{0.100000 seconds passed of 20.000000}"));
		OO_CHECK(sRemoved == nil);

		// Twenty seconds: removed.
		[cascade update:20.0];
		OO_CHECK(sRemoved == cascade);
	}
}


OO_TEST_MAIN()
