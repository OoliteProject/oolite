/*
OOJSVisualEffect.m (QuickJS-ng)

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

#import "OOJSVisualEffect.h"
#import "EntityOOJavaScriptExtensions.h"
#import "OOCollectionExtractors.h"
#import "OOJSEntity.h"
#import "OOJSVector.h"
#import "OOJavaScriptEngine.h"
#import "OOMesh.h"
#import "OOVisualEffectEntity.h"
#import "ResourceManager.h"

static JSClassID sVisualEffectClassID;

static BOOL JSVisualEffectGetVisualEffectEntity(JSContext* context, JSValueConst visualEffectObj, OOVisualEffectEntity** outEntity);

static JSValue VisualEffectGetProperty(OOJS_GETTER_ARGS);
static JSValue VisualEffectSetProperty(OOJS_SETTER_ARGS);

static JSValue VisualEffectRemove(OOJS_NATIVE_ARGS);
static JSValue VisualEffectGetShaders(OOJS_NATIVE_ARGS);
static JSValue VisualEffectSetShaders(OOJS_NATIVE_ARGS);
static JSValue VisualEffectGetMaterials(OOJS_NATIVE_ARGS);
static JSValue VisualEffectSetMaterials(OOJS_NATIVE_ARGS);
static JSValue VisualEffectScale(OOJS_NATIVE_ARGS);
static JSValue VisualEffectRestoreSubEntities(OOJS_NATIVE_ARGS);

static JSValue VisualEffectSetMaterialsInternal(OOJS_NATIVE_ARGS, OOVisualEffectEntity* thisEnt, BOOL fromShaders);

static JSClassDef sVisualEffectClass = {
    .class_name = "VisualEffect",
    .finalizer = OOJSObjectWrapperFinalize,
};

enum {
    // Property IDs
    kVisualEffect_beaconCode,
    kVisualEffect_beaconLabel,
    kVisualEffect_dataKey,
    kVisualEffect_hullHeatLevel,
    kVisualEffect_isBreakPattern,
    kVisualEffect_scaleX,
    kVisualEffect_scaleY,
    kVisualEffect_scaleZ,
    kVisualEffect_scannerDisplayColor1,
    kVisualEffect_scannerDisplayColor2,
    kVisualEffect_script,
    kVisualEffect_scriptInfo,
    kVisualEffect_shaderFloat1,
    kVisualEffect_shaderFloat2,
    kVisualEffect_shaderInt1,
    kVisualEffect_shaderInt2,
    kVisualEffect_shaderVector1,
    kVisualEffect_shaderVector2,
    kVisualEffect_subEntities,
    kVisualEffect_vectorForward,
    kVisualEffect_vectorRight,
    kVisualEffect_vectorUp
};

static const JSCFunctionListEntry sVisualEffectProperties[] = {
    // JS name, getter, setter, ID
    OOJS_PROPERTY_RW("beaconCode", VisualEffectGetProperty, VisualEffectSetProperty, kVisualEffect_beaconCode),
    OOJS_PROPERTY_RW("beaconLabel", VisualEffectGetProperty, VisualEffectSetProperty, kVisualEffect_beaconLabel),
    OOJS_PROPERTY_RO("dataKey", VisualEffectGetProperty, kVisualEffect_dataKey),
    OOJS_PROPERTY_RW("isBreakPattern", VisualEffectGetProperty, VisualEffectSetProperty, kVisualEffect_isBreakPattern),
    OOJS_PROPERTY_RW("scaleX", VisualEffectGetProperty, VisualEffectSetProperty, kVisualEffect_scaleX),
    OOJS_PROPERTY_RW("scaleY", VisualEffectGetProperty, VisualEffectSetProperty, kVisualEffect_scaleY),
    OOJS_PROPERTY_RW("scaleZ", VisualEffectGetProperty, VisualEffectSetProperty, kVisualEffect_scaleZ),
    OOJS_PROPERTY_RW("scannerDisplayColor1", VisualEffectGetProperty, VisualEffectSetProperty, kVisualEffect_scannerDisplayColor1),
    OOJS_PROPERTY_RW("scannerDisplayColor2", VisualEffectGetProperty, VisualEffectSetProperty, kVisualEffect_scannerDisplayColor2),
    OOJS_PROPERTY_RW("hullHeatLevel", VisualEffectGetProperty, VisualEffectSetProperty, kVisualEffect_hullHeatLevel),
    OOJS_PROPERTY_RO("script", VisualEffectGetProperty, kVisualEffect_script),
    OOJS_PROPERTY_RO("scriptInfo", VisualEffectGetProperty, kVisualEffect_scriptInfo),
    OOJS_PROPERTY_RW("shaderFloat1", VisualEffectGetProperty, VisualEffectSetProperty, kVisualEffect_shaderFloat1),
    OOJS_PROPERTY_RW("shaderFloat2", VisualEffectGetProperty, VisualEffectSetProperty, kVisualEffect_shaderFloat2),
    OOJS_PROPERTY_RW("shaderInt1", VisualEffectGetProperty, VisualEffectSetProperty, kVisualEffect_shaderInt1),
    OOJS_PROPERTY_RW("shaderInt2", VisualEffectGetProperty, VisualEffectSetProperty, kVisualEffect_shaderInt2),
    OOJS_PROPERTY_RW("shaderVector1", VisualEffectGetProperty, VisualEffectSetProperty, kVisualEffect_shaderVector1),
    OOJS_PROPERTY_RW("shaderVector2", VisualEffectGetProperty, VisualEffectSetProperty, kVisualEffect_shaderVector2),
    OOJS_PROPERTY_RO("subEntities", VisualEffectGetProperty, kVisualEffect_subEntities),
    OOJS_PROPERTY_RO("vectorForward", VisualEffectGetProperty, kVisualEffect_vectorForward),
    OOJS_PROPERTY_RO("vectorRight", VisualEffectGetProperty, kVisualEffect_vectorRight),
    OOJS_PROPERTY_RO("vectorUp", VisualEffectGetProperty, kVisualEffect_vectorUp),
};

static const JSCFunctionListEntry sVisualEffectMethods[] = {
    // JS name, min args, function
    JS_CFUNC_DEF("getMaterials", 0, VisualEffectGetMaterials),
    JS_CFUNC_DEF("getShaders", 0, VisualEffectGetShaders),
    JS_CFUNC_DEF("remove", 0, VisualEffectRemove),
    JS_CFUNC_DEF("restoreSubEntities", 0, VisualEffectRestoreSubEntities),
    JS_CFUNC_DEF("scale", 1, VisualEffectScale),
    JS_CFUNC_DEF("setMaterials", 1, VisualEffectSetMaterials),
    JS_CFUNC_DEF("setShaders", 2, VisualEffectSetShaders),
};

void InitOOJSVisualEffect(JSContext* context, JSValueConst global)
{
    OOJSRegisterClass(&sVisualEffectClassID, &sVisualEffectClass);

    JSValue parentPrototype = JS_GetClassProto(context, JSEntityClassID());
    NSCAssert(JS_IsObject(parentPrototype), @"Entity must be initialized before VisualEffect.");
    OOJSInitClass(context, global, sVisualEffectClassID, parentPrototype, OOJSUnconstructableConstruct, 0,
        sVisualEffectProperties, OOJS_COUNT(sVisualEffectProperties), sVisualEffectMethods, OOJS_COUNT(sVisualEffectMethods), NULL, 0);
    JS_FreeValue(context, parentPrototype);

    OOJSRegisterObjectConverter(sVisualEffectClassID, OOJSBasicPrivateObjectConverter);
    OOJSRegisterSubclass(sVisualEffectClassID, JSEntityClassID());
}

JSClassID JSVisualEffectClassID(void)
{
    return sVisualEffectClassID;
}

static BOOL JSVisualEffectGetVisualEffectEntity(JSContext* context, JSValueConst visualEffectObj, OOVisualEffectEntity** outEntity)
{
    OOJS_PROFILE_ENTER

    BOOL result;
    Entity* entity = nil;

    if (outEntity == NULL)
        return NO;
    *outEntity = nil;

    result = OOJSEntityGetEntity(context, visualEffectObj, &entity);
    if (!result)
        return NO;

    if (![entity isKindOfClass:[OOVisualEffectEntity class]])
        return NO;

    *outEntity = (OOVisualEffectEntity*)entity;
    return YES;

    OOJS_PROFILE_EXIT
}

@implementation OOVisualEffectEntity (OOJavaScriptExtensions)

- (JSClassID)oo_jsClassID
{
    return sVisualEffectClassID;
}

- (NSString*)oo_jsClassName
{
    return @"VisualEffect";
}

- (BOOL)isVisibleToScripts
{
    return YES;
}

- (NSArray*)subEntitiesForScript
{
    return [[self visualEffectSubEntityEnumerator] allObjects];
}

@end

static JSValue VisualEffectGetProperty(OOJS_GETTER_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    OOVisualEffectEntity* entity = nil;
    id result = nil;

    if (!JSVisualEffectGetVisualEffectEntity(context, this, &entity))
        return OOJSNativeFailure(context);
    if (entity == nil) {
        return JS_UNDEFINED;
    }

    switch (magic) {
    case kVisualEffect_beaconCode:
        result = [entity beaconCode];
        break;

    case kVisualEffect_beaconLabel:
        result = [entity beaconLabel];
        break;

    case kVisualEffect_dataKey:
        result = [entity effectKey];
        break;

    case kVisualEffect_isBreakPattern:
        return OOJSValueFromBOOL([entity isBreakPattern]);

    case kVisualEffect_vectorRight:
        OOJS_RETURN_VECTOR([entity rightVector]);

    case kVisualEffect_vectorForward:
        OOJS_RETURN_VECTOR([entity forwardVector]);

    case kVisualEffect_vectorUp:
        OOJS_RETURN_VECTOR([entity upVector]);

    case kVisualEffect_scaleX:
        return JS_NewNumber(context, [entity scaleX]);

    case kVisualEffect_scaleY:
        return JS_NewNumber(context, [entity scaleY]);

    case kVisualEffect_scaleZ:
        return JS_NewNumber(context, [entity scaleZ]);

    case kVisualEffect_scannerDisplayColor1:
        result = [[entity scannerDisplayColor1] normalizedArray];
        break;

    case kVisualEffect_scannerDisplayColor2:
        result = [[entity scannerDisplayColor2] normalizedArray];
        break;

    case kVisualEffect_hullHeatLevel:
        return JS_NewNumber(context, [entity hullHeatLevel]);

    case kVisualEffect_shaderFloat1:
        return JS_NewNumber(context, [entity shaderFloat1]);

    case kVisualEffect_shaderFloat2:
        return JS_NewNumber(context, [entity shaderFloat2]);

    case kVisualEffect_shaderInt1:
        return JS_NewInt32(context, [entity shaderInt1]);

    case kVisualEffect_shaderInt2:
        return JS_NewInt32(context, [entity shaderInt2]);

    case kVisualEffect_shaderVector1:
        OOJS_RETURN_VECTOR([entity shaderVector1]);

    case kVisualEffect_shaderVector2:
        OOJS_RETURN_VECTOR([entity shaderVector2]);

    case kVisualEffect_subEntities:
        result = [entity subEntitiesForScript];
        break;

    case kVisualEffect_script:
        result = [entity script];
        break;

    case kVisualEffect_scriptInfo:
        result = [entity scriptInfo];
        if (result == nil)
            result = [NSDictionary dictionary]; // empty rather than null
        break;

    default:
        OOJSReportBadPropertySelector(context, this, magic, sVisualEffectProperties, OOJS_COUNT(sVisualEffectProperties));
        return OOJSNativeFailure(context);
    }

    return OOJSValueFromNativeObject(context, result);

    OOJS_NATIVE_EXIT
}

static JSValue VisualEffectSetProperty(OOJS_SETTER_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    OOVisualEffectEntity* entity = nil;
    int bValue;
    OOColor* colorForScript;
    int32_t iValue;
    double fValue;
    Vector vValue;
    NSString* sValue = nil;

    if (!JSVisualEffectGetVisualEffectEntity(context, this, &entity))
        return OOJSNativeFailure(context);
    if (entity == nil)
        return JS_UNDEFINED;

    switch (magic) {
    case kVisualEffect_beaconCode:
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

    case kVisualEffect_beaconLabel:
        sValue = OOStringFromJSValue(context, value);
        if (sValue != nil) {
            [entity setBeaconLabel:sValue];
            return JS_UNDEFINED;
        }
        break;

    case kVisualEffect_isBreakPattern:
        if ((bValue = JS_ToBool(context, value)) >= 0) {
            [entity setIsBreakPattern:bValue];
            return JS_UNDEFINED;
        }
        break;

    case kVisualEffect_scannerDisplayColor1:
        colorForScript = [OOColor colorWithDescription:OOJSNativeObjectFromJSValue(context, value)];
        if (colorForScript != nil || JS_IsNull(value)) {
            [entity setScannerDisplayColor1:colorForScript];
            return JS_UNDEFINED;
        }
        break;

    case kVisualEffect_scannerDisplayColor2:
        colorForScript = [OOColor colorWithDescription:OOJSNativeObjectFromJSValue(context, value)];
        if (colorForScript != nil || JS_IsNull(value)) {
            [entity setScannerDisplayColor2:colorForScript];
            return JS_UNDEFINED;
        }
        break;

    case kVisualEffect_scaleX:
        if (JS_ToFloat64(context, &fValue, value) == 0) {
            if (fValue > 0.0) {
                [entity setScaleX:fValue];
                return JS_UNDEFINED;
            }
        }
        break;

    case kVisualEffect_scaleY:
        if (JS_ToFloat64(context, &fValue, value) == 0) {
            if (fValue > 0.0) {
                [entity setScaleY:fValue];
                return JS_UNDEFINED;
            }
        }
        break;

    case kVisualEffect_scaleZ:
        if (JS_ToFloat64(context, &fValue, value) == 0) {
            if (fValue > 0.0) {
                [entity setScaleZ:fValue];
                return JS_UNDEFINED;
            }
        }
        break;

    case kVisualEffect_hullHeatLevel:
        if (JS_ToFloat64(context, &fValue, value) == 0) {
            [entity setHullHeatLevel:fValue];
            return JS_UNDEFINED;
        }
        break;

    case kVisualEffect_shaderFloat1:
        if (JS_ToFloat64(context, &fValue, value) == 0) {
            [entity setShaderFloat1:fValue];
            return JS_UNDEFINED;
        }
        break;

    case kVisualEffect_shaderFloat2:
        if (JS_ToFloat64(context, &fValue, value) == 0) {
            [entity setShaderFloat2:fValue];
            return JS_UNDEFINED;
        }
        break;

    case kVisualEffect_shaderInt1:
        if (OOJSValueToInt32(context, value, &iValue)) {
            [entity setShaderInt1:iValue];
            return JS_UNDEFINED;
        }
        break;

    case kVisualEffect_shaderInt2:
        if (OOJSValueToInt32(context, value, &iValue)) {
            [entity setShaderInt2:iValue];
            return JS_UNDEFINED;
        }
        break;

    case kVisualEffect_shaderVector1:
        if (JSValueToVector(context, value, &vValue)) {
            [entity setShaderVector1:vValue];
            return JS_UNDEFINED;
        }
        break;

    case kVisualEffect_shaderVector2:
        if (JSValueToVector(context, value, &vValue)) {
            [entity setShaderVector2:vValue];
            return JS_UNDEFINED;
        }
        break;

    default:
        OOJSReportBadPropertySelector(context, this, magic, sVisualEffectProperties, OOJS_COUNT(sVisualEffectProperties));
        return OOJSNativeFailure(context);
    }

    OOJSReportBadPropertyValue(context, this, magic, sVisualEffectProperties, OOJS_COUNT(sVisualEffectProperties), value);
    return OOJSNativeFailure(context);

    OOJS_NATIVE_EXIT
}

// *** Methods ***

#define GET_THIS_EFFECT(THISENT)                                                            \
    do {                                                                                    \
        if (EXPECT_NOT(!JSVisualEffectGetVisualEffectEntity(context, OOJS_THIS, &THISENT))) \
            return OOJSNativeFailure(context); /* Exception */                              \
        if (OOIsStaleEntity(THISENT))                                                       \
            OOJS_RETURN_VOID;                                                               \
    } while (0)

