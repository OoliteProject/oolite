/*

OOJSClasses.m (QuickJS-ng)

JS class registration, subclass relationships, and SpiderMonkey-compatible
own properties for native classes.

Copyright (C) 2007-2013 David Taylor and Jens Ayton.

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

#include <algorithm>
#include <array>
#include <vector>

#include "OOJavaScriptEngine.h"

// Indexed by class ID; process lifetime, as are class IDs.
static const char* sClassNames[kOOJSMaxClassID];
static JSClassID sSuperclasses[kOOJSMaxClassID];

/*	Per class: the atoms of the getter/setter properties defined on its
        prototype by OOJSInitClass(), which SpiderMonkey reported as own
        properties of every instance (shared permanent properties), in
        definition order (as Object.keys() listed them) and sorted for lookup.
        Atoms are interned for the life of the process, like class IDs.

        Only the direct prototype's properties counted: for instance, a ship's
        Ship properties are own properties, but its Entity properties are not
        (checked against SpiderMonkey with tools/js-parity).
*/
struct SharedPropertyTable {
  std::vector<JSAtom> atoms;
  std::vector<JSAtom> sortedAtoms;
  bool recorded = false;
};

static std::array<SharedPropertyTable, kOOJSMaxClassID> sSharedProperties;

/*	Each class without exotic methods of its own gets its own, initially
        empty, JSClassExoticMethods; the hooks are only filled in when
        OOJSInitClass() records shared properties for it. Classes without
        accessor properties (Script, Timer...) therefore pay nothing on property
        lookups, which matters for Script objects: they are the with() scope of
        every script, so all bare identifier lookups pass through them.
*/
static std::array<JSClassExoticMethods, kOOJSMaxClassID> sExoticMethodStorage{};
static std::array<JSClassExoticMethods*, kOOJSMaxClassID> sOwnExoticMethods{};

JSClassID OOJSRegisterClass(JSClassID* ioClassID, const JSClassDef* classDef) {
  OOCParameterAssert(ioClassID != nullptr && classDef != nullptr);

  JSRuntime* runtime = JS_GetRuntime(OOJSAcquireContext());
  JSClassID classID = JS_NewClassID(runtime, ioClassID);
  OOCAssert(classID < kOOJSMaxClassID, "QuickJS class ID out of range.");

  if (!JS_IsRegisteredClass(runtime, classID)) {
    JSClassDef def = *classDef;
    if (def.exotic == nullptr) {
      sOwnExoticMethods[classID] = &sExoticMethodStorage[classID];
      def.exotic = sOwnExoticMethods[classID];
    }
    JS_NewClass(runtime, classID, &def);
    sClassNames[classID] = classDef->class_name;
  }
  return classID;
}

JSValue OOJSObjectPrototype(JSContext* context) {
  JSValue object = JS_NewObject(context);
  JSValue result = JS_GetPrototype(context, object);
  JS_FreeValue(context, object);
  return result;
}

const char* OOJSClassName(JSClassID classID) {
  return (classID < kOOJSMaxClassID) ? sClassNames[classID] : nullptr;
}

void OOJSRegisterSubclass(JSClassID subclass, JSClassID superclass) {
  OOCParameterAssert(subclass != 0 && superclass != 0 &&
                     subclass < kOOJSMaxClassID);
  OOCAssert(
      sSuperclasses[subclass] == 0 || sSuperclasses[subclass] == superclass,
      "A JS class cannot be registered as a subclass of multiple classes.");

  sSuperclasses[subclass] = superclass;
}

bool OOJSIsSubclass(JSClassID putativeSubclass, JSClassID superclass) {
  while (putativeSubclass != 0 && putativeSubclass < kOOJSMaxClassID) {
    if (putativeSubclass == superclass) return true;

    putativeSubclass = sSuperclasses[putativeSubclass];
  }

  return false;
}

static void RecordSharedProperties(JSContext* context, JSClassID classID,
                                   const JSCFunctionListEntry* properties,
                                   size_t count) {
  SharedPropertyTable* table = &sSharedProperties[classID];
  if (table->recorded || properties == nullptr) return;
  table->recorded = true;

  table->atoms.reserve(count);
  for (size_t i = 0; i < count; i++) {
    if (properties[i].def_type == JS_DEF_CGETSET ||
        properties[i].def_type == JS_DEF_CGETSET_MAGIC) {
      JSAtom atom = cxx_OOJSIDFromString(properties[i].name);

      // Some tables define a property twice (e.g. Ship's homeSystem); like
      // SpiderMonkey, keep the first.
      if (std::ranges::find(table->atoms, atom) == table->atoms.end())
        table->atoms.push_back(atom);
    }
  }
  table->sortedAtoms = table->atoms;
  std::ranges::sort(table->sortedAtoms);

  JSClassExoticMethods* exotic = sOwnExoticMethods[classID];
  if (exotic != nullptr && !table->atoms.empty()) {
    exotic->get_own_property = OOJSGetSharedPermanentOwnProperty;
    exotic->get_own_property_names = OOJSGetSharedPermanentOwnPropertyNames;
  }
}

