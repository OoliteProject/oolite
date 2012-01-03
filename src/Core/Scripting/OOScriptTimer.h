/*

OOScriptTimer.h

Abstract base class for script timers. An OOScriptTimer does nothing when it
fires; subclasses should override the -timerFired method.

Timers are immutable. They are retained by the timer subsystem while scheduled.
A timer with a negative interval will only fire once. A negative nexttime when
inited will cause the timer to fire after the specified interval. A persistent
timer will remain if the player dies and respawns; non-persistent timers will
be removed.


Oolite
Copyright (C) 2004-2012 Giles C Williams and contributors

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

#import "OOCocoa.h"
#import "OOTypes.h"


@interface OOScriptTimer: NSObject
{
@private
	OOTimeAbsolute				_nextTime;
	OOTimeDelta					_interval;
	BOOL						_isScheduled;
	BOOL						_hasBeenRun;	// Needed for one-shot timers.
}

- (id) initWithNextTime:(OOTimeAbsolute)nextTime
			   interval:(OOTimeDelta)interval;

// Sets nextTime to current time + delay.
- (id) initOneShotTimerWithDelay:(OOTimeDelta)delay;

- (OOTimeAbsolute)nextTime;
- (BOOL)setNextTime:(OOTimeAbsolute)nextTime;	// Only works when timer is not scheduled.
- (OOTimeDelta)interval;
- (void)setInterval:(OOTimeDelta)interval;

// Subclass responsibility:
- (void) timerFired;

- (BOOL) scheduleTimer;
- (void) unscheduleTimer;
- (BOOL) isScheduled;


+ (void) updateTimers;
+ (void) noteGameReset;


- (BOOL) isValidForScheduling;

- (NSComparisonResult) compareByNextFireTime:(OOScriptTimer *)other;

@end
