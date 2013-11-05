/*

OOLegacyScriptWhitelist.m


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

#import "OOLegacyScriptWhitelist.h"
#import "OOStringParsing.h"
#import	"ResourceManager.h"
#import "OOCollectionExtractors.h"
#import "PlayerEntityLegacyScriptEngine.h"
#import "NSDictionaryOOExtensions.h"
#import "OODeepCopy.h"


#define INCLUDE_RAW_STRING !defined(NDEBUG)	// If nonzero, raw condition strings are included; if zero, a placeholder is used.


typedef struct SanStackElement SanStackElement;
struct SanStackElement
{
	SanStackElement		*back;
	NSString			*key;		// Dictionary key; nil for arrays.
	NSUInteger			index;		// Array index if key is nil.
};


static NSArray *OOSanitizeLegacyScriptInternal(NSArray *script, SanStackElement *stack, BOOL allowAIMethods);
static NSArray *OOSanitizeLegacyScriptConditionsInternal(NSArray *conditions, SanStackElement *stack);

static NSArray *SanitizeCondition(NSString *condition, SanStackElement *stack);
static NSArray *SanitizeConditionalStatement(NSDictionary *statement, SanStackElement *stack, BOOL allowAIMethods);
static NSArray *SanitizeActionStatement(NSString *statement, SanStackElement *stack, BOOL allowAIMethods);
static OOOperationType ClassifyLHSConditionSelector(NSString *selectorString, NSString **outSanitizedMethod, SanStackElement *stack);
static NSString *SanitizeQueryMethod(NSString *selectorString);							// Checks aliases and whitelist, returns nil if whitelist fails.
static NSString *SanitizeActionMethod(NSString *selectorString, BOOL allowAIMethods);	// Checks aliases and whitelist, returns nil if whitelist fails.
static NSArray *AlwaysFalseConditions(void);
static BOOL IsAlwaysFalseConditions(NSArray *conditions);

static NSString *StringFromStack(SanStackElement *topOfStack);


NSArray *OOSanitizeLegacyScript(NSArray *script, NSString *context, BOOL allowAIMethods)
{
	SanStackElement stackRoot = { NULL, context, 0 };
	NSArray *result = OOSanitizeLegacyScriptInternal(script, &stackRoot, allowAIMethods);
	return [OODeepCopy(result) autorelease];
}


static NSArray *OOSanitizeLegacyScriptInternal(NSArray *script, SanStackElement *stack, BOOL allowAIMethods)
{
	NSAutoreleasePool			*pool = nil;
	NSMutableArray				*result = nil;
	NSEnumerator				*statementEnum = nil;
	id							statement = nil;
	NSUInteger					index = 0;
	
	pool = [[NSAutoreleasePool alloc] init];
	
	result = [NSMutableArray arrayWithCapacity:[script count]];
	
	for (statementEnum = [script objectEnumerator]; (statement = [statementEnum nextObject]); )
	{
		SanStackElement subStack =
		{
			stack, nil, index++
		};
		
		if ([statement isKindOfClass:[NSDictionary class]])
		{
			statement = SanitizeConditionalStatement(statement, &subStack, allowAIMethods);
		}
		else if ([statement isKindOfClass:[NSString class]])
		{
			statement = SanitizeActionStatement(statement, &subStack, allowAIMethods);
		}
		else
		{
			OOLog(@"script.syntax.statement.invalidType", @"***** SCRIPT ERROR: in %@, statement is of invalid type - expected string or dictionary, got %@.", StringFromStack(stack), [statement class]);
			statement = nil;
		}
		
		if (statement != nil)
		{
			[result addObject:statement];
		}
	}
	
	[result retain];
	[pool release];
	
	return [result autorelease];
}


NSArray *OOSanitizeLegacyScriptConditions(NSArray *conditions, NSString *context)
{
	if (context == nil)  context = @"<anonymous conditions>";
	SanStackElement stackRoot = { NULL, context, 0 };
	NSArray *result = OOSanitizeLegacyScriptConditionsInternal(conditions, &stackRoot);
	return [OODeepCopy(result) autorelease];
}


static NSArray *OOSanitizeLegacyScriptConditionsInternal(NSArray *conditions, SanStackElement *stack)
{
	NSEnumerator				*conditionEnum = nil;
	NSString					*condition = nil;
	NSMutableArray				*result = nil;
	NSArray						*tokens = nil;
	BOOL						OK = YES;
	NSUInteger					index = 0;
	
	if (OOLegacyConditionsAreSanitized(conditions) || conditions == nil)  return conditions;
	
	result = [NSMutableArray arrayWithCapacity:[conditions count]];
	
	for (conditionEnum = [conditions objectEnumerator]; (condition = [conditionEnum nextObject]); )
	{
		SanStackElement subStack =
		{
			stack, nil, index++
		};
		
		if (![condition isKindOfClass:[NSString class]])
		{
			OOLog(@"script.syntax.condition.notString", @"***** SCRIPT ERROR: in %@, bad condition - expected string, got %@; ignoring.", StringFromStack(stack), [condition class]);
			OK = NO;
			break;
		}
		
		tokens = SanitizeCondition(condition, &subStack);
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
	
	if (OK)  return result;
	else  return AlwaysFalseConditions();
}


BOOL OOLegacyConditionsAreSanitized(NSArray *conditions)
{
	if ([conditions count] == 0)  return YES;	// Empty array is safe.
	return [[conditions objectAtIndex:0] isKindOfClass:[NSArray class]];
}


static NSArray *SanitizeCondition(NSString *condition, SanStackElement *stack)
{
	NSArray						*tokens = nil;
	NSUInteger					i, tokenCount;
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
		OOLog(@"script.debug.syntax.scriptCondition.noneSpecified", @"***** SCRIPT ERROR: in %@, empty script condition.", StringFromStack(stack));
		return NO;
	}
	
	// Parse left-hand side.
	selectorString = [tokens oo_stringAtIndex:0];
	opType = ClassifyLHSConditionSelector(selectorString, &sanitizedSelectorString, stack);
	if (opType >= OP_INVALID)
	{
		OOLog(@"script.unpermittedMethod", @"***** SCRIPT ERROR: in %@ (\"%@\"), method \"%@\" not allowed.", StringFromStack(stack), condition, selectorString);
		return NO;
	}
	
	// Parse operator.
	if (tokenCount > 1)
	{
		comparatorString = [tokens oo_stringAtIndex:1];
		if ([comparatorString isEqualToString:@"equal"])  comparatorValue = COMPARISON_EQUAL;
		else if ([comparatorString isEqualToString:@"notequal"])  comparatorValue = COMPARISON_NOTEQUAL;
		else if ([comparatorString isEqualToString:@"lessthan"])  comparatorValue = COMPARISON_LESSTHAN;
		else if ([comparatorString isEqualToString:@"greaterthan"])  comparatorValue = COMPARISON_GREATERTHAN;
		else if ([comparatorString isEqualToString:@"morethan"])  comparatorValue = COMPARISON_GREATERTHAN;
		else if ([comparatorString isEqualToString:@"oneof"])  comparatorValue = COMPARISON_ONEOF;
		else if ([comparatorString isEqualToString:@"undefined"])  comparatorValue = COMPARISON_UNDEFINED;
		else
		{
			OOLog(@"script.debug.syntax.badComparison", @"***** SCRIPT ERROR: in %@ (\"%@\"), unknown comparison operator \"%@\", will return NO.", StringFromStack(stack), condition, comparatorString);
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
		OOLog(@"script.debug.syntax.noOperator", @"----- WARNING: SCRIPT in %@ -- No operator in expression \"%@\", will always evaluate as false.", StringFromStack(stack), condition);
		return NO;
	}
	
	// Check for invalid opType/comparator combinations.
	if (opType == OP_NUMBER && comparatorValue == COMPARISON_UNDEFINED)
	{
		OOLog(@"script.debug.syntax.invalidOperator", @"***** SCRIPT ERROR: in %@ (\"%@\"), comparison operator \"%@\" is not valid for %@.", StringFromStack(stack), condition, @"undefined", @"numbers");
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
				OOLog(@"script.debug.syntax.invalidOperator", @"***** SCRIPT ERROR: in %@ (\"%@\"), comparison operator \"%@\" is not valid for %@.", StringFromStack(stack), condition, OOComparisonTypeToString(comparatorValue), @"booleans");
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
			rhsItem = [tokens oo_stringAtIndex:i];
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
	
	NSString *rawString = nil;
#if INCLUDE_RAW_STRING
	rawString = condition;
#else
	rawString = @"<condition>";
#endif
	
	return [NSArray arrayWithObjects:
			[NSNumber numberWithUnsignedInt:opType],
			rawString,
			sanitizedSelectorString,
			[NSNumber numberWithUnsignedInt:comparatorValue],
			rhs,
			nil];
}


static NSArray *SanitizeConditionalStatement(NSDictionary *statement, SanStackElement *stack, BOOL allowAIMethods)
{
	NSArray					*conditions = nil;
	NSArray					*doActions = nil;
	NSArray					*elseActions = nil;
	
	conditions = [statement oo_arrayForKey:@"conditions"];
	if (conditions == nil)
	{
		OOLog(@"script.syntax.noConditions", @"***** SCRIPT ERROR: in %@, conditions array contains no \"conditions\" entry, ignoring.", StringFromStack(stack));
		return nil;
	}
	
	// Sanitize conditions.
	SanStackElement subStack = { stack, @"conditions", 0 };
	conditions = OOSanitizeLegacyScriptConditionsInternal(conditions, &subStack);
	if (conditions == nil)
	{
		return nil;
	}
	
	// Sanitize do and else.
	if (!IsAlwaysFalseConditions(conditions))  doActions = [statement oo_arrayForKey:@"do"];
	if (doActions != nil)
	{
		subStack.key = @"do";
		doActions = OOSanitizeLegacyScriptInternal(doActions, &subStack, allowAIMethods);
	}
	
	elseActions = [statement oo_arrayForKey:@"else"];
	if (elseActions != nil)
	{
		subStack.key = @"else";
		elseActions = OOSanitizeLegacyScriptInternal(elseActions, &subStack, allowAIMethods);
	}
	
	// If neither does anything, the statment has no effect.
	if ([doActions count] == 0 && [elseActions count] == 0)
	{
		return nil;
	}
	
	if (doActions == nil)  doActions = [NSArray array];
	if (elseActions == nil)  elseActions = [NSArray array];
	
	return [NSArray arrayWithObjects:[NSNumber numberWithBool:YES], conditions, doActions, elseActions, nil];
}


static NSArray *SanitizeActionStatement(NSString *statement, SanStackElement *stack, BOOL allowAIMethods)
{
	NSMutableArray				*tokens = nil;
	NSUInteger					tokenCount;
	NSString					*rawSelectorString = nil;
	NSString					*selectorString = nil;
	NSString					*argument = nil;
	
	tokens = ScanTokensFromString(statement);
	tokenCount = [tokens count];
	if (tokenCount == 0)  return nil;
	
	rawSelectorString = [tokens objectAtIndex:0];
	selectorString = SanitizeActionMethod(rawSelectorString, allowAIMethods);
	if (selectorString == nil)
	{
		OOLog(@"script.unpermittedMethod", @"***** SCRIPT ERROR: in %@ (\"%@\"), method \"%@\" not allowed.", StringFromStack(stack), statement, rawSelectorString);
		return nil;
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
		
		argument = [argument stringByReplacingOccurrencesOfString:@"[credits_number]" withString:@"[_oo_legacy_credits_number]"];
	}
	
	return [NSArray arrayWithObjects:[NSNumber numberWithBool:NO], selectorString, argument, nil];
}


static OOOperationType ClassifyLHSConditionSelector(NSString *selectorString, NSString **outSanitizedSelector, SanStackElement *stack)
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
		return OP_INVALID;
	}
	
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
	static NSSet				*whitelist = nil;
	static NSDictionary			*aliases = nil;
	NSString					*aliasedSelector = nil;
	
	if (whitelist == nil)
	{
		whitelist = [[NSSet alloc] initWithArray:[[ResourceManager whitelistDictionary] oo_arrayForKey:@"query_methods"]];
		aliases = [[[ResourceManager whitelistDictionary] oo_dictionaryForKey:@"query_method_aliases"] retain];
	}
	
	aliasedSelector = [aliases oo_stringForKey:selectorString];
	if (aliasedSelector != nil)  selectorString = aliasedSelector;
	
	if (![whitelist containsObject:selectorString])  selectorString = nil;
	
	return selectorString;
}


static NSString *SanitizeActionMethod(NSString *selectorString, BOOL allowAIMethods)
{
	static NSSet				*whitelist = nil;
	static NSSet				*whitelistWithAI = nil;
	static NSDictionary			*aliases = nil;
	static NSDictionary			*aliasesWithAI = nil;
	NSString					*aliasedSelector = nil;
	
	if (whitelist == nil)
	{
		NSArray						*actionMethods = nil;
		NSArray						*aiMethods = nil;
		NSArray						*aiAndActionMethods = nil;
		
		actionMethods = [[ResourceManager whitelistDictionary] oo_arrayForKey:@"action_methods"];
		aiMethods = [[ResourceManager whitelistDictionary] oo_arrayForKey:@"ai_methods"];
		aiAndActionMethods = [[ResourceManager whitelistDictionary] oo_arrayForKey:@"ai_and_action_methods"];
		
		if (actionMethods == nil)  actionMethods = [NSArray array];
		if (aiMethods == nil)  aiMethods = [NSArray array];
		
		if (aiAndActionMethods != nil)  actionMethods = [actionMethods arrayByAddingObjectsFromArray:aiAndActionMethods];
		
		whitelist = [[NSSet alloc] initWithArray:actionMethods];
		whitelistWithAI = [[NSSet alloc] initWithArray:[aiMethods arrayByAddingObjectsFromArray:actionMethods]];
		
		aliases = [[[ResourceManager whitelistDictionary] oo_dictionaryForKey:@"action_method_aliases"] retain];
		
		aliasesWithAI = [[ResourceManager whitelistDictionary] oo_dictionaryForKey:@"ai_method_aliases"];
		if (aliasesWithAI != nil)
		{
			aliasesWithAI = [[aliasesWithAI dictionaryByAddingEntriesFromDictionary:aliases] copy];
		}
		else
		{
			aliasesWithAI = [aliases copy];
		}
	}
	
	aliasedSelector = [(allowAIMethods ? aliasesWithAI : aliases) oo_stringForKey:selectorString];
	if (aliasedSelector != nil)  selectorString = aliasedSelector;
	
	if (![(allowAIMethods ? whitelistWithAI : whitelist) containsObject:selectorString])  selectorString = nil;
	
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
	return [[conditions oo_arrayAtIndex:0] oo_unsignedIntAtIndex:0] == OP_FALSE;
}


static NSMutableString *StringFromStackInternal(SanStackElement *topOfStack)
{
	if (topOfStack == NULL)  return nil;
	
	NSMutableString *base = StringFromStackInternal(topOfStack->back);
	if (base == nil)  base = [NSMutableString string];
	
	NSString *string = topOfStack->key;
	if (string == nil)  string = [NSString stringWithFormat:@"%lu", (unsigned long)topOfStack->index];
	if ([base length] > 0)  [base appendString:@"."];
	
	[base appendString:string];
	
	return base;
}


static NSString *StringFromStack(SanStackElement *topOfStack)
{
	return StringFromStackInternal(topOfStack);
}
