/*

OOJSOolite.h

JavaScript proxy for Oolite (for version checking and similar).


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

#import "OOJSOolite.h"
#import "MyOpenGLView.h"
#import "OOConstToString.h"
#import "OOJSPlayer.h"
#import "OOJavaScriptEngine.h"
#import "OOStringParsing.h"
#import "ResourceManager.h"

static JSValue OoliteGetProperty(OOJS_GETTER_ARGS);
static JSValue OoliteSetProperty(OOJS_SETTER_ARGS);

static NSString* VersionString(void);
static NSArray* VersionComponents(void);

static JSValue OoliteCompareVersion(OOJS_NATIVE_ARGS);

/*	oolite.jsVersion was SpiderMonkey's JS_GetVersion(), 185 (JSVERSION_ECMA_5).
        OXPs compare it numerically, so it stays 185: QuickJS implements a
        superset of ES5. jsVersionString was "1.8.5"; it now names the engine.
*/
enum {
    kOOJSCompatibleJSVersion = 185
};

static JSClassID sOoliteClassID;
static JSClassDef sOoliteClass = {
    .class_name = "Oolite",
};

enum {
    // Property IDs
    kOolite_version, // version number components, array, read-only
    kOolite_versionString, // version number as string, string, read-only
    kOolite_jsVersion, // JavaScript version, integer, read-only
    kOolite_jsVersionString, // JavaScript version as string, string, read-only
    kOolite_gameSettings, // Various game settings, object, read-only
    kOolite_resourcePaths, // Paths containing resources, built-in plus oxp/oxz, read-only
    kOolite_colorSaturation, // Color saturation, integer, read/write
    kOolite_postFX, // current post processing effect, integer, read/write
    kOolite_hdrToneMapper, // currently active HDR tone mapper, string, read/write
    kOolite_sdrToneMapper, // currently active SDR tone mapper, string, read/write
#ifdef OO_DEBUG_MONITOR_ENABLED
    kOolite_timeAccelerationFactor, // time acceleration, float, read/write
#endif
};

static const JSCFunctionListEntry sOoliteProperties[] = {
    // JS name					Getter				Setter				ID
    OOJS_PROPERTY_RO("gameSettings", OoliteGetProperty, kOolite_gameSettings),
    OOJS_PROPERTY_RO("jsVersion", OoliteGetProperty, kOolite_jsVersion),
    OOJS_PROPERTY_RO("jsVersionString", OoliteGetProperty, kOolite_jsVersionString),
    OOJS_PROPERTY_RO("version", OoliteGetProperty, kOolite_version),
    OOJS_PROPERTY_RO("versionString", OoliteGetProperty, kOolite_versionString),
    OOJS_PROPERTY_RO("resourcePaths", OoliteGetProperty, kOolite_resourcePaths),
    OOJS_PROPERTY_RW("colorSaturation", OoliteGetProperty, OoliteSetProperty, kOolite_colorSaturation),
    OOJS_PROPERTY_RW("postFX", OoliteGetProperty, OoliteSetProperty, kOolite_postFX),
    OOJS_PROPERTY_RW("hdrToneMapper", OoliteGetProperty, OoliteSetProperty, kOolite_hdrToneMapper),
    OOJS_PROPERTY_RW("sdrToneMapper", OoliteGetProperty, OoliteSetProperty, kOolite_sdrToneMapper),
#ifdef OO_DEBUG_MONITOR_ENABLED
    OOJS_PROPERTY_RW("timeAccelerationFactor", OoliteGetProperty, OoliteSetProperty, kOolite_timeAccelerationFactor),
#endif
};

static const JSCFunctionListEntry sOoliteMethods[] = {
    // JS name					Function					min args
    JS_CFUNC_DEF("compareVersion", 1, OoliteCompareVersion),
};

void InitOOJSOolite(JSContext* context, JSValueConst global)
{
    OOJSRegisterClass(&sOoliteClassID, &sOoliteClass);
    JSValueConst oolitePrototype = OOJSInitClass(context, global, sOoliteClassID, JS_UNDEFINED, OOJSUnconstructableConstruct, 0,
        sOoliteProperties, OOJS_COUNT(sOoliteProperties), sOoliteMethods, OOJS_COUNT(sOoliteMethods), NULL, 0);
    JS_DefinePropertyValueStr(context, global, "oolite", JS_NewObjectProtoClass(context, oolitePrototype, sOoliteClassID), OOJS_PROP_READONLY);
}

