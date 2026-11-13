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

#include "OOJSMission.h"

#include "GuiDisplayGen.h"
#include "OOConstToJSString.h"
#include "OODebugStandards.h"
#include "OOJSPlayer.h"
#include "OOJSScript.h"
#include "OOJSVector.h"
#include "OOJavaScriptEngine.h"
#include "OOMusicController.h"
#include "OOStringExpander.h"
#include "PlayerEntityScriptMethods.h"
#include "oofnd/Notification.hpp"
#include "oofnd/objc/OOException.h"

static JSValue MissionGetProperty(OOJS_GETTER_ARGS);
static JSValue MissionSetProperty(OOJS_SETTER_ARGS);

static JSValue MissionMarkSystem(OOJS_NATIVE_ARGS);
static JSValue MissionUnmarkSystem(OOJS_NATIVE_ARGS);
static JSValue MissionAddMessageText(OOJS_NATIVE_ARGS);
static JSValue MissionSetInstructions(OOJS_NATIVE_ARGS);
static JSValue MissionSetInstructionsKey(OOJS_NATIVE_ARGS);
static JSValue MissionRunScreen(OOJS_NATIVE_ARGS);
static JSValue MissionRunShipLibrary(OOJS_NATIVE_ARGS);

static JSValue MissionSetInstructionsInternal(JSContext* context, int argc,
                                              JSValueConst* argv, bool isKey);

/*	Mission screen callback variables.
        sCallbackFunction and sCallbackThis own their values (they were GC roots
        with SpiderMonkey). They are zero-filled until first set, so test them
        with JS_IsObject()/JS_IsFunction(). They are freed when consumed and
   when the engine is reset.
*/
static JSValue sCallbackFunction;
static JSValue sCallbackThis;
// The script that set the callback, shared. The holder is never deleted, so
// exit(0) runs no script's destructor after the engine has gone.
static std::shared_ptr<OOJSScript>& CallbackScript() {
  static std::shared_ptr<OOJSScript>& script =
      *new std::shared_ptr<OOJSScript>();
  return script;
}

// Borrowed: owned by the global object's read-only, permanent "mission"
// property. Reset by InitOOJSMission().
static JSValue sMissionObject;

static JSClassID sMissionClassID;
static JSClassDef sMissionClass = {
    .class_name = "Mission",
};

namespace {

enum class MissionProperty : std::int16_t {
  kMarkedSystems,
  kScreenID,
  kExitScreen
};

}  // namespace

static const JSCFunctionListEntry sMissionProperties[] = {
    // JS name					Getter
    // Setter				ID
    OOJS_PROPERTY_RO("markedSystems", MissionGetProperty,
                     MissionProperty::kMarkedSystems),
    OOJS_PROPERTY_RO("screenID", MissionGetProperty,
                     MissionProperty::kScreenID),
    OOJS_PROPERTY_RW("exitScreen", MissionGetProperty, MissionSetProperty,
                     MissionProperty::kExitScreen),
};

static const JSCFunctionListEntry sMissionMethods[] = {
    // JS name					Function
    // min args
    JS_CFUNC_DEF("addMessageText", 1, MissionAddMessageText),
    JS_CFUNC_DEF("markSystem", 1, MissionMarkSystem),
    JS_CFUNC_DEF("runScreen", 1,
                 MissionRunScreen),  // the callback function is optional!
    JS_CFUNC_DEF("setInstructions", 1, MissionSetInstructions),
    JS_CFUNC_DEF("setInstructionsKey", 1, MissionSetInstructionsKey),
    JS_CFUNC_DEF("unmarkSystem", 1, MissionUnmarkSystem),
    JS_CFUNC_DEF("runShipLibrary", 0, MissionRunShipLibrary),
};

// Replace an owned static value, freeing the old one.
static void SetOwnedValue(JSContext* context, JSValue* slot,
                          JSValueConst value) {
  JSValue old = *slot;
  *slot = JS_DupValue(context, value);
  JS_FreeValue(context, old);  // Zero-filled (integer) values need no freeing,
                               // and JS_FreeValue() ignores them.
}

