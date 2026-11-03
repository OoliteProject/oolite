/*
OOJSExhaustPlume.m (QuickJS-ng)

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

#import "OOJSExhaustPlume.h"
#import "EntityOOJavaScriptExtensions.h"
#import "OOExhaustPlumeEntity.h"
#import "OOJSEntity.h"
#import "OOJSVector.h"
#import "OOJavaScriptEngine.h"
#import "ShipEntity.h"

/*
        C++20 since bead oo-utlm, converted the way bead oo-ppc converted OOJSVector.mm (proposed
        ADR-0056 amendment oo-ppc). The JS class was already C++ on QuickJS-ng;
        OOJS_NATIVE_ENTER/EXIT and OOJS_PROFILE_ENTER/EXIT are C++ try/catch and scope guards
        (OOJSEngineNativeWrappers.h); BOOL/YES/NO are bool/true/false. The category on
        OOExhaustPlumeEntity became free functions, and its methods and interface moved to a
        bridge file of the binding (amendment oo-ykoy), then onto the OOExhaustPlumeEntity facade in
        OOExhaustPlumeEntity+ObjCBridge.mm (bead oo-9ht.48, amendment oo-6ia4 item 3). Messages to
        classes that are still Objective-C (OOExhaustPlumeEntity, ShipEntity, Entity) stay as they are,
        which is why the file is still .mm until Phase 4.
*/

static JSClassID sExhaustPlumeClassID;

static bool JSExhaustPlumeGetExhaustPlumeEntity(JSContext* context, JSValueConst jsobj, OOExhaustPlumeEntity** outEntity);

static JSValue ExhaustPlumeGetProperty(OOJS_GETTER_ARGS);
static JSValue ExhaustPlumeSetProperty(OOJS_SETTER_ARGS);

static JSValue ExhaustPlumeRemove(OOJS_NATIVE_ARGS);

static JSClassDef sExhaustPlumeClass = {
    .class_name = "ExhaustPlume",
    .finalizer = OOJSObjectWrapperFinalize,
};

enum {
    // Property IDs
    kExhaustPlume_size
};

static const JSCFunctionListEntry sExhaustPlumeProperties[] = {
    // JS name, getter, setter, ID
    OOJS_PROPERTY_RW("size", ExhaustPlumeGetProperty, ExhaustPlumeSetProperty, kExhaustPlume_size),
};

static const JSCFunctionListEntry sExhaustPlumeMethods[] = {
    // JS name, min args, function
    JS_CFUNC_DEF("remove", 0, ExhaustPlumeRemove),
};

void InitOOJSExhaustPlume(JSContext* context, JSValueConst global)
{
    OOJSRegisterClass(&sExhaustPlumeClassID, &sExhaustPlumeClass);

    JSValue parentPrototype = JS_GetClassProto(context, JSEntityClassID());
    OOCAssert(JS_IsObject(parentPrototype), "Entity must be initialized before ExhaustPlume.");
    OOJSInitClass(context, global, sExhaustPlumeClassID, parentPrototype, OOJSUnconstructableConstruct, 0,
        sExhaustPlumeProperties, OOJS_COUNT(sExhaustPlumeProperties), sExhaustPlumeMethods, OOJS_COUNT(sExhaustPlumeMethods), NULL, 0);
    JS_FreeValue(context, parentPrototype);

    OOJSRegisterObjectConverter(sExhaustPlumeClassID, OOJSBasicPrivateObjectConverter);
    OOJSRegisterSubclass(sExhaustPlumeClassID, JSEntityClassID());
}

JSClassID JSExhaustPlumeClassID(void)
{
    return sExhaustPlumeClassID;
}

static bool JSExhaustPlumeGetExhaustPlumeEntity(JSContext* context, JSValueConst jsobj, OOExhaustPlumeEntity** outEntity)
{
    OOJS_PROFILE_ENTER

    bool result;
    Entity* entity = nil;

    if (outEntity == NULL)
        return false;
    *outEntity = nil;

    result = OOJSEntityGetEntity(context, jsobj, &entity);
    if (!result)
        return false;

    if (![entity isKindOfClass:[OOExhaustPlumeEntity class]])
        return false;

    *outEntity = (OOExhaustPlumeEntity*)entity;
    return true;

    OOJS_PROFILE_EXIT
}

// The bodies of OOExhaustPlumeEntity (OOJavaScriptExtensions), whose methods are on the
// OOExhaustPlumeEntity facade, in OOExhaustPlumeEntity+ObjCBridge.mm (bead oo-9ht.48), until that
// facade goes (oo-9ht.110; proposed ADR-0056 amendments oo-ppc, oo-ykoy and oo-6ia4).
std::optional<std::string> OOJSExhaustPlumeJSClassName(void)
{
    return std::string("ExhaustPlume");
}

bool OOJSExhaustPlumeIsVisibleToScripts(void)
{
    return true;
}

static JSValue ExhaustPlumeGetProperty(OOJS_GETTER_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    OOExhaustPlumeEntity* entity = nil;
    id result = nil;

    if (!JSExhaustPlumeGetExhaustPlumeEntity(context, thisObj, &entity))
        return OOJSNativeFailure(context);
    if (entity == nil) {
        return JS_UNDEFINED;
    }

    switch (magic) {
    case kExhaustPlume_size:
        OOJS_RETURN_VECTOR([entity scale]);

    default:
        OOJSReportBadPropertySelector(context, thisObj, magic, sExhaustPlumeProperties, OOJS_COUNT(sExhaustPlumeProperties));
        return OOJSNativeFailure(context);
    }

    return OOJSValueFromNativeObject(context, result);

    OOJS_NATIVE_EXIT
}

static JSValue ExhaustPlumeSetProperty(OOJS_SETTER_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    OOExhaustPlumeEntity* entity = nil;
    Vector vValue;

    if (!JSExhaustPlumeGetExhaustPlumeEntity(context, thisObj, &entity))
        return OOJSNativeFailure(context);
    if (entity == nil)
        return JS_UNDEFINED;

    switch (magic) {
    case kExhaustPlume_size:
        if (JSValueToVector(context, value, &vValue)) {
            [entity setScale:vValue];
            return JS_UNDEFINED;
        }
        break;

    default:
        OOJSReportBadPropertySelector(context, thisObj, magic, sExhaustPlumeProperties, OOJS_COUNT(sExhaustPlumeProperties));
        return OOJSNativeFailure(context);
    }

    OOJSReportBadPropertyValue(context, thisObj, magic, sExhaustPlumeProperties, OOJS_COUNT(sExhaustPlumeProperties), value);
    return OOJSNativeFailure(context);

    OOJS_NATIVE_EXIT
}

// *** Methods ***

#define GET_THIS_EXHAUSTPLUME(THISENT)                                                      \
    do {                                                                                    \
        if (EXPECT_NOT(!JSExhaustPlumeGetExhaustPlumeEntity(context, OOJS_THIS, &THISENT))) \
            return OOJSNativeFailure(context); /* Exception */                              \
        if (OOIsStaleEntity(THISENT))                                                       \
            OOJS_RETURN_VOID;                                                               \
    } while (0)

static JSValue ExhaustPlumeRemove(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    OOExhaustPlumeEntity* thisEnt = nil;
    GET_THIS_EXHAUSTPLUME(thisEnt);

    ShipEntity* parent = [thisEnt owner];
    [parent removeExhaust:thisEnt];

    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}
