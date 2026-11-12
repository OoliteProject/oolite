/*	test_EntityDisposalReaders.cpp
        Pins the effect of the code that reads a weak reference to an entity
   while it is being disposed (spec 009 design step D2, data-model.md
   "Disposal reader"), on today's ownership code, so that moving the weak
   references to std::weak_ptr (which has expired by then) can be shown not
   to change it.

        The readers are Universe::clearBeacon's two comparisons of the dying
   beacon with the beacon list's head and tail (firstBeacon() == beacon,
   lastBeacon() == beacon). clearBeacon runs from Universe::doRemoveEntity, and
   from disposal only through ensureEntityReallyRemoved, for an entity still
   in the universe; the universe's entity list owns its entities, so the
   list is fixed at removal, while the entity is still owned, and its last
   release changes nothing more. The cases add three beacon waypoints to a
   universe, remove the head and then the tail, and read the list after the
   removal and again after disposal: the universe's dead list keeps a removed
   entity until the update ends and the autorelease pool drains, which is
   its last release.

        The test links the whole game but main (['*']) and uses a Universe that
   was never initialised and a plain player, as test_OOWaypointEntity does;
   the waypoints are made by the C++ factory, as the universe makes them.
   Run: tests/run.sh unit
*/

#include "OOWaypointEntity.h"
#include "PlayerEntity.h"
#include "Universe.h"
#include "oo_test.hpp"

// main.mm defines the debug flags, and the test has its own main.
#ifndef NDEBUG
uint32_t gDebugFlags = 0;
#endif

extern PlayerEntity* gOOPlayer;
extern Universe* gSharedUniverse;

class TestPlayer : public PlayerEntity {
 public:
  HPVector viewpointPosition() override { return kZeroHPVector; }
};

namespace {

// A C++ player, as PlayerEntity::sharedPlayer() makes the game's, retained
// (+1).
TestPlayer* NewTestPlayer() {
  oo::Ref<TestPlayer> player = oo::makeRef<TestPlayer>();
  {
    oo::AutoreleaseScope scope;
    oo::RetainEntity(oo::MadeEntity(player));
  }
  return player.get();
}

// A fresh universe (never initialised) for each case, and the player.
Universe* SetUp() {
  Universe* universe = new Universe();  // never released
  gSharedUniverse = universe;
  static TestPlayer* player = nullptr;
  if (player == nullptr) player = NewTestPlayer();
  gOOPlayer = player;
  return universe;
}

// A beacon waypoint, as the universe makes one, retained by the caller (+1).
Entity* RetainedWaypoint(const std::string& code) {
  oo::AutoreleaseScope scope;
  return oo::RetainEntity(oo::MadeEntity(OOWaypointEntity::waypointWithDictionary(
      oo::PList(oo::PList::Dict{{"beaconCode", oo::PList(code)}}))));
}

}  // namespace

OO_TEST(threeBeaconsMakeTheList) {
  {
    oo::AutoreleaseScope scope;
    Universe* u = SetUp();
    Entity* a = RetainedWaypoint("A");
    Entity* b = RetainedWaypoint("B");
    Entity* c = RetainedWaypoint("C");
    OO_CHECK(oo::EntityIsBeacon(a) && oo::EntityIsBeacon(b) && oo::EntityIsBeacon(c));
    OO_CHECK(u->addEntity(a));
    OO_CHECK(u->addEntity(b));
    OO_CHECK(u->addEntity(c));
    OO_CHECK(u->firstBeacon() == a);
    OO_CHECK(u->lastBeacon() == c);
    u->removeEntity(a);
    u->removeEntity(b);
    u->removeEntity(c);
    oo::ReleaseEntity(a);
    oo::ReleaseEntity(b);
    oo::ReleaseEntity(c);
  }
}

// The head: firstBeacon() == beacon.
OO_TEST(removingTheFirstBeaconMovesTheHeadBeforeItsLastRelease) {
  {
    oo::AutoreleaseScope scope;
    Universe* u = SetUp();
    Entity* a = RetainedWaypoint("A");
    Entity* b = RetainedWaypoint("B");
    Entity* c = RetainedWaypoint("C");
    OO_CHECK(u->addEntity(a) && u->addEntity(b) && u->addEntity(c));

    u->removeEntity(a);  // the universe's hold goes; the test's is the last
    OO_CHECK(a->getUniversalID() == NO_TARGET);
    const Entity* headAfterRemoval = u->firstBeacon();
    const Entity* tailAfterRemoval = u->lastBeacon();
    OO_CHECK(headAfterRemoval == b);  // the head moved to the next beacon
    OO_CHECK(tailAfterRemoval == c);
    OO_CHECK(oo::PrevBeacon(b) == nullptr && oo::NextBeacon(b) == c);
    OO_CHECK(!oo::EntityIsBeacon(a));  // clearBeacon cleared its code

    oo::WeakRef<Entity> removed(a);
    oo::ReleaseEntity(a);  // the test's hold; the universe's dead list keeps it
    {
      oo::AutoreleaseScope frame;
      u->no_update = true;
      u->update(1.0);  // the dead are autoreleased
    }  // the pool drains: the last release, and disposal
    OO_CHECK(removed.get() == nullptr);  // it was disposed
    OO_CHECK(u->firstBeacon() == headAfterRemoval);  // as removal left it
    OO_CHECK(u->lastBeacon() == tailAfterRemoval);

    u->removeEntity(b);
    u->removeEntity(c);
    oo::ReleaseEntity(b);
    oo::ReleaseEntity(c);
  }
}

// The tail: lastBeacon() == beacon.
OO_TEST(removingTheLastBeaconMovesTheTailBeforeItsLastRelease) {
  {
    oo::AutoreleaseScope scope;
    Universe* u = SetUp();
    Entity* a = RetainedWaypoint("A");
    Entity* b = RetainedWaypoint("B");
    Entity* c = RetainedWaypoint("C");
    OO_CHECK(u->addEntity(a) && u->addEntity(b) && u->addEntity(c));

    u->removeEntity(c);
    OO_CHECK(c->getUniversalID() == NO_TARGET);
    const Entity* headAfterRemoval = u->firstBeacon();
    const Entity* tailAfterRemoval = u->lastBeacon();
    OO_CHECK(headAfterRemoval == a);
    OO_CHECK(tailAfterRemoval == b);  // the tail moved to the previous beacon
    OO_CHECK(!oo::EntityIsBeacon(c));

    oo::WeakRef<Entity> removed(c);
    oo::ReleaseEntity(c);  // the test's hold; the universe's dead list keeps it
    {
      oo::AutoreleaseScope frame;
      u->no_update = true;
      u->update(1.0);  // the dead are autoreleased
    }  // the pool drains: the last release, and disposal
    OO_CHECK(removed.get() == nullptr);  // it was disposed
    OO_CHECK(u->firstBeacon() == headAfterRemoval);  // as removal left it
    OO_CHECK(u->lastBeacon() == tailAfterRemoval);

    u->removeEntity(a);
    u->removeEntity(b);
    oo::ReleaseEntity(a);
    oo::ReleaseEntity(b);
  }
}

OO_TEST_MAIN()
