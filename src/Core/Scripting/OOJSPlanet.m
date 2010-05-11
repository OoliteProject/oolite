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
#import "OOJSQuaternion.h"

#import "OOPlanetEntity.h"


DEFINE_JS_OBJECT_GETTER(JSPlanetGetPlanetEntity, OOPlanetEntity)


static JSObject		*sPlanetPrototype;


static JSBool PlanetGetProperty(JSContext *context, JSObject *this, jsval name, jsval *outValue);
static JSBool PlanetSetProperty(JSContext *context, JSObject *this, jsval name, jsval *value);


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
	kPlanet_radius,				// Radius of planet in metres, read-only
	kPlanet_texture,			// Planet texture read / write
	kPlanet_orientation,		// orientation, quaternion, read/write
};


static JSPropertySpec sPlanetProperties[] =
{
	// JS name					ID							flags
	{ "isMainPlanet",			kPlanet_isMainPlanet,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "hasAtmosphere",			kPlanet_hasAtmosphere,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "radius",					kPlanet_radius,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "texture",				kPlanet_texture,			JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "orientation",			kPlanet_orientation,		JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ 0 }
};


void InitOOJSPlanet(JSContext *context, JSObject *global)
{
	sPlanetPrototype = JS_InitClass(context, global, JSEntityPrototype(), &sPlanetClass.base, NULL, 0, sPlanetProperties, NULL, NULL, NULL);
	JSRegisterObjectConverter(&sPlanetClass.base, JSBasicPrivateObjectConverter);
}


@implementation OOPlanetEntity (OOJavaScriptExtensions)

- (BOOL) isVisibleToScripts
{
	return YES;
}


- (void)getJSClass:(JSClass **)outClass andPrototype:(JSObject **)outPrototype
{
	*outClass = &sPlanetClass.base;
	*outPrototype = sPlanetPrototype;
}


- (NSString *)jsClassName
{
	switch ([self planetType])
	{
		case STELLAR_TYPE_NORMAL_PLANET:
			return @"Planet";
		case STELLAR_TYPE_MOON:
			return @"Moon";
		default:
			return @"Unknown";
	}
}

@end


static JSBool PlanetGetProperty(JSContext *context, JSObject *this, jsval name, jsval *outValue)
{
	BOOL						OK = NO;
	OOPlanetEntity				*planet = nil;
	
	if (!JSVAL_IS_INT(name))  return YES;
	if (!JSPlanetGetPlanetEntity(context, this, &planet)) return NO;
	
	switch (JSVAL_TO_INT(name))
	{
		case kPlanet_isMainPlanet:
			*outValue = BOOLToJSVal(planet == (id)[UNIVERSE planet]);
			OK = YES;
			break;
			
		case kPlanet_radius:
			OK = JS_NewDoubleValue(context, [planet radius], outValue);
			break;
			
		case kPlanet_hasAtmosphere:
			*outValue = BOOLToJSVal([planet hasAtmosphere]);
			OK = YES;
			break;
			
		case kPlanet_texture:
			*outValue = [[planet textureFileName] javaScriptValueInContext:context];
			OK = YES;
			break;
			
		case kPlanet_orientation:
			OK = QuaternionToJSValue(context, [planet normalOrientation], outValue);
			break;
		
		default:
			OOReportJSBadPropertySelector(context, @"Planet", JSVAL_TO_INT(name));
	}
	return OK;
}


static JSBool PlanetSetProperty(JSContext *context, JSObject *this, jsval name, jsval *value)
{
	BOOL					OK = YES;
	OOPlanetEntity			*planet = nil;
	NSString				*sValue = nil;
	Quaternion				qValue;
	
	if (!JSVAL_IS_INT(name))  return YES;
	if (!JSPlanetGetPlanetEntity(context, this, &planet)) return NO;
	
	switch (JSVAL_TO_INT(name))
	{
		case kPlanet_texture:
			// all error messages are self contained

			sValue = JSValToNSString(context, *value);
			
			if ([planet isKindOfClass:[OOPlanetEntity class]])
			{
				if (sValue == nil)
				{
					OK = NO;
					OOReportJSWarning(context, @"Expected texture string. Value not set.");
				}
			}
			else
			{
				OK = NO;
			}
			
			if (OK)
			{
				OK = [planet setUpPlanetFromTexture:sValue];
				if (!OK) OOReportJSWarning(context, @"Cannot find texture \"%@\". Value not set.", sValue);
			}
			break;
			
		case kPlanet_orientation:
			if (JSValueToQuaternion(context, *value, &qValue))
			{
				quaternion_normalize(&qValue);
				[planet setOrientation:qValue];
				OK = YES;
			}
			break;
			
		default:
			OOReportJSBadPropertySelector(context, @"Planet", JSVAL_TO_INT(name));
			OK = NO;
	}
	
	return OK;
}
