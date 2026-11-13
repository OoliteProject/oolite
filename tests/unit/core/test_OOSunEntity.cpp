/*	test_OOSunEntity.mm
        Unit tests for OOSunEntity (src/Core/Entities/OOSunEntity.h), a system's
   star.

        The entity reads Universe and PLAYER, so the test links the whole game
   but main (['*']) and uses a Universe that was never initialised (minimum
   detail, so the corona never moves), subclassed to record the main light
   position, the sky colour and the system data the sun sets, and an entity that
   answers the viewpoint the test sets as PLAYER. A sun's radius, name and
   corona come from its dictionary, it is a no-draw, visible, collidable sun;
   its light colours are its colour blended with white;
   -changeSunProperty:withDictionary: takes the radius, the name, the corona,
        and going nova or not, and refuses anything else; a new position moves
   the main light; going nova counts down, then whitens the sky and records the
   nova and the growing radius in the system data; and the camera-relative
   position is pulled in to 1e9 for a far sun. The camera-relative position is
   read through the one helper below. The cases make the C++ sun and ask the C++
        class, and the facade case pins the crossing: the
        sun is the root Entity. Run: bash tools/check-core-tests.sh
*/

#include <cmath>
#include <map>
#include <string>

#include "EntityOOJavaScriptExtensions.h"
#include "OOColor.h"
#include "OODescription.h"
#include "OOJSEntity.h"
#include "OOJSSun.h"
#include "OOSunEntity.h"
#include "PlayerEntity.h"  // PLAYER is C++
#include "Universe.h"
#include "oo_test.hpp"
#include "oofnd/PListGet.hpp"
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
  HPVector _viewpoint = {};

  HPVector viewpointPosition() override { return _viewpoint; }
};

// NewTestPlayer<TestPlayer>(): a C++ player, as PlayerEntity::sharedPlayer()
// makes the game's, retained (+1).
template <class T>
T* NewTestPlayer() {
  std::shared_ptr<T> player = oo::makeShared<T>();
  {
    oo::RetainEntity(oo::MadeEntity(player));
  }
  return player.get();
}

// UNIVERSE: never initialised; records what the sun sets.
class TestUniverse : public Universe {
 public:
  Vector _mainLight = {};
  GLfloat _sky[4];
  int _skySets = {};
  std::map<std::string, oo::PList> _systemData = {};

  void setMainLightPosition(Vector sunPos) override { _mainLight = sunPos; }
  void setSkyColorRed(GLfloat red, GLfloat green, GLfloat blue,
                      GLfloat alpha) override {
    _sky[0] = red;
    _sky[1] = green;
    _sky[2] = blue;
    _sky[3] = alpha;
    _skySets++;
  }
  void setSystemDataKey(
      const std::string& key, const oo::PList& value,
      const std::optional<std::string>& /*manifest*/) override {
    _systemData[key] = value;
  }
};

namespace {

TestUniverse* sUniverse = nullptr;
TestPlayer* sPlayer = nullptr;

void SetUp() {
  if (sUniverse == nullptr) {
    sUniverse = new TestUniverse();  // never released
    new (&sUniverse->_systemData) std::map<std::string, oo::PList>();
    sPlayer = NewTestPlayer<TestPlayer>();
  }
  sUniverse->_skySets = 0;
  sUniverse->_systemData.clear();
  sUniverse->_mainLight = kZeroVector;
  gSharedUniverse = sUniverse;
  gOOPlayer = sPlayer;
  sPlayer->_viewpoint = kZeroHPVector;
}

// --- Ivars the test reads, and nothing else
// ---------------------------------------------------------

Vector CameraRelativePosition(Entity* e) {
  return e->cameraRelativePosition;
}  // --------------------------------------------------------------------------------------------------

oo::PList Dict(oo::PList::Dict entries) {
  return oo::PList(std::move(entries));
}

bool Near(double a, double b) { return std::fabs(a - b) < 1e-4; }

// A new C++ sun.
OOSunEntity* Sun(OOColor* color, double radius) {
  std::shared_ptr<OOSunEntity> sun = oo::makeShared<OOSunEntity>();
  (void)oo::MadeEntity(sun);
  sun->initSunWithColor(color, Dict({
                                   {"sun_name", oo::PList("Sol")},
                                   {"sun_radius", oo::PList(radius)},
                                   {"corona_flare", oo::PList(0.5)},
                                   {"corona_shimmer", oo::PList(0.5)},
                               }));
  return sun.get();
}

OOSunEntity* RedSun() {
  return Sun(OOColor::colorWithRed(1.0f, 0.0f, 0.0f, 1.0f).get(), 1000.0);
}

}  // namespace

