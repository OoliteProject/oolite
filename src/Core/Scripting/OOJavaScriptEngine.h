/*

OOJavaScriptEngine.h (QuickJS-ng)

JavaScript support for Oolite, ported from SpiderMonkey 1.8.5 to QuickJS-ng.
See https://github.com/OoliteProject/oolite/issues/580.

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

#pragma once

#import "OOFoundation.h"
#import "OOTypes.h"
#include "oofnd/PList.hpp"
#include "oofnd/StdLib.hpp"
#import "oofnd/objc/OOObject.h"
#include <quickjs.h>

#include "oofnd/Ref.hpp"
#include "oofnd/objc/OOAssert.h"
#include "oofnd/objc/OOObjCRef.h"

#if !OOJS_POC_HARNESS
#import "PlayerEntity.h"
#import "PlayerEntityLegacyScriptEngine.h"
#import "Universe.h"
#endif

/*	The plain C++ part of the engine API (bead oo-9ht.72): reporters, converters, argument and
        return macros, the native wrappers. A binding with no Objective-C includes only that header.
*/
#include "OOJSEngineCore.h"

#define OOJSENGINE_MONITOR_SUPPORT OO_DEBUG_MONITOR_ENABLED

#if OOJSENGINE_MONITOR_SUPPORT
#include "OOJavaScriptEngineMonitor.h" // a C++ interface
#endif

/*	The engine (proposed ADR-0056; docs/phases/3-slices/OOJavaScriptEngine.md): the singleton
        that owns the JS runtime and the main thread context. A global class since the deletion of its
        Objective-C facade; it is the sender of its reset notifications.
*/
class OOJavaScriptEngine : public oo::RefCounted {
public:
    // The shared engine, made on first use; borrowed, never released (proposed ADR-0056
    // amendment oo-r7m0).
    static OOJavaScriptEngine* sharedEngine();

    ~OOJavaScriptEngine();

    JSContext* context();
    // The global object, borrowed; invalidated by reset().
    JSValueConst globalObject();

    void runMissionCallback();

    /*	Tear down context and global object and rebuild them from scratch. This
            invalidates globalObject() and all prototypes.
    */
    bool reset();

    // Call a JS function. *outResult (may be NULL) is owned by the caller. Exceptions are reported and cleared.
    bool callJSFunction(JSValueConst function, JSValueConst jsThis, int argc, JSValueConst* argv, JSValue* outResult);

    void garbageCollectionOpportunity(bool force);

    bool showErrorLocations();
    void setShowErrorLocations(bool value);

#ifdef OO_DEBUG_MONITOR_ENABLED
    bool dumpStackForErrors();
    void setDumpStackForErrors(bool value);

    bool dumpStackForWarnings();
    void setDumpStackForWarnings(bool value);

    // Install handler for JS "debugger" statment. (Not supported by QuickJS; does nothing.)
    void enableDebuggerStatement();
#endif

    /*	Destroy the context and runtime. All native objects holding JSValues must
            have released them first. Returns the number of JS objects still alive
            after a final garbage collection; if it is non-zero, they are logged
            and the runtime is abandoned rather than freed.
    */
    NSUInteger shutDown();

#if OOJSENGINE_MONITOR_SUPPORT
    // (OOMonitorSupport)
    void setMonitor(OOJavaScriptEngineMonitor* monitor); // borrowed

    // (OOMonitorSupportInternal)
    // file is nullopt when the stack gives no location (a nil file before).
    void sendMonitorProblem(const std::string& severity, const std::optional<std::string>& file, unsigned line, const std::string& message, JSContext* context);
    // nullopt is meaningful to the monitor (Log() with a null message; no class for Log()).
    void sendMonitorLogMessage(const std::optional<std::string>& message, const std::optional<std::string>& messageClass, JSContext* context);
#endif

private:
    void init(); // -init's body after [super init]: run by sharedEngine() on the new object

    void createMainThreadContext();
    void destroyMainThreadContext();

    JSRuntime* _runtime = nullptr;
    JSContext* _context = nullptr;
    JSValue _globalObject = JS_UNDEFINED; // owned
    bool _showErrorLocations = { };

#ifdef OO_DEBUG_MONITOR_ENABLED
    bool _dumpStackForErrors = { };
    bool _dumpStackForWarnings = { };
#endif
#if OOJSENGINE_MONITOR_SUPPORT
    OOJavaScriptEngineMonitor* _monitor = nullptr; // borrowed: the debug monitor lives as long as the process
#endif
};

/*	The root-class JS glue for classes rooted on OOObject: the category OOObject (OOJavaScript)
        (OOObject+OOJavaScript.h) and the bodies of its default methods, which the category
        forwards to (amendment oo-ppc item 3). OOObjectJSValueInContext() returns an owned value.
*/
JSValue OOObjectJSValueInContext(JSContext* context);
std::optional<std::string> OOObjectJSClassName();
std::optional<std::string> OOObjectJSDescription(id object);
std::optional<std::string> OOObjectJSDescriptionWithClassName(id object, const std::optional<std::string>& className);
void OOObjectClearJSSelf(JSValueConst selfVal);

