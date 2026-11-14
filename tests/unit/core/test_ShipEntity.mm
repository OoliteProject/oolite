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
#import "OOColor.h"
#import "OORoleSet.h"
#import "OOCharacter.h"
#import "AI.h"
#import "PlayerEntity.h"
#import "ShipEntityScriptMethods.h"
#import "ShipEntityLoadRestore.h"

#include "oo_test.hpp"

#include <cmath>
#include <initializer_list>
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
void SetFrustration(ShipEntity *s, GLfloat value)	{ s->_cxxShip->frustration = value; }
void SetPlanetForLanding(ShipEntity *s, OOUniversalID uid)	{ s->_cxxShip->planetForLanding = uid; }
void SetPreviousCondition(ShipEntity *s, const oo::PList &condition)	{ s->_cxxShip->previousCondition = condition; }
unsigned NextNavpoint(ShipEntity *s)	{ return s->_cxxShip->next_navpoint_index; }
GLfloat WeaponDamage(ShipEntity *s)	{ return s->_cxxShip->weapon_damage; }
OOAegisStatus AegisStatus(ShipEntity *s)	{ return s->_cxxShip->aegis_status; }
void SetAegisStatus(ShipEntity *s, OOAegisStatus status)	{ s->_cxxShip->aegis_status = status; }
void SetSticks(ShipEntity *s, GLfloat roll, GLfloat pitch, GLfloat yaw)	{ s->_cxxShip->stick_roll = roll; s->_cxxShip->stick_pitch = pitch; s->_cxxShip->stick_yaw = yaw; }
GLfloat ScaleFactor(ShipEntity *s)	{ return s->_cxxShip->_scaleFactor; }
void SetMass(Entity *e, GLfloat value)	{ e->_cxxEntity->mass = value; }
bool IsWreckage(ShipEntity *s)	{ return s->_cxxShip->isWreckage; }
void SetShowDamage(ShipEntity *s, bool value)	{ s->_cxxShip->_showDamage = value; }
void SetWeaponTemps(ShipEntity *s, GLfloat temp, GLfloat aft)	{ s->_cxxShip->weapon_temp = temp; s->_cxxShip->aft_weapon_temp = aft; }
bool SuppressesExplosion(ShipEntity *s)	{ return s->_cxxShip->suppressExplosion; }
void SetBoundingBox(Entity *e, BoundingBox box)	{ e->_cxxEntity->boundingBox = box; }
void SetShotTime(ShipEntity *s, OOTimeDelta value)	{ s->_cxxShip->shot_time = value; }
double NextAegisCheck(ShipEntity *s)	{ return s->_cxxShip->_nextAegisCheck; }
double LaunchTime(ShipEntity *s)	{ return s->_cxxShip->launch_time; }
double LaunchDelay(ShipEntity *s)	{ return s->_cxxShip->launch_delay; }
void SetExplicitlyUnpiloted(ShipEntity *s, bool value)	{ s->_cxxShip->_explicitlyUnpiloted = value; }

void SetPrimaryTarget(ShipEntity *s, Entity *target)
{
	[s->_cxxShip->_primaryTarget release];
	s->_cxxShip->_primaryTarget = [target weakRetain];
}

void SetProximityAlert(ShipEntity *s, Entity *other)
{
	[s->_cxxShip->_proximityAlert release];
	s->_cxxShip->_proximityAlert = [other weakRetain];
}

void SetNavpoints(ShipEntity *s, std::initializer_list<HPVector> points, unsigned next)
{
	unsigned n = 0;
	for (HPVector p : points)  s->_cxxShip->navpoints[n++] = p;
	s->_cxxShip->number_of_navpoints = n;
	s->_cxxShip->next_navpoint_index = next;
}

// --------------------------------------------------------------------------------------------------


void SetUp()
{
	static Universe *universe = nil;
	if (universe == nil)
	{
		universe = (Universe *)class_createInstance([Universe class], 0);	// never released
		universe->_cxxUniverse = oo::makeRef<cxx::Universe>(universe);	// what -initWithGameView: makes first (ADR-0056 amendment oo-riqmz)
	}
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


// --- Slice 2: -cxx_setUpFromDictionary:, the set-up players and NPCs share (bead oo-cvbe3) -------

namespace {

const cxx::ShipEntity *Part(ShipEntity *s)	{ return s->_cxxShip; }

}	// namespace


// An empty definition (nil, as PlayerEntity's -deferredInit may give) is an empty dictionary,
// and every setting takes its default.
OO_TEST(setUpFromDictionaryDefaults)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = [[[TestShip alloc] cxx_initWithKey:"defaults" definition:Definition()] autorelease];
		OO_CHECK([ship cxx_setUpFromDictionary:oo::PList()]);
		const cxx::ShipEntity *part = Part(ship);
		OO_CHECK([ship cxx_shipInfoDictionary].isDict() && [ship cxx_shipInfoDictionary].count() == 0);
		OO_CHECK([ship maxFlightSpeed] == 160.0f && [ship maxFlightRoll] == 2.0f && [ship maxFlightPitch] == 1.0f && [ship maxFlightYaw] == 1.0f);
		OO_CHECK([ship cruiseSpeed] == 160.0f * 0.8f);
		OO_CHECK([ship maxThrust] == 15.0f && [ship thrust] == 15.0f);
		OO_CHECK([ship afterburnerFactor] == 7.0f && [ship afterburnerRate] == AFTERBURNER_BURNRATE);
		OO_CHECK([ship maxEnergy] == 200.0f && part->energy_recharge_rate == 1.0f);
		OO_CHECK([ship weaponFacings] == VALID_WEAPON_FACINGS);
		OO_CHECK([ship missileCount] == 0 && [ship missileCapacity] == 0);
		OO_CHECK(part->cloakPassive && part->cloakAutomatic && !part->cloaking_device_active && !part->military_jammer_active);
		OO_CHECK(part->isFrangible && !part->isWreckage && part->canFragment);
		OO_CHECK(part->max_cargo == 0 && [ship extraCargo] == 15);
		OO_CHECK([ship hyperspaceSpinTime] == DEFAULT_HYPERSPACE_SPIN_TIME);
		OO_CHECK([ship cxx_name] == std::optional<std::string>("?"));
		OO_CHECK([ship cxx_shipUniqueName] == std::optional<std::string>(""));
		OO_CHECK([ship cxx_shipClassName] == std::optional<std::string>("?"));
		OO_CHECK(part->displayName == std::nullopt);
		OO_CHECK(part->_scaleFactor == 1.0f);
		OO_CHECK(![ship scriptedMisjump] && [ship scriptedMisjumpRange] == 0.5f);
		OO_CHECK(part->_lightsActive && !part->haveExecutedSpawnAction && !part->isMissile);
		OO_CHECK(quaternion_equal([ship subEntityRotationalVelocity], kIdentityQuaternion));
		OO_CHECK(!part->_multiplyWeapons && part->forwardWeaponOffset.size() == 1 && vector_equal(part->forwardWeaponOffset[0], kZeroVector));
		OO_CHECK([ship sunGlareFilter] == 0.97f);
		OO_CHECK(part->scriptInfo.isNull() && part->explosionType.isNull());
		OO_CHECK(![ship isDemoShip]);
	}
}


// Each setting from the definition, with the clamps: an injector speed factor under 1, too many
// missiles for the pylons, too many pylons; and what follows from others (scaled positions, the
// class name from the name, no hyperspace motor).
OO_TEST(setUpFromDictionaryValues)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = [[[TestShip alloc] cxx_initWithKey:"values" definition:Definition()] autorelease];
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
		OO_CHECK([ship cxx_setUpFromDictionary:definition]);
		const cxx::ShipEntity *part = Part(ship);
		OO_CHECK([ship cxx_shipInfoDictionary].get<std::string>("name", "") == "Viper");
		OO_CHECK([ship maxFlightSpeed] == 300.0f && [ship maxFlightRoll] == 3.0f && [ship maxFlightPitch] == 1.5f);
		OO_CHECK([ship maxFlightYaw] == 1.5f);	// yaw defaults to pitch
		OO_CHECK([ship cruiseSpeed] == 300.0f * 0.8f);
		OO_CHECK([ship maxThrust] == 20.0f && [ship thrust] == 20.0f);
		OO_CHECK([ship afterburnerFactor] == 1.0f && [ship afterburnerRate] == 0.5f);
		OO_CHECK([ship maxEnergy] == 500.0f && part->energy_recharge_rate == 4.0f);
		OO_CHECK([ship weaponFacings] == VALID_WEAPON_FACINGS);
		OO_CHECK([ship missileCapacity] == SHIPENTITY_MAX_MISSILES && part->missiles == SHIPENTITY_MAX_MISSILES);
		OO_CHECK(!part->cloakPassive && !part->isFrangible);
		OO_CHECK(part->max_cargo == 20 && [ship extraCargo] == 5);
		OO_CHECK([ship hyperspaceSpinTime] == -1);
		OO_CHECK([ship cxx_name] == std::optional<std::string>("Viper"));
		OO_CHECK([ship cxx_shipUniqueName] == std::optional<std::string>("Bob"));
		OO_CHECK([ship cxx_shipClassName] == std::optional<std::string>("Viper"));
		OO_CHECK(part->displayName == std::optional<std::string>("Police Viper"));
		OO_CHECK(part->_scaleFactor == 2.0f);
		OO_CHECK(vector_equal(part->tractor_position, make_vector(2, 4, 6)));
		OO_CHECK(part->_multiplyWeapons && part->forwardWeaponOffset.size() == 2);
		OO_CHECK(part->forwardWeaponOffset.size() == 2 && vector_equal(part->forwardWeaponOffset[1], make_vector(-2, 0, 0)));
		OO_CHECK([ship sunGlareFilter] == 0.5f);
		OO_CHECK(part->scriptInfo.get<int>("a", 0) == 1);
		OO_CHECK(part->explosionType.isArray() && part->explosionType.count() == 1);
	}
}


// --- Slice 3: -setUpShipFromDictionary:, subentity serialisation and set-up (bead oo-mvzmb) -----

// A ship that keeps ShipEntity's own set-up.
@interface PlainShip: ShipEntity
@end


@implementation PlainShip
@end


namespace {

cxx::ShipEntity *MutablePart(ShipEntity *s)	{ return s->_cxxShip; }

}	// namespace


// The NPC settings on top of the shared ones: scan class, energy, weapon damage of a missile,
// roles without "player", the escort clamp, beacons, an unpiloted ship.
OO_TEST(setUpShipFromDictionaryNPC)
{
	@autoreleasepool
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
		PlainShip *ship = [[[PlainShip alloc] cxx_initWithKey:"npc" definition:definition] autorelease];
		OO_CHECK(ship != nil);
		const cxx::ShipEntity *part = Part(ship);
		OO_CHECK([ship isShip] && [ship scanClass] == CLASS_POLICE);
		OO_CHECK(part->scan_description == std::optional<std::string>("Cop"));
		OO_CHECK([ship energy] == 300.0 && [ship maxEnergy] == 300.0f);
		OO_CHECK(part->weapon_damage == 12.0f && part->weapon_damage_override == 12.0f);
		OO_CHECK(part->scannerRange == 30000.0f && [ship fuel] == 70 && part->fuel_accumulator == 1.0f);
		OO_CHECK(part->likely_cargo == 3 && !part->hasScoopMessage);
		OO_CHECK([ship hasRole:"police"] && ![ship hasRole:"player"]);
		OO_CHECK([ship accuracy] == 3.0f);
		OO_CHECK(part->_maxEscortCount == MAX_ESCORTS && part->_pendingEscortCount == MAX_ESCORTS);
		OO_CHECK([ship beaconCode] == std::optional<std::string>("B") && [ship beaconLabel] == std::optional<std::string>("B"));
		OO_CHECK(part->_heatInsulation == 1.5f);
		OO_CHECK(part->_explicitlyUnpiloted && part->crew == std::nullopt);
		OO_CHECK(part->reactionTime == 2.0f);
		OO_CHECK(vector_equal([ship forwardVector], kBasisZVector) && vector_equal([ship upVector], kBasisYVector) && vector_equal([ship rightVector], kBasisXVector));
		OO_CHECK(part->cargo_type == CARGO_NOT_CARGO);
		OO_CHECK([ship getAI] != nil && [ship owner] == ship);
	}
}


OO_TEST(subIdxAndSerialisation)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = [[[TestShip alloc] cxx_initWithKey:"mother" definition:Definition()] autorelease];
		TestShip *a = [[[TestShip alloc] cxx_initWithKey:"a" definition:Definition()] autorelease];
		TestShip *b = [[[TestShip alloc] cxx_initWithKey:"b" definition:Definition()] autorelease];
		[a setSubIdx:0];
		[b setSubIdx:2];
		OO_CHECK([a subIdx] == 0 && [b subIdx] == 2);
		[ship addSubEntity:a];
		[ship addSubEntity:b];
		MutablePart(ship)->_maxShipSubIdx = 4;
		OO_CHECK([ship maxShipSubEntities] == 4);
		OO_CHECK([ship cxx_serializeShipSubEntities] == std::optional<std::string>("1010"));
		[ship cxx_deserializeShipSubEntitiesFrom:"1111"];	// every one is alive: nothing happens
		OO_CHECK([ship subEntityCount] == 2 && [a owner] == ship && [b owner] == ship);
		[ship clearSubEntities];
	}
}


// -setUpSubEntities with no exhausts or subentities: the profile radius is the collision radius,
// and the frustum radius is the profile radius (no exhaust is longer).
OO_TEST(setUpSubEntitiesAndFrustumRadius)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = [[[TestShip alloc] cxx_initWithKey:"bare" definition:Definition()] autorelease];
		OO_CHECK([ship cxx_setUpFromDictionary:oo::PList()]);
		MutablePart(ship)->collision_radius = 25.0f;
		OO_CHECK([ship setUpSubEntities]);
		OO_CHECK([ship maxShipSubEntities] == 0 && [ship subEntityCount] == 0);
		OO_CHECK(Part(ship)->_profileRadius == 25.0f);
		OO_CHECK([ship frustumRadius] == 25.0f);
		OO_CHECK(Part(ship)->no_draw_distance == (GLfloat)(25.0 * 25.0 * NO_DRAW_DISTANCE_FACTOR * NO_DRAW_DISTANCE_FACTOR * 2.0));
	}
}


// --- Slice 4: standard subentities, cargo pods, descriptions, mesh, vectors, misjump, lists (oo-ln2m1)

OO_TEST(cargoTypeAndTemplatePod)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = [[[TestShip alloc] cxx_initWithKey:"pod" definition:Definition()] autorelease];
		OO_CHECK(![ship isTemplateCargoPod]);
		[ship setUpCargoType:"CARGO_ALLOY"];
		OO_CHECK(Part(ship)->cargo_type == CARGO_RANDOM && Part(ship)->commodity_type == std::optional<std::string>("alloys") && Part(ship)->commodity_amount == 1);
		[ship setUpCargoType:"CARGO_SCRIPTED_ITEM"];
		OO_CHECK(Part(ship)->cargo_type == CARGO_SCRIPTED_ITEM && Part(ship)->commodity_type == std::nullopt && Part(ship)->commodity_amount == 1);
		[ship setUpCargoType:"CARGO_NOT_CARGO"];
		OO_CHECK(Part(ship)->cargo_type == CARGO_NOT_CARGO);
	}
}


OO_TEST(simpleAccessors)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = [[[TestShip alloc] cxx_initWithKey:"acc" definition:Definition()] autorelease];
		[ship setSunGlareFilter:2.0f];
		OO_CHECK([ship sunGlareFilter] == 1.0f);
		[ship setSunGlareFilter:0.25f];
		OO_CHECK([ship sunGlareFilter] == 0.25f);

		[ship setAccuracy:20.0f];
		OO_CHECK([ship accuracy] == 10.0f);
		OO_CHECK(Part(ship)->pitch_tolerance == (GLfloat)(0.01 * (85.0f + 10.0f)) && Part(ship)->aim_tolerance == (GLfloat)(240.0 - 18.0f * 10.0f));
		OO_CHECK(Part(ship)->missile_load_time == 2.0);
		[ship setAccuracy:-9.0f];
		OO_CHECK([ship accuracy] == -5.0f);

		Quaternion q = { 0.5f, 0.5f, 0.5f, 0.5f };
		[ship setSubEntityRotationalVelocity:q];
		OO_CHECK(quaternion_equal([ship subEntityRotationalVelocity], q));

		[ship setScriptedMisjump:YES];
		[ship setScriptedMisjumpRange:0.75f];
		OO_CHECK([ship scriptedMisjump] && [ship scriptedMisjumpRange] == 0.75f);

		OO_CHECK([ship mesh] == nil && [ship octree] == nil);
		OO_CHECK([ship shipScript] == nil && [ship shipAIScript] == nil);
		[ship setAIScriptWakeTime:12.5];
		OO_CHECK([ship shipAIScriptWakeTime] == 12.5);
		[ship removeScript];
		OO_CHECK([ship shipScript] == nil);

		BoundingBox box = [ship totalBoundingBox];
		OO_CHECK(box.min.x == 0 && box.max.x == 0);
	}
}