OO_TEST(made) {
  {
    SetUp();
    OOSunEntity* sun = RedSun();
    OO_CHECK(sun != nullptr &&
             dynamic_cast<OOSunEntity*>(static_cast<Entity*>(sun)) != nullptr);
    OO_CHECK(sun->radius() == 1000.0 && sun->collisionRadius() == 1000.0f);
    OO_CHECK(sun->name() == std::optional<std::string>("Sol"));
    OO_CHECK(sun->planetType() == OOStellarBodyType::kSun);
    OO_CHECK(sun->getScanClass() == OOScanClass::kNoDraw);
    OO_CHECK(sun->isSun() && sun->isVisible() && sun->canCollide());
    OO_CHECK(!sun->willGoNova() && !sun->goneNova());
  }
}

OO_TEST(lightColours) {
  {
    SetUp();
    OOSunEntity* sun = RedSun();
    // Red blended 30% with white: (1, 0.3, 0.3).
    GLfloat diffuse[4] = {-1, -1, -1, -1};
    GLfloat specular[4] = {-1, -1, -1, -1};
    sun->getDiffuseComponents(diffuse);
    sun->getSpecularComponents(specular);
    OO_CHECK(Near(specular[0], 1.0) && Near(specular[1], 0.3) &&
             Near(specular[2], 0.3) && specular[3] == 1.0f);
    OO_CHECK(Near(diffuse[0], 1.0) && Near(diffuse[1], 0.65) &&
             Near(diffuse[2], 0.65) && diffuse[3] == 1.0f);

    OO_CHECK(sun->setSunColor(OOColor::blueColor().get()));
    sun->getSpecularComponents(specular);
    OO_CHECK(Near(specular[0], 0.3) && Near(specular[1], 0.3) &&
             Near(specular[2], 1.0));
    OO_CHECK(!sun->setSunColor(nullptr));
    sun->getSpecularComponents(specular);
    OO_CHECK(Near(specular[2], 1.0));
  }
}

OO_TEST(changeSunProperty) {
  {
    SetUp();
    OOSunEntity* sun = RedSun();
    OO_CHECK(sun->changeSunProperty("sun_radius",
                                    Dict({{"sun_radius", oo::PList(2500.0)}})));
    OO_CHECK(sun->radius() == 2500.0);
    OO_CHECK(sun->changeSunProperty("sun_name",
                                    Dict({{"sun_name", oo::PList("Alpha")}})));
    OO_CHECK(sun->name() == std::optional<std::string>("Alpha"));
    OO_CHECK(sun->changeSunProperty("sun_name", Dict({})));
    OO_CHECK(!sun->name().has_value());
    OO_CHECK(sun->changeSunProperty("corona_flare",
                                    Dict({{"corona_flare", oo::PList(0.25)}})));
    OO_CHECK(sun->radius() == 2500.0);
    OO_CHECK(sun->changeSunProperty(
        "corona_shimmer", Dict({{"corona_shimmer", oo::PList(0.5)}})));
    OO_CHECK(sun->changeSunProperty("corona_hues",
                                    Dict({{"corona_hues", oo::PList(0.5)}})));

    OO_CHECK(sun->changeSunProperty(
        "sun_gone_nova", Dict({{"sun_gone_nova", oo::PList(true)}})));
    OO_CHECK(sun->willGoNova() && sun->goneNova());
    OO_CHECK(sun->changeSunProperty("sun_gone_nova",
                                    Dict({{"sun_gone_nova", oo::PList(false)},
                                          {"corona_flare", oo::PList(0.1)}})));
    OO_CHECK(!sun->willGoNova() && !sun->goneNova());
    OO_CHECK(sun->radius() == 2500.0);  // the radius it had before going nova

    OO_CHECK(!sun->changeSunProperty(
        "sun_color", Dict({{"sun_color", oo::PList("redColor")}})));
  }
}

OO_TEST(radiusAndPosition) {
  {
    SetUp();
    OOSunEntity* sun = RedSun();
    sun->setRadius(300.0f, 0.0f);
    OO_CHECK(sun->radius() == 300.0);
    sun->setPosition(make_HPvector(10, 20, 30));
    OO_CHECK(HPvector_equal(sun->getPosition(), make_HPvector(10, 20, 30)));
    OO_CHECK(sUniverse->_mainLight.x == 10 && sUniverse->_mainLight.y == 20 &&
             sUniverse->_mainLight.z == 30);
  }
}

