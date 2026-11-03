/*

OOJavaScriptEnginePoc.mm (QuickJS-ng proof of concept)

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

#include "oofnd/Defaults.hpp"
#include "oofnd/Encoding.hpp"
#include "oofnd/Log.hpp"
#include "oofnd/String.hpp"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdarg>
#include <cstdlib>
#include <string_view>
#include <unordered_map>

#define OOJS_RUNTIME_SIZE_MiB 256
#define OOJS_TIME_LIMIT (1) // seconds

namespace {
cxx::OOJavaScriptEngine* sSharedEngine = nullptr; // the one +1 is never released
}

JSContext* gOOJSMainThreadContext = NULL;

static int InterruptHandler(JSRuntime* runtime, void* opaque);
static JSValue GlobalLog(OOJS_NATIVE_ARGS);

static const JSCFunctionListEntry sGlobalMethods[] = {
    JS_CFUNC_DEF("log", 1, GlobalLog),
};

//===========================================================================
// JavaScript engine initialisation and shutdown
//===========================================================================

/*	This minimal engine implements only what the harness uses of the full
        engine header. The engine methods the harness has no use for (mission
        callbacks, resets, garbage collection hints, the debug console's stack
        dump switches) do nothing.
*/
namespace cxx {

OOJavaScriptEngine* OOJavaScriptEngine::sharedEngine()
{
    if (sSharedEngine == nullptr) {
        OOJavaScriptEngine* engine = oo::makeRef<OOJavaScriptEngine>().leakRef();
        sSharedEngine = engine;
        engine->init();
    }

    return sSharedEngine;
}

void OOJavaScriptEngine::init()
{
    OOCAssert(sSharedEngine == this, "Attempt to create multiple OOJavaScriptEngines.");
    _showErrorLocations = true;

    _runtime = JS_NewRuntime();
    if (_runtime == NULL) {
        OO_LOG("script.javaScript.init.error", "{}", "***** FATAL ERROR: failed to create JavaScript runtime.");
        exit(1);
    }

    int64_t jsRuntimeInMiB = oo::Defaults::standard().integerForKey("jsruntime-size-mib");
    if (jsRuntimeInMiB <= 0)
        jsRuntimeInMiB = OOJS_RUNTIME_SIZE_MiB;
    JS_SetMemoryLimit(_runtime, static_cast<size_t>(jsRuntimeInMiB) * 1024 * 1024);
    JS_SetInterruptHandler(_runtime, InterruptHandler, NULL);
#ifndef NDEBUG
    JS_SetDumpFlags(_runtime, JS_DUMP_LEAKS);
#endif

    _context = JS_NewContext(_runtime);
    gOOJSMainThreadContext = _context;
    if (_context == NULL) {
        OO_LOG("script.javaScript.init.error", "{}", "***** FATAL ERROR: failed to create JavaScript context.");
        exit(1);
    }

    _globalObject = JS_GetGlobalObject(_context);
    JS_SetPropertyStr(_context, _globalObject, "global", JS_DupValue(_context, _globalObject));
    JS_SetPropertyFunctionList(_context, _globalObject, sGlobalMethods, OOJS_COUNT(sGlobalMethods));

    InitOOJSScript(_context, _globalObject);
    InitOOJSVector(_context, _globalObject);
    InitOOJSQuaternion(_context, _globalObject);
}

NSUInteger OOJavaScriptEngine::shutDown()
{
    if (_context == NULL)
        return 0;

    JS_FreeValue(_context, _globalObject);
    _globalObject = JS_UNDEFINED;
    JS_FreeContext(_context);
    _context = NULL;
    gOOJSMainThreadContext = NULL;

    JS_RunGC(_runtime);
    JSMemoryUsage usage;
    JS_ComputeMemoryUsage(_runtime, &usage);
    if (usage.obj_count != 0) {
        /*	JS_FreeRuntime() would assert. Dump what is left and abandon the
                runtime instead, so the leak can be reported.
        */
        OO_LOG("script.javaScript.shutDown.leak", "***** JavaScript runtime shut down with {} objects still alive; something is holding a JSValue it does not own, or has not freed one it does.", static_cast<long long>(usage.obj_count));
        JS_DumpMemoryUsage(stdout, &usage, _runtime);
        _runtime = NULL;
        return static_cast<NSUInteger>(usage.obj_count);
    }

    JS_FreeRuntime(_runtime);
    _runtime = NULL;
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

void OOJavaScriptEngine::runMissionCallback()
{
    // The harness has no mission screens.
}

bool OOJavaScriptEngine::reset()
{
    // The harness's context lives until shutDown(); it is never rebuilt.
    return false;
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
    // The harness collects only in shutDown().
    (void)force;
}

bool OOJavaScriptEngine::showErrorLocations()
{
    return _showErrorLocations;
}

void OOJavaScriptEngine::setShowErrorLocations(bool value)
{
    _showErrorLocations = value;
}

#ifdef OO_DEBUG_MONITOR_ENABLED
// The harness dumps no stacks; the switches are only kept.
bool OOJavaScriptEngine::dumpStackForErrors()
{
    return _dumpStackForErrors;
}

void OOJavaScriptEngine::setDumpStackForErrors(bool value)
{
    _dumpStackForErrors = value;
}

bool OOJavaScriptEngine::dumpStackForWarnings()
{
    return _dumpStackForWarnings;
}

void OOJavaScriptEngine::setDumpStackForWarnings(bool value)
{
    _dumpStackForWarnings = value;
}

void OOJavaScriptEngine::enableDebuggerStatement()
{
    // Not supported by QuickJS; does nothing, as in the full engine.
}
#endif

} // namespace cxx

JSAtom cxx_OOJSIDFromString(const std::string& string)
{
    // Interned for the life of the process, as in the full engine.
    static std::unordered_map<std::string, JSAtom> sAtomCache;

    auto cached = sAtomCache.find(string);
    if (cached != sAtomCache.end())
        return cached->second;
    JSAtom atom = JS_NewAtom(OOJSAcquireContext(), string.c_str());
    sAtomCache.emplace(string, atom);
    return atom;
}

JSValue OOJSNativeFailure(JSContext* context)
{
    if (JS_HasException(context))
        return JS_EXCEPTION;

    JSValue error = JS_NewError(context);
    JS_SetUncatchableError(context, error);
    return JS_Throw(context, error);
}

std::string OOJSWrapScriptSource(const std::string& source)
{
    // A newline before the closing part is needed if the last line is a // comment.
    const char* lineEnd = oo::str::hasSuffix(source, "\n") ? "" : "\n";
    return "with(this){(function(){" + source + lineEnd + "}).call(this)}";
}

//===========================================================================
// Global functions
//===========================================================================

// log([messageClass : String,] message : String, ...)
static JSValue GlobalLog(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    std::string message;
    std::string messageClass;

    if (EXPECT_NOT(argc < 1)) {
        OOJS_RETURN_VOID;
    }
    if (argc < 2) {
        messageClass = "script.debug.message";
        message = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]).value_or("(null)");
    } else {
        messageClass = cxx_OOStringFromJSValueEvenIfNull(context, OOJS_ARGV[0]).value_or("(null)");
        if (!oo::log::willDisplay(messageClass)) {
            // Do nothing (and short-circuit) if message class is filtered out.
            OOJS_RETURN_VOID;
        }

        for (int i = 1; i < argc; i++) {
            if (i != 1)
                message += ", ";
            message += cxx_OOStringFromJSValueEvenIfNull(context, OOJS_ARGV[i]).value_or("(null)");
        }
    }

    OOJS_BEGIN_FULL_NATIVE(context)
    OO_LOG(messageClass, "{}", message);
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
    return std::chrono::duration<double>(std::chrono::steady_clock::now().time_since_epoch()).count();
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

