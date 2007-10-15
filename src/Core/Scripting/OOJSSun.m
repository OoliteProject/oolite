/*

OOJSSun.m


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

#import "OOJSSun.h"
#import "OOJSEntity.h"
#import "OOJavaScriptEngine.h"

#import "PlanetEntity.h"


static JSObject		*sSunPrototype;

static BOOL JSSunGetPlanetEntity(JSContext *context, JSObject *SunObj, PlanetEntity **outEntity);


static JSBool SunGetProperty(JSContext *context, JSObject *this, jsval name, jsval *outValue);


static JSExtendedClass sSunClass =
{
	{
		"Sun",
		JSCLASS_HAS_PRIVATE | JSCLASS_IS_EXTENDED,
		
		JS_PropertyStub,		// addProperty
		JS_PropertyStub,		// delProperty
		SunGetProperty,			// getProperty
		JS_PropertyStub,		// setProperty
		JS_EnumerateStub,		// enumerate
		JS_ResolveStub,			// resolve
		JS_ConvertStub,			// convert
		JSObjectWrapperFinalize,// finalize
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
	kSun_radius,				// Radius of sun in metres.
};


static JSPropertySpec sSunProperties[] =
{
	// JS name					ID							flags
	{ "radius",					kSun_radius,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ 0 }
};


static JSFunctionSpec sSunMethods[] =
{
	// JS name					Function					min args
	{ 0 }
};


void InitOOJSSun(JSContext *context, JSObject *global)
{
    sSunPrototype = JS_InitClass(context, global, JSEntityPrototype(), &sSunClass.base, NULL, 0, sSunProperties, sSunMethods, NULL, NULL);
	JSRegisterObjectConverter(&sSunClass.base, JSBasicPrivateObjectConverter);
}


void OOSunGetClassAndPrototype(JSClass **outClass, JSObject **outPrototype)
{
	*outClass = &sSunClass.base;
	*outPrototype = sSunPrototype;
}


static BOOL JSSunGetPlanetEntity(JSContext *context, JSObject *stationObj, PlanetEntity **outEntity)
{
	BOOL						result;
	Entity						*entity = nil;
	
	if (outEntity != NULL)  *outEntity = nil;
	
	result = JSEntityGetEntity(context, stationObj, &entity);
	if (!result)  return NO;
	
	if (![entity isKindOfClass:[PlanetEntity class]])  return NO;
	
	*outEntity = (PlanetEntity *)entity;
	return YES;
}


static JSBool SunGetProperty(JSContext *context, JSObject *this, jsval name, jsval *outValue)
{
	PlanetEntity				*sun = nil;
	
	if (!JSVAL_IS_INT(name))  return YES;
	if (!JSSunGetPlanetEntity(context, this, &sun)) return NO;
	
	switch (JSVAL_TO_INT(name))
	{
			
		case kSun_radius:
			JS_NewDoubleValue(context, [sun radius], outValue);
			break;
			
		default:
			OOReportJavaScriptBadPropertySelector(context, @"Sun", JSVAL_TO_INT(name));
			return NO;
	}
	return YES;
}
