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

#import "OOJSSystemInfo.h"
#import "OOConstToString.h"
#import "OOIsNumberLiteral.h"
#import "OOJSScript.h"
#import "OOJSVector.h"
#import "OOJavaScriptEngine.h"
#import "OOSystemDescriptionManager.h"
#import "PlayerEntityScriptMethods.h"
#import "Universe.h"

#import "OOObjCPList.h"
#include "oofnd/Notification.hpp"
#include "oofnd/String.hpp"
#include "oofnd/objc/OOAssert.h"
#include <cstring>
#include <set>

/*	SpiderMonkey implemented SystemInfo's dynamic per-system properties with
        class getProperty/setProperty/delProperty hooks and a JSCLASS_NEW_ENUMERATE
        enumerate hook. QuickJS equivalents are exotic methods on the class:

        * get_property: properties on the prototype chain (methods, the four
          fixed properties, Object.prototype) are found first, as SpiderMonkey
          only consulted the hook for names it could not otherwise find;
          anything else is looked up in the system data.
        * get_own_property / get_own_property_names: the system data keys are
          enumerable, so for..in, Object.keys(), Object.getOwnPropertyNames()
          and JSON.stringify() list exactly the system data keys, as the
          SpiderMonkey enumerate hook did; but, as in SpiderMonkey,
          hasOwnProperty() and the in operator report false for them. The fixed
          properties are own properties (OOJSGetSharedPermanentOwnProperty()),
          as in SpiderMonkey, but are not listed by any enumeration.
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

static JSClassID sSystemInfoClassID;

/*	The most recently created SystemInfo object. SpiderMonkey's cache was a
        weak reference, but its lazy garbage collector kept the object alive for
        a while, so successive system.info reads in a script usually got the same
        object. With reference counting the object would die at the end of each
        statement, so the cache holds a reference, released when another system
        is requested and when the JavaScript engine is reset. Zero-filled until
        first use, so always test with JS_IsObject().
*/
static JSValue sCachedSystemInfo;
static OOGalaxyID sCachedGalaxy;
static OOSystemID sCachedSystem;

static JSValue SystemInfoGetProperty(OOJS_GETTER_ARGS);
static void SystemInfoFinalize(JSRuntime* runtime, JSValueConst thisObj);

static int SystemInfoExoticGetOwnProperty(JSContext* context, JSPropertyDescriptor* desc, JSValueConst obj, JSAtom prop);
static int SystemInfoExoticGetOwnPropertyNames(JSContext* context, JSPropertyEnum** ptab, uint32_t* plen, JSValueConst obj);
static int SystemInfoExoticDeleteProperty(JSContext* context, JSValueConst obj, JSAtom prop);
static JSValue SystemInfoExoticGetProperty(JSContext* context, JSValueConst obj, JSAtom prop, JSValueConst receiver);
static int SystemInfoExoticSetProperty(JSContext* context, JSValueConst obj, JSAtom prop, JSValueConst value, JSValueConst receiver, int flags);

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
    .get_property = SystemInfoExoticGetProperty,
    .set_property = SystemInfoExoticSetProperty,
};

static JSClassDef sSystemInfoClass = {
    .class_name = "SystemInfo",
    .finalizer = SystemInfoFinalize,
    .exotic = &sSystemInfoExoticMethods,
};

enum {
    // Property IDs
    kSystemInfo_coordinates, // system coordinates (in LY), Vector3D (with z = 0), read-only
    kSystemInfo_internalCoordinates, // system coordinates (unscaled), Vector3D (with z = 0), read-only
    kSystemInfo_galaxyID, // galaxy number, integer, read-only
    kSystemInfo_systemID // system number, integer, read-only
};

static const JSCFunctionListEntry sSystemInfoProperties[] = {
    // JS name, getter, setter, ID, flags (hidden: see comment at top of file)
    JS_CGETSET_MAGIC_DEF2("coordinates", SystemInfoGetProperty, NULL, kSystemInfo_coordinates, OOJS_PROP_HIDDEN_READONLY_CB),
    JS_CGETSET_MAGIC_DEF2("internalCoordinates", SystemInfoGetProperty, NULL, kSystemInfo_internalCoordinates, OOJS_PROP_HIDDEN_READONLY_CB),
    JS_CGETSET_MAGIC_DEF2("galaxyID", SystemInfoGetProperty, NULL, kSystemInfo_galaxyID, OOJS_PROP_HIDDEN_READONLY_CB),
    JS_CGETSET_MAGIC_DEF2("systemID", SystemInfoGetProperty, NULL, kSystemInfo_systemID, OOJS_PROP_HIDDEN_READONLY_CB),
};

