/*

OOJSPlayerShip.m (QuickJS-ng)

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

#import "EntityOOJavaScriptExtensions.h"
#import "HeadUpDisplay.h"
#import "OOCollectionExtractors.h"
#import "OOJSEntity.h"
#import "OOJSPlayer.h"
#import "OOJSQuaternion.h"
#import "OOJSShip.h"
#import "OOJSVector.h"
#import "OOJavaScriptEngine.h"
#import "OOSystemDescriptionManager.h"
#import "PlayerEntityContracts.h"
#import "PlayerEntityControls.h"
#import "PlayerEntityLegacyScriptEngine.h"
#import "PlayerEntityScriptMethods.h"
#import "PlayerEntitySound.h"
#import "StationEntity.h"

#import "OOConstToJSString.h"
#import "OOConstToString.h"
#import "OOEquipmentType.h"
#import "OOFunctionAttributes.h"
#import "OOJSEquipmentInfo.h"

static JSClassID sPlayerShipClassID;

static JSClassDef sPlayerShipClass = {
    .class_name = "PlayerShip",
    .finalizer = OOJSObjectWrapperFinalize,
};

static JSValue PlayerShipGetProperty(OOJS_GETTER_ARGS);
static JSValue PlayerShipSetProperty(OOJS_SETTER_ARGS);

static JSValue PlayerShipLaunch(OOJS_NATIVE_ARGS);
static JSValue PlayerShipRemoveAllCargo(OOJS_NATIVE_ARGS);
static JSValue PlayerShipUseSpecialCargo(OOJS_NATIVE_ARGS);
static JSValue PlayerShipEngageAutopilotToStation(OOJS_NATIVE_ARGS);
static JSValue PlayerShipDisengageAutopilot(OOJS_NATIVE_ARGS);
static JSValue PlayerShipRequestDockingClearance(OOJS_NATIVE_ARGS);
static JSValue PlayerShipCancelDockingRequest(OOJS_NATIVE_ARGS);
static JSValue PlayerShipAwardEquipmentToCurrentPylon(OOJS_NATIVE_ARGS);
static JSValue PlayerShipAddPassenger(OOJS_NATIVE_ARGS);
static JSValue PlayerShipRemovePassenger(OOJS_NATIVE_ARGS);
static JSValue PlayerShipAddParcel(OOJS_NATIVE_ARGS);
static JSValue PlayerShipRemoveParcel(OOJS_NATIVE_ARGS);
static JSValue PlayerShipAwardContract(OOJS_NATIVE_ARGS);
static JSValue PlayerShipRemoveContract(OOJS_NATIVE_ARGS);
static JSValue PlayerShipSetCustomView(OOJS_NATIVE_ARGS);
static JSValue PlayerShipSetPrimedEquipment(OOJS_NATIVE_ARGS);
static JSValue PlayerShipResetCustomView(OOJS_NATIVE_ARGS);
static JSValue PlayerShipResetScannerZoom(OOJS_NATIVE_ARGS);
static JSValue PlayerShipTakeInternalDamage(OOJS_NATIVE_ARGS);
static JSValue PlayerShipBeginHyperspaceCountdown(OOJS_NATIVE_ARGS);
static JSValue PlayerShipCancelHyperspaceCountdown(OOJS_NATIVE_ARGS);
static JSValue PlayerShipBeginGalacticHyperspaceCountdown(OOJS_NATIVE_ARGS);
static JSValue PlayerShipSetMultiFunctionDisplay(OOJS_NATIVE_ARGS);
static JSValue PlayerShipSetMultiFunctionText(OOJS_NATIVE_ARGS);
static JSValue PlayerShipHideHUDSelector(OOJS_NATIVE_ARGS);
static JSValue PlayerShipShowHUDSelector(OOJS_NATIVE_ARGS);
static JSValue PlayerShipSetCustomHUDDial(OOJS_NATIVE_ARGS);

static BOOL ValidateContracts(JSContext* context, int argc, JSValueConst* argv, BOOL isCargo, OOSystemID* start, OOSystemID* destination, double* eta, double* fee, double* premium, NSString* functionName, unsigned* risk);

enum {
    // Property IDs
    kPlayerShip_activeMissile, // index in 'missiles' array of current active missile
    kPlayerShip_aftShield, // aft shield charge level, nonnegative float, read/write
    kPlayerShip_aftShieldRechargeRate, // aft shield recharge rate, positive float, read-only
    kPlayerShip_chartHightlightMode, // what type of information is being shown on the chart
    kPlayerShip_compassMode, // compass mode, string, read/write
    kPlayerShip_compassTarget, // object targeted by the compass, entity, read/write
    kPlayerShip_compassType, // basic / advanced, string, read/write
    kPlayerShip_currentWeapon, // shortcut property to _aftWeapon, etc. overrides kShip generic version
    kPlayerShip_crosshairs, // custom plist file defining crosshairs
    kPlayerShip_cursorCoordinates, // cursor coordinates (unscaled), Vector3D, read only
    kPlayerShip_cursorCoordinatesInLY, // cursor coordinates (in LY), Vector3D, read only
    kPlayerShip_docked, // docked, boolean, read-only
    kPlayerShip_dockedStation, // docked station, entity, read-only
    kPlayerShip_fastEquipmentA, // fast equipment A, string, read/write
    kPlayerShip_fastEquipmentB, // fast equipment B, string, read/write
    kPlayerShip_forwardShield, // forward shield charge level, nonnegative float, read/write
    kPlayerShip_forwardShieldRechargeRate, // forward shield recharge rate, positive float, read-only
    kPlayerShip_fuelLeakRate, // fuel leak rate, float, read/write
    kPlayerShip_galacticHyperspaceBehaviour, // can be standard, all systems reachable or fixed coordinates, integer, read-only
    kPlayerShip_galacticHyperspaceFixedCoords, // used when fixed coords behaviour is selected, Vector3D, read/write
    kPlayerShip_galacticHyperspaceFixedCoordsInLY, // used when fixed coords behaviour is selected, Vector3D, read/write
    kPlayerShip_galaxyCoordinates, // galaxy coordinates (unscaled), Vector3D, read only
    kPlayerShip_galaxyCoordinatesInLY, // galaxy coordinates (in LY), Vector3D, read only
    kPlayerShip_hud, // hud name identifier, string, read/write
    kPlayerShip_hudAllowsBigGui, // hud big gui, string, read only
    kPlayerShip_hudHidden, // hud visibility, boolean, read/write
    kPlayerShip_injectorsEngaged, // injectors in use, boolean, read-only
    kPlayerShip_massLockable, // mass-lockability of player ship, read/write
    kPlayerShip_maxAftShield, // maximum aft shield charge level, positive float, read-only
    kPlayerShip_maxForwardShield, // maximum forward shield charge level, positive float, read-only
    kPlayerShip_messageGuiTextColor, // message gui standard text color, array, read/write
    kPlayerShip_messageGuiTextCommsColor, // message gui incoming comms text color, array, read/write
    kPlayerShip_multiFunctionDisplays, // mfd count, positive int, read-only
    kPlayerShip_multiFunctionDisplayList, // active mfd list, array, read-only
    kPlayerShip_missilesOnline, // bool (false for ident mode, true for missile mode)
    kPlayerShip_pitch, // pitch (overrules Ship)
    kPlayerShip_price, // idealised trade-in value decicredits, positive int, read-only
    kPlayerShip_primedEquipment, // currently primed equipment, string, read/write
    kPlayerShip_renovationCost, // int read-only current renovation cost
    kPlayerShip_reticleColorTarget, // Reticle color for normal targets, array, read/write
    kPlayerShip_reticleColorTargetSensitive, // Reticle color for targets picked up when sensitive mode is on, array, read/write
    kPlayerShip_reticleColorWormhole, // REticle color for wormholes, array, read/write
    kPlayerShip_renovationMultiplier, // float read-only multiplier for renovation costs
    kPlayerShip_reticleTargetSensitive, // target box changes color when primary target in crosshairs, boolean, read/write
    kPlayerShip_roll, // roll (overrules Ship)
    kPlayerShip_routeMode, // ANA mode
    kPlayerShip_scannerMinimalistic, // essentially scanner without gridlines
    kPlayerShip_scannerNonLinear, // non linear scanner setting, boolean, read/write
    kPlayerShip_scannerUltraZoom, // scanner zoom in powers of 2, boolean, read/write
    kPlayerShip_scoopOverride, // Scooping
    kPlayerShip_serviceLevel, // servicing level, positive int 75-100, read-only
    kPlayerShip_specialCargo, // special cargo, string, read-only
    kPlayerShip_targetSystem, // target system id, int, read-write
    kPlayerShip_nextSystem, // next hop system id, read-only
    kPlayerShip_infoSystem, // info (F7 screen) system id, int, read-write
    kPlayerShip_previousSystem, // previous system id, read-only
    kPlayerShip_torusEngaged, // torus in use, boolean, read-only
    kPlayerShip_viewDirection, // view direction identifier, string, read-only
    kPlayerShip_viewPositionAft, // view position offset, vector, read-only
    kPlayerShip_viewPositionForward, // view position offset, vector, read-only
    kPlayerShip_viewPositionPort, // view position offset, vector, read-only
    kPlayerShip_viewPositionStarboard, // view position offset, vector, read-only
    kPlayerShip_weaponsOnline, // weapons online status, boolean, read-only
    kPlayerShip_yaw, // yaw (overrules Ship)
};

static const JSCFunctionListEntry sPlayerShipProperties[] = {
    // JS name, getter, setter, ID
    OOJS_PROPERTY_RO("activeMissile", PlayerShipGetProperty, kPlayerShip_activeMissile),
    OOJS_PROPERTY_RW("aftShield", PlayerShipGetProperty, PlayerShipSetProperty, kPlayerShip_aftShield),
    OOJS_PROPERTY_RW("aftShieldRechargeRate", PlayerShipGetProperty, PlayerShipSetProperty, kPlayerShip_aftShieldRechargeRate),
    OOJS_PROPERTY_RW("chartHighlightMode", PlayerShipGetProperty, PlayerShipSetProperty, kPlayerShip_chartHightlightMode),
    OOJS_PROPERTY_RW("compassMode", PlayerShipGetProperty, PlayerShipSetProperty, kPlayerShip_compassMode),
    OOJS_PROPERTY_RW("compassTarget", PlayerShipGetProperty, PlayerShipSetProperty, kPlayerShip_compassTarget),
    OOJS_PROPERTY_RW("compassType", PlayerShipGetProperty, PlayerShipSetProperty, kPlayerShip_compassType),
    OOJS_PROPERTY_RW("currentWeapon", PlayerShipGetProperty, PlayerShipSetProperty, kPlayerShip_currentWeapon),
    OOJS_PROPERTY_RW("crosshairs", PlayerShipGetProperty, PlayerShipSetProperty, kPlayerShip_crosshairs),
    OOJS_PROPERTY_RO("cursorCoordinates", PlayerShipGetProperty, kPlayerShip_cursorCoordinates),
    OOJS_PROPERTY_RO("cursorCoordinatesInLY", PlayerShipGetProperty, kPlayerShip_cursorCoordinatesInLY),
    OOJS_PROPERTY_RO("docked", PlayerShipGetProperty, kPlayerShip_docked),
    OOJS_PROPERTY_RO("dockedStation", PlayerShipGetProperty, kPlayerShip_dockedStation),
    OOJS_PROPERTY_RW("fastEquipmentA", PlayerShipGetProperty, PlayerShipSetProperty, kPlayerShip_fastEquipmentA),
    OOJS_PROPERTY_RW("fastEquipmentB", PlayerShipGetProperty, PlayerShipSetProperty, kPlayerShip_fastEquipmentB),
    OOJS_PROPERTY_RW("forwardShield", PlayerShipGetProperty, PlayerShipSetProperty, kPlayerShip_forwardShield),
    OOJS_PROPERTY_RW("forwardShieldRechargeRate", PlayerShipGetProperty, PlayerShipSetProperty, kPlayerShip_forwardShieldRechargeRate),
    OOJS_PROPERTY_RW("fuelLeakRate", PlayerShipGetProperty, PlayerShipSetProperty, kPlayerShip_fuelLeakRate),
    OOJS_PROPERTY_RW("galacticHyperspaceBehaviour", PlayerShipGetProperty, PlayerShipSetProperty, kPlayerShip_galacticHyperspaceBehaviour),
    OOJS_PROPERTY_RW("galacticHyperspaceFixedCoords", PlayerShipGetProperty, PlayerShipSetProperty, kPlayerShip_galacticHyperspaceFixedCoords),
    OOJS_PROPERTY_RW("galacticHyperspaceFixedCoordsInLY", PlayerShipGetProperty, PlayerShipSetProperty, kPlayerShip_galacticHyperspaceFixedCoordsInLY),
    OOJS_PROPERTY_RO("galaxyCoordinates", PlayerShipGetProperty, kPlayerShip_galaxyCoordinates),
    OOJS_PROPERTY_RO("galaxyCoordinatesInLY", PlayerShipGetProperty, kPlayerShip_galaxyCoordinatesInLY),
    OOJS_PROPERTY_RW("hud", PlayerShipGetProperty, PlayerShipSetProperty, kPlayerShip_hud),
    OOJS_PROPERTY_RO("hudAllowsBigGui", PlayerShipGetProperty, kPlayerShip_hudAllowsBigGui),
    OOJS_PROPERTY_RW("hudHidden", PlayerShipGetProperty, PlayerShipSetProperty, kPlayerShip_hudHidden),
    OOJS_PROPERTY_RO("injectorsEngaged", PlayerShipGetProperty, kPlayerShip_injectorsEngaged),
    OOJS_PROPERTY_RW("massLockable", PlayerShipGetProperty, PlayerShipSetProperty, kPlayerShip_massLockable),
    // manifest defined in OOJSManifest.m
    OOJS_PROPERTY_RW("maxAftShield", PlayerShipGetProperty, PlayerShipSetProperty, kPlayerShip_maxAftShield),
    OOJS_PROPERTY_RW("maxForwardShield", PlayerShipGetProperty, PlayerShipSetProperty, kPlayerShip_maxForwardShield),
    OOJS_PROPERTY_RW("messageGuiTextColor", PlayerShipGetProperty, PlayerShipSetProperty, kPlayerShip_messageGuiTextColor),
    OOJS_PROPERTY_RW("messageGuiTextCommsColor", PlayerShipGetProperty, PlayerShipSetProperty, kPlayerShip_messageGuiTextCommsColor),
    OOJS_PROPERTY_RO("missilesOnline", PlayerShipGetProperty, kPlayerShip_missilesOnline),
    OOJS_PROPERTY_RO("multiFunctionDisplays", PlayerShipGetProperty, kPlayerShip_multiFunctionDisplays),
    OOJS_PROPERTY_RO("multiFunctionDisplayList", PlayerShipGetProperty, kPlayerShip_multiFunctionDisplayList),
    OOJS_PROPERTY_RO("price", PlayerShipGetProperty, kPlayerShip_price),
    OOJS_PROPERTY_RW("pitch", PlayerShipGetProperty, PlayerShipSetProperty, kPlayerShip_pitch),
    OOJS_PROPERTY_RW("primedEquipment", PlayerShipGetProperty, PlayerShipSetProperty, kPlayerShip_primedEquipment),
    OOJS_PROPERTY_RO("renovationCost", PlayerShipGetProperty, kPlayerShip_renovationCost),
    OOJS_PROPERTY_RW("reticleColorTarget", PlayerShipGetProperty, PlayerShipSetProperty, kPlayerShip_reticleColorTarget),
    OOJS_PROPERTY_RW("reticleColorTargetSensitive", PlayerShipGetProperty, PlayerShipSetProperty, kPlayerShip_reticleColorTargetSensitive),
    OOJS_PROPERTY_RW("reticleColorWormhole", PlayerShipGetProperty, PlayerShipSetProperty, kPlayerShip_reticleColorWormhole),
    OOJS_PROPERTY_RO("renovationMultiplier", PlayerShipGetProperty, kPlayerShip_renovationMultiplier),
    OOJS_PROPERTY_RW("reticleTargetSensitive", PlayerShipGetProperty, PlayerShipSetProperty, kPlayerShip_reticleTargetSensitive),
    OOJS_PROPERTY_RW("roll", PlayerShipGetProperty, PlayerShipSetProperty, kPlayerShip_roll),
    OOJS_PROPERTY_RO("routeMode", PlayerShipGetProperty, kPlayerShip_routeMode),
    OOJS_PROPERTY_RW("scannerMinimalistic", PlayerShipGetProperty, PlayerShipSetProperty, kPlayerShip_scannerMinimalistic),
    OOJS_PROPERTY_RW("scannerNonLinear", PlayerShipGetProperty, PlayerShipSetProperty, kPlayerShip_scannerNonLinear),
    OOJS_PROPERTY_RW("scannerUltraZoom", PlayerShipGetProperty, PlayerShipSetProperty, kPlayerShip_scannerUltraZoom),
    OOJS_PROPERTY_RW("scoopOverride", PlayerShipGetProperty, PlayerShipSetProperty, kPlayerShip_scoopOverride),
    OOJS_PROPERTY_RW("serviceLevel", PlayerShipGetProperty, PlayerShipSetProperty, kPlayerShip_serviceLevel),
    OOJS_PROPERTY_RO("specialCargo", PlayerShipGetProperty, kPlayerShip_specialCargo),
    OOJS_PROPERTY_RW("targetSystem", PlayerShipGetProperty, PlayerShipSetProperty, kPlayerShip_targetSystem),
    OOJS_PROPERTY_RO("nextSystem", PlayerShipGetProperty, kPlayerShip_nextSystem),
    OOJS_PROPERTY_RW("infoSystem", PlayerShipGetProperty, PlayerShipSetProperty, kPlayerShip_infoSystem),
    OOJS_PROPERTY_RO("previousSystem", PlayerShipGetProperty, kPlayerShip_previousSystem),
    OOJS_PROPERTY_RO("torusEngaged", PlayerShipGetProperty, kPlayerShip_torusEngaged),
    OOJS_PROPERTY_RO("viewDirection", PlayerShipGetProperty, kPlayerShip_viewDirection),
    OOJS_PROPERTY_RO("viewPositionAft", PlayerShipGetProperty, kPlayerShip_viewPositionAft),
    OOJS_PROPERTY_RO("viewPositionForward", PlayerShipGetProperty, kPlayerShip_viewPositionForward),
    OOJS_PROPERTY_RO("viewPositionPort", PlayerShipGetProperty, kPlayerShip_viewPositionPort),
    OOJS_PROPERTY_RO("viewPositionStarboard", PlayerShipGetProperty, kPlayerShip_viewPositionStarboard),
    OOJS_PROPERTY_RO("weaponsOnline", PlayerShipGetProperty, kPlayerShip_weaponsOnline),
    OOJS_PROPERTY_RW("yaw", PlayerShipGetProperty, PlayerShipSetProperty, kPlayerShip_yaw),
};

static const JSCFunctionListEntry sPlayerShipMethods[] = {
    // JS name, min args, function
    JS_CFUNC_DEF("addParcel", 0, PlayerShipAddParcel),
    JS_CFUNC_DEF("addPassenger", 0, PlayerShipAddPassenger),
    JS_CFUNC_DEF("awardContract", 0, PlayerShipAwardContract),
    JS_CFUNC_DEF("awardEquipmentToCurrentPylon", 1, PlayerShipAwardEquipmentToCurrentPylon),
    JS_CFUNC_DEF("beginHyperspaceCountdown", 0, PlayerShipBeginHyperspaceCountdown),
    JS_CFUNC_DEF("cancelDockingRequest", 1, PlayerShipCancelDockingRequest),
    JS_CFUNC_DEF("cancelHyperspaceCountdown", 0, PlayerShipCancelHyperspaceCountdown),
    JS_CFUNC_DEF("beginGalacticHyperspaceCountdown", 1, PlayerShipBeginGalacticHyperspaceCountdown),
    JS_CFUNC_DEF("disengageAutopilot", 0, PlayerShipDisengageAutopilot),
    JS_CFUNC_DEF("engageAutopilotToStation", 1, PlayerShipEngageAutopilotToStation),
    JS_CFUNC_DEF("hideHUDSelector", 1, PlayerShipHideHUDSelector),
    JS_CFUNC_DEF("launch", 0, PlayerShipLaunch),
    JS_CFUNC_DEF("removeAllCargo", 0, PlayerShipRemoveAllCargo),
    JS_CFUNC_DEF("removeContract", 2, PlayerShipRemoveContract),
    JS_CFUNC_DEF("removeParcel", 1, PlayerShipRemoveParcel),
    JS_CFUNC_DEF("removePassenger", 1, PlayerShipRemovePassenger),
    JS_CFUNC_DEF("requestDockingClearance", 1, PlayerShipRequestDockingClearance),
    JS_CFUNC_DEF("resetCustomView", 0, PlayerShipResetCustomView),
    JS_CFUNC_DEF("resetScannerZoom", 0, PlayerShipResetScannerZoom),
    JS_CFUNC_DEF("setCustomView", 2, PlayerShipSetCustomView),
    JS_CFUNC_DEF("setCustomHUDDial", 2, PlayerShipSetCustomHUDDial),
    JS_CFUNC_DEF("setMultiFunctionDisplay", 1, PlayerShipSetMultiFunctionDisplay),
    JS_CFUNC_DEF("setMultiFunctionText", 1, PlayerShipSetMultiFunctionText),
    JS_CFUNC_DEF("setPrimedEquipment", 1, PlayerShipSetPrimedEquipment),
    JS_CFUNC_DEF("showHUDSelector", 1, PlayerShipShowHUDSelector),
    JS_CFUNC_DEF("takeInternalDamage", 0, PlayerShipTakeInternalDamage),
    JS_CFUNC_DEF("useSpecialCargo", 1, PlayerShipUseSpecialCargo),
};

void InitOOJSPlayerShip(JSContext* context, JSValueConst global)
{
    OOJSRegisterClass(&sPlayerShipClassID, &sPlayerShipClass);

    JSValue shipPrototype = JS_GetClassProto(context, JSShipClassID());
    NSCAssert(JS_IsObject(shipPrototype), @"Ship must be initialized before PlayerShip.");
    OOJSInitClass(context, global, sPlayerShipClassID, shipPrototype, OOJSUnconstructableConstruct, 0,
        sPlayerShipProperties, OOJS_COUNT(sPlayerShipProperties), sPlayerShipMethods, OOJS_COUNT(sPlayerShipMethods), NULL, 0);
    JS_FreeValue(context, shipPrototype);

    OOJSRegisterObjectConverter(sPlayerShipClassID, OOJSBasicPrivateObjectConverter);
    OOJSRegisterSubclass(sPlayerShipClassID, JSShipClassID());

    PlayerEntity* player = [PlayerEntity sharedPlayer]; // NOTE: at time of writing, this creates the player entity. Don't use PLAYER here.

    // Create ship object as a property of the player object.
    JSValue playerObject = JS_GetPropertyStr(context, global, "player");
    NSCAssert(JS_IsObject(playerObject), @"Player must be initialized before PlayerShip.");

    JSValue shipObject = JS_NewObjectClass(context, (int)sPlayerShipClassID);
    JS_SetOpaque(shipObject, OOConsumeReference([player weakRetain]));
    // The player object's property and the player entity each own a reference.
    JS_DefinePropertyValueStr(context, playerObject, "ship", JS_DupValue(context, shipObject), OOJS_PROP_READONLY);
    [player setJSSelf:shipObject context:context];

    JS_FreeValue(context, shipObject);
    JS_FreeValue(context, playerObject);
    // Analyzer: object leaked. [Expected, object is retained by JS object.]
}

JSClassID JSPlayerShipClassID(void)
{
    return sPlayerShipClassID;
}

JSValue JSPlayerShipObject(void)
{
    JSContext* context = OOJSAcquireContext();
    JSValue playerObject = JSPlayerObject();
    JSValue result = JS_GetPropertyStr(context, playerObject, "ship");
    JS_FreeValue(context, playerObject);
    OOJSRelinquishContext(context);
    return result;
}

@implementation PlayerEntity (OOJavaScriptExtensions)

- (NSString*)oo_jsClassName
{
    return @"PlayerShip";
}

- (JSClassID)oo_jsClassID
{
    return sPlayerShipClassID;
}

- (void)setJSSelf:(JSValueConst)val context:(JSContext*)context
{
    // Drop any previous wrapper (and its reset observer).
    [self deleteJSSelf];

    // Released by -deleteJSSelf when the JavaScript engine resets.
    _jsSelf = JS_DupValue(context, val);

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(deleteJSSelf)
                                                 name:kOOJavaScriptEngineWillResetNotification
                                               object:[OOJavaScriptEngine sharedEngine]];
}

@end

static JSValue PlayerShipGetProperty(OOJS_GETTER_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    /*	SpiderMonkey compared this with the prototype. The prototype (like any
            object that isn't player.ship, such as the this of a detached getter
            call) has no private weak reference to the player.
    */
    if (EXPECT_NOT(OOIsPlayerStale() || JS_GetOpaque(this, sPlayerShipClassID) == NULL)) {
        return JS_UNDEFINED;
    }

    id result = nil;
    PlayerEntity* player = OOPlayerForScripting();

    switch (magic) {
    case kPlayerShip_activeMissile:
        return JS_NewNumber(context, [player activeMissile]);

    case kPlayerShip_fuelLeakRate:
        return JS_NewNumber(context, [player fuelLeakRate]);

    case kPlayerShip_docked:
        return OOJSValueFromBOOL([player isDocked]);

    case kPlayerShip_dockedStation:
        result = [player dockedStation];
        break;

    case kPlayerShip_specialCargo:
        result = [player specialCargo];
        break;

    case kPlayerShip_reticleColorTarget:
        result = [[[player hud] reticleColorForIndex:OO_RETICLE_COLOR_TARGET] normalizedArray];
        break;

    case kPlayerShip_reticleColorTargetSensitive:
        result = [[[player hud] reticleColorForIndex:OO_RETICLE_COLOR_TARGET_SENSITIVE] normalizedArray];
        break;

    case kPlayerShip_reticleColorWormhole:
        result = [[[player hud] reticleColorForIndex:OO_RETICLE_COLOR_WORMHOLE] normalizedArray];
        break;

    case kPlayerShip_reticleTargetSensitive:
        return OOJSValueFromBOOL([[player hud] reticleTargetSensitive]);

    case kPlayerShip_galacticHyperspaceBehaviour:
        return OOJSValueFromGalacticHyperspaceBehaviour(context, [player galacticHyperspaceBehaviour]);

    case kPlayerShip_galacticHyperspaceFixedCoords:
        OOJS_RETURN_WITH_HELPER(NSPointToVectorJSValue, [player galacticHyperspaceFixedCoords]);

    case kPlayerShip_galacticHyperspaceFixedCoordsInLY:
        OOJS_RETURN_VECTOR(OOGalacticCoordinatesFromInternal([player galacticHyperspaceFixedCoords]));

    case kPlayerShip_fastEquipmentA:
        result = [player fastEquipmentA];
        break;

    case kPlayerShip_fastEquipmentB:
        result = [player fastEquipmentB];
        break;

    case kPlayerShip_primedEquipment:
        result = [player currentPrimedEquipment];
        break;

    case kPlayerShip_forwardShield:
        return JS_NewNumber(context, [player forwardShieldLevel]);

    case kPlayerShip_aftShield:
        return JS_NewNumber(context, [player aftShieldLevel]);

    case kPlayerShip_maxForwardShield:
        return JS_NewNumber(context, [player maxForwardShieldLevel]);

    case kPlayerShip_maxAftShield:
        return JS_NewNumber(context, [player maxAftShieldLevel]);

    case kPlayerShip_forwardShieldRechargeRate:
        // No distinction made internally
        return JS_NewNumber(context, [player forwardShieldRechargeRate]);

    case kPlayerShip_aftShieldRechargeRate:
        // No distinction made internally
        return JS_NewNumber(context, [player aftShieldRechargeRate]);

    case kPlayerShip_multiFunctionDisplays:
        return JS_NewNumber(context, [[player hud] mfdCount]);

    case kPlayerShip_multiFunctionDisplayList:
        result = [player multiFunctionDisplayList];
        break;

    case kPlayerShip_missilesOnline:
        return OOJSValueFromBOOL(![player dialIdentEngaged]);

    case kPlayerShip_chartHightlightMode:
        result = OOStringFromLongRangeChartMode([player longRangeChartMode]);
        break;

    case kPlayerShip_galaxyCoordinates:
        OOJS_RETURN_WITH_HELPER(NSPointToVectorJSValue, [player galaxy_coordinates]);

    case kPlayerShip_galaxyCoordinatesInLY:
        OOJS_RETURN_VECTOR(OOGalacticCoordinatesFromInternal([player galaxy_coordinates]));

    case kPlayerShip_cursorCoordinates:
        OOJS_RETURN_WITH_HELPER(NSPointToVectorJSValue, [player cursor_coordinates]);

    case kPlayerShip_cursorCoordinatesInLY:
        OOJS_RETURN_VECTOR(OOGalacticCoordinatesFromInternal([player cursor_coordinates]));

    case kPlayerShip_targetSystem:
        return JS_NewInt32(context, [player targetSystemID]);

    case kPlayerShip_nextSystem:
        return JS_NewInt32(context, [player nextHopTargetSystemID]);

    case kPlayerShip_infoSystem:
        return JS_NewInt32(context, [player infoSystemID]);

    case kPlayerShip_previousSystem:
        return JS_NewInt32(context, [player previousSystemID]);

    case kPlayerShip_routeMode: {
        OORouteType route = [player ANAMode];
        switch (route) {
        case OPTIMIZED_BY_TIME:
            result = @"OPTIMIZED_BY_TIME";
            break;
        case OPTIMIZED_BY_JUMPS:
            result = @"OPTIMIZED_BY_JUMPS";
            break;
        case OPTIMIZED_BY_NONE:
            result = @"OPTIMIZED_BY_NONE";
            break;
        }
        break;
    }

    case kPlayerShip_scannerMinimalistic:
        return OOJSValueFromBOOL([[player hud] minimalisticScanner]);

    case kPlayerShip_scannerNonLinear:
        return OOJSValueFromBOOL([[player hud] nonlinearScanner]);

    case kPlayerShip_scannerUltraZoom:
        return OOJSValueFromBOOL([[player hud] scannerUltraZoom]);

    case kPlayerShip_scoopOverride:
        return OOJSValueFromBOOL([player scoopOverride]);

    case kPlayerShip_injectorsEngaged:
        return OOJSValueFromBOOL([player injectorsEngaged]);

    case kPlayerShip_massLockable:
        return OOJSValueFromBOOL([player massLockable]);

    case kPlayerShip_torusEngaged:
        return OOJSValueFromBOOL([player hyperspeedEngaged]);

    case kPlayerShip_compassTarget:
        result = [player compassTarget];
        break;

    case kPlayerShip_compassType:
        result = [OOStringFromCompassMode([player compassMode]) isEqualToString:@"COMPASS_MODE_BASIC"] ? @"OO_COMPASSTYPE_BASIC" : @"OO_COMPASSTYPE_ADVANCED";
        break;

    case kPlayerShip_compassMode:
        return OOJSValueFromCompassMode(context, [player compassMode]);

    case kPlayerShip_hud:
        result = [[player hud] hudName];
        break;

    case kPlayerShip_crosshairs:
        result = [[player hud] crosshairDefinition];
        break;

    case kPlayerShip_hudAllowsBigGui:
        return OOJSValueFromBOOL([[player hud] allowBigGui]);

    case kPlayerShip_hudHidden:
        return OOJSValueFromBOOL([[player hud] isHidden]);

    case kPlayerShip_weaponsOnline:
        return OOJSValueFromBOOL([player weaponsOnline]);

    case kPlayerShip_viewDirection:
        return OOJSValueFromViewID(context, [UNIVERSE viewDirection]);

    case kPlayerShip_viewPositionAft:
        OOJS_RETURN_VECTOR([player viewpointOffsetAft]);

    case kPlayerShip_viewPositionForward:
        OOJS_RETURN_VECTOR([player viewpointOffsetForward]);

    case kPlayerShip_viewPositionPort:
        OOJS_RETURN_VECTOR([player viewpointOffsetPort]);

    case kPlayerShip_viewPositionStarboard:
        OOJS_RETURN_VECTOR([player viewpointOffsetStarboard]);

    case kPlayerShip_currentWeapon:
        result = [player weaponTypeForFacing:[player currentWeaponFacing] strict:NO];
        break;

    case kPlayerShip_price:
        return JS_NewNumber(context, [UNIVERSE tradeInValueForCommanderDictionary:[player commanderDataDictionary]]);

    case kPlayerShip_serviceLevel:
        return JS_NewNumber(context, [player tradeInFactor]);

    case kPlayerShip_renovationCost:
        return JS_NewNumber(context, [player renovationCosts]);

    case kPlayerShip_renovationMultiplier:
        return JS_NewNumber(context, [player renovationFactor]);

        // make roll, pitch, yaw reported to JS use same +/- convention as
        // for NPC ships
    case kPlayerShip_pitch:
        return JS_NewNumber(context, -[player flightPitch]);

    case kPlayerShip_roll:
        return JS_NewNumber(context, -[player flightRoll]);

    case kPlayerShip_yaw:
        return JS_NewNumber(context, -[player flightYaw]);

    case kPlayerShip_messageGuiTextColor:
        result = [[[UNIVERSE messageGUI] textColor] normalizedArray];
        break;

    case kPlayerShip_messageGuiTextCommsColor:
        result = [[[UNIVERSE messageGUI] textCommsColor] normalizedArray];
        break;

    default:
        OOJSReportBadPropertySelector(context, this, magic, sPlayerShipProperties, OOJS_COUNT(sPlayerShipProperties));
        return OOJSNativeFailure(context);
    }

    return OOJSValueFromNativeObject(context, result);

    OOJS_NATIVE_EXIT
}

