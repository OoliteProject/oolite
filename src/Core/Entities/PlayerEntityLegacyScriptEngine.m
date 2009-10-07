/*

PlayerEntityLegacyScriptEngine.m

Oolite
Copyright (C) 2004-2008 Giles C Williams and contributors

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

#import "PlayerEntityLegacyScriptEngine.h"
#import "PlayerEntityScriptMethods.h"
#import "PlayerEntitySound.h"
#import "GuiDisplayGen.h"
#import "Universe.h"
#import "ResourceManager.h"
#import "AI.h"
#import "ShipEntityAI.h"
#import "ShipEntityScriptMethods.h"
#import "OOScript.h"
#import "OOMusicController.h"
#import "OOColor.h"
#import "OOStringParsing.h"
#import "OOConstToString.h"
#import "OOTexture.h"
#import "OOCollectionExtractors.h"
#import "OOLoggingExtended.h"
#import "OOSound.h"
#import "PlanetEntity.h"
#import "ParticleEntity.h"
#import "StationEntity.h"
#import "Comparison.h"
#import "OOLegacyScriptWhitelist.h"

#define kOOLogUnconvertedNSLog @"unclassified.PlayerEntityLegacyScriptEngine"


#define SUPPORT_TRACE_MESSAGES	(!defined NDEBUG)

// Trace messages are very verbose debug messages in the script mechanism,
// disabled in logcontrol.plist by default and disabled here in release builds
// for performance reasons.
#if SUPPORT_TRACE_MESSAGES
#define TraceLog OOLog
#else
#define TraceLog(...) do {} while (0)
#endif


#define TRACE_AND_RETURN(x)	do { BOOL r = (x); TraceLog(kOOLogTraceTestConditionResult, @"      Result: %@", r ? @"YES" : @"NO"); return r; } while (0)


static NSString * const kOOLogScriptAddShipsFailed			= @"script.addShips.failed";
static NSString * const kOOLogScriptMissionDescNoText		= @"script.missionDescription.noMissionText";
static NSString * const kOOLogScriptMissionDescNoKey		= @"script.missionDescription.noMissionKey";

static NSString * const kOOLogDebug							= @"script.debug";
static NSString * const kOOLogDebugOnMetaClass				= @"$scriptDebugOn";
	   NSString * const kOOLogDebugMessage					= @"script.debug.message";
static NSString * const kOOLogDebugOnOff					= @"script.debug.onOff";
static NSString * const kOOLogDebugAddPlanet				= @"script.debug.addPlanet";
static NSString * const kOOLogDebugReplaceVariablesInString	= @"script.debug.replaceVariablesInString";
static NSString * const kOOLogDebugProcessSceneStringAddScene = @"script.debug.processSceneString.addScene";
static NSString * const kOOLogDebugProcessSceneStringAddModel = @"script.debug.processSceneString.addModel";
static NSString * const kOOLogDebugProcessSceneStringAddMiniPlanet = @"script.debug.processSceneString.addMiniPlanet";
static NSString * const kOOLogDebugProcessSceneStringAddBillboard = @"script.debug.processSceneString.addBillboard";

static NSString * const kOOLogTraceScriptAction				= @"script.debug.trace.scriptAction";
static NSString * const kOOLogTraceTestCondition			= @"script.debug.trace.testCondition";
static NSString * const kOOLogTraceTestConditionCheckingVariable = @"script.debug.trace.testCondition.checkingVariable";
static NSString * const kOOLogTraceTestConditionValues		= @"script.debug.trace.testCondition.testValues";
static NSString * const kOOLogTraceTestConditionResult		= @"script.debug.trace.testCondition.testResult";
static NSString * const kOOLogTraceTestConditionOneOf		= @"script.debug.trace.testCondition.oneOf";

static NSString * const kOOLogNoteRemoveAllCargo			= @"script.debug.note.removeAllCargo";
static NSString * const kOOLogNoteUseSpecialCargo			= @"script.debug.note.useSpecialCargo";
	   NSString * const kOOLogNoteAddShips					= @"script.debug.note.addShips";
static NSString * const kOOLogNoteSet						= @"script.debug.note.set";
static NSString * const kOOLogNoteShowShipModel				= @"script.debug.note.showShipModel";
static NSString * const kOOLogNoteFuelLeak					= @"script.debug.note.setFuelLeak";
static NSString * const kOOLogNoteAddPlanet					= @"script.debug.note.addPlanet";
static NSString * const kOOLogNoteProcessSceneString		= @"script.debug.note.processSceneString";

static NSString * const kOOLogSyntaxBadConditional			= @"script.debug.syntax.badConditional";
static NSString * const kOOLogSyntaxNoAction				= @"script.debug.syntax.action.noneSpecified";
static NSString * const kOOLogSyntaxBadAction				= @"script.debug.syntax.action.badSelector";
static NSString * const kOOLogSyntaxNoScriptCondition		= @"script.debug.syntax.scriptCondition.noneSpecified";
static NSString * const kOOLogSyntaxBadScriptCondition		= @"script.debug.syntax.scriptCondition.badSelector";
static NSString * const kOOLogSyntaxSetPlanetInfo			= @"script.debug.syntax.setPlanetInfo";
static NSString * const kOOLogSyntaxAwardCargo				= @"script.debug.syntax.awardCargo";
static NSString * const kOOLogSyntaxAwardEquipment			= @"script.debug.syntax.awardEquipment";
static NSString * const kOOLogSyntaxMessageShipAIs			= @"script.debug.syntax.messageShipAIs";
	   NSString * const kOOLogSyntaxAddShips				= @"script.debug.syntax.addShips";
static NSString * const kOOLogSyntaxSet						= @"script.debug.syntax.set";
static NSString * const kOOLogSyntaxReset					= @"script.debug.syntax.reset";
static NSString * const kOOLogSyntaxIncrement				= @"script.debug.syntax.increment";
static NSString * const kOOLogSyntaxDecrement				= @"script.debug.syntax.decrement";
static NSString * const kOOLogSyntaxAdd						= @"script.debug.syntax.add";
static NSString * const kOOLogSyntaxSubtract				= @"script.debug.syntax.subtract";

static NSString * const kOOLogRemoveAllCargoNotDocked		= @"script.error.removeAllCargo.notDocked";


#define	ACTIONS_TEMP_PREFIX									"__oolite_actions_temp"
static NSString * const kActionTempPrefix					= @ ACTIONS_TEMP_PREFIX;
static NSString * const kActionTempFormat					= @ ACTIONS_TEMP_PREFIX ".%u";


static NSString		*sMissionStringValue = nil;
static NSString		*sCurrentMissionKey = nil;
static ShipEntity	*scriptTarget = nil;


@interface PlayerEntity (ScriptingPrivate)

- (BOOL) scriptTestCondition:(NSArray *)scriptCondition;
- (NSString *) expandScriptRightHandSide:(NSArray *)rhsComponents;

- (void) scriptActions:(NSArray *)actions forTarget:(ShipEntity *)target missionKey:(NSString *)missionKey;

@end


@implementation PlayerEntity (Scripting)


static NSString *CurrentScriptNameOr(NSString *alternative)
{
	if (sCurrentMissionKey != nil && ![sCurrentMissionKey hasPrefix:kActionTempPrefix])
	{
		return [NSString stringWithFormat:@"\"%@\"", sCurrentMissionKey];
	}
	return alternative;
}


OOINLINE NSString *CurrentScriptName(void)
{
	return CurrentScriptNameOr(nil);
}


OOINLINE NSString *CurrentScriptDesc(void)
{
	return CurrentScriptNameOr(@"<anonymous actions>");
}


static void PerformScriptActions(NSArray *actions, Entity *target);
static void PerformConditionalStatment(NSArray *actions, Entity *target);
static void PerformActionStatment(NSArray *statement, Entity *target);
static BOOL TestScriptConditions(NSArray *conditions);


static void PerformScriptActions(NSArray *actions, Entity *target)
{
	unsigned		i, count;
	NSArray			*statement = nil;
	
	count = [actions count];
	for (i = 0; i < count; i++)
	{
		statement = [actions objectAtIndex:i];
		if ([[statement objectAtIndex:0] boolValue])
		{
			PerformConditionalStatment(statement, target);
		}
		else
		{
			PerformActionStatment(statement, target);
		}
	}
}


static void PerformConditionalStatment(NSArray *statement, Entity *target)
{
	/*	A sanitized conditional statement takes the form of an array:
		(true, conditions, trueActions, falseActions)
		The first element is always true. The second is an array of conditions.
		The third and four elements are actions to perform if the conditions
		evaluate to true or false, respectively.
	*/
	
	NSArray				*conditions = nil;
	NSArray				*actions = nil;
	
	conditions = [statement objectAtIndex:1];
	
	if (TestScriptConditions(conditions))
	{
		actions = [statement objectAtIndex:2];
	}
	else
	{
		actions = [statement objectAtIndex:3];
	}
	
	PerformScriptActions(actions, target);
}


static void PerformActionStatment(NSArray *statement, Entity *target)
{
	/*	A sanitized action statement takes the form of an array:
	 (false, selector [, argument])
	 The first element is always false. The second is the method selector
	 (as a string). If the method takes an argument, the third argument is
	 the argument string.
	 
	 The sanitizer is responsible for ensuring that there is an argument,
	 even if it's the empty string, for any selector with a colon at the
	 end, and no arguments for selectors without colons. The runner can
	 therefore use the list's element count as a flag without examining the
	 selector.
	 */
	
	NSString				*selectorString = nil;
	NSString				*argumentString = nil;
	NSString				*expandedString = nil;
	SEL						selector = NULL;
	NSMutableDictionary		*locals = nil;
	PlayerEntity			*player = [PlayerEntity sharedPlayer];
	
	selectorString = [statement objectAtIndex:1];
	if ([statement count] > 2)  argumentString = [statement objectAtIndex:2];
	
	TraceLog(kOOLogTraceScriptAction, @"script action: \"%@%@\"", selectorString, argumentString ? (NSString *)[@" " stringByAppendingString:argumentString] : (NSString *)@"");
	
	selector = NSSelectorFromString(selectorString);
	
	if (target == nil || ![target respondsToSelector:selector])
	{
		target = player;
	}
	
	if (argumentString != nil)
	{
		// Method with argument; substitute [description] expressions.
		locals = [player localVariablesForMission:sCurrentMissionKey];
		expandedString = ExpandDescriptionsWithLocalsForCurrentSystem(argumentString, locals);
		
#if SUPPORT_TRACE_MESSAGES
		if (![expandedString isEqualToString:argumentString])
		{
			OOLogIndent();
			TraceLog(kOOLogTraceScriptAction, @"script action after expansion: \"%@ %@\"", selectorString, argumentString);
			OOLogOutdent();
		}
#endif
		
		[target performSelector:selector withObject:expandedString];
	}
	else
	{
		// Method without argument.
		[target performSelector:selector];
	}
}


static BOOL TestScriptConditions(NSArray *conditions)
{
	NSEnumerator			*condEnum = nil;
	NSArray					*condition = nil;
	PlayerEntity			*player = [PlayerEntity sharedPlayer];
	
	for (condEnum = [conditions objectEnumerator]; (condition = [condEnum nextObject]); )
	{
		if (![player scriptTestCondition:condition])  return NO;
	}
	
	return YES;
}


- (void) setScriptTarget:(ShipEntity *)ship
{
	scriptTarget = ship;
}


- (ShipEntity*) scriptTarget
{
	return scriptTarget;
}


OOINLINE OOEntityStatus RecursiveRemapStatus(OOEntityStatus status)
{
	// Some player stutuses should only be seen once per "event".
	// This remaps them to something innocuous in case of recursion.
	if (status == STATUS_DOCKING ||
		status == STATUS_LAUNCHING ||
		status == STATUS_ENTERING_WITCHSPACE ||
		status == STATUS_EXITING_WITCHSPACE)
	{
		return STATUS_IN_FLIGHT;
	}
	else
	{
		return status;
	}
}


static BOOL sRunningScript = NO;


