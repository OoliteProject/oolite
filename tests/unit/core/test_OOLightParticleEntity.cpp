/*	test_OOLightParticleEntity.mm
        Unit tests for OOLightParticleEntity
   (src/Core/Entities/OOLightParticleEntity.h), the textured glow that the
   sparks, flashes, flashers and plasma effects draw.

        Like Entity's, its object needs the game graph, so the test links the
   whole game but main (['*']) and uses a Universe that was never initialised
   (detail level minimum, so reduced detail) of a test subclass that answers the
   time and records what is removed, and a plain entity as PLAYER. The
   expectations cover: -initWithDiameter: (draw distance, scan class, status,
   white), the colour and diameter setters, -drawSubEntityImmediate:translucent:
   (the owner's camera distance, the cut-off, and the draw it sends to self),
   and that the texture a subclass answers is the one the debug texture list
   reports. The colour components, a @protected ivar, are read through the one
   helper below. A particle is made in C++ and handed to Objective-C with
   oo::NewEntityFacade, whose object is the root Entity's facade: the test
   subclass is a C++ subclass with the same answers, the class's own selectors
   are member calls and the root's are still sent to the object. Run: bash
   tools/check-core-tests.sh
*/

#include <cmath>

#include "OOColor.h"
#include "OODescription.h"
#include "OOLightParticleEntity.h"
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

// NewTestPlayer<TestPlayer>(): a C++ player under the ship's facade, as
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

// UNIVERSE: never initialised; answers the time the test sets.
class TestUniverse : public Universe {
 public:
};

// A subclass, as OOFlashEffectEntity is: counts its draws and answers its own
// texture. (Global, so its description names it.)
class TestParticle : public OOLightParticleEntity {
 public:
  int _draws = 0;
  OOTexture* _texture = nil;

  void drawImmediate(bool /*immediate*/, bool /*translucent*/) override {
    _draws++;
  }

  OOTexture* texture() override { return _texture; }
};

// An owner whose camera distance the test sets: a plain entity.

namespace {

// --- Ivars the game reads directly, and nothing else
// ------------------------------------------------

const GLfloat* ColorComponents(OOLightParticleEntity* e) {
  return e->_colorComponents;
}
GLfloat NoDrawDistance(Entity* e) { return e->no_draw_distance; }
GLfloat CamZeroDistance(Entity* e) { return e->cam_zero_distance; }
void SetCamZeroDistance(Entity* e, GLfloat value) {
  e->cam_zero_distance = value;
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
}

bool ComponentsAre(OOLightParticleEntity* e, GLfloat r, GLfloat g, GLfloat b,
                   GLfloat a) {
  const GLfloat* c = ColorComponents(e);
  return c[0] == r && c[1] == g && c[2] == b && c[3] == a;
}

/*	A new
   C++ particle, its object (the root's facade, autoreleased) made first and the
   initialiser's body run after, the facade's order. The object holds the
   particle; the test sends it the root's selectors.
*/
template <class T>
T* NewParticle(float diameter, Entity** outObject = nullptr) {
  const oo::Ref<T> particle = oo::makeRef<T>();
  Entity* object = oo::MadeEntity(particle);
  particle->initWithDiameter(diameter);
  if (outObject != nullptr) *outObject = object;
  return particle.get();
}

}  // namespace

OO_TEST(initWithDiameter) {
  {
    SetUp();
    Entity* object = nil;
    OOLightParticleEntity* particle =
        NewParticle<OOLightParticleEntity>(8.0f, &object);
    OO_CHECK(particle != nullptr &&
             typeid(*particle) == typeid(OOLightParticleEntity));
    OO_CHECK(particle->diameter() == 8.0f);
    OO_CHECK(object->getScanClass() == CLASS_NO_DRAW &&
             object->status() == STATUS_EFFECT);
    OO_CHECK(object->isEffect() && !object->canCollide());
    OO_CHECK(ComponentsAre(particle, 1.0f, 1.0f, 1.0f, 1.0f));

    // The draw distance grows with the diameter; reduced detail (a minimum
    // detail level) scales it by 12.
    GLfloat expected = pow(8.0f / 2.0, M_SQRT2) * NO_DRAW_DISTANCE_FACTOR *
                       NO_DRAW_DISTANCE_FACTOR;
    expected *= 12.0;
    OO_CHECK((UNIVERSE != nullptr ? UNIVERSE->reducedDetail() : false));
    OO_CHECK(NoDrawDistance(object) == expected);

    // A subclass initialises the same way.
    Entity* subObject = nil;
    TestParticle* sub = NewParticle<TestParticle>(2.0f, &subObject);
    OO_CHECK(sub->diameter() == 2.0f && subObject->status() == STATUS_EFFECT &&
             subObject->isEffect());
  }
}

