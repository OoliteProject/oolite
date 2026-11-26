/*

OOJSEngineTimeManagement.h


Copyright (C) 2010-2013 Jens Ayton

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/

#include "OOJSEngineTimeManagement.h"

#include "oofnd/PList.hpp"

#if OOJS_PROFILE
#include <cstddef>
#include <format>
#include <optional>
#include <string>
#include <string_view>
#include <unordered_map>
#include <utility>
#include <vector>

#include "oofnd/Log.hpp"
#include "oofnd/objc/OOAssert.h"
#endif

/*	The SpiderMonkey version of this file implemented the time limiter
        (with a watchdog thread that triggered SpiderMonkey's operation
        callback) and the JavaScript profiler.

        With QuickJS, the time limiter is implemented in OOJavaScriptEngine.m on
        top of QuickJS's interrupt handler, which QuickJS polls while running
        JavaScript, so neither the watchdog thread nor the operation callback is
        needed.

        The profiler is the SpiderMonkey one. JavaScript functions are profiled
        through the function call hook added by Oolite's QuickJS-ng patch
        (subprojects/packagefiles/quickjs-ng/0004-oolite-function-call-hook.patch),
        which stands in for SpiderMonkey's MOZ_TRACE_JSCALLS function callback.
        OOJS_QUICKJS_CALL_HOOK is set when building with the bundled, patched
        QuickJS-ng; with a system QuickJS-ng, only natives are profiled.
*/

void OOJSTimeManagementInit(OOJavaScriptEngine* /*engine*/,
                            JSRuntime* /*runtime*/) {
  // The interrupt handler is installed by OOJavaScriptEngine's constructor.
}

#if OOJS_PROFILE

namespace {
static bool sProfiling = false;
static bool sTracing = false;
}  // namespace
static OOJSProfileStackFrame* sProfileStack = nullptr;
// Profile key (native name or JS function, by pointer) -> entry, retained.
namespace {
static std::unordered_map<const void*, std::shared_ptr<OOTimeProfileEntry>>*
    sProfileInfo;

static OOTimeProfileEntry* ProfileEntryForKey(const void* key) {
  auto found = sProfileInfo->find(key);
  return (found != sProfileInfo->end()) ? found->second.get() : nullptr;
}
}  // namespace
static double sProfilerOverhead;
static double sProfilerTotalNativeTime;
static double sProfilerEntryTimeLimit;
static OOHighResTimeValue sProfilerStartTime;

#if OOJS_QUICKJS_CALL_HOOK
static double sProfilerTotalJavaScriptTime;

/*	Profile entries for JavaScript functions are keyed by the function's
        bytecode. A reference to a function using each bytecode is held until
        profiling ends, so the bytecode can't be freed and its address reused
        for another function.
*/
static JSValue* sProfiledFunctions;
static std::size_t sProfiledFunctionCount;
static std::size_t sProfiledFunctionCapacity;

namespace {
static void FunctionCallHook(JSContext* context, JSValueConst function,
                             const void* code, JSValueConst thisObj, int argc,
                             JSValueConst* argv, bool entering, void* opaque);
}  // namespace
#endif

void OOJSBeginProfiling(bool trace) {
  assert(sProfiling == false);
  sProfiling = true;
  sTracing = trace;
  sProfileInfo =
      new std::unordered_map<const void*, std::shared_ptr<OOTimeProfileEntry>>;
  sProfileInfo->reserve(100);
  sProfilerOverhead = 0.0;
  sProfilerTotalNativeTime = 0.0;
  sProfilerEntryTimeLimit = OOJSGetTimeLimiterLimit();

#if OOJS_QUICKJS_CALL_HOOK
  sProfilerTotalJavaScriptTime = 0.0;
  sProfiledFunctionCount = 0;
  JSContext* context = OOJSAcquireContext();
  JS_SetFunctionCallHook(JS_GetRuntime(context), FunctionCallHook, nullptr);
  OOJSRelinquishContext(context);
#endif

  // This should be last for precision.
  sProfilerStartTime = OOGetHighResTime();

  if (trace) {
    OO_LOG("script.javaScript.trace", "{}", ">>>> Beginning trace.");
    oo::log::indent();
  }
}

