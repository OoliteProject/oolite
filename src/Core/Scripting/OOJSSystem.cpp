/*

OOJSSystem.m (QuickJS-ng)


 Oolite
 Copyright (C) 2004-2013 Giles C Williams and contributors

 This program is free software; you can redistribute it and/or
 modify it under the terms of the GNU General Public License
 as published by the Free Software Foundation; either version 2
 of the License, or (at your option) any later version.

 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with this program; if not, write to the Free Software
 Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
 MA 02110-1301, USA.

 */

#include "OOJSSystem.h"

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <format>
#include <functional>
#include <map>
#include <optional>
#include <set>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

#include "EntityOOJavaScriptExtensions.h"
#include "OOConstToJSString.h"
#include "OOConstToString.h"
#include "OODebugStandards.h"
#include "OODescription.h"
#include "OOEntityFilterPredicate.h"
#include "OOJSEntity.h"
#include "OOJSPlayer.h"
#include "OOJSPopulatorDefinition.h"
#include "OOJSQuaternion.h"
#include "OOJSScript.h"
#include "OOJSSystemInfo.h"
#include "OOJSVector.h"
#include "OOJavaScriptEngine.h"
#include "OOPlanetEntity.h"
#include "OOSunEntity.h"  // the sun is C++
#include "PlayerEntityLegacyScriptEngine.h"
#include "PlayerEntityScriptMethods.h"
#include "ShipEntity.h"
#include "StationEntity.h"
#include "Universe.h"
#include "oofnd/PList.hpp"
#include "oofnd/String.hpp"

static JSClassID sSystemClassID;

// Support functions for entity search methods.
static bool GetRelativeToAndRange(JSContext* context,
                                  const std::string& methodName, int* ioArgc,
                                  JSValueConst** ioArgv, Entity** outRelativeTo,
                                  double* outRange);
static std::vector<oo::EntityHold> FindJSVisibleEntities(
    EntityFilterPredicate predicate, void* parameter, Entity* relativeTo,
    double range);
static std::vector<oo::EntityHold> FindShips(EntityFilterPredicate predicate,
                                             void* parameter,
                                             Entity* relativeTo, double range);
static OOComparisonResult CompareEntitiesByDistance(Entity* a, Entity* b,
                                                    Entity* relativeTo);

static JSValue SystemAddShipsOrGroup(JSContext* context, int argc,
                                     JSValueConst* argv, bool isGroup);
static JSValue SystemAddShipsOrGroupToRoute(JSContext* context, int argc,
                                            JSValueConst* argv, bool isGroup);

static JSValue SystemGetProperty(OOJS_GETTER_ARGS);
static JSValue SystemSetProperty(OOJS_SETTER_ARGS);

static JSValue SystemToString(OOJS_NATIVE_ARGS);
static JSValue SystemAddPlanet(OOJS_NATIVE_ARGS);
static JSValue SystemAddMoon(OOJS_NATIVE_ARGS);
static JSValue SystemSendAllShipsAway(OOJS_NATIVE_ARGS);
static JSValue SystemCountShipsWithPrimaryRole(OOJS_NATIVE_ARGS);
static JSValue SystemCountShipsWithRole(OOJS_NATIVE_ARGS);
static JSValue SystemCountEntitiesWithScanClass(OOJS_NATIVE_ARGS);
static JSValue SystemShipsWithPrimaryRole(OOJS_NATIVE_ARGS);
static JSValue SystemShipsWithRole(OOJS_NATIVE_ARGS);
static JSValue SystemEntitiesWithScanClass(OOJS_NATIVE_ARGS);
static JSValue SystemFilteredEntities(OOJS_NATIVE_ARGS);

static JSValue SystemLocationFromCode(OOJS_NATIVE_ARGS);
static JSValue SystemAddShips(OOJS_NATIVE_ARGS);
static JSValue SystemAddGroup(OOJS_NATIVE_ARGS);
static JSValue SystemAddShipsToRoute(OOJS_NATIVE_ARGS);
static JSValue SystemAddGroupToRoute(OOJS_NATIVE_ARGS);
static JSValue SystemAddVisualEffect(OOJS_NATIVE_ARGS);
static JSValue SystemSetPopulator(OOJS_NATIVE_ARGS);
static JSValue SystemSetWaypoint(OOJS_NATIVE_ARGS);

static JSValue SystemLegacyAddShips(OOJS_NATIVE_ARGS);
static JSValue SystemLegacyAddSystemShips(OOJS_NATIVE_ARGS);
static JSValue SystemLegacyAddShipsAt(OOJS_NATIVE_ARGS);
static JSValue SystemLegacyAddShipsAtPrecisely(OOJS_NATIVE_ARGS);
static JSValue SystemLegacyAddShipsWithinRadius(OOJS_NATIVE_ARGS);
static JSValue SystemLegacySpawnShip(OOJS_NATIVE_ARGS);

static JSValue SystemStaticSystemNameForID(OOJS_NATIVE_ARGS);
static JSValue SystemStaticSystemIDForName(OOJS_NATIVE_ARGS);
static JSValue SystemStaticInfoForSystem(OOJS_NATIVE_ARGS);

// System has no private data and no finalizer.
static JSClassDef sSystemClass = {
    .class_name = "System",
};

namespace {

enum class SystemProperty : std::int16_t {
  // Property IDs
  kAllDemoShips,            // demo ships, array of Ship, read-only
  kAllShips,                // ships in system, array of Ship, read-only
  kAllVisualEffects,        // VEs in system, array of VEs, read-only
  kAmbientLevel,            // ambient light level, float, read/write
  kBreakPattern,            // witchspace break pattern shown
  kDescription,             // description, string, read/write
  kEconomy,                 // economy ID, integer, read/write
  kEconomyDescription,      // economy ID description, string, read-only
  kGovernment,              // government ID, integer, read/write
  kGovernmentDescription,   // government ID description, string,
                            // read-only
  kID,                      // planet number, integer, read-only
  kInfo,                    // system info dictionary, SystemInfo, read/write
  kInhabitantsDescription,  // description of inhabitant species, string,
                            // read/write
  kIsInterstellarSpace,     // is interstellar space, boolean, read-only
  kMainPlanet,              // system's main planet, Planet, read-only
  kMainStation,             // system's main station, Station, read-only
  kName,                    // name, string, read/write
  kPlanets,                 // planets in system, array of Planet, read-only
  kPopulation,              // population, integer, read/write
  kPopulatorSettings,       // populator settings, dictionary, read-only
  kProductivity,            // productivity, integer, read/write
  kPseudoRandom100,         // constant-per-system pseudorandom number in
                            // [0..100), integer, read-only
  kPseudoRandom256,         // constant-per-system pseudorandom number in
                            // [0..256), integer, read-only
  kPseudoRandomNumber,      // constant-per-system pseudorandom number in
                            // [0..1), double, read-only
  kSun,                     // system's sun, Planet, read-only
  kStations,                // list of dockable entities, read-only
  kTechLevel,               // tech level ID, integer, read/write
  kWaypoints,               // dictionary of current player waypoints, read-only
  kWormholes,               // list of active entry wormholes, read-only

};

}  // namespace

static const JSCFunctionListEntry sSystemProperties[] = {
    // JS name, getter, setter, ID
    OOJS_PROPERTY_RO("allDemoShips", SystemGetProperty,
                     SystemProperty::kAllDemoShips),
    OOJS_PROPERTY_RO("allShips", SystemGetProperty, SystemProperty::kAllShips),
    OOJS_PROPERTY_RO("allVisualEffects", SystemGetProperty,
                     SystemProperty::kAllVisualEffects),
    OOJS_PROPERTY_RW("ambientLevel", SystemGetProperty, SystemSetProperty,
                     SystemProperty::kAmbientLevel),
    OOJS_PROPERTY_RW("breakPattern", SystemGetProperty, SystemSetProperty,
                     SystemProperty::kBreakPattern),
    OOJS_PROPERTY_RW("description", SystemGetProperty, SystemSetProperty,
                     SystemProperty::kDescription),
    OOJS_PROPERTY_RW("economy", SystemGetProperty, SystemSetProperty,
                     SystemProperty::kEconomy),
    OOJS_PROPERTY_RO("economyDescription", SystemGetProperty,
                     SystemProperty::kEconomyDescription),
    OOJS_PROPERTY_RW("government", SystemGetProperty, SystemSetProperty,
                     SystemProperty::kGovernment),
    OOJS_PROPERTY_RO("governmentDescription", SystemGetProperty,
                     SystemProperty::kGovernmentDescription),
    OOJS_PROPERTY_RO("ID", SystemGetProperty, SystemProperty::kID),
    OOJS_PROPERTY_RO("info", SystemGetProperty, SystemProperty::kInfo),
    OOJS_PROPERTY_RW("inhabitantsDescription", SystemGetProperty,
                     SystemSetProperty,
                     SystemProperty::kInhabitantsDescription),
    OOJS_PROPERTY_RO("isInterstellarSpace", SystemGetProperty,
                     SystemProperty::kIsInterstellarSpace),
    OOJS_PROPERTY_RO("mainPlanet", SystemGetProperty,
                     SystemProperty::kMainPlanet),
    OOJS_PROPERTY_RO("mainStation", SystemGetProperty,
                     SystemProperty::kMainStation),
    OOJS_PROPERTY_RW("name", SystemGetProperty, SystemSetProperty,
                     SystemProperty::kName),
    OOJS_PROPERTY_RO("planets", SystemGetProperty, SystemProperty::kPlanets),
    OOJS_PROPERTY_RW("population", SystemGetProperty, SystemSetProperty,
                     SystemProperty::kPopulation),
    OOJS_PROPERTY_RO("populatorSettings", SystemGetProperty,
                     SystemProperty::kPopulatorSettings),
    OOJS_PROPERTY_RW("productivity", SystemGetProperty, SystemSetProperty,
                     SystemProperty::kProductivity),
    OOJS_PROPERTY_RO("pseudoRandom100", SystemGetProperty,
                     SystemProperty::kPseudoRandom100),
    OOJS_PROPERTY_RO("pseudoRandom256", SystemGetProperty,
                     SystemProperty::kPseudoRandom256),
    OOJS_PROPERTY_RO("pseudoRandomNumber", SystemGetProperty,
                     SystemProperty::kPseudoRandomNumber),
    OOJS_PROPERTY_RO("stations", SystemGetProperty, SystemProperty::kStations),
    OOJS_PROPERTY_RO("sun", SystemGetProperty, SystemProperty::kSun),
    OOJS_PROPERTY_RW("techLevel", SystemGetProperty, SystemSetProperty,
                     SystemProperty::kTechLevel),
    OOJS_PROPERTY_RO("waypoints", SystemGetProperty,
                     SystemProperty::kWaypoints),
    OOJS_PROPERTY_RO("wormholes", SystemGetProperty,
                     SystemProperty::kWormholes),
};

