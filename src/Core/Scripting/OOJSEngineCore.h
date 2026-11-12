/*

OOJSEngineCore.h

The plain C++ part of the JavaScript engine API, split verbatim out of
OOJavaScriptEngine.h: context acquisition, error reporters, argument helpers,
the value/PList/string converters, class and converter registration, the time
limiter, the native wrappers and the OOJS_* property flags and return macros.
A binding translation unit includes this header instead of OOJavaScriptEngine.h,
which includes it back. id, Class and BOOL are libobjc2's C types.

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

        1. Parameters typed JSValueConst are borrowed. Native callbacks never
   free their this value or arguments.
        2. JSValues returned from functions, and JSValues stored through out
           parameters (e.g. VectorToJSValue(context, v, &outValue)), are owned
   by the caller. This includes -oo_jsValueInContext:,
           OOJSValueFromNativeObject() and OOJSSTR(). On failure the out
           parameter is left as JS_UNDEFINED and need not be freed.
        3. OOJS_RETURN(v) and friends transfer ownership of v to QuickJS.
        4. A native object that keeps a JSValue (the old JS_Add*Root pattern)
   owns a reference and must free it when done, and on
           kOOJavaScriptEngineWillResetNotification. If the JS object can reach
           back to the native object strongly, the reference must also be
           reported from the class gc_mark hook so the cycle collector can see
           it. Back references from JS to native objects use weak references,
           as before.
        5. Errors: a native that fails throws (OOJSReport*Error) and returns
           JS_EXCEPTION. Code calling into JS reports a pending
           exception with OOJSReportPendingException().
        6. Property IDs (JSAtom) from OOJSID() and OOJSIDFromString() are
           interned for the life of the process and are never freed.

        There is one runtime for the life of the process. -reset replaces the
        context (and so the global object and all prototypes), but class IDs and
        atoms survive.
*/

#pragma once

#include <quickjs.h>

#include <algorithm>
#include <chrono>
#include <condition_variable>
#include <cstdarg>
#include <cstddef>
#include <cstdint>
#include <functional>
#include <map>
#include <memory>
#include <mutex>
#include <optional>
#include <set>
#include <string>
#include <string_view>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <vector>

#include "OOFunctionAttributes.h"
#include "OOJSPropID.h"
#include "OOTypes.h"
#include "oofnd/PList.hpp"
#include "oofnd/Ref.hpp"
#include "oofnd/objc/OOAssert.h"
#include "oofnd/objc/OOFoundationTypes.h"

// Number of entries in a JSCFunctionListEntry (or other) array.
#define OOJS_COUNT(array) (sizeof(array) / sizeof *(array))

// There is only one context, created on the main thread.
OOINLINE JSContext* OOJSAcquireContext(void) {
  extern JSContext* gOOJSMainThreadContext;
  OOCAssert(gOOJSMainThreadContext != NULL,
            "Attempt to use JavaScript context before JavaScript engine is "
            "initialized.");
  return gOOJSMainThreadContext;
}

OOINLINE void OOJSRelinquishContext(JSContext* context) { (void)context; }

/*	Engine-neutral names, also defined by the SpiderMonkey header, so code
        outside src/Core/Scripting can be built against either engine.
*/
#define OOJSFreeValue(context, value) JS_FreeValue((context), (value))
#define OOJSUndefinedValue() JS_UNDEFINED
#define OOJSNullValue() JS_NULL
OOINLINE bool OOJSValueIsUndefined(JSValueConst value) {
  return JS_IsUndefined(value);
}
OOINLINE JSValue OOJSValueFromDouble(JSContext* context, double value) {
  return JS_NewNumber(context, value);
}
// JavaScript truthiness (like JS_ValueToBoolean()); NO if conversion throws.
bool OOJSValueToBOOL(JSContext* context, JSValueConst value);

/*	OOJSValueToInt32(): replacement for SpiderMonkey's JS_ValueToInt32(),
        which converted to a number and rounded to nearest, failing with an
   error if the result was NaN or out of range. (QuickJS's JS_ToInt32() is ECMA
        ToInt32, which truncates and wraps silently, like
   JS_ValueToECMAInt32().) On failure an exception is pending.
*/
bool OOJSValueToInt32(JSContext* context, JSValueConst value,
                      int32_t* outValue);

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
        OOJSScript), or JS_UNDEFINED if it failed to load. Kept here rather
        than on the global object so that OXPs can't see or replace it. The
        caller does not own the returned value.
