/*

OOJSPlanet.m


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

#import "OOJSPlanet.h"
#import "OOJSEntity.h"
#import "OOJavaScriptEngine.h"
#import "OOJSSun.h"

#import "PlanetEntity.h"


static JSObject		*sPlanetPrototype;

static BOOL JSPlanetGetPlanetEntity(JSContext *context, JSObject *PlanetObj, PlanetEntity **outEntity);


static JSBool PlanetGetProperty(JSContext *context, JSObject *this, jsval name, jsval *outValue);
static JSBool PlanetSetProperty(JSContext *context, JSObject *this, jsval name, jsval *value);

static JSBool PlanetSetTexture(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);


static JSExtendedClass sPlanetClass =
{
	{
		"Planet",
		JSCLASS_HAS_PRIVATE | JSCLASS_IS_EXTENDED,
		
		JS_PropertyStub,		// addProperty
		JS_PropertyStub,		// delProperty
		PlanetGetProperty,		// getProperty
		PlanetSetProperty,		// setProperty
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
	kPlanet_isMainPlanet,		// Is [UNIVERSE planet], boolean, read-only
	kPlanet_hasAtmosphere,
	kPlanet_radius,				// Radius of planet in metres.
};


static JSPropertySpec sPlanetProperties[] =
{
	// JS name					ID							flags
	{ "isMainPlanet",			kPlanet_isMainPlanet,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "hasAtmosphere",			kPlanet_hasAtmosphere,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "radius",					kPlanet_radius,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ 0 }
};


static JSFunctionSpec sPlanetMethods[] =
{
	// JS name					Function					min args
	{ "setTexture",				PlanetSetTexture,				1 },
	{ 0 }
};


void InitOOJSPlanet(JSContext *context, JSObject *global)
{
    sPlanetPrototype = JS_InitClass(context, global, JSEntityPrototype(), &sPlanetClass.base, NULL, 0, sPlanetProperties, sPlanetMethods, NULL, NULL);
	JSRegisterObjectConverter(&sPlanetClass.base, JSBasicPrivateObjectConverter);
}


static BOOL JSPlanetGetPlanetEntity(JSContext *context, JSObject *stationObj, PlanetEntity **outEntity)
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


@implementation PlanetEntity (OOJavaScriptExtensions)

- (void)getJSClass:(JSClass **)outClass andPrototype:(JSObject **)outPrototype
{
	if ([self planetType] == PLANET_TYPE_SUN)
	{
		OOSunGetClassAndPrototype(outClass, outPrototype);
	}
	else
	{
		*outClass = &sPlanetClass.base;
		*outPrototype = sPlanetPrototype;
	}
}


- (NSString *)jsClassName
{
	if ([self planetType] == PLANET_TYPE_SUN)
	{
		return @"Sun";
	}
	else
	{
		return @"Planet";
	}
}

@end


static JSBool PlanetGetProperty(JSContext *context, JSObject *this, jsval name, jsval *outValue)
{
	PlanetEntity				*planet = nil;
	
	if (!JSVAL_IS_INT(name))  return YES;
	if (!JSPlanetGetPlanetEntity(context, this, &planet)) return NO;
	
	switch (JSVAL_TO_INT(name))
	{
		case kPlanet_isMainPlanet:
			*outValue = BOOLToJSVal(planet == [UNIVERSE planet]);
			break;
			
		case kPlanet_radius:
			JS_NewDoubleValue(context, [planet radius], outValue);
			break;
			
		case kPlanet_hasAtmosphere:
			*outValue = BOOLToJSVal([planet hasAtmosphere]);
			break;
			
		default:
			OOReportJavaScriptBadPropertySelector(context, @"Planet", JSVAL_TO_INT(name));
			return NO;
	}
	return YES;
}


static JSBool PlanetSetProperty(JSContext *context, JSObject *this, jsval name, jsval *value)
{
	PlanetEntity				*entity = nil;
	
	if (!JSVAL_IS_INT(name))  return YES;
	if (!JSPlanetGetPlanetEntity(context, this, &entity)) return NO;
	
	switch (JSVAL_TO_INT(name))
	{
			
		default:
			OOReportJavaScriptBadPropertySelector(context, @"Planet", JSVAL_TO_INT(name));
			return NO;
	}
	
	return YES;
}


static JSBool PlanetSetTexture(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	PlanetEntity			*thisEnt = nil;
	NSString				*name = nil;
	PlayerEntity *player = [PlayerEntity sharedPlayer];

	
	if (!JSPlanetGetPlanetEntity(context, this, &thisEnt)) return YES;	// stale reference, no-op.
	name = [NSString stringWithJavaScriptValue:*argv inContext:context];
	if([player status] != STATUS_LAUNCHING && [player status] != STATUS_EXITING_WITCHSPACE)
	{
		OOReportJavaScriptError(context, @"Planet.%@ must be called only during shipWillLaunchFromStation or shipWillExitWitchspace.", @"setTexture");
		return YES;
	}
	if (name != nil)
	{
		if (![thisEnt setUpPlanetFromTexture:name])
		{
			OOReportJavaScriptError(context, @"Planet.%@(\"%@\"): cannot set texture for planet.", @"setTexture", name);
		}
	}
	else
	{
		OOReportJavaScriptError(context, @"Planet.%@(): no texture name specified.", @"setTexture");
	}
	return YES;
}
