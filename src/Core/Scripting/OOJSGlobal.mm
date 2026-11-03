/*

OOJSGlobal.m


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

#import "OOJSGlobal.h"
#import "OOJavaScriptEngine.h"

#import "GameController.h"
#import "GuiDisplayGen.h"
#import "MyOpenGLView.h"
#import "OOConstToJSString.h"
#import "OOConstToString.h"
#import "OOFoundationBridge.h"
#import "OOJSGuiScreenKeyDefinition.h"
#import "OOJSPlayer.h"
#import "OOPListView.h"
#import "OOStringBridge.h"
#import "OOStringExpander.h"
#import "OOSystemDescriptionManager.h"
#import "OOTexture.h"
#import "PlayerEntityScriptMethods.h"
#import "ResourceManager.h"
#include "oofnd/FileSystem.hpp"
#include "oofnd/ResourcePaths.hpp"
#include "oofnd/Scanner.hpp"

#if OOJSENGINE_MONITOR_SUPPORT

@interface OOJavaScriptEngine (OOMonitorSupportInternal)

// Implemented in OOJavaScriptEngine.mm (types from bead oo-3rb.203).
- (void)sendMonitorLogMessage:(const std::optional<std::string>&)message
             withMessageClass:(const std::optional<std::string>&)messageClass
                    inContext:(JSContext*)context;

@end

#endif

static const char* const kOOLogDebugMessage = "script.debug.message";

static JSValue GlobalGetProperty(OOJS_GETTER_ARGS);

// What -oo_stringForKey: made of the value it found: a string, or a number's text; nullopt (was
// nil) for no value or any other kind of value.
static std::optional<std::string> StringFromPList(const oo::PList* value)
{
    if (value == nullptr || !(value->isString() || value->isNumber()))
        return std::nullopt;
    return oo::PListGet<std::string>::from(value, std::string());
}

static std::optional<std::string> StringFromObject(id object)
{
    const oo::PList value = oo::PListFrom(object);
    return StringFromPList(&value);
}
#ifdef OO_DEBUG_MONITOR_ENABLED
static JSValue GlobalSetProperty(OOJS_SETTER_ARGS);
#endif

static JSValue GlobalLog(OOJS_NATIVE_ARGS);
static JSValue GlobalExpandDescription(OOJS_NATIVE_ARGS);
static JSValue GlobalKeyBindingDescription(OOJS_NATIVE_ARGS);
static JSValue GlobalExpandMissionText(OOJS_NATIVE_ARGS);
static JSValue GlobalDisplayNameForCommodity(OOJS_NATIVE_ARGS);
static JSValue GlobalRandomName(OOJS_NATIVE_ARGS);
static JSValue GlobalRandomInhabitantsDescription(OOJS_NATIVE_ARGS);
static JSValue GlobalSetScreenBackground(OOJS_NATIVE_ARGS);
static JSValue GlobalSetScreenOverlay(OOJS_NATIVE_ARGS);
static JSValue GlobalGetScreenBackgroundForKey(OOJS_NATIVE_ARGS);
static JSValue GlobalSetScreenBackgroundForKey(OOJS_NATIVE_ARGS);
static JSValue GlobalAutoAIForRole(OOJS_NATIVE_ARGS);
static JSValue GlobalPauseGame(OOJS_NATIVE_ARGS);
static JSValue GlobalGetGuiColorSettingForKey(OOJS_NATIVE_ARGS);
static JSValue GlobalSetGuiColorSettingForKey(OOJS_NATIVE_ARGS);
static JSValue GlobalSetExtraGuiScreenKeys(OOJS_NATIVE_ARGS);
static JSValue GlobalClearExtraGuiScreenKeys(OOJS_NATIVE_ARGS);

#ifdef OO_DEBUG_MONITOR_ENABLED
static JSValue GlobalTakeSnapShot(OOJS_NATIVE_ARGS);
static JSValue GlobalQuitGame(OOJS_NATIVE_ARGS);
#endif

/*	QuickJS's global object is an ordinary object, so the SpiderMonkey global
        class's tinyid getter and setter become accessor properties defined on
        the global object.
*/

enum {
    // Property IDs
    kGlobal_galaxyNumber, // galaxy number, integer, read-only
    kGlobal_global, // global.global.global.global, integer, read-only
    kGlobal_guiScreen, // current GUI screen, string, read-only
#ifdef OO_DEBUG_MONITOR_ENABLED
    kGlobal_timeAccelerationFactor // time acceleration, float, read/write
#endif
};

