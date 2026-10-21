/*

OOJSConsole.m (QuickJS-ng)


Oolite
Copyright (C) 2004-2013 Giles C Williams and contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/

#ifndef NDEBUG

#import "OOJSConsole.h"
#import "OODebugMonitor.h"
#include <stdint.h>

#import "OOConstToString.h"
#import "OODebugFlags.h"
#import "OOJSCall.h"
#import "OOJSEngineTimeManagement.h"
#import "OOJSEntity.h"
#import "OOJSScript.h"
#import "OOJSVector.h"
#import "OOLoggingExtended.h"
#import "OOOpenGLExtensionManager.h"
#import "ResourceManager.h"

@interface Entity (OODebugInspector)

// Method added by inspector in Debug OXP under OS X only.
- (void)inspect;

@end

NSString* OOPlatformDescription(void);

/*	Differences from the SpiderMonkey version:
        - pedanticMode is remembered but has no effect: SpiderMonkey's
          JSOPTION_STRICT extra warnings have no QuickJS equivalent.
        - dumpNamedRoots() does not exist (QuickJS has no named roots), and
          dumpHeap() writes QuickJS's memory usage summary.
        - profile(), getProfile() and trace() only profile natives, as in
          SpiderMonkey builds without MOZ_TRACE_JSCALLS.
        - ConsoleSettings properties are provided by the class's exotic methods
          rather than get/set/delete hooks. As before, they are not enumerable.
*/

static JSClassID sConsoleClassID;
static JSClassID sConsoleSettingsClassID;
static BOOL sPedanticMode = YES;

static JSValue ConsoleGetProperty(OOJS_GETTER_ARGS);
static JSValue ConsoleSetProperty(OOJS_SETTER_ARGS);

// Methods
static JSValue ConsoleConsoleMessage(OOJS_NATIVE_ARGS);
static JSValue ConsoleClearConsole(OOJS_NATIVE_ARGS);
static JSValue ConsoleScriptStack(OOJS_NATIVE_ARGS);
static JSValue ConsoleInspectEntity(OOJS_NATIVE_ARGS);
#if OO_DEBUG
static JSValue ConsoleCallObjCMethod(OOJS_NATIVE_ARGS);
static JSValue ConsoleSetUpCallObjC(OOJS_NATIVE_ARGS);
#endif
static JSValue ConsoleIsExecutableJavaScript(OOJS_NATIVE_ARGS);
static JSValue ConsoleDisplayMessagesInClass(OOJS_NATIVE_ARGS);
static JSValue ConsoleSetDisplayMessagesInClass(OOJS_NATIVE_ARGS);
static JSValue ConsoleWriteLogMarker(OOJS_NATIVE_ARGS);
static JSValue ConsoleWriteMemoryStats(OOJS_NATIVE_ARGS);
static JSValue ConsoleWriteJSMemoryStats(OOJS_NATIVE_ARGS);
static JSValue ConsoleGarbageCollect(OOJS_NATIVE_ARGS);
#if DEBUG
static JSValue ConsoleDumpHeap(OOJS_NATIVE_ARGS);
#endif
#if OOJS_PROFILE
static JSValue ConsoleProfile(OOJS_NATIVE_ARGS);
static JSValue ConsoleGetProfile(OOJS_NATIVE_ARGS);
static JSValue ConsoleTrace(OOJS_NATIVE_ARGS);

static BOOL PerformProfiling(JSContext* context, NSString* nominalFunction, int argc, JSValueConst* argv, JSValue* outRval, BOOL trace, OOTimeProfile** outProfile);
#endif

static int ConsoleSettingsGetOwnProperty(JSContext* context, JSPropertyDescriptor* desc, JSValueConst object, JSAtom propID);
static int ConsoleSettingsDeleteProperty(JSContext* context, JSValueConst object, JSAtom propID);
static int ConsoleSettingsDefineOwnProperty(JSContext* context, JSValueConst object, JSAtom propID, JSValueConst value, JSValueConst getter, JSValueConst setter, int flags);
static JSValue ConsoleSettingsGetProperty(JSContext* context, JSValueConst object, JSAtom propID, JSValueConst receiver);
static int ConsoleSettingsSetProperty(JSContext* context, JSValueConst object, JSAtom propID, JSValueConst value, JSValueConst receiver, int flags);

static JSClassDef sConsoleClass = {
    .class_name = "Console",
    .finalizer = OOJSObjectWrapperFinalize,
};

enum {
    // Property IDs
    kConsole_debugFlags, // debug flags, integer, read/write
    kConsole_detailLevel, // graphics detail level, symbolic string, read/write
    kConsole_maximumDetailLevel, // maximum graphics detail level, symbolic string, read-only
    kConsole_displayFPS, // display FPS (and related info), boolean, read/write
    kConsole_platformDescription, // Information about system we're running on in unspecified format, string, read-only
    kConsole_ignoreDroppedPackets, // boolean (default false), read/write
    kConsole_pedanticMode, // JS pedantic mode (JS_STRICT flag, not the same as "use strict"), boolean (default true), read/write
    kConsole_showErrorLocations, // Show error/warning source locations, boolean (default true), read/write
    kConsole_dumpStackForErrors, // Write stack dump when reporting error/exception, boolean (default false), read/write
    kConsole_dumpStackForWarnings, // Write stack dump when reporting warning, boolean (default false), read/write

