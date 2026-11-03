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

/*	REFERENCE OWNERSHIP CONVENTIONS

        SpiderMonkey values were traced by the garbage collector and never freed
        explicitly. QuickJS values are reference counted, so every JSValue is
        either owned (the holder must eventually JS_FreeValue() it, or hand it
        on) or borrowed (JSValueConst; the holder must not free it).

        1. Parameters typed JSValueConst are borrowed. Native callbacks never free
           their this value or arguments.
        2. JSValues returned from functions, and JSValues stored through out
           parameters (e.g. VectorToJSValue(context, v, &outValue)), are owned by
           the caller. This includes -oo_jsValueInContext:,
           OOJSValueFromNativeObject() and OOJSSTR(). On failure the out
           parameter is left as JS_UNDEFINED and need not be freed.
        3. OOJS_RETURN(v) and friends transfer ownership of v to QuickJS.
        4. A native object that keeps a JSValue (the old JS_Add*Root pattern) owns
           a reference and must free it when done, and on
           kOOJavaScriptEngineWillResetNotification. If the JS object can reach
           back to the native object strongly, the reference must also be
           reported from the class gc_mark hook so the cycle collector can see
           it. Back references from JS to native objects use weak references,
           as before.
        5. Errors: a native that fails throws (OOJSReport*Error) and returns
           JS_EXCEPTION. Code calling into JS from Objective-C reports a pending
           exception with OOJSReportPendingException().
        6. Property IDs (JSAtom) from OOJSID() and OOJSIDFromString() are
           interned for the life of the process and are never freed.

        There is one runtime for the life of the process. -reset replaces the
        context (and so the global object and all prototypes), but class IDs and
        atoms survive.
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

#define OOJSENGINE_MONITOR_SUPPORT OO_DEBUG_MONITOR_ENABLED

/*	Profiling of native functions (the debug console's profile(), getProfile()
        and trace()), as in SpiderMonkey builds without MOZ_TRACE_JSCALLS: time
        is attributed to natives bracketed by OOJS_NATIVE_ENTER/EXIT or
        OOJS_PROFILE_ENTER/EXIT, and everything else counts as JavaScript time.
*/
#define OOJS_PROFILE (OOLITE_DEBUG && !OOJS_POC_HARNESS)

// Number of entries in a JSCFunctionListEntry (or other) array.
#define OOJS_COUNT(array) (sizeof(array) / sizeof *(array))

#import "OOJSPropID.h"

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

// There is only one context, created on the main thread.
OOINLINE JSContext* OOJSAcquireContext(void)
{
    extern JSContext* gOOJSMainThreadContext;
    OOCAssert(gOOJSMainThreadContext != NULL, "Attempt to use JavaScript context before JavaScript engine is initialized.");
    return gOOJSMainThreadContext;
}

OOINLINE void OOJSRelinquishContext(JSContext* context)
{
    (void)context;
}

/*	Engine-neutral names, also defined by the SpiderMonkey header, so code
        outside src/Core/Scripting can be built against either engine.
*/
#define OOJSFreeValue(context, value) JS_FreeValue((context), (value))
#define OOJSUndefinedValue() JS_UNDEFINED
#define OOJSNullValue() JS_NULL
OOINLINE BOOL OOJSValueIsUndefined(JSValueConst value)
{
    return JS_IsUndefined(value);
}
OOINLINE JSValue OOJSValueFromDouble(JSContext* context, double value)
{
    return JS_NewNumber(context, value);
}
// JavaScript truthiness (like JS_ValueToBoolean()); NO if conversion throws.
BOOL OOJSValueToBOOL(JSContext* context, JSValueConst value);

/*	OOJSValueToInt32(): replacement for SpiderMonkey's JS_ValueToInt32(),
        which converted to a number and rounded to nearest, failing with an error
        if the result was NaN or out of range. (QuickJS's JS_ToInt32() is ECMA
        ToInt32, which truncates and wraps silently, like JS_ValueToECMAInt32().)
        On failure an exception is pending.
*/
BOOL OOJSValueToInt32(JSContext* context, JSValueConst value, int32_t* outValue);

