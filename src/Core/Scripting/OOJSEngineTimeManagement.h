/*

OOJSEngineTimeManagement.h

Functionality related to time limiting and profiling of JavaScript code.

The profile classes are OOTimeProfile and OOTimeProfileEntry: the debug console
holds them and the engine converts them to JavaScript with
oo_jsValueInContext().


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

#pragma once

#include <algorithm>
#include <chrono>
#include <condition_variable>
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

#include "OOJavaScriptEngine.h"
#include "oofnd/Ref.hpp"

/*	Time Limiter

        The time limiter stops scripts from running an arbitrarily long time.

        The time limiter must be started before calling into JavaScript code.
        Calls to OOJSStartTimeLimiter() and OOJSStopTimeLimiter() must be
   balanced, and may be nested. OOJSStartTimeLimiterWithTimeLimit() is like
   OOJSStartTimeLimiter(), but specifies a custom time limit. This limit is only
   used if the limiter is actually stopped.

        The time limiter can be paused and resumed for native operations that
   are known to be slow. OOJSPauseTimeLimiter() and OOJSResumeTimeLimiter() must
        be balanced and can be nested, but the nest count may be negative - it
   is valid to call OOJSResumeTimeLimiter() followed by OOJSPauseTimeLimiter().

        With QuickJS, the limiter functions
   (OOJSStartTimeLimiterWithTimeLimit(), OOJSStartTimeLimiter(),
   OOJSStopTimeLimiter(), OOJSPauseTimeLimiter(), OOJSResumeTimeLimiter(),
   kOOJSLongTimeLimit and, in debug builds, OOJSResetTimeLimiter(),
   OOJSGetTimeLimiterLimit() and OOJSSetTimeLimiterLimit()) are declared in
   OOJavaScriptEngine.h and implemented in OOJavaScriptEngine.m. QuickJS polls
   an interrupt handler while running JS code, so no watchdog thread or
   operation callback is needed.

        Not ported: the debug-build variants that record the file and line of
        the last start/stop (OOJSStartTimeLimiterWithTimeLimit_() and
        OOJSStopTimeLimiter_()), which were only used to diagnose unbalanced
        calls.
*/

#if OOJS_PROFILE

/*
        Profiling support.

        OOJSBeginProfiling(trace), OOJSEndProfiling(), OOJSIsProfiling()
        Start, stop, and query profiling mode. It is a hard error to start
        profiling while already profiling.

        If trace is set, all profileable functions will be logged. The actual
        profile will be of little use in this case because of logging overhead.

        As in SpiderMonkey builds without MOZ_TRACE_JSCALLS, only natives are
        profiled (QuickJS has no function call hook); time not spent in natives
        is reported as JavaScript time.

        OOJSExcludeTimeFromLimiter()
        Extend the current time limit by the given time, unless the limiter is
        paused. Used to keep profiler overhead from counting towards the limit.

        NOTE: the profiler declarations that need to be visible to functions
   that are profiled are found in OOJavaScriptEngine.h.
*/

class OOTimeProfile;

oo::Ref<OOTimeProfile> OOJSEndProfiling(void);

void OOJSBeginProfiling(bool trace);
bool OOJSIsProfiling(void);

void OOJSExcludeTimeFromLimiter(OOTimeDelta time);

class OOTimeProfileEntry;

class OOTimeProfile : public oo::RefCounted {
 public:
  std::optional<std::string> description();

  double totalTime();
  double javaScriptTime();
  double nativeTime();
  double extensionTime();
  double nonExtensionTime();
  double profilerOverhead();

  std::vector<oo::Ref<OOTimeProfileEntry>>
  profileEntries();  // sorted by self time, longest first

  JSValue oo_jsValueInContext(JSContext* context);

  // Set by OOJSEndProfiling() (the old private category).
  void setTotalTime(double value);
  void setNativeTime(double value);
  void setProfilerOverhead(double value);
  void setExtensionTime(double value);
  void setProfileEntries(const std::vector<oo::Ref<OOTimeProfileEntry>>& value);

 private:
  oo::PList propertyListRepresentation();

  double _totalTime = {};
  double _nativeTime = {};
  double _extensionTime = {};
  double _profilerOverhead = {};

  std::vector<oo::Ref<OOTimeProfileEntry>> _profileEntries;
};

class OOTimeProfileEntry : public oo::RefCounted {
 public:
  // The profiler's (the old private category): only while profiling.
  explicit OOTimeProfileEntry(const char* name);

  void addSampleWithTotalTime(OOTimeDelta totalTime, OOTimeDelta selfTime);

  std::optional<std::string> description();

  std::optional<std::string> function();  // nullopt: none
  NSUInteger hitCount();
  double totalTimeSum();
  double selfTimeSum();
  double totalTimeAverage();
  double selfTimeAverage();
  double totalTimeMax();
  double selfTimeMax();
  bool isJavaScriptFrame();

  OOComparisonResult compareByTotalTime(OOTimeProfileEntry* other);
  OOComparisonResult compareByTotalTimeReverse(OOTimeProfileEntry* other);
  OOComparisonResult compareBySelfTime(OOTimeProfileEntry* other);
  OOComparisonResult compareBySelfTimeReverse(OOTimeProfileEntry* other);

  JSValue oo_jsValueInContext(JSContext* context);

 private:
  friend class OOTimeProfile;  // its "profiles" list holds each entry's
                               // property list
  oo::PList propertyListRepresentation();

  std::optional<std::string> _function;  // nullopt when created without a name
  unsigned long _hitCount = {};
  double _totalTimeSum = {};
  double _selfTimeSum = {};
  double _totalTimeMax = {};
  double _selfTimeMax = {};
};

#endif

class OOJavaScriptEngine;

/*	Formerly installed the watchdog thread and operation callback. The
   QuickJS interrupt handler is installed by OOJavaScriptEngine's constructor,
   so this does nothing; it is kept for source compatibility.
*/
void OOJSTimeManagementInit(OOJavaScriptEngine* engine, JSRuntime* runtime);
