/*

OOJSPlayerShip.h

Oolite
Copyright (C) 2004-2009 Giles C Williams and contributors

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

#import "OOConstToString.h"
#import "OOFunctionAttributes.h"


static JSObject		*sPlayerShipPrototype;
static JSObject		*sPlayerShipObject;


static JSBool PlayerShipGetProperty(JSContext *context, JSObject *this, jsval name, jsval *outValue);
static JSBool PlayerShipSetProperty(JSContext *context, JSObject *this, jsval name, jsval *value);

static JSBool PlayerShipAwardEquipment(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool PlayerShipRemoveEquipment(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool PlayerShipEquipmentStatus(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool PlayerShipSetEquipmentStatus(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool PlayerShipLaunch(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool PlayerShipAwardCargo(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool PlayerShipCanAwardCargo(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool PlayerShipRemoveAllCargo(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool PlayerShipUseSpecialCargo(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);



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
	kPlayerShip_fuelLeakRate,					// fuel leak rate, float, read/write
	kPlayerShip_docked,							// docked, boolean, read-only
	kPlayerShip_dockedStation,					// docked station, entity, read-only
	kPlayerShip_specialCargo,					// special cargo, string, read-only
	kPlayerShip_reticleTargetSensitive,			// target box changes color when primary target in crosshairs, boolean, read/write
	kPlayerShip_galacticHyperspaceBehaviour,	// can be standard, all systems reachable or fixed coordinates, integer, read-only
	kPlayerShip_galacticHyperspaceFixedCoords,	// used when fixed coords behaviour is selected, vector, read-only
	kPlayerShip_forwardShield,					// forward shield charge level, nonnegative float, read/write
	kPlayerShip_aftShield,						// aft shield charge level, nonnegative float, read/write
	kPlayerShip_maxForwardShield,				// maximum forward shield charge level, positive float, read-only
	kPlayerShip_maxAftShield,					// maximum aft shield charge level, positive float, read-only
	kPlayerShip_forwardShieldRechargeRate,		// forward shield recharge rate, positive float, read-only
	kPlayerShip_aftShieldRechargeRate,			// aft shield recharge rate, positive float, read-only
	kPlayerShip_galaxyCoordinates,				// galaxy coordinates, vector, read only
	kPlayerShip_cursorCoordinates,				// cursor coordinates, vector, read only
	kPlayerShip_scriptedMisjump,					// next jump will miss if set to true, boolean, read/write
	kPlayerShip_hudHidden					// hud visibility, boolean, read/write
};


static JSPropertySpec sPlayerShipProperties[] =
{
	// JS name						ID									flags
	{ "fuelLeakRate",				kPlayerShip_fuelLeakRate,			JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "docked",						kPlayerShip_docked,					JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "dockedStation",				kPlayerShip_dockedStation,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "specialCargo",				kPlayerShip_specialCargo,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "reticleTargetSensitive",		kPlayerShip_reticleTargetSensitive,	JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "galacticHyperspaceBehaviour",	kPlayerShip_galacticHyperspaceBehaviour,	JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "galacticHyperspaceFixedCoords",	kPlayerShip_galacticHyperspaceFixedCoords,	JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "forwardShield",				kPlayerShip_forwardShield,			JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "aftShield",					kPlayerShip_aftShield,				JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "maxForwardShield",			kPlayerShip_maxForwardShield,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "maxAftShield",				kPlayerShip_maxAftShield,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "forwardShieldRechargeRate",	kPlayerShip_forwardShieldRechargeRate,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "aftShieldRechargeRate",		kPlayerShip_aftShieldRechargeRate,	JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "galaxyCoordinates",			kPlayerShip_galaxyCoordinates,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "cursorCoordinates",			kPlayerShip_cursorCoordinates,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "scriptedMisjump",			kPlayerShip_scriptedMisjump,		JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "hudHidden",				kPlayerShip_hudHidden,			JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ 0 }
};


static JSFunctionSpec sPlayerShipMethods[] =
{
	// JS name						Function							min args
	{ "awardEquipment",				PlayerShipAwardEquipment,			1 },	// Should be deprecated in favour of equipment object model
	{ "removeEquipment",			PlayerShipRemoveEquipment,			1 },	// Should be deprecated in favour of equipment object model
	{ "equipmentStatus",			PlayerShipEquipmentStatus,			1 },
	{ "setEquipmentStatus",			PlayerShipSetEquipmentStatus,		2 },
	{ "launch",						PlayerShipLaunch,					0 },
	{ "awardCargo",					PlayerShipAwardCargo,				1 },
	{ "canAwardCargo",				PlayerShipCanAwardCargo,			1 },
	{ "removeAllCargo",				PlayerShipRemoveAllCargo,			0 },
	{ "useSpecialCargo",			PlayerShipUseSpecialCargo,			1 },
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
	JS_AddNamedRoot(context, &jsSelf, "Player jsSelf");
}

@end


static JSBool PlayerShipGetProperty(JSContext *context, JSObject *this, jsval name, jsval *outValue)
{
	BOOL						OK = NO;
	id							result = nil;
	PlayerEntity				*player = OOPlayerForScripting();
	
	if (!JSVAL_IS_INT(name))  return YES;
	
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
			
		case kPlayerShip_scriptedMisjump:
			*outValue = BOOLToJSVal([player scriptedMisjump]);
			OK = YES;
			break;
			
		case kPlayerShip_hudHidden:
			*outValue = BOOLToJSVal([[player hud] isHidden]);
			OK = YES;
			break;
		
		default:
			OOReportJSBadPropertySelector(context, @"PlayerShip", JSVAL_TO_INT(name));
	}
	
	if (OK && result != nil)  *outValue = [result javaScriptValueInContext:context];
	return OK;
}


static JSBool PlayerShipSetProperty(JSContext *context, JSObject *this, jsval name, jsval *value)
{
	BOOL						OK = NO;
	PlayerEntity				*player = OOPlayerForScripting();
	jsdouble					fValue;
	JSBool						bValue;
	NSString					*sValue = nil;
	OOGalacticHyperspaceBehaviour ghBehaviour;
	Vector						vValue;
	
	if (!JSVAL_IS_INT(name))  return YES;
	
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
			
		case kPlayerShip_hudHidden:
			if (JS_ValueToBoolean(context, *value, &bValue))
			{
				[[player hud] setIsHidden:bValue];
				OK = YES;
			}
			break;
		
		default:
			OOReportJSBadPropertySelector(context, @"PlayerShip", JSVAL_TO_INT(name));
	}
	
	return OK;
}


// *** Methods ***

// awardEquipment(key : String)
static JSBool PlayerShipAwardEquipment(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	PlayerEntity				*player = OOPlayerForScripting();
	NSString					*key = nil;
	BOOL						OK = YES;
	
	key = JSValToNSString(context, argv[0]);
	if (EXPECT_NOT(key == nil))
	{
		OOReportJSBadArguments(context, @"PlayerShip", @"awardEquipment", argc, argv, nil, @"equipment key");
		return NO;
	}
	// berths & missile removal are not in hasEquipmentItem
	OK = ![player hasEquipmentItem:key] || [key isEqualToString:@"EQ_MISSILE_REMOVAL"] ||
			([key isEqualToString:@"EQ_PASSENGER_BERTH"] && [player availableCargoSpace] >= 5);
	
	if (OK)
	{
		if ([key isEqualToString:@"EQ_MISSILE_REMOVAL"]) [player removeMissiles];
		else if ([key isEqualToString:@"EQ_PASSENGER_BERTH"]) [player changePassengerBerths:+1];
		// EQ_CARGO_BAY is already dealt with correctly inside [player awardEquipment]
		else [player awardEquipment:key];
	}
	
	*outResult = BOOLToJSVal(OK);
	return YES;
}


// removeEquipment(key : String)
static JSBool PlayerShipRemoveEquipment(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	PlayerEntity				*player = OOPlayerForScripting();
	NSString					*key = nil;
	BOOL						OK = YES;
	
	key = JSValToNSString(context, argv[0]);
	if (EXPECT_NOT(key == nil))
	{
		OOReportJSBadArguments(context, @"PlayerShip", @"removeEquipment", argc, argv, nil, @"equipment key");
		return NO;
	}
	// berths are not in hasEquipmentItem
	OK = [player hasEquipmentItem:key] || ([key isEqualToString:@"EQ_PASSENGER_BERTH"] && [player passengerCapacity] > 0);
	if (OK)
	{
		//exceptions
		if ([key isEqualToString:@"EQ_PASSENGER_BERTH"] || [key isEqualToString:@"EQ_CARGO_BAY"])
		{
			if ([key isEqualToString:@"EQ_PASSENGER_BERTH"])
			{
				if ([player passengerCapacity] > [player passengerCount])
				{
					[player changePassengerBerths:-1];
				}
				else OK = NO;
			}
			else	// EQ_CARGO_BAY
			{
				if ([player extraCargo] <= [player availableCargoSpace])
				{
					[player removeEquipmentItem:key];
				}
				else OK = NO;
			}
		}
		else
			[player removeEquipmentItem:key];
	}
	
	*outResult = BOOLToJSVal(OK);
	return YES;
}


// setEquipmentStatus(key : String, status : String)
static JSBool PlayerShipSetEquipmentStatus(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	// equipment status accepted: @"EQUIPMENT_OK", @"EQUIPMENT_DAMAGED"
	
	PlayerEntity			*player = OOPlayerForScripting();
	NSString				*key = JSValToNSString(context, argv[0]);
	NSString				*damagedKey = [key stringByAppendingString:@"_DAMAGED"];
	NSString				*status = JSValToNSString(context, argv[1]);
	BOOL					hasOK = NO, hasDamaged = NO;

	if (EXPECT_NOT([UNIVERSE strict]))
	{
		// It's OK to have a hard error here since only built-in scripts run in strict mode.
		OOReportJSError(context, @"Cannot set equipment status while in strict mode.");
		return NO;
	}
	
	if (EXPECT_NOT(key == nil || status == nil || [key hasSuffix:@"_DAMAGED"]))
	{
		OOReportJSBadArguments(context, @"PlayerShip", @"setEquipmentStatus", argc, argv, nil, @"equipment key and status");
		return NO;
	}
	
	hasOK = [player hasEquipmentItem:key];
	hasDamaged = [player hasEquipmentItem:damagedKey];
	
	if ([status isEqualToString:@"EQUIPMENT_OK"])
	{
		if (hasDamaged)
		{
			[player removeEquipmentItem:damagedKey];
			[player addEquipmentItem:key];
		}
	}
	else if ([status isEqualToString:@"EQUIPMENT_DAMAGED"])
	{
		if (hasOK)
		{

			[player removeEquipmentItem:key];
			if ([key isEqual:@"EQ_FUEL"])
			{
				return YES;
			}
			[player addEquipmentItem:damagedKey];
			[player doScriptEvent:@"equipmentDamaged" withArgument:key];
		}
	}
	else
	{
		OOReportJSErrorForCaller(context, @"PlayerShip", @"setEquipmentStatus", @"Second parameter for setEquipmentStatus must be either \"EQUIPMENT_OK\" or \"EQUIPMENT_DAMAGED\".");
		return NO;
	}
	
	*outResult = BOOLToJSVal(hasOK || hasDamaged);
	return YES;
}


// equipmentStatus(key : String) : String
static JSBool PlayerShipEquipmentStatus(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	// values returned: @"EQUIPMENT_OK", @"EQUIPMENT_DAMAGED", @"EQUIPMENT_UNAVAILABLE"
	
	PlayerEntity			*player = OOPlayerForScripting();
	NSString				*key = JSValToNSString(context, argv[0]);
	NSString				*result = @"EQUIPMENT_UNAVAILABLE";
	
	if (EXPECT_NOT(key == nil))
	{
		OOReportJSBadArguments(context, @"PlayerShip", @"setEquipmentStatus", argc, argv, nil, @"equipment key");
		return NO;
	}
	
	if([player hasEquipmentItem:key]) result = @"EQUIPMENT_OK";
	else if([player hasEquipmentItem:[key stringByAppendingString:@"_DAMAGED"]]) result = @"EQUIPMENT_DAMAGED";
	
	*outResult = [result javaScriptValueInContext:context];
	return YES;
}


// launch()
static JSBool PlayerShipLaunch(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	[OOPlayerForScripting() launchFromStation];
	return YES;
}


// awardCargo(type : String [, quantity : Number])
static JSBool PlayerShipAwardCargo(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	PlayerEntity			*player = OOPlayerForScripting();
	NSString				*typeString = nil;
	OOCargoType				type;
	int32					amount = 1;
	BOOL					gotAmount = YES;
	
	typeString = JSValToNSString(context, argv[0]);
	if (argc > 1)  gotAmount = JS_ValueToInt32(context, argv[1], &amount);
	if (EXPECT_NOT(typeString == nil || !gotAmount))
	{
		OOReportJSBadArguments(context, @"PlayerShip", @"awardCargo", argc, argv, nil, @"type and optional quantity");
		return NO;
	}
	
	type = [UNIVERSE commodityForName:typeString];
	if (EXPECT_NOT(type == CARGO_UNDEFINED))
	{
		OOReportJSErrorForCaller(context, @"PlayerShip", @"awardCargo", @"Unknown cargo type \"%@\".", typeString);
		return NO;
	}
	
	if (EXPECT_NOT(amount < 0))
	{
		OOReportJSErrorForCaller(context, @"PlayerShip", @"awardCargo", @"Cargo quantity (%i) is negative.", amount);
		return NO;
	}
	
	if (EXPECT_NOT(![player canAwardCargoType:type amount:amount]))
	{
		OOReportJSErrorForCaller(context, @"PlayerShip", @"awardCargo", @"Cannot award %u units of cargo \"%@\" at this time (use canAwardCargo() to avoid this error).", amount, typeString);
		return NO;
	}
	OOReportJSWarning(context, @"PlayerShip.awardCargo('foo',bar) is deprecated and will be removed in a future version of Oolite. Use Manifest['foo'] = bar; instead.");
	[player awardCargoType:type amount:amount];
	return YES;
}


// canAwardCargo(type : String [, quantity : Number]) : Boolean
static JSBool PlayerShipCanAwardCargo(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	PlayerEntity			*player = OOPlayerForScripting();
	NSString				*typeString = nil;
	OOCargoType				type;
	int32					amount = 1;
	BOOL					gotAmount = YES;
	
	typeString = JSValToNSString(context, argv[0]);
	if (argc > 1)  gotAmount = JS_ValueToInt32(context, argv[1], &amount);
	if (EXPECT_NOT(typeString == nil || !gotAmount))
	{
		OOReportJSBadArguments(context, @"PlayerShip", @"canAwardCargo", argc, argv, nil, @"type and optional quantity");
		return NO;
	}
	
	type = [UNIVERSE commodityForName:typeString];
	if (EXPECT_NOT(type == CARGO_UNDEFINED))
	{
		OOReportJSErrorForCaller(context, @"PlayerShip", @"canAwardCargo", @"Unknown cargo type \"%@\".", typeString);
		return NO;
	}
	
	if (EXPECT_NOT(amount < 0))
	{
		OOReportJSErrorForCaller(context, @"PlayerShip", @"canAwardCargo", @"Cargo quantity (%i) is negative.", amount);
		return NO;
	}
	OOReportJSWarning(context, @"PlayerShip.canAwardCargo() is deprecated and will be removed in a future version of Oolite.");
	*outResult = BOOLToJSVal([player canAwardCargoType:type amount:amount]);
	return YES;
}


// removeAllCargo()
static JSBool PlayerShipRemoveAllCargo(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	PlayerEntity			*player = OOPlayerForScripting();
	
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
}


// useSpecialCargo(name : String)
static JSBool PlayerShipUseSpecialCargo(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	PlayerEntity			*player = OOPlayerForScripting();
	NSString				*name = nil;
	
	name = JSValToNSString(context, argv[0]);
	if (EXPECT_NOT(name == nil))
	{
		OOReportJSBadArguments(context, @"PlayerShip", @"useSpecialCargo", argc, argv, nil, @"special cargo description");
		return NO;
	}
	
	[player useSpecialCargo:JSValToNSString(context, argv[0])];
	return YES;
}
