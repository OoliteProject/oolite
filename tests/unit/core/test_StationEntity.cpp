/*	test_StationEntity.mm
	Unit tests for StationEntity (src/Core/Entities/StationEntity.h), the station: the class shell,
	which holds the station's state and its accessors, market, shipyard, flags and set-up in C++.
	The station is made in C++ the cases call its members, and
	the selectors the engine and the AI send by name are sent to its object.

	As test_ShipEntity's, the station's object needs the game graph, so the test links the whole
	game but main (['*']) and uses a Universe that was never initialised and a plain entity as
	PLAYER. The station keeps StationEntity's and ShipEntity's own set-up from the definition; only
	the virtual dock it makes when it has no docks is a stand-in (TestStation, a C++ subclass,
	records the dock's definition instead of asking the universe for the shipdata entry). The cases
	test the class's own units; the cases after "The crossing" pin the C++ part. Run: bash
	tools/check-core-tests.sh
	test_StationEntity
*/

#include "StationEntity.h"
#include "DockEntity.h"
#include "Universe.h"
#include "PlayerEntity.h"
#include "OODescription.h"
#include "oofnd/PList.hpp"
#include "oofnd/StdLib.hpp"
#include "EntityOOJavaScriptExtensions.h"
#include "OOJSEntity.h"
#include "OOJSShip.h"
#include "OOJSStation.h"
#include "OOCallByName.h"	// oo::EntityRespondsToName / oo::CallEntityByName

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
extern JSContext *gOOJSMainThreadContext;


class TestStationPlayer : public PlayerEntity
{
public:
	HPVector viewpointPosition() override	{ return kZeroHPVector; }
};

// A C++ player, as PlayerEntity::sharedPlayer() makes
// the game's, retained (+1).
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

// What the next station's virtual dock does, and the definition it was given.
bool sFailVirtualDock = false;
int sVirtualDocks = 0;
oo::PList sVirtualDockDict;

}	// namespace

// A station whose virtual dock only records its definition (the dock itself is
// a shipdata entry).
class TestStation : public StationEntity
{
public:
	bool setUpOneStandardSubentity(const oo::PList &subentDict, bool asTurret) override
	{
		if (asTurret)  return false;
		sVirtualDocks++;
		sVirtualDockDict = subentDict;
		return !sFailVirtualDock;
	}
};