static JSValue VisualEffectRemove(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    OOVisualEffectEntity* thisEnt = nil;
    GET_THIS_EFFECT(thisEnt);

    if ([thisEnt isSubEntity]) {
        OOVisualEffectEntity* parent = [thisEnt owner];
        [parent removeSubEntity:thisEnt];
    } else {
        [thisEnt remove];
    }

    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}

// getMaterials()
static JSValue VisualEffectGetMaterials(OOJS_NATIVE_ARGS)
{
    OOJS_PROFILE_ENTER

    NSObject* result = nil;
    OOVisualEffectEntity* thisEnt = nil;

    GET_THIS_EFFECT(thisEnt);

    result = [[thisEnt mesh] materials];
    if (result == nil)
        result = [NSDictionary dictionary];
    OOJS_RETURN_OBJECT(result);

    OOJS_PROFILE_EXIT
}

// getShaders()
static JSValue VisualEffectGetShaders(OOJS_NATIVE_ARGS)
{
    OOJS_PROFILE_ENTER

    NSObject* result = nil;
    OOVisualEffectEntity* thisEnt = nil;

    GET_THIS_EFFECT(thisEnt);

    result = [[thisEnt mesh] shaders];
    if (result == nil)
        result = [NSDictionary dictionary];
    OOJS_RETURN_OBJECT(result);

    OOJS_PROFILE_EXIT
}