/*	Script source wrapping.

        SpiderMonkey ran each script with its script object at the head of the
        scope chain, so a bare identifier resolved to a property of the script
        object before the global object (many OXPs rely on this). QuickJS has no
        API for that, but a sloppy-mode with statement provides the same scope
        chain, and strict-mode code nested inside it remains legal. The wrapper
        stays on the first line so line numbers are unchanged.

        Top-level var declarations become local to the script instead of being
        added to the global object (JSOPTION_VAROBJFIX). No known OXP depends
        on that, and it prevents scripts clobbering each other's globals.

        Anything prepended to a script (such as the debug-build "use strict"
        directive) must be added before wrapping: a with statement is a syntax
        error in strict code.
*/
std::string OOJSWrapScriptSource(const std::string& source);

/*	The compatibility script's const rewriter (see RewriteLegacyConst() in
        OOJSScript.m), or JS_UNDEFINED if it failed to load. Kept here rather
        than on the global object so that OXPs can't see or replace it. The
        caller does not own the returned value.
*/
JSValueConst OOJSLegacyConstRewriter(void);

// Report and clear a pending exception, as SpiderMonkey's error reporter did.
void OOJSReportPendingException(JSContext* context);

/*	Notifications sent when JavaScript engine is reset, on oo::NotificationCenter
        (oofnd/Notification.hpp, bead oo-3rb.9), posted with the engine as the object: will-reset
        before the context is destroyed, did-reset after it is recreated.
*/
extern const char* const kOOJavaScriptEngineWillResetNotificationName;
extern const char* const kOOJavaScriptEngineDidResetNotificationName;

/*	Error and warning reporters.

        The error reporters throw an Error. The caller must return JS_EXCEPTION
        (or NO from a BOOL helper whose caller returns JS_EXCEPTION).
        Warnings are logged with the current script location and do not throw.
        The cxx_ forms take printf formats (no %@: pass an object's text as %s with
        oo::DescriptionOf), formatted by oo::str::vformat. A nullopt function means no caller
        prefix; a nullopt scriptClass prefixes "function: ".
*/
void cxx_OOJSReportError(JSContext* context, const char* format, ...) __attribute__((format(printf, 2, 3)));
void cxx_OOJSReportErrorWithArguments(JSContext* context, const char* format, va_list args) __attribute__((format(printf, 2, 0)));
void cxx_OOJSReportErrorForCaller(JSContext* context, const std::optional<std::string>& scriptClass, const std::optional<std::string>& function, const char* format, ...) __attribute__((format(printf, 4, 5)));

void cxx_OOJSReportWarning(JSContext* context, const char* format, ...) __attribute__((format(printf, 2, 3)));
void cxx_OOJSReportWarningWithArguments(JSContext* context, const char* format, va_list args) __attribute__((format(printf, 2, 0)));
void cxx_OOJSReportWarningForCaller(JSContext* context, const std::optional<std::string>& scriptClass, const std::optional<std::string>& function, const char* format, ...) __attribute__((format(printf, 4, 5)));

// Name of the property with the given magic (tinyid) in a property table, for error messages.
std::string cxx_OOStringFromJSPropertyMagic(int magic, const JSCFunctionListEntry* list, size_t count);

void OOJSReportBadPropertySelector(JSContext* context, JSValueConst thisObj, int magic, const JSCFunctionListEntry* list, size_t count);
void OOJSReportBadPropertyValue(JSContext* context, JSValueConst thisObj, int magic, const JSCFunctionListEntry* list, size_t count, JSValueConst value);
// A nullopt message is "Invalid arguments"; a nullopt expectedArgsDescription adds no " -- expected ..." suffix.
void cxx_OOJSReportBadArguments(JSContext* context, const std::optional<std::string>& scriptClass, const std::optional<std::string>& function, int argc, JSValueConst* argv, const std::optional<std::string>& message, const std::optional<std::string>& expectedArgsDescription);

void OOJSReportWrappedException(JSContext* context, id exception);

/*	OOJSNativeFailure()

        SpiderMonkey natives could return NO without reporting an error, which
        silently stopped the running script. A QuickJS native must never return
        JS_EXCEPTION without a pending exception: scripts would catch a bogus
        "[uninitialized]" exception. Natives therefore fail with
                return OOJSNativeFailure(context);
        which returns the pending exception if there is one, and otherwise
        throws an uncatchable error that is not logged, stopping the script as
        before. (Directly after cxx_OOJSReportError(), return JS_EXCEPTION is fine.)
*/
JSValue OOJSNativeFailure(JSContext* context);

