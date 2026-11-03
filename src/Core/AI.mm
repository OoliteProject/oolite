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

#import "AI.h"
#import "OOCacheManager.h"
#import "OOCallByName.h"
#import "OOPListParsing.h"
#import "OOPListView.h"
#import "OOStringParsing.h"
#import "OOWeakReference.h"
#import "ResourceManager.h"
#include "oofnd/objc/OORuntime.h"
#import <objc/objc-arc.h>
#import <objc/runtime.h>

#import "GameController.h"
#import "OOFoundationBridge.h"
#import "OOStringBridge.h"
#import "ShipEntity.h"
#import "ShipEntityAI.h"
#include "oofnd/objc/OOException.h"
#import "oofnd/objc/OOObject.h"

#include "oofnd/Log.hpp"
#include "oofnd/Scanner.hpp"
#include "oofnd/String.hpp"

enum {
    kRecursionLimiter = 32, // reactToMethod: recursion
    kStackLimiter = 32 // setAITo: stack overflow
};

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

@implementation OOAIDeferredCallTrampolineInfoHolder
@end

static AI* sCurrentlyRunningAI = nil;

namespace {

// OODictionaryFromFile (OOPListParsing's bridge) as a property list: the file's
// property list when it is a dictionary, a null PList otherwise (its plist.wrongType log line,
// which named the Foundation class, is not kept).
oo::PList PListDictionaryFromFile(const std::string& path)
{
    oo::PList result = cxx_OOPropertyListFromFile(path);
    return result.isDict() ? result : oo::PList();
}

// The state machine's "jsScript" entry as an Objective-C object, nil if it has none (what
// -objectForKey:@"jsScript" answered).
id JSScriptObjectOf(const oo::PList& stateMachine)
{
    const oo::PList* script = stateMachine.find("jsScript");
    return script != nullptr ? oo::ObjectFromPList(*script) : nil;
}

} // namespace

@interface AI (OOPrivate)

// Wrapper for a deferred call (OOScheduleDeferredCall) to catch/fix bugs. <selector> is called by
// name with <argument> (OOCallByName.h).
- (void)performDeferredCall:(SEL)selector withArgument:(const std::string&)argument afterDelay:(NSTimeInterval)delay;
+ (void)deferredCallTrampolineWithInfo:(OOAIDeferredCallTrampolineInfoHolder*)info;
// The target of -cxx_setState:afterDelay:'s deferred call (called by name).
- (void)deferredSetState:(const std::string&)stateName;

- (void)refreshOwnerDesc;

// Set state machine and state without side effects. A nullopt state is no state (nil).
- (void)directSetStateMachine:(const oo::PList&)newSM name:(const std::string&)name;
- (void)directSetState:(const std::optional<std::string>&)state;

// Loading/whitelisting. A null result is no state machine (nil).
- (oo::PList)loadStateMachine:(const std::string&)smName jsName:(const std::string&)script;
- (oo::PList)cleanHandlers:(const oo::PList&)handlers forState:(const std::string&)stateKey stateMachine:(const std::string&)smName;
- (oo::PList)cleanActions:(const oo::PList&)actions forHandler:(const std::string&)handlerKey state:(const std::string&)stateKey stateMachine:(const std::string&)smName;

@end

#if DEBUG_GRAPHVIZ
#import "AIGraphViz.h"
#include "oofnd/Defaults.hpp"
#endif

@interface OOPreservedAIStateMachine : OOObject {
@private
    oo::PList _stateMachine;
    std::string _name;
    std::optional<std::string> _state;
    std::set<std::string> _pendingMessages;
    std::optional<std::string> _jsScript;
}

- (id)initWithStateMachine:(const oo::PList&)stateMachine
                      name:(const std::string&)name
                     state:(const std::optional<std::string>&)state
           pendingMessages:(const std::set<std::string>&)pendingMessages
                  jsScript:(const std::optional<std::string>&)script;

- (oo::PList)stateMachine;
- (id)name; // shared selector (Foundation declares -name too): -cxx_name as an Objective-C string
- (std::optional<std::string>)cxx_name; // (bead oo-3rb.289.8)
- (std::optional<std::string>)cxx_state;
- (std::set<std::string>)pendingMessages;
- (std::optional<std::string>)jsScript;