static const JSCFunctionListEntry sSystemInfoMethods[] = {
    // JS name, min args, function
    JS_CFUNC_DEF("toString", 0, OOJSObjectWrapperToString),
    JS_CFUNC_DEF("distanceToSystem", 1, SystemInfoDistanceToSystem),
    JS_CFUNC_DEF("routeToSystem", 1, SystemInfoRouteToSystem),
    JS_CFUNC_DEF("samplePrice", 1, SystemInfoSamplePrice),
    JS_CFUNC_DEF("setProperty", 3, SystemInfoSetPropertyMethod),
};

static const JSCFunctionListEntry sSystemInfoStaticMethods[] = {
    // JS name, min args, function
    JS_CFUNC_DEF("filteredSystems", 2, SystemInfoStaticFilteredSystems),
    JS_CFUNC_DEF("setInterstellarProperty", 4, SystemInfoStaticSetInterstellarProperty),
};

namespace {

// A string, or null for none.
oo::PList StringOrNull(const std::optional<std::string>& string)
{
    return string.has_value() ? oo::PList(*string) : oo::PList();
}

// A manifest identifier as the -fromManifest: arguments read it: a string, else none.
std::optional<std::string> ManifestString(const oo::PList& manifest)
{
    if (const std::string* text = manifest.getIf<std::string>())
        return *text;
    return std::nullopt;
}

// -intValue of a system property (an NSNumber or an NSString; 0 for nil).
int PropertyIntValue(const oo::PList& value)
{
    if (const std::string* text = value.getIf<std::string>())
        return oo::plist_get::intValue(oo::utf8ToUtf16(*text));
    return static_cast<int>(value.int64Value());
}

} // namespace

// Helper class wrapped by JS SystemInfo objects
@interface OOSystemInfo : OOObject {
@private
    OOGalaxyID _galaxy;
    OOSystemID _system;
    std::string _planetKey;
    std::set<std::string> _nullAssignedKeys; // See SystemInfoExoticSetProperty().
}

- (id)initWithGalaxy:(OOGalaxyID)galaxy system:(OOSystemID)system;

- (oo::PList)cxx_valueForKey:(const std::optional<std::string>&)key; // null for none
- (void)cxx_setValue:(const oo::PList&)value forKey:(const std::string&)key; // a null value removes

- (std::vector<std::string>)cxx_allKeys;

- (void)setNullAssigned:(BOOL)flag forKey:(const std::string&)key;
- (BOOL)isNullAssignedForKey:(const std::string&)key;

- (OOGalaxyID)galaxy;
- (OOSystemID)system;
//- (Random_Seed) systemSeed;

@end

DEFINE_JS_OBJECT_GETTER(JSSystemInfoGetSystemInfo, sSystemInfoClassID, OOSystemInfo)

@implementation OOSystemInfo

- (id)init
{
    [self release];
    return nil;
}

- (id)initWithGalaxy:(OOGalaxyID)galaxy system:(OOSystemID)system
{
    if (galaxy > kOOMaximumGalaxyID || system > kOOMaximumSystemID || system < kOOMinimumSystemID) {
        [self release];
        return nil;
    }

    if ((self = [super init])) {
        _galaxy = galaxy;
        _system = system;
        _planetKey = oo::str::format("%u %i", galaxy, system);
    }
    return self;
}

- (void)setNullAssigned:(BOOL)flag forKey:(const std::string&)key
{
    if (flag) {
        _nullAssignedKeys.insert(key);
    } else {
        _nullAssignedKeys.erase(key);
    }
}

- (BOOL)isNullAssignedForKey:(const std::string&)key
{
    return _nullAssignedKeys.count(key) != 0;
}

- (std::optional<std::string>)cxx_descriptionComponents
{
    return oo::str::format("galaxy %u, system %i", _galaxy, _system);
}

- (std::optional<std::string>)cxx_shortDescriptionComponents
{
    return _planetKey;
}

- (std::optional<std::string>)cxx_oo_jsClassName
{
    return std::string("SystemInfo");
}

- (BOOL)isEqual:(id)other
{
    return other == self || ([other isKindOfClass:[OOSystemInfo class]] && [other galaxy] == _galaxy && [other system] == _system);
}

- (NSUInteger)hash
{
    NSUInteger hash = _galaxy;
    hash <<= 16;
    hash |= (uint16_t)_system;
    return hash;
}

- (oo::PList)cxx_valueForKey:(const std::optional<std::string>&)key
{
    if ([UNIVERSE inInterstellarSpace] && _system == -1) {
        // -objectForKey: (a nil key found nothing)
        const oo::PList systemData = [UNIVERSE cxx_currentSystemData];
        const oo::PList* value = key.has_value() ? systemData.find(*key) : nullptr;
        return (value != nullptr) ? *value : oo::PList();
    }
    return [UNIVERSE cxx_systemDataForGalaxy:_galaxy planet:_system key:key.value_or("")]; // (a nil key as "")
}

