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

#include "OOJSWaypoint.h"

#include "EntityOOJavaScriptExtensions.h"
#include "OOJSEntity.h"
#include "OOJSQuaternion.h"
#include "OOJSVector.h"
#include "OOJavaScriptEngine.h"
#include "OOWaypointEntity.h"

/*
        The class is a static JSClassDef registered with OOJSRegisterClass(),
        its properties a JSCFunctionListEntry table whose magic is the property
        ID, as in #768.

        OOJS_NATIVE_ENTER/EXIT and OOJS_PROFILE_ENTER/EXIT are C++ try/catch and
        scope guards (OOJSEngineNativeWrappers.h). The category on
        OOWaypointEntity is free functions; the natives call the C++
        OOWaypointEntity's members.
*/

static JSClassID sWaypointClassID;

static bool JSWaypointGetWaypointEntity(JSContext* context,
                                        JSValueConst waypointObj,
                                        OOWaypointEntity** outEntity);

static JSValue WaypointGetProperty(OOJS_GETTER_ARGS);
static JSValue WaypointSetProperty(OOJS_SETTER_ARGS);

static JSClassDef sWaypointClass = {
    .class_name = "Waypoint",
    .finalizer =
        OOJSCxxObjectWrapperFinalize,  // the slot holds an OOJSEntityHolder
};

enum {
  // Property IDs
  kWaypoint_beaconCode,
  kWaypoint_beaconLabel,
  kWaypoint_orientation,  // overrides entity as waypoints can be unoriented
  kWaypoint_size
};

static const JSCFunctionListEntry sWaypointProperties[] = {
    // JS name, getter, setter, ID
    OOJS_PROPERTY_RW("beaconCode", WaypointGetProperty, WaypointSetProperty,
                     kWaypoint_beaconCode),
    OOJS_PROPERTY_RW("beaconLabel", WaypointGetProperty, WaypointSetProperty,
                     kWaypoint_beaconLabel),
    OOJS_PROPERTY_RW("orientation", WaypointGetProperty, WaypointSetProperty,
                     kWaypoint_orientation),
    OOJS_PROPERTY_RW("size", WaypointGetProperty, WaypointSetProperty,
                     kWaypoint_size),
};

// No Waypoint methods.

void InitOOJSWaypoint(JSContext* context, JSValueConst global) {
  OOJSRegisterClass(&sWaypointClassID, &sWaypointClass);

  JSValue parentPrototype = JS_GetClassProto(context, JSEntityClassID());
  OOCAssert(JS_IsObject(parentPrototype),
            "Entity must be initialized before Waypoint.");
  OOJSInitClass(context, global, sWaypointClassID, parentPrototype,
                OOJSUnconstructableConstruct, 0, sWaypointProperties,
                OOJS_COUNT(sWaypointProperties), nullptr, 0, nullptr, 0);
  JS_FreeValue(context, parentPrototype);

  OOJSRegisterObjectConverter(sWaypointClassID, OOJSEntityObjectConverter);
  OOJSRegisterSubclass(sWaypointClassID, JSEntityClassID());
}

JSClassID JSWaypointClassID() { return sWaypointClassID; }

static bool JSWaypointGetWaypointEntity(JSContext* context,
                                        JSValueConst waypointObj,
                                        OOWaypointEntity** outEntity) {
  OOJS_PROFILE_ENTER

  bool result;
  Entity* entity = nullptr;  // the slot holds the C++ entity

  if (outEntity == nullptr) return false;
  *outEntity = nullptr;

  result = OOJSEntityGetEntity(context, waypointObj, &entity);
  if (!result) return false;

  // A waypoint is the C++ OOWaypointEntity (a nil or other entity is not). The
  // natives call its members.
  OOWaypointEntity* waypoint = dynamic_cast<OOWaypointEntity*>(entity);
  if (waypoint == nullptr) return false;

  *outEntity = waypoint;
  return true;

  OOJS_PROFILE_EXIT
}

// The bodies of OOWaypointEntity (OOJavaScriptExtensions), which the C++
// class's overrides of the root's JS members call.
std::optional<std::string> OOJSWaypointJSClassName() {
  return std::string("Waypoint");
}

