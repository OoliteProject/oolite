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

#import "GuiDisplayGen.h"
#import "MyOpenGLView.h"
#import "NSFileManagerOOExtensions.h"
#import "OOCollectionExtractors.h"
#import "OOConstToJSString.h"
#import "OOConstToString.h"
#import "OOJSGuiScreenKeyDefinition.h"
#import "OOJSPlayer.h"
#import "OOStringExpander.h"
#import "OOSystemDescriptionManager.h"
#import "OOTexture.h"
#import "PlayerEntityScriptMethods.h"
#import "ResourceManager.h"

#if OOJSENGINE_MONITOR_SUPPORT

@interface OOJavaScriptEngine (OOMonitorSupportInternal)

- (void)sendMonitorLogMessage:(NSString*)message
             withMessageClass:(NSString*)messageClass
                    inContext:(JSContext*)context;

@end

#endif

static NSString* const kOOLogDebugMessage = @"script.debug.message";

static JSValue GlobalGetProperty(OOJS_GETTER_ARGS);
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
        OOJSReportBadPropertySelector(context, this, magic, sGlobalProperties, OOJS_COUNT(sGlobalProperties));
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
        OOJSReportBadPropertySelector(context, this, magic, sGlobalProperties, OOJS_COUNT(sGlobalProperties));
        return JS_EXCEPTION;
    }

    OOJSReportBadPropertyValue(context, this, magic, sGlobalProperties, OOJS_COUNT(sGlobalProperties), value);
    return JS_EXCEPTION;

    OOJS_NATIVE_EXIT
}
#endif

// *** Methods ***

