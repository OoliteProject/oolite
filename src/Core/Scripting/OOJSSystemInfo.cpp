/*

OOJSSystemInfo.m (QuickJS-ng)

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

#include "OOJSSystemInfo.h"

#include <cstddef>
#include <cstdint>
#include <cstring>
#include <format>
#include <optional>
#include <set>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

#include "OOCommodities.h"
#include "OOConstToString.h"
#include "OODescription.h"
#include "OOIsNumberLiteral.h"
#include "OOJSScript.h"
#include "OOJSVector.h"
#include "OOJavaScriptEngine.h"
#include "OOSystemDescriptionManager.h"
#include "OOTypes.h"  // OOCreditsQuantity (samplePrice)
#include "PlayerEntityScriptMethods.h"
#include "Universe.h"
#include "oofnd/Notification.hpp"
#include "oofnd/PList.hpp"
#include "oofnd/String.hpp"
#include "oofnd/objc/OOAssert.h"

/*	SpiderMonkey implemented SystemInfo's dynamic per-system properties with
        class getProperty/setProperty/delProperty hooks and a
   JSCLASS_NEW_ENUMERATE enumerate hook. QuickJS equivalents are exotic methods
   on the class:

        * get_property: properties on the prototype chain (methods, the four
          fixed properties, Object.prototype) are found first, as SpiderMonkey
          only consulted the hook for names it could not otherwise find;
          anything else is looked up in the system data.
        * get_own_property / get_own_property_names: the system data keys are
          enumerable, so for..in, Object.keys(), Object.getOwnPropertyNames()
          and JSON.stringify() list exactly the system data keys, as the
          SpiderMonkey enumerate hook did; but, as in SpiderMonkey,
          hasOwnProperty() reports false for them. The fixed
          properties are own properties (OOJSGetSharedPermanentOwnProperty()),
          as in SpiderMonkey, but are not listed by any enumeration.
        * has_property: the in operator, and the check QuickJS-ng 0.17's for..in
          makes on each listed key, which drops any key it answers false for.
          It answers true for a system data key, so for..in lists them; the in
          operator therefore reports them too, where SpiderMonkey reported
          false. Otherwise it answers as QuickJS would without the hook: own
          (fixed) properties, then the prototype chain.
        * set_property: assignments to names that are not read-only or
          accessors on the prototype chain are stored (as strings) in the
          system data, like the SpiderMonkey setProperty hook. SpiderMonkey also
          added a shadowing own slot property; reads go to the system data
          instead, except that a key assigned null reads back as null.
        * delete_property: removes the key from the system data, like the
          SpiderMonkey delProperty hook.

        The fixed properties (coordinates etc.) are not enumerable, because the
        SpiderMonkey enumerate hook never listed them.
*/
/*
        The private slot holds the C++ system info itself (OOSystemInfo,
        declared in OOJSSystemInfo.h), which implements OOJSPrivateObject: the
        natives read it with OOJSGetCxxPrivate, the finalizer and toString() are
        the engine's OOJSCxxObjectWrapperFinalize and
        OOJSCxxObjectWrapperToString, and the converter answers the object
        itself, as a oo::PListForeign. The natives null-guard where a message to
        nil answered.
*/

// The running script's manifest property; null for no script, or once a script
// a timer or definition pushed weakly has gone, as the message to nil answered.
namespace {
oo::PList RunningScriptManifest() {
  OOJSScript* running = OOJSScript::currentlyRunningScript();
  return running != nullptr ? running->propertyNamed(kLocalManifestProperty)
                            : oo::PList();
}
}  // namespace

static JSClassID sSystemInfoClassID;

/*	The most recently created SystemInfo object. SpiderMonkey's cache was a
        weak reference, but its lazy garbage collector kept the object alive for
        a while, so successive system.info reads in a script usually got the
   same object. With reference counting the object would die at the end of each
        statement, so the cache holds a reference, released when another system
        is requested and when the JavaScript engine is reset. Zero-filled until
        first use, so always test with JS_IsObject().
*/
static JSValue sCachedSystemInfo;
static OOGalaxyID sCachedGalaxy;
static OOSystemID sCachedSystem;

static JSValue SystemInfoGetProperty(OOJS_GETTER_ARGS);
static void SystemInfoFinalize(JSRuntime* runtime, JSValueConst thisObj);

static int SystemInfoExoticGetOwnProperty(JSContext* context,
                                          JSPropertyDescriptor* desc,
                                          JSValueConst obj, JSAtom prop);
static int SystemInfoExoticGetOwnPropertyNames(JSContext* context,
                                               JSPropertyEnum** ptab,
                                               uint32_t* plen,
                                               JSValueConst obj);
static int SystemInfoExoticDeleteProperty(JSContext* context, JSValueConst obj,
                                          JSAtom prop);
static int SystemInfoExoticHasProperty(JSContext* context, JSValueConst obj,
                                       JSAtom prop);
static JSValue SystemInfoExoticGetProperty(JSContext* context, JSValueConst obj,
                                           JSAtom prop, JSValueConst receiver);
static int SystemInfoExoticSetProperty(JSContext* context, JSValueConst obj,
                                       JSAtom prop, JSValueConst value,
                                       JSValueConst receiver, int flags);

static JSValue SystemInfoToString(OOJS_NATIVE_ARGS);
static JSValue SystemInfoDistanceToSystem(OOJS_NATIVE_ARGS);
static JSValue SystemInfoRouteToSystem(OOJS_NATIVE_ARGS);
static JSValue SystemInfoSamplePrice(OOJS_NATIVE_ARGS);
static JSValue SystemInfoSetPropertyMethod(OOJS_NATIVE_ARGS);

static JSValue SystemInfoStaticSetInterstellarProperty(OOJS_NATIVE_ARGS);
static JSValue SystemInfoStaticFilteredSystems(OOJS_NATIVE_ARGS);

static JSClassExoticMethods sSystemInfoExoticMethods = {
    .get_own_property = SystemInfoExoticGetOwnProperty,
    .get_own_property_names = SystemInfoExoticGetOwnPropertyNames,
    .delete_property = SystemInfoExoticDeleteProperty,
    .has_property = SystemInfoExoticHasProperty,
    .get_property = SystemInfoExoticGetProperty,
    .set_property = SystemInfoExoticSetProperty,
};

static JSClassDef sSystemInfoClass = {
    .class_name = "SystemInfo",
    .finalizer = SystemInfoFinalize,
    .exotic = &sSystemInfoExoticMethods,
};