namespace {

void SetExplicitlyUnpiloted(ShipEntity *s, bool value)	{ s->_explicitlyUnpiloted = value; }


void SetUp()
{
	static Universe *universe = nullptr;
	if (universe == nullptr)
	{
		universe = new Universe();	// never released
	}
	gSharedUniverse = universe;
	static TestStationPlayer *player = nullptr;
	if (player == nullptr)  player = NewTestPlayer<TestStationPlayer>();
	gOOPlayer = player;
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


// Made as StationEntity::newStationObject() makes a station, and its object
// autoreleased.
TestStation *MakeStation(const std::string &key, oo::PList::Dict extra = {})
{
	::ShipEntity *ship = oo::ToShip(oo::NewShipObject(oo::makeRef<TestStation>(), key, Definition(std::move(extra))));
	if (ship == nullptr)  return nullptr;
	TestStation *station = static_cast<TestStation *>(ship);
	station->initStationDefaults();
	oo::AutoreleaseEntity(station);
	return station;
}


// A message to nil's answers.
bool IsRotatingStation(TestStation *s)	{ return s != nullptr ? s->isRotatingStation() : false; }
std::optional<std::string> MarketOverrideName(TestStation *s)	{ return s != nullptr ? s->marketOverrideName() : std::nullopt; }
bool HasShipyard(TestStation *s)	{ return s != nullptr ? s->hasShipyard() : false; }


bool Near(HPVector a, HPVector b)	{ return std::fabs(a.x - b.x) < 1e-3 && std::fabs(a.y - b.y) < 1e-3 && std::fabs(a.z - b.z) < 1e-3; }

}	// namespace

// --- The class shell
// ------------------------------------------------------

// The initialiser and the set-up from the definition: every key the station
// reads, and the virtual dock it makes because it has none.
OO_TEST(initAndSetUpFromDictionary)
{
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
		OO_CHECK(station != nullptr);
		OO_CHECK((station != nullptr ? station->getIsShip() : false) && (station != nullptr ? station->getIsStation() : false) && !(station != nullptr ? station->getIsPlayer() : false));
		OO_CHECK((station != nullptr ? station->shipDataKey() : std::optional<std::string>()) == std::optional<std::string>("coriolis"));
		OO_CHECK((station != nullptr ? station->getHasBreakPattern() : false));
		OO_CHECK((station != nullptr ? station->getAlertLevel() : OOStationAlertLevel{}) == OOStationAlertLevel::kGreen);
		OO_CHECK((station != nullptr ? station->getEquivalentTechLevel() : 0) == 9);
		OO_CHECK((station != nullptr ? station->countOfDockedContractors() : unsigned{}) == 2);
		OO_CHECK((station != nullptr ? station->countOfDockedPolice() : unsigned{}) == 5);
		OO_CHECK((station != nullptr ? station->countOfDockedDefenders() : unsigned{}) == 4);
		OO_CHECK((station != nullptr ? station->getEquipmentPriceFactor() : 0.0f) == 0.5f);		// at least 0.5
		OO_CHECK(!(station != nullptr ? station->getHasNPCTraffic() : false));
		OO_CHECK((station != nullptr ? station->suppressArrivalReports() : false));
		OO_CHECK((station != nullptr ? station->getAllegiance() : std::optional<std::string>()) == std::optional<std::string>("pirate"));
		OO_CHECK((station != nullptr ? station->getMarketCapacity() : 0) == 50);
		OO_CHECK((station != nullptr ? station->getMarketDefinition() : oo::PList()).isArray() && (station != nullptr ? station->getMarketDefinition() : oo::PList()).count() == 2);
		OO_CHECK((station != nullptr ? station->getMarketScriptName() : std::optional<std::string>()) == std::optional<std::string>("market.js"));
		OO_CHECK((station != nullptr ? station->getMarketMonitored() : false) && !(station != nullptr ? station->getMarketBroadcast() : false));	// not the main station
		OO_CHECK((station != nullptr ? station->getRequiresDockingClearance() : false));
		OO_CHECK((station != nullptr ? station->getAllowsFastDocking() : false) && !(station != nullptr ? station->getAllowsAutoDocking() : false));
		OO_CHECK((station != nullptr ? station->getInterstellarUndockingAllowed() : false));
		OO_CHECK((station != nullptr ? station->getAllowsSaving() : false) == (UNIVERSE != nullptr ? UNIVERSE->deterministicPopulation() : false));	// a fixed station (no top speed)
		OO_CHECK(vector_equal((station != nullptr ? station->virtualPortDimensions() : Vector{}), make_vector(69, 69, 250)));
		OO_CHECK((station != nullptr ? station->playerReservedDock() : (DockEntity *)nullptr) == nullptr);
		OO_CHECK((station != nullptr ? station->group() : (OOShipGroup *)nullptr) != nullptr && (station != nullptr ? station->group() : (OOShipGroup *)nullptr) == (station != nullptr ? station->stationGroup() : (OOShipGroup *)nullptr));
		OO_CHECK(!(station != nullptr ? station->getCrew() : std::optional<std::vector<oo::Ref<OOCharacter>>>()).has_value());

		// No docks: a virtual one, at the port radius.
		OO_CHECK(sVirtualDocks == 1);
		OO_CHECK(sVirtualDockDict.get<std::string>("subentity_key", "") == "oolite-dock-virtual");
		OO_CHECK(sVirtualDockDict.get<bool>("is_dock", false) && sVirtualDockDict.get<bool>("_is_virtual_dock", false));
		OO_CHECK(sVirtualDockDict.get<std::string>("dock_label", "") == "the docking bay");
		const oo::PList *position = sVirtualDockDict.find("position");
		OO_CHECK(position != nullptr && position->get<double>("z", 0) == 750.0 && position->get<double>("x", 1) == 0.0);
		OO_CHECK((station != nullptr ? station->dockSubEntities() : std::vector<oo::EntityHold>()).empty());
	}
}


// The defaults of every key the station reads.
OO_TEST(setUpDefaults)
{
	{
		SetUp();
		TestStation *station = MakeStation("plain");
		OO_CHECK(station != nullptr);
		OO_CHECK((station != nullptr ? station->countOfDockedContractors() : unsigned{}) == 3 && (station != nullptr ? station->countOfDockedDefenders() : unsigned{}) == 3);
		OO_CHECK((station != nullptr ? station->countOfDockedPolice() : unsigned{}) == STATION_MAX_POLICE);
		OO_CHECK((station != nullptr ? station->getEquipmentPriceFactor() : 0.0f) == 1.0f);
		OO_CHECK((station != nullptr ? station->getHasNPCTraffic() : false));		// a fixed station has traffic
		OO_CHECK(!(station != nullptr ? station->suppressArrivalReports() : false));
		OO_CHECK(!(station != nullptr ? station->getAllegiance() : std::optional<std::string>()).has_value());
		OO_CHECK((station != nullptr ? station->getMarketCapacity() : 0) == MAIN_SYSTEM_MARKET_LIMIT);
		OO_CHECK((station != nullptr ? station->getMarketDefinition() : oo::PList()).isNull());
		OO_CHECK(!(station != nullptr ? station->getMarketScriptName() : std::optional<std::string>()).has_value());
		OO_CHECK(!(station != nullptr ? station->getMarketMonitored() : false) && (station != nullptr ? station->getMarketBroadcast() : false));
		OO_CHECK((station != nullptr ? station->getRequiresDockingClearance() : false) == (UNIVERSE != nullptr ? UNIVERSE->dockingClearanceProtocolActive() : false));
		OO_CHECK(!(station != nullptr ? station->getAllowsFastDocking() : false) && (station != nullptr ? station->getAllowsAutoDocking() : false));
		OO_CHECK(!(station != nullptr ? station->getInterstellarUndockingAllowed() : false));
		OO_CHECK(!(station != nullptr ? station->isRotatingStation() : false) || (station != nullptr ? station->shipInfoDictionary() : oo::PList()).find("roles") == nullptr);
		OO_CHECK(!(station != nullptr ? station->marketOverrideName() : std::optional<std::string>()).has_value());
		OO_CHECK(!(station != nullptr ? station->hasShipyard() : false));
		OO_CHECK(sVirtualDocks == 1);
	}
}


