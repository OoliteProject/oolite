/*

PlayerEntityLegacyScriptEngine.m

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

#include "PlayerEntityLegacyScriptEngine.h"
#include "PlayerEntityScriptMethods.h"
#include "PlayerEntitySound.h"
#include "PlayerEntityContracts.h"
#include "GuiDisplayGen.h"
#include "Universe.h"
#include "ResourceManager.h"
#include "AI.h"
#include "ShipEntityAI.h"
#include "ShipEntityScriptMethods.h"
#include "OOScript.h"
#include "OOMusicController.h"
#include "OOColor.h"
#include "OOStringParsing.h"
#include "OOStringExpander.h"
#include "OOConstToString.h"
#include "OOTexture.h"
#include "OOLoggingExtended.h"
#include "OOSound.h"
#include "OOSunEntity.h"
#include "OOPlanetEntity.h"
#include "OOPlanetDrawable.h"	// oo::makeRef<OOPlanetEntity>() destroys its drawables (bead oo-9ht.129)
#include "StationEntity.h"
#include "OOLegacyScriptWhitelist.h"
#include "OOJavaScriptEngine.h"
#include "OOEquipmentType.h"
#include "HeadUpDisplay.h"
#include "OOSystemDescriptionManager.h"
#include "OOEntityFilterPredicate.h"
#include "oofnd/objc/OOException.h"
#include "OOCallByName.h"
#include "MyOpenGLView.h"

#include "oofnd/StdLib.hpp"
#include "oofnd/PList.hpp"
#include "oofnd/String.hpp"
#include "oofnd/Log.hpp"
#include "oofnd/PListWriting.hpp"
#include "OOObjCPList.h"


static const char *const kOOLogScriptAddShipsFailed			= "script.addShips.failed";
static const char *const kOOLogScriptMissionDescNoText		= "script.missionDescription.noMissionText";
static const char *const kOOLogScriptMissionDescNoKey		= "script.missionDescription.noMissionKey";

static const char *const kOOLogDebugOnMetaClass				= "$scriptDebugOn";
static const char *const kOOLogDebugMessage					= "script.debug.message";
static const char *const kOOLogDebugOnOff					= "script.debug.onOff";
static const char *const kOOLogDebugAddPlanet				= "script.debug.addPlanet";
static const char *const kOOLogDebugReplaceVariablesInString	= "script.debug.replaceVariablesInString";
static const char *const kOOLogDebugProcessSceneStringAddScene = "script.debug.processSceneString.addScene";
static const char *const kOOLogDebugProcessSceneStringAddModel = "script.debug.processSceneString.addModel";
static const char *const kOOLogDebugProcessSceneStringAddMiniPlanet = "script.debug.processSceneString.addMiniPlanet";

static const char *const kOOLogNoteRemoveAllCargo			= "script.debug.note.removeAllCargo";
static const char *const kOOLogNoteUseSpecialCargo			= "script.debug.note.useSpecialCargo";
static const char *const kOOLogNoteAddShips					= "script.debug.note.addShips";
static const char *const kOOLogNoteSet						= "script.debug.note.set";
static const char *const kOOLogNoteShowShipModel				= "script.debug.note.showShipModel";
static const char *const kOOLogNoteFuelLeak					= "script.debug.note.setFuelLeak";
static const char *const kOOLogNoteAddPlanet					= "script.debug.note.addPlanet";
static const char *const kOOLogNoteProcessSceneString		= "script.debug.note.processSceneString";

static const char *const kOOLogSyntaxSetPlanetInfo			= "script.debug.syntax.setPlanetInfo";
static const char *const kOOLogSyntaxAwardCargo				= "script.debug.syntax.awardCargo";
static const char *const kOOLogSyntaxAwardEquipment			= "script.debug.syntax.awardEquipment";
static const char *const kOOLogSyntaxRemoveEquipment			= "script.debug.syntax.removeEquipment";
static const char *const kOOLogSyntaxMessageShipAIs			= "script.debug.syntax.messageShipAIs";
static const char *const kOOLogSyntaxAddShips				= "script.debug.syntax.addShips";
static const char *const kOOLogSyntaxSet						= "script.debug.syntax.set";
static const char *const kOOLogSyntaxReset					= "script.debug.syntax.reset";
static const char *const kOOLogSyntaxIncrement				= "script.debug.syntax.increment";
static const char *const kOOLogSyntaxDecrement				= "script.debug.syntax.decrement";
static const char *const kOOLogSyntaxAdd						= "script.debug.syntax.add";
static const char *const kOOLogSyntaxSubtract				= "script.debug.syntax.subtract";

static const char *const kOOLogRemoveAllCargoNotDocked		= "script.error.removeAllCargo.notDocked";


#define	ACTIONS_TEMP_PREFIX									"__oolite_actions_temp"
namespace {
constexpr const char *kActionTempPrefix			= ACTIONS_TEMP_PREFIX;
} // namespace


namespace {
std::optional<std::string>	sMissionStringValue;	// the variable a mission/local condition reads (nullopt: unset)
} // namespace
namespace {
std::optional<std::string>	sCurrentMissionKey;	// nullopt: no current mission (was nil)
} // namespace
static ShipEntity	*scriptTarget = nil;


namespace {
std::string CurrentScriptNameOr(const std::string &alternative)
{
	if (sCurrentMissionKey.has_value() && !oo::str::hasPrefix(*sCurrentMissionKey, kActionTempPrefix))
	{
		return "\"" + *sCurrentMissionKey + "\"";
	}
	return alternative;
}


std::string CurrentScriptDescription(void)
{
	return CurrentScriptNameOr("<anonymous actions>");
}


// A sanitized statement's element (a null PList for a missing one; sanitized trees always have them).
const oo::PList &ElementAt(const oo::PList &array, std::size_t index)
{
	static const oo::PList sNull;
	const oo::PList *element = array.at(index);
	return element != nullptr ? *element : sNull;
}


/*	Whitespace without newlines: GNUstep's whitespace-and-newline set (the scanner's
	oo::str::isWhitespaceOrNewline) without its newlines (U+000A-U+000D, U+0085, U+2028, U+2029).
	The later chunks of oo-j924 reuse it.
*/
bool IsWhitespaceNotNewline(char16_t c)
{
	return c == 0x09 || c == 0x20 || c == 0xA0 || c == 0x1680 || (c >= 0x2000 && c <= 0x200B)
		   || c == 0x202F || c == 0x205F || c == 0x3000;
}


// [UNIVERSE missiontext]'s entry as -oo_stringForKey: read it: a string, or a number's text. The
// universe's C++ part holds the table (no universe: none, as a message to nil answered).
std::optional<std::string> MissionTextForKey(const std::string &key)
{
	Universe *universe = UNIVERSE;
	const oo::PList missionText = (universe != nullptr) ? universe->getMissiontext() : oo::PList();
	const oo::PList *entry = missionText.find(key);
	const oo::PList value = (entry != nullptr) ? *entry : oo::PList();
	if (const std::string *string = value.getIf<std::string>())  return *string;
	if (value.isNumber())  return oo::plist_get::numberStringValue(value);
	return std::nullopt;
}


// An element as -oo_stringAtIndex: read it (a string, or a number's text; else nullopt).
std::optional<std::string> StringAtIndex(const oo::PList &array, std::size_t index)
{
	const oo::PList *value = array.at(index);
	if (value == nullptr)  return std::nullopt;
	if (const std::string *string = value->getIf<std::string>())  return *string;
	if (value->isNumber())  return oo::plist_get::numberStringValue(*value);
	return std::nullopt;
}


// A by-name value that turns a mission resource off: empty, or "none" in any case.
bool IsNoneValue(const std::string &value)
{
	return value.empty() || oo::str::lowercase(value) == "none";
}


// Tokens as a PList array, so an element reads with -oo_intAtIndex: & co.'s rules (get<T>).
oo::PList TokenArray(const std::vector<std::string> &tokens)
{
	oo::PList::Array result;
	for (const std::string &token : tokens)  result.push_back(oo::PList(token));
	return oo::PList(std::move(result));
}


// A query's string result: a string, or null for none (was nil).
oo::PList StringOrNull(const std::optional<std::string> &string)
{
	return string.has_value() ? oo::PList(*string) : oo::PList();
}


// The current system's data value for <key>, or null (was -objectForKey: of the Objective-C dictionary).
// The universe's C++ part answers (no universe: null, as a message to nil did).
oo::PList CurrentSystemDataValue(std::string_view key)
{
	Universe *universe = UNIVERSE;
	const oo::PList data = (universe != nullptr) ? universe->currentSystemData() : oo::PList();
	const oo::PList *value = data.find(key);
	return value != nullptr ? *value : oo::PList();
}


// -intValue of a query's result: a number's C conversion, a string's leading integer, none 0.
int IntValueOf(const oo::PList &value)
{
	if (const std::string *string = value.getIf<std::string>())  return oo::str::intValue(*string);
	return value.isNumber() ? static_cast<int>(value.int64Value()) : 0;
}


// -componentsJoinedByString:@" " of tokens[from...].
std::string JoinedFrom(const std::vector<std::string> &tokens, std::size_t from)
{
	std::string result;
	for (std::size_t i = from; i < tokens.size(); i++)
	{
		if (i != from)  result += " ";
		result += tokens[i];
	}
	return result;
}


std::string TrimWhitespace(std::string_view s)
{
	return oo::str::trimTrailing(oo::str::trimLeading(s, IsWhitespaceNotNewline), IsWhitespaceNotNewline);
}


/*	A query result or variable as the string the condition compares: a string as itself, nil as
	nullopt. Anything else (a variable holding an array, say) compares as its description; the old
	code sent it -isEqualToString: and raised.
*/
std::optional<std::string> ConditionString(const oo::PList &value)
{
	if (value.isNull())  return std::nullopt;
	if (const std::string *string = value.getIf<std::string>())  return *string;
	return oo::DescriptionOf(value);
}


// A *_number query's result as -doubleValue read it: a number's value, a string parsed, 0 for nil.
double QueryDoubleValue(const oo::PList &value)
{
	if (const std::string *string = value.getIf<std::string>())  return oo::str::doubleValue(*string);
	return value.doubleValue();
}


void PerformScriptActions(const oo::PList &actions, Entity *target);
void PerformConditionalStatment(const oo::PList &actions, Entity *target);
void PerformActionStatment(const oo::PList &statement, Entity *target);
BOOL TestScriptConditions(const oo::PList &conditions);
} // namespace


namespace {
void PerformScriptActions(const oo::PList &actions, Entity *target)
{
	const oo::PList::Array *statements = actions.getIf<oo::PList::Array>();
	if (statements == nullptr)  return;
	for (const oo::PList &statement : *statements)
	{
		if (ElementAt(statement, 0).boolValue())
		{
			PerformConditionalStatment(statement, target);
		}
		else
		{
			PerformActionStatment(statement, target);
		}
	}
}


void PerformConditionalStatment(const oo::PList &statement, Entity *target)
{
	/*	A sanitized conditional statement takes the form of an array:
		(true, conditions, trueActions, falseActions)
		The first element is always true. The second is an array of conditions.
		The third and four elements are actions to perform if the conditions
		evaluate to true or false, respectively.
	*/
	
	const oo::PList		&conditions = ElementAt(statement, 1);

	if (TestScriptConditions(conditions))
	{
		PerformScriptActions(ElementAt(statement, 2), target);
	}
	else
	{
		PerformScriptActions(ElementAt(statement, 3), target);
	}
}


void PerformActionStatment(const oo::PList &statement, Entity *target)
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
	
	std::string					selectorString;
	std::optional<std::string>	argumentString;
	PlayerEntity				*player = PLAYER;

	selectorString = statement.at<std::string>(1);
	if (statement.count() > 2)  argumentString = statement.at<std::string>(2);

	// The target's C++ part answers its methods called by name (bead oo-9ht.39.7.1), the player's
	// for the player only (bead oo-9ht.177); the planet's shader bindings are never actions
	Entity *cxxTarget = target;	// (oo::ToCxx of its object until bead oo-zwnvp)
	if (cxxTarget == nullptr || !oo::EntityRespondsToName(cxxTarget, selectorString))
	{
		cxxTarget = player;
	}

	if (argumentString.has_value())
	{
		// Method with argument; substitute [description] expressions. The action is called by
		// name with the expanded string (ADR-0055 item 5); a failed expansion passes nil, as before.
		// the player's C++ part answers the mission's locals (no player: none, as a message to nil did)
		PlayerEntity *cxxPlayer = player;
		const oo::PList locals = (cxxPlayer != nullptr) ? cxxPlayer->localVariablesForMission(sCurrentMissionKey) : oo::PList();
		const std::optional<std::string> expanded = cxx_OOExpandDescriptionString(OOStringExpanderDefaultRandomSeed(), *argumentString, oo::PList(), locals, std::nullopt, kOOExpandNoOptions);
		if (expanded.has_value())  oo::CallEntityByName(cxxTarget, selectorString, *expanded);
		else  oo::CallEntityByName(cxxTarget, selectorString, oo::PList());
	}
	else
	{
		// Method without argument.
		oo::CallEntityByName(cxxTarget, selectorString);
	}
}


BOOL TestScriptConditions(const oo::PList &conditions)
{
	PlayerEntity		*player = PLAYER;	// no player: every condition failed, as a message to nil answered

	if (const oo::PList::Array *conditionArray = conditions.getIf<oo::PList::Array>())
	{
		for (const oo::PList &condition : *conditionArray)
		{
			if (player == nullptr || !player->scriptTestCondition(condition))  return NO;
		}
	}

	return YES;
}
} // namespace


void PlayerEntity::setScriptTarget(::ShipEntity *ship)
{
	::scriptTarget = ship;
}


void PlayerEntity::setScriptTargetToSelf()
{
	setScriptTarget(this);
}


