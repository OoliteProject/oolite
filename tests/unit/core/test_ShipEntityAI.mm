/*	test_ShipEntityAI.mm
	Unit tests for ShipEntityAI.mm, the legacy plist-AI surface of ShipEntity: its slices
	(docs/phases/3-slices/ShipEntityAI.md, beads oo-iebuz, oo-xurzn, oo-wc9o3, oo-lqyhf) move the
	categories' methods into cxx::ShipEntity members, defined in the category's file, and leave
	forwarders on the Objective-C ShipEntity facade (proposed ADR-0056, amendments oo-o89 item 4 and
	oo-mvzmb).

	As test_ShipEntity's, the ship's object needs the game graph, so the test links the whole game
	but main (['*']) and uses a Universe that was never initialised (no entities, so every scan finds
	nothing), a plain entity as PLAYER and an empty JavaScript context. Its ships have no AI and are
	invisible to scripts, so the AI messages and script events the methods send go nowhere. Each
	slice adds its cases under a comment naming it, written against the Objective-C API and run on
	the unconverted class first. Ivars go through the helpers below.
	Run: bash tools/check-core-tests.sh test_ShipEntityAI
*/

#import "ShipEntity.h"
#import "ShipEntityAI.h"
#import "StationEntity.h"
#import "Universe.h"
#import "PlayerEntity.h"

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


@interface TestAIPlayer: Entity
@end


@implementation TestAIPlayer

- (HPVector) viewpointPosition	{ return kZeroHPVector; }

@end


// The private categories of ShipEntityAI.mm.
@interface ShipEntity (TestAIPrivate)
- (void) checkFoundTarget;
- (BOOL) performHyperSpaceExitReplace:(BOOL)replace;
- (BOOL) performHyperSpaceExitReplace:(BOOL)replace toSystem:(OOSystemID)systemID;
- (void) scanForNearestShipWithPredicate:(EntityFilterPredicate)predicate parameter:(void *)parameter;
- (void) scanForNearestShipWithNegatedPredicate:(EntityFilterPredicate)predicate parameter:(void *)parameter;
- (void) acceptDistressMessageFrom:(ShipEntity *)other;
- (void) performBuoyTumble;	// defined by the AI category, declared nowhere
@end


// A ship whose set-up from shipdata does nothing, and that scripts cannot see.
@interface TestAIShip: ShipEntity
@end


@implementation TestAIShip

- (BOOL) setUpShipFromDictionary:(const oo::PList &)dict	{ return YES; }
- (BOOL) isVisibleToScripts	{ return NO; }

@end


// A station whose virtual dock is not made (the dock is a shipdata entry), invisible to scripts.
@interface TestAIStation: StationEntity
@end


@implementation TestAIStation

- (BOOL) cxx_setUpOneStandardSubentity:(const oo::PList &)subentDict asTurret:(BOOL)asTurret	{ return YES; }
- (BOOL) isVisibleToScripts	{ return NO; }

@end


namespace {

OOBehaviour Behaviour(ShipEntity *s)			{ return s->_cxxShip->behaviour; }
void SetBehaviour(ShipEntity *s, OOBehaviour b)	{ s->_cxxShip->behaviour = b; }
GLfloat Frustration(ShipEntity *s)				{ return s->_cxxShip->frustration; }
void SetFrustration(ShipEntity *s, GLfloat f)	{ s->_cxxShip->frustration = f; }
GLfloat DesiredSpeed(ShipEntity *s)				{ return s->_cxxShip->desired_speed; }
void SetDesiredSpeed(ShipEntity *s, GLfloat v)	{ s->_cxxShip->desired_speed = v; }
GLfloat DesiredRange(ShipEntity *s)				{ return s->_cxxShip->desired_range; }
GLfloat StickRoll(ShipEntity *s)				{ return s->_cxxShip->stick_roll; }
GLfloat StickPitch(ShipEntity *s)				{ return s->_cxxShip->stick_pitch; }
void SetMaxFlight(ShipEntity *s, GLfloat speed, GLfloat roll, GLfloat pitch)	{ s->_cxxShip->maxFlightSpeed = speed; s->_cxxShip->max_flight_roll = roll; s->_cxxShip->max_flight_pitch = pitch; }
HPVector Destination(ShipEntity *s)				{ return s->_cxxShip->_destination; }
bool MatchRotation(ShipEntity *s)				{ return s->_cxxShip->docking_match_rotation; }
void SetDockingInstructions(ShipEntity *s, const oo::PList &instructions)	{ s->_cxxShip->dockingInstructions = instructions; }
void SetScannerRange(ShipEntity *s, GLfloat r)	{ s->_cxxShip->scannerRange = r; }
void SetAccuracy(ShipEntity *s, GLfloat a)		{ s->_cxxShip->accuracy = a; }
void SetNearPlanetSurface(ShipEntity *s, bool v)	{ s->_cxxShip->isNearPlanetSurface = v; }
void SetPrimaryTarget(ShipEntity *s, Entity *target)
{
	[s->_cxxShip->_primaryTarget release];
	s->_cxxShip->_primaryTarget = [target weakRetain];
}


void SetUp()
{
	static Universe *universe = nil;
	if (universe == nil)
	{
		universe = (Universe *)class_createInstance([Universe class], 0);	// never released
		universe->_cxxUniverse = oo::makeRef<cxx::Universe>(universe);	// what -initWithGameView: makes first (ADR-0056 amendment oo-riqmz)
	}
	gSharedUniverse = universe;
	static TestAIPlayer *player = nil;
	if (player == nil)  player = [[TestAIPlayer alloc] init];
	gOOPlayer = (PlayerEntity *)player;
	if (gOOJSMainThreadContext == nullptr)  gOOJSMainThreadContext = JS_NewContext(JS_NewRuntime());
	ranrot_srand(20261007);	// as the game seeds it: an unseeded generator answers one value, and OOHPVectorRandomSpatial() never ends
}


TestAIShip *MakeShip(const char *key)
{
	return [[[TestAIShip alloc] cxx_initWithKey:key definition:oo::PList(oo::PList::Dict{})] autorelease];
}


BOOL AlwaysYes(Entity *, void *)	{ return YES; }

}	// namespace