// A virtual dock that cannot be made: -setUpSubEntities answers NO, which ShipEntity's set-up
// ignores, so the station is still made.
OO_TEST(virtualDockThatFails)
{
	{
		SetUp();
		sFailVirtualDock = true;
		TestStation *station = MakeStation("dockless");
		OO_CHECK(station != nullptr && sVirtualDocks == 1);
		OO_CHECK(!(station != nullptr ? station->setUpSubEntities() : false) && sVirtualDocks == 2);
		sFailVirtualDock = false;
		OO_CHECK((station != nullptr ? station->setUpSubEntities() : false) && sVirtualDocks == 3);
	}
}


// Stations of any scan class are piloted unless explicitly unpiloted or a hulk.
OO_TEST(isUnpiloted)
{
	{
		SetUp();
		TestStation *station = MakeStation("rock", { { "scan_class", oo::PList(std::string("CLASS_CARGO")) } });
		OO_CHECK((station != nullptr ? station->isUnpiloted() : false));			// unpiloted = yes
		SetExplicitlyUnpiloted(station, false);
		OO_CHECK(!(station != nullptr ? station->isUnpiloted() : false));			// a ship of OOScanClass::kCargo would be
		if (station != nullptr)  station->setHulk(true);
		OO_CHECK((station != nullptr ? station->isUnpiloted() : false));
		if (station != nullptr)  station->setHulk(false);
		OO_CHECK(!(station != nullptr ? station->isUnpiloted() : false));
	}
}


OO_TEST(flagsAndCounts)
{
	{
		SetUp();
		TestStation *station = MakeStation("flags");
		if (station != nullptr)  station->setEquivalentTechLevel(4);
		OO_CHECK((station != nullptr ? station->getEquivalentTechLevel() : 0) == 4);

		if (station != nullptr)  station->setHasNPCTraffic(false);
		OO_CHECK(!(station != nullptr ? station->getHasNPCTraffic() : false));
		if (station != nullptr)  station->setHasNPCTraffic((bool)7);
		OO_CHECK((station != nullptr ? station->getHasNPCTraffic() : false) == true);

		if (station != nullptr)  station->setRequiresDockingClearance((bool)2);
		OO_CHECK((station != nullptr ? station->getRequiresDockingClearance() : false) == true);
		if (station != nullptr)  station->setRequiresDockingClearance(false);
		OO_CHECK((station != nullptr ? station->getRequiresDockingClearance() : false) == false);

		if (station != nullptr)  station->setAllowsFastDocking((bool)4);
		OO_CHECK((station != nullptr ? station->getAllowsFastDocking() : false) == true);
		if (station != nullptr)  station->setAllowsAutoDocking(false);
		OO_CHECK((station != nullptr ? station->getAllowsAutoDocking() : false) == false);

		if (station != nullptr)  station->setSuppressArrivalReports((bool)8);
		OO_CHECK((station != nullptr ? station->suppressArrivalReports() : false) == true);
		if (station != nullptr)  station->setHasBreakPattern(false);
		OO_CHECK((station != nullptr ? station->getHasBreakPattern() : false) == false);
		if (station != nullptr)  station->setHasBreakPattern(true);
		OO_CHECK((station != nullptr ? station->getHasBreakPattern() : false) == true);
	}
}


// The shipyard is held as given and edited in place; the interfaces are a live map.
OO_TEST(shipyardAndInterfaces)
{
	{
		SetUp();
		TestStation *station = MakeStation("yard");
		OO_CHECK((station != nullptr ? station->getLocalShipyard() : (std::vector<oo::PList> *)nullptr) == nullptr);	// not generated yet
		const std::vector<oo::PList> given{ oo::PList(oo::PList::Dict{ { "id", oo::PList(std::string("x")) } }) };
		if (station != nullptr)  station->setLocalShipyard(given);
		std::vector<oo::PList> *shipyard = (station != nullptr ? station->getLocalShipyard() : (std::vector<oo::PList> *)nullptr);
		OO_CHECK(shipyard != nullptr && shipyard->size() == 1);
		shipyard->push_back(oo::PList());
		OO_CHECK((station != nullptr ? station->getLocalShipyard() : (std::vector<oo::PList> *)nullptr)->size() == 2);

		auto *interfaces = (station != nullptr ? station->getLocalInterfaces() : (std::map<std::string, oo::Ref<OOJSInterfaceDefinition>, std::less<>> *)nullptr);
		OO_CHECK(interfaces != nullptr && interfaces->empty());
		if (station != nullptr)  station->setInterfaceDefinition(nullptr, "absent");	// removing nothing
		OO_CHECK((station != nullptr ? station->getLocalInterfaces() : (std::map<std::string, oo::Ref<OOJSInterfaceDefinition>, std::less<>> *)nullptr)->empty());

		StationEntity *none = nullptr;
		OO_CHECK((none != nullptr ? none->getLocalShipyard() : (std::vector<oo::PList> *)nullptr) == nullptr && (none != nullptr ? none->getLocalInterfaces() : (std::map<std::string, oo::Ref<OOJSInterfaceDefinition>, std::less<>> *)nullptr) == nullptr);
	}
}