static JSValue PlayerShipSetProperty(OOJS_SETTER_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    if (EXPECT_NOT(OOIsPlayerStale()))
        return JS_UNDEFINED;

    PlayerEntity* player = OOPlayerForScripting();
    double fValue;
    int bValue;
    int32_t iValue;
    NSString* sValue = nil;
    OOGalacticHyperspaceBehaviour ghBehaviour;
    Vector vValue;
    OOColor* colorForScript = nil;
    Entity* eValue = nil;

    switch (magic) {
    case kPlayerShip_fuelLeakRate:
        if (JS_ToFloat64(context, &fValue, value) == 0) {
            [player setFuelLeakRate:fValue];
            return JS_UNDEFINED;
        }
        break;

    case kPlayerShip_massLockable:
        if ((bValue = JS_ToBool(context, value)) >= 0) {
            [player setMassLockable:bValue];
            return JS_UNDEFINED;
        }
        break;

    case kPlayerShip_reticleTargetSensitive:
        if ((bValue = JS_ToBool(context, value)) >= 0) {
            [[player hud] setReticleTargetSensitive:bValue];
            return JS_UNDEFINED;
        }
        break;

    case kPlayerShip_chartHightlightMode:
        sValue = OOStringFromJSValue(context, value);
        if (sValue != nil) {
            OOLongRangeChartMode chartMode = OOLongRangeChartModeFromString(sValue);
            if (chartMode > OOLRC_MODE_UNKNOWN) {
                [player setLongRangeChartMode:chartMode];
                [player doScriptEvent:OOJSID("chartHighlightModeChanged") withArgument:OOStringFromLongRangeChartMode([player longRangeChartMode])];
                return JS_UNDEFINED;
            } else {
                OOJSReportError(context, @"Unknown chart hightlight mode specified - must be either OOLRC_MODE_SUNCOLOR, OOLRC_MODE_ECONOMY, OOLRC_MODE_GOVERNMENT or OOLRC_MODE_TECHLEVEL.");
            }
        }
        return OOJSNativeFailure(context); // not reachable if successfully set
        break;

    case kPlayerShip_compassMode:
        sValue = OOStringFromJSValue(context, value);
        if (sValue != nil) {
            OOCompassMode mode = OOCompassModeFromJSValue(context, value);
            [player setCompassMode:mode];
            [player validateCompassTarget];
            return JS_UNDEFINED;
        }
        break;

    case kPlayerShip_compassType:
        sValue = OOStringFromJSValue(context, value);
        if (sValue != nil) {
            if ([sValue isEqualToString:@"OO_COMPASSTYPE_BASIC"]) {
                [player setCompassMode:COMPASS_MODE_BASIC];
            } else if ([sValue isEqualToString:@"OO_COMPASSTYPE_ADVANCED"]) {
                if (![player hasEquipmentItemProviding:@"EQ_ADVANCED_COMPASS"]) {
                    OOJSReportWarning(context, @"Advanced Compass type requested and set but player ship does not carry the EQ_ADVANCED_COMPASS equipment or has it damaged.");
                }
                [player setCompassMode:COMPASS_MODE_PLANET];
            } else {
                OOJSReportError(context, @"Unknown compass type specified - must be either OO_COMPASSTYPE_BASIC or OO_COMPASSTYPE_ADVANCED.");
                return OOJSNativeFailure(context);
            }
            return JS_UNDEFINED;
        }
        break;

    case kPlayerShip_compassTarget:
        // can't change compass target in basic mode
        if (![player hasEquipmentItemProviding:@"EQ_ADVANCED_COMPASS"]) {
            OOJSReportError(context, @"Compass target cannot be set with a basic compass.");
            return OOJSNativeFailure(context);
        }
        // make sure we have a valid entity
        if (!JS_IsNull(value) && JSValueToEntity(context, value, &eValue)) {
            Entity* current = [player compassTarget];
            [player setNextCompassMode];
            [player validateCompassTarget];
            // cycle the targets until we either get back to the start (entity not found) or we find the one we're looking for
            while ([player compassTarget] != current && [player compassTarget] != eValue) {
                [player setNextCompassMode];
                [player validateCompassTarget];
            }
            // SpiderMonkey returned NO (stopping the script without an error) if the target wasn't found.
            if ([player compassTarget] == current)
                return OOJSNativeFailure(context);
            return JS_UNDEFINED;
        } else {
            OOJSReportError(context, @"Invalid compass target entity provided.");
            return OOJSNativeFailure(context);
        }
        break;

    case kPlayerShip_galacticHyperspaceBehaviour:
        ghBehaviour = OOGalacticHyperspaceBehaviourFromJSValue(context, value);
        if (ghBehaviour != GALACTIC_HYPERSPACE_BEHAVIOUR_UNKNOWN) {
            [player setGalacticHyperspaceBehaviour:ghBehaviour];
            return JS_UNDEFINED;
        }
        break;

    case kPlayerShip_galacticHyperspaceFixedCoords:
        if (JSValueToVector(context, value, &vValue)) {
            NSPoint coords = { vValue.x, vValue.y };
            [player setGalacticHyperspaceFixedCoords:coords];
            return JS_UNDEFINED;
        }
        break;

    case kPlayerShip_galacticHyperspaceFixedCoordsInLY:
        if (JSValueToVector(context, value, &vValue)) {
            NSPoint coords = OOInternalCoordinatesFromGalactic(vValue);
            [player setGalacticHyperspaceFixedCoords:coords];
            return JS_UNDEFINED;
        }
        break;

    case kPlayerShip_fastEquipmentA:
        sValue = OOStringFromJSValue(context, value);
        if (sValue != nil) {
            [player setFastEquipmentA:sValue];
            return JS_UNDEFINED;
        }
        break;

    case kPlayerShip_fastEquipmentB:
        sValue = OOStringFromJSValue(context, value);
        if (sValue != nil) {
            [player setFastEquipmentB:sValue];
            return JS_UNDEFINED;
        }
        break;

    case kPlayerShip_primedEquipment:
        sValue = OOStringFromJSValue(context, value);
        if (sValue != nil) {
            // As before, failure stops the script without an error.
            if (![player setPrimedEquipment:sValue showMessage:NO])
                return OOJSNativeFailure(context);
            return JS_UNDEFINED;
        }
        break;

    case kPlayerShip_pitch:
        if (JS_ToFloat64(context, &fValue, value) == 0) {
            if (!isnan(fValue)) // guard against undefined
            {
                [player decrease_flight_pitch:[player flightPitch] + fValue];
            }
            return JS_UNDEFINED;
        }
        break;

    case kPlayerShip_roll:
        if (JS_ToFloat64(context, &fValue, value) == 0) {
            if (!isnan(fValue)) // guard against undefined
            {
                [player decrease_flight_roll:[player flightRoll] + fValue];
            }
            return JS_UNDEFINED;
        }
        break;

    case kPlayerShip_yaw:
        if (JS_ToFloat64(context, &fValue, value) == 0) {
            if (!isnan(fValue)) // guard against undefined
            {
                [player decrease_flight_yaw:[player flightYaw] + fValue];
            }
            return JS_UNDEFINED;
        }
        break;

    case kPlayerShip_forwardShield:
        if (JS_ToFloat64(context, &fValue, value) == 0) {
            [player setForwardShieldLevel:fValue];
            return JS_UNDEFINED;
        }
        break;

    case kPlayerShip_aftShield:
        if (JS_ToFloat64(context, &fValue, value) == 0) {
            [player setAftShieldLevel:fValue];
            return JS_UNDEFINED;
        }
        break;

    case kPlayerShip_maxForwardShield:
        if (JS_ToFloat64(context, &fValue, value) == 0) {
            [player setMaxForwardShieldLevel:fValue];
            return JS_UNDEFINED;
        }
        break;

    case kPlayerShip_maxAftShield:
        if (JS_ToFloat64(context, &fValue, value) == 0) {
            [player setMaxAftShieldLevel:fValue];
            return JS_UNDEFINED;
        }
        break;

    case kPlayerShip_forwardShieldRechargeRate:
        if (JS_ToFloat64(context, &fValue, value) == 0) {
            [player setForwardShieldRechargeRate:fValue];
            return JS_UNDEFINED;
        }
        break;

    case kPlayerShip_aftShieldRechargeRate:
        if (JS_ToFloat64(context, &fValue, value) == 0) {
            [player setAftShieldRechargeRate:fValue];
            return JS_UNDEFINED;
        }
        break;

    case kPlayerShip_scannerMinimalistic:
        if ((bValue = JS_ToBool(context, value)) >= 0) {
            [[player hud] setMinimalisticScanner:bValue];
            return JS_UNDEFINED;
        }
        break;

    case kPlayerShip_scannerNonLinear:
        if ((bValue = JS_ToBool(context, value)) >= 0) {
            [[player hud] setNonlinearScanner:bValue];
            return JS_UNDEFINED;
        }
        break;

    case kPlayerShip_scannerUltraZoom:
        if ((bValue = JS_ToBool(context, value)) >= 0) {
            [[player hud] setScannerUltraZoom:bValue];
            return JS_UNDEFINED;
        }
        break;

    case kPlayerShip_scoopOverride:
        if ((bValue = JS_ToBool(context, value)) >= 0) {
            [player setScoopOverride:bValue];
            return JS_UNDEFINED;
        }
        break;

    case kPlayerShip_hud:
        sValue = OOStringFromJSValue(context, value);
        if (sValue != nil) {
            [player switchHudTo:sValue]; // EMMSTRAN: logged error should be a JS warning.
            return JS_UNDEFINED;
        } else {
            [player resetHud];
            return JS_UNDEFINED;
        }
        break;

    case kPlayerShip_crosshairs:
        sValue = OOStringFromJSValue(context, value);
        if (sValue == nil) {
            // reset HUD back to its plist settings
            NSString* hud = [[[player hud] hudName] retain];
            [player switchHudTo:hud];
            [hud release];
            return JS_UNDEFINED;
        } else {
            if (![[player hud] setCrosshairDefinition:sValue]) {
                OOJSReportWarning(context, @"Crosshair definition file %@ not found or invalid", sValue);
            }
            return JS_UNDEFINED;
        }
        break;

    case kPlayerShip_hudHidden:
        if ((bValue = JS_ToBool(context, value)) >= 0) {
            [[player hud] setHidden:bValue];
            return JS_UNDEFINED;
        }
        break;

    case kPlayerShip_serviceLevel:
        if (JS_ToFloat64(context, &fValue, value) == 0) {
            int newLevel = (int)fValue;
            [player adjustTradeInFactorBy:(newLevel - [player tradeInFactor])];
            return JS_UNDEFINED;
        }
        /*	The SpiderMonkey version fell through to currentWeapon here (which
                removed the current weapon) if the conversion threw. Report the bad
                value instead.
        */
        break;

    case kPlayerShip_currentWeapon: {
        BOOL exists = NO;
        sValue = JSValueToEquipmentKeyRelaxed(context, value, &exists);
        if (!exists || sValue == nil) {
            sValue = @"EQ_WEAPON_NONE";
        }
        [player setWeaponMount:[player currentWeaponFacing] toWeapon:sValue inContext:@"scripted"];
        return JS_UNDEFINED;
    }

    case kPlayerShip_targetSystem:
        /* This first check is essential: if removed, it would be
         * possible to make jumps of arbitrary length - CIM */
        if ([player status] != STATUS_ENTERING_WITCHSPACE) {
            /* These checks though similar are less important. The
             * consequences of allowing jump destination to be set in
             * flight are not as severe and do not allow the 7LY limit to
             * be broken. Nevertheless, it is not allowed. - CIM */
            // (except when compiled in debugging mode)
#ifndef OO_DUMP_PLANETINFO
            if (EXPECT_NOT([player status] != STATUS_DOCKED && [player status] != STATUS_LAUNCHING)) {
                OOJSReportError(context, @"player.ship.targetSystem is read-only unless called when docked.");
                return OOJSNativeFailure(context);
            }
#endif

            if (OOJSValueToInt32(context, value, &iValue)) {
                if (iValue >= 0 && iValue < OO_SYSTEMS_PER_GALAXY) {
                    [player setTargetSystemID:iValue];
                    return JS_UNDEFINED;
                } else {
                    return OOJSNativeFailure(context);
                }
            }
            /*	The SpiderMonkey version fell through to infoSystem, which
                    converted the value again, failed again and reported the bad
                    value.
            */
            break;
        } else {
            OOJSReportError(context, @"player.ship.targetSystem is read-only unless called when docked.");
            return OOJSNativeFailure(context);
        }

    case kPlayerShip_infoSystem:
        if (OOJSValueToInt32(context, value, &iValue)) {
            if (iValue >= 0 && iValue < OO_SYSTEMS_PER_GALAXY) {
                [player setInfoSystemID:iValue moveChart:YES];
                return JS_UNDEFINED;
            } else {
                return OOJSNativeFailure(context);
            }
        }
        break;

    case kPlayerShip_messageGuiTextColor:
        colorForScript = [OOColor colorWithDescription:OOJSNativeObjectFromJSValue(context, value)];
        if (colorForScript != nil || JS_IsNull(value)) {
            [[UNIVERSE messageGUI] setTextColor:colorForScript];
            return JS_UNDEFINED;
        }
        break;

    case kPlayerShip_messageGuiTextCommsColor:
        colorForScript = [OOColor colorWithDescription:OOJSNativeObjectFromJSValue(context, value)];
        if (colorForScript != nil || JS_IsNull(value)) {
            [[UNIVERSE messageGUI] setTextCommsColor:colorForScript];
            return JS_UNDEFINED;
        }
        break;

    case kPlayerShip_reticleColorTarget:
        colorForScript = [OOColor colorWithDescription:OOJSNativeObjectFromJSValue(context, value)];
        if (colorForScript != nil || JS_IsNull(value)) {
            if (![[player hud] setReticleColorForIndex:OO_RETICLE_COLOR_TARGET toColor:colorForScript])
                return OOJSNativeFailure(context);
            return JS_UNDEFINED;
        }
        break;

    case kPlayerShip_reticleColorTargetSensitive:
        colorForScript = [OOColor colorWithDescription:OOJSNativeObjectFromJSValue(context, value)];
        if (colorForScript != nil || JS_IsNull(value)) {
            if (![[player hud] setReticleColorForIndex:OO_RETICLE_COLOR_TARGET_SENSITIVE toColor:colorForScript])
                return OOJSNativeFailure(context);
            return JS_UNDEFINED;
        }
        break;

    case kPlayerShip_reticleColorWormhole:
        colorForScript = [OOColor colorWithDescription:OOJSNativeObjectFromJSValue(context, value)];
        if (colorForScript != nil || JS_IsNull(value)) {
            if (![[player hud] setReticleColorForIndex:OO_RETICLE_COLOR_WORMHOLE toColor:colorForScript])
                return OOJSNativeFailure(context);
            return JS_UNDEFINED;
        }
        break;

    default:
        OOJSReportBadPropertySelector(context, this, magic, sPlayerShipProperties, OOJS_COUNT(sPlayerShipProperties));
        return OOJSNativeFailure(context);
    }

    OOJSReportBadPropertyValue(context, this, magic, sPlayerShipProperties, OOJS_COUNT(sPlayerShipProperties), value);
    return OOJSNativeFailure(context);

    OOJS_NATIVE_EXIT
}

