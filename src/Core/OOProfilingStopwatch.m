#import "OOProfilingStopwatch.h"


@implementation OOProfilingStopwatch

- (id) init
{
	if ((self = [super init]))
	{
		_start = OOGetHighResTime();
	}
	return self;
}


+ (id) stopwatch
{
	return [[[self alloc] init] autorelease];
}


- (void) dealloc
{
	OODisposeHighResTime(_start);
	OODisposeHighResTime(_end);
	
	[super dealloc];
}


- (void) start
{
	OOHighResTimeValue temp = _start;
	_start = OOGetHighResTime();
	OODisposeHighResTime(temp);
	_running = YES;
}


- (void) stop
{
	OOHighResTimeValue temp = _start;
	_end = OOGetHighResTime();
	OODisposeHighResTime(temp);
	_running = NO;
}


- (OOTimeDelta) currentTime
{
	if (_running)
	{
		OOHighResTimeValue temp = _start;
		_end = OOGetHighResTime();
		OODisposeHighResTime(temp);
	}
	return OOHighResTimeDeltaInSeconds(_start, _end);
}


- (OOTimeDelta) reset
{
	OOTimeDelta result;
	if (_running)
	{
		OOHighResTimeValue now = OOGetHighResTime();
		result = OOHighResTimeDeltaInSeconds(_start, now);
		OODisposeHighResTime(_start);
		_start = now;
	}
	else
	{
		result = OOHighResTimeDeltaInSeconds(_start, _end);
		OODisposeHighResTime(_end);
		_end = OOCopyHighResTime(_start);
	}
	return result;
}

@end


#if OO_PROFILING_STOPWATCH_MACH_ABSOLUTE_TIME
OOTimeDelta OOHighResTimeDeltaInSeconds(OOHighResTimeValue startTime, OOHighResTimeValue endTime)
{
	uint64_t diff = endTime - startTime;
	static double conversion = 0.0;
	
	if (EXPECT_NOT(conversion == 0.0))
	{
		mach_timebase_info_data_t info;
		kern_return_t err = mach_timebase_info(&info);
		
		if (err == 0)
		{
			conversion = 1e-9 * (double)info.numer / (double)info.denom;
		}
	}
	
	return conversion * (double)diff;
}
#elif OO_PROFILING_STOPWATCH_WINDOWS
OOTimeDelta OOHighResTimeDeltaInSeconds(OOHighResTimeValue startTime, OOHighResTimeValue endTime)
{
	return 1e-6 * (double)(endTime - startTime);
}
#elif OO_PROFILING_STOPWATCH_GETTIMEOFDAY
OOTimeDelta OOHighResTimeDeltaInSeconds(OOHighResTimeValue startTime, OOHighResTimeValue endTime)
{
	int_fast32_t deltaS = (int_fast32_t)endTime.tv_sec - (int_fast32_t)startTime.tv_sec;
	int_fast32_t deltaU = (int_fast32_t)endTime.tv_usec - (int_fast32_t)startTime.tv_usec;
	double result = deltaU;
	result = (result * 1e-6) + deltaS;
	return result;
}
#endif
