/*

OOJSEntity.m (QuickJS-ng)

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

#import "OOJSEntity.h"
#import "OOConstToJSString.h"
#import "OOJSCall.h"
#import "OOJSQuaternion.h"
#import "OOJSVector.h"
#import "OOJavaScriptEngine.h"

#import "OOJSPlayer.h"
#import "PlayerEntity.h"
#import "ShipEntity.h"

static JSClassID sEntityClassID;

static JSValue EntityGetProperty(OOJS_GETTER_ARGS);
static JSValue EntitySetProperty(OOJS_SETTER_ARGS);
#ifdef OO_DEBUG_MONITOR_ENABLED
static JSValue EntityDumpState(OOJS_NATIVE_ARGS);
#endif

static JSClassDef sEntityClass = {
    .class_name = "Entity",
    .finalizer = OOJSObjectWrapperFinalize,
};

enum {
    // Property IDs
    kEntity_collisionRadius, // collision radius, double, read-only.
    kEntity_distanceTravelled, // distance travelled, double, read-only.
    kEntity_energy, // energy, double, read-write.
    kEntity_heading, // heading, vector, read-only (like orientation but ignoring twist angle)
    kEntity_mass, // mass, double, read-only
    kEntity_maxEnergy, // maxEnergy, double, read-only.
    kEntity_orientation, // orientation, quaternion, read/write
    kEntity_owner, // owner, Entity, read-only. (Parent ship for subentities, station for defense ships, launching ship for missiles etc)
    kEntity_position, // position in system space, Vector, read/write
    kEntity_scanClass, // scan class, string, read-only
    kEntity_spawnTime, // spawn time, double, read-only.
    kEntity_status, // entity status, string, read-only
    kEntity_isPlanet, // is planet, boolean, read-only.
    kEntity_isPlayer, // is player, boolean, read-only.
    kEntity_isShip, // is ship, boolean, read-only.
    kEntity_isStation, // is station, boolean, read-only.
    kEntity_isDock, // is dock, boolean, read-only.
    kEntity_isSubEntity, // is subentity, boolean, read-only.
    kEntity_isSun, // is sun, boolean, read-only.
    kEntity_isSunlit, // is sunlit, boolean, read-only.
    kEntity_isValid, // is not stale, boolean, read-only.
    kEntity_isInSpace, // is in space, boolean, read-only.
    kEntity_isVisible, // is within drawing distance, boolean, read-only.
    kEntity_isVisualEffect, // is visual effect, boolean, read-only.
    kEntity_isWormhole, // is visual effect, boolean, read-only.
};

static const JSCFunctionListEntry sEntityProperties[] = {
    // JS name, getter, setter, ID
    OOJS_PROPERTY_RO("collisionRadius", EntityGetProperty, kEntity_collisionRadius),
    OOJS_PROPERTY_RO("distanceTravelled", EntityGetProperty, kEntity_distanceTravelled),
    OOJS_PROPERTY_RW("energy", EntityGetProperty, EntitySetProperty, kEntity_energy),
    OOJS_PROPERTY_RO("heading", EntityGetProperty, kEntity_heading),
    OOJS_PROPERTY_RO("mass", EntityGetProperty, kEntity_mass),
    OOJS_PROPERTY_RW("maxEnergy", EntityGetProperty, EntitySetProperty, kEntity_maxEnergy),
    OOJS_PROPERTY_RW("orientation", EntityGetProperty, EntitySetProperty, kEntity_orientation),
    OOJS_PROPERTY_RO("owner", EntityGetProperty, kEntity_owner),
    OOJS_PROPERTY_RW("position", EntityGetProperty, EntitySetProperty, kEntity_position),
    OOJS_PROPERTY_RW("scanClass", EntityGetProperty, EntitySetProperty, kEntity_scanClass),
    OOJS_PROPERTY_RO("spawnTime", EntityGetProperty, kEntity_spawnTime),
    OOJS_PROPERTY_RO("status", EntityGetProperty, kEntity_status),
    OOJS_PROPERTY_RO("isPlanet", EntityGetProperty, kEntity_isPlanet),
    OOJS_PROPERTY_RO("isPlayer", EntityGetProperty, kEntity_isPlayer),
    OOJS_PROPERTY_RO("isShip", EntityGetProperty, kEntity_isShip),
    OOJS_PROPERTY_RO("isDock", EntityGetProperty, kEntity_isDock),
    OOJS_PROPERTY_RO("isStation", EntityGetProperty, kEntity_isStation),
    OOJS_PROPERTY_RO("isSubEntity", EntityGetProperty, kEntity_isSubEntity),
    OOJS_PROPERTY_RO("isSun", EntityGetProperty, kEntity_isSun),
    OOJS_PROPERTY_RO("isSunlit", EntityGetProperty, kEntity_isSunlit),
    OOJS_PROPERTY_RO("isValid", EntityGetProperty, kEntity_isValid),
    OOJS_PROPERTY_RO("isInSpace", EntityGetProperty, kEntity_isInSpace),
    OOJS_PROPERTY_RO("isVisible", EntityGetProperty, kEntity_isVisible),
    OOJS_PROPERTY_RO("isVisualEffect", EntityGetProperty, kEntity_isVisualEffect),
    OOJS_PROPERTY_RO("isWormhole", EntityGetProperty, kEntity_isWormhole),
};

static const JSCFunctionListEntry sEntityMethods[] = {
    // JS name, min args, function
    JS_CFUNC_DEF("toString", 0, OOJSObjectWrapperToString),
#ifdef OO_DEBUG_MONITOR_ENABLED
    JS_CFUNC_DEF("dumpState", 0, EntityDumpState),
#endif
};

JSClassID JSEntityClassID(void)
{
    return sEntityClassID;
}

void InitOOJSEntity(JSContext* context, JSValueConst global)
{
    OOJSRegisterClass(&sEntityClassID, &sEntityClass);
    OOJSInitClass(context, global, sEntityClassID, JS_UNDEFINED, OOJSUnconstructableConstruct, 0,
        sEntityProperties, OOJS_COUNT(sEntityProperties), sEntityMethods, OOJS_COUNT(sEntityMethods), NULL, 0);
    OOJSRegisterObjectConverter(sEntityClassID, OOJSBasicPrivateObjectConverter);
}

BOOL JSValueToEntity(JSContext* context, JSValueConst value, Entity** outEntity)
{
    if (JS_IsObject(value)) {
        return OOJSEntityGetEntity(context, value, outEntity);
    }

    return NO;
}

BOOL EntityFromArgumentList(JSContext* context, NSString* scriptClass, NSString* function, int argc, JSValueConst* argv, Entity** outEntity, int* outConsumed)
{
    OOJS_PROFILE_ENTER

    // Sanity checks.
    if (outConsumed != NULL)
        *outConsumed = 0;
    if (EXPECT_NOT(argc == 0 || argv == NULL || outEntity == NULL)) {
        OOLogGenericParameterError();
        return NO;
    }

    // Get value, if possible.
    if (EXPECT_NOT(!JSValueToEntity(context, argv[0], outEntity))) {
        // Failed; report bad parameters, if given a class and function.
        if (scriptClass != nil && function != nil) {
            OOJSReportWarning(context, @"%@.%@(): expected entity, got %@.", scriptClass, function, [NSString stringWithJavaScriptParameters:argv count:1 inContext:context]);
            return NO;
        }
    }

    // Success.
    if (outConsumed != NULL)
        *outConsumed = 1;
    return YES;

    OOJS_PROFILE_EXIT
}

static JSValue EntityGetProperty(OOJS_GETTER_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    Entity* entity = nil;
    id result = nil;
    JSValue value = JS_UNDEFINED;

    if (EXPECT_NOT(!OOJSEntityGetEntity(context, this, &entity)))
        return JS_EXCEPTION;
    if (OOIsStaleEntity(entity)) {
        if (magic == kEntity_isValid)
            return JS_FALSE;
        else
            return JS_UNDEFINED;
    }

    switch (magic) {
    case kEntity_collisionRadius:
        return JS_NewFloat64(context, [entity collisionRadius]);

    case kEntity_position:
        OOJS_RETURN_HPVECTOR([entity position]);

    case kEntity_orientation:
        OOJS_RETURN_QUATERNION([entity normalOrientation]);

    case kEntity_heading:
        OOJS_RETURN_VECTOR(vector_forward_from_quaternion([entity normalOrientation]));

    case kEntity_status:
        return OOJSValueFromEntityStatus(context, [entity status]);

    case kEntity_scanClass:
        return OOJSValueFromScanClass(context, [entity scanClass]);

    case kEntity_mass:
        return JS_NewFloat64(context, [entity mass]);

    case kEntity_owner:
        result = [entity owner];
        if (result == entity)
            result = nil;
        break;

    case kEntity_energy:
        return JS_NewFloat64(context, [entity energy]);

    case kEntity_maxEnergy:
        return JS_NewFloat64(context, [entity maxEnergy]);

    case kEntity_isValid:
        return [entity status] == STATUS_DEAD ? JS_FALSE : JS_TRUE;

    case kEntity_isInSpace:
        return OOJSValueFromBOOL([entity isInSpace]);

    case kEntity_isShip:
        return OOJSValueFromBOOL([entity isShip]);

    case kEntity_isStation:
        return OOJSValueFromBOOL([entity isStation]);

    case kEntity_isDock:
        return OOJSValueFromBOOL([entity isDock]);

    case kEntity_isSubEntity:
        return OOJSValueFromBOOL([entity isSubEntity]);

    case kEntity_isPlayer:
        return OOJSValueFromBOOL([entity isPlayer]);

    case kEntity_isPlanet:
        return OOJSValueFromBOOL([entity isPlanet]);

    case kEntity_isSun:
        return OOJSValueFromBOOL([entity isSun]);

    case kEntity_isSunlit:
        return OOJSValueFromBOOL([entity isSunlit]);

    case kEntity_isVisible:
        return OOJSValueFromBOOL([entity isVisible]);

    case kEntity_isVisualEffect:
        return OOJSValueFromBOOL([entity isVisualEffect]);

    case kEntity_isWormhole:
        return OOJSValueFromBOOL([entity isWormhole]);

    case kEntity_distanceTravelled:
        return JS_NewFloat64(context, [entity distanceTravelled]);

    case kEntity_spawnTime:
        return JS_NewFloat64(context, [entity spawnTime]);

    default:
        OOJSReportBadPropertySelector(context, this, magic, sEntityProperties, OOJS_COUNT(sEntityProperties));
        return JS_EXCEPTION;
    }

    value = OOJSValueFromNativeObject(context, result);
    return value;

    OOJS_NATIVE_EXIT
}

static JSValue EntitySetProperty(OOJS_SETTER_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    Entity* entity = nil;
    double fValue;
    HPVector hpvValue;
    Quaternion qValue;

    if (EXPECT_NOT(!OOJSEntityGetEntity(context, this, &entity)))
        return JS_EXCEPTION;
    if (OOIsStaleEntity(entity))
        return JS_UNDEFINED;

    switch (magic) {
    case kEntity_position:
        if (JSValueToHPVector(context, value, &hpvValue)) {
            [entity setPosition:hpvValue];
            if ([entity isShip]) {
                [(ShipEntity*)entity resetExhaustPlumes];
                [(ShipEntity*)entity forceAegisCheck];
            }
            return JS_UNDEFINED;
        }
        break;

    case kEntity_orientation:
        if (JSValueToQuaternion(context, value, &qValue)) {
            [entity setNormalOrientation:qValue];
            return JS_UNDEFINED;
        }
        break;

    case kEntity_energy:
        if (JS_ToFloat64(context, &fValue, value) == 0) {
            fValue = OOClamp_0_max_d(fValue, [entity maxEnergy]);
            [entity setEnergy:fValue];
            return JS_UNDEFINED;
        }
        JS_FreeValue(context, JS_GetException(context));
        break;

    case kEntity_maxEnergy:
        if (JS_ToFloat64(context, &fValue, value) == 0) {
            if (fValue <= 0.0) {
                OOJSReportError(context, @"entity.maxEnergy must be positive.");
                return JS_EXCEPTION;
            }
            [entity setMaxEnergy:fValue];
            return JS_UNDEFINED;
        }
        JS_FreeValue(context, JS_GetException(context));
        break;

    case kEntity_scanClass:
        if ([entity isShip] && ![entity isPlayer]) {
            OOScanClass newClass = OOScanClassFromJSValue(context, value);
            if (newClass == CLASS_NOT_SET || newClass == CLASS_NO_DRAW || newClass == CLASS_TARGET || newClass == CLASS_WORMHOLE || newClass == CLASS_PLAYER || newClass == CLASS_VISUAL_EFFECT) {
                OOJSReportError(context, @"entity.scanClass cannot be set to that value.");
                return JS_EXCEPTION;
            }
            [entity setScanClass:newClass];
            return JS_UNDEFINED;
        } else {
            OOJSReportError(context, @"entity.scanClass is read-only except on NPC ships.");
            return JS_EXCEPTION;
        }
    default:
        OOJSReportBadPropertySelector(context, this, magic, sEntityProperties, OOJS_COUNT(sEntityProperties));
        return JS_EXCEPTION;
    }

    OOJSReportBadPropertyValue(context, this, magic, sEntityProperties, OOJS_COUNT(sEntityProperties), value);
    return JS_EXCEPTION;

    OOJS_NATIVE_EXIT
}

#ifdef OO_DEBUG_MONITOR_ENABLED
static JSValue EntityDumpState(OOJS_NATIVE_ARGS)
{
    OOJS_PROFILE_ENTER

    Entity* thisEnt = nil;
    OOJSEntityGetEntity(context, OOJS_THIS, &thisEnt);
    [thisEnt dumpState];

    OOJS_RETURN_VOID;

    OOJS_PROFILE_EXIT
}
#endif