// log([messageClass : String,] message : string, ...)
static JSValue GlobalLog(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    NSString* message = nil;
    NSString* messageClass = nil;

    if (EXPECT_NOT(argc < 1)) {
        OOJS_RETURN_VOID;
    }
    if (argc < 2) {
        messageClass = kOOLogDebugMessage;
        message = OOStringFromJSValue(context, OOJS_ARGV[0]);
    } else {
        messageClass = OOStringFromJSValueEvenIfNull(context, OOJS_ARGV[0]);
        if (!OOLogWillDisplayMessagesInClass(messageClass)) {
            // Do nothing (and short-circuit) if message class is filtered out.
            OOJS_RETURN_VOID;
        }

        message = [NSString concatenationOfStringsFromJavaScriptValues:OOJS_ARGV + 1 count:argc - 1 separator:@", " inContext:context];
    }

    OOJS_BEGIN_FULL_NATIVE(context)
    OOLog(messageClass, @"%@", message);

#if OOJSENGINE_MONITOR_SUPPORT
    [[OOJavaScriptEngine sharedEngine] sendMonitorLogMessage:message
                                            withMessageClass:nil
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

    NSString* string = nil;
    NSDictionary* overrides = nil;

    if (argc > 0)
        string = OOStringFromJSValue(context, OOJS_ARGV[0]);
    if (string == nil) {
        OOJSReportBadArguments(context, nil, @"expandDescription", MIN(argc, 1), OOJS_ARGV, nil, @"string");
        return JS_EXCEPTION;
    }
    if (argc > 1) {
        overrides = OOJSDictionaryFromStringTable(context, OOJS_ARGV[1]);
    }

    OOJS_BEGIN_FULL_NATIVE(context)
    string = OOExpandDescriptionString(kNilRandomSeed, string, overrides, nil, nil, kOOExpandForJavaScript | kOOExpandGoodRNG);
    OOJS_END_FULL_NATIVE

    OOJS_RETURN_OBJECT(string);

    OOJS_NATIVE_EXIT
}

static JSValue GlobalKeyBindingDescription(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    NSString* string = nil;
    PlayerEntity* player = OOPlayerForScripting();

    if (argc > 0)
        string = OOStringFromJSValue(context, OOJS_ARGV[0]);
    if (string == nil) {
        OOJSReportBadArguments(context, nil, @"keyBindingDescription", MIN(argc, 1), OOJS_ARGV, nil, @"string");
        return JS_EXCEPTION;
    }

    OOJS_BEGIN_FULL_NATIVE(context)
    string = [player keyBindingDescription2:string];
    OOJS_END_FULL_NATIVE

    OOJS_RETURN_OBJECT(string);

    OOJS_NATIVE_EXIT
}

// expandMissionText(textKey : String [, overrides : object (dictionary)]) : String
static JSValue GlobalExpandMissionText(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    NSString* string = nil;
    NSDictionary* overrides = nil;

    if (argc > 0)
        string = OOStringFromJSValue(context, OOJS_ARGV[0]);
    if (string == nil) {
        OOJSReportBadArguments(context, nil, @"expandMissionText", MIN(argc, 1), OOJS_ARGV, nil, @"string");
        return JS_EXCEPTION;
    }
    if (argc > 1) {
        overrides = OOJSDictionaryFromStringTable(context, OOJS_ARGV[1]);
    }

    string = [[UNIVERSE missiontext] oo_stringForKey:string];
    string = OOExpandDescriptionString(kNilRandomSeed, string, overrides, nil, nil, kOOExpandForJavaScript | kOOExpandBackslashN | kOOExpandGoodRNG);

    OOJS_RETURN_OBJECT(string);

    OOJS_NATIVE_EXIT
}

// displayNameForCommodity(commodityName : String) : String
static JSValue GlobalDisplayNameForCommodity(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    NSString* string = nil;

    if (argc > 0)
        string = OOStringFromJSValue(context, OOJS_ARGV[0]);
    if (string == nil) {
        OOJSReportBadArguments(context, nil, @"displayNameForCommodity", MIN(argc, 1), OOJS_ARGV, nil, @"string");
        return JS_EXCEPTION;
    }
    OOJS_RETURN_OBJECT(CommodityDisplayNameForSymbolicName(string));

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
    setRandomSeed((RNG_Seed) { Ranrot(), Ranrot(), Ranrot(), Ranrot() });

    NSString* result = OOExpand(@"%N");

    // Restore seed.
    setRandomSeed(savedSeed);

    OOJS_RETURN_OBJECT(result);

    OOJS_NATIVE_EXIT
}

// randomInhabitantsDescription() : String
static JSValue GlobalRandomInhabitantsDescription(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    NSString* string = nil;
    Random_Seed aSeed;
    int isPlural = YES;

    if (argc > 0 && (isPlural = JS_ToBool(context, OOJS_ARGV[0])) < 0) {
        JS_FreeValue(context, JS_GetException(context));
        OOJSReportBadArguments(context, nil, @"randomInhabitantsDescription", 1, OOJS_ARGV, nil, @"boolean");
        return JS_EXCEPTION;
    }

    make_pseudo_random_seed(&aSeed);
    string = [UNIVERSE getSystemInhabitants:Ranrot() % OO_SYSTEMS_PER_GALAXY plural:isPlural];
    OOJS_RETURN_OBJECT(string);

    OOJS_NATIVE_EXIT
}

static JSValue GlobalClearExtraGuiScreenKeys(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    BOOL result = NO;
    PlayerEntity* player = OOPlayerForScripting();

    if (EXPECT_NOT(argc < 2)) {
        OOJSReportBadArguments(context, nil, @"setExtraGuiScreenKeys", 0, OOJS_ARGV, nil, @"missing arguments");
        return JS_EXCEPTION;
    }

    NSString* key = OOStringFromJSValue(context, OOJS_ARGV[0]);
    if (EXPECT_NOT(key == nil || [key isEqualToString:@""])) {
        OOJSReportBadArguments(context, nil, @"clearExtraGuiScreenKeys", 1, OOJS_ARGV, nil, @"key");
        return JS_EXCEPTION;
    }

    OOGUIScreenID gui = OOGUIScreenIDFromJSValue(context, OOJS_ARGV[1]);
    if (!gui) {
        OOJSReportBadArguments(context, nil, @"clearExtraGuiScreenKeys", 0, OOJS_ARGV, nil, @"guiScreen invalid entry");
        return JS_EXCEPTION;
    }

    [player clearExtraGuiScreenKeys:gui key:key];

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
    NSString* key = nil;
    OOGUIScreenID gui;
    NSDictionary* keydefs = NULL;
    JSValue params = JS_UNDEFINED;
    PlayerEntity* player = OOPlayerForScripting();
    // The SpiderMonkey version always described two arguments from argv[1] on; don't read past argv.
    int defArgc = MIN(argc - 1, 2);

    if (EXPECT_NOT(argc < 1)) {
        OOJSReportBadArguments(context, nil, @"setExtraGuiScreenKeys", 0, OOJS_ARGV, nil, @"key, definition");
        return JS_EXCEPTION;
    }
    key = OOStringFromJSValue(context, OOJS_ARGV[0]);

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
        OOJSReportBadArguments(context, @"global", @"setExtraGuiScreenKeys", defArgc, &OOJS_ARGV[1], nil, @"key, definition: definition is not a valid dictionary.");
        return JS_EXCEPTION;
    }

    value = GetParam(context, params, "guiScreen");
    if (JS_IsUndefined(value)) {
        JS_FreeValue(context, params);
        OOJSReportBadArguments(context, @"global", @"setExtraGuiScreenKeys", defArgc, &OOJS_ARGV[1], nil, @"key, definition: must have a 'guiScreen' property.");
        return JS_EXCEPTION;
    }

    gui = OOGUIScreenIDFromJSValue(context, value);
    JS_FreeValue(context, value);
    // gui will be 0 for invalid screen id's as well as GUI_SCREEN_MAIN
    if (gui == 0 || gui == GUI_SCREEN_LOAD || gui == GUI_SCREEN_SAVE || gui == GUI_SCREEN_STICKMAPPER || gui == GUI_SCREEN_OXZMANAGER || gui == GUI_SCREEN_NEWGAME || gui == GUI_SCREEN_SAVE_OVERWRITE || gui == GUI_SCREEN_KEYBOARD || gui == GUI_SCREEN_STICKPROFILE || gui == GUI_SCREEN_KEYBOARD_CONFIRMCLEAR || gui == GUI_SCREEN_KEYBOARD_CONFIG || gui == GUI_SCREEN_KEYBOARD_ENTRY || gui == GUI_SCREEN_KEYBOARD_LAYOUT) {
        JS_FreeValue(context, params);
        OOJSReportBadArguments(context, @"global", @"setExtraGuiScreenKeys", defArgc, &OOJS_ARGV[1], nil, @"key, definition: 'guiScreen' property must be a permitted and valid GUI_SCREEN idenfifier.");
        return JS_EXCEPTION;
    }

    value = GetParam(context, params, "registerKeys");
    if (JS_IsUndefined(value)) {
        JS_FreeValue(context, params);
        OOJSReportBadArguments(context, @"global", @"setExtraGuiScreenKeys", defArgc, &OOJS_ARGV[1], nil, @"key, definition: must have a 'registerKeys' property.");
        return JS_EXCEPTION;
    }
    if (!JS_IsNull(value)) {
        if (JS_IsObject(value)) {
            keydefs = OOJSNativeObjectFromJSObject(context, value);
        } else {
            JS_FreeValue(context, value);
            JS_FreeValue(context, params);
            OOJSReportBadArguments(context, @"global", @"setExtraGuiScreenKeys", defArgc, &OOJS_ARGV[1], nil, @"key, definition: registerKeys is not a valid dictionary.");
            return JS_EXCEPTION;
        }
    }
    JS_FreeValue(context, value);

    callback = GetParam(context, params, "callback");
    if (JS_IsUndefined(callback)) {
        JS_FreeValue(context, params);
        OOJSReportBadArguments(context, @"global", @"setExtraGuiScreenKeys", defArgc, &OOJS_ARGV[1], NULL, @"key, definition; must have a 'callback' property.");
        return JS_EXCEPTION;
    }
    if (!OOJSValueIsFunction(context, callback)) {
        JS_FreeValue(context, callback);
        JS_FreeValue(context, params);
        OOJSReportBadArguments(context, @"global", @"setExtraGuiScreenKeys", defArgc, &OOJS_ARGV[1], NULL, @"key, definition; 'callback' property must be a function.");
        return JS_EXCEPTION;
    }

    OOJSGuiScreenKeyDefinition* definition = [[OOJSGuiScreenKeyDefinition alloc] init];
    [definition setName:key];
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
        OOJSReportWarning(context, @"Usage error: %@() called with no arguments. Treating as %@(null). This call may fail in a future version of Oolite.", @"setScreenBackground", @"setScreenBackground");
    } else if (EXPECT_NOT(JS_IsUndefined(value))) {
        OOJSReportBadArguments(context, nil, @"setScreenBackground", 1, &value, nil, @"GUI texture descriptor");
        return JS_EXCEPTION;
    }

    if ([UNIVERSE viewDirection] == VIEW_GUI_DISPLAY) {
        GuiDisplayGen* gui = [UNIVERSE gui];
        NSDictionary* descriptor = [gui textureDescriptorFromJSValue:value inContext:context callerDescription:@"setScreenBackground()"];

        result = [gui setBackgroundTextureDescriptor:descriptor];

        // add some permanence to the override if we're in the equip ship screen
        if (result && [PLAYER guiScreen] == GUI_SCREEN_EQUIP_SHIP)
            [PLAYER setEquipScreenBackgroundDescriptor:descriptor];
    }

    OOJS_RETURN_BOOL(result);

    OOJS_NATIVE_EXIT
}