    kConsole_glVendorString, // OpenGL GL_VENDOR string, string, read-only
    kConsole_glRendererString, // OpenGL GL_RENDERER string, string, read-only
    kConsole_glFixedFunctionTextureUnitCount, // GL_MAX_TEXTURE_UNITS_ARB, integer, read-only
    kConsole_glFragmentShaderTextureUnitCount, // GL_MAX_TEXTURE_IMAGE_UNITS_ARB, integer, read-only

    // Symbolic constants for debug flags:
    kConsole_DEBUG_LINKED_LISTS,
    kConsole_DEBUG_COLLISIONS,
    kConsole_DEBUG_DOCKING,
    kConsole_DEBUG_OCTREE_LOGGING,
    kConsole_DEBUG_BOUNDING_BOXES,
    kConsole_DEBUG_OCTREE_DRAW,
    kConsole_DEBUG_DRAW_NORMALS,
    kConsole_DEBUG_NO_DUST,
    kConsole_DEBUG_NO_SHADER_FALLBACK,
    kConsole_DEBUG_SHADER_VALIDATION,

    kConsole_DEBUG_MISC
};

#define OOJS_PROPERTY_HIDDEN_RW(name, getter, setter, magic) JS_CGETSET_MAGIC_DEF2(name, getter, setter, magic, OOJS_PROP_HIDDEN_READWRITE_CB)

static const JSCFunctionListEntry sConsoleProperties[] = {
    // JS name								Getter				Setter				ID
    OOJS_PROPERTY_RW("debugFlags", ConsoleGetProperty, ConsoleSetProperty, kConsole_debugFlags),
    OOJS_PROPERTY_RW("detailLevel", ConsoleGetProperty, ConsoleSetProperty, kConsole_detailLevel),
    OOJS_PROPERTY_RO("maximumDetailLevel", ConsoleGetProperty, kConsole_maximumDetailLevel),
    OOJS_PROPERTY_RW("displayFPS", ConsoleGetProperty, ConsoleSetProperty, kConsole_displayFPS),
    OOJS_PROPERTY_RO("platformDescription", ConsoleGetProperty, kConsole_platformDescription),
    OOJS_PROPERTY_RW("pedanticMode", ConsoleGetProperty, ConsoleSetProperty, kConsole_pedanticMode),
    OOJS_PROPERTY_RW("ignoreDroppedPackets", ConsoleGetProperty, ConsoleSetProperty, kConsole_ignoreDroppedPackets),
    OOJS_PROPERTY_HIDDEN_RW("__showErrorLocations", ConsoleGetProperty, ConsoleSetProperty, kConsole_showErrorLocations),
    OOJS_PROPERTY_HIDDEN_RW("__dumpStackForErrors", ConsoleGetProperty, ConsoleSetProperty, kConsole_dumpStackForErrors),
    OOJS_PROPERTY_HIDDEN_RW("__dumpStackForWarnings", ConsoleGetProperty, ConsoleSetProperty, kConsole_dumpStackForWarnings),
    OOJS_PROPERTY_RO("glVendorString", ConsoleGetProperty, kConsole_glVendorString),
    OOJS_PROPERTY_RO("glRendererString", ConsoleGetProperty, kConsole_glRendererString),
    OOJS_PROPERTY_RO("glFixedFunctionTextureUnitCount", ConsoleGetProperty, kConsole_glFixedFunctionTextureUnitCount),
    OOJS_PROPERTY_RO("glFragmentShaderTextureUnitCount", ConsoleGetProperty, kConsole_glFragmentShaderTextureUnitCount),

#define DEBUG_FLAG_DECL(x) OOJS_PROPERTY_RO(#x, ConsoleGetProperty, kConsole_##x)
    DEBUG_FLAG_DECL(DEBUG_LINKED_LISTS),
    DEBUG_FLAG_DECL(DEBUG_COLLISIONS),
    DEBUG_FLAG_DECL(DEBUG_DOCKING),
    DEBUG_FLAG_DECL(DEBUG_OCTREE_LOGGING),
    DEBUG_FLAG_DECL(DEBUG_BOUNDING_BOXES),
    DEBUG_FLAG_DECL(DEBUG_OCTREE_DRAW),
    DEBUG_FLAG_DECL(DEBUG_DRAW_NORMALS),
    DEBUG_FLAG_DECL(DEBUG_NO_DUST),
    DEBUG_FLAG_DECL(DEBUG_NO_SHADER_FALLBACK),
    DEBUG_FLAG_DECL(DEBUG_SHADER_VALIDATION),

    DEBUG_FLAG_DECL(DEBUG_MISC),
#undef DEBUG_FLAG_DECL
};

