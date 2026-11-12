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

#include <cstddef>
#include <cstdint>
#include <format>
#include <map>
#include <optional>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

#include "EntityOOJavaScriptExtensions.h"
#include "GuiDisplayGen.h"
#include "HeadUpDisplay.h"
#include "OOConstToJSString.h"
#include "OOConstToString.h"
#include "OODescription.h"
#include "OOEquipmentType.h"
#include "OOFunctionAttributes.h"
#include "OOJSEntity.h"
#include "OOJSEquipmentInfo.h"
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
#include "Universe.h"
#include "oofnd/Notification.hpp"
#include "oofnd/PList.hpp"
#include "oofnd/String.hpp"
#include "oofnd/objc/OOAssert.h"
#include "oofnd/objc/OOException.h"

static JSClassID sPlayerShipClassID;

static JSClassDef sPlayerShipClass = {
    .class_name = "PlayerShip",
    .finalizer = OOJSCxxObjectWrapperFinalize,
};

namespace {

// A colour's components as its -normalizedArray gave them to JavaScript:
// floats, null for no colour.
oo::PList NormalizedColorComponents(OOColor* color) {
  if (color == nullptr) return oo::PList();
  oo::PList::Array components;
  for (float component : color->normalizedArray())
    components.push_back(oo::PList::singleReal(component));
  return oo::PList(std::move(components));
}

/*	A player with no HUD answers zero, false, nil or none to every message
   the getter sends the HUD; so does a null HUD here.
*/
template <typename R>
R AskHud(PlayerEntity* player, R (HeadUpDisplay::*member)()) {
  HeadUpDisplay* hud =
      (player != nullptr ? player->getHud() : (HeadUpDisplay*)nullptr);
  return (hud != nullptr) ? (hud->*member)() : R();
}

HeadUpDisplay* HudOf(PlayerEntity* player) {
  return (player != nullptr ? player->getHud() : (HeadUpDisplay*)nullptr);
}

oo::Ref<OOColor> HudReticleColor(PlayerEntity* player, std::size_t idx) {
  HeadUpDisplay* hud =
      (player != nullptr ? player->getHud() : (HeadUpDisplay*)nullptr);
  return (hud != nullptr) ? hud->reticleColorForIndex(idx) : oo::Ref<OOColor>();
}

// A string, or null for none (what an NSString or nil gave JavaScript).
oo::PList StringOrNull(const std::optional<std::string>& string) {
  return string.has_value() ? oo::PList(*string) : oo::PList();
}

}  // namespace

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

static bool ValidateContracts(JSContext* context, int argc, JSValueConst* argv,
                              bool isCargo, OOSystemID* start,
                              OOSystemID* destination, double* eta, double* fee,
                              double* premium, const std::string& functionName,
                              unsigned* risk);

namespace {

enum class PlayerShipProperty : std::int16_t {
  // Property IDs
  kActiveMissile,          // index in 'missiles' array of current active
                           // missile
  kAftShield,              // aft shield charge level, nonnegative float,
                           // read/write
  kAftShieldRechargeRate,  // aft shield recharge rate, positive
                           // float, read-only
  kChartHightlightMode,    // what type of information is being shown
                           // on the chart
  kCompassMode,            // compass mode, string, read/write
  kCompassTarget,          // object targeted by the compass, entity,
                           // read/write
  kCompassType,            // basic / advanced, string, read/write
  kCurrentWeapon,          // shortcut property to _aftWeapon, etc. overrides
                           // kShip generic version
  kCrosshairs,             // custom plist file defining crosshairs
  kCursorCoordinates,      // cursor coordinates (unscaled), Vector3D,
                           // read only
  kCursorCoordinatesInLY,  // cursor coordinates (in LY), Vector3D,
                           // read only
  kDocked,                 // docked, boolean, read-only
  kDockedStation,          // docked station, entity, read-only
  kFastEquipmentA,         // fast equipment A, string, read/write
  kFastEquipmentB,         // fast equipment B, string, read/write
  kForwardShield,          // forward shield charge level, nonnegative float,
                           // read/write
  kForwardShieldRechargeRate,          // forward shield recharge rate,
                                       // positive float, read-only
  kFuelLeakRate,                       // fuel leak rate, float, read/write
  kGalacticHyperspaceBehaviour,        // can be standard, all systems
                                       // reachable or fixed coordinates,
                                       // integer, read-only
  kGalacticHyperspaceFixedCoords,      // used when fixed coords
                                       // behaviour is selected,
                                       // Vector3D, read/write
  kGalacticHyperspaceFixedCoordsInLY,  // used when fixed coords
                                       // behaviour is selected,
                                       // Vector3D, read/write
  kGalaxyCoordinates,      // galaxy coordinates (unscaled), Vector3D,
                           // read only
  kGalaxyCoordinatesInLY,  // galaxy coordinates (in LY), Vector3D,
                           // read only
  kHud,                    // hud name identifier, string, read/write
  kHudAllowsBigGui,        // hud big gui, string, read only
  kHudHidden,              // hud visibility, boolean, read/write
  kInjectorsEngaged,       // injectors in use, boolean, read-only
  kMassLockable,           // mass-lockability of player ship, read/write
  kMaxAftShield,           // maximum aft shield charge level, positive float,
                           // read-only
  kMaxForwardShield,       // maximum forward shield charge level,
                           // positive float, read-only
  kMessageGuiTextColor,    // message gui standard text color, array,
                           // read/write
  kMessageGuiTextCommsColor,  // message gui incoming comms text
                              // color, array, read/write
  kMultiFunctionDisplays,     // mfd count, positive int, read-only
  kMultiFunctionDisplayList,  // active mfd list, array, read-only
  kMissilesOnline,            // bool (false for ident mode, true for missile
                              // mode)
  kPitch,                     // pitch (overrules Ship)
  kPrice,               // idealised trade-in value decicredits, positive int,
                        // read-only
  kPrimedEquipment,     // currently primed equipment, string,
                        // read/write
  kRenovationCost,      // int read-only current renovation cost
  kReticleColorTarget,  // Reticle color for normal targets, array,
                        // read/write
  kReticleColorTargetSensitive,  // Reticle color for targets picked
                                 // up when sensitive mode is on,
                                 // array, read/write
  kReticleColorWormhole,         // REticle color for wormholes, array,
                                 // read/write
  kRenovationMultiplier,         // float read-only multiplier for
                                 // renovation costs
  kReticleTargetSensitive,       // target box changes color when primary
                                 // target in crosshairs, boolean,
                                 // read/write
  kRoll,                         // roll (overrules Ship)
  kRouteMode,                    // ANA mode
  kScannerMinimalistic,          // essentially scanner without gridlines
  kScannerNonLinear,             // non linear scanner setting, boolean,
                                 // read/write
  kScannerUltraZoom,             // scanner zoom in powers of 2, boolean,
                                 // read/write
  kScoopOverride,                // Scooping
  kServiceLevel,           // servicing level, positive int 75-100, read-only
  kSpecialCargo,           // special cargo, string, read-only
  kTargetSystem,           // target system id, int, read-write
  kNextSystem,             // next hop system id, read-only
  kInfoSystem,             // info (F7 screen) system id, int, read-write
  kPreviousSystem,         // previous system id, read-only
  kTorusEngaged,           // torus in use, boolean, read-only
  kViewDirection,          // view direction identifier, string, read-only
  kViewPositionAft,        // view position offset, vector, read-only
  kViewPositionForward,    // view position offset, vector, read-only
  kViewPositionPort,       // view position offset, vector, read-only
  kViewPositionStarboard,  // view position offset, vector, read-only
  kWeaponsOnline,          // weapons online status, boolean, read-only
  kYaw,                    // yaw (overrules Ship)
};

}  // namespace

