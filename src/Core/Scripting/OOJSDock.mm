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

#import "OOJSDock.h"
#import "DockEntity.h"
#import "EntityOOJavaScriptExtensions.h"
#import "OOJSEntity.h"
#import "OOJSPlayer.h"
#import "OOJSShip.h"
#import "OOJavaScriptEngine.h"

#import "GameController.h"

/*
        C++20 since bead oo-zbx3, converted the way bead oo-ppc converted OOJSVector.mm (proposed
        ADR-0056 amendment oo-ppc). The JS class was already C++ on the scripting layer (QuickJS-ng);
        OOJS_NATIVE_ENTER/EXIT and OOJS_PROFILE_ENTER/EXIT are C++ try/catch and scope guards
        (OOJSEngineNativeWrappers.h); BOOL/YES/NO are bool/true/false. The category on DockEntity
        became a free function (the dock's JS class is JSDockClassID(), DockEntity::jsClassID()),
        and its methods moved to DockEntity. Messages to classes that are still Objective-C
        (Entity) stay as they are, which is why the file is still .mm until Phase 4.
*/

static JSClassID sDockClassID;

static bool JSDockGetDockEntity(JSContext* context, JSValueConst stationObj, DockEntity** outEntity);
static bool JSDockGetShipEntity(JSContext* context, JSValueConst shipObj, ShipEntity** outEntity);

static JSValue DockIsQueued(OOJS_NATIVE_ARGS);

static JSValue DockGetProperty(OOJS_GETTER_ARGS);
static JSValue DockSetProperty(OOJS_SETTER_ARGS);

static JSClassDef sDockClass = {
    .class_name = "Dock",
    .finalizer = OOJSCxxObjectWrapperFinalize,
};

enum {
    // Property IDs
    kDock_allowsDocking,
    kDock_disallowedDockingCollides,
    kDock_allowsLaunching,
    kDock_dockingQueueLength,
    kDock_launchingQueueLength
};

static const JSCFunctionListEntry sDockProperties[] = {
    // JS name, getter, setter, ID
    OOJS_PROPERTY_RW("allowsDocking", DockGetProperty, DockSetProperty, kDock_allowsDocking),
    OOJS_PROPERTY_RW("disallowedDockingCollides", DockGetProperty, DockSetProperty, kDock_disallowedDockingCollides),
    OOJS_PROPERTY_RW("allowsLaunching", DockGetProperty, DockSetProperty, kDock_allowsLaunching),
    OOJS_PROPERTY_RO("dockingQueueLength", DockGetProperty, kDock_dockingQueueLength),
    OOJS_PROPERTY_RO("launchingQueueLength", DockGetProperty, kDock_launchingQueueLength),
};

static const JSCFunctionListEntry sDockMethods[] = {
    // JS name, min args, function
    JS_CFUNC_DEF("isQueued", 1, DockIsQueued),
};

void InitOOJSDock(JSContext* context, JSValueConst global)
{
    OOJSRegisterClass(&sDockClassID, &sDockClass);

    JSValue parentPrototype = JS_GetClassProto(context, JSShipClassID());
    OOCAssert(JS_IsObject(parentPrototype), "Ship must be initialized before Dock.");
    OOJSInitClass(context, global, sDockClassID, parentPrototype, OOJSUnconstructableConstruct, 0,
        sDockProperties, OOJS_COUNT(sDockProperties), sDockMethods, OOJS_COUNT(sDockMethods), NULL, 0);
    JS_FreeValue(context, parentPrototype);

    OOJSRegisterObjectConverter(sDockClassID, OOJSEntityObjectConverter);
    OOJSRegisterSubclass(sDockClassID, JSShipClassID());
}

JSClassID JSDockClassID(void)
{
    return sDockClassID;
}

/*	As in the SpiderMonkey version, these return false without an exception for
        stale references (nil entity) and for entities of the wrong native class;
        OOJSEntityGetEntity() throws if the object is not an Entity at all.
*/
static bool JSDockGetDockEntity(JSContext* context, JSValueConst dockObj, DockEntity** outEntity)
{
    OOJS_PROFILE_ENTER

    bool result;
    Entity* entity = nullptr; // the slot holds the C++ entity

    if (outEntity == NULL)
        return false;
    *outEntity = nil;

    result = OOJSEntityGetEntity(context, dockObj, &entity);
    if (!result)
        return false;

    // A dock's object is a ship's: its C++ part says it is a dock,
    // where -isKindOfClass:[DockEntity class] did.
    DockEntity* dock = oo::ToDock(entity);
    if (dock == nullptr)
        return false;

    *outEntity = dock;
    return true;

    OOJS_PROFILE_EXIT
}