bool OOJSWaypointIsVisibleToScripts() { return true; }

static JSValue WaypointGetProperty(OOJS_GETTER_ARGS) {
  OOJS_NATIVE_ENTER(context)

  OOWaypointEntity* waypoint = nullptr;
  oo::PList result;  // null: nil
  std::optional<std::string> text;
  Quaternion q = kIdentityQuaternion;

  if (!JSWaypointGetWaypointEntity(context, thisObj, &waypoint))
    return OOJSNativeFailure(context);  // not null after this

  switch (magic) {
    case kWaypoint_beaconCode:
      text = waypoint->beaconCode();
      if (text.has_value()) result = oo::PList(*text);
      break;

    case kWaypoint_beaconLabel:
      text = waypoint->beaconLabel();
      if (text.has_value()) result = oo::PList(*text);
      break;

    case kWaypoint_orientation:
      q = waypoint
              ->getOrientation();  // what the object's -orientation answered
      if (!waypoint->getOriented()) {
        q = kZeroQuaternion;
      }
      OOJS_RETURN_QUATERNION(q);

    case kWaypoint_size:
      return JS_NewNumber(context, waypoint->size());

    default:
      OOJSReportBadPropertySelector(context, thisObj, magic,
                                    sWaypointProperties,
                                    OOJS_COUNT(sWaypointProperties));
      return OOJSNativeFailure(context);
  }

  return OOJSValueFromPList(context, result);

  OOJS_NATIVE_EXIT
}

static JSValue WaypointSetProperty(OOJS_SETTER_ARGS) {
  OOJS_NATIVE_ENTER(context)

  OOWaypointEntity* waypoint = nullptr;
  double fValue;
  std::optional<std::string> sValue;
  Quaternion qValue;

  if (!JSWaypointGetWaypointEntity(context, thisObj, &waypoint))
    return OOJSNativeFailure(context);  // not null after this

  switch (magic) {
    case kWaypoint_beaconCode:
      sValue = cxx_OOStringFromJSValue(context, value);
      if (!sValue.has_value() || sValue->empty()) {
        if (waypoint->isBeacon()) {
          if (UNIVERSE != nullptr) UNIVERSE->clearBeacon(waypoint);
          if ((PLAYER != nullptr ? PLAYER->nextBeaconEntity() : nullptr) ==
              waypoint)  // not virtual, so the binding test stands in for it
          {
            if (PLAYER != nullptr)
              PLAYER->PlayerEntity::setCompassMode(
                  COMPASS_MODE_PLANET);  // qualified: the final overrider, so
                                         // the binding test stands in for it
          }
        }
      } else {
        if (waypoint->isBeacon()) {
          waypoint->setBeaconCode(sValue);
        } else  // Universe needs to update beacon lists in this case only
        {
          waypoint->setBeaconCode(sValue);
          if (UNIVERSE != nullptr) UNIVERSE->setNextBeacon(waypoint);
        }
      }
      return JS_UNDEFINED;
      break;

    case kWaypoint_beaconLabel:
      sValue = cxx_OOStringFromJSValue(context, value);
      if (sValue.has_value()) {
        waypoint->setBeaconLabel(sValue);
        return JS_UNDEFINED;
      }
      break;

    case kWaypoint_orientation:
      if (JSValueToQuaternion(context, value, &qValue)) {
        waypoint->Entity::setNormalOrientation(
            qValue);  // what the object's selector called; qualified: the final
                      // overrider for a waypoint (no override, no subclass), so
                      // the binding test stands in for it
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
      OOJSReportBadPropertySelector(context, thisObj, magic,
                                    sWaypointProperties,
                                    OOJS_COUNT(sWaypointProperties));
      return OOJSNativeFailure(context);
  }

  OOJSReportBadPropertyValue(context, thisObj, magic, sWaypointProperties,
                             OOJS_COUNT(sWaypointProperties), value);
  return OOJSNativeFailure(context);

  OOJS_NATIVE_EXIT
}