static void ClearPendingCallback() {
  JSContext* context = OOJSAcquireContext();
  SetOwnedValue(context, &sCallbackFunction, JS_NULL);
  SetOwnedValue(context, &sCallbackThis, JS_NULL);
  CallbackScript().reset();
  OOJSRelinquishContext(context);
}

void InitOOJSMission(JSContext* context, JSValueConst global) {
  static bool observing = false;
  if (!observing) {
    // Releases the pending callback before the context is destroyed.
    static const char sResetObserver = 0;
    oo::NotificationCenter::defaultCenter().addObserver(
        &sResetObserver, kOOJavaScriptEngineWillResetNotificationName, nullptr,
        [](const oo::Notification&) { ClearPendingCallback(); });
    observing = true;
  }

  sCallbackFunction = JS_NULL;
  sCallbackThis = JS_NULL;

  OOJSRegisterClass(&sMissionClassID, &sMissionClass);
  JSValueConst missionPrototype =
      OOJSInitClass(context, global, sMissionClassID, JS_UNDEFINED,
                    OOJSUnconstructableConstruct, 0, sMissionProperties,
                    OOJS_COUNT(sMissionProperties), sMissionMethods,
                    OOJS_COUNT(sMissionMethods), nullptr, 0);
  JSValue missionObject =
      JS_NewObjectProtoClass(context, missionPrototype, sMissionClassID);
  sMissionObject = missionObject;
  JS_DefinePropertyValueStr(context, global, "mission", missionObject,
                            OOJS_PROP_READONLY);
}

void MissionRunCallback() {
  // don't do anything if we don't have a function.
  if (!JS_IsObject(sCallbackFunction)) return;

  JSValue argval = JS_UNDEFINED;
  JSValue argval2 = JS_UNDEFINED;
  JSValue rval = JS_UNDEFINED;
  PlayerEntity* player = OOPlayerForScripting();
  OOJavaScriptEngine* engine = OOJavaScriptEngine::sharedEngine();
  JSContext* context = OOJSAcquireContext();

  /*	Take local (owned) copies of sCallbackFunction and sCallbackThis, then
          clear the statics. This must be done in advance since the callback
          might call runScreen() and clobber the statics.
  */
  JSValue cbFunction = sCallbackFunction;
  JSValue cbThis = JS_NULL;
  std::shared_ptr<OOJSScript> cbScriptHold = std::move(CallbackScript());
  OOJSScript* cbScript = cbScriptHold.get();

  // As with JS_ValueToObject(), null and undefined give no object (and so the
  // global object as this).
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

  // (CallbackScript() is empty: cbScriptHold took it.)
  sCallbackFunction = JS_NULL;  // Ownership moved to cbFunction.
  SetOwnedValue(context, &sCallbackThis, JS_NULL);

  JSValue args[2];
  argval = OOJSValueFromPList(
      context,
      (player != nullptr ? player->missionChoice_string() : oo::PList()));
  argval2 = OOJSValueFromPList(
      context,
      (player != nullptr ? player->missionKeyPress_string() : oo::PList()));
  args[0] = argval;
  args[1] = argval2;

  // now reset the mission choice silently, before calling the callback script.
  if (player != nullptr) player->setMissionChoice(std::nullopt, "", false);

  // Call the callback.
  try {
    OOJSScript::pushScript(cbScript);
    engine->callJSFunction(cbFunction, cbThis, 2, args, &rval);
  } catch (...) {
    const auto exception = oo::CurrentOOException();
    if (!exception) throw;  // not an OOException: it goes on up, as before
    // Squash any exception, allow cleanup to happen and so forth.
    OO_LOG(cxx_kOOLogException,
           "Ignoring exception {}:{} during handling of mission screen "
           "completion callback.",
           exception->name(), exception->reason());
  }
  OOJSScript::popScript(cbScript);

  // Manage that memory.
  cbScriptHold.reset();
  JS_FreeValue(context, rval);
  JS_FreeValue(context, argval);
  JS_FreeValue(context, argval2);
  JS_FreeValue(context, cbFunction);
  JS_FreeValue(context, cbThis);

  OOJSRelinquishContext(context);
}