- (void) checkScript
{
	BOOL						wasRunningScript = sRunningScript;
	OOEntityStatus				status, restoreStatus;
	
	[self setScriptTarget:self];
	
	OOLogPushIndent();
	OOLog(@"script.trace.runWorld", @"----- Running world script with state %@", [self status_string]);
	OOLogIndentIf(@"script.trace.runWorld");
	
	/*	World scripts can potentially be invoked recursively, through
		scriptActionOnTarget: and possibly other mechanisms. This is bad, but
		that's the way it is. Legacy world scripts rely on only seeing certain
		player statuses once per "event". To ensure this, we must lie about
		the player's status when invoked recursively.
		
		Of course, there are also methods in the game that rely on status not
		lying. However, I don't believe any that rely on these particular
		statuses can be legitimately invoked by scripts. The alternative would
		be to track the "status-as-seen-by-scripts" separately from the "real"
		status, which'd risk synchronization problems.
		
		In summary, scriptActionOnTarget: is bad, and calling it from scripts
		rather than AIs is very bad.
		-- Ahruman, 20080302
		
		Addendum: scriptActionOnTarget: is currently not in the whitelist for
		script methods. Let's hope this doesn't turn out to be a problem.
		-- Ahruman, 20090208
	*/
	status = [self status];
	restoreStatus = status;
	NS_DURING
		if (sRunningScript)
		{
			status = RecursiveRemapStatus(status);
			[self setStatus:status];
			if (RecursiveRemapStatus(status) != restoreStatus)
			{
				OOLog(@"script.trace.runWorld.recurse.lying", @"----- Running world script recursively and temporarily changing player status from %@ to %@.", EntityStatusToString(restoreStatus), EntityStatusToString(status));
			}
			else
			{
				OOLog(@"script.trace.runWorld.recurse", @"----- Running world script recursively.", EntityStatusToString(restoreStatus), EntityStatusToString(status));
			}
		}
		sRunningScript = YES;
		
		// After all that, actually running the scripts is trivial.
		[[worldScripts allValues] makeObjectsPerformSelector:@selector(runWithTarget:) withObject:self];
	NS_HANDLER
		OOLog(kOOLogException, @"***** Exception running world scripts: %@ : %@", [localException name], [localException reason]);
	NS_ENDHANDLER
	
	// Restore anti-recursion measures.
	sRunningScript = wasRunningScript;
	if (status != restoreStatus)  [self setStatus:restoreStatus];
	
	OOLogPopIndent();
}


- (void)runScriptActions:(NSArray *)actions withContextName:(NSString *)contextName forTarget:(ShipEntity *)target
{
	NSAutoreleasePool		*pool = nil;
	NSString				*oldMissionKey = nil;
	NSString * volatile		theMissionKey = contextName;	// Work-around for silly exception macros
	
	pool = [[NSAutoreleasePool alloc] init];
	
	// FIXME: does this actually make sense in the context of non-missions?
	oldMissionKey = sCurrentMissionKey;
	sCurrentMissionKey = theMissionKey;
	[self setScriptTarget:target];
	
	NS_DURING
		PerformScriptActions(actions, target);
	NS_HANDLER
		OOLog(@"script.error.exception",
			  @"***** EXCEPTION %@: %@ while handling legacy script actions for %@",
			  [localException name],
			  [localException reason],
			  [theMissionKey hasPrefix:kActionTempPrefix] ? [target shortDescription] : theMissionKey);
		// Suppress exception
	NS_ENDHANDLER
	
	sCurrentMissionKey = oldMissionKey;
	[pool release];
}


- (void) runUnsanitizedScriptActions:(NSArray *)actions allowingAIMethods:(BOOL)allowAIMethods withContextName:(NSString *)contextName forTarget:(ShipEntity *)target
{
	[self runScriptActions:OOSanitizeLegacyScript(actions, contextName, allowAIMethods)
		   withContextName:contextName
				 forTarget:target];
}


- (BOOL) scriptTestConditions:(NSArray *)array
{
	BOOL				result = NO;
	
	NS_DURING
		result = TestScriptConditions(array);
	NS_HANDLER
		OOLog(@"script.error.exception",
			  @"***** EXCEPTION %@: %@ while testing legacy script conditions.",
			  [localException name],
			  [localException reason]);
		// Suppress exception
	NS_ENDHANDLER
	
	return result;
}


- (BOOL) scriptTestCondition:(NSArray *)scriptCondition
{
	/*	Test a script condition sanitized by OOLegacyScriptWhitelist.
		
		A sanitized condition is an array of the form:
			(opType, rawString, selector, comparisonType, operandArray).
		
		opType and comparisonType are NSNumbers containing OOOperationType and
		OOComparisonType enumerators, respectively.
		
		rawString is the original textual representation of the condition for
		display purposes.
		
		selector is a string, either a method selector or a mission/local
		variable name.
		
		operandArray is an array of operands. Each operand is itself an array
		of two items: a boolean indicating whether it's a method selector
		(true) or a string (false), and a string.
		
		The special opType OP_FALSE doesn't require any other elements in the
		array. All other valid opTypes require the array to have five elements.
		
		For performance reasons, this method assumes the script condition will
		have been generated by OOSanitizeLegacyScriptConditions() and doesn't
		perform extensive validity checks.
	*/
	
	OOOperationType				opType;
	NSString					*selectorString = nil;
	SEL							selector = NULL;
	OOComparisonType			comparator;
	NSArray						*operandArray = nil;
	NSString					*lhsString = nil;
	NSString					*expandedRHS = nil;
	NSArray						*rhsComponents = nil;
	NSString					*rhsItem = nil;
	OOUInteger					i, count;
	NSCharacterSet				*whitespace = nil;
	double						lhsValue, rhsValue;
	BOOL						lhsFlag, rhsFlag;
	
	opType = [scriptCondition oo_unsignedIntAtIndex:0];
	if (opType == OP_FALSE)  return NO;
	
	selectorString = [scriptCondition oo_stringAtIndex:2];
	comparator = [scriptCondition oo_unsignedIntAtIndex:3];
	operandArray = [scriptCondition oo_arrayAtIndex:4];
	
	TraceLog(kOOLogTraceTestCondition, @"scriptTestCondition [%@]: \"%@\"", CurrentScriptDesc(), [scriptCondition oo_stringAtIndex:1]);
	
	// Transform mission/local var ops into string ops.
	if (opType == OP_MISSION_VAR)
	{
		sMissionStringValue = [mission_variables objectForKey:selectorString];
		selector = @selector(mission_string);
		opType = OP_STRING;
	}
	else if (opType == OP_LOCAL_VAR)
	{
		sMissionStringValue = [[self localVariablesForMission:sCurrentMissionKey] objectForKey:selectorString];
		selector = @selector(mission_string);
		opType = OP_STRING;
	}
	else
	{
		selector = NSSelectorFromString(selectorString);
	}
	
	expandedRHS = [self expandScriptRightHandSide:operandArray];
	
	if (opType == OP_STRING)
	{
		lhsString = [self performSelector:selector];
		
		TraceLog(kOOLogTraceTestConditionValues, @"..... comparing %@ (from %@) to \"%@\" with operator %@",
				 lhsString ? (NSString *)[NSString stringWithFormat:@"\"%@\"", lhsString] : (NSString *)@"nil",
				 selectorString,
				 expandedRHS ? expandedRHS: (NSString *)(comparator == COMPARISON_UNDEFINED ? @"undefined" : @"nil"),
				OOComparisonTypeToString(comparator));
		
	#define DOUBLEVAL(x) ((x != nil) ? [x doubleValue] : 0.0)
		
		switch (comparator)
		{
			case COMPARISON_UNDEFINED:
				TRACE_AND_RETURN(lhsString == nil);
				
			case COMPARISON_EQUAL:
				TRACE_AND_RETURN([lhsString isEqualToString:expandedRHS]);
				
			case COMPARISON_NOTEQUAL:
				TRACE_AND_RETURN(![lhsString isEqualToString:expandedRHS]);
				
			case COMPARISON_LESSTHAN:
				TRACE_AND_RETURN(DOUBLEVAL(lhsString) < DOUBLEVAL(expandedRHS));
				
			case COMPARISON_GREATERTHAN:
				TRACE_AND_RETURN(DOUBLEVAL(lhsString) > DOUBLEVAL(expandedRHS));
				
			case COMPARISON_ONEOF:
				{
					rhsComponents = [expandedRHS componentsSeparatedByString:@","];
					count = [rhsComponents count];
					
					TraceLog(kOOLogTraceTestConditionOneOf, @"performing a ONEOF comparison with %u elements: is %@ ONEOF %@ ?", count, lhsString, expandedRHS);
					
					whitespace = [NSCharacterSet whitespaceCharacterSet];
					lhsString = [lhsString stringByTrimmingCharactersInSet:whitespace];
					
					for (i = 0; i < count; i++)
					{
						rhsItem = [[rhsComponents objectAtIndex:i] stringByTrimmingCharactersInSet:whitespace];
						if ([lhsString isEqualToString:rhsItem])
						{
							TraceLog(kOOLogTraceTestConditionOneOf, @"found a match (\"%@\") in ONEOF!", rhsItem);
							TRACE_AND_RETURN(YES);
						}
					}
				}
				TRACE_AND_RETURN(NO);
		}
	}
	else if (opType == OP_NUMBER)
	{
		lhsValue = [[self performSelector:selector] doubleValue];
		
		TraceLog(kOOLogTraceTestConditionValues, @"..... comparing %g (from %@) to \"%@\" with operator %@",
				 lhsValue,
				 selectorString,
				 expandedRHS ? expandedRHS : (NSString *)@"nil",
				 OOComparisonTypeToString(comparator));
		
		if (comparator == COMPARISON_ONEOF)
		{
			rhsComponents = [expandedRHS componentsSeparatedByString:@","];
			count = [rhsComponents count];
			
			TraceLog(kOOLogTraceTestConditionOneOf, @"performing a ONEOF comparison with %u elements: is %@ ONEOF %@ ?", count, lhsString, expandedRHS);
			
			for (i = 0; i < count; i++)
			{
				rhsItem = [rhsComponents objectAtIndex:i];
				rhsValue = [rhsItem doubleValue];
				
				if (lhsValue == rhsValue)
				{
					TraceLog(kOOLogTraceTestConditionOneOf, @"found a match (%@) in ONEOF!", rhsItem);
					TRACE_AND_RETURN(YES);
				}
			}
			
			TraceLog(kOOLogTraceTestConditionOneOf, @"No match in ONEOF");
			TRACE_AND_RETURN(NO);
		}
		else
		{
			rhsValue = [expandedRHS doubleValue];
			
			switch (comparator)
			{
				case COMPARISON_EQUAL:
					TRACE_AND_RETURN(lhsValue == rhsValue);
					
				case COMPARISON_NOTEQUAL:
					TRACE_AND_RETURN(lhsValue != rhsValue);
					
				case COMPARISON_LESSTHAN:
					TRACE_AND_RETURN(lhsValue < rhsValue);
					
				case COMPARISON_GREATERTHAN:
					TRACE_AND_RETURN(lhsValue > rhsValue);
					
				case COMPARISON_UNDEFINED:
				case COMPARISON_ONEOF:
					// "Can't happen" - undefined should have been caught by the sanitizer, oneof is handled above.
					OOLog(@"script.error.unexpectedOperator", @"***** SCRIPT ERROR: in %@, operator %@ is not valid for numbers, evaluating to false.", CurrentScriptDesc(), OOComparisonTypeToString(comparator));
					TRACE_AND_RETURN(NO);
			}
		}
	}
	else if (opType == OP_BOOL)
	{
		lhsFlag = [[self performSelector:selector] isEqual:@"YES"];
		rhsFlag = [expandedRHS isEqual:@"YES"];
		
		switch (comparator)
		{
			case COMPARISON_EQUAL:
				TRACE_AND_RETURN(lhsFlag == rhsFlag);
				
			case COMPARISON_NOTEQUAL:
				TRACE_AND_RETURN(lhsFlag != rhsFlag);
				
			case COMPARISON_LESSTHAN:
			case COMPARISON_GREATERTHAN:
			case COMPARISON_UNDEFINED:
			case COMPARISON_ONEOF:
				// "Can't happen" - should have been caught by the sanitizer.
				OOLog(@"script.error.unexpectedOperator", @"***** SCRIPT ERROR: in %@, operator %@ is not valid for booleans, evaluating to false.", CurrentScriptDesc(), OOComparisonTypeToString(comparator));
				TRACE_AND_RETURN(NO);
		}
	}
	
	// What are we doing here?
	OOLog(@"script.error.fallthrough", @"***** SCRIPT ERROR: in %@, unhandled condition '%@' (%@). This is an internal error, please report it.", CurrentScriptDesc(), [scriptCondition objectAtIndex:1], scriptCondition);
	return NO;
}


