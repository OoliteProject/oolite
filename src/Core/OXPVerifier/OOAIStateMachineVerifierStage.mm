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

#import "OOAIStateMachineVerifierStage.h"
#import "OOPListParsing.h"
#import "OOPListView.h"

#if OO_OXP_VERIFIER_ENABLED

#import "OOFoundationBridge.h"
#import "ResourceManager.h"

#include "oofnd/String.hpp"

static const char* const kStageName = "Validating AIs";

namespace {

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

@interface OOAIStateMachineVerifierStage (Private)

- (void)validateAI:(const std::string&)aiName;

@end

@implementation OOAIStateMachineVerifierStage

- (id)name // shared selector (proposed ADR-0043)
{
    return oo::NSStringFrom(kStageName);
}

- (BOOL)shouldRun
{
    return !_usedAIs.empty();
}

- (void)run
{
    // Build whitelist. Note that we merge in aliases since the distinction doesn't matter when just validating.
    const oo::PList whitelist = oo::PListFrom([ResourceManager whitelistDictionary]);
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
        [self validateAI:aiName];
    }

    _whitelist.clear();
}

+ (id)nameForReverseDependencyForVerifier:(OOOXPVerifier*)verifier
{
    return oo::NSStringFrom(kStageName);
}

- (void)stateMachineNamed:(const std::string&)name usedByShip:(const std::string&)shipName
{
    OOFileScannerVerifierStage* fileScanner = nil;

    if (!AddString(_usedAIs, name))
        return;

    fileScanner = [[self verifier] fileScannerStage];
    if (![fileScanner fileExists:oo::NSStringFrom(name)
                        inFolder:@"AIs"
                  referencedFrom:oo::NSStringFrom(oo::str::format("shipdata.plist entry \"%s\"", shipName.c_str()))
                    checkBuiltIn:YES]) {
        OOLog(@"verifyOXP.validateAI.notFound", @"----- WARNING: AI state machine \"%@\" referenced in shipdata.plist entry \"%@\" could not be found in %@ or in Oolite.", oo::NSStringFrom(name), oo::NSStringFrom(shipName), [[self verifier] oxpDisplayName]);
    }
}

@end

@implementation OOAIStateMachineVerifierStage (Private)

- (void)validateAI:(const std::string&)aiName
{
    std::optional<std::string> path;
    oo::PList aiStateMachine;
    std::vector<std::string> badSelectors; // sorted, no duplicates
    std::string badSelectorDesc;
    NSUInteger index = 0;

    OOLog(@"verifyOXP.verbose.validateAI", @"- Validating AI \"%@\".", oo::NSStringFrom(aiName));
    OOLogIndentIf(@"verifyOXP.verbose.validateAI");

    // Attempt to load AI.
    path = oo::OptionalString([[[self verifier] fileScannerStage] pathForFile:oo::NSStringFrom(aiName) inFolder:@"AIs" referencedFrom:@"AI list" checkBuiltIn:NO]);
    if (!path.has_value())
        return;

    aiStateMachine = oo::PListFrom(OODictionaryFromFile(oo::NSStringFrom(*path)));
    if (aiStateMachine.isNull()) {
        OOLog(@"verifyOXP.validateAI.failed.notDictPlist", @"***** ERROR: could not interpret \"%@\" as a dictionary.", oo::NSStringFrom(*path));
        return;
    }

    // Validate each state.
    for (const auto& [stateKey, stateHandlers] : *aiStateMachine.getIf<oo::PList::Dict>()) {
        if (!stateHandlers.isDict()) {
            OOLog(@"verifyOXP.validateAI.failed.invalidFormat.state", @"***** ERROR: state \"%@\" in AI \"%@\" is not a dictionary.", oo::NSStringFrom(stateKey), oo::NSStringFrom(aiName));
            continue;
        }

        // Verify handlers for this state.
        for (const auto& [handlerKey, handlerActions] : *stateHandlers.getIf<oo::PList::Dict>()) {
            if (!handlerActions.isArray()) {
                OOLog(@"verifyOXP.validateAI.failed.invalidFormat.handler", @"***** ERROR: handler \"%@\" for state \"%@\" in AI \"%@\" is not an array, ignoring.", oo::NSStringFrom(handlerKey), oo::NSStringFrom(stateKey), oo::NSStringFrom(aiName));
                continue;
            }

            // Verify commands for this handler.
            index = 0;
            for (const oo::PList& actionValue : *handlerActions.getIf<oo::PList::Array>()) {
                index++;
                const std::string* untrimmed = actionValue.getIf<std::string>();
                if (untrimmed == nullptr) {
                    OOLog(@"verifyOXP.validateAI.failed.invalidFormat.action", @"***** ERROR: action %zu in handler \"%@\" for state \"%@\" in AI \"%@\" is not a string, ignoring.", index - 1, oo::NSStringFrom(handlerKey), oo::NSStringFrom(stateKey), oo::NSStringFrom(aiName));
                    continue;
                }

                // Trim spaces from beginning and end (the whitespace character set, not newlines).
                const std::string action = oo::StdString([oo::NSStringFrom(*untrimmed) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]);

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
        OOLog(@"verifyOXP.validateAI.failed.badSelector", @"***** ERROR: the AI \"%@\" uses %zu unpermitted method%s: %@", oo::NSStringFrom(aiName), badSelectors.size(), (badSelectors.size() == 1) ? "" : "s", oo::NSStringFrom(badSelectorDesc));
    }

    OOLogOutdentIf(@"verifyOXP.verbose.validateAI");
}

@end

#endif