static const JSCFunctionListEntry sGlobalProperties[] = {
    // JS name					Getter				Setter				ID
    OOJS_PROPERTY_RO("galaxyNumber", GlobalGetProperty, kGlobal_galaxyNumber),
    OOJS_PROPERTY_RO("guiScreen", GlobalGetProperty, kGlobal_guiScreen),
#ifdef OO_DEBUG_MONITOR_ENABLED
    OOJS_PROPERTY_RW("timeAccelerationFactor", GlobalGetProperty, GlobalSetProperty, kGlobal_timeAccelerationFactor),
#endif
};

static const JSCFunctionListEntry sGlobalMethods[] = {
    // JS name							Function								min args
    JS_CFUNC_DEF("log", 1, GlobalLog),
    JS_CFUNC_DEF("autoAIForRole", 1, GlobalAutoAIForRole),
    JS_CFUNC_DEF("expandDescription", 1, GlobalExpandDescription),
    JS_CFUNC_DEF("expandMissionText", 1, GlobalExpandMissionText),
    JS_CFUNC_DEF("displayNameForCommodity", 1, GlobalDisplayNameForCommodity),
    JS_CFUNC_DEF("randomName", 0, GlobalRandomName),
    JS_CFUNC_DEF("randomInhabitantsDescription", 1, GlobalRandomInhabitantsDescription),
    JS_CFUNC_DEF("setScreenBackground", 1, GlobalSetScreenBackground),
    JS_CFUNC_DEF("getScreenBackgroundForKey", 1, GlobalGetScreenBackgroundForKey),
    JS_CFUNC_DEF("setScreenBackgroundForKey", 2, GlobalSetScreenBackgroundForKey),
    JS_CFUNC_DEF("setScreenOverlay", 1, GlobalSetScreenOverlay),
    JS_CFUNC_DEF("getGuiColorSettingForKey", 1, GlobalGetGuiColorSettingForKey),
    JS_CFUNC_DEF("setGuiColorSettingForKey", 2, GlobalSetGuiColorSettingForKey),
    JS_CFUNC_DEF("keyBindingDescription", 1, GlobalKeyBindingDescription),
    JS_CFUNC_DEF("setExtraGuiScreenKeys", 2, GlobalSetExtraGuiScreenKeys),
    JS_CFUNC_DEF("clearExtraGuiScreenKeys", 2, GlobalClearExtraGuiScreenKeys),

#ifdef OO_DEBUG_MONITOR_ENABLED
    JS_CFUNC_DEF("takeSnapShot", 1, GlobalTakeSnapShot),
    JS_CFUNC_DEF("quitGame", 0, GlobalQuitGame),
#endif
    JS_CFUNC_DEF("pauseGame", 0, GlobalPauseGame),
};

void SetUpOOJSGlobal(JSContext* context, JSValueConst global)
{
    JS_SetPropertyFunctionList(context, global, sGlobalProperties, OOJS_COUNT(sGlobalProperties));
    JS_SetPropertyFunctionList(context, global, sGlobalMethods, OOJS_COUNT(sGlobalMethods));
}

static JSValue GlobalGetProperty(OOJS_GETTER_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    PlayerEntity* player = OOPlayerForScripting();

    switch (magic) {
    case kGlobal_galaxyNumber:
        return JS_NewInt32(context, [player currentGalaxyID]);

    case kGlobal_guiScreen:
        return OOJSValueFromGUIScreenID(context, [player guiScreen]);

#ifdef OO_DEBUG_MONITOR_ENABLED
    case kGlobal_timeAccelerationFactor:
        return JS_NewNumber(context, [UNIVERSE timeAccelerationFactor]);
#endif

    default:
        OOJSReportBadPropertySelector(context, thisObj, magic, sGlobalProperties, OOJS_COUNT(sGlobalProperties));
        return JS_EXCEPTION;
    }

    OOJS_NATIVE_EXIT
}

#ifdef OO_DEBUG_MONITOR_ENABLED
static JSValue GlobalSetProperty(OOJS_SETTER_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    double fValue;

    switch (magic) {
    case kGlobal_timeAccelerationFactor:
        if (JS_ToFloat64(context, &fValue, value) == 0) {
            [UNIVERSE setTimeAccelerationFactor:fValue];
            return JS_UNDEFINED;
        }
        JS_FreeValue(context, JS_GetException(context));
        break;

    default:
        OOJSReportBadPropertySelector(context, thisObj, magic, sGlobalProperties, OOJS_COUNT(sGlobalProperties));
        return JS_EXCEPTION;
    }

    OOJSReportBadPropertyValue(context, thisObj, magic, sGlobalProperties, OOJS_COUNT(sGlobalProperties), value);
    return JS_EXCEPTION;

    OOJS_NATIVE_EXIT
}
#endif

