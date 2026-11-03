/*

OOJavaScriptEngine+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, beads oo-10qz, oo-903c, oo-elta and oo-k4nu): the Objective-C OOJavaScriptEngine
facade (see OOJavaScriptEngine+ObjCBridge.h). Every method forwards to its C++ member in one line.
Then the OONull and OOJSValue facades, the category on OOObject that forwards to the free
functions holding its bodies (amendment oo-ppc item 3; OONativeVector's went with its facade), and the one-line bridges of OOJavaScriptEngine.mm's free functions (amendment oo-9ht.139).
Deleted with OOJavaScriptEngine+ObjCBridge.h.

JavaScript support for Oolite
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

#import "EntityOOJavaScriptExtensions.h"
#import "OOJavaScriptEngine.h"
#import "OOPlanetEntity.h"
#import "OOVector.h"
#import "OOWeakReference.h"

#include "oofnd/objc/OOObjCPeer.h"

namespace {

// Never destroyed: a facade may be released while the process exits.
oo::ObjCPeers& Peers()
{
    static oo::ObjCPeers* peers = new oo::ObjCPeers;
    return *peers;
}

} // namespace

@interface OOJavaScriptEngine (OOObjCBridgePrivate)

- (id)initWithCxxEngine:(cxx::OOJavaScriptEngine*)engine;

@end

#if OOJSENGINE_MONITOR_SUPPORT

// The Objective-C face of the engine's monitor send (amendment oo-6ia4 item 6); log() in OOJSGlobal.mm
// calls the C++ member directly (bead oo-9ht.98).
@interface OOJavaScriptEngine (OOMonitorSupportInternal)

// nullopt is meaningful to the monitor (Log() with a null message; no class for Log()).
- (void)sendMonitorLogMessage:(const std::optional<std::string>&)message
             withMessageClass:(const std::optional<std::string>&)messageClass
                    inContext:(JSContext*)context;

@end

#endif

@implementation OOJavaScriptEngine

// Inside the @implementation for the private ivar.
OOJavaScriptEngine* oo::ToObjC(cxx::OOJavaScriptEngine* engine)
{
    // One facade for the life of the process, as there was one object (amendment oo-r7m0, item 5): it
    // is the sender of the engine's reset notifications, which observers filter on, so no peer table.
    static OOJavaScriptEngine* facade = nil;
    if (engine == nullptr)
        return nil;
    if (facade == nil)
        facade = [[OOJavaScriptEngine alloc] initWithCxxEngine:engine];
    return facade;
}

cxx::OOJavaScriptEngine* oo::ToCxx(OOJavaScriptEngine* engine)
{
    if (engine == nil)
        return nullptr;
    return engine->_cxxEngine.get();
}

- (id)initWithCxxEngine:(cxx::OOJavaScriptEngine*)engine
{
    self = [super init];
    if (self != nil)
        _cxxEngine = oo::Ref<cxx::OOJavaScriptEngine>(engine);
    return self;
}

+ (OOJavaScriptEngine*)sharedEngine
{
    return oo::ToObjC(cxx::OOJavaScriptEngine::sharedEngine());
}

- (JSContext*)context
{
    return _cxxEngine->context();
}
- (JSValueConst)globalObject
{
    return _cxxEngine->globalObject();
}
- (void)runMissionCallback
{
    _cxxEngine->runMissionCallback();
}
- (BOOL)reset
{
    return _cxxEngine->reset();
}

- (BOOL)callJSFunction:(JSValueConst)function forObject:(JSValueConst)jsThis argc:(int)argc argv:(JSValueConst*)argv result:(JSValue*)outResult
{
    return _cxxEngine->callJSFunction(function, jsThis, argc, argv, outResult);
}

- (void)garbageCollectionOpportunity:(BOOL)force
{
    _cxxEngine->garbageCollectionOpportunity(force);
}
- (BOOL)showErrorLocations
{
    return _cxxEngine->showErrorLocations();
}
- (void)setShowErrorLocations:(BOOL)value
{
    _cxxEngine->setShowErrorLocations(value);
}

#ifdef OO_DEBUG_MONITOR_ENABLED
- (BOOL)dumpStackForErrors
{
    return _cxxEngine->dumpStackForErrors();
}
- (void)setDumpStackForErrors:(BOOL)value
{
    _cxxEngine->setDumpStackForErrors(value);
}
- (BOOL)dumpStackForWarnings
{
    return _cxxEngine->dumpStackForWarnings();
}
- (void)setDumpStackForWarnings:(BOOL)value
{
    _cxxEngine->setDumpStackForWarnings(value);
}
- (void)enableDebuggerStatement
{
    _cxxEngine->enableDebuggerStatement();
}
#endif

- (NSUInteger)shutDown
{
    return _cxxEngine->shutDown();
}

@end

#if OOJSENGINE_MONITOR_SUPPORT

@implementation OOJavaScriptEngine (OOMonitorSupport)

- (void)setMonitor:(id<OOJavaScriptEngineMonitor>)monitor
{
    _cxxEngine->setMonitor(monitor);
}

@end

@implementation OOJavaScriptEngine (OOMonitorSupportInternal)

- (void)sendMonitorLogMessage:(const std::optional<std::string>&)message withMessageClass:(const std::optional<std::string>&)messageClass inContext:(JSContext*)context
{
    _cxxEngine->sendMonitorLogMessage(message, messageClass, context);
}

@end

#endif

@interface OOJSValue (OOObjCBridgePrivate)

- (id)initWithCxxValue:(cxx::OOJSValue*)value;
- (id)initWithNewCxxValue:(oo::Ref<cxx::OOJSValue>)value;

@end

@implementation OOJSValue

// Inside the @implementation for the private ivar.
OOJSValue* oo::ToObjC(cxx::OOJSValue* value)
{
    return Peers().peerFor(value, [value] { return [[OOJSValue alloc] initWithCxxValue:value]; });
}

cxx::OOJSValue* oo::ToCxx(OOJSValue* value)
{
    if (value == nil)
        return nullptr;
    return value->_cxxValue.get();
}

- (id)initWithCxxValue:(cxx::OOJSValue*)value
{
    self = [super init];
    if (self != nil)
        _cxxValue = oo::Ref<cxx::OOJSValue>(value);
    return self;
}

// For -initWithJSValue:inContext:, which callers send after +alloc
// (amendment oo-bhb9 item 3): the facade they made is the peer.
- (id)initWithNewCxxValue:(oo::Ref<cxx::OOJSValue>)value
{
    if (value.get() == nullptr) {
        [self release];
        return nil;
    }

    self = [super init];
    if (self != nil) {
        _cxxValue = std::move(value);
        @autoreleasepool {
            Peers().peerFor(_cxxValue.get(), [self] { return [self retain]; });
        }
    }
    return self;
}

- (void)dealloc
{
    Peers().forget(_cxxValue.get());
    [super dealloc];
}

+ (id)valueWithJSValue:(JSValueConst)value inContext:(JSContext*)context
{
    return oo::ToObjC(cxx::OOJSValue::valueWithJSValue(value, context).get());
}

- (id)initWithJSValue:(JSValueConst)value inContext:(JSContext*)context
{
    return [self initWithNewCxxValue:cxx::OOJSValue::valueWithJSValue(value, context)];
}

- (JSValue)oo_jsValueInContext:(JSContext*)context
{
    return _cxxValue->jsValueInContext(context);
}

@end

@interface OONull (OOObjCBridgePrivate)

- (id)initWithCxxNull:(cxx::OONull*)null;

@end

@implementation OONull

// Inside the @implementation for the private ivar.
OONull* oo::ToObjC(cxx::OONull* null)
{
    // One facade for the one null, for the life of the process: collections and callers compare it
    // by identity (amendments oo-r7m0 item 5 and oo-kq7 item 2), so no peer table.
    static OONull* facade = nil;
    if (null == nullptr)
        return nil;
    if (facade == nil)
        facade = [[OONull alloc] initWithCxxNull:null];
    return facade;
}

cxx::OONull* oo::ToCxx(OONull* null)
{
    if (null == nil)
        return nullptr;
    return null->_cxxNull.get();
}

- (id)initWithCxxNull:(cxx::OONull*)null
{
    self = [super init];
    if (self != nil)
        _cxxNull = oo::Ref<cxx::OONull>(null);
    return self;
}

+ (OONull*)null
{
    return oo::ToObjC(cxx::OONull::null());
}
- (id)copyWithZone:(OOZone*)zone
{
    return [self retain];
}
- (std::optional<std::string>)cxx_description
{
    return _cxxNull->description();
}
- (JSValue)oo_jsValueInContext:(JSContext*)context
{
    return _cxxNull->jsValueInContext(context);
}

@end

// The root class's JS glue (amendment oo-ppc item 3): the bodies are in OOJavaScriptEngine.mm.
@implementation OOObject (OOJavaScriptConversion)

- (JSValue)oo_jsValueInContext:(JSContext*)context
{
    return OOObjectJSValueInContext(context);
}
- (std::optional<std::string>)cxx_oo_jsClassName
{
    return OOObjectJSClassName();
}
- (std::optional<std::string>)cxx_oo_jsDescription
{
    return OOObjectJSDescription(self);
}
- (std::optional<std::string>)cxx_oo_jsDescriptionWithClassName:(const std::optional<std::string>&)className
{
    return OOObjectJSDescriptionWithClassName(self, className);
}
- (void)oo_clearJSSelf:(JSValueConst)selfVal
{
    OOObjectClearJSSelf(selfVal);
}

@end

id OOJavaScriptEngineWeakRefUnderlyingObject(id object)
{
    return [object weakRefUnderlyingObject];
}

Class OOJavaScriptEngineClass(id object)
{
    return [object class];
}

JSValue OOJavaScriptEngineJSValueInContext(id object, JSContext* context)
{
    return [object oo_jsValueInContext:context];
}

std::optional<std::string> OOJavaScriptEngineJSClassName(id object)
{
    return [object cxx_oo_jsClassName];
}

std::optional<std::string> OOJavaScriptEngineJSDescriptionWithClassName(id object, const std::optional<std::string>& className)
{
    return [object cxx_oo_jsDescriptionWithClassName:className];
}

std::optional<std::string> OOJavaScriptEngineDescriptionComponents(id object)
{
    return [object cxx_descriptionComponents];
}

Class OOJavaScriptEngineOOObjectClass()
{
    return [OOObject class];
}

std::optional<std::string> OOJavaScriptEngineJSDescription(id object)
{
    return [object cxx_oo_jsDescription];
}

void OOJavaScriptEngineClearJSSelf(id object, JSValueConst selfVal)
{
    [object oo_clearJSSelf:selfVal];
}

bool OOJavaScriptEngineIsKindOfClass(id object, Class requiredClass)
{
    return [object isKindOfClass:requiredClass];
}

#if !OOJS_POC_HARNESS
bool OOJavaScriptEngineIsVisibleToScripts(Entity* entity)
{
    return [entity isVisibleToScripts];
}

bool OOJavaScriptEngineIsShip(Entity* entity)
{
    return [entity isShip];
}

bool OOJavaScriptEngineIsSubEntity(Entity* entity)
{
    return [entity isSubEntity];
}

bool OOJavaScriptEngineIsPlanet(Entity* entity)
{
    return [entity isPlanet];
}

OOEntityStatus OOJavaScriptEngineStatus(Entity* entity)
{
    return [entity status];
}
#endif
