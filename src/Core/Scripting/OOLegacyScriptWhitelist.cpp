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

#include "OOLegacyScriptWhitelist.h"
#include "OOFoundation.h"
#include "OOStringParsing.h"
#include "PlayerEntityLegacyScriptEngine.h"
#include "ResourceManager.h"

#include "oofnd/PList.hpp"
#include "oofnd/StdLib.hpp"
#include "oofnd/String.hpp"

#define INCLUDE_RAW_STRING OOLITE_DEBUG // If nonzero, raw condition strings are included; if zero, a placeholder is used.

/*	The sanitizer works on oo::PList trees (bead oo-3rb.204, proposed ADR-0043): a sanitized
        script or conditions array is plist data (bools, unsigned integers, strings, nested arrays).
        A null oo::PList stands for nil.
*/

typedef struct SanStackElement SanStackElement;
struct SanStackElement {
    SanStackElement* back;
    std::optional<std::string> key; // Dictionary key; nullopt for arrays.
    NSUInteger index; // Array index if key is nullopt.
};

namespace {
static oo::PList OOSanitizeLegacyScriptInternal(const oo::PList& script, SanStackElement* stack, BOOL allowAIMethods);
static oo::PList OOSanitizeLegacyScriptConditionsInternal(const oo::PList& conditions, SanStackElement* stack);

static oo::PList SanitizeCondition(const std::string& condition, SanStackElement* stack);
static oo::PList SanitizeConditionalStatement(const oo::PList& statement, SanStackElement* stack, BOOL allowAIMethods);
static oo::PList SanitizeActionStatement(const std::string& statement, SanStackElement* stack, BOOL allowAIMethods);
static OOOperationType ClassifyLHSConditionSelector(const std::string& selectorString, std::optional<std::string>* outSanitizedMethod);
static std::optional<std::string> SanitizeQueryMethod(const std::string& selectorString); // Checks aliases and whitelist, returns nullopt if whitelist fails.
static std::optional<std::string> SanitizeActionMethod(const std::string& selectorString, BOOL allowAIMethods); // Checks aliases and whitelist, returns nullopt if whitelist fails.
static oo::PList AlwaysFalseConditions(void);
static BOOL IsAlwaysFalseConditions(const oo::PList& conditions);

static std::string StringFromStack(SanStackElement* topOfStack);
} // namespace

oo::PList OOSanitizeLegacyScript(const oo::PList& script, const std::optional<std::string>& context, BOOL allowAIMethods)
{
    SanStackElement stackRoot = { NULL, context, 0 };
    return OOSanitizeLegacyScriptInternal(script, &stackRoot, allowAIMethods); // a fresh tree, as the deep copy was
}

namespace {
static oo::PList OOSanitizeLegacyScriptInternal(const oo::PList& script, SanStackElement* stack, BOOL allowAIMethods)
{
    oo::PList::Array result;
    NSUInteger index = 0;

    {
        result.reserve(script.count());

        if (const oo::PList::Array* statements = script.getIf<oo::PList::Array>()) {
            for (const oo::PList& statement : *statements) {
                SanStackElement subStack = {
                    stack, std::nullopt, index++
                };

                oo::PList sanitized;
                if (statement.isDict()) {
                    sanitized = SanitizeConditionalStatement(statement, &subStack, allowAIMethods);
                } else if (const std::string* string = statement.getIf<std::string>()) {
                    sanitized = SanitizeActionStatement(*string, &subStack, allowAIMethods);
                } else {
                    OO_LOG("script.syntax.statement.invalidType", "***** SCRIPT ERROR: in {}, statement is of invalid type - expected string or dictionary, got {}.", StringFromStack(stack), oo::typeName(statement.type()));
                }

                if (!sanitized.isNull()) {
                    result.push_back(std::move(sanitized));
                }
            }
        }
    }

    return oo::PList(std::move(result));
}
} // namespace

oo::PList OOSanitizeLegacyScriptConditions(const oo::PList& conditions, const std::optional<std::string>& context)
{
    SanStackElement stackRoot = { NULL, context ? context : std::optional<std::string>("<anonymous conditions>"), 0 };
    return OOSanitizeLegacyScriptConditionsInternal(conditions, &stackRoot); // a copy, as the deep copy was; null = nil
}

