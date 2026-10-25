/*

OOJSPlayerShip.h

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
#include "OOJSPlayer.h"
#include "OOJSEntity.h"
#include "OOJSShip.h"
#include "OOJSVector.h"
#include "OOJSQuaternion.h"
#include "OOJavaScriptEngine.h"
#include "EntityOOJavaScriptExtensions.h"
#include "OOSystemDescriptionManager.h"
#include "PlayerEntity.h"
#include "PlayerEntityControls.h"
#include "PlayerEntityContracts.h"
#include "PlayerEntityScriptMethods.h"
#include "PlayerEntityLegacyScriptEngine.h"
#include "PlayerEntitySound.h"
#include "HeadUpDisplay.h"
#include "StationEntity.h"

#include "OOConstToJSString.h"
#include "OOConstToString.h"
#include "OOFunctionAttributes.h"
#include "OOEquipmentType.h"
#include "OOJSEquipmentInfo.h"
#include "GuiDisplayGen.h"
#include "Universe.h"

#include "ooscript/JSEngine.hpp"
#include <cstring>
#include "oofnd/Notification.hpp"
#include "oofnd/objc/OOAssert.h"
#include "oofnd/objc/OOException.h"
#include "OOObjCPList.h"
#include "oofnd/String.hpp"

/*
	Retargeted onto the ooscript façade (JSEngine.hpp) the way OOJSVector.mm does it (bead
	oo-sdz, the sweep exemplar): the class dispatch table becomes a static ooscript::ClassDef
	(the stub hooks are nullptr), InitClass/DefineObject become ooscript::initClass /
	ooscript::defineObject, native methods and class hooks take the façade's hook signature
	(Context/Object/PropertyId/Value pointer/CallArgs reference), and the directly spelled
	numeric-conversion calls (NewNumberValue, ValueToNumber, ValueToBoolean, ValueToInt32,
	ValueToECMAUint32, SetPrivate, RemoveObjectRoot) become their ooscript:: façade
	equivalents. Natives take the
	façade signature directly (ooscript::Context and a CallArgs reference) and the OOJS_*
	argument-marshalling macros expand to the CallArgs accessors, so the rest of each function
	body is UNCHANGED. `this` is renamed to `thisObj` because it
	is a reserved word once this file compiles as Objective-C++ (ADR-0001).
*/
namespace ooscript { }
using ooscript::Context;
using ooscript::Object;
using ooscript::Value;
using ooscript::PropertyId;
using ooscript::CallArgs;
using ooscript::ClassDef;
using ooscript::ClassFlag;
using ooscript::PropertyFlag;
using ooscript::PropertySpec;
using ooscript::FunctionSpec;

// Byte-identical façade <-> jsapi views, local to this call site (see OOJSVector.mm).
namespace {
static inline Object    *OOJSFOBJP(ooscript::Object *o)  { return reinterpret_cast<Object*>(o); }
} // namespace


namespace {
static ooscript::Object sPlayerShipPrototype;
} // namespace
namespace {
static ooscript::Object sPlayerShipObject;
} // namespace


namespace {

namespace {

// A colour's components as its -normalizedArray gave them to JavaScript: floats, null for no colour.
oo::PList NormalizedColorComponents(OOColor *color)
{
	if (color == nullptr)  return oo::PList();
	oo::PList::Array components;
	for (float component : color->normalizedArray())  components.push_back(oo::PList::singleReal(component));
	return oo::PList(std::move(components));
}


/*	The player's HUD is converted (HeadUpDisplay), and the player answers its facade. A
	player with no HUD answered zero, false, nil or none to every message the getter sent the HUD;
	so does a null HUD here (ADR-0056 amendments oo-6ia4 item 2, oo-nge8 item 6).
*/
template <typename R>
R AskHud(PlayerEntity *player, R (HeadUpDisplay::*member)())
{
	HeadUpDisplay *hud = (player != nullptr ? player->getHud() : (HeadUpDisplay *)nullptr);
	return (hud != nullptr) ? (hud->*member)() : R();
}


HeadUpDisplay *HudOf(PlayerEntity *player)
{
	return (player != nullptr ? player->getHud() : (HeadUpDisplay *)nullptr);
}


oo::Ref<OOColor> HudReticleColor(PlayerEntity *player, NSUInteger idx)
{
	HeadUpDisplay *hud = (player != nullptr ? player->getHud() : (HeadUpDisplay *)nullptr);
	return (hud != nullptr) ? hud->reticleColorForIndex(idx) : oo::Ref<OOColor>();
}

// A string, or null for none (what an NSString or nil gave JavaScript).
oo::PList StringOrNull(const std::optional<std::string> &string)
{
	return string.has_value() ? oo::PList(*string) : oo::PList();
}

}	// namespace


static bool PlayerShipGetProperty(Context cx, Object obj, PropertyId propID, Value *value);
} // namespace
namespace {
static bool PlayerShipSetProperty(Context cx, Object obj, PropertyId propID, bool strict, Value *value);
} // namespace

