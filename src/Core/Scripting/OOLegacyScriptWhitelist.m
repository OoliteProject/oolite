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
static OOOperationType ClassifyLHSConditionSelector(NSString *selectorString, NSString **outSanitizedMethod);
static NSString *SanitizeQueryMethod(NSString *selectorString);	// Checks aliases and whitelist, returns nil if whitelist fails.
static NSArray *AlwaysFalseConditions(void);


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
			OOLog(@"script.syntax.condition.notString", @"SCRIPT ERROR in %@ ***** Bad condition - expected string, got %@; ignoring.", context, [condition class]);
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
		OOLog(@"script.debug.syntax.scriptCondition.noneSpecified", @"SCRIPT ERROR in %@ ***** Empty script condition.", context);
		return NO;
	}
	
	// Parse left-hand side.
	selectorString = [tokens stringAtIndex:0];
	opType = ClassifyLHSConditionSelector(selectorString, &sanitizedSelectorString);
	if (opType >= OP_INVALID)
	{
		OOLog(@"script.unpermittedMethod", @"SCRIPT ERROR in %@ ***** Unpermitted method \"%@\".", context, selectorString);
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
			OOLog(@"script.debug.syntax.badComparison", @"SCRIPT ERROR in %@ ***** Unknown comparison operator \"%@\", will return NO.", context, comparatorString);
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
		OOLog(@"script.debug.syntax.noOperator", @"SCRIPT WARNING in %@ ----- No operator in expression \"%@\", will always evaluate as false.", context, condition);
		return NO;
	}
	
	// Check for invalid opType/comparator combinations.
	if (opType == OP_NUMBER && comparatorValue == COMPARISON_UNDEFINED)
	{
		OOLog(@"script.debug.syntax.invalidOperator", @"SCRIPT ERROR in %@ ***** Comparator \"%@\" is not valid for %@.", context, @"undefined", @"numbers");
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
				OOLog(@"script.debug.syntax.invalidOperator", @"SCRIPT ERROR in %@ ***** Comparator \"%@\" is not valid for %@.", context, OOComparisonTypeToString(comparatorValue), @"booleans");
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


static OOOperationType ClassifyLHSConditionSelector(NSString *selectorString, NSString **outSanitizedSelector)
{
	assert(outSanitizedSelector != NULL);
	
	*outSanitizedSelector = selectorString;
	
	// Allow arbitrary mission_foo or local_foo pseudo-selectors.
	if ([selectorString hasPrefix:@"mission_"])  return OP_MISSION_VAR;
	if ([selectorString hasPrefix:@"local_"])  return OP_LOCAL_VAR;
	
	// If it's a real method, check against whitelist.
	*outSanitizedSelector = SanitizeQueryMethod(selectorString);
	if (*outSanitizedSelector == nil)  return OP_INVALID;
	
	// If it's a real method, and in the whitelist, classify by suffix.
	if ([selectorString hasSuffix:@"_string"])  return OP_STRING;
	if ([selectorString hasSuffix:@"_number"])  return OP_NUMBER;
	if ([selectorString hasSuffix:@"_bool"])  return OP_BOOL;
	
	// If we got here, something's wrong.
	OOLog(@"script.sanitize.unclassifiedSelector", @"***** ERROR: Whitelisted query method \"%@\" has no type suffix, treating as invalid.", selectorString);
	return OP_INVALID;
}


static NSString *SanitizeQueryMethod(NSString *selectorString)
{
	static NSSet				*queryWhitelist = nil;
	static NSDictionary			*queryAliases = nil;
	NSString					*aliasedSelector = nil;
	
	if (queryWhitelist == nil)
	{
		queryWhitelist = [[NSSet alloc] initWithArray:[[ResourceManager whitelistDictionary] arrayForKey:@"query_methods"]];
		queryAliases = [[[ResourceManager whitelistDictionary] dictionaryForKey:@"query_method_aliases"] retain];
	}
	
	aliasedSelector = [queryAliases stringForKey:selectorString];
	if (aliasedSelector != nil)  selectorString = aliasedSelector;
	
	if (![queryWhitelist containsObject:selectorString])  selectorString = nil;
	
	return selectorString;
}


static NSArray *AlwaysFalseConditions(void)
{
	//	Return a conditions array that always evaluates as false.
	return [NSArray arrayWithObject:[NSArray arrayWithObject:[NSNumber numberWithUnsignedInt:OP_FALSE]]];
}
