/*	test_OOExhaustPlumeEntity.mm
        Unit tests for OOExhaustPlumeEntity
   (src/Core/Entities/OOExhaustPlumeEntity.h), the engine plumes ships carry as
   subentities.

        The entity reads Universe and its ship, so the test links the whole game
   but main (['*']) and uses a Universe that was never initialised, subclassed
   to answer the time the test sets, a plain entity as PLAYER, and as the ship
   an entity that answers the ShipEntity selectors the plume sends (a C++ ship
   stand-in). The RNG is seeded, as the game seeds it, so the plume's random
   fluctuations repeat. The tests cover: a plume is made for its ship from six
   tokens (position and scale, scaled by the ship's scale but for the scale's z,
   which outside 0.5..2 is 1), and from none is nil; its scale accessors; it is
   an exhaust (and an entity is not); its collision radius is what -update: last
   measured; -update: does nothing without a visible ship, measures nothing
   below a minimal speed, and otherwise measures the plume (the value is
   pinned); -rescaleBy: scales it and -rescaleBy:writeToCache: does nothing; and
   its texture is loaded once, by name (the loader replaced as in
   test_OOParticleSystem). The collision radius is set through the one helper
   below. The plumes are made as the ship makes them (exhaustForShip()). The
   cases ask the C++ class; the facade case pins the crossing (the object is the
   root's, whose C++ part is the plume), and jsExtensions pins that the engine's
   selectors reach the C++ class's overrides through the root. Run: tests/run.sh
   unit
*/

#include <cmath>
#include <optional>
#include <string>

#include "EntityOOJavaScriptExtensions.h"
#include "OOColor.h"
#include "OOExhaustPlumeEntity.h"
#include "OOJSEntity.h"
#include "OOJSExhaustPlume.h"
#include "OOTexture.h"
#include "PlayerEntity.h"
#include "Universe.h"
#include "oo_test.hpp"
#include "EntityManualRefs.h"  // the tests' manual entity references (T095)

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

// A C++ player under the ship's facade, as PlayerEntity::sharedPlayer() makes
// the game's, retained (+1) as +alloc's object was.
template <class T>
T* NewTestPlayer() {
  std::shared_ptr<T> player = oo::makeRef<T>();
  {
    oo::RetainEntity(oo::MadeEntity(player));
  }
  return player.get();
}

// UNIVERSE: never initialised; answers the test's time.
class TestUniverse : public Universe {
 public:
  OOTimeAbsolute& _time =
      universal_time;  // the universe's own state, which its getter answers
};

/*	The plume's ship: answers what the plume asks a ShipEntity. The plume
   calls the ship's members, so the stand-in is a C++ ship (never set up) that
   overrides the one
   virtual member it answered (isVisible()) and whose fields give the same
   answers from the others (not suppressing notifications, the emissive colour,
   the three vectors, no damage, the speed factor and the flight speed a hundred
   times it).
*/
class TestShip : public ::ShipEntity {
 public:
  bool isVisible() override { return _visible; }
  void setSpeedFactor(GLfloat value) {
    maxFlightSpeed = 100.0f;
    flightSpeed = 100.0f * value;
  }

  bool _visible = true;
};

extern JSContext*
    gOOJSMainThreadContext;  // the engine's (OOJavaScriptEngine.mm)