static JSValue MissionGetProperty(OOJS_GETTER_ARGS) {
  OOJS_NATIVE_ENTER(context)

  oo::PList result;  // null maps to null
  PlayerEntity* player = OOPlayerForScripting();

  switch (static_cast<MissionProperty>(magic)) {
    using enum MissionProperty;
    case kMarkedSystems: {
      // The destinations' values, in key order (-allValues gave hash order).
      oo::PList::Array values;
      // Kept in a local: getIf() points into it, and a temporary would die at
      // the end of the if's initialiser (a dangling pointer).
      const oo::PList missionDestinations =
          (player != nullptr ? player->getMissionDestinations() : oo::PList());
      if (const oo::PList::Dict* destinations =
              missionDestinations.getIf<oo::PList::Dict>()) {
        for (const auto& entry : *destinations) {
          if (!entry.second.isNull()) values.push_back(entry.second);
        }
      }
      result = oo::PList(std::move(values));
    } break;

    case kScreenID:
      if (const std::optional<std::string> screenID =
              (player != nullptr ? player->missionScreenID()
                                 : std::optional<std::string>()))
        result = oo::PList(*screenID);
      break;

    case kExitScreen:
      return OOJSValueFromGUIScreenID(
          context,
          (player != nullptr ? player->missionExitScreen() : OOGUIScreenID{}));

    default:
      OOJSReportBadPropertySelector(context, thisObj, magic, sMissionProperties,
                                    OOJS_COUNT(sMissionProperties));
      return JS_EXCEPTION;
  }

  return OOJSValueFromPList(context, result);

  OOJS_NATIVE_EXIT
}

static JSValue MissionSetProperty(OOJS_SETTER_ARGS) {
  OOJS_NATIVE_ENTER(context)

  OOGUIScreenID exitScreen;
  PlayerEntity* player = OOPlayerForScripting();

  switch (static_cast<MissionProperty>(magic)) {
    using enum MissionProperty;
    case kExitScreen:
      exitScreen = OOGUIScreenIDFromJSValue(context, value);
      if (player != nullptr) player->setMissionExitScreen(exitScreen);
      return JS_UNDEFINED;

    default:
      OOJSReportBadPropertySelector(context, thisObj, magic, sMissionProperties,
                                    OOJS_COUNT(sMissionProperties));
      return JS_EXCEPTION;
  }

  OOJSReportBadPropertyValue(context, thisObj, magic, sMissionProperties,
                             OOJS_COUNT(sMissionProperties), value);
  return JS_EXCEPTION;

  OOJS_NATIVE_EXIT
}

// *** Methods ***

// JS_ValueToInt32() without leaving an exception pending on failure
// (SpiderMonkey callers cleared it).
static bool ValueToInt32NoError(JSContext* context, JSValueConst value,
                                int32_t* outValue) {
  if (OOJSValueToInt32(context, value, outValue)) return true;
  if (JS_HasException(context))
    JS_FreeValue(
        context,
        JS_GetException(
            context));  // or JS_ValueToInt32 exception crashes JS engine
  return false;
}

// markSystem(integer+)
static JSValue MissionMarkSystem(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  PlayerEntity* player = OOPlayerForScripting();
  int i;
  int32_t dest;

  // two pass. Once to validate, once to apply if they validate
  for (i = 0; i < argc; i++) {
    if (!ValueToInt32NoError(context, OOJS_ARGV[i], &dest)) {
      // (JSVAL_IS_OBJECT() was also true for null, which converts to 0 and so
      // never gets here.)
      if (!JS_IsObject(OOJS_ARGV[i])) {
        cxx_OOJSReportBadArguments(context, "Mission", "markSystem",
                                   MIN(argc, 1), OOJS_ARGV, std::nullopt,
                                   "numbers or objects");
        return JS_EXCEPTION;
      }
    }
  }

  for (i = 0; i < argc; i++) {
    if (ValueToInt32NoError(context, OOJS_ARGV[i], &dest)) {
      cxx_OOStandardsDeprecated(
          "Use of numbers for mission.markSystem is deprecated");
      if (!OOEnforceStandards()) {
        if (player != nullptr)
          player->addMissionDestinationMarker(
              (player != nullptr ? player->defaultMarker(dest) : oo::PList()));
      }
    } else  // must be object, from above
    {
      oo::PList marker = cxx_OOJSPListFromJSObject(context, OOJS_ARGV[i]);
      OOSystemID system = marker.get<int>("system", -1);
      if (system >= 0) {
        if (player != nullptr) player->addMissionDestinationMarker(marker);
      }
    }
  }
  OOJS_RETURN_VOID;

  OOJS_NATIVE_EXIT
}

