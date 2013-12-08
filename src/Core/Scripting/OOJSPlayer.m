/*

OOJSPlayer.h

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
#import "OOCollectionExtractors.h"
#import "OOStringParsing.h"


static JSObject		*sPlayerPrototype;
static JSObject		*sPlayerObject;


static JSBool PlayerGetProperty(JSContext *context, JSObject *this, jsid propID, jsval *value);
static JSBool PlayerSetProperty(JSContext *context, JSObject *this, jsid propID, JSBool strict, jsval *value);

static JSBool PlayerCommsMessage(JSContext *context, uintN argc, jsval *vp);
static JSBool PlayerConsoleMessage(JSContext *context, uintN argc, jsval *vp);
static JSBool PlayerEndScenario(JSContext *context, uintN argc, jsval *vp);
static JSBool PlayerIncreaseContractReputation(JSContext *context, uintN argc, jsval *vp);
static JSBool PlayerDecreaseContractReputation(JSContext *context, uintN argc, jsval *vp);
static JSBool PlayerIncreasePassengerReputation(JSContext *context, uintN argc, jsval *vp);
static JSBool PlayerDecreasePassengerReputation(JSContext *context, uintN argc, jsval *vp);
static JSBool PlayerIncreaseParcelReputation(JSContext *context, uintN argc, jsval *vp);
static JSBool PlayerDecreaseParcelReputation(JSContext *context, uintN argc, jsval *vp);
static JSBool PlayerAddMessageToArrivalReport(JSContext *context, uintN argc, jsval *vp);
static JSBool PlayerReplaceShip(JSContext *context, uintN argc, jsval *vp);
static JSBool PlayerSetEscapePodDestination(JSContext *context, uintN argc, jsval *vp);
static JSBool PlayerSetPlayerRole(JSContext *context, uintN argc, jsval *vp);


static JSClass sPlayerClass =
{
	"Player",
	JSCLASS_HAS_PRIVATE,
	
	JS_PropertyStub,		// addProperty
	JS_PropertyStub,		// delProperty
	PlayerGetProperty,		// getProperty
	PlayerSetProperty,		// setProperty
	JS_EnumerateStub,		// enumerate
	JS_ResolveStub,			// resolve
	JS_ConvertStub,			// convert
	OOJSObjectWrapperFinalize,// finalize
	JSCLASS_NO_OPTIONAL_MEMBERS
};


enum
{
	// Property IDs
	kPlayer_alertAltitude,			// low altitude alert flag, boolean, read-only
	kPlayer_alertCondition,			// alert level, integer, read-only
	kPlayer_alertEnergy,			// low energy alert flag, boolean, read-only
	kPlayer_alertHostiles,			// hostiles present alert flag, boolean, read-only
	kPlayer_alertMassLocked,		// mass lock alert flag, boolean, read-only
	kPlayer_alertTemperature,		// cabin temperature alert flag, boolean, read-only
	kPlayer_bounty,					// bounty, unsigned int, read/write
	kPlayer_contractReputation,		// reputation for cargo contracts, integer, read only
	kPlayer_contractReputationPrecise,	// reputation for cargo contracts, float, read only
	kPlayer_credits,				// credit balance, float, read/write
	kPlayer_dockingClearanceStatus,	// docking clearance status, string, read only
	kPlayer_legalStatus,			// legalStatus, string, read-only
	kPlayer_name,					// Player name, string, read/write
	kPlayer_parcelReputation,	// reputation for parcel contracts, integer, read-only
	kPlayer_parcelReputationPrecise,	// reputation for parcel contracts, float, read-only
	kPlayer_passengerReputation,	// reputation for passenger contracts, integer, read-only
	kPlayer_passengerReputationPrecise,	// reputation for passenger contracts, float, read-only
	kPlayer_rank,					// rank, string, read-only
	kPlayer_roleWeights,			// role weights, array, read-only
	kPlayer_score,					// kill count, integer, read/write
	kPlayer_trumbleCount,			// number of trumbles, integer, read-only
};


static JSPropertySpec sPlayerProperties[] =
{
	// JS name					ID							flags
	{ "alertAltitude",			kPlayer_alertAltitude,		OOJS_PROP_READONLY_CB },
	{ "alertCondition",			kPlayer_alertCondition,		OOJS_PROP_READONLY_CB },
	{ "alertEnergy",			kPlayer_alertEnergy,		OOJS_PROP_READONLY_CB },
	{ "alertHostiles",			kPlayer_alertHostiles,		OOJS_PROP_READONLY_CB },
	{ "alertMassLocked",		kPlayer_alertMassLocked,	OOJS_PROP_READONLY_CB },
	{ "alertTemperature",		kPlayer_alertTemperature,	OOJS_PROP_READONLY_CB },
	{ "bounty",					kPlayer_bounty,				OOJS_PROP_READWRITE_CB },
	{ "contractReputation",		kPlayer_contractReputation,	OOJS_PROP_READONLY_CB },
	{ "contractReputationPrecise",		kPlayer_contractReputationPrecise,	OOJS_PROP_READONLY_CB },
	{ "credits",				kPlayer_credits,			OOJS_PROP_READWRITE_CB },
	{ "dockingClearanceStatus",	kPlayer_dockingClearanceStatus,	OOJS_PROP_READONLY_CB },
	{ "legalStatus",			kPlayer_legalStatus,		OOJS_PROP_READONLY_CB },
	{ "name",					kPlayer_name,				OOJS_PROP_READWRITE_CB },
	{ "parcelReputation",		kPlayer_parcelReputation,	OOJS_PROP_READONLY_CB },
	{ "parcelReputationPrecise",	kPlayer_parcelReputationPrecise,	OOJS_PROP_READONLY_CB },
	{ "passengerReputation",	kPlayer_passengerReputation,	OOJS_PROP_READONLY_CB },
	{ "passengerReputationPrecise",	kPlayer_passengerReputationPrecise,	OOJS_PROP_READONLY_CB },
	{ "rank",					kPlayer_rank,				OOJS_PROP_READONLY_CB },
	{ "roleWeights",			kPlayer_roleWeights,		OOJS_PROP_READONLY_CB },
	{ "score",					kPlayer_score,				OOJS_PROP_READWRITE_CB },
	{ "trumbleCount",			kPlayer_trumbleCount,		OOJS_PROP_READONLY_CB },
	{ 0 }
};


static JSFunctionSpec sPlayerMethods[] =
{
	// JS name							Function							min args
	{ "addMessageToArrivalReport",		PlayerAddMessageToArrivalReport,	1 },
	{ "commsMessage",					PlayerCommsMessage,					1 },
	{ "consoleMessage",					PlayerConsoleMessage,				1 },
	{ "decreaseContractReputation",		PlayerDecreaseContractReputation,	0 },
	{ "decreaseParcelReputation",	    PlayerDecreaseParcelReputation,		0 },
	{ "decreasePassengerReputation",	PlayerDecreasePassengerReputation,	0 },
	{ "endScenario",					PlayerEndScenario,					1 },
	{ "increaseContractReputation",		PlayerIncreaseContractReputation,	0 },
	{ "increaseParcelReputation",	    PlayerIncreaseParcelReputation,		0 },
	{ "increasePassengerReputation",	PlayerIncreasePassengerReputation,	0 },
	{ "replaceShip",					PlayerReplaceShip,					1 },
	{ "setEscapePodDestination",		PlayerSetEscapePodDestination,		1 },	// null destination must be set explicitly
	{ "setPlayerRole",					PlayerSetPlayerRole,				1 },
	{ 0 }
};


void InitOOJSPlayer(JSContext *context, JSObject *global)
{
	sPlayerPrototype = JS_InitClass(context, global, NULL, &sPlayerClass, OOJSUnconstructableConstruct, 0, sPlayerProperties, sPlayerMethods, NULL, NULL);
	OOJSRegisterObjectConverter(&sPlayerClass, OOJSBasicPrivateObjectConverter);
	
	// Create player object as a property of the global object.
	sPlayerObject = JS_DefineObject(context, global, "player", &sPlayerClass, sPlayerPrototype, OOJS_PROP_READONLY);
}


JSClass *JSPlayerClass(void)
{
	return &sPlayerClass;
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
	PlayerEntity *player = PLAYER;
	[player setScriptTarget:player];
	
	return player;
}


static JSBool PlayerGetProperty(JSContext *context, JSObject *this, jsid propID, jsval *value)
{
	if (!JSID_IS_INT(propID))  return YES;
	
	OOJS_NATIVE_ENTER(context)
	
	id							result = nil;
	PlayerEntity				*player = OOPlayerForScripting();
	
	switch (JSID_TO_INT(propID))
	{
		case kPlayer_name:
			result = [player commanderName];
			break;
			
		case kPlayer_score:
			*value = INT_TO_JSVAL([player score]);
			return YES;
			
		case kPlayer_credits:
			return JS_NewNumberValue(context, [player creditBalance], value);
			
		case kPlayer_rank:
			*value = OOJSValueFromNativeObject(context, OODisplayRatingStringFromKillCount([player score]));
			return YES;
			
		case kPlayer_legalStatus:
			*value = OOJSValueFromNativeObject(context, OODisplayStringFromLegalStatus([player legalStatus]));
			return YES;
			
		case kPlayer_alertCondition:
			*value = INT_TO_JSVAL([player alertCondition]);
			return YES;
			
		case kPlayer_alertTemperature:
			*value = OOJSValueFromBOOL([player alertFlags] & ALERT_FLAG_TEMP);
			return YES;
			
		case kPlayer_alertMassLocked:
			*value = OOJSValueFromBOOL([player alertFlags] & ALERT_FLAG_MASS_LOCK);
			return YES;
			
		case kPlayer_alertAltitude:
			*value = OOJSValueFromBOOL([player alertFlags] & ALERT_FLAG_ALT);
			return YES;
			
		case kPlayer_alertEnergy:
			*value = OOJSValueFromBOOL([player alertFlags] & ALERT_FLAG_ENERGY);
			return YES;
			
		case kPlayer_alertHostiles:
			*value = OOJSValueFromBOOL([player alertFlags] & ALERT_FLAG_HOSTILES);
			return YES;
			
		case kPlayer_trumbleCount:
			return JS_NewNumberValue(context, [player trumbleCount], value);
			
			/* For compatibility with previous versions, these are still on
			 * a -7 to +7 scale */
		case kPlayer_contractReputation:
			return JS_NewNumberValue(context, (int)(((float)[player contractReputation])/10.0), value);
			
		case kPlayer_passengerReputation:
			return JS_NewNumberValue(context, (int)(((float)[player passengerReputation])/10.0), value);

		case kPlayer_parcelReputation:
			return JS_NewNumberValue(context, (int)(((float)[player parcelReputation])/10.0), value);

			/* Full-precision reputations */
		case kPlayer_contractReputationPrecise:
			return JS_NewNumberValue(context, ((float)[player contractReputation])/10.0, value);
			
		case kPlayer_passengerReputationPrecise:
			return JS_NewNumberValue(context, ((float)[player passengerReputation])/10.0, value);

		case kPlayer_parcelReputationPrecise:
			return JS_NewNumberValue(context, ((float)[player parcelReputation])/10.0, value);
			
		case kPlayer_dockingClearanceStatus:
			// EMMSTRAN: OOConstToJSString-ify this.
			*value = OOJSValueFromNativeObject(context, DockingClearanceStatusToString([player getDockingClearanceStatus]));
			return YES;
			
		case kPlayer_bounty:
			*value = INT_TO_JSVAL([player legalStatus]);
			return YES;

		case kPlayer_roleWeights:
			result = [player roleWeights];
			break;
		
		default:
			OOJSReportBadPropertySelector(context, this, propID, sPlayerProperties);
			return NO;
	}
	
	*value = OOJSValueFromNativeObject(context, result);
	return YES;
	
	OOJS_NATIVE_EXIT
}


