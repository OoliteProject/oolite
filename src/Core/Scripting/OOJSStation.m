/*
OOJSStation.m

Oolite
Copyright (C) 2004-2012 Giles C Williams and contributors

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
#import "OOJavaScriptEngine.h"

#import "StationEntity.h"
#import "GameController.h"


static JSObject		*sStationPrototype;

static BOOL JSStationGetStationEntity(JSContext *context, JSObject *stationObj, StationEntity **outEntity);


static JSBool StationGetProperty(JSContext *context, JSObject *this, jsid propID, jsval *value);
static JSBool StationSetProperty(JSContext *context, JSObject *this, jsid propID, JSBool strict, jsval *value);

static JSBool StationDockPlayer(JSContext *context, uintN argc, jsval *vp);
static JSBool StationLaunchShipWithRole(JSContext *context, uintN argc, jsval *vp);
static JSBool StationLaunchDefenseShip(JSContext *context, uintN argc, jsval *vp);
static JSBool StationLaunchScavenger(JSContext *context, uintN argc, jsval *vp);
static JSBool StationLaunchMiner(JSContext *context, uintN argc, jsval *vp);
static JSBool StationLaunchPirateShip(JSContext *context, uintN argc, jsval *vp);
static JSBool StationLaunchShuttle(JSContext *context, uintN argc, jsval *vp);
static JSBool StationLaunchPatrol(JSContext *context, uintN argc, jsval *vp);
static JSBool StationLaunchPolice(JSContext *context, uintN argc, jsval *vp);


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
	kStation_dockedContractors, // miners and scavengers.
	kStation_dockedDefenders,
	kStation_dockedPolice,
	kStation_equipmentPriceFactor,
	kStation_equivalentTechLevel,
	kStation_hasNPCTraffic,
	kStation_hasShipyard,
	kStation_isMainStation,		// Is [UNIVERSE station], boolean, read-only
	kStation_requiresDockingClearance,
	kStation_allowsFastDocking,
	kStation_allowsAutoDocking,
	kStation_suppressArrivalReports,
};


static JSPropertySpec sStationProperties[] =
{
	// JS name						ID									flags
	{ "alertCondition",				kStation_alertCondition,			OOJS_PROP_READWRITE_CB },
	{ "allowsAutoDocking",			kStation_allowsAutoDocking,			OOJS_PROP_READWRITE_CB },
	{ "allowsFastDocking",			kStation_allowsFastDocking,			OOJS_PROP_READWRITE_CB },
	{ "dockedContractors",			kStation_dockedContractors,			OOJS_PROP_READONLY_CB },
	{ "dockedDefenders",			kStation_dockedDefenders,			OOJS_PROP_READONLY_CB },
	{ "dockedPolice",				kStation_dockedPolice,				OOJS_PROP_READONLY_CB },
	{ "equipmentPriceFactor",		kStation_equipmentPriceFactor,		OOJS_PROP_READONLY_CB },
	{ "equivalentTechLevel",		kStation_equivalentTechLevel,		OOJS_PROP_READONLY_CB },
	{ "hasNPCTraffic",				kStation_hasNPCTraffic,				OOJS_PROP_READWRITE_CB },
	{ "hasShipyard",				kStation_hasShipyard,				OOJS_PROP_READONLY_CB },
	{ "isMainStation",				kStation_isMainStation,				OOJS_PROP_READONLY_CB },
	{ "requiresDockingClearance",	kStation_requiresDockingClearance,	OOJS_PROP_READWRITE_CB },
	{ "suppressArrivalReports",		kStation_suppressArrivalReports,	OOJS_PROP_READWRITE_CB },
	{ 0 }
};


static JSFunctionSpec sStationMethods[] =
{
	// JS name					Function						min args
	{ "dockPlayer",				StationDockPlayer,				0 },
	{ "launchDefenseShip",		StationLaunchDefenseShip,		0 },
	{ "launchMiner",			StationLaunchMiner,				0 },
	{ "launchPatrol",			StationLaunchPatrol,			0 },
	{ "launchPirateShip",		StationLaunchPirateShip,		0 },
	{ "launchPolice",			StationLaunchPolice,			0 },
	{ "launchScavenger",		StationLaunchScavenger,			0 },
	{ "launchShipWithRole",		StationLaunchShipWithRole,		1 },
	{ "launchShuttle",			StationLaunchShuttle,			0 },
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
			
		case kStation_requiresDockingClearance:
			*value = OOJSValueFromBOOL([entity requiresDockingClearance]);
			return YES;
			
		case kStation_allowsFastDocking:
			*value = OOJSValueFromBOOL([entity allowsFastDocking]);
			return YES;
			
		case kStation_allowsAutoDocking:
			*value = OOJSValueFromBOOL([entity allowsAutoDocking]);
			return YES;

		case kStation_dockedContractors:
			*value = INT_TO_JSVAL([entity dockedContractors]);
			return YES;
			
		case kStation_dockedPolice:
			*value = INT_TO_JSVAL([entity dockedPolice]);
			return YES;
			
		case kStation_dockedDefenders:
			*value = INT_TO_JSVAL([entity dockedDefenders]);
			return YES;
			
		case kStation_equivalentTechLevel:
			*value = INT_TO_JSVAL([entity equivalentTechLevel]);
			return YES;
			
		case kStation_equipmentPriceFactor:
			return JS_NewNumberValue(context, [entity equipmentPriceFactor], value);
			
		case kStation_suppressArrivalReports:
			*value = OOJSValueFromBOOL([entity suppressArrivalReports]);
			return YES;
			
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
			
		case kStation_requiresDockingClearance:
			if (JS_ValueToBoolean(context, *value, &bValue))
			{
				[entity setRequiresDockingClearance:bValue];
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
		
		default:
			OOJSReportBadPropertySelector(context, this, propID, sStationProperties);
			return NO;
	}
	
	OOJSReportBadPropertyValue(context, this, propID, sStationProperties, *value);
	return NO;
	
	OOJS_NATIVE_EXIT
}


// *** Methods ***

// dockPlayer()
// Proposed and written by Frame 20090729
static JSBool StationDockPlayer(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	PlayerEntity	*player = OOPlayerForScripting();
	
	if (EXPECT_NOT([UNIVERSE isGamePaused]))
	{
		/*	Station.dockPlayer() was executed while the game was in pause.
			Do we want to return an error or just unpause and continue?
			I think unpausing is the sensible thing to do here - Nikos 20110208
		*/
		[[[UNIVERSE gameView] gameController] unpauseGame];
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
	
	result = [station launchIndependentShip:shipRole];
	if (abortAllDockings) [station abortAllDockings];
	
	OOJS_RETURN_OBJECT(result);
	OOJS_NATIVE_EXIT
}