static const JSCFunctionListEntry sConsoleMethods[] = {
    // JS name							Function							min args
    JS_CFUNC_DEF("consoleMessage", 2, ConsoleConsoleMessage),
    JS_CFUNC_DEF("clearConsole", 0, ConsoleClearConsole),
    JS_CFUNC_DEF("scriptStack", 0, ConsoleScriptStack),
    JS_CFUNC_DEF("inspectEntity", 1, ConsoleInspectEntity),
#if OO_DEBUG
    JS_CFUNC_DEF("__setUpCallObjC", 1, ConsoleSetUpCallObjC),
#endif
    JS_CFUNC_DEF("isExecutableJavaScript", 2, ConsoleIsExecutableJavaScript),
    JS_CFUNC_DEF("displayMessagesInClass", 1, ConsoleDisplayMessagesInClass),
    JS_CFUNC_DEF("setDisplayMessagesInClass", 2, ConsoleSetDisplayMessagesInClass),
    JS_CFUNC_DEF("writeLogMarker", 0, ConsoleWriteLogMarker),
    JS_CFUNC_DEF("writeMemoryStats", 0, ConsoleWriteMemoryStats),
    JS_CFUNC_DEF("writeJSMemoryStats", 0, ConsoleWriteJSMemoryStats),
    JS_CFUNC_DEF("garbageCollect", 0, ConsoleGarbageCollect),
#if DEBUG
    JS_CFUNC_DEF("dumpHeap", 0, ConsoleDumpHeap),
#endif
#if OOJS_PROFILE
    JS_CFUNC_DEF("profile", 1, ConsoleProfile),
    JS_CFUNC_DEF("getProfile", 1, ConsoleGetProfile),
    JS_CFUNC_DEF("trace", 1, ConsoleTrace),
#endif
};

static JSClassExoticMethods sConsoleSettingsExoticMethods = {
    .get_own_property = ConsoleSettingsGetOwnProperty,
    .delete_property = ConsoleSettingsDeleteProperty,
    .define_own_property = ConsoleSettingsDefineOwnProperty,
    .get_property = ConsoleSettingsGetProperty,
    .set_property = ConsoleSettingsSetProperty,
};

static JSClassDef sConsoleSettingsClass = {
    .class_name = "ConsoleSettings",
    .finalizer = OOJSObjectWrapperFinalize, // (same as Console)
    .exotic = &sConsoleSettingsExoticMethods,
};

static void InitOOJSConsole(JSContext* context, JSValueConst global)
{
    OOJSRegisterClass(&sConsoleClassID, &sConsoleClass);
    OOJSInitClass(context, global, sConsoleClassID, JS_UNDEFINED, OOJSUnconstructableConstruct, 0,
        sConsoleProperties, OOJS_COUNT(sConsoleProperties), sConsoleMethods, OOJS_COUNT(sConsoleMethods), NULL, 0);
    OOJSRegisterObjectConverter(sConsoleClassID, OOJSBasicPrivateObjectConverter);

    OOJSRegisterClass(&sConsoleSettingsClassID, &sConsoleSettingsClass);
    OOJSInitClass(context, global, sConsoleSettingsClassID, JS_UNDEFINED, OOJSUnconstructableConstruct, 0,
        NULL, 0, NULL, 0, NULL, 0);
    OOJSRegisterObjectConverter(sConsoleSettingsClassID, OOJSBasicPrivateObjectConverter);
}

JSValue DebugMonitorToJSConsole(JSContext* context, OODebugMonitor* monitor)
{
    OOJS_PROFILE_ENTER

    // The classes belong to the context, so are set up again after every reset.
    JSValue consolePrototype = (sConsoleClassID != 0) ? JS_GetClassProto(context, sConsoleClassID) : JS_NULL;
    if (!JS_IsObject(consolePrototype)) {
        JS_FreeValue(context, consolePrototype);
        InitOOJSConsole(context, [[OOJavaScriptEngine sharedEngine] globalObject]);
        consolePrototype = JS_GetClassProto(context, sConsoleClassID);
    }

    // Create Console object
    JSValue object = JS_NewObjectProtoClass(context, consolePrototype, sConsoleClassID);
    JS_FreeValue(context, consolePrototype);
    if (JS_IsException(object)) {
        OOJSReportPendingException(context);
        return JS_NULL;
    }
    JS_SetOpaque(object, [monitor weakRetain]);

    // Create ConsoleSettings object
    JSValue settingsPrototype = JS_GetClassProto(context, sConsoleSettingsClassID);
    JSValue settingsObject = JS_NewObjectProtoClass(context, settingsPrototype, sConsoleSettingsClassID);
    JS_FreeValue(context, settingsPrototype);
    if (JS_IsException(settingsObject)) {
        OOJSReportPendingException(context);
        JS_FreeValue(context, object);
        return JS_NULL;
    }
    JS_SetOpaque(settingsObject, [monitor weakRetain]);

    if (JS_SetPropertyStr(context, object, "settings", settingsObject) < 0) {
        OOJSReportPendingException(context);
        JS_FreeValue(context, object);
        return JS_NULL;
    }

    return object;

    OOJS_PROFILE_EXIT
}

static OODebugMonitor* MonitorForConsoleObject(JSContext* context, JSValueConst object, const char* function)
{
    id monitor = OOJSNativeObjectFromJSObject(context, object);
    if (![monitor isKindOfClass:[OODebugMonitor class]]) {
        OOJSReportError(context, @"Expected OODebugMonitor, got %@ in %s. %@", [monitor class], function, @"This is an internal error, please report it.");
        return nil;
    }
    return monitor;
}