namespace {

enum class SystemInfoProperty : std::int16_t {
  // Property IDs
  kCoordinates,          // system coordinates (in LY), Vector3D (with z =
                         // 0), read-only
  kInternalCoordinates,  // system coordinates (unscaled), Vector3D
                         // (with z = 0), read-only
  kGalaxyID,             // galaxy number, integer, read-only
  kSystemID              // system number, integer, read-only
};

}  // namespace

static const JSCFunctionListEntry sSystemInfoProperties[] = {
    // JS name, getter, setter, ID, flags (hidden: see comment at top of file)
    JS_CGETSET_MAGIC_DEF2("coordinates", SystemInfoGetProperty, nullptr,
                          OOJSPropertyMagic(SystemInfoProperty::kCoordinates),
                          OOJS_PROP_HIDDEN_READONLY_CB),
    JS_CGETSET_MAGIC_DEF2(
        "internalCoordinates", SystemInfoGetProperty, nullptr,
        OOJSPropertyMagic(SystemInfoProperty::kInternalCoordinates),
        OOJS_PROP_HIDDEN_READONLY_CB),
    JS_CGETSET_MAGIC_DEF2("galaxyID", SystemInfoGetProperty, nullptr,
                          OOJSPropertyMagic(SystemInfoProperty::kGalaxyID),
                          OOJS_PROP_HIDDEN_READONLY_CB),
    JS_CGETSET_MAGIC_DEF2("systemID", SystemInfoGetProperty, nullptr,
                          OOJSPropertyMagic(SystemInfoProperty::kSystemID),
                          OOJS_PROP_HIDDEN_READONLY_CB),
};

static const JSCFunctionListEntry sSystemInfoMethods[] = {
    // JS name, min args, function
    JS_CFUNC_DEF("toString", 0, SystemInfoToString),
    JS_CFUNC_DEF("distanceToSystem", 1, SystemInfoDistanceToSystem),
    JS_CFUNC_DEF("routeToSystem", 1, SystemInfoRouteToSystem),
    JS_CFUNC_DEF("samplePrice", 1, SystemInfoSamplePrice),
    JS_CFUNC_DEF("setProperty", 3, SystemInfoSetPropertyMethod),
};

static const JSCFunctionListEntry sSystemInfoStaticMethods[] = {
    // JS name, min args, function
    JS_CFUNC_DEF("filteredSystems", 2, SystemInfoStaticFilteredSystems),
    JS_CFUNC_DEF("setInterstellarProperty", 4,
                 SystemInfoStaticSetInterstellarProperty),
};

namespace {

// A string, or null for none.
oo::PList StringOrNull(const std::optional<std::string>& string) {
  return string.has_value() ? oo::PList(*string) : oo::PList();
}

// A manifest identifier as the -fromManifest: arguments read it: a string, else
// none.
std::optional<std::string> ManifestString(const oo::PList& manifest) {
  if (const std::string* text = manifest.getIf<std::string>()) return *text;
  return std::nullopt;
}

// What a message to a nil OOSystemInfo answered, for the natives that take one
// from a JS object (the prototype has none): 0, the zero point, null.
OOGalaxyID GalaxyOf(OOSystemInfo* info) {
  return (info != nullptr) ? info->galaxy() : 0;
}
OOSystemID SystemOf(OOSystemInfo* info) {
  return (info != nullptr) ? info->system() : 0;
}
NSPoint CoordinatesOf(OOSystemInfo* info) {
  return (info != nullptr) ? info->coordinates() : NSMakePoint(0, 0);
}
oo::PList ValueForKey(OOSystemInfo* info,
                      const std::optional<std::string>& key) {
  return (info != nullptr) ? info->valueForKey(key) : oo::PList();
}

// The integer value of a system property (a number or a string; 0 for none).
int PropertyIntValue(const oo::PList& value) {
  if (const std::string* text = value.getIf<std::string>())
    return oo::plist_get::intValue(oo::utf8ToUtf16(*text));
  return static_cast<int>(value.int64Value());
}

}  // namespace

// DEFINE_JS_OBJECT_GETTER(JSSystemInfoGetSystemInfo, sSystemInfoClassID,
// OOSystemInfo) for the C++ system info the slot holds.
static bool JSSystemInfoGetSystemInfo(JSContext* context, JSValueConst inObject,
                                      OOSystemInfo** outObject) {
  return OOJSGetCxxPrivate(context, inObject, sSystemInfoClassID, outObject);
}

// The system info of an instance, else null: the prototype, or an object of
// another class (it answers null).
static OOSystemInfo* SystemInfoForObject(JSValueConst obj) {
  return static_cast<OOSystemInfo*>(
      static_cast<oo::RefCounted*>(JS_GetOpaque(obj, sSystemInfoClassID)));
}

// OOSystemInfo (OOJSSystemInfo.h), the helper class wrapped by JS SystemInfo
// objects.

OOSystemInfo::OOSystemInfo(OOGalaxyID galaxy, OOSystemID system)
    : _galaxy(galaxy),
      _system(system),
      _planetKey(std::format("{} {}", galaxy, system)) {}

oo::Ref<OOSystemInfo> OOSystemInfo::initWithGalaxy(OOGalaxyID galaxy,
                                                   OOSystemID system) {
  if (galaxy > kOOMaximumGalaxyID || system > kOOMaximumSystemID ||
      system < kOOMinimumSystemID) {
    return nullptr;
  }

  return oo::adopt(new OOSystemInfo(galaxy, system));
}

void OOSystemInfo::setNullAssigned(bool flag, const std::string& key) {
  if (flag) {
    _nullAssignedKeys.insert(key);
  } else {
    _nullAssignedKeys.erase(key);
  }
}

bool OOSystemInfo::isNullAssignedForKey(const std::string& key) const {
  return _nullAssignedKeys.count(key) != 0;
}

std::optional<std::string> OOSystemInfo::descriptionComponents() const {
  return std::format("galaxy {}, system {}", _galaxy, _system);
}

std::optional<std::string> OOSystemInfo::shortDescriptionComponents() const {
  return _planetKey;
}

std::optional<std::string> OOSystemInfo::oo_jsClassName() const {
  return std::string("SystemInfo");
}

bool OOSystemInfo::isEqual(const OOSystemInfo* other) const {
  return other == this || (other != nullptr && other->galaxy() == _galaxy &&
                           other->system() == _system);
}

std::size_t OOSystemInfo::hash() const {
  std::size_t hash = _galaxy;
  hash <<= 16;
  hash |= (uint16_t)_system;
  return hash;
}

