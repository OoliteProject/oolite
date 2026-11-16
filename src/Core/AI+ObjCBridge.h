/*

AI+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056 and its amendment oo-o89; bead oo-puw9): the Objective-C AI, a
facade over the C++ cxx::AI (AI.h). Its interface is the one AI.h declared before the conversion,
copied exactly (same selectors, same types, same superclass), so its callers compile and behave
unchanged. Imported as the last line of AI.h; do not import it directly.

Its superclass, OOWeakRefObject, is still Objective-C and keeps state (the weak reference ships
and others hold to the AI), so the facade is the AI's identity: it makes and owns its C++ object
in -init, and the pair lives and dies together.

        direction                      crosses with                what it gives
        -----------------------------  --------------------------  -------------------------------------
        C++ -> Objective-C             oo::ToObjC(ai)              the live facade; never a new one, so
                                                                   nil once it is gone
        Objective-C -> C++             oo::ToCxx(ai)               the borrowed C++ object; null for nil

The deferred-call holder (OOAIDeferredCallTrampolineInfoHolder) is an Objective-C object that
OOScheduleDeferredCall() retains, and the call's target is the facade's class method
+deferredCallTrampolineWithInfo:, so both are here (amendment oo-rmd7 item 1).

Never add to this file; converted code does not message the facade. Deleted by its deletion bead
once no caller messages AI and OOWeakRefObject's subclasses are C++ (amendment oo-3kqi item 6).

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

#ifndef AI_OBJCBRIDGE_H
#define AI_OBJCBRIDGE_H

#import "OOFoundation.h"
#import "OOTypes.h"
#import "OOWeakReference.h"

@interface AI : OOWeakRefObject {
@private
    oo::Ref<cxx::AI> _cxxAI;
}

+ (AI*)currentlyRunningAI;
+ (std::optional<std::string>)cxx_currentlyRunningAIDescription;

- (std::optional<std::string>)cxx_name; // the state machine's name (bead oo-3rb.289.8)
- (std::optional<std::string>)cxx_associatedJS;
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

typedef struct
{
    AI* ai;
    SEL selector;
    std::string parameter; // the by-name call's string argument (OOCallByName.h)
} OOAIDeferredCallTrampolineInfo;

/*	Carries the trampoline info through OOScheduleDeferredCall(),
        which retains it until the call fires, as it did the value box that held the
        struct before (bead oo-3rb.48).
*/
@interface OOAIDeferredCallTrampolineInfoHolder : OOObject {
@public
    OOAIDeferredCallTrampolineInfo info;
}
@end

namespace oo {

// The AI's live facade (autoreleased), or nil: never a new one (see above). nil for null.
AI* ToObjC(cxx::AI* ai);

// The C++ AI behind a facade, borrowed (the facade owns it); null for nil.
cxx::AI* ToCxx(AI* ai);

} // namespace oo

#endif // AI_OBJCBRIDGE_H
