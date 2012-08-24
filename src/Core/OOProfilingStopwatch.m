/*	

OOProfilingStopwatch.m
Oolite

Testing utility to monitor elapsed times at high precision.


Copyright (C) 2010-2012 Jens Ayton and contributors

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

#import "OOProfilingStopwatch.h"


@implementation OOProfilingStopwatch

- (id) init
{
	if ((self = [super init]))
	{
		_start = OOGetHighResTime();
		_end = OOCopyHighResTime(_start);
		_running = YES;
	}
	return self;
}


+ (instancetype) stopwatch
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
		OOHighResTimeValue temp = _end;
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


OOTimeDelta OOHighResTimeDeltaInSeconds(OOHighResTimeValue startTime, OOHighResTimeValue endTime)
{
#if OO_PROFILING_STOPWATCH_MACH_ABSOLUTE_TIME
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
#elif OO_PROFILING_STOPWATCH_WINDOWS
	return 1e-3 * (double)(endTime - startTime);
#elif OO_PROFILING_STOPWATCH_GETTIMEOFDAY
	int_fast32_t deltaS = (int_fast32_t)endTime.tv_sec - (int_fast32_t)startTime.tv_sec;
	int_fast32_t deltaU = (int_fast32_t)endTime.tv_usec - (int_fast32_t)startTime.tv_usec;
	double result = deltaU;
	result = (result * 1e-6) + deltaS;
	return result;
#elif OO_PROFILING_STOPWATCH_JS_NOW
	return 1e-6 * (double)(endTime - startTime);
#endif
}
