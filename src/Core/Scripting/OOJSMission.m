/*

OOJSMission.m


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

#import "OOJSMission.h"
#import "OOConstToJSString.h"
#import "OOJSScript.h"
#import "OOJSVector.h"
#import "OOJavaScriptEngine.h"

#import "GuiDisplayGen.h"
#import "OOCollectionExtractors.h"
#import "OODebugStandards.h"
#import "OOJSPlayer.h"
#import "OOMusicController.h"
#import "OOStringExpander.h"
#import "PlayerEntityScriptMethods.h"

static JSValue MissionGetProperty(OOJS_GETTER_ARGS);
static JSValue MissionSetProperty(OOJS_SETTER_ARGS);

static JSValue MissionMarkSystem(OOJS_NATIVE_ARGS);
static JSValue MissionUnmarkSystem(OOJS_NATIVE_ARGS);
static JSValue MissionAddMessageText(OOJS_NATIVE_ARGS);
static JSValue MissionSetInstructions(OOJS_NATIVE_ARGS);
static JSValue MissionSetInstructionsKey(OOJS_NATIVE_ARGS);
static JSValue MissionRunScreen(OOJS_NATIVE_ARGS);
static JSValue MissionRunShipLibrary(OOJS_NATIVE_ARGS);

static JSValue MissionSetInstructionsInternal(JSContext* context, int argc, JSValueConst* argv, BOOL isKey);

/*	Mission screen callback variables.
        sCallbackFunction and sCallbackThis own their values (they were GC roots
        with SpiderMonkey). They are zero-filled until first set, so test them
        with JS_IsObject()/JS_IsFunction(). They are freed when consumed and when
        the engine is reset.
*/
static JSValue sCallbackFunction;
static JSValue sCallbackThis;
static OOJSScript* sCallbackScript = nil;

// Borrowed: owned by the global object's read-only, permanent "mission" property. Reset by InitOOJSMission().
static JSValue sMissionObject;

static JSClassID sMissionClassID;
static JSClassDef sMissionClass = {
    .class_name = "Mission",
};

enum {
    kMission_markedSystems,
    kMission_screenID,
    kMission_exitScreen
};

static const JSCFunctionListEntry sMissionProperties[] = {
    // JS name					Getter				Setter				ID
    OOJS_PROPERTY_RO("markedSystems", MissionGetProperty, kMission_markedSystems),
    OOJS_PROPERTY_RO("screenID", MissionGetProperty, kMission_screenID),
    OOJS_PROPERTY_RW("exitScreen", MissionGetProperty, MissionSetProperty, kMission_exitScreen),
};

static const JSCFunctionListEntry sMissionMethods[] = {
    // JS name					Function					min args
    JS_CFUNC_DEF("addMessageText", 1, MissionAddMessageText),
    JS_CFUNC_DEF("markSystem", 1, MissionMarkSystem),
    JS_CFUNC_DEF("runScreen", 1, MissionRunScreen), // the callback function is optional!
    JS_CFUNC_DEF("setInstructions", 1, MissionSetInstructions),
    JS_CFUNC_DEF("setInstructionsKey", 1, MissionSetInstructionsKey),
    JS_CFUNC_DEF("unmarkSystem", 1, MissionUnmarkSystem),
    JS_CFUNC_DEF("runShipLibrary", 0, MissionRunShipLibrary),
};

// Replace an owned static value, freeing the old one.
static void SetOwnedValue(JSContext* context, JSValue* slot, JSValueConst value)
{
    JSValue old = *slot;
    *slot = JS_DupValue(context, value);
    JS_FreeValue(context, old); // Zero-filled (integer) values need no freeing, and JS_FreeValue() ignores them.
}

static void ClearPendingCallback(void)
{
    JSContext* context = OOJSAcquireContext();
    SetOwnedValue(context, &sCallbackFunction, JS_NULL);
    SetOwnedValue(context, &sCallbackThis, JS_NULL);
    DESTROY(sCallbackScript);
    OOJSRelinquishContext(context);
}

// Releases the pending callback before the context is destroyed.
@interface OOJSMissionResetObserver : NSObject
@end

