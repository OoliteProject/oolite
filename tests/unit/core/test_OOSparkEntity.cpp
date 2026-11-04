/*	test_OOSparkEntity.mm
        Unit tests for OOSparkEntity (src/Core/Entities/OOSparkEntity.h), the
   spark a damaged ship throws.

        Its object needs the game graph, so the test links the whole game but
   main (['*']) and uses a Universe that was never initialised, of a test
   subclass that records what is removed, and a plain entity as PLAYER. The
   tests pin what the initialiser sets (position, velocity, size, colour,
   status), the fade towards red as it updates, and its removal when it has
   faded. Making a spark and reading its colour components go through the
   helpers below: a spark is made by its factory and handed to Objective-C as
   its facade, an OOLightParticleEntity. Run: bash tools/check-core-tests.sh
*/

#include <cmath>

#include "OOColor.h"
#include "OODescription.h"
#include "OOSparkEntity.h"
#include "PlayerEntity.h"
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

// NewTestPlayer<TestPlayer>(): a C++ player under the ship's facade, as
// PlayerEntity::sharedPlayer() makes the game's, retained (+1).
template <class T>
T* NewTestPlayer() {
  oo::Ref<T> player = oo::makeRef<T>();
  {
    oo::RetainEntity(oo::MadeEntity(player));
  }
  return player.get();
}

static Entity* sRemoved = nil;

// UNIVERSE: never initialised; records what is removed.
class TestUniverse : public Universe {
 public:
  bool removeEntity(Entity* entity) override {
    sRemoved = entity;
    return YES;
  }
};

namespace {

// --- How a spark is made, and its colour (a @protected ivar), and nothing else
// -------------------

Entity* MakeSpark(HPVector position, Vector velocity, OOTimeDelta duration,
                  float size, OOColor* color) {
  return oo::MadeEntity(OOSparkEntity::sparkWithPosition(
      position, velocity, duration, size, color));
}

// The object is the root Entity; its C++ part is the particle.
OOLightParticleEntity* Particle(Entity* e) {
  return static_cast<OOLightParticleEntity*>(e);
}
const GLfloat* ColorComponents(Entity* e) {
  return Particle(e)->_colorComponents;
}

// --------------------------------------------------------------------------------------------------

void SetUp() {
  static Universe* universe = nil;
  if (universe == nil) {
    universe = new TestUniverse();  // never released
  }
  gSharedUniverse = universe;
  static TestPlayer* player = nullptr;
  if (player == nullptr) player = NewTestPlayer<TestPlayer>();
  gOOPlayer = player;
  sRemoved = nil;
}

bool Near(GLfloat a, GLfloat b) { return fabs(a - b) < 1e-5; }

bool ComponentsAre(Entity* e, GLfloat r, GLfloat g, GLfloat b, GLfloat a) {
  const GLfloat* c = ColorComponents(e);
  return Near(c[0], r) && Near(c[1], g) && Near(c[2], b) && Near(c[3], a);
}

}  // namespace

OO_TEST(initWithPosition) {
  {
    SetUp();
    oo::Ref<OOColor> color = OOColor::colorWithRed(0.2f, 0.4f, 0.6f, 0.8f);
    Entity* spark = MakeSpark(make_HPvector(1, 2, 3), make_vector(10, 0, 0),
                              2.0, 4.0f, color.get());
    OO_CHECK(spark != nil);
    OO_CHECK(HPvector_equal(spark->getPosition(), make_HPvector(1, 2, 3)));
    OO_CHECK(vector_equal(spark->getVelocity(), make_vector(10, 0, 0)));
    OO_CHECK(spark->collisionRadius() == 2.0f &&
             Particle(spark)->diameter() == 4.0f);
    OO_CHECK(spark->status() == STATUS_EFFECT &&
             spark->getScanClass() == CLASS_NO_DRAW);
    OO_CHECK(spark->isEffect() && !spark->canCollide());
    OO_CHECK(ComponentsAre(spark, 0.2f, 0.4f, 0.6f, 0.8f));
    OO_CHECK(oo::EntityDescription(spark).starts_with("<OOSparkEntity 0x"));
  }
}

OO_TEST(fadesTowardsRedAndIsRemoved) {
  {
    SetUp();
    oo::Ref<OOColor> color = OOColor::colorWithRed(0.2f, 0.4f, 0.6f, 0.8f);
    Entity* spark = MakeSpark(make_HPvector(1, 2, 3), make_vector(10, 0, 0),
                              2.0, 4.0f, color.get());

    // Half way: half the base colour, plus half red; moved by its velocity.
    spark->update(1.0);
    OO_CHECK(ComponentsAre(spark, 0.6f, 0.2f, 0.3f, 0.4f));
    OO_CHECK(HPvector_equal(spark->getPosition(), make_HPvector(11, 2, 3)));
    OO_CHECK(sRemoved == nil);

    // Gone: red, transparent, and removed from the universe.
    spark->update(1.5);
    OO_CHECK(ComponentsAre(spark, 1.0f, 0.0f, 0.0f, 0.0f));
    OO_CHECK(sRemoved == spark);
  }
}

OO_TEST_MAIN()
