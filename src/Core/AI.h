/*

AI.h

Core NPC behaviour/artificial intelligence class.

C++20 since bead oo-puw9 (proposed ADR-0056; its superclass is still Objective-C, amendment
oo-o89). The AI is cxx::AI. Its superclass, OOWeakRefObject, is still Objective-C (ships hold
their AI and weak references to it through that object), so the Objective-C AI in
AI+ObjCBridge.h (imported at the end of this header) stays the object its callers hold. It makes
and owns the C++ object in its -init, and oo::ToObjC answers that one facade, never a new one.
The AI sends its owner's object its actions by name, as before; the owner is the C++ ShipEntity
since bead oo-9ht.144, whose object the AI holds by weak reference.

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

#import "OOFoundation.h"
#import "OOTypes.h"
#import "OOWeakReference.h"

#include "oofnd/PList.hpp"
#include "oofnd/Ref.hpp"
#include "oofnd/StdLib.hpp"
#include "oofnd/objc/OOObjCRef.h"

#define AI_THINK_INTERVAL 0.125

class ShipEntity; // C++ since bead oo-9ht.144
class OOPreservedAIStateMachine; // private to AI.mm; no facade, so global (amendment oo-fn2f item 4)

namespace cxx {

class AI : public oo::RefCounted {
public:
    AI(); // -init
    ~AI() override; // -dealloc

    static AI* currentlyRunningAI(); // borrowed; null: none
    static std::optional<std::string> currentlyRunningAIDescription();

    // -cxx_initWithStateMachine:andState:'s body after its [self init]. The facade runs it once it is
    // the object's peer (std::nullopt where the Foundation version took nil).
    void initWithStateMachine(const std::optional<std::string>& smName, const std::optional<std::string>& stateName);

    std::optional<std::string> descriptionComponents() const;
    std::optional<std::string> shortDescriptionComponents() const;

    std::optional<std::string> name(); // the state machine's name (bead oo-3rb.289.8)
    std::optional<std::string> associatedJS();
    std::optional<std::string> state(); // the current state; nullopt: none (bead oo-3rb.291.2)

    void setStateMachine(const std::string& smName, const std::string& script); // -cxx_setStateMachine:withJSScript:
    void setState(const std::string& stateName);

    void setStateMachine(const std::string& smName, NSTimeInterval delay); // -cxx_setStateMachine:afterDelay:
    void setState(const std::string& stateName, NSTimeInterval delay); // -cxx_setState:afterDelay:

    ::ShipEntity* owner();
    void setOwner(::ShipEntity* ship);

    void preserveCurrentStateMachine();

    void restorePreviousStateMachine();

    bool hasSuspendedStateMachines();
    void exitStateMachineWithMessage(const std::optional<std::string>& message); // nullopt: "RESTARTED"

    NSUInteger stackDepth();

    // Immediately handle a message. This is the core dispatcher. DebugContext is a textual hint for
    // diagnostics (std::nullopt where the Foundation version took nil).
    void reactToMessage(const std::string& message, const std::optional<std::string>& debugContext);

    void takeAction(const std::string& action);

    void think();

    void message(const std::string& ms);
    void dropMessage(const std::string& ms);
    std::set<std::string> getPendingMessages(); // -pendingMessages, in byte order (amendment oo-862e item 1)
    void debugDumpPendingMessages();

    void setNextThinkTime(OOTimeAbsolute ntt);
    OOTimeAbsolute getNextThinkTime(); // -nextThinkTime

    void setThinkTimeInterval(OOTimeDelta tti);
    OOTimeDelta getThinkTimeInterval(); // -thinkTimeInterval

    void clearStack();

    void clearAllData();

    void dumpState();

    // The target of setState(stateName, delay)'s deferred call, which the facade's -deferredSetState:
    // (called by name) forwards here.
    void deferredSetState(const std::string& stateName);

private:
    void reportStackOverflow();

    // Wrapper for a deferred call (OOScheduleDeferredCall) to catch/fix bugs. <selector> is called by
    // name with <argument> (OOCallByName.h).
    void performDeferredCall(SEL selector, const std::string& argument, NSTimeInterval delay);

    void refreshOwnerDesc();

    // Set state machine and state without side effects. A nullopt state is no state (nil).
    void directSetStateMachine(const oo::PList& newSM, const std::string& name);
    void directSetState(const std::optional<std::string>& state);

    // Loading/whitelisting. A null result is no state machine (nil).
    oo::PList loadStateMachine(const std::string& smName, const std::string& script);
    oo::PList cleanHandlers(const oo::PList& handlers, const std::string& stateKey, const std::string& smName);
    oo::PList cleanActions(const oo::PList& actions, const std::string& handlerKey, const std::string& stateKey, const std::string& smName);

    oo::ObjCRef<id> _owner = { }; // OOWeakReference to the object of the ShipEntity this is the AI for
    std::optional<std::string> ownerDesc = { }; // describes the object this is the AI for; nullopt until it has an owner

    oo::PList stateMachine = { }; // the loaded, whitelisted state machine; null: none (nil)
    std::string stateMachineName = { };
    std::optional<std::string> currentState = { }; // nullopt: no state (nil)
    std::set<std::string> pendingMessages = { }; // in byte order (a Foundation set before)

    std::vector<oo::Ref<OOPreservedAIStateMachine>> aiStack = { };

    OOTimeAbsolute nextThinkTime = { };
    OOTimeDelta thinkTimeInterval = { };

    std::optional<std::string> jsScript = { };
};

} // namespace cxx

// Transitional: the Objective-C AI, the object ships hold. Deleted, with namespace cxx above, by the
// bridge's deletion bead once OOWeakRefObject's subclasses are C++ and no caller messages AI.
#import "AI+ObjCBridge.h"
