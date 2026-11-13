/*

OOJSWorldScripts.m


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

#include "OOJSWorldScripts.h"

#include <cstring>

#include "OOJSPlayer.h"
#include "OOJavaScriptEngine.h"
#include "OOScript.h"
#include "PlayerEntity.h"

/*	SpiderMonkey called the WorldScripts class's getProperty hook for every
        property access and its enumerate hook defined each script's name on
        demand. QuickJS has no such hooks; instead, the class's exotic
        get_own_property and get_own_property_names methods make every world
        script appear as an enumerable, read-only own property.
*/
static int WorldScriptsGetOwnProperty(JSContext* context,
                                      JSPropertyDescriptor* desc,
                                      JSValueConst object, JSAtom propID);
static int WorldScriptsGetOwnPropertyNames(JSContext* context,
                                           JSPropertyEnum** outTable,
                                           uint32_t* outCount,
                                           JSValueConst object);

static JSClassExoticMethods sWorldScriptsExoticMethods = {
    .get_own_property = WorldScriptsGetOwnProperty,
    .get_own_property_names = WorldScriptsGetOwnPropertyNames,
};

static JSClassID sWorldScriptsClassID;
static JSClassDef sWorldScriptsClass = {
    .class_name = "WorldScripts",
    .exotic = &sWorldScriptsExoticMethods,
};

void InitOOJSWorldScripts(JSContext* context, JSValueConst global) {
  OOJSRegisterClass(&sWorldScriptsClassID, &sWorldScriptsClass);

  // As with JS_DefineObject() with a NULL prototype, the prototype is
  // Object.prototype.
  JSValue objectPrototype = OOJSObjectPrototype(context);
  JSValue worldScripts =
      JS_NewObjectProtoClass(context, objectPrototype, sWorldScriptsClassID);
  JS_FreeValue(context, objectPrototype);
  JS_DefinePropertyValueStr(context, global, "worldScripts", worldScripts,
                            OOJS_PROP_READONLY);
}

// Name of a world script for a string property ID, or nullopt for other IDs
// (symbols and integers).
static std::optional<std::string> ScriptNameForPropertyID(JSContext* context,
                                                          JSAtom propID) {
  std::optional<std::string> result;
  JSValue idValue = JS_AtomToValue(context, propID);
  if (JS_IsString(idValue)) {
    result = OOStringFromJSValue(context, idValue);
  }
  JS_FreeValue(context, idValue);
  return result;
}

static int WorldScriptsGetOwnProperty(JSContext* context,
                                      JSPropertyDescriptor* desc,
                                      JSValueConst object, JSAtom propID) {
  try {
    PlayerEntity* player = OOPlayerForScripting();
    std::optional<std::string> scriptName;
    OOScript* script = nullptr;

    scriptName = ScriptNameForPropertyID(context, propID);

    if (scriptName.has_value()) {
      script = nullptr;
      const auto worldScripts =
          (player != nullptr
               ? player->worldScriptsByName()
               : std::vector<std::pair<
                     std::string, std::shared_ptr<OOScript>>>());  // kept while
                                                                   // script is
                                                                   // used
      for (const auto& [name, scriptRef] :
           worldScripts)  // the last of a name, as the dictionary kept
      {
        if (name == *scriptName && scriptRef.get() != nullptr)
          script = scriptRef.get();
      }
      if (script != nullptr) {
        if (desc != nullptr) {
          /*	If script is an OOJSScript, this should return a JS Script
                  object. For other OOScript subclasses, it will return
                  null. If no script exists, the value will be
                  undefined.
          */
          desc->flags = OOJS_PROP_READONLY;
          desc->value = script->jsValueInContext(context);
          desc->getter = JS_UNDEFINED;
          desc->setter = JS_UNDEFINED;
        }
        return true;
      }
    }

    return false;
  } catch (...) {
    OOJSReportCurrentException(context);
    return -1;
  }
}

static int WorldScriptsGetOwnPropertyNames(JSContext* context,
                                           JSPropertyEnum** outTable,
                                           uint32_t* outCount,
                                           JSValueConst object) {
  /*	In order to support enumeration of world scripts (e.g.,
          for (name in worldScripts) { ... }), report each name.
          QuickJS frees the table and its atoms.
  */
  try {
    PlayerEntity* player = OOPlayerForScripting();
    const std::vector<std::string> names =
        (player != nullptr ? player->worldScriptNames()
                           : std::vector<std::string>());
    uint32_t i, count = static_cast<uint32_t>(names.size());

    JSPropertyEnum* table = static_cast<JSPropertyEnum*>(
        js_malloc(context, sizeof *table * MAX(count, 1U)));
    if (table == nullptr) return -1;

    for (i = 0; i < count; i++) {
      table[i].is_enumerable = true;
      table[i].atom = JS_NewAtom(context, names[i].c_str());
      if (table[i].atom == JS_ATOM_NULL) {
        JS_FreePropertyEnum(context, table, i);
        return -1;
      }
    }

    *outTable = table;
    *outCount = count;
    return 0;
  } catch (...) {
    OOJSReportCurrentException(context);
    return -1;
  }
}