OO_TEST(descriptions)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = [[[TestShip alloc] cxx_initWithKey:"desc" definition:Definition()] autorelease];
		OO_CHECK([ship cxx_setUpFromDictionary:oo::PList(oo::PList::Dict{ { "name", oo::PList(std::string("Viper")) } })]);
		OO_CHECK([ship cxx_shortDescriptionComponents] == std::optional<std::string>("\"Viper\""));
		const std::optional<std::string> desc = [ship cxx_descriptionComponents];
		OO_CHECK(desc.has_value() && desc->rfind("\"Viper\" ", 0) == 0);
	}
}


// The subentity lists, the ship / flasher / exhaust filters, and the subentity taking damage.
OO_TEST(subEntityLists)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = [[[TestShip alloc] cxx_initWithKey:"mother" definition:Definition()] autorelease];
		TestShip *sub = [[[TestShip alloc] cxx_initWithKey:"sub" definition:Definition()] autorelease];
		OO_CHECK([ship subEntityCount] == 0 && [ship subEntities].empty());
		[ship addSubEntity:sub];
		OO_CHECK([ship subEntityCount] == 1 && [ship hasSubEntity:sub]);
		OO_CHECK([ship subEntities].size() == 1 && [ship subEntities][0].get() == sub);
		OO_CHECK([ship subEntityEnumerator].size() == 1);
		OO_CHECK([ship cxx_shipSubEntities].size() == 1 && [ship cxx_shipSubEntities][0].get() == sub);
		OO_CHECK([ship flasherEnumerator].empty() && [ship cxx_exhausts].empty());
		[ship setSubEntityTakingDamage:sub];
		OO_CHECK([ship subEntityTakingDamage] == sub);
		[ship setSubEntityTakingDamage:ship];	// not a subentity: refused (debug builds)
#ifndef NDEBUG
		OO_CHECK([ship subEntityTakingDamage] == nil);
#endif
		[ship clearSubEntities];
		OO_CHECK([ship subEntityCount] == 0 && [sub owner] == nil);
	}
}


// --- Slice 5: bounding boxes, octree hit tests, universe add / remove, beacons, boulders (oo-ddnn8)

OO_TEST(octreeAndTractorWithoutAModel)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = [[[TestShip alloc] cxx_initWithKey:"nomodel" definition:Definition()] autorelease];
		OO_CHECK([ship cxx_setUpFromDictionary:oo::PList(oo::PList::Dict{ { "scoop_position", oo::PList(std::string("0 0 10")) } })]);
		OO_CHECK([ship octree] == nil && [ship volume] == 0.0f);
		OO_CHECK([ship doesHitLine:kZeroHPVector v1:make_HPvector(0, 0, 100)] == 0.0f);
		[ship setPosition:make_HPvector(1, 2, 3)];
		[ship setOrientation:kIdentityQuaternion];
		HPVector tractor = [ship absoluteTractorPosition];
		OO_CHECK(tractor.x == 1 && tractor.y == 2 && tractor.z == 13);
	}
}


OO_TEST(beacons)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = [[[TestShip alloc] cxx_initWithKey:"beacon" definition:Definition()] autorelease];
		TestShip *other = [[[TestShip alloc] cxx_initWithKey:"other" definition:Definition()] autorelease];
		OO_CHECK(![ship isBeacon] && [ship beaconCode] == std::nullopt && [ship beaconLabel] == std::nullopt);
		[ship setBeaconCode:std::string()];	// empty is none
		OO_CHECK(![ship isBeacon]);
		[ship setBeaconCode:std::string("X")];
		OO_CHECK([ship isBeacon] && [ship beaconCode] == std::optional<std::string>("X"));
		OO_CHECK([ship beaconLabel] == std::optional<std::string>("X"));	// the label defaults to the code
		[ship setBeaconLabel:std::string()];
		OO_CHECK([ship beaconLabel] == std::nullopt);
		[ship setBeaconCode:std::nullopt];
		OO_CHECK(![ship isBeacon]);

		OO_CHECK([ship nextBeacon] == nil && [ship prevBeacon] == nil);
		[ship setNextBeacon:other];
		[ship setPrevBeacon:other];
		OO_CHECK([ship nextBeacon] == other && [ship prevBeacon] == other);
		[ship setNextBeacon:nil];
		OO_CHECK([ship nextBeacon] == nil && [ship prevBeacon] == other);
	}
}


OO_TEST(visibilityBouldersAndKills)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = [[[TestShip alloc] cxx_initWithKey:"rock" definition:Definition()] autorelease];
		OO_CHECK([ship cxx_setUpFromDictionary:oo::PList()]);
		MutablePart(ship)->no_draw_distance = 100.0f;
		MutablePart(ship)->cam_zero_distance = 50.0f;
		OO_CHECK([ship isVisible]);
		MutablePart(ship)->cam_zero_distance = 150.0f;
		OO_CHECK(![ship isVisible]);

		OO_CHECK(![ship isBoulder] && ![ship isMinable]);
		[ship setIsBoulder:YES];
		OO_CHECK([ship isBoulder] && [ship isMinable]);
		MutablePart(ship)->noRocks = 1;
		OO_CHECK(![ship isMinable]);
		[ship setIsBoulder:NO];
		OO_CHECK(![ship isBoulder]);

		OO_CHECK([ship countsAsKill]);
		OO_CHECK([ship cxx_setUpFromDictionary:oo::PList(oo::PList::Dict{ { "counts_as_kill", oo::PList(false) } })]);
		OO_CHECK(![ship countsAsKill]);
	}
}


// --- Slice 6: ship data key, weapon offsets, collision checks, subentity geometry (oo-5z5wd) --------

OO_TEST(shipDataKeyAndInfo)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = [[[TestShip alloc] cxx_initWithKey:"keyed" definition:Definition()] autorelease];
		OO_CHECK([ship cxx_shipDataKey] == std::optional<std::string>("keyed"));
		OO_CHECK([ship cxx_shipDataKeyAutoRole] == std::optional<std::string>("[keyed]"));
		[ship cxx_setShipDataKey:std::nullopt];
		OO_CHECK([ship cxx_shipDataKey] == std::nullopt && [ship cxx_shipDataKeyAutoRole] == std::optional<std::string>("[(null)]"));
		OO_CHECK([ship cxx_shipInfoDictionary].isNull());	// the test ship's set-up kept none
		OO_CHECK([ship cxx_setUpFromDictionary:oo::PList(oo::PList::Dict{
			{ "frangible", oo::PList(false) },
			{ "model_scale_factor", oo::PList(2.0) },
			{ "weapon_position_aft", oo::PList(std::string("0 0 -5")) },
		})]);
		OO_CHECK([ship cxx_shipInfoDictionary].get<bool>("frangible", true) == false);
		OO_CHECK(![ship isFrangible]);
		OO_CHECK([ship cxx_aftWeaponOffset].size() == 1 && vector_equal([ship cxx_aftWeaponOffset][0], make_vector(0, 0, -10)));
		OO_CHECK([ship cxx_forwardWeaponOffset].size() == 1 && vector_equal([ship cxx_forwardWeaponOffset][0], kZeroVector));
		OO_CHECK([ship cxx_portWeaponOffset].size() == 1 && [ship cxx_starboardWeaponOffset].size() == 1);

		// The modes: "single" is one scaled vector; otherwise an array of them, or one zero vector.
		const oo::PList mounts(oo::PList::Dict{ { "k", oo::PList(oo::PList::Array{ oo::PList(std::string("1 0 0")), oo::PList(std::string("0 1 0")) }) } });
		const std::vector<Vector> multi = [ship cxx_weaponOffsetsFrom:mounts withKey:"k" inMode:"multiply"];
		OO_CHECK(multi.size() == 2 && vector_equal(multi[1], make_vector(0, 2, 0)));
		const std::vector<Vector> none = [ship cxx_weaponOffsetsFrom:mounts withKey:"absent" inMode:"multiply"];
		OO_CHECK(none.size() == 1 && vector_equal(none[0], kZeroVector));
	}
}


OO_TEST(scanClassAndCollisionFlags)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = [[[TestShip alloc] cxx_initWithKey:"flags" definition:Definition()] autorelease];
		[ship setScanClass:CLASS_NEUTRAL];
		OO_CHECK([ship scanClass] == CLASS_NEUTRAL);
		MutablePart(ship)->cloaking_device_active = 1;
		OO_CHECK([ship scanClass] == CLASS_NO_DRAW);
		MutablePart(ship)->cloaking_device_active = 0;

		OO_CHECK(![ship suppressFlightNotifications]);
		MutablePart(ship)->suppressAegisMessages = 1;
		OO_CHECK([ship suppressFlightNotifications]);

		OO_CHECK([ship status] == STATUS_IN_FLIGHT && [ship canCollide]);
		MutablePart(ship)->isWreckage = 1;
		OO_CHECK(![ship canCollide]);
		MutablePart(ship)->isWreckage = 0;
		[ship setStatus:STATUS_DEAD];
		OO_CHECK(![ship canCollide]);
		[ship setStatus:STATUS_IN_FLIGHT];
		OO_CHECK([ship canCollide]);
	}
}


// -checkCloseCollisionWith: nil, an entity already colliding, a plain entity (a collision), and a
// ship (the octrees decide; with no model, no collision). -absoluteIJKForSubentity of a free ship is
// its frame.
OO_TEST(closeCollisionAndFrame)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = [[[TestShip alloc] cxx_initWithKey:"hull" definition:Definition()] autorelease];
		TestShip *other = [[[TestShip alloc] cxx_initWithKey:"other" definition:Definition()] autorelease];
		Entity *plain = [[[Entity alloc] init] autorelease];
		OO_CHECK(![ship checkCloseCollisionWith:nil]);
		OO_CHECK([ship checkCloseCollisionWith:plain] && Part(ship)->collider == plain);
		MutablePart(ship)->collider = nil;
		OO_CHECK(![ship checkCloseCollisionWith:other] && Part(ship)->collider == nil);

		[ship setOrientation:kIdentityQuaternion];
		Triangle ijk = [ship absoluteIJKForSubentity];
		OO_CHECK(vector_equal(ijk.v[0], kBasisXVector) && vector_equal(ijk.v[1], kBasisYVector) && vector_equal(ijk.v[2], kBasisZVector));
	}
}


// --- Slice 7: -update: (bead oo-k2q1f) -------------------------------------------------------------

// A ship whose -update: only counts: a subentity that a demo ship updates.
@interface CountingShip: TestShip
{
@public
	int		_updates;
}
@end


@implementation CountingShip

- (void) update:(OOTimeDelta)delta_t
{
	_updates++;
}

@end


// A demo ship (the ship library's) turns at its demo rate, has its subentities updated, and has an
// infinite top speed clamped first.
OO_TEST(updateDemoShip)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = [[[TestShip alloc] cxx_initWithKey:"demo" definition:Definition()] autorelease];
		CountingShip *sub = [[[CountingShip alloc] cxx_initWithKey:"sub" definition:Definition()] autorelease];
		OO_CHECK([ship cxx_setUpFromDictionary:oo::PList()]);
		[ship addSubEntity:sub];
		MutablePart(ship)->isDemoShip = YES;
		MutablePart(ship)->demoRate = 0;
		[ship setMaxFlightSpeed:INFINITY];
		[ship update:0.1];
		OO_CHECK([ship maxFlightSpeed] == 300.0f);
		OO_CHECK(sub->_updates == 1);
		[ship clearSubEntities];
	}
}


// From C++, update() reaches an Objective-C subclass's override (the root's adapter line).
OO_TEST(updateReachesTheSubclass)
{
	@autoreleasepool
	{
		SetUp();
		CountingShip *ship = [[[CountingShip alloc] cxx_initWithKey:"counted" definition:Definition()] autorelease];
		cxx::Entity *part = oo::ToCxx(static_cast<Entity *>(ship));
		part->update(0.1);
		OO_CHECK(ship->_updates == 1);
	}
}


// --- Slice 8: behaviour dispatch, attack response, equipment queries (bead oo-vxdsc) ---------------

// The equipment queries over the ship's equipment keys (no equipment data is loaded, so no type is
// known: a key provides only itself).
OO_TEST(equipmentQueries)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = [[[TestShip alloc] cxx_initWithKey:"kit" definition:Definition()] autorelease];
		OO_CHECK(![ship hasEquipmentItem:oo::PList(std::string("EQ_A"))]);
		OO_CHECK(![ship hasAllEquipment:oo::PList(std::string("EQ_A"))]);	// none at all
		MutablePart(ship)->_equipment = { "EQ_A", "EQ_B_DAMAGED", "EQ_A" };
		OO_CHECK([ship cxx_countEquipmentItem:"EQ_A"] == 2 && [ship cxx_countEquipmentItem:"EQ_B"] == 0);
		OO_CHECK([ship cxx_hasOneEquipmentItem:"EQ_A" includeWeapons:NO whileLoading:NO]);
		OO_CHECK(![ship cxx_hasOneEquipmentItem:"EQ_B" includeWeapons:NO whileLoading:NO]);
		OO_CHECK([ship cxx_hasOneEquipmentItem:"EQ_B" includeWeapons:NO whileLoading:YES]);	// damaged counts while loading
		OO_CHECK([ship cxx_hasOneEquipmentItem:"EQ_B" includeMissiles:NO whileLoading:YES]);
		OO_CHECK(![ship cxx_hasOneEquipmentItem:"EQ_C" includeMissiles:YES whileLoading:NO]);
		OO_CHECK([ship hasEquipmentItem:oo::PList(std::string("EQ_A"))]);
		OO_CHECK([ship hasEquipmentItem:oo::PList(oo::PList::Array{ oo::PList(std::string("EQ_X")), oo::PList(std::string("EQ_A")) })]);
		OO_CHECK(![ship hasEquipmentItem:oo::PList(oo::PList::Array{ oo::PList(std::string("EQ_X")), oo::PList(1) })]);
		OO_CHECK([ship hasAllEquipment:oo::PList(oo::PList::Array{ oo::PList(std::string("EQ_A")) })]);
		OO_CHECK(![ship hasAllEquipment:oo::PList(oo::PList::Array{ oo::PList(std::string("EQ_A")), oo::PList(std::string("EQ_B")) })]);
		OO_CHECK([ship hasAllEquipment:oo::PList(oo::PList::Array{ oo::PList(std::string("EQ_A")), oo::PList(std::string("EQ_B")) }) includeWeapons:NO whileLoading:YES]);
		OO_CHECK(![ship hasAllEquipment:oo::PList(oo::PList::Array{ oo::PList(std::string("EQ_A")), oo::PList(2) })]);
		OO_CHECK([ship cxx_hasEquipmentItemProviding:"EQ_A"] && ![ship cxx_hasEquipmentItemProviding:"EQ_Z"]);
		OO_CHECK([ship cxx_equipmentItemProviding:"EQ_A"] == std::optional<std::string>("EQ_A"));
		OO_CHECK([ship cxx_equipmentItemProviding:"EQ_Z"] == std::nullopt);
		OO_CHECK(![ship hasPrimaryWeapon:nil]);
	}
}


OO_TEST(hyperspaceMotor)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = [[[TestShip alloc] cxx_initWithKey:"motor" definition:Definition()] autorelease];
		[ship setHyperspaceSpinTime:12.0f];
		OO_CHECK([ship hyperspaceSpinTime] == 12.0f && [ship hasHyperspaceMotor]);
		[ship setHyperspaceSpinTime:-1.0f];
		OO_CHECK(![ship hasHyperspaceMotor]);
	}
}


// --- Slice 9: equipment validity and adding, weapon mounts, scripting lists (bead oo-ke13m) ---------

OO_TEST(weaponMountsAndLists)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = [[[TestShip alloc] cxx_initWithKey:"mounts" definition:Definition()] autorelease];
		OO_CHECK([ship cxx_setUpFromDictionary:oo::PList(oo::PList::Dict{ { "weapon_facings", oo::PList(WEAPON_FACING_FORWARD | WEAPON_FACING_AFT) } })]);
		OO_CHECK([ship weaponFacings] == (WEAPON_FACING_FORWARD | WEAPON_FACING_AFT));
		// No weapon data is loaded: every mount is empty, and a facing the ship lacks has nothing.
		OO_CHECK(isWeaponNone([ship weaponTypeIDForFacing:WEAPON_FACING_FORWARD strict:YES]));
		OO_CHECK([ship weaponTypeIDForFacing:WEAPON_FACING_PORT strict:NO] == nil);
		OO_CHECK([ship weaponTypeForFacing:WEAPON_FACING_STARBOARD strict:NO] == nil);
		OO_CHECK([ship missilesList].empty());
		const oo::PList passengers = [ship passengerListForScripting];
		OO_CHECK(passengers.isArray() && passengers.count() == 0);
		OO_CHECK([ship parcelListForScripting].isArray() && [ship contractListForScripting].isArray());
	}
}