// unmarkSystem(integer+)
static JSValue MissionUnmarkSystem(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  PlayerEntity* player = OOPlayerForScripting();
  int i;
  int32_t dest;

  // two pass. Once to validate, once to apply if they validate
  for (i = 0; i < argc; i++) {
    if (!ValueToInt32NoError(context, OOJS_ARGV[i], &dest)) {
      if (!JS_IsObject(OOJS_ARGV[i])) {
        cxx_OOJSReportBadArguments(context, "Mission", "unmarkSystem",
                                   MIN(argc, 1), OOJS_ARGV, std::nullopt,
                                   "numbers or objects");
        return JS_EXCEPTION;
      }
    }
  }

  bool result = true;
  for (i = 0; i < argc; i++) {
    if (ValueToInt32NoError(context, OOJS_ARGV[i], &dest)) {
      cxx_OOStandardsDeprecated(
          "Use of numbers for mission.unmarkSystem is deprecated");
      if (!OOEnforceStandards()) {
        if (!(player != nullptr
                  ? player->removeMissionDestinationMarker(
                        (player != nullptr ? player->defaultMarker(dest)
                                           : oo::PList()))
                  : false)) {
          result = false;
        }
      }
    } else  // must be object, from above
    {
      oo::PList marker = cxx_OOJSPListFromJSObject(context, OOJS_ARGV[i]);
      OOSystemID system = marker.get<int>("system", -1);
      if (system >= 0) {
        if (!(player != nullptr ? player->removeMissionDestinationMarker(marker)
                                : false)) {
          result = false;
        }
      }
    }
  }

  OOJS_RETURN_BOOL(result);

  OOJS_NATIVE_EXIT
}

// addMessageText(text : String)
static JSValue MissionAddMessageText(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  PlayerEntity* player = OOPlayerForScripting();
  std::optional<std::string> text;

  if (EXPECT_NOT(argc == 0)) {
    OOJS_RETURN_VOID;
  }

  // Found "FIXME: warning if no mission screen running.",,,
  // However: used routinely by the Constrictor mission in F7, without mission
  // screens.
  text = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
  if (text.has_value()) {
    if (player != nullptr) player->addLiteralMissionText(*text);
  }  // (nil added nothing)

  OOJS_RETURN_VOID;

  OOJS_NATIVE_EXIT
}

// setInstructionsKey(instructionsKey: String [, missionKey : String])
static JSValue MissionSetInstructionsKey(OOJS_NATIVE_ARGS) {
  return MissionSetInstructionsInternal(context, argc, OOJS_ARGV, true);
}

// setInstructions(instructions: String [, missionKey : String])
static JSValue MissionSetInstructions(OOJS_NATIVE_ARGS) {
  return MissionSetInstructionsInternal(context, argc, OOJS_ARGV, false);
}