// *** Methods ***

// launch()
static JSValue PlayerShipLaunch(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    if (EXPECT_NOT(OOIsPlayerStale()))
        OOJS_RETURN_VOID;

    [OOPlayerForScripting() launchFromStation];
    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}

// removeAllCargo()
static JSValue PlayerShipRemoveAllCargo(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    if (EXPECT_NOT(OOIsPlayerStale()))
        OOJS_RETURN_VOID;

    PlayerEntity* player = OOPlayerForScripting();

    if ([player isDocked]) {
        [player removeAllCargo];
        OOJS_RETURN_VOID;
    } else {
        OOJSReportError(context, @"PlayerShip.removeAllCargo only works when docked.");
        return OOJSNativeFailure(context);
    }

    OOJS_NATIVE_EXIT
}

// useSpecialCargo(name : String)
static JSValue PlayerShipUseSpecialCargo(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    if (EXPECT_NOT(OOIsPlayerStale()))
        OOJS_RETURN_VOID;

    PlayerEntity* player = OOPlayerForScripting();
    NSString* name = nil;

    if (argc > 0)
        name = OOStringFromJSValue(context, OOJS_ARGV[0]);
    if (EXPECT_NOT(name == nil)) {
        OOJSReportBadArguments(context, @"PlayerShip", @"useSpecialCargo", MIN(argc, 1), OOJS_ARGV, nil, @"string (special cargo description)");
        return OOJSNativeFailure(context);
    }

    [player useSpecialCargo:OOStringFromJSValue(context, OOJS_ARGV[0])];
    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}

