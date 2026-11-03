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

#include "OOJSPlayerShip.h"
#include "EntityOOJavaScriptExtensions.h"
#include "HeadUpDisplay.h"
#include "OOJSEntity.h"
#include "OOJSPlayer.h"
#include "OOJSQuaternion.h"
#include "OOJSShip.h"
#include "OOJSVector.h"
#include "OOJavaScriptEngine.h"
#include "OOSystemDescriptionManager.h"
#include "PlayerEntity.h"
#include "PlayerEntityContracts.h"
#include "PlayerEntityControls.h"
#include "PlayerEntityLegacyScriptEngine.h"
#include "PlayerEntityScriptMethods.h"
#include "PlayerEntitySound.h"
#include "StationEntity.h"

#include "GuiDisplayGen.h"
#include "OOConstToJSString.h"
#include "OOConstToString.h"
#include "OOEquipmentType.h"
#include "OOFunctionAttributes.h"
#include "OOJSEquipmentInfo.h"
#include "Universe.h"

#include "OOObjCPList.h"
#include "oofnd/Notification.hpp"
#include "oofnd/String.hpp"
#include "oofnd/objc/OOAssert.h"
#include "oofnd/objc/OOException.h"

static JSClassID sPlayerShipClassID;

static JSClassDef sPlayerShipClass = {
    .class_name = "PlayerShip",
    .finalizer = OOJSCxxObjectWrapperFinalize,
};

namespace {

    // A colour's components as its -normalizedArray gave them to JavaScript: floats, null for no colour.
    oo::PList NormalizedColorComponents(OOColor* color)
    {
        if (color == nullptr)
            return oo::PList();
        oo::PList::Array components;
        for (float component : color->normalizedArray())
            components.push_back(oo::PList::singleReal(component));
        return oo::PList(std::move(components));
    }

    /*	The player's HUD is converted (HeadUpDisplay), and the player answers its facade. A
            player with no HUD answered zero, false, nil or none to every message the getter sent the HUD;
            so does a null HUD here (ADR-0056 amendments oo-6ia4 item 2, oo-nge8 item 6).
    */
    template <typename R>
    R AskHud(PlayerEntity* player, R (HeadUpDisplay::*member)())
    {
        HeadUpDisplay* hud = (player != nullptr ? player->getHud() : (HeadUpDisplay*)nullptr);
        return (hud != nullptr) ? (hud->*member)() : R();
    }

    HeadUpDisplay* HudOf(PlayerEntity* player)
    {
        return (player != nullptr ? player->getHud() : (HeadUpDisplay*)nullptr);
    }

    oo::Ref<OOColor> HudReticleColor(PlayerEntity* player, NSUInteger idx)
    {
        HeadUpDisplay* hud = (player != nullptr ? player->getHud() : (HeadUpDisplay*)nullptr);
        return (hud != nullptr) ? hud->reticleColorForIndex(idx) : oo::Ref<OOColor>();
    }

    // A string, or null for none (what an NSString or nil gave JavaScript).
    oo::PList StringOrNull(const std::optional<std::string>& string)
    {
        return string.has_value() ? oo::PList(*string) : oo::PList();
    }

} // namespace

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

static bool ValidateContracts(JSContext* context, int argc, JSValueConst* argv, bool isCargo, OOSystemID* start, OOSystemID* destination, double* eta, double* fee, double* premium, const std::string& functionName, unsigned* risk);

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
    OOCAssert(JS_IsObject(shipPrototype), "Ship must be initialized before PlayerShip.");
    OOJSInitClass(context, global, sPlayerShipClassID, shipPrototype, OOJSUnconstructableConstruct, 0,
        sPlayerShipProperties, OOJS_COUNT(sPlayerShipProperties), sPlayerShipMethods, OOJS_COUNT(sPlayerShipMethods), NULL, 0);
    JS_FreeValue(context, shipPrototype);

    OOJSRegisterObjectConverter(sPlayerShipClassID, OOJSEntityObjectConverter);
    OOJSRegisterSubclass(sPlayerShipClassID, JSShipClassID());

    PlayerEntity* player = PlayerEntity::sharedPlayer(); // NOTE: at time of writing, this creates the player entity. Don't use PLAYER here.

    // Create ship object as a property of the player object.
    JSValue playerObject = JS_GetPropertyStr(context, global, "player");
    OOCAssert(JS_IsObject(playerObject), "Player must be initialized before PlayerShip.");

    JSValue shipObject = JS_NewObjectClass(context, (int)sPlayerShipClassID);
    // The slot holds a weak reference to the C++ player (the player's object's weak reference
    // before), as every entity's JS object's does.
    OOJSSetCxxPrivate(shipObject, oo::makeRef<OOJSEntityHolder>(player).get());
    // The player object's property and the player entity each own a reference.
    JS_DefinePropertyValueStr(context, playerObject, "ship", JS_DupValue(context, shipObject), OOJS_PROP_READONLY);
    OOJSPlayerShipSetJSSelf(player, shipObject, context); // -setJSSelf:context:, the category in this file

    JS_FreeValue(context, shipObject);
    JS_FreeValue(context, playerObject);
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

// PlayerEntity (OOJavaScriptExtensions): the bodies of the category's methods, which the engine
// and the player sent by selector; the C++ player calls them. Its JS class is JSPlayerShipClassID()
// (PlayerEntity::jsClassID()).
std::optional<std::string> OOJSPlayerShipJSClassName(void)
{
    return std::string("PlayerShip");
}

void OOJSPlayerShipSetJSSelf(PlayerEntity* player, JSValueConst val, JSContext* context)
{

    // Drop any previous wrapper (and its reset observer).
    player->deleteJSSelf();

    // Released by deleteJSSelf() when the JavaScript engine resets.
    player->_jsSelf = JS_DupValue(context, val);

    oo::NotificationCenter::defaultCenter().addObserver(player, kOOJavaScriptEngineWillResetNotificationName,
        OOJavaScriptEngine::sharedEngine(),
        [player](const oo::Notification&) { player->deleteJSSelf(); });
}

