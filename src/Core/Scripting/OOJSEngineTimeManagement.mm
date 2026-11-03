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

void OOJSTimeManagementInit(OOJavaScriptEngine* engine, JSRuntime* runtime)
{
    // The interrupt handler is installed by -[OOJavaScriptEngine init].
}

#if OOJS_PROFILE

static BOOL sProfiling = NO;
static BOOL sTracing = NO;
static OOJSProfileStackFrame* sProfileStack = NULL;
// Profile key (native name or JS function, by pointer) -> entry, retained. Was a map table with
// non-owned pointer keys and retained object values (bead oo-3rb.20).
static std::unordered_map<const void*, OOTimeProfileEntry*>* sProfileInfo;

static OOTimeProfileEntry* ProfileEntryForKey(const void* key)
{
    auto found = sProfileInfo->find(key);
    return (found != sProfileInfo->end()) ? found->second : nil;
}
static double sProfilerOverhead;
static double sProfilerTotalNativeTime;
static double sProfilerEntryTimeLimit;
static OOHighResTimeValue sProfilerStartTime;

@interface OOTimeProfile (Private)

- (void)setTotalTime:(double)value;
- (void)setNativeTime:(double)value;
- (void)setProfilerOverhead:(double)value;
- (void)setExtensionTime:(double)value;
- (void)setProfileEntries:(const std::vector<oo::ObjCRef<OOTimeProfileEntry*>>&)value;

- (oo::PList)propertyListRepresentation;

@end

@interface OOTimeProfileEntry (Private)

- (id)initWithCName:(const char*)name;

- (void)addSampleWithTotalTime:(OOTimeDelta)totalTime selfTime:(OOTimeDelta)selfTime;

- (oo::PList)propertyListRepresentation;

@end

