/*

AI.m

Oolite
Copyright (C) 2004-2007 Giles C Williams and contributors

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
#import "OOInstinct.h"
#import "OOStringParsing.h"
#import "OOWeakReference.h"

#import "ShipEntity.h"

#define kOOLogUnconvertedNSLog @"unclassified.AI"


typedef struct
{
	AI				*ai;
	SEL				selector;
	id				parameter;
} OOAIDeferredCallTrampolineInfo;


@interface AI (OOPrivate)

// Wrapper for performSelector:withObject:afterDelay: to catch/fix bugs.
- (void)performDeferredCall:(SEL)selector withObject:(id)object afterDelay:(NSTimeInterval)delay;
+ (void)deferredCallTrampolineWithInfo:(NSValue *)info;

- (void)refreshOwnerDesc;

@end


@implementation AI

- (id) init
{    
    self = [super init];
	
	aiStack = [[NSMutableArray alloc] init];
	pendingMessages = [[NSMutableDictionary alloc] init];
	
	nextThinkTime = [[NSDate distantFuture] timeIntervalSinceNow];	// don't think for a while
	thinkTimeInterval = AI_THINK_INTERVAL;
	
	stateMachineName = [[NSString stringWithString:@"None allocated"] retain];	// no initial brain
	
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
	
	[super dealloc];
}


- (NSString *) descriptionComponents
{
	return [NSString stringWithFormat:@"\"%@\" in state: \"%@\" for %@", stateMachineName, currentState, ownerDesc];
}


- (void) setRulingInstinct:(OOInstinct*) instinct
{
	rulingInstinct = instinct;
}


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
	
	if ([aiStack count] > 32)
	{
		NSLog(@"***** ERROR: AI stack overflow for %@ stack:\n%@", _owner, aiStack);
		[NSException raise:@"OoliteException"
					format:@"AI stack overflow for %@", _owner];
	}
	
	if ([[self owner] reportAIMessages])  OOLog(@"ai.stack.push", @"Pushing state machine for %@", self);
	[aiStack insertObject:pickledMachine atIndex:0];	//  PUSH
}


- (void) restorePreviousStateMachine
{
	if ([aiStack count] == 0)  return;
	
	NSMutableDictionary *pickledMachine = [aiStack objectAtIndex:0];
	
	if ([[self owner] reportAIMessages])  OOLog(@"ai.stack.pop", @"Popping previous state machine for %@", self);
	
	[stateMachine release];
	stateMachine = [[pickledMachine objectForKey:@"stateMachine"] retain];
	
	[currentState release];
	currentState = [[pickledMachine objectForKey:@"currentState"] retain];
	
	[stateMachineName release];
	stateMachineName = [[pickledMachine objectForKey:@"stateMachineName"] retain];
	
	[pendingMessages release];
	pendingMessages = [[pickledMachine objectForKey:@"pendingMessages"] mutableCopy];  // restore a MUTABLE array
	
	[aiStack removeObjectAtIndex:0];   //  POP
}


- (BOOL) hasSuspendedStateMachines
{
	return [aiStack count] != 0;
}


- (void) exitStateMachine
{
	if ([aiStack count] != 0)
	{
		[self restorePreviousStateMachine];
		[self reactToMessage:@"RESTARTED"];
	}
}


- (void) setStateMachine:(NSString *) smName
{
	NSDictionary* newSM = [ResourceManager dictionaryFromFilesNamed:smName inFolder:@"AIs" andMerge:NO];
	
	if (newSM)
	{
		[self preserveCurrentStateMachine];
		[stateMachine release];	// release old state machine
		stateMachine = [newSM retain];
		nextThinkTime = 0.0;	// think at next tick
	}
	
	[currentState release];
	currentState = @"GLOBAL";
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
	
	// refresh stateMachineName
	[stateMachineName release];
	stateMachineName = [smName copy];
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


- (int) ai_stack_depth
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
	if (recursionLimiter > 32)
	{
		OOLog(@"ai.error.recursion", @"ERROR: AI reactToMessage: recursion in AI %@, state %@, aborting. It is not valid to call reactToMessage: FOO in state FOO.", stateMachineName, currentState);
		return;
	}
	
	messagesForState = [stateMachine objectForKey:currentState];
	if (messagesForState == nil)  return;
	
	if (currentState != nil && ![message isEqual:@"UPDATE"] && [owner reportAIMessages])
	{
		OOLog(@"ai.message.receive", @"AI for %@ in state '%@' receives message '%@'", ownerDesc, currentState, message);
	}
	
	actions = [[[messagesForState objectForKey:message] copy] autorelease];

	if (rulingInstinct != nil)  [rulingInstinct freezeShipVars];	// preserve the pre-thinking state

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
			SEL _interpretAIMessageSel = @selector(interpretAIMessage:);
			if ([owner respondsToSelector:_interpretAIMessageSel])
				[owner performSelector:_interpretAIMessageSel withObject:message];
		}
	}
	
	if (rulingInstinct != nil)
	{
		[rulingInstinct getShipVars];		// record the post-thinking state
		[rulingInstinct unfreezeShipVars];	// restore the pre-thinking state (AI is now abstract thought = instincts motivate)
	}
}


- (void) takeAction:(NSString *) action
{
	NSArray			*tokens = ScanTokensFromString(action);
	NSString		*dataString = nil;
	NSString		*selectorStr;
	SEL				selector;
	ShipEntity		*owner = [self owner];
	BOOL			report = [owner reportAIMessages];
	
	report = [owner reportAIMessages];
	if (report)
	{
		OOLog(@"ai.takeAction.takeAction", @"%@ to take action %@", ownerDesc, action);
		OOLogIndent();
	}
	
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
				if ([selectorStr isEqual:@"setStateTo:"])  [self setState:dataString];
				else if ([selectorStr isEqual:@"debugMessage:"])
				{
					OOLog(@"ai.takeAction.debugNessage", @"AI-DEBUG MESSAGE from %@ : %@", ownerDesc, dataString);
				}
				else
				{
					OOLog(@"ai.takeAction.badSelector", @"***** %@ does not respond to %@", ownerDesc, selectorStr);
				}
			}
		}
		else
		{
			OOLog(@"ai.takeAction.orphaned", @"***** AI %@, trying to perform %@, is orphaned (no owner)", self, selectorStr);
		}
	}
	else
	{
		if (report)  OOLog(@"ai.takeAction.noAction", @"  - no action '%@'", action);
	}
	
	if (report)
	{
		OOLogOutdent();
	}
}


- (void) think
{
	NSArray			*ms_list = nil;
	unsigned		i;
	
	if ([[self owner] universalID] == NO_TARGET || stateMachine == nil)  return;  // don't think until launched
	
	[self reactToMessage:@"UPDATE"];

	if (pendingMessages != nil)
	{
		if ([pendingMessages count] > 0)
		{
			ms_list = [pendingMessages allKeys];
		}
		
		[pendingMessages removeAllObjects];
	}
	
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
		OOLog(@"ai.message.failed.overflow", @"***** ERROR: AI pending messages overflow for '%@'; pending messages:\n%@", ownerDesc, pendingMessages);
		[NSException raise:@"OoliteException"
					format:@"AI pendingMessages overflow for %@", ownerDesc];
	}
	
	[pendingMessages setObject: ms forKey: ms];
}


- (void) setNextThinkTime:(double) ntt
{
	nextThinkTime = ntt;
}


- (double) nextThinkTime
{
	if (!stateMachine)
		return [[NSDate distantFuture] timeIntervalSinceNow];

	return nextThinkTime;
}


- (void) setThinkTimeInterval:(double) tti
{
	thinkTimeInterval = tti;
}


- (double) thinkTimeInterval
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
	OOLog(@"dumpState.ai", @"Next think time: %g", nextThinkTime);
	OOLog(@"dumpState.ai", @"Next think interval: %g", nextThinkTime);
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
		[info release];
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

@end
