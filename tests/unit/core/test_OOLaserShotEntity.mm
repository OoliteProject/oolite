/*	test_OOLaserShotEntity.mm
	Unit tests for OOLaserShotEntity (src/Core/Entities/OOLaserShotEntity.h), the beam a ship's laser
	draws for one shot: bead oo-5zpq, a leaf of the Entities pattern seam (amendment oo-bj8 item 12).

	Its object needs the game graph, so the test links the whole game but main (['*']) and uses a
	Universe that was never initialised, of a test subclass that records what is removed, and a plain
	entity as PLAYER. The ship that fires is an entity of the test's own that answers the selectors
	the class sends a ship (its root ship, speed and weapon range); the class asserts that it is a
	ship, so the test sets that flag. The expectations were written against the Objective-C API and
	run on the unconverted class first: where the shot starts and how it is turned for each facing,
	its velocity, owner, range and status; its colour (default red, a set colour brightened, the
	alpha constant); the lifetime in its description; following the player's ship; removal when its
	lifetime has run out. The colour is private; the test reads it through the access struct below,
	the only lines the conversion ported (amendment oo-862e item 2).
	Run: bash tools/check-core-tests.sh
*/

#import "OOLaserShotEntity.h"
#import "OOColor.h"
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


// UNIVERSE: never initialised; records what is removed.
@interface TestUniverse: Universe
@end


@implementation TestUniverse

- (OOTimeAbsolute) getTime				{ return 0; }
- (BOOL) removeEntity:(Entity *)entity	{ sRemoved = entity; return YES; }

@end


// The ship that fires: what OOLaserShotEntity asks of a ShipEntity.
@interface TestShip: Entity
@end


@implementation TestShip

- (ShipEntity *) rootShipEntity	{ return (ShipEntity *)self; }
- (GLfloat) flightSpeed			{ return 50.0f; }
- (GLfloat) weaponRange			{ return 1000.0f; }

@end


// --- The private colour, and nothing else ---------------------------------------------------------

struct OOLaserShotEntityTestAccess
{
	static const GLfloat *Color(OOLaserShotEntity *e)	{ return oo::ToCxx(e)->_color; }
};

// --------------------------------------------------------------------------------------------------


namespace {

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


TestShip *MakeShip()
{
	TestShip *ship = [[[TestShip alloc] init] autorelease];
	ship->_cxxEntity->isShip = YES;
	[ship setPosition:make_HPvector(100, 0, 0)];
	return ship;
}


bool Near(double a, double b)  { return fabs(a - b) < 1e-4; }


bool ColorIs(OOLaserShotEntity *e, GLfloat r, GLfloat g, GLfloat b, GLfloat a)
{
	const GLfloat *c = OOLaserShotEntityTestAccess::Color(e);
	return Near(c[0], r) && Near(c[1], g) && Near(c[2], b) && Near(c[3], a);
}

}	// namespace


OO_TEST(laserFromShip)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = MakeShip();
		OOLaserShotEntity *shot = [OOLaserShotEntity laserFromShip:(ShipEntity *)ship direction:WEAPON_FACING_FORWARD offset:make_vector(0, 0, 10)];
		OO_CHECK(shot != nil && [shot class] == [OOLaserShotEntity class]);
		OO_CHECK(HPvector_equal([shot position], make_HPvector(100, 0, 10)));
		OO_CHECK(vector_equal([shot velocity], make_vector(0, 0, 50)));
		OO_CHECK(quaternion_equal([shot orientation], kIdentityQuaternion));
		OO_CHECK([shot owner] == ship);
		OO_CHECK([shot collisionRadius] == 1000.0f);
		OO_CHECK([shot status] == STATUS_EFFECT && [shot isEffect] && ![shot canCollide]);
		OO_CHECK(ColorIs(shot, 1.0f / 3.0f, 0.0f, 0.0f, 0.09f));
		OO_CHECK(oo::DescriptionOf(shot).starts_with("<OOLaserShotEntity 0x"));
		OO_CHECK(oo::DescriptionOf(shot).find("{ttl: 0.090s - position: (100, 0, 10)") != std::string::npos);

		// The other facings turn the shot about the ship's up axis.
		OOLaserShotEntity *aft = [OOLaserShotEntity laserFromShip:(ShipEntity *)ship direction:WEAPON_FACING_AFT offset:kZeroVector];
		Vector forward = vector_forward_from_quaternion([aft orientation]);
		OO_CHECK(Near(forward.x, 0) && Near(forward.z, -1));
		OOLaserShotEntity *port = [OOLaserShotEntity laserFromShip:(ShipEntity *)ship direction:WEAPON_FACING_PORT offset:kZeroVector];
		OOLaserShotEntity *starboard = [OOLaserShotEntity laserFromShip:(ShipEntity *)ship direction:WEAPON_FACING_STARBOARD offset:kZeroVector];
		Vector portForward = vector_forward_from_quaternion([port orientation]);
		Vector starboardForward = vector_forward_from_quaternion([starboard orientation]);
		OO_CHECK(Near(fabs(portForward.x), 1) && Near(portForward.x, -starboardForward.x) && Near(portForward.z, 0));
	}
}


OO_TEST(color)
{
	@autoreleasepool
	{
		SetUp();
		OOLaserShotEntity *shot = [OOLaserShotEntity laserFromShip:(ShipEntity *)MakeShip() direction:WEAPON_FACING_FORWARD offset:kZeroVector];
		// Brightened five times, then a third; the alpha stays.
		[shot setColor:[OOColor colorWithRed:0.3f green:0.6f blue:0.9f alpha:0.1f]];
		OO_CHECK(ColorIs(shot, 0.5f, 1.0f, 1.5f, 0.09f));
		[shot setColor:nil];
		OO_CHECK(ColorIs(shot, 0.0f, 0.0f, 0.0f, 0.09f));

		[shot setRange:250.0f];
		OO_CHECK([shot collisionRadius] == 250.0f);

		// Nothing is drawn in the opaque pass.
		[shot drawImmediate:false translucent:false];
	}
}


OO_TEST(update)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = MakeShip();
		OOLaserShotEntity *shot = [OOLaserShotEntity laserFromShip:(ShipEntity *)ship direction:WEAPON_FACING_FORWARD offset:make_vector(0, 0, 10)];

		// An NPC's shot moves by its velocity.
		[shot update:0.05];
		OO_CHECK(HPvector_equal([shot position], make_HPvector(100, 0, 12.5)));
		OO_CHECK(sRemoved == nil);
		[shot update:0.05];
		OO_CHECK(sRemoved == shot);

		// The player's shot is put back where its ship's laser is.
		sRemoved = nil;
		ship->_cxxEntity->isPlayer = YES;
		OOLaserShotEntity *playerShot = [OOLaserShotEntity laserFromShip:(ShipEntity *)ship direction:WEAPON_FACING_FORWARD offset:make_vector(0, 0, 10)];
		[ship setPosition:make_HPvector(200, 0, 0)];
		[playerShot update:0.05];
		OO_CHECK(HPvector_equal([playerShot position], make_HPvector(200, 0, 10)));
		OO_CHECK(quaternion_equal([playerShot orientation], kIdentityQuaternion));
		OO_CHECK(sRemoved == nil);
	}
}


OO_TEST_MAIN()