namespace {
static oo::PList OOSanitizeLegacyScriptConditionsInternal(const oo::PList& conditions, SanStackElement* stack)
{
    oo::PList::Array result;
    BOOL OK = YES;
    NSUInteger index = 0;

    if (OOLegacyConditionsAreSanitized(conditions) || conditions.isNull())
        return conditions;

    result.reserve(conditions.count());

    if (const oo::PList::Array* conditionArray = conditions.getIf<oo::PList::Array>()) {
        for (const oo::PList& condition : *conditionArray) {
            SanStackElement subStack = {
                stack, std::nullopt, index++
            };

            const std::string* conditionString = condition.getIf<std::string>();
            if (conditionString == nullptr) {
                OO_LOG("script.syntax.condition.notString", "***** SCRIPT ERROR: in {}, bad condition - expected string, got {}; ignoring.", StringFromStack(stack), oo::typeName(condition.type()));
                OK = NO;
                break;
            }

            oo::PList tokens = SanitizeCondition(*conditionString, &subStack);
            if (!tokens.isNull()) {
                result.push_back(std::move(tokens));
            } else {
                OK = NO;
                break;
            }
        }
    }

    if (OK)
        return oo::PList(std::move(result));
    else
        return AlwaysFalseConditions();
}
} // namespace

BOOL OOLegacyConditionsAreSanitized(const oo::PList& conditions)
{
    if (conditions.count() == 0)
        return YES; // Empty array is safe.
    const oo::PList* first = conditions.at(0);
    return first != nullptr && first->isArray();
}

namespace {
static oo::PList SanitizeCondition(const std::string& condition, SanStackElement* stack)
{
    std::vector<std::string> tokens;
    NSUInteger i, tokenCount;
    OOOperationType opType;
    std::string selectorString;
    std::optional<std::string> sanitizedSelectorString;
    std::string comparatorString;
    OOComparisonType comparatorValue;
    oo::PList::Array rhs;
    std::optional<std::string> rhsSelector;
    std::optional<std::string> stringSegment;

    tokens = oo::str::tokens(condition);
    tokenCount = tokens.size();

    if (tokenCount < 1) {
        OO_LOG("script.debug.syntax.scriptCondition.noneSpecified", "***** SCRIPT ERROR: in {}, empty script condition.", StringFromStack(stack));
        return oo::PList();
    }

    // Parse left-hand side.
    selectorString = tokens[0];
    opType = ClassifyLHSConditionSelector(selectorString, &sanitizedSelectorString);
    if (opType >= OP_INVALID) {
        OO_LOG("script.unpermittedMethod", "***** SCRIPT ERROR: in {} (\"{}\"), method \"{}\" not allowed.", StringFromStack(stack), condition, selectorString);
        return oo::PList();
    }

    // Parse operator.
    if (tokenCount > 1) {
        comparatorString = tokens[1];
        if (comparatorString == "equal")
            comparatorValue = COMPARISON_EQUAL;
        else if (comparatorString == "notequal")
            comparatorValue = COMPARISON_NOTEQUAL;
        else if (comparatorString == "lessthan")
            comparatorValue = COMPARISON_LESSTHAN;
        else if (comparatorString == "greaterthan" || comparatorString == "morethan")
            comparatorValue = COMPARISON_GREATERTHAN;
        else if (comparatorString == "oneof")
            comparatorValue = COMPARISON_ONEOF;
        else if (comparatorString == "undefined")
            comparatorValue = COMPARISON_UNDEFINED;
        else {
            OO_LOG("script.debug.syntax.badComparison", "***** SCRIPT ERROR: in {} (\"{}\"), unknown comparison operator \"{}\", will return NO.", StringFromStack(stack), condition, comparatorString);
            return oo::PList();
        }
    } else {
        /*	In the direct interpreter, having no operator resulted in an
                implicit COMPARISON_NO operator, which always evaluated to false.
                Returning NO here causes AlwaysFalseConditions() to be used, which
                has the same effect.
         */
        OO_LOG("script.debug.syntax.noOperator", "----- WARNING: SCRIPT in {} -- No operator in expression \"{}\", will always evaluate as false.", StringFromStack(stack), condition);
        return oo::PList();
    }

    // Check for invalid opType/comparator combinations.
    if (opType == OP_NUMBER && comparatorValue == COMPARISON_UNDEFINED) {
        OO_LOG("script.debug.syntax.invalidOperator", "***** SCRIPT ERROR: in {} (\"{}\"), comparison operator \"{}\" is not valid for {}.", StringFromStack(stack), condition, "undefined", "numbers");
        return oo::PList();
    } else if (opType == OP_BOOL) {
        switch (comparatorValue) {
        // Valid comparators
        case COMPARISON_EQUAL:
        case COMPARISON_NOTEQUAL:
            break;

        default:
            OO_LOG("script.debug.syntax.invalidOperator", "***** SCRIPT ERROR: in {} (\"{}\"), comparison operator \"{}\" is not valid for {}.", StringFromStack(stack), condition, cxx_OOComparisonTypeToString(comparatorValue), "booleans");
            return oo::PList();
        }
    }

    /*	Parse right-hand side. Each token is converted to an array of the
            token and a boolean indicating whether it's a selector.

            This also coalesces non-selector tokens, i.e. whitespace-separated
            string segments.
    */
    if (tokenCount > 2) {
        rhs.reserve(tokenCount - 2);
        for (i = 2; i < tokenCount; i++) {
            const std::string& rhsItem = tokens[i];
            rhsSelector = SanitizeQueryMethod(rhsItem);
            if (rhsSelector) {
                // Method
                if (stringSegment) {
                    // Add stringSegment as a literal token.
                    rhs.push_back(oo::PList(oo::PList::Array { oo::PList(false), oo::PList(*stringSegment) }));
                    stringSegment = std::nullopt;
                }

                rhs.push_back(oo::PList(oo::PList::Array { oo::PList(true), oo::PList(*rhsSelector) }));
            } else {
                // String; append to stringSegment
                if (!stringSegment)
                    stringSegment = rhsItem;
                else
                    stringSegment = *stringSegment + " " + rhsItem;
            }
        }

        if (stringSegment) {
            rhs.push_back(oo::PList(oo::PList::Array { oo::PList(false), oo::PList(*stringSegment) }));
        }
    }

    std::string rawString;
#if INCLUDE_RAW_STRING
    rawString = condition;
#else
    rawString = "<condition>";
#endif

    // opType and comparisonType were +numberWithUnsignedInt:; oo::ObjectFromPList gives back
    // +numberWithUnsignedLongLong: (same value; the consumers read -unsignedIntValue).
    return oo::PList(oo::PList::Array {
        oo::PList::unsignedInteger(opType),
        oo::PList(rawString),
        oo::PList(sanitizedSelectorString ? *sanitizedSelectorString : std::string()),
        oo::PList::unsignedInteger(comparatorValue),
        oo::PList(std::move(rhs)) });
}
} // namespace