// The shipdata keys the station reads after the set-up: rotation, the market override, the
// shipyard.
OO_TEST(shipInfoQueries)
{
	{
		SetUp();
		OO_CHECK(IsRotatingStation(MakeStation("r1", { { "rotating", oo::PList(true) }, { "roles", oo::PList(std::string("carrier")) } })));
		OO_CHECK(IsRotatingStation(MakeStation("r2", { { "roles", oo::PList(std::string("station rotating-station")) } })));
		OO_CHECK(!IsRotatingStation(MakeStation("r3", { { "roles", oo::PList(std::string("carrier")) } })));
		OO_CHECK(IsRotatingStation(MakeStation("r4")));		// no roles at all: legacy YES

		OO_CHECK(MarketOverrideName(MakeStation("m1", { { "market", oo::PList(std::string("special")) } })) == std::optional<std::string>("special"));
		OO_CHECK(MarketOverrideName(MakeStation("m2", { { "market", oo::PList(3) } })) == std::optional<std::string>("3"));
		OO_CHECK(!MarketOverrideName(MakeStation("m3", { { "market", oo::PList(oo::PList::Array{}) } })).has_value());

		OO_CHECK(HasShipyard(MakeStation("s1", { { "has_shipyard", oo::PList(true) } })));
		OO_CHECK(HasShipyard(MakeStation("s2", { { "hasShipyard", oo::PList(std::string("yes")) } })));
		OO_CHECK(!HasShipyard(MakeStation("s3", { { "has_shipyard", oo::PList(false) }, { "hasShipyard", oo::PList(true) } })));
		OO_CHECK(!HasShipyard(MakeStation("s4")));
	}
}


OO_TEST(positionPlanetAndDescription)
{
	{
		SetUp();
		TestStation *station = MakeStation("where", { { "name", oo::PList(std::string("Coriolis")) } });
		if (station != nullptr)  station->setPosition(make_HPvector(1, 2, 3));
		if (station != nullptr)  station->setOrientation(kIdentityQuaternion);
		HPVector forward = vectorToHPVector(vector_forward_from_quaternion(kIdentityQuaternion));
		OO_CHECK(Near((station != nullptr ? station->beaconPosition() : HPVector{}), HPvector_add(make_HPvector(1, 2, 3), HPvector_multiply_scalar(forward, 10000.0))));

		if (station != nullptr)  station->setPlanet(nullptr);
		OO_CHECK((station != nullptr ? station->getPlanet() : (OOPlanetEntity *)nullptr) == nullptr);

		const std::optional<std::string> components = (station != nullptr ? station->descriptionComponents() : std::optional<std::string>());
		OO_CHECK(components.has_value() && components->rfind("\"Coriolis\" \"Coriolis\" ", 0) == 0);	// the ship's own after the station's name

#ifndef NDEBUG
		if (station != nullptr)  station->dumpSelfState();		// logs; nothing to check but that it runs
#endif
	}
}


// --- The crossing (after the conversion) ---------------------------------------------------------

// A station's object holds its C++ part, a StationEntity, and from C++ the ship's virtual members
// reach the station's.
OO_TEST(objCStationPartIsAStation)
{
	{
		SetUp();
		TestStation *station = MakeStation("crossing", { { "name", oo::PList(std::string("Dodo")) } });
		Entity *asEntity = station;
		StationEntity *part = station;
		OO_CHECK(part != nullptr);
		OO_CHECK(dynamic_cast<StationEntity *>(asEntity) == part);
		OO_CHECK(oo::ToStation(asEntity) == part);
		OO_CHECK(part->getHasBreakPattern() && part->getMarketCapacity() == MAIN_SYSTEM_MARKET_LIMIT);

		ShipEntity *asShip = part;
		OO_CHECK(asShip->isUnpiloted());		// unpiloted = yes
		SetExplicitlyUnpiloted(station, false);
		OO_CHECK(!asShip->isUnpiloted());
		Entity *asCxxEntity = part;
		OO_CHECK(asCxxEntity->descriptionComponents() == station->descriptionComponents());
	}
}