static const JSCFunctionListEntry sPlayerShipProperties[] = {
    // JS name, getter, setter, ID
    OOJS_PROPERTY_RO("activeMissile", PlayerShipGetProperty,
                     PlayerShipProperty::kActiveMissile),
    OOJS_PROPERTY_RW("aftShield", PlayerShipGetProperty, PlayerShipSetProperty,
                     PlayerShipProperty::kAftShield),
    OOJS_PROPERTY_RW("aftShieldRechargeRate", PlayerShipGetProperty,
                     PlayerShipSetProperty,
                     PlayerShipProperty::kAftShieldRechargeRate),
    OOJS_PROPERTY_RW("chartHighlightMode", PlayerShipGetProperty,
                     PlayerShipSetProperty,
                     PlayerShipProperty::kChartHightlightMode),
    OOJS_PROPERTY_RW("compassMode", PlayerShipGetProperty,
                     PlayerShipSetProperty, PlayerShipProperty::kCompassMode),
    OOJS_PROPERTY_RW("compassTarget", PlayerShipGetProperty,
                     PlayerShipSetProperty, PlayerShipProperty::kCompassTarget),
    OOJS_PROPERTY_RW("compassType", PlayerShipGetProperty,
                     PlayerShipSetProperty, PlayerShipProperty::kCompassType),
    OOJS_PROPERTY_RW("currentWeapon", PlayerShipGetProperty,
                     PlayerShipSetProperty, PlayerShipProperty::kCurrentWeapon),
    OOJS_PROPERTY_RW("crosshairs", PlayerShipGetProperty, PlayerShipSetProperty,
                     PlayerShipProperty::kCrosshairs),
    OOJS_PROPERTY_RO("cursorCoordinates", PlayerShipGetProperty,
                     PlayerShipProperty::kCursorCoordinates),
    OOJS_PROPERTY_RO("cursorCoordinatesInLY", PlayerShipGetProperty,
                     PlayerShipProperty::kCursorCoordinatesInLY),
    OOJS_PROPERTY_RO("docked", PlayerShipGetProperty,
                     PlayerShipProperty::kDocked),
    OOJS_PROPERTY_RO("dockedStation", PlayerShipGetProperty,
                     PlayerShipProperty::kDockedStation),
    OOJS_PROPERTY_RW("fastEquipmentA", PlayerShipGetProperty,
                     PlayerShipSetProperty,
                     PlayerShipProperty::kFastEquipmentA),
    OOJS_PROPERTY_RW("fastEquipmentB", PlayerShipGetProperty,
                     PlayerShipSetProperty,
                     PlayerShipProperty::kFastEquipmentB),
    OOJS_PROPERTY_RW("forwardShield", PlayerShipGetProperty,
                     PlayerShipSetProperty, PlayerShipProperty::kForwardShield),
    OOJS_PROPERTY_RW("forwardShieldRechargeRate", PlayerShipGetProperty,
                     PlayerShipSetProperty,
                     PlayerShipProperty::kForwardShieldRechargeRate),
    OOJS_PROPERTY_RW("fuelLeakRate", PlayerShipGetProperty,
                     PlayerShipSetProperty, PlayerShipProperty::kFuelLeakRate),
    OOJS_PROPERTY_RW("galacticHyperspaceBehaviour", PlayerShipGetProperty,
                     PlayerShipSetProperty,
                     PlayerShipProperty::kGalacticHyperspaceBehaviour),
    OOJS_PROPERTY_RW("galacticHyperspaceFixedCoords", PlayerShipGetProperty,
                     PlayerShipSetProperty,
                     PlayerShipProperty::kGalacticHyperspaceFixedCoords),
    OOJS_PROPERTY_RW("galacticHyperspaceFixedCoordsInLY", PlayerShipGetProperty,
                     PlayerShipSetProperty,
                     PlayerShipProperty::kGalacticHyperspaceFixedCoordsInLY),
    OOJS_PROPERTY_RO("galaxyCoordinates", PlayerShipGetProperty,
                     PlayerShipProperty::kGalaxyCoordinates),
    OOJS_PROPERTY_RO("galaxyCoordinatesInLY", PlayerShipGetProperty,
                     PlayerShipProperty::kGalaxyCoordinatesInLY),
    OOJS_PROPERTY_RW("hud", PlayerShipGetProperty, PlayerShipSetProperty,
                     PlayerShipProperty::kHud),
    OOJS_PROPERTY_RO("hudAllowsBigGui", PlayerShipGetProperty,
                     PlayerShipProperty::kHudAllowsBigGui),
    OOJS_PROPERTY_RW("hudHidden", PlayerShipGetProperty, PlayerShipSetProperty,
                     PlayerShipProperty::kHudHidden),
    OOJS_PROPERTY_RO("injectorsEngaged", PlayerShipGetProperty,
                     PlayerShipProperty::kInjectorsEngaged),
    OOJS_PROPERTY_RW("massLockable", PlayerShipGetProperty,
                     PlayerShipSetProperty, PlayerShipProperty::kMassLockable),
    // manifest defined in OOJSManifest.m
    OOJS_PROPERTY_RW("maxAftShield", PlayerShipGetProperty,
                     PlayerShipSetProperty, PlayerShipProperty::kMaxAftShield),
    OOJS_PROPERTY_RW("maxForwardShield", PlayerShipGetProperty,
                     PlayerShipSetProperty,
                     PlayerShipProperty::kMaxForwardShield),
    OOJS_PROPERTY_RW("messageGuiTextColor", PlayerShipGetProperty,
                     PlayerShipSetProperty,
                     PlayerShipProperty::kMessageGuiTextColor),
    OOJS_PROPERTY_RW("messageGuiTextCommsColor", PlayerShipGetProperty,
                     PlayerShipSetProperty,
                     PlayerShipProperty::kMessageGuiTextCommsColor),
    OOJS_PROPERTY_RO("missilesOnline", PlayerShipGetProperty,
                     PlayerShipProperty::kMissilesOnline),
    OOJS_PROPERTY_RO("multiFunctionDisplays", PlayerShipGetProperty,
                     PlayerShipProperty::kMultiFunctionDisplays),
    OOJS_PROPERTY_RO("multiFunctionDisplayList", PlayerShipGetProperty,
                     PlayerShipProperty::kMultiFunctionDisplayList),
    OOJS_PROPERTY_RO("price", PlayerShipGetProperty,
                     PlayerShipProperty::kPrice),
    OOJS_PROPERTY_RW("pitch", PlayerShipGetProperty, PlayerShipSetProperty,
                     PlayerShipProperty::kPitch),
    OOJS_PROPERTY_RW("primedEquipment", PlayerShipGetProperty,
                     PlayerShipSetProperty,
                     PlayerShipProperty::kPrimedEquipment),
    OOJS_PROPERTY_RO("renovationCost", PlayerShipGetProperty,
                     PlayerShipProperty::kRenovationCost),
    OOJS_PROPERTY_RW("reticleColorTarget", PlayerShipGetProperty,
                     PlayerShipSetProperty,
                     PlayerShipProperty::kReticleColorTarget),
    OOJS_PROPERTY_RW("reticleColorTargetSensitive", PlayerShipGetProperty,
                     PlayerShipSetProperty,
                     PlayerShipProperty::kReticleColorTargetSensitive),
    OOJS_PROPERTY_RW("reticleColorWormhole", PlayerShipGetProperty,
                     PlayerShipSetProperty,
                     PlayerShipProperty::kReticleColorWormhole),
    OOJS_PROPERTY_RO("renovationMultiplier", PlayerShipGetProperty,
                     PlayerShipProperty::kRenovationMultiplier),
    OOJS_PROPERTY_RW("reticleTargetSensitive", PlayerShipGetProperty,
                     PlayerShipSetProperty,
                     PlayerShipProperty::kReticleTargetSensitive),
    OOJS_PROPERTY_RW("roll", PlayerShipGetProperty, PlayerShipSetProperty,
                     PlayerShipProperty::kRoll),
    OOJS_PROPERTY_RO("routeMode", PlayerShipGetProperty,
                     PlayerShipProperty::kRouteMode),
    OOJS_PROPERTY_RW("scannerMinimalistic", PlayerShipGetProperty,
                     PlayerShipSetProperty,
                     PlayerShipProperty::kScannerMinimalistic),
    OOJS_PROPERTY_RW("scannerNonLinear", PlayerShipGetProperty,
                     PlayerShipSetProperty,
                     PlayerShipProperty::kScannerNonLinear),
    OOJS_PROPERTY_RW("scannerUltraZoom", PlayerShipGetProperty,
                     PlayerShipSetProperty,
                     PlayerShipProperty::kScannerUltraZoom),
    OOJS_PROPERTY_RW("scoopOverride", PlayerShipGetProperty,
                     PlayerShipSetProperty, PlayerShipProperty::kScoopOverride),
    OOJS_PROPERTY_RW("serviceLevel", PlayerShipGetProperty,
                     PlayerShipSetProperty, PlayerShipProperty::kServiceLevel),
    OOJS_PROPERTY_RO("specialCargo", PlayerShipGetProperty,
                     PlayerShipProperty::kSpecialCargo),
    OOJS_PROPERTY_RW("targetSystem", PlayerShipGetProperty,
                     PlayerShipSetProperty, PlayerShipProperty::kTargetSystem),
    OOJS_PROPERTY_RO("nextSystem", PlayerShipGetProperty,
                     PlayerShipProperty::kNextSystem),
    OOJS_PROPERTY_RW("infoSystem", PlayerShipGetProperty, PlayerShipSetProperty,
                     PlayerShipProperty::kInfoSystem),
    OOJS_PROPERTY_RO("previousSystem", PlayerShipGetProperty,
                     PlayerShipProperty::kPreviousSystem),
    OOJS_PROPERTY_RO("torusEngaged", PlayerShipGetProperty,
                     PlayerShipProperty::kTorusEngaged),
    OOJS_PROPERTY_RO("viewDirection", PlayerShipGetProperty,
                     PlayerShipProperty::kViewDirection),
    OOJS_PROPERTY_RO("viewPositionAft", PlayerShipGetProperty,
                     PlayerShipProperty::kViewPositionAft),
    OOJS_PROPERTY_RO("viewPositionForward", PlayerShipGetProperty,
                     PlayerShipProperty::kViewPositionForward),
    OOJS_PROPERTY_RO("viewPositionPort", PlayerShipGetProperty,
                     PlayerShipProperty::kViewPositionPort),
    OOJS_PROPERTY_RO("viewPositionStarboard", PlayerShipGetProperty,
                     PlayerShipProperty::kViewPositionStarboard),
    OOJS_PROPERTY_RO("weaponsOnline", PlayerShipGetProperty,
                     PlayerShipProperty::kWeaponsOnline),
    OOJS_PROPERTY_RW("yaw", PlayerShipGetProperty, PlayerShipSetProperty,
                     PlayerShipProperty::kYaw),
};

static const JSCFunctionListEntry sPlayerShipMethods[] = {
    // JS name, min args, function
    JS_CFUNC_DEF("addParcel", 0, PlayerShipAddParcel),
    JS_CFUNC_DEF("addPassenger", 0, PlayerShipAddPassenger),
    JS_CFUNC_DEF("awardContract", 0, PlayerShipAwardContract),
    JS_CFUNC_DEF("awardEquipmentToCurrentPylon", 1,
                 PlayerShipAwardEquipmentToCurrentPylon),
    JS_CFUNC_DEF("beginHyperspaceCountdown", 0,
                 PlayerShipBeginHyperspaceCountdown),
    JS_CFUNC_DEF("cancelDockingRequest", 1, PlayerShipCancelDockingRequest),
    JS_CFUNC_DEF("cancelHyperspaceCountdown", 0,
                 PlayerShipCancelHyperspaceCountdown),
    JS_CFUNC_DEF("beginGalacticHyperspaceCountdown", 1,
                 PlayerShipBeginGalacticHyperspaceCountdown),
    JS_CFUNC_DEF("disengageAutopilot", 0, PlayerShipDisengageAutopilot),
    JS_CFUNC_DEF("engageAutopilotToStation", 1,
                 PlayerShipEngageAutopilotToStation),
    JS_CFUNC_DEF("hideHUDSelector", 1, PlayerShipHideHUDSelector),
    JS_CFUNC_DEF("launch", 0, PlayerShipLaunch),
    JS_CFUNC_DEF("removeAllCargo", 0, PlayerShipRemoveAllCargo),
    JS_CFUNC_DEF("removeContract", 2, PlayerShipRemoveContract),
    JS_CFUNC_DEF("removeParcel", 1, PlayerShipRemoveParcel),
    JS_CFUNC_DEF("removePassenger", 1, PlayerShipRemovePassenger),
    JS_CFUNC_DEF("requestDockingClearance", 1,
                 PlayerShipRequestDockingClearance),
    JS_CFUNC_DEF("resetCustomView", 0, PlayerShipResetCustomView),
    JS_CFUNC_DEF("resetScannerZoom", 0, PlayerShipResetScannerZoom),
    JS_CFUNC_DEF("setCustomView", 2, PlayerShipSetCustomView),
    JS_CFUNC_DEF("setCustomHUDDial", 2, PlayerShipSetCustomHUDDial),
    JS_CFUNC_DEF("setMultiFunctionDisplay", 1,
                 PlayerShipSetMultiFunctionDisplay),
    JS_CFUNC_DEF("setMultiFunctionText", 1, PlayerShipSetMultiFunctionText),
    JS_CFUNC_DEF("setPrimedEquipment", 1, PlayerShipSetPrimedEquipment),
    JS_CFUNC_DEF("showHUDSelector", 1, PlayerShipShowHUDSelector),
    JS_CFUNC_DEF("takeInternalDamage", 0, PlayerShipTakeInternalDamage),
    JS_CFUNC_DEF("useSpecialCargo", 1, PlayerShipUseSpecialCargo),
};