// --- Slice 1: the AI category, OOAIPrivate (ship and station), the station stubs (bead oo-iebuz) ---

// The perform* behaviours: each sets its behaviour and resets the frustration.
OO_TEST(slice1Behaviours)
{
	@autoreleasepool
	{
		SetUp();
		TestAIShip *ship = MakeShip("pilot");
		struct { void (*perform)(TestAIShip *); OOBehaviour behaviour; } cases[] = {
			{ [](TestAIShip *s) { [s performCollect]; }, BEHAVIOUR_COLLECT_TARGET },
			{ [](TestAIShip *s) { [s performFaceDestination]; }, BEHAVIOUR_FACE_DESTINATION },
			{ [](TestAIShip *s) { [s performFlyToRangeFromDestination]; }, BEHAVIOUR_FLY_RANGE_FROM_DESTINATION },
			{ [](TestAIShip *s) { [s performIdle]; }, BEHAVIOUR_IDLE },
			{ [](TestAIShip *s) { [s performIntercept]; }, BEHAVIOUR_INTERCEPT_TARGET },
			{ [](TestAIShip *s) { [s performScriptedAI]; }, BEHAVIOUR_SCRIPTED_AI },
			{ [](TestAIShip *s) { [s performScriptedAttackAI]; }, BEHAVIOUR_SCRIPTED_ATTACK_AI },
		};
		for (const auto &c : cases)
		{
			SetBehaviour(ship, BEHAVIOUR_TUMBLE);
			SetFrustration(ship, 5);
			c.perform(ship);
			OO_CHECK(Behaviour(ship) == c.behaviour && Frustration(ship) == 0);
		}

		SetDesiredSpeed(ship, 50);
		SetFrustration(ship, 5);
		[ship performHold];
		OO_CHECK(Behaviour(ship) == BEHAVIOUR_TRACK_TARGET && DesiredSpeed(ship) == 0 && Frustration(ship) == 0);

		SetDesiredSpeed(ship, 50);
		[ship performStop];
		OO_CHECK(Behaviour(ship) == BEHAVIOUR_STOP_STILL && DesiredSpeed(ship) == 0);

		[ship performBuoyTumble];
		OO_CHECK(Behaviour(ship) == BEHAVIOUR_TUMBLE && StickRoll(ship) == 0.10f && StickPitch(ship) == 0.15f);

		SetMaxFlight(ship, 100, 2, 1);
		[ship performTumble];
		OO_CHECK(Behaviour(ship) == BEHAVIOUR_TUMBLE && std::fabs(StickRoll(ship)) <= 2.0f && std::fabs(StickPitch(ship)) <= 1.0f);

		SetBehaviour(ship, BEHAVIOUR_IDLE);
		[ship performEscort];
		OO_CHECK(Behaviour(ship) == BEHAVIOUR_FORMATION_FORM_UP && Frustration(ship) == 0);
		SetFrustration(ship, 5);
		[ship performEscort];		// already forming up: nothing changes
		OO_CHECK(Behaviour(ship) == BEHAVIOUR_FORMATION_FORM_UP && Frustration(ship) == 5);
	}
}


OO_TEST(slice1AttackFleeMiningLanding)
{
	@autoreleasepool
	{
		SetUp();
		TestAIShip *ship = MakeShip("fighter");
		SetBehaviour(ship, BEHAVIOUR_IDLE);
		[ship performAttack];
		OO_CHECK(Behaviour(ship) == BEHAVIOUR_ATTACK_TARGET && DesiredRange(ship) >= 750 && DesiredRange(ship) <= 2000);
		SetBehaviour(ship, BEHAVIOUR_EVASIVE_ACTION);
		[ship performAttack];		// evading: carries on
		OO_CHECK(Behaviour(ship) == BEHAVIOUR_EVASIVE_ACTION);

		SetAccuracy(ship, COMBAT_AI_ISNT_AWFUL);	// no aspect check
		SetBehaviour(ship, BEHAVIOUR_IDLE);
		[ship performFlee];
		OO_CHECK(Behaviour(ship) == BEHAVIOUR_FLEE_TARGET && Frustration(ship) == 0);
		SetBehaviour(ship, BEHAVIOUR_FLEE_EVASIVE_ACTION);
		[ship performFlee];
		OO_CHECK(Behaviour(ship) == BEHAVIOUR_FLEE_EVASIVE_ACTION);

		// Mining a target that is not a rock: lost target, idle.
		SetBehaviour(ship, BEHAVIOUR_TUMBLE);
		[ship performMining];
		OO_CHECK(Behaviour(ship) == BEHAVIOUR_IDLE);

		// Landing away from any planet's surface: idle.
		SetNearPlanetSurface(ship, false);
		SetBehaviour(ship, BEHAVIOUR_TUMBLE);
		SetFrustration(ship, 5);
		[ship performLandOnPlanet];
		OO_CHECK(Behaviour(ship) == BEHAVIOUR_IDLE && Frustration(ship) == 0);
	}
}