namespace {
static bool PlayerShipLaunch(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace
namespace {
static bool PlayerShipRemoveAllCargo(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace
namespace {
static bool PlayerShipUseSpecialCargo(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace
namespace {
static bool PlayerShipEngageAutopilotToStation(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace
namespace {
static bool PlayerShipDisengageAutopilot(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace
namespace {
static bool PlayerShipRequestDockingClearance(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace
namespace {
static bool PlayerShipCancelDockingRequest(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace
namespace {
static bool PlayerShipAwardEquipmentToCurrentPylon(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace
namespace {
static bool PlayerShipAddPassenger(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace
namespace {
static bool PlayerShipRemovePassenger(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace
namespace {
static bool PlayerShipAddParcel(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace
namespace {
static bool PlayerShipRemoveParcel(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace
namespace {
static bool PlayerShipAwardContract(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace
namespace {
static bool PlayerShipRemoveContract(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace
namespace {
static bool PlayerShipSetCustomView(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace
namespace {
static bool PlayerShipSetPrimedEquipment(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace
namespace {
static bool PlayerShipResetCustomView(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace
namespace {
static bool PlayerShipResetScannerZoom(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace
namespace {
static bool PlayerShipTakeInternalDamage(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace
namespace {
static bool PlayerShipBeginHyperspaceCountdown(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace
namespace {
static bool PlayerShipCancelHyperspaceCountdown(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace
namespace {
static bool PlayerShipBeginGalacticHyperspaceCountdown(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace
namespace {
static bool PlayerShipSetMultiFunctionDisplay(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace
namespace {
static bool PlayerShipSetMultiFunctionText(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace
namespace {
static bool PlayerShipHideHUDSelector(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace
namespace {
static bool PlayerShipShowHUDSelector(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace
namespace {
static bool PlayerShipSetCustomHUDDial(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace

namespace {
static bool ValidateContracts(ooscript::Context context, ooscript::CallArgs &oojsArgs, bool isCargo, OOSystemID *start, OOSystemID *destination, double *eta, double *fee, double *premium, const std::string &functionName, unsigned *risk);
} // namespace


namespace {
static ClassDef sPlayerShipClass =
{
	"PlayerShip",
	ClassFlag::HasPrivate,
	
	nullptr,				// addProperty (engine default: PropertyStub)
	nullptr,				// delProperty (engine default: PropertyStub)
	PlayerShipGetProperty,	// getProperty
	PlayerShipSetProperty,	// setProperty
	nullptr,				// enumerate (engine default: EnumerateStub)
	nullptr,				// newEnumerate (ooscript::ClassFlag::NewEnumerate not used)
	nullptr,				// resolve (engine default: ResolveStub)
	nullptr,				// convert (engine default: ConvertStub)
	OOJSCxxObjectWrapperFinalize,		// finalize
	nullptr,				// call
	nullptr,				// construct
	nullptr,				// backend: owned by the façade backend, must start null
};
} // namespace


enum : std::uint8_t
{
	// Property IDs
	kPlayerShip_activeMissile,                  // index in 'missiles' array of current active missile
	kPlayerShip_aftShield,						// aft shield charge level, nonnegative float, read/write
	kPlayerShip_aftShieldRechargeRate,			// aft shield recharge rate, positive float, read-only
	kPlayerShip_chartHightlightMode,            // what type of information is being shown on the chart
	kPlayerShip_compassMode,					// compass mode, string, read/write
	kPlayerShip_compassTarget,					// object targeted by the compass, entity, read/write
	kPlayerShip_compassType,					// basic / advanced, string, read/write
	kPlayerShip_currentWeapon,					// shortcut property to _aftWeapon, etc. overrides kShip generic version
	kPlayerShip_crosshairs,						// custom plist file defining crosshairs
	kPlayerShip_cursorCoordinates,				// cursor coordinates (unscaled), Vector3D, read only
	kPlayerShip_cursorCoordinatesInLY,			// cursor coordinates (in LY), Vector3D, read only
	kPlayerShip_docked,							// docked, boolean, read-only
	kPlayerShip_dockedStation,					// docked station, entity, read-only
	kPlayerShip_fastEquipmentA,					// fast equipment A, string, read/write
	kPlayerShip_fastEquipmentB,					// fast equipment B, string, read/write
	kPlayerShip_forwardShield,					// forward shield charge level, nonnegative float, read/write
	kPlayerShip_forwardShieldRechargeRate,		// forward shield recharge rate, positive float, read-only
	kPlayerShip_fuelLeakRate,					// fuel leak rate, float, read/write
	kPlayerShip_galacticHyperspaceBehaviour,	// can be standard, all systems reachable or fixed coordinates, integer, read-only
	kPlayerShip_galacticHyperspaceFixedCoords,	// used when fixed coords behaviour is selected, Vector3D, read/write
	kPlayerShip_galacticHyperspaceFixedCoordsInLY,	// used when fixed coords behaviour is selected, Vector3D, read/write
	kPlayerShip_galaxyCoordinates,				// galaxy coordinates (unscaled), Vector3D, read only
	kPlayerShip_galaxyCoordinatesInLY,			// galaxy coordinates (in LY), Vector3D, read only
	kPlayerShip_hud,							// hud name identifier, string, read/write
	kPlayerShip_hudAllowsBigGui,				// hud big gui, string, read only
	kPlayerShip_hudHidden,						// hud visibility, boolean, read/write
	kPlayerShip_injectorsEngaged,				// injectors in use, boolean, read-only
	kPlayerShip_massLockable,					// mass-lockability of player ship, read/write
	kPlayerShip_maxAftShield,					// maximum aft shield charge level, positive float, read-only
	kPlayerShip_maxForwardShield,				// maximum forward shield charge level, positive float, read-only
	kPlayerShip_messageGuiTextColor,			// message gui standard text color, array, read/write
	kPlayerShip_messageGuiTextCommsColor,		// message gui incoming comms text color, array, read/write
	kPlayerShip_multiFunctionDisplays,			// mfd count, positive int, read-only
	kPlayerShip_multiFunctionDisplayList,		// active mfd list, array, read-only
	kPlayerShip_missilesOnline,                 // bool (false for ident mode, true for missile mode)
	kPlayerShip_pitch,							// pitch (overrules Ship)
	kPlayerShip_price,							// idealised trade-in value decicredits, positive int, read-only
	kPlayerShip_primedEquipment,                // currently primed equipment, string, read/write
	kPlayerShip_renovationCost,					// int read-only current renovation cost
	kPlayerShip_reticleColorTarget,				// Reticle color for normal targets, array, read/write
	kPlayerShip_reticleColorTargetSensitive,	// Reticle color for targets picked up when sensitive mode is on, array, read/write
	kPlayerShip_reticleColorWormhole,			// REticle color for wormholes, array, read/write
	kPlayerShip_renovationMultiplier,			// float read-only multiplier for renovation costs
	kPlayerShip_reticleTargetSensitive,			// target box changes color when primary target in crosshairs, boolean, read/write
	kPlayerShip_roll,							// roll (overrules Ship)
	kPlayerShip_routeMode,						// ANA mode
	kPlayerShip_scannerMinimalistic	,			// essentially scanner without gridlines	
	kPlayerShip_scannerNonLinear,				// non linear scanner setting, boolean, read/write
	kPlayerShip_scannerUltraZoom,				// scanner zoom in powers of 2, boolean, read/write
	kPlayerShip_scoopOverride,					// Scooping
	kPlayerShip_serviceLevel,					// servicing level, positive int 75-100, read-only
	kPlayerShip_specialCargo,					// special cargo, string, read-only
	kPlayerShip_targetSystem,					// target system id, int, read-write
	kPlayerShip_nextSystem,						// next hop system id, read-only
	kPlayerShip_infoSystem,						// info (F7 screen) system id, int, read-write
	kPlayerShip_previousSystem,					// previous system id, read-only
	kPlayerShip_torusEngaged,					// torus in use, boolean, read-only
	kPlayerShip_viewDirection,					// view direction identifier, string, read-only
	kPlayerShip_viewPositionAft,					// view position offset, vector, read-only
	kPlayerShip_viewPositionForward,					// view position offset, vector, read-only
	kPlayerShip_viewPositionPort,					// view position offset, vector, read-only
	kPlayerShip_viewPositionStarboard,					// view position offset, vector, read-only
	kPlayerShip_weaponsOnline,					// weapons online status, boolean, read-only
	kPlayerShip_yaw,							// yaw (overrules Ship)
};


namespace {
static PropertySpec sPlayerShipProperties[] =
{
	// JS name								ID											flags									getter	setter
	{ "activeMissile",                  kPlayerShip_activeMissile,                  PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Shared, nullptr, nullptr },
	{ "aftShield",						kPlayerShip_aftShield,						PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared, nullptr, nullptr },
	{ "aftShieldRechargeRate",			kPlayerShip_aftShieldRechargeRate,			PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared, nullptr, nullptr },
	{ "chartHighlightMode",             kPlayerShip_chartHightlightMode,            PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared, nullptr, nullptr },
	{ "compassMode",					kPlayerShip_compassMode,					PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared, nullptr, nullptr },
	{ "compassTarget",					kPlayerShip_compassTarget,					PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared, nullptr, nullptr },
	{ "compassType",					kPlayerShip_compassType,					PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared, nullptr, nullptr },
	{ "currentWeapon",					kPlayerShip_currentWeapon,					PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared, nullptr, nullptr },
	{ "crosshairs",						kPlayerShip_crosshairs,						PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared, nullptr, nullptr },
	{ "cursorCoordinates",				kPlayerShip_cursorCoordinates,				PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Shared, nullptr, nullptr },
	{ "cursorCoordinatesInLY",			kPlayerShip_cursorCoordinatesInLY,			PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Shared, nullptr, nullptr },
	{ "docked",							kPlayerShip_docked,							PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Shared, nullptr, nullptr },
	{ "dockedStation",					kPlayerShip_dockedStation,					PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Shared, nullptr, nullptr },
	{ "fastEquipmentA",					kPlayerShip_fastEquipmentA,					PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared, nullptr, nullptr },
	{ "fastEquipmentB",					kPlayerShip_fastEquipmentB,					PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared, nullptr, nullptr },
	{ "forwardShield",					kPlayerShip_forwardShield,					PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared, nullptr, nullptr },
	{ "forwardShieldRechargeRate",		kPlayerShip_forwardShieldRechargeRate,		PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared, nullptr, nullptr },
	{ "fuelLeakRate",					kPlayerShip_fuelLeakRate,					PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared, nullptr, nullptr },
	{ "galacticHyperspaceBehaviour",	kPlayerShip_galacticHyperspaceBehaviour,	PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared, nullptr, nullptr },
	{ "galacticHyperspaceFixedCoords",	kPlayerShip_galacticHyperspaceFixedCoords,	PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared, nullptr, nullptr },
	{ "galacticHyperspaceFixedCoordsInLY",	kPlayerShip_galacticHyperspaceFixedCoordsInLY,	PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared, nullptr, nullptr },
	{ "galaxyCoordinates",				kPlayerShip_galaxyCoordinates,				PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Shared, nullptr, nullptr },
	{ "galaxyCoordinatesInLY",			kPlayerShip_galaxyCoordinatesInLY,			PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Shared, nullptr, nullptr },
	{ "hud",							kPlayerShip_hud,							PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared, nullptr, nullptr },
	{ "hudAllowsBigGui",				kPlayerShip_hudAllowsBigGui,				PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Shared, nullptr, nullptr },
	{ "hudHidden",						kPlayerShip_hudHidden,						PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared, nullptr, nullptr },
	{ "injectorsEngaged",				kPlayerShip_injectorsEngaged,				PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Shared, nullptr, nullptr },
	{ "massLockable",					kPlayerShip_massLockable,					PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared, nullptr, nullptr },
	// manifest defined in OOJSManifest.m
	{ "maxAftShield",					kPlayerShip_maxAftShield,					PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared, nullptr, nullptr },
	{ "maxForwardShield",				kPlayerShip_maxForwardShield,				PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared, nullptr, nullptr },
	{ "messageGuiTextColor",			kPlayerShip_messageGuiTextColor,			PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared, nullptr, nullptr },
	{ "messageGuiTextCommsColor",		kPlayerShip_messageGuiTextCommsColor,		PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared, nullptr, nullptr },
	{ "missilesOnline",					kPlayerShip_missilesOnline,					PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Shared, nullptr, nullptr },
	{ "multiFunctionDisplays",			kPlayerShip_multiFunctionDisplays,			PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Shared, nullptr, nullptr },
	{ "multiFunctionDisplayList",  		kPlayerShip_multiFunctionDisplayList,		PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Shared, nullptr, nullptr },
	{ "price",							kPlayerShip_price,							PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Shared, nullptr, nullptr },
	{ "pitch",							kPlayerShip_pitch,							PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared, nullptr, nullptr },
	{ "primedEquipment",				kPlayerShip_primedEquipment,				PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared, nullptr, nullptr },
	{ "renovationCost",					kPlayerShip_renovationCost,					PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Shared, nullptr, nullptr },
	{ "reticleColorTarget",				kPlayerShip_reticleColorTarget,				PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared, nullptr, nullptr },
	{ "reticleColorTargetSensitive",	kPlayerShip_reticleColorTargetSensitive,	PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared, nullptr, nullptr },
	{ "reticleColorWormhole",			kPlayerShip_reticleColorWormhole,			PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared, nullptr, nullptr },
	{ "renovationMultiplier",			kPlayerShip_renovationMultiplier,			PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Shared, nullptr, nullptr },
	{ "reticleTargetSensitive",			kPlayerShip_reticleTargetSensitive,			PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared, nullptr, nullptr },
	{ "roll",							kPlayerShip_roll,							PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared, nullptr, nullptr },
	{ "routeMode",						kPlayerShip_routeMode,						PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Shared, nullptr, nullptr },
	{ "scannerMinimalistic",				kPlayerShip_scannerMinimalistic,			PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared, nullptr, nullptr },
	{ "scannerNonLinear",				kPlayerShip_scannerNonLinear,				PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared, nullptr, nullptr },
	{ "scannerUltraZoom",				kPlayerShip_scannerUltraZoom,				PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared, nullptr, nullptr },
	{ "scoopOverride",					kPlayerShip_scoopOverride,					PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared, nullptr, nullptr },
	{ "serviceLevel",					kPlayerShip_serviceLevel,					PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared, nullptr, nullptr },
	{ "specialCargo",					kPlayerShip_specialCargo,					PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Shared, nullptr, nullptr },
	{ "targetSystem",					kPlayerShip_targetSystem,					PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared, nullptr, nullptr },
	{ "nextSystem",                     kPlayerShip_nextSystem,                     PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Shared, nullptr, nullptr },
	{ "infoSystem",						kPlayerShip_infoSystem,						PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared, nullptr, nullptr },
	{ "previousSystem",					kPlayerShip_previousSystem,					PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Shared, nullptr, nullptr },
	{ "torusEngaged",					kPlayerShip_torusEngaged,					PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Shared, nullptr, nullptr },
	{ "viewDirection",					kPlayerShip_viewDirection,					PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Shared, nullptr, nullptr },
	{ "viewPositionAft",				kPlayerShip_viewPositionAft,				PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Shared, nullptr, nullptr },
	{ "viewPositionForward",			kPlayerShip_viewPositionForward,			PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Shared, nullptr, nullptr },
	{ "viewPositionPort",				kPlayerShip_viewPositionPort,				PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Shared, nullptr, nullptr },
	{ "viewPositionStarboard",			kPlayerShip_viewPositionStarboard,			PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Shared, nullptr, nullptr },
	{ "weaponsOnline",					kPlayerShip_weaponsOnline,					PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Shared, nullptr, nullptr },
	{ "yaw",							kPlayerShip_yaw,							PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared, nullptr, nullptr },
	{ 0 }			
};
} // namespace


// A raw jsapi mirror of sPlayerShipProperties, used only for the two bad-property error
// reporters in OOJavaScriptEngine.m (OOJSReportBadPropertySelector/Value): those helpers are
// outside this bead's scope (shared across every binding file) and still take a
// ooscript::PropertySpec*, not ooscript::PropertySpec* (see OOJSVector.mm's sVectorPropertiesRaw).
namespace {
static ooscript::PropertySpec sPlayerShipPropertiesRaw[] =
{
	// JS name								ID											flags
	{ "activeMissile",                  kPlayerShip_activeMissile,                  OOJS_PROP_READONLY_CB },
	{ "aftShield",						kPlayerShip_aftShield,						OOJS_PROP_READWRITE_CB },
	{ "aftShieldRechargeRate",			kPlayerShip_aftShieldRechargeRate,			OOJS_PROP_READWRITE_CB },
	{ "chartHighlightMode",             kPlayerShip_chartHightlightMode,            OOJS_PROP_READWRITE_CB },
	{ "compassMode",					kPlayerShip_compassMode,					OOJS_PROP_READWRITE_CB },
	{ "compassTarget",					kPlayerShip_compassTarget,					OOJS_PROP_READWRITE_CB },
	{ "compassType",					kPlayerShip_compassType,					OOJS_PROP_READWRITE_CB },
	{ "currentWeapon",					kPlayerShip_currentWeapon,					OOJS_PROP_READWRITE_CB },
	{ "crosshairs",						kPlayerShip_crosshairs,						OOJS_PROP_READWRITE_CB },
	{ "cursorCoordinates",				kPlayerShip_cursorCoordinates,				OOJS_PROP_READONLY_CB },
	{ "cursorCoordinatesInLY",			kPlayerShip_cursorCoordinatesInLY,			OOJS_PROP_READONLY_CB },
	{ "docked",							kPlayerShip_docked,							OOJS_PROP_READONLY_CB },
	{ "dockedStation",					kPlayerShip_dockedStation,					OOJS_PROP_READONLY_CB },
	{ "fastEquipmentA",					kPlayerShip_fastEquipmentA,					OOJS_PROP_READWRITE_CB },
	{ "fastEquipmentB",					kPlayerShip_fastEquipmentB,					OOJS_PROP_READWRITE_CB },
	{ "forwardShield",					kPlayerShip_forwardShield,					OOJS_PROP_READWRITE_CB },
	{ "forwardShieldRechargeRate",		kPlayerShip_forwardShieldRechargeRate,		OOJS_PROP_READWRITE_CB },
	{ "fuelLeakRate",					kPlayerShip_fuelLeakRate,					OOJS_PROP_READWRITE_CB },
	{ "galacticHyperspaceBehaviour",	kPlayerShip_galacticHyperspaceBehaviour,	OOJS_PROP_READWRITE_CB },
	{ "galacticHyperspaceFixedCoords",	kPlayerShip_galacticHyperspaceFixedCoords,	OOJS_PROP_READWRITE_CB },
	{ "galacticHyperspaceFixedCoordsInLY",	kPlayerShip_galacticHyperspaceFixedCoordsInLY,	OOJS_PROP_READWRITE_CB },
	{ "galaxyCoordinates",				kPlayerShip_galaxyCoordinates,				OOJS_PROP_READONLY_CB },
	{ "galaxyCoordinatesInLY",			kPlayerShip_galaxyCoordinatesInLY,			OOJS_PROP_READONLY_CB },
	{ "hud",							kPlayerShip_hud,							OOJS_PROP_READWRITE_CB },
	{ "hudAllowsBigGui",				kPlayerShip_hudAllowsBigGui,				OOJS_PROP_READONLY_CB },
	{ "hudHidden",						kPlayerShip_hudHidden,						OOJS_PROP_READWRITE_CB },
	{ "injectorsEngaged",				kPlayerShip_injectorsEngaged,				OOJS_PROP_READONLY_CB },
	{ "massLockable",					kPlayerShip_massLockable,					OOJS_PROP_READWRITE_CB },
	// manifest defined in OOJSManifest.m
	{ "maxAftShield",					kPlayerShip_maxAftShield,					OOJS_PROP_READWRITE_CB },
	{ "maxForwardShield",				kPlayerShip_maxForwardShield,				OOJS_PROP_READWRITE_CB },
	{ "messageGuiTextColor",			kPlayerShip_messageGuiTextColor,			OOJS_PROP_READWRITE_CB },
	{ "messageGuiTextCommsColor",		kPlayerShip_messageGuiTextCommsColor,		OOJS_PROP_READWRITE_CB },
	{ "missilesOnline",					kPlayerShip_missilesOnline,					OOJS_PROP_READONLY_CB },
	{ "multiFunctionDisplays",			kPlayerShip_multiFunctionDisplays,			OOJS_PROP_READONLY_CB },
	{ "multiFunctionDisplayList",  		kPlayerShip_multiFunctionDisplayList,		OOJS_PROP_READONLY_CB },
	{ "price",							kPlayerShip_price,							OOJS_PROP_READONLY_CB },
	{ "pitch",							kPlayerShip_pitch,							OOJS_PROP_READWRITE_CB },
	{ "primedEquipment",				kPlayerShip_primedEquipment,				OOJS_PROP_READWRITE_CB },
	{ "renovationCost",					kPlayerShip_renovationCost,					OOJS_PROP_READONLY_CB },
	{ "reticleColorTarget",				kPlayerShip_reticleColorTarget,				OOJS_PROP_READWRITE_CB },
	{ "reticleColorTargetSensitive",	kPlayerShip_reticleColorTargetSensitive,	OOJS_PROP_READWRITE_CB },
	{ "reticleColorWormhole",			kPlayerShip_reticleColorWormhole,			OOJS_PROP_READWRITE_CB },
	{ "renovationMultiplier",			kPlayerShip_renovationMultiplier,			OOJS_PROP_READONLY_CB },
	{ "reticleTargetSensitive",			kPlayerShip_reticleTargetSensitive,			OOJS_PROP_READWRITE_CB },
	{ "roll",							kPlayerShip_roll,							OOJS_PROP_READWRITE_CB },
	{ "routeMode",						kPlayerShip_routeMode,						OOJS_PROP_READONLY_CB },
	{ "scannerMinimalistic",				kPlayerShip_scannerMinimalistic,			OOJS_PROP_READWRITE_CB },
	{ "scannerNonLinear",				kPlayerShip_scannerNonLinear,				OOJS_PROP_READWRITE_CB },
	{ "scannerUltraZoom",				kPlayerShip_scannerUltraZoom,				OOJS_PROP_READWRITE_CB },
	{ "scoopOverride",					kPlayerShip_scoopOverride,					OOJS_PROP_READWRITE_CB },
	{ "serviceLevel",					kPlayerShip_serviceLevel,					OOJS_PROP_READWRITE_CB },
	{ "specialCargo",					kPlayerShip_specialCargo,					OOJS_PROP_READONLY_CB },
	{ "targetSystem",					kPlayerShip_targetSystem,					OOJS_PROP_READWRITE_CB },
	{ "nextSystem",                     kPlayerShip_nextSystem,                     OOJS_PROP_READONLY_CB },
	{ "infoSystem",						kPlayerShip_infoSystem,						OOJS_PROP_READWRITE_CB },
	{ "previousSystem",					kPlayerShip_previousSystem,					OOJS_PROP_READONLY_CB },
	{ "torusEngaged",					kPlayerShip_torusEngaged,					OOJS_PROP_READONLY_CB },
	{ "viewDirection",					kPlayerShip_viewDirection,					OOJS_PROP_READONLY_CB },
	{ "viewPositionAft",				kPlayerShip_viewPositionAft,				OOJS_PROP_READONLY_CB },
	{ "viewPositionForward",			kPlayerShip_viewPositionForward,			OOJS_PROP_READONLY_CB },
	{ "viewPositionPort",				kPlayerShip_viewPositionPort,				OOJS_PROP_READONLY_CB },
	{ "viewPositionStarboard",			kPlayerShip_viewPositionStarboard,			OOJS_PROP_READONLY_CB },
	{ "weaponsOnline",					kPlayerShip_weaponsOnline,					OOJS_PROP_READONLY_CB },
	{ "yaw",							kPlayerShip_yaw,							OOJS_PROP_READWRITE_CB },
	{ 0 }
};
} // namespace


namespace {
static FunctionSpec sPlayerShipMethods[] =
{
	// JS name							Function								min args	flags
	{ "addParcel",   					PlayerShipAddParcel,						0,			0 },
	{ "addPassenger",					PlayerShipAddPassenger,						0,			0 },
	{ "awardContract",					PlayerShipAwardContract,					0,			0 },
	{ "awardEquipmentToCurrentPylon",	PlayerShipAwardEquipmentToCurrentPylon,		1,			0 },
	{ "beginHyperspaceCountdown",       PlayerShipBeginHyperspaceCountdown,         0,			0 },
	{ "cancelDockingRequest",			PlayerShipCancelDockingRequest,             1,			0 },
	{ "cancelHyperspaceCountdown",      PlayerShipCancelHyperspaceCountdown,        0,			0 },
	{ "beginGalacticHyperspaceCountdown", PlayerShipBeginGalacticHyperspaceCountdown, 1,			0 },
	{ "disengageAutopilot",				PlayerShipDisengageAutopilot,				0,			0 },
	{ "engageAutopilotToStation",		PlayerShipEngageAutopilotToStation,			1,			0 },
	{ "hideHUDSelector",				PlayerShipHideHUDSelector,					1,			0 },
	{ "launch",							PlayerShipLaunch,							0,			0 },
	{ "removeAllCargo",					PlayerShipRemoveAllCargo,					0,			0 },
	{ "removeContract",					PlayerShipRemoveContract,					2,			0 },
	{ "removeParcel",                   PlayerShipRemoveParcel,                     1,			0 },
	{ "removePassenger",				PlayerShipRemovePassenger,					1,			0 },
	{ "requestDockingClearance",        PlayerShipRequestDockingClearance,          1,			0 },
	{ "resetCustomView",				PlayerShipResetCustomView,					0,			0 },
	{ "resetScannerZoom",				PlayerShipResetScannerZoom,					0,			0 },
	{ "setCustomView",					PlayerShipSetCustomView,					2,			0 },
	{ "setCustomHUDDial",				PlayerShipSetCustomHUDDial,					2,			0 },
	{ "setMultiFunctionDisplay",		PlayerShipSetMultiFunctionDisplay,			1,			0 },
	{ "setMultiFunctionText",			PlayerShipSetMultiFunctionText,				1,			0 },
	{ "setPrimedEquipment",				PlayerShipSetPrimedEquipment,               1,			0 },
	{ "showHUDSelector",				PlayerShipShowHUDSelector,					1,			0 },
	{ "takeInternalDamage",				PlayerShipTakeInternalDamage,				0,			0 },
	{ "useSpecialCargo",				PlayerShipUseSpecialCargo,					1,			0 },
	{ 0 }
};
} // namespace


void InitOOJSPlayerShip(ooscript::Context context, ooscript::Object global)
{
	Object proto = ooscript::initClass((context), (global), (JSShipPrototype()), &sPlayerShipClass, OOJSUnconstructableConstruct, 0, sPlayerShipProperties, sPlayerShipMethods, nullptr, nullptr);
	sPlayerShipPrototype = (proto);
	OOJSRegisterObjectConverter(&sPlayerShipClass, OOJSEntityObjectConverter);
	OOJSRegisterSubclass(&sPlayerShipClass, JSShipClass());
	
	PlayerEntity *player = PlayerEntity::sharedPlayer();	// NOTE: at time of writing, this creates the player entity. Don't use PLAYER here.
	
	// Create ship object as a property of the player object.
	Object shipObj = ooscript::defineObject((context), (JSPlayerObject()), "ship", &sPlayerShipClass, proto, OOJS_PROP_READONLY);
	sPlayerShipObject = (shipObj);
	// The slot holds a weak reference to the C++ player (bead oo-9ht.39.3; the player's object's
	// weak reference before), as every entity's JS object's does.
	OOJSSetCxxPrivate((context), shipObj, oo::makeRef<OOJSEntityHolder>(player).get());
	OOJSPlayerShipSetJSSelf(player, sPlayerShipObject, context);	// -setJSSelf:context:, the category in this file
}


ooscript::ClassDef *JSPlayerShipClass(void)
{
	return &sPlayerShipClass;
}


ooscript::Object JSPlayerShipPrototype(void)
{
	return sPlayerShipPrototype;
}


ooscript::Object JSPlayerShipObject(void)
{
	return sPlayerShipObject;
}


// PlayerEntity (OOJavaScriptExtensions): the bodies of the category's methods, which the engine
// and the player sent by selector; the C++ player calls them (ADR-0056 amendments oo-ppc item 3,
// oo-ykoy, oo-9ht.177).
std::optional<std::string> OOJSPlayerShipJSClassName(void)
{
	return std::string("PlayerShip");
}


void OOJSPlayerShipSetJSSelf(PlayerEntity *player, ooscript::Object val, ooscript::Context context)
{
	player->_jsSelf = val;
	OOJSAddGCObjectRoot(context, &player->_jsSelf, "Player jsSelf");

	oo::NotificationCenter::defaultCenter().addObserver(player, kOOJavaScriptEngineWillResetNotificationName,
														OOJavaScriptEngine::sharedEngine(),
														[player](const oo::Notification &notification) { OOJSPlayerShipJavaScriptEngineWillReset(player, notification); });
}


void OOJSPlayerShipJavaScriptEngineWillReset(PlayerEntity *player, const oo::Notification & /*notification*/)
{
	oo::NotificationCenter::defaultCenter().removeObserver(player, kOOJavaScriptEngineWillResetNotificationName,
															OOJavaScriptEngine::sharedEngine());

	if (player->_jsSelf != NULL)
	{

		ooscript::Context context = OOJSAcquireContext();
		ooscript::removeObjectRoot((context), OOJSFOBJP(&player->_jsSelf));
		player->_jsSelf = NULL;
		OOJSRelinquishContext(context);
	}
}


namespace {
static bool PlayerShipGetProperty(Context cx, Object obj, PropertyId propID, Value *value)
{
	if (!ooscript::isInt32Id(propID))  return true;
	
	ooscript::Context context = (cx);
	ooscript::Object thisObj = (obj);
	ooscript::Value *value_raw = (value);
	
	OOJS_NATIVE_ENTER(context)
	
	if (EXPECT_NOT(OOIsPlayerStale() || thisObj == sPlayerShipPrototype))  { *value_raw = ooscript::undefinedValue(); return true; }
	
	oo::PList					result;	// null maps to null
	PlayerEntity				*player = OOPlayerForScripting();
	
	switch (ooscript::idToInt32(propID))
	{
		case kPlayerShip_activeMissile:
			return ooscript::newNumberValue(cx, (player != nullptr ? player->getActiveMissile() : 0), value);
                      
		case kPlayerShip_fuelLeakRate:
			return ooscript::newNumberValue(cx, (player != nullptr ? player->fuelLeakRate() : 0.0f), value);
			
		case kPlayerShip_docked:
			*value_raw = OOJSValueFromBOOL(player != nullptr ? player->isDocked() : false);
			return true;
			
		case kPlayerShip_dockedStation:
			result = oo::EntityObjectNode(player != nullptr ? player->dockedStation() : (StationEntity *)nullptr);
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
			*value_raw = OOJSValueFromBOOL(AskHud(player, &HeadUpDisplay::getReticleTargetSensitive));
			return true;
			
		case kPlayerShip_galacticHyperspaceBehaviour:
			*value_raw = OOJSValueFromGalacticHyperspaceBehaviour(context, (player != nullptr ? player->getGalacticHyperspaceBehaviour() : OOGalacticHyperspaceBehaviour{}));
			return true;
			
		case kPlayerShip_galacticHyperspaceFixedCoords:
			return NSPointToVectorJSValue(context, (player != nullptr ? player->getGalacticHyperspaceFixedCoords() : NSPoint{}), value_raw);
			
		case kPlayerShip_galacticHyperspaceFixedCoordsInLY:
			return VectorToJSValue(context, OOGalacticCoordinatesFromInternal(player != nullptr ? player->getGalacticHyperspaceFixedCoords() : NSPoint{}), value_raw);

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
			return ooscript::newNumberValue(cx, (player != nullptr ? player->forwardShieldLevel() : 0.0f), value);
			
		case kPlayerShip_aftShield:
			return ooscript::newNumberValue(cx, (player != nullptr ? player->aftShieldLevel() : 0.0f), value);
			
		case kPlayerShip_maxForwardShield:
			return ooscript::newNumberValue(cx, (player != nullptr ? player->maxForwardShieldLevel() : 0.0f), value);
			
		case kPlayerShip_maxAftShield:
			return ooscript::newNumberValue(cx, (player != nullptr ? player->maxAftShieldLevel() : 0.0f), value);
			
		case kPlayerShip_forwardShieldRechargeRate:
			// No distinction made internally
			return ooscript::newNumberValue(cx, (player != nullptr ? player->forwardShieldRechargeRate() : 0.0f), value);

		case kPlayerShip_aftShieldRechargeRate:
			// No distinction made internally
			return ooscript::newNumberValue(cx, (player != nullptr ? player->aftShieldRechargeRate() : 0.0f), value);
			
		case kPlayerShip_multiFunctionDisplays:
			return ooscript::newNumberValue(cx, AskHud(player, &HeadUpDisplay::mfdCount), value);

		case kPlayerShip_multiFunctionDisplayList:
			{
				oo::PList::Array list;	// [OONull null] for an inactive MFD
				for (const std::optional<std::string> &key : (player != nullptr ? player->multiFunctionDisplayList() : std::vector<std::optional<std::string>>()))
				{
					list.push_back(key.has_value() ? oo::PList(*key) : OONullObjectNode());
				}
				result = oo::PList(std::move(list));
			}
			break;

		case kPlayerShip_missilesOnline:
			*value_raw = OOJSValueFromBOOL(!(player != nullptr ? player->dialIdentEngaged() : false));
			return true;

		case kPlayerShip_chartHightlightMode:
			result = oo::PList(cxx_OOStringFromLongRangeChartMode(player != nullptr ? player->getLongRangeChartMode() : OOLongRangeChartMode{}));
			break;

		case kPlayerShip_galaxyCoordinates:
			return NSPointToVectorJSValue(context, (player != nullptr ? player->getGalaxy_coordinates() : NSPoint{}), value_raw);
			
		case kPlayerShip_galaxyCoordinatesInLY:
			return VectorToJSValue(context, OOGalacticCoordinatesFromInternal(player != nullptr ? player->getGalaxy_coordinates() : NSPoint{}), value_raw);
			
		case kPlayerShip_cursorCoordinates:
			return NSPointToVectorJSValue(context, (player != nullptr ? player->getCursor_coordinates() : NSPoint{}), value_raw);

		case kPlayerShip_cursorCoordinatesInLY:
			return VectorToJSValue(context, OOGalacticCoordinatesFromInternal(player != nullptr ? player->getCursor_coordinates() : NSPoint{}), value_raw);
			
		case kPlayerShip_targetSystem:
			*value_raw = ooscript::int32Value(player != nullptr ? player->targetSystemID() : 0);
			return true;

		case kPlayerShip_nextSystem:
			*value_raw = ooscript::int32Value(player != nullptr ? player->nextHopTargetSystemID() : 0);
			return true;
			
		case kPlayerShip_infoSystem:
			*value_raw = ooscript::int32Value(player != nullptr ? player->infoSystemID() : 0);
			return true;

		case kPlayerShip_previousSystem:
			*value_raw = ooscript::int32Value(player != nullptr ? player->previousSystemID() : 0);
			return true;
			
		case kPlayerShip_routeMode:
		{
			OORouteType route = (player != nullptr ? player->ANAMode() : OORouteType{});
			switch (route)
			{
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
			*value_raw = OOJSValueFromBOOL(AskHud(player, &HeadUpDisplay::minimalisticScanner));
			return true;
			
		case kPlayerShip_scannerNonLinear:
			*value_raw = OOJSValueFromBOOL(AskHud(player, &HeadUpDisplay::nonlinearScanner));
			return true;
			
		case kPlayerShip_scannerUltraZoom:
			*value_raw = OOJSValueFromBOOL(AskHud(player, &HeadUpDisplay::scannerUltraZoom));
			return true;
			
		case kPlayerShip_scoopOverride:
			*value_raw = OOJSValueFromBOOL(player != nullptr ? player->getScoopOverride() : false);
			return true;

		case kPlayerShip_injectorsEngaged:
			*value_raw = OOJSValueFromBOOL(player != nullptr ? player->injectorsEngaged() : false);
			return true;
			
		case kPlayerShip_massLockable:
			*value_raw = OOJSValueFromBOOL(player != nullptr ? player->getMassLockable() : false);
			return true;

		case kPlayerShip_torusEngaged:
			*value_raw = OOJSValueFromBOOL(player != nullptr ? player->hyperspeedEngaged() : false);
			return true;
			
		case kPlayerShip_compassTarget:
			result = oo::EntityObjectNode(player != nullptr ? player->getCompassTargetEntity() : (Entity *)nullptr);	// the C++ entity's node, the same object's (bead oo-9ht.39.25)
			break;
			
		case kPlayerShip_compassType:
			result = oo::PList((cxx_OOStringFromCompassMode(player != nullptr ? player->getCompassMode() : OOCompassMode{}) == "COMPASS_MODE_BASIC") ?
										"OO_COMPASSTYPE_BASIC" : "OO_COMPASSTYPE_ADVANCED");
			break;
			
		case kPlayerShip_compassMode:
			*value_raw = OOJSValueFromCompassMode(context, (player != nullptr ? player->getCompassMode() : OOCompassMode{}));
			return true;
			
		case kPlayerShip_hud:
			result = StringOrNull(AskHud(player, &HeadUpDisplay::getHudName));
			break;

		case kPlayerShip_crosshairs:
			result = StringOrNull(AskHud(player, &HeadUpDisplay::getCrosshairDefinition));
			break;

		case kPlayerShip_hudAllowsBigGui:
			*value_raw = OOJSValueFromBOOL(AskHud(player, &HeadUpDisplay::getAllowBigGui));
			return true;

		case kPlayerShip_hudHidden:
			*value_raw = OOJSValueFromBOOL(AskHud(player, &HeadUpDisplay::isHidden));
			return true;
			
		case kPlayerShip_weaponsOnline:
			*value_raw = OOJSValueFromBOOL(player != nullptr ? player->weaponsOnline() : false);
			return true;
			
		case kPlayerShip_viewDirection:
			*value_raw = OOJSValueFromViewID(context, (UNIVERSE != nullptr ? UNIVERSE->getViewDirection() : OOViewID{}));
			return true;

		case kPlayerShip_viewPositionAft:
			return VectorToJSValue(context, (player != nullptr ? player->viewpointOffsetAft() : Vector{}), value_raw);

		case kPlayerShip_viewPositionForward:
			return VectorToJSValue(context, (player != nullptr ? player->viewpointOffsetForward() : Vector{}), value_raw);

		case kPlayerShip_viewPositionPort:
			return VectorToJSValue(context, (player != nullptr ? player->viewpointOffsetPort() : Vector{}), value_raw);

		case kPlayerShip_viewPositionStarboard:
			return VectorToJSValue(context, (player != nullptr ? player->viewpointOffsetStarboard() : Vector{}), value_raw);

		case kPlayerShip_currentWeapon:
			result = OOEquipmentTypeObjectNode(player != nullptr ? player->weaponTypeForFacing((player != nullptr ? player->getCurrentWeaponFacing() : OOWeaponFacing{}), false) : (OOEquipmentType *)nullptr);
			break;
		
	  case kPlayerShip_price:
			return ooscript::newNumberValue(cx, (UNIVERSE != nullptr ? UNIVERSE->tradeInValueForCommanderDictionary((player != nullptr ? player->commanderDataDictionary() : oo::PList())) : 0), value);

	  case kPlayerShip_serviceLevel:
			return ooscript::newNumberValue(cx, (player != nullptr ? player->tradeInFactor() : int{}), value);

		case kPlayerShip_renovationCost:
			return ooscript::newNumberValue(cx, (player != nullptr ? player->renovationCosts() : 0.0), value);

		case kPlayerShip_renovationMultiplier:
			return ooscript::newNumberValue(cx, (player != nullptr ? player->renovationFactor() : 0.0), value);


			// make roll, pitch, yaw reported to JS use same +/- convention as
			// for NPC ships
		case kPlayerShip_pitch:
			return ooscript::newNumberValue(cx, -(player != nullptr ? player->getFlightPitch() : 0.0f), value);

		case kPlayerShip_roll:
			return ooscript::newNumberValue(cx, -(player != nullptr ? player->getFlightRoll() : 0.0f), value);

		case kPlayerShip_yaw:
			return ooscript::newNumberValue(cx, -(player != nullptr ? player->getFlightYaw() : 0.0f), value);
			
		case kPlayerShip_messageGuiTextColor:
			result = NormalizedColorComponents(UNIVERSE->messageGUI()->getTextColor());
			break;
			
		case kPlayerShip_messageGuiTextCommsColor:
			result = NormalizedColorComponents(UNIVERSE->messageGUI()->getTextCommsColor());
			break;
			
		default:
			OOJSReportBadPropertySelector(context, thisObj, (propID), sPlayerShipPropertiesRaw);
	}
	
	*value_raw = OOJSValueFromPList(context, result);
	return true;
	
	OOJS_NATIVE_EXIT
}
} // namespace


namespace {
static bool PlayerShipSetProperty(Context cx, Object obj, PropertyId propID, bool /*strict*/, Value *value)
{
	if (!ooscript::isInt32Id(propID))  return true;
	
	ooscript::Context context = (cx);
	ooscript::Object thisObj = (obj);
	ooscript::Value *value_raw = (value);
	
	OOJS_NATIVE_ENTER(context)
	
	if (EXPECT_NOT(OOIsPlayerStale())) return true;
	
	PlayerEntity				*player = OOPlayerForScripting();
	double					fValue;
	bool						bValue;
	int32_t						iValue;
	std::optional<std::string>					sValue;
	OOGalacticHyperspaceBehaviour ghBehaviour;
	Vector						vValue;
	oo::Ref<OOColor>		colorForScript;	// the colours are converted (OOColor)
	Entity					*eValue = nullptr;	// as JSValueToEntity() answers (the C++ entity since bead oo-9ht.39.3)

	switch (ooscript::idToInt32(propID))
	{
		case kPlayerShip_fuelLeakRate:
			if (ooscript::valueToNumber(cx, *value, &fValue))
			{
				if (player != nullptr)  player->setFuelLeakRate(fValue);
				return true;
			}
			break;
			
		case kPlayerShip_massLockable:
			if (ooscript::valueToBoolean(cx, *value, &bValue))
			{
				if (player != nullptr)  player->setMassLockable(bValue);
				return true;
			}
			break;
			
		case kPlayerShip_reticleTargetSensitive:
			if (ooscript::valueToBoolean(cx, *value, &bValue))
			{
				if (HeadUpDisplay *hud = HudOf(player))  hud->setReticleTargetSensitive(bValue);
				return true;
			}
			break;
		
		case kPlayerShip_chartHightlightMode:
			sValue = cxx_OOStringFromJSValue(context, *value_raw);
			if (sValue.has_value()) 
			{
				OOLongRangeChartMode chartMode = cxx_OOLongRangeChartModeFromString(sValue.value_or(""));
				if (chartMode > OOLRC_MODE_UNKNOWN)
				{
					if (player != nullptr)  player->setLongRangeChartMode(chartMode);
					if (player != nullptr)  player->doScriptEvent(OOJSID("chartHighlightModeChanged"), { oo::PList(cxx_OOStringFromLongRangeChartMode(player != nullptr ? player->getLongRangeChartMode() : OOLongRangeChartMode{})) });
					return true;
				}
				else
				{
					cxx_OOJSReportError(context, "Unknown chart hightlight mode specified - must be either OOLRC_MODE_SUNCOLOR, OOLRC_MODE_ECONOMY, OOLRC_MODE_GOVERNMENT or OOLRC_MODE_TECHLEVEL.");
				}
			}
			return false;	// not reachable if successfully set
			break;

		case kPlayerShip_compassMode:
			sValue = cxx_OOStringFromJSValue(context, *value_raw);
			if(sValue.has_value())
			{
				OOCompassMode mode = OOCompassModeFromJSValue(context, *value_raw);
				if (player != nullptr)  player->setCompassMode(mode);
				if (player != nullptr)  player->validateCompassTarget();
				return true;
			}
			break;
			
		case kPlayerShip_compassType:
			sValue = cxx_OOStringFromJSValue(context, *value_raw);
			if (sValue.has_value())
			{
				if (*sValue == "OO_COMPASSTYPE_BASIC")
				{
					if (player != nullptr)  player->setCompassMode(COMPASS_MODE_BASIC);
				}
				else  if(*sValue == "OO_COMPASSTYPE_ADVANCED")
				{
					if (!(player != nullptr ? player->hasEquipmentItemProviding("EQ_ADVANCED_COMPASS") : false))
					{
						cxx_OOJSReportWarning(context, "Advanced Compass type requested and set but player ship does not carry the EQ_ADVANCED_COMPASS equipment or has it damaged.");
					}
					if (player != nullptr)  player->setCompassMode(COMPASS_MODE_PLANET);
				}
				else
				{
					cxx_OOJSReportError(context, "Unknown compass type specified - must be either OO_COMPASSTYPE_BASIC or OO_COMPASSTYPE_ADVANCED.");
					return false;
				}
				return true;
			}
			break;
		
		case kPlayerShip_compassTarget:
			// can't change compass target in basic mode
			if (!(player != nullptr ? player->hasEquipmentItemProviding("EQ_ADVANCED_COMPASS") : false)) 
			{
				cxx_OOJSReportError(context, "Compass target cannot be set with a basic compass.");
				return false;
			}
			// make sure we have a valid entity
			if (!ooscript::isNull(*value_raw) && JSValueToEntity(context, *value_raw, &eValue)) 
			{
				Entity *current = (player != nullptr ? player->getCompassTargetEntity() : nullptr);	// the C++ entities (bead oo-9ht.39.25)
				if (player != nullptr)  player->setNextCompassMode();
				if (player != nullptr)  player->validateCompassTarget();
				// cycle the targets until we either get back to the start (entity not found) or we find the one we're looking for
				while ((player != nullptr ? player->getCompassTargetEntity() : nullptr) != current && (player != nullptr ? player->getCompassTargetEntity() : nullptr) != eValue)	// the C++ entities (bead oo-9ht.39.8.11)
				{
					if (player != nullptr)  player->setNextCompassMode();
					if (player != nullptr)  player->validateCompassTarget();
				}
				return (player != nullptr ? player->getCompassTargetEntity() : nullptr) != current;
			}
			else 
			{
				cxx_OOJSReportError(context, "Invalid compass target entity provided.");
				return false;
			}
			break;

		case kPlayerShip_galacticHyperspaceBehaviour:
			ghBehaviour = OOGalacticHyperspaceBehaviourFromJSValue(context, *value_raw);
			if (ghBehaviour != GALACTIC_HYPERSPACE_BEHAVIOUR_UNKNOWN)
			{
				if (player != nullptr)  player->setGalacticHyperspaceBehaviour(ghBehaviour);
				return true;
			}
			break;
			
		case kPlayerShip_galacticHyperspaceFixedCoords:
			if (JSValueToVector(context, *value_raw, &vValue))
			{
				NSPoint coords = { vValue.x, vValue.y };
				if (player != nullptr)  player->setGalacticHyperspaceFixedCoords(coords);
				return true;
			}
			break;
			
		case kPlayerShip_galacticHyperspaceFixedCoordsInLY:
			if (JSValueToVector(context, *value_raw, &vValue))
			{
				NSPoint coords = OOInternalCoordinatesFromGalactic(vValue);
				if (player != nullptr)  player->setGalacticHyperspaceFixedCoords(coords);
				return true;
			}
			break;
			
		case kPlayerShip_fastEquipmentA:
			sValue = cxx_OOStringFromJSValue(context, *value_raw);
			if (sValue.has_value())
			{
				if (player != nullptr)  player->setFastEquipmentA(sValue);
				return true;
			}
			break;

		case kPlayerShip_fastEquipmentB:
			sValue = cxx_OOStringFromJSValue(context, *value_raw);
			if (sValue.has_value())
			{
				if (player != nullptr)  player->setFastEquipmentB(sValue);
				return true;
			}
			break;

		case kPlayerShip_primedEquipment:
			sValue = cxx_OOStringFromJSValue(context, *value_raw);
			if (sValue.has_value())
			{
				return (player != nullptr ? player->setPrimedEquipment(*sValue, false) : false);
			}
			break;

		case kPlayerShip_pitch:
			if (ooscript::valueToNumber(cx, *value, &fValue))
			{
				if (!isnan(fValue)) // guard against undefined
				{
					if (player != nullptr)  player->decrease_flight_pitch(((player != nullptr ? player->getFlightPitch() : 0.0f) + fValue));
				}
				return true;
			}
			break;
			
		case kPlayerShip_roll:
			if (ooscript::valueToNumber(cx, *value, &fValue))
			{
				if (!isnan(fValue)) // guard against undefined
				{
					if (player != nullptr)  player->decrease_flight_roll(((player != nullptr ? player->getFlightRoll() : 0.0f) + fValue));
				}
				return true;
			}
			break;
			
		case kPlayerShip_yaw:
			if (ooscript::valueToNumber(cx, *value, &fValue))
			{
				if (!isnan(fValue)) // guard against undefined
				{
					if (player != nullptr)  player->decrease_flight_yaw(((player != nullptr ? player->getFlightYaw() : 0.0f) + fValue));
				}
				return true;
			}
			break;
			
		case kPlayerShip_forwardShield:
			if (ooscript::valueToNumber(cx, *value, &fValue))
			{
				if (player != nullptr)  player->setForwardShieldLevel(fValue);
				return true;
			}
			break;
			
		case kPlayerShip_aftShield:
			if (ooscript::valueToNumber(cx, *value, &fValue))
			{
				if (player != nullptr)  player->setAftShieldLevel(fValue);
				return true;
			}
			break;

		case kPlayerShip_maxForwardShield:
			if (ooscript::valueToNumber(cx, *value, &fValue))
			{
				if (player != nullptr)  player->setMaxForwardShieldLevel(fValue);
				return true;
			}
			break;
			
		case kPlayerShip_maxAftShield:
			if (ooscript::valueToNumber(cx, *value, &fValue))
			{
				if (player != nullptr)  player->setMaxAftShieldLevel(fValue);
				return true;
			}
			break;

		case kPlayerShip_forwardShieldRechargeRate:
			if (ooscript::valueToNumber(cx, *value, &fValue))
			{
				if (player != nullptr)  player->setForwardShieldRechargeRate(fValue);
				return true;
			}
			break;
			
		case kPlayerShip_aftShieldRechargeRate:
			if (ooscript::valueToNumber(cx, *value, &fValue))
			{
				if (player != nullptr)  player->setAftShieldRechargeRate(fValue);
				return true;
			}
			break;
			
		case kPlayerShip_scannerMinimalistic:
			if (ooscript::valueToBoolean(cx, *value, &bValue))
			{
				if (HeadUpDisplay *hud = HudOf(player))  hud->setMinimalisticScanner(bValue);
				return true;
			}
			break;
			
		case kPlayerShip_scannerNonLinear:
			if (ooscript::valueToBoolean(cx, *value, &bValue))
			{
				if (HeadUpDisplay *hud = HudOf(player))  hud->setNonlinearScanner(bValue);
				return true;
			}
			break;
			
		case kPlayerShip_scannerUltraZoom:
			if (ooscript::valueToBoolean(cx, *value, &bValue))
			{
				if (HeadUpDisplay *hud = HudOf(player))  hud->setScannerUltraZoom(bValue);
				return true;
			}
			break;
			
		case kPlayerShip_scoopOverride:
			if (ooscript::valueToBoolean(cx, *value, &bValue))
			{
				if (player != nullptr)  player->setScoopOverride(bValue);
				return true;
			}
			break;
			
		case kPlayerShip_hud:
			sValue = cxx_OOStringFromJSValue(context, *value_raw);
			if (sValue.has_value())
			{
				if (sValue.has_value() && player != nullptr)  player->switchHudTo(*sValue);	// EMMSTRAN: logged error should be a JS warning.
				return true;
			}
			else
			{
				if (player != nullptr)  player->resetHud();
				return true;
			}
			break;
			
		case kPlayerShip_crosshairs:
			sValue = cxx_OOStringFromJSValue(context, *value_raw);
			if (!sValue.has_value())
			{
				// reset HUD back to its plist settings
				std::optional<std::string> hud = AskHud(player, &HeadUpDisplay::getHudName);	// a copy, as the retain kept it
				if (hud.has_value() && player != nullptr)  player->switchHudTo(*hud);
				return true;
			}
			else
			{
				if (!(HudOf(player) != nullptr && HudOf(player)->setCrosshairDefinition(sValue.value_or(""))))
				{
					cxx_OOJSReportWarning(context, "Crosshair definition file %s not found or invalid", (sValue ? sValue->c_str() : "(null)"));
				}
				return true;
			}
			break;

		case kPlayerShip_hudHidden:
			if (ooscript::valueToBoolean(cx, *value, &bValue))
			{
				if (HeadUpDisplay *hud = HudOf(player))  hud->setHidden(bValue);
				return true;
			}
			break;

	  case kPlayerShip_serviceLevel:
			if (ooscript::valueToNumber(cx, *value, &fValue))
			{
				int newLevel = (int)fValue;
				if (player != nullptr)  player->adjustTradeInFactorBy((newLevel-(player != nullptr ? player->tradeInFactor() : int{})));
				return true;
			}
			
		case kPlayerShip_currentWeapon:
		{
			BOOL exists = NO;	// JSValueToEquipmentKeyRelaxed() takes a BOOL * (amendment oo-nge8 item 1)
			sValue = JSValueToEquipmentKeyRelaxed(context, *value_raw, &exists);
			if (!exists || !sValue.has_value()) 
			{
				sValue = "EQ_WEAPON_NONE";
			}
			if (player != nullptr)  player->setWeaponMount(player->getCurrentWeaponFacing(), sValue.value_or(""), "scripted");
			return true;
		}
		
		case kPlayerShip_targetSystem:
			/* This first check is essential: if removed, it would be
			 * possible to make jumps of arbitrary length - CIM */
			if ((player != nullptr ? player->status() : OOEntityStatus{}) != STATUS_ENTERING_WITCHSPACE)
			{
				/* These checks though similar are less important. The
				 * consequences of allowing jump destination to be set in
				 * flight are not as severe and do not allow the 7LY limit to
				 * be broken. Nevertheless, it is not allowed. - CIM */
				// (except when compiled in debugging mode)
#ifndef OO_DUMP_PLANETINFO
				if (EXPECT_NOT((player != nullptr ? player->status() : OOEntityStatus{}) != STATUS_DOCKED && (player != nullptr ? player->status() : OOEntityStatus{}) != STATUS_LAUNCHING))
				{
					cxx_OOJSReportError(context, "player.ship.targetSystem is read-only unless called when docked.");
					return false;
				}
#endif
				
				if (ooscript::valueToInt32(cx, *value, &iValue))
				{
					if (iValue >= 0 && iValue < OO_SYSTEMS_PER_GALAXY)
					{ 
						if (player != nullptr)  player->setTargetSystemID(iValue);
						return true;
					}
					else
					{
						return false;
					}
				}
			}
			else
			{
				cxx_OOJSReportError(context, "player.ship.targetSystem is read-only unless called when docked.");
				return false;
			}
		
		case kPlayerShip_infoSystem:
			if (ooscript::valueToInt32(cx, *value, &iValue))
			{
				if (iValue >= 0 && iValue < OO_SYSTEMS_PER_GALAXY)
				{ 
					if (player != nullptr)  player->setInfoSystemID(iValue, true);
					return true;
				}
				else
				{
					return false;
				}
			}
			break;
			
		case kPlayerShip_messageGuiTextColor:
			colorForScript = OOColor::colorWithDescription(cxx_OOJSPListFromJSValue(context, *value_raw));
			if (colorForScript != nullptr || ooscript::isNull(*value_raw))
			{
				UNIVERSE->messageGUI()->setTextColor(colorForScript.get());
				return true;
			}
			break;
			
		case kPlayerShip_messageGuiTextCommsColor:
			colorForScript = OOColor::colorWithDescription(cxx_OOJSPListFromJSValue(context, *value_raw));
			if (colorForScript != nullptr || ooscript::isNull(*value_raw))
			{
				UNIVERSE->messageGUI()->setTextCommsColor(colorForScript.get());
				return true;
			}
			break;
			
		case kPlayerShip_reticleColorTarget:
			colorForScript = OOColor::colorWithDescription(cxx_OOJSPListFromJSValue(context, *value_raw));
			if (colorForScript != nullptr || ooscript::isNull(*value_raw))
			{
				return HudOf(player) != nullptr && HudOf(player)->setReticleColorForIndex(OO_RETICLE_COLOR_TARGET, colorForScript.get());
			}
			break;
			
		case kPlayerShip_reticleColorTargetSensitive:
			colorForScript = OOColor::colorWithDescription(cxx_OOJSPListFromJSValue(context, *value_raw));
			if (colorForScript != nullptr || ooscript::isNull(*value_raw))
			{
				return HudOf(player) != nullptr && HudOf(player)->setReticleColorForIndex(OO_RETICLE_COLOR_TARGET_SENSITIVE, colorForScript.get());
			}
			break;
			
		case kPlayerShip_reticleColorWormhole:
			colorForScript = OOColor::colorWithDescription(cxx_OOJSPListFromJSValue(context, *value_raw));
			if (colorForScript != nullptr || ooscript::isNull(*value_raw))
			{
				return HudOf(player) != nullptr && HudOf(player)->setReticleColorForIndex(OO_RETICLE_COLOR_WORMHOLE, colorForScript.get());
			}
			break;

		default:
			OOJSReportBadPropertySelector(context, thisObj, (propID), sPlayerShipPropertiesRaw);
			return false;
	}
	
	OOJSReportBadPropertyValue(context, thisObj, (propID), sPlayerShipPropertiesRaw, *value_raw);
	return false;
	
	OOJS_NATIVE_EXIT
}
} // namespace


// *** Methods ***

// launch()
namespace {
static bool PlayerShipLaunch(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_NATIVE_ENTER(context)
	
	if (EXPECT_NOT(OOIsPlayerStale()))  OOJS_RETURN_VOID;
	
	if (PlayerEntity *player = OOPlayerForScripting())  player->launchFromStation();
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}
} // namespace


// removeAllCargo()
namespace {
static bool PlayerShipRemoveAllCargo(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_NATIVE_ENTER(context)
	
	if (EXPECT_NOT(OOIsPlayerStale()))  OOJS_RETURN_VOID;
	
	PlayerEntity *player = OOPlayerForScripting();
	
	if ((player != nullptr ? player->isDocked() : false))
	{
		if (player != nullptr)  player->removeAllCargo();
		OOJS_RETURN_VOID;
	}
	else
	{
		cxx_OOJSReportError(context, "PlayerShip.removeAllCargo only works when docked.");
		return false;
	}
	
	OOJS_NATIVE_EXIT
}
} // namespace


// useSpecialCargo(name : String)
namespace {
static bool PlayerShipUseSpecialCargo(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_NATIVE_ENTER(context)
	
	if (EXPECT_NOT(OOIsPlayerStale()))  OOJS_RETURN_VOID;
	
	PlayerEntity			*player = OOPlayerForScripting();
	std::optional<std::string>				name;
	
	if (oojsArgs.count() > 0)  name = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (EXPECT_NOT(!name.has_value()))
	{
		cxx_OOJSReportBadArguments(context, "PlayerShip", "useSpecialCargo", MIN(oojsArgs.count(), 1U), OOJS_ARGV, std::nullopt, "string (special cargo description)");
		return false;
	}
	
	if (player != nullptr)  player->useSpecialCargo(cxx_OOStringFromJSValue(context, OOJS_ARGV[0]).value_or(std::string()));	// (nil was "")
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}
} // namespace


// engageAutopilotToStation(stationForDocking : Station) : Boolean
namespace {
static bool PlayerShipEngageAutopilotToStation(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_NATIVE_ENTER(context)
	
	if (EXPECT_NOT(OOIsPlayerStale()))  OOJS_RETURN_VOID;
	
	PlayerEntity			*player = OOPlayerForScripting();
	StationEntity			*stationForDocking = nil;
	
	if (oojsArgs.count() > 0)  stationForDocking = oo::ToStation(OOJSEntityFromJSValue(context, OOJS_ARGV[0]));	// a station's object is a ship's (bead oo-9ht.175)
	if (stationForDocking == nil)
	{
		cxx_OOJSReportBadArguments(context, "PlayerShip", "engageAutopilot", MIN(oojsArgs.count(), 1U), OOJS_ARGV, std::nullopt, "station");
		return false;
	}
	
	OOJS_RETURN_BOOL(player != nullptr ? player->engageAutopilotToStation(stationForDocking) : false);
	
	OOJS_NATIVE_EXIT
}
} // namespace


// disengageAutopilot()
namespace {
static bool PlayerShipDisengageAutopilot(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_NATIVE_ENTER(context)
	
	if (EXPECT_NOT(OOIsPlayerStale()))  OOJS_RETURN_VOID;
	
	if (PlayerEntity *player = OOPlayerForScripting())  player->disengageAutopilot();
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}
} // namespace

namespace {
static bool PlayerShipRequestDockingClearance(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_NATIVE_ENTER(context)
	
	if (EXPECT_NOT(OOIsPlayerStale()))  OOJS_RETURN_VOID;

	PlayerEntity			*player = OOPlayerForScripting();
	StationEntity			*stationForDocking = nil;
	
	if (oojsArgs.count() > 0)  stationForDocking = oo::ToStation(OOJSEntityFromJSValue(context, OOJS_ARGV[0]));	// a station's object is a ship's (bead oo-9ht.175)
	if (stationForDocking == nil)
	{
		cxx_OOJSReportBadArguments(context, "PlayerShip", "requestDockingClearance", MIN(oojsArgs.count(), 1U), OOJS_ARGV, std::nullopt, "station");
		return false;
	}

	if (player != nullptr)  player->requestDockingClearance(stationForDocking);
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}
} // namespace

namespace {
static bool PlayerShipCancelDockingRequest(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_NATIVE_ENTER(context)
	
	if (EXPECT_NOT(OOIsPlayerStale()))  OOJS_RETURN_VOID;

	PlayerEntity			*player = OOPlayerForScripting();
	StationEntity			*stationForDocking = nil;
	
	if (oojsArgs.count() > 0)  stationForDocking = oo::ToStation(OOJSEntityFromJSValue(context, OOJS_ARGV[0]));	// a station's object is a ship's (bead oo-9ht.175)
	if (stationForDocking == nil)
	{
		cxx_OOJSReportBadArguments(context, "PlayerShip", "cancelDockingRequest", MIN(oojsArgs.count(), 1U), OOJS_ARGV, std::nullopt, "station");
		return false;
	}

	if (player != nullptr)  player->cancelDockingRequest(stationForDocking);
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}
} // namespace

// awardEquipmentToCurrentPylon(externalTank: equipmentInfoExpression) : Boolean
namespace {
static bool PlayerShipAwardEquipmentToCurrentPylon(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_NATIVE_ENTER(context)
	
	if (EXPECT_NOT(OOIsPlayerStale()))  OOJS_RETURN_VOID;
	
	PlayerEntity			*player = OOPlayerForScripting();
	std::optional<std::string>				key;
	oo::Ref<OOEquipmentType>	eqType;	// the equipment types are converted (OOEquipmentType)
	
	if (oojsArgs.count() > 0)  key = JSValueToEquipmentKey(context, OOJS_ARGV[0]);
	if (key.has_value())  eqType = OOEquipmentType::equipmentTypeWithIdentifier(*key);
	if (EXPECT_NOT(!(eqType != nullptr && eqType->isMissileOrMine())))
	{
		cxx_OOJSReportBadArguments(context, "PlayerShip", "awardEquipmentToCurrentPylon", MIN(oojsArgs.count(), 1U), OOJS_ARGV, std::nullopt, "equipment type (external store)");
		return false;
	}
	
	OOJS_RETURN_BOOL(player != nullptr ? player->assignToActivePylon(key.value_or("")) : false);
	
	OOJS_NATIVE_EXIT
}
} // namespace


// addPassenger(name: string, start: int, destination: int, ETA: double, fee: double) : Boolean
namespace {
static bool PlayerShipAddPassenger(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_NATIVE_ENTER(context)
	
	PlayerEntity		*player = OOPlayerForScripting();
	std::optional<std::string> 			name;
	OOSystemID			start = 0, destination = 0;
	double			eta = 0.0, fee = 0.0, advance = 0.0;
	unsigned			risk = 0;

	if (oojsArgs.count() < 5)
	{
		cxx_OOJSReportBadArguments(context, "PlayerShip", "addPassenger", oojsArgs.count(), OOJS_ARGV, std::nullopt, "name, start, destination, ETA, fee");
		return false;
	}
	
	name = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (EXPECT_NOT(!name.has_value()))
	{
		cxx_OOJSReportBadArguments(context, "PlayerShip", "addPassenger", 1, &OOJS_ARGV[0], std::nullopt, "string");
		return false;
	}
	
	if (!ValidateContracts(context, oojsArgs, false, &start, &destination, &eta, &fee, &advance, "addPassenger", &risk))  return false; // always go through validate contracts (passenger)
	
	// Ensure there's space.
	if ((player != nullptr ? player->passengerCount() : 0) >= (player != nullptr ? player->passengerCapacity() : 0))  OOJS_RETURN_BOOL(false);
	
	bool OK = (player != nullptr ? player->addPassenger(name.value_or(""), start, destination, eta, fee, advance, risk) : false);
	OOJS_RETURN_BOOL(OK);
	
	OOJS_NATIVE_EXIT
}
} // namespace


// removePassenger(name :string)
namespace {
static bool PlayerShipRemovePassenger(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_NATIVE_ENTER(context)
	
	PlayerEntity		*player = OOPlayerForScripting();
	std::optional<std::string>			name;
	bool				OK = true;
	
	if (oojsArgs.count() > 0)  name = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (EXPECT_NOT(!name.has_value()))
	{
		cxx_OOJSReportBadArguments(context, "PlayerShip", "removePassenger", MIN(oojsArgs.count(), 1U), OOJS_ARGV, std::nullopt, "string");
		return false;
	}
	
	OK = (player != nullptr ? player->passengerCount() : 0) > 0 && !name->empty();
	if (OK)  OK = (player != nullptr ? player->removePassenger(name.value_or("")) : false);
	
	OOJS_RETURN_BOOL(OK);
	
	OOJS_NATIVE_EXIT
}
} // namespace


// addParcel(description: string, start: int, destination: int, ETA: double, fee: double) : Boolean
namespace {
static bool PlayerShipAddParcel(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_NATIVE_ENTER(context)
	
	PlayerEntity		*player = OOPlayerForScripting();
	std::optional<std::string> 			name;
	OOSystemID			start = 0, destination = 0;
	double			eta = 0.0, fee = 0.0, premium = 0.0;
	unsigned			risk = 0;
	
	if (oojsArgs.count() < 5)
	{
		cxx_OOJSReportBadArguments(context, "PlayerShip", "addParcel", oojsArgs.count(), OOJS_ARGV, std::nullopt, "name, start, destination, ETA, fee");
		return false;
	}
	
	name = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (EXPECT_NOT(!name.has_value()))
	{
		cxx_OOJSReportBadArguments(context, "PlayerShip", "addParcel", 1, &OOJS_ARGV[0], std::nullopt, "string");
		return false;
	}
	
	if (!ValidateContracts(context, oojsArgs, false, &start, &destination, &eta, &fee, &premium, "addParcel", &risk))  return false; // always go through validate contracts (passenger/parcel mode)
	
	// Ensure there's space.
	
	bool OK = (player != nullptr ? player->addParcel(name.value_or(""), start, destination, eta, fee, premium, risk) : false);
	OOJS_RETURN_BOOL(OK);
	
	OOJS_NATIVE_EXIT
}
} // namespace


// removeParcel(description :string)
namespace {
static bool PlayerShipRemoveParcel(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_NATIVE_ENTER(context)
	
	PlayerEntity		*player = OOPlayerForScripting();
	std::optional<std::string>			name;
	bool				OK = true;
	
	if (oojsArgs.count() > 0)  name = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (EXPECT_NOT(!name.has_value()))
	{
		cxx_OOJSReportBadArguments(context, "PlayerShip", "removeParcel", MIN(oojsArgs.count(), 1U), OOJS_ARGV, std::nullopt, "string");
		return false;
	}
	
	OK = (player != nullptr ? player->parcelCount() : 0) > 0 && !name->empty();
	if (OK)  OK = (player != nullptr ? player->removeParcel(name.value_or("")) : false);
	
	OOJS_RETURN_BOOL(OK);
	
	OOJS_NATIVE_EXIT
}
} // namespace


// awardContract(quantity: int, commodity: string, start: int, destination: int, eta: double, fee: double) : Boolean
namespace {
static bool PlayerShipAwardContract(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_NATIVE_ENTER(context)
	
	PlayerEntity		*player = OOPlayerForScripting();
	std::optional<std::string> 			key;
	int32_t 				qty = 0;
	OOSystemID			start = 0, destination = 0;
	double			eta = 0.0, fee = 0.0, premium = 0.0;
	
	if (oojsArgs.count() < 6)
	{
		cxx_OOJSReportBadArguments(context, "PlayerShip", "awardContract", oojsArgs.count(), OOJS_ARGV, std::nullopt, "quantity, commodity, start, destination, ETA, fee");
		return false;
	}
	
	if (!ooscript::valueToInt32(context, (OOJS_ARGV[0]), &qty))
	{
		cxx_OOJSReportBadArguments(context, "PlayerShip", "awardContract", 1, &OOJS_ARGV[0], std::nullopt, "positive integer (cargo quantity)");
		return false;
	}
	
	key = cxx_OOStringFromJSValue(context, OOJS_ARGV[1]);
	if (EXPECT_NOT(!key.has_value()))
	{
		cxx_OOJSReportBadArguments(context, "PlayerShip", "awardContract", 1, &OOJS_ARGV[1], std::nullopt, "string (commodity identifier)");
		return false;
	}
	
	if (!ValidateContracts(context, oojsArgs, true, &start, &destination, &eta, &fee, &premium, "awardContract", NULL))  return false; // always go through validate contracts (cargo)
	
	bool OK = (player != nullptr ? player->awardContract(qty, key.value_or(""), start, destination, eta, fee, premium) : false);
	OOJS_RETURN_BOOL(OK);
	
	OOJS_NATIVE_EXIT
}
} // namespace


// removeContract(commodity: string, destination: int)
namespace {
static bool PlayerShipRemoveContract(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_NATIVE_ENTER(context)
	
	PlayerEntity		*player = OOPlayerForScripting();
	std::optional<std::string>			key;
	int32_t				dest = 0;
	
	if (oojsArgs.count() < 2)
	{
		cxx_OOJSReportBadArguments(context, "PlayerShip", "removeContract", oojsArgs.count(), OOJS_ARGV, std::nullopt, "commodity, destination");
		return false;
	}
	
	key = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
	
	if (EXPECT_NOT(!key.has_value()))
	{
		cxx_OOJSReportBadArguments(context, "PlayerShip", "removeContract", 1, &OOJS_ARGV[0], std::nullopt, "string (commodity identifier)");
		return false;
	}
	
	if (!ooscript::valueToInt32(context, (OOJS_ARGV[1]), &dest) || dest < 0 || dest > 255)
	{
		cxx_OOJSReportBadArguments(context, "PlayerShip", "removeContract", 1, &OOJS_ARGV[1], std::nullopt, "system ID");
		return false;
	}
	
	bool OK = (player != nullptr ? player->removeContract(key.value_or(""), (unsigned)dest) : false);	
	OOJS_RETURN_BOOL(OK);
	
	OOJS_NATIVE_EXIT
}
} // namespace


// setCustomView(position:vector, orientation:quaternion [, weapon:string])
namespace {
static bool PlayerShipSetCustomView(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_NATIVE_ENTER(context)
	
	PlayerEntity		*player = OOPlayerForScripting();
	
	if (oojsArgs.count() < 2)
	{
		cxx_OOJSReportBadArguments(context, "PlayerShip", "setCustomView", oojsArgs.count(), OOJS_ARGV, std::nullopt, "position, orientiation, [weapon]");
		return false;
	}

// must be in custom view
	if ((UNIVERSE != nullptr ? UNIVERSE->getViewDirection() : OOViewID{}) != VIEW_CUSTOM) 
	{
		cxx_OOJSReportError(context, "PlayerShip.setCustomView only works when custom view is active.");
		return false;
	}

	oo::PList::Dict				viewData;

	Vector position = kZeroVector;
	bool gotpos = JSValueToVector(context, OOJS_ARGV[0], &position);
	if (!gotpos)
	{
		cxx_OOJSReportBadArguments(context, "PlayerShip", "setCustomView", oojsArgs.count(), OOJS_ARGV, std::nullopt, "position, orientiation, [weapon]");
		return false;
	}
	std::string positionstr = oo::str::format("%f %f %f",position.x,position.y,position.z);   

	Quaternion orientation = kIdentityQuaternion;
	bool gotquat = JSValueToQuaternion(context, OOJS_ARGV[1], &orientation);
	if (!gotquat)
	{
		cxx_OOJSReportBadArguments(context, "PlayerShip", "setCustomView", oojsArgs.count(), OOJS_ARGV, std::nullopt, "position, orientiation, [weapon]");
		return false;
	}
	std::string orientationstr = oo::str::format("%f %f %f %f",orientation.w,orientation.x,orientation.y,orientation.z);

	viewData["view_position"] = positionstr;
	viewData["view_orientation"] = orientationstr;

	if (oojsArgs.count() > 2)
	{
		std::optional<std::string> facing = cxx_OOStringFromJSValue(context,OOJS_ARGV[2]);
		// -setObject:forKey: raised on a nil facing (GNUstep 1.31.1's text).
		if (!facing.has_value())  OORaiseException(OOInvalidArgumentException, "Tried to add nil value for key '%s' to dictionary", "weapon_facing");
		viewData["weapon_facing"] = *facing;
	} 

	if (player != nullptr)  player->setCustomViewDataFromDictionary(oo::PList(std::move(viewData)), false);
	if (player != nullptr)  player->noteSwitchToView(VIEW_CUSTOM, VIEW_CUSTOM);


	OOJS_RETURN_BOOL(true);
	OOJS_NATIVE_EXIT
}
} // namespace


// resetCustomView()
namespace {
static bool PlayerShipResetCustomView(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_NATIVE_ENTER(context)
	
	PlayerEntity		*player = OOPlayerForScripting();
	
// must be in custom view
	if ((UNIVERSE != nullptr ? UNIVERSE->getViewDirection() : OOViewID{}) != VIEW_CUSTOM) 
	{
		cxx_OOJSReportError(context, "PlayerShip.setCustomView only works when custom view is active.");
		return false;
	}

	if (player != nullptr)  player->resetCustomView();
	if (player != nullptr)  player->noteSwitchToView(VIEW_CUSTOM, VIEW_CUSTOM);

	OOJS_RETURN_BOOL(true);
	OOJS_NATIVE_EXIT
}
} // namespace


// resetScannerZoom()
namespace {
static bool PlayerShipResetScannerZoom(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_NATIVE_ENTER(context)
	
	PlayerEntity		*player = OOPlayerForScripting();
	
	if (player != nullptr)  player->resetScannerZoom();

	OOJS_RETURN_VOID;
	OOJS_NATIVE_EXIT
}
} // namespace


// takeInternalDamage()
namespace {
static bool PlayerShipTakeInternalDamage(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_NATIVE_ENTER(context)
	
	PlayerEntity		*player = OOPlayerForScripting();
	
	bool took = (player != nullptr ? player->takeInternalDamage() : false);

	OOJS_RETURN_BOOL(took);
	OOJS_NATIVE_EXIT
}
} // namespace


// beginHyperspaceCountdown([int: spin_time])
namespace {
static bool PlayerShipBeginHyperspaceCountdown(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_NATIVE_ENTER(context)
	
	PlayerEntity		*player = OOPlayerForScripting();
	int32_t                           spin_time;
	int32_t                           witchspaceSpinUpTime = 0;
	bool begun = false;
	if (oojsArgs.count() < 1) 
	{
		witchspaceSpinUpTime = 0;
#ifdef OO_DUMP_PLANETINFO
		// quick intersystem jumps for debugging
		witchspaceSpinUpTime = 1;
#endif
	}
	else
	{
		if (!ooscript::valueToInt32(context, (OOJS_ARGV[0]), &spin_time) || spin_time < 5 || spin_time > 60)
		{
			cxx_OOJSReportBadArguments(context, "PlayerShip", "beginHyperspaceCountdown", 1, &OOJS_ARGV[0], std::nullopt, "between 5 and 60 seconds");
			return false;
		}
		if (spin_time < 5) 
		{
			witchspaceSpinUpTime = 5;
		}
		else
		{
			witchspaceSpinUpTime = spin_time;
		}
	}
	if ((player != nullptr ? player->hasHyperspaceMotor() : false) && (player != nullptr ? player->status() : OOEntityStatus{}) == STATUS_IN_FLIGHT && (player != nullptr ? player->witchJumpChecklist(false) : false))
	{
		if (player != nullptr)  player->beginWitchspaceCountdown(witchspaceSpinUpTime);
		begun = true;
	}
	OOJS_RETURN_BOOL(begun);
	OOJS_NATIVE_EXIT
}
} // namespace


// cancelHyperspaceCountdown()
namespace {
static bool PlayerShipCancelHyperspaceCountdown(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_NATIVE_ENTER(context)
       
	PlayerEntity            *player = OOPlayerForScripting();
       
	bool cancelled = false;
	if ((player != nullptr ? player->hasHyperspaceMotor() : false) && (player != nullptr ? player->status() : OOEntityStatus{}) == STATUS_WITCHSPACE_COUNTDOWN)
	{
		if (player != nullptr)  player->cancelWitchspaceCountdown();
		if (player != nullptr)  player->setJumpType(false);
		cancelled = true;
	}

	OOJS_RETURN_BOOL(cancelled);
	OOJS_NATIVE_EXIT
		
}
} // namespace


namespace {
static bool PlayerShipBeginGalacticHyperspaceCountdown(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_NATIVE_ENTER(context)
	
	PlayerEntity		*player = OOPlayerForScripting();
	int32_t				spin_time;
	int32_t				witchspaceSpinUpTime = 5;
	bool begun = false;
	if (oojsArgs.count() == 1) 
	{

		if (!ooscript::valueToInt32(context, (OOJS_ARGV[0]), &spin_time) || spin_time < 5 || spin_time > 60)
		{
			cxx_OOJSReportBadArguments(context, "PlayerShip", "beginGalacticHyperspaceCountdown", 1, &OOJS_ARGV[0], std::nullopt, "between 5 and 60 seconds");
			return false;
		}
		if (spin_time < 5) 
		{
			witchspaceSpinUpTime = 5;
		}
		else
		{
			witchspaceSpinUpTime = spin_time;
		}
	}
	if ((player != nullptr ? player->hasEquipmentItemProviding("EQ_GAL_DRIVE") : false) && (player != nullptr ? player->status() : OOEntityStatus{}) == STATUS_IN_FLIGHT && (player != nullptr ? player->witchJumpChecklist(true) : false))
	{
		if (player != nullptr)  player->setJumpType(true);
		if (player != nullptr)  player->setWitchspaceCountdown(witchspaceSpinUpTime);
		if (player != nullptr)  player->setStatus(STATUS_WITCHSPACE_COUNTDOWN);
		if (player != nullptr)  player->playGalacticHyperspace();
		// say it!
		if (UNIVERSE != nullptr)  UNIVERSE->addMessage(oo::str::format(OO_DESC("witch-galactic-in-f-seconds").c_str(), witchspaceSpinUpTime), 1.0);
		begun = true;
	}
	OOJS_RETURN_BOOL(begun);
	OOJS_NATIVE_EXIT
}
} // namespace


// setMultiFunctionDisplay(index,key)
namespace {
static bool PlayerShipSetMultiFunctionDisplay(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_NATIVE_ENTER(context)

	std::optional<std::string>		key;
	uint32_t			index = 0;
	PlayerEntity	*player = OOPlayerForScripting();
	bool			OK = true;

	if (oojsArgs.count() > 0)  
	{
		if (!ooscript::valueToECMAUint32(context, (OOJS_ARGV[0]), &index))
		{
			cxx_OOJSReportBadArguments(context, "PlayerShip", "setMultiFunctionDisplay", MIN(oojsArgs.count(), 1U), OOJS_ARGV, std::nullopt, "number (index) [, string (key)]");
			return false;
		}
	}

	if (oojsArgs.count() > 1)
	{
		key = cxx_OOStringFromJSValue(context, OOJS_ARGV[1]);
	}

	OK = (player != nullptr ? player->setMultiFunctionDisplay(index, key) : false);

	OOJS_RETURN_BOOL(OK);

	OOJS_NATIVE_EXIT
}
} // namespace


// setMultiFunctionText(key,value)
namespace {
static bool PlayerShipSetMultiFunctionText(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_NATIVE_ENTER(context)

	std::optional<std::string>				key;
	std::optional<std::string>	value;
	PlayerEntity			*player = OOPlayerForScripting();
	bool					reflow = false;

	if (oojsArgs.count() > 0)  
	{
		key = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
	}
	if (!key.has_value())
	{
		cxx_OOJSReportBadArguments(context, "PlayerShip", "setMultiFunctionText", MIN(oojsArgs.count(), 1U), OOJS_ARGV, std::nullopt, "string (key) [, string (text)]");
		return false;
	}
	if (oojsArgs.count() > 1)
	{
		value = cxx_OOStringFromJSValue(context, OOJS_ARGV[1]);
	}
	if (oojsArgs.count() > 2 && EXPECT_NOT(!ooscript::valueToBoolean(context, (OOJS_ARGV[2]), &reflow)))
	{
		cxx_OOJSReportBadArguments(context, "setMultiFunctionText", "reflow", oojsArgs.count(), OOJS_ARGV, std::nullopt, "boolean");
		return false;
	}

	if (!reflow)
	{
		if (player != nullptr)  player->setMultiFunctionText(value, key);
	}
	else
	{
		GuiDisplayGen	*gui = (UNIVERSE != nullptr ? UNIVERSE->getGui() : nullptr);
		if (player != nullptr)  player->setMultiFunctionText(gui->reflowTextForMFD(value), key);
	}

	OOJS_RETURN_VOID;

	OOJS_NATIVE_EXIT
}
} // namespace

// setPrimedEquipment(key, [noMessage])
namespace {
static bool PlayerShipSetPrimedEquipment(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_NATIVE_ENTER(context)

	std::optional<std::string>				key;
	PlayerEntity			*player = OOPlayerForScripting();
	bool					showMsg = true;

	if (oojsArgs.count() > 0)  
	{
		key = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
	}
	if (!key.has_value())
	{
		cxx_OOJSReportBadArguments(context, "PlayerShip", "setPrimedEquipment", MIN(oojsArgs.count(), 1U), OOJS_ARGV, std::nullopt, "string (key)");
		return false;
	}
	if (oojsArgs.count() > 1 && EXPECT_NOT(!ooscript::valueToBoolean(context, (OOJS_ARGV[1]), &showMsg)))
 	{
 		cxx_OOJSReportBadArguments(context, "PlayerShip", "setPrimedEquipment", MIN(oojsArgs.count(), 2U), OOJS_ARGV, std::nullopt, "boolean");
 		return false;
 	}

	OOJS_RETURN_BOOL(key.has_value() ? (player != nullptr ? player->setPrimedEquipment(*key, showMsg) : false) : false);

	OOJS_NATIVE_EXIT
}
} // namespace


// setCustomHUDDial(key,value)
namespace {
static bool PlayerShipSetCustomHUDDial(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_NATIVE_ENTER(context)

	std::optional<std::string>				key;
	oo::PList				value;
	PlayerEntity			*player = OOPlayerForScripting();

	if (oojsArgs.count() > 0)  
	{
		key = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
	}
	if (!key.has_value())
	{
		cxx_OOJSReportBadArguments(context, "PlayerShip", "setCustomHUDDial", MIN(oojsArgs.count(), 1U), OOJS_ARGV, std::nullopt, "string (key), value]");
		return false;
	}
	if (oojsArgs.count() > 1)
	{
		value = cxx_OOJSPListFromJSValue(context, OOJS_ARGV[1]);
	}
	else
	{
		value = oo::PList(std::string());
	}

	if (player != nullptr)  player->setDialCustom(value, key.value_or(""));
	

	OOJS_RETURN_VOID;

	OOJS_NATIVE_EXIT
}
} // namespace


namespace {
static bool PlayerShipHideHUDSelector(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_NATIVE_ENTER(context)

	std::optional<std::string>				key;
	PlayerEntity			*player = OOPlayerForScripting();

	if (oojsArgs.count() > 0)  
	{
		key = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
	}
	if (!key.has_value())
	{
		cxx_OOJSReportBadArguments(context, "PlayerShip", "hideHUDSelector", MIN(oojsArgs.count(), 1U), OOJS_ARGV, std::nullopt, "string (selector)");
		return false;
	}
	if (HeadUpDisplay *hud = HudOf(player))  hud->setHiddenSelector(key.value_or(""), true);
	
	OOJS_RETURN_VOID;

	OOJS_NATIVE_EXIT
}
} // namespace


namespace {
static bool PlayerShipShowHUDSelector(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_NATIVE_ENTER(context)

	std::optional<std::string>				key;
	PlayerEntity			*player = OOPlayerForScripting();

	if (oojsArgs.count() > 0)  
	{
		key = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
	}
	if (!key.has_value())
	{
		cxx_OOJSReportBadArguments(context, "PlayerShip", "hideHUDSelector", MIN(oojsArgs.count(), 1U), OOJS_ARGV, std::nullopt, "string (selector)");
		return false;
	}
	if (HeadUpDisplay *hud = HudOf(player))  hud->setHiddenSelector(key.value_or(""), false);
	
	OOJS_RETURN_VOID;

	OOJS_NATIVE_EXIT
}
} // namespace



namespace {
static bool ValidateContracts(ooscript::Context context, ooscript::CallArgs &oojsArgs, bool isCargo, OOSystemID *start, OOSystemID *destination, double *eta, double *fee, double *premium, const std::string &functionName, unsigned *risk)
{
	OOJS_PROFILE_ENTER
	
	OOCParameterAssert(context != NULL && oojsArgs.rawVp() != NULL && start != NULL && destination != NULL && eta != NULL && fee != NULL);
	
	Context cx = (context);
	unsigned		uValue, offset = isCargo ? 2 : 1;
	double		fValue;
	int32_t			iValue;
	
	if (!ooscript::valueToInt32(cx, (OOJS_ARGV[offset + 0]), &iValue) || iValue < 0 || iValue > kOOMaximumSystemID)
	{
		cxx_OOJSReportBadArguments(context, "PlayerShip", functionName, 1, &OOJS_ARGV[offset + 0], std::nullopt, "system ID");
		return false;
	}
	*start = iValue;
	
	if (!ooscript::valueToInt32(cx, (OOJS_ARGV[offset + 1]), &iValue) || iValue < 0 || iValue > kOOMaximumSystemID)
	{
		cxx_OOJSReportBadArguments(context, "PlayerShip", functionName, 1, &OOJS_ARGV[offset + 1], std::nullopt, "system ID");
		return false;
	}
	*destination = iValue;
	
	
	if (!ooscript::valueToNumber(cx, (OOJS_ARGV[offset + 2]), &fValue) || !isfinite(fValue) || fValue <= (PLAYER != nullptr ? PLAYER->clockTime() : 0.0))
	{
		cxx_OOJSReportBadArguments(context, "PlayerShip", functionName, 1, &OOJS_ARGV[offset + 2], std::nullopt, "number (future time)");
		return false;
	}
	*eta = fValue;
	
	if (!ooscript::valueToNumber(cx, (OOJS_ARGV[offset + 3]), &fValue) || !isfinite(fValue) || fValue < 0.0)
	{
		cxx_OOJSReportBadArguments(context, "PlayerShip", functionName, 1, &OOJS_ARGV[offset + 3], std::nullopt, "number (credits quantity)");
		return false;
	}
	*fee = fValue;

	if (oojsArgs.count() > offset+4 && ooscript::valueToNumber(cx, (OOJS_ARGV[offset + 4]), &fValue) && isfinite(fValue) && fValue >= 0.0)
	{
		*premium = fValue;
	}

	if (!isCargo)
	{
		if (oojsArgs.count() > offset+5 && ooscript::valueToECMAUint32(cx, (OOJS_ARGV[offset + 5]), &uValue) && isfinite((double)uValue))
		{
			*risk = uValue;
		}
	}
	
	return true;
	
	OOJS_PROFILE_EXIT
}
} // namespace