static bool JSDockGetShipEntity(JSContext* context, JSValueConst shipObj, ShipEntity** outEntity)
{
    OOJS_PROFILE_ENTER

    bool result;
    Entity* entity = nullptr; // the slot holds the C++ entity

    if (outEntity == NULL)
        return false;
    *outEntity = nil;

    result = OOJSEntityGetEntity(context, shipObj, &entity);
    if (!result)
        return false;

    if (!(oo::ToShip(entity) != nullptr))
        return false;

    *outEntity = oo::ToShip(entity);
    return true;

    OOJS_PROFILE_EXIT
}

// The bodies of DockEntity's class questions, which DockEntity's overrides call.
std::optional<std::string> OOJSDockJSClassName(void)
{
    return std::string("Dock");
}

static JSValue DockGetProperty(OOJS_GETTER_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    DockEntity* entity = nil;

    if (!JSDockGetDockEntity(context, thisObj, &entity))
        return OOJSNativeFailure(context);
    if (entity == nil) {
        return JS_UNDEFINED;
    }

    switch (magic) {
    case kDock_allowsDocking:
        return OOJSValueFromBOOL((entity != nullptr ? entity->allowsDocking() : false));

    case kDock_disallowedDockingCollides:
        return OOJSValueFromBOOL((entity != nullptr ? entity->disallowedDockingCollides() : false));

    case kDock_allowsLaunching:
        return OOJSValueFromBOOL((entity != nullptr ? entity->allowsLaunching() : false));

    case kDock_dockingQueueLength:
        return JS_NewNumber(context, (entity != nullptr ? entity->countOfShipsInDockingQueue() : 0));

    case kDock_launchingQueueLength:
        return JS_NewNumber(context, (entity != nullptr ? entity->countOfShipsInLaunchQueue() : 0));

    default:
        OOJSReportBadPropertySelector(context, thisObj, magic, sDockProperties, OOJS_COUNT(sDockProperties));
        return OOJSNativeFailure(context);
    }

    OOJS_NATIVE_EXIT
}

static JSValue DockSetProperty(OOJS_SETTER_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    DockEntity* entity = nil;
    int bValue;
    //	int32_t						iValue;

    if (!JSDockGetDockEntity(context, thisObj, &entity))
        return OOJSNativeFailure(context);
    if (entity == nil)
        return JS_UNDEFINED;

    switch (magic) {
    case kDock_allowsDocking:
        if ((bValue = JS_ToBool(context, value)) >= 0) {
            if (entity != nullptr)
                entity->setAllowsDocking(bValue);
            return JS_UNDEFINED;
        }
        break;

    case kDock_allowsLaunching:
        if ((bValue = JS_ToBool(context, value)) >= 0) {
            if (entity != nullptr)
                entity->setAllowsLaunching(bValue);
            return JS_UNDEFINED;
        }
        break;

    case kDock_disallowedDockingCollides:
        if ((bValue = JS_ToBool(context, value)) >= 0) {
            if (entity != nullptr)
                entity->setDisallowedDockingCollides(bValue);
            return JS_UNDEFINED;
        }
        break;

    default:
        OOJSReportBadPropertySelector(context, thisObj, magic, sDockProperties, OOJS_COUNT(sDockProperties));
        return OOJSNativeFailure(context);
    }

    OOJSReportBadPropertyValue(context, thisObj, magic, sDockProperties, OOJS_COUNT(sDockProperties), value);
    return OOJSNativeFailure(context);

    OOJS_NATIVE_EXIT
}

// *** Methods ***

static JSValue DockIsQueued(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    bool result = false;
    DockEntity* dock = nil;

    JSDockGetDockEntity(context, OOJS_THIS, &dock);
    // SpiderMonkey tolerated returning normally with an error pending; QuickJS does not.
    if (JS_HasException(context))
        return JS_EXCEPTION;
    if (argc == 0) {
        cxx_OOJSReportBadArguments(context, "Dock", "isQueued", MIN(argc, 1), OOJS_ARGV, std::nullopt, "ship");
        return OOJSNativeFailure(context);
    }
    ShipEntity* ship = nil;
    // The SpiderMonkey version did not check that argv[0] is an object; a non-object is treated as no ship.
    if (JS_IsObject(OOJS_ARGV[0])) {
        JSDockGetShipEntity(context, OOJS_ARGV[0], &ship);
        if (JS_HasException(context))
            return JS_EXCEPTION;
    }
    if (ship != nil) {
        result = (dock != nullptr ? dock->shipIsInDockingQueue(ship) : false);
    }

    OOJS_RETURN_BOOL(result);

    OOJS_NATIVE_EXIT
}