std::shared_ptr<OOTimeProfile> OOJSEndProfiling() {
  // This should be at the top for precision.
  OOHighResTimeValue now = OOGetHighResTime();
  // Time limiter should be as close to outermost as practical.
  OOJSPauseTimeLimiter();

  assert(sProfiling && sProfileStack == nullptr);

  sProfiling = false;

  std::shared_ptr<OOTimeProfile> result = oo::makeShared<OOTimeProfile>();

  result->setTotalTime(OOHighResTimeDeltaInSeconds(sProfilerStartTime, now));
  result->setNativeTime(sProfilerTotalNativeTime);
#if OOJS_QUICKJS_CALL_HOOK
  result->setJavaScriptTime(sProfilerTotalJavaScriptTime);
#else
  result->setJavaScriptTime(result->totalTime() - sProfilerTotalNativeTime);
#endif
  result->setProfilerOverhead(sProfilerOverhead);

  double currentTimeLimit = OOJSGetTimeLimiterLimit();
  result->setExtensionTime(currentTimeLimit - sProfilerEntryTimeLimit);

  std::vector<std::shared_ptr<OOTimeProfileEntry>> entries;
  entries.reserve(sProfileInfo->size());
  for (const auto& keyAndEntry : *sProfileInfo)
    entries.emplace_back(keyAndEntry.second);
  std::stable_sort(entries.begin(), entries.end(),
                   [](const auto& a, const auto& b) {
                     return a->compareBySelfTimeReverse(b.get()) ==
                            OOComparisonResult::kAscending;
                   });
  result->setProfileEntries(entries);

  if (sTracing) {
    oo::log::outdent();
    OO_LOG("script.javaScript.trace", "{}", "<<<< End of trace.");
    sTracing = false;
  }

  // Clean up (the table held the entries' references).
#if OOJS_QUICKJS_CALL_HOOK
  JSContext* context = OOJSAcquireContext();
  JS_SetFunctionCallHook(JS_GetRuntime(context), nullptr, nullptr);
  for (std::size_t i = 0; i < sProfiledFunctionCount; i++) {
    JS_FreeValue(context, sProfiledFunctions[i]);
  }
  sProfiledFunctionCount = 0;
  OOJSRelinquishContext(context);
#endif

  delete sProfileInfo;
  sProfileInfo = nullptr;
  OODisposeHighResTime(sProfilerStartTime);

  OODisposeHighResTime(now);

  OOJSResumeTimeLimiter();
  return result;
}

bool OOJSIsProfiling() { return sProfiling; }

