/*

OOJSMissionVariables.h

JavaScript mission variables object.


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

#include "OOJSMissionVariables.h"

#include "OOIsNumberLiteral.h"
#include "OOJSPlayer.h"
#include "OOJavaScriptEngine.h"
#include "oofnd/String.hpp"

/*	SpiderMonkey called the MissionVariables class's get, set and delete
   hooks for every property access, and its enumerate hook for for-in. QuickJS
        has no such hooks; the class's exotic methods provide the same view
        instead: every mission variable appears as an enumerable own property,
        assignments and deletions go to the player's mission variables, and
        reading a missing (non-"_") name gives null, as before. Names starting
        with "_" are not mission variables; reading them falls back to the
        prototype (Object.prototype) and assigning them is an error. Properties
        of Object.prototype (such as toString) are found there unless a mission
        variable of the same name exists.
*/

// Property name for a string property ID, or nullopt for other IDs (symbols).
static std::optional<std::string> NameForPropertyID(JSContext* context,
                                                    JSAtom propID) {
  std::optional<std::string> result;
  JSValue idValue = JS_AtomToValue(context, propID);
  // SpiderMonkey's hooks ignored integer IDs; QuickJS uses integer atoms for
  // names like "0".
  if (JS_IsString(idValue)) {
    result = OOStringFromJSValue(context, idValue);
  }
  JS_FreeValue(context, idValue);
  return result;
}

static std::optional<std::string> KeyForPropertyName(
    const std::optional<std::string>& name) {
  if (!name.has_value() || oo::str::hasPrefix(*name, "_")) return std::nullopt;
  return "mission_" + *name;
}

static int MissionVariablesGetOwnProperty(JSContext* context,
                                          JSPropertyDescriptor* desc,
                                          JSValueConst object, JSAtom propID);
static int MissionVariablesGetOwnPropertyNames(JSContext* context,
                                               JSPropertyEnum** outTable,
                                               uint32_t* outCount,
                                               JSValueConst object);
static int MissionVariablesDeleteProperty(JSContext* context,
                                          JSValueConst object, JSAtom propID);
static int MissionVariablesDefineOwnProperty(JSContext* context,
                                             JSValueConst object, JSAtom propID,
                                             JSValueConst value,
                                             JSValueConst getter,
                                             JSValueConst setter, int flags);
static JSValue MissionVariablesGetProperty(JSContext* context,
                                           JSValueConst object, JSAtom propID,
                                           JSValueConst receiver);
static int MissionVariablesSetProperty(JSContext* context, JSValueConst object,
                                       JSAtom propID, JSValueConst value,
                                       JSValueConst receiver, int flags);

#ifdef OO_DEBUG_MONITOR_ENABLED
static oo::PList MissionVariablesConverter(JSContext* context,
                                           JSValueConst object);
#endif

static JSClassExoticMethods sMissionVariablesExoticMethods = {
    .get_own_property = MissionVariablesGetOwnProperty,
    .get_own_property_names = MissionVariablesGetOwnPropertyNames,
    .delete_property = MissionVariablesDeleteProperty,
    .define_own_property = MissionVariablesDefineOwnProperty,
    .get_property = MissionVariablesGetProperty,
    .set_property = MissionVariablesSetProperty,
};

static JSClassID sMissionVariablesClassID;
static JSClassDef sMissionVariablesClass = {
    .class_name = "MissionVariables",
    .exotic = &sMissionVariablesExoticMethods,
};

void InitOOJSMissionVariables(JSContext* context, JSValueConst global) {
  OOJSRegisterClass(&sMissionVariablesClassID, &sMissionVariablesClass);

  // As with JS_DefineObject() with a NULL prototype, the prototype is
  // Object.prototype.
  JSValue objectPrototype = OOJSObjectPrototype(context);
  JSValue missionVariables = JS_NewObjectProtoClass(context, objectPrototype,
                                                    sMissionVariablesClassID);
  JS_FreeValue(context, objectPrototype);
  JS_DefinePropertyValueStr(context, global, "missionVariables",
                            missionVariables, OOJS_PROP_READONLY);

#ifdef OO_DEBUG_MONITOR_ENABLED
  // Allow callObjC() on missionVariables to call methods on the mission
  // variables dictionary.
  OOJSRegisterObjectConverter(sMissionVariablesClassID,
                              MissionVariablesConverter);
#endif
}

