/*	test_PlayerEntity.mm
	Unit tests for PlayerEntity (src/Core/Entities/PlayerEntity.h), the player's ship: slice 1 of
	its slice plan (docs/phases/3-slices/PlayerEntity.md), the class shell, which moves the
	player's state into cxx::PlayerEntity and keeps the Objective-C PlayerEntity as its facade, a
	subclass of the ship's.

	Like the ship's, the player's object needs the game graph, so the test links the whole game but
	main (['*']) and uses a Universe that was never initialised and an empty JavaScript context for
	the events the ship sends its scripts. The player is made in two steps, as the game makes it:
	-init (+sharedPlayer) early in start-up, before there is ship data, and -deferredInit once there
	is. Setting the player up from shipdata, the session and the controls (slice 5 and
	PlayerEntityControls) need the game's data, so a subclass stands in for those three and only
	counts; the cases test the slice's own units: +sharedPlayer, -init (the ship made the player's
	way, and the only player), -deferredInit (the ship's initialiser sent again over the same
	object, and the player's own defaults), and -dealloc (it releases what the player held, and a
	player released before its initialiser ran). The expectations were written against the
	Objective-C API and run on the unconverted class first. Ivars the test reads or sets go through
	the category below, the one place that knows where they live. The tests after those pin the
	crossing: an Objective-C player's C++ part is a cxx::PlayerEntity, and the facade's _cxxPlayer
	is that part.
	Run: bash tools/check-core-tests.sh test_PlayerEntity
*/

#import "PlayerEntity.h"
#import "MyOpenGLView.h"
#import "OODescription.h"
#import "Universe.h"

#include "oo_test.hpp"

#include <cmath>
#include <string>


// main.mm defines the debug flags, and the test has its own main.
#ifndef NDEBUG
uint32_t gDebugFlags = 0;
#endif

extern PlayerEntity *gOOPlayer;
extern Universe *gSharedUniverse;
extern JSContext *gOOJSMainThreadContext;


// --- Ivars the test reads or sets, and nothing else ------------------------------------------------

@interface PlayerEntity (TestIvars)
- (double) testMaxFieldOfView;
- (BOOL) testScoopsActive;
- (NSUInteger) testTargetMemoryIndex;
- (ShipEntity *) testMissileAtPylon:(int)pylon;
- (void) testSetMissile:(ShipEntity *)missile atPylon:(int)pylon;
- (void) testSetSavePath:(const std::string &)path;
- (BOOL) testHasSavePath;
@end


@implementation PlayerEntity (TestIvars)

- (double) testMaxFieldOfView	{ return _cxxPlayer->maxFieldOfView; }
- (BOOL) testScoopsActive	{ return _cxxPlayer->scoopsActive; }
- (NSUInteger) testTargetMemoryIndex	{ return _cxxPlayer->target_memory_index; }
- (ShipEntity *) testMissileAtPylon:(int)pylon	{ return _cxxPlayer->missile_entity[pylon]; }
- (void) testSetMissile:(ShipEntity *)missile atPylon:(int)pylon	{ _cxxPlayer->missile_entity[pylon] = [missile retain]; }
- (void) testSetSavePath:(const std::string &)path	{ _cxxPlayer->save_path = path; }
- (BOOL) testHasSavePath	{ return _cxxPlayer->save_path.has_value(); }

@end

// --------------------------------------------------------------------------------------------------


namespace {

// What the stand-ins were sent.
int sShipSetUps = 0;
oo::PList sShipSetUpDict;
int sPlayerSetUps = 0;
BOOL sPlayerSetUpStopOnError = YES;
int sInitControls = 0;

}	// namespace


// A player whose set-up from shipdata, session set-up and controls only count (slice 5's units and
// PlayerEntityControls', which need the game's data).
@interface TestPlayer: PlayerEntity
@end


@implementation TestPlayer

- (BOOL) setUpShipFromDictionary:(const oo::PList &)dict
{
	sShipSetUps++;
	sShipSetUpDict = dict;
	return YES;
}


