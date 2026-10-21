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
#import "OOCollectionExtractors.h"
#import "OOJSEntity.h"
#import "OOJSVector.h"
#import "OOJavaScriptEngine.h"
#import "WormholeEntity.h"

static JSClassID sWormholeClassID;

static BOOL JSWormholeGetWormholeEntity(JSContext* context, JSValueConst wormholeObj, WormholeEntity** outEntity);

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
    NSCAssert(JS_IsObject(parentPrototype), @"Entity must be initialized before Wormhole.");
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

static BOOL JSWormholeGetWormholeEntity(JSContext* context, JSValueConst wormholeObj, WormholeEntity** outEntity)
{
    OOJS_PROFILE_ENTER

    BOOL result;
    Entity* entity = nil;

    if (outEntity == NULL)
        return NO;
    *outEntity = nil;

    result = OOJSEntityGetEntity(context, wormholeObj, &entity);
    if (!result)
        return NO;

    if (![entity isKindOfClass:[WormholeEntity class]])
        return NO;

    *outEntity = (WormholeEntity*)entity;
    return YES;

    OOJS_PROFILE_EXIT
}

@implementation WormholeEntity (OOJavaScriptExtensions)

- (JSClassID)oo_jsClassID
{
    return sWormholeClassID;
}

- (NSString*)oo_jsClassName
{
    return @"Wormhole";
}

- (BOOL)isVisibleToScripts
{
    return YES;
}

@end

static JSValue WormholeGetProperty(OOJS_GETTER_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    WormholeEntity* entity = nil;
    id result = nil;

    if (!JSWormholeGetWormholeEntity(context, this, &entity))
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
        OOJSReportBadPropertySelector(context, this, magic, sWormholeProperties, OOJS_COUNT(sWormholeProperties));
        return OOJSNativeFailure(context);
    }

    return OOJSValueFromNativeObject(context, result);

    OOJS_NATIVE_EXIT
}
