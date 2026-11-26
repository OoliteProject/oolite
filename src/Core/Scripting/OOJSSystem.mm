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

#import "OOJSSystem.h"
#import "OOJavaScriptEngine.h"

#import "OOJSEntity.h"
#import "OOJSPlayer.h"
#import "OOJSQuaternion.h"
#import "OOJSSystem+ObjCBridge.h"
#import "OOJSSystemInfo.h"
#import "OOJSVector.h"
#import "OOPlanetEntity.h"
#import "PlayerEntityScriptMethods.h"
#import "Universe.h"

#import "EntityOOJavaScriptExtensions.h"
#import "OOConstToJSString.h"
#import "OOConstToString.h"
#import "OODebugStandards.h"
#import "OOEntityFilterPredicate.h"
#import "OOJSPopulatorDefinition.h"
#import "OOJSScript.h"

#import "OOObjCPList.h"
#include "oofnd/String.hpp"
#include <algorithm>
#include <set>

static JSClassID sSystemClassID;

// Support functions for entity search methods.
static BOOL GetRelativeToAndRange(JSContext* context, const std::string& methodName, int* ioArgc, JSValueConst** ioArgv, Entity** outRelativeTo, double* outRange);
static std::vector<oo::ObjCRef<Entity*>> FindJSVisibleEntities(EntityFilterPredicate predicate, void* parameter, Entity* relativeTo, double range);
static std::vector<oo::ObjCRef<Entity*>> FindShips(EntityFilterPredicate predicate, void* parameter, Entity* relativeTo, double range);
static OOComparisonResult CompareEntitiesByDistance(id a, id b, void* relativeTo);

static JSValue SystemAddShipsOrGroup(JSContext* context, int argc, JSValueConst* argv, bool isGroup);
static JSValue SystemAddShipsOrGroupToRoute(JSContext* context, int argc, JSValueConst* argv, bool isGroup);

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

enum {
    // Property IDs
    kSystem_allDemoShips, // demo ships, array of Ship, read-only
    kSystem_allShips, // ships in system, array of Ship, read-only
    kSystem_allVisualEffects, // VEs in system, array of VEs, read-only
    kSystem_ambientLevel, // ambient light level, float, read/write
    kSystem_breakPattern, // witchspace break pattern shown
    kSystem_description, // description, string, read/write
    kSystem_economy, // economy ID, integer, read/write
    kSystem_economyDescription, // economy ID description, string, read-only
    kSystem_government, // government ID, integer, read/write
    kSystem_governmentDescription, // government ID description, string, read-only
    kSystem_ID, // planet number, integer, read-only
    kSystem_info, // system info dictionary, SystemInfo, read/write
    kSystem_inhabitantsDescription, // description of inhabitant species, string, read/write
    kSystem_isInterstellarSpace, // is interstellar space, boolean, read-only
    kSystem_mainPlanet, // system's main planet, Planet, read-only
    kSystem_mainStation, // system's main station, Station, read-only
    kSystem_name, // name, string, read/write
    kSystem_planets, // planets in system, array of Planet, read-only
    kSystem_population, // population, integer, read/write
    kSystem_populatorSettings, // populator settings, dictionary, read-only
    kSystem_productivity, // productivity, integer, read/write
    kSystem_pseudoRandom100, // constant-per-system pseudorandom number in [0..100), integer, read-only
    kSystem_pseudoRandom256, // constant-per-system pseudorandom number in [0..256), integer, read-only
    kSystem_pseudoRandomNumber, // constant-per-system pseudorandom number in [0..1), double, read-only
    kSystem_sun, // system's sun, Planet, read-only
    kSystem_stations, // list of dockable entities, read-only
    kSystem_techLevel, // tech level ID, integer, read/write
    kSystem_waypoints, // dictionary of current player waypoints, read-only
    kSystem_wormholes, // list of active entry wormholes, read-only

};

static const JSCFunctionListEntry sSystemProperties[] = {
    // JS name, getter, setter, ID
    OOJS_PROPERTY_RO("allDemoShips", SystemGetProperty, kSystem_allDemoShips),
    OOJS_PROPERTY_RO("allShips", SystemGetProperty, kSystem_allShips),
    OOJS_PROPERTY_RO("allVisualEffects", SystemGetProperty, kSystem_allVisualEffects),
    OOJS_PROPERTY_RW("ambientLevel", SystemGetProperty, SystemSetProperty, kSystem_ambientLevel),
    OOJS_PROPERTY_RW("breakPattern", SystemGetProperty, SystemSetProperty, kSystem_breakPattern),
    OOJS_PROPERTY_RW("description", SystemGetProperty, SystemSetProperty, kSystem_description),
    OOJS_PROPERTY_RW("economy", SystemGetProperty, SystemSetProperty, kSystem_economy),
    OOJS_PROPERTY_RO("economyDescription", SystemGetProperty, kSystem_economyDescription),
    OOJS_PROPERTY_RW("government", SystemGetProperty, SystemSetProperty, kSystem_government),
    OOJS_PROPERTY_RO("governmentDescription", SystemGetProperty, kSystem_governmentDescription),
    OOJS_PROPERTY_RO("ID", SystemGetProperty, kSystem_ID),
    OOJS_PROPERTY_RO("info", SystemGetProperty, kSystem_info),
    OOJS_PROPERTY_RW("inhabitantsDescription", SystemGetProperty, SystemSetProperty, kSystem_inhabitantsDescription),
    OOJS_PROPERTY_RO("isInterstellarSpace", SystemGetProperty, kSystem_isInterstellarSpace),
    OOJS_PROPERTY_RO("mainPlanet", SystemGetProperty, kSystem_mainPlanet),
    OOJS_PROPERTY_RO("mainStation", SystemGetProperty, kSystem_mainStation),
    OOJS_PROPERTY_RW("name", SystemGetProperty, SystemSetProperty, kSystem_name),
    OOJS_PROPERTY_RO("planets", SystemGetProperty, kSystem_planets),
    OOJS_PROPERTY_RW("population", SystemGetProperty, SystemSetProperty, kSystem_population),
    OOJS_PROPERTY_RO("populatorSettings", SystemGetProperty, kSystem_populatorSettings),
    OOJS_PROPERTY_RW("productivity", SystemGetProperty, SystemSetProperty, kSystem_productivity),
    OOJS_PROPERTY_RO("pseudoRandom100", SystemGetProperty, kSystem_pseudoRandom100),
    OOJS_PROPERTY_RO("pseudoRandom256", SystemGetProperty, kSystem_pseudoRandom256),
    OOJS_PROPERTY_RO("pseudoRandomNumber", SystemGetProperty, kSystem_pseudoRandomNumber),
    OOJS_PROPERTY_RO("stations", SystemGetProperty, kSystem_stations),
    OOJS_PROPERTY_RO("sun", SystemGetProperty, kSystem_sun),
    OOJS_PROPERTY_RW("techLevel", SystemGetProperty, SystemSetProperty, kSystem_techLevel),
    OOJS_PROPERTY_RO("waypoints", SystemGetProperty, kSystem_waypoints),
    OOJS_PROPERTY_RO("wormholes", SystemGetProperty, kSystem_wormholes),
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
    JS_CFUNC_DEF("countEntitiesWithScanClass", 1, SystemCountEntitiesWithScanClass),
    JS_CFUNC_DEF("countShipsWithPrimaryRole", 1, SystemCountShipsWithPrimaryRole),
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
    JS_CFUNC_DEF("legacy_addShipsAtPrecisely", 6, SystemLegacyAddShipsAtPrecisely),
    JS_CFUNC_DEF("legacy_addShipsWithinRadius", 7, SystemLegacyAddShipsWithinRadius),
    JS_CFUNC_DEF("legacy_spawnShip", 1, SystemLegacySpawnShip),
};