void OOJSBeginProfiling(BOOL trace)
{
    assert(sProfiling == NO);
    sProfiling = YES;
    sTracing = trace;
    sProfileInfo = new std::unordered_map<const void*, OOTimeProfileEntry*>;
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

OOTimeProfile* OOJSEndProfiling(void)
{
    // This should be at the top for precision.
    OOHighResTimeValue now = OOGetHighResTime();
    // Time limiter should be as close to outermost as practical.
    OOJSPauseTimeLimiter();

    assert(sProfiling && sProfileStack == NULL);

    sProfiling = NO;

    OOTimeProfile* result = [[OOTimeProfile alloc] init];

    [result setTotalTime:OOHighResTimeDeltaInSeconds(sProfilerStartTime, now)];
    [result setNativeTime:sProfilerTotalNativeTime];
    [result setProfilerOverhead:sProfilerOverhead];

    double currentTimeLimit = OOJSGetTimeLimiterLimit();
    [result setExtensionTime:currentTimeLimit - sProfilerEntryTimeLimit];

    std::vector<oo::ObjCRef<OOTimeProfileEntry*>> entries;
    entries.reserve(sProfileInfo->size());
    for (const auto& keyAndEntry : *sProfileInfo)
        entries.emplace_back(keyAndEntry.second);
    std::stable_sort(entries.begin(), entries.end(), [](const auto& a, const auto& b) { return [a.get() compareBySelfTimeReverse:b.get()] == OOOrderedAscending; });
    [result setProfileEntries:entries];

    if (sTracing) {
        oo::log::outdent();
        OO_LOG("script.javaScript.trace", "{}", "<<<< End of trace.");
        sTracing = NO;
    }

    // Clean up.
    for (const auto& keyAndEntry : *sProfileInfo)
        [keyAndEntry.second release];
    delete sProfileInfo;
    sProfileInfo = NULL;
    OODisposeHighResTime(sProfilerStartTime);

    OODisposeHighResTime(now);

    OOJSResumeTimeLimiter();
    return [result autorelease];
}

BOOL OOJSIsProfiling(void)
{
    return sProfiling;
}

static void UpdateProfileForFrame(OOHighResTimeValue now, OOJSProfileStackFrame* frame);

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
        BOOL done = NO;

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

static void UpdateProfileForFrame(OOHighResTimeValue now, OOJSProfileStackFrame* frame)
{
    sProfileStack = frame->back;

    OOTimeProfileEntry* entry = ProfileEntryForKey(frame->key);
    if (entry == nil) {
        entry = [[OOTimeProfileEntry alloc] initWithCName:frame->function];
        (*sProfileInfo)[frame->key] = entry; // the table's reference
    }

    OOTimeDelta time = OOHighResTimeDeltaInSeconds(frame->startTime, now);
    OOTimeDelta selfTime = time - frame->subTime;
    [entry addSampleWithTotalTime:time selfTime:selfTime];

    *(frame->total) += selfTime;
    if (sProfileStack != NULL)
        sProfileStack->subTime += time;

    if (EXPECT_NOT(sTracing))
        oo::log::outdent();
}

@implementation OOTimeProfile

- (std::optional<std::string>)cxx_description
{
    double totalTime = [self totalTime];

    std::string result = oo::str::format(
        "Total time: %g ms\n"
        "JavaScript: %g ms, native: %g ms\n"
        "Counted towards limit: %g ms, excluded: %g ms\n"
        "Profiler overhead: %g ms",
        totalTime * 1000.0,
        [self javaScriptTime] * 1000.0, [self nativeTime] * 1000.0,
        [self nonExtensionTime] * 1000.0, [self extensionTime] * 1000.0,
        [self profilerOverhead] * 1000.0);

    const std::vector<oo::ObjCRef<OOTimeProfileEntry*>>& profileEntries = _profileEntries;
    NSUInteger i, count = profileEntries.size();
    if (count != 0) {
        result += "\n                                                        NAME  T  COUNT    TOTAL     SELF  TOTAL%   SELF%  SELFMAX";
        for (i = 0; i < count; i++) {
            OOTimeProfileEntry* entry = profileEntries[i].get();

            double totalPc = [entry totalTimeSum] * 100.0 / totalTime;
            double selfPc = [entry selfTimeSum] * 100.0 / totalTime;

            result += oo::str::format("\n%60s  %c%7lu %8.2f %8.2f   %5.1f   %5.1f %8.2f",
                [entry cxx_function].value_or("(null)").c_str(),
                [entry isJavaScriptFrame] ? 'J' : 'N',
                (unsigned long)[entry hitCount], [entry totalTimeSum] * 1000.0, [entry selfTimeSum] * 1000.0, totalPc, selfPc, [entry selfTimeMax] * 1000.0);
        }
    }

    return result;
}

- (double)totalTime
{
    return _totalTime;
}

- (void)setTotalTime:(double)value
{
    _totalTime = value;
}

- (double)javaScriptTime
{
    return _totalTime - _nativeTime;
}

- (double)nativeTime
{
    return _nativeTime;
}

- (void)setNativeTime:(double)value
{
    _nativeTime = value;
}

- (double)extensionTime
{
    return _extensionTime;
}

- (void)setExtensionTime:(double)value
{
    _extensionTime = value;
}

- (double)nonExtensionTime
{
    return _totalTime - _extensionTime;
}

- (double)profilerOverhead
{
    return _profilerOverhead;
}

- (void)setProfilerOverhead:(double)value
{
    _profilerOverhead = value;
}

- (std::vector<oo::ObjCRef<OOTimeProfileEntry*>>)profileEntries
{
    return _profileEntries;
}

- (void)setProfileEntries:(const std::vector<oo::ObjCRef<OOTimeProfileEntry*>>&)value
{
    _profileEntries = value;
}

- (JSValue)oo_jsValueInContext:(JSContext*)context
{
    return OOJSValueFromPList(context, [self propertyListRepresentation]);
}

- (oo::PList)propertyListRepresentation
{
    // "profiles" holds each entry's own property list.
    oo::PList::Array profiles;
    profiles.reserve(_profileEntries.size());
    for (const auto& entry : _profileEntries)
        profiles.push_back([entry.get() propertyListRepresentation]);

    oo::PList::Dict result;
    result.emplace("profiles", oo::PList(std::move(profiles)));
    result.emplace("totalTime", oo::PList([self totalTime]));
    result.emplace("javaScriptTime", oo::PList([self javaScriptTime]));
    result.emplace("nativeTime", oo::PList([self nativeTime]));
    result.emplace("extensionTime", oo::PList([self extensionTime]));
    result.emplace("nonExtensionTime", oo::PList([self nonExtensionTime]));
    result.emplace("profilerOverhead", oo::PList([self profilerOverhead]));
    return oo::PList(std::move(result));
}

@end

@implementation OOTimeProfileEntry

- (id)initWithCName:(const char*)name
{
    OOAssert(sProfiling, "Can't create profile entries while not profiling.");

    if ((self = [super init])) {
        if (name != NULL) {
            _function = std::string(name);
        }
    }

    return self;
}

- (void)addSampleWithTotalTime:(OOTimeDelta)totalTime selfTime:(OOTimeDelta)selfTime
{
    _hitCount++;
    _totalTimeSum += totalTime;
    _selfTimeSum += selfTime;
    _totalTimeMax = fmax(_totalTimeMax, totalTime);
    _selfTimeMax = fmax(_selfTimeMax, selfTime);
}

- (std::optional<std::string>)cxx_description
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

- (std::optional<std::string>)cxx_function
{
    return _function;
}

- (NSUInteger)hitCount
{
    return _hitCount;
}

- (double)totalTimeSum
{
    return _totalTimeSum;
}

- (double)selfTimeSum
{
    return _selfTimeSum;
}

- (double)totalTimeAverage
{
    return _hitCount ? (_totalTimeSum / _hitCount) : 0.0;
}

- (double)selfTimeAverage
{
    return _hitCount ? (_selfTimeSum / _hitCount) : 0.0;
}

- (double)totalTimeMax
{
    return _totalTimeMax;
}

- (double)selfTimeMax
{
    return _selfTimeMax;
}

- (BOOL)isJavaScriptFrame
{
    return NO;
}

- (OOComparisonResult)compareByTotalTime:(OOTimeProfileEntry*)other
{
    return (OOComparisonResult)-[self compareByTotalTimeReverse:other];
}

- (OOComparisonResult)compareByTotalTimeReverse:(OOTimeProfileEntry*)other
{
    double selfTotal = [self totalTimeSum];
    double otherTotal = [other totalTimeSum];

    if (selfTotal < otherTotal)
        return OOOrderedDescending;
    if (selfTotal > otherTotal)
        return OOOrderedAscending;
    return OOOrderedSame;
}

- (OOComparisonResult)compareBySelfTime:(OOTimeProfileEntry*)other
{
    return (OOComparisonResult)-[self compareBySelfTimeReverse:other];
}

- (OOComparisonResult)compareBySelfTimeReverse:(OOTimeProfileEntry*)other
{
    double selfTotal = [self selfTimeSum];
    double otherTotal = [other selfTimeSum];

    if (selfTotal < otherTotal)
        return OOOrderedDescending;
    if (selfTotal > otherTotal)
        return OOOrderedAscending;
    return OOOrderedSame;
}

- (JSValue)oo_jsValueInContext:(JSContext*)context
{
    return OOJSValueFromPList(context, [self propertyListRepresentation]);
}

- (oo::PList)propertyListRepresentation
{
    oo::PList::Dict result;
    // A nameless entry gave an empty dictionary: its nil name ended the object/key list.
    if (_function.has_value()) {
        result.emplace("name", oo::PList(*_function));
        result.emplace("hitCount", oo::PList::unsignedInteger([self hitCount]));
        result.emplace("totalTimeSum", oo::PList([self totalTimeSum]));
        result.emplace("selfTimeSum", oo::PList([self selfTimeSum]));
        result.emplace("totalTimeAverage", oo::PList([self totalTimeAverage]));
        result.emplace("selfTimeAverage", oo::PList([self selfTimeAverage]));
        result.emplace("totalTimeMax", oo::PList([self totalTimeMax]));
        result.emplace("selfTimeMax", oo::PList([self selfTimeMax]));
        result.emplace("isJavaScriptFrame", oo::PList(static_cast<bool>([self isJavaScriptFrame])));
    }
    return oo::PList(std::move(result));
}

@end

#endif