@end

@implementation AI

+ (AI*)currentlyRunningAI
{
    return sCurrentlyRunningAI;
}

+ (std::optional<std::string>)cxx_currentlyRunningAIDescription
{
    if (sCurrentlyRunningAI != nil) {
        return oo::str::format("%s in state %s", [sCurrentlyRunningAI cxx_name].value_or("(null)").c_str(), [sCurrentlyRunningAI cxx_state].value_or("(null)").c_str());
    } else {
        return "<no AI running>";
    }
}

- (id)init
{
    if ((self = [super init])) {
        nextThinkTime = INFINITY; // don't think for a while
        thinkTimeInterval = AI_THINK_INTERVAL;

        stateMachineName = "<no AI>"; // no initial brain
    }

    return self;
}

- (id)cxx_initWithStateMachine:(const std::optional<std::string>&)smName andState:(const std::optional<std::string>&)stateName
{
    if ((self = [self init])) {
        if (smName.has_value())
            [self cxx_setStateMachine:*smName withJSScript:"oolite-nullAI.js"];
        if (stateName.has_value())
            currentState = *stateName;
    }

    return self;
}

- (void)dealloc
{
    if (sCurrentlyRunningAI == self) {
        sCurrentlyRunningAI = nil;
    }

    DESTROY(_owner);

    [super dealloc];
}

- (std::optional<std::string>)cxx_descriptionComponents
{
    return oo::str::format("\"%s\" in state: \"%s\" for %s", stateMachineName.c_str(), currentState.value_or("(null)").c_str(), ownerDesc.value_or("(null)").c_str());
}

- (std::optional<std::string>)cxx_shortDescriptionComponents
{
    return oo::str::format("%s:%s / %s", stateMachineName.c_str(), currentState.value_or("(null)").c_str(), oo::DescriptionOf(JSScriptObjectOf(stateMachine)).c_str());
}

- (ShipEntity*)owner
{
    ShipEntity* owner = [_owner weakRefUnderlyingObject];
    if (owner == nil) {
        [_owner release];
        _owner = nil;
    }

    return owner;
}

- (void)setOwner:(ShipEntity*)ship
{
    [_owner release];
    _owner = [ship weakRetain];
    [self refreshOwnerDesc];
}

- (void)reportStackOverflow
{
    if (oo::log::willDisplay("ai.error.stackOverflow")) {
        BOOL stackDump = oo::log::willDisplay("ai.error.stackOverflow.dump");

        const char* trailer = stackDump ? " -- stack:" : ".";
        OO_LOG_ERR("ai.error.stackOverflow", "AI stack overflow for {} in {}: {}{}\n", oo::ShortDescriptionOf(_owner), stateMachineName, currentState.value_or("(null)"), trailer);

        if (stackDump) {
            OOLogIndent();

            std::size_t count = aiStack.size();
            while (count--) {
                OOPreservedAIStateMachine* preservedMachine = aiStack[count].get();
                OO_LOG("ai.error.stackOverflow.dump", "{}: {}: {}", count, [preservedMachine cxx_name].value_or("(null)"), [preservedMachine cxx_state].value_or("(null)"));
            }

            OOLogOutdent();
        }
    }
}

- (void)preserveCurrentStateMachine
{
    if (stateMachine.isNull())
        return;

    if (aiStack.size() >= kStackLimiter) {
        [self reportStackOverflow];

        [OOException raise:"OoliteException"
                    format:"AI stack overflow for %s", oo::DescriptionOf(_owner).c_str()];
    }

    const oo::PList* script = stateMachine.find("jsScript");
    oo::ObjCRef<OOPreservedAIStateMachine*> preservedMachine = oo::adoptObjC([[OOPreservedAIStateMachine alloc]
        initWithStateMachine:stateMachine
                        name:stateMachineName
                       state:currentState
             pendingMessages:pendingMessages
                    jsScript:(script != nullptr && script->isString()) ? std::optional<std::string>(*script->getIf<std::string>()) : std::nullopt]);

#ifdef OO_DEBUG_MONITOR_ENABLED
    if ([[self owner] reportAIMessages])
        OO_LOG("ai.stack.push", "Pushing state machine for {}", oo::DescriptionOf(self));
#endif

    aiStack.push_back(std::move(preservedMachine)); // PUSH
}

