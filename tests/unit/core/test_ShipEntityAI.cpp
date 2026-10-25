/*	test_ShipEntityAI.mm
	Unit tests for ShipEntityAI.mm, the legacy plist-AI surface of ShipEntity: its slices
	(docs/phases/3-slices/ShipEntityAI.md, beads oo-iebuz, oo-xurzn, oo-wc9o3, oo-lqyhf) move the
	categories' methods into ShipEntity members, defined in the category's file, and leave
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

#include "ShipEntity.h"
#include "ShipEntityAI.h"
#include "StationEntity.h"
#include "Universe.h"
#include "PlayerEntity.h"
#include "OOCallByName.h"	// oo::EntityRespondsToName / oo::CallEntityByName (bead oo-9ht.39.7.3)

#include "oo_test.hpp"

#include <cmath>
#include <string>


// main.mm defines the debug flags, and the test has its own main.
#ifndef NDEBUG
uint32_t gDebugFlags = 0;
#endif

class PlayerEntity;
extern PlayerEntity *gOOPlayer;
extern Universe *gSharedUniverse;
extern ooscript::Context gOOJSMainThreadContext;


class TestAIPlayer : public PlayerEntity	// C++ since bead oo-9ht.177 deleted the Objective-C player
{
public:
	HPVector viewpointPosition() override	{ return kZeroHPVector; }
};

// [[TestPlayer alloc] init] (bead oo-9ht.177): a C++ player under the ship's facade, as
// PlayerEntity::sharedPlayer() makes the game's, retained (+1) as +alloc's object was.
template <class T>
T *NewTestPlayer()
{
	oo::Ref<T> player = oo::makeRef<T>();
	{
		oo::RetainEntity(oo::MadeEntity(player));
	}
	return player.get();
}



// A ship whose set-up from shipdata does nothing, and that scripts cannot see (a C++ subclass since
// bead oo-9ht.144 deleted the Objective-C ship).
class TestAIShip : public ShipEntity
{
public:
	bool setUpShipFromDictionary(const oo::PList &dict) override	{ (void)dict; return YES; }
	bool isVisibleToScripts() override	{ return NO; }
};


// A station whose virtual dock is not made (the dock is a shipdata entry), invisible to scripts. A
// C++ subclass since bead oo-9ht.175 deleted the Objective-C station (amendment oo-9ht.177 item 5).
class TestAIStation : public StationEntity
{
public:
	bool setUpOneStandardSubentity(const oo::PList &/*subentDict*/, bool /*asTurret*/) override	{ return YES; }
	bool isVisibleToScripts() override	{ return NO; }
};


// [[[TestAIStation alloc] cxx_initWithKey:definition:] autorelease] until bead oo-9ht.175: made as
// StationEntity::newStationObject() makes a station; answers its object (the ship's facade).
namespace {

ShipEntity *NewTestAIStation(const std::string &key, const oo::PList &dict)
{
	ShipEntity *station = oo::ToShip(oo::NewShipObject(oo::makeRef<TestAIStation>(), key, dict));
	if (station != nullptr)  static_cast<StationEntity *>(station)->initStationDefaults();
	oo::AutoreleaseEntity(station);
	return station;	// the station (its object until bead oo-9ht.144)
}

}	// namespace


namespace {

OOBehaviour Behaviour(ShipEntity *s)			{ return s->behaviour; }
void SetBehaviour(ShipEntity *s, OOBehaviour b)	{ s->behaviour = b; }
GLfloat Frustration(ShipEntity *s)				{ return s->frustration; }
void SetFrustration(ShipEntity *s, GLfloat f)	{ s->frustration = f; }
GLfloat DesiredSpeed(ShipEntity *s)				{ return s->desired_speed; }
void SetDesiredSpeed(ShipEntity *s, GLfloat v)	{ s->desired_speed = v; }
GLfloat DesiredRange(ShipEntity *s)				{ return s->desired_range; }
GLfloat StickRoll(ShipEntity *s)				{ return s->stick_roll; }
GLfloat StickPitch(ShipEntity *s)				{ return s->stick_pitch; }
void SetMaxFlight(ShipEntity *s, GLfloat speed, GLfloat roll, GLfloat pitch)	{ s->maxFlightSpeed = speed; s->max_flight_roll = roll; s->max_flight_pitch = pitch; }
HPVector Destination(ShipEntity *s)				{ return s->_destination; }
bool MatchRotation(ShipEntity *s)				{ return s->docking_match_rotation; }
void SetDockingInstructions(ShipEntity *s, const oo::PList &instructions)	{ s->dockingInstructions = instructions; }
void SetScannerRange(ShipEntity *s, GLfloat r)	{ s->scannerRange = r; }
void SetAccuracy(ShipEntity *s, GLfloat a)		{ s->accuracy = a; }
void SetNearPlanetSurface(ShipEntity *s, bool v)	{ s->isNearPlanetSurface = v; }
void SetPrimaryTarget(ShipEntity *s, Entity *target)
{
	s->_primaryTarget = oo::WeakRef<Entity>(target);	// the entity's C++ part (bead oo-9ht.39.5.2)
}


void SetUp()
{
	static Universe *universe = nil;
	if (universe == nil)
	{
		universe = new Universe();	// never released
	}
	gSharedUniverse = universe;
	static TestAIPlayer *player = nullptr;
	if (player == nullptr)  player = NewTestPlayer<TestAIPlayer>();
	gOOPlayer = player;
	if (gOOJSMainThreadContext == nullptr)  gOOJSMainThreadContext = ooscript::newContext(ooscript::newRuntime(8u * 1024u * 1024u), 8192);
	ranrot_srand(20261007);	// as the game seeds it: an unseeded generator answers one value, and OOHPVectorRandomSpatial() never ends
}


TestAIShip *MakeShip(const char *key)
{
	// [[[TestAIShip alloc] cxx_initWithKey:definition:] autorelease] until bead oo-9ht.144
	return static_cast<TestAIShip *>(oo::ToShip(oo::AutoreleaseEntity(oo::NewShipObject(oo::makeRef<TestAIShip>(), key, oo::PList(oo::PList::Dict{})))));
}


BOOL AlwaysYes(Entity *, void *)	{ return YES; }	// the C++ entity since bead oo-9ht.39.23

}	// namespace