*/
JSValueConst OOJSLegacyConstRewriter(void);

// Report and clear a pending exception, as SpiderMonkey's error reporter did.
void OOJSReportPendingException(JSContext* context);

/*	Notifications sent when JavaScript engine is reset, on
   oo::NotificationCenter (oofnd/Notification.hpp), posted with
   the engine as the object: will-reset before the context is destroyed,
   did-reset after it is recreated.
*/
extern const char* const kOOJavaScriptEngineWillResetNotificationName;
extern const char* const kOOJavaScriptEngineDidResetNotificationName;

/*	Error and warning reporters.

        The error reporters throw an Error. The caller
        must return JS_EXCEPTION
        (or NO from a BOOL helper whose caller returns JS_EXCEPTION).
        Warnings are logged with the current script location and do not throw.
        The cxx_ forms take printf formats (no %@: pass an object's text as %s
   with oo::DescriptionOf), formatted by oo::str::vformat. A nullopt function
   means no caller prefix; a nullopt scriptClass prefixes "function: ".
*/
void cxx_OOJSReportError(JSContext* context, const char* format, ...)
    OO_PRINTF_FORMAT(2, 3);
void cxx_OOJSReportErrorWithArguments(JSContext* context, const char* format,
                                      va_list args) OO_PRINTF_FORMAT(2, 0);
void cxx_OOJSReportErrorForCaller(JSContext* context,
                                  const std::optional<std::string>& scriptClass,
                                  const std::optional<std::string>& function,
                                  const char* format, ...)
    OO_PRINTF_FORMAT(4, 5);

void cxx_OOJSReportWarning(JSContext* context, const char* format, ...)
    OO_PRINTF_FORMAT(2, 3);
void cxx_OOJSReportWarningWithArguments(JSContext* context, const char* format,
                                        va_list args) OO_PRINTF_FORMAT(2, 0);
void cxx_OOJSReportWarningForCaller(
    JSContext* context, const std::optional<std::string>& scriptClass,
    const std::optional<std::string>& function, const char* format, ...)
    OO_PRINTF_FORMAT(4, 5);

// Name of the property with the given magic (tinyid) in a property table, for
// error messages.
std::string cxx_OOStringFromJSPropertyMagic(int magic,
                                            const JSCFunctionListEntry* list,
                                            size_t count);

void OOJSReportBadPropertySelector(JSContext* context, JSValueConst thisObj,
                                   int magic, const JSCFunctionListEntry* list,
                                   size_t count);
void OOJSReportBadPropertyValue(JSContext* context, JSValueConst thisObj,
                                int magic, const JSCFunctionListEntry* list,
                                size_t count, JSValueConst value);
// A nullopt message is "Invalid arguments"; a nullopt expectedArgsDescription
// adds no " -- expected ..." suffix.
void cxx_OOJSReportBadArguments(
    JSContext* context, const std::optional<std::string>& scriptClass,
    const std::optional<std::string>& function, int argc, JSValueConst* argv,
    const std::optional<std::string>& message,
    const std::optional<std::string>& expectedArgsDescription);

/*	OOJSNativeFailure()

        SpiderMonkey natives could return NO without reporting an error, which
        silently stopped the running script. A QuickJS native must never return
        JS_EXCEPTION without a pending exception: scripts would catch a bogus
        "[uninitialized]" exception. Natives therefore fail with
                return OOJSNativeFailure(context);
        which returns the pending exception if there is one, and otherwise
        throws an uncatchable error that is not logged, stopping the script as
        before. (Directly after cxx_OOJSReportError(), return JS_EXCEPTION is
   fine.)
*/
JSValue OOJSNativeFailure(JSContext* context);

/*	OOJSSetWarningOrErrorStackSkip()

        Indicate that the direct call site is not relevant for error handler.
        Currently, if non-zero, no call site information is provided.
*/
void OOJSSetWarningOrErrorStackSkip(unsigned skip);