/*	QuickJS polls this regularly while running JS code, so unlike the
        SpiderMonkey operation callback no watchdog thread is needed. Returning
        non-zero throws an uncatchable error, which unwinds all JS frames.
*/
static int InterruptHandler(JSRuntime* /*runtime*/, void* /*opaque*/)
{
    if (EXPECT(sLimiterStartDepth == 0 || sLimiterPauseDepth > 0))
        return 0;

    double elapsed = MonotonicTime() - sLimiterStart;
    if (elapsed <= sLimiterTimeLimit)
        return 0;

    OO_LOG_ERR("script.javaScript.timeLimit", "Script \"{}\" ran for {:g} seconds and has been terminated.", [[OOJSScript currentlyRunningScript] name].value_or("(null)"), elapsed);
    return 1;
}

//===========================================================================
// Error reporting
//===========================================================================

/*	QuickJS records locations only in the stack property, as lines of the form
        "    at name (file:line:column)" or "    at file:line:column".
        Extract the file and line of the innermost frame.
*/
static BOOL GetLocationFromStack(const std::optional<std::string>& stack, std::string* outFile, unsigned* outLine)
{
    if (!stack.has_value())
        return NO;

    std::string_view rest(*stack);
    while (!rest.empty()) {
        const std::size_t newline = rest.find('\n');
        std::string_view frame = rest.substr(0, newline);
        rest = (newline == std::string_view::npos) ? std::string_view() : rest.substr(newline + 1);

        // -stringByTrimmingCharactersInSet: whitespace
        const std::size_t first = frame.find_first_not_of(" \t");
        if (first == std::string_view::npos)
            continue;
        frame = frame.substr(first, frame.find_last_not_of(" \t") - first + 1);
        if (frame.substr(0, 3) != "at ")
            continue;
        frame.remove_prefix(3);

        const std::size_t open = frame.rfind('(');
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

static void LogProblem(const std::string& severity, const std::string& errorName, const std::string& message, const std::optional<std::string>& stack)
{
    const std::string messageClass = "script.javaScript." + severity + "." + errorName;
    const char* highlight = (severity == "warning") ? "-----" : "*****";

    if (!oo::log::willDisplay(messageClass))
        return;

    const std::string activeScript = [[OOJSScript currentlyRunningScript] displayName].value_or("<unidentified script>");
    OO_LOG(messageClass, "{} JavaScript {} ({}): {}", highlight, severity, activeScript, message);

    std::string file;
    unsigned line = 0;
    if (cxx::OOJavaScriptEngine::sharedEngine()->showErrorLocations() && GetLocationFromStack(stack, &file, &line)) {
        OO_LOG(messageClass, "      {}, line {}.", file, line);
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

    std::string errorName = "exception";
    if (JS_IsError(exception)) {
        JSValue name = JS_GetPropertyStr(context, exception, "name");
        errorName = cxx_OOStringFromJSValue(context, name).value_or(errorName);
        JS_FreeValue(context, name);
    }

    LogProblem("exception", errorName, cxx_OOStringFromJSValueEvenIfNull(context, exception).value_or("(null)"), StackOfValue(context, exception));

    JS_FreeValue(context, exception);
    OOJSResumeTimeLimiter();
}

static std::string CallerPrefix(const std::optional<std::string>& scriptClass, const std::optional<std::string>& function)
{
    if (!function.has_value())
        return std::string();
    if (!scriptClass.has_value())
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
        // Squash any secondary errors during error handling.
    }
}

void cxx_OOJSReportErrorWithArguments(JSContext* context, const char* format, va_list args)
{
    try {
        std::string msg = oo::str::vformat(format, args);
        JS_ThrowPlainError(context, "%s", msg.c_str());
    } catch (...) {
        // Squash any secondary errors during error handling.
    }
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
        // Squash any secondary errors during error handling.
    }
}

void cxx_OOJSReportWarningWithArguments(JSContext* context, const char* format, va_list args)
{
    try {
        std::string msg = oo::str::vformat(format, args);

        // A fresh Error object captures the current JS stack, giving the location.
        JSValue error = JS_NewError(context);
        LogProblem("warning", "warning", msg, StackOfValue(context, error));
        JS_FreeValue(context, error);
    } catch (...) {
        // Squash any secondary errors during error handling.
    }
}

std::string cxx_OOStringFromJSPropertyMagic(int magic, const JSCFunctionListEntry* list, size_t count)
{
    for (size_t i = 0; i < count; i++) {
        if (list[i].def_type == JS_DEF_CGETSET_MAGIC && list[i].magic == magic)
            return std::string(list[i].name);
    }
    return std::to_string(magic);
}

void OOJSReportBadPropertySelector(JSContext* context, JSValueConst thisObj, int magic, const JSCFunctionListEntry* list, size_t count)
{
    const std::string propName = cxx_OOStringFromJSPropertyMagic(magic, list, count);
    const std::string className = OOJSClassNameOfValue(context, thisObj);

    cxx_OOJSReportError(context, "Invalid property identifier %s for instance of %s.", propName.c_str(), className.c_str());
}

void OOJSReportBadPropertyValue(JSContext* context, JSValueConst thisObj, int magic, const JSCFunctionListEntry* list, size_t count, JSValueConst value)
{
    const std::string propName = cxx_OOStringFromJSPropertyMagic(magic, list, count);
    const std::string className = OOJSClassNameOfValue(context, thisObj);
    const std::string valueDesc = cxx_OOJSDescribeValue(context, value, YES);

    cxx_OOJSReportError(context, "Cannot set property %s of instance of %s to invalid value %s.", propName.c_str(), className.c_str(), valueDesc.c_str());
}

void cxx_OOJSReportBadArguments(JSContext* context, const std::optional<std::string>& scriptClass, const std::optional<std::string>& function, int argc, JSValueConst* argv, const std::optional<std::string>& message, const std::optional<std::string>& expectedArgsDescription)
{
    try {
        std::string text = message.value_or("Invalid arguments");
        text += " " + cxx_OOJSStringWithJavaScriptParameters(argv, argc, context).value_or("(null)");
        if (expectedArgsDescription.has_value())
            text += " -- expected " + *expectedArgsDescription;

        cxx_OOJSReportErrorForCaller(context, scriptClass, function, "%s.", text.c_str());
    } catch (...) {
        // Squash any secondary errors during error handling.
    }
}

BOOL cxx_OOJSArgumentListGetNumber(JSContext* context, const std::optional<std::string>& scriptClass, const std::optional<std::string>& function, int argc, JSValueConst* argv, double* outNumber, int* outConsumed)
{
    if (OOJSArgumentListGetNumberNoError(context, argc, argv, outNumber, outConsumed)) {
        return YES;
    } else {
        cxx_OOJSReportBadArguments(context, scriptClass, function, argc, argv, std::string("Expected number, got"), std::nullopt);
        return NO;
    }
}

BOOL OOJSArgumentListGetNumberNoError(JSContext* context, int argc, JSValueConst* argv, double* outNumber, int* outConsumed)
{
    double value;

    OOCParameterAssert(context != NULL && (argv != NULL || argc == 0) && outNumber != NULL);

    // Get value, if possible.
    if (EXPECT_NOT(argc < 1 || JS_ToFloat64(context, &value, argv[0]) < 0 || std::isnan(value))) {
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

    JSValue ctor = JS_GetPropertyStr(context, value, "constructor");
    JSValue name = JS_IsObject(ctor) ? JS_GetPropertyStr(context, ctor, "name") : JS_UNDEFINED;
    std::optional<std::string> result = cxx_OOStringFromJSValue(context, name);
    JS_FreeValue(context, name);
    JS_FreeValue(context, ctor);
    return result.value_or("Object");
}

// Owned; undefined on failure. Null elements are dropped, as in the full engine.
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
        if (EXPECT_NOT(JS_SetPropertyUint32(context, result, i, OOJSValueFromPList(context, element)) < 0)) {
            JS_FreeValue(context, JS_GetException(context));
            JS_FreeValue(context, result);
            return JS_UNDEFINED;
        }
        ++i;
    }

    return result;
}