::ShipEntity *PlayerEntity::scriptTarget()
{
	return ::scriptTarget;
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


// Return the world scripts that care about -checkScript, by name, in the world scripts' (load) order.
std::vector<std::pair<std::string, oo::Ref<OOScript>>> PlayerEntity::getWorldScriptsRequiringTickle()
{
	// The cache ivar is PlayerEntity.h's; it is built once per script load.
	if (worldScriptsRequiringTickle.has_value())  return *worldScriptsRequiringTickle;

	std::vector<std::pair<std::string, oo::Ref<OOScript>>> tickleScripts;
	for (const auto &entry : worldScripts)
	{
		if (entry.second != nullptr && entry.second->requiresTickle())
		{
			tickleScripts.push_back(entry);
		}
	}

	worldScriptsRequiringTickle = tickleScripts;
	return tickleScripts;
}


void PlayerEntity::checkScript()
{
	BOOL						wasRunningScript = sRunningScript;
	OOEntityStatus				status, restoreStatus;
	
	const std::vector<std::pair<std::string, oo::Ref<OOScript>>> tickleScripts = getWorldScriptsRequiringTickle();
	if (tickleScripts.empty())
	{
		// Quick exit if we only have JS scripts.
		return;
	}
	
	setScriptTarget(this);
	
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
	status = this->status();
	restoreStatus = status;
	try
	{
		if (sRunningScript)
		{
			status = RecursiveRemapStatus(status);
			setStatus(status);
		}
		sRunningScript = YES;
		
		// After all that, actually running the scripts is trivial. ORDER-SENSITIVE (decision D):
		// load order (was script-name byte order, and before that the hash order of -allValues).
		for (const auto &entry : tickleScripts)
		{
			if (entry.second != nullptr)  entry.second->runWithTarget(this);
		}
	}
	catch (...)
	{
		const auto exception = oo::CurrentOOException();
		if (!exception)  throw;	// not an OOException: it goes on up, as before
		OO_LOG(cxx_kOOLogException, "***** Exception running world scripts: {} : {}", exception->name(), exception->reason());
	}
	
	// Restore anti-recursion measures.
	sRunningScript = wasRunningScript;
	if (status != restoreStatus)  setStatus(restoreStatus);
}


void PlayerEntity::runScriptActions(const oo::PList &actions, const std::optional<std::string> &contextName, ::ShipEntity *target)
{
	std::optional<std::string>	oldMissionKey;

	{
		oo::AutoreleaseScope pool;	// was @autoreleasepool (oo-31u.8)
		// FIXME: does this actually make sense in the context of non-missions?
		oldMissionKey = sCurrentMissionKey;
		sCurrentMissionKey = contextName;

		try
		{
			PerformScriptActions(actions, target);
		}
		catch (...)
		{
			const auto exception = oo::CurrentOOException();
			if (!exception)  throw;	// not an OOException: it goes on up, as before
			OO_LOG("script.error.exception",
				  "***** EXCEPTION {}: {} while handling legacy script actions for {}",
				  exception->name(),
				  exception->reason(),
				  (contextName.has_value() && oo::str::hasPrefix(*contextName, kActionTempPrefix)) ? oo::EntityShortDescription(target) : contextName.value_or("(null)"));
			// Suppress exception
		}

		sCurrentMissionKey = oldMissionKey;
	}
}


void PlayerEntity::runUnsanitizedScriptActions(const oo::PList &actions, bool allowAIMethods, const std::optional<std::string> &contextName, ::ShipEntity *target)
{
	runScriptActions(OOSanitizeLegacyScript(actions, contextName, allowAIMethods), contextName, target);
}


bool PlayerEntity::scriptTestConditions(const oo::PList &array)
{
	BOOL				result = NO;
	
	try
	{
		result = TestScriptConditions(array);
	}
	catch (...)
	{
		const auto exception = oo::CurrentOOException();
		if (!exception)  throw;	// not an OOException: it goes on up, as before
		OO_LOG("script.error.exception",
			  "***** EXCEPTION {}: {} while testing legacy script conditions.",
			  exception->name(),
			  exception->reason());
		// Suppress exception
	}
	
	return result;
}


bool PlayerEntity::scriptTestCondition(const oo::PList &scriptCondition)
{
	/*	Test a script condition sanitized by OOLegacyScriptWhitelist.
		
		A sanitized condition is an array of the form:
			(opType, rawString, selector, comparisonType, operandArray).
		
		opType and comparisonType are numbers containing OOOperationType and
		OOComparisonType enumerators, respectively.
		
		rawString is the original textual representation of the condition for
		display purposes.
		
		selector is a string, either a method selector or a mission/local
		variable name.
		
		operandArray is an array of operands. Each operand is itself an array
		of two items: a boolean indicating whether it's a method selector
		(true) or a literal string (false), and a string.
		
		The special opType OP_FALSE doesn't require any other elements in the
		array. All other valid opTypes require the array to have five elements.
		
		For performance reasons, this method assumes the script condition will
		have been generated by OOSanitizeLegacyScriptConditions() and doesn't
		perform extensive validity checks.
	*/

	OOOperationType				opType;
	std::string					selectorString;
	std::string					selector;	// the query's name (bead oo-9ht.39.7.1: called on the player's C++ part)
	OOComparisonType			comparator;
	std::optional<std::string>	lhsString;
	std::string					expandedRHS;
	double						lhsValue, rhsValue;
	BOOL						lhsFlag, rhsFlag;

	opType = (OOOperationType)scriptCondition.at<unsigned int>(0);
	if (opType == OP_FALSE)  return NO;

	selectorString = scriptCondition.at<std::string>(2);
	comparator = (OOComparisonType)scriptCondition.at<unsigned int>(3);
	const oo::PList &operandArray = ElementAt(scriptCondition, 4);

	// Transform mission/local var ops into string ops.
	if (opType == OP_MISSION_VAR)
	{
		sMissionStringValue = ConditionString(missionVariableForKey(selectorString));
		selector = "mission_string";
		opType = OP_STRING;
	}
	else if (opType == OP_LOCAL_VAR)
	{
		const oo::PList locals = localVariablesForMission(sCurrentMissionKey);
		const oo::PList *local = locals.find(selectorString);
		sMissionStringValue = ConditionString(local != nullptr ? *local : oo::PList());
		selector = "mission_string";
		opType = OP_STRING;
	}
	else
	{
		selector = selectorString;
	}

	expandedRHS = expandScriptRightHandSide(operandArray).value_or(std::string());

	if (opType == OP_STRING)
	{
		// The query is called by name and answers a PList (ADR-0055 item 5).
		lhsString = ConditionString(oo::CallEntityByName(this, selector));

	#define DOUBLEVAL(x) ((x).has_value() ? oo::str::doubleValue(*(x)) : 0.0)

		switch (comparator)
		{
			case COMPARISON_UNDEFINED:
				return !lhsString.has_value();

			case COMPARISON_EQUAL:
				return lhsString.has_value() && *lhsString == expandedRHS;

			case COMPARISON_NOTEQUAL:
				return !(lhsString.has_value() && *lhsString == expandedRHS);

			case COMPARISON_LESSTHAN:
				return DOUBLEVAL(lhsString) < oo::str::doubleValue(expandedRHS);

			case COMPARISON_GREATERTHAN:
				return DOUBLEVAL(lhsString) > oo::str::doubleValue(expandedRHS);

			case COMPARISON_ONEOF:
				{
					if (!lhsString.has_value())  return NO;	// nil matched nothing
					const std::string trimmedLHS = TrimWhitespace(*lhsString);

					for (const std::string &rhsItem : oo::str::split(expandedRHS, ","))
					{
						if (trimmedLHS == TrimWhitespace(rhsItem))
						{
							return YES;
						}
					}
				}
				return NO;
		}
	}
	else if (opType == OP_NUMBER)
	{
		lhsValue = QueryDoubleValue(oo::CallEntityByName(this, selector));

		if (comparator == COMPARISON_ONEOF)
		{
			for (const std::string &rhsItem : oo::str::split(expandedRHS, ","))
			{
				rhsValue = oo::str::doubleValue(rhsItem);

				if (lhsValue == rhsValue)
				{
					return YES;
				}
			}

			return NO;
		}
		else
		{
			rhsValue = oo::str::doubleValue(expandedRHS);

			switch (comparator)
			{
				case COMPARISON_EQUAL:
					return lhsValue == rhsValue;

				case COMPARISON_NOTEQUAL:
					return lhsValue != rhsValue;

				case COMPARISON_LESSTHAN:
					return lhsValue < rhsValue;

				case COMPARISON_GREATERTHAN:
					return lhsValue > rhsValue;

				case COMPARISON_UNDEFINED:
				case COMPARISON_ONEOF:
					// "Can't happen" - undefined should have been caught by the sanitizer, oneof is handled above.
					OO_LOG("script.error.unexpectedOperator", "***** SCRIPT ERROR: in {}, operator {} is not valid for numbers, evaluating to false.", CurrentScriptDescription(), cxx_OOComparisonTypeToString(comparator));
					return NO;
			}
		}
	}
	else if (opType == OP_BOOL)
	{
		lhsFlag = ConditionString(oo::CallEntityByName(this, selector)) == std::optional<std::string>("YES");
		rhsFlag = expandedRHS == "YES";

		switch (comparator)
		{
			case COMPARISON_EQUAL:
				return lhsFlag == rhsFlag;

			case COMPARISON_NOTEQUAL:
				return lhsFlag != rhsFlag;

			case COMPARISON_LESSTHAN:
			case COMPARISON_GREATERTHAN:
			case COMPARISON_UNDEFINED:
			case COMPARISON_ONEOF:
				// "Can't happen" - should have been caught by the sanitizer.
				OO_LOG("script.error.unexpectedOperator", "***** SCRIPT ERROR: in {}, operator {} is not valid for booleans, evaluating to false.", CurrentScriptDescription(), cxx_OOComparisonTypeToString(comparator));
				return NO;
		}
	}

	// What are we doing here? (The condition prints as an old-style plist: decision C.)
	const auto conditionText = oo::writeOldStylePList(scriptCondition);
	std::string conditionDescription = conditionText.has_value() ? std::string(conditionText->stringView()) : std::string();
	if (!conditionDescription.empty() && conditionDescription.back() == '\n')  conditionDescription.pop_back();
	OO_LOG("script.error.fallthrough", "***** SCRIPT ERROR: in {}, unhandled condition '{}' ({}). {}", CurrentScriptDescription(), scriptCondition.at<std::string>(1), conditionDescription, "This is an internal error, please report it.");
	return NO;
}


std::optional<std::string> PlayerEntity::expandScriptRightHandSide(const oo::PList &rhsComponents)
{
	std::string				result;
	bool					first = true;

	if (const oo::PList::Array *components = rhsComponents.getIf<oo::PList::Array>())
	{
		for (const oo::PList &component : *components)
		{
			/*	Each component is a two-element array. The second element is a
				string. The first element is a boolean indicating whether the
				string is a selector (true) or a literal (false).

				All valid selectors return a string or a number; in either
				case, -description gives us a useful value to substitute into
				the expanded string.
			*/

			std::string value = component.at<std::string>(1);

			if (ElementAt(component, 0).boolValue())
			{
				// (nil prints "(null)", for backwards compatibility)
				value = oo::DescriptionOf(oo::CallEntityByName(this, value));
			}

			if (!first)  result += " ";
			result += value;
			first = false;
		}
	}

	return result;
}


oo::PList PlayerEntity::missionVariables()
{
	return mission_variables;	// a snapshot
}


oo::PList PlayerEntity::missionVariableForKey(const std::string &key)
{
	const oo::PList *value = mission_variables.find(key);
	return (value != nullptr) ? *value : oo::PList();
}


// Before set-up (no store yet) nothing is stored, as messaging the nil dictionary did.
void PlayerEntity::setMissionVariable(const oo::PList &value, const std::string &key)
{
	oo::PList::Dict *store = mission_variables.getIf<oo::PList::Dict>();
	if (store == nullptr)  return;
	if (!value.isNull())  (*store)[key] = value;
	else store->erase(key);
}


/*	A mission's local variables, as a snapshot Dict (null for no mission). The per-mission tables in
	the localVariables ivar (PlayerEntity.h's) are replaced on write; nothing else reads or saves
	them, so the old create-an-empty-table-on-read side effect is not kept.
*/
oo::PList PlayerEntity::localVariablesForMission(const std::optional<std::string> &missionKey)
{
	if (!missionKey.has_value())  return oo::PList();

	const auto found = localVariables.find(*missionKey);
	oo::PList result = (found != localVariables.end()) ? found->second : oo::PList();
	if (!result.isDict())  result = oo::PList(oo::PList::Dict{});
	return result;
}


std::optional<std::string> PlayerEntity::localVariableForKey(const std::string &variableName, const std::optional<std::string> &missionKey)
{
	if (!missionKey.has_value())  return std::nullopt;
	const oo::PList locals = localVariablesForMission(missionKey);
	const oo::PList *value = locals.find(variableName);
	if (value == nullptr)  return std::nullopt;
	return ConditionString(*value);
}


void PlayerEntity::setLocalVariable(const std::optional<std::string> &value, const std::string &variableName, const std::optional<std::string> &missionKey)
{
	if (missionKey.has_value())
	{
		oo::PList locals = localVariablesForMission(missionKey);
		oo::PList::Dict *table = locals.getIf<oo::PList::Dict>();
		if (value.has_value())
		{
			(*table)[variableName] = oo::PList(*value);
		}
		else
		{
			table->erase(variableName);
		}
		localVariables[*missionKey] = std::move(locals);
	}
}


oo::PList PlayerEntity::missionsList()
{
	oo::PList::Array		result1;	// strings
	oo::PList::Array		result2;	// arrays: a header, then entries

	// The manifests (PlayerEntityContracts), their entries' strings.
	const std::vector<std::string>	passengerManifest = passengerList();
	const std::vector<std::string>	contractManifest = contractList();
	const std::vector<std::string>	parcelManifest = parcelList();

	auto addManifest = [&result2](const std::string &header, const std::vector<std::string> &entries)
	{
		if (entries.empty())  return;
		oo::PList::Array list{ oo::PList(header) };
		for (const std::string &entry : entries)  list.push_back(oo::PList(entry));
		result2.push_back(oo::PList(std::move(list)));
	};

	addManifest(OO_DESC("manifest-passengers"), passengerManifest);
	addManifest(OO_DESC("manifest-parcels"), parcelManifest);
	addManifest(OO_DESC("manifest-contracts"), contractManifest);

	/* For proper display, array entries need to all be after string
	 * entries, so sort them now */
	// ORDER-SENSITIVE (decision D): world scripts in load order (was -allKeys order)
	for (const std::string &scriptName : worldScriptNames())
	{
		const oo::PList vars = missionVariableForKey(scriptName);

		if (vars.isString())
		{
			result1.push_back(vars);
		}
		else if (const oo::PList::Array *varList = vars.getIf<oo::PList::Array>())
		{
			BOOL found = NO;
			const std::optional<std::string> header = StringAtIndex(vars, 0);
			for (std::size_t i = 0; i < result2.size(); i++)
			{
				const std::optional<std::string> elementHeader = StringAtIndex(result2[i], 0);
				if (elementHeader.has_value() && header.has_value() && *elementHeader == *header)
				{
					// -removeObject: (every equal element), then the merged list at the end.
					const oo::PList element = result2[i];
					std::erase(result2, element);
					oo::PList::Array merged = *element.getIf<oo::PList::Array>();
					merged.insert(merged.end(), varList->begin() + 1, varList->end());
					result2.push_back(oo::PList(std::move(merged)));
					found = YES;
					break;
				}
			}
			if (!found)
			{
				result2.push_back(vars);
			}
		}
	}
	result1.insert(result1.end(), result2.begin(), result2.end());
	return oo::PList(std::move(result1));
}


std::optional<std::string> PlayerEntity::replaceVariablesInString(const std::string &args)
{
	const oo::PList		locals = localVariablesForMission(sCurrentMissionKey);
	std::string			resultString = args;

	// Each replacement is literal (NSLiteralSearch).
	auto replace = [&resultString](const std::string &target, const std::string &replacement)
	{
		resultString = oo::str::replaceOccurrences(resultString, target, replacement, oo::str::Search::literal);
	};

	for (const std::string &valueString : oo::str::tokens(args))
	{
		const oo::PList missionValue = oo::str::hasPrefix(valueString, "mission_") ? missionVariableForKey(valueString) : oo::PList();
		const oo::PList *localValue = locals.find(valueString);

		if (!missionValue.isNull())
		{
			// (a non-string variable substitutes its description; the old code raised)
			replace(valueString, ConditionString(missionValue).value_or(std::string()));
		}
		else if (localValue != nullptr)
		{
			replace(valueString, ConditionString(*localValue).value_or(std::string()));
		}
		else if (oo::str::hasSuffix(valueString, "_number") || oo::str::hasSuffix(valueString, "_bool") || oo::str::hasSuffix(valueString, "_string"))
		{
			// called by name on the player's C++ part (bead oo-9ht.39.7.1); "%@" of the result, as
			// +stringWithFormat: printed it
			if (oo::EntityRespondsToName(this, valueString))
			{
				replace(valueString, oo::DescriptionOf(oo::CallEntityByName(this, valueString)));
			}
		}
		else if (oo::str::hasPrefix(valueString, "[") && oo::str::hasSuffix(valueString, "]"))
		{
			replace(valueString, cxx_OOExpand(valueString).value_or(std::string()));
		}
	}

	OO_LOG(kOOLogDebugReplaceVariablesInString, "EXPANSION: \"{}\" becomes \"{}\"", args, resultString);

	return resultString;
}

/*-----------------------------------------------------*/


void PlayerEntity::setMissionDescription(const std::string &textKey)	// called by name (ADR-0043 item 21)
{
	setMissionDescription(textKey, sCurrentMissionKey);
}


void PlayerEntity::setMissionDescription(const std::string &textKey, const std::optional<std::string> &key)
{
	const std::optional<std::string> text = MissionTextForKey(textKey);

	if (!text.has_value())
	{
		OO_LOG_ERR(kOOLogScriptMissionDescNoText, "in {}, no mission text set for key '{}' [UNIVERSE missiontext] is:\n{} ", CurrentScriptDescription(), textKey, oo::DescriptionOf((UNIVERSE != nullptr ? UNIVERSE->getMissiontext() : oo::PList())));
		return;
	}

	setMissionInstructions(*text, key);
}


// implementation of mission.setInstructions(), also final part of legacy setMissionDescription
void PlayerEntity::setMissionInstructions(const std::string &text, const std::optional<std::string> &key)
{
	if (!key.has_value())
	{
		OO_LOG_ERR(kOOLogScriptMissionDescNoKey, "in {}, mission key not set", CurrentScriptDescription());
		return;
	}

	const std::string expanded = cxx_OOExpand(text).value_or(std::string());
	setMissionVariable(oo::PList(replaceVariablesInString(expanded).value_or(std::string())), *key);
}


void PlayerEntity::setMissionInstructionsList(const oo::PList &list, const std::optional<std::string> &key)
{
	if (!key.has_value())
	{
		OO_LOG_ERR(kOOLogScriptMissionDescNoKey, "in {}, mission key not set", CurrentScriptDescription());
		return;
	}

	oo::PList::Array expandedList;
	NSUInteger i,ct = list.count();
	for (i=0 ; i<ct ; i++)
	{
		const std::optional<std::string> text = StringAtIndex(list, i);
		if (text.has_value())
		{
			const std::string expanded = cxx_OOExpand(*text).value_or(std::string());
			expandedList.push_back(oo::PList(replaceVariablesInString(expanded).value_or(std::string())));
		}
	}

	setMissionVariable(oo::PList(std::move(expandedList)), *key);
}


void PlayerEntity::clearMissionDescription()
{
	if (!sCurrentMissionKey.has_value())
	{
		OO_LOG_ERR(kOOLogScriptMissionDescNoKey, "in {}, mission key not set", CurrentScriptDescription());
		return;
	}

	clearMissionDescriptionForMission(*sCurrentMissionKey);
}


void PlayerEntity::clearMissionDescriptionForMission(const std::string &key)	// called by name (ADR-0043 item 21)
{
	setMissionVariable(oo::PList(), key);	// (removing an absent key does nothing)
}


// called by name (ADR-0043 item 21), as are the queries below
oo::PList PlayerEntity::mission_string()
{
	return StringOrNull(sMissionStringValue);
}


oo::PList PlayerEntity::status_string()	// called by name (ADR-0043 item 21)
{
	return oo::PList(cxx_OOStringFromEntityStatus(status()));
}


oo::PList PlayerEntity::gui_screen_string()	// called by name (ADR-0043 item 21)
{
	return oo::PList(cxx_OOStringFromGUIScreenID(gui_screen));
}


oo::PList PlayerEntity::getGalaxy_number()	// called by name (ADR-0043 item 21)
{
	return oo::PList::signedInteger(currentGalaxyID());
}


oo::PList PlayerEntity::planet_number()	// called by name (ADR-0043 item 21)
{
	return oo::PList::signedInteger(currentSystemID());
}


oo::PList PlayerEntity::score_number()	// called by name (ADR-0043 item 21)
{
	return oo::PList::unsignedInteger(score());
}


oo::PList PlayerEntity::credits_number()	// called by name (ADR-0043 item 21)
{
	return oo::PList((double)(creditBalance()));
}


oo::PList PlayerEntity::scriptTimer_number()	// called by name (ADR-0043 item 21)
{
	return oo::PList((double)(scriptTimer()));
}


static int shipsFound;
oo::PList PlayerEntity::shipsFound_number()	// called by name (ADR-0043 item 21)
{
	return oo::PList::signedInteger(shipsFound);
}


oo::PList PlayerEntity::commanderLegalStatus_number()	// called by name (ADR-0043 item 21)
{
	return oo::PList::signedInteger(getLegalStatus());
}


void PlayerEntity::setLegalStatus(const std::string &valueString)	// called by name (ADR-0043 item 21)
{
	legalStatusValue = oo::str::intValue(valueString);
}


oo::PList PlayerEntity::commanderLegalStatus_string()	// called by name (ADR-0043 item 21)
{
	return StringOrNull(cxx_OODisplayStringFromLegalStatus(legalStatusValue));
}


oo::PList PlayerEntity::d100_number()	// called by name (ADR-0043 item 21)
{
	int d100 = ranrot_rand() % 100;
	return oo::PList::signedInteger(d100);
}


oo::PList PlayerEntity::pseudoFixedD100_number()	// called by name (ADR-0043 item 21)
{
	return oo::PList::signedInteger(systemPseudoRandom100());
}


oo::PList PlayerEntity::d256_number()	// called by name (ADR-0043 item 21)
{
	int d256 = ranrot_rand() % 256;
	return oo::PList::signedInteger(d256);
}


oo::PList PlayerEntity::pseudoFixedD256_number()	// called by name (ADR-0043 item 21)
{
	return oo::PList::signedInteger(systemPseudoRandom256());
}


oo::PList PlayerEntity::clock_number()	// called by name (ADR-0043 item 21); returns the game time in seconds
{
	return oo::PList((double)(ship_clock));
}


oo::PList PlayerEntity::clock_secs_number()	// called by name (ADR-0043 item 21); returns the game time in seconds
{
	return oo::PList::unsignedInteger((unsigned long long)(ship_clock));
}


oo::PList PlayerEntity::clock_mins_number()	// called by name (ADR-0043 item 21); returns the game time in minutes
{
	return oo::PList::unsignedInteger((unsigned long long)(ship_clock / 60.0));
}


oo::PList PlayerEntity::clock_hours_number()	// called by name (ADR-0043 item 21); returns the game time in hours
{
	return oo::PList::unsignedInteger((unsigned long long)(ship_clock / 3600.0));
}


oo::PList PlayerEntity::clock_days_number()	// called by name (ADR-0043 item 21); returns the game time in days
{
	return oo::PList::unsignedInteger((unsigned long long)(ship_clock / 86400.0));
}


oo::PList PlayerEntity::fuelLevel_number()	// called by name (ADR-0043 item 21); returns the fuel level in LY
{
	return oo::PList::singleReal((float)(floor(0.1 * fuel)));
}


oo::PList PlayerEntity::dockedAtMainStation_bool()	// called by name (ADR-0043 item 21)
{
	if (dockedAtMainStation())  return oo::PList("YES");
	else  return oo::PList("NO");
}


oo::PList PlayerEntity::foundEquipment_bool()	// called by name (ADR-0043 item 21)
{
	return oo::PList((found_equipment)? "YES" : "NO");
}


oo::PList PlayerEntity::sunWillGoNova_bool()	// called by name (ADR-0043 item 21); returns whether the sun is going to go nova
{
	return oo::PList((((UNIVERSE != nullptr ? UNIVERSE->sun() : nullptr) != nullptr ? UNIVERSE->sun()->willGoNova() : false))? "YES" : "NO");
}


oo::PList PlayerEntity::sunGoneNova_bool()	// called by name (ADR-0043 item 21); returns whether the sun has gone nova
{
	return oo::PList((((UNIVERSE != nullptr ? UNIVERSE->sun() : nullptr) != nullptr ? UNIVERSE->sun()->goneNova() : false))? "YES" : "NO");
}


oo::PList PlayerEntity::missionChoice_string()	// called by name (ADR-0043 item 21); returns nil or the key for the chosen option
{
	return StringOrNull(missionChoice);
}


oo::PList PlayerEntity::missionKeyPress_string()	// called by name (ADR-0043 item 21)
{
	return StringOrNull(missionKeyPress);
}


oo::PList PlayerEntity::dockedTechLevel_number()	// called by name (ADR-0043 item 21)
{
	::StationEntity *dockedStation = this->dockedStation();
	if (!dockedStation) 
	{
		return systemTechLevel_number();
	}
	return oo::PList::unsignedInteger((dockedStation != nullptr ? dockedStation->getEquivalentTechLevel() : 0));
}

oo::PList PlayerEntity::dockedStationName_string()	// called by name (ADR-0043 item 21); returns 'NONE' if the player isn't docked, [station name] if it is, 'UNKNOWN' otherwise (?)
{
	if (status() != STATUS_DOCKED)  return oo::PList("NONE");

	return oo::PList(dockedStationName().value_or("UNKNOWN"));
}


oo::PList PlayerEntity::systemGovernment_string()	// called by name (ADR-0043 item 21)
{
	int government = IntValueOf(systemGovernment_number()); // 0 .. 7 (0 anarchic .. 7 most stable)
	return oo::PList(cxx_OODisplayStringFromGovernmentID(government).value_or("UNKNOWN"));
}


oo::PList PlayerEntity::systemGovernment_number()	// called by name (ADR-0043 item 21)
{
	return CurrentSystemDataValue(KEY_GOVERNMENT);
}


oo::PList PlayerEntity::systemEconomy_string()	// called by name (ADR-0043 item 21)
{
	int economy = IntValueOf(systemEconomy_number()); // 0 .. 7 (0 rich industrial .. 7 poor agricultural)
	return oo::PList(cxx_OODisplayStringFromEconomyID(economy).value_or("UNKNOWN"));
}


oo::PList PlayerEntity::systemEconomy_number()	// called by name (ADR-0043 item 21)
{
	return CurrentSystemDataValue(KEY_ECONOMY);
}


oo::PList PlayerEntity::systemTechLevel_number()	// called by name (ADR-0043 item 21)
{
	return CurrentSystemDataValue(KEY_TECHLEVEL);
}


oo::PList PlayerEntity::systemPopulation_number()	// called by name (ADR-0043 item 21)
{
	return CurrentSystemDataValue(KEY_POPULATION);
}


oo::PList PlayerEntity::systemProductivity_number()	// called by name (ADR-0043 item 21)
{
	return CurrentSystemDataValue(KEY_PRODUCTIVITY);
}


oo::PList PlayerEntity::commanderName_string()	// called by name (ADR-0043 item 21)
{
	return StringOrNull(commanderName());
}


oo::PList PlayerEntity::commanderRank_string()	// called by name (ADR-0043 item 21)
{
	return StringOrNull(cxx_OODisplayRatingStringFromKillCount(score()));
}


oo::PList PlayerEntity::commanderShip_string()	// called by name (ADR-0043 item 21)
{
	return StringOrNull(getName());
}


oo::PList PlayerEntity::commanderShipDisplayName_string()	// called by name (ADR-0043 item 21)
{
	return StringOrNull(getDisplayName());
}

/*-----------------------------------------------------*/


std::optional<std::string> PlayerEntity::expandMessage(const std::string &valueString)
{
	Random_Seed very_random_seed;
	very_random_seed.a = rand() & 255;
	very_random_seed.b = rand() & 255;
	very_random_seed.c = rand() & 255;
	very_random_seed.d = rand() & 255;
	very_random_seed.e = rand() & 255;
	very_random_seed.f = rand() & 255;
	seed_RNG_only_for_planet_description(very_random_seed);
	return replaceVariablesInString(cxx_OOExpand(valueString).value_or(std::string()));
}


void PlayerEntity::commsMessage(const std::string &valueString)	// called by name (ADR-0055 item 5); shared selector (proposed ADR-0043)
{
	if (UNIVERSE != nullptr)  UNIVERSE->addCommsMessage(expandMessage(valueString), 4.5);
}


// Enabled on 02-May-2008 - Nikos
// This method does the same as -commsMessage, (which in fact calls), the difference being that scripts can use this
// method to have unpiloted ship entities sending comms messages.
void PlayerEntity::commsMessageByUnpiloted(const std::string &valueString)	// called by name (ADR-0055 item 5); shared selector (proposed ADR-0043)
{
	commsMessage(valueString);
}


void PlayerEntity::consoleMessage3s(const std::string &valueString)	// called by name (ADR-0043 item 21)
{
	if (UNIVERSE != nullptr)  UNIVERSE->addMessage(expandMessage(valueString), 3);
}


void PlayerEntity::consoleMessage6s(const std::string &valueString)	// called by name (ADR-0043 item 21)
{
	if (UNIVERSE != nullptr)  UNIVERSE->addMessage(expandMessage(valueString), 6);
}


void PlayerEntity::awardCredits(const std::string &valueString)	// called by name (ADR-0043 item 21)
{
	if (::scriptTarget != this)  return;

	/*	We can't use -longLongValue here for Mac OS X 10.4 compatibility, but
		we don't need to since larger values have never been supported for
		legacy scripts.
	*/
	int64_t award = oo::str::intValue(valueString);
	award *= 10;
	if (award < 0 && credits < (OOCreditsQuantity)-award)  credits = 0;
	else  credits += award;
}


void PlayerEntity::awardShipKills(const std::string &valueString)	// called by name (ADR-0043 item 21)
{
	if (::scriptTarget != this)  return;

	int value = oo::str::intValue(valueString);
	if (0 < value)  ship_kills += value;
}


void PlayerEntity::awardEquipment(const std::string &equipString)	// called by name (ADR-0043 item 21); eg. EQ_NAVAL_ENERGY_UNIT
{
	if (::scriptTarget != this)  return;

	const std::string equipKey = equipString;
	if (equipKey == "EQ_FUEL")
	{
		setFuel(fuelCapacity());
	}

	::OOEquipmentType *eqType = OOEquipmentType::equipmentTypeWithIdentifier(equipKey).get();

	if ((eqType != nullptr ? eqType->isMissileOrMine() : false))
	{
		mountMissileWithRole(equipKey);
	}
	else if(oo::str::hasPrefix(equipKey, "EQ_WEAPON") && !oo::str::hasSuffix(equipKey, "_DAMAGED"))
	{
		OO_LOG(kOOLogSyntaxAwardEquipment, "***** SCRIPT ERROR: in {}, CANNOT award undamaged weapon:'{}'. Damaged weapons can be awarded instead.", CurrentScriptDescription(), equipKey);
	}
	// (the "_DAMAGED" suffix is ASCII, so its bytes are its characters)
	else if (oo::str::hasSuffix(equipKey, "_DAMAGED") && hasEquipmentItem(oo::PList(equipKey.substr(0, equipKey.size() - 8))))
	{
		OO_LOG(kOOLogSyntaxAwardEquipment, "***** SCRIPT ERROR: in {}, CANNOT award damaged equipment:'{}'. Undamaged version already equipped.", CurrentScriptDescription(), equipKey);
	}
	else if ((eqType != nullptr ? eqType->canCarryMultiple() : false) || !hasEquipmentItem(oo::PList(equipKey)))
	{
		addEquipmentItem(equipKey, YES, "scripted");
	}
}


void PlayerEntity::removeEquipment(const std::string &equipString)	// called by name (ADR-0043 item 21); eg. EQ_NAVAL_ENERGY_UNIT
{
	if (::scriptTarget != this)  return;

	const std::string equipKey = equipString;
	if (equipKey == "EQ_FUEL")
	{
		fuel = 0;
		return;
	}

	if (equipKey == "EQ_CARGO_BAY" && hasEquipmentItem(oo::PList(equipKey))
			&& (extraCargo() > availableCargoSpace()))
	{
		OO_LOG(kOOLogSyntaxRemoveEquipment, "***** SCRIPT ERROR: in {}, CANNOT remove cargo bay. Too much cargo.", CurrentScriptDescription());
		return;
	}
	if (hasEquipmentItem(oo::PList(equipKey)) || hasEquipmentItem(oo::PList(equipKey + "_DAMAGED")))
	{
		removeEquipmentItem(equipKey);
	}

}


void PlayerEntity::setPlanetinfo(const std::string &key_valueString)	// called by name (ADR-0043 item 21); uses key=value format
{
	const std::string argument = key_valueString;
	const std::vector<std::string> tokens = oo::str::split(argument, "=");

	if (tokens.size() != 2)
	{
		OO_LOG(kOOLogSyntaxSetPlanetInfo, "***** SCRIPT ERROR: in {}, CANNOT setPlanetinfo: '{}' (bad parameter count)", CurrentScriptDescription(), argument);
		return;
	}

	const std::string keyString = TrimWhitespace(tokens[0]);
	const std::string valueString = TrimWhitespace(tokens[1]);

	/* Legacy script planetinfo settings are now non-persistent over save/load
	 * Virtually nothing uses them any more, and expecting them to have a
	 * manifest and identifying what it is if so seems unnecessary */
	if (UNIVERSE != nullptr)  UNIVERSE->setSystemDataKey(keyString, oo::PList(valueString), std::string());

}


void PlayerEntity::setSpecificPlanetInfo(const std::string &key_valueString)	// called by name (ADR-0043 item 21); uses galaxy#=planet#=key=value
{
	const std::string argument = key_valueString;
	const std::vector<std::string> tokens = oo::str::split(argument, "=");
	int gnum, pnum;

	if (tokens.size() != 4)
	{
		OO_LOG(kOOLogSyntaxSetPlanetInfo, "***** SCRIPT ERROR: in {}, CANNOT setSpecificPlanetInfo: '{}' (bad parameter count)", CurrentScriptDescription(), argument);
		return;
	}

	const oo::PList tokenArray = TokenArray(tokens);
	gnum = tokenArray.at<int>(0);
	pnum = tokenArray.at<int>(1);
	const std::string keyString = TrimWhitespace(tokens[2]);
	const std::string valueString = TrimWhitespace(tokens[3]);

	if (UNIVERSE != nullptr)  UNIVERSE->setSystemDataForGalaxy(gnum, pnum, keyString, oo::PList(valueString), std::string(), OO_LAYER_OXP_DYNAMIC);
}


void PlayerEntity::awardCargo(const std::string &amount_typeString)	// called by name (ADR-0043 item 21)
{
	if (::scriptTarget != this)  return;

	const std::string		argument = amount_typeString;
	const std::vector<std::string>	tokens = oo::str::tokens(argument);
	OOCargoQuantityDelta	amount;
	OOMassUnit				unit;

	if (tokens.size() != 2)
	{
		OO_LOG(kOOLogSyntaxAwardCargo, "***** SCRIPT ERROR: in {}, CANNOT awardCargo: '{}' ({})", CurrentScriptDescription(), argument, "bad parameter count");
		return;
	}

	const oo::PList tokenArray = TokenArray(tokens);
	const std::string &type = tokens[1];	// the good (Amendment 1 item 10: a std::string)
	if (!((UNIVERSE != nullptr ? UNIVERSE->getCommodities() : nullptr) != nullptr ? UNIVERSE->getCommodities()->goodDefined(type) : false))
	{
		OO_LOG(kOOLogSyntaxAwardCargo, "***** SCRIPT ERROR: in {}, CANNOT awardCargo: '{}' ({})", CurrentScriptDescription(), argument, "unknown type");
		return;
	}

	amount = tokenArray.at<int>(0);
	if (amount < 0)
	{
		OO_LOG(kOOLogSyntaxAwardCargo, "***** SCRIPT ERROR: in {}, CANNOT awardCargo: '{}' ({})", CurrentScriptDescription(), argument, "negative quantity");
		return;
	}

	unit = (shipCommodityData != nullptr ? shipCommodityData->massUnitForGood(type) : UNITS_TONS);
	if (specialCargo && unit == UNITS_TONS)
	{
		OO_LOG(kOOLogSyntaxAwardCargo, "***** SCRIPT ERROR: in {}, CANNOT awardCargo: '{}' ({})", CurrentScriptDescription(), argument, "cargo hold full with special cargo");
		return;
	}

	awardCommodityType(type, amount);
}


void PlayerEntity::removeAllCargo()
{
	removeAllCargo(NO);
}

void PlayerEntity::removeAllCargo(bool forceRemoval)
{
	// Misnamed method. It only removes cargo measured in TONS, g & Kg items are not removed. --Kaks 20091004
	if (::scriptTarget != this)  return;

	if (status() != STATUS_DOCKED && !forceRemoval)
	{
		OO_LOG_WARN(kOOLogRemoveAllCargoNotDocked, "{}removeAllCargo only works when docked.", " in " + CurrentScriptDescription() + ", ");
		return;
	}

	OO_LOG(kOOLogNoteRemoveAllCargo, "{} removeAllCargo", forceRemoval ? "Forcing" : "Going to");

	for (const std::string &type : (shipCommodityData != nullptr ? shipCommodityData->goods() : std::vector<std::string>()))
	{
		if ((shipCommodityData != nullptr ? shipCommodityData->massUnitForGood(type) : UNITS_TONS) == UNITS_TONS)
		{
			if (shipCommodityData != nullptr)  shipCommodityData->setQuantity(0, type);
		}
	}


	if (forceRemoval && status() != STATUS_DOCKED)
	{
		NSInteger i;
		for (i = cargo.size() - 1; i >= 0; i--)
		{
			::ShipEntity* canister = oo::ToShip(cargo[i].get());
			if (!canister)  break;
			// Since we are forcing cargo removal, we don't really care about the unit of measurement. Any
			// commodity at more than 1000kg or 1000000gr will be inside cargopods, so remove those too.
			cargo.erase(cargo.begin() + i);
		}
	}

	specialCargo.reset();

	calculateCurrentCargo();
}


void PlayerEntity::useSpecialCargo(const std::string &descriptionString)	// called by name (ADR-0043 item 21)
{
	if (::scriptTarget != this)  return;

	const std::string description = descriptionString;
	removeAllCargo(YES);
	OO_LOG(kOOLogNoteUseSpecialCargo, "Going to useSpecialCargo:'{}'", description);
	specialCargo = cxx_OOExpand(description);
}


void PlayerEntity::testForEquipment(const std::string &equipString)	// called by name (ADR-0043 item 21); eg. EQ_NAVAL_ENERGY_UNIT
{
	found_equipment = hasEquipmentItem(oo::PList(equipString));
}


void PlayerEntity::awardFuel(const std::string &valueString)	// called by name (ADR-0043 item 21); add to fuel up to 7.0 LY
{
	int delta  = 10 * (float)oo::str::doubleValue(valueString);
	OOFuelQuantity scriptTargetFuelBeforeAward = (::scriptTarget != nullptr ? ::scriptTarget->getFuel() : OOFuelQuantity{});

	if (delta < 0 && scriptTargetFuelBeforeAward < (unsigned)-delta)  { if (::scriptTarget != nullptr)  ::scriptTarget->setFuel(0); }
	else
	{
		if (::scriptTarget != nullptr)  ::scriptTarget->setFuel((scriptTargetFuelBeforeAward + delta));
	}
}


void PlayerEntity::messageShipAIs(const std::string &roles_message)	// called by name (ADR-0043 item 21)
{
	const std::string			argument = roles_message;
	const std::vector<std::string>	tokens = oo::str::tokens(argument);

	if (tokens.size() < 2)
	{
		OO_LOG(kOOLogSyntaxMessageShipAIs, "***** SCRIPT ERROR: in {}, CANNOT messageShipAIs: '{}' (bad parameter count)", CurrentScriptDescription(), argument);
		return;
	}

	std::string roleString = tokens[0];
	const std::string messageString = JoinedFrom(tokens, 1);

	for (const auto &target : (UNIVERSE != nullptr ? UNIVERSE->findShipsMatchingPredicate(HasPrimaryRolePredicate, &roleString, -1, nullptr) : std::vector<oo::EntityHold>()))
	{
		if (oo::ToShip(target.get()) != nullptr && oo::ToShip(target.get())->getAI() != nullptr)  oo::ToShip(target.get())->getAI()->reactToMessage(messageString, std::string("messageShipAIs:"));
	}
}


void PlayerEntity::ejectItem(const std::string &itemKey)	// called by name (ADR-0043 item 21)
{
	if (::scriptTarget == nil)  ::scriptTarget = oo::ToShip(this);
	if (::scriptTarget != nullptr)  ::scriptTarget->ejectShipOfType(itemKey);
}


void PlayerEntity::addShips(const std::string &roles_number)	// called by name (ADR-0043 item 21)
{
	const std::string			argument = roles_number;
	const std::vector<std::string>	tokens = oo::str::tokens(argument);

	if (tokens.size() != 2)
	{
		OO_LOG(kOOLogSyntaxAddShips, "***** SCRIPT ERROR: in {}, CANNOT addShips: '{}' (expected <role> <count>)", CurrentScriptDescription(), argument);
		return;
	}

	const std::string &roleString = tokens[0];

	int number = oo::str::intValue(tokens[1]);
	if (number < 0)
	{
		OO_LOG(kOOLogSyntaxAddShips, "***** SCRIPT ERROR: in {}, can't add {} ships -- that's less than zero, y'know..", CurrentScriptDescription(), number);
		return;
	}

	OO_LOG(kOOLogNoteAddShips, "DEBUG: Going to add {} ships with role '{}'", number, roleString);

	while (number--)
		if (UNIVERSE != nullptr)  UNIVERSE->witchspaceShipWithPrimaryRole(roleString);
}


void PlayerEntity::addSystemShips(const std::string &roles_number_position)	// called by name (ADR-0043 item 21)
{
	const std::string			argument = roles_number_position;
	const std::vector<std::string>	tokens = oo::str::tokens(argument);

	if (tokens.size() != 3)
	{
		OO_LOG(kOOLogSyntaxAddShips, "***** SCRIPT ERROR: in {}, CANNOT addSystemShips: '{}' (expected <role> <count> <position>)", CurrentScriptDescription(), argument);
		return;
	}

	const std::string &roleString = tokens[0];

	int number = oo::str::intValue(tokens[1]);
	double posn = oo::str::doubleValue(tokens[2]);
	if (number < 0)
	{
		OO_LOG(kOOLogSyntaxAddShips, "***** SCRIPT ERROR: in {}, can't add {} ships -- that's less than zero, y'know..", CurrentScriptDescription(), number);
		return;
	}

	OO_LOG(kOOLogNoteAddShips, "DEBUG: Going to add {} ships with role '{}' at a point {:.3f} along route1", number, roleString, posn);

	while (number--)
		if (UNIVERSE != nullptr)  UNIVERSE->addShipWithRole(roleString, posn);
}


void PlayerEntity::addShipsAt(const std::string &roles_number_system_x_y_z)	// called by name (ADR-0043 item 21)
{
	const std::string			argument = roles_number_system_x_y_z;
	const std::vector<std::string>	tokens = oo::str::tokens(argument);

	if (tokens.size() != 6)
	{
		OO_LOG(kOOLogSyntaxAddShips, "***** SCRIPT ERROR: in {}, CANNOT addShipsAt: '{}' (expected <role> <count> <coordinate-system> <x> <y> <z>)", CurrentScriptDescription(), argument);
		return;
	}

	const std::string &roleString = tokens[0];
	const std::string &systemString = tokens[2];

	HPVector posn = make_HPvector(oo::str::doubleValue(tokens[3]), oo::str::doubleValue(tokens[4]), oo::str::doubleValue(tokens[5]));

	int number = oo::str::intValue(tokens[1]);
	if (number < 1)
	{
		OO_LOG(kOOLogSyntaxAddShips, "----- WARNING in {}  Tried to add {} ships -- no ship added.", CurrentScriptDescription(), number);
		return;
	}

	OO_LOG(kOOLogNoteAddShips, "DEBUG: Going to add {} ship(s) with role '{}' at point ({:.3f}, {:.3f}, {:.3f}) using system {}", number, roleString, posn.x, posn.y, posn.z, systemString);

	if (!(UNIVERSE != nullptr ? UNIVERSE->addShipsNearPosition(number, roleString, posn, systemString) : false))
	{
		OO_LOG(kOOLogScriptAddShipsFailed, "***** SCRIPT ERROR: in {}, {} could not add {} ships with role \"{}\"", CurrentScriptDescription(), "addShipsAt:", (unsigned)number, roleString);
	}
}


void PlayerEntity::addShipsAtPrecisely(const std::string &roles_number_system_x_y_z)	// called by name (ADR-0043 item 21)
{
	const std::string			argument = roles_number_system_x_y_z;
	const std::vector<std::string>	tokens = oo::str::tokens(argument);

	if (tokens.size() != 6)
	{
		OO_LOG(kOOLogSyntaxAddShips, "***** SCRIPT ERROR: in {},* CANNOT addShipsAtPrecisely: '{}' (expected <role> <count> <coordinate-system> <x> <y> <z>)", CurrentScriptDescription(), argument);
		return;
	}

	const std::string &roleString = tokens[0];
	const std::string &systemString = tokens[2];

	HPVector posn = make_HPvector(oo::str::doubleValue(tokens[3]), oo::str::doubleValue(tokens[4]), oo::str::doubleValue(tokens[5]));

	int number = oo::str::intValue(tokens[1]);
	if (number < 1)
	{
		OO_LOG(kOOLogSyntaxAddShips, "----- WARNING: in {}, Can't add {} ships -- no ship added.", CurrentScriptDescription(), number);
		return;
	}

	OO_LOG(kOOLogNoteAddShips, "DEBUG: Going to add {} ship(s) with role '{}' precisely at point ({:.3f}, {:.3f}, {:.3f}) using system {}", number, roleString, posn.x, posn.y, posn.z, systemString);

	if (!(UNIVERSE != nullptr ? UNIVERSE->addShipsAtPosition(number, roleString, posn, systemString) : false))
	{
		OO_LOG(kOOLogScriptAddShipsFailed, "***** SCRIPT ERROR: in {}, {} could not add {} ships with role '{}'", CurrentScriptDescription(), "addShipsAtPrecisely:", (unsigned)number, roleString);
	}
}


void PlayerEntity::addShipsWithinRadius(const std::string &roles_number_system_x_y_z_r)	// called by name (ADR-0043 item 21)
{
	const std::string			argument = roles_number_system_x_y_z_r;
	const std::vector<std::string>	tokens = oo::str::tokens(argument);

	if (tokens.size() != 7)
	{
		OO_LOG(kOOLogSyntaxAddShips, "***** SCRIPT ERROR: in {}, CANNOT 'addShipsWithinRadius: {}' (expected <role> <count> <coordinate-system> <x> <y> <z> <radius>))", CurrentScriptDescription(), argument);
		return;
	}

	const std::string &roleString = tokens[0];
	int number = oo::str::intValue(tokens[1]);
	const std::string &systemString = tokens[2];
	double x = oo::str::doubleValue(tokens[3]);
	double y = oo::str::doubleValue(tokens[4]);
	double z = oo::str::doubleValue(tokens[5]);
	GLfloat r = (float)oo::str::doubleValue(tokens[6]);
	HPVector posn = make_HPvector(x, y, z);

	if (number < 1)
	{
		OO_LOG(kOOLogSyntaxAddShips, "----- WARNING: in {}, can't add {} ships -- no ship added.", CurrentScriptDescription(), number);
		return;
	}

	OO_LOG(kOOLogNoteAddShips, "DEBUG: Going to add {} ship(s) with role '{}' within {:.2f} radius about point ({:.3f}, {:.3f}, {:.3f}) using system {}", number, roleString, (double)r, x, y, z, systemString);

	if (!(UNIVERSE != nullptr ? UNIVERSE->addShipsNearPosition(number, roleString, posn, systemString, r) : false))
	{
		OO_LOG(kOOLogScriptAddShipsFailed, "***** SCRIPT ERROR :in {}, {} could not add {} ships with role \"{}\"", CurrentScriptDescription(), "addShipsWithinRadius:", (unsigned)number, roleString);
	}
}


void PlayerEntity::spawnShip(const std::string &ship_key)	// called by name (ADR-0055 item 5)
{
	if ((UNIVERSE != nullptr ? UNIVERSE->spawnShip(ship_key) : false))
	{
		OO_LOG(kOOLogNoteAddShips, "DEBUG: Spawned ship with shipdata key '{}'.", ship_key);
	}
	else
	{
		OO_LOG(kOOLogScriptAddShipsFailed, "***** SCRIPT ERROR: in {}, could not spawn ship with shipdata key '{}'.", CurrentScriptDescription(), ship_key);
	}
}


void PlayerEntity::set(const std::string &missionvariable_value)	// called by name (ADR-0043 item 21)
{
	const std::string	argument = missionvariable_value;
	std::vector<std::string>	tokens = oo::str::tokens(argument);
	std::string			missionVariableString;
	std::string			valueString;
	BOOL				hasMissionPrefix, hasLocalPrefix;

	if (tokens.size() < 2)
	{
		OO_LOG(kOOLogSyntaxSet, "***** SCRIPT ERROR: in {}, CANNOT SET '{}' (expected mission_variable or local_variable followed by value expression)", CurrentScriptDescription(), argument);
		return;
	}

	missionVariableString = tokens[0];
	valueString = JoinedFrom(tokens, 1);

	hasMissionPrefix = oo::str::hasPrefix(missionVariableString, "mission_");
	hasLocalPrefix = oo::str::hasPrefix(missionVariableString, "local_");

	if (!hasMissionPrefix && !hasLocalPrefix)
	{
		OO_LOG(kOOLogSyntaxSet, "***** SCRIPT ERROR: in {}, IDENTIFIER '{}' DOES NOT BEGIN WITH 'mission_' or 'local_'", CurrentScriptDescription(), missionVariableString);
		return;
	}

	OO_LOG(kOOLogNoteSet, "DEBUG: script {} is set to {}", missionVariableString, valueString);

	if (hasMissionPrefix)
	{
		setMissionVariable(oo::PList(valueString), missionVariableString);
	}
	else
	{
		setLocalVariable(valueString, missionVariableString, sCurrentMissionKey);
	}
}


void PlayerEntity::reset(const std::string &missionvariable)	// called by name (ADR-0043 item 21)
{
	const std::string missionVariableString = TrimWhitespace(missionvariable);
	BOOL hasMissionPrefix, hasLocalPrefix;

	hasMissionPrefix = oo::str::hasPrefix(missionVariableString, "mission_");
	hasLocalPrefix = oo::str::hasPrefix(missionVariableString, "local_");

	if (hasMissionPrefix)
	{
		setMissionVariable(oo::PList(), missionVariableString);
	}
	else if (hasLocalPrefix)
	{
		setLocalVariable(std::nullopt, missionVariableString, sCurrentMissionKey);
	}
	else
	{
		OO_LOG(kOOLogSyntaxReset, "***** SCRIPT ERROR: in {}, IDENTIFIER '{}' DOES NOT BEGIN WITH 'mission_' or 'local_'", CurrentScriptDescription(), missionVariableString);
	}
}


void PlayerEntity::increment(const std::string &missionVariableObject)	// called by name (ADR-0043 item 21)
{
	const std::string missionVariableString = missionVariableObject;
	BOOL hasMissionPrefix, hasLocalPrefix;
	int value = 0;

	hasMissionPrefix = oo::str::hasPrefix(missionVariableString, "mission_");
	hasLocalPrefix = oo::str::hasPrefix(missionVariableString, "local_");

	if (hasMissionPrefix)
	{
		value = oo::str::intValue(ConditionString(missionVariableForKey(missionVariableString)).value_or(std::string()));
		value++;
		setMissionVariable(oo::PList(oo::str::format("%d", value)), missionVariableString);
	}
	else if (hasLocalPrefix)
	{
		value = oo::str::intValue(localVariableForKey(missionVariableString, sCurrentMissionKey).value_or(std::string()));
		value++;
		setLocalVariable(oo::str::format("%d", value), missionVariableString, sCurrentMissionKey);
	}
	else
	{
		OO_LOG(kOOLogSyntaxIncrement, "***** SCRIPT ERROR: in {}, IDENTIFIER '{}' DOES NOT BEGIN WITH 'mission_' or 'local_'", CurrentScriptDescription(), missionVariableString);
	}
}


void PlayerEntity::decrement(const std::string &missionVariableObject)	// called by name (ADR-0043 item 21)
{
	const std::string missionVariableString = missionVariableObject;
	BOOL hasMissionPrefix, hasLocalPrefix;
	int value = 0;

	hasMissionPrefix = oo::str::hasPrefix(missionVariableString, "mission_");
	hasLocalPrefix = oo::str::hasPrefix(missionVariableString, "local_");

	if (hasMissionPrefix)
	{
		value = oo::str::intValue(ConditionString(missionVariableForKey(missionVariableString)).value_or(std::string()));
		value--;
		setMissionVariable(oo::PList(oo::str::format("%d", value)), missionVariableString);
	}
	else if (hasLocalPrefix)
	{
		value = oo::str::intValue(localVariableForKey(missionVariableString, sCurrentMissionKey).value_or(std::string()));
		value--;
		setLocalVariable(oo::str::format("%d", value), missionVariableString, sCurrentMissionKey);
	}
	else
	{
		OO_LOG(kOOLogSyntaxDecrement, "***** SCRIPT ERROR: in {}, IDENTIFIER '{}' DOES NOT BEGIN WITH 'mission_' or 'local_'", CurrentScriptDescription(), missionVariableString);
	}
}


void PlayerEntity::add(const std::string &missionVariableString_value)	// called by name (ADR-0043 item 21)
{
	const std::string	argument = missionVariableString_value;
	std::string			missionVariableString;
	std::string			valueString;
	double	value;
	std::vector<std::string>	tokens = oo::str::tokens(argument);
	BOOL hasMissionPrefix, hasLocalPrefix;

	if (tokens.size() < 2)
	{
		OO_LOG(kOOLogSyntaxAdd, "***** SCRIPT ERROR: in {}, CANNOT ADD: '{}'", CurrentScriptDescription(), argument);
		return;
	}

	missionVariableString = tokens[0];
	valueString = JoinedFrom(tokens, 1);

	hasMissionPrefix = oo::str::hasPrefix(missionVariableString, "mission_");
	hasLocalPrefix = oo::str::hasPrefix(missionVariableString, "local_");

	if (hasMissionPrefix)
	{
		value = oo::str::doubleValue(ConditionString(missionVariableForKey(missionVariableString)).value_or(std::string()));
		value += oo::str::doubleValue(valueString);
		setMissionVariable(oo::PList(oo::str::format("%f", value)), missionVariableString);
	}
	else if (hasLocalPrefix)
	{
		value = oo::str::doubleValue(localVariableForKey(missionVariableString, sCurrentMissionKey).value_or(std::string()));
		value += oo::str::doubleValue(valueString);
		setLocalVariable(oo::str::format("%f", value), missionVariableString, sCurrentMissionKey);
	}
	else
	{
		OO_LOG(kOOLogSyntaxAdd, "***** SCRIPT ERROR: in {}, CANNOT ADD: '{}' -- IDENTIFIER '{}' DOES NOT BEGIN WITH 'mission_' or 'local_'", CurrentScriptDescription(), argument, argument);
	}
}


void PlayerEntity::subtract(const std::string &missionVariableString_value)	// called by name (ADR-0043 item 21)
{
	const std::string	argument = missionVariableString_value;
	std::string			missionVariableString;
	std::string			valueString;
	double	value;
	std::vector<std::string>	tokens = oo::str::tokens(argument);
	BOOL hasMissionPrefix, hasLocalPrefix;

	if (tokens.size() < 2)
	{
		OO_LOG(kOOLogSyntaxSubtract, "***** SCRIPT ERROR: in {}, CANNOT SUBTRACT: '{}'", CurrentScriptDescription(), argument);
		return;
	}

	missionVariableString = tokens[0];
	valueString = JoinedFrom(tokens, 1);

	hasMissionPrefix = oo::str::hasPrefix(missionVariableString, "mission_");
	hasLocalPrefix = oo::str::hasPrefix(missionVariableString, "local_");

	if (hasMissionPrefix)
	{
		value = oo::str::doubleValue(ConditionString(missionVariableForKey(missionVariableString)).value_or(std::string()));
		value -= oo::str::doubleValue(valueString);
		setMissionVariable(oo::PList(oo::str::format("%f", value)), missionVariableString);
	}
	else if (hasLocalPrefix)
	{
		value = oo::str::doubleValue(localVariableForKey(missionVariableString, sCurrentMissionKey).value_or(std::string()));
		value -= oo::str::doubleValue(valueString);
		setLocalVariable(oo::str::format("%f", value), missionVariableString, sCurrentMissionKey);
	}
	else
	{
		OO_LOG(kOOLogSyntaxSubtract, "***** SCRIPT ERROR: in {}, CANNOT SUBTRACT: '{}' -- IDENTIFIER '{}' DOES NOT BEGIN WITH 'mission_' or 'local_'", CurrentScriptDescription(), argument, argument);
	}
}


void PlayerEntity::checkForShips(const std::string &roleString)	// called by name (ADR-0043 item 21)
{
	shipsFound = (UNIVERSE != nullptr ? UNIVERSE->countShipsWithPrimaryRole(roleString) : 0u);
}


void PlayerEntity::resetScriptTimer()
{
	script_time = 0.0;
	script_time_check = SCRIPT_TIMER_INTERVAL;
	script_time_interval = SCRIPT_TIMER_INTERVAL;
}


void PlayerEntity::addMissionText(const std::string &textKey)	// called by name (ADR-0043 item 21)
{
	const std::optional<std::string> key = textKey;

	if (key.has_value() && key == lastTextKey)  return; // don't repeatedly add the same text
	lastTextKey = key;

	// Replace literal \n in strings with line breaks and perform expansions.
	const std::optional<std::string> text = MissionTextForKey(key.value_or(std::string()));
	if (!key.has_value() || !text.has_value())  return;
	const std::string expanded = cxx_OOExpandWithOptions(OOStringExpanderDefaultRandomSeed(), kOOExpandBackslashN, *text).value_or(std::string());

	const std::optional<std::string> literal = replaceVariablesInString(expanded);
	if (literal.has_value())  addLiteralMissionText(*literal);
}


void PlayerEntity::addLiteralMissionText(const std::string &text)	// called by name (ADR-0043 item 21)
{
	::GuiDisplayGen *gui = (UNIVERSE != nullptr ? UNIVERSE->getGui() : nullptr);

	for (const std::string &para : oo::str::split(text, "\n"))
	{
		missionTextRow = gui->addLongText(para, missionTextRow, GUI_ALIGN_LEFT);
	}
}


void PlayerEntity::setMissionChoiceByTextEntry(bool enable)
{
	::MyOpenGLView	*gameView = (UNIVERSE != nullptr ? UNIVERSE->getGameView() : nullptr);
	_missionTextEntry = enable;
	if (gameView != nullptr)  gameView->resetTypedString();
}


void PlayerEntity::setMissionChoices(const std::string &choicesKey)	// called by name (ADR-0043 item 21); choicesKey is a key for a dictionary of // choices/choice phrases in missiontext.plist and also..
{
	const oo::PList missionText = (UNIVERSE != nullptr ? UNIVERSE->getMissiontext() : oo::PList());
	const oo::PList *choicesEntry = missionText.find(choicesKey);
	const oo::PList choicesDict = (choicesEntry != nullptr) ? *choicesEntry : oo::PList();
	if (!choicesDict.isDict() || choicesDict.count() == 0)
	{
		return;
	}
	setMissionChoicesDictionary(choicesDict);
}


void PlayerEntity::setMissionChoicesDictionary(const oo::PList &choicesDict)
{
	::GuiDisplayGen* gui = (UNIVERSE != nullptr ? UNIVERSE->getGui() : nullptr);
	// TODO: MORE STUFF HERE
	//
	// What it does now:
	// find list of choices in missiontext.plist
	// add them to gui setting the key for each line to the key in the dict of choices
	// and the text of the line to the value in the dict of choices
	// and also set the selectable range
	// ++ change the mission screen's response to wait for a choice
	// and only if the selectable range is not present ask:
	// Press Space Commander...
	//

	NSUInteger end_row = 21;
	if (getHud() != nullptr && getHud()->getAllowBigGui())
	{
		end_row = 27;
	}

	// The keys, case-insensitively sorted (a Dict's keys are strings; the bridge form logs and
	// describes any non-string key). The sort is stable over byte order, where the unstable sort
	// started from hash order.
	std::vector<std::string> choiceKeys;
	if (const oo::PList::Dict *choices = choicesDict.getIf<oo::PList::Dict>())
	{
		for (const auto &[key, value] : *choices)  choiceKeys.push_back(key);
	}
	std::stable_sort(choiceKeys.begin(), choiceKeys.end(), [](const std::string &a, const std::string &b) { return oo::str::caseInsensitiveCompare(a, b) < 0; });

	NSInteger keysCount = choiceKeys.size();
	if ((end_row + 1) < choiceKeys.size()) {
		OO_LOG_ERR(cxx_kOOLogException, "in mission.runScreen choices: number of choices defined ({}) is greater than available lines ({}). Check HUD settings for allowBigGui.", choiceKeys.size(), (end_row + 1));
		keysCount = end_row + 1;
	}

	gui->setText(std::string(), end_row);				// clears out the 'Press spacebar' message
	gui->setKey(std::string(), end_row);					// clears the key to enable pollDemoControls to check for a selection
	gui->setSelectableRange(NSMakeRange(0,0));	// clears the selectable range
	if (UNIVERSE != nullptr)  UNIVERSE->enterGUIViewModeWithMouseInteraction(YES); // enables mouse selection of the choices list items

	OOGUIRow			choicesRow = (end_row+1) - keysCount;
	std::string			choiceText;

	BOOL selectableRowExists = NO;
	NSUInteger firstSelectableRow = end_row;

	for (const std::string &choiceKey : choiceKeys)
	{
		const oo::PList &choiceValue = *choicesDict.find(choiceKey);
		OOGUIAlignment alignment = GUI_ALIGN_CENTER;
		oo::Ref<OOColor>	rowColor = OOColor::yellowColor();
		BOOL selectable = YES;
		if (const std::string *text = choiceValue.getIf<std::string>())
		{
			choiceText = " " + *text + " ";
		}
		else if (choiceValue.isDict())
		{
			// "%@" of -oo_stringForKey:@"text": a string or a number's text; "(null)" if neither.
			const oo::PList *textValue = choiceValue.find("text");
			const bool hasText = textValue != nullptr && (textValue->isString() || textValue->isNumber());
			choiceText = " " + (hasText ? choiceValue.get<std::string>("text") : std::string("(null)")) + " ";
			const std::string alignmentChoice = choiceValue.get<std::string>("alignment", "CENTER");
			if (alignmentChoice == "LEFT")
			{
				alignment = GUI_ALIGN_LEFT;
			}
			else if (alignmentChoice == "RIGHT")
			{
				alignment = GUI_ALIGN_RIGHT;
			}
			const oo::PList *colorDesc = choiceValue.find("color");
			if (choiceValue.get<bool>("unselectable"))
			{
				selectable = NO;
			}
			if (colorDesc != nullptr)
			{
				rowColor = OOColor::colorWithDescription(*colorDesc);
			}
			else if (!selectable) // different default
			{
				rowColor = OOColor::darkGrayColor();
			}
		}
		else
		{
			continue; // invalid type
		}
		choiceText = cxx_OOExpand(choiceText).value_or(std::string());
		choiceText = replaceVariablesInString(choiceText).value_or(std::string());
		// allow blank rows
		if (choiceText != "  ")
		{
			gui->setText(choiceText, choicesRow, alignment);
			if (selectable)
			{
				gui->setKey(choiceKey, choicesRow);
			}
			else
			{
				gui->setKey(std::string(GUI_KEY_SKIP), choicesRow);
			}
			gui->setColor(rowColor.get(), choicesRow);
			if (selectable && !selectableRowExists)
			{
				selectableRowExists = YES;
				firstSelectableRow = choicesRow;
			}
		}
		else
		{
			gui->setKey(std::string(GUI_KEY_SKIP), choicesRow);
		}
		choicesRow++;
		if (static_cast<NSUInteger>(choicesRow) > (end_row + 1)) break;
	}

	if (!selectableRowExists)
	{
		// just in case choices are set but they're all blank.
		gui->setText(std::optional<std::string>(" "), end_row, GUI_ALIGN_CENTER);
		gui->setKey(std::string(), end_row);
		gui->setColor(OOColor::yellowColor().get(), end_row);
	}

	gui->setSelectableRange(NSMakeRange((end_row+1) - keysCount, keysCount));
	gui->setSelectedRow(firstSelectableRow);

	resetMissionChoice();
}


void PlayerEntity::resetMissionChoice()
{
	setMissionChoice(std::nullopt);
}


void PlayerEntity::clearMissionScreen()
{
	setMissionOverlayDescriptor(oo::PList());
	setMissionBackgroundDescriptor(oo::PList());
	setMissionBackgroundSpecial("");
	setMissionTitle(std::nullopt);
	setMissionMusic(std::string());	// (nil was "none")
	showShipModel(std::string());
}


void PlayerEntity::addMissionDestination(const std::string &destinations)	// called by name (ADR-0043 item 21)
{
	for (const std::string &token : oo::str::tokens(destinations))
	{
		const int dest = oo::str::intValue(token);	// -oo_intAtIndex: of the token
		if (dest < 0 || dest > 255)
			continue;

		addMissionDestinationMarker(defaultMarker(dest));
	}
}


void PlayerEntity::removeMissionDestination(const std::string &destinations)	// called by name (ADR-0043 item 21)
{
	for (const std::string &token : oo::str::tokens(destinations))
	{
		const int dest = oo::str::intValue(token);
		if (dest < 0 || dest > 255)  continue;

		removeMissionDestinationMarker(defaultMarker(dest));
	}
}


void PlayerEntity::showShipModel(const std::string &role)	// called by name (ADR-0043 item 21)
{
	const std::string roleString = role;
	if (roleString == "none" || roleString.empty())
	{
		if (UNIVERSE != nullptr)  UNIVERSE->removeDemoShips();
		return;
	}

	::ShipEntity *ship = (UNIVERSE != nullptr ? UNIVERSE->makeDemoShipWithRole(roleString, YES) : (::ShipEntity *)nil);
	OO_LOG(kOOLogNoteShowShipModel, "::::: showShipModel:'{}' ({}) ({})", roleString, oo::EntityDescription(ship), (ship != nullptr ? ship->getName() : std::optional<std::string>()).value_or("(null)"));
}


void PlayerEntity::setMissionMusic(const std::string &value)	// called by name (ADR-0043 item 21)
{
	// "" (was nil) and "none" clear it
	OOMusicController::sharedController()->setMissionMusic(IsNoneValue(value) ? std::nullopt : std::optional<std::string>(value));
}


std::optional<std::string> PlayerEntity::missionTitle()
{
	return _missionTitle;
}


void PlayerEntity::setMissionTitle(const std::optional<std::string> &value)
{
	// (nil matters: the mission screen then falls back to DESC(mission-information))
	_missionTitle = value;
}


// Not declared in the header; called by name (setMissionImage: is whitelisted) (ADR-0043 item 21).
void PlayerEntity::setMissionImage(const std::string &value)
{
	const std::string imageName = value;
	if (!IsNoneValue(imageName))
 	{
		setMissionOverlayDescriptor(oo::PList(oo::PList::Dict{ { "name", oo::PList(imageName) } }));
	}
	else
	{
		setMissionOverlayDescriptor(oo::PList());
	}

}


// called by name (ADR-0043 item 21)
void PlayerEntity::setMissionBackground(const std::string &value)
{
	const std::string backgroundName = value;
	if (!IsNoneValue(backgroundName))
 	{
		setMissionBackgroundDescriptor(oo::PList(oo::PList::Dict{ { "name", oo::PList(backgroundName) } }));
	}
	else
	{
		setMissionBackgroundDescriptor(oo::PList());
	}
}


void PlayerEntity::setFuelLeak(const std::string &value)	// called by name (ADR-0043 item 21)
{
	if (::scriptTarget != this)
	{
		if (::scriptTarget != nullptr)  ::scriptTarget->setFuel(0);
		return;
	}
	
	fuel_leak_rate = oo::str::doubleValue(value);
	if (fuel_leak_rate > 0)
	{
		playFuelLeak();
		if (UNIVERSE != nullptr)  UNIVERSE->addMessage(OO_DESC("danger-fuel-leak"), 6);
		OO_LOG(kOOLogNoteFuelLeak, "{}", "FUEL LEAK activated!");
	}
}


oo::PList PlayerEntity::fuelLeakRate_number()	// called by name (ADR-0043 item 21)
{
	return oo::PList::singleReal((float)(fuelLeakRate()));
}


void PlayerEntity::setSunNovaIn(const std::string &time_value)	// called by name (ADR-0043 item 21)
{
	double time_until_nova = oo::str::doubleValue(time_value);
	if ((UNIVERSE != nullptr ? UNIVERSE->sun() : nullptr) != nullptr)  UNIVERSE->sun()->setGoingNova(YES, time_until_nova);
}


void PlayerEntity::launchFromStation()
{
	// ensure autosave is ready for the next unscripted launch
	if ((UNIVERSE != nullptr ? UNIVERSE->getAutoSave() : false)) { if (UNIVERSE != nullptr)  UNIVERSE->setAutoSaveNow(YES); }
	if (status() == STATUS_DOCKING)  setStatus(STATUS_DOCKED); // needed here to prevent the normal update from continuing with docking.
	leaveDock(dockedStation());
}


void PlayerEntity::blowUpStation()
{
	::StationEntity		*mainStation = nil;
	
	mainStation = (UNIVERSE != nullptr ? UNIVERSE->station() : nullptr);
	if (mainStation != nil)
	{
		if (UNIVERSE != nullptr)  UNIVERSE->unMagicMainStation();
		if (mainStation != nullptr)  mainStation->takeEnergyDamage(500000000.0, nullptr, nullptr, std::string());	// 500 million should do it!
	}
}


void PlayerEntity::sendAllShipsAway()
{
	if (!UNIVERSE)
		return;
	int			ent_count =		UNIVERSE->n_entities;
	Entity**	uni_entities =	UNIVERSE->sortedEntities;	// grab the public sorted list
	std::vector<Entity *>	my_entities(ent_count);
	int i;
	for (i = 0; i < ent_count; i++)
		my_entities[i] = oo::RetainEntity(uni_entities[i]);		//	retained (its object; bead oo-9ht.39.18)

	for (i = 1; i < ent_count; i++)
	{
		Entity* e1 = my_entities[i];
		if (oo::EntityIsShip(e1))
		{
			::ShipEntity* se1 = oo::ToShip(e1);
			int e_class = e1->getScanClass();	// virtual: an Objective-C entity is still messaged
			if (((e_class == CLASS_NEUTRAL)||(e_class == CLASS_POLICE)||(e_class == CLASS_MILITARY)||(e_class == CLASS_THARGOID)) &&
											! ((se1 != nullptr ? se1->getIsStation() : false) && (se1 != nullptr ? se1->getMaxFlightSpeed() : 0.0f) == 0) &&  // exclude only stations, not carriers.
											(se1 != nullptr ? se1->hasHyperspaceMotor() : false)) // exclude non jumping ships. Escorts will still be able to follow a mother.
			{
				::AI*	se1AI = (se1 != nullptr ? se1->getAI() : (::AI *)nullptr);
				if (se1 != nullptr)  se1->setFuel(MAX(PLAYER_MAX_FUEL, (se1 != nullptr ? se1->fuelCapacity() : OOFuelQuantity{})));
				if (se1 != nullptr)  se1->setAITo("exitingTraderAI.plist");	// lets them return to their previous state after the jump
				if (se1AI != nullptr)  se1AI->setState("EXIT_SYSTEM");
				// The following should prevent all ships leaving at once (freezes oolite on slower machines)
				if (se1AI != nullptr)  se1AI->setNextThinkTime((UNIVERSE != nullptr ? UNIVERSE->getTime() : 0.0) + 3 + (ranrot_rand() & 15));
				if (se1 != nullptr)  se1->setPrimaryRole("oolite-none");	// prevents new ship from appearing at witchpoint when this one leaves!
			}
		}
	}
	
	for (i = 0; i < ent_count; i++)
	{
		oo::ReleaseEntity(my_entities[i]);		//	released
	}
}


void PlayerEntity::addPlanet(const std::string &planetKey)	// called by name (ADR-0043 item 21)
{
	addPlanetEntity(planetKey);
}


::OOPlanetEntity *PlayerEntity::addPlanetEntity(const std::string &planetKey)
{
	OO_LOG(kOOLogNoteAddPlanet, "addPlanet: {}", planetKey);

	if (!UNIVERSE)
		return nil;
	// The system properties, once, as an oo::PList (null when there are none).
	const oo::PList dict = ((UNIVERSE != nullptr ? UNIVERSE->getSystemManager() : nullptr) != nullptr ? UNIVERSE->getSystemManager()->getPropertiesForSystemKey(planetKey) : oo::PList());
	if (dict.isNull())
	{
		OO_LOG("script.error.addPlanet.keyNotFound", "***** ERROR: could not find an entry in planetinfo.plist for '{}'", planetKey);
		return nil;
	}

	/*- add planet -*/
	// ("%@" of the dictionary: the round trip prints the same description)
	OO_LOG(kOOLogDebugAddPlanet, "DEBUG: initPlanetFromDictionary: {}", oo::DescriptionOf(dict));
	::OOPlanetEntity *planet = nullptr;
	{
		// [[[OOPlanetEntity alloc] initFromDictionary:...] autorelease]: a new C++ planet, kept by its
		// autoreleased Objective-C object (the facade went with bead oo-9ht.129).
		oo::Ref<::OOPlanetEntity> planetRef = oo::makeRef<::OOPlanetEntity>();
		oo::MadeEntity(planetRef);
		planetRef->initFromDictionary(dict, true, ((UNIVERSE != nullptr ? UNIVERSE->getSystemManager() : nullptr) != nullptr ? UNIVERSE->getSystemManager()->getRandomSeedForCurrentSystem() : Random_Seed()), system_id);
		planet = planetRef.get();
	}

	Quaternion planetOrientation;
	const oo::PList *orientationValue = dict.find("orientation");
	if (cxx_ScanQuaternionFromString((orientationValue != nullptr && orientationValue->isString()) ? std::optional<std::string>(*orientationValue->getIf<std::string>()) : std::nullopt, &planetOrientation))
	{
		if (planet != nullptr)  planet->setOrientation(planetOrientation);
	}

	const oo::PList *positionValue = dict.find("position");
	if (positionValue == nullptr)
	{
		OO_LOG("script.error.addPlanet.noPosition", "***** ERROR: you must specify a position for scripted planet '{}' before it can be created", planetKey);
		return nil;
	}

	const std::string positionString = ConditionString(*positionValue).value_or(std::string());
	if(oo::str::hasPrefix(positionString, "abs ") && ((UNIVERSE != nullptr ? UNIVERSE->planet() : nullptr) != nil || (UNIVERSE != nullptr ? UNIVERSE->sun() : nullptr) !=nil))
	{
		OO_LOG_WARN("script.deprecated", "setting {} for {} '{}' in 'abs' inside .plists can cause compatibility issues across Oolite versions. Use coordinates relative to main system objects instead.","position","planet",planetKey);
	}

	HPVector posn = (UNIVERSE != nullptr ? UNIVERSE->coordinatesFromCoordinateSystemString(positionString) : HPVector{});
	if (posn.x || posn.y || posn.z)
	{
		OO_LOG(kOOLogDebugAddPlanet, "planet position ({:.2f} {:.2f} {:.2f}) derived from {}", posn.x, posn.y, posn.z, positionString);
	}
	else
	{
		cxx_ScanHPVectorFromString(positionString, &posn);
		OO_LOG(kOOLogDebugAddPlanet, "planet position ({:.2f} {:.2f} {:.2f}) derived from {}", posn.x, posn.y, posn.z, positionString);
	}
	if (planet != nullptr)  planet->setPosition(posn);

	if (UNIVERSE != nullptr)  UNIVERSE->addEntity(planet);
	return planet;
}


void PlayerEntity::addMoon(const std::string &moonKey)	// called by name (ADR-0043 item 21)
{
	addMoonEntity(moonKey);
}


::OOPlanetEntity *PlayerEntity::addMoonEntity(const std::string &moonKey)
{
	OO_LOG(kOOLogNoteAddPlanet, "DEBUG: addMoon '{}'", moonKey);

	if (!UNIVERSE)
		return nil;
	// The system properties, once, as an oo::PList (null when there are none).
	const oo::PList dict = ((UNIVERSE != nullptr ? UNIVERSE->getSystemManager() : nullptr) != nullptr ? UNIVERSE->getSystemManager()->getPropertiesForSystemKey(moonKey) : oo::PList());
	if (dict.isNull())
	{
		OO_LOG("script.error.addPlanet.keyNotFound", "***** ERROR: could not find an entry in planetinfo.plist for '{}'", moonKey);
		return nil;
	}

	/*- add planet -*/
	// ("%@" of the dictionary: the round trip prints the same description)
	OO_LOG(kOOLogDebugAddPlanet, "DEBUG: initMoonFromDictionary: {}", oo::DescriptionOf(dict));
	::OOPlanetEntity *planet = nullptr;
	{
		// [[[OOPlanetEntity alloc] initFromDictionary:...] autorelease]: a new C++ planet, kept by its
		// autoreleased Objective-C object (the facade went with bead oo-9ht.129).
		oo::Ref<::OOPlanetEntity> planetRef = oo::makeRef<::OOPlanetEntity>();
		oo::MadeEntity(planetRef);
		planetRef->initFromDictionary(dict, false, ((UNIVERSE != nullptr ? UNIVERSE->getSystemManager() : nullptr) != nullptr ? UNIVERSE->getSystemManager()->getRandomSeedForCurrentSystem() : Random_Seed()), system_id);
		planet = planetRef.get();
	}

	Quaternion planetOrientation;
	const oo::PList *orientationValue = dict.find("orientation");
	if (cxx_ScanQuaternionFromString((orientationValue != nullptr && orientationValue->isString()) ? std::optional<std::string>(*orientationValue->getIf<std::string>()) : std::nullopt, &planetOrientation))
	{
		if (planet != nullptr)  planet->setOrientation(planetOrientation);
	}

	const oo::PList *positionValue = dict.find("position");
	if (positionValue == nullptr)
	{
		OO_LOG("script.error.addPlanet.noPosition", "***** ERROR: you must specify a position for scripted moon '{}' before it can be created", moonKey);
		return nil;
	}

	const std::string positionString = ConditionString(*positionValue).value_or(std::string());
	if(oo::str::hasPrefix(positionString, "abs ") && ((UNIVERSE != nullptr ? UNIVERSE->planet() : nullptr) != nil || (UNIVERSE != nullptr ? UNIVERSE->sun() : nullptr) !=nil))
	{
		OO_LOG_WARN("script.deprecated", "setting {} for {} '{}' in 'abs' inside .plists can cause compatibility issues across Oolite versions. Use coordinates relative to main system objects instead.","position","moon",moonKey);
	}

	HPVector posn = (UNIVERSE != nullptr ? UNIVERSE->coordinatesFromCoordinateSystemString(positionString) : HPVector{});
	if (posn.x || posn.y || posn.z)
	{
		OO_LOG(kOOLogDebugAddPlanet, "moon position ({:.2f} {:.2f} {:.2f}) derived from {}", posn.x, posn.y, posn.z, positionString);
	}
	else
	{
		cxx_ScanHPVectorFromString(positionString, &posn);
		OO_LOG(kOOLogDebugAddPlanet, "moon position ({:.2f} {:.2f} {:.2f}) derived from {}", posn.x, posn.y, posn.z, positionString);
	}
	if (planet != nullptr)  planet->setPosition(posn);

	if (UNIVERSE != nullptr)  UNIVERSE->addEntity(planet);
	return planet;
}


void PlayerEntity::debugOn()
{
	oo::log::logger().setDisplay(kOOLogDebugOnMetaClass, true);
	OO_LOG(kOOLogDebugOnOff, "{}", "SCRIPT debug messages ON");
}


void PlayerEntity::debugOff()
{
	OO_LOG(kOOLogDebugOnOff, "{}", "SCRIPT debug messages OFF");
	oo::log::logger().setDisplay(kOOLogDebugOnMetaClass, false);
}


void PlayerEntity::debugMessage(const std::string &args)	// called by name (ADR-0043 item 21)
{
	OO_LOG(kOOLogDebugMessage, "SCRIPT debugMessage: {}", args);
}


void PlayerEntity::playSound(const std::string &soundName)	// called by name (ADR-0043 item 21)
{
	playLegacyScriptSound(soundName);
}

/*-----------------------------------------------------*/


void PlayerEntity::doMissionCallback()
{
	// make sure we don't call the same callback twice
	_missionWithCallback = NO;
	OOJavaScriptEngine::sharedEngine()->runMissionCallback();
}


void PlayerEntity::clearMissionScreenID()
{
	_missionScreenID.reset();
}


void PlayerEntity::setMissionScreenID(const std::optional<std::string> &msid)
{
	_missionScreenID = msid;
}


std::optional<std::string> PlayerEntity::missionScreenID()
{
	return _missionScreenID;
}


void PlayerEntity::endMissionScreenAndNoteOpportunity()
{
	_missionAllowInterrupt = NO;
	clearMissionScreenID();
	// Older scripts might intercept missionScreenEnded first, and call secondary mission screens.
	const ooscript::PropertyId missionScreenEnded = OOJSID("missionScreenEnded");
	if(!doWorldEventUntilMissionScreen(missionScreenEnded))
	{
		// if we're here, no mission screen is running. Opportunity! :)
		doWorldEventUntilMissionScreen(OOJSID("missionScreenOpportunity"));
	}
}


void PlayerEntity::setGuiToMissionScreen()
{
	// reset special background as legacy scripts can't use it, and this
	// is only called by legacy scripts
	setMissionBackgroundSpecial("");
	// likewise exit screen target
	setMissionExitScreen(GUI_SCREEN_STATUS);

	setGuiToMissionScreenWithCallback(NO);
}


void PlayerEntity::refreshMissionScreenTextEntry()
{
	::MyOpenGLView	*gameView = (UNIVERSE != nullptr ? UNIVERSE->getGameView() : nullptr);
	::GuiDisplayGen	*gui = (UNIVERSE != nullptr ? UNIVERSE->getGui() : nullptr);
	NSUInteger end_row = 21;
	if (getHud() != nullptr && getHud()->getAllowBigGui()) 
	{
		end_row = 27;
	}

	// The DESC entry is the format (data): ADR-0043 item 19.
	const std::optional<std::string> typed = (gameView != nullptr ? gameView->getTypedString() : std::optional<std::string>());
	gui->setText(oo::str::formatRuntime(OO_DESC("mission-screen-text-prompt-@"), { typed.has_value() ? oo::str::FormatArg(*typed) : oo::str::FormatArg::null() }), end_row, GUI_ALIGN_LEFT);
	gui->setColor(OOColor::cyanColor().get(), end_row);
	
	gui->setShowTextCursor(YES);
	gui->setCurrentRow(end_row);

}


void PlayerEntity::setGuiToMissionScreenWithCallback(bool callback)
{
	::GuiDisplayGen	*gui = (UNIVERSE != nullptr ? UNIVERSE->getGui() : nullptr);
	OOGUIScreenID	oldScreen = gui_screen;
	NSUInteger end_row = 21;
	if (getHud() != nullptr && getHud()->getAllowBigGui()) 
	{
		end_row = 27;
	}

	// GUI stuff
	{
		gui->clear();
		gui->setTitle(missionTitle().value_or(OO_DESC("mission-information")));

		if (!_missionTextEntry)
		{
			gui->setText(OO_DESC("press-space-commander"), end_row, GUI_ALIGN_CENTER);
			gui->setColor(OOColor::yellowColor().get(), end_row);
			gui->setKey("spacebar", end_row);
			gui->setShowTextCursor(NO);
		}
		else
		{
			refreshMissionScreenTextEntry();
		}
		gui->setSelectableRange(NSMakeRange(0,0));
		
		gui->setForegroundTextureDescriptor(missionOverlayDescriptorOrDefault());
		gui->setBackgroundTextureDescriptor(missionBackgroundDescriptorOrDefault());
		// must set special second as setting the descriptor resets it
		BOOL overridden = missionBackgroundDescriptor() ? YES : NO;
		gui->setBackgroundTextureSpecial(missionBackgroundSpecial(), !overridden);
		

	}
	/* ends */

	missionTextRow = 1;

	
	if (gui)
		gui_screen = GUI_SCREEN_MISSION;

	lastTextKey.reset();
	
	OOMusicController::sharedController()->playMissionMusic();
	
	// the following are necessary...
	if (UNIVERSE != nullptr)  UNIVERSE->enterGUIViewModeWithMouseInteraction(NO);
	_missionWithCallback = callback;
	_missionAllowInterrupt = NO;
	noteGUIDidChangeFrom(oldScreen, gui_screen);

}


void PlayerEntity::setBackgroundFromDescriptionsKey(const std::string &d_key)
{
	const oo::PList *itemsEntry = UNIVERSE->descriptions()->find(d_key);
	const oo::PList items = (itemsEntry != nullptr) ? *itemsEntry : oo::PList();
	//
	if (items.isNull())
		return;
	//
	addScene(items, kZeroVector);
	//
	setShowDemoShips(YES);
}


void PlayerEntity::addScene(const oo::PList &items, Vector off)
{
	const oo::PList::Array *itemArray = items.getIf<oo::PList::Array>();
	if (itemArray == nullptr)  return;

	for (const oo::PList &item : *itemArray)
	{
		if (const std::string *itemString = item.getIf<std::string>())
		{
			processSceneString(*itemString, off);
		}
		else if (item.isArray())
		{
			addScene(item, off);
		}
		else if (item.isDict())
		{
			processSceneDictionary(item, off);
		}
	}
}


bool PlayerEntity::processSceneDictionary(const oo::PList &couplet, Vector off)
{
	const oo::PList *conditions = couplet.find("conditions");
	oo::PList actions;
	if (const oo::PList *doActions = couplet.find("do"))
		actions = oo::PList(oo::PList::Array{ *doActions });
	oo::PList else_actions;
	if (const oo::PList *elseActions = couplet.find("else"))
		else_actions = oo::PList(oo::PList::Array{ *elseActions });
	BOOL success = YES;
	// ("%@" of the dictionaries: their round-tripped descriptions, the same text)
	if (conditions == nullptr)
	{
		OO_LOG("script.scene.couplet.badConditions", "***** SCENE ERROR: {} - conditions not {}, returning {}.", oo::DescriptionOf(couplet), " found","YES and performing 'do' actions");
	}
	else
	{
		if (!conditions->isArray())
		{
			OO_LOG("script.scene.couplet.badConditions", "***** SCENE ERROR: {} - conditions not {}, returning {}.", oo::DescriptionOf(*conditions), "an array","NO");
			return NO;
		}
	}

	// check conditions..
	success = TestScriptConditions(OOSanitizeLegacyScriptConditions(conditions != nullptr ? *conditions : oo::PList(), "<scene dictionary conditions>"));

	// perform successful actions...
	if ((success) && actions.count())
		addScene(actions, off);

	// perform unsuccessful actions
	if ((!success) && else_actions.count())
		addScene(else_actions, off);

	return success;
}


bool PlayerEntity::processSceneString(const std::string &item, Vector off)
{
	Vector	model_p0;
	Quaternion	model_q;

	const std::vector<std::string> i_info = oo::str::tokens(item);
	if (i_info.empty())
		return NO;	// (nil returned NO; an all-blank string raised on -objectAtIndex:0)
	const std::string i_key = oo::str::lowercase(i_info[0]);

	// ("%@" of the token array: the same description)
	OO_LOG(kOOLogNoteProcessSceneString, "..... processing {} ({})", oo::DescriptionOf(TokenArray(i_info)), i_key);

	// tokens [from, from + count) joined by " ", as -subarrayWithRange: then -componentsJoinedByString:@" "
	auto joined = [&i_info](std::size_t from, std::size_t count)
	{
		std::string result;
		for (std::size_t i = from; i < from + count; i++)
		{
			if (i != from)  result += " ";
			result += i_info[i];
		}
		return result;
	};

	//
	// recursively add further scenes:
	//
	if (i_key == "scene")
	{
		if (i_info.size() != 5)	// must be scene_key_x_y_z
			return NO;				//		   0.... 1.. 2 3 4
		const std::string &scene_key = i_info[1];
		Vector	scene_offset = {};
		cxx_ScanVectorFromString(joined(2, 3), &scene_offset);
		scene_offset.x += off.x;	scene_offset.y += off.y;	scene_offset.z += off.z;
		const oo::PList *sceneEntry = UNIVERSE->descriptions()->find(scene_key);
		const oo::PList scene_items = (sceneEntry != nullptr) ? *sceneEntry : oo::PList();
		OO_LOG(kOOLogDebugProcessSceneStringAddScene, "::::: adding scene: '{}'", scene_key);
		//
		if (!scene_items.isNull())
		{
			addScene(scene_items, scene_offset);
			return YES;
		}
		else
			return NO;
	}
	//
	// Add ship models:
	//
	if (i_key == "ship" || i_key == "model" || i_key == "role")
	{
		if (i_info.size() != 10)	// must be item_name_x_y_z_W_X_Y_Z_align
		{
			return NO;				//		   0... 1... 2 3 4 5 6 7 8 9....
		}

		::ShipEntity* ship = nil;

		if (i_key == "ship" || i_key == "model")
		{
			ship = (UNIVERSE != nullptr ? UNIVERSE->newShipWithName(i_info[1]) : (::ShipEntity *)nil);
		}
		else if (i_key == "role")
		{
			ship = (UNIVERSE != nullptr ? UNIVERSE->newShipWithRole(i_info[1]) : (::ShipEntity *)nil);
		}
		if (!ship)
			return NO;

		cxx_ScanVectorAndQuaternionFromString(joined(2, 7), &model_p0, &model_q);

		Vector	model_offset = cxx_positionOffsetForShipInRotationToAlignment(ship, model_q, i_info[9]);
		model_p0 = vector_add(model_p0, vector_subtract(off, model_offset));

		OO_LOG(kOOLogDebugProcessSceneStringAddModel, "::::: adding model to scene:'{}'", oo::EntityDescription(ship));
		if (ship != nullptr)  ship->setOrientation(model_q);
		if (ship != nullptr)  ship->setPosition(vectorToHPVector(model_p0));
		if (UNIVERSE != nullptr)  UNIVERSE->setMainLightPosition((Vector){ DEMO_LIGHT_POSITION }); // set light origin
		if (ship != nullptr)  ship->setScanClass(CLASS_NO_DRAW);
		if (ship != nullptr)  ship->switchAITo("nullAI.plist");
		if (UNIVERSE != nullptr)  UNIVERSE->addEntity(ship);	// STATUS_IN_FLIGHT, AI state GLOBAL
		if (ship != nullptr)  ship->setStatus(STATUS_COCKPIT_DISPLAY);
		if (ship != nullptr)  ship->setRoll(0.0);
		if (ship != nullptr)  ship->setPitch(0.0);
		if (ship != nullptr)  ship->setVelocity(kZeroVector);
		if (ship != nullptr)  ship->setBehaviour(BEHAVIOUR_STOP_STILL);

		if (ship != nullptr)  oo::ReleaseEntity(ship);
		return YES;
	}
	//
	// Add player ship model:
	//
	if (i_key == "player")
	{
		if (i_info.size() != 9)	// must be player_x_y_z_W_X_Y_Z_align
			return NO;				//		   0..... 1 2 3 4 5 6 7 8....

		::ShipEntity* doppelganger = (UNIVERSE != nullptr ? UNIVERSE->newShipWithName(shipDataKey().value_or(std::string())) : (::ShipEntity *)nil);   // retain count = 1
		if (!doppelganger)
			return NO;

		cxx_ScanVectorAndQuaternionFromString(joined(1, 7), &model_p0, &model_q);

		Vector	model_offset = cxx_positionOffsetForShipInRotationToAlignment( doppelganger, model_q, i_info[8]);
		model_p0.x += off.x - model_offset.x;
		model_p0.y += off.y - model_offset.y;
		model_p0.z += off.z - model_offset.z;

		OO_LOG(kOOLogDebugProcessSceneStringAddModel, "::::: adding model to scene:'{}'", oo::EntityDescription(doppelganger));
		if (doppelganger != nullptr)  doppelganger->setOrientation(model_q);
		if (doppelganger != nullptr)  doppelganger->setPosition(vectorToHPVector(model_p0));
		if (UNIVERSE != nullptr)  UNIVERSE->setMainLightPosition((Vector){ DEMO_LIGHT_POSITION }); // set light origin
		if (doppelganger != nullptr)  doppelganger->setScanClass(CLASS_NO_DRAW);
		if (doppelganger != nullptr)  doppelganger->switchAITo("nullAI.plist");
		if (UNIVERSE != nullptr)  UNIVERSE->addEntity(doppelganger);
		if (doppelganger != nullptr)  doppelganger->setStatus(STATUS_COCKPIT_DISPLAY);
		if (doppelganger != nullptr)  doppelganger->setRoll(0.0);
		if (doppelganger != nullptr)  doppelganger->setPitch(0.0);
		if (doppelganger != nullptr)  doppelganger->setVelocity(kZeroVector);
		if (doppelganger != nullptr)  doppelganger->setBehaviour(BEHAVIOUR_STOP_STILL);

		if (doppelganger != nullptr)  oo::ReleaseEntity(doppelganger);
		return YES;
	}
	//
	// Add  planet model: selected via gui-scene-show-planet/-local-planet
	//
	if (i_key == "local-planet" || i_key == "target-planet")
	{
		if (i_info.size() != 4)	// must be xxxxx-planet_x_y_z
			return NO;				//		   0........... 1 2 3

		// sunlight position for F7 screen is chosen pseudo randomly from  4 different positions.
		if (info_system_id & 8)
		{
			_sysInfoLight = (info_system_id & 2) ? (Vector){ -10000.0, 4000.0, -10000.0 } : (Vector){ -12000.0, -5000.0, -10000.0 };
		}
		else
		{
			_sysInfoLight = (info_system_id & 2) ? (Vector){ 6000.0, -5000.0, -10000.0 } : (Vector){ 6000.0, 4000.0, -10000.0 };
		}

		if (UNIVERSE != nullptr)  UNIVERSE->setMainLightPosition(_sysInfoLight); // set light origin

		::OOPlanetEntity *originalPlanet = nil;
		if (i_key == "local-planet" && (UNIVERSE != nullptr && UNIVERSE->sun() != nullptr))
		{
			originalPlanet = (UNIVERSE != nullptr ? UNIVERSE->planet() : nullptr);
		}
		else
		{
			// [[[OOPlanetEntity alloc] initAsMainPlanetForSystem:] autorelease]: a new C++ planet, kept by
			// its autoreleased Objective-C object (the facade went with bead oo-9ht.129).
			oo::Ref<::OOPlanetEntity> planetRef = oo::makeRef<::OOPlanetEntity>();
			oo::MadeEntity(planetRef);
			planetRef->initAsMainPlanetForSystem(info_system_id);
			originalPlanet = planetRef.get();
		}
		// -miniatureVersion: a new C++ planet and its autoreleased Objective-C object; nil for nil.
		::OOPlanetEntity *doppelganger = nullptr;
		if (originalPlanet != nullptr)
		{
			oo::Ref<::OOPlanetEntity> miniature = originalPlanet->miniatureVersion();
			oo::MadeEntity(miniature);
			doppelganger = miniature.get();
		}
		if (doppelganger == nil)  return NO;


		cxx_ScanVectorFromString(joined(1, 3), &model_p0);

		// miniature radii are roughly between 60 and 120. Place miniatures with a radius bigger than 60 a bit futher away.
		model_p0 = vector_multiply_scalar(model_p0, 1 - 0.5 * ((60 - (doppelganger != nullptr ? doppelganger->radius() : 0.0)) / 60));

		model_p0 = vector_add(model_p0, off);

		// TODO: find better quaternion values.
		//Quaternion model_q = { 0.83, 0.365148, 0.182574, 0.0 }; // shows new planets' north pole.
		//Quaternion model_q = { 0.83, -0.365148, 0.182574, 0.0 }; // shows new planets' south pole.
		Quaternion model_q = { 0.83, 0.12, 0.44, 0.0 };	// new planets - default orientation.
		OO_LOG(kOOLogDebugProcessSceneStringAddMiniPlanet, "::::: adding {} to scene:'{}'", i_key, oo::EntityDescription(doppelganger));
		if (doppelganger != nullptr)  doppelganger->setOrientation(model_q);
		// HPVect: mission screen coordinates are small enough that we don't need high-precision for calculations
		if (doppelganger != nullptr)  doppelganger->setPosition(vectorToHPVector(model_p0));
		/* MKW - add rotation based on current time
		 *     - necessary to duplicate the rotation already performed in PlanetEntity.m since we reset the orientation above. */
		int		deltaT = floor(fmod(clockTimeAdjusted(), 86400));
		if (doppelganger != nullptr)  doppelganger->update(deltaT);
		if (UNIVERSE != nullptr)  UNIVERSE->addEntity(doppelganger);

		return YES;
	}

	return NO;
}


bool PlayerEntity::addEqScriptForKey(const std::string &eq_key)
{
	const std::optional<std::string> scriptName = (OOEquipmentType::equipmentTypeWithIdentifier(eq_key).get() != nullptr ? OOEquipmentType::equipmentTypeWithIdentifier(eq_key).get()->scriptName() : std::optional<std::string>());

	OO_LOG("player.equipmentScript", "Added equipment {}, with the following script property: '{}'.", eq_key, scriptName.value_or("(null)"));

	if (!scriptName.has_value()) return NO;

	// no duplicates! (eqScripts holds (key, script) pairs)
	if (eqScriptIndexForKey(eq_key) != eqScripts.size())  return NO;

	// the script's properties: a mixed configuration (Amendment 2)
	oo::PList::Dict properties;
	properties["ship"] = oo::EntityObjectNode(this);
	properties["equipmentKey"] = oo::PList(eq_key);
	oo::Ref<OOScript> s = OOScript::jsScriptFromFileNamed(*scriptName, oo::PList(std::move(properties)));
	if (s == nullptr) return NO;

	OO_LOG("player.equipmentScript", "Script '{}': installation {}successful.", *scriptName, (s == nullptr ? "un" : ""));

	eqScripts.emplace_back(eq_key, std::move(s));
	if (primedEquipment == eqScripts.size() - 1) primedEquipment++;	// if primed-none, keep it as primed-none.
	OO_LOG("player.equipmentScript", "Scriptable equipment available: {}.", eqScripts.size());
	return YES;
}


void PlayerEntity::removeEqScriptForKey(const std::string &eq_key)
{
	NSUInteger			i, count = eqScripts.size();

	for (i = 0; i < count; i++)
	{
		// (count is not updated after a removal: an index past the end read nil, matching nothing)
		if (i < eqScripts.size() && eqScripts[i].first == eq_key)
		{
			eqScripts.erase(eqScripts.begin() + static_cast<std::ptrdiff_t>(i));

			if (i == primedEquipment)  primedEquipment = count;	// primed-none
			else if (i < primedEquipment)  primedEquipment--; // track the primed equipment
			if (count == primedEquipment)  primedEquipment--; // the array has shrunk by one!

			OO_LOG("player.equipmentScript", "Removed equipment {}, with the following script property: '{}'.", eq_key, (OOEquipmentType::equipmentTypeWithIdentifier(eq_key).get() != nullptr ? OOEquipmentType::equipmentTypeWithIdentifier(eq_key).get()->scriptName() : std::optional<std::string>()).value_or("(null)"));
		}
	}
}


NSUInteger PlayerEntity::eqScriptIndexForKey(const std::string &eq_key)
{
	NSUInteger			i, count = eqScripts.size();

	for (i = 0; i < count; i++)
	{
		if (eqScripts[i].first == eq_key) return i;
	}

	return count;
}


void PlayerEntity::targetNearestHostile()
{
	scanForHostiles();
	Entity *ent = foundTarget();
	if (ent != nullptr)
	{
		ident_engaged = YES;
		missile_status = MISSILE_STATUS_TARGET_LOCKED;
		addTarget(ent);
	}
}


void PlayerEntity::targetNearestIncomingMissile()
{
	scanForNearestIncomingMissile();
	Entity *ent = foundTarget();
	if (ent != nullptr)
	{
		ident_engaged = YES;
		missile_status = MISSILE_STATUS_TARGET_LOCKED;
		addTarget(ent);
	}
}


void PlayerEntity::setGalacticHyperspaceBehaviourTo(const std::string &galacticHyperspaceBehaviourString)	// called by name (ADR-0043 item 21)
{
	OOGalacticHyperspaceBehaviour ghBehaviour = cxx_OOGalacticHyperspaceBehaviourFromString(galacticHyperspaceBehaviourString);
	if (ghBehaviour == GALACTIC_HYPERSPACE_BEHAVIOUR_UNKNOWN)
	{
		OO_LOG("player.setGalacticHyperspaceBehaviour.invalidInput",
			  "setGalacticHyperspaceBehaviourTo: called with unknown behaviour {}.", galacticHyperspaceBehaviourString);
	}
	setGalacticHyperspaceBehaviour(ghBehaviour);
}


void PlayerEntity::setGalacticHyperspaceFixedCoordsTo(const std::string &galacticHyperspaceFixedCoordsString)	// called by name (ADR-0043 item 21)
{
	const oo::PList coord_vals = TokenArray(oo::str::tokens(galacticHyperspaceFixedCoordsString));
	if (coord_vals.count() < 2)	// Will be 0 if string is empty
	{
		OO_LOG("player.setGalacticHyperspaceFixedCoords.invalidInput", "{}",
			  "setGalacticHyperspaceFixedCoords: called with bad specifier. Defaulting to Oolite standard.");
		galacticHyperspaceFixedCoords.x = galacticHyperspaceFixedCoords.y = 0x60;
	}
	
	setGalacticHyperspaceFixedCoordsX(coord_vals.at<unsigned char>(0), coord_vals.at<unsigned char>(1));
}


std::string cxx_OOComparisonTypeToString(OOComparisonType type)
{
	switch (type)
	{
		case COMPARISON_EQUAL:			return "equal";
		case COMPARISON_NOTEQUAL:		return "notequal";
		case COMPARISON_LESSTHAN:		return "lessthan";
		case COMPARISON_GREATERTHAN:	return "greaterthan";
		case COMPARISON_ONEOF:			return "oneof";
		case COMPARISON_UNDEFINED:		return "undefined";
	}
	return "<error: invalid comparison type>";
}
