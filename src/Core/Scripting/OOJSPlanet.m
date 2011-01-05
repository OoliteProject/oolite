/*

OOJSPlanet.m


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

#import "OOJSPlanet.h"
#import "OOJSEntity.h"
#import "OOJavaScriptEngine.h"
#import "OOJSQuaternion.h"

#import "OOPlanetEntity.h"


static JSObject		*sPlanetPrototype;


static JSBool PlanetGetProperty(OOJS_PROP_ARGS);
static JSBool PlanetSetProperty(OOJS_PROP_ARGS);


static JSClass sPlanetClass =
{
	"Planet",
	JSCLASS_HAS_PRIVATE,
	
	JS_PropertyStub,		// addProperty
	JS_PropertyStub,		// delProperty
	PlanetGetProperty,		// getProperty
	PlanetSetProperty,		// setProperty
	JS_EnumerateStub,		// enumerate
	JS_ResolveStub,			// resolve
	JS_ConvertStub,			// convert
	OOJSObjectWrapperFinalize,// finalize
	JSCLASS_NO_OPTIONAL_MEMBERS
};


enum
{
	// Property IDs
	kPlanet_isMainPlanet,		// Is [UNIVERSE planet], boolean, read-only
	kPlanet_hasAtmosphere,
	kPlanet_radius,				// Radius of planet in metres, read-only
	kPlanet_texture,			// Planet texture read / write
	kPlanet_orientation,		// orientation, quaternion, read/write
	kPlanet_rotationalVelocity,	// read/write
};


static JSPropertySpec sPlanetProperties[] =
{
	// JS name					ID							flags
	{ "isMainPlanet",			kPlanet_isMainPlanet,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "hasAtmosphere",			kPlanet_hasAtmosphere,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "radius",					kPlanet_radius,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "texture",				kPlanet_texture,			JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "orientation",			kPlanet_orientation,		JSPROP_PERMANENT | JSPROP_ENUMERATE },	// Not documented since it's inherited from Entity
	{ "rotationalVelocity",		kPlanet_rotationalVelocity,	JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ 0 }
};


DEFINE_JS_OBJECT_GETTER(JSPlanetGetPlanetEntity, &sPlanetClass, sPlanetPrototype, OOPlanetEntity)


void InitOOJSPlanet(JSContext *context, JSObject *global)
{
	sPlanetPrototype = JS_InitClass(context, global, JSEntityPrototype(), &sPlanetClass, NULL, 0, sPlanetProperties, NULL, NULL, NULL);
	OOJSRegisterObjectConverter(&sPlanetClass, OOJSBasicPrivateObjectConverter);
	OOJSRegisterSubclass(&sPlanetClass, JSEntityClass());
}


@implementation OOPlanetEntity (OOJavaScriptExtensions)

- (BOOL) isVisibleToScripts
{
	return YES;
}


- (void)getJSClass:(JSClass **)outClass andPrototype:(JSObject **)outPrototype
{
	*outClass = &sPlanetClass;
	*outPrototype = sPlanetPrototype;
}


- (NSString *) oo_jsClassName
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


static JSBool PlanetGetProperty(OOJS_PROP_ARGS)
{
	if (!OOJS_PROPID_IS_INT)  return YES;
	
	OOJS_NATIVE_ENTER(context)
	
	BOOL						OK = NO;
	OOPlanetEntity				*planet = nil;
	if (!JSPlanetGetPlanetEntity(context, this, &planet)) return NO;
	
	switch (OOJS_PROPID_INT)
	{
		case kPlanet_isMainPlanet:
			*value = OOJSValueFromBOOL(planet == (id)[UNIVERSE planet]);
			OK = YES;
			break;
			
		case kPlanet_radius:
			OK = JS_NewDoubleValue(context, [planet radius], value);
			break;
			
		case kPlanet_hasAtmosphere:
			*value = OOJSValueFromBOOL([planet hasAtmosphere]);
			OK = YES;
			break;
			
		case kPlanet_texture:
			*value = [[planet textureFileName] oo_jsValueInContext:context];
			OK = YES;
			break;
			
		case kPlanet_orientation:
			OK = QuaternionToJSValue(context, [planet normalOrientation], value);
			break;
		
		case kPlanet_rotationalVelocity:
			OK = JS_NewDoubleValue(context, [planet rotationalVelocity], value);
			break;
		
		default:
			OOJSReportBadPropertySelector(context, @"Planet", OOJS_PROPID_INT);
	}
	return OK;
	
	OOJS_NATIVE_EXIT
}


static JSBool PlanetSetProperty(OOJS_PROP_ARGS)
{
	if (!OOJS_PROPID_IS_INT)  return YES;
	
	OOJS_NATIVE_ENTER(context)
	
	BOOL					OK = NO;
	OOPlanetEntity			*planet = nil;
	NSString				*sValue = nil;
	Quaternion				qValue;
	jsdouble				dValue;
	
	if (!JSPlanetGetPlanetEntity(context, this, &planet)) return NO;
	
	switch (OOJS_PROPID_INT)
	{
		case kPlanet_texture:
			// all error messages are self contained

			sValue = OOStringFromJSValue(context, *value);
			
			if ([planet isKindOfClass:[OOPlanetEntity class]])
			{
				if (sValue == nil)
				{
					OOJSReportWarning(context, @"Expected texture string. Value not set.");
				}
				else
				{
					OK = YES;
				}
			}
			
			if (OK)
			{
				OK = [planet setUpPlanetFromTexture:sValue];
				if (!OK) OOJSReportWarning(context, @"Cannot find texture \"%@\". Value not set.", sValue);
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

		case kPlanet_rotationalVelocity:
			if (JS_ValueToNumber(context, *value, &dValue))
			{
				[planet setRotationalVelocity:dValue];
				OK = YES;
			}
			break;
			
		default:
			OOJSReportBadPropertySelector(context, @"Planet", OOJS_PROPID_INT);
			break;
	}
	
	return OK;
	
	OOJS_NATIVE_EXIT
}
