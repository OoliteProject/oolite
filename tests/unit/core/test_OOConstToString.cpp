/*	test_OOConstToString.mm
        Unit tests for the OOConstToString functions that message converted
   classes. OOConstToString.mm has no class; it calls OOEquipmentType and
   OOCommodityMarket members and sends to UNIVERSE.

        Pinned: a weapon type's identifier (none for no weapon, "EQ_WEAPON_NONE"
   for the string form), the sloppy lookup that tries an "EQ_" prefix and falls
   back to EQ_WEAPON_NONE, its strict, string and legacy (save-game number)
   forms, and the mass unit of a commodity in the universe's market (tons when
   there is no market or no such good).

        The game around them is replaced, as in test_OOEquipmentType: UNIVERSE
   hands out the equipment data, the descriptions and a market; the cache
   manager, script loader, player and standards functions are the test's.
   OOEquipmentType, OOCommodityMarket and OOColor are the game's own. Run:
   tests/run.sh unit
*/

#include <cstdlib>
#include <string>

#include "OOCommodityMarket.h"
#include "OOConstToString.h"
#include "OOEquipmentType.h"
#include "OOStringExpander.h"
#include "oo_test.hpp"

// ShipEntity.h's declarations (it imports the whole game).
typedef OOEquipmentType* OOWeaponType;
std::optional<std::string> OOEquipmentIdentifierFromWeaponType(
    OOWeaponType weapon);
OOWeaponType OOWeaponTypeFromEquipmentIdentifierSloppy(
    const std::string& string);
OOWeaponType OOWeaponTypeFromEquipmentIdentifierStrict(
    const std::string& string);
OOWeaponType OOWeaponTypeFromEquipmentIdentifierLegacy(
    const std::string& string);
std::optional<std::string> OOStringFromWeaponType(OOWeaponType weapon);
OOWeaponType OOWeaponTypeFromString(const std::string& string);

// --- The game around the functions
// -----------------------------------------------------------

namespace {

oo::PList Item(int techLevel, int price, const char* name, const char* key) {
  return oo::PList(oo::PList::Array{oo::PList(techLevel), oo::PList(price),
                                    oo::PList(name), oo::PList(key),
                                    oo::PList("about it")});
}

oo::PList EquipmentData() {
  return oo::PList(oo::PList::Array{
      Item(1, 0, "No weapon", "EQ_WEAPON_NONE"),
      Item(2, 4000, "Pulse laser", "EQ_WEAPON_PULSE_LASER"),
      Item(5, 10000, "Beam laser", "EQ_WEAPON_BEAM_LASER"),
      Item(3, 300, "Fuel", "EQ_FUEL"),
      Item(4, 500, "Laser without prefix", "LASER_WITHOUT_PREFIX"),
  });
}

oo::PList Good(
    std::initializer_list<std::pair<const char*, oo::PList>> entries) {
  oo::PList::Dict dict;
  for (const auto& [key, value] : entries) dict[key] = value;
  return oo::PList(std::move(dict));
}

}  // namespace

#include "UniverseStandIn.h"

// The universe as the code under test sees it: a stand-in for the C++ class
// with the header's names and signatures. It answers virtual members, so it has
// the game's vtable (UniverseStandIn.h) and StandInUniverse overrides them.
class Universe : public oo::Object {
 public:
  OO_UNIVERSE_STAND_IN_VIRTUAL_MEMBERS

  std::shared_ptr<OOCommodityMarket> market;

  oo::PList getEquipmentData();
  oo::PList getEquipmentDataOutfitting();
  ::OOCommodityMarket* getCommodityMarket();
};

class StandInUniverse : public Universe {
 public:
  const oo::PList* descriptions() override {
    static const oo::PList descriptions = oo::PList(oo::PList::Dict{});
    return &descriptions;
  }
  std::optional<std::string> descriptionForKey(
      const std::string& /*key*/) override {
    return std::nullopt;
  }
};

oo::PList Universe::getEquipmentData() { return EquipmentData(); }
oo::PList Universe::getEquipmentDataOutfitting() { return EquipmentData(); }
::OOCommodityMarket* Universe::getCommodityMarket() { return market.get(); }

Universe* gSharedUniverse = nullptr;

// The mass-unit symbols, as descriptions.plist spells them.
std::string OOLookUpDescriptionPRIV(const std::string& key) {
  if (key == "cargo-tons-symbol") return "t";
  if (key == "cargo-kilograms-symbol") return "kg";
  if (key == "cargo-grams-symbol") return "g";
  return key;
}

// The expander (a whole-game unit); the functions pinned here never expand.
std::optional<std::string> OOExpandDescriptionString(
    Random_Seed /*seed*/, const std::string& string,
    const oo::PList& /*overrides*/, const oo::PList& /*legacyLocals*/,
    const std::optional<std::string>& /*systemName*/,
    OOExpandOptions /*options*/) {
  return string;
}

