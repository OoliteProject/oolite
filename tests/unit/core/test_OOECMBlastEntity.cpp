/*	test_OOECMBlastEntity.mm
        Unit tests for OOECMBlastEntity (src/Core/Entities/OOECMBlastEntity.h),
   the invisible entity that sends a ship's ECM pulses.

        The entity reads Universe, so the test links the whole game but main
   (['*']) and uses a Universe that was never initialised, subclassed to record
   -removeEntity: and the range searches the pulses make (it finds no ship, so
   no script event is sent). The blast calls the C++ ship's members, so the
   firing ship is a C++ ship under its object, never set up. The tests cover: no
        blast from nil; a blast is a no-draw effect at the ship's position; four
   pulses half a second apart, a quarter of the scanner range wider each, then
   it removes itself; a dead or deallocated ship ends it at once; it is an ECM
   blast and the ship is not (the check asks the C++ member). The blasts are
   made through the one helper below: the blast is a C++ entity whose object is
   the Entity wrapping it. Run: bash tools/check-core-tests.sh
*/

#include <vector>

#include "OOECMBlastEntity.h"
#include "PlayerEntity.h"  // the stand-in PLAYER
#include "ShipEntity.h"
#include "Universe.h"
#include "oo_test.hpp"
#include "EntityManualRefs.h"  // the tests' manual entity references (T095)

// main.mm defines the debug flags, and the test has its own main.
#ifndef NDEBUG
uint32_t gDebugFlags = 0;
#endif

extern PlayerEntity* gOOPlayer;
extern Universe* gSharedUniverse;

// UNIVERSE: never initialised; records what is removed and what is searched
// for.
class TestUniverse : public Universe {
 public:
  Entity* _removed = {};
  std::vector<double>* _ranges = {};
  Entity* _searchedFrom = {};

  bool removeEntity(Entity* entity) override {
    _removed = entity;
    return true;
  }
  std::vector<oo::EntityHold> findEntitiesMatchingPredicate(
      EntityFilterPredicate /*predicate*/, void* /*parameter*/, double range,
      Entity* entity) override {
    _ranges->push_back(range);
    _searchedFrom = entity;
    return {};
  }
};

extern JSContext*
    gOOJSMainThreadContext;  // the engine's (OOJavaScriptEngine.mm)

namespace {

TestUniverse* sUniverse = nullptr;
std::vector<double> sRanges;

// PLAYER: the debug build asserts it is set (OOGetPlayer()), so the entities'
// positions, which read it, have a player whose viewpoint is the origin: the
// camera-relative positions are the release build's with no player (the
// origin's). Never released, as the player is not.
class TestPlayer : public PlayerEntity {
 public:
  HPVector viewpointPosition() override { return kZeroHPVector; }
};

void SetUpTestPlayer() {
  static TestPlayer* player = nullptr;
  if (player == nullptr) {
    std::shared_ptr<TestPlayer> made = oo::makeShared<TestPlayer>();
    {
      oo::AutoreleaseScope scope;
      oo::RetainEntity(oo::MadeEntity(
          made));  // +1, as PlayerEntity::sharedPlayer() makes the game's
    }
    player = made.get();
  }
  gOOPlayer = player;
}

void SetUp() {
  if (sUniverse == nullptr) {
    sUniverse = new TestUniverse();  // never released
  }
  sRanges.clear();
  sUniverse->_ranges = &sRanges;
  sUniverse->_removed = nullptr;
  sUniverse->_searchedFrom = nullptr;
  gSharedUniverse = sUniverse;
  SetUpTestPlayer();
  // The ship's -dealloc sends its (absent) scripts entityDestroyed in a request
  // on the main thread's context, so there is one, with nothing in it.
  if (gOOJSMainThreadContext == nullptr)
    gOOJSMainThreadContext = JS_NewContext(JS_NewRuntime());
}

// A ship (the blast calls its members), under its object
// (autoreleased), never set up.
Entity* Ship() {
  Entity* ship = oo::MadeEntity(oo::makeShared<::ShipEntity>());
  ship->setPosition(make_HPvector(10, 20, 30));
  ship->setStatus(OOEntityStatus::kInFlight);
  return ship;
}

// --- How the test makes a blast
// ---------------------

Entity* Blast(Entity* ship) {
  return oo::MadeEntity(OOECMBlastEntity::initFromShip(oo::ToShip(ship)));
}

// Whether the entity is an ECM blast, from the C++ member.
bool IsECMBlast(Entity* entity) {
  OOECMBlastEntity* blast = dynamic_cast<OOECMBlastEntity*>(entity);
  return blast != nullptr && blast->isECMBlast();
}

// --------------------------------------------------------------------------------------------------

}  // namespace

OO_TEST(noShipNoBlast) {
  {
    oo::AutoreleaseScope scope;
    SetUp();
    OO_CHECK(Blast(nullptr) == nullptr);
  }
}

OO_TEST(blastAtTheShip) {
  {
    oo::AutoreleaseScope scope;
    SetUp();
    Entity* ship = Ship();
    Entity* blast = Blast(ship);
    OO_CHECK(blast != nullptr);
    OO_CHECK(HPvector_equal(blast->getPosition(), make_HPvector(10, 20, 30)));
    OO_CHECK(blast->status() == OOEntityStatus::kEffect &&
             blast->getScanClass() == OOScanClass::kNoDraw);
    OO_CHECK(blast->owner() == nullptr);
    OO_CHECK(IsECMBlast(blast) && !IsECMBlast(ship));
  }
}

OO_TEST(fourPulsesThenGone) {
  {
    oo::AutoreleaseScope scope;
    SetUp();
    Entity* ship = Ship();
    Entity* blast = Blast(ship);

    blast->update(0.25);
    OO_CHECK(sRanges.empty() && sUniverse->_removed == nullptr);
    blast->update(0.25);
    OO_CHECK(sRanges.size() == 1 && sRanges[0] == SCANNER_MAX_RANGE * 0.25);
    OO_CHECK(sUniverse->_searchedFrom == blast);
    blast->update(0.5);
    blast->update(0.5);
    OO_CHECK(sRanges.size() == 3 && sRanges[1] == SCANNER_MAX_RANGE * 0.5 &&
             sRanges[2] == SCANNER_MAX_RANGE * 0.75);
    OO_CHECK(sUniverse->_removed == nullptr);
    blast->update(0.5);
    OO_CHECK(sRanges.size() == 4 && sRanges[3] == SCANNER_MAX_RANGE);
    OO_CHECK(sUniverse->_removed == blast);
  }
}

OO_TEST(deadShipEndsIt) {
  {
    oo::AutoreleaseScope scope;
    SetUp();
    Entity* ship = Ship();
    Entity* blast = Blast(ship);
    ship->setStatus(OOEntityStatus::kDead);
    blast->update(0.5);
    OO_CHECK(sRanges.empty() && sUniverse->_removed == blast);
  }

  Entity* blast = nullptr;
  {
    oo::AutoreleaseScope scope;
    SetUp();
    Entity* ship = oo::RetainEntity(
        oo::MadeEntity(oo::makeShared<::ShipEntity>()));  // a ship
    blast = oo::RetainEntity(Blast(ship));
    oo::ReleaseEntity(ship);  // the blast holds it weakly
  }
  {
    oo::AutoreleaseScope scope;
    blast->update(0.5);
    OO_CHECK(sRanges.empty() && sUniverse->_removed == blast);
    oo::ReleaseEntity(blast);
  }
}

OO_TEST_MAIN()