- (NSString *) expandScriptRightHandSide:(NSArray *)rhsComponents
{
	NSMutableArray			*result = nil;
	NSEnumerator			*componentEnum = nil;
	NSArray					*component = nil;
	NSString				*value = nil;
	
	result = [NSMutableArray arrayWithCapacity:[rhsComponents count]];
	
	for (componentEnum = [rhsComponents objectEnumerator]; (component = [componentEnum nextObject]); )
	{
		/*	Each component is a two-element array. The second element is a
			string. The first element is a boolean indicating whether the
			string is a selector (true) or a literal (false).
			
			All valid selectors return a string or an NSNumber; in either
			case, -description gives us a useful value to substitute into
			the expanded string.
		*/
		
		value = [component oo_stringAtIndex:1];
		
		if ([[component objectAtIndex:0] boolValue])
		{
			value = [[self performSelector:NSSelectorFromString(value)] description];
			if (value == nil)  value = @"(null)";	// for backwards compatibility
		}
		
		[result addObject:value];
	}
	
	return [result componentsJoinedByString:@" "];
}


- (NSDictionary *) missionVariables
{
	return mission_variables;
}


- (NSString *)missionVariableForKey:(NSString *)key
{
	NSString *result = nil;
	if (key != nil)  result = [mission_variables objectForKey:key];
	return result;
}


- (void)setMissionVariable:(NSString *)value forKey:(NSString *)key
{
	if (key != nil)
	{
		if (value != nil)  [mission_variables setObject:value forKey:key];
		else [mission_variables removeObjectForKey:key];
	}
}


- (NSMutableDictionary *)localVariablesForMission:(NSString *)missionKey
{
	NSMutableDictionary		*result = nil;
	
	if (missionKey == nil)  return nil;
	
	result = [localVariables objectForKey:missionKey];
	if (result == nil)
	{
		result = [NSMutableDictionary dictionary];
		[localVariables setObject:result forKey:missionKey];
	}
	
	return result;
}


- (NSString *)localVariableForKey:(NSString *)variableName andMission:(NSString *)missionKey
{
	return [[localVariables oo_dictionaryForKey:missionKey] objectForKey:variableName];
}


- (void)setLocalVariable:(NSString *)value forKey:(NSString *)variableName andMission:(NSString *)missionKey
{
	NSMutableDictionary		*locals = nil;
	
	if (variableName != nil && missionKey != nil)
	{
		locals = [self localVariablesForMission:missionKey];
		if (value != nil)
		{
			[locals setObject:value forKey:variableName];
		}
		else
		{
			[locals removeObjectForKey:variableName];
		}
	}
}


- (NSArray *) missionsList
{
	NSEnumerator			*scriptEnum = nil;
	NSString				*scriptName = nil;
	NSString				*vars = nil;
	NSMutableArray			*result = nil;
	
	result = [NSMutableArray array];
	
	for (scriptEnum = [worldScripts keyEnumerator]; (scriptName = [scriptEnum nextObject]); )
	{
		vars = [mission_variables objectForKey:scriptName];
		
		if (vars != nil)
		{
			[result addObject:[NSString stringWithFormat:@"\t%@", vars]];
		}
	}
	return result;
}


- (NSString*) replaceVariablesInString:(NSString*) args
{
	NSMutableDictionary	*locals = [self localVariablesForMission:sCurrentMissionKey];
	NSMutableString		*resultString = [NSMutableString stringWithString: args];
	NSString			*valueString;
	unsigned			i;
	NSMutableArray		*tokens = ScanTokensFromString(args);
	
	for (i = 0; i < [tokens  count]; i++)
	{
		valueString = [tokens objectAtIndex:i];
		
		if ([mission_variables objectForKey:valueString])
		{
			[resultString replaceOccurrencesOfString:valueString withString:[mission_variables objectForKey:valueString] options:NSLiteralSearch range:NSMakeRange(0, [resultString length])];
		}
		else if ([locals objectForKey:valueString])
		{
			[resultString replaceOccurrencesOfString:valueString withString:[locals objectForKey:valueString] options:NSLiteralSearch range:NSMakeRange(0, [resultString length])];
		}
		else if (([valueString hasSuffix:@"_number"])||([valueString hasSuffix:@"_bool"])||([valueString hasSuffix:@"_string"]))
		{
			SEL valueselector = NSSelectorFromString(valueString);
			if ([self respondsToSelector:valueselector])
			{
				[resultString replaceOccurrencesOfString:valueString withString:[NSString stringWithFormat:@"%@", [self performSelector:valueselector]] options:NSLiteralSearch range:NSMakeRange(0, [resultString length])];
			}
		}
		else if ([valueString hasPrefix:@"["]&&[valueString hasSuffix:@"]"])
		{
			NSString* replaceString = ExpandDescriptionForCurrentSystem(valueString);
			[resultString replaceOccurrencesOfString:valueString withString:replaceString options:NSLiteralSearch range:NSMakeRange(0, [resultString length])];
		}
	}
	
	OOLog(kOOLogDebugReplaceVariablesInString, @"EXPANSION: \"%@\" becomes \"%@\"", args, resultString);
	
	return [NSString stringWithString: resultString];
}

/*-----------------------------------------------------*/


- (void) setMissionDescription:(NSString *)textKey
{
	NSString		*text = [[UNIVERSE missiontext] oo_stringForKey:textKey];
	if (!text)
	{
		OOLog(kOOLogScriptMissionDescNoText, @"***** SCRIPT ERROR: in %@, no missiontext set for key '%@' [UNIVERSE missiontext] is:\n%@ ", CurrentScriptDesc(), textKey, [UNIVERSE missiontext]);
		return;
	}
	if (!sCurrentMissionKey)
	{
		OOLog(kOOLogScriptMissionDescNoKey, @"***** SCRIPT ERROR: in %@, sCurrentMissionKey not set", CurrentScriptDesc());
		return;
	}
	text = ExpandDescriptionForCurrentSystem(text);
	text = [self replaceVariablesInString: text];

	[mission_variables setObject:text forKey:sCurrentMissionKey];
}


- (void) clearMissionDescription
{
	if (!sCurrentMissionKey)
	{
		OOLog(kOOLogScriptMissionDescNoText, @"***** SCRIPT ERROR: in %@, sCurrentMissionKey not set", CurrentScriptDesc());
		return;
	}
	if (![mission_variables objectForKey:sCurrentMissionKey])
		return;
	[mission_variables removeObjectForKey:sCurrentMissionKey];
}


- (void) setMissionDescription:(NSString *)textKey forMission:(NSString *)key
{
	NSString *old_sCurrentMissionKey = sCurrentMissionKey;
	sCurrentMissionKey = key;
	[self setMissionDescription:textKey];
	sCurrentMissionKey = old_sCurrentMissionKey;
}


- (void) clearMissionDescriptionForMission:(NSString *)key
{
	NSString *old_sCurrentMissionKey = sCurrentMissionKey;
	sCurrentMissionKey = key;
	[self clearMissionDescription];
	sCurrentMissionKey = old_sCurrentMissionKey;
}


- (NSString *) mission_string
{
	return sMissionStringValue;
}


- (NSString *) status_string
{
	return EntityStatusToString([self status]);
}


- (NSString *) gui_screen_string
{
	return GUIScreenIDToString(gui_screen);
}


- (NSNumber *) galaxy_number
{
	return [NSNumber numberWithInt:[self currentGalaxyID]];
}


- (NSNumber *) planet_number
{
	return [NSNumber numberWithInt:[self currentSystemID]];
}


- (NSNumber *) score_number
{
	return [NSNumber numberWithUnsignedInt:[self score]];
}


- (NSNumber *) credits_number
{
	return [NSNumber numberWithDouble:[self creditBalance]];
}


- (NSNumber *) scriptTimer_number
{
	return [NSNumber numberWithDouble:[self scriptTimer]];
}


static int shipsFound;
- (NSNumber *) shipsFound_number
{
	return [NSNumber numberWithInt:shipsFound];
}


- (NSNumber *) commanderLegalStatus_number
{
	return [NSNumber numberWithInt:[self legalStatus]];
}


- (void) setLegalStatus:(NSString *)valueString
{
	legalStatus = [valueString intValue];
}


- (NSString *) commanderLegalStatus_string
{
	return LegalStatusToString(legalStatus);
}


static int scriptRandomSeed = -1;	// ensure proper random function
- (NSNumber *) d100_number
{
	if (scriptRandomSeed == -1)	scriptRandomSeed = floor(1301 * ship_clock);	// stop predictable sequences
	ranrot_srand(scriptRandomSeed);
	scriptRandomSeed = ranrot_rand();
	int d100 = ranrot_rand() % 100;
	return [NSNumber numberWithInt:d100];
}


- (NSNumber *) pseudoFixedD100_number
{
	return [NSNumber numberWithInt:[self systemPseudoRandom100]];
}


- (NSNumber *) d256_number
{
	if (scriptRandomSeed == -1)	scriptRandomSeed = floor(1301 * ship_clock);	// stop predictable sequences
	ranrot_srand(scriptRandomSeed);
	scriptRandomSeed = ranrot_rand();
	int d256 = ranrot_rand() % 256;
	return [NSNumber numberWithInt:d256];
}


- (NSNumber *) pseudoFixedD256_number
{
	return [NSNumber numberWithInt:[self systemPseudoRandom256]];
}


- (NSNumber *) clock_number				// returns the game time in seconds
{
	return [NSNumber numberWithDouble:ship_clock];
}


- (NSNumber *) clock_secs_number		// returns the game time in seconds
{
	return [NSNumber numberWithUnsignedLongLong:ship_clock];
}


- (NSNumber *) clock_mins_number		// returns the game time in minutes
{
	return [NSNumber numberWithUnsignedLongLong:ship_clock / 60.0];
}


- (NSNumber *) clock_hours_number		// returns the game time in hours
{
	return [NSNumber numberWithUnsignedLongLong:ship_clock / 3600.0];
}


- (NSNumber *) clock_days_number		// returns the game time in days
{
	return [NSNumber numberWithUnsignedLongLong:ship_clock / 86400.0];
}


- (NSNumber *) fuelLevel_number			// returns the fuel level in LY
{
	return [NSNumber numberWithFloat:floor(0.1 * fuel)];
}


- (NSString *) dockedAtMainStation_bool
{
	if ([self dockedAtMainStation])  return @"YES";
	else  return @"NO";
}


- (NSString *) foundEquipment_bool
{
	return (found_equipment)? @"YES" : @"NO";
}


- (NSString *) sunWillGoNova_bool		// returns whether the sun is going to go nova
{
	return ([[UNIVERSE sun] willGoNova])? @"YES" : @"NO";
}


- (NSString *) sunGoneNova_bool		// returns whether the sun has gone nova
{
	return ([[UNIVERSE sun] goneNova])? @"YES" : @"NO";
}


- (NSString *) missionChoice_string		// returns nil or the key for the chosen option
{
	return missionChoice;
}


- (NSNumber *) dockedTechLevel_number
{
	if (!dockedStation) 
	{
		return [self systemTechLevel_number];
	}
	return [NSNumber numberWithInt:[dockedStation equivalentTechLevel]];
}

- (NSString *) dockedStationName_string	// returns 'NONE' if the player isn't docked, [station name] if it is, 'UNKNOWN' otherwise (?)
{
	NSString			*result = nil;
	if ([self status] != STATUS_DOCKED)  return @"NONE";
	
	result = [self dockedStationName];
	if (result == nil)  result = @"UNKNOWN";
	return result;
}


- (NSString *) systemGovernment_string
{
	int government = [[self systemGovernment_number] intValue]; // 0 .. 7 (0 anarchic .. 7 most stable)
	NSString *result = GovernmentToString(government);
	if (result == nil) result = @"UNKNOWN";
	
	return result;
}


- (NSNumber *) systemGovernment_number
{
	NSDictionary *systeminfo = [UNIVERSE generateSystemData:system_seed];
	return [systeminfo objectForKey:KEY_GOVERNMENT];
}


