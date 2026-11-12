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

#include "oofnd/Defaults.hpp"
#include "oofnd/Encoding.hpp"
#include "oofnd/FileSystem.hpp"
#include "oofnd/Log.hpp"
#include "oofnd/Notification.hpp"
#include "oofnd/PList.hpp"
#include "oofnd/PListGet.hpp"
#include "oofnd/Scanner.hpp"
#include "oofnd/StdLib.hpp"
#include "oofnd/String.hpp"

#import "EntityOOJavaScriptExtensions.h"
#import "OOConstToJSString.h"
#import "OOFoundationBridge.h"
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

#import "OOFoundationException.h"
#import "OOStringBridge.h"

#include "oofnd/objc/OOAssert.h"

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

// file is nullopt when the stack gives no location (a nil file before).
- (void)sendMonitorProblemOfSeverity:(const std::string&)severity
                              inFile:(const std::optional<std::string>&)file
                                line:(unsigned)line
                         withMessage:(const std::string&)message
                           inContext:(JSContext*)context;

// nullopt is meaningful to the monitor (Log() with a null message; no class for Log()).
- (void)sendMonitorLogMessage:(const std::optional<std::string>&)message
             withMessageClass:(const std::optional<std::string>&)messageClass
                    inContext:(JSContext*)context;

@end

#endif

static unsigned sErrorHandlerStackSkip = 0;

JSContext* gOOJSMainThreadContext = NULL;

static JSValue sLegacyConstRewriter = JS_UNDEFINED;

const char* const kOOJavaScriptEngineWillResetNotificationName = "org.aegidian.oolite OOJavaScriptEngine will reset";
const char* const kOOJavaScriptEngineDidResetNotificationName = "org.aegidian.oolite OOJavaScriptEngine did reset";

static int InterruptHandler(JSRuntime* runtime, void* opaque);
static void RegisterStandardObjectConverters(JSContext* context);
static void RemoveNonSpiderMonkeyGlobals(JSContext* context, JSValueConst global);
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
    OOAssert(sSharedEngine == nil, "Attempt to create multiple OOJavaScriptEngines.");

    if (!(self = [super init]))
        return nil;
    sSharedEngine = self;
    _showErrorLocations = YES;

    oo::Defaults& defaults = oo::Defaults::standard();
#ifdef OO_DEBUG_MONITOR_ENABLED
    /*	Set stack trace preferences from preferences. These will be overriden
            by the debug OXP script if installed, but being able to enable traces
            without setting up the debug console could be useful for debugging
            users' problems.
    */
    [self setDumpStackForErrors:defaults.boolForKey("dump-stack-for-errors")];
    [self setDumpStackForWarnings:defaults.boolForKey("dump-stack-for-warnings")];
#endif

    _runtime = JS_NewRuntime();
    if (_runtime == NULL) {
        OO_LOG("script.javaScript.init.error", "{}", "***** FATAL ERROR: failed to create JavaScript runtime.");
        exit(1);
    }

    const oo::PList jsRuntimeSize = defaults.object("jsruntime-size-mib");
    uint32_t jsRuntimeInMiB = static_cast<uint32_t>(oo::PListGet<int>::from(jsRuntimeSize.isNull() ? nullptr : &jsRuntimeSize, OOJS_RUNTIME_SIZE_MiB));
    JS_SetMemoryLimit(_runtime, jsRuntimeInMiB * 1024L * 1024L);
    JS_SetMaxStackSize(_runtime, OOJS_STACK_SIZE);
    JS_SetInterruptHandler(_runtime, InterruptHandler, NULL);

    [self createMainThreadContext];

    return self;
}

- (void)createMainThreadContext
{
    OOAssert(gOOJSMainThreadContext == NULL, "-[OOJavaScriptEngine createMainThreadContext] called while the main thread context exists.");

    gOOJSMainThreadContext = JS_NewContext(_runtime);
    if (gOOJSMainThreadContext == NULL) {
        OO_LOG("script.javaScript.init.error", "{}", "***** FATAL ERROR: failed to create JavaScript context.");
        exit(1);
    }
    _context = gOOJSMainThreadContext;

    // Create the global object.
    _globalObject = JS_GetGlobalObject(_context);
    RemoveNonSpiderMonkeyGlobals(_context, _globalObject);
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
                           properties:oo::ObjectFromPList(oo::PList(oo::PList::Dict { { "special", oo::PListObject(specialWrapper) } }))];

    OO_LOG("script.javaScript.init.success", "{}", "Set up JavaScript context.");
}

- (void)destroyMainThreadContext
{
    if (gOOJSMainThreadContext != NULL) {
        OOConstToJSStringDestroy();

        JS_FreeValue(_context, sLegacyConstRewriter);
        sLegacyConstRewriter = JS_UNDEFINED;

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
            OO_LOG_WARN("script.javaScript.reset.liveObjects", "{} JavaScript objects are still alive after the context was destroyed; something is holding a JSValue it does not own, or has not freed one it does.", static_cast<long long>(usage.obj_count));
        } else {
            OO_LOG("script.javaScript.reset.liveObjects", "{}", "No JavaScript objects left alive after the context was destroyed.");
        }
#endif
    }
}