namespace {

TestUniverse* sUniverse = nullptr;

// The texture loader's stand-in.
std::optional<std::string> sTextureName;
OOTexture* sTexture = nullptr;  // never released

// OOTexture::nameFactory, the test-only loader hook.
std::shared_ptr<OOTexture> LoadTexture(const std::optional<std::string>& name,
                               const std::optional<std::string>&,
                               OOTextureFlags, GLfloat, GLfloat) {
  sTextureName = name;
  return oo::share(sTexture);
}

void SetUp(OOTimeAbsolute time) {
  if (sUniverse == nullptr) {
    sUniverse = new TestUniverse();                 // never released
    sTexture = oo::makeRef<OOTexture>().leakRef();  // never released
    OOTexture::nameFactory = &LoadTexture;
  }
  sUniverse->_time = time;
  gSharedUniverse = sUniverse;
  static TestPlayer* player = nullptr;
  if (player == nullptr) player = NewTestPlayer<TestPlayer>();
  gOOPlayer = player;
  // The ship's -dealloc sends its (absent) scripts entityDestroyed in a request
  // on the main thread's context, so there is one, with nothing in it.
  if (gOOJSMainThreadContext == nullptr)
    gOOJSMainThreadContext = JS_NewContext(JS_NewRuntime());
  ranrot_srand(12345);
}

// --- Ivars the test sets, and nothing else
// ---------------------------------------------------------

void SetCollisionRadius(Entity* e, GLfloat value) {
  e->collision_radius = value;
}

// --------------------------------------------------------------------------------------------------

bool Near(double a, double b) { return std::fabs(a - b) < 1e-3; }

bool VectorIs(Vector v, float x, float y, float z) {
  return v.x == x && v.y == y && v.z == z;
}

// A ship's object (autoreleased, as the Objective-C stand-in was), holding the
// stand-in ship.
Entity* Ship() {
  std::shared_ptr<TestShip> ship = oo::makeRef<TestShip>();
  Entity* object = oo::MadeEntity(ship);
  ship->isShip =
      true;  // a ship (its subentity plume asks it, as a set-up ship answers)
  ship->_visible = true;
  ship->setSpeedFactor(1.0f);
  ship->suppressAegisMessages = false;
  ship->exhaust_emissive_color = OOColor::colorWithRed(0.7f, 0.9f, 1.0f, 0.9f);
  ship->v_forward = make_vector(0, 0, 1);
  ship->v_right = make_vector(1, 0, 0);
  ship->v_up = make_vector(0, 1, 0);
  ship->energy = ship->maxEnergy = 100.0f;  // no damage
  return object;
}

TestShip* Part(Entity* ship) {
  return static_cast<TestShip*>(oo::ToShip(ship));
}

// A plume, made as the ship makes one: its Objective-C object is autoreleased
// in the test's pool and holds it; null for no tokens.
OOExhaustPlumeEntity* Plume(Entity* ship, std::vector<std::string> tokens,
                            float scale) {
  return static_cast<OOExhaustPlumeEntity*>(oo::MadeEntity(
      OOExhaustPlumeEntity::exhaustForShip(oo::ToShip(ship), tokens, scale)));
}

}  // namespace

OO_TEST(made) {
  {
    SetUp(0.0);
    Entity* ship = Ship();
    OOExhaustPlumeEntity* plume =
        Plume(ship, {"1", "2", "3", "4", "5", "1.5"}, 2.0f);
    OO_CHECK(plume != nullptr);
    OO_CHECK(plume->owner() == ship);
    OO_CHECK(HPvector_equal(plume->getPosition(), make_HPvector(2, 4, 6)));
    OO_CHECK(VectorIs(plume->scale(), 8, 10, 1.5f));  // z is not scaled
    // Callers ask the C++ part.
    OO_CHECK(plume->isExhaust() &&
             dynamic_cast<OOExhaustPlumeEntity*>(ship) == nullptr);
    OO_CHECK(plume->findCollisionRadius() == 0.0);

    OO_CHECK(Plume(ship, {}, 1.0f) == nullptr);
  }
}

OO_TEST(scaleZ) {
  {
    SetUp(0.0);
    Entity* ship = Ship();
    OO_CHECK(VectorIs(
        Plume(ship, {"0", "0", "0", "1", "1", "0.4"}, 1.0f)->scale(), 1, 1, 1));
    OO_CHECK(VectorIs(
        Plume(ship, {"0", "0", "0", "1", "1", "2.5"}, 1.0f)->scale(), 1, 1, 1));
    OOExhaustPlumeEntity* plume =
        Plume(ship, {"0", "0", "0", "1", "1", "2"}, 1.0f);
    OO_CHECK(VectorIs(plume->scale(), 1, 1, 2));
    plume->setScale(make_vector(3, 4, 0.5f));
    OO_CHECK(VectorIs(plume->scale(), 3, 4, 0.5f));
    plume->setScale(make_vector(3, 4, 0.0f));
    OO_CHECK(VectorIs(plume->scale(), 3, 4, 1));
  }
}

OO_TEST(rescale) {
  {
    SetUp(0.0);
    OOExhaustPlumeEntity* plume =
        Plume(Ship(), {"0", "0", "0", "1", "2", "1.5"}, 1.0f);
    plume->rescaleBy(2.0f);
    OO_CHECK(VectorIs(plume->scale(), 2, 4, 3));  // z too: no clamp here
    plume->rescaleBy(5.0f, true);
    OO_CHECK(VectorIs(plume->scale(), 2, 4, 3));
  }
}