#ifdef OO_DEBUG_MONITOR_ENABLED
static oo::PList MissionVariablesConverter(JSContext* /*context*/,
                                           JSValueConst /*object*/) {
  return (PLAYER != nullptr ? PLAYER->missionVariables() : oo::PList());
}
#endif

// Owned value of a mission variable, or JS_UNDEFINED if it doesn't exist.
static JSValue ValueForMissionVariable(JSContext* context,
                                       const std::string& key) {
  PlayerEntity* player = OOPlayerForScripting();
  const oo::PList mvar =
      (player != nullptr ? player->missionVariableForKey(key) : oo::PList());

  if (mvar.isNull()) return JS_UNDEFINED;

  if (const std::string* string =
          mvar.getIf<std::string>())  // Currently there should only be strings,
                                      // but we may want to change this.
  {
    if (OOIsNumberLiteral(*string, true)) {
      return JS_NewNumber(
          context, oo::str::doubleValue(*string));  // as NSString's doubleValue
    }
  }

  return OOJSValueFromPList(context, mvar);
}

static int MissionVariablesGetOwnProperty(JSContext* context,
                                          JSPropertyDescriptor* desc,
                                          JSValueConst object, JSAtom propID) {
  try {
    std::optional<std::string> key =
        KeyForPropertyName(NameForPropertyID(context, propID));
    if (!key.has_value()) return false;

    JSValue value = ValueForMissionVariable(context, *key);
    if (JS_IsUndefined(value)) return false;

    if (desc != nullptr) {
      desc->flags = JS_PROP_C_W_E;
      desc->value = value;
      desc->getter = JS_UNDEFINED;
      desc->setter = JS_UNDEFINED;
    } else {
      JS_FreeValue(context, value);
    }
    return true;
  } catch (...) {
    OOJSReportCurrentException(context);
    return -1;
  }
}

static int MissionVariablesGetOwnPropertyNames(JSContext* context,
                                               JSPropertyEnum** outTable,
                                               uint32_t* outCount,
                                               JSValueConst object) {
  try {
    // A copy of the keys, which is good since the enumerating code might
    // mutate. In key order
    // (-allKeys gave them in hash order).
    std::vector<std::string> mvars;
    const oo::PList missionVariables =
        (PLAYER != nullptr ? PLAYER->missionVariables() : oo::PList());
    if (const oo::PList::Dict* dict =
            missionVariables.getIf<oo::PList::Dict>()) {
      for (const auto& entry : *dict) mvars.push_back(entry.first);
    }
    std::size_t count = mvars.size();
    assert(count <= INT32_MAX);

    JSPropertyEnum* table = static_cast<JSPropertyEnum*>(js_malloc(
        context, sizeof *table * MAX(count, static_cast<std::size_t>(1))));
    if (table == nullptr) return -1;

    uint32_t used = 0;
    for (std::string next : mvars) {
      if (!oo::str::hasPrefix(next, "mission_"))
        continue;  // Skip mission instructions, which aren't visible through
                   // missionVariables.

      next = next.substr(8);  // Cut off "mission_".

      JSAtom atom = JS_NewAtom(context, next.c_str());
      if (atom == JS_ATOM_NULL) {
        JS_FreePropertyEnum(context, table, used);
        return -1;
      }
      table[used].is_enumerable = true;
      table[used].atom = atom;
      used++;
    }

    // QuickJS frees the table and its atoms.
    *outTable = table;
    *outCount = used;
    return 0;
  } catch (...) {
    OOJSReportCurrentException(context);
    return -1;
  }
}

