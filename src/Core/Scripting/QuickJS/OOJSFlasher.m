/*
OOJSFlasher.m (QuickJS-ng)

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

#import "OOJSFlasher.h"
#import "EntityOOJavaScriptExtensions.h"
#import "OOFlasherEntity.h"
#import "OOJSEntity.h"
#import "OOJSVector.h"
#import "OOJavaScriptEngine.h"
#import "OOVisualEffectEntity.h"
#import "ShipEntity.h"

static JSClassID sFlasherClassID;

static BOOL JSFlasherGetFlasherEntity(JSContext* context, JSValueConst jsobj, OOFlasherEntity** outEntity);

static JSValue FlasherGetProperty(OOJS_GETTER_ARGS);
static JSValue FlasherSetProperty(OOJS_SETTER_ARGS);

static JSValue FlasherRemove(OOJS_NATIVE_ARGS);

static JSClassDef sFlasherClass = {
    .class_name = "Flasher",
    .finalizer = OOJSObjectWrapperFinalize,
};

enum {
    // Property IDs
    kFlasher_active,
    kFlasher_color,
    kFlasher_fraction,
    kFlasher_frequency,
    kFlasher_phase,
    kFlasher_size
};

static const JSCFunctionListEntry sFlasherProperties[] = {
    // JS name, getter, setter, ID
    OOJS_PROPERTY_RW("active", FlasherGetProperty, FlasherSetProperty, kFlasher_active),
    OOJS_PROPERTY_RW("color", FlasherGetProperty, FlasherSetProperty, kFlasher_color),
    OOJS_PROPERTY_RW("fraction", FlasherGetProperty, FlasherSetProperty, kFlasher_fraction),
    OOJS_PROPERTY_RW("frequency", FlasherGetProperty, FlasherSetProperty, kFlasher_frequency),
    OOJS_PROPERTY_RW("phase", FlasherGetProperty, FlasherSetProperty, kFlasher_phase),
    OOJS_PROPERTY_RW("size", FlasherGetProperty, FlasherSetProperty, kFlasher_size),
};

static const JSCFunctionListEntry sFlasherMethods[] = {
    // JS name, min args, function
    JS_CFUNC_DEF("remove", 0, FlasherRemove),
};

void InitOOJSFlasher(JSContext* context, JSValueConst global)
{
    OOJSRegisterClass(&sFlasherClassID, &sFlasherClass);

    JSValue parentPrototype = JS_GetClassProto(context, JSEntityClassID());
    NSCAssert(JS_IsObject(parentPrototype), @"Entity must be initialized before Flasher.");
    OOJSInitClass(context, global, sFlasherClassID, parentPrototype, OOJSUnconstructableConstruct, 0,
        sFlasherProperties, OOJS_COUNT(sFlasherProperties), sFlasherMethods, OOJS_COUNT(sFlasherMethods), NULL, 0);
    JS_FreeValue(context, parentPrototype);

    OOJSRegisterObjectConverter(sFlasherClassID, OOJSBasicPrivateObjectConverter);
    OOJSRegisterSubclass(sFlasherClassID, JSEntityClassID());
}

JSClassID JSFlasherClassID(void)
{
    return sFlasherClassID;
}

static BOOL JSFlasherGetFlasherEntity(JSContext* context, JSValueConst jsobj, OOFlasherEntity** outEntity)
{
    OOJS_PROFILE_ENTER

    BOOL result;
    Entity* entity = nil;

    if (outEntity == NULL)
        return NO;
    *outEntity = nil;

    result = OOJSEntityGetEntity(context, jsobj, &entity);
    if (!result)
        return NO;

    if (![entity isKindOfClass:[OOFlasherEntity class]])
        return NO;

    *outEntity = (OOFlasherEntity*)entity;
    return YES;

    OOJS_PROFILE_EXIT
}

@implementation OOFlasherEntity (OOJavaScriptExtensions)

- (JSClassID)oo_jsClassID
{
    return sFlasherClassID;
}

- (NSString*)oo_jsClassName
{
    return @"Flasher";
}

- (BOOL)isVisibleToScripts
{
    return YES;
}

@end

static JSValue FlasherGetProperty(OOJS_GETTER_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    OOFlasherEntity* entity = nil;
    id result = nil;

    if (!JSFlasherGetFlasherEntity(context, this, &entity))
        return OOJSNativeFailure(context);
    if (entity == nil) {
        return JS_UNDEFINED;
    }

    switch (magic) {
    case kFlasher_active:
        return OOJSValueFromBOOL([entity isActive]);

    case kFlasher_color:
        result = [[entity color] normalizedArray];
        break;

    case kFlasher_frequency:
        return JS_NewNumber(context, [entity frequency]);

    case kFlasher_fraction:
        return JS_NewNumber(context, [entity fraction]);

    case kFlasher_phase:
        return JS_NewNumber(context, [entity phase]);

    case kFlasher_size:
        return JS_NewNumber(context, [entity diameter]);

    default:
        OOJSReportBadPropertySelector(context, this, magic, sFlasherProperties, OOJS_COUNT(sFlasherProperties));
        return OOJSNativeFailure(context);
    }

    return OOJSValueFromNativeObject(context, result);

    OOJS_NATIVE_EXIT
}

static JSValue FlasherSetProperty(OOJS_SETTER_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    OOFlasherEntity* entity = nil;
    double fValue;
    int bValue;
    OOColor* colorForScript = nil;

    if (!JSFlasherGetFlasherEntity(context, this, &entity))
        return OOJSNativeFailure(context);
    if (entity == nil)
        return JS_UNDEFINED;

    switch (magic) {
    case kFlasher_active:
        if ((bValue = JS_ToBool(context, value)) >= 0) {
            [entity setActive:bValue];
            return JS_UNDEFINED;
        }
        break;

    case kFlasher_color:
        colorForScript = [OOColor colorWithDescription:OOJSNativeObjectFromJSValue(context, value)];
        if (colorForScript != nil || JS_IsNull(value)) {
            [entity setColor:colorForScript];
            return JS_UNDEFINED;
        }
        break;

    case kFlasher_frequency:
        if (JS_ToFloat64(context, &fValue, value) == 0) {
            if (fValue >= 0.0) {
                [entity setFrequency:fValue];
                return JS_UNDEFINED;
            }
        }
        break;

    case kFlasher_fraction:
        if (JS_ToFloat64(context, &fValue, value) == 0) {
            if (fValue > 0.0 && fValue <= 1.0) {
                [entity setFraction:fValue];
                return JS_UNDEFINED;
            }
        }
        break;

    case kFlasher_phase:
        if (JS_ToFloat64(context, &fValue, value) == 0) {
            [entity setPhase:fValue];
            return JS_UNDEFINED;
        }
        break;

    case kFlasher_size:
        if (JS_ToFloat64(context, &fValue, value) == 0) {
            if (fValue > 0.0) {
                [entity setDiameter:fValue];
                return JS_UNDEFINED;
            }
        }
        break;

    default:
        OOJSReportBadPropertySelector(context, this, magic, sFlasherProperties, OOJS_COUNT(sFlasherProperties));
        return OOJSNativeFailure(context);
    }

    OOJSReportBadPropertyValue(context, this, magic, sFlasherProperties, OOJS_COUNT(sFlasherProperties), value);
    return OOJSNativeFailure(context);

    OOJS_NATIVE_EXIT
}

// *** Methods ***

#define GET_THIS_FLASHER(THISENT)                                                 \
    do {                                                                          \
        if (EXPECT_NOT(!JSFlasherGetFlasherEntity(context, OOJS_THIS, &THISENT))) \
            return OOJSNativeFailure(context); /* Exception */                    \
        if (OOIsStaleEntity(THISENT))                                             \
            OOJS_RETURN_VOID;                                                     \
    } while (0)

static JSValue FlasherRemove(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    OOFlasherEntity* thisEnt = nil;
    GET_THIS_FLASHER(thisEnt);

    Entity* parent = [thisEnt owner];
    if ([parent isShip]) {
        [(ShipEntity*)parent removeFlasher:thisEnt];
    } else {
        [(OOVisualEffectEntity*)parent removeSubEntity:thisEnt];
    }

    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}