// setMaterials(params: dict, [shaders: dict])  // sets materials dictionary. Optional parameter sets the shaders dictionary too.
static JSValue VisualEffectSetMaterials(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    OOVisualEffectEntity* thisEnt = nil;

    if (argc < 1) {
        OOJSReportBadArguments(context, @"VisualEffect", @"setMaterials", 0, OOJS_ARGV, nil, @"parameter object");
        return OOJSNativeFailure(context);
    }

    GET_THIS_EFFECT(thisEnt);

    return VisualEffectSetMaterialsInternal(context, OOJS_THIS, argc, OOJS_ARGV, thisEnt, NO);

    OOJS_NATIVE_EXIT
}

// setShaders(params: dict)
static JSValue VisualEffectSetShaders(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    OOVisualEffectEntity* thisEnt = nil;

    GET_THIS_EFFECT(thisEnt);

    if (argc < 1) {
        OOJSReportBadArguments(context, @"VisualEffect", @"setShaders", 0, OOJS_ARGV, nil, @"parameter object");
        return OOJSNativeFailure(context);
    }

    if (JS_IsNull(OOJS_ARGV[0]) || (!JS_IsNull(OOJS_ARGV[0]) && !JS_IsObject(OOJS_ARGV[0]))) {
        // EMMSTRAN: JS_ValueToObject() and normal error handling here.
        OOJSReportWarning(context, @"VisualEffect.%@: expected %@ instead of '%@'.", @"setShaders", @"object", OOStringFromJSValueEvenIfNull(context, OOJS_ARGV[0]));
        OOJS_RETURN_BOOL(NO);
    }

    /*	SpiderMonkey's version overwrote OOJS_ARGV[1] in place. QuickJS argv
            belongs to the caller (and its values are reference counted), so pass
            a borrowed copy instead.
    */
    JSValueConst shaderArgv[2] = { OOJS_ARGV[0], OOJS_ARGV[0] };
    return VisualEffectSetMaterialsInternal(context, OOJS_THIS, argc, shaderArgv, thisEnt, YES);

    OOJS_NATIVE_EXIT
}