static const JSCFunctionListEntry sSystemStaticMethods[] = {
    // JS name, min args, function
    JS_CFUNC_DEF("infoForSystem", 2, SystemStaticInfoForSystem),
    JS_CFUNC_DEF("systemIDForName", 1, SystemStaticSystemIDForName),
    JS_CFUNC_DEF("systemNameForID", 1, SystemStaticSystemNameForID),
};

void InitOOJSSystem(JSContext* context, JSValueConst global)
{
    OOJSRegisterClass(&sSystemClassID, &sSystemClass);
    OOJSInitClass(context, global, sSystemClassID, JS_UNDEFINED, OOJSUnconstructableConstruct, 0,
        sSystemProperties, OOJS_COUNT(sSystemProperties), sSystemMethods, OOJS_COUNT(sSystemMethods),
        sSystemStaticMethods, OOJS_COUNT(sSystemStaticMethods));

    // Create system object as a property of the global object.
    JSValue systemObject = JS_NewObjectClass(context, (int)sSystemClassID);
    JS_DefinePropertyValueStr(context, global, "system", systemObject, OOJS_PROP_READONLY);
}

static JSValue SystemGetProperty(OOJS_GETTER_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    oo::PList result; // null maps to null
    PlayerEntity* player = nil;
    bool handled = false;

    player = OOPlayerForScripting();

    // Handle cases which don't require systemData.
    switch (magic) {
    case kSystem_ID:
        return JS_NewInt32(context, OOJSSystemPlayerCurrentSystemID(player));

    case kSystem_isInterstellarSpace:
        return OOJSValueFromBOOL(OOJSSystemUniverseInInterstellarSpace());

    case kSystem_mainStation:
        result = oo::PListObject(OOJSSystemUniverseStation());
        handled = true;
        break;

    case kSystem_mainPlanet:
        result = oo::PListObject(OOJSSystemUniversePlanet());
        handled = true;
        break;

    case kSystem_sun:
        result = oo::PListObject(OOJSSystemUniverseSun());
        handled = true;
        break;

    case kSystem_planets: {
        std::vector<oo::ObjCRef<OOPlanetEntity*>> visible;
        for (const auto& r : OOJSSystemUniversePlanets()) {
            if (!OOJSSystemEntityIsVisibleToScripts(r.get()))
                continue;
            visible.push_back(r);
        }
        result = oo::PListFromObjects(visible);
        handled = true;
        break;
    }

    case kSystem_stations:
        result = oo::PListFromObjects(OOJSSystemUniverseStations());
        handled = true;
        break;

    case kSystem_waypoints: {
        // An immutable dictionary of the waypoints by key, as -currentWaypoints built it.
        oo::PList::Dict waypoints;
        for (const auto& [key, waypoint] : OOJSSystemUniverseCurrentWaypoints()) {
            if (waypoint.get() != nil)
                waypoints[key] = oo::PListObject(waypoint.get());
        }
        result = oo::PList(std::move(waypoints));
        handled = true;
        break;
    }

    case kSystem_wormholes:
        result = oo::PListFromObjects(OOJSSystemUniverseWormholes());
        handled = true;
        break;

    case kSystem_allShips:
        OOJS_BEGIN_FULL_NATIVE(context)
        result = oo::PListFromObjects(OOJSSystemUniverseFindShipsMatchingPredicate(JSEntityIsJavaScriptSearchablePredicate, NULL, -1, nil));
        OOJS_END_FULL_NATIVE
        handled = true;
        break;

    case kSystem_allDemoShips:
        OOJS_BEGIN_FULL_NATIVE(context)
        result = oo::PListFromObjects(OOJSSystemUniverseFindShipsMatchingPredicate(JSEntityIsDemoShipPredicate, NULL, -1, nil));
        OOJS_END_FULL_NATIVE
        handled = true;
        break;

    case kSystem_allVisualEffects:
        OOJS_BEGIN_FULL_NATIVE(context)
        result = oo::PListFromObjects(OOJSSystemUniverseFindVisualEffectsMatchingPredicate(JSEntityIsJavaScriptSearchablePredicate, NULL, -1, nil));
        OOJS_END_FULL_NATIVE
        handled = true;
        break;

    case kSystem_ambientLevel:
        return JS_NewNumber(context, OOJSSystemUniverseAmbientLightLevel());

    case kSystem_info:
        return GetJSSystemInfoForSystem(context, OOJSSystemPlayerCurrentGalaxyID(player), OOJSSystemPlayerCurrentSystemID(player));

    case kSystem_pseudoRandomNumber:
        return JS_NewNumber(context, OOJSSystemPlayerSystemPseudoRandomFloat(player));

    case kSystem_pseudoRandom100:
        return JS_NewInt32(context, OOJSSystemPlayerSystemPseudoRandom100(player));

    case kSystem_pseudoRandom256:
        return JS_NewInt32(context, OOJSSystemPlayerSystemPseudoRandom256(player));

    case kSystem_breakPattern:
        return OOJSValueFromBOOL(OOJSSystemUniverseWitchspaceBreakPattern());

    case kSystem_populatorSettings:
        return OOJSValueFromPList(context, OOJSSystemUniverseGetPopulatorSettings());
    }

    if (!handled) {
        // Handle cases which do require systemData.
        if (EXPECT(!OOJSSystemUniverseInInterstellarSpace())) {
            const oo::PList systemData = OOJSSystemUniverseCurrentSystemData();

            switch (magic) {
            case kSystem_name:
                if (const oo::PList* entry = systemData.find(KEY_NAME))
                    result = *entry; // -objectForKey:
                break;

            case kSystem_description:
                if (const oo::PList* entry = systemData.find(KEY_DESCRIPTION))
                    result = *entry; // -objectForKey:
                break;

            case kSystem_inhabitantsDescription:
                if (const oo::PList* entry = systemData.find(KEY_INHABITANTS))
                    result = *entry; // -objectForKey:
                break;

            case kSystem_government:
                return JS_NewInt32(context, systemData.get<int>(std::string(KEY_GOVERNMENT)));

            case kSystem_governmentDescription:
                result = oo::PList(cxx_OODisplayStringFromGovernmentID(systemData.get<int>(std::string(KEY_GOVERNMENT))).value_or(std::string(OO_DESC("not-applicable"))));
                break;

            case kSystem_economy:
                return JS_NewInt32(context, systemData.get<int>(std::string(KEY_ECONOMY)));

            case kSystem_economyDescription:
                result = oo::PList(cxx_OODisplayStringFromEconomyID(systemData.get<int>(std::string(KEY_ECONOMY))).value_or(std::string(OO_DESC("not-applicable"))));
                break;

            case kSystem_techLevel:
                return JS_NewInt32(context, systemData.get<int>(std::string(KEY_TECHLEVEL)));

            case kSystem_population:
                return JS_NewInt32(context, systemData.get<int>(std::string(KEY_POPULATION)));

            case kSystem_productivity:
                return JS_NewInt32(context, systemData.get<int>(std::string(KEY_PRODUCTIVITY)));

            default:
                OOJSReportBadPropertySelector(context, thisObj, magic, sSystemProperties, OOJS_COUNT(sSystemProperties));
                return OOJSNativeFailure(context);
            }
        } else {
            // if in interstellar space, systemData values are null & void!
            switch (magic) {
            case kSystem_name:
                result = oo::PList(std::string(OO_DESC("interstellar-space")));
                break;

            case kSystem_description:
                result = oo::PList(std::string());
                break;

            case kSystem_inhabitantsDescription:
                result = oo::PList(std::string(OO_DESC("not-applicable")));
                break;

            case kSystem_government:
                return JS_NewInt32(context, -1);

            case kSystem_governmentDescription:
                result = oo::PList(std::string(OO_DESC("not-applicable")));
                break;

            case kSystem_economy:
                return JS_NewInt32(context, -1);

            case kSystem_economyDescription:
                result = oo::PList(std::string(OO_DESC("not-applicable")));
                break;

            case kSystem_techLevel:
                return JS_NewInt32(context, -1);

            case kSystem_population:
                return JS_NewInt32(context, 0);

            case kSystem_productivity:
                return JS_NewInt32(context, 0);

            default:
                OOJSReportBadPropertySelector(context, thisObj, magic, sSystemProperties, OOJS_COUNT(sSystemProperties));
                return OOJSNativeFailure(context);
            }
        }
    }

    return OOJSValueFromPList(context, result);

    OOJS_NATIVE_EXIT
}