// engageAutopilotToStation(stationForDocking : Station) : Boolean
static JSValue PlayerShipEngageAutopilotToStation(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    if (EXPECT_NOT(OOIsPlayerStale()))
        OOJS_RETURN_VOID;

    PlayerEntity* player = OOPlayerForScripting();
    StationEntity* stationForDocking = nil;

    if (argc > 0)
        stationForDocking = OOJSNativeObjectOfClassFromJSValue(context, OOJS_ARGV[0], [StationEntity class]);
    if (stationForDocking == nil) {
        OOJSReportBadArguments(context, @"PlayerShip", @"engageAutopilot", MIN(argc, 1), OOJS_ARGV, nil, @"station");
        return OOJSNativeFailure(context);
    }

    OOJS_RETURN_BOOL([player engageAutopilotToStation:stationForDocking]);

    OOJS_NATIVE_EXIT
}

// disengageAutopilot()
static JSValue PlayerShipDisengageAutopilot(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    if (EXPECT_NOT(OOIsPlayerStale()))
        OOJS_RETURN_VOID;

    [OOPlayerForScripting() disengageAutopilot];
    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}

static JSValue PlayerShipRequestDockingClearance(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    if (EXPECT_NOT(OOIsPlayerStale()))
        OOJS_RETURN_VOID;

    PlayerEntity* player = OOPlayerForScripting();
    StationEntity* stationForDocking = nil;

    if (argc > 0)
        stationForDocking = OOJSNativeObjectOfClassFromJSValue(context, OOJS_ARGV[0], [StationEntity class]);
    if (stationForDocking == nil) {
        OOJSReportBadArguments(context, @"PlayerShip", @"requestDockingClearance", MIN(argc, 1), OOJS_ARGV, nil, @"station");
        return OOJSNativeFailure(context);
    }

    [player requestDockingClearance:stationForDocking];
    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}