OO_TEST(equipmentKeysAndUnknownEquipment)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = [[[TestShip alloc] cxx_initWithKey:"keys" definition:Definition()] autorelease];
		OO_CHECK([ship cxx_equipmentKeys].empty() && [ship equipmentCount] == 0);
		MutablePart(ship)->_equipment = { "EQ_A", "EQ_B" };
		OO_CHECK([ship cxx_equipmentKeys] == std::vector<std::string>({ "EQ_A", "EQ_B" }) && [ship equipmentCount] == 2);
		// An equipment key with no equipment type is never valid, and is not added.
		OO_CHECK(![ship cxx_equipmentValidToAdd:"EQ_UNKNOWN" inContext:"npc"]);
		OO_CHECK(![ship canAddEquipment:"EQ_UNKNOWN" inContext:"npc"]);
		OO_CHECK(![ship addEquipmentItem:"EQ_UNKNOWN" inContext:"npc"]);
		OO_CHECK([ship equipmentCount] == 2);
	}
}


// --- Slice 10: equipment removal, missiles, capacities, has-equipment predicates, shields (oo-wvcs2)

OO_TEST(capacitiesAndPredicates)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = [[[TestShip alloc] cxx_initWithKey:"preds" definition:Definition()] autorelease];
		OO_CHECK([ship cxx_setUpFromDictionary:oo::PList(oo::PList::Dict{
			{ "missiles", oo::PList(2) }, { "max_missiles", oo::PList(4) }, { "extra_cargo", oo::PList(7) } })]);
		OO_CHECK([ship missileCount] == 2 && [ship missileCapacity] == 4 && [ship extraCargo] == 7);
		OO_CHECK([ship parcelCount] == 0 && [ship passengerCount] == 0 && [ship passengerCapacity] == 0);
		OO_CHECK([ship maxHyperspaceDistance] == MAX_JUMP_RANGE);

		OO_CHECK(![ship hasScoop] && ![ship hasECM] && ![ship hasShieldBooster] && ![ship hasEscapePod]);
		OO_CHECK([ship shieldBoostFactor] == 1.0f && [ship shieldRechargeRate] == 2.0f);
		OO_CHECK([ship maxForwardShieldLevel] == BASELINE_SHIELD_LEVEL && [ship maxAftShieldLevel] == BASELINE_SHIELD_LEVEL);

		// Each predicate is "some equipment provides the key" (a key provides itself).
		MutablePart(ship)->_equipment = { "EQ_FUEL_SCOOPS", "EQ_ECM", "EQ_SHIELD_BOOSTER", "EQ_NAVAL_SHIELD_BOOSTER",
			"EQ_CLOAKING_DEVICE", "EQ_MILITARY_SCANNER_FILTER", "EQ_MILITARY_JAMMER", "EQ_CARGO_BAY", "EQ_HEAT_SHIELD",
			"EQ_FUEL_INJECTION", "EQ_QC_MINE", "EQ_ESCAPE_POD", "EQ_DOCK_COMP", "EQ_GAL_DRIVE" };
		OO_CHECK([ship hasScoop] && [ship hasFuelScoop] && ![ship hasCargoScoop]);
		OO_CHECK([ship hasECM] && [ship hasCloakingDevice] && [ship hasMilitaryScannerFilter] && [ship hasMilitaryJammer]);
		OO_CHECK([ship hasExpandedCargoBay] && [ship hasShieldBooster] && [ship hasMilitaryShieldEnhancer]);
		OO_CHECK([ship hasHeatShield] && [ship hasFuelInjection] && [ship hasEscapePod] && [ship hasCascadeMine]);
		OO_CHECK([ship hasDockingComputer] && [ship hasGalacticHyperdrive]);
		OO_CHECK([ship shieldBoostFactor] == 3.0f && [ship shieldRechargeRate] == 3.0f);
		OO_CHECK([ship maxForwardShieldLevel] == BASELINE_SHIELD_LEVEL * 3.0f);

		// An unknown equipment type is not removed; -removeAllEquipment clears the keys.
		[ship removeEquipmentItem:"EQ_ECM"];
		OO_CHECK([ship hasECM]);
		[ship removeAllEquipment];
		OO_CHECK([ship equipmentCount] == 0 && ![ship hasECM]);
	}
}


OO_TEST(removeMissiles)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = [[[TestShip alloc] cxx_initWithKey:"launcher" definition:Definition()] autorelease];
		OO_CHECK([ship removeMissiles] == 0 && [ship missileCount] == 0);
	}
}


// --- Slice 11: thrust and afterburner; idle, tumble, tractored, track, intercept, dogfight (oo-eh955)

OO_TEST(thrustAndAfterburner)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = [[[TestShip alloc] cxx_initWithKey:"burner" definition:Definition()] autorelease];
		[ship setAfterburnerFactor:4.0f];
		[ship setAfterburnerRate:0.5f];
		[ship setMaxThrust:30.0f];
		OO_CHECK([ship afterburnerFactor] == 4.0f && [ship afterburnerRate] == 0.5f && [ship maxThrust] == 30.0f);
		OO_CHECK([ship thrust] == 0.0f);	// the thrust itself is the set-up's, not -setMaxThrust:'s
	}
}


// -behaviour_stop_still: and -behaviour_idle: centre the sticks (a buoy keeps rolling), and the
// sticks move the flight controls at their rate (-applySticks:).
OO_TEST(behaviourStopStillAndIdle)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = [[[TestShip alloc] cxx_initWithKey:"still" definition:Definition()] autorelease];
		MutablePart(ship)->flightRoll = 1.0f;
		MutablePart(ship)->stick_roll = 1.0f;
		MutablePart(ship)->stick_pitch = 1.0f;
		[ship behaviour_stop_still:0.1];
		OO_CHECK(Part(ship)->stick_roll == 0 && Part(ship)->stick_pitch == 0 && Part(ship)->stick_yaw == 0);
		OO_CHECK(fabs(Part(ship)->flightRoll - 0.8f) < 1e-5f);

		[ship setScanClass:CLASS_BUOY];
		MutablePart(ship)->flightRoll = 0.5f;
		MutablePart(ship)->flightPitch = 0.25f;
		[ship behaviour_idle:0.1];
		OO_CHECK(Part(ship)->stick_roll == 0.5f && Part(ship)->stick_pitch == 0.25f && Part(ship)->stick_yaw == 0);
		OO_CHECK(Part(ship)->flightRoll == 0.5f && Part(ship)->flightPitch == 0.25f);

		[ship setScanClass:CLASS_NEUTRAL];
		[ship behaviour_idle:0.1];
		OO_CHECK(Part(ship)->stick_roll == 0 && Part(ship)->stick_pitch == 0);

		MutablePart(ship)->stick_roll = 0.5f;
		MutablePart(ship)->flightRoll = 0.0f;
		[ship behaviour_tumble:0.1];	// the sticks as they are
		OO_CHECK(Part(ship)->stick_roll == 0.5f && fabs(Part(ship)->flightRoll - 0.2f) < 1e-5f);
	}
}


// Behaviours that need a target, with none: the ship notes the lost target and goes idle.
OO_TEST(behavioursWithoutATarget)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = [[[TestShip alloc] cxx_initWithKey:"hunter" definition:Definition()] autorelease];
		MutablePart(ship)->behaviour = BEHAVIOUR_ATTACK_SLOW_DOGFIGHT;
		[ship behaviour_attack_slow_dogfight:0.1];
		OO_CHECK(Part(ship)->behaviour == BEHAVIOUR_IDLE);
		MutablePart(ship)->behaviour = BEHAVIOUR_ATTACK_BREAK_OFF_TARGET;
		[ship behaviour_attack_break_off_target:0.1];
		OO_CHECK(Part(ship)->behaviour == BEHAVIOUR_IDLE);
	}
}


// --- Slice 12: behaviours: attack target, broadside, close with target (bead oo-0akes) --------------

// With no target the attack behaviours note the lost target and go idle.
OO_TEST(attackBehavioursWithoutATarget)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = [[[TestShip alloc] cxx_initWithKey:"attacker" definition:Definition()] autorelease];
		MutablePart(ship)->behaviour = BEHAVIOUR_ATTACK_BROADSIDE;
		[ship behaviour_attack_broadside:0.1];
		OO_CHECK(Part(ship)->behaviour == BEHAVIOUR_IDLE);
		MutablePart(ship)->behaviour = BEHAVIOUR_ATTACK_BROADSIDE_LEFT;
		[ship behaviour_attack_broadside_left:0.1];
		OO_CHECK(Part(ship)->behaviour == BEHAVIOUR_IDLE);
		MutablePart(ship)->behaviour = BEHAVIOUR_ATTACK_BROADSIDE_RIGHT;
		[ship behaviour_attack_broadside_right:0.1];
		OO_CHECK(Part(ship)->behaviour == BEHAVIOUR_IDLE);
		MutablePart(ship)->behaviour = BEHAVIOUR_CLOSE_TO_BROADSIDE_RANGE;
		[ship behaviour_close_to_broadside_range:0.1];
		OO_CHECK(Part(ship)->behaviour == BEHAVIOUR_IDLE);
		MutablePart(ship)->behaviour = BEHAVIOUR_CLOSE_WITH_TARGET;
		[ship behaviour_close_with_target:0.1];
		OO_CHECK(Part(ship)->behaviour == BEHAVIOUR_IDLE);
	}
}


// -behaviour_attack_target: chooses the next attack behaviour: an unarmed ship (no weapon on any
// mount or subentity) flies from its target, and the choice resets the ship's frustration. The
// broadside on either side, with no target, notes the lost target and goes idle.
OO_TEST(attackTargetChoiceAndBroadsideSides)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = [[[TestShip alloc] cxx_initWithKey:"unarmed" definition:Definition()] autorelease];
		MutablePart(ship)->behaviour = BEHAVIOUR_ATTACK_TARGET;
		MutablePart(ship)->frustration = 5.0f;
		[ship behaviour_attack_target:0.1];
		OO_CHECK(Part(ship)->behaviour == BEHAVIOUR_ATTACK_FLY_FROM_TARGET);
		OO_CHECK(Part(ship)->frustration == 0.0f);

		MutablePart(ship)->behaviour = BEHAVIOUR_ATTACK_BROADSIDE_LEFT;
		[ship behaviour_attack_broadside_target:0.1 leftside:YES];
		OO_CHECK(Part(ship)->behaviour == BEHAVIOUR_IDLE);
		MutablePart(ship)->behaviour = BEHAVIOUR_ATTACK_BROADSIDE_RIGHT;
		[ship behaviour_attack_broadside_target:0.1 leftside:NO];
		OO_CHECK(Part(ship)->behaviour == BEHAVIOUR_IDLE);
	}
}


// --- Slices 13-15: the behaviours (the expectations were run on the Objective-C methods first) ----

namespace {

// A ship in flight at the origin, with a top speed and a scanner, and nothing else.
TestShip *FlyingShip(const char *key)
{
	TestShip *ship = [[[TestShip alloc] cxx_initWithKey:key definition:Definition()] autorelease];
	[ship setMaxFlightSpeed:200];
	[ship setScannerRange:25600];
	[ship setPosition:kZeroHPVector];
	return ship;
}


// A ship the first one targets, at (0, 0, z).
// (Not -addTarget:, which tells the ship's scripts, and a ship has no JavaScript object here.)
TestShip *TargetAt(TestShip *ship, double z)
{
	TestShip *target = FlyingShip("target");
	[target setPosition:make_HPvector(0, 0, z)];
	SetPrimaryTarget(ship, target);
	return target;
}

}	// namespace


// Slices 13 and 14: an attack behaviour with no target to track notes the lost target and goes idle.
OO_TEST(attackBehavioursWithoutATargetGoIdle)
{
	@autoreleasepool
	{
		SetUp();
		const struct { OOBehaviour behaviour; void (*run)(TestShip *); } cases[] =
		{
			{ BEHAVIOUR_ATTACK_SNIPER, [](TestShip *s) { [s behaviour_attack_sniper:0.1]; } },
			{ BEHAVIOUR_ATTACK_FLY_TO_TARGET_SIX, [](TestShip *s) { [s behaviour_fly_to_target_six:0.1]; } },
			{ BEHAVIOUR_ATTACK_MINING_TARGET, [](TestShip *s) { [s behaviour_attack_mining_target:0.1]; } },
			{ BEHAVIOUR_ATTACK_FLY_TO_TARGET, [](TestShip *s) { [s behaviour_attack_fly_to_target:0.1]; } },
			{ BEHAVIOUR_ATTACK_FLY_FROM_TARGET, [](TestShip *s) { [s behaviour_attack_fly_from_target:0.1]; } },
			{ BEHAVIOUR_RUNNING_DEFENSE, [](TestShip *s) { [s behaviour_running_defense:0.1]; } },
			{ BEHAVIOUR_FLEE_TARGET, [](TestShip *s) { [s behaviour_flee_target:0.1]; } },
		};
		for (const auto &c : cases)
		{
			TestShip *ship = FlyingShip("lonely");
			[ship setBehaviour:c.behaviour];
			SetFrustration(ship, 2);
			c.run(ship);
			OO_CHECK(Behaviour(ship) == BEHAVIOUR_IDLE && [ship frustration] == 0);
		}

		// The miner also slows to three eighths of its top speed.
		TestShip *miner = FlyingShip("miner");
		[miner behaviour_attack_mining_target:0.1];
		OO_CHECK([miner desiredSpeed] == 200 * 0.375);
	}
}


// Slice 13: the sniper closes in to attack inside 15 km, and outside it flies at top speed while
// out of weapon range.
OO_TEST(sniper)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = FlyingShip("sniper");
		TargetAt(ship, 1000);
		[ship setBehaviour:BEHAVIOUR_ATTACK_SNIPER];
		[ship behaviour_attack_sniper:0.1];
		OO_CHECK(Behaviour(ship) == BEHAVIOUR_ATTACK_TARGET);

		TestShip *distant = FlyingShip("distant sniper");
		TargetAt(distant, 20000);
		[distant setBehaviour:BEHAVIOUR_ATTACK_SNIPER];
		[distant behaviour_attack_sniper:0.1];
		OO_CHECK(Behaviour(distant) == BEHAVIOUR_ATTACK_SNIPER && [distant desiredSpeed] == 200);
	}
}


// Slice 13: a ship already at the point it was heading for vectors in to attack at 0.4 of its top
// speed (the target is at a standstill); the miner closes on a rock at seven eighths of it; and an
// attacker inside its weapon range starts its attack run.
OO_TEST(attackApproaches)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *six = FlyingShip("six");
		TargetAt(six, 2000);
		[six setBehaviour:BEHAVIOUR_ATTACK_FLY_TO_TARGET_SIX];
		[six behaviour_fly_to_target_six:0.1];
		OO_CHECK(Behaviour(six) == BEHAVIOUR_ATTACK_FLY_TO_TARGET && [six desiredSpeed] == 200 * 0.4);

		TestShip *miner = FlyingShip("miner");
		TargetAt(miner, 2000);
		[miner setBehaviour:BEHAVIOUR_ATTACK_MINING_TARGET];
		[miner behaviour_attack_mining_target:0.1];
		OO_CHECK(Behaviour(miner) == BEHAVIOUR_ATTACK_MINING_TARGET && [miner desiredSpeed] == 200 * 0.875);

		TestShip *attacker = FlyingShip("attacker");
		TargetAt(attacker, 1000);
		[attacker setWeaponRange:30000];
		[attacker setBehaviour:BEHAVIOUR_ATTACK_FLY_TO_TARGET];
		[attacker behaviour_attack_fly_to_target:0.1];
		OO_CHECK(Behaviour(attacker) == BEHAVIOUR_ATTACK_TARGET);
	}
}


// Slice 14: the destination behaviours that only decide.
OO_TEST(destinationDecisions)
{
	@autoreleasepool
	{
		SetUp();
		// Inside the range it should keep: fly away from the destination, at least at top speed.
		TestShip *ship = FlyingShip("ranger");
		[ship setDestination:make_HPvector(0, 0, 100)];
		[ship setDesiredRange:500];
		[ship setDesiredSpeed:10];
		SetFrustration(ship, 3);
		[ship behaviour_fly_range_from_destination:0.1];
		OO_CHECK(Behaviour(ship) == BEHAVIOUR_FLY_FROM_DESTINATION && [ship desiredSpeed] == 200 && [ship frustration] == 0);

		// Outside it: fly to the destination.
		[ship setDesiredRange:50];
		[ship behaviour_fly_range_from_destination:0.1];
		OO_CHECK(Behaviour(ship) == BEHAVIOUR_FLY_TO_DESTINATION);

		// Facing a destination stops the ship.
		TestShip *facer = FlyingShip("facer");
		[facer setDestination:make_HPvector(0, 1000, 0)];
		[facer setDesiredSpeed:50];
		[facer setBehaviour:BEHAVIOUR_FACE_DESTINATION];
		[facer behaviour_face_destination:0.1];
		OO_CHECK([facer desiredSpeed] == 0);

		// Landing with no planet to land on: idle, and the JS AI is woken to reconsider.
		TestShip *lander = FlyingShip("lander");
		SetPlanetForLanding(lander, NO_TARGET);
		[lander setBehaviour:BEHAVIOUR_LAND_ON_PLANET];
		[lander behaviour_land_on_planet:0.1];
		OO_CHECK(Behaviour(lander) == BEHAVIOUR_IDLE && [lander shipAIScriptWakeTime] == 1 && [lander desiredSpeed] == 0);

		// Forming up with no leader: top speed.
		TestShip *escort = FlyingShip("escort");
		[escort setDestination:make_HPvector(0, 0, 3000)];
		[escort setBehaviour:BEHAVIOUR_FORMATION_FORM_UP];
		[escort behaviour_formation_form_up:0.1];
		OO_CHECK([escort desiredSpeed] == 200);
	}
}