- (void)restorePreviousStateMachine
{
    if (aiStack.empty())
        return;

    const oo::ObjCRef<OOPreservedAIStateMachine*> preservedMachine = aiStack.back();

#ifdef OO_DEBUG_MONITOR_ENABLED
    if ([[self owner] reportAIMessages])
        OO_LOG("ai.stack.pop", "Popping previous state machine for {}", oo::DescriptionOf(self));
#endif

    [self directSetStateMachine:[preservedMachine.get() stateMachine]
                           name:[preservedMachine.get() cxx_name].value_or(std::string())];

    [self directSetState:[preservedMachine.get() cxx_state]];

    // restore JS script
    [[self owner] setAIScript:[preservedMachine.get() jsScript].value_or("")];

    pendingMessages = [preservedMachine.get() pendingMessages];

    aiStack.pop_back(); //  POP
}

- (BOOL)hasSuspendedStateMachines
{
    return !aiStack.empty();
}

- (void)cxx_exitStateMachineWithMessage:(const std::optional<std::string>&)message
{
    if (!aiStack.empty()) {
        [self restorePreviousStateMachine];
        [self cxx_reactToMessage:message.value_or("RESTARTED") context:"suspended AI restart"];
    }
}

- (void)cxx_setStateMachine:(const std::string&)smName withJSScript:(const std::string&)script
{
    const oo::PList newSM = [self loadStateMachine:smName jsName:script];

    if (!newSM.isNull()) {
        [self preserveCurrentStateMachine];
        [self directSetStateMachine:newSM name:smName];
        [self directSetState:"GLOBAL"];

        nextThinkTime = 0.0; // think at next tick

        /*	CRASH in objc_msgSend, apparently on [self reactToMessage:@"ENTER"] (1.69, OS X/x86).
                Analysis: self corrupted. We're being called by __NSFireDelayedPerform, which doesn't go
                through NSObject's -performSelector: (with an object), suggesting it's using IMP caching. An
                invalid self is therefore possible.
                Attempted fix: new delayed dispatch with trampoline, see -[AI setStateMachine:afterDelay:].
                 -- Ahruman, 20070706
        */
        [self cxx_reactToMessage:"ENTER" context:"changing AI"];

        // refresh name
        [self refreshOwnerDesc];
    }
}

- (void)cxx_setState:(const std::string&)stateName
{
    if (stateMachine.find(stateName) != nullptr) {
        /*	CRASH in objc_msgSend, apparently on [self reactToMessage:@"EXIT"] (1.69, OS X/x86).
                Analysis: self corrupted. We're being called by __NSFireDelayedPerform, which doesn't go
                through NSObject's -performSelector: (with an object), suggesting it's using IMP caching. An
                invalid self is therefore possible.
                Attempted fix: new delayed dispatch with trampoline, see -[AI setState:afterDelay:].
                 -- Ahruman, 20070706
        */
        [self cxx_reactToMessage:"EXIT" context:"changing state"];
        [self directSetState:stateName];
        [self cxx_reactToMessage:"ENTER" context:"changing state"];
    }
}

- (void)cxx_setStateMachine:(const std::string&)smName afterDelay:(NSTimeInterval)delay
{
    [self performDeferredCall:@selector(setStateMachine:) withArgument:smName afterDelay:delay];
}

- (void)cxx_setState:(const std::string&)stateName afterDelay:(NSTimeInterval)delay
{
    [self performDeferredCall:@selector(deferredSetState:) withArgument:stateName afterDelay:delay];
}

- (id)name // shared selector (Foundation declares -name too; retires with oo-qps)
{
    return oo::NSStringOrNil([self cxx_name]);
}

- (std::optional<std::string>)cxx_name
{
    return stateMachineName;
}