oo::PList OOSystemInfo::valueForKey(const std::optional<std::string>& key) {
  if ((UNIVERSE != nullptr ? UNIVERSE->inInterstellarSpace() : false) &&
      _system == -1) {
    // -objectForKey: (a nil key found nothing)
    const oo::PList systemData =
        (UNIVERSE != nullptr ? UNIVERSE->currentSystemData() : oo::PList());
    const oo::PList* value = key.has_value() ? systemData.find(*key) : nullptr;
    return (value != nullptr) ? *value : oo::PList();
  }
  return (UNIVERSE != nullptr ? UNIVERSE->systemDataForGalaxy(_galaxy, _system,
                                                              key.value_or(""))
                              : oo::PList());  // (a nil key as "")
}

void OOSystemInfo::setValue(const oo::PList& value, const std::string& key) {
  // The running script's manifest identifier, handed on as it was read.
  const oo::PList manifest = RunningScriptManifest();

  if (UNIVERSE != nullptr)
    UNIVERSE->setSystemDataForGalaxy(_galaxy, _system, key, value,
                                     ManifestString(manifest),
                                     OO_LAYER_OXP_DYNAMIC);
}

std::vector<std::string> OOSystemInfo::allKeys() {
  if ((UNIVERSE != nullptr ? UNIVERSE->inInterstellarSpace() : false) &&
      _system == -1) {
    // the dictionary's keys, in key order (-allKeys gave hash order)
    std::vector<std::string> keys;
    // -cxx_currentSystemData answers a copy: keep it alive while the loop reads
    // it.
    const oo::PList systemData =
        (UNIVERSE != nullptr ? UNIVERSE->currentSystemData() : oo::PList());
    if (const oo::PList::Dict* systemDict =
            systemData.getIf<oo::PList::Dict>()) {
      for (const auto& entry : *systemDict) keys.push_back(entry.first);
    }
    return keys;
  }
  return (UNIVERSE != nullptr
              ? UNIVERSE->systemDataKeysForGalaxy(_galaxy, _system)
              : std::vector<std::string>());
}

OOGalaxyID OOSystemInfo::galaxy() const { return _galaxy; }

OOSystemID OOSystemInfo::system() const { return _system; }

/*- (Random_Seed) systemSeed
{
        OOAssert([PLAYER currentGalaxyID] == _galaxy, "Attempt to use
-[OOSystemInfo systemSeed] from a different galaxy."); return [UNIVERSE
systemSeedForSystemNumber:_system];
        }*/

NSPoint OOSystemInfo::coordinates() {
  if ((UNIVERSE != nullptr ? UNIVERSE->inInterstellarSpace() : false) &&
      _system == -1) {
    return (PLAYER != nullptr
                ? PLAYER->PlayerEntity::getGalaxy_coordinates()
                : NSPoint{});  // qualified: the final overrider, so the binding
                               // test stands in for it
  }
  return (UNIVERSE != nullptr ? UNIVERSE->coordinatesForSystem(_system)
                              : NSPoint{});
}

JSValue OOSystemInfo::jsValueInContext(JSContext* context) {
  JSValue result = JS_NewObjectClass(context, (int)sSystemInfoClassID);
  if (JS_IsException(result)) {
    JS_FreeValue(context, JS_GetException(context));
    return JS_NULL;
  }
  // The slot holds this, retained (OOJSCxxObjectWrapperFinalize releases it).
  if (!OOJSSetCxxPrivate(result, this)) {
    JS_FreeValue(context, result);
    return JS_NULL;
  }

  return result;
}

void OOSystemInfo::clearJSSelf(JSValueConst /*selfVal*/) {
  // No wrapper is remembered: each jsValueInContext() makes a new one.
}

// The JS class name and the components.
std::string OOSystemInfo::className() const { return "OOSystemInfo"; }

std::string OOSystemInfo::description() const {
  const std::optional<std::string> components = descriptionComponents();
  return std::format("<OOSystemInfo>{{{}}}", components.value_or(""));
}

std::optional<std::string> OOSystemInfo::jsDescription() {
  const std::optional<std::string> components = descriptionComponents();
  const std::string name = oo_jsClassName().value_or("OOSystemInfo");
  if (components.has_value()) return std::format("[{} {}]", name, *components);
  return std::format("[object {}]", name);
}

// OOJSBasicPrivateObjectConverter for the C++ system info the slot holds: the
// object itself as a PList::Object node (null for the prototype).
static oo::PList SystemInfoConverter(JSContext* /*context*/,
                                     JSValueConst object) {
  OOSystemInfo* info = SystemInfoForObject(object);
  if (info == nullptr) return oo::PList();
  return oo::PList(oo::PList::Object(oo::Ref<oo::PListForeign>(info)));
}

// Drop the cached SystemInfo object.
static void SystemInfoJavaScriptEngineWillReset() {
  JSValue oldCache = sCachedSystemInfo;
  sCachedSystemInfo = JS_UNDEFINED;
  if (JS_IsObject(oldCache)) JS_FreeValue(OOJSAcquireContext(), oldCache);
}

void InitOOJSSystemInfo(JSContext* context, JSValueConst global) {
  static bool observing = false;
  if (!observing) {
    // Process lifetime, as the class registration.
    oo::NotificationCenter::defaultCenter().addObserver(
        nullptr, kOOJavaScriptEngineWillResetNotificationName, nullptr,
        [](const oo::Notification&) { SystemInfoJavaScriptEngineWillReset(); });
    observing = true;
  }
  sCachedSystemInfo = JS_UNDEFINED;

  OOJSRegisterClass(&sSystemInfoClassID, &sSystemInfoClass);
  OOJSInitClass(context, global, sSystemInfoClassID, JS_UNDEFINED,
                OOJSUnconstructableConstruct, 0, sSystemInfoProperties,
                OOJS_COUNT(sSystemInfoProperties), sSystemInfoMethods,
                OOJS_COUNT(sSystemInfoMethods), sSystemInfoStaticMethods,
                OOJS_COUNT(sSystemInfoStaticMethods));
  OOJSRegisterObjectConverter(sSystemInfoClassID, SystemInfoConverter);
}

