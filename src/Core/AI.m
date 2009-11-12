
/*

AI.m

Oolite
Copyright (C) 2004-2009 Giles C Williams and contributors

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
#import "ResourceManager.h"
#import "OOStringParsing.h"
#import "OOWeakReference.h"
#import "OOCacheManager.h"
#import "OOCollectionExtractors.h"

#import "ShipEntity.h"

#ifdef OO_BRAIN_AI
#import "OOInstinct.h"
#endif

#define kOOLogUnconvertedNSLog @"unclassified.AI"


enum
{
	kRecursionLimiter		= 32,	// reactToMethod: recursion
	kStackLimiter			= 32	// setAITo: stack overflow
};


typedef struct
{
	AI				*ai;
	SEL				selector;
	id				parameter;
} OOAIDeferredCallTrampolineInfo;


static AI *sCurrentlyRunningAI = nil;


@interface AI (OOPrivate)

// Wrapper for performSelector:withObject:afterDelay: to catch/fix bugs.
- (void)performDeferredCall:(SEL)selector withObject:(id)object afterDelay:(NSTimeInterval)delay;
+ (void)deferredCallTrampolineWithInfo:(NSValue *)info;

- (void)refreshOwnerDesc;

// Loading/whitelisting
- (NSDictionary *) loadStateMachine:(NSString *)smName;
- (NSDictionary *) cleanHandlers:(NSDictionary *)handlers forState:(NSString *)stateKey stateMachine:(NSString *)smName;
- (NSArray *) cleanActions:(NSArray *)actions forHandler:(NSString *)handlerKey state:(NSString *)stateKey stateMachine:(NSString *)smName;

@end

#if DEBUG_GRAPHVIZ

static void GenerateGraphVizForStateMachine(NSDictionary *stateMachine, NSString *name);

#endif


@implementation AI

+ (AI *) currentlyRunningAI
{
	return sCurrentlyRunningAI;
}


+ (NSString *) currentlyRunningAIDescription
{
	if (sCurrentlyRunningAI != nil)
	{
		return [NSString stringWithFormat:@"%@ in state %@", [sCurrentlyRunningAI name], [sCurrentlyRunningAI state]];
	}
	else
	{
		return @"<no AI running>";
	}
}


- (id) init
{
	self = [super init];
	
	aiStack = [[NSMutableArray alloc] init];
	pendingMessages = [[NSMutableSet alloc] init];
	
	nextThinkTime = [[NSDate distantFuture] timeIntervalSinceNow];	// don't think for a while
	thinkTimeInterval = AI_THINK_INTERVAL;
	
	stateMachineName = [[NSString stringWithString:@"<no AI>"] retain];	// no initial brain
	
	return self;
}


- (id) initWithStateMachine:(NSString *) smName andState:(NSString *) stateName
{
	self = [self init];
	
	if (smName != nil)  [self setStateMachine:smName];
	if (stateName != nil)  currentState = [stateName retain];
	
	return self;
}


- (void) dealloc
{
	[_owner release];
	[ownerDesc release];
	[aiStack release];
	[stateMachine release];
	[stateMachineName release];
	[currentState release];
	[pendingMessages release];
	
	if (sCurrentlyRunningAI == self)  sCurrentlyRunningAI = nil;
	
	[super dealloc];
}


- (NSString *) descriptionComponents
{
	return [NSString stringWithFormat:@"\"%@\" in state: \"%@\" for %@", stateMachineName, currentState, ownerDesc];
}


- (NSString *) shortDescriptionComponents
{
	return [NSString stringWithFormat:@"%@:%@", stateMachineName, currentState];
}


#ifdef OO_BRAIN_AI
- (OOInstinct *) rulingInstinct
{
	return rulingInstinct;
}


- (void) setRulingInstinct:(OOInstinct*) instinct
{
	rulingInstinct = instinct;
}
#endif


- (ShipEntity *)owner
{
	ShipEntity		*owner = [_owner weakRefUnderlyingObject];
	if (owner == nil)
	{
		[_owner release];
		_owner = nil;
	}
	
	return owner;
}


- (void) setOwner:(ShipEntity *)ship
{
	[_owner release];
	_owner = [ship weakRetain];
	[self refreshOwnerDesc];
}


- (void) reportStackOverflow
{
	if (OOLogWillDisplayMessagesInClass(@"ai.error.stackOverflow"))
	{
		BOOL stackDump = OOLogWillDisplayMessagesInClass(@"ai.error.stackOverflow.dump");
		
		NSString *trailer = stackDump ? @" -- stack:" : @".";
		OOLogERR(@"ai.error.stackOverflow", @"AI stack overflow for %@ in %@: %@%@\n", [_owner shortDescription], stateMachineName, currentState, trailer);
		
		if (stackDump)
		{
			OOLogIndent();
			
			unsigned count = [aiStack count];
			while (count--)
			{
				NSDictionary *pickledMachine = [aiStack objectAtIndex:count];
				OOLog(@"ai.error.stackOverflow.dump", @"%3u: %@: %@", count, [pickledMachine oo_stringForKey:@"stateMachineName"], [pickledMachine oo_stringForKey:@"currentState"]);
			}
			
			OOLogOutdent();
		}
	}
}


- (void) preserveCurrentStateMachine
{
	if (!stateMachine)
		return;
	
	NSMutableDictionary *pickledMachine = [NSMutableDictionary dictionaryWithCapacity:3];
	
	[pickledMachine setObject:stateMachine forKey:@"stateMachine"];
	[pickledMachine setObject:currentState forKey:@"currentState"];
	[pickledMachine setObject:stateMachineName forKey:@"stateMachineName"];
	[pickledMachine setObject:[[pendingMessages copy] autorelease] forKey:@"pendingMessages"];
	
	if (aiStack == nil)  aiStack = [[NSMutableArray alloc] init];
	
	if ([aiStack count] >= kStackLimiter)
	{
		[self reportStackOverflow];
		
		[NSException raise:@"OoliteException"
					format:@"AI stack overflow for %@", _owner];
	}
	
#ifndef NDEBUG
	if ([[self owner] reportAIMessages])  OOLog(@"ai.stack.push", @"Pushing state machine for %@", self);
#endif
	[aiStack insertObject:pickledMachine atIndex:0];	//  PUSH
}


- (void) restorePreviousStateMachine
{
	if ([aiStack count] == 0)  return;
	
	NSMutableDictionary *pickledMachine = [aiStack objectAtIndex:0];
	
#ifndef NDEBUG
	if ([[self owner] reportAIMessages])  OOLog(@"ai.stack.pop", @"Popping previous state machine for %@", self);
#endif
	
	[stateMachine release];
	stateMachine = [[pickledMachine objectForKey:@"stateMachine"] retain];
	
	[currentState release];
	currentState = [[pickledMachine objectForKey:@"currentState"] retain];
	
	[stateMachineName release];
	stateMachineName = [[pickledMachine objectForKey:@"stateMachineName"] retain];
	
	[pendingMessages release];
	pendingMessages = [[pickledMachine objectForKey:@"pendingMessages"] mutableCopy];  // restore a MUTABLE set
	
	[aiStack removeObjectAtIndex:0];   //  POP
}


- (BOOL) hasSuspendedStateMachines
{
	return [aiStack count] != 0;
}


- (void) exitStateMachineWithMessage:(NSString *)message
{
	if ([aiStack count] != 0)
	{
		[self restorePreviousStateMachine];
		if (message == nil)  message = @"RESTARTED";
		[self reactToMessage:message];
	}
}


- (void) setStateMachine:(NSString *) smName
{
	NSDictionary *newSM = [self loadStateMachine:smName];
	
	if (newSM)
	{
		[self preserveCurrentStateMachine];
		[stateMachine release];	// release old state machine
		stateMachine = [newSM retain];
		nextThinkTime = 0.0;	// think at next tick
		
		[currentState release];
		currentState = @"GLOBAL";
		
		// refresh stateMachineName
		[stateMachineName release];
		stateMachineName = [smName copy];

		/*	CRASH in objc_msgSend, apparently on [self reactToMessage:@"ENTER"] (1.69, OS X/x86).
			Analysis: self corrupted. We're being called by __NSFireDelayedPerform, which doesn't go
			through -[NSObject performSelector:withObject:], suggesting it's using IMP caching. An
			invalid self is therefore possible.
			Attempted fix: new delayed dispatch with trampoline, see -[AI setStateMachine:afterDelay:].
			 -- Ahruman, 20070706
		*/
		[self reactToMessage:@"ENTER"];
		
		// refresh name
		[self refreshOwnerDesc];
	}

}


