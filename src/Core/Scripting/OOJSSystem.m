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
#import "OOJSSystemInfo.h"
#import "OOJSVector.h"
#import "OOPlanetEntity.h"
#import "PlayerEntityScriptMethods.h"
#import "Universe.h"

#import "EntityOOJavaScriptExtensions.h"
#import "OOCollectionExtractors.h"
#import "OOConstToJSString.h"
#import "OOConstToString.h"
#import "OODebugStandards.h"
#import "OOEntityFilterPredicate.h"
#import "OOFilteringEnumerator.h"
#import "OOJSPopulatorDefinition.h"
#import "OOJSScript.h"

static JSClassID sSystemClassID;

// Support functions for entity search methods.
static BOOL GetRelativeToAndRange(JSContext* context, NSString* methodName, int* ioArgc, JSValueConst** ioArgv, Entity** outRelativeTo, double* outRange);
static NSArray* FindJSVisibleEntities(EntityFilterPredicate predicate, void* parameter, Entity* relativeTo, double range);
static NSArray* FindShips(EntityFilterPredicate predicate, void* parameter, Entity* relativeTo, double range);
static NSComparisonResult CompareEntitiesByDistance(id a, id b, void* relativeTo);

static JSValue SystemAddShipsOrGroup(JSContext* context, int argc, JSValueConst* argv, BOOL isGroup);
static JSValue SystemAddShipsOrGroupToRoute(JSContext* context, int argc, JSValueConst* argv, BOOL isGroup);

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

    id result = nil;
    PlayerEntity* player = nil;
    NSDictionary* systemData = nil;
    BOOL handled = NO;

    player = OOPlayerForScripting();

    // Handle cases which don't require systemData.
    switch (magic) {
    case kSystem_ID:
        return JS_NewInt32(context, [player currentSystemID]);

    case kSystem_isInterstellarSpace:
        return OOJSValueFromBOOL([UNIVERSE inInterstellarSpace]);

    case kSystem_mainStation:
        result = [UNIVERSE station];
        handled = YES;
        break;

    case kSystem_mainPlanet:
        result = [UNIVERSE planet];
        handled = YES;
        break;

    case kSystem_sun:
        result = [UNIVERSE sun];
        handled = YES;
        break;

    case kSystem_planets:
        result = [[[UNIVERSE planets] objectEnumeratorFilteredWithSelector:@selector(isVisibleToScripts)] allObjects];
        handled = YES;
        break;

    case kSystem_stations:
        result = [UNIVERSE stations];
        handled = YES;
        break;

    case kSystem_waypoints:
        result = [UNIVERSE currentWaypoints];
        handled = YES;
        break;

    case kSystem_wormholes:
        result = [UNIVERSE wormholes];
        handled = YES;
        break;

    case kSystem_allShips:
        OOJS_BEGIN_FULL_NATIVE(context)
        result = [UNIVERSE findShipsMatchingPredicate:JSEntityIsJavaScriptSearchablePredicate parameter:NULL inRange:-1 ofEntity:nil];
        OOJS_END_FULL_NATIVE
        handled = YES;
        break;

    case kSystem_allDemoShips:
        OOJS_BEGIN_FULL_NATIVE(context)
        result = [UNIVERSE findShipsMatchingPredicate:JSEntityIsDemoShipPredicate parameter:NULL inRange:-1 ofEntity:nil];
        OOJS_END_FULL_NATIVE
        handled = YES;
        break;

    case kSystem_allVisualEffects:
        OOJS_BEGIN_FULL_NATIVE(context)
        result = [UNIVERSE findVisualEffectsMatchingPredicate:JSEntityIsJavaScriptSearchablePredicate parameter:NULL inRange:-1 ofEntity:nil];
        OOJS_END_FULL_NATIVE
        handled = YES;
        break;

    case kSystem_ambientLevel:
        return JS_NewNumber(context, [UNIVERSE ambientLightLevel]);

    case kSystem_info:
        return GetJSSystemInfoForSystem(context, [player currentGalaxyID], [player currentSystemID]);

    case kSystem_pseudoRandomNumber:
        return JS_NewNumber(context, [player systemPseudoRandomFloat]);

    case kSystem_pseudoRandom100:
        return JS_NewInt32(context, [player systemPseudoRandom100]);

    case kSystem_pseudoRandom256:
        return JS_NewInt32(context, [player systemPseudoRandom256]);

    case kSystem_breakPattern:
        return OOJSValueFromBOOL([UNIVERSE witchspaceBreakPattern]);

    case kSystem_populatorSettings:
        return OOJSValueFromNativeObject(context, [UNIVERSE getPopulatorSettings]);
    }

    if (!handled) {
        // Handle cases which do require systemData.
        if (EXPECT(![UNIVERSE inInterstellarSpace])) {
            systemData = [UNIVERSE currentSystemData];

            switch (magic) {
            case kSystem_name:
                result = [systemData objectForKey:KEY_NAME];
                break;

            case kSystem_description:
                result = [systemData objectForKey:KEY_DESCRIPTION];
                break;

            case kSystem_inhabitantsDescription:
                result = [systemData objectForKey:KEY_INHABITANTS];
                break;

            case kSystem_government:
                return JS_NewInt32(context, [systemData oo_intForKey:KEY_GOVERNMENT]);

            case kSystem_governmentDescription:
                result = OODisplayStringFromGovernmentID([systemData oo_intForKey:KEY_GOVERNMENT]);
                if (result == nil)
                    result = DESC(@"not-applicable");
                break;

            case kSystem_economy:
                return JS_NewInt32(context, [systemData oo_intForKey:KEY_ECONOMY]);

            case kSystem_economyDescription:
                result = OODisplayStringFromEconomyID([systemData oo_intForKey:KEY_ECONOMY]);
                if (result == nil)
                    result = DESC(@"not-applicable");
                break;

            case kSystem_techLevel:
                return JS_NewInt32(context, [systemData oo_intForKey:KEY_TECHLEVEL]);

            case kSystem_population:
                return JS_NewInt32(context, [systemData oo_intForKey:KEY_POPULATION]);

            case kSystem_productivity:
                return JS_NewInt32(context, [systemData oo_intForKey:KEY_PRODUCTIVITY]);

            default:
                OOJSReportBadPropertySelector(context, this, magic, sSystemProperties, OOJS_COUNT(sSystemProperties));
                return OOJSNativeFailure(context);
            }
        } else {
            // if in interstellar space, systemData values are null & void!
            switch (magic) {
            case kSystem_name:
                result = DESC(@"interstellar-space");
                break;

            case kSystem_description:
                result = @"";
                break;

            case kSystem_inhabitantsDescription:
                result = DESC(@"not-applicable");
                break;

            case kSystem_government:
                return JS_NewInt32(context, -1);

            case kSystem_governmentDescription:
                result = DESC(@"not-applicable");
                break;

            case kSystem_economy:
                return JS_NewInt32(context, -1);

            case kSystem_economyDescription:
                result = DESC(@"not-applicable");
                break;

            case kSystem_techLevel:
                return JS_NewInt32(context, -1);

            case kSystem_population:
                return JS_NewInt32(context, 0);

            case kSystem_productivity:
                return JS_NewInt32(context, 0);

            default:
                OOJSReportBadPropertySelector(context, this, magic, sSystemProperties, OOJS_COUNT(sSystemProperties));
                return OOJSNativeFailure(context);
            }
        }
    }

    return OOJSValueFromNativeObject(context, result);

    OOJS_NATIVE_EXIT
}

