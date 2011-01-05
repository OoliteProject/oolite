/*

OOJSTimeManagement.m


Copyright (C) 2010-2011 Jens Ayton

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

#import "OOJavaScriptEngine.h"
#import "OOProfilingStopwatch.h"
#import "OOJSScript.h"
#import "OOCollectionExtractors.h"
#import "OOLoggingExtended.h"
#import <unistd.h>


#if OO_DEBUG
#define OOJS_DEBUG_LIMITER	1
#else
#define OOJS_DEBUG_LIMITER	0
#endif


static unsigned sLimiterStartDepth;
static int sLimiterPauseDepth;
static OOHighResTimeValue sLimiterStart;
static OOHighResTimeValue sLimiterPauseStart;
static double sLimiterTimeLimit;

#if !OO_NEW_JS
static unsigned long sBranchCount;
enum
{
	/*	Inverse proportion of BranchCallback calls on which we test the time
	 limit. Must be a power of two!
	 */
#if OOJS_DEBUG_LIMITER
	kMaxBranchCount = (1 << 8)	// 256
#else
	kMaxBranchCount = (1 << 18)	// 262144
#endif
};
#endif

#if OOJS_DEBUG_LIMITER
#define OOJS_TIME_LIMIT		(0.1)	// seconds
#else
#define OOJS_TIME_LIMIT		(1)	// seconds
#endif

#ifndef NDEBUG
static const char *sLastStartedFile;
static unsigned sLastStartedLine;
static const char *sLastStoppedFile;
static unsigned sLastStoppedLine;
#endif


#if OO_NEW_JS
static BOOL sStop = NO;
#endif


#ifndef NDEBUG
void OOJSStartTimeLimiterWithTimeLimit_(OOTimeDelta limit, const char *file, unsigned line)
#else
void OOJSStartTimeLimiterWithTimeLimit(OOTimeDelta limit)
#endif
{
	if (sLimiterStartDepth++ == 0)
	{
		if (limit <= 0.0)  limit = OOJS_TIME_LIMIT;
		sLimiterTimeLimit = limit;
		sLimiterPauseDepth = 0;
		
		OODisposeHighResTime(sLimiterStart);
		sLimiterStart = OOGetHighResTime();
	}
	
#ifndef NDEBUG
	sLastStartedFile = file;
	sLastStartedLine = line;
#endif
}


#ifndef NDEBUG
void OOJSStopTimeLimiter_(const char *file, unsigned line)
#else
void OOJSStopTimeLimiter(void)
#endif
{
#ifndef NDEBUG
	if (sLimiterStartDepth == 0)
	{
		OOLog(@"bug.javaScript.limiterDepth", @"Attempt to stop JavaScript time limiter while it is already fully stopped. This is an internal bug, please report it. (Last start: %@:%u, last valid stop: %@:%u, this stop attempt: %@:%u.)", OOLogAbbreviatedFileName(sLastStartedFile), sLastStartedLine, OOLogAbbreviatedFileName(sLastStoppedFile), sLastStoppedLine, OOLogAbbreviatedFileName(file), line);
		return;
	}
	
	sLastStoppedFile = file;
	sLastStoppedLine = line;
#endif
	
	if (--sLimiterStartDepth == 0)  sLimiterTimeLimit = 0.0;
}


void OOJSPauseTimeLimiter(void)
{
	if (sLimiterPauseDepth++ == 0)
	{
		OODisposeHighResTime(sLimiterPauseStart);
		sLimiterPauseStart = OOGetHighResTime();
	}
}


void OOJSResumeTimeLimiter(void)
{
	if (--sLimiterPauseDepth == 0)
		
	{
		OOHighResTimeValue now = OOGetHighResTime();
		OOTimeDelta elapsed = OOHighResTimeDeltaInSeconds(sLimiterPauseStart, now);
		OODisposeHighResTime(now);
		
		sLimiterTimeLimit += elapsed;
	}
}


#ifndef NDEBUG
OOHighResTimeValue OOJSCopyTimeLimiterNominalStartTime(void)
{
	return sLimiterStart;
}


