/*

OOJavaScriptEngine.h (QuickJS-ng proof of concept)

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
           the caller. On failure the out parameter is left as JS_UNDEFINED and
           need not be freed.
        3. OOJS_RETURN(v) and friends transfer ownership of v to QuickJS.
        4. A native object that keeps a JSValue (the old JS_Add*Root pattern) owns
           a reference and must free it before the runtime is destroyed. If the
           JS object can reach back to the native object strongly, the reference
           must also be reported from the class gc_mark hook so the cycle
           collector can see it. Back references from JS to native objects use
           weak references, as before.
        5. Errors: a native that fails throws (OOJSReport*Error) and returns
           JS_EXCEPTION. Code calling into JS from Objective-C reports a pending
           exception with OOJSReportPendingException().
*/

#pragma once

#import "OOFoundation.h"
#import "OOTypes.h"
#include <quickjs.h>

// Number of entries in a JSCFunctionListEntry (or other) array.
#define OOJS_COUNT(array) (sizeof(array) / sizeof *(array))

@interface OOJavaScriptEngine : NSObject {
@private
    JSRuntime* _runtime;
    JSContext* _context;
    JSValue _globalObject;
    BOOL _showErrorLocations;
}

+ (OOJavaScriptEngine*)sharedEngine;

- (JSContext*)context;
- (JSValueConst)globalObject;

// Call a JS function. *outResult is owned by the caller. Exceptions are reported and cleared.
- (BOOL)callJSFunction:(JSValueConst)function
             forObject:(JSValueConst)jsThis
                  argc:(int)argc
                  argv:(JSValueConst*)argv
                result:(JSValue*)outResult;

- (BOOL)showErrorLocations;
- (void)setShowErrorLocations:(BOOL)value;

/*	Destroy the context and runtime. All native objects holding JSValues must
        have released them first. Returns the number of JS objects still alive
        after a final garbage collection; if it is non-zero, they are logged
        and the runtime is abandoned rather than freed.
*/
- (NSUInteger)shutDown;

@end

// There is only one context, created on the main thread.
OOINLINE JSContext* OOJSAcquireContext(void)
{
    return [[OOJavaScriptEngine sharedEngine] context];
}

OOINLINE void OOJSRelinquishContext(JSContext* context)
{
    (void)context;
}

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

// These throw an Error. The caller must return JS_EXCEPTION.
void OOJSReportError(JSContext* context, NSString* format, ...);
void OOJSReportErrorWithArguments(JSContext* context, NSString* format, va_list args);
void OOJSReportErrorForCaller(JSContext* context, NSString* scriptClass, NSString* function, NSString* format, ...);

// Warnings are logged with the current script location and do not throw.
void OOJSReportWarning(JSContext* context, NSString* format, ...);
void OOJSReportWarningWithArguments(JSContext* context, NSString* format, va_list args);
void OOJSReportWarningForCaller(JSContext* context, NSString* scriptClass, NSString* function, NSString* format, ...);

void OOJSReportBadPropertySelector(JSContext* context, JSValueConst thisObj, int magic, const JSCFunctionListEntry* list, size_t count);
void OOJSReportBadPropertyValue(JSContext* context, JSValueConst thisObj, int magic, const JSCFunctionListEntry* list, size_t count, JSValueConst value);
void OOJSReportBadArguments(JSContext* context, NSString* scriptClass, NSString* function, int argc, JSValueConst* argv, NSString* message, NSString* expectedArgsDescription);

void OOJSReportWrappedException(JSContext* context, id exception);

/*	Get a number from an argument list. NaN is treated as failure, as before.
        The NoError variant leaves no pending exception.
*/
BOOL OOJSArgumentListGetNumber(JSContext* context, NSString* scriptClass, NSString* function, int argc, JSValueConst* argv, double* outNumber, int* outConsumed);
BOOL OOJSArgumentListGetNumberNoError(JSContext* context, int argc, JSValueConst* argv, double* outNumber, int* outConsumed);

OOINLINE JSValue OOJSValueFromBOOL(int b)
{
    return JS_NewBool(NULL, b != 0);
}

// Returns an owned value: JS_NULL for nil, otherwise [object oo_jsValueInContext:].
JSValue OOJSValueFromNativeObject(JSContext* context, id object);

NSString* OOStringFromJSValue(JSContext* context, JSValueConst value); // nil for null and undefined.
NSString* OOStringFromJSValueEvenIfNull(JSContext* context, JSValueConst value);
NSString* OOJSDescribeValue(JSContext* context, JSValueConst value, BOOL abbreviateObjects);

// Name of the value's class, e.g. "Vector3D", for error messages.
NSString* OOJSClassNameOfValue(JSContext* context, JSValueConst value);

@interface NSObject (OOJavaScriptConversion)

// Returns an owned value. The default implementation returns JS_UNDEFINED.
- (JSValue)oo_jsValueInContext:(JSContext*)context;

@end

@interface NSString (OOJavaScriptExtensions)

+ (NSString*)stringWithJavaScriptParameters:(JSValueConst*)params count:(int)count inContext:(JSContext*)context;
- (NSString*)escapedForJavaScriptLiteral;

@end

// Time limiter. Calls must be balanced, as before; nesting is supported.
#define kOOJSLongTimeLimit (5.0)
void OOJSStartTimeLimiterWithTimeLimit(OOTimeDelta limit);
#define OOJSStartTimeLimiter() OOJSStartTimeLimiterWithTimeLimit(0.0)
void OOJSStopTimeLimiter(void);
void OOJSPauseTimeLimiter(void);
void OOJSResumeTimeLimiter(void);

/*	Native function and property callback conveniences.

        Native functions are declared as
                static JSValue Foo(OOJS_NATIVE_ARGS);
        and use OOJS_THIS, OOJS_ARGV and argc as the SpiderMonkey versions did.
*/
#define OOJS_NATIVE_ARGS JSContext *context, JSValueConst oojsThis, int argc, JSValueConst *oojsArgv
#define OOJS_THIS oojsThis
#define OOJS_ARGV oojsArgv

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
            return JS_EXCEPTION;                  \
        return oojsRVal;                          \
    } while (0)

#define OOJS_RETURN_VECTOR(value) OOJS_RETURN_WITH_HELPER(VectorToJSValue, value)
#define OOJS_RETURN_HPVECTOR(value) OOJS_RETURN_WITH_HELPER(HPVectorToJSValue, value)
#define OOJS_RETURN_QUATERNION(value) OOJS_RETURN_WITH_HELPER(QuaternionToJSValue, value)

/*	OOJS_NATIVE_ENTER()/OOJS_NATIVE_EXIT bracket natives that call into
        Objective-C code which may throw; the exception is converted into a JS
        error. OOJS_PROFILE_ENTER/EXIT bracket natives that cannot throw. The
        JS profiler hooks are not ported yet, so the latter are plain blocks.
*/
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

#define OOJS_PROFILE_ENTER {
#define OOJS_PROFILE_EXIT }
#define OOJS_PROFILE_EXIT_VOID }

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

// Property attributes, equivalent to the SpiderMonkey OOJS_PROP_* flags.
#define OOJS_PROP_READWRITE_CB JS_PROP_ENUMERABLE
#define OOJS_PROP_READONLY_CB JS_PROP_ENUMERABLE