/* **  helper functions ** */

static JSValue VisualEffectSetMaterialsInternal(OOJS_NATIVE_ARGS, OOVisualEffectEntity* thisEnt, BOOL fromShaders)
{
    OOJS_PROFILE_ENTER

    JSValueConst params = JS_UNDEFINED;
    NSDictionary* materials;
    NSDictionary* shaders;
    BOOL withShaders = NO;
    BOOL success = NO;

    GET_THIS_EFFECT(thisEnt);

    if (JS_IsNull(OOJS_ARGV[0]) || (!JS_IsNull(OOJS_ARGV[0]) && !JS_IsObject(OOJS_ARGV[0]))) {
        OOJSReportWarning(context, @"VisualEffect.%@: expected %@ instead of '%@'.", @"setMaterials", @"object", OOStringFromJSValueEvenIfNull(context, OOJS_ARGV[0]));
        OOJS_RETURN_BOOL(NO);
    }

    if (argc > 1) {
        withShaders = YES;
        if (JS_IsNull(OOJS_ARGV[1]) || (!JS_IsNull(OOJS_ARGV[1]) && !JS_IsObject(OOJS_ARGV[1]))) {
            OOJSReportWarning(context, @"VisualEffect.%@: expected %@ instead of '%@'.", @"setMaterials", @"object as second parameter", OOStringFromJSValueEvenIfNull(context, OOJS_ARGV[1]));
            withShaders = NO;
        }
    }

    if (fromShaders) {
        materials = [[thisEnt mesh] materials];
        params = OOJS_ARGV[0];
        shaders = OOJSNativeObjectFromJSObject(context, params);
    } else {
        params = OOJS_ARGV[0];
        materials = OOJSNativeObjectFromJSObject(context, params);
        if (withShaders) {
            params = OOJS_ARGV[1];
            shaders = OOJSNativeObjectFromJSObject(context, params);
        } else {
            shaders = [[thisEnt mesh] shaders];
        }
    }

    OOJS_BEGIN_FULL_NATIVE(context)
    NSDictionary* effectDict = [thisEnt effectInfoDictionary];

    // First we test to see if we can create the mesh.
    OOMesh* mesh = [OOMesh meshWithName:[effectDict oo_stringForKey:@"model"]
                               cacheKey:nil
                     materialDictionary:materials
                      shadersDictionary:shaders
                                 smooth:[effectDict oo_boolForKey:@"smooth" defaultValue:NO]
                           shaderMacros:[[ResourceManager materialDefaults] oo_dictionaryForKey:@"ship-prefix-macros"]
                    shaderBindingTarget:thisEnt];

    if (mesh != nil) {
        [thisEnt setMesh:mesh];
        success = YES;
    }
    OOJS_END_FULL_NATIVE

    OOJS_RETURN_BOOL(success);

    OOJS_PROFILE_EXIT
}

