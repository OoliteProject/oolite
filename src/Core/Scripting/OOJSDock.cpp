/*
OOJSDock.m (QuickJS-ng)

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

#include "OOJSDock.h"

#include "DockEntity.h"
#include "EntityOOJavaScriptExtensions.h"
#include "GameController.h"
#include "OOJSEntity.h"
#include "OOJSPlayer.h"
#include "OOJSShip.h"
#include "OOJavaScriptEngine.h"

static JSClassID sDockClassID;

static bool JSDockGetDockEntity(JSContext* context, JSValueConst stationObj,
                                DockEntity** outEntity);
static bool JSDockGetShipEntity(JSContext* context, JSValueConst shipObj,
                                ShipEntity** outEntity);

static JSValue DockIsQueued(OOJS_NATIVE_ARGS);

static JSValue DockGetProperty(OOJS_GETTER_ARGS);
static JSValue DockSetProperty(OOJS_SETTER_ARGS);

static JSClassDef sDockClass = {
    .class_name = "Dock",
    .finalizer = OOJSCxxObjectWrapperFinalize,
};

namespace {

enum class DockProperty : std::int16_t {
  // Property IDs
  kAllowsDocking,
  kDisallowedDockingCollides,
  kAllowsLaunching,
  kDockingQueueLength,
  kLaunchingQueueLength
};

}  // namespace

static const JSCFunctionListEntry sDockProperties[] = {
    // JS name, getter, setter, ID
    OOJS_PROPERTY_RW("allowsDocking", DockGetProperty, DockSetProperty,
                     DockProperty::kAllowsDocking),
    OOJS_PROPERTY_RW("disallowedDockingCollides", DockGetProperty,
                     DockSetProperty, DockProperty::kDisallowedDockingCollides),
    OOJS_PROPERTY_RW("allowsLaunching", DockGetProperty, DockSetProperty,
                     DockProperty::kAllowsLaunching),
    OOJS_PROPERTY_RO("dockingQueueLength", DockGetProperty,
                     DockProperty::kDockingQueueLength),
    OOJS_PROPERTY_RO("launchingQueueLength", DockGetProperty,
                     DockProperty::kLaunchingQueueLength),
};

static const JSCFunctionListEntry sDockMethods[] = {
    // JS name, min args, function
    JS_CFUNC_DEF("isQueued", 1, DockIsQueued),
};

void InitOOJSDock(JSContext* context, JSValueConst global) {
  OOJSRegisterClass(&sDockClassID, &sDockClass);

  JSValue parentPrototype = JS_GetClassProto(context, JSShipClassID());
  OOCAssert(JS_IsObject(parentPrototype),
            "Ship must be initialized before Dock.");
  OOJSInitClass(context, global, sDockClassID, parentPrototype,
                OOJSUnconstructableConstruct, 0, sDockProperties,
                OOJS_COUNT(sDockProperties), sDockMethods,
                OOJS_COUNT(sDockMethods), nullptr, 0);
  JS_FreeValue(context, parentPrototype);

  OOJSRegisterObjectConverter(sDockClassID, OOJSEntityObjectConverter);
  OOJSRegisterSubclass(sDockClassID, JSShipClassID());
}

JSClassID JSDockClassID() { return sDockClassID; }

/*	As in the SpiderMonkey version, these return false without an exception
   for stale references (nil entity) and for entities of the wrong native class;
        OOJSEntityGetEntity() throws if the object is not an Entity at all.
*/
static bool JSDockGetDockEntity(JSContext* context, JSValueConst dockObj,
                                DockEntity** outEntity) {
  OOJS_PROFILE_ENTER

  bool result;
  Entity* entity = nullptr;  // the slot holds the C++ entity

  if (outEntity == nullptr) return false;
  *outEntity = nullptr;

  result = OOJSEntityGetEntity(context, dockObj, &entity);
  if (!result) return false;

  // A dock's object is a ship's: its C++ part says it is a dock.
  DockEntity* dock = oo::ToDock(entity);
  if (dock == nullptr) return false;

  *outEntity = dock;
  return true;

  OOJS_PROFILE_EXIT
}

static bool JSDockGetShipEntity(JSContext* context, JSValueConst shipObj,
                                ShipEntity** outEntity) {
  OOJS_PROFILE_ENTER

  bool result;
  Entity* entity = nullptr;  // the slot holds the C++ entity

  if (outEntity == nullptr) return false;
  *outEntity = nullptr;

  result = OOJSEntityGetEntity(context, shipObj, &entity);
  if (!result) return false;

  if (!(oo::ToShip(entity) != nullptr)) return false;

  *outEntity = oo::ToShip(entity);
  return true;

  OOJS_PROFILE_EXIT
}