static JSBool PlayerSetProperty(JSContext *context, JSObject *this, jsid propID, JSBool strict, jsval *value)
{
	if (!JSID_IS_INT(propID))  return YES;
	
	OOJS_NATIVE_ENTER(context)
	
	PlayerEntity				*player = OOPlayerForScripting();
	jsdouble					fValue;
	int32						iValue;
	NSString					*sValue;
	
	switch (JSID_TO_INT(propID))
	{
		case kPlayer_name:
			sValue = OOStringFromJSValue(context,*value);
			if (sValue != nil)
			{
				[player setCommanderName:sValue];
				return YES;
			}
			break;

		case kPlayer_score:
			if (JS_ValueToInt32(context, *value, &iValue))
			{
				iValue = MAX(iValue, 0);
				[player setScore:iValue];
				return YES;
			}
			break;
			
		case kPlayer_credits:
			if (JS_ValueToNumber(context, *value, &fValue))
			{
				[player setCreditBalance:fValue];
				return YES;
			}
			break;
			
		case kPlayer_bounty:
			if (JS_ValueToInt32(context, *value, &iValue))
			{
				if (iValue < 0)  iValue = 0;
				[player setBounty:iValue withReason:kOOLegalStatusReasonByScript];
				return YES;
			}
			break;
		
		default:
			OOJSReportBadPropertySelector(context, this, propID, sPlayerProperties);
			return NO;
	}
	
	OOJSReportBadPropertyValue(context, this, propID, sPlayerProperties, *value);
	return NO;
	
	OOJS_NATIVE_EXIT
}