- (void) setState:(NSString *) stateName
{
	if ([stateMachine objectForKey:stateName])
	{
		/*	CRASH in objc_msgSend, apparently on [self reactToMessage:@"EXIT"] (1.69, OS X/x86).
			Analysis: self corrupted. We're being called by __NSFireDelayedPerform, which doesn't go
			through -[NSObject performSelector:withObject:], suggesting it's using IMP caching. An
			invalid self is therefore possible.
			Attempted fix: new delayed dispatch with trampoline, see -[AI setState:afterDelay:].
			 -- Ahruman, 20070706
		*/
		[self reactToMessage:@"EXIT"];
		[currentState release];
		currentState = [stateName retain];
		[self reactToMessage:@"ENTER"];
	}
}


- (void) setStateMachine:(NSString *)smName afterDelay:(NSTimeInterval)delay
{
	[self performDeferredCall:@selector(setStateMachine:) withObject:smName afterDelay:delay];
}


- (void) setState:(NSString *)stateName afterDelay:(NSTimeInterval)delay
{
	[self performDeferredCall:@selector(setState:) withObject:stateName afterDelay:delay];
}


- (NSString *) name
{
	return [[stateMachineName retain] autorelease];
}


- (NSString *) state
{
	return [[currentState retain] autorelease];
}