// Owned; undefined on failure. Null and undefined values are dropped and empty keys skipped, as in the full engine.
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

JSValue OOJSValueFromPList(JSContext* context, const oo::PList& plist)
{
    switch (plist.type()) {
    case oo::PList::Type::Null:
        return JS_NULL;

    case oo::PList::Type::Bool:
        return JS_NewInt32(context, *plist.getIf<bool>() ? 1 : 0);

    case oo::PList::Type::Integer: {
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
        double d = *plist.getIf<double>();
        if (plist.isSinglePrecision())
            d = static_cast<double>(static_cast<float>(d));
        return JS_NewFloat64(context, d);
    }

    case oo::PList::Type::String: {
        const std::string& string = *plist.getIf<std::string>();
        return JS_NewStringLen(context, string.data(), string.size());
    }

    case oo::PList::Type::Data:
    case oo::PList::Type::Date:
        return JS_UNDEFINED;

    case oo::PList::Type::Array:
        return JSArrayValueFromPList(context, *plist.getIf<oo::PList::Array>());

    case oo::PList::Type::Dict:
        return JSObjectValueFromPList(context, *plist.getIf<oo::PList::Dict>());

    case oo::PList::Type::Object:
        // The harness has no native-object glue: an object is undefined, as its NSObject glue gave.
        return JS_UNDEFINED;
    }
    return JS_UNDEFINED;
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

    if (JS_IsString(value)) {
        constexpr size_t kMaxLength = 200;

        // Truncated to kMaxLength UTF-16 units, as the NSString was cut.
        const std::u16string units = oo::utf8ToUtf16(cxx_OOStringFromJSValueEvenIfNull(context, value).value_or(""));
        const std::string truncated = oo::utf16ToUtf8(std::u16string_view(units.data(), std::min(units.size(), kMaxLength)));
        result = "\"" + cxx_OOJSEscapedForJavaScriptLiteral(truncated) + ((units.size() > kMaxLength) ? "..." : "") + "\"";
    } else if (JS_IsArray(value)) {
        // Descibe up to four elements of an array.
        int64_t count;
        if (JS_GetLength(context, value, &count) == 0) {
            if (!recursing) {
                std::string arrayDesc = "[";
                int64_t i, effectiveCount = std::min(count, static_cast<int64_t>(4));
                for (i = 0; i < effectiveCount; i++) {
                    JSValue item = JS_GetPropertyUint32(context, value, static_cast<uint32_t>(i));
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
                    arrayDesc += oo::str::format(", ... <%lli items total>]", static_cast<long long>(count));
                } else {
                    arrayDesc += "]";
                }

                result = arrayDesc;
            } else {
                result = oo::str::format("[<%lli items>]", static_cast<long long>(count));
            }
        } else {
            result = "[...]";
        }
    }

    if (!result.has_value()) {
        result = cxx_OOStringFromJSValueEvenIfNull(context, value);

        if (abbreviateObjects && JS_IsObject(value) && result == "[object Object]") {
            result = "{...}";
        }

        if (!result.has_value())
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

    std::string result = "(";

    for (int i = 0; i < count; ++i) {
        if (i != 0)
            result += ", ";
        result += cxx_OOJSDescribeValue(context, params[i], NO);
    }

    result += ")";
    return result;
}

std::string cxx_OOJSEscapedForJavaScriptLiteral(std::string_view string)
{
    /*	Byte-wise over UTF-8: every escaped character is ASCII, so multi-byte
            sequences pass through unchanged, as the UTF-16 units they encode did.
    */
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