static JSValue SystemSetProperty(OOJS_SETTER_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    PlayerEntity* player = nil;
    OOGalaxyID galaxy;
    OOSystemID system;
    NSString* stringValue = nil;
    NSString* manifest = nil;
    double fValue;
    int32_t iValue;
    int bValue;

    player = OOPlayerForScripting();

    galaxy = [player currentGalaxyID];
    system = [player currentSystemID];

    switch (magic) {
    case kSystem_ambientLevel:
        if (JS_ToFloat64(context, &fValue, value) == 0) {
            [UNIVERSE setAmbientLightLevel:fValue];
            [UNIVERSE setLighting];
            return JS_UNDEFINED;
        }
        break;

    case kSystem_breakPattern:
        if ((bValue = JS_ToBool(context, value)) >= 0) {
            [UNIVERSE setWitchspaceBreakPattern:bValue];
            return JS_UNDEFINED;
        }

        break;
    default: {
    } // do nothing yet
    }

    if (system == -1)
        return JS_UNDEFINED; // Can't change anything else in interstellar space.

    manifest = [[OOJSScript currentlyRunningScript] propertyNamed:kLocalManifestProperty];

    switch (magic) {
    case kSystem_name:
        stringValue = OOStringFromJSValue(context, value);
        if (stringValue != nil) {
            [UNIVERSE setSystemDataForGalaxy:galaxy planet:system key:KEY_NAME value:stringValue fromManifest:manifest forLayer:OO_LAYER_OXP_DYNAMIC];
            return JS_UNDEFINED;
        }
        break;

    case kSystem_description:
        stringValue = OOStringFromJSValue(context, value);
        if (stringValue != nil) {
            [UNIVERSE setSystemDataForGalaxy:galaxy planet:system key:KEY_DESCRIPTION value:stringValue fromManifest:manifest forLayer:OO_LAYER_OXP_DYNAMIC];
            return JS_UNDEFINED;
        }
        break;

    case kSystem_inhabitantsDescription:
        stringValue = OOStringFromJSValue(context, value);
        if (stringValue != nil) {
            [UNIVERSE setSystemDataForGalaxy:galaxy planet:system key:KEY_INHABITANTS value:stringValue fromManifest:manifest forLayer:OO_LAYER_OXP_DYNAMIC];
            return JS_UNDEFINED;
        }
        break;

    case kSystem_government:
        if (OOJSValueToInt32(context, value, &iValue)) {
            if (iValue < 0)
                iValue = 0;
            if (7 < iValue)
                iValue = 7;
            [UNIVERSE setSystemDataForGalaxy:galaxy planet:system key:KEY_GOVERNMENT value:[NSNumber numberWithInt:iValue] fromManifest:manifest forLayer:OO_LAYER_OXP_DYNAMIC];
            return JS_UNDEFINED;
        }
        break;

    case kSystem_economy:
        if (OOJSValueToInt32(context, value, &iValue)) {
            if (iValue < 0)
                iValue = 0;
            if (7 < iValue)
                iValue = 7;
            [UNIVERSE setSystemDataForGalaxy:galaxy planet:system key:KEY_ECONOMY value:[NSNumber numberWithInt:iValue] fromManifest:manifest forLayer:OO_LAYER_OXP_DYNAMIC];
            return JS_UNDEFINED;
        }
        break;

    case kSystem_techLevel:
        if (OOJSValueToInt32(context, value, &iValue)) {
            if (iValue < 0)
                iValue = 0;
            if (15 < iValue)
                iValue = 15;
            [UNIVERSE setSystemDataForGalaxy:galaxy planet:system key:KEY_TECHLEVEL value:[NSNumber numberWithInt:iValue] fromManifest:manifest forLayer:OO_LAYER_OXP_DYNAMIC];
            return JS_UNDEFINED;
        }
        break;

    case kSystem_population:
        if (OOJSValueToInt32(context, value, &iValue)) {
            [UNIVERSE setSystemDataForGalaxy:galaxy planet:system key:KEY_POPULATION value:[NSNumber numberWithInt:iValue] fromManifest:manifest forLayer:OO_LAYER_OXP_DYNAMIC];
            return JS_UNDEFINED;
        }
        break;

    case kSystem_productivity:
        if (OOJSValueToInt32(context, value, &iValue)) {
            [UNIVERSE setSystemDataForGalaxy:galaxy planet:system key:KEY_PRODUCTIVITY value:[NSNumber numberWithInt:iValue] fromManifest:manifest forLayer:OO_LAYER_OXP_DYNAMIC];
            return JS_UNDEFINED;
        }
        break;

    default:
        OOJSReportBadPropertySelector(context, this, magic, sSystemProperties, OOJS_COUNT(sSystemProperties));
        return OOJSNativeFailure(context);
    }

    OOJSReportBadPropertyValue(context, this, magic, sSystemProperties, OOJS_COUNT(sSystemProperties), value);
    return OOJSNativeFailure(context);

    OOJS_NATIVE_EXIT
}

