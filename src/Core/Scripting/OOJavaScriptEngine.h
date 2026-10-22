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
#include <quickjs.h>

#if !OOJS_POC_HARNESS
#import "PlayerEntity.h"
#import "PlayerEntityLegacyScriptEngine.h"
#import "Universe.h"
#endif

#define OOJSENGINE_MONITOR_SUPPORT OOLITE_DEBUG

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

@interface OOJavaScriptEngine : NSObject {
@private
    JSRuntime* _runtime;
    JSContext* _context;
    JSValue _globalObject;
    BOOL _showErrorLocations;

#ifndef NDEBUG
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

#ifndef NDEBUG
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
        (@"exception" or @"warning") and the innermost location on the stack, if
        any (file is nil otherwise).
*/
@protocol OOJavaScriptEngineMonitor <NSObject>

// Sent for JS errors or warnings.
- (oneway void)jsEngine:(in byref OOJavaScriptEngine*)engine
                context:(in JSContext*)context
      problemOfSeverity:(in NSString*)severity
                 inFile:(in NSString*)file
                   line:(in unsigned)line
              stackSkip:(in unsigned)stackSkip
        showingLocation:(in BOOL)showLocation
            withMessage:(in NSString*)message;

// Sent for JS log messages. Note: messageClass will be nil if Log() is used rather than LogWithClass().
- (oneway void)jsEngine:(in byref OOJavaScriptEngine*)engine
                context:(in JSContext*)context
             logMessage:(in NSString*)message
                ofClass:(in NSString*)messageClass;

@end

@interface OOJavaScriptEngine (OOMonitorSupport)

- (void)setMonitor:(id<OOJavaScriptEngineMonitor>)monitor;

@end

#endif

// There is only one context, created on the main thread.
OOINLINE JSContext* OOJSAcquireContext(void)
{
    extern JSContext* gOOJSMainThreadContext;
    NSCAssert(gOOJSMainThreadContext != NULL, @"Attempt to use JavaScript context before JavaScript engine is initialized.");
    return gOOJSMainThreadContext;
}

OOINLINE void OOJSRelinquishContext(JSContext* context)
{
    (void)context;
}

// Notifications sent when JavaScript engine is reset.
extern NSString* const kOOJavaScriptEngineWillResetNotification;
extern NSString* const kOOJavaScriptEngineDidResetNotification;

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
NSString* OOJSWrapScriptSource(NSString* source);

// Report and clear a pending exception, as SpiderMonkey's error reporter did.
void OOJSReportPendingException(JSContext* context);

/*	Error and warning reporters.

        The error reporters throw an Error. The caller must return JS_EXCEPTION
        (or NO from a BOOL helper whose caller returns JS_EXCEPTION).
        Warnings are logged with the current script location and do not throw.
*/
void OOJSReportError(JSContext* context, NSString* format, ...);
void OOJSReportErrorWithArguments(JSContext* context, NSString* format, va_list args);
void OOJSReportErrorForCaller(JSContext* context, NSString* scriptClass, NSString* function, NSString* format, ...);

void OOJSReportWarning(JSContext* context, NSString* format, ...);
void OOJSReportWarningWithArguments(JSContext* context, NSString* format, va_list args);
void OOJSReportWarningForCaller(JSContext* context, NSString* scriptClass, NSString* function, NSString* format, ...);

// Name of the property with the given magic (tinyid) in a property table, for error messages.
NSString* OOStringFromJSPropertyMagic(int magic, const JSCFunctionListEntry* list, size_t count);

void OOJSReportBadPropertySelector(JSContext* context, JSValueConst thisObj, int magic, const JSCFunctionListEntry* list, size_t count);
void OOJSReportBadPropertyValue(JSContext* context, JSValueConst thisObj, int magic, const JSCFunctionListEntry* list, size_t count, JSValueConst value);
void OOJSReportBadArguments(JSContext* context, NSString* scriptClass, NSString* function, int argc, JSValueConst* argv, NSString* message, NSString* expectedArgsDescription);

void OOJSReportWrappedException(JSContext* context, id exception);

/*	OOJSNativeFailure()

        SpiderMonkey natives could return NO without reporting an error, which
        silently stopped the running script. A QuickJS native must never return
        JS_EXCEPTION without a pending exception: scripts would catch a bogus
        "[uninitialized]" exception. Natives therefore fail with
                return OOJSNativeFailure(context);
        which returns the pending exception if there is one, and otherwise
        throws an uncatchable error that is not logged, stopping the script as
        before. (Directly after OOJSReportError(), return JS_EXCEPTION is fine.)
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
BOOL OOJSArgumentListGetNumber(JSContext* context, NSString* scriptClass, NSString* function, int argc, JSValueConst* argv, double* outNumber, int* outConsumed);
BOOL OOJSArgumentListGetNumberNoError(JSContext* context, int argc, JSValueConst* argv, double* outNumber, int* outConsumed);

OOINLINE JSValue OOJSValueFromBOOL(int b)
{
    return JS_NewBool(NULL, b != 0);
}

@interface NSObject (OOJavaScript)

/*	-oo_jsValueInContext:

        Return the JavaScript value representation of an object, owned by the
        caller. The default implementation returns JS_UNDEFINED.
        If the receiver may be nil, use OOJSValueFromNativeObject() instead.
*/
- (JSValue)oo_jsValueInContext:(JSContext*)context;

/*	-oo_jsDescription
        -oo_jsDescriptionWithClassName:
        -oo_jsClassName

        See comments for -descriptionComponents in OOFoundation.h.
*/
- (NSString*)oo_jsDescription;
- (NSString*)oo_jsDescriptionWithClassName:(NSString*)className;
- (NSString*)oo_jsClassName;

/*	oo_clearJSSelf:
        This is called by OOJSObjectWrapperFinalize() when a JS object wrapper is
        collected. The default implementation does nothing.
*/
- (void)oo_clearJSSelf:(JSValueConst)selfVal;

@end

// Return an owned JavaScript value for an object, or null if passed nil.
OOINLINE JSValue OOJSValueFromNativeObject(JSContext* context, id object)
{
    if (object != nil)
        return [object oo_jsValueInContext:context];
    return JS_NULL;
}

// Like OOJSValueFromNativeObject(), but primitives are boxed. Returns an owned object or JS_EXCEPTION.
JSValue OOJSObjectFromNativeObject(JSContext* context, id object);

/*	OOJSValue: an object whose purpose in life is to hold a JavaScript value.
        This is somewhat useful for putting JavaScript objects in ObjC collections,
        for instance to pass as properties to script loaders. The value is held
        (with its own reference) until the OOJSValue is deallocated or the engine
        is reset.
*/
@interface OOJSValue : NSObject {
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

/*	Convert an arbitrary JS value to an NSString, calling its toString method
        if needed. OOStringFromJSValue() returns nil if value is null or
        undefined, OOStringFromJSValueEvenIfNull() returns "null" or "undefined".
*/
NSString* OOStringFromJSValue(JSContext* context, JSValueConst value);
NSString* OOStringFromJSValueEvenIfNull(JSContext* context, JSValueConst value);

/*	Describe a value for debugging or error reporting. Strings are quoted,
        escaped and limited in length. Functions are described as "function foo"
        (or just "function" if they're anonymous). Up to four elements of arrays
        are included, followed by total count of there are more than four.
        If abbreviateObjects, the description "[object Object]" is replaced with
        "{...}", which may or may not be clearer depending on context.
*/
NSString* OOJSDescribeValue(JSContext* context, JSValueConst value, BOOL abbreviateObjects);

// Name of the value's JS class, e.g. "Vector3D", for error messages.
NSString* OOJSClassNameOfValue(JSContext* context, JSValueConst value);

// Convert a property ID to an NSString.
NSString* OOStringFromJSID(JSAtom propID);

// Convert an NSString to a property ID (interned for the life of the process; JS_ATOM_NULL for nil).
JSAtom OOJSIDFromString(NSString* string);

@interface NSString (OOJavaScriptExtensions)

// For diagnostic messages; produces things like @"(42, true, "a string", an object description)".
+ (NSString*)stringWithJavaScriptParameters:(JSValueConst*)params count:(int)count inContext:(JSContext*)context;

// Concatenate sequence of arbitrary JS objects into string.
+ (NSString*)concatenationOfStringsFromJavaScriptValues:(JSValueConst*)values count:(size_t)count separator:(NSString*)separator inContext:(JSContext*)context;

// Add escape codes for string so that it's a valid JavaScript literal (if you put "" or '' around it).
- (NSString*)escapedForJavaScriptLiteral;

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

// Class IDs of the standard classes, looked up when the engine starts.
extern JSClassID gOOJSObjectClassID, gOOJSStringClassID, gOOJSArrayClassID, gOOJSNumberClassID, gOOJSBooleanClassID;

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
        OOJSDictionaryFromJSObject(context, object)

