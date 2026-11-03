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

#import "OOJSEngineTimeManagement.h"
#import "OOObjCPList.h"
#include "oofnd/String.hpp"
#include "oofnd/Log.hpp"
#include "oofnd/StdLib.hpp"
#include "oofnd/objc/OOAssert.h"

/*	The SpiderMonkey version of this file implemented the time limiter
        (with a watchdog thread that triggered SpiderMonkey's operation
        callback) and the JavaScript profiler.

        With QuickJS, the time limiter is implemented in OOJavaScriptEngine.m on
        top of QuickJS's interrupt handler, which QuickJS polls while running
        JavaScript, so neither the watchdog thread nor the operation callback is
        needed.

        The profiler is the SpiderMonkey one without MOZ_TRACE_JSCALLS support:
        only natives are profiled.
*/

void OOJSTimeManagementInit(OOJavaScriptEngine* /*engine*/, JSRuntime* /*runtime*/)
{
    // The interrupt handler is installed by -[OOJavaScriptEngine init].
}

#if OOJS_PROFILE

namespace {
static bool sProfiling = false;
static bool sTracing = false;
} // namespace
static OOJSProfileStackFrame* sProfileStack = NULL;
// Profile key (native name or JS function, by pointer) -> entry, retained. Was a map table with
// non-owned pointer keys and retained object values (bead oo-3rb.20).
namespace {
static std::unordered_map<const void*, oo::Ref<OOTimeProfileEntry>>* sProfileInfo;

static OOTimeProfileEntry* ProfileEntryForKey(const void* key)
{
    auto found = sProfileInfo->find(key);
    return (found != sProfileInfo->end()) ? found->second.get() : nullptr;
}
} // namespace
static double sProfilerOverhead;
static double sProfilerTotalNativeTime;
static double sProfilerEntryTimeLimit;
static OOHighResTimeValue sProfilerStartTime;

void OOJSBeginProfiling(bool trace)
{
    assert(sProfiling == false);
    sProfiling = true;
    sTracing = trace;
    sProfileInfo = new std::unordered_map<const void*, oo::Ref<OOTimeProfileEntry>>;
    sProfileInfo->reserve(100);
    sProfilerOverhead = 0.0;
    sProfilerTotalNativeTime = 0.0;
    sProfilerEntryTimeLimit = OOJSGetTimeLimiterLimit();

    // This should be last for precision.
    sProfilerStartTime = OOGetHighResTime();

    if (trace) {
        OO_LOG("script.javaScript.trace", "{}", ">>>> Beginning trace.");
        oo::log::indent();
    }
}

oo::Ref<OOTimeProfile> OOJSEndProfiling(void)
{
    // This should be at the top for precision.
    OOHighResTimeValue now = OOGetHighResTime();
    // Time limiter should be as close to outermost as practical.
    OOJSPauseTimeLimiter();

    assert(sProfiling && sProfileStack == NULL);

    sProfiling = false;

    oo::Ref<OOTimeProfile> result = oo::makeRef<OOTimeProfile>();

    result->setTotalTime(OOHighResTimeDeltaInSeconds(sProfilerStartTime, now));
    result->setNativeTime(sProfilerTotalNativeTime);
    result->setProfilerOverhead(sProfilerOverhead);

    double currentTimeLimit = OOJSGetTimeLimiterLimit();
    result->setExtensionTime(currentTimeLimit - sProfilerEntryTimeLimit);

    std::vector<oo::Ref<OOTimeProfileEntry>> entries;
    entries.reserve(sProfileInfo->size());
    for (const auto& keyAndEntry : *sProfileInfo)
        entries.emplace_back(keyAndEntry.second);
    std::stable_sort(entries.begin(), entries.end(), [](const auto& a, const auto& b) { return a->compareBySelfTimeReverse(b.get()) == OOOrderedAscending; });
    result->setProfileEntries(entries);

    if (sTracing) {
        oo::log::outdent();
        OO_LOG("script.javaScript.trace", "{}", "<<<< End of trace.");
        sTracing = false;
    }

    // Clean up (the table held the entries' references).
    delete sProfileInfo;
    sProfileInfo = NULL;
    OODisposeHighResTime(sProfilerStartTime);

    OODisposeHighResTime(now);

    OOJSResumeTimeLimiter();
    return result;
}

bool OOJSIsProfiling(void)
{
    return sProfiling;
}

namespace {
static void UpdateProfileForFrame(OOHighResTimeValue now, OOJSProfileStackFrame* frame);
} // namespace

void OOJSProfileEnter(OOJSProfileStackFrame* frame, const char* function)
{
    if (EXPECT(!sProfiling))
        return;
    if (EXPECT_NOT(sTracing)) {
        // We use EXPECT_NOT here because profiles are time-critical and traces are not.
        OO_LOG("script.javaScript.trace.ON", ">> {} [ON]", function);
        oo::log::indent();
    }

    *frame = (OOJSProfileStackFrame) {
        .back = sProfileStack,
        .key = function,
        .function = function,
        .startTime = OOGetHighResTime(),
        .subTime = 0,
        .total = &sProfilerTotalNativeTime
    };
    sProfileStack = frame;
}