// *** Methods ***

// toString() : String
static JSValue SystemToString(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    PlayerEntity* player = OOPlayerForScripting();
    NSString* systemDesc = nil;

    systemDesc = [NSString stringWithFormat:@"[System %u:%u \"%@\"]", [player currentGalaxyID], [player currentSystemID], [[UNIVERSE currentSystemData] objectForKey:KEY_NAME]];
    OOJS_RETURN_OBJECT(systemDesc);

    OOJS_NATIVE_EXIT
}

// addPlanet(key : String) : Planet
static JSValue SystemAddPlanet(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    PlayerEntity* player = OOPlayerForScripting();
    NSString* key = nil;
    OOPlanetEntity* planet = nil;

    if (argc > 0)
        key = OOStringFromJSValue(context, OOJS_ARGV[0]);
    if (EXPECT_NOT(key == nil)) {
        OOJSReportBadArguments(context, @"System", @"addPlanet", MIN(argc, 1), OOJS_ARGV, nil, @"string (planet key)");
        return OOJSNativeFailure(context);
    }

    OOJS_BEGIN_FULL_NATIVE(context)
    planet = [player addPlanet:key];
    OOJS_END_FULL_NATIVE

    OOJS_RETURN_OBJECT(planet);

    OOJS_NATIVE_EXIT
}

// addMoon(key : String) : Planet
static JSValue SystemAddMoon(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    PlayerEntity* player = OOPlayerForScripting();
    NSString* key = nil;
    OOPlanetEntity* planet = nil;

    if (argc > 0)
        key = OOStringFromJSValue(context, OOJS_ARGV[0]);
    if (EXPECT_NOT(key == nil)) {
        OOJSReportBadArguments(context, @"System", @"addMoon", MIN(argc, 1), OOJS_ARGV, nil, @"string (planet key)");
        return OOJSNativeFailure(context);
    }

    OOJS_BEGIN_FULL_NATIVE(context)
    planet = [player addMoon:key];
    OOJS_END_FULL_NATIVE

    OOJS_RETURN_OBJECT(planet);

    OOJS_NATIVE_EXIT
}

// sendAllShipsAway()
static JSValue SystemSendAllShipsAway(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    PlayerEntity* player = OOPlayerForScripting();

    [player sendAllShipsAway];
    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}

// countShipsWithPrimaryRole(role : String [, relativeTo : Entity [, range : Number]]) : Number
static JSValue SystemCountShipsWithPrimaryRole(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    NSString* role = nil;
    Entity* relativeTo = nil;
    double range = -1;
    unsigned result;

    if (argc > 0)
        role = OOStringFromJSValue(context, OOJS_ARGV[0]);
    if (EXPECT_NOT(role == nil)) {
        OOJSReportBadArguments(context, @"System", @"countShipsWithPrimaryRole", MIN(argc, 1), OOJS_ARGV, nil, @"string (role)");
        return OOJSNativeFailure(context);
    }

    // Get optional arguments
    argc -= 1;
    JSValueConst* argv = OOJS_ARGV + 1;
    if (EXPECT_NOT(!GetRelativeToAndRange(context, @"countShipsWithPrimaryRole", &argc, &argv, &relativeTo, &range)))
        return OOJSNativeFailure(context);

    OOJS_BEGIN_FULL_NATIVE(context)
    result = [UNIVERSE countShipsWithPrimaryRole:role inRange:range ofEntity:relativeTo];
    OOJS_END_FULL_NATIVE

    OOJS_RETURN_INT(result);

    OOJS_NATIVE_EXIT
}

// countShipsWithRole(role : String [, relativeTo : Entity [, range : Number]]) : Number
static JSValue SystemCountShipsWithRole(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    NSString* role = nil;
    Entity* relativeTo = nil;
    double range = -1;
    unsigned result;

    if (argc > 0)
        role = OOStringFromJSValue(context, OOJS_ARGV[0]);
    if (EXPECT_NOT(role == nil)) {
        OOJSReportBadArguments(context, @"System", @"countShipsWithRole", MIN(argc, 1), OOJS_ARGV, nil, @"string (role)");
        return OOJSNativeFailure(context);
    }

    // Get optional arguments
    argc -= 1;
    JSValueConst* argv = OOJS_ARGV + 1;
    if (EXPECT_NOT(!GetRelativeToAndRange(context, @"countShipsWithRole", &argc, &argv, &relativeTo, &range)))
        return OOJSNativeFailure(context);

    OOJS_BEGIN_FULL_NATIVE(context)
    result = [UNIVERSE countShipsWithRole:role inRange:range ofEntity:relativeTo];
    OOJS_END_FULL_NATIVE

    OOJS_RETURN_INT(result);

    OOJS_NATIVE_EXIT
}