// *** Methods ***

// log([messageClass : String,] message : string, ...)
static JSValue GlobalLog(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    std::optional<std::string> message;
    std::string messageClass;

    if (EXPECT_NOT(argc < 1)) {
        OOJS_RETURN_VOID;
    }
    if (argc < 2) {
        messageClass = kOOLogDebugMessage;
        message = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
    } else {
        messageClass = cxx_OOStringFromJSValueEvenIfNull(context, OOJS_ARGV[0]).value_or(std::string());
        if (!oo::log::willDisplay(messageClass)) {
            // Do nothing (and short-circuit) if message class is filtered out.
            OOJS_RETURN_VOID;
        }

        // The remaining arguments as strings, joined with ", " (as +concatenationOfStringsFromJavaScriptValues:... did).
        std::string joined;
        for (int i = 1; i < argc; i++) {
            if (i > 1)
                joined += ", ";
            joined += cxx_OOStringFromJSValueEvenIfNull(context, OOJS_ARGV[i]).value_or(std::string());
        }
        message = joined;
    }

    OOJS_BEGIN_FULL_NATIVE(context)
    OO_LOG(messageClass, "{}", message.value_or("(null)"));

#if OOJSENGINE_MONITOR_SUPPORT
    [[OOJavaScriptEngine sharedEngine] sendMonitorLogMessage:message
                                            withMessageClass:std::nullopt
                                                   inContext:context];
#endif
    OOJS_END_FULL_NATIVE

    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}

// expandDescription(description : String [, overrides : object (dictionary)]) : String
static JSValue GlobalExpandDescription(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    std::optional<std::string> string;
    oo::PList overrides;

    if (argc > 0)
        string = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
    if (!string.has_value()) {
        cxx_OOJSReportBadArguments(context, std::nullopt, "expandDescription", MIN(argc, 1), OOJS_ARGV, std::nullopt, "string");
        return JS_EXCEPTION;
    }
    if (argc > 1) {
        overrides = OOJSDictionaryFromStringTable(context, OOJS_ARGV[1]);
    }

    OOJS_BEGIN_FULL_NATIVE(context)
    string = cxx_OOExpandDescriptionString(kNilRandomSeed, *string, overrides, oo::PList(), std::nullopt, kOOExpandForJavaScript | kOOExpandGoodRNG);
    OOJS_END_FULL_NATIVE

    OOJS_RETURN_OBJECT(oo::NSStringOrNil(string));

    OOJS_NATIVE_EXIT
}

static JSValue GlobalKeyBindingDescription(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    std::optional<std::string> string;
    PlayerEntity* player = OOPlayerForScripting();

    if (argc > 0)
        string = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
    if (!string.has_value()) {
        cxx_OOJSReportBadArguments(context, std::nullopt, "keyBindingDescription", MIN(argc, 1), OOJS_ARGV, std::nullopt, "string");
        return JS_EXCEPTION;
    }

    OOJS_BEGIN_FULL_NATIVE(context)
    string = [player cxx_keyBindingDescription2:*string];
    OOJS_END_FULL_NATIVE

    OOJS_RETURN_OBJECT(oo::NSStringOrNil(string));

    OOJS_NATIVE_EXIT
}

// expandMissionText(textKey : String [, overrides : object (dictionary)]) : String
static JSValue GlobalExpandMissionText(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    std::optional<std::string> string;
    oo::PList overrides;

    if (argc > 0)
        string = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
    if (!string.has_value()) {
        cxx_OOJSReportBadArguments(context, std::nullopt, "expandMissionText", MIN(argc, 1), OOJS_ARGV, std::nullopt, "string");
        return JS_EXCEPTION;
    }
    if (argc > 1) {
        overrides = OOJSDictionaryFromStringTable(context, OOJS_ARGV[1]);
    }

    string = StringFromObject([oo::ObjectFromPList([UNIVERSE cxx_missiontext]) objectForKey:oo::NSStringFrom(*string)]);
    if (string.has_value())
        string = cxx_OOExpandDescriptionString(kNilRandomSeed, *string, overrides, oo::PList(), std::nullopt, kOOExpandForJavaScript | kOOExpandBackslashN | kOOExpandGoodRNG); // nil expanded to nil

    OOJS_RETURN_OBJECT(oo::NSStringOrNil(string));

    OOJS_NATIVE_EXIT
}

