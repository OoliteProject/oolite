/*	test_StationEntity.mm
	Unit tests for StationEntity (src/Core/Entities/StationEntity.h), the station: slice 1 of its
	slice plan (docs/phases/3-slices/StationEntity.md, bead oo-64ako), the class shell, which moves
	the station's state and its accessors, market, shipyard, flags and set-up into
	cxx::StationEntity and keeps the Objective-C StationEntity as its facade (proposed ADR-0056,
	amendments oo-60fwo and oo-64ako).

	As test_ShipEntity's, the station's object needs the game graph, so the test links the whole
	game but main (['*']) and uses a Universe that was never initialised and a plain entity as
	PLAYER. The station keeps StationEntity's and ShipEntity's own set-up from the definition; only
	the virtual dock it makes when it has no docks is a stand-in (TestStation records the dock's
	definition instead of asking the universe for the shipdata entry). The cases test the slice's
	own units through the Objective-C API, written against it and run on the unconverted class
	first; the cases after "The crossing" pin the C++ part once it exists.
	Run: bash tools/check-core-tests.sh test_StationEntity
*/

#import "StationEntity.h"
#import "DockEntity.h"
#import "Universe.h"
#import "PlayerEntity.h"
#import "OOWeakSet.h"
#import "OOObjCPList.h"

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


@interface TestStationPlayer: Entity
@end


@implementation TestStationPlayer

- (HPVector) viewpointPosition	{ return kZeroHPVector; }

@end


namespace {

// What the next station's virtual dock does, and the definition it was given.
bool sFailVirtualDock = false;
int sVirtualDocks = 0;
oo::PList sVirtualDockDict;

}	// namespace


// A station whose virtual dock only records its definition (the dock itself is a shipdata entry).
@interface TestStation: StationEntity
@end


@implementation TestStation

- (BOOL) cxx_setUpOneStandardSubentity:(const oo::PList &)subentDict asTurret:(BOOL)asTurret
{
	if (asTurret)  return NO;
	sVirtualDocks++;
	sVirtualDockDict = subentDict;
	return !sFailVirtualDock;
}

@end


namespace {

void SetExplicitlyUnpiloted(ShipEntity *s, bool value)	{ s->_cxxShip->_explicitlyUnpiloted = value; }


void SetUp()
{
	static Universe *universe = nil;
	if (universe == nil)
	{
		universe = (Universe *)class_createInstance([Universe class], 0);	// never released
		universe->_cxxUniverse = oo::makeRef<cxx::Universe>(universe);	// what -initWithGameView: makes first (ADR-0056 amendment oo-riqmz)
	}
	gSharedUniverse = universe;
	static TestStationPlayer *player = nil;
	if (player == nil)  player = [[TestStationPlayer alloc] init];
	gOOPlayer = (PlayerEntity *)player;
	// The ship's -dealloc sends its (absent) scripts entityDestroyed in a request on the main
	// thread's context, so there is one, with nothing in it.
	if (gOOJSMainThreadContext == nullptr)  gOOJSMainThreadContext = JS_NewContext(JS_NewRuntime());
	sFailVirtualDock = false;
	sVirtualDocks = 0;
	sVirtualDockDict = oo::PList();
}


// An unpiloted station (a crewed one would ask the universe for a police pilot).
oo::PList Definition(oo::PList::Dict extra = {})
{
	oo::PList::Dict dict{ { "unpiloted", oo::PList(true) } };
	for (auto &entry : extra)  dict[entry.first] = entry.second;
	return oo::PList(std::move(dict));
}


TestStation *MakeStation(const std::string &key, oo::PList::Dict extra = {})
{
	return [[[TestStation alloc] cxx_initWithKey:key definition:Definition(std::move(extra))] autorelease];
}


bool Near(HPVector a, HPVector b)	{ return std::fabs(a.x - b.x) < 1e-3 && std::fabs(a.y - b.y) < 1e-3 && std::fabs(a.z - b.z) < 1e-3; }

}	// namespace


// --- Slice 1: the class shell (bead oo-64ako) ------------------------------------------------------

