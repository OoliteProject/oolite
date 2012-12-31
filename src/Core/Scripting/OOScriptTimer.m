/*

OOScriptTimer.m


Oolite
Copyright (C) 2004-2013 Giles C Williams and contributors

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
MA 02110-1301, USA.

*/

#import "OOScriptTimer.h"
#import "Universe.h"
#import "OOLogging.h"
#import "OOPriorityQueue.h"


static OOPriorityQueue	*sTimers;

// During an update, new timers must be deferred to avoid an infinite loop.
static BOOL				sUpdating;
static NSMutableArray	*sDeferredTimers;


@implementation OOScriptTimer

- (id) initWithNextTime:(OOTimeAbsolute)nextTime
			   interval:(OOTimeDelta)interval
{
	OOTimeAbsolute			now;
	
	if ((self = [super init]))
	{
		if (interval <= 0.0)  interval = -1.0;
		
		now = [UNIVERSE getTime];
		if (nextTime < 0.0)  nextTime = now + interval;
		if (nextTime < now && interval < 0)
		{
			// Negative or old nextTime and negative interval = meaningless.
			[self release];
			self = nil;
		}
		else
		{
			_nextTime = nextTime;
			_interval = interval;
			_hasBeenRun = NO;
		}
	}
	
	return self;
}

	// Sets nextTime to current time + delay.
- (id) initOneShotTimerWithDelay:(OOTimeDelta)delay
{
	return [self initWithNextTime:[UNIVERSE getTime] + delay interval:-1.0];
}


- (void) dealloc
{
	if (_isScheduled)  [self unscheduleTimer];
	
	[super dealloc];
}


- (NSString *) descriptionComponents
{
	NSString					*intervalDesc = nil;
	
	if (_interval <= 0.0)  intervalDesc = @"one-shot";
	else  intervalDesc = [NSString stringWithFormat:@"interval: %g", _interval];
		
	return [NSString stringWithFormat:@"nextTime: %g, %@, %srunning", _nextTime, intervalDesc, _isScheduled ? "" : "not "];
}


- (OOTimeAbsolute)nextTime
{
	return _nextTime;
}


- (BOOL)setNextTime:(OOTimeAbsolute)nextTime
{
	if (_isScheduled)  return NO;
	
	_nextTime = nextTime;
	return YES;
}


- (OOTimeDelta)interval
{
	return _interval;
}


- (void)setInterval:(OOTimeDelta)interval
{
	if (interval <= 0.0)  interval = -1.0;
	_interval = interval;
}


- (void) timerFired
{
	OOLogGenericSubclassResponsibility();
}


- (BOOL) scheduleTimer
{
	if (_isScheduled)  return YES;
	if (![self isValidForScheduling])  return NO;
	
	if (EXPECT(!sUpdating))
	{
		if (EXPECT_NOT(sTimers == nil))  sTimers = [[OOPriorityQueue alloc] initWithComparator:@selector(compareByNextFireTime:)];
		[sTimers addObject:self];
	}
	else
	{
		if (sDeferredTimers == nil)  sDeferredTimers = [[NSMutableArray alloc] init];
		[sDeferredTimers addObject:self];
	}
	
	_isScheduled = YES;
	return YES;
}


- (void) unscheduleTimer
{
	[sTimers removeExactObject:self];
	_isScheduled = NO;
	_hasBeenRun = NO;
}


- (BOOL) isScheduled
{
	return _isScheduled;
}


+ (void) updateTimers
{
	OOScriptTimer		*timer = nil;
	OOTimeAbsolute		now;
	
	sUpdating = YES;
	
	now = [UNIVERSE getTime];
	for (;;)
	{
		timer = [sTimers peekAtNextObject];
		if (timer == nil || now < [timer nextTime])  break;
		
		[sTimers removeNextObject];
		
		// Must fire before rescheduling so that the timer callback can stop itself. -- Ahruman 2011-01-01
		[timer timerFired];
		
		timer->_hasBeenRun = YES;
		
		if (timer->_isScheduled)
		{
			timer->_isScheduled = NO;
			[timer scheduleTimer];
		}
	}
	
	if (sDeferredTimers != nil)
	{
		[sTimers addObjects:sDeferredTimers];
		DESTROY(sDeferredTimers);
	}
	
	sUpdating = NO;
}


+ (void) noteGameReset
{
	NSArray				*timers = nil;
	NSEnumerator		*timerEnum = nil;
	OOScriptTimer		*timer = nil;
	
	// Intermediate array is required so we don't get stuck in an endless loop over reinserted timers. Note that -sortedObjects also clears the queue!
	timers = [sTimers sortedObjects];
	for (timerEnum = [timers objectEnumerator]; (timer = [timerEnum nextObject]); )
	{
		timer->_isScheduled = NO;
	}
}


- (BOOL) isValidForScheduling
{
	OOTimeAbsolute		now;
	double				scaled;
	
	now = [UNIVERSE getTime];
	if (_nextTime <= now)
	{
		if (_interval <= 0.0 && _hasBeenRun)  return NO;	// One-shot timer which has expired
		
		// Move _nextTime to the closest future time that's a multiple of _interval
		scaled = (now - _nextTime) / _interval;
		scaled = ceil(scaled);
		_nextTime += scaled * _interval;
		if (_nextTime <= now && _hasBeenRun) 
		{
			// Should only happen if _nextTime is exactly equal to now after previous stuff
			_nextTime += _interval;
		}
	}
	
	return YES;
}

- (NSComparisonResult) compareByNextFireTime:(OOScriptTimer *)other
{
	OOTimeAbsolute		otherTime = -INFINITY;
	
	@try
	{
		if (other != nil)  otherTime = [other nextTime];
	}
	@catch (NSException *exception)
	{
		OOLog(kOOLogException, @"\n\n***** Ignoring Timer Exception: %@ : %@ *****\n\n",[exception name], [exception reason]);
	}
	
	if (_nextTime < otherTime) return NSOrderedAscending;
	else if (_nextTime > otherTime) return NSOrderedDescending;
	else  return NSOrderedSame;
}

@end