- (BOOL) setUpAndConfirmOK:(BOOL)stopOnError
{
	sPlayerSetUps++;
	sPlayerSetUpStopOnError = stopOnError;
	return YES;
}


- (void) initControls
{
	sInitControls++;
}

@end


// A ship that stands in for a missile on a pylon.
@interface TestMissile: ShipEntity
@end


@implementation TestMissile

- (BOOL) setUpShipFromDictionary:(const oo::PList &)dict	{ return YES; }

@end


namespace {

void SetUp()
{
	static Universe *universe = nil;
	if (universe == nil)
	{
		universe = (Universe *)class_createInstance([Universe class], 0);	// never released
		universe->_cxxUniverse = oo::makeRef<cxx::Universe>(universe);	// what -initWithGameView: makes first (ADR-0056 amendment oo-riqmz)
	}
	gSharedUniverse = universe;
	gOOPlayer = nil;	// -init expects to make the only player
	// The ship's -dealloc sends its (absent) scripts entityDestroyed in a request on the main
	// thread's context, so there is one, with nothing in it.
	if (gOOJSMainThreadContext == nullptr)  gOOJSMainThreadContext = JS_NewContext(JS_NewRuntime());
	sShipSetUps = 0;
	sShipSetUpDict = oo::PList();
	sPlayerSetUps = 0;
	sPlayerSetUpStopOnError = YES;
	sInitControls = 0;
}


#ifndef NDEBUG
// -deferredInit sends the ship's initialiser, and so the root's -init, a second time, which counts
// the entity again, as it did.
void UncountSecondInit(Class cls)
{
	gLiveEntityCount--;
	gTotalEntityMemory -= class_getInstanceSize(cls);
}
#endif

}	// namespace


// -init: the ship made the player's way (-initBypassForPlayer), not set up from shipdata, not yet
// the player, and not yet the shared player.
OO_TEST(initIsTheShipMadeThePlayersWay)
{
	@autoreleasepool
	{
		SetUp();
		TestPlayer *player = [[TestPlayer alloc] init];
		OO_CHECK(player != nil);
		OO_CHECK(sShipSetUps == 0 && sPlayerSetUps == 0 && sInitControls == 0);
		OO_CHECK(![player isShip] && ![player isPlayer]);
		OO_CHECK([player status] == STATUS_COCKPIT_DISPLAY);
		OO_CHECK([player cxx_shipDataKey] == std::nullopt);
		OO_CHECK([player temperature] == 0 && [player weaponRechargeRate] == 0);
		OO_CHECK([player testMaxFieldOfView] == 0);
		OO_CHECK(gOOPlayer == nil);
		[player release];
	}
}


// +sharedPlayer: made once, by -init, and kept.
OO_TEST(sharedPlayer)
{
	PlayerEntity *player = nil;
	@autoreleasepool
	{
		SetUp();
		player = [PlayerEntity sharedPlayer];
		OO_CHECK(player != nil && [player class] == [PlayerEntity class]);
		OO_CHECK(gOOPlayer == player);
		OO_CHECK([PlayerEntity sharedPlayer] == player);
		OO_CHECK(![player isPlayer] && [player status] == STATUS_COCKPIT_DISPLAY);
	}
	gOOPlayer = nil;
	[player release];
}