static JSValue SystemSetProperty(OOJS_SETTER_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    PlayerEntity* player = nil;
    OOGalaxyID galaxy;
    OOSystemID system;
    std::optional<std::string> stringValue;
    oo::PList manifest; // the running script's manifest identifier, handed on as it was read
    double fValue;
    int32_t iValue;
    int bValue;

    player = OOPlayerForScripting();

    galaxy = OOJSSystemPlayerCurrentGalaxyID(player);
    system = OOJSSystemPlayerCurrentSystemID(player);

    switch (magic) {
    case kSystem_ambientLevel:
        if (JS_ToFloat64(context, &fValue, value) == 0) {
            OOJSSystemUniverseSetAmbientLightLevel(fValue);
            OOJSSystemUniverseSetLighting();
            return JS_UNDEFINED;
        }
        break;

    case kSystem_breakPattern:
        if ((bValue = JS_ToBool(context, value)) >= 0) {
            OOJSSystemUniverseSetWitchspaceBreakPattern(bValue);
            return JS_UNDEFINED;
        }

        break;
    default: {
    } // do nothing yet
    }

    if (system == -1)
        return JS_UNDEFINED; // Can't change anything else in interstellar space.

    // The running script is converted (cxx::OOJSScript): a message to no script answered null.
    ::OOJSScript* runningScript = cxx::OOJSScript::currentlyRunningScript();
    manifest = (runningScript != nil) ? oo::ToCxx(runningScript)->propertyNamed(kLocalManifestProperty) : oo::PList();
    // the identifier as -fromManifest: read it: a string, else none
    const std::optional<std::string> manifestID = manifest.isString() ? std::optional<std::string>(*manifest.getIf<std::string>()) : std::nullopt;

    switch (magic) {
    case kSystem_name:
        stringValue = cxx_OOStringFromJSValue(context, value);
        if (stringValue.has_value()) {
            OOJSSystemUniverseSetSystemDataForGalaxy(galaxy, system, std::string(KEY_NAME), oo::PList(*stringValue), manifestID, OO_LAYER_OXP_DYNAMIC);
            return JS_UNDEFINED;
        }
        break;

    case kSystem_description:
        stringValue = cxx_OOStringFromJSValue(context, value);
        if (stringValue.has_value()) {
            OOJSSystemUniverseSetSystemDataForGalaxy(galaxy, system, std::string(KEY_DESCRIPTION), oo::PList(*stringValue), manifestID, OO_LAYER_OXP_DYNAMIC);
            return JS_UNDEFINED;
        }
        break;

    case kSystem_inhabitantsDescription:
        stringValue = cxx_OOStringFromJSValue(context, value);
        if (stringValue.has_value()) {
            OOJSSystemUniverseSetSystemDataForGalaxy(galaxy, system, std::string(KEY_INHABITANTS), oo::PList(*stringValue), manifestID, OO_LAYER_OXP_DYNAMIC);
            return JS_UNDEFINED;
        }
        break;

    case kSystem_government:
        if (OOJSValueToInt32(context, value, &iValue)) {
            if (iValue < 0)
                iValue = 0;
            if (7 < iValue)
                iValue = 7;
            OOJSSystemUniverseSetSystemDataForGalaxy(galaxy, system, std::string(KEY_GOVERNMENT), oo::PList::signedInteger(iValue), manifestID, OO_LAYER_OXP_DYNAMIC);
            return JS_UNDEFINED;
        }
        break;

    case kSystem_economy:
        if (OOJSValueToInt32(context, value, &iValue)) {
            if (iValue < 0)
                iValue = 0;
            if (7 < iValue)
                iValue = 7;
            OOJSSystemUniverseSetSystemDataForGalaxy(galaxy, system, std::string(KEY_ECONOMY), oo::PList::signedInteger(iValue), manifestID, OO_LAYER_OXP_DYNAMIC);
            return JS_UNDEFINED;
        }
        break;

    case kSystem_techLevel:
        if (OOJSValueToInt32(context, value, &iValue)) {
            if (iValue < 0)
                iValue = 0;
            if (15 < iValue)
                iValue = 15;
            OOJSSystemUniverseSetSystemDataForGalaxy(galaxy, system, std::string(KEY_TECHLEVEL), oo::PList::signedInteger(iValue), manifestID, OO_LAYER_OXP_DYNAMIC);
            return JS_UNDEFINED;
        }
        break;

    case kSystem_population:
        if (OOJSValueToInt32(context, value, &iValue)) {
            OOJSSystemUniverseSetSystemDataForGalaxy(galaxy, system, std::string(KEY_POPULATION), oo::PList::signedInteger(iValue), manifestID, OO_LAYER_OXP_DYNAMIC);
            return JS_UNDEFINED;
        }
        break;

    case kSystem_productivity:
        if (OOJSValueToInt32(context, value, &iValue)) {
            OOJSSystemUniverseSetSystemDataForGalaxy(galaxy, system, std::string(KEY_PRODUCTIVITY), oo::PList::signedInteger(iValue), manifestID, OO_LAYER_OXP_DYNAMIC);
            return JS_UNDEFINED;
        }
        break;

    default:
        OOJSReportBadPropertySelector(context, thisObj, magic, sSystemProperties, OOJS_COUNT(sSystemProperties));
        return OOJSNativeFailure(context);
    }

    OOJSReportBadPropertyValue(context, thisObj, magic, sSystemProperties, OOJS_COUNT(sSystemProperties), value);
    return OOJSNativeFailure(context);

    OOJS_NATIVE_EXIT
}

// *** Methods ***

// toString() : String
static JSValue SystemToString(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    PlayerEntity* player = OOPlayerForScripting();
    std::string systemDesc;

    const oo::PList systemData = OOJSSystemUniverseCurrentSystemData();
    const oo::PList* systemName = systemData.find(KEY_NAME); // -objectForKey:; "(null)" for none
    systemDesc = oo::str::format("[System %u:%u \"%s\"]", OOJSSystemPlayerCurrentGalaxyID(player), OOJSSystemPlayerCurrentSystemID(player), oo::DescriptionOf(systemName != nullptr ? *systemName : oo::PList()).c_str());
    OOJS_RETURN_PLIST(oo::PList(systemDesc));

    OOJS_NATIVE_EXIT
}

// addPlanet(key : String) : Planet
static JSValue SystemAddPlanet(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    PlayerEntity* player = OOPlayerForScripting();
    std::optional<std::string> key;
    OOPlanetEntity* planet = nil;

    if (argc > 0)
        key = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
    if (EXPECT_NOT(!key.has_value())) {
        cxx_OOJSReportBadArguments(context, "System", "addPlanet", MIN(argc, 1), OOJS_ARGV, std::nullopt, "string (planet key)");
        return OOJSNativeFailure(context);
    }

    OOJS_BEGIN_FULL_NATIVE(context)
    planet = OOJSSystemPlayerAddPlanet(player, *key);
    OOJS_END_FULL_NATIVE

    OOJS_RETURN_OBJECT(planet);

    OOJS_NATIVE_EXIT
}

// addMoon(key : String) : Planet
static JSValue SystemAddMoon(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    PlayerEntity* player = OOPlayerForScripting();
    std::optional<std::string> key;
    OOPlanetEntity* planet = nil;

    if (argc > 0)
        key = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
    if (EXPECT_NOT(!key.has_value())) {
        cxx_OOJSReportBadArguments(context, "System", "addMoon", MIN(argc, 1), OOJS_ARGV, std::nullopt, "string (planet key)");
        return OOJSNativeFailure(context);
    }

    OOJS_BEGIN_FULL_NATIVE(context)
    planet = OOJSSystemPlayerAddMoon(player, *key);
    OOJS_END_FULL_NATIVE

    OOJS_RETURN_OBJECT(planet);

    OOJS_NATIVE_EXIT
}

