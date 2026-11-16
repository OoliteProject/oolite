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

#include "oofnd/objc/OOAssert.h"

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

@class Entity;
@protocol OOJavaScriptEngineMonitor;

@interface OOJavaScriptEngine : OOObject {
@private
    JSRuntime* _runtime;
    JSContext* _context;
    JSValue _globalObject;
    BOOL _showErrorLocations;

#ifdef OO_DEBUG_MONITOR_ENABLED
    BOOL _dumpStackForErrors;
    BOOL _dumpStackForWarnings;
#endif
#if OOJSENGINE_MONITOR_SUPPORT
    id<OOJavaScriptEngineMonitor> _monitor;
#endif
}

+ (OOJavaScriptEngine*)sharedEngine;

- (JSContext*)context;
- (JSValueConst)globalObject;

- (void)runMissionCallback;

/*	Tear down context and global object and rebuild them from scratch. This
        invalidates -globalObject and all prototypes.
*/
- (BOOL)reset;

// Call a JS function. *outResult is owned by the caller. Exceptions are reported and cleared.
- (BOOL)callJSFunction:(JSValueConst)function
             forObject:(JSValueConst)jsThis
                  argc:(int)argc
                  argv:(JSValueConst*)argv
                result:(JSValue*)outResult;

- (void)garbageCollectionOpportunity:(BOOL)force;

- (BOOL)showErrorLocations;
- (void)setShowErrorLocations:(BOOL)value;

#ifdef OO_DEBUG_MONITOR_ENABLED
- (BOOL)dumpStackForErrors;
- (void)setDumpStackForErrors:(BOOL)value;

- (BOOL)dumpStackForWarnings;
- (void)setDumpStackForWarnings:(BOOL)value;

// Install handler for JS "debugger" statment. (Not supported by QuickJS; does nothing.)
- (void)enableDebuggerStatement;
#endif

/*	Destroy the context and runtime. All native objects holding JSValues must
        have released them first. Returns the number of JS objects still alive
        after a final garbage collection; if it is non-zero, they are logged
        and the runtime is abandoned rather than freed.
*/
- (NSUInteger)shutDown;

@end

#if OOJSENGINE_MONITOR_SUPPORT

/*	Protocol for debugging "monitor" object.
        The monitor is an object -- in Oolite, or via Distributed Objects -- which
        is provided with debugging information by the OOJavaScriptEngine.

        QuickJS has no JSErrorReport, so problems are described by severity
        ("exception" or "warning") and the innermost location on the stack, if
        any (file is nullopt otherwise).
*/
@protocol OOJavaScriptEngineMonitor <OOObject>

// Sent for JS errors or warnings.
- (void)jsEngine:(OOJavaScriptEngine*)engine
              context:(JSContext*)context
    problemOfSeverity:(const std::string&)severity
               inFile:(const std::optional<std::string>&)file
                 line:(unsigned)line
            stackSkip:(unsigned)stackSkip
      showingLocation:(BOOL)showLocation
          withMessage:(const std::string&)message;

// Sent for JS log messages. Note: messageClass is nullopt if Log() is used rather than LogWithClass().
- (void)jsEngine:(OOJavaScriptEngine*)engine
         context:(JSContext*)context
      logMessage:(const std::string&)message
         ofClass:(const std::optional<std::string>&)messageClass;

@end

@interface OOJavaScriptEngine (OOMonitorSupport)

- (void)setMonitor:(id<OOJavaScriptEngineMonitor>)monitor;

@end

#endif

/*	The root-class JS glue for classes rooted on OOObject (ADR-0029). An object on another root
        has none: OOJSValueFromNativeObject() gives undefined for it (oo-qps.72).

        -oo_jsValueInContext:

        Return the JavaScript value representation of an object, owned by the
        caller. The default implementation returns JS_UNDEFINED.
        If the receiver may be nil, use OOJSValueFromNativeObject() instead.

        -cxx_oo_jsDescription
        -cxx_oo_jsDescriptionWithClassName:
        -cxx_oo_jsClassName

        They wrap -cxx_descriptionComponents (OODescription.h) as [jsClassName components]. C++ string twins on OOObject.

        oo_clearJSSelf:
        This is called by OOJSObjectWrapperFinalize() when a JS object wrapper is
        collected. The default implementation does nothing.
*/
@interface OOObject (OOJavaScript)

- (JSValue)oo_jsValueInContext:(JSContext*)context;
- (std::optional<std::string>)cxx_oo_jsDescription;
- (std::optional<std::string>)cxx_oo_jsDescriptionWithClassName:(const std::optional<std::string>&)className;
- (std::optional<std::string>)cxx_oo_jsClassName;
- (void)oo_clearJSSelf:(JSValueConst)selfVal;

@end

/*	OONull: the placeholder for null inside native collections, which cannot
        hold nil (was Foundation's null singleton, ADR-0029 Decision 5). A JS array
        element that is null or undefined becomes [OONull null] in the native array, and
        [OONull null] becomes JS null, so JS null round-trips as before. Game code
        uses it where a collection slot is empty (MFD settings, target memory,
        script event arguments). It describes itself as "<null>", as its
        predecessor did, and -copy returns itself.
*/
@interface OONull : OOObject <OOCopying>

+ (OONull*)null;

@end

/*	OOJSValue: an object whose purpose in life is to hold a JavaScript value.
        This is somewhat useful for putting JavaScript objects in ObjC collections,
        for instance to pass as properties to script loaders. The value is held
        (with its own reference) until the OOJSValue is deallocated or the engine
        is reset.
*/
@interface OOJSValue : OOObject {
    JSValue _val;
}

+ (id)valueWithJSValue:(JSValueConst)value inContext:(JSContext*)context;
- (id)initWithJSValue:(JSValueConst)value inContext:(JSContext*)context;

@end

#if !OOJS_POC_HARNESS

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