// The initialiser and the set-up from the definition: every key the station reads, and the
// virtual dock it makes because it has none.
OO_TEST(initAndSetUpFromDictionary)
{
	@autoreleasepool
	{
		SetUp();
		TestStation *station = MakeStation("coriolis", {
			{ "port_radius", oo::PList(750.0) },
			{ "equivalent_tech_level", oo::PList(9) },
			{ "max_scavengers", oo::PList(2) },
			{ "max_defense_ships", oo::PList(4) },
			{ "max_police", oo::PList(5) },
			{ "equipment_price_factor", oo::PList(0.25) },
			{ "has_npc_traffic", oo::PList(false) },
			{ "suppress_arrival_reports", oo::PList(true) },
			{ "allegiance", oo::PList(std::string("pirate")) },
			{ "market_capacity", oo::PList(50) },
			{ "market_definition", oo::PList(oo::PList::Array{ oo::PList(std::string("a")), oo::PList(std::string("b")) }) },
			{ "market_script", oo::PList(std::string("market.js")) },
			{ "market_monitored", oo::PList(true) },
			{ "market_broadcast", oo::PList(false) },
			{ "requires_docking_clearance", oo::PList(true) },
			{ "allows_fast_docking", oo::PList(true) },
			{ "allows_auto_docking", oo::PList(false) },
			{ "interstellar_undocking", oo::PList(true) },
		});
		OO_CHECK(station != nil);
		OO_CHECK([station isShip] && [station isStation] && ![station isPlayer]);
		OO_CHECK([station cxx_shipDataKey] == std::optional<std::string>("coriolis"));
		OO_CHECK([station hasBreakPattern]);
		OO_CHECK([station alertLevel] == STATION_ALERT_LEVEL_GREEN);
		OO_CHECK([station equivalentTechLevel] == 9);
		OO_CHECK([station countOfDockedContractors] == 2);
		OO_CHECK([station countOfDockedPolice] == 5);
		OO_CHECK([station countOfDockedDefenders] == 4);
		OO_CHECK([station equipmentPriceFactor] == 0.5f);		// at least 0.5
		OO_CHECK(![station hasNPCTraffic]);
		OO_CHECK([station suppressArrivalReports]);
		OO_CHECK([station cxx_allegiance] == std::optional<std::string>("pirate"));
		OO_CHECK([station marketCapacity] == 50);
		OO_CHECK([station cxx_marketDefinition].isArray() && [station cxx_marketDefinition].count() == 2);
		OO_CHECK([station cxx_marketScriptName] == std::optional<std::string>("market.js"));
		OO_CHECK([station marketMonitored] && ![station marketBroadcast]);	// not the main station
		OO_CHECK([station requiresDockingClearance]);
		OO_CHECK([station allowsFastDocking] && ![station allowsAutoDocking]);
		OO_CHECK([station interstellarUndockingAllowed]);
		OO_CHECK([station allowsSaving] == [UNIVERSE deterministicPopulation]);	// a fixed station (no top speed)
		OO_CHECK(vector_equal([station virtualPortDimensions], make_vector(69, 69, 250)));
		OO_CHECK([station playerReservedDock] == nil);
		OO_CHECK([station group] != nil && [station group] == [station stationGroup]);
		OO_CHECK(![station cxx_crew].has_value());

		// No docks: a virtual one, at the port radius.
		OO_CHECK(sVirtualDocks == 1);
		OO_CHECK(sVirtualDockDict.get<std::string>("subentity_key", "") == "oolite-dock-virtual");
		OO_CHECK(sVirtualDockDict.get<bool>("is_dock", false) && sVirtualDockDict.get<bool>("_is_virtual_dock", false));
		OO_CHECK(sVirtualDockDict.get<std::string>("dock_label", "") == "the docking bay");
		const oo::PList *position = sVirtualDockDict.find("position");
		OO_CHECK(position != nullptr && position->get<double>("z", 0) == 750.0 && position->get<double>("x", 1) == 0.0);
		OO_CHECK([station cxx_dockSubEntities].empty());
	}
}