// A vector box's JS value (OOJSValueFromPList, for an Object node that holds one), owned by the
// caller.
class OONativeVector;
JSValue OONativeVectorJSValueInContext(OONativeVector* vector, JSContext* context);

/*	OONull: the placeholder for null inside native collections, which cannot
        hold nil (was Foundation's null singleton, ADR-0029 Decision 5). A JS array
        element that is null or undefined becomes [OONull null] in the native array, and
        [OONull null] becomes JS null, so JS null round-trips as before. Game code
        uses it where a collection slot is empty (MFD settings, target memory,
        script event arguments). It describes itself as "<null>", as its
        predecessor did, and -copy returns itself. A property list holds it as an
        Object node whose foreign object it is (OONullObjectNode(); the collections held its
        Objective-C facade, which is deleted).
*/
class OONull : public oo::PListForeign {
public:
    // The one null, made on first use; borrowed, never released (amendment oo-r7m0).
    static OONull* null();

    JSValue jsValueInContext(JSContext* context); // JS null

    // oo::PListForeign: what the facade answered (its class, and "%@" as "<null>").
    std::string className() const override;
    std::string description() const override; // "<null>"
};

// The one null as a PList::Object node ([OONull null] through oo::PListObject()), and whether a
// node is that null (oo::ObjectIn(node) == [OONull null]).
inline oo::PList OONullObjectNode()
{
    return oo::PList(oo::PList::Object(oo::Ref<oo::PListForeign>(OONull::null())));
}

inline bool OOIsNullObjectNode(const oo::PList& plist)
{
    const oo::PList::Object* node = plist.getIf<oo::PList::Object>();
    return node != nullptr && node->get() == OONull::null();
}

// OOJSValue is declared in OOJSEngineCore.h (a plain C++ header, so C++-only bindings can use it).

#if !OOJS_POC_HARNESS

class Entity;

// OOEntityFilterPredicate wrapping a JavaScript function.
typedef struct
{
    JSContext* context;
    JSValueConst function; // Caller is responsible for ensuring this is a function object (using OOJSValueIsFunction()).
    JSValueConst jsThis;
    BOOL errorFlag; // Set if a JS exception occurs. The
                    // exception will have been reported.
                    // This also supresses further filtering.
} JSFunctionPredicateParameter;
BOOL JSFunctionPredicate(Entity* entity, void* parameter);

// YES for ships and (normal) planets. Parameter: ignored.
BOOL JSEntityIsJavaScriptVisiblePredicate(Entity* entity, void* parameter);

// YES for ships other than sub-entities and menu-display ships, and planets other than atmospheres and menu miniatures. Parameter: ignored.
BOOL JSEntityIsJavaScriptSearchablePredicate(Entity* entity, void* parameter);

// YES for menu-display ships. Parameter: ignored
BOOL JSEntityIsDemoShipPredicate(Entity* entity, void* parameter);

#endif

/*
        DEFINE_JS_OBJECT_GETTER()
        Defines a helper to extract Objective-C objects from the private field of
        JS objects, with runtime type checking. Weakrefs are automatically
        unpacked.

        Types which extend other types, such as entity subtypes, must register
        their relationships with OOJSRegisterSubclass().

        The signature of the generated function is:
        BOOL <name>(JSContext *context, JSValueConst inObject, <class>** outObject)
        If it returns NO, inObject is of the wrong class and an error has been
        raised. Otherwise, outObject is either a native object of the specified
        class (or a subclass) or nil (for prototypes and stale references).
*/
#define DEFINE_JS_OBJECT_GETTER(NAME, JSCLASSID, OBJCCLASSNAME)                                                \
    static BOOL NAME(JSContext* context, JSValueConst inObject, OBJCCLASSNAME** outObject) GCC_ATTR((unused)); \
    static BOOL NAME(JSContext* context, JSValueConst inObject, OBJCCLASSNAME** outObject)                     \
    {                                                                                                          \
        OOCParameterAssert(outObject != NULL);                                                                 \
        static Class cls = Nil;                                                                                \
        if (EXPECT_NOT(cls == Nil))                                                                            \
            cls = [OBJCCLASSNAME class];                                                                       \
        return OOJSObjectGetterImplPRIVATE(context, inObject, (JSCLASSID), cls, #NAME, (id*)outObject);        \
    }

// For DEFINE_JS_OBJECT_GETTER()'s use.
BOOL OOJSObjectGetterImplPRIVATE(JSContext* context, JSValueConst object, JSClassID requiredClassID, Class requiredObjCClass, const char* name, id* outObject);

// The root class's JS glue and the engine's one-line sends to Objective-C objects (they were in
// the engine's facade file; they go with the root class, Phase 4).
#import "OOObject+OOJavaScript.h"