static JSValue ConsoleGetProperty(OOJS_GETTER_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    switch (magic) {
#ifndef NDEBUG
    case kConsole_debugFlags:
        return JS_NewUint32(context, (uint32_t)gDebugFlags);
#endif

    case kConsole_detailLevel:
        return [OOStringFromGraphicsDetail([UNIVERSE detailLevel]) oo_jsValueInContext:context];

    case kConsole_maximumDetailLevel:
        return [OOStringFromGraphicsDetail([[OOOpenGLExtensionManager sharedManager] maximumDetailLevel]) oo_jsValueInContext:context];

    case kConsole_displayFPS:
        return OOJSValueFromBOOL([UNIVERSE displayFPS]);

    case kConsole_platformDescription:
        return OOJSValueFromNativeObject(context, OOPlatformDescription());

    case kConsole_pedanticMode:
        return OOJSValueFromBOOL(sPedanticMode);

    case kConsole_ignoreDroppedPackets:
        return OOJSValueFromBOOL([[OODebugMonitor sharedDebugMonitor] TCPIgnoresDroppedPackets]);

    case kConsole_showErrorLocations:
        return OOJSValueFromBOOL([[OOJavaScriptEngine sharedEngine] showErrorLocations]);

    case kConsole_dumpStackForErrors:
        return OOJSValueFromBOOL([[OOJavaScriptEngine sharedEngine] dumpStackForErrors]);

    case kConsole_dumpStackForWarnings:
        return OOJSValueFromBOOL([[OOJavaScriptEngine sharedEngine] dumpStackForWarnings]);

    case kConsole_glVendorString:
        return OOJSValueFromNativeObject(context, [[OOOpenGLExtensionManager sharedManager] vendorString]);

    case kConsole_glRendererString:
        return OOJSValueFromNativeObject(context, [[OOOpenGLExtensionManager sharedManager] rendererString]);

    case kConsole_glFixedFunctionTextureUnitCount:
        return JS_NewInt32(context, [[OOOpenGLExtensionManager sharedManager] textureUnitCount]);

    case kConsole_glFragmentShaderTextureUnitCount:
        return JS_NewInt32(context, [[OOOpenGLExtensionManager sharedManager] textureImageUnitCount]);

#define DEBUG_FLAG_CASE(x) \
    case kConsole_##x:     \
        return JS_NewInt32(context, x);
        DEBUG_FLAG_CASE(DEBUG_LINKED_LISTS);
        DEBUG_FLAG_CASE(DEBUG_COLLISIONS);
        DEBUG_FLAG_CASE(DEBUG_DOCKING);
        DEBUG_FLAG_CASE(DEBUG_OCTREE_LOGGING);
        DEBUG_FLAG_CASE(DEBUG_BOUNDING_BOXES);
        DEBUG_FLAG_CASE(DEBUG_OCTREE_DRAW);
        DEBUG_FLAG_CASE(DEBUG_DRAW_NORMALS);
        DEBUG_FLAG_CASE(DEBUG_NO_DUST);
        DEBUG_FLAG_CASE(DEBUG_NO_SHADER_FALLBACK);
        DEBUG_FLAG_CASE(DEBUG_SHADER_VALIDATION);

        DEBUG_FLAG_CASE(DEBUG_MISC);
#undef DEBUG_FLAG_CASE

    default:
        OOJSReportBadPropertySelector(context, this, magic, sConsoleProperties, OOJS_COUNT(sConsoleProperties));
        return OOJSNativeFailure(context);
    }

    OOJS_NATIVE_EXIT
}

static JSValue ConsoleSetProperty(OOJS_SETTER_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    int32_t iValue;
    NSString* sValue;

    switch (magic) {
#ifndef NDEBUG
    case kConsole_debugFlags:
        if (OOJSValueToInt32(context, value, &iValue)) {
            gDebugFlags = iValue;
        }
        break;
#endif
    case kConsole_detailLevel:
        sValue = OOStringFromJSValue(context, value);
        OOJS_BEGIN_FULL_NATIVE(context)
        [UNIVERSE setDetailLevel:OOGraphicsDetailFromString(sValue)];
        OOJS_END_FULL_NATIVE
        break;

    case kConsole_displayFPS:
        [UNIVERSE setDisplayFPS:OOJSValueToBOOL(context, value)];
        break;

    case kConsole_pedanticMode:
        sPedanticMode = OOJSValueToBOOL(context, value);
        break;

    case kConsole_ignoreDroppedPackets:
        [[OODebugMonitor sharedDebugMonitor] setTCPIgnoresDroppedPackets:OOJSValueToBOOL(context, value)];
        break;

    case kConsole_showErrorLocations:
        [[OOJavaScriptEngine sharedEngine] setShowErrorLocations:OOJSValueToBOOL(context, value)];
        break;

    case kConsole_dumpStackForErrors:
        [[OOJavaScriptEngine sharedEngine] setDumpStackForErrors:OOJSValueToBOOL(context, value)];
        break;

    case kConsole_dumpStackForWarnings:
        [[OOJavaScriptEngine sharedEngine] setDumpStackForWarnings:OOJSValueToBOOL(context, value)];
        break;

    default:
        OOJSReportBadPropertySelector(context, this, magic, sConsoleProperties, OOJS_COUNT(sConsoleProperties));
        return OOJSNativeFailure(context);
    }

    return JS_UNDEFINED;

    OOJS_NATIVE_EXIT
}

