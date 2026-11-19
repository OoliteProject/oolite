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

void OOJSTimeManagementInit(OOJavaScriptEngine* engine, JSRuntime* runtime)
{
    // The interrupt handler is installed by -[OOJavaScriptEngine init].
}

#if OOJS_PROFILE

static BOOL sProfiling = NO;
static BOOL sTracing = NO;
static OOJSProfileStackFrame* sProfileStack = NULL;
static NSMapTable* sProfileInfo;
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
static NSUInteger sProfiledFunctionCount;
static NSUInteger sProfiledFunctionCapacity;

static void FunctionCallHook(JSContext* context, JSValueConst function, const void* code, JSValueConst thisObj, int argc, JSValueConst* argv, bool entering, void* opaque);
#endif

@interface OOTimeProfile (Private)

- (void)setTotalTime:(double)value;
- (void)setNativeTime:(double)value;
- (void)setJavaScriptTime:(double)value;
- (void)setProfilerOverhead:(double)value;
- (void)setExtensionTime:(double)value;
- (void)setProfileEntries:(NSArray*)value;

- (NSDictionary*)propertyListRepresentation;

@end

@interface OOTimeProfileEntry (Private)

- (id)initWithCName:(const char*)name;
#if OOJS_QUICKJS_CALL_HOOK
- (id)initWithJSFunction:(JSValueConst)function context:(JSContext*)context;
#endif

- (void)addSampleWithTotalTime:(OOTimeDelta)totalTime selfTime:(OOTimeDelta)selfTime;

- (NSDictionary*)propertyListRepresentation;

@end