static JSValue GlobalGetScreenBackgroundForKey(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    if (EXPECT_NOT(argc == 0)) {
        OOJSReportBadArguments(context, nil, @"getScreenBackgroundDefault", 0, OOJS_ARGV, nil, @"missing arguments");
        return JS_EXCEPTION;
    }
    NSString* key = OOStringFromJSValue(context, OOJS_ARGV[0]);
    if (EXPECT_NOT(key == nil || [key isEqualToString:@""])) {
        OOJSReportBadArguments(context, nil, @"getScreenBackgroundDefault", 0, OOJS_ARGV, nil, @"key");
        return JS_EXCEPTION;
    }
    NSDictionary* descriptor = [UNIVERSE screenTextureDescriptorForKey:key];

    OOJS_RETURN_OBJECT(descriptor);

    OOJS_NATIVE_EXIT
}

// setScreenBackgroundDefault (key : NSString, descriptor : guiTextureDescriptor) : boolean
static JSValue GlobalSetScreenBackgroundForKey(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    BOOL result = NO;

    if (EXPECT_NOT(argc < 2)) {
        OOJSReportBadArguments(context, nil, @"setScreenBackgroundDefault", 0, OOJS_ARGV, nil, @"missing arguments");
        return JS_EXCEPTION;
    }

    NSString* key = OOStringFromJSValue(context, OOJS_ARGV[0]);
    JSValueConst value = OOJS_ARGV[1];
    if (EXPECT_NOT(key == nil || [key isEqualToString:@""])) {
        OOJSReportBadArguments(context, nil, @"setScreenBackgroundDefault", 0, OOJS_ARGV, nil, @"key");
        return JS_EXCEPTION;
    }

    GuiDisplayGen* gui = [UNIVERSE gui];
    NSDictionary* descriptor = [gui textureDescriptorFromJSValue:value inContext:context callerDescription:@"setScreenBackgroundDefault()"];

    [UNIVERSE setScreenTextureDescriptorForKey:key descriptor:descriptor];
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
        OOJSReportWarning(context, @"Usage error: %@() called with no arguments. Treating as %@(null). This call may fail in a future version of Oolite.", @"setScreenOverlay", @"setScreenOverlay");
    } else if (EXPECT_NOT(JS_IsUndefined(value))) {
        OOJSReportBadArguments(context, nil, @"setScreenOverlay", 1, &value, nil, @"GUI texture descriptor");
        return JS_EXCEPTION;
    }

    if ([UNIVERSE viewDirection] == VIEW_GUI_DISPLAY) {
        GuiDisplayGen* gui = [UNIVERSE gui];
        NSDictionary* descriptor = [gui textureDescriptorFromJSValue:value inContext:context callerDescription:@"setScreenOverlay()"];

        result = [gui setForegroundTextureDescriptor:descriptor];
    }

    OOJS_RETURN_BOOL(result);

    OOJS_NATIVE_EXIT
}