static BOOL DoWeDefineAllDebugFlags(enum OODebugFlags flags) GCC_ATTR((unused));
static BOOL DoWeDefineAllDebugFlags(enum OODebugFlags flags)
{
    /*	This function doesn't do anything, but will generate a warning
            (Enumeration value 'DEBUG_FOO' not handled in switch) if a debug flag
            is added without updating it. The point is that if you get such a
            warning, you should first add a JS symbolic constant for the flag,
            then add it to the switch to suppress the warning.
            NOTE: don't add a default: to this switch, or I will have to hurt you.
            -- Ahruman 2010-04-11
    */
    switch (flags) {
    case DEBUG_LINKED_LISTS:
    case DEBUG_COLLISIONS:
    case DEBUG_DOCKING:
    case DEBUG_OCTREE_LOGGING:
    case DEBUG_BOUNDING_BOXES:
    case DEBUG_OCTREE_DRAW:
    case DEBUG_DRAW_NORMALS:
    case DEBUG_NO_DUST:
    case DEBUG_NO_SHADER_FALLBACK:
    case DEBUG_SHADER_VALIDATION:
    case DEBUG_MISC:
        return YES;
    }

    return NO;
}

// *** Settings ***

/*	The ConsoleSettings prototype is itself an instance of the class (see
        OOJSInitClass()), but has no monitor. It has no settings: properties
        defined on it while the class is set up, such as constructor, are
        ignored, and reads fall through to Object.prototype.
*/
static BOOL IsSettingsPrototype(JSValueConst object)
{
    return JS_GetOpaque(object, sConsoleSettingsClassID) == NULL;
}

// Setting key for a string property ID, or nil for other IDs (symbols).
static NSString* SettingKeyForPropertyID(JSContext* context, JSAtom propID)
{
    NSString* result = nil;
    JSValue idValue = JS_AtomToValue(context, propID);
    if (JS_IsString(idValue)) {
        result = OOStringFromJSValue(context, idValue);
    }
    JS_FreeValue(context, idValue);
    return result;
}

/*	SpiderMonkey's get hook was called for every read; settings that don't
        exist read as undefined, and settings are not reported as own properties
        (the enumerate hook was a stub), so for-in and Object.keys() see nothing.
*/
static int ConsoleSettingsGetOwnProperty(JSContext* context, JSPropertyDescriptor* desc, JSValueConst object, JSAtom propID)
{
    return NO;
}

static JSValue ConsoleSettingsGetProperty(JSContext* context, JSValueConst object, JSAtom propID, JSValueConst receiver)
{
    OOJS_NATIVE_ENTER(context)

    NSString* key = SettingKeyForPropertyID(context, propID);
    if (key == nil || IsSettingsPrototype(object)) {
        // Symbols, such as Symbol.toPrimitive: look them up on the prototype.
        JSValue prototype = JS_GetPrototype(context, object);
        JSValue result = JS_GetProperty(context, prototype, propID);
        JS_FreeValue(context, prototype);
        return result;
    }

    OODebugMonitor* monitor = MonitorForConsoleObject(context, object, __PRETTY_FUNCTION__);
    if (monitor == nil)
        return OOJSNativeFailure(context);

    id settingValue = [monitor configurationValueForKey:key];
    if (settingValue != nil)
        return [settingValue oo_jsValueInContext:context];
    return JS_UNDEFINED;

    OOJS_NATIVE_EXIT
}

static int SetSetting(JSContext* context, JSValueConst object, JSAtom propID, JSValueConst value)
{
    NSString* key = SettingKeyForPropertyID(context, propID);
    if (key == nil || IsSettingsPrototype(object))
        return YES;

    OODebugMonitor* monitor = MonitorForConsoleObject(context, object, __PRETTY_FUNCTION__);
    if (monitor == nil)
        return -1;

    // Not OOJS_BEGIN_FULL_NATIVE() - we use JSAPI while paused.
    OOJSPauseTimeLimiter();
    if (JS_IsNull(value) || JS_IsUndefined(value)) {
        [monitor setConfigurationValue:nil forKey:key];
    } else {
        id settingValue = OOJSNativeObjectFromJSValue(context, value);
        if (settingValue != nil) {
            [monitor setConfigurationValue:settingValue forKey:key];
        } else {
            OOJSReportWarning(context, @"debugConsole.settings: could not convert %@ to native object.", OOStringFromJSValue(context, value));
        }
    }
    OOJSResumeTimeLimiter();

    return YES;
}

static int ConsoleSettingsSetProperty(JSContext* context, JSValueConst object, JSAtom propID, JSValueConst value, JSValueConst receiver, int flags)
{
    @try {
        return SetSetting(context, object, propID, value);
    }
    @catch (id exception) {
        OOJSReportWrappedException(context, exception);
        return -1;
    }
}

// Object.defineProperty() and similar: treated as assignment of the value.
static int ConsoleSettingsDefineOwnProperty(JSContext* context, JSValueConst object, JSAtom propID, JSValueConst value, JSValueConst getter, JSValueConst setter, int flags)
{
    @try {
        if (!(flags & JS_PROP_HAS_VALUE))
            return YES;
        return SetSetting(context, object, propID, value);
    }
    @catch (id exception) {
        OOJSReportWrappedException(context, exception);
        return -1;
    }
}

