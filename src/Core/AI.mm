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
#import "OOPListParsing.h"
#import "OOPListView.h"
#import "OOStringParsing.h"
#import "OOWeakReference.h"
#import "ResourceManager.h"
#import <objc/objc-arc.h>
#import <objc/runtime.h>

#import "OOFoundationBridge.h"
#import "OOFoundationException.h"
#import "OOStringBridge.h"
#import "ShipEntity.h"
#import "ShipEntityAI.h"
#import "oofnd/objc/OOObject.h"

#include "oofnd/String.hpp"

enum {
    kRecursionLimiter = 32, // reactToMethod: recursion
    kStackLimiter = 32 // setAITo: stack overflow
};

typedef struct
{
    AI* ai;
    SEL selector;
    id parameter;
} OOAIDeferredCallTrampolineInfo;

/*	Carries the trampoline info through -performSelector:withObject:afterDelay:,
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

// The state machine's "jsScript" entry as an Objective-C object, nil if it has none (what
// -objectForKey:@"jsScript" answered).
id JSScriptObjectOf(const oo::PList& stateMachine)
{
    const oo::PList* script = stateMachine.find("jsScript");
    return script != nullptr ? oo::ObjectFromPList(*script) : nil;
}

} // namespace

@interface AI (OOPrivate)

// Wrapper for performSelector:withObject:afterDelay: to catch/fix bugs.
- (void)performDeferredCall:(SEL)selector withObject:(id)object afterDelay:(NSTimeInterval)delay;
+ (void)deferredCallTrampolineWithInfo:(OOAIDeferredCallTrampolineInfoHolder*)info;
// The target of -cxx_setState:afterDelay:'s deferred call: stateName is an Objective-C string.
- (void)deferredSetState:(id)stateName;

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
- (id)name; // shared selector (proposed ADR-0043): an Objective-C string
- (id)state; // shared selector (proposed ADR-0043): an Objective-C string or nil
- (id)pendingMessages; // shared selector (proposed ADR-0043): an Objective-C set of strings
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
        return oo::str::format("%s in state %s", oo::DescriptionOf([sCurrentlyRunningAI name]).c_str(), oo::DescriptionOf([sCurrentlyRunningAI state]).c_str());
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

- (id)descriptionComponents
{
    return oo::NSStringFrom(oo::str::format("\"%s\" in state: \"%s\" for %s", stateMachineName.c_str(), currentState.value_or("(null)").c_str(), ownerDesc.value_or("(null)").c_str()));
}

- (id)shortDescriptionComponents
{
    return oo::NSStringFrom(oo::str::format("%s:%s / %s", stateMachineName.c_str(), currentState.value_or("(null)").c_str(), oo::DescriptionOf(JSScriptObjectOf(stateMachine)).c_str()));
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
    if (OOLogWillDisplayMessagesInClass(@"ai.error.stackOverflow")) {
        BOOL stackDump = OOLogWillDisplayMessagesInClass(@"ai.error.stackOverflow.dump");

        const char* trailer = stackDump ? " -- stack:" : ".";
        OOLogERR(@"ai.error.stackOverflow", @"AI stack overflow for %@ in %@: %@%@\n", [_owner shortDescription], oo::NSStringFrom(stateMachineName), oo::NSStringOrNil(currentState), oo::NSStringFrom(trailer));

        if (stackDump) {
            OOLogIndent();

            std::size_t count = aiStack.size();
            while (count--) {
                OOPreservedAIStateMachine* preservedMachine = aiStack[count].get();
                OOLog(@"ai.error.stackOverflow.dump", @"%3zu: %@: %@", count, [preservedMachine name], [preservedMachine state]);
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
                    format:"AI stack overflow for %s", [[_owner description] UTF8String]];
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
        OOLog(@"ai.stack.push", @"Pushing state machine for %@", self);
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
        OOLog(@"ai.stack.pop", @"Popping previous state machine for %@", self);
#endif

    [self directSetStateMachine:[preservedMachine.get() stateMachine]
                           name:oo::StdString([preservedMachine.get() name])];

    [self directSetState:oo::OptionalString([preservedMachine.get() state])];

    // restore JS script
    [[self owner] setAIScript:oo::NSStringOrNil([preservedMachine.get() jsScript])];

    const std::vector<std::string> preservedMessages = oo::StringsFrom([preservedMachine.get() pendingMessages]);
    pendingMessages = std::set<std::string>(preservedMessages.begin(), preservedMessages.end());

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
                through -[NSObject performSelector:withObject:], suggesting it's using IMP caching. An
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
                through -[NSObject performSelector:withObject:], suggesting it's using IMP caching. An
                invalid self is therefore possible.
                Attempted fix: new delayed dispatch with trampoline, see -[AI setState:afterDelay:].
                 -- Ahruman, 20070706
        */
        [self cxx_reactToMessage:"EXIT" context:"changing state"];
        [self directSetState:stateName];
        [self cxx_reactToMessage:"ENTER" context:"changing state"];
    }
}

