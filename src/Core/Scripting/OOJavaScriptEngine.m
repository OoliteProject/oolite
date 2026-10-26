/*

OOJavaScriptEngine.m (QuickJS-ng)

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
#import "OOJSEngineTimeManagement.h"
#import "OOJSScript.h"

#import "EntityOOJavaScriptExtensions.h"
#import "NSNumberOOExtensions.h"
#import "NSStringOOExtensions.h"
#import "OOCollectionExtractors.h"
#import "OOConstToJSString.h"
#import "OOPlanetEntity.h"
#import "OOVisualEffectEntity.h"
#import "OOWaypointEntity.h"
#import "OOWeakReference.h"
#import "ResourceManager.h"
#import "Universe.h"

#import "OOJSClock.h"
#import "OOJSDock.h"
#import "OOJSEntity.h"
#import "OOJSEquipmentInfo.h"
#import "OOJSExhaustPlume.h"
#import "OOJSFlasher.h"
#import "OOJSFont.h"
#import "OOJSFrameCallbacks.h"
#import "OOJSGlobal.h"
#import "OOJSManifest.h"
#import "OOJSMission.h"
#import "OOJSMissionVariables.h"
#import "OOJSOolite.h"
#import "OOJSPlanet.h"
#import "OOJSPlayer.h"
#import "OOJSPlayerShip.h"
#import "OOJSQuaternion.h"
#import "OOJSShip.h"
#import "OOJSShipGroup.h"
#import "OOJSSound.h"
#import "OOJSSoundSource.h"
#import "OOJSSpecialFunctions.h"
#import "OOJSStation.h"
#import "OOJSSun.h"
#import "OOJSSystem.h"
#import "OOJSSystemInfo.h"
#import "OOJSTimer.h"
#import "OOJSVector.h"
#import "OOJSVisualEffect.h"
#import "OOJSWaypoint.h"
#import "OOJSWorldScripts.h"
#import "OOJSWormhole.h"

#include <time.h>
#if OOLITE_WINDOWS
#include <windows.h>
#endif

#define OOJS_RUNTIME_SIZE_MiB 256
#define OOJS_STACK_SIZE (1024 * 1024)

#if OO_DEBUG
#define OOJS_TIME_LIMIT (0.2) // seconds
#else
#define OOJS_TIME_LIMIT (1) // seconds
#endif

static OOJavaScriptEngine* sSharedEngine = nil;
#if OOJSENGINE_MONITOR_SUPPORT

@interface OOJavaScriptEngine (OOMonitorSupportInternal)

- (void)sendMonitorProblemOfSeverity:(NSString*)severity
                              inFile:(NSString*)file
                                line:(unsigned)line
                         withMessage:(NSString*)message
                           inContext:(JSContext*)context;

- (void)sendMonitorLogMessage:(NSString*)message
             withMessageClass:(NSString*)messageClass
                    inContext:(JSContext*)context;

@end

#endif

static unsigned sErrorHandlerStackSkip = 0;

JSContext* gOOJSMainThreadContext = NULL;

NSString* const kOOJavaScriptEngineWillResetNotification = @"org.aegidian.oolite OOJavaScriptEngine will reset";
NSString* const kOOJavaScriptEngineDidResetNotification = @"org.aegidian.oolite OOJavaScriptEngine did reset";

static int InterruptHandler(JSRuntime* runtime, void* opaque);
static void RegisterStandardObjectConverters(JSContext* context);
static void LoadCompatibilityScript(JSContext* context);

@interface OOJavaScriptEngine (Private)

- (void)createMainThreadContext;
- (void)destroyMainThreadContext;

@end

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

- (void)runMissionCallback
{
    MissionRunCallback();
}

- (id)init
{
    NSAssert(sSharedEngine == nil, @"Attempt to create multiple OOJavaScriptEngines.");

    if (!(self = [super init]))
        return nil;
    sSharedEngine = self;
    _showErrorLocations = YES;

    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
#ifdef OO_DEBUG_MONITOR_ENABLED
    /*	Set stack trace preferences from preferences. These will be overriden
            by the debug OXP script if installed, but being able to enable traces
            without setting up the debug console could be useful for debugging
            users' problems.
    */
    [self setDumpStackForErrors:[defaults boolForKey:@"dump-stack-for-errors"]];
    [self setDumpStackForWarnings:[defaults boolForKey:@"dump-stack-for-warnings"]];
#endif

    _runtime = JS_NewRuntime();
    if (_runtime == NULL) {
        OOLog(@"script.javaScript.init.error", @"%@", @"***** FATAL ERROR: failed to create JavaScript runtime.");
        exit(1);
    }

    uint32_t jsRuntimeInMiB = [defaults oo_intForKey:@"jsruntime-size-mib" defaultValue:OOJS_RUNTIME_SIZE_MiB];
    JS_SetMemoryLimit(_runtime, jsRuntimeInMiB * 1024L * 1024L);
    JS_SetMaxStackSize(_runtime, OOJS_STACK_SIZE);
    JS_SetInterruptHandler(_runtime, InterruptHandler, NULL);

    [self createMainThreadContext];

    return self;
}

