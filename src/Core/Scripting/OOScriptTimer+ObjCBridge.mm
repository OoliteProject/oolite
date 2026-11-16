/*

OOScriptTimer+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, bead oo-kdyh): the Objective-C OOScriptTimer facade; see
OOScriptTimer+ObjCBridge.h. Each method forwards in one line to cxx::OOScriptTimer.


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

#include "oofnd/objc/OOObjCPeer.h"
#include "oofnd/objc/OORuntime.h"

#include <cstdlib>
#include <cxxabi.h>
#include <typeinfo>

namespace {

// Never destroyed: a facade may be released while the process exits.
oo::ObjCPeers& Peers()
{
    static oo::ObjCPeers* peers = new oo::ObjCPeers;
    return *peers;
}

/*	The class of a timer's facade: the Objective-C class named like its C++ class, when that is a
        subclass of this one (cxx::OOJSTimer's is OOJSTimer, which answers the JavaScript glue), else
        OOScriptTimer (ADR-0056 amendment oo-up4b item 3).
*/
Class FacadeClass(cxx::OOScriptTimer& timer)
{
    int status = 0;
    char* demangled = abi::__cxa_demangle(typeid(timer).name(), nullptr, nullptr, &status);
    const std::string name = (status == 0 && demangled != nullptr) ? demangled : typeid(timer).name();
    std::free(demangled);
    if (name.starts_with("cxx::")) {
        Class facade = OOClassFromName(std::string_view(name).substr(5));
        if (facade != Nil && [facade isSubclassOfClass:[OOScriptTimer class]])
            return facade;
    }
    return [OOScriptTimer class];
}

} // namespace

@interface OOScriptTimer (OOObjCBridgePrivate)

// For oo::ToObjC, under the peer table's lock: stores the C++ object.
- (id)initWithCxxTimer:(cxx::OOScriptTimer*)timer;

// For the initialisers: releases self and answers nil for null, else stores the new C++ object
// and records the facade as its peer (amendment oo-bhb9 item 3).
- (id)initWithNewCxxTimer:(const oo::Ref<cxx::OOScriptTimer>&)timer;

@end

@implementation OOScriptTimer

// Inside the @implementation for the private ivar.
::OOScriptTimer* oo::ToObjC(cxx::OOScriptTimer* timer)
{
    if (timer == nullptr)
        return nil;
    Class facadeClass = FacadeClass(*timer);
    return Peers().peerFor(timer, [timer, facadeClass] { return [[facadeClass alloc] initWithCxxTimer:timer]; });
}

::OOScriptTimer* oo::LiveObjC(cxx::OOScriptTimer* timer)
{
    return Peers().peerFor(timer, [] { return (id)nil; });
}

cxx::OOScriptTimer* oo::ToCxx(::OOScriptTimer* timer)
{
    if (timer == nil)
        return nullptr;
    return timer->_cxxTimer.get();
}

- (id)initWithCxxTimer:(cxx::OOScriptTimer*)timer
{
    self = [super init];
    if (self != nil)
        _cxxTimer = oo::Ref<cxx::OOScriptTimer>(timer);
    return self;
}

- (id)initWithNewCxxTimer:(const oo::Ref<cxx::OOScriptTimer>&)timer
{
    if (timer == nullptr) {
        [self release];
        return nil;
    }
    self = [super init];
    if (self != nil) {
        _cxxTimer = timer;
        @autoreleasepool {
            Peers().peerFor(_cxxTimer.get(), [self] { return [self retain]; });
        }
    }
    return self;
}

- (id)initWithNextTime:(OOTimeAbsolute)nextTime
              interval:(OOTimeDelta)interval
{
    return [self initWithNewCxxTimer:cxx::OOScriptTimer::timerWithNextTime(nextTime, interval)];
}

- (id)initOneShotTimerWithDelay:(OOTimeDelta)delay
{
    return [self initWithNewCxxTimer:cxx::OOScriptTimer::oneShotTimerWithDelay(delay)];
}

- (void)dealloc
{
    Peers().forget(_cxxTimer.get());
    [super dealloc];
}

- (std::optional<std::string>)cxx_descriptionComponents
{
    return _cxxTimer->descriptionComponents();
}
- (OOTimeAbsolute)nextTime
{
    return _cxxTimer->nextTime();
}
- (BOOL)setNextTime:(OOTimeAbsolute)nextTime
{
    return _cxxTimer->setNextTime(nextTime);
}
- (OOTimeDelta)interval
{
    return _cxxTimer->interval();
}
- (void)setInterval:(OOTimeDelta)interval
{
    _cxxTimer->setInterval(interval);
}
- (void)timerFired
{
    _cxxTimer->timerFired();
}
- (BOOL)scheduleTimer
{
    return _cxxTimer->scheduleTimer();
}
- (void)unscheduleTimer
{
    _cxxTimer->unscheduleTimer();
}
- (BOOL)isScheduled
{
    return _cxxTimer->isScheduled();
}
+ (void)updateTimers
{
    cxx::OOScriptTimer::updateTimers();
}
+ (void)noteGameReset
{
    cxx::OOScriptTimer::noteGameReset();
}
- (BOOL)isValidForScheduling
{
    return _cxxTimer->isValidForScheduling();
}
- (OOComparisonResult)compareByNextFireTime:(OOScriptTimer*)other
{
    return _cxxTimer->compareByNextFireTime(oo::ToCxx(other));
}

@end
