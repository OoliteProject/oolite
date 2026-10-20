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

/*	SpiderMonkey implemented SystemInfo's dynamic per-system properties with
        class getProperty/setProperty/delProperty hooks and a JSCLASS_NEW_ENUMERATE
        enumerate hook. QuickJS equivalents are exotic methods on the class:

        * get_property: properties on the prototype chain (methods, the four
          fixed properties, Object.prototype) are found first, as SpiderMonkey
          only consulted the hook for names it could not otherwise find;
          anything else is looked up in the system data.
        * get_own_property / get_own_property_names: the system data keys are
          the (enumerable) own properties, so for..in, Object.keys(),
          Object.getOwnPropertyNames() and JSON.stringify() list exactly the
          system data keys, as the SpiderMonkey enumerate hook did. As a side
          effect, hasOwnProperty() and the in operator now report true for
          system data keys (SpiderMonkey reported false). The fixed properties
          are also own properties (OOJSGetSharedPermanentOwnProperty()), as in
          SpiderMonkey, and appear in Object.getOwnPropertyNames() (but not
          for..in or Object.keys(), being hidden). SpiderMonkey's enumerate hook
          listed only the system data keys there.
        * set_property: assignments to names that are not read-only or
          accessors on the prototype chain are stored (as strings) in the
          system data, like the SpiderMonkey setProperty hook. SpiderMonkey also
          added a shadowing own slot property; it is not needed here, since reads
          go to the system data.
        * delete_property: removes the key from the system data, like the
          SpiderMonkey delProperty hook.

        The fixed properties (coordinates etc.) are not enumerable, because the
        SpiderMonkey enumerate hook never listed them.
*/

static JSClassID sSystemInfoClassID;

/*	Weak reference (no reference count held) to the most recently created
        SystemInfo object. Cleared when that object is finalized and when the
        JavaScript engine is reset. Zero-filled until first use, so always test
        with JS_IsObject().
*/
static JSValue sCachedSystemInfo;
static OOGalaxyID sCachedGalaxy;
static OOSystemID sCachedSystem;

static JSValue SystemInfoGetProperty(OOJS_GETTER_ARGS);
static void SystemInfoFinalize(JSRuntime* runtime, JSValueConst this);

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

// Helper class wrapped by JS SystemInfo objects
@interface OOSystemInfo : NSObject {
@private
    OOGalaxyID _galaxy;
    OOSystemID _system;
    NSString* _planetKey;
}

- (id)initWithGalaxy:(OOGalaxyID)galaxy system:(OOSystemID)system;

- (id)valueForKey:(NSString*)key;
- (void)setValue:(id)value forKey:(NSString*)key;

- (NSArray*)allKeys;

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
        _planetKey = [[NSString stringWithFormat:@"%u %i", galaxy, system] retain];
    }
    return self;
}

- (void)dealloc
{
    [_planetKey release];

    [super dealloc];
}

- (NSString*)descriptionComponents
{
    return [NSString stringWithFormat:@"galaxy %u, system %i", _galaxy, _system];
}

- (NSString*)shortDescriptionComponents
{
    return _planetKey;
}