// The docking instructions a ship remembers: destination, speed (at most the ship's top speed),
// range and rotation matching.
OO_TEST(slice1RecallDockingInstructions)
{
	@autoreleasepool
	{
		SetUp();
		TestAIShip *ship = MakeShip("docker");
		SetMaxFlight(ship, 100, 1, 1);
		[ship recallDockingInstructions];		// none: nothing changes
		OO_CHECK(DesiredSpeed(ship) == 0);

		SetDockingInstructions(ship, oo::PList(oo::PList::Dict{
			{ "destination", oo::PList(oo::PList::Dict{ { "x", oo::PList(1.0) }, { "y", oo::PList(2.0) }, { "z", oo::PList(3.0) } }) },
			{ "speed", oo::PList(250.0) },
			{ "range", oo::PList(40.0) },
			{ "match_rotation", oo::PList(true) },
		}));
		[ship recallDockingInstructions];
		OO_CHECK(HPdistance2(Destination(ship), make_HPvector(1, 2, 3)) < 1e-9);
		OO_CHECK(DesiredSpeed(ship) == 100 && DesiredRange(ship) == 40 && MatchRotation(ship));
	}
}


// Scans in an empty universe find nothing, and forget what was found before.
OO_TEST(slice1ScansFindNothing)
{
	@autoreleasepool
	{
		SetUp();
		TestAIShip *ship = MakeShip("scanner");
		TestAIShip *other = MakeShip("other");
		SetScannerRange(ship, 25000);

		[ship setFoundTarget:other];
		[ship scanForHostiles];
		OO_CHECK([ship foundTarget] == nil);

		[ship setFoundTarget:other];
		[ship scanForNearestShipWithPredicate:AlwaysYes parameter:NULL];
		OO_CHECK([ship foundTarget] == nil);

		[ship setFoundTarget:other];
		[ship scanForNearestShipWithNegatedPredicate:AlwaysYes parameter:NULL];
		OO_CHECK([ship foundTarget] == nil);

		[ship setFoundTarget:other];
		[ship scanForNearestShipWithPredicate:NULL parameter:NULL];
		OO_CHECK([ship foundTarget] == nil);

		[ship setFoundTarget:other];
		[ship scanForNearestIncomingMissile];
		OO_CHECK([ship foundTarget] == nil);

		[ship checkFoundTarget];		// no AI: nothing to tell
	}
}


// What the AI category does when there is nothing to act on.
OO_TEST(slice1NothingToActOn)
{
	@autoreleasepool
	{
		SetUp();
		TestAIShip *ship = MakeShip("loner");
		TestAIShip *other = MakeShip("other");

		// No escort to suggest to: the ship is its own owner.
		OO_CHECK(![ship suggestEscortTo:nil]);
		OO_CHECK([ship owner] == ship);

		// No aggressor: no distress call.
		[ship broadcastDistressMessage];
		[ship broadcastDistressMessageWithDumping:NO];
		OO_CHECK([ship foundTarget] == nil);

		// No primary target: no group attack, and a target that is not a wormhole: no escorts sent.
		[ship groupAttackTarget];
		OO_CHECK([ship foundTarget] == nil);
		SetPrimaryTarget(ship, other);
		[ship wormholeEscorts];
		OO_CHECK([ship primaryTarget] == other);

		// A ship that alone answers a request for help: it takes the target as found.
		[ship groupAttackTarget];
		OO_CHECK([ship foundTarget] == other);

		// Already entering witchspace: no second jump (the universe's destinations are not asked).
		[ship setStatus:STATUS_ENTERING_WITCHSPACE];
		OO_CHECK(![ship performHyperSpaceToSpecificSystem:7]);
		OO_CHECK(![ship performHyperSpaceExitReplace:NO]);
		OO_CHECK(![ship performHyperSpaceExitReplace:YES toSystem:3]);
		OO_CHECK([ship status] == STATUS_ENTERING_WITCHSPACE);
		[ship setStatus:STATUS_IN_FLIGHT];
	}
}


// A distress call accepted: the caller's attacker is the found target. A station that is not the
// main station ignores it.
OO_TEST(slice1AcceptDistressMessage)
{
	@autoreleasepool
	{
		SetUp();
		TestAIShip *ship = MakeShip("helper");
		TestAIShip *caller = MakeShip("caller");
		TestAIShip *attacker = MakeShip("attacker");
		SetPrimaryTarget(caller, attacker);
		[ship acceptDistressMessageFrom:caller];
		OO_CHECK([ship foundTarget] == attacker);

		TestAIStation *station = [[[TestAIStation alloc] cxx_initWithKey:"station" definition:oo::PList(oo::PList::Dict{ { "unpiloted", oo::PList(true) } })] autorelease];
		OO_CHECK(station != nil);
		[station acceptDistressMessageFrom:caller];
		OO_CHECK([station foundTarget] == nil);
	}
}


// The station AI methods on a ship that is not a station only log.
OO_TEST(slice1StationStubs)
{
	@autoreleasepool
	{
		SetUp();
		TestAIShip *ship = MakeShip("notastation");
		[(id)ship increaseAlertLevel];
		[(id)ship decreaseAlertLevel];
		[(id)ship abortAllDockings];
		[(id)ship launchShipWithRole:std::string("trader")];
		OO_CHECK([(id)ship launchPolice].isNull());
		OO_CHECK([ship status] == STATUS_IN_FLIGHT);
	}
}