- (BOOL)reset
{
    OOAssert(gOOJSMainThreadContext != NULL, "JavaScript engine not active. Can't reset.");

    OOJSFrameCallbacksRemoveAll();

    oo::NotificationCenter::defaultCenter().post(kOOJavaScriptEngineWillResetNotificationName, self);

    [self destroyMainThreadContext];
    [self createMainThreadContext];

    oo::NotificationCenter::defaultCenter().post(kOOJavaScriptEngineDidResetNotificationName, self);

    [self garbageCollectionOpportunity:YES];
    OO_LOG("script.javascript.init", "{}", "JavaScript reset successful.");
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
        OO_LOG("script.javaScript.shutDown", "{}", "Not shutting down the JavaScript runtime (and skipping its leak check): quitting from inside a script.");
        return 0;
    }

    OOJSFrameCallbacksRemoveAll();
    oo::NotificationCenter::defaultCenter().post(kOOJavaScriptEngineWillResetNotificationName, self);
    [self destroyMainThreadContext];

    JSMemoryUsage usage;
    JS_ComputeMemoryUsage(_runtime, &usage);
    if (usage.obj_count != 0) {
        /*	JS_FreeRuntime() would assert. Dump what is left and abandon the
                runtime instead, so the leak can be reported.
        */
        OO_LOG("script.javaScript.shutDown.leak", "***** JavaScript runtime shut down with {} objects still alive; something is holding a JSValue it does not own, or has not freed one it does.", static_cast<long long>(usage.obj_count));
        _runtime = NULL;
        return (NSUInteger)usage.obj_count;
    }

    JS_FreeRuntime(_runtime);
    _runtime = NULL;
    OO_LOG("script.javaScript.shutDown", "{}", "JavaScript runtime shut down with no leaked objects.");
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
    OOParameterAssert(JS_IsFunction(_context, function));

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

- (void)sendMonitorProblemOfSeverity:(const std::string&)severity
                              inFile:(const std::optional<std::string>&)file
                                line:(unsigned)line
                         withMessage:(const std::string&)message
                           inContext:(JSContext*)theContext
{
    if ([_monitor respondsToSelector:@selector(jsEngine:context:problemOfSeverity:inFile:line:stackSkip:showingLocation:withMessage:)]) {
        [_monitor jsEngine:self context:theContext problemOfSeverity:oo::NSStringFrom(severity) inFile:oo::NSStringOrNil(file) line:line stackSkip:sErrorHandlerStackSkip showingLocation:[self showErrorLocations] withMessage:oo::NSStringFrom(message)];
    }
}

- (void)sendMonitorLogMessage:(const std::optional<std::string>&)message
             withMessageClass:(const std::optional<std::string>&)messageClass
                    inContext:(JSContext*)theContext
{
    if ([_monitor respondsToSelector:@selector(jsEngine:context:logMessage:ofClass:)]) {
        [_monitor jsEngine:self context:theContext logMessage:oo::NSStringOrNil(message) ofClass:oo::NSStringOrNil(messageClass)];
    }
}

@end

#endif

/*	QuickJS-ng defines ES2015 and later globals (Map, Symbol, Promise,
        globalThis...) that SpiderMonkey 1.8.5 didn't have. Remove them, so that
        OXPs see the same global object under either engine and can't come to
        depend on QuickJS-only features. Some couldn't work anyway: nothing runs
        the job queue, so Promise reactions and queueMicrotask() callbacks would
        never be called.
*/
static void RemoveNonSpiderMonkeyGlobals(JSContext* context, JSValueConst global)
{
    static const char* const kSpiderMonkeyGlobals[] = {
        "undefined", "NaN", "Infinity", "eval", "isNaN", "isFinite", "parseFloat", "parseInt",
        "escape", "unescape", "decodeURI", "encodeURI", "decodeURIComponent", "encodeURIComponent",
        "Object", "Function", "Array", "Boolean", "Number", "String", "Date", "RegExp", "Math", "JSON",
        "Error", "InternalError", "EvalError", "RangeError", "ReferenceError", "SyntaxError", "TypeError", "URIError",
        "ArrayBuffer", "Int8Array", "Uint8Array", "Uint8ClampedArray", "Int16Array", "Uint16Array",
        "Int32Array", "Uint32Array", "Float32Array", "Float64Array", "Proxy"
    };

    JSPropertyEnum* properties = NULL;
    uint32_t count = 0;
    if (JS_GetOwnPropertyNames(context, &properties, &count, global, JS_GPN_STRING_MASK) < 0) {
        JS_FreeValue(context, JS_GetException(context));
        return;
    }

    for (uint32_t i = 0; i < count; i++) {
        const char* name = JS_AtomToCString(context, properties[i].atom);
        BOOL keep = (name == NULL);
        for (size_t j = 0; !keep && j < sizeof kSpiderMonkeyGlobals / sizeof *kSpiderMonkeyGlobals; j++) {
            keep = (strcmp(name, kSpiderMonkeyGlobals[j]) == 0);
        }
        JS_FreeCString(context, name);
        if (!keep)
            JS_DeleteProperty(context, global, properties[i].atom, 0);
    }
    JS_FreePropertyEnum(context, properties, count);
}

JSValueConst OOJSLegacyConstRewriter(void)
{
    return sLegacyConstRewriter;
}