- (void)cxx_setValue:(const oo::PList&)value forKey:(const std::string&)key
{
    // The running script's manifest identifier, handed on as it was read.
    const oo::PList manifest = [[OOJSScript currentlyRunningScript] cxx_propertyNamed:kLocalManifestProperty];

    [UNIVERSE cxx_setSystemDataForGalaxy:_galaxy planet:_system key:key value:value fromManifest:ManifestString(manifest) forLayer:OO_LAYER_OXP_DYNAMIC];
}

- (std::vector<std::string>)cxx_allKeys
{
    if ([UNIVERSE inInterstellarSpace] && _system == -1) {
        // the dictionary's keys, in key order (-allKeys gave hash order)
        std::vector<std::string> keys;
        if (const oo::PList::Dict* systemData = [UNIVERSE cxx_currentSystemData].getIf<oo::PList::Dict>()) {
            for (const auto& entry : *systemData)
                keys.push_back(entry.first);
        }
        return keys;
    }
    return [UNIVERSE cxx_systemDataKeysForGalaxy:_galaxy planet:_system];
}

- (OOGalaxyID)galaxy
{
    return _galaxy;
}

- (OOSystemID)system
{
    return _system;
}

/*- (Random_Seed) systemSeed
{
        OOAssert([PLAYER currentGalaxyID] == _galaxy, "Attempt to use -[OOSystemInfo systemSeed] from a different galaxy.");
        return [UNIVERSE systemSeedForSystemNumber:_system];
        }*/

- (NSPoint)coordinates
{
    if ([UNIVERSE inInterstellarSpace] && _system == -1) {
        return [PLAYER galaxy_coordinates];
    }
    return [UNIVERSE coordinatesForSystem:_system];
}

- (JSValue)oo_jsValueInContext:(JSContext*)context
{
    JSValue result = JS_NewObjectClass(context, (int)sSystemInfoClassID);
    if (JS_IsException(result)) {
        JS_FreeValue(context, JS_GetException(context));
        return JS_NULL;
    }
    JS_SetOpaque(result, [self retain]);

    return result;
}

+ (void)oo_javaScriptEngineWillReset:(const oo::Notification&)notification
{
    JSValue oldCache = sCachedSystemInfo;
    sCachedSystemInfo = JS_UNDEFINED;
    if (JS_IsObject(oldCache))
        JS_FreeValue(OOJSAcquireContext(), oldCache);
}

@end

void InitOOJSSystemInfo(JSContext* context, JSValueConst global)
{
    static BOOL observing = NO;
    if (!observing) {
        oo::NotificationCenter::defaultCenter().addObserver([OOSystemInfo class], kOOJavaScriptEngineWillResetNotificationName,
            nullptr,
            [](const oo::Notification& notification) { [OOSystemInfo oo_javaScriptEngineWillReset:notification]; });
        observing = YES;
    }
    sCachedSystemInfo = JS_UNDEFINED;

    OOJSRegisterClass(&sSystemInfoClassID, &sSystemInfoClass);
    OOJSInitClass(context, global, sSystemInfoClassID, JS_UNDEFINED, OOJSUnconstructableConstruct, 0,
        sSystemInfoProperties, OOJS_COUNT(sSystemInfoProperties), sSystemInfoMethods, OOJS_COUNT(sSystemInfoMethods),
        sSystemInfoStaticMethods, OOJS_COUNT(sSystemInfoStaticMethods));
    OOJSRegisterObjectConverter(sSystemInfoClassID, OOJSBasicPrivateObjectConverter);
}

JSValue GetJSSystemInfoForSystem(JSContext* context, OOGalaxyID galaxy, OOSystemID system)
{
    OOJS_PROFILE_ENTER

    // Use cached object if possible.
    if (JS_IsObject(sCachedSystemInfo) && sCachedGalaxy == galaxy && sCachedSystem == system) {
        return JS_DupValue(context, sCachedSystemInfo);
    }

    // If not, create a new one.
    OOSystemInfo* info = nil;
    JSValue result;
    OOJS_BEGIN_FULL_NATIVE(context)
    info = [[[OOSystemInfo alloc] initWithGalaxy:galaxy system:system] autorelease];
    OOJS_END_FULL_NATIVE

    if (EXPECT_NOT(info == nil)) {
        cxx_OOJSReportWarning(context, "Could not create system info object for galaxy %u, system %i.", galaxy, system);
    }

    result = OOJSValueFromNativeObject(context, info);

    // Replace the cached object. (Freeing it may run SystemInfoFinalize(), which clears the cache.)
    JSValue oldCache = sCachedSystemInfo;
    sCachedSystemInfo = JS_UNDEFINED;
    if (JS_IsObject(oldCache))
        JS_FreeValue(context, oldCache);
    sCachedSystemInfo = JS_IsObject(result) ? JS_DupValue(context, result) : JS_UNDEFINED;
    sCachedGalaxy = galaxy;
    sCachedSystem = system;

    return result;

    OOJS_PROFILE_EXIT
}

