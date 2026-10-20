/*

OOJavaScriptEngine.m (QuickJS-ng proof of concept)

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

#import "OOJavaScriptEngine.h"
#import "OOJSQuaternion.h"
#import "OOJSScript.h"
#import "OOJSVector.h"

#include <time.h>
#if OOLITE_WINDOWS
#include <windows.h>
#endif

#define OOJS_RUNTIME_SIZE_MiB 256
#define OOJS_TIME_LIMIT (1) // seconds

static OOJavaScriptEngine* sSharedEngine = nil;

static int InterruptHandler(JSRuntime* runtime, void* opaque);
static JSValue GlobalLog(OOJS_NATIVE_ARGS);

static const JSCFunctionListEntry sGlobalMethods[] = {
    JS_CFUNC_DEF("log", 1, GlobalLog),
};

//===========================================================================
// JavaScript engine initialisation and shutdown
//===========================================================================

@implementation OOJavaScriptEngine

+ (OOJavaScriptEngine*)sharedEngine
{
    if (sSharedEngine == nil)
        sSharedEngine = [[self alloc] init];

    return sSharedEngine;
}

- (id)init
{
    NSAssert(sSharedEngine == nil, @"Attempt to create multiple OOJavaScriptEngines.");

    if (!(self = [super init]))
        return nil;
    sSharedEngine = self;
    _showErrorLocations = YES;

    _runtime = JS_NewRuntime();
    if (_runtime == NULL) {
        OOLog(@"script.javaScript.init.error", @"%@", @"***** FATAL ERROR: failed to create JavaScript runtime.");
        exit(1);
    }

    NSInteger jsRuntimeInMiB = [[NSUserDefaults standardUserDefaults] integerForKey:@"jsruntime-size-mib"];
    if (jsRuntimeInMiB <= 0)
        jsRuntimeInMiB = OOJS_RUNTIME_SIZE_MiB;
    JS_SetMemoryLimit(_runtime, jsRuntimeInMiB * 1024L * 1024L);
    JS_SetInterruptHandler(_runtime, InterruptHandler, NULL);
#ifndef NDEBUG
    JS_SetDumpFlags(_runtime, JS_DUMP_LEAKS);
#endif

    _context = JS_NewContext(_runtime);
    if (_context == NULL) {
        OOLog(@"script.javaScript.init.error", @"%@", @"***** FATAL ERROR: failed to create JavaScript context.");
        exit(1);
    }

    _globalObject = JS_GetGlobalObject(_context);
    JS_SetPropertyStr(_context, _globalObject, "global", JS_DupValue(_context, _globalObject));
    JS_SetPropertyFunctionList(_context, _globalObject, sGlobalMethods, OOJS_COUNT(sGlobalMethods));

    InitOOJSScript(_context, _globalObject);
    InitOOJSVector(_context, _globalObject);
    InitOOJSQuaternion(_context, _globalObject);

    return self;
}

- (NSUInteger)shutDown
{
    if (_context == NULL)
        return 0;

    JS_FreeValue(_context, _globalObject);
    _globalObject = JS_UNDEFINED;
    JS_FreeContext(_context);
    _context = NULL;

    JS_RunGC(_runtime);
    JSMemoryUsage usage;
    JS_ComputeMemoryUsage(_runtime, &usage);
    if (usage.obj_count != 0) {
        /*	JS_FreeRuntime() would assert. Dump what is left and abandon the
                runtime instead, so the leak can be reported.
        */
        OOLog(@"script.javaScript.shutDown.leak", @"***** JavaScript runtime shut down with %lli objects still alive; something is holding a JSValue it does not own, or has not freed one it does.", (long long)usage.obj_count);
        JS_DumpMemoryUsage(stdout, &usage, _runtime);
        _runtime = NULL;
        return (NSUInteger)usage.obj_count;
    }

    JS_FreeRuntime(_runtime);
    _runtime = NULL;
    return 0;
}

- (void)dealloc
{
    [self shutDown];
    if (sSharedEngine == self)
        sSharedEngine = nil;
    [super dealloc];
}

- (JSContext*)context
{
    return _context;
}

- (JSValueConst)globalObject
{
    return _globalObject;
}