@implementation OOJSMissionResetObserver

+ (void)engineWillReset:(NSNotification*)notification
{
    ClearPendingCallback();
}

@end

void InitOOJSMission(JSContext* context, JSValueConst global)
{
    static BOOL observing = NO;
    if (!observing) {
        [[NSNotificationCenter defaultCenter] addObserver:[OOJSMissionResetObserver class]
                                                 selector:@selector(engineWillReset:)
                                                     name:kOOJavaScriptEngineWillResetNotification
                                                   object:nil];
        observing = YES;
    }

    sCallbackFunction = JS_NULL;
    sCallbackThis = JS_NULL;

    OOJSRegisterClass(&sMissionClassID, &sMissionClass);
    JSValueConst missionPrototype = OOJSInitClass(context, global, sMissionClassID, JS_UNDEFINED, OOJSUnconstructableConstruct, 0,
        sMissionProperties, OOJS_COUNT(sMissionProperties), sMissionMethods, OOJS_COUNT(sMissionMethods), NULL, 0);
    JSValue missionObject = JS_NewObjectProtoClass(context, missionPrototype, sMissionClassID);
    sMissionObject = missionObject;
    JS_DefinePropertyValueStr(context, global, "mission", missionObject, OOJS_PROP_READONLY);
}

void MissionRunCallback()
{
    // don't do anything if we don't have a function.
    if (!JS_IsObject(sCallbackFunction))
        return;

    JSValue argval = JS_UNDEFINED;
    JSValue argval2 = JS_UNDEFINED;
    JSValue rval = JS_UNDEFINED;
    PlayerEntity* player = OOPlayerForScripting();
    OOJavaScriptEngine* engine = [OOJavaScriptEngine sharedEngine];
    JSContext* context = OOJSAcquireContext();

    /*	Take local (owned) copies of sCallbackFunction and sCallbackThis, then
            clear the statics. This must be done in advance since the callback
            might call runScreen() and clobber the statics.
    */
    JSValue cbFunction = sCallbackFunction;
    JSValue cbThis = JS_NULL;
    OOJSScript* cbScript = sCallbackScript;

    // As with JS_ValueToObject(), null and undefined give no object (and so the global object as this).
    if (JS_IsObject(sCallbackThis)) {
        cbThis = JS_DupValue(context, sCallbackThis);
    } else if (!JS_IsNull(sCallbackThis) && !JS_IsUndefined(sCallbackThis)) {
        cbThis = JS_ToObject(context, sCallbackThis);
        if (JS_IsException(cbThis)) {
            JS_FreeValue(context, JS_GetException(context));
            cbThis = JS_NULL;
        }
    }
    if (!JS_IsObject(cbThis)) {
        cbThis = JS_GetGlobalObject(context);
    }

    sCallbackScript = nil;
    sCallbackFunction = JS_NULL; // Ownership moved to cbFunction.
    SetOwnedValue(context, &sCallbackThis, JS_NULL);

    JSValue args[2];
    argval = OOJSValueFromNativeObject(context, [player missionChoice_string]);
    argval2 = OOJSValueFromNativeObject(context, [player missionKeyPress_string]);
    args[0] = argval;
    args[1] = argval2;

    // now reset the mission choice silently, before calling the callback script.
    [player setMissionChoice:nil keyPress:@"" withEvent:NO];

    // Call the callback.
    @try {
        [OOJSScript pushScript:cbScript];
        [engine callJSFunction:cbFunction
                     forObject:cbThis
                          argc:2
                          argv:args
                        result:&rval];
    }
    @catch (NSException* exception) {
        // Squash any exception, allow cleanup to happen and so forth.
        OOLog(kOOLogException, @"Ignoring exception %@:%@ during handling of mission screen completion callback.", [exception name], [exception reason]);
    }
    [OOJSScript popScript:cbScript];

    // Manage that memory.
    [cbScript release];
    JS_FreeValue(context, rval);
    JS_FreeValue(context, argval);
    JS_FreeValue(context, argval2);
    JS_FreeValue(context, cbFunction);
    JS_FreeValue(context, cbThis);

    OOJSRelinquishContext(context);
}

