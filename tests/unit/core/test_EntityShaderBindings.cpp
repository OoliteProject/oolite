/*	test_EntityShaderBindings.mm
        Unit tests for the category Entity (ShaderBindings)
   (src/Core/Entities/EntityShaderBindings.mm): the values a
   shader's uniforms bind to by name on any entity (the clock, the system's
   "flavour" numbers and its attributes), all read from PLAYER.

        The shader uniforms bind the entity's members through the entities'
   member table, so the test asks the binding a uniform makes for each name on
   an entity, and pins the uniform type the row gives ('f' a float, 'I' an
   unsigned int). PLAYER is an entity that answers what the category asks for
   with values the test sets; a system attribute that is not a number reads 0.
   The test links the whole game but main (['*']) for Entity. The rows read the
   entity's C++ part (the binding's target, which the helpers below pass), and
        everyPermittedNameBindsAsBySelector pins that every name
   whitelist.plist permits binds through a row, with the type the selector path
   read. Run: bash tools/check-core-tests.sh
*/

#include <cmath>
#include <cstdio>
#include <cstring>

#include "Entity.h"
#include "PlayerEntity.h"
#include "oo_test.hpp"
#include "oofnd/PList.hpp"

// main.mm defines the debug flags, and the test has its own main.
#ifndef NDEBUG
uint32_t gDebugFlags = 0;
#endif

class PlayerEntity;
extern PlayerEntity* gOOPlayer;

// The values under test, as the uniforms reach them: the binding for a name.
#include "OOEntityCalledByName.h"  // the by-name table's names
#include "OOShaderUniformMethodType.h"

// PLAYER: answers what the category asks for, with the test's values.
class TestPlayer : public PlayerEntity {
 public:
  double _clockTime = 0;
  unsigned _random100 = 0;
  unsigned _random256 = 0;
  oo::PList _government;
  oo::PList _economy;
  oo::PList _techLevel;
  oo::PList _population;
  oo::PList _productivity;

  double clockTime() override { return _clockTime; }
  unsigned systemPseudoRandom100() override { return _random100; }
  unsigned systemPseudoRandom256() override { return _random256; }
  oo::PList systemGovernment_number() override { return _government; }
  oo::PList systemEconomy_number() override { return _economy; }
  oo::PList systemTechLevel_number() override { return _techLevel; }
  oo::PList systemPopulation_number() override { return _population; }
  oo::PList systemProductivity_number() override { return _productivity; }
};

// A C++ player under the ship's facade, as PlayerEntity::sharedPlayer() makes
// the game's, retained (+1) as +alloc's object was.
template <class T>
T* NewTestPlayer() {
  oo::Ref<T> player = oo::makeRef<T>();
  {
    oo::RetainEntity(oo::MadeEntity(player));
  }
  return player.get();
}

namespace {

TestPlayer* sPlayer = nullptr;

void SetUp() {
  if (sPlayer == nullptr)
    sPlayer = NewTestPlayer<TestPlayer>();  // never released
  gOOPlayer = sPlayer;
  sPlayer->_clockTime = 0;
  sPlayer->_random100 = 0;
  sPlayer->_random256 = 0;
  sPlayer->_government = oo::PList();
  sPlayer->_economy = oo::PList();
  sPlayer->_techLevel = oo::PList();
  sPlayer->_population = oo::PList();
  sPlayer->_productivity = oo::PList();
}

Entity* AnEntity() { return oo::MadeEntity(oo::makeRef<Entity>()); }

// The binding a uniform bound to the name on the entity makes (the member
// table).
OOShaderMemberBinding Binding(Entity* entity, const char* name) {
  OOShaderMemberBinding binding = {};
  if (!EntityShaderMemberBindingFor(entity, name, &binding)) binding = {};
  return binding;
}

// What a uniform bound to the name reads: an integer or a float.
long long BoundInt(Entity* entity, const char* name) {
  OOShaderBindingValue value = {};
  const OOShaderMemberBinding binding = Binding(entity, name);
  if (binding.get != nullptr)
    binding.get(binding.target, value);  // the entity's C++ part
  return value.i;
}

double BoundFloat(Entity* entity, const char* name) {
  OOShaderBindingValue value = {};
  const OOShaderMemberBinding binding = Binding(entity, name);
  if (binding.get != nullptr)
    binding.get(binding.target, value);  // the entity's C++ part
  return value.f;
}

}  // namespace