// Slice 15: arriving, leaving, resuming after a proximity alert, and the navpoints.
OO_TEST(destinationArrivals)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = FlyingShip("arriving");
		[ship setDestination:make_HPvector(0, 0, 10)];
		[ship setDesiredRange:100];
		[ship setDesiredSpeed:50];
		SetFrustration(ship, 3);
		[ship setBehaviour:BEHAVIOUR_FLY_TO_DESTINATION];
		[ship behaviour_fly_to_destination:0.1];
		OO_CHECK(Behaviour(ship) == BEHAVIOUR_IDLE && [ship desiredSpeed] == 0 && [ship frustration] == 0);

		TestShip *leaving = FlyingShip("leaving");
		[leaving setDestination:make_HPvector(0, 0, 1000)];
		[leaving setDesiredRange:100];
		[leaving setDesiredSpeed:50];
		[leaving setBehaviour:BEHAVIOUR_FLY_FROM_DESTINATION];
		[leaving behaviour_fly_from_destination:0.1];
		OO_CHECK(Behaviour(leaving) == BEHAVIOUR_IDLE && [leaving desiredSpeed] == 0);

		// Clear of the obstacle: what the ship did before the alert resumes.
		TestShip *avoider = FlyingShip("avoider");
		[avoider setDestination:make_HPvector(0, 0, 1000)];
		[avoider setDesiredRange:100];
		[avoider setBehaviour:BEHAVIOUR_AVOID_COLLISION];
		SetFrustration(avoider, 3);
		SetPreviousCondition(avoider, oo::PList(oo::PList::Dict{
			{ "behaviour", oo::PList((double)BEHAVIOUR_FLY_TO_DESTINATION) },
			{ "desired_range", oo::PList(300.0) },
			{ "desired_speed", oo::PList(12.0) } }));
		[avoider behaviour_avoid_collision:0.1];
		OO_CHECK(Behaviour(avoider) == BEHAVIOUR_FLY_TO_DESTINATION && [avoider desiredRange] == 300 && [avoider desiredSpeed] == 12 && [avoider frustration] == 0);

		// A turret with no mount and no targets does nothing.
		TestShip *turret = FlyingShip("turret");
		[turret setBehaviour:BEHAVIOUR_TRACK_AS_TURRET];
		[turret behaviour_track_as_turret:0.1];
		OO_CHECK(Behaviour(turret) == BEHAVIOUR_TRACK_AS_TURRET);

		// Reaching a navpoint moves on to the next; reaching the last one is the end of the route.
		TestShip *nav = FlyingShip("navigator");
		[nav setDesiredRange:50];
		[nav setBehaviour:BEHAVIOUR_FLY_THRU_NAVPOINTS];
		SetNavpoints(nav, { make_HPvector(0, 0, 10), make_HPvector(0, 0, 5000), make_HPvector(0, 5000, 5000) }, 0);
		[nav behaviour_fly_thru_navpoints:0.1];
		OO_CHECK(NextNavpoint(nav) == 1 && Behaviour(nav) == BEHAVIOUR_FLY_THRU_NAVPOINTS);
		SetNavpoints(nav, { make_HPvector(0, 5000, 5000), make_HPvector(0, 0, 10) }, 1);
		[nav behaviour_fly_thru_navpoints:0.1];
		OO_CHECK(NextNavpoint(nav) == 0 && Behaviour(nav) == BEHAVIOUR_IDLE);
	}
}


// Slice 15: a scripted AI with no ship script reverts to idle; the reaction time, and the target
// position it leads by.
OO_TEST(scriptedAIAndReactionTime)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = FlyingShip("scripted");
		[ship setBehaviour:BEHAVIOUR_SCRIPTED_AI];
		[ship behaviour_scripted_ai:0.1];
		OO_CHECK(Behaviour(ship) == BEHAVIOUR_IDLE);

		OO_CHECK([ship reactionTime] == 0);
		[ship setReactionTime:0.75f];
		OO_CHECK([ship reactionTime] == 0.75f);

		OO_CHECK(HPvector_equal([ship calculateTargetPosition], kZeroHPVector));		// no target
		TestShip *hunter = FlyingShip("hunter");
		TargetAt(hunter, 1234);
		OO_CHECK(HPvector_equal([hunter calculateTargetPosition], make_HPvector(0, 0, 1234)));	// no reaction time: where it is
	}
}


// Slice 16: the tracking curve through a target that is standing still is that target's position,
// with or without a reaction time.
OO_TEST(trackingCurve)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = FlyingShip("tracker");
		[ship setReactionTime:0.6f];
		TargetAt(ship, 1500);
		[ship startTrackingCurve];
		HPVector led = [ship calculateTargetPosition];
		OO_CHECK(fabs(led.x) < 1e-6 && fabs(led.y) < 1e-6 && fabs(led.z - 1500) < 1e-6);
		[ship updateTrackingCurve];	// too soon after the start: unchanged
		led = [ship calculateTargetPosition];
		OO_CHECK(fabs(led.z - 1500) < 1e-6);

		[ship setReactionTime:0];
		[ship calculateTrackingCurve];
		OO_CHECK(HPvector_equal([ship calculateTargetPosition], make_HPvector(0, 0, 1500)));
	}
}


// Slice 16: the scanner colours, scripted and by scan class.
OO_TEST(scannerColours)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = FlyingShip("coloured");
		OOColor *red = [OOColor colorWithRed:1 green:0 blue:0 alpha:1];
		OOColor *blue = [OOColor colorWithRed:0 green:0 blue:1 alpha:1];
		OO_CHECK([ship scannerDisplayColor1] == nil && [ship scannerDisplayColorHostile2] == nil);
		[ship setScannerDisplayColor1:red];
		[ship setScannerDisplayColor2:blue];
		[ship setScannerDisplayColorHostile1:blue];
		[ship setScannerDisplayColorHostile2:red];
		OO_CHECK([ship scannerDisplayColor1] == red && [ship scannerDisplayColor2] == blue);
		OO_CHECK([ship scannerDisplayColorHostile1] == blue && [ship scannerDisplayColorHostile2] == red);
		[ship setScannerDisplayColor2:nil];		// nil: the ship's definition's, which has none
		OO_CHECK([ship scannerDisplayColor2] == nil);

		TestShip *other = FlyingShip("viewer");
		GLfloat *c = [ship scannerDisplayColorForShip:other isHostile:NO flash:YES scannerDisplayColor1:red scannerDisplayColor2:nil scannerDisplayColorH1:nil scannerDisplayColorH2:nil];
		OO_CHECK(c[0] == 1 && c[1] == 0 && c[2] == 0 && c[3] == 1);
		c = [ship scannerDisplayColorForShip:other isHostile:YES flash:NO scannerDisplayColor1:red scannerDisplayColor2:nil scannerDisplayColorH1:red scannerDisplayColorH2:blue];	// hostile, not flashing: the second
		OO_CHECK(c[0] == 0 && c[2] == 1);
		[ship setScanClass:CLASS_CARGO];
		c = [ship scannerDisplayColorForShip:other isHostile:NO flash:NO scannerDisplayColor1:nil scannerDisplayColor2:nil scannerDisplayColorH1:nil scannerDisplayColorH2:nil];
		OO_CHECK(c[0] == 0.9f && c[1] == 0.9f && c[2] == 0.9f && c[3] == 1);
		[ship setScanClass:CLASS_POLICE];
		c = [ship scannerDisplayColorForShip:other isHostile:YES flash:YES scannerDisplayColor1:nil scannerDisplayColor2:nil scannerDisplayColorH1:nil scannerDisplayColorH2:nil];
		OO_CHECK(c[0] == 1 && c[1] == 0 && c[2] == 0.5f);
		[ship setScanClass:CLASS_NEUTRAL];
		c = [ship scannerDisplayColorForShip:other isHostile:NO flash:NO scannerDisplayColor1:nil scannerDisplayColor2:nil scannerDisplayColorH1:nil scannerDisplayColorH2:nil];
		OO_CHECK(c[0] == 1 && c[1] == 1 && c[2] == 0);
	}
}


// Slice 16: cloaking flags, owner, thrust and orientation.
OO_TEST(cloakOwnerThrustAndOrientation)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = FlyingShip("flier");
		OO_CHECK(![ship isCloaked] && ![ship hasAutoCloak] && ![ship isJammingScanning]);
		[ship setAutoCloak:YES];
		OO_CHECK([ship hasAutoCloak]);

		TestShip *mother = FlyingShip("mother");
		[ship setOwner:mother];
		OO_CHECK([ship owner] == mother);
		[ship setOwner:nil];

		// Full thrust from a standstill: up to the desired speed, and forward by speed x time.
		[ship setThrust:1000];
		[ship setDesiredSpeed:100];
		[ship applyThrust:0.5];
		OO_CHECK([ship flightSpeed] == 100);
		OO_CHECK(fabs([ship position].z - 50) < 1e-6);

		// Turned at random: the vectors follow the orientation.
		Quaternion q;
		quaternion_set_random(&q);
		[ship setOrientation:q];
		Vector f = [ship forwardVector], expected = vector_forward_from_quaternion([ship orientation]);
		OO_CHECK(fabs(f.x - expected.x) < 1e-6 && fabs(f.y - expected.y) < 1e-6 && fabs(f.z - expected.z) < 1e-6);
	}
}


// Slice 17: rolling, climbing and yawing turn the ship by the product of the turns, and update its
// vectors; with no turn and no rotation so far, nothing happens.
OO_TEST(attitude)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = FlyingShip("acrobat");
		[ship applyRoll:0 andClimb:0];
		OO_CHECK(quaternion_equal([ship orientation], kIdentityQuaternion));

		Quaternion q = kIdentityQuaternion;
		quaternion_rotate_about_z(&q, -0.1f);
		quaternion_rotate_about_x(&q, -0.2f);
		[ship applyRoll:0.1f andClimb:0.2f];
		Quaternion o = [ship orientation];
		OO_CHECK(fabs(o.w - q.w) < 1e-6 && fabs(o.x - q.x) < 1e-6 && fabs(o.y - q.y) < 1e-6 && fabs(o.z - q.z) < 1e-6);
		Vector f = [ship forwardVector], expected = vector_forward_from_quaternion(o);
		OO_CHECK(fabs(f.x - expected.x) < 1e-6 && fabs(f.y - expected.y) < 1e-6 && fabs(f.z - expected.z) < 1e-6);

		// The attitude rates times the time step, as one turn.
		TestShip *a = FlyingShip("rates");
		TestShip *b = FlyingShip("by hand");
		[a setRoll:0.5];
		[a setPitch:0.25];
		[a setYaw:-0.5];
		[a applyAttitudeChanges:0.2];
		[b applyRoll:(GLfloat)(0.5 * M_PI / 2.0) * 0.2 climb:(GLfloat)(0.25 * M_PI / 2.0) * 0.2 andYaw:(GLfloat)(-0.5 * M_PI / 2.0) * 0.2];	// -setRoll: is a fraction of a right angle
		Quaternion qa = [a orientation], qb = [b orientation];
		OO_CHECK(fabs(qa.w - qb.w) < 1e-6 && fabs(qa.x - qb.x) < 1e-6 && fabs(qa.y - qb.y) < 1e-6 && fabs(qa.z - qb.z) < 1e-6);
	}
}


// Slice 17: avoiding a collision remembers what the ship was doing and heads for the point between
// the two ships; resuming restores it.
OO_TEST(avoidCollisionAndResume)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = FlyingShip("careful");
		TestShip *rock = FlyingShip("rock");
		[rock setPosition:make_HPvector(0, 0, 400)];
		[ship setBehaviour:BEHAVIOUR_FLY_TO_DESTINATION];
		[ship setDestination:make_HPvector(0, 0, 9000)];
		[ship setDesiredRange:300];
		[ship setDesiredSpeed:12];

		[ship avoidCollision];		// no alert: nothing
		OO_CHECK(Behaviour(ship) == BEHAVIOUR_FLY_TO_DESTINATION);

		SetProximityAlert(ship, rock);
		OO_CHECK([ship proximityAlert] == rock);
		[ship avoidCollision];
		OO_CHECK(Behaviour(ship) == BEHAVIOUR_AVOID_COLLISION);
		OO_CHECK(HPvector_equal([ship destination], make_HPvector(0, 0, 200)));

		[ship resumePostProximityAlert];
		OO_CHECK(Behaviour(ship) == BEHAVIOUR_FLY_TO_DESTINATION && [ship desiredRange] == 300 && [ship desiredSpeed] == 12);
		OO_CHECK(HPvector_equal([ship destination], make_HPvector(0, 0, 9000)));
		OO_CHECK([ship proximityAlert] == nil);

		// A missile does not avoid anything.
		[ship setScanClass:CLASS_MISSILE];
		SetProximityAlert(ship, rock);
		[ship avoidCollision];
		OO_CHECK(Behaviour(ship) == BEHAVIOUR_FLY_TO_DESTINATION);

		// Clearing the alert, and a light object never raises one.
		[ship setProximityAlert:nil];
		OO_CHECK([ship proximityAlert] == nil);
		[ship setProximityAlert:rock];		// mass 0
		OO_CHECK([ship proximityAlert] == nil);
	}
}


// Slice 17: message time, groups and escorts.
OO_TEST(groupsAndEscorts)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = FlyingShip("leader");
		[ship setMessageTime:4.5];
		OO_CHECK([ship messageTime] == 4.5);

		OO_CHECK(![ship hasEscorts] && [ship escortCount] == 0 && [ship cxx_escorts].empty());
		OOShipGroup *escorts = [ship escortGroup];		// made on demand, led by the ship
		OO_CHECK(escorts != nil && [escorts leader] == ship && [ship escortGroup] == escorts);
		TestShip *wingman = FlyingShip("wingman");
		[escorts addShip:wingman];
		OO_CHECK([ship hasEscorts] && [ship escortCount] == 1);
		OO_CHECK([ship cxx_escorts].size() == 1 && [ship cxx_escorts][0].get() == wingman && [ship escortArray].size() == 1);

		OOShipGroup *other = [[[OOShipGroup alloc] init] autorelease];
		[ship setEscortGroup:other];
		OO_CHECK([ship escortGroup] == other && [other leader] == ship);

		OOShipGroup *group = [[[OOShipGroup alloc] init] autorelease];
		[wingman setGroup:group];
		OO_CHECK([wingman group] == group && [group containsShip:wingman]);
		[wingman setGroup:nil];
		OO_CHECK([wingman group] == nil && ![group containsShip:wingman]);

		TestShip *station = FlyingShip("station");
		OOShipGroup *stationGroup = [station stationGroup];
		OO_CHECK(stationGroup != nil && [stationGroup leader] == station && [station group] == stationGroup);

		[ship setMaxEscortCount:3];
		[ship setPendingEscortCount:5];
		OO_CHECK([ship maxEscortCount] == 3 && [ship pendingEscortCount] == 3);
		OO_CHECK([ship turretCount] == 0);
	}
}


// Slice 17: the names, and what the ship is called on screen.
OO_TEST(names)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = FlyingShip("named");
		[ship cxx_setName:std::string("Cobra Mk III")];
		OO_CHECK([ship cxx_name] == std::optional<std::string>("Cobra Mk III"));
		OO_CHECK([ship displayName] == std::optional<std::string>("Cobra Mk III"));
		[ship cxx_setShipUniqueName:std::string("Lucky")];
		OO_CHECK([ship cxx_shipUniqueName] == std::optional<std::string>("Lucky"));
		OO_CHECK([ship displayName] == std::optional<std::string>("Cobra Mk III: Lucky"));
		[ship cxx_setShipClassName:std::string("Cobra")];
		OO_CHECK([ship cxx_shipClassName] == std::optional<std::string>("Cobra"));
		OO_CHECK([ship displayName] == std::optional<std::string>("Cobra: Lucky"));
		[ship cxx_setShipUniqueName:std::string("")];
		OO_CHECK([ship displayName] == std::optional<std::string>("Cobra"));
		[ship cxx_setDisplayName:std::string("The Cobra")];
		OO_CHECK([ship displayName] == std::optional<std::string>("The Cobra"));

		OO_CHECK([ship cxx_scanDescriptionForScripting] == std::nullopt);
		[ship cxx_setScanDescription:std::string("Trader")];
		OO_CHECK([ship cxx_scanDescription] == std::optional<std::string>("Trader") && [ship cxx_scanDescriptionForScripting] == std::optional<std::string>("Trader"));
	}
}