namespace {
static void UpdateProfileForFrame(OOHighResTimeValue now,
                                  OOJSProfileStackFrame* frame);

#if OOJS_QUICKJS_CALL_HOOK
static void CleanUpJSFrame(OOJSProfileStackFrame* frame) {
  OODisposeHighResTime(frame->startTime);
  free(frame);
}

static void HoldProfiledFunction(JSContext* context, JSValueConst function) {
  if (sProfiledFunctionCount == sProfiledFunctionCapacity) {
    sProfiledFunctionCapacity =
        sProfiledFunctionCapacity ? sProfiledFunctionCapacity * 2 : 64;
    sProfiledFunctions = static_cast<JSValue*>(
        realloc(sProfiledFunctions,
                sProfiledFunctionCapacity * sizeof *sProfiledFunctions));
    assert(sProfiledFunctions != nullptr);
  }
  sProfiledFunctions[sProfiledFunctionCount++] = JS_DupValue(context, function);
}

static void TraceEnterJSFunction(JSContext* context, JSValueConst thisObj,
                                 int argc, JSValueConst* argv,
                                 OOTimeProfileEntry* profileEntry) {
  std::string name = profileEntry->function().value_or("(null)") + "(";

  // Temporarily disable profiling as we'll call out to profiled functions to
  // get value descriptions.
  sProfiling = false;

  bool first = true;
  if (!JS_IsUndefined(thisObj)) {
    name += "this: " + OOJSDescribeValue(context, thisObj, true);
    first = false;
  }
  for (int i = 0; i < argc; i++) {
    if (!first)
      name += ", ";
    else
      first = false;
    name += OOJSDescribeValue(context, argv[i], true);
  }

  sProfiling = true;

  name += ")";
  OO_LOG("script.javaScript.trace.JS", ">> {} [JS]", name);
  oo::log::indent();
}

static void FunctionCallHook(JSContext* context, JSValueConst function,
                             const void* code, JSValueConst thisObj, int argc,
                             JSValueConst* argv, bool entering, void* opaque) {
  if (EXPECT(!sProfiling)) return;

  OOHighResTimeValue start = OOGetHighResTime();
  bool startOwnedByFrame = false;

  {
    if (entering) {
      // Create profile entry up front so we can shove the JS function in it.
      OOTimeProfileEntry* entry = ProfileEntryForKey(code);
      if (entry == nullptr) {
        const std::shared_ptr<OOTimeProfileEntry> made =
            oo::makeShared<OOTimeProfileEntry>(function, context);
        (*sProfileInfo)[code] = made;  // the table's reference
        entry = made.get();
        HoldProfiledFunction(context, function);
      }

      if (EXPECT_NOT(sTracing)) {
        // We use EXPECT_NOT here because profiles are time-critical and traces
        // are not.
        TraceEnterJSFunction(context, thisObj, argc, argv, entry);
      }

      // Make a stack frame on the heap.
      OOJSProfileStackFrame* frame = static_cast<OOJSProfileStackFrame*>(
          malloc(sizeof(OOJSProfileStackFrame)));
      assert(frame != nullptr);

      *frame = (OOJSProfileStackFrame){.back = sProfileStack,
                                       .key = code,
                                       .function = nullptr,
                                       .startTime = start,
                                       .subTime = 0.0,
                                       .total = &sProfilerTotalJavaScriptTime,
                                       .cleanup = CleanUpJSFrame};

      sProfileStack = frame;
      startOwnedByFrame = true;
    } else if (sProfileStack != nullptr &&
               sProfileStack->cleanup == CleanUpJSFrame &&
               sProfileStack->key == code) {
      // Exiting. A frame entered before profiling started is not on the profile
      // stack.
      UpdateProfileForFrame(start, sProfileStack);
    }
  }

  OOHighResTimeValue end = OOGetHighResTime();
  double currentOverhead = OOHighResTimeDeltaInSeconds(start, end);
  sProfilerOverhead += currentOverhead;
  OOJSExcludeTimeFromLimiter(currentOverhead);
  if (!startOwnedByFrame) OODisposeHighResTime(start);
  OODisposeHighResTime(end);
}
#endif
}  // namespace

void OOJSProfileEnter(OOJSProfileStackFrame* frame, const char* function) {
  if (EXPECT(!sProfiling)) return;
  if (EXPECT_NOT(sTracing)) {
    // We use EXPECT_NOT here because profiles are time-critical and traces are
    // not.
    OO_LOG("script.javaScript.trace.ON", ">> {} [ON]", function);
    oo::log::indent();
  }

  *frame = (OOJSProfileStackFrame){.back = sProfileStack,
                                   .key = function,
                                   .function = function,
                                   .startTime = OOGetHighResTime(),
                                   .subTime = 0,
                                   .total = &sProfilerTotalNativeTime,
                                   .cleanup = nullptr};
  sProfileStack = frame;
}

void OOJSProfileExit(OOJSProfileStackFrame* frame) {
  if (EXPECT(!sProfiling)) return;

  /*	A frame entered before profiling started (such as the console's
          profile() itself) is not on the profile stack.
  */
  OOJSProfileStackFrame* search = sProfileStack;
  while (search != nullptr && search != frame) search = search->back;
  if (search == nullptr) return;

  OOHighResTimeValue now = OOGetHighResTime();
  {
    bool done = false;

    // Pop any frames above this one, as for a native that threw.
    for (;;) {
      assert(sProfileStack != nullptr);

      done = (sProfileStack == frame);
      UpdateProfileForFrame(now, sProfileStack);
      if (EXPECT(done)) break;
    }
  }

  OODisposeHighResTime(frame->startTime);

  OOHighResTimeValue end = OOGetHighResTime();
  double currentOverhead = OOHighResTimeDeltaInSeconds(now, end);
  sProfilerOverhead += currentOverhead;
  OOJSExcludeTimeFromLimiter(currentOverhead);

  OODisposeHighResTime(now);
  OODisposeHighResTime(end);
}

