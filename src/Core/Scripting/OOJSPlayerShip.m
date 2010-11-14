/*

OOJSPlayerShip.h

Oolite
Copyright (C) 2004-2010 Giles C Williams and contributors

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
#import "OOJavaScriptEngine.h"
#import "EntityOOJavaScriptExtensions.h"

#import "PlayerEntity.h"
#import "PlayerEntityContracts.h"
#import "PlayerEntityScriptMethods.h"
#import "PlayerEntityLegacyScriptEngine.h"
#import "HeadUpDisplay.h"
#import "StationEntity.h"

#import "OOConstToString.h"
#import "OOFunctionAttributes.h"
#import "OOEquipmentType.h"
#import "OOJSEquipmentInfo.h"


// the following line results in NaN when requesting blocked numeric values, instead of undefined, as expected...
// checking for blocked props within each function for now.
// #define OOPlayerShipForScripting() (EXPECT_NOT([UNIVERSE blockJSPlayerShipProps]) ? NULL : OOPlayerForScripting())

#define OOPlayerShipForScripting() ( OOPlayerForScripting())


static JSObject		*sPlayerShipPrototype;
static JSObject		*sPlayerShipObject;


static JSBool PlayerShipGetProperty(JSContext *context, JSObject *this, jsval name, jsval *outValue);
static JSBool PlayerShipSetProperty(JSContext *context, JSObject *this, jsval name, jsval *value);

static JSBool PlayerShipLaunch(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool PlayerShipRemoveAllCargo(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool PlayerShipUseSpecialCargo(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool PlayerShipEngageAutopilotToStation(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool PlayerShipDisengageAutopilot(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool PlayerShipAwardEquipmentToCurrentPylon(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);


static JSExtendedClass sPlayerShipClass =
{
	{
		"PlayerShip",
		JSCLASS_HAS_PRIVATE | JSCLASS_IS_EXTENDED,
		
		JS_PropertyStub,		// addProperty
		JS_PropertyStub,		// delProperty
		PlayerShipGetProperty,	// getProperty
		PlayerShipSetProperty,	// setProperty
		JS_EnumerateStub,		// enumerate
		JS_ResolveStub,			// resolve
		JS_ConvertStub,			// convert
		JSObjectWrapperFinalize,// finalize
		JSCLASS_NO_OPTIONAL_MEMBERS
	},
	JSObjectWrapperEquality,	// equality
	NULL,						// outerObject
	NULL,						// innerObject
	JSCLASS_NO_RESERVED_MEMBERS
};


enum
{
	// Property IDs
	kPlayerShip_aftShield,						// aft shield charge level, nonnegative float, read/write
	kPlayerShip_aftShieldRechargeRate,			// aft shield recharge rate, positive float, read-only
	kPlayerShip_compassMode,					// compass mode, string, read-only
	kPlayerShip_compassTarget,					// object targeted by the compass, entity, read-only
	kPlayerShip_cursorCoordinates,				// cursor coordinates, vector, read only
	kPlayerShip_docked,							// docked, boolean, read-only
	kPlayerShip_dockedStation,					// docked station, entity, read-only
	kPlayerShip_forwardShield,					// forward shield charge level, nonnegative float, read/write
	kPlayerShip_forwardShieldRechargeRate,		// forward shield recharge rate, positive float, read-only
	kPlayerShip_fuelLeakRate,					// fuel leak rate, float, read/write
	kPlayerShip_galacticHyperspaceBehaviour,	// can be standard, all systems reachable or fixed coordinates, integer, read-only
	kPlayerShip_galacticHyperspaceFixedCoords,	// used when fixed coords behaviour is selected, vector, read-only
	kPlayerShip_galaxyCoordinates,				// galaxy coordinates, vector, read only
	kPlayerShip_hud,							// hud name identifier, string, read/write
	kPlayerShip_hudHidden,						// hud visibility, boolean, read/write
	kPlayerShip_maxAftShield,					// maximum aft shield charge level, positive float, read-only
	kPlayerShip_maxForwardShield,				// maximum forward shield charge level, positive float, read-only
	kPlayerShip_reticleTargetSensitive,			// target box changes color when primary target in crosshairs, boolean, read/write
	kPlayerShip_scoopOverride,					// Scooping
	kPlayerShip_scriptedMisjump,				// next jump will miss if set to true, boolean, read/write
	kPlayerShip_specialCargo,					// special cargo, string, read-only
	kPlayerShip_targetSystem,					// target system id, int, read-only
	kPlayerShip_weaponsOnline,					// weapons online status, boolean, read-only
};


static JSPropertySpec sPlayerShipProperties[] =
{
	// JS name						ID									flags
	{ "aftShield",						kPlayerShip_aftShield,						JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "aftShieldRechargeRate",			kPlayerShip_aftShieldRechargeRate,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "compassMode",					kPlayerShip_compassMode,					JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "compassTarget",					kPlayerShip_compassTarget,					JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "cursorCoordinates",				kPlayerShip_cursorCoordinates,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "docked",							kPlayerShip_docked,							JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "dockedStation",					kPlayerShip_dockedStation,					JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "forwardShield",					kPlayerShip_forwardShield,					JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "forwardShieldRechargeRate",		kPlayerShip_forwardShieldRechargeRate,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "fuelLeakRate",					kPlayerShip_fuelLeakRate,					JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "galacticHyperspaceBehaviour",	kPlayerShip_galacticHyperspaceBehaviour,	JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "galacticHyperspaceFixedCoords",	kPlayerShip_galacticHyperspaceFixedCoords,	JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "galaxyCoordinates",				kPlayerShip_galaxyCoordinates,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "hud",							kPlayerShip_hud,							JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "hudHidden",						kPlayerShip_hudHidden,						JSPROP_PERMANENT | JSPROP_ENUMERATE },
	// manifest defined in OOJSManifest.m
	{ "maxAftShield",					kPlayerShip_maxAftShield,					JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "maxForwardShield",				kPlayerShip_maxForwardShield,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "reticleTargetSensitive",			kPlayerShip_reticleTargetSensitive,			JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "scoopOverride",					kPlayerShip_scoopOverride,					JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "scriptedMisjump",				kPlayerShip_scriptedMisjump,				JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "specialCargo",					kPlayerShip_specialCargo,					JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "targetSystem",					kPlayerShip_targetSystem,					JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "weaponsOnline",					kPlayerShip_weaponsOnline,					JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ 0 }			
};


static JSFunctionSpec sPlayerShipMethods[] =
{
	// JS name						Function							min args
	{ "awardEquipmentToCurrentPylon",	PlayerShipAwardEquipmentToCurrentPylon,		1 },
	{ "disengageAutopilot",				PlayerShipDisengageAutopilot,				0 },
	{ "engageAutopilotToStation",		PlayerShipEngageAutopilotToStation,			1 },
	{ "launch",							PlayerShipLaunch,							0 },
	{ "removeAllCargo",					PlayerShipRemoveAllCargo,					0 },
	{ "useSpecialCargo",				PlayerShipUseSpecialCargo,					1 },
	{ 0 }
};


void InitOOJSPlayerShip(JSContext *context, JSObject *global)
{
	sPlayerShipPrototype = JS_InitClass(context, global, JSShipPrototype(), &sPlayerShipClass.base, NULL, 0, sPlayerShipProperties, sPlayerShipMethods, NULL, NULL);
	JSRegisterObjectConverter(&sPlayerShipClass.base, JSBasicPrivateObjectConverter);
	
	// Create ship object as a property of the player object.
	sPlayerShipObject = JS_DefineObject(context, JSPlayerObject(), "ship", &sPlayerShipClass.base, sPlayerShipPrototype, JSPROP_ENUMERATE | JSPROP_READONLY | JSPROP_PERMANENT);
	JS_SetPrivate(context, sPlayerShipObject, [[PlayerEntity sharedPlayer] weakRetain]);
	[[PlayerEntity sharedPlayer] setJSSelf:sPlayerShipObject context:context];
	// Analyzer: object leaked. [Expected, object is retained by JS object.]
}


JSClass *JSPlayerShipClass(void)
{
	return &sPlayerShipClass.base;
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

- (NSString *)jsClassName
{
	return @"PlayerShip";
}


- (void)setJSSelf:(JSObject *)val context:(JSContext *)context
{
	jsSelf = val;
	OO_AddJSGCRoot(context, &jsSelf, "Player jsSelf");
}

@end


static JSBool PlayerShipGetProperty(JSContext *context, JSObject *this, jsval name, jsval *outValue)
{
	OOJS_NATIVE_ENTER(context)
	
	if (EXPECT_NOT([UNIVERSE blockJSPlayerShipProps])) {*outValue = JSVAL_VOID; return YES;}
	if (EXPECT_NOT(!JSVAL_IS_INT(name)))  return YES;
	
	BOOL						OK = NO;
	id							result = nil;
	PlayerEntity				*player = OOPlayerShipForScripting();
	
	switch (JSVAL_TO_INT(name))
	{
		case kPlayerShip_fuelLeakRate:
			OK = JS_NewDoubleValue(context, [player fuelLeakRate], outValue);
			break;
			
		case kPlayerShip_docked:
			*outValue = BOOLToJSVal([player isDocked]);
			OK = YES;
			break;
			
		case kPlayerShip_dockedStation:
			result = [player dockedStation];
			if (result == nil)  result = [NSNull null];
			OK = YES;
			break;
			
		case kPlayerShip_specialCargo:
			result = [player specialCargo];
			OK = YES;
			break;
			
		case kPlayerShip_reticleTargetSensitive:
			*outValue = BOOLToJSVal([[player hud] reticleTargetSensitive]);
			OK = YES;
			break;
			
		case kPlayerShip_galacticHyperspaceBehaviour:
			result = GalacticHyperspaceBehaviourToString([player galacticHyperspaceBehaviour]);
			OK = YES;
			break;
			
		case kPlayerShip_galacticHyperspaceFixedCoords:
			OK = NSPointToVectorJSValue(context, [player galacticHyperspaceFixedCoords], outValue);
			break;
			
		case kPlayerShip_forwardShield:
			OK = JS_NewDoubleValue(context, [player forwardShieldLevel], outValue);
			break;
			
		case kPlayerShip_aftShield:
			OK = JS_NewDoubleValue(context, [player aftShieldLevel], outValue);
			break;
			
		case kPlayerShip_maxForwardShield:
			OK = JS_NewDoubleValue(context, [player maxForwardShieldLevel], outValue);
			break;
			
		case kPlayerShip_maxAftShield:
			OK = JS_NewDoubleValue(context, [player maxAftShieldLevel], outValue);
			break;
			
		case kPlayerShip_forwardShieldRechargeRate:
		case kPlayerShip_aftShieldRechargeRate:
			// No distinction made internally
			OK = JS_NewDoubleValue(context, [player shieldRechargeRate], outValue);
			break;
			
		case kPlayerShip_galaxyCoordinates:
			OK = NSPointToVectorJSValue(context, [player galaxy_coordinates], outValue);
			break;
			
		case kPlayerShip_cursorCoordinates:
			OK = NSPointToVectorJSValue(context, [player cursor_coordinates], outValue);
			break;
			
		case kPlayerShip_targetSystem:
			*outValue = INT_TO_JSVAL([UNIVERSE findSystemNumberAtCoords:[player cursor_coordinates] withGalaxySeed:[player galaxy_seed]]);
			OK = YES;
			break;

		case kPlayerShip_scriptedMisjump:
			*outValue = BOOLToJSVal([player scriptedMisjump]);
			OK = YES;
			break;
			
		case kPlayerShip_scoopOverride:
			*outValue = BOOLToJSVal([player scoopOverride]);
			OK = YES;
			break;
			
		case kPlayerShip_compassTarget:
			result = [player compassTarget];
			OK = YES;
			break;
			
		case kPlayerShip_compassMode:
			result = CompassModeToString([player compassMode]);
			OK = YES;
			break;
			
		case kPlayerShip_hud:
			result = [[player hud] hudName];
			OK = YES;
			break;
			
		case kPlayerShip_hudHidden:
			*outValue = BOOLToJSVal([[player hud] isHidden]);
			OK = YES;
			break;
			
		case kPlayerShip_weaponsOnline:
			*outValue = BOOLToJSVal([player weaponsOnline]);
			OK = YES;
			break;
		
		default:
			OOReportJSBadPropertySelector(context, @"PlayerShip", JSVAL_TO_INT(name));
	}
	
	if (OK && result != nil)  *outValue = [result javaScriptValueInContext:context];
	return OK;
	
	OOJS_NATIVE_EXIT
}


static JSBool PlayerShipSetProperty(JSContext *context, JSObject *this, jsval name, jsval *value)
{
	OOJS_NATIVE_ENTER(context)
	
	if (EXPECT_NOT([UNIVERSE blockJSPlayerShipProps])) return YES;
	if (EXPECT_NOT(!JSVAL_IS_INT(name)))  return YES;
	
	BOOL						OK = NO;
	PlayerEntity				*player = OOPlayerShipForScripting();
	jsdouble					fValue;
	JSBool						bValue;
	NSString					*sValue = nil;
	OOGalacticHyperspaceBehaviour ghBehaviour;
	Vector						vValue;
	
	switch (JSVAL_TO_INT(name))
	{
		case kPlayerShip_fuelLeakRate:
			if (JS_ValueToNumber(context, *value, &fValue))
			{
				[player setFuelLeakRate:fValue];
				OK = YES;
			}
			break;
			
		case kPlayerShip_reticleTargetSensitive:
			if (JS_ValueToBoolean(context, *value, &bValue))
			{
				[[player hud] setReticleTargetSensitive:bValue];
				OK = YES;
			}
			break;
			
		case kPlayerShip_galacticHyperspaceBehaviour:
			sValue = JSValToNSString(context,*value);
			if (sValue != nil)
			{
				ghBehaviour = StringToGalacticHyperspaceBehaviour(sValue);
				if (ghBehaviour != GALACTIC_HYPERSPACE_BEHAVIOUR_UNKNOWN)
				{
					[player setGalacticHyperspaceBehaviour:ghBehaviour];
				}
				OK = YES;
			}
			break;
			
		case kPlayerShip_galacticHyperspaceFixedCoords:
			if (JSValueToVector(context, *value, &vValue))
			{
				[player setGalacticHyperspaceFixedCoordsX:OOClamp_0_max_f(vValue.x, 255.0f) y:OOClamp_0_max_f(vValue.y, 255.0f)];
				OK = YES;
			}
			break;
			
		case kPlayerShip_forwardShield:
			if (JS_ValueToNumber(context, *value, &fValue))
			{
				[player setForwardShieldLevel:fValue];
				OK = YES;
			}
			break;
			
		case kPlayerShip_aftShield:
			if (JS_ValueToNumber(context, *value, &fValue))
			{
				[player setAftShieldLevel:fValue];
				OK = YES;
			}
			break;
			
		case kPlayerShip_scriptedMisjump:
			if (JS_ValueToBoolean(context, *value, &bValue))
			{
				[player setScriptedMisjump:bValue];
				OK = YES;
			}
			break;
		case kPlayerShip_scoopOverride:
			if (JS_ValueToBoolean(context, *value, &bValue))
			{
				[player setScoopOverride:bValue];
				OK = YES;
			}
			break;
			
		case kPlayerShip_hud:
			sValue = JSValToNSString(context, *value);
			if (sValue != nil)
			{
				if ([player switchHudTo:sValue])
				{
					OK = YES;
				}
				else
				{
					OOReportJSError(context, @"%@hud could not be changed to %@",@"PlayerShip.", sValue);
					OK = NO;
				}
			}
			else
			{
				[player resetHud];
				OK = YES;
			}
			break;
			
		case kPlayerShip_hudHidden:
			if (JS_ValueToBoolean(context, *value, &bValue))
			{
				[[player hud] setHidden:bValue];
				OK = YES;
			}
			break;
		
		default:
			OOReportJSBadPropertySelector(context, @"PlayerShip", JSVAL_TO_INT(name));
	}
	
	return OK;
	
	OOJS_NATIVE_EXIT
}


// *** Methods ***

// launch()
static JSBool PlayerShipLaunch(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	OOJS_NATIVE_ENTER(context)
	
	if (EXPECT_NOT([UNIVERSE blockJSPlayerShipProps])) return YES;
	
	[OOPlayerShipForScripting() launchFromStation];
	return YES;
	
	OOJS_NATIVE_EXIT
}


// removeAllCargo()
static JSBool PlayerShipRemoveAllCargo(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	OOJS_NATIVE_ENTER(context)
	
	if (EXPECT_NOT([UNIVERSE blockJSPlayerShipProps])) return YES;
	
	PlayerEntity *player = OOPlayerShipForScripting();
	
	if ([player isDocked])
	{
		[player removeAllCargo];
		return YES;
	}
	else
	{
		OOReportJSError(context, @"%@removeAllCargo only works when docked.",@"PlayerShip.");
		return NO;
	}
	
	OOJS_NATIVE_EXIT
}


// useSpecialCargo(name : String)
static JSBool PlayerShipUseSpecialCargo(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	OOJS_NATIVE_ENTER(context)
	
	if (EXPECT_NOT([UNIVERSE blockJSPlayerShipProps])) return YES;
	
	PlayerEntity			*player = OOPlayerShipForScripting();
	NSString				*name = nil;
	
	name = JSValToNSString(context, argv[0]);
	if (EXPECT_NOT(name == nil))
	{
		OOReportJSBadArguments(context, @"PlayerShip", @"useSpecialCargo", argc, argv, nil, @"special cargo description");
		return NO;
	}
	
	[player useSpecialCargo:JSValToNSString(context, argv[0])];
	return YES;
	
	OOJS_NATIVE_EXIT
}


// engageAutopilotToStation(stationForDocking : Station) : Boolean
static JSBool PlayerShipEngageAutopilotToStation(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	OOJS_NATIVE_ENTER(context)
	
	if (EXPECT_NOT([UNIVERSE blockJSPlayerShipProps])) return YES;
	
	PlayerEntity			*player = OOPlayerShipForScripting();
	StationEntity			*stationForDocking = nil;
	
	stationForDocking = JSValueToObjectOfClass(context, argv[0], [StationEntity class]);
	if (stationForDocking == nil)
	{
		OOReportJSBadArguments(context, @"PlayerShip", @"engageAutopilot", argc, argv, nil, @"station for docking");
		return NO;
	}
	
	*outResult = BOOLToJSVal([player engageAutopilotToStation:stationForDocking]);
	
	return YES;
	
	OOJS_NATIVE_EXIT
}


// disengageAutopilot()
static JSBool PlayerShipDisengageAutopilot(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	OOJS_NATIVE_ENTER(context)
	
	if (EXPECT_NOT([UNIVERSE blockJSPlayerShipProps])) return YES;
	
	PlayerEntity			*player = OOPlayerShipForScripting();
	
	[player disengageAutopilot];
	return YES;
	
	OOJS_NATIVE_EXIT
}


// awardEquipmentToCurrentPylon(externalTank: equipmentInfoExpression) : Boolean
static JSBool PlayerShipAwardEquipmentToCurrentPylon(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	OOJS_NATIVE_ENTER(context)
	
	if (EXPECT_NOT([UNIVERSE blockJSPlayerShipProps])) return YES;
	
	PlayerEntity			*player = OOPlayerShipForScripting();
	NSString				*key = nil;
	OOEquipmentType			*eqType = nil;
	
	key = JSValueToEquipmentKey(context, argv[0]);
	if (EXPECT_NOT(key == nil))
	{
		OOReportJSBadArguments(context, @"PlayerShip", @"awardEquipmentToCurrentPylon", argc, argv, nil, @"equipment type");
		return NO;
	}
	
	eqType = [OOEquipmentType equipmentTypeWithIdentifier:key];
	if (EXPECT_NOT(![eqType isMissileOrMine]))
	{
		OOReportJSBadArguments(context, @"PlayerShip", @"awardEquipmentToCurrentPylon", argc, argv, nil, @"external store");
		return NO;
	}
	
	*outResult = BOOLToJSVal([player assignToActivePylon:key]);
	
	return YES;
	
	OOJS_NATIVE_EXIT
}
