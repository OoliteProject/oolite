/*

AI.m

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

#include "AI.h"
#include "ResourceManager.h"
#include "OOStringParsing.h"
#include "OOCacheManager.h"
#include "OOCallByName.h"
#include "OOPListParsing.h"

#include "ShipEntity.h"
#include "ShipEntityAI.h"
#include "GameController.h"
#include "oofnd/objc/OOException.h"
#include "oofnd/objc/OOObject.h"

#include "oofnd/Log.hpp"
#include "oofnd/String.hpp"
#include "oofnd/Scanner.hpp"

#include <cstring>
#include <functional>
#include "oofnd/Ref.hpp"	// oo::autorelease (beads oo-pvhrh, oo-31u.7)


enum
{
	kRecursionLimiter		= 32,	// reactToMethod: recursion
	kStackLimiter			= 32	// setAITo: stack overflow
};






namespace {

AI *sCurrentlyRunningAI = nullptr;


// OODictionaryFromFile(OOPListParsing's bridge) as a property list: the file's
// property list when it is a dictionary, a null PList otherwise (its plist.wrongType log line,
// which named the Foundation class, is not kept).
oo::PList PListDictionaryFromFile(const std::string &path)
{
	oo::PList result = cxx_OOPropertyListFromFile(path);
	return result.isDict() ? result : oo::PList();
}


// The state machine's "jsScript" entry, a null PList if it has none (where
// -objectForKey:@"jsScript" answered nil).
oo::PList JSScriptOf(const oo::PList &stateMachine)
{
	const oo::PList *script = stateMachine.find("jsScript");
	return script != nullptr ? *script : oo::PList();
}


// The pending messages as -description of an NSSet of them printed them (GNUstep describes a set
// as the array of its objects), in byte order where that was the set's hash order.
std::string PendingMessagesDescription(const std::set<std::string> &messages)
{
	oo::PList::Array list;
	for (const std::string &message : messages)  list.emplace_back(message);
	return oo::DescriptionOf(oo::PList(std::move(list)));
}


/*	The AI's methods a deferred call names, by the selector the by-name call (OOCallByName) used:
	exactly the names the facade answered (bead oo-9ht.73). setStateMachine(smName, delay) names
	-setStateMachine:, which the facade did not answer (the ship's selector), so it is not here and
	its call logs and does nothing, as before.
*/
struct DeferredAIMethod
{
	const char	*selectorName;
	void		(AI::*method)(const std::string &argument);
};

const DeferredAIMethod kDeferredAIMethods[] =
{
	{ "deferredSetState:", &AI::deferredSetState },
};

} // namespace


/*	OOAIAutorelease(): the AI goes to the innermost oo::AutoreleaseScope, whose drain releases it where
	the keeper object that held it was released (beads oo-pvhrh, oo-31u.7).
*/

void OOAIAutorelease(oo::Ref<AI> ai)
{
	if (ai == nullptr)  return;
	oo::autorelease(std::move(ai));
}


/*	A deferred call's body (bead oo-9ht.73; a C++ call since bead oo-pvhrh, where the Objective-C
	holder OOAIDeferredCall's -fire was the target): calls the method the selector named, found in
	kDeferredAIMethods by the name the by-name call used.
*/
namespace {

void FireAIDeferredCall(AI *ai, const char *selectorName, const std::string &parameter)
{
	for (const DeferredAIMethod &entry : kDeferredAIMethods)
	{
		if (strcmp(entry.selectorName, selectorName) == 0)
		{
			(ai->*entry.method)(parameter);
			return;
		}
	}
	// The by-name call's line for a selector its target did not answer (OOCallByName.mm LogUnknown).
	OO_LOG_ERR("callByName.unknownSelector", "{} does not respond to {}.", "AI", selectorName);
}

}


#if DEBUG_GRAPHVIZ
#include "AIGraphViz.h"
#include "oofnd/Defaults.hpp"
#endif


class OOPreservedAIStateMachine : public oo::RefCounted
{
public:
	OOPreservedAIStateMachine(const oo::PList &stateMachine,
						   const std::string &name,
						  const std::optional<std::string> &state,
			const std::set<std::string> &pendingMessages,
									 const std::optional<std::string> &script);