- (NSString*)oo_jsClassName
{
    return @"SystemInfo";
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

- (id)valueForKey:(NSString*)key
{
    if ([UNIVERSE inInterstellarSpace] && _system == -1) {
        return [[UNIVERSE currentSystemData] objectForKey:key];
    }
    return [UNIVERSE systemDataForGalaxy:_galaxy planet:_system key:key];
}

- (void)setValue:(id)value forKey:(NSString*)key
{
    NSString* manifest = [[OOJSScript currentlyRunningScript] propertyNamed:kLocalManifestProperty];

    [UNIVERSE setSystemDataForGalaxy:_galaxy planet:_system key:key value:value fromManifest:manifest forLayer:OO_LAYER_OXP_DYNAMIC];
}

- (NSArray*)allKeys
{
    if ([UNIVERSE inInterstellarSpace] && _system == -1) {
        return [[UNIVERSE currentSystemData] allKeys];
    }
    return [UNIVERSE systemDataKeysForGalaxy:_galaxy planet:_system];
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
        NSAssert([PLAYER currentGalaxyID] == _galaxy, @"Attempt to use -[OOSystemInfo systemSeed] from a different galaxy.");
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

// The cache holds no reference, so it only needs forgetting on reset.
+ (void)oo_javaScriptEngineWillReset:(NSNotification*)notification
{
    sCachedSystemInfo = JS_UNDEFINED;
}

@end

void InitOOJSSystemInfo(JSContext* context, JSValueConst global)
{
    static BOOL observing = NO;
    if (!observing) {
        [[NSNotificationCenter defaultCenter] addObserver:[OOSystemInfo class]
                                                 selector:@selector(oo_javaScriptEngineWillReset:)
                                                     name:kOOJavaScriptEngineWillResetNotification
                                                   object:nil];
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
        OOJSReportWarning(context, @"Could not create system info object for galaxy %u, system %i.", galaxy, system);
    }

    result = OOJSValueFromNativeObject(context, info);

    // Cache is not a reference; we clear it in finalize if necessary.
    sCachedSystemInfo = JS_IsObject(result) ? result : JS_UNDEFINED;
    sCachedGalaxy = galaxy;
    sCachedSystem = system;

    return result;

    OOJS_PROFILE_EXIT
}

static void SystemInfoFinalize(JSRuntime* runtime, JSValueConst this)
{
    OOJS_PROFILE_ENTER

    // Clear now-stale cache entry if appropriate.
    if (JS_IsObject(sCachedSystemInfo) && JS_VALUE_GET_PTR(sCachedSystemInfo) == JS_VALUE_GET_PTR(this)) {
        sCachedSystemInfo = JS_UNDEFINED;
    }

    // Releases the OOSystemInfo.
    OOJSObjectWrapperFinalize(runtime, this);

    OOJS_PROFILE_EXIT_VOID
}

// *** Exotic property behaviour (replaces SpiderMonkey class hooks) ***

/*	Exotic methods are called from inside QuickJS, so Objective-C exceptions
        must not escape them. These bracket the body of each one, converting an
        exception into a JS error.
*/
#define OOJS_EXOTIC_ENTER \
    @try {
#define OOJS_EXOTIC_EXIT(context, failure)              \
    }                                                   \
    @catch (id exception)                               \
    {                                                   \
        OOJSReportWrappedException(context, exception); \
        return (failure);                               \
    }

// The OOSystemInfo of an instance, or nil for the prototype.
static OOSystemInfo* SystemInfoForObject(JSValueConst obj)
{
    return (OOSystemInfo*)JS_GetOpaque(obj, sSystemInfoClassID);
}

// The key for a string property, or nil for symbols.
static NSString* SystemInfoKeyForAtom(JSContext* context, JSAtom prop)
{
    NSString* key = nil;
    JSValue propValue = JS_AtomToValue(context, prop);
    if (JS_IsString(propValue)) {
        key = OOStringFromJSValue(context, propValue);
    }
    JS_FreeValue(context, propValue);
    return key;
}

/*	Look up a system data value, as the string-ID branch of the SpiderMonkey
        SystemInfoGetProperty() did. Returns YES and an owned *outValue if the key
        exists, NO otherwise (or on exception, which is then pending and
        *outValue is JS_EXCEPTION).
*/
static BOOL SystemInfoGetSystemDataValue(JSContext* context, OOSystemInfo* info, NSString* key, JSValue* outValue)
{
    *outValue = JS_UNDEFINED;

    OOSystemDescriptionManager* systemManager = [UNIVERSE systemManager];
    id propValue = nil;
    // interstellar space needs more work at this stage
    if ([info system] != -1) {
        propValue = [systemManager getProperty:key forSystem:[info system] inGalaxy:[info galaxy]];
    } else {
        propValue = [info valueForKey:key];
    }

    if (propValue == nil)
        return NO;

    if ([propValue isKindOfClass:[NSNumber class]] || OOIsNumberLiteral([propValue description], YES)) {
        *outValue = JS_NewNumber(context, [propValue doubleValue]);
    } else {
        *outValue = [propValue oo_jsValueInContext:context];
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
    NSString* key = (info != nil) ? SystemInfoKeyForAtom(context, prop) : nil;
    JSValue value;

    /*	SpiderMonkey reported the fixed (shared permanent) properties as own
            properties, so they win over system data keys of the same name
            (notably "coordinates"). They are hidden, but a name that is also a
            system data key is reported as enumerable, since the SpiderMonkey
            enumerate hook listed every system data key.
    */
    int shared = OOJSGetSharedPermanentOwnProperty(context, desc, obj, prop);
    if (shared != 0) {
        if (shared > 0 && desc != NULL && key != nil) {
            if (SystemInfoGetSystemDataValue(context, info, key, &value)) {
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

    if (key == nil)
        return false; // Prototype (no dynamic properties) or symbol.

    if (!SystemInfoGetSystemDataValue(context, info, key, &value)) {
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

    // The fixed (shared permanent) properties, as for other wrapper classes.
    JSPropertyEnum* shared = NULL;
    uint32_t sharedCount = 0;
    if (OOJSGetSharedPermanentOwnPropertyNames(context, &shared, &sharedCount, obj) < 0)
        return -1;

    OOSystemInfo* info = SystemInfoForObject(obj);
    NSArray* keys = [info allKeys];
    NSUInteger count = [keys count];
    assert(count <= INT32_MAX - sharedCount);

    JSPropertyEnum* tab = js_mallocz(context, sizeof *tab * (count + sharedCount + 1));
    if (tab == NULL) {
        JS_FreePropertyEnum(context, shared, sharedCount);
        return -1;
    }

    // System data keys (all enumerable; the SpiderMonkey enumerate hook listed exactly these).
    uint32_t i = 0;
    for (NSString* key in keys) {
        JSAtom atom = JS_NewAtom(context, [[key description] UTF8String]);
        if (atom == JS_ATOM_NULL) {
            JS_FreePropertyEnum(context, tab, i);
            JS_FreePropertyEnum(context, shared, sharedCount);
            return -1;
        }
        tab[i].atom = atom;
        tab[i].is_enumerable = true;
        i++;
    }

    /*	Then the fixed properties not already listed (QuickJS does not remove
            duplicates; "coordinates" is usually also a system data key). These are
            hidden, so only Object.getOwnPropertyNames() sees the extra names.
            NOTE: SpiderMonkey's JSCLASS_NEW_ENUMERATE hook replaced enumeration
            entirely, so there Object.getOwnPropertyNames() returned only the
            system data keys.
    */
    uint32_t keyCount = i;
    for (uint32_t j = 0; j < sharedCount; j++) {
        BOOL duplicate = NO;
        for (uint32_t k = 0; k < keyCount; k++) {
            if (tab[k].atom == shared[j].atom) {
                duplicate = YES;
                break;
            }
        }
        if (!duplicate) {
            tab[i].atom = JS_DupAtom(context, shared[j].atom);
            tab[i].is_enumerable = false;
            i++;
        }
    }
    JS_FreePropertyEnum(context, shared, sharedCount);

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
    NSString* key = SystemInfoKeyForAtom(context, prop);
    if (info != nil && key != nil) {
        [info setValue:nil forKey:key];
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

    NSString* key = SystemInfoKeyForAtom(context, prop);
    if (key == nil)
        return JS_UNDEFINED;

    JSValue value;
    SystemInfoGetSystemDataValue(context, info, key, &value);
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
    NSString* key = SystemInfoKeyForAtom(context, prop);
    if (info == nil || key == nil || !JS_IsObject(receiver) || JS_VALUE_GET_PTR(receiver) != JS_VALUE_GET_PTR(obj)) {
        // Ordinary property (prototype object, symbol, or inherited by another object).
        return JS_DefinePropertyValue(context, receiver, prop, JS_DupValue(context, value), JS_PROP_C_W_E);
    }

    [info setValue:OOStringFromJSValue(context, value) forKey:key];
    return true;

    OOJS_EXOTIC_EXIT(context, -1)
}

// *** Fixed properties ***

static JSValue SystemInfoGetProperty(OOJS_GETTER_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    OOSystemInfo* info = OOJSNativeObjectOfClassFromJSObject(context, this, [OOSystemInfo class]);
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
            OOJSReportError(context, @"Cannot read systemInfo values for %@.", savedInterstellarInfo ? @"invalid interstellar space reference" : @"other galaxies");
            return OOJSNativeFailure(context);
        }
        break;

    case kSystemInfo_internalCoordinates:
        if (sameGalaxy && !savedInterstellarInfo) {
            OOJS_RETURN_WITH_HELPER(NSPointToVectorJSValue, [info coordinates]);
        } else {
            OOJSReportError(context, @"Cannot read systemInfo values for %@.", savedInterstellarInfo ? @"invalid interstellar space reference" : @"other galaxies");
            return OOJSNativeFailure(context);
        }
        break;

    case kSystemInfo_galaxyID:
        return JS_NewInt32(context, [info galaxy]);

    case kSystemInfo_systemID:
        return JS_NewInt32(context, [info system]);

    default:
        OOJSReportBadPropertySelector(context, this, magic, sSystemInfoProperties, OOJS_COUNT(sSystemInfoProperties));
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
        OOJSReportBadArguments(context, @"SystemInfo", @"distanceToSystem", MIN(argc, 1), OOJS_ARGV, nil, @"system info");
        return OOJSNativeFailure(context);
    }

    BOOL sameGalaxy = ([thisInfo galaxy] == [otherInfo galaxy]);
    if (!sameGalaxy) {
        OOJSReportErrorForCaller(context, @"SystemInfo", @"distanceToSystem", @"Cannot calculate distance for systems in other galaxies.");
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
    NSDictionary* result = nil;
    OORouteType routeType = OPTIMIZED_BY_JUMPS;

    if (!JSSystemInfoGetSystemInfo(context, OOJS_THIS, &thisInfo))
        return OOJSNativeFailure(context);
    if (argc < 1 || !JS_IsObject(OOJS_ARGV[0]) || !JSSystemInfoGetSystemInfo(context, OOJS_ARGV[0], &otherInfo)) {
        OOJSReportBadArguments(context, @"SystemInfo", @"routeToSystem", MIN(argc, 1), OOJS_ARGV, nil, @"system info");
        return OOJSNativeFailure(context);
    }

    BOOL sameGalaxy = ([thisInfo galaxy] == [otherInfo galaxy]);
    if (!sameGalaxy) {
        OOJSReportErrorForCaller(context, @"SystemInfo", @"routeToSystem", @"Cannot calculate route for destinations in other galaxies.");
        return OOJSNativeFailure(context);
    }

    if (argc >= 2) {
        routeType = StringToRouteType(OOStringFromJSValue(context, OOJS_ARGV[1]));
    }

    OOJS_BEGIN_FULL_NATIVE(context)
    result = [UNIVERSE routeFromSystem:[thisInfo system] toSystem:[otherInfo system] optimizedBy:routeType];
    OOJS_END_FULL_NATIVE

    OOJS_RETURN_OBJECT(result);

    OOJS_NATIVE_EXIT
}

// samplePrice(commodity)
static JSValue SystemInfoSamplePrice(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    OOSystemInfo* thisInfo = nil;

    if (!JSSystemInfoGetSystemInfo(context, OOJS_THIS, &thisInfo))
        return OOJSNativeFailure(context);
    OOCommodityType commodity = OOStringFromJSValue(context, OOJS_ARGV[0]);
    if (EXPECT_NOT(![[UNIVERSE commodities] goodDefined:commodity])) {
        OOJSReportBadArguments(context, @"SystemInfo", @"samplePrice", MIN(argc, 1), OOJS_ARGV, NULL, @"Unrecognised commodity type");
        return OOJSNativeFailure(context);
    }

    BOOL sameGalaxy = ([thisInfo galaxy] == [PLAYER galaxyNumber]);
    if (!sameGalaxy) {
        OOJSReportErrorForCaller(context, @"SystemInfo", @"samplePrice", @"Cannot calculate sample price for destinations in other galaxies.");
        return OOJSNativeFailure(context);
    }

    OOCreditsQuantity price = [[UNIVERSE commodities] samplePriceForCommodity:commodity inEconomy:[[thisInfo valueForKey:@"economy"] intValue] withScript:[thisInfo valueForKey:@"commodity_script"] inSystem:[thisInfo system]];

    return JS_NewNumber(context, price);

    OOJS_NATIVE_EXIT
}

static JSValue SystemInfoSetPropertyMethod(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    OOSystemInfo* thisInfo = nil;

    if (!JSSystemInfoGetSystemInfo(context, OOJS_THIS, &thisInfo))
        return OOJSNativeFailure(context);

    NSString* property = nil;
    id value = nil;
    NSString* manifest = nil;

    int32_t iValue;

    if (argc < 3) {
        OOJSReportBadArguments(context, @"SystemInfo", @"setProperty", MIN(argc, 3), OOJS_ARGV, NULL, @"setProperty(layer, property, value [,manifest])");
        return OOJSNativeFailure(context);
    }
    if (!OOJSValueToInt32(context, OOJS_ARGV[0], &iValue)) {
        OOJSReportBadArguments(context, @"SystemInfo", @"setProperty", MIN(argc, 3), OOJS_ARGV, NULL, @"setProperty(layer, property, value [,manifest])");
        return OOJSNativeFailure(context);
    }
    if (iValue < 0 || iValue >= OO_SYSTEM_LAYERS) {
        OOJSReportBadArguments(context, @"SystemInfo", @"setProperty", MIN(argc, 3), OOJS_ARGV, NULL, @"layer must be 0, 1, 2 or 3");
        return OOJSNativeFailure(context);
    }
    OOSystemLayer layer = (OOSystemLayer)iValue;

    property = OOStringFromJSValue(context, OOJS_ARGV[1]);
    if (!JS_IsNull(OOJS_ARGV[2])) {
        value = OOJSNativeObjectFromJSValue(context, OOJS_ARGV[2]);
    }
    if (argc >= 4) {
        manifest = OOStringFromJSValue(context, OOJS_ARGV[3]);
    } else {
        manifest = [[OOJSScript currentlyRunningScript] propertyNamed:kLocalManifestProperty];
    }

    [UNIVERSE setSystemDataForGalaxy:[thisInfo galaxy] planet:[thisInfo system] key:property value:value fromManifest:manifest forLayer:layer];

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
        OOJSReportBadArguments(context, @"SystemInfo", @"filteredSystems", argc, OOJS_ARGV, nil, @"this and predicate function");
        return OOJSNativeFailure(context);
    }
    JSValueConst jsThis = OOJS_ARGV[0];
    JSValueConst predicate = OOJS_ARGV[1];

    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
    NSMutableArray* result = [NSMutableArray arrayWithCapacity:256];
    JSValue rval = JS_UNDEFINED;

    // Not OOJS_BEGIN_FULL_NATIVE() - we use JSAPI while paused.
    OOJSPauseTimeLimiter();

    // Iterate over systems.
    BOOL OK = result != nil;
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
                [result addObject:info];
            } else if (boolVal < 0) {
                JS_FreeValue(context, JS_GetException(context));
            }
        }
        JS_FreeValue(context, callResult);

        if (!OK)
            break;
    }

    if (OK) {
        rval = [result oo_jsValueInContext:context];
    } else {
        rval = OOJSNativeFailure(context);
    }

    [pool release];

    OOJSResumeTimeLimiter();
    return rval;

    OOJS_NATIVE_EXIT
}

static JSValue SystemInfoStaticSetInterstellarProperty(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    NSString* property = nil;
    id value = nil;
    NSString* manifest = nil;

    int32_t iValue;
    OOGalaxyID g;
    OOSystemID s1, s2;

    if (argc < 6) {
        OOJSReportBadArguments(context, @"SystemInfo", @"setInterstellarProperty", MIN(argc, 3), OOJS_ARGV, NULL, @"setProperty(galaxy, fromsystem, tosystem, layer, property, value [,manifest])");
        return OOJSNativeFailure(context);
    }
    if (!OOJSValueToInt32(context, OOJS_ARGV[0], &iValue)) {
        OOJSReportBadArguments(context, @"SystemInfo", @"setInterstellarProperty", MIN(argc, 3), OOJS_ARGV, NULL, @"setProperty(galaxy, fromsystem, tosystem, layer, property, value [,manifest])");
        return OOJSNativeFailure(context);
    }
    if (iValue < 0 || iValue > kOOMaximumGalaxyID) {
        OOJSReportBadArguments(context, @"SystemInfo", @"setInterstellarProperty", MIN(argc, 3), OOJS_ARGV, NULL, @"galaxy out of range");
        return OOJSNativeFailure(context);
    } else {
        g = (OOGalaxyID)iValue;
    }

    if (!OOJSValueToInt32(context, OOJS_ARGV[1], &iValue)) {
        OOJSReportBadArguments(context, @"SystemInfo", @"setInterstellarProperty", MIN(argc, 3), OOJS_ARGV, NULL, @"setProperty(galaxy, fromsystem, tosystem, layer, property, value [,manifest])");
        return OOJSNativeFailure(context);
    }
    if (iValue < 0 || iValue > kOOMaximumSystemID) {
        OOJSReportBadArguments(context, @"SystemInfo", @"setInterstellarProperty", MIN(argc, 3), OOJS_ARGV, NULL, @"fromsystem out of range");
        return OOJSNativeFailure(context);
    } else {
        s1 = (OOSystemID)iValue;
    }

    if (!OOJSValueToInt32(context, OOJS_ARGV[2], &iValue)) {
        OOJSReportBadArguments(context, @"SystemInfo", @"setInterstellarProperty", MIN(argc, 3), OOJS_ARGV, NULL, @"setProperty(galaxy, fromsystem, tosystem, layer, property, value [,manifest])");
        return OOJSNativeFailure(context);
    }
    if (iValue < 0 || iValue > kOOMaximumSystemID) {
        OOJSReportBadArguments(context, @"SystemInfo", @"setInterstellarProperty", MIN(argc, 3), OOJS_ARGV, NULL, @"tosystem out of range");
        return OOJSNativeFailure(context);
    } else {
        s2 = (OOSystemID)iValue;
    }

    if (!OOJSValueToInt32(context, OOJS_ARGV[3], &iValue)) {
        OOJSReportBadArguments(context, @"SystemInfo", @"setInterstellarProperty", MIN(argc, 3), OOJS_ARGV, NULL, @"setProperty(galaxy, fromsystem, tosystem, layer, property, value [,manifest])");
        return OOJSNativeFailure(context);
    }
    if (iValue < 0 || iValue >= OO_SYSTEM_LAYERS) {
        OOJSReportBadArguments(context, @"SystemInfo", @"setInterstellarProperty", MIN(argc, 3), OOJS_ARGV, NULL, @"layer must be 0, 1, 2 or 3");
        return OOJSNativeFailure(context);
    }
    OOSystemLayer layer = (OOSystemLayer)iValue;

    property = OOStringFromJSValue(context, OOJS_ARGV[4]);
    if (!JS_IsNull(OOJS_ARGV[5])) {
        value = OOJSNativeObjectFromJSValue(context, OOJS_ARGV[5]);
    }
    if (argc >= 7) {
        manifest = OOStringFromJSValue(context, OOJS_ARGV[6]);
    } else {
        manifest = [[OOJSScript currentlyRunningScript] propertyNamed:kLocalManifestProperty];
    }

    NSString* key = [NSString stringWithFormat:@"interstellar: %u %u %u", g, s1, s2];

    [[UNIVERSE systemManager] setProperty:property forSystemKey:key andLayer:layer toValue:value fromManifest:manifest];

    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}