// Slice 18: roles. A ship has its primary role, its data key's automatic role and the roles of its
// role set; adding is a no-op for a role it has.
OO_TEST(roles)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = FlyingShip("cobra3-trader");
		[ship setPrimaryRole:"trader"];
		OO_CHECK([ship cxx_primaryRole] == std::optional<std::string>("trader") && [ship cxx_hasPrimaryRole:"trader"]);
		OO_CHECK([ship hasRole:"trader"] && [ship hasRole:"[cobra3-trader]"] && ![ship hasRole:"pirate"]);
		[ship addRole:"pirate"];
		OO_CHECK([ship hasRole:"pirate"]);
		[ship cxx_addRole:"hunter" withProbability:0.5f];
		OO_CHECK([ship hasRole:"hunter"]);
		OORoleSet *roles = [ship roleSet];
		OO_CHECK([roles hasRole:"pirate"] && [roles hasRole:"hunter"] && [roles hasRole:"trader"] && [roles hasRole:"[cobra3-trader]"]);
		[ship cxx_removeRole:"pirate"];
		OO_CHECK(![ship hasRole:"pirate"] && [ship hasRole:"hunter"]);

		// The weapons are known by their primary role.
		[ship setPrimaryRole:"EQ_HARDENED_MISSILE"];
		OO_CHECK([ship isMissile] && ![ship isMine] && [ship isWeapon]);
		[ship setPrimaryRole:"missile"];
		OO_CHECK([ship isMissile]);
		[ship setPrimaryRole:"EQ_QC_MINE"];
		OO_CHECK(![ship isMissile] && [ship isMine] && [ship isWeapon]);
	}
}


// Slice 18: the ship-type predicates that do not ask the universe, and hostility.
OO_TEST(typesAndHostility)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = FlyingShip("viper");
		[ship setScanClass:CLASS_POLICE];
		OO_CHECK([ship isPolice] && ![ship isThargoid]);
		[ship setScanClass:CLASS_THARGOID];
		OO_CHECK(![ship isPolice] && [ship isThargoid]);
		OO_CHECK(![ship isUnpiloted] && ![ship isExplicitlyUnpiloted]);
		[ship setScanClass:CLASS_CARGO];
		OO_CHECK([ship isUnpiloted]);
		[ship setScanClass:CLASS_NEUTRAL];
		[ship setBehaviour:BEHAVIOUR_TRACK_AS_TURRET];
		OO_CHECK([ship isTurret]);

		// Hostile: a ship target and an attacking behaviour (or one it will resume after an alert).
		[ship setBehaviour:BEHAVIOUR_ATTACK_TARGET];
		OO_CHECK(![ship hasHostileTarget]);		// no target
		TestShip *target = TargetAt(ship, 1000);
		OO_CHECK([ship hasHostileTarget] && [ship isHostileTo:target] && ![ship isHostileTo:ship]);
		[ship setBehaviour:BEHAVIOUR_FLY_TO_DESTINATION];
		OO_CHECK(![ship hasHostileTarget]);
		[ship setBehaviour:BEHAVIOUR_AVOID_COLLISION];
		SetPreviousCondition(ship, oo::PList(oo::PList::Dict{ { "behaviour", oo::PList((double)BEHAVIOUR_ATTACK_SNIPER) } }));
		OO_CHECK([ship hasHostileTarget]);
		[ship setBehaviour:BEHAVIOUR_IDLE];
		[ship setPrimaryRole:"missile"];
		OO_CHECK([ship hasHostileTarget]);		// a missile's target always is

		// Without a jammer, a ship is identified by its display name.
		[ship cxx_setDisplayName:std::string("Viper")];
		OO_CHECK([ship identFromShip:target] == std::optional<std::string>("Viper"));
	}
}


// Slice 18: the weapon and scanner values, and leaving the aegis.
OO_TEST(weaponAndScannerValues)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = FlyingShip("gunship");
		[ship setWeaponRange:5000];
		OO_CHECK([ship weaponRange] == 5000);
		[ship setEnergyRechargeRate:2.5f];
		OO_CHECK([ship energyRechargeRate] == 2.5f);
		[ship setWeaponRechargeRate:0.5f];
		OO_CHECK([ship weaponRechargeRate] == 0.5f);
		[ship setWeaponEnergy:12];
		OO_CHECK(WeaponDamage(ship) == 12);
		[ship setWeaponDataFromType:nil];		// no weapon: nothing
		OO_CHECK([ship weaponRange] == 0 && [ship weaponRechargeRate] == 0 && WeaponDamage(ship) == 0);
		OO_CHECK([ship currentWeaponFacing] == WEAPON_FACING_FORWARD);
		[ship setScannerRange:30000];
		OO_CHECK([ship scannerRange] == 30000);
		[ship setReference:make_vector(1, 2, 3)];
		OO_CHECK(vector_equal([ship reference], make_vector(1, 2, 3)));
		OO_CHECK(![ship reportAIMessages]);
		[ship setReportAIMessages:YES];
		OO_CHECK([ship reportAIMessages]);

		SetAegisStatus(ship, AEGIS_IN_DOCKING_RANGE);
		[ship transitionToAegisNone];
		OO_CHECK(AegisStatus(ship) == AEGIS_NONE);
	}
}


// Slice 19: the aegis bookkeeping, the systems, the status and the launch delay.
OO_TEST(aegisSystemsAndStatus)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = FlyingShip("navigator");
		[ship forceAegisCheck];
		OO_CHECK(NextAegisCheck(ship) == -1.0);
		OO_CHECK(![ship withinStationAegis]);
		SetAegisStatus(ship, AEGIS_IN_DOCKING_RANGE);
		OO_CHECK([ship withinStationAegis]);

		OO_CHECK([ship lastAegisLock] == nil);
		TestShip *body = FlyingShip("stand-in for a planet");
		[ship setLastAegisLock:(Entity<OOStellarBody> *)body];
		OO_CHECK([ship lastAegisLock] == (Entity<OOStellarBody> *)body);
		[ship setLastAegisLock:nil];
		OO_CHECK([ship lastAegisLock] == nil);

		[ship setHomeSystem:7];
		[ship setDestinationSystem:42];
		OO_CHECK([ship homeSystem] == 7 && [ship destinationSystem] == 42);

		[ship setStatus:STATUS_LAUNCHING];
		OO_CHECK([ship status] == STATUS_LAUNCHING && LaunchTime(ship) == [UNIVERSE getTime]);
		[ship setStatus:STATUS_IN_FLIGHT];
		OO_CHECK([ship status] == STATUS_IN_FLIGHT);
		[ship setLaunchDelay:2.5];
		OO_CHECK(LaunchDelay(ship) == 2.5);
	}
}


// Slice 19: the crew, the AI and the flags read from the definition.
OO_TEST(crewAndAI)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = FlyingShip("crewed");
		OO_CHECK(![ship cxx_crew].has_value() && [ship cxx_crewForScripting].empty());
		[ship cxx_setCrew:std::vector<oo::ObjCRef<OOCharacter *>>{}];
		OO_CHECK([ship cxx_crew].has_value() && [ship cxx_crew]->empty());
		SetExplicitlyUnpiloted(ship, true);
		[ship cxx_setCrew:std::vector<oo::ObjCRef<OOCharacter *>>{}];	// unpiloted ships have none
		OO_CHECK(![ship cxx_crew].has_value());

		OO_CHECK([ship getAI] == nil && ![ship hasNewAI]);
		AI *ai = [[[AI alloc] init] autorelease];
		[ship setAI:ai];
		OO_CHECK([ship getAI] == ai);
		[ship setAI:nil];
		OO_CHECK([ship getAI] == nil);

		OO_CHECK([ship hasAutoAI] && ![ship hasAutoWeapons]);	// the definition says neither
		OO_CHECK([ship frustration] == 0);
	}
}


// Slice 19: fuel is clamped to the capacity.
OO_TEST(fuel)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = FlyingShip("tanker");
		OO_CHECK([ship fuelCapacity] == PLAYER_MAX_FUEL);
		[ship setFuel:35];
		OO_CHECK([ship fuel] == 35);
		[ship setFuel:PLAYER_MAX_FUEL + 10];
		OO_CHECK([ship fuel] == PLAYER_MAX_FUEL);
	}
}


// Slice 20: the sticks move the flight rates towards them by a limited step; the rate setters.
OO_TEST(sticksAndRates)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = FlyingShip("pilot");
		SetSticks(ship, 1.0f, -1.0f, 0.01f);
		[ship applySticks:0.1];			// roll moves 2 x dt, pitch and yaw 4 x dt, or reach the stick
		OO_CHECK(fabs([ship flightRoll] - 0.2f) < 1e-6 && fabs([ship flightPitch] + 0.4f) < 1e-6 && fabs([ship flightYaw] - 0.01f) < 1e-6);
		SetSticks(ship, -1.0f, -1.0f, 0.01f);
		[ship applySticks:0.1];			// against the current roll: four times faster
		OO_CHECK(fabs([ship flightRoll] - (0.2f - 0.8f)) < 1e-6);

		[ship setRoll:1];
		OO_CHECK(fabs([ship flightRoll] - M_PI / 2.0) < 1e-6);
		[ship setRawRoll:0.25];
		OO_CHECK([ship flightRoll] == 0.25f);
		[ship setPitch:-1];
		[ship setYaw:0.5];
		OO_CHECK(fabs([ship flightPitch] + M_PI / 2.0) < 1e-6 && fabs([ship flightYaw] - M_PI / 4.0) < 1e-6);
		[ship setThrust:12];
		OO_CHECK([ship thrust] == 12);
		[ship setThrustForDemo:0.5f];
		OO_CHECK([ship flightSpeed] == 100);
		[ship setSpeed:42];
		OO_CHECK([ship flightSpeed] == 42);
		[ship setDesiredSpeed:17];
		OO_CHECK([ship desiredSpeed] == 17);
	}
}


// Slice 20: bounty and legal status.
OO_TEST(bountyAndLegalStatus)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = FlyingShip("offender");
		[ship setBounty:40];
		OO_CHECK([ship bounty] == 40 && [ship legalStatus] == 40);
		[ship setBounty:60 withReason:kOOLegalStatusReasonByScript];
		OO_CHECK([ship bounty] == 60);
		[ship setBounty:5 withReasonAsString:"setup"];
		OO_CHECK([ship bounty] == 5);

		[ship setScanClass:CLASS_POLICE];
		[ship setBounty:30];		// police never have bounties
		OO_CHECK([ship bounty] == 5);
		[ship setScanClass:CLASS_THARGOID];
		[ship setBounty:30];		// nor do Thargoids, but by script or set-up
		OO_CHECK([ship bounty] == 5);
		[ship setBounty:30 withReason:kOOLegalStatusReasonSetup];
		OO_CHECK([ship bounty] == 30);
		[ship setCollisionRadius:20];
		OO_CHECK([ship legalStatus] == 100);	// a Thargoid's is five times its radius
		[ship setScanClass:CLASS_ROCK];
		OO_CHECK([ship legalStatus] == 0);
	}
}


// Slice 20: commodities and cargo.
OO_TEST(commoditiesAndCargo)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *pod = FlyingShip("pod");
		OO_CHECK(![pod cxx_commodityType].has_value() && [pod commodityAmount] == 0);
		[pod cxx_setCommodity:"food" andAmount:3];
		OO_CHECK([pod cxx_commodityType] == std::optional<std::string>("food") && [pod commodityAmount] == 3);

		TestShip *ship = FlyingShip("hauler");
		[ship setMaxAvailableCargoSpace:3];
		OO_CHECK([ship maxAvailableCargoSpace] == 3 && [ship availableCargoSpace] == 3 && [ship cargoQuantityOnBoard] == 0);
		TestShip *food = FlyingShip("food pod");
		[food cxx_setCommodity:"food" andAmount:1];
		TestShip *gold = FlyingShip("gold pod");
		[gold cxx_setCommodity:"gold" andAmount:1];
		[ship setCargo:{ oo::ObjCRef<ShipEntity *>(food), oo::ObjCRef<ShipEntity *>(gold) }];
		OO_CHECK([ship cxx_cargoCount] == 2 && [ship cargoQuantityOnBoard] == 2 && [ship availableCargoSpace] == 1);
		OO_CHECK([ship cxx_cargo]->size() == 2 && (*[ship cxx_cargo])[1].get() == gold);
		OO_CHECK((![ship cxx_addCargo:{ oo::ObjCRef<ShipEntity *>(food), oo::ObjCRef<ShipEntity *>(food) }]));	// no room
		OO_CHECK([ship cxx_addCargo:{ oo::ObjCRef<ShipEntity *>(food) }] && [ship cxx_cargoCount] == 3);
		OO_CHECK(![ship cxx_removeCargo:"gold" amount:2]);		// not that many: nothing removed
		OO_CHECK([ship cxx_cargoCount] == 3);
		OO_CHECK([ship cxx_removeCargo:"food" amount:2] && [ship cxx_cargoCount] == 1 && (*[ship cxx_cargo])[0].get() == gold);

		OO_CHECK([ship cargoFlag] == (OOCargoFlag)0 && ![ship showScoopMessage]);	// TestShip skips the set-up that reads both
		[ship setMaxAvailableCargoSpace:0];
		[ship setCargoFlag:CARGO_FLAG_FULL_PASSENGERS];		// no room: no cargo
		OO_CHECK([ship cargoFlag] == CARGO_FLAG_FULL_PASSENGERS && [ship cxx_cargoCount] == 0);
	}
}


// Slice 21: the flight controls, clamped to the ship's limits.
OO_TEST(flightControls)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = FlyingShip("controls");
		[ship setDesiredRange:750];
		OO_CHECK([ship desiredRange] == 750 && [ship cruiseSpeed] == 0);

		[ship increase_flight_speed:50];
		OO_CHECK([ship flightSpeed] == 50);
		[ship increase_flight_speed:500];		// past the top speed: overshoots once
		OO_CHECK([ship flightSpeed] == 550);
		[ship increase_flight_speed:1];			// then is the top speed
		OO_CHECK([ship flightSpeed] == 200);
		OO_CHECK([ship speedFactor] == 1);
		[ship decrease_flight_speed:150];
		OO_CHECK([ship flightSpeed] == 50);
		[ship decrease_flight_speed:80];
		OO_CHECK([ship flightSpeed] == 0);

		[ship setMaxFlightRoll:2];
		[ship setMaxFlightPitch:1];
		[ship setMaxFlightYaw:0.5f];
		OO_CHECK([ship maxFlightRoll] == 2 && [ship maxFlightPitch] == 1 && [ship maxFlightYaw] == 0.5f);
		[ship increase_flight_roll:3];
		[ship increase_flight_pitch:0.25];
		[ship decrease_flight_yaw:1];
		OO_CHECK([ship flightRoll] == 2 && [ship flightPitch] == 0.25f && [ship flightYaw] == -0.5f);
		[ship decrease_flight_roll:5];
		[ship decrease_flight_pitch:0.5];
		[ship increase_flight_yaw:2];
		OO_CHECK([ship flightRoll] == -2 && [ship flightPitch] == -0.25f && [ship flightYaw] == 0.5f);

		[ship setMaxFlightSpeed:0];
		OO_CHECK([ship speedFactor] == 0 && [ship maxFlightSpeed] == 0);
	}
}


// Slice 21: temperature, insulation, damage and hulks.
OO_TEST(temperatureDamageAndHulks)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = FlyingShip("hot");
		OO_CHECK([ship temperature] == SHIP_MIN_CABIN_TEMP);
		OO_CHECK([ship randomEjectaTemperature] == SHIP_MIN_CABIN_TEMP);	// a cold ship's debris is as cold
		[ship setTemperature:500];
		OO_CHECK([ship temperature] == 500);
		float ejecta = [ship randomEjectaTemperatureWithMaxFactor:0.5f];
		OO_CHECK(ejecta > SHIP_MIN_CABIN_TEMP && ejecta < 500);
		[ship setHeatInsulation:2];
		OO_CHECK([ship heatInsulation] == 2);

		[ship setMaxEnergy:200];
		[ship setEnergy:150];
		OO_CHECK([ship damage] == 25);

		OO_CHECK(![ship isHulk]);
		[ship setHulk:YES];
		OO_CHECK([ship isHulk] && [ship isUnpiloted]);
		[ship setHulk:NO];
		TestShip *sub = FlyingShip("turret");
		SetSubEntity(sub, true);
		[sub setHulk:YES];		// a subentity never is
		OO_CHECK(![sub isHulk]);
		SetSubEntity(sub, false);
	}
}