static JSValue GlobalGetGuiColorSettingForKey(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    if (EXPECT_NOT(argc == 0)) {
        OOJSReportBadArguments(context, nil, @"getGuiColorForKey", 0, OOJS_ARGV, nil, @"missing arguments");
        return JS_EXCEPTION;
    }
    NSString* key = OOStringFromJSValue(context, OOJS_ARGV[0]);
    if (EXPECT_NOT(key == nil || [key isEqualToString:@""])) {
        OOJSReportBadArguments(context, nil, @"getGuiColorForKey", 0, OOJS_ARGV, nil, @"key");
        return JS_EXCEPTION;
    }
    if ([key rangeOfString:@"color"].location == NSNotFound) {
        OOJSReportBadArguments(context, nil, @"getGuiColorForKey", 0, OOJS_ARGV, nil, @"valid color key setting");
        return JS_EXCEPTION;
    }

    GuiDisplayGen* gui = [UNIVERSE gui];
    OOColor* col = [gui colorFromSetting:key defaultValue:nil];

    OOJS_RETURN_OBJECT([col normalizedArray]);

    OOJS_NATIVE_EXIT
}

// setGuiColorForKey(descriptor : OOColor) : boolean
static JSValue GlobalSetGuiColorSettingForKey(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    BOOL result = NO;
    OOColor* col = nil;

    if (EXPECT_NOT(argc != 2)) {
        OOJSReportBadArguments(context, nil, @"setGuiColorForKey", 0, OOJS_ARGV, nil, @"missing arguments");
        return JS_EXCEPTION;
    }

    NSString* key = OOStringFromJSValue(context, OOJS_ARGV[0]);
    JSValueConst value = OOJS_ARGV[1];
    if (EXPECT_NOT(key == nil || [key isEqualToString:@""])) {
        OOJSReportBadArguments(context, nil, @"setGuiColorForKey", 0, OOJS_ARGV, nil, @"key");
        return JS_EXCEPTION;
    }
    if ([key rangeOfString:@"color"].location == NSNotFound) {
        OOJSReportBadArguments(context, nil, @"setGuiColorForKey", 0, OOJS_ARGV, nil, @"valid color key setting");
        return JS_EXCEPTION;
    }

    if (!JS_IsNull(value)) {
        col = [OOColor colorWithDescription:OOJSNativeObjectFromJSValue(context, value)];
        if (col == nil) {
            OOJSReportBadArguments(context, nil, @"setGuiColorForKey", 1, OOJS_ARGV, nil, @"color descriptor");
            return JS_EXCEPTION;
        }
    }

    GuiDisplayGen* gui = [UNIVERSE gui];
    [gui setGuiColorSettingFromKey:key color:col];
    result = YES;

    OOJS_RETURN_BOOL(result);

    OOJS_NATIVE_EXIT
}

