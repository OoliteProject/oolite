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

#import "PlayerEntityLegacyScriptEngine.h"

#include <vector>
#import "AI.h"
#import "Comparison.h"
#import "GuiDisplayGen.h"
#import "HeadUpDisplay.h"
#import "MyOpenGLView+Input.h"
#import "OOColor.h"
#import "OOConstToString.h"
#import "OOEntityFilterPredicate.h"
#import "OOEquipmentType.h"
#import "OOFoundationBridge.h"
#import "OOFoundationException.h"
#import "OOJavaScriptEngine.h"
#import "OOLegacyScriptWhitelist.h"
#import "OOLoggingExtended.h"
#import "OOMusicController.h"
#import "OOPlanetEntity.h"
#import "OOScript.h"
#import "OOSound.h"
#import "OOStringBridge.h"
#import "OOStringExpander.h"
#import "OOStringParsing.h"
#import "OOSunEntity.h"
#import "OOSystemDescriptionManager.h"
#import "OOTexture.h"
#import "PlayerEntityContracts.h"
#import "PlayerEntityScriptMethods.h"
#import "PlayerEntitySound.h"
#import "ResourceManager.h"
#import "ShipEntityAI.h"
#import "ShipEntityScriptMethods.h"
#import "StationEntity.h"
#import "Universe.h"
#include "oofnd/objc/OORuntime.h"

#include "oofnd/Log.hpp"
#include "oofnd/PList.hpp"
#include "oofnd/PListWriting.hpp"
#include "oofnd/StdLib.hpp"
#include "oofnd/String.hpp"

static const char* const kOOLogScriptAddShipsFailed = "script.addShips.failed";
static const char* const kOOLogScriptMissionDescNoText = "script.missionDescription.noMissionText";
static const char* const kOOLogScriptMissionDescNoKey = "script.missionDescription.noMissionKey";

static const char* const kOOLogDebugOnMetaClass = "$scriptDebugOn";
static const char* const kOOLogDebugMessage = "script.debug.message";
static const char* const kOOLogDebugOnOff = "script.debug.onOff";
static const char* const kOOLogDebugAddPlanet = "script.debug.addPlanet";
static const char* const kOOLogDebugReplaceVariablesInString = "script.debug.replaceVariablesInString";
static const char* const kOOLogDebugProcessSceneStringAddScene = "script.debug.processSceneString.addScene";
static const char* const kOOLogDebugProcessSceneStringAddModel = "script.debug.processSceneString.addModel";
static const char* const kOOLogDebugProcessSceneStringAddMiniPlanet = "script.debug.processSceneString.addMiniPlanet";

static const char* const kOOLogNoteRemoveAllCargo = "script.debug.note.removeAllCargo";
static const char* const kOOLogNoteUseSpecialCargo = "script.debug.note.useSpecialCargo";
static const char* const kOOLogNoteAddShips = "script.debug.note.addShips";
static const char* const kOOLogNoteSet = "script.debug.note.set";
static const char* const kOOLogNoteShowShipModel = "script.debug.note.showShipModel";
static const char* const kOOLogNoteFuelLeak = "script.debug.note.setFuelLeak";
static const char* const kOOLogNoteAddPlanet = "script.debug.note.addPlanet";
static const char* const kOOLogNoteProcessSceneString = "script.debug.note.processSceneString";

static const char* const kOOLogSyntaxSetPlanetInfo = "script.debug.syntax.setPlanetInfo";
static const char* const kOOLogSyntaxAwardCargo = "script.debug.syntax.awardCargo";
static const char* const kOOLogSyntaxAwardEquipment = "script.debug.syntax.awardEquipment";
static const char* const kOOLogSyntaxRemoveEquipment = "script.debug.syntax.removeEquipment";
static const char* const kOOLogSyntaxMessageShipAIs = "script.debug.syntax.messageShipAIs";
static const char* const kOOLogSyntaxAddShips = "script.debug.syntax.addShips";
static const char* const kOOLogSyntaxSet = "script.debug.syntax.set";
static const char* const kOOLogSyntaxReset = "script.debug.syntax.reset";
static const char* const kOOLogSyntaxIncrement = "script.debug.syntax.increment";
static const char* const kOOLogSyntaxDecrement = "script.debug.syntax.decrement";
static const char* const kOOLogSyntaxAdd = "script.debug.syntax.add";
static const char* const kOOLogSyntaxSubtract = "script.debug.syntax.subtract";

static const char* const kOOLogRemoveAllCargoNotDocked = "script.error.removeAllCargo.notDocked";

#define ACTIONS_TEMP_PREFIX "__oolite_actions_temp"
namespace {
constexpr const char* kActionTempPrefix = ACTIONS_TEMP_PREFIX;
} // namespace

namespace {
std::optional<std::string> sMissionStringValue; // the variable a mission/local condition reads (nullopt: unset)
} // namespace
namespace {
std::optional<std::string> sCurrentMissionKey; // nullopt: no current mission (was nil)
} // namespace
static ShipEntity* scriptTarget = nil;

@interface PlayerEntity (ScriptingPrivate)

- (BOOL)scriptTestCondition:(const oo::PList&)scriptCondition;
- (std::optional<std::string>)expandScriptRightHandSide:(const oo::PList&)rhsComponents;

- (std::optional<std::string>)expandMessage:(const std::string&)valueString;

@end

@implementation PlayerEntity (Scripting)

