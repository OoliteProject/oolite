/*

OOJSSun.m (QuickJS-ng)


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

#import "OOJSSun.h"
#import "EntityOOJavaScriptExtensions.h"
#import "OOJSEntity.h"
#import "OOJavaScriptEngine.h"
#import "OOSunEntity.h"

static JSClassID sSunClassID;

static JSValue SunGetProperty(OOJS_GETTER_ARGS);
static JSValue SunGoNova(OOJS_NATIVE_ARGS);
static JSValue SunCancelNova(OOJS_NATIVE_ARGS);

static JSClassDef sSunClass = {
    .class_name = "Sun",
    .finalizer = OOJSObjectWrapperFinalize,
};

enum {
    // Property IDs
    kSun_radius, // Radius of sun in metres, number, read-only
    kSun_hasGoneNova, // Has sun gone nova, boolean, read-only
    kSun_isGoingNova, // Will sun go nova, boolean, read-only
    kSun_name // Name of sun, string, read-only (writable via systeminfo)
};

static const JSCFunctionListEntry sSunProperties[] = {
    // JS name, getter, setter, ID
    OOJS_PROPERTY_RO("hasGoneNova", SunGetProperty, kSun_hasGoneNova),
    OOJS_PROPERTY_RO("isGoingNova", SunGetProperty, kSun_isGoingNova),
    OOJS_PROPERTY_RO("name", SunGetProperty, kSun_name),
    OOJS_PROPERTY_RO("radius", SunGetProperty, kSun_radius),
};

static const JSCFunctionListEntry sSunMethods[] = {
    // JS name, min args, function
    JS_CFUNC_DEF("cancelNova", 0, SunCancelNova),
    JS_CFUNC_DEF("goNova", 1, SunGoNova),
};

DEFINE_JS_OBJECT_GETTER(JSSunGetSunEntity, sSunClassID, OOSunEntity)

void InitOOJSSun(JSContext* context, JSValueConst global)
{
    OOJSRegisterClass(&sSunClassID, &sSunClass);

    JSValue parentPrototype = JS_GetClassProto(context, JSEntityClassID());
    NSCAssert(JS_IsObject(parentPrototype), @"Entity must be initialized before Sun.");
    OOJSInitClass(context, global, sSunClassID, parentPrototype, OOJSUnconstructableConstruct, 0,
        sSunProperties, OOJS_COUNT(sSunProperties), sSunMethods, OOJS_COUNT(sSunMethods), NULL, 0);
    JS_FreeValue(context, parentPrototype);

    OOJSRegisterObjectConverter(sSunClassID, OOJSBasicPrivateObjectConverter);
    OOJSRegisterSubclass(sSunClassID, JSEntityClassID());
}

JSClassID JSSunClassID(void)
{
    return sSunClassID;
}

@implementation OOSunEntity (OOJavaScriptExtensions)

- (BOOL)isVisibleToScripts
{
    return YES;
}

- (JSClassID)oo_jsClassID
{
    return sSunClassID;
}

- (NSString*)oo_jsClassName
{
    return @"Sun";
}

@end

static JSValue SunGetProperty(OOJS_GETTER_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    OOSunEntity* sun = nil;

    if (EXPECT_NOT(!JSSunGetSunEntity(context, this, &sun)))
        return OOJSNativeFailure(context);

    switch (magic) {
    case kSun_radius:
        return JS_NewNumber(context, [sun radius]);

    case kSun_name:
        return OOJSValueFromNativeObject(context, [sun name]);

    case kSun_hasGoneNova:
        return OOJSValueFromBOOL([sun goneNova]);

    case kSun_isGoingNova:
        return OOJSValueFromBOOL([sun willGoNova] && ![sun goneNova]);

    default:
        OOJSReportBadPropertySelector(context, this, magic, sSunProperties, OOJS_COUNT(sSunProperties));
        return OOJSNativeFailure(context);
    }

    OOJS_NATIVE_EXIT
}

// *** Methods ***

// goNova([delay : Number])
static JSValue SunGoNova(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    OOSunEntity* sun = nil;
    double delay = 0;

    if (EXPECT_NOT(!JSSunGetSunEntity(context, OOJS_THIS, &sun)))
        return OOJSNativeFailure(context);
    if (argc > 0 && EXPECT_NOT(JS_ToFloat64(context, &delay, OOJS_ARGV[0]) != 0))
        return OOJSNativeFailure(context);

    [sun setGoingNova:YES inTime:delay];
    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}

// cancelNova()
static JSValue SunCancelNova(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    OOSunEntity* sun = nil;

    if (EXPECT_NOT(!JSSunGetSunEntity(context, OOJS_THIS, &sun)))
        return OOJSNativeFailure(context);

    if ([sun willGoNova] && ![sun goneNova]) {
        [sun setGoingNova:NO inTime:0];
    }
    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}