static JSValue MissionGetProperty(OOJS_GETTER_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    id result = nil;
    PlayerEntity* player = OOPlayerForScripting();

    switch (magic) {
    case kMission_markedSystems:
        result = [player getMissionDestinations];
        if (result == nil)
            result = [NSDictionary dictionary];
        result = [result allValues];
        break;

    case kMission_screenID:
        result = [player missionScreenID];
        break;

    case kMission_exitScreen:
        return OOJSValueFromGUIScreenID(context, [player missionExitScreen]);

    default:
        OOJSReportBadPropertySelector(context, this, magic, sMissionProperties, OOJS_COUNT(sMissionProperties));
        return JS_EXCEPTION;
    }

    return OOJSValueFromNativeObject(context, result);

    OOJS_NATIVE_EXIT
}

static JSValue MissionSetProperty(OOJS_SETTER_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    OOGUIScreenID exitScreen;
    PlayerEntity* player = OOPlayerForScripting();

    switch (magic) {
    case kMission_exitScreen:
        exitScreen = OOGUIScreenIDFromJSValue(context, value);
        [player setMissionExitScreen:exitScreen];
        return JS_UNDEFINED;

    default:
        OOJSReportBadPropertySelector(context, this, magic, sMissionProperties, OOJS_COUNT(sMissionProperties));
        return JS_EXCEPTION;
    }

    OOJSReportBadPropertyValue(context, this, magic, sMissionProperties, OOJS_COUNT(sMissionProperties), value);
    return JS_EXCEPTION;

    OOJS_NATIVE_EXIT
}

// *** Methods ***

// JS_ValueToInt32() without leaving an exception pending on failure (SpiderMonkey callers cleared it).
static BOOL ValueToInt32NoError(JSContext* context, JSValueConst value, int32_t* outValue)
{
    if (OOJSValueToInt32(context, value, outValue))
        return YES;
    if (JS_HasException(context))
        JS_FreeValue(context, JS_GetException(context)); // or JS_ValueToInt32 exception crashes JS engine
    return NO;
}

// markSystem(integer+)
static JSValue MissionMarkSystem(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    PlayerEntity* player = OOPlayerForScripting();
    int i;
    int32_t dest;

    // two pass. Once to validate, once to apply if they validate
    for (i = 0; i < argc; i++) {
        if (!ValueToInt32NoError(context, OOJS_ARGV[i], &dest)) {
            // (JSVAL_IS_OBJECT() was also true for null, which converts to 0 and so never gets here.)
            if (!JS_IsObject(OOJS_ARGV[i])) {
                OOJSReportBadArguments(context, @"Mission", @"markSystem", MIN(argc, 1), OOJS_ARGV, nil, @"numbers or objects");
                return JS_EXCEPTION;
            }
        }
    }

    for (i = 0; i < argc; i++) {
        if (ValueToInt32NoError(context, OOJS_ARGV[i], &dest)) {
            OOStandardsDeprecated(@"Use of numbers for mission.markSystem is deprecated");
            if (!OOEnforceStandards()) {
                [player addMissionDestinationMarker:[player defaultMarker:dest]];
            }
        } else // must be object, from above
        {
            NSDictionary* marker = OOJSNativeObjectFromJSObject(context, OOJS_ARGV[i]);
            OOSystemID system = [marker oo_intForKey:@"system" defaultValue:-1];
            if (system >= 0) {
                [player addMissionDestinationMarker:marker];
            }
        }
    }
    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}

