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

#include "OOJavaScriptEngine.h"
#include "OOFoundation.h" // OOLITE_DEBUG
#include "OOJSEngineTimeManagement.h"
#include "OOJSScript.h"

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

#include "EntityOOJavaScriptExtensions.h"
#include "OOConstToJSString.h"
#include "OOJSPrivateObject.h"
#include "OOObjCPList.h" // Object nodes (OOJSValueFromPList)
#include "OOPlanetEntity.h"
#include "OOVisualEffectEntity.h"
#include "OOWaypointEntity.h"
#include "ResourceManager.h"
#include "Universe.h"

#include "OOJSClock.h"
#include "OOJSDock.h"
#include "OOJSEntity.h"
#include "OOJSEquipmentInfo.h"
#include "OOJSExhaustPlume.h"
#include "OOJSFlasher.h"
#include "OOJSFont.h"
#include "OOJSFrameCallbacks.h"
#include "OOJSGlobal.h"
#include "OOJSManifest.h"
#include "OOJSMission.h"
#include "OOJSMissionVariables.h"
#include "OOJSOolite.h"
#include "OOJSPlanet.h"
#include "OOJSPlayer.h"
#include "OOJSPlayerShip.h"
#include "OOJSQuaternion.h"
#include "OOJSShip.h"
#include "OOJSShipGroup.h"
#include "OOJSSound.h"
#include "OOJSSoundSource.h"
#include "OOJSSpecialFunctions.h"
#include "OOJSStation.h"
#include "OOJSSun.h"
#include "OOJSSystem.h"
#include "OOJSSystemInfo.h"
#include "OOJSTimer.h"
#include "OOJSVector.h"
#include "OOJSVisualEffect.h"
#include "OOJSWaypoint.h"
#include "OOJSWorldScripts.h"
#include "OOJSWormhole.h"

#include "oofnd/objc/OOException.h"

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

static OOJavaScriptEngine* sSharedEngine = nullptr; // the one +1 is never released (amendment oo-r7m0 item 1)

static unsigned sErrorHandlerStackSkip = 0;

JSContext* gOOJSMainThreadContext = NULL;

static JSValue sLegacyConstRewriter = JS_UNDEFINED;

const char* const kOOJavaScriptEngineWillResetNotificationName = "org.aegidian.oolite OOJavaScriptEngine will reset";
const char* const kOOJavaScriptEngineDidResetNotificationName = "org.aegidian.oolite OOJavaScriptEngine did reset";

static int InterruptHandler(JSRuntime* runtime, void* opaque);
static void RegisterStandardObjectConverters(JSContext* context);
static void RemoveNonSpiderMonkeyGlobals(JSContext* context, JSValueConst global);
static void LoadCompatibilityScript(JSContext* context);

//===========================================================================
// JavaScript engine initialisation and shutdown
//===========================================================================

OOJavaScriptEngine* OOJavaScriptEngine::sharedEngine()
{
    if (sSharedEngine == nullptr) {
        // The one +1, never released (amendment oo-r7m0 item 1). Recorded before init() runs, as
        // -init recorded self before it made the context, so a re-entrant sharedEngine() answers
        // the engine being set up (amendment oo-3bgz item 3).
        OOJavaScriptEngine* engine = oo::makeRef<OOJavaScriptEngine>().leakRef();
        sSharedEngine = engine;
        engine->init();
    }

    return sSharedEngine;
}

void OOJavaScriptEngine::runMissionCallback()
{
    MissionRunCallback();
}

void OOJavaScriptEngine::init()
{
    // -init asserted that no engine existed yet; sharedEngine() makes only this one.
    OOCAssert(sSharedEngine == this, "Attempt to create multiple OOJavaScriptEngines.");

    _showErrorLocations = true;

    oo::Defaults& defaults = oo::Defaults::standard();
#ifdef OO_DEBUG_MONITOR_ENABLED
    /*	Set stack trace preferences from preferences. These will be overriden
            by the debug OXP script if installed, but being able to enable traces
            without setting up the debug console could be useful for debugging
            users' problems.
    */
    setDumpStackForErrors(defaults.boolForKey("dump-stack-for-errors"));
    setDumpStackForWarnings(defaults.boolForKey("dump-stack-for-warnings"));
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

    createMainThreadContext();
}