void OOJSResetTimeLimiter(void)
{
	OODisposeHighResTime(sLimiterStart);
	sLimiterStart = OOGetHighResTime();
	
#if OO_NEW_JS
	sStop = NO;
#endif
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



#if OO_NEW_JS

enum
{
	kWatchdogTimerFrequency = (useconds_t)(OOJS_TIME_LIMIT * 1000000)	// Microseconds
};


@implementation OOJavaScriptEngine (WatchdogTimer)

- (void) watchdogTimerThread
{
	for (;;)
	{
#if OOLITE_WINDOWS
		// Apparently, there's no fine-grained sleep on Windows. Precision isn't all that important.
		sleep((OOJS_TIME_LIMIT > 1.0) ? OOJS_TIME_LIMIT : 1);
#else
		usleep(kWatchdogTimerFrequency);
#endif
		
		if (EXPECT(sLimiterStartDepth == 0 || sLimiterPauseDepth > 0))  continue;	// Most of the time, a script isn't running.
		
		// Note: if you add logging here, you need a manual autorelease pool.
		
		OOHighResTimeValue now = OOGetHighResTime();
		OOTimeDelta elapsed = OOHighResTimeDeltaInSeconds(sLimiterStart, now);
		OODisposeHighResTime(now);
		
		if (EXPECT_NOT(elapsed > sLimiterTimeLimit))
		{
			sStop = YES;
			JS_TriggerAllOperationCallbacks(runtime);
		}
	}
}

@end


static JSBool OperationCallback(JSContext *context)
{
	if (!sStop)  return YES;
	
    JS_ClearPendingException(context);
	
	OOHighResTimeValue now = OOGetHighResTime();
	OOTimeDelta elapsed = OOHighResTimeDeltaInSeconds(sLimiterStart, now);
	OODisposeHighResTime(now);
	
	OOLogERR(@"script.javaScript.timeLimit", @"Script \"%@\" ran for %g seconds and has been terminated.", [[OOJSScript currentlyRunningScript] name], elapsed);
#ifndef NDEBUG
	OOJSDumpStack(@"script.javaScript.stackTrace.timeLimit", context);
#endif
	
	// FIXME: we really should put something in the JS log here, but since that's implemented in JS there are complications.
	
	return NO;
}

#else

static JSBool BranchCallback(JSContext *context, JSScript *script)
{
	// This will be called a _lot_. Efficiency is important.
	if (EXPECT(sBranchCount++ & (kMaxBranchCount - 1)))
	{
		return YES;
	}
	
	// One in kMaxBranchCount calls, check if the timer has overflowed.
	sBranchCount = 0;
	
#ifndef NDEBUG
	if (sLimiterStartDepth == 0)
	{
		OOLog(@"bug.javaScript.limiterInactive", @"JavaScript branch callback hit while time limiter inactive. This is an internal error, please report it. bugs@oolite.org");
	}
#endif
	
	if (sLimiterPauseDepth > 0)  return YES;
	
	OOHighResTimeValue now = OOGetHighResTime();
	OOTimeDelta elapsed = OOHighResTimeDeltaInSeconds(sLimiterStart, now);
	OODisposeHighResTime(now);
	
	if (elapsed < sLimiterTimeLimit)  return YES;
	
    JS_ClearPendingException(context);
	
	OOLogERR(@"script.javaScript.timeLimit", @"Script \"%@\" ran for %g seconds and has been terminated.", [[OOJSScript currentlyRunningScript] name], elapsed);
#ifndef NDEBUG
	OOJSDumpStack(@"script.javaScript.stackTrace.timeLimit", context);
#endif
	
	// FIXME: we really should put something in the JS log here, but since that's implemented in JS there are complications.
	
	return NO;
}
#endif


static JSBool ContextCallback(JSContext *context, uintN contextOp)
{
	if (contextOp == JSCONTEXT_NEW)
	{
#if OO_NEW_JS
		JS_SetOperationCallback(context, OperationCallback);
#else
		JS_SetBranchCallback(context, BranchCallback);
#endif
	}
	return YES;
}


void OOJSTimeManagementInit(OOJavaScriptEngine *engine, JSRuntime *runtime)
{
#if OO_NEW_JS
	[NSThread detachNewThreadSelector:@selector(watchdogTimerThread)
							 toTarget:engine
						   withObject:nil];
#endif
	
	JS_SetContextCallback(runtime, ContextCallback);
}


#if OOJS_PROFILE

static BOOL						sProfiling = NO;
static OOJSProfileStackFrame	*sProfileStack = NULL;
static NSMapTable				*sProfileInfo;
static double					sProfilerOverhead;
static double					sProfilerTotalNativeTime;
static double					sProfilerEntryTimeLimit;
static OOHighResTimeValue		sProfilerStartTime;


@interface OOTimeProfile (Private)

- (void) setTotalTime:(double)value;
- (void) setNativeTime:(double)value;
- (void) setExtensionTime:(double)value;
- (void) setProfilerOverhead:(double)value;
- (void) setProfileEntries:(NSArray *)value;

- (NSDictionary *) propertyListRepresentation;

@end


@interface OOTimeProfileEntry (Private)

- (id) initWithCName:(const char *)name;

- (void) addSampleWithTotalTime:(OOTimeDelta)totalTime selfTime:(OOTimeDelta)selfTime;

- (NSDictionary *) propertyListRepresentation;

@end


void OOJSBeginProfiling(void)
{
	assert(sProfiling == NO);
	sProfiling = YES;
	sProfileInfo = NSCreateMapTable(NSNonOwnedPointerMapKeyCallBacks, NSObjectMapValueCallBacks, 100);
	sProfilerOverhead = 0.0;
	sProfilerTotalNativeTime = 0.0;
	sProfilerEntryTimeLimit = OOJSGetTimeLimiterLimit();
	
	// This should be last for precision.
	sProfilerStartTime = OOGetHighResTime();
}


OOTimeProfile *OOJSEndProfiling(void)
{
	// This should be at the top for precision.
	OOHighResTimeValue now = OOGetHighResTime();
	// Time limiter should be as close to outermost as practical.
	OOJSPauseTimeLimiter();
	
	assert(sProfiling && sProfileStack == NULL);
	
	sProfiling = NO;

	OOTimeProfile *result = [[OOTimeProfile alloc] init];
	
	[result setTotalTime:OOHighResTimeDeltaInSeconds(sProfilerStartTime, now)];
	[result setNativeTime:sProfilerTotalNativeTime];
	double currentTimeLimit = OOJSGetTimeLimiterLimit(); 
	[result setExtensionTime:currentTimeLimit - sProfilerEntryTimeLimit];
	[result setProfilerOverhead:sProfilerOverhead];
	
	[result setProfileEntries:[NSAllMapTableValues(sProfileInfo) sortedArrayUsingSelector:@selector(compareBySelfTimeReverse:)]];
	
	// Clean up.
	NSFreeMapTable(sProfileInfo);
	OODisposeHighResTime(sProfilerStartTime);
	
	OODisposeHighResTime(now);
	
	OOJSResumeTimeLimiter();
	return result;
}


BOOL OOJSIsProfiling(void)
{
	return sProfiling;
}


void OOJSProfileEnter(OOJSProfileStackFrame *frame, const char *function)
{
	if (EXPECT(!sProfiling))  return;
	
	*frame = (OOJSProfileStackFrame)
	{
		.back = sProfileStack,
		.function = function,
		.subTime = 0.0,
		.startTime = OOGetHighResTime()
	};
	sProfileStack = frame;
}


void OOJSProfileExit(OOJSProfileStackFrame *frame)
{
	if (EXPECT(!sProfiling))  return;
	
	OOHighResTimeValue now = OOGetHighResTime();
	NSAutoreleasePool *pool = [NSAutoreleasePool new];
	
	assert(frame == sProfileStack && frame != NULL);
	
	sProfileStack = frame->back;
	
	OOTimeProfileEntry *entry = NSMapGet(sProfileInfo, frame->function);
	if (entry == nil)
	{
		entry = [[OOTimeProfileEntry alloc] initWithCName:frame->function];
		NSMapInsertKnownAbsent(sProfileInfo, frame->function, entry);
		[entry release];
	}
	
	OOTimeDelta time = OOHighResTimeDeltaInSeconds(frame->startTime, now);
	OOTimeDelta selfTime = time - frame->subTime;
	[entry addSampleWithTotalTime:time selfTime:selfTime];
	
	sProfilerTotalNativeTime += selfTime;
	
	if (sProfileStack != NULL)  sProfileStack->subTime += time;
	
	[pool release];
	
	OODisposeHighResTime(frame->startTime);
	
	OOHighResTimeValue end = OOGetHighResTime();
	double currentOverhead = OOHighResTimeDeltaInSeconds(now, end);
	sProfilerOverhead += currentOverhead;
	
	/*	Equivalent of pausing/resuming time limiter, except that it guarantees
		excluded time will match profiler overhead if there are no other
		pauses happening.
	*/
	if (sLimiterPauseDepth == 0)  sLimiterTimeLimit += currentOverhead;
	
	OODisposeHighResTime(now);
	OODisposeHighResTime(end);
}


@implementation OOTimeProfile

- (void) dealloc
{
	DESTROY(_profileEntries);
	
	[super dealloc];
}


- (NSString *) description
{
	double totalTime = [self totalTime];
	
	NSMutableString *result = [NSMutableString stringWithFormat:
							  @"Total time: %g ms\n"
							   "JavaScript: %g ms, native: %g ms\n"
							   "Counted towards limit: %g ms, excluded: %g ms\n"
							   "Profiler overhead: %g ms",
							   totalTime * 1000.0,
							   [self javaScriptTime] * 1000.0, [self nativeTime] * 1000.0,
							   [self nonExtensionTime] * 1000.0, [self extensionTime] * 1000.0,
							   [self profilerOverhead] * 1000.0];
	
	NSArray *profileEntries = [self profileEntries];
	OOUInteger i, count = [profileEntries count];
	if (count != 0)
	{
		[result appendString:@"\n                                    NAME  COUNT    TOTAL     SELF  TOTAL%   SELF%  SELFMAX"];
		for (i = 0; i < count; i++)
		{
		//	[result appendFormat:@"\n    %@", [_profileEntries objectAtIndex:i]];
			
			OOTimeProfileEntry *entry = [profileEntries objectAtIndex:i];
			
			double totalPc = [entry totalTimeSum] * 100.0 / totalTime;
			double selfPc = [entry selfTimeSum] * 100.0 / totalTime;
			
			[result appendFormat:@"\n%40s%7lu %8.2f %8.2f   %5.1f   %5.1f %8.2f",
			 [[entry function] UTF8String],
			 (unsigned long)[entry hitCount], [entry totalTimeSum] * 1000.0, [entry selfTimeSum] * 1000.0, totalPc, selfPc, [entry selfTimeMax] * 1000.0];
		}
	}
	
	return result;
}


- (double) totalTime
{
	return _totalTime;
}


- (void) setTotalTime:(double)value
{
	_totalTime = value;
}


- (double) javaScriptTime
{
	return _totalTime - _nativeTime;
}


- (double) nativeTime
{
	return _nativeTime;
}


- (void) setNativeTime:(double)value
{
	_nativeTime = value;
}


- (double) extensionTime
{
	return _extensionTime;
}


- (void) setExtensionTime:(double)value
{
	_extensionTime = value;
}


- (double) nonExtensionTime
{
	return _totalTime - _extensionTime;
}


- (double) profilerOverhead
{
	return _profilerOverhead;
}


- (void) setProfilerOverhead:(double)value
{
	_profilerOverhead = value;
}


- (NSArray *) profileEntries
{
	return _profileEntries;
}


- (void) setProfileEntries:(NSArray *)value
{
	if (_profileEntries != value)
	{
		[_profileEntries release];
		_profileEntries = [value retain];
	}
}


- (jsval) oo_jsValueInContext:(JSContext *)context
{
	return [[self propertyListRepresentation] oo_jsValueInContext:context];
}


- (NSDictionary *) propertyListRepresentation
{
	NSArray *profileEntries = [self profileEntries];
	NSMutableArray *convertedEntries = [NSMutableArray arrayWithCapacity:[profileEntries count]];
	NSEnumerator *entryEnum = nil;
	OOTimeProfileEntry *entry = nil;
	for (entryEnum = [profileEntries objectEnumerator]; (entry = [entryEnum nextObject]); )
	{
		[convertedEntries addObject:[entry propertyListRepresentation]];
	}
	
	return [NSDictionary dictionaryWithObjectsAndKeys:
			profileEntries, @"profiles",
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

- (id) initWithCName:(const char *)name
{
	if ((self = [super init]))
	{
		_function = [[NSString alloc] initWithUTF8String:name];
	}
	
	return self;
}


- (void) dealloc
{
	DESTROY(_function);
	
	[super dealloc];
}


- (void) addSampleWithTotalTime:(OOTimeDelta)totalTime selfTime:(OOTimeDelta)selfTime
{
	_hitCount++;
	_totalTimeSum += totalTime;
	_selfTimeSum += selfTime;
	_totalTimeMax = OOMax_f(_totalTimeMax, totalTime);
	_selfTimeMax = OOMax_f(_selfTimeMax, selfTime);
}


- (NSString *) description
{
	if (_hitCount == 0)  return [NSString stringWithFormat:@"%@: --", _function];
	
	// Convert everything to milliseconds.
	float totalTimeSum = _totalTimeSum * 1000.0;
	float selfTimeSum = _selfTimeSum * 1000.0;
	float totalTimeMax = _totalTimeMax * 1000.0;
	float selfTimeMax = _selfTimeMax * 1000.0;
	
	if (totalTimeSum == selfTimeSum && totalTimeMax == selfTimeMax)
	{
		if (_hitCount == 1)
		{
			return [NSString stringWithFormat:@"%@: 1 time, %g ms", _function, totalTimeSum];
		}
		else
		{
			return [NSString stringWithFormat:@"%@: %lu times, total %g ms, avg %g ms, max %g ms", _function, _hitCount, totalTimeSum, totalTimeSum / _hitCount, totalTimeMax];
		}
	}
	else
	{
		if (_hitCount == 1)
		{
			return [NSString stringWithFormat:@"%@: 1 time, %g ms (self %g ms)", _function, totalTimeSum, selfTimeSum];
		}
		else
		{
			return [NSString stringWithFormat:@"%@: %lu times, total %g ms (self %g ms), avg %g ms (self %g ms), max %g ms, max self %g ms", _function, _hitCount, totalTimeSum, selfTimeSum, totalTimeSum / _hitCount, selfTimeSum / _hitCount, totalTimeMax, selfTimeMax];
		}
	}
}


- (NSString *) function
{
	return _function;
}


- (OOUInteger) hitCount
{
	return _hitCount;
}


- (double) totalTimeSum
{
	return _totalTimeSum;
}


- (double) selfTimeSum
{
	return _selfTimeSum;
}


- (double) totalTimeAverage
{
	return _hitCount ? (_totalTimeSum / _hitCount) : 0.0;
}


- (double) selfTimeAverage
{
	return _hitCount ? (_selfTimeSum / _hitCount) : 0.0;
}


- (double) totalTimeMax
{
	return _totalTimeMax;
}


- (double) selfTimeMax
{
	return _selfTimeMax;
}


- (NSComparisonResult) compareByTotalTime:(OOTimeProfileEntry *)other
{
	return -[self compareByTotalTimeReverse:other];
}


- (NSComparisonResult) compareByTotalTimeReverse:(OOTimeProfileEntry *)other
{
	double selfTotal = [self totalTimeSum];
	double otherTotal = [other totalTimeSum];
	
	if (selfTotal < otherTotal)  return NSOrderedDescending;
	if (selfTotal > otherTotal)  return NSOrderedAscending;
	return NSOrderedSame;
}


- (NSComparisonResult) compareBySelfTime:(OOTimeProfileEntry *)other
{
	return -[self compareBySelfTimeReverse:other];
}


- (NSComparisonResult) compareBySelfTimeReverse:(OOTimeProfileEntry *)other
{
	double selfTotal = [self selfTimeSum];
	double otherTotal = [other selfTimeSum];
	
	if (selfTotal < otherTotal)  return NSOrderedDescending;
	if (selfTotal > otherTotal)  return NSOrderedAscending;
	return NSOrderedSame;
}


- (jsval) oo_jsValueInContext:(JSContext *)context
{
	return [[self propertyListRepresentation] oo_jsValueInContext:context];
}


- (NSDictionary *) propertyListRepresentation
{
	return [NSDictionary dictionaryWithObjectsAndKeys:
			_function, @"name",
			[NSNumber numberWithUnsignedInt:[self hitCount]], @"hitCount",
			[NSNumber numberWithDouble:[self totalTimeSum]], @"totalTimeSum",
			[NSNumber numberWithDouble:[self selfTimeSum]], @"selfTimeSum",
			[NSNumber numberWithDouble:[self totalTimeAverage]], @"totalTimeAverage",
			[NSNumber numberWithDouble:[self selfTimeAverage]], @"selfTimeAverage",
			[NSNumber numberWithDouble:[self totalTimeMax]], @"totalTimeMax",
			[NSNumber numberWithDouble:[self selfTimeMax]], @"selfTimeMax",
			nil];
}

@end

#endif