/*	Define the SpiderMonkey extensions OXPs rely on (toSource(), uneval()...)
        before any other script runs. The script is run as plain global code, not
        wrapped like normal scripts. Its result is the const rewriter.
*/
static void LoadCompatibilityScript(JSContext* context)
{
    const std::optional<std::string> path = [ResourceManager cxx_pathForFileNamed:"oolite-quickjs-compat.js" inFolder:std::string("Scripts")];
    std::optional<std::string> source;
    // +stringWithContentsOfUnicodeFile: (it read through .oxz archives)
    if (path.has_value()) {
        if (const std::optional<oo::Data> bytes = OODataFromOXZFile(*path))
            source = oo::str::decodeUnicodeText(bytes->stringView());
    }
    if (!source.has_value()) {
        OO_LOG_ERR("script.javaScript.init.error", "{}", "Could not load oolite-quickjs-compat.js; SpiderMonkey compatibility functions such as toSource() will be missing.");
        return;
    }

    // JS_Eval requires a terminating NUL, which std::string's c_str() has.
    JSValue result = JS_Eval(context, source->c_str(), source->size(), path->c_str(), JS_EVAL_TYPE_GLOBAL);
    if (JS_IsException(result))
        OOJSReportPendingException(context);
    else if (JS_IsFunction(context, result))
        sLegacyConstRewriter = JS_DupValue(context, result);
    JS_FreeValue(context, result);

    /*	The bundled QuickJS-ng is patched (subprojects/packagefiles/quickjs-ng)
            for SpiderMonkey behaviour OXPs rely on. Warn if this one isn't, e.g.
            a system library.
    */
    static BOOL checked = NO;
    if (!checked) {
        checked = YES;
        const char* test = "(function () { 'use strict'; try { 'x'.oolite = 1; new Math.max(); return true; } catch (e) { return false; } })()";
        JSValue patched = JS_Eval(context, test, strlen(test), "<compatibility check>", JS_EVAL_TYPE_GLOBAL);
        if (!JS_IsException(patched) && !OOJSValueToBOOL(context, patched)) {
            OO_LOG_WARN("script.javaScript.init.unpatchedEngine", "{}", "This QuickJS-ng library lacks Oolite's compatibility patches; some OXPs that worked with SpiderMonkey may fail. Build with the bundled QuickJS-ng subproject.");
        }
        if (JS_IsException(patched))
            JS_FreeValue(context, JS_GetException(context));
        JS_FreeValue(context, patched);
    }
}

NSString* OOJSWrapScriptSource(NSString* source)
{
    // A newline before the closing part is needed if the last line is a // comment.
    const char* lineEnd = [source hasSuffix:@"\n"] ? "" : "\n";
    return oo::NSStringFrom(oo::str::format("with(this){(function(){%s%s}).call(this)}", oo::DescriptionOf(source).c_str(), lineEnd));
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
        // ("%@" of a nil string printed "(null)")
        cxx_OOJSReportError(context, "can't convert %s to an integer", cxx_OOStringFromJSValueEvenIfNull(context, value).value_or("(null)").c_str());
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
        OO_LOG("bug.javaScript.limiterDepth", "{}", "Attempt to stop JavaScript time limiter while it is already fully stopped. This is an internal bug, please report it.");
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

    OO_LOG_ERR("script.javaScript.timeLimit", "Script \"{}\" ran for {} seconds and has been terminated.", oo::DescriptionOf([[OOJSScript currentlyRunningScript] name]), oo::str::format("%g", elapsed));
#ifdef OO_DEBUG_MONITOR_ENABLED
    OOJSDumpStack(gOOJSMainThreadContext);
#endif
    return 1;
}

//===========================================================================
// Error reporting
//===========================================================================

static std::string_view TrimWhitespace(std::string_view text)
{
    static constexpr std::string_view kWhitespace = " \t";
    const std::size_t first = text.find_first_not_of(kWhitespace);
    if (first == std::string_view::npos)
        return std::string_view();
    const std::size_t last = text.find_last_not_of(kWhitespace);
    return text.substr(first, last - first + 1);
}

/*	QuickJS records locations only in the stack property, as lines of the form
        "    at name (file:line:column)" or "    at file:line:column".
        Extract the file and line of the innermost frame with a location.
*/
static BOOL GetLocationFromStack(const std::optional<std::string>& stack, std::optional<std::string>* outFile, unsigned* outLine)
{
    if (!stack.has_value())
        return NO;

    std::string_view rest(*stack);
    while (!rest.empty()) {
        const std::size_t newline = rest.find('\n');
        std::string_view frame = TrimWhitespace(rest.substr(0, newline));
        rest = (newline == std::string_view::npos) ? std::string_view() : rest.substr(newline + 1);

        if (frame.substr(0, 3) != "at ")
            continue;
        frame.remove_prefix(3);

        // The first "(" opens the location: the path may itself contain parentheses ("Program Files (x86)").
        const std::size_t open = frame.find('(');
        if (open != std::string_view::npos && !frame.empty() && frame.back() == ')') {
            frame = frame.substr(open + 1, frame.size() - open - 2);
        }

        // file:line:column; the file may itself contain colons.
        const std::size_t lastColon = frame.rfind(':');
        if (lastColon == std::string_view::npos || lastColon == 0)
            continue;
        const std::size_t lineColon = frame.rfind(':', lastColon - 1);
        if (lineColon == std::string_view::npos)
            continue; // Native frame, e.g. "at log (native)".

        const std::string lineText(frame.substr(lineColon + 1, lastColon - lineColon - 1));
        *outFile = std::string(frame.substr(0, lineColon));
        *outLine = static_cast<unsigned>(atoi(lineText.c_str()));
        return YES;
    }
    return NO;
}

static std::optional<std::string> StackOfValue(JSContext* context, JSValueConst value)
{
    if (!JS_IsObject(value))
        return std::nullopt;
    JSValue stack = JS_GetPropertyStr(context, value, "stack");
    std::optional<std::string> result = cxx_OOStringFromJSValue(context, stack);
    JS_FreeValue(context, stack);
    return result;
}

static std::optional<std::string> CurrentStack(JSContext* context)
{
    // A fresh Error object captures the current JS stack.
    JSValue error = JS_NewError(context);
    std::optional<std::string> result = StackOfValue(context, error);
    JS_FreeValue(context, error);
    return result;
}

