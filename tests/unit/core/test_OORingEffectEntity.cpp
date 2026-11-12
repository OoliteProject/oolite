/*	test_OORingEffectEntity.mm
        Unit tests for OORingEffectEntity
   (src/Core/Entities/OORingEffectEntity.h), the expanding ring of a big
   explosion or a witchspace jump.

        The entity reads Universe and PLAYER, so the test links the whole game
   but main (['*']) and uses a Universe that was never initialised, subclassed
   to record -removeEntity:, and a plain entity as PLAYER. The expectations
   cover: no ring from nil; a ring takes the source's position, orientation and
   velocity, is an effect that cannot collide, owned by the source; its
   description counts the time passed; it removes itself after two seconds. The
   rings are made through the one block of helpers below: each ring is a C++
   entity. Run: bash tools/check-core-tests.sh
*/

#include <string>

#include "OODescription.h"
#include "OORingEffectEntity.h"
#include "PlayerEntity.h"  // PLAYER is C++
#include "Universe.h"
#include "oo_test.hpp"

// main.mm defines the debug flags, and the test has its own main.
#ifndef NDEBUG
uint32_t gDebugFlags = 0;
#endif

class PlayerEntity;
extern PlayerEntity* gOOPlayer;
extern Universe* gSharedUniverse;

class TestPlayer : public PlayerEntity {
 public:
  HPVector viewpointPosition() override { return kZeroHPVector; }
};

// NewTestPlayer<TestPlayer>(): a C++ player, as
// PlayerEntity::sharedPlayer() makes the game's, retained (+1) as +alloc's
// object was.
template <class T>
T* NewTestPlayer() {
  oo::Ref<T> player = oo::makeRef<T>();
  {
    oo::RetainEntity(oo::MadeEntity(player));
  }
  return player.get();
}

// UNIVERSE: never initialised; records what is removed.
class TestUniverse : public Universe {
 public:
  Entity* _removed = {};

  bool removeEntity(
      Entity* entity) override  // the C++ entity; the record is its object
  {
    _removed = entity;
    return true;
  }
};

namespace {

TestUniverse* sUniverse = nullptr;

void SetUp() {
  if (sUniverse == nullptr) {
    sUniverse = new TestUniverse();  // never released
  }
  sUniverse->_removed = nullptr;
  gSharedUniverse = sUniverse;
  static TestPlayer* player = nullptr;
  if (player == nullptr) player = NewTestPlayer<TestPlayer>();
  gOOPlayer = player;
}

// --- How the test makes a ring (ported by the conversion), and nothing else
// ----------------------

Entity* Ring(Entity* source) {
  return oo::MadeEntity(OORingEffectEntity::ringFromEntity(source));
}  // the source's C++ entity
Entity* ShrinkingRing(Entity* source) {
  return oo::MadeEntity(OORingEffectEntity::shrinkingRingFromEntity(source));
}

// --------------------------------------------------------------------------------------------------

Entity* Source() {
  Entity* source = oo::MadeEntity(oo::makeRef<Entity>());
  source->setCollisionRadius(8.0f);
  source->setPosition(make_HPvector(1, 2, 3));
  source->setOrientation(make_quaternion(0, 1, 0, 0));
  source->setVelocity(make_vector(4, 5, 6));
  return source;
}

}  // namespace

OO_TEST(noSourceNoRing) {
  {
    SetUp();
    OO_CHECK(Ring(nullptr) == nullptr);
    OO_CHECK(ShrinkingRing(nullptr) == nullptr);
  }
}

OO_TEST(ringTakesTheSource) {
  {
    SetUp();
    Entity* source = Source();
    for (Entity* ring : {Ring(source), ShrinkingRing(source)}) {
      OO_CHECK(ring != nullptr && ring != source);
      OO_CHECK(HPvector_equal(ring->getPosition(), make_HPvector(1, 2, 3)));
      Quaternion q = ring->getOrientation();
      OO_CHECK(q.w == 0 && q.x == 1 && q.y == 0 && q.z == 0);
      Vector v = ring->getVelocity();
      OO_CHECK(v.x == 4 && v.y == 5 && v.z == 6);
      OO_CHECK(ring->status() == OOEntityStatus::kEffect &&
               ring->getScanClass() == OOScanClass::kNoDraw);
      OO_CHECK(ring->owner() == source);
      OO_CHECK(ring->isEffect() && !ring->canCollide());
      OO_CHECK(!ring->getIsShip() && !ring->getIsVisualEffect());
      OO_CHECK(
          oo::EntityDescription(ring).starts_with("<OORingEffectEntity 0x"));
      OO_CHECK(oo::EntityDescription(ring).ends_with(
          "{0.000000 seconds passed of 2.000000}"));
    }
  }
}

OO_TEST(updateCountsAndExpires) {
  {
    SetUp();
    Entity* ring = Ring(Source());
    ring->update(0.5);
    OO_CHECK(oo::EntityDescription(ring).ends_with(
        "{0.500000 seconds passed of 2.000000}"));
    OO_CHECK(
        HPvector_equal(ring->getPosition(),
                       make_HPvector(3, 4.5, 6)));  // moved by its velocity
    OO_CHECK(sUniverse->_removed == nullptr);

    ring->update(1.5);
    OO_CHECK(sUniverse->_removed == nullptr);  // exactly two seconds: not yet
    ring->update(0.25);
    OO_CHECK(sUniverse->_removed == ring);
  }
}

OO_TEST_MAIN()