	oo::PList stateMachine();
	std::optional<std::string> name();	// (bead oo-3rb.289.8)
	std::optional<std::string> state();
	std::set<std::string> pendingMessages();
	std::optional<std::string> jsScript();

private:
	oo::PList					_stateMachine = {};
	std::string					_name = {};
	std::optional<std::string>	_state = {};
	std::set<std::string>		_pendingMessages = {};
	std::optional<std::string>	_jsScript = {};
};


oo::Ref<AI> AI::newWithStateMachine(const std::optional<std::string> &smName, const std::optional<std::string> &stateName)
{
	oo::Ref<AI> ai = oo::makeRef<AI>();
	ai->initWithStateMachine(smName, stateName);
	return ai;
}


std::string AI::description() const
{
	std::string result = oo::str::format("<AI %s>", oo::str::pointerDescription(this).c_str());
	const std::optional<std::string> components = descriptionComponents();
	if (components.has_value())  result += "{" + *components + "}";
	return result;
}


std::string AI::shortDescription() const
{
	std::string result = oo::str::format("<AI %s>", oo::str::pointerDescription(this).c_str());
	const std::optional<std::string> components = shortDescriptionComponents();
	if (components.has_value())  result += "{" + *components + "}";
	return result;
}


AI *AI::currentlyRunningAI()
{
	return sCurrentlyRunningAI;
}


std::optional<std::string> AI::currentlyRunningAIDescription()
{
	if (sCurrentlyRunningAI != nullptr)
	{
		return oo::str::format("%s in state %s", sCurrentlyRunningAI->name().value_or("(null)").c_str(), sCurrentlyRunningAI->state().value_or("(null)").c_str());
	}
	else
	{
		return "<no AI running>";
	}
}


AI::AI()
{
	{
		nextThinkTime = INFINITY;	// don't think for a while
		thinkTimeInterval = AI_THINK_INTERVAL;

		stateMachineName = "<no AI>";	// no initial brain
	}
}


void AI::initWithStateMachine(const std::optional<std::string> &smName, const std::optional<std::string> &stateName)
{
	{
		if (smName.has_value())  setStateMachine(*smName, "oolite-nullAI.js");
		if (stateName.has_value())  currentState = *stateName;
	}
}


AI::~AI()
{
	if (sCurrentlyRunningAI == this)
	{
		sCurrentlyRunningAI = nullptr;
	}

	_owner = nullptr;
}


std::optional<std::string> AI::descriptionComponents() const
{
	return oo::str::format("\"%s\" in state: \"%s\" for %s", stateMachineName.c_str(), currentState.value_or("(null)").c_str(), ownerDesc.value_or("(null)").c_str());
}


std::optional<std::string> AI::shortDescriptionComponents() const
{
	return oo::str::format("%s:%s / %s", stateMachineName.c_str(), currentState.value_or("(null)").c_str(), oo::DescriptionOf(JSScriptOf(stateMachine)).c_str());
}


::ShipEntity *AI::owner()
{
	// Only a ship is ever the owner (setOwner()).
	::ShipEntity		*owner = static_cast<::ShipEntity *>(_owner.get());
	if (owner == nil)
	{
		_owner = nullptr;
	}
	
	return owner;
}


void AI::setOwner(::ShipEntity *ship)
{
	_owner = ship;
	refreshOwnerDesc();
}


void AI::reportStackOverflow()
{
	if (oo::log::willDisplay("ai.error.stackOverflow"))
	{
		BOOL stackDump = oo::log::willDisplay("ai.error.stackOverflow.dump");
		
		const char *trailer = stackDump ? " -- stack:" : ".";
		OO_LOG_ERR("ai.error.stackOverflow", "AI stack overflow for {} in {}: {}{}\n", oo::EntityShortDescription(owner()), stateMachineName, currentState.value_or("(null)"), trailer);

		if (stackDump)
		{
			OOLogIndent();

			std::size_t count = aiStack.size();
			while (count--)
			{
				OOPreservedAIStateMachine *preservedMachine = aiStack[count].get();
				OO_LOG("ai.error.stackOverflow.dump", "{}: {}: {}", count, preservedMachine->name().value_or("(null)"), preservedMachine->state().value_or("(null)"));
			}
			
			OOLogOutdent();
		}
	}
}