// The defaults of every key the station reads.
OO_TEST(setUpDefaults)
{
	@autoreleasepool
	{
		SetUp();
		TestStation *station = MakeStation("plain");
		OO_CHECK(station != nil);
		OO_CHECK([station countOfDockedContractors] == 3 && [station countOfDockedDefenders] == 3);
		OO_CHECK([station countOfDockedPolice] == STATION_MAX_POLICE);
		OO_CHECK([station equipmentPriceFactor] == 1.0f);
		OO_CHECK([station hasNPCTraffic]);		// a fixed station has traffic
		OO_CHECK(![station suppressArrivalReports]);
		OO_CHECK(![station cxx_allegiance].has_value());
		OO_CHECK([station marketCapacity] == MAIN_SYSTEM_MARKET_LIMIT);
		OO_CHECK([station cxx_marketDefinition].isNull());
		OO_CHECK(![station cxx_marketScriptName].has_value());
		OO_CHECK(![station marketMonitored] && [station marketBroadcast]);
		OO_CHECK([station requiresDockingClearance] == [UNIVERSE dockingClearanceProtocolActive]);
		OO_CHECK(![station allowsFastDocking] && [station allowsAutoDocking]);
		OO_CHECK(![station interstellarUndockingAllowed]);
		OO_CHECK(![station isRotatingStation] || [station cxx_shipInfoDictionary].find("roles") == nullptr);
		OO_CHECK(![station marketOverrideName].has_value());
		OO_CHECK(![station hasShipyard]);
		OO_CHECK(sVirtualDocks == 1);
	}
}


// A virtual dock that cannot be made: -setUpSubEntities answers NO, which ShipEntity's set-up
// ignores, so the station is still made.
OO_TEST(virtualDockThatFails)
{
	@autoreleasepool
	{
		SetUp();
		sFailVirtualDock = true;
		TestStation *station = MakeStation("dockless");
		OO_CHECK(station != nil && sVirtualDocks == 1);
		OO_CHECK(![station setUpSubEntities] && sVirtualDocks == 2);
		sFailVirtualDock = false;
		OO_CHECK([station setUpSubEntities] && sVirtualDocks == 3);
	}
}


// Stations of any scan class are piloted unless explicitly unpiloted or a hulk.
OO_TEST(isUnpiloted)
{
	@autoreleasepool
	{
		SetUp();
		TestStation *station = MakeStation("rock", { { "scan_class", oo::PList(std::string("CLASS_CARGO")) } });
		OO_CHECK([station isUnpiloted]);			// unpiloted = yes
		SetExplicitlyUnpiloted(station, false);
		OO_CHECK(![station isUnpiloted]);			// a ship of CLASS_CARGO would be
		[station setHulk:YES];
		OO_CHECK([station isUnpiloted]);
		[station setHulk:NO];
		OO_CHECK(![station isUnpiloted]);
	}
}


OO_TEST(flagsAndCounts)
{
	@autoreleasepool
	{
		SetUp();
		TestStation *station = MakeStation("flags");
		[station setEquivalentTechLevel:4];
		OO_CHECK([station equivalentTechLevel] == 4);

		[station setHasNPCTraffic:NO];
		OO_CHECK(![station hasNPCTraffic]);
		[station setHasNPCTraffic:(BOOL)7];
		OO_CHECK([station hasNPCTraffic] == YES);

		[station setRequiresDockingClearance:(BOOL)2];
		OO_CHECK([station requiresDockingClearance] == YES);
		[station setRequiresDockingClearance:NO];
		OO_CHECK([station requiresDockingClearance] == NO);

		[station setAllowsFastDocking:(BOOL)4];
		OO_CHECK([station allowsFastDocking] == YES);
		[station setAllowsAutoDocking:NO];
		OO_CHECK([station allowsAutoDocking] == NO);

		[station setSuppressArrivalReports:(BOOL)8];
		OO_CHECK([station suppressArrivalReports] == YES);
		[station setHasBreakPattern:NO];
		OO_CHECK([station hasBreakPattern] == NO);
		[station setHasBreakPattern:YES];
		OO_CHECK([station hasBreakPattern] == YES);
	}
}


// The shipyard is held as given and edited in place; the interfaces are a live map.
OO_TEST(shipyardAndInterfaces)
{
	@autoreleasepool
	{
		SetUp();
		TestStation *station = MakeStation("yard");
		OO_CHECK([station cxx_localShipyard] == nullptr);	// not generated yet
		const std::vector<oo::PList> given{ oo::PList(oo::PList::Dict{ { "id", oo::PList(std::string("x")) } }) };
		[station cxx_setLocalShipyard:given];
		std::vector<oo::PList> *shipyard = [station cxx_localShipyard];
		OO_CHECK(shipyard != nullptr && shipyard->size() == 1);
		shipyard->push_back(oo::PList());
		OO_CHECK([station cxx_localShipyard]->size() == 2);

		auto *interfaces = [station cxx_localInterfaces];
		OO_CHECK(interfaces != nullptr && interfaces->empty());
		[station cxx_setInterfaceDefinition:nil forKey:"absent"];	// removing nothing
		OO_CHECK([station cxx_localInterfaces]->empty());

		StationEntity *none = nil;
		OO_CHECK([none cxx_localShipyard] == nullptr && [none cxx_localInterfaces] == nullptr);
	}
}


