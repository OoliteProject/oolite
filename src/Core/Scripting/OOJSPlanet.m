/*

OOJSPlanet.m (QuickJS-ng)


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
#import "EntityOOJavaScriptExtensions.h"
#import "OOJSEntity.h"
#import "OOJSQuaternion.h"
#import "OOJSVector.h"
#import "OOJavaScriptEngine.h"
#import "OOPlanetEntity.h"

static JSClassID sPlanetClassID;

static JSValue PlanetGetProperty(OOJS_GETTER_ARGS);
static JSValue PlanetSetProperty(OOJS_SETTER_ARGS);

static JSClassDef sPlanetClass = {
    .class_name = "Planet",
    .finalizer = OOJSObjectWrapperFinalize,
};

enum {
    // Property IDs
    kPlanet_airColor, // air color, read/write
    kPlanet_airColorMixRatio, // air color mix ratio, float, read/write
    kPlanet_airDensity, // air density, float, read/write
    kPlanet_hasAtmosphere,
    kPlanet_illuminationColor, // illumination color, read/write
    kPlanet_isMainPlanet, // Is [UNIVERSE planet], boolean, read-only
    kPlanet_name, // Name of planet, string, read/write
    kPlanet_radius, // Radius of planet in metres, read-only
    kPlanet_texture, // Planet texture read / write
    kPlanet_orientation, // orientation, quaternion, read/write
    kPlanet_rotationalVelocity, // read/write
    kPlanet_terminatorThresholdVector,
};

static const JSCFunctionListEntry sPlanetProperties[] = {
    // JS name, getter, setter, ID
    OOJS_PROPERTY_RW("airColor", PlanetGetProperty, PlanetSetProperty, kPlanet_airColor),
    OOJS_PROPERTY_RW("airColorMixRatio", PlanetGetProperty, PlanetSetProperty, kPlanet_airColorMixRatio),
    OOJS_PROPERTY_RW("airDensity", PlanetGetProperty, PlanetSetProperty, kPlanet_airDensity),
    OOJS_PROPERTY_RO("hasAtmosphere", PlanetGetProperty, kPlanet_hasAtmosphere),
    OOJS_PROPERTY_RW("illuminationColor", PlanetGetProperty, PlanetSetProperty, kPlanet_illuminationColor),
    OOJS_PROPERTY_RO("isMainPlanet", PlanetGetProperty, kPlanet_isMainPlanet),
    OOJS_PROPERTY_RW("name", PlanetGetProperty, PlanetSetProperty, kPlanet_name),
    OOJS_PROPERTY_RO("radius", PlanetGetProperty, kPlanet_radius),
    OOJS_PROPERTY_RW("rotationalVelocity", PlanetGetProperty, PlanetSetProperty, kPlanet_rotationalVelocity),
    OOJS_PROPERTY_RW("texture", PlanetGetProperty, PlanetSetProperty, kPlanet_texture),
    OOJS_PROPERTY_RW("orientation", PlanetGetProperty, PlanetSetProperty, kPlanet_orientation), // Not documented since it's inherited from Entity
    OOJS_PROPERTY_RW("terminatorThresholdVector", PlanetGetProperty, PlanetSetProperty, kPlanet_terminatorThresholdVector),
};

DEFINE_JS_OBJECT_GETTER(JSPlanetGetPlanetEntity, sPlanetClassID, OOPlanetEntity)

void InitOOJSPlanet(JSContext* context, JSValueConst global)
{
    OOJSRegisterClass(&sPlanetClassID, &sPlanetClass);

    JSValue parentPrototype = JS_GetClassProto(context, JSEntityClassID());
    NSCAssert(JS_IsObject(parentPrototype), @"Entity must be initialized before Planet.");
    OOJSInitClass(context, global, sPlanetClassID, parentPrototype, OOJSUnconstructableConstruct, 0,
        sPlanetProperties, OOJS_COUNT(sPlanetProperties), NULL, 0, NULL, 0);
    JS_FreeValue(context, parentPrototype);

    OOJSRegisterObjectConverter(sPlanetClassID, OOJSBasicPrivateObjectConverter);
    OOJSRegisterSubclass(sPlanetClassID, JSEntityClassID());
}

JSClassID JSPlanetClassID(void)
{
    return sPlanetClassID;
}

@implementation OOPlanetEntity (OOJavaScriptExtensions)

- (BOOL)isVisibleToScripts
{
    OOStellarBodyType type = [self planetType];
    return type == STELLAR_TYPE_NORMAL_PLANET || type == STELLAR_TYPE_MOON;
}

- (JSClassID)oo_jsClassID
{
    return sPlanetClassID;
}

- (NSString*)oo_jsClassName
{
    switch ([self planetType]) {
    case STELLAR_TYPE_NORMAL_PLANET:
        return @"Planet";
    case STELLAR_TYPE_MOON:
        return @"Moon";
    default:
        return @"Unknown";
    }
}

@end

static JSValue PlanetGetProperty(OOJS_GETTER_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    OOPlanetEntity* planet = nil;
    if (!JSPlanetGetPlanetEntity(context, this, &planet))
        return OOJSNativeFailure(context);

    switch (magic) {
    case kPlanet_airColor:
        return OOJSValueFromNativeObject(context, [[planet airColor] normalizedArray]);

    case kPlanet_airColorMixRatio:
        return JS_NewNumber(context, [planet airColorMixRatio]);

    case kPlanet_airDensity:
        return JS_NewNumber(context, [planet airDensity]);

    case kPlanet_illuminationColor:
        return OOJSValueFromNativeObject(context, [[planet illuminationColor] normalizedArray]);

    case kPlanet_isMainPlanet:
        return OOJSValueFromBOOL(planet == (id)[UNIVERSE planet]);

    case kPlanet_radius:
        return JS_NewNumber(context, [planet radius]);

    case kPlanet_hasAtmosphere:
        return OOJSValueFromBOOL([planet hasAtmosphere]);

    case kPlanet_texture:
        return OOJSValueFromNativeObject(context, [planet textureFileName]);

    case kPlanet_name:
        return OOJSValueFromNativeObject(context, [planet name]);

    case kPlanet_orientation:
        OOJS_RETURN_QUATERNION([planet normalOrientation]);

    case kPlanet_rotationalVelocity:
        return JS_NewNumber(context, [planet rotationalVelocity]);

    case kPlanet_terminatorThresholdVector:
        OOJS_RETURN_VECTOR([planet terminatorThresholdVector]);

    default:
        OOJSReportBadPropertySelector(context, this, magic, sPlanetProperties, OOJS_COUNT(sPlanetProperties));
        return OOJSNativeFailure(context);
    }

    OOJS_NATIVE_EXIT
}

static JSValue PlanetSetProperty(OOJS_SETTER_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    OOPlanetEntity* planet = nil;
    NSString* sValue = nil;
    Quaternion qValue;
    Vector vValue;
    double dValue;
    OOColor* colorForScript = nil;

    if (!JSPlanetGetPlanetEntity(context, this, &planet))
        return OOJSNativeFailure(context);

    switch (magic) {
    case kPlanet_airColor:
        colorForScript = [OOColor colorWithDescription:OOJSNativeObjectFromJSValue(context, value)];
        if (colorForScript != nil || JS_IsNull(value)) {
            [planet setAirColor:colorForScript];
            return JS_UNDEFINED;
        }
        break;

    case kPlanet_airColorMixRatio:
        if (JS_ToFloat64(context, &dValue, value) == 0) {
            [planet setAirColorMixRatio:dValue];
            return JS_UNDEFINED;
        }
        break;

    case kPlanet_airDensity:
        if (JS_ToFloat64(context, &dValue, value) == 0) {
            [planet setAirDensity:dValue];
            return JS_UNDEFINED;
        }
        break;

    case kPlanet_illuminationColor:
        colorForScript = [OOColor colorWithDescription:OOJSNativeObjectFromJSValue(context, value)];
        if (colorForScript != nil || JS_IsNull(value)) {
            [planet setIlluminationColor:colorForScript];
            return JS_UNDEFINED;
        }
        break;

    case kPlanet_name:
        sValue = OOStringFromJSValue(context, value);
        [planet setName:sValue];
        return JS_UNDEFINED;

    case kPlanet_texture: {
        BOOL OK = NO;
        sValue = OOStringFromJSValue(context, value);

        OOJSPauseTimeLimiter();

        if ([planet isKindOfClass:[OOPlanetEntity class]]) {
            if (sValue == nil) {
                OOJSReportWarning(context, @"Expected texture string. Value not set.");
            } else {
                OK = YES;
            }
        }

        if (OK) {
            OK = [planet setUpPlanetFromTexture:sValue];
            if (!OK)
                OOJSReportWarning(context, @"Cannot find texture \"%@\". Value not set.", sValue);
        }

        OOJSResumeTimeLimiter();

        return JS_UNDEFINED; // Even if !OK, no exception was raised.
    }

    case kPlanet_orientation:
        if (JSValueToQuaternion(context, value, &qValue)) {
            quaternion_normalize(&qValue);
            [planet setOrientation:qValue];
            return JS_UNDEFINED;
        }
        break;

    case kPlanet_rotationalVelocity:
        if (JS_ToFloat64(context, &dValue, value) == 0) {
            [planet setRotationalVelocity:dValue];
            return JS_UNDEFINED;
        }
        break;

    case kPlanet_terminatorThresholdVector:
        if (JSValueToVector(context, value, &vValue)) {
            [planet setTerminatorThresholdVector:vValue];
            return JS_UNDEFINED;
        }
        break;

    default:
        OOJSReportBadPropertySelector(context, this, magic, sPlanetProperties, OOJS_COUNT(sPlanetProperties));
        return OOJSNativeFailure(context);
    }

    OOJSReportBadPropertyValue(context, this, magic, sPlanetProperties, OOJS_COUNT(sPlanetProperties), value);
    return OOJSNativeFailure(context);

    OOJS_NATIVE_EXIT
}
