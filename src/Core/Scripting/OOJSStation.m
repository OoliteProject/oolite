/*
OOJSStation.m

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

#import "OOJSStation.h"
#import "OOJSEntity.h"
#import "OOJSShip.h"
#import "OOJSPlayer.h"
#import "PlayerEntityContracts.h"
#import "OOJavaScriptEngine.h"
#import "OOJSInterfaceDefinition.h"

#import "OOCollectionExtractors.h"
#import "OOEquipmentType.h"
#import "OOShipRegistry.h"
#import "OOConstToString.h"
#import "StationEntity.h"
#import "GameController.h"


static JSObject		*sStationPrototype;

static BOOL JSStationGetStationEntity(JSContext *context, JSObject *stationObj, StationEntity **outEntity);


static JSBool StationGetProperty(JSContext *context, JSObject *this, jsid propID, jsval *value);
static JSBool StationSetProperty(JSContext *context, JSObject *this, jsid propID, JSBool strict, jsval *value);

static JSBool StationAbortAllDockings(JSContext *context, uintN argc, jsval *vp);
static JSBool StationAbortDockingForShip(JSContext *context, uintN argc, jsval *vp);
static JSBool StationCanDockShip(JSContext *context, uintN argc, jsval *vp);
static JSBool StationDockPlayer(JSContext *context, uintN argc, jsval *vp);
static JSBool StationIncreaseAlertLevel(JSContext *context, uintN argc, jsval *vp);
static JSBool StationDecreaseAlertLevel(JSContext *context, uintN argc, jsval *vp);
static JSBool StationLaunchShipWithRole(JSContext *context, uintN argc, jsval *vp);
static JSBool StationLaunchDefenseShip(JSContext *context, uintN argc, jsval *vp);
static JSBool StationLaunchEscort(JSContext *context, uintN argc, jsval *vp);
static JSBool StationLaunchScavenger(JSContext *context, uintN argc, jsval *vp);
static JSBool StationLaunchMiner(JSContext *context, uintN argc, jsval *vp);
static JSBool StationLaunchPirateShip(JSContext *context, uintN argc, jsval *vp);
static JSBool StationLaunchShuttle(JSContext *context, uintN argc, jsval *vp);
static JSBool StationLaunchPatrol(JSContext *context, uintN argc, jsval *vp);
static JSBool StationLaunchPolice(JSContext *context, uintN argc, jsval *vp);
static JSBool StationSetInterface(JSContext *context, uintN argc, jsval *vp);
static JSBool StationSetMarketPrice(JSContext *context, uintN argc, jsval *vp);
static JSBool StationSetMarketQuantity(JSContext *context, uintN argc, jsval *vp);
static JSBool StationResetMarket(JSContext *context, uintN argc, jsval *vp);
static JSBool StationAddShipToShipyard(JSContext *context, uintN argc, jsval *vp);
static JSBool StationRemoveShipFromShipyard(JSContext *context, uintN argc, jsval *vp);

static JSClass sStationClass =
{
	"Station",
	JSCLASS_HAS_PRIVATE,
	
	JS_PropertyStub,		// addProperty
	JS_PropertyStub,		// delProperty
	StationGetProperty,		// getProperty
	StationSetProperty,		// setProperty
	JS_EnumerateStub,		// enumerate
	JS_ResolveStub,			// resolve
	JS_ConvertStub,			// convert
	OOJSObjectWrapperFinalize,// finalize
	JSCLASS_NO_OPTIONAL_MEMBERS
};


enum
{
	// Property IDs
	kStation_alertCondition,
	kStation_allegiance,
	kStation_allowsAutoDocking,
	kStation_allowsFastDocking,
	kStation_breakPattern,
	kStation_dockedContractors, // miners and scavengers.
	kStation_dockedDefenders,
	kStation_dockedPolice,
	kStation_equipmentPriceFactor,
	kStation_equivalentTechLevel,
	kStation_hasNPCTraffic,
	kStation_hasShipyard,
	kStation_isMainStation,		// Is [UNIVERSE station], boolean, read-only
	kStation_market,
	kStation_requiresDockingClearance,
	kStation_roll,
	kStation_suppressArrivalReports,
	kStation_shipyard,
};


static JSPropertySpec sStationProperties[] =
{
	// JS name						ID									flags
	{ "alertCondition",				kStation_alertCondition,			OOJS_PROP_READWRITE_CB },
	{ "allegiance",					kStation_allegiance,				OOJS_PROP_READWRITE_CB },
	{ "allowsAutoDocking",			kStation_allowsAutoDocking,			OOJS_PROP_READWRITE_CB },
	{ "allowsFastDocking",			kStation_allowsFastDocking,			OOJS_PROP_READWRITE_CB },
	{ "breakPattern",				kStation_breakPattern,				OOJS_PROP_READWRITE_CB },
	{ "dockedContractors",			kStation_dockedContractors,			OOJS_PROP_READONLY_CB },
	{ "dockedDefenders",			kStation_dockedDefenders,			OOJS_PROP_READONLY_CB },
	{ "dockedPolice",				kStation_dockedPolice,				OOJS_PROP_READONLY_CB },
	{ "equipmentPriceFactor",		kStation_equipmentPriceFactor,		OOJS_PROP_READONLY_CB },
	{ "equivalentTechLevel",		kStation_equivalentTechLevel,		OOJS_PROP_READONLY_CB },
	{ "hasNPCTraffic",				kStation_hasNPCTraffic,				OOJS_PROP_READWRITE_CB },
	{ "hasShipyard",				kStation_hasShipyard,				OOJS_PROP_READONLY_CB },
	{ "isMainStation",				kStation_isMainStation,				OOJS_PROP_READONLY_CB },
	{ "market",        kStation_market,     OOJS_PROP_READONLY_CB },
	{ "requiresDockingClearance",	kStation_requiresDockingClearance,	OOJS_PROP_READWRITE_CB },
	{ "roll",						kStation_roll,						OOJS_PROP_READWRITE_CB },
	{ "suppressArrivalReports",		kStation_suppressArrivalReports,	OOJS_PROP_READWRITE_CB },
	{ "shipyard",                   kStation_shipyard,                  OOJS_PROP_READONLY_CB },
	{ 0 }
};


static JSFunctionSpec sStationMethods[] =
{
	// JS name					Function						min args
	{ "abortAllDockings",		StationAbortAllDockings,		0 },
	{ "abortDockingForShip",	StationAbortDockingForShip,		1 },
	{ "canDockShip",            StationCanDockShip,				1 },	
	{ "dockPlayer",				StationDockPlayer,				0 },
	{ "increaseAlertLevel",     StationIncreaseAlertLevel,      0 },
	{ "decreaseAlertLevel",     StationDecreaseAlertLevel,      0 },
	{ "launchDefenseShip",		StationLaunchDefenseShip,		0 },
	{ "launchEscort",			StationLaunchEscort,			0 },
	{ "launchMiner",			StationLaunchMiner,				0 },
	{ "launchPatrol",			StationLaunchPatrol,			0 },
	{ "launchPirateShip",		StationLaunchPirateShip,		0 },
	{ "launchPolice",			StationLaunchPolice,			0 },
	{ "launchScavenger",		StationLaunchScavenger,			0 },
	{ "launchShipWithRole",		StationLaunchShipWithRole,		1 },
	{ "launchShuttle",			StationLaunchShuttle,			0 },
	{ "setInterface",			StationSetInterface,			0 },
	{ "setMarketPrice",			StationSetMarketPrice,			2 },
	{ "setMarketQuantity",		StationSetMarketQuantity,		2 },
	{ "resetMarket",			StationResetMarket,				0 },
	{ "addShipToShipyard",      StationAddShipToShipyard,       1 },
	{ "removeShipFromShipyard", StationRemoveShipFromShipyard,  1 },
	{ 0 }
};


void InitOOJSStation(JSContext *context, JSObject *global)
{
	sStationPrototype = JS_InitClass(context, global, JSShipPrototype(), &sStationClass, OOJSUnconstructableConstruct, 0, sStationProperties, sStationMethods, NULL, NULL);
	OOJSRegisterObjectConverter(&sStationClass, OOJSBasicPrivateObjectConverter);
	OOJSRegisterSubclass(&sStationClass, JSShipClass());
}


static BOOL JSStationGetStationEntity(JSContext *context, JSObject *stationObj, StationEntity **outEntity)
{
	OOJS_PROFILE_ENTER
	
	BOOL						result;
	Entity						*entity = nil;
	
	if (outEntity == NULL)  return NO;
	*outEntity = nil;
	
	result = OOJSEntityGetEntity(context, stationObj, &entity);
	if (!result)  return NO;
	
	if (![entity isKindOfClass:[StationEntity class]])  return NO;
	
	*outEntity = (StationEntity *)entity;
	return YES;
	
	OOJS_PROFILE_EXIT
}

static BOOL JSStationGetShipEntity(JSContext *context, JSObject *shipObj, ShipEntity **outEntity)
{
	OOJS_PROFILE_ENTER
	
	BOOL						result;
	Entity						*entity = nil;
	
	if (outEntity == NULL)  return NO;
	*outEntity = nil;
	
	result = OOJSEntityGetEntity(context, shipObj, &entity);
	if (!result)  return NO;
	
	if (![entity isKindOfClass:[ShipEntity class]])  return NO;
	
	*outEntity = (ShipEntity *)entity;
	return YES;
	
	OOJS_PROFILE_EXIT
}


@implementation StationEntity (OOJavaScriptExtensions)

- (void)getJSClass:(JSClass **)outClass andPrototype:(JSObject **)outPrototype
{
	*outClass = &sStationClass;
	*outPrototype = sStationPrototype;
}


- (NSString *) oo_jsClassName
{
	return @"Station";
}

@end


static JSBool StationGetProperty(JSContext *context, JSObject *this, jsid propID, jsval *value)
{
	if (!JSID_IS_INT(propID))  return YES;
	
	OOJS_NATIVE_ENTER(context)
	
	StationEntity				*entity = nil;
	
	if (!JSStationGetStationEntity(context, this, &entity))  return NO;
	if (entity == nil)  { *value = JSVAL_VOID; return YES; }
	
	switch (JSID_TO_INT(propID))
	{
		case kStation_isMainStation:
			*value = OOJSValueFromBOOL(entity == [UNIVERSE station]);
			return YES;
		
		case kStation_hasNPCTraffic:
			*value = OOJSValueFromBOOL([entity hasNPCTraffic]);
			return YES;
			
		case kStation_hasShipyard:
			*value = OOJSValueFromBOOL([entity hasShipyard]);
			return YES;
		
		case kStation_alertCondition:
			*value = INT_TO_JSVAL([entity alertLevel]);
			return YES;

		case kStation_allegiance:
		{
			NSString *result = [entity allegiance];
			*value = OOJSValueFromNativeObject(context, result);
			return YES;
		}
			
		case kStation_requiresDockingClearance:
			*value = OOJSValueFromBOOL([entity requiresDockingClearance]);
			return YES;
			
		case kStation_roll:
			// same as in ship definition, but this time read/write below
			return JS_NewNumberValue(context, [entity flightRoll], value);
			
		case kStation_allowsFastDocking:
			*value = OOJSValueFromBOOL([entity allowsFastDocking]);
			return YES;
			
		case kStation_allowsAutoDocking:
			*value = OOJSValueFromBOOL([entity allowsAutoDocking]);
			return YES;

		case kStation_dockedContractors:
			*value = INT_TO_JSVAL([entity countOfDockedContractors]);
			return YES;
			
		case kStation_dockedPolice:
			*value = INT_TO_JSVAL([entity countOfDockedPolice]);
			return YES;
			
		case kStation_dockedDefenders:
			*value = INT_TO_JSVAL([entity countOfDockedDefenders]);
			return YES;
			
		case kStation_equivalentTechLevel:
			*value = INT_TO_JSVAL((int32_t)[entity equivalentTechLevel]);
			return YES;
			
		case kStation_equipmentPriceFactor:
			return JS_NewNumberValue(context, [entity equipmentPriceFactor], value);
			
		case kStation_suppressArrivalReports:
			*value = OOJSValueFromBOOL([entity suppressArrivalReports]);
			return YES;
			
		case kStation_breakPattern:
			*value = OOJSValueFromBOOL([entity hasBreakPattern]);
			return YES;

		case kStation_shipyard:
		{
			if (![entity hasShipyard]) 
			{
				// return null if station has no shipyard
				*value = OOJSValueFromNativeObject(context, nil);
			} 
			else 
			{
				if ([entity localShipyard] == nil) [entity generateShipyard];
				NSMutableArray *shipyard = [entity localShipyard];
				*value = OOJSValueFromNativeObject(context, shipyard);
			}
			return YES;
		}

		case kStation_market:
		{
			NSDictionary *market = [entity localMarketForScripting];
			*value = OOJSValueFromNativeObject(context, market);
			return YES;
		}

		default:
			OOJSReportBadPropertySelector(context, this, propID, sStationProperties);
			return NO;
	}
	
	OOJS_NATIVE_EXIT
}


static JSBool StationSetProperty(JSContext *context, JSObject *this, jsid propID, JSBool strict, jsval *value)
{
	if (!JSID_IS_INT(propID))  return YES;
	
	OOJS_NATIVE_ENTER(context)
	
	StationEntity				*entity = nil;
	JSBool						bValue;
	int32						iValue;
	jsdouble					fValue;
	NSString					*sValue = nil;
	
	if (!JSStationGetStationEntity(context, this, &entity)) return NO;
	if (entity == nil)  return YES;
	
	switch (JSID_TO_INT(propID))
	{
		case kStation_hasNPCTraffic:
			if (JS_ValueToBoolean(context, *value, &bValue))
			{
				[entity setHasNPCTraffic:bValue];
				return YES;
			}
			break;
		
		case kStation_alertCondition:
			if (JS_ValueToInt32(context, *value, &iValue))
			{
				[entity setAlertLevel:iValue signallingScript:NO];	// Performs range checking
				return YES;
			}
			break;

		case kStation_allegiance:
			sValue = OOStringFromJSValue(context,*value);
			if (sValue != nil)
			{
				[entity setAllegiance:sValue];
				return YES;
			}
			break;

			
		case kStation_requiresDockingClearance:
			if (JS_ValueToBoolean(context, *value, &bValue))
			{
				[entity setRequiresDockingClearance:bValue];
				return YES;
			}
			break;
			
		case kStation_roll:
			if (JS_ValueToNumber(context, *value, &fValue))
			{
/*				if (fValue < -2.0)  fValue = -2.0;
				if (fValue > 2.0)  fValue = 2.0;	// clamping to -2.0...2.0 gives us ±M_PI actual maximum rotation
				[entity setRoll:fValue]; */
				// use setRawRoll to make the units here equal to those in kShip_roll
				if (fValue < -M_PI)  fValue = -M_PI;
				else if (fValue > M_PI)  fValue = M_PI;
				[entity setRawRoll:fValue];
				return YES;
			}
			break;

		case kStation_allowsFastDocking:
			if (JS_ValueToBoolean(context, *value, &bValue))
			{
				[entity setAllowsFastDocking:bValue];
				return YES;
			}
			break;
			
		case kStation_allowsAutoDocking:
			if (JS_ValueToBoolean(context, *value, &bValue))
			{
				[entity setAllowsAutoDocking:bValue];
				return YES;
			}
			break;

		case kStation_suppressArrivalReports:
			if (JS_ValueToBoolean(context, *value, &bValue))
			{
				[entity setSuppressArrivalReports:bValue];
				return YES;
			}
			break;

		case kStation_breakPattern:
			if (JS_ValueToBoolean(context, *value, &bValue))
			{
				[entity setHasBreakPattern:bValue];
				return YES;
			}
			break;
		
		default:
			OOJSReportBadPropertySelector(context, this, propID, sStationProperties);
			return NO;
	}
	
	OOJSReportBadPropertyValue(context, this, propID, sStationProperties, *value);
	return NO;
	
	OOJS_NATIVE_EXIT
}