/*	OOJSSetWarningOrErrorStackSkip()

        Indicate that the direct call site is not relevant for error handler.
        Currently, if non-zero, no call site information is provided.
*/
void OOJSSetWarningOrErrorStackSkip(unsigned skip);

/*	Get a number from an argument list. NaN is treated as failure, as before.
        The NoError variant leaves no pending exception.
*/
BOOL cxx_OOJSArgumentListGetNumber(JSContext* context, const std::optional<std::string>& scriptClass, const std::optional<std::string>& function, int argc, JSValueConst* argv, double* outNumber, int* outConsumed);
BOOL OOJSArgumentListGetNumberNoError(JSContext* context, int argc, JSValueConst* argv, double* outNumber, int* outConsumed);

OOINLINE JSValue OOJSValueFromBOOL(int b)
{
    return JS_NewBool(NULL, b != 0);
}

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

/*	OOJSValueFromNativeObject()
        Return an owned JavaScript value for an object, or null if passed nil. An
        object whose root class is not OOObject gives undefined, as the NSObject
        glue did; oo-qps.72 deleted the Foundation branch that converted one
        through its property-list form (proposed ADR-0051). Plist data is
        OOJSValueFromPList()'s.
*/
JSValue OOJSValueFromNativeObject(JSContext* context, id object);

/*	OOJSValueFromPList()
        Return the owned JavaScript value representation of a property list,
        exactly as OOJSValueFromNativeObject(context, oo::ObjectFromPList(plist))
        gave it (proposed ADR-0051): null for a null PList; a bool as the number 1
        or 0; an integer as a number; a real as a double (a single-precision one as
        the double of its float); a string as a string; data and dates undefined;
        an array as an Array and a dictionary as an Object (null elements and
        values dropped, empty keys skipped, key order); a PList::Object node as
        OOJSValueFromNativeObject() of its object.
*/
JSValue OOJSValueFromPList(JSContext* context, const oo::PList& plist);

// Like OOJSValueFromNativeObject(), but primitives are boxed. Returns an owned object or JS_EXCEPTION.
JSValue OOJSObjectFromNativeObject(JSContext* context, id object);

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

/**** String utilities ****/

/*	OOJSSTR(const char * [literal])

        An owned string value for a string literal. The string is interned the
        first time the macro is hit.
*/
#define OOJSSTR(str) JS_AtomToString(OOJSAcquireContext(), OOJSID(str))

/*	The JS-to-string converters (proposed ADR-0043). Each returns std::nullopt where the
        Foundation form it replaces returned nil.

        Convert an arbitrary JS value to a UTF-8 string, calling its toString method
        if needed. cxx_OOStringFromJSValue() returns nullopt if value is null or
        undefined, cxx_OOStringFromJSValueEvenIfNull() returns "null" or "undefined".
*/
std::optional<std::string> cxx_OOStringFromJSValue(JSContext* context, JSValueConst value);
std::optional<std::string> cxx_OOStringFromJSValueEvenIfNull(JSContext* context, JSValueConst value);

/*	Describe a value for debugging or error reporting. Strings are quoted,
        escaped and limited in length. Functions are described as "function foo"
        (or just "function" if they're anonymous). Up to four elements of arrays
        are included, followed by total count of there are more than four.
        If abbreviateObjects, the description "[object Object]" is replaced with
        "{...}", which may or may not be clearer depending on context. Never empty of meaning:
        the last fallback is "?".
*/
std::string cxx_OOJSDescribeValue(JSContext* context, JSValueConst value, BOOL abbreviateObjects);

// Name of the value's JS class, e.g. "Vector3D", for error messages.
std::string OOJSClassNameOfValue(JSContext* context, JSValueConst value);

// Convert a property ID to a UTF-8 string (nullopt if it has no string value).
std::optional<std::string> cxx_OOStringFromJSID(JSAtom propID);

// Convert a UTF-8 string to a property ID (interned for the life of the process).
JSAtom cxx_OOJSIDFromString(const std::string& string);

/*	The string helpers of the retired string category (OOJavaScriptExtensions) (bead oo-3rb.199).
        Each std::optional result is nullopt where the category method returned nil.
*/

