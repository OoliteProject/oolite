/*

AI+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056 and its amendment oo-o89; bead oo-puw9): the Objective-C AI
facade, and the deferred-call holder and trampoline. See AI+ObjCBridge.h.

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

#import "AI.h"
#import "OOCallByName.h"

#include "oofnd/objc/OOObjCPeer.h"

namespace {

// Never destroyed: a facade may be released while the process exits.
oo::ObjCPeers& Peers()
{
    static oo::ObjCPeers* peers = new oo::ObjCPeers;
    return *peers;
}

} // namespace

@implementation OOAIDeferredCallTrampolineInfoHolder
@end

@interface AI (OOPrivate)

// The deferred call's target, and the method it calls by name (OOCallByName.h).
+ (void)deferredCallTrampolineWithInfo:(OOAIDeferredCallTrampolineInfoHolder*)info;
- (void)deferredSetState:(const std::string&)stateName;

@end

@implementation AI

// Inside the @implementation for the private ivar.
AI* oo::ToObjC(cxx::AI* ai)
{
    return Peers().peerFor(ai, [] { return (id)nil; });
}

cxx::AI* oo::ToCxx(AI* ai)
{
    if (ai == nil)
        return nullptr;
    return ai->_cxxAI.get();
}

+ (AI*)currentlyRunningAI
{
    return oo::ToObjC(cxx::AI::currentlyRunningAI());
}

+ (std::optional<std::string>)cxx_currentlyRunningAIDescription
{
    return cxx::AI::currentlyRunningAIDescription();
}

- (id)init
{
    self = [super init];
    if (self != nil) {
        _cxxAI = oo::makeRef<cxx::AI>();
        @autoreleasepool {
            Peers().peerFor(_cxxAI.get(), [self] { return [self retain]; });
        }
    }
    return self;
}

- (id)cxx_initWithStateMachine:(const std::optional<std::string>&)smName andState:(const std::optional<std::string>&)stateName
{
    self = [self init];
    if (self != nil)
        _cxxAI->initWithStateMachine(smName, stateName);
    return self;
}

- (void)dealloc
{
    Peers().forget(_cxxAI.get());
    [super dealloc];
}

- (std::optional<std::string>)cxx_descriptionComponents
{
    return _cxxAI->descriptionComponents();
}
- (std::optional<std::string>)cxx_shortDescriptionComponents
{
    return _cxxAI->shortDescriptionComponents();
}

- (std::optional<std::string>)cxx_name
{
    return _cxxAI->name();
}
- (std::optional<std::string>)cxx_associatedJS
{
    return _cxxAI->associatedJS();
}
- (std::optional<std::string>)cxx_state
{
    return _cxxAI->state();
}

- (void)cxx_setStateMachine:(const std::string&)smName withJSScript:(const std::string&)script
{
    _cxxAI->setStateMachine(smName, script);
}
- (void)cxx_setState:(const std::string&)stateName
{
    _cxxAI->setState(stateName);
}
- (void)cxx_setStateMachine:(const std::string&)smName afterDelay:(NSTimeInterval)delay
{
    _cxxAI->setStateMachine(smName, delay);
}
- (void)cxx_setState:(const std::string&)stateName afterDelay:(NSTimeInterval)delay
{
    _cxxAI->setState(stateName, delay);
}

- (ShipEntity*)owner
{
    return _cxxAI->owner();
}
- (void)setOwner:(ShipEntity*)ship
{
    _cxxAI->setOwner(ship);
}

- (void)preserveCurrentStateMachine
{
    _cxxAI->preserveCurrentStateMachine();
}
- (void)restorePreviousStateMachine
{
    _cxxAI->restorePreviousStateMachine();
}
- (BOOL)hasSuspendedStateMachines
{
    return _cxxAI->hasSuspendedStateMachines();
}
- (void)cxx_exitStateMachineWithMessage:(const std::optional<std::string>&)message
{
    _cxxAI->exitStateMachineWithMessage(message);
}
- (NSUInteger)stackDepth
{
    return _cxxAI->stackDepth();
}

- (void)cxx_reactToMessage:(const std::string&)message context:(const std::optional<std::string>&)debugContext
{
    _cxxAI->reactToMessage(message, debugContext);
}
- (void)cxx_takeAction:(const std::string&)action
{
    _cxxAI->takeAction(action);
}
- (void)think
{
    _cxxAI->think();
}

- (void)message:(const std::string&)ms
{
    _cxxAI->message(ms);
}
- (void)cxx_dropMessage:(const std::string&)ms
{
    _cxxAI->dropMessage(ms);
}
- (std::set<std::string>)pendingMessages
{
    return _cxxAI->getPendingMessages();
}
- (void)debugDumpPendingMessages
{
    _cxxAI->debugDumpPendingMessages();
}

- (void)setNextThinkTime:(OOTimeAbsolute)ntt
{
    _cxxAI->setNextThinkTime(ntt);
}
- (OOTimeAbsolute)nextThinkTime
{
    return _cxxAI->getNextThinkTime();
}
- (void)setThinkTimeInterval:(OOTimeDelta)tti
{
    _cxxAI->setThinkTimeInterval(tti);
}
- (OOTimeDelta)thinkTimeInterval
{
    return _cxxAI->getThinkTimeInterval();
}

- (void)clearStack
{
    _cxxAI->clearStack();
}
- (void)clearAllData
{
    _cxxAI->clearAllData();
}
- (void)dumpState
{
    _cxxAI->dumpState();
}

@end

/*	This is an attempt to fix the bugs referred to above regarding calls from
        __NSFireDelayedPerform with a corrupt self. I'm not certain whether this
        will fix the issue or merely cause a less weird crash in
        +deferredCallTrampolineWithInfo:.
        -- Ahruman 20070706
*/
@implementation AI (OOPrivate)

- (void)deferredSetState:(const std::string&)stateName
{
    _cxxAI->deferredSetState(stateName);
}

+ (void)deferredCallTrampolineWithInfo:(OOAIDeferredCallTrampolineInfoHolder*)info
{
    OOAIDeferredCallTrampolineInfo infoStruct;

    if (info != nil) {
        infoStruct = info->info;

        OOCallByName(infoStruct.ai, infoStruct.selector, infoStruct.parameter);

        [infoStruct.ai release];
    }
}

@end