// *** Methods ***

static JSBool StationAbortAllDockings(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	StationEntity *station = nil;
	JSStationGetStationEntity(context, OOJS_THIS, &station); 
	[station abortAllDockings];
	
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}

static JSBool StationAbortDockingForShip(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	StationEntity *station = nil;
	JSStationGetStationEntity(context, OOJS_THIS, &station); 
	if (argc == 0)
	{
		OOJSReportBadArguments(context, @"Station", @"abortDockingForShip", MIN(argc, 1U), OOJS_ARGV, nil, @"ship in docking queue");
		return NO;
	}
	if (!JSVAL_IS_OBJECT(OOJS_ARGV[0]))  return NO;
	ShipEntity *ship = nil;
	JSStationGetShipEntity(context, JSVAL_TO_OBJECT(OOJS_ARGV[0]), &ship);
	if (ship != nil)
	{
		[station abortDockingForShip:ship];
	}
	
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}

// canDockShip(shipEntity) : boolean
// Proposed by phkb (Nick Rogers) 20161206
static JSBool StationCanDockShip(JSContext *context, uintN argc, jsval *vp)
{
   OOJS_NATIVE_ENTER(context)

   BOOL         result = YES;
   ShipEntity      *shipToCheck = nil;

   if (argc > 0)
   {
      if (!JSVAL_IS_OBJECT(OOJS_ARGV[0]) || !JSStationGetShipEntity(context, JSVAL_TO_OBJECT(OOJS_ARGV[0]), &shipToCheck))
      {
         return NO;
      }
   }
   if (EXPECT_NOT(shipToCheck == nil))
   {
      OOJSReportBadArguments(context, @"Station", @"canDockShip", MIN(argc, 1U), OOJS_ARGV, nil, @"shipEntity");
      return NO;
   }
   
   StationEntity *station = nil;
   if (!JSStationGetStationEntity(context, OOJS_THIS, &station))  OOJS_RETURN_VOID; // stale reference, no-op
   
   OOJS_BEGIN_FULL_NATIVE(context)
   result = [station fitsInDock:shipToCheck andLogNoFit:NO];
   OOJS_END_FULL_NATIVE

   OOJS_RETURN_BOOL(result);
   OOJS_NATIVE_EXIT
}