static void SystemInfoFinalize(JSRuntime* runtime, JSValueConst thisObj)
{
    OOJS_PROFILE_ENTER

    // Clear now-stale cache entry if appropriate.
    if (JS_IsObject(sCachedSystemInfo) && JS_VALUE_GET_PTR(sCachedSystemInfo) == JS_VALUE_GET_PTR(thisObj)) {
        sCachedSystemInfo = JS_UNDEFINED;
    }

    // Releases the OOSystemInfo.
    OOJSObjectWrapperFinalize(runtime, thisObj);

    OOJS_PROFILE_EXIT_VOID
}

// *** Exotic property behaviour (replaces SpiderMonkey class hooks) ***

/*	Exotic methods are called from inside QuickJS, so native exceptions must
        not escape them. These bracket the body of each one, converting an
        exception into a JS error.
*/
#define OOJS_EXOTIC_ENTER \
    try {
#define OOJS_EXOTIC_EXIT(context, failure)   \
    }                                        \
    catch (...)                              \
    {                                        \
        OOJSReportCurrentException(context); \
        return (failure);                    \
    }

// The OOSystemInfo of an instance, or nil for the prototype.
static OOSystemInfo* SystemInfoForObject(JSValueConst obj)
{
    return (OOSystemInfo*)JS_GetOpaque(obj, sSystemInfoClassID);
}

// The key for a string property, or nullopt for symbols.
static std::optional<std::string> SystemInfoKeyForAtom(JSContext* context, JSAtom prop)
{
    std::optional<std::string> key;
    JSValue propValue = JS_AtomToValue(context, prop);
    if (JS_IsString(propValue)) {
        key = cxx_OOStringFromJSValue(context, propValue);
    }
    JS_FreeValue(context, propValue);
    return key;
}

/*	Look up a system data value, as the string-ID branch of the SpiderMonkey
        SystemInfoGetProperty() did. Returns YES and an owned *outValue if the key
        exists, NO otherwise (or on exception, which is then pending and
        *outValue is JS_EXCEPTION).
*/
static BOOL SystemInfoGetSystemDataValue(JSContext* context, OOSystemInfo* info, const std::string& key, JSValue* outValue)
{
    *outValue = JS_UNDEFINED;

    OOSystemDescriptionManager* systemManager = [UNIVERSE systemManager];
    oo::PList propValue;
    // interstellar space needs more work at this stage
    if ([info system] != -1) {
        propValue = [systemManager cxx_getProperty:key forSystem:[info system] inGalaxy:[info galaxy]];
    } else {
        propValue = [info cxx_valueForKey:key];
    }

    if (propValue.isNull())
        return NO;

    if (propValue.isNumber() || OOIsNumberLiteral(oo::DescriptionOf(propValue), YES)) {
        // -doubleValue: an NSNumber's, or an NSString's (a number literal)
        const std::string* text = propValue.getIf<std::string>();
        const double number = (text != nullptr) ? oo::plist_get::doubleValue(oo::utf8ToUtf16(*text)) : propValue.doubleValue();
        *outValue = JS_NewNumber(context, number);
    } else {
        *outValue = OOJSValueFromPList(context, propValue); // non-null: as its own glue gave
    }
    return YES;
}

/*	Ordinary [[Set]] on the prototype chain of obj (whose own properties have
        already been checked by QuickJS). If an accessor or read-only property is
        found, it is handled and *outHandled is set; the return value is then the
        set_property result. Otherwise *outHandled is NO and the caller decides
        where the value goes.
*/
static int SystemInfoSetOnPrototypeChain(JSContext* context, JSValueConst obj, JSAtom prop, JSValueConst value, JSValueConst receiver, int flags, BOOL* outHandled)
{
    JSValue proto = JS_GetPrototype(context, obj);
    *outHandled = YES;

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
                if (JS_IsUndefined(desc.setter))
                    goto readOnly;
                JSValue result = JS_Call(context, desc.setter, receiver, 1, &value);
                JS_FreeValue(context, desc.setter);
                if (JS_IsException(result))
                    return -1;
                JS_FreeValue(context, result);
                return true;
            }
            JS_FreeValue(context, desc.value);
            if (!(desc.flags & JS_PROP_WRITABLE))
                goto readOnly;
            *outHandled = NO;
            return true;
        }

        JSValue next = JS_GetPrototype(context, proto);
        JS_FreeValue(context, proto);
        proto = next;
    }

    if (JS_IsException(proto))
        return -1;
    JS_FreeValue(context, proto);
    *outHandled = NO;
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