static const JSCFunctionListEntry sSystemMethods[] = {
    // JS name, min args, function
    JS_CFUNC_DEF("toString", 0, SystemToString),
    JS_CFUNC_DEF("addGroup", 3, SystemAddGroup),
    JS_CFUNC_DEF("addGroupToRoute", 2, SystemAddGroupToRoute),
    JS_CFUNC_DEF("addMoon", 1, SystemAddMoon),
    JS_CFUNC_DEF("addPlanet", 1, SystemAddPlanet),
    JS_CFUNC_DEF("addShips", 3, SystemAddShips),
    JS_CFUNC_DEF("addShipsToRoute", 2, SystemAddShipsToRoute),
    JS_CFUNC_DEF("addVisualEffect", 2, SystemAddVisualEffect),
    JS_CFUNC_DEF("countEntitiesWithScanClass", 1,
                 SystemCountEntitiesWithScanClass),
    JS_CFUNC_DEF("countShipsWithPrimaryRole", 1,
                 SystemCountShipsWithPrimaryRole),
    JS_CFUNC_DEF("countShipsWithRole", 1, SystemCountShipsWithRole),
    JS_CFUNC_DEF("entitiesWithScanClass", 1, SystemEntitiesWithScanClass),
    JS_CFUNC_DEF("filteredEntities", 2, SystemFilteredEntities),
    JS_CFUNC_DEF("locationFromCode", 1, SystemLocationFromCode),
    // scrambledPseudoRandomNumber is implemented in oolite-global-prefix.js
    JS_CFUNC_DEF("sendAllShipsAway", 1, SystemSendAllShipsAway),
    JS_CFUNC_DEF("setPopulator", 2, SystemSetPopulator),
    JS_CFUNC_DEF("setWaypoint", 4, SystemSetWaypoint),
    JS_CFUNC_DEF("shipsWithPrimaryRole", 1, SystemShipsWithPrimaryRole),
    JS_CFUNC_DEF("shipsWithRole", 1, SystemShipsWithRole),

    JS_CFUNC_DEF("legacy_addShips", 2, SystemLegacyAddShips),
    JS_CFUNC_DEF("legacy_addSystemShips", 3, SystemLegacyAddSystemShips),
    JS_CFUNC_DEF("legacy_addShipsAt", 6, SystemLegacyAddShipsAt),
    JS_CFUNC_DEF("legacy_addShipsAtPrecisely", 6,
                 SystemLegacyAddShipsAtPrecisely),
    JS_CFUNC_DEF("legacy_addShipsWithinRadius", 7,
                 SystemLegacyAddShipsWithinRadius),
    JS_CFUNC_DEF("legacy_spawnShip", 1, SystemLegacySpawnShip),
};

static const JSCFunctionListEntry sSystemStaticMethods[] = {
    // JS name, min args, function
    JS_CFUNC_DEF("infoForSystem", 2, SystemStaticInfoForSystem),
    JS_CFUNC_DEF("systemIDForName", 1, SystemStaticSystemIDForName),
    JS_CFUNC_DEF("systemNameForID", 1, SystemStaticSystemNameForID),
};

void InitOOJSSystem(JSContext* context, JSValueConst global) {
  OOJSRegisterClass(&sSystemClassID, &sSystemClass);
  OOJSInitClass(context, global, sSystemClassID, JS_UNDEFINED,
                OOJSUnconstructableConstruct, 0, sSystemProperties,
                OOJS_COUNT(sSystemProperties), sSystemMethods,
                OOJS_COUNT(sSystemMethods), sSystemStaticMethods,
                OOJS_COUNT(sSystemStaticMethods));

  // Create system object as a property of the global object.
  JSValue systemObject =
      JS_NewObjectClass(context, static_cast<int>(sSystemClassID));
  JS_DefinePropertyValueStr(context, global, "system", systemObject,
                            OOJS_PROP_READONLY);
}