static JSValue MissionSetInstructionsInternal(JSContext* context, int argc,
                                              JSValueConst* argv, bool isKey) {
  OOJS_NATIVE_ENTER(context)

  PlayerEntity* player = OOPlayerForScripting();
  std::optional<std::string> text;
  oo::PList texts;
  std::optional<std::string> missionKey;

  if (EXPECT_NOT(argc == 0)) {
    cxx_OOJSReportWarning(
        context,
        "Usage error: mission.%s() called with no arguments. Treating as "
        "Mission.%s(null). This call may fail in a future version of Oolite.",
        (isKey ? "setInstructionsKey" : "setInstructions"),
        (isKey ? "setInstructionsKey" : "setInstructions"));
  } else if (EXPECT_NOT(JS_IsUndefined(argv[0]))) {
    cxx_OOJSReportBadArguments(
        context, "Mission",
        std::string(isKey ? "setInstructionsKey" : "setInstructions"), 1, argv,
        std::nullopt, "string or null");
    return JS_EXCEPTION;
  } else if (!JS_IsNull(argv[0]) && JS_IsObject(argv[0])) {
    texts = cxx_OOJSPListFromJSValue(context, argv[0]);
  } else {
    text = cxx_OOStringFromJSValue(context, argv[0]);
  }

  if (argc > 1) {
    missionKey = cxx_OOStringFromJSValueEvenIfNull(context, argv[1]);
  } else {
    OOJSScript* runningScript = OOJSScript::currentlyRunningScript();
    missionKey =
        (runningScript != nullptr) ? runningScript->name() : std::nullopt;
  }

  if (text.has_value()) {
    if (isKey) {
      if (player != nullptr) player->setMissionDescription(*text, missionKey);
    } else {
      if (player != nullptr) player->setMissionInstructions(*text, missionKey);
    }
  } else if (!texts.isNull() && !isKey) {
    if (player != nullptr)
      player->setMissionInstructionsList(texts, missionKey);
  } else {
    if (missionKey.has_value()) {
      if (player != nullptr)
        player->clearMissionDescriptionForMission(*missionKey);
    } else {
      if (player != nullptr)
        player->setMissionInstructions(std::string(), std::nullopt);
    }  // logs "mission key not set", as a nil key did
  }

  OOJS_RETURN_VOID;

  OOJS_NATIVE_EXIT
}

/*	Get a property of the runScreen() parameter object. Returns an owned
   value. If a getter throws, the exception is reported and cleared and the
        property is treated as undefined. (SpiderMonkey's JS_GetProperty()
        returned false, which the code below treats as a missing property; a
        QuickJS native must not return normally with an exception pending.)
*/
static JSValue GetParameter(JSContext* context, JSValueConst object,
                            const char* key) {
  JSValue value = JS_GetPropertyStr(context, object, key);
  if (JS_IsException(value)) {
    OOJSReportPendingException(context);
    return JS_UNDEFINED;
  }
  return value;
}

static oo::PList GetParameterDictionary(JSContext* context, JSValueConst object,
                                        const char* key) {
  oo::PList result;  // was nil
  JSValue value = GetParameter(context, object, key);
  if (JS_IsObject(value)) {
    result = cxx_OOJSPListFromJSObject(context, value);
  }
  JS_FreeValue(context, value);
  return result;
}

static std::optional<std::string> GetParameterString(JSContext* context,
                                                     JSValueConst object,
                                                     const char* key) {
  JSValue value = GetParameter(context, object, key);
  std::optional<std::string> result = cxx_OOStringFromJSValue(context, value);
  JS_FreeValue(context, value);
  return result;
}

// What -oo_stringForKey: made of the value it found: a string, or a number's
// text; nullopt (was nil) for no value or any other kind of value.
static std::optional<std::string> StringFromPList(const oo::PList* value) {
  if (value == nullptr || !(value->isString() || value->isNumber()))
    return std::nullopt;
  return oo::PListGet<std::string>::from(value, std::string());
}

static oo::PList GetParameterImageDescriptor(JSContext* context,
                                             JSValueConst object,
                                             const char* key) {
  JSValue value = JS_GetPropertyStr(context, object, key);
  if (JS_IsException(value)) {
    OOJSReportPendingException(context);
    return oo::PList();  // was nil
  }
  oo::PList result = UNIVERSE->getGui()->textureDescriptorFromJSValue(
      value, context, std::string("mission.runScreen()"));
  JS_FreeValue(context, value);
  return result;
}