// --- Docking traffic control and the launch queue
// -------------------------- The test's stations have no docks (the virtual dock
// is a stand-in), so the cases pin what the station does itself.

// A ship visiting the station: its own set-up, and invisible to scripts.
class TestVisitor : public ShipEntity
{
public:
	bool isVisibleToScripts() override	{ return false; }
};


namespace {

TestVisitor *MakeVisitor(const std::string &key, oo::PList::Dict extra = {})
{
	oo::PList::Dict dict{ { "unpiloted", oo::PList(true) } };
	for (auto &entry : extra)  dict[entry.first] = entry.second;
	return static_cast<TestVisitor *>(oo::ToShip(oo::AutoreleaseEntity(oo::NewShipObject(oo::makeRef<TestVisitor>(), key, oo::PList(std::move(dict))))));
}

oo::WeakSet<Entity> *ShipsOnHold2(StationEntity *s)	{ return &s->_shipsOnHold; }
void SetDefendersLaunched2(StationEntity *s, unsigned n)	{ s->defenders_launched = n; }
void SetScavengersLaunched2(StationEntity *s, unsigned n)	{ s->scavengers_launched = n; }
unsigned DockedShuttles2(StationEntity *s)				{ return s->docked_shuttles; }
unsigned DockedTraders2(StationEntity *s)				{ return s->docked_traders; }

}	// namespace


OO_TEST(slice2NoDocks)
{
	{
		SetUp();
		TestStation *station = MakeStation("dockless2");
		TestVisitor *ship = MakeVisitor("visitor");
		OO_CHECK((station != nullptr ? station->dockSubEntities() : std::vector<oo::EntityHold>()).empty());
		OO_CHECK(!(station != nullptr ? station->hasMultipleDocks() : false) && !(station != nullptr ? station->hasClearDock() : false) && !(station != nullptr ? station->hasLaunchDock() : false) && !(station != nullptr ? station->hasEligibleDock() : false));
		OO_CHECK((station != nullptr ? station->selectDockForDocking() : (DockEntity *)nullptr) == nullptr);
		OO_CHECK(!(station != nullptr ? station->dockingCorridorIsEmpty() : false));
		OO_CHECK(!(station != nullptr ? station->shipIsInDockingCorridor(ship) : false) && !(station != nullptr ? station->shipIsInDockingCorridor(nullptr) : false));
		OO_CHECK(vector_equal((station != nullptr ? station->portUpVectorForShip(ship) : Vector{}), kZeroVector));
		OO_CHECK((station != nullptr ? station->countOfShipsInLaunchQueueWithPrimaryRole("trader") : unsigned{}) == 0);
		OO_CHECK(!(station != nullptr ? station->fitsInDock(nullptr) : false) && !(station != nullptr ? station->fitsInDock(ship) : false) && !(station != nullptr ? station->fitsInDock(ship, false) : false));
		OO_CHECK((station != nullptr ? station->dockingInstructionsForShip(nullptr) : oo::PList()).isNull());

		// Nothing to launch from, clear or check: nothing happens.
		if (station != nullptr)  station->addShipToLaunchQueue(ship, true);	// logged
		if (station != nullptr)  station->launchShip(ship);
		if (station != nullptr)  station->clearDockingCorridor();
		if (station != nullptr)  station->sanityCheckShipsOnApproach();
		if (station != nullptr)  station->autoDockShipsOnHold();
		OO_CHECK((ship != nullptr ? ship->status() : OOEntityStatus{}) == OOEntityStatus::kInFlight && (station != nullptr ? station->status() : OOEntityStatus{}) == OOEntityStatus::kInFlight);
	}
}


// The ships on hold: told to hold position (as docking instructions), cleared, aborted.
OO_TEST(slice2HoldPosition)
{
	{
		SetUp();
		TestStation *station = MakeStation("holder");
		TestVisitor *ship = MakeVisitor("waiter");
		if (ship != nullptr)  ship->setPosition(make_HPvector(1, 2, 3));
		ShipsOnHold2(station)->add(ship);		// already holding: no message
		const oo::PList hold = (station != nullptr ? station->holdPositionInstructionForShip(ship) : oo::PList());
		OO_CHECK(hold.get<std::string>("ai_message", "") == "HOLD_POSITION" && hold.find("comms_message") == nullptr);
		OO_CHECK(hold.get<double>("speed", -1) == 0 && hold.get<double>("range", -1) == 100);
		OO_CHECK(hold.get<int>("docking_stage", 0) == -1 && !hold.get<bool>("match_rotation", true));
		const oo::PList *destination = hold.find("destination");
		OO_CHECK(destination != nullptr && destination->get<double>("x", 0) == 1 && destination->get<double>("z", 0) == 3);
		const oo::PList *stationRef = hold.find("station");
		OO_CHECK(stationRef != nullptr && oo::EntityInWeakNode(*stationRef) == station);
		OO_CHECK(ShipsOnHold2(station)->contains(ship) && ShipsOnHold2(station)->count() == 1);

		if (station != nullptr)  station->clear();
		OO_CHECK(ShipsOnHold2(station)->count() == 0);

		ShipsOnHold2(station)->add(ship);
		if (station != nullptr)  station->abortDockingForShip(ship);
		OO_CHECK(!ShipsOnHold2(station)->contains(ship));
	}
}


