/*

OOJSTimeManagement.h

Functionality related to time limiting and profiling of JavaScript code.


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


#import "jsapi.h"


/*	Time limiter
	
	The time limiter stops scripts from running an arbitrarily long time.
	
	The time limiter must be started before calling into JavaScript code.
	Calls to OOJSStartTimeLimiter() and OOJSStopTimeLimiter() must be balanced,
	and may be nested.
	OOJSStartTimeLimiterWithTimeLimit() is like OOJSStartTimeLimiter(), but
	specifies a custom time limit. This limit is only used if the limiter is
	actually stopped.
	
	The time limiter can be paused and resumed for native operations that are
	known to be slow. OOJSPauseTimeLimiter() and OOJSResumeTimeLimiter() must
	be balanced and can be nested, but the nest count may be negative - it is
	valid to call OOJSResumeTimeLimiter() followed by OOJSPauseTimeLimiter().
*/
#define OOJSStartTimeLimiter()  OOJSStartTimeLimiterWithTimeLimit(0.0)

#ifndef NDEBUG
#define OOJSStartTimeLimiterWithTimeLimit(limit)  OOJSStartTimeLimiterWithTimeLimit_(limit, OOLOG_FILE_NAME, __LINE__)
#define OOJSStopTimeLimiter()  OOJSStopTimeLimiter_(OOLOG_FILE_NAME, __LINE__)
void OOJSStartTimeLimiterWithTimeLimit_(OOTimeDelta limit, const char *file, unsigned line);
void OOJSStopTimeLimiter_(const char *file, unsigned line);
#else
void OOJSStartTimeLimiterWithTimeLimit(OOTimeDelta limit);
void OOJSStopTimeLimiter(void);
#endif

void OOJSPauseTimeLimiter(void);
void OOJSResumeTimeLimiter(void);


#define kOOJSLongTimeLimit (2.0)


#ifndef OOJS_PROFILE
#define OOJS_PROFILE (!defined(NDEBUG) && OOLITE_NATIVE_EXCEPTIONS)
#endif

#if OOJS_PROFILE
#import "OOProfilingStopwatch.h"

/*
	Profiling support.
	
	OOJSCopyTimeLimiterNominalStartTime()
	Copy the nominal start time for the time limiter. This is the actual time
	with any time extensions (paused periods) added in.
	
	OOJSResetTimeLimiter()
	Set the time limiter start time to now.
	
	OOJSGetTimeLimiterLimit()
	OOJSSetTimeLimiterLimit()
	Manipulate the timeout.
*/


@class OOTimeProfile, OOTimeProfileEntry;


void OOJSBeginProfiling(void);
OOTimeProfile *OOJSEndProfiling(void);
BOOL OOJSIsProfiling(void);

OOHighResTimeValue OOJSCopyTimeLimiterNominalStartTime(void);

void OOJSResetTimeLimiter(void);
OOTimeDelta OOJSGetTimeLimiterLimit(void);
void OOJSSetTimeLimiterLimit(OOTimeDelta limit);


typedef struct OOJSProfileStackFrame OOJSProfileStackFrame;
struct OOJSProfileStackFrame
{
	OOJSProfileStackFrame	*back;
	const char				*function;
	OOHighResTimeValue		startTime;
	OOTimeDelta				subTime;
};


#define OOJS_DECLARE_PROFILE_STACK_FRAME(name) OOJSProfileStackFrame name;
void OOJSProfileEnter(OOJSProfileStackFrame *frame, const char *function);
void OOJSProfileExit(OOJSProfileStackFrame *frame);


@interface OOTimeProfile: NSObject
{
@private
	double						_totalTime;
	double						_nativeTime;
	double						_extensionTime;
	
	double						_profilerOverhead;
	
	NSArray						*_profileEntries;
}

- (double) totalTime;
- (double) javaScriptTime;
- (double) nativeTime;
- (double) extensionTime;
- (double) nonExtensionTime;
- (double) profilerOverhead;

- (NSArray *) profileEntries;	// Array of OOTimeProfileEntry

@end


@interface OOTimeProfileEntry: NSObject
{
@private
	NSString					*_function;
	unsigned long				_hitCount;
	double						_totalTimeSum;
	double						_selfTimeSum;
	double						_totalTimeMax;
	double						_selfTimeMax;
}

- (NSString *) description;

- (NSString *) function;
- (OOUInteger) hitCount;
- (double) totalTimeSum;
- (double) selfTimeSum;
- (double) totalTimeAverage;
- (double) selfTimeAverage;
- (double) totalTimeMax;
- (double) selfTimeMax;

- (NSComparisonResult) compareByTotalTime:(OOTimeProfileEntry *)other;
- (NSComparisonResult) compareByTotalTimeReverse:(OOTimeProfileEntry *)other;
- (NSComparisonResult) compareBySelfTime:(OOTimeProfileEntry *)other;
- (NSComparisonResult) compareBySelfTimeReverse:(OOTimeProfileEntry *)other;

@end

#else

#define OOJS_DECLARE_PROFILE_STACK_FRAME(name)
#define OOJSProfileEnter(frame, function) do {} while (0)
#define OOJSProfileExit(frame) do {} while (0)

#endif


// Context callback, set up by -[OOJavaScriptEngine init].
JSBool OOJSContextCallback(JSContext *context, uintN contextOp);
