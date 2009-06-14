/*

OOLegacyScriptWhitelist.m


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

#import "OOLegacyScriptWhitelist.h"
#import "OOStringParsing.h"
#import	"ResourceManager.h"
#import "OOCollectionExtractors.h"
#import "PlayerEntityLegacyScriptEngine.h"


static NSArray *SanitizeCondition(NSString *condition, NSString *context);
static NSArray *SanitizeConditionalStatement(NSDictionary *statement, NSString *context);
static NSArray *SanitizeActionStatement(NSString *statement, NSString *context);
static OOOperationType ClassifyLHSConditionSelector(NSString *selectorString, NSString **outSanitizedMethod, NSString *context);
static NSString *SanitizeQueryMethod(NSString *selectorString);		// Checks aliases and whitelist, returns nil if whitelist fails.
static NSString *SanitizeActionMethod(NSString *selectorString);	// Checks aliases and whitelist, returns nil if whitelist fails.
static NSArray *AlwaysFalseConditions(void);
static BOOL IsAlwaysFalseConditions(NSArray *conditions);


NSArray *OOSanitizeLegacyScript(NSArray *script, NSString *context)
{
	NSAutoreleasePool			*pool = nil;
	NSMutableArray				*result = nil;
	NSEnumerator				*statementEnum = nil;
	id							statement = nil;
	
	pool = [[NSAutoreleasePool alloc] init];
	
	result = [NSMutableArray arrayWithCapacity:[script count]];
	
	for (statementEnum = [script objectEnumerator]; (statement = [statementEnum nextObject]); )
	{
		if ([statement isKindOfClass:[NSDictionary class]])
		{
			statement = SanitizeConditionalStatement(statement, context);
		}
		else if ([statement isKindOfClass:[NSString class]])
		{
			statement = SanitizeActionStatement(statement, context);
		}
		else
		{
			OOLog(@"script.syntax.statement.invalidType", @"***** SCRIPT ERROR: in %@, statement is of invalid type - expected string or dictionary, got %@.", context, [statement class]);
			statement = nil;
		}
		
		if (statement != nil)
		{
			[result addObject:statement];
		}
	}
	
	result = [result copy];
	[pool release];
	
	return [result autorelease];
}


NSArray *OOSanitizeLegacyScriptConditions(NSArray *conditions, NSString *context)
{
	NSEnumerator				*conditionEnum = nil;
	NSString					*condition = nil;
	NSMutableArray				*result = nil;
	NSArray						*tokens = nil;
	BOOL						OK = YES;
	
	if (OOLegacyConditionsAreSanitized(conditions) || conditions == nil)  return conditions;
	if (context == nil)  context = @"<anonymous conditions>";
	
	result = [NSMutableArray arrayWithCapacity:[conditions count]];
	
	for (conditionEnum = [conditions objectEnumerator]; (condition = [conditionEnum nextObject]); )
	{
		if (![condition isKindOfClass:[NSString class]])
		{
			OOLog(@"script.syntax.condition.notString", @"***** SCRIPT ERROR: in %@, bad condition - expected string, got %@; ignoring.", context, [condition class]);
			OK = NO;
			break;
		}
		
		tokens = SanitizeCondition(condition, context);
		if (tokens != nil)
		{
			[result addObject:tokens];
		}
		else
		{
			OK = NO;
			break;
		}
	}
	
	if (OK)  return [[result copy] autorelease];
	else  return AlwaysFalseConditions();
}


BOOL OOLegacyConditionsAreSanitized(NSArray *conditions)
{
	if ([conditions count] == 0)  return YES;	// Empty array is safe.
	return [[conditions objectAtIndex:0] isKindOfClass:[NSArray class]];
}


static NSArray *SanitizeCondition(NSString *condition, NSString *context)
{
	NSArray						*tokens = nil;
	OOUInteger					i, tokenCount;
	OOOperationType				opType;
	NSString					*selectorString = nil;
	NSString					*sanitizedSelectorString = nil;
	NSString					*comparatorString = nil;
	OOComparisonType			comparatorValue;
	NSMutableArray				*rhs = nil;
	NSString					*rhsItem = nil;
	NSString					*rhsSelector = nil;
	NSArray						*sanitizedRHSItem = nil;
	NSString					*stringSegment = nil;
	
	tokens = ScanTokensFromString(condition);
	tokenCount = [tokens count];
	
	if (tokenCount < 1)
	{
		OOLog(@"script.debug.syntax.scriptCondition.noneSpecified", @"***** SCRIPT ERROR: in %@, empty script condition.", context);
		return NO;
	}
	
	// Parse left-hand side.
	selectorString = [tokens stringAtIndex:0];
	opType = ClassifyLHSConditionSelector(selectorString, &sanitizedSelectorString, context);
	if (opType >= OP_INVALID)
	{
		OOLog(@"script.unpermittedMethod", @"***** SCRIPT ERROR: in %@, method '%@' not allowed.", context, selectorString);
		return NO;
	}
	
	// Parse operator.
	if (tokenCount > 1)
	{
		comparatorString = [tokens stringAtIndex:1];
		if ([comparatorString isEqualToString:@"equal"])  comparatorValue = COMPARISON_EQUAL;
		else if ([comparatorString isEqualToString:@"notequal"])  comparatorValue = COMPARISON_NOTEQUAL;
		else if ([comparatorString isEqualToString:@"lessthan"])  comparatorValue = COMPARISON_LESSTHAN;
		else if ([comparatorString isEqualToString:@"greaterthan"])  comparatorValue = COMPARISON_GREATERTHAN;
		else if ([comparatorString isEqualToString:@"morethan"])  comparatorValue = COMPARISON_GREATERTHAN;
		else if ([comparatorString isEqualToString:@"oneof"])  comparatorValue = COMPARISON_ONEOF;
		else if ([comparatorString isEqualToString:@"undefined"])  comparatorValue = COMPARISON_UNDEFINED;
		else
		{
			OOLog(@"script.debug.syntax.badComparison", @"***** SCRIPT ERROR: in %@, unknown comparison operator '%@', will return NO.", context, comparatorString);
			return NO;
		}
	}
	else
	{
		/*	In the direct interpreter, having no operator resulted in an
			implicit COMPARISON_NO operator, which always evaluated to false.
			Returning NO here causes AlwaysFalseConditions() to be used, which
			has the same effect.
		 */
		OOLog(@"script.debug.syntax.noOperator", @"----- WARNING: SCRIPT in %@ -- No operator in expression '%@', will always evaluate as false.", context, condition);
		return NO;
	}
	
	// Check for invalid opType/comparator combinations.
	if (opType == OP_NUMBER && comparatorValue == COMPARISON_UNDEFINED)
	{
		OOLog(@"script.debug.syntax.invalidOperator", @"***** SCRIPT ERROR: in %@, comparison operator '%@' is not valid for %@.", context, @"undefined", @"numbers");
		return NO;
	}
	else if (opType == OP_BOOL)
	{
		switch (comparatorValue)
		{
			// Valid comparators
			case COMPARISON_EQUAL:
			case COMPARISON_NOTEQUAL:
				break;
			
			default:
				OOLog(@"script.debug.syntax.invalidOperator", @"***** SCRIPT ERROR: in %@, comparison operator '%@' is not valid for %@.", context, OOComparisonTypeToString(comparatorValue), @"booleans");
				return NO;
				
		}
	}
	
	/*	Parse right-hand side. Each token is converted to an array of the
		token and a boolean indicating whether it's a selector.
		
		This also coalesces non-selector tokens, i.e. whitespace-separated
		string segments.
	*/
	if (tokenCount > 2)
	{
		rhs = [NSMutableArray arrayWithCapacity:tokenCount - 2];
		for (i = 2; i < tokenCount; i++)
		{
			rhsItem = [tokens stringAtIndex:i];
			rhsSelector = SanitizeQueryMethod(rhsItem);
			if (rhsSelector != nil)
			{
				// Method
				if (stringSegment != nil)
				{
					// Add stringSegment as a literal token.
					sanitizedRHSItem = [NSArray arrayWithObjects:[NSNumber numberWithBool:NO], stringSegment, nil];
					[rhs addObject:sanitizedRHSItem];
					stringSegment = nil;
				}
				
				sanitizedRHSItem = [NSArray arrayWithObjects:[NSNumber numberWithBool:YES], rhsSelector, nil];
				[rhs addObject:sanitizedRHSItem];
			}
			else
			{
				// String; append to stringSegment
				if (stringSegment == nil)  stringSegment = rhsItem;
				else  stringSegment = [NSString stringWithFormat:@"%@ %@", stringSegment, rhsItem];
			}
		}
		
		if (stringSegment != nil)
		{
			sanitizedRHSItem = [NSArray arrayWithObjects:[NSNumber numberWithBool:NO], stringSegment, nil];
			[rhs addObject:sanitizedRHSItem];
		}
	}
	else
	{
		rhs = [NSArray array];
	}
	
	return [NSArray arrayWithObjects:
			[NSNumber numberWithUnsignedInt:opType],
			condition,
			sanitizedSelectorString,
			[NSNumber numberWithUnsignedInt:comparatorValue],
			rhs,
			nil];
}


