/*

OOJSPlayer.h

Oolite
Copyright (C) 2004-2007 Giles C Williams and contributors

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
#import "OOJavaScriptEngine.h"
#import "EntityOOJavaScriptExtensions.h"

#import "PlayerEntity.h"
#import "PlayerEntityScriptMethods.h"
#import "PlayerEntityLegacyScriptEngine.h"

#import "OOFunctionAttributes.h"


static JSObject		*sPlayerPrototype;
static JSObject		*sPlayerObject;


static JSBool PlayerGetProperty(JSContext *context, JSObject *this, jsval name, jsval *outValue);
static JSBool PlayerSetProperty(JSContext *context, JSObject *this, jsval name, jsval *value);

static JSBool PlayerAwardEquipment(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool PlayerRemoveEquipment(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool PlayerHasEquipment(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool PlayerLaunch(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool PlayerAwardCargo(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool PlayerRemoveAllCargo(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool PlayerUseSpecialCargo(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);


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
		JSEntityFinalize,		// finalize
		JSCLASS_NO_OPTIONAL_MEMBERS
	},
	JSEntityEquality,			// equality
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
	kPlayer_legalStatus,		// Deprecated synonym for bounty
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
	kPlayer_alertHostiles		// hostiles present alert flag, boolean, read-only
};


static JSPropertySpec sPlayerProperties[] =
{
	// JS name					ID							flags
	{ "name",					kPlayer_name,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "score",					kPlayer_score,				JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "credits",				kPlayer_credits,			JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "legalStatus",			kPlayer_legalStatus,		JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "fuelLeakRate",			kPlayer_fuelLeakRate,		JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "alertCondition",			kPlayer_alertCondition,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "docked",					kPlayer_docked,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "dockedStation",			kPlayer_dockedStation,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "dockedStationName",		kPlayer_dockedStationName,	JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "dockedAtMainStation",	kPlayer_dockedAtMainStation,JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "alertTemperature",		kPlayer_alertTemperature,	JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "alertMassLocked",		kPlayer_alertMassLocked,	JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "alertAltitude",			kPlayer_alertAltitude,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "alertEnergy",			kPlayer_alertEnergy,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "alertHostiles",			kPlayer_alertHostiles,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ 0 }
};


static JSFunctionSpec sPlayerMethods[] =
{
	// JS name					Function					min args
	{ "awardEquipment",			PlayerAwardEquipment,		1 },	// Should be deprecated in favour of equipment object model
	{ "removeEquipment",		PlayerRemoveEquipment,		1 },	// Should be deprecated in favour of equipment object model
	{ "hasEquipment",			PlayerHasEquipment,			1 },
	{ "launch",					PlayerLaunch,				0 },
	{ "awardCargo",				PlayerAwardCargo,			2 },
	{ "removeAllCargo",			PlayerRemoveAllCargo,		0 },
	{ "useSpecialCargo",		PlayerUseSpecialCargo,		1 },
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


PlayerEntity *OPlayerForScripting(void)
{
	PlayerEntity *player = [PlayerEntity sharedPlayer];
	[player setScriptTarget:player];
	
	return player;
}


static JSBool PlayerGetProperty(JSContext *context, JSObject *this, jsval name, jsval *outValue)
{
	id							result = nil;
	PlayerEntity				*player = OPlayerForScripting();
	
	if (!JSVAL_IS_INT(name))  return YES;
	
	switch (JSVAL_TO_INT(name))
	{
		case kPlayer_name:
			result = [player playerName];
			break;
			
		case kPlayer_score:
			*outValue = INT_TO_JSVAL([player score]);
			break;
			
		case kPlayer_credits:
			JS_NewDoubleValue(context, [player creditBalance], outValue);
			break;
			
		case kPlayer_legalStatus:
			OOReportJavaScriptWarning(context, @"Player.%@ is deprecated, use Player.%@ instead.", @"legalStatus", @"bounty");
			*outValue = INT_TO_JSVAL([player legalStatus]);
			break;
			
		case kPlayer_fuelLeakRate:
			JS_NewDoubleValue(context, [player fuelLeakRate], outValue);
			break;
			
		case kPlayer_alertCondition:
			*outValue = INT_TO_JSVAL([player alertCondition]);
			break;
			
		case kPlayer_docked:
			*outValue = BOOLToJSVal([player isDocked]);
			break;
			
		case kPlayer_dockedStation:
			result = [player dockedStation];
			if (result == nil)  result = [NSNull null];
			break;
		
		case kPlayer_dockedStationName:
			OOReportJavaScriptWarning(context, @"Player.%@ is deprecated, use Player.%@ instead.", @"dockedStationName", @"dockedStation.shipDescription");
			result = [player dockedStationName];
			break;
			
		case kPlayer_dockedAtMainStation:
			OOReportJavaScriptWarning(context, @"Player.%@ is deprecated, use Player.%@ instead.", @"dockedAtMainStation", @"dockedStation.isMainStation");
			*outValue = BOOLToJSVal([player dockedAtMainStation]);
			break;
			
		case kPlayer_alertTemperature:
			*outValue = BOOLToJSVal([player alertFlags] & ALERT_FLAG_TEMP);
			break;
			
		case kPlayer_alertMassLocked:
			*outValue = BOOLToJSVal([player alertFlags] & ALERT_FLAG_MASS_LOCK);
			break;
			
		case kPlayer_alertAltitude:
			*outValue = BOOLToJSVal([player alertFlags] & ALERT_FLAG_ALT);
			break;
			
		case kPlayer_alertEnergy:
			*outValue = BOOLToJSVal([player alertFlags] & ALERT_FLAG_ENERGY);
			break;
			
		case kPlayer_alertHostiles:
			*outValue = BOOLToJSVal([player alertFlags] & ALERT_FLAG_HOSTILES);
			break;
		
		default:
			OOReportJavaScriptBadPropertySelector(context, @"Player", JSVAL_TO_INT(name));
			return NO;
	}
	
	if (result != nil)  *outValue = [result javaScriptValueInContext:context];
	return YES;
}


static JSBool PlayerSetProperty(JSContext *context, JSObject *this, jsval name, jsval *value)
{
	PlayerEntity				*player = OPlayerForScripting();
	jsdouble					fValue;
	int32						iValue;
	
	if (!JSVAL_IS_INT(name))  return YES;
	
	switch (JSVAL_TO_INT(name))
	{
		case kPlayer_score:
			if (JS_ValueToInt32(context, *value, &iValue))
			{
				[player setScore:iValue];
			}
			break;
			
		case kPlayer_legalStatus:
			OOReportJavaScriptWarning(context, @"Player.%@ is deprecated, use Player.%@ instead.", @"legalStatus", @"bounty");
			if (JS_ValueToInt32(context, *value, &iValue) && 0 < iValue)
			{
				[player setBounty:iValue];
			}
			break;
			
		case kPlayer_credits:
			if (JS_ValueToNumber(context, *value, &fValue))
			{
				[player setCreditBalance:fValue];
			}
			break;
		
		case kPlayer_fuelLeakRate:
			if (JS_ValueToNumber(context, *value, &fValue))
			{
				[player setFuelLeakRate:fValue];
			}
			break;
		
		default:
			OOReportJavaScriptBadPropertySelector(context, @"Player", JSVAL_TO_INT(name));
			return NO;
	}
	
	return YES;
}


static JSBool PlayerAwardEquipment(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	[OPlayerForScripting() awardEquipment:JSValToNSString(context, argv[0])];
	return YES;
}


static JSBool PlayerRemoveEquipment(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	[OPlayerForScripting() removeEquipment:JSValToNSString(context, argv[0])];
	return YES;
}


static JSBool PlayerHasEquipment(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	*outResult = BOOLToJSVal([OPlayerForScripting() hasExtraEquipment:JSValToNSString(context, argv[0])]);
	return YES;
}


static JSBool PlayerLaunch(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	[OPlayerForScripting() launchFromStation];
	return YES;
}


static JSBool PlayerAwardCargo(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	NSString				*typeString = nil;
	OOCargoType				type;
	int32					amount;
	
	typeString = JSValToNSString(context, argv[0]);
	type = [UNIVERSE commodityForName:typeString];
	if (type == NSNotFound)
	{
		OOReportJavaScriptError(context, @"Unknown cargo type \"%@\".", typeString);
		return YES;
	}
	
	if (!JS_ValueToInt32(context, argv[1], &amount))
	{
		OOReportJavaScriptError(context, @"Expected cargo quantity (integer), got \"%@\".", JSValToNSString(context, argv[1]));
		return YES;
	}
	
	if (amount < 0)
	{
		OOReportJavaScriptError(context, @"Cargo quantity (%i) is negative.", amount);
		return YES;
	}
	
	[OPlayerForScripting() awardCargoType:type amount:amount];
	
	return YES;
}


static JSBool PlayerRemoveAllCargo(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	PlayerEntity			*player = OPlayerForScripting();
	
	if ([player isDocked])
	{
		[player removeAllCargo];
	}
	else
	{
		OOReportJavaScriptError(context, @"Player.removeAllCargo() may only be called when the player is docked.");
	}
	return YES;
}


static JSBool PlayerUseSpecialCargo(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	[OPlayerForScripting() useSpecialCargo:JSValToNSString(context, argv[0])];
	return YES;
}