// The shipdata keys the station reads after the set-up: rotation, the market override, the
// shipyard.
OO_TEST(shipInfoQueries)
{
	@autoreleasepool
	{
		SetUp();
		OO_CHECK([MakeStation("r1", { { "rotating", oo::PList(true) }, { "roles", oo::PList(std::string("carrier")) } }) isRotatingStation]);
		OO_CHECK([MakeStation("r2", { { "roles", oo::PList(std::string("station rotating-station")) } }) isRotatingStation]);
		OO_CHECK(![MakeStation("r3", { { "roles", oo::PList(std::string("carrier")) } }) isRotatingStation]);
		OO_CHECK([MakeStation("r4") isRotatingStation]);		// no roles at all: legacy YES

		OO_CHECK([MakeStation("m1", { { "market", oo::PList(std::string("special")) } }) marketOverrideName] == std::optional<std::string>("special"));
		OO_CHECK([MakeStation("m2", { { "market", oo::PList(3) } }) marketOverrideName] == std::optional<std::string>("3"));
		OO_CHECK(![MakeStation("m3", { { "market", oo::PList(oo::PList::Array{}) } }) marketOverrideName].has_value());

		OO_CHECK([MakeStation("s1", { { "has_shipyard", oo::PList(true) } }) hasShipyard]);
		OO_CHECK([MakeStation("s2", { { "hasShipyard", oo::PList(std::string("yes")) } }) hasShipyard]);
		OO_CHECK(![MakeStation("s3", { { "has_shipyard", oo::PList(false) }, { "hasShipyard", oo::PList(true) } }) hasShipyard]);
		OO_CHECK(![MakeStation("s4") hasShipyard]);
	}
}


OO_TEST(positionPlanetAndDescription)
{
	@autoreleasepool
	{
		SetUp();
		TestStation *station = MakeStation("where", { { "name", oo::PList(std::string("Coriolis")) } });
		[station setPosition:make_HPvector(1, 2, 3)];
		[station setOrientation:kIdentityQuaternion];
		HPVector forward = vectorToHPVector(vector_forward_from_quaternion(kIdentityQuaternion));
		OO_CHECK(Near([station beaconPosition], HPvector_add(make_HPvector(1, 2, 3), HPvector_multiply_scalar(forward, 10000.0))));

		[station setPlanet:nil];
		OO_CHECK([station planet] == nil);

		const std::optional<std::string> components = [station cxx_descriptionComponents];
		OO_CHECK(components.has_value() && components->rfind("\"Coriolis\" \"Coriolis\" ", 0) == 0);	// the ship's own after the station's name

#ifndef NDEBUG
		[station dumpSelfState];		// logs; nothing to check but that it runs
#endif
	}
}


// --- The crossing (after the conversion) ---------------------------------------------------------

// A station's C++ part is a cxx::StationEntity, the facade's typed alias is that part, and from C++
// the ship's virtual members reach the station's.
OO_TEST(objCStationPartIsAStation)
{
	@autoreleasepool
	{
		SetUp();
		TestStation *station = MakeStation("crossing", { { "name", oo::PList(std::string("Dodo")) } });
		Entity *asEntity = station;
		cxx::StationEntity *part = oo::ToCxx(station);
		OO_CHECK(part != nullptr && part == station->_cxxStation);
		OO_CHECK(static_cast<cxx::ShipEntity *>(part) == station->_cxxShip);
		OO_CHECK(dynamic_cast<cxx::StationEntity *>(oo::ToCxx(asEntity)) == part);
		OO_CHECK(oo::AsObjCEntity(part) != nullptr && oo::ToObjC(part) == station);
		OO_CHECK(part->getHasBreakPattern() && part->getMarketCapacity() == MAIN_SYSTEM_MARKET_LIMIT);

		cxx::ShipEntity *asShip = part;
		OO_CHECK(asShip->isUnpiloted());		// unpiloted = yes
		SetExplicitlyUnpiloted(station, false);
		OO_CHECK(!asShip->isUnpiloted());
		cxx::Entity *asCxxEntity = part;
		OO_CHECK(asCxxEntity->descriptionComponents() == [station cxx_descriptionComponents]);
	}
}