static JSValue SystemGetProperty(OOJS_GETTER_ARGS) {
  OOJS_NATIVE_ENTER(context)

  oo::PList result;  // null maps to null
  PlayerEntity* player = nullptr;
  bool handled = false;

  player = OOPlayerForScripting();

  // Handle cases which don't require systemData.
  switch (static_cast<SystemProperty>(magic)) {
    using enum SystemProperty;
    case kID:
      return JS_NewInt32(context,
                         player != nullptr ? player->currentSystemID() : 0);

    case kIsInterstellarSpace:
      return OOJSValueFromBOOL(
          (UNIVERSE != nullptr ? UNIVERSE->inInterstellarSpace() : false));

    case kMainStation:
      result = oo::EntityObjectNode(
          (UNIVERSE != nullptr ? UNIVERSE->station() : nullptr));
      handled = true;
      break;

    case kMainPlanet:
      result = oo::EntityObjectNode(
          (UNIVERSE != nullptr ? UNIVERSE->planet() : nullptr));
      handled = true;
      break;

    case kSun:
      result = oo::EntityObjectNode(
          (UNIVERSE != nullptr ? UNIVERSE->sun() : nullptr));
      handled = true;
      break;

    case kPlanets: {
      std::vector<oo::EntityHold> visible;  // the planets (their objects held)
      for (const auto& r :
           (UNIVERSE != nullptr ? UNIVERSE->planets()
                                : std::vector<oo::EntityHold>())) {
        if (!OOJSEntityIsVisibleToScripts(r.get()))
          continue;  // the C++ planet's answer
        visible.push_back(r);
      }
      result = oo::EntityNodesFrom(visible);
      handled = true;
      break;
    }

    case kStations:
      result = oo::EntityNodesFrom((UNIVERSE != nullptr
                                        ? UNIVERSE->stations()
                                        : std::vector<oo::EntityHold>()));
      handled = true;
      break;

    case kWaypoints: {
      // An immutable dictionary of the waypoints by key, as -currentWaypoints
      // built it.
      oo::PList::Dict waypoints;
      for (const auto& [key, waypoint] :
           (UNIVERSE != nullptr
                ? UNIVERSE->currentWaypoints()
                : std::map<std::string, oo::EntityHold, std::less<>>())) {
        if (waypoint.get() != nullptr)
          waypoints[key] = oo::EntityObjectNode(waypoint.get());
      }
      result = oo::PList(std::move(waypoints));
      handled = true;
      break;
    }

    case kWormholes:
      result = oo::EntityNodesFrom((UNIVERSE != nullptr
                                        ? UNIVERSE->wormholes()
                                        : std::vector<oo::EntityHold>()));
      handled = true;
      break;

    case kAllShips:
      OOJS_BEGIN_FULL_NATIVE(context)
      result = oo::EntityNodesFrom(
          (UNIVERSE != nullptr ? UNIVERSE->findShipsMatchingPredicate(
                                     JSEntityIsJavaScriptSearchablePredicate,
                                     nullptr, -1, nullptr)
                               : std::vector<oo::EntityHold>()));
      OOJS_END_FULL_NATIVE
      handled = true;
      break;

    case kAllDemoShips:
      OOJS_BEGIN_FULL_NATIVE(context)
      result = oo::EntityNodesFrom(
          (UNIVERSE != nullptr
               ? UNIVERSE->findShipsMatchingPredicate(
                     JSEntityIsDemoShipPredicate, nullptr, -1, nullptr)
               : std::vector<oo::EntityHold>()));
      OOJS_END_FULL_NATIVE
      handled = true;
      break;

    case kAllVisualEffects:
      OOJS_BEGIN_FULL_NATIVE(context)
      result = oo::EntityNodesFrom(
          (UNIVERSE != nullptr ? UNIVERSE->findVisualEffectsMatchingPredicate(
                                     JSEntityIsJavaScriptSearchablePredicate,
                                     nullptr, -1, nullptr)
                               : std::vector<oo::EntityHold>()));
      OOJS_END_FULL_NATIVE
      handled = true;
      break;

    case kAmbientLevel:
      return JS_NewNumber(
          context,
          (UNIVERSE != nullptr ? UNIVERSE->getAmbientLightLevel() : 0.0f));

    case kInfo:
      return GetJSSystemInfoForSystem(
          context,
          (player != nullptr ? player->currentGalaxyID() : OOGalaxyID{}),
          (player != nullptr ? player->currentSystemID() : 0));

    case kPseudoRandomNumber:
      return JS_NewNumber(
          context,
          (player != nullptr ? player->systemPseudoRandomFloat() : 0.0));

    case kPseudoRandom100:
      return JS_NewInt32(context, player != nullptr
                                      ? player->systemPseudoRandom100()
                                      : unsigned{});

    case kPseudoRandom256:
      return JS_NewInt32(context, player != nullptr
                                      ? player->systemPseudoRandom256()
                                      : unsigned{});

    case kBreakPattern:
      return OOJSValueFromBOOL(
          (UNIVERSE != nullptr ? UNIVERSE->witchspaceBreakPattern() : false));

    case kPopulatorSettings:
      return OOJSValueFromPList(
          context, (UNIVERSE != nullptr ? UNIVERSE->getPopulatorSettings()
                                        : oo::PList()));

    default:  // the properties that need the system's data: below
      break;
  }

  if (!handled) {
    // Handle cases which do require systemData.
    if (EXPECT(
            !(UNIVERSE != nullptr ? UNIVERSE->inInterstellarSpace() : false))) {
      const oo::PList systemData =
          (UNIVERSE != nullptr ? UNIVERSE->currentSystemData() : oo::PList());

      switch (static_cast<SystemProperty>(magic)) {
        using enum SystemProperty;
        case kName:
          if (const oo::PList* entry = systemData.find(KEY_NAME))
            result = *entry;  // -objectForKey:
          break;

        case kDescription:
          if (const oo::PList* entry = systemData.find(KEY_DESCRIPTION))
            result = *entry;  // -objectForKey:
          break;

        case kInhabitantsDescription:
          if (const oo::PList* entry = systemData.find(KEY_INHABITANTS))
            result = *entry;  // -objectForKey:
          break;

        case kGovernment:
          return JS_NewInt32(context,
                             systemData.get<int>(std::string(KEY_GOVERNMENT)));

        case kGovernmentDescription:
          result =
              oo::PList(cxx_OODisplayStringFromGovernmentID(
                            systemData.get<int>(std::string(KEY_GOVERNMENT)))
                            .value_or(std::string(OO_DESC("not-applicable"))));
          break;

        case kEconomy:
          return JS_NewInt32(context,
                             systemData.get<int>(std::string(KEY_ECONOMY)));

        case kEconomyDescription:
          result =
              oo::PList(cxx_OODisplayStringFromEconomyID(
                            systemData.get<int>(std::string(KEY_ECONOMY)))
                            .value_or(std::string(OO_DESC("not-applicable"))));
          break;

        case kTechLevel:
          return JS_NewInt32(context,
                             systemData.get<int>(std::string(KEY_TECHLEVEL)));

        case kPopulation:
          return JS_NewInt32(context,
                             systemData.get<int>(std::string(KEY_POPULATION)));

        case kProductivity:
          return JS_NewInt32(
              context, systemData.get<int>(std::string(KEY_PRODUCTIVITY)));

        default:
          OOJSReportBadPropertySelector(context, thisObj, magic,
                                        sSystemProperties,
                                        OOJS_COUNT(sSystemProperties));
          return OOJSNativeFailure(context);
      }
    } else {
      // if in interstellar space, systemData values are null & void!
      switch (static_cast<SystemProperty>(magic)) {
        using enum SystemProperty;
        case kName:
          result = oo::PList(std::string(OO_DESC("interstellar-space")));
          break;

        case kDescription:
          result = oo::PList(std::string());
          break;

        case kInhabitantsDescription:
          result = oo::PList(std::string(OO_DESC("not-applicable")));
          break;

        case kGovernment:
          return JS_NewInt32(context, -1);

        case kGovernmentDescription:
          result = oo::PList(std::string(OO_DESC("not-applicable")));
          break;

        case kEconomy:
          return JS_NewInt32(context, -1);

        case kEconomyDescription:
          result = oo::PList(std::string(OO_DESC("not-applicable")));
          break;

        case kTechLevel:
          return JS_NewInt32(context, -1);

        case kPopulation:
          return JS_NewInt32(context, 0);

        case kProductivity:
          return JS_NewInt32(context, 0);

        default:
          OOJSReportBadPropertySelector(context, thisObj, magic,
                                        sSystemProperties,
                                        OOJS_COUNT(sSystemProperties));
          return OOJSNativeFailure(context);
      }
    }
  }

  return OOJSValueFromPList(context, result);

  OOJS_NATIVE_EXIT
}

static JSValue SystemSetProperty(OOJS_SETTER_ARGS) {
  OOJS_NATIVE_ENTER(context)

  PlayerEntity* player = nullptr;
  OOGalaxyID galaxy;
  OOSystemID system;
  std::optional<std::string> stringValue;
  oo::PList manifest;  // the running script's manifest identifier, handed on as
                       // it was read
  double fValue;
  int32_t iValue;
  int bValue;

  player = OOPlayerForScripting();

  galaxy = (player != nullptr ? player->currentGalaxyID() : OOGalaxyID{});
  system = (player != nullptr ? player->currentSystemID() : 0);

  switch (static_cast<SystemProperty>(magic)) {
    using enum SystemProperty;
    case kAmbientLevel:
      if (JS_ToFloat64(context, &fValue, value) == 0) {
        if (UNIVERSE != nullptr) UNIVERSE->setAmbientLightLevel(fValue);
        if (UNIVERSE != nullptr) UNIVERSE->setLighting();
        return JS_UNDEFINED;
      }
      break;

    case kBreakPattern:
      if ((bValue = JS_ToBool(context, value)) >= 0) {
        if (UNIVERSE != nullptr) UNIVERSE->setWitchspaceBreakPattern(bValue);
        return JS_UNDEFINED;
      }

      break;
    default: {
    }  // do nothing yet
  }

  if (system == -1)
    return JS_UNDEFINED;  // Can't change anything else in interstellar space.

  // The running script: null when no script runs.
  OOJSScript* runningScript = OOJSScript::currentlyRunningScript();
  manifest = (runningScript != nullptr)
                 ? runningScript->propertyNamed(kLocalManifestProperty)
                 : oo::PList();
  // the identifier as -fromManifest: read it: a string, else none
  const std::optional<std::string> manifestID =
      manifest.isString()
          ? std::optional<std::string>(*manifest.getIf<std::string>())
          : std::nullopt;

  switch (static_cast<SystemProperty>(magic)) {
    using enum SystemProperty;
    case kName:
      stringValue = cxx_OOStringFromJSValue(context, value);
      if (stringValue.has_value()) {
        if (UNIVERSE != nullptr)
          UNIVERSE->setSystemDataForGalaxy(
              galaxy, system, std::string(KEY_NAME), oo::PList(*stringValue),
              manifestID, OOSystemLayer::kOXPDynamic);
        return JS_UNDEFINED;
      }
      break;

    case kDescription:
      stringValue = cxx_OOStringFromJSValue(context, value);
      if (stringValue.has_value()) {
        if (UNIVERSE != nullptr)
          UNIVERSE->setSystemDataForGalaxy(
              galaxy, system, std::string(KEY_DESCRIPTION),
              oo::PList(*stringValue), manifestID, OOSystemLayer::kOXPDynamic);
        return JS_UNDEFINED;
      }
      break;

    case kInhabitantsDescription:
      stringValue = cxx_OOStringFromJSValue(context, value);
      if (stringValue.has_value()) {
        if (UNIVERSE != nullptr)
          UNIVERSE->setSystemDataForGalaxy(
              galaxy, system, std::string(KEY_INHABITANTS),
              oo::PList(*stringValue), manifestID, OOSystemLayer::kOXPDynamic);
        return JS_UNDEFINED;
      }
      break;

    case kGovernment:
      if (OOJSValueToInt32(context, value, &iValue)) {
        if (iValue < 0) iValue = 0;
        if (7 < iValue) iValue = 7;
        if (UNIVERSE != nullptr)
          UNIVERSE->setSystemDataForGalaxy(
              galaxy, system, std::string(KEY_GOVERNMENT),
              oo::PList::signedInteger(iValue), manifestID,
              OOSystemLayer::kOXPDynamic);
        return JS_UNDEFINED;
      }
      break;

    case kEconomy:
      if (OOJSValueToInt32(context, value, &iValue)) {
        if (iValue < 0) iValue = 0;
        if (7 < iValue) iValue = 7;
        if (UNIVERSE != nullptr)
          UNIVERSE->setSystemDataForGalaxy(
              galaxy, system, std::string(KEY_ECONOMY),
              oo::PList::signedInteger(iValue), manifestID,
              OOSystemLayer::kOXPDynamic);
        return JS_UNDEFINED;
      }
      break;

    case kTechLevel:
      if (OOJSValueToInt32(context, value, &iValue)) {
        if (iValue < 0) iValue = 0;
        if (15 < iValue) iValue = 15;
        if (UNIVERSE != nullptr)
          UNIVERSE->setSystemDataForGalaxy(
              galaxy, system, std::string(KEY_TECHLEVEL),
              oo::PList::signedInteger(iValue), manifestID,
              OOSystemLayer::kOXPDynamic);
        return JS_UNDEFINED;
      }
      break;

    case kPopulation:
      if (OOJSValueToInt32(context, value, &iValue)) {
        if (UNIVERSE != nullptr)
          UNIVERSE->setSystemDataForGalaxy(
              galaxy, system, std::string(KEY_POPULATION),
              oo::PList::signedInteger(iValue), manifestID,
              OOSystemLayer::kOXPDynamic);
        return JS_UNDEFINED;
      }
      break;

    case kProductivity:
      if (OOJSValueToInt32(context, value, &iValue)) {
        if (UNIVERSE != nullptr)
          UNIVERSE->setSystemDataForGalaxy(
              galaxy, system, std::string(KEY_PRODUCTIVITY),
              oo::PList::signedInteger(iValue), manifestID,
              OOSystemLayer::kOXPDynamic);
        return JS_UNDEFINED;
      }
      break;

    default:
      OOJSReportBadPropertySelector(context, thisObj, magic, sSystemProperties,
                                    OOJS_COUNT(sSystemProperties));
      return OOJSNativeFailure(context);
  }

  OOJSReportBadPropertyValue(context, thisObj, magic, sSystemProperties,
                             OOJS_COUNT(sSystemProperties), value);
  return OOJSNativeFailure(context);

  OOJS_NATIVE_EXIT
}