// For diagnostic messages; produces things like "(42, true, "a string", an object description)".
// nullopt if params is NULL and count is not zero.
std::optional<std::string> cxx_OOJSStringWithJavaScriptParameters(JSValueConst* params, int count, JSContext* context);

// Concatenate sequence of arbitrary JS objects into string (nullopt if count < 1 or values is NULL).
std::optional<std::string> cxx_OOJSConcatenationOfStringsFromJavaScriptValues(JSValueConst* values, size_t count, const std::string& separator, JSContext* context);

// Add escape codes for string so that it's a valid JavaScript literal (if you put "" or '' around it).
std::string cxx_OOJSEscapedForJavaScriptLiteral(std::string_view string);

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

// Class IDs of the standard classes, looked up when the engine starts.
extern JSClassID gOOJSObjectClassID, gOOJSStringClassID, gOOJSArrayClassID, gOOJSNumberClassID, gOOJSBooleanClassID;

/*	cxx_OOJSPListFromJSValue(context, value) / cxx_OOJSPListFromJSObject(context, object)
        The oo::PList form of the native-object family: exactly what oo::PListFrom()
        made of OOJSNativeObjectFromJSValue()'s result (proposed ADR-0051): null for
        null, undefined or an unconvertible value; int32 -> signed integer, double
        -> real, boolean -> bool, string -> string; a JS Array -> array (a null or
        undefined element -> a PList::Object holding [OONull null]); a plain Object
        -> dictionary (see cxx_OOJSDictionaryFromJSObject()); an object of a class
        with a registered converter -> oo::PListFrom() of what the converter
        returns (a private object -> a PList::Object node holding it). The id
        functions below return the object of a PList::Object node of these (nil
        for plist data): oo-qps.72 deleted their Foundation form (ADR-0055
        Amendment 2); every caller asks for a native object.
*/
oo::PList cxx_OOJSPListFromJSValue(JSContext* context, JSValueConst value);
oo::PList cxx_OOJSPListFromJSObject(JSContext* context, JSValueConst object);

id OOJSNativeObjectFromJSValue(JSContext* context, JSValueConst value);
id OOJSNativeObjectFromJSObject(JSContext* context, JSValueConst object);
id OOJSNativeObjectOfClassFromJSValue(JSContext* context, JSValueConst value, Class requiredClass);
id OOJSNativeObjectOfClassFromJSObject(JSContext* context, JSValueConst object, Class requiredClass);

OOINLINE BOOL OOJSValueIsFunction(JSContext* context, JSValueConst value)
{
    return JS_IsFunction(context, value);
}

OOINLINE BOOL OOJSValueIsArray(JSContext* context, JSValueConst value)
{
    return JS_IsArray(value);
}

/*	OOJSDictionaryFromJSValue(context, value)
        cxx_OOJSDictionaryFromJSObject(context, object)

        Converts a JavaScript value to a dictionary by calling
        cxx_OOJSPListFromJSValue() on each of its values (a live object such as
        an entity or OONull stays a PList::Object node); a value that converts to
        null is left out.

        Only enumerable own (i.e., not inherited) properties are included; an
        integer-like property is keyed by its decimal text, as JS itself names it
        (proposed ADR-0051). A value that is not an object or cannot be enumerated
        gives a null PList. This is also how the native-object family converts a
        plain JS Object.
*/
oo::PList OOJSDictionaryFromJSValue(JSContext* context, JSValueConst value);
oo::PList cxx_OOJSDictionaryFromJSObject(JSContext* context, JSValueConst object);

/*	OOJSDictionaryFromStringTable(context, value)

        Treat an arbitrary JavaScript object as a dictionary mapping strings to
        strings, and convert to a corresponding dictionary. The values are
        converted to strings. A null PList if the value is null or not an
        object, or cannot be enumerated.

        Only enumerable own (i.e., not inherited) properties with string keys are
        included.
*/
oo::PList OOJSDictionaryFromStringTable(JSContext* context, JSValueConst value);