// -deferredInit: the ship's initialiser sent again with the player's ship key and an empty
// definition, which keeps the object (and its C++ part) and runs the ship's body over it; then
// the player's own defaults, the session set-up, and the controls.
OO_TEST(deferredInit)
{
	@autoreleasepool
	{
		SetUp();
		TestPlayer *player = [[TestPlayer alloc] init];
		gOOPlayer = player;
		Entity *asEntity = player;
		void *part = oo::ToCxx(asEntity);
		[player setFuel:5];
		[player testSetSavePath:"some.oolite-save"];

		[player deferredInit];
		OO_CHECK((void *)oo::ToCxx(asEntity) == part);
		OO_CHECK(sShipSetUps == 1 && sShipSetUpDict.isDict() && sShipSetUpDict.getIf<oo::PList::Dict>()->empty());
		OO_CHECK([player cxx_shipDataKey] == std::optional<std::string>(std::string(PLAYER_SHIP_DESC)));
		OO_CHECK([player isShip] && [player isPlayer]);
		OO_CHECK([player status] == STATUS_START_GAME);
		OO_CHECK([player temperature] == SHIP_MIN_CABIN_TEMP && [player weaponRechargeRate] == 6.0f);
		OO_CHECK([player fuel] == 5);	// what the bodies do not set stays
		OO_CHECK(std::fabs([player testMaxFieldOfView] - MAX_FOV) < 1e-6);
		OO_CHECK([player compassMode] == COMPASS_MODE_BASIC);
		OO_CHECK(![player testScoopsActive] && [player testTargetMemoryIndex] == 0);
		OO_CHECK(![player testHasSavePath]);
		for (int i = 0; i < PLAYER_MAX_MISSILES; i++)  OO_CHECK([player testMissileAtPylon:i] == nil);
		OO_CHECK(sPlayerSetUps == 1 && sPlayerSetUpStopOnError == NO);
		OO_CHECK(sInitControls == 1);

		gOOPlayer = nil;
		[player release];
#ifndef NDEBUG
		UncountSecondInit([TestPlayer class]);
#endif
	}
}


// -dealloc releases what the player held (here, a missile on a pylon), and the ship's -dealloc
// runs after it.
OO_TEST(deallocReleasesWhatThePlayerHeld)
{
	TestMissile *missile = nil;
	@autoreleasepool
	{
		SetUp();
		missile = [[TestMissile alloc] cxx_initWithKey:"missile" definition:oo::PList()];
		TestPlayer *player = [[TestPlayer alloc] init];
		[player testSetMissile:missile atPylon:2];
		OO_CHECK([missile retainCount] == 2);
		OO_CHECK([player testMissileAtPylon:2] == missile);
		[player release];
	}
	OO_CHECK([missile retainCount] == 1);
	[missile release];
}


// A player released before its initialiser ran (alloc, then release): -dealloc runs without
// having been set up, as the ship's and the root's do.
OO_TEST(releasedBeforeInit)
{
	@autoreleasepool
	{
		SetUp();
		TestPlayer *player = [TestPlayer alloc];
		[player release];
		OO_CHECK(gOOPlayer == nil);
	}
}


// The crossing: an Objective-C player's C++ part is a cxx::PlayerEntity, the facade's _cxxPlayer,
// beside the ship's _cxxShip, and the ship's adapter lines reach the player's overrides.
OO_TEST(objCPlayerPartIsAPlayer)
{
	@autoreleasepool
	{
		SetUp();
		TestPlayer *player = [[TestPlayer alloc] init];
		Entity *asEntity = player;
		cxx::PlayerEntity *part = oo::ToCxx(player);
		OO_CHECK(part != nullptr && part == player->_cxxPlayer);
		OO_CHECK(static_cast<cxx::ShipEntity *>(part) == player->_cxxShip);
		OO_CHECK(dynamic_cast<cxx::PlayerEntity *>(oo::ToCxx(asEntity)) == part);
		OO_CHECK(oo::AsObjCEntity(part) != nullptr && oo::ToObjC(part) == player);

		cxx::ShipEntity *asShip = part;
		OO_CHECK(asShip->setUpShipFromDictionary(oo::PList()) && sShipSetUps == 1);
		[player release];
	}
}


// Every member starts zeroed, as the runtime zeroed the ivars.
OO_TEST(membersStartZeroed)
{
	@autoreleasepool
	{
		SetUp();
		TestPlayer *player = [[TestPlayer alloc] init];
		cxx::PlayerEntity *part = player->_cxxPlayer;
		OO_CHECK(part->hud == nil && part->compassTarget == nil && part->wormhole == nil);
		OO_CHECK(part->system_id == 0 && part->ship_clock == 0 && part->scoopsActive == NO);
		for (int i = 0; i < PLAYER_MAX_MISSILES; i++)  OO_CHECK(part->missile_entity[i] == nil);
		OO_CHECK(!part->save_path.has_value() && part->worldScripts.empty());
		[player release];
	}
}


OO_TEST_MAIN()