// A failing initialiser that releases the station before [super init]: the facade's -dealloc runs
// without a C++ part.
OO_TEST(stationReleasedBeforeInit)
{
	@autoreleasepool
	{
		SetUp();
		TestStation *station = [TestStation alloc];
		OO_CHECK(station->_cxxStation == nullptr);
		[station release];
	}
}


// --- Slice 2: docking traffic control and the launch queue (bead oo-9j462) --------------------------
// Written against the Objective-C API and run on the unconverted slice first. The test's stations
// have no docks (the virtual dock is a stand-in), so the cases pin what the station does itself.

@interface StationEntity (TestSlice2)
- (void) addShipToLaunchQueue:(ShipEntity *)ship withPriority:(BOOL)priority;	// the private category of StationEntity.mm
- (unsigned) countOfShipsInLaunchQueueWithPrimaryRole:(const std::string &)role;
- (oo::PList) holdPositionInstructionForShip:(ShipEntity *)ship;
- (void) addShipToStationCount:(ShipEntity *)ship;
- (void) autoDockShipsOnHold;
- (BOOL) hasEligibleDock;	// defined, declared nowhere
@end


// A ship visiting the station: its own set-up, and invisible to scripts.
@interface TestVisitor: ShipEntity
@end


@implementation TestVisitor

- (BOOL) isVisibleToScripts	{ return NO; }

@end


namespace {

TestVisitor *MakeVisitor(const std::string &key, oo::PList::Dict extra = {})
{
	oo::PList::Dict dict{ { "unpiloted", oo::PList(true) } };
	for (auto &entry : extra)  dict[entry.first] = entry.second;
	return [[[TestVisitor alloc] cxx_initWithKey:key definition:oo::PList(std::move(dict))] autorelease];
}

OOWeakSet *ShipsOnHold2(StationEntity *s)				{ return s->_cxxStation->_shipsOnHold; }
void SetDefendersLaunched2(StationEntity *s, unsigned n)	{ s->_cxxStation->defenders_launched = n; }
void SetScavengersLaunched2(StationEntity *s, unsigned n)	{ s->_cxxStation->scavengers_launched = n; }
unsigned DockedShuttles2(StationEntity *s)				{ return s->_cxxStation->docked_shuttles; }
unsigned DockedTraders2(StationEntity *s)				{ return s->_cxxStation->docked_traders; }

}	// namespace


OO_TEST(slice2NoDocks)
{
	@autoreleasepool
	{
		SetUp();
		TestStation *station = MakeStation("dockless2");
		TestVisitor *ship = MakeVisitor("visitor");
		OO_CHECK([station cxx_dockSubEntities].empty());
		OO_CHECK(![station hasMultipleDocks] && ![station hasClearDock] && ![station hasLaunchDock] && ![station hasEligibleDock]);
		OO_CHECK([station selectDockForDocking] == nil);
		OO_CHECK(![station dockingCorridorIsEmpty]);
		OO_CHECK(![station shipIsInDockingCorridor:ship] && ![station shipIsInDockingCorridor:nil]);
		OO_CHECK(vector_equal([station portUpVectorForShip:ship], kZeroVector));
		OO_CHECK([station countOfShipsInLaunchQueueWithPrimaryRole:"trader"] == 0);
		OO_CHECK(![station fitsInDock:nil] && ![station fitsInDock:ship] && ![station fitsInDock:ship andLogNoFit:NO]);
		OO_CHECK([station dockingInstructionsForShip:nil].isNull());

		// Nothing to launch from, clear or check: nothing happens.
		[station addShipToLaunchQueue:ship withPriority:YES];	// logged
		[station launchShip:ship];
		[station clearDockingCorridor];
		[station sanityCheckShipsOnApproach];
		[station autoDockShipsOnHold];
		OO_CHECK([ship status] == STATUS_IN_FLIGHT && [station status] == STATUS_IN_FLIGHT);
	}
}