// From C++ (after the conversion): the members, and the station's override of the virtual one.
OO_TEST(slice1MembersFromCxx)
{
	@autoreleasepool
	{
		SetUp();
		TestAIShip *ship = MakeShip("member");
		cxx::ShipEntity *part = ship->_cxxShip;
		part->performStop();
		OO_CHECK(Behaviour(ship) == BEHAVIOUR_STOP_STILL);
		OO_CHECK(part->launchPolice().isNull() && !part->launchPatrol());

		TestAIShip *caller = MakeShip("caller");
		TestAIShip *attacker = MakeShip("attacker");
		SetPrimaryTarget(caller, attacker);
		part->acceptDistressMessageFrom(caller);
		OO_CHECK([ship foundTarget] == attacker);

		TestAIStation *station = [[[TestAIStation alloc] cxx_initWithKey:"station" definition:oo::PList(oo::PList::Dict{ { "unpiloted", oo::PList(true) } })] autorelease];
		cxx::ShipEntity *stationAsShip = station->_cxxShip;
		stationAsShip->acceptDistressMessageFrom(caller);		// the station's: not the main station, so nothing
		OO_CHECK([station foundTarget] == nil);
	}
}


// --- Slice 2: PureAI part 1: state, speed, scans for prey and loot, planets, legal status (bead
// oo-xurzn) ------------------------------------------------------------------------------------

// The private category PureAI of ShipEntityAI.mm.
@interface ShipEntity (TestPureAI1)
- (void) setStateTo:(const std::string &)state;
- (void) pauseAI:(const std::string &)intervalString;
- (void) randomPauseAI:(const std::string &)intervalString;
- (void) dropMessages:(const std::string &)messageString;
- (void) debugDumpPendingMessages;
- (void) setDestinationToCurrentLocation;
- (void) setDestinationToJinkPosition;
- (void) setDesiredRangeTo:(const std::string &)rangeString;
- (void) setDesiredRangeForWaypoint;
- (void) setSpeedTo:(const std::string &)speedString;
- (void) setSpeedFactorTo:(const std::string &)speedString;
- (void) setSpeedToCruiseSpeed;
- (void) setThrustFactorTo:(const std::string &)thrustFactorString;
- (void) setTargetToPrimaryAggressor;
- (void) addPrimaryAggressorAsDefenseTarget;
- (void) scanForNearestMerchantman;
- (void) scanForRandomMerchantman;
- (void) scanForLoot;
- (void) scanForRandomLoot;
- (void) setTargetToFoundTarget;
- (void) addFoundTargetAsDefenseTarget;
- (void) checkForFullHold;
- (void) getWitchspaceEntryCoordinates;
- (void) setDestinationFromCoordinates;
- (void) setCoordinatesFromPosition;
- (void) fightOrFleeMissile;
- (void) setCourseToPlanet;
- (void) setTakeOffFromPlanet;
- (void) checkTargetLegalStatus;
- (void) checkOwnLegalStatus;
- (void) exitAIWithMessage:(const std::string &)message;
- (void) setDestinationToTarget;
- (void) setDestinationWithinTarget;
@end


namespace {

void SetPosition2(Entity *e, HPVector p)			{ e->_cxxEntity->position = p; }
HPVector Coordinates2(ShipEntity *s)				{ return s->_cxxShip->coordinates; }
void SetCoordinates2(ShipEntity *s, HPVector c)	{ s->_cxxShip->coordinates = c; }
void SetCruiseSpeed2(ShipEntity *s, GLfloat v)	{ s->_cxxShip->cruiseSpeed = v; }
void SetMaxThrust2(ShipEntity *s, GLfloat v)		{ s->_cxxShip->max_thrust = v; }
GLfloat Thrust2(ShipEntity *s)					{ return s->_cxxShip->thrust; }
bool PitchingOver2(ShipEntity *s)				{ return s->_cxxShip->pitching_over; }
void SetCollisionRadius2(Entity *e, GLfloat r)	{ e->_cxxEntity->collision_radius = r; }

}	// namespace


OO_TEST(slice2SpeedAndRange)
{
	@autoreleasepool
	{
		SetUp();
		TestAIShip *ship = MakeShip("speedy");
		SetMaxFlight(ship, 600, 1, 1);
		[ship setDesiredRangeTo:"123.5"];
		OO_CHECK(DesiredRange(ship) == 123.5f);
		[ship setDesiredRangeForWaypoint];
		OO_CHECK(DesiredRange(ship) == 100.0f);		// top speed / pitch / 6
		SetMaxFlight(ship, 60, 1, 1);
		[ship setDesiredRangeForWaypoint];
		OO_CHECK(DesiredRange(ship) == 50.0f);			// at least 50

		[ship setSpeedTo:"42"];
		OO_CHECK(DesiredSpeed(ship) == 42.0f);
		SetMaxFlight(ship, 100, 1, 1);
		[ship setSpeedFactorTo:"0.5"];
		OO_CHECK(DesiredSpeed(ship) == 50.0f);
		SetCruiseSpeed2(ship, 80);
		[ship setSpeedToCruiseSpeed];
		OO_CHECK(DesiredSpeed(ship) == 80.0f);

		SetMaxThrust2(ship, 20);
		[ship setThrustFactorTo:"0.25"];
		OO_CHECK(Thrust2(ship) == 5.0f);
		[ship setThrustFactorTo:"3"];					// clamped to 1
		OO_CHECK(Thrust2(ship) == 20.0f);
	}
}