// unmarkSystem(integer+)
static JSValue MissionUnmarkSystem(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    PlayerEntity* player = OOPlayerForScripting();
    int i;
    int32_t dest;

    // two pass. Once to validate, once to apply if they validate
    for (i = 0; i < argc; i++) {
        if (!ValueToInt32NoError(context, OOJS_ARGV[i], &dest)) {
            if (!JS_IsObject(OOJS_ARGV[i])) {
                OOJSReportBadArguments(context, @"Mission", @"unmarkSystem", MIN(argc, 1), OOJS_ARGV, nil, @"numbers or objects");
                return JS_EXCEPTION;
            }
        }
    }

    BOOL result = YES;
    for (i = 0; i < argc; i++) {
        if (ValueToInt32NoError(context, OOJS_ARGV[i], &dest)) {
            OOStandardsDeprecated(@"Use of numbers for mission.unmarkSystem is deprecated");
            if (!OOEnforceStandards()) {
                if (![player removeMissionDestinationMarker:[player defaultMarker:dest]]) {
                    result = NO;
                }
            }
        } else // must be object, from above
        {
            NSDictionary* marker = OOJSNativeObjectFromJSObject(context, OOJS_ARGV[i]);
            OOSystemID system = [marker oo_intForKey:@"system" defaultValue:-1];
            if (system >= 0) {
                if (![player removeMissionDestinationMarker:marker]) {
                    result = NO;
                }
            }
        }
    }

    OOJS_RETURN_BOOL(result);

    OOJS_NATIVE_EXIT
}

// addMessageText(text : String)
static JSValue MissionAddMessageText(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    PlayerEntity* player = OOPlayerForScripting();
    NSString* text = nil;

    if (EXPECT_NOT(argc == 0)) {
        OOJS_RETURN_VOID;
    }

    // Found "FIXME: warning if no mission screen running.",,,
    // However: used routinely by the Constrictor mission in F7, without mission screens.
    text = OOStringFromJSValue(context, OOJS_ARGV[0]);
    [player addLiteralMissionText:text];

    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}

// setInstructionsKey(instructionsKey: String [, missionKey : String])
static JSValue MissionSetInstructionsKey(OOJS_NATIVE_ARGS)
{
    return MissionSetInstructionsInternal(context, argc, OOJS_ARGV, YES);
}

// setInstructions(instructions: String [, missionKey : String])
static JSValue MissionSetInstructions(OOJS_NATIVE_ARGS)
{
    return MissionSetInstructionsInternal(context, argc, OOJS_ARGV, NO);
}

static JSValue MissionSetInstructionsInternal(JSContext* context, int argc, JSValueConst* argv, BOOL isKey)
{
    OOJS_NATIVE_ENTER(context)

    PlayerEntity* player = OOPlayerForScripting();
    NSString* text = nil;
    NSArray* texts = nil;
    NSString* missionKey = nil;

    if (EXPECT_NOT(argc == 0)) {
        OOJSReportWarning(context, @"Usage error: mission.%@() called with no arguments. Treating as Mission.%@(null). This call may fail in a future version of Oolite.", isKey ? @"setInstructionsKey" : @"setInstructions", isKey ? @"setInstructionsKey" : @"setInstructions");
    } else if (EXPECT_NOT(JS_IsUndefined(argv[0]))) {
        OOJSReportBadArguments(context, @"Mission", isKey ? @"setInstructionsKey" : @"setInstructions", 1, argv, NULL, @"string or null");
        return JS_EXCEPTION;
    } else if (!JS_IsNull(argv[0]) && JS_IsObject(argv[0])) {
        texts = OOJSNativeObjectFromJSValue(context, argv[0]);
    } else {
        text = OOStringFromJSValue(context, argv[0]);
    }

    if (argc > 1) {
        missionKey = OOStringFromJSValueEvenIfNull(context, argv[1]);
    } else {
        missionKey = [[OOJSScript currentlyRunningScript] name];
    }

    if (text != nil) {
        if (isKey) {
            [player setMissionDescription:text forMission:missionKey];
        } else {
            [player setMissionInstructions:text forMission:missionKey];
        }
    } else if (texts != nil && !isKey) {
        [player setMissionInstructionsList:texts forMission:missionKey];
    } else {
        [player clearMissionDescriptionForMission:missionKey];
    }

    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}

/*	Get a property of the runScreen() parameter object. Returns an owned value.
        If a getter throws, the exception is reported and cleared and the
        property is treated as undefined. (SpiderMonkey's JS_GetProperty()
        returned false, which the code below treats as a missing property; a
        QuickJS native must not return normally with an exception pending.)
*/
static JSValue GetParameter(JSContext* context, JSValueConst object, const char* key)
{
    JSValue value = JS_GetPropertyStr(context, object, key);
    if (JS_IsException(value)) {
        OOJSReportPendingException(context);
        return JS_UNDEFINED;
    }
    return value;
}