OO_TEST(updateWithoutVisibleShip) {
  {
    SetUp(1.0);
    Entity* ship = Ship();
    OOExhaustPlumeEntity* plume =
        Plume(ship, {"0", "0", "-10", "2", "2", "1"}, 1.0f);
    SetCollisionRadius(plume, 42.0f);
    Part(ship)->_visible = false;
    plume->update(0.1);
    OO_CHECK(plume->findCollisionRadius() == 42.0);

    plume->setOwner(nullptr);
    plume->update(0.1);
    OO_CHECK(plume->findCollisionRadius() == 42.0);
  }
}

OO_TEST(updateBelowMinimalSpeed) {
  {
    SetUp(1.0);
    Entity* ship = Ship();
    OOExhaustPlumeEntity* plume =
        Plume(ship, {"0", "0", "-10", "2", "2", "1"}, 1.0f);
    SetCollisionRadius(plume, 42.0f);
    Part(ship)->setSpeedFactor(0.0005f);
    plume->update(0.1);
    OO_CHECK(plume->findCollisionRadius() == 0.0);
  }
}

OO_TEST(updateMeasures) {
  {
    SetUp(1.0);
    Entity* ship = Ship();
    OOExhaustPlumeEntity* plume =
        Plume(ship, {"0", "0", "-10", "2", "2", "1"}, 1.0f);
    plume->resetPlume();
    plume->update(0.1);
    // What the Objective-C class measured, with this seed.
    OO_CHECK(Near(plume->findCollisionRadius(), 14.464036));
  }
}

OO_TEST(texture) {
  {
    SetUp(0.0);
    OOExhaustPlumeEntity* plume =
        Plume(Ship(), {"0", "0", "0", "1", "1", "1"}, 1.0f);
    sTextureName.reset();
    OO_CHECK(plume->texture() == sTexture);
    OO_CHECK(sTextureName ==
             std::optional<std::string>("oolite-exhaust-blur.png"));
    sTextureName.reset();
    OO_CHECK(plume->texture() == sTexture &&
             OOExhaustPlumeEntity::plumeTexture() == sTexture);
    OO_CHECK(!sTextureName.has_value());  // loaded once
  }
}

OO_TEST(facade) {
  {
    SetUp(0.0);
    // The object is the root's facade, whose C++ part is the plume: a C++
    // entity.
    Entity* object = oo::MadeEntity(OOExhaustPlumeEntity::exhaustForShip(
        oo::ToShip(Ship()), {"0", "0", "0", "1", "1", "1"}, 1.0f));
    OO_CHECK(dynamic_cast<OOExhaustPlumeEntity*>(object) != nullptr);
    OO_CHECK(object == object);
  }
}

// Registers Entity's JS class and the given class (a child of Entity) in the
// test's context, as the engine's start does; the context is made here if the
// test has none yet.
static void RegisterJSClasses(void (*initClass)(JSContext*, JSValueConst)) {
  extern JSContext* gOOJSMainThreadContext;
  if (gOOJSMainThreadContext == nullptr)
    gOOJSMainThreadContext = JS_NewContext(JS_NewRuntime());
  JSContext* context = OOJSAcquireContext();
  JSValue global = JS_GetGlobalObject(context);
  InitOOJSEntity(context, global);
  initClass(context, global);
  JS_FreeValue(context, global);
}

// The C++ class's overrides of the root's JS members: what the engine asks a
// plume's object for by selector is what OOJSExhaustPlume.mm answers.
OO_TEST(jsExtensions) {
  {
    SetUp(0.0);
    Entity* plume = Plume(Ship(), {"0", "0", "0", "1", "1", "1"}, 1.0f);
    RegisterJSClasses(InitOOJSExhaustPlume);
    const JSClassID jsClass = OOJSEntityJSClassID(plume);
    const JSClassID expectedClass = JSExhaustPlumeClassID();
    OO_CHECK(jsClass != 0 && jsClass == expectedClass);
    OO_CHECK(OOJSEntityJSClassName(plume) ==
             std::optional<std::string>("ExhaustPlume"));
    OO_CHECK(OOJSEntityIsVisibleToScripts(plume) == true);
  }
}

OO_TEST_MAIN()