/*	Get a number from an argument list. NaN is treated as failure, as
   before. The NoError variant leaves no pending exception.
*/
bool cxx_OOJSArgumentListGetNumber(
    JSContext* context, const std::optional<std::string>& scriptClass,
    const std::optional<std::string>& function, int argc, JSValueConst* argv,
    double* outNumber, int* outConsumed);
bool OOJSArgumentListGetNumberNoError(JSContext* context, int argc,
                                      JSValueConst* argv, double* outNumber,
                                      int* outConsumed);

OOINLINE JSValue OOJSValueFromBOOL(int b) { return JS_NewBool(NULL, b != 0); }

/*	OOJSValueFromPList()
        Return the owned JavaScript value representation of a property list,
   exactly as OOJSValueFromNativeObject(context, oo::ObjectFromPList(plist))
   gave it: null for a null PList; a bool as the number 1 or 0; an integer as a
   number; a real as a double (a single-precision one as the double of its
   float); a string as a string; data and dates undefined; an array as an Array
   and a dictionary as an Object (null elements and values dropped, empty keys
   skipped, key order); a PList::Object node as its C++ object's JS glue.

        Requires a request on context.
*/
JSValue OOJSValueFromPList(JSContext* context, const oo::PList& plist);

/**** String utilities ****/

/*	OOJSSTR(const char * [literal])

        An owned string value for a string literal. The string is interned the
        first time the macro is hit.
*/
#define OOJSSTR(str) JS_AtomToString(OOJSAcquireContext(), OOJSID(str))

/*	The JS-to-string converters. Each returns std::nullopt where the
        Foundation form it replaces returned nil.

        Convert an arbitrary JS value to a UTF-8 string, calling its toString
   method if needed. cxx_OOStringFromJSValue() returns nullopt if value is null
   or undefined, cxx_OOStringFromJSValueEvenIfNull() returns "null" or
   "undefined".
*/
std::optional<std::string> cxx_OOStringFromJSValue(JSContext* context,
                                                   JSValueConst value);
std::optional<std::string> cxx_OOStringFromJSValueEvenIfNull(
    JSContext* context, JSValueConst value);

/*	Describe a value for debugging or error reporting. Strings are quoted,
        escaped and limited in length. Functions are described as "function foo"
        (or just "function" if they're anonymous). Up to four elements of arrays
        are included, followed by total count of there are more than four.
        If abbreviateObjects, the description "[object Object]" is replaced with
        "{...}", which may or may not be clearer depending on context. Never
   empty of meaning: the last fallback is "?".
*/
std::string cxx_OOJSDescribeValue(JSContext* context, JSValueConst value,
                                  bool abbreviateObjects);

// Name of the value's JS class, e.g. "Vector3D", for error messages.
std::string OOJSClassNameOfValue(JSContext* context, JSValueConst value);

// Convert a property ID to a UTF-8 string (nullopt if it has no string value).
std::optional<std::string> cxx_OOStringFromJSID(JSAtom propID);

// Convert a UTF-8 string to a property ID (interned for the life of the
// process).
JSAtom cxx_OOJSIDFromString(const std::string& string);

/*	The string helpers of the retired string category
   (OOJavaScriptExtensions). Each std::optional result is
   nullopt where the category method returned nil.
*/

// For diagnostic messages; produces things like "(42, true, "a string", an
// object description)". nullopt if params is NULL and count is not zero.
std::optional<std::string> cxx_OOJSStringWithJavaScriptParameters(
    JSValueConst* params, int count, JSContext* context);

// Concatenate sequence of arbitrary JS objects into string (nullopt if count <
// 1 or values is NULL).
std::optional<std::string> cxx_OOJSConcatenationOfStringsFromJavaScriptValues(
    JSValueConst* values, size_t count, const std::string& separator,
    JSContext* context);

// Add escape codes for string so that it's a valid JavaScript literal (if you
// put "" or '' around it).
std::string cxx_OOJSEscapedForJavaScriptLiteral(std::string_view string);