// *** Methods ***

// toString() : String
static JSValue SystemToString(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  PlayerEntity* player = OOPlayerForScripting();
  std::string systemDesc;

  const oo::PList systemData =
      (UNIVERSE != nullptr ? UNIVERSE->currentSystemData() : oo::PList());
  const oo::PList* systemName =
      systemData.find(KEY_NAME);  // -objectForKey:; "(null)" for none
  systemDesc = std::format(
      "[System {}:{} \"{}\"]",
      (player != nullptr ? player->currentGalaxyID() : OOGalaxyID{}),
      static_cast<unsigned int>(
          (player != nullptr ? player->currentSystemID() : 0)),
      oo::DescriptionOf(systemName != nullptr ? *systemName : oo::PList()));
  OOJS_RETURN_PLIST(oo::PList(systemDesc));

  OOJS_NATIVE_EXIT
}

// addPlanet(key : String) : Planet
static JSValue SystemAddPlanet(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  PlayerEntity* player = OOPlayerForScripting();
  std::optional<std::string> key;
  OOPlanetEntity* planet = nullptr;

  if (argc > 0) key = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
  if (EXPECT_NOT(!key.has_value())) {
    cxx_OOJSReportBadArguments(context, "System", "addPlanet", MIN(argc, 1),
                               OOJS_ARGV, std::nullopt, "string (planet key)");
    return OOJSNativeFailure(context);
  }

  OOJS_BEGIN_FULL_NATIVE(context)
  planet = (player != nullptr ? player->addPlanetEntity(*key)
                              : static_cast<OOPlanetEntity*>(nullptr));
  OOJS_END_FULL_NATIVE

  OOJS_RETURN(
      OOJSValueFromCxxObject(context, planet));  // the C++ planet's JS value

  OOJS_NATIVE_EXIT
}

// addMoon(key : String) : Planet
static JSValue SystemAddMoon(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  PlayerEntity* player = OOPlayerForScripting();
  std::optional<std::string> key;
  OOPlanetEntity* planet = nullptr;

  if (argc > 0) key = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
  if (EXPECT_NOT(!key.has_value())) {
    cxx_OOJSReportBadArguments(context, "System", "addMoon", MIN(argc, 1),
                               OOJS_ARGV, std::nullopt, "string (planet key)");
    return OOJSNativeFailure(context);
  }

  OOJS_BEGIN_FULL_NATIVE(context)
  planet = (player != nullptr ? player->addMoonEntity(*key)
                              : static_cast<OOPlanetEntity*>(nullptr));
  OOJS_END_FULL_NATIVE

  OOJS_RETURN(
      OOJSValueFromCxxObject(context, planet));  // the C++ planet's JS value

  OOJS_NATIVE_EXIT
}

// sendAllShipsAway()
static JSValue SystemSendAllShipsAway(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  PlayerEntity* player = OOPlayerForScripting();

  if (player != nullptr) player->sendAllShipsAway();
  OOJS_RETURN_VOID;

  OOJS_NATIVE_EXIT
}

// countShipsWithPrimaryRole(role : String [, relativeTo : Entity [, range :
// Number]]) : Number
static JSValue SystemCountShipsWithPrimaryRole(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  std::optional<std::string> role;
  Entity* relativeTo = nullptr;  // the C++ entity
  double range = -1;
  unsigned result;

  if (argc > 0) role = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
  if (EXPECT_NOT(!role.has_value())) {
    cxx_OOJSReportBadArguments(context, "System", "countShipsWithPrimaryRole",
                               MIN(argc, 1), OOJS_ARGV, std::nullopt,
                               "string (role)");
    return OOJSNativeFailure(context);
  }

  // Get optional arguments
  argc -= 1;
  JSValueConst* argv = OOJS_ARGV + 1;
  if (EXPECT_NOT(!GetRelativeToAndRange(context, "countShipsWithPrimaryRole",
                                        &argc, &argv, &relativeTo, &range)))
    return OOJSNativeFailure(context);

  OOJS_BEGIN_FULL_NATIVE(context)
  result = (UNIVERSE != nullptr
                ? UNIVERSE->countShipsWithPrimaryRole(*role, range, relativeTo)
                : 0u);
  OOJS_END_FULL_NATIVE

  OOJS_RETURN_INT(result);

  OOJS_NATIVE_EXIT
}

// countShipsWithRole(role : String [, relativeTo : Entity [, range : Number]])
// : Number
static JSValue SystemCountShipsWithRole(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  std::optional<std::string> role;
  Entity* relativeTo = nullptr;  // the C++ entity
  double range = -1;
  unsigned result;

  if (argc > 0) role = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
  if (EXPECT_NOT(!role.has_value())) {
    cxx_OOJSReportBadArguments(context, "System", "countShipsWithRole",
                               MIN(argc, 1), OOJS_ARGV, std::nullopt,
                               "string (role)");
    return OOJSNativeFailure(context);
  }

  // Get optional arguments
  argc -= 1;
  JSValueConst* argv = OOJS_ARGV + 1;
  if (EXPECT_NOT(!GetRelativeToAndRange(context, "countShipsWithRole", &argc,
                                        &argv, &relativeTo, &range)))
    return OOJSNativeFailure(context);

  OOJS_BEGIN_FULL_NATIVE(context)
  result = (UNIVERSE != nullptr
                ? UNIVERSE->countShipsWithRole(*role, range, relativeTo)
                : 0u);
  OOJS_END_FULL_NATIVE

  OOJS_RETURN_INT(result);

  OOJS_NATIVE_EXIT
}

// shipsWithPrimaryRole(role : String [, relativeTo : Entity [, range :
// Number]]) : Array (Entity)
static JSValue SystemShipsWithPrimaryRole(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  std::optional<std::string> role;
  Entity* relativeTo = nullptr;  // the C++ entity
  double range = -1;
  std::vector<oo::EntityHold> result;

  if (argc > 0) role = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
  if (EXPECT_NOT(!role.has_value())) {
    cxx_OOJSReportBadArguments(context, "System", "countShipsWithRole",
                               MIN(argc, 1), OOJS_ARGV, std::nullopt,
                               "string (role)");
    return OOJSNativeFailure(context);
  }

  // Get optional arguments
  argc -= 1;
  JSValueConst* argv = OOJS_ARGV + 1;
  if (EXPECT_NOT(!GetRelativeToAndRange(context, "shipsWithPrimaryRole", &argc,
                                        &argv, &relativeTo, &range)))
    return OOJSNativeFailure(context);

  // Search for entities
  OOJS_BEGIN_FULL_NATIVE(context)
  result = FindShips(HasPrimaryRolePredicate, &*role, relativeTo, range);
  OOJS_END_FULL_NATIVE

  OOJS_RETURN_PLIST(oo::EntityNodesFrom(result));

  OOJS_NATIVE_EXIT
}

// shipsWithRole(role : String [, relativeTo : Entity [, range : Number]]) :
// Array (Entity)
static JSValue SystemShipsWithRole(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  std::optional<std::string> role;
  Entity* relativeTo = nullptr;  // the C++ entity
  double range = -1;
  std::vector<oo::EntityHold> result;

  if (argc > 0) role = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
  if (EXPECT_NOT(!role.has_value())) {
    cxx_OOJSReportBadArguments(context, "System", "shipsWithRole", MIN(argc, 1),
                               OOJS_ARGV, std::nullopt, "string (role)");
    return OOJSNativeFailure(context);
  }

  // Get optional arguments
  argc -= 1;
  JSValueConst* subargv = OOJS_ARGV + 1;
  if (EXPECT_NOT(!GetRelativeToAndRange(context, "shipsWithRole", &argc,
                                        &subargv, &relativeTo, &range)))
    return OOJSNativeFailure(context);

  // Search for entities
  OOJS_BEGIN_FULL_NATIVE(context)
  result = FindShips(HasRolePredicate, &*role, relativeTo, range);
  OOJS_END_FULL_NATIVE

  OOJS_RETURN_PLIST(oo::EntityNodesFrom(result));

  OOJS_NATIVE_EXIT
}