- (NSString *) systemEconomy_string
{
	int economy = [[self systemEconomy_number] intValue]; // 0 .. 7 (0 rich industrial .. 7 poor agricultural)
	NSString *result = EconomyToString(economy);
	if (result == nil) result = @"UNKNOWN";
	
	return result;
}


- (NSNumber *) systemEconomy_number
{
	NSDictionary *systeminfo = [UNIVERSE generateSystemData:system_seed];
	return [systeminfo objectForKey:KEY_ECONOMY];
}


- (NSNumber *) systemTechLevel_number
{
	NSDictionary *systeminfo = [UNIVERSE generateSystemData:system_seed];
	return [systeminfo objectForKey:KEY_TECHLEVEL];
}


- (NSNumber *) systemPopulation_number
{
	NSDictionary *systeminfo = [UNIVERSE generateSystemData:system_seed];
	return [systeminfo objectForKey:KEY_POPULATION];
}


- (NSNumber *) systemProductivity_number
{
	NSDictionary *systeminfo = [UNIVERSE generateSystemData:system_seed];
	return [systeminfo objectForKey:KEY_PRODUCTIVITY];
}


- (NSString *) commanderName_string
{
	return [self playerName];
}


- (NSString *) commanderRank_string
{
	return KillCountToRatingString([self score]);
}


- (NSString *) commanderShip_string
{
	return [self name];
}


- (NSString *) commanderShipDisplayName_string
{
	return [self displayName];
}

/*-----------------------------------------------------*/

- (void) commsMessage:(NSString *)valueString
{	
	Random_Seed very_random_seed;
	very_random_seed.a = rand() & 255;
	very_random_seed.b = rand() & 255;
	very_random_seed.c = rand() & 255;
	very_random_seed.d = rand() & 255;
	very_random_seed.e = rand() & 255;
	very_random_seed.f = rand() & 255;
	seed_RNG_only_for_planet_description(very_random_seed);
	NSString* expandedMessage = ExpandDescriptionForCurrentSystem(valueString);
	expandedMessage = [self replaceVariablesInString: expandedMessage];

	[UNIVERSE addCommsMessage:expandedMessage forCount:4.5];
}


// Enabled on 02-May-2008 - Nikos
// This method does the same as -commsMessage, (which in fact calls), the difference being that scripts can use this
// method to have unpiloted ship entities sending comms messages.
- (void) commsMessageByUnpiloted:(NSString *)valueString
{
	[self commsMessage:valueString];
}


- (void) consoleMessage3s:(NSString *)valueString
{
	Random_Seed very_random_seed;
	very_random_seed.a = rand() & 255;
	very_random_seed.b = rand() & 255;
	very_random_seed.c = rand() & 255;
	very_random_seed.d = rand() & 255;
	very_random_seed.e = rand() & 255;
	very_random_seed.f = rand() & 255;
	seed_RNG_only_for_planet_description(very_random_seed);
	NSString* expandedMessage = ExpandDescriptionForCurrentSystem(valueString);
	expandedMessage = [self replaceVariablesInString: expandedMessage];

	[UNIVERSE addMessage: expandedMessage forCount: 3];
}


- (void) consoleMessage6s:(NSString *)valueString
{
	Random_Seed very_random_seed;
	very_random_seed.a = rand() & 255;
	very_random_seed.b = rand() & 255;
	very_random_seed.c = rand() & 255;
	very_random_seed.d = rand() & 255;
	very_random_seed.e = rand() & 255;
	very_random_seed.f = rand() & 255;
	seed_RNG_only_for_planet_description(very_random_seed);
	NSString* expandedMessage = ExpandDescriptionForCurrentSystem(valueString);
	expandedMessage = [self replaceVariablesInString: expandedMessage];

	[UNIVERSE addMessage: expandedMessage forCount: 6];
}


- (void) awardCredits:(NSString *)valueString
{
	if (scriptTarget != self)  return;
	
	int award = 10 * [valueString intValue];
	if (award < 0 && credits < (unsigned)-award)  credits = 0;
	else  credits += award;
}


- (void) awardShipKills:(NSString *)valueString
{
	if (scriptTarget != self)  return;
	
	int value = [valueString intValue];
	if (0 < value)  ship_kills += value;
}


- (void) awardEquipment:(NSString *)equipString  //eg. EQ_NAVAL_ENERGY_UNIT
{
	if (scriptTarget != self)  return;
	
	if ([equipString isEqual:@"EQ_FUEL"])
	{
		[self setFuel:[self fuelCapacity]];
		return;
	}
	
	if ([equipString hasSuffix:@"MISSILE"]||[equipString hasSuffix:@"MINE"])
	{
		[self mountMissile:[[UNIVERSE newShipWithRole:equipString] autorelease]];
		return;
	}
	if([equipString hasPrefix:@"EQ_WEAPON"] && ![equipString hasSuffix:@"_DAMAGED"])
	{
		OOLog(kOOLogSyntaxAwardEquipment, @"***** SCRIPT ERROR: in %@, CANNOT award undamaged weapon:'%@'. Damaged weapons can be awarded instead.", CurrentScriptDesc(), equipString);
		return;
	}
	if ([equipString hasSuffix:@"_DAMAGED"] && [self hasEquipmentItem:[equipString substringToIndex:[equipString length] - [@"_DAMAGED" length]]])
	{
		OOLog(kOOLogSyntaxAwardEquipment, @"***** SCRIPT ERROR: in %@, CANNOT award damaged equipment:'%@'. Undamaged version already equipped.", CurrentScriptDesc(), equipString);
	}
	else if (![self hasEquipmentItem:equipString])
	{
		[self addEquipmentItem:equipString];
	}

}


- (void) removeEquipment:(NSString *)equipKey  //eg. EQ_NAVAL_ENERGY_UNIT
{

	if (scriptTarget != self)  return;

	if ([equipKey isEqual:@"EQ_FUEL"])
	{
		fuel = 0;
		return;
	}

	if ([self hasEquipmentItem:equipKey] || [self hasEquipmentItem:[equipKey stringByAppendingString:@"_DAMAGED"]])
	{
		[self removeEquipmentItem:equipKey];
	}

}


