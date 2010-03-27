/*
OOJSStation.m

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

#import "OOJSStation.h"
#import "OOJSEntity.h"
#import "OOJSShip.h"
#import "OOJSPlayer.h"
#import "OOJavaScriptEngine.h"

#import "StationEntity.h"


static JSObject		*sStationPrototype;

static BOOL JSStationGetStationEntity(JSContext *context, JSObject *stationObj, StationEntity **outEntity);


static JSBool StationGetProperty(JSContext *context, JSObject *this, jsval name, jsval *outValue);
static JSBool StationSetProperty(JSContext *context, JSObject *this, jsval name, jsval *value);

static JSBool StationDockPlayer(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool StationLaunchShipWithRole(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool StationLaunchDefenseShip(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool StationLaunchScavenger(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool StationLaunchMiner(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool StationLaunchPirateShip(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool StationLaunchShuttle(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool StationLaunchPatrol(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool StationLaunchPolice(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);


static JSExtendedClass sStationClass =
{
	{
		"Station",
		JSCLASS_HAS_PRIVATE | JSCLASS_IS_EXTENDED,
		
		JS_PropertyStub,		// addProperty
		JS_PropertyStub,		// delProperty
		StationGetProperty,		// getProperty
		StationSetProperty,		// setProperty
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
	kStation_isMainStation,		// Is [UNIVERSE station], boolean, read-only
	kStation_hasNPCTraffic,
	kStation_alertCondition,
#if DOCKING_CLEARANCE_ENABLED
	kStation_requiresDockingClearance,
#endif
	kStation_dockedContractors, // miners and scavengers.
	kStation_dockedPolice,
	kStation_dockedDefenders,
	kStation_equivalentTechLevel,
	kStation_equipmentPriceFactor,
	kStation_suppressArrivalReports,
};


static JSPropertySpec sStationProperties[] =
{
	// JS name					ID							flags
	{ "isMainStation",			kStation_isMainStation,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "hasNPCTraffic",			kStation_hasNPCTraffic,		JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "alertCondition",			kStation_alertCondition,	JSPROP_PERMANENT | JSPROP_ENUMERATE },
#if DOCKING_CLEARANCE_ENABLED
	{ "requiresDockingClearance",	kStation_requiresDockingClearance,	JSPROP_PERMANENT | JSPROP_ENUMERATE },
#endif
	{ "dockedContractors",		kStation_dockedContractors,	JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "dockedPolice",			kStation_dockedPolice,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "dockedDefenders",		kStation_dockedDefenders,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "equivalentTechLevel",	kStation_equivalentTechLevel,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "equipmentPriceFactor",	kStation_equipmentPriceFactor,	JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "suppressArrivalReports",	kStation_suppressArrivalReports,	JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ 0 }
};


static JSFunctionSpec sStationMethods[] =
{
	// JS name					Function						min args
	{ "dockPlayer",				StationDockPlayer,				0 },
	{ "launchShipWithRole",		StationLaunchShipWithRole,		1 },
	{ "launchDefenseShip",		StationLaunchDefenseShip,		0 },
	{ "launchScavenger",		StationLaunchScavenger,			0 },
	{ "launchMiner",			StationLaunchMiner,				0 },
	{ "launchPirateShip",		StationLaunchPirateShip,		0 },
	{ "launchShuttle",			StationLaunchShuttle,			0 },
	{ "launchPatrol",			StationLaunchPatrol,			0 },
	{ "launchPolice",			StationLaunchPolice,			0 },
	{ 0 }
};


void InitOOJSStation(JSContext *context, JSObject *global)
{
	sStationPrototype = JS_InitClass(context, global, JSShipPrototype(), &sStationClass.base, NULL, 0, sStationProperties, sStationMethods, NULL, NULL);
	JSRegisterObjectConverter(&sStationClass.base, JSBasicPrivateObjectConverter);
}


static BOOL JSStationGetStationEntity(JSContext *context, JSObject *stationObj, StationEntity **outEntity)
{
	BOOL						result;
	Entity						*entity = nil;
	
	if (outEntity == NULL)  return NO;
	*outEntity = nil;
	
	result = JSEntityGetEntity(context, stationObj, &entity);
	if (!result)  return NO;
	
	if (![entity isKindOfClass:[StationEntity class]])  return NO;
	
	*outEntity = (StationEntity *)entity;
	return YES;
}


@implementation StationEntity (OOJavaScriptExtensions)

- (void)getJSClass:(JSClass **)outClass andPrototype:(JSObject **)outPrototype
{
	*outClass = &sStationClass.base;
	*outPrototype = sStationPrototype;
}


- (NSString *)jsClassName
{
	return @"Station";
}

@end


static JSBool StationGetProperty(JSContext *context, JSObject *this, jsval name, jsval *outValue)
{
	StationEntity				*entity = nil;
	
	if (!JSVAL_IS_INT(name))  return YES;
	if (!JSStationGetStationEntity(context, this, &entity)) return NO;
	
	switch (JSVAL_TO_INT(name))
	{
		case kStation_isMainStation:
			*outValue = BOOLToJSVal(entity == [UNIVERSE station]);
			break;
		
		case kStation_hasNPCTraffic:
			*outValue = BOOLToJSVal([entity hasNPCTraffic]);
			break;
		
		case kStation_alertCondition:
			*outValue = INT_TO_JSVAL([entity alertLevel]);
			break;
			
#if DOCKING_CLEARANCE_ENABLED
		case kStation_requiresDockingClearance:
			*outValue = BOOLToJSVal([entity requiresDockingClearance]);
			break;
#endif
			
		case kStation_dockedContractors:
			*outValue = INT_TO_JSVAL([entity dockedContractors]);
			break;
			
		case kStation_dockedPolice:
			*outValue = INT_TO_JSVAL([entity dockedPolice]);
			break;
			
		case kStation_dockedDefenders:
			*outValue = INT_TO_JSVAL([entity dockedDefenders]);
			break;
			
		case kStation_equivalentTechLevel:
			*outValue = INT_TO_JSVAL([entity equivalentTechLevel]);
			break;
			
		case kStation_equipmentPriceFactor:
			JS_NewDoubleValue(context, [entity equipmentPriceFactor], outValue);
			break;
			
		case kStation_suppressArrivalReports:
			*outValue = BOOLToJSVal([entity suppressArrivalReports]);
			break;
			
		default:
			OOReportJSBadPropertySelector(context, @"Station", JSVAL_TO_INT(name));
			return NO;
	}
	return YES;
}


static JSBool StationSetProperty(JSContext *context, JSObject *this, jsval name, jsval *value)
{
	BOOL						OK = NO;
	StationEntity				*entity = nil;
	JSBool						bValue;
	int32						iValue;
	
	
	if (!JSVAL_IS_INT(name))  return YES;
	if (!JSStationGetStationEntity(context, this, &entity)) return NO;
	
	switch (JSVAL_TO_INT(name))
	{
		case kStation_hasNPCTraffic:
			if (JS_ValueToBoolean(context, *value, &bValue))
			{
				[entity setHasNPCTraffic:bValue];
				OK = YES;
			}
			break;
		
		case kStation_alertCondition:
			if (JS_ValueToInt32(context, *value, &iValue))
			{
				[entity setAlertLevel:iValue signallingScript:NO];	// Performs range checking
				OK = YES;
			}
			break;
			
#if DOCKING_CLEARANCE_ENABLED
		case kStation_requiresDockingClearance:
			if (JS_ValueToBoolean(context, *value, &bValue))
			{
				[entity setRequiresDockingClearance:bValue];
				OK = YES;
			}
			break;
#endif

		case kStation_suppressArrivalReports:
			if (JS_ValueToBoolean(context, *value, &bValue))
			{
				[entity setSuppressArrivalReports:bValue];
				OK = YES;
			}
			break;
		
		default:
			OOReportJSBadPropertySelector(context, @"Station", JSVAL_TO_INT(name));
	}
	
	return OK;
}


// *** Methods ***

// dockPlayer()
// Proposed and written by Frame 20090729
static JSBool StationDockPlayer(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	PlayerEntity	*player = OOPlayerForScripting();
	
	if ([player isDocked])
	{
		return YES; //fail silently
	}
	
	StationEntity *stationForDockingPlayer = nil;
	JSStationGetStationEntity(context, this, &stationForDockingPlayer); 
	
#if DOCKING_CLEARANCE_ENABLED
	[player setDockingClearanceStatus:DOCKING_CLEARANCE_STATUS_GRANTED];
#endif

	[player safeAllMissiles];
	[UNIVERSE setViewDirection:VIEW_FORWARD];
	[player enterDock:stationForDockingPlayer];
	return YES;
}


// launchShipWithRole(role : String [, abortAllDockings : boolean]) : shipEntity
static JSBool StationLaunchShipWithRole(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	StationEntity *station = nil;
	ShipEntity	*result = nil;
	JSBool		abortAllDockings = NO;
	
	if (!JSStationGetStationEntity(context, this, &station))  return YES; // stale reference, no-op
	
	if (argc > 1)  JS_ValueToBoolean(context, argv[1], &abortAllDockings);
	
	NSString *shipRole = JSValToNSString(context, argv[0]);
	if (EXPECT_NOT(shipRole == nil))
	{
		OOReportJSBadArguments(context, @"Station", @"launchShipWithRole", argc, argv, nil, @"shipRole");
		return NO;
	}
	
	result = [station launchIndependentShip:shipRole];
	if (abortAllDockings) [station abortAllDockings];
	*outResult = [result javaScriptValueInContext:context];
	
	return YES;
}


static JSBool StationLaunchDefenseShip(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	StationEntity *station = nil;
	ShipEntity	*result = nil;
	if (!JSStationGetStationEntity(context, this, &station))  return YES; // stale reference, no-op
		
	result = [station launchDefenseShip];
	*outResult = [result javaScriptValueInContext:context];
	
	return YES;
}


static JSBool StationLaunchScavenger(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	StationEntity *station = nil;
	ShipEntity	*result = nil;
	if (!JSStationGetStationEntity(context, this, &station))  return YES; // stale reference, no-op
	
	result = [station launchScavenger];
	*outResult = [result javaScriptValueInContext:context];
	
	return YES;
}


static JSBool StationLaunchMiner(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	StationEntity *station = nil;
	ShipEntity	*result = nil;
	if (!JSStationGetStationEntity(context, this, &station))  return YES; // stale reference, no-op
	
	result = [station launchMiner];
	*outResult = [result javaScriptValueInContext:context];
	
	return YES;
}


static JSBool StationLaunchPirateShip(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	StationEntity *station = nil;
	ShipEntity	*result = nil;
	if (!JSStationGetStationEntity(context, this, &station))  return YES; // stale reference, no-op
	
	result = [station launchPirateShip];
	*outResult = [result javaScriptValueInContext:context];
	
	return YES;
}


static JSBool StationLaunchShuttle(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	StationEntity *station = nil;
	ShipEntity	*result = nil;
	if (!JSStationGetStationEntity(context, this, &station))  return YES; // stale reference, no-op
	
	result = [station launchShuttle];
	*outResult = [result javaScriptValueInContext:context];
	
	return YES;
}


static JSBool StationLaunchPatrol(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	StationEntity *station = nil;
	ShipEntity	*result = nil;
	if (!JSStationGetStationEntity(context, this, &station))  return YES; // stale reference, no-op
	
	result = [station launchPatrol];
	*outResult = [result javaScriptValueInContext:context];
	
	return YES;
}


static JSBool StationLaunchPolice(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	StationEntity *station = nil;
	NSArray	*result = nil;
	if (!JSStationGetStationEntity(context, this, &station))  return YES; // stale reference, no-op
	
	result = [station launchPolice];
	*outResult = [result javaScriptValueInContext:context];
	
	return YES;
}