// countEntitiesWithScanClass(scanClass : String [, relativeTo : Entity [, range
// : Number]]) : Number
static JSValue SystemCountEntitiesWithScanClass(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  OOScanClass scanClass = OOScanClass::kNotSet;
  Entity* relativeTo = nullptr;  // the C++ entity
  double range = -1;
  unsigned result;

  if (argc > 0) scanClass = OOScanClassFromJSValue(context, OOJS_ARGV[0]);
  if (scanClass == OOScanClass::kNotSet) {
    cxx_OOJSReportBadArguments(context, "System", "countEntitiesWithScanClass",
                               MIN(argc, 1), OOJS_ARGV, std::nullopt,
                               "string (scan class)");
    return OOJSNativeFailure(context);
  }

  // Get optional arguments
  argc -= 1;
  JSValueConst* argv = OOJS_ARGV + 1;
  if (EXPECT_NOT(!GetRelativeToAndRange(context, "countEntitiesWithScanClass",
                                        &argc, &argv, &relativeTo, &range)))
    return OOJSNativeFailure(context);

  OOJS_BEGIN_FULL_NATIVE(context)
  result = (UNIVERSE != nullptr ? UNIVERSE->countShipsWithScanClass(
                                      scanClass, range, relativeTo)
                                : 0u);
  OOJS_END_FULL_NATIVE

  OOJS_RETURN_INT(result);

  OOJS_NATIVE_EXIT
}

// entitiesWithScanClass(scanClass : String [, relativeTo : Entity [, range :
// Number]]) : Array (Entity)
static JSValue SystemEntitiesWithScanClass(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  OOScanClass scanClass = OOScanClass::kNotSet;
  Entity* relativeTo = nullptr;  // the C++ entity
  double range = -1;
  std::vector<oo::EntityHold> result;

  if (argc > 0) scanClass = OOScanClassFromJSValue(context, OOJS_ARGV[0]);
  if (scanClass == OOScanClass::kNotSet) {
    cxx_OOJSReportBadArguments(context, "System", "countEntitiesWithScanClass",
                               MIN(argc, 1), OOJS_ARGV, std::nullopt,
                               "string (scan class)");
    return OOJSNativeFailure(context);
  }

  // Get optional arguments
  argc -= 1;
  JSValueConst* argv = OOJS_ARGV + 1;
  if (EXPECT_NOT(!GetRelativeToAndRange(context, "entitiesWithScanClass", &argc,
                                        &argv, &relativeTo, &range)))
    return OOJSNativeFailure(context);

  // Search for entities
  OOJS_BEGIN_FULL_NATIVE(context)
  result = FindJSVisibleEntities(HasScanClassPredicate, &scanClass, relativeTo,
                                 range);
  OOJS_END_FULL_NATIVE

  OOJS_RETURN_PLIST(oo::EntityNodesFrom(result));

  OOJS_NATIVE_EXIT
}

// filteredEntities(this : Object, predicate : Function [, relativeTo : Entity
// [, range : Number]]) : Array (Entity)
static JSValue SystemFilteredEntities(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  JSValue jsThis = JS_UNDEFINED;
  JSValueConst predicate;
  Entity* relativeTo = nullptr;  // the C++ entity
  double range = -1;
  std::vector<oo::EntityHold> result;

  // Get this and predicate arguments
  if (argc < 2 || !OOJSValueIsFunction(context, OOJS_ARGV[1])) {
    cxx_OOJSReportBadArguments(
        context, "System", "filteredEntities", argc, OOJS_ARGV, std::nullopt,
        "this, predicate function, and optional reference entity and range");
    return OOJSNativeFailure(context);
  }
  /*	As with SpiderMonkey's JS_ValueToObject(), primitives are boxed. It gave
          no object for null and undefined, and calling a function with no this
          object used the global object, so pass the global object explicitly.
  */
  if (JS_IsNull(OOJS_ARGV[0]) || JS_IsUndefined(OOJS_ARGV[0])) {
    jsThis = JS_GetGlobalObject(context);
  } else {
    jsThis = JS_ToObject(context, OOJS_ARGV[0]);
    if (JS_IsException(jsThis)) {
      JS_FreeValue(context, JS_GetException(context));
      cxx_OOJSReportBadArguments(
          context, "System", "filteredEntities", argc, OOJS_ARGV, std::nullopt,
          "this, predicate function, and optional reference entity and range");
      return OOJSNativeFailure(context);
    }
  }
  predicate = OOJS_ARGV[1];

  // Get optional arguments
  argc -= 2;
  JSValueConst* argv = OOJS_ARGV + 2;
  if (EXPECT_NOT(!GetRelativeToAndRange(context, "filteredEntities", &argc,
                                        &argv, &relativeTo, &range))) {
    JS_FreeValue(context, jsThis);
    return OOJSNativeFailure(context);
  }

  // Search for entities
  JSFunctionPredicateParameter param = {context, predicate, jsThis, false};
  OOJSPauseTimeLimiter();
  try {
    result =
        FindJSVisibleEntities(JSFunctionPredicate, &param, relativeTo, range);
  } catch (...) {
    OOJSResumeTimeLimiter();
    JS_FreeValue(context, jsThis);
    throw;
  }
  OOJSResumeTimeLimiter();
  JS_FreeValue(context, jsThis);

  // The predicate's exception has been reported (as before); stop the script.
  if (EXPECT_NOT(param.errorFlag)) return OOJSNativeFailure(context);

  OOJS_RETURN_PLIST(oo::EntityNodesFrom(result));

  OOJS_NATIVE_EXIT
}

// locationFromCode(populator_named_region : String)
static JSValue SystemLocationFromCode(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  std::optional<std::string> code;
  if (argc > 0) {
    code = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
  }
  if (EXPECT_NOT(!code.has_value())) {
    cxx_OOJSReportBadArguments(context, "System", "locationFromCode", argc,
                               OOJS_ARGV, std::nullopt, "location code");
    return OOJSNativeFailure(context);
  }
  OOSunEntity* sun = (UNIVERSE != nullptr ? UNIVERSE->sun() : nullptr);
  OOPlanetEntity* planet = (UNIVERSE != nullptr ? UNIVERSE->planet() : nullptr);
  HPVector position = kZeroHPVector;
  if (sun == nullptr || planet == nullptr) {
    position = (UNIVERSE != nullptr
                    ? UNIVERSE->locationByCode("WITCHPOINT", nullptr, nullptr)
                    : HPVector{});
  } else {
    position =
        (UNIVERSE != nullptr ? UNIVERSE->locationByCode(*code, sun, planet)
                             : HPVector{});
  }

  OOJS_RETURN_HPVECTOR(position);

  OOJS_NATIVE_EXIT
}

// addShips(role : String, count : Number [, position: Vector [, radius:
// Number]]) : Array of Ship
static JSValue SystemAddShips(OOJS_NATIVE_ARGS) {
  return SystemAddShipsOrGroup(context, argc, OOJS_ARGV, false);
}

// addGroup(role : String, count : Number [, position: Vector [, radius:
// Number]]) : ShipGroup
static JSValue SystemAddGroup(OOJS_NATIVE_ARGS) {
  return SystemAddShipsOrGroup(context, argc, OOJS_ARGV, true);
}

// addShipsToRoute(role : String, count : Number [, position: Number [, route:
// String]])
static JSValue SystemAddShipsToRoute(OOJS_NATIVE_ARGS) {
  return SystemAddShipsOrGroupToRoute(context, argc, OOJS_ARGV, false);
}

// addGroupToRoute(role : String, count : Number,  position: Number[, route:
// String])
static JSValue SystemAddGroupToRoute(OOJS_NATIVE_ARGS) {
  return SystemAddShipsOrGroupToRoute(context, argc, OOJS_ARGV, true);
}

/*	The legacy_* methods read argv entries beyond argc before checking argc,
   as before. This is safe because QuickJS pads argv with undefined up to each
        method's declared minimum argument count.
*/

// legacy_addShips(role : String, count : Number)
static JSValue SystemLegacyAddShips(OOJS_NATIVE_ARGS) {
  cxx_OOStandardsDeprecated("system.legacy_addShips() is deprecated");
  OOJS_NATIVE_ENTER(context)

  std::optional<std::string> role;
  int32_t count;

  if (argc > 0) role = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
  if (EXPECT_NOT(!role.has_value() ||
                 !OOJSValueToInt32(context, OOJS_ARGV[1], &count) || argc < 2 ||
                 count < 1 || 64 < count)) {
    cxx_OOJSReportBadArguments(context, "System", "legacy_addShips", argc,
                               OOJS_ARGV, std::nullopt,
                               "role and positive count no greater than 64");
    return OOJSNativeFailure(context);
  }

  OOJS_BEGIN_FULL_NATIVE(context)
  while (count--) {
    if (UNIVERSE != nullptr) UNIVERSE->witchspaceShipWithPrimaryRole(*role);
  }
  OOJS_END_FULL_NATIVE

  OOJS_RETURN_VOID;

  OOJS_NATIVE_EXIT
}