static void LogProblem(JSContext* context, const std::string& severity, const std::string& errorName, const std::string& message, const std::optional<std::string>& stack)
{
    const std::string messageClass = "script.javaScript." + severity + "." + errorName;
    const std::string highlight = (severity == "warning") ? "-----" : "*****";
    OOJavaScriptEngine* jsEng = [OOJavaScriptEngine sharedEngine];

    // Skip the rest if this is a warning being ignored. Errors and exceptions always go to the debug monitor.
    if (severity == "warning" && !oo::log::willDisplay(messageClass))
        return;

    // avoid windows DEP exceptions!
    OOJSScript* thisScript = [[OOJSScript currentlyRunningScript] weakRetain];
    const std::string activeScript = oo::OptionalString([[thisScript weakRefUnderlyingObject] displayName]).value_or("<unidentified script>");
    [thisScript release];
    OO_LOG(messageClass, "{} JavaScript {} ({}): {}", highlight, severity, activeScript, message);

    std::optional<std::string> file;
    unsigned line = 0;
    if ([jsEng showErrorLocations] && sErrorHandlerStackSkip == 0 && GetLocationFromStack(stack, &file, &line)) {
        OO_LOG(messageClass, "      {}, line {}.", *file, line);
    }

#ifdef OO_DEBUG_MONITOR_ENABLED
    BOOL dump = (severity == "warning") ? [jsEng dumpStackForWarnings] : [jsEng dumpStackForErrors];
    if (dump && stack.has_value())
        OO_LOG("script.javaScript.stackTrace", "{}", *stack);
#endif

#if OOJSENGINE_MONITOR_SUPPORT
    if (!file.has_value())
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

    std::string errorName = "exception";
    if (JS_IsError(exception)) {
        JSValue name = JS_GetPropertyStr(context, exception, "name");
        errorName = cxx_OOStringFromJSValue(context, name).value_or(errorName);
        JS_FreeValue(context, name);
    }

    // ("%@" of a nil message printed "(null)")
    std::optional<std::string> message = cxx_OOStringFromJSValueEvenIfNull(context, exception);
    if (!JS_IsError(exception)) {
        message = "uncaught exception: " + message.value_or("?");
    }

    LogProblem(context, "exception", errorName, message.value_or("(null)"), StackOfValue(context, exception));

    JS_FreeValue(context, exception);
    OOJSResumeTimeLimiter();
}

static std::string CallerPrefix(const std::optional<std::string>& scriptClass, const std::optional<std::string>& function)
{
    if (!function)
        return std::string();
    if (!scriptClass)
        return *function + ": ";
    return *scriptClass + "." + *function + ": ";
}

void cxx_OOJSReportError(JSContext* context, const char* format, ...)
{
    va_list args;

    va_start(args, format);
    cxx_OOJSReportErrorWithArguments(context, format, args);
    va_end(args);
}

void cxx_OOJSReportErrorForCaller(JSContext* context, const std::optional<std::string>& scriptClass, const std::optional<std::string>& function, const char* format, ...)
{
    va_list args;

    @try {
        va_start(args, format);
        std::string msg = oo::str::vformat(format, args);
        va_end(args);

        cxx_OOJSReportError(context, "%s%s", CallerPrefix(scriptClass, function).c_str(), msg.c_str());
    }
    @catch (id exception) {
        // Squash any secondary errors during error handling.
    }
}

void cxx_OOJSReportErrorWithArguments(JSContext* context, const char* format, va_list args)
{
    @try {
        std::string msg = oo::str::vformat(format, args);
        JS_ThrowPlainError(context, "%s", msg.c_str());
    }
    @catch (id exception) {
        // Squash any secondary errors during error handling.
    }
}