/*	The deferred call's parameter is retained here and released by the trampoline (which released
        the caller's string before: harmless for the literals callers passed, and now balanced for the
        string made here).
*/
- (void)cxx_setStateMachine:(const std::string&)smName afterDelay:(NSTimeInterval)delay
{
    [self performDeferredCall:@selector(setStateMachine:) withObject:[oo::NSStringFrom(smName) retain] afterDelay:delay];
}

- (void)cxx_setState:(const std::string&)stateName afterDelay:(NSTimeInterval)delay
{
    [self performDeferredCall:@selector(deferredSetState:) withObject:[oo::NSStringFrom(stateName) retain] afterDelay:delay];
}

- (id)name
{
    return oo::NSStringFrom(stateMachineName);
}

- (std::optional<std::string>)cxx_associatedJS
{
    return oo::OptionalString(JSScriptObjectOf(stateMachine));
}

- (id)state
{
    return oo::NSStringOrNil(currentState);
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
        OOLogERR(@"ai.error.recursion", @"AI dispatch: hit stack depth limit in AI %@, state %@ handling message %@ in context \"%@\", aborting.", oo::NSStringFrom(stateMachineName), oo::NSStringOrNil(currentState), oo::NSStringFrom(message), oo::NSStringOrNil(debugContext));

#ifndef NDEBUG
        AIStackElement* stack = sStack;
        unsigned depth = 0;
        while (stack != NULL) {
            OOLog(@"ai.error.recursion.stackTrace", @"%4u  %@ - %@:%@.%@ (%@)", depth++, [stack->owner shortDescription], oo::NSStringFrom(stack->aiName), oo::NSStringOrNil(stack->state), oo::NSStringFrom(*stack->message), oo::NSStringFrom(*stack->context));
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
        OOLog(@"ai.message.receive", @"AI %@ for %@ in state '%@' receives message '%@'. Context: %@, stack depth: %u", oo::NSStringFrom(stateMachineName), oo::NSStringOrNil(ownerDesc), oo::NSStringOrNil(currentState), oo::NSStringFrom(message), oo::NSStringOrNil(debugContext), recursionLimiter);
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
            OOLog(kOOLogException, @"Squashing exception %@:%@ in AI handler %@:%@.%@", oo::NSStringFrom([exception name]), oo::NSStringFrom([exception reason]), oo::NSStringFrom(stateMachineName), oo::NSStringOrNil(currentState), oo::NSStringFrom(message));
        }
        @catch (OOFoundationException* exception) {
            OOLog(kOOLogException, @"Squashing exception %@:%@ in AI handler %@:%@.%@", [exception name], [exception reason], oo::NSStringFrom(stateMachineName), oo::NSStringOrNil(currentState), oo::NSStringFrom(message));
        }

        --recursionLimiter;
    } else {
        if (currentState.has_value()) {
            if ([owner respondsToSelector:@selector(interpretAIMessage:)]) {
                [owner performSelector:@selector(interpretAIMessage:) withObject:oo::NSStringFrom(message)];
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
        OOLog(@"ai.takeAction", @"%@ to take action %@", oo::NSStringOrNil(ownerDesc), oo::NSStringFrom(action));
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

            SEL selector = NSSelectorFromString(oo::NSStringFrom(selectorStr));
            if ([owner respondsToSelector:selector]) {
                if (dataString.has_value())
                    [owner performSelector:selector withObject:oo::NSStringFrom(*dataString)];
                else
                    [owner performSelector:selector];
            } else {
                OOLogERR(@"ai.takeAction.badSelector", @"in AI %@ in state %@: %@ does not respond to %@", oo::NSStringFrom(stateMachineName), oo::NSStringOrNil(currentState), oo::NSStringOrNil(ownerDesc), oo::NSStringFrom(selectorStr));
            }
        } else {
            OOLog(@"ai.takeAction.orphaned", @"***** AI %@, trying to perform %@, is orphaned (no owner)", oo::NSStringFrom(stateMachineName), oo::NSStringFrom(selectorStr));
        }
    } else {
#ifdef OO_DEBUG_MONITOR_ENABLED
        if (report)
            OOLog(@"ai.takeAction.noAction", @"DEBUG: - no action '%@'", oo::NSStringFrom(action));
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

- (void)message:(id)ms
{
    if ([[self owner] universalID] == NO_TARGET)
        return; // don't think until launched

    if (EXPECT_NOT(pendingMessages.size() > 32)) {
        // Generate the error, but don't crash Oolite! Fixes bug #18055 - Pending message overflow for thargoids, -> crash !
        OOLogERR(@"ai.message.failed.overflow", @"AI message \"%@\" received by '%@' AI while pending messages stack full; message discarded. Pending messages:\n%@", ms, oo::NSStringOrNil(ownerDesc), [self pendingMessages]);
    } else {
        pendingMessages.insert(oo::StdString(ms));
    }
}

- (void)cxx_dropMessage:(const std::string&)ms
{
    pendingMessages.erase(ms);
}

- (id)pendingMessages
{
    return oo::NSSetFromStrings(pendingMessages);
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

    OOLog(@"ai.debug.pendingMessages", @"Pending messages for AI %@: %@", [self descriptionComponents], oo::NSStringFrom(displayMessages));
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
    OOLog(@"dumpState.ai", @"State machine name: %@", oo::NSStringFrom(stateMachineName));
    OOLog(@"dumpState.ai", @"Current state: %@", oo::NSStringOrNil(currentState));
    OOLog(@"dumpState.ai", @"Next think time: %g", nextThinkTime);
    OOLog(@"dumpState.ai", @"Next think interval: %g", thinkTimeInterval);
}

@end

/*	This is an attempt to fix the bugs referred to above regarding calls from
        __NSFireDelayedPerform with a corrupt self. I'm not certain whether this
        will fix the issue or merely cause a less weird crash in
        +deferredCallTrampolineWithInfo:.
        -- Ahruman 20070706
*/
@implementation AI (OOPrivate)

- (void)performDeferredCall:(SEL)selector withObject:(id)object afterDelay:(NSTimeInterval)delay
{
    OOAIDeferredCallTrampolineInfo infoStruct;
    OOAIDeferredCallTrampolineInfoHolder* info = nil;

    if (selector != NULL) {
        infoStruct.ai = [self retain];
        infoStruct.selector = selector;
        infoStruct.parameter = object;

        info = [[OOAIDeferredCallTrampolineInfoHolder alloc] init];
        info->info = infoStruct;

        [[AI class] performSelector:@selector(deferredCallTrampolineWithInfo:)
                         withObject:info
                         afterDelay:delay];
        [info release];
    }
}

- (void)deferredSetState:(id)stateName
{
    [self cxx_setState:oo::StdString(stateName)];
}

+ (void)deferredCallTrampolineWithInfo:(OOAIDeferredCallTrampolineInfoHolder*)info
{
    OOAIDeferredCallTrampolineInfo infoStruct;

    if (info != nil) {
        infoStruct = info->info;

        [infoStruct.ai performSelector:infoStruct.selector withObject:infoStruct.parameter];

        [infoStruct.ai release];
        [infoStruct.parameter release];
    }
}

- (void)refreshOwnerDesc
{
    ShipEntity* owner = [self owner];
    if ([owner isPlayer]) {
        ownerDesc = "player autopilot";
    } else if (owner != nil) {
        ownerDesc = oo::str::format("%s %d", oo::DescriptionOf([owner name]).c_str(), [owner universalID]);
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
        OOLog(@"ai.load", @"Loading and sanitizing AI \"%@\"", oo::NSStringFrom(smName));
        OOLogPushIndent();
        OOLogIndentIf(@"ai.load");

        @try {
            // Load state machine and validate against whitelist.
            const std::optional<std::string> aiPath = oo::OptionalString([ResourceManager pathForFileNamed:oo::NSStringFrom(smName) inFolder:@"AIs"]);
            if (aiPath.has_value()) {
                newSM = oo::PListFrom(OODictionaryFromFile(oo::NSStringFrom(*aiPath)));
            }
            if (newSM.isNull()) {
                [cacheMgr cxx_setObject:@"nil" forKey:smName inCache:"AIs"];
                std::string fromString;
                if ([self state] != nil) {
                    fromString = oo::str::format(" from %s:%s", oo::DescriptionOf([self name]).c_str(), oo::DescriptionOf([self state]).c_str());
                }
                OOLog(@"ai.load.failed.unknownAI", @"Can't switch AI for %@%@ to \"%@\" - could not load file.", [[self owner] shortDescription], oo::NSStringFrom(fromString), oo::NSStringFrom(smName));
                return oo::PList();
            }

            oo::PList::Dict cleanSM;

            // In byte order of the state name (the dictionary's hash order before).
            const oo::PList::Dict* states = newSM.getIf<oo::PList::Dict>();
            for (const auto& [stateKey, stateHandlers] : states != nullptr ? *states : oo::PList::Dict()) {
                if (!stateHandlers.isDict()) {
                    OOLogWARN(@"ai.invalidFormat.state", @"State \"%@\" in AI \"%@\" is not a dictionary, ignoring.", oo::NSStringFrom(stateKey), oo::NSStringFrom(smName));
                    continue;
                }

                cleanSM[stateKey] = [self cleanHandlers:stateHandlers forState:stateKey stateMachine:smName];
            }
            cleanSM["jsScript"] = oo::PList(script);

            newSM = oo::PList(std::move(cleanSM));

#if DEBUG_GRAPHVIZ
            if ([[NSUserDefaults standardUserDefaults] boolForKey:@"generate-ai-graphviz"]) {
                GenerateGraphVizForAIStateMachine(oo::ObjectFromPList(newSM), oo::NSStringFrom(smName));
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
            OOLogWARN(@"ai.invalidFormat.handler", @"Handler \"%@\" for state \"%@\" in AI \"%@\" is not an array, ignoring.", oo::NSStringFrom(handlerKey), oo::NSStringFrom(stateKey), oo::NSStringFrom(smName));
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
        const oo::PList whitelistDictionary = oo::PListFrom([ResourceManager whitelistDictionary]);
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

    // -stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]: whitespace, not newlines.
    NSCharacterSet* whitespace = [NSCharacterSet whitespaceCharacterSet];
    auto isWhitespace = [whitespace](char16_t c) { return [whitespace characterIsMember:c] != NO; };

    const oo::PList::Array* entries = actions.getIf<oo::PList::Array>();
    for (const oo::PList& entry : entries != nullptr ? *entries : oo::PList::Array()) {
        if (!entry.isString()) {
            OOLogWARN(@"ai.invalidFormat.action", @"An action in handler \"%@\" for state \"%@\" in AI \"%@\" is not a string, ignoring.", oo::NSStringFrom(handlerKey), oo::NSStringFrom(stateKey), oo::NSStringFrom(smName));
            continue;
        }

        // Trim spaces from beginning and end.
        std::string action = oo::str::trimTrailing(oo::str::trimLeading(*entry.getIf<std::string>(), isWhitespace), isWhitespace);

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
                    joined += oo::DescriptionOf(oo::ObjectFromPList(token));
                }
                action = std::move(joined);
                selector = oo::DescriptionOf(oo::ObjectFromPList(aliasedSelector->getIf<oo::PList::Array>()->front()));
            }
        }

        // Check for selector in whitelist.
        if (!whitelist->contains(selector)) {
            OOLog(@"ai.unpermittedMethod", @"Handler \"%@\" for state \"%@\" in AI \"%@\" uses \"%@\", which is not a permitted AI method.", oo::NSStringFrom(handlerKey), oo::NSStringFrom(stateKey), oo::NSStringFrom(smName), oo::NSStringFrom(selector));
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

- (id)name
{
    return oo::NSStringFrom(_name);
}

- (id)state
{
    return oo::NSStringOrNil(_state);
}

- (id)pendingMessages
{
    return oo::NSSetFromStrings(_pendingMessages);
}

- (std::optional<std::string>)jsScript
{
    return _jsScript;
}

@end