// displayNameForCommodity(commodityName : String) : String
static JSValue GlobalDisplayNameForCommodity(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    std::optional<std::string> string;

    if (argc > 0)
        string = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
    if (!string.has_value()) {
        cxx_OOJSReportBadArguments(context, std::nullopt, "displayNameForCommodity", MIN(argc, 1), OOJS_ARGV, std::nullopt, "string");
        return JS_EXCEPTION;
    }
    OOJS_RETURN_OBJECT(oo::NSStringFrom(cxx_CommodityDisplayNameForSymbolicName(*string)));

    OOJS_NATIVE_EXIT
}

// randomName() : String
static JSValue GlobalRandomName(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    /*	Temporarily set the system generation seed to a "really random" seed,
            so randomName() isn't repeatable.
    */
    RNG_Seed savedSeed = currentRandomSeed();
    setRandomSeed((RNG_Seed) { (int32_t)Ranrot(), (int32_t)Ranrot(), (int32_t)Ranrot(), (int32_t)Ranrot() });

    std::optional<std::string> result = cxx_OOExpand("%N");

    // Restore seed.
    setRandomSeed(savedSeed);

    OOJS_RETURN_OBJECT(oo::NSStringOrNil(result));

    OOJS_NATIVE_EXIT
}

// randomInhabitantsDescription() : String
static JSValue GlobalRandomInhabitantsDescription(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    std::optional<std::string> string;
    Random_Seed aSeed;
    int isPlural = YES;

    if (argc > 0 && (isPlural = JS_ToBool(context, OOJS_ARGV[0])) < 0) {
        JS_FreeValue(context, JS_GetException(context));
        cxx_OOJSReportBadArguments(context, std::nullopt, "randomInhabitantsDescription", 1, OOJS_ARGV, std::nullopt, "boolean");
        return JS_EXCEPTION;
    }

    make_pseudo_random_seed(&aSeed);
    string = [UNIVERSE cxx_getSystemInhabitants:Ranrot() % OO_SYSTEMS_PER_GALAXY plural:isPlural];
    OOJS_RETURN_OBJECT(oo::NSStringOrNil(string));

    OOJS_NATIVE_EXIT
}

static JSValue GlobalClearExtraGuiScreenKeys(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    BOOL result = NO;
    PlayerEntity* player = OOPlayerForScripting();

    if (EXPECT_NOT(argc < 2)) {
        cxx_OOJSReportBadArguments(context, std::nullopt, "setExtraGuiScreenKeys", 0, OOJS_ARGV, std::nullopt, "missing arguments");
        return JS_EXCEPTION;
    }

    std::optional<std::string> key = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
    if (EXPECT_NOT(!key.has_value() || key->empty())) {
        cxx_OOJSReportBadArguments(context, std::nullopt, "clearExtraGuiScreenKeys", 1, OOJS_ARGV, std::nullopt, "key");
        return JS_EXCEPTION;
    }

    OOGUIScreenID gui = OOGUIScreenIDFromJSValue(context, OOJS_ARGV[1]);
    if (!gui) {
        cxx_OOJSReportBadArguments(context, std::nullopt, "clearExtraGuiScreenKeys", 0, OOJS_ARGV, std::nullopt, "guiScreen invalid entry");
        return JS_EXCEPTION;
    }

    [player cxx_clearExtraGuiScreenKeys:gui key:*key];

    result = YES;
    OOJS_RETURN_BOOL(result);

    OOJS_NATIVE_EXIT
}

/*	Get a property of a parameter object. Returns an owned value. If a getter
        throws, the exception is reported and cleared and the property is treated
        as undefined. (SpiderMonkey's JS_GetProperty() returned false, which the
        callers below treat as a missing property; a native must not return
        normally with an exception pending in QuickJS.)
*/
static JSValue GetParam(JSContext* context, JSValueConst object, const char* key)
{
    JSValue value = JS_GetPropertyStr(context, object, key);
    if (JS_IsException(value)) {
        OOJSReportPendingException(context);
        return JS_UNDEFINED;
    }
    return value;
}

