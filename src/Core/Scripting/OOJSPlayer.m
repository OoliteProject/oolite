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
#import "PlayerEntityContracts.h"
#import "PlayerEntityScriptMethods.h"
#import "PlayerEntityLegacyScriptEngine.h"

#import "OOConstToString.h"
#import "OOFunctionAttributes.h"


static JSObject		*sPlayerPrototype;
static JSObject		*sPlayerObject;


static JSBool PlayerGetProperty(JSContext *context, JSObject *this, jsval name, jsval *outValue);
static JSBool PlayerSetProperty(JSContext *context, JSObject *this, jsval name, jsval *value);

static JSBool PlayerCommsMessage(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool PlayerConsoleMessage(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool PlayerIncreaseContractReputation(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool PlayerDecreaseContractReputation(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool PlayerIncreasePassengerReputation(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool PlayerDecreasePassengerReputation(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);



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
	kPlayer_name,					// Player name, string, read-only
	kPlayer_score,					// kill count, integer, read/write
	kPlayer_credits,				// credit balance, float, read/write
	kPlayer_alertCondition,			// alert level, integer, read-only
	kPlayer_alertTemperature,		// cabin temperature alert flag, boolean, read-only
	kPlayer_alertMassLocked,		// mass lock alert flag, boolean, read-only
	kPlayer_alertAltitude,			// low altitude alert flag, boolean, read-only
	kPlayer_alertEnergy,			// low energy alert flag, boolean, read-only
	kPlayer_alertHostiles,			// hostiles present alert flag, boolean, read-only
	kPlayer_trumbleCount,			// number of trumbles, integer, read-only
	kPlayer_contractReputation,		// reputation for cargo contracts, integer, read only
	kPlayer_passengerReputation,	// reputation for passenger contracts, integer, read only
	kPlayer_bounty					// bounty, unsigned int, read/write
};


static JSPropertySpec sPlayerProperties[] =
{
	// JS name					ID							flags
	{ "name",					kPlayer_name,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "score",					kPlayer_score,				JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "credits",				kPlayer_credits,			JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "alertCondition",			kPlayer_alertCondition,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "alertTemperature",		kPlayer_alertTemperature,	JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "alertMassLocked",		kPlayer_alertMassLocked,	JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "alertAltitude",			kPlayer_alertAltitude,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "alertEnergy",			kPlayer_alertEnergy,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "alertHostiles",			kPlayer_alertHostiles,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "trumbleCount",			kPlayer_trumbleCount,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "contractReputation",		kPlayer_contractReputation,	JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "passengerReputation",	kPlayer_passengerReputation, JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "bounty",					kPlayer_bounty,				JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ 0 }
};


static JSFunctionSpec sPlayerMethods[] =
{
	// JS name							Function							min args
	{ "commsMessage",					PlayerCommsMessage,					1 },
	{ "consoleMessage",					PlayerConsoleMessage,				1 },
	{ "increaseContractReputation",		PlayerIncreaseContractReputation,	0 },
	{ "decreaseContractReputation",		PlayerDecreaseContractReputation,	0 },
	{ "increasePassengerReputation",	PlayerIncreasePassengerReputation,	0 },
	{ "decreasePassengerReputation",	PlayerDecreasePassengerReputation,	0 },
	{ 0 }
};


void InitOOJSPlayer(JSContext *context, JSObject *global)
{
	sPlayerPrototype = JS_InitClass(context, global, NULL, &sPlayerClass.base, NULL, 0, sPlayerProperties, sPlayerMethods, NULL, NULL);
	JSRegisterObjectConverter(&sPlayerClass.base, JSBasicPrivateObjectConverter);
	
	// Create player object as a property of the global object.
	sPlayerObject = JS_DefineObject(context, global, "player", &sPlayerClass.base, sPlayerPrototype, JSPROP_ENUMERATE | JSPROP_READONLY | JSPROP_PERMANENT);
}


JSClass *JSPlayerClass(void)
{
	return &sPlayerClass.base;
}


JSObject *JSPlayerPrototype(void)
{
	return sPlayerPrototype;
}


JSObject *JSPlayerObject(void)
{
	return sPlayerObject;
}


PlayerEntity *OOPlayerForScripting(void)
{
	PlayerEntity *player = [PlayerEntity sharedPlayer];
	[player setScriptTarget:player];
	
	return player;
}


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
			
		case kPlayer_alertCondition:
			*outValue = INT_TO_JSVAL([player alertCondition]);
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
			
		case kPlayer_contractReputation:
			*outValue = INT_TO_JSVAL([player contractReputation]);
			OK = YES;
			break;
			
		case kPlayer_passengerReputation:
			*outValue = INT_TO_JSVAL([player passengerReputation]);
			OK = YES;
			break;
			
		case kPlayer_bounty:
			*outValue = INT_TO_JSVAL([player legalStatus]);
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
			
		case kPlayer_bounty:
			if (JS_ValueToInt32(context, *value, &iValue))
			{
				if (iValue < 0)  iValue = 0;
				[player setBounty:iValue];
				OK = YES;
			}
			break;
		
		default:
			OOReportJSBadPropertySelector(context, @"Player", JSVAL_TO_INT(name));
	}
	
	return OK;
}


// *** Methods ***

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


// consoleMessage(message : String [, duration : Number])
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


// increaseContractReputation()
static JSBool PlayerIncreaseContractReputation(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	[OOPlayerForScripting() increaseContractReputation];
	return YES;
}


// decreaseContractReputation()
static JSBool PlayerDecreaseContractReputation(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	[OOPlayerForScripting() decreaseContractReputation];
	return YES;
}


// increasePassengerReputation()
static JSBool PlayerIncreasePassengerReputation(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	[OOPlayerForScripting() increasePassengerReputation];
	return YES;
}


// decreasePassengerReputation()
static JSBool PlayerDecreasePassengerReputation(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	[OOPlayerForScripting() decreasePassengerReputation];
	return YES;
}