// The ships on hold: told to hold position (as docking instructions), cleared, aborted.
OO_TEST(slice2HoldPosition)
{
	@autoreleasepool
	{
		SetUp();
		TestStation *station = MakeStation("holder");
		TestVisitor *ship = MakeVisitor("waiter");
		[ship setPosition:make_HPvector(1, 2, 3)];
		[ShipsOnHold2(station) addObject:ship];		// already holding: no message
		const oo::PList hold = [station holdPositionInstructionForShip:ship];
		OO_CHECK(hold.get<std::string>("ai_message", "") == "HOLD_POSITION" && hold.find("comms_message") == nullptr);
		OO_CHECK(hold.get<double>("speed", -1) == 0 && hold.get<double>("range", -1) == 100);
		OO_CHECK(hold.get<int>("docking_stage", 0) == -1 && !hold.get<bool>("match_rotation", true));
		const oo::PList *destination = hold.find("destination");
		OO_CHECK(destination != nullptr && destination->get<double>("x", 0) == 1 && destination->get<double>("z", 0) == 3);
		const oo::PList *stationRef = hold.find("station");
		OO_CHECK(stationRef != nullptr && [oo::ObjectIn(*stationRef) weakRefUnderlyingObject] == station);
		OO_CHECK([ShipsOnHold2(station) containsObject:ship] && [ShipsOnHold2(station) count] == 1);

		[station clear];
		OO_CHECK([ShipsOnHold2(station) count] == 0);

		[ShipsOnHold2(station) addObject:ship];
		[station abortDockingForShip:ship];
		OO_CHECK(![ShipsOnHold2(station) containsObject:ship]);
	}
}


// A docked ship counts back in: defenders and scavengers return. (Shuttles and traders are known by
// the role categories, which the test's universe has not loaded: they count as neither.)
OO_TEST(slice2StationCount)
{
	@autoreleasepool
	{
		SetUp();
		TestStation *station = MakeStation("counter", { { "has_npc_traffic", oo::PList(false) } });
		OO_CHECK(DockedShuttles2(station) == 0 && DockedTraders2(station) == 0);
		[station addShipToStationCount:MakeVisitor("shuttle", { { "roles", oo::PList(std::string("shuttle")) } })];
		OO_CHECK(DockedShuttles2(station) == 0 && DockedTraders2(station) == 0);

		SetDefendersLaunched2(station, 2);
		const unsigned police = [station countOfDockedPolice];
		[station addShipToStationCount:MakeVisitor("cop", { { "roles", oo::PList(std::string("defense_ship")) } })];
		OO_CHECK([station countOfDockedPolice] == police + 1);

		SetScavengersLaunched2(station, 1);
		const unsigned contractors = [station countOfDockedContractors];
		[station addShipToStationCount:MakeVisitor("miner", { { "roles", oo::PList(std::string("miner")) } })];
		OO_CHECK([station countOfDockedContractors] == contractors + 1);
		[station addShipToStationCount:MakeVisitor("scavenger", { { "roles", oo::PList(std::string("scavenger")) } })];
		OO_CHECK([station countOfDockedContractors] == contractors + 1);	// none out any more
	}
}


// From C++ (after the conversion): the members.
OO_TEST(slice2MembersFromCxx)
{
	@autoreleasepool
	{
		SetUp();
		TestStation *station = MakeStation("member2");
		TestVisitor *ship = MakeVisitor("guest");
		cxx::StationEntity *part = station->_cxxStation;
		OO_CHECK(!part->hasMultipleDocks() && !part->fitsInDock(nil) && part->selectDockForDocking() == nil);
		[ShipsOnHold2(station) addObject:ship];
		OO_CHECK(part->holdPositionInstructionForShip(ship).get<std::string>("ai_message", "") == "HOLD_POSITION");
		part->clear();
		OO_CHECK([ShipsOnHold2(station) count] == 0);
	}
}


// --- Slice 3: docking clearance, damage, allegiance and alert level (bead oo-hjzwk) ---------------
// Written against the Objective-C API and run on the unconverted slice first.

namespace {

double LastPatrolReport3(StationEntity *s)			{ return s->_cxxStation->last_patrol_report_time; }
void SetLastPatrolReport3(StationEntity *s, double t)	{ s->_cxxStation->last_patrol_report_time = t; }
void SetEnergy3(Entity *e, GLfloat energy)			{ e->_cxxEntity->energy = energy; e->_cxxEntity->maxEnergy = 1000; }
GLfloat Energy3(Entity *e)							{ return e->_cxxEntity->energy; }
void SetPrimaryTarget3(ShipEntity *s, Entity *target)
{
	[s->_cxxShip->_primaryTarget release];
	s->_cxxShip->_primaryTarget = [target weakRetain];
}

}	// namespace