// A docked ship counts back in: defenders and scavengers return. (Shuttles and traders are known by
// the role categories, which the test's universe has not loaded: they count as neither.)
OO_TEST(slice2StationCount)
{
	{
		SetUp();
		TestStation *station = MakeStation("counter", { { "has_npc_traffic", oo::PList(false) } });
		OO_CHECK(DockedShuttles2(station) == 0 && DockedTraders2(station) == 0);
		if (station != nullptr)  station->addShipToStationCount(MakeVisitor("shuttle", { { "roles", oo::PList(std::string("shuttle")) } }));
		OO_CHECK(DockedShuttles2(station) == 0 && DockedTraders2(station) == 0);

		SetDefendersLaunched2(station, 2);
		const unsigned police = (station != nullptr ? station->countOfDockedPolice() : unsigned{});
		if (station != nullptr)  station->addShipToStationCount(MakeVisitor("cop", { { "roles", oo::PList(std::string("defense_ship")) } }));
		OO_CHECK((station != nullptr ? station->countOfDockedPolice() : unsigned{}) == police + 1);

		SetScavengersLaunched2(station, 1);
		const unsigned contractors = (station != nullptr ? station->countOfDockedContractors() : unsigned{});
		if (station != nullptr)  station->addShipToStationCount(MakeVisitor("miner", { { "roles", oo::PList(std::string("miner")) } }));
		OO_CHECK((station != nullptr ? station->countOfDockedContractors() : unsigned{}) == contractors + 1);
		if (station != nullptr)  station->addShipToStationCount(MakeVisitor("scavenger", { { "roles", oo::PList(std::string("scavenger")) } }));
		OO_CHECK((station != nullptr ? station->countOfDockedContractors() : unsigned{}) == contractors + 1);	// none out any more
	}
}


// From C++ (after the conversion): the members.
OO_TEST(slice2MembersFromCxx)
{
	{
		SetUp();
		TestStation *station = MakeStation("member2");
		TestVisitor *ship = MakeVisitor("guest");
		StationEntity *part = station;
		OO_CHECK(!part->hasMultipleDocks() && !part->fitsInDock(nullptr) && part->selectDockForDocking() == nullptr);
		ShipsOnHold2(station)->add(ship);
		OO_CHECK(part->holdPositionInstructionForShip(ship).get<std::string>("ai_message", "") == "HOLD_POSITION");
		part->clear();
		OO_CHECK(ShipsOnHold2(station)->count() == 0);
	}
}


// --- Docking clearance, damage, allegiance and alert level
// --------------- 
namespace {

double LastPatrolReport3(StationEntity *s)			{ return s->last_patrol_report_time; }
void SetLastPatrolReport3(StationEntity *s, double t)	{ s->last_patrol_report_time = t; }
void SetEnergy3(Entity *e, GLfloat energy)		{ e->energy = energy; e->maxEnergy = 1000; }
GLfloat Energy3(Entity *e)						{ return e->energy; }
void SetPrimaryTarget3(ShipEntity *s, Entity *target)
{
	s->_primaryTarget = oo::WeakRef<Entity>(target);
}

}	// namespace


OO_TEST(slice3AllegianceAndAlertLevel)
{
	{
		SetUp();
		TestStation *station = MakeStation("alert");
		if (station != nullptr)  station->setAllegiance(std::string("hunter"));
		OO_CHECK((station != nullptr ? station->getAllegiance() : std::optional<std::string>()) == std::optional<std::string>("hunter"));
		if (station != nullptr)  station->setAllegiance(std::nullopt);
		OO_CHECK(!(station != nullptr ? station->getAllegiance() : std::optional<std::string>()).has_value());

		OO_CHECK((station != nullptr ? station->getAlertLevel() : OOStationAlertLevel{}) == OOStationAlertLevel::kGreen);
		if (station != nullptr)  station->setAlertLevel(OOStationAlertLevel::kRed, false);
		OO_CHECK((station != nullptr ? station->getAlertLevel() : OOStationAlertLevel{}) == OOStationAlertLevel::kRed);
		if (station != nullptr)  station->setAlertLevel((OOStationAlertLevel)99, false);		// clamped
		OO_CHECK((station != nullptr ? station->getAlertLevel() : OOStationAlertLevel{}) == OOStationAlertLevel::kRed);
		if (station != nullptr)  station->setAlertLevel((OOStationAlertLevel)0, false);
		OO_CHECK((station != nullptr ? station->getAlertLevel() : OOStationAlertLevel{}) == OOStationAlertLevel::kGreen);
		if (station != nullptr)  station->increaseAlertLevel();
		OO_CHECK((station != nullptr ? station->getAlertLevel() : OOStationAlertLevel{}) == OOStationAlertLevel::kYellow);
		if (station != nullptr)  station->increaseAlertLevel();
		if (station != nullptr)  station->increaseAlertLevel();
		OO_CHECK((station != nullptr ? station->getAlertLevel() : OOStationAlertLevel{}) == OOStationAlertLevel::kRed);
		if (station != nullptr)  station->decreaseAlertLevel();
		OO_CHECK((station != nullptr ? station->getAlertLevel() : OOStationAlertLevel{}) == OOStationAlertLevel::kYellow);

		// A target at yellow or red alert is a hostile one; none, or green, is not.
		OO_CHECK(!(station != nullptr ? station->hasHostileTarget() : false));
		TestVisitor *intruder = MakeVisitor("intruder");
		SetPrimaryTarget3(station, intruder);
		OO_CHECK((station != nullptr ? station->hasHostileTarget() : false));
		if (station != nullptr)  station->setAlertLevel(OOStationAlertLevel::kGreen, false);
		OO_CHECK(!(station != nullptr ? station->hasHostileTarget() : false));
	}
}