void AI::preserveCurrentStateMachine()
{
	if (stateMachine.isNull())  return;
	
	if (aiStack.size() >= kStackLimiter)
	{
		reportStackOverflow();

		OORaiseException("OoliteException", "AI stack overflow for %s", oo::EntityDescription(owner()).c_str());
	}
	
	const oo::PList *script = stateMachine.find("jsScript");
	oo::Ref<OOPreservedAIStateMachine> preservedMachine = oo::makeRef<OOPreservedAIStateMachine>(
												   stateMachine,
																   stateMachineName,
																  currentState,
														pendingMessages,
																									(script != nullptr && script->isString()) ? std::optional<std::string>(*script->getIf<std::string>()) : std::nullopt);
	
#ifndef NDEBUG
	if ((owner() != nullptr ? owner()->getReportAIMessages() : false))  OO_LOG("ai.stack.push", "Pushing state machine for {}", description());
#endif
	
	aiStack.push_back(std::move(preservedMachine));  // PUSH
}


void AI::restorePreviousStateMachine()
{
	if (aiStack.empty())  return;

	const oo::Ref<OOPreservedAIStateMachine> preservedMachine = aiStack.back();
	
#ifndef NDEBUG
	if ((owner() != nullptr ? owner()->getReportAIMessages() : false))  OO_LOG("ai.stack.pop", "Popping previous state machine for {}", description());
#endif
	
	directSetStateMachine(preservedMachine->stateMachine(),
						   preservedMachine->name().value_or(std::string()));

	directSetState(preservedMachine->state());

	// restore JS script
	if (owner() != nullptr)  owner()->setAIScript(preservedMachine->jsScript().value_or(""));

	pendingMessages = preservedMachine->pendingMessages();

	aiStack.pop_back();  //  POP
}


bool AI::hasSuspendedStateMachines()
{
	return !aiStack.empty();
}


void AI::exitStateMachineWithMessage(const std::optional<std::string> &message)
{
	if (!aiStack.empty())
	{
		restorePreviousStateMachine();
		reactToMessage(message.value_or("RESTARTED"), "suspended AI restart");
	}
}


void AI::setStateMachine(const std::string &smName, const std::string &script)
{
	const oo::PList newSM = loadStateMachine(smName, script);

	if (!newSM.isNull())
	{
		preserveCurrentStateMachine();
		directSetStateMachine(newSM, smName);
		directSetState("GLOBAL");
		
		nextThinkTime = 0.0;	// think at next tick

		/*	CRASH in objc_msgSend, apparently on [self reactToMessage:@"ENTER"] (1.69, OS X/x86).
			Analysis: self corrupted. We're being called by __NSFireDelayedPerform, which doesn't go
			through NSObject's -performSelector: (with an object), suggesting it's using IMP caching. An
			invalid self is therefore possible.
			Attempted fix: new delayed dispatch with trampoline, see -[AI setStateMachine:afterDelay:].
			 -- Ahruman, 20070706
		*/
		reactToMessage("ENTER", "changing AI");

		// refresh name
		refreshOwnerDesc();
	}
}


void AI::setState(const std::string &stateName)
{
	if (stateMachine.find(stateName) != nullptr)
	{
		/*	CRASH in objc_msgSend, apparently on [self reactToMessage:@"EXIT"] (1.69, OS X/x86).
			Analysis: self corrupted. We're being called by __NSFireDelayedPerform, which doesn't go
			through NSObject's -performSelector: (with an object), suggesting it's using IMP caching. An
			invalid self is therefore possible.
			Attempted fix: new delayed dispatch with trampoline, see -[AI setState:afterDelay:].
			 -- Ahruman, 20070706
		*/
		reactToMessage("EXIT", "changing state");
		directSetState(stateName);
		reactToMessage("ENTER", "changing state");
	}
}