// Get a boolean parameter; *outValue is left unchanged if the parameter is
// undefined.
static void GetParameterBool(JSContext* context, JSValueConst object,
                             const char* key, bool* outValue) {
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

// runScreen(params: dict, callBack:function) - if the callback function is
// null, emulate the old style runMissionScreen
static JSValue MissionRunScreen(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  PlayerEntity* player = OOPlayerForScripting();
  JSValueConst function = JS_NULL;
  JSValue value = JS_UNDEFINED;
  JSValue params = JS_UNDEFINED;

  // No mission screens during intro.
  if ((player != nullptr ? player->status() : OOEntityStatus{}) ==
      OOEntityStatus::kStartGame) {
    // (though no JS should be loaded at this stage, so this
    // check may be obsolete - CIM)
    OOJS_RETURN_BOOL(false);
  }

  // Validate arguments.
  // (SpiderMonkey's JS_ValueToObject() accepted null and undefined, yielding no
  // object, and then crashed; treat them as invalid.)
  if (argc >= 1 && !JS_IsNull(OOJS_ARGV[0]) && !JS_IsUndefined(OOJS_ARGV[0])) {
    params = JS_ToObject(context, OOJS_ARGV[0]);
    if (JS_IsException(params)) {
      JS_FreeValue(context, JS_GetException(context));
      params = JS_UNDEFINED;
    }
  }
  if (!JS_IsObject(params)) {
    cxx_OOJSReportBadArguments(context, "mission", "runScreen", MIN(argc, 1),
                               &OOJS_ARGV[0], std::nullopt, "parameter object");
    return JS_EXCEPTION;
  }

  if (argc > 1) function = OOJS_ARGV[1];
  if (!JS_IsNull(function) && !OOJSValueIsFunction(context, function)) {
    JS_FreeValue(context, params);
    cxx_OOJSReportBadArguments(context, "mission", "runScreen", 1,
                               &OOJS_ARGV[1], std::nullopt, "function");
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

    // (Leaked by the SpiderMonkey version if
    // runScreen() was called twice.)
    CallbackScript() = oo::share(OOJSScript::currentlyRunningScript());
    if (argc > 2) {
      SetOwnedValue(context, &sCallbackThis, OOJS_ARGV[2]);
    } else {
      JSValue scriptValue =
          OOJSValueFromCxxObject(context, CallbackScript().get());
      SetOwnedValue(context, &sCallbackThis, scriptValue);
      JS_FreeValue(context, scriptValue);
    }
  }

  // Apply settings.
  value = GetParameter(context, params, "title");
  if (!JS_IsUndefined(value)) {
    if (player != nullptr)
      player->setMissionTitle(cxx_OOStringFromJSValue(context, value));
  } else {
    std::optional<std::string> titleKey =
        GetParameterString(context, params, "titleKey");
    if (titleKey.has_value()) {
      const oo::PList missionText =
          (UNIVERSE != nullptr ? UNIVERSE->getMissiontext() : oo::PList());
      std::optional<std::string> message =
          StringFromPList(missionText.find(*titleKey));  // -objectForKey:
      if (message.has_value()) {
        if (player != nullptr) player->setMissionTitle(cxx_OOExpand(*message));
      } else {
        cxx_OOJSReportWarning(context,
                              "Mission.runScreen: titleKey '%s' has no entry "
                              "in missiontext.plist.",
                              titleKey->c_str());
      }
    }
  }
  JS_FreeValue(context, value);

  OOMusicController::sharedController()->setMissionMusic(
      GetParameterString(context, params, "music"));
  if (player != nullptr)
    player->setMissionOverlayDescriptor(
        GetParameterImageDescriptor(context, params, "overlay"));
  if (player != nullptr)
    player->setMissionBackgroundDescriptor(
        GetParameterImageDescriptor(context, params, "background"));
  if (player != nullptr)
    player->setMissionBackgroundSpecial(
        GetParameterString(context, params, "backgroundSpecial").value_or(""));

  value = GetParameter(context, params, "customChartZoom");
  if (!JS_IsUndefined(value)) {
    double zoom;
    if (JS_ToFloat64(context, &zoom, value) == 0) {
      if (zoom >= 1 && zoom <= CHART_MAX_ZOOM) {
        if (player != nullptr) player->setCustomChartZoom(zoom);
      } else {
        cxx_OOJSReportWarning(
            context,
            "Mission.runScreen: invalid customChartZoom value specified.");
        if (player != nullptr) player->setCustomChartZoom(1);
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
      NSPoint coords = {vValue.x, vValue.y};
      if (player != nullptr) player->setCustomChartCentre(coords);
    } else {
      if (player != nullptr)
        player->setCustomChartCentre(
            (player != nullptr
                 ? player->PlayerEntity::getGalaxy_coordinates()
                 : NSPoint{}));  // qualified: the final overrider, so the
                                 // binding test stands in for it
      cxx_OOJSReportWarning(
          context,
          "Mission.runScreen: invalid value for customChartCentre. Must be "
          "valid vector. Defaulting to current location.");
    }
  }
  JS_FreeValue(context, value);

  value = GetParameter(context, params, "customChartCentreInLY");
  if (!JS_IsUndefined(value)) {
    Vector vValue;
    if (JSValueToVector(context, value, &vValue)) {
      NSPoint coords = OOInternalCoordinatesFromGalactic(vValue);
      if (player != nullptr) player->setCustomChartCentre(coords);
    } else {
      if (player != nullptr)
        player->setCustomChartCentre(
            (player != nullptr
                 ? player->PlayerEntity::getGalaxy_coordinates()
                 : NSPoint{}));  // qualified: the final overrider, so the
                                 // binding test stands in for it
      cxx_OOJSReportWarning(
          context,
          "Mission.runScreen: invalid value for customChartCentreInLY. Must be "
          "valid vector. Defaulting to current location.");
    }
  }
  JS_FreeValue(context, value);

  if (UNIVERSE != nullptr)
    UNIVERSE->removeDemoShips();  // remove any demoship or miniature planet
                                  // that may be remaining from previous screens

  ShipEntity* demoShip = nullptr;
  value = GetParameter(context, params, "model");
  if (!JS_IsUndefined(value)) {
    if ((player != nullptr ? player->status() : OOEntityStatus{}) ==
            OOEntityStatus::kInFlight &&
        JS_IsString(value)) {
      cxx_OOJSReportWarning(
          context,
          "Mission.runScreen: model cannot be displayed while in flight.");
    } else {
      std::optional<std::string> role = cxx_OOStringFromJSValue(context, value);

      bool spinning = true;
      GetParameterBool(context, params, "spinModel", &spinning);

      //	[player
      // showShipModel:oo::NSStringOrNil(cxx_OOStringFromJSValue(context,
      // value))];
      demoShip = (UNIVERSE != nullptr ? UNIVERSE->makeDemoShipWithRole(
                                            role.value_or(""), spinning)
                                      : static_cast<::ShipEntity*>(nullptr));
    }
  }
  JS_FreeValue(context, value);

  if (demoShip != nullptr) {
    value = GetParameter(context, params, "modelPersonality");
    if (!JS_IsUndefined(value)) {
      int32_t personality = 0;
      if (!OOJSValueToInt32(context, value, &personality) &&
          JS_HasException(context)) {
        JS_FreeValue(context, JS_GetException(context));
      }
      demoShip->setEntityPersonalityInt(personality);
    }
    JS_FreeValue(context, value);

    JSValue demoShipVal =
        OOJSValueFromCxxObject(context, demoShip);  // the C++ ship's JS value
    if (JS_SetPropertyStr(context, sMissionObject, "displayModel",
                          demoShipVal) < 0) {
      OOJSReportPendingException(context);
    }
  } else {
    if (JS_DeleteProperty(context, sMissionObject, OOJSID("displayModel"), 0) <
        0) {
      OOJSReportPendingException(context);
    }
  }

  bool allowInterrupt = false;
  // force the allowInterrupt to be YES while in flight
  if ((player != nullptr ? player->status() : OOEntityStatus{}) ==
      OOEntityStatus::kInFlight) {
    allowInterrupt = true;
  } else {
    GetParameterBool(context, params, "allowInterrupt", &allowInterrupt);
  }

  value = GetParameter(context, params, "exitScreen");
  if (!JS_IsUndefined(value)) {
    if (player != nullptr)
      player->setMissionExitScreen(OOGUIScreenIDFromJSValue(context, value));
  } else {
    if (player != nullptr) player->setMissionExitScreen(OOGUIScreenID::kStatus);
  }
  JS_FreeValue(context, value);

  value = GetParameter(context, params, "screenID");
  if (!JS_IsUndefined(value)) {
    if (player != nullptr)
      player->setMissionScreenID(cxx_OOStringFromJSValue(context, value));
  } else {
    if (player != nullptr) player->clearMissionScreenID();
  }
  JS_FreeValue(context, value);

  if (player != nullptr) player->clearExtraMissionKeys();
  value = GetParameter(context, params, "registerKeys");
  if (!JS_IsUndefined(value)) {
    if (player != nullptr)
      player->setExtraMissionKeys(
          GetParameterDictionary(context, params, "registerKeys"));
  }
  JS_FreeValue(context, value);

  bool textEntry = false;
  GetParameterBool(context, params, "textEntry", &textEntry);
  if (textEntry) {
    if (player != nullptr) player->setMissionChoiceByTextEntry(true);
  } else {
    if (player != nullptr) player->setMissionChoiceByTextEntry(false);
  }

  // Start the mission screen.
  SetOwnedValue(context, &sCallbackFunction, function);
  if (player != nullptr)
    player->setGuiToMissionScreenWithCallback(!JS_IsNull(sCallbackFunction));

  // Apply more settings. (These must be done after starting the screen for
  // legacy reasons.)
  if (allowInterrupt) {
    if (player != nullptr) player->allowMissionInterrupt();
  }
  std::optional<std::string> message =
      GetParameterString(context, params, "message");
  if (message.has_value()) {
    if (player != nullptr) player->addLiteralMissionText(*message);
  } else {
    std::optional<std::string> messageKey =
        GetParameterString(context, params, "messageKey");
    if (messageKey.has_value()) {
      if (player != nullptr) player->addMissionText(*messageKey);
    }
  }

  if (!textEntry) {
    oo::PList choices = GetParameterDictionary(context, params, "choices");
    if (choices.isNull()) {
      if (player != nullptr)
        player->setMissionChoices(
            GetParameterString(context, params, "choicesKey")
                .value_or(std::string()));  // (nil was "")
    } else {
      if (player != nullptr) player->setMissionChoicesDictionary(choices);
    }
  }

  std::optional<std::string> firstKey =
      GetParameterString(context, params, "initialChoicesKey");
  if (firstKey.has_value()) {
    OOGUIRow row = UNIVERSE->getGui()->rowForKey(firstKey);
    if (row != -1) {
      UNIVERSE->getGui()->setSelectedRow(row);
    }
  }

  // now clean up!
  if (player != nullptr) player->setMissionOverlayDescriptor(oo::PList());
  if (player != nullptr) player->setMissionBackgroundDescriptor(oo::PList());
  if (player != nullptr) player->setMissionTitle(std::nullopt);
  if (player != nullptr)
    player->setMissionMusic(std::string());  // (nil was "none")

  JS_FreeValue(context, params);

  OOJSResumeTimeLimiter();

  OOJS_RETURN_BOOL(true);

  OOJS_NATIVE_EXIT
}

static JSValue MissionRunShipLibrary(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  PlayerEntity* player = OOPlayerForScripting();
  bool OK = true;
  if ((player != nullptr ? player->status() : OOEntityStatus{}) !=
      OOEntityStatus::kDocked) {
    cxx_OOJSReportWarning(context, "Mission.runShipLibrary: must be docked.");
    OK = false;
  } else {
    if (PLAYER != nullptr) PLAYER->setGuiToIntroFirstGo(false);
  }

  OOJS_RETURN_BOOL(OK);

  OOJS_NATIVE_EXIT
}
