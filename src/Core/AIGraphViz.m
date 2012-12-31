/*

AIGraphViz.m

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

#if DEBUG_GRAPHVIZ

#import "OOStringParsing.h"
#import "ResourceManager.h"
#import "OOCollectionExtractors.h"


// Generate and track unique identifiers for state-handler pairs.
static NSString *HandlerToken(NSString *state, NSString *handler, NSMutableDictionary *handlerKeys, NSMutableSet *uniqueSet);
static void HandleOneCommand(NSMutableString *graphViz, NSString *stateKey, NSString *handlerKey, NSMutableDictionary *handlerKeys, NSArray *handlerCommands, NSUInteger commandIter, NSUInteger commandCount, NSMutableSet *specialNodes, NSMutableSet *uniqueSet, BOOL *haveSetOrSwichAI);
static void AddSimpleSpecialNodeLink(NSMutableString *graphViz, NSString *handlerToken, NSString *name, NSString *shape, NSString *color, NSMutableSet *specialNodes);
static void AddExitAINode(NSMutableString *graphViz, NSString *handlerToken, NSString *message, NSMutableSet *specialNodes);
static void AddChangeAINode(NSMutableString *graphViz, NSString *handlerToken, NSString *method, NSArray *components, NSArray *handlerCommands, NSUInteger commandIter, NSUInteger commandCount, NSMutableSet *specialNodes);


void GenerateGraphVizForAIStateMachine(NSDictionary *stateMachine, NSString *smName)
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
			NSArray *handlerCommands = [state oo_arrayForKey:handlerKey];
			NSUInteger commandIter, commandCount = [handlerCommands count];
			BOOL haveSetOrSwichAI = NO;
			
			for (commandIter = 0; commandIter < commandCount; commandIter++)
			{
				HandleOneCommand(graphViz, stateKey, handlerKey, handlerKeys, handlerCommands, commandIter, commandCount, specialNodes, uniqueSet, &haveSetOrSwichAI);
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
	[ResourceManager writeDiagnosticString:graphViz toFileNamed:[NSString stringWithFormat:@"AI Dumps/%@.dot", smName]];
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


static void HandleOneCommand(NSMutableString *graphViz, NSString *stateKey, NSString *handlerKey, NSMutableDictionary *handlerKeys, NSArray *handlerCommands, NSUInteger commandIter, NSUInteger commandCount, NSMutableSet *specialNodes, NSMutableSet *uniqueSet, BOOL *haveSetOrSwichAI)
{
	NSString *command = [handlerCommands oo_stringAtIndex:commandIter];
	if (EXPECT_NOT(command == nil))  return;
	
	NSArray *components = ScanTokensFromString(command);
	NSString *method = [components objectAtIndex:0];
	NSString *handlerToken = HandlerToken(stateKey, handlerKey, handlerKeys, uniqueSet);
	
	if (!*haveSetOrSwichAI && [method isEqualToString:@"setStateTo:"])
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
		AddExitAINode(graphViz, handlerToken, message, specialNodes);
	}
	else if ([method isEqualToString:@"setAITo:"] || [method isEqualToString:@"switchAITo:"])
	{
		*haveSetOrSwichAI = YES;
		AddChangeAINode(graphViz, handlerToken, method, components, handlerCommands, commandIter, commandCount, specialNodes);
	}
}


static void AddSimpleSpecialNodeLink(NSMutableString *graphViz, NSString *handlerToken, NSString *name, NSString *shape, NSString *color, NSMutableSet *specialNodes)
{
	NSString *identifier = GraphVizTokenString([@"special_" stringByAppendingString:name], nil);
	NSString *declaration = [NSString stringWithFormat:@"\t%@ [label=\"%@\" color=\"#%@\" shape=%@]\n", identifier, EscapedGraphVizString(name), color, shape];
	[specialNodes addObject:declaration];
	
	[graphViz appendFormat:@"\t%@ -> %@ [color=\"#%@\"]\n", handlerToken, identifier, color];
}


static void AddExitAINode(NSMutableString *graphViz, NSString *handlerToken, NSString *message, NSMutableSet *specialNodes)
{
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


static void AddChangeAINode(NSMutableString *graphViz, NSString *handlerToken, NSString *method, NSArray *components, NSArray *handlerCommands, NSUInteger commandIter, NSUInteger commandCount, NSMutableSet *specialNodes)
{
	NSString *methodTag = [method substringToIndex:[method length] - 3];	// delete "To:".
	
	if ([components count] > 1)
	{
		NSString *targetAI = [components objectAtIndex:1];
		NSString *token = [NSString stringWithFormat:@"%@_%@", methodTag, targetAI];
		NSString *label = [NSString stringWithFormat:@"%@\n%@", method, targetAI];
		
		// Look through remaining commands for a setStateTo:, which applies to the new AI.
		NSString *targetState = nil;
		NSUInteger j = commandIter;
		for (; j < commandCount; j++)
		{
			NSString *command = [handlerCommands oo_stringAtIndex:j];
			if ([command hasPrefix:@"setStateTo:"])
			{
				NSArray *components = ScanTokensFromString(command);
				if ([components count] > 1)  targetState = [components objectAtIndex:1];
			}
		}
		if (targetState != nil)
		{
			token = [NSString stringWithFormat:@"%@_%@", token, targetState];
			label = [NSString stringWithFormat:@"%@ (%@)", label, targetState];
		}
		
		token = GraphVizTokenString(token, nil);
		label = EscapedGraphVizString(label);
		
		[specialNodes addObject:[NSString stringWithFormat:@"\t%@ [label=\"%@\" color=\"#408000\" shape=ellipse]\n", token, label]];
		[graphViz appendFormat:@"\t%@ -> %@ [color=\"#408000\"]\n", handlerToken, token];
	}
	else
	{
		[specialNodes addObject:[NSString stringWithFormat:@"\tspecial_broken_%@ [label=\"Broken %@ command!\\n(No target AI specified.)\" color=\"#C00000\" shape=diamond]\n", methodTag, method]];
		[graphViz appendFormat:@"\t%@ -> tspecial_broken_%@ [color=\"#C00000\"]\n", handlerToken, methodTag];
	}
}

#endif