void AI::setStateMachine(const std::string &smName, NSTimeInterval delay)
{
	performDeferredCall("setStateMachine:", smName, delay);
}


void AI::setState(const std::string &stateName, NSTimeInterval delay)
{
	performDeferredCall("deferredSetState:", stateName, delay);
}


std::optional<std::string> AI::name()
{
	return stateMachineName;
}


std::optional<std::string> AI::associatedJS()
{
	// the entry is the script name loadStateMachine: stored (a string)
	const oo::PList script = JSScriptOf(stateMachine);
	const std::string *name = script.getIf<std::string>();
	return (name != nullptr) ? std::optional<std::string>(*name) : std::nullopt;
}


std::optional<std::string> AI::state()
{
	return currentState;
}


NSUInteger AI::stackDepth()
{
	return aiStack.size();
}


#ifndef NDEBUG
typedef struct AIStackElement AIStackElement;
struct AIStackElement
{
	AIStackElement			*back;
	::ShipEntity				*owner;
	std::string				aiName;		// at the time of the call (the state machine may change)
	std::optional<std::string>	state;
	const std::string		*message;
	const std::string		*context;
};

static AIStackElement *sStack = NULL;
#endif


void AI::reactToMessage(const std::string &message, const std::optional<std::string> &debugContextArgument)
{
	std::size_t		i;
	::ShipEntity		*owner = this->owner();
	static unsigned	recursionLimiter = 0;
	AI				*previousRunning = sCurrentlyRunningAI;
	
	/*	CRASH in _freedHandler when called via -setState: __NSFireDelayedPerform (1.69, OS X/x86).
		Analysis: owner invalid.
		Fix: make owner a weak reference.
		 -- Ahruman, 20070706
	*/
	if (owner == nil || (owner != nullptr ? owner->getUniversalID() : OOUniversalID{}) == NO_TARGET)  return;

#ifndef NDEBUG
	// Push debug stack frame.
	const std::optional<std::string> debugContext = debugContextArgument.has_value() ? debugContextArgument : std::optional<std::string>("unspecified");
	AIStackElement stackElement =
	{
		.back = sStack,
		.owner = owner,
		.aiName = stateMachineName,
		.state = currentState,
		.message = &message,
		.context = &*debugContext
	};
	sStack = &stackElement;
#endif
	
	/*	CRASH when calling reactToMessage: FOO in state FOO causes infinite
		recursion. (NB: there are other ways of triggering this.)
		FIX: recursion limiter. Alternative is to explicitly catch this case
		in takeAction:, but that could potentially miss indirect recursion via
		scripts.
	*/
	if (recursionLimiter > kRecursionLimiter)
	{
#ifdef NDEBUG
		const std::optional<std::string> &debugContext = debugContextArgument;
#endif
		OO_LOG_ERR("ai.error.recursion", "AI dispatch: hit stack depth limit in AI {}, state {} handling message {} in context \"{}\", aborting.", stateMachineName, currentState.value_or("(null)"), message, debugContext.value_or("(null)"));
		
#ifndef NDEBUG
		AIStackElement *stack = sStack;
		unsigned depth = 0;
		while (stack != NULL)
		{
			OO_LOG("ai.error.recursion.stackTrace", "{}  {} - {}:{}.{} ({})", depth++, oo::EntityShortDescription(stack->owner), stack->aiName, stack->state.value_or("(null)"), *stack->message, *stack->context);
			stack = stack->back;
		}
		
		// unwind.
		if (sStack != NULL)  sStack = sStack->back;
#endif
		
		return;
	}
	
	const oo::PList *messagesForState = currentState.has_value() ? stateMachine.find(*currentState) : nullptr;
	if (messagesForState == nullptr)
	{
#ifndef NDEBUG
		// Unwind the frame pushed above (this exit used to leave sStack pointing at it).
		if (sStack != NULL)  sStack = sStack->back;
#endif
		return;
	}
	
#ifndef NDEBUG
	if (currentState.has_value() && message != "UPDATE" && (owner != nullptr ? owner->getReportAIMessages() : false))
	{
		OO_LOG("ai.message.receive", "AI {} for {} in state '{}' receives message '{}'. Context: {}, stack depth: {}", stateMachineName, ownerDesc.value_or("(null)"), currentState.value_or("(null)"), message, debugContext.value_or("(null)"), static_cast<unsigned>(recursionLimiter));
	}
#endif
	
	// A copy: an action may replace the state machine.
	const oo::PList *actionList = messagesForState->find(message);
	const oo::PList actions = actionList != nullptr ? *actionList : oo::PList();

	sCurrentlyRunningAI = this;
	if (actions.count() > 0)
	{
		++recursionLimiter;
		try
		{
			for (i = 0; i < actions.count(); i++)
			{
				takeAction(actions.at<std::string>(i));
			}
		}
		catch (...)
		{
			const auto exception = oo::CurrentOOException();
			if (!exception)  throw;	// not an OOException: it goes on up, as before
			OO_LOG(cxx_kOOLogException, "Squashing exception {}:{} in AI handler {}:{}.{}", exception->name(), exception->reason(), stateMachineName, currentState.value_or("(null)"), message);
		}
		
		--recursionLimiter;
	}
	else
	{
		if (currentState.has_value())
		{
			// the ship's C++ part answers its methods called by name (bead oo-9ht.39.7.1)
			if (oo::EntityRespondsToName(owner, "interpretAIMessage:"))
			{
				oo::CallEntityByName(owner, "interpretAIMessage:", message);
			}
		}
	}
	
	sCurrentlyRunningAI = previousRunning;
#ifndef NDEBUG
	// Unwind stack.
	if (sStack != NULL)  sStack = sStack->back;
#endif
}