// sendAllShipsAway()
static JSValue SystemSendAllShipsAway(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    PlayerEntity* player = OOPlayerForScripting();

    OOJSSystemPlayerSendAllShipsAway(player);
    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}

// countShipsWithPrimaryRole(role : String [, relativeTo : Entity [, range : Number]]) : Number
static JSValue SystemCountShipsWithPrimaryRole(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    std::optional<std::string> role;
    Entity* relativeTo = nil;
    double range = -1;
    unsigned result;

    if (argc > 0)
        role = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
    if (EXPECT_NOT(!role.has_value())) {
        cxx_OOJSReportBadArguments(context, "System", "countShipsWithPrimaryRole", MIN(argc, 1), OOJS_ARGV, std::nullopt, "string (role)");
        return OOJSNativeFailure(context);
    }

    // Get optional arguments
    argc -= 1;
    JSValueConst* argv = OOJS_ARGV + 1;
    if (EXPECT_NOT(!GetRelativeToAndRange(context, "countShipsWithPrimaryRole", &argc, &argv, &relativeTo, &range)))
        return OOJSNativeFailure(context);

    OOJS_BEGIN_FULL_NATIVE(context)
    result = OOJSSystemUniverseCountShipsWithPrimaryRole(*role, range, relativeTo);
    OOJS_END_FULL_NATIVE

    OOJS_RETURN_INT(result);

    OOJS_NATIVE_EXIT
}

// countShipsWithRole(role : String [, relativeTo : Entity [, range : Number]]) : Number
static JSValue SystemCountShipsWithRole(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    std::optional<std::string> role;
    Entity* relativeTo = nil;
    double range = -1;
    unsigned result;

    if (argc > 0)
        role = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
    if (EXPECT_NOT(!role.has_value())) {
        cxx_OOJSReportBadArguments(context, "System", "countShipsWithRole", MIN(argc, 1), OOJS_ARGV, std::nullopt, "string (role)");
        return OOJSNativeFailure(context);
    }

    // Get optional arguments
    argc -= 1;
    JSValueConst* argv = OOJS_ARGV + 1;
    if (EXPECT_NOT(!GetRelativeToAndRange(context, "countShipsWithRole", &argc, &argv, &relativeTo, &range)))
        return OOJSNativeFailure(context);

    OOJS_BEGIN_FULL_NATIVE(context)
    result = OOJSSystemUniverseCountShipsWithRole(*role, range, relativeTo);
    OOJS_END_FULL_NATIVE

    OOJS_RETURN_INT(result);

    OOJS_NATIVE_EXIT
}

// shipsWithPrimaryRole(role : String [, relativeTo : Entity [, range : Number]]) : Array (Entity)
static JSValue SystemShipsWithPrimaryRole(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    std::optional<std::string> role;
    Entity* relativeTo = nil;
    double range = -1;
    std::vector<oo::ObjCRef<Entity*>> result;

    if (argc > 0)
        role = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
    if (EXPECT_NOT(!role.has_value())) {
        cxx_OOJSReportBadArguments(context, "System", "countShipsWithRole", MIN(argc, 1), OOJS_ARGV, std::nullopt, "string (role)");
        return OOJSNativeFailure(context);
    }

    // Get optional arguments
    argc -= 1;
    JSValueConst* argv = OOJS_ARGV + 1;
    if (EXPECT_NOT(!GetRelativeToAndRange(context, "shipsWithPrimaryRole", &argc, &argv, &relativeTo, &range)))
        return OOJSNativeFailure(context);

    // Search for entities
    OOJS_BEGIN_FULL_NATIVE(context)
    result = FindShips(HasPrimaryRolePredicate, &*role, relativeTo, range);
    OOJS_END_FULL_NATIVE

    OOJS_RETURN_PLIST(oo::PListFromObjects(result));

    OOJS_NATIVE_EXIT
}

// shipsWithRole(role : String [, relativeTo : Entity [, range : Number]]) : Array (Entity)
static JSValue SystemShipsWithRole(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    std::optional<std::string> role;
    Entity* relativeTo = nil;
    double range = -1;
    std::vector<oo::ObjCRef<Entity*>> result;

    if (argc > 0)
        role = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
    if (EXPECT_NOT(!role.has_value())) {
        cxx_OOJSReportBadArguments(context, "System", "shipsWithRole", MIN(argc, 1), OOJS_ARGV, std::nullopt, "string (role)");
        return OOJSNativeFailure(context);
    }

    // Get optional arguments
    argc -= 1;
    JSValueConst* subargv = OOJS_ARGV + 1;
    if (EXPECT_NOT(!GetRelativeToAndRange(context, "shipsWithRole", &argc, &subargv, &relativeTo, &range)))
        return OOJSNativeFailure(context);

    // Search for entities
    OOJS_BEGIN_FULL_NATIVE(context)
    result = FindShips(HasRolePredicate, &*role, relativeTo, range);
    OOJS_END_FULL_NATIVE

    OOJS_RETURN_PLIST(oo::PListFromObjects(result));

    OOJS_NATIVE_EXIT
}

// countEntitiesWithScanClass(scanClass : String [, relativeTo : Entity [, range : Number]]) : Number
static JSValue SystemCountEntitiesWithScanClass(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    OOScanClass scanClass = CLASS_NOT_SET;
    Entity* relativeTo = nil;
    double range = -1;
    unsigned result;

    if (argc > 0)
        scanClass = OOScanClassFromJSValue(context, OOJS_ARGV[0]);
    if (scanClass == CLASS_NOT_SET) {
        cxx_OOJSReportBadArguments(context, "System", "countEntitiesWithScanClass", MIN(argc, 1), OOJS_ARGV, std::nullopt, "string (scan class)");
        return OOJSNativeFailure(context);
    }

    // Get optional arguments
    argc -= 1;
    JSValueConst* argv = OOJS_ARGV + 1;
    if (EXPECT_NOT(!GetRelativeToAndRange(context, "countEntitiesWithScanClass", &argc, &argv, &relativeTo, &range)))
        return OOJSNativeFailure(context);

    OOJS_BEGIN_FULL_NATIVE(context)
    result = OOJSSystemUniverseCountShipsWithScanClass(scanClass, range, relativeTo);
    OOJS_END_FULL_NATIVE

    OOJS_RETURN_INT(result);

    OOJS_NATIVE_EXIT
}

// entitiesWithScanClass(scanClass : String [, relativeTo : Entity [, range : Number]]) : Array (Entity)
static JSValue SystemEntitiesWithScanClass(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    OOScanClass scanClass = CLASS_NOT_SET;
    Entity* relativeTo = nil;
    double range = -1;
    std::vector<oo::ObjCRef<Entity*>> result;

    if (argc > 0)
        scanClass = OOScanClassFromJSValue(context, OOJS_ARGV[0]);
    if (scanClass == CLASS_NOT_SET) {
        cxx_OOJSReportBadArguments(context, "System", "countEntitiesWithScanClass", MIN(argc, 1), OOJS_ARGV, std::nullopt, "string (scan class)");
        return OOJSNativeFailure(context);
    }

    // Get optional arguments
    argc -= 1;
    JSValueConst* argv = OOJS_ARGV + 1;
    if (EXPECT_NOT(!GetRelativeToAndRange(context, "entitiesWithScanClass", &argc, &argv, &relativeTo, &range)))
        return OOJSNativeFailure(context);

    // Search for entities
    OOJS_BEGIN_FULL_NATIVE(context)
    result = FindJSVisibleEntities(HasScanClassPredicate, &scanClass, relativeTo, range);
    OOJS_END_FULL_NATIVE

    OOJS_RETURN_PLIST(oo::PListFromObjects(result));

    OOJS_NATIVE_EXIT
}