// dockPlayer()
// Proposed and written by Frame 20090729
static JSBool StationDockPlayer(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	PlayerEntity	*player = OOPlayerForScripting();
	GameController	*gameController = [UNIVERSE gameController];
	
	if (EXPECT_NOT([gameController isGamePaused]))
	{
		/*	Station.dockPlayer() was executed while the game was in pause.
			Do we want to return an error or just unpause and continue?
			I think unpausing is the sensible thing to do here - Nikos 20110208
		*/
		[gameController setGamePaused:NO];
	}
	
	if (EXPECT(![player isDocked]))
	{
		StationEntity *stationForDockingPlayer = nil;
		JSStationGetStationEntity(context, OOJS_THIS, &stationForDockingPlayer); 
		[player setDockingClearanceStatus:DOCKING_CLEARANCE_STATUS_GRANTED];
		[player safeAllMissiles];
		[UNIVERSE setViewDirection:VIEW_FORWARD];
		[player enterDock:stationForDockingPlayer];
	}
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


static JSBool StationIncreaseAlertLevel(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	StationEntity	*station = nil;

	if (!JSStationGetStationEntity(context, OOJS_THIS, &station))  OOJS_RETURN_VOID; // stale reference, no-op

	OOJS_BEGIN_FULL_NATIVE(context)
	if ([station alertCondition] < 3)
	{
		[station increaseAlertLevel];
	}
	OOJS_END_FULL_NATIVE
	OOJS_RETURN_VOID;
	OOJS_NATIVE_EXIT
}

static JSBool StationDecreaseAlertLevel(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	StationEntity	*station = nil;

	if (!JSStationGetStationEntity(context, OOJS_THIS, &station))  OOJS_RETURN_VOID; // stale reference, no-op

	OOJS_BEGIN_FULL_NATIVE(context)
	if ([station alertCondition] > 1)
	{
		[station decreaseAlertLevel];
	}
	OOJS_END_FULL_NATIVE
	OOJS_RETURN_VOID;
	OOJS_NATIVE_EXIT
}

// launchShipWithRole(role : String [, abortAllDockings : boolean]) : shipEntity
static JSBool StationLaunchShipWithRole(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	NSString		*shipRole = nil;
	StationEntity	*station = nil;
	ShipEntity		*result = nil;
	JSBool			abortAllDockings = NO;
	
	if (!JSStationGetStationEntity(context, OOJS_THIS, &station))  OOJS_RETURN_VOID; // stale reference, no-op
	
	if (argc > 0)  shipRole = OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (EXPECT_NOT(shipRole == nil))
	{
		OOJSReportBadArguments(context, @"Station", @"launchShipWithRole", MIN(argc, 1U), OOJS_ARGV, nil, @"string (role)");
		return NO;
	}
	
	if (argc > 1)  JS_ValueToBoolean(context, OOJS_ARGV[1], &abortAllDockings);

	OOJS_BEGIN_FULL_NATIVE(context)
	result = [station launchIndependentShip:shipRole];
	if (abortAllDockings) [station abortAllDockings];
	OOJS_END_FULL_NATIVE

	OOJS_RETURN_OBJECT(result);
	OOJS_NATIVE_EXIT
}


static JSBool StationLaunchDefenseShip(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	StationEntity *station = nil;
	if (!JSStationGetStationEntity(context, OOJS_THIS, &station))  OOJS_RETURN_VOID; // stale reference, no-op

	ShipEntity *launched = nil;
	OOJS_BEGIN_FULL_NATIVE(context)
	launched = [station launchDefenseShip];
	OOJS_END_FULL_NATIVE
	OOJS_RETURN_OBJECT(launched);

	OOJS_NATIVE_EXIT
}


static JSBool StationLaunchEscort(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	StationEntity *station = nil;
	if (!JSStationGetStationEntity(context, OOJS_THIS, &station))  OOJS_RETURN_VOID; // stale reference, no-op
	
	ShipEntity *launched = nil;
	OOJS_BEGIN_FULL_NATIVE(context)
	launched = [station launchEscort];
	OOJS_END_FULL_NATIVE
	OOJS_RETURN_OBJECT(launched);

	OOJS_NATIVE_EXIT
}


static JSBool StationLaunchScavenger(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	StationEntity *station = nil;
	if (!JSStationGetStationEntity(context, OOJS_THIS, &station))  OOJS_RETURN_VOID; // stale reference, no-op

	ShipEntity *launched = nil;
	OOJS_BEGIN_FULL_NATIVE(context)
	launched = [station launchScavenger];
	OOJS_END_FULL_NATIVE
	OOJS_RETURN_OBJECT(launched);

	OOJS_NATIVE_EXIT
}


static JSBool StationLaunchMiner(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	StationEntity *station = nil;
	if (!JSStationGetStationEntity(context, OOJS_THIS, &station))  OOJS_RETURN_VOID; // stale reference, no-op
	
	ShipEntity *launched = nil;
	OOJS_BEGIN_FULL_NATIVE(context)
	launched = [station launchMiner];
	OOJS_END_FULL_NATIVE
	OOJS_RETURN_OBJECT(launched);
	OOJS_NATIVE_EXIT
}


static JSBool StationLaunchPirateShip(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	StationEntity *station = nil;
	if (!JSStationGetStationEntity(context, OOJS_THIS, &station))  OOJS_RETURN_VOID; // stale reference, no-op
	
	ShipEntity *launched = nil;
	OOJS_BEGIN_FULL_NATIVE(context)
	launched = [station launchPirateShip];
	OOJS_END_FULL_NATIVE
	OOJS_RETURN_OBJECT(launched);

	OOJS_NATIVE_EXIT
}


static JSBool StationLaunchShuttle(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	StationEntity *station = nil;
	if (!JSStationGetStationEntity(context, OOJS_THIS, &station))  OOJS_RETURN_VOID; // stale reference, no-op
	
	ShipEntity *launched = nil;
	OOJS_BEGIN_FULL_NATIVE(context)
	launched = [station launchShuttle];
	OOJS_END_FULL_NATIVE
	OOJS_RETURN_OBJECT(launched);
	OOJS_NATIVE_EXIT
}


static JSBool StationLaunchPatrol(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	StationEntity *station = nil;
	if (!JSStationGetStationEntity(context, OOJS_THIS, &station))  OOJS_RETURN_VOID; // stale reference, no-op
	
	ShipEntity *launched = nil;
	OOJS_BEGIN_FULL_NATIVE(context)
	launched = [station launchPatrol];
	OOJS_END_FULL_NATIVE
	OOJS_RETURN_OBJECT(launched);
	OOJS_NATIVE_EXIT
}


static JSBool StationLaunchPolice(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	StationEntity *station = nil;
	if (!JSStationGetStationEntity(context, OOJS_THIS, &station))  OOJS_RETURN_VOID; // stale reference, no-op
	
	NSArray *launched = nil;
	OOJS_BEGIN_FULL_NATIVE(context)
	launched = [station launchPolice];
	OOJS_END_FULL_NATIVE
	OOJS_RETURN_OBJECT(launched);
	OOJS_NATIVE_EXIT
}

static JSBool StationSetInterface(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)

	StationEntity *station = nil;
	if (!JSStationGetStationEntity(context, OOJS_THIS, &station))  OOJS_RETURN_VOID; // stale reference, no-op

	if (argc < 1)
	{
		OOJSReportBadArguments(context, @"Station", @"setInterface", MIN(argc, 1U), OOJS_ARGV, NULL, @"key [, definition]");
		return NO;
	}
	NSString *key = OOStringFromJSValue(context, OOJS_ARGV[0]);

	if (argc < 2 || JSVAL_IS_NULL(OOJS_ARGV[1]))
	{
		[station setInterfaceDefinition:nil forKey:key];
		OOJS_RETURN_VOID;
	}
	

	jsval				value = JSVAL_NULL;
	jsval				callback = JSVAL_NULL;
	JSObject				*callbackThis = NULL;
	JSObject			*params = NULL;

	NSString      *title = nil;
	NSString      *summary = nil;
	NSString      *category = nil;

	if (!JS_ValueToObject(context, OOJS_ARGV[1], &params))
	{
		OOJSReportBadArguments(context, @"Station", @"setInterface", MIN(argc, 1U), OOJS_ARGV, NULL, @"key [, definition]");
		return NO;
	}

	// get and validate title
	if (JS_GetProperty(context, params, "title", &value) == JS_FALSE || JSVAL_IS_VOID(value))
	{
		OOJSReportBadArguments(context, @"Station", @"setInterface", MIN(argc, 1U), OOJS_ARGV, NULL, @"key [, definition]; if definition is set, it must have a 'title' property.");
		return NO;
	}
	title = OOStringFromJSValue(context, value);
	if (title == nil || [title length] == 0) 
	{
		OOJSReportBadArguments(context, @"Station", @"setInterface", MIN(argc, 1U), OOJS_ARGV, NULL, @"key [, definition]; if definition is set, 'title' property must be a non-empty string.");
		return NO;
	}

	// get category with default
	if (JS_GetProperty(context, params, "category", &value) == JS_FALSE || JSVAL_IS_VOID(value))
	{
		category = [NSString stringWithString:DESC(@"interfaces-category-uncategorised")];
	}
	else
	{
		category = OOStringFromJSValue(context, value);
		if (category == nil || [category length] == 0) {
			category = [NSString stringWithString:DESC(@"interfaces-category-uncategorised")];
		}
	}

	// get and validate summary
	if (JS_GetProperty(context, params, "summary", &value) == JS_FALSE || JSVAL_IS_VOID(value))
	{
		OOJSReportBadArguments(context, @"Station", @"setInterface", MIN(argc, 1U), OOJS_ARGV, NULL, @"key [, definition]; if definition is set, it must have a 'summary' property.");
		return NO;
	}
	summary = OOStringFromJSValue(context, value);
	if (summary == nil || [summary length] == 0) 
	{
		OOJSReportBadArguments(context, @"Station", @"setInterface", MIN(argc, 1U), OOJS_ARGV, NULL, @"key [, definition]; if definition is set, 'summary' property must be a non-empty string.");
		return NO;
	}

	// get and validate callback
	if (JS_GetProperty(context, params, "callback", &callback) == JS_FALSE || JSVAL_IS_VOID(callback))
	{
		OOJSReportBadArguments(context, @"Station", @"setInterface", MIN(argc, 1U), OOJS_ARGV, NULL, @"key [, definition]; if definition is set, it must have a 'callback' property.");
		return NO;
	}
	if (!OOJSValueIsFunction(context,callback))
	{
		OOJSReportBadArguments(context, @"Station", @"setInterface", MIN(argc, 1U), OOJS_ARGV, NULL, @"key [, definition]; 'callback' property must be a function.");
		return NO;
	}

	OOJSInterfaceDefinition* definition = [[OOJSInterfaceDefinition alloc] init];
	[definition setTitle:title];
	[definition setCategory:category];
	[definition setSummary:summary];
	[definition setCallback:callback];

	// get callback 'this'
	if (JS_GetProperty(context, params, "cbThis", &value) == JS_TRUE && !JSVAL_IS_VOID(value))
	{
		JS_ValueToObject(context, value, &callbackThis);
		[definition setCallbackThis:callbackThis];
		// can do .bind(this) for callback instead
	}
	
	[station setInterfaceDefinition:definition forKey:key];

	[definition release];

	OOJS_RETURN_VOID;

	OOJS_NATIVE_EXIT
}