static NSArray *SanitizeConditionalStatement(NSDictionary *statement, NSString *context)
{
	NSArray					*conditions = nil;
	NSArray					*doActions = nil;
	NSArray					*elseActions = nil;
	
	conditions = [statement arrayForKey:@"conditions"];
	if (conditions == nil)
	{
		OOLog(@"script.syntax.noConditions", @"***** SCRIPT ERROR: in %@, conditions array contains no \"conditions\" entry, ignoring.", context);
		return nil;
	}
	
	// Sanitize conditions.
	conditions = OOSanitizeLegacyScriptConditions(conditions, context);
	if (conditions == nil)
	{
		return nil;
	}
	
	// Sanitize do and else.
	if (!IsAlwaysFalseConditions(conditions))  doActions = [statement arrayForKey:@"do"];
	if (doActions != nil)  doActions = OOSanitizeLegacyScript(doActions, context);
	
	elseActions = [statement arrayForKey:@"else"];
	if (elseActions != nil)  elseActions = OOSanitizeLegacyScript(elseActions, context);
	
	// If neither does anything, the statment has no effect.
	if ([doActions count] == 0 && [elseActions count] == 0)
	{
		return nil;
	}
	
	if (doActions == nil)  doActions = [NSArray array];
	if (elseActions == nil)  elseActions = [NSArray array];
	
	return [NSArray arrayWithObjects:[NSNumber numberWithBool:YES], conditions, doActions, elseActions, nil];
}