// The bodies of DockEntity's class questions, which DockEntity's overrides
// call.
std::optional<std::string> OOJSDockJSClassName() { return std::string("Dock"); }

static JSValue DockGetProperty(OOJS_GETTER_ARGS) {
  OOJS_NATIVE_ENTER(context)

  DockEntity* entity = nullptr;

  if (!JSDockGetDockEntity(context, thisObj, &entity))
    return OOJSNativeFailure(context);
  if (entity == nullptr) {
    return JS_UNDEFINED;
  }

  switch (static_cast<DockProperty>(magic)) {
    using enum DockProperty;
    case kAllowsDocking:
      return OOJSValueFromBOOL(
          (entity != nullptr ? entity->allowsDocking() : false));

    case kDisallowedDockingCollides:
      return OOJSValueFromBOOL(
          (entity != nullptr ? entity->disallowedDockingCollides() : false));

    case kAllowsLaunching:
      return OOJSValueFromBOOL(
          (entity != nullptr ? entity->allowsLaunching() : false));

    case kDockingQueueLength:
      return JS_NewNumber(
          context,
          (entity != nullptr ? entity->countOfShipsInDockingQueue() : 0));

    case kLaunchingQueueLength:
      return JS_NewNumber(
          context,
          (entity != nullptr ? entity->countOfShipsInLaunchQueue() : 0));

    default:
      OOJSReportBadPropertySelector(context, thisObj, magic, sDockProperties,
                                    OOJS_COUNT(sDockProperties));
      return OOJSNativeFailure(context);
  }

  OOJS_NATIVE_EXIT
}

static JSValue DockSetProperty(OOJS_SETTER_ARGS) {
  OOJS_NATIVE_ENTER(context)

  DockEntity* entity = nullptr;
  int bValue;
  //	int32_t						iValue;

  if (!JSDockGetDockEntity(context, thisObj, &entity))
    return OOJSNativeFailure(context);
  if (entity == nullptr) return JS_UNDEFINED;

  switch (static_cast<DockProperty>(magic)) {
    using enum DockProperty;
    case kAllowsDocking:
      if ((bValue = JS_ToBool(context, value)) >= 0) {
        if (entity != nullptr) entity->setAllowsDocking(bValue);
        return JS_UNDEFINED;
      }
      break;

    case kAllowsLaunching:
      if ((bValue = JS_ToBool(context, value)) >= 0) {
        if (entity != nullptr) entity->setAllowsLaunching(bValue);
        return JS_UNDEFINED;
      }
      break;

    case kDisallowedDockingCollides:
      if ((bValue = JS_ToBool(context, value)) >= 0) {
        if (entity != nullptr) entity->setDisallowedDockingCollides(bValue);
        return JS_UNDEFINED;
      }
      break;

    default:
      OOJSReportBadPropertySelector(context, thisObj, magic, sDockProperties,
                                    OOJS_COUNT(sDockProperties));
      return OOJSNativeFailure(context);
  }

  OOJSReportBadPropertyValue(context, thisObj, magic, sDockProperties,
                             OOJS_COUNT(sDockProperties), value);
  return OOJSNativeFailure(context);

  OOJS_NATIVE_EXIT
}

// *** Methods ***

static JSValue DockIsQueued(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  bool result = false;
  DockEntity* dock = nullptr;

  JSDockGetDockEntity(context, OOJS_THIS, &dock);
  // SpiderMonkey tolerated returning normally with an error pending; QuickJS
  // does not.
  if (JS_HasException(context)) return JS_EXCEPTION;
  if (argc == 0) {
    cxx_OOJSReportBadArguments(context, "Dock", "isQueued", MIN(argc, 1),
                               OOJS_ARGV, std::nullopt, "ship");
    return OOJSNativeFailure(context);
  }
  ShipEntity* ship = nullptr;
  // The SpiderMonkey version did not check that argv[0] is an object; a
  // non-object is treated as no ship.
  if (JS_IsObject(OOJS_ARGV[0])) {
    JSDockGetShipEntity(context, OOJS_ARGV[0], &ship);
    if (JS_HasException(context)) return JS_EXCEPTION;
  }
  if (ship != nullptr) {
    result = (dock != nullptr ? dock->shipIsInDockingQueue(ship) : false);
  }

  OOJS_RETURN_BOOL(result);

  OOJS_NATIVE_EXIT
}