- (std::optional<std::string>)cxx_associatedJS
{
    return oo::OptionalString(JSScriptObjectOf(stateMachine));
}

- (id)state // shared selector (Foundation declares -state too; retires with oo-qps)
{
    return oo::NSStringOrNil([self cxx_state]);
}

- (std::optional<std::string>)cxx_state
{
    return currentState;
}

- (NSUInteger)stackDepth
{
    return aiStack.size();
}

#ifndef NDEBUG
typedef struct AIStackElement AIStackElement;
struct AIStackElement {
    AIStackElement* back;
    ShipEntity* owner;
    std::string aiName; // at the time of the call (the state machine may change)
    std::optional<std::string> state;
    const std::string* message;
    const std::string* context;
};

static AIStackElement* sStack = NULL;
#endif

- (void)cxx_reactToMessage:(const std::string&)message context:(const std::optional<std::string>&)debugContextArgument
{
    std::size_t i;
    ShipEntity* owner = [self owner];
    static unsigned recursionLimiter = 0;
    AI* previousRunning = sCurrentlyRunningAI;

    /*	CRASH in _freedHandler when called via -setState: __NSFireDelayedPerform (1.69, OS X/x86).
            Analysis: owner invalid.
            Fix: make owner an OOWeakReference.
             -- Ahruman, 20070706
    */
    if (owner == nil || [owner universalID] == NO_TARGET)
        return;

#ifndef NDEBUG
    // Push debug stack frame.
    const std::optional<std::string> debugContext = debugContextArgument.has_value() ? debugContextArgument : std::optional<std::string>("unspecified");
    AIStackElement stackElement = {
        .back = sStack,
        .owner = owner,
        .aiName = stateMachineName,
        .state = currentState,
        .message = &message,
        .context = &*debugContext
    };
    sStack = &stackElement;
#else
    // The argument as given: the deployment build's message log (OO_DEBUG_MONITOR_ENABLED, upstream #756) reads it.
    const std::optional<std::string>& debugContext = debugContextArgument;
#endif

    /*	CRASH when calling reactToMessage: FOO in state FOO causes infinite
            recursion. (NB: there are other ways of triggering this.)
            FIX: recursion limiter. Alternative is to explicitly catch this case
            in takeAction:, but that could potentially miss indirect recursion via
            scripts.
    */
    if (recursionLimiter > kRecursionLimiter) {
        OO_LOG_ERR("ai.error.recursion", "AI dispatch: hit stack depth limit in AI {}, state {} handling message {} in context \"{}\", aborting.", stateMachineName, currentState.value_or("(null)"), message, debugContext.value_or("(null)"));

#ifndef NDEBUG
        AIStackElement* stack = sStack;
        unsigned depth = 0;
        while (stack != NULL) {
            OO_LOG("ai.error.recursion.stackTrace", "{}  {} - {}:{}.{} ({})", depth++, oo::ShortDescriptionOf(stack->owner), stack->aiName, stack->state.value_or("(null)"), *stack->message, *stack->context);
            stack = stack->back;
        }

        // unwind.
        if (sStack != NULL)
            sStack = sStack->back;
#endif

        return;
    }

    const oo::PList* messagesForState = currentState.has_value() ? stateMachine.find(*currentState) : nullptr;
    if (messagesForState == nullptr) {
#ifndef NDEBUG
        // Unwind the frame pushed above (this exit used to leave sStack pointing at it).
        if (sStack != NULL)
            sStack = sStack->back;
#endif
        return;
    }

#ifdef OO_DEBUG_MONITOR_ENABLED
    if (currentState.has_value() && message != "UPDATE" && [owner reportAIMessages]) {
        OO_LOG("ai.message.receive", "AI {} for {} in state '{}' receives message '{}'. Context: {}, stack depth: {}", stateMachineName, ownerDesc.value_or("(null)"), currentState.value_or("(null)"), message, debugContext.value_or("(null)"), static_cast<unsigned>(recursionLimiter));
    }
#endif

    // A copy: an action may replace the state machine.
    const oo::PList* actionList = messagesForState->find(message);
    const oo::PList actions = actionList != nullptr ? *actionList : oo::PList();

    sCurrentlyRunningAI = self;
    if (actions.count() > 0) {
        ++recursionLimiter;
        @try {
            for (i = 0; i < actions.count(); i++) {
                [self cxx_takeAction:actions.at<std::string>(i)];
            }
        }
        @catch (OOException* exception) {
            OO_LOG(cxx_kOOLogException, "Squashing exception {}:{} in AI handler {}:{}.{}", [exception name], [exception reason], stateMachineName, currentState.value_or("(null)"), message);
        }

        --recursionLimiter;
    } else {
        if (currentState.has_value()) {
            if ([owner respondsToSelector:@selector(interpretAIMessage:)]) {
                OOCallByName(owner, @selector(interpretAIMessage:), message);
            }
        }
    }

    sCurrentlyRunningAI = previousRunning;
#ifndef NDEBUG
    // Unwind stack.
    if (sStack != NULL)
        sStack = sStack->back;
#endif
}