static JSValue PlayerShipCancelDockingRequest(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    if (EXPECT_NOT(OOIsPlayerStale()))
        OOJS_RETURN_VOID;

    PlayerEntity* player = OOPlayerForScripting();
    StationEntity* stationForDocking = nil;

    if (argc > 0)
        stationForDocking = OOJSNativeObjectOfClassFromJSValue(context, OOJS_ARGV[0], [StationEntity class]);
    if (stationForDocking == nil) {
        OOJSReportBadArguments(context, @"PlayerShip", @"cancelDockingRequest", MIN(argc, 1), OOJS_ARGV, nil, @"station");
        return OOJSNativeFailure(context);
    }

    [player cancelDockingRequest:stationForDocking];
    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}

// awardEquipmentToCurrentPylon(externalTank: equipmentInfoExpression) : Boolean
static JSValue PlayerShipAwardEquipmentToCurrentPylon(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    if (EXPECT_NOT(OOIsPlayerStale()))
        OOJS_RETURN_VOID;

    PlayerEntity* player = OOPlayerForScripting();
    NSString* key = nil;
    OOEquipmentType* eqType = nil;

    if (argc > 0)
        key = JSValueToEquipmentKey(context, OOJS_ARGV[0]);
    if (key != nil)
        eqType = [OOEquipmentType equipmentTypeWithIdentifier:key];
    if (EXPECT_NOT(![eqType isMissileOrMine])) {
        OOJSReportBadArguments(context, @"PlayerShip", @"awardEquipmentToCurrentPylon", MIN(argc, 1), OOJS_ARGV, nil, @"equipment type (external store)");
        return OOJSNativeFailure(context);
    }

    OOJS_RETURN_BOOL([player assignToActivePylon:key]);

    OOJS_NATIVE_EXIT
}