static NSDictionary* GetParameterDictionary(JSContext* context, JSValueConst object, const char* key)
{
    NSDictionary* result = nil;
    JSValue value = GetParameter(context, object, key);
    if (JS_IsObject(value)) {
        result = OOJSNativeObjectFromJSObject(context, value);
    }
    JS_FreeValue(context, value);
    return result;
}

static NSString* GetParameterString(JSContext* context, JSValueConst object, const char* key)
{
    JSValue value = GetParameter(context, object, key);
    NSString* result = OOStringFromJSValue(context, value);
    JS_FreeValue(context, value);
    return result;
}

static NSDictionary* GetParameterImageDescriptor(JSContext* context, JSValueConst object, const char* key)
{
    JSValue value = JS_GetPropertyStr(context, object, key);
    if (JS_IsException(value)) {
        OOJSReportPendingException(context);
        return nil;
    }
    NSDictionary* result = [[UNIVERSE gui] textureDescriptorFromJSValue:value inContext:context callerDescription:@"mission.runScreen()"];
    JS_FreeValue(context, value);
    return result;
}

// Get a boolean parameter; *outValue is left unchanged if the parameter is undefined.
static void GetParameterBool(JSContext* context, JSValueConst object, const char* key, BOOL* outValue)
{
    JSValue value = GetParameter(context, object, key);
    if (!JS_IsUndefined(value)) {
        int b = JS_ToBool(context, value);
        if (b >= 0)
            *outValue = b;
        else
            JS_FreeValue(context, JS_GetException(context));
    }
    JS_FreeValue(context, value);
}