- (BOOL)callJSFunction:(JSValueConst)function
             forObject:(JSValueConst)jsThis
                  argc:(int)argc
                  argv:(JSValueConst*)argv
                result:(JSValue*)outResult
{
    NSParameterAssert(JS_IsFunction(_context, function));

    OOJSStartTimeLimiter();
    JSValue result = JS_Call(_context, function, jsThis, argc, argv);
    OOJSStopTimeLimiter();

    if (JS_IsException(result)) {
        OOJSReportPendingException(_context);
        if (outResult != NULL)
            *outResult = JS_UNDEFINED;
        return NO;
    }

    if (outResult != NULL)
        *outResult = result;
    else
        JS_FreeValue(_context, result);
    return YES;
}

- (BOOL)showErrorLocations
{
    return _showErrorLocations;
}

- (void)setShowErrorLocations:(BOOL)value
{
    _showErrorLocations = !!value;
}

@end

NSString* OOJSWrapScriptSource(NSString* source)
{
    // A newline before the closing part is needed if the last line is a // comment.
    NSString* lineEnd = [source hasSuffix:@"\n"] ? @"" : @"\n";
    return [NSString stringWithFormat:@"with(this){(function(){%@%@}).call(this)}", source, lineEnd];
}

//===========================================================================
// Global functions
//===========================================================================

// log([messageClass : String,] message : String, ...)
static JSValue GlobalLog(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    NSString* message = nil;
    NSString* messageClass = nil;

    if (EXPECT_NOT(argc < 1)) {
        OOJS_RETURN_VOID;
    }
    if (argc < 2) {
        messageClass = @"script.debug.message";
        message = OOStringFromJSValue(context, OOJS_ARGV[0]);
    } else {
        messageClass = OOStringFromJSValueEvenIfNull(context, OOJS_ARGV[0]);
        if (!OOLogWillDisplayMessagesInClass(messageClass)) {
            // Do nothing (and short-circuit) if message class is filtered out.
            OOJS_RETURN_VOID;
        }

        NSMutableArray* parts = [NSMutableArray arrayWithCapacity:argc - 1];
        for (int i = 1; i < argc; i++) {
            [parts addObject:OOStringFromJSValueEvenIfNull(context, OOJS_ARGV[i])];
        }
        message = [parts componentsJoinedByString:@", "];
    }

    OOJS_BEGIN_FULL_NATIVE(context)
    OOLog(messageClass, @"%@", message);
    OOJS_END_FULL_NATIVE

    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}

//===========================================================================
// Time limiter
//===========================================================================

static unsigned sLimiterStartDepth;
static int sLimiterPauseDepth;
static double sLimiterStart;
static double sLimiterPauseStart;
static double sLimiterTimeLimit;

static double MonotonicTime(void)
{
#if OOLITE_WINDOWS
    static LARGE_INTEGER frequency;
    LARGE_INTEGER counter;
    if (frequency.QuadPart == 0)
        QueryPerformanceFrequency(&frequency);
    QueryPerformanceCounter(&counter);
    return (double)counter.QuadPart / (double)frequency.QuadPart;
#else
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return now.tv_sec + now.tv_nsec * 1e-9;
#endif
}

void OOJSStartTimeLimiterWithTimeLimit(OOTimeDelta limit)
{
    if (sLimiterStartDepth++ == 0) {
        if (limit <= 0.0)
            limit = OOJS_TIME_LIMIT;
        sLimiterTimeLimit = limit;
        sLimiterPauseDepth = 0;
        sLimiterStart = MonotonicTime();
    }
}

void OOJSStopTimeLimiter(void)
{
    if (sLimiterStartDepth == 0) {
        OOLog(@"bug.javaScript.limiterDepth", @"%@", @"Attempt to stop JavaScript time limiter while it is already fully stopped. This is an internal bug, please report it.");
        return;
    }

    if (--sLimiterStartDepth == 0)
        sLimiterTimeLimit = 0.0;
}

void OOJSPauseTimeLimiter(void)
{
    if (sLimiterPauseDepth++ == 0)
        sLimiterPauseStart = MonotonicTime();
}

void OOJSResumeTimeLimiter(void)
{
    if (--sLimiterPauseDepth == 0)
        sLimiterTimeLimit += MonotonicTime() - sLimiterPauseStart;
}