// addPassenger(name: string, start: int, destination: int, ETA: double, fee: double) : Boolean
static JSValue PlayerShipAddPassenger(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    PlayerEntity* player = OOPlayerForScripting();
    NSString* name = nil;
    OOSystemID start = 0, destination = 0;
    double eta = 0.0, fee = 0.0, advance = 0.0;
    unsigned risk = 0;

    if (argc < 5) {
        OOJSReportBadArguments(context, @"PlayerShip", @"addPassenger", argc, OOJS_ARGV, nil, @"name, start, destination, ETA, fee");
        return OOJSNativeFailure(context);
    }

    name = OOStringFromJSValue(context, OOJS_ARGV[0]);
    if (EXPECT_NOT(name == nil)) {
        OOJSReportBadArguments(context, @"PlayerShip", @"addPassenger", 1, &OOJS_ARGV[0], nil, @"string");
        return OOJSNativeFailure(context);
    }

    if (!ValidateContracts(context, argc, OOJS_ARGV, NO, &start, &destination, &eta, &fee, &advance, @"addPassenger", &risk))
        return OOJSNativeFailure(context); // always go through validate contracts (passenger)

    // Ensure there's space.
    if ([player passengerCount] >= [player passengerCapacity])
        OOJS_RETURN_BOOL(NO);

    BOOL OK = [player addPassenger:name start:start destination:destination eta:eta fee:fee advance:advance risk:risk];
    OOJS_RETURN_BOOL(OK);

    OOJS_NATIVE_EXIT
}

// removePassenger(name :string)
static JSValue PlayerShipRemovePassenger(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    PlayerEntity* player = OOPlayerForScripting();
    NSString* name = nil;
    BOOL OK = YES;

    if (argc > 0)
        name = OOStringFromJSValue(context, OOJS_ARGV[0]);
    if (EXPECT_NOT(name == nil)) {
        OOJSReportBadArguments(context, @"PlayerShip", @"removePassenger", MIN(argc, 1), OOJS_ARGV, nil, @"string");
        return OOJSNativeFailure(context);
    }

    OK = [player passengerCount] > 0 && [name length] > 0;
    if (OK)
        OK = [player removePassenger:name];

    OOJS_RETURN_BOOL(OK);

    OOJS_NATIVE_EXIT
}