static JSValue GlobalSetExtraGuiScreenKeys(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    BOOL result = NO;
    JSValue callback = JS_UNDEFINED;
    JSValue value = JS_UNDEFINED;
    std::optional<std::string> key;
    OOGUIScreenID gui;
    oo::PList keydefs;
    JSValue params = JS_UNDEFINED;
    PlayerEntity* player = OOPlayerForScripting();
    // The SpiderMonkey version always described two arguments from argv[1] on; don't read past argv.
    int defArgc = MIN(argc - 1, 2);

    if (EXPECT_NOT(argc < 1)) {
        cxx_OOJSReportBadArguments(context, std::nullopt, "setExtraGuiScreenKeys", 0, OOJS_ARGV, std::nullopt, "key, definition");
        return JS_EXCEPTION;
    }
    key = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);

    // Validate arguments.
    // (SpiderMonkey's JS_ValueToObject() accepted null and undefined, yielding no object; treat them as invalid.)
    if (argc >= 2 && !JS_IsNull(OOJS_ARGV[1]) && !JS_IsUndefined(OOJS_ARGV[1])) {
        params = JS_ToObject(context, OOJS_ARGV[1]);
        if (JS_IsException(params)) {
            JS_FreeValue(context, JS_GetException(context));
            params = JS_UNDEFINED;
        }
    }
    if (!JS_IsObject(params)) {
        cxx_OOJSReportBadArguments(context, "global", "setExtraGuiScreenKeys", defArgc, &OOJS_ARGV[1], std::nullopt, "key, definition: definition is not a valid dictionary.");
        return JS_EXCEPTION;
    }

    value = GetParam(context, params, "guiScreen");
    if (JS_IsUndefined(value)) {
        JS_FreeValue(context, params);
        cxx_OOJSReportBadArguments(context, "global", "setExtraGuiScreenKeys", defArgc, &OOJS_ARGV[1], std::nullopt, "key, definition: must have a 'guiScreen' property.");
        return JS_EXCEPTION;
    }

    gui = OOGUIScreenIDFromJSValue(context, value);
    JS_FreeValue(context, value);
    // gui will be 0 for invalid screen id's as well as GUI_SCREEN_MAIN
    if (gui == 0 || gui == GUI_SCREEN_LOAD || gui == GUI_SCREEN_SAVE || gui == GUI_SCREEN_STICKMAPPER || gui == GUI_SCREEN_OXZMANAGER || gui == GUI_SCREEN_NEWGAME || gui == GUI_SCREEN_SAVE_OVERWRITE || gui == GUI_SCREEN_KEYBOARD || gui == GUI_SCREEN_STICKPROFILE || gui == GUI_SCREEN_KEYBOARD_CONFIRMCLEAR || gui == GUI_SCREEN_KEYBOARD_CONFIG || gui == GUI_SCREEN_KEYBOARD_ENTRY || gui == GUI_SCREEN_KEYBOARD_LAYOUT) {
        JS_FreeValue(context, params);
        cxx_OOJSReportBadArguments(context, "global", "setExtraGuiScreenKeys", defArgc, &OOJS_ARGV[1], std::nullopt, "key, definition: 'guiScreen' property must be a permitted and valid GUI_SCREEN idenfifier.");
        return JS_EXCEPTION;
    }

    value = GetParam(context, params, "registerKeys");
    if (JS_IsUndefined(value)) {
        JS_FreeValue(context, params);
        cxx_OOJSReportBadArguments(context, "global", "setExtraGuiScreenKeys", defArgc, &OOJS_ARGV[1], std::nullopt, "key, definition: must have a 'registerKeys' property.");
        return JS_EXCEPTION;
    }
    if (!JS_IsNull(value)) {
        if (JS_IsObject(value)) {
            keydefs = cxx_OOJSPListFromJSObject(context, value);
        } else {
            JS_FreeValue(context, value);
            JS_FreeValue(context, params);
            cxx_OOJSReportBadArguments(context, "global", "setExtraGuiScreenKeys", defArgc, &OOJS_ARGV[1], std::nullopt, "key, definition: registerKeys is not a valid dictionary.");
            return JS_EXCEPTION;
        }
    }
    JS_FreeValue(context, value);

    callback = GetParam(context, params, "callback");
    if (JS_IsUndefined(callback)) {
        JS_FreeValue(context, params);
        cxx_OOJSReportBadArguments(context, "global", "setExtraGuiScreenKeys", defArgc, &OOJS_ARGV[1], std::nullopt, "key, definition; must have a 'callback' property.");
        return JS_EXCEPTION;
    }
    if (!OOJSValueIsFunction(context, callback)) {
        JS_FreeValue(context, callback);
        JS_FreeValue(context, params);
        cxx_OOJSReportBadArguments(context, "global", "setExtraGuiScreenKeys", defArgc, &OOJS_ARGV[1], std::nullopt, "key, definition; 'callback' property must be a function.");
        return JS_EXCEPTION;
    }

    OOJSGuiScreenKeyDefinition* definition = [[OOJSGuiScreenKeyDefinition alloc] init];
    [definition cxx_setName:key];
    [definition setRegisterKeys:keydefs];
    [definition setCallback:callback]; // Takes its own reference.
    JS_FreeValue(context, callback);

    // get callback 'this'
    value = GetParam(context, params, "cbThis");
    if (!JS_IsUndefined(value)) {
        // As with SpiderMonkey's JS_ValueToObject(), null gives no object; primitives are boxed.
        if (!JS_IsNull(value)) {
            JSValue callbackThis = JS_ToObject(context, value);
            if (JS_IsException(callbackThis)) {
                JS_FreeValue(context, JS_GetException(context));
            } else {
                [definition setCallbackThis:callbackThis];
            }
            JS_FreeValue(context, callbackThis);
        }
        // can do .bind(this) for callback instead
    }
    JS_FreeValue(context, value);
    JS_FreeValue(context, params);

    result = [player setExtraGuiScreenKeys:gui definition:definition];
    [definition release];

    OOJS_RETURN_BOOL(result);

    OOJS_NATIVE_EXIT
}