void OOJSReportWrappedException(JSContext* context, id exception)
{
    if (!JS_HasException(context)) {
        if ([exception isKindOfClass:[OOException class]])
            cxx_OOJSReportError(context, "Native exception: %s", [(OOException*)exception reason]);
        else if ([exception isKindOfClass:[OOFoundationException class]])
            cxx_OOJSReportError(context, "Native exception: %s", oo::DescriptionOf([(OOFoundationException*)exception reason]).c_str());
        else
            cxx_OOJSReportError(context, "Unidentified native exception");
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

void cxx_OOJSReportWarning(JSContext* context, const char* format, ...)
{
    va_list args;

    va_start(args, format);
    cxx_OOJSReportWarningWithArguments(context, format, args);
    va_end(args);
}

void cxx_OOJSReportWarningForCaller(JSContext* context, const std::optional<std::string>& scriptClass, const std::optional<std::string>& function, const char* format, ...)
{
    va_list args;

    @try {
        va_start(args, format);
        std::string msg = oo::str::vformat(format, args);
        va_end(args);

        cxx_OOJSReportWarning(context, "%s%s", CallerPrefix(scriptClass, function).c_str(), msg.c_str());
    }
    @catch (id exception) {
        // Squash any secondary errors during error handling.
    }
}

void cxx_OOJSReportWarningWithArguments(JSContext* context, const char* format, va_list args)
{
    @try {
        std::string msg = oo::str::vformat(format, args);
        OOJSPauseTimeLimiter();
        // SpiderMonkey reported Oolite's own warnings as error number 206, "ooliteDefined" in javascript-errors.plist.
        LogProblem(context, "warning", "ooliteDefined", msg, CurrentStack(context));
        OOJSResumeTimeLimiter();
    }
    @catch (id exception) {
        // Squash any secondary errors during error handling.
    }
}

std::string cxx_OOStringFromJSPropertyMagic(int magic, const JSCFunctionListEntry* list, size_t count)
{
    for (size_t i = 0; i < count; i++) {
        if (list[i].def_type == JS_DEF_CGETSET_MAGIC && list[i].magic == magic)
            return std::string(list[i].name);
    }
    return oo::str::format("%i", magic);
}

void OOJSReportBadPropertySelector(JSContext* context, JSValueConst thisObj, int magic, const JSCFunctionListEntry* list, size_t count)
{
    std::string propName = cxx_OOStringFromJSPropertyMagic(magic, list, count);
    NSString* className = OOJSClassNameOfValue(context, thisObj);

    cxx_OOJSReportError(context, "Invalid property identifier %s for instance of %s.", propName.c_str(), oo::DescriptionOf(className).c_str());
}

void OOJSReportBadPropertyValue(JSContext* context, JSValueConst thisObj, int magic, const JSCFunctionListEntry* list, size_t count, JSValueConst value)
{
    std::string propName = cxx_OOStringFromJSPropertyMagic(magic, list, count);
    NSString* className = OOJSClassNameOfValue(context, thisObj);
    std::string valueDesc = cxx_OOJSDescribeValue(context, value, YES);

    cxx_OOJSReportError(context, "Cannot set property %s of instance of %s to invalid value %s.", propName.c_str(), oo::DescriptionOf(className).c_str(), valueDesc.c_str());
}

void cxx_OOJSReportBadArguments(JSContext* context, const std::optional<std::string>& scriptClass, const std::optional<std::string>& function, int argc, JSValueConst* argv, const std::optional<std::string>& message, const std::optional<std::string>& expectedArgsDescription)
{
    @try {
        std::string text = message ? *message : std::string("Invalid arguments");
        std::optional<std::string> parameters = cxx_OOJSStringWithJavaScriptParameters(argv, argc, context);
        text += " " + (parameters ? *parameters : std::string("(null)"));
        if (expectedArgsDescription)
            text += " -- expected " + *expectedArgsDescription;

        cxx_OOJSReportErrorForCaller(context, scriptClass, function, "%s.", text.c_str());
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
    OO_LOG("script.javaScript.stackTrace", "{}", CurrentStack(context).value_or("<no JavaScript stack>"));
}
#endif

BOOL cxx_OOJSArgumentListGetNumber(JSContext* context, const std::optional<std::string>& scriptClass, const std::optional<std::string>& function, int argc, JSValueConst* argv, double* outNumber, int* outConsumed)
{
    if (OOJSArgumentListGetNumberNoError(context, argc, argv, outNumber, outConsumed)) {
        return YES;
    } else {
        cxx_OOJSReportBadArguments(context, scriptClass, function, argc, argv,
            std::string("Expected number, got"), std::nullopt);
        return NO;
    }
}

BOOL OOJSArgumentListGetNumberNoError(JSContext* context, int argc, JSValueConst* argv, double* outNumber, int* outConsumed)
{
    double value;

    OOCParameterAssert(context != NULL && (argv != NULL || argc == 0) && outNumber != NULL);

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
    OOCParameterAssert(name != NULL && name[0] != '\0');

    JSAtom atom = JS_NewAtom(OOJSAcquireContext(), name);
    if (EXPECT_NOT(atom == JS_ATOM_NULL)) {
        [OOException raise:OOGenericException format:"Failed to initialize JS ID cache for \"%s\".", name];
    }
    return atom;
}

JSAtom cxx_OOJSIDFromString(const std::string& string)
{
    // Atoms are interned for the life of the process; the cache keeps its one reference to each.
    static std::unordered_map<std::string, JSAtom>* sAtomCache = nullptr;

    if (sAtomCache != nullptr) {
        auto cached = sAtomCache->find(string);
        if (cached != sAtomCache->end())
            return cached->second;
    }

    JSAtom atom = JS_NewAtomLen(OOJSAcquireContext(), string.data(), string.size());
    if (EXPECT(atom != JS_ATOM_NULL)) {
        if (sAtomCache == nullptr)
            sAtomCache = new std::unordered_map<std::string, JSAtom>;
        sAtomCache->emplace(string, atom);
    }
    return atom;
}

std::optional<std::string> cxx_OOStringFromJSID(JSAtom propID)
{
    JSContext* context = OOJSAcquireContext();
    JSValue value = JS_AtomToString(context, propID);
    std::optional<std::string> result = cxx_OOStringFromJSValue(context, value);
    JS_FreeValue(context, value);
    return result;
}

//===========================================================================
// Native to JS conversion
//===========================================================================

// The root-class JS glue for classes rooted on OOObject (ADR-0029); the same methods on the
// Foundation root class live in OOJavaScriptEngine+FoundationBridge.mm until gnustep-base goes.
@implementation OOObject (OOJavaScriptConversion)

- (JSValue)oo_jsValueInContext:(JSContext*)context
{
    return JS_UNDEFINED;
}

- (id)oo_jsClassName
{
    return nil;
}

- (id)oo_jsDescription
{
    return [self oo_jsDescriptionWithClassName:[self oo_jsClassName]];
}

- (id)oo_jsDescriptionWithClassName:(id)className
{
    id components = [self descriptionComponents];
    if (className == nil)
        className = [[self class] description];

    // "%@" of each: oo::DescriptionOf prints the same text.
    if (components != nil) {
        return oo::NSStringFrom(oo::str::format("[%s %s]", oo::DescriptionOf(className).c_str(), oo::DescriptionOf(components).c_str()));
    } else {
        return oo::NSStringFrom(oo::str::format("[object %s]", oo::DescriptionOf(className).c_str()));
    }
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
            oo::NotificationCenter::defaultCenter().addObserver(self, kOOJavaScriptEngineWillResetNotificationName,
                [OOJavaScriptEngine sharedEngine],
                [self](const oo::Notification&) { [self deleteJSValue]; });
        }
    }
    return self;
}

- (void)deleteJSValue
{
    if (!JS_IsUndefined(_val)) {
        JS_FreeValue(OOJSAcquireContext(), _val);
        _val = JS_UNDEFINED;

        oo::NotificationCenter::defaultCenter().removeObserver(self, kOOJavaScriptEngineWillResetNotificationName,
            [OOJavaScriptEngine sharedEngine]);
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

std::optional<std::string> cxx_OOStringFromJSValueEvenIfNull(JSContext* context, JSValueConst value)
{
    size_t length;
    const char* chars = JS_ToCStringLen(context, &length, value); // Calls the value's toString method if needed.
    if (chars == NULL) {
        JS_FreeValue(context, JS_GetException(context));
        return std::nullopt;
    }

    std::string result(chars, length);
    JS_FreeCString(context, chars);
    return result;
}

std::optional<std::string> cxx_OOStringFromJSValue(JSContext* context, JSValueConst value)
{
    if (EXPECT(!JS_IsNull(value) && !JS_IsUndefined(value))) {
        return cxx_OOStringFromJSValueEvenIfNull(context, value);
    }
    return std::nullopt;
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

static std::string DescribeValue(JSContext* context, JSValueConst value, BOOL abbreviateObjects, BOOL recursing)
{
    if (JS_IsFunction(context, value)) {
        JSValue nameVal = JS_GetPropertyStr(context, value, "name");
        std::optional<std::string> name = cxx_OOStringFromJSValue(context, nameVal);
        JS_FreeValue(context, nameVal);
        if (name.has_value() && !name->empty())
            return "function " + *name;
        else
            return "function";
    }

    std::optional<std::string> result;
    JSClassID classID = JS_GetClassID(value);

    if (JS_IsString(value) || (classID != JS_INVALID_CLASS_ID && classID == gOOJSStringClassID)) {
        enum { kMaxLength = 200 };

        // Truncated to kMaxLength UTF-16 units, as the NSString was cut.
        const std::u16string units = oo::utf8ToUtf16(cxx_OOStringFromJSValueEvenIfNull(context, value).value_or(""));
        const std::string truncated = oo::utf16ToUtf8(std::u16string_view(units.data(), MIN(units.size(), (size_t)kMaxLength)));
        result = "\"" + cxx_OOJSEscapedForJavaScriptLiteral(truncated) + ((units.size() > kMaxLength) ? "..." : "") + "\"";
    } else if (JS_IsArray(value)) {
        // Descibe up to four elements of an array.
        int64_t count;
        if (JS_GetLength(context, value, &count) == 0) {
            if (!recursing) {
                std::string arrayDesc = "[";
                int64_t i, effectiveCount = MIN(count, (int64_t)4);
                for (i = 0; i < effectiveCount; i++) {
                    JSValue item = JS_GetPropertyUint32(context, value, (uint32_t)i);
                    std::string itemDesc = "?";
                    if (!JS_IsException(item)) {
                        itemDesc = DescribeValue(context, item, YES /* always abbreviate objects in arrays */, YES);
                    }
                    JS_FreeValue(context, item);
                    if (i != 0)
                        arrayDesc += ", ";
                    arrayDesc += itemDesc;
                }
                if (effectiveCount != count) {
                    arrayDesc += oo::str::format(", ... <%lli items total>]", (long long)count);
                } else {
                    arrayDesc += "]";
                }

                result = arrayDesc;
            } else {
                result = oo::str::format("[<%lli items>]", (long long)count);
            }
        } else {
            JS_FreeValue(context, JS_GetException(context));
            result = "[...]";
        }
    }

    if (!result) {
        result = cxx_OOStringFromJSValueEvenIfNull(context, value);

        if (abbreviateObjects && classID == gOOJSObjectClassID && result && *result == "[object Object]") {
            result = "{...}";
        }

        if (!result)
            result = "?";
    }

    return *result;
}

std::string cxx_OOJSDescribeValue(JSContext* context, JSValueConst value, BOOL abbreviateObjects)
{
    return DescribeValue(context, value, abbreviateObjects, NO);
}

std::optional<std::string> cxx_OOJSStringWithJavaScriptParameters(JSValueConst* params, int count, JSContext* context)
{
    if (params == NULL && count != 0)
        return std::nullopt;

    int i;
    std::string result = "(";

    for (i = 0; i < count; ++i) {
        if (i != 0)
            result += ", ";
        result += cxx_OOJSDescribeValue(context, params[i], NO);
    }

    result += ")";
    return result;
}

std::optional<std::string> cxx_OOJSConcatenationOfStringsFromJavaScriptValues(JSValueConst* values, size_t count, const std::string& separator, JSContext* context)
{
    size_t i;
    std::optional<std::string> result;

    if (count < 1)
        return std::nullopt;
    if (values == NULL)
        return std::nullopt;

    for (i = 0; i != count; ++i) {
        std::optional<std::string> element = cxx_OOStringFromJSValueEvenIfNull(context, values[i]);
        if (!result)
            result = element; // a nil element left the result nil, as -mutableCopy of nil did
        else {
            *result += separator;
            if (element)
                *result += *element;
        }
    }

    return result;
}

std::string cxx_OOJSEscapedForJavaScriptLiteral(std::string_view string)
{
    // Byte-wise over UTF-8: every escaped character is ASCII, so multi-byte sequences pass through
    // unchanged, as the UTF-16 units they encode did.
    std::string result;
    result.reserve(string.size());

    for (char c : string) {
        switch (c) {
        case '\\':
            result += "\\\\";
            break;

        case '\b':
            result += "\\b";
            break;

        case '\f':
            result += "\\f";
            break;

        case '\n':
            result += "\\n";
            break;

        case '\r':
            result += "\\r";
            break;

        case '\t':
            result += "\\t";
            break;

        case '\v':
            result += "\\v";
            break;

        case '\'':
            result += "\\\'";
            break;

        case '\"':
            result += "\\\"";
            break;

        default:
            result += c;
        }
    }
    return result;
}

@implementation OONativeVector (OOJavaScriptConversion)

- (JSValue)oo_jsValueInContext:(JSContext*)context
{
    JSValue value = JS_UNDEFINED;
    VectorToJSValue(context, [self getVector], &value);
    return value;
}

@end

@implementation OONull

+ (OONull*)null
{
    static OONull* sNull = nil;
    if (sNull == nil)
        sNull = [[OONull alloc] init];
    return sNull;
}

- (id)copyWithZone:(OOZone*)zone
{
    return [self retain];
}

- (id)description // shared selector (proposed ADR-0043)
{
    return oo::NSStringFrom("<null>");
}

- (JSValue)oo_jsValueInContext:(JSContext*)context
{
    return JS_NULL;
}

@end

//===========================================================================
// Reusable callbacks
//===========================================================================

JSValue OOJSUnconstructableConstruct(JSContext* context, JSValueConst thisObj, int argc, JSValueConst* argv)
{
    // For constructors, this is new.target, i.e. the constructor function itself.
    JSValue nameVal = JS_GetPropertyStr(context, thisObj, "name");
    std::optional<std::string> name = cxx_OOStringFromJSValue(context, nameVal);
    JS_FreeValue(context, nameVal);

    // %@ of a nil name printed "(null)".
    cxx_OOJSReportError(context, "%s cannot be used as a constructor.", name ? name->c_str() : "(null)");
    return JS_EXCEPTION;
}

void OOJSObjectWrapperFinalize(JSRuntime* runtime, JSValueConst thisObj)
{
    JSClassID classID;
    id object = (id)JS_GetAnyOpaque(thisObj, &classID);
    if (object != nil) {
        [[object weakRefUnderlyingObject] oo_clearJSSelf:thisObj];
        [object release];
        JS_SetOpaque(thisObj, NULL);
    }
}

JSValue OOJSObjectWrapperToString(JSContext* context, JSValueConst thisObj, int argc, JSValueConst* argv)
{
    OOJS_NATIVE_ENTER(context)

    id object = nil;
    id description = nil; // the object's own -oo_jsDescription / -description

    object = OOJSNativeObjectFromJSObject(context, thisObj);
    if (object != nil) {
        description = [object oo_jsDescription];
        if (description == nil)
            description = [object description];
    }
    if (description == nil) {
        const char* className = OOJSClassName(JS_GetClassID(thisObj));
        if (className != NULL) {
            description = oo::NSStringFrom(oo::str::format("[object %s]", className));
        }
    }
    if (description == nil)
        description = oo::NSStringFrom("[object]");

    OOJS_RETURN_OBJECT(description);

    OOJS_NATIVE_EXIT
}

//===========================================================================
// Entity predicates
//===========================================================================

BOOL JSFunctionPredicate(Entity* entity, void* parameter)
{
    JSFunctionPredicateParameter* param = (JSFunctionPredicateParameter*)parameter;
    BOOL result = NO;

    OOCParameterAssert(entity != nil && param != NULL);
    OOCParameterAssert(param->context != NULL);
    OOCParameterAssert(OOJSValueIsFunction(param->context, param->function));

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
    OOCParameterAssert(requiredObjCClass != Nil);
    OOCParameterAssert(context != NULL && requiredClassID != 0 && outObject != NULL);

    /*
            Ensure it's a valid type of JS object. This is absolutely necessary,
            because if we don't check it we'll crash trying to get the private
            field of something that isn't an ObjC object wrapper - for example,
            Ship.setAI.call(new Vector3D, "") is valid JavaScript.
    */
    JSClassID actualClassID = JS_GetClassID(object);
    if (EXPECT_NOT(!OOJSIsSubclass(actualClassID, requiredClassID))) {
        std::optional<std::string> got = cxx_OOStringFromJSValue(context, object);
        cxx_OOJSReportError(context, "Native method expected %s, got %s.", OOJSClassName(requiredClassID), got ? got->c_str() : "(null)");
        return NO;
    }

    // Get the underlying object.
    JSClassID ignored;
    *outObject = [(id)JS_GetAnyOpaque(object, &ignored) weakRefUnderlyingObject];

#ifndef NDEBUG
    // Double-check that the underlying object is of the expected ObjC class.
    if (EXPECT_NOT(*outObject != nil && ![*outObject isKindOfClass:requiredObjCClass])) {
        cxx_OOJSReportError(context, "Native method expected %s from %s and got correct JS type but incorrect native object %s", oo::DescriptionOf(requiredObjCClass).c_str(), OOJSClassName(requiredClassID), oo::DescriptionOf(*outObject).c_str());
        return NO;
    }
#endif

    return YES;
}

//===========================================================================
// JS to native conversion
//===========================================================================

oo::PList OOJSDictionaryFromJSValue(JSContext* context, JSValueConst value)
{
    if (EXPECT_NOT(!JS_IsObject(value))) {
        return oo::PList();
    }
    return cxx_OOJSDictionaryFromJSObject(context, value);
}

/*	An integer-like property name, which SpiderMonkey had as an int jsid: the test of the
        Foundation form's KeyForAtom() (OOJavaScriptEngine+FoundationBridge.mm), which makes such a
        key an NSNumber.
*/
static bool IsIntegerLikeKey(const std::string& key)
{
    const std::size_t length = oo::utf8ToUtf16(key).size(); // [key length]: UTF-16 units
    if (length != 0 && length < 10) {
        const char first = key[0];
        if ((first >= '1' && first <= '9') || key == "0") {
            oo::str::Scanner scanner(key);
            int intValue;
            if (scanner.scanInt(&intValue) && scanner.isAtEnd()) {
                return true;
            }
        }
    }
    return false;
}

oo::PList cxx_OOJSDictionaryFromJSObject(JSContext* context, JSValueConst object)
{
    JSPropertyEnum* properties = NULL;
    uint32_t i, count;
    oo::PList::Dict result;
    bool hasIntegerKey = false;

    if (JS_GetOwnPropertyNames(context, &properties, &count, object, JS_GPN_STRING_MASK | JS_GPN_ENUM_ONLY) < 0) {
        JS_FreeValue(context, JS_GetException(context));
        return oo::PList();
    }

    for (i = 0; i != count; ++i) {
        const std::optional<std::string> key = cxx_OOStringFromJSID(properties[i].atom);
        /*	The Foundation form (OOJSDictionaryFromJSObject, in the bridge) keeps
                an int32 property id as a number key; oo::PListFrom() made a dictionary
                with a number key a null PList, so such an entry makes the whole result
                null here. (CIM 15/2/13 asked whether the key should be a string.)
        */
        const bool isIntegerKey = key.has_value() && IsIntegerLikeKey(*key);
        JSValue value = JS_GetProperty(context, object, properties[i].atom);
        if (JS_IsException(value)) {
            JS_FreeValue(context, JS_GetException(context));
            continue;
        }

        if (key.has_value() && !JS_IsUndefined(value)) {
            id objValue = OOJSNativeObjectFromJSValue(context, value);
            if (objValue != nil) {
                if (isIntegerKey)
                    hasIntegerKey = true;
                else
                    result.insert_or_assign(*key, oo::PListFrom(objValue));
            }
        }
        JS_FreeValue(context, value);
    }

    JS_FreePropertyEnum(context, properties, count);
    if (hasIntegerKey)
        return oo::PList();
    return oo::PList(std::move(result));
}

oo::PList OOJSDictionaryFromStringTable(JSContext* context, JSValueConst tableValue)
{
    JSPropertyEnum* properties = NULL;
    uint32_t i, count;
    oo::PList::Dict result;

    if (EXPECT_NOT(JS_IsNull(tableValue) || JS_IsUndefined(tableValue))) {
        return oo::PList();
    }

    JSValue tableObject = JS_ToObject(context, tableValue);
    if (JS_IsException(tableObject)) {
        JS_FreeValue(context, JS_GetException(context));
        return oo::PList();
    }

    if (JS_GetOwnPropertyNames(context, &properties, &count, tableObject, JS_GPN_STRING_MASK | JS_GPN_ENUM_ONLY) < 0) {
        JS_FreeValue(context, JS_GetException(context));
        JS_FreeValue(context, tableObject);
        return oo::PList();
    }

    for (i = 0; i != count; ++i) {
        const std::optional<std::string> key = cxx_OOStringFromJSID(properties[i].atom);
        JSValue value = JS_GetProperty(context, tableObject, properties[i].atom);
        if (JS_IsException(value)) {
            JS_FreeValue(context, JS_GetException(context));
            continue;
        }

        if (key.has_value() && !JS_IsUndefined(value)) {
            std::optional<std::string> string = cxx_OOStringFromJSValueEvenIfNull(context, value);
            if (string.has_value()) {
                result.insert_or_assign(*key, oo::PList(std::move(*string)));
            }
        }
        JS_FreeValue(context, value);
    }

    JS_FreePropertyEnum(context, properties, count);
    JS_FreeValue(context, tableObject);
    return oo::PList(std::move(result));
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
        // +numberWithLongLong: where this was +numberWithInt: (same value; bead oo-3rb.202).
        return oo::ObjectFromPList(oo::PList::signedInteger(intValue));
    }
    if (JS_IsNumber(value)) {
        JS_ToFloat64(context, &doubleValue, value);
        return oo::ObjectFromPList(oo::PList(doubleValue));
    }
    if (JS_IsBool(value)) {
        return oo::ObjectFromPList(oo::PList(static_cast<bool>(JS_VALUE_GET_BOOL(value))));
    }
    if (JS_IsString(value)) {
        return oo::NSStringOrNil(cxx_OOStringFromJSValue(context, value));
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
    id result = (id)JS_GetAnyOpaque(object, &ignored);
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
    std::vector<id> values;

    // Convert a JS array to a native array by calling OOJSNativeObjectFromJSValue() on all its elements.
    if (!JS_IsArray(array))
        return nil;
    if (JS_GetLength(context, array, &count) < 0) {
        JS_FreeValue(context, JS_GetException(context));
        return nil;
    }

    values.reserve(static_cast<std::size_t>(count));
    for (i = 0; i != count; ++i) {
        JSValue value = JS_GetPropertyUint32(context, array, (uint32_t)i);
        if (JS_IsException(value)) {
            JS_FreeValue(context, JS_GetException(context));
            value = JS_UNDEFINED;
        }

        id object = OOJSNativeObjectFromJSValue(context, value);
        JS_FreeValue(context, value);
        if (object == nil)
            object = [OONull null];
        values.push_back(object);
    }

    return oo::NSArrayFromObjects(values);
}

static id JSStringConverter(JSContext* context, JSValueConst object)
{
    return oo::NSStringOrNil(cxx_OOStringFromJSValue(context, object));
}

static id JSNumberConverter(JSContext* context, JSValueConst object)
{
    double value;
    if (JS_ToFloat64(context, &value, object) == 0) {
        return oo::ObjectFromPList(oo::PList(value));
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
        return oo::ObjectFromPList(oo::PList(value != 0));
    }
    JS_FreeValue(context, JS_GetException(context));
    return nil;
}

static id JSObjectConverter(JSContext* context, JSValueConst object)
{
    /*	SpiderMonkey's global object had a class of its own, with no converter,
            so it converted to nil. QuickJS's is a plain object, and converting it
            as one recurses until the stack overflows, since its global property
            refers to itself; a Timer whose this is the global object did that on firing.
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