OO_TEST(slice3DamageAndMovement)
{
	{
		SetUp();
		TestStation *station = MakeStation("target");
		TestVisitor *friendly = MakeVisitor("defender");
		if (friendly != nullptr)  friendly->setGroup((station != nullptr ? station->group() : (OOShipGroup *)nullptr));

		// Friendly fire is ignored.
		SetEnergy3(station, 500);
		if (station != nullptr)  station->takeEnergyDamage(100, friendly, friendly, "");
		OO_CHECK(Energy3(station) == 500);

		// A station that is not the main one is moved like a ship.
		if (station != nullptr)  station->setVelocity(kZeroVector);
		if (station != nullptr)  station->adjustVelocity(make_vector(1, 0, 0));
		OO_CHECK(vector_equal((station != nullptr ? station->getVelocity() : Vector{}), make_vector(1, 0, 0)));
	}
}


OO_TEST(slice3PatrolsAndQueues)
{
	{
		SetUp();
		TestStation *station = MakeStation("base");
		SetLastPatrolReport3(station, -1000);
		if (station != nullptr)  station->acceptPatrolReportFrom(nullptr);
		OO_CHECK(LastPatrolReport3(station) == (UNIVERSE != nullptr ? UNIVERSE->getTime() : 0.0));
		OO_CHECK((station != nullptr ? station->currentlyInDockingQueues() : unsigned{}) == 0 && (station != nullptr ? station->currentlyInLaunchingQueues() : unsigned{}) == 0);
	}
}


// From C++ (after the conversion): the members, and the ship's virtual members reaching the station's.
OO_TEST(slice3MembersFromCxx)
{
	{
		SetUp();
		TestStation *station = MakeStation("member3");
		StationEntity *part = station;
		part->setAlertLevel(OOStationAlertLevel::kRed, false);
		OO_CHECK(part->getAlertLevel() == OOStationAlertLevel::kRed && (station != nullptr ? station->getAlertLevel() : OOStationAlertLevel{}) == OOStationAlertLevel::kRed);
		part->setAllegiance(std::string("neutral"));
		OO_CHECK(part->getAllegiance() == std::optional<std::string>("neutral"));
		ShipEntity *asShip = part;
		SetPrimaryTarget3(station, MakeVisitor("foe"));
		OO_CHECK(asShip->hasHostileTarget());		// virtual: the station's
		TestVisitor *friendly = MakeVisitor("friend");
		if (friendly != nullptr)  friendly->setGroup((station != nullptr ? station->group() : (OOShipGroup *)nullptr));
		SetEnergy3(station, 500);
		Entity *asEntity = part;
		asEntity->takeEnergyDamage(100, friendly, friendly, "");
		OO_CHECK(Energy3(station) == 500);			// friendly fire, through the root's virtual
	}
}


// --- NPC launchers
// ------------------------------------------------------- The test's station
// has no docks (its virtual dock is only recorded), so every launcher takes its
// "no launch docks" path: nothing is made, queued or counted, and the station's
// universe is never asked for a ship.

namespace {

unsigned DefendersLaunched4(StationEntity *s)	{ return s->defenders_launched; }
unsigned ScavengersLaunched4(StationEntity *s)	{ return s->scavengers_launched; }
unsigned DockedShuttles4(StationEntity *s)		{ return s->docked_shuttles; }

}	// namespace


