/*	test_ShipEntity.mm
	Unit tests for ShipEntity (src/Core/Entities/ShipEntity.h), the ship: slice 1 of its slice plan
	(docs/phases/3-slices/ShipEntity.md, bead oo-60fwo), the class shell, which moves the ship's
	state into cxx::ShipEntity and keeps the Objective-C ShipEntity as its facade (proposed
	ADR-0056, amendments oo-bj8 and oo-60fwo).

	Like Entity's, the ship's object needs the game graph, so the test links the whole game but
	main (['*']) and uses a Universe that was never initialised, a plain entity as PLAYER
	(amendment oo-bj8 item 11), and an empty JavaScript context for the events the ship sends its
	scripts. The ship is a subclass whose -setUpShipFromDictionary: only counts (the set-up from
	shipdata is slices 2 and 3, and needs the game's data), so the cases test the slice's own units:
	the initialisers (what -cxx_initWithKey:definition: sets before the set-up, the set-up
	failing, the top-speed sanity check, -initBypassForPlayer, and -init sent again as
	PlayerEntity's -deferredInit does), -dealloc (it leaves the ship's groups), and the two
	SubEntityRelationship categories. The expectations were written against the Objective-C API
	and run on the unconverted class first. Ivars the game reads directly go through the block of
	helpers below, the one place that knows where they live. The tests after those pin the
	crossing: an Objective-C ship's C++ part is a cxx::ShipEntity, the facade's _cxxShip is that
	part, and a ship released before its initialiser ran is deallocated without a C++ part.
	Run: bash tools/check-core-tests.sh
*/

#import "ShipEntity.h"
#import "OOShipGroup.h"
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
extern JSContext *gOOJSMainThreadContext;


@interface TestPlayer: Entity
@end


@implementation TestPlayer

- (HPVector) viewpointPosition	{ return kZeroHPVector; }

@end


// Declared by nothing public: PlayerEntity and the ship's own set-up declare them privately.
@interface ShipEntity (TestPrivate)
- (id) initBypassForPlayer;
- (void) addSubEntity:(Entity<OOSubEntity> *)subent;
@end


namespace {

// What the next ship's set-up does.
bool sFailSetUp = false;
bool sInfiniteSpeed = false;

}	// namespace


// A ship whose set-up from shipdata only counts and records what it was given.
@interface TestShip: ShipEntity
{
@public
	int			_setUps;
	oo::PList	_setUpDict;
}
@end


@implementation TestShip

- (BOOL) setUpShipFromDictionary:(const oo::PList &)dict
{
	_setUps++;
	_setUpDict = dict;
	if (sInfiniteSpeed)  [self setMaxFlightSpeed:INFINITY];
	return !sFailSetUp;
}

@end


namespace {

// --- Ivars the game reads directly (ship->shot_time), and nothing else ----------------------------

OOTimeDelta ShotTime(ShipEntity *s)		{ return s->_cxxShip->shot_time; }
OOBehaviour Behaviour(ShipEntity *s)	{ return s->_cxxShip->behaviour; }
void SetSubEntity(Entity *e, bool value)	{ e->_cxxEntity->isSubEntity = value; }

// --------------------------------------------------------------------------------------------------


void SetUp()
{
	static Universe *universe = nil;
	if (universe == nil)  universe = (Universe *)class_createInstance([Universe class], 0);	// never released
	gSharedUniverse = universe;
	static TestPlayer *player = nil;
	if (player == nil)  player = [[TestPlayer alloc] init];
	gOOPlayer = (PlayerEntity *)player;
	// The ship's -dealloc sends its (absent) scripts entityDestroyed in a request on the main
	// thread's context, so there is one, with nothing in it.
	if (gOOJSMainThreadContext == nullptr)  gOOJSMainThreadContext = JS_NewContext(JS_NewRuntime());
	sFailSetUp = false;
	sInfiniteSpeed = false;
}


oo::PList Definition()
{
	return oo::PList(oo::PList::Dict{ { "max_flight_speed", oo::PList(250.0) } });
}

}	// namespace