void AI::takeAction(const std::string &action)
{
	::ShipEntity *owner = this->owner();

#ifndef NDEBUG
	bool report = (owner != nullptr ? owner->getReportAIMessages() : false);
	if (report)
	{
		OO_LOG("ai.takeAction", "{} to take action {}", ownerDesc.value_or("(null)"), action);
		OOLogIndent();
	}
#endif

	const std::vector<std::string> tokens = oo::str::tokens(action);
	const std::size_t tokenCount = tokens.size();

	if (tokenCount != 0)
	{
		const std::string &selectorStr = tokens[0];

		if (owner != nil)
		{
			std::optional<std::string> dataString;

			if (tokenCount == 2)
			{
				dataString = tokens[1];
			}
			else if (tokenCount > 1)
			{
				std::string joined;
				for (std::size_t i = 1; i < tokenCount; i++)
				{
					if (i > 1)  joined += " ";
					joined += tokens[i];
				}
				dataString = std::move(joined);
			}

			// the ship's C++ part answers its methods called by name (bead oo-9ht.39.7.1)
			if (oo::EntityRespondsToName(owner, selectorStr))
			{
				if (dataString.has_value())  oo::CallEntityByName(owner, selectorStr, *dataString);
				else  oo::CallEntityByName(owner, selectorStr);
			}
			else
			{
				OO_LOG_ERR("ai.takeAction.badSelector", "in AI {} in state {}: {} does not respond to {}", stateMachineName, currentState.value_or("(null)"), ownerDesc.value_or("(null)"), selectorStr);
			}
		}
		else
		{
			OO_LOG("ai.takeAction.orphaned", "***** AI {}, trying to perform {}, is orphaned (no owner)", stateMachineName, selectorStr);
		}
	}
	else
	{
#ifndef NDEBUG
		if (report)  OO_LOG("ai.takeAction.noAction", "DEBUG: - no action '{}'", action);
#endif
	}

#ifndef NDEBUG
	if (report)
	{
		OOLogOutdent();
	}
#endif
}


void AI::think()
{
	if ((owner() != nullptr ? owner()->getUniversalID() : OOUniversalID{}) == NO_TARGET || stateMachine.isNull())  return;  // don't think until launched

	reactToMessage("UPDATE", "periodic update");

	// In byte order of the message (the set's hash order before).
	const std::vector<std::string> ms_list(pendingMessages.begin(), pendingMessages.end());
	pendingMessages.clear();

	for (const std::string &ms : ms_list)
	{
		reactToMessage(ms, "handling deferred message");
	}
}