static JSBool StationLaunchDefenseShip(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	StationEntity *station = nil;
	if (!JSStationGetStationEntity(context, OOJS_THIS, &station))  OOJS_RETURN_VOID; // stale reference, no-op
	
	OOJS_RETURN_OBJECT([station launchDefenseShip]);
	OOJS_NATIVE_EXIT
}


static JSBool StationLaunchScavenger(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	StationEntity *station = nil;
	if (!JSStationGetStationEntity(context, OOJS_THIS, &station))  OOJS_RETURN_VOID; // stale reference, no-op
	
	OOJS_RETURN_OBJECT([station launchScavenger]);
	OOJS_NATIVE_EXIT
}


static JSBool StationLaunchMiner(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	StationEntity *station = nil;
	if (!JSStationGetStationEntity(context, OOJS_THIS, &station))  OOJS_RETURN_VOID; // stale reference, no-op
	
	OOJS_RETURN_OBJECT([station launchMiner]);
	OOJS_NATIVE_EXIT
}


static JSBool StationLaunchPirateShip(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	StationEntity *station = nil;
	if (!JSStationGetStationEntity(context, OOJS_THIS, &station))  OOJS_RETURN_VOID; // stale reference, no-op
	
	OOJS_RETURN_OBJECT([station launchPirateShip]);
	OOJS_NATIVE_EXIT
}


static JSBool StationLaunchShuttle(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	StationEntity *station = nil;
	if (!JSStationGetStationEntity(context, OOJS_THIS, &station))  OOJS_RETURN_VOID; // stale reference, no-op
	
	OOJS_RETURN_OBJECT([station launchShuttle]);
	OOJS_NATIVE_EXIT
}


static JSBool StationLaunchPatrol(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	StationEntity *station = nil;
	if (!JSStationGetStationEntity(context, OOJS_THIS, &station))  OOJS_RETURN_VOID; // stale reference, no-op
	
	OOJS_RETURN_OBJECT([station launchPatrol]);
	OOJS_NATIVE_EXIT
}


static JSBool StationLaunchPolice(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	StationEntity *station = nil;
	if (!JSStationGetStationEntity(context, OOJS_THIS, &station))  OOJS_RETURN_VOID; // stale reference, no-op
	
	OOJS_RETURN_OBJECT([station launchPolice]);
	OOJS_NATIVE_EXIT
}