// legacy_addSystemShips(role : String, count : Number, location : Number)
static JSValue SystemLegacyAddSystemShips(OOJS_NATIVE_ARGS) {
  cxx_OOStandardsDeprecated("system.legacy_addSystemShips() is deprecated");
  OOJS_NATIVE_ENTER(context)

  double position;
  std::optional<std::string> role;
  int32_t count;

  if (argc > 0) role = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
  if (EXPECT_NOT(!role.has_value() ||
                 !OOJSValueToInt32(context, OOJS_ARGV[1], &count) ||
                 count < 1 || 64 < count || argc < 3 ||
                 JS_ToFloat64(context, &position, OOJS_ARGV[2]) != 0)) {
    cxx_OOJSReportBadArguments(
        context, "System", "legacy_addSystemShips", argc, OOJS_ARGV,
        std::nullopt,
        "role, positive count no greater than 64, and position along route");
    return OOJSNativeFailure(context);
  }

  OOJS_BEGIN_FULL_NATIVE(context)
  while (count--) {
    if (UNIVERSE != nullptr) UNIVERSE->addShipWithRole(*role, position);
  }
  OOJS_END_FULL_NATIVE

  OOJS_RETURN_VOID;

  OOJS_NATIVE_EXIT
}

// legacy_addShipsAt(role : String, count : Number, coordScheme : String, coords
// : vectorExpression)
static JSValue SystemLegacyAddShipsAt(OOJS_NATIVE_ARGS) {
  cxx_OOStandardsDeprecated("system.legacy_addShipsAt() is deprecated");
  OOJS_NATIVE_ENTER(context)

  PlayerEntity* player = OOPlayerForScripting();
  HPVector where;
  std::optional<std::string> role;
  int32_t count;
  std::optional<std::string> coordScheme;
  std::string arg;

  if (argc > 0) role = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
  coordScheme = cxx_OOStringFromJSValue(context, OOJS_ARGV[2]);
  if (EXPECT_NOT(!role.has_value() ||
                 !OOJSValueToInt32(context, OOJS_ARGV[1], &count) ||
                 count < 1 || 64 < count || !coordScheme.has_value() ||
                 argc < 4 ||
                 !VectorFromArgumentListNoError(
                     context, argc - 3, OOJS_ARGV + 3, &where, nullptr))) {
    cxx_OOJSReportBadArguments(context, "System", "legacy_addShipsAt", argc,
                               OOJS_ARGV, std::nullopt,
                               "role, positive count no greater than 64, "
                               "coordinate scheme and coordinates");
    return OOJSNativeFailure(context);
  }

  OOJS_BEGIN_FULL_NATIVE(context)
  arg = std::format("{} {} {} {:f} {:f} {:f}", *role, count, *coordScheme,
                    where.x, where.y, where.z);
  if (player != nullptr) player->addShipsAt(arg);
  OOJS_END_FULL_NATIVE

  OOJS_RETURN_VOID;

  OOJS_NATIVE_EXIT
}

// legacy_addShipsAtPrecisely(role : String, count : Number, coordScheme :
// String, coords : vectorExpression)
static JSValue SystemLegacyAddShipsAtPrecisely(OOJS_NATIVE_ARGS) {
  cxx_OOStandardsDeprecated(
      "system.legacy_addShipsAtPrecisely() is deprecated");
  OOJS_NATIVE_ENTER(context)

  PlayerEntity* player = OOPlayerForScripting();
  HPVector where;
  std::optional<std::string> role;
  int32_t count;
  std::optional<std::string> coordScheme;
  std::string arg;

  if (argc > 0) role = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
  coordScheme = cxx_OOStringFromJSValue(context, OOJS_ARGV[2]);
  if (EXPECT_NOT(!role.has_value() ||
                 !OOJSValueToInt32(context, OOJS_ARGV[1], &count) ||
                 count < 1 || 64 < count || !coordScheme.has_value() ||
                 argc < 4 ||
                 !VectorFromArgumentListNoError(
                     context, argc - 3, OOJS_ARGV + 3, &where, nullptr))) {
    cxx_OOJSReportBadArguments(context, "System", "legacy_addShipsAtPrecisely",
                               argc, OOJS_ARGV, std::nullopt,
                               "role, positive count no greater than 64, "
                               "coordinate scheme and coordinates");
    return OOJSNativeFailure(context);
  }

  OOJS_BEGIN_FULL_NATIVE(context)
  arg = std::format("{} {} {} {:f} {:f} {:f}", *role, count, *coordScheme,
                    where.x, where.y, where.z);
  if (player != nullptr) player->addShipsAtPrecisely(arg);
  OOJS_END_FULL_NATIVE

  OOJS_RETURN_VOID;

  OOJS_NATIVE_EXIT
}

// legacy_addShipsWithinRadius(role : String, count : Number, coordScheme :
// String, coords : vectorExpression, radius : Number)
static JSValue SystemLegacyAddShipsWithinRadius(OOJS_NATIVE_ARGS) {
  cxx_OOStandardsDeprecated(
      "system.legacy_addShipsWithinRadius() is deprecated");
  OOJS_NATIVE_ENTER(context)

  PlayerEntity* player = OOPlayerForScripting();
  HPVector where;
  double radius;
  std::optional<std::string> role;
  int32_t count;
  std::optional<std::string> coordScheme;
  std::string arg;
  int consumed = 0;

  if (argc > 0) role = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
  if (argc > 2) coordScheme = cxx_OOStringFromJSValue(context, OOJS_ARGV[2]);
  if (EXPECT_NOT(
          !role.has_value() ||
          !OOJSValueToInt32(context, OOJS_ARGV[1], &count) || count < 1 ||
          64 < count || !coordScheme.has_value() || argc < 5 ||
          !VectorFromArgumentListNoError(context, argc - 3, OOJS_ARGV + 3,
                                         &where, &consumed) ||
          JS_ToFloat64(context, &radius, OOJS_ARGV[3 + consumed]) != 0)) {
    cxx_OOJSReportBadArguments(context, "System", "legacy_addShipWithinRadius",
                               argc, OOJS_ARGV, std::nullopt,
                               "role, positive count no greater than 64, "
                               "coordinate scheme, coordinates and radius");
    return OOJSNativeFailure(context);
  }

  OOJS_BEGIN_FULL_NATIVE(context)
  arg = std::format("{} {} {} {:f} {:f} {:f} {:f}", *role, count, *coordScheme,
                    where.x, where.y, where.z, radius);
  if (player != nullptr) player->addShipsWithinRadius(arg);
  OOJS_END_FULL_NATIVE

  OOJS_RETURN_VOID;

  OOJS_NATIVE_EXIT
}

// legacy_spawnShip(key : string)
static JSValue SystemLegacySpawnShip(OOJS_NATIVE_ARGS) {
  cxx_OOStandardsDeprecated("system.legacy_spawnShip() is deprecated");
  OOJS_NATIVE_ENTER(context)

  std::optional<std::string> key;
  OOPlayerForScripting();  // For backwards-compatibility

  if (argc > 0) key = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
  if (!key.has_value()) {
    cxx_OOJSReportBadArguments(context, "System", "legacy_spawnShip",
                               MIN(argc, 1), OOJS_ARGV, std::nullopt,
                               "string (ship key)");
    return OOJSNativeFailure(context);
  }

  OOJS_BEGIN_FULL_NATIVE(context)
  if (UNIVERSE != nullptr) UNIVERSE->spawnShip(*key);
  OOJS_END_FULL_NATIVE

  OOJS_RETURN_VOID;

  OOJS_NATIVE_EXIT
}

// *** Static methods ***

// systemNameForID(ID : Number) : String
static JSValue SystemStaticSystemNameForID(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  int32_t systemID;

  if (argc < 1 || !OOJSValueToInt32(context, OOJS_ARGV[0], &systemID) ||
      systemID < -1 || kOOMaximumSystemID < systemID)  // -1 interstellar space!
  {
    cxx_OOJSReportBadArguments(context, "System", "systemNameForID",
                               MIN(argc, 1), OOJS_ARGV, std::nullopt,
                               "system ID");
    return OOJSNativeFailure(context);
  }

  if (systemID == -1)
    OOJS_RETURN_PLIST(oo::PList(std::string(OO_DESC("interstellar-space"))));
  else
    OOJS_RETURN_STRING_OR_NULL((UNIVERSE != nullptr
                                    ? UNIVERSE->getSystemName(systemID)
                                    : std::optional<std::string>()));

  OOJS_NATIVE_EXIT
}

// systemIDForName(name : String) : Number
static JSValue SystemStaticSystemIDForName(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  std::optional<std::string> name;
  unsigned result;

  if (argc > 0) name = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
  if (!name.has_value()) {
    cxx_OOJSReportBadArguments(context, "System", "systemIDForName",
                               MIN(argc, 1), OOJS_ARGV, std::nullopt, "string");
    return OOJSNativeFailure(context);
  }

  OOJS_BEGIN_FULL_NATIVE(context)

  result = (UNIVERSE != nullptr ? UNIVERSE->findSystemFromName(*name) : 0);

  OOJS_END_FULL_NATIVE

  // As with INT_TO_JSVAL(), the unsigned result is reinterpreted as signed (so
  // not found is -1).
  OOJS_RETURN_INT(static_cast<int32_t>(result));

  OOJS_NATIVE_EXIT
}