void AI::message(const std::string &ms)
{
	if ((owner() != nullptr ? owner()->getUniversalID() : OOUniversalID{}) == NO_TARGET)  return;  // don't think until launched

	if (EXPECT_NOT(pendingMessages.size() > 32))
	{
		// Generate the error, but don't crash Oolite! Fixes bug #18055 - Pending message overflow for thargoids, -> crash !
		OO_LOG_ERR("ai.message.failed.overflow", "AI message \"{}\" received by '{}' AI while pending messages stack full; message discarded. Pending messages:\n{}", ms, ownerDesc.value_or("(null)"), PendingMessagesDescription(pendingMessages));
	}
	else
	{
		pendingMessages.insert(ms);
	}
}


void AI::dropMessage(const std::string &ms)
{
	pendingMessages.erase(ms);
}
	

std::set<std::string> AI::getPendingMessages()
{
	return pendingMessages;
}


void AI::debugDumpPendingMessages()
{
	std::string			displayMessages;

	if (!pendingMessages.empty())
	{
		std::vector<std::string> sortedMessages(pendingMessages.begin(), pendingMessages.end());
		std::stable_sort(sortedMessages.begin(), sortedMessages.end(), [](const std::string &a, const std::string &b)
		{
			return oo::str::caseInsensitiveCompare(a, b) < 0;
		});
		bool first = true;
		for (const std::string &sortedMessage : sortedMessages)
		{
			if (!first)  displayMessages += ", ";
			first = false;
			displayMessages += sortedMessage;
		}
	}
	else
	{
		displayMessages = "none";
	}

	OO_LOG("ai.debug.pendingMessages", "Pending messages for AI {}: {}", descriptionComponents().value_or("(null)"), displayMessages);
}


void AI::setNextThinkTime(OOTimeAbsolute ntt)
{
	nextThinkTime = ntt;
}


OOTimeAbsolute AI::getNextThinkTime()
{
	if (stateMachine.isNull())
		return INFINITY;

	return nextThinkTime;
}


void AI::setThinkTimeInterval(OOTimeDelta tti)
{
	thinkTimeInterval = tti;
}


OOTimeDelta AI::getThinkTimeInterval()
{
	return thinkTimeInterval;
}


void AI::clearStack()
{
	aiStack.clear();
}


void AI::clearAllData()
{
	aiStack.clear();
	pendingMessages.clear();
	
	nextThinkTime += 36000.0;	// should dealloc in under ten hours!
}


void AI::dumpState()
{
	OO_LOG("dumpState.ai", "State machine name: {}", stateMachineName);
	OO_LOG("dumpState.ai", "Current state: {}", currentState.value_or("(null)"));
	OO_LOG("dumpState.ai", "Next think time: {:g}", nextThinkTime);
	OO_LOG("dumpState.ai", "Next think interval: {:g}", thinkTimeInterval);
}



/*	This is an attemptto fix the bugs referred to above regarding calls from
	__NSFireDelayedPerform with a corrupt self. I'm not certain whether this
	will fix the issue or merely cause a less weird crash in
	+deferredCallTrampolineWithInfo:.
	-- Ahruman 20070706
*/
void AI::performDeferredCall(const char *selectorName, const std::string &argument, NSTimeInterval delay)
{
	if (selectorName != NULL)
	{
		// The call keeps the AI alive until it has run (the holder retained it; it retained the facade).
		oo::Ref<AI> ai(this);
		OOScheduleDeferredCall([ai, selectorName, argument]() { FireAIDeferredCall(ai.get(), selectorName, argument); }, delay);
	}
}


void AI::deferredSetState(const std::string &stateName)
{
	setState(stateName);
}


void AI::refreshOwnerDesc()
{
	::ShipEntity *owner = this->owner();
	if ((owner != nullptr ? owner->getIsPlayer() : false))
	{
		ownerDesc = "player autopilot";
	}
	else if (owner != nil)
	{
		ownerDesc = oo::str::format("%s %d", (owner != nullptr ? owner->getName() : std::optional<std::string>()).value_or("(null)").c_str(), (owner != nullptr ? owner->getUniversalID() : OOUniversalID{}));
	}
	else
	{
		ownerDesc = "no owner";
	}
}