JSValue GetJSSystemInfoForSystem(JSContext* context, OOGalaxyID galaxy,
                                 OOSystemID system) {
  OOJS_PROFILE_ENTER

  // Use cached object if possible.
  if (JS_IsObject(sCachedSystemInfo) && sCachedGalaxy == galaxy &&
      sCachedSystem == system) {
    return JS_DupValue(context, sCachedSystemInfo);
  }

  // If not, create a new one.
  oo::Ref<OOSystemInfo> info;
  JSValue result;
  OOJS_BEGIN_FULL_NATIVE(context)
  info = OOSystemInfo::initWithGalaxy(
      galaxy, system);  // null for a galaxy or system out of range
  OOJS_END_FULL_NATIVE

  if (EXPECT_NOT(info == nullptr)) {
    cxx_OOJSReportWarning(
        context,
        "Could not create system info object for galaxy %u, system %i.", galaxy,
        system);
  }

  result = OOJSValueFromCxxObject(context, info.get());

  // Replace the cached object. (Freeing it may run SystemInfoFinalize(), which
  // clears the cache.)
  JSValue oldCache = sCachedSystemInfo;
  sCachedSystemInfo = JS_UNDEFINED;
  if (JS_IsObject(oldCache)) JS_FreeValue(context, oldCache);
  sCachedSystemInfo =
      JS_IsObject(result) ? JS_DupValue(context, result) : JS_UNDEFINED;
  sCachedGalaxy = galaxy;
  sCachedSystem = system;

  return result;

  OOJS_PROFILE_EXIT
}

static JSValue SystemInfoToString(OOJS_NATIVE_ARGS) {
  (void)argc;
  (void)OOJS_ARGV;
  return OOJSCxxObjectWrapperToString(context, OOJS_THIS, sSystemInfoClassID);
}

static void SystemInfoFinalize(JSRuntime* runtime, JSValueConst thisObj) {
  OOJS_PROFILE_ENTER

  // Clear now-stale cache entry if appropriate.
  if (JS_IsObject(sCachedSystemInfo) &&
      JS_VALUE_GET_PTR(sCachedSystemInfo) == JS_VALUE_GET_PTR(thisObj)) {
    sCachedSystemInfo = JS_UNDEFINED;
  }

  OOJSCxxObjectWrapperFinalize(
      runtime, thisObj);  // clearJSSelf(), the slot's release, the empty slot

  OOJS_PROFILE_EXIT_VOID
}

// *** Exotic property behaviour (replaces SpiderMonkey class hooks) ***

/*	Exotic methods are called from inside QuickJS, so native exceptions must
        not escape them. These bracket the body of each one, converting an
        exception into a JS error.
*/
#define OOJS_EXOTIC_ENTER try {
#define OOJS_EXOTIC_EXIT(context, failure) \
  }                                        \
  catch (...) {                            \
    OOJSReportCurrentException(context);   \
    return (failure);                      \
  }

// The key for a string property, or nullopt for symbols.
static std::optional<std::string> SystemInfoKeyForAtom(JSContext* context,
                                                       JSAtom prop) {
  std::optional<std::string> key;
  JSValue propValue = JS_AtomToValue(context, prop);
  if (JS_IsString(propValue)) {
    key = cxx_OOStringFromJSValue(context, propValue);
  }
  JS_FreeValue(context, propValue);
  return key;
}

/*	Look up a system data value, as the string-ID branch of the SpiderMonkey
        SystemInfoGetProperty() did. Returns true and an owned *outValue if the
   key exists, false otherwise (or on exception, which is then pending and
        *outValue is JS_EXCEPTION).
*/
static bool SystemInfoGetSystemDataValue(JSContext* context, OOSystemInfo* info,
                                         const std::string& key,
                                         JSValue* outValue) {
  *outValue = JS_UNDEFINED;

  OOSystemDescriptionManager* systemManager =
      (UNIVERSE != nullptr ? UNIVERSE->getSystemManager() : nullptr);
  oo::PList propValue;
  // interstellar space needs more work at this stage
  if (info->system() != -1) {
    propValue =
        (systemManager != nullptr)
            ? systemManager->getProperty(key, info->system(), info->galaxy())
            : oo::PList();  // (null from a message to nil)
  } else {
    propValue = info->valueForKey(key);
  }

  if (propValue.isNull()) return false;

  if (propValue.isNumber() ||
      OOIsNumberLiteral(oo::DescriptionOf(propValue), true)) {
    // A number's value, or a string's (a number literal)
    const std::string* text = propValue.getIf<std::string>();
    const double number =
        (text != nullptr) ? oo::plist_get::doubleValue(oo::utf8ToUtf16(*text))
                          : propValue.doubleValue();
    *outValue = JS_NewNumber(context, number);
  } else {
    *outValue = OOJSValueFromPList(
        context, propValue);  // non-null: as its own glue gave
  }
  return true;
}

/*	Ordinary [[Set]] on the prototype chain of obj (whose own properties
   have already been checked by QuickJS). If an accessor or read-only property
   is found, it is handled and *outHandled is set; the return value is then the
        set_property result. Otherwise *outHandled is false and the caller
   decides where the value goes.
*/
static int SystemInfoSetOnPrototypeChain(JSContext* context, JSValueConst obj,
                                         JSAtom prop, JSValueConst value,
                                         JSValueConst receiver, int flags,
                                         bool* outHandled) {
  JSValue proto = JS_GetPrototype(context, obj);
  *outHandled = true;

  while (JS_IsObject(proto)) {
    JSPropertyDescriptor desc;
    int found = JS_GetOwnProperty(context, &desc, proto, prop);
    if (found < 0) {
      JS_FreeValue(context, proto);
      return -1;
    }
    if (found) {
      JS_FreeValue(context, proto);
      if (desc.flags & JS_PROP_GETSET) {
        JS_FreeValue(context, desc.getter);
        if (JS_IsUndefined(desc.setter)) goto readOnly;
        JSValue result = JS_Call(context, desc.setter, receiver, 1, &value);
        JS_FreeValue(context, desc.setter);
        if (JS_IsException(result)) return -1;
        JS_FreeValue(context, result);
        return true;
      }
      JS_FreeValue(context, desc.value);
      if (!(desc.flags & JS_PROP_WRITABLE)) goto readOnly;
      *outHandled = false;
      return true;
    }

    JSValue next = JS_GetPrototype(context, proto);
    JS_FreeValue(context, proto);
    proto = next;
  }

  if (JS_IsException(proto)) return -1;
  JS_FreeValue(context, proto);
  *outHandled = false;
  return true;

readOnly:
  /*	QuickJS does not expose whether the calling code is strict, so
          assignments to read-only properties are ignored except when the
          caller explicitly asks for an exception (JS_PROP_THROW).
  */
  if (flags & JS_PROP_THROW) {
    JSValue propName = JS_AtomToString(context, prop);
    const char* name = JS_ToCString(context, propName);
    JS_ThrowTypeError(context, "'%s' is read-only", name ? name : "?");
    JS_FreeCString(context, name);
    JS_FreeValue(context, propName);
    return -1;
  }
  return false;
}