static JSBool StationSetMarketPrice(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)

	StationEntity *station = nil;
	if (!JSStationGetStationEntity(context, OOJS_THIS, &station))  OOJS_RETURN_VOID; // stale reference, no-op

	if (argc < 2)
	{
		OOJSReportBadArguments(context, @"Station", @"setMarketPrice", MIN(argc, 2U), OOJS_ARGV, NULL, @"commodity, credits");
		return NO;
	}
	
	OOCommodityType commodity = OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (EXPECT_NOT(![[UNIVERSE commodities] goodDefined:commodity]))
	{
		OOJSReportBadArguments(context, @"Station", @"setMarketPrice", MIN(argc, 2U), OOJS_ARGV, NULL, @"Unrecognised commodity type");
		return NO;
	}

	int32 price;
	BOOL gotPrice = JS_ValueToInt32(context, OOJS_ARGV[1], &price);
	if (EXPECT_NOT(!gotPrice || price < 0))
	{
		OOJSReportBadArguments(context, @"Station", @"setMarketPrice", MIN(argc, 2U), OOJS_ARGV, NULL, @"Price must be at least 0 decicredits");
		return NO;
	}

	[station setPrice:(NSUInteger)price forCommodity:commodity];

	if (station == [PLAYER dockedStation] && [PLAYER guiScreen] == GUI_SCREEN_MARKET)
	{
		[PLAYER setGuiToMarketScreen]; // refresh screen
	}

	OOJS_RETURN_BOOL(YES);

	OOJS_NATIVE_EXIT
}


