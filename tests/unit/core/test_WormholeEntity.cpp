/*	test_WormholeEntity.mm
	Unit tests for WormholeEntity (src/Core/Entities/WormholeEntity.h), the witchspace wormholes
	ships leave behind: bead oo-z55j, a leaf of the Entities seam with a facade (proposed ADR-0056,
	amendments oo-bj8 item 12 and oo-0mxi).

	The entity reads Universe and PLAYER, so the test links the whole game but main (['*']) and
	uses a Universe that was never initialised, subclassed to answer the current system, the system
	names and a real system description manager (with the coordinates of the systems the test
	uses) and the clock format, with no sun, and to record what is removed; PLAYER is an entity that answers the galaxy, the clock,
	its galactic coordinates and its forward vector; the ship that opens a wormhole is a plain
	entity of the mass the test sets (a C++ ship under its object, never set up, since bead
	oo-9ht.144). The expectations were written against the Objective-C API
	and run on the unconverted class first: a wormhole made by a ship is a no-mass-yet effect of
	the wormhole scan class whose size, expiry and arrival follow from the ship's mass and the
	distance; one made from a saved dictionary reads its systems, times (crossed times fixed),
	position and misjump back, and -getDict writes them; the misjump setters move the exit and the
	arrival; the scan state; who can collide with it; -update: shrinks nothing at no mass, hides it
	and removes it once it has expired; -suckInShip: refuses a missing ship, one already leaving,
	another system and an expired wormhole; -disgorgeShips moves a wormhole that held the player
	behind the player; and the description. Masses and distances are set through the one helper
	below. The callers made it with alloc/initWormholeTo:fromShip: and alloc/initWithDict:, which
	the conversion kept on the facade; bead oo-9ht.112 deleted the facade (standing approval
	oo-9n5p9): the cases make the C++ wormhole and its Objective-C object (oo::NewEntityFacade) and
	ask the C++ class, and the facade case pins the new crossing: its object is the root Entity's.
	Run: bash tools/check-core-tests.sh
*/

#include "WormholeEntity.h"
#include "PlayerEntity.h"	// PLAYER is C++ (bead oo-9ht.177)
#include "EntityOOJavaScriptExtensions.h"
#include "OOJSWormhole.h"
#include "OOSystemDescriptionManager.h"
#include "OODescription.h"
#include "Universe.h"

#include "oo_test.hpp"
#include "oofnd/PListGet.hpp"

#include <cmath>
#include <string>


// main.mm defines the debug flags, and the test has its own main.
#ifndef NDEBUG
uint32_t gDebugFlags = 0;
#endif

class PlayerEntity;
extern PlayerEntity *gOOPlayer;
extern Universe *gSharedUniverse;


class TestPlayer : public PlayerEntity	// C++ since bead oo-9ht.177 deleted the Objective-C player
{
public:
	double		_clock = {};
	NSPoint		_coordinates = {};

	HPVector viewpointPosition() override	{ return kZeroHPVector; }
	OOGalaxyID galaxyNumber() override	{ return 0; }
	double clockTime() override	{ return _clock; }
	double clockTimeAdjusted() override	{ return _clock; }
	NSPoint getGalaxy_coordinates() override	{ return _coordinates; }
	Vector forwardVector() override	{ return make_vector(0, 0, 1); }
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




// An effect, for the collision test (an Objective-C subclass until bead oo-j12i2; a C++ one
// overriding the member its selector became).
class TestEffect : public Entity
{
public:
	bool isEffect() override	{ return true; }
};


// UNIVERSE: never initialised; answers the system and the system manager, and records removals.
class TestUniverse : public Universe
{
public:
	OOSystemID &_system = systemID;	// the universe's own state, which its getter answers (bead oo-ql9rn)
	Entity			*_removed = {};