// addParcel(description: string, start: int, destination: int, ETA: double, fee: double) : Boolean
static JSValue PlayerShipAddParcel(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    PlayerEntity* player = OOPlayerForScripting();
    NSString* name = nil;
    OOSystemID start = 0, destination = 0;
    double eta = 0.0, fee = 0.0, premium = 0.0;
    unsigned risk = 0;

    if (argc < 5) {
        OOJSReportBadArguments(context, @"PlayerShip", @"addParcel", argc, OOJS_ARGV, nil, @"name, start, destination, ETA, fee");
        return OOJSNativeFailure(context);
    }

    name = OOStringFromJSValue(context, OOJS_ARGV[0]);
    if (EXPECT_NOT(name == nil)) {
        OOJSReportBadArguments(context, @"PlayerShip", @"addParcel", 1, &OOJS_ARGV[0], nil, @"string");
        return OOJSNativeFailure(context);
    }

    if (!ValidateContracts(context, argc, OOJS_ARGV, NO, &start, &destination, &eta, &fee, &premium, @"addParcel", &risk))
        return OOJSNativeFailure(context); // always go through validate contracts (passenger/parcel mode)

    // Ensure there's space.

    BOOL OK = [player addParcel:name start:start destination:destination eta:eta fee:fee premium:premium risk:risk];
    OOJS_RETURN_BOOL(OK);

    OOJS_NATIVE_EXIT
}

// removeParcel(description :string)
static JSValue PlayerShipRemoveParcel(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    PlayerEntity* player = OOPlayerForScripting();
    NSString* name = nil;
    BOOL OK = YES;

    if (argc > 0)
        name = OOStringFromJSValue(context, OOJS_ARGV[0]);
    if (EXPECT_NOT(name == nil)) {
        OOJSReportBadArguments(context, @"PlayerShip", @"removeParcel", MIN(argc, 1), OOJS_ARGV, nil, @"string");
        return OOJSNativeFailure(context);
    }

    OK = [player parcelCount] > 0 && [name length] > 0;
    if (OK)
        OK = [player removeParcel:name];

    OOJS_RETURN_BOOL(OK);

    OOJS_NATIVE_EXIT
}

// awardContract(quantity: int, commodity: string, start: int, destination: int, eta: double, fee: double) : Boolean
static JSValue PlayerShipAwardContract(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    PlayerEntity* player = OOPlayerForScripting();
    NSString* key = nil;
    int32_t qty = 0;
    OOSystemID start = 0, destination = 0;
    double eta = 0.0, fee = 0.0, premium = 0.0;

    if (argc < 6) {
        OOJSReportBadArguments(context, @"PlayerShip", @"awardContract", argc, OOJS_ARGV, nil, @"quantity, commodity, start, destination, ETA, fee");
        return OOJSNativeFailure(context);
    }

    if (!OOJSValueToInt32(context, OOJS_ARGV[0], &qty)) {
        OOJSReportBadArguments(context, @"PlayerShip", @"awardContract", 1, &OOJS_ARGV[0], nil, @"positive integer (cargo quantity)");
        return OOJSNativeFailure(context);
    }

    key = OOStringFromJSValue(context, OOJS_ARGV[1]);
    if (EXPECT_NOT(key == nil)) {
        OOJSReportBadArguments(context, @"PlayerShip", @"awardContract", 1, &OOJS_ARGV[1], nil, @"string (commodity identifier)");
        return OOJSNativeFailure(context);
    }

    if (!ValidateContracts(context, argc, OOJS_ARGV, YES, &start, &destination, &eta, &fee, &premium, @"awardContract", NULL))
        return OOJSNativeFailure(context); // always go through validate contracts (cargo)

    BOOL OK = [player awardContract:qty commodity:key start:start destination:destination eta:eta fee:fee premium:premium];
    OOJS_RETURN_BOOL(OK);

    OOJS_NATIVE_EXIT
}

// removeContract(commodity: string, destination: int)
static JSValue PlayerShipRemoveContract(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    PlayerEntity* player = OOPlayerForScripting();
    NSString* key = nil;
    int32_t dest = 0;

    if (argc < 2) {
        OOJSReportBadArguments(context, @"PlayerShip", @"removeContract", argc, OOJS_ARGV, nil, @"commodity, destination");
        return OOJSNativeFailure(context);
    }

    key = OOStringFromJSValue(context, OOJS_ARGV[0]);

    if (EXPECT_NOT(key == nil)) {
        OOJSReportBadArguments(context, @"PlayerShip", @"removeContract", 1, &OOJS_ARGV[0], nil, @"string (commodity identifier)");
        return OOJSNativeFailure(context);
    }

    if (!OOJSValueToInt32(context, OOJS_ARGV[1], &dest) || dest < 0 || dest > 255) {
        OOJSReportBadArguments(context, @"PlayerShip", @"removeContract", 1, &OOJS_ARGV[1], nil, @"system ID");
        return OOJSNativeFailure(context);
    }

    BOOL OK = [player removeContract:key destination:(unsigned)dest];
    OOJS_RETURN_BOOL(OK);

    OOJS_NATIVE_EXIT
}

// setCustomView(position:vector, orientation:quaternion [, weapon:string])
static JSValue PlayerShipSetCustomView(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    PlayerEntity* player = OOPlayerForScripting();

    if (argc < 2) {
        OOJSReportBadArguments(context, @"PlayerShip", @"setCustomView", argc, OOJS_ARGV, nil, @"position, orientiation, [weapon]");
        return OOJSNativeFailure(context);
    }

    // must be in custom view
    if ([UNIVERSE viewDirection] != VIEW_CUSTOM) {
        OOJSReportError(context, @"PlayerShip.setCustomView only works when custom view is active.");
        return OOJSNativeFailure(context);
    }

    NSMutableDictionary* viewData = [NSMutableDictionary dictionaryWithCapacity:3];

    Vector position = kZeroVector;
    BOOL gotpos = JSValueToVector(context, OOJS_ARGV[0], &position);
    if (!gotpos) {
        OOJSReportBadArguments(context, @"PlayerShip", @"setCustomView", argc, OOJS_ARGV, nil, @"position, orientiation, [weapon]");
        return OOJSNativeFailure(context);
    }
    NSString* positionstr = [[NSString alloc] initWithFormat:@"%f %f %f", position.x, position.y, position.z];

    Quaternion orientation = kIdentityQuaternion;
    BOOL gotquat = JSValueToQuaternion(context, OOJS_ARGV[1], &orientation);
    if (!gotquat) {
        [positionstr release]; // (Leaked in the SpiderMonkey version.)
        OOJSReportBadArguments(context, @"PlayerShip", @"setCustomView", argc, OOJS_ARGV, nil, @"position, orientiation, [weapon]");
        return OOJSNativeFailure(context);
    }
    NSString* orientationstr = [[NSString alloc] initWithFormat:@"%f %f %f %f", orientation.w, orientation.x, orientation.y, orientation.z];

    [viewData setObject:positionstr forKey:@"view_position"];
    [viewData setObject:orientationstr forKey:@"view_orientation"];

    if (argc > 2) {
        NSString* facing = OOStringFromJSValue(context, OOJS_ARGV[2]);
        [viewData setObject:facing forKey:@"weapon_facing"];
    }

    [player setCustomViewDataFromDictionary:viewData withScaling:NO];
    [player noteSwitchToView:VIEW_CUSTOM fromView:VIEW_CUSTOM];

    [positionstr release];
    [orientationstr release];

    OOJS_RETURN_BOOL(YES);
    OOJS_NATIVE_EXIT
}

// resetCustomView()
static JSValue PlayerShipResetCustomView(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    PlayerEntity* player = OOPlayerForScripting();

    // must be in custom view
    if ([UNIVERSE viewDirection] != VIEW_CUSTOM) {
        OOJSReportError(context, @"PlayerShip.setCustomView only works when custom view is active.");
        return OOJSNativeFailure(context);
    }

    [player resetCustomView];
    [player noteSwitchToView:VIEW_CUSTOM fromView:VIEW_CUSTOM];

    OOJS_RETURN_BOOL(YES);
    OOJS_NATIVE_EXIT
}

// resetScannerZoom()
static JSValue PlayerShipResetScannerZoom(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    PlayerEntity* player = OOPlayerForScripting();

    [player resetScannerZoom];

    OOJS_RETURN_VOID;
    OOJS_NATIVE_EXIT
}

// takeInternalDamage()
static JSValue PlayerShipTakeInternalDamage(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    PlayerEntity* player = OOPlayerForScripting();

    BOOL took = [player takeInternalDamage];

    OOJS_RETURN_BOOL(took);
    OOJS_NATIVE_EXIT
}

// beginHyperspaceCountdown([int: spin_time])
static JSValue PlayerShipBeginHyperspaceCountdown(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    PlayerEntity* player = OOPlayerForScripting();
    int32_t spin_time;
    int32_t witchspaceSpinUpTime = 0;
    BOOL begun = NO;
    if (argc < 1) {
        witchspaceSpinUpTime = 0;
#ifdef OO_DUMP_PLANETINFO
        // quick intersystem jumps for debugging
        witchspaceSpinUpTime = 1;
#endif
    } else {
        if (!OOJSValueToInt32(context, OOJS_ARGV[0], &spin_time) || spin_time < 5 || spin_time > 60) {
            OOJSReportBadArguments(context, @"PlayerShip", @"beginHyperspaceCountdown", 1, &OOJS_ARGV[0], nil, @"between 5 and 60 seconds");
            return OOJSNativeFailure(context);
        }
        if (spin_time < 5) {
            witchspaceSpinUpTime = 5;
        } else {
            witchspaceSpinUpTime = spin_time;
        }
    }
    if ([player hasHyperspaceMotor] && [player status] == STATUS_IN_FLIGHT && [player witchJumpChecklist:false]) {
        [player beginWitchspaceCountdown:witchspaceSpinUpTime];
        begun = YES;
    }
    OOJS_RETURN_BOOL(begun);
    OOJS_NATIVE_EXIT
}