static int SystemInfoExoticGetOwnProperty(JSContext* context, JSPropertyDescriptor* desc, JSValueConst obj, JSAtom prop)
{
    OOJS_EXOTIC_ENTER

    OOSystemInfo* info = SystemInfoForObject(obj);
    std::optional<std::string> key = (info != nil) ? SystemInfoKeyForAtom(context, prop) : std::nullopt;
    JSValue value;

    /*	SpiderMonkey reported the fixed (shared permanent) properties as own
            properties, so they win over system data keys of the same name
            (notably "coordinates"). They are hidden, but a name that is also a
            system data key is reported as enumerable, since the SpiderMonkey
            enumerate hook listed every system data key.
    */
    int shared = OOJSGetSharedPermanentOwnProperty(context, desc, obj, prop);
    if (shared != 0) {
        if (shared > 0 && desc != NULL && key.has_value()) {
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
        return false; // Prototype (no dynamic properties) or symbol.

    /*	SpiderMonkey's resolve hook made system data keys enumerable (for..in and
            Object.keys() list them) but not own properties: hasOwnProperty() and
            the in operator returned false. QuickJS asks this hook without a
            descriptor for hasOwnProperty() and in, and with one when collecting
            enumerable keys, so answer accordingly. (QuickJS-ng 0.17 behaviour;
            tools/js-parity checks it.)
    */
    if (desc == NULL)
        return false;

    if (!SystemInfoGetSystemDataValue(context, info, *key, &value)) {
        return false;
    }
    if (JS_IsException(value))
        return -1;

    if (desc != NULL) {
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

static int SystemInfoExoticGetOwnPropertyNames(JSContext* context, JSPropertyEnum** ptab, uint32_t* plen, JSValueConst obj)
{
    OOJS_EXOTIC_ENTER

    *ptab = NULL;
    *plen = 0;

    OOSystemInfo* info = SystemInfoForObject(obj);
    const std::vector<std::string> keys = [info cxx_allKeys];
    NSUInteger count = keys.size();
    assert(count <= INT32_MAX);

    JSPropertyEnum* tab = (JSPropertyEnum*)js_mallocz(context, sizeof *tab * (count + 1));
    if (tab == NULL)
        return -1;

    // System data keys (all enumerable; the SpiderMonkey enumerate hook listed exactly these).
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

static int SystemInfoExoticDeleteProperty(JSContext* context, JSValueConst obj, JSAtom prop)
{
    OOJS_EXOTIC_ENTER

    // SpiderMonkey version: set the property to undefined (which removes it).
    OOSystemInfo* info = SystemInfoForObject(obj);
    std::optional<std::string> key = SystemInfoKeyForAtom(context, prop);
    if (info != nil && key.has_value()) {
        [info cxx_setValue:oo::PList() forKey:*key];
    }
    return true;

    OOJS_EXOTIC_EXIT(context, -1)
}

static JSValue SystemInfoExoticGetProperty(JSContext* context, JSValueConst obj, JSAtom prop, JSValueConst receiver)
{
    OOJS_EXOTIC_ENTER

    // Prototype chain first: SpiderMonkey only used the hook for otherwise unknown names.
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
                    result = JS_Call(context, desc.getter, receiver, 0, NULL);
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
    if (JS_IsException(proto))
        return JS_EXCEPTION;
    JS_FreeValue(context, proto);

    OOSystemInfo* info = SystemInfoForObject(obj);
    if (info == nil) {
        // Let QuickJS behave normally for the prototype object (where info will be nil).
        return JS_UNDEFINED;
    }

    std::optional<std::string> key = SystemInfoKeyForAtom(context, prop);
    if (!key.has_value())
        return JS_UNDEFINED;

    JSValue value;
    if (!SystemInfoGetSystemDataValue(context, info, *key, &value) && [info isNullAssignedForKey:*key])
        return JS_NULL;
    return value;

    OOJS_EXOTIC_EXIT(context, JS_EXCEPTION)
}

static int SystemInfoExoticSetProperty(JSContext* context, JSValueConst obj, JSAtom prop, JSValueConst value, JSValueConst receiver, int flags)
{
    OOJS_EXOTIC_ENTER

    BOOL handled;
    int result = SystemInfoSetOnPrototypeChain(context, obj, prop, value, receiver, flags, &handled);
    if (handled)
        return result;

    OOSystemInfo* info = SystemInfoForObject(obj);
    std::optional<std::string> key = SystemInfoKeyForAtom(context, prop);
    if (info == nil || !key.has_value() || !JS_IsObject(receiver) || JS_VALUE_GET_PTR(receiver) != JS_VALUE_GET_PTR(obj)) {
        // Ordinary property (prototype object, symbol, or inherited by another object).
        return JS_DefinePropertyValue(context, receiver, prop, JS_DupValue(context, value), JS_PROP_C_W_E);
    }

    /*	Assigning null removes the system data key. SpiderMonkey also stored the
            value in the object's own slot, so reading the key back gave null;
            remember such keys to do the same.
    */
    [info cxx_setValue:StringOrNull(cxx_OOStringFromJSValue(context, value)) forKey:*key];
    [info setNullAssigned:JS_IsNull(value) forKey:*key];
    return true;

    OOJS_EXOTIC_EXIT(context, -1)
}

// *** Fixed properties ***

static JSValue SystemInfoGetProperty(OOJS_GETTER_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    OOSystemInfo* info = OOJSNativeObjectOfClassFromJSObject(context, thisObj, [OOSystemInfo class]);
    if (info == nil) {
        // Let QuickJS handle access to the prototype object (where info will be nil).
        return JS_UNDEFINED;
    }

    // What if we're trying to access a saved witchspace systemInfo object?
    BOOL savedInterstellarInfo = ![UNIVERSE inInterstellarSpace] && [info system] == -1;
    BOOL sameGalaxy = [PLAYER currentGalaxyID] == [info galaxy];

    switch (magic) {
    case kSystemInfo_coordinates:
        if (sameGalaxy && !savedInterstellarInfo) {
            OOJS_RETURN_VECTOR(OOGalacticCoordinatesFromInternal([info coordinates]));
        } else {
            cxx_OOJSReportError(context, "Cannot read systemInfo values for %s.", (savedInterstellarInfo ? "invalid interstellar space reference" : "other galaxies"));
            return OOJSNativeFailure(context);
        }
        break;

    case kSystemInfo_internalCoordinates:
        if (sameGalaxy && !savedInterstellarInfo) {
            OOJS_RETURN_WITH_HELPER(NSPointToVectorJSValue, [info coordinates]);
        } else {
            cxx_OOJSReportError(context, "Cannot read systemInfo values for %s.", (savedInterstellarInfo ? "invalid interstellar space reference" : "other galaxies"));
            return OOJSNativeFailure(context);
        }
        break;

    case kSystemInfo_galaxyID:
        return JS_NewInt32(context, [info galaxy]);

    case kSystemInfo_systemID:
        return JS_NewInt32(context, [info system]);

    default:
        OOJSReportBadPropertySelector(context, thisObj, magic, sSystemInfoProperties, OOJS_COUNT(sSystemInfoProperties));
        return OOJSNativeFailure(context);
    }

    OOJS_NATIVE_EXIT
}

// *** Methods ***

// distanceToSystem(sys : SystemInfo) : Number
static JSValue SystemInfoDistanceToSystem(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    OOSystemInfo* thisInfo = nil;
    OOSystemInfo* otherInfo = nil;

    if (!JSSystemInfoGetSystemInfo(context, OOJS_THIS, &thisInfo))
        return OOJSNativeFailure(context);
    // SpiderMonkey version used JS_ValueToObject(); a primitive can't be a SystemInfo anyway.
    if (argc < 1 || !JS_IsObject(OOJS_ARGV[0]) || !JSSystemInfoGetSystemInfo(context, OOJS_ARGV[0], &otherInfo)) {
        cxx_OOJSReportBadArguments(context, "SystemInfo", "distanceToSystem", MIN(argc, 1), OOJS_ARGV, std::nullopt, "system info");
        return OOJSNativeFailure(context);
    }

    BOOL sameGalaxy = ([thisInfo galaxy] == [otherInfo galaxy]);
    if (!sameGalaxy) {
        cxx_OOJSReportErrorForCaller(context, "SystemInfo", "distanceToSystem", "Cannot calculate distance for systems in other galaxies.");
        return OOJSNativeFailure(context);
    }

    NSPoint thisCoord = [thisInfo coordinates];
    NSPoint otherCoord = [otherInfo coordinates];

    OOJS_RETURN_DOUBLE(distanceBetweenPlanetPositions(thisCoord.x, thisCoord.y, otherCoord.x, otherCoord.y));

    OOJS_NATIVE_EXIT
}

// routeToSystem(sys : SystemInfo [, optimizedBy : String]) : Object
static JSValue SystemInfoRouteToSystem(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    OOSystemInfo* thisInfo = nil;
    OOSystemInfo* otherInfo = nil;
    oo::PList result;
    OORouteType routeType = OPTIMIZED_BY_JUMPS;

    if (!JSSystemInfoGetSystemInfo(context, OOJS_THIS, &thisInfo))
        return OOJSNativeFailure(context);
    if (argc < 1 || !JS_IsObject(OOJS_ARGV[0]) || !JSSystemInfoGetSystemInfo(context, OOJS_ARGV[0], &otherInfo)) {
        cxx_OOJSReportBadArguments(context, "SystemInfo", "routeToSystem", MIN(argc, 1), OOJS_ARGV, std::nullopt, "system info");
        return OOJSNativeFailure(context);
    }

    BOOL sameGalaxy = ([thisInfo galaxy] == [otherInfo galaxy]);
    if (!sameGalaxy) {
        cxx_OOJSReportErrorForCaller(context, "SystemInfo", "routeToSystem", "Cannot calculate route for destinations in other galaxies.");
        return OOJSNativeFailure(context);
    }

    if (argc >= 2) {
        routeType = cxx_StringToRouteType(cxx_OOStringFromJSValue(context, OOJS_ARGV[1]).value_or(""));
    }

    OOJS_BEGIN_FULL_NATIVE(context)
    result = [UNIVERSE cxx_routeFromSystem:[thisInfo system] toSystem:[otherInfo system] optimizedBy:routeType];
    OOJS_END_FULL_NATIVE

    OOJS_RETURN_PLIST(result);

    OOJS_NATIVE_EXIT
}

// samplePrice(commodity)
static JSValue SystemInfoSamplePrice(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    OOSystemInfo* thisInfo = nil;

    if (!JSSystemInfoGetSystemInfo(context, OOJS_THIS, &thisInfo))
        return OOJSNativeFailure(context);
    std::optional<std::string> commodity = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
    if (EXPECT_NOT(![[UNIVERSE commodities] cxx_goodDefined:commodity.value_or("")])) {
        cxx_OOJSReportBadArguments(context, "SystemInfo", "samplePrice", MIN(argc, 1), OOJS_ARGV, std::nullopt, "Unrecognised commodity type");
        return OOJSNativeFailure(context);
    }

    BOOL sameGalaxy = ([thisInfo galaxy] == [PLAYER galaxyNumber]);
    if (!sameGalaxy) {
        cxx_OOJSReportErrorForCaller(context, "SystemInfo", "samplePrice", "Cannot calculate sample price for destinations in other galaxies.");
        return OOJSNativeFailure(context);
    }

    OOCreditsQuantity price = [[UNIVERSE commodities] cxx_samplePriceForCommodity:commodity.value_or("") inEconomy:PropertyIntValue([thisInfo cxx_valueForKey:std::string("economy")]) withScript:ManifestString([thisInfo cxx_valueForKey:std::string("commodity_script")]) inSystem:[thisInfo system]];

    return JS_NewNumber(context, price);

    OOJS_NATIVE_EXIT
}

static JSValue SystemInfoSetPropertyMethod(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    OOSystemInfo* thisInfo = nil;

    if (!JSSystemInfoGetSystemInfo(context, OOJS_THIS, &thisInfo))
        return OOJSNativeFailure(context);

    std::optional<std::string> property;
    oo::PList value; // null for a JavaScript null
    oo::PList manifest; // a string from JavaScript, or the running script's manifest identifier as read

    int32_t iValue;

    if (argc < 3) {
        cxx_OOJSReportBadArguments(context, "SystemInfo", "setProperty", MIN(argc, 3), OOJS_ARGV, std::nullopt, "setProperty(layer, property, value [,manifest])");
        return OOJSNativeFailure(context);
    }
    if (!OOJSValueToInt32(context, OOJS_ARGV[0], &iValue)) {
        cxx_OOJSReportBadArguments(context, "SystemInfo", "setProperty", MIN(argc, 3), OOJS_ARGV, std::nullopt, "setProperty(layer, property, value [,manifest])");
        return OOJSNativeFailure(context);
    }
    if (iValue < 0 || iValue >= OO_SYSTEM_LAYERS) {
        cxx_OOJSReportBadArguments(context, "SystemInfo", "setProperty", MIN(argc, 3), OOJS_ARGV, std::nullopt, "layer must be 0, 1, 2 or 3");
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
        manifest = [[OOJSScript currentlyRunningScript] cxx_propertyNamed:kLocalManifestProperty];
    }

    [UNIVERSE cxx_setSystemDataForGalaxy:[thisInfo galaxy] planet:[thisInfo system] key:property.value_or("") value:value fromManifest:ManifestString(manifest) forLayer:layer];

    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}

// filteredSystems(this : Object, predicate : Function) : Array
static JSValue SystemInfoStaticFilteredSystems(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    /*	SpiderMonkey version converted the this argument with
            JS_ValueToObject(). QuickJS performs the same conversion (and
            null/undefined -> global object) when calling a non-strict
            function, so it is passed through unchanged.
    */
    // Get this and predicate arguments
    if (argc < 2 || !OOJSValueIsFunction(context, OOJS_ARGV[1])) {
        cxx_OOJSReportBadArguments(context, "SystemInfo", "filteredSystems", argc, OOJS_ARGV, std::nullopt, "this and predicate function");
        return OOJSNativeFailure(context);
    }
    JSValueConst jsThis = OOJS_ARGV[0];
    JSValueConst predicate = OOJS_ARGV[1];

    JSValue rval = JS_UNDEFINED;
    @autoreleasepool {
        std::vector<oo::ObjCRef<OOSystemInfo*>> result;
        result.reserve(256);

        // Not OOJS_BEGIN_FULL_NATIVE() - we use JSAPI while paused.
        OOJSPauseTimeLimiter();

        // Iterate over systems.
        BOOL OK = YES; // (the array was always made)
        OOGalaxyID galaxy = [PLAYER currentGalaxyID];
        OOSystemID system;
        for (system = 0; system <= kOOMaximumSystemID; system++) {
            // NOTE: this deliberately bypasses the cache, since iteration is inherently unfriendly to a single-item cache.
            OOSystemInfo* info = [[[OOSystemInfo alloc] initWithGalaxy:galaxy system:system] autorelease];
            JSValue args[1] = { OOJSValueFromNativeObject(context, info) };

            OOJSResumeTimeLimiter();
            JSValue callResult = JS_Call(context, predicate, jsThis, 1, (JSValueConst*)args);
            OOJSPauseTimeLimiter();
            JS_FreeValue(context, args[0]);

            // On exception, it is left pending and propagated to our caller, as before.
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

            if (!OK)
                break;
        }

        if (OK) {
            oo::PList::Array infos;
            infos.reserve(result.size());
            for (const auto& info : result)
                infos.push_back(oo::PListObject(info.get()));
            rval = OOJSValueFromPList(context, oo::PList(std::move(infos)));
        } else {
            rval = OOJSNativeFailure(context);
        }
    }

    OOJSResumeTimeLimiter();
    return rval;

    OOJS_NATIVE_EXIT
}

static JSValue SystemInfoStaticSetInterstellarProperty(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    std::optional<std::string> property;
    oo::PList value; // null for a JavaScript null
    oo::PList manifest; // a string from JavaScript, or the running script's manifest identifier as read

    int32_t iValue;
    OOGalaxyID g;
    OOSystemID s1, s2;

    if (argc < 6) {
        cxx_OOJSReportBadArguments(context, "SystemInfo", "setInterstellarProperty", MIN(argc, 3), OOJS_ARGV, std::nullopt, "setProperty(galaxy, fromsystem, tosystem, layer, property, value [,manifest])");
        return OOJSNativeFailure(context);
    }
    if (!OOJSValueToInt32(context, OOJS_ARGV[0], &iValue)) {
        cxx_OOJSReportBadArguments(context, "SystemInfo", "setInterstellarProperty", MIN(argc, 3), OOJS_ARGV, std::nullopt, "setProperty(galaxy, fromsystem, tosystem, layer, property, value [,manifest])");
        return OOJSNativeFailure(context);
    }
    if (iValue < 0 || iValue > kOOMaximumGalaxyID) {
        cxx_OOJSReportBadArguments(context, "SystemInfo", "setInterstellarProperty", MIN(argc, 3), OOJS_ARGV, std::nullopt, "galaxy out of range");
        return OOJSNativeFailure(context);
    } else {
        g = (OOGalaxyID)iValue;
    }

    if (!OOJSValueToInt32(context, OOJS_ARGV[1], &iValue)) {
        cxx_OOJSReportBadArguments(context, "SystemInfo", "setInterstellarProperty", MIN(argc, 3), OOJS_ARGV, std::nullopt, "setProperty(galaxy, fromsystem, tosystem, layer, property, value [,manifest])");
        return OOJSNativeFailure(context);
    }
    if (iValue < 0 || iValue > kOOMaximumSystemID) {
        cxx_OOJSReportBadArguments(context, "SystemInfo", "setInterstellarProperty", MIN(argc, 3), OOJS_ARGV, std::nullopt, "fromsystem out of range");
        return OOJSNativeFailure(context);
    } else {
        s1 = (OOSystemID)iValue;
    }

    if (!OOJSValueToInt32(context, OOJS_ARGV[2], &iValue)) {
        cxx_OOJSReportBadArguments(context, "SystemInfo", "setInterstellarProperty", MIN(argc, 3), OOJS_ARGV, std::nullopt, "setProperty(galaxy, fromsystem, tosystem, layer, property, value [,manifest])");
        return OOJSNativeFailure(context);
    }
    if (iValue < 0 || iValue > kOOMaximumSystemID) {
        cxx_OOJSReportBadArguments(context, "SystemInfo", "setInterstellarProperty", MIN(argc, 3), OOJS_ARGV, std::nullopt, "tosystem out of range");
        return OOJSNativeFailure(context);
    } else {
        s2 = (OOSystemID)iValue;
    }

    if (!OOJSValueToInt32(context, OOJS_ARGV[3], &iValue)) {
        cxx_OOJSReportBadArguments(context, "SystemInfo", "setInterstellarProperty", MIN(argc, 3), OOJS_ARGV, std::nullopt, "setProperty(galaxy, fromsystem, tosystem, layer, property, value [,manifest])");
        return OOJSNativeFailure(context);
    }
    if (iValue < 0 || iValue >= OO_SYSTEM_LAYERS) {
        cxx_OOJSReportBadArguments(context, "SystemInfo", "setInterstellarProperty", MIN(argc, 3), OOJS_ARGV, std::nullopt, "layer must be 0, 1, 2 or 3");
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
        manifest = [[OOJSScript currentlyRunningScript] cxx_propertyNamed:kLocalManifestProperty];
    }

    std::string key = oo::str::format("interstellar: %u %u %u", g, s1, s2);

    [[UNIVERSE systemManager] cxx_setProperty:property.value_or("") forSystemKey:key andLayer:layer toValue:value fromManifest:ManifestString(manifest)];

    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}