static JSValue OoliteGetProperty(OOJS_GETTER_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    id result = nil;
    MyOpenGLView* gameView = [UNIVERSE gameView];

    switch (magic) {
    case kOolite_version:
        result = VersionComponents();
        break;

    case kOolite_versionString:
        result = VersionString();
        break;

    case kOolite_jsVersion:
        return JS_NewInt32(context, kOOJSCompatibleJSVersion);

    case kOolite_jsVersionString:
        result = [NSString stringWithFormat:@"QuickJS-ng %s", JS_GetVersion()];
        break;

    case kOolite_gameSettings:
        result = [UNIVERSE gameSettings];
        break;

    case kOolite_resourcePaths:
        // user name in displayed paths masked for privacy - remember that the console can be run remotely too
        result = [ResourceManager maskUserNameInPathArray:[ResourceManager paths]];
        break;

    case kOolite_colorSaturation:
        return JS_NewNumber(context, [gameView colorSaturation]);

    case kOolite_postFX:
        return JS_NewInt32(context, [UNIVERSE currentPostFX]);

    case kOolite_hdrToneMapper: {
        NSString* toneMapperStr = @"OOHDR_TONEMAPPER_UNDEFINED";
#if OOLITE_WINDOWS
        if ([gameView hdrOutput]) {
            toneMapperStr = OOStringFromHDRToneMapper([gameView hdrToneMapper]);
        }
#endif
        result = toneMapperStr;
        break;
    }

    case kOolite_sdrToneMapper: {
        NSString* toneMapperStr = @"OOSDR_TONEMAPPER_UNDEFINED";
        if (![gameView hdrOutput]) {
            toneMapperStr = OOStringFromSDRToneMapper([gameView sdrToneMapper]);
        }
        result = toneMapperStr;
        break;
    }

#ifdef OO_DEBUG_MONITOR_ENABLED
    case kOolite_timeAccelerationFactor:
        return JS_NewNumber(context, [UNIVERSE timeAccelerationFactor]);
#endif

    default:
        OOJSReportBadPropertySelector(context, this, magic, sOoliteProperties, OOJS_COUNT(sOoliteProperties));
        return JS_EXCEPTION;
    }

    return OOJSValueFromNativeObject(context, result);

    OOJS_NATIVE_EXIT
}

static JSValue OoliteSetProperty(OOJS_SETTER_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    double fValue;
    int32_t iValue;
    NSString* sValue = nil;
    MyOpenGLView* gameView = [UNIVERSE gameView];

    switch (magic) {
    case kOolite_colorSaturation:
        if (JS_ToFloat64(context, &fValue, value) == 0) {
            float currentColorSaturation = [gameView colorSaturation];
            [gameView adjustColorSaturation:fValue - currentColorSaturation];
            return JS_UNDEFINED;
        }
        break;

    case kOolite_postFX:
        if (OOJSValueToInt32(context, value, &iValue)) {
            iValue = MAX(iValue, 0);
            [UNIVERSE setCurrentPostFX:iValue];
            return JS_UNDEFINED;
        }
        break;

    case kOolite_hdrToneMapper:
        if (!JS_IsString(value))
            break; // non-string is not allowed
        sValue = OOStringFromJSValue(context, value);
        if (sValue != nil) {
#if OOLITE_WINDOWS
            if ([gameView hdrOutput])
                [gameView setHDRToneMapper:OOHDRToneMapperFromString(sValue)];
            else
                OOJSReportWarning(context, @"hdrToneMapper cannot be set if not running in HDR mode");
#endif
            return JS_UNDEFINED;
        }
        break;

    case kOolite_sdrToneMapper:
        if (!JS_IsString(value))
            break; // non-string is not allowed
        sValue = OOStringFromJSValue(context, value);
        if (sValue != nil) {
            if (![gameView hdrOutput])
                [gameView setSDRToneMapper:OOSDRToneMapperFromString(sValue)];
            else
                OOJSReportWarning(context, @"sdrToneMapper cannot be set if not running in SDR mode");
            return JS_UNDEFINED;
        }
        break;

#ifdef OO_DEBUG_MONITOR_ENABLED
    case kOolite_timeAccelerationFactor:
        if (JS_ToFloat64(context, &fValue, value) == 0) {
            [UNIVERSE setTimeAccelerationFactor:fValue];
            return JS_UNDEFINED;
        }
        break;
#endif

    default:
        OOJSReportBadPropertySelector(context, this, magic, sOoliteProperties, OOJS_COUNT(sOoliteProperties));
        return JS_EXCEPTION;
    }

    // A failed conversion may have left an exception pending; report the bad value instead, as before.
    if (JS_HasException(context))
        JS_FreeValue(context, JS_GetException(context));
    OOJSReportBadPropertyValue(context, this, magic, sOoliteProperties, OOJS_COUNT(sOoliteProperties), value);
    return JS_EXCEPTION;

    OOJS_NATIVE_EXIT
}

static NSString* VersionString(void)
{
    return [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"];
}

static NSArray* VersionComponents(void)
{
    return ComponentsFromVersionString(VersionString());
}

/*	oolite.compareVersion(versionSpec) : Number
        returns -1 if the current version of Oolite is less than versionSpec, 0 if
        they are equal, and 1 if the current version is newer. versionSpec may be
        a string or an array. Example:
        if (0 < oolite.compareVersion("1.70"))  log("Old version of Oolite!")
        else  this.doStuffThatRequires170()
*/
static JSValue OoliteCompareVersion(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    id components = nil;
    NSEnumerator* componentEnum = nil;
    id component = nil;

    if (argc == 0)
        OOJS_RETURN_VOID; // Backwards-compatibility: be overly lenient.

    components = OOJSNativeObjectFromJSValue(context, OOJS_ARGV[0]);
    if ([components isKindOfClass:[NSArray class]]) {
        // Require each element to be a number
        for (componentEnum = [components objectEnumerator]; (component = [componentEnum nextObject]);) {
            if (![component isKindOfClass:[NSNumber class]]) {
                components = nil;
                break;
            }
        }
    } else if ([components isKindOfClass:[NSString class]]) {
        components = ComponentsFromVersionString(components);
    } else
        components = nil;

    if (components != nil) {
        OOJS_RETURN_INT((int32_t)CompareVersions(components, VersionComponents()));
    } else {
        OOJS_RETURN_VOID;
    }

    OOJS_NATIVE_EXIT
}