        Converts a JavaScript value to a dictionary by calling
        OOJSNativeObjectFromJSValue() on each of its values.

        Only enumerable own (i.e., not inherited) properties are included.
        Integer keys become NSNumbers, as before.
*/
NSDictionary* OOJSDictionaryFromJSValue(JSContext* context, JSValueConst value);
NSDictionary* OOJSDictionaryFromJSObject(JSContext* context, JSValueConst object);

/*	OOJSDictionaryFromStringTable(context, value)

        Treat an arbitrary JavaScript object as a dictionary mapping strings to
        strings, and convert to a corresponding NSDictionary. The values are
        converted to strings.

        Only enumerable own (i.e., not inherited) properties with string keys are
        included.
*/
NSDictionary* OOJSDictionaryFromStringTable(JSContext* context, JSValueConst value);

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
        NSCParameterAssert(outObject != NULL);                                                                 \
        static Class cls = Nil;                                                                                \
        if (EXPECT_NOT(cls == Nil))                                                                            \
            cls = [OBJCCLASSNAME class];                                                                       \
        return OOJSObjectGetterImplPRIVATE(context, inObject, (JSCLASSID), cls, #NAME, (id*)outObject);        \
    }

// For DEFINE_JS_OBJECT_GETTER()'s use.
BOOL OOJSObjectGetterImplPRIVATE(JSContext* context, JSValueConst object, JSClassID requiredClassID, Class requiredObjCClass, const char* name, id* outObject);

/*	Support for OOJSNativeObjectFromJSValue() family

        OOJSClassConverterCallback specifies the prototype for a callback function
        which converts a JavaScript object to an Objective-C object.

        OOJSBasicPrivateObjectConverter() is a OOJSClassConverterCallback which
        returns the JS object's private storage value. It automatically unpacks
        OOWeakReferences if relevant.

        OOJSRegisterObjectConverter() registers a callback for a specific JS class.
        It is not automatically propagated to subclasses.
*/
typedef id (*OOJSClassConverterCallback)(JSContext* context, JSValueConst object);
id OOJSBasicPrivateObjectConverter(JSContext* context, JSValueConst object);

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
#ifndef NDEBUG
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
JSValue OOJSUnconstructableConstruct(JSContext* context, JSValueConst this, int argc, JSValueConst* argv);

/*	OOJSObjectWrapperFinalize

        Finalizer for JS classes whose private storage is a retained object
        reference (generally an OOWeakReference, but doesn't have to be).
*/
void OOJSObjectWrapperFinalize(JSRuntime* runtime, JSValueConst this);

/*	OOJSObjectWrapperToString

        Implementation of toString() for JS classes whose private storage is an
        Objective-C object reference (generally an OOWeakReference).

        Calls -oo_jsDescription and, if that fails, -description.
*/
JSValue OOJSObjectWrapperToString(JSContext* context, JSValueConst this, int argc, JSValueConst* argv);

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
#define OOJS_GETTER_ARGS JSContext *context, JSValueConst this, int magic
#define OOJS_SETTER_ARGS JSContext *context, JSValueConst this, JSValueConst value, int magic
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

#define OOJS_PROFILE_ENTER_NAMED(NAME)                \
    {                                                 \
        OOJSProfileStackFrame oojsProfilerStackFrame; \
        @try {                                        \
            OOJSProfileEnter(&oojsProfilerStackFrame, NAME);

#define OOJS_PROFILE_EXIT                         \
    }                                             \
    @finally                                      \
    {                                             \
        OOJSProfileExit(&oojsProfilerStackFrame); \
    }                                             \
    }

#define OOJS_NATIVE_ENTER(cx)                         \
    {                                                 \
        JSContext* oojsNativeContext = (cx);          \
        OOJSProfileStackFrame oojsProfilerStackFrame; \
        @try {                                        \
            OOJSProfileEnter(&oojsProfilerStackFrame, __FUNCTION__);

#define OOJS_NATIVE_EXIT                                          \
    }                                                             \
    @catch (id exception)                                         \
    {                                                             \
        OOJSReportWrappedException(oojsNativeContext, exception); \
        return JS_EXCEPTION;                                      \
    }                                                             \
    @finally                                                      \
    {                                                             \
        OOJSProfileExit(&oojsProfilerStackFrame);                 \
    }                                                             \
    }

#else

#define OOJS_PROFILE_ENTER_NAMED(NAME) {
#define OOJS_PROFILE_EXIT }

#define OOJS_NATIVE_ENTER(cx)                \
    {                                        \
        JSContext* oojsNativeContext = (cx); \
        @try {

#define OOJS_NATIVE_EXIT                                          \
    }                                                             \
    @catch (id exception)                                         \
    {                                                             \
        OOJSReportWrappedException(oojsNativeContext, exception); \
        return JS_EXCEPTION;                                      \
    }                                                             \
    }

#endif // OOJS_PROFILE

#define OOJS_PROFILE_ENTER OOJS_PROFILE_ENTER_NAMED(__FUNCTION__)
#define OOJS_PROFILE_EXIT_VOID OOJS_PROFILE_EXIT

#define OOJS_BEGIN_FULL_NATIVE(context) \
    {                                   \
        (void)(context);                \
        OOJSPauseTimeLimiter();         \
        @try {

#define OOJS_END_FULL_NATIVE     \
    }                            \
    @finally                     \
    {                            \
        OOJSResumeTimeLimiter(); \
    }                            \
    }

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