void AI::directSetStateMachine(const oo::PList &newSM, const std::string &name)
{
	stateMachine = newSM;
	stateMachineName = name;
}


void AI::directSetState(const std::optional<std::string> &state)
{
	currentState = state;
}


oo::PList AI::loadStateMachine(const std::string &smName, const std::string &script)
{
	oo::PList				newSM;
	::OOCacheManager			*cacheMgr = OOCacheManager::sharedCache();

	if (smName != "nullAI.plist")
	{
		// don't cache nullAI since they're different depending on associated JS AI
		oo::PList cached = cacheMgr->pListForKey(smName, "AIs");
		if (!cached.isNull() && !cached.isDict())  return oo::PList();	// catches use of @"nil" to indicate no AI found.
		newSM = std::move(cached);
	}

	if (newSM.isNull())
	{
		OO_LOG("ai.load", "Loading and sanitizing AI \"{}\"", smName);
		OOLogPushIndent();
		oo::log::indentIf("ai.load");

		{
			const oo::Finally popIndent([] { OOLogPopIndent(); });	// was @finally

			// Load state machine and validate against whitelist.
			const std::optional<std::string> aiPath = ResourceManager::pathForFileNamed(smName, "AIs");
			if (aiPath.has_value())
			{
				newSM = PListDictionaryFromFile(*aiPath);
			}
			if (newSM.isNull())
			{
				cacheMgr->setPList(oo::PList("nil"), smName, "AIs");
				std::string fromString;
				const std::optional<std::string> state = this->state();
				if (state.has_value())
				{
					fromString = oo::str::format(" from %s:%s", name().value_or("(null)").c_str(), state->c_str());
				}
				OO_LOG("ai.load.failed.unknownAI", "Can't switch AI for {}{} to \"{}\" - could not load file.", oo::EntityShortDescription(owner()), fromString, smName);
				return oo::PList();
			}

			oo::PList::Dict cleanSM;

			// In byte order of the state name (the dictionary's hash order before).
			const oo::PList::Dict *states = newSM.getIf<oo::PList::Dict>();
			for (const auto &[stateKey, stateHandlers] : states != nullptr ? *states : oo::PList::Dict())
			{
				if (!stateHandlers.isDict())
				{
					OO_LOG_WARN("ai.invalidFormat.state", "State \"{}\" in AI \"{}\" is not a dictionary, ignoring.", stateKey, smName);
					continue;
				}

				cleanSM[stateKey] = cleanHandlers(stateHandlers, stateKey, smName);
			}
			cleanSM["jsScript"] = oo::PList(script);

			newSM = oo::PList(std::move(cleanSM));

#if DEBUG_GRAPHVIZ
			if (oo::Defaults::standard().boolForKey("generate-ai-graphviz"))
			{
				GenerateGraphVizForAIStateMachine(newSM, smName);
			}
#endif

			// Cache.
			cacheMgr->setPList(newSM, smName, "AIs");
		}
	}

	return newSM;
}


oo::PList AI::cleanHandlers(const oo::PList &handlers, const std::string &stateKey, const std::string &smName)
{
	oo::PList::Dict			result;

	// In byte order of the handler name (the dictionary's hash order before).
	const oo::PList::Dict *entries = handlers.getIf<oo::PList::Dict>();
	for (const auto &[handlerKey, handlerActions] : entries != nullptr ? *entries : oo::PList::Dict())
	{
		if (!handlerActions.isArray())
		{
			OO_LOG_WARN("ai.invalidFormat.handler", "Handler \"{}\" for state \"{}\" in AI \"{}\" is not an array, ignoring.", handlerKey, stateKey, smName);
			continue;
		}

		result[handlerKey] = cleanActions(handlerActions, handlerKey, stateKey, smName);
	}

	return oo::PList(std::move(result));
}