- (unsigned) stackDepth
{
	return [aiStack count];
}


- (void) reactToMessage:(NSString *)message
{
	unsigned		i;
	NSArray			*actions = nil;
	NSDictionary	*messagesForState = nil;
	ShipEntity		*owner = [self owner];
	static unsigned	recursionLimiter = 0;
	AI				*previousRunning = sCurrentlyRunningAI;
	
	
	/*	CRASH in _freedHandler when called via -setState: __NSFireDelayedPerform (1.69, OS X/x86).
		Analysis: owner invalid.
		Fix: make owner an OOWeakReference.
		 -- Ahruman, 20070706
	*/
	if (message == nil || owner == nil || [owner universalID] == NO_TARGET)  return;
	
	
	/*	CRASH when calling reactToMessage: FOO in state FOO causes infinite
		recursion.
		FIX: recursion limiter. Alternative is to explicitly catch this case
		in takeAction:, but that could potentially miss indirect recursion via
		scripts.
	*/
	if (recursionLimiter > kRecursionLimiter)
	{
		OOLogERR(@"ai.error.recursion", @"AI reactToMessage: recursion in AI %@, state %@, aborting. It is not valid to call reactToMessage: FOO in state FOO.", stateMachineName, currentState);
		return;
	}
	
	messagesForState = [stateMachine objectForKey:currentState];
	if (messagesForState == nil)  return;
	
#ifndef NDEBUG
	if (currentState != nil && ![message isEqual:@"UPDATE"] && [owner reportAIMessages])
	{
		OOLog(@"ai.message.receive", @"AI %@ for %@ in state '%@' receives message '%@'", stateMachineName, ownerDesc, currentState, message);
	}
#endif
	
	actions = [[[messagesForState objectForKey:message] copy] autorelease];
	
#ifdef OO_BRAIN_AI
	if (rulingInstinct != nil)  [rulingInstinct freezeShipVars];	// preserve the pre-thinking state
#endif
	
	sCurrentlyRunningAI = self;
	if ([actions count] > 0)
	{
		NS_DURING
			++recursionLimiter;
			for (i = 0; i < [actions count]; i++)
			{
				[self takeAction:[actions objectAtIndex:i]];
			}
			--recursionLimiter;
		NS_HANDLER
			--recursionLimiter;
		NS_ENDHANDLER
	}
	else
	{
		if (currentState != nil)
		{
			if ([owner respondsToSelector:@selector(interpretAIMessage:)])
			{
				[owner performSelector:@selector(interpretAIMessage:) withObject:message];
			}
		}
	}
	sCurrentlyRunningAI = previousRunning;
	
#ifdef OO_BRAIN_AI
	if (rulingInstinct != nil)
	{
		[rulingInstinct getShipVars];		// record the post-thinking state
		[rulingInstinct unfreezeShipVars];	// restore the pre-thinking state (AI is now abstract thought = instincts motivate)
	}
#endif
}


- (void) takeAction:(NSString *) action
{
	NSArray			*tokens = ScanTokensFromString(action);
	NSString		*dataString = nil;
	NSString		*selectorStr;
	SEL				selector;
	ShipEntity		*owner = [self owner];
	
#ifndef NDEBUG
	BOOL report = [owner reportAIMessages];
	if (report)
	{
		OOLog(@"ai.takeAction", @"%@ to take action %@", ownerDesc, action);
		OOLogIndent();
	}
#endif
	
	if ([tokens count] != 0)
	{
		selectorStr = [tokens objectAtIndex:0];
		
		if (owner != nil)
		{
			if ([tokens count] > 1)
			{
				dataString = [[tokens subarrayWithRange:NSMakeRange(1, [tokens count] - 1)] componentsJoinedByString:@" "];
			}
			
			selector = NSSelectorFromString(selectorStr);
			if ([owner respondsToSelector:selector])
			{
				if (dataString)  [owner performSelector:selector withObject:dataString];
				else  [owner performSelector:selector];
			}
			else
			{
				if ([selectorStr isEqual:@"debugMessage:"])
				{
					OOLog(@"ai.takeAction.debugMessage", @"DEBUG: AI MESSAGE from %@: %@", ownerDesc, dataString);
				}
				else
				{
					OOLogERR(@"ai.takeAction.badSelector", @"in AI %@ in state %@: %@ does not respond to %@", stateMachineName, currentState, ownerDesc, selectorStr);
				}
			}
		}
		else
		{
			OOLog(@"ai.takeAction.orphaned", @"***** AI %@, trying to perform %@, is orphaned (no owner)", stateMachineName, selectorStr);
		}
	}
	else
	{
#ifndef NDEBUG
		if (report)  OOLog(@"ai.takeAction.noAction", @"DEBUG: - no action '%@'", action);
#endif
	}
	
#ifndef NDEBUG
	if (report)
	{
		OOLogOutdent();
	}
#endif
}


