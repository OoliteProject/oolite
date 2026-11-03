/*

OOScriptTimer.h

Abstract base class for script timers. An OOScriptTimer does nothing when it
fires; subclasses should override the -timerFired method.

Timers are immutable. They are retained by the timer subsystem while scheduled.
A timer with a negative interval will only fire once. A negative nexttime when
inited will cause the timer to fire after the specified interval. A persistent
timer will remain if the player dies and respawns; non-persistent timers will
be removed.

C++20 since bead oo-kdyh (proposed ADR-0056, the OOColor house style), converted with its one
subclass, OOJSTimer (OOJSTimer.h). The class is cxx::OOScriptTimer while
OOScriptTimer+ObjCBridge.h, imported at the end of this header, keeps the Objective-C
OOScriptTimer that PlayerEntity messages (+updateTimers, +noteGameReset) and that the timer
queue holds: OOPriorityQueue (bead oo-3lj8) keeps Objective-C elements ordered by a selector, so
a scheduled timer is queued as its facade, which keeps it alive while it is scheduled.


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

#ifndef OOSCRIPTTIMER_H
#define OOSCRIPTTIMER_H

#import "OOFoundation.h"
#import "OOTypes.h"
#include "oofnd/Ref.hpp"
#include "oofnd/StdLib.hpp"

#include <optional>
#include <string>

namespace cxx {

class OOScriptTimer : public oo::RefCounted {
public:
    // [[OOScriptTimer alloc] initWithNextTime:interval:]: null where the initialiser answered nil
    // (a next time in the past, or negative, with no interval).
    static oo::Ref<OOScriptTimer> timerWithNextTime(OOTimeAbsolute nextTime, OOTimeDelta interval);

    // [[OOScriptTimer alloc] initOneShotTimerWithDelay:]: sets nextTime to current time + delay.
    static oo::Ref<OOScriptTimer> oneShotTimerWithDelay(OOTimeDelta delay);

    ~OOScriptTimer() override;

    virtual std::optional<std::string> descriptionComponents() const;

    OOTimeAbsolute nextTime();
    bool setNextTime(OOTimeAbsolute nextTime); // Only works when timer is not scheduled.
    OOTimeDelta interval();
    void setInterval(OOTimeDelta interval);

    // Subclass responsibility:
    virtual void timerFired();

    bool scheduleTimer();
    void unscheduleTimer();
    bool isScheduled();

    static void updateTimers();
    static void noteGameReset();

    bool isValidForScheduling();

    OOComparisonResult compareByNextFireTime(OOScriptTimer* other);

protected:
    OOScriptTimer() = default;

    // The initialisers (-initWithNextTime:interval:, -initOneShotTimerWithDelay:), for the
    // factories above and a subclass's: false where they answered nil (proposed ADR-0056
    // amendment oo-bhb9).
    bool initWithNextTime(OOTimeAbsolute nextTime, OOTimeDelta interval);
    bool initOneShotTimerWithDelay(OOTimeDelta delay);

private:
    OOTimeAbsolute _nextTime = { };
    OOTimeDelta _interval = { };
    bool _isScheduled = { };
    bool _hasBeenRun = { }; // Needed for one-shot timers.
};

} // namespace cxx

// Transitional: the Objective-C OOScriptTimer, for callers not yet converted and for the timer
// queue. Deleted, with namespace cxx above, by the bridge's deletion bead.
#import "OOScriptTimer+ObjCBridge.h"

#endif // OOSCRIPTTIMER_H
