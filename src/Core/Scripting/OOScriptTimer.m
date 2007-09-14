/*

OOScriptTimer.m


Oolite
Copyright (C) 2004-2007 Giles C Williams and contributors

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


static OOPriorityQueue *sTimers = nil;


@implementation OOScriptTimer

- (id) initWithNextTime:(OOTimeAbsolute)nextTime
			   interval:(OOTimeDelta)interval
{
	OOTimeAbsolute			now;
	
	self = [super init];
	if (self != nil)
	{
		now = [UNIVERSE getTime];
		if (nextTime < 0.0)  nextTime = now + interval;
		if (nextTime < now)
		{
			// Negative or old nextTime and negative interval = meaningless.
			[self release];
			self = nil;
		}
	}
	
	return self;
}

	// Sets nextTime to current time + delay.
- (id) initOneShotTimerWithDelay:(OOTimeDelta)delay
{
	return [self initWithNextTime:[UNIVERSE getTime] + delay interval:-1.0];
}


- (OOTimeAbsolute)nextTime
{
	return _nextTime;
}


- (void) timerFired
{
	OOLogGenericSubclassResponsibility();
}


- (BOOL) isPersistent
{
	return NO;
}


- (BOOL) scheduleTimer
{
	if (![self isValidForScheduling])  return NO;
	
	if (sTimers == nil)  sTimers = [[OOPriorityQueue alloc] initWithComparator:@selector(compareByNextFireTime:)];
	[sTimers addObject:self];
	return YES;
}


- (void) unscheduleTimer
{
	[sTimers removeExactObject:self];
}


+ (void) updateTimers
{
	OOScriptTimer		*timer = nil;
	OOTimeAbsolute		now;
	
	now = [UNIVERSE getTime];
	for (;;)
	{
		timer = [sTimers peekAtNextObject];
		if (now < [timer nextTime])  break;
		
		[sTimers removeNextObject];
		[timer timerFired];
		[timer scheduleTimer];
	}
}


+ (void) noteGameReset
{
	NSArray				*timers = nil;
	NSEnumerator		*timerEnum = nil;
	OOScriptTimer		*timer = nil;
	
	// Intermediate array is required so we don't get stuck in an endless loop over reinserted timers
	timers = [sTimers sortedObjects];
	for (timerEnum = [timers objectEnumerator]; (timer = [timerEnum nextObject]); )
	{
		if ([timer isPersistent])  [timer scheduleTimer];
	}
}


- (BOOL) isValidForScheduling
{
	OOTimeAbsolute		now;
	double				scaled;
	
	now = [UNIVERSE getTime];
	if (_nextTime < now)
	{
		if (_interval <= 0.0)  return NO;	// One-shot timer which has expired
		
		// Move _nextTime to the closest future time that's a multiple of _interval
		scaled = (now - _nextTime) / _interval;
		scaled = ceil(scaled);
		_nextTime += scaled * _interval;
	}
	
	return YES;
}

- (NSComparisonResult) compareByNextFireTime:(OOScriptTimer *)other
{
	OOTimeAbsolute		otherTime;
	
	if (other != nil)  otherTime = [other nextTime];
	else  otherTime = -INFINITY;
	
	if (_nextTime < otherTime) return NSOrderedAscending;
	else if (_nextTime < otherTime) return NSOrderedDescending;
	else  return NSOrderedSame;
}

@end
