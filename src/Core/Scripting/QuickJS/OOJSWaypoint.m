/*
OOJSWaypoint.m (QuickJS-ng)

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

#import "OOJSWaypoint.h"
#import "EntityOOJavaScriptExtensions.h"
#import "OOCollectionExtractors.h"
#import "OOJSEntity.h"
#import "OOJSQuaternion.h"
#import "OOJSVector.h"
#import "OOJavaScriptEngine.h"
#import "OOWaypointEntity.h"

static JSClassID sWaypointClassID;

static BOOL JSWaypointGetWaypointEntity(JSContext* context, JSValueConst waypointObj, OOWaypointEntity** outEntity);

static JSValue WaypointGetProperty(OOJS_GETTER_ARGS);
static JSValue WaypointSetProperty(OOJS_SETTER_ARGS);

static JSClassDef sWaypointClass = {
    .class_name = "Waypoint",
    .finalizer = OOJSObjectWrapperFinalize,
};

enum {
    // Property IDs
    kWaypoint_beaconCode,
    kWaypoint_beaconLabel,
    kWaypoint_orientation, // overrides entity as waypoints can be unoriented
    kWaypoint_size
};

static const JSCFunctionListEntry sWaypointProperties[] = {
    // JS name, getter, setter, ID
    OOJS_PROPERTY_RW("beaconCode", WaypointGetProperty, WaypointSetProperty, kWaypoint_beaconCode),
    OOJS_PROPERTY_RW("beaconLabel", WaypointGetProperty, WaypointSetProperty, kWaypoint_beaconLabel),
    OOJS_PROPERTY_RW("orientation", WaypointGetProperty, WaypointSetProperty, kWaypoint_orientation),
    OOJS_PROPERTY_RW("size", WaypointGetProperty, WaypointSetProperty, kWaypoint_size),
};

// No Waypoint methods.

void InitOOJSWaypoint(JSContext* context, JSValueConst global)
{
    OOJSRegisterClass(&sWaypointClassID, &sWaypointClass);

    JSValue parentPrototype = JS_GetClassProto(context, JSEntityClassID());
    NSCAssert(JS_IsObject(parentPrototype), @"Entity must be initialized before Waypoint.");
    OOJSInitClass(context, global, sWaypointClassID, parentPrototype, OOJSUnconstructableConstruct, 0,
        sWaypointProperties, OOJS_COUNT(sWaypointProperties), NULL, 0, NULL, 0);
    JS_FreeValue(context, parentPrototype);

    OOJSRegisterObjectConverter(sWaypointClassID, OOJSBasicPrivateObjectConverter);
    OOJSRegisterSubclass(sWaypointClassID, JSEntityClassID());
}

JSClassID JSWaypointClassID(void)
{
    return sWaypointClassID;
}

static BOOL JSWaypointGetWaypointEntity(JSContext* context, JSValueConst waypointObj, OOWaypointEntity** outEntity)
{
    OOJS_PROFILE_ENTER

    BOOL result;
    Entity* entity = nil;

    if (outEntity == NULL)
        return NO;
    *outEntity = nil;

    result = OOJSEntityGetEntity(context, waypointObj, &entity);
    if (!result)
        return NO;

    if (![entity isKindOfClass:[OOWaypointEntity class]])
        return NO;

    *outEntity = (OOWaypointEntity*)entity;
    return YES;

    OOJS_PROFILE_EXIT
}

@implementation OOWaypointEntity (OOJavaScriptExtensions)

- (JSClassID)oo_jsClassID
{
    return sWaypointClassID;
}

- (NSString*)oo_jsClassName
{
    return @"Waypoint";
}

- (BOOL)isVisibleToScripts
{
    return YES;
}

@end

static JSValue WaypointGetProperty(OOJS_GETTER_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    OOWaypointEntity* entity = nil;
    id result = nil;
    Quaternion q = kIdentityQuaternion;

    if (!JSWaypointGetWaypointEntity(context, this, &entity))
        return OOJSNativeFailure(context);
    if (entity == nil) {
        return JS_UNDEFINED;
    }

    switch (magic) {
    case kWaypoint_beaconCode:
        result = [entity beaconCode];
        break;

    case kWaypoint_beaconLabel:
        result = [entity beaconLabel];
        break;

    case kWaypoint_orientation:
        q = [entity orientation];
        if (![entity oriented]) {
            q = kZeroQuaternion;
        }
        OOJS_RETURN_QUATERNION(q);

    case kWaypoint_size:
        return JS_NewNumber(context, [entity size]);

    default:
        OOJSReportBadPropertySelector(context, this, magic, sWaypointProperties, OOJS_COUNT(sWaypointProperties));
        return OOJSNativeFailure(context);
    }

    return OOJSValueFromNativeObject(context, result);

    OOJS_NATIVE_EXIT
}

static JSValue WaypointSetProperty(OOJS_SETTER_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    OOWaypointEntity* entity = nil;
    double fValue;
    NSString* sValue = nil;
    Quaternion qValue;

    if (!JSWaypointGetWaypointEntity(context, this, &entity))
        return OOJSNativeFailure(context);
    if (entity == nil)
        return JS_UNDEFINED;

    switch (magic) {
    case kWaypoint_beaconCode:
        sValue = OOStringFromJSValue(context, value);
        if (sValue == nil || [sValue length] == 0) {
            if ([entity isBeacon]) {
                [UNIVERSE clearBeacon:entity];
                if ([PLAYER nextBeacon] == entity) {
                    [PLAYER setCompassMode:COMPASS_MODE_PLANET];
                }
            }
        } else {
            if ([entity isBeacon]) {
                [entity setBeaconCode:sValue];
            } else // Universe needs to update beacon lists in this case only
            {
                [entity setBeaconCode:sValue];
                [UNIVERSE setNextBeacon:entity];
            }
        }
        return JS_UNDEFINED;
        break;

    case kWaypoint_beaconLabel:
        sValue = OOStringFromJSValue(context, value);
        if (sValue != nil) {
            [entity setBeaconLabel:sValue];
            return JS_UNDEFINED;
        }
        break;

    case kWaypoint_orientation:
        if (JSValueToQuaternion(context, value, &qValue)) {
            [entity setNormalOrientation:qValue];
            return JS_UNDEFINED;
        }
        break;

    case kWaypoint_size:
        if (JS_ToFloat64(context, &fValue, value) == 0) {
            if (fValue > 0.0) {
                [entity setSize:fValue];
                return JS_UNDEFINED;
            }
        }
        break;

    default:
        OOJSReportBadPropertySelector(context, this, magic, sWaypointProperties, OOJS_COUNT(sWaypointProperties));
        return OOJSNativeFailure(context);
    }

    OOJSReportBadPropertyValue(context, this, magic, sWaypointProperties, OOJS_COUNT(sWaypointProperties), value);
    return OOJSNativeFailure(context);

    OOJS_NATIVE_EXIT
}
