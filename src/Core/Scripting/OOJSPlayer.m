/*

OOJSPlayer.h

Oolite
Copyright (C) 2004-2008 Giles C Williams and contributors

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

#import "OOJSPlayer.h"
#import "OOJSEntity.h"
#import "OOJSShip.h"
#import "OOJSVector.h"
#import "OOJavaScriptEngine.h"
#import "EntityOOJavaScriptExtensions.h"

#import "PlayerEntity.h"
#import "PlayerEntityScriptMethods.h"
#import "PlayerEntityLegacyScriptEngine.h"

#import "OOConstToString.h"
#import "OOFunctionAttributes.h"


static JSObject		*sPlayerPrototype;
static JSObject		*sPlayerObject;


static JSBool PlayerGetProperty(JSContext *context, JSObject *this, jsval name, jsval *outValue);
static JSBool PlayerSetProperty(JSContext *context, JSObject *this, jsval name, jsval *value);

static JSBool PlayerAwardEquipment(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool PlayerRemoveEquipment(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool PlayerHasEquipment(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool PlayerEquipmentStatus(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool PlayerSetEquipmentStatus(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool PlayerLaunch(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool PlayerAwardCargo(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool PlayerCanAwardCargo(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool PlayerRemoveAllCargo(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool PlayerUseSpecialCargo(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool PlayerCommsMessage(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool PlayerConsoleMessage(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool PlayerSetGalacticHyperspaceBehaviour(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool PlayerSetGalacticHyperspaceFixedCoords(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);



static JSExtendedClass sPlayerClass =
{
	{
		"Player",
		JSCLASS_HAS_PRIVATE | JSCLASS_IS_EXTENDED,
		
		JS_PropertyStub,		// addProperty
		JS_PropertyStub,		// delProperty
		PlayerGetProperty,		// getProperty
		PlayerSetProperty,		// setProperty
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
	kPlayer_name,				// Player name, string, read-only
	kPlayer_score,				// kill count, integer, read/write
	kPlayer_credits,			// credit balance, float, read/write
	kPlayer_fuelLeakRate,		// fuel leak rate, float, read/write
	kPlayer_alertCondition,		// alert level, integer, read-only
	kPlayer_docked,				// docked, boolean, read-only
	kPlayer_dockedStation,		// docked station, entity, read-only
	kPlayer_dockedStationName,	// name of docked station, string, read-only
	kPlayer_dockedAtMainStation,// whether current docked station is system main station, boolean, read-only
	kPlayer_alertTemperature,	// cabin temperature alert flag, boolean, read-only
	kPlayer_alertMassLocked,	// mass lock alert flag, boolean, read-only
	kPlayer_alertAltitude,		// low altitude alert flag, boolean, read-only
	kPlayer_alertEnergy,		// low energy alert flag, boolean, read-only
	kPlayer_alertHostiles,		// hostiles present alert flag, boolean, read-only
	kPlayer_trumbleCount,		// number of trumbles, integer, read-only
	kPlayer_specialCargo,		// special cargo, string, read-only
	kPlayer_galacticHyperspaceBehaviour,	// can be standard, all systems reachable or fixed coordinates, integer, read-only
	kPlayer_galacticHyperspaceFixedCoords,	// used when fixed coords behaviour is selected, vector, read-only
};


static JSPropertySpec sPlayerProperties[] =
{
	// JS name					ID							flags
	{ "name",					kPlayer_name,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "score",					kPlayer_score,				JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "credits",				kPlayer_credits,			JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "fuelLeakRate",			kPlayer_fuelLeakRate,		JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "alertCondition",			kPlayer_alertCondition,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "docked",					kPlayer_docked,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "dockedStation",			kPlayer_dockedStation,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "alertTemperature",		kPlayer_alertTemperature,	JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "alertMassLocked",		kPlayer_alertMassLocked,	JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "alertAltitude",			kPlayer_alertAltitude,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "alertEnergy",			kPlayer_alertEnergy,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "alertHostiles",			kPlayer_alertHostiles,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "trumbleCount",			kPlayer_trumbleCount,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "specialCargo",			kPlayer_specialCargo,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "galacticHyperspaceBehaviour",	kPlayer_galacticHyperspaceBehaviour,	JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "galacticHyperspaceFixedCoords",	kPlayer_galacticHyperspaceFixedCoords,	JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ 0 }
};


static JSFunctionSpec sPlayerMethods[] =
{
	// JS name					Function					min args
	{ "awardEquipment",			PlayerAwardEquipment,		1 },	// Should be deprecated in favour of equipment object model
	{ "removeEquipment",		PlayerRemoveEquipment,		1 },	// Should be deprecated in favour of equipment object model
	{ "hasEquipment",			PlayerHasEquipment,			1 },
	{ "equipmentStatus",		PlayerEquipmentStatus,		1 },
	{ "setEquipmentStatus",		PlayerSetEquipmentStatus,	2 },
	{ "launch",					PlayerLaunch,				0 },
	{ "awardCargo",				PlayerAwardCargo,			1 },
	{ "canAwardCargo",			PlayerCanAwardCargo,		1 },
	{ "removeAllCargo",			PlayerRemoveAllCargo,		0 },
	{ "useSpecialCargo",		PlayerUseSpecialCargo,		1 },
	{ "commsMessage",			PlayerCommsMessage,			1 },
	{ "consoleMessage",			PlayerConsoleMessage,		1 },
	{ "setGalacticHyperspaceBehaviour",	PlayerSetGalacticHyperspaceBehaviour,	1 },
	{ "setGalacticHyperspaceFixedCoords",	PlayerSetGalacticHyperspaceFixedCoords,	1 },
	{ 0 }
};


void InitOOJSPlayer(JSContext *context, JSObject *global)
{
    sPlayerPrototype = JS_InitClass(context, global, JSShipPrototype(), &sPlayerClass.base, NULL, 0, sPlayerProperties, sPlayerMethods, NULL, NULL);
	JSRegisterObjectConverter(&sPlayerClass.base, JSBasicPrivateObjectConverter);
	
	// Create player object as a property of the global object.
	sPlayerObject = JS_DefineObject(context, global, "player", &sPlayerClass.base, sPlayerPrototype, JSPROP_ENUMERATE | JSPROP_READONLY | JSPROP_PERMANENT);
	JS_SetPrivate(context, sPlayerObject, [[PlayerEntity sharedPlayer] weakRetain]);
	[[PlayerEntity sharedPlayer] setJSSelf:sPlayerObject context:context];
}


BOOL JSPlayerGetPlayerEntity(JSContext *context, JSObject *playerObj, PlayerEntity **outEntity)
{
	BOOL						result;
	Entity						*entity = nil;
	
	if (outEntity != NULL)  *outEntity = nil;
	
	result = JSEntityGetEntity(context, playerObj, &entity);
	if (!result)  return NO;
	
	if (![entity isKindOfClass:[PlayerEntity class]])  return NO;
	
	*outEntity = (PlayerEntity *)entity;
	return YES;
}


JSClass *JSPlayerClass(void)
{
	return &sPlayerClass.base;
}


JSObject *JSPlayerPrototype(void)
{
	return sPlayerPrototype;
}


PlayerEntity *OOPlayerForScripting(void)
{
	PlayerEntity *player = [PlayerEntity sharedPlayer];
	[player setScriptTarget:player];
	
	return player;
}


@implementation PlayerEntity (OOJavaScriptExtensions)

- (NSString *)jsClassName
{
	return @"Player";
}


- (void)setJSSelf:(JSObject *)val context:(JSContext *)context
{
	jsSelf = val;
	JS_AddNamedRoot(context, &jsSelf, "Player jsSelf");
}

@end


static JSBool PlayerGetProperty(JSContext *context, JSObject *this, jsval name, jsval *outValue)
{
	BOOL						OK = NO;
	id							result = nil;
	PlayerEntity				*player = OOPlayerForScripting();
	
	if (!JSVAL_IS_INT(name))  return YES;
	
	switch (JSVAL_TO_INT(name))
	{
		case kPlayer_name:
			result = [player playerName];
			OK = YES;
			break;
			
		case kPlayer_score:
			*outValue = INT_TO_JSVAL([player score]);
			OK = YES;
			break;
			
		case kPlayer_credits:
			OK = JS_NewDoubleValue(context, [player creditBalance], outValue);
			break;
			
		case kPlayer_fuelLeakRate:
			OK = JS_NewDoubleValue(context, [player fuelLeakRate], outValue);
			break;
			
		case kPlayer_alertCondition:
			*outValue = INT_TO_JSVAL([player alertCondition]);
			OK = YES;
			break;
			
		case kPlayer_docked:
			*outValue = BOOLToJSVal([player isDocked]);
			OK = YES;
			break;
			
		case kPlayer_dockedStation:
			result = [player dockedStation];
			if (result == nil)  result = [NSNull null];
			OK = YES;
			break;
			
		case kPlayer_alertTemperature:
			*outValue = BOOLToJSVal([player alertFlags] & ALERT_FLAG_TEMP);
			OK = YES;
			break;
			
		case kPlayer_alertMassLocked:
			*outValue = BOOLToJSVal([player alertFlags] & ALERT_FLAG_MASS_LOCK);
			OK = YES;
			break;
			
		case kPlayer_alertAltitude:
			*outValue = BOOLToJSVal([player alertFlags] & ALERT_FLAG_ALT);
			OK = YES;
			break;
			
		case kPlayer_alertEnergy:
			*outValue = BOOLToJSVal([player alertFlags] & ALERT_FLAG_ENERGY);
			OK = YES;
			break;
			
		case kPlayer_alertHostiles:
			*outValue = BOOLToJSVal([player alertFlags] & ALERT_FLAG_HOSTILES);
			OK = YES;
			break;
			
		case kPlayer_trumbleCount:
			OK = JS_NewNumberValue(context, [player trumbleCount], outValue);
			break;
			
		case kPlayer_specialCargo:
			result = [player specialCargo];
			OK = YES;
			break;
			
		case kPlayer_galacticHyperspaceBehaviour:
			OK = JS_NewNumberValue(context, [player galacticHyperspaceBehaviour], outValue);
			break;
			
		case kPlayer_galacticHyperspaceFixedCoords:
			OK = NSPointToVectorJSValue(context, [player galacticHyperspaceFixedCoords], outValue);
			break;
		
		default:
			OOReportJSBadPropertySelector(context, @"Player", JSVAL_TO_INT(name));
	}
	
	if (OK && result != nil)  *outValue = [result javaScriptValueInContext:context];
	return OK;
}


static JSBool PlayerSetProperty(JSContext *context, JSObject *this, jsval name, jsval *value)
{
	BOOL						OK = NO;
	PlayerEntity				*player = OOPlayerForScripting();
	jsdouble					fValue;
	int32						iValue;
	
	if (!JSVAL_IS_INT(name))  return YES;
	
	switch (JSVAL_TO_INT(name))
	{
		case kPlayer_score:
			if (JS_ValueToInt32(context, *value, &iValue))
			{
				iValue = MAX(iValue, 0);
				[player setScore:iValue];
				OK = YES;
			}
			break;
			
		case kPlayer_credits:
			if (JS_ValueToNumber(context, *value, &fValue))
			{
				[player setCreditBalance:fValue];
				OK = YES;
			}
			break;
		
		case kPlayer_fuelLeakRate:
			if (JS_ValueToNumber(context, *value, &fValue))
			{
				[player setFuelLeakRate:fValue];
				OK = YES;
			}
			break;
		
		default:
			OOReportJSBadPropertySelector(context, @"Player", JSVAL_TO_INT(name));
	}
	
	return OK;
}


// *** Methods ***

// awardEquipment(key : String)
static JSBool PlayerAwardEquipment(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	PlayerEntity				*player = OOPlayerForScripting();
	NSString					*key = nil;
	
	key = JSValToNSString(context, argv[0]);
	if (EXPECT_NOT(key == nil))
	{
		OOReportJSBadArguments(context, @"Player", @"awardEquipment", argc, argv, @"Invalid arguments", @"equipment key");
		return NO;
	}
	
	[player awardEquipment:key];
	return YES;
}


// removeEquipment(key : String)
static JSBool PlayerRemoveEquipment(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	PlayerEntity				*player = OOPlayerForScripting();
	NSString					*key = nil;
	
	key = JSValToNSString(context, argv[0]);
	if (EXPECT_NOT(key == nil))
	{
		OOReportJSBadArguments(context, @"Player", @"removeEquipment", argc, argv, @"Invalid arguments", @"equipment key");
		return NO;
	}
	
	[player removeEquipmentItem:key];
	return YES;
}


// hasEquipment(key : String) : Boolean
static JSBool PlayerHasEquipment(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	PlayerEntity				*player = OOPlayerForScripting();
	NSString					*key = nil;
	
	key = JSValToNSString(context, argv[0]);
	if (EXPECT_NOT(key == nil))
	{
		OOReportJSBadArguments(context, @"Player", @"hasEquipment", argc, argv, @"Invalid arguments", @"equipment key");
		return NO;
	}
	
	*outResult = BOOLToJSVal([player hasEquipmentItem:key]);
	return YES;
}


// setEquipmentStatus(key : String, status : String)
static JSBool PlayerSetEquipmentStatus(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
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
	
	if (EXPECT_NOT(key == nil || status == nil))
	{
		OOReportJSBadArguments(context, @"Player", @"setEquipmentStatus", argc, argv, @"Invalid arguments", @"equipment key and status");
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
			[player addEquipmentItem:damagedKey];
		}
	}
	else
	{
		OOReportJSErrorForCaller(context, @"Player", @"setEquipmentStatus", @"Second parameter for setEquipmentStatus must be either \"EQUIPMENT_OK\" or \"EQUIPMENT_DAMAGED\".");
		return NO;
	}
	
	*outResult = BOOLToJSVal(hasOK || hasDamaged);
	return YES;
}


// equipmentStatus(key : String) : String
static JSBool PlayerEquipmentStatus(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	// values returned: @"EQUIPMENT_OK", @"EQUIPMENT_DAMAGED", @"EQUIPMENT_UNAVAILABLE"
	
	PlayerEntity			*player = OOPlayerForScripting();
	NSString				*key = JSValToNSString(context, argv[0]);
	NSString				*result = @"EQUIPMENT_UNAVAILABLE";
	
	if (EXPECT_NOT(key == nil))
	{
		OOReportJSBadArguments(context, @"Player", @"setEquipmentStatus", argc, argv, @"Invalid arguments", @"equipment key");
		return NO;
	}
	
	if([player hasEquipmentItem:key]) result = @"EQUIPMENT_OK";
	else if([player hasEquipmentItem:[key stringByAppendingString:@"_DAMAGED"]]) result = @"EQUIPMENT_DAMAGED";
	
	*outResult = [result javaScriptValueInContext:context];
	return YES;
}


// launch()
static JSBool PlayerLaunch(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	[OOPlayerForScripting() launchFromStation];
	return YES;
}


// awardCargo(type : String [, quantity : Number])
static JSBool PlayerAwardCargo(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
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
		OOReportJSBadArguments(context, @"Player", @"awardCargo", argc, argv, @"Invalid arguments", @"type and optional quantity");
		return NO;
	}
	
	type = [UNIVERSE commodityForName:typeString];
	if (EXPECT_NOT(type == NSNotFound))
	{
		OOReportJSErrorForCaller(context, @"Player", @"awardCargo", @"Unknown cargo type \"%@\".", typeString);
		return NO;
	}
	
	if (EXPECT_NOT(amount < 0))
	{
		OOReportJSErrorForCaller(context, @"Player", @"awardCargo", @"Cargo quantity (%i) is negative.", amount);
		return NO;
	}
	
	if (EXPECT_NOT(![player canAwardCargoType:type amount:amount]))
	{
		OOReportJSErrorForCaller(context, @"Player", @"awardCargo", @"Cannot award %u units of cargo \"%@\" at this time (use canAwardCargo() to avoid this error).", amount, typeString);
		return NO;
	}
	
	[player awardCargoType:type amount:amount];
	return YES;
}


// canAwardCargo(type : String [, quantity : Number]) : Boolean
static JSBool PlayerCanAwardCargo(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
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
		OOReportJSBadArguments(context, @"Player", @"canAwardCargo", argc, argv, @"Invalid arguments", @"type and optional quantity");
		return NO;
	}
	
	type = [UNIVERSE commodityForName:typeString];
	if (EXPECT_NOT(type == NSNotFound))
	{
		OOReportJSErrorForCaller(context, @"Player", @"canAwardCargo", @"Unknown cargo type \"%@\".", typeString);
		return NO;
	}
	
	if (EXPECT_NOT(amount < 0))
	{
		OOReportJSErrorForCaller(context, @"Player", @"canAwardCargo", @"Cargo quantity (%i) is negative.", amount);
		return NO;
	}
	
	*outResult = BOOLToJSVal([player canAwardCargoType:type amount:amount]);
	return YES;
}


// removeAllCargo()
static JSBool PlayerRemoveAllCargo(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	PlayerEntity			*player = OOPlayerForScripting();
	
	if ([player isDocked])
	{
		[player removeAllCargo];
		return YES;
	}
	else
	{
		OOReportJSError(context, @"Player.removeAllCargo() may only be called when the player is docked.");
		return NO;
	}
}


// useSpecialCargo(name : String)
static JSBool PlayerUseSpecialCargo(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	PlayerEntity			*player = OOPlayerForScripting();
	NSString				*name = nil;
	
	name = JSValToNSString(context, argv[0]);
	if (EXPECT_NOT(name == nil))
	{
		OOReportJSBadArguments(context, @"Player", @"useSpecialCargo", argc, argv, @"Invalid arguments", @"special cargo description");
		return NO;
	}
	
	[player useSpecialCargo:JSValToNSString(context, argv[0])];
	return YES;
}


// commsMessage(message : String [, duration : Number])
static JSBool PlayerCommsMessage(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	NSString				*message = nil;
	double					time = 4.5;
	BOOL					gotTime = YES;
	
	message = JSValToNSString(context, argv[0]);
	if (argc > 1)  gotTime = JS_ValueToNumber(context, argv[1], &time);
	if (EXPECT_NOT(message == nil || !gotTime))
	{
		OOReportJSBadArguments(context, @"Player", @"commsMessage", argc, argv, @"Invalid arguments", @"message and optional duration");
		return NO;
	}
	
	[UNIVERSE addCommsMessage:message forCount:time];
	return YES;
}


// commsMessage(message : String [, duration : Number])
static JSBool PlayerConsoleMessage(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	NSString				*message = nil;
	double					time = 3.0;
	BOOL					gotTime = YES;
	
	message = JSValToNSString(context, argv[0]);
	if (argc > 1)  gotTime = JS_ValueToNumber(context, argv[1], &time);
	if (EXPECT_NOT(message == nil || !gotTime))
	{
		OOReportJSBadArguments(context, @"Player", @"commsMessage", argc, argv, @"Invalid arguments", @"message and optional duration");
		return NO;
	}
	
	[UNIVERSE addMessage:message forCount:time];
	return YES;
}


// setGalacticHyperspaceBehaviour(behaviour : String)
static JSBool PlayerSetGalacticHyperspaceBehaviour(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	PlayerEntity			*player = OOPlayerForScripting();
	NSString				*behavString = nil;
	OOGalacticHyperspaceBehaviour behaviour;
	
	behavString = JSValToNSString(context, argv[0]);
	if (EXPECT_NOT(behavString == nil))
	{
		OOReportJSBadArguments(context, @"Player", @"setGalacticHyperspaceBehaviour", argc, argv, @"Invalid arguments", @"behaviour name");
		return NO;
	}
	
	behaviour = StringToGalacticHyperspaceBehaviour(behavString);
	if (behaviour == GALACTIC_HYPERSPACE_BEHAVIOUR_UNKNOWN)
	{
		OOReportJSErrorForCaller(context, @"Player", @"setGalacticHyperspaceBehaviour", @"Unknown galactic hyperspace behaviour name %@.", behavString);
	}
	
	[player setGalacticHyperspaceBehaviour:behaviour];
	return YES;
}


// setGalacticHyperspaceFixedCoords(v : vectorExpression) or setGalacticHyperspaceFixedCoords(x : Number, y : Number)
static JSBool PlayerSetGalacticHyperspaceFixedCoords(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	PlayerEntity			*player = OOPlayerForScripting();
	double					x, y;
	Vector					v;
	
	if (argc == 2)
	{
		// Expect two integers
		if (EXPECT_NOT(!JS_ValueToNumber(context, argv[0], &x) ||
					   !JS_ValueToNumber(context, argv[1], &y)))
		{
			OOReportJSBadArguments(context, @"Player", @"setGalacticHyperspaceFixedCoords", argc, argv, @"Invalid arguments", @"vector expression or two numbers");
			return NO;
		}
	}
	else
	{
		// Expect vectorExpression
		if (EXPECT_NOT(!VectorFromArgumentList(context, @"Player", @"setGalacticHyperspaceFixedCoords", argc, argv, &v, NULL)))
		{
			OOReportJSBadArguments(context, @"Player", @"setGalacticHyperspaceFixedCoords", argc, argv, @"Invalid arguments", @"vector expression or two numbers");
			return NO;
		}
		x = v.x;
		y = v.y;
	}
	
	x = OOClamp_0_max_d(x, 255);
	y = OOClamp_0_max_d(y, 255);
	
	[player setGalacticHyperspaceFixedCoordsX:x y:y];
	return YES;
}