// shipsWithPrimaryRole(role : String [, relativeTo : Entity [, range : Number]]) : Array (Entity)
static JSValue SystemShipsWithPrimaryRole(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    NSString* role = nil;
    Entity* relativeTo = nil;
    double range = -1;
    NSArray* result = nil;

    if (argc > 0)
        role = OOStringFromJSValue(context, OOJS_ARGV[0]);
    if (EXPECT_NOT(role == nil)) {
        OOJSReportBadArguments(context, @"System", @"countShipsWithRole", MIN(argc, 1), OOJS_ARGV, nil, @"string (role)");
        return OOJSNativeFailure(context);
    }

    // Get optional arguments
    argc -= 1;
    JSValueConst* argv = OOJS_ARGV + 1;
    if (EXPECT_NOT(!GetRelativeToAndRange(context, @"shipsWithPrimaryRole", &argc, &argv, &relativeTo, &range)))
        return OOJSNativeFailure(context);

    // Search for entities
    OOJS_BEGIN_FULL_NATIVE(context)
    result = FindShips(HasPrimaryRolePredicate, role, relativeTo, range);
    OOJS_END_FULL_NATIVE

    OOJS_RETURN_OBJECT(result);

    OOJS_NATIVE_EXIT
}

// shipsWithRole(role : String [, relativeTo : Entity [, range : Number]]) : Array (Entity)
static JSValue SystemShipsWithRole(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    NSString* role = nil;
    Entity* relativeTo = nil;
    double range = -1;
    NSArray* result = nil;

    if (argc > 0)
        role = OOStringFromJSValue(context, OOJS_ARGV[0]);
    if (EXPECT_NOT(role == nil)) {
        OOJSReportBadArguments(context, @"System", @"shipsWithRole", MIN(argc, 1), OOJS_ARGV, nil, @"string (role)");
        return OOJSNativeFailure(context);
    }

    // Get optional arguments
    argc -= 1;
    JSValueConst* subargv = OOJS_ARGV + 1;
    if (EXPECT_NOT(!GetRelativeToAndRange(context, @"shipsWithRole", &argc, &subargv, &relativeTo, &range)))
        return OOJSNativeFailure(context);

    // Search for entities
    OOJS_BEGIN_FULL_NATIVE(context)
    result = FindShips(HasRolePredicate, role, relativeTo, range);
    OOJS_END_FULL_NATIVE

    OOJS_RETURN_OBJECT(result);

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
        OOJSReportBadArguments(context, @"System", @"countEntitiesWithScanClass", MIN(argc, 1), OOJS_ARGV, nil, @"string (scan class)");
        return OOJSNativeFailure(context);
    }

    // Get optional arguments
    argc -= 1;
    JSValueConst* argv = OOJS_ARGV + 1;
    if (EXPECT_NOT(!GetRelativeToAndRange(context, @"countEntitiesWithScanClass", &argc, &argv, &relativeTo, &range)))
        return OOJSNativeFailure(context);

    OOJS_BEGIN_FULL_NATIVE(context)
    result = [UNIVERSE countShipsWithScanClass:scanClass inRange:range ofEntity:relativeTo];
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
    NSArray* result = nil;

    if (argc > 0)
        scanClass = OOScanClassFromJSValue(context, OOJS_ARGV[0]);
    if (scanClass == CLASS_NOT_SET) {
        OOJSReportBadArguments(context, @"System", @"countEntitiesWithScanClass", MIN(argc, 1), OOJS_ARGV, nil, @"string (scan class)");
        return OOJSNativeFailure(context);
    }

    // Get optional arguments
    argc -= 1;
    JSValueConst* argv = OOJS_ARGV + 1;
    if (EXPECT_NOT(!GetRelativeToAndRange(context, @"entitiesWithScanClass", &argc, &argv, &relativeTo, &range)))
        return OOJSNativeFailure(context);

    // Search for entities
    OOJS_BEGIN_FULL_NATIVE(context)
    result = FindJSVisibleEntities(HasScanClassPredicate, [NSNumber numberWithInt:scanClass], relativeTo, range);
    OOJS_END_FULL_NATIVE

    OOJS_RETURN_OBJECT(result);

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
    NSArray* result = nil;

    // Get this and predicate arguments
    if (argc < 2 || !OOJSValueIsFunction(context, OOJS_ARGV[1])) {
        OOJSReportBadArguments(context, @"System", @"filteredEntities", argc, OOJS_ARGV, nil, @"this, predicate function, and optional reference entity and range");
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
            OOJSReportBadArguments(context, @"System", @"filteredEntities", argc, OOJS_ARGV, nil, @"this, predicate function, and optional reference entity and range");
            return OOJSNativeFailure(context);
        }
    }
    predicate = OOJS_ARGV[1];

    // Get optional arguments
    argc -= 2;
    JSValueConst* argv = OOJS_ARGV + 2;
    if (EXPECT_NOT(!GetRelativeToAndRange(context, @"filteredEntities", &argc, &argv, &relativeTo, &range))) {
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

    OOJS_RETURN_OBJECT(result);

    OOJS_NATIVE_EXIT
}