// filteredEntities(this : Object, predicate : Function [, relativeTo : Entity [, range : Number]]) : Array (Entity)
static JSValue SystemFilteredEntities(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    JSValue jsThis = JS_UNDEFINED;
    JSValueConst predicate;
    Entity* relativeTo = nil;
    double range = -1;
    std::vector<oo::ObjCRef<Entity*>> result;

    // Get this and predicate arguments
    if (argc < 2 || !OOJSValueIsFunction(context, OOJS_ARGV[1])) {
        cxx_OOJSReportBadArguments(context, "System", "filteredEntities", argc, OOJS_ARGV, std::nullopt, "this, predicate function, and optional reference entity and range");
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
            cxx_OOJSReportBadArguments(context, "System", "filteredEntities", argc, OOJS_ARGV, std::nullopt, "this, predicate function, and optional reference entity and range");
            return OOJSNativeFailure(context);
        }
    }
    predicate = OOJS_ARGV[1];

    // Get optional arguments
    argc -= 2;
    JSValueConst* argv = OOJS_ARGV + 2;
    if (EXPECT_NOT(!GetRelativeToAndRange(context, "filteredEntities", &argc, &argv, &relativeTo, &range))) {
        JS_FreeValue(context, jsThis);
        return OOJSNativeFailure(context);
    }

    // Search for entities
    JSFunctionPredicateParameter param = { context, predicate, jsThis, NO };
    OOJSPauseTimeLimiter();
    @try {
        result = FindJSVisibleEntities(JSFunctionPredicate, &param, relativeTo, range);
    }
    @finally {
        OOJSResumeTimeLimiter();
        JS_FreeValue(context, jsThis);
    }

    // The predicate's exception has been reported (as before); stop the script.
    if (EXPECT_NOT(param.errorFlag))
        return OOJSNativeFailure(context);

    OOJS_RETURN_PLIST(oo::PListFromObjects(result));

    OOJS_NATIVE_EXIT
}

// locationFromCode(populator_named_region : String)
static JSValue SystemLocationFromCode(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    std::optional<std::string> code;
    if (argc > 0) {
        code = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
    }
    if (EXPECT_NOT(!code.has_value())) {
        cxx_OOJSReportBadArguments(context, "System", "locationFromCode", argc, OOJS_ARGV, std::nullopt, "location code");
        return OOJSNativeFailure(context);
    }
    OOSunEntity* sun = OOJSSystemUniverseSun();
    OOPlanetEntity* planet = OOJSSystemUniversePlanet();
    HPVector position = kZeroHPVector;
    if (sun == nil || planet == nil) {
        position = OOJSSystemUniverseLocationByCode("WITCHPOINT", nil, nil);
    } else {
        position = OOJSSystemUniverseLocationByCode(*code, sun, planet);
    }

    OOJS_RETURN_HPVECTOR(position);

    OOJS_NATIVE_EXIT
}

// addShips(role : String, count : Number [, position: Vector [, radius: Number]]) : Array of Ship
static JSValue SystemAddShips(OOJS_NATIVE_ARGS)
{
    return SystemAddShipsOrGroup(context, argc, OOJS_ARGV, NO);
}

// addGroup(role : String, count : Number [, position: Vector [, radius: Number]]) : ShipGroup
static JSValue SystemAddGroup(OOJS_NATIVE_ARGS)
{
    return SystemAddShipsOrGroup(context, argc, OOJS_ARGV, YES);
}

// addShipsToRoute(role : String, count : Number [, position: Number [, route: String]])
static JSValue SystemAddShipsToRoute(OOJS_NATIVE_ARGS)
{
    return SystemAddShipsOrGroupToRoute(context, argc, OOJS_ARGV, NO);
}

// addGroupToRoute(role : String, count : Number,  position: Number[, route: String])
static JSValue SystemAddGroupToRoute(OOJS_NATIVE_ARGS)
{
    return SystemAddShipsOrGroupToRoute(context, argc, OOJS_ARGV, YES);
}

/*	The legacy_* methods read argv entries beyond argc before checking argc, as
        before. This is safe because QuickJS pads argv with undefined up to each
        method's declared minimum argument count.
*/

// legacy_addShips(role : String, count : Number)
static JSValue SystemLegacyAddShips(OOJS_NATIVE_ARGS)
{
    cxx_OOStandardsDeprecated("system.legacy_addShips() is deprecated");
    OOJS_NATIVE_ENTER(context)

    std::optional<std::string> role;
    int32_t count;

    if (argc > 0)
        role = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
    if (EXPECT_NOT(!role.has_value() || !OOJSValueToInt32(context, OOJS_ARGV[1], &count) || argc < 2 || count < 1 || 64 < count)) {
        cxx_OOJSReportBadArguments(context, "System", "legacy_addShips", argc, OOJS_ARGV, std::nullopt, "role and positive count no greater than 64");
        return OOJSNativeFailure(context);
    }

    OOJS_BEGIN_FULL_NATIVE(context)
    while (count--)
        OOJSSystemUniverseWitchspaceShipWithPrimaryRole(*role);
    OOJS_END_FULL_NATIVE

    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}

// legacy_addSystemShips(role : String, count : Number, location : Number)
static JSValue SystemLegacyAddSystemShips(OOJS_NATIVE_ARGS)
{
    cxx_OOStandardsDeprecated("system.legacy_addSystemShips() is deprecated");
    OOJS_NATIVE_ENTER(context)

    double position;
    std::optional<std::string> role;
    int32_t count;

    if (argc > 0)
        role = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
    if (EXPECT_NOT(!role.has_value() || !OOJSValueToInt32(context, OOJS_ARGV[1], &count) || count < 1 || 64 < count || argc < 3 || JS_ToFloat64(context, &position, OOJS_ARGV[2]) != 0)) {
        cxx_OOJSReportBadArguments(context, "System", "legacy_addSystemShips", argc, OOJS_ARGV, std::nullopt, "role, positive count no greater than 64, and position along route");
        return OOJSNativeFailure(context);
    }

    OOJS_BEGIN_FULL_NATIVE(context)
    while (count--)
        OOJSSystemUniverseAddShipWithRoleNearRouteOneAt(*role, position);
    OOJS_END_FULL_NATIVE

    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}

// legacy_addShipsAt(role : String, count : Number, coordScheme : String, coords : vectorExpression)
static JSValue SystemLegacyAddShipsAt(OOJS_NATIVE_ARGS)
{
    cxx_OOStandardsDeprecated("system.legacy_addShipsAt() is deprecated");
    OOJS_NATIVE_ENTER(context)

    PlayerEntity* player = OOPlayerForScripting();
    HPVector where;
    std::optional<std::string> role;
    int32_t count;
    std::optional<std::string> coordScheme;
    std::string arg;

    if (argc > 0)
        role = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
    coordScheme = cxx_OOStringFromJSValue(context, OOJS_ARGV[2]);
    if (EXPECT_NOT(!role.has_value() || !OOJSValueToInt32(context, OOJS_ARGV[1], &count) || count < 1 || 64 < count || !coordScheme.has_value() || argc < 4 || !VectorFromArgumentListNoError(context, argc - 3, OOJS_ARGV + 3, &where, NULL))) {
        cxx_OOJSReportBadArguments(context, "System", "legacy_addShipsAt", argc, OOJS_ARGV, std::nullopt, "role, positive count no greater than 64, coordinate scheme and coordinates");
        return OOJSNativeFailure(context);
    }

    OOJS_BEGIN_FULL_NATIVE(context)
    arg = oo::str::format("%s %d %s %f %f %f", role->c_str(), count, coordScheme->c_str(), where.x, where.y, where.z);
    OOJSSystemPlayerAddShipsAt(player, arg);
    OOJS_END_FULL_NATIVE

    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}