OO_TEST(slice4LaunchersWithoutLaunchDock)
{
	{
		SetUp();
		TestStation *station = MakeStation("launcher", { { "max_police", oo::PList(4) }, { "max_defense_ships", oo::PList(4) } });
		SetPrimaryTarget3(station, MakeVisitor("quarry"));
		OO_CHECK(!(station != nullptr ? station->hasLaunchDock() : false));
		const unsigned defenders = DefendersLaunched4(station);
		const unsigned scavengers = ScavengersLaunched4(station);
		const unsigned shuttles = DockedShuttles4(station);

		OO_CHECK((station != nullptr ? station->launchIndependentShip("trader") : oo::PList()).isNull());
		OO_CHECK(oo::EntitiesIn((station != nullptr ? station->launchPolice() : oo::PList())).empty());
		OO_CHECK((station != nullptr ? station->launchDefenseShip() : (::ShipEntity *)nullptr) == nullptr);
		OO_CHECK((station != nullptr ? station->launchScavenger() : (::ShipEntity *)nullptr) == nullptr);
		OO_CHECK((station != nullptr ? station->launchMiner() : (::ShipEntity *)nullptr) == nullptr);
		OO_CHECK((station != nullptr ? station->launchPirateShip() : (::ShipEntity *)nullptr) == nullptr);
		OO_CHECK((station != nullptr ? station->launchShuttle() : (::ShipEntity *)nullptr) == nullptr);
		OO_CHECK((station != nullptr ? station->launchEscort() : (::ShipEntity *)nullptr) == nullptr);
		OO_CHECK((station != nullptr ? station->launchPatrol() : (::ShipEntity *)nullptr) == nullptr);
		if (station != nullptr)  station->launchShipWithRole("shuttle");

		OO_CHECK(DefendersLaunched4(station) == defenders && ScavengersLaunched4(station) == scavengers && DockedShuttles4(station) == shuttles);
		OO_CHECK((station != nullptr ? station->countOfShipsInLaunchQueueWithPrimaryRole("police") : unsigned{}) == 0 && (station != nullptr ? station->currentlyInLaunchingQueues() : unsigned{}) == 0);
		OO_CHECK((station != nullptr ? station->status() : OOEntityStatus{}) == OOEntityStatus::kInFlight);
	}
}


// The launchers stay reachable by name (AI and scripts send them by name); the
// by-name table answers them.
OO_TEST(slice4LaunchersAnswerTheirSelectors)
{
	{
		SetUp();
		TestStation *station = MakeStation("selectors");
		OO_CHECK(oo::EntityRespondsToName(station, "launchIndependentShip:") && oo::EntityRespondsToName(station, "launchShipWithRole:"));
		OO_CHECK(oo::EntityRespondsToName(station, "launchPolice") && oo::EntityRespondsToName(station, "launchDefenseShip"));
		OO_CHECK(oo::EntityRespondsToName(station, "launchScavenger") && oo::EntityRespondsToName(station, "launchMiner"));
		OO_CHECK(oo::EntityRespondsToName(station, "launchPirateShip") && oo::EntityRespondsToName(station, "launchShuttle"));
		OO_CHECK(oo::EntityRespondsToName(station, "launchEscort") && oo::EntityRespondsToName(station, "launchPatrol"));
	}
}


// From C++: the members, which the selectors forward to.
OO_TEST(slice4MembersFromCxx)
{
	{
		SetUp();
		TestStation *station = MakeStation("member4");
		SetPrimaryTarget3(station, MakeVisitor("mark"));
		StationEntity *part = station;
		const unsigned defenders = DefendersLaunched4(station);
		OO_CHECK(part->launchIndependentShip("trader").isNull());
		OO_CHECK(oo::EntitiesIn(part->launchPolice()).empty());
		OO_CHECK(part->launchDefenseShip() == nullptr && part->launchScavenger() == nullptr && part->launchMiner() == nullptr);
		OO_CHECK(part->launchPirateShip() == nullptr && part->launchShuttle() == nullptr && part->launchEscort() == nullptr);
		OO_CHECK(part->launchPatrol() == nullptr);
		part->launchShipWithRole("escort");
		OO_CHECK(DefendersLaunched4(station) == defenders && part->currentlyInLaunchingQueues() == 0);
	}
}


// --- The script engine's class questions
// ---------------------------------------

// What the engine asks a station by selector: its JS class is the Station
// class, not the Ship class it inherits, both through the root and from its
// C++ part.
OO_TEST(stationAnswersTheStationJSClass)
{
	{
		SetUp();
		TestStation *station = MakeStation("jsclass");
		// The classes are registered by their Init functions, parents first, as the engine's
		// start registers them.
		JSContext *context = OOJSAcquireContext();
		JSValue global = JS_GetGlobalObject(context);
		InitOOJSEntity(context, global);
		InitOOJSShip(context, global);
		InitOOJSStation(context, global);
		JS_FreeValue(context, global);
		OOJSRelinquishContext(context);
		const JSClassID stationClass = JSStationClassID();
		OO_CHECK(stationClass != 0 && stationClass != JSShipClassID());

		OO_CHECK(OOJSEntityJSClassName(station) == std::optional<std::string>("Station"));
		JSClassID jsClass = OOJSEntityJSClassID(station);
		OO_CHECK(jsClass == stationClass);

		ShipEntity *asShip = station;
		OO_CHECK(asShip->jsClassName() == std::optional<std::string>("Station"));
		jsClass = asShip->jsClassID();
		OO_CHECK(jsClass == stationClass);
	}
}


OO_TEST_MAIN()