OO_TEST(slice2Destinations)
{
	@autoreleasepool
	{
		SetUp();
		TestAIShip *ship = MakeShip("navigator");
		TestAIShip *target = MakeShip("target");
		SetPosition2(ship, make_HPvector(10, 20, 30));
		[ship setDestinationToCurrentLocation];
		OO_CHECK(HPdistance(Destination(ship), make_HPvector(10, 20, 30)) <= 0.5 + 1e-6);

		[ship setCoordinatesFromPosition];
		OO_CHECK(HPdistance2(Coordinates2(ship), make_HPvector(10, 20, 30)) == 0);
		SetCoordinates2(ship, make_HPvector(1, 2, 3));
		[ship setDestinationFromCoordinates];
		OO_CHECK(HPdistance2(Destination(ship), make_HPvector(1, 2, 3)) == 0);

		// No target: the destination stays.
		[ship setDestinationToTarget];
		[ship setDestinationWithinTarget];
		OO_CHECK(HPdistance2(Destination(ship), make_HPvector(1, 2, 3)) == 0);
		SetPosition2(target, make_HPvector(500, 0, 0));
		SetCollisionRadius2(target, 20);
		SetPrimaryTarget(ship, target);
		[ship setDestinationToTarget];
		OO_CHECK(HPdistance2(Destination(ship), make_HPvector(500, 0, 0)) == 0);
		[ship setDestinationWithinTarget];
		OO_CHECK(HPdistance(Destination(ship), make_HPvector(500, 0, 0)) <= 20 + 1e-3);

		[ship setOrientation:kIdentityQuaternion];
		[ship setDestinationToJinkPosition];
		OO_CHECK(PitchingOver2(ship));

		// No station in the universe: ten seconds of flight forward.
		SetMaxFlight(ship, 100, 1, 1);
		SetPosition2(ship, make_HPvector(0, 0, 0));
		[ship getWitchspaceEntryCoordinates];
		OO_CHECK(HPdistance(Coordinates2(ship), make_HPvector(0, 0, 1000)) < 1e-3);
	}
}


OO_TEST(slice2TargetsAndScans)
{
	@autoreleasepool
	{
		SetUp();
		TestAIShip *ship = MakeShip("hunter");
		TestAIShip *other = MakeShip("other");
		SetScannerRange(ship, 25000);

		// No aggressor: nothing to target or defend against.
		[ship setTargetToPrimaryAggressor];
		[ship addPrimaryAggressorAsDefenseTarget];
		OO_CHECK([ship primaryTarget] == nil && ![ship isDefenseTarget:other]);

		// The found target becomes the primary target; none found, none taken.
		[ship setTargetToFoundTarget];
		OO_CHECK([ship primaryTarget] == nil);
		[ship setFoundTarget:other];
		[ship setTargetToFoundTarget];
		OO_CHECK([ship primaryTarget] == other);

		// Scans in an empty universe forget the found target.
		[ship setFoundTarget:other];
		[ship scanForNearestMerchantman];
		OO_CHECK([ship foundTarget] == nil);
		[ship setFoundTarget:other];
		[ship scanForRandomMerchantman];
		OO_CHECK([ship foundTarget] == nil);
		[ship setFoundTarget:other];
		[ship scanForRandomLoot];			// no scoop: gives up before the scan
		OO_CHECK([ship foundTarget] == other);
		[ship scanForLoot];				// no scoop: gives up before the scan
		OO_CHECK([ship foundTarget] == other);
		[ship fightOrFleeMissile];		// no missile coming
		OO_CHECK([ship foundTarget] == other && [ship primaryTarget] == other);
	}
}


// The methods that only tell the AI (the test's ships have none) or log run without effect.
OO_TEST(slice2MessagesOnly)
{
	@autoreleasepool
	{
		SetUp();
		TestAIShip *ship = MakeShip("quiet");
		SetBehaviour(ship, BEHAVIOUR_IDLE);
		[ship setStateTo:"GLOBAL"];
		[ship pauseAI:"2.5"];
		[ship randomPauseAI:"1 2"];
		[ship randomPauseAI:"1"];			// a syntax error: logged
		[ship dropMessages:"A, B ,C"];
		[ship debugDumpPendingMessages];
		[ship checkForFullHold];
		[ship checkTargetLegalStatus];
		[ship checkOwnLegalStatus];
		[ship exitAIWithMessage:""];
		[ship setCourseToPlanet];			// no planet
		[ship setTakeOffFromPlanet];		// no planet: logged
		OO_CHECK(Behaviour(ship) == BEHAVIOUR_IDLE && [ship status] == STATUS_IN_FLIGHT);
	}
}


// From C++ (after the conversion): the members.
OO_TEST(slice2MembersFromCxx)
{
	@autoreleasepool
	{
		SetUp();
		TestAIShip *ship = MakeShip("member2");
		cxx::ShipEntity *part = ship->_cxxShip;
		part->setSpeedTo("7");
		OO_CHECK(DesiredSpeed(ship) == 7.0f);
		SetPosition2(ship, make_HPvector(4, 5, 6));
		part->setCoordinatesFromPosition();
		part->setDestinationFromCoordinates();
		OO_CHECK(HPdistance2(Destination(ship), make_HPvector(4, 5, 6)) == 0);
	}
}


// --- Slice 3: PureAI part 2: checks, comms, Thargoids, escorts, patrols, target marking (bead
// oo-wc9o3) ------------------------------------------------------------------------------------