OO_TEST(slice3AllegianceAndAlertLevel)
{
	@autoreleasepool
	{
		SetUp();
		TestStation *station = MakeStation("alert");
		[station cxx_setAllegiance:std::string("hunter")];
		OO_CHECK([station cxx_allegiance] == std::optional<std::string>("hunter"));
		[station cxx_setAllegiance:std::nullopt];
		OO_CHECK(![station cxx_allegiance].has_value());

		OO_CHECK([station alertLevel] == STATION_ALERT_LEVEL_GREEN);
		[station setAlertLevel:STATION_ALERT_LEVEL_RED signallingScript:NO];
		OO_CHECK([station alertLevel] == STATION_ALERT_LEVEL_RED);
		[station setAlertLevel:(OOStationAlertLevel)99 signallingScript:NO];		// clamped
		OO_CHECK([station alertLevel] == STATION_ALERT_LEVEL_RED);
		[station setAlertLevel:(OOStationAlertLevel)0 signallingScript:NO];
		OO_CHECK([station alertLevel] == STATION_ALERT_LEVEL_GREEN);
		[station increaseAlertLevel];
		OO_CHECK([station alertLevel] == STATION_ALERT_LEVEL_YELLOW);
		[station increaseAlertLevel];
		[station increaseAlertLevel];
		OO_CHECK([station alertLevel] == STATION_ALERT_LEVEL_RED);
		[station decreaseAlertLevel];
		OO_CHECK([station alertLevel] == STATION_ALERT_LEVEL_YELLOW);

		// A target at yellow or red alert is a hostile one; none, or green, is not.
		OO_CHECK(![station hasHostileTarget]);
		TestVisitor *intruder = MakeVisitor("intruder");
		SetPrimaryTarget3(station, intruder);
		OO_CHECK([station hasHostileTarget]);
		[station setAlertLevel:STATION_ALERT_LEVEL_GREEN signallingScript:NO];
		OO_CHECK(![station hasHostileTarget]);
	}
}


OO_TEST(slice3DamageAndMovement)
{
	@autoreleasepool
	{
		SetUp();
		TestStation *station = MakeStation("target");
		TestVisitor *friendly = MakeVisitor("defender");
		[friendly setGroup:[station group]];

		// Friendly fire is ignored.
		SetEnergy3(station, 500);
		[station takeEnergyDamage:100 from:friendly becauseOf:friendly weaponIdentifier:""];
		OO_CHECK(Energy3(station) == 500);

		// A station that is not the main one is moved like a ship.
		[station setVelocity:kZeroVector];
		[station adjustVelocity:make_vector(1, 0, 0)];
		OO_CHECK(vector_equal([station velocity], make_vector(1, 0, 0)));
	}
}


OO_TEST(slice3PatrolsAndQueues)
{
	@autoreleasepool
	{
		SetUp();
		TestStation *station = MakeStation("base");
		SetLastPatrolReport3(station, -1000);
		[station acceptPatrolReportFrom:nil];
		OO_CHECK(LastPatrolReport3(station) == [UNIVERSE getTime]);
		OO_CHECK([station currentlyInDockingQueues] == 0 && [station currentlyInLaunchingQueues] == 0);
	}
}


// From C++ (after the conversion): the members, and the ship's virtual members reaching the station's.
OO_TEST(slice3MembersFromCxx)
{
	@autoreleasepool
	{
		SetUp();
		TestStation *station = MakeStation("member3");
		cxx::StationEntity *part = station->_cxxStation;
		part->setAlertLevel(STATION_ALERT_LEVEL_RED, NO);
		OO_CHECK(part->getAlertLevel() == STATION_ALERT_LEVEL_RED && [station alertLevel] == STATION_ALERT_LEVEL_RED);
		part->setAllegiance(std::string("neutral"));
		OO_CHECK(part->getAllegiance() == std::optional<std::string>("neutral"));
		cxx::ShipEntity *asShip = part;
		SetPrimaryTarget3(station, MakeVisitor("foe"));
		OO_CHECK(asShip->hasHostileTarget());		// virtual: the station's
		TestVisitor *friendly = MakeVisitor("friend");
		[friendly setGroup:[station group]];
		SetEnergy3(station, 500);
		cxx::Entity *asEntity = part;
		asEntity->takeEnergyDamage(100, oo::ToCxx(static_cast<Entity *>(friendly)), oo::ToCxx(static_cast<Entity *>(friendly)), "");
		OO_CHECK(Energy3(station) == 500);			// friendly fire, through the root's virtual
	}
}