static JSBool StationSetMarketQuantity(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)

	StationEntity *station = nil;
	if (!JSStationGetStationEntity(context, OOJS_THIS, &station))  OOJS_RETURN_VOID; // stale reference, no-op

	if (argc < 2)
	{
		OOJSReportBadArguments(context, @"Station", @"setMarketQuantity", MIN(argc, 2U), OOJS_ARGV, NULL, @"commodity, units");
		return NO;
	}
	
	OOCommodityType commodity = OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (EXPECT_NOT(![[UNIVERSE commodities] goodDefined:commodity]))
	{
		OOJSReportBadArguments(context, @"Station", @"setMarketQuantity", MIN(argc, 2U), OOJS_ARGV, NULL, @"Unrecognised commodity type");
		return NO;
	}

	int32 quantity;
	BOOL gotQuantity = JS_ValueToInt32(context, OOJS_ARGV[1], &quantity);
	if (EXPECT_NOT(!gotQuantity || quantity < 0 || (OOCargoQuantity)quantity > [[station localMarket] capacityForGood:commodity]))
	{
		OOJSReportBadArguments(context, @"Station", @"setMarketQuantity", MIN(argc, 2U), OOJS_ARGV, NULL, @"Quantity must be between 0 and the station market capacity");
		return NO;
	}

	[station setQuantity:(OOCargoQuantity)quantity forCommodity:commodity];
	
	if (station == [PLAYER dockedStation] && [PLAYER guiScreen] == GUI_SCREEN_MARKET)
	{
		[PLAYER setGuiToMarketScreen]; // refresh screen
	}

	OOJS_RETURN_BOOL(YES);

	OOJS_NATIVE_EXIT
}