oo::PList AI::cleanActions(const oo::PList &actions, const std::string &handlerKey, const std::string &stateKey, const std::string &smName)
{
	oo::PList::Array						result;
	static std::optional<std::set<std::string>>	whitelist;
	static oo::PList						aliases;

	if (!whitelist.has_value())
	{
		const oo::PList whitelistDictionary = ResourceManager::whitelistDictionary();
		whitelist.emplace();
		for (const char *key : { "ai_methods", "ai_and_action_methods" })
		{
			const oo::PList *methods = whitelistDictionary.get<oo::PList::Array>(key);
			if (methods == nullptr)  continue;
			for (const oo::PList &method : *methods->getIf<oo::PList::Array>())
			{
				if (method.isString())  whitelist->insert(*method.getIf<std::string>());
			}
		}
		const oo::PList *aliasDictionary = whitelistDictionary.get<oo::PList::Dict>("ai_method_aliases");
		if (aliasDictionary != nullptr)  aliases = *aliasDictionary;
	}

	// The whitespace character set: whitespace, not newlines.
	const oo::str::CharacterSet whitespace = oo::str::CharacterSet::whitespace();

	const oo::PList::Array *entries = actions.getIf<oo::PList::Array>();
	for (const oo::PList &entry : entries != nullptr ? *entries : oo::PList::Array())
	{
		if (!entry.isString())
		{
			OO_LOG_WARN("ai.invalidFormat.action", "An action in handler \"{}\" for state \"{}\" in AI \"{}\" is not a string, ignoring.", handlerKey, stateKey, smName);
			continue;
		}

		// Trim spaces from beginning and end.
		std::string action = oo::str::trim(*entry.getIf<std::string>(), whitespace);

		// Cut off parameters.
		const std::size_t space = action.find(' ');
		std::string selector = space == std::string::npos ? action : action.substr(0, space);

		// Look in alias table.
		const oo::PList *aliasedSelector = aliases.find(selector);
		if (aliasedSelector != nullptr)
		{
			if (aliasedSelector->isString())
			{
				// Change selector and action to use real method name.
				const std::string &alias = *aliasedSelector->getIf<std::string>();
				if (space == std::string::npos)  action = alias;
				else
				{
					std::string parameters = action.substr(space);
					action = alias;
					action += parameters;
				}
				selector = alias;
			}
			else if (aliasedSelector->isArray() && aliasedSelector->count() != 0)
			{
				// Alias is complete expression, pretokenized in anticipation of a tokenized future.
				std::string joined;
				bool first = true;
				for (const oo::PList &token : *aliasedSelector->getIf<oo::PList::Array>())
				{
					if (!first)  joined += " ";
					first = false;
					joined += oo::DescriptionOf(token);
				}
				action = std::move(joined);
				selector = oo::DescriptionOf(aliasedSelector->getIf<oo::PList::Array>()->front());
			}
		}

		// Check for selector in whitelist.
		if (!whitelist->contains(selector))
		{
			OO_LOG("ai.unpermittedMethod", "Handler \"{}\" for state \"{}\" in AI \"{}\" uses \"{}\", which is not a permitted AI method.", handlerKey, stateKey, smName, selector);
			continue;
		}

		result.push_back(oo::PList(std::move(action)));
	}

	return oo::PList(std::move(result));
}


OOPreservedAIStateMachine::OOPreservedAIStateMachine(const oo::PList &stateMachine,
					   const std::string &name,
					  const std::optional<std::string> &state,
			const std::set<std::string> &pendingMessages,
									 const std::optional<std::string> &script)
{
	{
		_stateMachine = stateMachine;
		_name = name;
		_state = state;
		_pendingMessages = pendingMessages;
		_jsScript = script;
	}
}


oo::PList OOPreservedAIStateMachine::stateMachine()
{
	return _stateMachine;
}


std::optional<std::string> OOPreservedAIStateMachine::name()
{
	return _name;
}


std::optional<std::string> OOPreservedAIStateMachine::state()
{
	return _state;
}


std::set<std::string> OOPreservedAIStateMachine::pendingMessages()
{
	return _pendingMessages;
}

std::optional<std::string> OOPreservedAIStateMachine::jsScript()
{
	return _jsScript;
}