namespace {
static void UpdateProfileForFrame(OOHighResTimeValue now,
                                  OOJSProfileStackFrame* frame) {
  sProfileStack = frame->back;

  OOTimeProfileEntry* entry = ProfileEntryForKey(frame->key);
  if (entry == nullptr) {
    const std::shared_ptr<OOTimeProfileEntry> made =
        oo::makeShared<OOTimeProfileEntry>(frame->function);
    (*sProfileInfo)[frame->key] = made;  // the table's reference
    entry = made.get();
  }

  OOTimeDelta time = OOHighResTimeDeltaInSeconds(frame->startTime, now);
  OOTimeDelta selfTime = time - frame->subTime;
  entry->addSampleWithTotalTime(time, selfTime);

  *(frame->total) += selfTime;
  if (sProfileStack != nullptr) sProfileStack->subTime += time;

  if (frame->cleanup != nullptr) frame->cleanup(frame);

  if (EXPECT_NOT(sTracing)) oo::log::outdent();
}
}  // namespace

std::optional<std::string> OOTimeProfile::description() {
  double totalTime = this->totalTime();

  std::string result = std::format(
      "Total time: {:g} ms\nJavaScript: {:g} ms, native: {:g} ms\nCounted "
      "towards limit: {:g} ms, excluded: {:g} ms\nProfiler overhead: {:g} ms",
      totalTime * 1000.0, javaScriptTime() * 1000.0, nativeTime() * 1000.0,
      nonExtensionTime() * 1000.0, extensionTime() * 1000.0,
      profilerOverhead() * 1000.0);

  const std::vector<std::shared_ptr<OOTimeProfileEntry>>& profileEntries =
      _profileEntries;
  std::size_t i, count = profileEntries.size();
  if (count != 0) {
    result +=
        "\n                                                        NAME  T  "
        "COUNT    TOTAL     SELF  TOTAL%   SELF%  SELFMAX";
    for (i = 0; i < count; i++) {
      OOTimeProfileEntry* entry = profileEntries[i].get();

      double totalPc = entry->totalTimeSum() * 100.0 / totalTime;
      double selfPc = entry->selfTimeSum() * 100.0 / totalTime;

      result += std::format(
          "\n{:>60}  {}{:7} {:8.2f} {:8.2f}   {:5.1f}   {:5.1f} {:8.2f}",
          entry->function().value_or("(null)"),
          entry->isJavaScriptFrame() ? 'J' : 'N',
          static_cast<unsigned long>(entry->hitCount()),
          entry->totalTimeSum() * 1000.0, entry->selfTimeSum() * 1000.0,
          totalPc, selfPc, entry->selfTimeMax() * 1000.0);
    }
  }

  return result;
}

double OOTimeProfile::totalTime() { return _totalTime; }

void OOTimeProfile::setTotalTime(double value) { _totalTime = value; }

double OOTimeProfile::javaScriptTime() { return _javaScriptTime; }

void OOTimeProfile::setJavaScriptTime(double value) { _javaScriptTime = value; }

double OOTimeProfile::nativeTime() { return _nativeTime; }

void OOTimeProfile::setNativeTime(double value) { _nativeTime = value; }

double OOTimeProfile::extensionTime() { return _extensionTime; }

void OOTimeProfile::setExtensionTime(double value) { _extensionTime = value; }

double OOTimeProfile::nonExtensionTime() { return _totalTime - _extensionTime; }

double OOTimeProfile::profilerOverhead() { return _profilerOverhead; }

void OOTimeProfile::setProfilerOverhead(double value) {
  _profilerOverhead = value;
}

std::vector<std::shared_ptr<OOTimeProfileEntry>>
OOTimeProfile::profileEntries() {
  return _profileEntries;
}