OO_TEST(clockTime) {
  {
    SetUp();
    Entity* entity = AnEntity();
    sPlayer->_clockTime = 1234.5;
    OO_CHECK(BoundFloat(entity, "clock") == 1234.5f);
    // A double clock time is narrowed to a float.
    sPlayer->_clockTime = 180054321.75;
    OO_CHECK(BoundFloat(entity, "clock") == (GLfloat)180054321.75);
  }
}

OO_TEST(flavourNumbers) {
  {
    SetUp();
    Entity* entity = AnEntity();
    sPlayer->_random100 = 42;
    sPlayer->_random256 = 200;
    OO_CHECK(BoundInt(entity, "pseudoFixedD100") == 42);
    OO_CHECK(BoundInt(entity, "pseudoFixedD256") == 200);
  }
}

OO_TEST(systemAttributes) {
  {
    SetUp();
    Entity* entity = AnEntity();
    sPlayer->_government = oo::PList(3);
    sPlayer->_economy = oo::PList(5);
    sPlayer->_techLevel = oo::PList(11);
    sPlayer->_population = oo::PList(47);
    sPlayer->_productivity = oo::PList(21680);
    OO_CHECK(BoundInt(entity, "systemGovernment") == 3);
    OO_CHECK(BoundInt(entity, "systemEconomy") == 5);
    OO_CHECK(BoundInt(entity, "systemTechLevel") == 11);
    OO_CHECK(BoundInt(entity, "systemPopulation") == 47);
    OO_CHECK(BoundInt(entity, "systemProductivity") == 21680);
  }
}

OO_TEST(attributeNotANumberIsZero) {
  {
    SetUp();
    Entity* entity = AnEntity();
    // No value (nil), and a value that is not a number: 0, as -unsignedIntValue
    // of nil.
    sPlayer->_government = oo::PList();
    sPlayer->_economy = oo::PList("rich");
    OO_CHECK(BoundInt(entity, "systemGovernment") == 0);
    OO_CHECK(BoundInt(entity, "systemEconomy") == 0);
    OO_CHECK(BoundInt(entity, "systemTechLevel") == 0);
    OO_CHECK(BoundInt(entity, "systemPopulation") == 0);
    OO_CHECK(BoundInt(entity, "systemProductivity") == 0);
  }
}

OO_TEST(uniformTypes) {
  {
    // The uniform's type is the method's return type: a float for the clock
    // ('f'), unsigned ints ('I') for the rest.
    Entity* entity = AnEntity();
    OO_CHECK(Binding(entity, "clock").type == kOOShaderUniformTypeFloat);
    OO_CHECK(Binding(entity, "pseudoFixedD100").type ==
             kOOShaderUniformTypeUnsignedInt);
    OO_CHECK(Binding(entity, "pseudoFixedD256").type ==
             kOOShaderUniformTypeUnsignedInt);
    OO_CHECK(Binding(entity, "systemGovernment").type ==
             kOOShaderUniformTypeUnsignedInt);
    OO_CHECK(Binding(entity, "systemEconomy").type ==
             kOOShaderUniformTypeUnsignedInt);
    OO_CHECK(Binding(entity, "systemTechLevel").type ==
             kOOShaderUniformTypeUnsignedInt);
    OO_CHECK(Binding(entity, "systemPopulation").type ==
             kOOShaderUniformTypeUnsignedInt);
    OO_CHECK(Binding(entity, "systemProductivity").type ==
             kOOShaderUniformTypeUnsignedInt);
  }
}

OO_TEST(subclassesAnswerToo) {
  {
    SetUp();
    // A subclass of Entity (here the test's player) answers the category's
    // selectors.
    sPlayer->_random100 = 7;
    OO_CHECK(BoundInt(sPlayer, "pseudoFixedD100") == 7);  // the player's object
  }
}