static NSArray *SanitizeActionStatement(NSString *statement, NSString *context)
{
	NSMutableArray				*tokens = nil;
	OOUInteger					tokenCount;
	NSString					*rawSelectorString = nil;
	NSString					*selectorString = nil;
	NSString					*argument = nil;
	
	tokens = ScanTokensFromString(statement);
	tokenCount = [tokens count];
	if (tokenCount == 0)  return nil;
	
	rawSelectorString = [tokens objectAtIndex:0];
	selectorString = SanitizeActionMethod(rawSelectorString);
	if (selectorString == nil)
	{
		OOLog(@"script.unpermittedMethod", @"***** SCRIPT ERROR: in %@, method '%@' not allowed. In a future version of Oolite, this method will be removed from the handler. If you believe the handler should allow this method, please report it to bugs@oolite.org.", context, rawSelectorString);
		
	//	return nil;
		selectorString = rawSelectorString;
	}
	
	if ([selectorString isEqualToString:@"doNothing"])
	{
		return nil;
	}
	
	if ([selectorString hasSuffix:@":"])
	{
		// Expects an argument
		if (tokenCount == 2)
		{
			argument = [tokens objectAtIndex:1];
		}
		else
		{
			[tokens removeObjectAtIndex:0];
			argument = [tokens componentsJoinedByString:@" "];
		}
	}
	
	return [NSArray arrayWithObjects:[NSNumber numberWithBool:NO], selectorString, argument, nil];
}