// --- Slice 4: NPC launchers (bead oo-tqem7) -------------------------------------------------------
// Written against the Objective-C API and run on the unconverted slice first. The test's station
// has no docks (its virtual dock is only recorded), so every launcher takes its "no launch docks"
// path: nothing is made, queued or counted, and the station's universe is never asked for a ship.

namespace {

unsigned DefendersLaunched4(StationEntity *s)	{ return s->_cxxStation->defenders_launched; }
unsigned ScavengersLaunched4(StationEntity *s)	{ return s->_cxxStation->scavengers_launched; }
unsigned DockedShuttles4(StationEntity *s)		{ return s->_cxxStation->docked_shuttles; }

}	// namespace


OO_TEST(slice4LaunchersWithoutLaunchDock)
{
	@autoreleasepool
	{
		SetUp();
		TestStation *station = MakeStation("launcher", { { "max_police", oo::PList(4) }, { "max_defense_ships", oo::PList(4) } });
		SetPrimaryTarget3(station, MakeVisitor("quarry"));
		OO_CHECK(![station hasLaunchDock]);
		const unsigned defenders = DefendersLaunched4(station);
		const unsigned scavengers = ScavengersLaunched4(station);
		const unsigned shuttles = DockedShuttles4(station);

		OO_CHECK([station launchIndependentShip:"trader"].isNull());
		OO_CHECK(oo::ObjCRefsIn<ShipEntity *>([station launchPolice]).empty());
		OO_CHECK([station launchDefenseShip] == nil);
		OO_CHECK([station launchScavenger] == nil);
		OO_CHECK([station launchMiner] == nil);
		OO_CHECK([station launchPirateShip] == nil);
		OO_CHECK([station launchShuttle] == nil);
		OO_CHECK([station launchEscort] == nil);
		OO_CHECK([station launchPatrol] == nil);
		[station launchShipWithRole:"shuttle"];

		OO_CHECK(DefendersLaunched4(station) == defenders && ScavengersLaunched4(station) == scavengers && DockedShuttles4(station) == shuttles);
		OO_CHECK([station countOfShipsInLaunchQueueWithPrimaryRole:"police"] == 0 && [station currentlyInLaunchingQueues] == 0);
		OO_CHECK([station status] == STATUS_IN_FLIGHT);
	}
}


// The launchers stay reachable by selector (ADR-0055 item 5: AI and scripts send them by name).
OO_TEST(slice4LaunchersAnswerTheirSelectors)
{
	@autoreleasepool
	{
		SetUp();
		TestStation *station = MakeStation("selectors");
		OO_CHECK([station respondsToSelector:@selector(launchIndependentShip:)] && [station respondsToSelector:@selector(launchShipWithRole:)]);
		OO_CHECK([station respondsToSelector:@selector(launchPolice)] && [station respondsToSelector:@selector(launchDefenseShip)]);
		OO_CHECK([station respondsToSelector:@selector(launchScavenger)] && [station respondsToSelector:@selector(launchMiner)]);
		OO_CHECK([station respondsToSelector:@selector(launchPirateShip)] && [station respondsToSelector:@selector(launchShuttle)]);
		OO_CHECK([station respondsToSelector:@selector(launchEscort)] && [station respondsToSelector:@selector(launchPatrol)]);
	}
}


// From C++ (after the conversion): the members, which the facade's selectors forward to.
OO_TEST(slice4MembersFromCxx)
{
	@autoreleasepool
	{
		SetUp();
		TestStation *station = MakeStation("member4");
		SetPrimaryTarget3(station, MakeVisitor("mark"));
		cxx::StationEntity *part = station->_cxxStation;
		const unsigned defenders = DefendersLaunched4(station);
		OO_CHECK(part->launchIndependentShip("trader").isNull());
		OO_CHECK(oo::ObjCRefsIn<ShipEntity *>(part->launchPolice()).empty());
		OO_CHECK(part->launchDefenseShip() == nil && part->launchScavenger() == nil && part->launchMiner() == nil);
		OO_CHECK(part->launchPirateShip() == nil && part->launchShuttle() == nil && part->launchEscort() == nil);
		OO_CHECK(part->launchPatrol() == nil);
		part->launchShipWithRole("escort");
		OO_CHECK(DefendersLaunched4(station) == defenders && part->currentlyInLaunchingQueues() == 0);
	}
}


OO_TEST_MAIN()