void InitOOJSPlayerShip(JSContext* context, JSValueConst global) {
  OOJSRegisterClass(&sPlayerShipClassID, &sPlayerShipClass);

  JSValue shipPrototype = JS_GetClassProto(context, JSShipClassID());
  OOCAssert(JS_IsObject(shipPrototype),
            "Ship must be initialized before PlayerShip.");
  OOJSInitClass(context, global, sPlayerShipClassID, shipPrototype,
                OOJSUnconstructableConstruct, 0, sPlayerShipProperties,
                OOJS_COUNT(sPlayerShipProperties), sPlayerShipMethods,
                OOJS_COUNT(sPlayerShipMethods), nullptr, 0);
  JS_FreeValue(context, shipPrototype);

  OOJSRegisterObjectConverter(sPlayerShipClassID, OOJSEntityObjectConverter);
  OOJSRegisterSubclass(sPlayerShipClassID, JSShipClassID());

  PlayerEntity* player =
      PlayerEntity::sharedPlayer();  // NOTE: at time of writing, this creates
                                     // the player entity. Don't use PLAYER
                                     // here.

  // Create ship object as a property of the player object.
  JSValue playerObject = JS_GetPropertyStr(context, global, "player");
  OOCAssert(JS_IsObject(playerObject),
            "Player must be initialized before PlayerShip.");

  JSValue shipObject = JS_NewObjectClass(context, (int)sPlayerShipClassID);
  // The slot holds a weak reference to the C++ player, as every entity's JS
  // object's does.
  OOJSSetCxxPrivate(shipObject, oo::makeRef<OOJSEntityHolder>(player).get());
  // The player object's property and the player entity each own a reference.
  JS_DefinePropertyValueStr(context, playerObject, "ship",
                            JS_DupValue(context, shipObject),
                            OOJS_PROP_READONLY);
  OOJSPlayerShipSetJSSelf(
      player, shipObject,
      context);  // -setJSSelf:context:, the category in this file

  JS_FreeValue(context, shipObject);
  JS_FreeValue(context, playerObject);
}

JSClassID JSPlayerShipClassID() { return sPlayerShipClassID; }

JSValue JSPlayerShipObject() {
  JSContext* context = OOJSAcquireContext();
  JSValue playerObject = JSPlayerObject();
  JSValue result = JS_GetPropertyStr(context, playerObject, "ship");
  JS_FreeValue(context, playerObject);
  OOJSRelinquishContext(context);
  return result;
}

// PlayerEntity (OOJavaScriptExtensions): the bodies of the category's methods,
// which the engine and the player sent by selector; the C++ player calls them.
// Its JS class is JSPlayerShipClassID() (PlayerEntity::jsClassID()).
std::optional<std::string> OOJSPlayerShipJSClassName() {
  return std::string("PlayerShip");
}

void OOJSPlayerShipSetJSSelf(PlayerEntity* player, JSValueConst val,
                             JSContext* context) {
  // Drop any previous wrapper (and its reset observer).
  player->deleteJSSelf();

  // Released by deleteJSSelf() when the JavaScript engine resets.
  player->_jsSelf = JS_DupValue(context, val);

  oo::NotificationCenter::defaultCenter().addObserver(
      player, kOOJavaScriptEngineWillResetNotificationName,
      OOJavaScriptEngine::sharedEngine(),
      [player](const oo::Notification&) { player->deleteJSSelf(); });
}

static JSValue PlayerShipGetProperty(OOJS_GETTER_ARGS) {
  OOJS_NATIVE_ENTER(context)

  /*	SpiderMonkey compared this with the prototype. The prototype (like any
          object that isn't player.ship, such as the this of a detached getter
          call) has no private weak reference to the player.
  */
  if (EXPECT_NOT(OOIsPlayerStale() ||
                 JS_GetOpaque(thisObj, sPlayerShipClassID) == nullptr)) {
    return JS_UNDEFINED;
  }

  oo::PList result;  // null maps to null
  PlayerEntity* player = OOPlayerForScripting();

  switch (static_cast<PlayerShipProperty>(magic)) {
    using enum PlayerShipProperty;
    case kActiveMissile:
      return JS_NewNumber(context,
                          (player != nullptr ? player->getActiveMissile() : 0));

    case kFuelLeakRate:
      return JS_NewNumber(context,
                          (player != nullptr ? player->fuelLeakRate() : 0.0f));

    case kDocked:
      return OOJSValueFromBOOL(player != nullptr ? player->isDocked() : false);

    case kDockedStation:
      result =
          oo::EntityObjectNode(player != nullptr ? player->dockedStation()
                                                 : (StationEntity*)nullptr);
      break;

    case kSpecialCargo:
      result = StringOrNull(player != nullptr ? player->getSpecialCargo()
                                              : std::optional<std::string>());
      break;

    case kReticleColorTarget:
      result = NormalizedColorComponents(
          HudReticleColor(player, OO_RETICLE_COLOR_TARGET).get());
      break;

    case kReticleColorTargetSensitive:
      result = NormalizedColorComponents(
          HudReticleColor(player, OO_RETICLE_COLOR_TARGET_SENSITIVE).get());
      break;

    case kReticleColorWormhole:
      result = NormalizedColorComponents(
          HudReticleColor(player, OO_RETICLE_COLOR_WORMHOLE).get());
      break;

    case kReticleTargetSensitive:
      return OOJSValueFromBOOL(
          AskHud(player, &HeadUpDisplay::getReticleTargetSensitive));

    case kGalacticHyperspaceBehaviour:
      return OOJSValueFromGalacticHyperspaceBehaviour(
          context, (player != nullptr ? player->getGalacticHyperspaceBehaviour()
                                      : OOGalacticHyperspaceBehaviour{}));

    case kGalacticHyperspaceFixedCoords:
      OOJS_RETURN_WITH_HELPER(
          NSPointToVectorJSValue,
          (player != nullptr ? player->getGalacticHyperspaceFixedCoords()
                             : NSPoint{}));

    case kGalacticHyperspaceFixedCoordsInLY:
      OOJS_RETURN_VECTOR(OOGalacticCoordinatesFromInternal(
          player != nullptr ? player->getGalacticHyperspaceFixedCoords()
                            : NSPoint{}));

    case kFastEquipmentA:
      result = StringOrNull(player != nullptr ? player->fastEquipmentA()
                                              : std::optional<std::string>());
      break;

    case kFastEquipmentB:
      result = StringOrNull(player != nullptr ? player->fastEquipmentB()
                                              : std::optional<std::string>());
      break;

    case kPrimedEquipment:
      result = oo::PList(player != nullptr ? player->currentPrimedEquipment()
                                           : std::string());
      break;

    case kForwardShield:
      return JS_NewNumber(
          context, (player != nullptr ? player->forwardShieldLevel() : 0.0f));

    case kAftShield:
      return JS_NewNumber(
          context, (player != nullptr ? player->aftShieldLevel() : 0.0f));

    case kMaxForwardShield:
      return JS_NewNumber(
          context,
          (player != nullptr ? player->maxForwardShieldLevel() : 0.0f));

    case kMaxAftShield:
      return JS_NewNumber(
          context, (player != nullptr ? player->maxAftShieldLevel() : 0.0f));

    case kForwardShieldRechargeRate:
      // No distinction made internally
      return JS_NewNumber(
          context,
          (player != nullptr ? player->forwardShieldRechargeRate() : 0.0f));

    case kAftShieldRechargeRate:
      // No distinction made internally
      return JS_NewNumber(
          context,
          (player != nullptr ? player->aftShieldRechargeRate() : 0.0f));

    case kMultiFunctionDisplays:
      return JS_NewNumber(context, AskHud(player, &HeadUpDisplay::mfdCount));

    case kMultiFunctionDisplayList: {
      oo::PList::Array list;  // [OONull null] for an inactive MFD
      for (const std::optional<std::string>& key :
           (player != nullptr ? player->multiFunctionDisplayList()
                              : std::vector<std::optional<std::string>>())) {
        list.push_back(key.has_value() ? oo::PList(*key) : OONullObjectNode());
      }
      result = oo::PList(std::move(list));
    } break;

    case kMissilesOnline:
      return OOJSValueFromBOOL(
          !(player != nullptr ? player->dialIdentEngaged() : false));

    case kChartHightlightMode:
      result = oo::PList(cxx_OOStringFromLongRangeChartMode(
          player != nullptr ? player->getLongRangeChartMode()
                            : OOLongRangeChartMode{}));
      break;

    case kGalaxyCoordinates:
      OOJS_RETURN_WITH_HELPER(
          NSPointToVectorJSValue,
          (player != nullptr ? player->getGalaxy_coordinates() : NSPoint{}));

    case kGalaxyCoordinatesInLY:
      OOJS_RETURN_VECTOR(OOGalacticCoordinatesFromInternal(
          player != nullptr ? player->getGalaxy_coordinates() : NSPoint{}));

    case kCursorCoordinates:
      OOJS_RETURN_WITH_HELPER(
          NSPointToVectorJSValue,
          (player != nullptr ? player->getCursor_coordinates() : NSPoint{}));

    case kCursorCoordinatesInLY:
      OOJS_RETURN_VECTOR(OOGalacticCoordinatesFromInternal(
          player != nullptr ? player->getCursor_coordinates() : NSPoint{}));

    case kTargetSystem:
      return JS_NewInt32(context,
                         player != nullptr ? player->targetSystemID() : 0);

    case kNextSystem:
      return JS_NewInt32(
          context, player != nullptr ? player->nextHopTargetSystemID() : 0);

    case kInfoSystem:
      return JS_NewInt32(context,
                         player != nullptr ? player->infoSystemID() : 0);

    case kPreviousSystem:
      return JS_NewInt32(context,
                         player != nullptr ? player->previousSystemID() : 0);

    case kRouteMode: {
      OORouteType route =
          (player != nullptr ? player->ANAMode() : OORouteType{});
      switch (route) {
        case OORouteType::kTime:
          result = oo::PList("OPTIMIZED_BY_TIME");
          break;
        case OORouteType::kJumps:
          result = oo::PList("OPTIMIZED_BY_JUMPS");
          break;
        case OORouteType::kNone:
          result = oo::PList("OPTIMIZED_BY_NONE");
          break;
      }
      break;
    }

    case kScannerMinimalistic:
      return OOJSValueFromBOOL(
          AskHud(player, &HeadUpDisplay::minimalisticScanner));

    case kScannerNonLinear:
      return OOJSValueFromBOOL(
          AskHud(player, &HeadUpDisplay::nonlinearScanner));

    case kScannerUltraZoom:
      return OOJSValueFromBOOL(
          AskHud(player, &HeadUpDisplay::scannerUltraZoom));

    case kScoopOverride:
      return OOJSValueFromBOOL(player != nullptr ? player->getScoopOverride()
                                                 : false);

    case kInjectorsEngaged:
      return OOJSValueFromBOOL(player != nullptr ? player->injectorsEngaged()
                                                 : false);

    case kMassLockable:
      return OOJSValueFromBOOL(player != nullptr ? player->getMassLockable()
                                                 : false);

    case kTorusEngaged:
      return OOJSValueFromBOOL(player != nullptr ? player->hyperspeedEngaged()
                                                 : false);

    case kCompassTarget:
      result = oo::EntityObjectNode(
          player != nullptr
              ? player->getCompassTargetEntity()
              : (Entity*)nullptr);  // the C++ entity's node, the same object's
      break;

    case kCompassType:
      result = oo::PList(
          (cxx_OOStringFromCompassMode(
               player != nullptr ? player->getCompassMode()
                                 : OOCompassMode{}) == "COMPASS_MODE_BASIC")
              ? "OO_COMPASSTYPE_BASIC"
              : "OO_COMPASSTYPE_ADVANCED");
      break;

    case kCompassMode:
      return OOJSValueFromCompassMode(
          context,
          (player != nullptr ? player->getCompassMode() : OOCompassMode{}));

    case kHud:
      result = StringOrNull(AskHud(player, &HeadUpDisplay::getHudName));
      break;

    case kCrosshairs:
      result =
          StringOrNull(AskHud(player, &HeadUpDisplay::getCrosshairDefinition));
      break;

    case kHudAllowsBigGui:
      return OOJSValueFromBOOL(AskHud(player, &HeadUpDisplay::getAllowBigGui));

    case kHudHidden:
      return OOJSValueFromBOOL(AskHud(player, &HeadUpDisplay::isHidden));

    case kWeaponsOnline:
      return OOJSValueFromBOOL(player != nullptr ? player->weaponsOnline()
                                                 : false);

    case kViewDirection:
      return OOJSValueFromViewID(
          context,
          (UNIVERSE != nullptr ? UNIVERSE->getViewDirection() : OOViewID{}));

    case kViewPositionAft:
      OOJS_RETURN_VECTOR(
          (player != nullptr ? player->viewpointOffsetAft() : Vector{}));

    case kViewPositionForward:
      OOJS_RETURN_VECTOR(
          (player != nullptr ? player->viewpointOffsetForward() : Vector{}));

    case kViewPositionPort:
      OOJS_RETURN_VECTOR(
          (player != nullptr ? player->viewpointOffsetPort() : Vector{}));

    case kViewPositionStarboard:
      OOJS_RETURN_VECTOR(
          (player != nullptr ? player->viewpointOffsetStarboard() : Vector{}));

    case kCurrentWeapon:
      result = OOEquipmentTypeObjectNode(
          player != nullptr
              ? player->weaponTypeForFacing(
                    (player != nullptr ? player->getCurrentWeaponFacing()
                                       : OOWeaponFacing{}),
                    false)
              : (OOEquipmentType*)nullptr);
      break;

    case kPrice:
      return JS_NewNumber(
          context,
          (UNIVERSE != nullptr
               ? UNIVERSE->tradeInValueForCommanderDictionary(
                     (player != nullptr ? player->commanderDataDictionary()
                                        : oo::PList()))
               : 0));

    case kServiceLevel:
      return JS_NewNumber(
          context, (player != nullptr ? player->tradeInFactor() : int{}));

    case kRenovationCost:
      return JS_NewNumber(
          context, (player != nullptr ? player->renovationCosts() : 0.0));

    case kRenovationMultiplier:
      return JS_NewNumber(
          context, (player != nullptr ? player->renovationFactor() : 0.0));

      // make roll, pitch, yaw reported to JS use same +/- convention as
      // for NPC ships
    case kPitch:
      return JS_NewNumber(
          context, -(player != nullptr ? player->getFlightPitch() : 0.0f));

    case kRoll:
      return JS_NewNumber(
          context, -(player != nullptr ? player->getFlightRoll() : 0.0f));

    case kYaw:
      return JS_NewNumber(context,
                          -(player != nullptr ? player->getFlightYaw() : 0.0f));

    case kMessageGuiTextColor:
      result =
          NormalizedColorComponents(UNIVERSE->messageGUI()->getTextColor());
      break;

    case kMessageGuiTextCommsColor:
      result = NormalizedColorComponents(
          UNIVERSE->messageGUI()->getTextCommsColor());
      break;

    default:
      OOJSReportBadPropertySelector(context, thisObj, magic,
                                    sPlayerShipProperties,
                                    OOJS_COUNT(sPlayerShipProperties));
      return OOJSNativeFailure(context);
  }

  return OOJSValueFromPList(context, result);

  OOJS_NATIVE_EXIT
}