/*	Classes

        OOJSRegisterClass() allocates a class ID (once per process; *ioClassID
        must start as 0) and registers the class with the runtime. Prototypes
        are created per context by each class's Init function.

        Oolite reflects part of its class hierarchy as related JS classes whose
        prototypes inherit each other. For instance, JS Entity methods work on JS
        Ships. OOJSRegisterSubclass() records such a relationship, and
        OOJSIsSubclass() tests whether putativeSubclass is equal to superclass
        or a registered subclass of it, recursively.
*/
enum { kOOJSMaxClassID = 1 << 16 }; // QuickJS's limit.

JSClassID OOJSRegisterClass(JSClassID* ioClassID, const JSClassDef* classDef);

// Object.prototype for the current context (owned).
JSValue OOJSObjectPrototype(JSContext* context);
const char* OOJSClassName(JSClassID classID);

void OOJSRegisterSubclass(JSClassID subclass, JSClassID superclass);
BOOL OOJSIsSubclass(JSClassID putativeSubclass, JSClassID superclass);
OOINLINE BOOL OOJSIsMemberOfSubclass(JSContext* context, JSValueConst object, JSClassID superclass)
{
    return JS_IsObject(object) && OOJSIsSubclass(JS_GetClassID(object), superclass);
}

/*	Create the prototype for a class whose instances wrap native objects. As
        with SpiderMonkey's JS_InitClass(), the prototype is itself an instance
        of the class (with no native object), inheriting from parentPrototype
        (Object.prototype if JS_UNDEFINED). If constructor is non-NULL, a global
        constructor function named after the class is also defined.

        The prototype is set as the class prototype for the context; the
        return value is borrowed from there.

        SpiderMonkey reported the properties of a JS_InitClass() prototype
        (JSPROP_SHARED | JSPROP_PERMANENT) as own properties of every instance,
        so Object.keys(), hasOwnProperty() and JSON.stringify() saw them; e.g.
        JSON.stringify(new Vector3D(1, 2, 3)) is {"x":1,"y":2,"z":3}. Classes
        registered with OOJSRegisterClass() and no exotic methods of their own
        reproduce this for the getter/setter properties passed to OOJSInitClass().
        As in SpiderMonkey, only the object's direct prototype counts: a ship's
        Ship properties are own properties, its Entity properties are not.
        Classes with their own exotic methods can call the functions below from
        theirs to get the same behaviour.
*/
int OOJSGetSharedPermanentOwnProperty(JSContext* context, JSPropertyDescriptor* desc, JSValueConst object, JSAtom prop);
int OOJSGetSharedPermanentOwnPropertyNames(JSContext* context, JSPropertyEnum** ptab, uint32_t* plen, JSValueConst object);

JSValueConst OOJSInitClass(JSContext* context, JSValueConst global, JSClassID classID, JSValueConst parentPrototype,
    JSCFunction* constructor, int constructorArgCount,
    const JSCFunctionListEntry* properties, size_t propertyCount,
    const JSCFunctionListEntry* methods, size_t methodCount,
    const JSCFunctionListEntry* staticMethods, size_t staticMethodCount);

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

/*	Support for OOJSNativeObjectFromJSValue() family

        OOJSClassConverterCallback specifies the prototype for a callback function
        which converts a JavaScript object to its property-list form: plist data,
        or a PList::Object node holding a native object (proposed ADR-0055 item 4).

        OOJSBasicPrivateObjectConverter() is a OOJSClassConverterCallback which
        returns the JS object's private storage value as an Object node (a null
        PList for nil). It automatically unpacks OOWeakReferences if relevant.

        OOJSRegisterObjectConverter() registers a callback for a specific JS class.
        It is not automatically propagated to subclasses.
*/
typedef oo::PList (*OOJSClassConverterCallback)(JSContext* context, JSValueConst object);
oo::PList OOJSBasicPrivateObjectConverter(JSContext* context, JSValueConst object);

void OOJSRegisterObjectConverter(JSClassID classID, OOJSClassConverterCallback converter);

// Time limiter. Calls must be balanced, as before; nesting is supported.
#define kOOJSLongTimeLimit (5.0)
void OOJSStartTimeLimiterWithTimeLimit(OOTimeDelta limit);
#define OOJSStartTimeLimiter() OOJSStartTimeLimiterWithTimeLimit(0.0)
void OOJSStopTimeLimiter(void);
void OOJSPauseTimeLimiter(void);
void OOJSResumeTimeLimiter(void);

