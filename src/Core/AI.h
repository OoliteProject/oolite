/*

AI.h

Core NPC behaviour/artificial intelligence class.

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

#import "OOTypes.h"
#import "OOWeakReference.h"
#import <Foundation/Foundation.h>

#include "oofnd/PList.hpp"
#include "oofnd/StdLib.hpp"
#include "oofnd/objc/OOObjCRef.h"

#define AI_THINK_INTERVAL 0.125

@class ShipEntity, OOPreservedAIStateMachine;

@interface AI : OOWeakRefObject {
@private
    id _owner; // OOWeakReference to the ShipEntity this is the AI for
    std::optional<std::string> ownerDesc; // describes the object this is the AI for; nullopt until it has an owner

    oo::PList stateMachine; // the loaded, whitelisted state machine; null: none (nil)
    std::string stateMachineName;
    std::optional<std::string> currentState; // nullopt: no state (nil)
    std::set<std::string> pendingMessages; // in byte order (a Foundation set before)

    std::vector<oo::ObjCRef<OOPreservedAIStateMachine*>> aiStack;

    OOTimeAbsolute nextThinkTime;
    OOTimeDelta thinkTimeInterval;

    std::optional<std::string> jsScript;
}

+ (AI*)currentlyRunningAI;
+ (std::optional<std::string>)cxx_currentlyRunningAIDescription;

- (id)name; // shared selector (proposed ADR-0043): the state machine's name, an Objective-C string
- (std::optional<std::string>)cxx_associatedJS;
- (id)state; // shared selector (Foundation declares -state too): -cxx_state as an Objective-C string or nil
- (std::optional<std::string>)cxx_state; // the current state; nullopt: none (bead oo-3rb.291.2)

- (void)cxx_setStateMachine:(const std::string&)smName withJSScript:(const std::string&)script;
- (void)cxx_setState:(const std::string&)stateName;

- (void)cxx_setStateMachine:(const std::string&)smName afterDelay:(NSTimeInterval)delay;
- (void)cxx_setState:(const std::string&)stateName afterDelay:(NSTimeInterval)delay;

// std::nullopt where the Foundation version took nil (no state machine / no initial state). An
// initializer outside the init family by name, so the ownership it returns (+1) is declared.
- (id)cxx_initWithStateMachine:(const std::optional<std::string>&)smName andState:(const std::optional<std::string>&)stateName OO_RETURNS_RETAINED;

- (ShipEntity*)owner;
- (void)setOwner:(ShipEntity*)ship;

- (void)preserveCurrentStateMachine;

- (void)restorePreviousStateMachine;

- (BOOL)hasSuspendedStateMachines;
- (void)cxx_exitStateMachineWithMessage:(const std::optional<std::string>&)message; // nullopt: "RESTARTED"

- (NSUInteger)stackDepth;

// Immediately handle a message. This is the core dispatcher. DebugContext is a textual hint for
// diagnostics (std::nullopt where the Foundation version took nil).
- (void)cxx_reactToMessage:(const std::string&)message context:(const std::optional<std::string>&)debugContext;

- (void)cxx_takeAction:(const std::string&)action;

- (void)think;

- (void)message:(const std::string&)ms; // flipped with its family (bead oo-3rb.276)
- (void)cxx_dropMessage:(const std::string&)ms;
- (std::set<std::string>)pendingMessages; // in byte order
- (void)debugDumpPendingMessages;

- (void)setNextThinkTime:(OOTimeAbsolute)ntt;
- (OOTimeAbsolute)nextThinkTime;

- (void)setThinkTimeInterval:(OOTimeDelta)tti;
- (OOTimeDelta)thinkTimeInterval;

- (void)clearStack;

- (void)clearAllData;

- (void)dumpState;

@end

/*	TRANSITIONAL (proposed ADR-0043, "Transitional bridges"): the Foundation-typed API this header
        declared before the AI.mm sweep (beads oo-3rb.84-87, oo-gtl8), forwarding to the cxx_ methods
        above, so unmigrated callers compile unchanged. Callers move to the cxx_ API in their own sweep
        beads; the bridge goes in its own bead.
*/
#import "AI+FoundationBridge.h"