- (void) think
{
	NSArray			*ms_list = nil;
	unsigned		i;
	
	if ([[self owner] universalID] == NO_TARGET || stateMachine == nil)  return;  // don't think until launched
	
	[self reactToMessage:@"UPDATE"];

	if ([pendingMessages count] > 0)  ms_list = [pendingMessages allObjects];
	[pendingMessages removeAllObjects];
	
	if (ms_list != nil)
	{
		for (i = 0; i < [ms_list count]; i++)
		{
			[self reactToMessage:[ms_list objectAtIndex:i]];
		}
	}
}


- (void) message:(NSString *) ms
{
	if ([[self owner] universalID] == NO_TARGET)  return;  // don't think until launched

	if ([pendingMessages count] > 32)
	{
		OOLogERR(@"ai.message.failed.overflow", @"AI pending messages overflow for '%@'; pending messages:\n%@", ownerDesc, pendingMessages);
		[NSException raise:@"OoliteException"
					format:@"AI pendingMessages overflow for %@", ownerDesc];
	}
	
	[pendingMessages addObject:ms];
}


- (void) dropMessage:(NSString *) ms
{
	[pendingMessages removeObject:ms];
}
	

- (NSSet *) pendingMessages
{
	return [[pendingMessages copy] autorelease];
}