namespace {
static oo::PList SanitizeConditionalStatement(const oo::PList& statement, SanStackElement* stack, BOOL allowAIMethods)
{
    oo::PList conditions;
    oo::PList doActions;
    oo::PList elseActions;

    // -oo_arrayForKey: an array value, else nil.
    auto arrayForKey = [&statement](std::string_view key) {
        const oo::PList* value = statement.find(key);
        return (value != nullptr && value->isArray()) ? *value : oo::PList();
    };

    conditions = arrayForKey("conditions");
    if (conditions.isNull()) {
        OO_LOG("script.syntax.noConditions", "***** SCRIPT ERROR: in {}, conditions array contains no \"conditions\" entry, ignoring.", StringFromStack(stack));
        return oo::PList();
    }

    // Sanitize conditions.
    SanStackElement subStack = { stack, std::string("conditions"), 0 };
    conditions = OOSanitizeLegacyScriptConditionsInternal(conditions, &subStack);
    if (conditions.isNull()) {
        return oo::PList();
    }

    // Sanitize do and else.
    if (!IsAlwaysFalseConditions(conditions))
        doActions = arrayForKey("do");
    if (!doActions.isNull()) {
        subStack.key = "do";
        doActions = OOSanitizeLegacyScriptInternal(doActions, &subStack, allowAIMethods);
    }

    elseActions = arrayForKey("else");
    if (!elseActions.isNull()) {
        subStack.key = "else";
        elseActions = OOSanitizeLegacyScriptInternal(elseActions, &subStack, allowAIMethods);
    }

    // If neither does anything, the statment has no effect.
    if (doActions.count() == 0 && elseActions.count() == 0) {
        return oo::PList();
    }

    if (doActions.isNull())
        doActions = oo::PList(oo::PList::Array { });
    if (elseActions.isNull())
        elseActions = oo::PList(oo::PList::Array { });

    return oo::PList(oo::PList::Array { oo::PList(true), std::move(conditions), std::move(doActions), std::move(elseActions) });
}
} // namespace