static JSValue PlayerShipSetProperty(OOJS_SETTER_ARGS) {
  OOJS_NATIVE_ENTER(context)

  if (EXPECT_NOT(OOIsPlayerStale())) return JS_UNDEFINED;

  PlayerEntity* player = OOPlayerForScripting();
  double fValue;
  int bValue;
  int32_t iValue;
  std::optional<std::string> sValue;
  OOGalacticHyperspaceBehaviour ghBehaviour;
  Vector vValue;
  oo::Ref<OOColor> colorForScript;  // the colours are converted (OOColor)
  Entity* eValue = nullptr;  // as JSValueToEntity() answers (the C++ entity)

  switch (static_cast<PlayerShipProperty>(magic)) {
    using enum PlayerShipProperty;
    case kFuelLeakRate:
      if (JS_ToFloat64(context, &fValue, value) == 0) {
        if (player != nullptr) player->setFuelLeakRate(fValue);
        return JS_UNDEFINED;
      }
      break;

    case kMassLockable:
      if ((bValue = JS_ToBool(context, value)) >= 0) {
        if (player != nullptr) player->setMassLockable(bValue);
        return JS_UNDEFINED;
      }
      break;

    case kReticleTargetSensitive:
      if ((bValue = JS_ToBool(context, value)) >= 0) {
        if (HeadUpDisplay* hud = HudOf(player))
          hud->setReticleTargetSensitive(bValue);
        return JS_UNDEFINED;
      }
      break;

    case kChartHightlightMode:
      sValue = cxx_OOStringFromJSValue(context, value);
      if (sValue.has_value()) {
        OOLongRangeChartMode chartMode =
            cxx_OOLongRangeChartModeFromString(sValue.value_or(""));
        if (chartMode > OOLongRangeChartMode::kUnknown) {
          if (player != nullptr) player->setLongRangeChartMode(chartMode);
          if (player != nullptr)
            player->doScriptEvent(
                OOJSID("chartHighlightModeChanged"),
                {oo::PList(cxx_OOStringFromLongRangeChartMode(
                    player != nullptr ? player->getLongRangeChartMode()
                                      : OOLongRangeChartMode{}))});
          return JS_UNDEFINED;
        } else {
          cxx_OOJSReportError(
              context,
              "Unknown chart hightlight mode specified - must be either "
              "OOLRC_MODE_SUNCOLOR, OOLRC_MODE_ECONOMY, OOLRC_MODE_GOVERNMENT "
              "or OOLRC_MODE_TECHLEVEL.");
        }
      }
      return OOJSNativeFailure(context);  // not reachable if successfully set
      break;

    case kCompassMode:
      sValue = cxx_OOStringFromJSValue(context, value);
      if (sValue.has_value()) {
        OOCompassMode mode = OOCompassModeFromJSValue(context, value);
        if (player != nullptr) player->setCompassMode(mode);
        if (player != nullptr) player->validateCompassTarget();
        return JS_UNDEFINED;
      }
      break;

    case kCompassType:
      sValue = cxx_OOStringFromJSValue(context, value);
      if (sValue.has_value()) {
        if (*sValue == "OO_COMPASSTYPE_BASIC") {
          if (player != nullptr) player->setCompassMode(OOCompassMode::kBasic);
        } else if (*sValue == "OO_COMPASSTYPE_ADVANCED") {
          if (!(player != nullptr
                    ? player->hasEquipmentItemProviding("EQ_ADVANCED_COMPASS")
                    : false)) {
            cxx_OOJSReportWarning(
                context,
                "Advanced Compass type requested and set but player ship does "
                "not carry the EQ_ADVANCED_COMPASS equipment or has it "
                "damaged.");
          }
          if (player != nullptr) player->setCompassMode(OOCompassMode::kPlanet);
        } else {
          cxx_OOJSReportError(
              context,
              "Unknown compass type specified - must be either "
              "OO_COMPASSTYPE_BASIC or OO_COMPASSTYPE_ADVANCED.");
          return OOJSNativeFailure(context);
        }
        return JS_UNDEFINED;
      }
      break;

    case kCompassTarget:
      // can't change compass target in basic mode
      if (!(player != nullptr
                ? player->hasEquipmentItemProviding("EQ_ADVANCED_COMPASS")
                : false)) {
        cxx_OOJSReportError(
            context, "Compass target cannot be set with a basic compass.");
        return OOJSNativeFailure(context);
      }
      // make sure we have a valid entity
      if (!JS_IsNull(value) && JSValueToEntity(context, value, &eValue)) {
        Entity* current = (player != nullptr ? player->getCompassTargetEntity()
                                             : nullptr);  // the C++ entities
        if (player != nullptr) player->setNextCompassMode();
        if (player != nullptr) player->validateCompassTarget();
        // cycle the targets until we either get back to the start (entity not
        // found) or we find the one we're looking for
        while ((player != nullptr ? player->getCompassTargetEntity()
                                  : nullptr) != current &&
               (player != nullptr ? player->getCompassTargetEntity()
                                  : nullptr) != eValue)  // the C++ entities
        {
          if (player != nullptr) player->setNextCompassMode();
          if (player != nullptr) player->validateCompassTarget();
        }
        // SpiderMonkey returned NO (stopping the script without an error) if
        // the target wasn't found.
        if ((player != nullptr ? player->getCompassTargetEntity() : nullptr) ==
            current)
          return OOJSNativeFailure(context);
        return JS_UNDEFINED;
      } else {
        cxx_OOJSReportError(context, "Invalid compass target entity provided.");
        return OOJSNativeFailure(context);
      }
      break;

    case kGalacticHyperspaceBehaviour:
      ghBehaviour = OOGalacticHyperspaceBehaviourFromJSValue(context, value);
      if (ghBehaviour != OOGalacticHyperspaceBehaviour::kUnknown) {
        if (player != nullptr)
          player->setGalacticHyperspaceBehaviour(ghBehaviour);
        return JS_UNDEFINED;
      }
      break;

    case kGalacticHyperspaceFixedCoords:
      if (JSValueToVector(context, value, &vValue)) {
        NSPoint coords = {vValue.x, vValue.y};
        if (player != nullptr) player->setGalacticHyperspaceFixedCoords(coords);
        return JS_UNDEFINED;
      }
      break;

    case kGalacticHyperspaceFixedCoordsInLY:
      if (JSValueToVector(context, value, &vValue)) {
        NSPoint coords = OOInternalCoordinatesFromGalactic(vValue);
        if (player != nullptr) player->setGalacticHyperspaceFixedCoords(coords);
        return JS_UNDEFINED;
      }
      break;

    case kFastEquipmentA:
      sValue = cxx_OOStringFromJSValue(context, value);
      if (sValue.has_value()) {
        if (player != nullptr) player->setFastEquipmentA(sValue);
        return JS_UNDEFINED;
      }
      break;

    case kFastEquipmentB:
      sValue = cxx_OOStringFromJSValue(context, value);
      if (sValue.has_value()) {
        if (player != nullptr) player->setFastEquipmentB(sValue);
        return JS_UNDEFINED;
      }
      break;

    case kPrimedEquipment:
      sValue = cxx_OOStringFromJSValue(context, value);
      if (sValue.has_value()) {
        // As before, failure stops the script without an error.
        if (!(player != nullptr ? player->setPrimedEquipment(*sValue, false)
                                : false))
          return OOJSNativeFailure(context);
        return JS_UNDEFINED;
      }
      break;

    case kPitch:
      if (JS_ToFloat64(context, &fValue, value) == 0) {
        if (!isnan(fValue))  // guard against undefined
        {
          if (player != nullptr)
            player->decrease_flight_pitch(
                ((player != nullptr ? player->getFlightPitch() : 0.0f) +
                 fValue));
        }
        return JS_UNDEFINED;
      }
      break;

    case kRoll:
      if (JS_ToFloat64(context, &fValue, value) == 0) {
        if (!isnan(fValue))  // guard against undefined
        {
          if (player != nullptr)
            player->decrease_flight_roll((
                (player != nullptr ? player->getFlightRoll() : 0.0f) + fValue));
        }
        return JS_UNDEFINED;
      }
      break;

    case kYaw:
      if (JS_ToFloat64(context, &fValue, value) == 0) {
        if (!isnan(fValue))  // guard against undefined
        {
          if (player != nullptr)
            player->decrease_flight_yaw(
                ((player != nullptr ? player->getFlightYaw() : 0.0f) + fValue));
        }
        return JS_UNDEFINED;
      }
      break;

    case kForwardShield:
      if (JS_ToFloat64(context, &fValue, value) == 0) {
        if (player != nullptr) player->setForwardShieldLevel(fValue);
        return JS_UNDEFINED;
      }
      break;

    case kAftShield:
      if (JS_ToFloat64(context, &fValue, value) == 0) {
        if (player != nullptr) player->setAftShieldLevel(fValue);
        return JS_UNDEFINED;
      }
      break;

    case kMaxForwardShield:
      if (JS_ToFloat64(context, &fValue, value) == 0) {
        if (player != nullptr) player->setMaxForwardShieldLevel(fValue);
        return JS_UNDEFINED;
      }
      break;

    case kMaxAftShield:
      if (JS_ToFloat64(context, &fValue, value) == 0) {
        if (player != nullptr) player->setMaxAftShieldLevel(fValue);
        return JS_UNDEFINED;
      }
      break;

    case kForwardShieldRechargeRate:
      if (JS_ToFloat64(context, &fValue, value) == 0) {
        if (player != nullptr) player->setForwardShieldRechargeRate(fValue);
        return JS_UNDEFINED;
      }
      break;

    case kAftShieldRechargeRate:
      if (JS_ToFloat64(context, &fValue, value) == 0) {
        if (player != nullptr) player->setAftShieldRechargeRate(fValue);
        return JS_UNDEFINED;
      }
      break;

    case kScannerMinimalistic:
      if ((bValue = JS_ToBool(context, value)) >= 0) {
        if (HeadUpDisplay* hud = HudOf(player))
          hud->setMinimalisticScanner(bValue);
        return JS_UNDEFINED;
      }
      break;

    case kScannerNonLinear:
      if ((bValue = JS_ToBool(context, value)) >= 0) {
        if (HeadUpDisplay* hud = HudOf(player))
          hud->setNonlinearScanner(bValue);
        return JS_UNDEFINED;
      }
      break;

    case kScannerUltraZoom:
      if ((bValue = JS_ToBool(context, value)) >= 0) {
        if (HeadUpDisplay* hud = HudOf(player))
          hud->setScannerUltraZoom(bValue);
        return JS_UNDEFINED;
      }
      break;

    case kScoopOverride:
      if ((bValue = JS_ToBool(context, value)) >= 0) {
        if (player != nullptr) player->setScoopOverride(bValue);
        return JS_UNDEFINED;
      }
      break;

    case kHud:
      sValue = cxx_OOStringFromJSValue(context, value);
      if (sValue.has_value()) {
        if (sValue.has_value() && player != nullptr)
          player->switchHudTo(
              *sValue);  // EMMSTRAN: logged error should be a JS warning.
        return JS_UNDEFINED;
      } else {
        if (player != nullptr) player->resetHud();
        return JS_UNDEFINED;
      }
      break;

    case kCrosshairs:
      sValue = cxx_OOStringFromJSValue(context, value);
      if (!sValue.has_value()) {
        // reset HUD back to its plist settings
        std::optional<std::string> hud = AskHud(
            player,
            &HeadUpDisplay::getHudName);  // a copy, as the retain kept it
        if (hud.has_value() && player != nullptr) player->switchHudTo(*hud);
        return JS_UNDEFINED;
      } else {
        if (!(HudOf(player) != nullptr &&
              HudOf(player)->setCrosshairDefinition(sValue.value_or("")))) {
          cxx_OOJSReportWarning(
              context, "Crosshair definition file %s not found or invalid",
              (sValue ? sValue->c_str() : "(null)"));
        }
        return JS_UNDEFINED;
      }
      break;

    case kHudHidden:
      if ((bValue = JS_ToBool(context, value)) >= 0) {
        if (HeadUpDisplay* hud = HudOf(player)) hud->setHidden(bValue);
        return JS_UNDEFINED;
      }
      break;

    case kServiceLevel:
      if (JS_ToFloat64(context, &fValue, value) == 0) {
        int newLevel = (int)fValue;
        if (player != nullptr)
          player->adjustTradeInFactorBy(
              (newLevel -
               (player != nullptr ? player->tradeInFactor() : int{})));
        return JS_UNDEFINED;
      }
      /*	The SpiderMonkey version fell through to currentWeapon here
         (which removed the current weapon) if the conversion threw. Report the
         bad value instead.
      */
      break;

    case kCurrentWeapon: {
      bool exists = false;  // JSValueToEquipmentKeyRelaxed() takes a bool *
      sValue = JSValueToEquipmentKeyRelaxed(context, value, &exists);
      if (!exists || !sValue.has_value()) {
        sValue = "EQ_WEAPON_NONE";
      }
      if (player != nullptr)
        player->setWeaponMount(player->getCurrentWeaponFacing(),
                               sValue.value_or(""), "scripted");
      return JS_UNDEFINED;
    }

    case kTargetSystem:
      /* This first check is essential: if removed, it would be
       * possible to make jumps of arbitrary length - CIM */
      if ((player != nullptr ? player->status() : OOEntityStatus{}) !=
          OOEntityStatus::kEnteringWitchspace) {
        /* These checks though similar are less important. The
         * consequences of allowing jump destination to be set in
         * flight are not as severe and do not allow the 7LY limit to
         * be broken. Nevertheless, it is not allowed. - CIM */
        // (except when compiled in debugging mode)
#ifndef OO_DUMP_PLANETINFO
        if (EXPECT_NOT(
                (player != nullptr ? player->status() : OOEntityStatus{}) !=
                    OOEntityStatus::kDocked &&
                (player != nullptr ? player->status() : OOEntityStatus{}) !=
                    OOEntityStatus::kLaunching)) {
          cxx_OOJSReportError(context,
                              "player.ship.targetSystem is read-only unless "
                              "called when docked.");
          return OOJSNativeFailure(context);
        }
#endif

        if (OOJSValueToInt32(context, value, &iValue)) {
          if (iValue >= 0 && iValue < OO_SYSTEMS_PER_GALAXY) {
            if (player != nullptr) player->setTargetSystemID(iValue);
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
        cxx_OOJSReportError(
            context,
            "player.ship.targetSystem is read-only unless called when docked.");
        return OOJSNativeFailure(context);
      }

    case kInfoSystem:
      if (OOJSValueToInt32(context, value, &iValue)) {
        if (iValue >= 0 && iValue < OO_SYSTEMS_PER_GALAXY) {
          if (player != nullptr) player->setInfoSystemID(iValue, true);
          return JS_UNDEFINED;
        } else {
          return OOJSNativeFailure(context);
        }
      }
      break;

    case kMessageGuiTextColor:
      colorForScript = OOColor::colorWithDescription(
          cxx_OOJSPListFromJSValue(context, value));
      if (colorForScript != nullptr || JS_IsNull(value)) {
        UNIVERSE->messageGUI()->setTextColor(colorForScript.get());
        return JS_UNDEFINED;
      }
      break;

    case kMessageGuiTextCommsColor:
      colorForScript = OOColor::colorWithDescription(
          cxx_OOJSPListFromJSValue(context, value));
      if (colorForScript != nullptr || JS_IsNull(value)) {
        UNIVERSE->messageGUI()->setTextCommsColor(colorForScript.get());
        return JS_UNDEFINED;
      }
      break;

    case kReticleColorTarget:
      colorForScript = OOColor::colorWithDescription(
          cxx_OOJSPListFromJSValue(context, value));
      if (colorForScript != nullptr || JS_IsNull(value)) {
        if (!(HudOf(player) != nullptr &&
              HudOf(player)->setReticleColorForIndex(OO_RETICLE_COLOR_TARGET,
                                                     colorForScript.get())))
          return OOJSNativeFailure(context);
        return JS_UNDEFINED;
      }
      break;

    case kReticleColorTargetSensitive:
      colorForScript = OOColor::colorWithDescription(
          cxx_OOJSPListFromJSValue(context, value));
      if (colorForScript != nullptr || JS_IsNull(value)) {
        if (!(HudOf(player) != nullptr &&
              HudOf(player)->setReticleColorForIndex(
                  OO_RETICLE_COLOR_TARGET_SENSITIVE, colorForScript.get())))
          return OOJSNativeFailure(context);
        return JS_UNDEFINED;
      }
      break;

    case kReticleColorWormhole:
      colorForScript = OOColor::colorWithDescription(
          cxx_OOJSPListFromJSValue(context, value));
      if (colorForScript != nullptr || JS_IsNull(value)) {
        if (!(HudOf(player) != nullptr &&
              HudOf(player)->setReticleColorForIndex(OO_RETICLE_COLOR_WORMHOLE,
                                                     colorForScript.get())))
          return OOJSNativeFailure(context);
        return JS_UNDEFINED;
      }
      break;

    default:
      OOJSReportBadPropertySelector(context, thisObj, magic,
                                    sPlayerShipProperties,
                                    OOJS_COUNT(sPlayerShipProperties));
      return OOJSNativeFailure(context);
  }

  OOJSReportBadPropertyValue(context, thisObj, magic, sPlayerShipProperties,
                             OOJS_COUNT(sPlayerShipProperties), value);
  return OOJSNativeFailure(context);

  OOJS_NATIVE_EXIT
}

// *** Methods ***

// launch()
static JSValue PlayerShipLaunch(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  if (EXPECT_NOT(OOIsPlayerStale())) OOJS_RETURN_VOID;

  if (PlayerEntity* player = OOPlayerForScripting())
    player->launchFromStation();
  OOJS_RETURN_VOID;

  OOJS_NATIVE_EXIT
}

// removeAllCargo()
static JSValue PlayerShipRemoveAllCargo(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  if (EXPECT_NOT(OOIsPlayerStale())) OOJS_RETURN_VOID;

  PlayerEntity* player = OOPlayerForScripting();

  if ((player != nullptr ? player->isDocked() : false)) {
    if (player != nullptr) player->removeAllCargo();
    OOJS_RETURN_VOID;
  } else {
    cxx_OOJSReportError(context,
                        "PlayerShip.removeAllCargo only works when docked.");
    return OOJSNativeFailure(context);
  }

  OOJS_NATIVE_EXIT
}

// useSpecialCargo(name : String)
static JSValue PlayerShipUseSpecialCargo(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  if (EXPECT_NOT(OOIsPlayerStale())) OOJS_RETURN_VOID;

  PlayerEntity* player = OOPlayerForScripting();
  std::optional<std::string> name;

  if (argc > 0) name = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
  if (EXPECT_NOT(!name.has_value())) {
    cxx_OOJSReportBadArguments(context, "PlayerShip", "useSpecialCargo",
                               MIN(argc, 1), OOJS_ARGV, std::nullopt,
                               "string (special cargo description)");
    return OOJSNativeFailure(context);
  }

  if (player != nullptr)
    player->useSpecialCargo(cxx_OOStringFromJSValue(context, OOJS_ARGV[0])
                                .value_or(std::string()));  // (nil was "")
  OOJS_RETURN_VOID;

  OOJS_NATIVE_EXIT
}

// engageAutopilotToStation(stationForDocking : Station) : Boolean
static JSValue PlayerShipEngageAutopilotToStation(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  if (EXPECT_NOT(OOIsPlayerStale())) OOJS_RETURN_VOID;

  PlayerEntity* player = OOPlayerForScripting();
  StationEntity* stationForDocking = nullptr;

  if (argc > 0)
    stationForDocking = oo::ToStation(OOJSEntityFromJSValue(
        context, OOJS_ARGV[0]));  // a station's object is a ship's
  if (stationForDocking == nullptr) {
    cxx_OOJSReportBadArguments(context, "PlayerShip", "engageAutopilot",
                               MIN(argc, 1), OOJS_ARGV, std::nullopt,
                               "station");
    return OOJSNativeFailure(context);
  }

  OOJS_RETURN_BOOL(player != nullptr
                       ? player->engageAutopilotToStation(stationForDocking)
                       : false);

  OOJS_NATIVE_EXIT
}

// disengageAutopilot()
static JSValue PlayerShipDisengageAutopilot(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  if (EXPECT_NOT(OOIsPlayerStale())) OOJS_RETURN_VOID;

  if (PlayerEntity* player = OOPlayerForScripting())
    player->disengageAutopilot();
  OOJS_RETURN_VOID;

  OOJS_NATIVE_EXIT
}

static JSValue PlayerShipRequestDockingClearance(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  if (EXPECT_NOT(OOIsPlayerStale())) OOJS_RETURN_VOID;

  PlayerEntity* player = OOPlayerForScripting();
  StationEntity* stationForDocking = nullptr;

  if (argc > 0)
    stationForDocking = oo::ToStation(OOJSEntityFromJSValue(
        context, OOJS_ARGV[0]));  // a station's object is a ship's
  if (stationForDocking == nullptr) {
    cxx_OOJSReportBadArguments(context, "PlayerShip", "requestDockingClearance",
                               MIN(argc, 1), OOJS_ARGV, std::nullopt,
                               "station");
    return OOJSNativeFailure(context);
  }

  if (player != nullptr) player->requestDockingClearance(stationForDocking);
  OOJS_RETURN_VOID;

  OOJS_NATIVE_EXIT
}

static JSValue PlayerShipCancelDockingRequest(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  if (EXPECT_NOT(OOIsPlayerStale())) OOJS_RETURN_VOID;

  PlayerEntity* player = OOPlayerForScripting();
  StationEntity* stationForDocking = nullptr;

  if (argc > 0)
    stationForDocking = oo::ToStation(OOJSEntityFromJSValue(
        context, OOJS_ARGV[0]));  // a station's object is a ship's
  if (stationForDocking == nullptr) {
    cxx_OOJSReportBadArguments(context, "PlayerShip", "cancelDockingRequest",
                               MIN(argc, 1), OOJS_ARGV, std::nullopt,
                               "station");
    return OOJSNativeFailure(context);
  }

  if (player != nullptr) player->cancelDockingRequest(stationForDocking);
  OOJS_RETURN_VOID;

  OOJS_NATIVE_EXIT
}

// awardEquipmentToCurrentPylon(externalTank: equipmentInfoExpression) : Boolean
static JSValue PlayerShipAwardEquipmentToCurrentPylon(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  if (EXPECT_NOT(OOIsPlayerStale())) OOJS_RETURN_VOID;

  PlayerEntity* player = OOPlayerForScripting();
  std::optional<std::string> key;
  oo::Ref<OOEquipmentType>
      eqType;  // the equipment types are converted (OOEquipmentType)

  if (argc > 0) key = JSValueToEquipmentKey(context, OOJS_ARGV[0]);
  if (key.has_value())
    eqType = OOEquipmentType::equipmentTypeWithIdentifier(*key);
  if (EXPECT_NOT(!(eqType != nullptr && eqType->isMissileOrMine()))) {
    cxx_OOJSReportBadArguments(
        context, "PlayerShip", "awardEquipmentToCurrentPylon", MIN(argc, 1),
        OOJS_ARGV, std::nullopt, "equipment type (external store)");
    return OOJSNativeFailure(context);
  }

  OOJS_RETURN_BOOL(player != nullptr
                       ? player->assignToActivePylon(key.value_or(""))
                       : false);

  OOJS_NATIVE_EXIT
}

// addPassenger(name: string, start: int, destination: int, ETA: double, fee:
// double) : Boolean
static JSValue PlayerShipAddPassenger(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  PlayerEntity* player = OOPlayerForScripting();
  std::optional<std::string> name;
  OOSystemID start = 0, destination = 0;
  double eta = 0.0, fee = 0.0, advance = 0.0;
  unsigned risk = 0;

  if (argc < 5) {
    cxx_OOJSReportBadArguments(context, "PlayerShip", "addPassenger", argc,
                               OOJS_ARGV, std::nullopt,
                               "name, start, destination, ETA, fee");
    return OOJSNativeFailure(context);
  }

  name = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
  if (EXPECT_NOT(!name.has_value())) {
    cxx_OOJSReportBadArguments(context, "PlayerShip", "addPassenger", 1,
                               &OOJS_ARGV[0], std::nullopt, "string");
    return OOJSNativeFailure(context);
  }

  if (!ValidateContracts(context, argc, OOJS_ARGV, false, &start, &destination,
                         &eta, &fee, &advance, "addPassenger", &risk))
    return OOJSNativeFailure(
        context);  // always go through validate contracts (passenger)

  // Ensure there's space.
  if ((player != nullptr ? player->passengerCount() : 0) >=
      (player != nullptr ? player->passengerCapacity() : 0))
    OOJS_RETURN_BOOL(false);

  bool OK = (player != nullptr
                 ? player->addPassenger(name.value_or(""), start, destination,
                                        eta, fee, advance, risk)
                 : false);
  OOJS_RETURN_BOOL(OK);

  OOJS_NATIVE_EXIT
}

// removePassenger(name :string)
static JSValue PlayerShipRemovePassenger(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  PlayerEntity* player = OOPlayerForScripting();
  std::optional<std::string> name;
  bool OK = true;

  if (argc > 0) name = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
  if (EXPECT_NOT(!name.has_value())) {
    cxx_OOJSReportBadArguments(context, "PlayerShip", "removePassenger",
                               MIN(argc, 1), OOJS_ARGV, std::nullopt, "string");
    return OOJSNativeFailure(context);
  }

  OK = (player != nullptr ? player->passengerCount() : 0) > 0 && !name->empty();
  if (OK)
    OK = (player != nullptr ? player->removePassenger(name.value_or(""))
                            : false);

  OOJS_RETURN_BOOL(OK);

  OOJS_NATIVE_EXIT
}

// addParcel(description: string, start: int, destination: int, ETA: double,
// fee: double) : Boolean
static JSValue PlayerShipAddParcel(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  PlayerEntity* player = OOPlayerForScripting();
  std::optional<std::string> name;
  OOSystemID start = 0, destination = 0;
  double eta = 0.0, fee = 0.0, premium = 0.0;
  unsigned risk = 0;

  if (argc < 5) {
    cxx_OOJSReportBadArguments(context, "PlayerShip", "addParcel", argc,
                               OOJS_ARGV, std::nullopt,
                               "name, start, destination, ETA, fee");
    return OOJSNativeFailure(context);
  }

  name = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
  if (EXPECT_NOT(!name.has_value())) {
    cxx_OOJSReportBadArguments(context, "PlayerShip", "addParcel", 1,
                               &OOJS_ARGV[0], std::nullopt, "string");
    return OOJSNativeFailure(context);
  }

  if (!ValidateContracts(context, argc, OOJS_ARGV, false, &start, &destination,
                         &eta, &fee, &premium, "addParcel", &risk))
    return OOJSNativeFailure(context);  // always go through validate contracts
                                        // (passenger/parcel mode)

  // Ensure there's space.

  bool OK = (player != nullptr
                 ? player->addParcel(name.value_or(""), start, destination, eta,
                                     fee, premium, risk)
                 : false);
  OOJS_RETURN_BOOL(OK);

  OOJS_NATIVE_EXIT
}

// removeParcel(description :string)
static JSValue PlayerShipRemoveParcel(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  PlayerEntity* player = OOPlayerForScripting();
  std::optional<std::string> name;
  bool OK = true;

  if (argc > 0) name = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
  if (EXPECT_NOT(!name.has_value())) {
    cxx_OOJSReportBadArguments(context, "PlayerShip", "removeParcel",
                               MIN(argc, 1), OOJS_ARGV, std::nullopt, "string");
    return OOJSNativeFailure(context);
  }

  OK = (player != nullptr ? player->parcelCount() : 0) > 0 && !name->empty();
  if (OK)
    OK = (player != nullptr ? player->removeParcel(name.value_or("")) : false);

  OOJS_RETURN_BOOL(OK);

  OOJS_NATIVE_EXIT
}

// awardContract(quantity: int, commodity: string, start: int, destination: int,
// eta: double, fee: double) : Boolean
static JSValue PlayerShipAwardContract(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  PlayerEntity* player = OOPlayerForScripting();
  std::optional<std::string> key;
  int32_t qty = 0;
  OOSystemID start = 0, destination = 0;
  double eta = 0.0, fee = 0.0, premium = 0.0;

  if (argc < 6) {
    cxx_OOJSReportBadArguments(
        context, "PlayerShip", "awardContract", argc, OOJS_ARGV, std::nullopt,
        "quantity, commodity, start, destination, ETA, fee");
    return OOJSNativeFailure(context);
  }

  if (!OOJSValueToInt32(context, OOJS_ARGV[0], &qty)) {
    cxx_OOJSReportBadArguments(context, "PlayerShip", "awardContract", 1,
                               &OOJS_ARGV[0], std::nullopt,
                               "positive integer (cargo quantity)");
    return OOJSNativeFailure(context);
  }

  key = cxx_OOStringFromJSValue(context, OOJS_ARGV[1]);
  if (EXPECT_NOT(!key.has_value())) {
    cxx_OOJSReportBadArguments(context, "PlayerShip", "awardContract", 1,
                               &OOJS_ARGV[1], std::nullopt,
                               "string (commodity identifier)");
    return OOJSNativeFailure(context);
  }

  if (!ValidateContracts(context, argc, OOJS_ARGV, true, &start, &destination,
                         &eta, &fee, &premium, "awardContract", nullptr))
    return OOJSNativeFailure(
        context);  // always go through validate contracts (cargo)

  bool OK =
      (player != nullptr ? player->awardContract(qty, key.value_or(""), start,
                                                 destination, eta, fee, premium)
                         : false);
  OOJS_RETURN_BOOL(OK);

  OOJS_NATIVE_EXIT
}

// removeContract(commodity: string, destination: int)
static JSValue PlayerShipRemoveContract(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  PlayerEntity* player = OOPlayerForScripting();
  std::optional<std::string> key;
  int32_t dest = 0;

  if (argc < 2) {
    cxx_OOJSReportBadArguments(context, "PlayerShip", "removeContract", argc,
                               OOJS_ARGV, std::nullopt,
                               "commodity, destination");
    return OOJSNativeFailure(context);
  }

  key = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);

  if (EXPECT_NOT(!key.has_value())) {
    cxx_OOJSReportBadArguments(context, "PlayerShip", "removeContract", 1,
                               &OOJS_ARGV[0], std::nullopt,
                               "string (commodity identifier)");
    return OOJSNativeFailure(context);
  }

  if (!OOJSValueToInt32(context, OOJS_ARGV[1], &dest) || dest < 0 ||
      dest > 255) {
    cxx_OOJSReportBadArguments(context, "PlayerShip", "removeContract", 1,
                               &OOJS_ARGV[1], std::nullopt, "system ID");
    return OOJSNativeFailure(context);
  }

  bool OK = (player != nullptr
                 ? player->removeContract(key.value_or(""), (unsigned)dest)
                 : false);
  OOJS_RETURN_BOOL(OK);

  OOJS_NATIVE_EXIT
}

// setCustomView(position:vector, orientation:quaternion [, weapon:string])
static JSValue PlayerShipSetCustomView(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  PlayerEntity* player = OOPlayerForScripting();

  if (argc < 2) {
    cxx_OOJSReportBadArguments(context, "PlayerShip", "setCustomView", argc,
                               OOJS_ARGV, std::nullopt,
                               "position, orientiation, [weapon]");
    return OOJSNativeFailure(context);
  }

  // must be in custom view
  if ((UNIVERSE != nullptr ? UNIVERSE->getViewDirection() : OOViewID{}) !=
      OOViewID::kCustom) {
    cxx_OOJSReportError(
        context,
        "PlayerShip.setCustomView only works when custom view is active.");
    return OOJSNativeFailure(context);
  }

  oo::PList::Dict viewData;

  Vector position = kZeroVector;
  bool gotpos = JSValueToVector(context, OOJS_ARGV[0], &position);
  if (!gotpos) {
    cxx_OOJSReportBadArguments(context, "PlayerShip", "setCustomView", argc,
                               OOJS_ARGV, std::nullopt,
                               "position, orientiation, [weapon]");
    return OOJSNativeFailure(context);
  }
  std::string positionstr =
      std::format("{:f} {:f} {:f}", position.x, position.y, position.z);

  Quaternion orientation = kIdentityQuaternion;
  bool gotquat = JSValueToQuaternion(context, OOJS_ARGV[1], &orientation);
  if (!gotquat) {
    cxx_OOJSReportBadArguments(context, "PlayerShip", "setCustomView", argc,
                               OOJS_ARGV, std::nullopt,
                               "position, orientiation, [weapon]");
    return OOJSNativeFailure(context);
  }
  std::string orientationstr =
      std::format("{:f} {:f} {:f} {:f}", orientation.w, orientation.x,
                  orientation.y, orientation.z);

  viewData["view_position"] = positionstr;
  viewData["view_orientation"] = orientationstr;

  if (argc > 2) {
    std::optional<std::string> facing =
        cxx_OOStringFromJSValue(context, OOJS_ARGV[2]);
    // -setObject:forKey: raised on a nil facing (GNUstep 1.31.1's text).
    if (!facing.has_value())
      OORaiseException(OOInvalidArgumentException,
                       "Tried to add nil value for key '%s' to dictionary",
                       "weapon_facing");
    viewData["weapon_facing"] = *facing;
  }

  if (player != nullptr)
    player->setCustomViewDataFromDictionary(oo::PList(std::move(viewData)),
                                            false);
  if (player != nullptr)
    player->noteSwitchToView(OOViewID::kCustom, OOViewID::kCustom);

  OOJS_RETURN_BOOL(true);
  OOJS_NATIVE_EXIT
}

// resetCustomView()
static JSValue PlayerShipResetCustomView(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  PlayerEntity* player = OOPlayerForScripting();

  // must be in custom view
  if ((UNIVERSE != nullptr ? UNIVERSE->getViewDirection() : OOViewID{}) !=
      OOViewID::kCustom) {
    cxx_OOJSReportError(
        context,
        "PlayerShip.setCustomView only works when custom view is active.");
    return OOJSNativeFailure(context);
  }

  if (player != nullptr) player->resetCustomView();
  if (player != nullptr)
    player->noteSwitchToView(OOViewID::kCustom, OOViewID::kCustom);

  OOJS_RETURN_BOOL(true);
  OOJS_NATIVE_EXIT
}

// resetScannerZoom()
static JSValue PlayerShipResetScannerZoom(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  PlayerEntity* player = OOPlayerForScripting();

  if (player != nullptr) player->resetScannerZoom();

  OOJS_RETURN_VOID;
  OOJS_NATIVE_EXIT
}

// takeInternalDamage()
static JSValue PlayerShipTakeInternalDamage(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  PlayerEntity* player = OOPlayerForScripting();

  bool took = (player != nullptr ? player->takeInternalDamage() : false);

  OOJS_RETURN_BOOL(took);
  OOJS_NATIVE_EXIT
}

// beginHyperspaceCountdown([int: spin_time])
static JSValue PlayerShipBeginHyperspaceCountdown(OOJS_NATIVE_ARGS) {
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
    if (!OOJSValueToInt32(context, OOJS_ARGV[0], &spin_time) || spin_time < 5 ||
        spin_time > 60) {
      cxx_OOJSReportBadArguments(context, "PlayerShip",
                                 "beginHyperspaceCountdown", 1, &OOJS_ARGV[0],
                                 std::nullopt, "between 5 and 60 seconds");
      return OOJSNativeFailure(context);
    }
    if (spin_time < 5) {
      witchspaceSpinUpTime = 5;
    } else {
      witchspaceSpinUpTime = spin_time;
    }
  }
  if ((player != nullptr ? player->hasHyperspaceMotor() : false) &&
      (player != nullptr ? player->status() : OOEntityStatus{}) ==
          OOEntityStatus::kInFlight &&
      (player != nullptr ? player->witchJumpChecklist(false) : false)) {
    if (player != nullptr)
      player->beginWitchspaceCountdown(witchspaceSpinUpTime);
    begun = true;
  }
  OOJS_RETURN_BOOL(begun);
  OOJS_NATIVE_EXIT
}