// locationFromCode(populator_named_region : String)
static JSValue SystemLocationFromCode(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    NSString* code = nil;
    if (argc > 0) {
        code = OOStringFromJSValue(context, OOJS_ARGV[0]);
    }
    if (EXPECT_NOT(code == nil)) {
        OOJSReportBadArguments(context, @"System", @"locationFromCode", argc, OOJS_ARGV, nil, @"location code");
        return OOJSNativeFailure(context);
    }
    OOSunEntity* sun = [UNIVERSE sun];
    OOPlanetEntity* planet = [UNIVERSE planet];
    HPVector position = kZeroHPVector;
    if (sun == nil || planet == nil) {
        position = [UNIVERSE locationByCode:@"WITCHPOINT" withSun:nil andPlanet:nil];
    } else {
        position = [UNIVERSE locationByCode:code withSun:sun andPlanet:planet];
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
    OOStandardsDeprecated(@"system.legacy_addShips() is deprecated");
    OOJS_NATIVE_ENTER(context)

    NSString* role = nil;
    int32_t count;

    if (argc > 0)
        role = OOStringFromJSValue(context, OOJS_ARGV[0]);
    if (EXPECT_NOT(role == nil || !OOJSValueToInt32(context, OOJS_ARGV[1], &count) || argc < 2 || count < 1 || 64 < count)) {
        OOJSReportBadArguments(context, @"System", @"legacy_addShips", argc, OOJS_ARGV, nil, @"role and positive count no greater than 64");
        return OOJSNativeFailure(context);
    }

    OOJS_BEGIN_FULL_NATIVE(context)
    while (count--)
        [UNIVERSE witchspaceShipWithPrimaryRole:role];
    OOJS_END_FULL_NATIVE

    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}

// legacy_addSystemShips(role : String, count : Number, location : Number)
static JSValue SystemLegacyAddSystemShips(OOJS_NATIVE_ARGS)
{
    OOStandardsDeprecated(@"system.legacy_addSystemShips() is deprecated");
    OOJS_NATIVE_ENTER(context)

    double position;
    NSString* role = nil;
    int32_t count;

    if (argc > 0)
        role = OOStringFromJSValue(context, OOJS_ARGV[0]);
    if (EXPECT_NOT(role == nil || !OOJSValueToInt32(context, OOJS_ARGV[1], &count) || count < 1 || 64 < count || argc < 3 || JS_ToFloat64(context, &position, OOJS_ARGV[2]) != 0)) {
        OOJSReportBadArguments(context, @"System", @"legacy_addSystemShips", argc, OOJS_ARGV, nil, @"role, positive count no greater than 64, and position along route");
        return OOJSNativeFailure(context);
    }

    OOJS_BEGIN_FULL_NATIVE(context)
    while (count--)
        [UNIVERSE addShipWithRole:role nearRouteOneAt:position];
    OOJS_END_FULL_NATIVE

    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}

// legacy_addShipsAt(role : String, count : Number, coordScheme : String, coords : vectorExpression)
static JSValue SystemLegacyAddShipsAt(OOJS_NATIVE_ARGS)
{
    OOStandardsDeprecated(@"system.legacy_addShipsAt() is deprecated");
    OOJS_NATIVE_ENTER(context)

    PlayerEntity* player = OOPlayerForScripting();
    HPVector where;
    NSString* role = nil;
    int32_t count;
    NSString* coordScheme = nil;
    NSString* arg = nil;

    if (argc > 0)
        role = OOStringFromJSValue(context, OOJS_ARGV[0]);
    coordScheme = OOStringFromJSValue(context, OOJS_ARGV[2]);
    if (EXPECT_NOT(role == nil || !OOJSValueToInt32(context, OOJS_ARGV[1], &count) || count < 1 || 64 < count || coordScheme == nil || argc < 4 || !VectorFromArgumentListNoError(context, argc - 3, OOJS_ARGV + 3, &where, NULL))) {
        OOJSReportBadArguments(context, @"System", @"legacy_addShipsAt", argc, OOJS_ARGV, nil, @"role, positive count no greater than 64, coordinate scheme and coordinates");
        return OOJSNativeFailure(context);
    }

    OOJS_BEGIN_FULL_NATIVE(context)
    arg = [NSString stringWithFormat:@"%@ %d %@ %f %f %f", role, count, coordScheme, where.x, where.y, where.z];
    [player addShipsAt:arg];
    OOJS_END_FULL_NATIVE

    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}

// legacy_addShipsAtPrecisely(role : String, count : Number, coordScheme : String, coords : vectorExpression)
static JSValue SystemLegacyAddShipsAtPrecisely(OOJS_NATIVE_ARGS)
{
    OOStandardsDeprecated(@"system.legacy_addShipsAtPrecisely() is deprecated");
    OOJS_NATIVE_ENTER(context)

    PlayerEntity* player = OOPlayerForScripting();
    HPVector where;
    NSString* role = nil;
    int32_t count;
    NSString* coordScheme = nil;
    NSString* arg = nil;

    if (argc > 0)
        role = OOStringFromJSValue(context, OOJS_ARGV[0]);
    coordScheme = OOStringFromJSValue(context, OOJS_ARGV[2]);
    if (EXPECT_NOT(role == nil || !OOJSValueToInt32(context, OOJS_ARGV[1], &count) || count < 1 || 64 < count || coordScheme == nil || argc < 4 || !VectorFromArgumentListNoError(context, argc - 3, OOJS_ARGV + 3, &where, NULL))) {
        OOJSReportBadArguments(context, @"System", @"legacy_addShipsAtPrecisely", argc, OOJS_ARGV, nil, @"role, positive count no greater than 64, coordinate scheme and coordinates");
        return OOJSNativeFailure(context);
    }

    OOJS_BEGIN_FULL_NATIVE(context)
    arg = [NSString stringWithFormat:@"%@ %d %@ %f %f %f", role, count, coordScheme, where.x, where.y, where.z];
    [player addShipsAtPrecisely:arg];
    OOJS_END_FULL_NATIVE

    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}

// legacy_addShipsWithinRadius(role : String, count : Number, coordScheme : String, coords : vectorExpression, radius : Number)
static JSValue SystemLegacyAddShipsWithinRadius(OOJS_NATIVE_ARGS)
{
    OOStandardsDeprecated(@"system.legacy_addShipsWithinRadius() is deprecated");
    OOJS_NATIVE_ENTER(context)

    PlayerEntity* player = OOPlayerForScripting();
    HPVector where;
    double radius;
    NSString* role = nil;
    int32_t count;
    NSString* coordScheme = nil;
    NSString* arg = nil;
    int consumed = 0;

    if (argc > 0)
        role = OOStringFromJSValue(context, OOJS_ARGV[0]);
    if (argc > 2)
        coordScheme = OOStringFromJSValue(context, OOJS_ARGV[2]);
    if (EXPECT_NOT(role == nil || !OOJSValueToInt32(context, OOJS_ARGV[1], &count) || count < 1 || 64 < count || coordScheme == nil || argc < 5 || !VectorFromArgumentListNoError(context, argc - 3, OOJS_ARGV + 3, &where, &consumed) || JS_ToFloat64(context, &radius, OOJS_ARGV[3 + consumed]) != 0)) {
        OOJSReportBadArguments(context, @"System", @"legacy_addShipWithinRadius", argc, OOJS_ARGV, nil, @"role, positive count no greater than 64, coordinate scheme, coordinates and radius");
        return OOJSNativeFailure(context);
    }

    OOJS_BEGIN_FULL_NATIVE(context)
    arg = [NSString stringWithFormat:@"%@ %d %@ %f %f %f %f", role, count, coordScheme, where.x, where.y, where.z, radius];
    [player addShipsWithinRadius:arg];
    OOJS_END_FULL_NATIVE

    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}

// legacy_spawnShip(key : string)
static JSValue SystemLegacySpawnShip(OOJS_NATIVE_ARGS)
{
    OOStandardsDeprecated(@"system.legacy_spawnShip() is deprecated");
    OOJS_NATIVE_ENTER(context)

    NSString* key = nil;
    OOPlayerForScripting(); // For backwards-compatibility

    if (argc > 0)
        key = OOStringFromJSValue(context, OOJS_ARGV[0]);
    if (key == nil) {
        OOJSReportBadArguments(context, @"System", @"legacy_spawnShip", MIN(argc, 1), OOJS_ARGV, nil, @"string (ship key)");
        return OOJSNativeFailure(context);
    }

    OOJS_BEGIN_FULL_NATIVE(context)
    [UNIVERSE spawnShip:key];
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
        OOJSReportBadArguments(context, @"System", @"systemNameForID", MIN(argc, 1), OOJS_ARGV, nil, @"system ID");
        return OOJSNativeFailure(context);
    }

    if (systemID == -1)
        OOJS_RETURN_OBJECT(DESC(@"interstellar-space"));
    else
        OOJS_RETURN_OBJECT([UNIVERSE getSystemName:systemID]);

    OOJS_NATIVE_EXIT
}