static int SystemInfoExoticGetOwnProperty(JSContext* context,
                                          JSPropertyDescriptor* desc,
                                          JSValueConst obj, JSAtom prop) {
  OOJS_EXOTIC_ENTER

  OOSystemInfo* info = SystemInfoForObject(obj);
  std::optional<std::string> key =
      (info != nullptr) ? SystemInfoKeyForAtom(context, prop) : std::nullopt;
  JSValue value;

  /*	SpiderMonkey reported the fixed (shared permanent) properties as own
          properties, so they win over system data keys of the same name
          (notably "coordinates"). They are hidden, but a name that is also a
          system data key is reported as enumerable, since the SpiderMonkey
          enumerate hook listed every system data key.
  */
  int shared = OOJSGetSharedPermanentOwnProperty(context, desc, obj, prop);
  if (shared != 0) {
    if (shared > 0 && desc != nullptr && key.has_value()) {
      if (SystemInfoGetSystemDataValue(context, info, *key, &value)) {
        if (JS_IsException(value)) {
          JS_FreeValue(context, desc->getter);
          JS_FreeValue(context, desc->setter);
          JS_FreeValue(context, desc->value);
          return -1;
        }
        JS_FreeValue(context, value);
        desc->flags |= JS_PROP_ENUMERABLE;
      }
    }
    return shared;
  }

  if (!key.has_value())
    return false;  // Prototype (no dynamic properties) or symbol.

  /*	SpiderMonkey's resolve hook made system data keys enumerable (for..in
     and Object.keys() list them) but not own properties: hasOwnProperty()
          returned false. QuickJS asks this hook without a descriptor for
          hasOwnProperty(), and with one when collecting enumerable keys, so
          answer accordingly. (The in operator and for..in ask
          SystemInfoExoticHasProperty() instead.)
  */
  if (desc == nullptr) return false;

  if (!SystemInfoGetSystemDataValue(context, info, *key, &value)) {
    return false;
  }
  if (JS_IsException(value)) return -1;

  if (desc != nullptr) {
    desc->flags = JS_PROP_C_W_E;
    desc->value = value;
    desc->getter = JS_UNDEFINED;
    desc->setter = JS_UNDEFINED;
  } else {
    JS_FreeValue(context, value);
  }
  return true;

  OOJS_EXOTIC_EXIT(context, -1)
}

static int SystemInfoExoticGetOwnPropertyNames(JSContext* context,
                                               JSPropertyEnum** ptab,
                                               uint32_t* plen,
                                               JSValueConst obj) {
  OOJS_EXOTIC_ENTER

  *ptab = nullptr;
  *plen = 0;

  OOSystemInfo* info = SystemInfoForObject(obj);
  const std::vector<std::string> keys =
      (info != nullptr)
          ? info->allKeys()
          : std::vector<std::string>();  // (none from a message to nil)
  std::size_t count = keys.size();
  assert(count <= INT32_MAX);

  JSPropertyEnum* tab =
      (JSPropertyEnum*)js_mallocz(context, sizeof *tab * (count + 1));
  if (tab == nullptr) return -1;

  // System data keys (all enumerable; the SpiderMonkey enumerate hook listed
  // exactly these).
  uint32_t i = 0;
  for (const std::string& key : keys) {
    JSAtom atom = JS_NewAtom(context, key.c_str());
    if (atom == JS_ATOM_NULL) {
      JS_FreePropertyEnum(context, tab, i);
      return -1;
    }
    tab[i].atom = atom;
    tab[i].is_enumerable = true;
    i++;
  }

  /*	Only the system data keys, as SpiderMonkey's JSCLASS_NEW_ENUMERATE hook
          listed: the fixed properties (galaxyID...) are not named, although
          hasOwnProperty() reports them, as before.
  */
  *ptab = tab;
  *plen = i;
  return 0;

  OOJS_EXOTIC_EXIT(context, -1)
}

static int SystemInfoExoticDeleteProperty(JSContext* context, JSValueConst obj,
                                          JSAtom prop) {
  OOJS_EXOTIC_ENTER

  // SpiderMonkey version: set the property to undefined (which removes it).
  OOSystemInfo* info = SystemInfoForObject(obj);
  std::optional<std::string> key = SystemInfoKeyForAtom(context, prop);
  if (info != nullptr && key.has_value()) {
    info->setValue(oo::PList(), *key);
  }
  return true;

  OOJS_EXOTIC_EXIT(context, -1)
}

static int SystemInfoExoticHasProperty(JSContext* context, JSValueConst obj,
                                       JSAtom prop) {
  OOJS_EXOTIC_ENTER

  // Ordinary own properties (the prototype's methods), then the exotic hook.
  int own = JS_GetOwnProperty(context, nullptr, obj, prop);
  if (own != 0) return own;

  OOSystemInfo* info = SystemInfoForObject(obj);
  std::optional<std::string> key =
      (info != nullptr) ? SystemInfoKeyForAtom(context, prop) : std::nullopt;
  if (key.has_value()) {
    JSValue value;
    if (SystemInfoGetSystemDataValue(context, info, *key, &value)) {
      if (JS_IsException(value)) return -1;
      JS_FreeValue(context, value);
      return true;
    }
  }

  JSValue proto = JS_GetPrototype(context, obj);
  if (JS_IsException(proto)) return -1;
  int found = JS_HasProperty(context, proto, prop);  // false for null
  JS_FreeValue(context, proto);
  return found;

  OOJS_EXOTIC_EXIT(context, -1)
}

static JSValue SystemInfoExoticGetProperty(JSContext* context, JSValueConst obj,
                                           JSAtom prop, JSValueConst receiver) {
  OOJS_EXOTIC_ENTER

  // Prototype chain first: SpiderMonkey only used the hook for otherwise
  // unknown names.
  JSValue proto = JS_GetPrototype(context, obj);
  while (JS_IsObject(proto)) {
    JSPropertyDescriptor desc;
    int found = JS_GetOwnProperty(context, &desc, proto, prop);
    if (found < 0) {
      JS_FreeValue(context, proto);
      return JS_EXCEPTION;
    }
    if (found) {
      JS_FreeValue(context, proto);
      if (desc.flags & JS_PROP_GETSET) {
        JSValue result = JS_UNDEFINED;
        JS_FreeValue(context, desc.setter);
        if (JS_IsFunction(context, desc.getter)) {
          result = JS_Call(context, desc.getter, receiver, 0, nullptr);
        }
        JS_FreeValue(context, desc.getter);
        return result;
      }
      return desc.value;
    }

    JSValue next = JS_GetPrototype(context, proto);
    JS_FreeValue(context, proto);
    proto = next;
  }
  if (JS_IsException(proto)) return JS_EXCEPTION;
  JS_FreeValue(context, proto);

  OOSystemInfo* info = SystemInfoForObject(obj);
  if (info == nullptr) {
    // Let QuickJS behave normally for the prototype object (where info will be
    // nil).
    return JS_UNDEFINED;
  }

  std::optional<std::string> key = SystemInfoKeyForAtom(context, prop);
  if (!key.has_value()) return JS_UNDEFINED;

  JSValue value;
  if (!SystemInfoGetSystemDataValue(context, info, *key, &value) &&
      info->isNullAssignedForKey(*key))
    return JS_NULL;
  return value;

  OOJS_EXOTIC_EXIT(context, JS_EXCEPTION)
}