// Slice 22: a ship with no model rescales its scale factor and its mass (by the cube), and its
// subentities' positions; wreckage and the damage flag; a ship with no cargo throws nothing out.
OO_TEST(rescaleWreckageAndDebris)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = FlyingShip("big");
		TestShip *sub = FlyingShip("part");
		[sub setPosition:make_HPvector(1, 2, 3)];
		[ship addSubEntity:sub];
		const GLfloat scale = ScaleFactor(ship);
		SetMass(ship, 10);
		[ship rescaleBy:2 writeToCache:NO];
		OO_CHECK(ScaleFactor(ship) == scale * 2 && [ship mass] == 80);
		OO_CHECK(HPdistance([sub position], make_HPvector(2, 4, 6)) < 1e-9);
		[ship rescaleBy:0.5];
		OO_CHECK(ScaleFactor(ship) == scale && [ship mass] == 10);

		OO_CHECK(!IsWreckage(ship) && ![ship showDamage]);
		[ship setIsWreckage:YES];
		SetShowDamage(ship, true);
		OO_CHECK(IsWreckage(ship) && [ship showDamage]);

		OO_CHECK([ship cxx_cargoCount] == 0);
		[ship releaseCargoPodsDebris];
		OO_CHECK([ship cxx_cargoCount] == 0);
	}
}


// Slice 23: the heat levels, clamped to 0 ... 1; the weapon's recovery; the personality, its shader
// seed and its range; the explosion flag; the scanner; the alignment offsets in the bounding box;
// and beacon codes compared without case.
OO_TEST(heatPersonalityAlignmentAndBeacons)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = FlyingShip("warm");
		SetWeaponTemps(ship, NPC_MAX_WEAPON_TEMP / 2, NPC_MAX_WEAPON_TEMP * 2);
		OO_CHECK([ship laserHeatLevel] == 0.5f && [ship laserHeatLevelAft] == 1.0f);
		[ship setTemperature:SHIP_MAX_CABIN_TEMP / 4];
		OO_CHECK([ship hullHeatLevel] == 0.25f);
		[ship setWeaponRechargeRate:2];
		OO_CHECK([ship weaponRecoveryTime] == 0.0f);	// the shot time starts at INITIAL_SHOT_TIME: long recovered
		SetShotTime(ship, 0.5);
		OO_CHECK([ship weaponRecoveryTime] == 0.75f);

		[ship setEntityPersonalityInt:100];
		OO_CHECK([ship entityPersonalityInt] == 100 && [ship randomSeedForShaders] == 100u * 0x00010001u);
		OO_CHECK([ship entityPersonality] == 100 / (float)ENTITY_PERSONALITY_MAX);
		[ship setEntityPersonalityInt:ENTITY_PERSONALITY_MAX + 1];	// out of range: ignored
		OO_CHECK([ship entityPersonalityInt] == 100);

		OO_CHECK(!SuppressesExplosion(ship));
		[ship setSuppressExplosion:YES];
		OO_CHECK(SuppressesExplosion(ship));

		OO_CHECK([ship numberOfScannedShips] == 0);
		[ship setFoundTarget:nil];
		OO_CHECK([ship foundTarget] == nil && [ship primaryAggressor] == nil && [ship lastEscortTarget] == nil);

		SetBoundingBox(ship, BoundingBox{ { -1, -2, -3 }, { 3, 4, 5 } });
		Vector offset = [ship positionOffsetForAlignment:"MmC"];
		OO_CHECK(offset.x == 3 && offset.y == -2 && offset.z == 1);
		offset = [ship positionOffsetForAlignment:"c"];		// the others are padded with '-': zero
		OO_CHECK(offset.x == 1 && offset.y == 0 && offset.z == 0);

		TestShip *other = FlyingShip("beacon");
		[ship setBeaconCode:std::string("alpha")];
		[other setBeaconCode:std::string("BETA")];
		OO_CHECK([ship compareBeaconCodeWith:other] == OOOrderedAscending && [other compareBeaconCodeWith:ship] == OOOrderedDescending);
	}
}


// --- Slice 24: target memory and validity, behaviour and destination accessors, distances, leading
// the target (bead oo-zd80m). Written against the Objective-C API and run on the unconverted slice
// first.

@interface ShipEntity (TestSlice24)
- (void) setShipHitByLaser:(ShipEntity *)ship;	// the private category of ShipEntity.mm
@end


// The later slices' ship: one that scripts cannot see, so that the events it sends with entities as
// arguments make no JavaScript objects in the test's empty context.
@interface LateSliceTestShip: TestShip
@end


@implementation LateSliceTestShip

- (BOOL) isVisibleToScripts	{ return NO; }

@end


namespace {

TestShip *MakeLateSliceShip(const char *key)
{
	return [[[LateSliceTestShip alloc] cxx_initWithKey:key definition:Definition()] autorelease];
}

GLfloat Frustration24(ShipEntity *s)			{ return s->_cxxShip->frustration; }
void SetFrustration24(ShipEntity *s, GLfloat f)	{ s->_cxxShip->frustration = f; }
void SetScannerRange24(ShipEntity *s, GLfloat r)	{ s->_cxxShip->scannerRange = r; }
void SetWeaponRange24(ShipEntity *s, GLfloat r)	{ s->_cxxShip->weaponRange = r; }
void SetDestination24(ShipEntity *s, HPVector d)	{ s->_cxxShip->_destination = d; }
void SetPosition24(Entity *e, HPVector p)		{ e->_cxxEntity->position = p; }
void SetFlightControls24(ShipEntity *s, GLfloat v)
{
	s->_cxxShip->flightRoll = s->_cxxShip->flightPitch = s->_cxxShip->flightYaw = v;
	s->_cxxShip->stick_roll = s->_cxxShip->stick_pitch = s->_cxxShip->stick_yaw = v;
}
bool FlightControlsZero24(ShipEntity *s)
{
	cxx::ShipEntity *p = s->_cxxShip;
	return p->flightRoll == 0 && p->flightPitch == 0 && p->flightYaw == 0 && p->stick_roll == 0 && p->stick_pitch == 0 && p->stick_yaw == 0;
}
bool Near24(HPVector a, HPVector b)	{ return HPdistance2(a, b) < 1e-6; }
void SetCollisionRadius24(Entity *e, GLfloat r)	{ e->_cxxEntity->collision_radius = r; }

}	// namespace


OO_TEST(slice24RememberedShips)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = MakeLateSliceShip("rememberer");
		TestShip *other = MakeLateSliceShip("other");
		OO_CHECK([ship thankedShip] == nil && [ship rememberedShip] == nil && [ship targetStation] == nil);

		[ship setThankedShip:other];
		[ship setRememberedShip:other];
		[ship setTargetStation:other];
		OO_CHECK([ship thankedShip] == other && [ship rememberedShip] == other && (id)[ship targetStation] == other);

		// A ship that is no longer a valid target is forgotten, and stays forgotten.
		[other setStatus:STATUS_DOCKED];
		OO_CHECK([ship thankedShip] == nil && [ship rememberedShip] == nil && [ship targetStation] == nil);
		[other setStatus:STATUS_IN_FLIGHT];
		OO_CHECK([ship thankedShip] == nil && [ship rememberedShip] == nil && [ship targetStation] == nil);

		[ship setThankedShip:other];
		[ship setThankedShip:nil];
		OO_CHECK([ship thankedShip] == nil);

		OO_CHECK([ship shipHitByLaser] == nil);
		[ship setShipHitByLaser:other];
		OO_CHECK([ship shipHitByLaser] == other);
		[ship setShipHitByLaser:nil];
		OO_CHECK([ship shipHitByLaser] == nil);
	}
}


OO_TEST(slice24IsValidTarget)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = MakeLateSliceShip("judge");
		TestShip *other = MakeLateSliceShip("target");
		Entity *plain = [[[Entity alloc] init] autorelease];
		OO_CHECK(![ship isValidTarget:nil]);
		OO_CHECK([ship isValidTarget:other]);
		OO_CHECK(![ship isValidTarget:plain]);		// neither a ship nor a wormhole
		const OOEntityStatus invalid[] = { STATUS_ENTERING_WITCHSPACE, STATUS_IN_HOLD, STATUS_DOCKED, STATUS_DEAD };
		for (OOEntityStatus s : invalid)
		{
			[other setStatus:s];
			OO_CHECK(![ship isValidTarget:other]);
		}
		[other setStatus:STATUS_ACTIVE];
		OO_CHECK([ship isValidTarget:other]);
	}
}


OO_TEST(slice24PrimaryTarget)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = MakeLateSliceShip("hunter");
		TestShip *other = MakeLateSliceShip("prey");
		OO_CHECK([ship primaryTarget] == nil && [ship primaryTargetWithoutValidityCheck] == nil);
		OO_CHECK(![ship canStillTrackPrimaryTarget]);

		[ship addTarget:ship];		// never itself
		OO_CHECK([ship primaryTarget] == nil);

		[ship addTarget:other];
		OO_CHECK([ship primaryTarget] == other && [ship primaryTargetWithoutValidityCheck] == other);

		// In range (a quarter more than the scanner's), and out of it.
		SetScannerRange24(ship, 1000);
		SetPosition24(other, make_HPvector(0, 0, 1240));
		OO_CHECK([ship canStillTrackPrimaryTarget]);
		SetPosition24(other, make_HPvector(0, 0, 1260));
		OO_CHECK(![ship canStillTrackPrimaryTarget]);
		SetPosition24(other, kZeroHPVector);

		// An invalid target: the unchecked getter keeps it, the checked one drops it.
		[other setStatus:STATUS_DEAD];
		OO_CHECK(![ship canStillTrackPrimaryTarget]);
		OO_CHECK([ship primaryTargetWithoutValidityCheck] == other);
		OO_CHECK([ship primaryTarget] == nil);
		OO_CHECK([ship primaryTargetWithoutValidityCheck] == nil);
		[other setStatus:STATUS_IN_FLIGHT];

		// -removeTarget:nil drops the target without the lost-target events.
		[ship addTarget:other];
		[ship removeTarget:nil];
		OO_CHECK([ship primaryTarget] == nil);

		// -removeTarget: with a target notes it lost.
		[ship addTarget:other];
		[ship removeTarget:other];
		OO_CHECK([ship primaryTarget] == nil);
	}
}


OO_TEST(slice24NoteLostTarget)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = MakeLateSliceShip("forgetful");
		TestShip *other = MakeLateSliceShip("lost");
		[ship addTarget:other];
		[ship noteLostTarget];
		OO_CHECK([ship primaryTarget] == nil);
		[ship noteLostTarget];		// with none, still fine
		OO_CHECK([ship primaryTarget] == nil);

		[ship addTarget:other];
		[ship setBehaviour:BEHAVIOUR_ATTACK_TARGET];
		SetFrustration24(ship, 5);
		[ship noteLostTargetAndGoIdle];
		OO_CHECK([ship primaryTarget] == nil);
		OO_CHECK([ship behaviour] == BEHAVIOUR_IDLE && Frustration24(ship) == 0);
	}
}


OO_TEST(slice24IsFriendlyTo)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = MakeLateSliceShip("friend");
		TestShip *other = MakeLateSliceShip("stranger");
		OO_CHECK([ship isFriendlyTo:ship]);
		OO_CHECK(![ship isFriendlyTo:other]);

		[ship setScanClass:CLASS_POLICE];
		[other setScanClass:CLASS_POLICE];
		OO_CHECK([ship isFriendlyTo:other]);
		[ship setScanClass:CLASS_THARGOID];
		[other setScanClass:CLASS_THARGOID];
		OO_CHECK([ship isFriendlyTo:other]);
		[ship setScanClass:CLASS_MILITARY];
		[other setScanClass:CLASS_MILITARY];
		OO_CHECK([ship isFriendlyTo:other]);
		[ship setScanClass:CLASS_NEUTRAL];
		[other setScanClass:CLASS_NEUTRAL];
		OO_CHECK(![ship isFriendlyTo:other]);

		OOShipGroup *group = [[[OOShipGroup alloc] init] autorelease];
		[ship setGroup:group];
		[other setGroup:group];
		OO_CHECK([ship isFriendlyTo:other] && [other isFriendlyTo:ship]);
		[ship setGroup:nil];
		[other setGroup:nil];
	}
}


OO_TEST(slice24BehaviourAndDestination)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = MakeLateSliceShip("navigator");
		SetFrustration24(ship, 3);
		[ship setBehaviour:[ship behaviour]];		// no change: frustration stays
		OO_CHECK(Frustration24(ship) == 3);
		[ship setBehaviour:BEHAVIOUR_FLEE_TARGET];	// a change is a good thing
		OO_CHECK([ship behaviour] == BEHAVIOUR_FLEE_TARGET && Frustration24(ship) == 0);

		SetDestination24(ship, make_HPvector(1, 2, 3));
		OO_CHECK(Near24([ship destination], make_HPvector(1, 2, 3)));
		[ship setCoordinate:make_HPvector(4, 5, 6)];
		OO_CHECK(Near24([ship coordinates], make_HPvector(4, 5, 6)));
	}
}


OO_TEST(slice24Distances)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = MakeLateSliceShip("formation");
		SetPosition24(ship, make_HPvector(10, 20, 30));
		[ship setOrientation:kIdentityQuaternion];
		Vector f = [ship forwardVector], u = [ship upVector], r = [ship rightVector];
		OO_CHECK(Near24([ship distance_six:5], make_HPvector(10 - 5 * f.x, 20 - 5 * f.y, 30 - 5 * f.z)));
		OO_CHECK(Near24([ship distance_twelve:5 withOffset:2], make_HPvector(10 + 5 * u.x + 2 * r.x, 20 + 5 * u.y + 2 * r.y, 30 + 5 * u.z + 2 * r.z)));
	}
}


OO_TEST(slice24TrackOntoTarget)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = MakeLateSliceShip("tracker");
		TestShip *other = MakeLateSliceShip("tracked");
		[ship setOrientation:kIdentityQuaternion];
		SetFlightControls24(ship, 0.5f);

		// No target: nothing changes.
		[ship trackOntoTarget:0.1 withDForward:0];
		OO_CHECK(!FlightControlsZero24(ship));

		// Already on target (the dot product is inside the target's cone): nothing changes.
		[ship addTarget:other];
		SetPosition24(other, make_HPvector(1000, 0, 0));
		SetCollisionRadius24(other, 100);
		[ship trackOntoTarget:0.1 withDForward:1];
		OO_CHECK(!FlightControlsZero24(ship));
		OO_CHECK(fabs([ship forwardVector].z) > 0.999);

		// Otherwise it turns onto the line to the target (the x axis) and stops turning.
		[ship trackOntoTarget:0.1 withDForward:0];
		Vector f = [ship forwardVector];
		OO_CHECK(fabs(fabs(f.x) - 1) < 1e-4 && fabs(f.y) < 1e-4 && fabs(f.z) < 1e-4);
		OO_CHECK(FlightControlsZero24(ship));
	}
}


OO_TEST(slice24BallTrackLeadingTarget)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = MakeLateSliceShip("turret");
		TestShip *other = MakeLateSliceShip("aimed-at");
		OO_CHECK([ship ballTrackLeadingTarget:0.1 atTarget:nil] == -2.0);
		SetPosition24(other, make_HPvector(0, 0, 1000));
		SetWeaponRange24(ship, 500);
		OO_CHECK([ship ballTrackLeadingTarget:0.1 atTarget:other] == -2.0);	// out of range
	}
}


// --- Slice 25: evasive jink, primary and side target tracking (bead oo-k6wuw). Written against the
// Objective-C API and run on the unconverted slice first.

namespace {

void SetAccuracy25(ShipEntity *s, GLfloat a)	{ s->_cxxShip->accuracy = a; }
Vector Jink25(ShipEntity *s)					{ return s->_cxxShip->jink; }
void SetFrustration25(ShipEntity *s, GLfloat f)	{ s->_cxxShip->frustration = f; }
GLfloat Frustration25(ShipEntity *s)			{ return s->_cxxShip->frustration; }

}	// namespace


OO_TEST(slice25SetEvasiveJink)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = MakeLateSliceShip("jinker");

		// An awful pilot does not jink.
		SetAccuracy25(ship, COMBAT_AI_ISNT_AWFUL - 1);
		[ship setEvasiveJink:400];
		OO_CHECK(vector_equal(Jink25(ship), kZeroVector));

		// Otherwise x and y are well away from zero, and z is what was asked for.
		SetAccuracy25(ship, COMBAT_AI_ISNT_AWFUL + 1);
		for (int i = 0; i < 50; i++)
		{
			[ship setEvasiveJink:400];
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
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = MakeLateSliceShip("aimless");

		[ship setBehaviour:BEHAVIOUR_ATTACK_TARGET];
		SetFrustration25(ship, 2);
		[ship evasiveAction:0.1];
		OO_CHECK([ship behaviour] == BEHAVIOUR_IDLE && Frustration25(ship) == 0);

		[ship setBehaviour:BEHAVIOUR_ATTACK_TARGET];
		OO_CHECK([ship trackPrimaryTarget:0.1 retreat:NO] == 0.0);
		OO_CHECK([ship behaviour] == BEHAVIOUR_IDLE);

		[ship setBehaviour:BEHAVIOUR_ATTACK_TARGET];
		OO_CHECK([ship trackSideTarget:0.1 leftside:YES] == 0.0);
		OO_CHECK([ship behaviour] == BEHAVIOUR_IDLE);
	}
}