static JSValue PlayerShipGetProperty(OOJS_GETTER_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    /*	SpiderMonkey compared this with the prototype. The prototype (like any
            object that isn't player.ship, such as the this of a detached getter
            call) has no private weak reference to the player.
    */
    if (EXPECT_NOT(OOIsPlayerStale() || JS_GetOpaque(thisObj, sPlayerShipClassID) == NULL)) {
        return JS_UNDEFINED;
    }

    oo::PList result; // null maps to null
    PlayerEntity* player = OOPlayerForScripting();

    switch (magic) {
    case kPlayerShip_activeMissile:
        return JS_NewNumber(context, (player != nullptr ? player->getActiveMissile() : 0));

    case kPlayerShip_fuelLeakRate:
        return JS_NewNumber(context, (player != nullptr ? player->fuelLeakRate() : 0.0f));

    case kPlayerShip_docked:
        return OOJSValueFromBOOL(player != nullptr ? player->isDocked() : false);

    case kPlayerShip_dockedStation:
        result = oo::EntityObjectNode(player != nullptr ? player->dockedStation() : (StationEntity*)nullptr);
        break;

    case kPlayerShip_specialCargo:
        result = StringOrNull(player != nullptr ? player->getSpecialCargo() : std::optional<std::string>());
        break;

    case kPlayerShip_reticleColorTarget:
        result = NormalizedColorComponents(HudReticleColor(player, OO_RETICLE_COLOR_TARGET).get());
        break;

    case kPlayerShip_reticleColorTargetSensitive:
        result = NormalizedColorComponents(HudReticleColor(player, OO_RETICLE_COLOR_TARGET_SENSITIVE).get());
        break;

    case kPlayerShip_reticleColorWormhole:
        result = NormalizedColorComponents(HudReticleColor(player, OO_RETICLE_COLOR_WORMHOLE).get());
        break;

    case kPlayerShip_reticleTargetSensitive:
        return OOJSValueFromBOOL(AskHud(player, &HeadUpDisplay::getReticleTargetSensitive));

    case kPlayerShip_galacticHyperspaceBehaviour:
        return OOJSValueFromGalacticHyperspaceBehaviour(context, (player != nullptr ? player->getGalacticHyperspaceBehaviour() : OOGalacticHyperspaceBehaviour {}));

    case kPlayerShip_galacticHyperspaceFixedCoords:
        OOJS_RETURN_WITH_HELPER(NSPointToVectorJSValue, (player != nullptr ? player->getGalacticHyperspaceFixedCoords() : NSPoint {}));

    case kPlayerShip_galacticHyperspaceFixedCoordsInLY:
        OOJS_RETURN_VECTOR(OOGalacticCoordinatesFromInternal(player != nullptr ? player->getGalacticHyperspaceFixedCoords() : NSPoint {}));

    case kPlayerShip_fastEquipmentA:
        result = StringOrNull(player != nullptr ? player->fastEquipmentA() : std::optional<std::string>());
        break;

    case kPlayerShip_fastEquipmentB:
        result = StringOrNull(player != nullptr ? player->fastEquipmentB() : std::optional<std::string>());
        break;

    case kPlayerShip_primedEquipment:
        result = oo::PList(player != nullptr ? player->currentPrimedEquipment() : std::string());
        break;

    case kPlayerShip_forwardShield:
        return JS_NewNumber(context, (player != nullptr ? player->forwardShieldLevel() : 0.0f));

    case kPlayerShip_aftShield:
        return JS_NewNumber(context, (player != nullptr ? player->aftShieldLevel() : 0.0f));

    case kPlayerShip_maxForwardShield:
        return JS_NewNumber(context, (player != nullptr ? player->maxForwardShieldLevel() : 0.0f));

    case kPlayerShip_maxAftShield:
        return JS_NewNumber(context, (player != nullptr ? player->maxAftShieldLevel() : 0.0f));

    case kPlayerShip_forwardShieldRechargeRate:
        // No distinction made internally
        return JS_NewNumber(context, (player != nullptr ? player->forwardShieldRechargeRate() : 0.0f));

    case kPlayerShip_aftShieldRechargeRate:
        // No distinction made internally
        return JS_NewNumber(context, (player != nullptr ? player->aftShieldRechargeRate() : 0.0f));

    case kPlayerShip_multiFunctionDisplays:
        return JS_NewNumber(context, AskHud(player, &HeadUpDisplay::mfdCount));

    case kPlayerShip_multiFunctionDisplayList: {
        oo::PList::Array list; // [OONull null] for an inactive MFD
        for (const std::optional<std::string>& key : (player != nullptr ? player->multiFunctionDisplayList() : std::vector<std::optional<std::string>>())) {
            list.push_back(key.has_value() ? oo::PList(*key) : OONullObjectNode());
        }
        result = oo::PList(std::move(list));
    } break;

    case kPlayerShip_missilesOnline:
        return OOJSValueFromBOOL(!(player != nullptr ? player->dialIdentEngaged() : false));

    case kPlayerShip_chartHightlightMode:
        result = oo::PList(cxx_OOStringFromLongRangeChartMode(player != nullptr ? player->getLongRangeChartMode() : OOLongRangeChartMode { }));
        break;

    case kPlayerShip_galaxyCoordinates:
        OOJS_RETURN_WITH_HELPER(NSPointToVectorJSValue, (player != nullptr ? player->getGalaxy_coordinates() : NSPoint {}));

    case kPlayerShip_galaxyCoordinatesInLY:
        OOJS_RETURN_VECTOR(OOGalacticCoordinatesFromInternal(player != nullptr ? player->getGalaxy_coordinates() : NSPoint {}));

    case kPlayerShip_cursorCoordinates:
        OOJS_RETURN_WITH_HELPER(NSPointToVectorJSValue, (player != nullptr ? player->getCursor_coordinates() : NSPoint {}));

    case kPlayerShip_cursorCoordinatesInLY:
        OOJS_RETURN_VECTOR(OOGalacticCoordinatesFromInternal(player != nullptr ? player->getCursor_coordinates() : NSPoint {}));

    case kPlayerShip_targetSystem:
        return JS_NewInt32(context, player != nullptr ? player->targetSystemID() : 0);

    case kPlayerShip_nextSystem:
        return JS_NewInt32(context, player != nullptr ? player->nextHopTargetSystemID() : 0);

    case kPlayerShip_infoSystem:
        return JS_NewInt32(context, player != nullptr ? player->infoSystemID() : 0);

    case kPlayerShip_previousSystem:
        return JS_NewInt32(context, player != nullptr ? player->previousSystemID() : 0);

    case kPlayerShip_routeMode: {
        OORouteType route = (player != nullptr ? player->ANAMode() : OORouteType { });
        switch (route) {
        case OPTIMIZED_BY_TIME:
            result = oo::PList("OPTIMIZED_BY_TIME");
            break;
        case OPTIMIZED_BY_JUMPS:
            result = oo::PList("OPTIMIZED_BY_JUMPS");
            break;
        case OPTIMIZED_BY_NONE:
            result = oo::PList("OPTIMIZED_BY_NONE");
            break;
        }
        break;
    }

    case kPlayerShip_scannerMinimalistic:
        return OOJSValueFromBOOL(AskHud(player, &HeadUpDisplay::minimalisticScanner));

    case kPlayerShip_scannerNonLinear:
        return OOJSValueFromBOOL(AskHud(player, &HeadUpDisplay::nonlinearScanner));

    case kPlayerShip_scannerUltraZoom:
        return OOJSValueFromBOOL(AskHud(player, &HeadUpDisplay::scannerUltraZoom));

    case kPlayerShip_scoopOverride:
        return OOJSValueFromBOOL(player != nullptr ? player->getScoopOverride() : false);

    case kPlayerShip_injectorsEngaged:
        return OOJSValueFromBOOL(player != nullptr ? player->injectorsEngaged() : false);

    case kPlayerShip_massLockable:
        return OOJSValueFromBOOL(player != nullptr ? player->getMassLockable() : false);

    case kPlayerShip_torusEngaged:
        return OOJSValueFromBOOL(player != nullptr ? player->hyperspeedEngaged() : false);

    case kPlayerShip_compassTarget:
        result = oo::EntityObjectNode(player != nullptr ? player->getCompassTargetEntity() : (Entity*)nullptr); // the C++ entity's node, the same object's
        break;

    case kPlayerShip_compassType:
        result = oo::PList((cxx_OOStringFromCompassMode(player != nullptr ? player->getCompassMode() : OOCompassMode { }) == "COMPASS_MODE_BASIC") ? "OO_COMPASSTYPE_BASIC" : "OO_COMPASSTYPE_ADVANCED");
        break;

    case kPlayerShip_compassMode:
        return OOJSValueFromCompassMode(context, (player != nullptr ? player->getCompassMode() : OOCompassMode {}));

    case kPlayerShip_hud:
        result = StringOrNull(AskHud(player, &HeadUpDisplay::getHudName));
        break;

    case kPlayerShip_crosshairs:
        result = StringOrNull(AskHud(player, &HeadUpDisplay::getCrosshairDefinition));
        break;

    case kPlayerShip_hudAllowsBigGui:
        return OOJSValueFromBOOL(AskHud(player, &HeadUpDisplay::getAllowBigGui));

    case kPlayerShip_hudHidden:
        return OOJSValueFromBOOL(AskHud(player, &HeadUpDisplay::isHidden));

    case kPlayerShip_weaponsOnline:
        return OOJSValueFromBOOL(player != nullptr ? player->weaponsOnline() : false);

    case kPlayerShip_viewDirection:
        return OOJSValueFromViewID(context, (UNIVERSE != nullptr ? UNIVERSE->getViewDirection() : OOViewID { }));

    case kPlayerShip_viewPositionAft:
        OOJS_RETURN_VECTOR((player != nullptr ? player->viewpointOffsetAft() : Vector {}));

    case kPlayerShip_viewPositionForward:
        OOJS_RETURN_VECTOR((player != nullptr ? player->viewpointOffsetForward() : Vector {}));

    case kPlayerShip_viewPositionPort:
        OOJS_RETURN_VECTOR((player != nullptr ? player->viewpointOffsetPort() : Vector {}));

    case kPlayerShip_viewPositionStarboard:
        OOJS_RETURN_VECTOR((player != nullptr ? player->viewpointOffsetStarboard() : Vector {}));

    case kPlayerShip_currentWeapon:
        result = OOEquipmentTypeObjectNode(player != nullptr ? player->weaponTypeForFacing((player != nullptr ? player->getCurrentWeaponFacing() : OOWeaponFacing { }), false) : (OOEquipmentType*)nullptr);
        break;

    case kPlayerShip_price:
        return JS_NewNumber(context, (UNIVERSE != nullptr ? UNIVERSE->tradeInValueForCommanderDictionary((player != nullptr ? player->commanderDataDictionary() : oo::PList())) : 0));

    case kPlayerShip_serviceLevel:
        return JS_NewNumber(context, (player != nullptr ? player->tradeInFactor() : int {}));

    case kPlayerShip_renovationCost:
        return JS_NewNumber(context, (player != nullptr ? player->renovationCosts() : 0.0));

    case kPlayerShip_renovationMultiplier:
        return JS_NewNumber(context, (player != nullptr ? player->renovationFactor() : 0.0));

        // make roll, pitch, yaw reported to JS use same +/- convention as
        // for NPC ships
    case kPlayerShip_pitch:
        return JS_NewNumber(context, -(player != nullptr ? player->getFlightPitch() : 0.0f));

    case kPlayerShip_roll:
        return JS_NewNumber(context, -(player != nullptr ? player->getFlightRoll() : 0.0f));

    case kPlayerShip_yaw:
        return JS_NewNumber(context, -(player != nullptr ? player->getFlightYaw() : 0.0f));

    case kPlayerShip_messageGuiTextColor:
        result = NormalizedColorComponents(UNIVERSE->messageGUI()->getTextColor());
        break;

    case kPlayerShip_messageGuiTextCommsColor:
        result = NormalizedColorComponents(UNIVERSE->messageGUI()->getTextCommsColor());
        break;

    default:
        OOJSReportBadPropertySelector(context, thisObj, magic, sPlayerShipProperties, OOJS_COUNT(sPlayerShipProperties));
        return OOJSNativeFailure(context);
    }

    return OOJSValueFromPList(context, result);

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
    std::optional<std::string> sValue;
    OOGalacticHyperspaceBehaviour ghBehaviour;
    Vector vValue;
    oo::Ref<OOColor> colorForScript; // the colours are converted (OOColor)
    Entity* eValue = nullptr; // as JSValueToEntity() answers (the C++ entity)

    switch (magic) {
    case kPlayerShip_fuelLeakRate:
        if (JS_ToFloat64(context, &fValue, value) == 0) {
            if (player != nullptr)
                player->setFuelLeakRate(fValue);
            return JS_UNDEFINED;
        }
        break;

    case kPlayerShip_massLockable:
        if ((bValue = JS_ToBool(context, value)) >= 0) {
            if (player != nullptr)
                player->setMassLockable(bValue);
            return JS_UNDEFINED;
        }
        break;

    case kPlayerShip_reticleTargetSensitive:
        if ((bValue = JS_ToBool(context, value)) >= 0) {
            if (HeadUpDisplay* hud = HudOf(player))
                hud->setReticleTargetSensitive(bValue);
            return JS_UNDEFINED;
        }
        break;

    case kPlayerShip_chartHightlightMode:
        sValue = cxx_OOStringFromJSValue(context, value);
        if (sValue.has_value()) {
            OOLongRangeChartMode chartMode = cxx_OOLongRangeChartModeFromString(sValue.value_or(""));
            if (chartMode > OOLRC_MODE_UNKNOWN) {
                if (player != nullptr)
                    player->setLongRangeChartMode(chartMode);
                if (player != nullptr)
                    player->doScriptEvent(OOJSID("chartHighlightModeChanged"), { oo::PList(cxx_OOStringFromLongRangeChartMode(player != nullptr ? player->getLongRangeChartMode() : OOLongRangeChartMode {})) });
                return JS_UNDEFINED;
            } else {
                cxx_OOJSReportError(context, "Unknown chart hightlight mode specified - must be either OOLRC_MODE_SUNCOLOR, OOLRC_MODE_ECONOMY, OOLRC_MODE_GOVERNMENT or OOLRC_MODE_TECHLEVEL.");
            }
        }
        return OOJSNativeFailure(context); // not reachable if successfully set
        break;

    case kPlayerShip_compassMode:
        sValue = cxx_OOStringFromJSValue(context, value);
        if (sValue.has_value()) {
            OOCompassMode mode = OOCompassModeFromJSValue(context, value);
            if (player != nullptr)
                player->setCompassMode(mode);
            if (player != nullptr)
                player->validateCompassTarget();
            return JS_UNDEFINED;
        }
        break;

    case kPlayerShip_compassType:
        sValue = cxx_OOStringFromJSValue(context, value);
        if (sValue.has_value()) {
            if (*sValue == "OO_COMPASSTYPE_BASIC") {
                if (player != nullptr)
                    player->setCompassMode(COMPASS_MODE_BASIC);
            } else if (*sValue == "OO_COMPASSTYPE_ADVANCED") {
                if (!(player != nullptr ? player->hasEquipmentItemProviding("EQ_ADVANCED_COMPASS") : false)) {
                    cxx_OOJSReportWarning(context, "Advanced Compass type requested and set but player ship does not carry the EQ_ADVANCED_COMPASS equipment or has it damaged.");
                }
                if (player != nullptr)
                    player->setCompassMode(COMPASS_MODE_PLANET);
            } else {
                cxx_OOJSReportError(context, "Unknown compass type specified - must be either OO_COMPASSTYPE_BASIC or OO_COMPASSTYPE_ADVANCED.");
                return OOJSNativeFailure(context);
            }
            return JS_UNDEFINED;
        }
        break;

    case kPlayerShip_compassTarget:
        // can't change compass target in basic mode
        if (!(player != nullptr ? player->hasEquipmentItemProviding("EQ_ADVANCED_COMPASS") : false)) {
            cxx_OOJSReportError(context, "Compass target cannot be set with a basic compass.");
            return OOJSNativeFailure(context);
        }
        // make sure we have a valid entity
        if (!JS_IsNull(value) && JSValueToEntity(context, value, &eValue)) {
            Entity* current = (player != nullptr ? player->getCompassTargetEntity() : nullptr); // the C++ entities
            if (player != nullptr)
                player->setNextCompassMode();
            if (player != nullptr)
                player->validateCompassTarget();
            // cycle the targets until we either get back to the start (entity not found) or we find the one we're looking for
            while ((player != nullptr ? player->getCompassTargetEntity() : nullptr) != current && (player != nullptr ? player->getCompassTargetEntity() : nullptr) != eValue) // the C++ entities
            {
                if (player != nullptr)
                    player->setNextCompassMode();
                if (player != nullptr)
                    player->validateCompassTarget();
            }
            // SpiderMonkey returned NO (stopping the script without an error) if the target wasn't found.
            if ((player != nullptr ? player->getCompassTargetEntity() : nullptr) == current)
                return OOJSNativeFailure(context);
            return JS_UNDEFINED;
        } else {
            cxx_OOJSReportError(context, "Invalid compass target entity provided.");
            return OOJSNativeFailure(context);
        }
        break;

    case kPlayerShip_galacticHyperspaceBehaviour:
        ghBehaviour = OOGalacticHyperspaceBehaviourFromJSValue(context, value);
        if (ghBehaviour != GALACTIC_HYPERSPACE_BEHAVIOUR_UNKNOWN) {
            if (player != nullptr)
                player->setGalacticHyperspaceBehaviour(ghBehaviour);
            return JS_UNDEFINED;
        }
        break;

    case kPlayerShip_galacticHyperspaceFixedCoords:
        if (JSValueToVector(context, value, &vValue)) {
            NSPoint coords = { vValue.x, vValue.y };
            if (player != nullptr)
                player->setGalacticHyperspaceFixedCoords(coords);
            return JS_UNDEFINED;
        }
        break;

    case kPlayerShip_galacticHyperspaceFixedCoordsInLY:
        if (JSValueToVector(context, value, &vValue)) {
            NSPoint coords = OOInternalCoordinatesFromGalactic(vValue);
            if (player != nullptr)
                player->setGalacticHyperspaceFixedCoords(coords);
            return JS_UNDEFINED;
        }
        break;

    case kPlayerShip_fastEquipmentA:
        sValue = cxx_OOStringFromJSValue(context, value);
        if (sValue.has_value()) {
            if (player != nullptr)
                player->setFastEquipmentA(sValue);
            return JS_UNDEFINED;
        }
        break;

    case kPlayerShip_fastEquipmentB:
        sValue = cxx_OOStringFromJSValue(context, value);
        if (sValue.has_value()) {
            if (player != nullptr)
                player->setFastEquipmentB(sValue);
            return JS_UNDEFINED;
        }
        break;

    case kPlayerShip_primedEquipment:
        sValue = cxx_OOStringFromJSValue(context, value);
        if (sValue.has_value()) {
            // As before, failure stops the script without an error.
            if (!(player != nullptr ? player->setPrimedEquipment(*sValue, false) : false))
                return OOJSNativeFailure(context);
            return JS_UNDEFINED;
        }
        break;

    case kPlayerShip_pitch:
        if (JS_ToFloat64(context, &fValue, value) == 0) {
            if (!isnan(fValue)) // guard against undefined
            {
                if (player != nullptr)
                    player->decrease_flight_pitch(((player != nullptr ? player->getFlightPitch() : 0.0f) + fValue));
            }
            return JS_UNDEFINED;
        }
        break;

    case kPlayerShip_roll:
        if (JS_ToFloat64(context, &fValue, value) == 0) {
            if (!isnan(fValue)) // guard against undefined
            {
                if (player != nullptr)
                    player->decrease_flight_roll(((player != nullptr ? player->getFlightRoll() : 0.0f) + fValue));
            }
            return JS_UNDEFINED;
        }
        break;

    case kPlayerShip_yaw:
        if (JS_ToFloat64(context, &fValue, value) == 0) {
            if (!isnan(fValue)) // guard against undefined
            {
                if (player != nullptr)
                    player->decrease_flight_yaw(((player != nullptr ? player->getFlightYaw() : 0.0f) + fValue));
            }
            return JS_UNDEFINED;
        }
        break;

    case kPlayerShip_forwardShield:
        if (JS_ToFloat64(context, &fValue, value) == 0) {
            if (player != nullptr)
                player->setForwardShieldLevel(fValue);
            return JS_UNDEFINED;
        }
        break;

    case kPlayerShip_aftShield:
        if (JS_ToFloat64(context, &fValue, value) == 0) {
            if (player != nullptr)
                player->setAftShieldLevel(fValue);
            return JS_UNDEFINED;
        }
        break;

    case kPlayerShip_maxForwardShield:
        if (JS_ToFloat64(context, &fValue, value) == 0) {
            if (player != nullptr)
                player->setMaxForwardShieldLevel(fValue);
            return JS_UNDEFINED;
        }
        break;

    case kPlayerShip_maxAftShield:
        if (JS_ToFloat64(context, &fValue, value) == 0) {
            if (player != nullptr)
                player->setMaxAftShieldLevel(fValue);
            return JS_UNDEFINED;
        }
        break;

    case kPlayerShip_forwardShieldRechargeRate:
        if (JS_ToFloat64(context, &fValue, value) == 0) {
            if (player != nullptr)
                player->setForwardShieldRechargeRate(fValue);
            return JS_UNDEFINED;
        }
        break;

    case kPlayerShip_aftShieldRechargeRate:
        if (JS_ToFloat64(context, &fValue, value) == 0) {
            if (player != nullptr)
                player->setAftShieldRechargeRate(fValue);
            return JS_UNDEFINED;
        }
        break;

    case kPlayerShip_scannerMinimalistic:
        if ((bValue = JS_ToBool(context, value)) >= 0) {
            if (HeadUpDisplay* hud = HudOf(player))
                hud->setMinimalisticScanner(bValue);
            return JS_UNDEFINED;
        }
        break;

    case kPlayerShip_scannerNonLinear:
        if ((bValue = JS_ToBool(context, value)) >= 0) {
            if (HeadUpDisplay* hud = HudOf(player))
                hud->setNonlinearScanner(bValue);
            return JS_UNDEFINED;
        }
        break;

    case kPlayerShip_scannerUltraZoom:
        if ((bValue = JS_ToBool(context, value)) >= 0) {
            if (HeadUpDisplay* hud = HudOf(player))
                hud->setScannerUltraZoom(bValue);
            return JS_UNDEFINED;
        }
        break;

    case kPlayerShip_scoopOverride:
        if ((bValue = JS_ToBool(context, value)) >= 0) {
            if (player != nullptr)
                player->setScoopOverride(bValue);
            return JS_UNDEFINED;
        }
        break;

    case kPlayerShip_hud:
        sValue = cxx_OOStringFromJSValue(context, value);
        if (sValue.has_value()) {
            if (sValue.has_value() && player != nullptr)
                player->switchHudTo(*sValue); // EMMSTRAN: logged error should be a JS warning.
            return JS_UNDEFINED;
        } else {
            if (player != nullptr)
                player->resetHud();
            return JS_UNDEFINED;
        }
        break;

    case kPlayerShip_crosshairs:
        sValue = cxx_OOStringFromJSValue(context, value);
        if (!sValue.has_value()) {
            // reset HUD back to its plist settings
            std::optional<std::string> hud = AskHud(player, &HeadUpDisplay::getHudName); // a copy, as the retain kept it
            if (hud.has_value() && player != nullptr)
                player->switchHudTo(*hud);
            return JS_UNDEFINED;
        } else {
            if (!(HudOf(player) != nullptr && HudOf(player)->setCrosshairDefinition(sValue.value_or("")))) {
                cxx_OOJSReportWarning(context, "Crosshair definition file %s not found or invalid", (sValue ? sValue->c_str() : "(null)"));
            }
            return JS_UNDEFINED;
        }
        break;

    case kPlayerShip_hudHidden:
        if ((bValue = JS_ToBool(context, value)) >= 0) {
            if (HeadUpDisplay* hud = HudOf(player))
                hud->setHidden(bValue);
            return JS_UNDEFINED;
        }
        break;

    case kPlayerShip_serviceLevel:
        if (JS_ToFloat64(context, &fValue, value) == 0) {
            int newLevel = (int)fValue;
            if (player != nullptr)
                player->adjustTradeInFactorBy((newLevel - (player != nullptr ? player->tradeInFactor() : int {})));
            return JS_UNDEFINED;
        }
        /*	The SpiderMonkey version fell through to currentWeapon here (which
                removed the current weapon) if the conversion threw. Report the bad
                value instead.
        */
        break;

    case kPlayerShip_currentWeapon: {
        BOOL exists = NO; // JSValueToEquipmentKeyRelaxed() takes a BOOL * (amendment oo-nge8 item 1)
        sValue = JSValueToEquipmentKeyRelaxed(context, value, &exists);
        if (!exists || !sValue.has_value()) {
            sValue = "EQ_WEAPON_NONE";
        }
        if (player != nullptr)
            player->setWeaponMount(player->getCurrentWeaponFacing(), sValue.value_or(""), "scripted");
        return JS_UNDEFINED;
    }

    case kPlayerShip_targetSystem:
        /* This first check is essential: if removed, it would be
         * possible to make jumps of arbitrary length - CIM */
        if ((player != nullptr ? player->status() : OOEntityStatus { }) != STATUS_ENTERING_WITCHSPACE) {
            /* These checks though similar are less important. The
             * consequences of allowing jump destination to be set in
             * flight are not as severe and do not allow the 7LY limit to
             * be broken. Nevertheless, it is not allowed. - CIM */
            // (except when compiled in debugging mode)
#ifndef OO_DUMP_PLANETINFO
            if (EXPECT_NOT((player != nullptr ? player->status() : OOEntityStatus { }) != STATUS_DOCKED && (player != nullptr ? player->status() : OOEntityStatus { }) != STATUS_LAUNCHING)) {
                cxx_OOJSReportError(context, "player.ship.targetSystem is read-only unless called when docked.");
                return OOJSNativeFailure(context);
            }
#endif

            if (OOJSValueToInt32(context, value, &iValue)) {
                if (iValue >= 0 && iValue < OO_SYSTEMS_PER_GALAXY) {
                    if (player != nullptr)
                        player->setTargetSystemID(iValue);
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
            cxx_OOJSReportError(context, "player.ship.targetSystem is read-only unless called when docked.");
            return OOJSNativeFailure(context);
        }

    case kPlayerShip_infoSystem:
        if (OOJSValueToInt32(context, value, &iValue)) {
            if (iValue >= 0 && iValue < OO_SYSTEMS_PER_GALAXY) {
                if (player != nullptr)
                    player->setInfoSystemID(iValue, true);
                return JS_UNDEFINED;
            } else {
                return OOJSNativeFailure(context);
            }
        }
        break;

    case kPlayerShip_messageGuiTextColor:
        colorForScript = OOColor::colorWithDescription(cxx_OOJSPListFromJSValue(context, value));
        if (colorForScript != nullptr || JS_IsNull(value)) {
            UNIVERSE->messageGUI()->setTextColor(colorForScript.get());
            return JS_UNDEFINED;
        }
        break;

    case kPlayerShip_messageGuiTextCommsColor:
        colorForScript = OOColor::colorWithDescription(cxx_OOJSPListFromJSValue(context, value));
        if (colorForScript != nullptr || JS_IsNull(value)) {
            UNIVERSE->messageGUI()->setTextCommsColor(colorForScript.get());
            return JS_UNDEFINED;
        }
        break;

    case kPlayerShip_reticleColorTarget:
        colorForScript = OOColor::colorWithDescription(cxx_OOJSPListFromJSValue(context, value));
        if (colorForScript != nullptr || JS_IsNull(value)) {
            if (!(HudOf(player) != nullptr && HudOf(player)->setReticleColorForIndex(OO_RETICLE_COLOR_TARGET, colorForScript.get())))
                return OOJSNativeFailure(context);
            return JS_UNDEFINED;
        }
        break;

    case kPlayerShip_reticleColorTargetSensitive:
        colorForScript = OOColor::colorWithDescription(cxx_OOJSPListFromJSValue(context, value));
        if (colorForScript != nullptr || JS_IsNull(value)) {
            if (!(HudOf(player) != nullptr && HudOf(player)->setReticleColorForIndex(OO_RETICLE_COLOR_TARGET_SENSITIVE, colorForScript.get())))
                return OOJSNativeFailure(context);
            return JS_UNDEFINED;
        }
        break;

    case kPlayerShip_reticleColorWormhole:
        colorForScript = OOColor::colorWithDescription(cxx_OOJSPListFromJSValue(context, value));
        if (colorForScript != nullptr || JS_IsNull(value)) {
            if (!(HudOf(player) != nullptr && HudOf(player)->setReticleColorForIndex(OO_RETICLE_COLOR_WORMHOLE, colorForScript.get())))
                return OOJSNativeFailure(context);
            return JS_UNDEFINED;
        }
        break;

    default:
        OOJSReportBadPropertySelector(context, thisObj, magic, sPlayerShipProperties, OOJS_COUNT(sPlayerShipProperties));
        return OOJSNativeFailure(context);
    }

    OOJSReportBadPropertyValue(context, thisObj, magic, sPlayerShipProperties, OOJS_COUNT(sPlayerShipProperties), value);
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

    if (PlayerEntity* player = OOPlayerForScripting())
        player->launchFromStation();
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

    if ((player != nullptr ? player->isDocked() : false)) {
        if (player != nullptr)
            player->removeAllCargo();
        OOJS_RETURN_VOID;
    } else {
        cxx_OOJSReportError(context, "PlayerShip.removeAllCargo only works when docked.");
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
    std::optional<std::string> name;

    if (argc > 0)
        name = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
    if (EXPECT_NOT(!name.has_value())) {
        cxx_OOJSReportBadArguments(context, "PlayerShip", "useSpecialCargo", MIN(argc, 1), OOJS_ARGV, std::nullopt, "string (special cargo description)");
        return OOJSNativeFailure(context);
    }

    if (player != nullptr)
        player->useSpecialCargo(cxx_OOStringFromJSValue(context, OOJS_ARGV[0]).value_or(std::string())); // (nil was "")
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
        stationForDocking = oo::ToStation(OOJSEntityFromJSValue(context, OOJS_ARGV[0])); // a station's object is a ship's
    if (stationForDocking == nil) {
        cxx_OOJSReportBadArguments(context, "PlayerShip", "engageAutopilot", MIN(argc, 1), OOJS_ARGV, std::nullopt, "station");
        return OOJSNativeFailure(context);
    }

    OOJS_RETURN_BOOL(player != nullptr ? player->engageAutopilotToStation(stationForDocking) : false);

    OOJS_NATIVE_EXIT
}

// disengageAutopilot()
static JSValue PlayerShipDisengageAutopilot(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    if (EXPECT_NOT(OOIsPlayerStale()))
        OOJS_RETURN_VOID;

    if (PlayerEntity* player = OOPlayerForScripting())
        player->disengageAutopilot();
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
        stationForDocking = oo::ToStation(OOJSEntityFromJSValue(context, OOJS_ARGV[0])); // a station's object is a ship's
    if (stationForDocking == nil) {
        cxx_OOJSReportBadArguments(context, "PlayerShip", "requestDockingClearance", MIN(argc, 1), OOJS_ARGV, std::nullopt, "station");
        return OOJSNativeFailure(context);
    }

    if (player != nullptr)
        player->requestDockingClearance(stationForDocking);
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
        stationForDocking = oo::ToStation(OOJSEntityFromJSValue(context, OOJS_ARGV[0])); // a station's object is a ship's
    if (stationForDocking == nil) {
        cxx_OOJSReportBadArguments(context, "PlayerShip", "cancelDockingRequest", MIN(argc, 1), OOJS_ARGV, std::nullopt, "station");
        return OOJSNativeFailure(context);
    }

    if (player != nullptr)
        player->cancelDockingRequest(stationForDocking);
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
    std::optional<std::string> key;
    oo::Ref<OOEquipmentType> eqType; // the equipment types are converted (OOEquipmentType)

    if (argc > 0)
        key = JSValueToEquipmentKey(context, OOJS_ARGV[0]);
    if (key.has_value())
        eqType = OOEquipmentType::equipmentTypeWithIdentifier(*key);
    if (EXPECT_NOT(!(eqType != nullptr && eqType->isMissileOrMine()))) {
        cxx_OOJSReportBadArguments(context, "PlayerShip", "awardEquipmentToCurrentPylon", MIN(argc, 1), OOJS_ARGV, std::nullopt, "equipment type (external store)");
        return OOJSNativeFailure(context);
    }

    OOJS_RETURN_BOOL(player != nullptr ? player->assignToActivePylon(key.value_or("")) : false);

    OOJS_NATIVE_EXIT
}

// addPassenger(name: string, start: int, destination: int, ETA: double, fee: double) : Boolean
static JSValue PlayerShipAddPassenger(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    PlayerEntity* player = OOPlayerForScripting();
    std::optional<std::string> name;
    OOSystemID start = 0, destination = 0;
    double eta = 0.0, fee = 0.0, advance = 0.0;
    unsigned risk = 0;

    if (argc < 5) {
        cxx_OOJSReportBadArguments(context, "PlayerShip", "addPassenger", argc, OOJS_ARGV, std::nullopt, "name, start, destination, ETA, fee");
        return OOJSNativeFailure(context);
    }

    name = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
    if (EXPECT_NOT(!name.has_value())) {
        cxx_OOJSReportBadArguments(context, "PlayerShip", "addPassenger", 1, &OOJS_ARGV[0], std::nullopt, "string");
        return OOJSNativeFailure(context);
    }

    if (!ValidateContracts(context, argc, OOJS_ARGV, false, &start, &destination, &eta, &fee, &advance, "addPassenger", &risk))
        return OOJSNativeFailure(context); // always go through validate contracts (passenger)

    // Ensure there's space.
    if ((player != nullptr ? player->passengerCount() : 0) >= (player != nullptr ? player->passengerCapacity() : 0))
        OOJS_RETURN_BOOL(false);

    bool OK = (player != nullptr ? player->addPassenger(name.value_or(""), start, destination, eta, fee, advance, risk) : false);
    OOJS_RETURN_BOOL(OK);

    OOJS_NATIVE_EXIT
}

// removePassenger(name :string)
static JSValue PlayerShipRemovePassenger(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    PlayerEntity* player = OOPlayerForScripting();
    std::optional<std::string> name;
    bool OK = true;

    if (argc > 0)
        name = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
    if (EXPECT_NOT(!name.has_value())) {
        cxx_OOJSReportBadArguments(context, "PlayerShip", "removePassenger", MIN(argc, 1), OOJS_ARGV, std::nullopt, "string");
        return OOJSNativeFailure(context);
    }

    OK = (player != nullptr ? player->passengerCount() : 0) > 0 && !name->empty();
    if (OK)
        OK = (player != nullptr ? player->removePassenger(name.value_or("")) : false);

    OOJS_RETURN_BOOL(OK);

    OOJS_NATIVE_EXIT
}

// addParcel(description: string, start: int, destination: int, ETA: double, fee: double) : Boolean
static JSValue PlayerShipAddParcel(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    PlayerEntity* player = OOPlayerForScripting();
    std::optional<std::string> name;
    OOSystemID start = 0, destination = 0;
    double eta = 0.0, fee = 0.0, premium = 0.0;
    unsigned risk = 0;

    if (argc < 5) {
        cxx_OOJSReportBadArguments(context, "PlayerShip", "addParcel", argc, OOJS_ARGV, std::nullopt, "name, start, destination, ETA, fee");
        return OOJSNativeFailure(context);
    }

    name = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
    if (EXPECT_NOT(!name.has_value())) {
        cxx_OOJSReportBadArguments(context, "PlayerShip", "addParcel", 1, &OOJS_ARGV[0], std::nullopt, "string");
        return OOJSNativeFailure(context);
    }

    if (!ValidateContracts(context, argc, OOJS_ARGV, false, &start, &destination, &eta, &fee, &premium, "addParcel", &risk))
        return OOJSNativeFailure(context); // always go through validate contracts (passenger/parcel mode)

    // Ensure there's space.

    bool OK = (player != nullptr ? player->addParcel(name.value_or(""), start, destination, eta, fee, premium, risk) : false);
    OOJS_RETURN_BOOL(OK);

    OOJS_NATIVE_EXIT
}

// removeParcel(description :string)
static JSValue PlayerShipRemoveParcel(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    PlayerEntity* player = OOPlayerForScripting();
    std::optional<std::string> name;
    bool OK = true;

    if (argc > 0)
        name = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
    if (EXPECT_NOT(!name.has_value())) {
        cxx_OOJSReportBadArguments(context, "PlayerShip", "removeParcel", MIN(argc, 1), OOJS_ARGV, std::nullopt, "string");
        return OOJSNativeFailure(context);
    }

    OK = (player != nullptr ? player->parcelCount() : 0) > 0 && !name->empty();
    if (OK)
        OK = (player != nullptr ? player->removeParcel(name.value_or("")) : false);

    OOJS_RETURN_BOOL(OK);

    OOJS_NATIVE_EXIT
}

// awardContract(quantity: int, commodity: string, start: int, destination: int, eta: double, fee: double) : Boolean
static JSValue PlayerShipAwardContract(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    PlayerEntity* player = OOPlayerForScripting();
    std::optional<std::string> key;
    int32_t qty = 0;
    OOSystemID start = 0, destination = 0;
    double eta = 0.0, fee = 0.0, premium = 0.0;

    if (argc < 6) {
        cxx_OOJSReportBadArguments(context, "PlayerShip", "awardContract", argc, OOJS_ARGV, std::nullopt, "quantity, commodity, start, destination, ETA, fee");
        return OOJSNativeFailure(context);
    }

    if (!OOJSValueToInt32(context, OOJS_ARGV[0], &qty)) {
        cxx_OOJSReportBadArguments(context, "PlayerShip", "awardContract", 1, &OOJS_ARGV[0], std::nullopt, "positive integer (cargo quantity)");
        return OOJSNativeFailure(context);
    }

    key = cxx_OOStringFromJSValue(context, OOJS_ARGV[1]);
    if (EXPECT_NOT(!key.has_value())) {
        cxx_OOJSReportBadArguments(context, "PlayerShip", "awardContract", 1, &OOJS_ARGV[1], std::nullopt, "string (commodity identifier)");
        return OOJSNativeFailure(context);
    }

    if (!ValidateContracts(context, argc, OOJS_ARGV, true, &start, &destination, &eta, &fee, &premium, "awardContract", NULL))
        return OOJSNativeFailure(context); // always go through validate contracts (cargo)

    bool OK = (player != nullptr ? player->awardContract(qty, key.value_or(""), start, destination, eta, fee, premium) : false);
    OOJS_RETURN_BOOL(OK);

    OOJS_NATIVE_EXIT
}

// removeContract(commodity: string, destination: int)
static JSValue PlayerShipRemoveContract(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    PlayerEntity* player = OOPlayerForScripting();
    std::optional<std::string> key;
    int32_t dest = 0;

    if (argc < 2) {
        cxx_OOJSReportBadArguments(context, "PlayerShip", "removeContract", argc, OOJS_ARGV, std::nullopt, "commodity, destination");
        return OOJSNativeFailure(context);
    }

    key = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);

    if (EXPECT_NOT(!key.has_value())) {
        cxx_OOJSReportBadArguments(context, "PlayerShip", "removeContract", 1, &OOJS_ARGV[0], std::nullopt, "string (commodity identifier)");
        return OOJSNativeFailure(context);
    }

    if (!OOJSValueToInt32(context, OOJS_ARGV[1], &dest) || dest < 0 || dest > 255) {
        cxx_OOJSReportBadArguments(context, "PlayerShip", "removeContract", 1, &OOJS_ARGV[1], std::nullopt, "system ID");
        return OOJSNativeFailure(context);
    }

    bool OK = (player != nullptr ? player->removeContract(key.value_or(""), (unsigned)dest) : false);
    OOJS_RETURN_BOOL(OK);

    OOJS_NATIVE_EXIT
}

// setCustomView(position:vector, orientation:quaternion [, weapon:string])
static JSValue PlayerShipSetCustomView(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    PlayerEntity* player = OOPlayerForScripting();

    if (argc < 2) {
        cxx_OOJSReportBadArguments(context, "PlayerShip", "setCustomView", argc, OOJS_ARGV, std::nullopt, "position, orientiation, [weapon]");
        return OOJSNativeFailure(context);
    }

    // must be in custom view
    if ((UNIVERSE != nullptr ? UNIVERSE->getViewDirection() : OOViewID { }) != VIEW_CUSTOM) {
        cxx_OOJSReportError(context, "PlayerShip.setCustomView only works when custom view is active.");
        return OOJSNativeFailure(context);
    }

    oo::PList::Dict viewData;

    Vector position = kZeroVector;
    bool gotpos = JSValueToVector(context, OOJS_ARGV[0], &position);
    if (!gotpos) {
        cxx_OOJSReportBadArguments(context, "PlayerShip", "setCustomView", argc, OOJS_ARGV, std::nullopt, "position, orientiation, [weapon]");
        return OOJSNativeFailure(context);
    }
    std::string positionstr = oo::str::format("%f %f %f", position.x, position.y, position.z);

    Quaternion orientation = kIdentityQuaternion;
    bool gotquat = JSValueToQuaternion(context, OOJS_ARGV[1], &orientation);
    if (!gotquat) {
        cxx_OOJSReportBadArguments(context, "PlayerShip", "setCustomView", argc, OOJS_ARGV, std::nullopt, "position, orientiation, [weapon]");
        return OOJSNativeFailure(context);
    }
    std::string orientationstr = oo::str::format("%f %f %f %f", orientation.w, orientation.x, orientation.y, orientation.z);

    viewData["view_position"] = positionstr;
    viewData["view_orientation"] = orientationstr;

    if (argc > 2) {
        std::optional<std::string> facing = cxx_OOStringFromJSValue(context, OOJS_ARGV[2]);
        // -setObject:forKey: raised on a nil facing (GNUstep 1.31.1's text).
        if (!facing.has_value())
            OORaiseException(OOInvalidArgumentException, "Tried to add nil value for key '%s' to dictionary", "weapon_facing");
        viewData["weapon_facing"] = *facing;
    }

    if (player != nullptr)
        player->setCustomViewDataFromDictionary(oo::PList(std::move(viewData)), false);
    if (player != nullptr)
        player->noteSwitchToView(VIEW_CUSTOM, VIEW_CUSTOM);

    OOJS_RETURN_BOOL(true);
    OOJS_NATIVE_EXIT
}

// resetCustomView()
static JSValue PlayerShipResetCustomView(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    PlayerEntity* player = OOPlayerForScripting();

    // must be in custom view
    if ((UNIVERSE != nullptr ? UNIVERSE->getViewDirection() : OOViewID { }) != VIEW_CUSTOM) {
        cxx_OOJSReportError(context, "PlayerShip.setCustomView only works when custom view is active.");
        return OOJSNativeFailure(context);
    }

    if (player != nullptr)
        player->resetCustomView();
    if (player != nullptr)
        player->noteSwitchToView(VIEW_CUSTOM, VIEW_CUSTOM);

    OOJS_RETURN_BOOL(true);
    OOJS_NATIVE_EXIT
}

// resetScannerZoom()
static JSValue PlayerShipResetScannerZoom(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    PlayerEntity* player = OOPlayerForScripting();

    if (player != nullptr)
        player->resetScannerZoom();

    OOJS_RETURN_VOID;
    OOJS_NATIVE_EXIT
}

// takeInternalDamage()
static JSValue PlayerShipTakeInternalDamage(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    PlayerEntity* player = OOPlayerForScripting();

    bool took = (player != nullptr ? player->takeInternalDamage() : false);

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
    bool begun = false;
    if (argc < 1) {
        witchspaceSpinUpTime = 0;
#ifdef OO_DUMP_PLANETINFO
        // quick intersystem jumps for debugging
        witchspaceSpinUpTime = 1;
#endif
    } else {
        if (!OOJSValueToInt32(context, OOJS_ARGV[0], &spin_time) || spin_time < 5 || spin_time > 60) {
            cxx_OOJSReportBadArguments(context, "PlayerShip", "beginHyperspaceCountdown", 1, &OOJS_ARGV[0], std::nullopt, "between 5 and 60 seconds");
            return OOJSNativeFailure(context);
        }
        if (spin_time < 5) {
            witchspaceSpinUpTime = 5;
        } else {
            witchspaceSpinUpTime = spin_time;
        }
    }
    if ((player != nullptr ? player->hasHyperspaceMotor() : false) && (player != nullptr ? player->status() : OOEntityStatus { }) == STATUS_IN_FLIGHT && (player != nullptr ? player->witchJumpChecklist(false) : false)) {
        if (player != nullptr)
            player->beginWitchspaceCountdown(witchspaceSpinUpTime);
        begun = true;
    }
    OOJS_RETURN_BOOL(begun);
    OOJS_NATIVE_EXIT
}

// cancelHyperspaceCountdown()
static JSValue PlayerShipCancelHyperspaceCountdown(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    PlayerEntity* player = OOPlayerForScripting();

    bool cancelled = false;
    if ((player != nullptr ? player->hasHyperspaceMotor() : false) && (player != nullptr ? player->status() : OOEntityStatus { }) == STATUS_WITCHSPACE_COUNTDOWN) {
        if (player != nullptr)
            player->cancelWitchspaceCountdown();
        if (player != nullptr)
            player->setJumpType(false);
        cancelled = true;
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
    bool begun = false;
    if (argc == 1) {

        if (!OOJSValueToInt32(context, OOJS_ARGV[0], &spin_time) || spin_time < 5 || spin_time > 60) {
            cxx_OOJSReportBadArguments(context, "PlayerShip", "beginGalacticHyperspaceCountdown", 1, &OOJS_ARGV[0], std::nullopt, "between 5 and 60 seconds");
            return OOJSNativeFailure(context);
        }
        if (spin_time < 5) {
            witchspaceSpinUpTime = 5;
        } else {
            witchspaceSpinUpTime = spin_time;
        }
    }
    if ((player != nullptr ? player->hasEquipmentItemProviding("EQ_GAL_DRIVE") : false) && (player != nullptr ? player->status() : OOEntityStatus { }) == STATUS_IN_FLIGHT && (player != nullptr ? player->witchJumpChecklist(true) : false)) {
        if (player != nullptr)
            player->setJumpType(true);
        if (player != nullptr)
            player->setWitchspaceCountdown(witchspaceSpinUpTime);
        if (player != nullptr)
            player->setStatus(STATUS_WITCHSPACE_COUNTDOWN);
        if (player != nullptr)
            player->playGalacticHyperspace();
        // say it!
        if (UNIVERSE != nullptr)
            UNIVERSE->addMessage(oo::str::format(OO_DESC("witch-galactic-in-f-seconds").c_str(), witchspaceSpinUpTime), 1.0);
        begun = true;
    }
    OOJS_RETURN_BOOL(begun);
    OOJS_NATIVE_EXIT
}

// setMultiFunctionDisplay(index,key)
static JSValue PlayerShipSetMultiFunctionDisplay(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    std::optional<std::string> key;
    uint32_t index = 0;
    PlayerEntity* player = OOPlayerForScripting();
    bool OK = true;

    if (argc > 0) {
        if (JS_ToUint32(context, &index, OOJS_ARGV[0]) != 0) {
            cxx_OOJSReportBadArguments(context, "PlayerShip", "setMultiFunctionDisplay", MIN(argc, 1), OOJS_ARGV, std::nullopt, "number (index) [, string (key)]");
            return OOJSNativeFailure(context);
        }
    }

    if (argc > 1) {
        key = cxx_OOStringFromJSValue(context, OOJS_ARGV[1]);
    }

    OK = (player != nullptr ? player->setMultiFunctionDisplay(index, key) : false);

    OOJS_RETURN_BOOL(OK);

    OOJS_NATIVE_EXIT
}

// setMultiFunctionText(key,value)
static JSValue PlayerShipSetMultiFunctionText(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    std::optional<std::string> key;
    std::optional<std::string> value;
    PlayerEntity* player = OOPlayerForScripting();
    int reflow = false;

    if (argc > 0) {
        key = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
    }
    if (!key.has_value()) {
        cxx_OOJSReportBadArguments(context, "PlayerShip", "setMultiFunctionText", MIN(argc, 1), OOJS_ARGV, std::nullopt, "string (key) [, string (text)]");
        return OOJSNativeFailure(context);
    }
    if (argc > 1) {
        value = cxx_OOStringFromJSValue(context, OOJS_ARGV[1]);
    }
    if (argc > 2 && EXPECT_NOT((reflow = JS_ToBool(context, OOJS_ARGV[2])) < 0)) {
        cxx_OOJSReportBadArguments(context, "setMultiFunctionText", "reflow", argc, OOJS_ARGV, std::nullopt, "boolean");
        return OOJSNativeFailure(context);
    }

    if (!reflow) {
        if (player != nullptr)
            player->setMultiFunctionText(value, key);
    } else {
        GuiDisplayGen* gui = (UNIVERSE != nullptr ? UNIVERSE->getGui() : nullptr);
        if (player != nullptr)
            player->setMultiFunctionText(gui->reflowTextForMFD(value), key);
    }

    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}

// setPrimedEquipment(key, [noMessage])
static JSValue PlayerShipSetPrimedEquipment(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    std::optional<std::string> key;
    PlayerEntity* player = OOPlayerForScripting();
    int showMsg = true;

    if (argc > 0) {
        key = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
    }
    if (!key.has_value()) {
        cxx_OOJSReportBadArguments(context, "PlayerShip", "setPrimedEquipment", MIN(argc, 1), OOJS_ARGV, std::nullopt, "string (key)");
        return OOJSNativeFailure(context);
    }
    if (argc > 1 && EXPECT_NOT((showMsg = JS_ToBool(context, OOJS_ARGV[1])) < 0)) {
        cxx_OOJSReportBadArguments(context, "PlayerShip", "setPrimedEquipment", MIN(argc, 2), OOJS_ARGV, std::nullopt, "boolean");
        return OOJSNativeFailure(context);
    }

    OOJS_RETURN_BOOL(key.has_value() ? (player != nullptr ? player->setPrimedEquipment(*key, showMsg) : false) : false);

    OOJS_NATIVE_EXIT
}

// setCustomHUDDial(key,value)
static JSValue PlayerShipSetCustomHUDDial(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    std::optional<std::string> key;
    oo::PList value;
    PlayerEntity* player = OOPlayerForScripting();

    if (argc > 0) {
        key = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
    }
    if (!key.has_value()) {
        cxx_OOJSReportBadArguments(context, "PlayerShip", "setCustomHUDDial", MIN(argc, 1), OOJS_ARGV, std::nullopt, "string (key), value]");
        return OOJSNativeFailure(context);
    }
    if (argc > 1) {
        value = cxx_OOJSPListFromJSValue(context, OOJS_ARGV[1]);
    } else {
        value = oo::PList(std::string());
    }

    if (player != nullptr)
        player->setDialCustom(value, key.value_or(""));

    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}

static JSValue PlayerShipHideHUDSelector(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    std::optional<std::string> key;
    PlayerEntity* player = OOPlayerForScripting();

    if (argc > 0) {
        key = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
    }
    if (!key.has_value()) {
        cxx_OOJSReportBadArguments(context, "PlayerShip", "hideHUDSelector", MIN(argc, 1), OOJS_ARGV, std::nullopt, "string (selector)");
        return OOJSNativeFailure(context);
    }
    if (HeadUpDisplay* hud = HudOf(player))
        hud->setHiddenSelector(key.value_or(""), true);

    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}

static JSValue PlayerShipShowHUDSelector(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    std::optional<std::string> key;
    PlayerEntity* player = OOPlayerForScripting();

    if (argc > 0) {
        key = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
    }
    if (!key.has_value()) {
        cxx_OOJSReportBadArguments(context, "PlayerShip", "hideHUDSelector", MIN(argc, 1), OOJS_ARGV, std::nullopt, "string (selector)");
        return OOJSNativeFailure(context);
    }
    if (HeadUpDisplay* hud = HudOf(player))
        hud->setHiddenSelector(key.value_or(""), false);

    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}

static bool ValidateContracts(JSContext* context, int argc, JSValueConst* argv, bool isCargo, OOSystemID* start, OOSystemID* destination, double* eta, double* fee, double* premium, const std::string& functionName, unsigned* risk)
{
    OOJS_PROFILE_ENTER

    OOCParameterAssert(context != NULL && argv != NULL && start != NULL && destination != NULL && eta != NULL && fee != NULL);

    uint32_t uValue;
    int offset = isCargo ? 2 : 1;
    double fValue;
    int32_t iValue;

    if (!OOJSValueToInt32(context, argv[offset + 0], &iValue) || iValue < 0 || iValue > kOOMaximumSystemID) {
        cxx_OOJSReportBadArguments(context, "PlayerShip", functionName, 1, &argv[offset + 0], std::nullopt, "system ID");
        return false;
    }
    *start = iValue;

    if (!OOJSValueToInt32(context, argv[offset + 1], &iValue) || iValue < 0 || iValue > kOOMaximumSystemID) {
        cxx_OOJSReportBadArguments(context, "PlayerShip", functionName, 1, &argv[offset + 1], std::nullopt, "system ID");
        return false;
    }
    *destination = iValue;

    if (JS_ToFloat64(context, &fValue, argv[offset + 2]) != 0 || !isfinite(fValue) || fValue <= (PLAYER != nullptr ? PLAYER->clockTime() : 0.0)) {
        cxx_OOJSReportBadArguments(context, "PlayerShip", functionName, 1, &argv[offset + 2], std::nullopt, "number (future time)");
        return false;
    }
    *eta = fValue;

    if (JS_ToFloat64(context, &fValue, argv[offset + 3]) != 0 || !isfinite(fValue) || fValue < 0.0) {
        cxx_OOJSReportBadArguments(context, "PlayerShip", functionName, 1, &argv[offset + 3], std::nullopt, "number (credits quantity)");
        return false;
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

    return true;

    OOJS_PROFILE_EXIT
}