- (void)createMainThreadContext
{
    NSAssert(gOOJSMainThreadContext == NULL, @"-[OOJavaScriptEngine createMainThreadContext] called while the main thread context exists.");

    gOOJSMainThreadContext = JS_NewContext(_runtime);
    if (gOOJSMainThreadContext == NULL) {
        OOLog(@"script.javaScript.init.error", @"%@", @"***** FATAL ERROR: failed to create JavaScript context.");
        exit(1);
    }
    _context = gOOJSMainThreadContext;

    // Create the global object.
    _globalObject = JS_GetGlobalObject(_context);
    JS_DefinePropertyValueStr(_context, _globalObject, "global", JS_DupValue(_context, _globalObject), OOJS_PROP_READONLY);

    RegisterStandardObjectConverters(_context);
    LoadCompatibilityScript(_context);

    SetUpOOJSGlobal(_context, _globalObject);
    OOConstToJSStringInit(_context);

    // Initialize Oolite classes.
    InitOOJSMissionVariables(_context, _globalObject);
    InitOOJSMission(_context, _globalObject);
    InitOOJSOolite(_context, _globalObject);
    InitOOJSVector(_context, _globalObject);
    InitOOJSQuaternion(_context, _globalObject);
    InitOOJSSystem(_context, _globalObject);
    InitOOJSEntity(_context, _globalObject);
    InitOOJSShip(_context, _globalObject);
    InitOOJSStation(_context, _globalObject);
    InitOOJSDock(_context, _globalObject);
    InitOOJSVisualEffect(_context, _globalObject);
    InitOOJSExhaustPlume(_context, _globalObject);
    InitOOJSFlasher(_context, _globalObject);
    InitOOJSWormhole(_context, _globalObject);
    InitOOJSWaypoint(_context, _globalObject);
    InitOOJSPlayer(_context, _globalObject);
    InitOOJSPlayerShip(_context, _globalObject);
    InitOOJSManifest(_context, _globalObject);
    InitOOJSSun(_context, _globalObject);
    InitOOJSPlanet(_context, _globalObject);
    InitOOJSScript(_context, _globalObject);
    InitOOJSTimer(_context, _globalObject);
    InitOOJSClock(_context, _globalObject);
    InitOOJSWorldScripts(_context, _globalObject);
    InitOOJSSound(_context, _globalObject);
    InitOOJSSoundSource(_context, _globalObject);
    InitOOJSSpecialFunctions(_context, _globalObject);
    InitOOJSSystemInfo(_context, _globalObject);
    InitOOJSEquipmentInfo(_context, _globalObject);
    InitOOJSShipGroup(_context, _globalObject);
    InitOOJSFrameCallbacks(_context, _globalObject);
    InitOOJSFont(_context, _globalObject);

    // Run prefix scripts.
    JSValue special = JSSpecialFunctionsObjectWrapper(_context);
    OOJSValue* specialWrapper = [OOJSValue valueWithJSValue:special inContext:_context];
    JS_FreeValue(_context, special);
    [OOJSScript jsScriptFromFileNamed:@"oolite-global-prefix.js"
                           properties:[NSDictionary dictionaryWithObject:specialWrapper forKey:@"special"]];

    OOLog(@"script.javaScript.init.success", @"%@", @"Set up JavaScript context.");
}

- (void)destroyMainThreadContext
{
    if (gOOJSMainThreadContext != NULL) {
        OOConstToJSStringDestroy();

        JS_FreeValue(_context, _globalObject);
        _globalObject = JS_UNDEFINED;

        JS_FreeContext(_context);
        _context = NULL;
        gOOJSMainThreadContext = NULL;

        JS_RunGC(_runtime);

#ifndef NDEBUG
        /*	Every native object holding a JSValue should have let go of it on
                kOOJavaScriptEngineWillResetNotification, so nothing should be
                left. Anything that is indicates a reference counting error.
        */
        JSMemoryUsage usage;
        JS_ComputeMemoryUsage(_runtime, &usage);
        if (usage.obj_count != 0) {
            OOLogWARN(@"script.javaScript.reset.liveObjects", @"%lli JavaScript objects are still alive after the context was destroyed; something is holding a JSValue it does not own, or has not freed one it does.", (long long)usage.obj_count);
        } else {
            OOLog(@"script.javaScript.reset.liveObjects", @"%@", @"No JavaScript objects left alive after the context was destroyed.");
        }
#endif
    }
}

- (BOOL)reset
{
    NSAssert(gOOJSMainThreadContext != NULL, @"JavaScript engine not active. Can't reset.");

    OOJSFrameCallbacksRemoveAll();

    [[NSNotificationCenter defaultCenter] postNotificationName:kOOJavaScriptEngineWillResetNotification object:self];

    [self destroyMainThreadContext];
    [self createMainThreadContext];

    [[NSNotificationCenter defaultCenter] postNotificationName:kOOJavaScriptEngineDidResetNotification object:self];

    [self garbageCollectionOpportunity:YES];
    OOLog(@"script.javascript.init", @"%@", @"JavaScript reset successful.");
    return YES;
}

// YES if JavaScript code is on the stack (e.g. quitGame() called from a script).
static BOOL IsRunningJavaScript(JSContext* context)
{
    if (context == NULL)
        return NO;
    for (int level = 0; level < 16; level++) {
        JSAtom name = JS_GetScriptOrModuleName(context, level);
        if (name != JS_ATOM_NULL) {
            JS_FreeAtom(context, name);
            return YES;
        }
    }
    return NO;
}