- (void) debugDumpPendingMessages
{
	NSArray				*sortedMessages = nil;
	NSString			*displayMessages = nil;
	
	if ([pendingMessages count] > 0)
	{
		sortedMessages = [[pendingMessages allObjects] sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
		displayMessages = [sortedMessages componentsJoinedByString:@", "];
	}
	else
	{
		displayMessages = @"none";
	}
	
	OOLog(@"ai.debug.pendingMessages", @"Pending messages for AI %@: %@", [self descriptionComponents], displayMessages);
}


- (void) setNextThinkTime:(OOTimeAbsolute) ntt
{
	nextThinkTime = ntt;
}


- (OOTimeAbsolute) nextThinkTime
{
	if (!stateMachine)
		return [[NSDate distantFuture] timeIntervalSinceNow];

	return nextThinkTime;
}


- (void) setThinkTimeInterval:(OOTimeDelta) tti
{
	thinkTimeInterval = tti;
}


- (OOTimeDelta) thinkTimeInterval
{
	return thinkTimeInterval;
}


- (void) clearStack
{
	[aiStack removeAllObjects];
}


- (void) clearAllData
{
	[aiStack removeAllObjects];
	[pendingMessages removeAllObjects];
	
	nextThinkTime += 36000.0;	// should dealloc in under ten hours!
	thinkTimeInterval = 36000.0;
}


- (void)dumpState
{
	OOLog(@"dumpState.ai", @"State machine name: %@", stateMachineName);
	OOLog(@"dumpState.ai", @"Current state: %@", currentState);
#ifdef OO_BRAIN_AI
	if (rulingInstinct!= nil && OOLogWillDisplayMessagesInClass(@"dumpState.ai.instinct"))
	{
		OOLog(@"dumpState.ai.instinct", @"Ruling instinct:");
		OOLogPushIndent();
		OOLogIndent();
		NS_DURING
			[rulingInstinct dumpState];
		NS_HANDLER
		NS_ENDHANDLER
		OOLogPopIndent();
	}
#endif
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
	OOAIDeferredCallTrampolineInfo	infoStruct;
	NSValue							*info = nil;
	
	if (selector != NULL)
	{
		infoStruct.ai = [self retain];
		infoStruct.selector = selector;
		infoStruct.parameter = object;
		
		info = [[NSValue alloc] initWithBytes:&infoStruct objCType:@encode(OOAIDeferredCallTrampolineInfo)];
		
		[[AI class] performSelector:@selector(deferredCallTrampolineWithInfo:)
						 withObject:info
						 afterDelay:delay];
		[info release];
	}
}


+ (void)deferredCallTrampolineWithInfo:(NSValue *)info
{
	OOAIDeferredCallTrampolineInfo	infoStruct;
	
	if (info != nil)
	{
		assert(strcmp([info objCType], @encode(OOAIDeferredCallTrampolineInfo)) == 0);
		[info getValue:&infoStruct];
		
		[infoStruct.ai performSelector:infoStruct.selector withObject:infoStruct.parameter];
		
		[infoStruct.ai release];
		[infoStruct.parameter release];
	}
}


- (void)refreshOwnerDesc
{
	ShipEntity *owner = [self owner];
	[ownerDesc release];
	if (owner != nil)
	{
		ownerDesc = [[NSString alloc] initWithFormat:@"%@ %d", [owner name], [owner universalID]];
	}
	else
	{
		ownerDesc = @"no owner";
	}
}


- (NSDictionary *) loadStateMachine:(NSString *)smName
{
	NSDictionary			*newSM = nil;
	NSMutableDictionary		*cleanSM = nil;
	OOCacheManager			*cacheMgr = [OOCacheManager sharedCache];
	NSEnumerator			*stateEnum = nil;
	NSString				*stateKey = nil;
	NSDictionary			*stateHandlers = nil;
	NSAutoreleasePool		*pool = nil;
	
	newSM = [cacheMgr objectForKey:smName inCache:@"AIs"];
	if (newSM != nil && ![newSM isKindOfClass:[NSDictionary class]])  return nil;	// catches use of @"nil" to indicate no AI found.
	
	if (newSM == nil)
	{
		pool = [[NSAutoreleasePool alloc] init];
		OOLog(@"ai.load", @"Loading and sanitizing AI \"%@\"", smName);
		OOLogPushIndent();
		OOLogIndentIf(@"ai.load");
		
		NS_DURING
			// Load state machine and validate against whitelist.
			newSM = [ResourceManager dictionaryFromFilesNamed:smName inFolder:@"AIs" mergeMode:MERGE_NONE cache:NO];
			if (newSM == nil)
			{
				[cacheMgr setObject:@"nil" forKey:smName inCache:@"AIs"];
				OOLog(@"ai.load.failed.unknownAI", @"Can't switch AI for %@ from %@:%@ to \"%@\" - could not load file.", [[self owner] shortDescription], [self name], [self state], smName);
				NS_VALUERETURN(nil, NSDictionary *);
			}
			
			cleanSM = [NSMutableDictionary dictionaryWithCapacity:[newSM count]];
			
			for (stateEnum = [newSM keyEnumerator]; (stateKey = [stateEnum nextObject]); )
			{
				stateHandlers = [newSM objectForKey:stateKey];
				if (![stateHandlers isKindOfClass:[NSDictionary class]])
				{
					OOLogWARN(@"ai.invalidFormat.state", @"State \"%@\" in AI \"%@\" is not a dictionary, ignoring.", stateKey, smName);
					continue;
				}
				
				stateHandlers = [self cleanHandlers:stateHandlers forState:stateKey stateMachine:smName];
				[cleanSM setObject:stateHandlers forKey:stateKey];
			}
			
			// Make immutable.
			newSM = [[cleanSM copy] autorelease];
			
#if DEBUG_GRAPHVIZ
			if ([[NSUserDefaults standardUserDefaults] boolForKey:@"generate-ai-graphviz"])
			{
				GenerateGraphVizForStateMachine(newSM, smName);
			}
#endif
			
			// Cache.
			[cacheMgr setObject:newSM forKey:smName inCache:@"AIs"];
		NS_HANDLER
			OOLogPopIndent();
			[localException raise];
		NS_ENDHANDLER
		
		OOLogPopIndent();
		[pool release];
	}
	
	return newSM;
}


- (NSDictionary *) cleanHandlers:(NSDictionary *)handlers forState:(NSString *)stateKey stateMachine:(NSString *)smName
{
	NSEnumerator			*handlerEnum = nil;
	NSString				*handlerKey = nil;
	NSArray					*handlerActions = nil;
	NSMutableDictionary		*result = nil;
	
	result = [NSMutableDictionary dictionaryWithCapacity:[handlers count]];
	for (handlerEnum = [handlers keyEnumerator]; (handlerKey = [handlerEnum nextObject]); )
	{
		handlerActions = [handlers objectForKey:handlerKey];
		if (![handlerActions isKindOfClass:[NSArray class]])
		{
			OOLogWARN(@"ai.invalidFormat.handler", @"Handler \"%@\" for state \"%@\" in AI \"%@\" is not an array, ignoring.", handlerKey, stateKey, smName);
			continue;
		}
		
		handlerActions = [self cleanActions:handlerActions forHandler:handlerKey state:stateKey stateMachine:smName];
		[result setObject:handlerActions forKey:handlerKey];
	}
	
	// Return immutable copy.
	return [[result copy] autorelease];
}


- (NSArray *) cleanActions:(NSArray *)actions forHandler:(NSString *)handlerKey state:(NSString *)stateKey stateMachine:(NSString *)smName
{
	NSEnumerator			*actionEnum = nil;
	NSString				*action = nil;
	NSRange					spaceRange;
	NSString				*selector = nil;
	id						aliasedSelector = nil;
	NSMutableArray			*result = nil;
	static NSSet			*whitelist = nil;
	static NSDictionary		*aliases = nil;
	NSArray					*whitelistArray1 = nil;
	NSArray					*whitelistArray2 = nil;
	
	if (whitelist == nil)
	{
		whitelistArray1 = [[ResourceManager whitelistDictionary] oo_arrayForKey:@"ai_methods"];
		if (whitelistArray1 == nil)  whitelistArray1 = [NSArray array];
		whitelistArray2 = [[ResourceManager whitelistDictionary] oo_arrayForKey:@"ai_and_action_methods"];
		if (whitelistArray2 != nil)  whitelistArray1 = [whitelistArray1 arrayByAddingObjectsFromArray:whitelistArray2];
		
		whitelist = [[NSSet alloc] initWithArray:whitelistArray1];
		aliases = [[[ResourceManager whitelistDictionary] oo_dictionaryForKey:@"ai_method_aliases"] retain];
	}
	
	result = [NSMutableArray arrayWithCapacity:[actions count]];
	for (actionEnum = [actions objectEnumerator]; (action = [actionEnum nextObject]); )
	{
		if (![action isKindOfClass:[NSString class]])
		{
			OOLogWARN(@"ai.invalidFormat.action", @"An action in handler \"%@\" for state \"%@\" in AI \"%@\" is not a string, ignoring.", handlerKey, stateKey, smName);
			continue;
		}
		
		// Trim spaces from beginning and end.
		action = [action stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
		
		// Cut off parameters.
		spaceRange = [action rangeOfString:@" "];
		if (spaceRange.location == NSNotFound)  selector = action;
		else  selector = [action substringToIndex:spaceRange.location];
		
		// Look in alias table.
		aliasedSelector = [aliases objectForKey:selector];
		if (aliasedSelector != nil)
		{
			if ([aliasedSelector isKindOfClass:[NSString class]])
			{
				// Change selector and action to use real method name.
				selector = aliasedSelector;
				if (spaceRange.location == NSNotFound)  action = aliasedSelector;
				else action = [aliasedSelector stringByAppendingString:[action substringFromIndex:spaceRange.location]];
			}
			else if ([aliasedSelector isKindOfClass:[NSArray class]] && [aliasedSelector count] != 0)
			{
				// Alias is complete expression, pretokenized in anticipation of a tokenized future.
				action = [aliasedSelector componentsJoinedByString:@" "];
				selector = [[aliasedSelector objectAtIndex:0] description];
			}
		}
		
		// Check for selector in whitelist.
		if (![whitelist containsObject:selector])
		{
			OOLog(@"ai.unpermittedMethod", @"Handler \"%@\" for state \"%@\" in AI \"%@\" uses \"%@\", which is not a permitted AI method. In a future version of Oolite, this method will be removed from the handler. If you believe the handler should be a permitted method, please report it to bugs@oolite.org.", handlerKey, stateKey, smName, selector);
			// continue;
		}
		
		[result addObject:action];
	}
	
	// Return immutable copy.
	return [[result copy] autorelease];
}

@end


#if DEBUG_GRAPHVIZ

// Generate and track unique identifiers for state-handler pairs.
static NSString *HandlerToken(NSString *state, NSString *handler, NSMutableDictionary *handlerKeys, NSMutableSet *uniqueSet);
static void AddSimpleSpecialNodeLink(NSMutableString *graphViz, NSString *handlerToken, NSString *name, NSString *shape, NSString *color, NSMutableSet *specialNodes);


static void GenerateGraphVizForStateMachine(NSDictionary *stateMachine, NSString *smName)
{
	NSMutableSet *uniqueSet = [NSMutableSet set];
	NSMutableDictionary *handlerKeys = [NSMutableDictionary dictionary];
	
	NSMutableString *graphViz =
	[NSMutableString stringWithFormat:
	 @"digraph ai_flow\n{\n"
	 "\tgraph [charset=\"UTF-8\", label=\"%@ transition diagram\", labelloc=t, labeljust=l rankdir=LR compound=true nodesep=0.1 ranksep=2.5 fontname=Helvetica]\n"
	 "\tedge [arrowhead=normal]\n"
	 "\tnode [shape=box height=0.2 width=3.5 fontname=Helvetica color=\"#808080\"]\n\t\n"
	 "\tspecial_start [shape=ellipse color=\"#0000C0\" label=\"Start\"]\n\tspecial_start -> %@ [lhead=\"cluster_GLOBAL\" color=\"#0000A0\"]\n", EscapedGraphVizString(smName), HandlerToken(@"GLOBAL", @"ENTER", handlerKeys, uniqueSet)];
	
	NSEnumerator *stateKeyEnum = [stateMachine keyEnumerator];
	NSString *stateKey = nil;
	
	NSMutableSet *specialNodes = [NSMutableSet set];
	
	while ((stateKey = [stateKeyEnum nextObject]))
	{
		NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
		
		[graphViz appendFormat:@"\t\n\tsubgraph cluster_%@\n\t{\n\t\tlabel=\"%@\"\n", stateKey, EscapedGraphVizString(stateKey)];
		
		NSDictionary *state = [stateMachine oo_dictionaryForKey:stateKey];
		NSEnumerator *handlerKeyEnum = [state keyEnumerator];
		NSString *handlerKey = nil;
		while ((handlerKey = [handlerKeyEnum nextObject]))
		{
			[graphViz appendFormat:@"\t\t%@ [label=\"%@\"]\n", HandlerToken(stateKey, handlerKey, handlerKeys, uniqueSet), EscapedGraphVizString(handlerKey)];
		}
		
		// Ensure there is an ENTER handler for arrows to point at.
		if ([state objectForKey:@"ENTER"] == nil)
		{
			[graphViz appendFormat:@"\t\t%@ [label=\"ENTER (implicit)\"] // No ENTER handler in file, but it's still the target of any incoming transitions.\n", HandlerToken(stateKey, @"ENTER", handlerKeys, uniqueSet)];
		}
		
		[graphViz appendString:@"\t}\n"];
		
		// Go through each handler looking for interesting methods.
		handlerKeyEnum = [state keyEnumerator];
		while ((handlerKey = [handlerKeyEnum nextObject]))
		{
			NSEnumerator *commandEnum = [[state oo_arrayForKey:handlerKey] objectEnumerator];
			NSString *command = nil;
			BOOL haveSetOrSwichAI = NO;
			
			while ((command = [commandEnum nextObject]))
			{
				NSArray *components = ScanTokensFromString(command);
				NSString *method = [components objectAtIndex:0];
				NSString *handlerToken = HandlerToken(stateKey, handlerKey, handlerKeys, uniqueSet);
				
				if (!haveSetOrSwichAI && [method isEqualToString:@"setStateTo:"])
				{
					if ([components count] > 1)
					{
						NSString *targetState = [components objectAtIndex:1];
						NSString *targetLabel = HandlerToken(targetState, @"ENTER", handlerKeys, uniqueSet);
						BOOL constraint = YES;
						if ([targetState isEqualToString:stateKey])  constraint = NO;
						else if ([targetState isEqualToString:@"GLOBAL"])  constraint = NO;
						
						[graphViz appendFormat:@"\t%@ -> %@ [lhead=cluster_%@%@]\n", handlerToken, targetLabel, targetState, constraint ? @"" : @" constraint=false"];
					}
					else
					{
						[specialNodes addObject:@"\tspecial_brokenSetStateTo [label=\"Broken setStateTo: command!\\n(No target state specified.)\" color=\"#C00000\" shape=diamond]\n"];
						[graphViz appendFormat:@"\t%@ -> special_brokenSetStateTo [color=\"#C00000\"]\n", handlerToken];
					}
				}
				else if ([method isEqualToString:@"becomeExplosion"])
				{
					AddSimpleSpecialNodeLink(graphViz, handlerToken, @"becomeExplosion", @"diamond", @"804000", specialNodes);
				}
				else if ([method isEqualToString:@"becomeEnergyBlast"])
				{
					AddSimpleSpecialNodeLink(graphViz, handlerToken, @"becomeEnergyBlast", @"diamond", @"804000", specialNodes);
				}
				else if ([method isEqualToString:@"landOnPlanet"])
				{
					AddSimpleSpecialNodeLink(graphViz, handlerToken, @"landOnPlanet", @"diamond", @"008040", specialNodes);
				}
				else if ([method isEqualToString:@"performHyperSpaceExit"])
				{
					AddSimpleSpecialNodeLink(graphViz, handlerToken, @"performHyperSpaceExit", @"box", @"008080", specialNodes);
				}
				else if ([method isEqualToString:@"performHyperSpaceExitWithoutReplacing"])
				{
					AddSimpleSpecialNodeLink(graphViz, handlerToken, @"performHyperSpaceExitWithoutReplacing", @"box", @"008080", specialNodes);
				}
				else if ([method isEqualToString:@"enterTargetWormhole"])
				{
					AddSimpleSpecialNodeLink(graphViz, handlerToken, @"enterTargetWormhole", @"box", @"008080", specialNodes);
				}
				else if ([method isEqualToString:@"becomeUncontrolledThargon"])
				{
					AddSimpleSpecialNodeLink(graphViz, handlerToken, @"becomeUncontrolledThargon", @"ellipse", @"804000", specialNodes);
				}
				else if ([method isEqualToString:@"exitAIWithMessage:"])
				{
					NSString *message = ([components count] > 1) ? [components objectAtIndex:1] : nil;
					NSString *token = nil;
					NSString *label = nil;
					if ([message isEqualToString:@"RESTARTED"] || [message length] == 0)
					{
						token = @"exitAI";
						label = @"exitAI";
					}
					else
					{
						token = GraphVizTokenString([@"exitAI_" stringByAppendingString:message], nil);
						label = EscapedGraphVizString([@"exitAIWithMessage:\n" stringByAppendingString:message]);
					}
					
					[specialNodes addObject:[NSString stringWithFormat:@"\t%@ [label=\"%@\" color=\"#0000A0\" shape=ellipse]\n", token, label]];
					[graphViz appendFormat:@"\t%@ -> %@ [color=\"#0000C0\"]\n", handlerToken, token];
				}
				else if ([method isEqualToString:@"setAITo:"])
				{
					if ([components count] > 1)
					{
						NSString *targetAI = [components objectAtIndex:1];
						NSString *token = [@"setAI_" stringByAppendingString:targetAI];
						NSString *label = [@"setAITo:\n" stringByAppendingString:targetAI];
						
						// FIXME: find subsequent setStateTo: and include in node (incl. token)
						haveSetOrSwichAI = YES;
						token = GraphVizTokenString(token, nil);
						label = EscapedGraphVizString(label);
						
						[specialNodes addObject:[NSString stringWithFormat:@"\t%@ [label=\"%@\" color=\"#0000A0\" shape=ellipse]\n", token, label]];
						 [graphViz appendFormat:@"\t%@ -> %@ [color=\"#0000A0\"]\n", handlerToken, token];
					}
					else
					{
						[specialNodes addObject:@"\tspecial_brokenSetAI [label=\"Broken setAITo: command!\\n(No target AI specified.)\" color=\"#C00000\" shape=diamond]\n"];
						[graphViz appendFormat:@"\t%@ -> special_brokenSetAI [color=\"#C00000\"]\n", handlerToken];
					}
				}
				else if ([method isEqualToString:@"switchAITo:"])
				{
					if ([components count] > 1)
					{
						NSString *targetAI = [components objectAtIndex:1];
						NSString *token = [@"switchAI_" stringByAppendingString:targetAI];
						NSString *label = [@"switchAITo:\n" stringByAppendingString:targetAI];
						
						// FIXME: find subsequent setStateTo: and include in node (incl. token)
						haveSetOrSwichAI = YES;
						token = GraphVizTokenString(token, nil);
						label = EscapedGraphVizString(label);
						
						[specialNodes addObject:[NSString stringWithFormat:@"\t%@ [label=\"%@\" color=\"#0000A0\" shape=ellipse]\n", token, label]];
						[graphViz appendFormat:@"\t%@ -> %@ [color=\"#0000A0\"]\n", handlerToken, token];
					}
					else
					{
						[specialNodes addObject:@"\tspecial_brokenSwitchAI [label=\"Broken switchAITo: command!\\n(No target AI specified.)\" color=\"#C00000\" shape=diamond]\n"];
						[graphViz appendFormat:@"\t%@ -> special_brokenSetAI [color=\"#C00000\"]\n", handlerToken];
					}
				}
				else
				{
				//	OOLog(@"temp", @"Uninteresting method %@ in %@:%@:%@", method, smName, stateKey, handlerKey);
				}
			}
		}
		
		[pool release];
	}
	
	if ([specialNodes count] != 0)
	{
		[graphViz appendString:@"\t\n"];
		
		NSEnumerator *specialEnum = [specialNodes objectEnumerator];
		NSString *special = nil;
		while ((special = [specialEnum nextObject]))
		{
			[graphViz appendString:special];
		}
	}
	
	[graphViz appendString:@"}\n"];
	[ResourceManager writeDiagnosticData:[graphViz dataUsingEncoding:NSUTF8StringEncoding] toFileNamed:[smName stringByAppendingPathExtension:@"dot"]];
}


static NSString *HandlerToken(NSString *state, NSString *handler, NSMutableDictionary *handlerKeys, NSMutableSet *uniqueSet)
{
	NSString *result = [[handlerKeys oo_dictionaryForKey:state] oo_stringForKey:handler];
	
	if (result == nil)
	{
		result = [NSString stringWithFormat:@"%@_h_%@", state, handler];
		result = GraphVizTokenString(result, uniqueSet);
		
		NSMutableDictionary *stateDict = [handlerKeys objectForKey:state];
		if (stateDict == nil)
		{
			stateDict = [NSMutableDictionary dictionary];
			[handlerKeys setObject:stateDict forKey:state];
		}
		
		[stateDict setObject:result forKey:handler];
	}
	
	return result;
}


static void AddSimpleSpecialNodeLink(NSMutableString *graphViz, NSString *handlerToken, NSString *name, NSString *shape, NSString *color, NSMutableSet *specialNodes)
{
	NSString *identifier = GraphVizTokenString([@"special_" stringByAppendingString:name], nil);
	NSString *declaration = [NSString stringWithFormat:@"\t%@ [label=\"%@\" color=\"#%@\" shape=%@]\n", identifier, EscapedGraphVizString(name), color, shape];
	[specialNodes addObject:declaration];
	
	[graphViz appendFormat:@"\t%@ -> %@ [color=\"#%@\"]\n", handlerToken, identifier, color];
}

#endif