// cancelHyperspaceCountdown()
static JSValue PlayerShipCancelHyperspaceCountdown(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  PlayerEntity* player = OOPlayerForScripting();

  bool cancelled = false;
  if ((player != nullptr ? player->hasHyperspaceMotor() : false) &&
      (player != nullptr ? player->status() : OOEntityStatus{}) ==
          OOEntityStatus::kWitchspaceCountdown) {
    if (player != nullptr) player->cancelWitchspaceCountdown();
    if (player != nullptr) player->setJumpType(false);
    cancelled = true;
  }

  OOJS_RETURN_BOOL(cancelled);
  OOJS_NATIVE_EXIT
}

static JSValue PlayerShipBeginGalacticHyperspaceCountdown(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  PlayerEntity* player = OOPlayerForScripting();
  int32_t spin_time;
  int32_t witchspaceSpinUpTime = 5;
  bool begun = false;
  if (argc == 1) {
    if (!OOJSValueToInt32(context, OOJS_ARGV[0], &spin_time) || spin_time < 5 ||
        spin_time > 60) {
      cxx_OOJSReportBadArguments(
          context, "PlayerShip", "beginGalacticHyperspaceCountdown", 1,
          &OOJS_ARGV[0], std::nullopt, "between 5 and 60 seconds");
      return OOJSNativeFailure(context);
    }
    if (spin_time < 5) {
      witchspaceSpinUpTime = 5;
    } else {
      witchspaceSpinUpTime = spin_time;
    }
  }
  if ((player != nullptr ? player->hasEquipmentItemProviding("EQ_GAL_DRIVE")
                         : false) &&
      (player != nullptr ? player->status() : OOEntityStatus{}) ==
          OOEntityStatus::kInFlight &&
      (player != nullptr ? player->witchJumpChecklist(true) : false)) {
    if (player != nullptr) player->setJumpType(true);
    if (player != nullptr) player->setWitchspaceCountdown(witchspaceSpinUpTime);
    if (player != nullptr)
      player->setStatus(OOEntityStatus::kWitchspaceCountdown);
    if (player != nullptr) player->playGalacticHyperspace();
    // say it!
    if (UNIVERSE != nullptr)
      UNIVERSE->addMessage(
          oo::str::format(OO_DESC("witch-galactic-in-f-seconds").c_str(),
                          witchspaceSpinUpTime),
          1.0);
    begun = true;
  }
  OOJS_RETURN_BOOL(begun);
  OOJS_NATIVE_EXIT
}