- (NSUInteger)shutDown
{
    if (_runtime == NULL)
        return 0;

    /*	The game can quit from inside a script (quitGame()). The frames on the
            stack then legitimately hold JS values, and a function keeps its whole
            context alive, so the leak check would be meaningless, and freeing the
            context under running code is unsafe.
    */
    if (IsRunningJavaScript(_context)) {
        OOLog(@"script.javaScript.shutDown", @"%@", @"Not shutting down the JavaScript runtime (and skipping its leak check): quitting from inside a script.");
        return 0;
    }

    OOJSFrameCallbacksRemoveAll();
    [[NSNotificationCenter defaultCenter] postNotificationName:kOOJavaScriptEngineWillResetNotification object:self];
    [self destroyMainThreadContext];

    JSMemoryUsage usage;
    JS_ComputeMemoryUsage(_runtime, &usage);
    if (usage.obj_count != 0) {
        /*	JS_FreeRuntime() would assert. Dump what is left and abandon the
                runtime instead, so the leak can be reported.
        */
        OOLog(@"script.javaScript.shutDown.leak", @"***** JavaScript runtime shut down with %lli objects still alive; something is holding a JSValue it does not own, or has not freed one it does.", (long long)usage.obj_count);
        _runtime = NULL;
        return (NSUInteger)usage.obj_count;
    }

    JS_FreeRuntime(_runtime);
    _runtime = NULL;
    OOLog(@"script.javaScript.shutDown", @"%@", @"JavaScript runtime shut down with no leaked objects.");
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

- (void)garbageCollectionOpportunity:(BOOL)force
{
    /*	Reference counting frees most objects immediately, and QuickJS runs its
            cycle collector by allocation threshold, so only forced collections
            need doing here.
    */
    if (force)
        JS_RunGC(_runtime);
}

- (BOOL)showErrorLocations
{
    return _showErrorLocations;
}

- (void)setShowErrorLocations:(BOOL)value
{
    _showErrorLocations = !!value;
}

#ifdef OO_DEBUG_MONITOR_ENABLED
- (BOOL)dumpStackForErrors
{
    return _dumpStackForErrors;
}

- (void)setDumpStackForErrors:(BOOL)value
{
    _dumpStackForErrors = !!value;
}

- (BOOL)dumpStackForWarnings
{
    return _dumpStackForWarnings;
}

- (void)setDumpStackForWarnings:(BOOL)value
{
    _dumpStackForWarnings = !!value;
}

- (void)enableDebuggerStatement
{
    // QuickJS treats the debugger statement as a no-op and has no hook for it.
}
#endif

@end

#if OOJSENGINE_MONITOR_SUPPORT

@implementation OOJavaScriptEngine (OOMonitorSupport)

- (void)setMonitor:(id<OOJavaScriptEngineMonitor>)inMonitor
{
    [_monitor autorelease];
    _monitor = [inMonitor retain];
}

@end

@implementation OOJavaScriptEngine (OOMonitorSupportInternal)

- (void)sendMonitorProblemOfSeverity:(NSString*)severity
                              inFile:(NSString*)file
                                line:(unsigned)line
                         withMessage:(NSString*)message
                           inContext:(JSContext*)theContext
{
    if ([_monitor respondsToSelector:@selector(jsEngine:context:problemOfSeverity:inFile:line:stackSkip:showingLocation:withMessage:)]) {
        [_monitor jsEngine:self context:theContext problemOfSeverity:severity inFile:file line:line stackSkip:sErrorHandlerStackSkip showingLocation:[self showErrorLocations] withMessage:message];
    }
}

- (void)sendMonitorLogMessage:(NSString*)message
             withMessageClass:(NSString*)messageClass
                    inContext:(JSContext*)theContext
{
    if ([_monitor respondsToSelector:@selector(jsEngine:context:logMessage:ofClass:)]) {
        [_monitor jsEngine:self context:theContext logMessage:message ofClass:messageClass];
    }
}

@end

#endif

/*	Define the SpiderMonkey extensions OXPs rely on (toSource(), uneval()...)
        before any other script runs. The script is run as plain global code, not
        wrapped like normal scripts.
*/
static void LoadCompatibilityScript(JSContext* context)
{
    NSString* path = [ResourceManager pathForFileNamed:@"oolite-quickjs-compat.js" inFolder:@"Scripts"];
    NSString* source = (path != nil) ? [NSString stringWithContentsOfUnicodeFile:path] : nil;
    if (source == nil) {
        OOLogERR(@"script.javaScript.init.error", @"%@", @"Could not load oolite-quickjs-compat.js; SpiderMonkey compatibility functions such as toSource() will be missing.");
        return;
    }

    NSData* utf8 = [source dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableData* terminated = [NSMutableData dataWithData:utf8];
    [terminated appendBytes:"" length:1]; // JS_Eval requires a terminating NUL.

    JSValue result = JS_Eval(context, [terminated bytes], [utf8 length], [path UTF8String], JS_EVAL_TYPE_GLOBAL);
    if (JS_IsException(result))
        OOJSReportPendingException(context);
    JS_FreeValue(context, result);

    /*	The bundled QuickJS-ng is patched (subprojects/packagefiles/quickjs-ng)
            for SpiderMonkey behaviour OXPs rely on. Warn if this one isn't, e.g.
            a system library.
    */
    static BOOL checked = NO;
    if (!checked) {
        checked = YES;
        const char* test = "(function () { 'use strict'; try { 'x'.oolite = 1; return true; } catch (e) { return false; } })()";
        JSValue patched = JS_Eval(context, test, strlen(test), "<compatibility check>", JS_EVAL_TYPE_GLOBAL);
        if (!JS_IsException(patched) && !OOJSValueToBOOL(context, patched)) {
            OOLogWARN(@"script.javaScript.init.unpatchedEngine", @"%@", @"This QuickJS-ng library lacks Oolite's compatibility patches; some OXPs that worked with SpiderMonkey may fail. Build with the bundled QuickJS-ng subproject.");
        }
        if (JS_IsException(patched))
            JS_FreeValue(context, JS_GetException(context));
        JS_FreeValue(context, patched);
    }
}

NSString* OOJSWrapScriptSource(NSString* source)
{
    // A newline before the closing part is needed if the last line is a // comment.
    NSString* lineEnd = [source hasSuffix:@"\n"] ? @"" : @"\n";
    return [NSString stringWithFormat:@"with(this){(function(){%@%@}).call(this)}", source, lineEnd];
}

BOOL OOJSValueToBOOL(JSContext* context, JSValueConst value)
{
    int result = JS_ToBool(context, value);
    if (result < 0) {
        JS_FreeValue(context, JS_GetException(context));
        return NO;
    }
    return result != 0;
}

BOOL OOJSValueToInt32(JSContext* context, JSValueConst value, int32_t* outValue)
{
    double number;
    if (JS_ToFloat64(context, &number, value) < 0)
        return NO;

    number = floor(number + 0.5);
    if (isnan(number) || number < INT32_MIN || number > INT32_MAX) {
        OOJSReportError(context, @"can't convert %@ to an integer", OOStringFromJSValueEvenIfNull(context, value));
        return NO;
    }

    *outValue = (int32_t)number;
    return YES;
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

#ifndef NDEBUG
void OOJSResetTimeLimiter(void)
{
    sLimiterStart = MonotonicTime();
}

OOTimeDelta OOJSGetTimeLimiterLimit(void)
{
    return sLimiterTimeLimit;
}

void OOJSSetTimeLimiterLimit(OOTimeDelta limit)
{
    sLimiterTimeLimit = limit;
}
#endif

#if OOJS_PROFILE
void OOJSExcludeTimeFromLimiter(OOTimeDelta time)
{
    /*	Equivalent of pausing/resuming time limiter, except that it guarantees
            excluded time will match profiler overhead if there are no other
            pauses happening.
    */
    if (sLimiterPauseDepth == 0)
        sLimiterTimeLimit += time;
}
#endif

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
#ifdef OO_DEBUG_MONITOR_ENABLED
    OOJSDumpStack(gOOJSMainThreadContext);
#endif
    return 1;
}

//===========================================================================
// Error reporting
//===========================================================================

/*	QuickJS records locations only in the stack property, as lines of the form
        "    at name (file:line:column)" or "    at file:line:column".
        Extract the file and line of the innermost frame with a location.
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

static NSString* CurrentStack(JSContext* context)
{
    // A fresh Error object captures the current JS stack.
    JSValue error = JS_NewError(context);
    NSString* result = StackOfValue(context, error);
    JS_FreeValue(context, error);
    return result;
}

static void LogProblem(JSContext* context, NSString* severity, NSString* errorName, NSString* message, NSString* stack)
{
    NSString* messageClass = [NSString stringWithFormat:@"script.javaScript.%@.%@", severity, errorName];
    NSString* highlight = [severity isEqualToString:@"warning"] ? @"-----" : @"*****";
    OOJavaScriptEngine* jsEng = [OOJavaScriptEngine sharedEngine];

    // Skip the rest if this is a warning being ignored.
    if (!OOLogWillDisplayMessagesInClass(messageClass))
        return;

    // avoid windows DEP exceptions!
    OOJSScript* thisScript = [[OOJSScript currentlyRunningScript] weakRetain];
    NSString* activeScript = [[thisScript weakRefUnderlyingObject] displayName];
    [thisScript release];
    if (activeScript == nil)
        activeScript = @"<unidentified script>";
    OOLog(messageClass, @"%@ JavaScript %@ (%@): %@", highlight, severity, activeScript, message);

    NSString* file = nil;
    unsigned line = 0;
    if ([jsEng showErrorLocations] && sErrorHandlerStackSkip == 0 && GetLocationFromStack(stack, &file, &line)) {
        OOLog(messageClass, @"      %@, line %u.", file, line);
    }

#ifdef OO_DEBUG_MONITOR_ENABLED
    BOOL dump = [severity isEqualToString:@"warning"] ? [jsEng dumpStackForWarnings] : [jsEng dumpStackForErrors];
    if (dump && stack != nil)
        OOLog(@"script.javaScript.stackTrace", @"%@", stack);
#endif

#if OOJSENGINE_MONITOR_SUPPORT
    if (file == nil)
        GetLocationFromStack(stack, &file, &line);
    [jsEng sendMonitorProblemOfSeverity:severity
                                 inFile:file
                                   line:line
                            withMessage:message
                              inContext:context];
#endif
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

    NSString* message = OOStringFromJSValueEvenIfNull(context, exception);
    if (!JS_IsError(exception)) {
        message = [@"uncaught exception: " stringByAppendingString:message ?: @"?"];
    }

    LogProblem(context, @"exception", errorName, message, StackOfValue(context, exception));

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

JSValue OOJSNativeFailure(JSContext* context)
{
    if (JS_HasException(context))
        return JS_EXCEPTION;

    // Uncatchable errors are not reported by OOJSReportPendingException().
    JSValue error = JS_NewError(context);
    JS_SetUncatchableError(context, error);
    return JS_Throw(context, error);
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
        OOJSPauseTimeLimiter();
        // SpiderMonkey reported Oolite's own warnings as error number 206, "ooliteDefined" in javascript-errors.plist.
        LogProblem(context, @"warning", @"ooliteDefined", msg, CurrentStack(context));
        OOJSResumeTimeLimiter();
    }
    @catch (id exception) {
        // Squash any secondary errors during error handling.
    }
    [msg release];
}

NSString* OOStringFromJSPropertyMagic(int magic, const JSCFunctionListEntry* list, size_t count)
{
    for (size_t i = 0; i < count; i++) {
        if (list[i].def_type == JS_DEF_CGETSET_MAGIC && list[i].magic == magic)
            return [NSString stringWithUTF8String:list[i].name];
    }
    return [NSString stringWithFormat:@"%i", magic];
}

void OOJSReportBadPropertySelector(JSContext* context, JSValueConst thisObj, int magic, const JSCFunctionListEntry* list, size_t count)
{
    NSString* propName = OOStringFromJSPropertyMagic(magic, list, count);
    NSString* className = OOJSClassNameOfValue(context, thisObj);

    OOJSReportError(context, @"Invalid property identifier %@ for instance of %@.", propName, className);
}

void OOJSReportBadPropertyValue(JSContext* context, JSValueConst thisObj, int magic, const JSCFunctionListEntry* list, size_t count, JSValueConst value)
{
    NSString* propName = OOStringFromJSPropertyMagic(magic, list, count);
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

void OOJSSetWarningOrErrorStackSkip(unsigned skip)
{
    sErrorHandlerStackSkip = skip;
}

#if OOLITE_DEBUG || defined(OO_DEBUG_MONITOR_ENABLED)
void OOJSDumpStack(JSContext* context)
{
    NSString* stack = CurrentStack(context);
    OOLog(@"script.javaScript.stackTrace", @"%@", stack ?: @"<no JavaScript stack>");
}
#endif

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
// Property IDs
//===========================================================================

JSAtom OOJSInternAtomPRIVATE(const char* name)
{
    NSCParameterAssert(name != NULL && name[0] != '\0');

    JSAtom atom = JS_NewAtom(OOJSAcquireContext(), name);
    if (EXPECT_NOT(atom == JS_ATOM_NULL)) {
        [NSException raise:NSGenericException format:@"Failed to initialize JS ID cache for \"%s\".", name];
    }
    return atom;
}

JSAtom OOJSIDFromString(NSString* string)
{
    static NSMutableDictionary* sAtomCache = nil;

    if (EXPECT_NOT(string == nil))
        return JS_ATOM_NULL;

    NSNumber* cached = [sAtomCache objectForKey:string];
    if (cached != nil)
        return (JSAtom)[cached unsignedIntValue];

    NSData* utf8 = [string dataUsingEncoding:NSUTF8StringEncoding];
    JSAtom atom = JS_NewAtomLen(OOJSAcquireContext(), [utf8 bytes], [utf8 length]);
    if (EXPECT(atom != JS_ATOM_NULL)) {
        if (sAtomCache == nil)
            sAtomCache = [[NSMutableDictionary alloc] init];
        [sAtomCache setObject:[NSNumber numberWithUnsignedInt:atom] forKey:string];
    }
    return atom;
}

NSString* OOStringFromJSID(JSAtom propID)
{
    JSContext* context = OOJSAcquireContext();
    JSValue value = JS_AtomToString(context, propID);
    NSString* result = OOStringFromJSValue(context, value);
    JS_FreeValue(context, value);
    return result;
}

//===========================================================================
// Native to JS conversion
//===========================================================================

static JSValue JSArrayFromNSArray(JSContext* context, NSArray* array)
{
    if (array == nil)
        return JS_UNDEFINED;

    JSValue result = JS_NewArray(context);
    if (JS_IsException(result))
        return JS_UNDEFINED;

    @try {
        NSUInteger i, count = [array count];
        for (i = 0; i != count; ++i) {
            // JS_SetPropertyUint32() takes ownership of the value.
            JSValue value = [[array objectAtIndex:i] oo_jsValueInContext:context];
            if (EXPECT_NOT(JS_SetPropertyUint32(context, result, (uint32_t)i, value) < 0)) {
                JS_FreeValue(context, result);
                return JS_UNDEFINED;
            }
        }
    }
    @catch (id ex) {
        JS_FreeValue(context, result);
        return JS_UNDEFINED;
    }

    return result;
}

/*	Convert an NSDictionary to a JavaScript Object.
        Only properties whose keys are either strings or non-negative NSNumbers,
        and	whose values have a non-void JS representation, are converted.
*/
static JSValue JSObjectFromNSDictionary(JSContext* context, NSDictionary* dictionary)
{
    if (dictionary == nil)
        return JS_UNDEFINED;

    JSValue result = JS_NewObject(context);
    if (JS_IsException(result))
        return JS_UNDEFINED;

    BOOL OK = YES;
    @try {
        id key = nil;
        foreachkey(key, dictionary)
        {
            JSValue value = JS_UNDEFINED;
            if ([key isKindOfClass:[NSString class]] && [key length] != 0) {
                value = [[dictionary objectForKey:key] oo_jsValueInContext:context];
                if (!JS_IsUndefined(value)) {
                    OK = JS_SetProperty(context, result, OOJSIDFromString(key), value) >= 0;
                }
            } else if ([key isKindOfClass:[NSNumber class]]) {
                int index = [key intValue];
                if (0 < index) {
                    value = [[dictionary objectForKey:key] oo_jsValueInContext:context];
                    if (!JS_IsUndefined(value)) {
                        OK = JS_SetPropertyUint32(context, result, (uint32_t)index, value) >= 0;
                    }
                }
            }

            if (EXPECT_NOT(!OK))
                break;
        }
    }
    @catch (id exception) {
        OK = NO;
    }

    if (EXPECT_NOT(!OK)) {
        JS_FreeValue(context, result);
        return JS_UNDEFINED;
    }

    return result;
}

@implementation NSObject (OOJavaScript)

- (JSValue)oo_jsValueInContext:(JSContext*)context
{
    return JS_UNDEFINED;
}

- (NSString*)oo_jsClassName
{
    return nil;
}

- (NSString*)oo_jsDescription
{
    return [self oo_jsDescriptionWithClassName:[self oo_jsClassName]];
}

- (NSString*)oo_jsDescriptionWithClassName:(NSString*)className
{
    NSString* components = nil;
    NSString* description = nil;

    components = [self descriptionComponents];
    if (className == nil)
        className = [[self class] description];

    if (components != nil) {
        description = [NSString stringWithFormat:@"[%@ %@]", className, components];
    } else {
        description = [NSString stringWithFormat:@"[object %@]", className];
    }

    return description;
}

- (void)oo_clearJSSelf:(JSValueConst)selfVal
{
}

@end

JSValue OOJSObjectFromNativeObject(JSContext* context, id object)
{
    JSValue value = OOJSValueFromNativeObject(context, object);
    if (JS_IsObject(value) || JS_IsException(value))
        return value;

    JSValue result = JS_ToObject(context, value);
    JS_FreeValue(context, value);
    return result;
}

@implementation OOJSValue

+ (id)valueWithJSValue:(JSValueConst)value inContext:(JSContext*)context
{
    return [[[self alloc] initWithJSValue:value inContext:context] autorelease];
}

- (id)initWithJSValue:(JSValueConst)value inContext:(JSContext*)context
{
    self = [super init];
    if (self != nil) {
        if (context == NULL)
            context = OOJSAcquireContext();

        _val = JS_DupValue(context, value);
        if (!JS_IsUndefined(_val)) {
            [[NSNotificationCenter defaultCenter] addObserver:self
                                                     selector:@selector(deleteJSValue)
                                                         name:kOOJavaScriptEngineWillResetNotification
                                                       object:[OOJavaScriptEngine sharedEngine]];
        }
    }
    return self;
}

- (void)deleteJSValue
{
    if (!JS_IsUndefined(_val)) {
        JS_FreeValue(OOJSAcquireContext(), _val);
        _val = JS_UNDEFINED;

        [[NSNotificationCenter defaultCenter] removeObserver:self
                                                        name:kOOJavaScriptEngineWillResetNotification
                                                      object:[OOJavaScriptEngine sharedEngine]];
    }
}

- (void)dealloc
{
    [self deleteJSValue];
    [super dealloc];
}

- (JSValue)oo_jsValueInContext:(JSContext*)context
{
    return JS_DupValue(context, _val);
}

@end

//===========================================================================
// String utilities
//===========================================================================

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

    const char* registered = OOJSClassName(JS_GetClassID(value));
    if (registered != NULL)
        return [NSString stringWithUTF8String:registered];

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
    JSClassID classID = JS_GetClassID(value);

    if (JS_IsString(value) || (classID != JS_INVALID_CLASS_ID && classID == gOOJSStringClassID)) {
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
            JS_FreeValue(context, JS_GetException(context));
            result = @"[...]";
        }
    }

    if (result == nil) {
        result = OOStringFromJSValueEvenIfNull(context, value);

        if (abbreviateObjects && classID == gOOJSObjectClassID && [result isEqualToString:@"[object Object]"]) {
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

- (JSValue)oo_jsValueInContext:(JSContext*)context
{
    NSData* utf8 = [self dataUsingEncoding:NSUTF8StringEncoding];
    return JS_NewStringLen(context, [utf8 bytes], [utf8 length]);
}

+ (NSString*)concatenationOfStringsFromJavaScriptValues:(JSValueConst*)values count:(size_t)count separator:(NSString*)separator inContext:(JSContext*)context
{
    size_t i;
    NSMutableString* result = nil;
    NSString* element = nil;

    if (count < 1)
        return nil;
    if (values == NULL)
        return NULL;

    for (i = 0; i != count; ++i) {
        element = OOStringFromJSValueEvenIfNull(context, values[i]);
        if (result == nil)
            result = [[element mutableCopy] autorelease];
        else {
            if (separator != nil)
                [result appendString:separator];
            [result appendString:element];
        }
    }

    return result;
}

- (NSString*)escapedForJavaScriptLiteral
{
    NSMutableString* result = nil;
    NSUInteger i, length;
    unichar c;
    NSAutoreleasePool* pool = nil;

    length = [self length];
    result = [NSMutableString stringWithCapacity:length];

    // Not hugely efficient.
    pool = [[NSAutoreleasePool alloc] init];
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
    [pool release];

    return result;
}

- (NSString*)oo_jsClassName
{
    return @"String";
}

@end

@implementation NSArray (OOJavaScriptConversion)

- (JSValue)oo_jsValueInContext:(JSContext*)context
{
    return JSArrayFromNSArray(context, self);
}

@end

@implementation OONativeVector (OOJavaScriptConversion)

- (JSValue)oo_jsValueInContext:(JSContext*)context
{
    JSValue value = JS_UNDEFINED;
    VectorToJSValue(context, [self getVector], &value);
    return value;
}

@end

@implementation NSDictionary (OOJavaScriptConversion)

- (JSValue)oo_jsValueInContext:(JSContext*)context
{
    return JSObjectFromNSDictionary(context, self);
}

@end

@implementation NSNumber (OOJavaScriptConversion)

- (JSValue)oo_jsValueInContext:(JSContext*)context
{
    // As with SpiderMonkey, all NSNumbers (including booleans) become JS numbers.
    if ([self oo_isFloatingPointNumber])
        return JS_NewFloat64(context, [self doubleValue]);
    return JS_NewNumber(context, (double)[self longLongValue]);
}

- (NSString*)oo_jsClassName
{
    return @"Number";
}

@end

@implementation NSNull (OOJavaScriptConversion)

- (JSValue)oo_jsValueInContext:(JSContext*)context
{
    return JS_NULL;
}

@end

//===========================================================================
// Reusable callbacks
//===========================================================================

JSValue OOJSUnconstructableConstruct(JSContext* context, JSValueConst this, int argc, JSValueConst* argv)
{
    // For constructors, this is new.target, i.e. the constructor function itself.
    JSValue nameVal = JS_GetPropertyStr(context, this, "name");
    NSString* name = OOStringFromJSValue(context, nameVal);
    JS_FreeValue(context, nameVal);

    OOJSReportError(context, @"%@ cannot be used as a constructor.", name);
    return JS_EXCEPTION;
}

void OOJSObjectWrapperFinalize(JSRuntime* runtime, JSValueConst this)
{
    JSClassID classID;
    id object = JS_GetAnyOpaque(this, &classID);
    if (object != nil) {
        [[object weakRefUnderlyingObject] oo_clearJSSelf:this];
        [object release];
        JS_SetOpaque(this, NULL);
    }
}

JSValue OOJSObjectWrapperToString(JSContext* context, JSValueConst this, int argc, JSValueConst* argv)
{
    OOJS_NATIVE_ENTER(context)

    id object = nil;
    NSString* description = nil;

    object = OOJSNativeObjectFromJSObject(context, this);
    if (object != nil) {
        description = [object oo_jsDescription];
        if (description == nil)
            description = [object description];
    }
    if (description == nil) {
        const char* className = OOJSClassName(JS_GetClassID(this));
        if (className != NULL) {
            description = [NSString stringWithFormat:@"[object %@]", [NSString stringWithUTF8String:className]];
        }
    }
    if (description == nil)
        description = @"[object]";

    OOJS_RETURN_OBJECT(description);

    OOJS_NATIVE_EXIT
}

//===========================================================================
// Entity predicates
//===========================================================================

BOOL JSFunctionPredicate(Entity* entity, void* parameter)
{
    JSFunctionPredicateParameter* param = parameter;
    BOOL result = NO;

    NSCParameterAssert(entity != nil && param != NULL);
    NSCParameterAssert(param->context != NULL);
    NSCParameterAssert(OOJSValueIsFunction(param->context, param->function));

    if (EXPECT_NOT(param->errorFlag))
        return NO;

    JSValue arg = [entity oo_jsValueInContext:param->context]; // entity is required to be non-nil (asserted above), so oo_jsValueInContext: is safe.

    OOJSStartTimeLimiter();
    OOJSResumeTimeLimiter();
    JSValue rval = JS_Call(param->context, param->function, param->jsThis, 1, (JSValueConst*)&arg);
    OOJSPauseTimeLimiter();
    OOJSStopTimeLimiter();

    JS_FreeValue(param->context, arg);

    if (!JS_IsException(rval)) {
        result = OOJSValueToBOOL(param->context, rval);
        JS_FreeValue(param->context, rval);
    } else {
        OOJSReportPendingException(param->context);
        param->errorFlag = YES;
    }

    return result;
}

BOOL JSEntityIsJavaScriptVisiblePredicate(Entity* entity, void* parameter)
{
    return [entity isVisibleToScripts];
}

BOOL JSEntityIsJavaScriptSearchablePredicate(Entity* entity, void* parameter)
{
    if (![entity isVisibleToScripts])
        return NO;
    if ([entity isShip]) {
        if ([entity isSubEntity])
            return NO;
        if ([entity status] == STATUS_COCKPIT_DISPLAY)
            return NO; // Demo ship
        return YES;
    } else if ([entity isPlanet]) {
        switch ([(OOPlanetEntity*)entity planetType]) {
        case STELLAR_TYPE_MOON:
        case STELLAR_TYPE_NORMAL_PLANET:
        case STELLAR_TYPE_SUN:
            return YES;

#if !NEW_PLANETS
        case STELLAR_TYPE_ATMOSPHERE:
#endif
        case STELLAR_TYPE_MINIATURE:
            return NO;
        }
    }

    return YES; // would happen if we added a new script-visible class
}

BOOL JSEntityIsDemoShipPredicate(Entity* entity, void* parameter)
{
    return ([entity isVisibleToScripts] && [entity isShip] && [entity status] == STATUS_COCKPIT_DISPLAY && ![entity isSubEntity]);
}

//===========================================================================
// Classes
//===========================================================================

// Class registration lives in OOJSClasses.m.

BOOL OOJSObjectGetterImplPRIVATE(JSContext* context, JSValueConst object, JSClassID requiredClassID, Class requiredObjCClass, const char* name, id* outObject)
{
    NSCParameterAssert(requiredObjCClass != Nil);
    NSCParameterAssert(context != NULL && requiredClassID != 0 && outObject != NULL);

    /*
            Ensure it's a valid type of JS object. This is absolutely necessary,
            because if we don't check it we'll crash trying to get the private
            field of something that isn't an ObjC object wrapper - for example,
            Ship.setAI.call(new Vector3D, "") is valid JavaScript.
    */
    JSClassID actualClassID = JS_GetClassID(object);
    if (EXPECT_NOT(!OOJSIsSubclass(actualClassID, requiredClassID))) {
        OOJSReportError(context, @"Native method expected %s, got %@.", OOJSClassName(requiredClassID), OOStringFromJSValue(context, object));
        return NO;
    }

    // Get the underlying object.
    JSClassID ignored;
    *outObject = [(id)JS_GetAnyOpaque(object, &ignored) weakRefUnderlyingObject];

#ifndef NDEBUG
    // Double-check that the underlying object is of the expected ObjC class.
    if (EXPECT_NOT(*outObject != nil && ![*outObject isKindOfClass:requiredObjCClass])) {
        OOJSReportError(context, @"Native method expected %@ from %s and got correct JS type but incorrect native object %@", requiredObjCClass, OOJSClassName(requiredClassID), *outObject);
        return NO;
    }
#endif

    return YES;
}

//===========================================================================
// JS to native conversion
//===========================================================================

NSDictionary* OOJSDictionaryFromJSValue(JSContext* context, JSValueConst value)
{
    if (EXPECT_NOT(!JS_IsObject(value))) {
        return nil;
    }
    return OOJSDictionaryFromJSObject(context, value);
}

// Integer-like property names become NSNumbers, as SpiderMonkey's int jsids did.
static id KeyForAtom(JSContext* context, JSAtom atom)
{
    NSString* key = OOStringFromJSID(atom);
    if ([key length] != 0 && [key length] < 10) {
        unichar first = [key characterAtIndex:0];
        if ((first >= '1' && first <= '9') || [key isEqualToString:@"0"]) {
            NSScanner* scanner = [NSScanner scannerWithString:key];
            int intValue;
            if ([scanner scanInt:&intValue] && [scanner isAtEnd]) {
                return [NSNumber numberWithInt:intValue];
            }
        }
    }
    return key;
}

NSDictionary* OOJSDictionaryFromJSObject(JSContext* context, JSValueConst object)
{
    JSPropertyEnum* properties = NULL;
    uint32_t i, count;

    if (JS_GetOwnPropertyNames(context, &properties, &count, object, JS_GPN_STRING_MASK | JS_GPN_ENUM_ONLY) < 0) {
        JS_FreeValue(context, JS_GetException(context));
        return nil;
    }

    NSMutableDictionary* result = [NSMutableDictionary dictionaryWithCapacity:count];
    for (i = 0; i != count; ++i) {
        id objKey = KeyForAtom(context, properties[i].atom);
        JSValue value = JS_GetProperty(context, object, properties[i].atom);
        if (JS_IsException(value)) {
            JS_FreeValue(context, JS_GetException(context));
            continue;
        }

        if (objKey != nil && !JS_IsUndefined(value)) {
            id objValue = OOJSNativeObjectFromJSValue(context, value);
            if (objValue != nil) {
                [result setObject:objValue forKey:objKey];
            }
        }
        JS_FreeValue(context, value);
    }

    JS_FreePropertyEnum(context, properties, count);
    return result;
}

NSDictionary* OOJSDictionaryFromStringTable(JSContext* context, JSValueConst tableValue)
{
    JSPropertyEnum* properties = NULL;
    uint32_t i, count;

    if (EXPECT_NOT(JS_IsNull(tableValue) || JS_IsUndefined(tableValue))) {
        return nil;
    }

    JSValue tableObject = JS_ToObject(context, tableValue);
    if (JS_IsException(tableObject)) {
        JS_FreeValue(context, JS_GetException(context));
        return nil;
    }

    if (JS_GetOwnPropertyNames(context, &properties, &count, tableObject, JS_GPN_STRING_MASK | JS_GPN_ENUM_ONLY) < 0) {
        JS_FreeValue(context, JS_GetException(context));
        JS_FreeValue(context, tableObject);
        return nil;
    }

    NSMutableDictionary* result = [NSMutableDictionary dictionaryWithCapacity:count];
    for (i = 0; i != count; ++i) {
        NSString* objKey = OOStringFromJSID(properties[i].atom);
        JSValue value = JS_GetProperty(context, tableObject, properties[i].atom);
        if (JS_IsException(value)) {
            JS_FreeValue(context, JS_GetException(context));
            continue;
        }

        if (objKey != nil && !JS_IsUndefined(value)) {
            NSString* objValue = OOStringFromJSValueEvenIfNull(context, value);
            if (objValue != nil) {
                [result setObject:objValue forKey:objKey];
            }
        }
        JS_FreeValue(context, value);
    }

    JS_FreePropertyEnum(context, properties, count);
    JS_FreeValue(context, tableObject);
    return result;
}

// Indexed by class ID; process lifetime.
static OOJSClassConverterCallback sObjectConverters[kOOJSMaxClassID];

JSClassID gOOJSObjectClassID, gOOJSStringClassID, gOOJSArrayClassID, gOOJSNumberClassID, gOOJSBooleanClassID;

id OOJSNativeObjectFromJSValue(JSContext* context, JSValueConst value)
{
    if (JS_IsNull(value) || JS_IsUndefined(value))
        return nil;

    int32_t intValue;
    double doubleValue;

    if (JS_VALUE_GET_TAG(value) == JS_TAG_INT) {
        JS_ToInt32(context, &intValue, value);
        return [NSNumber numberWithInt:intValue];
    }
    if (JS_IsNumber(value)) {
        JS_ToFloat64(context, &doubleValue, value);
        return [NSNumber numberWithDouble:doubleValue];
    }
    if (JS_IsBool(value)) {
        return [NSNumber numberWithBool:JS_VALUE_GET_BOOL(value)];
    }
    if (JS_IsString(value)) {
        return OOStringFromJSValue(context, value);
    }
    if (JS_IsObject(value)) {
        return OOJSNativeObjectFromJSObject(context, value);
    }
    return nil;
}

id OOJSNativeObjectFromJSObject(JSContext* context, JSValueConst object)
{
    if (!JS_IsObject(object))
        return nil;

    JSClassID classID = JS_GetClassID(object);
    OOJSClassConverterCallback converter = (classID < kOOJSMaxClassID) ? sObjectConverters[classID] : NULL;
    if (converter != NULL) {
        return converter(context, object);
    }
    return nil;
}

id OOJSNativeObjectOfClassFromJSValue(JSContext* context, JSValueConst value, Class requiredClass)
{
    id result = OOJSNativeObjectFromJSValue(context, value);
    if (![result isKindOfClass:requiredClass])
        result = nil;
    return result;
}

id OOJSNativeObjectOfClassFromJSObject(JSContext* context, JSValueConst object, Class requiredClass)
{
    id result = OOJSNativeObjectFromJSObject(context, object);
    if (![result isKindOfClass:requiredClass])
        result = nil;
    return result;
}

id OOJSBasicPrivateObjectConverter(JSContext* context, JSValueConst object)
{
    /*	This will do the right thing - for non-OOWeakReferences,
            weakRefUnderlyingObject returns the object itself. For nil, of course,
            it returns nil.
    */
    JSClassID ignored;
    id result = JS_GetAnyOpaque(object, &ignored);
    return [result weakRefUnderlyingObject];
}

void OOJSRegisterObjectConverter(JSClassID classID, OOJSClassConverterCallback converter)
{
    if (classID == 0 || classID >= kOOJSMaxClassID)
        return;
    sObjectConverters[classID] = converter;
}

static id JSArrayConverter(JSContext* context, JSValueConst array)
{
    int64_t i, count;

    // Convert a JS array to an NSArray by calling OOJSNativeObjectFromJSValue() on all its elements.
    if (!JS_IsArray(array))
        return nil;
    if (JS_GetLength(context, array, &count) < 0) {
        JS_FreeValue(context, JS_GetException(context));
        return nil;
    }

    NSMutableArray* result = [NSMutableArray arrayWithCapacity:(NSUInteger)count];
    for (i = 0; i != count; ++i) {
        JSValue value = JS_GetPropertyUint32(context, array, (uint32_t)i);
        if (JS_IsException(value)) {
            JS_FreeValue(context, JS_GetException(context));
            value = JS_UNDEFINED;
        }

        id object = OOJSNativeObjectFromJSValue(context, value);
        JS_FreeValue(context, value);
        if (object == nil)
            object = [NSNull null];
        [result addObject:object];
    }

    return result;
}

static id JSStringConverter(JSContext* context, JSValueConst object)
{
    return OOStringFromJSValue(context, object);
}

static id JSNumberConverter(JSContext* context, JSValueConst object)
{
    double value;
    if (JS_ToFloat64(context, &value, object) == 0) {
        return [NSNumber numberWithDouble:value];
    }
    JS_FreeValue(context, JS_GetException(context));
    return nil;
}

static id JSBooleanConverter(JSContext* context, JSValueConst object)
{
    /*	Fun With JavaScript: Boolean(false) is a truthy value, since it's a
            non-null object. However, Boolean objects are transformed to numbers
            sanely, so this works.
    */
    double value;
    if (JS_ToFloat64(context, &value, object) == 0) {
        return [NSNumber numberWithBool:(value != 0)];
    }
    JS_FreeValue(context, JS_GetException(context));
    return nil;
}

static id JSObjectConverter(JSContext* context, JSValueConst object)
{
    /*	SpiderMonkey's global object had a class of its own, with no converter,
            so it converted to nil. QuickJS's is a plain object, and converting it
            as one recurses until the stack overflows, since globalThis refers to
            itself; a Timer whose this is the global object did that on firing.
    */
    JSValue global = JS_GetGlobalObject(context);
    BOOL isGlobal = JS_IsStrictEqual(context, global, object);
    JS_FreeValue(context, global);
    if (isGlobal)
        return nil;

    return OOJSDictionaryFromJSObject(context, object);
}

static void RegisterStandardObjectConverters(JSContext* context)
{
    if (gOOJSObjectClassID == 0) {
        // The standard class IDs are not part of the QuickJS API, so look them up from instances.
        const char* source = "[{}, new String(''), [], new Number(0), new Boolean(false)]";
        JSValue templates = JS_Eval(context, source, strlen(source), "<init>", JS_EVAL_TYPE_GLOBAL);
        JSClassID* ids[] = { &gOOJSObjectClassID, &gOOJSStringClassID, &gOOJSArrayClassID, &gOOJSNumberClassID, &gOOJSBooleanClassID };
        for (uint32_t i = 0; i < OOJS_COUNT(ids); i++) {
            JSValue item = JS_GetPropertyUint32(context, templates, i);
            *ids[i] = JS_GetClassID(item);
            JS_FreeValue(context, item);
        }
        JS_FreeValue(context, templates);
    }

    OOJSRegisterObjectConverter(gOOJSObjectClassID, JSObjectConverter);
    OOJSRegisterObjectConverter(gOOJSStringClassID, JSStringConverter);
    OOJSRegisterObjectConverter(gOOJSArrayClassID, JSArrayConverter);
    OOJSRegisterObjectConverter(gOOJSNumberClassID, JSNumberConverter);
    OOJSRegisterObjectConverter(gOOJSBooleanClassID, JSBooleanConverter);
}