// systemIDForName(name : String) : Number
static JSValue SystemStaticSystemIDForName(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    NSString* name = nil;
    unsigned result;

    if (argc > 0)
        name = OOStringFromJSValue(context, OOJS_ARGV[0]);
    if (name == nil) {
        OOJSReportBadArguments(context, @"System", @"systemIDForName", MIN(argc, 1), OOJS_ARGV, nil, @"string");
        return OOJSNativeFailure(context);
    }

    OOJS_BEGIN_FULL_NATIVE(context)

    result = [UNIVERSE findSystemFromName:name];

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
        OOJSReportBadArguments(context, @"System", @"infoForSystem", argc, OOJS_ARGV, nil, @"galaxy ID and system ID");
        return OOJSNativeFailure(context);
    }

    if (galaxyID < 0 || galaxyID > kOOMaximumGalaxyID) {
        OOJSReportBadArguments(context, @"System", @"infoForSystem", 1, OOJS_ARGV, @"Invalid galaxy ID", [NSString stringWithFormat:@"number in the range 0 to %u", kOOMaximumGalaxyID]);
        return OOJSNativeFailure(context);
    }

    if (systemID < kOOMinimumSystemID || systemID > kOOMaximumSystemID) {
        OOJSReportBadArguments(context, @"System", @"infoForSystem", 1, OOJS_ARGV + 1, @"Invalid system ID", [NSString stringWithFormat:@"number in the range %i to %i", kOOMinimumSystemID, kOOMaximumSystemID]);
        return OOJSNativeFailure(context);
    }

    OOJS_RETURN(GetJSSystemInfoForSystem(context, galaxyID, systemID));

    OOJS_NATIVE_EXIT
}

static JSValue SystemAddVisualEffect(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    NSString* key = nil;
    HPVector where;

    int consumed = 0;

    if (argc > 0)
        key = OOStringFromJSValue(context, OOJS_ARGV[0]);
    if (key == nil) {
        OOJSReportBadArguments(context, @"System", @"addVisualEffect", MIN(argc, 1), &OOJS_ARGV[0], nil, @"string (key)");
        return OOJSNativeFailure(context);
    }

    if (!VectorFromArgumentListNoError(context, argc - 1, OOJS_ARGV + 1, &where, &consumed)) {
        OOJSReportBadArguments(context, @"System", @"addVisualEffect", MIN(argc - 1, 1), &OOJS_ARGV[1], nil, @"vector");
        return OOJSNativeFailure(context);
    }

    OOVisualEffectEntity* result = nil;

    OOJS_BEGIN_FULL_NATIVE(context)

    result = [UNIVERSE addVisualEffectAt:where withKey:key];

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

    NSString* key;
    NSMutableDictionary* settings;
    JSValue params = JS_UNDEFINED;

    if (argc < 1) {
        OOJSReportBadArguments(context, @"System", @"setPopulator", MIN(argc, 0), &OOJS_ARGV[0], nil, @"string (key), object (settings)");
        return OOJSNativeFailure(context);
    }
    key = OOStringFromJSValue(context, OOJS_ARGV[0]);
    if (key == nil) {
        OOJSReportBadArguments(context, @"System", @"setPopulator", MIN(argc, 0), &OOJS_ARGV[0], nil, @"key, settings");
        return OOJSNativeFailure(context);
    }
    if (argc < 2 || JS_IsNull(OOJS_ARGV[1])) {
        // clearing
        [UNIVERSE setPopulatorSetting:key to:nil];
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
            OOJSReportBadArguments(context, @"System", @"setPopulator", MIN(argc, 1), OOJS_ARGV, NULL, @"key, settings");
            return OOJSNativeFailure(context);
        }
        JSValue callback = GetParam(context, params, "callback");
        if (JS_IsUndefined(callback)) {
            JS_FreeValue(context, params);
            OOJSReportBadArguments(context, @"System", @"setPopulator", MIN(argc, 1), OOJS_ARGV, NULL, @"settings must have a 'callback' property.");
            return OOJSNativeFailure(context);
        }

        OOJSPopulatorDefinition* populator = [[OOJSPopulatorDefinition alloc] init];
        [populator setCallback:callback]; // Takes its own reference.
        JS_FreeValue(context, callback);

        // (The SpiderMonkey version converted argv[1] directly; params is the same object for any object argument.)
        settings = OOJSNativeObjectFromJSObject(context, params);
        [settings setObject:populator forKey:@"callbackObj"];

        JSValue coords = GetParam(context, params, "coordinates");
        if (!JS_IsUndefined(coords)) {
            Vector coordinates = kZeroVector;
            if (JSValueToVector(context, coords, &coordinates)) {
                // convert vector in NS-storable form
                [settings setObject:[NSArray arrayWithObjects:[NSNumber numberWithFloat:coordinates.x], [NSNumber numberWithFloat:coordinates.y], [NSNumber numberWithFloat:coordinates.z], nil] forKey:@"coordinates"];
            }
        }
        JS_FreeValue(context, coords);
        JS_FreeValue(context, params);

        [populator release];

        // A failed vector conversion is ignored, as before, but QuickJS natives must not return normally with an exception pending.
        if (EXPECT_NOT(JS_HasException(context)))
            return JS_EXCEPTION;

        [UNIVERSE setPopulatorSetting:key to:settings];
    }

    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}