@interface ShipEntity (TestPureAI2)
- (void) checkAegis;
- (void) checkEnergy;
- (void) checkHeatInsulation;
- (void) findNewDefenseTarget;
- (void) setDestinationToStationBeacon;
- (void) performHyperSpaceExit;
- (void) performHyperSpaceExitWithoutReplacing;
- (void) disengageAutopilot;
- (void) wormholeGroup;
- (void) ejectCargo;
- (void) scanForThargoid;
- (void) scanForNonThargoid;
- (void) thargonCheckMother;
- (void) checkDistanceTravelled;
- (void) fightOrFleeHostiles;
- (void) suggestEscort;
- (void) escortCheckMother;
- (void) checkGroupOddsVersusTarget;
- (void) scanForFormationLeader;
- (void) messageMother:(const std::string &)msgString;
- (void) messageSelf:(const std::string &)msgString;
- (void) setPlanetPatrolCoordinates;
- (void) setSunSkimStartCoordinates;
- (void) setSunSkimEndCoordinates;
- (void) setSunSkimExitCoordinates;
- (void) patrolReportIn;
- (void) checkForMotherStation;
- (void) sendTargetCommsMessage:(const std::string &)message;
- (void) markTargetForFines;
- (void) markTargetForOffence:(const std::string &)valueString;
- (void) storeTarget;
@end


namespace {

OOAegisStatus AegisStatus3(ShipEntity *s)			{ return s->_cxxShip->aegis_status; }
void SetAegisStatus3(ShipEntity *s, int status)	{ s->_cxxShip->aegis_status = (OOAegisStatus)status; }
void SetEnergy3(Entity *e, GLfloat energy, GLfloat maxEnergy)	{ e->_cxxEntity->energy = energy; e->_cxxEntity->maxEnergy = maxEnergy; }
HPVector Coordinates3(ShipEntity *s)				{ return s->_cxxShip->coordinates; }
void SetCoordinates3(ShipEntity *s, HPVector c)	{ s->_cxxShip->coordinates = c; }
void SetDestination3(ShipEntity *s, HPVector d)	{ s->_cxxShip->_destination = d; }

}	// namespace


OO_TEST(slice3ChecksAndScans)
{
	@autoreleasepool
	{
		SetUp();
		TestAIShip *ship = MakeShip("checker");
		TestAIShip *other = MakeShip("other");
		SetScannerRange(ship, 25000);

		// An aegis status out of range is an internal error, and is reset.
		SetAegisStatus3(ship, 99);
		[ship checkAegis];
		OO_CHECK(AegisStatus3(ship) == AEGIS_NONE);
		[ship checkAegis];
		OO_CHECK(AegisStatus3(ship) == AEGIS_NONE);

		SetEnergy3(ship, 50, 100);
		[ship checkEnergy];
		[ship checkHeatInsulation];
		[ship checkDistanceTravelled];
		[ship checkGroupOddsVersusTarget];
		[ship checkForMotherStation];
		[ship disengageAutopilot];		// logged: only for the player
		[ship messageSelf:"HELLO"];
		[ship messageMother:"HELLO"];	// no mother

		[ship findNewDefenseTarget];		// nobody on the scanner
		OO_CHECK(![ship isDefenseTarget:other]);

		[ship setFoundTarget:other];
		[ship scanForThargoid];
		OO_CHECK([ship foundTarget] == nil);
		[ship setFoundTarget:other];
		[ship scanForNonThargoid];
		OO_CHECK([ship foundTarget] == nil);
		[ship setFoundTarget:other];
		[ship scanForFormationLeader];
		OO_CHECK([ship foundTarget] == nil);
		[ship setFoundTarget:other];
		[ship thargonCheckMother];		// no mother and none to be found
		OO_CHECK([ship foundTarget] == nil && [ship owner] != other);
	}
}


OO_TEST(slice3NothingToActOn)
{
	@autoreleasepool
	{
		SetUp();
		TestAIShip *ship = MakeShip("idle");
		TestAIShip *other = MakeShip("other");

		// No station, no sun: destinations and coordinates stay.
		SetDestination3(ship, make_HPvector(1, 2, 3));
		SetCoordinates3(ship, make_HPvector(4, 5, 6));
		[ship setDestinationToStationBeacon];
		[ship setPlanetPatrolCoordinates];
		[ship setSunSkimStartCoordinates];
		[ship setSunSkimEndCoordinates];
		[ship setSunSkimExitCoordinates];
		[ship patrolReportIn];
		OO_CHECK(HPdistance2(Destination(ship), make_HPvector(1, 2, 3)) == 0 && HPdistance2(Coordinates3(ship), make_HPvector(4, 5, 6)) == 0);

		// Already entering witchspace: no jump.
		[ship setStatus:STATUS_ENTERING_WITCHSPACE];
		[ship performHyperSpaceExit];
		[ship performHyperSpaceExitWithoutReplacing];
		OO_CHECK([ship status] == STATUS_ENTERING_WITCHSPACE);
		[ship setStatus:STATUS_IN_FLIGHT];

		// No escort to suggest to, no mother to check: the ship is its own owner.
		[ship suggestEscort];
		OO_CHECK([ship owner] == ship);
		[ship setOwner:nil];
		[ship escortCheckMother];
		OO_CHECK([ship owner] == ship);

		// A target that is not a wormhole: nobody goes.
		SetPrimaryTarget(ship, other);
		[ship wormholeGroup];
		OO_CHECK([ship primaryTarget] == other);

		// Not police: no offence marked.
		[ship markTargetForOffence:"16"];
		OO_CHECK([other bounty] == 0);

		// No cargo bay: nothing to eject.
		[ship ejectCargo];
		OO_CHECK([ship cargoQuantityOnBoard] == 0);
	}
}


