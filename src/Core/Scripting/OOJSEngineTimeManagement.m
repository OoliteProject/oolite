/*

OOJSTimeManagement.m


Copyright (C) 2010 Jens Ayton

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


#if 1 // OO_DEBUG
#define OOJS_DEBUG_LIMITER	1
#else
#define OOJS_DEBUG_LIMITER	0
#endif


static unsigned sLimiterStartDepth;
static int sLimiterPauseDepth;
static OOHighResTimeValue sLimiterStart;
static OOHighResTimeValue sLimiterPauseStart;
static double sLimiterTimeLimit;
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

#if OOJS_DEBUG_LIMITER
#define OOJS_TIME_LIMIT		(0.05)	// seconds
#else
#define OOJS_TIME_LIMIT		(0.25)	// seconds
#endif

#ifndef NDEBUG
static const char *sLastStartedFile;
static unsigned sLastStartedLine;
static const char *sLastStoppedFile;
static unsigned sLastStoppedLine;
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
	
	OOLogERR(@"script.javaScript.timeLimit", @"Script \"%@\" ran for %g seconds and has been terminated.", [[OOJSScript currentlyRunningScript] name], elapsed);
#ifndef NDEBUG
	OOJSDumpStack(@"script.javaScript.stackTrace.timeLimit", context);
#endif
	
	// FIXME: we really should put something in the JS log here, but since that's implemented in JS there are complications.
	
	return NO;
}


#if OOJS_PROFILE

static BOOL						sProfiling = NO;
static OOJSProfileStackFrame	*sProfileStack = NULL;
static NSMutableDictionary		*sProfileInfo;
static OOTimeDelta				sProfilerOverhead;
static OOTimeDelta				sProfilerTotalTime;


void OOJSBeginProfiling(void)
{
	assert(sProfiling == NO);
	sProfiling = YES;
	sProfileInfo = [[NSMutableDictionary alloc] init];
	sProfilerOverhead = 0.0;
	sProfilerTotalTime = 0.0;
}


NSDictionary *OOJSEndProfiling(void)
{
	OOJSPauseTimeLimiter();
	assert(sProfiling && sProfileStack == NULL);
	
	sProfiling = NO;
	NSMutableDictionary *result = [sProfileInfo autorelease];
	sProfileInfo = nil;
	[result oo_setFloat:sProfilerOverhead forKey:@"profiler overhead"];
	[result oo_setFloat:sProfilerTotalTime forKey:@"total native time"];
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
	
	OOHighResTimeValue now = OOGetHighResTime();
	
	assert(frame != NULL);
	
	*frame = (OOJSProfileStackFrame)
	{
		.back = sProfileStack,
		.function = function,
		.startTime = now,
		.subTime = 0.0
	};
	
	sProfileStack = frame;
}


void OOJSProfileExit(OOJSProfileStackFrame *frame)
{
	if (EXPECT(!sProfiling))  return;
	
	OOJSPauseTimeLimiter();
	OOHighResTimeValue now = OOGetHighResTime();
	NSAutoreleasePool *pool = [NSAutoreleasePool new];
	
	assert(frame == sProfileStack && frame != NULL);
	
	sProfileStack = frame->back;
	
	NSString *key = [NSString stringWithUTF8String:frame->function];
	NSMutableDictionary *entry = [sProfileInfo objectForKey:key];
	if (entry == nil)
	{
		entry = [NSMutableDictionary dictionaryWithCapacity:4];
		[sProfileInfo setObject:entry forKey:key];
	}
	
	OOTimeDelta time = OOHighResTimeDeltaInSeconds(frame->startTime, now);
	OOTimeDelta selfTime = time - frame->subTime;
	
	[entry oo_setFloat:[entry oo_doubleForKey:@"total"] + time forKey:@"total"];
	[entry oo_setFloat:[entry oo_doubleForKey:@"self"] + selfTime forKey:@"self"];
	[entry oo_setUnsignedInteger:[entry oo_unsignedIntegerForKey:@"count"] + 1 forKey:@"count"];
	
	sProfilerTotalTime += selfTime;
	
	if (sProfileStack != NULL)  sProfileStack->subTime += time;
	
	[pool release];
	
	OODisposeHighResTime(frame->startTime);
	
	OOHighResTimeValue end = OOGetHighResTime();
	sProfilerOverhead += OOHighResTimeDeltaInSeconds(now, end);
	
	OODisposeHighResTime(now);
	OODisposeHighResTime(end);
	
	OOJSResumeTimeLimiter();
}

#endif


JSBool OOJSContextCallback(JSContext *context, uintN contextOp)
{
	if (contextOp == JSCONTEXT_NEW)
	{
		JS_SetBranchCallback(context, BranchCallback);
	}
	return YES;
}
