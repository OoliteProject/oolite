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
#import "OOJSEntity.h"
#import "OOJSQuaternion.h"
#import "OOJSVector.h"
#import "OOJavaScriptEngine.h"
#import "OOWaypointEntity.h"

/*
        C++20 since bead oo-mae5, converted the way bead oo-ppc converted OOJSVector.mm (proposed
        ADR-0056 amendment oo-ppc). The JS class was already C++ on QuickJS-ng;
        OOJS_NATIVE_ENTER/EXIT and OOJS_PROFILE_ENTER/EXIT are C++ try/catch and scope guards
        (OOJSEngineNativeWrappers.h); BOOL/YES/NO are bool/true/false. The category on OOWaypointEntity
        became free functions, and its methods and interface moved to a bridge file of the binding
        (amendment oo-ykoy), then onto the OOWaypointEntity facade in OOWaypointEntity+ObjCBridge.mm
        (bead oo-9ht.50, amendment oo-6ia4 item 3). Messages to classes that are still Objective-C
        (OOWaypointEntity, Entity, Universe, PlayerEntity) stay as they are, which is why the file is
        still .mm until Phase 4.
*/

static JSClassID sWaypointClassID;

static bool JSWaypointGetWaypointEntity(JSContext* context, JSValueConst waypointObj, OOWaypointEntity** outEntity, OOBeaconEntityObject** outObject);

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
    OOCAssert(JS_IsObject(parentPrototype), "Entity must be initialized before Waypoint.");
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

static bool JSWaypointGetWaypointEntity(JSContext* context, JSValueConst waypointObj, OOWaypointEntity** outEntity, OOBeaconEntityObject** outObject)
{
    OOJS_PROFILE_ENTER

    bool result;
    Entity* entity = nil;

    if (outEntity == NULL || outObject == NULL)
        return false;
    *outEntity = nullptr;
    *outObject = nil;

    result = OOJSEntityGetEntity(context, waypointObj, &entity);
    if (!result)
        return false;

    // The object is the root's facade: a waypoint is its C++ part (a nil or other entity is not, as
    // -isKindOfClass: answered). The object answers the beacon selectors.
    OOWaypointEntity* waypoint = dynamic_cast<OOWaypointEntity*>(oo::ToCxx(entity));
    if (waypoint == nullptr)
        return false;

    *outEntity = waypoint;
    *outObject = (OOBeaconEntityObject*)entity;
    return true;

    OOJS_PROFILE_EXIT
}

// The bodies of OOWaypointEntity (OOJavaScriptExtensions), which the C++ class's overrides of the
// root's JS members call (the facade that forwarded to them is deleted).
std::optional<std::string> OOJSWaypointJSClassName(void)
{
    return std::string("Waypoint");
}

bool OOJSWaypointIsVisibleToScripts(void)
{
    return true;
}

static JSValue WaypointGetProperty(OOJS_GETTER_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    OOWaypointEntity* waypoint = nullptr;
    OOBeaconEntityObject* entity = nil;
    oo::PList result; // null: nil
    std::optional<std::string> text;
    Quaternion q = kIdentityQuaternion;

    if (!JSWaypointGetWaypointEntity(context, thisObj, &waypoint, &entity))
        return OOJSNativeFailure(context);
    if (entity == nil) {
        return JS_UNDEFINED;
    }

    switch (magic) {
    case kWaypoint_beaconCode:
        text = [entity beaconCode];
        if (text.has_value())
            result = oo::PList(*text);
        break;

    case kWaypoint_beaconLabel:
        text = [entity beaconLabel];
        if (text.has_value())
            result = oo::PList(*text);
        break;

    case kWaypoint_orientation:
        q = [entity orientation];
        if (!waypoint->getOriented()) {
            q = kZeroQuaternion;
        }
        OOJS_RETURN_QUATERNION(q);

    case kWaypoint_size:
        return JS_NewNumber(context, waypoint->size());

    default:
        OOJSReportBadPropertySelector(context, thisObj, magic, sWaypointProperties, OOJS_COUNT(sWaypointProperties));
        return OOJSNativeFailure(context);
    }

    return OOJSValueFromPList(context, result);

    OOJS_NATIVE_EXIT
}

static JSValue WaypointSetProperty(OOJS_SETTER_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    OOWaypointEntity* waypoint = nullptr;
    OOBeaconEntityObject* entity = nil;
    double fValue;
    std::optional<std::string> sValue;
    Quaternion qValue;

    if (!JSWaypointGetWaypointEntity(context, thisObj, &waypoint, &entity))
        return OOJSNativeFailure(context);
    if (entity == nil)
        return JS_UNDEFINED;

    switch (magic) {
    case kWaypoint_beaconCode:
        sValue = cxx_OOStringFromJSValue(context, value);
        if (!sValue.has_value() || sValue->empty()) {
            if ([entity isBeacon]) {
                [UNIVERSE clearBeacon:entity];
                if ((PLAYER != nullptr ? (::Entity<OOBeaconEntity>*)PLAYER->PlayerEntity::nextBeacon() : (::Entity<OOBeaconEntity>*)nullptr) == entity) // qualified: the final overrider, so the binding test stands in for it
                {
                    if (PLAYER != nullptr)
                        PLAYER->PlayerEntity::setCompassMode(COMPASS_MODE_PLANET); // qualified: the final overrider, so the binding test stands in for it
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
        sValue = cxx_OOStringFromJSValue(context, value);
        if (sValue.has_value()) {
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
                waypoint->setSize(fValue);
                return JS_UNDEFINED;
            }
        }
        break;

    default:
        OOJSReportBadPropertySelector(context, thisObj, magic, sWaypointProperties, OOJS_COUNT(sWaypointProperties));
        return OOJSNativeFailure(context);
    }

    OOJSReportBadPropertyValue(context, thisObj, magic, sWaypointProperties, OOJS_COUNT(sWaypointProperties), value);
    return OOJSNativeFailure(context);

    OOJS_NATIVE_EXIT
}