void OOJavaScriptEngine::createMainThreadContext()
{
    OOCAssert(gOOJSMainThreadContext == NULL, "-[OOJavaScriptEngine createMainThreadContext] called while the main thread context exists.");

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
    oo::Ref<OOJSValue> specialWrapper = OOJSValue::valueWithJSValue(special, _context);
    JS_FreeValue(_context, special);
    OOScriptAutorelease(OOScript::jsScriptFromFileNamed("oolite-global-prefix.js", // (nothing keeps it)
        oo::PList(oo::PList::Dict { { "special", OOJSValueObjectNode(specialWrapper.get()) } })));

    OO_LOG("script.javaScript.init.success", "{}", "Set up JavaScript context.");
}

void OOJavaScriptEngine::destroyMainThreadContext()
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

bool OOJavaScriptEngine::reset()
{
    OOCAssert(gOOJSMainThreadContext != NULL, "JavaScript engine not active. Can't reset.");

    OOJSFrameCallbacksRemoveAll();

    oo::NotificationCenter::defaultCenter().post(kOOJavaScriptEngineWillResetNotificationName, this); // the engine: what observers filter on

    destroyMainThreadContext();
    createMainThreadContext();

    oo::NotificationCenter::defaultCenter().post(kOOJavaScriptEngineDidResetNotificationName, this);

    garbageCollectionOpportunity(true);
    OO_LOG("script.javascript.init", "{}", "JavaScript reset successful.");
    return true;
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

NSUInteger OOJavaScriptEngine::shutDown()
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
    oo::NotificationCenter::defaultCenter().post(kOOJavaScriptEngineWillResetNotificationName, this); // the engine: what observers filter on
    destroyMainThreadContext();

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

OOJavaScriptEngine::~OOJavaScriptEngine()
{
    shutDown();
    if (sSharedEngine == this)
        sSharedEngine = nullptr;
}

JSContext* OOJavaScriptEngine::context()
{
    return _context;
}

JSValueConst OOJavaScriptEngine::globalObject()
{
    return _globalObject;
}

bool OOJavaScriptEngine::callJSFunction(JSValueConst function, JSValueConst jsThis, int argc, JSValueConst* argv, JSValue* outResult)
{
    OOCParameterAssert(JS_IsFunction(_context, function));

    OOJSStartTimeLimiter();
    JSValue result = JS_Call(_context, function, jsThis, argc, argv);
    OOJSStopTimeLimiter();

    if (JS_IsException(result)) {
        OOJSReportPendingException(_context);
        if (outResult != NULL)
            *outResult = JS_UNDEFINED;
        return false;
    }

    if (outResult != NULL)
        *outResult = result;
    else
        JS_FreeValue(_context, result);
    return true;
}

void OOJavaScriptEngine::garbageCollectionOpportunity(bool force)
{
    /*	Reference counting frees most objects immediately, and QuickJS runs its
            cycle collector by allocation threshold, so only forced collections
            need doing here.
    */
    if (force)
        JS_RunGC(_runtime);
}

bool OOJavaScriptEngine::showErrorLocations()
{
    return _showErrorLocations;
}

void OOJavaScriptEngine::setShowErrorLocations(bool value)
{
    _showErrorLocations = !!value;
}

#ifdef OO_DEBUG_MONITOR_ENABLED
bool OOJavaScriptEngine::dumpStackForErrors()
{
    return _dumpStackForErrors;
}

void OOJavaScriptEngine::setDumpStackForErrors(bool value)
{
    _dumpStackForErrors = !!value;
}

bool OOJavaScriptEngine::dumpStackForWarnings()
{
    return _dumpStackForWarnings;
}

void OOJavaScriptEngine::setDumpStackForWarnings(bool value)
{
    _dumpStackForWarnings = !!value;
}

void OOJavaScriptEngine::enableDebuggerStatement()
{
    // QuickJS treats the debugger statement as a no-op and has no hook for it.
}
#endif

#if OOJSENGINE_MONITOR_SUPPORT

void OOJavaScriptEngine::setMonitor(OOJavaScriptEngineMonitor* inMonitor)
{
    _monitor = inMonitor;
}

void OOJavaScriptEngine::sendMonitorProblem(const std::string& severity, const std::optional<std::string>& file, unsigned line, const std::string& message, JSContext* theContext)
{
    if (_monitor != nullptr) {
        _monitor->jsEngine(this, theContext, severity, file, line, sErrorHandlerStackSkip, showErrorLocations(), message);
    }
}

void OOJavaScriptEngine::sendMonitorLogMessage(const std::optional<std::string>& message, const std::optional<std::string>& messageClass, JSContext* theContext)
{
    if (_monitor != nullptr) {
        _monitor->jsEngine(this, theContext, message.value_or(""), messageClass);
    }
}

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
        bool keep = (name == NULL);
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
    const std::optional<std::string> path = ResourceManager::pathForFileNamed("oolite-quickjs-compat.js", std::string("Scripts"));
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

std::string OOJSWrapScriptSource(const std::string& source)
{
    // A newline before the closing part is needed if the last line is a // comment.
    const char* lineEnd = oo::str::hasSuffix(source, "\n") ? "" : "\n";
    return "with(this){(function(){" + source + lineEnd + "}).call(this)}";
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

    OOJSScript* runningScript = OOJSScript::currentlyRunningScript();
    OO_LOG_ERR("script.javaScript.timeLimit", "Script \"{}\" ran for {} seconds and has been terminated.", ((runningScript != nullptr) ? runningScript->name() : std::nullopt).value_or("(null)"), oo::str::format("%g", elapsed));
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
    OOJavaScriptEngine* jsEng = OOJavaScriptEngine::sharedEngine();

    // Skip the rest if this is a warning being ignored. Errors and exceptions always go to the debug monitor.
    if (severity == "warning" && !oo::log::willDisplay(messageClass))
        return;

    // avoid windows DEP exceptions!
    // The running script (null when none runs, or once a script a timer or definition pushed
    // weakly has gone: a message to nil).
    OOJSScript* runningScript = OOJSScript::currentlyRunningScript();
    const std::string activeScript = ((runningScript != nullptr) ? runningScript->displayName() : std::nullopt).value_or("<unidentified script>");
    OO_LOG(messageClass, "{} JavaScript {} ({}): {}", highlight, severity, activeScript, message);

    std::optional<std::string> file;
    unsigned line = 0;
    if (jsEng->showErrorLocations() && sErrorHandlerStackSkip == 0 && GetLocationFromStack(stack, &file, &line)) {
        OO_LOG(messageClass, "      {}, line {}.", *file, line);
    }

#ifdef OO_DEBUG_MONITOR_ENABLED
    bool dump = (severity == "warning") ? jsEng->dumpStackForWarnings() : jsEng->dumpStackForErrors();
    if (dump && stack.has_value())
        OO_LOG("script.javaScript.stackTrace", "{}", *stack);
#endif

#if OOJSENGINE_MONITOR_SUPPORT
    if (!file.has_value())
        GetLocationFromStack(stack, &file, &line);
    jsEng->sendMonitorProblem(severity, file, line, message, context);
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

    try {
        va_start(args, format);
        std::string msg = oo::str::vformat(format, args);
        va_end(args);

        cxx_OOJSReportError(context, "%s%s", CallerPrefix(scriptClass, function).c_str(), msg.c_str());
    } catch (...) {
        // Squash any secondary errors during error handling: nothing more to do.
        return;
    }
}

void cxx_OOJSReportErrorWithArguments(JSContext* context, const char* format, va_list args)
{
    try {
        std::string msg = oo::str::vformat(format, args);
        JS_ThrowPlainError(context, "%s", msg.c_str());
    } catch (...) {
        // Squash any secondary errors during error handling: nothing more to do.
        return;
    }
}

// OOJSReportCurrentException() is in OOJSEngineNativeWrappers.mm (OOJSReportWrappedException() went with the
// Objective-C exceptions, when the exception became the C++ oo::Exception).

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

    try {
        va_start(args, format);
        std::string msg = oo::str::vformat(format, args);
        va_end(args);

        cxx_OOJSReportWarning(context, "%s%s", CallerPrefix(scriptClass, function).c_str(), msg.c_str());
    } catch (...) {
        // Squash any secondary errors during error handling: nothing more to do.
        return;
    }
}