// A target the ship can no longer track (out of scanner range) is lost the same way.
OO_TEST(slice25TargetOutOfRangeGoesIdle)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = MakeLateSliceShip("short-sighted");
		TestShip *other = MakeLateSliceShip("far-away");
		SetScannerRange24(ship, 100);
		SetPosition24(other, make_HPvector(0, 0, 1000));

		[ship addTarget:other];
		[ship setBehaviour:BEHAVIOUR_ATTACK_TARGET];
		OO_CHECK([ship trackPrimaryTarget:0.1 retreat:NO] == 0.0);
		OO_CHECK([ship behaviour] == BEHAVIOUR_IDLE && [ship primaryTarget] == nil);

		[ship addTarget:other];
		[ship setBehaviour:BEHAVIOUR_ATTACK_TARGET];
		OO_CHECK([ship trackSideTarget:0.1 leftside:NO] == 0.0);
		OO_CHECK([ship behaviour] == BEHAVIOUR_IDLE && [ship primaryTarget] == nil);
	}
}


// --- Slice 26: missile and destination tracking, collision exceptions, defence targets, ranges
// (bead oo-v92af). Written against the Objective-C API and run on the unconverted slice first.

namespace {

void SetUpVectors26(ShipEntity *s, Vector up, Vector right)	{ s->_cxxShip->v_up = up; s->_cxxShip->v_right = right; }
void SetMaxFlightRoll26(ShipEntity *s, GLfloat r)			{ s->_cxxShip->max_flight_roll = r; }
void SetCollisionRadius26(Entity *e, GLfloat r)				{ e->_cxxEntity->collision_radius = r; }

}	// namespace


OO_TEST(slice26RollToMatchUp)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = MakeLateSliceShip("roller");
		SetMaxFlightRoll26(ship, 2);
		SetUpVectors26(ship, kBasisYVector, kBasisXVector);

		// Already up: the match roll, its sign flipped for a ship that is not the player.
		OO_CHECK(fabs([ship rollToMatchUp:kBasisYVector rotating:0.5f] - (-0.5f)) < 1e-6);
		// Upside down: the same.
		OO_CHECK(fabs([ship rollToMatchUp:vector_flip(kBasisYVector) rotating:0.5f] - (-0.5f)) < 1e-6);
		// Up is to the right (sin 1 flipped to -1): the roll decreases by the full max.
		OO_CHECK(fabs([ship rollToMatchUp:kBasisXVector rotating:0.5f] - (-2.0f)) < 1e-6);
		// Up is to the left: it increases by it.
		OO_CHECK(fabs([ship rollToMatchUp:vector_flip(kBasisXVector) rotating:0.5f] - 2.0f) < 1e-6);
	}
}


OO_TEST(slice26Ranges)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = MakeLateSliceShip("ranger");
		TestShip *other = MakeLateSliceShip("ranged");
		SetPosition24(ship, make_HPvector(0, 0, 0));
		SetDestination24(ship, make_HPvector(0, 3, 4));
		OO_CHECK(fabs([ship rangeToDestination] - 5.0f) < 1e-5);

		OO_CHECK([ship rangeToSecondaryTarget:nil] == 0.0);
		OO_CHECK([ship rangeToPrimaryTarget] == 0.0);		// no target
		OO_CHECK([ship approachAspectToPrimaryTarget] == 0.0);

		SetPosition24(other, make_HPvector(0, 0, 100));
		SetCollisionRadius26(ship, 10);
		SetCollisionRadius26(other, 15);
		OO_CHECK(fabs([ship rangeToSecondaryTarget:other] - 75.0) < 1e-6);
		[ship addTarget:other];
		OO_CHECK(fabs([ship rangeToPrimaryTarget] - 75.0) < 1e-6);

		// Approach aspect: the target's forward vector against the direction from it to us.
		[other setOrientation:kIdentityQuaternion];
		Vector f = [other forwardVector];
		Vector delta = vector_normal(HPVectorToVector(HPvector_subtract(make_HPvector(0, 0, 0), make_HPvector(0, 0, 100))));
		OO_CHECK(fabs([ship approachAspectToPrimaryTarget] - dot_product(delta, f)) < 1e-6);

		OO_CHECK(![ship hasProximityAlertIgnoringTarget:NO]);	// no proximity alert
		OO_CHECK(![ship hasProximityAlertIgnoringTarget:YES]);
	}
}


OO_TEST(slice26CollisionExceptions)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = MakeLateSliceShip("excepting");
		TestShip *a = MakeLateSliceShip("a");
		TestShip *b = MakeLateSliceShip("b");
		OO_CHECK(![ship collisionExceptedFor:a] && [ship cxx_collisionExceptions].empty());
		[ship removeCollisionException:a];		// none yet: fine

		[ship addCollisionException:a];
		[ship addCollisionException:b];
		OO_CHECK([ship collisionExceptedFor:a] && [ship collisionExceptedFor:b]);
		OO_CHECK([ship cxx_collisionExceptions].size() == 2);

		[ship removeCollisionException:a];
		OO_CHECK(![ship collisionExceptedFor:a] && [ship collisionExceptedFor:b]);
		auto left = [ship cxx_collisionExceptions];
		OO_CHECK(left.size() == 1 && left[0].get() == b);
	}
}


OO_TEST(slice26DefenseTargets)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = MakeLateSliceShip("defender");
		TestShip *a = MakeLateSliceShip("attacker-a");
		TestShip *b = MakeLateSliceShip("attacker-b");
		Entity *plain = [[[Entity alloc] init] autorelease];
		OO_CHECK([ship defenseTargetCount] == 0 && [ship allDefenseTargets].empty() && [ship cxx_defenseTargets].empty());
		[ship validateDefenseTargets];		// none yet: fine

		OO_CHECK(![ship addDefenseTarget:nil]);
		OO_CHECK(![ship addDefenseTarget:plain]);		// not a ship
		OO_CHECK([ship addDefenseTarget:a]);
		OO_CHECK(![ship addDefenseTarget:a]);		// already one
		OO_CHECK([ship addDefenseTarget:b]);
		OO_CHECK([ship defenseTargetCount] == 2 && [ship isDefenseTarget:a] && [ship isDefenseTarget:b]);
		OO_CHECK([ship allDefenseTargets].size() == 2 && [ship cxx_defenseTargets].size() == 2);

		// A dead one is dropped by the validation.
		[a setStatus:STATUS_DEAD];
		[ship validateDefenseTargets];
		OO_CHECK(![ship isDefenseTarget:a] && [ship isDefenseTarget:b] && [ship defenseTargetCount] == 1);

		[ship removeDefenseTarget:b];
		OO_CHECK([ship defenseTargetCount] == 0);

		// At most MAX_TARGETS.
		std::vector<TestShip *> many;
		for (unsigned i = 0; i < MAX_TARGETS; i++)
		{
			many.push_back(MakeLateSliceShip("many"));
			OO_CHECK([ship addDefenseTarget:many.back()]);
		}
		OO_CHECK(![ship addDefenseTarget:b]);
		[ship removeAllDefenseTargets];
		OO_CHECK([ship defenseTargetCount] == 0);
	}
}


// --- Slice 27: aim tolerance, sun glare, main weapons and turret fire, laser colours (bead
// oo-pnfyp). Written against the Objective-C API and run on the unconverted slice first.

namespace {

void SetAim27(ShipEntity *s, GLfloat tolerance, GLfloat accuracy, OOWeaponFacing facing)
{
	s->_cxxShip->aim_tolerance = tolerance;
	s->_cxxShip->accuracy = accuracy;
	s->_cxxShip->currentWeaponFacing = facing;
	s->_cxxShip->_missed_shots = 0;
	s->_cxxEntity->isSunlit = false;
}
GLfloat ExpectedAim27(GLfloat basic_aim, GLfloat best_cos)
{
	GLfloat max_cos = sqrt(1 - (basic_aim * basic_aim / 100000000.0));
	return max_cos < best_cos ? max_cos : best_cos;
}
void SetShotTime27(ShipEntity *s, OOTimeDelta t)	{ s->_cxxShip->shot_time = t; }
void SetRechargeRate27(ShipEntity *s, float r)	{ s->_cxxShip->weapon_recharge_rate = r; }

}	// namespace


OO_TEST(slice27CurrentAimTolerance)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = MakeLateSliceShip("gunner");

		// An awful shot, forward: the tolerance as it is.
		SetAim27(ship, 1000, COMBAT_AI_ISNT_AWFUL - 1, WEAPON_FACING_FORWARD);
		OO_CHECK(fabs([ship currentAimTolerance] - ExpectedAim27(1000, 0.99999)) < 1e-7);
		// Aft: a third worse.
		SetAim27(ship, 1000, COMBAT_AI_ISNT_AWFUL - 1, WEAPON_FACING_AFT);
		OO_CHECK(fabs([ship currentAimTolerance] - ExpectedAim27(1000 * 1.3, 0.99999)) < 1e-7);
		// Better pilots: tighter, and tighter still after missing.
		SetAim27(ship, 1000, COMBAT_AI_ISNT_AWFUL, WEAPON_FACING_FORWARD);
		OO_CHECK(fabs([ship currentAimTolerance] - ExpectedAim27(1000, 0.999999)) < 1e-7);
		[ship adjustMissedShots:4];
		OO_CHECK([ship missedShots] == 4);
		OO_CHECK(fabs([ship currentAimTolerance] - ExpectedAim27(1000 / 2.0, 0.999999)) < 1e-7);
		// A side laser makes even a good pilot worse.
		SetAim27(ship, 1000, COMBAT_AI_ISNT_AWFUL, WEAPON_FACING_PORT);
		OO_CHECK(fabs([ship currentAimTolerance] - ExpectedAim27(1000 * 1.3, 0.999999)) < 1e-7);
		// Deadly shots.
		SetAim27(ship, 1000, COMBAT_AI_TRACKS_CLOSER, WEAPON_FACING_FORWARD);
		OO_CHECK(fabs([ship currentAimTolerance] - ExpectedAim27(1000 / 5.0, 0.9999999)) < 1e-7);
	}
}


OO_TEST(slice27ShotTimeAndTurret)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = MakeLateSliceShip("turret-gun");
		SetShotTime27(ship, 3);
		OO_CHECK([ship shotTime] == 3);
		[ship resetShotTime];
		OO_CHECK([ship shotTime] == 0);

		// Not recharged: no shot.
		SetRechargeRate27(ship, 1);
		SetWeaponRange24(ship, 1000);
		OO_CHECK(![ship fireTurretCannon:10]);
		// Recharged, but out of range (more than 1% past it): no shot either.
		SetShotTime27(ship, 2);
		OO_CHECK(![ship fireTurretCannon:1011]);
		OO_CHECK([ship shotTime] == 2);
	}
}


OO_TEST(slice27Colours)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = MakeLateSliceShip("painted");
		OOColor *red = [OOColor redColor];
		OOColor *blue = [OOColor blueColor];
		[ship setLaserColor:red];
		[ship setExhaustEmissiveColor:blue];
		OO_CHECK([ship laserColor] == red && [ship exhaustEmissiveColor] == blue);
		// nil is ignored.
		[ship setLaserColor:nil];
		[ship setExhaustEmissiveColor:nil];
		OO_CHECK([ship laserColor] == red && [ship exhaustEmissiveColor] == blue);
	}
}


// --- Slice 28: laser shots, missed shots, sparks, missile launch decision (bead oo-40ocf). Written
// against the Objective-C API and run on the unconverted slice first.

namespace {

void SetBoundingBox28(Entity *e, BoundingBox bb)	{ e->_cxxEntity->boundingBox = bb; }
void SetScaleFactor28(ShipEntity *s, GLfloat f)	{ s->_cxxShip->_scaleFactor = f; }
void SetMissiles28(ShipEntity *s, unsigned n)		{ s->_cxxShip->missiles = n; }

}	// namespace


OO_TEST(slice28MissedShots)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = MakeLateSliceShip("misser");
		TestShip *sub = MakeLateSliceShip("sub-misser");
		OO_CHECK([ship missedShots] == 0);
		[ship adjustMissedShots:3];
		[ship adjustMissedShots:2];
		OO_CHECK([ship missedShots] == 5);
		[ship adjustMissedShots:-10];		// never below zero
		OO_CHECK([ship missedShots] == 0);

		// A subentity's count is its owner's.
		[ship addSubEntity:sub];
		[sub adjustMissedShots:2];
		OO_CHECK([ship missedShots] == 2 && [sub missedShots] == 2);
		[ship clearSubEntities];
	}
}


OO_TEST(slice28MissileLaunchPosition)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = MakeLateSliceShip("launcher");
		BoundingBox bb = { { -10, -20, -30 }, { 10, 20, 30 } };
		SetBoundingBox28(ship, bb);
		SetScaleFactor28(ship, 1);
		// No missile_launch_position: 4 m below and 1 m ahead of the bounding box.
		Vector start = [ship missileLaunchPosition];
		OO_CHECK(start.x == 0 && start.y == -24 && start.z == 31);
		// Scaled.
		SetScaleFactor28(ship, 2);
		start = [ship missileLaunchPosition];
		OO_CHECK(start.x == 0 && start.y == -48 && start.z == 62);
	}
}


OO_TEST(slice28ConsiderFiringMissileWithoutMissiles)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = MakeLateSliceShip("unarmed");
		SetMissiles28(ship, 0);
		[ship considerFiringMissile:0.1];		// nothing to fire: nothing happens
		OO_CHECK([ship missileCount] == 0);
	}
}


// --- Slice 29: missile firing, ECM, cloak, cascade mine, escape capsule, cargo dumping (bead
// oo-g900k). Written against the Objective-C API and run on the unconverted slice first.

namespace {

bool CloakActive29(ShipEntity *s)	{ return s->_cxxShip->cloaking_device_active; }

}	// namespace


OO_TEST(slice29MissileFlagAndLoadTime)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = MakeLateSliceShip("missile-ish");
		OO_CHECK(![ship isMissileFlagSet]);
		[ship setIsMissileFlag:YES];
		OO_CHECK([ship isMissileFlagSet]);
		[ship setIsMissileFlag:NO];
		OO_CHECK(![ship isMissileFlagSet]);

		[ship setMissileLoadTime:2.5];
		OO_CHECK([ship missileLoadTime] == 2.5);
		[ship setMissileLoadTime:-1];		// never negative
		OO_CHECK([ship missileLoadTime] == 0);
	}
}


// Without the equipment, ECM and the cloak do nothing.
OO_TEST(slice29NoEquipment)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = MakeLateSliceShip("plain-hull");
		OO_CHECK(![ship fireECM]);
		OO_CHECK(![ship activateCloakingDevice] && !CloakActive29(ship));
		[ship deactivateCloakingDevice];
		OO_CHECK(!CloakActive29(ship));
		[ship noticeECM];		// no missiles: nothing to delay
	}
}


// With an empty hold, there is nothing to dump.
OO_TEST(slice29DumpEmptyHold)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = MakeLateSliceShip("empty-hold");
		OO_CHECK([ship cxx_dumpCargoItem:std::nullopt] == nil);
		OO_CHECK([ship cxx_dumpCargoItem:std::optional<std::string>("food")] == nil);
		[ship dumpCargo];
	}
}


// --- Slice 30: collisions, velocity, tractoring and scooping (bead oo-ogoct). Written against the
// Objective-C API and run on the unconverted slice first.

@interface ShipEntity (TestSlice30)
- (void) suppressTargetLost;	// undeclared: sent by name
@end


namespace {

void SetFlightSpeed30(ShipEntity *s, GLfloat v)	{ s->_cxxShip->flightSpeed = v; }
Vector RawVelocity30(Entity *e)					{ return e->_cxxEntity->velocity; }
void SetMass30(Entity *e, GLfloat m)			{ e->_cxxEntity->mass = m; }
bool Near30(Vector a, Vector b)					{ return distance2(a, b) < 1e-8; }

}	// namespace