OO_TEST(goingNova) {
  {
    SetUp();
    OOSunEntity* sun = RedSun();
    sun->setGoingNova(true, 1.0);
    OO_CHECK(sun->willGoNova() && !sun->goneNova());
    sun->update(0.5);
    OO_CHECK(!sun->goneNova() && sUniverse->_skySets == 0);
    sun->update(0.625);
    OO_CHECK(sun->goneNova() && sUniverse->_skySets == 0);

    // The expansion: the sky goes white and the nova is recorded.
    sun->update(0.125);
    OO_CHECK(sUniverse->_skySets == 1 && sUniverse->_sky[0] == 1.0f &&
             sUniverse->_sky[3] == 1.0f);
    OO_CHECK(sUniverse->_systemData["sun_gone_nova"] ==
             oo::PList(static_cast<bool>(
                 true)));  // a boolean (OOCocoa.h defines true as 1)
    OO_CHECK(sUniverse->_systemData.count("corona_flare") == 1 &&
             sUniverse->_systemData.count("corona_hues") == 1);
    OO_CHECK(Near(
        oo::PListGet<double>::from(&sUniverse->_systemData["sun_radius"], -1.0),
        1000.0 + 0.125 * 10000.0));

    // Later in the minute: the sky fades, nothing more recorded but the radius.
    sUniverse->_systemData.clear();
    sun->update(1.0);
    OO_CHECK(sUniverse->_skySets == 2 && sUniverse->_sky[0] == 0.8125f &&
             sUniverse->_sky[3] == 1.0f);
    OO_CHECK(sUniverse->_systemData.count("sun_gone_nova") == 0 &&
             sUniverse->_systemData.count("sun_radius") == 1);
    // Then it goes black.
    sun->update(0.125);
    OO_CHECK(sUniverse->_skySets == 3 && sUniverse->_sky[0] == 0.0f &&
             sUniverse->_sky[3] == 0.0f);

    sun->resetNova();
    OO_CHECK(sun->willGoNova() &&
             sun->goneNova());  // reset keeps the higher temperature
    sun->setGoingNova(false, 0);
    OO_CHECK(!sun->willGoNova());
  }
}

OO_TEST(description) {
  {
    SetUp();
    OOSunEntity* sun = RedSun();
    sun->setGoingNova(true, 10.0);
    const std::string description = oo::EntityDescription(sun);
    OO_CHECK(description.find("radius: 1.000km") != std::string::npos);
    OO_CHECK(description.find("(will go nova)") != std::string::npos);
  }
}

OO_TEST(cameraRelativePosition) {
  {
    SetUp();
    OOSunEntity* sun = RedSun();
    sun->setPosition(make_HPvector(100, 0, 0));
    sPlayer->_viewpoint = make_HPvector(40, 0, 0);
    sun->updateCameraRelativePosition();
    Vector v = CameraRelativePosition(sun);
    OO_CHECK(v.x == 60.0f && v.y == 0.0f && v.z == 0.0f);

    sun->setPosition(make_HPvector(4e9, 0, 3e9));
    sPlayer->_viewpoint = kZeroHPVector;
    sun->updateCameraRelativePosition();
    v = CameraRelativePosition(sun);
    OO_CHECK(Near(v.x / 1e9, 0.8) && Near(v.z / 1e9, 0.6));
  }
}

OO_TEST(facade) {
  {
    SetUp();
    OOSunEntity* sun = RedSun();
    Entity* object = sun;
    OO_CHECK(object != nullptr);  // A C++ entity.
    OO_CHECK(dynamic_cast<OOSunEntity*>(object) == sun);
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

// The binding's category: what
// the engine asks a OOSunEntity for by selector is what OOJSSun.mm answers.
OO_TEST(jsExtensions) {
  {
    SetUp();
    OOSunEntity* sun = RedSun();
    RegisterJSClasses(InitOOJSSun);
    Entity* object = sun;  // what the engine asks
    const JSClassID jsClass = OOJSEntityJSClassID(object);
    const JSClassID expectedClass = JSSunClassID();
    OO_CHECK(jsClass != 0 && jsClass == expectedClass);
    OO_CHECK(OOJSEntityJSClassName(object) ==
             std::optional<std::string>("Sun"));
    OO_CHECK(OOJSEntityIsVisibleToScripts(object) == true);
  }
}

OO_TEST_MAIN()
