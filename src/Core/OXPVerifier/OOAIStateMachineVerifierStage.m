/*

OOAIStateMachineVerifierStage.m


Oolite
Copyright (C) 2004-2012 Giles C Williams and contributors

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

#import "OOAIStateMachineVerifierStage.h"
#import "OOCollectionExtractors.h"
#import "OOPListParsing.h"

#if OO_OXP_VERIFIER_ENABLED

#import "ResourceManager.h"

static NSString * const kStageName	= @"Validating AIs";


@interface OOAIStateMachineVerifierStage (Private)

- (void) validateAI:(NSString *)aiName;

@end


@implementation OOAIStateMachineVerifierStage

- (void) dealloc
{
	[_whitelist release];
	[_usedAIs release];
	
	[super dealloc];
}


- (NSString *) name
{
	return kStageName;
}


- (BOOL) shouldRun
{
	return [_usedAIs count] != 0;
}


- (void) run
{
	NSArray						*aiNames = nil;
	NSEnumerator				*aiEnum = nil;
	NSString					*aiName = nil;
	NSMutableSet				*whitelist = nil;
	
	// Build whitelist. Note that we merge in aliases since the distinction doesn't matter when just validating.
	whitelist = [[NSMutableSet alloc] init];
	[whitelist addObjectsFromArray:[[ResourceManager whitelistDictionary] oo_arrayForKey:@"ai_methods"]];
	[whitelist addObjectsFromArray:[[ResourceManager whitelistDictionary] oo_arrayForKey:@"ai_and_action_methods"]];
	[whitelist addObjectsFromArray:[[[ResourceManager whitelistDictionary] oo_dictionaryForKey:@"ai_method_aliases"] allKeys]];
	_whitelist = [whitelist copy];
	[whitelist release];
	
	aiNames = [[_usedAIs allObjects] sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
	for (aiEnum = [aiNames objectEnumerator]; (aiName = [aiEnum nextObject]); )
	{
		[self validateAI:aiName];
	}
	
	[_whitelist release];
	_whitelist = nil;
}


+ (NSString *) nameForReverseDependencyForVerifier:(OOOXPVerifier *)verifier
{
	return kStageName;
}


- (void) stateMachineNamed:(NSString *)name usedByShip:(NSString *)shipName
{
	OOFileScannerVerifierStage	*fileScanner = nil;
	
	if (name == nil)  return;
	if ([_usedAIs containsObject:name])  return;
	if (_usedAIs == nil)  _usedAIs = [[NSMutableSet alloc] init];
	[_usedAIs addObject:name];
	
	fileScanner = [[self verifier] fileScannerStage];
	if (![fileScanner fileExists:name
						inFolder:@"AIs"
				  referencedFrom:[NSString stringWithFormat:@"shipdata.plist entry \"%@\"", shipName]
					checkBuiltIn:YES])
	{
		OOLog(@"verifyOXP.validateAI.notFound", @"----- WARNING: AI state machine \"%@\" referenced in shipdata.plist entry \"%@\" could not be found in %@ or in Oolite.", name, shipName, [[self verifier] oxpDisplayName]);
	}
}

@end


@implementation OOAIStateMachineVerifierStage (Private)

- (void) validateAI:(NSString *)aiName
{
	NSString				*path = nil;
	NSDictionary			*aiStateMachine = nil;
	NSEnumerator			*stateEnum = nil;
	NSString				*stateKey = nil;
	NSDictionary			*stateHandlers = nil;
	NSEnumerator			*handlerEnum = nil;
	NSString				*handlerKey = nil;
	NSArray					*handlerActions = nil;
	NSEnumerator			*actionEnum = nil;
	NSString				*action = nil;
	NSRange					spaceRange;
	NSString				*selector = nil;
	NSMutableSet			*badSelectors = nil;
	NSString				*badSelectorDesc = nil;
	NSUInteger				index = 0;
	
	OOLog(@"verifyOXP.verbose.validateAI", @"- Validating AI \"%@\".", aiName);
	OOLogIndentIf(@"verifyOXP.verbose.validateAI");
	
	// Attempt to load AI.
	path = [[[self verifier] fileScannerStage] pathForFile:aiName inFolder:@"AIs" referencedFrom:@"AI list" checkBuiltIn:NO];
	if (path == nil)  return;
	
	badSelectors = [NSMutableSet set];
	
	aiStateMachine = OODictionaryFromFile(path);
	if (aiStateMachine == nil)
	{
		OOLog(@"verifyOXP.validateAI.failed.notDictPlist", @"***** ERROR: could not interpret \"%@\" as a dictionary.", path);
		return;
	}
	
	// Validate each state.
	for (stateEnum = [aiStateMachine keyEnumerator]; (stateKey = [stateEnum nextObject]); )
	{
		stateHandlers = [aiStateMachine objectForKey:stateKey];
		if (![stateHandlers isKindOfClass:[NSDictionary class]])
		{
			OOLog(@"verifyOXP.validateAI.failed.invalidFormat.state", @"***** ERROR: state \"%@\" in AI \"%@\" is not a dictionary.", stateKey, aiName);
			continue;
		}
		
		// Verify handlers for this state.
		for (handlerEnum = [stateHandlers keyEnumerator]; (handlerKey = [handlerEnum nextObject]); )
		{
			handlerActions = [stateHandlers objectForKey:handlerKey];
			if (![handlerActions isKindOfClass:[NSArray class]])
			{
				OOLog(@"verifyOXP.validateAI.failed.invalidFormat.handler", @"***** ERROR: handler \"%@\" for state \"%@\" in AI \"%@\" is not an array, ignoring.", handlerKey, stateKey, aiName);
				continue;
			}
			
			// Verify commands for this handler.
			index = 0;
			for (actionEnum = [handlerActions objectEnumerator]; (action = [actionEnum nextObject]); )
			{
				index++;
				if (![action isKindOfClass:[NSString class]])
				{
					OOLog(@"verifyOXP.validateAI.failed.invalidFormat.action", @"***** ERROR: action %lu in handler \"%@\" for state \"%@\" in AI \"%@\" is not a string, ignoring.", index - 1, handlerKey, stateKey, aiName);
					continue;
				}
				
				// Trim spaces from beginning and end.
				action = [action stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
				
				// Cut off parameters.
				spaceRange = [action rangeOfString:@" "];
				if (spaceRange.location == NSNotFound)  selector = action;
				else  selector = [action substringToIndex:spaceRange.location];
				
				// Check against whitelist.
				if (![_whitelist containsObject:selector])
				{
					[badSelectors addObject:selector];
				}
			}
		}
	}
	
	if ([badSelectors count] != 0)
	{
		badSelectorDesc = [[[badSelectors allObjects] sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)] componentsJoinedByString:@", "];
		OOLog(@"verifyOXP.validateAI.failed.badSelector", @"***** ERROR: the AI \"%@\" uses %lu unpermitted method%s: %@", aiName, [badSelectors count], ([badSelectors count] == 1) ? "" : "s", badSelectorDesc);
	}
	
	OOLogOutdentIf(@"verifyOXP.verbose.validateAI");
}

@end

#endif
