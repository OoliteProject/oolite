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
#import "OOJavaScriptEngine.h"

#import "StationEntity.h"


static JSObject		*sStationPrototype;

static BOOL JSStationGetStationEntity(JSContext *context, JSObject *stationObj, StationEntity **outEntity);


static JSBool StationGetProperty(JSContext *context, JSObject *this, jsval name, jsval *outValue);
static JSBool StationSetProperty(JSContext *context, JSObject *this, jsval name, jsval *value);


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
};


static JSPropertySpec sStationProperties[] =
{
	// JS name					ID							flags
	{ "isMainStation",			kStation_isMainStation,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "hasNPCTraffic",			kStation_hasNPCTraffic,		JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "alertCondition",			kStation_alertCondition,	JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ 0 }
};


static JSFunctionSpec sStationMethods[] =
{
	// JS name					Function					min args
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
		
		default:
			OOReportJSBadPropertySelector(context, @"Station", JSVAL_TO_INT(name));
	}
	
	return OK;
}
