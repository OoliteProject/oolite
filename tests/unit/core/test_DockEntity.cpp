/*	test_DockEntity.mm
	Unit tests for DockEntity (src/Core/Entities/DockEntity.h), a station's dock: slice 1 of its
	slice plan (docs/phases/3-slices/DockEntity.md, bead oo-ao2d), the class shell, which moved the
	dock's state and its flags, geometry and lifecycle into C++ (proposed ADR-0056, amendments
	oo-60fwo and oo-64ako). Bead oo-9ht.180 deleted the Objective-C facade (amendment oo-9ht.180):
	the dock is made in C++ (its object is the ship's facade) and the cases call its members with
	every expected value kept.

	As test_StationEntity's, the dock's object needs the game graph, so the test links the whole
	game but main (['*']) and uses a Universe that was never initialised and a plain entity as
	PLAYER (answering the one player query a dock makes when it aborts its dockings). A dock's
	station is a StationEntity whose virtual dock only records its definition, with the dock added
	as its subentity. The cases test the slice's own units through the Objective-C API, written
	against it and run on the unconverted class first; the cases after "The crossing" pin the C++
	part once it exists.
	Run: bash tools/check-core-tests.sh test_DockEntity
*/

#include "DockEntity.h"
#include "StationEntity.h"
#include "Universe.h"
#include "PlayerEntity.h"

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