// infoForSystem(galaxyID : Number, systemID : Number) : SystemInfo
static JSValue SystemStaticInfoForSystem(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  int32_t galaxyID;
  int32_t systemID;

  if (argc < 2 || !OOJSValueToInt32(context, OOJS_ARGV[0], &galaxyID) ||
      !OOJSValueToInt32(context, OOJS_ARGV[1], &systemID)) {
    cxx_OOJSReportBadArguments(context, "System", "infoForSystem", argc,
                               OOJS_ARGV, std::nullopt,
                               "galaxy ID and system ID");
    return OOJSNativeFailure(context);
  }

  if (galaxyID < 0 || galaxyID > kOOMaximumGalaxyID) {
    cxx_OOJSReportBadArguments(
        context, "System", "infoForSystem", 1, OOJS_ARGV, "Invalid galaxy ID",
        std::format("number in the range 0 to {}",
                    static_cast<unsigned int>(kOOMaximumGalaxyID)));
    return OOJSNativeFailure(context);
  }

  if (systemID < kOOMinimumSystemID || systemID > kOOMaximumSystemID) {
    cxx_OOJSReportBadArguments(
        context, "System", "infoForSystem", 1, OOJS_ARGV + 1,
        "Invalid system ID",
        std::format("number in the range {} to {}",
                    static_cast<int>(kOOMinimumSystemID),
                    static_cast<int>(kOOMaximumSystemID)));
    return OOJSNativeFailure(context);
  }

  OOJS_RETURN(GetJSSystemInfoForSystem(context, galaxyID, systemID));

  OOJS_NATIVE_EXIT
}

static JSValue SystemAddVisualEffect(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  std::optional<std::string> key;
  HPVector where;

  int consumed = 0;

  if (argc > 0) key = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
  if (!key.has_value()) {
    cxx_OOJSReportBadArguments(context, "System", "addVisualEffect",
                               MIN(argc, 1), &OOJS_ARGV[0], std::nullopt,
                               "string (key)");
    return OOJSNativeFailure(context);
  }

  if (!VectorFromArgumentListNoError(context, argc - 1, OOJS_ARGV + 1, &where,
                                     &consumed)) {
    cxx_OOJSReportBadArguments(context, "System", "addVisualEffect",
                               MIN(argc - 1, 1), &OOJS_ARGV[1], std::nullopt,
                               "vector");
    return OOJSNativeFailure(context);
  }

  Entity* result = nullptr;  // the C++ effect

  OOJS_BEGIN_FULL_NATIVE(context)

  result = (UNIVERSE != nullptr ? UNIVERSE->addVisualEffectAt(where, *key)
                                : nullptr);

  OOJS_END_FULL_NATIVE

  OOJS_RETURN(OOJSEntityJSValue(result, context));

  OOJS_NATIVE_EXIT
}

// Get a property of a settings object. As before, a failed get is treated like
// a missing property.
static JSValue GetParam(JSContext* context, JSValueConst object,
                        const char* key) {
  JSValue value = JS_GetPropertyStr(context, object, key);
  if (JS_IsException(value)) {
    OOJSReportPendingException(context);
    return JS_UNDEFINED;
  }
  return value;
}

static JSValue SystemSetPopulator(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  std::optional<std::string> key;
  oo::PList settings;
  JSValue params = JS_UNDEFINED;

  if (argc < 1) {
    cxx_OOJSReportBadArguments(context, "System", "setPopulator", MIN(argc, 0),
                               &OOJS_ARGV[0], std::nullopt,
                               "string (key), object (settings)");
    return OOJSNativeFailure(context);
  }
  key = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
  if (!key.has_value()) {
    cxx_OOJSReportBadArguments(context, "System", "setPopulator", MIN(argc, 0),
                               &OOJS_ARGV[0], std::nullopt, "key, settings");
    return OOJSNativeFailure(context);
  }
  if (argc < 2 || JS_IsNull(OOJS_ARGV[1])) {
    // clearing
    if (UNIVERSE != nullptr) UNIVERSE->setPopulatorSetting(*key, oo::PList());
  } else {
    // adding
    // As with SpiderMonkey's JS_ValueToObject(), primitives are boxed.
    // (undefined gave no object, which then could not work; treat it as
    // invalid.)
    if (!JS_IsUndefined(OOJS_ARGV[1])) {
      params = JS_ToObject(context, OOJS_ARGV[1]);
      if (JS_IsException(params)) {
        JS_FreeValue(context, JS_GetException(context));
        params = JS_UNDEFINED;
      }
    }
    if (!JS_IsObject(params)) {
      cxx_OOJSReportBadArguments(context, "System", "setPopulator",
                                 MIN(argc, 1), OOJS_ARGV, std::nullopt,
                                 "key, settings");
      return OOJSNativeFailure(context);
    }
    JSValue callback = GetParam(context, params, "callback");
    if (JS_IsUndefined(callback)) {
      JS_FreeValue(context, params);
      cxx_OOJSReportBadArguments(context, "System", "setPopulator",
                                 MIN(argc, 1), OOJS_ARGV, std::nullopt,
                                 "settings must have a 'callback' property.");
      return OOJSNativeFailure(context);
    }

    // The reference releases the definition where -release did.
    oo::Ref<OOJSPopulatorDefinition> populator =
        oo::makeRef<OOJSPopulatorDefinition>();
    populator->setCallback(callback);  // Takes its own reference.
    JS_FreeValue(context, callback);

    // (The SpiderMonkey version converted argv[1] directly; params is the same
    // object for any object argument.)
    settings = cxx_OOJSPListFromJSObject(context, params);
    oo::PList::Dict* settingsDict =
        settings.getIf<oo::PList::Dict>();  // messages to a nil dictionary did
                                            // nothing
    if (settingsDict != nullptr)
      (*settingsDict)["callbackObj"] =
          OOJSPopulatorDefinitionToPList(populator);

    JSValue coords = GetParam(context, params, "coordinates");
    if (!JS_IsUndefined(coords)) {
      Vector coordinates = kZeroVector;
      if (JSValueToVector(context, coords, &coordinates)) {
        // convert vector in NS-storable form (three floats)
        if (settingsDict != nullptr)
          (*settingsDict)["coordinates"] =
              oo::PList(oo::PList::Array{oo::PList::singleReal(coordinates.x),
                                         oo::PList::singleReal(coordinates.y),
                                         oo::PList::singleReal(coordinates.z)});
      }
    }
    JS_FreeValue(context, coords);
    JS_FreeValue(context, params);

    populator = nullptr;  // -release

    // A failed vector conversion is ignored, as before, but QuickJS natives
    // must not return normally with an exception pending.
    if (EXPECT_NOT(JS_HasException(context))) return JS_EXCEPTION;

    if (UNIVERSE != nullptr) UNIVERSE->setPopulatorSetting(*key, settings);
  }

  OOJS_RETURN_VOID;

  OOJS_NATIVE_EXIT
}

static JSValue SystemSetWaypoint(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  std::optional<std::string> key;
  oo::PList settings;
  HPVector position;
  Quaternion orientation;

  if (argc < 1) {
    cxx_OOJSReportBadArguments(context, "System", "setWaypoint", MIN(argc, 0),
                               &OOJS_ARGV[0], std::nullopt,
                               "key, position, orientation, definition");
    return OOJSNativeFailure(context);
  }
  key = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
  if (!key.has_value()) {
    cxx_OOJSReportBadArguments(context, "System", "setWaypoint", MIN(argc, 0),
                               &OOJS_ARGV[0], std::nullopt,
                               "key, position, orientation, definition");
    return OOJSNativeFailure(context);
  }
  if (argc < 4 || JS_IsNull(OOJS_ARGV[3])) {
    // clearing
    if (UNIVERSE != nullptr) UNIVERSE->defineWaypoint(oo::PList(), *key);
  } else {
    // adding
    if (!JSValueToHPVector(context, OOJS_ARGV[1], &position)) {
      cxx_OOJSReportBadArguments(context, "System", "setWaypoint", MIN(argc, 2),
                                 OOJS_ARGV, std::nullopt,
                                 "key, position, orientation, definition");
      return OOJSNativeFailure(context);
    }
    if (!JSValueToQuaternion(context, OOJS_ARGV[2], &orientation)) {
      cxx_OOJSReportBadArguments(context, "System", "setWaypoint", MIN(argc, 3),
                                 OOJS_ARGV, std::nullopt,
                                 "key, position, orientation, definition");
      return OOJSNativeFailure(context);
    }
    if (!JS_IsObject(OOJS_ARGV[3]) || JS_IsNull(OOJS_ARGV[3])) {
      cxx_OOJSReportBadArguments(context, "System", "setWaypoint", MIN(argc, 4),
                                 OOJS_ARGV, std::nullopt,
                                 "key, position, orientation, definition");
      return OOJSNativeFailure(context);
    }

    settings = cxx_OOJSPListFromJSObject(
        context, OOJS_ARGV[3]);  // a copy, as -mutableCopy was
    if (oo::PList::Dict* settingsDict =
            settings.getIf<oo::PList::Dict>())  // messages to a nil copy did
                                                // nothing
    {
      (*settingsDict)["position"] = oo::PList(oo::PList::Array{
          oo::PList(position.x), oo::PList(position.y), oo::PList(position.z)});
      (*settingsDict)["orientation"] = oo::PList(
          oo::PList::Array{oo::PList(orientation.w), oo::PList(orientation.x),
                           oo::PList(orientation.y), oo::PList(orientation.z)});
    }

    if (UNIVERSE != nullptr) UNIVERSE->defineWaypoint(settings, *key);
  }

  OOJS_RETURN_VOID;

  OOJS_NATIVE_EXIT
}

// *** Helper functions ***