#ifdef OO_DEBUG_MONITOR_ENABLED
// takeSnapShot([name : alphanumeric String]) : Boolean
static JSValue GlobalTakeSnapShot(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    NSString* value = nil;
    NSMutableCharacterSet* allowedChars = (NSMutableCharacterSet*)[NSMutableCharacterSet alphanumericCharacterSet];
    BOOL result = NO;

    [allowedChars addCharactersInString:@"_-"];

    if (argc > 0) {
        value = OOStringFromJSValue(context, OOJS_ARGV[0]);
        if (EXPECT_NOT(value == nil || [value rangeOfCharacterFromSet:[allowedChars invertedSet]].location != NSNotFound)) {
            OOJSReportBadArguments(context, nil, @"takeSnapShot", argc, OOJS_ARGV, nil, @"alphanumeric string");
            return JS_EXCEPTION;
        }
    }

    NSString* playerFileDirectory = [[NSFileManager defaultManager] defaultCommanderPath];
    NSDictionary* attr = [[NSFileManager defaultManager] oo_fileSystemAttributesAtPath:playerFileDirectory];

    if (attr != nil) {
        double freeSpace = [attr oo_doubleForKey:NSFileSystemFreeSize];
        if (freeSpace < 1073741824) // less than 1 GB free on disk?
        {
            OOJSReportWarning(context, @"takeSnapShot: function disabled when free disk space is less than 1GB.");
            OOJS_RETURN_BOOL(NO);
        }
    }

    OOJS_BEGIN_FULL_NATIVE(context)
    result = [[UNIVERSE gameView] snapShot:value];
    OOJS_END_FULL_NATIVE

    OOJS_RETURN_BOOL(result);

    OOJS_NATIVE_EXIT
}
#endif

// autoAIForRole(role : String) : String
static JSValue GlobalAutoAIForRole(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    NSString* string = nil;

    if (argc > 0)
        string = OOStringFromJSValue(context, OOJS_ARGV[0]);
    if (string == nil) {
        OOJSReportBadArguments(context, nil, @"autoAIForRole", MIN(argc, 1), OOJS_ARGV, nil, @"string");
        return JS_EXCEPTION;
    }

    NSDictionary* autoAIMap = [ResourceManager dictionaryFromFilesNamed:@"autoAImap.plist" inFolder:@"Config" andMerge:YES];
    NSString* autoAI = [autoAIMap oo_stringForKey:string];

    OOJS_RETURN_OBJECT(autoAI);

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

    OOLog(@"script.debug.quit", @"%@", @"Quit requested via JavaScript global.quitGame()");

    /*	Quit once the calling script has returned, so that the JavaScript
            runtime can be shut down and leak-checked with no script on the stack.
    */
    [UNIVERSE performSelector:@selector(quitGame) withObject:nil afterDelay:0.0];

    OOJS_RETURN_BOOL(YES);

    OOJS_NATIVE_EXIT
}
#endif