// setMultiFunctionDisplay(index,key)
static JSValue PlayerShipSetMultiFunctionDisplay(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  std::optional<std::string> key;
  uint32_t index = 0;
  PlayerEntity* player = OOPlayerForScripting();
  bool OK = true;

  if (argc > 0) {
    if (JS_ToUint32(context, &index, OOJS_ARGV[0]) != 0) {
      cxx_OOJSReportBadArguments(
          context, "PlayerShip", "setMultiFunctionDisplay", MIN(argc, 1),
          OOJS_ARGV, std::nullopt, "number (index) [, string (key)]");
      return OOJSNativeFailure(context);
    }
  }

  if (argc > 1) {
    key = cxx_OOStringFromJSValue(context, OOJS_ARGV[1]);
  }

  OK =
      (player != nullptr ? player->setMultiFunctionDisplay(index, key) : false);

  OOJS_RETURN_BOOL(OK);

  OOJS_NATIVE_EXIT
}

// setMultiFunctionText(key,value)
static JSValue PlayerShipSetMultiFunctionText(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  std::optional<std::string> key;
  std::optional<std::string> value;
  PlayerEntity* player = OOPlayerForScripting();
  int reflow = false;

  if (argc > 0) {
    key = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
  }
  if (!key.has_value()) {
    cxx_OOJSReportBadArguments(context, "PlayerShip", "setMultiFunctionText",
                               MIN(argc, 1), OOJS_ARGV, std::nullopt,
                               "string (key) [, string (text)]");
    return OOJSNativeFailure(context);
  }
  if (argc > 1) {
    value = cxx_OOStringFromJSValue(context, OOJS_ARGV[1]);
  }
  if (argc > 2 && EXPECT_NOT((reflow = JS_ToBool(context, OOJS_ARGV[2])) < 0)) {
    cxx_OOJSReportBadArguments(context, "setMultiFunctionText", "reflow", argc,
                               OOJS_ARGV, std::nullopt, "boolean");
    return OOJSNativeFailure(context);
  }

  if (!reflow) {
    if (player != nullptr) player->setMultiFunctionText(value, key);
  } else {
    GuiDisplayGen* gui = (UNIVERSE != nullptr ? UNIVERSE->getGui() : nullptr);
    if (player != nullptr)
      player->setMultiFunctionText(gui->reflowTextForMFD(value), key);
  }

  OOJS_RETURN_VOID;

  OOJS_NATIVE_EXIT
}