static int SystemInfoExoticSetProperty(JSContext* context, JSValueConst obj,
                                       JSAtom prop, JSValueConst value,
                                       JSValueConst receiver, int flags) {
  OOJS_EXOTIC_ENTER

  bool handled;
  int result = SystemInfoSetOnPrototypeChain(context, obj, prop, value,
                                             receiver, flags, &handled);
  if (handled) return result;

  OOSystemInfo* info = SystemInfoForObject(obj);
  std::optional<std::string> key = SystemInfoKeyForAtom(context, prop);
  if (info == nullptr || !key.has_value() || !JS_IsObject(receiver) ||
      JS_VALUE_GET_PTR(receiver) != JS_VALUE_GET_PTR(obj)) {
    // Ordinary property (prototype object, symbol, or inherited by another
    // object).
    return JS_DefinePropertyValue(context, receiver, prop,
                                  JS_DupValue(context, value), JS_PROP_C_W_E);
  }

  /*	Assigning null removes the system data key. SpiderMonkey also stored the
          value in the object's own slot, so reading the key back gave null;
          remember such keys to do the same.
  */
  info->setValue(StringOrNull(cxx_OOStringFromJSValue(context, value)), *key);
  info->setNullAssigned(JS_IsNull(value), *key);
  return true;

  OOJS_EXOTIC_EXIT(context, -1)
}

// *** Fixed properties ***

static JSValue SystemInfoGetProperty(OOJS_GETTER_ARGS) {
  OOJS_NATIVE_ENTER(context)

  OOSystemInfo* info = SystemInfoForObject(thisObj);
  if (info == nullptr) {
    // Let QuickJS handle access to the prototype object (where info will be
    // nil).
    return JS_UNDEFINED;
  }

  // What if we're trying to access a saved witchspace systemInfo object?
  bool savedInterstellarInfo =
      !(UNIVERSE != nullptr ? UNIVERSE->inInterstellarSpace() : false) &&
      SystemOf(info) == -1;
  bool sameGalaxy = (PLAYER != nullptr ? PLAYER->PlayerEntity::currentGalaxyID()
                                       : OOGalaxyID{}) ==
                    GalaxyOf(info);  // qualified: the final overrider, so the
                                     // binding test stands in for it

  switch (static_cast<SystemInfoProperty>(magic)) {
    using enum SystemInfoProperty;
    case kCoordinates:
      if (sameGalaxy && !savedInterstellarInfo) {
        OOJS_RETURN_VECTOR(
            OOGalacticCoordinatesFromInternal(CoordinatesOf(info)));
      } else {
        cxx_OOJSReportError(
            context, "Cannot read systemInfo values for %s.",
            (savedInterstellarInfo ? "invalid interstellar space reference"
                                   : "other galaxies"));
        return OOJSNativeFailure(context);
      }
      break;

    case kInternalCoordinates:
      if (sameGalaxy && !savedInterstellarInfo) {
        OOJS_RETURN_WITH_HELPER(NSPointToVectorJSValue, CoordinatesOf(info));
      } else {
        cxx_OOJSReportError(
            context, "Cannot read systemInfo values for %s.",
            (savedInterstellarInfo ? "invalid interstellar space reference"
                                   : "other galaxies"));
        return OOJSNativeFailure(context);
      }
      break;

    case kGalaxyID:
      return JS_NewInt32(context, GalaxyOf(info));

    case kSystemID:
      return JS_NewInt32(context, SystemOf(info));

    default:
      OOJSReportBadPropertySelector(context, thisObj, magic,
                                    sSystemInfoProperties,
                                    OOJS_COUNT(sSystemInfoProperties));
      return OOJSNativeFailure(context);
  }

  OOJS_NATIVE_EXIT
}

// *** Methods ***

// distanceToSystem(sys : SystemInfo) : Number
static JSValue SystemInfoDistanceToSystem(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  OOSystemInfo* thisInfo = nullptr;
  OOSystemInfo* otherInfo = nullptr;

  if (!JSSystemInfoGetSystemInfo(context, OOJS_THIS, &thisInfo))
    return OOJSNativeFailure(context);
  // SpiderMonkey version used JS_ValueToObject(); a primitive can't be a
  // SystemInfo anyway.
  if (argc < 1 || !JS_IsObject(OOJS_ARGV[0]) ||
      !JSSystemInfoGetSystemInfo(context, OOJS_ARGV[0], &otherInfo)) {
    cxx_OOJSReportBadArguments(context, "SystemInfo", "distanceToSystem",
                               MIN(argc, 1), OOJS_ARGV, std::nullopt,
                               "system info");
    return OOJSNativeFailure(context);
  }

  bool sameGalaxy = (GalaxyOf(thisInfo) == GalaxyOf(otherInfo));
  if (!sameGalaxy) {
    cxx_OOJSReportErrorForCaller(
        context, "SystemInfo", "distanceToSystem",
        "Cannot calculate distance for systems in other galaxies.");
    return OOJSNativeFailure(context);
  }

  NSPoint thisCoord = CoordinatesOf(thisInfo);
  NSPoint otherCoord = CoordinatesOf(otherInfo);

  OOJS_RETURN_DOUBLE(distanceBetweenPlanetPositions(
      thisCoord.x, thisCoord.y, otherCoord.x, otherCoord.y));

  OOJS_NATIVE_EXIT
}