// Class IDs of the standard classes, looked up when the engine starts.
extern JSClassID gOOJSObjectClassID, gOOJSStringClassID, gOOJSArrayClassID,
    gOOJSNumberClassID, gOOJSBooleanClassID;

/*	cxx_OOJSPListFromJSValue(context, value) /
   cxx_OOJSPListFromJSObject(context, object) The oo::PList form of the
   native-object family: exactly what oo::PListFrom() made of
   OOJSNativeObjectFromJSValue()'s result: null for null,
   undefined or an unconvertible value; int32 -> signed integer, double
        -> real, boolean -> bool, string -> string; a JS Array -> array (a null
   or undefined element -> a PList::Object holding [OONull null]); a plain
   Object
        -> dictionary (see cxx_OOJSDictionaryFromJSObject()); an object of a
   class with a registered converter -> oo::PListFrom() of what the converter
        returns (a private object -> a PList::Object node holding it). No slot
        holds an Objective-C object.
*/
oo::PList cxx_OOJSPListFromJSValue(JSContext* context, JSValueConst value);
oo::PList cxx_OOJSPListFromJSObject(JSContext* context, JSValueConst object);

OOINLINE bool OOJSValueIsFunction(JSContext* context, JSValueConst value) {
  return JS_IsFunction(context, value);
}

OOINLINE bool OOJSValueIsArray(JSContext* context, JSValueConst value) {
  return JS_IsArray(value);
}

/*	OOJSDictionaryFromJSValue(context, value)
        cxx_OOJSDictionaryFromJSObject(context, object)

        Converts a JavaScript value to a dictionary by calling
        cxx_OOJSPListFromJSValue() on each of its values (a live object such as
        an entity or OONull stays a PList::Object node); a value that converts
   to null is left out.

        Only enumerable own (i.e., not inherited) properties are included; an
        integer-like property is keyed by its decimal text, as JS itself names
   it. A value that is not an object or cannot be enumerated
        gives a null PList. This is also how the native-object family converts a
        plain JS Object.
*/
oo::PList OOJSDictionaryFromJSValue(JSContext* context, JSValueConst value);
oo::PList cxx_OOJSDictionaryFromJSObject(JSContext* context,
                                         JSValueConst object);

/*	OOJSDictionaryFromStringTable(context, value)

        Treat an arbitrary JavaScript object as a dictionary mapping strings to
        strings, and convert to a corresponding dictionary. The values are
        converted to strings. A null PList if the value is null or not an
        object, or cannot be enumerated.

        Only enumerable own (i.e., not inherited) properties with string keys
   are included.
*/
oo::PList OOJSDictionaryFromStringTable(JSContext* context, JSValueConst value);

/*	Classes

        OOJSRegisterClass() allocates a class ID (once per process; *ioClassID
        must start as 0) and registers the class with the runtime. Prototypes
        are created per context by each class's Init function.

        Oolite reflects part of its class hierarchy as related JS classes whose
        prototypes inherit each other. For instance, JS Entity methods work on
   JS Ships. OOJSRegisterSubclass() records such a relationship, and
        OOJSIsSubclass() tests whether putativeSubclass is equal to superclass
        or a registered subclass of it, recursively.
*/
inline constexpr JSClassID kOOJSMaxClassID = 1 << 16;  // QuickJS's limit.

JSClassID OOJSRegisterClass(JSClassID* ioClassID, const JSClassDef* classDef);

// Object.prototype for the current context (owned).
JSValue OOJSObjectPrototype(JSContext* context);
const char* OOJSClassName(JSClassID classID);