// setScreenBackground(descriptor : guiTextureDescriptor) : Boolean
static JSValue GlobalSetScreenBackground(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    BOOL result = NO;
    JSValueConst value = (argc > 0) ? OOJS_ARGV[0] : JS_NULL;

    if (EXPECT_NOT(argc == 0)) {
        cxx_OOJSReportWarning(context, "Usage error: %s() called with no arguments. Treating as %s(null). This call may fail in a future version of Oolite.", "setScreenBackground", "setScreenBackground");
    } else if (EXPECT_NOT(JS_IsUndefined(value))) {
        cxx_OOJSReportBadArguments(context, std::nullopt, "setScreenBackground", 1, &value, std::nullopt, "GUI texture descriptor");
        return JS_EXCEPTION;
    }

    if ([UNIVERSE viewDirection] == VIEW_GUI_DISPLAY) {
        GuiDisplayGen* gui = [UNIVERSE gui];
        oo::PList descriptor = [gui cxx_textureDescriptorFromJSValue:value inContext:context callerDescription:std::string("setScreenBackground()")];

        result = [gui cxx_setBackgroundTextureDescriptor:descriptor];

        // add some permanence to the override if we're in the equip ship screen
        if (result && [PLAYER guiScreen] == GUI_SCREEN_EQUIP_SHIP)
            [PLAYER cxx_setEquipScreenBackgroundDescriptor:descriptor];
    }

    OOJS_RETURN_BOOL(result);

    OOJS_NATIVE_EXIT
}

static JSValue GlobalGetScreenBackgroundForKey(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    if (EXPECT_NOT(argc == 0)) {
        cxx_OOJSReportBadArguments(context, std::nullopt, "getScreenBackgroundDefault", 0, OOJS_ARGV, std::nullopt, "missing arguments");
        return JS_EXCEPTION;
    }
    std::optional<std::string> key = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
    if (EXPECT_NOT(!key.has_value() || key->empty())) {
        cxx_OOJSReportBadArguments(context, std::nullopt, "getScreenBackgroundDefault", 0, OOJS_ARGV, std::nullopt, "key");
        return JS_EXCEPTION;
    }
    OOJS_RETURN_OBJECT(oo::ObjectFromPList([UNIVERSE cxx_screenTextureDescriptorForKey:*key]));

    OOJS_NATIVE_EXIT
}

// setScreenBackgroundDefault (key : String, descriptor : guiTextureDescriptor) : boolean
static JSValue GlobalSetScreenBackgroundForKey(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    BOOL result = NO;

    if (EXPECT_NOT(argc < 2)) {
        cxx_OOJSReportBadArguments(context, std::nullopt, "setScreenBackgroundDefault", 0, OOJS_ARGV, std::nullopt, "missing arguments");
        return JS_EXCEPTION;
    }

    std::optional<std::string> key = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
    JSValueConst value = OOJS_ARGV[1];
    if (EXPECT_NOT(!key.has_value() || key->empty())) {
        cxx_OOJSReportBadArguments(context, std::nullopt, "setScreenBackgroundDefault", 0, OOJS_ARGV, std::nullopt, "key");
        return JS_EXCEPTION;
    }

    GuiDisplayGen* gui = [UNIVERSE gui];
    oo::PList descriptor = [gui cxx_textureDescriptorFromJSValue:value inContext:context callerDescription:std::string("setScreenBackgroundDefault()")];

    [UNIVERSE cxx_setScreenTextureDescriptorForKey:*key descriptor:oo::PListFrom(oo::ObjectFromPList(descriptor))];
    result = YES;

    OOJS_RETURN_BOOL(result);

    OOJS_NATIVE_EXIT
}