#ifndef NDEBUG
// Debug console support for the time limiter.
void OOJSResetTimeLimiter(void);
OOTimeDelta OOJSGetTimeLimiterLimit(void);
void OOJSSetTimeLimiterLimit(OOTimeDelta limit);
#endif

/*	OOJSDumpStack()
        Write the current JavaScript stack to the log. QuickJS provides only
        function names and locations, not local variables.
*/
#if OOLITE_DEBUG || defined(OO_DEBUG_MONITOR_ENABLED)
void OOJSDumpStack(JSContext* context);
#else
#define OOJSDumpStack(cx) \
    do {                  \
    } while (0)
#endif

/***** Reusable JS callbacks ****/

/*	OOJSUnconstructableConstruct

        Constructor callback for pseudo-classes which can't be constructed.
*/
JSValue OOJSUnconstructableConstruct(JSContext* context, JSValueConst thisObj, int argc, JSValueConst* argv);

/*	OOJSObjectWrapperFinalize

        Finalizer for JS classes whose private storage is a retained object
        reference (generally an OOWeakReference, but doesn't have to be).
*/
void OOJSObjectWrapperFinalize(JSRuntime* runtime, JSValueConst thisObj);

/*	OOJSObjectWrapperToString

        Implementation of toString() for JS classes whose private storage is an
        Objective-C object reference (generally an OOWeakReference).

        Calls -cxx_oo_jsDescription and, if that fails, -description.
*/
JSValue OOJSObjectWrapperToString(JSContext* context, JSValueConst thisObj, int argc, JSValueConst* argv);

/*	Native function and property callback conveniences.

        Native functions are declared as
                static JSValue Foo(OOJS_NATIVE_ARGS);
        and use OOJS_THIS, OOJS_ARGV and argc as the SpiderMonkey versions did.
        Property callbacks are declared as
                static JSValue FooGetProperty(OOJS_GETTER_ARGS);
                static JSValue FooSetProperty(OOJS_SETTER_ARGS);
        and switch on magic (the old tinyid). A setter receives its value as
        value and returns JS_UNDEFINED on success.
*/
#define OOJS_NATIVE_ARGS JSContext *context, JSValueConst oojsThis, int argc, JSValueConst *oojsArgv
#define OOJS_GETTER_ARGS JSContext *context, JSValueConst thisObj, int magic
#define OOJS_SETTER_ARGS JSContext *context, JSValueConst thisObj, JSValueConst value, int magic
#define OOJS_THIS oojsThis
#define OOJS_ARGV oojsArgv

/*	Replacement for SpiderMonkey's JS_IsConstructing(), valid only in
        constructors created by OOJSInitClass() (JS_CFUNC_constructor_or_func):
        QuickJS passes new.target as this when called with new, and undefined
        when called as a function.
*/
#define OOJS_IS_CONSTRUCTING (!JS_IsUndefined(OOJS_THIS))

#define OOJS_RETURN(v) \
    do {               \
        return (v);    \
    } while (0)
#define OOJS_RETURN_VOID OOJS_RETURN(JS_UNDEFINED)
#define OOJS_RETURN_NULL OOJS_RETURN(JS_NULL)
#define OOJS_RETURN_BOOL(v) OOJS_RETURN(OOJSValueFromBOOL(v))
#define OOJS_RETURN_INT(v) OOJS_RETURN(JS_NewInt32(context, (v)))
#define OOJS_RETURN_DOUBLE(v) OOJS_RETURN(JS_NewFloat64(context, (v)))
#define OOJS_RETURN_OBJECT(o) OOJS_RETURN(OOJSValueFromNativeObject(context, (o)))