- (void)cxx_takeAction:(const std::string&)action
{
    ShipEntity* owner = [self owner];

#ifdef OO_DEBUG_MONITOR_ENABLED
    BOOL report = [owner reportAIMessages];
    if (report) {
        OO_LOG("ai.takeAction", "{} to take action {}", ownerDesc.value_or("(null)"), action);
        OOLogIndent();
    }
#endif

    const std::vector<std::string> tokens = oo::str::tokens(action);
    const std::size_t tokenCount = tokens.size();

    if (tokenCount != 0) {
        const std::string& selectorStr = tokens[0];

        if (owner != nil) {
            std::optional<std::string> dataString;

            if (tokenCount == 2) {
                dataString = tokens[1];
            } else if (tokenCount > 1) {
                std::string joined;
                for (std::size_t i = 1; i < tokenCount; i++) {
                    if (i > 1)
                        joined += " ";
                    joined += tokens[i];
                }
                dataString = std::move(joined);
            }

            SEL selector = OOSelectorFromName(selectorStr);
            if ([owner respondsToSelector:selector]) {
                if (dataString.has_value())
                    OOCallByName(owner, selector, *dataString);
                else
                    OOCallByName(owner, selector);
            } else {
                OO_LOG_ERR("ai.takeAction.badSelector", "in AI {} in state {}: {} does not respond to {}", stateMachineName, currentState.value_or("(null)"), ownerDesc.value_or("(null)"), selectorStr);
            }
        } else {
            OO_LOG("ai.takeAction.orphaned", "***** AI {}, trying to perform {}, is orphaned (no owner)", stateMachineName, selectorStr);
        }
    } else {
#ifdef OO_DEBUG_MONITOR_ENABLED
        if (report)
            OO_LOG("ai.takeAction.noAction", "DEBUG: - no action '{}'", action);
#endif
    }

#ifdef OO_DEBUG_MONITOR_ENABLED
    if (report) {
        OOLogOutdent();
    }
#endif
}

- (void)think
{
    if ([[self owner] universalID] == NO_TARGET || stateMachine.isNull())
        return; // don't think until launched

    [self cxx_reactToMessage:"UPDATE" context:"periodic update"];

    // In byte order of the message (the set's hash order before).
    const std::vector<std::string> ms_list(pendingMessages.begin(), pendingMessages.end());
    pendingMessages.clear();

    for (const std::string& ms : ms_list) {
        [self cxx_reactToMessage:ms context:"handling deferred message"];
    }
}

- (void)message:(const std::string&)ms
{
    if ([[self owner] universalID] == NO_TARGET)
        return; // don't think until launched

    if (EXPECT_NOT(pendingMessages.size() > 32)) {
        // Generate the error, but don't crash Oolite! Fixes bug #18055 - Pending message overflow for thargoids, -> crash !
        OO_LOG_ERR("ai.message.failed.overflow", "AI message \"{}\" received by '{}' AI while pending messages stack full; message discarded. Pending messages:\n{}", ms, ownerDesc.value_or("(null)"), oo::DescriptionOf(oo::NSSetFromStrings([self pendingMessages])));
    } else {
        pendingMessages.insert(ms);
    }
}

