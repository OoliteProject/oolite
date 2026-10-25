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

#ifndef INCLUDED_OOPROFILINGSTOPWATCH_h
#define INCLUDED_OOPROFILINGSTOPWATCH_h

#ifndef OOSTOPWATCH_STANDALONE
#if defined(__cplusplus) && !defined(OO_PLAIN_CPP_UNIT)	// was __OBJC__: a game unit (an Objective-C++ unit until bead oo-dbz), not a plain C++ one
#include "OOCocoa.h"
#else
/*	A plain C++ translation unit (bead oo-9ht.72: the JS bindings, through
	OOJSEngineNativeWrappers.h) cannot parse OOCocoa.h's Objective-C class declarations. The one platform switch
	below that differs from its default on this build is set as OOCocoa.h sets it (WIN32 is only
	defined on the GNUstep build), so
	OOHighResTimeValue is the same type in both kinds of translation unit.
*/
#if defined(WIN32) && !defined(OOLITE_WINDOWS)
#define OOLITE_WINDOWS 1
#endif
#endif
#include "OOFunctionAttributes.h"
#include "OOTypes.h"
#endif

#include "oofnd/Ref.hpp"


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
/*	...otherwise, use a microsecond count from std::chrono::steady_clock for higher
	precision (formerly the script engine's own clock; bead oo-1gc.3). Only
	differences between two readings are ever used.
*/
#define OO_PROFILING_STOPWATCH_MICROSECONDS 1
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

#if OO_PROFILING_STOPWATCH_MICROSECONDS
#include <chrono>
#include <cstdint>
typedef int64_t OOHighResTimeValue;

OOINLINE OOHighResTimeValue OOGetHighResTime(void)
{
	return std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now().time_since_epoch()).count();
}
#define OODisposeHighResTime(time)  do { (void)time; } while (0)
#define OOCopyHighResTime(time) ((OOHighResTimeValue)time)
#endif

OOTimeDelta OOHighResTimeDeltaInSeconds(OOHighResTimeValue startTime, OOHighResTimeValue endTime);


class OOProfilingStopwatch : public oo::RefCounted
{
public:
	OOProfilingStopwatch();
	~OOProfilingStopwatch() override;

	static oo::Ref<OOProfilingStopwatch> stopwatch();		// New stopwatch is initially started.

	void start();
	void stop();
	OOTimeDelta currentTime();	// Returns stop time - start time if stopped, or now - start time if running.

	/*	Resets timer to zero, returning the current value. This is drift-free, i.e.
		if it is called twice in a row while running the sum is an accurate time
		since the timer started.
	*/
	OOTimeDelta reset();

private:
	OOHighResTimeValue	_start = {};
	OOHighResTimeValue	_end = {};
	bool				_running = {};
};

#endif	// INCLUDED_OOPROFILINGSTOPWATCH_h