namespace {
static oo::PList SanitizeActionStatement(const std::string& statement, SanStackElement* stack, BOOL allowAIMethods)
{
    std::vector<std::string> tokens;
    NSUInteger tokenCount;
    std::string rawSelectorString;
    std::optional<std::string> selectorString;
    std::optional<std::string> argument;

    tokens = oo::str::tokens(statement);
    tokenCount = tokens.size();
    if (tokenCount == 0)
        return oo::PList();

    rawSelectorString = tokens[0];
    selectorString = SanitizeActionMethod(rawSelectorString, allowAIMethods);
    if (!selectorString) {
        OO_LOG("script.unpermittedMethod", "***** SCRIPT ERROR: in {} (\"{}\"), method \"{}\" not allowed.", StringFromStack(stack), statement, rawSelectorString);
        return oo::PList();
    }

    if (*selectorString == "doNothing") {
        return oo::PList();
    }

    if (oo::str::hasSuffix(*selectorString, ":")) {
        // Expects an argument
        if (tokenCount == 2) {
            argument = tokens[1];
        } else {
            // The remaining tokens joined by " " ("" when there are none).
            std::string joined;
            for (NSUInteger i = 1; i < tokenCount; i++) {
                if (i != 1)
                    joined += " ";
                joined += tokens[i];
            }
            argument = joined;
        }

        argument = oo::str::replaceOccurrences(*argument, "[credits_number]", "[_oo_legacy_credits_number]");
    }

    // A statement with no argument is (false, selector): +arrayWithObjects: stopped at the nil.
    oo::PList::Array result { oo::PList(false), oo::PList(*selectorString) };
    if (argument)
        result.push_back(oo::PList(*argument));
    return oo::PList(std::move(result));
}
} // namespace

namespace {
static OOOperationType ClassifyLHSConditionSelector(const std::string& selectorString, std::optional<std::string>* outSanitizedSelector)
{
    assert(outSanitizedSelector != NULL);

    *outSanitizedSelector = selectorString;

    // Allow arbitrary mission_foo or local_foo pseudo-selectors.
    if (oo::str::hasPrefix(selectorString, "mission_"))
        return OP_MISSION_VAR;
    if (oo::str::hasPrefix(selectorString, "local_"))
        return OP_LOCAL_VAR;

    // If it's a real method, check against whitelist.
    *outSanitizedSelector = SanitizeQueryMethod(selectorString);
    if (!*outSanitizedSelector) {
        return OP_INVALID;
    }

    // If it's a real method, and in the whitelist, classify by suffix.
    if (oo::str::hasSuffix(selectorString, "_string"))
        return OP_STRING;
    if (oo::str::hasSuffix(selectorString, "_number"))
        return OP_NUMBER;
    if (oo::str::hasSuffix(selectorString, "_bool"))
        return OP_BOOL;

    // If we got here, something's wrong.
    OO_LOG("script.sanitize.unclassifiedSelector", "***** ERROR: Whitelisted query method \"{}\" has no type suffix, treating as invalid.", selectorString);
    return OP_INVALID;
}
} // namespace

namespace {

// The whitelist.plist array under key as a set of its strings (-oo_arrayForKey:, then
// -initWithArray:; a missing key gives an empty set, as +setWithArray:nil did).
std::set<std::string> WhitelistSet(const oo::PList& whitelist, std::string_view key)
{
    std::set<std::string> result;
    const oo::PList* value = whitelist.find(key);
    if (value != nullptr) {
        if (const oo::PList::Array* array = value->getIf<oo::PList::Array>()) {
            for (const oo::PList& element : *array) {
                if (const std::string* string = element.getIf<std::string>())
                    result.insert(*string);
            }
        }
    }
    return result;
}

// The whitelist.plist dictionary under key (-oo_dictionaryForKey:; null if missing).
oo::PList WhitelistDictionary(const oo::PList& whitelist, std::string_view key)
{
    const oo::PList* value = whitelist.find(key);
    return (value != nullptr && value->isDict()) ? *value : oo::PList();
}

// An alias lookup as -oo_stringForKey: did it: a string, or a number's -stringValue; else none.
std::optional<std::string> AliasFor(const oo::PList& aliases, const std::string& selectorString)
{
    const oo::PList* value = aliases.find(selectorString);
    if (value == nullptr || !(value->isString() || value->isNumber()))
        return std::nullopt;
    return aliases.get<std::string>(selectorString);
}

} // namespace