- (void)cxx_dropMessage:(const std::string&)ms
{
    pendingMessages.erase(ms);
}

- (std::set<std::string>)pendingMessages
{
    return pendingMessages;
}

- (void)debugDumpPendingMessages
{
    std::string displayMessages;

    if (!pendingMessages.empty()) {
        std::vector<std::string> sortedMessages(pendingMessages.begin(), pendingMessages.end());
        std::stable_sort(sortedMessages.begin(), sortedMessages.end(), [](const std::string& a, const std::string& b) {
            return oo::str::caseInsensitiveCompare(a, b) < 0;
        });
        bool first = true;
        for (const std::string& sortedMessage : sortedMessages) {
            if (!first)
                displayMessages += ", ";
            first = false;
            displayMessages += sortedMessage;
        }
    } else {
        displayMessages = "none";
    }

    OO_LOG("ai.debug.pendingMessages", "Pending messages for AI {}: {}", [self cxx_descriptionComponents].value_or("(null)"), displayMessages);
}

- (void)setNextThinkTime:(OOTimeAbsolute)ntt
{
    nextThinkTime = ntt;
}

- (OOTimeAbsolute)nextThinkTime
{
    if (stateMachine.isNull())
        return INFINITY;

    return nextThinkTime;
}

- (void)setThinkTimeInterval:(OOTimeDelta)tti
{
    thinkTimeInterval = tti;
}

- (OOTimeDelta)thinkTimeInterval
{
    return thinkTimeInterval;
}

- (void)clearStack
{
    aiStack.clear();
}

- (void)clearAllData
{
    aiStack.clear();
    pendingMessages.clear();

    nextThinkTime += 36000.0; // should dealloc in under ten hours!
}

- (void)dumpState
{
    OO_LOG("dumpState.ai", "State machine name: {}", stateMachineName);
    OO_LOG("dumpState.ai", "Current state: {}", currentState.value_or("(null)"));
    OO_LOG("dumpState.ai", "Next think time: {:g}", nextThinkTime);
    OO_LOG("dumpState.ai", "Next think interval: {:g}", thinkTimeInterval);
}

@end

/*	This is an attempt to fix the bugs referred to above regarding calls from
        __NSFireDelayedPerform with a corrupt self. I'm not certain whether this
        will fix the issue or merely cause a less weird crash in
        +deferredCallTrampolineWithInfo:.
        -- Ahruman 20070706
*/
@implementation AI (OOPrivate)

- (void)performDeferredCall:(SEL)selector withArgument:(const std::string&)argument afterDelay:(NSTimeInterval)delay
{
    OOAIDeferredCallTrampolineInfo infoStruct;
    OOAIDeferredCallTrampolineInfoHolder* info = nil;

    if (selector != NULL) {
        infoStruct.ai = [self retain];
        infoStruct.selector = selector;
        infoStruct.parameter = argument;

        info = [[OOAIDeferredCallTrampolineInfoHolder alloc] init];
        info->info = infoStruct;

        OOScheduleDeferredCall([AI class], @selector(deferredCallTrampolineWithInfo:), info, delay);
        [info release];
    }
}

