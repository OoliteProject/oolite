/*	test_ShipEntity.mm
	Unit tests for ShipEntity (src/Core/Entities/ShipEntity.h), the ship: slice 1 of its slice plan
	(docs/phases/3-slices/ShipEntity.md, bead oo-60fwo), the class shell, which moves the ship's
	state into ShipEntity and keeps the Objective-C ShipEntity as its facade (proposed
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
	crossing: an Objective-C ship's C++ part is a ShipEntity, the facade's _cxxShip is that
	part, and a ship released before its initialiser ran is deallocated without a C++ part.
	Run: bash tools/check-core-tests.sh
*/

#include "ShipEntity.h"
#include "OOShipGroup.h"
#include "OODescription.h"
#include "Universe.h"
#include "OOColor.h"
#include "OORoleSet.h"
#include "OOCharacter.h"
#include "AI.h"
#include "PlayerEntity.h"
#include "ShipEntityScriptMethods.h"
#include "ShipEntityLoadRestore.h"

#include "oo_test.hpp"

#include <cmath>
#include <initializer_list>
#include <string>


// main.mm defines the debug flags, and the test has its own main.
#ifndef NDEBUG
uint32_t gDebugFlags = 0;
#endif

class PlayerEntity;
extern PlayerEntity *gOOPlayer;
extern Universe *gSharedUniverse;
extern ooscript::Context gOOJSMainThreadContext;


class TestPlayer : public PlayerEntity	// C++ since bead oo-9ht.177 deleted the Objective-C player
{
public:
	HPVector viewpointPosition() override	{ return kZeroHPVector; }
};

// NewTestPlayer<TestPlayer>() (bead oo-9ht.177): a C++ player under the ship's facade, as
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



namespace {

// What the next ship's set-up does.
bool sFailSetUp = false;
bool sInfiniteSpeed = false;

}	// namespace


// A ship whose set-up from shipdata only counts and records what it was given (a C++ subclass since
// bead oo-9ht.144 deleted the Objective-C ship).
class TestShip : public ShipEntity
{
public:
	int			_setUps = 0;
	oo::PList	_setUpDict;

	bool setUpShipFromDictionary(const oo::PList &dict) override
	{
		_setUps++;
		_setUpDict = dict;
		if (sInfiniteSpeed)  setMaxFlightSpeed(INFINITY);
		return !sFailSetUp;
	}
};


namespace {

// [[[T alloc] cxx_initWithKey:key definition:dict] autorelease] (bead oo-9ht.144): a ship made in C++,
// its object autoreleased; null where the set-up failed (the initialiser answered nil).
template <class T>
T *MakeShip(const std::string &key, const oo::PList &dict)
{
	return static_cast<T *>(oo::ToShip(oo::AutoreleaseEntity(oo::NewShipObject(oo::makeRef<T>(), key, dict))));
}

// [[T alloc] cxx_initWithKey:key definition:dict]: the same with its object retained (+1).
template <class T>
T *NewShip(const std::string &key, const oo::PList &dict)
{
	return static_cast<T *>(oo::ToShip(oo::NewShipObject(oo::makeRef<T>(), key, dict)));
}

}	// namespace


// --- The members private again in C++ (bead oo-9ht.184.1), and nothing else -------------------------

struct ShipEntityTestAccess
{
	static double &NextAegisCheck(ShipEntity *s)			{ return s->_nextAegisCheck; }
	static uint8_t MaxEscortCount(const ShipEntity *s)		{ return s->_maxEscortCount; }
	static uint8_t PendingEscortCount(const ShipEntity *s)	{ return s->_pendingEscortCount; }
	static float HeatInsulation(const ShipEntity *s)		{ return s->_heatInsulation; }
	static GLfloat ProfileRadius(const ShipEntity *s)		{ return s->_profileRadius; }
	static BOOL &IsDemoShip(ShipEntity *s)					{ return s->isDemoShip; }
	static OOScalar &DemoRate(ShipEntity *s)				{ return s->demoRate; }
	static std::vector<std::string> &Equipment(ShipEntity *s)	{ return s->_equipment; }
	static BOOL &EscortPositionsValid(ShipEntity *s)		{ return s->_escortPositionsValid; }
	static Quaternion &DemoStartOrientation(ShipEntity *s)	{ return s->demoStartOrientation; }
};

// --------------------------------------------------------------------------------------------------