static JSBool StationResetMarket(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)

	StationEntity *station = nil;
	if (!JSStationGetStationEntity(context, OOJS_THIS, &station))  OOJS_RETURN_BOOL(NO); // stale reference, no-op
	OOJS_RETURN_BOOL([ station resetLocalMarket ]);

	OOJS_NATIVE_EXIT
}

static JSBool StationAddShipToShipyard(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)

	JSObject *params = NULL;
	StationEntity *station = nil;
	if (!JSStationGetStationEntity(context, OOJS_THIS, &station))  OOJS_RETURN_VOID; // stale reference, no-op

	if (argc != 1 || (!JSVAL_IS_NULL(OOJS_ARGV[0]) && !JS_ValueToObject(context, OOJS_ARGV[0], &params)))
	{
		OOJSReportBadArguments(context, @"Station", @"addShipToShipyard", MIN(argc, 1U), OOJS_ARGV, NULL, @"shipyard item definition");
		return NO;
	}

	// make sure the station has a shipyard
	if (![station hasShipyard]) {
		OOJSReportWarningForCaller(context, @"Station", @"removeShipFromShipyard", @"Station does not have shipyard.");
		return NO;
	}
	// make sure the shipyard has been generated
	if (![station localShipyard]) [station generateShipyard];
	NSMutableArray *shipyard = [station localShipyard];

	if (JSVAL_IS_NULL(OOJS_ARGV[0]))  OOJS_RETURN_VOID;	// OK, do nothing for null ship.

	NSMutableDictionary *result = [NSMutableDictionary dictionary];
	NSDictionary *shipyardDefinition = OOJSNativeObjectFromJSObject(context, JSVAL_TO_OBJECT(OOJS_ARGV[0]));
	// validate each element of the dictionary
	if (!shipyardDefinition) 
	{
		OOJSReportBadArguments(context, @"Station", @"addShipToShipyard", MIN(argc, 1U), OOJS_ARGV, nil, @"valid dictionary object");
		return NO;
	}
	if (![shipyardDefinition objectForKey:KEY_SHORT_DESCRIPTION]) 
	{
		OOJSReportBadArguments(context, @"Station", @"addShipToShipyard", MIN(argc, 1U), OOJS_ARGV, nil, @"'short_description' in dictionary");
		return NO;
	}
	[result setObject:[shipyardDefinition oo_stringForKey:@"short_description"] forKey:KEY_SHORT_DESCRIPTION];
	if (![shipyardDefinition objectForKey:SHIPYARD_KEY_SHIPDATA_KEY]) 
	{
		OOJSReportBadArguments(context, @"Station", @"addShipToShipyard", MIN(argc, 1U), OOJS_ARGV, nil, @"'shipdata_key' in dictionary");
		return NO;
	}
	// get the shipInfo and shipyardInfo for this key
	NSString 			*shipKey = [shipyardDefinition oo_stringForKey:SHIPYARD_KEY_SHIPDATA_KEY defaultValue:nil];
	OOShipRegistry		*registry = [OOShipRegistry sharedRegistry];
	NSMutableDictionary	*shipInfo = [NSMutableDictionary dictionaryWithDictionary:[registry shipInfoForKey:shipKey]];
	NSDictionary		*shipyardInfo = [registry shipyardInfoForKey:shipKey];
	if (!shipInfo) 
	{
		OOJSReportWarningForCaller(context, @"Station", @"addShipToShipyard", @"Invalid shipdata_key provided.");
		return NO;
	}
	// make sure the ship is a player ship
	if ([[shipInfo oo_stringForKey:@"roles"] rangeOfString:@"player"].location == NSNotFound)
	{
		OOJSReportWarningForCaller(context, @"Station", @"addShipToShipyard", @"shipdata_key not suitable for player role.");
		return NO;
	}
	if (!shipyardInfo) 
	{
		OOJSReportWarningForCaller(context, @"Station", @"addShipToShipyard", @"No shipyard information found for shipdata_key.");
		return NO;
	}
	// ok, feel pretty safe to include this ship now
	[result setObject:shipKey forKey:SHIPYARD_KEY_SHIPDATA_KEY];

	// add an ID
	Random_Seed ship_seed = [UNIVERSE marketSeed];
	int superRand1 = ship_seed.a * 0x10000 + ship_seed.c * 0x100 + ship_seed.e;
	uint32_t superRand2 = ship_seed.b * 0x10000 + ship_seed.d * 0x100 + ship_seed.f;
	superRand2 &= Ranrot();
	NSString *shipID = [NSString stringWithFormat:@"%06x-%06x", superRand1, superRand2];
	[result setObject:shipID forKey:SHIPYARD_KEY_ID];

	if (![shipyardDefinition objectForKey:SHIPYARD_KEY_PRICE]) 
	{
		// if not provided, get the price from the registry
		OOCreditsQuantity price = [shipyardInfo oo_unsignedIntForKey:KEY_PRICE];
		[result setObject:[NSNumber numberWithUnsignedLongLong:price] forKey:SHIPYARD_KEY_PRICE];
	}
	else 
	{
		OOCreditsQuantity price = [shipyardDefinition oo_unsignedIntForKey:SHIPYARD_KEY_PRICE];
		if (price > 0)
		{
			[result setObject:[NSNumber numberWithUnsignedLongLong:price] forKey:SHIPYARD_KEY_PRICE];
		}
		else
		{
			OOJSReportBadArguments(context, @"Station", @"addShipToShipyard", MIN(argc, 1U), OOJS_ARGV, nil, @"'price' in dictionary");
			return NO;
		}
	}

	if (![shipyardDefinition objectForKey:SHIPYARD_KEY_PERSONALITY]) 
	{
		// default to 0 if not supplied
		[result setObject:0 forKey:SHIPYARD_KEY_PERSONALITY];
	} 
	else
	{
		[result setObject:[NSNumber numberWithUnsignedLongLong:[shipyardDefinition oo_unsignedIntForKey:SHIPYARD_KEY_PERSONALITY]] forKey:SHIPYARD_KEY_PERSONALITY];
	}

	NSArray	*extras = [shipyardDefinition oo_arrayForKey:KEY_EQUIPMENT_EXTRAS];
	if (!extras) 
	{
		// pick up defaults if extras not supplied
		extras = [NSArray arrayWithArray:[[shipyardInfo oo_dictionaryForKey:KEY_STANDARD_EQUIPMENT] oo_arrayForKey:KEY_EQUIPMENT_EXTRAS]];
	}
	if ([extras count] > 0) {
		// go looking for lasers and add them directly to our shipInfo
		NSString* fwdWeaponString = [[shipyardInfo oo_dictionaryForKey:KEY_STANDARD_EQUIPMENT] oo_stringForKey:KEY_EQUIPMENT_FORWARD_WEAPON];
		NSString* aftWeaponString = [[shipyardInfo oo_dictionaryForKey:KEY_STANDARD_EQUIPMENT] oo_stringForKey:KEY_EQUIPMENT_AFT_WEAPON];
		OOWeaponFacingSet availableFacings = [shipyardInfo oo_unsignedIntForKey:KEY_WEAPON_FACINGS defaultValue:VALID_WEAPON_FACINGS] & VALID_WEAPON_FACINGS;

		OOWeaponType fwdWeapon = OOWeaponTypeFromEquipmentIdentifierSloppy(fwdWeaponString);
		OOWeaponType aftWeapon = OOWeaponTypeFromEquipmentIdentifierSloppy(aftWeaponString);

		unsigned int i;
		NSString *equipmentKey = nil;
		for (i = 0; i < [extras count]; i++) {
			equipmentKey = [extras oo_stringAtIndex:i];
			if ([equipmentKey hasPrefix:@"EQ_WEAPON"])
			{
				OOWeaponType new_weapon = OOWeaponTypeFromEquipmentIdentifierSloppy(equipmentKey);
				//fit best weapon forward
				if (availableFacings & WEAPON_FACING_FORWARD && [new_weapon weaponThreatAssessment] > [fwdWeapon weaponThreatAssessment])
				{
					//again remember to divide price by 10 to get credits from tenths of credit
					fwdWeaponString = equipmentKey;
					fwdWeapon = new_weapon;
					[shipInfo setObject:fwdWeaponString forKey:KEY_EQUIPMENT_FORWARD_WEAPON];
				}
				else 
				{
					//if less good than current forward, try fitting is to rear
					if (availableFacings & WEAPON_FACING_AFT && (isWeaponNone(aftWeapon) || [new_weapon weaponThreatAssessment] > [aftWeapon weaponThreatAssessment]))
					{
						aftWeaponString = equipmentKey;
						aftWeapon = new_weapon;
						[shipInfo setObject:aftWeaponString forKey:KEY_EQUIPMENT_AFT_WEAPON];
					}
				}
			}
		}
	}
	// add the extras
	[result setObject:extras forKey:KEY_EQUIPMENT_EXTRAS];
	// add the ship spec
	[result setObject:shipInfo forKey:SHIPYARD_KEY_SHIP];
	// add it to the station's shipyard
	[shipyard addObject:result];

	// refresh the screen if the shipyard is currently being displayed
	if(station == [PLAYER dockedStation] && [PLAYER guiScreen] == GUI_SCREEN_SHIPYARD)
	{
		[PLAYER setGuiToShipyardScreen:0];
	}	

	OOJS_RETURN_BOOL(YES);

	OOJS_NATIVE_EXIT
}