- (void)deferredSetState:(const std::string&)stateName
{
    [self cxx_setState:stateName];
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

- (void)refreshOwnerDesc
{
    ShipEntity* owner = [self owner];
    if ([owner isPlayer]) {
        ownerDesc = "player autopilot";
    } else if (owner != nil) {
        ownerDesc = oo::str::format("%s %d", [owner cxx_name].value_or("(null)").c_str(), [owner universalID]);
    } else {
        ownerDesc = "no owner";
    }
}

- (void)directSetStateMachine:(const oo::PList&)newSM name:(const std::string&)name
{
    stateMachine = newSM;
    stateMachineName = name;
}

- (void)directSetState:(const std::optional<std::string>&)state
{
    currentState = state;
}

- (oo::PList)loadStateMachine:(const std::string&)smName jsName:(const std::string&)script
{
    oo::PList newSM;
    OOCacheManager* cacheMgr = [OOCacheManager sharedCache];
    void* pool = NULL;

    if (smName != "nullAI.plist") {
        // don't cache nullAI since they're different depending on associated JS AI
        id cached = [cacheMgr cxx_objectForKey:smName inCache:"AIs"];
        if (cached != nil && !oo::IsNSDictionary(cached))
            return oo::PList(); // catches use of @"nil" to indicate no AI found.
        newSM = oo::PListFrom(cached);
    }

    if (newSM.isNull()) {
        pool = objc_autoreleasePoolPush();
        OO_LOG("ai.load", "Loading and sanitizing AI \"{}\"", smName);
        OOLogPushIndent();
        oo::log::indentIf("ai.load");

        @try {
            // Load state machine and validate against whitelist.
            const std::optional<std::string> aiPath = [ResourceManager cxx_pathForFileNamed:smName inFolder:"AIs"];
            if (aiPath.has_value()) {
                newSM = PListDictionaryFromFile(*aiPath);
            }
            if (newSM.isNull()) {
                [cacheMgr cxx_setObject:@"nil" forKey:smName inCache:"AIs"];
                std::string fromString;
                const std::optional<std::string> state = [self cxx_state];
                if (state.has_value()) {
                    fromString = oo::str::format(" from %s:%s", [self cxx_name].value_or("(null)").c_str(), state->c_str());
                }
                OO_LOG("ai.load.failed.unknownAI", "Can't switch AI for {}{} to \"{}\" - could not load file.", oo::ShortDescriptionOf([self owner]), fromString, smName);
                return oo::PList();
            }

            oo::PList::Dict cleanSM;

            // In byte order of the state name (the dictionary's hash order before).
            const oo::PList::Dict* states = newSM.getIf<oo::PList::Dict>();
            for (const auto& [stateKey, stateHandlers] : states != nullptr ? *states : oo::PList::Dict()) {
                if (!stateHandlers.isDict()) {
                    OO_LOG_WARN("ai.invalidFormat.state", "State \"{}\" in AI \"{}\" is not a dictionary, ignoring.", stateKey, smName);
                    continue;
                }

                cleanSM[stateKey] = [self cleanHandlers:stateHandlers forState:stateKey stateMachine:smName];
            }
            cleanSM["jsScript"] = oo::PList(script);

            newSM = oo::PList(std::move(cleanSM));

#if DEBUG_GRAPHVIZ
            if (oo::Defaults::standard().boolForKey("generate-ai-graphviz")) {
                GenerateGraphVizForAIStateMachine(newSM, smName);
            }
#endif

            // Cache.
            [cacheMgr cxx_setObject:oo::ObjectFromPList(newSM) forKey:smName inCache:"AIs"];
        }
        @finally {
            OOLogPopIndent();
        }

        objc_autoreleasePoolPop(pool);
    }

    return newSM;
}

- (oo::PList)cleanHandlers:(const oo::PList&)handlers forState:(const std::string&)stateKey stateMachine:(const std::string&)smName
{
    oo::PList::Dict result;

    // In byte order of the handler name (the dictionary's hash order before).
    const oo::PList::Dict* entries = handlers.getIf<oo::PList::Dict>();
    for (const auto& [handlerKey, handlerActions] : entries != nullptr ? *entries : oo::PList::Dict()) {
        if (!handlerActions.isArray()) {
            OO_LOG_WARN("ai.invalidFormat.handler", "Handler \"{}\" for state \"{}\" in AI \"{}\" is not an array, ignoring.", handlerKey, stateKey, smName);
            continue;
        }

        result[handlerKey] = [self cleanActions:handlerActions forHandler:handlerKey state:stateKey stateMachine:smName];
    }

    return oo::PList(std::move(result));
}

- (oo::PList)cleanActions:(const oo::PList&)actions forHandler:(const std::string&)handlerKey state:(const std::string&)stateKey stateMachine:(const std::string&)smName
{
    oo::PList::Array result;
    static std::optional<std::set<std::string>> whitelist;
    static oo::PList aliases;

    if (!whitelist.has_value()) {
        const oo::PList whitelistDictionary = [ResourceManager cxx_whitelistDictionary];
        whitelist.emplace();
        for (const char* key : { "ai_methods", "ai_and_action_methods" }) {
            const oo::PList* methods = whitelistDictionary.get<oo::PList::Array>(key);
            if (methods == nullptr)
                continue;
            for (const oo::PList& method : *methods->getIf<oo::PList::Array>()) {
                if (method.isString())
                    whitelist->insert(*method.getIf<std::string>());
            }
        }
        const oo::PList* aliasDictionary = whitelistDictionary.get<oo::PList::Dict>("ai_method_aliases");
        if (aliasDictionary != nullptr)
            aliases = *aliasDictionary;
    }

    // The whitespace character set: whitespace, not newlines.
    const oo::str::CharacterSet whitespace = oo::str::CharacterSet::whitespace();

    const oo::PList::Array* entries = actions.getIf<oo::PList::Array>();
    for (const oo::PList& entry : entries != nullptr ? *entries : oo::PList::Array()) {
        if (!entry.isString()) {
            OO_LOG_WARN("ai.invalidFormat.action", "An action in handler \"{}\" for state \"{}\" in AI \"{}\" is not a string, ignoring.", handlerKey, stateKey, smName);
            continue;
        }

        // Trim spaces from beginning and end.
        std::string action = oo::str::trim(*entry.getIf<std::string>(), whitespace);

        // Cut off parameters.
        const std::size_t space = action.find(' ');
        std::string selector = space == std::string::npos ? action : action.substr(0, space);

        // Look in alias table.
        const oo::PList* aliasedSelector = aliases.find(selector);
        if (aliasedSelector != nullptr) {
            if (aliasedSelector->isString()) {
                // Change selector and action to use real method name.
                const std::string& alias = *aliasedSelector->getIf<std::string>();
                if (space == std::string::npos)
                    action = alias;
                else {
                    std::string parameters = action.substr(space);
                    action = alias;
                    action += parameters;
                }
                selector = alias;
            } else if (aliasedSelector->isArray() && aliasedSelector->count() != 0) {
                // Alias is complete expression, pretokenized in anticipation of a tokenized future.
                std::string joined;
                bool first = true;
                for (const oo::PList& token : *aliasedSelector->getIf<oo::PList::Array>()) {
                    if (!first)
                        joined += " ";
                    first = false;
                    joined += oo::DescriptionOf(token);
                }
                action = std::move(joined);
                selector = oo::DescriptionOf(aliasedSelector->getIf<oo::PList::Array>()->front());
            }
        }

        // Check for selector in whitelist.
        if (!whitelist->contains(selector)) {
            OO_LOG("ai.unpermittedMethod", "Handler \"{}\" for state \"{}\" in AI \"{}\" uses \"{}\", which is not a permitted AI method.", handlerKey, stateKey, smName, selector);
            continue;
        }

        result.push_back(oo::PList(std::move(action)));
    }

    return oo::PList(std::move(result));
}

@end

@implementation OOPreservedAIStateMachine

- (id)initWithStateMachine:(const oo::PList&)stateMachine
                      name:(const std::string&)name
                     state:(const std::optional<std::string>&)state
           pendingMessages:(const std::set<std::string>&)pendingMessages
                  jsScript:(const std::optional<std::string>&)script
{
    if ((self = [super init])) {
        _stateMachine = stateMachine;
        _name = name;
        _state = state;
        _pendingMessages = pendingMessages;
        _jsScript = script;
    }

    return self;
}

- (oo::PList)stateMachine
{
    return _stateMachine;
}

- (id)name // shared selector (Foundation declares -name too; retires with oo-qps)
{
    return oo::NSStringOrNil([self cxx_name]);
}

- (std::optional<std::string>)cxx_name
{
    return _name;
}

- (std::optional<std::string>)cxx_state
{
    return _state;
}

- (std::set<std::string>)pendingMessages
{
    return _pendingMessages;
}

- (std::optional<std::string>)jsScript
{
    return _jsScript;
}

@end