// --- Slice 1: the AI category, OOAIPrivate (ship and station), the station stubs (bead oo-iebuz) ---

// The perform* behaviours: each sets its behaviour and resets the frustration.
OO_TEST(slice1Behaviours)
{
	{
		SetUp();
		TestAIShip *ship = MakeShip("pilot");
		struct { void (*perform)(TestAIShip *); OOBehaviour behaviour; } cases[] = {
			{ [](TestAIShip *s) { if (s != nullptr)  s->performCollect(); }, BEHAVIOUR_COLLECT_TARGET },
			{ [](TestAIShip *s) { if (s != nullptr)  s->performFaceDestination(); }, BEHAVIOUR_FACE_DESTINATION },
			{ [](TestAIShip *s) { if (s != nullptr)  s->performFlyToRangeFromDestination(); }, BEHAVIOUR_FLY_RANGE_FROM_DESTINATION },
			{ [](TestAIShip *s) { if (s != nullptr)  s->performIdle(); }, BEHAVIOUR_IDLE },
			{ [](TestAIShip *s) { if (s != nullptr)  s->performIntercept(); }, BEHAVIOUR_INTERCEPT_TARGET },
			{ [](TestAIShip *s) { if (s != nullptr)  s->performScriptedAI(); }, BEHAVIOUR_SCRIPTED_AI },
			{ [](TestAIShip *s) { if (s != nullptr)  s->performScriptedAttackAI(); }, BEHAVIOUR_SCRIPTED_ATTACK_AI },
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
		if (ship != nullptr)  ship->performHold();
		OO_CHECK(Behaviour(ship) == BEHAVIOUR_TRACK_TARGET && DesiredSpeed(ship) == 0 && Frustration(ship) == 0);

		SetDesiredSpeed(ship, 50);
		if (ship != nullptr)  ship->performStop();
		OO_CHECK(Behaviour(ship) == BEHAVIOUR_STOP_STILL && DesiredSpeed(ship) == 0);

		if (ship != nullptr)  ship->performBuoyTumble();
		OO_CHECK(Behaviour(ship) == BEHAVIOUR_TUMBLE && StickRoll(ship) == 0.10f && StickPitch(ship) == 0.15f);

		SetMaxFlight(ship, 100, 2, 1);
		if (ship != nullptr)  ship->performTumble();
		OO_CHECK(Behaviour(ship) == BEHAVIOUR_TUMBLE && std::fabs(StickRoll(ship)) <= 2.0f && std::fabs(StickPitch(ship)) <= 1.0f);

		SetBehaviour(ship, BEHAVIOUR_IDLE);
		if (ship != nullptr)  ship->performEscort();
		OO_CHECK(Behaviour(ship) == BEHAVIOUR_FORMATION_FORM_UP && Frustration(ship) == 0);
		SetFrustration(ship, 5);
		if (ship != nullptr)  ship->performEscort();		// already forming up: nothing changes
		OO_CHECK(Behaviour(ship) == BEHAVIOUR_FORMATION_FORM_UP && Frustration(ship) == 5);
	}
}


OO_TEST(slice1AttackFleeMiningLanding)
{
	{
		SetUp();
		TestAIShip *ship = MakeShip("fighter");
		SetBehaviour(ship, BEHAVIOUR_IDLE);
		if (ship != nullptr)  ship->performAttack();
		OO_CHECK(Behaviour(ship) == BEHAVIOUR_ATTACK_TARGET && DesiredRange(ship) >= 750 && DesiredRange(ship) <= 2000);
		SetBehaviour(ship, BEHAVIOUR_EVASIVE_ACTION);
		if (ship != nullptr)  ship->performAttack();		// evading: carries on
		OO_CHECK(Behaviour(ship) == BEHAVIOUR_EVASIVE_ACTION);

		SetAccuracy(ship, COMBAT_AI_ISNT_AWFUL);	// no aspect check
		SetBehaviour(ship, BEHAVIOUR_IDLE);
		if (ship != nullptr)  ship->performFlee();
		OO_CHECK(Behaviour(ship) == BEHAVIOUR_FLEE_TARGET && Frustration(ship) == 0);
		SetBehaviour(ship, BEHAVIOUR_FLEE_EVASIVE_ACTION);
		if (ship != nullptr)  ship->performFlee();
		OO_CHECK(Behaviour(ship) == BEHAVIOUR_FLEE_EVASIVE_ACTION);

		// Mining a target that is not a rock: lost target, idle.
		SetBehaviour(ship, BEHAVIOUR_TUMBLE);
		if (ship != nullptr)  ship->performMining();
		OO_CHECK(Behaviour(ship) == BEHAVIOUR_IDLE);

		// Landing away from any planet's surface: idle.
		SetNearPlanetSurface(ship, false);
		SetBehaviour(ship, BEHAVIOUR_TUMBLE);
		SetFrustration(ship, 5);
		if (ship != nullptr)  ship->performLandOnPlanet();
		OO_CHECK(Behaviour(ship) == BEHAVIOUR_IDLE && Frustration(ship) == 0);
	}
}


// The docking instructions a ship remembers: destination, speed (at most the ship's top speed),
// range and rotation matching.
OO_TEST(slice1RecallDockingInstructions)
{
	{
		SetUp();
		TestAIShip *ship = MakeShip("docker");
		SetMaxFlight(ship, 100, 1, 1);
		if (ship != nullptr)  ship->recallDockingInstructions();		// none: nothing changes
		OO_CHECK(DesiredSpeed(ship) == 0);

		SetDockingInstructions(ship, oo::PList(oo::PList::Dict{
			{ "destination", oo::PList(oo::PList::Dict{ { "x", oo::PList(1.0) }, { "y", oo::PList(2.0) }, { "z", oo::PList(3.0) } }) },
			{ "speed", oo::PList(250.0) },
			{ "range", oo::PList(40.0) },
			{ "match_rotation", oo::PList(true) },
		}));
		if (ship != nullptr)  ship->recallDockingInstructions();
		OO_CHECK(HPdistance2(Destination(ship), make_HPvector(1, 2, 3)) < 1e-9);
		OO_CHECK(DesiredSpeed(ship) == 100 && DesiredRange(ship) == 40 && MatchRotation(ship));
	}
}


// Scans in an empty universe find nothing, and forget what was found before.
OO_TEST(slice1ScansFindNothing)
{
	{
		SetUp();
		TestAIShip *ship = MakeShip("scanner");
		TestAIShip *other = MakeShip("other");
		SetScannerRange(ship, 25000);

		if (ship != nullptr)  ship->setFoundTarget(other);
		if (ship != nullptr)  ship->scanForHostiles();
		OO_CHECK((ship != nullptr ? ship->foundTarget() : (Entity *)nullptr) == nil);

		if (ship != nullptr)  ship->setFoundTarget(other);
		if (ship != nullptr)  ship->scanForNearestShipWithPredicate(AlwaysYes, NULL);
		OO_CHECK((ship != nullptr ? ship->foundTarget() : (Entity *)nullptr) == nil);

		if (ship != nullptr)  ship->setFoundTarget(other);
		if (ship != nullptr)  ship->scanForNearestShipWithNegatedPredicate(AlwaysYes, NULL);
		OO_CHECK((ship != nullptr ? ship->foundTarget() : (Entity *)nullptr) == nil);

		if (ship != nullptr)  ship->setFoundTarget(other);
		if (ship != nullptr)  ship->scanForNearestShipWithPredicate(NULL, NULL);
		OO_CHECK((ship != nullptr ? ship->foundTarget() : (Entity *)nullptr) == nil);

		if (ship != nullptr)  ship->setFoundTarget(other);
		if (ship != nullptr)  ship->scanForNearestIncomingMissile();
		OO_CHECK((ship != nullptr ? ship->foundTarget() : (Entity *)nullptr) == nil);

		if (ship != nullptr)  ship->checkFoundTarget();		// no AI: nothing to tell
	}
}


// What the AI category does when there is nothing to act on.
OO_TEST(slice1NothingToActOn)
{
	{
		SetUp();
		TestAIShip *ship = MakeShip("loner");
		TestAIShip *other = MakeShip("other");

		// No escort to suggest to: the ship is its own owner.
		OO_CHECK(!(ship != nullptr ? ship->suggestEscortTo(nullptr) : false));
		OO_CHECK((ship != nullptr ? ship->owner() : nullptr) == ship);

		// No aggressor: no distress call.
		if (ship != nullptr)  ship->broadcastDistressMessage();
		if (ship != nullptr)  ship->broadcastDistressMessageWithDumping(NO);
		OO_CHECK((ship != nullptr ? ship->foundTarget() : (Entity *)nullptr) == nil);

		// No primary target: no group attack, and a target that is not a wormhole: no escorts sent.
		if (ship != nullptr)  ship->groupAttackTarget();
		OO_CHECK((ship != nullptr ? ship->foundTarget() : (Entity *)nullptr) == nil);
		SetPrimaryTarget(ship, other);
		if (ship != nullptr)  ship->wormholeEscorts();
		OO_CHECK((ship != nullptr ? ship->primaryTarget() : (Entity *)nullptr) == other);

		// A ship that alone answers a request for help: it takes the target as found.
		if (ship != nullptr)  ship->groupAttackTarget();
		OO_CHECK((ship != nullptr ? ship->foundTarget() : (Entity *)nullptr) == other);

		// Already entering witchspace: no second jump (the universe's destinations are not asked).
		if (ship != nullptr)  ship->setStatus(STATUS_ENTERING_WITCHSPACE);
		OO_CHECK(!(ship != nullptr ? ship->performHyperSpaceToSpecificSystem(7) : false));
		OO_CHECK(!(ship != nullptr ? ship->performHyperSpaceExitReplace(NO) : false));
		OO_CHECK(!(ship != nullptr ? ship->performHyperSpaceExitReplace(YES, 3) : false));
		OO_CHECK((ship != nullptr ? ship->status() : OOEntityStatus{}) == STATUS_ENTERING_WITCHSPACE);
		if (ship != nullptr)  ship->setStatus(STATUS_IN_FLIGHT);
	}
}


// A distress call accepted: the caller's attacker is the found target. A station that is not the
// main station ignores it.
OO_TEST(slice1AcceptDistressMessage)
{
	{
		SetUp();
		TestAIShip *ship = MakeShip("helper");
		TestAIShip *caller = MakeShip("caller");
		TestAIShip *attacker = MakeShip("attacker");
		SetPrimaryTarget(caller, attacker);
		if (ship != nullptr)  ship->acceptDistressMessageFrom(caller);
		OO_CHECK((ship != nullptr ? ship->foundTarget() : (Entity *)nullptr) == attacker);

		ShipEntity *station = NewTestAIStation("station", oo::PList(oo::PList::Dict{ { "unpiloted", oo::PList(true) } }));
		OO_CHECK(station != nil);
		if (station != nullptr)  station->acceptDistressMessageFrom(caller);
		OO_CHECK((station != nullptr ? station->foundTarget() : (Entity *)nullptr) == nil);
	}
}


// The station AI methods on a ship that is not a station only log.
OO_TEST(slice1StationStubs)
{
	{
		SetUp();
		TestAIShip *ship = MakeShip("notastation");
		// The AI calls them by name: the by-name table's rows since bead oo-9ht.39.7.3 (the category
		// Entity (OOShipSelectorsCalledByName)'s station stubs, sent to the ship's object, until then).
		oo::CallEntityByName(ship, "increaseAlertLevel");
		oo::CallEntityByName(ship, "decreaseAlertLevel");
		oo::CallEntityByName(ship, "abortAllDockings");
		oo::CallEntityByName(ship, "launchShipWithRole:", std::string("trader"));
		OO_CHECK(oo::CallEntityByName(ship, "launchPolice").isNull());
		OO_CHECK((ship != nullptr ? ship->status() : OOEntityStatus{}) == STATUS_IN_FLIGHT);
	}
}


// From C++ (after the conversion): the members, and the station's override of the virtual one.
OO_TEST(slice1MembersFromCxx)
{
	{
		SetUp();
		TestAIShip *ship = MakeShip("member");
		ShipEntity *part = ship;
		part->performStop();
		OO_CHECK(Behaviour(ship) == BEHAVIOUR_STOP_STILL);
		OO_CHECK(part->launchPolice().isNull() && !part->launchPatrol());

		TestAIShip *caller = MakeShip("caller");
		TestAIShip *attacker = MakeShip("attacker");
		SetPrimaryTarget(caller, attacker);
		part->acceptDistressMessageFrom(caller);
		OO_CHECK((ship != nullptr ? ship->foundTarget() : (Entity *)nullptr) == attacker);

		ShipEntity *station = NewTestAIStation("station", oo::PList(oo::PList::Dict{ { "unpiloted", oo::PList(true) } }));
		ShipEntity *stationAsShip = station;
		stationAsShip->acceptDistressMessageFrom(caller);		// the station's: not the main station, so nothing
		OO_CHECK((station != nullptr ? station->foundTarget() : (Entity *)nullptr) == nil);
	}
}


// --- Slice 2: PureAI part 1: state, speed, scans for prey and loot, planets, legal status (bead
// oo-xurzn) ------------------------------------------------------------------------------------


namespace {

void SetPosition2(Entity *e, HPVector p)			{ e->position = p; }
HPVector Coordinates2(ShipEntity *s)				{ return s->coordinates; }
void SetCoordinates2(ShipEntity *s, HPVector c)	{ s->coordinates = c; }
void SetCruiseSpeed2(ShipEntity *s, GLfloat v)	{ s->cruiseSpeed = v; }
void SetMaxThrust2(ShipEntity *s, GLfloat v)		{ s->max_thrust = v; }
GLfloat Thrust2(ShipEntity *s)					{ return s->thrust; }
bool PitchingOver2(ShipEntity *s)				{ return s->pitching_over; }
void SetCollisionRadius2(Entity *e, GLfloat r)	{ e->collision_radius = r; }

}	// namespace


OO_TEST(slice2SpeedAndRange)
{
	{
		SetUp();
		TestAIShip *ship = MakeShip("speedy");
		SetMaxFlight(ship, 600, 1, 1);
		if (ship != nullptr)  ship->setDesiredRangeTo("123.5");
		OO_CHECK(DesiredRange(ship) == 123.5f);
		if (ship != nullptr)  ship->setDesiredRangeForWaypoint();
		OO_CHECK(DesiredRange(ship) == 100.0f);		// top speed / pitch / 6
		SetMaxFlight(ship, 60, 1, 1);
		if (ship != nullptr)  ship->setDesiredRangeForWaypoint();
		OO_CHECK(DesiredRange(ship) == 50.0f);			// at least 50

		if (ship != nullptr)  ship->setSpeedTo("42");
		OO_CHECK(DesiredSpeed(ship) == 42.0f);
		SetMaxFlight(ship, 100, 1, 1);
		if (ship != nullptr)  ship->setSpeedFactorTo("0.5");
		OO_CHECK(DesiredSpeed(ship) == 50.0f);
		SetCruiseSpeed2(ship, 80);
		if (ship != nullptr)  ship->setSpeedToCruiseSpeed();
		OO_CHECK(DesiredSpeed(ship) == 80.0f);

		SetMaxThrust2(ship, 20);
		if (ship != nullptr)  ship->setThrustFactorTo("0.25");
		OO_CHECK(Thrust2(ship) == 5.0f);
		if (ship != nullptr)  ship->setThrustFactorTo("3");					// clamped to 1
		OO_CHECK(Thrust2(ship) == 20.0f);
	}
}


OO_TEST(slice2Destinations)
{
	{
		SetUp();
		TestAIShip *ship = MakeShip("navigator");
		TestAIShip *target = MakeShip("target");
		SetPosition2(ship, make_HPvector(10, 20, 30));
		if (ship != nullptr)  ship->setDestinationToCurrentLocation();
		OO_CHECK(HPdistance(Destination(ship), make_HPvector(10, 20, 30)) <= 0.5 + 1e-6);

		if (ship != nullptr)  ship->setCoordinatesFromPosition();
		OO_CHECK(HPdistance2(Coordinates2(ship), make_HPvector(10, 20, 30)) == 0);
		SetCoordinates2(ship, make_HPvector(1, 2, 3));
		if (ship != nullptr)  ship->setDestinationFromCoordinates();
		OO_CHECK(HPdistance2(Destination(ship), make_HPvector(1, 2, 3)) == 0);

		// No target: the destination stays.
		if (ship != nullptr)  ship->setDestinationToTarget();
		if (ship != nullptr)  ship->setDestinationWithinTarget();
		OO_CHECK(HPdistance2(Destination(ship), make_HPvector(1, 2, 3)) == 0);
		SetPosition2(target, make_HPvector(500, 0, 0));
		SetCollisionRadius2(target, 20);
		SetPrimaryTarget(ship, target);
		if (ship != nullptr)  ship->setDestinationToTarget();
		OO_CHECK(HPdistance2(Destination(ship), make_HPvector(500, 0, 0)) == 0);
		if (ship != nullptr)  ship->setDestinationWithinTarget();
		OO_CHECK(HPdistance(Destination(ship), make_HPvector(500, 0, 0)) <= 20 + 1e-3);

		if (ship != nullptr)  ship->setOrientation(kIdentityQuaternion);
		if (ship != nullptr)  ship->setDestinationToJinkPosition();
		OO_CHECK(PitchingOver2(ship));

		// No station in the universe: ten seconds of flight forward.
		SetMaxFlight(ship, 100, 1, 1);
		SetPosition2(ship, make_HPvector(0, 0, 0));
		if (ship != nullptr)  ship->getWitchspaceEntryCoordinates();
		OO_CHECK(HPdistance(Coordinates2(ship), make_HPvector(0, 0, 1000)) < 1e-3);
	}
}


OO_TEST(slice2TargetsAndScans)
{
	{
		SetUp();
		TestAIShip *ship = MakeShip("hunter");
		TestAIShip *other = MakeShip("other");
		SetScannerRange(ship, 25000);

		// No aggressor: nothing to target or defend against.
		if (ship != nullptr)  ship->setTargetToPrimaryAggressor();
		if (ship != nullptr)  ship->addPrimaryAggressorAsDefenseTarget();
		OO_CHECK((ship != nullptr ? ship->primaryTarget() : (Entity *)nullptr) == nil && !(ship != nullptr ? ship->isDefenseTarget(other) : false));

		// The found target becomes the primary target; none found, none taken.
		if (ship != nullptr)  ship->setTargetToFoundTarget();
		OO_CHECK((ship != nullptr ? ship->primaryTarget() : (Entity *)nullptr) == nil);
		if (ship != nullptr)  ship->setFoundTarget(other);
		if (ship != nullptr)  ship->setTargetToFoundTarget();
		OO_CHECK((ship != nullptr ? ship->primaryTarget() : (Entity *)nullptr) == other);

		// Scans in an empty universe forget the found target.
		if (ship != nullptr)  ship->setFoundTarget(other);
		if (ship != nullptr)  ship->scanForNearestMerchantman();
		OO_CHECK((ship != nullptr ? ship->foundTarget() : (Entity *)nullptr) == nil);
		if (ship != nullptr)  ship->setFoundTarget(other);
		if (ship != nullptr)  ship->scanForRandomMerchantman();
		OO_CHECK((ship != nullptr ? ship->foundTarget() : (Entity *)nullptr) == nil);
		if (ship != nullptr)  ship->setFoundTarget(other);
		if (ship != nullptr)  ship->scanForRandomLoot();			// no scoop: gives up before the scan
		OO_CHECK((ship != nullptr ? ship->foundTarget() : (Entity *)nullptr) == other);
		if (ship != nullptr)  ship->scanForLoot();				// no scoop: gives up before the scan
		OO_CHECK((ship != nullptr ? ship->foundTarget() : (Entity *)nullptr) == other);
		if (ship != nullptr)  ship->fightOrFleeMissile();		// no missile coming
		OO_CHECK((ship != nullptr ? ship->foundTarget() : (Entity *)nullptr) == other && (ship != nullptr ? ship->primaryTarget() : (Entity *)nullptr) == other);
	}
}


// The methods that only tell the AI (the test's ships have none) or log run without effect.
OO_TEST(slice2MessagesOnly)
{
	{
		SetUp();
		TestAIShip *ship = MakeShip("quiet");
		SetBehaviour(ship, BEHAVIOUR_IDLE);
		if (ship != nullptr)  ship->setStateTo("GLOBAL");
		if (ship != nullptr)  ship->pauseAI("2.5");
		if (ship != nullptr)  ship->randomPauseAI("1 2");
		if (ship != nullptr)  ship->randomPauseAI("1");			// a syntax error: logged
		if (ship != nullptr)  ship->dropMessages("A, B ,C");
		if (ship != nullptr)  ship->debugDumpPendingMessages();
		if (ship != nullptr)  ship->checkForFullHold();
		if (ship != nullptr)  ship->checkTargetLegalStatus();
		if (ship != nullptr)  ship->checkOwnLegalStatus();
		if (ship != nullptr)  ship->exitAIWithMessage("");
		if (ship != nullptr)  ship->setCourseToPlanet();			// no planet
		if (ship != nullptr)  ship->setTakeOffFromPlanet();		// no planet: logged
		OO_CHECK(Behaviour(ship) == BEHAVIOUR_IDLE && (ship != nullptr ? ship->status() : OOEntityStatus{}) == STATUS_IN_FLIGHT);
	}
}


// From C++ (after the conversion): the members.
OO_TEST(slice2MembersFromCxx)
{
	{
		SetUp();
		TestAIShip *ship = MakeShip("member2");
		ShipEntity *part = ship;
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


namespace {

OOAegisStatus AegisStatus3(ShipEntity *s)			{ return s->aegis_status; }
void SetAegisStatus3(ShipEntity *s, int status)	{ s->aegis_status = (OOAegisStatus)status; }
void SetEnergy3(Entity *e, GLfloat energy, GLfloat maxEnergy)	{ e->energy = energy; e->maxEnergy = maxEnergy; }
HPVector Coordinates3(ShipEntity *s)				{ return s->coordinates; }
void SetCoordinates3(ShipEntity *s, HPVector c)	{ s->coordinates = c; }
void SetDestination3(ShipEntity *s, HPVector d)	{ s->_destination = d; }

}	// namespace


OO_TEST(slice3ChecksAndScans)
{
	{
		SetUp();
		TestAIShip *ship = MakeShip("checker");
		TestAIShip *other = MakeShip("other");
		SetScannerRange(ship, 25000);

		// An aegis status out of range is an internal error, and is reset.
		SetAegisStatus3(ship, 99);
		if (ship != nullptr)  ship->checkAegis();
		OO_CHECK(AegisStatus3(ship) == AEGIS_NONE);
		if (ship != nullptr)  ship->checkAegis();
		OO_CHECK(AegisStatus3(ship) == AEGIS_NONE);

		SetEnergy3(ship, 50, 100);
		if (ship != nullptr)  ship->checkEnergy();
		if (ship != nullptr)  ship->checkHeatInsulation();
		if (ship != nullptr)  ship->checkDistanceTravelled();
		if (ship != nullptr)  ship->checkGroupOddsVersusTarget();
		if (ship != nullptr)  ship->checkForMotherStation();
		if (ship != nullptr)  ship->disengageAutopilot();		// logged: only for the player
		if (ship != nullptr)  ship->messageSelf("HELLO");
		if (ship != nullptr)  ship->messageMother("HELLO");	// no mother

		if (ship != nullptr)  ship->findNewDefenseTarget();		// nobody on the scanner
		OO_CHECK(!(ship != nullptr ? ship->isDefenseTarget(other) : false));

		if (ship != nullptr)  ship->setFoundTarget(other);
		if (ship != nullptr)  ship->scanForThargoid();
		OO_CHECK((ship != nullptr ? ship->foundTarget() : (Entity *)nullptr) == nil);
		if (ship != nullptr)  ship->setFoundTarget(other);
		if (ship != nullptr)  ship->scanForNonThargoid();
		OO_CHECK((ship != nullptr ? ship->foundTarget() : (Entity *)nullptr) == nil);
		if (ship != nullptr)  ship->setFoundTarget(other);
		if (ship != nullptr)  ship->scanForFormationLeader();
		OO_CHECK((ship != nullptr ? ship->foundTarget() : (Entity *)nullptr) == nil);
		if (ship != nullptr)  ship->setFoundTarget(other);
		if (ship != nullptr)  ship->thargonCheckMother();		// no mother and none to be found
		OO_CHECK((ship != nullptr ? ship->foundTarget() : (Entity *)nullptr) == nil && (ship != nullptr ? ship->owner() : nullptr) != other);
	}
}


OO_TEST(slice3NothingToActOn)
{
	{
		SetUp();
		TestAIShip *ship = MakeShip("idle");
		TestAIShip *other = MakeShip("other");

		// No station, no sun: destinations and coordinates stay.
		SetDestination3(ship, make_HPvector(1, 2, 3));
		SetCoordinates3(ship, make_HPvector(4, 5, 6));
		if (ship != nullptr)  ship->setDestinationToStationBeacon();
		if (ship != nullptr)  ship->setPlanetPatrolCoordinates();
		if (ship != nullptr)  ship->setSunSkimStartCoordinates();
		if (ship != nullptr)  ship->setSunSkimEndCoordinates();
		if (ship != nullptr)  ship->setSunSkimExitCoordinates();
		if (ship != nullptr)  ship->patrolReportIn();
		OO_CHECK(HPdistance2(Destination(ship), make_HPvector(1, 2, 3)) == 0 && HPdistance2(Coordinates3(ship), make_HPvector(4, 5, 6)) == 0);

		// Already entering witchspace: no jump.
		if (ship != nullptr)  ship->setStatus(STATUS_ENTERING_WITCHSPACE);
		if (ship != nullptr)  ship->performHyperSpaceExit();
		if (ship != nullptr)  ship->performHyperSpaceExitWithoutReplacing();
		OO_CHECK((ship != nullptr ? ship->status() : OOEntityStatus{}) == STATUS_ENTERING_WITCHSPACE);
		if (ship != nullptr)  ship->setStatus(STATUS_IN_FLIGHT);

		// No escort to suggest to, no mother to check: the ship is its own owner.
		if (ship != nullptr)  ship->suggestEscort();
		OO_CHECK((ship != nullptr ? ship->owner() : nullptr) == ship);
		if (ship != nullptr)  ship->setOwner(nullptr);
		if (ship != nullptr)  ship->escortCheckMother();
		OO_CHECK((ship != nullptr ? ship->owner() : nullptr) == ship);

		// A target that is not a wormhole: nobody goes.
		SetPrimaryTarget(ship, other);
		if (ship != nullptr)  ship->wormholeGroup();
		OO_CHECK((ship != nullptr ? ship->primaryTarget() : (Entity *)nullptr) == other);

		// Not police: no offence marked.
		if (ship != nullptr)  ship->markTargetForOffence("16");
		OO_CHECK((other != nullptr ? other->getBounty() : 0) == 0);

		// No cargo bay: nothing to eject.
		if (ship != nullptr)  ship->ejectCargo();
		OO_CHECK((ship != nullptr ? ship->cargoQuantityOnBoard() : 0) == 0);
	}
}


OO_TEST(slice3TargetsAndFighting)
{
	{
		SetUp();
		TestAIShip *ship = MakeShip("fighter");
		TestAIShip *other = MakeShip("other");

		// The target is remembered, and forgotten when there is none.
		SetPrimaryTarget(ship, other);
		if (ship != nullptr)  ship->storeTarget();
		OO_CHECK((ship != nullptr ? ship->rememberedShip() : (Entity *)nullptr) == other);
		SetPrimaryTarget(ship, nil);
		if (ship != nullptr)  ship->storeTarget();
		OO_CHECK((ship != nullptr ? ship->rememberedShip() : (Entity *)nullptr) == nullptr);

		// A lost target: comms and fines go nowhere.
		if (ship != nullptr)  ship->sendTargetCommsMessage("[hello]");
		if (ship != nullptr)  ship->markTargetForFines();
		OO_CHECK((ship != nullptr ? ship->primaryTarget() : (Entity *)nullptr) == nil);

		// Full energy, no escorts, no missiles: fight the found target.
		SetEnergy3(ship, 100, 100);
		if (ship != nullptr)  ship->setFoundTarget(other);
		if (ship != nullptr)  ship->fightOrFleeHostiles();
		OO_CHECK((ship != nullptr ? ship->primaryAggressor() : (Entity *)nullptr) == other && (ship != nullptr ? ship->isDefenseTarget(other) : false));
	}
}


// From C++ (after the conversion): the members.
OO_TEST(slice3MembersFromCxx)
{
	{
		SetUp();
		TestAIShip *ship = MakeShip("member3");
		TestAIShip *other = MakeShip("other");
		ShipEntity *part = ship;
		SetPrimaryTarget(ship, other);
		part->storeTarget();
		OO_CHECK((ship != nullptr ? ship->rememberedShip() : (Entity *)nullptr) == other);
		SetAegisStatus3(ship, 42);
		part->checkAegis();
		OO_CHECK(AegisStatus3(ship) == AEGIS_NONE);
		part->disengageAutopilot();		// virtual: the ship's, which logs
	}
}


// --- Slice 4: PureAI part 3: stored targets, nearest-ship scans, stations, script actions, beacons
// (bead oo-lqyhf) ------------------------------------------------------------------------------


namespace {

bool ThrowSparks4(Entity *e)						{ return e->throw_sparks; }
unsigned NavpointCount4(ShipEntity *s)			{ return s->number_of_navpoints; }
unsigned NextNavpoint4(ShipEntity *s)			{ return s->next_navpoint_index; }
HPVector Navpoint4(ShipEntity *s, unsigned i)	{ return s->navpoints[i]; }
HPVector Coordinates4(ShipEntity *s)				{ return s->coordinates; }
void SetCoordinates4(ShipEntity *s, HPVector c)	{ s->coordinates = c; }
void SetPosition4(Entity *e, HPVector p)			{ e->position = p; }
void SetCollisionRadius4(Entity *e, GLfloat r)	{ e->collision_radius = r; }

}	// namespace


OO_TEST(slice4StoredTargetsAndScans)
{
	{
		SetUp();
		TestAIShip *ship = MakeShip("seeker");
		TestAIShip *other = MakeShip("other");
		SetScannerRange(ship, 25000);

		// A remembered ship in range is found again; none remembered, nothing found.
		if (ship != nullptr)  ship->setRememberedShip(other);
		if (ship != nullptr)  ship->recallStoredTarget();
		OO_CHECK((ship != nullptr ? ship->foundTarget() : (Entity *)nullptr) == other);
		if (ship != nullptr)  ship->setRememberedShip(nullptr);
		if (ship != nullptr)  ship->setFoundTarget(nullptr);
		if (ship != nullptr)  ship->recallStoredTarget();
		OO_CHECK((ship != nullptr ? ship->foundTarget() : (Entity *)nullptr) == nil && (ship != nullptr ? ship->rememberedShip() : (Entity *)nullptr) == nullptr);

		// Every scan of an empty universe forgets the found target.
		void (*scans[])(TestAIShip *) = {
			[](TestAIShip *s) { if (s != nullptr)  s->scanForRocks(); },
			[](TestAIShip *s) { if (s != nullptr)  s->scanForNearestShipWithPrimaryRole("trader"); },
			[](TestAIShip *s) { if (s != nullptr)  s->scanForNearestShipHavingRole("trader"); },
			[](TestAIShip *s) { if (s != nullptr)  s->scanForNearestShipWithAnyPrimaryRole("trader pirate"); },
			[](TestAIShip *s) { if (s != nullptr)  s->scanForNearestShipHavingAnyRole("trader pirate"); },
			[](TestAIShip *s) { if (s != nullptr)  s->scanForNearestShipWithScanClass("CLASS_NEUTRAL"); },
			[](TestAIShip *s) { if (s != nullptr)  s->scanForNearestShipWithoutPrimaryRole("trader"); },
			[](TestAIShip *s) { if (s != nullptr)  s->scanForNearestShipNotHavingRole("trader"); },
			[](TestAIShip *s) { if (s != nullptr)  s->scanForNearestShipWithoutAnyPrimaryRole("trader pirate"); },
			[](TestAIShip *s) { if (s != nullptr)  s->scanForNearestShipNotHavingAnyRole("trader pirate"); },
			[](TestAIShip *s) { if (s != nullptr)  s->scanForNearestShipWithoutScanClass("CLASS_NEUTRAL"); },
		};
		for (auto scan : scans)
		{
			if (ship != nullptr)  ship->setFoundTarget(other);
			scan(ship);
			OO_CHECK((ship != nullptr ? ship->foundTarget() : (Entity *)nullptr) == nil);
		}

		// No group, so no mother to defend: the found target stays.
		if (ship != nullptr)  ship->setFoundTarget(other);
		if (ship != nullptr)  ship->requestNewTarget();
		OO_CHECK((ship != nullptr ? ship->foundTarget() : (Entity *)nullptr) == other);
	}
}


OO_TEST(slice4StationsAndCoordinates)
{
	{
		SetUp();
		TestAIShip *ship = MakeShip("docker");
		TestAIShip *other = MakeShip("other");

		// No station anywhere: back off 8 km from the origin, straight back.
		SetPosition4(ship, make_HPvector(0, 0, 0));
		SetCollisionRadius4(ship, 0);
		if (ship != nullptr)  ship->setDestinationToDockingAbort();
		OO_CHECK(HPdistance(Coordinates4(ship), make_HPvector(0, 0, -8000)) < 1e-3 && HPdistance(Destination(ship), make_HPvector(0, 0, -8000)) < 1e-3);

		// No stations in range, and a last station that is not one: no target.
		if (ship != nullptr)  ship->setTargetToRandomStation();
		OO_CHECK((ship != nullptr ? ship->primaryTarget() : (Entity *)nullptr) == nil);
		if (ship != nullptr)  ship->setTargetStation(other);
		if (ship != nullptr)  ship->setTargetToLastStation();
		OO_CHECK((ship != nullptr ? ship->primaryTarget() : (Entity *)nullptr) == nil && (ship != nullptr ? ship->targetStation() : (Entity *)nullptr) == nullptr);

		// A malformed coordinate string changes nothing.
		SetCoordinates4(ship, make_HPvector(1, 2, 3));
		if (ship != nullptr)  ship->setCoordinates("wpu 1 2");
		OO_CHECK(HPdistance2(Coordinates4(ship), make_HPvector(1, 2, 3)) == 0);
		if (ship != nullptr)  ship->checkForNormalSpace();
	}
}


OO_TEST(slice4ActionsAndRacepoints)
{
	{
		SetUp();
		TestAIShip *ship = MakeShip("racer");
		TestAIShip *pylon = MakeShip("pylon");

		if (ship != nullptr)  ship->setFuel(0);
		if (ship != nullptr)  ship->addFuel("3");
		OO_CHECK((ship != nullptr ? ship->getFuel() : OOFuelQuantity{}) == 30);

		if (ship != nullptr)  ship->ai_throwSparks();
		OO_CHECK(ThrowSparks4(ship));

		// Nothing to act on, or no script to tell: nothing happens.
		if (ship != nullptr)  ship->scriptActionOnTarget("set: mission_x 1");
		if (ship != nullptr)  ship->safeScriptActionOnTarget("set: mission_x 1");
		if (ship != nullptr)  ship->sendScriptMessage("");
		if (ship != nullptr)  ship->sendScriptMessage("hello");
		if (ship != nullptr)  ship->sendScriptMessage("hello a b");
		if (ship != nullptr)  ship->rollD("0");				// logged
		if (ship != nullptr)  ship->rollD("6");
		if (ship != nullptr)  ship->ai_debugMessage("hi");
		OO_CHECK((ship != nullptr ? ship->status() : OOEntityStatus{}) == STATUS_IN_FLIGHT);

		// No target: no racepoints.
		if (ship != nullptr)  ship->setRacepointsFromTarget();
		OO_CHECK(NavpointCount4(ship) == 0);
		SetPosition4(pylon, make_HPvector(100, 0, 0));
		SetCollisionRadius4(pylon, 10);
		if (pylon != nullptr)  pylon->setOrientation(kIdentityQuaternion);
		SetPrimaryTarget(ship, pylon);
		if (ship != nullptr)  ship->setRacepointsFromTarget();
		OO_CHECK(NavpointCount4(ship) == 2 && NextNavpoint4(ship) == 0);
		OO_CHECK(HPdistance(Navpoint4(ship, 0), make_HPvector(100, 0, -10)) < 1e-3 && HPdistance(Navpoint4(ship, 1), make_HPvector(100, 0, 10)) < 1e-3);
		OO_CHECK(HPdistance2(Destination(ship), Navpoint4(ship, 0)) == 0);

		SetCollisionRadius4(ship, 25);
		if (ship != nullptr)  ship->performFlyRacepoints();
		OO_CHECK(Behaviour(ship) == BEHAVIOUR_FLY_THRU_NAVPOINTS && DesiredRange(ship) == 25 && NextNavpoint4(ship) == 0);
	}
}


// From C++ (after the conversion): the members.
OO_TEST(slice4MembersFromCxx)
{
	{
		SetUp();
		TestAIShip *ship = MakeShip("member4");
		ShipEntity *part = ship;
		if (ship != nullptr)  ship->setFuel(0);
		part->addFuel("2");
		OO_CHECK((ship != nullptr ? ship->getFuel() : OOFuelQuantity{}) == 20);
		SetCollisionRadius4(ship, 12);
		part->performFlyRacepoints();
		OO_CHECK(Behaviour(ship) == BEHAVIOUR_FLY_THRU_NAVPOINTS && DesiredRange(ship) == 12);
	}
}


OO_TEST_MAIN()