// legacy_addShipsAtPrecisely(role : String, count : Number, coordScheme : String, coords : vectorExpression)
static JSValue SystemLegacyAddShipsAtPrecisely(OOJS_NATIVE_ARGS)
{
    cxx_OOStandardsDeprecated("system.legacy_addShipsAtPrecisely() is deprecated");
    OOJS_NATIVE_ENTER(context)

    PlayerEntity* player = OOPlayerForScripting();
    HPVector where;
    std::optional<std::string> role;
    int32_t count;
    std::optional<std::string> coordScheme;
    std::string arg;

    if (argc > 0)
        role = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
    coordScheme = cxx_OOStringFromJSValue(context, OOJS_ARGV[2]);
    if (EXPECT_NOT(!role.has_value() || !OOJSValueToInt32(context, OOJS_ARGV[1], &count) || count < 1 || 64 < count || !coordScheme.has_value() || argc < 4 || !VectorFromArgumentListNoError(context, argc - 3, OOJS_ARGV + 3, &where, NULL))) {
        cxx_OOJSReportBadArguments(context, "System", "legacy_addShipsAtPrecisely", argc, OOJS_ARGV, std::nullopt, "role, positive count no greater than 64, coordinate scheme and coordinates");
        return OOJSNativeFailure(context);
    }

    OOJS_BEGIN_FULL_NATIVE(context)
    arg = oo::str::format("%s %d %s %f %f %f", role->c_str(), count, coordScheme->c_str(), where.x, where.y, where.z);
    OOJSSystemPlayerAddShipsAtPrecisely(player, arg);
    OOJS_END_FULL_NATIVE

    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}

// legacy_addShipsWithinRadius(role : String, count : Number, coordScheme : String, coords : vectorExpression, radius : Number)
static JSValue SystemLegacyAddShipsWithinRadius(OOJS_NATIVE_ARGS)
{
    cxx_OOStandardsDeprecated("system.legacy_addShipsWithinRadius() is deprecated");
    OOJS_NATIVE_ENTER(context)

    PlayerEntity* player = OOPlayerForScripting();
    HPVector where;
    double radius;
    std::optional<std::string> role;
    int32_t count;
    std::optional<std::string> coordScheme;
    std::string arg;
    int consumed = 0;

    if (argc > 0)
        role = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
    if (argc > 2)
        coordScheme = cxx_OOStringFromJSValue(context, OOJS_ARGV[2]);
    if (EXPECT_NOT(!role.has_value() || !OOJSValueToInt32(context, OOJS_ARGV[1], &count) || count < 1 || 64 < count || !coordScheme.has_value() || argc < 5 || !VectorFromArgumentListNoError(context, argc - 3, OOJS_ARGV + 3, &where, &consumed) || JS_ToFloat64(context, &radius, OOJS_ARGV[3 + consumed]) != 0)) {
        cxx_OOJSReportBadArguments(context, "System", "legacy_addShipWithinRadius", argc, OOJS_ARGV, std::nullopt, "role, positive count no greater than 64, coordinate scheme, coordinates and radius");
        return OOJSNativeFailure(context);
    }

    OOJS_BEGIN_FULL_NATIVE(context)
    arg = oo::str::format("%s %d %s %f %f %f %f", role->c_str(), count, coordScheme->c_str(), where.x, where.y, where.z, radius);
    OOJSSystemPlayerAddShipsWithinRadius(player, arg);
    OOJS_END_FULL_NATIVE

    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}

// legacy_spawnShip(key : string)
static JSValue SystemLegacySpawnShip(OOJS_NATIVE_ARGS)
{
    cxx_OOStandardsDeprecated("system.legacy_spawnShip() is deprecated");
    OOJS_NATIVE_ENTER(context)

    std::optional<std::string> key;
    OOPlayerForScripting(); // For backwards-compatibility

    if (argc > 0)
        key = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
    if (!key.has_value()) {
        cxx_OOJSReportBadArguments(context, "System", "legacy_spawnShip", MIN(argc, 1), OOJS_ARGV, std::nullopt, "string (ship key)");
        return OOJSNativeFailure(context);
    }

    OOJS_BEGIN_FULL_NATIVE(context)
    OOJSSystemUniverseSpawnShip(*key);
    OOJS_END_FULL_NATIVE

    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}

// *** Static methods ***

// systemNameForID(ID : Number) : String
static JSValue SystemStaticSystemNameForID(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    int32_t systemID;

    if (argc < 1 || !OOJSValueToInt32(context, OOJS_ARGV[0], &systemID) || systemID < -1 || kOOMaximumSystemID < systemID) // -1 interstellar space!
    {
        cxx_OOJSReportBadArguments(context, "System", "systemNameForID", MIN(argc, 1), OOJS_ARGV, std::nullopt, "system ID");
        return OOJSNativeFailure(context);
    }

    if (systemID == -1)
        OOJS_RETURN_PLIST(oo::PList(std::string(OO_DESC("interstellar-space"))));
    else
        OOJS_RETURN_STRING_OR_NULL(OOJSSystemUniverseGetSystemName(systemID));

    OOJS_NATIVE_EXIT
}

// systemIDForName(name : String) : Number
static JSValue SystemStaticSystemIDForName(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    std::optional<std::string> name;
    unsigned result;

    if (argc > 0)
        name = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
    if (!name.has_value()) {
        cxx_OOJSReportBadArguments(context, "System", "systemIDForName", MIN(argc, 1), OOJS_ARGV, std::nullopt, "string");
        return OOJSNativeFailure(context);
    }

    OOJS_BEGIN_FULL_NATIVE(context)

    result = OOJSSystemUniverseFindSystemFromName(*name);

    OOJS_END_FULL_NATIVE

    // As with INT_TO_JSVAL(), the unsigned result is reinterpreted as signed (so not found is -1).
    OOJS_RETURN_INT((int32_t)result);

    OOJS_NATIVE_EXIT
}

// infoForSystem(galaxyID : Number, systemID : Number) : SystemInfo
static JSValue SystemStaticInfoForSystem(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    int32_t galaxyID;
    int32_t systemID;

    if (argc < 2 || !OOJSValueToInt32(context, OOJS_ARGV[0], &galaxyID) || !OOJSValueToInt32(context, OOJS_ARGV[1], &systemID)) {
        cxx_OOJSReportBadArguments(context, "System", "infoForSystem", argc, OOJS_ARGV, std::nullopt, "galaxy ID and system ID");
        return OOJSNativeFailure(context);
    }

    if (galaxyID < 0 || galaxyID > kOOMaximumGalaxyID) {
        cxx_OOJSReportBadArguments(context, "System", "infoForSystem", 1, OOJS_ARGV, "Invalid galaxy ID", oo::str::format("number in the range 0 to %u", kOOMaximumGalaxyID));
        return OOJSNativeFailure(context);
    }

    if (systemID < kOOMinimumSystemID || systemID > kOOMaximumSystemID) {
        cxx_OOJSReportBadArguments(context, "System", "infoForSystem", 1, OOJS_ARGV + 1, "Invalid system ID", oo::str::format("number in the range %i to %i", kOOMinimumSystemID, kOOMaximumSystemID));
        return OOJSNativeFailure(context);
    }

    OOJS_RETURN(GetJSSystemInfoForSystem(context, galaxyID, systemID));

    OOJS_NATIVE_EXIT
}

static JSValue SystemAddVisualEffect(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    std::optional<std::string> key;
    HPVector where;

    int consumed = 0;

    if (argc > 0)
        key = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
    if (!key.has_value()) {
        cxx_OOJSReportBadArguments(context, "System", "addVisualEffect", MIN(argc, 1), &OOJS_ARGV[0], std::nullopt, "string (key)");
        return OOJSNativeFailure(context);
    }

    if (!VectorFromArgumentListNoError(context, argc - 1, OOJS_ARGV + 1, &where, &consumed)) {
        cxx_OOJSReportBadArguments(context, "System", "addVisualEffect", MIN(argc - 1, 1), &OOJS_ARGV[1], std::nullopt, "vector");
        return OOJSNativeFailure(context);
    }

    OOVisualEffectEntity* result = nil;

    OOJS_BEGIN_FULL_NATIVE(context)

    result = OOJSSystemUniverseAddVisualEffectAt(where, *key);

    OOJS_END_FULL_NATIVE

    OOJS_RETURN_OBJECT(result);

    OOJS_NATIVE_EXIT
}

