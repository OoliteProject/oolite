/*

OOJSPlayer.h

Oolite
Copyright (C) 2004-2011 Giles C Williams and contributors

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


static JSBool PlayerGetProperty(OOJS_PROP_ARGS);
static JSBool PlayerSetProperty(OOJS_PROP_ARGS);

static JSBool PlayerCommsMessage(OOJS_NATIVE_ARGS);
static JSBool PlayerConsoleMessage(OOJS_NATIVE_ARGS);
static JSBool PlayerIncreaseContractReputation(OOJS_NATIVE_ARGS);
static JSBool PlayerDecreaseContractReputation(OOJS_NATIVE_ARGS);
static JSBool PlayerIncreasePassengerReputation(OOJS_NATIVE_ARGS);
static JSBool PlayerDecreasePassengerReputation(OOJS_NATIVE_ARGS);
static JSBool PlayerAddMessageToArrivalReport(OOJS_NATIVE_ARGS);
static JSBool PlayerSetEscapePodDestination(OOJS_NATIVE_ARGS);


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
	kPlayer_credits,				// credit balance, float, read/write
#if DOCKING_CLEARANCE_ENABLED
	kPlayer_dockingClearanceStatus,	// docking clearance status, string, read only
#endif
	kPlayer_legalStatus,			// legalStatus, string, read-only
	kPlayer_name,					// Player name, string, read-only
	kPlayer_passengerReputation,	// reputation for passenger contracts, integer, read-only
	kPlayer_rank,					// rank, string, read-only
	kPlayer_score,					// kill count, integer, read/write
	kPlayer_trumbleCount,			// number of trumbles, integer, read-only
};


static JSPropertySpec sPlayerProperties[] =
{
	// JS name					ID							flags
	{ "name",					kPlayer_name,				OOJS_PROP_READONLY_CB },
	{ "score",					kPlayer_score,				OOJS_PROP_READWRITE_CB },
	{ "credits",				kPlayer_credits,			OOJS_PROP_READWRITE_CB },
	{ "rank",					kPlayer_rank,				OOJS_PROP_READONLY_CB },
	{ "legalStatus",			kPlayer_legalStatus,		OOJS_PROP_READONLY_CB },
	{ "alertCondition",			kPlayer_alertCondition,		OOJS_PROP_READONLY_CB },
	{ "alertTemperature",		kPlayer_alertTemperature,	OOJS_PROP_READONLY_CB },
	{ "alertMassLocked",		kPlayer_alertMassLocked,	OOJS_PROP_READONLY_CB },
	{ "alertAltitude",			kPlayer_alertAltitude,		OOJS_PROP_READONLY_CB },
	{ "alertEnergy",			kPlayer_alertEnergy,		OOJS_PROP_READONLY_CB },
	{ "alertHostiles",			kPlayer_alertHostiles,		OOJS_PROP_READONLY_CB },
	{ "trumbleCount",			kPlayer_trumbleCount,		OOJS_PROP_READONLY_CB },
	{ "contractReputation",		kPlayer_contractReputation,	OOJS_PROP_READONLY_CB },
	{ "passengerReputation",	kPlayer_passengerReputation,	OOJS_PROP_READONLY_CB },
#if DOCKING_CLEARANCE_ENABLED
	{ "dockingClearanceStatus",	kPlayer_dockingClearanceStatus,	OOJS_PROP_READONLY_CB },
#endif
	{ "bounty",					kPlayer_bounty,				OOJS_PROP_READWRITE_CB },
	{ 0 }
};


static JSFunctionSpec sPlayerMethods[] =
{
	// JS name							Function							min args
	{ "addMessageToArrivalReport",		PlayerAddMessageToArrivalReport,	1 },
	{ "commsMessage",					PlayerCommsMessage,					1 },
	{ "consoleMessage",					PlayerConsoleMessage,				1 },
	{ "decreaseContractReputation",		PlayerDecreaseContractReputation,	0 },
	{ "decreasePassengerReputation",	PlayerDecreasePassengerReputation,	0 },
	{ "increaseContractReputation",		PlayerIncreaseContractReputation,	0 },
	{ "increasePassengerReputation",	PlayerIncreasePassengerReputation,	0 },
	{ "setEscapePodDestination",		PlayerSetEscapePodDestination,		1 },	// null destination must be set explicitly
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


static JSBool PlayerGetProperty(OOJS_PROP_ARGS)
{
	if (!OOJS_PROPID_IS_INT)  return YES;
	
	OOJS_NATIVE_ENTER(context)
	
	BOOL						OK = NO;
	id							result = nil;
	PlayerEntity				*player = OOPlayerForScripting();
	
	switch (OOJS_PROPID_INT)
	{
		case kPlayer_name:
			result = [player playerName];
			OK = YES;
			break;
			
		case kPlayer_score:
			*value = INT_TO_JSVAL([player score]);
			OK = YES;
			break;
			
		case kPlayer_credits:
			OK = JS_NewDoubleValue(context, [player creditBalance], value);
			break;
			
		case kPlayer_rank:
			*value = [OODisplayRatingStringFromKillCount([player score]) oo_jsValueInContext:context];
			OK = YES;
			break;
			
		case kPlayer_legalStatus:
			*value = [OODisplayStringFromLegalStatus([player bounty]) oo_jsValueInContext:context];
			OK = YES;
			break;
			
		case kPlayer_alertCondition:
			*value = INT_TO_JSVAL([player alertCondition]);
			OK = YES;
			break;
			
		case kPlayer_alertTemperature:
			*value = OOJSValueFromBOOL([player alertFlags] & ALERT_FLAG_TEMP);
			OK = YES;
			break;
			
		case kPlayer_alertMassLocked:
			*value = OOJSValueFromBOOL([player alertFlags] & ALERT_FLAG_MASS_LOCK);
			OK = YES;
			break;
			
		case kPlayer_alertAltitude:
			*value = OOJSValueFromBOOL([player alertFlags] & ALERT_FLAG_ALT);
			OK = YES;
			break;
			
		case kPlayer_alertEnergy:
			*value = OOJSValueFromBOOL([player alertFlags] & ALERT_FLAG_ENERGY);
			OK = YES;
			break;
			
		case kPlayer_alertHostiles:
			*value = OOJSValueFromBOOL([player alertFlags] & ALERT_FLAG_HOSTILES);
			OK = YES;
			break;
			
		case kPlayer_trumbleCount:
			OK = JS_NewNumberValue(context, [player trumbleCount], value);
			break;
			
		case kPlayer_contractReputation:
			*value = INT_TO_JSVAL([player contractReputation]);
			OK = YES;
			break;
			
		case kPlayer_passengerReputation:
			*value = INT_TO_JSVAL([player passengerReputation]);
			OK = YES;
			break;
		
#if DOCKING_CLEARANCE_ENABLED	
		case kPlayer_dockingClearanceStatus:
			*value = [DockingClearanceStatusToString([player getDockingClearanceStatus]) oo_jsValueInContext:context];
			OK = YES;
			break;
#endif
			
		case kPlayer_bounty:
			*value = INT_TO_JSVAL([player legalStatus]);
			OK = YES;
			break;
		
		default:
			OOJSReportBadPropertySelector(context, @"Player", OOJS_PROPID_INT);
	}
	
	if (OK && result != nil)  *value = [result oo_jsValueInContext:context];
	return OK;
	
	OOJS_NATIVE_EXIT
}


static JSBool PlayerSetProperty(OOJS_PROP_ARGS)
{
	if (!OOJS_PROPID_IS_INT)  return YES;
	
	OOJS_NATIVE_ENTER(context)
	
	BOOL						OK = NO;
	PlayerEntity				*player = OOPlayerForScripting();
	jsdouble					fValue;
	int32						iValue;
	
	switch (OOJS_PROPID_INT)
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
			OOJSReportBadPropertySelector(context, @"Player", OOJS_PROPID_INT);
	}
	
	return OK;
	
	OOJS_NATIVE_EXIT
}


// *** Methods ***

// commsMessage(message : String [, duration : Number])
static JSBool PlayerCommsMessage(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	NSString				*message = nil;
	double					time = 4.5;
	BOOL					gotTime = YES;
	
	message = OOStringFromJSValue(context, OOJS_ARG(0));
	if (argc > 1)  gotTime = JS_ValueToNumber(context, OOJS_ARG(1), &time);
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
static JSBool PlayerConsoleMessage(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	NSString				*message = nil;
	double					time = 3.0;
	BOOL					gotTime = YES;
	
	message = OOStringFromJSValue(context, OOJS_ARG(0));
	if (argc > 1)  gotTime = JS_ValueToNumber(context, OOJS_ARG(1), &time);
	if (message == nil || !gotTime)
	{
		OOJSReportBadArguments(context, @"Player", @"consoleMessage", argc, OOJS_ARGV, nil, @"message and optional duration");
		return NO;
	}
	
	[UNIVERSE addMessage:message forCount:time];
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// increaseContractReputation()
static JSBool PlayerIncreaseContractReputation(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	[OOPlayerForScripting() increaseContractReputation];
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// decreaseContractReputation()
static JSBool PlayerDecreaseContractReputation(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	[OOPlayerForScripting() decreaseContractReputation];
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// increasePassengerReputation()
static JSBool PlayerIncreasePassengerReputation(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	[OOPlayerForScripting() increasePassengerReputation];
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// decreasePassengerReputation()
static JSBool PlayerDecreasePassengerReputation(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	[OOPlayerForScripting() decreasePassengerReputation];
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}

// addMessageToArrivalReport(message : String)
static JSBool PlayerAddMessageToArrivalReport(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	NSString				*report = nil;
	
	report = OOStringFromJSValue(context, OOJS_ARG(0));
	if (report == nil)
	{
		OOJSReportBadArguments(context, @"Player", @"addMessageToArrivalReport", argc, OOJS_ARGV, nil, @"arrival message");
		return NO;
	}
	
	[OOPlayerForScripting() addMessageToReport:report];
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// setEscapePodDestination(Entity | 'NEARBY_SYSTEM')
static JSBool PlayerSetEscapePodDestination(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	if (EXPECT_NOT(!OOIsPlayerStale()))
	{
		OOJSReportError(context, @"Player.setEscapePodDestination() only works while the escape pod is in flight.");
		return NO;
	}
	
	BOOL			OK = NO;
	id				destValue = NO;
	PlayerEntity	*player = OOPlayerForScripting();
	
	if (argc == 1)
	{
		destValue = OOJSNativeObjectFromJSValue(context, OOJS_ARG(0));
		
		if (!destValue || [destValue isKindOfClass:[ShipEntity class]])
		{
			// if destValue is anything rather than NO or a station, don't do anything, keep OK == NO
			if (!destValue)
			{
				[player setDockTarget:NULL];
				OK = YES;
			}
			else if ([destValue isStation])
			{
				[player setDockTarget:destValue];
				OK = YES;
			}
		}
		else
		{
			if ([destValue isKindOfClass:[NSString class]])
			{
				if ([destValue isEqualToString:@"NEARBY_SYSTEM"])
				{
					// find the nearest system with a main station, or die in the attempt!
					[player setDockTarget:NULL];
					
					double rescueRange = 7.0;	// reach at least 1 other system!
					if ([UNIVERSE inInterstellarSpace])
					{
						// Set 3.5 ly as the limit, enough to reach at least 2 systems!
						// In strict mode the max rescue distance in witchspace would be 2.35ly:
						// 4.70 fuel to get there, 2.35 to fly back = 7ly fuel, plus rounding error.
						rescueRange = [UNIVERSE strict] ? 2.35 : 3.5;
					}
					NSMutableArray	*sDests = (NSMutableArray *)[UNIVERSE nearbyDestinationsWithinRange:rescueRange];
					int 			i = 0, nDests = [sDests count];
					if (nDests > 0)	for (i = --nDests; i > 0; i--)
					{
						if ([(NSDictionary*)[sDests objectAtIndex:i] oo_boolForKey:@"nova"])
						{
							[sDests removeObjectAtIndex:i];
						}
					}
					
					// i is back to 0, nDests could have changed...
					nDests = [sDests count];
					if (nDests > 0)	// we have a system with a main station!
					{
						if (nDests > 1) i = ranrot_rand() % nDests;	// any nearby system will do.
						NSDictionary * dest = [sDests objectAtIndex:i];
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
				JSBool		bValue;
				if (JS_ValueToBoolean(context, OOJS_ARG(0), &bValue) && bValue == NO)
				{
					[player setDockTarget:NULL];
					OK = YES;
				}
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