// routeToSystem(sys : SystemInfo [, optimizedBy : String]) : Object
static JSValue SystemInfoRouteToSystem(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  OOSystemInfo* thisInfo = nullptr;
  OOSystemInfo* otherInfo = nullptr;
  oo::PList result;
  OORouteType routeType = OORouteType::kJumps;

  if (!JSSystemInfoGetSystemInfo(context, OOJS_THIS, &thisInfo))
    return OOJSNativeFailure(context);
  if (argc < 1 || !JS_IsObject(OOJS_ARGV[0]) ||
      !JSSystemInfoGetSystemInfo(context, OOJS_ARGV[0], &otherInfo)) {
    cxx_OOJSReportBadArguments(context, "SystemInfo", "routeToSystem",
                               MIN(argc, 1), OOJS_ARGV, std::nullopt,
                               "system info");
    return OOJSNativeFailure(context);
  }

  bool sameGalaxy = (GalaxyOf(thisInfo) == GalaxyOf(otherInfo));
  if (!sameGalaxy) {
    cxx_OOJSReportErrorForCaller(
        context, "SystemInfo", "routeToSystem",
        "Cannot calculate route for destinations in other galaxies.");
    return OOJSNativeFailure(context);
  }

  if (argc >= 2) {
    routeType = cxx_StringToRouteType(
        cxx_OOStringFromJSValue(context, OOJS_ARGV[1]).value_or(""));
  }

  OOJS_BEGIN_FULL_NATIVE(context)
  result = (UNIVERSE != nullptr
                ? UNIVERSE->routeFromSystem(SystemOf(thisInfo),
                                            SystemOf(otherInfo), routeType)
                : oo::PList());
  OOJS_END_FULL_NATIVE

  OOJS_RETURN_PLIST(result);

  OOJS_NATIVE_EXIT
}

// samplePrice(commodity)
static JSValue SystemInfoSamplePrice(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  OOSystemInfo* thisInfo = nullptr;

  if (!JSSystemInfoGetSystemInfo(context, OOJS_THIS, &thisInfo))
    return OOJSNativeFailure(context);
  OOCommodities* commodities =
      (UNIVERSE != nullptr
           ? UNIVERSE->getCommodities()
           : nullptr);  // null: no good is defined, as a message to nil
  std::optional<std::string> commodity =
      cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
  if (EXPECT_NOT(commodities == nullptr ||
                 !commodities->goodDefined(commodity.value_or("")))) {
    cxx_OOJSReportBadArguments(context, "SystemInfo", "samplePrice",
                               MIN(argc, 1), OOJS_ARGV, std::nullopt,
                               "Unrecognised commodity type");
    return OOJSNativeFailure(context);
  }

  bool sameGalaxy =
      (GalaxyOf(thisInfo) ==
       (PLAYER != nullptr
            ? PLAYER->PlayerEntity::galaxyNumber()
            : OOGalaxyID{}));  // qualified: the final overrider, so the binding
                               // test stands in for it
  if (!sameGalaxy) {
    cxx_OOJSReportErrorForCaller(
        context, "SystemInfo", "samplePrice",
        "Cannot calculate sample price for destinations in other galaxies.");
    return OOJSNativeFailure(context);
  }

  int economy = PropertyIntValue(ValueForKey(
      thisInfo,
      std::string("economy")));  // one system-data read per local, in the order
                                 // Clang evaluates the arguments: a description
                                 // that is an array draws
  std::optional<std::string> commodityScript =
      ManifestString(ValueForKey(thisInfo, std::string("commodity_script")));
  OOCreditsQuantity price = commodities->samplePriceForCommodity(
      commodity.value_or(""), economy, commodityScript, SystemOf(thisInfo));

  return JS_NewNumber(context, price);

  OOJS_NATIVE_EXIT
}

static JSValue SystemInfoSetPropertyMethod(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  OOSystemInfo* thisInfo = nullptr;

  if (!JSSystemInfoGetSystemInfo(context, OOJS_THIS, &thisInfo))
    return OOJSNativeFailure(context);

  std::optional<std::string> property;
  oo::PList value;     // null for a JavaScript null
  oo::PList manifest;  // a string from JavaScript, or the running script's
                       // manifest identifier as read

  int32_t iValue;

  if (argc < 3) {
    cxx_OOJSReportBadArguments(
        context, "SystemInfo", "setProperty", MIN(argc, 3), OOJS_ARGV,
        std::nullopt, "setProperty(layer, property, value [,manifest])");
    return OOJSNativeFailure(context);
  }
  if (!OOJSValueToInt32(context, OOJS_ARGV[0], &iValue)) {
    cxx_OOJSReportBadArguments(
        context, "SystemInfo", "setProperty", MIN(argc, 3), OOJS_ARGV,
        std::nullopt, "setProperty(layer, property, value [,manifest])");
    return OOJSNativeFailure(context);
  }
  if (iValue < 0 || iValue >= OO_SYSTEM_LAYERS) {
    cxx_OOJSReportBadArguments(context, "SystemInfo", "setProperty",
                               MIN(argc, 3), OOJS_ARGV, std::nullopt,
                               "layer must be 0, 1, 2 or 3");
    return OOJSNativeFailure(context);
  }
  OOSystemLayer layer = (OOSystemLayer)iValue;

  property = cxx_OOStringFromJSValue(context, OOJS_ARGV[1]);
  if (!JS_IsNull(OOJS_ARGV[2])) {
    value = cxx_OOJSPListFromJSValue(context, OOJS_ARGV[2]);
  }
  if (argc >= 4) {
    manifest = StringOrNull(cxx_OOStringFromJSValue(context, OOJS_ARGV[3]));
  } else {
    manifest = RunningScriptManifest();
  }

  if (UNIVERSE != nullptr)
    UNIVERSE->setSystemDataForGalaxy(GalaxyOf(thisInfo), SystemOf(thisInfo),
                                     property.value_or(""), value,
                                     ManifestString(manifest), layer);

  OOJS_RETURN_VOID;

  OOJS_NATIVE_EXIT
}