static int MissionVariablesDeleteProperty(JSContext* context,
                                          JSValueConst object, JSAtom propID) {
  try {
    PlayerEntity* player = OOPlayerForScripting();

    std::optional<std::string> name = NameForPropertyID(context, propID);
    if (name.has_value()) {
      std::optional<std::string> key = KeyForPropertyName(name);
      if (key.has_value()) {
        if (player != nullptr) player->setMissionVariable(oo::PList(), *key);
      }
    }
    return true;
  } catch (...) {
    OOJSReportCurrentException(context);
    return -1;
  }
}

static JSValue MissionVariablesGetProperty(JSContext* context,
                                           JSValueConst object, JSAtom propID,
                                           JSValueConst receiver) {
  OOJS_NATIVE_ENTER(context)

  std::optional<std::string> key =
      KeyForPropertyName(NameForPropertyID(context, propID));
  if (key.has_value()) {
    JSValue value = ValueForMissionVariable(context, *key);
    if (!JS_IsUndefined(value)) return value;
  }

  // Not a mission variable; look in the prototype chain.
  JSValue prototype = JS_GetPrototype(context, object);
  if (JS_IsException(prototype)) return JS_EXCEPTION;

  JSValue result = JS_UNDEFINED;
  if (JS_IsObject(prototype)) {
    int found =
        key.has_value() ? JS_HasProperty(context, prototype, propID) : true;
    if (found < 0) {
      result = JS_EXCEPTION;
    } else if (found) {
      result = JS_GetProperty(context, prototype, propID);
    } else {
      // Missing mission variables read as null
      // (OOJSValueFromNativeObject(nil)).
      result = JS_NULL;
    }
  } else if (key.has_value()) {
    result = JS_NULL;
  }
  JS_FreeValue(context, prototype);
  return result;

  OOJS_NATIVE_EXIT
}

static bool SetMissionVariable(JSContext* context, JSAtom propID,
                               JSValueConst value) {
  PlayerEntity* player = OOPlayerForScripting();

  std::optional<std::string> name = NameForPropertyID(context, propID);
  if (name.has_value()) {
    std::optional<std::string> key = KeyForPropertyName(name);
    if (!key.has_value()) {
      OOJSReportError(context, "Invalid mission variable name \"%s\".",
                      OOJSEscapedForJavaScriptLiteral(*name).c_str());
      return false;
    }

    // nil (a value with no string form) clears the variable. (The old OONull
    // test could not match a string and is gone.)
    std::optional<std::string> objValue = OOStringFromJSValue(context, value);

    if (player != nullptr)
      player->setMissionVariable(
          objValue.has_value() ? oo::PList(*objValue) : oo::PList(), *key);
  }
  return true;
}

static int MissionVariablesSetProperty(JSContext* context, JSValueConst object,
                                       JSAtom propID, JSValueConst value,
                                       JSValueConst receiver, int flags) {
  try {
    return SetMissionVariable(context, propID, value) ? true : -1;
  } catch (...) {
    OOJSReportCurrentException(context);
    return -1;
  }
}

static int MissionVariablesDefineOwnProperty(JSContext* context,
                                             JSValueConst object, JSAtom propID,
                                             JSValueConst value,
                                             JSValueConst getter,
                                             JSValueConst setter, int flags) {
  /*	Object.defineProperty() and friends. Mission variables can't be
          accessors; a defined value is stored like an assignment.
  */
  try {
    if (flags & (JS_PROP_HAS_GET | JS_PROP_HAS_SET)) {
      const std::optional<std::string> badName = OOStringFromJSID(propID);
      OOJSReportError(context, "Invalid mission variable name \"%s\".",
                      badName.has_value()
                          ? OOJSEscapedForJavaScriptLiteral(*badName).c_str()
                          : "(null)");
      return -1;
    }
    if (!(flags & JS_PROP_HAS_VALUE)) return true;
    return SetMissionVariable(context, propID, value) ? true : -1;
  } catch (...) {
    OOJSReportCurrentException(context);
    return -1;
  }
}