	std::optional<std::string> getSystemName(OOSystemID sys, OOGalaxyID /*gnum*/) override	{ return "System " + std::to_string(sys); }	// getSystemName(sys) asks it
	bool removeEntity(Entity *entity) override	// the C++ entity since bead oo-9ht.39.26; the record is its object, as before
	{
		_removed = entity;
		return YES;
	}
};


extern ooscript::Context gOOJSMainThreadContext;	// the engine's (OOJavaScriptEngine.mm)


namespace {

OOSystemDescriptionManager *sManager = nullptr;

}


namespace {

TestUniverse *sUniverse = nil;
TestPlayer *sPlayer = nullptr;


void SetUp()
{
	if (sUniverse == nil)
	{
		sUniverse = new TestUniverse();	// never released
		sPlayer = NewTestPlayer<TestPlayer>();
		// Systems 7 at (10, 20) and 9 at (13, 24) of galaxy 0: 5 light-year units apart, 2.0 LY.
		oo::Ref<OOSystemDescriptionManager> manager = oo::makeRef<OOSystemDescriptionManager>();
		manager->setProperties(oo::PList(oo::PList::Dict{ { "coordinates", oo::PList("10 20") } }), "0 7");
		manager->setProperties(oo::PList(oo::PList::Dict{ { "coordinates", oo::PList("13 24") } }), "0 9");
		manager->buildRouteCache();	// fills the coordinates cache
		sManager = manager.leakRef();	// never released
		// What -systemManager and -cxx_descriptionForKey: answered: the universe's own manager and
		// descriptions (the game's clock format, for the description's arrival time; bead oo-ql9rn).
		sUniverse->systemManager = oo::Ref<OOSystemDescriptionManager>(sManager);
		sUniverse->_descriptions = oo::PList(oo::PList::Dict{ { "clock-format", oo::PList("%07d:%02d:%02d:%02d") } });
	}
	sUniverse->_system = 7;
	sUniverse->_removed = nil;
	sPlayer->_clock = 1000.0;
	sPlayer->_coordinates = NSMakePoint(10, 20);
	gSharedUniverse = sUniverse;
	gOOPlayer = sPlayer;
	// The ship's -dealloc sends its (absent) scripts entityDestroyed in a request on the main
	// thread's context, so there is one, with nothing in it (the ship stand-in is C++ since bead
	// oo-9ht.144, as test_StationEntity's ships are).
	if (gOOJSMainThreadContext == nullptr)  gOOJSMainThreadContext = ooscript::newContext(ooscript::newRuntime(8u * 1024u * 1024u), 8192);
}


// --- Ivars the test sets and reads, and nothing else ----------------------------------------------

void SetMass(Entity *e, GLfloat mass)		{ e->mass = mass; }

// --------------------------------------------------------------------------------------------------


bool Near(double a, double b)
{
	return std::fabs(a - b) < 1e-3 * std::fmax(1.0, std::fabs(b));
}


// A ship: C++ since bead oo-9ht.144 (the wormhole calls its members), under its object
// (oo::NewEntityFacade, autoreleased as the plain entity was), never set up.
Entity *Ship(GLfloat mass)
{
	Entity *ship = oo::MadeEntity(oo::makeRef<::ShipEntity>());
	SetMass(ship, mass);
	ship->setPosition(make_HPvector(1, 2, 3));
	return ship;
}


// alloc/init.../autorelease: a new C++ wormhole, owned by its autoreleased Objective-C object.
WormholeEntity *ToNine(Entity *ship)
{
	oo::Ref<WormholeEntity> wh = oo::makeRef<WormholeEntity>();
	(void)oo::MadeEntity(wh);
	wh->initWormholeTo(9, oo::ToShip(ship));
	return wh.get();
}


WormholeEntity *FromDict(const oo::PList &dict)
{
	oo::Ref<WormholeEntity> wh = oo::makeRef<WormholeEntity>();
	(void)oo::MadeEntity(wh);
	wh->initWithDict(dict);
	return wh.get();
}


oo::PList Saved(double expiry = 1500.0)
{
	return oo::PList(oo::PList::Dict{
		{ "origin_id", oo::PList(7) },
		{ "dest_id", oo::PList(9) },
		{ "expiry_time", oo::PList(expiry) },
		{ "arrival_time", oo::PList(2000.0) },
		{ "position", oo::PList(oo::PList::Array{ oo::PList(4.0), oo::PList(5.0), oo::PList(6.0) }) },
		{ "misjump", oo::PList(true) },
	});
}

}	// namespace


OO_TEST(madeByShip)
{
	{
		SetUp();
		WormholeEntity *wh = ToNine(Ship(1000.0f));
		OO_CHECK(wh != nil && dynamic_cast<WormholeEntity *>(static_cast<Entity *>(wh)) != nullptr && wh->getIsWormhole());
		OO_CHECK(wh->status() == STATUS_EFFECT && wh->getScanClass() == CLASS_WORMHOLE);
		OO_CHECK(wh->getOrigin() == 7 && wh->getDestination() == 9);
		NSPoint o = wh->originCoordinates(), d = wh->destinationCoordinates();
		OO_CHECK(o.x == 10 && o.y == 20 && d.x == 13 && d.y == 24);
		OO_CHECK(HPvector_equal(wh->getPosition(), make_HPvector(1, 2, 3)));
		// No player mass (not the player): 200000 tonnes.
		OO_CHECK(Near(wh->collisionRadius(), 0.5 * M_PI * std::pow(200000.0, 1.0 / 3.0)));
		const double distance = distanceBetweenPlanetPositions(10, 20, 13, 24);
		OO_CHECK(Near(wh->travelTime(), distance * distance * 3600));
		OO_CHECK(Near(wh->arrivalTime(), 1000.0 + distance * distance * 3600));
		OO_CHECK(wh->estimatedArrivalTime() == wh->arrivalTime());
		OO_CHECK(Near(wh->expiryTime(), 1000.0 + 200000.0 / WORMHOLE_SHRINK_RATE));
		OO_CHECK(!wh->withMisjump() && !wh->isScanned() && wh->scanInfo() == WH_SCANINFO_NONE);
		OO_CHECK(wh->exitSpeed() == 50.0);
		OO_CHECK(wh->canCollide());
		OO_CHECK(wh->getShipsInTransit() == oo::PList(oo::PList::Array{}));
	}
}


OO_TEST(misjump)
{
	{
		SetUp();
		WormholeEntity *wh = ToNine(Ship(1000.0f));
		const double arrival = wh->arrivalTime();
		const double distance = distanceBetweenPlanetPositions(10, 20, 13, 24);
		wh->setMisjump();
		OO_CHECK(wh->withMisjump());
		OO_CHECK(Near(wh->arrivalTime(), arrival - distance * distance * 900));
		NSPoint d = wh->destinationCoordinates();
		OO_CHECK(d.x == 11.5 && d.y == 22);
		wh->setMisjump();	// only once
		OO_CHECK(Near(wh->arrivalTime(), arrival - distance * distance * 900));

		WormholeEntity *ranged = ToNine(Ship(1000.0f));
		ranged->setMisjumpWithRange(0.25f);
		OO_CHECK(ranged->withMisjump() && ranged->misjumpRange() == 0.25f);
		OO_CHECK(Near(ranged->arrivalTime(), arrival - (distance * 0.75) * (distance * 0.75) * 3600.0));
		d = ranged->destinationCoordinates();
		OO_CHECK(Near(d.x, 10 * 0.75 + 13 * 0.25) && Near(d.y, 20 * 0.75 + 24 * 0.25));

		WormholeEntity *unsafe = ToNine(Ship(1000.0f));
		unsafe->setMisjumpWithRange(2.0f);
		OO_CHECK(unsafe->misjumpRange() == 0.5f);
	}
}


OO_TEST(saved)
{
	{
		SetUp();
		WormholeEntity *wh = FromDict(Saved());
		OO_CHECK(wh->getOrigin() == 7 && wh->getDestination() == 9);
		OO_CHECK(wh->expiryTime() == 1500.0 && wh->arrivalTime() == 2000.0 && wh->estimatedArrivalTime() == 2000.0);
		OO_CHECK(HPvector_equal(wh->getPosition(), make_HPvector(4, 5, 6)));
		OO_CHECK(wh->withMisjump() && wh->isScanned() && wh->scanInfo() == WH_SCANINFO_SCANNED);
		OO_CHECK(!wh->canCollide());		// no mass

		oo::PList dict = wh->getDict();
		OO_CHECK(dict.get<int>("origin_id") == 7 && dict.get<int>("dest_id") == 9);
		OO_CHECK(dict.get<double>("expiry_time") == 1500.0 && dict.get<double>("arrival_time") == 2000.0);
		OO_CHECK(dict.get<bool>("misjump"));
		OO_CHECK(dict.get<std::string>("origin_coords") == "10.000000 20.000000" && dict.get<std::string>("dest_coords") == "13.000000 24.000000");
		OO_CHECK(dict.find("ships") != nullptr && dict.find("ships")->count() == 0);

		// Crossed times: the expiry is a second before the arrival.
		WormholeEntity *fixed = FromDict(Saved(2500.0));
		OO_CHECK(fixed->expiryTime() == 1999.0);
	}
}


OO_TEST(scanning)
{
	{
		SetUp();
		WormholeEntity *wh = ToNine(Ship(1000.0f));
		wh->setScannedAt(1234.0);
		OO_CHECK(wh->isScanned() && wh->scanTime() == 1234.0 && wh->scanInfo() == WH_SCANINFO_SCANNED);
		wh->setScannedAt(5678.0);
		OO_CHECK(wh->scanTime() == 1234.0);
		wh->setScanInfo(WH_SCANINFO_DESTINATION);
		OO_CHECK(wh->scanInfo() == WH_SCANINFO_DESTINATION);
		wh->setExitSpeed(75.0);
		OO_CHECK(wh->exitSpeed() == 75.0);
	}
}


OO_TEST(collisions)
{
	{
		SetUp();
		WormholeEntity *wh = ToNine(Ship(1000.0f));
		OO_CHECK(wh->canCollide());
		sUniverse->_system = 8;
		OO_CHECK(!wh->canCollide());
		sUniverse->_system = 7;
		sPlayer->_coordinates = NSMakePoint(11, 20);
		OO_CHECK(!wh->canCollide());
		sPlayer->_coordinates = NSMakePoint(10, 20);

		OO_CHECK(wh->checkCloseCollisionWith(Ship(1.0f)));
		OO_CHECK(!wh->checkCloseCollisionWith(oo::MadeEntity(oo::makeRef<TestEffect>())));
	}
}


OO_TEST(update)
{
	{
		SetUp();
		WormholeEntity *saved = FromDict(Saved());
		saved->update(0.1);
		OO_CHECK(saved->getScanClass() == CLASS_NO_DRAW);	// no mass
		OO_CHECK(sUniverse->_removed == nil);
		sPlayer->_clock = 1600.0;						// past its expiry
		saved->update(0.1);
		OO_CHECK(sUniverse->_removed == saved);

		sPlayer->_clock = 1000.0;
		WormholeEntity *wh = ToNine(Ship(1000.0f));
		wh->update(1.0);
		OO_CHECK(wh->getScanClass() == CLASS_WORMHOLE);
		OO_CHECK(Near(wh->collisionRadius(), 0.5 * M_PI * std::pow(200000.0 - WORMHOLE_SHRINK_RATE, 1.0 / 3.0)));
	}
}


OO_TEST(suckInRefused)
{
	{
		SetUp();
		WormholeEntity *wh = ToNine(Ship(1000.0f));
		OO_CHECK(!wh->suckInShip(nullptr));
		Entity *leaving = Ship(10.0f);
		leaving->setStatus(STATUS_ENTERING_WITCHSPACE);
		OO_CHECK(!wh->suckInShip(oo::ToShip(leaving)));
		sUniverse->_system = 8;
		OO_CHECK(!wh->suckInShip(oo::ToShip(Ship(10.0f))));
		sUniverse->_system = 7;
		sPlayer->_clock = 1000.0 + 200000.0 / WORMHOLE_SHRINK_RATE + 1.0;	// expired
		OO_CHECK(!wh->suckInShip(oo::ToShip(Ship(10.0f))));
		OO_CHECK(wh->getShipsInTransit() == oo::PList(oo::PList::Array{}));
	}
}


OO_TEST(disgorgeWithPlayer)
{
	{
		SetUp();
		WormholeEntity *wh = ToNine(Ship(1000.0f));
		sPlayer->setPosition(make_HPvector(100, 0, 0));
		wh->disgorgeShips();		// no ships, no player: it stays
		OO_CHECK(HPvector_equal(wh->getPosition(), make_HPvector(1, 2, 3)));
		wh->setContainsPlayer(YES);
		wh->disgorgeShips();
		OO_CHECK(HPvector_equal(wh->getPosition(), make_HPvector(100, 0, -500)));
		wh->setExitPosition(make_HPvector(7, 7, 7));
		wh->disgorgeShips();		// once only
		OO_CHECK(HPvector_equal(wh->getPosition(), make_HPvector(7, 7, 7)));
	}
}


OO_TEST(description)
{
	{
		SetUp();
		WormholeEntity *wh = ToNine(Ship(1000.0f));
		const std::string description = oo::EntityDescription(wh);
		OO_CHECK(description.find("destination: System 9 ttl: 50.00s arrival: 0000000:") != std::string::npos);
		wh->setMisjump();
		OO_CHECK(oo::EntityDescription(wh).find("destination: Interstellar Space") != std::string::npos);
	}
}


OO_TEST(facade)
{
	{
		SetUp();
		WormholeEntity *wh = ToNine(Ship(1000.0f));
		// Its Objective-C object is the root's facade since bead oo-9ht.112 (amendment oo-9ht.107).
		Entity *object = wh;
		OO_CHECK(object != nil);	// (and its object's class, the root facade: retired with the facade, bead oo-dpyk8, under oo-9n5p9)
		// A C++ entity (amendment oo-0mxi), not an Objective-C entity's adapter.
		OO_CHECK(dynamic_cast<WormholeEntity *>(object) == wh);
	}
}


// The binding's category, which the facade carries since bead oo-9ht.43: what the engine asks a
// WormholeEntity for by selector is what OOJSWormhole.mm answers.
OO_TEST(jsExtensions)
{
	{
		SetUp();
		WormholeEntity *wh = ToNine(Ship(1000.0f));
		ooscript::ClassDef *jsClass = nullptr, *expectedClass = nullptr;
		ooscript::Object prototype = nullptr, expectedPrototype = nullptr;
		Entity *object = wh;	// what the engine asks (the root's facade since bead oo-9ht.112)
		OOJSEntityGetJSClass(object, &jsClass, &prototype);
		OOJSWormholeGetJSClass(&expectedClass, &expectedPrototype);
		OO_CHECK(jsClass != nullptr && jsClass == expectedClass && prototype == expectedPrototype);
		OO_CHECK(OOJSEntityJSClassName(object) == std::optional<std::string>("Wormhole"));
		OO_CHECK(OOJSEntityIsVisibleToScripts(object) == YES);
	}
}


OO_TEST_MAIN()