/*	PList return slots (proposed ADR-0055 item 4). A native returns C++ values as
        oo::PList, converted by OOJSValueFromPList() (the same JS value
        OOJSValueFromNativeObject() gave for the Foundation object it replaces):

        OOJS_RETURN_PLIST(plist)            the value of <plist> (null for a null PList)
        OOJS_RETURN_STRING_OR_NULL(opt)     a std::optional<std::string>: the string,
                                            or null for nullopt (what nil gave)

        The recipe:

        OOJS_RETURN_OBJECT(oo::NSStringFrom(s))           OOJS_RETURN_PLIST(oo::PList(s))
        OOJS_RETURN_OBJECT(oo::NSStringOrNil(o))          OOJS_RETURN_STRING_OR_NULL(o)
        OOJS_RETURN_OBJECT(oo::ObjectFromPList(p))        OOJS_RETURN_PLIST(p)
        OOJS_RETURN_OBJECT(oo::NSArrayFromObjects(v))     OOJS_RETURN_PLIST(oo::PListFromObjects(v))  (OOObjCPList.h)
        OOJSValueFromNativeObject(context, oo::ObjectFromPList(p))    OOJSValueFromPList(context, p)

        Exemplar: OOJSObjectWrapperToString() in OOJavaScriptEngine.mm.
*/
#define OOJS_RETURN_PLIST(plist) OOJS_RETURN(OOJSValueFromPList(context, (plist)))
#define OOJS_RETURN_STRING_OR_NULL(opt)                                                                     \
    do {                                                                                                    \
        const std::optional<std::string>& oojsOptionalString_ = (opt);                                      \
        OOJS_RETURN_PLIST(oojsOptionalString_.has_value() ? oo::PList(*oojsOptionalString_) : oo::PList()); \
    } while (0)

#define OOJS_RETURN_WITH_HELPER(helper, value)    \
    do {                                          \
        JSValue oojsRVal;                         \
        if (!helper(context, (value), &oojsRVal)) \
            return OOJSNativeFailure(context);    \
        return oojsRVal;                          \
    } while (0)

#define OOJS_RETURN_VECTOR(value) OOJS_RETURN_WITH_HELPER(VectorToJSValue, value)
#define OOJS_RETURN_HPVECTOR(value) OOJS_RETURN_WITH_HELPER(HPVectorToJSValue, value)
#define OOJS_RETURN_QUATERNION(value) OOJS_RETURN_WITH_HELPER(QuaternionToJSValue, value)

/*	OOJS_NATIVE_ENTER()/OOJS_NATIVE_EXIT bracket natives that call into
        Objective-C code which may throw; the exception is converted into a JS
        error. OOJS_PROFILE_ENTER/EXIT bracket natives that cannot throw. When
        OOJS_PROFILE is set, both also record the time spent in the native for
        the profiler.
*/
#if OOJS_PROFILE

#import "OOProfilingStopwatch.h"

/*
        Profiler implementation details. This should be internal to
        OOJSEngineTimeManagement.m, but needs to be declared on the stack by the
        macros below when profiling is enabled.
*/
typedef struct OOJSProfileStackFrame OOJSProfileStackFrame;
struct OOJSProfileStackFrame {
    OOJSProfileStackFrame* back; // Stack link
    const void* key; // Key to look up profile entries: the function name.
    const char* function; // Name of function.
    OOHighResTimeValue startTime; // Time frame was entered.
    OOTimeDelta subTime; // Time spent in subroutine calls.
    OOTimeDelta* total; // Pointer to accumulator for this type of frame.
};

void OOJSProfileEnter(OOJSProfileStackFrame* frame, const char* function);
void OOJSProfileExit(OOJSProfileStackFrame* frame);

/*
        C++ since bead oo-ppc (the Phase 3 scripting-bindings pattern; proposed ADR-0056 amendment
        oo-ppc). The pairs below were Objective-C try, catch (id) and finally blocks. They are now a
        C++ try, a catch (...) and scope guards, so a binding file that uses them contains no
        Objective-C exception syntax. What each one does is unchanged:
          * OOJS_NATIVE_EXIT catches whatever the body throws and hands it to
            OOJSReportCurrentException() (OOJSEngineNativeWrappers.mm), which reports an Objective-C
            exception exactly as OOJSReportWrappedException() did. It also reports a C++ exception
            ("Native exception: <what()>"), which the Objective-C catch (id) could not catch: that
            path ended in std::terminate (ADR-0029 measurement 10). The native then returns
            JS_EXCEPTION.
          * The profiler frame is exited, and the time limiter is resumed, when the scope ends, by
            return or by exception, as the finally blocks did.
*/

// The scope OOJS_PROFILE_ENTER opens: enters the frame, and exits it however the scope ends.
class OOJSProfileScope {
public:
    explicit OOJSProfileScope(const char* function) { OOJSProfileEnter(&_frame, function); }
    ~OOJSProfileScope() { OOJSProfileExit(&_frame); }
    OOJSProfileScope(const OOJSProfileScope&) = delete;
    OOJSProfileScope& operator=(const OOJSProfileScope&) = delete;

private:
    OOJSProfileStackFrame _frame = { };
};