// setPrimedEquipment(key, [noMessage])
static JSValue PlayerShipSetPrimedEquipment(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  std::optional<std::string> key;
  PlayerEntity* player = OOPlayerForScripting();
  int showMsg = true;

  if (argc > 0) {
    key = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
  }
  if (!key.has_value()) {
    cxx_OOJSReportBadArguments(context, "PlayerShip", "setPrimedEquipment",
                               MIN(argc, 1), OOJS_ARGV, std::nullopt,
                               "string (key)");
    return OOJSNativeFailure(context);
  }
  if (argc > 1 &&
      EXPECT_NOT((showMsg = JS_ToBool(context, OOJS_ARGV[1])) < 0)) {
    cxx_OOJSReportBadArguments(context, "PlayerShip", "setPrimedEquipment",
                               MIN(argc, 2), OOJS_ARGV, std::nullopt,
                               "boolean");
    return OOJSNativeFailure(context);
  }

  OOJS_RETURN_BOOL(key.has_value()
                       ? (player != nullptr
                              ? player->setPrimedEquipment(*key, showMsg)
                              : false)
                       : false);

  OOJS_NATIVE_EXIT
}

// setCustomHUDDial(key,value)
static JSValue PlayerShipSetCustomHUDDial(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  std::optional<std::string> key;
  oo::PList value;
  PlayerEntity* player = OOPlayerForScripting();

  if (argc > 0) {
    key = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
  }
  if (!key.has_value()) {
    cxx_OOJSReportBadArguments(context, "PlayerShip", "setCustomHUDDial",
                               MIN(argc, 1), OOJS_ARGV, std::nullopt,
                               "string (key), value]");
    return OOJSNativeFailure(context);
  }
  if (argc > 1) {
    value = cxx_OOJSPListFromJSValue(context, OOJS_ARGV[1]);
  } else {
    value = oo::PList(std::string());
  }

  if (player != nullptr) player->setDialCustom(value, key.value_or(""));

  OOJS_RETURN_VOID;

  OOJS_NATIVE_EXIT
}