void OOJSRegisterSubclass(JSClassID subclass, JSClassID superclass);
bool OOJSIsSubclass(JSClassID putativeSubclass, JSClassID superclass);
OOINLINE bool OOJSIsMemberOfSubclass(JSContext* context, JSValueConst object,
                                     JSClassID superclass) {
  return JS_IsObject(object) &&
         OOJSIsSubclass(JS_GetClassID(object), superclass);
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
        reproduce this for the getter/setter properties passed to
   OOJSInitClass(). As in SpiderMonkey, only the object's direct prototype
   counts: a ship's Ship properties are own properties, its Entity properties
   are not. Classes with their own exotic methods can call the functions below
   from theirs to get the same behaviour.
*/
int OOJSGetSharedPermanentOwnProperty(JSContext* context,
                                      JSPropertyDescriptor* desc,
                                      JSValueConst object, JSAtom prop);
int OOJSGetSharedPermanentOwnPropertyNames(JSContext* context,
                                           JSPropertyEnum** ptab,
                                           uint32_t* plen, JSValueConst object);

JSValueConst OOJSInitClass(JSContext* context, JSValueConst global,
                           JSClassID classID, JSValueConst parentPrototype,
                           JSCFunction* constructor, int constructorArgCount,
                           const JSCFunctionListEntry* properties,
                           size_t propertyCount,
                           const JSCFunctionListEntry* methods,
                           size_t methodCount,
                           const JSCFunctionListEntry* staticMethods,
                           size_t staticMethodCount);

/*	Support for OOJSNativeObjectFromJSValue() family

        OOJSClassConverterCallback specifies the prototype for a callback
   function which converts a JavaScript object to its property-list form: plist
   data, or a PList::Object node holding a native object.

        OOJSBasicPrivateObjectConverter() is a OOJSClassConverterCallback which
        returns the JS object's private storage value as an Object node (a null
        PList for none). The slot holds a C++ object: a node
        is made of it when it is a PList::Object's foreign object, else none.

        OOJSRegisterObjectConverter() registers a callback for a specific JS
   class. It is not automatically propagated to subclasses.
*/
typedef oo::PList (*OOJSClassConverterCallback)(JSContext* context,
                                                JSValueConst object);
oo::PList OOJSBasicPrivateObjectConverter(JSContext* context,
                                          JSValueConst object);

void OOJSRegisterObjectConverter(JSClassID classID,
                                 OOJSClassConverterCallback converter);

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

/*	OOJSValue: an object whose purpose in life is to hold a JavaScript
   value. This is somewhat useful for putting JavaScript objects in property
   lists, for instance to pass as properties to script loaders. The value is
   held (with its own reference) until the OOJSValue is destroyed or the engine
        is reset. A property list holds it as an Object node: it is its own
   node's foreign object (OOJSValueObjectNode()).
*/
class OOJSValue : public oo::PListForeign {
 public:
  // context may be NULL (the main thread context is used).
  static oo::Ref<OOJSValue> valueWithJSValue(JSValueConst value,
                                             JSContext* context);

  ~OOJSValue();

  // The held value, owned by the caller (a new reference).
  JSValue jsValueInContext(JSContext* context);

  // oo::PListForeign: the class name, and "%@" as <OOJSValue 0x...>.
  std::string className() const override;
  std::string description() const override;

 private:
  // The initialiser after [super init], which could not fail: run by the
  // factory.
  void initWithJSValue(JSValueConst value, JSContext* context);

  void deleteJSValue();

  JSValue _val = JS_UNDEFINED;
  const void* _resetSender = {};  // the engine, the sender of its reset
                                  // notifications, while _val is held
};

// A held value as a PList::Object node ; null -> null PList.
inline oo::PList OOJSValueObjectNode(OOJSValue* value) {
  if (value == nullptr) return oo::PList();
  return oo::PList(oo::PList::Object(oo::Ref<oo::PListForeign>(value)));
}

/*	OOJSDumpStack()
        Write the current JavaScript stack to the log. QuickJS provides only
        function names and locations, not local variables.
*/
#if OOLITE_DEBUG || defined(OO_DEBUG_MONITOR_ENABLED)
void OOJSDumpStack(JSContext* context);
#else
#define OOJSDumpStack(cx) \
  do {                    \
  } while (0)
#endif

/***** Reusable JS callbacks ****/

/*	OOJSUnconstructableConstruct

        Constructor callback for pseudo-classes which can't be constructed.
*/
JSValue OOJSUnconstructableConstruct(JSContext* context, JSValueConst thisObj,
                                     int argc, JSValueConst* argv);

/*	OOJSObjectWrapperFinalize

        Finalizer for JS classes whose private storage is a retained object
        reference: OOJSCxxObjectWrapperFinalize() (OOJSPrivateObject.h), since
   the slot holds only a C++ object.
*/
void OOJSObjectWrapperFinalize(JSRuntime* runtime, JSValueConst thisObj);

/*	OOJSObjectWrapperToString

        Implementation of toString() for JS classes whose private storage is an
        object reference: "[object <JS class name>]" ("[object]" for no class).
        No slot holds an Objective-C object.
*/
JSValue OOJSObjectWrapperToString(JSContext* context, JSValueConst thisObj,
                                  int argc, JSValueConst* argv);

#include "OOJSEngineNativeWrappers.h"

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
#define OOJS_NATIVE_ARGS \
  JSContext *context, JSValueConst oojsThis, int argc, JSValueConst *oojsArgv
#define OOJS_GETTER_ARGS JSContext *context, JSValueConst thisObj, int magic
#define OOJS_SETTER_ARGS \
  JSContext *context, JSValueConst thisObj, JSValueConst value, int magic
#define OOJS_THIS oojsThis
#define OOJS_ARGV oojsArgv

/*	Replacement for SpiderMonkey's JS_IsConstructing(), valid only in
        constructors created by OOJSInitClass() (JS_CFUNC_constructor_or_func):
        QuickJS passes new.target as this when called with new, and undefined
        when called as a function.
*/
#define OOJS_IS_CONSTRUCTING (!JS_IsUndefined(OOJS_THIS))

#define OOJS_RETURN(v) \
  do {                 \
    return (v);        \
  } while (0)
#define OOJS_RETURN_VOID OOJS_RETURN(JS_UNDEFINED)
#define OOJS_RETURN_NULL OOJS_RETURN(JS_NULL)
#define OOJS_RETURN_BOOL(v) OOJS_RETURN(OOJSValueFromBOOL(v))
#define OOJS_RETURN_INT(v) OOJS_RETURN(JS_NewInt32(context, (v)))
#define OOJS_RETURN_DOUBLE(v) OOJS_RETURN(JS_NewFloat64(context, (v)))

/*	PList return slots. A native returns C++ values as oo::PList, converted
   by OOJSValueFromPList():

   - OOJS_RETURN_PLIST(plist): the value of <plist> (null for a null PList);
   - OOJS_RETURN_STRING_OR_NULL(opt): a std::optional<std::string>, the string
     or null for nullopt.

   Exemplar: OOJSObjectWrapperToString() in OOJavaScriptEngine.cpp.
*/
#define OOJS_RETURN_PLIST(plist) \
  OOJS_RETURN(OOJSValueFromPList(context, (plist)))
#define OOJS_RETURN_STRING_OR_NULL(opt)                            \
  do {                                                             \
    const std::optional<std::string>& oojsOptionalString_ = (opt); \
    OOJS_RETURN_PLIST(oojsOptionalString_.has_value()              \
                          ? oo::PList(*oojsOptionalString_)        \
                          : oo::PList());                          \
  } while (0)

#define OOJS_RETURN_WITH_HELPER(helper, value) \
  do {                                         \
    JSValue oojsRVal;                          \
    if (!helper(context, (value), &oojsRVal))  \
      return OOJSNativeFailure(context);       \
    return oojsRVal;                           \
  } while (0)

#define OOJS_RETURN_VECTOR(value) \
  OOJS_RETURN_WITH_HELPER(VectorToJSValue, value)
#define OOJS_RETURN_HPVECTOR(value) \
  OOJS_RETURN_WITH_HELPER(HPVectorToJSValue, value)
#define OOJS_RETURN_QUATERNION(value) \
  OOJS_RETURN_WITH_HELPER(QuaternionToJSValue, value)

/***** Property attributes, equivalent to the SpiderMonkey OOJS_PROP_* flags
 * *****/

// Callback-based (JS_CGETSET_MAGIC_DEF2). Read-only properties are defined
// without a setter.
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
#define OOJS_PROPERTY_RW(name, getter, setter, magic) \
  JS_CGETSET_MAGIC_DEF2(name, getter, setter, magic, OOJS_PROP_READWRITE_CB)
#define OOJS_PROPERTY_RO(name, getter, magic) \
  JS_CGETSET_MAGIC_DEF2(name, getter, NULL, magic, OOJS_PROP_READONLY_CB)