Random_Seed OOStringExpanderDefaultRandomSeed(void) { return Random_Seed(); }

#include "OOCacheManager.h"

// The cache manager: a C++ stand-in.
OOCacheManager* OOCacheManager::sharedCache() {
  static OOCacheManager* shared = new OOCacheManager;
  return shared;
}
OOCacheManager::~OOCacheManager() {}
void OOCacheManager::setPList(const oo::PList& value, const std::string& key,
                              const std::string& cache) {
  (void)value;
  (void)key;
  (void)cache;
}

#include "OOScript.h"

// OOScript's members that OOEquipmentType.mm calls, and the rest of its
// virtual members, for the vtable.
std::optional<std::string> OOScript::descriptionComponents() {
  return std::nullopt;
}
std::optional<std::string> OOScript::name() { return std::nullopt; }
std::optional<std::string> OOScript::scriptDescription() {
  return std::nullopt;
}
std::optional<std::string> OOScript::version() { return std::nullopt; }
bool OOScript::requiresTickle() { return false; }
void OOScript::runWithTarget(Entity*) {}
bool OOScript::callMethod(JSAtom, JSContext*, JSValueConst*, int, JSValue*) {
  return false;
}
std::string OOScript::className() const { return "OOScript"; }
std::string OOScript::description() const { return "<OOScript>"; }
JSValue OOScript::jsValueInContext(JSContext*) {
  std::abort();
}  // never reached (no engine is linked)
void OOScript::clearJSSelf(JSValueConst) {}
void OOScriptAutorelease(std::shared_ptr<OOScript>) {}
std::shared_ptr<OOScript> OOScript::jsScriptFromFileNamed(const std::string&,
                                                  const oo::PList&) {
  return nullptr;
}

// PLAYER: the members the code under test calls, declared as PlayerEntity.h
// declares them (the test imports no game header that defines the class), with
// the same answers.
class PlayerEntity {
 public:
  oo::PList processKeyCode(const oo::PList& key_def);
  std::optional<std::string> validateKey(const std::string& key,
                                         const oo::PList& check_keys);
  oo::PList missionVariableForKey(const std::string& key);
};

oo::PList PlayerEntity::processKeyCode(const oo::PList& key_def) {
  return key_def;
}
std::optional<std::string> PlayerEntity::validateKey(
    const std::string& /*key*/, const oo::PList& /*check_keys*/) {
  return std::nullopt;
}
oo::PList PlayerEntity::missionVariableForKey(const std::string& /*key*/) {
  return oo::PList();
}

PlayerEntity* gOOPlayer = nullptr;

void OOStandardsDeprecated(const std::string& /*message*/) {}

bool OOEnforceStandards(void) { return false; }

oo::PList OOSanitizeLegacyScriptConditions(
    const oo::PList& conditions,
    const std::optional<std::string>& /*context*/) {
  return conditions;
}

namespace {

void LoadEquipment() {
  if (gSharedUniverse == nullptr) gSharedUniverse = new StandInUniverse();
  if (gOOPlayer == nullptr) gOOPlayer = new PlayerEntity;  // never deleted
  OOEquipmentType::loadEquipment();
}

std::string IdentifierOf(OOWeaponType weapon) {
  return weapon != nullptr ? weapon->identifier().value_or("-") : "nil";
}

}  // namespace

// --- Weapon types
// ----------------------------------------------------------------------------

OO_TEST(weaponTypeIdentifiers) {
  {
    LoadEquipment();
    OOWeaponType pulse =
        OOEquipmentType::equipmentTypeWithIdentifier("EQ_WEAPON_PULSE_LASER")
            .get();
    OO_CHECK(pulse != nullptr);

    OO_CHECK(OOStringFromWeaponType(pulse) ==
             std::optional<std::string>("EQ_WEAPON_PULSE_LASER"));
    OO_CHECK(OOStringFromWeaponType(nullptr) ==
             std::optional<std::string>("EQ_WEAPON_NONE"));

    OO_CHECK(OOEquipmentIdentifierFromWeaponType(pulse) ==
             std::optional<std::string>("EQ_WEAPON_PULSE_LASER"));
    // A message to nil answered a zeroed std::optional: no identifier.
    OO_CHECK(OOEquipmentIdentifierFromWeaponType(nullptr) == std::nullopt);
  }
}