// filteredSystems(this : Object, predicate : Function) : Array
static JSValue SystemInfoStaticFilteredSystems(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  /*	SpiderMonkey version converted the this argument with
          JS_ValueToObject(). QuickJS performs the same conversion (and
          null/undefined -> global object) when calling a non-strict
          function, so it is passed through unchanged.
  */
  // Get this and predicate arguments
  if (argc < 2 || !OOJSValueIsFunction(context, OOJS_ARGV[1])) {
    cxx_OOJSReportBadArguments(context, "SystemInfo", "filteredSystems", argc,
                               OOJS_ARGV, std::nullopt,
                               "this and predicate function");
    return OOJSNativeFailure(context);
  }
  JSValueConst jsThis = OOJS_ARGV[0];
  JSValueConst predicate = OOJS_ARGV[1];

  JSValue rval = JS_UNDEFINED;
  {
    oo::AutoreleaseScope pool;
    std::vector<oo::Ref<OOSystemInfo>> result;
    result.reserve(256);

    // Not OOJS_BEGIN_FULL_NATIVE() - we use JSAPI while paused.
    OOJSPauseTimeLimiter();

    // Iterate over systems.
    bool OK = true;  // (the array was always made)
    OOGalaxyID galaxy =
        (PLAYER != nullptr
             ? PLAYER->PlayerEntity::currentGalaxyID()
             : OOGalaxyID{});  // qualified: the final overrider, so the binding
                               // test stands in for it
    OOSystemID system;
    for (system = 0; system <= kOOMaximumSystemID; system++) {
      // NOTE: this deliberately bypasses the cache, since iteration is
      // inherently unfriendly to a single-item cache.
      oo::Ref<OOSystemInfo> info = OOSystemInfo::initWithGalaxy(galaxy, system);
      JSValue args[1] = {OOJSValueFromCxxObject(context, info.get())};

      OOJSResumeTimeLimiter();
      JSValue callResult =
          JS_Call(context, predicate, jsThis, 1, (JSValueConst*)args);
      OOJSPauseTimeLimiter();
      JS_FreeValue(context, args[0]);

      // On exception, it is left pending and propagated to our caller, as
      // before.
      OK = !JS_IsException(callResult);

      if (OK) {
        int boolVal = JS_ToBool(context, callResult);
        if (boolVal > 0) {
          result.emplace_back(info);
        } else if (boolVal < 0) {
          JS_FreeValue(context, JS_GetException(context));
        }
      }
      JS_FreeValue(context, callResult);

      if (!OK) break;
    }

    if (OK) {
      oo::PList::Array infos;
      infos.reserve(result.size());
      for (const auto& info : result)
        infos.push_back(oo::PList(
            oo::PList::Object(oo::Ref<oo::PListForeign>(info.get()))));
      rval = OOJSValueFromPList(context, oo::PList(std::move(infos)));
    } else {
      rval = OOJSNativeFailure(context);
    }
  }

  OOJSResumeTimeLimiter();
  return rval;

  OOJS_NATIVE_EXIT
}

static JSValue SystemInfoStaticSetInterstellarProperty(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  std::optional<std::string> property;
  oo::PList value;     // null for a JavaScript null
  oo::PList manifest;  // a string from JavaScript, or the running script's
                       // manifest identifier as read

  int32_t iValue;
  OOGalaxyID g;
  OOSystemID s1, s2;

  if (argc < 6) {
    cxx_OOJSReportBadArguments(context, "SystemInfo", "setInterstellarProperty",
                               MIN(argc, 3), OOJS_ARGV, std::nullopt,
                               "setProperty(galaxy, fromsystem, tosystem, "
                               "layer, property, value [,manifest])");
    return OOJSNativeFailure(context);
  }
  if (!OOJSValueToInt32(context, OOJS_ARGV[0], &iValue)) {
    cxx_OOJSReportBadArguments(context, "SystemInfo", "setInterstellarProperty",
                               MIN(argc, 3), OOJS_ARGV, std::nullopt,
                               "setProperty(galaxy, fromsystem, tosystem, "
                               "layer, property, value [,manifest])");
    return OOJSNativeFailure(context);
  }
  if (iValue < 0 || iValue > kOOMaximumGalaxyID) {
    cxx_OOJSReportBadArguments(context, "SystemInfo", "setInterstellarProperty",
                               MIN(argc, 3), OOJS_ARGV, std::nullopt,
                               "galaxy out of range");
    return OOJSNativeFailure(context);
  } else {
    g = (OOGalaxyID)iValue;
  }

  if (!OOJSValueToInt32(context, OOJS_ARGV[1], &iValue)) {
    cxx_OOJSReportBadArguments(context, "SystemInfo", "setInterstellarProperty",
                               MIN(argc, 3), OOJS_ARGV, std::nullopt,
                               "setProperty(galaxy, fromsystem, tosystem, "
                               "layer, property, value [,manifest])");
    return OOJSNativeFailure(context);
  }
  if (iValue < 0 || iValue > kOOMaximumSystemID) {
    cxx_OOJSReportBadArguments(context, "SystemInfo", "setInterstellarProperty",
                               MIN(argc, 3), OOJS_ARGV, std::nullopt,
                               "fromsystem out of range");
    return OOJSNativeFailure(context);
  } else {
    s1 = (OOSystemID)iValue;
  }

  if (!OOJSValueToInt32(context, OOJS_ARGV[2], &iValue)) {
    cxx_OOJSReportBadArguments(context, "SystemInfo", "setInterstellarProperty",
                               MIN(argc, 3), OOJS_ARGV, std::nullopt,
                               "setProperty(galaxy, fromsystem, tosystem, "
                               "layer, property, value [,manifest])");
    return OOJSNativeFailure(context);
  }
  if (iValue < 0 || iValue > kOOMaximumSystemID) {
    cxx_OOJSReportBadArguments(context, "SystemInfo", "setInterstellarProperty",
                               MIN(argc, 3), OOJS_ARGV, std::nullopt,
                               "tosystem out of range");
    return OOJSNativeFailure(context);
  } else {
    s2 = (OOSystemID)iValue;
  }

  if (!OOJSValueToInt32(context, OOJS_ARGV[3], &iValue)) {
    cxx_OOJSReportBadArguments(context, "SystemInfo", "setInterstellarProperty",
                               MIN(argc, 3), OOJS_ARGV, std::nullopt,
                               "setProperty(galaxy, fromsystem, tosystem, "
                               "layer, property, value [,manifest])");
    return OOJSNativeFailure(context);
  }
  if (iValue < 0 || iValue >= OO_SYSTEM_LAYERS) {
    cxx_OOJSReportBadArguments(context, "SystemInfo", "setInterstellarProperty",
                               MIN(argc, 3), OOJS_ARGV, std::nullopt,
                               "layer must be 0, 1, 2 or 3");
    return OOJSNativeFailure(context);
  }
  OOSystemLayer layer = (OOSystemLayer)iValue;

  property = cxx_OOStringFromJSValue(context, OOJS_ARGV[4]);
  if (!JS_IsNull(OOJS_ARGV[5])) {
    value = cxx_OOJSPListFromJSValue(context, OOJS_ARGV[5]);
  }
  if (argc >= 7) {
    manifest = StringOrNull(cxx_OOStringFromJSValue(context, OOJS_ARGV[6]));
  } else {
    manifest = RunningScriptManifest();
  }

  std::string key =
      std::format("interstellar: {} {} {}", static_cast<unsigned>(g),
                  static_cast<unsigned>(s1), static_cast<unsigned>(s2));

  OOSystemDescriptionManager* systemManager =
      (UNIVERSE != nullptr
           ? UNIVERSE->getSystemManager()
           : nullptr);  // null: nothing set, as a message to nil
  if (systemManager != nullptr)
    systemManager->setProperty(property.value_or(""), key, layer, value,
                               ManifestString(manifest));

  OOJS_RETURN_VOID;

  OOJS_NATIVE_EXIT
}