- (void) setPlanetinfo:(NSString *)key_valueString	// uses key=value format
{
	NSArray *	tokens = [key_valueString componentsSeparatedByString:@"="];
	NSString*   keyString = nil;
	NSString*	valueString = nil;

	if ([tokens count] != 2)
	{
		OOLog(kOOLogSyntaxSetPlanetInfo, @"***** SCRIPT ERROR: in %@, CANNOT setPlanetinfo: '%@' (bad parameter count)", CurrentScriptDesc(), key_valueString);
		return;
	}
	
	keyString = [[tokens objectAtIndex:0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
	valueString = [[tokens objectAtIndex:1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
	
	[UNIVERSE setSystemDataKey:keyString value:valueString];

}


- (void) setSpecificPlanetInfo:(NSString *)key_valueString  // uses galaxy#=planet#=key=value
{
	NSArray *	tokens = [key_valueString componentsSeparatedByString:@"="];
	NSString*   keyString = nil;
	NSString*	valueString = nil;
	int gnum, pnum;

	if ([tokens count] != 4)
	{
		OOLog(kOOLogSyntaxSetPlanetInfo, @"***** SCRIPT ERROR: in %@, CANNOT setSpecificPlanetInfo: '%@' (bad parameter count)", CurrentScriptDesc(), key_valueString);
		return;
	}

	gnum = [tokens oo_intAtIndex:0];
	pnum = [tokens oo_intAtIndex:1];
	keyString = [[tokens objectAtIndex:2] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
	valueString = [[tokens objectAtIndex:3] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];

	[UNIVERSE setSystemDataForGalaxy:gnum planet:pnum key:keyString value:valueString];
}


- (void) awardCargo:(NSString *)amount_typeString
{
	if (scriptTarget != self)  return;

	NSArray					*tokens = ScanTokensFromString(amount_typeString);
	NSString				*typeString = nil;
	OOCargoQuantityDelta	amount;
	OOCargoType				type;
	OOMassUnit				unit;
	NSArray					*commodityArray = nil;

	if ([tokens count] != 2)
	{
		OOLog(kOOLogSyntaxAwardCargo, @"***** SCRIPT ERROR: in %@, CANNOT awardCargo: '%@' (%@)", CurrentScriptDesc(), amount_typeString, @"bad parameter count");
		return;
	}
	
	typeString = [tokens objectAtIndex:1];
	type = [UNIVERSE commodityForName:typeString];
	if (type == CARGO_UNDEFINED)  type = [typeString intValue];
	
	commodityArray = [UNIVERSE commodityDataForType:type];
	
	if (commodityArray == nil)
	{
		OOLog(kOOLogSyntaxAwardCargo, @"***** SCRIPT ERROR: in %@, CANNOT awardCargo: '%@' (%@)", CurrentScriptDesc(), amount_typeString, @"unknown type");
		return;
	}
	
	amount = [tokens oo_intAtIndex:0];
	if (amount < 0)
	{
		OOLog(kOOLogSyntaxAwardCargo, @"***** SCRIPT ERROR: in %@, CANNOT awardCargo: '%@' (%@)", CurrentScriptDesc(), amount_typeString, @"negative quantity");
		return;
	}
	
	unit = [UNIVERSE unitsForCommodity:type];
	if (specialCargo && unit == UNITS_TONS)
	{
		OOLog(kOOLogSyntaxAwardCargo, @"***** SCRIPT ERROR: in %@, CANNOT awardCargo: '%@' (%@)", CurrentScriptDesc(), amount_typeString, @"cargo hold full with special cargo");
		return;
	}
	
	[self awardCargoType:type amount:amount];
}


- (void) removeAllCargo
{
	[self removeAllCargo:NO];
}

- (void) removeAllCargo:(BOOL)forceRemoval
{
	// misnamed function. it only removes  cargo measured in TONS, g & Kg items are not removed. --Kaks 20091004 
	OOCargoType				type;
	OOMassUnit				unit;
	
	if (scriptTarget != self)  return;
	
	if ([self status] != STATUS_DOCKED && !forceRemoval)
	{
		OOLog(kOOLogRemoveAllCargoNotDocked, @"***** SCRIPT ERROR: in %@, removeAllCargo: only works when docked.", CurrentScriptDesc());
		return;
	}
	
	if (forceRemoval)
	{
		OOLog(kOOLogNoteRemoveAllCargo, @"Forcing removeAllCargo:");
	}
	else
	{
		OOLog(kOOLogNoteRemoveAllCargo, @"Going to removeAllCargo:");
	}
	
	NSMutableArray *manifest = [NSMutableArray arrayWithArray:shipCommodityData];
	for (type = 0; type < (OOCargoType)[manifest count]; type++)
	{
		NSMutableArray *manifest_commodity = [NSMutableArray arrayWithArray:[manifest oo_arrayAtIndex:type]];
		// manifest contains entries for all 17 commodities, whether their quantity is 0 or more.
		unit = [UNIVERSE unitsForCommodity:type]; // will return tons for unknown types
		if (unit == UNITS_TONS)
		{
			[manifest_commodity replaceObjectAtIndex:MARKET_QUANTITY withObject:[NSNumber numberWithInt:0]];
			[manifest replaceObjectAtIndex:type withObject:[NSArray arrayWithArray:manifest_commodity]];
		}
	}

	if(forceRemoval && [self status] != STATUS_DOCKED)
	{
		int i;
		for (i = [cargo count]-1; i >=0; i--)
		{
			ShipEntity* canister = [cargo objectAtIndex:i];
			if (!canister) break;
			unit = [UNIVERSE unitsForCommodity:[canister commodityType]];
			if (unit == UNITS_TONS)
				[cargo removeObjectAtIndex:i];
		}
	}

	[shipCommodityData release];
	shipCommodityData = [manifest mutableCopy];
	
	[specialCargo release];
	specialCargo = nil;
}


- (void) useSpecialCargo:(NSString *)descriptionString;
{
	if (scriptTarget != self)  return;
	
	OOLog(kOOLogNoteUseSpecialCargo, @"Going to useSpecialCargo:'%@'", descriptionString);
	
	[self removeAllCargo:YES];
	specialCargo = [ExpandDescriptionForCurrentSystem(descriptionString) retain];
}


- (void) testForEquipment:(NSString *)equipString	//eg. EQ_NAVAL_ENERGY_UNIT
{
	found_equipment = [self hasEquipmentItem:equipString];
}


- (void) awardFuel:(NSString *)valueString	// add to fuel up to 7.0 LY
{
	int delta  = 10 * [valueString floatValue];
	OOFuelQuantity scriptTargetFuelBeforeAward = [scriptTarget fuel];

	if (delta < 0 && scriptTargetFuelBeforeAward < (unsigned)-delta)  [scriptTarget setFuel:0];
	else
	{
		[scriptTarget setFuel:(scriptTargetFuelBeforeAward + delta)];
	}
}


- (void) messageShipAIs:(NSString *)roles_message
{
	NSMutableArray*	tokens = ScanTokensFromString(roles_message);
	NSString*   roleString = nil;
	NSString*	messageString = nil;

	if ([tokens count] < 2)
	{
		OOLog(kOOLogSyntaxMessageShipAIs, @"***** SCRIPT ERROR: in %@, CANNOT messageShipAIs: '%@' (bad parameter count)", CurrentScriptDesc(), roles_message);
		return;
	}

	roleString = [tokens objectAtIndex:0];
	[tokens removeObjectAtIndex:0];
	messageString = [tokens componentsJoinedByString:@" "];

	[UNIVERSE sendShipsWithPrimaryRole:roleString messageToAI:messageString];
}


- (void) ejectItem:(NSString *)itemKey
{
	if (scriptTarget == nil)  scriptTarget = self;
	[scriptTarget ejectShipOfType:itemKey];
}


- (void) addShips:(NSString *)roles_number
{
	NSMutableArray*	tokens = ScanTokensFromString(roles_number);
	NSString*   roleString = nil;
	NSString*	numberString = nil;
	
	if ([tokens count] != 2)
	{
		OOLog(kOOLogSyntaxAddShips, @"***** SCRIPT ERROR: in %@, CANNOT addShips: '%@' (expected <role> <count>)", CurrentScriptDesc(), roles_number);
		return;
	}
	
	roleString = [tokens objectAtIndex:0];
	numberString = [tokens objectAtIndex:1];
	
	int number = [numberString intValue];
	if (number < 0)
	{
		OOLog(kOOLogSyntaxAddShips, @"***** SCRIPT ERROR: in %@, can't add %i ships -- that's less than zero, y'know..", CurrentScriptDesc(), number);
		return;
	}
	
	OOLog(kOOLogNoteAddShips, @"DEBUG: Going to add %d ships with role '%@'", number, roleString);
	
	while (number--)
		[UNIVERSE witchspaceShipWithPrimaryRole:roleString];
}


- (void) addSystemShips:(NSString *)roles_number_position
{
	NSMutableArray*	tokens = ScanTokensFromString(roles_number_position);
	NSString*   roleString = nil;
	NSString*	numberString = nil;
	NSString*	positionString = nil;

	if ([tokens count] != 3)
	{
		OOLog(kOOLogSyntaxAddShips, @"***** SCRIPT ERROR: in %@, CANNOT addSystemShips: '%@' (expected <role> <count> <position>)", CurrentScriptDesc(), roles_number_position);
		return;
	}

	roleString = [tokens objectAtIndex:0];
	numberString = [tokens objectAtIndex:1];
	positionString = [tokens objectAtIndex:2];

	int number = [numberString intValue];
	double posn = [positionString doubleValue];
	if (number < 0)
	{
		OOLog(kOOLogSyntaxAddShips, @"***** SCRIPT ERROR: in %@, can't add %i ships -- that's less than zero, y'know..", CurrentScriptDesc(), number);
		return;
	}

	OOLog(kOOLogNoteAddShips, @"DEBUG: Going to add %d ships with role '%@' at a point %.3f along route1", number, roleString, posn);

	while (number--)
		[UNIVERSE addShipWithRole:roleString nearRouteOneAt:posn];
}


- (void) addShipsAt:(NSString *)roles_number_system_x_y_z
{
	NSMutableArray*	tokens = ScanTokensFromString(roles_number_system_x_y_z);

	NSString*   roleString = nil;
	NSString*	numberString = nil;
	NSString*	systemString = nil;
	NSString*	xString = nil;
	NSString*	yString = nil;
	NSString*	zString = nil;

	if ([tokens count] != 6)
	{
		OOLog(kOOLogSyntaxAddShips, @"***** SCRIPT ERROR: in %@, CANNOT addShipsAt: '%@' (expected <role> <count> <coordinate-system> <x> <y> <z>)", CurrentScriptDesc(), roles_number_system_x_y_z);
		return;
	}

	roleString = [tokens objectAtIndex:0];
	numberString = [tokens objectAtIndex:1];
	systemString = [tokens objectAtIndex:2];
	xString = [tokens objectAtIndex:3];
	yString = [tokens objectAtIndex:4];
	zString = [tokens objectAtIndex:5];

	Vector posn = make_vector( [xString floatValue], [yString floatValue], [zString floatValue]);

	int number = [numberString intValue];
	if (number < 1)
	{
		OOLog(kOOLogSyntaxAddShips, @"----- WARNING in %@  Tried to add %i ships -- no ship added.", CurrentScriptDesc(), number);
		return;
	}

	OOLog(kOOLogNoteAddShips, @"DEBUG: Going to add %d ship(s) with role '%@' at point (%.3f, %.3f, %.3f) using system %@", number, roleString, posn.x, posn.y, posn.z, systemString);

	if (![UNIVERSE addShips: number withRole:roleString nearPosition: posn withCoordinateSystem: systemString])
	{
		OOLog(kOOLogScriptAddShipsFailed, @"***** SCRIPT ERROR: in %@, %@ could not add %u ships with role \"%@\"", CurrentScriptDesc(), @"addShipsAt:", number, roleString);
	}
}


- (void) addShipsAtPrecisely:(NSString *)roles_number_system_x_y_z
{
	NSMutableArray*	tokens = ScanTokensFromString(roles_number_system_x_y_z);

	NSString*   roleString = nil;
	NSString*	numberString = nil;
	NSString*	systemString = nil;
	NSString*	xString = nil;
	NSString*	yString = nil;
	NSString*	zString = nil;

	if ([tokens count] != 6)
	{
		OOLog(kOOLogSyntaxAddShips, @"***** SCRIPT ERROR: in %@,* CANNOT addShipsAtPrecisely: '%@' (expected <role> <count> <coordinate-system> <x> <y> <z>)", CurrentScriptDesc(), roles_number_system_x_y_z);
		return;
	}

	roleString = [tokens objectAtIndex:0];
	numberString = [tokens objectAtIndex:1];
	systemString = [tokens objectAtIndex:2];
	xString = [tokens objectAtIndex:3];
	yString = [tokens objectAtIndex:4];
	zString = [tokens objectAtIndex:5];

	Vector posn = make_vector( [xString floatValue], [yString floatValue], [zString floatValue]);

	int number = [numberString intValue];
	if (number < 1)
	{
		OOLog(kOOLogSyntaxAddShips, @"----- WARNING: in %@, Can't add %i ships -- no ship added.", CurrentScriptDesc(), number);
		return;
	}

	OOLog(kOOLogNoteAddShips, @"DEBUG: Going to add %d ship(s) with role '%@' precisely at point (%.3f, %.3f, %.3f) using system %@", number, roleString, posn.x, posn.y, posn.z, systemString);

	if (![UNIVERSE addShips: number withRole:roleString atPosition: posn withCoordinateSystem: systemString])
	{
		OOLog(kOOLogScriptAddShipsFailed, @"***** SCRIPT ERROR: in %@, %@ could not add %u ships with role '%@'", CurrentScriptDesc(), @"addShipsAtPrecisely:", number, roleString);
	}
}


- (void) addShipsWithinRadius:(NSString *)roles_number_system_x_y_z_r
{
	NSMutableArray*	tokens = ScanTokensFromString(roles_number_system_x_y_z_r);

	if ([tokens count] != 7)
	{
		OOLog(kOOLogSyntaxAddShips, @"***** SCRIPT ERROR: in %@, CANNOT 'addShipsWithinRadius: %@' (expected <role> <count> <coordinate-system> <x> <y> <z> <radius>))", CurrentScriptDesc(), roles_number_system_x_y_z_r);
		return;
	}

	NSString* roleString = [tokens objectAtIndex:0];
	int number = [[tokens objectAtIndex:1] intValue];
	NSString* systemString = [tokens objectAtIndex:2];
	GLfloat x = [[tokens objectAtIndex:3] floatValue];
	GLfloat y = [[tokens objectAtIndex:4] floatValue];
	GLfloat z = [[tokens objectAtIndex:5] floatValue];
	GLfloat r = [[tokens objectAtIndex:6] floatValue];
	Vector posn = make_vector( x, y, z);

	if (number < 1)
	{
		OOLog(kOOLogSyntaxAddShips, @"----- WARNING: in %@, can't add %i ships -- no ship added.", CurrentScriptDesc(), number);
		return;
	}

	OOLog(kOOLogNoteAddShips, @"DEBUG: Going to add %d ship(s) with role '%@' within %.2f radius about point (%.3f, %.3f, %.3f) using system %@", number, roleString, r, x, y, z, systemString);

	if (![UNIVERSE addShips:number withRole: roleString nearPosition: posn withCoordinateSystem: systemString withinRadius: r])
	{
		OOLog(kOOLogScriptAddShipsFailed, @"***** SCRIPT ERROR :in %@, %@ could not add %u ships with role \"%@\"", CurrentScriptDesc(), @"addShipsWithinRadius:", number, roleString);
	}
}


- (void) spawnShip:(NSString *)ship_key
{
	if ([UNIVERSE spawnShip:ship_key])
	{
		OOLog(kOOLogNoteAddShips, @"DEBUG: Spawned ship with shipdata key '%@'.", ship_key);
	}
	else
	{
		OOLog(kOOLogScriptAddShipsFailed, @"***** SCRIPT ERROR: in %@, could not spawn ship with shipdata key '%@'.", CurrentScriptDesc(), ship_key);
	}
}


- (void) set:(NSString *)missionvariable_value
{
	NSMutableArray		*tokens = ScanTokensFromString(missionvariable_value);
	NSString			*missionVariableString = nil;
	NSString			*valueString = nil;
	BOOL				hasMissionPrefix, hasLocalPrefix;

	if ([tokens count] < 2)
	{
		OOLog(kOOLogSyntaxSet, @"***** SCRIPT ERROR: in %@, CANNOT SET '%@' (expected mission_variable or local_variable followed by value expression)", CurrentScriptDesc(), missionvariable_value);
		return;
	}

	missionVariableString = [tokens objectAtIndex:0];
	[tokens removeObjectAtIndex:0];
	valueString = [tokens componentsJoinedByString:@" "];

	hasMissionPrefix = [missionVariableString hasPrefix:@"mission_"];
	hasLocalPrefix = [missionVariableString hasPrefix:@"local_"];

	if (!hasMissionPrefix && !hasLocalPrefix)
	{
		OOLog(kOOLogSyntaxSet, @"***** SCRIPT ERROR: in %@, IDENTIFIER '%@' DOES NOT BEGIN WITH 'mission_' or 'local_'", CurrentScriptDesc(), missionVariableString);
		return;
	}

	OOLog(kOOLogNoteSet, @"DEBUG: script %@ is set to %@", missionVariableString, valueString);
	
	if (hasMissionPrefix)
	{
		[self setMissionVariable:valueString forKey:missionVariableString];
	}
	else
	{
		[self setLocalVariable:valueString forKey:missionVariableString andMission:sCurrentMissionKey];
	}
}


- (void) reset:(NSString *)missionvariable
{
	NSString*   missionVariableString = [missionvariable stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
	BOOL hasMissionPrefix, hasLocalPrefix;

	hasMissionPrefix = [missionVariableString hasPrefix:@"mission_"];
	hasLocalPrefix = [missionVariableString hasPrefix:@"local_"];

	if (hasMissionPrefix)
	{
		[self setMissionVariable:nil forKey:missionVariableString];
	}
	else if (hasLocalPrefix)
	{
		[self setLocalVariable:nil forKey:missionVariableString andMission:sCurrentMissionKey];
	}
	else
	{
		OOLog(kOOLogSyntaxReset, @"***** SCRIPT ERROR: in %@, IDENTIFIER '%@' DOES NOT BEGIN WITH 'mission_' or 'local_'", CurrentScriptDesc(), missionVariableString);
	}
}


- (void) increment:(NSString *)missionVariableString
{
	BOOL hasMissionPrefix, hasLocalPrefix;
	int value = 0;

	hasMissionPrefix = [missionVariableString hasPrefix:@"mission_"];
	hasLocalPrefix = [missionVariableString hasPrefix:@"local_"];

	if (hasMissionPrefix)
	{
		value = [[self missionVariableForKey:missionVariableString] intValue];
		value++;
		[self setMissionVariable:[NSString stringWithFormat:@"%d", value] forKey:missionVariableString];
	}
	else if (hasLocalPrefix)
	{
		value = [[self localVariableForKey:missionVariableString andMission:sCurrentMissionKey] intValue];
		value++;
		[self setLocalVariable:[NSString stringWithFormat:@"%d", value] forKey:missionVariableString andMission:sCurrentMissionKey];
	}
	else
	{
		OOLog(kOOLogSyntaxIncrement, @"***** SCRIPT ERROR: in %@, IDENTIFIER '%@' DOES NOT BEGIN WITH 'mission_' or 'local_'", CurrentScriptDesc(), missionVariableString);
	}
}


- (void) decrement:(NSString *)missionVariableString
{
	BOOL hasMissionPrefix, hasLocalPrefix;
	int value = 0;

	hasMissionPrefix = [missionVariableString hasPrefix:@"mission_"];
	hasLocalPrefix = [missionVariableString hasPrefix:@"local_"];
	
	if (hasMissionPrefix)
	{
		value = [[self missionVariableForKey:missionVariableString] intValue];
		value--;
		[self setMissionVariable:[NSString stringWithFormat:@"%d", value] forKey:missionVariableString];
	}
	else if (hasLocalPrefix)
	{
		value = [[self localVariableForKey:missionVariableString andMission:sCurrentMissionKey] intValue];
		value--;
		[self setLocalVariable:[NSString stringWithFormat:@"%d", value] forKey:missionVariableString andMission:sCurrentMissionKey];
	}
	else
	{
		OOLog(kOOLogSyntaxDecrement, @"***** SCRIPT ERROR: in %@, IDENTIFIER '%@' DOES NOT BEGIN WITH 'mission_' or 'local_'", CurrentScriptDesc(), missionVariableString);
	}
}


- (void) add:(NSString *)missionVariableString_value
{
	NSString*   missionVariableString = nil;
	NSString*   valueString;
	double	value;
	NSMutableArray*	tokens = ScanTokensFromString(missionVariableString_value);
	BOOL hasMissionPrefix, hasLocalPrefix;

	if ([tokens count] < 2)
	{
		OOLog(kOOLogSyntaxAdd, @"***** SCRIPT ERROR: in %@, CANNOT ADD: '%@'", CurrentScriptDesc(), missionVariableString_value);
		return;
	}

	missionVariableString = [tokens objectAtIndex:0];
	[tokens removeObjectAtIndex:0];
	valueString = [tokens componentsJoinedByString:@" "];

	hasMissionPrefix = [missionVariableString hasPrefix:@"mission_"];
	hasLocalPrefix = [missionVariableString hasPrefix:@"local_"];

	if (hasMissionPrefix)
	{
		value = [[self missionVariableForKey:missionVariableString] doubleValue];
		value += [valueString doubleValue];
		[self setMissionVariable:[NSString stringWithFormat:@"%f", value] forKey:missionVariableString];
	}
	else if (hasLocalPrefix)
	{
		value = [[self localVariableForKey:missionVariableString andMission:sCurrentMissionKey] doubleValue];
		value += [valueString doubleValue];
		[self setLocalVariable:[NSString stringWithFormat:@"%f", value] forKey:missionVariableString andMission:sCurrentMissionKey];
	}
	else
	{
		OOLog(kOOLogSyntaxAdd, @"***** SCRIPT ERROR: in %@, CANNOT ADD: '%@' -- IDENTIFIER '%@' DOES NOT BEGIN WITH 'mission_' or 'local_'", CurrentScriptDesc(), missionVariableString_value);
	}
}


- (void) subtract:(NSString *)missionVariableString_value
{
	NSString*   missionVariableString = nil;
	NSString*   valueString;
	double	value;
	NSMutableArray*	tokens = ScanTokensFromString(missionVariableString_value);
	BOOL hasMissionPrefix, hasLocalPrefix;

	if ([tokens count] < 2)
	{
		OOLog(kOOLogSyntaxSubtract, @"***** SCRIPT ERROR: in %@, CANNOT SUBTRACT: '%@'", CurrentScriptDesc(), missionVariableString_value);
		return;
	}

	missionVariableString = [tokens objectAtIndex:0];
	[tokens removeObjectAtIndex:0];
	valueString = [tokens componentsJoinedByString:@" "];

	hasMissionPrefix = [missionVariableString hasPrefix:@"mission_"];
	hasLocalPrefix = [missionVariableString hasPrefix:@"local_"];
	
	if (hasMissionPrefix)
	{
		value = [[self missionVariableForKey:missionVariableString] doubleValue];
		value -= [valueString doubleValue];
		[self setMissionVariable:[NSString stringWithFormat:@"%f", value] forKey:missionVariableString];
	}
	else if (hasLocalPrefix)
	{
		value = [[self localVariableForKey:missionVariableString andMission:sCurrentMissionKey] doubleValue];
		value -= [valueString doubleValue];
		[self setLocalVariable:[NSString stringWithFormat:@"%f", value] forKey:missionVariableString andMission:sCurrentMissionKey];
	}
	else
	{
		OOLog(kOOLogSyntaxSubtract, @"***** SCRIPT ERROR: in %@, CANNOT ADD: '%@' -- IDENTIFIER '%@' DOES NOT BEGIN WITH 'mission_' or 'local_'", CurrentScriptDesc(), missionVariableString_value);
	}
}


- (void) checkForShips:(NSString *)roleString
{
	shipsFound = [UNIVERSE countShipsWithPrimaryRole:roleString];
}


- (void) resetScriptTimer
{
	script_time = 0.0;
	script_time_check = SCRIPT_TIMER_INTERVAL;
	script_time_interval = SCRIPT_TIMER_INTERVAL;
}


- (void) addMissionText: (NSString *)textKey
{
	NSString			*text = nil;
	NSArray				*paras = nil;
	
	if ([textKey isEqual:lastTextKey])  return; // don't repeatedly add the same text
	[lastTextKey release];
	lastTextKey = [textKey copy];
	
	// Replace literal \n in strings with line breaks and perform expansions.
	text = [[UNIVERSE missiontext] oo_stringForKey:textKey];
	if (text == nil)  return;
	text = ExpandDescriptionForCurrentSystem(text);
	paras = [text componentsSeparatedByString:@"\\n"];
	text = [paras componentsJoinedByString:@"\n"];
	text = [self replaceVariablesInString:text];
	
	[self addLiteralMissionText:text];
}


- (void) addLiteralMissionText:(NSString *)text
{
	GuiDisplayGen		*gui = [UNIVERSE gui];
	NSArray				*paras = [text componentsSeparatedByString:@"\n"];
	unsigned			i, count;
	
	if (text != nil)
	{
		count = [paras count];
		for (i = 0; i < count; i++)
		{
			missionTextRow = [gui addLongText:[paras objectAtIndex:i] startingAtRow:missionTextRow align:GUI_ALIGN_LEFT];
		}
	}
}


- (void) setMissionChoices:(NSString *)choicesKey	// choicesKey is a key for a dictionary of
{													// choices/choice phrases in missiontext.plist and also..
	GuiDisplayGen* gui = [UNIVERSE gui];
	// TODO: MORE STUFF HERE
	// must find list of choices in missiontext.plist
	// add them to gui setting the key for each line to the key in the dict of choices
	// and the text of the line to the value in the dict of choices
	// and also set the selectable range
	// ++ change the mission screen's response to wait for a choice
	// and only if the selectable range is not present ask:
	// Press Space Commander...
	//
	NSDictionary *choices_dict = [[UNIVERSE missiontext] oo_dictionaryForKey:choicesKey];
	if ([choices_dict count] == 0)
	{
		return;
	}
	
	NSArray *choice_keys = [[choices_dict allKeys] sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
	
	[gui setText:@"" forRow:21];			// clears out the 'Press spacebar' message
	[gui setKey:@"" forRow:21];				// clears the key to enable pollDemoControls to check for a selection
	[gui setSelectableRange:NSMakeRange(0,0)];	// clears the selectable range
	
	int					choices_row = 22 - [choice_keys count];
	NSEnumerator		*choiceEnum = nil;
	NSString			*choiceKey = nil;
	NSString			*choiceText = nil;
	
	for (choiceEnum = [choice_keys objectEnumerator]; (choiceKey = [choiceEnum nextObject]); )
	{
		choiceText = [NSString stringWithFormat:@" %@ ",[choices_dict objectForKey:choiceKey]];
		choiceText = ExpandDescriptionForCurrentSystem(choiceText);
		choiceText = [self replaceVariablesInString:choiceText];
		[gui setText:choiceText forRow:choices_row align: GUI_ALIGN_CENTER];
		[gui setKey:choiceKey forRow:choices_row];
		[gui setColor:[OOColor yellowColor] forRow:choices_row];
		choices_row++;
	}
	
	[gui setSelectableRange:NSMakeRange(22 - [choice_keys count], [choice_keys count])];
	[gui setSelectedRow: 22 - [choice_keys count]];
	
	[self resetMissionChoice];
}


- (void) resetMissionChoice
{
	[self setMissionChoice:nil];
}


- (void) clearMissionScreen
{
	[self setMissionImage:nil];
	[self setMissionMusic:nil];
	[self showShipModel:nil];
}


- (void) addMissionDestination:(NSString *)destinations
{
	unsigned i, j;
	int pnum, dest;
	NSMutableArray*	tokens = ScanTokensFromString(destinations);
	BOOL addDestination;

	for (j = 0; j < [tokens count]; j++)
	{
		dest = [tokens oo_intAtIndex:j];
		if (dest < 0 || dest > 255)
			continue;

		addDestination = YES;
		for (i = 0; i < [missionDestinations count]; i++)
		{
			pnum = [missionDestinations oo_intAtIndex:i];
			if (pnum == dest)
			{
				addDestination = NO;
				break;
			}
		}

		if (addDestination == YES)
			[missionDestinations addObject:[NSNumber numberWithUnsignedInt:dest]];
	}
}


- (void) removeMissionDestination:(NSString *)destinations
{
	unsigned			i, j;
	int					pnum, dest;
	NSMutableArray		*tokens = ScanTokensFromString(destinations);
	BOOL				removeDestination;

	for (j = 0; j < [tokens count]; j++)
	{
		dest = [[tokens objectAtIndex:j] intValue];
		if (dest < 0 || dest > 255)  continue;
		
		removeDestination = NO;
		for (i = 0; i < [missionDestinations count]; i++)
		{
			pnum = [missionDestinations oo_intAtIndex:i];
			if (pnum == dest)
			{
				removeDestination = YES;
				break;
			}
		}
		
		if (removeDestination == YES)
		{
			[missionDestinations removeObjectAtIndex:i];
		}
	}
}


-(NSString *) getMissionShipModel
{
	return missionShipModel;
}


- (void) showShipModel:(NSString *)shipKey
{
	ShipEntity		*ship;

	if (!dockedStation)  return;
	missionShipModel = nil;
	[UNIVERSE removeDemoShips];	// get rid of any pre-existing models on display
	if ([shipKey isEqualToString:@"none"] || [shipKey length] == 0)  return;
	
	[[PlayerEntity sharedPlayer] setShowDemoShips: YES];
	Quaternion		q2 = { (GLfloat)0.707, (GLfloat)0.707, (GLfloat)0.0, (GLfloat)0.0};
	missionShipModel = [NSString stringWithString:shipKey];
	ship = [UNIVERSE newShipWithRole: shipKey];   // retain count = 1
	if (ship)
	{
		double cr = ship->collision_radius;
		OOLog(kOOLogNoteShowShipModel, @"::::: showShipModel:'%@' (%@) (%@)", shipKey, ship, [ship name]);
		[ship setOrientation: q2];
		[ship setPositionX:0.0f y:0.0f z:3.6f * cr];
		[ship setScanClass:CLASS_NO_DRAW];
		[ship setRoll:M_PI/5.0];
		[ship setPitch:M_PI/10.0];
		[[ship getAI] setStateMachine:@"nullAI.plist"];
		[ship setPendingEscortCount:0];
		[UNIVERSE addEntity:ship];
		[ship setStatus:STATUS_COCKPIT_DISPLAY];
		
		[ship release];
	}
}


- (void) setMissionMusic:(NSString *)value
{
	if ([value length] == 0 || [[value lowercaseString] isEqual:@"none"])
	{
		value = nil;
	}
	[[OOMusicController	sharedController] setMissionMusic:value];
}


- (NSString *) getMissionImage
{
	return missionBackgroundFile;
}


- (void) setMissionImage:(NSString *)value
{
	missionBackgroundFile = nil;
	[missionBackgroundTexture release];
	missionBackgroundTexture = nil;
	
	if ([value length] != 0 && ![[value lowercaseString] isEqual:@"none"])
 	{
		missionBackgroundFile = [NSString stringWithString: value];
		missionBackgroundTexture = [OOTexture textureWithName:value inFolder:@"Images"];
		[missionBackgroundTexture retain];
 	}
}


- (void) setFuelLeak:(NSString *)value
{	
	if (scriptTarget != self)
	{
		[scriptTarget setFuel:0];
		return;
	}
	
	fuel_leak_rate = [value doubleValue];
	if (fuel_leak_rate > 0)
	{
		[self playFuelLeak];
		[UNIVERSE addMessage:DESC(@"danger-fuel-leak") forCount:6];
		OOLog(kOOLogNoteFuelLeak, @"FUEL LEAK activated!");
	}
}


- (NSNumber *) fuelLeakRate_number
{
	return [NSNumber numberWithFloat:[self fuelLeakRate]];
}


- (void) setSunNovaIn:(NSString *)time_value
{
	double time_until_nova = [time_value doubleValue];
	[[UNIVERSE sun] setGoingNova:YES inTime: time_until_nova];
}


- (void) launchFromStation
{
	// ensure autosave is ready
	if ([UNIVERSE autoSave]) [UNIVERSE setAutoSaveNow:YES];
	[self leaveDock:dockedStation];
}


- (void) blowUpStation
{
	StationEntity		*mainStation = nil;
	
	mainStation = [UNIVERSE station];
	if (mainStation != nil)
	{
		[UNIVERSE unMagicMainStation];
		[mainStation takeEnergyDamage:500000000.0 from:nil becauseOf:nil];	// 500 million should do it!
	}
}


- (void) sendAllShipsAway
{
	if (!UNIVERSE)
		return;
	int			ent_count =		UNIVERSE->n_entities;
	Entity**	uni_entities =	UNIVERSE->sortedEntities;	// grab the public sorted list
	Entity*		my_entities[ent_count];
	int i;
	for (i = 0; i < ent_count; i++)
		my_entities[i] = [uni_entities[i] retain];		//	retained

	for (i = 1; i < ent_count; i++)
	{
		Entity* e1 = my_entities[i];
		// Nova mission fix: if a station jumps away, the large witchjump cloud they leave behind 
		// becomes a shortcut to another system. FIXME: Behemoths present a similar problem.
		if ([e1 isShip] && ! [e1 isStation])
		{
			ShipEntity* se1 = (ShipEntity*)e1;
			int e_class = [e1 scanClass];
			if ((e_class == CLASS_NEUTRAL)||(e_class == CLASS_POLICE)||(e_class == CLASS_MILITARY)||(e_class == CLASS_THARGOID))
			{
				AI*	se1AI = [se1 getAI];
				[se1 setFuel:MAX(PLAYER_MAX_FUEL, [se1 fuelCapacity])];
				[se1AI setStateMachine:@"exitingTraderAI.plist"];
				[se1AI setState:@"EXIT_SYSTEM"];
				// FIXME: I don't think the following line does anything meaningful. -- Ahruman
				// The following shoulf prevent all ships leaving at once (freezes oolite on slower machines)
				[se1AI reactToMessage:[NSString stringWithFormat:@"pauseAI: %d", 3 + (ranrot_rand() & 15)]];
				[se1 setPrimaryRole:@"none"];	// prevents new ship from appearing at witchpoint when this one leaves!
			}
		}
	}
	// ships need to be released after their AIs makes them jump away.
	//for (i = 0; i < ent_count; i++)
	//	[my_entities[i] release];		//	released
}


- (void) addPlanet: (NSString *)planetKey
{
	OOLog(kOOLogNoteAddPlanet, @"addPlanet: %@", planetKey);

	if (!UNIVERSE)
		return;
	NSDictionary* dict = [[UNIVERSE planetInfo] oo_dictionaryForKey:planetKey];
	if (!dict)
	{
		OOLog(@"script.error.addPlanet.keyNotFound", @"***** ERROR: could not find an entry in planetinfo.plist for '%@'", planetKey);
		return;
	}

	/*- add planet -*/
	OOLog(kOOLogDebugAddPlanet, @"DEBUG: initPlanetFromDictionary: %@", dict);
	PlanetEntity*	planet = [[[PlanetEntity alloc] initPlanetFromDictionary:dict] autorelease];
	[planet setStatus:STATUS_ACTIVE];
	
	Quaternion planetOrientation;
	if (ScanQuaternionFromString([dict objectForKey:@"orientation"], &planetOrientation))
	{
		[planet setOrientation:planetOrientation];
	}

	if (![dict objectForKey:@"position"])
	{
		OOLog(@"script.error.addPlanet.noPosition", @"***** ERROR: you must specify a position for scripted planet '%@' before it can be created", planetKey);
		return;
	}
	
	NSString *positionString = [dict objectForKey:@"position"];
	if([positionString hasPrefix:@"abs "] && ([UNIVERSE planet] != nil || [UNIVERSE sun] !=nil))
	{
		OOLogWARN(@"script.deprecated", @"setting %@ for %@ '%@' in 'abs' inside .plists can cause compatibility issues across Oolite versions. Use coordinates relative to main system objects instead.",@"position",@"planet",planetKey);
	}
	
	Vector posn = [UNIVERSE coordinatesFromCoordinateSystemString:positionString];
	if (posn.x || posn.y || posn.z)
	{
		OOLog(kOOLogDebugAddPlanet, @"planet position (%.2f %.2f %.2f) derived from %@", posn.x, posn.y, posn.z, positionString);
	}
	else
	{
		ScanVectorFromString(positionString, &posn);
		OOLog(kOOLogDebugAddPlanet, @"planet position (%.2f %.2f %.2f) derived from %@", posn.x, posn.y, posn.z, positionString);
	}
	[planet setPosition: posn];
	
	[UNIVERSE addEntity:planet];
}


- (void) addMoon: (NSString *)moonKey
{
	OOLog(kOOLogNoteAddPlanet, @"DEBUG: addMoon '%@'", moonKey);

	if (!UNIVERSE)
		return;
	NSDictionary* dict = [[UNIVERSE planetInfo] oo_dictionaryForKey:moonKey];
	if (!dict)
	{
		OOLog(@"script.error.addPlanet.keyNotFound", @"***** ERROR: could not find an entry in planetinfo.plist for '%@'", moonKey);
		return;
	}

	OOLog(kOOLogDebugAddPlanet, @"DEBUG: initMoonFromDictionary: %@", dict);
	PlanetEntity*	planet = [[[PlanetEntity alloc] initMoonFromDictionary:dict] autorelease];
	[planet setStatus:STATUS_ACTIVE];
	
	Quaternion planetOrientation;
	if (ScanQuaternionFromString([dict objectForKey:@"orientation"], &planetOrientation))
	{
		[planet setOrientation:planetOrientation];
	}

	if (![dict objectForKey:@"position"])
	{
		OOLog(@"script.error.addPlanet.noPosition", @"***** ERROR: you must specify a position for scripted moon '%@' before it can be created", moonKey);
		return;
	}
	
	NSString *positionString = [dict objectForKey:@"position"];
	if([positionString hasPrefix:@"abs "] && ([UNIVERSE planet] != nil || [UNIVERSE sun] !=nil))
	{
		OOLogWARN(@"script.deprecated", @"setting %@ for %@ '%@' in 'abs' inside .plists can cause compatibility issues across Oolite versions. Use coordinates relative to main system objects instead.",@"position",@"moon",moonKey);
	}
	Vector posn = [UNIVERSE coordinatesFromCoordinateSystemString:positionString];
	if (posn.x || posn.y || posn.z)
	{
		OOLog(kOOLogDebugAddPlanet, @"moon position (%.2f %.2f %.2f) derived from %@", posn.x, posn.y, posn.z, positionString);
	}
	else
	{
		ScanVectorFromString(positionString, &posn);
		OOLog(kOOLogDebugAddPlanet, @"moon position (%.2f %.2f %.2f) derived from %@", posn.x, posn.y, posn.z, positionString);
	}
	[planet setPosition: posn];
	
	[UNIVERSE addEntity:planet];
}


- (void) debugOn
{
	OOLogSetDisplayMessagesInClass(kOOLogDebugOnMetaClass, YES);
	OOLog(kOOLogDebugOnOff, @"SCRIPT debug messages ON");
}


- (void) debugOff
{
	OOLog(kOOLogDebugOnOff, @"SCRIPT debug messages OFF");
	OOLogSetDisplayMessagesInClass(kOOLogDebugOnMetaClass, NO);
}


- (void) debugMessage:(NSString *)args
{
	OOLog(kOOLogDebugMessage, @"SCRIPT debugMessage: %@", args);
}


- (void) playSound:(NSString *) soundName
{
	[self playLegacyScriptSound:soundName];
}

/*-----------------------------------------------------*/


- (void) setGuiToMissionScreen
{
	GuiDisplayGen* gui = [UNIVERSE gui];

	// GUI stuff
	{
		[gui clear];
		[gui setTitle:DESC(@"mission-information")];
		//
		[gui setText:DESC(@"press-space-commander") forRow:21 align:GUI_ALIGN_CENTER];
		[gui setColor:[OOColor yellowColor] forRow:21];
		[gui setKey:@"spacebar" forRow:21];
		//
		[gui setSelectableRange:NSMakeRange(0,0)];
		[gui setBackgroundTexture:missionBackgroundTexture];

		[gui setShowTextCursor:NO];
	}
	/* ends */

	missionTextRow = 1;

	if (gui)
		gui_screen = GUI_SCREEN_MISSION;

	if (lastTextKey)
	{
		[lastTextKey release];
		lastTextKey = nil;
	}
	
	[[OOMusicController sharedController] playMissionMusic];
	
	// the following are necessary...
	[UNIVERSE setDisplayText:YES];
	[UNIVERSE setViewDirection:VIEW_GUI_DISPLAY];
}


- (void) setBackgroundFromDescriptionsKey:(NSString*) d_key
{
	NSArray * items = (NSArray *)[[UNIVERSE descriptions] objectForKey:d_key];
	//
	if (!items)
		return;
	//
	[self addScene: items atOffset: kZeroVector];
	//
	[self setShowDemoShips: YES];
}


- (void) addScene:(NSArray *)items atOffset:(Vector)off
{
	unsigned				i;
	
	if (items == nil)  return;
	
	for (i = 0; i < [items count]; i++)
	{
		id item = [items objectAtIndex:i];
		if ([item isKindOfClass:[NSString class]])
		{
			[self processSceneString:item atOffset: off];
		}
		else if ([item isKindOfClass:[NSArray class]])
		{
			[self addScene:item atOffset: off];
		}
		else if ([item isKindOfClass:[NSDictionary class]])
		{
			[self processSceneDictionary:item atOffset: off];
		}
	}
}


- (BOOL) processSceneDictionary:(NSDictionary *) couplet atOffset:(Vector) off
{
	NSArray *conditions = [couplet objectForKey:@"conditions"];
	NSArray *actions = nil;
	if ([couplet objectForKey:@"do"])
		actions = [NSArray arrayWithObject: [couplet objectForKey:@"do"]];
	NSArray *else_actions = nil;
	if ([couplet objectForKey:@"else"])
		else_actions = [NSArray arrayWithObject: [couplet objectForKey:@"else"]];
	BOOL success = YES;
	if (conditions == nil)
	{
		OOLog(@"script.scene.couplet.badConditions", @"***** SCENE ERROR: %@ - conditions not %@, returning %@.", [couplet description], @" found",@"YES and performing 'do' actions");
	}
	else
	{
		if (![conditions isKindOfClass:[NSArray class]])
		{
			OOLog(@"script.scene.couplet.badConditions", @"***** SCENE ERROR: %@ - conditions not %@, returning %@.", [conditions description], @"an array",@"NO");
			return NO;
		}
	}

	// check conditions..
	success = TestScriptConditions(OOSanitizeLegacyScriptConditions(conditions, @"<scene dictionary conditions>"));

	// perform successful actions...
	if ((success) && (actions) && [actions count])
		[self addScene: actions atOffset: off];

	// perform unsuccessful actions
	if ((!success) && (else_actions) && [else_actions count])
		[self addScene: else_actions atOffset: off];

	return success;
}


- (BOOL) processSceneString:(NSString*) item atOffset:(Vector) off
{
	Vector	model_p0;
	Quaternion	model_q;
	
	if (!item)
		return NO;
	NSArray * i_info = ScanTokensFromString(item);
	if (!i_info)
		return NO;
	NSString* i_key = [(NSString*)[i_info objectAtIndex:0] lowercaseString];

	OOLog(kOOLogNoteProcessSceneString, @"..... processing %@ (%@)", i_info, i_key);

	//
	// recursively add further scenes:
	//
	if ([i_key isEqual:@"scene"])
	{
		if ([i_info count] != 5)	// must be scene_key_x_y_z
			return NO;				//		   0.... 1.. 2 3 4
		NSString* scene_key = (NSString*)[i_info objectAtIndex: 1];
		Vector	scene_offset = {0};
		ScanVectorFromString([[i_info subarrayWithRange:NSMakeRange(2, 3)] componentsJoinedByString:@" "], &scene_offset);
		scene_offset.x += off.x;	scene_offset.y += off.y;	scene_offset.z += off.z;
		NSArray * scene_items = (NSArray *)[[UNIVERSE descriptions] objectForKey:scene_key];
		OOLog(kOOLogDebugProcessSceneStringAddScene, @"::::: adding scene: '%@'", scene_key);
		//
		if (scene_items)
		{
			[self addScene: scene_items atOffset: scene_offset];
			return YES;
		}
		else
			return NO;
	}
	//
	// Add ship models:
	//
	if ([i_key isEqual:@"ship"]||[i_key isEqual:@"model"]||[i_key isEqual:@"role"])
	{
		if ([i_info count] != 10)	// must be item_name_x_y_z_W_X_Y_Z_align
		{
			return NO;				//		   0... 1... 2 3 4 5 6 7 8 9....
		}
		
		ShipEntity* ship = nil;
		
		if ([i_key isEqual:@"ship"]||[i_key isEqual:@"model"])
		{
			ship = [UNIVERSE newShipWithName:[i_info oo_stringAtIndex: 1]];
		}
		else if ([i_key isEqual:@"role"])
		{
			ship = [UNIVERSE newShipWithRole:[i_info oo_stringAtIndex: 1]];
		}
		if (!ship)
			return NO;

		ScanVectorAndQuaternionFromString([[i_info subarrayWithRange:NSMakeRange(2, 7)] componentsJoinedByString:@" "], &model_p0, &model_q);
		
		Vector	model_offset = positionOffsetForShipInRotationToAlignment(ship, model_q, [i_info oo_stringAtIndex:9]);
		model_p0 = vector_add(model_p0, vector_subtract(off, model_offset));

		OOLog(kOOLogDebugProcessSceneStringAddModel, @"::::: adding model to scene:'%@'", ship);
		[ship setOrientation: model_q];
		[ship setPosition: model_p0];
		[ship setStatus: STATUS_COCKPIT_DISPLAY];
		[ship setScanClass: CLASS_NO_DRAW];
		[UNIVERSE addEntity: ship];
		[[ship getAI] setStateMachine: @"nullAI.plist"];
		[ship setRoll: 0.0];
		[ship setPitch: 0.0];
		[ship setVelocity: kZeroVector];
		[ship setBehaviour: BEHAVIOUR_STOP_STILL];

		[ship release];
		return YES;
	}
	//
	// Add player ship model:
	//
	if ([i_key isEqual:@"player"])
	{
		if ([i_info count] != 9)	// must be player_x_y_z_W_X_Y_Z_align
			return NO;				//		   0..... 1 2 3 4 5 6 7 8....

		ShipEntity* doppelganger = [UNIVERSE newShipWithName: ship_desc];   // retain count = 1
		if (!doppelganger)
			return NO;
		
		ScanVectorAndQuaternionFromString([[i_info subarrayWithRange:NSMakeRange( 1, 7)] componentsJoinedByString:@" "], &model_p0, &model_q);
		
		Vector	model_offset = positionOffsetForShipInRotationToAlignment( doppelganger, model_q, (NSString*)[i_info objectAtIndex:8]);
		model_p0.x += off.x - model_offset.x;
		model_p0.y += off.y - model_offset.y;
		model_p0.z += off.z - model_offset.z;

		OOLog(kOOLogDebugProcessSceneStringAddModel, @"::::: adding model to scene:'%@'", doppelganger);
		[doppelganger setOrientation: model_q];
		[doppelganger setPosition: model_p0];
		[doppelganger setStatus: STATUS_COCKPIT_DISPLAY];
		[doppelganger setScanClass: CLASS_NO_DRAW];
		[UNIVERSE addEntity: doppelganger];
		[[doppelganger getAI] setStateMachine: @"nullAI.plist"];
		[doppelganger setRoll: 0.0];
		[doppelganger setPitch: 0.0];
		[doppelganger setVelocity: kZeroVector];
		[doppelganger setBehaviour: BEHAVIOUR_STOP_STILL];

		[doppelganger release];
		return YES;
	}
	//
	// Add  planet model: selected via gui-scene-show-planet/-local-planet
	//
	if ([i_key isEqual:@"local-planet"] || [i_key isEqual:@"target-planet"])
	{
		if ([i_info count] != 4)	// must be xxxxx-planet_x_y_z
			return NO;				//		   0........... 1 2 3
		PlanetEntity* doppelganger=nil;
		BOOL	procGen = NO;
#if ALLOW_PROCEDURAL_PLANETS
		procGen = [UNIVERSE doProcedurallyTexturedPlanets];
		if ([i_key isEqual:@"local-planet"] && procGen && [UNIVERSE sun])
		{
			// can safely show retextured planets!
			doppelganger = [[PlanetEntity alloc] initMiniatureFromPlanet:[UNIVERSE planet]];
		}
		else
#endif
		{
			doppelganger = [[PlanetEntity alloc] initWithSeed:target_system_seed];
			if (doppelganger)
				[doppelganger miniaturize];
		}
		if (!doppelganger)
			return NO;
		
		ScanVectorFromString([[i_info subarrayWithRange:NSMakeRange(1, 3)] componentsJoinedByString:@" "], &model_p0);
		Quaternion model_q = { 0.707, 0.707, 0.0, 0.0 };
		if (procGen)
		{
			model_q = make_quaternion( 0.707, 0.314, 0.707, 0.0 );
		} 
		model_p0 = vector_add(model_p0, off);

		OOLog(kOOLogDebugProcessSceneStringAddMiniPlanet, @"::::: adding %@ to scene:'%@'", i_key, doppelganger);
		[doppelganger setOrientation: model_q];
		[doppelganger setPosition: model_p0];
		[UNIVERSE addEntity: doppelganger];

		[doppelganger autorelease];
		return YES;
	}

	//
	// Add billboard model:
	//
	if ([i_key isEqual:@"billboard"])
	{
#if SUPPORT_BILLBOARD
		if ([i_info count] != 6)	// must be billboard_imagefile_x_y_w_h
			return NO;				//		   0........ 1........ 2 3 4 5

		NSString* texturefile = (NSString*)[i_info objectAtIndex:1];
		NSSize billSize = NSMakeSize([[i_info objectAtIndex:4] floatValue], [[i_info objectAtIndex:5] floatValue]);
		Vector	model_p0;
		model_p0.x = [[i_info objectAtIndex:2] floatValue] + off.x;
		model_p0.y = [[i_info objectAtIndex:3] floatValue] + off.y;
		model_p0.z = off.z;

		ParticleEntity* billboard = [[ParticleEntity alloc] initBillboard:billSize withTexture:texturefile];
		if (!billboard)
			return NO;
		
		[billboard setPosition:vector_add([billboard position], model_p0)];
			
		[billboard setStatus: STATUS_COCKPIT_DISPLAY];
		
		OOLog(kOOLogDebugProcessSceneStringAddBillboard, @"::::: adding billboard:'%@' to scene.", billboard);

		[UNIVERSE addEntity: billboard];

		[billboard release];
		return YES;
#else
		OOLogERR(@"scene.billboard", @"Scene billboards are disabled because Ahruman thought no-one was using them.");
#endif
	}
	//
	// fall through..
	return NO;
}


- (BOOL) mapKey:(NSString *)keycode toOXP:(OOScript *)oxp
{
	OOScript *s = [oxpKeys objectForKey:keycode];
	if (s == nil)
	{
		if (oxpKeys == nil)  oxpKeys = [[NSMutableDictionary alloc] init];
		
		[oxpKeys setObject:oxp forKey:keycode];
		return YES;
	}
	
	return NO;
}


- (void) targetNearestHostile
{
	[self scanForHostiles];
	if (found_target != NO_TARGET)
	{
		Entity *ent = [UNIVERSE entityForUniversalID:found_target];
		if (ent != 0x00)
		{
			ident_engaged = YES;
			missile_status = MISSILE_STATUS_TARGET_LOCKED;
			[self addTarget:ent];
		}
	}
}


#if TARGET_INCOMING_MISSILES
- (void) targetNearestIncomingMissile
{
	[self scanForNearestIncomingMissile];
	Entity *ent = [UNIVERSE entityForUniversalID:found_target];
	if (ent != nil)
	{
		ident_engaged = YES;
		missile_status = MISSILE_STATUS_TARGET_LOCKED;
		[self addTarget:ent];
	}
	[self doScriptEvent:@"playerTargetedMissile" withArgument:ent];
}
#endif


- (void) setGalacticHyperspaceBehaviourTo:(NSString *)galacticHyperspaceBehaviourString
{
	OOGalacticHyperspaceBehaviour ghBehaviour = StringToGalacticHyperspaceBehaviour(galacticHyperspaceBehaviourString);
	if (ghBehaviour == GALACTIC_HYPERSPACE_BEHAVIOUR_UNKNOWN)
	{
		OOLog(@"player.setGalacticHyperspaceBehaviour.invalidInput",
			  @"setGalacticHyperspaceBehaviourTo: called with unknown behaviour %@.", galacticHyperspaceBehaviourString);
	}
	[self setGalacticHyperspaceBehaviour:ghBehaviour];
}


- (void) setGalacticHyperspaceFixedCoordsTo:(NSString *)galacticHyperspaceFixedCoordsString
{	
	NSArray *coord_vals = ScanTokensFromString(galacticHyperspaceFixedCoordsString);
	if ([coord_vals count] < 2)	// Will be 0 if string is nil
	{
		OOLog(@"player.setGalacticHyperspaceFixedCoords.invalidInput",
			  @"setGalacticHyperspaceFixedCoords: called with bad specifier. Defaulting to Oolite standard.");
		galacticHyperspaceFixedCoords.x = galacticHyperspaceFixedCoords.y = 0x60;
	}
	
	[self setGalacticHyperspaceFixedCoordsX:[coord_vals oo_unsignedCharAtIndex:0]
										  y:[coord_vals oo_unsignedCharAtIndex:1]];
}

@end


NSString *OOComparisonTypeToString(OOComparisonType type)
{
	switch (type)
	{
		case COMPARISON_EQUAL:			return @"equal";
		case COMPARISON_NOTEQUAL:		return @"notequal";
		case COMPARISON_LESSTHAN:		return @"lessthan";
		case COMPARISON_GREATERTHAN:	return @"greaterthan";
		case COMPARISON_ONEOF:			return @"oneof";
		case COMPARISON_UNDEFINED:		return @"undefined";
	}
	return @"<error: invalid comparison type>";
}
