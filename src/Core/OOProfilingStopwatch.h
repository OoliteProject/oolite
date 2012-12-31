/*	

OOProfilingStopwatch.h
Oolite

Testing utility to monitor elapsed times at high precision.


Copyright (C) 2010-2013 Jens Ayton and contributors

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

#ifndef OOSTOPWATCH_STANDALONE
#import "OOCocoa.h"
#import "OOFunctionAttributes.h"
#import "OOTypes.h"
#endif


/*	Platform-specific high-resolution timer:
	
	OOHighResTimeValue is a time value. This could be a scalar, struct or pointer.
	OOHighResTimeValue OOGetHighResTime(void) returns the current time.
	OODisposeHighResTime() destroys an existing OOHighResTimeValue, if necessary.
	It must do nothing if the value passed is zeroed out.
	OOCopyHighResTime(x) returns a timer value equal to x.
	OOTimeDelta OOHighResTimeDeltaInSeconds(OOHighResTimeValue startTime, OOHighResTimeValue endTime)
	returns the difference between two time values, in seconds.
*/

#if OOLITE_MAC_OS_X

// Mac OS X: always use MACH_ABSOLUTE_TIME.
#define OO_PROFILING_STOPWATCH_MACH_ABSOLUTE_TIME 1
#import <mach/mach_time.h>

typedef uint64_t OOHighResTimeValue;

#define OOGetHighResTime mach_absolute_time
#define OODisposeHighResTime(time)  do { (void)time; } while (0)
#define OOCopyHighResTime(time) ((OOHighResTimeValue)time)

#elif OOLITE_WINDOWS

// Windows: if standalone, use timeGetTime...
#if OOSTOPWATCH_STANDALONE
#define OO_PROFILING_STOPWATCH_WINDOWS 1
typedef DWORD OOHighResTimeValue;	// Rolls over once every 50 days, but we can live with that.

// Note: timeGetTime returns time in milliseconds. This results in lower time resolution in Windows, but at this stage I
// don't think we need to do something about it. If we really need microseond precision, we might consider an implementation
// based on the Win32 API QueryPerformanceCounter function - Nikos 20100615.
#define OOGetHighResTime timeGetTime
#define OODisposeHighResTime(time)  do { (void)time; } while (0)
#define OOCopyHighResTime(time) ((OOHighResTimeValue)time)

#else
/*	...otherwise, use JS_Now() for higher precision. The Windows implementation
	does the messy work of calibrating performance counters against low-res
	timers.
*/
#define OO_PROFILING_STOPWATCH_JS_NOW 1
#endif

#else

// Other platforms (presumed unixy): use gettimeofday().

#define OO_PROFILING_STOPWATCH_GETTIMEOFDAY 1
#include <sys/time.h>

typedef struct timeval OOHighResTimeValue;

OOINLINE OOHighResTimeValue OOGetHighResTime(void)
{
	struct timeval tv;
	gettimeofday(&tv, NULL);
	return tv;
}

#define OODisposeHighResTime(time)  do { (void)time; } while (0)
#define OOCopyHighResTime(time) ((OOHighResTimeValue)time)

#endif

#if OO_PROFILING_STOPWATCH_JS_NOW
#include <jsapi.h>
typedef int64 OOHighResTimeValue;

#define OOGetHighResTime JS_Now
#define OODisposeHighResTime(time)  do { (void)time; } while (0)
#define OOCopyHighResTime(time) ((OOHighResTimeValue)time)
#endif

OOTimeDelta OOHighResTimeDeltaInSeconds(OOHighResTimeValue startTime, OOHighResTimeValue endTime);


@interface OOProfilingStopwatch: NSObject
{
@private
	OOHighResTimeValue	_start;
	OOHighResTimeValue	_end;
	BOOL				_running;
}

+ (instancetype) stopwatch;		// New stopwatch is initially started.

- (void) start;
- (void) stop;
- (OOTimeDelta) currentTime;	// Returns stop time - start time if stopped, or now - start time if running.

/*	Resets timer to zero, returning the current value. This is drift-free, i.e.
	if it is called twice in a row while running the sum is an accurate time
	since the timer started.
*/
- (OOTimeDelta) reset;

@end