static int ConsoleSettingsDeleteProperty(JSContext* context, JSValueConst object, JSAtom propID)
{
    @try {
        NSString* key = SettingKeyForPropertyID(context, propID);
        if (key == nil || IsSettingsPrototype(object))
            return NO;

        OODebugMonitor* monitor = MonitorForConsoleObject(context, object, __PRETTY_FUNCTION__);
        if (monitor == nil)
            return -1;

        [monitor setConfigurationValue:nil forKey:key];
        return YES;
    }
    @catch (id exception) {
        OOJSReportWrappedException(context, exception);
        return -1;
    }
}

// *** Methods ***

// function consoleMessage(colorCode : String, message : String [, emphasisStart : Number, emphasisLength : Number]) : void
static JSValue ConsoleConsoleMessage(OOJS_NATIVE_ARGS)
{
    NSRange emphasisRange = { 0, 0 };

    OOJS_NATIVE_ENTER(context)

    id monitor = nil;
    NSString *colorKey = nil,
             *message = nil;
    double location, length;

    // Not OOJS_BEGIN_FULL_NATIVE() - we use JSAPI while paused.
    OOJSPauseTimeLimiter();
    monitor = OOJSNativeObjectOfClassFromJSObject(context, OOJS_THIS, [OODebugMonitor class]);
    if (monitor == nil) {
        OOJSReportError(context, @"Expected OODebugMonitor, got %@ in %s. %@", [monitor class], __PRETTY_FUNCTION__, @"This is an internal error, please report it.");
        OOJSResumeTimeLimiter();
        return OOJSNativeFailure(context);
    }

    if (argc > 0)
        colorKey = OOStringFromJSValue(context, OOJS_ARGV[0]);
    if (argc > 1)
        message = OOStringFromJSValue(context, OOJS_ARGV[1]);

    if (argc > 3) {
        // Attempt to get two numbers, specifying an emphasis range.
        if (JS_ToFloat64(context, &location, OOJS_ARGV[2]) == 0 && JS_ToFloat64(context, &length, OOJS_ARGV[3]) == 0) {
            emphasisRange = (NSRange) { location, length };
        }
    }

    if (message == nil) {
        if (colorKey == nil) {
            OOJSReportWarning(context, @"Console.consoleMessage() called with no parameters.");
        } else {
            message = colorKey;
            colorKey = @"command-result";
        }
    }

    if (message != nil) {
        [monitor appendJSConsoleLine:message
                            colorKey:colorKey
                       emphasisRange:emphasisRange];
    }
    OOJSResumeTimeLimiter();

    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}

// function clearConsole() : void
static JSValue ConsoleClearConsole(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    OODebugMonitor* monitor = MonitorForConsoleObject(context, OOJS_THIS, __PRETTY_FUNCTION__);
    if (monitor == nil)
        return OOJSNativeFailure(context);

    [monitor clearJSConsole];
    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}

// function scriptStack() : Array
static JSValue ConsoleScriptStack(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    OOJS_RETURN_OBJECT([OOJSScript scriptStack]);

    OOJS_NATIVE_EXIT
}

// function inspectEntity(entity : Entity) : void
static JSValue ConsoleInspectEntity(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    Entity* entity = nil;

    if (argc > 0 && JSValueToEntity(context, OOJS_ARGV[0], &entity)) {
        OOJS_BEGIN_FULL_NATIVE(context)
        if ([entity respondsToSelector:@selector(inspect)]) {
            [entity inspect];
        }
        OOJS_END_FULL_NATIVE
    }

    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}

#if OO_DEBUG
// function callObjC(selector : String [, ...]) : Object
static JSValue ConsoleCallObjCMethod(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    id object = nil;
    JSValue result;
    BOOL OK;

    object = OOJSNativeObjectFromJSObject(context, OOJS_THIS);
    if (object == nil) {
        OOJSReportError(context, @"Attempt to call __callObjCMethod() for non-Objective-C object %@.", OOStringFromJSValueEvenIfNull(context, OOJS_THIS));
        return OOJSNativeFailure(context);
    }

    OOJSPauseTimeLimiter();
    result = JS_UNDEFINED;
    OK = OOJSCallObjCObjectMethod(context, object, [object oo_jsClassName], argc, OOJS_ARGV, &result);
    OOJSResumeTimeLimiter();

    if (!OK) {
        JS_FreeValue(context, result);
        return OOJSNativeFailure(context);
    }
    return result;

    OOJS_NATIVE_EXIT
}

// function __setUpCallObjC(object) -- object is expected to be Object.prototye.
static JSValue ConsoleSetUpCallObjC(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    if (EXPECT_NOT(argc < 1 || !JS_IsObject(OOJS_ARGV[0]))) {
        OOJSReportBadArguments(context, @"Console", @"__setUpCallObjC", argc, OOJS_ARGV, nil, @"Object.prototype");
        return OOJSNativeFailure(context);
    }

    // Read-only, permanent and not enumerable, as OOJS_METHOD_READONLY was.
    JSValue function = JS_NewCFunction(context, ConsoleCallObjCMethod, "callObjC", 1);
    JS_DefinePropertyValueStr(context, OOJS_ARGV[0], "callObjC", function, 0);
    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}
#endif

