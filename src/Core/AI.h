/*

AI.h

Core NPC behaviour/artificial intelligence class.

C++20 since bead oo-puw9 (proposed ADR-0056). Bead oo-9ht.73 deleted its Objective-C facade
(amendment oo-9ht.73): the AI is the global C++ class AI, held as oo::Ref<AI>, and a
deferred call holds it. The AI sends its owner's object its actions by name, as before; the owner is
the C++ ShipEntity since bead oo-9ht.144, which the AI holds by weak reference (oo::WeakRef).

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

#pragma once

#include "OOCocoa.h"
#include "OOTypes.h"

#include "oofnd/StdLib.hpp"
#include "oofnd/PList.hpp"
#include "oofnd/Ref.hpp"

#define AI_THINK_INTERVAL					0.125


class ShipEntity;	// C++ since bead oo-9ht.144
class Entity;
class OOPreservedAIStateMachine;	// private to AI.mm; no facade, so global (amendment oo-fn2f item 4)


/*	A ship's AI: C++ only since bead oo-9ht.73 deleted its Objective-C facade (proposed ADR-0056,
	amendment oo-9ht.73). Held as oo::Ref<AI>; a ship's shipAI owns it.
*/
class AI : public oo::RefCounted
{
public:
	AI();		// -init
	~AI() override;	// -dealloc

	// [[AI alloc] cxx_initWithStateMachine:andState:]: a new AI running the state machine (nullopt:
	// none) in the state (nullopt: none).
	static oo::Ref<AI> newWithStateMachine(const std::optional<std::string> &smName, const std::optional<std::string> &stateName);

	// What -description and -shortDescription printed: <AI 0xnnnnnnnn>{components}, the address the
	// C++ object's where it was the facade's.
	std::string description() const;
	std::string shortDescription() const;

	static AI *currentlyRunningAI();	// borrowed; null: none (+currentlyRunningAI)
	static std::optional<std::string> currentlyRunningAIDescription();

	// -cxx_initWithStateMachine:andState:'s body after its [self init] (std::nullopt where the
	// Foundation version took nil); newWithStateMachine() runs it.
	void initWithStateMachine(const std::optional<std::string> &smName, const std::optional<std::string> &stateName);

	std::optional<std::string> descriptionComponents() const;
	std::optional<std::string> shortDescriptionComponents() const;

	std::optional<std::string> name();	// the state machine's name (bead oo-3rb.289.8)
	std::optional<std::string> associatedJS();
	std::optional<std::string> state();	// the current state; nullopt: none (bead oo-3rb.291.2)

	void setStateMachine(const std::string &smName, const std::string &script);	// -cxx_setStateMachine:withJSScript:
	void setState(const std::string &stateName);

	void setStateMachine(const std::string &smName, NSTimeInterval delay);	// -cxx_setStateMachine:afterDelay:
	void setState(const std::string &stateName, NSTimeInterval delay);		// -cxx_setState:afterDelay:

	::ShipEntity *owner();
	void setOwner(::ShipEntity *ship);

	void preserveCurrentStateMachine();

	void restorePreviousStateMachine();

	bool hasSuspendedStateMachines();
	void exitStateMachineWithMessage(const std::optional<std::string> &message);	// nullopt: "RESTARTED"

	NSUInteger stackDepth();

	// Immediately handle a message. This is the core dispatcher. DebugContext is a textual hint for
	// diagnostics (std::nullopt where the Foundation version took nil).
	void reactToMessage(const std::string &message, const std::optional<std::string> &debugContext);

	void takeAction(const std::string &action);

	void think();

	void message(const std::string &ms);
	void dropMessage(const std::string &ms);
	std::set<std::string> getPendingMessages();	// -pendingMessages, in byte order (amendment oo-862e item 1)
	void debugDumpPendingMessages();

	void setNextThinkTime(OOTimeAbsolute ntt);
	OOTimeAbsolute getNextThinkTime();	// -nextThinkTime

	void setThinkTimeInterval(OOTimeDelta tti);
	OOTimeDelta getThinkTimeInterval();	// -thinkTimeInterval

	void clearStack();

	void clearAllData();

	void dumpState();

	// The target of setState(stateName, delay)'s deferred call, found in the deferred calls' name
	// table (AI.mm) where the facade's -deferredSetState: was found by name.
	void deferredSetState(const std::string &stateName);

private:
	void reportStackOverflow();

	// Wrapper for a deferred call (OOScheduleDeferredCall) to catch/fix bugs. <selectorName> is found
	// in the deferred calls' name table (AI.mm) and called with <argument>.
	void performDeferredCall(const char *selectorName, const std::string &argument, NSTimeInterval delay);

	void refreshOwnerDesc();

	// Set state machine and state without side effects. A nullopt state is no state (nil).
	void directSetStateMachine(const oo::PList &newSM, const std::string &name);
	void directSetState(const std::optional<std::string> &state);

	// Loading/whitelisting. A null result is no state machine (nil).
	oo::PList loadStateMachine(const std::string &smName, const std::string &script);
	oo::PList cleanHandlers(const oo::PList &handlers, const std::string &stateKey, const std::string &smName);
	oo::PList cleanActions(const oo::PList &actions, const std::string &handlerKey, const std::string &stateKey, const std::string &smName);

	oo::WeakRef<Entity>	_owner = {};			// the ShipEntity this is the AI for, weakly (a weak reference proxy to its object before bead oo-9ht.73)
	std::optional<std::string>	ownerDesc = {};		// describes the object this is the AI for; nullopt until it has an owner

	oo::PList			stateMachine = {};			// the loaded, whitelisted state machine; null: none (nil)
	std::string			stateMachineName = {};
	std::optional<std::string>	currentState = {};	// nullopt: no state (nil)
	std::set<std::string>	pendingMessages = {};	// in byte order (a Foundation set before)

	std::vector<oo::Ref<OOPreservedAIStateMachine>>	aiStack;	// no `= {}`: GCC instantiates ~Ref<T> at a default member initializer, and T is incomplete here (bead oo-1q4)

	OOTimeAbsolute		nextThinkTime = {};
	OOTimeDelta			thinkTimeInterval = {};

	std::optional<std::string>	jsScript = {};
};


/*	[ai autorelease], which the deleted facade answered (bead oo-9ht.73): keeps the AI until the
	current autorelease pool drains, so an AI a ship lets go of (replaced, or the ship set up again)
	while it may still be running lives exactly as long as its autoreleased object did. Nothing for
	null.
*/
void OOAIAutorelease(oo::Ref<AI> ai);