namespace {

// --- Ivars the game reads directly (ship->shot_time), and nothing else ----------------------------

OOTimeDelta ShotTime(ShipEntity *s)		{ return s->shot_time; }
OOBehaviour Behaviour(ShipEntity *s)	{ return s->behaviour; }
void SetSubEntity(Entity *e, bool value)	{ e->isSubEntity = value; }
void SetFrustration(ShipEntity *s, GLfloat value)	{ s->frustration = value; }
void SetPlanetForLanding(ShipEntity *s, OOUniversalID uid)	{ s->planetForLanding = uid; }
void SetPreviousCondition(ShipEntity *s, const oo::PList &condition)	{ s->previousCondition = condition; }
unsigned NextNavpoint(ShipEntity *s)	{ return s->next_navpoint_index; }
GLfloat WeaponDamage(ShipEntity *s)	{ return s->weapon_damage; }
OOAegisStatus AegisStatus(ShipEntity *s)	{ return s->aegis_status; }
void SetAegisStatus(ShipEntity *s, OOAegisStatus status)	{ s->aegis_status = status; }
void SetSticks(ShipEntity *s, GLfloat roll, GLfloat pitch, GLfloat yaw)	{ s->stick_roll = roll; s->stick_pitch = pitch; s->stick_yaw = yaw; }
GLfloat ScaleFactor(ShipEntity *s)	{ return s->_scaleFactor; }
void SetMass(Entity *e, GLfloat value)	{ e->mass = value; }
bool IsWreckage(ShipEntity *s)	{ return s->isWreckage; }
void SetShowDamage(ShipEntity *s, bool value)	{ s->_showDamage = value; }
void SetWeaponTemps(ShipEntity *s, GLfloat temp, GLfloat aft)	{ s->weapon_temp = temp; s->aft_weapon_temp = aft; }
bool SuppressesExplosion(ShipEntity *s)	{ return s->suppressExplosion; }
void SetBoundingBox(Entity *e, BoundingBox box)	{ e->boundingBox = box; }
void SetShotTime(ShipEntity *s, OOTimeDelta value)	{ s->shot_time = value; }
double NextAegisCheck(ShipEntity *s)	{ return ShipEntityTestAccess::NextAegisCheck(s); }
double LaunchTime(ShipEntity *s)	{ return s->launch_time; }
double LaunchDelay(ShipEntity *s)	{ return s->launch_delay; }
void SetExplicitlyUnpiloted(ShipEntity *s, bool value)	{ s->_explicitlyUnpiloted = value; }

void SetPrimaryTarget(ShipEntity *s, Entity *target)
{
	s->_primaryTarget = oo::WeakRef<Entity>(target);	// the entity's C++ part (bead oo-9ht.39.5.2)
}

void SetProximityAlert(ShipEntity *s, Entity *other)
{
	s->_proximityAlert = oo::WeakRef<Entity>(other);	// the entity's C++ part (bead oo-9ht.39.5.2)
}

void SetNavpoints(ShipEntity *s, std::initializer_list<HPVector> points, unsigned next)
{
	unsigned n = 0;
	for (HPVector p : points)  s->navpoints[n++] = p;
	s->number_of_navpoints = n;
	s->next_navpoint_index = next;
}

// --------------------------------------------------------------------------------------------------


void SetUp()
{
	static Universe *universe = nil;
	if (universe == nil)
	{
		universe = new Universe();	// never released
	}
	gSharedUniverse = universe;
	static TestPlayer *player = nullptr;
	if (player == nullptr)  player = NewTestPlayer<TestPlayer>();
	gOOPlayer = player;
	// The ship's -dealloc sends its (absent) scripts entityDestroyed in a request on the main
	// thread's context, so there is one, with nothing in it.
	if (gOOJSMainThreadContext == nullptr)  gOOJSMainThreadContext = ooscript::newContext(ooscript::newRuntime(8u * 1024u * 1024u), 8192);
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
	{
		SetUp();
		TestShip *ship = MakeShip<TestShip>("test-ship", Definition());
		OO_CHECK(ship != nil);
		OO_CHECK(ship->_setUps == 1 && ship->_setUpDict.get<double>("max_flight_speed", 0) == 250.0);
		OO_CHECK((ship != nullptr ? ship->getIsShip() : false) && !(ship != nullptr ? ship->getIsStation() : false) && !(ship != nullptr ? ship->getIsPlayer() : false));
		OO_CHECK((ship != nullptr ? ship->shipDataKey() : std::optional<std::string>()) == std::optional<std::string>("test-ship"));
		OO_CHECK((ship != nullptr ? ship->status() : OOEntityStatus{}) == STATUS_IN_FLIGHT);
		OO_CHECK((ship != nullptr ? ship->zeroDistance() : 0.0) == (GLfloat)(SCANNER_MAX_RANGE2 * 2.0));
		OO_CHECK((ship != nullptr ? ship->weaponRechargeRate() : 0.0f) == 6.0f);
		OO_CHECK(ShotTime(ship) == INITIAL_SHOT_TIME);
		OO_CHECK((ship != nullptr ? ship->temperature() : 0.0f) == SHIP_MIN_CABIN_TEMP);
		OO_CHECK((ship != nullptr ? ship->getCurrentWeaponFacing() : OOWeaponFacing{}) == WEAPON_FACING_FORWARD);
		OO_CHECK((ship != nullptr ? ship->laserHeatLevelForward() : 0.0f) == 0 && (ship != nullptr ? ship->laserHeatLevelAft() : 0.0f) == 0 && (ship != nullptr ? ship->laserHeatLevelPort() : 0.0f) == 0 && (ship != nullptr ? ship->laserHeatLevelStarboard() : 0.0f) == 0);
		OO_CHECK((ship != nullptr ? ship->entityPersonalityInt() : GLint{}) >= 0 && (ship != nullptr ? ship->entityPersonalityInt() : GLint{}) <= (GLint)ENTITY_PERSONALITY_MAX);
		OO_CHECK((ship != nullptr ? ship->getMaxFlightSpeed() : 0.0f) == 0);	// the set-up did not set it
		OO_CHECK(Behaviour(ship) == BEHAVIOUR_IDLE);
	}
}


OO_TEST(initIsAnEmptyKey)
{
	{
		SetUp();
		TestShip *ship = MakeShip<TestShip>(std::string{}, oo::PList());
		OO_CHECK(ship != nil && ship->_setUps == 1 && ship->_setUpDict.isNull());
		OO_CHECK((ship != nullptr ? ship->shipDataKey() : std::optional<std::string>()) == std::optional<std::string>(""));
		OO_CHECK((ship != nullptr ? ship->getIsShip() : false) && (ship != nullptr ? ship->status() : OOEntityStatus{}) == STATUS_IN_FLIGHT);
	}
}


OO_TEST(initFailsWhenSetUpFails)
{
	{
		SetUp();
		sFailSetUp = true;
		TestShip *ship = NewShip<TestShip>("bad", Definition());
		OO_CHECK(ship == nil);
	}
}


OO_TEST(initClampsAnInfiniteTopSpeed)
{
	{
		SetUp();
		sInfiniteSpeed = true;
		TestShip *ship = MakeShip<TestShip>("fast", Definition());
		OO_CHECK(ship != nil && (ship != nullptr ? ship->getMaxFlightSpeed() : 0.0f) == 300.0f);
	}
}


OO_TEST(deallocLeavesItsGroups)
{
	oo::Ref<OOShipGroup> group;	// C++ since bead oo-9ht.19: held where the facades were retained
	oo::Ref<OOShipGroup> escorts;
	{
		SetUp();
		group = OOShipGroup::groupWithName(std::nullopt);	// -init
		TestShip *ship = NewShip<TestShip>("grouped", Definition());
		if (ship != nullptr)  ship->setGroup(group.get());
		escorts = oo::Ref<OOShipGroup>((ship != nullptr ? ship->escortGroup() : (OOShipGroup *)nullptr));
		OO_CHECK(group->containsShip(ship) && escorts->containsShip(ship) && escorts->leader() == ship);
		if (ship != nullptr)  oo::ReleaseEntity(ship);
	}
	OO_CHECK(group->count() == 0 && escorts->count() == 0);
	group = nullptr;
	escorts = nullptr;
}


OO_TEST(subEntityRelationship)
{
	{
		SetUp();
		Entity *plain = oo::MadeEntity(oo::makeRef<Entity>());
		TestShip *ship = MakeShip<TestShip>("mother", Definition());
		TestShip *sub = MakeShip<TestShip>("turret", Definition());
		TestShip *other = MakeShip<TestShip>("other", Definition());

		// Entity's: never.
		OO_CHECK(!oo::EntityIsShipWithSubEntityShip(plain, ship));
		// (Its object's -drawSubEntityImmediate:translucent:, the root facade's category, did nothing: retired
		// with the facade, bead oo-dpyk8, under oo-9n5p9.)

		// The ship's: a ship that is its subentity, and that it agrees is.
		OO_CHECK(!(ship != nullptr ? ship->isShipWithSubEntityShip(plain) : false));
		OO_CHECK(!(ship != nullptr ? ship->isShipWithSubEntityShip(sub) : false));		// not a subentity
		if (ship != nullptr)  ship->addSubEntity(sub);
		OO_CHECK((sub != nullptr ? sub->owner() : nullptr) == ship && (ship != nullptr ? ship->hasSubEntity(sub) : false));
		OO_CHECK((ship != nullptr ? ship->isShipWithSubEntityShip(sub) : false));
		OO_CHECK(!(other != nullptr ? other->isShipWithSubEntityShip(sub) : false));		// someone else's
#ifndef NDEBUG
		// A ship that claims the parent, which does not agree: an internal error, and it is cut loose.
		SetSubEntity(other, true);
		if (other != nullptr)  other->setOwner(ship);
		OO_CHECK(!(ship != nullptr ? ship->isShipWithSubEntityShip(other) : false));
		OO_CHECK((other != nullptr ? other->owner() : nullptr) == nil);
		SetSubEntity(other, false);
#endif
		if (ship != nullptr)  ship->clearSubEntities();
		OO_CHECK((sub != nullptr ? sub->owner() : nullptr) == nil);
	}
}


// --- Slice 2: -cxx_setUpFromDictionary:, the set-up players and NPCs share (bead oo-cvbe3) -------

namespace {

const ShipEntity *Part(ShipEntity *s)	{ return s; }

}	// namespace


// An empty definition (nil, as PlayerEntity's -deferredInit may give) is an empty dictionary,
// and every setting takes its default.
OO_TEST(setUpFromDictionaryDefaults)
{
	{
		SetUp();
		TestShip *ship = MakeShip<TestShip>("defaults", Definition());
		OO_CHECK((ship != nullptr ? ship->setUpFromDictionary(oo::PList()) : false));
		const ShipEntity *part = Part(ship);
		OO_CHECK((ship != nullptr ? ship->shipInfoDictionary() : oo::PList()).isDict() && (ship != nullptr ? ship->shipInfoDictionary() : oo::PList()).count() == 0);
		OO_CHECK((ship != nullptr ? ship->getMaxFlightSpeed() : 0.0f) == 160.0f && (ship != nullptr ? ship->maxFlightRoll() : 0.0f) == 2.0f && (ship != nullptr ? ship->maxFlightPitch() : 0.0f) == 1.0f && (ship != nullptr ? ship->maxFlightYaw() : 0.0f) == 1.0f);
		OO_CHECK((ship != nullptr ? ship->getCruiseSpeed() : 0.0) == 160.0f * 0.8f);
		OO_CHECK((ship != nullptr ? ship->maxThrust() : 0.0f) == 15.0f && (ship != nullptr ? ship->getThrust() : 0.0f) == 15.0f);
		OO_CHECK((ship != nullptr ? ship->afterburnerFactor() : 0.0f) == 7.0f && (ship != nullptr ? ship->afterburnerRate() : 0.0f) == AFTERBURNER_BURNRATE);
		OO_CHECK((ship != nullptr ? ship->getMaxEnergy() : 0.0f) == 200.0f && part->energy_recharge_rate == 1.0f);
		OO_CHECK((ship != nullptr ? ship->weaponFacings() : OOWeaponFacingSet{}) == VALID_WEAPON_FACINGS);
		OO_CHECK((ship != nullptr ? ship->missileCount() : 0) == 0 && (ship != nullptr ? ship->missileCapacity() : 0) == 0);
		OO_CHECK(part->cloakPassive && part->cloakAutomatic && !part->cloaking_device_active && !part->military_jammer_active);
		OO_CHECK(part->isFrangible && !part->isWreckage && part->canFragment);
		OO_CHECK(part->max_cargo == 0 && (ship != nullptr ? ship->extraCargo() : 0) == 15);
		OO_CHECK((ship != nullptr ? ship->hyperspaceSpinTime() : 0.0f) == DEFAULT_HYPERSPACE_SPIN_TIME);
		OO_CHECK((ship != nullptr ? ship->getName() : std::optional<std::string>()) == std::optional<std::string>("?"));
		OO_CHECK((ship != nullptr ? ship->getShipUniqueName() : std::optional<std::string>()) == std::optional<std::string>(""));
		OO_CHECK((ship != nullptr ? ship->getShipClassName() : std::optional<std::string>()) == std::optional<std::string>("?"));
		OO_CHECK(part->displayName == std::nullopt);
		OO_CHECK(part->_scaleFactor == 1.0f);
		OO_CHECK(!(ship != nullptr ? ship->scriptedMisjump() : false) && (ship != nullptr ? ship->scriptedMisjumpRange() : 0.0f) == 0.5f);
		OO_CHECK(part->_lightsActive && !part->haveExecutedSpawnAction && !part->isMissile);
		OO_CHECK(quaternion_equal((ship != nullptr ? ship->subEntityRotationalVelocity() : Quaternion{}), kIdentityQuaternion));
		OO_CHECK(!part->_multiplyWeapons && part->forwardWeaponOffset.size() == 1 && vector_equal(part->forwardWeaponOffset[0], kZeroVector));
		OO_CHECK((ship != nullptr ? ship->getSunGlareFilter() : 0.0f) == 0.97f);
		OO_CHECK(part->scriptInfo.isNull() && part->explosionType.isNull());
		OO_CHECK(!(ship != nullptr ? ship->getIsDemoShip() : false));
	}
}


// Each setting from the definition, with the clamps: an injector speed factor under 1, too many
// missiles for the pylons, too many pylons; and what follows from others (scaled positions, the
// class name from the name, no hyperspace motor).
OO_TEST(setUpFromDictionaryValues)
{
	{
		SetUp();
		TestShip *ship = MakeShip<TestShip>("values", Definition());
		const oo::PList definition(oo::PList::Dict{
			{ "max_flight_speed", oo::PList(300.0) },
			{ "max_flight_roll", oo::PList(3.0) },
			{ "max_flight_pitch", oo::PList(1.5) },
			{ "thrust", oo::PList(20.0) },
			{ "injector_burn_rate", oo::PList(0.5) },
			{ "injector_speed_factor", oo::PList(0.5) },
			{ "max_energy", oo::PList(500.0) },
			{ "energy_recharge_rate", oo::PList(4.0) },
			{ "weapon_facings", oo::PList(0xFF) },
			{ "missiles", oo::PList(40) },
			{ "max_missiles", oo::PList(50) },
			{ "cloak_passive", oo::PList(false) },
			{ "frangible", oo::PList(false) },
			{ "max_cargo", oo::PList(20) },
			{ "extra_cargo", oo::PList(5) },
			{ "hyperspace_motor", oo::PList(false) },
			{ "name", oo::PList(std::string("Viper")) },
			{ "ship_name", oo::PList(std::string("Bob")) },
			{ "display_name", oo::PList(std::string("Police Viper")) },
			{ "model_scale_factor", oo::PList(2.0) },
			{ "scoop_position", oo::PList(std::string("1 2 3")) },
			{ "weapon_mount_mode", oo::PList(std::string("multiply")) },
			{ "weapon_position_forward", oo::PList(oo::PList::Array{ oo::PList(std::string("1 0 0")), oo::PList(std::string("-1 0 0")) }) },
			{ "sun_glare_filter", oo::PList(0.5) },
			{ "script_info", oo::PList(oo::PList::Dict{ { "a", oo::PList(1) } }) },
			{ "explosion_type", oo::PList(oo::PList::Array{ oo::PList(std::string("boom")) }) },
		});
		OO_CHECK((ship != nullptr ? ship->setUpFromDictionary(definition) : false));
		const ShipEntity *part = Part(ship);
		OO_CHECK((ship != nullptr ? ship->shipInfoDictionary() : oo::PList()).get<std::string>("name", "") == "Viper");
		OO_CHECK((ship != nullptr ? ship->getMaxFlightSpeed() : 0.0f) == 300.0f && (ship != nullptr ? ship->maxFlightRoll() : 0.0f) == 3.0f && (ship != nullptr ? ship->maxFlightPitch() : 0.0f) == 1.5f);
		OO_CHECK((ship != nullptr ? ship->maxFlightYaw() : 0.0f) == 1.5f);	// yaw defaults to pitch
		OO_CHECK((ship != nullptr ? ship->getCruiseSpeed() : 0.0) == 300.0f * 0.8f);
		OO_CHECK((ship != nullptr ? ship->maxThrust() : 0.0f) == 20.0f && (ship != nullptr ? ship->getThrust() : 0.0f) == 20.0f);
		OO_CHECK((ship != nullptr ? ship->afterburnerFactor() : 0.0f) == 1.0f && (ship != nullptr ? ship->afterburnerRate() : 0.0f) == 0.5f);
		OO_CHECK((ship != nullptr ? ship->getMaxEnergy() : 0.0f) == 500.0f && part->energy_recharge_rate == 4.0f);
		OO_CHECK((ship != nullptr ? ship->weaponFacings() : OOWeaponFacingSet{}) == VALID_WEAPON_FACINGS);
		OO_CHECK((ship != nullptr ? ship->missileCapacity() : 0) == SHIPENTITY_MAX_MISSILES && part->missiles == SHIPENTITY_MAX_MISSILES);
		OO_CHECK(!part->cloakPassive && !part->isFrangible);
		OO_CHECK(part->max_cargo == 20 && (ship != nullptr ? ship->extraCargo() : 0) == 5);
		OO_CHECK((ship != nullptr ? ship->hyperspaceSpinTime() : 0.0f) == -1);
		OO_CHECK((ship != nullptr ? ship->getName() : std::optional<std::string>()) == std::optional<std::string>("Viper"));
		OO_CHECK((ship != nullptr ? ship->getShipUniqueName() : std::optional<std::string>()) == std::optional<std::string>("Bob"));
		OO_CHECK((ship != nullptr ? ship->getShipClassName() : std::optional<std::string>()) == std::optional<std::string>("Viper"));
		OO_CHECK(part->displayName == std::optional<std::string>("Police Viper"));
		OO_CHECK(part->_scaleFactor == 2.0f);
		OO_CHECK(vector_equal(part->tractor_position, make_vector(2, 4, 6)));
		OO_CHECK(part->_multiplyWeapons && part->forwardWeaponOffset.size() == 2);
		OO_CHECK(part->forwardWeaponOffset.size() == 2 && vector_equal(part->forwardWeaponOffset[1], make_vector(-2, 0, 0)));
		OO_CHECK((ship != nullptr ? ship->getSunGlareFilter() : 0.0f) == 0.5f);
		OO_CHECK(part->scriptInfo.get<int>("a", 0) == 1);
		OO_CHECK(part->explosionType.isArray() && part->explosionType.count() == 1);
	}
}


// --- Slice 3: -setUpShipFromDictionary:, subentity serialisation and set-up (bead oo-mvzmb) -----

// A ship that keeps ShipEntity's own set-up.
class PlainShip : public ShipEntity	// C++ since bead oo-9ht.144
{
};


namespace {

ShipEntity *MutablePart(ShipEntity *s)	{ return s; }

}	// namespace


// The NPC settings on top of the shared ones: scan class, energy, weapon damage of a missile,
// roles without "player", the escort clamp, beacons, an unpiloted ship.
OO_TEST(setUpShipFromDictionaryNPC)
{
	{
		SetUp();
		const oo::PList definition(oo::PList::Dict{
			{ "scan_class", oo::PList(std::string("CLASS_POLICE")) },
			{ "scan_description", oo::PList(std::string("Cop")) },
			{ "max_energy", oo::PList(300.0) },
			{ "weapon_energy", oo::PList(12.0) },
			{ "scanner_range", oo::PList(30000.0) },
			{ "fuel", oo::PList(70) },
			{ "likely_cargo", oo::PList(3) },
			{ "has_scoop_message", oo::PList(false) },
			{ "roles", oo::PList(std::string("police player")) },
			{ "accuracy", oo::PList(3.0) },
			{ "escorts", oo::PList(20) },
			{ "beacon", oo::PList(std::string("B")) },
			{ "heat_insulation", oo::PList(1.5) },
			{ "unpiloted", oo::PList(true) },
			{ "reaction_time", oo::PList(2.0) },
		});
		PlainShip *ship = MakeShip<PlainShip>("npc", definition);
		OO_CHECK(ship != nil);
		const ShipEntity *part = Part(ship);
		OO_CHECK((ship != nullptr ? ship->getIsShip() : false) && (ship != nullptr ? ship->getScanClass() : OOScanClass{}) == CLASS_POLICE);
		OO_CHECK(part->scan_description == std::optional<std::string>("Cop"));
		OO_CHECK((ship != nullptr ? ship->getEnergy() : 0.0f) == 300.0 && (ship != nullptr ? ship->getMaxEnergy() : 0.0f) == 300.0f);
		OO_CHECK(part->weapon_damage == 12.0f && part->weapon_damage_override == 12.0f);
		OO_CHECK(part->scannerRange == 30000.0f && (ship != nullptr ? ship->getFuel() : OOFuelQuantity{}) == 70 && part->fuel_accumulator == 1.0f);
		OO_CHECK(part->likely_cargo == 3 && !part->hasScoopMessage);
		OO_CHECK((ship != nullptr ? ship->hasRole("police") : false) && !(ship != nullptr ? ship->hasRole("player") : false));
		OO_CHECK((ship != nullptr ? ship->getAccuracy() : 0.0f) == 3.0f);
		OO_CHECK(ShipEntityTestAccess::MaxEscortCount(part) == MAX_ESCORTS && ShipEntityTestAccess::PendingEscortCount(part) == MAX_ESCORTS);
		OO_CHECK((ship != nullptr ? ship->beaconCode() : std::optional<std::string>()) == std::optional<std::string>("B") && (ship != nullptr ? ship->beaconLabel() : std::optional<std::string>()) == std::optional<std::string>("B"));
		OO_CHECK(ShipEntityTestAccess::HeatInsulation(part) == 1.5f);
		OO_CHECK(part->_explicitlyUnpiloted && part->crew == std::nullopt);
		OO_CHECK(part->reactionTime == 2.0f);
		OO_CHECK(vector_equal((ship != nullptr ? ship->forwardVector() : Vector{}), kBasisZVector) && vector_equal((ship != nullptr ? ship->upVector() : Vector{}), kBasisYVector) && vector_equal((ship != nullptr ? ship->rightVector() : Vector{}), kBasisXVector));
		OO_CHECK(part->cargo_type == CARGO_NOT_CARGO);
		OO_CHECK((ship != nullptr ? ship->getAI() : (::AI *)nullptr) != nil && (ship != nullptr ? ship->owner() : nullptr) == ship);
	}
}


OO_TEST(subIdxAndSerialisation)
{
	{
		SetUp();
		TestShip *ship = MakeShip<TestShip>("mother", Definition());
		TestShip *a = MakeShip<TestShip>("a", Definition());
		TestShip *b = MakeShip<TestShip>("b", Definition());
		if (a != nullptr)  a->setSubIdx(0);
		if (b != nullptr)  b->setSubIdx(2);
		OO_CHECK((a != nullptr ? a->subIdx() : 0) == 0 && (b != nullptr ? b->subIdx() : 0) == 2);
		if (ship != nullptr)  ship->addSubEntity(a);
		if (ship != nullptr)  ship->addSubEntity(b);
		MutablePart(ship)->_maxShipSubIdx = 4;
		OO_CHECK((ship != nullptr ? ship->maxShipSubEntities() : 0) == 4);
		OO_CHECK((ship != nullptr ? ship->serializeShipSubEntities() : std::optional<std::string>()) == std::optional<std::string>("1010"));
		if (ship != nullptr)  ship->deserializeShipSubEntitiesFrom("1111");	// every one is alive: nothing happens
		OO_CHECK((ship != nullptr ? ship->subEntityCount() : 0) == 2 && (a != nullptr ? a->owner() : nullptr) == ship && (b != nullptr ? b->owner() : nullptr) == ship);
		if (ship != nullptr)  ship->clearSubEntities();
	}
}


// -setUpSubEntities with no exhausts or subentities: the profile radius is the collision radius,
// and the frustum radius is the profile radius (no exhaust is longer).
OO_TEST(setUpSubEntitiesAndFrustumRadius)
{
	{
		SetUp();
		TestShip *ship = MakeShip<TestShip>("bare", Definition());
		OO_CHECK((ship != nullptr ? ship->setUpFromDictionary(oo::PList()) : false));
		MutablePart(ship)->collision_radius = 25.0f;
		OO_CHECK((ship != nullptr ? ship->setUpSubEntities() : false));
		OO_CHECK((ship != nullptr ? ship->maxShipSubEntities() : 0) == 0 && (ship != nullptr ? ship->subEntityCount() : 0) == 0);
		OO_CHECK(ShipEntityTestAccess::ProfileRadius(Part(ship)) == 25.0f);
		OO_CHECK((ship != nullptr ? ship->frustumRadius() : 0.0f) == 25.0f);
		OO_CHECK(Part(ship)->no_draw_distance == (GLfloat)(25.0 * 25.0 * NO_DRAW_DISTANCE_FACTOR * NO_DRAW_DISTANCE_FACTOR * 2.0));
	}
}


// --- Slice 4: standard subentities, cargo pods, descriptions, mesh, vectors, misjump, lists (oo-ln2m1)

OO_TEST(cargoTypeAndTemplatePod)
{
	{
		SetUp();
		TestShip *ship = MakeShip<TestShip>("pod", Definition());
		OO_CHECK(!(ship != nullptr ? ship->isTemplateCargoPod() : false));
		if (ship != nullptr)  ship->setUpCargoType("CARGO_ALLOY");
		OO_CHECK(Part(ship)->cargo_type == CARGO_RANDOM && Part(ship)->commodity_type == std::optional<std::string>("alloys") && Part(ship)->commodity_amount == 1);
		if (ship != nullptr)  ship->setUpCargoType("CARGO_SCRIPTED_ITEM");
		OO_CHECK(Part(ship)->cargo_type == CARGO_SCRIPTED_ITEM && Part(ship)->commodity_type == std::nullopt && Part(ship)->commodity_amount == 1);
		if (ship != nullptr)  ship->setUpCargoType("CARGO_NOT_CARGO");
		OO_CHECK(Part(ship)->cargo_type == CARGO_NOT_CARGO);
	}
}


OO_TEST(simpleAccessors)
{
	{
		SetUp();
		TestShip *ship = MakeShip<TestShip>("acc", Definition());
		if (ship != nullptr)  ship->setSunGlareFilter(2.0f);
		OO_CHECK((ship != nullptr ? ship->getSunGlareFilter() : 0.0f) == 1.0f);
		if (ship != nullptr)  ship->setSunGlareFilter(0.25f);
		OO_CHECK((ship != nullptr ? ship->getSunGlareFilter() : 0.0f) == 0.25f);

		if (ship != nullptr)  ship->setAccuracy(20.0f);
		OO_CHECK((ship != nullptr ? ship->getAccuracy() : 0.0f) == 10.0f);
		OO_CHECK(Part(ship)->pitch_tolerance == (GLfloat)(0.01 * (85.0f + 10.0f)) && Part(ship)->aim_tolerance == (GLfloat)(240.0 - 18.0f * 10.0f));
		OO_CHECK(Part(ship)->missile_load_time == 2.0);
		if (ship != nullptr)  ship->setAccuracy(-9.0f);
		OO_CHECK((ship != nullptr ? ship->getAccuracy() : 0.0f) == -5.0f);

		Quaternion q = { 0.5f, 0.5f, 0.5f, 0.5f };
		if (ship != nullptr)  ship->setSubEntityRotationalVelocity(q);
		OO_CHECK(quaternion_equal((ship != nullptr ? ship->subEntityRotationalVelocity() : Quaternion{}), q));

		if (ship != nullptr)  ship->setScriptedMisjump(YES);
		if (ship != nullptr)  ship->setScriptedMisjumpRange(0.75f);
		OO_CHECK((ship != nullptr ? ship->scriptedMisjump() : false) && (ship != nullptr ? ship->scriptedMisjumpRange() : 0.0f) == 0.75f);

		OO_CHECK((ship != nullptr ? ship->mesh() : (OOMesh *)nullptr) == nullptr && ship->getOctree() == nullptr);
		OO_CHECK((ship != nullptr ? ship->shipScript() : (OOScript *)nullptr) == nil && (ship != nullptr ? ship->shipAIScript() : (OOScript *)nullptr) == nil);
		if (ship != nullptr)  ship->setAIScriptWakeTime(12.5);
		OO_CHECK((ship != nullptr ? ship->shipAIScriptWakeTime() : OOTimeAbsolute{}) == 12.5);
		if (ship != nullptr)  ship->removeScript();
		OO_CHECK((ship != nullptr ? ship->shipScript() : (OOScript *)nullptr) == nil);

		BoundingBox box = (ship != nullptr ? ship->getTotalBoundingBox() : BoundingBox{});
		OO_CHECK(box.min.x == 0 && box.max.x == 0);
	}
}


OO_TEST(descriptions)
{
	{
		SetUp();
		TestShip *ship = MakeShip<TestShip>("desc", Definition());
		OO_CHECK((ship != nullptr ? ship->setUpFromDictionary(oo::PList(oo::PList::Dict{ { "name", oo::PList(std::string("Viper")) } })) : false));
		OO_CHECK((ship != nullptr ? ship->shortDescriptionComponents() : std::optional<std::string>()) == std::optional<std::string>("\"Viper\""));
		const std::optional<std::string> desc = (ship != nullptr ? ship->descriptionComponents() : std::optional<std::string>());
		OO_CHECK(desc.has_value() && desc->rfind("\"Viper\" ", 0) == 0);
	}
}


// The subentity lists, the ship / flasher / exhaust filters, and the subentity taking damage.
OO_TEST(subEntityLists)
{
	{
		SetUp();
		TestShip *ship = MakeShip<TestShip>("mother", Definition());
		TestShip *sub = MakeShip<TestShip>("sub", Definition());
		OO_CHECK((ship != nullptr ? ship->subEntityCount() : 0) == 0 && (ship != nullptr ? ship->getSubEntities() : std::vector<oo::EntityHold>()).empty());
		if (ship != nullptr)  ship->addSubEntity(sub);
		OO_CHECK((ship != nullptr ? ship->subEntityCount() : 0) == 1 && (ship != nullptr ? ship->hasSubEntity(sub) : false));
		OO_CHECK((ship != nullptr ? ship->getSubEntities() : std::vector<oo::EntityHold>()).size() == 1 && (ship != nullptr ? ship->getSubEntities() : std::vector<oo::EntityHold>())[0].get() == sub);
		OO_CHECK((ship != nullptr ? ship->subEntityEnumerator() : std::vector<oo::EntityHold>()).size() == 1);
		OO_CHECK((ship != nullptr ? ship->shipSubEntities() : std::vector<oo::EntityHold>()).size() == 1 && (ship != nullptr ? ship->shipSubEntities() : std::vector<oo::EntityHold>())[0].get() == sub);
		OO_CHECK((ship != nullptr ? ship->flasherEnumerator() : std::vector<oo::EntityHold>()).empty() && (ship != nullptr ? ship->exhausts() : std::vector<oo::EntityHold>()).empty());
		if (ship != nullptr)  ship->setSubEntityTakingDamage(sub);
		OO_CHECK((ship != nullptr ? ship->subEntityTakingDamage() : (::ShipEntity *)nil) == sub);
		if (ship != nullptr)  ship->setSubEntityTakingDamage(ship);	// not a subentity: refused (debug builds)
#ifndef NDEBUG
		OO_CHECK((ship != nullptr ? ship->subEntityTakingDamage() : (::ShipEntity *)nil) == nil);
#endif
		if (ship != nullptr)  ship->clearSubEntities();
		OO_CHECK((ship != nullptr ? ship->subEntityCount() : 0) == 0 && (sub != nullptr ? sub->owner() : nullptr) == nil);
	}
}


// --- Slice 5: bounding boxes, octree hit tests, universe add / remove, beacons, boulders (oo-ddnn8)

OO_TEST(octreeAndTractorWithoutAModel)
{
	{
		SetUp();
		TestShip *ship = MakeShip<TestShip>("nomodel", Definition());
		OO_CHECK((ship != nullptr ? ship->setUpFromDictionary(oo::PList(oo::PList::Dict{ { "scoop_position", oo::PList(std::string("0 0 10")) } })) : false));
		OO_CHECK(ship->getOctree() == nullptr && (ship != nullptr ? ship->volume() : 0.0f) == 0.0f);
		OO_CHECK((ship != nullptr ? ship->doesHitLine(kZeroHPVector, make_HPvector(0, 0, 100)) : 0.0f) == 0.0f);
		if (ship != nullptr)  ship->setPosition(make_HPvector(1, 2, 3));
		if (ship != nullptr)  ship->setOrientation(kIdentityQuaternion);
		HPVector tractor = (ship != nullptr ? ship->absoluteTractorPosition() : HPVector{});
		OO_CHECK(tractor.x == 1 && tractor.y == 2 && tractor.z == 13);
	}
}


OO_TEST(beacons)
{
	{
		SetUp();
		TestShip *ship = MakeShip<TestShip>("beacon", Definition());
		TestShip *other = MakeShip<TestShip>("other", Definition());
		OO_CHECK(!(ship != nullptr ? ship->isBeacon() : false) && (ship != nullptr ? ship->beaconCode() : std::optional<std::string>()) == std::nullopt && (ship != nullptr ? ship->beaconLabel() : std::optional<std::string>()) == std::nullopt);
		if (ship != nullptr)  ship->setBeaconCode(std::string());	// empty is none
		OO_CHECK(!(ship != nullptr ? ship->isBeacon() : false));
		if (ship != nullptr)  ship->setBeaconCode(std::string("X"));
		OO_CHECK((ship != nullptr ? ship->isBeacon() : false) && (ship != nullptr ? ship->beaconCode() : std::optional<std::string>()) == std::optional<std::string>("X"));
		OO_CHECK((ship != nullptr ? ship->beaconLabel() : std::optional<std::string>()) == std::optional<std::string>("X"));	// the label defaults to the code
		if (ship != nullptr)  ship->setBeaconLabel(std::string());
		OO_CHECK((ship != nullptr ? ship->beaconLabel() : std::optional<std::string>()) == std::nullopt);
		if (ship != nullptr)  ship->setBeaconCode(std::nullopt);
		OO_CHECK(!(ship != nullptr ? ship->isBeacon() : false));

		OO_CHECK((ship != nullptr ? ship->nextBeacon() : (Entity *)nullptr) == nil && (ship != nullptr ? ship->prevBeacon() : (Entity *)nullptr) == nil);
		if (ship != nullptr)  ship->setNextBeacon(other);
		if (ship != nullptr)  ship->setPrevBeacon(other);
		OO_CHECK((ship != nullptr ? ship->nextBeacon() : (Entity *)nullptr) == other && (ship != nullptr ? ship->prevBeacon() : (Entity *)nullptr) == other);
		if (ship != nullptr)  ship->setNextBeacon(nullptr);
		OO_CHECK((ship != nullptr ? ship->nextBeacon() : (Entity *)nullptr) == nil && (ship != nullptr ? ship->prevBeacon() : (Entity *)nullptr) == other);
	}
}


OO_TEST(visibilityBouldersAndKills)
{
	{
		SetUp();
		TestShip *ship = MakeShip<TestShip>("rock", Definition());
		OO_CHECK((ship != nullptr ? ship->setUpFromDictionary(oo::PList()) : false));
		MutablePart(ship)->no_draw_distance = 100.0f;
		MutablePart(ship)->cam_zero_distance = 50.0f;
		OO_CHECK((ship != nullptr ? ship->isVisible() : false));
		MutablePart(ship)->cam_zero_distance = 150.0f;
		OO_CHECK(!(ship != nullptr ? ship->isVisible() : false));

		OO_CHECK(!(ship != nullptr ? ship->isBoulder() : false) && !(ship != nullptr ? ship->isMinable() : false));
		if (ship != nullptr)  ship->setIsBoulder(YES);
		OO_CHECK((ship != nullptr ? ship->isBoulder() : false) && (ship != nullptr ? ship->isMinable() : false));
		MutablePart(ship)->noRocks = 1;
		OO_CHECK(!(ship != nullptr ? ship->isMinable() : false));
		if (ship != nullptr)  ship->setIsBoulder(NO);
		OO_CHECK(!(ship != nullptr ? ship->isBoulder() : false));

		OO_CHECK((ship != nullptr ? ship->countsAsKill() : false));
		OO_CHECK((ship != nullptr ? ship->setUpFromDictionary(oo::PList(oo::PList::Dict{ { "counts_as_kill", oo::PList(false) } })) : false));
		OO_CHECK(!(ship != nullptr ? ship->countsAsKill() : false));
	}
}


// --- Slice 6: ship data key, weapon offsets, collision checks, subentity geometry (oo-5z5wd) --------

OO_TEST(shipDataKeyAndInfo)
{
	{
		SetUp();
		TestShip *ship = MakeShip<TestShip>("keyed", Definition());
		OO_CHECK((ship != nullptr ? ship->shipDataKey() : std::optional<std::string>()) == std::optional<std::string>("keyed"));
		OO_CHECK((ship != nullptr ? ship->shipDataKeyAutoRole() : std::optional<std::string>()) == std::optional<std::string>("[keyed]"));
		if (ship != nullptr)  ship->setShipDataKey(std::nullopt);
		OO_CHECK((ship != nullptr ? ship->shipDataKey() : std::optional<std::string>()) == std::nullopt && (ship != nullptr ? ship->shipDataKeyAutoRole() : std::optional<std::string>()) == std::optional<std::string>("[(null)]"));
		OO_CHECK((ship != nullptr ? ship->shipInfoDictionary() : oo::PList()).isNull());	// the test ship's set-up kept none
		OO_CHECK((ship != nullptr ? ship->setUpFromDictionary(oo::PList(oo::PList::Dict{ { "frangible", oo::PList(false) }, { "model_scale_factor", oo::PList(2.0) }, { "weapon_position_aft", oo::PList(std::string("0 0 -5")) }, })) : false));
		OO_CHECK((ship != nullptr ? ship->shipInfoDictionary() : oo::PList()).get<bool>("frangible", true) == false);
		OO_CHECK(!(ship != nullptr ? ship->getIsFrangible() : false));
		OO_CHECK((ship != nullptr ? ship->getAftWeaponOffset() : std::vector<Vector>()).size() == 1 && vector_equal((ship != nullptr ? ship->getAftWeaponOffset() : std::vector<Vector>())[0], make_vector(0, 0, -10)));
		OO_CHECK((ship != nullptr ? ship->getForwardWeaponOffset() : std::vector<Vector>()).size() == 1 && vector_equal((ship != nullptr ? ship->getForwardWeaponOffset() : std::vector<Vector>())[0], kZeroVector));
		OO_CHECK((ship != nullptr ? ship->getPortWeaponOffset() : std::vector<Vector>()).size() == 1 && (ship != nullptr ? ship->getStarboardWeaponOffset() : std::vector<Vector>()).size() == 1);

		// The modes: "single" is one scaled vector; otherwise an array of them, or one zero vector.
		const oo::PList mounts(oo::PList::Dict{ { "k", oo::PList(oo::PList::Array{ oo::PList(std::string("1 0 0")), oo::PList(std::string("0 1 0")) }) } });
		const std::vector<Vector> multi = (ship != nullptr ? ship->weaponOffsetsFrom(mounts, "k", "multiply") : std::vector<Vector>());
		OO_CHECK(multi.size() == 2 && vector_equal(multi[1], make_vector(0, 2, 0)));
		const std::vector<Vector> none = (ship != nullptr ? ship->weaponOffsetsFrom(mounts, "absent", "multiply") : std::vector<Vector>());
		OO_CHECK(none.size() == 1 && vector_equal(none[0], kZeroVector));
	}
}


OO_TEST(scanClassAndCollisionFlags)
{
	{
		SetUp();
		TestShip *ship = MakeShip<TestShip>("flags", Definition());
		if (ship != nullptr)  ship->setScanClass(CLASS_NEUTRAL);
		OO_CHECK((ship != nullptr ? ship->getScanClass() : OOScanClass{}) == CLASS_NEUTRAL);
		MutablePart(ship)->cloaking_device_active = 1;
		OO_CHECK((ship != nullptr ? ship->getScanClass() : OOScanClass{}) == CLASS_NO_DRAW);
		MutablePart(ship)->cloaking_device_active = 0;

		OO_CHECK(!(ship != nullptr ? ship->suppressFlightNotifications() : false));
		MutablePart(ship)->suppressAegisMessages = 1;
		OO_CHECK((ship != nullptr ? ship->suppressFlightNotifications() : false));

		OO_CHECK((ship != nullptr ? ship->status() : OOEntityStatus{}) == STATUS_IN_FLIGHT && (ship != nullptr ? ship->canCollide() : false));
		MutablePart(ship)->isWreckage = 1;
		OO_CHECK(!(ship != nullptr ? ship->canCollide() : false));
		MutablePart(ship)->isWreckage = 0;
		if (ship != nullptr)  ship->setStatus(STATUS_DEAD);
		OO_CHECK(!(ship != nullptr ? ship->canCollide() : false));
		if (ship != nullptr)  ship->setStatus(STATUS_IN_FLIGHT);
		OO_CHECK((ship != nullptr ? ship->canCollide() : false));
	}
}


// -checkCloseCollisionWith: nil, an entity already colliding, a plain entity (a collision), and a
// ship (the octrees decide; with no model, no collision). -absoluteIJKForSubentity of a free ship is
// its frame.
OO_TEST(closeCollisionAndFrame)
{
	{
		SetUp();
		TestShip *ship = MakeShip<TestShip>("hull", Definition());
		TestShip *other = MakeShip<TestShip>("other", Definition());
		Entity *plain = oo::MadeEntity(oo::makeRef<Entity>());
		OO_CHECK(!(ship != nullptr ? ship->checkCloseCollisionWith(nullptr) : false));
		OO_CHECK((ship != nullptr ? ship->checkCloseCollisionWith(plain) : false) && Part(ship)->collider == plain);
		MutablePart(ship)->collider = nil;
		OO_CHECK(!(ship != nullptr ? ship->checkCloseCollisionWith(other) : false) && Part(ship)->collider == nil);

		if (ship != nullptr)  ship->setOrientation(kIdentityQuaternion);
		Triangle ijk = (ship != nullptr ? ship->absoluteIJKForSubentity() : Triangle{});
		OO_CHECK(vector_equal(ijk.v[0], kBasisXVector) && vector_equal(ijk.v[1], kBasisYVector) && vector_equal(ijk.v[2], kBasisZVector));
	}
}


// --- Slice 7: -update: (bead oo-k2q1f) -------------------------------------------------------------

// A ship whose -update: only counts: a subentity that a demo ship updates (C++ since bead oo-9ht.144).
class CountingShip : public TestShip
{
public:
	int		_updates = 0;