OO_TEST(sloppyLookUp) {
  {
    LoadEquipment();
    OOWeaponType pulse =
        OOEquipmentType::equipmentTypeWithIdentifier("EQ_WEAPON_PULSE_LASER")
            .get();
    OOWeaponType none =
        OOEquipmentType::equipmentTypeWithIdentifier("EQ_WEAPON_NONE").get();
    OO_CHECK(pulse != nullptr && none != nullptr && pulse != none);

    // The identifier itself, then with "EQ_" put in front, then EQ_WEAPON_NONE.
    OO_CHECK(OOWeaponTypeFromEquipmentIdentifierSloppy(
                 "EQ_WEAPON_PULSE_LASER") == pulse);
    OO_CHECK(OOWeaponTypeFromEquipmentIdentifierSloppy(
                 "WEAPON_PULSE_LASER") == pulse);
    OO_CHECK(
        OOWeaponTypeFromEquipmentIdentifierSloppy("LASER_WITHOUT_PREFIX") ==
        OOEquipmentType::equipmentTypeWithIdentifier("LASER_WITHOUT_PREFIX")
            .get());
    OO_CHECK(OOWeaponTypeFromEquipmentIdentifierSloppy("EQ_FUEL") ==
             OOEquipmentType::equipmentTypeWithIdentifier("EQ_FUEL").get());
    OO_CHECK(OOWeaponTypeFromEquipmentIdentifierSloppy("PULSE_LASER") ==
             none);
    OO_CHECK(OOWeaponTypeFromEquipmentIdentifierSloppy(
                 "EQ_NO_SUCH_THING") == none);
    OO_CHECK(OOWeaponTypeFromEquipmentIdentifierSloppy("") == none);

    // The other spellings are the same look-up.
    OO_CHECK(
        OOWeaponTypeFromEquipmentIdentifierStrict("WEAPON_BEAM_LASER") ==
        OOEquipmentType::equipmentTypeWithIdentifier("EQ_WEAPON_BEAM_LASER")
            .get());
    OO_CHECK(OOWeaponTypeFromString("WEAPON_PULSE_LASER") == pulse);
    OO_CHECK(OOWeaponTypeFromString("nonsense") == none);

    // Save games stored weapons as numbers.
    OO_CHECK(OOWeaponTypeFromEquipmentIdentifierLegacy("2") == pulse);
    OO_CHECK(IdentifierOf(OOWeaponTypeFromEquipmentIdentifierLegacy("3")) ==
             "EQ_WEAPON_BEAM_LASER");
    OO_CHECK(OOWeaponTypeFromEquipmentIdentifierLegacy("4") ==
             none);  // no mining laser here
    OO_CHECK(OOWeaponTypeFromEquipmentIdentifierLegacy("EQ_FUEL") ==
             OOEquipmentType::equipmentTypeWithIdentifier("EQ_FUEL").get());
  }
}

// --- Mass units
// ------------------------------------------------------------------------------

OO_TEST(massUnitOfACommodity) {
  {
    LoadEquipment();

    // No market: a message to nil answered 0, OOMassUnit::kTons.
    gSharedUniverse->market = nullptr;
    OO_CHECK(DisplayStringForMassUnitForCommodity("gold") ==
             std::optional<std::string>("t"));

    std::shared_ptr<OOCommodityMarket> market = oo::makeShared<OOCommodityMarket>();
    market->setGood("gold", Good({{"name", oo::PList("Gold")},
                                  {"quantity_unit", oo::PList(1)}}));
    market->setGood("gems", Good({{"name", oo::PList("Gem-stones")},
                                  {"quantity_unit", oo::PList(2)}}));
    market->setGood("food", Good({{"name", oo::PList("Food")},
                                  {"quantity_unit", oo::PList(0)}}));
    market->setGood("alloys", Good({{"name", oo::PList("Alloys")},
                                    {"quantity_unit", oo::PList(7)}}));
    gSharedUniverse->market = market;

    OO_CHECK(DisplayStringForMassUnitForCommodity("gold") ==
             std::optional<std::string>("kg"));
    OO_CHECK(DisplayStringForMassUnitForCommodity("gems") ==
             std::optional<std::string>("g"));
    OO_CHECK(DisplayStringForMassUnitForCommodity("food") ==
             std::optional<std::string>("t"));
    OO_CHECK(DisplayStringForMassUnitForCommodity("unobtainium") ==
             std::optional<std::string>("t"));
    OO_CHECK(DisplayStringForMassUnitForCommodity("alloys") ==
             DisplayStringForMassUnit(OOMassUnit::kUnknown));

    gSharedUniverse->market = nullptr;
  }
}

// The JS glue of OOEquipmentType (OOJSPrivateObject), defined in
// OOJSEquipmentInfo.mm, which this test does not link: the vtable names these.
JSValue OOEquipmentType::jsValueInContext(JSContext*) { return JS_UNDEFINED; }
void OOEquipmentType::clearJSSelf(JSValueConst) {}
std::optional<std::string> OOEquipmentType::jsDescription() {
  return std::nullopt;
}

OO_TEST_MAIN()
