/*	test_OOECMBlastEntity.mm
	Unit tests for OOECMBlastEntity (src/Core/Entities/OOECMBlastEntity.h), the invisible entity
	that sends a ship's ECM pulses: bead oo-ryhi, a leaf of the Entities seam (proposed ADR-0056,
	amendment oo-bj8 item 12).

	The entity reads Universe, so the test links the whole game but main (['*']) and uses a Universe
	that was never initialised, subclassed to record -removeEntity: and the range searches the
	pulses make (it finds no ship, so no script event is sent). The firing ship was a plain entity
	(the blast messaged it only as one: -position, -status, its weak reference); since bead oo-9ht.144 the
	blast calls the C++ ship's members, so it is a C++ ship under its object, never set up. The expectations were
	written against the Objective-C API and run on the unconverted class first (but for "no blast
	from nil", which crashed there in the Entity facade's -dealloc of an entity whose -init never
	ran, bead oo-s6ic6): no blast from nil; a blast is a no-draw effect at the ship's position; four
	pulses half a second apart, a quarter of the scanner range wider each, then it removes itself;
	a dead or deallocated ship ends it at once; it is an ECM blast and the ship is not (-isECMBlast,
	which nothing sent, went with its bridge in bead oo-9ht.75; the check asks the C++ member). The
	blasts are made through the one helper below, the only line the conversion ported: the blast is
	now a C++ entity whose Objective-C object is the Entity facade oo::NewEntityFacade made.
	Run: bash tools/check-core-tests.sh
*/

#include "OOECMBlastEntity.h"
#include "Universe.h"
#include "ShipEntity.h"	// the ship is C++ (bead oo-9ht.144)
#include "PlayerEntity.h"	// the stand-in PLAYER (bead oo-vdw34)

#include "oo_test.hpp"

#include <vector>


// main.mm defines the debug flags, and the test has its own main.
#ifndef NDEBUG
uint32_t gDebugFlags = 0;
#endif

extern PlayerEntity *gOOPlayer;
extern Universe *gSharedUniverse;


// UNIVERSE: never initialised; records what is removed and what is searched for.
class TestUniverse : public Universe
{
public:
	Entity					*_removed = {};
	std::vector<double>		*_ranges = {};
	Entity					*_searchedFrom = {};

	bool removeEntity(Entity *entity) override	// the C++ entity since bead oo-9ht.39.26; the record is its object, as before
	{
		_removed = entity;
		return YES;
	}
	std::vector<oo::EntityHold> findEntitiesMatchingPredicate(EntityFilterPredicate /*predicate*/, void * /*parameter*/, double range, Entity *entity) override	// held C++ entities since bead oo-9ht.39.26	// the reference's C++ entity
	{
		_ranges->push_back(range);
		_searchedFrom = entity;
		return {};
	}
};


extern ooscript::Context gOOJSMainThreadContext;	// the engine's (OOJavaScriptEngine.mm)


namespace {

TestUniverse *sUniverse = nil;
std::vector<double> sRanges;


// PLAYER (bead oo-vdw34): the debug build asserts it is set (OOGetPlayer()), so the entities' positions,
// which read it, have a player whose viewpoint is the origin: the camera-relative positions are the
// release build's with no player (the origin's). Never released, as the player is not.
class TestPlayer : public PlayerEntity
{
public:
	HPVector viewpointPosition() override	{ return kZeroHPVector; }
};


void SetUpTestPlayer()
{
	static TestPlayer *player = nullptr;
	if (player == nullptr)
	{
		oo::Ref<TestPlayer> made = oo::makeRef<TestPlayer>();
		{
			oo::AutoreleaseScope scope;	// was @autoreleasepool (oo-31u.6)
			oo::RetainEntity(oo::MadeEntity(made));	// +1, as PlayerEntity::sharedPlayer() makes the game's
		}
		player = made.get();
	}
	gOOPlayer = player;
}


void SetUp()
{
	if (sUniverse == nil)
	{
		sUniverse = new TestUniverse();	// never released
	}
	sRanges.clear();
	sUniverse->_ranges = &sRanges;
	sUniverse->_removed = nil;
	sUniverse->_searchedFrom = nil;
	gSharedUniverse = sUniverse;
	SetUpTestPlayer();
	// The ship's -dealloc sends its (absent) scripts entityDestroyed in a request on the main
	// thread's context, so there is one, with nothing in it (the ship stand-in is C++ since bead
	// oo-9ht.144, as test_StationEntity's ships are).
	if (gOOJSMainThreadContext == nullptr)  gOOJSMainThreadContext = ooscript::newContext(ooscript::newRuntime(8u * 1024u * 1024u), 8192);
}


// A ship: C++ since bead oo-9ht.144 (the blast calls its members), under its object
// (oo::NewEntityFacade, autoreleased as the plain entity was), never set up.
Entity *Ship()
{
	Entity *ship = oo::MadeEntity(oo::makeRef<::ShipEntity>());
	ship->setPosition(make_HPvector(10, 20, 30));
	ship->setStatus(STATUS_IN_FLIGHT);
	return ship;
}


// --- How the test makes a blast (ported by the conversion), and nothing else ---------------------

Entity *Blast(Entity *ship)	{ return oo::MadeEntity(OOECMBlastEntity::initFromShip(oo::ToShip(ship))); }


// What -[Entity isECMBlast] answered, from the C++ member (bead oo-9ht.75 deleted the category).
bool IsECMBlast(Entity *entity)
{
	OOECMBlastEntity *blast = dynamic_cast<OOECMBlastEntity *>(entity);
	return blast != nullptr && blast->isECMBlast();
}

// --------------------------------------------------------------------------------------------------

}	// namespace