// Get a property of a settings object. As before, a failed get is treated like a missing property.
static JSValue GetParam(JSContext* context, JSValueConst object, const char* key)
{
    JSValue value = JS_GetPropertyStr(context, object, key);
    if (JS_IsException(value)) {
        OOJSReportPendingException(context);
        return JS_UNDEFINED;
    }
    return value;
}

static JSValue SystemSetPopulator(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    std::optional<std::string> key;
    oo::PList settings;
    JSValue params = JS_UNDEFINED;

    if (argc < 1) {
        cxx_OOJSReportBadArguments(context, "System", "setPopulator", MIN(argc, 0), &OOJS_ARGV[0], std::nullopt, "string (key), object (settings)");
        return OOJSNativeFailure(context);
    }
    key = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
    if (!key.has_value()) {
        cxx_OOJSReportBadArguments(context, "System", "setPopulator", MIN(argc, 0), &OOJS_ARGV[0], std::nullopt, "key, settings");
        return OOJSNativeFailure(context);
    }
    if (argc < 2 || JS_IsNull(OOJS_ARGV[1])) {
        // clearing
        OOJSSystemUniverseSetPopulatorSetting(*key, oo::PList());
    } else {
        // adding
        // As with SpiderMonkey's JS_ValueToObject(), primitives are boxed. (undefined gave no object, which then could not work; treat it as invalid.)
        if (!JS_IsUndefined(OOJS_ARGV[1])) {
            params = JS_ToObject(context, OOJS_ARGV[1]);
            if (JS_IsException(params)) {
                JS_FreeValue(context, JS_GetException(context));
                params = JS_UNDEFINED;
            }
        }
        if (!JS_IsObject(params)) {
            cxx_OOJSReportBadArguments(context, "System", "setPopulator", MIN(argc, 1), OOJS_ARGV, std::nullopt, "key, settings");
            return OOJSNativeFailure(context);
        }
        JSValue callback = GetParam(context, params, "callback");
        if (JS_IsUndefined(callback)) {
            JS_FreeValue(context, params);
            cxx_OOJSReportBadArguments(context, "System", "setPopulator", MIN(argc, 1), OOJS_ARGV, std::nullopt, "settings must have a 'callback' property.");
            return OOJSNativeFailure(context);
        }

        // The definition is converted (cxx::OOJSPopulatorDefinition), and only alloc/init makes its
        // facade (ADR-0056 amendment oo-o89 item 2); the reference releases it where -release did.
        oo::ObjCRef<OOJSPopulatorDefinition*> populator = oo::adoptObjC(OOJSSystemNewPopulatorDefinition());
        oo::ToCxx(populator.get())->setCallback(callback); // Takes its own reference.
        JS_FreeValue(context, callback);

        // (The SpiderMonkey version converted argv[1] directly; params is the same object for any object argument.)
        settings = cxx_OOJSPListFromJSObject(context, params);
        oo::PList::Dict* settingsDict = settings.getIf<oo::PList::Dict>(); // messages to a nil dictionary did nothing
        if (settingsDict != nullptr)
            (*settingsDict)["callbackObj"] = oo::PListObject(populator.get());

        JSValue coords = GetParam(context, params, "coordinates");
        if (!JS_IsUndefined(coords)) {
            Vector coordinates = kZeroVector;
            if (JSValueToVector(context, coords, &coordinates)) {
                // convert vector in NS-storable form (three floats)
                if (settingsDict != nullptr)
                    (*settingsDict)["coordinates"] = oo::PList(oo::PList::Array { oo::PList::singleReal(coordinates.x), oo::PList::singleReal(coordinates.y), oo::PList::singleReal(coordinates.z) });
            }
        }
        JS_FreeValue(context, coords);
        JS_FreeValue(context, params);

        populator = nullptr; // -release

        // A failed vector conversion is ignored, as before, but QuickJS natives must not return normally with an exception pending.
        if (EXPECT_NOT(JS_HasException(context)))
            return JS_EXCEPTION;

        OOJSSystemUniverseSetPopulatorSetting(*key, settings);
    }

    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}

static JSValue SystemSetWaypoint(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    std::optional<std::string> key;
    oo::PList settings;
    HPVector position;
    Quaternion orientation;

    if (argc < 1) {
        cxx_OOJSReportBadArguments(context, "System", "setWaypoint", MIN(argc, 0), &OOJS_ARGV[0], std::nullopt, "key, position, orientation, definition");
        return OOJSNativeFailure(context);
    }
    key = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
    if (!key.has_value()) {
        cxx_OOJSReportBadArguments(context, "System", "setWaypoint", MIN(argc, 0), &OOJS_ARGV[0], std::nullopt, "key, position, orientation, definition");
        return OOJSNativeFailure(context);
    }
    if (argc < 4 || JS_IsNull(OOJS_ARGV[3])) {
        // clearing
        OOJSSystemUniverseDefineWaypoint(oo::PList(), *key);
    } else {
        // adding
        if (!JSValueToHPVector(context, OOJS_ARGV[1], &position)) {
            cxx_OOJSReportBadArguments(context, "System", "setWaypoint", MIN(argc, 2), OOJS_ARGV, std::nullopt, "key, position, orientation, definition");
            return OOJSNativeFailure(context);
        }
        if (!JSValueToQuaternion(context, OOJS_ARGV[2], &orientation)) {
            cxx_OOJSReportBadArguments(context, "System", "setWaypoint", MIN(argc, 3), OOJS_ARGV, std::nullopt, "key, position, orientation, definition");
            return OOJSNativeFailure(context);
        }
        if (!JS_IsObject(OOJS_ARGV[3]) || JS_IsNull(OOJS_ARGV[3])) {
            cxx_OOJSReportBadArguments(context, "System", "setWaypoint", MIN(argc, 4), OOJS_ARGV, std::nullopt, "key, position, orientation, definition");
            return OOJSNativeFailure(context);
        }

        settings = cxx_OOJSPListFromJSObject(context, OOJS_ARGV[3]); // a copy, as -mutableCopy was
        if (oo::PList::Dict* settingsDict = settings.getIf<oo::PList::Dict>()) // messages to a nil copy did nothing
        {
            (*settingsDict)["position"] = oo::PList(oo::PList::Array { oo::PList(position.x), oo::PList(position.y), oo::PList(position.z) });
            (*settingsDict)["orientation"] = oo::PList(oo::PList::Array { oo::PList(orientation.w), oo::PList(orientation.x), oo::PList(orientation.y), oo::PList(orientation.z) });
        }

        OOJSSystemUniverseDefineWaypoint(settings, *key);
    }

    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}

// *** Helper functions ***