// PLAYER: docked at no station (C++ since bead oo-9ht.177 deleted the Objective-C player).
class TestDockPlayer : public PlayerEntity
{
public:
	HPVector viewpointPosition() override			{ return kZeroHPVector; }
	::StationEntity *getTargetDockStation() override	{ return nil; }
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


// A station whose virtual dock is not made (the dock is a shipdata entry). A C++ subclass since bead
// oo-9ht.175 deleted the Objective-C station (amendment oo-9ht.177 item 5).
class TestDockStation : public StationEntity
{
public:
	bool setUpOneStandardSubentity(const oo::PList &/*subentDict*/, bool /*asTurret*/) override	{ return YES; }
};


namespace {

void SetUp()
{
	static Universe *universe = nil;
	if (universe == nil)
	{
		universe = new Universe();	// never released
	}
	gSharedUniverse = universe;
	static TestDockPlayer *player = nullptr;
	if (player == nullptr)  player = NewTestPlayer<TestDockPlayer>();
	gOOPlayer = player;
	// The ship's -dealloc sends its (absent) scripts entityDestroyed in a request on the main
	// thread's context, so there is one, with nothing in it.
	if (gOOJSMainThreadContext == nullptr)  gOOJSMainThreadContext = ooscript::newContext(ooscript::newRuntime(8u * 1024u * 1024u), 8192);
}


// Unpiloted (a crewed ship would ask the universe for a pilot).
oo::PList Definition()
{
	return oo::PList(oo::PList::Dict{ { "unpiloted", oo::PList(true) } });
}


// [[[DockEntity alloc] cxx_initWithKey:definition:] autorelease] until bead oo-9ht.180: the dock
// DockEntity::newDockObject() makes, its object (the ship's facade) autoreleased.
DockEntity *MakeDock(const std::string &key)
{
	::ShipEntity *ship = DockEntity::newDockObject(key, Definition());
	oo::AutoreleaseEntity(ship);
	return static_cast<DockEntity *>(ship);
}


// A dock that is a subentity of a station, so its parent is the station.
DockEntity *MakeDockOfStation(TestDockStation **outStation)
{
	// [[[TestDockStation alloc] cxx_initWithKey:definition:] autorelease] until bead oo-9ht.175: made as
	// StationEntity::newStationObject() makes a station, its object (the ship's facade) autoreleased.
	::ShipEntity *object = oo::ToShip(oo::AutoreleaseEntity(oo::NewShipObject(oo::makeRef<TestDockStation>(), "dock-station", Definition())));
	TestDockStation *station = static_cast<TestDockStation *>(object);
	station->initStationDefaults();
	DockEntity *dock = MakeDock("dock");
	if (object != nullptr)  object->addSubEntity(dock);
	*outStation = station;
	return dock;
}


bool Near(Vector a, Vector b)	{ return std::fabs(a.x - b.x) < 1e-5 && std::fabs(a.y - b.y) < 1e-5 && std::fabs(a.z - b.z) < 1e-5; }


BoundingBox Box(float width, float height)
{
	BoundingBox bb;
	bb.min = make_vector(0, 0, 0);
	bb.max = make_vector(width, height, 1);
	return bb;
}

}	// namespace


// --- Slice 1: the class shell (bead oo-ao2d) --------------------------------------------------------

// The initialiser and the set-up from the definition: a dock is a ship that is not a station, open
// for docking and launching, with empty queues.
OO_TEST(initAndSetUp)
{
	{
		SetUp();
		DockEntity *dock = MakeDock("dock");
		OO_CHECK(dock != nil);
		OO_CHECK((dock != nullptr ? dock->isDock() : false) && (dock != nullptr ? dock->getIsShip() : false) && !(dock != nullptr ? dock->getIsStation() : false) && !(dock != nullptr ? dock->getIsPlayer() : false));
		OO_CHECK((dock != nullptr ? dock->shipDataKey() : std::optional<std::string>()) == std::optional<std::string>("dock"));
		OO_CHECK((dock != nullptr ? dock->allowsDocking() : false) && (dock != nullptr ? dock->allowsLaunching() : false) && !(dock != nullptr ? dock->disallowedDockingCollides() : false));
		OO_CHECK((dock != nullptr ? dock->countOfShipsInDockingQueue() : 0) == 0 && (dock != nullptr ? dock->countOfShipsInLaunchQueue() : 0) == 0);
		OO_CHECK((dock != nullptr ? dock->parentEntity() : (Entity *)nullptr) == nullptr);
	}
}


// The flags: closing to docking or launching aborts what is queued (nothing here).
OO_TEST(flags)
{
	{
		SetUp();
		DockEntity *dock = MakeDock("flags");
		if (dock != nullptr)  dock->setAllowsDocking(NO);
		OO_CHECK(!(dock != nullptr ? dock->allowsDocking() : false));
		if (dock != nullptr)  dock->setAllowsDocking(YES);
		OO_CHECK((dock != nullptr ? dock->allowsDocking() : false));
		if (dock != nullptr)  dock->setAllowsLaunching(NO);
		OO_CHECK(!(dock != nullptr ? dock->allowsLaunching() : false));
		if (dock != nullptr)  dock->setAllowsLaunching(YES);
		OO_CHECK((dock != nullptr ? dock->allowsLaunching() : false));
		if (dock != nullptr)  dock->setDisallowedDockingCollides(YES);
		OO_CHECK((dock != nullptr ? dock->disallowedDockingCollides() : false));
		if (dock != nullptr)  dock->clear();
		OO_CHECK((dock != nullptr ? dock->countOfShipsInDockingQueue() : 0) == 0 && (dock != nullptr ? dock->countOfShipsInLaunchQueue() : 0) == 0);
	}
}


// Off centre: away from the station's axis, or not facing along it.
OO_TEST(isOffCentre)
{
	{
		SetUp();
		DockEntity *dock = MakeDock("centre");
		OO_CHECK(!(dock != nullptr ? dock->isOffCentre() : false));
		if (dock != nullptr)  dock->setPosition(make_HPvector(0, 0, 500));
		OO_CHECK(!(dock != nullptr ? dock->isOffCentre() : false));
		if (dock != nullptr)  dock->setPosition(make_HPvector(3, 3, 0));
		OO_CHECK((dock != nullptr ? dock->isOffCentre() : false));
		if (dock != nullptr)  dock->setPosition(kZeroHPVector);
		Quaternion q = kIdentityQuaternion;
		quaternion_rotate_about_y(&q, M_PI_2);
		if (dock != nullptr)  dock->setOrientation(q);
		OO_CHECK((dock != nullptr ? dock->isOffCentre() : false));
	}
}


// The geometry from the station: a virtual dock takes the station's virtual port; the port's up
// vector turns with a ship whose box is the other way round.
OO_TEST(dimensionsAndPortUpVector)
{
	{
		SetUp();
		TestDockStation *station = nullptr;
		DockEntity *dock = MakeDockOfStation(&station);
		OO_CHECK((dock != nullptr ? dock->parentEntity() : (Entity *)nullptr) == station);

		if (dock != nullptr)  dock->setVirtual();
		if (dock != nullptr)  dock->setDimensionsAndCorridor(NO, YES, NO);
		OO_CHECK(!(dock != nullptr ? dock->allowsDocking() : false) && (dock != nullptr ? dock->disallowedDockingCollides() : false) && !(dock != nullptr ? dock->allowsLaunching() : false));

		// The virtual port is 69 x 69: square, so only the ship's box decides.
		OO_CHECK(Near((dock != nullptr ? dock->portUpVectorForShipsBoundingBox(Box(20, 10)) : Vector{}), make_vector(0, 1, 0)));
		OO_CHECK(Near((dock != nullptr ? dock->portUpVectorForShipsBoundingBox(Box(10, 20)) : Vector{}), make_vector(1, 0, 0)));

		if (dock != nullptr)  dock->setDimensionsAndCorridor(YES, NO, YES);
		OO_CHECK((dock != nullptr ? dock->allowsDocking() : false) && !(dock != nullptr ? dock->disallowedDockingCollides() : false) && (dock != nullptr ? dock->allowsLaunching() : false));
	}
}


// A virtual dock takes no damage.
OO_TEST(virtualDockTakesNoDamage)
{
	{
		SetUp();
		DockEntity *dock = MakeDock("virtual");
		if (dock != nullptr)  dock->setVirtual();
		const double energy = (dock != nullptr ? dock->getEnergy() : 0.0f);
		if (dock != nullptr)  dock->takeEnergyDamage(50.0, nullptr, nullptr, "");
		OO_CHECK((dock != nullptr ? dock->getEnergy() : 0.0f) == energy);
		if (dock != nullptr)  dock->noteTakingDamage(50.0, nullptr, kOODamageTypeEnergy);
		OO_CHECK((dock != nullptr ? dock->getEnergy() : 0.0f) == energy);
		if (dock != nullptr)  dock->drawImmediate(false, false);	// not drawn: nothing to check but that it returns
	}
}


// --- Slice 2: docking guidance (bead oo-9ht.178) ---------------------------------------------------
// These cases reach only the approach queue and the dock's flags: no player, no ship in the
// universe, no clock.

namespace {

// A ship with the universal ID the approach queue keys it by.
ShipEntity *MakeQueuedShip(OOUniversalID shipID)
{
	ShipEntity *ship = oo::ToShip(oo::AutoreleaseEntity(oo::NewShipObject(oo::makeRef<::ShipEntity>(), "queued", Definition())));
	ship->universalID = shipID;
	return ship;
}

}	// namespace


// A dock that is closed rejects a ship outright, before it asks the ship or its script anything
// (the later tests of an open dock call the script engine, which this test does not start).
OO_TEST(canAcceptShipForDocking)
{
	{
		SetUp();
		DockEntity *dock = MakeDock("accept");
		ShipEntity *ship = MakeQueuedShip(11);
		if (dock != nullptr)  dock->setAllowsDocking(NO);
		OO_CHECK((dock != nullptr ? dock->canAcceptShipForDocking(ship) : std::optional<std::string>()) == std::optional<std::string>("DOCK_CLOSED"));
		OO_CHECK(dock->canAcceptShipForDocking(ship) == std::optional<std::string>("DOCK_CLOSED"));
	}
}


// The approach queue: a ship is in it by its ID, and aborting its docking takes it out again.
OO_TEST(approachQueue)
{
	{
		SetUp();
		DockEntity *dock = MakeDock("queue");
		ShipEntity *ship = MakeQueuedShip(12);
		OO_CHECK(!(dock != nullptr ? dock->shipIsInDockingQueue(nullptr) : false) && !(dock != nullptr ? dock->shipIsInDockingQueue(ship) : false));
		dock->shipsOnApproach[12] = std::vector<oo::PList>();
		OO_CHECK((dock != nullptr ? dock->shipIsInDockingQueue(ship) : false));
		OO_CHECK((dock != nullptr ? dock->countOfShipsInDockingQueue() : 0) == 1);
		if (dock != nullptr)  dock->abortDockingForShip(ship);
		OO_CHECK(!(dock != nullptr ? dock->shipIsInDockingQueue(ship) : false));
		OO_CHECK((dock != nullptr ? dock->countOfShipsInDockingQueue() : 0) == 0);
	}
}


// Docking instructions for no ship are none.
OO_TEST(dockingInstructionsForNoShip)
{
	{
		SetUp();
		DockEntity *dock = MakeDock("instructions");
		OO_CHECK((dock != nullptr ? dock->dockingInstructionsForShip(nullptr) : oo::PList()).isNull());
	}
}


// Nothing in the queue: nothing to pull in, and the queue stays empty. The C++ part does the same.
OO_TEST(autoDockEmptyQueue)
{
	{
		SetUp();
		DockEntity *dock = MakeDock("autodock");
		if (dock != nullptr)  dock->autoDockShipsOnApproach();
		OO_CHECK((dock != nullptr ? dock->countOfShipsInDockingQueue() : 0) == 0);
		DockEntity *part = dock;
		part->shipsOnApproach[13] = std::vector<oo::PList>();
		part->autoDockShipsOnApproach();	// no ship has ID 13 in the (never initialised) universe's lookup: dropped
		OO_CHECK(part->countOfShipsInDockingQueue() == 0);
	}
}


// --- Slice 3: the docking corridor and launching (bead oo-9ht.179) -----------------------------
// These cases reach only the launch queue and the checks that refuse a non-ship: no player, no
// script engine, no ship in the universe.

// Not a ship: not in the corridor, not allowed to launch.
OO_TEST(corridorAndLaunchRefuseNoShip)
{
	{
		SetUp();
		DockEntity *dock = MakeDock("refuse");
		OO_CHECK(!(dock != nullptr ? dock->shipIsInDockingCorridor(nullptr) : false));
		OO_CHECK(!(dock != nullptr ? dock->allowsLaunchingOf(nullptr) : false));
		OO_CHECK(!dock->shipIsInDockingCorridor(nil));
		OO_CHECK(!dock->allowsLaunchingOf(nil));
	}
}


// The launch queue: a ship joins at the back, or at the front with priority; nothing joins for no
// ship; aborting the launches empties it.
OO_TEST(launchQueue)
{
	{
		SetUp();
		DockEntity *dock = MakeDock("launchqueue");
		ShipEntity *first = MakeQueuedShip(21);
		ShipEntity *second = MakeQueuedShip(22);
		if (dock != nullptr)  dock->addShipToLaunchQueue(nullptr, NO);
		OO_CHECK((dock != nullptr ? dock->countOfShipsInLaunchQueue() : 0) == 0);
		if (dock != nullptr)  dock->addShipToLaunchQueue(first, NO);
		dock->addShipToLaunchQueue(second, true);
		OO_CHECK((dock != nullptr ? dock->countOfShipsInLaunchQueue() : 0) == 2);
		DockEntity *part = dock;
		OO_CHECK(part->launchQueue[0].get() == second && part->launchQueue[1].get() == first);	// the queue holds the C++ ships (bead oo-9ht.39.19)
		OO_CHECK((first != nullptr ? first->status() : OOEntityStatus{}) == STATUS_DOCKED && (second != nullptr ? second->status() : OOEntityStatus{}) == STATUS_DOCKED);
		OO_CHECK((dock != nullptr ? dock->countOfShipsInLaunchQueueWithPrimaryRole("no-such-role") : 0) == 0);
		part->no_docking_while_launching = YES;
		if (dock != nullptr)  dock->abortAllLaunches();
		OO_CHECK((dock != nullptr ? dock->countOfShipsInLaunchQueue() : 0) == 0 && !part->no_docking_while_launching);
	}
}


// --- The crossing (after the conversion) ---------------------------------------------------------

// A dock's object holds its C++ part, a DockEntity, and from C++ the entity's virtual members reach
// the dock's.
OO_TEST(objCDockPartIsADock)
{
	{
		SetUp();
		DockEntity *dock = MakeDock("crossing");
		DockEntity *part = dock;
		OO_CHECK(part != nullptr);
		OO_CHECK(oo::ToDock(part) == part);

		Entity *asEntity = part;
		OO_CHECK(asEntity->isDock());
		OO_CHECK(part->allowsDocking() && part->allowsLaunching() && !part->disallowedDockingCollides());
		part->setAllowsDocking(false);
		OO_CHECK(!(dock != nullptr ? dock->allowsDocking() : false));
		OO_CHECK(part->countOfShipsInDockingQueue() == 0 && part->countOfShipsInLaunchQueue() == 0);

		part->setVirtual();
		OO_CHECK(part->virtual_dock);
		const double energy = (dock != nullptr ? dock->getEnergy() : 0.0f);
		asEntity->takeEnergyDamage(10.0, nullptr, nullptr, "");
		OO_CHECK((dock != nullptr ? dock->getEnergy() : 0.0f) == energy);
	}
}


OO_TEST_MAIN()