void OOJSBeginProfiling(BOOL trace)
{
    assert(sProfiling == NO);
    sProfiling = YES;
    sTracing = trace;
    sProfileInfo = NSCreateMapTable(NSNonOwnedPointerMapKeyCallBacks, NSObjectMapValueCallBacks, 100);
    sProfilerOverhead = 0.0;
    sProfilerTotalNativeTime = 0.0;
    sProfilerEntryTimeLimit = OOJSGetTimeLimiterLimit();

#if OOJS_QUICKJS_CALL_HOOK
    sProfilerTotalJavaScriptTime = 0.0;
    sProfiledFunctionCount = 0;
    JSContext* context = OOJSAcquireContext();
    JS_SetFunctionCallHook(JS_GetRuntime(context), FunctionCallHook, NULL);
    OOJSRelinquishContext(context);
#endif

    // This should be last for precision.
    sProfilerStartTime = OOGetHighResTime();

    if (trace) {
        OOLog(@"script.javaScript.trace", @"%@", @">>>> Beginning trace.");
        OOLogIndent();
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
#if OOJS_QUICKJS_CALL_HOOK
    [result setJavaScriptTime:sProfilerTotalJavaScriptTime];
#else
    [result setJavaScriptTime:[result totalTime] - sProfilerTotalNativeTime];
#endif
    [result setProfilerOverhead:sProfilerOverhead];

    double currentTimeLimit = OOJSGetTimeLimiterLimit();
    [result setExtensionTime:currentTimeLimit - sProfilerEntryTimeLimit];

    [result setProfileEntries:[NSAllMapTableValues(sProfileInfo) sortedArrayUsingSelector:@selector(compareBySelfTimeReverse:)]];

    if (sTracing) {
        OOLogOutdent();
        OOLog(@"script.javaScript.trace", @"%@", @"<<<< End of trace.");
        sTracing = NO;
    }

    // Clean up.
#if OOJS_QUICKJS_CALL_HOOK
    JSContext* context = OOJSAcquireContext();
    JS_SetFunctionCallHook(JS_GetRuntime(context), NULL, NULL);
    for (NSUInteger i = 0; i < sProfiledFunctionCount; i++) {
        JS_FreeValue(context, sProfiledFunctions[i]);
    }
    sProfiledFunctionCount = 0;
    OOJSRelinquishContext(context);
#endif

    NSFreeMapTable(sProfileInfo);
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

#if OOJS_QUICKJS_CALL_HOOK
static void CleanUpJSFrame(OOJSProfileStackFrame* frame)
{
    OODisposeHighResTime(frame->startTime);
    free(frame);
}

static void HoldProfiledFunction(JSContext* context, JSValueConst function)
{
    if (sProfiledFunctionCount == sProfiledFunctionCapacity) {
        sProfiledFunctionCapacity = sProfiledFunctionCapacity ? sProfiledFunctionCapacity * 2 : 64;
        sProfiledFunctions = (JSValue*)realloc(sProfiledFunctions, sProfiledFunctionCapacity * sizeof *sProfiledFunctions);
        assert(sProfiledFunctions != NULL);
    }
    sProfiledFunctions[sProfiledFunctionCount++] = JS_DupValue(context, function);
}

static void TraceEnterJSFunction(JSContext* context, JSValueConst thisObj, int argc, JSValueConst* argv, OOTimeProfileEntry* profileEntry)
{
    NSMutableString* name = [NSMutableString stringWithFormat:@"%@(", [profileEntry function]];

    // Temporarily disable profiling as we'll call out to profiled functions to get value descriptions.
    sProfiling = NO;

    BOOL first = YES;
    if (!JS_IsUndefined(thisObj)) {
        [name appendFormat:@"this: %@", OOJSDescribeValue(context, thisObj, YES)];
        first = NO;
    }
    for (int i = 0; i < argc; i++) {
        if (!first)
            [name appendString:@", "];
        else
            first = NO;
        [name appendString:OOJSDescribeValue(context, argv[i], YES)];
    }

    sProfiling = YES;

    [name appendString:@")"];
    OOLog(@"script.javaScript.trace.JS", @">> %@ [JS]", name);
    OOLogIndent();
}

static void FunctionCallHook(JSContext* context, JSValueConst function, const void* code, JSValueConst thisObj, int argc, JSValueConst* argv, bool entering, void* opaque)
{
    if (EXPECT(!sProfiling))
        return;

    OOHighResTimeValue start = OOGetHighResTime();
    BOOL startOwnedByFrame = NO;

    NSAutoreleasePool* pool = [NSAutoreleasePool new];

    if (entering) {
        // Create profile entry up front so we can shove the JS function in it.
        OOTimeProfileEntry* entry = (OOTimeProfileEntry*)NSMapGet(sProfileInfo, code);
        if (entry == nil) {
            entry = [[OOTimeProfileEntry alloc] initWithJSFunction:function context:context];
            NSMapInsertKnownAbsent(sProfileInfo, code, entry);
            [entry release];
            HoldProfiledFunction(context, function);
        }

        if (EXPECT_NOT(sTracing)) {
            // We use EXPECT_NOT here because profiles are time-critical and traces are not.
            TraceEnterJSFunction(context, thisObj, argc, argv, entry);
        }

        // Make a stack frame on the heap.
        OOJSProfileStackFrame* frame = (OOJSProfileStackFrame*)malloc(sizeof(OOJSProfileStackFrame));
        assert(frame != NULL);

        *frame = (OOJSProfileStackFrame) {
            .back = sProfileStack,
            .key = code,
            .startTime = start,
            .subTime = 0.0,
            .total = &sProfilerTotalJavaScriptTime,
            .cleanup = CleanUpJSFrame
        };

        sProfileStack = frame;
        startOwnedByFrame = YES;
    } else if (sProfileStack != NULL && sProfileStack->cleanup == CleanUpJSFrame && sProfileStack->key == code) {
        // Exiting. A frame entered before profiling started is not on the profile stack.
        UpdateProfileForFrame(start, sProfileStack);
    }

    [pool release];

    OOHighResTimeValue end = OOGetHighResTime();
    double currentOverhead = OOHighResTimeDeltaInSeconds(start, end);
    sProfilerOverhead += currentOverhead;
    OOJSExcludeTimeFromLimiter(currentOverhead);
    if (!startOwnedByFrame)
        OODisposeHighResTime(start);
    OODisposeHighResTime(end);
}
#endif

void OOJSProfileEnter(OOJSProfileStackFrame* frame, const char* function)
{
    if (EXPECT(!sProfiling))
        return;
    if (EXPECT_NOT(sTracing)) {
        // We use EXPECT_NOT here because profiles are time-critical and traces are not.
        OOLog(@"script.javaScript.trace.ON", @">> %s [ON]", function);
        OOLogIndent();
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

    OOTimeProfileEntry* entry = (OOTimeProfileEntry*)NSMapGet(sProfileInfo, frame->key);
    if (entry == nil) {
        entry = [[OOTimeProfileEntry alloc] initWithCName:frame->function];
        NSMapInsertKnownAbsent(sProfileInfo, frame->key, entry);
        [entry release];
    }

    OOTimeDelta time = OOHighResTimeDeltaInSeconds(frame->startTime, now);
    OOTimeDelta selfTime = time - frame->subTime;
    [entry addSampleWithTotalTime:time selfTime:selfTime];

    *(frame->total) += selfTime;
    if (sProfileStack != NULL)
        sProfileStack->subTime += time;

    if (frame->cleanup != NULL)
        frame->cleanup(frame);

    if (EXPECT_NOT(sTracing))
        OOLogOutdent();
}

@implementation OOTimeProfile

- (void)dealloc
{
    DESTROY(_profileEntries);

    [super dealloc];
}

- (NSString*)description
{
    double totalTime = [self totalTime];

    NSMutableString* result = [NSMutableString stringWithFormat:
            @"Total time: %g ms\n"
             "JavaScript: %g ms, native: %g ms\n"
             "Counted towards limit: %g ms, excluded: %g ms\n"
             "Profiler overhead: %g ms",
        totalTime * 1000.0,
        [self javaScriptTime] * 1000.0, [self nativeTime] * 1000.0,
        [self nonExtensionTime] * 1000.0, [self extensionTime] * 1000.0,
        [self profilerOverhead] * 1000.0];

    NSArray* profileEntries = [self profileEntries];
    NSUInteger i, count = [profileEntries count];
    if (count != 0) {
        [result appendString:@"\n                                                        NAME  T  COUNT    TOTAL     SELF  TOTAL%   SELF%  SELFMAX"];
        for (i = 0; i < count; i++) {
            OOTimeProfileEntry* entry = [profileEntries objectAtIndex:i];

            double totalPc = [entry totalTimeSum] * 100.0 / totalTime;
            double selfPc = [entry selfTimeSum] * 100.0 / totalTime;

            [result appendFormat:@"\n%60s  %c%7lu %8.2f %8.2f   %5.1f   %5.1f %8.2f",
                [[entry function] UTF8String],
                [entry isJavaScriptFrame] ? 'J' : 'N',
                (unsigned long)[entry hitCount], [entry totalTimeSum] * 1000.0, [entry selfTimeSum] * 1000.0, totalPc, selfPc, [entry selfTimeMax] * 1000.0];
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
    return _javaScriptTime;
}

- (void)setJavaScriptTime:(double)value
{
    _javaScriptTime = value;
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

- (NSArray*)profileEntries
{
    return _profileEntries;
}

- (void)setProfileEntries:(NSArray*)value
{
    if (_profileEntries != value) {
        [_profileEntries release];
        _profileEntries = [value retain];
    }
}

- (JSValue)oo_jsValueInContext:(JSContext*)context
{
    return OOJSValueFromNativeObject(context, [self propertyListRepresentation]);
}

- (NSDictionary*)propertyListRepresentation
{
    NSArray* profileEntries = [self profileEntries];
    NSMutableArray* convertedEntries = [NSMutableArray arrayWithCapacity:[profileEntries count]];
    OOTimeProfileEntry* entry = nil;
    foreach (entry, profileEntries) {
        [convertedEntries addObject:[entry propertyListRepresentation]];
    }

    return [NSDictionary dictionaryWithObjectsAndKeys:
            convertedEntries, @"profiles",
        [NSNumber numberWithDouble:[self totalTime]], @"totalTime",
        [NSNumber numberWithDouble:[self javaScriptTime]], @"javaScriptTime",
        [NSNumber numberWithDouble:[self nativeTime]], @"nativeTime",
        [NSNumber numberWithDouble:[self extensionTime]], @"extensionTime",
        [NSNumber numberWithDouble:[self nonExtensionTime]], @"nonExtensionTime",
        [NSNumber numberWithDouble:[self profilerOverhead]], @"profilerOverhead",
        nil];
}

@end

@implementation OOTimeProfileEntry

- (id)initWithCName:(const char*)name
{
    NSAssert(sProfiling, @"Can't create profile entries while not profiling.");

    if ((self = [super init])) {
        if (name != NULL) {
            _function = [[NSString stringWithUTF8String:name] retain];
        }
    }

    return self;
}

#if OOJS_QUICKJS_CALL_HOOK
- (id)initWithJSFunction:(JSValueConst)function context:(JSContext*)context
{
    if ((self = [self initWithCName:NULL])) {
        // Temporarily disable profiling so we don't profile the profiler while it's profiling the profilee.
        sProfiling = NO;
        _isJavaScriptFrame = YES;

        JSAtom nameAtom, fileAtom;
        int line;
        NSString* funcName = nil;
        NSString* location = nil;
        if (JS_GetFunctionInfo(context, function, &nameAtom, &fileAtom, &line)) {
            if (nameAtom != JS_ATOM_NULL) {
                funcName = OOStringFromJSID(nameAtom);
                JS_FreeAtom(context, nameAtom);
            }
            if (fileAtom != JS_ATOM_NULL) {
                location = [NSString stringWithFormat:@"%@:%i", OOStringFromJSID(fileAtom), line];
                JS_FreeAtom(context, fileAtom);
            }
        }
        if ([funcName length] == 0)
            funcName = @"<anonymous>";

        if (location != nil) {
            _function = [[NSString alloc] initWithFormat:@"(%@) %@", location, funcName];
        } else
            _function = [funcName retain];

        sProfiling = YES;
    }

    return self;
}
#endif

- (void)dealloc
{
    DESTROY(_function);

    [super dealloc];
}

- (void)addSampleWithTotalTime:(OOTimeDelta)totalTime selfTime:(OOTimeDelta)selfTime
{
    _hitCount++;
    _totalTimeSum += totalTime;
    _selfTimeSum += selfTime;
    _totalTimeMax = fmax(_totalTimeMax, totalTime);
    _selfTimeMax = fmax(_selfTimeMax, selfTime);
}

- (NSString*)description
{
    if (_hitCount == 0)
        return [NSString stringWithFormat:@"%@: --", _function];

    // Convert everything to milliseconds.
    float totalTimeSum = _totalTimeSum * 1000.0;
    float selfTimeSum = _selfTimeSum * 1000.0;
    float totalTimeMax = _totalTimeMax * 1000.0;
    float selfTimeMax = _selfTimeMax * 1000.0;

    if (totalTimeSum == selfTimeSum && totalTimeMax == selfTimeMax) {
        if (_hitCount == 1) {
            return [NSString stringWithFormat:@"%@: 1 time, %g ms", _function, totalTimeSum];
        } else {
            return [NSString stringWithFormat:@"%@: %lu times, total %g ms, avg %g ms, max %g ms", _function, _hitCount, totalTimeSum, totalTimeSum / _hitCount, totalTimeMax];
        }
    } else {
        if (_hitCount == 1) {
            return [NSString stringWithFormat:@"%@: 1 time, %g ms (self %g ms)", _function, totalTimeSum, selfTimeSum];
        } else {
            return [NSString stringWithFormat:@"%@: %lu times, total %g ms (self %g ms), avg %g ms (self %g ms), max %g ms, max self %g ms", _function, _hitCount, totalTimeSum, selfTimeSum, totalTimeSum / _hitCount, selfTimeSum / _hitCount, totalTimeMax, selfTimeMax];
        }
    }
}

- (NSString*)function
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
    return _isJavaScriptFrame;
}

- (NSComparisonResult)compareByTotalTime:(OOTimeProfileEntry*)other
{
    return (NSComparisonResult)-[self compareByTotalTimeReverse:other];
}

- (NSComparisonResult)compareByTotalTimeReverse:(OOTimeProfileEntry*)other
{
    double selfTotal = [self totalTimeSum];
    double otherTotal = [other totalTimeSum];

    if (selfTotal < otherTotal)
        return NSOrderedDescending;
    if (selfTotal > otherTotal)
        return NSOrderedAscending;
    return NSOrderedSame;
}

- (NSComparisonResult)compareBySelfTime:(OOTimeProfileEntry*)other
{
    return (NSComparisonResult)-[self compareBySelfTimeReverse:other];
}

- (NSComparisonResult)compareBySelfTimeReverse:(OOTimeProfileEntry*)other
{
    double selfTotal = [self selfTimeSum];
    double otherTotal = [other selfTimeSum];

    if (selfTotal < otherTotal)
        return NSOrderedDescending;
    if (selfTotal > otherTotal)
        return NSOrderedAscending;
    return NSOrderedSame;
}

- (JSValue)oo_jsValueInContext:(JSContext*)context
{
    return OOJSValueFromNativeObject(context, [self propertyListRepresentation]);
}

- (NSDictionary*)propertyListRepresentation
{
    return [NSDictionary dictionaryWithObjectsAndKeys:
            _function, @"name",
        [NSNumber numberWithUnsignedInteger:[self hitCount]], @"hitCount",
        [NSNumber numberWithDouble:[self totalTimeSum]], @"totalTimeSum",
        [NSNumber numberWithDouble:[self selfTimeSum]], @"selfTimeSum",
        [NSNumber numberWithDouble:[self totalTimeAverage]], @"totalTimeAverage",
        [NSNumber numberWithDouble:[self selfTimeAverage]], @"selfTimeAverage",
        [NSNumber numberWithDouble:[self totalTimeMax]], @"totalTimeMax",
        [NSNumber numberWithDouble:[self selfTimeMax]], @"selfTimeMax",
        [NSNumber numberWithBool:[self isJavaScriptFrame]], @"isJavaScriptFrame",
        nil];
}

@end

#endif