#define OOJS_PROFILE_ENTER_NAMED(NAME)           \
    {                                            \
        OOJSProfileScope oojsProfileScope(NAME); \
        {

#define OOJS_PROFILE_EXIT \
    }                     \
    }

#define OOJS_NATIVE_ENTER(cx)                            \
    {                                                    \
        JSContext* oojsNativeContext = (cx);             \
        OOJSProfileScope oojsProfileScope(__FUNCTION__); \
        try {

#define OOJS_NATIVE_EXIT                               \
    }                                                  \
    catch (...)                                        \
    {                                                  \
        OOJSReportCurrentException(oojsNativeContext); \
        return JS_EXCEPTION;                           \
    }                                                  \
    }

#else

#define OOJS_PROFILE_ENTER_NAMED(NAME) {
#define OOJS_PROFILE_EXIT }

#define OOJS_NATIVE_ENTER(cx)                \
    {                                        \
        JSContext* oojsNativeContext = (cx); \
        try {

#define OOJS_NATIVE_EXIT                               \
    }                                                  \
    catch (...)                                        \
    {                                                  \
        OOJSReportCurrentException(oojsNativeContext); \
        return JS_EXCEPTION;                           \
    }                                                  \
    }

#endif // OOJS_PROFILE

/*	OOJSReportCurrentException()
        Call only inside a catch handler. Reports the exception being handled as a JS error unless
        one is already pending: an Objective-C exception as OOJSReportWrappedException() does, a C++
        one as "Native exception: <what()>" (std::exception) or "Unidentified native exception".
*/
void OOJSReportCurrentException(JSContext* context);

#define OOJS_PROFILE_ENTER OOJS_PROFILE_ENTER_NAMED(__FUNCTION__)
#define OOJS_PROFILE_EXIT_VOID OOJS_PROFILE_EXIT

#define OOJS_BEGIN_FULL_NATIVE(context)                   \
    {                                                     \
        OOJSFullNativeScope oojsFullNativeScope(context); \
        {

#define OOJS_END_FULL_NATIVE \
    }                        \
    }

// The scope OOJS_BEGIN_FULL_NATIVE opens: what its Objective-C try and finally did, in the same order.
class OOJSFullNativeScope {
public:
    explicit OOJSFullNativeScope(JSContext* /*context*/) { OOJSPauseTimeLimiter(); }
    ~OOJSFullNativeScope() { OOJSResumeTimeLimiter(); }
    OOJSFullNativeScope(const OOJSFullNativeScope&) = delete;
    OOJSFullNativeScope& operator=(const OOJSFullNativeScope&) = delete;
};

/***** Property attributes, equivalent to the SpiderMonkey OOJS_PROP_* flags *****/

// Callback-based (JS_CGETSET_MAGIC_DEF2). Read-only properties are defined without a setter.
#define OOJS_PROP_READWRITE_CB JS_PROP_ENUMERABLE
#define OOJS_PROP_READONLY_CB JS_PROP_ENUMERABLE
#define OOJS_PROP_HIDDEN_READWRITE_CB 0
#define OOJS_PROP_HIDDEN_READONLY_CB 0

// Slot-based (JS_DefinePropertyValue*).
#define OOJS_PROP_READWRITE (JS_PROP_ENUMERABLE | JS_PROP_WRITABLE)
#define OOJS_PROP_READONLY JS_PROP_ENUMERABLE
#define OOJS_PROP_HIDDEN_READWRITE JS_PROP_WRITABLE
#define OOJS_PROP_HIDDEN_READONLY 0
#define OOJS_METHOD_READONLY OOJS_PROP_HIDDEN_READONLY

// Property definition shorthands for the common cases.
#define OOJS_PROPERTY_RW(name, getter, setter, magic) JS_CGETSET_MAGIC_DEF2(name, getter, setter, magic, OOJS_PROP_READWRITE_CB)
#define OOJS_PROPERTY_RO(name, getter, magic) JS_CGETSET_MAGIC_DEF2(name, getter, NULL, magic, OOJS_PROP_READONLY_CB)