/*	Like SpiderMonkey's JS_BufferIsCompilableUnit(): true unless the code fails
        to compile only because it ends too soon, as when the console user is
        part way through typing a multi-line function. Code with other syntax
        errors is "executable" so that the error is reported when it's run.
        QuickJS reports running out of input as an "end of" error (input,
        string, comment, regexp) or an unexpected empty token, at the end of
        the code.
*/
static BOOL IsIncompleteSyntaxError(JSContext* context, JSValueConst exception, NSString* code)
{
    if (!JS_IsError(exception))
        return NO;

    JSValue nameVal = JS_GetPropertyStr(context, exception, "name");
    NSString* name = OOStringFromJSValue(context, nameVal);
    JS_FreeValue(context, nameVal);
    if (![name isEqualToString:@"SyntaxError"])
        return NO;

    JSValue messageVal = JS_GetPropertyStr(context, exception, "message");
    NSString* message = OOStringFromJSValue(context, messageVal);
    JS_FreeValue(context, messageVal);

    if ([message rangeOfString:@"end of " options:NSCaseInsensitiveSearch].location != NSNotFound)
        return YES;
    if ([message hasSuffix:@"''"])
        return YES;

    // Otherwise, incomplete if the error is at the very end of the code.
    JSValue stackVal = JS_GetPropertyStr(context, exception, "stack");
    NSString* stack = OOStringFromJSValue(context, stackVal);
    JS_FreeValue(context, stackVal);

    NSArray* lines = [code componentsSeparatedByString:@"\n"];
    NSString* endLocation = [NSString stringWithFormat:@"<console input>:%lu:%lu", (unsigned long)[lines count], (unsigned long)[[lines lastObject] length] + 1];
    NSString* firstFrame = [[stack componentsSeparatedByString:@"\n"] firstObject];
    return [firstFrame rangeOfString:endLocation].location != NSNotFound;
}