// setScreenOverlay(descriptor : guiTextureDescriptor) : Boolean
static JSValue GlobalSetScreenOverlay(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    BOOL result = NO;
    JSValueConst value = (argc > 0) ? OOJS_ARGV[0] : JS_NULL;

    if (EXPECT_NOT(argc == 0)) {
        cxx_OOJSReportWarning(context, "Usage error: %s() called with no arguments. Treating as %s(null). This call may fail in a future version of Oolite.", "setScreenOverlay", "setScreenOverlay");
    } else if (EXPECT_NOT(JS_IsUndefined(value))) {
        cxx_OOJSReportBadArguments(context, std::nullopt, "setScreenOverlay", 1, &value, std::nullopt, "GUI texture descriptor");
        return JS_EXCEPTION;
    }

    if ([UNIVERSE viewDirection] == VIEW_GUI_DISPLAY) {
        GuiDisplayGen* gui = [UNIVERSE gui];
        oo::PList descriptor = [gui cxx_textureDescriptorFromJSValue:value inContext:context callerDescription:std::string("setScreenOverlay()")];

        result = [gui cxx_setForegroundTextureDescriptor:descriptor];
    }

    OOJS_RETURN_BOOL(result);

    OOJS_NATIVE_EXIT
}

static JSValue GlobalGetGuiColorSettingForKey(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    if (EXPECT_NOT(argc == 0)) {
        cxx_OOJSReportBadArguments(context, std::nullopt, "getGuiColorForKey", 0, OOJS_ARGV, std::nullopt, "missing arguments");
        return JS_EXCEPTION;
    }
    std::optional<std::string> key = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
    if (EXPECT_NOT(!key.has_value() || key->empty())) {
        cxx_OOJSReportBadArguments(context, std::nullopt, "getGuiColorForKey", 0, OOJS_ARGV, std::nullopt, "key");
        return JS_EXCEPTION;
    }
    if (key->find("color") == std::string::npos) {
        cxx_OOJSReportBadArguments(context, std::nullopt, "getGuiColorForKey", 0, OOJS_ARGV, std::nullopt, "valid color key setting");
        return JS_EXCEPTION;
    }

    GuiDisplayGen* gui = [UNIVERSE gui];
    OOColor* col = [gui cxx_colorFromSetting:*key defaultValue:nil];

    // The components as the colour's -normalizedArray gave them: floats, nil for no colour.
    oo::PList::Array components;
    for (float component : [col cxx_normalizedArray])
        components.push_back(oo::PList::singleReal(component));
    OOJS_RETURN_OBJECT(col != nil ? oo::ObjectFromPList(oo::PList(std::move(components))) : nil);

    OOJS_NATIVE_EXIT
}

// setGuiColorForKey(descriptor : OOColor) : boolean
static JSValue GlobalSetGuiColorSettingForKey(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    BOOL result = NO;
    OOColor* col = nil;

    if (EXPECT_NOT(argc != 2)) {
        cxx_OOJSReportBadArguments(context, std::nullopt, "setGuiColorForKey", 0, OOJS_ARGV, std::nullopt, "missing arguments");
        return JS_EXCEPTION;
    }

    std::optional<std::string> key = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
    JSValueConst value = OOJS_ARGV[1];
    if (EXPECT_NOT(!key.has_value() || key->empty())) {
        cxx_OOJSReportBadArguments(context, std::nullopt, "setGuiColorForKey", 0, OOJS_ARGV, std::nullopt, "key");
        return JS_EXCEPTION;
    }
    if (key->find("color") == std::string::npos) {
        cxx_OOJSReportBadArguments(context, std::nullopt, "setGuiColorForKey", 0, OOJS_ARGV, std::nullopt, "valid color key setting");
        return JS_EXCEPTION;
    }

    if (!JS_IsNull(value)) {
        col = [OOColor colorWithDescription:oo::ObjectFromPList(cxx_OOJSPListFromJSValue(context, value))];
        if (col == nil) {
            cxx_OOJSReportBadArguments(context, std::nullopt, "setGuiColorForKey", 1, OOJS_ARGV, std::nullopt, "color descriptor");
            return JS_EXCEPTION;
        }
    }

    GuiDisplayGen* gui = [UNIVERSE gui];
    [gui cxx_setGuiColorSettingFromKey:*key color:col];
    result = YES;

    OOJS_RETURN_BOOL(result);

    OOJS_NATIVE_EXIT
}