OO_TEST(slice3TargetsAndFighting)
{
	@autoreleasepool
	{
		SetUp();
		TestAIShip *ship = MakeShip("fighter");
		TestAIShip *other = MakeShip("other");

		// The target is remembered, and forgotten when there is none.
		SetPrimaryTarget(ship, other);
		[ship storeTarget];
		OO_CHECK([ship rememberedShip] == other);
		SetPrimaryTarget(ship, nil);
		[ship storeTarget];
		OO_CHECK([ship rememberedShip] == nil);

		// A lost target: comms and fines go nowhere.
		[ship sendTargetCommsMessage:"[hello]"];
		[ship markTargetForFines];
		OO_CHECK([ship primaryTarget] == nil);

		// Full energy, no escorts, no missiles: fight the found target.
		SetEnergy3(ship, 100, 100);
		[ship setFoundTarget:other];
		[ship fightOrFleeHostiles];
		OO_CHECK([ship primaryAggressor] == other && [ship isDefenseTarget:other]);
	}
}


// From C++ (after the conversion): the members.
OO_TEST(slice3MembersFromCxx)
{
	@autoreleasepool
	{
		SetUp();
		TestAIShip *ship = MakeShip("member3");
		TestAIShip *other = MakeShip("other");
		cxx::ShipEntity *part = ship->_cxxShip;
		SetPrimaryTarget(ship, other);
		part->storeTarget();
		OO_CHECK([ship rememberedShip] == other);
		SetAegisStatus3(ship, 42);
		part->checkAegis();
		OO_CHECK(AegisStatus3(ship) == AEGIS_NONE);
		part->disengageAutopilot();		// virtual: the ship's, which logs
	}
}


// --- Slice 4: PureAI part 3: stored targets, nearest-ship scans, stations, script actions, beacons
// (bead oo-lqyhf) ------------------------------------------------------------------------------

@interface ShipEntity (TestPureAI3)
- (void) recallStoredTarget;
- (void) scanForRocks;
- (void) setDestinationToDockingAbort;
- (void) requestNewTarget;
- (void) rollD:(const std::string &)die_number;
- (void) scanForNearestShipWithPrimaryRole:(const std::string &)scanRole;
- (void) scanForNearestShipHavingRole:(const std::string &)scanRole;
- (void) scanForNearestShipWithAnyPrimaryRole:(const std::string &)scanRoles;
- (void) scanForNearestShipHavingAnyRole:(const std::string &)scanRoles;
- (void) scanForNearestShipWithScanClass:(const std::string &)scanScanClass;
- (void) scanForNearestShipWithoutPrimaryRole:(const std::string &)scanRole;
- (void) scanForNearestShipNotHavingRole:(const std::string &)scanRole;
- (void) scanForNearestShipWithoutAnyPrimaryRole:(const std::string &)scanRoles;
- (void) scanForNearestShipNotHavingAnyRole:(const std::string &)scanRoles;
- (void) scanForNearestShipWithoutScanClass:(const std::string &)scanScanClass;
- (void) setCoordinates:(const std::string &)system_x_y_z;
- (void) checkForNormalSpace;
- (void) setTargetToRandomStation;
- (void) setTargetToLastStation;
- (void) addFuel:(const std::string &)fuel_number;
- (void) scriptActionOnTarget:(const std::string &)action;
- (void) safeScriptActionOnTarget:(const std::string &)action;
- (void) sendScriptMessage:(const std::string &)message;
- (void) ai_throwSparks;
- (void) ai_debugMessage:(const std::string &)message;
- (void) setRacepointsFromTarget;
- (void) performFlyRacepoints;
@end


namespace {

bool ThrowSparks4(Entity *e)						{ return e->_cxxEntity->throw_sparks; }
unsigned NavpointCount4(ShipEntity *s)			{ return s->_cxxShip->number_of_navpoints; }
unsigned NextNavpoint4(ShipEntity *s)			{ return s->_cxxShip->next_navpoint_index; }
HPVector Navpoint4(ShipEntity *s, unsigned i)	{ return s->_cxxShip->navpoints[i]; }
HPVector Coordinates4(ShipEntity *s)				{ return s->_cxxShip->coordinates; }
void SetCoordinates4(ShipEntity *s, HPVector c)	{ s->_cxxShip->coordinates = c; }
void SetPosition4(Entity *e, HPVector p)			{ e->_cxxEntity->position = p; }
void SetCollisionRadius4(Entity *e, GLfloat r)	{ e->_cxxEntity->collision_radius = r; }

}	// namespace