// cancelHyperspaceCountdown()
static JSValue PlayerShipCancelHyperspaceCountdown(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    PlayerEntity* player = OOPlayerForScripting();

    BOOL cancelled = NO;
    if ([player hasHyperspaceMotor] && [player status] == STATUS_WITCHSPACE_COUNTDOWN) {
        [player cancelWitchspaceCountdown];
        [player setJumpType:false];
        cancelled = YES;
    }

    OOJS_RETURN_BOOL(cancelled);
    OOJS_NATIVE_EXIT
}

static JSValue PlayerShipBeginGalacticHyperspaceCountdown(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    PlayerEntity* player = OOPlayerForScripting();
    int32_t spin_time;
    int32_t witchspaceSpinUpTime = 5;
    BOOL begun = NO;
    if (argc == 1) {

        if (!OOJSValueToInt32(context, OOJS_ARGV[0], &spin_time) || spin_time < 5 || spin_time > 60) {
            OOJSReportBadArguments(context, @"PlayerShip", @"beginGalacticHyperspaceCountdown", 1, &OOJS_ARGV[0], nil, @"between 5 and 60 seconds");
            return OOJSNativeFailure(context);
        }
        if (spin_time < 5) {
            witchspaceSpinUpTime = 5;
        } else {
            witchspaceSpinUpTime = spin_time;
        }
    }
    if ([player hasEquipmentItemProviding:@"EQ_GAL_DRIVE"] && [player status] == STATUS_IN_FLIGHT && [player witchJumpChecklist:true]) {
        [player setJumpType:YES];
        [player setWitchspaceCountdown:witchspaceSpinUpTime];
        [player setStatus:STATUS_WITCHSPACE_COUNTDOWN];
        [player playGalacticHyperspace];
        // say it!
        [UNIVERSE addMessage:[NSString stringWithFormat:DESC(@"witch-galactic-in-f-seconds"), witchspaceSpinUpTime] forCount:1.0];
        begun = YES;
    }
    OOJS_RETURN_BOOL(begun);
    OOJS_NATIVE_EXIT
}

// setMultiFunctionDisplay(index,key)
static JSValue PlayerShipSetMultiFunctionDisplay(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    NSString* key = nil;
    uint32_t index = 0;
    PlayerEntity* player = OOPlayerForScripting();
    BOOL OK = YES;

    if (argc > 0) {
        if (JS_ToUint32(context, &index, OOJS_ARGV[0]) != 0) {
            OOJSReportBadArguments(context, @"PlayerShip", @"setMultiFunctionDisplay", MIN(argc, 1), OOJS_ARGV, nil, @"number (index) [, string (key)]");
            return OOJSNativeFailure(context);
        }
    }

    if (argc > 1) {
        key = OOStringFromJSValue(context, OOJS_ARGV[1]);
    }

    OK = [player setMultiFunctionDisplay:index toKey:key];

    OOJS_RETURN_BOOL(OK);

    OOJS_NATIVE_EXIT
}

// setMultiFunctionText(key,value)
static JSValue PlayerShipSetMultiFunctionText(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    NSString* key = nil;
    NSString* value = nil;
    PlayerEntity* player = OOPlayerForScripting();
    int reflow = NO;

    if (argc > 0) {
        key = OOStringFromJSValue(context, OOJS_ARGV[0]);
    }
    if (key == nil) {
        OOJSReportBadArguments(context, @"PlayerShip", @"setMultiFunctionText", MIN(argc, 1), OOJS_ARGV, nil, @"string (key) [, string (text)]");
        return OOJSNativeFailure(context);
    }
    if (argc > 1) {
        value = OOStringFromJSValue(context, OOJS_ARGV[1]);
    }
    if (argc > 2 && EXPECT_NOT((reflow = JS_ToBool(context, OOJS_ARGV[2])) < 0)) {
        OOJSReportBadArguments(context, @"setMultiFunctionText", @"reflow", argc, OOJS_ARGV, nil, @"boolean");
        return OOJSNativeFailure(context);
    }

    if (!reflow) {
        [player setMultiFunctionText:value forKey:key];
    } else {
        GuiDisplayGen* gui = [UNIVERSE gui];
        NSString* formatted = [gui reflowTextForMFD:value];
        [player setMultiFunctionText:formatted forKey:key];
    }

    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}

// setPrimedEquipment(key, [noMessage])
static JSValue PlayerShipSetPrimedEquipment(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    NSString* key = nil;
    PlayerEntity* player = OOPlayerForScripting();
    int showMsg = YES;

    if (argc > 0) {
        key = OOStringFromJSValue(context, OOJS_ARGV[0]);
    }
    if (key == nil) {
        OOJSReportBadArguments(context, @"PlayerShip", @"setPrimedEquipment", MIN(argc, 1), OOJS_ARGV, nil, @"string (key)");
        return OOJSNativeFailure(context);
    }
    if (argc > 1 && EXPECT_NOT((showMsg = JS_ToBool(context, OOJS_ARGV[1])) < 0)) {
        OOJSReportBadArguments(context, @"PlayerShip", @"setPrimedEquipment", MIN(argc, 2), OOJS_ARGV, nil, @"boolean");
        return OOJSNativeFailure(context);
    }

    OOJS_RETURN_BOOL([player setPrimedEquipment:key showMessage:showMsg]);

    OOJS_NATIVE_EXIT
}

// setCustomHUDDial(key,value)
static JSValue PlayerShipSetCustomHUDDial(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    NSString* key = nil;
    id value = nil;
    PlayerEntity* player = OOPlayerForScripting();

    if (argc > 0) {
        key = OOStringFromJSValue(context, OOJS_ARGV[0]);
    }
    if (key == nil) {
        OOJSReportBadArguments(context, @"PlayerShip", @"setCustomHUDDial", MIN(argc, 1), OOJS_ARGV, nil, @"string (key), value]");
        return OOJSNativeFailure(context);
    }
    if (argc > 1) {
        value = OOJSNativeObjectFromJSValue(context, OOJS_ARGV[1]);
    } else {
        value = @"";
    }

    [player setDialCustom:value forKey:key];

    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}

static JSValue PlayerShipHideHUDSelector(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    NSString* key = nil;
    PlayerEntity* player = OOPlayerForScripting();

    if (argc > 0) {
        key = OOStringFromJSValue(context, OOJS_ARGV[0]);
    }
    if (key == nil) {
        OOJSReportBadArguments(context, @"PlayerShip", @"hideHUDSelector", MIN(argc, 1), OOJS_ARGV, nil, @"string (selector)");
        return OOJSNativeFailure(context);
    }
    [[player hud] setHiddenSelector:key hidden:YES];

    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}

static JSValue PlayerShipShowHUDSelector(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    NSString* key = nil;
    PlayerEntity* player = OOPlayerForScripting();

    if (argc > 0) {
        key = OOStringFromJSValue(context, OOJS_ARGV[0]);
    }
    if (key == nil) {
        OOJSReportBadArguments(context, @"PlayerShip", @"hideHUDSelector", MIN(argc, 1), OOJS_ARGV, nil, @"string (selector)");
        return OOJSNativeFailure(context);
    }
    [[player hud] setHiddenSelector:key hidden:NO];

    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}

static BOOL ValidateContracts(JSContext* context, int argc, JSValueConst* argv, BOOL isCargo, OOSystemID* start, OOSystemID* destination, double* eta, double* fee, double* premium, NSString* functionName, unsigned* risk)
{
    OOJS_PROFILE_ENTER

    NSCParameterAssert(context != NULL && argv != NULL && start != NULL && destination != NULL && eta != NULL && fee != NULL);

    uint32_t uValue;
    int offset = isCargo ? 2 : 1;
    double fValue;
    int32_t iValue;

    if (!OOJSValueToInt32(context, argv[offset + 0], &iValue) || iValue < 0 || iValue > kOOMaximumSystemID) {
        OOJSReportBadArguments(context, @"PlayerShip", functionName, 1, &argv[offset + 0], nil, @"system ID");
        return NO;
    }
    *start = iValue;

    if (!OOJSValueToInt32(context, argv[offset + 1], &iValue) || iValue < 0 || iValue > kOOMaximumSystemID) {
        OOJSReportBadArguments(context, @"PlayerShip", functionName, 1, &argv[offset + 1], nil, @"system ID");
        return NO;
    }
    *destination = iValue;

    if (JS_ToFloat64(context, &fValue, argv[offset + 2]) != 0 || !isfinite(fValue) || fValue <= [PLAYER clockTime]) {
        OOJSReportBadArguments(context, @"PlayerShip", functionName, 1, &argv[offset + 2], nil, @"number (future time)");
        return NO;
    }
    *eta = fValue;

    if (JS_ToFloat64(context, &fValue, argv[offset + 3]) != 0 || !isfinite(fValue) || fValue < 0.0) {
        OOJSReportBadArguments(context, @"PlayerShip", functionName, 1, &argv[offset + 3], nil, @"number (credits quantity)");
        return NO;
    }
    *fee = fValue;

    // Optional arguments: as before, invalid values are ignored. Don't leave a conversion error pending.
    if (argc > offset + 4) {
        if (JS_ToFloat64(context, &fValue, argv[offset + 4]) != 0)
            JS_FreeValue(context, JS_GetException(context));
        else if (isfinite(fValue) && fValue >= 0.0)
            *premium = fValue;
    }

    if (!isCargo) {
        if (argc > offset + 5) {
            if (JS_ToUint32(context, &uValue, argv[offset + 5]) != 0)
                JS_FreeValue(context, JS_GetException(context));
            else
                *risk = uValue;
        }
    }

    return YES;

    OOJS_PROFILE_EXIT
}