OO_TEST(slice30Velocity)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = MakeLateSliceShip("mover");
		[ship setOrientation:kIdentityQuaternion];
		Vector f = [ship forwardVector];
		SetFlightSpeed30(ship, 10);
		OO_CHECK(Near30([ship thrustVector], vector_multiply_scalar(f, 10)));

		// The velocity is the entity's plus the thrust.
		[ship setVelocity:make_vector(1, 2, 3)];
		OO_CHECK(Near30([ship velocity], vector_add(make_vector(1, 2, 3), vector_multiply_scalar(f, 10))));
		// From C++, the root's virtual reaches the ship's.
		OO_CHECK(Near30(oo::ToCxx(static_cast<Entity *>(ship))->getVelocity(), [ship velocity]));

		// Setting the total velocity sets the entity's to what is left after the thrust.
		[ship setTotalVelocity:make_vector(0, 0, 0)];
		OO_CHECK(Near30(RawVelocity30(ship), vector_flip(vector_multiply_scalar(f, 10))));
		OO_CHECK(Near30([ship velocity], kZeroVector));

		[ship setVelocity:kZeroVector];
		[ship adjustVelocity:make_vector(1, 0, 0)];
		[ship adjustVelocity:make_vector(0, 2, 0)];
		OO_CHECK(Near30(RawVelocity30(ship), make_vector(1, 2, 0)));

		[ship setVelocity:kZeroVector];
		SetMass30(ship, 4);
		[ship addImpactMoment:make_vector(8, 0, 0) fraction:0.5f];
		OO_CHECK(Near30(RawVelocity30(ship), make_vector(1, 0, 0)));
	}
}


OO_TEST(slice30ScoopingAndCollisions)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = MakeLateSliceShip("scooper");
		TestShip *other = MakeLateSliceShip("cargo");
		OO_CHECK(![ship canScoop:nil]);
		OO_CHECK(![ship canScoop:other]);		// no cargo scoop
		[ship suppressTargetLost];		// does nothing
		[ship manageCollisions];		// nothing colliding: nothing happens
		OO_CHECK([ship status] == STATUS_IN_FLIGHT);
	}
}


// --- Slice 31: cascades, energy / scrape / heat damage, abandoning ship, docks, wormholes,
// witchspace (bead oo-gx86h). Written against the Objective-C API and run on the unconverted slice
// first.

namespace {

void SetEnergy31(Entity *e, GLfloat energy, GLfloat maxEnergy)	{ e->_cxxEntity->energy = energy; e->_cxxEntity->maxEnergy = maxEnergy; }
GLfloat Energy31(Entity *e)									{ return e->_cxxEntity->energy; }
bool ThrowSparks31(Entity *e)									{ return e->_cxxEntity->throw_sparks; }

}	// namespace


OO_TEST(slice31DamageThatDoesNothing)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = MakeLateSliceShip("tough");
		TestShip *other = MakeLateSliceShip("rammer");
		SetEnergy31(ship, 100, 100);

		// Nothing, or a negative amount: no damage.
		[ship takeEnergyDamage:0 from:other becauseOf:other weaponIdentifier:""];
		[ship takeEnergyDamage:-5 from:other becauseOf:other weaponIdentifier:""];
		OO_CHECK(Energy31(ship) == 100);
		// From C++, the root's virtual reaches the ship's.
		oo::ToCxx(static_cast<Entity *>(ship))->takeEnergyDamage(0, oo::ToCxx(static_cast<Entity *>(other)), nullptr, "");
		OO_CHECK(Energy31(ship) == 100);

		// No scrapes while launching.
		[other setStatus:STATUS_LAUNCHING];
		[ship takeScrapeDamage:10 from:other];
		OO_CHECK(Energy31(ship) == 100);

		// The dead take nothing.
		[ship setStatus:STATUS_DEAD];
		[ship takeEnergyDamage:10 from:other becauseOf:other weaponIdentifier:""];
		[ship takeScrapeDamage:10 from:other];
		[ship takeHeatDamage:10];
		OO_CHECK(Energy31(ship) == 100);
	}
}


// A subentity of a ship that is not frangible takes no heat damage. (Damage that is taken sends the
// shipTakingDamage event with JavaScript values, which the test's empty context cannot make.)
OO_TEST(slice31HeatDamageToAFixedSubentity)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = MakeLateSliceShip("fixed-mount");
		TestShip *sub = MakeLateSliceShip("fixed-turret");
		[ship addSubEntity:sub];
		SetEnergy31(sub, 100, 100);
		OO_CHECK(![ship isFrangible]);
		[sub takeHeatDamage:10];
		OO_CHECK(Energy31(sub) == 100 && !ThrowSparks31(sub));
		[ship clearSubEntities];
	}
}


OO_TEST(slice31NoCascadeWithEnergyToSpare)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = MakeLateSliceShip("stable");
		SetEnergy31(ship, 100, 100);
		OO_CHECK(![ship cascadeIfAppropriateWithDamageAmount:50 cascadeOwner:nil]);	// survives the hit
		SetEnergy31(ship, 5, 100);
		OO_CHECK(![ship cascadeIfAppropriateWithDamageAmount:50 cascadeOwner:nil]);	// too little energy to go pop
		[ship leaveDock:nil];		// no station: nothing
	}
}


// --- Slice 32: witchspace effects, offences, lights, escort formation and deployment, nearest
// stations (bead oo-5e0ny). Written against the Objective-C API and run on the unconverted slice
// first.

@interface ShipEntity (TestSlice32)
- (HPVector) coordinatesForEscortPosition:(unsigned)idx;	// the private category of ShipEntity.mm
@end


namespace {

bool EscortPositionsValid32(ShipEntity *s)	{ return s->_cxxShip->_escortPositionsValid; }
void SetEscortPositionsValid32(ShipEntity *s, bool v)	{ s->_cxxShip->_escortPositionsValid = v; }

}	// namespace


OO_TEST(slice32Lights)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = MakeLateSliceShip("lit");
		TestShip *sub = MakeLateSliceShip("lit-turret");
		[ship addSubEntity:sub];
		[ship switchLightsOn];
		OO_CHECK([ship lightsActive] && [sub lightsActive]);
		[ship switchLightsOff];
		OO_CHECK(![ship lightsActive] && ![sub lightsActive]);
		[ship clearSubEntities];
	}
}


OO_TEST(slice32Destinations)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = MakeLateSliceShip("goer");
		SetFrustration24(ship, 4);
		[ship setEscortDestination:make_HPvector(1, 1, 1)];		// an escort's: frustration stays
		OO_CHECK(Near24([ship destination], make_HPvector(1, 1, 1)) && Frustration24(ship) == 4);
		[ship setDestination:make_HPvector(2, 2, 2)];			// a new destination: none
		OO_CHECK(Near24([ship destination], make_HPvector(2, 2, 2)) && Frustration24(ship) == 0);
	}
}


OO_TEST(slice32EscortFormation)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = MakeLateSliceShip("mother");
		TestShip *other = MakeLateSliceShip("would-be-escort");
		SetEscortPositionsValid32(ship, true);
		[ship updateEscortFormation];
		OO_CHECK(!EscortPositionsValid32(ship));

		// With no positions set, every escort position is the ship's own, however big the index.
		SetPosition24(ship, make_HPvector(5, 6, 7));
		[ship setOrientation:kIdentityQuaternion];
		OO_CHECK(Near24([ship coordinatesForEscortPosition:0], make_HPvector(5, 6, 7)));
		OO_CHECK(Near24([ship coordinatesForEscortPosition:1000], make_HPvector(5, 6, 7)));

		// Escorts must share the scan class.
		[other setScanClass:CLASS_POLICE];
		OO_CHECK(![ship canAcceptEscort:other]);
	}
}


OO_TEST(slice32PoliceAreNotOffenders)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = MakeLateSliceShip("copper");
		[ship setScanClass:CLASS_POLICE];
		[ship markAsOffender:64];
		[ship markAsOffender:64 withReason:kOOLegalStatusReasonByScript];
		OO_CHECK([ship bounty] == 0);
	}
}


// --- Slice 33: landing, docking abort, broadcasts and comms, fines, AI messages, spawning, close
// contacts, salvage (bead oo-tz2ra). Written against the Objective-C API and run on the unconverted
// slice first.

@interface ShipEntity (TestSlice33)
- (BoundingBox) findBoundingBoxRelativeTo:(Entity *)other i:(Vector) _i j:(Vector) _j k:(Vector) _k;	// undeclared: sent by name
@end


namespace {

void SetBounty33(ShipEntity *s, OOCreditsQuantity b)	{ s->_cxxShip->bounty = b; }

}	// namespace


OO_TEST(slice33Fines)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = MakeLateSliceShip("clean");
		TestShip *crook = MakeLateSliceShip("crook");
		OO_CHECK(![ship markedForFines]);
		OO_CHECK(![ship markForFines] && ![ship markedForFines]);	// clean: nothing to fine

		SetBounty33(crook, 50);
		OO_CHECK([crook markForFines] && [crook markedForFines]);
		OO_CHECK(![crook markForFines] && [crook markedForFines]);	// never twice
	}
}


OO_TEST(slice33SmallAccessors)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = MakeLateSliceShip("contact");
		OO_CHECK([ship cxx_dockingInstructions].isNull());

		OO_CHECK(![ship trackCloseContacts]);
		[ship setTrackCloseContacts:YES];
		OO_CHECK([ship trackCloseContacts]);
		[ship setTrackCloseContacts:NO];
		OO_CHECK(![ship trackCloseContacts]);

		// Mining needs the behaviour and a mining laser.
		[ship setBehaviour:BEHAVIOUR_ATTACK_MINING_TARGET];
		OO_CHECK(![ship isMining]);
		[ship setBehaviour:BEHAVIOUR_IDLE];
		OO_CHECK(![ship isMining]);

		[ship spawn:"just-one-token"];		// bad syntax: logged, nothing spawned
		[ship spawn:"a b c"];
	}
}


OO_TEST(slice33FindBoundingBoxRelativeTo)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = MakeLateSliceShip("boxed");
		TestShip *other = MakeLateSliceShip("reference");
		SetPosition24(other, make_HPvector(100, 0, 0));
		// Relative to another entity is relative to its position; to nil, to our own.
		BoundingBox a = [ship findBoundingBoxRelativeTo:other i:kBasisXVector j:kBasisYVector k:kBasisZVector];
		BoundingBox b = [ship findBoundingBoxRelativeToPosition:make_HPvector(100, 0, 0) i:kBasisXVector j:kBasisYVector k:kBasisZVector];
		OO_CHECK(vector_equal(a.min, b.min) && vector_equal(a.max, b.max));
		BoundingBox c = [ship findBoundingBoxRelativeTo:nil i:kBasisXVector j:kBasisYVector k:kBasisZVector];
		BoundingBox d = [ship findBoundingBoxRelativeToPosition:[ship position] i:kBasisXVector j:kBasisYVector k:kBasisZVector];
		OO_CHECK(vector_equal(c.min, d.min) && vector_equal(c.max, d.max));
	}
}


// --- Slice 34: salvage pilot, debug dump, script info, demo ship, script events and AI reactions,
// alert condition, shader helpers (bead oo-nkyn3). Written against the Objective-C API and run on
// the unconverted slice first.

#import "OOJSPropID.h"


@interface ShipEntity (TestSlice34)
- (OOTimeAbsolute) getDemoStartTime;	// undeclared: sent by name
- (void) doNothing;					// undeclared: sent by name
@end


namespace {

Quaternion DemoStartOrientation34(ShipEntity *s)	{ return s->_cxxShip->demoStartOrientation; }
OOScalar DemoRate34(ShipEntity *s)					{ return s->_cxxShip->demoRate; }

}	// namespace


OO_TEST(slice34ScriptInfo)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = MakeLateSliceShip("scripted");
		OO_CHECK([ship script] == nil);
		// None: an empty dictionary, not null.
		oo::PList info = [ship scriptInfo];
		OO_CHECK(info.getIf<oo::PList::Dict>() != nullptr && info.getIf<oo::PList::Dict>()->empty());

		[ship overrideScriptInfo:oo::PList(oo::PList::Dict{ { "a", oo::PList(1.0) }, { "b", oo::PList(2.0) } })];
		OO_CHECK([ship scriptInfo].get<double>("a", 0) == 1.0 && [ship scriptInfo].get<double>("b", 0) == 2.0);
		// An override replaces the entries it has and keeps the others.
		[ship overrideScriptInfo:oo::PList(oo::PList::Dict{ { "b", oo::PList(3.0) }, { "c", oo::PList(4.0) } })];
		info = [ship scriptInfo];
		OO_CHECK(info.get<double>("a", 0) == 1.0 && info.get<double>("b", 0) == 3.0 && info.get<double>("c", 0) == 4.0);
		// A null override changes nothing.
		[ship overrideScriptInfo:oo::PList()];
		OO_CHECK([ship scriptInfo].get<double>("b", 0) == 3.0);
	}
}


OO_TEST(slice34DemoShip)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = MakeLateSliceShip("demo");
		OO_CHECK(![ship isDemoShip]);
		Quaternion q = { 0.5f, 0.5f, 0.5f, 0.5f };
		[ship setOrientation:q];
		[ship setDemoShip:0.25];
		OO_CHECK([ship isDemoShip] && DemoRate34(ship) == 0.25);
		OO_CHECK(quaternion_equal(DemoStartOrientation34(ship), [ship orientation]));
		[ship setDemoStartTime:12.5];
		OO_CHECK([ship getDemoStartTime] == 12.5);
	}
}


OO_TEST(slice34AlertConditionAndEvents)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = MakeLateSliceShip("alert");
		SetEnergy31(ship, 100, 100);
		OO_CHECK([ship alertCondition] == ALERT_CONDITION_YELLOW);		// NPCs are never green
		SetEnergy31(ship, 20, 100);
		OO_CHECK([ship alertCondition] == ALERT_CONDITION_RED);		// low on energy
		[ship setStatus:STATUS_DOCKED];
		OO_CHECK([ship alertCondition] == ALERT_CONDITION_DOCKED);
		[ship setStatus:STATUS_IN_FLIGHT];

		// The ship is its own shader entity when it is not a subentity.
		OO_CHECK([ship entityForShaderProperties] == ship);

		// No scripts, no AI: the events and messages go nowhere, harmlessly.
		[ship doScriptEvent:OOJSID("shipSpawned")];
		[ship doScriptEvent:OOJSID("shipSpawned") withArgument:ship];
		[ship doScriptEvent:OOJSID("shipSpawned") withArgument:ship andArgument:nil];
		[ship cxx_doScriptEvent:OOJSID("shipSpawned") withPListArguments:{ oo::PList(1.0) }];
		[ship cxx_doScriptEvent:OOJSID("shipSpawned") andReactToAIMessage:"NOTHING"];
		[ship cxx_doScriptEvent:OOJSID("shipSpawned") withArgument:ship andReactToAIMessage:"NOTHING"];
		[ship sendAIMessage:"NOTHING"];
		[ship cxx_reactToAIMessage:"NOTHING" context:std::nullopt];
		[ship doNothing];
		OO_CHECK([ship status] == STATUS_IN_FLIGHT);
	}
}


OO_TEST(slice34WeaponHelpers)
{
	@autoreleasepool
	{
		OO_CHECK(isWeaponNone(nil));
	}
}


// --- ShipEntityScriptMethods.mm (bead oo-42dr): the category ShipEntity (ScriptMethods) --------------
// The cases that do not reach the universe (it was never initialised here): ejecting nothing and
// spawning none. Ejecting or spawning a real ship needs the game's ship data, which the goldens run.

OO_TEST(scriptMethodsEjectAndSpawnNothing)
{
	@autoreleasepool
	{
		SetUp();
		TestShip *ship = MakeLateSliceShip("ejector");
		// std::nullopt ejects nothing, as nil did.
		OO_CHECK([ship ejectShipOfType:std::nullopt] == nil);
		OO_CHECK([ship ejectShipOfRole:std::nullopt] == nil);
		// A count of zero spawns nothing and answers an empty list.
		OO_CHECK([ship spawnShipsWithRole:"trader" count:0].empty());
		OO_CHECK([ship status] == STATUS_IN_FLIGHT);
	}
}


// --- ShipEntityLoadRestore.mm (bead oo-kw44): the category ShipEntity (LoadRestore) -------------------
// The cases that reach neither the ship registry nor the universe: restoring from no dictionary.
// Saving a ship, and restoring one, look its key up in the ship registry, whose data the unit test
// does not load (it would scan for add-ons); the goldens' wormholes run those.

OO_TEST(loadRestoreFromNothing)
{
	@autoreleasepool
	{
		SetUp();
		// Null restores no ship, with or without fallback and a context, as nil did.
		OO_CHECK([ShipEntity shipRestoredFromDictionary:oo::PList() useFallback:NO context:nullptr] == nil);
		OO_CHECK([ShipEntity shipRestoredFromDictionary:oo::PList() useFallback:YES context:nullptr] == nil);
		OOShipSaveContext context;
		OO_CHECK([ShipEntity shipRestoredFromDictionary:oo::PList() useFallback:YES context:&context] == nil);
		OO_CHECK(context.nextGroupID == 0 && context.groups.empty() && context.groupsByID.empty());
	}
}


OO_TEST_MAIN()