OO_TEST(initWithKeyAndDefinition)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = [[[TestShip alloc] cxx_initWithKey:"test-ship" definition:Definition()] autorelease];
		OO_CHECK(ship != nil);
		OO_CHECK(ship->_setUps == 1 && ship->_setUpDict.get<double>("max_flight_speed", 0) == 250.0);
		OO_CHECK([ship isShip] && ![ship isStation] && ![ship isPlayer]);
		OO_CHECK([ship cxx_shipDataKey] == std::optional<std::string>("test-ship"));
		OO_CHECK([ship status] == STATUS_IN_FLIGHT);
		OO_CHECK([ship zeroDistance] == (GLfloat)(SCANNER_MAX_RANGE2 * 2.0));
		OO_CHECK([ship weaponRechargeRate] == 6.0f);
		OO_CHECK(ShotTime(ship) == INITIAL_SHOT_TIME);
		OO_CHECK([ship temperature] == SHIP_MIN_CABIN_TEMP);
		OO_CHECK([ship currentWeaponFacing] == WEAPON_FACING_FORWARD);
		OO_CHECK([ship laserHeatLevelForward] == 0 && [ship laserHeatLevelAft] == 0 && [ship laserHeatLevelPort] == 0 && [ship laserHeatLevelStarboard] == 0);
		OO_CHECK([ship entityPersonalityInt] >= 0 && [ship entityPersonalityInt] <= (GLint)ENTITY_PERSONALITY_MAX);
		OO_CHECK([ship maxFlightSpeed] == 0);	// the set-up did not set it
		OO_CHECK(Behaviour(ship) == BEHAVIOUR_IDLE);
	}
}


OO_TEST(initIsAnEmptyKey)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = [[[TestShip alloc] init] autorelease];
		OO_CHECK(ship != nil && ship->_setUps == 1 && ship->_setUpDict.isNull());
		OO_CHECK([ship cxx_shipDataKey] == std::optional<std::string>(""));
		OO_CHECK([ship isShip] && [ship status] == STATUS_IN_FLIGHT);
	}
}


OO_TEST(initFailsWhenSetUpFails)
{
	@autoreleasepool
	{
		SetUp();
		sFailSetUp = true;
		TestShip *ship = [[TestShip alloc] cxx_initWithKey:"bad" definition:Definition()];
		OO_CHECK(ship == nil);
	}
}


OO_TEST(initClampsAnInfiniteTopSpeed)
{
	@autoreleasepool
	{
		SetUp();
		sInfiniteSpeed = true;
		TestShip *ship = [[[TestShip alloc] cxx_initWithKey:"fast" definition:Definition()] autorelease];
		OO_CHECK(ship != nil && [ship maxFlightSpeed] == 300.0f);
	}
}


OO_TEST(initBypassForPlayer)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = [[[TestShip alloc] initBypassForPlayer] autorelease];
		OO_CHECK(ship != nil && ship->_setUps == 0);
		OO_CHECK(![ship isShip] && [ship status] == STATUS_COCKPIT_DISPLAY);
		OO_CHECK([ship cxx_shipDataKey] == std::nullopt);
		OO_CHECK([ship temperature] == 0 && [ship weaponRechargeRate] == 0 && ShotTime(ship) == 0);
	}
}


// PlayerEntity's -deferredInit: made by -initBypassForPlayer, then sent -[ShipEntity
// cxx_initWithKey:definition:] (and so -init) again. The ship keeps its C++ part, the body runs
// again over it, and what the body does not set stays.
OO_TEST(initSentAgain)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = [[[TestShip alloc] initBypassForPlayer] autorelease];
		Entity *asEntity = ship;
		void *part = oo::ToCxx(asEntity);
		[ship setFuel:5];
		[ship setEnergy:42];
		OO_CHECK([ship cxx_initWithKey:"player" definition:Definition()] == ship);
		OO_CHECK((void *)oo::ToCxx(asEntity) == part);
		OO_CHECK(ship->_setUps == 1 && [ship isShip] && [ship status] == STATUS_IN_FLIGHT);
		OO_CHECK([ship cxx_shipDataKey] == std::optional<std::string>("player"));
		OO_CHECK([ship fuel] == 5 && [ship energy] == 42);
		OO_CHECK([ship temperature] == SHIP_MIN_CABIN_TEMP && ShotTime(ship) == INITIAL_SHOT_TIME);
#ifndef NDEBUG
		gLiveEntityCount--;		// the second -init counted it again, as it did
		gTotalEntityMemory -= class_getInstanceSize([TestShip class]);