static bool TableContainsAtom(const SharedPropertyTable* table, JSAtom atom) {
  return std::ranges::binary_search(table->sortedAtoms, atom);
}

/*	A property is a shared permanent property of an object if its class
        defines it on its prototype. The descriptor is the prototype's
        getter/setter pair, so reads and writes go through the native callbacks
        as before (a data descriptor would make QuickJS create a shadowing own
        property on assignment).
*/
int OOJSGetSharedPermanentOwnProperty(JSContext* context,
                                      JSPropertyDescriptor* desc,
                                      JSValueConst object, JSAtom prop) {
  JSClassID classID = JS_GetClassID(object);
  if (classID == 0 || classID >= kOOJSMaxClassID ||
      !TableContainsAtom(&sSharedProperties[classID], prop))
    return 0;

  JSValue prototype = JS_GetClassProto(context, classID);
  int result = 0;
  // The prototype holds the property in its own shape, so this does not
  // recurse.
  if (JS_IsObject(prototype) && !JS_IsStrictEqual(context, prototype, object))
    result = JS_GetOwnProperty(context, desc, prototype, prop);
  JS_FreeValue(context, prototype);
  return result;
}

int OOJSGetSharedPermanentOwnPropertyNames(JSContext* context,
                                           JSPropertyEnum** ptab,
                                           uint32_t* plen,
                                           JSValueConst object) {
  JSClassID classID = JS_GetClassID(object);
  const SharedPropertyTable* table = (classID != 0 && classID < kOOJSMaxClassID)
                                         ? &sSharedProperties[classID]
                                         : nullptr;
  uint32_t count =
      (table != nullptr) ? static_cast<uint32_t>(table->atoms.size()) : 0;

  // A class's own prototype gets its properties from its shape, not from here.
  JSValue prototype =
      (count != 0) ? JS_GetClassProto(context, classID) : JS_UNDEFINED;
  if (JS_IsStrictEqual(context, prototype, object)) count = 0;
  JS_FreeValue(context, prototype);

  JSPropertyEnum* tab = static_cast<JSPropertyEnum*>(
      js_malloc(context, sizeof(JSPropertyEnum) * (count ? count : 1)));
  if (tab == nullptr) return -1;

  for (uint32_t i = 0; i < count; i++) {
    tab[i].atom = JS_DupAtom(context, table->atoms[i]);
    tab[i].is_enumerable =
        false;  // Ignored; QuickJS asks get_own_property for flags.
  }

  *ptab = tab;
  *plen = count;
  return 0;
}

JSValueConst OOJSInitClass(JSContext* context, JSValueConst global,
                           JSClassID classID, JSValueConst parentPrototype,
                           JSCFunction* constructor, int constructorArgCount,
                           const JSCFunctionListEntry* properties,
                           size_t propertyCount,
                           const JSCFunctionListEntry* methods,
                           size_t methodCount,
                           const JSCFunctionListEntry* staticMethods,
                           size_t staticMethodCount) {
  JSValue prototype;
  if (JS_IsUndefined(parentPrototype)) {
    JSValue objectPrototype = OOJSObjectPrototype(context);
    prototype = JS_NewObjectProtoClass(context, objectPrototype, classID);
    JS_FreeValue(context, objectPrototype);
  } else {
    prototype = JS_NewObjectProtoClass(context, parentPrototype, classID);
  }

  if (properties != nullptr) {
    JS_SetPropertyFunctionList(context, prototype, properties,
                               static_cast<int>(propertyCount));
    RecordSharedProperties(context, classID, properties, propertyCount);
  }
  if (methods != nullptr)
    JS_SetPropertyFunctionList(context, prototype, methods,
                               static_cast<int>(methodCount));

  if (constructor != nullptr) {
    const char* name = OOJSClassName(classID);
    JSValue ctor =
        JS_NewCFunction2(context, constructor, name, constructorArgCount,
                         JS_CFUNC_constructor_or_func, 0);
    JS_SetConstructor(context, ctor, prototype);
    if (staticMethods != nullptr)
      JS_SetPropertyFunctionList(context, ctor, staticMethods,
                                 static_cast<int>(staticMethodCount));
    JS_DefinePropertyValueStr(context, global, name, ctor,
                              JS_PROP_WRITABLE | JS_PROP_CONFIGURABLE);
  }

  // The calls above don't report failures; don't leave an exception for the
  // next script to find.
  if (JS_HasException(context)) OOJSReportPendingException(context);

  // The context's class prototype table takes ownership, so the value stays
  // valid as a borrowed reference.
  JS_SetClassProto(context, classID, prototype);
  return prototype;
}
