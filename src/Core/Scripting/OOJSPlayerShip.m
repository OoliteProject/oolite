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

#import "OOCollectionExtractors.h"
#import "OOJSPlayer.h"
#import "OOJSEntity.h"
#import "OOJSShip.h"
#import "OOJSVector.h"
#import "OOJSQuaternion.h"
#import "OOJavaScriptEngine.h"
#import "EntityOOJavaScriptExtensions.h"
#import "OOSystemDescriptionManager.h"
#import "PlayerEntity.h"
#import "PlayerEntityControls.h"
#import "PlayerEntityContracts.h"
#import "PlayerEntityScriptMethods.h"
#import "PlayerEntityLegacyScriptEngine.h"
#import "HeadUpDisplay.h"
#import "StationEntity.h"

#import "OOConstToJSString.h"
#import "OOConstToString.h"
#import "OOFunctionAttributes.h"
#import "OOEquipmentType.h"
#import "OOJSEquipmentInfo.h"


static JSObject		*sPlayerShipPrototype;
static JSObject		*sPlayerShipObject;


static JSBool PlayerShipGetProperty(JSContext *context, JSObject *this, jsid propID, jsval *value);
static JSBool PlayerShipSetProperty(JSContext *context, JSObject *this, jsid propID, JSBool strict, jsval *value);

static JSBool PlayerShipLaunch(JSContext *context, uintN argc, jsval *vp);
static JSBool PlayerShipRemoveAllCargo(JSContext *context, uintN argc, jsval *vp);
static JSBool PlayerShipUseSpecialCargo(JSContext *context, uintN argc, jsval *vp);
static JSBool PlayerShipEngageAutopilotToStation(JSContext *context, uintN argc, jsval *vp);
static JSBool PlayerShipDisengageAutopilot(JSContext *context, uintN argc, jsval *vp);
static JSBool PlayerShipRequestDockingClearance(JSContext *context, uintN argc, jsval *vp);
static JSBool PlayerShipCancelDockingRequest(JSContext *context, uintN argc, jsval *vp);
static JSBool PlayerShipAwardEquipmentToCurrentPylon(JSContext *context, uintN argc, jsval *vp);
static JSBool PlayerShipAddPassenger(JSContext *context, uintN argc, jsval *vp);
static JSBool PlayerShipRemovePassenger(JSContext *context, uintN argc, jsval *vp);
static JSBool PlayerShipAddParcel(JSContext *context, uintN argc, jsval *vp);
static JSBool PlayerShipRemoveParcel(JSContext *context, uintN argc, jsval *vp);
static JSBool PlayerShipAwardContract(JSContext *context, uintN argc, jsval *vp);
static JSBool PlayerShipRemoveContract(JSContext *context, uintN argc, jsval *vp);
static JSBool PlayerShipSetCustomView(JSContext *context, uintN argc, jsval *vp);
static JSBool PlayerShipSetPrimedEquipment(JSContext *context, uintN argc, jsval *vp);
static JSBool PlayerShipResetCustomView(JSContext *context, uintN argc, jsval *vp);
static JSBool PlayerShipResetScannerZoom(JSContext *context, uintN argc, jsval *vp);
static JSBool PlayerShipTakeInternalDamage(JSContext *context, uintN argc, jsval *vp);
static JSBool PlayerShipBeginHyperspaceCountdown(JSContext *context, uintN argc, jsval *vp);
static JSBool PlayerShipCancelHyperspaceCountdown(JSContext *context, uintN argc, jsval *vp);
static JSBool PlayerShipSetMultiFunctionDisplay(JSContext *context, uintN argc, jsval *vp);
static JSBool PlayerShipSetMultiFunctionText(JSContext *context, uintN argc, jsval *vp);
static JSBool PlayerShipHideHUDSelector(JSContext *context, uintN argc, jsval *vp);
static JSBool PlayerShipShowHUDSelector(JSContext *context, uintN argc, jsval *vp);
static JSBool PlayerShipSetCustomHUDDial(JSContext *context, uintN argc, jsval *vp);

static BOOL ValidateContracts(JSContext *context, uintN argc, jsval *vp, BOOL isCargo, OOSystemID *start, OOSystemID *destination, double *eta, double *fee, double *premium, NSString *functionName, unsigned *risk);


static JSClass sPlayerShipClass =
{
	"PlayerShip",
	JSCLASS_HAS_PRIVATE,
	
	JS_PropertyStub,		// addProperty
	JS_PropertyStub,		// delProperty
	PlayerShipGetProperty,	// getProperty
	PlayerShipSetProperty,	// setProperty
	JS_EnumerateStub,		// enumerate
	JS_ResolveStub,			// resolve
	JS_ConvertStub,			// convert
	OOJSObjectWrapperFinalize,// finalize
	JSCLASS_NO_OPTIONAL_MEMBERS
};


enum
{
	// Property IDs
	kPlayerShip_aftShield,						// aft shield charge level, nonnegative float, read/write
	kPlayerShip_aftShieldRechargeRate,			// aft shield recharge rate, positive float, read-only
	kPlayerShip_compassMode,					// compass mode, string, read/write
	kPlayerShip_compassTarget,					// object targeted by the compass, entity, read-only
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
	kPlayerShip_missilesOnline,      // bool (false for ident mode, true for missile mode)
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
	kPlayerShip_scannerNonLinear,				// non linear scanner setting, boolean, read/write
	kPlayerShip_scannerUltraZoom,				// scanner zoom in powers of 2, boolean, read/write
	kPlayerShip_scoopOverride,					// Scooping
	kPlayerShip_serviceLevel,					// servicing level, positive int 75-100, read-only
	kPlayerShip_specialCargo,					// special cargo, string, read-only
	kPlayerShip_targetSystem,					// target system id, int, read-write
	kPlayerShip_nextSystem,						// next hop system id, read-only
	kPlayerShip_infoSystem,						// info (F7 screen) system id, int, read-write
	kPlayerShip_torusEngaged,					// torus in use, boolean, read-only
	kPlayerShip_viewDirection,					// view direction identifier, string, read-only
	kPlayerShip_viewPositionAft,					// view position offset, vector, read-only
	kPlayerShip_viewPositionForward,					// view position offset, vector, read-only
	kPlayerShip_viewPositionPort,					// view position offset, vector, read-only
	kPlayerShip_viewPositionStarboard,					// view position offset, vector, read-only
	kPlayerShip_weaponsOnline,					// weapons online status, boolean, read-only
	kPlayerShip_yaw,							// yaw (overrules Ship)
};


