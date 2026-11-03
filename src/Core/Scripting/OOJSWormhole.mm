/*
OOJSWormhole.m (QuickJS-ng)

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

#import "OOJSWormhole.h"
#import "EntityOOJavaScriptExtensions.h"
#import "OOJSEntity.h"
#import "OOJSVector.h"
#import "OOJavaScriptEngine.h"
#import "WormholeEntity.h"

/*
        C++20 since bead oo-ykoy, converted the way bead oo-ppc converted OOJSVector.mm (proposed
        ADR-0056 amendment oo-ppc). The JS class was already C++ on the scripting layer (QuickJS-ng);
        OOJS_NATIVE_ENTER/EXIT and OOJS_PROFILE_ENTER/EXIT are C++ try/catch and scope guards
        (OOJSEngineNativeWrappers.h); BOOL/YES/NO are bool/true/false. The category on
        WormholeEntity became two free functions (its -oo_jsClassID answers JSWormholeClassID()),
        and its methods moved to OOJSWormhole+ObjCBridge.mm (amendment oo-ykoy). Messages to
        classes that are still Objective-C (WormholeEntity, Entity) stay as they are, which is why
        the file is still .mm until Phase 4.
*/

static JSClassID sWormholeClassID;

static bool JSWormholeGetWormholeEntity(JSContext* context, JSValueConst wormholeObj, WormholeEntity** outEntity);

static JSValue WormholeGetProperty(OOJS_GETTER_ARGS);

static JSClassDef sWormholeClass = {
    .class_name = "Wormhole",
    .finalizer = OOJSObjectWrapperFinalize,
};

enum {
    // Property IDs
    kWormhole_arrivalTime,
    kWormhole_destination,
    kWormhole_expiryTime,
    kWormhole_origin

};

/*	All Wormhole properties are read-only, so the SpiderMonkey setProperty hook
        (which only reported a bad property selector) was unreachable for them
        and is not ported.
*/
static const JSCFunctionListEntry sWormholeProperties[] = {
    // JS name, getter, setter, ID
    OOJS_PROPERTY_RO("arrivalTime", WormholeGetProperty, kWormhole_arrivalTime),
    OOJS_PROPERTY_RO("destination", WormholeGetProperty, kWormhole_destination),
    OOJS_PROPERTY_RO("expiryTime", WormholeGetProperty, kWormhole_expiryTime),
    OOJS_PROPERTY_RO("origin", WormholeGetProperty, kWormhole_origin),
};

// No Wormhole methods.

void InitOOJSWormhole(JSContext* context, JSValueConst global)
{
    OOJSRegisterClass(&sWormholeClassID, &sWormholeClass);

    JSValue parentPrototype = JS_GetClassProto(context, JSEntityClassID());
    OOCAssert(JS_IsObject(parentPrototype), "Entity must be initialized before Wormhole.");
    OOJSInitClass(context, global, sWormholeClassID, parentPrototype, OOJSUnconstructableConstruct, 0,
        sWormholeProperties, OOJS_COUNT(sWormholeProperties), NULL, 0, NULL, 0);
    JS_FreeValue(context, parentPrototype);

    OOJSRegisterObjectConverter(sWormholeClassID, OOJSBasicPrivateObjectConverter);
    OOJSRegisterSubclass(sWormholeClassID, JSEntityClassID());
}

JSClassID JSWormholeClassID(void)
{
    return sWormholeClassID;
}

static bool JSWormholeGetWormholeEntity(JSContext* context, JSValueConst wormholeObj, WormholeEntity** outEntity)
{
    OOJS_PROFILE_ENTER

    bool result;
    Entity* entity = nil;

    if (outEntity == NULL)
        return false;
    *outEntity = nil;

    result = OOJSEntityGetEntity(context, wormholeObj, &entity);
    if (!result)
        return false;

    if (![entity isKindOfClass:[WormholeEntity class]])
        return false;

    *outEntity = (WormholeEntity*)entity;
    return true;

    OOJS_PROFILE_EXIT
}

// The bodies of WormholeEntity (OOJavaScriptExtensions), whose methods are in
// OOJSWormhole+ObjCBridge.mm until WormholeEntity converts (proposed ADR-0056 amendments oo-ppc
// and oo-ykoy).
std::optional<std::string> OOJSWormholeJSClassName(void)
{
    return std::string("Wormhole");
}

bool OOJSWormholeIsVisibleToScripts(void)
{
    return true;
}

static JSValue WormholeGetProperty(OOJS_GETTER_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    WormholeEntity* entity = nil;
    id result = nil;

    if (!JSWormholeGetWormholeEntity(context, thisObj, &entity))
        return OOJSNativeFailure(context);
    if (entity == nil) {
        return JS_UNDEFINED;
    }

    switch (magic) {
    case kWormhole_arrivalTime:
        return JS_NewNumber(context, [entity arrivalTime]);

    case kWormhole_destination:
        return JS_NewNumber(context, [entity destination]);

    case kWormhole_expiryTime:
        return JS_NewNumber(context, [entity expiryTime]);

    case kWormhole_origin:
        return JS_NewNumber(context, [entity origin]);

    default:
        OOJSReportBadPropertySelector(context, thisObj, magic, sWormholeProperties, OOJS_COUNT(sWormholeProperties));
        return OOJSNativeFailure(context);
    }

    return OOJSValueFromNativeObject(context, result);

    OOJS_NATIVE_EXIT
}