static OOOperationType ClassifyLHSConditionSelector(NSString *selectorString, NSString **outSanitizedSelector, NSString *context)
{
	assert(outSanitizedSelector != NULL);
	
	*outSanitizedSelector = selectorString;
	
	// Allow arbitrary mission_foo or local_foo pseudo-selectors.
	if ([selectorString hasPrefix:@"mission_"])  return OP_MISSION_VAR;
	if ([selectorString hasPrefix:@"local_"])  return OP_LOCAL_VAR;
	
	// If it's a real method, check against whitelist.
	*outSanitizedSelector = SanitizeQueryMethod(selectorString);
	if (*outSanitizedSelector == nil)
	{
		OOLog(@"script.unpermittedMethod", @"***** SCRIPT ERROR: in %@, method '%@' not allowed. In a future version of Oolite, this method will be removed from the handler. If you believe the handler should allow this method, please report it to bugs@oolite.org.", context, selectorString);
		
		// return OP_INVALID;
		*outSanitizedSelector = selectorString;
	}
	
	// If it's a real method, and in the whitelist, classify by suffix.
	if ([selectorString hasSuffix:@"_string"])  return OP_STRING;
	if ([selectorString hasSuffix:@"_number"])  return OP_NUMBER;
	if ([selectorString hasSuffix:@"_bool"])  return OP_BOOL;
	
	// If we got here, something's wrong.
	OOLog(@"script.sanitize.unclassifiedSelector", @"***** ERROR: Whitelisted query method '%@' has no type suffix, treating as invalid.", selectorString);
	return OP_INVALID;
}


static NSString *SanitizeQueryMethod(NSString *selectorString)
{
	static NSSet				*whitelist = nil;
	static NSDictionary			*aliases = nil;
	NSString					*aliasedSelector = nil;
	
	if (whitelist == nil)
	{
		whitelist = [[NSSet alloc] initWithArray:[[ResourceManager whitelistDictionary] arrayForKey:@"query_methods"]];
		aliases = [[[ResourceManager whitelistDictionary] dictionaryForKey:@"query_method_aliases"] retain];
	}
	
	aliasedSelector = [aliases stringForKey:selectorString];
	if (aliasedSelector != nil)  selectorString = aliasedSelector;
	
	if (![whitelist containsObject:selectorString])  selectorString = nil;
	
	return selectorString;
}


static NSString *SanitizeActionMethod(NSString *selectorString)
{
	static NSSet				*whitelist = nil;
	static NSDictionary			*aliases = nil;
	NSString					*aliasedSelector = nil;
	NSArray						*whitelistArray1 = nil;
	NSArray						*whitelistArray2 = nil;
	
	if (whitelist == nil)
	{
		whitelistArray1 = [[ResourceManager whitelistDictionary] arrayForKey:@"action_methods"];
		if (whitelistArray1 == nil)  whitelistArray1 = [NSArray array];
		whitelistArray2 = [[ResourceManager whitelistDictionary] arrayForKey:@"ai_and_action_methods"];
		if (whitelistArray2 != nil)  whitelistArray1 = [whitelistArray1 arrayByAddingObjectsFromArray:whitelistArray2];
		
		whitelist = [[NSSet alloc] initWithArray:whitelistArray1];
		aliases = [[[ResourceManager whitelistDictionary] dictionaryForKey:@"action_method_aliases"] retain];
	}
	
	aliasedSelector = [aliases stringForKey:selectorString];
	if (aliasedSelector != nil)  selectorString = aliasedSelector;
	
	if (![whitelist containsObject:selectorString])  selectorString = nil;
	
	return selectorString;
}


//	Return a conditions array that always evaluates as false.
static NSArray *AlwaysFalseConditions(void)
{
	static NSArray *alwaysFalse = nil;
	if (alwaysFalse != nil)
	{
		alwaysFalse = [NSArray arrayWithObject:[NSArray arrayWithObject:[NSNumber numberWithUnsignedInt:OP_FALSE]]];
		[alwaysFalse retain];
	}
	
	return alwaysFalse;
}


static BOOL IsAlwaysFalseConditions(NSArray *conditions)
{
	return [[conditions arrayAtIndex:0] unsignedIntAtIndex:0] == OP_FALSE;
}