namespace {
std::string CurrentScriptNameOr(const std::string& alternative)
{
    if (sCurrentMissionKey.has_value() && !oo::str::hasPrefix(*sCurrentMissionKey, kActionTempPrefix)) {
        return "\"" + *sCurrentMissionKey + "\"";
    }
    return alternative;
}

std::string CurrentScriptDescription(void)
{
    return CurrentScriptNameOr("<anonymous actions>");
}

// A sanitized statement's element (a null PList for a missing one; sanitized trees always have them).
const oo::PList& ElementAt(const oo::PList& array, std::size_t index)
{
    static const oo::PList sNull;
    const oo::PList* element = array.at(index);
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

// [UNIVERSE missiontext]'s entry as -oo_stringForKey: read it: a string, or a number's text.
std::optional<std::string> MissionTextForKey(const std::string& key)
{
    const oo::PList value = oo::PListFrom([[UNIVERSE missiontext] objectForKey:oo::NSStringFrom(key)]);
    if (const std::string* string = value.getIf<std::string>())
        return *string;
    if (value.isNumber())
        return oo::plist_get::numberStringValue(value);
    return std::nullopt;
}

// An element as -oo_stringAtIndex: read it (a string, or a number's text; else nullopt).
std::optional<std::string> StringAtIndex(const oo::PList& array, std::size_t index)
{
    const oo::PList* value = array.at(index);
    if (value == nullptr)
        return std::nullopt;
    if (const std::string* string = value->getIf<std::string>())
        return *string;
    if (value->isNumber())
        return oo::plist_get::numberStringValue(*value);
    return std::nullopt;
}

// A by-name value that turns a mission resource off: empty, or "none" in any case.
bool IsNoneValue(const std::string& value)
{
    return value.empty() || oo::str::lowercase(value) == "none";
}

// Tokens as a PList array, so an element reads with -oo_intAtIndex: & co.'s rules (get<T>).
oo::PList TokenArray(const std::vector<std::string>& tokens)
{
    oo::PList::Array result;
    for (const std::string& token : tokens)
        result.push_back(oo::PList(token));
    return oo::PList(std::move(result));
}

// -componentsJoinedByString:@" " of tokens[from...].
std::string JoinedFrom(const std::vector<std::string>& tokens, std::size_t from)
{
    std::string result;
    for (std::size_t i = from; i < tokens.size(); i++) {
        if (i != from)
            result += " ";
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
std::optional<std::string> ConditionString(id value)
{
    if (value == nil)
        return std::nullopt;
    if (oo::IsNSString(value))
        return oo::OptionalString(value);
    return oo::DescriptionOf(value);
}

std::optional<std::string> ConditionString(const oo::PList& value)
{
    if (value.isNull())
        return std::nullopt;
    if (const std::string* string = value.getIf<std::string>())
        return *string;
    return oo::DescriptionOf(oo::ObjectFromPList(value));
}

void PerformScriptActions(const oo::PList& actions, Entity* target);
void PerformConditionalStatment(const oo::PList& actions, Entity* target);
void PerformActionStatment(const oo::PList& statement, Entity* target);
BOOL TestScriptConditions(const oo::PList& conditions);
} // namespace

namespace {
void PerformScriptActions(const oo::PList& actions, Entity* target)
{
    const oo::PList::Array* statements = actions.getIf<oo::PList::Array>();
    if (statements == nullptr)
        return;
    for (const oo::PList& statement : *statements) {
        if (ElementAt(statement, 0).boolValue()) {
            PerformConditionalStatment(statement, target);
        } else {
            PerformActionStatment(statement, target);
        }
    }
}

void PerformConditionalStatment(const oo::PList& statement, Entity* target)
{
    /*	A sanitized conditional statement takes the form of an array:
            (true, conditions, trueActions, falseActions)
            The first element is always true. The second is an array of conditions.
            The third and four elements are actions to perform if the conditions
            evaluate to true or false, respectively.
    */

    const oo::PList& conditions = ElementAt(statement, 1);

    if (TestScriptConditions(conditions)) {
        PerformScriptActions(ElementAt(statement, 2), target);
    } else {
        PerformScriptActions(ElementAt(statement, 3), target);
    }
}

void PerformActionStatment(const oo::PList& statement, Entity* target)
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

    std::string selectorString;
    std::optional<std::string> argumentString;
    SEL selector = NULL;
    PlayerEntity* player = PLAYER;

    selectorString = statement.at<std::string>(1);
    if (statement.count() > 2)
        argumentString = statement.at<std::string>(2);

    selector = OOSelectorFromName(selectorString.c_str());

    if (target == nil || ![target respondsToSelector:selector]) {
        target = player;
    }

    if (argumentString.has_value()) {
        // Method with argument; substitute [description] expressions. The action is called by
        // name, so its argument stays a string object (ADR-0043 item 21).
        [target performSelector:selector withObject:OOExpandDescriptionString(OOStringExpanderDefaultRandomSeed(), oo::NSStringFrom(*argumentString), nil, oo::ObjectFromPList([player localVariablesForMission:sCurrentMissionKey]), nil, kOOExpandNoOptions)];
    } else {
        // Method without argument.
        [target performSelector:selector];
    }
}

BOOL TestScriptConditions(const oo::PList& conditions)
{
    PlayerEntity* player = PLAYER;

    if (const oo::PList::Array* conditionArray = conditions.getIf<oo::PList::Array>()) {
        for (const oo::PList& condition : *conditionArray) {
            if (![player scriptTestCondition:condition])
                return NO;
        }
    }

    return YES;
}
} // namespace

- (void)setScriptTarget:(ShipEntity*)ship
{
    scriptTarget = ship;
}

- (ShipEntity*)scriptTarget
{
    return scriptTarget;
}

OOINLINE OOEntityStatus RecursiveRemapStatus(OOEntityStatus status)
{
    // Some player stutuses should only be seen once per "event".
    // This remaps them to something innocuous in case of recursion.
    if (status == STATUS_DOCKING || status == STATUS_LAUNCHING || status == STATUS_ENTERING_WITCHSPACE || status == STATUS_EXITING_WITCHSPACE) {
        return STATUS_IN_FLIGHT;
    } else {
        return status;
    }
}

static BOOL sRunningScript = NO;

// Return the world scripts that care about -checkScript, by name (a Dict of Object nodes).
- (oo::PList)worldScriptsRequiringTickle
{
    // The cache ivar is PlayerEntity.h's (a dictionary of the scripts); it is kept that way.
    if (worldScriptsRequiringTickle != nil)
        return oo::PListFrom(worldScriptsRequiringTickle);

    oo::PList::Dict tickleScripts;
    for (const std::string& scriptName : oo::StringsFrom([worldScripts allKeys])) {
        OOScript* candidateScript = [worldScripts objectForKey:oo::NSStringFrom(scriptName)];
        if ([candidateScript requiresTickle]) {
            tickleScripts[scriptName] = oo::PListObject(candidateScript);
        }
    }

    oo::PList result(std::move(tickleScripts));
    worldScriptsRequiringTickle = [oo::ObjectFromPList(result) retain];
    return result;
}

- (void)checkScript
{
    BOOL wasRunningScript = sRunningScript;
    OOEntityStatus status, restoreStatus;

    const oo::PList tickleScripts = [self worldScriptsRequiringTickle];
    if (tickleScripts.count() == 0) {
        // Quick exit if we only have JS scripts.
        return;
    }

    [self setScriptTarget:self];

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
    @try {
        if (sRunningScript) {
            status = RecursiveRemapStatus(status);
            [self setStatus:status];
        }
        sRunningScript = YES;

        // After all that, actually running the scripts is trivial. (Order: script name, byte
        // order; it was the hash order of -allValues.)
        for (const auto& [scriptName, tickleScript] : *tickleScripts.getIf<oo::PList::Dict>()) {
            [(OOScript*)oo::ObjectIn(tickleScript) runWithTarget:self];
        }
    }
    @catch (OOException* exception) {
        OOLog(kOOLogException, @"***** Exception running world scripts: %@ : %@", oo::NSStringFrom([exception name]), oo::NSStringFrom([exception reason]));
    }
    @catch (OOFoundationException* exception) {
        OOLog(kOOLogException, @"***** Exception running world scripts: %@ : %@", [exception name], [exception reason]);
    }

    // Restore anti-recursion measures.
    sRunningScript = wasRunningScript;
    if (status != restoreStatus)
        [self setStatus:restoreStatus];
}

- (void)cxx_runScriptActions:(const oo::PList&)actions withContextName:(const std::optional<std::string>&)contextName forTarget:(ShipEntity*)target
{
    std::optional<std::string> oldMissionKey;

    @autoreleasepool {
        // FIXME: does this actually make sense in the context of non-missions?
        oldMissionKey = sCurrentMissionKey;
        sCurrentMissionKey = contextName;

        @try {
            PerformScriptActions(actions, target);
        }
        @catch (OOException* exception) {
            OOLog(@"script.error.exception",
                @"***** EXCEPTION %@: %@ while handling legacy script actions for %@",
                oo::NSStringFrom([exception name]),
                oo::NSStringFrom([exception reason]),
                (contextName.has_value() && oo::str::hasPrefix(*contextName, kActionTempPrefix)) ? [target shortDescription] : oo::NSStringOrNil(contextName));
            // Suppress exception
        }
        @catch (OOFoundationException* exception) {
            // (a nil context printed "(null)")
            OOLog(@"script.error.exception",
                @"***** EXCEPTION %@: %@ while handling legacy script actions for %@",
                [exception name],
                [exception reason],
                (contextName.has_value() && oo::str::hasPrefix(*contextName, kActionTempPrefix)) ? [target shortDescription] : oo::NSStringOrNil(contextName));
            // Suppress exception
        }

        sCurrentMissionKey = oldMissionKey;
    }
}

- (void)cxx_runUnsanitizedScriptActions:(const oo::PList&)actions allowingAIMethods:(BOOL)allowAIMethods withContextName:(const std::optional<std::string>&)contextName forTarget:(ShipEntity*)target
{
    [self cxx_runScriptActions:OOSanitizeLegacyScript(actions, contextName, allowAIMethods)
               withContextName:contextName
                     forTarget:target];
}

- (BOOL)cxx_scriptTestConditions:(const oo::PList&)array
{
    BOOL result = NO;

    @try {
        result = TestScriptConditions(array);
    }
    @catch (OOException* exception) {
        OOLog(@"script.error.exception",
            @"***** EXCEPTION %@: %@ while testing legacy script conditions.",
            oo::NSStringFrom([exception name]),
            oo::NSStringFrom([exception reason]));
        // Suppress exception
    }
    @catch (OOFoundationException* exception) {
        OOLog(@"script.error.exception",
            @"***** EXCEPTION %@: %@ while testing legacy script conditions.",
            [exception name],
            [exception reason]);
        // Suppress exception
    }

    return result;
}

- (BOOL)scriptTestCondition:(const oo::PList&)scriptCondition
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

    OOOperationType opType;
    std::string selectorString;
    SEL selector = NULL;
    OOComparisonType comparator;
    std::optional<std::string> lhsString;
    std::string expandedRHS;
    double lhsValue, rhsValue;
    BOOL lhsFlag, rhsFlag;

    opType = (OOOperationType)scriptCondition.at<unsigned int>(0);
    if (opType == OP_FALSE)
        return NO;

    selectorString = scriptCondition.at<std::string>(2);
    comparator = (OOComparisonType)scriptCondition.at<unsigned int>(3);
    const oo::PList& operandArray = ElementAt(scriptCondition, 4);

    // Transform mission/local var ops into string ops.
    if (opType == OP_MISSION_VAR) {
        sMissionStringValue = ConditionString([self cxx_missionVariableForKey:selectorString]);
        selector = @selector(mission_string);
        opType = OP_STRING;
    } else if (opType == OP_LOCAL_VAR) {
        const oo::PList locals = [self localVariablesForMission:sCurrentMissionKey];
        const oo::PList* local = locals.find(selectorString);
        sMissionStringValue = ConditionString(local != nullptr ? *local : oo::PList());
        selector = @selector(mission_string);
        opType = OP_STRING;
    } else {
        selector = OOSelectorFromName(selectorString.c_str());
    }

    expandedRHS = [self expandScriptRightHandSide:operandArray].value_or(std::string());

    if (opType == OP_STRING) {
        // The query is called by name and answers an object (ADR-0043 item 21).
        lhsString = ConditionString([self performSelector:selector]);

#define DOUBLEVAL(x) ((x).has_value() ? oo::str::doubleValue(*(x)) : 0.0)

        switch (comparator) {
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

        case COMPARISON_ONEOF: {
            if (!lhsString.has_value())
                return NO; // nil matched nothing
            const std::string trimmedLHS = TrimWhitespace(*lhsString);

            for (const std::string& rhsItem : oo::str::split(expandedRHS, ",")) {
                if (trimmedLHS == TrimWhitespace(rhsItem)) {
                    return YES;
                }
            }
        }
            return NO;
        }
    } else if (opType == OP_NUMBER) {
        lhsValue = [[self performSelector:selector] doubleValue];

        if (comparator == COMPARISON_ONEOF) {
            for (const std::string& rhsItem : oo::str::split(expandedRHS, ",")) {
                rhsValue = oo::str::doubleValue(rhsItem);

                if (lhsValue == rhsValue) {
                    return YES;
                }
            }

            return NO;
        } else {
            rhsValue = oo::str::doubleValue(expandedRHS);

            switch (comparator) {
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
                OOLog(@"script.error.unexpectedOperator", @"***** SCRIPT ERROR: in %@, operator %@ is not valid for numbers, evaluating to false.", oo::NSStringFrom(CurrentScriptDescription()), oo::NSStringFrom(cxx_OOComparisonTypeToString(comparator)));
                return NO;
            }
        }
    } else if (opType == OP_BOOL) {
        lhsFlag = ConditionString([self performSelector:selector]) == std::optional<std::string>("YES");
        rhsFlag = expandedRHS == "YES";

        switch (comparator) {
        case COMPARISON_EQUAL:
            return lhsFlag == rhsFlag;

        case COMPARISON_NOTEQUAL:
            return lhsFlag != rhsFlag;

        case COMPARISON_LESSTHAN:
        case COMPARISON_GREATERTHAN:
        case COMPARISON_UNDEFINED:
        case COMPARISON_ONEOF:
            // "Can't happen" - should have been caught by the sanitizer.
            OOLog(@"script.error.unexpectedOperator", @"***** SCRIPT ERROR: in %@, operator %@ is not valid for booleans, evaluating to false.", oo::NSStringFrom(CurrentScriptDescription()), oo::NSStringFrom(cxx_OOComparisonTypeToString(comparator)));
            return NO;
        }
    }

    // What are we doing here? (The condition prints as an old-style plist: decision C.)
    const auto conditionText = oo::writeOldStylePList(scriptCondition);
    std::string conditionDescription = conditionText.has_value() ? std::string(conditionText->stringView()) : std::string();
    if (!conditionDescription.empty() && conditionDescription.back() == '\n')
        conditionDescription.pop_back();
    OOLog(@"script.error.fallthrough", @"***** SCRIPT ERROR: in %@, unhandled condition '%@' (%@). %@", oo::NSStringFrom(CurrentScriptDescription()), oo::NSStringFrom(scriptCondition.at<std::string>(1)), oo::NSStringFrom(conditionDescription), @"This is an internal error, please report it.");
    return NO;
}

- (std::optional<std::string>)expandScriptRightHandSide:(const oo::PList&)rhsComponents
{
    std::string result;
    bool first = true;

    if (const oo::PList::Array* components = rhsComponents.getIf<oo::PList::Array>()) {
        for (const oo::PList& component : *components) {
            /*	Each component is a two-element array. The second element is a
                    string. The first element is a boolean indicating whether the
                    string is a selector (true) or a literal (false).

                    All valid selectors return a string or a number; in either
                    case, -description gives us a useful value to substitute into
                    the expanded string.
            */

            std::string value = component.at<std::string>(1);

            if (ElementAt(component, 0).boolValue()) {
                // (nil prints "(null)", for backwards compatibility)
                value = oo::DescriptionOf([self performSelector:OOSelectorFromName(value.c_str())]);
            }

            if (!first)
                result += " ";
            result += value;
            first = false;
        }
    }

    return result;
}

- (oo::PList)cxx_missionVariables
{
    return oo::PListFrom(mission_variables); // a snapshot
}

- (oo::PList)cxx_missionVariableForKey:(const std::string&)key
{
    return oo::PListFrom([mission_variables objectForKey:oo::NSStringFrom(key)]);
}

- (void)cxx_setMissionVariable:(const oo::PList&)value forKey:(const std::string&)key
{
    if (!value.isNull())
        [mission_variables setObject:oo::ObjectFromPList(value) forKey:oo::NSStringFrom(key)];
    else
        [mission_variables removeObjectForKey:oo::NSStringFrom(key)];
}

/*	A mission's local variables, as a snapshot Dict (null for no mission). The per-mission tables in
        the localVariables ivar (PlayerEntity.h's) are immutable dictionaries replaced on write; nothing
        else reads or saves them, so the old create-an-empty-table-on-read side effect is not kept.
*/
- (oo::PList)localVariablesForMission:(const std::optional<std::string>&)missionKey
{
    if (!missionKey.has_value())
        return oo::PList();

    oo::PList result = oo::PListFrom([localVariables objectForKey:oo::NSStringFrom(*missionKey)]);
    if (!result.isDict())
        result = oo::PList(oo::PList::Dict { });
    return result;
}

- (std::optional<std::string>)localVariableForKey:(const std::string&)variableName andMission:(const std::optional<std::string>&)missionKey
{
    if (!missionKey.has_value())
        return std::nullopt;
    const oo::PList locals = [self localVariablesForMission:missionKey];
    const oo::PList* value = locals.find(variableName);
    if (value == nullptr)
        return std::nullopt;
    return ConditionString(*value);
}

- (void)setLocalVariable:(const std::optional<std::string>&)value forKey:(const std::string&)variableName andMission:(const std::optional<std::string>&)missionKey
{
    if (missionKey.has_value()) {
        oo::PList locals = [self localVariablesForMission:missionKey];
        oo::PList::Dict* table = locals.getIf<oo::PList::Dict>();
        if (value.has_value()) {
            (*table)[variableName] = oo::PList(*value);
        } else {
            table->erase(variableName);
        }
        [localVariables setObject:oo::ObjectFromPList(locals) forKey:oo::NSStringFrom(*missionKey)];
    }
}

- (oo::PList)cxx_missionsList
{
    oo::PList::Array result1; // strings
    oo::PList::Array result2; // arrays: a header, then entries

    // The manifests (PlayerEntityContracts, not migrated) as oo::PList arrays.
    const oo::PList passengerManifest = oo::PListFrom([self passengerList]);
    const oo::PList contractManifest = oo::PListFrom([self contractList]);
    const oo::PList parcelManifest = oo::PListFrom([self parcelList]);

    auto addManifest = [&result2](const std::string& header, const oo::PList& manifest) {
        const oo::PList::Array* entries = manifest.getIf<oo::PList::Array>();
        if (entries == nullptr || entries->empty())
            return;
        oo::PList::Array list { oo::PList(header) };
        list.insert(list.end(), entries->begin(), entries->end());
        result2.push_back(oo::PList(std::move(list)));
    };

    addManifest(oo::StdString(DESC(@"manifest-passengers")), passengerManifest);
    addManifest(oo::StdString(DESC(@"manifest-parcels")), parcelManifest);
    addManifest(oo::StdString(DESC(@"manifest-contracts")), contractManifest);

    /* For proper display, array entries need to all be after string
     * entries, so sort them now */
    // (world scripts in -allKeys order, which is the -keyEnumerator order the loop used)
    for (const std::string& scriptName : oo::StringsFrom([worldScripts allKeys])) {
        const oo::PList vars = [self cxx_missionVariableForKey:scriptName];

        if (vars.isString()) {
            result1.push_back(vars);
        } else if (const oo::PList::Array* varList = vars.getIf<oo::PList::Array>()) {
            BOOL found = NO;
            const std::optional<std::string> header = StringAtIndex(vars, 0);
            for (std::size_t i = 0; i < result2.size(); i++) {
                const std::optional<std::string> elementHeader = StringAtIndex(result2[i], 0);
                if (elementHeader.has_value() && header.has_value() && *elementHeader == *header) {
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
            if (!found) {
                result2.push_back(vars);
            }
        }
    }
    result1.insert(result1.end(), result2.begin(), result2.end());
    return oo::PList(std::move(result1));
}

- (std::optional<std::string>)replaceVariablesInString:(const std::string&)args
{
    const oo::PList locals = [self localVariablesForMission:sCurrentMissionKey];
    std::string resultString = args;

    // Each replacement is literal (NSLiteralSearch).
    auto replace = [&resultString](const std::string& target, const std::string& replacement) {
        resultString = oo::str::replaceOccurrences(resultString, target, replacement, oo::str::Search::literal);
    };

    for (const std::string& valueString : oo::str::tokens(args)) {
        const oo::PList missionValue = oo::str::hasPrefix(valueString, "mission_") ? [self cxx_missionVariableForKey:valueString] : oo::PList();
        const oo::PList* localValue = locals.find(valueString);

        if (!missionValue.isNull()) {
            // (a non-string variable substitutes its description; the old code raised)
            replace(valueString, ConditionString(missionValue).value_or(std::string()));
        } else if (localValue != nullptr) {
            replace(valueString, ConditionString(*localValue).value_or(std::string()));
        } else if (oo::str::hasSuffix(valueString, "_number") || oo::str::hasSuffix(valueString, "_bool") || oo::str::hasSuffix(valueString, "_string")) {
            SEL valueselector = OOSelectorFromName(valueString.c_str());
            if ([self respondsToSelector:valueselector]) {
                // called by name; "%@" of the result, as +stringWithFormat: printed it
                replace(valueString, oo::DescriptionOf([self performSelector:valueselector]));
            }
        } else if (oo::str::hasPrefix(valueString, "[") && oo::str::hasSuffix(valueString, "]")) {
            replace(valueString, oo::StdString(OOExpand(oo::NSStringFrom(valueString))));
        }
    }

    OO_LOG(kOOLogDebugReplaceVariablesInString, "EXPANSION: \"{}\" becomes \"{}\"", args, resultString);

    return resultString;
}

/*-----------------------------------------------------*/

- (void)setMissionDescription:(id)textKey // called by name (ADR-0043 item 21)
{
    [self setMissionDescription:oo::StdString(textKey) forMission:sCurrentMissionKey];
}

- (void)setMissionDescription:(const std::string&)textKey forMission:(const std::optional<std::string>&)key
{
    const std::optional<std::string> text = MissionTextForKey(textKey);

    if (!text.has_value()) {
        OO_LOG_ERR(kOOLogScriptMissionDescNoText, "in {}, no mission text set for key '{}' [UNIVERSE missiontext] is:\n{} ", CurrentScriptDescription(), textKey, oo::DescriptionOf([UNIVERSE missiontext]));
        return;
    }

    [self cxx_setMissionInstructions:*text forMission:key];
}

// implementation of mission.setInstructions(), also final part of legacy setMissionDescription
- (void)cxx_setMissionInstructions:(const std::string&)text forMission:(const std::optional<std::string>&)key
{
    if (!key.has_value()) {
        OO_LOG_ERR(kOOLogScriptMissionDescNoKey, "in {}, mission key not set", CurrentScriptDescription());
        return;
    }

    const std::string expanded = oo::StdString(OOExpand(oo::NSStringFrom(text)));
    [self cxx_setMissionVariable:oo::PList([self replaceVariablesInString:expanded].value_or(std::string())) forKey:*key];
}

- (void)cxx_setMissionInstructionsList:(const oo::PList&)list forMission:(const std::optional<std::string>&)key
{
    if (!key.has_value()) {
        OO_LOG_ERR(kOOLogScriptMissionDescNoKey, "in {}, mission key not set", CurrentScriptDescription());
        return;
    }

    oo::PList::Array expandedList;
    NSUInteger i, ct = list.count();
    for (i = 0; i < ct; i++) {
        const std::optional<std::string> text = StringAtIndex(list, i);
        if (text.has_value()) {
            const std::string expanded = oo::StdString(OOExpand(oo::NSStringFrom(*text)));
            expandedList.push_back(oo::PList([self replaceVariablesInString:expanded].value_or(std::string())));
        }
    }

    [self cxx_setMissionVariable:oo::PList(std::move(expandedList)) forKey:*key];
}

- (void)clearMissionDescription
{
    [self clearMissionDescriptionForMission:oo::NSStringOrNil(sCurrentMissionKey)];
}

- (void)clearMissionDescriptionForMission:(id)key // called by name (ADR-0043 item 21)
{
    if (key == nil) {
        OO_LOG_ERR(kOOLogScriptMissionDescNoKey, "in {}, mission key not set", CurrentScriptDescription());
        return;
    }

    [self cxx_setMissionVariable:oo::PList() forKey:oo::StdString(key)]; // (removing an absent key does nothing)
}

// called by name (ADR-0043 item 21), as are the queries below
- (id)mission_string
{
    return oo::NSStringOrNil(sMissionStringValue);
}

- (id)status_string // called by name (ADR-0043 item 21)
{
    return OOStringFromEntityStatus([self status]);
}

- (id)gui_screen_string // called by name (ADR-0043 item 21)
{
    return OOStringFromGUIScreenID(gui_screen);
}

- (id)galaxy_number // called by name (ADR-0043 item 21)
{
    return oo::ObjectFromPList(oo::PList::signedInteger([self currentGalaxyID]));
}

- (id)planet_number // called by name (ADR-0043 item 21)
{
    return oo::ObjectFromPList(oo::PList::signedInteger([self currentSystemID]));
}

- (id)score_number // called by name (ADR-0043 item 21)
{
    return oo::ObjectFromPList(oo::PList::unsignedInteger([self score]));
}

- (id)credits_number // called by name (ADR-0043 item 21)
{
    return oo::ObjectFromPList(oo::PList((double)([self creditBalance])));
}

- (id)scriptTimer_number // called by name (ADR-0043 item 21)
{
    return oo::ObjectFromPList(oo::PList((double)([self scriptTimer])));
}

static int shipsFound;
- (id)shipsFound_number // called by name (ADR-0043 item 21)
{
    return oo::ObjectFromPList(oo::PList::signedInteger(shipsFound));
}

- (id)commanderLegalStatus_number // called by name (ADR-0043 item 21)
{
    return oo::ObjectFromPList(oo::PList::signedInteger([self legalStatus]));
}

- (void)setLegalStatus:(id)valueString // called by name (ADR-0043 item 21); shared selector (proposed ADR-0043)
{
    legalStatus = oo::str::intValue(oo::StdString(valueString)); // nil was 0, as "" is
}

- (id)commanderLegalStatus_string // called by name (ADR-0043 item 21)
{
    return OODisplayStringFromLegalStatus(legalStatus);
}

- (id)d100_number // called by name (ADR-0043 item 21)
{
    int d100 = ranrot_rand() % 100;
    return oo::ObjectFromPList(oo::PList::signedInteger(d100));
}

- (id)pseudoFixedD100_number // called by name (ADR-0043 item 21)
{
    return oo::ObjectFromPList(oo::PList::signedInteger([self systemPseudoRandom100]));
}

- (id)d256_number // called by name (ADR-0043 item 21)
{
    int d256 = ranrot_rand() % 256;
    return oo::ObjectFromPList(oo::PList::signedInteger(d256));
}

- (id)pseudoFixedD256_number // called by name (ADR-0043 item 21)
{
    return oo::ObjectFromPList(oo::PList::signedInteger([self systemPseudoRandom256]));
}

- (id)clock_number // called by name (ADR-0043 item 21); returns the game time in seconds
{
    return oo::ObjectFromPList(oo::PList((double)(ship_clock)));
}

- (id)clock_secs_number // called by name (ADR-0043 item 21); returns the game time in seconds
{
    return oo::ObjectFromPList(oo::PList::unsignedInteger((unsigned long long)(ship_clock)));
}

- (id)clock_mins_number // called by name (ADR-0043 item 21); returns the game time in minutes
{
    return oo::ObjectFromPList(oo::PList::unsignedInteger((unsigned long long)(ship_clock / 60.0)));
}

- (id)clock_hours_number // called by name (ADR-0043 item 21); returns the game time in hours
{
    return oo::ObjectFromPList(oo::PList::unsignedInteger((unsigned long long)(ship_clock / 3600.0)));
}

- (id)clock_days_number // called by name (ADR-0043 item 21); returns the game time in days
{
    return oo::ObjectFromPList(oo::PList::unsignedInteger((unsigned long long)(ship_clock / 86400.0)));
}

- (id)fuelLevel_number // called by name (ADR-0043 item 21); returns the fuel level in LY
{
    return oo::ObjectFromPList(oo::PList::singleReal((float)(floor(0.1 * fuel))));
}

- (id)dockedAtMainStation_bool // called by name (ADR-0043 item 21)
{
    if ([self dockedAtMainStation])
        return @"YES";
    else
        return @"NO";
}

- (id)foundEquipment_bool // called by name (ADR-0043 item 21)
{
    return (found_equipment) ? @"YES" : @"NO";
}

- (id)sunWillGoNova_bool // called by name (ADR-0043 item 21); returns whether the sun is going to go nova
{
    return ([[UNIVERSE sun] willGoNova]) ? @"YES" : @"NO";
}

- (id)sunGoneNova_bool // called by name (ADR-0043 item 21); returns whether the sun has gone nova
{
    return ([[UNIVERSE sun] goneNova]) ? @"YES" : @"NO";
}

- (id)missionChoice_string // called by name (ADR-0043 item 21); returns nil or the key for the chosen option
{
    return oo::NSStringOrNil(missionChoice);
}

- (id)missionKeyPress_string // called by name (ADR-0043 item 21)
{
    return oo::NSStringOrNil(missionKeyPress);
}

- (id)dockedTechLevel_number // called by name (ADR-0043 item 21)
{
    StationEntity* dockedStation = [self dockedStation];
    if (!dockedStation) {
        return [self systemTechLevel_number];
    }
    return oo::ObjectFromPList(oo::PList::unsignedInteger([dockedStation equivalentTechLevel]));
}

- (id)dockedStationName_string // called by name (ADR-0043 item 21); returns 'NONE' if the player isn't docked, [station name] if it is, 'UNKNOWN' otherwise (?)
{
    if ([self status] != STATUS_DOCKED)
        return @"NONE";

    return oo::NSStringFrom(oo::OptionalString([self dockedStationName]).value_or("UNKNOWN"));
}

- (id)systemGovernment_string // called by name (ADR-0043 item 21)
{
    int government = [[self systemGovernment_number] intValue]; // 0 .. 7 (0 anarchic .. 7 most stable)
    return oo::NSStringFrom(oo::OptionalString(OODisplayStringFromGovernmentID(government)).value_or("UNKNOWN"));
}

- (id)systemGovernment_number // called by name (ADR-0043 item 21)
{
    return [[UNIVERSE currentSystemData] objectForKey:KEY_GOVERNMENT];
}

- (id)systemEconomy_string // called by name (ADR-0043 item 21)
{
    int economy = [[self systemEconomy_number] intValue]; // 0 .. 7 (0 rich industrial .. 7 poor agricultural)
    return oo::NSStringFrom(oo::OptionalString(OODisplayStringFromEconomyID(economy)).value_or("UNKNOWN"));
}

- (id)systemEconomy_number // called by name (ADR-0043 item 21)
{
    return [[UNIVERSE currentSystemData] objectForKey:KEY_ECONOMY];
}

- (id)systemTechLevel_number // called by name (ADR-0043 item 21)
{
    return [[UNIVERSE currentSystemData] objectForKey:KEY_TECHLEVEL];
}

- (id)systemPopulation_number // called by name (ADR-0043 item 21)
{
    return [[UNIVERSE currentSystemData] objectForKey:KEY_POPULATION];
}

- (id)systemProductivity_number // called by name (ADR-0043 item 21)
{
    return [[UNIVERSE currentSystemData] objectForKey:KEY_PRODUCTIVITY];
}

- (id)commanderName_string // called by name (ADR-0043 item 21)
{
    return [self commanderName];
}

- (id)commanderRank_string // called by name (ADR-0043 item 21)
{
    return OODisplayRatingStringFromKillCount([self score]);
}

- (id)commanderShip_string // called by name (ADR-0043 item 21)
{
    return [self name];
}

- (id)commanderShipDisplayName_string // called by name (ADR-0043 item 21)
{
    return [self displayName];
}

/*-----------------------------------------------------*/

- (std::optional<std::string>)expandMessage:(const std::string&)valueString
{
    Random_Seed very_random_seed;
    very_random_seed.a = rand() & 255;
    very_random_seed.b = rand() & 255;
    very_random_seed.c = rand() & 255;
    very_random_seed.d = rand() & 255;
    very_random_seed.e = rand() & 255;
    very_random_seed.f = rand() & 255;
    seed_RNG_only_for_planet_description(very_random_seed);
    return [self replaceVariablesInString:oo::StdString(OOExpand(oo::NSStringFrom(valueString)))];
}

- (void)commsMessage:(id)valueString // called by name (ADR-0043 item 21); shared selector (proposed ADR-0043)
{
    [UNIVERSE addCommsMessage:oo::NSStringOrNil([self expandMessage:oo::StdString(valueString)]) forCount:4.5];
}

// Enabled on 02-May-2008 - Nikos
// This method does the same as -commsMessage, (which in fact calls), the difference being that scripts can use this
// method to have unpiloted ship entities sending comms messages.
- (void)commsMessageByUnpiloted:(id)valueString // called by name (ADR-0043 item 21); shared selector (proposed ADR-0043)
{
    [self commsMessage:valueString];
}

- (void)consoleMessage3s:(id)valueString // called by name (ADR-0043 item 21)
{
    [UNIVERSE addMessage:oo::NSStringOrNil([self expandMessage:oo::StdString(valueString)]) forCount:3];
}

- (void)consoleMessage6s:(id)valueString // called by name (ADR-0043 item 21)
{
    [UNIVERSE addMessage:oo::NSStringOrNil([self expandMessage:oo::StdString(valueString)]) forCount:6];
}

- (void)awardCredits:(id)valueString // called by name (ADR-0043 item 21)
{
    if (scriptTarget != self)
        return;

    /*	We can't use -longLongValue here for Mac OS X 10.4 compatibility, but
            we don't need to since larger values have never been supported for
            legacy scripts.
    */
    int64_t award = oo::str::intValue(oo::StdString(valueString));
    award *= 10;
    if (award < 0 && credits < (OOCreditsQuantity)-award)
        credits = 0;
    else
        credits += award;
}

- (void)awardShipKills:(id)valueString // called by name (ADR-0043 item 21)
{
    if (scriptTarget != self)
        return;

    int value = oo::str::intValue(oo::StdString(valueString));
    if (0 < value)
        ship_kills += value;
}

- (void)awardEquipment:(id)equipString // called by name (ADR-0043 item 21); eg. EQ_NAVAL_ENERGY_UNIT
{
    if (scriptTarget != self)
        return;

    const std::string equipKey = oo::StdString(equipString);
    if (equipKey == "EQ_FUEL") {
        [self setFuel:[self fuelCapacity]];
    }

    OOEquipmentType* eqType = [OOEquipmentType equipmentTypeWithIdentifier:equipString];

    if ([eqType isMissileOrMine]) {
        [self mountMissileWithRole:equipString];
    } else if (oo::str::hasPrefix(equipKey, "EQ_WEAPON") && !oo::str::hasSuffix(equipKey, "_DAMAGED")) {
        OO_LOG(kOOLogSyntaxAwardEquipment, "***** SCRIPT ERROR: in {}, CANNOT award undamaged weapon:'{}'. Damaged weapons can be awarded instead.", CurrentScriptDescription(), equipKey);
    }
    // (the "_DAMAGED" suffix is ASCII, so its bytes are its characters)
    else if (oo::str::hasSuffix(equipKey, "_DAMAGED") && [self hasEquipmentItem:oo::NSStringFrom(equipKey.substr(0, equipKey.size() - 8))]) {
        OO_LOG(kOOLogSyntaxAwardEquipment, "***** SCRIPT ERROR: in {}, CANNOT award damaged equipment:'{}'. Undamaged version already equipped.", CurrentScriptDescription(), equipKey);
    } else if ([eqType canCarryMultiple] || ![self hasEquipmentItem:equipString]) {
        [self addEquipmentItem:equipString withValidation:YES inContext:@"scripted"];
    }
}

- (void)removeEquipment:(id)equipString // called by name (ADR-0043 item 21); eg. EQ_NAVAL_ENERGY_UNIT
{
    if (scriptTarget != self)
        return;

    const std::string equipKey = oo::StdString(equipString);
    if (equipKey == "EQ_FUEL") {
        fuel = 0;
        return;
    }

    if (equipKey == "EQ_CARGO_BAY" && [self hasEquipmentItem:equipString]
        && ([self extraCargo] > [self availableCargoSpace])) {
        OO_LOG(kOOLogSyntaxRemoveEquipment, "***** SCRIPT ERROR: in {}, CANNOT remove cargo bay. Too much cargo.", CurrentScriptDescription());
        return;
    }
    if ([self hasEquipmentItem:equipString] || [self hasEquipmentItem:oo::NSStringFrom(equipKey + "_DAMAGED")]) {
        [self removeEquipmentItem:equipString];
    }
}

- (void)setPlanetinfo:(id)key_valueString // called by name (ADR-0043 item 21); uses key=value format
{
    const std::string argument = oo::StdString(key_valueString);
    const std::vector<std::string> tokens = oo::str::split(argument, "=");

    if (tokens.size() != 2) {
        OO_LOG(kOOLogSyntaxSetPlanetInfo, "***** SCRIPT ERROR: in {}, CANNOT setPlanetinfo: '{}' (bad parameter count)", CurrentScriptDescription(), argument);
        return;
    }

    const std::string keyString = TrimWhitespace(tokens[0]);
    const std::string valueString = TrimWhitespace(tokens[1]);

    /* Legacy script planetinfo settings are now non-persistent over save/load
     * Virtually nothing uses them any more, and expecting them to have a
     * manifest and identifying what it is if so seems unnecessary */
    [UNIVERSE setSystemDataKey:oo::NSStringFrom(keyString) value:oo::NSStringFrom(valueString) fromManifest:@""];
}

- (void)setSpecificPlanetInfo:(id)key_valueString // called by name (ADR-0043 item 21); uses galaxy#=planet#=key=value
{
    const std::string argument = oo::StdString(key_valueString);
    const std::vector<std::string> tokens = oo::str::split(argument, "=");
    int gnum, pnum;

    if (tokens.size() != 4) {
        OO_LOG(kOOLogSyntaxSetPlanetInfo, "***** SCRIPT ERROR: in {}, CANNOT setSpecificPlanetInfo: '{}' (bad parameter count)", CurrentScriptDescription(), argument);
        return;
    }

    const oo::PList tokenArray = TokenArray(tokens);
    gnum = tokenArray.at<int>(0);
    pnum = tokenArray.at<int>(1);
    const std::string keyString = TrimWhitespace(tokens[2]);
    const std::string valueString = TrimWhitespace(tokens[3]);

    [UNIVERSE setSystemDataForGalaxy:gnum planet:pnum key:oo::NSStringFrom(keyString) value:oo::NSStringFrom(valueString) fromManifest:@"" forLayer:OO_LAYER_OXP_DYNAMIC];
}

- (void)awardCargo:(id)amount_typeString // called by name (ADR-0043 item 21)
{
    if (scriptTarget != self)
        return;

    const std::string argument = oo::StdString(amount_typeString);
    const std::vector<std::string> tokens = oo::str::tokens(argument);
    OOCargoQuantityDelta amount;
    OOMassUnit unit;

    if (tokens.size() != 2) {
        OO_LOG(kOOLogSyntaxAwardCargo, "***** SCRIPT ERROR: in {}, CANNOT awardCargo: '{}' ({})", CurrentScriptDescription(), argument, "bad parameter count");
        return;
    }

    const oo::PList tokenArray = TokenArray(tokens);
    const std::string& type = tokens[1]; // the good (Amendment 1 item 10: a std::string)
    if (![[UNIVERSE commodities] goodDefined:oo::NSStringFrom(type)]) {
        OO_LOG(kOOLogSyntaxAwardCargo, "***** SCRIPT ERROR: in {}, CANNOT awardCargo: '{}' ({})", CurrentScriptDescription(), argument, "unknown type");
        return;
    }

    amount = tokenArray.at<int>(0);
    if (amount < 0) {
        OO_LOG(kOOLogSyntaxAwardCargo, "***** SCRIPT ERROR: in {}, CANNOT awardCargo: '{}' ({})", CurrentScriptDescription(), argument, "negative quantity");
        return;
    }

    unit = [shipCommodityData massUnitForGood:oo::NSStringFrom(type)];
    if (specialCargo && unit == UNITS_TONS) {
        OO_LOG(kOOLogSyntaxAwardCargo, "***** SCRIPT ERROR: in {}, CANNOT awardCargo: '{}' ({})", CurrentScriptDescription(), argument, "cargo hold full with special cargo");
        return;
    }

    [self awardCommodityType:oo::NSStringFrom(type) amount:amount];
}

- (void)removeAllCargo
{
    [self removeAllCargo:NO];
}

- (void)removeAllCargo:(BOOL)forceRemoval
{
    // Misnamed method. It only removes cargo measured in TONS, g & Kg items are not removed. --Kaks 20091004
    if (scriptTarget != self)
        return;

    if ([self status] != STATUS_DOCKED && !forceRemoval) {
        OO_LOG_WARN(kOOLogRemoveAllCargoNotDocked, "{}removeAllCargo only works when docked.", " in " + CurrentScriptDescription() + ", ");
        return;
    }

    OO_LOG(kOOLogNoteRemoveAllCargo, "{} removeAllCargo", forceRemoval ? "Forcing" : "Going to");

    for (const std::string& type : oo::StringsFrom([shipCommodityData goods])) {
        if ([shipCommodityData massUnitForGood:oo::NSStringFrom(type)] == UNITS_TONS) {
            [shipCommodityData cxx_setQuantity:0 forGood:type];
        }
    }

    if (forceRemoval && [self status] != STATUS_DOCKED) {
        NSInteger i;
        for (i = cargo.size() - 1; i >= 0; i--) {
            ShipEntity* canister = cargo[i].get();
            if (!canister)
                break;
            // Since we are forcing cargo removal, we don't really care about the unit of measurement. Any
            // commodity at more than 1000kg or 1000000gr will be inside cargopods, so remove those too.
            cargo.erase(cargo.begin() + i);
        }
    }

    specialCargo.reset();

    [self calculateCurrentCargo];
}

- (void)useSpecialCargo:(id)descriptionString // called by name (ADR-0043 item 21)
{
    if (scriptTarget != self)
        return;

    const std::string description = oo::StdString(descriptionString);
    [self removeAllCargo:YES];
    OO_LOG(kOOLogNoteUseSpecialCargo, "Going to useSpecialCargo:'{}'", description);
    specialCargo = oo::OptionalString(OOExpand(oo::NSStringFrom(description)));
}

- (void)testForEquipment:(id)equipString // called by name (ADR-0043 item 21); eg. EQ_NAVAL_ENERGY_UNIT
{
    found_equipment = [self hasEquipmentItem:equipString];
}

- (void)awardFuel:(id)valueString // called by name (ADR-0043 item 21); add to fuel up to 7.0 LY
{
    int delta = 10 * (float)oo::str::doubleValue(oo::StdString(valueString));
    OOFuelQuantity scriptTargetFuelBeforeAward = [scriptTarget fuel];

    if (delta < 0 && scriptTargetFuelBeforeAward < (unsigned)-delta)
        [scriptTarget setFuel:0];
    else {
        [scriptTarget setFuel:(scriptTargetFuelBeforeAward + delta)];
    }
}

- (void)messageShipAIs:(id)roles_message // called by name (ADR-0043 item 21)
{
    const std::string argument = oo::StdString(roles_message);
    const std::vector<std::string> tokens = oo::str::tokens(argument);

    if (tokens.size() < 2) {
        OO_LOG(kOOLogSyntaxMessageShipAIs, "***** SCRIPT ERROR: in {}, CANNOT messageShipAIs: '{}' (bad parameter count)", CurrentScriptDescription(), argument);
        return;
    }

    const std::string& roleString = tokens[0];
    const std::string messageString = JoinedFrom(tokens, 1);

    for (const auto& target : oo::ObjCRefsFrom<ShipEntity*>([UNIVERSE findShipsMatchingPredicate:HasPrimaryRolePredicate
                                                                                       parameter:oo::NSStringFrom(roleString)
                                                                                         inRange:-1
                                                                                        ofEntity:nil])) {
        [[target.get() getAI] cxx_reactToMessage:messageString context:std::string("messageShipAIs:")];
    }
}

- (void)ejectItem:(id)itemKey // called by name (ADR-0043 item 21)
{
    if (scriptTarget == nil)
        scriptTarget = self;
    [scriptTarget ejectShipOfType:oo::OptionalString(itemKey)];
}

- (void)addShips:(id)roles_number // called by name (ADR-0043 item 21)
{
    const std::string argument = oo::StdString(roles_number);
    const std::vector<std::string> tokens = oo::str::tokens(argument);

    if (tokens.size() != 2) {
        OO_LOG(kOOLogSyntaxAddShips, "***** SCRIPT ERROR: in {}, CANNOT addShips: '{}' (expected <role> <count>)", CurrentScriptDescription(), argument);
        return;
    }

    const std::string& roleString = tokens[0];

    int number = oo::str::intValue(tokens[1]);
    if (number < 0) {
        OO_LOG(kOOLogSyntaxAddShips, "***** SCRIPT ERROR: in {}, can't add {} ships -- that's less than zero, y'know..", CurrentScriptDescription(), number);
        return;
    }

    OO_LOG(kOOLogNoteAddShips, "DEBUG: Going to add {} ships with role '{}'", number, roleString);

    while (number--)
        [UNIVERSE witchspaceShipWithPrimaryRole:oo::NSStringFrom(roleString)];
}

- (void)addSystemShips:(id)roles_number_position // called by name (ADR-0043 item 21)
{
    const std::string argument = oo::StdString(roles_number_position);
    const std::vector<std::string> tokens = oo::str::tokens(argument);

    if (tokens.size() != 3) {
        OO_LOG(kOOLogSyntaxAddShips, "***** SCRIPT ERROR: in {}, CANNOT addSystemShips: '{}' (expected <role> <count> <position>)", CurrentScriptDescription(), argument);
        return;
    }

    const std::string& roleString = tokens[0];

    int number = oo::str::intValue(tokens[1]);
    double posn = oo::str::doubleValue(tokens[2]);
    if (number < 0) {
        OO_LOG(kOOLogSyntaxAddShips, "***** SCRIPT ERROR: in {}, can't add {} ships -- that's less than zero, y'know..", CurrentScriptDescription(), number);
        return;
    }

    OO_LOG(kOOLogNoteAddShips, "DEBUG: Going to add {} ships with role '{}' at a point {:.3f} along route1", number, roleString, posn);

    while (number--)
        [UNIVERSE addShipWithRole:oo::NSStringFrom(roleString) nearRouteOneAt:posn];
}

- (void)addShipsAt:(id)roles_number_system_x_y_z // called by name (ADR-0043 item 21)
{
    const std::string argument = oo::StdString(roles_number_system_x_y_z);
    const std::vector<std::string> tokens = oo::str::tokens(argument);

    if (tokens.size() != 6) {
        OO_LOG(kOOLogSyntaxAddShips, "***** SCRIPT ERROR: in {}, CANNOT addShipsAt: '{}' (expected <role> <count> <coordinate-system> <x> <y> <z>)", CurrentScriptDescription(), argument);
        return;
    }

    const std::string& roleString = tokens[0];
    const std::string& systemString = tokens[2];

    HPVector posn = make_HPvector(oo::str::doubleValue(tokens[3]), oo::str::doubleValue(tokens[4]), oo::str::doubleValue(tokens[5]));

    int number = oo::str::intValue(tokens[1]);
    if (number < 1) {
        OO_LOG(kOOLogSyntaxAddShips, "----- WARNING in {}  Tried to add {} ships -- no ship added.", CurrentScriptDescription(), number);
        return;
    }

    OO_LOG(kOOLogNoteAddShips, "DEBUG: Going to add {} ship(s) with role '{}' at point ({:.3f}, {:.3f}, {:.3f}) using system {}", number, roleString, posn.x, posn.y, posn.z, systemString);

    if (![UNIVERSE addShips:number withRole:oo::NSStringFrom(roleString) nearPosition:posn withCoordinateSystem:oo::NSStringFrom(systemString)]) {
        OO_LOG(kOOLogScriptAddShipsFailed, "***** SCRIPT ERROR: in {}, {} could not add {} ships with role \"{}\"", CurrentScriptDescription(), "addShipsAt:", (unsigned)number, roleString);
    }
}

- (void)addShipsAtPrecisely:(id)roles_number_system_x_y_z // called by name (ADR-0043 item 21)
{
    const std::string argument = oo::StdString(roles_number_system_x_y_z);
    const std::vector<std::string> tokens = oo::str::tokens(argument);

    if (tokens.size() != 6) {
        OO_LOG(kOOLogSyntaxAddShips, "***** SCRIPT ERROR: in {},* CANNOT addShipsAtPrecisely: '{}' (expected <role> <count> <coordinate-system> <x> <y> <z>)", CurrentScriptDescription(), argument);
        return;
    }

    const std::string& roleString = tokens[0];
    const std::string& systemString = tokens[2];

    HPVector posn = make_HPvector(oo::str::doubleValue(tokens[3]), oo::str::doubleValue(tokens[4]), oo::str::doubleValue(tokens[5]));

    int number = oo::str::intValue(tokens[1]);
    if (number < 1) {
        OO_LOG(kOOLogSyntaxAddShips, "----- WARNING: in {}, Can't add {} ships -- no ship added.", CurrentScriptDescription(), number);
        return;
    }

    OO_LOG(kOOLogNoteAddShips, "DEBUG: Going to add {} ship(s) with role '{}' precisely at point ({:.3f}, {:.3f}, {:.3f}) using system {}", number, roleString, posn.x, posn.y, posn.z, systemString);

    if (![UNIVERSE addShips:number withRole:oo::NSStringFrom(roleString) atPosition:posn withCoordinateSystem:oo::NSStringFrom(systemString)]) {
        OO_LOG(kOOLogScriptAddShipsFailed, "***** SCRIPT ERROR: in {}, {} could not add {} ships with role '{}'", CurrentScriptDescription(), "addShipsAtPrecisely:", (unsigned)number, roleString);
    }
}

- (void)addShipsWithinRadius:(id)roles_number_system_x_y_z_r // called by name (ADR-0043 item 21)
{
    const std::string argument = oo::StdString(roles_number_system_x_y_z_r);
    const std::vector<std::string> tokens = oo::str::tokens(argument);

    if (tokens.size() != 7) {
        OO_LOG(kOOLogSyntaxAddShips, "***** SCRIPT ERROR: in {}, CANNOT 'addShipsWithinRadius: {}' (expected <role> <count> <coordinate-system> <x> <y> <z> <radius>))", CurrentScriptDescription(), argument);
        return;
    }

    const std::string& roleString = tokens[0];
    int number = oo::str::intValue(tokens[1]);
    const std::string& systemString = tokens[2];
    double x = oo::str::doubleValue(tokens[3]);
    double y = oo::str::doubleValue(tokens[4]);
    double z = oo::str::doubleValue(tokens[5]);
    GLfloat r = (float)oo::str::doubleValue(tokens[6]);
    HPVector posn = make_HPvector(x, y, z);

    if (number < 1) {
        OO_LOG(kOOLogSyntaxAddShips, "----- WARNING: in {}, can't add {} ships -- no ship added.", CurrentScriptDescription(), number);
        return;
    }

    OO_LOG(kOOLogNoteAddShips, "DEBUG: Going to add {} ship(s) with role '{}' within {:.2f} radius about point ({:.3f}, {:.3f}, {:.3f}) using system {}", number, roleString, (double)r, x, y, z, systemString);

    if (![UNIVERSE addShips:number withRole:oo::NSStringFrom(roleString) nearPosition:posn withCoordinateSystem:oo::NSStringFrom(systemString) withinRadius:r]) {
        OO_LOG(kOOLogScriptAddShipsFailed, "***** SCRIPT ERROR :in {}, {} could not add {} ships with role \"{}\"", CurrentScriptDescription(), "addShipsWithinRadius:", (unsigned)number, roleString);
    }
}

- (void)spawnShip:(id)ship_key // called by name (ADR-0043 item 21); shared selector (proposed ADR-0043)
{
    if ([UNIVERSE spawnShip:ship_key]) {
        OO_LOG(kOOLogNoteAddShips, "DEBUG: Spawned ship with shipdata key '{}'.", oo::DescriptionOf(ship_key));
    } else {
        OO_LOG(kOOLogScriptAddShipsFailed, "***** SCRIPT ERROR: in {}, could not spawn ship with shipdata key '{}'.", CurrentScriptDescription(), oo::DescriptionOf(ship_key));
    }
}

- (void)set:(id)missionvariable_value // called by name (ADR-0043 item 21)
{
    const std::string argument = oo::StdString(missionvariable_value);
    std::vector<std::string> tokens = oo::str::tokens(argument);
    std::string missionVariableString;
    std::string valueString;
    BOOL hasMissionPrefix, hasLocalPrefix;

    if (tokens.size() < 2) {
        OO_LOG(kOOLogSyntaxSet, "***** SCRIPT ERROR: in {}, CANNOT SET '{}' (expected mission_variable or local_variable followed by value expression)", CurrentScriptDescription(), argument);
        return;
    }

    missionVariableString = tokens[0];
    valueString = JoinedFrom(tokens, 1);

    hasMissionPrefix = oo::str::hasPrefix(missionVariableString, "mission_");
    hasLocalPrefix = oo::str::hasPrefix(missionVariableString, "local_");

    if (!hasMissionPrefix && !hasLocalPrefix) {
        OO_LOG(kOOLogSyntaxSet, "***** SCRIPT ERROR: in {}, IDENTIFIER '{}' DOES NOT BEGIN WITH 'mission_' or 'local_'", CurrentScriptDescription(), missionVariableString);
        return;
    }

    OO_LOG(kOOLogNoteSet, "DEBUG: script {} is set to {}", missionVariableString, valueString);

    if (hasMissionPrefix) {
        [self cxx_setMissionVariable:oo::PList(valueString) forKey:missionVariableString];
    } else {
        [self setLocalVariable:valueString forKey:missionVariableString andMission:sCurrentMissionKey];
    }
}

- (void)reset:(id)missionvariable // called by name (ADR-0043 item 21)
{
    const std::string missionVariableString = TrimWhitespace(oo::StdString(missionvariable));
    BOOL hasMissionPrefix, hasLocalPrefix;

    hasMissionPrefix = oo::str::hasPrefix(missionVariableString, "mission_");
    hasLocalPrefix = oo::str::hasPrefix(missionVariableString, "local_");

    if (hasMissionPrefix) {
        [self cxx_setMissionVariable:oo::PList() forKey:missionVariableString];
    } else if (hasLocalPrefix) {
        [self setLocalVariable:std::nullopt forKey:missionVariableString andMission:sCurrentMissionKey];
    } else {
        OO_LOG(kOOLogSyntaxReset, "***** SCRIPT ERROR: in {}, IDENTIFIER '{}' DOES NOT BEGIN WITH 'mission_' or 'local_'", CurrentScriptDescription(), missionVariableString);
    }
}

- (void)increment:(id)missionVariableObject // called by name (ADR-0043 item 21)
{
    const std::string missionVariableString = oo::StdString(missionVariableObject);
    BOOL hasMissionPrefix, hasLocalPrefix;
    int value = 0;

    hasMissionPrefix = oo::str::hasPrefix(missionVariableString, "mission_");
    hasLocalPrefix = oo::str::hasPrefix(missionVariableString, "local_");

    if (hasMissionPrefix) {
        value = oo::str::intValue(ConditionString([self cxx_missionVariableForKey:missionVariableString]).value_or(std::string()));
        value++;
        [self cxx_setMissionVariable:oo::PList(oo::str::format("%d", value)) forKey:missionVariableString];
    } else if (hasLocalPrefix) {
        value = oo::str::intValue([self localVariableForKey:missionVariableString andMission:sCurrentMissionKey].value_or(std::string()));
        value++;
        [self setLocalVariable:oo::str::format("%d", value) forKey:missionVariableString andMission:sCurrentMissionKey];
    } else {
        OO_LOG(kOOLogSyntaxIncrement, "***** SCRIPT ERROR: in {}, IDENTIFIER '{}' DOES NOT BEGIN WITH 'mission_' or 'local_'", CurrentScriptDescription(), missionVariableString);
    }
}

- (void)decrement:(id)missionVariableObject // called by name (ADR-0043 item 21)
{
    const std::string missionVariableString = oo::StdString(missionVariableObject);
    BOOL hasMissionPrefix, hasLocalPrefix;
    int value = 0;

    hasMissionPrefix = oo::str::hasPrefix(missionVariableString, "mission_");
    hasLocalPrefix = oo::str::hasPrefix(missionVariableString, "local_");

    if (hasMissionPrefix) {
        value = oo::str::intValue(ConditionString([self cxx_missionVariableForKey:missionVariableString]).value_or(std::string()));
        value--;
        [self cxx_setMissionVariable:oo::PList(oo::str::format("%d", value)) forKey:missionVariableString];
    } else if (hasLocalPrefix) {
        value = oo::str::intValue([self localVariableForKey:missionVariableString andMission:sCurrentMissionKey].value_or(std::string()));
        value--;
        [self setLocalVariable:oo::str::format("%d", value) forKey:missionVariableString andMission:sCurrentMissionKey];
    } else {
        OO_LOG(kOOLogSyntaxDecrement, "***** SCRIPT ERROR: in {}, IDENTIFIER '{}' DOES NOT BEGIN WITH 'mission_' or 'local_'", CurrentScriptDescription(), missionVariableString);
    }
}

- (void)add:(id)missionVariableString_value // called by name (ADR-0043 item 21)
{
    const std::string argument = oo::StdString(missionVariableString_value);
    std::string missionVariableString;
    std::string valueString;
    double value;
    std::vector<std::string> tokens = oo::str::tokens(argument);
    BOOL hasMissionPrefix, hasLocalPrefix;

    if (tokens.size() < 2) {
        OO_LOG(kOOLogSyntaxAdd, "***** SCRIPT ERROR: in {}, CANNOT ADD: '{}'", CurrentScriptDescription(), argument);
        return;
    }

    missionVariableString = tokens[0];
    valueString = JoinedFrom(tokens, 1);

    hasMissionPrefix = oo::str::hasPrefix(missionVariableString, "mission_");
    hasLocalPrefix = oo::str::hasPrefix(missionVariableString, "local_");

    if (hasMissionPrefix) {
        value = oo::str::doubleValue(ConditionString([self cxx_missionVariableForKey:missionVariableString]).value_or(std::string()));
        value += oo::str::doubleValue(valueString);
        [self cxx_setMissionVariable:oo::PList(oo::str::format("%f", value)) forKey:missionVariableString];
    } else if (hasLocalPrefix) {
        value = oo::str::doubleValue([self localVariableForKey:missionVariableString andMission:sCurrentMissionKey].value_or(std::string()));
        value += oo::str::doubleValue(valueString);
        [self setLocalVariable:oo::str::format("%f", value) forKey:missionVariableString andMission:sCurrentMissionKey];
    } else {
        OO_LOG(kOOLogSyntaxAdd, "***** SCRIPT ERROR: in {}, CANNOT ADD: '{}' -- IDENTIFIER '{}' DOES NOT BEGIN WITH 'mission_' or 'local_'", CurrentScriptDescription(), argument, argument);
    }
}

- (void)subtract:(id)missionVariableString_value // called by name (ADR-0043 item 21)
{
    const std::string argument = oo::StdString(missionVariableString_value);
    std::string missionVariableString;
    std::string valueString;
    double value;
    std::vector<std::string> tokens = oo::str::tokens(argument);
    BOOL hasMissionPrefix, hasLocalPrefix;

    if (tokens.size() < 2) {
        OO_LOG(kOOLogSyntaxSubtract, "***** SCRIPT ERROR: in {}, CANNOT SUBTRACT: '{}'", CurrentScriptDescription(), argument);
        return;
    }

    missionVariableString = tokens[0];
    valueString = JoinedFrom(tokens, 1);

    hasMissionPrefix = oo::str::hasPrefix(missionVariableString, "mission_");
    hasLocalPrefix = oo::str::hasPrefix(missionVariableString, "local_");

    if (hasMissionPrefix) {
        value = oo::str::doubleValue(ConditionString([self cxx_missionVariableForKey:missionVariableString]).value_or(std::string()));
        value -= oo::str::doubleValue(valueString);
        [self cxx_setMissionVariable:oo::PList(oo::str::format("%f", value)) forKey:missionVariableString];
    } else if (hasLocalPrefix) {
        value = oo::str::doubleValue([self localVariableForKey:missionVariableString andMission:sCurrentMissionKey].value_or(std::string()));
        value -= oo::str::doubleValue(valueString);
        [self setLocalVariable:oo::str::format("%f", value) forKey:missionVariableString andMission:sCurrentMissionKey];
    } else {
        OO_LOG(kOOLogSyntaxSubtract, "***** SCRIPT ERROR: in {}, CANNOT SUBTRACT: '{}' -- IDENTIFIER '{}' DOES NOT BEGIN WITH 'mission_' or 'local_'", CurrentScriptDescription(), argument, argument);
    }
}

- (void)checkForShips:(id)roleString // called by name (ADR-0043 item 21)
{
    shipsFound = [UNIVERSE countShipsWithPrimaryRole:roleString];
}

- (void)resetScriptTimer
{
    script_time = 0.0;
    script_time_check = SCRIPT_TIMER_INTERVAL;
    script_time_interval = SCRIPT_TIMER_INTERVAL;
}

- (void)addMissionText:(id)textKey // called by name (ADR-0043 item 21)
{
    const std::optional<std::string> key = oo::OptionalString(textKey);

    if (key.has_value() && key == lastTextKey)
        return; // don't repeatedly add the same text
    lastTextKey = key;

    // Replace literal \n in strings with line breaks and perform expansions.
    const std::optional<std::string> text = MissionTextForKey(key.value_or(std::string()));
    if (!key.has_value() || !text.has_value())
        return;
    const std::string expanded = oo::StdString(OOExpandWithOptions(OOStringExpanderDefaultRandomSeed(), kOOExpandBackslashN, oo::NSStringFrom(*text)));

    [self addLiteralMissionText:oo::NSStringOrNil([self replaceVariablesInString:expanded])];
}

- (void)addLiteralMissionText:(id)text // called by name (ADR-0043 item 21)
{
    if (text != nil) {
        GuiDisplayGen* gui = [UNIVERSE gui];

        for (const std::string& para : oo::str::split(oo::StdString(text), "\n")) {
            missionTextRow = [gui cxx_addLongText:para startingAtRow:missionTextRow align:GUI_ALIGN_LEFT];
        }
    }
}

- (void)setMissionChoiceByTextEntry:(BOOL)enable
{
    MyOpenGLView* gameView = [UNIVERSE gameView];
    _missionTextEntry = enable;
    [gameView resetTypedString];
}

- (void)setMissionChoices:(id)choicesKey // called by name (ADR-0043 item 21); choicesKey is a key for a dictionary of
{ // choices/choice phrases in missiontext.plist and also..
    const oo::PList choicesDict = oo::PListFrom([[UNIVERSE missiontext] objectForKey:oo::NSStringFrom(oo::StdString(choicesKey))]);
    if (!choicesDict.isDict() || choicesDict.count() == 0) {
        return;
    }
    [self cxx_setMissionChoicesDictionary:choicesDict];
}

- (void)cxx_setMissionChoicesDictionary:(const oo::PList&)choicesDict
{
    GuiDisplayGen* gui = [UNIVERSE gui];
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
    if ([[self hud] allowBigGui]) {
        end_row = 27;
    }

    // The keys, case-insensitively sorted (a Dict's keys are strings; the bridge form logs and
    // describes any non-string key). The sort is stable over byte order, where the unstable sort
    // started from hash order.
    std::vector<std::string> choiceKeys;
    if (const oo::PList::Dict* choices = choicesDict.getIf<oo::PList::Dict>()) {
        for (const auto& [key, value] : *choices)
            choiceKeys.push_back(key);
    }
    std::stable_sort(choiceKeys.begin(), choiceKeys.end(), [](const std::string& a, const std::string& b) { return oo::str::caseInsensitiveCompare(a, b) < 0; });

    NSInteger keysCount = choiceKeys.size();
    if ((end_row + 1) < choiceKeys.size()) {
        OOLogERR(kOOLogException, @"in mission.runScreen choices: number of choices defined (%zu) is greater than available lines (%zu). Check HUD settings for allowBigGui.", choiceKeys.size(), (end_row + 1));
        keysCount = end_row + 1;
    }

    [gui cxx_setText:std::string() forRow:end_row]; // clears out the 'Press spacebar' message
    [gui cxx_setKey:std::string() forRow:end_row]; // clears the key to enable pollDemoControls to check for a selection
    [gui setSelectableRange:NSMakeRange(0, 0)]; // clears the selectable range
    [UNIVERSE enterGUIViewModeWithMouseInteraction:YES]; // enables mouse selection of the choices list items

    OOGUIRow choicesRow = (end_row + 1) - keysCount;
    std::string choiceText;

    BOOL selectableRowExists = NO;
    NSUInteger firstSelectableRow = end_row;

    for (const std::string& choiceKey : choiceKeys) {
        const oo::PList& choiceValue = *choicesDict.find(choiceKey);
        OOGUIAlignment alignment = GUI_ALIGN_CENTER;
        OOColor* rowColor = [OOColor yellowColor];
        BOOL selectable = YES;
        if (const std::string* text = choiceValue.getIf<std::string>()) {
            choiceText = " " + *text + " ";
        } else if (choiceValue.isDict()) {
            // "%@" of -oo_stringForKey:@"text": a string or a number's text; "(null)" if neither.
            const oo::PList* textValue = choiceValue.find("text");
            const bool hasText = textValue != nullptr && (textValue->isString() || textValue->isNumber());
            choiceText = " " + (hasText ? choiceValue.get<std::string>("text") : std::string("(null)")) + " ";
            const std::string alignmentChoice = choiceValue.get<std::string>("alignment", "CENTER");
            if (alignmentChoice == "LEFT") {
                alignment = GUI_ALIGN_LEFT;
            } else if (alignmentChoice == "RIGHT") {
                alignment = GUI_ALIGN_RIGHT;
            }
            id colorDesc = [choiceOpts objectForKey:@"color"];
            if (oo::PListView(choiceOpts).get<bool>(@"unselectable")) {
                selectable = NO;
            }
            if (colorDesc != nullptr) {
                rowColor = [OOColor colorWithDescription:oo::ObjectFromPList(*colorDesc)];
            } else if (!selectable) // different default
            {
                rowColor = [OOColor darkGrayColor];
            }
        } else {
            continue; // invalid type
        }
        choiceText = oo::StdString(OOExpand(oo::NSStringFrom(choiceText)));
        choiceText = [self replaceVariablesInString:choiceText].value_or(std::string());
        // allow blank rows
        if (choiceText != "  ") {
            [gui cxx_setText:choiceText forRow:choicesRow align:alignment];
            if (selectable) {
                [gui cxx_setKey:choiceKey forRow:choicesRow];
            } else {
                [gui cxx_setKey:oo::StdString(GUI_KEY_SKIP) forRow:choicesRow];
            }
            [gui setColor:rowColor forRow:choicesRow];
            if (selectable && !selectableRowExists) {
                selectableRowExists = YES;
                firstSelectableRow = choicesRow;
            }
        } else {
            [gui cxx_setKey:oo::StdString(GUI_KEY_SKIP) forRow:choicesRow];
        }
        choicesRow++;
        if (choicesRow > (end_row + 1))
            break;
    }

    if (!selectableRowExists) {
        // just in case choices are set but they're all blank.
        [gui cxx_setText:std::optional<std::string>("  ") forRow:end_row align:GUI_ALIGN_CENTER];
        [gui cxx_setKey:std::string() forRow:end_row];
        [gui setColor:[OOColor yellowColor] forRow:end_row];
    }

    [gui setSelectableRange:NSMakeRange((end_row + 1) - keysCount, keysCount)];
    [gui setSelectedRow:firstSelectableRow];

    [self resetMissionChoice];
}

- (void)resetMissionChoice
{
    [self setMissionChoice:nil];
}

- (void)clearMissionScreen
{
    [self setMissionOverlayDescriptor:nil];
    [self setMissionBackgroundDescriptor:nil];
    [self setMissionBackgroundSpecial:nil];
    [self cxx_setMissionTitle:std::nullopt];
    [self setMissionMusic:nil];
    [self showShipModel:nil];
}

- (void)addMissionDestination:(id)destinations // called by name (ADR-0043 item 21)
{
    for (const std::string& token : oo::str::tokens(oo::StdString(destinations))) {
        const int dest = oo::str::intValue(token); // -oo_intAtIndex: of the token
        if (dest < 0 || dest > 255)
            continue;

        [self addMissionDestinationMarker:[self defaultMarker:dest]];
    }
}

- (void)removeMissionDestination:(id)destinations // called by name (ADR-0043 item 21)
{
    for (const std::string& token : oo::str::tokens(oo::StdString(destinations))) {
        const int dest = oo::str::intValue(token);
        if (dest < 0 || dest > 255)
            continue;

        [self removeMissionDestinationMarker:[self defaultMarker:dest]];
    }
}

- (void)showShipModel:(id)role // called by name (ADR-0043 item 21)
{
    const std::string roleString = oo::StdString(role);
    if (roleString == "none" || roleString.empty()) {
        [UNIVERSE removeDemoShips];
        return;
    }

    ShipEntity* ship = [UNIVERSE makeDemoShipWithRole:role spinning:YES];
    OO_LOG(kOOLogNoteShowShipModel, "::::: showShipModel:'{}' ({}) ({})", roleString, oo::DescriptionOf(ship), oo::DescriptionOf([ship name]));
}

- (void)setMissionMusic:(id)value // called by name (ADR-0043 item 21); shared selector (proposed ADR-0043)
{
    // nil and "none" still pass nil on
    [[OOMusicController sharedController] setMissionMusic:IsNoneValue(oo::StdString(value)) ? nil : value];
}

- (std::optional<std::string>)cxx_missionTitle
{
    return _missionTitle;
}

- (void)cxx_setMissionTitle:(const std::optional<std::string>&)value
{
    // (nil matters: the mission screen then falls back to DESC(mission-information))
    _missionTitle = value;
}

// Not declared in the header; called by name (setMissionImage: is whitelisted) (ADR-0043 item 21).
- (void)setMissionImage:(id)value
{
    const std::string imageName = oo::StdString(value);
    if (!IsNoneValue(imageName)) {
        [self setMissionOverlayDescriptor:oo::ObjectFromPList(oo::PList(oo::PList::Dict { { "name", oo::PList(imageName) } }))];
    } else {
        [self setMissionOverlayDescriptor:nil];
    }
}

// called by name (ADR-0043 item 21)
- (void)setMissionBackground:(id)value
{
    const std::string backgroundName = oo::StdString(value);
    if (!IsNoneValue(backgroundName)) {
        [self setMissionBackgroundDescriptor:oo::ObjectFromPList(oo::PList(oo::PList::Dict { { "name", oo::PList(backgroundName) } }))];
    } else {
        [self setMissionBackgroundDescriptor:nil];
    }
}

- (void)setFuelLeak:(id)value // called by name (ADR-0043 item 21)
{
    if (scriptTarget != self) {
        [scriptTarget setFuel:0];
        return;
    }

    fuel_leak_rate = oo::str::doubleValue(oo::StdString(value));
    if (fuel_leak_rate > 0) {
        [self playFuelLeak];
        [UNIVERSE addMessage:DESC(@"danger-fuel-leak") forCount:6];
        OO_LOG(kOOLogNoteFuelLeak, "{}", "FUEL LEAK activated!");
    }
}

- (id)fuelLeakRate_number // called by name (ADR-0043 item 21)
{
    return oo::ObjectFromPList(oo::PList::singleReal((float)([self fuelLeakRate])));
}

- (void)setSunNovaIn:(id)time_value // called by name (ADR-0043 item 21)
{
    double time_until_nova = oo::str::doubleValue(oo::StdString(time_value));
    [[UNIVERSE sun] setGoingNova:YES inTime:time_until_nova];
}

- (void)launchFromStation
{
    // ensure autosave is ready for the next unscripted launch
    if ([UNIVERSE autoSave])
        [UNIVERSE setAutoSaveNow:YES];
    if ([self status] == STATUS_DOCKING)
        [self setStatus:STATUS_DOCKED]; // needed here to prevent the normal update from continuing with docking.
    [self leaveDock:[self dockedStation]];
}

- (void)blowUpStation
{
    StationEntity* mainStation = nil;

    mainStation = [UNIVERSE station];
    if (mainStation != nil) {
        [UNIVERSE unMagicMainStation];
        [mainStation takeEnergyDamage:500000000.0 from:nil becauseOf:nil weaponIdentifier:@""]; // 500 million should do it!
    }
}

- (void)sendAllShipsAway
{
    if (!UNIVERSE)
        return;
    int ent_count = UNIVERSE->n_entities;
    Entity** uni_entities = UNIVERSE->sortedEntities; // grab the public sorted list
    std::vector<Entity*> my_entities(ent_count);
    int i;
    for (i = 0; i < ent_count; i++)
        my_entities[i] = [uni_entities[i] retain]; //	retained

    for (i = 1; i < ent_count; i++) {
        Entity* e1 = my_entities[i];
        if ([e1 isShip]) {
            ShipEntity* se1 = (ShipEntity*)e1;
            int e_class = [e1 scanClass];
            if (((e_class == CLASS_NEUTRAL) || (e_class == CLASS_POLICE) || (e_class == CLASS_MILITARY) || (e_class == CLASS_THARGOID)) && !([se1 isStation] && [se1 maxFlightSpeed] == 0) && // exclude only stations, not carriers.
                [se1 hasHyperspaceMotor]) // exclude non jumping ships. Escorts will still be able to follow a mother.
            {
                AI* se1AI = [se1 getAI];
                [se1 setFuel:MAX(PLAYER_MAX_FUEL, [se1 fuelCapacity])];
                [se1 setAITo:@"exitingTraderAI.plist"]; // lets them return to their previous state after the jump
                [se1AI setState:@"EXIT_SYSTEM"];
                // The following should prevent all ships leaving at once (freezes oolite on slower machines)
                [se1AI setNextThinkTime:[UNIVERSE getTime] + 3 + (ranrot_rand() & 15)];
                [se1 setPrimaryRole:@"oolite-none"]; // prevents new ship from appearing at witchpoint when this one leaves!
            }
        }
    }

    for (i = 0; i < ent_count; i++) {
        [my_entities[i] release]; //	released
    }
}

- (OOPlanetEntity*)addPlanet:(id)planetKey // called by name (ADR-0043 item 21)
{
    OO_LOG(kOOLogNoteAddPlanet, "addPlanet: {}", oo::DescriptionOf(planetKey));

    if (!UNIVERSE)
        return nil;
    // The system properties, once, as an oo::PList (null when there are none).
    const oo::PList dict = oo::PListFrom([[UNIVERSE systemManager] getPropertiesForSystemKey:planetKey]);
    if (dict.isNull()) {
        OO_LOG("script.error.addPlanet.keyNotFound", "***** ERROR: could not find an entry in planetinfo.plist for '{}'", oo::DescriptionOf(planetKey));
        return nil;
    }

    /*- add planet -*/
    // ("%@" of the dictionary: the round trip prints the same description)
    OO_LOG(kOOLogDebugAddPlanet, "DEBUG: initPlanetFromDictionary: {}", oo::DescriptionOf(oo::ObjectFromPList(dict)));
    OOPlanetEntity* planet = [[[OOPlanetEntity alloc] initFromDictionary:dict withAtmosphere:YES andSeed:[[UNIVERSE systemManager] getRandomSeedForCurrentSystem] forSystem:system_id] autorelease];

    Quaternion planetOrientation;
    const oo::PList* orientationValue = dict.find("orientation");
    if (ScanQuaternionFromString(orientationValue != nullptr ? oo::ObjectFromPList(*orientationValue) : nil, &planetOrientation)) {
        [planet setOrientation:planetOrientation];
    }

    const oo::PList* positionValue = dict.find("position");
    if (positionValue == nullptr) {
        OO_LOG("script.error.addPlanet.noPosition", "***** ERROR: you must specify a position for scripted planet '{}' before it can be created", oo::DescriptionOf(planetKey));
        return nil;
    }

    const std::string positionString = ConditionString(*positionValue).value_or(std::string());
    if (oo::str::hasPrefix(positionString, "abs ") && ([UNIVERSE planet] != nil || [UNIVERSE sun] != nil)) {
        OO_LOG_WARN("script.deprecated", "setting {} for {} '{}' in 'abs' inside .plists can cause compatibility issues across Oolite versions. Use coordinates relative to main system objects instead.", "position", "planet", oo::DescriptionOf(planetKey));
    }

    HPVector posn = [UNIVERSE coordinatesFromCoordinateSystemString:oo::NSStringFrom(positionString)];
    if (posn.x || posn.y || posn.z) {
        OO_LOG(kOOLogDebugAddPlanet, "planet position ({:.2f} {:.2f} {:.2f}) derived from {}", posn.x, posn.y, posn.z, positionString);
    } else {
        ScanHPVectorFromString(oo::NSStringFrom(positionString), &posn);
        OO_LOG(kOOLogDebugAddPlanet, "planet position ({:.2f} {:.2f} {:.2f}) derived from {}", posn.x, posn.y, posn.z, positionString);
    }
    [planet setPosition:posn];

    [UNIVERSE addEntity:planet];
    return planet;
}

- (OOPlanetEntity*)addMoon:(id)moonKey // called by name (ADR-0043 item 21)
{
    OO_LOG(kOOLogNoteAddPlanet, "DEBUG: addMoon '{}'", oo::DescriptionOf(moonKey));

    if (!UNIVERSE)
        return nil;
    // The system properties, once, as an oo::PList (null when there are none).
    const oo::PList dict = oo::PListFrom([[UNIVERSE systemManager] getPropertiesForSystemKey:moonKey]);
    if (dict.isNull()) {
        OO_LOG("script.error.addPlanet.keyNotFound", "***** ERROR: could not find an entry in planetinfo.plist for '{}'", oo::DescriptionOf(moonKey));
        return nil;
    }

    /*- add planet -*/
    // ("%@" of the dictionary: the round trip prints the same description)
    OO_LOG(kOOLogDebugAddPlanet, "DEBUG: initMoonFromDictionary: {}", oo::DescriptionOf(oo::ObjectFromPList(dict)));
    OOPlanetEntity* planet = [[[OOPlanetEntity alloc] initFromDictionary:dict withAtmosphere:NO andSeed:[[UNIVERSE systemManager] getRandomSeedForCurrentSystem] forSystem:system_id] autorelease];

    Quaternion planetOrientation;
    const oo::PList* orientationValue = dict.find("orientation");
    if (ScanQuaternionFromString(orientationValue != nullptr ? oo::ObjectFromPList(*orientationValue) : nil, &planetOrientation)) {
        [planet setOrientation:planetOrientation];
    }

    const oo::PList* positionValue = dict.find("position");
    if (positionValue == nullptr) {
        OO_LOG("script.error.addPlanet.noPosition", "***** ERROR: you must specify a position for scripted moon '{}' before it can be created", oo::DescriptionOf(moonKey));
        return nil;
    }

    const std::string positionString = ConditionString(*positionValue).value_or(std::string());
    if (oo::str::hasPrefix(positionString, "abs ") && ([UNIVERSE planet] != nil || [UNIVERSE sun] != nil)) {
        OO_LOG_WARN("script.deprecated", "setting {} for {} '{}' in 'abs' inside .plists can cause compatibility issues across Oolite versions. Use coordinates relative to main system objects instead.", "position", "moon", oo::DescriptionOf(moonKey));
    }

    HPVector posn = [UNIVERSE coordinatesFromCoordinateSystemString:oo::NSStringFrom(positionString)];
    if (posn.x || posn.y || posn.z) {
        OO_LOG(kOOLogDebugAddPlanet, "moon position ({:.2f} {:.2f} {:.2f}) derived from {}", posn.x, posn.y, posn.z, positionString);
    } else {
        ScanHPVectorFromString(oo::NSStringFrom(positionString), &posn);
        OO_LOG(kOOLogDebugAddPlanet, "moon position ({:.2f} {:.2f} {:.2f}) derived from {}", posn.x, posn.y, posn.z, positionString);
    }
    [planet setPosition:posn];

    [UNIVERSE addEntity:planet];
    return planet;
}

- (void)debugOn
{
    oo::log::logger().setDisplay(kOOLogDebugOnMetaClass, true);
    OO_LOG(kOOLogDebugOnOff, "{}", "SCRIPT debug messages ON");
}

- (void)debugOff
{
    OO_LOG(kOOLogDebugOnOff, "{}", "SCRIPT debug messages OFF");
    oo::log::logger().setDisplay(kOOLogDebugOnMetaClass, false);
}

- (void)debugMessage:(id)args // called by name (ADR-0043 item 21)
{
    OO_LOG(kOOLogDebugMessage, "SCRIPT debugMessage: {}", oo::DescriptionOf(args));
}

- (void)playSound:(id)soundName // called by name (ADR-0043 item 21); shared selector (proposed ADR-0043)
{
    [self playLegacyScriptSound:oo::StdString(soundName)];
}

/*-----------------------------------------------------*/

- (void)doMissionCallback
{
    // make sure we don't call the same callback twice
    _missionWithCallback = NO;
    [[OOJavaScriptEngine sharedEngine] runMissionCallback];
}

- (void)clearMissionScreenID
{
    _missionScreenID.reset();
}

- (void)cxx_setMissionScreenID:(const std::optional<std::string>&)msid
{
    _missionScreenID = msid;
}

- (std::optional<std::string>)cxx_missionScreenID
{
    return _missionScreenID;
}

- (void)endMissionScreenAndNoteOpportunity
{
    _missionAllowInterrupt = NO;
    [self clearMissionScreenID];
    // Older scripts might intercept missionScreenEnded first, and call secondary mission screens.
    if (![self doWorldEventUntilMissionScreen:OOJSID("missionScreenEnded")]) {
        // if we're here, no mission screen is running. Opportunity! :)
        [self doWorldEventUntilMissionScreen:OOJSID("missionScreenOpportunity")];
    }
}

- (void)setGuiToMissionScreen
{
    // reset special background as legacy scripts can't use it, and this
    // is only called by legacy scripts
    [self setMissionBackgroundSpecial:nil];
    // likewise exit screen target
    [self setMissionExitScreen:GUI_SCREEN_STATUS];

    [self setGuiToMissionScreenWithCallback:NO];
}

- (void)refreshMissionScreenTextEntry
{
    MyOpenGLView* gameView = [UNIVERSE gameView];
    GuiDisplayGen* gui = [UNIVERSE gui];
    NSUInteger end_row = 21;
    if ([[self hud] allowBigGui]) {
        end_row = 27;
    }

    // The DESC entry is the format (data): ADR-0043 item 19.
    const std::optional<std::string> typed = [gameView cxx_typedString];
    [gui cxx_setText:oo::str::formatRuntime(oo::StdString(DESC(@"mission-screen-text-prompt-@")), { typed.has_value() ? oo::str::FormatArg(*typed) : oo::str::FormatArg::null() }) forRow:end_row align:GUI_ALIGN_LEFT];
    [gui setColor:[OOColor cyanColor] forRow:end_row];

    [gui setShowTextCursor:YES];
    [gui setCurrentRow:end_row];
}

- (void)setGuiToMissionScreenWithCallback:(BOOL)callback
{
    GuiDisplayGen* gui = [UNIVERSE gui];
    OOGUIScreenID oldScreen = gui_screen;
    NSUInteger end_row = 21;
    if ([[self hud] allowBigGui]) {
        end_row = 27;
    }

    // GUI stuff
    {
        [gui clear];
        [gui setTitle:oo::NSStringFrom([self cxx_missionTitle].value_or(oo::StdString(DESC(@"mission-information"))))];

        if (!_missionTextEntry) {
            [gui cxx_setText:oo::OptionalString(DESC(@"press-space-commander")) forRow:end_row align:GUI_ALIGN_CENTER];
            [gui setColor:[OOColor yellowColor] forRow:end_row];
            [gui cxx_setKey:"spacebar" forRow:end_row];
            [gui setShowTextCursor:NO];
        } else {
            [self refreshMissionScreenTextEntry];
        }
        [gui setSelectableRange:NSMakeRange(0, 0)];

        [gui cxx_setForegroundTextureDescriptor:oo::PListFrom([self missionOverlayDescriptorOrDefault])];
        [gui cxx_setBackgroundTextureDescriptor:oo::PListFrom([self missionBackgroundDescriptorOrDefault])];
        // must set special second as setting the descriptor resets it
        BOOL overridden = ([self missionBackgroundDescriptor] != nil);
        [gui setBackgroundTextureSpecial:[self missionBackgroundSpecial] withBackground:!overridden];
    }
    /* ends */

    missionTextRow = 1;

    if (gui)
        gui_screen = GUI_SCREEN_MISSION;

    lastTextKey.reset();

    [[OOMusicController sharedController] playMissionMusic];

    // the following are necessary...
    [UNIVERSE enterGUIViewModeWithMouseInteraction:NO];
    _missionWithCallback = callback;
    _missionAllowInterrupt = NO;
    [self noteGUIDidChangeFrom:oldScreen to:gui_screen];
}

- (void)cxx_setBackgroundFromDescriptionsKey:(const std::string&)d_key
{
    const oo::PList items = oo::PListFrom([[UNIVERSE descriptions] objectForKey:oo::NSStringFrom(d_key)]);
    //
    if (items.isNull())
        return;
    //
    [self addScene:items atOffset:kZeroVector];
    //
    [self setShowDemoShips:YES];
}

- (void)addScene:(const oo::PList&)items atOffset:(Vector)off
{
    const oo::PList::Array* itemArray = items.getIf<oo::PList::Array>();
    if (itemArray == nullptr)
        return;

    for (const oo::PList& item : *itemArray) {
        if (const std::string* itemString = item.getIf<std::string>()) {
            [self processSceneString:*itemString atOffset:off];
        } else if (item.isArray()) {
            [self addScene:item atOffset:off];
        } else if (item.isDict()) {
            [self processSceneDictionary:item atOffset:off];
        }
    }
}

- (BOOL)processSceneDictionary:(const oo::PList&)couplet atOffset:(Vector)off
{
    const oo::PList* conditions = couplet.find("conditions");
    oo::PList actions;
    if (const oo::PList* doActions = couplet.find("do"))
        actions = oo::PList(oo::PList::Array { *doActions });
    oo::PList else_actions;
    if (const oo::PList* elseActions = couplet.find("else"))
        else_actions = oo::PList(oo::PList::Array { *elseActions });
    BOOL success = YES;
    // ("%@" of the dictionaries: their round-tripped descriptions, the same text)
    if (conditions == nullptr) {
        OO_LOG("script.scene.couplet.badConditions", "***** SCENE ERROR: {} - conditions not {}, returning {}.", oo::DescriptionOf(oo::ObjectFromPList(couplet)), " found", "YES and performing 'do' actions");
    } else {
        if (!conditions->isArray()) {
            OO_LOG("script.scene.couplet.badConditions", "***** SCENE ERROR: {} - conditions not {}, returning {}.", oo::DescriptionOf(oo::ObjectFromPList(*conditions)), "an array", "NO");
            return NO;
        }
    }

    // check conditions..
    success = TestScriptConditions(OOSanitizeLegacyScriptConditions(conditions != nullptr ? *conditions : oo::PList(), "<scene dictionary conditions>"));

    // perform successful actions...
    if ((success) && actions.count())
        [self addScene:actions atOffset:off];

    // perform unsuccessful actions
    if ((!success) && else_actions.count())
        [self addScene:else_actions atOffset:off];

    return success;
}

- (BOOL)processSceneString:(const std::string&)item atOffset:(Vector)off
{
    Vector model_p0;
    Quaternion model_q;

    const std::vector<std::string> i_info = oo::str::tokens(item);
    if (i_info.empty())
        return NO; // (nil returned NO; an all-blank string raised on -objectAtIndex:0)
    const std::string i_key = oo::str::lowercase(i_info[0]);

    // ("%@" of the token array: the same description)
    OO_LOG(kOOLogNoteProcessSceneString, "..... processing {} ({})", oo::DescriptionOf(oo::NSArrayFromStrings(i_info)), i_key);

    // tokens [from, from + count) joined by " ", as -subarrayWithRange: then -componentsJoinedByString:@" "
    auto joined = [&i_info](std::size_t from, std::size_t count) {
        std::string result;
        for (std::size_t i = from; i < from + count; i++) {
            if (i != from)
                result += " ";
            result += i_info[i];
        }
        return result;
    };

    //
    // recursively add further scenes:
    //
    if (i_key == "scene") {
        if (i_info.size() != 5) // must be scene_key_x_y_z
            return NO; //		   0.... 1.. 2 3 4
        const std::string& scene_key = i_info[1];
        Vector scene_offset = { 0 };
        ScanVectorFromString(oo::NSStringFrom(joined(2, 3)), &scene_offset);
        scene_offset.x += off.x;
        scene_offset.y += off.y;
        scene_offset.z += off.z;
        const oo::PList scene_items = oo::PListFrom([[UNIVERSE descriptions] objectForKey:oo::NSStringFrom(scene_key)]);
        OO_LOG(kOOLogDebugProcessSceneStringAddScene, "::::: adding scene: '{}'", scene_key);
        //
        if (!scene_items.isNull()) {
            [self addScene:scene_items atOffset:scene_offset];
            return YES;
        } else
            return NO;
    }
    //
    // Add ship models:
    //
    if (i_key == "ship" || i_key == "model" || i_key == "role") {
        if (i_info.size() != 10) // must be item_name_x_y_z_W_X_Y_Z_align
        {
            return NO; //		   0... 1... 2 3 4 5 6 7 8 9....
        }

        ShipEntity* ship = nil;

        if (i_key == "ship" || i_key == "model") {
            ship = [UNIVERSE newShipWithName:oo::NSStringFrom(i_info[1])];
        } else if (i_key == "role") {
            ship = [UNIVERSE newShipWithRole:oo::NSStringFrom(i_info[1])];
        }
        if (!ship)
            return NO;

        ScanVectorAndQuaternionFromString(oo::NSStringFrom(joined(2, 7)), &model_p0, &model_q);

        Vector model_offset = positionOffsetForShipInRotationToAlignment(ship, model_q, oo::NSStringFrom(i_info[9]));
        model_p0 = vector_add(model_p0, vector_subtract(off, model_offset));

        OO_LOG(kOOLogDebugProcessSceneStringAddModel, "::::: adding model to scene:'{}'", oo::DescriptionOf(ship));
        [ship setOrientation:model_q];
        [ship setPosition:vectorToHPVector(model_p0)];
        [UNIVERSE setMainLightPosition:(Vector) { DEMO_LIGHT_POSITION }]; // set light origin
        [ship setScanClass:CLASS_NO_DRAW];
        [ship switchAITo:@"nullAI.plist"];
        [UNIVERSE addEntity:ship]; // STATUS_IN_FLIGHT, AI state GLOBAL
        [ship setStatus:STATUS_COCKPIT_DISPLAY];
        [ship setRoll:0.0];
        [ship setPitch:0.0];
        [ship setVelocity:kZeroVector];
        [ship setBehaviour:BEHAVIOUR_STOP_STILL];

        [ship release];
        return YES;
    }
    //
    // Add player ship model:
    //
    if (i_key == "player") {
        if (i_info.size() != 9) // must be player_x_y_z_W_X_Y_Z_align
            return NO; //		   0..... 1 2 3 4 5 6 7 8....

        ShipEntity* doppelganger = [UNIVERSE newShipWithName:[self shipDataKey]]; // retain count = 1
        if (!doppelganger)
            return NO;

        ScanVectorAndQuaternionFromString(oo::NSStringFrom(joined(1, 7)), &model_p0, &model_q);

        Vector model_offset = positionOffsetForShipInRotationToAlignment(doppelganger, model_q, oo::NSStringFrom(i_info[8]));
        model_p0.x += off.x - model_offset.x;
        model_p0.y += off.y - model_offset.y;
        model_p0.z += off.z - model_offset.z;

        OO_LOG(kOOLogDebugProcessSceneStringAddModel, "::::: adding model to scene:'{}'", oo::DescriptionOf(doppelganger));
        [doppelganger setOrientation:model_q];
        [doppelganger setPosition:vectorToHPVector(model_p0)];
        [UNIVERSE setMainLightPosition:(Vector) { DEMO_LIGHT_POSITION }]; // set light origin
        [doppelganger setScanClass:CLASS_NO_DRAW];
        [doppelganger switchAITo:@"nullAI.plist"];
        [UNIVERSE addEntity:doppelganger];
        [doppelganger setStatus:STATUS_COCKPIT_DISPLAY];
        [doppelganger setRoll:0.0];
        [doppelganger setPitch:0.0];
        [doppelganger setVelocity:kZeroVector];
        [doppelganger setBehaviour:BEHAVIOUR_STOP_STILL];

        [doppelganger release];
        return YES;
    }
    //
    // Add  planet model: selected via gui-scene-show-planet/-local-planet
    //
    if (i_key == "local-planet" || i_key == "target-planet") {
        if (i_info.size() != 4) // must be xxxxx-planet_x_y_z
            return NO; //		   0........... 1 2 3

        // sunlight position for F7 screen is chosen pseudo randomly from  4 different positions.
        if (info_system_id & 8) {
            _sysInfoLight = (info_system_id & 2) ? (Vector) { -10000.0, 4000.0, -10000.0 } : (Vector) { -12000.0, -5000.0, -10000.0 };
        } else {
            _sysInfoLight = (info_system_id & 2) ? (Vector) { 6000.0, -5000.0, -10000.0 } : (Vector) { 6000.0, 4000.0, -10000.0 };
        }

        [UNIVERSE setMainLightPosition:_sysInfoLight]; // set light origin

#if NEW_PLANETS
        OOPlanetEntity* originalPlanet = nil;
        if (i_key == "local-planet" && [UNIVERSE sun]) {
            originalPlanet = [UNIVERSE planet];
        } else {
            originalPlanet = [[[OOPlanetEntity alloc] initAsMainPlanetForSystem:info_system_id] autorelease];
        }
        OOPlanetEntity* doppelganger = [originalPlanet miniatureVersion];
        if (doppelganger == nil)
            return NO;

#else
        // (the planet info is a mixed configuration: plist data and the texture object, Amendment 2)
        OOPlanetEntity* doppelganger = nil;
        oo::PList planetInfo = oo::PListFrom([UNIVERSE generateSystemData:target_system_seed]);
        if (!planetInfo.isDict())
            planetInfo = oo::PList(oo::PList::Dict { });

        if (i_key == "local-planet" && [UNIVERSE sun]) {
            OOPlanetEntity* mainPlanet = [UNIVERSE planet];
            OOTexture* texture = [mainPlanet texture];
            if (texture != nil) {
                oo::PList::Dict& info = *planetInfo.getIf<oo::PList::Dict>();
                info["_oo_textureObject"] = oo::PListObject(texture);
                info["_oo_isExplicitlyTextured"] = oo::PList((bool)[mainPlanet isExplicitlyTextured]);
                info["mainForLocalSystem"] = oo::PList(true);
                //[planetInfo oo_setQuaternion:[mainPlanet orientation] forKey:@"orientation"]; // the orientation is overwritten later on, without regard for the real planet's orientation.
            }
        }

        doppelganger = [[OOPlanetEntity alloc] initFromDictionary:planetInfo withAtmosphere:YES andSeed:target_system_seed];
        [doppelganger miniaturize];
        [doppelganger autorelease];

        if (doppelganger == nil)
            return NO;
#endif

        ScanVectorFromString(oo::NSStringFrom(joined(1, 3)), &model_p0);

        // miniature radii are roughly between 60 and 120. Place miniatures with a radius bigger than 60 a bit futher away.
        model_p0 = vector_multiply_scalar(model_p0, 1 - 0.5 * ((60 - [doppelganger radius]) / 60));

        model_p0 = vector_add(model_p0, off);

        // TODO: find better quaternion values.
#if NEW_PLANETS
        // Quaternion model_q = { 0.83, 0.365148, 0.182574, 0.0 }; // shows new planets' north pole.
        // Quaternion model_q = { 0.83, -0.365148, 0.182574, 0.0 }; // shows new planets' south pole.
        Quaternion model_q = { 0.83, 0.12, 0.44, 0.0 }; // new planets - default orientation.
#else
        // model_q = make_quaternion( M_SQRT1_2, 0.314, M_SQRT1_2, 0.0 );
        Quaternion model_q = { 0.833492, 0.333396, 0.440611, 0.0 };
#endif
        OO_LOG(kOOLogDebugProcessSceneStringAddMiniPlanet, "::::: adding {} to scene:'{}'", i_key, oo::DescriptionOf(doppelganger));
        [doppelganger setOrientation:model_q];
        // HPVect: mission screen coordinates are small enough that we don't need high-precision for calculations
        [doppelganger setPosition:vectorToHPVector(model_p0)];
        /* MKW - add rotation based on current time
         *     - necessary to duplicate the rotation already performed in PlanetEntity.m since we reset the orientation above. */
        int deltaT = floor(fmod([self clockTimeAdjusted], 86400));
        [doppelganger update:deltaT];
        [UNIVERSE addEntity:doppelganger];

        return YES;
    }

    return NO;
}

- (BOOL)cxx_addEqScriptForKey:(const std::string&)eq_key
{
    const std::optional<std::string> scriptName = oo::OptionalString([[OOEquipmentType equipmentTypeWithIdentifier:oo::NSStringFrom(eq_key)] scriptName]);

    OOLog(@"player.equipmentScript", @"Added equipment %@, with the following script property: '%@'.", oo::NSStringFrom(eq_key), oo::NSStringOrNil(scriptName));

    if (!scriptName.has_value())
        return NO;

    // no duplicates! (eqScripts holds (key, script) pairs)
    if ([self cxx_eqScriptIndexForKey:eq_key] != eqScripts.size())
        return NO;

    // the script's properties: a mixed configuration (Amendment 2)
    oo::PList::Dict properties;
    properties["ship"] = oo::PListObject(self);
    properties["equipmentKey"] = oo::PList(eq_key);
    OOScript* s = [OOScript jsScriptFromFileNamed:oo::NSStringFrom(*scriptName) properties:oo::ObjectFromPList(oo::PList(std::move(properties)))];
    if (s == nil)
        return NO;

    OOLog(@"player.equipmentScript", @"Script '%@': installation %@successful.", oo::NSStringFrom(*scriptName), (s == nil ? @"un" : @""));

    eqScripts.emplace_back(eq_key, oo::ObjCRef<OOJSScript*>(static_cast<OOJSScript*>(s)));
    if (primedEquipment == eqScripts.size() - 1)
        primedEquipment++; // if primed-none, keep it as primed-none.
    OOLog(@"player.equipmentScript", @"Scriptable equipment available: %zu.", eqScripts.size());
    return YES;
}

- (void)cxx_removeEqScriptForKey:(const std::string&)eq_key
{
    NSUInteger i, count = eqScripts.size();

    for (i = 0; i < count; i++) {
        // (count is not updated after a removal: an index past the end read nil, matching nothing)
        if (i < eqScripts.size() && eqScripts[i].first == eq_key) {
            eqScripts.erase(eqScripts.begin() + static_cast<std::ptrdiff_t>(i));

            if (i == primedEquipment)
                primedEquipment = count; // primed-none
            else if (i < primedEquipment)
                primedEquipment--; // track the primed equipment
            if (count == primedEquipment)
                primedEquipment--; // the array has shrunk by one!

            OOLog(@"player.equipmentScript", @"Removed equipment %@, with the following script property: '%@'.", oo::NSStringFrom(eq_key), [[OOEquipmentType equipmentTypeWithIdentifier:oo::NSStringFrom(eq_key)] scriptName]);
        }
    }
}

- (NSUInteger)cxx_eqScriptIndexForKey:(const std::string&)eq_key
{
    NSUInteger i, count = eqScripts.size();

    for (i = 0; i < count; i++) {
        if (eqScripts[i].first == eq_key)
            return i;
    }

    return count;
}

- (void)targetNearestHostile
{
    [self scanForHostiles];
    Entity* ent = [self foundTarget];
    if (ent != nil) {
        ident_engaged = YES;
        missile_status = MISSILE_STATUS_TARGET_LOCKED;
        [self addTarget:ent];
    }
}

- (void)targetNearestIncomingMissile
{
    [self scanForNearestIncomingMissile];
    Entity* ent = [self foundTarget];
    if (ent != nil) {
        ident_engaged = YES;
        missile_status = MISSILE_STATUS_TARGET_LOCKED;
        [self addTarget:ent];
    }
}

- (void)setGalacticHyperspaceBehaviourTo:(id)galacticHyperspaceBehaviourString // called by name (ADR-0043 item 21)
{
    OOGalacticHyperspaceBehaviour ghBehaviour = OOGalacticHyperspaceBehaviourFromString(galacticHyperspaceBehaviourString);
    if (ghBehaviour == GALACTIC_HYPERSPACE_BEHAVIOUR_UNKNOWN) {
        OOLog(@"player.setGalacticHyperspaceBehaviour.invalidInput",
            @"setGalacticHyperspaceBehaviourTo: called with unknown behaviour %@.", galacticHyperspaceBehaviourString);
    }
    [self setGalacticHyperspaceBehaviour:ghBehaviour];
}

- (void)setGalacticHyperspaceFixedCoordsTo:(id)galacticHyperspaceFixedCoordsString // called by name (ADR-0043 item 21)
{
    const oo::PList coord_vals = TokenArray(oo::str::tokens(oo::StdString(galacticHyperspaceFixedCoordsString)));
    if (coord_vals.count() < 2) // Will be 0 if string is nil
    {
        OOLog(@"player.setGalacticHyperspaceFixedCoords.invalidInput", @"%@",
            @"setGalacticHyperspaceFixedCoords: called with bad specifier. Defaulting to Oolite standard.");
        galacticHyperspaceFixedCoords.x = galacticHyperspaceFixedCoords.y = 0x60;
    }

    [self setGalacticHyperspaceFixedCoordsX:coord_vals.at<unsigned char>(0)
                                          y:coord_vals.at<unsigned char>(1)];
}

@end

std::string cxx_OOComparisonTypeToString(OOComparisonType type)
{
    switch (type) {
    case COMPARISON_EQUAL:
        return "equal";
    case COMPARISON_NOTEQUAL:
        return "notequal";
    case COMPARISON_LESSTHAN:
        return "lessthan";
    case COMPARISON_GREATERTHAN:
        return "greaterthan";
    case COMPARISON_ONEOF:
        return "oneof";
    case COMPARISON_UNDEFINED:
        return "undefined";
    }
    return "<error: invalid comparison type>";
}
