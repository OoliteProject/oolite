/*	OOProfilingStopwatch.h
	Oolite
	
	Testing utility to monitor elapsed times at high precision.
*/

#import "OOCocoa.h"
#import "OOFunctionAttributes.h"
#import "OOTypes.h"


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
#define OO_PROFILING_STOPWATCH_MACH_ABSOLUTE_TIME 1
#import <mach/mach_time.h>

typedef uint64_t OOHighResTimeValue;

#define OOGetHighResTime mach_absolute_time
#define OODisposeHighResTime(time)  do { (void)time; } while (0)
#define OOCopyHighResTime(time) ((OOHighResTimeValue)time)

OOTimeDelta OOHighResTimeDeltaInSeconds(OOHighResTimeValue startTime, OOHighResTimeValue endTime);
#elif OOLITE_WINDOWS
#define OO_PROFILING_STOPWATCH_WINDOWS 1
typedef DWORD OOHighResTimeValue;	// Rolls over once every 50 days, but we can live with that.

#define OOGetHighResTime timeGetTime
#define OODisposeHighResTime(time)  do { (void)time; } while (0)
#define OOCopyHighResTime(time) ((OOHighResTimeValue)time)

OOTimeDelta OOHighResTimeDeltaInSeconds(OOHighResTimeValue startTime, OOHighResTimeValue endTime);
#else
#define OO_PROFILING_STOPWATCH_GETTIMEOFDAY 1
#import <sys/time.h>

typedef struct timeval OOHighResTimeValue;

OOINLINE OOHighResTimeValue OOGetHighResTime(void)
{
	struct timeval tv;
	gettimeofday(&tv, NULL);
	return tv;
}

#define OODisposeHighResTime(time)  do { (void)time; } while (0)
#define OOCopyHighResTime(time) ((OOHighResTimeValue)time)

OOTimeDelta OOHighResTimeDeltaInSeconds(OOHighResTimeValue startTime, OOHighResTimeValue endTime);
#endif


@interface OOProfilingStopwatch: NSObject
{
@private
	OOHighResTimeValue	_start;
	OOHighResTimeValue	_end;
	BOOL				_running;
}

+ (id) stopwatch;

- (void) start;
- (void) stop;
- (OOTimeDelta) currentTime;	// Returns stop time - start time if stopped, or now - start time if running.

/*	Resets timer to zero, returning the current value. This is drift-free, i.e.
	if it is called twice in a row while running the sum is an accurate time
	since the timer started.
*/
- (OOTimeDelta) reset;

@end