static JSBool StationRemoveShipFromShipyard(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)

	StationEntity *station = nil;
	if (!JSStationGetStationEntity(context, OOJS_THIS, &station))  OOJS_RETURN_VOID; // stale reference, no-op

	// make sure the station has a shipyard
	if (![station hasShipyard]) {
		OOJSReportWarningForCaller(context, @"Station", @"removeShipFromShipyard", @"Station does not have shipyard.");
		return NO;
	}
	// make sure the shipyard has been generated
	if (![station localShipyard]) [station generateShipyard];
	NSMutableArray *shipyard = [station localShipyard];
	
	int32 shipIndex = -1;
	BOOL gotIndex = YES;
	gotIndex = JS_ValueToInt32(context, OOJS_ARGV[0], &shipIndex);

	if (argc != 1 || (!JSVAL_IS_NULL(OOJS_ARGV[0]) && !gotIndex) || shipIndex < 0 || (shipIndex + 1) > [shipyard count]) 
	{
		OOJSReportBadArguments(context, @"Station", @"removeShipFromShipyard", MIN(argc, 1U), OOJS_ARGV, NULL, @"valid ship index");
		return NO;
	}

	[shipyard removeObjectAtIndex:shipIndex];

	// refresh the screen if the shipyard is currently being displayed
	if(station == [PLAYER dockedStation] && [PLAYER guiScreen] == GUI_SCREEN_SHIPYARD)
	{
		[PLAYER setGuiToShipyardScreen:0];
	}

	OOJS_RETURN_BOOL(YES);

	OOJS_NATIVE_EXIT
}