OO_TEST(slice4StoredTargetsAndScans)
{
	@autoreleasepool
	{
		SetUp();
		TestAIShip *ship = MakeShip("seeker");
		TestAIShip *other = MakeShip("other");
		SetScannerRange(ship, 25000);

		// A remembered ship in range is found again; none remembered, nothing found.
		[ship setRememberedShip:other];
		[ship recallStoredTarget];
		OO_CHECK([ship foundTarget] == other);
		[ship setRememberedShip:nil];
		[ship setFoundTarget:nil];
		[ship recallStoredTarget];
		OO_CHECK([ship foundTarget] == nil && [ship rememberedShip] == nil);

		// Every scan of an empty universe forgets the found target.
		void (*scans[])(TestAIShip *) = {
			[](TestAIShip *s) { [s scanForRocks]; },
			[](TestAIShip *s) { [s scanForNearestShipWithPrimaryRole:"trader"]; },
			[](TestAIShip *s) { [s scanForNearestShipHavingRole:"trader"]; },
			[](TestAIShip *s) { [s scanForNearestShipWithAnyPrimaryRole:"trader pirate"]; },
			[](TestAIShip *s) { [s scanForNearestShipHavingAnyRole:"trader pirate"]; },
			[](TestAIShip *s) { [s scanForNearestShipWithScanClass:"CLASS_NEUTRAL"]; },
			[](TestAIShip *s) { [s scanForNearestShipWithoutPrimaryRole:"trader"]; },
			[](TestAIShip *s) { [s scanForNearestShipNotHavingRole:"trader"]; },
			[](TestAIShip *s) { [s scanForNearestShipWithoutAnyPrimaryRole:"trader pirate"]; },
			[](TestAIShip *s) { [s scanForNearestShipNotHavingAnyRole:"trader pirate"]; },
			[](TestAIShip *s) { [s scanForNearestShipWithoutScanClass:"CLASS_NEUTRAL"]; },
		};
		for (auto scan : scans)
		{
			[ship setFoundTarget:other];
			scan(ship);
			OO_CHECK([ship foundTarget] == nil);
		}

		// No group, so no mother to defend: the found target stays.
		[ship setFoundTarget:other];
		[ship requestNewTarget];
		OO_CHECK([ship foundTarget] == other);
	}
}


OO_TEST(slice4StationsAndCoordinates)
{
	@autoreleasepool
	{
		SetUp();
		TestAIShip *ship = MakeShip("docker");
		TestAIShip *other = MakeShip("other");

		// No station anywhere: back off 8 km from the origin, straight back.
		SetPosition4(ship, make_HPvector(0, 0, 0));
		SetCollisionRadius4(ship, 0);
		[ship setDestinationToDockingAbort];
		OO_CHECK(HPdistance(Coordinates4(ship), make_HPvector(0, 0, -8000)) < 1e-3 && HPdistance(Destination(ship), make_HPvector(0, 0, -8000)) < 1e-3);

		// No stations in range, and a last station that is not one: no target.
		[ship setTargetToRandomStation];
		OO_CHECK([ship primaryTarget] == nil);
		[ship setTargetStation:other];
		[ship setTargetToLastStation];
		OO_CHECK([ship primaryTarget] == nil && [ship targetStation] == nil);

		// A malformed coordinate string changes nothing.
		SetCoordinates4(ship, make_HPvector(1, 2, 3));
		[ship setCoordinates:"wpu 1 2"];
		OO_CHECK(HPdistance2(Coordinates4(ship), make_HPvector(1, 2, 3)) == 0);
		[ship checkForNormalSpace];
	}
}


OO_TEST(slice4ActionsAndRacepoints)
{
	@autoreleasepool
	{
		SetUp();
		TestAIShip *ship = MakeShip("racer");
		TestAIShip *pylon = MakeShip("pylon");

		[ship setFuel:0];
		[ship addFuel:"3"];
		OO_CHECK([ship fuel] == 30);

		[ship ai_throwSparks];
		OO_CHECK(ThrowSparks4(ship));

		// Nothing to act on, or no script to tell: nothing happens.
		[ship scriptActionOnTarget:"set: mission_x 1"];
		[ship safeScriptActionOnTarget:"set: mission_x 1"];
		[ship sendScriptMessage:""];
		[ship sendScriptMessage:"hello"];
		[ship sendScriptMessage:"hello a b"];
		[ship rollD:"0"];				// logged
		[ship rollD:"6"];
		[ship ai_debugMessage:"hi"];
		OO_CHECK([ship status] == STATUS_IN_FLIGHT);

		// No target: no racepoints.
		[ship setRacepointsFromTarget];
		OO_CHECK(NavpointCount4(ship) == 0);
		SetPosition4(pylon, make_HPvector(100, 0, 0));
		SetCollisionRadius4(pylon, 10);
		[pylon setOrientation:kIdentityQuaternion];
		SetPrimaryTarget(ship, pylon);
		[ship setRacepointsFromTarget];
		OO_CHECK(NavpointCount4(ship) == 2 && NextNavpoint4(ship) == 0);
		OO_CHECK(HPdistance(Navpoint4(ship, 0), make_HPvector(100, 0, -10)) < 1e-3 && HPdistance(Navpoint4(ship, 1), make_HPvector(100, 0, 10)) < 1e-3);
		OO_CHECK(HPdistance2(Destination(ship), Navpoint4(ship, 0)) == 0);

		SetCollisionRadius4(ship, 25);
		[ship performFlyRacepoints];
		OO_CHECK(Behaviour(ship) == BEHAVIOUR_FLY_THRU_NAVPOINTS && DesiredRange(ship) == 25 && NextNavpoint4(ship) == 0);
	}
}


// From C++ (after the conversion): the members.
OO_TEST(slice4MembersFromCxx)
{
	@autoreleasepool
	{
		SetUp();
		TestAIShip *ship = MakeShip("member4");
		cxx::ShipEntity *part = ship->_cxxShip;
		[ship setFuel:0];
		part->addFuel("2");
		OO_CHECK([ship fuel] == 20);
		SetCollisionRadius4(ship, 12);
		part->performFlyRacepoints();
		OO_CHECK(Behaviour(ship) == BEHAVIOUR_FLY_THRU_NAVPOINTS && DesiredRange(ship) == 12);
	}
}


OO_TEST_MAIN()