#endif
	}
}


OO_TEST(deallocLeavesItsGroups)
{
	OOShipGroup *group = nil;
	OOShipGroup *escorts = nil;
	@autoreleasepool
	{
		SetUp();
		group = [[OOShipGroup alloc] init];
		TestShip *ship = [[TestShip alloc] cxx_initWithKey:"grouped" definition:Definition()];
		[ship setGroup:group];
		escorts = [[ship escortGroup] retain];
		OO_CHECK([group containsShip:ship] && [escorts containsShip:ship] && [escorts leader] == ship);
		[ship release];
	}
	OO_CHECK([group count] == 0 && [escorts count] == 0);
	[group release];
	[escorts release];
}


OO_TEST(subEntityRelationship)
{
	@autoreleasepool
	{
		SetUp();
		Entity *plain = [[[Entity alloc] init] autorelease];
		TestShip *ship = [[[TestShip alloc] cxx_initWithKey:"mother" definition:Definition()] autorelease];
		TestShip *sub = [[[TestShip alloc] cxx_initWithKey:"turret" definition:Definition()] autorelease];
		TestShip *other = [[[TestShip alloc] cxx_initWithKey:"other" definition:Definition()] autorelease];

		// Entity's: never.
		OO_CHECK(![plain isShipWithSubEntityShip:ship]);
		[(Entity<OOSubEntity> *)plain drawSubEntityImmediate:true translucent:false];	// does nothing

		// The ship's: a ship that is its subentity, and that it agrees is.
		OO_CHECK(![ship isShipWithSubEntityShip:plain]);
		OO_CHECK(![ship isShipWithSubEntityShip:sub]);		// not a subentity
		[ship addSubEntity:sub];
		OO_CHECK([sub owner] == ship && [ship hasSubEntity:sub]);
		OO_CHECK([ship isShipWithSubEntityShip:sub]);
		OO_CHECK(![other isShipWithSubEntityShip:sub]);		// someone else's
#ifndef NDEBUG
		// A ship that claims the parent, which does not agree: an internal error, and it is cut loose.
		SetSubEntity(other, true);
		[other setOwner:ship];
		OO_CHECK(![ship isShipWithSubEntityShip:other]);
		OO_CHECK([other owner] == nil);
		SetSubEntity(other, false);
#endif
		[ship clearSubEntities];
		OO_CHECK([sub owner] == nil);
	}
}


// --- The crossing (after the conversion) ---------------------------------------------------------

// An Objective-C ship's C++ part is a cxx::ShipEntity, and the facade's typed alias is that part.
OO_TEST(objCShipPartIsAShip)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = [[[TestShip alloc] cxx_initWithKey:"crossing" definition:Definition()] autorelease];
		Entity *asEntity = ship;
		cxx::ShipEntity *part = oo::ToCxx(ship);
		OO_CHECK(part != nullptr && part == ship->_cxxShip);
		OO_CHECK(dynamic_cast<cxx::ShipEntity *>(oo::ToCxx(asEntity)) == part);
		OO_CHECK(oo::AsObjCEntity(part) != nullptr && oo::ToObjC(part) == ship);
		OO_CHECK(part->getIsShip() && part->_shipKey == std::optional<std::string>("crossing"));

		// From C++, a member that a subclass overrides reaches the Objective-C override.
		part->setStatus(STATUS_LAUNCHING);
		OO_CHECK([ship status] == STATUS_LAUNCHING);
		OO_CHECK(part->isShipWithSubEntityShip(asEntity) == false);

		// A ship made the player's way has its part as well.
		TestShip *bypass = [[[TestShip alloc] initBypassForPlayer] autorelease];
		OO_CHECK(bypass->_cxxShip != nullptr && bypass->_cxxShip == oo::ToCxx(static_cast<Entity *>(bypass)));
	}
}


// A failing initialiser that releases the ship before [super init] (the Objective-C idiom): the
// facade's -dealloc runs without a C++ part, as the root's does (oo-s6ic6).
OO_TEST(releasedBeforeInit)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = [TestShip alloc];
		OO_CHECK(ship->_cxxShip == nullptr);
		[ship release];
	}
}


OO_TEST_MAIN()