// *** Methods ***

// commsMessage(message : String [, duration : Number])
static JSBool PlayerCommsMessage(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	NSString				*message = nil;
	double					time = 4.5;
	BOOL					gotTime = YES;
	
	if (argc > 0)  message = OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (argc > 1)  gotTime = JS_ValueToNumber(context, OOJS_ARGV[1], &time);
	if (message == nil || !gotTime)
	{
		OOJSReportBadArguments(context, @"Player", @"commsMessage", argc, OOJS_ARGV, nil, @"message and optional duration");
		return NO;
	}
	
	[UNIVERSE addCommsMessage:message forCount:time];
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// consoleMessage(message : String [, duration : Number])
static JSBool PlayerConsoleMessage(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	NSString				*message = nil;
	double					time = 3.0;
	BOOL					gotTime = YES;
	
	if (argc > 0)  message = OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (argc > 1)  gotTime = JS_ValueToNumber(context, OOJS_ARGV[1], &time);
	if (message == nil || !gotTime)
	{
		OOJSReportBadArguments(context, @"Player", @"consoleMessage", argc, OOJS_ARGV, nil, @"message and optional duration");
		return NO;
	}
	
	[UNIVERSE addMessage:message forCount:time];
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// endScenario(scenario : String)
static JSBool PlayerEndScenario(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	NSString				*scenario = nil;
	
	if (argc > 0)  scenario = OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (scenario == nil)
	{
		OOJSReportBadArguments(context, @"Player", @"endScenario", argc, OOJS_ARGV, nil, @"scenario key");
		return NO;
	}
	
	OOJS_RETURN_BOOL([PLAYER endScenario:scenario]);
	
	OOJS_NATIVE_EXIT
}


// increaseContractReputation()
static JSBool PlayerIncreaseContractReputation(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	[OOPlayerForScripting() increaseContractReputation:1];
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// decreaseContractReputation()
static JSBool PlayerDecreaseContractReputation(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	[OOPlayerForScripting() decreaseContractReputation:1];
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// increaseParcelReputation()
static JSBool PlayerIncreaseParcelReputation(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	[OOPlayerForScripting() increaseParcelReputation:1];
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// decreaseParcelReputation()
static JSBool PlayerDecreaseParcelReputation(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	[OOPlayerForScripting() decreaseParcelReputation:1];
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// increasePassengerReputation()
static JSBool PlayerIncreasePassengerReputation(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	[OOPlayerForScripting() increasePassengerReputation:1];
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// decreasePassengerReputation()
static JSBool PlayerDecreasePassengerReputation(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	[OOPlayerForScripting() decreasePassengerReputation:1];
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}

// addMessageToArrivalReport(message : String)
static JSBool PlayerAddMessageToArrivalReport(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	NSString				*report = nil;
	PlayerEntity			*player = OOPlayerForScripting();
	
	if (argc > 0)  report = OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (report == nil)
	{
		OOJSReportBadArguments(context, @"Player", @"addMessageToArrivalReport", MIN(argc, 1U), OOJS_ARGV, nil, @"string (arrival message)");
		return NO;
	}
	
	[player addMessageToReport:report];
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// replaceShip (shipyard-key : String)
static JSBool PlayerReplaceShip(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	NSString				*shipKey = nil;
	PlayerEntity			*player = OOPlayerForScripting();
	BOOL success = NO;
	int personality = 0;

	if (argc > 0)  shipKey = OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (shipKey == nil)
	{
		OOJSReportBadArguments(context, @"Player", @"replaceShip", MIN(argc, 1U), OOJS_ARGV, nil, @"string (shipyard key)");
		return NO;
	}

	if (EXPECT_NOT(!([player status] == STATUS_DOCKED)))
	{
		OOJSReportError(context, @"Player.replaceShip() only works while the player is docked.");
		return NO;
	}
	
	success = [player buyNamedShip:shipKey];
	if (argc > 1)
	{
		JS_ValueToInt32(context,OOJS_ARGV[1],&personality);
		if (personality >= 0 && (uint16_t)personality < ENTITY_PERSONALITY_MAX)
		{
			[player setEntityPersonalityInt:(uint16_t)personality];
		}
	}

	if (success) 
	{ // slightly misnamed world event now
		[player doScriptEvent:OOJSID("playerBoughtNewShip") withArgument:player];
	}

	OOJS_RETURN_BOOL(success);
	
	OOJS_NATIVE_EXIT
}


// setEscapePodDestination(Entity | 'NEARBY_SYSTEM')
static JSBool PlayerSetEscapePodDestination(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	if (EXPECT_NOT(!OOIsPlayerStale()))
	{
		OOJSReportError(context, @"Player.setEscapePodDestination() only works while the escape pod is in flight.");
		return NO;
	}
	
	BOOL			OK = NO;
	id				destValue = nil;
	PlayerEntity	*player = OOPlayerForScripting();
	
	if (argc == 1)
	{
		destValue = OOJSNativeObjectFromJSValue(context, OOJS_ARGV[0]);
		
		if (destValue == nil)
		{
			[player setDockTarget:NULL];
			OK = YES;
		}
		else if ([destValue isKindOfClass:[ShipEntity class]] && [destValue isStation])
		{
			[player setDockTarget:destValue];
			OK = YES;
		}
		else if ([destValue isKindOfClass:[NSString class]])
		{
			if ([destValue isEqualToString:@"NEARBY_SYSTEM"])
			{
				// find the nearest system with a main station, or die in the attempt!
				[player setDockTarget:NULL];
				
				double rescueRange = MAX_JUMP_RANGE;	// reach at least 1 other system!
				if ([UNIVERSE inInterstellarSpace])
				{
					// Set 3.5 ly as the limit, enough to reach at least 2 systems!
					rescueRange = MAX_JUMP_RANGE / 2.0;
				}
				NSMutableArray	*sDests = [UNIVERSE nearbyDestinationsWithinRange:rescueRange];
				NSUInteger		i = 0, nDests = [sDests count];
				
				if (nDests > 0)	for (i = --nDests; i > 0; i--)
				{
					if ([[sDests oo_dictionaryAtIndex:i] oo_boolForKey:@"nova"])
					{
						[sDests removeObjectAtIndex:i];
					}
				}
				
				// i is back to 0, nDests could have changed...
				nDests = [sDests count];
				if (nDests > 0)	// we have a system with a main station!
				{
					if (nDests > 1)  i = ranrot_rand() % nDests;	// any nearby system will do.
					NSDictionary *dest = [sDests objectAtIndex:i];
					
					// add more time until rescue, with overheads for entering witchspace in case of overlapping systems.
					double dist = [dest oo_doubleForKey:@"distance"];
					[player addToAdjustTime:(.2 + dist * dist) * 3600.0 + 5400.0 * (ranrot_rand() & 127)];
					
					// at the end of the docking sequence we'll check if the target system is the same as the system we're in...
					[player setTargetSystemSeed:RandomSeedFromString([dest oo_stringForKey:@"system_seed"])];
				}
				OK = YES;
			}
		}
		else
		{
			JSBool bValue;
			if (JS_ValueToBoolean(context, OOJS_ARGV[0], &bValue) && bValue == NO)
			{
				[player setDockTarget:NULL];
				OK = YES;
			}
		}
	}
	
	if (OK == NO)
	{
		OOJSReportBadArguments(context, @"Player", @"setEscapePodDestination", argc, OOJS_ARGV, nil, @"a valid station, null, or 'NEARBY_SYSTEM'");
	}
	return OK;
	
	OOJS_NATIVE_EXIT
}


// setPlayerRole (role-key : String [, index : Number])
static JSBool PlayerSetPlayerRole(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	NSString				*role = nil;
	PlayerEntity			*player = OOPlayerForScripting();
	uint32 index = 0;

	if (argc > 0)  role = OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (role == nil)
	{
		OOJSReportBadArguments(context, @"Player", @"setPlayerRole", MIN(argc, 1U), OOJS_ARGV, nil, @"string (role) [, number (index)]");
		return NO;
	}

	if (argc > 1)
	{
		if (JS_ValueToECMAUint32(context,OOJS_ARGV[1],&index))
		{
			[player addRoleToPlayer:role inSlot:index];
			return YES;
		}
	}
	[player addRoleToPlayer:role];
	return YES;

	OOJS_NATIVE_EXIT
}