OO_TEST(colorAndDiameter) {
  {
    SetUp();
    OOLightParticleEntity* particle = NewParticle<OOLightParticleEntity>(1.0f);
    particle->setColor(OOColor::colorWithRed(0.25f, 0.5f, 0.75f, 0.5f).get());
    OO_CHECK(ComponentsAre(particle, 0.25f, 0.5f, 0.75f, 0.5f));
    particle->setColor(OOColor::colorWithRed(1.0f, 0.0f, 0.5f, 1.0f).get(),
                       0.125f);
    OO_CHECK(ComponentsAre(particle, 1.0f, 0.0f, 0.5f, 0.125f));

    // nil changes nothing (a message to nil did nothing), except the alpha it
    // is given.
    particle->setColor(nullptr);
    OO_CHECK(ComponentsAre(particle, 1.0f, 0.0f, 0.5f, 0.125f));
    particle->setColor(nullptr, 0.25f);
    OO_CHECK(ComponentsAre(particle, 1.0f, 0.0f, 0.5f, 0.25f));

    particle->setDiameter(3.0f);
    OO_CHECK(particle->diameter() == 3.0f);
  }
}

OO_TEST(drawSubEntity) {
  {
    SetUp();
    Entity* object = nil;
    TestParticle* particle = NewParticle<TestParticle>(1.0f, &object);
    Entity* owner = oo::MadeEntity(oo::makeRef<Entity>());
    object->setOwner(owner);

    // Opaque pass: nothing.
    SetCamZeroDistance(owner, 5.0f);
    particle->drawSubEntityImmediate(false, false);
    OO_CHECK(CamZeroDistance(object) == 0.0f && particle->_draws == 0);

    // Beyond the draw distance: the owner's distance is taken, and nothing is
    // drawn.
    SetCamZeroDistance(owner, NoDrawDistance(object) * 2.0f);
    particle->drawSubEntityImmediate(false, true);
    OO_CHECK(CamZeroDistance(object) == NoDrawDistance(object) * 2.0f &&
             particle->_draws == 0);

    // Near: drawn through -drawImmediate:translucent:, which the subclass
    // overrides.
    SetCamZeroDistance(owner, 5.0f);
    particle->drawSubEntityImmediate(false, true);
    OO_CHECK(CamZeroDistance(object) == 5.0f && particle->_draws == 1);

    // The base's own draw does nothing in the opaque pass, or beyond the draw
    // distance.
    Entity* plain = nil;
    (void)NewParticle<OOLightParticleEntity>(1.0f, &plain);
    plain->drawImmediate(false, false);
    SetCamZeroDistance(plain, NoDrawDistance(plain));
    plain->drawImmediate(false, true);
  }
}

#ifndef NDEBUG
OO_TEST(texturesListTheSubclassTexture) {
  {
    SetUp();
    Entity* object = nil;
    TestParticle* particle = NewParticle<TestParticle>(1.0f, &object);
    const oo::Ref<OOTexture> kept =
        oo::makeRef<OOTexture>();  // a C++ texture; only retained and compared
    OOTexture* texture = kept.get();
    particle->_texture = texture;
    const std::vector<oo::Ref<OOTexture>> textures = object->allTextures();
    OO_CHECK(textures.size() == 1 && textures[0].get() == texture);
  }
}
#endif

OO_TEST(description) {
  {
    SetUp();
    Entity* object = nil;
    (void)NewParticle<TestParticle>(1.0f, &object);
    OO_CHECK(oo::EntityDescription(object).starts_with("<TestParticle 0x"));
    OO_CHECK(oo::EntityDescription(object).ends_with(
        "scanClass: CLASS_NO_DRAW status: STATUS_EFFECT}"));
  }
}

// --- A C++ subclass -----

// A converted subclass, as OOSparkEntity is.
class TestCxxParticle : public OOLightParticleEntity {};

OO_TEST(cxxSubclassFacade) {
  {
    SetUp();
    const oo::Ref<TestCxxParticle> particle = oo::makeRef<TestCxxParticle>();
    particle->initWithDiameter(6.0f);
    Entity* facade = oo::MadeEntity(particle);
    OO_CHECK(facade != nil);
    OO_CHECK(particle->diameter() == 6.0f && facade->isEffect() &&
             !facade->canCollide() && facade->status() == STATUS_EFFECT);
    particle->setColor(OOColor::colorWithRed(0.5f, 0.25f, 0.0f, 1.0f).get(),
                       0.5f);
    OO_CHECK(ComponentsAre(particle.get(), 0.5f, 0.25f, 0.0f, 0.5f));
    OO_CHECK(oo::EntityDescription(facade).starts_with("<TestCxxParticle 0x"));
  }
}

OO_TEST_MAIN()