static JSValue SystemSetWaypoint(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    NSString* key;
    NSMutableDictionary* settings;
    HPVector position;
    Quaternion orientation;

    if (argc < 1) {
        OOJSReportBadArguments(context, @"System", @"setWaypoint", MIN(argc, 0), &OOJS_ARGV[0], nil, @"key, position, orientation, definition");
        return OOJSNativeFailure(context);
    }
    key = OOStringFromJSValue(context, OOJS_ARGV[0]);
    if (key == nil) {
        OOJSReportBadArguments(context, @"System", @"setWaypoint", MIN(argc, 0), &OOJS_ARGV[0], nil, @"key, position, orientation, definition");
        return OOJSNativeFailure(context);
    }
    if (argc < 4 || JS_IsNull(OOJS_ARGV[3])) {
        // clearing
        [UNIVERSE defineWaypoint:nil forKey:key];
    } else {
        // adding
        if (!JSValueToHPVector(context, OOJS_ARGV[1], &position)) {
            OOJSReportBadArguments(context, @"System", @"setWaypoint", MIN(argc, 2), OOJS_ARGV, NULL, @"key, position, orientation, definition");
            return OOJSNativeFailure(context);
        }
        if (!JSValueToQuaternion(context, OOJS_ARGV[2], &orientation)) {
            OOJSReportBadArguments(context, @"System", @"setWaypoint", MIN(argc, 3), OOJS_ARGV, NULL, @"key, position, orientation, definition");
            return OOJSNativeFailure(context);
        }
        if (!JS_IsObject(OOJS_ARGV[3]) || JS_IsNull(OOJS_ARGV[3])) {
            OOJSReportBadArguments(context, @"System", @"setWaypoint", MIN(argc, 4), OOJS_ARGV, NULL, @"key, position, orientation, definition");
            return OOJSNativeFailure(context);
        }

        settings = [[OOJSNativeObjectFromJSObject(context, OOJS_ARGV[3]) mutableCopy] autorelease];
        [settings setObject:[NSArray arrayWithObjects:[NSNumber numberWithDouble:position.x], [NSNumber numberWithDouble:position.y], [NSNumber numberWithDouble:position.z], nil] forKey:@"position"];
        [settings setObject:[NSArray arrayWithObjects:[NSNumber numberWithDouble:orientation.w], [NSNumber numberWithDouble:orientation.x], [NSNumber numberWithDouble:orientation.y], [NSNumber numberWithDouble:orientation.z], nil] forKey:@"orientation"];

        [UNIVERSE defineWaypoint:settings forKey:key];
    }

    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}

// *** Helper functions ***

// Shared implementation of addShips() and addGroup().
static JSValue SystemAddShipsOrGroup(JSContext* context, int argc, JSValueConst* argv, BOOL isGroup)
{
    OOJS_NATIVE_ENTER(context)

    NSString* role = nil;
    int32_t count = 0;
    int consumed = 0;
    HPVector where;
    double radius = NSNotFound; // a negative value means
    id result = nil;

    NSString* func = isGroup ? @"addGroup" : @"addShips";

    if (argc > 0)
        role = OOStringFromJSValue(context, argv[0]);
    if (role == nil) {
        OOJSReportBadArguments(context, @"System", func, MIN(argc, 1), &argv[0], nil, @"string (role)");
        return JS_EXCEPTION;
    }
    if (argc < 2 || !OOJSValueToInt32(context, argv[1], &count) || count < 1 || 64 < count) {
        OOJSReportBadArguments(context, @"System", func, MIN(argc - 1, 1), &argv[1], nil, @"number (positive count no greater than 64)");
        return JS_EXCEPTION;
    }

    if (argc < 3) {
        where = [UNIVERSE getWitchspaceExitPosition];
        radius = SCANNER_MAX_RANGE;
    } else {
        if (!VectorFromArgumentListNoError(context, argc - 2, argv + 2, &where, &consumed)) {
            OOJSReportBadArguments(context, @"System", func, MIN(argc - 2, 1), &argv[2], nil, @"vector");
            return JS_EXCEPTION;
        }

        if (argc > 2 + consumed) {
            if (JS_ToFloat64(context, &radius, argv[2 + consumed]) < 0) {
                OOJSReportBadArguments(context, @"System", func, MIN(argc - 2 - consumed, 1), &argv[2 + consumed], nil, @"number (radius)");
                return JS_EXCEPTION;
            }
        }
    }

    OOJS_BEGIN_FULL_NATIVE(context)
    // Note: the use of witchspace-in effects (as in legacy_addShips) depends on proximity to the witchpoint.
    result = [UNIVERSE addShipsAt:where withRole:role quantity:count withinRadius:radius asGroup:isGroup];

    if (isGroup) {
        NSArray* array = result;
        if ([array count] > 0)
            result = [(ShipEntity*)[array objectAtIndex:0] group];
        else
            result = nil;
    }
    OOJS_END_FULL_NATIVE

    OOJS_RETURN_OBJECT(result);

    OOJS_NATIVE_EXIT
}