void OOTimeProfile::setProfileEntries(
    const std::vector<std::shared_ptr<OOTimeProfileEntry>>& value) {
  _profileEntries = value;
}

JSValue OOTimeProfile::oo_jsValueInContext(JSContext* context) {
  return OOJSValueFromPList(context, propertyListRepresentation());
}

oo::PList OOTimeProfile::propertyListRepresentation() {
  // "profiles" holds each entry's own property list.
  oo::PList::Array profiles;
  profiles.reserve(_profileEntries.size());
  for (const auto& entry : _profileEntries)
    profiles.push_back(entry->propertyListRepresentation());

  oo::PList::Dict result;
  result.emplace("profiles", oo::PList(std::move(profiles)));
  result.emplace("totalTime", oo::PList(totalTime()));
  result.emplace("javaScriptTime", oo::PList(javaScriptTime()));
  result.emplace("nativeTime", oo::PList(nativeTime()));
  result.emplace("extensionTime", oo::PList(extensionTime()));
  result.emplace("nonExtensionTime", oo::PList(nonExtensionTime()));
  result.emplace("profilerOverhead", oo::PList(profilerOverhead()));
  return oo::PList(std::move(result));
}

OOTimeProfileEntry::OOTimeProfileEntry(const char* name) {
  OOCAssert(sProfiling, "Can't create profile entries while not profiling.");

  {
    if (name != nullptr) {
      _function = std::string(name);
    }
  }
}

#if OOJS_QUICKJS_CALL_HOOK
OOTimeProfileEntry::OOTimeProfileEntry(JSValueConst function,
                                       JSContext* context)
    : OOTimeProfileEntry(static_cast<const char*>(nullptr)) {
  // Temporarily disable profiling so we don't profile the profiler while it's
  // profiling the profilee.
  sProfiling = false;
  _isJavaScriptFrame = true;

  JSAtom nameAtom, fileAtom;
  int line;
  std::string funcName;
  std::optional<std::string> location;
  if (JS_GetFunctionInfo(context, function, &nameAtom, &fileAtom, &line)) {
    if (nameAtom != JS_ATOM_NULL) {
      funcName = OOStringFromJSID(nameAtom).value_or("");
      JS_FreeAtom(context, nameAtom);
    }
    if (fileAtom != JS_ATOM_NULL) {
      location =
          std::format("{}:{}", OOStringFromJSID(fileAtom).value_or(""), line);
      JS_FreeAtom(context, fileAtom);
    }
  }
  if (funcName.empty()) funcName = "<anonymous>";

  if (location.has_value()) {
    _function = std::format("({}) {}", *location, funcName);
  } else
    _function = funcName;

  sProfiling = true;
}
#endif

void OOTimeProfileEntry::addSampleWithTotalTime(OOTimeDelta totalTime,
                                                OOTimeDelta selfTime) {
  _hitCount++;
  _totalTimeSum += totalTime;
  _selfTimeSum += selfTime;
  _totalTimeMax = fmax(_totalTimeMax, totalTime);
  _selfTimeMax = fmax(_selfTimeMax, selfTime);
}

std::optional<std::string> OOTimeProfileEntry::description() {
  const std::string_view function = _function.has_value()
                                        ? std::string_view(*_function)
                                        : "(null)";  // as %@ printed nil
  if (_hitCount == 0) return std::format("{}: --", function);

  // Convert everything to milliseconds.
  float totalTimeSum = _totalTimeSum * 1000.0;
  float selfTimeSum = _selfTimeSum * 1000.0;
  float totalTimeMax = _totalTimeMax * 1000.0;
  float selfTimeMax = _selfTimeMax * 1000.0;

  if (totalTimeSum == selfTimeSum && totalTimeMax == selfTimeMax) {
    if (_hitCount == 1) {
      return std::format("{}: 1 time, {:g} ms", function, totalTimeSum);
    } else {
      return std::format(
          "{}: {} times, total {:g} ms, avg {:g} ms, max {:g} ms", function,
          _hitCount, totalTimeSum, totalTimeSum / _hitCount, totalTimeMax);
    }
  } else {
    if (_hitCount == 1) {
      return std::format("{}: 1 time, {:g} ms (self {:g} ms)", function,
                         totalTimeSum, selfTimeSum);
    } else {
      return std::format(
          "{}: {} times, total {:g} ms (self {:g} ms), avg {:g} ms (self {:g} "
          "ms), max {:g} ms, max self {:g} ms",
          function, _hitCount, totalTimeSum, selfTimeSum,
          totalTimeSum / _hitCount, selfTimeSum / _hitCount, totalTimeMax,
          selfTimeMax);
    }
  }
}