namespace {
static std::optional<std::string> SanitizeQueryMethod(const std::string& selectorString)
{
    static const oo::PList whitelistDictionary = ResourceManager::whitelistDictionary();
    static const std::set<std::string> whitelist = WhitelistSet(whitelistDictionary, "query_methods");
    static const oo::PList aliases = WhitelistDictionary(whitelistDictionary, "query_method_aliases");

    std::optional<std::string> result = selectorString;
    std::optional<std::string> aliasedSelector = AliasFor(aliases, selectorString);
    if (aliasedSelector)
        result = aliasedSelector;

    if (whitelist.find(*result) == whitelist.end())
        result = std::nullopt;

    return result;
}
} // namespace

namespace {
static std::optional<std::string> SanitizeActionMethod(const std::string& selectorString, BOOL allowAIMethods)
{
    static const oo::PList whitelistDictionary = ResourceManager::whitelistDictionary();
    static std::set<std::string> whitelist;
    static std::set<std::string> whitelistWithAI;
    static oo::PList aliases;
    static oo::PList aliasesWithAI;
    static bool inited = false;

    if (!inited) {
        std::set<std::string> actionMethods = WhitelistSet(whitelistDictionary, "action_methods");
        std::set<std::string> aiMethods = WhitelistSet(whitelistDictionary, "ai_methods");
        std::set<std::string> aiAndActionMethods = WhitelistSet(whitelistDictionary, "ai_and_action_methods");

        actionMethods.insert(aiAndActionMethods.begin(), aiAndActionMethods.end());

        whitelist = actionMethods;
        whitelistWithAI = aiMethods;
        whitelistWithAI.insert(actionMethods.begin(), actionMethods.end());

        aliases = WhitelistDictionary(whitelistDictionary, "action_method_aliases");

        // ai_method_aliases overlaid with action_method_aliases: the action entries win, as
        // merging dictionary entriesaliases did.
        aliasesWithAI = WhitelistDictionary(whitelistDictionary, "ai_method_aliases");
        if (!aliasesWithAI.isNull()) {
            if (const oo::PList::Dict* actionAliases = aliases.getIf<oo::PList::Dict>()) {
                oo::PList::Dict* merged = aliasesWithAI.getIf<oo::PList::Dict>();
                for (const auto& [key, value] : *actionAliases)
                    merged->insert_or_assign(key, value);
            }
        } else {
            aliasesWithAI = aliases;
        }

        inited = true;
    }

    std::optional<std::string> result = selectorString;
    std::optional<std::string> aliasedSelector = AliasFor(allowAIMethods ? aliasesWithAI : aliases, selectorString);
    if (aliasedSelector)
        result = aliasedSelector;

    const std::set<std::string>& list = allowAIMethods ? whitelistWithAI : whitelist;
    if (list.find(*result) == list.end())
        result = std::nullopt;

    return result;
}
} // namespace

//	Return a conditions array that always evaluates as false.
namespace {
static oo::PList AlwaysFalseConditions(void)
{
    /*	Upstream bug kept (proposed ADR-0043; goldens decide): the cache is only filled when it is
            already non-nil, so this always returns nil (a null PList). A failed conditions array
            therefore drops its enclosing conditional statement.
    */
    static oo::PList alwaysFalse;
    if (!alwaysFalse.isNull()) {
        alwaysFalse = oo::PList(oo::PList::Array { oo::PList(oo::PList::Array { oo::PList::unsignedInteger(OP_FALSE) }) });
    }

    return alwaysFalse;
}
} // namespace

namespace {
static BOOL IsAlwaysFalseConditions(const oo::PList& conditions)
{
    // -oo_arrayAtIndex:0 (an array element, else nil), then its -oo_unsignedIntAtIndex:0.
    const oo::PList* first = conditions.at(0);
    oo::PList firstCondition = (first != nullptr && first->isArray()) ? *first : oo::PList();
    return firstCondition.at<unsigned int>(0) == OP_FALSE;
}
} // namespace

namespace {
static std::string StringFromStackInternal(SanStackElement* topOfStack)
{
    if (topOfStack == NULL)
        return std::string();

    std::string base = StringFromStackInternal(topOfStack->back);

    std::string string = topOfStack->key ? *topOfStack->key : oo::str::format("%zu", (size_t)topOfStack->index);
    if (base.size() > 0)
        base += ".";

    base += string;

    return base;
}
} // namespace

namespace {
static std::string StringFromStack(SanStackElement* topOfStack)
{
    return StringFromStackInternal(topOfStack);
}
} // namespace