// Every name whitelist.plist permits a shader to bind on an entity (its four
// shader_*_binding_methods arrays) is a row of the member table, with the
// uniform type the selector path read; laserColor, which nothing answers, and
// the NSUInteger names, whose type no uniform takes, bind neither way. The rows
// and the bindings they make are checked.
OO_TEST(everyPermittedNameBindsAsBySelector) {
  {
    SetUp();
    static const char* const kNames[] = {
        "position",
        "orientation",
        "relativePosition",
        "cameraRelativePosition",
        "viewpointOffset",
        "collisionRadius",
        "mass",
        "energy",
        "maxEnergy",
        "universalTime",
        "spawnTime",
        "timeElapsedSinceSpawn",
        "throwingSparks",
        "fogUniform",
        "airColorAsVector",
        "illuminationColorAsVector",
        "airColorMixRatio",
        "airDensity",
        "terminatorThresholdVector",
        "clock",
        "pseudoFixedD100",
        "pseudoFixedD256",
        "systemGovernment",
        "systemEconomy",
        "systemTechLevel",
        "systemPopulation",
        "systemProductivity",
        "isBeacon",
        "isFrangible",
        "isCloaked",
        "isJammingScanning",
        "hasMilitaryScannerFilter",
        "messageTime",
        "escortCount",
        "hasHostileTarget",
        "weaponRange",
        "scannerRange",
        "withinStationAegis",
        "fuel",
        "flightPitch",
        "flightRoll",
        "flightYaw",
        "flightSpeed",
        "maxFlightSpeed",
        "speedFactor",
        "damage",
        "weaponRecoveryTime",
        "laserHeatLevel",
        "laserHeatLevelAft",
        "laserHeatLevelForward",
        "laserHeatLevelPort",
        "laserHeatLevelStarboard",
        "hullHeatLevel",
        "entityPersonality",
        "entityPersonalityInt",
        "numberOfScannedShips",
        "destination",
        "rangeToDestination",
        "rangeToPrimaryTarget",
        "laserColor",
        "isHulk",
        "lightsActive",
        "legalStatus",
        "velocity",
        "missileCapacity",
        "missileCount",
        "alertCondition",
        "fuelLeakRate",
        "massLocked",
        "atHyperspeed",
        "dialForwardShield",
        "dialAftShield",
        "dialMissileStatus",
        "dialFuelScoopStatus",
        "compassMode",
        "dialIdentEngaged",
        "trumbleCount",
        "tradeInFactor",
        "forwardVector",
        "rightVector",
        "upVector",
        "shaderFloat1",
        "shaderFloat2",
        "shaderInt1",
        "shaderInt2",
        "shaderVector1",
        "shaderVector2",
    };
    Entity* const objects[] = {AnEntity(),
                               sPlayer};  // any entity; a player (a ship)
    int rows = 0;
    for (Entity* object : objects) {
      for (const char* name : kNames) {
        OOShaderMemberBinding binding = {};
        const bool byRow = EntityShaderMemberBindingFor(object, name, &binding);
        if (byRow) {
          OO_CHECK(binding.target == object);
          rows++;
        }
      }
    }
    OO_CHECK(rows > 0);
    OO_CHECK(Binding(AnEntity(), "laserColor").get == nullptr);
    OO_CHECK(Binding(AnEntity(), "airColorAsVector").get ==
             nullptr);  // a planet's only
    OO_CHECK(Binding(AnEntity(), "cameraRelativePosition").type ==
             kOOShaderUniformTypeVector);
    OO_CHECK(Binding(AnEntity(), "fogUniform").type ==
             kOOShaderUniformTypeColor);
    OO_CHECK(Binding(sPlayer, "tradeInFactor").type == kOOShaderUniformTypeInt);
    OO_CHECK(BoundInt(sPlayer, "tradeInFactor") == sPlayer->tradeInFactor());
  }
}

OO_TEST_MAIN()