// Shared implementation of addShips() and addGroup().
static JSValue SystemAddShipsOrGroup(JSContext* context, int argc, JSValueConst* argv, bool isGroup)
{
    OOJS_NATIVE_ENTER(context)

    std::optional<std::string> role;
    int32_t count = 0;
    int consumed = 0;
    HPVector where;
    double radius = (double)NSNotFound; // a negative value means
    oo::PList result;

    std::string func = isGroup ? "addGroup" : "addShips";

    if (argc > 0)
        role = cxx_OOStringFromJSValue(context, argv[0]);
    if (!role.has_value()) {
        cxx_OOJSReportBadArguments(context, "System", func, MIN(argc, 1), &argv[0], std::nullopt, "string (role)");
        return JS_EXCEPTION;
    }
    if (argc < 2 || !OOJSValueToInt32(context, argv[1], &count) || count < 1 || 64 < count) {
        cxx_OOJSReportBadArguments(context, "System", func, MIN(argc - 1, 1), &argv[1], std::nullopt, "number (positive count no greater than 64)");
        return JS_EXCEPTION;
    }

    if (argc < 3) {
        where = OOJSSystemUniverseGetWitchspaceExitPosition();
        radius = SCANNER_MAX_RANGE;
    } else {
        if (!VectorFromArgumentListNoError(context, argc - 2, argv + 2, &where, &consumed)) {
            cxx_OOJSReportBadArguments(context, "System", func, MIN(argc - 2, 1), &argv[2], std::nullopt, "vector");
            return JS_EXCEPTION;
        }

        if (argc > 2 + consumed) {
            if (JS_ToFloat64(context, &radius, argv[2 + consumed]) < 0) {
                cxx_OOJSReportBadArguments(context, "System", func, MIN(argc - 2 - consumed, 1), &argv[2 + consumed], std::nullopt, "number (radius)");
                return JS_EXCEPTION;
            }
        }
    }

    OOJS_BEGIN_FULL_NATIVE(context)
    // Note: the use of witchspace-in effects (as in legacy_addShips) depends on proximity to the witchpoint.
    const std::vector<oo::ObjCRef<ShipEntity*>> added = OOJSSystemUniverseAddShipsAt(where, *role, count, radius, isGroup);
    if (!added.empty())
        result = oo::PListFromObjects(added); // null where no ship was added, as before

    if (isGroup) {
        const std::vector<oo::ObjCRef<ShipEntity*>> ships = oo::ObjCRefsIn<ShipEntity*>(result);
        if (ships.size() > 0)
            result = oo::PListObject(OOJSSystemShipGroup(ships[0].get()));
        else
            result = oo::PList();
    }
    OOJS_END_FULL_NATIVE

    OOJS_RETURN_PLIST(result);

    OOJS_NATIVE_EXIT
}

static JSValue SystemAddShipsOrGroupToRoute(JSContext* context, int argc, JSValueConst* argv, bool isGroup)
{
    OOJS_NATIVE_ENTER(context)

    std::optional<std::string> role;
    std::optional<std::string> route = "st"; // default route witchpoint -> station. ("st" itself is not selectable by script)
    static const std::set<std::string> validRoutes = { "wp", "pw", "ws", "sw", "sp", "ps" };
    int32_t count = 0;
    double where = (double)NSNotFound; // a negative value means random positioning!
    oo::PList result;

    std::string func = isGroup ? "addGroup" : "addShips";

    if (argc > 0)
        role = cxx_OOStringFromJSValue(context, argv[0]);
    if (!role.has_value()) {
        cxx_OOJSReportBadArguments(context, "System", func, MIN(argc, 1), &argv[0], std::nullopt, "string (role)");
        return JS_EXCEPTION;
    }
    if (argc < 2 || !OOJSValueToInt32(context, argv[1], &count) || count < 1 || 64 < count) {
        cxx_OOJSReportBadArguments(context, "System", func, MIN(argc - 1, 1), &argv[1], std::nullopt, "number (positive count no greater than 64)");
        return JS_EXCEPTION;
    }

    if (argc > 2) {
        if (JS_ToFloat64(context, &where, argv[2]) != 0 || !isfinite(where) || where < 0.0f || where > 1.0f) {
            cxx_OOJSReportBadArguments(context, "System", func, MIN(argc - 2, 1), &argv[2], std::nullopt, "number (position along route)");
            return JS_EXCEPTION;
        }

        if (argc > 3) {
            route = cxx_OOStringFromJSValue(context, argv[3]);
            if (route.has_value())
                route = oo::str::lowercase(*route);

            if (!route.has_value() || validRoutes.count(*route) == 0) {
                cxx_OOJSReportBadArguments(context, "System", func, MIN(argc - 3, 1), &argv[3], std::nullopt, "string (route specifier)");
                return JS_EXCEPTION;
            }
        }
    }

    OOJS_BEGIN_FULL_NATIVE(context)
    // Note: the use of witchspace-in effects (as in legacy_addShips) depends on proximity to the witchpoint.
    const std::vector<oo::ObjCRef<ShipEntity*>> added = OOJSSystemUniverseAddShipsToRoute(*route, *role, count, where, isGroup);
    if (!added.empty())
        result = oo::PListFromObjects(added); // null where no ship was added, as before

    if (isGroup) {
        const std::vector<oo::ObjCRef<ShipEntity*>> ships = oo::ObjCRefsIn<ShipEntity*>(result);
        if (ships.size() > 0)
            result = oo::PListObject(OOJSSystemShipGroup(ships[0].get()));
        else
            result = oo::PList();
    }
    OOJS_END_FULL_NATIVE

    OOJS_RETURN_PLIST(result);

    OOJS_NATIVE_EXIT
}

static BOOL GetRelativeToAndRange(JSContext* context, const std::string& methodName, int* ioArgc, JSValueConst** ioArgv, Entity** outRelativeTo, double* outRange)
{
    OOJS_PROFILE_ENTER

    // No NULL arguments accepted.
    assert(ioArgc && ioArgv && outRelativeTo && outRange);

    // Get optional argument relativeTo : Entity
    if (*ioArgc != 0) {
        if (EXPECT_NOT(JS_IsNull(**ioArgv) || !JSValueToEntity(context, **ioArgv, outRelativeTo))) {
            cxx_OOJSReportBadArguments(context, "System", methodName, 1, *ioArgv, std::nullopt, "entity");
            return NO;
        }
        (*ioArgv)++;
        (*ioArgc)--;
    }

    // Get optional argument range : Number
    if (*ioArgc != 0) {
        if (EXPECT_NOT(JS_ToFloat64(context, outRange, **ioArgv) != 0)) {
            cxx_OOJSReportBadArguments(context, "System", methodName, 1, *ioArgv, std::nullopt, "number");
            return NO;
        }
        (*ioArgv)++;
        (*ioArgc)--;
    }

    return YES;

    OOJS_PROFILE_EXIT
}

static std::vector<oo::ObjCRef<Entity*>> FindJSVisibleEntities(EntityFilterPredicate predicate, void* parameter, Entity* relativeTo, double range)
{
    OOJS_PROFILE_ENTER

    std::vector<oo::ObjCRef<Entity*>> result;
    BinaryOperationPredicateParameter param = {
        JSEntityIsJavaScriptSearchablePredicate, NULL,
        predicate, parameter
    };

    result = OOJSSystemUniverseFindEntitiesMatchingPredicate(ANDPredicate, &param, range, relativeTo);

    if (relativeTo != nil && !oo::ToCxx(relativeTo)->getIsPlayer()) {
        // -sortUsingFunction:context: with the same comparison (a stable sort: GNUstep's is timsort).
        std::stable_sort(result.begin(), result.end(), [relativeTo](const oo::ObjCRef<Entity*>& a, const oo::ObjCRef<Entity*>& b) {
            return CompareEntitiesByDistance(a.get(), b.get(), relativeTo) == OOOrderedAscending;
        });
    }
    return result; // empty for no matches, as the empty array was

    OOJS_PROFILE_EXIT
}

static std::vector<oo::ObjCRef<Entity*>> FindShips(EntityFilterPredicate predicate, void* parameter, Entity* relativeTo, double range)
{
    OOJS_PROFILE_ENTER

    BinaryOperationPredicateParameter param = {
        IsShipPredicate, NULL,
        predicate, parameter
    };
    return FindJSVisibleEntities(ANDPredicate, &param, relativeTo, range);

    OOJS_PROFILE_EXIT
}

static OOComparisonResult CompareEntitiesByDistance(id a, id b, void* relativeTo)
{
    OOJS_PROFILE_ENTER

    Entity *ea = a,
           *eb = b,
           *r = (id)relativeTo;
    float d1, d2;

    d1 = HPdistance2(ea->_cxxEntity->position, r->_cxxEntity->position);
    d2 = HPdistance2(eb->_cxxEntity->position, r->_cxxEntity->position);

    if (d1 < d2)
        return OOOrderedAscending;
    else if (d1 > d2)
        return OOOrderedDescending;
    else
        return OOOrderedSame;

    OOJS_PROFILE_EXIT
}