#ifdef OO_DEBUG_MONITOR_ENABLED
// takeSnapShot([name : alphanumeric String]) : Boolean
static JSValue GlobalTakeSnapShot(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    std::optional<std::string> value;
    const oo::str::CharacterSet alphanumerics = oo::str::CharacterSet::alphanumeric();
    BOOL result = NO;

    // Allowed: the alphanumeric character set plus "_-", tested per UTF-16 unit as -rangeOfCharacterFromSet: did.
    auto isAllowed = [&alphanumerics](const std::string& name) {
        for (char16_t unit : oo::utf8ToUtf16(name)) {
            if (unit != u'_' && unit != u'-' && !alphanumerics.contains(unit))
                return false;
        }
        return true;
    };

    if (argc > 0) {
        value = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
        if (EXPECT_NOT(!value.has_value() || !isAllowed(*value))) {
            cxx_OOJSReportBadArguments(context, std::nullopt, "takeSnapShot", argc, OOJS_ARGV, std::nullopt, "alphanumeric string");
            return JS_EXCEPTION;
        }
    }

    const oo::ResourcePaths resourcePaths = oo::ResourcePaths::current();
    const oo::fs::Path savedir = resourcePaths.saveDirectory();
    const oo::fs::FileType saveType = oo::fs::fileType(savedir);
    std::string playerFileDirectory;
    if (saveType == oo::fs::FileType::none) {
        if (oo::fs::createDirectories(savedir))
            playerFileDirectory = oo::fs::utf8String(savedir);
        else
            playerFileDirectory = oo::fs::utf8String(resourcePaths.homeDirectory());
    } else if (saveType != oo::fs::FileType::directory) {
        playerFileDirectory = oo::fs::utf8String(resourcePaths.homeDirectory());
    } else {
        playerFileDirectory = oo::fs::utf8String(savedir);
    }
    const auto freeBytes = oo::fs::freeSpace(oo::fs::pathFromUTF8(playerFileDirectory));

    if (freeBytes.has_value()) {
        double freeSpace = static_cast<double>(*freeBytes);
        if (freeSpace < 1073741824) // less than 1 GB free on disk?
        {
            cxx_OOJSReportWarning(context, "takeSnapShot: function disabled when free disk space is less than 1GB.");
            OOJS_RETURN_BOOL(NO);
        }
    }

    OOJS_BEGIN_FULL_NATIVE(context)
    result = [[UNIVERSE gameView] cxx_snapShot:value];
    OOJS_END_FULL_NATIVE

    OOJS_RETURN_BOOL(result);

    OOJS_NATIVE_EXIT
}
#endif

// autoAIForRole(role : String) : String
static JSValue GlobalAutoAIForRole(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    std::optional<std::string> string;

    if (argc > 0)
        string = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
    if (!string.has_value()) {
        cxx_OOJSReportBadArguments(context, std::nullopt, "autoAIForRole", MIN(argc, 1), OOJS_ARGV, std::nullopt, "string");
        return JS_EXCEPTION;
    }

    const oo::PList autoAIMap = [ResourceManager cxx_dictionaryFromFilesNamed:"autoAImap.plist" inFolder:"Config" andMerge:YES];
    std::optional<std::string> autoAI = StringFromPList(autoAIMap.find(*string));

    OOJS_RETURN_OBJECT(oo::NSStringOrNil(autoAI));

    OOJS_NATIVE_EXIT
}

// pauseGame() : Boolean
static JSValue GlobalPauseGame(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    BOOL result = NO;
    PlayerEntity* player = PLAYER;

    if (player) {
        OOGUIScreenID guiScreen = [player guiScreen];

        if (guiScreen != GUI_SCREEN_LONG_RANGE_CHART && guiScreen != GUI_SCREEN_MISSION && guiScreen != GUI_SCREEN_REPORT && guiScreen != GUI_SCREEN_KEYBOARD_ENTRY && guiScreen != GUI_SCREEN_SAVE) {
            [UNIVERSE pauseGame];
            result = YES;
        }
    }

    OOJS_RETURN_BOOL(result);

    OOJS_NATIVE_EXIT
}

#ifdef OO_DEBUG_MONITOR_ENABLED
// quitGame() : Boolean
static JSValue GlobalQuitGame(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    OO_LOG("script.debug.quit", "{}", "Quit requested via JavaScript global.quitGame()");

    /*	Quit once the calling script has returned, so that the JavaScript
            runtime can be shut down and leak-checked with no script on the stack.
    */
    OOScheduleDeferredCall(UNIVERSE, @selector(quitGame), nil, 0.0);

    OOJS_RETURN_BOOL(YES);

    OOJS_NATIVE_EXIT
}
#endif