static JSPropertySpec sPlayerShipProperties[] =
{
	// JS name							ID											flags
	{ "aftShield",						kPlayerShip_aftShield,						OOJS_PROP_READWRITE_CB },
	{ "aftShieldRechargeRate",			kPlayerShip_aftShieldRechargeRate,			OOJS_PROP_READWRITE_CB },
	{ "compassMode",					kPlayerShip_compassMode,					OOJS_PROP_READWRITE_CB },
	{ "compassTarget",					kPlayerShip_compassTarget,					OOJS_PROP_READONLY_CB },
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
	{ "pitch",							kPlayerShip_pitch,							OOJS_PROP_READONLY_CB },
	{ "primedEquipment",				kPlayerShip_primedEquipment,				OOJS_PROP_READWRITE_CB },
	{ "renovationCost",					kPlayerShip_renovationCost,					OOJS_PROP_READONLY_CB },
	{ "reticleColorTarget",				kPlayerShip_reticleColorTarget,				OOJS_PROP_READWRITE_CB },
	{ "reticleColorTargetSensitive",	kPlayerShip_reticleColorTargetSensitive,	OOJS_PROP_READWRITE_CB },
	{ "reticleColorWormhole",			kPlayerShip_reticleColorWormhole,			OOJS_PROP_READWRITE_CB },
	{ "renovationMultiplier",			kPlayerShip_renovationMultiplier,			OOJS_PROP_READONLY_CB },
	{ "reticleTargetSensitive",			kPlayerShip_reticleTargetSensitive,			OOJS_PROP_READWRITE_CB },
	{ "roll",							kPlayerShip_roll,							OOJS_PROP_READONLY_CB },
	{ "routeMode",						kPlayerShip_routeMode,						OOJS_PROP_READONLY_CB },
	{ "scannerNonLinear",				kPlayerShip_scannerNonLinear,				OOJS_PROP_READWRITE_CB },
	{ "scannerUltraZoom",				kPlayerShip_scannerUltraZoom,				OOJS_PROP_READWRITE_CB },
	{ "scoopOverride",					kPlayerShip_scoopOverride,					OOJS_PROP_READWRITE_CB },
	{ "serviceLevel",					kPlayerShip_serviceLevel,					OOJS_PROP_READWRITE_CB },
	{ "specialCargo",					kPlayerShip_specialCargo,					OOJS_PROP_READONLY_CB },
	{ "targetSystem",					kPlayerShip_targetSystem,					OOJS_PROP_READWRITE_CB },
	{ "nextSystem",                     kPlayerShip_nextSystem,                     OOJS_PROP_READONLY_CB },
	{ "infoSystem",						kPlayerShip_infoSystem,						OOJS_PROP_READWRITE_CB },
	{ "torusEngaged",					kPlayerShip_torusEngaged,					OOJS_PROP_READONLY_CB },
	{ "viewDirection",					kPlayerShip_viewDirection,					OOJS_PROP_READONLY_CB },
	{ "viewPositionAft",				kPlayerShip_viewPositionAft,				OOJS_PROP_READONLY_CB },
	{ "viewPositionForward",			kPlayerShip_viewPositionForward,			OOJS_PROP_READONLY_CB },
	{ "viewPositionPort",				kPlayerShip_viewPositionPort,				OOJS_PROP_READONLY_CB },
	{ "viewPositionStarboard",			kPlayerShip_viewPositionStarboard,			OOJS_PROP_READONLY_CB },
	{ "weaponsOnline",					kPlayerShip_weaponsOnline,					OOJS_PROP_READONLY_CB },
	{ "yaw",							kPlayerShip_yaw,							OOJS_PROP_READONLY_CB },
	{ 0 }			
};


static JSFunctionSpec sPlayerShipMethods[] =
{
	// JS name						Function							min args
	{ "addParcel",   					PlayerShipAddParcel,						0 },
	{ "addPassenger",					PlayerShipAddPassenger,						0 },
	{ "awardContract",					PlayerShipAwardContract,					0 },
	{ "awardEquipmentToCurrentPylon",	PlayerShipAwardEquipmentToCurrentPylon,		1 },
	{ "beginHyperspaceCountdown",       PlayerShipBeginHyperspaceCountdown,         0 },
	{ "cancelDockingRequest",			PlayerShipCancelDockingRequest,             1 },
	{ "cancelHyperspaceCountdown",      PlayerShipCancelHyperspaceCountdown,        0 },
	{ "disengageAutopilot",				PlayerShipDisengageAutopilot,				0 },
	{ "engageAutopilotToStation",		PlayerShipEngageAutopilotToStation,			1 },
	{ "hideHUDSelector",				PlayerShipHideHUDSelector,					1 },
	{ "launch",							PlayerShipLaunch,							0 },
	{ "removeAllCargo",					PlayerShipRemoveAllCargo,					0 },
	{ "removeContract",					PlayerShipRemoveContract,					2 },
	{ "removeParcel",                   PlayerShipRemoveParcel,                     1 },
	{ "removePassenger",				PlayerShipRemovePassenger,					1 },
	{ "requestDockingClearance",        PlayerShipRequestDockingClearance,          1 },
	{ "resetCustomView",				PlayerShipResetCustomView,					0 },
	{ "resetScannerZoom",				PlayerShipResetScannerZoom,					0 },
	{ "setCustomView",					PlayerShipSetCustomView,					2 },
	{ "setCustomHUDDial",				PlayerShipSetCustomHUDDial,					2 },
	{ "setMultiFunctionDisplay",		PlayerShipSetMultiFunctionDisplay,			1 },
	{ "setMultiFunctionText",			PlayerShipSetMultiFunctionText,				1 },
	{ "setPrimedEquipment",				PlayerShipSetPrimedEquipment,               1 },
	{ "showHUDSelector",				PlayerShipShowHUDSelector,					1 },
	{ "takeInternalDamage",				PlayerShipTakeInternalDamage,				0 },
	{ "useSpecialCargo",				PlayerShipUseSpecialCargo,					1 },
	{ 0 }
};


void InitOOJSPlayerShip(JSContext *context, JSObject *global)
{
	sPlayerShipPrototype = JS_InitClass(context, global, JSShipPrototype(), &sPlayerShipClass, OOJSUnconstructableConstruct, 0, sPlayerShipProperties, sPlayerShipMethods, NULL, NULL);
	OOJSRegisterObjectConverter(&sPlayerShipClass, OOJSBasicPrivateObjectConverter);
	OOJSRegisterSubclass(&sPlayerShipClass, JSShipClass());
	
	PlayerEntity *player = [PlayerEntity sharedPlayer];	// NOTE: at time of writing, this creates the player entity. Don't use PLAYER here.
	
	// Create ship object as a property of the player object.
	sPlayerShipObject = JS_DefineObject(context, JSPlayerObject(), "ship", &sPlayerShipClass, sPlayerShipPrototype, OOJS_PROP_READONLY);
	JS_SetPrivate(context, sPlayerShipObject, OOConsumeReference([player weakRetain]));
	[player setJSSelf:sPlayerShipObject context:context];
	// Analyzer: object leaked. [Expected, object is retained by JS object.]
}


JSClass *JSPlayerShipClass(void)
{
	return &sPlayerShipClass;
}


JSObject *JSPlayerShipPrototype(void)
{
	return sPlayerShipPrototype;
}


JSObject *JSPlayerShipObject(void)
{
	return sPlayerShipObject;
}


@implementation PlayerEntity (OOJavaScriptExtensions)

- (NSString *) oo_jsClassName
{
	return @"PlayerShip";
}


- (void) setJSSelf:(JSObject *)val context:(JSContext *)context
{
	_jsSelf = val;
	OOJSAddGCObjectRoot(context, &_jsSelf, "Player jsSelf");
	
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(javaScriptEngineWillReset:)
												 name:kOOJavaScriptEngineWillResetNotification
											   object:[OOJavaScriptEngine sharedEngine]];
}


- (void) javaScriptEngineWillReset:(NSNotification *)notification
{
	[[NSNotificationCenter defaultCenter] removeObserver:self
													name:kOOJavaScriptEngineWillResetNotification
												  object:[OOJavaScriptEngine sharedEngine]];
	
	if (_jsSelf != NULL)
	{
		
		JSContext *context = OOJSAcquireContext();
		JS_RemoveObjectRoot(context, &_jsSelf);
		_jsSelf = NULL;
		OOJSRelinquishContext(context);
	}
}