static JSValue VisualEffectScale(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    OOVisualEffectEntity* thisEnt = nil;
    GET_THIS_EFFECT(thisEnt);
    double scale = 0.0;
    BOOL gotScale;

    if (argc < 1) {
        OOJSReportBadArguments(context, @"VisualEffect", @"scale", argc, OOJS_ARGV, nil, @"scale factor needed");
        return OOJSNativeFailure(context);
    }

    gotScale = JS_ToFloat64(context, &scale, OOJS_ARGV[0]) == 0;
    if (EXPECT_NOT(scale <= 0.0 || !gotScale)) {
        OOJSReportBadArguments(context, @"VisualEffect", @"scale", argc, OOJS_ARGV, nil, @"scale factor must be positive");
        return OOJSNativeFailure(context);
    }

    // set all three scales
    [thisEnt setScaleX:scale];
    [thisEnt setScaleY:scale];
    [thisEnt setScaleZ:scale];

    return JS_UNDEFINED;
    OOJS_NATIVE_EXIT
}

// restoreSubEntities(): boolean
static JSValue VisualEffectRestoreSubEntities(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    OOVisualEffectEntity* thisEnt = nil;
    NSUInteger numSubEntitiesRestored = 0U;

    GET_THIS_EFFECT(thisEnt);

    NSUInteger subCount = [[thisEnt subEntitiesForScript] count];

    [thisEnt clearSubEntities];
    [thisEnt setUpSubEntities];

    if ([[thisEnt subEntitiesForScript] count] - subCount > 0)
        numSubEntitiesRestored = [[thisEnt subEntitiesForScript] count] - subCount;

    OOJS_RETURN_BOOL(numSubEntitiesRestored > 0);

    OOJS_NATIVE_EXIT
}
