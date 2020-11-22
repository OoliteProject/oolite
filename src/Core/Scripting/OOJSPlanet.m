/*

OOJSPlanet.m


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

#import "OOJSPlanet.h"
#import "OOJSEntity.h"
#import "OOJavaScriptEngine.h"
#import "OOJSQuaternion.h"
#import "OOJSVector.h"

#import "OOPlanetEntity.h"


static JSObject		*sPlanetPrototype;


static JSBool PlanetGetProperty(JSContext *context, JSObject *this, jsid propID, jsval *value);
static JSBool PlanetSetProperty(JSContext *context, JSObject *this, jsid propID, JSBool strict, jsval *value);


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
	kPlanet_airColor,			// air color, read/write
	kPlanet_airColorMixRatio,	// air color mix ratio, float, read/write
	kPlanet_airDensity,		// air density, float, read/write
	kPlanet_isMainPlanet,		// Is [UNIVERSE planet], boolean, read-only
	kPlanet_hasAtmosphere,
	kPlanet_name,				// Name of planet, string, read/write
	kPlanet_radius,				// Radius of planet in metres, read-only
	kPlanet_texture,			// Planet texture read / write
	kPlanet_orientation,		// orientation, quaternion, read/write
	kPlanet_rotationalVelocity,	// read/write
	kPlanet_terminatorThresholdVector,
};


static JSPropertySpec sPlanetProperties[] =
{
	// JS name					ID							flags
	{ "airColor",				kPlanet_airColor,					OOJS_PROP_READWRITE_CB },
	{ "airColorMixRatio",			kPlanet_airColorMixRatio,			OOJS_PROP_READWRITE_CB },
	{ "airDensity",				kPlanet_airDensity,				OOJS_PROP_READWRITE_CB },
	{ "hasAtmosphere",			kPlanet_hasAtmosphere,			OOJS_PROP_READONLY_CB },
	{ "isMainPlanet",				kPlanet_isMainPlanet,				OOJS_PROP_READONLY_CB },
	{ "name",					kPlanet_name,						OOJS_PROP_READWRITE_CB },
	{ "radius",					kPlanet_radius,					OOJS_PROP_READONLY_CB },
	{ "rotationalVelocity",		kPlanet_rotationalVelocity,		OOJS_PROP_READWRITE_CB },
	{ "texture",					kPlanet_texture,					OOJS_PROP_READWRITE_CB },
	{ "orientation",				kPlanet_orientation,				OOJS_PROP_READWRITE_CB },	// Not documented since it's inherited from Entity
	{ "terminatorThresholdVector",	kPlanet_terminatorThresholdVector,	OOJS_PROP_READWRITE_CB },
	{ 0 }
};


DEFINE_JS_OBJECT_GETTER(JSPlanetGetPlanetEntity, &sPlanetClass, sPlanetPrototype, OOPlanetEntity)


void InitOOJSPlanet(JSContext *context, JSObject *global)
{
	sPlanetPrototype = JS_InitClass(context, global, JSEntityPrototype(), &sPlanetClass, OOJSUnconstructableConstruct, 0, sPlanetProperties, NULL, NULL, NULL);
	OOJSRegisterObjectConverter(&sPlanetClass, OOJSBasicPrivateObjectConverter);
	OOJSRegisterSubclass(&sPlanetClass, JSEntityClass());
}


@implementation OOPlanetEntity (OOJavaScriptExtensions)

- (BOOL) isVisibleToScripts
{
	OOStellarBodyType type = [self planetType];
	return type == STELLAR_TYPE_NORMAL_PLANET || type == STELLAR_TYPE_MOON;
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


static JSBool PlanetGetProperty(JSContext *context, JSObject *this, jsid propID, jsval *value)
{
	if (!JSID_IS_INT(propID))  return YES;
	
	OOJS_NATIVE_ENTER(context)
	
	OOPlanetEntity				*planet = nil;
	if (!JSPlanetGetPlanetEntity(context, this, &planet))  return NO;
	
	switch (JSID_TO_INT(propID))
	{
		case kPlanet_airColor:
			*value = OOJSValueFromNativeObject(context, [[planet airColor] normalizedArray]);
			return YES;
			
		case kPlanet_airColorMixRatio:
			return JS_NewNumberValue(context, [planet airColorMixRatio], value);
			
		case kPlanet_airDensity:
			return JS_NewNumberValue(context, [planet airDensity], value);

		case kPlanet_isMainPlanet:
			*value = OOJSValueFromBOOL(planet == (id)[UNIVERSE planet]);
			return YES;
			
		case kPlanet_radius:
			return JS_NewNumberValue(context, [planet radius], value);
			
		case kPlanet_hasAtmosphere:
			*value = OOJSValueFromBOOL([planet hasAtmosphere]);
			return YES;
			
		case kPlanet_texture:
			*value = OOJSValueFromNativeObject(context, [planet textureFileName]);
			return YES;
			
		case kPlanet_name:
			*value = OOJSValueFromNativeObject(context, [planet name]);
			return YES;

		case kPlanet_orientation:
			return QuaternionToJSValue(context, [planet normalOrientation], value);
		
		case kPlanet_rotationalVelocity:
			return JS_NewNumberValue(context, [planet rotationalVelocity], value);
			
		case kPlanet_terminatorThresholdVector:
			return VectorToJSValue(context, [planet terminatorThresholdVector], value);
		
		default:
			OOJSReportBadPropertySelector(context, this, propID, sPlanetProperties);
			return NO;
	}
	
	OOJS_NATIVE_EXIT
}


static JSBool PlanetSetProperty(JSContext *context, JSObject *this, jsid propID, JSBool strict, jsval *value)
{
	if (!JSID_IS_INT(propID))  return YES;
	
	OOJS_NATIVE_ENTER(context)
	
	OOPlanetEntity			*planet = nil;
	NSString				*sValue = nil;
	Quaternion				qValue;
	Vector					vValue;
	jsdouble				dValue;
	OOColor				*colorForScript = nil;
	
	if (!JSPlanetGetPlanetEntity(context, this, &planet))  return NO;
	
	switch (JSID_TO_INT(propID))
	{
		case kPlanet_airColor:
			colorForScript = [OOColor colorWithDescription:OOJSNativeObjectFromJSValue(context, *value)];
			if (colorForScript != nil || JSVAL_IS_NULL(*value))
			{
				[planet setAirColor:colorForScript];
				return YES;
			}
			break;
			
		case kPlanet_airColorMixRatio:
			if (JS_ValueToNumber(context, *value, &dValue))
			{
				[planet setAirColorMixRatio:dValue];
				return YES;
			}
			break;
			
		case kPlanet_airDensity:
			if (JS_ValueToNumber(context, *value, &dValue))
			{
				[planet setAirDensity:dValue];
				return YES;
			}
			break;

		case kPlanet_name:
			sValue = OOStringFromJSValue(context, *value);
			[planet setName:sValue];
			return YES;

		case kPlanet_texture:
		{
			BOOL OK = NO;
			sValue = OOStringFromJSValue(context, *value);
			
			OOJSPauseTimeLimiter();
	
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
				if (!OK)  OOJSReportWarning(context, @"Cannot find texture \"%@\". Value not set.", sValue);
			}

			OOJSResumeTimeLimiter();

			return YES;	// Even if !OK, no exception was raised.
		}
			
		case kPlanet_orientation:
			if (JSValueToQuaternion(context, *value, &qValue))
			{
				quaternion_normalize(&qValue);
				[planet setOrientation:qValue];
				return YES;
			}
			break;

		case kPlanet_rotationalVelocity:
			if (JS_ValueToNumber(context, *value, &dValue))
			{
				[planet setRotationalVelocity:dValue];
				return YES;
			}
			break;
			
		case kPlanet_terminatorThresholdVector:
			if (JSValueToVector(context, *value, &vValue))
			{
				[planet setTerminatorThresholdVector:vValue];
				return YES;
			}
			break;
			
		default:
			OOJSReportBadPropertySelector(context, this, propID, sPlanetProperties);
			return NO;
	}
	
	OOJSReportBadPropertyValue(context, this, propID, sPlanetProperties, *value);
	return NO;
	
	OOJS_NATIVE_EXIT
}