std::optional<std::string> OOTimeProfileEntry::function() { return _function; }

std::size_t OOTimeProfileEntry::hitCount() { return _hitCount; }

double OOTimeProfileEntry::totalTimeSum() { return _totalTimeSum; }

double OOTimeProfileEntry::selfTimeSum() { return _selfTimeSum; }

double OOTimeProfileEntry::totalTimeAverage() {
  return _hitCount ? (_totalTimeSum / _hitCount) : 0.0;
}

double OOTimeProfileEntry::selfTimeAverage() {
  return _hitCount ? (_selfTimeSum / _hitCount) : 0.0;
}

double OOTimeProfileEntry::totalTimeMax() { return _totalTimeMax; }

double OOTimeProfileEntry::selfTimeMax() { return _selfTimeMax; }

bool OOTimeProfileEntry::isJavaScriptFrame() { return _isJavaScriptFrame; }

OOComparisonResult OOTimeProfileEntry::compareByTotalTime(
    OOTimeProfileEntry* other) {
  return static_cast<OOComparisonResult>(
      -oo::ToUnderlying(compareByTotalTimeReverse(other)));
}

OOComparisonResult OOTimeProfileEntry::compareByTotalTimeReverse(
    OOTimeProfileEntry* other) {
  double selfTotal = totalTimeSum();
  double otherTotal = (other != nullptr) ? other->totalTimeSum()
                                         : 0.0;  // (a message to nil gave 0)

  if (selfTotal < otherTotal) return OOComparisonResult::kDescending;
  if (selfTotal > otherTotal) return OOComparisonResult::kAscending;
  return OOComparisonResult::kSame;
}

OOComparisonResult OOTimeProfileEntry::compareBySelfTime(
    OOTimeProfileEntry* other) {
  return static_cast<OOComparisonResult>(
      -oo::ToUnderlying(compareBySelfTimeReverse(other)));
}

OOComparisonResult OOTimeProfileEntry::compareBySelfTimeReverse(
    OOTimeProfileEntry* other) {
  double selfTotal = selfTimeSum();
  double otherTotal = (other != nullptr) ? other->selfTimeSum()
                                         : 0.0;  // (a message to nil gave 0)

  if (selfTotal < otherTotal) return OOComparisonResult::kDescending;
  if (selfTotal > otherTotal) return OOComparisonResult::kAscending;
  return OOComparisonResult::kSame;
}

JSValue OOTimeProfileEntry::oo_jsValueInContext(JSContext* context) {
  return OOJSValueFromPList(context, propertyListRepresentation());
}

oo::PList OOTimeProfileEntry::propertyListRepresentation() {
  oo::PList::Dict result;
  // A nameless entry gave an empty dictionary: its nil name ended the
  // object/key list.
  if (_function.has_value()) {
    result.emplace("name", oo::PList(*_function));
    result.emplace("hitCount", oo::PList::unsignedInteger(hitCount()));
    result.emplace("totalTimeSum", oo::PList(totalTimeSum()));
    result.emplace("selfTimeSum", oo::PList(selfTimeSum()));
    result.emplace("totalTimeAverage", oo::PList(totalTimeAverage()));
    result.emplace("selfTimeAverage", oo::PList(selfTimeAverage()));
    result.emplace("totalTimeMax", oo::PList(totalTimeMax()));
    result.emplace("selfTimeMax", oo::PList(selfTimeMax()));
    result.emplace("isJavaScriptFrame",
                   oo::PList(static_cast<bool>(isJavaScriptFrame())));
  }
  return oo::PList(std::move(result));
}

#endif