// Shared implementation of addShips() and addGroup().
static JSValue SystemAddShipsOrGroup(JSContext* context, int argc,
                                     JSValueConst* argv, bool isGroup) {
  OOJS_NATIVE_ENTER(context)

  std::optional<std::string> role;
  int32_t count = 0;
  int consumed = 0;
  HPVector where;
  double radius = static_cast<double>(oo::kNotFound);  // a negative value means
  oo::PList result;

  std::string func = isGroup ? "addGroup" : "addShips";

  if (argc > 0) role = cxx_OOStringFromJSValue(context, argv[0]);
  if (!role.has_value()) {
    cxx_OOJSReportBadArguments(context, "System", func, MIN(argc, 1), &argv[0],
                               std::nullopt, "string (role)");
    return JS_EXCEPTION;
  }
  if (argc < 2 || !OOJSValueToInt32(context, argv[1], &count) || count < 1 ||
      64 < count) {
    cxx_OOJSReportBadArguments(context, "System", func, MIN(argc - 1, 1),
                               &argv[1], std::nullopt,
                               "number (positive count no greater than 64)");
    return JS_EXCEPTION;
  }

  if (argc < 3) {
    where = (UNIVERSE != nullptr ? UNIVERSE->getWitchspaceExitPosition()
                                 : HPVector{});
    radius = SCANNER_MAX_RANGE;
  } else {
    if (!VectorFromArgumentListNoError(context, argc - 2, argv + 2, &where,
                                       &consumed)) {
      cxx_OOJSReportBadArguments(context, "System", func, MIN(argc - 2, 1),
                                 &argv[2], std::nullopt, "vector");
      return JS_EXCEPTION;
    }

    if (argc > 2 + consumed) {
      if (JS_ToFloat64(context, &radius, argv[2 + consumed]) < 0) {
        cxx_OOJSReportBadArguments(
            context, "System", func, MIN(argc - 2 - consumed, 1),
            &argv[2 + consumed], std::nullopt, "number (radius)");
        return JS_EXCEPTION;
      }
    }
  }

  OOJS_BEGIN_FULL_NATIVE(context)
  // Note: the use of witchspace-in effects (as in legacy_addShips) depends on
  // proximity to the witchpoint.
  const std::vector<oo::EntityHold> added =
      (UNIVERSE != nullptr
           ? UNIVERSE->addShipsAt(where, *role, count, radius, isGroup)
           : std::vector<oo::EntityHold>());
  if (!added.empty())
    result =
        oo::EntityNodesFrom(added);  // null where no ship was added, as before

  if (isGroup) {
    const std::vector<Entity*> ships =
        oo::EntitiesIn(result);  // borrowed: result holds them
    ShipEntity* first = (ships.size() > 0 ? oo::ToShip(ships[0]) : nullptr);
    if (ships.size() > 0)
      result =
          OOShipGroupObjectNode(first != nullptr ? first->group() : nullptr);
    else
      result = oo::PList();
  }
  OOJS_END_FULL_NATIVE

  OOJS_RETURN_PLIST(result);

  OOJS_NATIVE_EXIT
}

static JSValue SystemAddShipsOrGroupToRoute(JSContext* context, int argc,
                                            JSValueConst* argv, bool isGroup) {
  OOJS_NATIVE_ENTER(context)

  std::optional<std::string> role;
  std::optional<std::string> route =
      "st";  // default route witchpoint -> station. ("st" itself is not
             // selectable by script)
  static const std::set<std::string> validRoutes = {"wp", "pw", "ws",
                                                    "sw", "sp", "ps"};
  int32_t count = 0;
  double where = static_cast<double>(
      oo::kNotFound);  // a negative value means random positioning!
  oo::PList result;

  std::string func = isGroup ? "addGroup" : "addShips";

  if (argc > 0) role = cxx_OOStringFromJSValue(context, argv[0]);
  if (!role.has_value()) {
    cxx_OOJSReportBadArguments(context, "System", func, MIN(argc, 1), &argv[0],
                               std::nullopt, "string (role)");
    return JS_EXCEPTION;
  }
  if (argc < 2 || !OOJSValueToInt32(context, argv[1], &count) || count < 1 ||
      64 < count) {
    cxx_OOJSReportBadArguments(context, "System", func, MIN(argc - 1, 1),
                               &argv[1], std::nullopt,
                               "number (positive count no greater than 64)");
    return JS_EXCEPTION;
  }

  if (argc > 2) {
    if (JS_ToFloat64(context, &where, argv[2]) != 0 || !isfinite(where) ||
        where < 0.0f || where > 1.0f) {
      cxx_OOJSReportBadArguments(context, "System", func, MIN(argc - 2, 1),
                                 &argv[2], std::nullopt,
                                 "number (position along route)");
      return JS_EXCEPTION;
    }

    if (argc > 3) {
      route = cxx_OOStringFromJSValue(context, argv[3]);
      if (route.has_value()) route = oo::str::lowercase(*route);

      if (!route.has_value() || validRoutes.count(*route) == 0) {
        cxx_OOJSReportBadArguments(context, "System", func, MIN(argc - 3, 1),
                                   &argv[3], std::nullopt,
                                   "string (route specifier)");
        return JS_EXCEPTION;
      }
    }
  }

  OOJS_BEGIN_FULL_NATIVE(context)
  // Note: the use of witchspace-in effects (as in legacy_addShips) depends on
  // proximity to the witchpoint.
  const std::vector<oo::EntityHold> added =
      (UNIVERSE != nullptr
           ? UNIVERSE->addShipsToRoute(*route, *role, count, where, isGroup)
           : std::vector<oo::EntityHold>());
  if (!added.empty())
    result =
        oo::EntityNodesFrom(added);  // null where no ship was added, as before

  if (isGroup) {
    const std::vector<Entity*> ships =
        oo::EntitiesIn(result);  // borrowed: result holds them
    ShipEntity* first = (ships.size() > 0 ? oo::ToShip(ships[0]) : nullptr);
    if (ships.size() > 0)
      result =
          OOShipGroupObjectNode(first != nullptr ? first->group() : nullptr);
    else
      result = oo::PList();
  }
  OOJS_END_FULL_NATIVE

  OOJS_RETURN_PLIST(result);

  OOJS_NATIVE_EXIT
}

static bool GetRelativeToAndRange(JSContext* context,
                                  const std::string& methodName, int* ioArgc,
                                  JSValueConst** ioArgv, Entity** outRelativeTo,
                                  double* outRange) {
  OOJS_PROFILE_ENTER

  // No NULL arguments accepted.
  assert(ioArgc && ioArgv && outRelativeTo && outRange);

  // Get optional argument relativeTo : Entity
  if (*ioArgc != 0) {
    Entity* relativeTo = nullptr;  // the C++ entity
    if (EXPECT_NOT(JS_IsNull(**ioArgv) ||
                   !JSValueToEntity(context, **ioArgv, &relativeTo))) {
      cxx_OOJSReportBadArguments(context, "System", methodName, 1, *ioArgv,
                                 std::nullopt, "entity");
      return false;
    }
    *outRelativeTo = relativeTo;
    (*ioArgv)++;
    (*ioArgc)--;
  }

  // Get optional argument range : Number
  if (*ioArgc != 0) {
    if (EXPECT_NOT(JS_ToFloat64(context, outRange, **ioArgv) != 0)) {
      cxx_OOJSReportBadArguments(context, "System", methodName, 1, *ioArgv,
                                 std::nullopt, "number");
      return false;
    }
    (*ioArgv)++;
    (*ioArgc)--;
  }

  return true;

  OOJS_PROFILE_EXIT
}

static std::vector<oo::EntityHold> FindJSVisibleEntities(
    EntityFilterPredicate predicate, void* parameter, Entity* relativeTo,
    double range) {
  OOJS_PROFILE_ENTER

  std::vector<oo::EntityHold> result;
  BinaryOperationPredicateParameter param = {
      JSEntityIsJavaScriptSearchablePredicate, nullptr, predicate, parameter};

  result = (UNIVERSE != nullptr ? UNIVERSE->findEntitiesMatchingPredicate(
                                      ANDPredicate, &param, range, relativeTo)
                                : std::vector<oo::EntityHold>());

  if (relativeTo != nullptr && !relativeTo->getIsPlayer()) {
    // -sortUsingFunction:context: with the same comparison (a stable sort:
    // GNUstep's is timsort).
    std::stable_sort(
        result.begin(), result.end(),
        [relativeTo](const oo::EntityHold& a, const oo::EntityHold& b) {
          return CompareEntitiesByDistance(a.get(), b.get(), relativeTo) ==
                 OOComparisonResult::kAscending;
        });
  }
  return result;  // empty for no matches, as the empty array was

  OOJS_PROFILE_EXIT
}

static std::vector<oo::EntityHold> FindShips(EntityFilterPredicate predicate,
                                             void* parameter,
                                             Entity* relativeTo, double range) {
  OOJS_PROFILE_ENTER

  BinaryOperationPredicateParameter param = {IsShipPredicate, nullptr,
                                             predicate, parameter};
  return FindJSVisibleEntities(ANDPredicate, &param, relativeTo, range);

  OOJS_PROFILE_EXIT
}

static OOComparisonResult CompareEntitiesByDistance(Entity* a, Entity* b,
                                                    Entity* relativeTo) {
  OOJS_PROFILE_ENTER

  Entity *ea = a,  // the C++ entities
      *eb = b;
  Entity* r = relativeTo;  // the C++ entity
  float d1, d2;

  d1 = HPdistance2(ea->position, r->position);
  d2 = HPdistance2(eb->position, r->position);

  if (d1 < d2)
    return OOComparisonResult::kAscending;
  else if (d1 > d2)
    return OOComparisonResult::kDescending;
  else
    return OOComparisonResult::kSame;

  OOJS_PROFILE_EXIT
}