static JSValue PlayerShipHideHUDSelector(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  std::optional<std::string> key;
  PlayerEntity* player = OOPlayerForScripting();

  if (argc > 0) {
    key = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
  }
  if (!key.has_value()) {
    cxx_OOJSReportBadArguments(context, "PlayerShip", "hideHUDSelector",
                               MIN(argc, 1), OOJS_ARGV, std::nullopt,
                               "string (selector)");
    return OOJSNativeFailure(context);
  }
  if (HeadUpDisplay* hud = HudOf(player))
    hud->setHiddenSelector(key.value_or(""), true);

  OOJS_RETURN_VOID;

  OOJS_NATIVE_EXIT
}

static JSValue PlayerShipShowHUDSelector(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  std::optional<std::string> key;
  PlayerEntity* player = OOPlayerForScripting();

  if (argc > 0) {
    key = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
  }
  if (!key.has_value()) {
    cxx_OOJSReportBadArguments(context, "PlayerShip", "hideHUDSelector",
                               MIN(argc, 1), OOJS_ARGV, std::nullopt,
                               "string (selector)");
    return OOJSNativeFailure(context);
  }
  if (HeadUpDisplay* hud = HudOf(player))
    hud->setHiddenSelector(key.value_or(""), false);

  OOJS_RETURN_VOID;

  OOJS_NATIVE_EXIT
}

static bool ValidateContracts(JSContext* context, int argc, JSValueConst* argv,
                              bool isCargo, OOSystemID* start,
                              OOSystemID* destination, double* eta, double* fee,
                              double* premium, const std::string& functionName,
                              unsigned* risk) {
  OOJS_PROFILE_ENTER

  OOCParameterAssert(context != nullptr && argv != nullptr &&
                     start != nullptr && destination != nullptr &&
                     eta != nullptr && fee != nullptr);

  uint32_t uValue;
  int offset = isCargo ? 2 : 1;
  double fValue;
  int32_t iValue;

  if (!OOJSValueToInt32(context, argv[offset + 0], &iValue) || iValue < 0 ||
      iValue > kOOMaximumSystemID) {
    cxx_OOJSReportBadArguments(context, "PlayerShip", functionName, 1,
                               &argv[offset + 0], std::nullopt, "system ID");
    return false;
  }
  *start = iValue;

  if (!OOJSValueToInt32(context, argv[offset + 1], &iValue) || iValue < 0 ||
      iValue > kOOMaximumSystemID) {
    cxx_OOJSReportBadArguments(context, "PlayerShip", functionName, 1,
                               &argv[offset + 1], std::nullopt, "system ID");
    return false;
  }
  *destination = iValue;

  if (JS_ToFloat64(context, &fValue, argv[offset + 2]) != 0 ||
      !isfinite(fValue) ||
      fValue <= (PLAYER != nullptr ? PLAYER->clockTime() : 0.0)) {
    cxx_OOJSReportBadArguments(context, "PlayerShip", functionName, 1,
                               &argv[offset + 2], std::nullopt,
                               "number (future time)");
    return false;
  }
  *eta = fValue;

  if (JS_ToFloat64(context, &fValue, argv[offset + 3]) != 0 ||
      !isfinite(fValue) || fValue < 0.0) {
    cxx_OOJSReportBadArguments(context, "PlayerShip", functionName, 1,
                               &argv[offset + 3], std::nullopt,
                               "number (credits quantity)");
    return false;
  }
  *fee = fValue;

  // Optional arguments: as before, invalid values are ignored. Don't leave a
  // conversion error pending.
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