void OOJSProfileExit(OOJSProfileStackFrame* frame)
{
    if (EXPECT(!sProfiling))
        return;

    /*	A frame entered before profiling started (such as the console's
            profile() itself) is not on the profile stack.
    */
    OOJSProfileStackFrame* search = sProfileStack;
    while (search != NULL && search != frame)
        search = search->back;
    if (search == NULL)
        return;

    OOHighResTimeValue now = OOGetHighResTime();
    @autoreleasepool {
        bool done = false;

        // Pop any frames above this one, as for a native that threw.
        for (;;) {
            assert(sProfileStack != NULL);

            done = (sProfileStack == frame);
            UpdateProfileForFrame(now, sProfileStack);
            if (EXPECT(done))
                break;
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
static void UpdateProfileForFrame(OOHighResTimeValue now, OOJSProfileStackFrame* frame)
{
    sProfileStack = frame->back;

    OOTimeProfileEntry* entry = ProfileEntryForKey(frame->key);
    if (entry == nullptr) {
        const oo::Ref<OOTimeProfileEntry> made = oo::makeRef<OOTimeProfileEntry>(frame->function);
        (*sProfileInfo)[frame->key] = made; // the table's reference
        entry = made.get();
    }

    OOTimeDelta time = OOHighResTimeDeltaInSeconds(frame->startTime, now);
    OOTimeDelta selfTime = time - frame->subTime;
    entry->addSampleWithTotalTime(time, selfTime);

    *(frame->total) += selfTime;
    if (sProfileStack != NULL)
        sProfileStack->subTime += time;

    if (EXPECT_NOT(sTracing))
        oo::log::outdent();
}
} // namespace

std::optional<std::string> OOTimeProfile::description()
{
    double totalTime = this->totalTime();

    std::string result = oo::str::format(
        "Total time: %g ms\n"
        "JavaScript: %g ms, native: %g ms\n"
        "Counted towards limit: %g ms, excluded: %g ms\n"
        "Profiler overhead: %g ms",
        totalTime * 1000.0,
        javaScriptTime() * 1000.0, nativeTime() * 1000.0,
        nonExtensionTime() * 1000.0, extensionTime() * 1000.0,
        profilerOverhead() * 1000.0);

    const std::vector<oo::Ref<OOTimeProfileEntry>>& profileEntries = _profileEntries;
    NSUInteger i, count = profileEntries.size();
    if (count != 0) {
        result += "\n                                                        NAME  T  COUNT    TOTAL     SELF  TOTAL%   SELF%  SELFMAX";
        for (i = 0; i < count; i++) {
            OOTimeProfileEntry* entry = profileEntries[i].get();

            double totalPc = entry->totalTimeSum() * 100.0 / totalTime;
            double selfPc = entry->selfTimeSum() * 100.0 / totalTime;

            result += oo::str::format("\n%60s  %c%7lu %8.2f %8.2f   %5.1f   %5.1f %8.2f",
                entry->function().value_or("(null)").c_str(),
                entry->isJavaScriptFrame() ? 'J' : 'N',
                (unsigned long)entry->hitCount(), entry->totalTimeSum() * 1000.0, entry->selfTimeSum() * 1000.0, totalPc, selfPc, entry->selfTimeMax() * 1000.0);
        }
    }

    return result;
}

double OOTimeProfile::totalTime()
{
    return _totalTime;
}

void OOTimeProfile::setTotalTime(double value)
{
    _totalTime = value;
}

double OOTimeProfile::javaScriptTime()
{
    return _totalTime - _nativeTime;
}

double OOTimeProfile::nativeTime()
{
    return _nativeTime;
}

void OOTimeProfile::setNativeTime(double value)
{
    _nativeTime = value;
}

double OOTimeProfile::extensionTime()
{
    return _extensionTime;
}

void OOTimeProfile::setExtensionTime(double value)
{
    _extensionTime = value;
}

double OOTimeProfile::nonExtensionTime()
{
    return _totalTime - _extensionTime;
}

double OOTimeProfile::profilerOverhead()
{
    return _profilerOverhead;
}

void OOTimeProfile::setProfilerOverhead(double value)
{
    _profilerOverhead = value;
}

std::vector<oo::Ref<OOTimeProfileEntry>> OOTimeProfile::profileEntries()
{
    return _profileEntries;
}

void OOTimeProfile::setProfileEntries(const std::vector<oo::Ref<OOTimeProfileEntry>>& value)
{
    _profileEntries = value;
}

JSValue OOTimeProfile::oo_jsValueInContext(JSContext* context)
{
    return OOJSValueFromPList(context, propertyListRepresentation());
}

oo::PList OOTimeProfile::propertyListRepresentation()
{
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

OOTimeProfileEntry::OOTimeProfileEntry(const char* name)
{
    OOCAssert(sProfiling, "Can't create profile entries while not profiling.");

    {
        if (name != NULL) {
            _function = std::string(name);
        }
    }
}


void OOTimeProfileEntry::addSampleWithTotalTime(OOTimeDelta totalTime, OOTimeDelta selfTime)
{
    _hitCount++;
    _totalTimeSum += totalTime;
    _selfTimeSum += selfTime;
    _totalTimeMax = fmax(_totalTimeMax, totalTime);
    _selfTimeMax = fmax(_selfTimeMax, selfTime);
}

std::optional<std::string> OOTimeProfileEntry::description()
{
    const char* function = _function.has_value() ? _function->c_str() : "(null)"; // as %@ printed nil
    if (_hitCount == 0)
        return oo::str::format("%s: --", function);

    // Convert everything to milliseconds.
    float totalTimeSum = _totalTimeSum * 1000.0;
    float selfTimeSum = _selfTimeSum * 1000.0;
    float totalTimeMax = _totalTimeMax * 1000.0;
    float selfTimeMax = _selfTimeMax * 1000.0;

    if (totalTimeSum == selfTimeSum && totalTimeMax == selfTimeMax) {
        if (_hitCount == 1) {
            return oo::str::format("%s: 1 time, %g ms", function, totalTimeSum);
        } else {
            return oo::str::format("%s: %lu times, total %g ms, avg %g ms, max %g ms", function, _hitCount, totalTimeSum, totalTimeSum / _hitCount, totalTimeMax);
        }
    } else {
        if (_hitCount == 1) {
            return oo::str::format("%s: 1 time, %g ms (self %g ms)", function, totalTimeSum, selfTimeSum);
        } else {
            return oo::str::format("%s: %lu times, total %g ms (self %g ms), avg %g ms (self %g ms), max %g ms, max self %g ms", function, _hitCount, totalTimeSum, selfTimeSum, totalTimeSum / _hitCount, selfTimeSum / _hitCount, totalTimeMax, selfTimeMax);
        }
    }
}

std::optional<std::string> OOTimeProfileEntry::function()
{
    return _function;
}

NSUInteger OOTimeProfileEntry::hitCount()
{
    return _hitCount;
}

double OOTimeProfileEntry::totalTimeSum()
{
    return _totalTimeSum;
}

double OOTimeProfileEntry::selfTimeSum()
{
    return _selfTimeSum;
}

double OOTimeProfileEntry::totalTimeAverage()
{
    return _hitCount ? (_totalTimeSum / _hitCount) : 0.0;
}

double OOTimeProfileEntry::selfTimeAverage()
{
    return _hitCount ? (_selfTimeSum / _hitCount) : 0.0;
}

double OOTimeProfileEntry::totalTimeMax()
{
    return _totalTimeMax;
}

double OOTimeProfileEntry::selfTimeMax()
{
    return _selfTimeMax;
}

bool OOTimeProfileEntry::isJavaScriptFrame()
{
    return false;
}

OOComparisonResult OOTimeProfileEntry::compareByTotalTime(OOTimeProfileEntry* other)
{
    return (OOComparisonResult)-compareByTotalTimeReverse(other);
}

OOComparisonResult OOTimeProfileEntry::compareByTotalTimeReverse(OOTimeProfileEntry* other)
{
    double selfTotal = totalTimeSum();
    double otherTotal = (other != nullptr) ? other->totalTimeSum() : 0.0; // (a message to nil gave 0)

    if (selfTotal < otherTotal)
        return OOOrderedDescending;
    if (selfTotal > otherTotal)
        return OOOrderedAscending;
    return OOOrderedSame;
}

OOComparisonResult OOTimeProfileEntry::compareBySelfTime(OOTimeProfileEntry* other)
{
    return (OOComparisonResult)-compareBySelfTimeReverse(other);
}

OOComparisonResult OOTimeProfileEntry::compareBySelfTimeReverse(OOTimeProfileEntry* other)
{
    double selfTotal = selfTimeSum();
    double otherTotal = (other != nullptr) ? other->selfTimeSum() : 0.0; // (a message to nil gave 0)

    if (selfTotal < otherTotal)
        return OOOrderedDescending;
    if (selfTotal > otherTotal)
        return OOOrderedAscending;
    return OOOrderedSame;
}

JSValue OOTimeProfileEntry::oo_jsValueInContext(JSContext* context)
{
    return OOJSValueFromPList(context, propertyListRepresentation());
}

oo::PList OOTimeProfileEntry::propertyListRepresentation()
{
    oo::PList::Dict result;
    // A nameless entry gave an empty dictionary: its nil name ended the object/key list.
    if (_function.has_value()) {
        result.emplace("name", oo::PList(*_function));
        result.emplace("hitCount", oo::PList::unsignedInteger(hitCount()));
        result.emplace("totalTimeSum", oo::PList(totalTimeSum()));
        result.emplace("selfTimeSum", oo::PList(selfTimeSum()));
        result.emplace("totalTimeAverage", oo::PList(totalTimeAverage()));
        result.emplace("selfTimeAverage", oo::PList(selfTimeAverage()));
        result.emplace("totalTimeMax", oo::PList(totalTimeMax()));
        result.emplace("selfTimeMax", oo::PList(selfTimeMax()));
        result.emplace("isJavaScriptFrame", oo::PList(static_cast<bool>(isJavaScriptFrame())));
    }
    return oo::PList(std::move(result));
}

#endif