OO_TEST(noShipNoBlast)
{
	{
		oo::AutoreleaseScope scope;	// was @autoreleasepool (oo-31u.6)
		SetUp();
		OO_CHECK(Blast(nil) == nil);
	}
}


OO_TEST(blastAtTheShip)
{
	{
		oo::AutoreleaseScope scope;	// was @autoreleasepool (oo-31u.6)
		SetUp();
		Entity *ship = Ship();
		Entity *blast = Blast(ship);
		OO_CHECK(blast != nil);
		OO_CHECK(HPvector_equal(blast->getPosition(), make_HPvector(10, 20, 30)));
		OO_CHECK(blast->status() == STATUS_EFFECT && blast->getScanClass() == CLASS_NO_DRAW);
		OO_CHECK(blast->owner() == nil);
		OO_CHECK(IsECMBlast(blast) && !IsECMBlast(ship));
	}
}


OO_TEST(fourPulsesThenGone)
{
	{
		oo::AutoreleaseScope scope;	// was @autoreleasepool (oo-31u.6)
		SetUp();
		Entity *ship = Ship();
		Entity *blast = Blast(ship);

		blast->update(0.25);
		OO_CHECK(sRanges.empty() && sUniverse->_removed == nil);
		blast->update(0.25);
		OO_CHECK(sRanges.size() == 1 && sRanges[0] == SCANNER_MAX_RANGE * 0.25);
		OO_CHECK(sUniverse->_searchedFrom == blast);
		blast->update(0.5);
		blast->update(0.5);
		OO_CHECK(sRanges.size() == 3 && sRanges[1] == SCANNER_MAX_RANGE * 0.5 && sRanges[2] == SCANNER_MAX_RANGE * 0.75);
		OO_CHECK(sUniverse->_removed == nil);
		blast->update(0.5);
		OO_CHECK(sRanges.size() == 4 && sRanges[3] == SCANNER_MAX_RANGE);
		OO_CHECK(sUniverse->_removed == blast);
	}
}


OO_TEST(deadShipEndsIt)
{
	{
		oo::AutoreleaseScope scope;	// was @autoreleasepool (oo-31u.6)
		SetUp();
		Entity *ship = Ship();
		Entity *blast = Blast(ship);
		ship->setStatus(STATUS_DEAD);
		blast->update(0.5);
		OO_CHECK(sRanges.empty() && sUniverse->_removed == blast);
	}

	Entity *blast = nil;
	{
		oo::AutoreleaseScope scope;	// was @autoreleasepool (oo-31u.6)
		SetUp();
		Entity *ship = oo::RetainEntity(oo::MadeEntity(oo::makeRef<::ShipEntity>()));	// a ship (bead oo-9ht.144)
		blast = oo::RetainEntity(Blast(ship));
		oo::ReleaseEntity(ship);		// the blast holds it weakly
	}
	{
		oo::AutoreleaseScope scope;	// was @autoreleasepool (oo-31u.6)
		blast->update(0.5);
		OO_CHECK(sRanges.empty() && sUniverse->_removed == blast);
		oo::ReleaseEntity(blast);
	}
}


OO_TEST_MAIN()
