/*

OOAIStateMachineVerifierStage.m


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

#include "OOAIStateMachineVerifierStage.h"
#include "OOPListParsing.h"

#if OO_OXP_VERIFIER_ENABLED

#include "ResourceManager.h"

#include "oofnd/Scanner.hpp"
#include "oofnd/String.hpp"

static const char* const kStageName = "Validating AIs";

namespace {

// OODictionaryFromFile (OOPListParsing's bridge) as a property list: the file's
// property list when it is a dictionary, a null PList otherwise (its plist.wrongType log line,
// which named the Foundation class, is not kept).
oo::PList PListDictionaryFromFile(const std::string& path)
{
    oo::PList result = cxx_OOPropertyListFromFile(path);
    return result.isDict() ? result : oo::PList();
}

// Adding to a set kept as a sorted vector; false if it was already there.
bool AddString(std::vector<std::string>& set, const std::string& string)
{
    const auto where = std::lower_bound(set.begin(), set.end(), string);
    if (where != set.end() && *where == string)
        return false;
    set.insert(where, string);
    return true;
}

bool ContainsString(const std::vector<std::string>& set, const std::string& string)
{
    return std::binary_search(set.begin(), set.end(), string);
}

std::vector<std::string> SortedCaseInsensitively(std::vector<std::string> strings)
{
    std::stable_sort(strings.begin(), strings.end(), [](const std::string& a, const std::string& b) {
        return oo::str::caseInsensitiveCompare(a, b) < 0;
    });
    return strings;
}

} // namespace

std::optional<std::string> OOAIStateMachineVerifierStage::name()
{
    return kStageName;
}

bool OOAIStateMachineVerifierStage::shouldRun()
{
    return !_usedAIs.empty();
}

void OOAIStateMachineVerifierStage::run()
{
    // Build whitelist. Note that we merge in aliases since the distinction doesn't matter when just validating.
    const oo::PList whitelist = ResourceManager::whitelistDictionary();
    for (const char* key : { "ai_methods", "ai_and_action_methods" }) {
        if (const oo::PList* methods = whitelist.get<oo::PList::Array>(key)) {
            for (const oo::PList& method : *methods->getIf<oo::PList::Array>()) {
                if (const std::string* string = method.getIf<std::string>())
                    AddString(_whitelist, *string);
            }
        }
    }
    if (const oo::PList* aliases = whitelist.get<oo::PList::Dict>("ai_method_aliases")) {
        for (const auto& [alias, value] : *aliases->getIf<oo::PList::Dict>())
            AddString(_whitelist, alias);
    }

    for (const std::string& aiName : SortedCaseInsensitively(_usedAIs)) {
        validateAI(aiName);
    }

    _whitelist.clear();
}

std::string OOAIStateMachineVerifierStage::nameForReverseDependencyForVerifier(OOOXPVerifier*)
{
    return kStageName;
}

void OOAIStateMachineVerifierStage::stateMachineNamed(const std::string& name, const std::string& shipName)
{
    OOFileScannerVerifierStage* fileScanner = nullptr;

    if (!AddString(_usedAIs, name))
        return;

    fileScanner = static_cast<OOFileScannerVerifierStage*>(verifier()->stageWithName(OOFileScannerVerifierStage::kName));
    if (fileScanner == nullptr || !fileScanner->fileExists(name, "AIs", oo::str::format("shipdata.plist entry \"%s\"", shipName.c_str()), true)) {
        OO_LOG("verifyOXP.validateAI.notFound", "----- WARNING: AI state machine \"{}\" referenced in shipdata.plist entry \"{}\" could not be found in {} or in Oolite.", name, shipName, verifier()->oxpDisplayName().value_or("(null)"));
    }
}

void OOAIStateMachineVerifierStage::validateAI(const std::string& aiName)
{
    std::optional<std::string> path;
    oo::PList aiStateMachine;
    std::vector<std::string> badSelectors; // sorted, no duplicates
    std::string badSelectorDesc;
    NSUInteger index = 0;

    OO_LOG("verifyOXP.verbose.validateAI", "- Validating AI \"{}\".", aiName);
    oo::log::indentIf("verifyOXP.verbose.validateAI");

    // Attempt to load AI.
    OOFileScannerVerifierStage* fileScanner = static_cast<OOFileScannerVerifierStage*>(verifier()->stageWithName(OOFileScannerVerifierStage::kName));
    if (fileScanner != nullptr)
        path = fileScanner->pathForFile(aiName, "AIs", "AI list", false);
    if (!path.has_value())
        return;
    aiStateMachine = PListDictionaryFromFile(*path);
    if (aiStateMachine.isNull()) {
        OO_LOG("verifyOXP.validateAI.failed.notDictPlist", "***** ERROR: could not interpret \"{}\" as a dictionary.", *path);
        return;
    }

    // Validate each state.
    for (const auto& [stateKey, stateHandlers] : *aiStateMachine.getIf<oo::PList::Dict>()) {
        if (!stateHandlers.isDict()) {
            OO_LOG("verifyOXP.validateAI.failed.invalidFormat.state", "***** ERROR: state \"{}\" in AI \"{}\" is not a dictionary.", stateKey, aiName);
            continue;
        }

        // Verify handlers for this state.
        for (const auto& [handlerKey, handlerActions] : *stateHandlers.getIf<oo::PList::Dict>()) {
            if (!handlerActions.isArray()) {
                OO_LOG("verifyOXP.validateAI.failed.invalidFormat.handler", "***** ERROR: handler \"{}\" for state \"{}\" in AI \"{}\" is not an array, ignoring.", handlerKey, stateKey, aiName);
                continue;
            }

            // Verify commands for this handler.
            index = 0;
            for (const oo::PList& actionValue : *handlerActions.getIf<oo::PList::Array>()) {
                index++;
                const std::string* untrimmed = actionValue.getIf<std::string>();
                if (untrimmed == nullptr) {
                    OO_LOG("verifyOXP.validateAI.failed.invalidFormat.action", "***** ERROR: action {} in handler \"{}\" for state \"{}\" in AI \"{}\" is not a string, ignoring.", index - 1, handlerKey, stateKey, aiName);
                    continue;
                }

                // Trim spaces from beginning and end (the whitespace character set, not newlines).
                const std::string action = oo::str::trim(*untrimmed, oo::str::CharacterSet::whitespace());

                // Cut off parameters.
                const std::string selector = action.substr(0, action.find(' '));

                // Check against whitelist.
                if (!ContainsString(_whitelist, selector)) {
                    AddString(badSelectors, selector);
                }
            }
        }
    }

    if (badSelectors.size() != 0) {
        for (const std::string& selector : SortedCaseInsensitively(badSelectors)) {
            if (!badSelectorDesc.empty())
                badSelectorDesc += ", ";
            badSelectorDesc += selector;
        }
        OO_LOG("verifyOXP.validateAI.failed.badSelector", "***** ERROR: the AI \"{}\" uses {} unpermitted method{}: {}", aiName, badSelectors.size(), (badSelectors.size() == 1) ? "" : "s", badSelectorDesc);
    }

    oo::log::outdentIf("verifyOXP.verbose.validateAI");
}

#endif
