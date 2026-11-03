/*

OOScriptTimer+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, bead oo-kdyh): the Objective-C OOScriptTimer, a facade over the
C++ cxx::OOScriptTimer (OOScriptTimer.h), for what is not converted yet: PlayerEntity, which
sends +updateTimers and +noteGameReset, and OOPriorityQueue, whose elements are Objective-C
objects ordered by a selector (-compareByNextFireTime:), so a scheduled timer is queued as its
facade. Its interface is the one OOScriptTimer.h declared before the conversion, copied exactly
(same selectors and types; the ivar is the C++ object). Imported as the last line of
OOScriptTimer.h; do not import it directly.

        a caller that is                       holds / passes                  crosses with
        -------------------------------------  ------------------------------  -------------------------
        still Objective-C                      OOScriptTimer *                 nothing: messages as before
        converted (C++)                        oo::Ref<cxx::OOScriptTimer>
          handing a timer to Objective-C                                        oo::ToObjC(timer)
          taking one from Objective-C                                           oo::ToCxx(objcTimer)

oo::ToObjC gives a timer's one live facade (oo::ObjCPeers), of the facade class named like its
C++ class (cxx::OOJSTimer's is OOJSTimer, OOJSTimer+ObjCBridge.h), so identity survives and the
queue finds the facade it holds. No Objective-C subclass of OOScriptTimer is left (OOJSTimer
converted in the same bead); a new one would need the adapter of ADR-0056 amendment 1. Never add
to this file; converted code does not message the facade. Deleted by its deletion bead once
PlayerEntity is converted and the timer queue holds C++ timers.


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

#ifndef OOSCRIPTTIMER_OBJCBRIDGE_H
#define OOSCRIPTTIMER_OBJCBRIDGE_H

#import "OOFoundation.h"
#import "oofnd/objc/OOObject.h"

@interface OOScriptTimer : OOObject {
@private
    oo::Ref<cxx::OOScriptTimer> _cxxTimer;
}

- (id)initWithNextTime:(OOTimeAbsolute)nextTime
              interval:(OOTimeDelta)interval;

// Sets nextTime to current time + delay.
- (id)initOneShotTimerWithDelay:(OOTimeDelta)delay;

- (OOTimeAbsolute)nextTime;
- (BOOL)setNextTime:(OOTimeAbsolute)nextTime; // Only works when timer is not scheduled.
- (OOTimeDelta)interval;
- (void)setInterval:(OOTimeDelta)interval;

// Subclass responsibility:
- (void)timerFired;

- (BOOL)scheduleTimer;
- (void)unscheduleTimer;
- (BOOL)isScheduled;

+ (void)updateTimers;
+ (void)noteGameReset;

- (BOOL)isValidForScheduling;

- (OOComparisonResult)compareByNextFireTime:(OOScriptTimer*)other;

@end

namespace oo {

// A timer's Objective-C facade, of the class named like its C++ class: its live one, else a new
// one; autoreleased. nil for null.
::OOScriptTimer* ToObjC(cxx::OOScriptTimer* timer);
inline ::OOScriptTimer* ToObjC(const Ref<cxx::OOScriptTimer>& timer) { return ToObjC(timer.get()); }

// The timer's live facade, or nil: never makes one. For unscheduling, which also runs from the
// destructors, when the facade is already gone.
::OOScriptTimer* LiveObjC(cxx::OOScriptTimer* timer);

// The C++ timer behind a facade, borrowed (the facade retains it); null for nil.
cxx::OOScriptTimer* ToCxx(::OOScriptTimer* timer);

} // namespace oo

#endif // OOSCRIPTTIMER_OBJCBRIDGE_H