/*	QuickJS polls this regularly while running JS code, so unlike the
        SpiderMonkey operation callback no watchdog thread is needed. Returning
        non-zero throws an uncatchable error, which unwinds all JS frames.
*/
static int InterruptHandler(JSRuntime* runtime, void* opaque)
{
    if (EXPECT(sLimiterStartDepth == 0 || sLimiterPauseDepth > 0))
        return 0;

    double elapsed = MonotonicTime() - sLimiterStart;
    if (elapsed <= sLimiterTimeLimit)
        return 0;

    OOLogERR(@"script.javaScript.timeLimit", @"Script \"%@\" ran for %g seconds and has been terminated.", [[OOJSScript currentlyRunningScript] name], elapsed);
    return 1;
}

//===========================================================================
// Error reporting
//===========================================================================

/*	QuickJS records locations only in the stack property, as lines of the form
        "    at name (file:line:column)" or "    at file:line:column".
        Extract the file and line of the innermost frame.
*/
static BOOL GetLocationFromStack(NSString* stack, NSString** outFile, unsigned* outLine)
{
    for (NSString* frame in [stack componentsSeparatedByString:@"\n"]) {
        frame = [frame stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (![frame hasPrefix:@"at "])
            continue;
        frame = [frame substringFromIndex:3];

        NSRange open = [frame rangeOfString:@"(" options:NSBackwardsSearch];
        if (open.location != NSNotFound && [frame hasSuffix:@")"]) {
            frame = [frame substringWithRange:NSMakeRange(open.location + 1, [frame length] - open.location - 2)];
        }

        NSArray* parts = [frame componentsSeparatedByString:@":"];
        if ([parts count] < 3)
            continue; // Native frame, e.g. "at log (native)".

        NSUInteger count = [parts count];
        *outFile = [[parts subarrayWithRange:NSMakeRange(0, count - 2)] componentsJoinedByString:@":"];
        *outLine = (unsigned)[[parts objectAtIndex:count - 2] intValue];
        return YES;
    }
    return NO;
}

static NSString* StackOfValue(JSContext* context, JSValueConst value)
{
    if (!JS_IsObject(value))
        return nil;
    JSValue stack = JS_GetPropertyStr(context, value, "stack");
    NSString* result = OOStringFromJSValue(context, stack);
    JS_FreeValue(context, stack);
    return result;
}

static void LogProblem(NSString* severity, NSString* errorName, NSString* message, NSString* stack)
{
    NSString* messageClass = [NSString stringWithFormat:@"script.javaScript.%@.%@", severity, errorName];
    NSString* highlight = [severity isEqualToString:@"warning"] ? @"-----" : @"*****";

    if (!OOLogWillDisplayMessagesInClass(messageClass))
        return;

    NSString* activeScript = [[OOJSScript currentlyRunningScript] displayName];
    if (activeScript == nil)
        activeScript = @"<unidentified script>";
    OOLog(messageClass, @"%@ JavaScript %@ (%@): %@", highlight, severity, activeScript, message);

    NSString* file = nil;
    unsigned line = 0;
    if ([[OOJavaScriptEngine sharedEngine] showErrorLocations] && GetLocationFromStack(stack, &file, &line)) {
        OOLog(messageClass, @"      %@, line %u.", file, line);
    }
}

void OOJSReportPendingException(JSContext* context)
{
    JSValue exception = JS_GetException(context);

    // The time limiter has already logged a termination.
    if (JS_IsUncatchableError(exception)) {
        JS_FreeValue(context, exception);
        return;
    }

    OOJSPauseTimeLimiter();

    NSString* errorName = @"exception";
    if (JS_IsError(exception)) {
        JSValue name = JS_GetPropertyStr(context, exception, "name");
        errorName = OOStringFromJSValue(context, name) ?: errorName;
        JS_FreeValue(context, name);
    }

    LogProblem(@"exception", errorName, OOStringFromJSValueEvenIfNull(context, exception), StackOfValue(context, exception));

    JS_FreeValue(context, exception);
    OOJSResumeTimeLimiter();
}

static NSString* CallerPrefix(NSString* scriptClass, NSString* function)
{
    if (function == nil)
        return @"";
    if (scriptClass == nil)
        return [function stringByAppendingString:@": "];
    return [NSString stringWithFormat:@"%@.%@: ", scriptClass, function];
}

void OOJSReportError(JSContext* context, NSString* format, ...)
{
    va_list args;

    va_start(args, format);
    OOJSReportErrorWithArguments(context, format, args);
    va_end(args);
}

void OOJSReportErrorForCaller(JSContext* context, NSString* scriptClass, NSString* function, NSString* format, ...)
{
    va_list args;
    NSString* msg = nil;

    @try {
        va_start(args, format);
        msg = [[NSString alloc] initWithFormat:format arguments:args];
        va_end(args);

        OOJSReportError(context, @"%@%@", CallerPrefix(scriptClass, function), msg);
    }
    @catch (id exception) {
        // Squash any secondary errors during error handling.
    }
    [msg release];
}

void OOJSReportErrorWithArguments(JSContext* context, NSString* format, va_list args)
{
    NSString* msg = nil;

    @try {
        msg = [[NSString alloc] initWithFormat:format arguments:args];
        JS_ThrowPlainError(context, "%s", [msg UTF8String]);
    }
    @catch (id exception) {
        // Squash any secondary errors during error handling.
    }
    [msg release];
}

void OOJSReportWrappedException(JSContext* context, id exception)
{
    if (!JS_HasException(context)) {
        if ([exception isKindOfClass:[NSException class]])
            OOJSReportError(context, @"Native exception: %@", [exception reason]);
        else
            OOJSReportError(context, @"Unidentified native exception");
    }
    // Else, let the pending exception propagate.
}

void OOJSReportWarning(JSContext* context, NSString* format, ...)
{
    va_list args;

    va_start(args, format);
    OOJSReportWarningWithArguments(context, format, args);
    va_end(args);
}

void OOJSReportWarningForCaller(JSContext* context, NSString* scriptClass, NSString* function, NSString* format, ...)
{
    va_list args;
    NSString* msg = nil;

    @try {
        va_start(args, format);
        msg = [[NSString alloc] initWithFormat:format arguments:args];
        va_end(args);

        OOJSReportWarning(context, @"%@%@", CallerPrefix(scriptClass, function), msg);
    }
    @catch (id exception) {
        // Squash any secondary errors during error handling.
    }
    [msg release];
}

void OOJSReportWarningWithArguments(JSContext* context, NSString* format, va_list args)
{
    NSString* msg = nil;

    @try {
        msg = [[NSString alloc] initWithFormat:format arguments:args];

        // A fresh Error object captures the current JS stack, giving the location.
        JSValue error = JS_NewError(context);
        LogProblem(@"warning", @"warning", msg, StackOfValue(context, error));
        JS_FreeValue(context, error);
    }
    @catch (id exception) {
        // Squash any secondary errors during error handling.
    }
    [msg release];
}

static NSString* PropertyNameForMagic(int magic, const JSCFunctionListEntry* list, size_t count)
{
    for (size_t i = 0; i < count; i++) {
        if (list[i].def_type == JS_DEF_CGETSET_MAGIC && list[i].magic == magic)
            return [NSString stringWithUTF8String:list[i].name];
    }
    return [NSString stringWithFormat:@"%i", magic];
}

void OOJSReportBadPropertySelector(JSContext* context, JSValueConst thisObj, int magic, const JSCFunctionListEntry* list, size_t count)
{
    NSString* propName = PropertyNameForMagic(magic, list, count);
    NSString* className = OOJSClassNameOfValue(context, thisObj);

    OOJSReportError(context, @"Invalid property identifier %@ for instance of %@.", propName, className);
}

void OOJSReportBadPropertyValue(JSContext* context, JSValueConst thisObj, int magic, const JSCFunctionListEntry* list, size_t count, JSValueConst value)
{
    NSString* propName = PropertyNameForMagic(magic, list, count);
    NSString* className = OOJSClassNameOfValue(context, thisObj);
    NSString* valueDesc = OOJSDescribeValue(context, value, YES);

    OOJSReportError(context, @"Cannot set property %@ of instance of %@ to invalid value %@.", propName, className, valueDesc);
}

void OOJSReportBadArguments(JSContext* context, NSString* scriptClass, NSString* function, int argc, JSValueConst* argv, NSString* message, NSString* expectedArgsDescription)
{
    @try {
        if (message == nil)
            message = @"Invalid arguments";
        message = [NSString stringWithFormat:@"%@ %@", message, [NSString stringWithJavaScriptParameters:argv count:argc inContext:context]];
        if (expectedArgsDescription != nil)
            message = [NSString stringWithFormat:@"%@ -- expected %@", message, expectedArgsDescription];

        OOJSReportErrorForCaller(context, scriptClass, function, @"%@.", message);
    }
    @catch (id exception) {
        // Squash any secondary errors during error handling.
    }
}

BOOL OOJSArgumentListGetNumber(JSContext* context, NSString* scriptClass, NSString* function, int argc, JSValueConst* argv, double* outNumber, int* outConsumed)
{
    if (OOJSArgumentListGetNumberNoError(context, argc, argv, outNumber, outConsumed)) {
        return YES;
    } else {
        OOJSReportBadArguments(context, scriptClass, function, argc, argv,
            @"Expected number, got", NULL);
        return NO;
    }
}

BOOL OOJSArgumentListGetNumberNoError(JSContext* context, int argc, JSValueConst* argv, double* outNumber, int* outConsumed)
{
    double value;

    NSCParameterAssert(context != NULL && (argv != NULL || argc == 0) && outNumber != NULL);

    // Get value, if possible.
    if (EXPECT_NOT(argc < 1 || JS_ToFloat64(context, &value, argv[0]) < 0 || isnan(value))) {
        // ToNumber can throw (e.g. for a Symbol); this variant must not leave an exception pending.
        if (JS_HasException(context))
            JS_FreeValue(context, JS_GetException(context));
        if (outConsumed != NULL)
            *outConsumed = 0;
        return NO;
    }

    // Success.
    *outNumber = value;
    if (outConsumed != NULL)
        *outConsumed = 1;
    return YES;
}

//===========================================================================
// Value conversion
//===========================================================================

JSValue OOJSValueFromNativeObject(JSContext* context, id object)
{
    if (object == nil)
        return JS_NULL;
    return [object oo_jsValueInContext:context];
}

NSString* OOStringFromJSValueEvenIfNull(JSContext* context, JSValueConst value)
{
    size_t length;
    const char* chars = JS_ToCStringLen(context, &length, value); // Calls the value's toString method if needed.
    if (chars == NULL) {
        JS_FreeValue(context, JS_GetException(context));
        return nil;
    }

    NSString* result = [[[NSString alloc] initWithBytes:chars length:length encoding:NSUTF8StringEncoding] autorelease];
    JS_FreeCString(context, chars);
    return result;
}

NSString* OOStringFromJSValue(JSContext* context, JSValueConst value)
{
    if (EXPECT(!JS_IsNull(value) && !JS_IsUndefined(value))) {
        return OOStringFromJSValueEvenIfNull(context, value);
    }
    return nil;
}

NSString* OOJSClassNameOfValue(JSContext* context, JSValueConst value)
{
    if (!JS_IsObject(value))
        return @"primitive";

    JSValue ctor = JS_GetPropertyStr(context, value, "constructor");
    JSValue name = JS_IsObject(ctor) ? JS_GetPropertyStr(context, ctor, "name") : JS_UNDEFINED;
    NSString* result = OOStringFromJSValue(context, name);
    JS_FreeValue(context, name);
    JS_FreeValue(context, ctor);
    return result ?: @"Object";
}

static NSString* DescribeValue(JSContext* context, JSValueConst value, BOOL abbreviateObjects, BOOL recursing)
{
    if (JS_IsFunction(context, value)) {
        JSValue nameVal = JS_GetPropertyStr(context, value, "name");
        NSString* name = OOStringFromJSValue(context, nameVal);
        JS_FreeValue(context, nameVal);
        if ([name length] != 0)
            return [NSString stringWithFormat:@"function %@", name];
        else
            return @"function";
    }

    NSString* result = nil;

    if (JS_IsString(value)) {
        enum { kMaxLength = 200 };

        NSString* string = OOStringFromJSValueEvenIfNull(context, value);
        NSUInteger length = [string length];
        result = [string substringToIndex:MIN(length, (NSUInteger)kMaxLength)];
        result = [NSString stringWithFormat:@"\"%@%@\"", [result escapedForJavaScriptLiteral], (length > kMaxLength) ? @"..." : @""];
    } else if (JS_IsArray(value)) {
        // Descibe up to four elements of an array.
        int64_t count;
        if (JS_GetLength(context, value, &count) == 0) {
            if (!recursing) {
                NSMutableString* arrayDesc = [NSMutableString stringWithString:@"["];
                int64_t i, effectiveCount = MIN(count, (int64_t)4);
                for (i = 0; i < effectiveCount; i++) {
                    JSValue item = JS_GetPropertyUint32(context, value, (uint32_t)i);
                    NSString* itemDesc = @"?";
                    if (!JS_IsException(item)) {
                        itemDesc = DescribeValue(context, item, YES /* always abbreviate objects in arrays */, YES);
                    }
                    JS_FreeValue(context, item);
                    if (i != 0)
                        [arrayDesc appendString:@", "];
                    [arrayDesc appendString:itemDesc];
                }
                if (effectiveCount != count) {
                    [arrayDesc appendFormat:@", ... <%lli items total>]", (long long)count];
                } else {
                    [arrayDesc appendString:@"]"];
                }

                result = arrayDesc;
            } else {
                result = [NSString stringWithFormat:@"[<%lli items>]", (long long)count];
            }
        } else {
            result = @"[...]";
        }
    }

    if (result == nil) {
        result = OOStringFromJSValueEvenIfNull(context, value);

        if (abbreviateObjects && JS_IsObject(value) && [result isEqualToString:@"[object Object]"]) {
            result = @"{...}";
        }

        if (result == nil)
            result = @"?";
    }

    return result;
}

NSString* OOJSDescribeValue(JSContext* context, JSValueConst value, BOOL abbreviateObjects)
{
    return DescribeValue(context, value, abbreviateObjects, NO);
}

@implementation NSObject (OOJavaScriptConversion)

- (JSValue)oo_jsValueInContext:(JSContext*)context
{
    return JS_UNDEFINED;
}

@end

@implementation NSString (OOJavaScriptConversion)

- (JSValue)oo_jsValueInContext:(JSContext*)context
{
    NSData* utf8 = [self dataUsingEncoding:NSUTF8StringEncoding];
    return JS_NewStringLen(context, [utf8 bytes], [utf8 length]);
}

@end

@implementation NSNumber (OOJavaScriptConversion)

- (JSValue)oo_jsValueInContext:(JSContext*)context
{
    // As with SpiderMonkey, all NSNumbers (including booleans) become JS numbers.
    return JS_NewNumber(context, [self doubleValue]);
}

@end

@implementation NSNull (OOJavaScriptConversion)

- (JSValue)oo_jsValueInContext:(JSContext*)context
{
    return JS_NULL;
}

@end

@implementation NSString (OOJavaScriptExtensions)

+ (NSString*)stringWithJavaScriptParameters:(JSValueConst*)params count:(int)count inContext:(JSContext*)context
{
    if (params == NULL && count != 0)
        return nil;

    int i;
    NSMutableString* result = [NSMutableString stringWithString:@"("];

    for (i = 0; i < count; ++i) {
        if (i != 0)
            [result appendString:@", "];
        [result appendString:OOJSDescribeValue(context, params[i], NO)];
    }

    [result appendString:@")"];
    return result;
}

- (NSString*)escapedForJavaScriptLiteral
{
    NSMutableString* result = nil;
    NSUInteger i, length;
    unichar c;

    length = [self length];
    result = [NSMutableString stringWithCapacity:length];

    // Not hugely efficient.
    for (i = 0; i != length; ++i) {
        c = [self characterAtIndex:i];
        switch (c) {
        case '\\':
            [result appendString:@"\\\\"];
            break;

        case '\b':
            [result appendString:@"\\b"];
            break;

        case '\f':
            [result appendString:@"\\f"];
            break;

        case '\n':
            [result appendString:@"\\n"];
            break;

        case '\r':
            [result appendString:@"\\r"];
            break;

        case '\t':
            [result appendString:@"\\t"];
            break;

        case '\v':
            [result appendString:@"\\v"];
            break;

        case '\'':
            [result appendString:@"\\\'"];
            break;

        case '\"':
            [result appendString:@"\\\""];
            break;

        default:
            [result appendString:[NSString stringWithCharacters:&c length:1]];
        }
    }

    return result;
}

@end