@end


static JSBool PlayerShipGetProperty(JSContext *context, JSObject *this, jsid propID, jsval *value)
{
	if (!JSID_IS_INT(propID))  return YES;
	
	OOJS_NATIVE_ENTER(context)
	
	if (EXPECT_NOT(OOIsPlayerStale() || this == sPlayerShipPrototype))  { *value = JSVAL_VOID; return YES; }
	
	id							result = nil;
	PlayerEntity				*player = OOPlayerForScripting();
	
	switch (JSID_TO_INT(propID))
	{
                      
		case kPlayerShip_fuelLeakRate:
			return JS_NewNumberValue(context, [player fuelLeakRate], value);
			
		case kPlayerShip_docked:
			*value = OOJSValueFromBOOL([player isDocked]);
			return YES;
			
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
			*value = OOJSValueFromBOOL([[player hud] reticleTargetSensitive]);
			return YES;
			
		case kPlayerShip_galacticHyperspaceBehaviour:
			*value = OOJSValueFromGalacticHyperspaceBehaviour(context, [player galacticHyperspaceBehaviour]);
			return YES;
			
		case kPlayerShip_galacticHyperspaceFixedCoords:
			return NSPointToVectorJSValue(context, [player galacticHyperspaceFixedCoords], value);
			
		case kPlayerShip_galacticHyperspaceFixedCoordsInLY:
			return VectorToJSValue(context, OOGalacticCoordinatesFromInternal([player galacticHyperspaceFixedCoords]), value);

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
			return JS_NewNumberValue(context, [player forwardShieldLevel], value);
			
		case kPlayerShip_aftShield:
			return JS_NewNumberValue(context, [player aftShieldLevel], value);
			
		case kPlayerShip_maxForwardShield:
			return JS_NewNumberValue(context, [player maxForwardShieldLevel], value);
			
		case kPlayerShip_maxAftShield:
			return JS_NewNumberValue(context, [player maxAftShieldLevel], value);
			
		case kPlayerShip_forwardShieldRechargeRate:
			// No distinction made internally
			return JS_NewNumberValue(context, [player forwardShieldRechargeRate], value);

		case kPlayerShip_aftShieldRechargeRate:
			// No distinction made internally
			return JS_NewNumberValue(context, [player aftShieldRechargeRate], value);
			
		case kPlayerShip_multiFunctionDisplays:
			return JS_NewNumberValue(context, [[player hud] mfdCount], value);

		case kPlayerShip_multiFunctionDisplayList:
			result = [player multiFunctionDisplayList];
			break;

		case kPlayerShip_missilesOnline:
			*value = OOJSValueFromBOOL(![player dialIdentEngaged]);
			return YES;

		case kPlayerShip_galaxyCoordinates:
			return NSPointToVectorJSValue(context, [player galaxy_coordinates], value);
			
		case kPlayerShip_galaxyCoordinatesInLY:
			return VectorToJSValue(context, OOGalacticCoordinatesFromInternal([player galaxy_coordinates]), value);
			
		case kPlayerShip_cursorCoordinates:
			return NSPointToVectorJSValue(context, [player cursor_coordinates], value);

		case kPlayerShip_cursorCoordinatesInLY:
			return VectorToJSValue(context, OOGalacticCoordinatesFromInternal([player cursor_coordinates]), value);
			
		case kPlayerShip_targetSystem:
			*value = INT_TO_JSVAL([player targetSystemID]);
			return YES;

		case kPlayerShip_nextSystem:
			*value = INT_TO_JSVAL([player nextHopTargetSystemID]);
			return YES;
			
		case kPlayerShip_infoSystem:
			*value = INT_TO_JSVAL([player infoSystemID]);
			return YES;

		case kPlayerShip_routeMode:
		{
			OORouteType route = [player ANAMode];
			switch (route)
			{
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
			
		case kPlayerShip_scannerNonLinear:
			*value = OOJSValueFromBOOL([[player hud] nonlinearScanner]);
			return YES;
			
		case kPlayerShip_scannerUltraZoom:
			*value = OOJSValueFromBOOL([[player hud] scannerUltraZoom]);
			return YES;
			
		case kPlayerShip_scoopOverride:
			*value = OOJSValueFromBOOL([player scoopOverride]);
			return YES;

		case kPlayerShip_injectorsEngaged:
			*value = OOJSValueFromBOOL([player injectorsEngaged]);
			return YES;
			
		case kPlayerShip_massLockable:
			*value = OOJSValueFromBOOL([player massLockable]);
			return YES;

		case kPlayerShip_torusEngaged:
			*value = OOJSValueFromBOOL([player hyperspeedEngaged]);
			return YES;
			
		case kPlayerShip_compassTarget:
			result = [player compassTarget];
			break;
			
		case kPlayerShip_compassType:
			result = [OOStringFromCompassMode([player compassMode]) isEqualToString:@"COMPASS_MODE_BASIC"] ?
														@"OO_COMPASSTYPE_BASIC" : @"OO_COMPASSTYPE_ADVANCED";
			break;
			
		case kPlayerShip_compassMode:
			*value = OOJSValueFromCompassMode(context, [player compassMode]);
			return YES;
			
		case kPlayerShip_hud:
			result = [[player hud] hudName];
			break;

		case kPlayerShip_crosshairs:
			result = [[player hud] crosshairDefinition];
			break;

		case kPlayerShip_hudAllowsBigGui:
			*value = OOJSValueFromBOOL([[player hud] allowBigGui]);
			return YES;

		case kPlayerShip_hudHidden:
			*value = OOJSValueFromBOOL([[player hud] isHidden]);
			return YES;
			
		case kPlayerShip_weaponsOnline:
			*value = OOJSValueFromBOOL([player weaponsOnline]);
			return YES;
			
		case kPlayerShip_viewDirection:
			*value = OOJSValueFromViewID(context, [UNIVERSE viewDirection]);
			return YES;

		case kPlayerShip_viewPositionAft:
			return VectorToJSValue(context, [player viewpointOffsetAft], value);

		case kPlayerShip_viewPositionForward:
			return VectorToJSValue(context, [player viewpointOffsetForward], value);

		case kPlayerShip_viewPositionPort:
			return VectorToJSValue(context, [player viewpointOffsetPort], value);

		case kPlayerShip_viewPositionStarboard:
			return VectorToJSValue(context, [player viewpointOffsetStarboard], value);

		case kPlayerShip_currentWeapon:
			result = [player weaponTypeForFacing:[player currentWeaponFacing] strict:NO];
			break;
		
	  case kPlayerShip_price:
			return JS_NewNumberValue(context, [UNIVERSE tradeInValueForCommanderDictionary:[player commanderDataDictionary]], value);

	  case kPlayerShip_serviceLevel:
			return JS_NewNumberValue(context, [player tradeInFactor], value);

		case kPlayerShip_renovationCost:
			return JS_NewNumberValue(context, [player renovationCosts], value);

		case kPlayerShip_renovationMultiplier:
			return JS_NewNumberValue(context, [player renovationFactor], value);


			// make roll, pitch, yaw reported to JS use same +/- convention as
			// for NPC ships
		case kPlayerShip_pitch:
			return JS_NewNumberValue(context, -[player flightPitch], value);

		case kPlayerShip_roll:
			return JS_NewNumberValue(context, -[player flightRoll], value);

		case kPlayerShip_yaw:
			return JS_NewNumberValue(context, -[player flightYaw], value);
			
		case kPlayerShip_messageGuiTextColor:
			result = [[[UNIVERSE messageGUI] textColor] normalizedArray];
			break;
			
		case kPlayerShip_messageGuiTextCommsColor:
			result = [[[UNIVERSE messageGUI] textCommsColor] normalizedArray];
			break;
			
		default:
			OOJSReportBadPropertySelector(context, this, propID, sPlayerShipProperties);
	}
	
	*value = OOJSValueFromNativeObject(context, result);
	return YES;
	
	OOJS_NATIVE_EXIT
}


static JSBool PlayerShipSetProperty(JSContext *context, JSObject *this, jsid propID, JSBool strict, jsval *value)
{
	if (!JSID_IS_INT(propID))  return YES;
	
	OOJS_NATIVE_ENTER(context)
	
	if (EXPECT_NOT(OOIsPlayerStale())) return YES;
	
	PlayerEntity				*player = OOPlayerForScripting();
	jsdouble					fValue;
	JSBool						bValue;
	int32						iValue;
	NSString					*sValue = nil;
	OOGalacticHyperspaceBehaviour ghBehaviour;
	Vector						vValue;
	OOColor						*colorForScript = nil;
	
	switch (JSID_TO_INT(propID))
	{
		case kPlayerShip_fuelLeakRate:
			if (JS_ValueToNumber(context, *value, &fValue))
			{
				[player setFuelLeakRate:fValue];
				return YES;
			}
			break;
			
		case kPlayerShip_massLockable:
			if (JS_ValueToBoolean(context, *value, &bValue))
			{
				[player setMassLockable:bValue];
				return YES;
			}
			break;
			
		case kPlayerShip_reticleTargetSensitive:
			if (JS_ValueToBoolean(context, *value, &bValue))
			{
				[[player hud] setReticleTargetSensitive:bValue];
				return YES;
			}
			break;
		
		case kPlayerShip_compassMode:
			sValue = OOStringFromJSValue(context, *value);
			if(sValue != nil)
			{
				OOCompassMode mode = OOCompassModeFromJSValue(context, *value);
				[player setCompassMode:mode];
				[player validateCompassTarget];
				return YES;
			}
			break;
			
		case kPlayerShip_compassType:
			sValue = OOStringFromJSValue(context, *value);
			if (sValue != nil)
			{
				if ([sValue isEqualToString:@"OO_COMPASSTYPE_BASIC"])
				{
					[player setCompassMode:COMPASS_MODE_BASIC];
				}
				else  if([sValue isEqualToString:@"OO_COMPASSTYPE_ADVANCED"])
				{
					if (![player hasEquipmentItemProviding:@"EQ_ADVANCED_COMPASS"])
					{
						OOJSReportWarning(context, @"Advanced Compass type requested and set but player ship does not carry the EQ_ADVANCED_COMPASS equipment or has it damaged.");
					}
					[player setCompassMode:COMPASS_MODE_PLANET];
				}
				else
				{
					OOJSReportError(context, @"Unknown compass type specified - must be either OO_COMPASSTYPE_BASIC or OO_COMPASSTYPE_ADVANCED.");
					return NO;
				}
				return YES;
			}
			break;
			
		case kPlayerShip_galacticHyperspaceBehaviour:
			ghBehaviour = OOGalacticHyperspaceBehaviourFromJSValue(context, *value);
			if (ghBehaviour != GALACTIC_HYPERSPACE_BEHAVIOUR_UNKNOWN)
			{
				[player setGalacticHyperspaceBehaviour:ghBehaviour];
				return YES;
			}
			break;
			
		case kPlayerShip_galacticHyperspaceFixedCoords:
			if (JSValueToVector(context, *value, &vValue))
			{
				NSPoint coords = { vValue.x, vValue.y };
				[player setGalacticHyperspaceFixedCoords:coords];
				return YES;
			}
			break;
			
		case kPlayerShip_galacticHyperspaceFixedCoordsInLY:
			if (JSValueToVector(context, *value, &vValue))
			{
				NSPoint coords = OOInternalCoordinatesFromGalactic(vValue);
				[player setGalacticHyperspaceFixedCoords:coords];
				return YES;
			}
			break;
			
		case kPlayerShip_fastEquipmentA:
			sValue = OOStringFromJSValue(context, *value);
			if (sValue != nil)
			{
				[player setFastEquipmentA:sValue];
				return YES;
			}
			break;

		case kPlayerShip_fastEquipmentB:
			sValue = OOStringFromJSValue(context, *value);
			if (sValue != nil)
			{
				[player setFastEquipmentB:sValue];
				return YES;
			}
			break;

		case kPlayerShip_primedEquipment:
			sValue = OOStringFromJSValue(context, *value);
			if (sValue != nil)
			{
				return [player setPrimedEquipment:sValue showMessage:NO];
			}
			break;

		case kPlayerShip_forwardShield:
			if (JS_ValueToNumber(context, *value, &fValue))
			{
				[player setForwardShieldLevel:fValue];
				return YES;
			}
			break;
			
		case kPlayerShip_aftShield:
			if (JS_ValueToNumber(context, *value, &fValue))
			{
				[player setAftShieldLevel:fValue];
				return YES;
			}
			break;

		case kPlayerShip_maxForwardShield:
			if (JS_ValueToNumber(context, *value, &fValue))
			{
				[player setMaxForwardShieldLevel:fValue];
				return YES;
			}
			break;
			
		case kPlayerShip_maxAftShield:
			if (JS_ValueToNumber(context, *value, &fValue))
			{
				[player setMaxAftShieldLevel:fValue];
				return YES;
			}
			break;

		case kPlayerShip_forwardShieldRechargeRate:
			if (JS_ValueToNumber(context, *value, &fValue))
			{
				[player setForwardShieldRechargeRate:fValue];
				return YES;
			}
			break;
			
		case kPlayerShip_aftShieldRechargeRate:
			if (JS_ValueToNumber(context, *value, &fValue))
			{
				[player setAftShieldRechargeRate:fValue];
				return YES;
			}
			break;
			
		case kPlayerShip_scannerNonLinear:
			if (JS_ValueToBoolean(context, *value, &bValue))
			{
				[[player hud] setNonlinearScanner:bValue];
				return YES;
			}
			break;
			
		case kPlayerShip_scannerUltraZoom:
			if (JS_ValueToBoolean(context, *value, &bValue))
			{
				[[player hud] setScannerUltraZoom:bValue];
				return YES;
			}
			break;
			
		case kPlayerShip_scoopOverride:
			if (JS_ValueToBoolean(context, *value, &bValue))
			{
				[player setScoopOverride:bValue];
				return YES;
			}
			break;
			
		case kPlayerShip_hud:
			sValue = OOStringFromJSValue(context, *value);
			if (sValue != nil)
			{
				[player switchHudTo:sValue];	// EMMSTRAN: logged error should be a JS warning.
				return YES;
			}
			else
			{
				[player resetHud];
				return YES;
			}
			break;
			
		case kPlayerShip_crosshairs:
			sValue = OOStringFromJSValue(context, *value);
			if (sValue == nil)
			{
				// reset HUD back to its plist settings
				NSString *hud = [[[player hud] hudName] retain];
				[player switchHudTo:hud];
				[hud release];
				return YES;
			}
			else
			{
				if (![[player hud] setCrosshairDefinition:sValue])
				{
					OOJSReportWarning(context, @"Crosshair definition file %@ not found or invalid", sValue);
				}
				return YES;
			}
			break;

		case kPlayerShip_hudHidden:
			if (JS_ValueToBoolean(context, *value, &bValue))
			{
				[[player hud] setHidden:bValue];
				return YES;
			}
			break;

	  case kPlayerShip_serviceLevel:
			if (JS_ValueToNumber(context, *value, &fValue))
			{
				int newLevel = (int)fValue;
				[player adjustTradeInFactorBy:(newLevel-[player tradeInFactor])];
				return YES;
			}
			
		case kPlayerShip_currentWeapon:
		{
			BOOL exists = NO;
			sValue = JSValueToEquipmentKeyRelaxed(context, *value, &exists);
			if (!exists || sValue == nil) 
			{
				sValue = @"EQ_WEAPON_NONE";
			}
			[player setWeaponMount:[player currentWeaponFacing] toWeapon:sValue inContext:@"scripted"];
			return YES;
		}
		
		case kPlayerShip_targetSystem:
			/* This first check is essential: if removed, it would be
			 * possible to make jumps of arbitrary length - CIM */
			if ([player status] != STATUS_ENTERING_WITCHSPACE)
			{
				/* These checks though similar are less important. The
				 * consequences of allowing jump destination to be set in
				 * flight are not as severe and do not allow the 7LY limit to
				 * be broken. Nevertheless, it is not allowed. - CIM */
				// (except when compiled in debugging mode)
#ifndef OO_DUMP_PLANETINFO
				if (EXPECT_NOT([player status] != STATUS_DOCKED && [player status] != STATUS_LAUNCHING))
				{
					OOJSReportError(context, @"player.ship.targetSystem is read-only unless called when docked.");
					return NO;
				}
#endif
				
				if (JS_ValueToInt32(context, *value, &iValue))
				{
					if (iValue >= 0 && iValue < OO_SYSTEMS_PER_GALAXY)
					{ 
						[player setTargetSystemID:iValue];
						return YES;
					}
					else
					{
						return NO;
					}
				}
			}
			else
			{
				OOJSReportError(context, @"player.ship.targetSystem is read-only unless called when docked.");
				return NO;
			}
		
		case kPlayerShip_infoSystem:
			if (JS_ValueToInt32(context, *value, &iValue))
			{
				if (iValue >= 0 && iValue < OO_SYSTEMS_PER_GALAXY)
				{ 
					[player setInfoSystemID:iValue moveChart: YES];
					return YES;
				}
				else
				{
					return NO;
				}
			}
			break;
			
		case kPlayerShip_messageGuiTextColor:
			colorForScript = [OOColor colorWithDescription:OOJSNativeObjectFromJSValue(context, *value)];
			if (colorForScript != nil || JSVAL_IS_NULL(*value))
			{
				[[UNIVERSE messageGUI] setTextColor:colorForScript];
				return YES;
			}
			break;
			
		case kPlayerShip_messageGuiTextCommsColor:
			colorForScript = [OOColor colorWithDescription:OOJSNativeObjectFromJSValue(context, *value)];
			if (colorForScript != nil || JSVAL_IS_NULL(*value))
			{
				[[UNIVERSE messageGUI] setTextCommsColor:colorForScript];
				return YES;
			}
			break;
			
		case kPlayerShip_reticleColorTarget:
			colorForScript = [OOColor colorWithDescription:OOJSNativeObjectFromJSValue(context, *value)];
			if (colorForScript != nil || JSVAL_IS_NULL(*value))
			{
				return [[player hud] setReticleColorForIndex:OO_RETICLE_COLOR_TARGET toColor:colorForScript];
			}
			break;
			
		case kPlayerShip_reticleColorTargetSensitive:
			colorForScript = [OOColor colorWithDescription:OOJSNativeObjectFromJSValue(context, *value)];
			if (colorForScript != nil || JSVAL_IS_NULL(*value))
			{
				return [[player hud] setReticleColorForIndex:OO_RETICLE_COLOR_TARGET_SENSITIVE toColor:colorForScript];
			}
			break;
			
		case kPlayerShip_reticleColorWormhole:
			colorForScript = [OOColor colorWithDescription:OOJSNativeObjectFromJSValue(context, *value)];
			if (colorForScript != nil || JSVAL_IS_NULL(*value))
			{
				return [[player hud] setReticleColorForIndex:OO_RETICLE_COLOR_WORMHOLE toColor:colorForScript];
			}
			break;

		default:
			OOJSReportBadPropertySelector(context, this, propID, sPlayerShipProperties);
			return NO;
	}
	
	OOJSReportBadPropertyValue(context, this, propID, sPlayerShipProperties, *value);
	return NO;
	
	OOJS_NATIVE_EXIT
}


// *** Methods ***

// launch()
static JSBool PlayerShipLaunch(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	if (EXPECT_NOT(OOIsPlayerStale()))  OOJS_RETURN_VOID;
	
	[OOPlayerForScripting() launchFromStation];
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// removeAllCargo()
static JSBool PlayerShipRemoveAllCargo(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	if (EXPECT_NOT(OOIsPlayerStale()))  OOJS_RETURN_VOID;
	
	PlayerEntity *player = OOPlayerForScripting();
	
	if ([player isDocked])
	{
		[player removeAllCargo];
		OOJS_RETURN_VOID;
	}
	else
	{
		OOJSReportError(context, @"PlayerShip.removeAllCargo only works when docked.");
		return NO;
	}
	
	OOJS_NATIVE_EXIT
}


// useSpecialCargo(name : String)
static JSBool PlayerShipUseSpecialCargo(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	if (EXPECT_NOT(OOIsPlayerStale()))  OOJS_RETURN_VOID;
	
	PlayerEntity			*player = OOPlayerForScripting();
	NSString				*name = nil;
	
	if (argc > 0)  name = OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (EXPECT_NOT(name == nil))
	{
		OOJSReportBadArguments(context, @"PlayerShip", @"useSpecialCargo", MIN(argc, 1U), OOJS_ARGV, nil, @"string (special cargo description)");
		return NO;
	}
	
	[player useSpecialCargo:OOStringFromJSValue(context, OOJS_ARGV[0])];
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// engageAutopilotToStation(stationForDocking : Station) : Boolean
static JSBool PlayerShipEngageAutopilotToStation(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	if (EXPECT_NOT(OOIsPlayerStale()))  OOJS_RETURN_VOID;
	
	PlayerEntity			*player = OOPlayerForScripting();
	StationEntity			*stationForDocking = nil;
	
	if (argc > 0)  stationForDocking = OOJSNativeObjectOfClassFromJSValue(context, OOJS_ARGV[0], [StationEntity class]);
	if (stationForDocking == nil)
	{
		OOJSReportBadArguments(context, @"PlayerShip", @"engageAutopilot", MIN(argc, 1U), OOJS_ARGV, nil, @"station");
		return NO;
	}
	
	OOJS_RETURN_BOOL([player engageAutopilotToStation:stationForDocking]);
	
	OOJS_NATIVE_EXIT
}


// disengageAutopilot()
static JSBool PlayerShipDisengageAutopilot(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	if (EXPECT_NOT(OOIsPlayerStale()))  OOJS_RETURN_VOID;
	
	[OOPlayerForScripting() disengageAutopilot];
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}

static JSBool PlayerShipRequestDockingClearance(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	if (EXPECT_NOT(OOIsPlayerStale()))  OOJS_RETURN_VOID;

	PlayerEntity			*player = OOPlayerForScripting();
	StationEntity			*stationForDocking = nil;
	
	if (argc > 0)  stationForDocking = OOJSNativeObjectOfClassFromJSValue(context, OOJS_ARGV[0], [StationEntity class]);
	if (stationForDocking == nil)
	{
		OOJSReportBadArguments(context, @"PlayerShip", @"requestDockingClearance", MIN(argc, 1U), OOJS_ARGV, nil, @"station");
		return NO;
	}

	[player requestDockingClearance:stationForDocking];
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}

static JSBool PlayerShipCancelDockingRequest(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	if (EXPECT_NOT(OOIsPlayerStale()))  OOJS_RETURN_VOID;

	PlayerEntity			*player = OOPlayerForScripting();
	StationEntity			*stationForDocking = nil;
	
	if (argc > 0)  stationForDocking = OOJSNativeObjectOfClassFromJSValue(context, OOJS_ARGV[0], [StationEntity class]);
	if (stationForDocking == nil)
	{
		OOJSReportBadArguments(context, @"PlayerShip", @"cancelDockingRequest", MIN(argc, 1U), OOJS_ARGV, nil, @"station");
		return NO;
	}

	[player cancelDockingRequest:stationForDocking];
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}

// awardEquipmentToCurrentPylon(externalTank: equipmentInfoExpression) : Boolean
static JSBool PlayerShipAwardEquipmentToCurrentPylon(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	if (EXPECT_NOT(OOIsPlayerStale()))  OOJS_RETURN_VOID;
	
	PlayerEntity			*player = OOPlayerForScripting();
	NSString				*key = nil;
	OOEquipmentType			*eqType = nil;
	
	if (argc > 0)  key = JSValueToEquipmentKey(context, OOJS_ARGV[0]);
	if (key != nil)  eqType = [OOEquipmentType equipmentTypeWithIdentifier:key];
	if (EXPECT_NOT(![eqType isMissileOrMine]))
	{
		OOJSReportBadArguments(context, @"PlayerShip", @"awardEquipmentToCurrentPylon", MIN(argc, 1U), OOJS_ARGV, nil, @"equipment type (external store)");
		return NO;
	}
	
	OOJS_RETURN_BOOL([player assignToActivePylon:key]);
	
	OOJS_NATIVE_EXIT
}


// addPassenger(name: string, start: int, destination: int, ETA: double, fee: double) : Boolean
static JSBool PlayerShipAddPassenger(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	PlayerEntity		*player = OOPlayerForScripting();
	NSString 			*name = nil;
	OOSystemID			start = 0, destination = 0;
	jsdouble			eta = 0.0, fee = 0.0, advance = 0.0;
	unsigned			risk = 0;

	if (argc < 5)
	{
		OOJSReportBadArguments(context, @"PlayerShip", @"addPassenger", argc, OOJS_ARGV, nil, @"name, start, destination, ETA, fee");
		return NO;
	}
	
	name = OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (EXPECT_NOT(name == nil))
	{
		OOJSReportBadArguments(context, @"PlayerShip", @"addPassenger", 1, &OOJS_ARGV[0], nil, @"string");
		return NO;
	}
	
	if (!ValidateContracts(context, argc, vp, NO, &start, &destination, &eta, &fee, &advance, @"addPassenger", &risk))  return NO; // always go through validate contracts (passenger)
	
	// Ensure there's space.
	if ([player passengerCount] >= [player passengerCapacity])  OOJS_RETURN_BOOL(NO);
	
	BOOL OK = [player addPassenger:name start:start destination:destination eta:eta fee:fee advance:advance risk:risk];
	OOJS_RETURN_BOOL(OK);
	
	OOJS_NATIVE_EXIT
}


// removePassenger(name :string)
static JSBool PlayerShipRemovePassenger(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	PlayerEntity		*player = OOPlayerForScripting();
	NSString			*name = nil;
	BOOL				OK = YES;
	
	if (argc > 0)  name = OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (EXPECT_NOT(name == nil))
	{
		OOJSReportBadArguments(context, @"PlayerShip", @"removePassenger", MIN(argc, 1U), OOJS_ARGV, nil, @"string");
		return NO;
	}
	
	OK = [player passengerCount] > 0 && [name length] > 0;
	if (OK)  OK = [player removePassenger:name];
	
	OOJS_RETURN_BOOL(OK);
	
	OOJS_NATIVE_EXIT
}


// addParcel(description: string, start: int, destination: int, ETA: double, fee: double) : Boolean
static JSBool PlayerShipAddParcel(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	PlayerEntity		*player = OOPlayerForScripting();
	NSString 			*name = nil;
	OOSystemID			start = 0, destination = 0;
	jsdouble			eta = 0.0, fee = 0.0, premium = 0.0;
	unsigned			risk = 0;
	
	if (argc < 5)
	{
		OOJSReportBadArguments(context, @"PlayerShip", @"addParcel", argc, OOJS_ARGV, nil, @"name, start, destination, ETA, fee");
		return NO;
	}
	
	name = OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (EXPECT_NOT(name == nil))
	{
		OOJSReportBadArguments(context, @"PlayerShip", @"addParcel", 1, &OOJS_ARGV[0], nil, @"string");
		return NO;
	}
	
	if (!ValidateContracts(context, argc, vp, NO, &start, &destination, &eta, &fee, &premium, @"addParcel", &risk))  return NO; // always go through validate contracts (passenger/parcel mode)
	
	// Ensure there's space.
	
	BOOL OK = [player addParcel:name start:start destination:destination eta:eta fee:fee premium:premium risk:risk];
	OOJS_RETURN_BOOL(OK);
	
	OOJS_NATIVE_EXIT
}


// removeParcel(description :string)
static JSBool PlayerShipRemoveParcel(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	PlayerEntity		*player = OOPlayerForScripting();
	NSString			*name = nil;
	BOOL				OK = YES;
	
	if (argc > 0)  name = OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (EXPECT_NOT(name == nil))
	{
		OOJSReportBadArguments(context, @"PlayerShip", @"removeParcel", MIN(argc, 1U), OOJS_ARGV, nil, @"string");
		return NO;
	}
	
	OK = [player parcelCount] > 0 && [name length] > 0;
	if (OK)  OK = [player removeParcel:name];
	
	OOJS_RETURN_BOOL(OK);
	
	OOJS_NATIVE_EXIT
}


// awardContract(quantity: int, commodity: string, start: int, destination: int, eta: double, fee: double) : Boolean
static JSBool PlayerShipAwardContract(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	PlayerEntity		*player = OOPlayerForScripting();
	NSString 			*key = nil;
	int32 				qty = 0;
	OOSystemID			start = 0, destination = 0;
	jsdouble			eta = 0.0, fee = 0.0, premium = 0.0;
	
	if (argc < 6)
	{
		OOJSReportBadArguments(context, @"PlayerShip", @"awardContract", argc, OOJS_ARGV, nil, @"quantity, commodity, start, destination, ETA, fee");
		return NO;
	}
	
	if (!JS_ValueToInt32(context, OOJS_ARGV[0], &qty))
	{
		OOJSReportBadArguments(context, @"PlayerShip", @"awardContract", 1, &OOJS_ARGV[0], nil, @"positive integer (cargo quantity)");
		return NO;
	}
	
	key = OOStringFromJSValue(context, OOJS_ARGV[1]);
	if (EXPECT_NOT(key == nil))
	{
		OOJSReportBadArguments(context, @"PlayerShip", @"awardContract", 1, &OOJS_ARGV[1], nil, @"string (commodity identifier)");
		return NO;
	}
	
	if (!ValidateContracts(context, argc, vp, YES, &start, &destination, &eta, &fee, &premium, @"awardContract", NULL))  return NO; // always go through validate contracts (cargo)
	
	BOOL OK = [player awardContract:qty commodity:key start:start destination:destination eta:eta fee:fee premium:premium];
	OOJS_RETURN_BOOL(OK);
	
	OOJS_NATIVE_EXIT
}


// removeContract(commodity: string, destination: int)
static JSBool PlayerShipRemoveContract(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	PlayerEntity		*player = OOPlayerForScripting();
	NSString			*key = nil;
	int32				dest = 0;
	
	if (argc < 2)
	{
		OOJSReportBadArguments(context, @"PlayerShip", @"removeContract", argc, OOJS_ARGV, nil, @"commodity, destination");
		return NO;
	}
	
	key = OOStringFromJSValue(context, OOJS_ARGV[0]);
	
	if (EXPECT_NOT(key == nil))
	{
		OOJSReportBadArguments(context, @"PlayerShip", @"removeContract", 1, &OOJS_ARGV[0], nil, @"string (commodity identifier)");
		return NO;
	}
	
	if (!JS_ValueToInt32(context, OOJS_ARGV[1], &dest) || dest < 0 || dest > 255)
	{
		OOJSReportBadArguments(context, @"PlayerShip", @"removeContract", 1, &OOJS_ARGV[1], nil, @"system ID");
		return NO;
	}
	
	BOOL OK = [player removeContract:key destination:(unsigned)dest];	
	OOJS_RETURN_BOOL(OK);
	
	OOJS_NATIVE_EXIT
}


// setCustomView(position:vector, orientation:quaternion [, weapon:string])
static JSBool PlayerShipSetCustomView(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	PlayerEntity		*player = OOPlayerForScripting();
	
	if (argc < 2)
	{
		OOJSReportBadArguments(context, @"PlayerShip", @"setCustomView", argc, OOJS_ARGV, nil, @"position, orientiation, [weapon]");
		return NO;
	}

// must be in custom view
	if ([UNIVERSE viewDirection] != VIEW_CUSTOM) 
	{
		OOJSReportError(context, @"PlayerShip.setCustomView only works when custom view is active.");
		return NO;
	}

	NSMutableDictionary			*viewData = [NSMutableDictionary dictionaryWithCapacity:3];

	Vector position = kZeroVector;
	BOOL gotpos = JSValueToVector(context, OOJS_ARGV[0], &position);
	if (!gotpos)
	{
		OOJSReportBadArguments(context, @"PlayerShip", @"setCustomView", argc, OOJS_ARGV, nil, @"position, orientiation, [weapon]");
		return NO;
	}
	NSString *positionstr = [[NSString alloc] initWithFormat:@"%f %f %f",position.x,position.y,position.z];   

	Quaternion orientation = kIdentityQuaternion;
	BOOL gotquat = JSValueToQuaternion(context, OOJS_ARGV[1], &orientation);
	if (!gotquat)
	{
		OOJSReportBadArguments(context, @"PlayerShip", @"setCustomView", argc, OOJS_ARGV, nil, @"position, orientiation, [weapon]");
		return NO;
	}
	NSString *orientationstr = [[NSString alloc] initWithFormat:@"%f %f %f %f",orientation.w,orientation.x,orientation.y,orientation.z];

	[viewData setObject:positionstr forKey:@"view_position"];
	[viewData setObject:orientationstr forKey:@"view_orientation"];

	if (argc > 2)
	{
		NSString* facing = OOStringFromJSValue(context,OOJS_ARGV[2]);
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
static JSBool PlayerShipResetCustomView(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	PlayerEntity		*player = OOPlayerForScripting();
	
// must be in custom view
	if ([UNIVERSE viewDirection] != VIEW_CUSTOM) 
	{
		OOJSReportError(context, @"PlayerShip.setCustomView only works when custom view is active.");
		return NO;
	}

	[player resetCustomView];
	[player noteSwitchToView:VIEW_CUSTOM fromView:VIEW_CUSTOM];

	OOJS_RETURN_BOOL(YES);
	OOJS_NATIVE_EXIT
}


// resetScannerZoom()
static JSBool PlayerShipResetScannerZoom(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	PlayerEntity		*player = OOPlayerForScripting();
	
	[player resetScannerZoom];

	OOJS_RETURN_VOID;
	OOJS_NATIVE_EXIT
}


// takeInternalDamage()
static JSBool PlayerShipTakeInternalDamage(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	PlayerEntity		*player = OOPlayerForScripting();
	
	BOOL took = [player takeInternalDamage];

	OOJS_RETURN_BOOL(took);
	OOJS_NATIVE_EXIT
}


// beginHyperspaceCountdown([int: spin_time])
static JSBool PlayerShipBeginHyperspaceCountdown(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	PlayerEntity		*player = OOPlayerForScripting();
	int32                           spin_time;
	int32                           witchspaceSpinUpTime = 0;
	BOOL begun = NO;
	if (argc < 1) 
	{
		witchspaceSpinUpTime = 0;
#ifdef OO_DUMP_PLANETINFO
		// quick intersystem jumps for debugging
		witchspaceSpinUpTime = 1;
#endif
	}
	else
	{
		if (!JS_ValueToInt32(context, OOJS_ARGV[0], &spin_time) || spin_time < 5 || spin_time > 60)
		{
			OOJSReportBadArguments(context, @"PlayerShip", @"beginHyperspaceCountdown", 1, &OOJS_ARGV[0], nil, @"between 5 and 60 seconds");
			return NO;
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
	if ([player hasHyperspaceMotor] && [player status] == STATUS_IN_FLIGHT && [player witchJumpChecklist:false])
	{
		[player beginWitchspaceCountdown:witchspaceSpinUpTime];
		begun = YES;
	}
	OOJS_RETURN_BOOL(begun);
	OOJS_NATIVE_EXIT
}


// cancelHyperspaceCountdown()
static JSBool PlayerShipCancelHyperspaceCountdown(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
       
	PlayerEntity            *player = OOPlayerForScripting();
       
	BOOL cancelled = NO;
	if ([player hasHyperspaceMotor] && [player status] == STATUS_WITCHSPACE_COUNTDOWN)
	{
		[player cancelWitchspaceCountdown];
		[player setJumpType:false];
		cancelled = YES;
	}

	OOJS_RETURN_BOOL(cancelled);
	OOJS_NATIVE_EXIT
		
}


// setMultiFunctionDisplay(index,key)
static JSBool PlayerShipSetMultiFunctionDisplay(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)

	NSString		*key = nil;
	uint32			index = 0;
	PlayerEntity	*player = OOPlayerForScripting();
	BOOL			OK = YES;

	if (argc > 0)  
	{
		if (!JS_ValueToECMAUint32(context,OOJS_ARGV[0],&index))
		{
			OOJSReportBadArguments(context, @"PlayerShip", @"setMultiFunctionDisplay", MIN(argc, 1U), OOJS_ARGV, nil, @"number (index) [, string (key)]");
			return NO;
		}
	}

	if (argc > 1)
	{
		key = OOStringFromJSValue(context, OOJS_ARGV[1]);
	}

	OK = [player setMultiFunctionDisplay:index toKey:key];

	OOJS_RETURN_BOOL(OK);

	OOJS_NATIVE_EXIT
}


// setMultiFunctionText(key,value)
static JSBool PlayerShipSetMultiFunctionText(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)

	NSString				*key = nil;
	NSString				*value = nil;
	PlayerEntity			*player = OOPlayerForScripting();
	JSBool					reflow = NO;

	if (argc > 0)  
	{
		key = OOStringFromJSValue(context, OOJS_ARGV[0]);
	}
	if (key == nil)
	{
		OOJSReportBadArguments(context, @"PlayerShip", @"setMultiFunctionText", MIN(argc, 1U), OOJS_ARGV, nil, @"string (key) [, string (text)]");
		return NO;
	}
	if (argc > 1)
	{
		value = OOStringFromJSValue(context, OOJS_ARGV[1]);
	}
	if (argc > 2 && EXPECT_NOT(!JS_ValueToBoolean(context, OOJS_ARGV[2], &reflow)))
	{
		OOJSReportBadArguments(context, @"setMultiFunctionText", @"reflow", argc, OOJS_ARGV, nil, @"boolean");
		return NO;
	}

	if (!reflow)
	{
		[player setMultiFunctionText:value forKey:key];
	}
	else
	{
		GuiDisplayGen	*gui = [UNIVERSE gui];
		NSString *formatted = [gui reflowTextForMFD:value];
		[player setMultiFunctionText:formatted forKey:key];
	}

	OOJS_RETURN_VOID;

	OOJS_NATIVE_EXIT
}

// setPrimedEquipment(key, [noMessage])
static JSBool PlayerShipSetPrimedEquipment(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)

	NSString				*key = nil;
	PlayerEntity			*player = OOPlayerForScripting();
	JSBool					showMsg = YES;

	if (argc > 0)  
	{
		key = OOStringFromJSValue(context, OOJS_ARGV[0]);
	}
	if (key == nil)
	{
		OOJSReportBadArguments(context, @"PlayerShip", @"setPrimedEquipment", MIN(argc, 1U), OOJS_ARGV, nil, @"string (key)");
		return NO;
	}
	if (argc > 1 && EXPECT_NOT(!JS_ValueToBoolean(context, OOJS_ARGV[1], &showMsg)))
 	{
 		OOJSReportBadArguments(context, @"PlayerShip", @"setPrimedEquipment", MIN(argc, 2U), OOJS_ARGV, nil, @"boolean");
 		return NO;
 	}

	OOJS_RETURN_BOOL([player setPrimedEquipment:key showMessage:showMsg]);

	OOJS_NATIVE_EXIT
}


// setCustomHUDDial(key,value)
static JSBool PlayerShipSetCustomHUDDial(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)

	NSString				*key = nil;
	id						value = nil;
	PlayerEntity			*player = OOPlayerForScripting();

	if (argc > 0)  
	{
		key = OOStringFromJSValue(context, OOJS_ARGV[0]);
	}
	if (key == nil)
	{
		OOJSReportBadArguments(context, @"PlayerShip", @"setCustomHUDDial", MIN(argc, 1U), OOJS_ARGV, nil, @"string (key), value]");
		return NO;
	}
	if (argc > 1)
	{
		value = OOJSNativeObjectFromJSValue(context, OOJS_ARGV[1]);
	}
	else
	{
		value = @"";
	}

	[player setDialCustom:value forKey:key];
	

	OOJS_RETURN_VOID;

	OOJS_NATIVE_EXIT
}


static JSBool PlayerShipHideHUDSelector(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)

	NSString				*key = nil;
	PlayerEntity			*player = OOPlayerForScripting();

	if (argc > 0)  
	{
		key = OOStringFromJSValue(context, OOJS_ARGV[0]);
	}
	if (key == nil)
	{
		OOJSReportBadArguments(context, @"PlayerShip", @"hideHUDSelector", MIN(argc, 1U), OOJS_ARGV, nil, @"string (selector)");
		return NO;
	}
	[[player hud] setHiddenSelector:key hidden:YES];
	
	OOJS_RETURN_VOID;

	OOJS_NATIVE_EXIT
}


static JSBool PlayerShipShowHUDSelector(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)

	NSString				*key = nil;
	PlayerEntity			*player = OOPlayerForScripting();

	if (argc > 0)  
	{
		key = OOStringFromJSValue(context, OOJS_ARGV[0]);
	}
	if (key == nil)
	{
		OOJSReportBadArguments(context, @"PlayerShip", @"hideHUDSelector", MIN(argc, 1U), OOJS_ARGV, nil, @"string (selector)");
		return NO;
	}
	[[player hud] setHiddenSelector:key hidden:NO];
	
	OOJS_RETURN_VOID;

	OOJS_NATIVE_EXIT
}



static BOOL ValidateContracts(JSContext *context, uintN argc, jsval *vp, BOOL isCargo, OOSystemID *start, OOSystemID *destination, double *eta, double *fee, double *premium, NSString *functionName, unsigned *risk)
{
	OOJS_PROFILE_ENTER
	
	NSCParameterAssert(context != NULL && vp != NULL && start != NULL && destination != NULL && eta != NULL && fee != NULL);
	
	unsigned		uValue, offset = isCargo ? 2 : 1;
	jsdouble		fValue;
	int32			iValue;
	
	if (!JS_ValueToInt32(context, OOJS_ARGV[offset + 0], &iValue) || iValue < 0 || iValue > kOOMaximumSystemID)
	{
		OOJSReportBadArguments(context, @"PlayerShip", functionName, 1, &OOJS_ARGV[offset + 0], nil, @"system ID");
		return NO;
	}
	*start = iValue;
	
	if (!JS_ValueToInt32(context, OOJS_ARGV[offset + 1], &iValue) || iValue < 0 || iValue > kOOMaximumSystemID)
	{
		OOJSReportBadArguments(context, @"PlayerShip", functionName, 1, &OOJS_ARGV[offset + 1], nil, @"system ID");
		return NO;
	}
	*destination = iValue;
	
	
	if (!JS_ValueToNumber(context, OOJS_ARGV[offset + 2], &fValue) || !isfinite(fValue) || fValue <= [PLAYER clockTime])
	{
		OOJSReportBadArguments(context, @"PlayerShip", functionName, 1, &OOJS_ARGV[offset + 2], nil, @"number (future time)");
		return NO;
	}
	*eta = fValue;
	
	if (!JS_ValueToNumber(context, OOJS_ARGV[offset + 3], &fValue) || !isfinite(fValue) || fValue < 0.0)
	{
		OOJSReportBadArguments(context, @"PlayerShip", functionName, 1, &OOJS_ARGV[offset + 3], nil, @"number (credits quantity)");
		return NO;
	}
	*fee = fValue;

	if (argc > offset+4 && JS_ValueToNumber(context, OOJS_ARGV[offset + 4], &fValue) && isfinite(fValue) && fValue >= 0.0)
	{
		*premium = fValue;
	}

	if (!isCargo)
	{
		if (argc > offset+5 && JS_ValueToECMAUint32(context, OOJS_ARGV[offset + 5], &uValue) && isfinite((double)uValue))
		{
			*risk = uValue;
		}
	}
	
	return YES;
	
	OOJS_PROFILE_EXIT
}