// runScreen(params: dict, callBack:function) - if the callback function is null, emulate the old style runMissionScreen
static JSValue MissionRunScreen(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    PlayerEntity* player = OOPlayerForScripting();
    JSValueConst function = JS_NULL;
    JSValue value = JS_UNDEFINED;
    JSValue params = JS_UNDEFINED;

    // No mission screens during intro.
    if ([player status] == STATUS_START_GAME) {
        // (though no JS should be loaded at this stage, so this
        // check may be obsolete - CIM)
        OOJS_RETURN_BOOL(NO);
    }

    // Validate arguments.
    // (SpiderMonkey's JS_ValueToObject() accepted null and undefined, yielding no object, and then crashed; treat them as invalid.)
    if (argc >= 1 && !JS_IsNull(OOJS_ARGV[0]) && !JS_IsUndefined(OOJS_ARGV[0])) {
        params = JS_ToObject(context, OOJS_ARGV[0]);
        if (JS_IsException(params)) {
            JS_FreeValue(context, JS_GetException(context));
            params = JS_UNDEFINED;
        }
    }
    if (!JS_IsObject(params)) {
        OOJSReportBadArguments(context, @"mission", @"runScreen", MIN(argc, 1), &OOJS_ARGV[0], nil, @"parameter object");
        return JS_EXCEPTION;
    }

    if (argc > 1)
        function = OOJS_ARGV[1];
    if (!JS_IsNull(function) && !OOJSValueIsFunction(context, function)) {
        JS_FreeValue(context, params);
        OOJSReportBadArguments(context, @"mission", @"runScreen", 1, &OOJS_ARGV[1], nil, @"function");
        return JS_EXCEPTION;
    }

    // Not OOJS_BEGIN_FULL_NATIVE() - we use JSAPI while paused.
    OOJSPauseTimeLimiter();

    if (!JS_IsNull(function)) {

        /* CIM 30/12/12: This following line causes problems in certain
         * cases, but has to be kept for backward
         * compatibility. Documenting the third argument of
         * mission.runScreen will at least help people get around it in
         * multi-world-script mission screens. (Though, since no-one has
         * complained yet, perhaps I'm the only one who uses them?) */

        [sCallbackScript release]; // (Leaked by the SpiderMonkey version if runScreen() was called twice.)
        sCallbackScript = [[[OOJSScript currentlyRunningScript] weakRefUnderlyingObject] retain];
        if (argc > 2) {
            SetOwnedValue(context, &sCallbackThis, OOJS_ARGV[2]);
        } else {
            JSValue scriptValue = OOJSValueFromNativeObject(context, sCallbackScript);
            SetOwnedValue(context, &sCallbackThis, scriptValue);
            JS_FreeValue(context, scriptValue);
        }
    }

    // Apply settings.
    value = GetParameter(context, params, "title");
    if (!JS_IsUndefined(value)) {
        [player setMissionTitle:OOStringFromJSValue(context, value)];
    } else {
        NSString* titleKey = GetParameterString(context, params, "titleKey");
        if (titleKey != nil) {
            NSString* message = [[UNIVERSE missiontext] oo_stringForKey:titleKey];
            if (message != nil) {
                [player setMissionTitle:OOExpand(message)];
            } else {
                OOJSReportWarning(context, @"Mission.runScreen: titleKey '%@' has no entry in missiontext.plist.", titleKey);
            }
        }
    }
    JS_FreeValue(context, value);

    [[OOMusicController sharedController] setMissionMusic:GetParameterString(context, params, "music")];
    [player setMissionOverlayDescriptor:GetParameterImageDescriptor(context, params, "overlay")];
    [player setMissionBackgroundDescriptor:GetParameterImageDescriptor(context, params, "background")];
    [player setMissionBackgroundSpecial:GetParameterString(context, params, "backgroundSpecial")];

    value = GetParameter(context, params, "customChartZoom");
    if (!JS_IsUndefined(value)) {
        double zoom;
        if (JS_ToFloat64(context, &zoom, value) == 0) {
            if (zoom >= 1 && zoom <= CHART_MAX_ZOOM) {
                [player setCustomChartZoom:zoom];
            } else {
                OOJSReportWarning(context, @"Mission.runScreen: invalid customChartZoom value specified.");
                [player setCustomChartZoom:1];
            }
        } else {
            JS_FreeValue(context, JS_GetException(context));
        }
    }
    JS_FreeValue(context, value);

    value = GetParameter(context, params, "customChartCentre");
    if (!JS_IsUndefined(value)) {
        Vector vValue;
        if (JSValueToVector(context, value, &vValue)) {
            NSPoint coords = { vValue.x, vValue.y };
            [player setCustomChartCentre:coords];
        } else {
            [player setCustomChartCentre:[player galaxy_coordinates]];
            OOJSReportWarning(context, @"Mission.runScreen: invalid value for customChartCentre. Must be valid vector. Defaulting to current location.");
        }
    }
    JS_FreeValue(context, value);

    value = GetParameter(context, params, "customChartCentreInLY");
    if (!JS_IsUndefined(value)) {
        Vector vValue;
        if (JSValueToVector(context, value, &vValue)) {
            NSPoint coords = OOInternalCoordinatesFromGalactic(vValue);
            [player setCustomChartCentre:coords];
        } else {
            [player setCustomChartCentre:[player galaxy_coordinates]];
            OOJSReportWarning(context, @"Mission.runScreen: invalid value for customChartCentreInLY. Must be valid vector. Defaulting to current location.");
        }
    }
    JS_FreeValue(context, value);

    [UNIVERSE removeDemoShips]; // remove any demoship or miniature planet that may be remaining from previous screens

    ShipEntity* demoShip = nil;
    value = GetParameter(context, params, "model");
    if (!JS_IsUndefined(value)) {
        if ([player status] == STATUS_IN_FLIGHT && JS_IsString(value)) {
            OOJSReportWarning(context, @"Mission.runScreen: model cannot be displayed while in flight.");
        } else {
            NSString* role = OOStringFromJSValue(context, value);

            BOOL spinning = YES;
            GetParameterBool(context, params, "spinModel", &spinning);

            //	[player showShipModel:OOStringFromJSValue(context, value)];
            demoShip = [UNIVERSE makeDemoShipWithRole:role spinning:spinning];
        }
    }
    JS_FreeValue(context, value);

    if (demoShip != nil) {
        value = GetParameter(context, params, "modelPersonality");
        if (!JS_IsUndefined(value)) {
            int32_t personality = 0;
            if (!OOJSValueToInt32(context, value, &personality) && JS_HasException(context)) {
                JS_FreeValue(context, JS_GetException(context));
            }
            [demoShip setEntityPersonalityInt:personality];
        }
        JS_FreeValue(context, value);

        JSValue demoShipVal = [demoShip oo_jsValueInContext:context];
        if (JS_SetPropertyStr(context, sMissionObject, "displayModel", demoShipVal) < 0) {
            OOJSReportPendingException(context);
        }
    } else {
        if (JS_DeleteProperty(context, sMissionObject, OOJSID("displayModel"), 0) < 0) {
            OOJSReportPendingException(context);
        }
    }

    BOOL allowInterrupt = NO;
    // force the allowInterrupt to be YES while in flight
    if ([player status] == STATUS_IN_FLIGHT) {
        allowInterrupt = YES;
    } else {
        GetParameterBool(context, params, "allowInterrupt", &allowInterrupt);
    }

    value = GetParameter(context, params, "exitScreen");
    if (!JS_IsUndefined(value)) {
        [player setMissionExitScreen:OOGUIScreenIDFromJSValue(context, value)];
    } else {
        [player setMissionExitScreen:GUI_SCREEN_STATUS];
    }
    JS_FreeValue(context, value);

    value = GetParameter(context, params, "screenID");
    if (!JS_IsUndefined(value)) {
        [player setMissionScreenID:OOStringFromJSValue(context, value)];
    } else {
        [player clearMissionScreenID];
    }
    JS_FreeValue(context, value);

    [player clearExtraMissionKeys];
    value = GetParameter(context, params, "registerKeys");
    if (!JS_IsUndefined(value)) {
        [player setExtraMissionKeys:GetParameterDictionary(context, params, "registerKeys")];
    }
    JS_FreeValue(context, value);

    BOOL textEntry = NO;
    GetParameterBool(context, params, "textEntry", &textEntry);
    if (textEntry) {
        [player setMissionChoiceByTextEntry:YES];
    } else {
        [player setMissionChoiceByTextEntry:NO];
    }

    // Start the mission screen.
    SetOwnedValue(context, &sCallbackFunction, function);
    [player setGuiToMissionScreenWithCallback:!JS_IsNull(sCallbackFunction)];

    // Apply more settings. (These must be done after starting the screen for legacy reasons.)
    if (allowInterrupt) {
        [player allowMissionInterrupt];
    }
    NSString* message = GetParameterString(context, params, "message");
    if (message != nil) {
        [player addLiteralMissionText:message];
    } else {
        NSString* messageKey = GetParameterString(context, params, "messageKey");
        if (messageKey != nil)
            [player addMissionText:messageKey];
    }

    if (!textEntry) {
        NSDictionary* choices = GetParameterDictionary(context, params, "choices");
        if (choices == nil) {
            [player setMissionChoices:GetParameterString(context, params, "choicesKey")];
        } else {
            [player setMissionChoicesDictionary:choices];
        }
    }

    NSString* firstKey = GetParameterString(context, params, "initialChoicesKey");
    if (firstKey != nil) {
        OOGUIRow row = [[UNIVERSE gui] rowForKey:firstKey];
        if (row != -1) {
            [[UNIVERSE gui] setSelectedRow:row];
        }
    }

    // now clean up!
    [player setMissionOverlayDescriptor:nil];
    [player setMissionBackgroundDescriptor:nil];
    [player setMissionTitle:nil];
    [player setMissionMusic:nil];

    JS_FreeValue(context, params);

    OOJSResumeTimeLimiter();

    OOJS_RETURN_BOOL(YES);

    OOJS_NATIVE_EXIT
}

static JSValue MissionRunShipLibrary(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    PlayerEntity* player = OOPlayerForScripting();
    BOOL OK = YES;
    if ([player status] != STATUS_DOCKED) {
        OOJSReportWarning(context, @"Mission.runShipLibrary: must be docked.");
        OK = NO;
    } else {
        [PLAYER setGuiToIntroFirstGo:NO];
    }

    OOJS_RETURN_BOOL(OK);

    OOJS_NATIVE_EXIT
}