// function isExecutableJavaScript(this : Object, string : String) : Boolean
static JSValue ConsoleIsExecutableJavaScript(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    BOOL result = YES;

    if (argc < 2 || !JS_IsObject(OOJS_ARGV[0]) || !JS_IsString(OOJS_ARGV[1])) {
        OOJS_RETURN_BOOL(NO); // Fail silently
    }

    // Not OOJS_BEGIN_FULL_NATIVE() - we use JSAPI while paused.
    OOJSPauseTimeLimiter();

    NSString* string = OOStringFromJSValue(context, OOJS_ARGV[1]);
    NSData* stringData = [string dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableData* source = [NSMutableData dataWithData:stringData];
    [source appendBytes:"" length:1]; // JS_Eval() requires a terminating NUL.

    JSValue compiled = JS_Eval(context, [source bytes], [stringData length], "<console input>", JS_EVAL_TYPE_GLOBAL | JS_EVAL_FLAG_COMPILE_ONLY);
    if (JS_IsException(compiled)) {
        JSValue exception = JS_GetException(context);
        result = !IsIncompleteSyntaxError(context, exception, string);
        JS_FreeValue(context, exception);
    } else {
        JS_FreeValue(context, compiled);
    }

    OOJSResumeTimeLimiter();

    OOJS_RETURN_BOOL(result);

    OOJS_NATIVE_EXIT
}

// function displayMessagesInClass(class : String) : Boolean
static JSValue ConsoleDisplayMessagesInClass(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    NSString* messageClass = nil;

    if (argc > 0)
        messageClass = OOStringFromJSValue(context, OOJS_ARGV[0]);
    OOJS_RETURN_BOOL(messageClass != nil && OOLogWillDisplayMessagesInClass(messageClass));

    OOJS_NATIVE_EXIT
}

// function setDisplayMessagesInClass(class : String, flag : Boolean) : void
static JSValue ConsoleSetDisplayMessagesInClass(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    NSString* messageClass = nil;

    if (argc > 0)
        messageClass = OOStringFromJSValue(context, OOJS_ARGV[0]);
    if (messageClass != nil && argc > 1) {
        OOLogSetDisplayMessagesInClass(messageClass, OOJSValueToBOOL(context, OOJS_ARGV[1]));
    }
    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}

// function writeLogMarker() : void
static JSValue ConsoleWriteLogMarker(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    OOLogInsertMarker();
    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}

// function writeMemoryStats() : void
static JSValue ConsoleWriteMemoryStats(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    OOJS_BEGIN_FULL_NATIVE(context)
    [[OODebugMonitor sharedDebugMonitor] dumpMemoryStatistics];
    OOJS_END_FULL_NATIVE

    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}

// function writeJSMemoryStats() : void
static JSValue ConsoleWriteJSMemoryStats(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    OOJS_BEGIN_FULL_NATIVE(context)
    [[OODebugMonitor sharedDebugMonitor] dumpJSMemoryStatistics];
    OOJS_END_FULL_NATIVE

    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}

static size_t JSHeapSize(JSRuntime* runtime)
{
    JSMemoryUsage usage;
    JS_ComputeMemoryUsage(runtime, &usage);
    return (size_t)usage.malloc_size;
}

// function garbageCollect() : string
static JSValue ConsoleGarbageCollect(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    JSRuntime* runtime = JS_GetRuntime(context);
    size_t bytesBefore = JSHeapSize(runtime);
    JS_RunGC(runtime);
    size_t bytesAfter = JSHeapSize(runtime);

    OOJS_RETURN_OBJECT(([NSString stringWithFormat:@"Bytes before: %zu Bytes after: %zu", bytesBefore, bytesAfter]));

    OOJS_NATIVE_EXIT
}

#if DEBUG
static JSValue ConsoleDumpHeap(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    BOOL OK = NO;
    NSString* path = [[ResourceManager diagnosticFileLocation] stringByAppendingPathComponent:@"js-heaps.txt"];
    FILE* file = fopen([path UTF8String], "w");
    if (file != NULL) {
        JSRuntime* runtime = JS_GetRuntime(context);
        JSMemoryUsage usage;
        JS_ComputeMemoryUsage(runtime, &usage);
        JS_DumpMemoryUsage(file, &usage, runtime);
        fclose(file);
        OK = YES;
    }

    OOJS_RETURN_BOOL(OK);

    OOJS_NATIVE_EXIT
}
#endif

#if OOJS_PROFILE

// function profile(func : function [, Object this = debugConsole.script]) : String
static JSValue ConsoleProfile(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    if (EXPECT_NOT(OOJSIsProfiling())) {
        OOJSReportError(context, @"Profiling functions may not be called while already profiling.");
        return OOJSNativeFailure(context);
    }

    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
    OOTimeProfile* profile = nil;
    JSValue result = JS_UNDEFINED;

    if (PerformProfiling(context, @"profile", argc, OOJS_ARGV, NULL, NO, &profile)) {
        result = OOJSValueFromNativeObject(context, [profile description]);
    } else {
        result = OOJSNativeFailure(context);
    }

    [pool release];
    return result;

    OOJS_NATIVE_EXIT
}

// function getProfile(func : function [, Object this = debugConsole.script]) : Object { totalTime : Number, jsTime : Number, extensionTime : Number }
static JSValue ConsoleGetProfile(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    if (EXPECT_NOT(OOJSIsProfiling())) {
        OOJSReportError(context, @"Profiling functions may not be called while already profiling.");
        return OOJSNativeFailure(context);
    }

    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
    OOTimeProfile* profile = nil;
    JSValue result = JS_UNDEFINED;

    if (PerformProfiling(context, @"getProfile", argc, OOJS_ARGV, NULL, NO, &profile)) {
        result = OOJSValueFromNativeObject(context, profile);
    } else {
        result = OOJSNativeFailure(context);
    }

    [pool release];
    return result;

    OOJS_NATIVE_EXIT
}

// function trace(func : function [, Object this = debugConsole.script]) : [return type of func]
static JSValue ConsoleTrace(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    if (EXPECT_NOT(OOJSIsProfiling())) {
        OOJSReportError(context, @"Profiling functions may not be called while already profiling.");
        return OOJSNativeFailure(context);
    }

    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
    JSValue rval = JS_UNDEFINED;
    JSValue result;

    if (PerformProfiling(context, @"trace", argc, OOJS_ARGV, &rval, YES, NULL)) {
        result = rval;
    } else {
        result = OOJSNativeFailure(context);
    }

    [pool release];
    return result;

    OOJS_NATIVE_EXIT
}

/*	Calls argv[0] with argv[1] (or debugConsole.script) as this, profiling it.
        *outRval, if not NULL, is owned by the caller. On failure, any exception
        has been reported.
*/
static BOOL PerformProfiling(JSContext* context, NSString* nominalFunction, int argc, JSValueConst* argv, JSValue* outRval, BOOL trace, OOTimeProfile** outProfile)
{
    // Get function.
    if (argc < 1 || !OOJSValueIsFunction(context, argv[0])) {
        OOJSReportBadArguments(context, @"Console", nominalFunction, MIN(argc, 1), argv, nil, @"function");
        return NO;
    }
    JSValueConst function = argv[0];

    // Get "this" object.
    JSValue this;
    if (argc > 1)
        this = JS_DupValue(context, argv[1]);
    else {
        JSValue debugConsole = OOJSValueFromNativeObject(context, [OODebugMonitor sharedDebugMonitor]);
        this = JS_GetPropertyStr(context, debugConsole, "script");
        JS_FreeValue(context, debugConsole);
    }

    // Fiddle with time limiter.
    // We want to save the current limit, reset the limiter, and set the time limit to a long time.
#define LONG_TIME (1e7) // A long time - 115.7 days - but, crucially, finite.

    OOTimeDelta originalLimit = OOJSGetTimeLimiterLimit();
    OOJSSetTimeLimiterLimit(LONG_TIME);
    OOJSResetTimeLimiter();

    OOJSBeginProfiling(trace);

    // Call the function.
    JSValue rval = JS_Call(context, function, this, 0, NULL);

    // Get results.
    OOTimeProfile* profile = OOJSEndProfiling();
    if (outProfile != NULL)
        *outProfile = profile;

    // Restore original timer state.
    OOJSSetTimeLimiterLimit(originalLimit);
    OOJSResetTimeLimiter();

    JS_FreeValue(context, this);

    if (JS_IsException(rval)) {
        OOJSReportPendingException(context);
        return NO;
    }

    if (outRval != NULL)
        *outRval = rval;
    else
        JS_FreeValue(context, rval);
    return YES;
}

#endif // OOJS_PROFILE

#endif /* NDEBUG */