void cxx_OOJSReportWarningWithArguments(JSContext* context, const char* format, va_list args)
{
    try {
        std::string msg = oo::str::vformat(format, args);
        OOJSPauseTimeLimiter();
        // SpiderMonkey reported Oolite's own warnings as error number 206, "ooliteDefined" in javascript-errors.plist.
        LogProblem(context, "warning", "ooliteDefined", msg, CurrentStack(context));
        OOJSResumeTimeLimiter();
    } catch (...) {
        // Squash any secondary errors during error handling: nothing more to do.
        return;
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
    std::string className = OOJSClassNameOfValue(context, thisObj);

    cxx_OOJSReportError(context, "Invalid property identifier %s for instance of %s.", propName.c_str(), className.c_str());
}

void OOJSReportBadPropertyValue(JSContext* context, JSValueConst thisObj, int magic, const JSCFunctionListEntry* list, size_t count, JSValueConst value)
{
    std::string propName = cxx_OOStringFromJSPropertyMagic(magic, list, count);
    std::string className = OOJSClassNameOfValue(context, thisObj);
    std::string valueDesc = cxx_OOJSDescribeValue(context, value, YES);

    cxx_OOJSReportError(context, "Cannot set property %s of instance of %s to invalid value %s.", propName.c_str(), className.c_str(), valueDesc.c_str());
}

void cxx_OOJSReportBadArguments(JSContext* context, const std::optional<std::string>& scriptClass, const std::optional<std::string>& function, int argc, JSValueConst* argv, const std::optional<std::string>& message, const std::optional<std::string>& expectedArgsDescription)
{
    try {
        std::string text = message ? *message : std::string("Invalid arguments");
        std::optional<std::string> parameters = cxx_OOJSStringWithJavaScriptParameters(argv, argc, context);
        text += " " + (parameters ? *parameters : std::string("(null)"));
        if (expectedArgsDescription)
            text += " -- expected " + *expectedArgsDescription;

        cxx_OOJSReportErrorForCaller(context, scriptClass, function, "%s.", text.c_str());
    } catch (...) {
        // Squash any secondary errors during error handling: nothing more to do.
        return;
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
        OORaiseException(OOGenericException, "Failed to initialize JS ID cache for \"%s\".", name);
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

// (The root-class JS glue for classes rooted on OOObject - OOObjectJSValueInContext(),
// OOObjectJSClassName(), OOObjectJSDescription(), OOObjectJSDescriptionWithClassName() - went with
// the root's JS bridges: no game object is an Objective-C object.)

namespace {
// The Foundation array's glue (JSArrayFromNSArray) over ObjectFromPList's array: null elements dropped.
// Owned; undefined on failure.
static JSValue JSArrayValueFromPList(JSContext* context, const oo::PList::Array& array)
{
    JSValue result = JS_NewArray(context);
    if (JS_IsException(result)) {
        JS_FreeValue(context, JS_GetException(context));
        return JS_UNDEFINED;
    }

    uint32_t i = 0;
    for (const oo::PList& element : array) {
        if (element.isNull())
            continue;
        // JS_SetPropertyUint32() takes ownership of the value.
        JSValue elementValue = OOJSValueFromPList(context, element);
        if (EXPECT_NOT(JS_SetPropertyUint32(context, result, i, elementValue) < 0)) {
            JS_FreeValue(context, JS_GetException(context));
            JS_FreeValue(context, result);
            return JS_UNDEFINED;
        }
        ++i;
    }

    return result;
}

// The Foundation dictionary's glue (JSObjectFromNSDictionary) over ObjectFromPList's dictionary: null and
// undefined values dropped, empty keys skipped, key order. Owned; undefined on failure.
static JSValue JSObjectValueFromPList(JSContext* context, const oo::PList::Dict& dict)
{
    JSValue result = JS_NewObject(context);
    if (JS_IsException(result)) {
        JS_FreeValue(context, JS_GetException(context));
        return JS_UNDEFINED;
    }

    for (const auto& [key, element] : dict) {
        if (element.isNull() || key.empty())
            continue;
        JSValue elementValue = OOJSValueFromPList(context, element);
        if (JS_IsUndefined(elementValue))
            continue;
        // JS_SetProperty() takes ownership of the value.
        if (EXPECT_NOT(JS_SetProperty(context, result, cxx_OOJSIDFromString(key), elementValue) < 0)) {
            JS_FreeValue(context, JS_GetException(context));
            JS_FreeValue(context, result);
            return JS_UNDEFINED;
        }
    }

    return result;
}
} // namespace

// (OOJSValueFromNativeObject(), the JS value of an Objective-C object - null for nil, the root's JS
// glue - went with the Objective-C runtime: no game object is an Objective-C object.)

JSValue OOJSValueFromPList(JSContext* context, const oo::PList& plist)
{
    switch (plist.type()) {
    case oo::PList::Type::Null:
        return JS_NULL;

    case oo::PList::Type::Bool:
        // +numberWithBool: is not a float type: an int32.
        return JS_NewInt32(context, *plist.getIf<bool>() ? 1 : 0);

    case oo::PList::Type::Integer: {
        // The Foundation number's glue: JS_NewNumber() of the integer, an int32 when it is in range.
        const oo::PList::Integer& integer = *plist.getIf<oo::PList::Integer>();
        if (integer.isUnsigned) {
            const unsigned long long u = integer.unsignedValue();
            if (u <= static_cast<unsigned long long>(INT32_MAX))
                return JS_NewInt32(context, static_cast<int32_t>(u));
            return JS_NewNumber(context, static_cast<double>(u));
        }
        const long long v = integer.value;
        if (static_cast<long long>(INT32_MIN) <= v && v <= static_cast<long long>(INT32_MAX))
            return JS_NewInt32(context, static_cast<int32_t>(v));
        return JS_NewNumber(context, static_cast<double>(v));
    }

    case oo::PList::Type::Real: {
        // The Foundation number's glue: a float type is always a double.
        double d = *plist.getIf<double>();
        if (plist.isSinglePrecision())
            d = static_cast<double>(static_cast<float>(d)); // +numberWithFloat: -doubleValue
        return JS_NewFloat64(context, d);
    }

    case oo::PList::Type::String: {
        const std::string& string = *plist.getIf<std::string>();
        return JS_NewStringLen(context, string.data(), string.size());
    }

    case oo::PList::Type::Data:
    case oo::PList::Type::Date:
        return JS_UNDEFINED; // Foundation data and dates: the root class's glue

    case oo::PList::Type::Array:
        return JSArrayValueFromPList(context, *plist.getIf<oo::PList::Array>());

    case oo::PList::Type::Dict:
        return JSObjectValueFromPList(context, *plist.getIf<oo::PList::Dict>());

    case oo::PList::Type::Object: {
        // A C++ object that is its own JS glue (OOJSPrivateObject.h), else an Objective-C object.
        if (const oo::PList::Object* node = plist.getIf<oo::PList::Object>()) {
            if (OOJSPrivateObject* glue = dynamic_cast<OOJSPrivateObject*>(node->get()))
                return OOJSValueFromCxxObject(context, glue);
            if (OONativeVector* box = dynamic_cast<OONativeVector*>(node->get()))
                return OONativeVectorJSValueInContext(box, context);
            // An entity's node: the entity's JS value, which its object's forwarded to.
            if (const auto* held = dynamic_cast<const oo::EntityPListForeign*>(node->get()))
                return OOJSEntityJSValue(held->entity(), context);
            // An entity held weakly: the entity's value, undefined once it has gone, as the weak
            // reference forwarded to its object's.
            if (const auto* weak = dynamic_cast<const oo::EntityWeakPListForeign*>(node->get())) {
                Entity* entity = weak->entity();
                return entity != nullptr ? OOJSEntityJSValue(entity, context) : JS_UNDEFINED;
            }
            // The one null and a held value: their own JS glue, which their facades forwarded to.
            if (OONull* null = dynamic_cast<OONull*>(node->get()))
                return null->jsValueInContext(context);
            if (OOJSValue* held = dynamic_cast<OOJSValue*>(node->get()))
                return held->jsValueInContext(context);
        }
        // A node that holds no Objective-C object (a C++ one): no JS glue. (The Objective-C object's
        // node went with the Objective-C runtime: no game object is one.)
        return JS_UNDEFINED;
    }
    }
    return JS_UNDEFINED;
}

// (OOJSObjectFromNativeObject() went with OOJSValueFromNativeObject().)

oo::Ref<OOJSValue> OOJSValue::valueWithJSValue(JSValueConst value, JSContext* context)
{
    oo::Ref<OOJSValue> result = oo::makeRef<OOJSValue>();
    result->initWithJSValue(value, context);
    return result;
}

void OOJSValue::initWithJSValue(JSValueConst value, JSContext* context)
{
    if (context == NULL)
        context = OOJSAcquireContext();

    _val = JS_DupValue(context, value);
    if (!JS_IsUndefined(_val)) {
        // The engine: the sender of its reset notifications. Kept for removing the
        // observer, so the destructor does not ask for the engine (which could make it).
        _resetSender = OOJavaScriptEngine::sharedEngine();
        oo::NotificationCenter::defaultCenter().addObserver(this, kOOJavaScriptEngineWillResetNotificationName,
            _resetSender,
            [this](const oo::Notification&) { deleteJSValue(); });
    }
}

void OOJSValue::deleteJSValue()
{
    if (!JS_IsUndefined(_val)) {
        JS_FreeValue(OOJSAcquireContext(), _val);
        _val = JS_UNDEFINED;

        oo::NotificationCenter::defaultCenter().removeObserver(this, kOOJavaScriptEngineWillResetNotificationName,
            _resetSender);
    }
}

OOJSValue::~OOJSValue()
{
    deleteJSValue();
}

JSValue OOJSValue::jsValueInContext(JSContext* context)
{
    return JS_DupValue(context, _val);
}

std::string OOJSValue::className() const
{
    return "OOJSValue";
}

std::string OOJSValue::description() const
{
    return oo::str::format("<OOJSValue %s>", oo::str::pointerDescription(this).c_str());
}

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

std::string OOJSClassNameOfValue(JSContext* context, JSValueConst value)
{
    if (!JS_IsObject(value))
        return "primitive";

    const char* registered = OOJSClassName(JS_GetClassID(value));
    if (registered != NULL)
        return registered;

    JSValue ctor = JS_GetPropertyStr(context, value, "constructor");
    JSValue name = JS_IsObject(ctor) ? JS_GetPropertyStr(context, ctor, "name") : JS_UNDEFINED;
    std::optional<std::string> result = cxx_OOStringFromJSValue(context, name);
    JS_FreeValue(context, name);
    JS_FreeValue(context, ctor);
    return result.value_or("Object");
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

// A vector box's JS value, a Vector3D (was OONativeVector (OOJavaScriptConversion)'s
// -oo_jsValueInContext:; the box's facade is deleted).
JSValue OONativeVectorJSValueInContext(OONativeVector* vector, JSContext* context)
{
    JSValue value = JS_UNDEFINED;
    VectorToJSValue(context, vector->getVector(), &value);
    return value;
}

OONull* OONull::null()
{
    static OONull* sNull = nullptr; // the one +1 is never released (amendment oo-r7m0 item 1)
    if (sNull == nullptr)
        sNull = oo::makeRef<OONull>().leakRef();
    return sNull;
}

// (-copyWithZone:, which answered the object itself, was the facade's: the one null is shared by reference.)

std::string OONull::className() const
{
    return "OONull";
}

std::string OONull::description() const
{
    return "<null>";
}

JSValue OONull::jsValueInContext(JSContext* /*context*/)
{
    return JS_NULL;
}

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

// The slot holds a C++ object: the C++ finalizer, which tells it its wrapper is gone (clearJSSelf,
// as -oo_clearJSSelf: was sent), releases the slot's retain and empties the slot.
void OOJSObjectWrapperFinalize(JSRuntime* runtime, JSValueConst thisObj)
{
    OOJSCxxObjectWrapperFinalize(runtime, thisObj);
}

// Only an Objective-C object found through the class's converter described itself (its
// -cxx_oo_jsDescription, else -description); a C++ node's object never did, and no slot holds an
// Objective-C object: the JS class names it.
JSValue OOJSObjectWrapperToString(JSContext* context, JSValueConst thisObj, int argc, JSValueConst* argv)
{
    OOJS_NATIVE_ENTER(context)

    std::optional<std::string> description;

    const char* className = OOJSClassName(JS_GetClassID(thisObj));
    if (className != NULL) {
        description = oo::str::format("[object %s]", className);
    }
    if (!description.has_value())
        description = std::string("[object]");

    OOJS_RETURN_STRING_OR_NULL(description);

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

    JSValue arg = OOJSEntityJSValue(entity, param->context); // the C++ entity's glue; entity is required to be non-nil (asserted above).

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

namespace {

/*	What the entity predicates ask an entity: C++, moved from OOObject+OOJavaScript.mm, whose
        one-line bridges they were.
*/
bool OOJavaScriptEngineIsVisibleToScripts(Entity* entity)
{
    return OOJSEntityIsVisibleToScripts(entity); // the C++ entity's answer, which the root facade's selector forwarded to
}

// The root facade's -isShip, -isSubEntity, -isPlanet and -status forwarded to these members.
bool OOJavaScriptEngineIsShip(Entity* entity)
{
    return entity != nullptr && entity->getIsShip();
}

bool OOJavaScriptEngineIsSubEntity(Entity* entity)
{
    return entity != nullptr && entity->getIsSubEntity();
}

bool OOJavaScriptEngineIsPlanet(Entity* entity)
{
    return entity != nullptr && entity->isPlanet();
}

OOEntityStatus OOJavaScriptEngineStatus(Entity* entity)
{
    return entity != nullptr ? entity->status() : OOEntityStatus { };
}

} // namespace

BOOL JSEntityIsJavaScriptVisiblePredicate(Entity* entity, void* parameter)
{
    return OOJavaScriptEngineIsVisibleToScripts(entity);
}

BOOL JSEntityIsJavaScriptSearchablePredicate(Entity* entity, void* parameter)
{
    if (!OOJavaScriptEngineIsVisibleToScripts(entity))
        return NO;
    if (OOJavaScriptEngineIsShip(entity)) {
        if (OOJavaScriptEngineIsSubEntity(entity))
            return NO;
        if (OOJavaScriptEngineStatus(entity) == STATUS_COCKPIT_DISPLAY)
            return NO; // Demo ship
        return YES;
    } else if (OOJavaScriptEngineIsPlanet(entity)) {
        switch (static_cast<OOPlanetEntity*>(entity)->planetType()) // a planet: not nil
        {
        case STELLAR_TYPE_MOON:
        case STELLAR_TYPE_NORMAL_PLANET:
        case STELLAR_TYPE_SUN:
            return YES;

        case STELLAR_TYPE_MINIATURE:
            return NO;
        }
    }

    return YES; // would happen if we added a new script-visible class
}

BOOL JSEntityIsDemoShipPredicate(Entity* entity, void* parameter)
{
    return (OOJavaScriptEngineIsVisibleToScripts(entity) && OOJavaScriptEngineIsShip(entity) && OOJavaScriptEngineStatus(entity) == STATUS_COCKPIT_DISPLAY && !OOJavaScriptEngineIsSubEntity(entity));
}

//===========================================================================
// Classes
//===========================================================================

// Class registration lives in OOJSClasses.m.

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

oo::PList cxx_OOJSDictionaryFromJSObject(JSContext* context, JSValueConst object)
{
    JSPropertyEnum* properties = NULL;
    uint32_t i, count;
    oo::PList::Dict result;

    if (JS_GetOwnPropertyNames(context, &properties, &count, object, JS_GPN_STRING_MASK | JS_GPN_ENUM_ONLY) < 0) {
        JS_FreeValue(context, JS_GetException(context));
        return oo::PList();
    }

    for (i = 0; i != count; ++i) {
        /*	An integer-like property is keyed by its decimal text, the name JS itself
                gives it (proposed ADR-0051). The Foundation converter kept it as a number
                key no native code could look up (CIM 15/2/13 asked whether the key should be
                a string), and this function gave a null PList for the whole object.
        */
        const std::optional<std::string> key = cxx_OOStringFromJSID(properties[i].atom);
        JSValue value = JS_GetProperty(context, object, properties[i].atom);
        if (JS_IsException(value)) {
            JS_FreeValue(context, JS_GetException(context));
            continue;
        }

        if (key.has_value() && !JS_IsUndefined(value)) {
            oo::PList element = cxx_OOJSPListFromJSValue(context, value);
            if (!element.isNull())
                result.insert_or_assign(*key, std::move(element));
        }
        JS_FreeValue(context, value);
    }

    JS_FreePropertyEnum(context, properties, count);
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

oo::PList cxx_OOJSPListFromJSValue(JSContext* context, JSValueConst value)
{
    if (JS_IsNull(value) || JS_IsUndefined(value))
        return oo::PList();

    int32_t intValue;
    double doubleValue;

    if (JS_VALUE_GET_TAG(value) == JS_TAG_INT) {
        JS_ToInt32(context, &intValue, value);
        return oo::PList::signedInteger(intValue);
    }
    if (JS_IsNumber(value)) {
        JS_ToFloat64(context, &doubleValue, value);
        return oo::PList(doubleValue);
    }
    if (JS_IsBool(value)) {
        return oo::PList(static_cast<bool>(JS_VALUE_GET_BOOL(value)));
    }
    if (JS_IsString(value)) {
        std::optional<std::string> string = cxx_OOStringFromJSValue(context, value);
        return string.has_value() ? oo::PList(std::move(*string)) : oo::PList();
    }
    if (JS_IsObject(value)) {
        return cxx_OOJSPListFromJSObject(context, value);
    }
    return oo::PList();
}

static oo::PList PListFromJSArray(JSContext* context, JSValueConst array);
static oo::PList PListFromJSStringObject(JSContext* context, JSValueConst object);
static oo::PList PListFromJSNumberObject(JSContext* context, JSValueConst object);
static oo::PList PListFromJSBooleanObject(JSContext* context, JSValueConst object);
static oo::PList PListFromJSPlainObject(JSContext* context, JSValueConst object);
static oo::PList JSArrayConverter(JSContext* context, JSValueConst array);
static oo::PList JSStringConverter(JSContext* context, JSValueConst object);
static oo::PList JSNumberConverter(JSContext* context, JSValueConst object);
static oo::PList JSBooleanConverter(JSContext* context, JSValueConst object);
static oo::PList JSObjectConverter(JSContext* context, JSValueConst object);

oo::PList cxx_OOJSPListFromJSObject(JSContext* context, JSValueConst object)
{
    if (!JS_IsObject(object))
        return oo::PList();

    JSClassID classID = JS_GetClassID(object);
    OOJSClassConverterCallback converter = (classID < kOOJSMaxClassID) ? sObjectConverters[classID] : NULL;
    if (converter == NULL)
        return oo::PList();

    // The engine's own converters build the PList; a private-object converter gives an Object node.
    return converter(context, object);
}

// The slot holds a C++ object: a node of it when it is a node's foreign object, else none; an empty
// slot is a null PList, as nil was.
oo::PList OOJSBasicPrivateObjectConverter(JSContext* /*context*/, JSValueConst object)
{
    JSClassID ignored;
    oo::RefCounted* held = static_cast<oo::RefCounted*>(JS_GetAnyOpaque(object, &ignored));
    if (oo::PListForeign* foreign = dynamic_cast<oo::PListForeign*>(held))
        return oo::PList(oo::PList::Object(foreign));
    return oo::PList();
}

void OOJSRegisterObjectConverter(JSClassID classID, OOJSClassConverterCallback converter)
{
    if (classID == 0 || classID >= kOOJSMaxClassID)
        return;
    sObjectConverters[classID] = converter;
}

static oo::PList PListFromJSArray(JSContext* context, JSValueConst array)
{
    int64_t i, count;
    oo::PList::Array values;

    // Convert a JS array to a native array by calling cxx_OOJSPListFromJSValue() on all its elements.
    if (!JS_IsArray(array))
        return oo::PList();
    if (JS_GetLength(context, array, &count) < 0) {
        JS_FreeValue(context, JS_GetException(context));
        return oo::PList();
    }

    values.reserve(static_cast<std::size_t>(count));
    for (i = 0; i != count; ++i) {
        JSValue value = JS_GetPropertyUint32(context, array, (uint32_t)i);
        if (JS_IsException(value)) {
            JS_FreeValue(context, JS_GetException(context));
            value = JS_UNDEFINED;
        }

        oo::PList element = cxx_OOJSPListFromJSValue(context, value);
        JS_FreeValue(context, value);
        if (element.isNull()) {
            element = OONullObjectNode(); // [OONull null]
        }
        values.push_back(std::move(element));
    }

    return oo::PList(std::move(values));
}

static oo::PList JSArrayConverter(JSContext* context, JSValueConst array)
{
    return PListFromJSArray(context, array);
}

static oo::PList PListFromJSStringObject(JSContext* context, JSValueConst object)
{
    std::optional<std::string> string = cxx_OOStringFromJSValue(context, object);
    return string.has_value() ? oo::PList(std::move(*string)) : oo::PList();
}

static oo::PList JSStringConverter(JSContext* context, JSValueConst object)
{
    return PListFromJSStringObject(context, object);
}

static oo::PList PListFromJSNumberObject(JSContext* context, JSValueConst object)
{
    double value;
    if (JS_ToFloat64(context, &value, object) == 0) {
        return oo::PList(value);
    }
    JS_FreeValue(context, JS_GetException(context));
    return oo::PList();
}

static oo::PList JSNumberConverter(JSContext* context, JSValueConst object)
{
    return PListFromJSNumberObject(context, object);
}

static oo::PList PListFromJSBooleanObject(JSContext* context, JSValueConst object)
{
    /*	Fun With JavaScript: Boolean(false) is a truthy value, since it's a
            non-null object. However, Boolean objects are transformed to numbers
            sanely, so this works.
    */
    double value;
    if (JS_ToFloat64(context, &value, object) == 0) {
        return oo::PList(value != 0);
    }
    JS_FreeValue(context, JS_GetException(context));
    return oo::PList();
}

static oo::PList JSBooleanConverter(JSContext* context, JSValueConst object)
{
    return PListFromJSBooleanObject(context, object);
}

// A plain JS Object: cxx_OOJSDictionaryFromJSObject() (proposed ADR-0051; was the bridge's
// Foundation converter, which kept an integer-like key as a number).
static oo::PList PListFromJSPlainObject(JSContext* context, JSValueConst object)
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
        return oo::PList();

    return cxx_OOJSDictionaryFromJSObject(context, object);
}

static oo::PList JSObjectConverter(JSContext* context, JSValueConst object)
{
    return PListFromJSPlainObject(context, object);
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
