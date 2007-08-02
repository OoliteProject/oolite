/*
OOJSStation.m

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

#import "OOJSStation.h"
#import "OOJSEntity.h"
#import "OOJSShip.h"
#import "OOJavaScriptEngine.h"

#import "StationEntity.h"


static JSObject		*sStationPrototype;
static JSObject		*sStationObject;


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
		JS_FinalizeStub,		// finalize
		JSCLASS_NO_OPTIONAL_MEMBERS
	},
	NULL,						// equality
	NULL,						// outerObject
	NULL,						// innerObject
	JSCLASS_NO_RESERVED_MEMBERS
};


enum
{
	// Property IDs
	kStation_isMain				// Is [UNIVERSE station], boolean, read-only
};


static JSPropertySpec sStationProperties[] =
{
	// JS name					ID							flags
	{ "isMain",					kStation_isMain,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
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
	JSEntityRegisterEntitySubclass(&sStationClass.base);
}


BOOL JSStationGetStationEntity(JSContext *context, JSObject *stationObj, StationEntity **outEntity)
{
	BOOL						result;
	Entity						*entity = nil;
	
	if (outEntity != NULL)  *outEntity = nil;
	
	result = JSEntityGetEntity(context, stationObj, &entity);
	if (!result)  return NO;
	
	if (![entity isKindOfClass:[StationEntity class]])  return NO;
	
	*outEntity = (StationEntity *)entity;
	return YES;
}


JSClass *JSStationClass(void)
{
	return &sStationClass.base;
}


JSObject *JSStationPrototype(void)
{
	return sStationPrototype;
}


JSObject *JSStationObject(void)
{
	return sStationObject;
}


static JSBool StationGetProperty(JSContext *context, JSObject *this, jsval name, jsval *outValue)
{
	StationEntity				*entity = nil;
	
	if (!JSVAL_IS_INT(name))  return YES;
	if (!JSStationGetStationEntity(context, this, &entity)) return NO;
	
	switch (JSVAL_TO_INT(name))
	{
		case kStation_isMain:
			*outValue = BOOLToJSVal(entity == [UNIVERSE station]);
			break;
		
		default:
			OOReportJavaScriptBadPropertySelector(context, @"Station", JSVAL_TO_INT(name));
			return NO;
	}
	return YES;
}


static JSBool StationSetProperty(JSContext *context, JSObject *this, jsval name, jsval *value)
{
	return YES;
}
