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
#import "OOLogging.h"
#import "OOPriorityQueue.h"
#import "Universe.h"
#include "oofnd/String.hpp"
#include "oofnd/objc/OORuntime.h"

static OOPriorityQueue* sTimers;

// During an update, new timers must be deferred to avoid an infinite loop.
namespace {
static bool sUpdating;
} // namespace
namespace {
static std::vector<oo::ObjCRef<OOScriptTimer*>>* sDeferredTimers;
} // namespace

namespace cxx {

oo::Ref<OOScriptTimer> OOScriptTimer::timerWithNextTime(OOTimeAbsolute nextTime, OOTimeDelta interval)
{
    oo::Ref<OOScriptTimer> timer = oo::adopt(new OOScriptTimer);
    if (!timer->initWithNextTime(nextTime, interval))
        return nullptr;
    return timer;
}

oo::Ref<OOScriptTimer> OOScriptTimer::oneShotTimerWithDelay(OOTimeDelta delay)
{
    oo::Ref<OOScriptTimer> timer = oo::adopt(new OOScriptTimer);
    if (!timer->initOneShotTimerWithDelay(delay))
        return nullptr;
    return timer;
}

bool OOScriptTimer::initWithNextTime(OOTimeAbsolute nextTime, OOTimeDelta interval)
{
    OOTimeAbsolute now;

    {
        if (interval <= 0.0)
            interval = -1.0;

        now = [UNIVERSE getTime];
        if (nextTime < 0.0)
            nextTime = now + interval;
        if (nextTime < now && interval < 0) {
            // Negative or old nextTime and negative interval = meaningless.
            return false;
        } else {
            _nextTime = nextTime;
            _interval = interval;
            _hasBeenRun = false;
        }
    }

    return true;
}

// Sets nextTime to current time + delay.
bool OOScriptTimer::initOneShotTimerWithDelay(OOTimeDelta delay)
{
    return initWithNextTime([UNIVERSE getTime] + delay, -1.0);
}

OOScriptTimer::~OOScriptTimer()
{
    if (_isScheduled)
        unscheduleTimer();
}

std::optional<std::string> OOScriptTimer::descriptionComponents() const
{
    std::string intervalDesc;

    if (_interval <= 0.0)
        intervalDesc = "one-shot";
    else
        intervalDesc = oo::str::format("interval: %g", _interval);

    return oo::str::format("nextTime: %g, %s, %srunning", _nextTime, intervalDesc.c_str(), _isScheduled ? "" : "not ");
}

OOTimeAbsolute OOScriptTimer::nextTime()
{
    return _nextTime;
}

bool OOScriptTimer::setNextTime(OOTimeAbsolute nextTime)
{
    if (_isScheduled)
        return false;

    _nextTime = nextTime;
    return true;
}

OOTimeDelta OOScriptTimer::interval()
{
    return _interval;
}

void OOScriptTimer::setInterval(OOTimeDelta interval)
{
    if (interval <= 0.0)
        interval = -1.0;
    _interval = interval;
}

void OOScriptTimer::timerFired()
{
    OOLogGenericSubclassResponsibility();
}

bool OOScriptTimer::scheduleTimer()
{
    if (_isScheduled)
        return true;
    if (!isValidForScheduling())
        return false;

    if (EXPECT(!sUpdating)) {
        if (EXPECT_NOT(sTimers == nullptr))
            sTimers = OOPriorityQueue::queueWithComparator(OOSelectorFromName("compareByNextFireTime:")).leakRef();
        sTimers->addObject(oo::ToObjC(this)); // the queue holds (and retains) the timer's facade
    } else {
        if (sDeferredTimers == NULL)
            sDeferredTimers = new std::vector<oo::ObjCRef<::OOScriptTimer*>>;
        sDeferredTimers->emplace_back(oo::ToObjC(this));
    }

    _isScheduled = true;
    return true;
}

void OOScriptTimer::unscheduleTimer()
{
    // A queued timer's facade is alive (the queue retains it), so a timer with no live facade is not
    // in the queue; this is also what makes the call safe from the destructors.
    if (sTimers != nullptr)
        sTimers->removeExactObject(oo::LiveObjC(this));
    _isScheduled = false;
    _hasBeenRun = false;
}

bool OOScriptTimer::isScheduled()
{
    return _isScheduled;
}

void OOScriptTimer::updateTimers()
{
    OOScriptTimer* timer = nullptr;
    OOTimeAbsolute now;

    sUpdating = true;

    now = [UNIVERSE getTime];
    for (;;) {
        timer = (sTimers != nullptr) ? oo::ToCxx(static_cast<::OOScriptTimer*>(sTimers->peekAtNextObject())) : nullptr;
        if (timer == nullptr || now < timer->nextTime())
            break;

        sTimers->removeNextObject(); // autoreleases the facade, which keeps the timer alive

        // Must fire before rescheduling so that the timer callback can stop itself. -- Ahruman 2011-01-01
        timer->timerFired();

        timer->_hasBeenRun = true;

        if (timer->_isScheduled) {
            timer->_isScheduled = false;
            timer->scheduleTimer();
        }
    }

    if (sDeferredTimers != NULL) {
        for (const auto& deferred : *sDeferredTimers)
            if (sTimers != nullptr)
                sTimers->addObject(deferred.get()); // as -addObjects: did, in order
        delete sDeferredTimers;
        sDeferredTimers = NULL;
    }

    sUpdating = false;
}

void OOScriptTimer::noteGameReset()
{
    // Intermediate array is required so we don't get stuck in an endless loop over reinserted timers. Note that -sortedObjects also clears the queue!
    const std::vector<oo::ObjCRef<id>> timers = (sTimers != nullptr) ? sTimers->sortedObjects() : std::vector<oo::ObjCRef<id>>(); // (no C++ value from a message to nil)
    for (const auto& timer : timers) {
        oo::ToCxx(static_cast<::OOScriptTimer*>(timer.get()))->_isScheduled = false;
    }
}

bool OOScriptTimer::isValidForScheduling()
{
    OOTimeAbsolute now;
    double scaled;

    now = [UNIVERSE getTime];
    if (_nextTime <= now) {
        if (_interval <= 0.0 && _hasBeenRun)
            return false; // One-shot timer which has expired

        // Move _nextTime to the closest future time that's a multiple of _interval
        scaled = (now - _nextTime) / _interval;
        scaled = ceil(scaled);
        _nextTime += scaled * _interval;
        if (_nextTime <= now && _hasBeenRun) {
            // Should only happen if _nextTime is exactly equal to now after previous stuff
            _nextTime += _interval;
        }
    }

    return true;
}

OOComparisonResult OOScriptTimer::compareByNextFireTime(OOScriptTimer* other)
{
    OOTimeAbsolute otherTime = -INFINITY;

    // The old body read [other nextTime] inside a try block, logging and ignoring an OOException. It is a
    // plain C++ getter now, which cannot throw, so the handler is gone.
    if (other != nullptr)
        otherTime = other->nextTime();

    if (_nextTime < otherTime)
        return OOOrderedAscending;
    else if (_nextTime > otherTime)
        return OOOrderedDescending;
    else
        return OOOrderedSame;
}

} // namespace cxx