static JSValue SystemAddShipsOrGroupToRoute(JSContext* context, int argc, JSValueConst* argv, BOOL isGroup)
{
    OOJS_NATIVE_ENTER(context)

    NSString* role = nil;
    NSString* route = @"st"; // default route witchpoint -> station. ("st" itself is not selectable by script)
    static NSSet* validRoutes = nil;
    int32_t count = 0;
    double where = NSNotFound; // a negative value means random positioning!
    id result = nil;

    NSString* func = isGroup ? @"addGroup" : @"addShips";

    if (argc > 0)
        role = OOStringFromJSValue(context, argv[0]);
    if (role == nil) {
        OOJSReportBadArguments(context, @"System", func, MIN(argc, 1), &argv[0], nil, @"string (role)");
        return JS_EXCEPTION;
    }
    if (argc < 2 || !OOJSValueToInt32(context, argv[1], &count) || count < 1 || 64 < count) {
        OOJSReportBadArguments(context, @"System", func, MIN(argc - 1, 1), &argv[1], nil, @"number (positive count no greater than 64)");
        return JS_EXCEPTION;
    }

    if (argc > 2) {
        if (JS_ToFloat64(context, &where, argv[2]) != 0 || !isfinite(where) || where < 0.0f || where > 1.0f) {
            OOJSReportBadArguments(context, @"System", func, MIN(argc - 2, 1), &argv[2], nil, @"number (position along route)");
            return JS_EXCEPTION;
        }

        if (argc > 3) {
            route = [OOStringFromJSValue(context, argv[3]) lowercaseString];

            if (validRoutes == nil) {
                validRoutes = [[NSSet alloc] initWithObjects:@"wp", @"pw", @"ws", @"sw", @"sp", @"ps", nil];
            }

            if (route == nil || ![validRoutes containsObject:route]) {
                OOJSReportBadArguments(context, @"System", func, MIN(argc - 3, 1), &argv[3], nil, @"string (route specifier)");
                return JS_EXCEPTION;
            }
        }
    }

    OOJS_BEGIN_FULL_NATIVE(context)
    // Note: the use of witchspace-in effects (as in legacy_addShips) depends on proximity to the witchpoint.
    result = [UNIVERSE addShipsToRoute:route withRole:role quantity:count routeFraction:where asGroup:isGroup];

    if (isGroup) {
        NSArray* array = result;
        if ([array count] > 0)
            result = [(ShipEntity*)[array objectAtIndex:0] group];
        else
            result = nil;
    }
    OOJS_END_FULL_NATIVE

    OOJS_RETURN_OBJECT(result);

    OOJS_NATIVE_EXIT
}

static BOOL GetRelativeToAndRange(JSContext* context, NSString* methodName, int* ioArgc, JSValueConst** ioArgv, Entity** outRelativeTo, double* outRange)
{
    OOJS_PROFILE_ENTER

    // No NULL arguments accepted.
    assert(ioArgc && ioArgv && outRelativeTo && outRange);

    // Get optional argument relativeTo : Entity
    if (*ioArgc != 0) {
        if (EXPECT_NOT(JS_IsNull(**ioArgv) || !JSValueToEntity(context, **ioArgv, outRelativeTo))) {
            OOJSReportBadArguments(context, @"System", methodName, 1, *ioArgv, nil, @"entity");
            return NO;
        }
        (*ioArgv)++;
        (*ioArgc)--;
    }

    // Get optional argument range : Number
    if (*ioArgc != 0) {
        if (EXPECT_NOT(JS_ToFloat64(context, outRange, **ioArgv) != 0)) {
            OOJSReportBadArguments(context, @"System", methodName, 1, *ioArgv, nil, @"number");
            return NO;
        }
        (*ioArgv)++;
        (*ioArgc)--;
    }

    return YES;

    OOJS_PROFILE_EXIT
}

static NSArray* FindJSVisibleEntities(EntityFilterPredicate predicate, void* parameter, Entity* relativeTo, double range)
{
    OOJS_PROFILE_ENTER

    NSMutableArray* result = nil;
    BinaryOperationPredicateParameter param = {
        JSEntityIsJavaScriptSearchablePredicate, NULL,
        predicate, parameter
    };

    result = [UNIVERSE findEntitiesMatchingPredicate:ANDPredicate
                                           parameter:&param
                                             inRange:range
                                            ofEntity:relativeTo];

    if (result != nil && relativeTo != nil && ![relativeTo isPlayer]) {
        [result sortUsingFunction:CompareEntitiesByDistance context:relativeTo];
    }
    if (result == nil)
        return [NSArray array];
    return result;

    OOJS_PROFILE_EXIT
}

static NSArray* FindShips(EntityFilterPredicate predicate, void* parameter, Entity* relativeTo, double range)
{
    OOJS_PROFILE_ENTER

    BinaryOperationPredicateParameter param = {
        IsShipPredicate, NULL,
        predicate, parameter
    };
    return FindJSVisibleEntities(ANDPredicate, &param, relativeTo, range);

    OOJS_PROFILE_EXIT
}

static NSComparisonResult CompareEntitiesByDistance(id a, id b, void* relativeTo)
{
    OOJS_PROFILE_ENTER

    Entity *ea = a,
           *eb = b,
           *r = (id)relativeTo;
    float d1, d2;

    d1 = HPdistance2(ea->position, r->position);
    d2 = HPdistance2(eb->position, r->position);

    if (d1 < d2)
        return NSOrderedAscending;
    else if (d1 > d2)
        return NSOrderedDescending;
    else
        return NSOrderedSame;

    OOJS_PROFILE_EXIT
}