	void update(OOTimeDelta delta_t) override
	{
		(void)delta_t;
		_updates++;
	}
};


// A demo ship (the ship library's) turns at its demo rate, has its subentities updated, and has an
// infinite top speed clamped first.
OO_TEST(updateDemoShip)
{
	{
		SetUp();
		TestShip *ship = MakeShip<TestShip>("demo", Definition());
		CountingShip *sub = MakeShip<CountingShip>("sub", Definition());
		OO_CHECK((ship != nullptr ? ship->setUpFromDictionary(oo::PList()) : false));
		if (ship != nullptr)  ship->addSubEntity(sub);
		ShipEntityTestAccess::IsDemoShip(MutablePart(ship)) = YES;
		ShipEntityTestAccess::DemoRate(MutablePart(ship)) = 0;
		if (ship != nullptr)  ship->setMaxFlightSpeed(INFINITY);
		if (ship != nullptr)  ship->update(0.1);
		OO_CHECK((ship != nullptr ? ship->getMaxFlightSpeed() : 0.0f) == 300.0f);
		OO_CHECK(sub->_updates == 1);
		if (ship != nullptr)  ship->clearSubEntities();
	}
}


// From C++, update() reaches an Objective-C subclass's override (the root's adapter line).
OO_TEST(updateReachesTheSubclass)
{
	{
		SetUp();
		CountingShip *ship = MakeShip<CountingShip>("counted", Definition());
		Entity *part = ship;
		part->update(0.1);
		OO_CHECK(ship->_updates == 1);
	}
}


// --- Slice 8: behaviour dispatch, attack response, equipment queries (bead oo-vxdsc) ---------------

// The equipment queries over the ship's equipment keys (no equipment data is loaded, so no type is
// known: a key provides only itself).
OO_TEST(equipmentQueries)
{
	{
		SetUp();
		TestShip *ship = MakeShip<TestShip>("kit", Definition());
		OO_CHECK(!(ship != nullptr ? ship->hasEquipmentItem(oo::PList(std::string("EQ_A"))) : false));
		OO_CHECK(!(ship != nullptr ? ship->hasAllEquipment(oo::PList(std::string("EQ_A"))) : false));	// none at all
		ShipEntityTestAccess::Equipment(MutablePart(ship)) = { "EQ_A", "EQ_B_DAMAGED", "EQ_A" };
		OO_CHECK((ship != nullptr ? ship->countEquipmentItem("EQ_A") : 0) == 2 && (ship != nullptr ? ship->countEquipmentItem("EQ_B") : 0) == 0);
		OO_CHECK((ship != nullptr ? ship->hasOneEquipmentItem("EQ_A", NO, NO) : false));
		OO_CHECK(!(ship != nullptr ? ship->hasOneEquipmentItem("EQ_B", NO, NO) : false));
		OO_CHECK((ship != nullptr ? ship->hasOneEquipmentItem("EQ_B", NO, YES) : false));	// damaged counts while loading
		OO_CHECK((ship != nullptr ? ship->hasOneEquipmentItemIncludingMissiles("EQ_B", NO, YES) : false));
		OO_CHECK(!(ship != nullptr ? ship->hasOneEquipmentItemIncludingMissiles("EQ_C", YES, NO) : false));
		OO_CHECK((ship != nullptr ? ship->hasEquipmentItem(oo::PList(std::string("EQ_A"))) : false));
		OO_CHECK((ship != nullptr ? ship->hasEquipmentItem(oo::PList(oo::PList::Array{ oo::PList(std::string("EQ_X")), oo::PList(std::string("EQ_A")) })) : false));
		OO_CHECK(!(ship != nullptr ? ship->hasEquipmentItem(oo::PList(oo::PList::Array{ oo::PList(std::string("EQ_X")), oo::PList(1) })) : false));
		OO_CHECK((ship != nullptr ? ship->hasAllEquipment(oo::PList(oo::PList::Array{ oo::PList(std::string("EQ_A")) })) : false));
		OO_CHECK(!(ship != nullptr ? ship->hasAllEquipment(oo::PList(oo::PList::Array{ oo::PList(std::string("EQ_A")), oo::PList(std::string("EQ_B")) })) : false));
		OO_CHECK((ship != nullptr ? ship->hasAllEquipment(oo::PList(oo::PList::Array{ oo::PList(std::string("EQ_A")), oo::PList(std::string("EQ_B")) }), NO, YES) : false));
		OO_CHECK(!(ship != nullptr ? ship->hasAllEquipment(oo::PList(oo::PList::Array{ oo::PList(std::string("EQ_A")), oo::PList(2) })) : false));
		OO_CHECK((ship != nullptr ? ship->hasEquipmentItemProviding("EQ_A") : false) && !(ship != nullptr ? ship->hasEquipmentItemProviding("EQ_Z") : false));
		OO_CHECK((ship != nullptr ? ship->equipmentItemProviding("EQ_A") : std::optional<std::string>()) == std::optional<std::string>("EQ_A"));
		OO_CHECK((ship != nullptr ? ship->equipmentItemProviding("EQ_Z") : std::optional<std::string>()) == std::nullopt);
		OO_CHECK(!(ship != nullptr ? ship->hasPrimaryWeapon(nullptr) : false));
	}
}


OO_TEST(hyperspaceMotor)
{
	{
		SetUp();
		TestShip *ship = MakeShip<TestShip>("motor", Definition());
		if (ship != nullptr)  ship->setHyperspaceSpinTime(12.0f);
		OO_CHECK((ship != nullptr ? ship->hyperspaceSpinTime() : 0.0f) == 12.0f && (ship != nullptr ? ship->hasHyperspaceMotor() : false));
		if (ship != nullptr)  ship->setHyperspaceSpinTime(-1.0f);
		OO_CHECK(!(ship != nullptr ? ship->hasHyperspaceMotor() : false));
	}
}


// --- Slice 9: equipment validity and adding, weapon mounts, scripting lists (bead oo-ke13m) ---------

OO_TEST(weaponMountsAndLists)
{
	{
		SetUp();
		TestShip *ship = MakeShip<TestShip>("mounts", Definition());
		OO_CHECK((ship != nullptr ? ship->setUpFromDictionary(oo::PList(oo::PList::Dict{ { "weapon_facings", oo::PList(WEAPON_FACING_FORWARD | WEAPON_FACING_AFT) } })) : false));
		OO_CHECK((ship != nullptr ? ship->weaponFacings() : OOWeaponFacingSet{}) == (WEAPON_FACING_FORWARD | WEAPON_FACING_AFT));
		// No weapon data is loaded: every mount is empty, and a facing the ship lacks has nothing.
		OO_CHECK(isWeaponNone((ship != nullptr ? ship->weaponTypeIDForFacing(WEAPON_FACING_FORWARD, YES) : OOWeaponType{})));
		OO_CHECK((ship != nullptr ? ship->weaponTypeIDForFacing(WEAPON_FACING_PORT, NO) : OOWeaponType{}) == nil);
		OO_CHECK((ship != nullptr ? ship->weaponTypeForFacing(WEAPON_FACING_STARBOARD, NO) : (OOEquipmentType *)nullptr) == nil);
		OO_CHECK((ship != nullptr ? ship->missilesList() : std::vector<oo::Ref<OOEquipmentType>>()).empty());
		const oo::PList passengers = (ship != nullptr ? ship->passengerListForScripting() : oo::PList());
		OO_CHECK(passengers.isArray() && passengers.count() == 0);
		OO_CHECK((ship != nullptr ? ship->parcelListForScripting() : oo::PList()).isArray() && (ship != nullptr ? ship->contractListForScripting() : oo::PList()).isArray());
	}
}


OO_TEST(equipmentKeysAndUnknownEquipment)
{
	{
		SetUp();
		TestShip *ship = MakeShip<TestShip>("keys", Definition());
		OO_CHECK((ship != nullptr ? ship->equipmentKeys() : std::vector<std::string>()).empty() && (ship != nullptr ? ship->equipmentCount() : 0) == 0);
		ShipEntityTestAccess::Equipment(MutablePart(ship)) = { "EQ_A", "EQ_B" };
		OO_CHECK((ship != nullptr ? ship->equipmentKeys() : std::vector<std::string>()) == std::vector<std::string>({ "EQ_A", "EQ_B" }) && (ship != nullptr ? ship->equipmentCount() : 0) == 2);
		// An equipment key with no equipment type is never valid, and is not added.
		OO_CHECK(!(ship != nullptr ? ship->equipmentValidToAdd("EQ_UNKNOWN", "npc") : false));
		OO_CHECK(!(ship != nullptr ? ship->canAddEquipment("EQ_UNKNOWN", "npc") : false));
		OO_CHECK(!(ship != nullptr ? ship->addEquipmentItem("EQ_UNKNOWN", "npc") : false));
		OO_CHECK((ship != nullptr ? ship->equipmentCount() : 0) == 2);
	}
}


// --- Slice 10: equipment removal, missiles, capacities, has-equipment predicates, shields (oo-wvcs2)

OO_TEST(capacitiesAndPredicates)
{
	{
		SetUp();
		TestShip *ship = MakeShip<TestShip>("preds", Definition());
		OO_CHECK((ship != nullptr ? ship->setUpFromDictionary(oo::PList(oo::PList::Dict{ { "missiles", oo::PList(2) }, { "max_missiles", oo::PList(4) }, { "extra_cargo", oo::PList(7) } })) : false));
		OO_CHECK((ship != nullptr ? ship->missileCount() : 0) == 2 && (ship != nullptr ? ship->missileCapacity() : 0) == 4 && (ship != nullptr ? ship->extraCargo() : 0) == 7);
		OO_CHECK((ship != nullptr ? ship->parcelCount() : 0) == 0 && (ship != nullptr ? ship->passengerCount() : 0) == 0 && (ship != nullptr ? ship->passengerCapacity() : 0) == 0);
		OO_CHECK((ship != nullptr ? ship->maxHyperspaceDistance() : 0.0) == MAX_JUMP_RANGE);

		OO_CHECK(!(ship != nullptr ? ship->hasScoop() : false) && !(ship != nullptr ? ship->hasECM() : false) && !(ship != nullptr ? ship->hasShieldBooster() : false) && !(ship != nullptr ? ship->hasEscapePod() : false));
		OO_CHECK((ship != nullptr ? ship->shieldBoostFactor() : 0.0f) == 1.0f && (ship != nullptr ? ship->shieldRechargeRate() : 0.0f) == 2.0f);
		OO_CHECK((ship != nullptr ? ship->maxForwardShieldLevel() : 0.0f) == BASELINE_SHIELD_LEVEL && (ship != nullptr ? ship->maxAftShieldLevel() : 0.0f) == BASELINE_SHIELD_LEVEL);

		// Each predicate is "some equipment provides the key" (a key provides itself).
		ShipEntityTestAccess::Equipment(MutablePart(ship)) = { "EQ_FUEL_SCOOPS", "EQ_ECM", "EQ_SHIELD_BOOSTER", "EQ_NAVAL_SHIELD_BOOSTER",
			"EQ_CLOAKING_DEVICE", "EQ_MILITARY_SCANNER_FILTER", "EQ_MILITARY_JAMMER", "EQ_CARGO_BAY", "EQ_HEAT_SHIELD",
			"EQ_FUEL_INJECTION", "EQ_QC_MINE", "EQ_ESCAPE_POD", "EQ_DOCK_COMP", "EQ_GAL_DRIVE" };
		OO_CHECK((ship != nullptr ? ship->hasScoop() : false) && (ship != nullptr ? ship->hasFuelScoop() : false) && !(ship != nullptr ? ship->hasCargoScoop() : false));
		OO_CHECK((ship != nullptr ? ship->hasECM() : false) && (ship != nullptr ? ship->hasCloakingDevice() : false) && (ship != nullptr ? ship->hasMilitaryScannerFilter() : false) && (ship != nullptr ? ship->hasMilitaryJammer() : false));
		OO_CHECK((ship != nullptr ? ship->hasExpandedCargoBay() : false) && (ship != nullptr ? ship->hasShieldBooster() : false) && (ship != nullptr ? ship->hasMilitaryShieldEnhancer() : false));
		OO_CHECK((ship != nullptr ? ship->hasHeatShield() : false) && (ship != nullptr ? ship->hasFuelInjection() : false) && (ship != nullptr ? ship->hasEscapePod() : false) && (ship != nullptr ? ship->hasCascadeMine() : false));
		OO_CHECK((ship != nullptr ? ship->hasDockingComputer() : false) && (ship != nullptr ? ship->hasGalacticHyperdrive() : false));
		OO_CHECK((ship != nullptr ? ship->shieldBoostFactor() : 0.0f) == 3.0f && (ship != nullptr ? ship->shieldRechargeRate() : 0.0f) == 3.0f);
		OO_CHECK((ship != nullptr ? ship->maxForwardShieldLevel() : 0.0f) == BASELINE_SHIELD_LEVEL * 3.0f);

		// An unknown equipment type is not removed; -removeAllEquipment clears the keys.
		if (ship != nullptr)  ship->removeEquipmentItem("EQ_ECM");
		OO_CHECK((ship != nullptr ? ship->hasECM() : false));
		if (ship != nullptr)  ship->removeAllEquipment();
		OO_CHECK((ship != nullptr ? ship->equipmentCount() : 0) == 0 && !(ship != nullptr ? ship->hasECM() : false));
	}
}


OO_TEST(removeMissiles)
{
	{
		SetUp();
		TestShip *ship = MakeShip<TestShip>("launcher", Definition());
		OO_CHECK((ship != nullptr ? ship->removeMissiles() : 0) == 0 && (ship != nullptr ? ship->missileCount() : 0) == 0);
	}
}


// --- Slice 11: thrust and afterburner; idle, tumble, tractored, track, intercept, dogfight (oo-eh955)

OO_TEST(thrustAndAfterburner)
{
	{
		SetUp();
		TestShip *ship = MakeShip<TestShip>("burner", Definition());
		if (ship != nullptr)  ship->setAfterburnerFactor(4.0f);
		if (ship != nullptr)  ship->setAfterburnerRate(0.5f);
		if (ship != nullptr)  ship->setMaxThrust(30.0f);
		OO_CHECK((ship != nullptr ? ship->afterburnerFactor() : 0.0f) == 4.0f && (ship != nullptr ? ship->afterburnerRate() : 0.0f) == 0.5f && (ship != nullptr ? ship->maxThrust() : 0.0f) == 30.0f);
		OO_CHECK((ship != nullptr ? ship->getThrust() : 0.0f) == 0.0f);	// the thrust itself is the set-up's, not -setMaxThrust:'s
	}
}


// -behaviour_stop_still: and -behaviour_idle: centre the sticks (a buoy keeps rolling), and the
// sticks move the flight controls at their rate (-applySticks:).
OO_TEST(behaviourStopStillAndIdle)
{
	{
		SetUp();
		TestShip *ship = MakeShip<TestShip>("still", Definition());
		MutablePart(ship)->flightRoll = 1.0f;
		MutablePart(ship)->stick_roll = 1.0f;
		MutablePart(ship)->stick_pitch = 1.0f;
		if (ship != nullptr)  ship->behaviour_stop_still(0.1);
		OO_CHECK(Part(ship)->stick_roll == 0 && Part(ship)->stick_pitch == 0 && Part(ship)->stick_yaw == 0);
		OO_CHECK(fabs(Part(ship)->flightRoll - 0.8f) < 1e-5f);

		if (ship != nullptr)  ship->setScanClass(CLASS_BUOY);
		MutablePart(ship)->flightRoll = 0.5f;
		MutablePart(ship)->flightPitch = 0.25f;
		if (ship != nullptr)  ship->behaviour_idle(0.1);
		OO_CHECK(Part(ship)->stick_roll == 0.5f && Part(ship)->stick_pitch == 0.25f && Part(ship)->stick_yaw == 0);
		OO_CHECK(Part(ship)->flightRoll == 0.5f && Part(ship)->flightPitch == 0.25f);

		if (ship != nullptr)  ship->setScanClass(CLASS_NEUTRAL);
		if (ship != nullptr)  ship->behaviour_idle(0.1);
		OO_CHECK(Part(ship)->stick_roll == 0 && Part(ship)->stick_pitch == 0);

		MutablePart(ship)->stick_roll = 0.5f;
		MutablePart(ship)->flightRoll = 0.0f;
		if (ship != nullptr)  ship->behaviour_tumble(0.1);	// the sticks as they are
		OO_CHECK(Part(ship)->stick_roll == 0.5f && fabs(Part(ship)->flightRoll - 0.2f) < 1e-5f);
	}
}


// Behaviours that need a target, with none: the ship notes the lost target and goes idle.
OO_TEST(behavioursWithoutATarget)
{
	{
		SetUp();
		TestShip *ship = MakeShip<TestShip>("hunter", Definition());
		MutablePart(ship)->behaviour = BEHAVIOUR_ATTACK_SLOW_DOGFIGHT;
		if (ship != nullptr)  ship->behaviour_attack_slow_dogfight(0.1);
		OO_CHECK(Part(ship)->behaviour == BEHAVIOUR_IDLE);
		MutablePart(ship)->behaviour = BEHAVIOUR_ATTACK_BREAK_OFF_TARGET;
		if (ship != nullptr)  ship->behaviour_attack_break_off_target(0.1);
		OO_CHECK(Part(ship)->behaviour == BEHAVIOUR_IDLE);
	}
}


// --- Slice 12: behaviours: attack target, broadside, close with target (bead oo-0akes) --------------

// With no target the attack behaviours note the lost target and go idle.
OO_TEST(attackBehavioursWithoutATarget)
{
	{
		SetUp();
		TestShip *ship = MakeShip<TestShip>("attacker", Definition());
		MutablePart(ship)->behaviour = BEHAVIOUR_ATTACK_BROADSIDE;
		if (ship != nullptr)  ship->behaviour_attack_broadside(0.1);
		OO_CHECK(Part(ship)->behaviour == BEHAVIOUR_IDLE);
		MutablePart(ship)->behaviour = BEHAVIOUR_ATTACK_BROADSIDE_LEFT;
		if (ship != nullptr)  ship->behaviour_attack_broadside_left(0.1);
		OO_CHECK(Part(ship)->behaviour == BEHAVIOUR_IDLE);
		MutablePart(ship)->behaviour = BEHAVIOUR_ATTACK_BROADSIDE_RIGHT;
		if (ship != nullptr)  ship->behaviour_attack_broadside_right(0.1);
		OO_CHECK(Part(ship)->behaviour == BEHAVIOUR_IDLE);
		MutablePart(ship)->behaviour = BEHAVIOUR_CLOSE_TO_BROADSIDE_RANGE;
		if (ship != nullptr)  ship->behaviour_close_to_broadside_range(0.1);
		OO_CHECK(Part(ship)->behaviour == BEHAVIOUR_IDLE);
		MutablePart(ship)->behaviour = BEHAVIOUR_CLOSE_WITH_TARGET;
		if (ship != nullptr)  ship->behaviour_close_with_target(0.1);
		OO_CHECK(Part(ship)->behaviour == BEHAVIOUR_IDLE);
	}
}


// -behaviour_attack_target: chooses the next attack behaviour: an unarmed ship (no weapon on any
// mount or subentity) flies from its target, and the choice resets the ship's frustration. The
// broadside on either side, with no target, notes the lost target and goes idle.
OO_TEST(attackTargetChoiceAndBroadsideSides)
{
	{
		SetUp();
		TestShip *ship = MakeShip<TestShip>("unarmed", Definition());
		MutablePart(ship)->behaviour = BEHAVIOUR_ATTACK_TARGET;
		MutablePart(ship)->frustration = 5.0f;
		if (ship != nullptr)  ship->behaviour_attack_target(0.1);
		OO_CHECK(Part(ship)->behaviour == BEHAVIOUR_ATTACK_FLY_FROM_TARGET);
		OO_CHECK(Part(ship)->frustration == 0.0f);

		MutablePart(ship)->behaviour = BEHAVIOUR_ATTACK_BROADSIDE_LEFT;
		if (ship != nullptr)  ship->behaviour_attack_broadside_target(0.1, YES);
		OO_CHECK(Part(ship)->behaviour == BEHAVIOUR_IDLE);
		MutablePart(ship)->behaviour = BEHAVIOUR_ATTACK_BROADSIDE_RIGHT;
		if (ship != nullptr)  ship->behaviour_attack_broadside_target(0.1, NO);
		OO_CHECK(Part(ship)->behaviour == BEHAVIOUR_IDLE);
	}
}


// --- Slices 13-15: the behaviours (the expectations were run on the Objective-C methods first) ----

namespace {

// A ship in flight at the origin, with a top speed and a scanner, and nothing else.
TestShip *FlyingShip(const char *key)
{
	TestShip *ship = MakeShip<TestShip>(key, Definition());
	if (ship != nullptr)  ship->setMaxFlightSpeed(200);
	if (ship != nullptr)  ship->setScannerRange(25600);
	if (ship != nullptr)  ship->setPosition(kZeroHPVector);
	return ship;
}


// A ship the first one targets, at (0, 0, z).
// (Not -addTarget:, which tells the ship's scripts, and a ship has no JavaScript object here.)
TestShip *TargetAt(TestShip *ship, double z)
{
	TestShip *target = FlyingShip("target");
	if (target != nullptr)  target->setPosition(make_HPvector(0, 0, z));
	SetPrimaryTarget(ship, target);
	return target;
}

}	// namespace


// Slices 13 and 14: an attack behaviour with no target to track notes the lost target and goes idle.
OO_TEST(attackBehavioursWithoutATargetGoIdle)
{
	{
		SetUp();
		const struct { OOBehaviour behaviour; void (*run)(TestShip *); } cases[] =
		{
			{ BEHAVIOUR_ATTACK_SNIPER, [](TestShip *s) { if (s != nullptr)  s->behaviour_attack_sniper(0.1); } },
			{ BEHAVIOUR_ATTACK_FLY_TO_TARGET_SIX, [](TestShip *s) { if (s != nullptr)  s->behaviour_fly_to_target_six(0.1); } },
			{ BEHAVIOUR_ATTACK_MINING_TARGET, [](TestShip *s) { if (s != nullptr)  s->behaviour_attack_mining_target(0.1); } },
			{ BEHAVIOUR_ATTACK_FLY_TO_TARGET, [](TestShip *s) { if (s != nullptr)  s->behaviour_attack_fly_to_target(0.1); } },
			{ BEHAVIOUR_ATTACK_FLY_FROM_TARGET, [](TestShip *s) { if (s != nullptr)  s->behaviour_attack_fly_from_target(0.1); } },
			{ BEHAVIOUR_RUNNING_DEFENSE, [](TestShip *s) { if (s != nullptr)  s->behaviour_running_defense(0.1); } },
			{ BEHAVIOUR_FLEE_TARGET, [](TestShip *s) { if (s != nullptr)  s->behaviour_flee_target(0.1); } },
		};
		for (const auto &c : cases)
		{
			TestShip *ship = FlyingShip("lonely");
			if (ship != nullptr)  ship->setBehaviour(c.behaviour);
			SetFrustration(ship, 2);
			c.run(ship);
			OO_CHECK(Behaviour(ship) == BEHAVIOUR_IDLE && (ship != nullptr ? ship->getFrustration() : 0.0) == 0);
		}

		// The miner also slows to three eighths of its top speed.
		TestShip *miner = FlyingShip("miner");
		if (miner != nullptr)  miner->behaviour_attack_mining_target(0.1);
		OO_CHECK((miner != nullptr ? miner->desiredSpeed() : 0.0) == 200 * 0.375);
	}
}


// Slice 13: the sniper closes in to attack inside 15 km, and outside it flies at top speed while
// out of weapon range.
OO_TEST(sniper)
{
	{
		SetUp();
		TestShip *ship = FlyingShip("sniper");
		TargetAt(ship, 1000);
		if (ship != nullptr)  ship->setBehaviour(BEHAVIOUR_ATTACK_SNIPER);
		if (ship != nullptr)  ship->behaviour_attack_sniper(0.1);
		OO_CHECK(Behaviour(ship) == BEHAVIOUR_ATTACK_TARGET);

		TestShip *distant = FlyingShip("distant sniper");
		TargetAt(distant, 20000);
		if (distant != nullptr)  distant->setBehaviour(BEHAVIOUR_ATTACK_SNIPER);
		if (distant != nullptr)  distant->behaviour_attack_sniper(0.1);
		OO_CHECK(Behaviour(distant) == BEHAVIOUR_ATTACK_SNIPER && (distant != nullptr ? distant->desiredSpeed() : 0.0) == 200);
	}
}


// Slice 13: a ship already at the point it was heading for vectors in to attack at 0.4 of its top
// speed (the target is at a standstill); the miner closes on a rock at seven eighths of it; and an
// attacker inside its weapon range starts its attack run.
OO_TEST(attackApproaches)
{
	{
		SetUp();
		TestShip *six = FlyingShip("six");
		TargetAt(six, 2000);
		if (six != nullptr)  six->setBehaviour(BEHAVIOUR_ATTACK_FLY_TO_TARGET_SIX);
		if (six != nullptr)  six->behaviour_fly_to_target_six(0.1);
		OO_CHECK(Behaviour(six) == BEHAVIOUR_ATTACK_FLY_TO_TARGET && (six != nullptr ? six->desiredSpeed() : 0.0) == 200 * 0.4);

		TestShip *miner = FlyingShip("miner");
		TargetAt(miner, 2000);
		if (miner != nullptr)  miner->setBehaviour(BEHAVIOUR_ATTACK_MINING_TARGET);
		if (miner != nullptr)  miner->behaviour_attack_mining_target(0.1);
		OO_CHECK(Behaviour(miner) == BEHAVIOUR_ATTACK_MINING_TARGET && (miner != nullptr ? miner->desiredSpeed() : 0.0) == 200 * 0.875);

		TestShip *attacker = FlyingShip("attacker");
		TargetAt(attacker, 1000);
		if (attacker != nullptr)  attacker->setWeaponRange(30000);
		if (attacker != nullptr)  attacker->setBehaviour(BEHAVIOUR_ATTACK_FLY_TO_TARGET);
		if (attacker != nullptr)  attacker->behaviour_attack_fly_to_target(0.1);
		OO_CHECK(Behaviour(attacker) == BEHAVIOUR_ATTACK_TARGET);
	}
}


// Slice 14: the destination behaviours that only decide.
OO_TEST(destinationDecisions)
{
	{
		SetUp();
		// Inside the range it should keep: fly away from the destination, at least at top speed.
		TestShip *ship = FlyingShip("ranger");
		if (ship != nullptr)  ship->setDestination(make_HPvector(0, 0, 100));
		if (ship != nullptr)  ship->setDesiredRange(500);
		if (ship != nullptr)  ship->setDesiredSpeed(10);
		SetFrustration(ship, 3);
		if (ship != nullptr)  ship->behaviour_fly_range_from_destination(0.1);
		OO_CHECK(Behaviour(ship) == BEHAVIOUR_FLY_FROM_DESTINATION && (ship != nullptr ? ship->desiredSpeed() : 0.0) == 200 && (ship != nullptr ? ship->getFrustration() : 0.0) == 0);

		// Outside it: fly to the destination.
		if (ship != nullptr)  ship->setDesiredRange(50);
		if (ship != nullptr)  ship->behaviour_fly_range_from_destination(0.1);
		OO_CHECK(Behaviour(ship) == BEHAVIOUR_FLY_TO_DESTINATION);

		// Facing a destination stops the ship.
		TestShip *facer = FlyingShip("facer");
		if (facer != nullptr)  facer->setDestination(make_HPvector(0, 1000, 0));
		if (facer != nullptr)  facer->setDesiredSpeed(50);
		if (facer != nullptr)  facer->setBehaviour(BEHAVIOUR_FACE_DESTINATION);
		if (facer != nullptr)  facer->behaviour_face_destination(0.1);
		OO_CHECK((facer != nullptr ? facer->desiredSpeed() : 0.0) == 0);

		// Landing with no planet to land on: idle, and the JS AI is woken to reconsider.
		TestShip *lander = FlyingShip("lander");
		SetPlanetForLanding(lander, NO_TARGET);
		if (lander != nullptr)  lander->setBehaviour(BEHAVIOUR_LAND_ON_PLANET);
		if (lander != nullptr)  lander->behaviour_land_on_planet(0.1);
		OO_CHECK(Behaviour(lander) == BEHAVIOUR_IDLE && (lander != nullptr ? lander->shipAIScriptWakeTime() : OOTimeAbsolute{}) == 1 && (lander != nullptr ? lander->desiredSpeed() : 0.0) == 0);

		// Forming up with no leader: top speed.
		TestShip *escort = FlyingShip("escort");
		if (escort != nullptr)  escort->setDestination(make_HPvector(0, 0, 3000));
		if (escort != nullptr)  escort->setBehaviour(BEHAVIOUR_FORMATION_FORM_UP);
		if (escort != nullptr)  escort->behaviour_formation_form_up(0.1);
		OO_CHECK((escort != nullptr ? escort->desiredSpeed() : 0.0) == 200);
	}
}


// Slice 15: arriving, leaving, resuming after a proximity alert, and the navpoints.
OO_TEST(destinationArrivals)
{
	{
		SetUp();
		TestShip *ship = FlyingShip("arriving");
		if (ship != nullptr)  ship->setDestination(make_HPvector(0, 0, 10));
		if (ship != nullptr)  ship->setDesiredRange(100);
		if (ship != nullptr)  ship->setDesiredSpeed(50);
		SetFrustration(ship, 3);
		if (ship != nullptr)  ship->setBehaviour(BEHAVIOUR_FLY_TO_DESTINATION);
		if (ship != nullptr)  ship->behaviour_fly_to_destination(0.1);
		OO_CHECK(Behaviour(ship) == BEHAVIOUR_IDLE && (ship != nullptr ? ship->desiredSpeed() : 0.0) == 0 && (ship != nullptr ? ship->getFrustration() : 0.0) == 0);

		TestShip *leaving = FlyingShip("leaving");
		if (leaving != nullptr)  leaving->setDestination(make_HPvector(0, 0, 1000));
		if (leaving != nullptr)  leaving->setDesiredRange(100);
		if (leaving != nullptr)  leaving->setDesiredSpeed(50);
		if (leaving != nullptr)  leaving->setBehaviour(BEHAVIOUR_FLY_FROM_DESTINATION);
		if (leaving != nullptr)  leaving->behaviour_fly_from_destination(0.1);
		OO_CHECK(Behaviour(leaving) == BEHAVIOUR_IDLE && (leaving != nullptr ? leaving->desiredSpeed() : 0.0) == 0);

		// Clear of the obstacle: what the ship did before the alert resumes.
		TestShip *avoider = FlyingShip("avoider");
		if (avoider != nullptr)  avoider->setDestination(make_HPvector(0, 0, 1000));
		if (avoider != nullptr)  avoider->setDesiredRange(100);
		if (avoider != nullptr)  avoider->setBehaviour(BEHAVIOUR_AVOID_COLLISION);
		SetFrustration(avoider, 3);
		SetPreviousCondition(avoider, oo::PList(oo::PList::Dict{
			{ "behaviour", oo::PList((double)BEHAVIOUR_FLY_TO_DESTINATION) },
			{ "desired_range", oo::PList(300.0) },
			{ "desired_speed", oo::PList(12.0) } }));
		if (avoider != nullptr)  avoider->behaviour_avoid_collision(0.1);
		OO_CHECK(Behaviour(avoider) == BEHAVIOUR_FLY_TO_DESTINATION && (avoider != nullptr ? avoider->desiredRange() : 0.0) == 300 && (avoider != nullptr ? avoider->desiredSpeed() : 0.0) == 12 && (avoider != nullptr ? avoider->getFrustration() : 0.0) == 0);

		// A turret with no mount and no targets does nothing.
		TestShip *turret = FlyingShip("turret");
		if (turret != nullptr)  turret->setBehaviour(BEHAVIOUR_TRACK_AS_TURRET);
		if (turret != nullptr)  turret->behaviour_track_as_turret(0.1);
		OO_CHECK(Behaviour(turret) == BEHAVIOUR_TRACK_AS_TURRET);

		// Reaching a navpoint moves on to the next; reaching the last one is the end of the route.
		TestShip *nav = FlyingShip("navigator");
		if (nav != nullptr)  nav->setDesiredRange(50);
		if (nav != nullptr)  nav->setBehaviour(BEHAVIOUR_FLY_THRU_NAVPOINTS);
		SetNavpoints(nav, { make_HPvector(0, 0, 10), make_HPvector(0, 0, 5000), make_HPvector(0, 5000, 5000) }, 0);
		if (nav != nullptr)  nav->behaviour_fly_thru_navpoints(0.1);
		OO_CHECK(NextNavpoint(nav) == 1 && Behaviour(nav) == BEHAVIOUR_FLY_THRU_NAVPOINTS);
		SetNavpoints(nav, { make_HPvector(0, 5000, 5000), make_HPvector(0, 0, 10) }, 1);
		if (nav != nullptr)  nav->behaviour_fly_thru_navpoints(0.1);
		OO_CHECK(NextNavpoint(nav) == 0 && Behaviour(nav) == BEHAVIOUR_IDLE);
	}
}


// Slice 15: a scripted AI with no ship script reverts to idle; the reaction time, and the target
// position it leads by.
OO_TEST(scriptedAIAndReactionTime)
{
	{
		SetUp();
		TestShip *ship = FlyingShip("scripted");
		if (ship != nullptr)  ship->setBehaviour(BEHAVIOUR_SCRIPTED_AI);
		if (ship != nullptr)  ship->behaviour_scripted_ai(0.1);
		OO_CHECK(Behaviour(ship) == BEHAVIOUR_IDLE);

		OO_CHECK((ship != nullptr ? ship->getReactionTime() : 0.0f) == 0);
		if (ship != nullptr)  ship->setReactionTime(0.75f);
		OO_CHECK((ship != nullptr ? ship->getReactionTime() : 0.0f) == 0.75f);

		OO_CHECK(HPvector_equal((ship != nullptr ? ship->calculateTargetPosition() : HPVector{}), kZeroHPVector));		// no target
		TestShip *hunter = FlyingShip("hunter");
		TargetAt(hunter, 1234);
		OO_CHECK(HPvector_equal((hunter != nullptr ? hunter->calculateTargetPosition() : HPVector{}), make_HPvector(0, 0, 1234)));	// no reaction time: where it is
	}
}


// Slice 16: the tracking curve through a target that is standing still is that target's position,
// with or without a reaction time.
OO_TEST(trackingCurve)
{
	{
		SetUp();
		TestShip *ship = FlyingShip("tracker");
		if (ship != nullptr)  ship->setReactionTime(0.6f);
		TargetAt(ship, 1500);
		if (ship != nullptr)  ship->startTrackingCurve();
		HPVector led = (ship != nullptr ? ship->calculateTargetPosition() : HPVector{});
		OO_CHECK(fabs(led.x) < 1e-6 && fabs(led.y) < 1e-6 && fabs(led.z - 1500) < 1e-6);
		if (ship != nullptr)  ship->updateTrackingCurve();	// too soon after the start: unchanged
		led = (ship != nullptr ? ship->calculateTargetPosition() : HPVector{});
		OO_CHECK(fabs(led.z - 1500) < 1e-6);

		if (ship != nullptr)  ship->setReactionTime(0);
		if (ship != nullptr)  ship->calculateTrackingCurve();
		OO_CHECK(HPvector_equal((ship != nullptr ? ship->calculateTargetPosition() : HPVector{}), make_HPvector(0, 0, 1500)));
	}
}


// Slice 16: the scanner colours, scripted and by scan class.
OO_TEST(scannerColours)
{
	{
		SetUp();
		TestShip *ship = FlyingShip("coloured");
		oo::Ref<OOColor>	red = OOColor::colorWithRed(1, 0, 0, 1);
		oo::Ref<OOColor>	blue = OOColor::colorWithRed(0, 0, 1, 1);
		OO_CHECK((ship != nullptr ? ship->scannerDisplayColor1() : (OOColor *)nullptr) == nil && (ship != nullptr ? ship->scannerDisplayColorHostile2() : (OOColor *)nullptr) == nil);
		if (ship != nullptr)  ship->setScannerDisplayColor1(red.get());
		if (ship != nullptr)  ship->setScannerDisplayColor2(blue.get());
		if (ship != nullptr)  ship->setScannerDisplayColorHostile1(blue.get());
		if (ship != nullptr)  ship->setScannerDisplayColorHostile2(red.get());
		OO_CHECK((ship != nullptr ? ship->scannerDisplayColor1() : (OOColor *)nullptr) == red && (ship != nullptr ? ship->scannerDisplayColor2() : (OOColor *)nullptr) == blue);
		OO_CHECK((ship != nullptr ? ship->scannerDisplayColorHostile1() : (OOColor *)nullptr) == blue && (ship != nullptr ? ship->scannerDisplayColorHostile2() : (OOColor *)nullptr) == red);
		if (ship != nullptr)  ship->setScannerDisplayColor2(nullptr);		// nil: the ship's definition's, which has none
		OO_CHECK((ship != nullptr ? ship->scannerDisplayColor2() : (OOColor *)nullptr) == nil);

		TestShip *other = FlyingShip("viewer");
		GLfloat *c = (ship != nullptr ? ship->scannerDisplayColorForShip(other, NO, YES, red.get(), nullptr, nullptr, nullptr) : (GLfloat *)nullptr);
		OO_CHECK(c[0] == 1 && c[1] == 0 && c[2] == 0 && c[3] == 1);
		c = (ship != nullptr ? ship->scannerDisplayColorForShip(other, YES, NO, red.get(), nullptr, red.get(), blue.get()) : (GLfloat *)nullptr);	// hostile, not flashing: the second
		OO_CHECK(c[0] == 0 && c[2] == 1);
		if (ship != nullptr)  ship->setScanClass(CLASS_CARGO);
		c = (ship != nullptr ? ship->scannerDisplayColorForShip(other, NO, NO, nullptr, nullptr, nullptr, nullptr) : (GLfloat *)nullptr);
		OO_CHECK(c[0] == 0.9f && c[1] == 0.9f && c[2] == 0.9f && c[3] == 1);
		if (ship != nullptr)  ship->setScanClass(CLASS_POLICE);
		c = (ship != nullptr ? ship->scannerDisplayColorForShip(other, YES, YES, nullptr, nullptr, nullptr, nullptr) : (GLfloat *)nullptr);
		OO_CHECK(c[0] == 1 && c[1] == 0 && c[2] == 0.5f);
		if (ship != nullptr)  ship->setScanClass(CLASS_NEUTRAL);
		c = (ship != nullptr ? ship->scannerDisplayColorForShip(other, NO, NO, nullptr, nullptr, nullptr, nullptr) : (GLfloat *)nullptr);
		OO_CHECK(c[0] == 1 && c[1] == 1 && c[2] == 0);
	}
}


// Slice 16: cloaking flags, owner, thrust and orientation.
OO_TEST(cloakOwnerThrustAndOrientation)
{
	{
		SetUp();
		TestShip *ship = FlyingShip("flier");
		OO_CHECK(!(ship != nullptr ? ship->isCloaked() : false) && !(ship != nullptr ? ship->hasAutoCloak() : false) && !(ship != nullptr ? ship->isJammingScanning() : false));
		if (ship != nullptr)  ship->setAutoCloak(YES);
		OO_CHECK((ship != nullptr ? ship->hasAutoCloak() : false));

		TestShip *mother = FlyingShip("mother");
		if (ship != nullptr)  ship->setOwner(mother);
		OO_CHECK((ship != nullptr ? ship->owner() : nullptr) == mother);
		if (ship != nullptr)  ship->setOwner(nullptr);

		// Full thrust from a standstill: up to the desired speed, and forward by speed x time.
		if (ship != nullptr)  ship->setThrust(1000);
		if (ship != nullptr)  ship->setDesiredSpeed(100);
		if (ship != nullptr)  ship->applyThrust(0.5);
		OO_CHECK((ship != nullptr ? ship->getFlightSpeed() : 0.0f) == 100);
		OO_CHECK(fabs((ship != nullptr ? ship->getPosition() : HPVector{}).z - 50) < 1e-6);

		// Turned at random: the vectors follow the orientation.
		Quaternion q;
		quaternion_set_random(&q);
		if (ship != nullptr)  ship->setOrientation(q);
		Vector f = (ship != nullptr ? ship->forwardVector() : Vector{}), expected = vector_forward_from_quaternion((ship != nullptr ? ship->getOrientation() : Quaternion{}));
		OO_CHECK(fabs(f.x - expected.x) < 1e-6 && fabs(f.y - expected.y) < 1e-6 && fabs(f.z - expected.z) < 1e-6);
	}
}


// Slice 17: rolling, climbing and yawing turn the ship by the product of the turns, and update its
// vectors; with no turn and no rotation so far, nothing happens.
OO_TEST(attitude)
{
	{
		SetUp();
		TestShip *ship = FlyingShip("acrobat");
		if (ship != nullptr)  ship->applyRoll(0, 0);
		OO_CHECK(quaternion_equal((ship != nullptr ? ship->getOrientation() : Quaternion{}), kIdentityQuaternion));

		Quaternion q = kIdentityQuaternion;
		quaternion_rotate_about_z(&q, -0.1f);
		quaternion_rotate_about_x(&q, -0.2f);
		if (ship != nullptr)  ship->applyRoll(0.1f, 0.2f);
		Quaternion o = (ship != nullptr ? ship->getOrientation() : Quaternion{});
		OO_CHECK(fabs(o.w - q.w) < 1e-6 && fabs(o.x - q.x) < 1e-6 && fabs(o.y - q.y) < 1e-6 && fabs(o.z - q.z) < 1e-6);
		Vector f = (ship != nullptr ? ship->forwardVector() : Vector{}), expected = vector_forward_from_quaternion(o);
		OO_CHECK(fabs(f.x - expected.x) < 1e-6 && fabs(f.y - expected.y) < 1e-6 && fabs(f.z - expected.z) < 1e-6);

		// The attitude rates times the time step, as one turn.
		TestShip *a = FlyingShip("rates");
		TestShip *b = FlyingShip("by hand");
		if (a != nullptr)  a->setRoll(0.5);
		if (a != nullptr)  a->setPitch(0.25);
		if (a != nullptr)  a->setYaw(-0.5);
		if (a != nullptr)  a->applyAttitudeChanges(0.2);
		if (b != nullptr)  b->applyRoll((GLfloat)(0.5 * M_PI / 2.0) * 0.2, (GLfloat)(0.25 * M_PI / 2.0) * 0.2, (GLfloat)(-0.5 * M_PI / 2.0) * 0.2);	// -setRoll: is a fraction of a right angle
		Quaternion qa = (a != nullptr ? a->getOrientation() : Quaternion{}), qb = (b != nullptr ? b->getOrientation() : Quaternion{});
		OO_CHECK(fabs(qa.w - qb.w) < 1e-6 && fabs(qa.x - qb.x) < 1e-6 && fabs(qa.y - qb.y) < 1e-6 && fabs(qa.z - qb.z) < 1e-6);
	}
}


// Slice 17: avoiding a collision remembers what the ship was doing and heads for the point between
// the two ships; resuming restores it.
OO_TEST(avoidCollisionAndResume)
{
	{
		SetUp();
		TestShip *ship = FlyingShip("careful");
		TestShip *rock = FlyingShip("rock");
		if (rock != nullptr)  rock->setPosition(make_HPvector(0, 0, 400));
		if (ship != nullptr)  ship->setBehaviour(BEHAVIOUR_FLY_TO_DESTINATION);
		if (ship != nullptr)  ship->setDestination(make_HPvector(0, 0, 9000));
		if (ship != nullptr)  ship->setDesiredRange(300);
		if (ship != nullptr)  ship->setDesiredSpeed(12);

		if (ship != nullptr)  ship->avoidCollision();		// no alert: nothing
		OO_CHECK(Behaviour(ship) == BEHAVIOUR_FLY_TO_DESTINATION);

		SetProximityAlert(ship, rock);
		OO_CHECK((ship != nullptr ? ship->proximityAlert() : (Entity *)nullptr) == rock);
		if (ship != nullptr)  ship->avoidCollision();
		OO_CHECK(Behaviour(ship) == BEHAVIOUR_AVOID_COLLISION);
		OO_CHECK(HPvector_equal((ship != nullptr ? ship->destination() : HPVector{}), make_HPvector(0, 0, 200)));

		if (ship != nullptr)  ship->resumePostProximityAlert();
		OO_CHECK(Behaviour(ship) == BEHAVIOUR_FLY_TO_DESTINATION && (ship != nullptr ? ship->desiredRange() : 0.0) == 300 && (ship != nullptr ? ship->desiredSpeed() : 0.0) == 12);
		OO_CHECK(HPvector_equal((ship != nullptr ? ship->destination() : HPVector{}), make_HPvector(0, 0, 9000)));
		OO_CHECK((ship != nullptr ? ship->proximityAlert() : (Entity *)nullptr) == nullptr);

		// A missile does not avoid anything.
		if (ship != nullptr)  ship->setScanClass(CLASS_MISSILE);
		SetProximityAlert(ship, rock);
		if (ship != nullptr)  ship->avoidCollision();
		OO_CHECK(Behaviour(ship) == BEHAVIOUR_FLY_TO_DESTINATION);

		// Clearing the alert, and a light object never raises one.
		if (ship != nullptr)  ship->setProximityAlert(nullptr);
		OO_CHECK((ship != nullptr ? ship->proximityAlert() : (Entity *)nullptr) == nullptr);
		if (ship != nullptr)  ship->setProximityAlert(rock);		// mass 0
		OO_CHECK((ship != nullptr ? ship->proximityAlert() : (Entity *)nullptr) == nullptr);
	}
}


// Slice 17: message time, groups and escorts.
OO_TEST(groupsAndEscorts)
{
	{
		SetUp();
		TestShip *ship = FlyingShip("leader");
		if (ship != nullptr)  ship->setMessageTime(4.5);
		OO_CHECK((ship != nullptr ? ship->getMessageTime() : 0.0) == 4.5);

		OO_CHECK(!(ship != nullptr ? ship->hasEscorts() : false) && (ship != nullptr ? ship->escortCount() : uint8_t{}) == 0 && (ship != nullptr ? ship->escorts() : std::vector<oo::EntityHold>()).empty());
		OOShipGroup *escorts = (ship != nullptr ? ship->escortGroup() : (OOShipGroup *)nullptr);		// made on demand, led by the ship
		OO_CHECK(escorts != nil && escorts->leader() == ship && (ship != nullptr ? ship->escortGroup() : (OOShipGroup *)nullptr) == escorts);
		TestShip *wingman = FlyingShip("wingman");
		escorts->addShip(wingman);
		OO_CHECK((ship != nullptr ? ship->hasEscorts() : false) && (ship != nullptr ? ship->escortCount() : uint8_t{}) == 1);
		OO_CHECK((ship != nullptr ? ship->escorts() : std::vector<oo::EntityHold>()).size() == 1 && (ship != nullptr ? ship->escorts() : std::vector<oo::EntityHold>())[0].get() == wingman && (ship != nullptr ? ship->escortArray() : std::vector<oo::EntityHold>()).size() == 1);

		oo::Ref<OOShipGroup> other = OOShipGroup::groupWithName(std::nullopt);	// -init; held where the autoreleased facade was
		if (ship != nullptr)  ship->setEscortGroup(other.get());
		OO_CHECK((ship != nullptr ? ship->escortGroup() : (OOShipGroup *)nullptr) == other.get() && other->leader() == ship);

		oo::Ref<OOShipGroup> group = OOShipGroup::groupWithName(std::nullopt);
		if (wingman != nullptr)  wingman->setGroup(group.get());
		OO_CHECK((wingman != nullptr ? wingman->group() : (OOShipGroup *)nullptr) == group.get() && group->containsShip(wingman));
		if (wingman != nullptr)  wingman->setGroup(nullptr);
		OO_CHECK((wingman != nullptr ? wingman->group() : (OOShipGroup *)nullptr) == nil && !group->containsShip(wingman));

		TestShip *station = FlyingShip("station");
		OOShipGroup *stationGroup = (station != nullptr ? station->stationGroup() : (OOShipGroup *)nullptr);
		OO_CHECK(stationGroup != nil && stationGroup->leader() == station && (station != nullptr ? station->group() : (OOShipGroup *)nullptr) == stationGroup);

		if (ship != nullptr)  ship->setMaxEscortCount(3);
		if (ship != nullptr)  ship->setPendingEscortCount(5);
		OO_CHECK((ship != nullptr ? ship->maxEscortCount() : uint8_t{}) == 3 && (ship != nullptr ? ship->pendingEscortCount() : uint8_t{}) == 3);
		OO_CHECK((ship != nullptr ? ship->turretCount() : 0) == 0);
	}
}


// Slice 17: the names, and what the ship is called on screen.
OO_TEST(names)
{
	{
		SetUp();
		TestShip *ship = FlyingShip("named");
		if (ship != nullptr)  ship->setName(std::string("Cobra Mk III"));
		OO_CHECK((ship != nullptr ? ship->getName() : std::optional<std::string>()) == std::optional<std::string>("Cobra Mk III"));
		OO_CHECK((ship != nullptr ? ship->getDisplayName() : std::optional<std::string>()) == std::optional<std::string>("Cobra Mk III"));
		if (ship != nullptr)  ship->setShipUniqueName(std::string("Lucky"));
		OO_CHECK((ship != nullptr ? ship->getShipUniqueName() : std::optional<std::string>()) == std::optional<std::string>("Lucky"));
		OO_CHECK((ship != nullptr ? ship->getDisplayName() : std::optional<std::string>()) == std::optional<std::string>("Cobra Mk III: Lucky"));
		if (ship != nullptr)  ship->setShipClassName(std::string("Cobra"));
		OO_CHECK((ship != nullptr ? ship->getShipClassName() : std::optional<std::string>()) == std::optional<std::string>("Cobra"));
		OO_CHECK((ship != nullptr ? ship->getDisplayName() : std::optional<std::string>()) == std::optional<std::string>("Cobra: Lucky"));
		if (ship != nullptr)  ship->setShipUniqueName(std::string(""));
		OO_CHECK((ship != nullptr ? ship->getDisplayName() : std::optional<std::string>()) == std::optional<std::string>("Cobra"));
		if (ship != nullptr)  ship->setDisplayName(std::string("The Cobra"));
		OO_CHECK((ship != nullptr ? ship->getDisplayName() : std::optional<std::string>()) == std::optional<std::string>("The Cobra"));

		OO_CHECK((ship != nullptr ? ship->scanDescriptionForScripting() : std::optional<std::string>()) == std::nullopt);
		if (ship != nullptr)  ship->setScanDescription(std::string("Trader"));
		OO_CHECK((ship != nullptr ? ship->scanDescription() : std::optional<std::string>()) == std::optional<std::string>("Trader") && (ship != nullptr ? ship->scanDescriptionForScripting() : std::optional<std::string>()) == std::optional<std::string>("Trader"));
	}
}


// Slice 18: roles. A ship has its primary role, its data key's automatic role and the roles of its
// role set; adding is a no-op for a role it has.
OO_TEST(roles)
{
	{
		SetUp();
		TestShip *ship = FlyingShip("cobra3-trader");
		if (ship != nullptr)  ship->setPrimaryRole("trader");
		OO_CHECK((ship != nullptr ? ship->getPrimaryRole() : std::optional<std::string>()) == std::optional<std::string>("trader") && (ship != nullptr ? ship->hasPrimaryRole("trader") : false));
		OO_CHECK((ship != nullptr ? ship->hasRole("trader") : false) && (ship != nullptr ? ship->hasRole("[cobra3-trader]") : false) && !(ship != nullptr ? ship->hasRole("pirate") : false));
		if (ship != nullptr)  ship->addRole("pirate");
		OO_CHECK((ship != nullptr ? ship->hasRole("pirate") : false));
		if (ship != nullptr)  ship->addRole("hunter", 0.5f);
		OO_CHECK((ship != nullptr ? ship->hasRole("hunter") : false));
		const oo::Ref<OORoleSet> roles = ship->getRoleSet();
		OO_CHECK(roles->hasRole("pirate") && roles->hasRole("hunter") && roles->hasRole("trader") && roles->hasRole("[cobra3-trader]"));
		if (ship != nullptr)  ship->removeRole("pirate");
		OO_CHECK(!(ship != nullptr ? ship->hasRole("pirate") : false) && (ship != nullptr ? ship->hasRole("hunter") : false));

		// The weapons are known by their primary role.
		if (ship != nullptr)  ship->setPrimaryRole("EQ_HARDENED_MISSILE");
		OO_CHECK((ship != nullptr ? ship->getIsMissile() : false) && !(ship != nullptr ? ship->isMine() : false) && (ship != nullptr ? ship->isWeapon() : false));
		if (ship != nullptr)  ship->setPrimaryRole("missile");
		OO_CHECK((ship != nullptr ? ship->getIsMissile() : false));
		if (ship != nullptr)  ship->setPrimaryRole("EQ_QC_MINE");
		OO_CHECK(!(ship != nullptr ? ship->getIsMissile() : false) && (ship != nullptr ? ship->isMine() : false) && (ship != nullptr ? ship->isWeapon() : false));
	}
}


// Slice 18: the ship-type predicates that do not ask the universe, and hostility.
OO_TEST(typesAndHostility)
{
	{
		SetUp();
		TestShip *ship = FlyingShip("viper");
		if (ship != nullptr)  ship->setScanClass(CLASS_POLICE);
		OO_CHECK((ship != nullptr ? ship->isPolice() : false) && !(ship != nullptr ? ship->isThargoid() : false));
		if (ship != nullptr)  ship->setScanClass(CLASS_THARGOID);
		OO_CHECK(!(ship != nullptr ? ship->isPolice() : false) && (ship != nullptr ? ship->isThargoid() : false));
		OO_CHECK(!(ship != nullptr ? ship->isUnpiloted() : false) && !(ship != nullptr ? ship->isExplicitlyUnpiloted() : false));
		if (ship != nullptr)  ship->setScanClass(CLASS_CARGO);
		OO_CHECK((ship != nullptr ? ship->isUnpiloted() : false));
		if (ship != nullptr)  ship->setScanClass(CLASS_NEUTRAL);
		if (ship != nullptr)  ship->setBehaviour(BEHAVIOUR_TRACK_AS_TURRET);
		OO_CHECK((ship != nullptr ? ship->isTurret() : false));

		// Hostile: a ship target and an attacking behaviour (or one it will resume after an alert).
		if (ship != nullptr)  ship->setBehaviour(BEHAVIOUR_ATTACK_TARGET);
		OO_CHECK(!(ship != nullptr ? ship->hasHostileTarget() : false));		// no target
		TestShip *target = TargetAt(ship, 1000);
		OO_CHECK((ship != nullptr ? ship->hasHostileTarget() : false) && (ship != nullptr ? ship->isHostileTo(target) : false) && !(ship != nullptr ? ship->isHostileTo(ship) : false));
		if (ship != nullptr)  ship->setBehaviour(BEHAVIOUR_FLY_TO_DESTINATION);
		OO_CHECK(!(ship != nullptr ? ship->hasHostileTarget() : false));
		if (ship != nullptr)  ship->setBehaviour(BEHAVIOUR_AVOID_COLLISION);
		SetPreviousCondition(ship, oo::PList(oo::PList::Dict{ { "behaviour", oo::PList((double)BEHAVIOUR_ATTACK_SNIPER) } }));
		OO_CHECK((ship != nullptr ? ship->hasHostileTarget() : false));
		if (ship != nullptr)  ship->setBehaviour(BEHAVIOUR_IDLE);
		if (ship != nullptr)  ship->setPrimaryRole("missile");
		OO_CHECK((ship != nullptr ? ship->hasHostileTarget() : false));		// a missile's target always is

		// Without a jammer, a ship is identified by its display name.
		if (ship != nullptr)  ship->setDisplayName(std::string("Viper"));
		OO_CHECK((ship != nullptr ? ship->identFromShip(target) : std::optional<std::string>()) == std::optional<std::string>("Viper"));
	}
}


// Slice 18: the weapon and scanner values, and leaving the aegis.
OO_TEST(weaponAndScannerValues)
{
	{
		SetUp();
		TestShip *ship = FlyingShip("gunship");
		if (ship != nullptr)  ship->setWeaponRange(5000);
		OO_CHECK((ship != nullptr ? ship->getWeaponRange() : 0.0f) == 5000);
		if (ship != nullptr)  ship->setEnergyRechargeRate(2.5f);
		OO_CHECK((ship != nullptr ? ship->energyRechargeRate() : 0.0f) == 2.5f);
		if (ship != nullptr)  ship->setWeaponRechargeRate(0.5f);
		OO_CHECK((ship != nullptr ? ship->weaponRechargeRate() : 0.0f) == 0.5f);
		if (ship != nullptr)  ship->setWeaponEnergy(12);
		OO_CHECK(WeaponDamage(ship) == 12);
		if (ship != nullptr)  ship->setWeaponDataFromType(nullptr);		// no weapon: nothing
		OO_CHECK((ship != nullptr ? ship->getWeaponRange() : 0.0f) == 0 && (ship != nullptr ? ship->weaponRechargeRate() : 0.0f) == 0 && WeaponDamage(ship) == 0);
		OO_CHECK((ship != nullptr ? ship->getCurrentWeaponFacing() : OOWeaponFacing{}) == WEAPON_FACING_FORWARD);
		if (ship != nullptr)  ship->setScannerRange(30000);
		OO_CHECK((ship != nullptr ? ship->getScannerRange() : 0.0f) == 30000);
		if (ship != nullptr)  ship->setReference(make_vector(1, 2, 3));
		OO_CHECK(vector_equal((ship != nullptr ? ship->getReference() : Vector{}), make_vector(1, 2, 3)));
		OO_CHECK(!(ship != nullptr ? ship->getReportAIMessages() : false));
		if (ship != nullptr)  ship->setReportAIMessages(YES);
		OO_CHECK((ship != nullptr ? ship->getReportAIMessages() : false));

		SetAegisStatus(ship, AEGIS_IN_DOCKING_RANGE);
		if (ship != nullptr)  ship->transitionToAegisNone();
		OO_CHECK(AegisStatus(ship) == AEGIS_NONE);
	}
}


// Slice 19: the aegis bookkeeping, the systems, the status and the launch delay.
OO_TEST(aegisSystemsAndStatus)
{
	{
		SetUp();
		TestShip *ship = FlyingShip("navigator");
		if (ship != nullptr)  ship->forceAegisCheck();
		OO_CHECK(NextAegisCheck(ship) == -1.0);
		OO_CHECK(!(ship != nullptr ? ship->withinStationAegis() : false));
		SetAegisStatus(ship, AEGIS_IN_DOCKING_RANGE);
		OO_CHECK((ship != nullptr ? ship->withinStationAegis() : false));

		OO_CHECK((ship != nullptr ? ship->lastAegisLock() : (Entity *)nullptr) == nullptr);
		TestShip *body = FlyingShip("stand-in for a planet");
		if (ship != nullptr)  ship->setLastAegisLock(body);
		OO_CHECK((ship != nullptr ? ship->lastAegisLock() : (Entity *)nullptr) == body);
		if (ship != nullptr)  ship->setLastAegisLock(nullptr);
		OO_CHECK((ship != nullptr ? ship->lastAegisLock() : (Entity *)nullptr) == nullptr);

		if (ship != nullptr)  ship->setHomeSystem(7);
		if (ship != nullptr)  ship->setDestinationSystem(42);
		OO_CHECK((ship != nullptr ? ship->homeSystem() : 0) == 7 && (ship != nullptr ? ship->destinationSystem() : 0) == 42);

		if (ship != nullptr)  ship->setStatus(STATUS_LAUNCHING);
		OO_CHECK((ship != nullptr ? ship->status() : OOEntityStatus{}) == STATUS_LAUNCHING && LaunchTime(ship) == (UNIVERSE != nullptr ? UNIVERSE->getTime() : 0.0));
		if (ship != nullptr)  ship->setStatus(STATUS_IN_FLIGHT);
		OO_CHECK((ship != nullptr ? ship->status() : OOEntityStatus{}) == STATUS_IN_FLIGHT);
		if (ship != nullptr)  ship->setLaunchDelay(2.5);
		OO_CHECK(LaunchDelay(ship) == 2.5);
	}
}


// Slice 19: the crew, the AI and the flags read from the definition.
OO_TEST(crewAndAI)
{
	{
		SetUp();
		TestShip *ship = FlyingShip("crewed");
		OO_CHECK(!(ship != nullptr ? ship->getCrew() : std::optional<std::vector<oo::Ref<OOCharacter>>>()).has_value() && (ship != nullptr ? ship->crewForScripting() : std::vector<oo::PList>()).empty());
		if (ship != nullptr)  ship->setCrew(std::vector<oo::Ref<OOCharacter>>{});
		OO_CHECK((ship != nullptr ? ship->getCrew() : std::optional<std::vector<oo::Ref<OOCharacter>>>()).has_value() && (ship != nullptr ? ship->getCrew() : std::optional<std::vector<oo::Ref<OOCharacter>>>())->empty());
		SetExplicitlyUnpiloted(ship, true);
		if (ship != nullptr)  ship->setCrew(std::vector<oo::Ref<OOCharacter>>{});	// unpiloted ships have none
		OO_CHECK(!(ship != nullptr ? ship->getCrew() : std::optional<std::vector<oo::Ref<OOCharacter>>>()).has_value());

		OO_CHECK((ship != nullptr ? ship->getAI() : (::AI *)nullptr) == nil && !(ship != nullptr ? ship->hasNewAI() : false));
		oo::Ref<AI> heldAI = oo::makeRef<AI>();	// [[[AI alloc] init] autorelease]: C++ since bead oo-9ht.73
		AI *ai = heldAI.get();
		if (ship != nullptr)  ship->setAI(ai);
		OO_CHECK((ship != nullptr ? ship->getAI() : (::AI *)nullptr) == ai);
		if (ship != nullptr)  ship->setAI(nullptr);
		OO_CHECK((ship != nullptr ? ship->getAI() : (::AI *)nullptr) == nil);

		OO_CHECK((ship != nullptr ? ship->hasAutoAI() : false) && !(ship != nullptr ? ship->hasAutoWeapons() : false));	// the definition says neither
		OO_CHECK((ship != nullptr ? ship->getFrustration() : 0.0) == 0);
	}
}


// Slice 19: fuel is clamped to the capacity.
OO_TEST(fuel)
{
	{
		SetUp();
		TestShip *ship = FlyingShip("tanker");
		OO_CHECK((ship != nullptr ? ship->fuelCapacity() : OOFuelQuantity{}) == PLAYER_MAX_FUEL);
		if (ship != nullptr)  ship->setFuel(35);
		OO_CHECK((ship != nullptr ? ship->getFuel() : OOFuelQuantity{}) == 35);
		if (ship != nullptr)  ship->setFuel(PLAYER_MAX_FUEL + 10);
		OO_CHECK((ship != nullptr ? ship->getFuel() : OOFuelQuantity{}) == PLAYER_MAX_FUEL);
	}
}


// Slice 20: the sticks move the flight rates towards them by a limited step; the rate setters.
OO_TEST(sticksAndRates)
{
	{
		SetUp();
		TestShip *ship = FlyingShip("pilot");
		SetSticks(ship, 1.0f, -1.0f, 0.01f);
		if (ship != nullptr)  ship->applySticks(0.1);			// roll moves 2 x dt, pitch and yaw 4 x dt, or reach the stick
		OO_CHECK(fabs((ship != nullptr ? ship->getFlightRoll() : 0.0f) - 0.2f) < 1e-6 && fabs((ship != nullptr ? ship->getFlightPitch() : 0.0f) + 0.4f) < 1e-6 && fabs((ship != nullptr ? ship->getFlightYaw() : 0.0f) - 0.01f) < 1e-6);
		SetSticks(ship, -1.0f, -1.0f, 0.01f);
		if (ship != nullptr)  ship->applySticks(0.1);			// against the current roll: four times faster
		OO_CHECK(fabs((ship != nullptr ? ship->getFlightRoll() : 0.0f) - (0.2f - 0.8f)) < 1e-6);

		if (ship != nullptr)  ship->setRoll(1);
		OO_CHECK(fabs((ship != nullptr ? ship->getFlightRoll() : 0.0f) - M_PI / 2.0) < 1e-6);
		if (ship != nullptr)  ship->setRawRoll(0.25);
		OO_CHECK((ship != nullptr ? ship->getFlightRoll() : 0.0f) == 0.25f);
		if (ship != nullptr)  ship->setPitch(-1);
		if (ship != nullptr)  ship->setYaw(0.5);
		OO_CHECK(fabs((ship != nullptr ? ship->getFlightPitch() : 0.0f) + M_PI / 2.0) < 1e-6 && fabs((ship != nullptr ? ship->getFlightYaw() : 0.0f) - M_PI / 4.0) < 1e-6);
		if (ship != nullptr)  ship->setThrust(12);
		OO_CHECK((ship != nullptr ? ship->getThrust() : 0.0f) == 12);
		if (ship != nullptr)  ship->setThrustForDemo(0.5f);
		OO_CHECK((ship != nullptr ? ship->getFlightSpeed() : 0.0f) == 100);
		if (ship != nullptr)  ship->setSpeed(42);
		OO_CHECK((ship != nullptr ? ship->getFlightSpeed() : 0.0f) == 42);
		if (ship != nullptr)  ship->setDesiredSpeed(17);
		OO_CHECK((ship != nullptr ? ship->desiredSpeed() : 0.0) == 17);
	}
}


// Slice 20: bounty and legal status.
OO_TEST(bountyAndLegalStatus)
{
	{
		SetUp();
		TestShip *ship = FlyingShip("offender");
		if (ship != nullptr)  ship->setBounty(40);
		OO_CHECK((ship != nullptr ? ship->getBounty() : 0) == 40 && (ship != nullptr ? ship->legalStatus() : int{}) == 40);
		if (ship != nullptr)  ship->setBounty(60, kOOLegalStatusReasonByScript);
		OO_CHECK((ship != nullptr ? ship->getBounty() : 0) == 60);
		if (ship != nullptr)  ship->setBounty(5, "setup");
		OO_CHECK((ship != nullptr ? ship->getBounty() : 0) == 5);

		if (ship != nullptr)  ship->setScanClass(CLASS_POLICE);
		if (ship != nullptr)  ship->setBounty(30);		// police never have bounties
		OO_CHECK((ship != nullptr ? ship->getBounty() : 0) == 5);
		if (ship != nullptr)  ship->setScanClass(CLASS_THARGOID);
		if (ship != nullptr)  ship->setBounty(30);		// nor do Thargoids, but by script or set-up
		OO_CHECK((ship != nullptr ? ship->getBounty() : 0) == 5);
		if (ship != nullptr)  ship->setBounty(30, kOOLegalStatusReasonSetup);
		OO_CHECK((ship != nullptr ? ship->getBounty() : 0) == 30);
		if (ship != nullptr)  ship->setCollisionRadius(20);
		OO_CHECK((ship != nullptr ? ship->legalStatus() : int{}) == 100);	// a Thargoid's is five times its radius
		if (ship != nullptr)  ship->setScanClass(CLASS_ROCK);
		OO_CHECK((ship != nullptr ? ship->legalStatus() : int{}) == 0);
	}
}


// Slice 20: commodities and cargo.
OO_TEST(commoditiesAndCargo)
{
	{
		SetUp();
		TestShip *pod = FlyingShip("pod");
		OO_CHECK(!(pod != nullptr ? pod->commodityType() : std::optional<std::string>()).has_value() && (pod != nullptr ? pod->commodityAmount() : 0) == 0);
		if (pod != nullptr)  pod->setCommodity("food", 3);
		OO_CHECK((pod != nullptr ? pod->commodityType() : std::optional<std::string>()) == std::optional<std::string>("food") && (pod != nullptr ? pod->commodityAmount() : 0) == 3);

		TestShip *ship = FlyingShip("hauler");
		if (ship != nullptr)  ship->setMaxAvailableCargoSpace(3);
		OO_CHECK((ship != nullptr ? ship->maxAvailableCargoSpace() : 0) == 3 && (ship != nullptr ? ship->availableCargoSpace() : 0) == 3 && (ship != nullptr ? ship->cargoQuantityOnBoard() : 0) == 0);
		TestShip *food = FlyingShip("food pod");
		if (food != nullptr)  food->setCommodity("food", 1);
		TestShip *gold = FlyingShip("gold pod");
		if (gold != nullptr)  gold->setCommodity("gold", 1);
		if (ship != nullptr)  ship->setCargo({ oo::EntityHold(food), oo::EntityHold(gold) });
		OO_CHECK((ship != nullptr ? ship->cargoCount() : 0) == 2 && (ship != nullptr ? ship->cargoQuantityOnBoard() : 0) == 2 && (ship != nullptr ? ship->availableCargoSpace() : 0) == 1);
		OO_CHECK((ship != nullptr ? ship->getCargo() : (std::vector<oo::EntityHold> *)nullptr)->size() == 2 && (*(ship != nullptr ? ship->getCargo() : (std::vector<oo::EntityHold> *)nullptr))[1].get() == gold);
		OO_CHECK((!(ship != nullptr ? ship->addCargo({ oo::EntityHold(food), oo::EntityHold(food) }) : false)));	// no room
		OO_CHECK((ship != nullptr ? ship->addCargo({ oo::EntityHold(food) }) : false) && (ship != nullptr ? ship->cargoCount() : 0) == 3);
		OO_CHECK(!(ship != nullptr ? ship->removeCargo("gold", 2) : false));		// not that many: nothing removed
		OO_CHECK((ship != nullptr ? ship->cargoCount() : 0) == 3);
		OO_CHECK((ship != nullptr ? ship->removeCargo("food", 2) : false) && (ship != nullptr ? ship->cargoCount() : 0) == 1 && (*(ship != nullptr ? ship->getCargo() : (std::vector<oo::EntityHold> *)nullptr))[0].get() == gold);

		OO_CHECK((ship != nullptr ? ship->cargoFlag() : OOCargoFlag{}) == (OOCargoFlag)0 && !(ship != nullptr ? ship->showScoopMessage() : false));	// TestShip skips the set-up that reads both
		if (ship != nullptr)  ship->setMaxAvailableCargoSpace(0);
		if (ship != nullptr)  ship->setCargoFlag(CARGO_FLAG_FULL_PASSENGERS);		// no room: no cargo
		OO_CHECK((ship != nullptr ? ship->cargoFlag() : OOCargoFlag{}) == CARGO_FLAG_FULL_PASSENGERS && (ship != nullptr ? ship->cargoCount() : 0) == 0);
	}
}


// Slice 21: the flight controls, clamped to the ship's limits.
OO_TEST(flightControls)
{
	{
		SetUp();
		TestShip *ship = FlyingShip("controls");
		if (ship != nullptr)  ship->setDesiredRange(750);
		OO_CHECK((ship != nullptr ? ship->desiredRange() : 0.0) == 750 && (ship != nullptr ? ship->getCruiseSpeed() : 0.0) == 0);

		if (ship != nullptr)  ship->increase_flight_speed(50);
		OO_CHECK((ship != nullptr ? ship->getFlightSpeed() : 0.0f) == 50);
		if (ship != nullptr)  ship->increase_flight_speed(500);		// past the top speed: overshoots once
		OO_CHECK((ship != nullptr ? ship->getFlightSpeed() : 0.0f) == 550);
		if (ship != nullptr)  ship->increase_flight_speed(1);			// then is the top speed
		OO_CHECK((ship != nullptr ? ship->getFlightSpeed() : 0.0f) == 200);
		OO_CHECK((ship != nullptr ? ship->speedFactor() : 0.0f) == 1);
		if (ship != nullptr)  ship->decrease_flight_speed(150);
		OO_CHECK((ship != nullptr ? ship->getFlightSpeed() : 0.0f) == 50);
		if (ship != nullptr)  ship->decrease_flight_speed(80);
		OO_CHECK((ship != nullptr ? ship->getFlightSpeed() : 0.0f) == 0);

		if (ship != nullptr)  ship->setMaxFlightRoll(2);
		if (ship != nullptr)  ship->setMaxFlightPitch(1);
		if (ship != nullptr)  ship->setMaxFlightYaw(0.5f);
		OO_CHECK((ship != nullptr ? ship->maxFlightRoll() : 0.0f) == 2 && (ship != nullptr ? ship->maxFlightPitch() : 0.0f) == 1 && (ship != nullptr ? ship->maxFlightYaw() : 0.0f) == 0.5f);
		if (ship != nullptr)  ship->increase_flight_roll(3);
		if (ship != nullptr)  ship->increase_flight_pitch(0.25);
		if (ship != nullptr)  ship->decrease_flight_yaw(1);
		OO_CHECK((ship != nullptr ? ship->getFlightRoll() : 0.0f) == 2 && (ship != nullptr ? ship->getFlightPitch() : 0.0f) == 0.25f && (ship != nullptr ? ship->getFlightYaw() : 0.0f) == -0.5f);
		if (ship != nullptr)  ship->decrease_flight_roll(5);
		if (ship != nullptr)  ship->decrease_flight_pitch(0.5);
		if (ship != nullptr)  ship->increase_flight_yaw(2);
		OO_CHECK((ship != nullptr ? ship->getFlightRoll() : 0.0f) == -2 && (ship != nullptr ? ship->getFlightPitch() : 0.0f) == -0.25f && (ship != nullptr ? ship->getFlightYaw() : 0.0f) == 0.5f);

		if (ship != nullptr)  ship->setMaxFlightSpeed(0);
		OO_CHECK((ship != nullptr ? ship->speedFactor() : 0.0f) == 0 && (ship != nullptr ? ship->getMaxFlightSpeed() : 0.0f) == 0);
	}
}


// Slice 21: temperature, insulation, damage and hulks.
OO_TEST(temperatureDamageAndHulks)
{
	{
		SetUp();
		TestShip *ship = FlyingShip("hot");
		OO_CHECK((ship != nullptr ? ship->temperature() : 0.0f) == SHIP_MIN_CABIN_TEMP);
		OO_CHECK((ship != nullptr ? ship->randomEjectaTemperature() : 0.0f) == SHIP_MIN_CABIN_TEMP);	// a cold ship's debris is as cold
		if (ship != nullptr)  ship->setTemperature(500);
		OO_CHECK((ship != nullptr ? ship->temperature() : 0.0f) == 500);
		float ejecta = (ship != nullptr ? ship->randomEjectaTemperatureWithMaxFactor(0.5f) : 0.0f);
		OO_CHECK(ejecta > SHIP_MIN_CABIN_TEMP && ejecta < 500);
		if (ship != nullptr)  ship->setHeatInsulation(2);
		OO_CHECK((ship != nullptr ? ship->heatInsulation() : 0.0f) == 2);

		if (ship != nullptr)  ship->setMaxEnergy(200);
		if (ship != nullptr)  ship->setEnergy(150);
		OO_CHECK((ship != nullptr ? ship->damage() : int{}) == 25);

		OO_CHECK(!(ship != nullptr ? ship->getIsHulk() : false));
		if (ship != nullptr)  ship->setHulk(YES);
		OO_CHECK((ship != nullptr ? ship->getIsHulk() : false) && (ship != nullptr ? ship->isUnpiloted() : false));
		if (ship != nullptr)  ship->setHulk(NO);
		TestShip *sub = FlyingShip("turret");
		SetSubEntity(sub, true);
		if (sub != nullptr)  sub->setHulk(YES);		// a subentity never is
		OO_CHECK(!(sub != nullptr ? sub->getIsHulk() : false));
		SetSubEntity(sub, false);
	}
}


// Slice 22: a ship with no model rescales its scale factor and its mass (by the cube), and its
// subentities' positions; wreckage and the damage flag; a ship with no cargo throws nothing out.
OO_TEST(rescaleWreckageAndDebris)
{
	{
		SetUp();
		TestShip *ship = FlyingShip("big");
		TestShip *sub = FlyingShip("part");
		if (sub != nullptr)  sub->setPosition(make_HPvector(1, 2, 3));
		if (ship != nullptr)  ship->addSubEntity(sub);
		const GLfloat scale = ScaleFactor(ship);
		SetMass(ship, 10);
		if (ship != nullptr)  ship->rescaleBy(2, NO);
		OO_CHECK(ScaleFactor(ship) == scale * 2 && (ship != nullptr ? ship->getMass() : 0.0f) == 80);
		OO_CHECK(HPdistance((sub != nullptr ? sub->getPosition() : HPVector{}), make_HPvector(2, 4, 6)) < 1e-9);
		if (ship != nullptr)  ship->rescaleBy(0.5);
		OO_CHECK(ScaleFactor(ship) == scale && (ship != nullptr ? ship->getMass() : 0.0f) == 10);

		OO_CHECK(!IsWreckage(ship) && !(ship != nullptr ? ship->showDamage() : false));
		if (ship != nullptr)  ship->setIsWreckage(YES);
		SetShowDamage(ship, true);
		OO_CHECK(IsWreckage(ship) && (ship != nullptr ? ship->showDamage() : false));

		OO_CHECK((ship != nullptr ? ship->cargoCount() : 0) == 0);
		if (ship != nullptr)  ship->releaseCargoPodsDebris();
		OO_CHECK((ship != nullptr ? ship->cargoCount() : 0) == 0);
	}
}


// Slice 23: the heat levels, clamped to 0 ... 1; the weapon's recovery; the personality, its shader
// seed and its range; the explosion flag; the scanner; the alignment offsets in the bounding box;
// and beacon codes compared without case.
OO_TEST(heatPersonalityAlignmentAndBeacons)
{
	{
		SetUp();
		TestShip *ship = FlyingShip("warm");
		SetWeaponTemps(ship, NPC_MAX_WEAPON_TEMP / 2, NPC_MAX_WEAPON_TEMP * 2);
		OO_CHECK((ship != nullptr ? ship->laserHeatLevel() : 0.0f) == 0.5f && (ship != nullptr ? ship->laserHeatLevelAft() : 0.0f) == 1.0f);
		if (ship != nullptr)  ship->setTemperature(SHIP_MAX_CABIN_TEMP / 4);
		OO_CHECK((ship != nullptr ? ship->hullHeatLevel() : 0.0f) == 0.25f);
		if (ship != nullptr)  ship->setWeaponRechargeRate(2);
		OO_CHECK((ship != nullptr ? ship->weaponRecoveryTime() : 0.0f) == 0.0f);	// the shot time starts at INITIAL_SHOT_TIME: long recovered
		SetShotTime(ship, 0.5);
		OO_CHECK((ship != nullptr ? ship->weaponRecoveryTime() : 0.0f) == 0.75f);

		if (ship != nullptr)  ship->setEntityPersonalityInt(100);
		OO_CHECK((ship != nullptr ? ship->entityPersonalityInt() : GLint{}) == 100 && (ship != nullptr ? ship->randomSeedForShaders() : uint32_t{}) == 100u * 0x00010001u);
		OO_CHECK((ship != nullptr ? ship->entityPersonality() : 0.0f) == 100 / (float)ENTITY_PERSONALITY_MAX);
		if (ship != nullptr)  ship->setEntityPersonalityInt(ENTITY_PERSONALITY_MAX + 1);	// out of range: ignored
		OO_CHECK((ship != nullptr ? ship->entityPersonalityInt() : GLint{}) == 100);

		OO_CHECK(!SuppressesExplosion(ship));
		if (ship != nullptr)  ship->setSuppressExplosion(YES);
		OO_CHECK(SuppressesExplosion(ship));

		OO_CHECK((ship != nullptr ? ship->numberOfScannedShips() : int{}) == 0);
		if (ship != nullptr)  ship->setFoundTarget(nullptr);
		OO_CHECK((ship != nullptr ? ship->foundTarget() : (Entity *)nullptr) == nil && (ship != nullptr ? ship->primaryAggressor() : (Entity *)nullptr) == nil && (ship != nullptr ? ship->lastEscortTarget() : (Entity *)nullptr) == nullptr);

		SetBoundingBox(ship, BoundingBox{ { -1, -2, -3 }, { 3, 4, 5 } });
		Vector offset = (ship != nullptr ? ship->positionOffsetForAlignment("MmC") : Vector{});
		OO_CHECK(offset.x == 3 && offset.y == -2 && offset.z == 1);
		offset = (ship != nullptr ? ship->positionOffsetForAlignment("c") : Vector{});		// the others are padded with '-': zero
		OO_CHECK(offset.x == 1 && offset.y == 0 && offset.z == 0);

		TestShip *other = FlyingShip("beacon");
		if (ship != nullptr)  ship->setBeaconCode(std::string("alpha"));
		if (other != nullptr)  other->setBeaconCode(std::string("BETA"));
		OO_CHECK((ship != nullptr ? ship->compareBeaconCodeWith(other) : OOComparisonResult{}) == OOOrderedAscending && (other != nullptr ? other->compareBeaconCodeWith(ship) : OOComparisonResult{}) == OOOrderedDescending);
	}
}


// --- Slice 24: target memory and validity, behaviour and destination accessors, distances, leading
// the target (bead oo-zd80m). Written against the Objective-C API and run on the unconverted slice
// first.


// The later slices' ship: one that scripts cannot see, so that the events it sends with entities as
// arguments make no JavaScript objects in the test's empty context.
class LateSliceTestShip : public TestShip	// C++ since bead oo-9ht.144
{
public:
	bool isVisibleToScripts() override	{ return false; }
};


namespace {

TestShip *MakeLateSliceShip(const char *key)
{
	return MakeShip<LateSliceTestShip>(key, Definition());
}

GLfloat Frustration24(ShipEntity *s)			{ return s->frustration; }
void SetFrustration24(ShipEntity *s, GLfloat f)	{ s->frustration = f; }
void SetScannerRange24(ShipEntity *s, GLfloat r)	{ s->scannerRange = r; }
void SetWeaponRange24(ShipEntity *s, GLfloat r)	{ s->weaponRange = r; }
void SetDestination24(ShipEntity *s, HPVector d)	{ s->_destination = d; }
void SetPosition24(Entity *e, HPVector p)		{ e->position = p; }
void SetFlightControls24(ShipEntity *s, GLfloat v)
{
	s->flightRoll = s->flightPitch = s->flightYaw = v;
	s->stick_roll = s->stick_pitch = s->stick_yaw = v;
}
bool FlightControlsZero24(ShipEntity *s)
{
	ShipEntity *p = s;
	return p->flightRoll == 0 && p->flightPitch == 0 && p->flightYaw == 0 && p->stick_roll == 0 && p->stick_pitch == 0 && p->stick_yaw == 0;
}
bool Near24(HPVector a, HPVector b)	{ return HPdistance2(a, b) < 1e-6; }
void SetCollisionRadius24(Entity *e, GLfloat r)	{ e->collision_radius = r; }

}	// namespace


OO_TEST(slice24RememberedShips)
{
	{
		SetUp();
		TestShip *ship = MakeLateSliceShip("rememberer");
		TestShip *other = MakeLateSliceShip("other");
		OO_CHECK((ship != nullptr ? ship->thankedShip() : (Entity *)nullptr) == nullptr && (ship != nullptr ? ship->rememberedShip() : (Entity *)nullptr) == nullptr && (ship != nullptr ? ship->targetStation() : (Entity *)nullptr) == nullptr);

		if (ship != nullptr)  ship->setThankedShip(other);
		if (ship != nullptr)  ship->setRememberedShip(other);
		if (ship != nullptr)  ship->setTargetStation(other);
		OO_CHECK((ship != nullptr ? ship->thankedShip() : (Entity *)nullptr) == other && (ship != nullptr ? ship->rememberedShip() : (Entity *)nullptr) == other && (ship != nullptr ? ship->targetStation() : (Entity *)nullptr) == other);

		// A ship that is no longer a valid target is forgotten, and stays forgotten.
		if (other != nullptr)  other->setStatus(STATUS_DOCKED);
		OO_CHECK((ship != nullptr ? ship->thankedShip() : (Entity *)nullptr) == nullptr && (ship != nullptr ? ship->rememberedShip() : (Entity *)nullptr) == nullptr && (ship != nullptr ? ship->targetStation() : (Entity *)nullptr) == nullptr);
		if (other != nullptr)  other->setStatus(STATUS_IN_FLIGHT);
		OO_CHECK((ship != nullptr ? ship->thankedShip() : (Entity *)nullptr) == nullptr && (ship != nullptr ? ship->rememberedShip() : (Entity *)nullptr) == nullptr && (ship != nullptr ? ship->targetStation() : (Entity *)nullptr) == nullptr);

		if (ship != nullptr)  ship->setThankedShip(other);
		if (ship != nullptr)  ship->setThankedShip(nullptr);
		OO_CHECK((ship != nullptr ? ship->thankedShip() : (Entity *)nullptr) == nullptr);

		OO_CHECK((ship != nullptr ? ship->shipHitByLaser() : (::ShipEntity *)nil) == nil);
		if (ship != nullptr)  ship->setShipHitByLaser(other);
		OO_CHECK((ship != nullptr ? ship->shipHitByLaser() : (::ShipEntity *)nil) == other);
		if (ship != nullptr)  ship->setShipHitByLaser(nullptr);
		OO_CHECK((ship != nullptr ? ship->shipHitByLaser() : (::ShipEntity *)nil) == nil);
	}
}


OO_TEST(slice24IsValidTarget)
{
	{
		SetUp();
		TestShip *ship = MakeLateSliceShip("judge");
		TestShip *other = MakeLateSliceShip("target");
		Entity *plain = oo::MadeEntity(oo::makeRef<Entity>());
		OO_CHECK(!(ship != nullptr ? ship->isValidTarget(nullptr) : false));
		OO_CHECK((ship != nullptr ? ship->isValidTarget(other) : false));
		OO_CHECK(!(ship != nullptr ? ship->isValidTarget(plain) : false));		// neither a ship nor a wormhole
		const OOEntityStatus invalid[] = { STATUS_ENTERING_WITCHSPACE, STATUS_IN_HOLD, STATUS_DOCKED, STATUS_DEAD };
		for (OOEntityStatus s : invalid)
		{
			if (other != nullptr)  other->setStatus(s);
			OO_CHECK(!(ship != nullptr ? ship->isValidTarget(other) : false));
		}
		if (other != nullptr)  other->setStatus(STATUS_ACTIVE);
		OO_CHECK((ship != nullptr ? ship->isValidTarget(other) : false));
	}
}


OO_TEST(slice24PrimaryTarget)
{
	{
		SetUp();
		TestShip *ship = MakeLateSliceShip("hunter");
		TestShip *other = MakeLateSliceShip("prey");
		OO_CHECK((ship != nullptr ? ship->primaryTarget() : (Entity *)nullptr) == nil && (ship != nullptr ? ship->primaryTargetWithoutValidityCheck() : (Entity *)nullptr) == nil);
		OO_CHECK(!(ship != nullptr ? ship->canStillTrackPrimaryTarget() : false));

		if (ship != nullptr)  ship->addTarget(ship);		// never itself
		OO_CHECK((ship != nullptr ? ship->primaryTarget() : (Entity *)nullptr) == nil);

		if (ship != nullptr)  ship->addTarget(other);
		OO_CHECK((ship != nullptr ? ship->primaryTarget() : (Entity *)nullptr) == other && (ship != nullptr ? ship->primaryTargetWithoutValidityCheck() : (Entity *)nullptr) == other);

		// In range (a quarter more than the scanner's), and out of it.
		SetScannerRange24(ship, 1000);
		SetPosition24(other, make_HPvector(0, 0, 1240));
		OO_CHECK((ship != nullptr ? ship->canStillTrackPrimaryTarget() : false));
		SetPosition24(other, make_HPvector(0, 0, 1260));
		OO_CHECK(!(ship != nullptr ? ship->canStillTrackPrimaryTarget() : false));
		SetPosition24(other, kZeroHPVector);

		// An invalid target: the unchecked getter keeps it, the checked one drops it.
		if (other != nullptr)  other->setStatus(STATUS_DEAD);
		OO_CHECK(!(ship != nullptr ? ship->canStillTrackPrimaryTarget() : false));
		OO_CHECK((ship != nullptr ? ship->primaryTargetWithoutValidityCheck() : (Entity *)nullptr) == other);
		OO_CHECK((ship != nullptr ? ship->primaryTarget() : (Entity *)nullptr) == nil);
		OO_CHECK((ship != nullptr ? ship->primaryTargetWithoutValidityCheck() : (Entity *)nullptr) == nil);
		if (other != nullptr)  other->setStatus(STATUS_IN_FLIGHT);

		// -removeTarget:nil drops the target without the lost-target events.
		if (ship != nullptr)  ship->addTarget(other);
		if (ship != nullptr)  ship->removeTarget(nullptr);
		OO_CHECK((ship != nullptr ? ship->primaryTarget() : (Entity *)nullptr) == nil);

		// -removeTarget: with a target notes it lost.
		if (ship != nullptr)  ship->addTarget(other);
		if (ship != nullptr)  ship->removeTarget(other);
		OO_CHECK((ship != nullptr ? ship->primaryTarget() : (Entity *)nullptr) == nil);
	}
}


OO_TEST(slice24NoteLostTarget)
{
	{
		SetUp();
		TestShip *ship = MakeLateSliceShip("forgetful");
		TestShip *other = MakeLateSliceShip("lost");
		if (ship != nullptr)  ship->addTarget(other);
		if (ship != nullptr)  ship->noteLostTarget();
		OO_CHECK((ship != nullptr ? ship->primaryTarget() : (Entity *)nullptr) == nil);
		if (ship != nullptr)  ship->noteLostTarget();		// with none, still fine
		OO_CHECK((ship != nullptr ? ship->primaryTarget() : (Entity *)nullptr) == nil);

		if (ship != nullptr)  ship->addTarget(other);
		if (ship != nullptr)  ship->setBehaviour(BEHAVIOUR_ATTACK_TARGET);
		SetFrustration24(ship, 5);
		if (ship != nullptr)  ship->noteLostTargetAndGoIdle();
		OO_CHECK((ship != nullptr ? ship->primaryTarget() : (Entity *)nullptr) == nil);
		OO_CHECK((ship != nullptr ? ship->getBehaviour() : OOBehaviour{}) == BEHAVIOUR_IDLE && Frustration24(ship) == 0);
	}
}


OO_TEST(slice24IsFriendlyTo)
{
	{
		SetUp();
		TestShip *ship = MakeLateSliceShip("friend");
		TestShip *other = MakeLateSliceShip("stranger");
		OO_CHECK((ship != nullptr ? ship->isFriendlyTo(ship) : false));
		OO_CHECK(!(ship != nullptr ? ship->isFriendlyTo(other) : false));

		if (ship != nullptr)  ship->setScanClass(CLASS_POLICE);
		if (other != nullptr)  other->setScanClass(CLASS_POLICE);
		OO_CHECK((ship != nullptr ? ship->isFriendlyTo(other) : false));
		if (ship != nullptr)  ship->setScanClass(CLASS_THARGOID);
		if (other != nullptr)  other->setScanClass(CLASS_THARGOID);
		OO_CHECK((ship != nullptr ? ship->isFriendlyTo(other) : false));
		if (ship != nullptr)  ship->setScanClass(CLASS_MILITARY);
		if (other != nullptr)  other->setScanClass(CLASS_MILITARY);
		OO_CHECK((ship != nullptr ? ship->isFriendlyTo(other) : false));
		if (ship != nullptr)  ship->setScanClass(CLASS_NEUTRAL);
		if (other != nullptr)  other->setScanClass(CLASS_NEUTRAL);
		OO_CHECK(!(ship != nullptr ? ship->isFriendlyTo(other) : false));

		oo::Ref<OOShipGroup> group = OOShipGroup::groupWithName(std::nullopt);	// -init; held where the autoreleased facade was
		if (ship != nullptr)  ship->setGroup(group.get());
		if (other != nullptr)  other->setGroup(group.get());
		OO_CHECK((ship != nullptr ? ship->isFriendlyTo(other) : false) && (other != nullptr ? other->isFriendlyTo(ship) : false));
		if (ship != nullptr)  ship->setGroup(nullptr);
		if (other != nullptr)  other->setGroup(nullptr);
	}
}


OO_TEST(slice24BehaviourAndDestination)
{
	{
		SetUp();
		TestShip *ship = MakeLateSliceShip("navigator");
		SetFrustration24(ship, 3);
		if (ship != nullptr)  ship->setBehaviour((ship != nullptr ? ship->getBehaviour() : OOBehaviour{}));		// no change: frustration stays
		OO_CHECK(Frustration24(ship) == 3);
		if (ship != nullptr)  ship->setBehaviour(BEHAVIOUR_FLEE_TARGET);	// a change is a good thing
		OO_CHECK((ship != nullptr ? ship->getBehaviour() : OOBehaviour{}) == BEHAVIOUR_FLEE_TARGET && Frustration24(ship) == 0);

		SetDestination24(ship, make_HPvector(1, 2, 3));
		OO_CHECK(Near24((ship != nullptr ? ship->destination() : HPVector{}), make_HPvector(1, 2, 3)));
		if (ship != nullptr)  ship->setCoordinate(make_HPvector(4, 5, 6));
		OO_CHECK(Near24((ship != nullptr ? ship->getCoordinates() : HPVector{}), make_HPvector(4, 5, 6)));
	}
}


OO_TEST(slice24Distances)
{
	{
		SetUp();
		TestShip *ship = MakeLateSliceShip("formation");
		SetPosition24(ship, make_HPvector(10, 20, 30));
		if (ship != nullptr)  ship->setOrientation(kIdentityQuaternion);
		Vector f = (ship != nullptr ? ship->forwardVector() : Vector{}), u = (ship != nullptr ? ship->upVector() : Vector{}), r = (ship != nullptr ? ship->rightVector() : Vector{});
		OO_CHECK(Near24((ship != nullptr ? ship->distance_six(5) : HPVector{}), make_HPvector(10 - 5 * f.x, 20 - 5 * f.y, 30 - 5 * f.z)));
		OO_CHECK(Near24((ship != nullptr ? ship->distance_twelve(5, 2) : HPVector{}), make_HPvector(10 + 5 * u.x + 2 * r.x, 20 + 5 * u.y + 2 * r.y, 30 + 5 * u.z + 2 * r.z)));
	}
}


OO_TEST(slice24TrackOntoTarget)
{
	{
		SetUp();
		TestShip *ship = MakeLateSliceShip("tracker");
		TestShip *other = MakeLateSliceShip("tracked");
		if (ship != nullptr)  ship->setOrientation(kIdentityQuaternion);
		SetFlightControls24(ship, 0.5f);

		// No target: nothing changes.
		if (ship != nullptr)  ship->trackOntoTarget(0.1, 0);
		OO_CHECK(!FlightControlsZero24(ship));

		// Already on target (the dot product is inside the target's cone): nothing changes.
		if (ship != nullptr)  ship->addTarget(other);
		SetPosition24(other, make_HPvector(1000, 0, 0));
		SetCollisionRadius24(other, 100);
		if (ship != nullptr)  ship->trackOntoTarget(0.1, 1);
		OO_CHECK(!FlightControlsZero24(ship));
		OO_CHECK(fabs((ship != nullptr ? ship->forwardVector() : Vector{}).z) > 0.999);

		// Otherwise it turns onto the line to the target (the x axis) and stops turning.
		if (ship != nullptr)  ship->trackOntoTarget(0.1, 0);
		Vector f = (ship != nullptr ? ship->forwardVector() : Vector{});
		OO_CHECK(fabs(fabs(f.x) - 1) < 1e-4 && fabs(f.y) < 1e-4 && fabs(f.z) < 1e-4);
		OO_CHECK(FlightControlsZero24(ship));
	}
}


OO_TEST(slice24BallTrackLeadingTarget)
{
	{
		SetUp();
		TestShip *ship = MakeLateSliceShip("turret");
		TestShip *other = MakeLateSliceShip("aimed-at");
		OO_CHECK((ship != nullptr ? ship->ballTrackLeadingTarget(0.1, nullptr) : 0.0) == -2.0);
		SetPosition24(other, make_HPvector(0, 0, 1000));
		SetWeaponRange24(ship, 500);
		OO_CHECK((ship != nullptr ? ship->ballTrackLeadingTarget(0.1, other) : 0.0) == -2.0);	// out of range
	}
}


// --- Slice 25: evasive jink, primary and side target tracking (bead oo-k6wuw). Written against the
// Objective-C API and run on the unconverted slice first.

namespace {

void SetAccuracy25(ShipEntity *s, GLfloat a)	{ s->accuracy = a; }
Vector Jink25(ShipEntity *s)					{ return s->jink; }
void SetFrustration25(ShipEntity *s, GLfloat f)	{ s->frustration = f; }
GLfloat Frustration25(ShipEntity *s)			{ return s->frustration; }

}	// namespace


OO_TEST(slice25SetEvasiveJink)
{
	{
		SetUp();
		TestShip *ship = MakeLateSliceShip("jinker");

		// An awful pilot does not jink.
		SetAccuracy25(ship, COMBAT_AI_ISNT_AWFUL - 1);
		if (ship != nullptr)  ship->setEvasiveJink(400);
		OO_CHECK(vector_equal(Jink25(ship), kZeroVector));

		// Otherwise x and y are well away from zero, and z is what was asked for.
		SetAccuracy25(ship, COMBAT_AI_ISNT_AWFUL + 1);
		for (int i = 0; i < 50; i++)
		{
			if (ship != nullptr)  ship->setEvasiveJink(400);
			Vector j = Jink25(ship);
			OO_CHECK(fabs(j.x) >= 128.0 && fabs(j.x) <= 256.0);
			OO_CHECK(fabs(j.y) >= 128.0 && fabs(j.y) <= 256.0);
			OO_CHECK(j.z == 400);
		}
	}
}


// With no target, each of them gives up: the ship goes idle and the tracking answers 0.
OO_TEST(slice25NoTargetGoesIdle)
{
	{
		SetUp();
		TestShip *ship = MakeLateSliceShip("aimless");

		if (ship != nullptr)  ship->setBehaviour(BEHAVIOUR_ATTACK_TARGET);
		SetFrustration25(ship, 2);
		if (ship != nullptr)  ship->evasiveAction(0.1);
		OO_CHECK((ship != nullptr ? ship->getBehaviour() : OOBehaviour{}) == BEHAVIOUR_IDLE && Frustration25(ship) == 0);

		if (ship != nullptr)  ship->setBehaviour(BEHAVIOUR_ATTACK_TARGET);
		OO_CHECK((ship != nullptr ? ship->trackPrimaryTarget(0.1, NO) : 0.0) == 0.0);
		OO_CHECK((ship != nullptr ? ship->getBehaviour() : OOBehaviour{}) == BEHAVIOUR_IDLE);

		if (ship != nullptr)  ship->setBehaviour(BEHAVIOUR_ATTACK_TARGET);
		OO_CHECK((ship != nullptr ? ship->trackSideTarget(0.1, YES) : 0.0) == 0.0);
		OO_CHECK((ship != nullptr ? ship->getBehaviour() : OOBehaviour{}) == BEHAVIOUR_IDLE);
	}
}


// A target the ship can no longer track (out of scanner range) is lost the same way.
OO_TEST(slice25TargetOutOfRangeGoesIdle)
{
	{
		SetUp();
		TestShip *ship = MakeLateSliceShip("short-sighted");
		TestShip *other = MakeLateSliceShip("far-away");
		SetScannerRange24(ship, 100);
		SetPosition24(other, make_HPvector(0, 0, 1000));

		if (ship != nullptr)  ship->addTarget(other);
		if (ship != nullptr)  ship->setBehaviour(BEHAVIOUR_ATTACK_TARGET);
		OO_CHECK((ship != nullptr ? ship->trackPrimaryTarget(0.1, NO) : 0.0) == 0.0);
		OO_CHECK((ship != nullptr ? ship->getBehaviour() : OOBehaviour{}) == BEHAVIOUR_IDLE && (ship != nullptr ? ship->primaryTarget() : (Entity *)nullptr) == nil);

		if (ship != nullptr)  ship->addTarget(other);
		if (ship != nullptr)  ship->setBehaviour(BEHAVIOUR_ATTACK_TARGET);
		OO_CHECK((ship != nullptr ? ship->trackSideTarget(0.1, NO) : 0.0) == 0.0);
		OO_CHECK((ship != nullptr ? ship->getBehaviour() : OOBehaviour{}) == BEHAVIOUR_IDLE && (ship != nullptr ? ship->primaryTarget() : (Entity *)nullptr) == nil);
	}
}


// --- Slice 26: missile and destination tracking, collision exceptions, defence targets, ranges
// (bead oo-v92af). Written against the Objective-C API and run on the unconverted slice first.

namespace {

void SetUpVectors26(ShipEntity *s, Vector up, Vector right)	{ s->v_up = up; s->v_right = right; }
void SetMaxFlightRoll26(ShipEntity *s, GLfloat r)			{ s->max_flight_roll = r; }
void SetCollisionRadius26(Entity *e, GLfloat r)				{ e->collision_radius = r; }

}	// namespace


OO_TEST(slice26RollToMatchUp)
{
	{
		SetUp();
		TestShip *ship = MakeLateSliceShip("roller");
		SetMaxFlightRoll26(ship, 2);
		SetUpVectors26(ship, kBasisYVector, kBasisXVector);

		// Already up: the match roll, its sign flipped for a ship that is not the player.
		OO_CHECK(fabs((ship != nullptr ? ship->rollToMatchUp(kBasisYVector, 0.5f) : 0.0f) - (-0.5f)) < 1e-6);
		// Upside down: the same.
		OO_CHECK(fabs((ship != nullptr ? ship->rollToMatchUp(vector_flip(kBasisYVector), 0.5f) : 0.0f) - (-0.5f)) < 1e-6);
		// Up is to the right (sin 1 flipped to -1): the roll decreases by the full max.
		OO_CHECK(fabs((ship != nullptr ? ship->rollToMatchUp(kBasisXVector, 0.5f) : 0.0f) - (-2.0f)) < 1e-6);
		// Up is to the left: it increases by it.
		OO_CHECK(fabs((ship != nullptr ? ship->rollToMatchUp(vector_flip(kBasisXVector), 0.5f) : 0.0f) - 2.0f) < 1e-6);
	}
}


OO_TEST(slice26Ranges)
{
	{
		SetUp();
		TestShip *ship = MakeLateSliceShip("ranger");
		TestShip *other = MakeLateSliceShip("ranged");
		SetPosition24(ship, make_HPvector(0, 0, 0));
		SetDestination24(ship, make_HPvector(0, 3, 4));
		OO_CHECK(fabs((ship != nullptr ? ship->rangeToDestination() : 0.0f) - 5.0f) < 1e-5);

		OO_CHECK((ship != nullptr ? ship->rangeToSecondaryTarget(nullptr) : 0.0) == 0.0);
		OO_CHECK((ship != nullptr ? ship->rangeToPrimaryTarget() : 0.0) == 0.0);		// no target
		OO_CHECK((ship != nullptr ? ship->approachAspectToPrimaryTarget() : 0.0) == 0.0);

		SetPosition24(other, make_HPvector(0, 0, 100));
		SetCollisionRadius26(ship, 10);
		SetCollisionRadius26(other, 15);
		OO_CHECK(fabs((ship != nullptr ? ship->rangeToSecondaryTarget(other) : 0.0) - 75.0) < 1e-6);
		if (ship != nullptr)  ship->addTarget(other);
		OO_CHECK(fabs((ship != nullptr ? ship->rangeToPrimaryTarget() : 0.0) - 75.0) < 1e-6);

		// Approach aspect: the target's forward vector against the direction from it to us.
		if (other != nullptr)  other->setOrientation(kIdentityQuaternion);
		Vector f = (other != nullptr ? other->forwardVector() : Vector{});
		Vector delta = vector_normal(HPVectorToVector(HPvector_subtract(make_HPvector(0, 0, 0), make_HPvector(0, 0, 100))));
		OO_CHECK(fabs((ship != nullptr ? ship->approachAspectToPrimaryTarget() : 0.0) - dot_product(delta, f)) < 1e-6);

		OO_CHECK(!(ship != nullptr ? ship->hasProximityAlertIgnoringTarget(NO) : false));	// no proximity alert
		OO_CHECK(!(ship != nullptr ? ship->hasProximityAlertIgnoringTarget(YES) : false));
	}
}


OO_TEST(slice26CollisionExceptions)
{
	{
		SetUp();
		TestShip *ship = MakeLateSliceShip("excepting");
		TestShip *a = MakeLateSliceShip("a");
		TestShip *b = MakeLateSliceShip("b");
		OO_CHECK(!(ship != nullptr ? ship->collisionExceptedFor(a) : false) && (ship != nullptr ? ship->collisionExceptions() : std::vector<oo::EntityHold>()).empty());
		if (ship != nullptr)  ship->removeCollisionException(a);		// none yet: fine

		if (ship != nullptr)  ship->addCollisionException(a);
		if (ship != nullptr)  ship->addCollisionException(b);
		OO_CHECK((ship != nullptr ? ship->collisionExceptedFor(a) : false) && (ship != nullptr ? ship->collisionExceptedFor(b) : false));
		OO_CHECK((ship != nullptr ? ship->collisionExceptions() : std::vector<oo::EntityHold>()).size() == 2);

		if (ship != nullptr)  ship->removeCollisionException(a);
		OO_CHECK(!(ship != nullptr ? ship->collisionExceptedFor(a) : false) && (ship != nullptr ? ship->collisionExceptedFor(b) : false));
		auto left = (ship != nullptr ? ship->collisionExceptions() : std::vector<oo::EntityHold>());
		OO_CHECK(left.size() == 1 && left[0].get() == b);
	}
}


OO_TEST(slice26DefenseTargets)
{
	{
		SetUp();
		TestShip *ship = MakeLateSliceShip("defender");
		TestShip *a = MakeLateSliceShip("attacker-a");
		TestShip *b = MakeLateSliceShip("attacker-b");
		Entity *plain = oo::MadeEntity(oo::makeRef<Entity>());
		OO_CHECK((ship != nullptr ? ship->defenseTargetCount() : 0) == 0 && (ship != nullptr ? ship->allDefenseTargets() : std::vector<oo::EntityHold>()).empty() && (ship != nullptr ? ship->defenseTargets() : std::vector<oo::EntityHold>()).empty());
		if (ship != nullptr)  ship->validateDefenseTargets();		// none yet: fine

		OO_CHECK(!(ship != nullptr ? ship->addDefenseTarget(nullptr) : false));
		OO_CHECK(!(ship != nullptr ? ship->addDefenseTarget(plain) : false));		// not a ship
		OO_CHECK((ship != nullptr ? ship->addDefenseTarget(a) : false));
		OO_CHECK(!(ship != nullptr ? ship->addDefenseTarget(a) : false));		// already one
		OO_CHECK((ship != nullptr ? ship->addDefenseTarget(b) : false));
		OO_CHECK((ship != nullptr ? ship->defenseTargetCount() : 0) == 2 && (ship != nullptr ? ship->isDefenseTarget(a) : false) && (ship != nullptr ? ship->isDefenseTarget(b) : false));
		OO_CHECK((ship != nullptr ? ship->allDefenseTargets() : std::vector<oo::EntityHold>()).size() == 2 && (ship != nullptr ? ship->defenseTargets() : std::vector<oo::EntityHold>()).size() == 2);

		// A dead one is dropped by the validation.
		if (a != nullptr)  a->setStatus(STATUS_DEAD);
		if (ship != nullptr)  ship->validateDefenseTargets();
		OO_CHECK(!(ship != nullptr ? ship->isDefenseTarget(a) : false) && (ship != nullptr ? ship->isDefenseTarget(b) : false) && (ship != nullptr ? ship->defenseTargetCount() : 0) == 1);

		if (ship != nullptr)  ship->removeDefenseTarget(b);
		OO_CHECK((ship != nullptr ? ship->defenseTargetCount() : 0) == 0);

		// At most MAX_TARGETS.
		std::vector<TestShip *> many;
		for (unsigned i = 0; i < MAX_TARGETS; i++)
		{
			many.push_back(MakeLateSliceShip("many"));
			OO_CHECK((ship != nullptr ? ship->addDefenseTarget(many.back()) : false));
		}
		OO_CHECK(!(ship != nullptr ? ship->addDefenseTarget(b) : false));
		if (ship != nullptr)  ship->removeAllDefenseTargets();
		OO_CHECK((ship != nullptr ? ship->defenseTargetCount() : 0) == 0);
	}
}


// --- Slice 27: aim tolerance, sun glare, main weapons and turret fire, laser colours (bead
// oo-pnfyp). Written against the Objective-C API and run on the unconverted slice first.

namespace {

void SetAim27(ShipEntity *s, GLfloat tolerance, GLfloat accuracy, OOWeaponFacing facing)
{
	s->aim_tolerance = tolerance;
	s->accuracy = accuracy;
	s->currentWeaponFacing = facing;
	s->_missed_shots = 0;
	s->isSunlit = false;
}
GLfloat ExpectedAim27(GLfloat basic_aim, GLfloat best_cos)
{
	GLfloat max_cos = sqrt(1 - (basic_aim * basic_aim / 100000000.0));
	return max_cos < best_cos ? max_cos : best_cos;
}
void SetShotTime27(ShipEntity *s, OOTimeDelta t)	{ s->shot_time = t; }
void SetRechargeRate27(ShipEntity *s, float r)	{ s->weapon_recharge_rate = r; }

}	// namespace


OO_TEST(slice27CurrentAimTolerance)
{
	{
		SetUp();
		TestShip *ship = MakeLateSliceShip("gunner");

		// An awful shot, forward: the tolerance as it is.
		SetAim27(ship, 1000, COMBAT_AI_ISNT_AWFUL - 1, WEAPON_FACING_FORWARD);
		OO_CHECK(fabs((ship != nullptr ? ship->currentAimTolerance() : 0.0f) - ExpectedAim27(1000, 0.99999)) < 1e-7);
		// Aft: a third worse.
		SetAim27(ship, 1000, COMBAT_AI_ISNT_AWFUL - 1, WEAPON_FACING_AFT);
		OO_CHECK(fabs((ship != nullptr ? ship->currentAimTolerance() : 0.0f) - ExpectedAim27(1000 * 1.3, 0.99999)) < 1e-7);
		// Better pilots: tighter, and tighter still after missing.
		SetAim27(ship, 1000, COMBAT_AI_ISNT_AWFUL, WEAPON_FACING_FORWARD);
		OO_CHECK(fabs((ship != nullptr ? ship->currentAimTolerance() : 0.0f) - ExpectedAim27(1000, 0.999999)) < 1e-7);
		if (ship != nullptr)  ship->adjustMissedShots(4);
		OO_CHECK((ship != nullptr ? ship->missedShots() : int{}) == 4);
		OO_CHECK(fabs((ship != nullptr ? ship->currentAimTolerance() : 0.0f) - ExpectedAim27(1000 / 2.0, 0.999999)) < 1e-7);
		// A side laser makes even a good pilot worse.
		SetAim27(ship, 1000, COMBAT_AI_ISNT_AWFUL, WEAPON_FACING_PORT);
		OO_CHECK(fabs((ship != nullptr ? ship->currentAimTolerance() : 0.0f) - ExpectedAim27(1000 * 1.3, 0.999999)) < 1e-7);
		// Deadly shots.
		SetAim27(ship, 1000, COMBAT_AI_TRACKS_CLOSER, WEAPON_FACING_FORWARD);
		OO_CHECK(fabs((ship != nullptr ? ship->currentAimTolerance() : 0.0f) - ExpectedAim27(1000 / 5.0, 0.9999999)) < 1e-7);
	}
}


OO_TEST(slice27ShotTimeAndTurret)
{
	{
		SetUp();
		TestShip *ship = MakeLateSliceShip("turret-gun");
		SetShotTime27(ship, 3);
		OO_CHECK((ship != nullptr ? ship->shotTime() : OOTimeDelta{}) == 3);
		if (ship != nullptr)  ship->resetShotTime();
		OO_CHECK((ship != nullptr ? ship->shotTime() : OOTimeDelta{}) == 0);

		// Not recharged: no shot.
		SetRechargeRate27(ship, 1);
		SetWeaponRange24(ship, 1000);
		OO_CHECK(!(ship != nullptr ? ship->fireTurretCannon(10) : false));
		// Recharged, but out of range (more than 1% past it): no shot either.
		SetShotTime27(ship, 2);
		OO_CHECK(!(ship != nullptr ? ship->fireTurretCannon(1011) : false));
		OO_CHECK((ship != nullptr ? ship->shotTime() : OOTimeDelta{}) == 2);
	}
}


OO_TEST(slice27Colours)
{
	{
		SetUp();
		TestShip *ship = MakeLateSliceShip("painted");
		oo::Ref<OOColor>	red = OOColor::redColor();
		oo::Ref<OOColor>	blue = OOColor::blueColor();
		if (ship != nullptr)  ship->setLaserColor(red.get());
		if (ship != nullptr)  ship->setExhaustEmissiveColor(blue.get());
		OO_CHECK((ship != nullptr ? ship->laserColor() : (OOColor *)nullptr) == red && (ship != nullptr ? ship->exhaustEmissiveColor() : (OOColor *)nullptr) == blue);
		// nil is ignored.
		if (ship != nullptr)  ship->setLaserColor(nullptr);
		if (ship != nullptr)  ship->setExhaustEmissiveColor(nullptr);
		OO_CHECK((ship != nullptr ? ship->laserColor() : (OOColor *)nullptr) == red && (ship != nullptr ? ship->exhaustEmissiveColor() : (OOColor *)nullptr) == blue);
	}
}


// --- Slice 28: laser shots, missed shots, sparks, missile launch decision (bead oo-40ocf). Written
// against the Objective-C API and run on the unconverted slice first.

namespace {

void SetBoundingBox28(Entity *e, BoundingBox bb)	{ e->boundingBox = bb; }
void SetScaleFactor28(ShipEntity *s, GLfloat f)	{ s->_scaleFactor = f; }
void SetMissiles28(ShipEntity *s, unsigned n)		{ s->missiles = n; }

}	// namespace


OO_TEST(slice28MissedShots)
{
	{
		SetUp();
		TestShip *ship = MakeLateSliceShip("misser");
		TestShip *sub = MakeLateSliceShip("sub-misser");
		OO_CHECK((ship != nullptr ? ship->missedShots() : int{}) == 0);
		if (ship != nullptr)  ship->adjustMissedShots(3);
		if (ship != nullptr)  ship->adjustMissedShots(2);
		OO_CHECK((ship != nullptr ? ship->missedShots() : int{}) == 5);
		if (ship != nullptr)  ship->adjustMissedShots(-10);		// never below zero
		OO_CHECK((ship != nullptr ? ship->missedShots() : int{}) == 0);

		// A subentity's count is its owner's.
		if (ship != nullptr)  ship->addSubEntity(sub);
		if (sub != nullptr)  sub->adjustMissedShots(2);
		OO_CHECK((ship != nullptr ? ship->missedShots() : int{}) == 2 && (sub != nullptr ? sub->missedShots() : int{}) == 2);
		if (ship != nullptr)  ship->clearSubEntities();
	}
}


OO_TEST(slice28MissileLaunchPosition)
{
	{
		SetUp();
		TestShip *ship = MakeLateSliceShip("launcher");
		BoundingBox bb = { { -10, -20, -30 }, { 10, 20, 30 } };
		SetBoundingBox28(ship, bb);
		SetScaleFactor28(ship, 1);
		// No missile_launch_position: 4 m below and 1 m ahead of the bounding box.
		Vector start = (ship != nullptr ? ship->missileLaunchPosition() : Vector{});
		OO_CHECK(start.x == 0 && start.y == -24 && start.z == 31);
		// Scaled.
		SetScaleFactor28(ship, 2);
		start = (ship != nullptr ? ship->missileLaunchPosition() : Vector{});
		OO_CHECK(start.x == 0 && start.y == -48 && start.z == 62);
	}
}


OO_TEST(slice28ConsiderFiringMissileWithoutMissiles)
{
	{
		SetUp();
		TestShip *ship = MakeLateSliceShip("unarmed");
		SetMissiles28(ship, 0);
		if (ship != nullptr)  ship->considerFiringMissile(0.1);		// nothing to fire: nothing happens
		OO_CHECK((ship != nullptr ? ship->missileCount() : 0) == 0);
	}
}


// --- Slice 29: missile firing, ECM, cloak, cascade mine, escape capsule, cargo dumping (bead
// oo-g900k). Written against the Objective-C API and run on the unconverted slice first.

namespace {

bool CloakActive29(ShipEntity *s)	{ return s->cloaking_device_active; }

}	// namespace


OO_TEST(slice29MissileFlagAndLoadTime)
{
	{
		SetUp();
		TestShip *ship = MakeLateSliceShip("missile-ish");
		OO_CHECK(!(ship != nullptr ? ship->isMissileFlagSet() : false));
		if (ship != nullptr)  ship->setIsMissileFlag(YES);
		OO_CHECK((ship != nullptr ? ship->isMissileFlagSet() : false));
		if (ship != nullptr)  ship->setIsMissileFlag(NO);
		OO_CHECK(!(ship != nullptr ? ship->isMissileFlagSet() : false));

		if (ship != nullptr)  ship->setMissileLoadTime(2.5);
		OO_CHECK((ship != nullptr ? ship->missileLoadTime() : OOTimeDelta{}) == 2.5);
		if (ship != nullptr)  ship->setMissileLoadTime(-1);		// never negative
		OO_CHECK((ship != nullptr ? ship->missileLoadTime() : OOTimeDelta{}) == 0);
	}
}


// Without the equipment, ECM and the cloak do nothing.
OO_TEST(slice29NoEquipment)
{
	{
		SetUp();
		TestShip *ship = MakeLateSliceShip("plain-hull");
		OO_CHECK(!(ship != nullptr ? ship->fireECM() : false));
		OO_CHECK(!(ship != nullptr ? ship->activateCloakingDevice() : false) && !CloakActive29(ship));
		if (ship != nullptr)  ship->deactivateCloakingDevice();
		OO_CHECK(!CloakActive29(ship));
		if (ship != nullptr)  ship->noticeECM();		// no missiles: nothing to delay
	}
}


// With an empty hold, there is nothing to dump.
OO_TEST(slice29DumpEmptyHold)
{
	{
		SetUp();
		TestShip *ship = MakeLateSliceShip("empty-hold");
		OO_CHECK((ship != nullptr ? ship->dumpCargoItem(std::nullopt) : (::ShipEntity *)nil) == nil);
		OO_CHECK((ship != nullptr ? ship->dumpCargoItem(std::optional<std::string>("food")) : (::ShipEntity *)nil) == nil);
		if (ship != nullptr)  ship->dumpCargo();
	}
}


// --- Slice 30: collisions, velocity, tractoring and scooping (bead oo-ogoct). Written against the
// Objective-C API and run on the unconverted slice first.


namespace {

void SetFlightSpeed30(ShipEntity *s, GLfloat v)	{ s->flightSpeed = v; }
Vector RawVelocity30(Entity *e)					{ return e->velocity; }
void SetMass30(Entity *e, GLfloat m)			{ e->mass = m; }
bool Near30(Vector a, Vector b)					{ return distance2(a, b) < 1e-8; }

}	// namespace


OO_TEST(slice30Velocity)
{
	{
		SetUp();
		TestShip *ship = MakeLateSliceShip("mover");
		if (ship != nullptr)  ship->setOrientation(kIdentityQuaternion);
		Vector f = (ship != nullptr ? ship->forwardVector() : Vector{});
		SetFlightSpeed30(ship, 10);
		OO_CHECK(Near30((ship != nullptr ? ship->thrustVector() : Vector{}), vector_multiply_scalar(f, 10)));

		// The velocity is the entity's plus the thrust.
		if (ship != nullptr)  ship->setVelocity(make_vector(1, 2, 3));
		OO_CHECK(Near30((ship != nullptr ? ship->getVelocity() : Vector{}), vector_add(make_vector(1, 2, 3), vector_multiply_scalar(f, 10))));
		// From C++, the root's virtual reaches the ship's.
		OO_CHECK(Near30(ship->getVelocity(), (ship != nullptr ? ship->getVelocity() : Vector{})));

		// Setting the total velocity sets the entity's to what is left after the thrust.
		if (ship != nullptr)  ship->setTotalVelocity(make_vector(0, 0, 0));
		OO_CHECK(Near30(RawVelocity30(ship), vector_flip(vector_multiply_scalar(f, 10))));
		OO_CHECK(Near30((ship != nullptr ? ship->getVelocity() : Vector{}), kZeroVector));

		if (ship != nullptr)  ship->setVelocity(kZeroVector);
		if (ship != nullptr)  ship->adjustVelocity(make_vector(1, 0, 0));
		if (ship != nullptr)  ship->adjustVelocity(make_vector(0, 2, 0));
		OO_CHECK(Near30(RawVelocity30(ship), make_vector(1, 2, 0)));

		if (ship != nullptr)  ship->setVelocity(kZeroVector);
		SetMass30(ship, 4);
		if (ship != nullptr)  ship->addImpactMoment(make_vector(8, 0, 0), 0.5f);
		OO_CHECK(Near30(RawVelocity30(ship), make_vector(1, 0, 0)));
	}
}


OO_TEST(slice30ScoopingAndCollisions)
{
	{
		SetUp();
		TestShip *ship = MakeLateSliceShip("scooper");
		TestShip *other = MakeLateSliceShip("cargo");
		OO_CHECK(!(ship != nullptr ? ship->canScoop(nullptr) : false));
		OO_CHECK(!(ship != nullptr ? ship->canScoop(other) : false));		// no cargo scoop
		if (ship != nullptr)  ship->suppressTargetLost();		// does nothing
		if (ship != nullptr)  ship->manageCollisions();		// nothing colliding: nothing happens
		OO_CHECK((ship != nullptr ? ship->status() : OOEntityStatus{}) == STATUS_IN_FLIGHT);
	}
}


// --- Slice 31: cascades, energy / scrape / heat damage, abandoning ship, docks, wormholes,
// witchspace (bead oo-gx86h). Written against the Objective-C API and run on the unconverted slice
// first.

namespace {

void SetEnergy31(Entity *e, GLfloat energy, GLfloat maxEnergy)	{ e->energy = energy; e->maxEnergy = maxEnergy; }
GLfloat Energy31(Entity *e)									{ return e->energy; }
bool ThrowSparks31(Entity *e)									{ return e->throw_sparks; }

}	// namespace


OO_TEST(slice31DamageThatDoesNothing)
{
	{
		SetUp();
		TestShip *ship = MakeLateSliceShip("tough");
		TestShip *other = MakeLateSliceShip("rammer");
		SetEnergy31(ship, 100, 100);

		// Nothing, or a negative amount: no damage.
		if (ship != nullptr)  ship->takeEnergyDamage(0, other, other, "");
		if (ship != nullptr)  ship->takeEnergyDamage(-5, other, other, "");
		OO_CHECK(Energy31(ship) == 100);
		// From C++, the root's virtual reaches the ship's.
		ship->takeEnergyDamage(0, other, nullptr, "");
		OO_CHECK(Energy31(ship) == 100);

		// No scrapes while launching.
		if (other != nullptr)  other->setStatus(STATUS_LAUNCHING);
		if (ship != nullptr)  ship->takeScrapeDamage(10, other);
		OO_CHECK(Energy31(ship) == 100);

		// The dead take nothing.
		if (ship != nullptr)  ship->setStatus(STATUS_DEAD);
		if (ship != nullptr)  ship->takeEnergyDamage(10, other, other, "");
		if (ship != nullptr)  ship->takeScrapeDamage(10, other);
		if (ship != nullptr)  ship->takeHeatDamage(10);
		OO_CHECK(Energy31(ship) == 100);
	}
}


// A subentity of a ship that is not frangible takes no heat damage. (Damage that is taken sends the
// shipTakingDamage event with JavaScript values, which the test's empty context cannot make.)
OO_TEST(slice31HeatDamageToAFixedSubentity)
{
	{
		SetUp();
		TestShip *ship = MakeLateSliceShip("fixed-mount");
		TestShip *sub = MakeLateSliceShip("fixed-turret");
		if (ship != nullptr)  ship->addSubEntity(sub);
		SetEnergy31(sub, 100, 100);
		OO_CHECK(!(ship != nullptr ? ship->getIsFrangible() : false));
		if (sub != nullptr)  sub->takeHeatDamage(10);
		OO_CHECK(Energy31(sub) == 100 && !ThrowSparks31(sub));
		if (ship != nullptr)  ship->clearSubEntities();
	}
}


OO_TEST(slice31NoCascadeWithEnergyToSpare)
{
	{
		SetUp();
		TestShip *ship = MakeLateSliceShip("stable");
		SetEnergy31(ship, 100, 100);
		OO_CHECK(!(ship != nullptr ? ship->cascadeIfAppropriateWithDamageAmount(50, nullptr) : false));	// survives the hit
		SetEnergy31(ship, 5, 100);
		OO_CHECK(!(ship != nullptr ? ship->cascadeIfAppropriateWithDamageAmount(50, nullptr) : false));	// too little energy to go pop
		if (ship != nullptr)  ship->leaveDock(nullptr);		// no station: nothing
	}
}


// --- Slice 32: witchspace effects, offences, lights, escort formation and deployment, nearest
// stations (bead oo-5e0ny). Written against the Objective-C API and run on the unconverted slice
// first.


namespace {

bool EscortPositionsValid32(ShipEntity *s)	{ return ShipEntityTestAccess::EscortPositionsValid(s); }
void SetEscortPositionsValid32(ShipEntity *s, bool v)	{ ShipEntityTestAccess::EscortPositionsValid(s) = v; }

}	// namespace


OO_TEST(slice32Lights)
{
	{
		SetUp();
		TestShip *ship = MakeLateSliceShip("lit");
		TestShip *sub = MakeLateSliceShip("lit-turret");
		if (ship != nullptr)  ship->addSubEntity(sub);
		if (ship != nullptr)  ship->switchLightsOn();
		OO_CHECK((ship != nullptr ? ship->lightsActive() : false) && (sub != nullptr ? sub->lightsActive() : false));
		if (ship != nullptr)  ship->switchLightsOff();
		OO_CHECK(!(ship != nullptr ? ship->lightsActive() : false) && !(sub != nullptr ? sub->lightsActive() : false));
		if (ship != nullptr)  ship->clearSubEntities();
	}
}


OO_TEST(slice32Destinations)
{
	{
		SetUp();
		TestShip *ship = MakeLateSliceShip("goer");
		SetFrustration24(ship, 4);
		if (ship != nullptr)  ship->setEscortDestination(make_HPvector(1, 1, 1));		// an escort's: frustration stays
		OO_CHECK(Near24((ship != nullptr ? ship->destination() : HPVector{}), make_HPvector(1, 1, 1)) && Frustration24(ship) == 4);
		if (ship != nullptr)  ship->setDestination(make_HPvector(2, 2, 2));			// a new destination: none
		OO_CHECK(Near24((ship != nullptr ? ship->destination() : HPVector{}), make_HPvector(2, 2, 2)) && Frustration24(ship) == 0);
	}
}


OO_TEST(slice32EscortFormation)
{
	{
		SetUp();
		TestShip *ship = MakeLateSliceShip("mother");
		TestShip *other = MakeLateSliceShip("would-be-escort");
		SetEscortPositionsValid32(ship, true);
		if (ship != nullptr)  ship->updateEscortFormation();
		OO_CHECK(!EscortPositionsValid32(ship));

		// With no positions set, every escort position is the ship's own, however big the index.
		SetPosition24(ship, make_HPvector(5, 6, 7));
		if (ship != nullptr)  ship->setOrientation(kIdentityQuaternion);
		OO_CHECK(Near24((ship != nullptr ? ship->coordinatesForEscortPosition(0) : HPVector{}), make_HPvector(5, 6, 7)));
		OO_CHECK(Near24((ship != nullptr ? ship->coordinatesForEscortPosition(1000) : HPVector{}), make_HPvector(5, 6, 7)));

		// Escorts must share the scan class.
		if (other != nullptr)  other->setScanClass(CLASS_POLICE);
		OO_CHECK(!(ship != nullptr ? ship->canAcceptEscort(other) : false));
	}
}


OO_TEST(slice32PoliceAreNotOffenders)
{
	{
		SetUp();
		TestShip *ship = MakeLateSliceShip("copper");
		if (ship != nullptr)  ship->setScanClass(CLASS_POLICE);
		if (ship != nullptr)  ship->markAsOffender(64);
		if (ship != nullptr)  ship->markAsOffender(64, kOOLegalStatusReasonByScript);
		OO_CHECK((ship != nullptr ? ship->getBounty() : 0) == 0);
	}
}


// --- Slice 33: landing, docking abort, broadcasts and comms, fines, AI messages, spawning, close
// contacts, salvage (bead oo-tz2ra). Written against the Objective-C API and run on the unconverted
// slice first.


namespace {

void SetBounty33(ShipEntity *s, OOCreditsQuantity b)	{ s->bounty = b; }

}	// namespace


OO_TEST(slice33Fines)
{
	{
		SetUp();
		TestShip *ship = MakeLateSliceShip("clean");
		TestShip *crook = MakeLateSliceShip("crook");
		OO_CHECK(!(ship != nullptr ? ship->markedForFines() : false));
		OO_CHECK(!(ship != nullptr ? ship->markForFines() : false) && !(ship != nullptr ? ship->markedForFines() : false));	// clean: nothing to fine

		SetBounty33(crook, 50);
		OO_CHECK((crook != nullptr ? crook->markForFines() : false) && (crook != nullptr ? crook->markedForFines() : false));
		OO_CHECK(!(crook != nullptr ? crook->markForFines() : false) && (crook != nullptr ? crook->markedForFines() : false));	// never twice
	}
}


OO_TEST(slice33SmallAccessors)
{
	{
		SetUp();
		TestShip *ship = MakeLateSliceShip("contact");
		OO_CHECK((ship != nullptr ? ship->getDockingInstructions() : oo::PList()).isNull());

		OO_CHECK(!(ship != nullptr ? ship->getTrackCloseContacts() : false));
		if (ship != nullptr)  ship->setTrackCloseContacts(YES);
		OO_CHECK((ship != nullptr ? ship->getTrackCloseContacts() : false));
		if (ship != nullptr)  ship->setTrackCloseContacts(NO);
		OO_CHECK(!(ship != nullptr ? ship->getTrackCloseContacts() : false));

		// Mining needs the behaviour and a mining laser.
		if (ship != nullptr)  ship->setBehaviour(BEHAVIOUR_ATTACK_MINING_TARGET);
		OO_CHECK(!(ship != nullptr ? ship->isMining() : false));
		if (ship != nullptr)  ship->setBehaviour(BEHAVIOUR_IDLE);
		OO_CHECK(!(ship != nullptr ? ship->isMining() : false));

		if (ship != nullptr)  ship->spawn("just-one-token");		// bad syntax: logged, nothing spawned
		if (ship != nullptr)  ship->spawn("a b c");
	}
}


OO_TEST(slice33FindBoundingBoxRelativeTo)
{
	{
		SetUp();
		TestShip *ship = MakeLateSliceShip("boxed");
		TestShip *other = MakeLateSliceShip("reference");
		SetPosition24(other, make_HPvector(100, 0, 0));
		// Relative to another entity is relative to its position; to nil, to our own.
		BoundingBox a = (ship != nullptr ? ship->findBoundingBoxRelativeTo(other, kBasisXVector, kBasisYVector, kBasisZVector) : BoundingBox{});
		BoundingBox b = (ship != nullptr ? ship->findBoundingBoxRelativeToPosition(make_HPvector(100, 0, 0), kBasisXVector, kBasisYVector, kBasisZVector) : BoundingBox{});
		OO_CHECK(vector_equal(a.min, b.min) && vector_equal(a.max, b.max));
		BoundingBox c = (ship != nullptr ? ship->findBoundingBoxRelativeTo(nullptr, kBasisXVector, kBasisYVector, kBasisZVector) : BoundingBox{});
		BoundingBox d = (ship != nullptr ? ship->findBoundingBoxRelativeToPosition((ship != nullptr ? ship->getPosition() : HPVector{}), kBasisXVector, kBasisYVector, kBasisZVector) : BoundingBox{});
		OO_CHECK(vector_equal(c.min, d.min) && vector_equal(c.max, d.max));
	}
}


// --- Slice 34: salvage pilot, debug dump, script info, demo ship, script events and AI reactions,
// alert condition, shader helpers (bead oo-nkyn3). Written against the Objective-C API and run on
// the unconverted slice first.

#include "OOJSPropID.h"



namespace {

Quaternion DemoStartOrientation34(ShipEntity *s)	{ return ShipEntityTestAccess::DemoStartOrientation(s); }
OOScalar DemoRate34(ShipEntity *s)					{ return ShipEntityTestAccess::DemoRate(s); }

}	// namespace


OO_TEST(slice34ScriptInfo)
{
	{
		SetUp();
		TestShip *ship = MakeLateSliceShip("scripted");
		OO_CHECK((ship != nullptr ? ship->getScript() : (OOScript *)nullptr) == nil);
		// None: an empty dictionary, not null.
		oo::PList info = (ship != nullptr ? ship->getScriptInfo() : oo::PList());
		OO_CHECK(info.getIf<oo::PList::Dict>() != nullptr && info.getIf<oo::PList::Dict>()->empty());

		if (ship != nullptr)  ship->overrideScriptInfo(oo::PList(oo::PList::Dict{ { "a", oo::PList(1.0) }, { "b", oo::PList(2.0) } }));
		OO_CHECK((ship != nullptr ? ship->getScriptInfo() : oo::PList()).get<double>("a", 0) == 1.0 && (ship != nullptr ? ship->getScriptInfo() : oo::PList()).get<double>("b", 0) == 2.0);
		// An override replaces the entries it has and keeps the others.
		if (ship != nullptr)  ship->overrideScriptInfo(oo::PList(oo::PList::Dict{ { "b", oo::PList(3.0) }, { "c", oo::PList(4.0) } }));
		info = (ship != nullptr ? ship->getScriptInfo() : oo::PList());
		OO_CHECK(info.get<double>("a", 0) == 1.0 && info.get<double>("b", 0) == 3.0 && info.get<double>("c", 0) == 4.0);
		// A null override changes nothing.
		if (ship != nullptr)  ship->overrideScriptInfo(oo::PList());
		OO_CHECK((ship != nullptr ? ship->getScriptInfo() : oo::PList()).get<double>("b", 0) == 3.0);
	}
}


OO_TEST(slice34DemoShip)
{
	{
		SetUp();
		TestShip *ship = MakeLateSliceShip("demo");
		OO_CHECK(!(ship != nullptr ? ship->getIsDemoShip() : false));
		Quaternion q = { 0.5f, 0.5f, 0.5f, 0.5f };
		if (ship != nullptr)  ship->setOrientation(q);
		if (ship != nullptr)  ship->setDemoShip(0.25);
		OO_CHECK((ship != nullptr ? ship->getIsDemoShip() : false) && DemoRate34(ship) == 0.25);
		OO_CHECK(quaternion_equal(DemoStartOrientation34(ship), (ship != nullptr ? ship->getOrientation() : Quaternion{})));
		if (ship != nullptr)  ship->setDemoStartTime(12.5);
		OO_CHECK((ship != nullptr ? ship->getDemoStartTime() : OOTimeAbsolute{}) == 12.5);
	}
}


OO_TEST(slice34AlertConditionAndEvents)
{
	{
		SetUp();
		TestShip *ship = MakeLateSliceShip("alert");
		SetEnergy31(ship, 100, 100);
		OO_CHECK((ship != nullptr ? ship->alertCondition() : OOAlertCondition{}) == ALERT_CONDITION_YELLOW);		// NPCs are never green
		SetEnergy31(ship, 20, 100);
		OO_CHECK((ship != nullptr ? ship->alertCondition() : OOAlertCondition{}) == ALERT_CONDITION_RED);		// low on energy
		if (ship != nullptr)  ship->setStatus(STATUS_DOCKED);
		OO_CHECK((ship != nullptr ? ship->alertCondition() : OOAlertCondition{}) == ALERT_CONDITION_DOCKED);
		if (ship != nullptr)  ship->setStatus(STATUS_IN_FLIGHT);

		// The ship is its own shader entity when it is not a subentity.
		OO_CHECK((ship != nullptr ? ship->entityForShaderProperties() : (Entity *)nullptr) == ship);

		// No scripts, no AI: the events and messages go nowhere, harmlessly.
		if (ship != nullptr)  ship->doScriptEvent(OOJSID("shipSpawned"));
		if (ship != nullptr)  ship->doScriptEvent(OOJSID("shipSpawned"), ship);
		if (ship != nullptr)  ship->doScriptEvent(OOJSID("shipSpawned"), ship, nullptr);
		if (ship != nullptr)  ship->doScriptEvent(OOJSID("shipSpawned"), { oo::PList(1.0) });
		if (ship != nullptr)  ship->doScriptEvent(OOJSID("shipSpawned"), "NOTHING");
		if (ship != nullptr)  ship->doScriptEvent(OOJSID("shipSpawned"), ship, "NOTHING");
		if (ship != nullptr)  ship->sendAIMessage("NOTHING");
		if (ship != nullptr)  ship->reactToAIMessage("NOTHING", std::nullopt);
		if (ship != nullptr)  ship->doNothing();
		OO_CHECK((ship != nullptr ? ship->status() : OOEntityStatus{}) == STATUS_IN_FLIGHT);
	}
}


OO_TEST(slice34WeaponHelpers)
{
	{
		OO_CHECK(isWeaponNone(nil));
	}
}


// --- ShipEntityScriptMethods.mm (bead oo-42dr): the category ShipEntity (ScriptMethods) --------------
// The cases that do not reach the universe (it was never initialised here): ejecting nothing and
// spawning none. Ejecting or spawning a real ship needs the game's ship data, which the goldens run.

OO_TEST(scriptMethodsEjectAndSpawnNothing)
{
	{
		SetUp();
		TestShip *ship = MakeLateSliceShip("ejector");
		// std::nullopt ejects nothing, as nil did.
		OO_CHECK((ship != nullptr ? ship->ejectShipOfType(std::nullopt) : (::ShipEntity *)nil) == nil);
		OO_CHECK((ship != nullptr ? ship->ejectShipOfRole(std::nullopt) : (::ShipEntity *)nil) == nil);
		// A count of zero spawns nothing and answers an empty list.
		OO_CHECK((ship != nullptr ? ship->spawnShipsWithRole("trader", 0) : std::vector<oo::EntityHold>()).empty());
		OO_CHECK((ship != nullptr ? ship->status() : OOEntityStatus{}) == STATUS_IN_FLIGHT);
	}
}


// --- ShipEntityLoadRestore.mm (bead oo-kw44): the category ShipEntity (LoadRestore) -------------------
// The cases that reach neither the ship registry nor the universe: restoring from no dictionary.
// Saving a ship, and restoring one, look its key up in the ship registry, whose data the unit test
// does not load (it would scan for add-ons); the goldens' wormholes run those.

OO_TEST(loadRestoreFromNothing)
{
	{
		SetUp();
		// Null restores no ship, with or without fallback and a context, as nil did.
		OO_CHECK(ShipEntity::shipRestoredFromDictionary(oo::PList(), NO, nullptr) == nil);
		OO_CHECK(ShipEntity::shipRestoredFromDictionary(oo::PList(), YES, nullptr) == nil);
		OOShipSaveContext context;
		OO_CHECK(ShipEntity::shipRestoredFromDictionary(oo::PList(), YES, &context) == nil);
		OO_CHECK(context.nextGroupID == 0 && context.groups.empty() && context.groupsByID.empty());
	}
}


OO_TEST_MAIN()
