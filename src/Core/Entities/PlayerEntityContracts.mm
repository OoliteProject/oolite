/*

PlayerEntityContracts.m

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

#import "PlayerEntityContracts.h"
#import "HeadUpDisplay.h"
#import "PlayerEntity.h"
#import "PlayerEntityControls.h"
#import "PlayerEntityLegacyScriptEngine.h"
#import "ProxyPlayerEntity.h"

#import "AI.h"
#import "GuiDisplayGen.h"
#import "MyOpenGLView.h"
#import "OOCharacter.h"
#import "OOColor.h"
#import "OOConstToString.h"
#import "OOEquipmentType.h"
#import "OOJavaScriptEngine.h"
#import "OOShipRegistry.h"
#import "OOStringExpander.h"
#import "OOStringParsing.h"
#import "OOTexture.h"
#import "ShipEntityAI.h"
#import "StationEntity.h"
#import "Universe.h"
#include "oofnd/PList.hpp"
#include "oofnd/String.hpp"
#include "oofnd/objc/OOObjCRef.h"

#include <set>

static unsigned RepForRisk(unsigned risk);

namespace {

// -oo_intForKey: on the reputation dictionary.
int ReputationValue(const oo::PList::Dict& reputation, const std::string& key)
{
    const auto it = reputation.find(key);
    return it != reputation.end() ? oo::PListGet<int>::from(&it->second, 0) : 0;
}

// -oo_stringForKey: where the old code could read nil: a string, or a number's -stringValue;
// nullopt when the key is absent or holds anything else.
std::optional<std::string> OptionalStringForKey(const oo::PList& dict, std::string_view key)
{
    const oo::PList* value = dict.find(key);
    if (value == nullptr || !(value->isString() || value->isNumber()))
        return std::nullopt;
    return dict.get<std::string>(key);
}

// %@ of a string that may be nil, in a runtime format.
oo::str::FormatArg TextArg(const std::optional<std::string>& string)
{
    return string ? oo::str::FormatArg(*string) : oo::str::FormatArg::null();
}

// -oo_doubleForKey: on a record dictionary (0 when absent).
double DoubleForKey(const oo::PList::Dict& dict, const std::string& key)
{
    const auto it = dict.find(key);
    return it != dict.end() ? oo::PListGet<double>::from(&it->second, 0.0) : 0.0;
}

// -oo_setInteger:forKey: / +numberWithInt: (both a signed integer).
void SetReputationValue(oo::PList::Dict& reputation, const std::string& key, int value)
{
    reputation[key] = oo::PList::signedInteger(value);
}

} // namespace

@interface PlayerEntity (ContractsPrivate)

- (OOCreditsQuantity)tradeInValue;
- (std::vector<std::string>)cxx_contractsListFromEntries:(const oo::PList::Array&)contracts_array forCargo:(BOOL)forCargo forParcels:(BOOL)forParcels;

@end

@implementation PlayerEntity (Contracts)

- (std::optional<std::string>)cxx_processEscapePods // removes pods from cargo bay and treats categories of characters carried
{
    unsigned i;
    BOOL added_entry = NO; // to prevent empty lines for slaves and the rare empty report.
    std::string result;
    std::vector<oo::ObjCRef<OOCharacter*>> rescuees;
    // -intValue of the system's government: a string's leading integer, a number truncated, nil 0
    const oo::PList systemData = [UNIVERSE cxx_currentSystemData];
    const oo::PList* governmentValue = systemData.find(KEY_GOVERNMENT);
    OOGovernmentID government = 0;
    if (governmentValue != nullptr && governmentValue->isString())
        government = oo::str::intValue(*governmentValue->getIf<std::string>());
    else if (governmentValue != nullptr)
        government = static_cast<int>(governmentValue->int64Value());
    if ([UNIVERSE inInterstellarSpace])
        government = 1; // equivalent to Feudal. I'm assuming any station in interstellar space is military. -- Ahruman 2008-05-29

    // step through the cargo removing crew from any escape pods
    // No enumerator because we're mutating the array -- Ahruman
    for (i = 0; i < cargo.size(); i++) {
        ShipEntity* cargoItem = cargo[i].get();

        const std::optional<std::vector<oo::ObjCRef<OOCharacter*>>> podCrew = [cargoItem cxx_crew];
        if (podCrew.has_value()) {
            // Has crew -> is escape pod.
            rescuees.insert(rescuees.end(), podCrew->begin(), podCrew->end());
            [cargoItem cxx_setCrew:std::nullopt];
            cargo.erase(cargo.begin() + i);
            i--;
        }
    }

    // step through the rescuees awarding insurance or bounty or adding to slaves
    for (i = 0; i < rescuees.size(); i++) {
        OOCharacter* rescuee = rescuees[i].get();

        if ([rescuee script]) {
            [rescuee doScriptEvent:OOJSID("unloadCharacter")];
        } else if (![rescuee legacyScript].isNull()) {
            [self cxx_runUnsanitizedScriptActions:[rescuee legacyScript]
                                allowingAIMethods:YES
                                  withContextName:oo::str::format("<character \"%s\" script>", [rescuee cxx_name].value_or("(null)").c_str())
                                        forTarget:nil];
        } else if ([rescuee insuranceCredits] && [rescuee legalStatus]) {
            float reward = (5.0 + government) * [rescuee legalStatus];
            float insurance = 10 * [rescuee insuranceCredits];
            if (government > (Ranrot() & 7) || reward >= insurance) {
                // claim bounty for capture, ignore insurance
                result += oo::str::formatRuntime(OO_DESC("capture-reward-for-@@-@-credits-@-alt"),
                    { [rescuee cxx_name].value_or("(null)"), oo::ShortDescriptionOf(rescuee), cxx_OOStringFromDeciCredits(reward, YES, NO), cxx_OOStringFromDeciCredits(insurance, YES, NO) });
                [self cxx_doScriptEvent:OOJSID("playerRescuedEscapePod") withPListArguments:{ oo::PList::unsignedInteger(static_cast<NSUInteger>(reward)), oo::PList("bounty"), [rescuee infoForScripting] }];
            } else {
                // claim insurance reward with reduction of bounty
                result += oo::str::formatRuntime(OO_DESC("rescue-reward-for-@@-@-credits-@-alt"),
                    { [rescuee cxx_name].value_or("(null)"), oo::ShortDescriptionOf(rescuee), cxx_OOStringFromDeciCredits(insurance - reward, YES, NO), cxx_OOStringFromDeciCredits(reward, YES, NO) });
                reward = insurance - reward;
                [self cxx_doScriptEvent:OOJSID("playerRescuedEscapePod") withPListArguments:{ oo::PList::unsignedInteger(static_cast<NSUInteger>(reward)), oo::PList("insurance"), [rescuee infoForScripting] }];
            }
            credits += reward;
            added_entry = YES;
        } else if ([rescuee insuranceCredits]) {
            // claim insurance reward
            result += oo::str::formatRuntime(OO_DESC("rescue-reward-for-@@-@-credits"),
                { [rescuee cxx_name].value_or("(null)"), oo::ShortDescriptionOf(rescuee), cxx_OOStringFromDeciCredits([rescuee insuranceCredits] * 10, YES, NO) });
            credits += 10 * [rescuee insuranceCredits];
            [self cxx_doScriptEvent:OOJSID("playerRescuedEscapePod") withPListArguments:{ oo::PList::unsignedInteger(static_cast<NSUInteger>(10 * [rescuee insuranceCredits])), oo::PList("insurance"), [rescuee infoForScripting] }];

            added_entry = YES;
        } else if ([rescuee legalStatus]) {
            // claim bounty for capture
            float reward = (5.0 + government) * [rescuee legalStatus];
            result += oo::str::formatRuntime(OO_DESC("capture-reward-for-@@-@-credits"),
                { [rescuee cxx_name].value_or("(null)"), oo::ShortDescriptionOf(rescuee), cxx_OOStringFromDeciCredits(reward, YES, NO) });
            credits += reward;
            [self cxx_doScriptEvent:OOJSID("playerRescuedEscapePod") withPListArguments:{ oo::PList::unsignedInteger(static_cast<NSUInteger>(reward)), oo::PList("bounty"), [rescuee infoForScripting] }];
            added_entry = YES;
        } else {
            // sell as slave - increase no. of slaves in manifest
            [shipCommodityData cxx_addQuantity:1 forGood:"slaves"];
            [self cxx_doScriptEvent:OOJSID("playerRescuedEscapePod") withPListArguments:{ oo::PList::unsignedInteger(0), oo::PList("slave"), [rescuee infoForScripting] }];
        }
        if ((i < rescuees.size() - 1) && added_entry)
            result += "\n";
        added_entry = NO;
    }

    [self calculateCurrentCargo];

    return result; // never nil (the old method returned an empty string when nothing was reported)
}

- (std::optional<std::string>)cxx_checkPassengerContracts // returns messages from any passengers whose status have changed
{
    if ([self dockedStation] != [UNIVERSE station]) // only drop off passengers or fulfil contracts at main station
        return std::nullopt;

    // check escape pods...
    // TODO

    std::string result; // each report line ends in "\n" (legacy format-line helper)
    unsigned i;

    // check passenger contracts
    for (i = 0; i < passengers.size(); i++) {
        const oo::PList passenger_info = passengers[i]; // a copy: the entry may be removed below (it was retained)
        const std::optional<std::string> passenger_name = OptionalStringForKey(passenger_info, std::string(PASSENGER_KEY_NAME));
        int dest = passenger_info.get<int>(std::string(CONTRACT_KEY_DESTINATION));
        // the system name can change via script
        const std::optional<std::string> passenger_dest_name = [UNIVERSE cxx_getSystemName:dest];
        int dest_eta = passenger_info.get<double>(std::string(CONTRACT_KEY_ARRIVAL_TIME)) - ship_clock;

        if (system_id == dest) {
            // we've arrived in system!
            if (dest_eta > 0) {
                // and in good time
                long long fee = passenger_info.get<long long>(std::string(CONTRACT_KEY_FEE));
                while ((randf() < 0.75) && (dest_eta > 3600)) // delivered with more than an hour to spare and a decent customer?
                {
                    fee *= 110; // tip + 10%
                    fee /= 100;
                    dest_eta *= 0.5;
                }
                credits += 10 * fee;

                result += oo::str::formatRuntime(OO_DESC("passenger-delivered-okay-@-@-@"), { TextArg(passenger_name), cxx_OOIntCredits(fee), TextArg(passenger_dest_name) }) + "\n";
                if (passenger_info.get<unsigned int>(std::string(CONTRACT_KEY_RISK), 0) > 0) {
                    [self cxx_addRoleToPlayer:"trader-courier+"];
                }

                [self increasePassengerReputation:RepForRisk(passenger_info.get<unsigned int>(std::string(CONTRACT_KEY_RISK), 0))];
                passengers.erase(passengers.begin() + i--);
                [self cxx_doScriptEvent:OOJSID("playerCompletedContract") withPListArguments:{ oo::PList("passenger"), oo::PList("success"), oo::PList::unsignedInteger(static_cast<NSUInteger>(10 * fee)), passenger_info }];
            } else {
                // but we're late!
                long long fee = passenger_info.get<long long>(std::string(CONTRACT_KEY_FEE)) / 2; // halve fare
                while (randf() < 0.5) // maybe halve fare a few times!
                    fee /= 2;
                credits += 10 * fee;

                result += oo::str::formatRuntime(OO_DESC("passenger-delivered-late-@-@-@"), { TextArg(passenger_name), cxx_OOIntCredits(fee), TextArg(passenger_dest_name) }) + "\n";
                if (passenger_info.get<unsigned int>(std::string(CONTRACT_KEY_RISK), 0) > 0) {
                    [self cxx_addRoleToPlayer:"trader-courier+"];
                }

                passengers.erase(passengers.begin() + i--);
                [self cxx_doScriptEvent:OOJSID("playerCompletedContract") withPListArguments:{ oo::PList("passenger"), oo::PList("late"), oo::PList::unsignedInteger(static_cast<NSUInteger>(10 * fee)), passenger_info }];
            }
        } else {
            if (dest_eta < 0) {
                // we've run out of time!
                result += oo::str::formatRuntime(OO_DESC("passenger-failed-@"), { TextArg(passenger_name) }) + "\n";

                [self decreasePassengerReputation:RepForRisk(passenger_info.get<unsigned int>(std::string(CONTRACT_KEY_RISK), 0))];
                passengers.erase(passengers.begin() + i--);
                [self cxx_doScriptEvent:OOJSID("playerCompletedContract") withPListArguments:{ oo::PList("passenger"), oo::PList("failed"), oo::PList::unsignedInteger(static_cast<NSUInteger>(0)), passenger_info }];
            }
        }
    }

    // check parcel contracts
    for (i = 0; i < parcels.size(); i++) {
        const oo::PList parcel_info = parcels[i]; // a copy: the entry may be removed below (it was retained)
        const std::optional<std::string> parcel_name = OptionalStringForKey(parcel_info, std::string(PASSENGER_KEY_NAME));
        int dest = parcel_info.get<int>(std::string(CONTRACT_KEY_DESTINATION));
        int dest_eta = parcel_info.get<double>(std::string(CONTRACT_KEY_ARRIVAL_TIME)) - ship_clock;

        if (system_id == dest) {
            // we've arrived in system!
            if (dest_eta > 0) {
                // and in good time
                long long fee = parcel_info.get<long long>(std::string(CONTRACT_KEY_FEE));
                while ((randf() < 0.75) && (dest_eta > 86400)) // delivered with more than a day to spare and a decent customer?
                {
                    // lower tips than passengers
                    fee *= 110; // tip + 10%
                    fee /= 100;
                    dest_eta *= 0.5;
                }
                credits += 10 * fee;

                result += oo::str::formatRuntime(OO_DESC("parcel-delivered-okay-@-@"), { TextArg(parcel_name), cxx_OOIntCredits(fee) }) + "\n";

                [self increaseParcelReputation:RepForRisk(parcel_info.get<unsigned int>(std::string(CONTRACT_KEY_RISK), 0))];

                parcels.erase(parcels.begin() + i--);
                if (parcel_info.get<unsigned int>(std::string(CONTRACT_KEY_RISK), 0) > 0) {
                    [self cxx_addRoleToPlayer:"trader-courier+"];
                }
                [self cxx_doScriptEvent:OOJSID("playerCompletedContract") withPListArguments:{ oo::PList("parcel"), oo::PList("success"), oo::PList::unsignedInteger(static_cast<NSUInteger>(10 * fee)), parcel_info }];

            } else {
                // but we're late!
                long long fee = parcel_info.get<long long>(std::string(CONTRACT_KEY_FEE)) / 2; // halve fare
                while (randf() < 0.5) // maybe halve fare a few times!
                    fee /= 2;
                credits += 10 * fee;

                result += oo::str::formatRuntime(OO_DESC("parcel-delivered-late-@-@"), { TextArg(parcel_name), cxx_OOIntCredits(fee) }) + "\n";
                if (parcel_info.get<unsigned int>(std::string(CONTRACT_KEY_RISK), 0) > 0) {
                    [self cxx_addRoleToPlayer:"trader-courier+"];
                }
                parcels.erase(parcels.begin() + i--);
                [self cxx_doScriptEvent:OOJSID("playerCompletedContract") withPListArguments:{ oo::PList("parcel"), oo::PList("late"), oo::PList::unsignedInteger(static_cast<NSUInteger>(10 * fee)), parcel_info }];
            }
        } else {
            if (dest_eta < 0) {
                // we've run out of time!
                result += oo::str::formatRuntime(OO_DESC("parcel-failed-@"), { TextArg(parcel_name) }) + "\n";

                [self decreaseParcelReputation:RepForRisk(parcel_info.get<unsigned int>(std::string(CONTRACT_KEY_RISK), 0))];
                parcels.erase(parcels.begin() + i--);
                [self cxx_doScriptEvent:OOJSID("playerCompletedContract") withPListArguments:{ oo::PList("parcel"), oo::PList("failed"), oo::PList::unsignedInteger(static_cast<NSUInteger>(0)), parcel_info }];
            }
        }
    }

    // check cargo contracts
    for (i = 0; i < contracts.size(); i++) {
        const oo::PList contract_info = contracts[i]; // a copy: the entry may be removed below (it was retained)
        const std::optional<std::string> contract_cargo_desc = OptionalStringForKey(contract_info, std::string(CARGO_KEY_DESCRIPTION));
        int dest = contract_info.get<int>(std::string(CONTRACT_KEY_DESTINATION));
        int dest_eta = contract_info.get<double>(std::string(CONTRACT_KEY_ARRIVAL_TIME)) - ship_clock;

        if (system_id == dest) {
            // no longer needed
            // int premium = 10 * oo::PListView(contract_info).get<float>(CONTRACT_KEY_PREMIUM);
            int fee = 10 * contract_info.get<float>(std::string(CONTRACT_KEY_FEE));

            const std::string contract_cargo_type = contract_info.get<std::string>(std::string(CARGO_KEY_TYPE)); // a missing type was nil, which the market read as ""
            int contract_amount = contract_info.get<int>(std::string(CARGO_KEY_AMOUNT));

            int quantity_on_hand = [shipCommodityData cxx_quantityForGood:contract_cargo_type];

            // we've arrived in system!
            if (dest_eta > 0) {
                // and in good time
                if (quantity_on_hand >= contract_amount) {
                    // with the goods too!

                    // remove the goods...
                    [shipCommodityData cxx_removeQuantity:contract_amount forGood:contract_cargo_type];

                    // pay the premium and fee
                    // credits += fee + premium;
                    // not any more: all contracts initially awarded by JS, so fee
                    // is now all that needs to be paid - CIM

                    if ([shipCommodityData cxx_exportLegalityForGood:contract_cargo_type] > 0) {
                        [self cxx_addRoleToPlayer:"trader-smuggler"];
                    } else {
                        [self cxx_addRoleToPlayer:"trader"];
                    }

                    credits += fee;
                    result += oo::str::formatRuntime(OO_DESC("cargo-delivered-okay-@-@"), { TextArg(contract_cargo_desc), cxx_OOCredits(fee) }) + "\n";

                    contracts.erase(contracts.begin() + i--);
                    // repute++
                    // +10 as cargo contracts don't have risk modifiers
                    [self increaseContractReputation:10];
                    [self cxx_doScriptEvent:OOJSID("playerCompletedContract") withPListArguments:{ oo::PList("cargo"), oo::PList("success"), oo::PList::unsignedInteger(static_cast<NSUInteger>(fee)), contract_info }];

                } else {
                    // see if the amount of goods delivered is acceptable

                    float percent_delivered = 100.0 * (float)quantity_on_hand / (float)contract_amount;
                    float acceptable_ratio = 100.0 - 10.0 * system_id / 256.0; // down to 90%

                    if (percent_delivered >= acceptable_ratio) {
                        // remove the goods...
                        [shipCommodityData cxx_setQuantity:0 forGood:contract_cargo_type];

                        // pay the fee
                        int shortfall = 100 - percent_delivered;
                        int payment = percent_delivered * (fee) / 100.0;
                        credits += payment;

                        if ([shipCommodityData cxx_exportLegalityForGood:contract_cargo_type] > 0) {
                            [self cxx_addRoleToPlayer:"trader-smuggler"];
                        } else {
                            [self cxx_addRoleToPlayer:"trader"];
                        }

                        result += oo::str::formatRuntime(OO_DESC("cargo-delivered-short-@-@-d"), { TextArg(contract_cargo_desc), cxx_OOCredits(payment), shortfall }) + "\n";

                        contracts.erase(contracts.begin() + i--);
                        // repute unchanged
                        [self cxx_doScriptEvent:OOJSID("playerCompletedContract") withPListArguments:{ oo::PList("cargo"), oo::PList("short"), oo::PList::unsignedInteger(static_cast<NSUInteger>(payment)), contract_info }];

                    } else {
                        result += oo::str::formatRuntime(OO_DESC("cargo-refused-short-%@"), { TextArg(contract_cargo_desc) }) + "\n";
                        // The player has still time to buy the missing goods elsewhere and fulfil the contract.
                    }
                }
            } else {
                // but we're late!
                result += oo::str::formatRuntime(OO_DESC("cargo-delivered-late-@"), { TextArg(contract_cargo_desc) }) + "\n";

                contracts.erase(contracts.begin() + i--);
                // repute--
                [self decreaseContractReputation:10];
                [self cxx_doScriptEvent:OOJSID("playerCompletedContract") withPListArguments:{ oo::PList("cargo"), oo::PList("late"), oo::PList::unsignedInteger(static_cast<NSUInteger>(0)), contract_info }];
            }
        } else {
            if (dest_eta < 0) {
                // we've run out of time!
                result += oo::str::formatRuntime(OO_DESC("cargo-failed-@"), { TextArg(contract_cargo_desc) }) + "\n";

                contracts.erase(contracts.begin() + i--);
                // repute--
                [self decreaseContractReputation:10];
                [self cxx_doScriptEvent:OOJSID("playerCompletedContract") withPListArguments:{ oo::PList("cargo"), oo::PList("failed"), oo::PList::unsignedInteger(static_cast<NSUInteger>(0)), contract_info }];
            }
        }
    }

    // check passenger_record for expired contracts (only deletes: the key order does not matter)
    std::vector<std::string> names;
    for (const auto& record : passenger_record)
        names.push_back(record.first);
    for (i = 0; i < names.size(); i++) {
        double dest_eta = DoubleForKey(passenger_record, names[i]) - ship_clock;
        if (dest_eta < 0) {
            // check they're not STILL on board
            BOOL on_board = NO;
            unsigned j;
            for (j = 0; j < passengers.size(); j++) {
                const oo::PList* passenger_name = passengers[j].find(std::string(PASSENGER_KEY_NAME)); // -isEqual: to the record's key
                if (passenger_name != nullptr && passenger_name->isString() && *passenger_name->getIf<std::string>() == names[i])
                    on_board = YES;
            }
            if (!on_board) {
                passenger_record.erase(names[i]);
            }
        }
    }

    // check contract_record for expired contracts (only deletes: the key order does not matter)
    std::vector<std::string> ids;
    for (const auto& record : contract_record)
        ids.push_back(record.first);
    for (i = 0; i < ids.size(); i++) {
        double dest_eta = DoubleForKey(contract_record, ids[i]) - ship_clock; // -doubleValue
        if (dest_eta < 0) {
            contract_record.erase(ids[i]);
        }
    }

    // check parcel_record for expired deliveries (only deletes: the key order does not matter)
    std::vector<std::string> parcel_ids;
    for (const auto& record : parcel_record)
        parcel_ids.push_back(record.first);
    for (i = 0; i < parcel_ids.size(); i++) {
        double dest_eta = DoubleForKey(parcel_record, parcel_ids[i]) - ship_clock; // -doubleValue
        if (dest_eta < 0) {
            parcel_record.erase(parcel_ids[i]);
        }
    }

    if (result.empty()) {
        return std::nullopt; // nil: nothing to report
    } else {
        // Should have a trailing \n
        result.pop_back();
    }

    return result;
}

- (OOCargoQuantity)cxx_contractedVolumeForGood:(const std::string&)good
{
    OOCargoQuantity total = 0;
    for (unsigned i = 0; i < contracts.size(); i++) {
        const oo::PList& contract_info = contracts[i];
        if (OptionalStringForKey(contract_info, std::string(CARGO_KEY_TYPE)) == good) {
            total += contract_info.get<NSUInteger>(std::string(CARGO_KEY_AMOUNT));
        }
    }
    return total;
}

- (void)cxx_addMessageToReport:(const std::string&)report
{
    if (!report.empty()) {
        if (dockingReport.empty())
            dockingReport += report;
        else
            dockingReport += "\n\n" + report; // @"\n\n%@"
    }
}

- (oo::PList)reputation
{
    return oo::PList(reputation);
}

- (int)passengerReputation
{
    int good = ReputationValue(reputation, std::string(PASSAGE_GOOD_KEY));
    int bad = ReputationValue(reputation, std::string(PASSAGE_BAD_KEY));
    int unknown = ReputationValue(reputation, std::string(PASSAGE_UNKNOWN_KEY));

    if (unknown > 0)
        unknown = MAX_CONTRACT_REP - (((2 * unknown) + (market_rnd % unknown)) / 3);
    else
        unknown = MAX_CONTRACT_REP;

    return (good + unknown - 3 * bad) / 2; // return a number from -MAX_CONTRACT_REP to +MAX_CONTRACT_REP
}

- (void)increasePassengerReputation:(unsigned)amount
{
    int good = ReputationValue(reputation, std::string(PASSAGE_GOOD_KEY));
    int bad = ReputationValue(reputation, std::string(PASSAGE_BAD_KEY));
    int unknown = ReputationValue(reputation, std::string(PASSAGE_UNKNOWN_KEY));

    for (unsigned i = 0; i < amount; i++) {
        if (bad > 0) {
            // shift a bean from bad to unknown
            bad--;
            if (unknown < MAX_CONTRACT_REP)
                unknown++;
        } else {
            // shift a bean from unknown to good
            if (unknown > 0)
                unknown--;
            if (good < MAX_CONTRACT_REP)
                good++;
        }
    }
    SetReputationValue(reputation, std::string(PASSAGE_GOOD_KEY), good);
    SetReputationValue(reputation, std::string(PASSAGE_BAD_KEY), bad);
    SetReputationValue(reputation, std::string(PASSAGE_UNKNOWN_KEY), unknown);
}

- (void)decreasePassengerReputation:(unsigned)amount
{
    int good = ReputationValue(reputation, std::string(PASSAGE_GOOD_KEY));
    int bad = ReputationValue(reputation, std::string(PASSAGE_BAD_KEY));
    int unknown = ReputationValue(reputation, std::string(PASSAGE_UNKNOWN_KEY));

    for (unsigned i = 0; i < amount; i++) {
        if (good > 0) {
            // shift a bean from good to bad
            good--;
            if (bad < MAX_CONTRACT_REP)
                bad++;
        } else {
            // shift a bean from unknown to bad
            if (unknown > 0)
                unknown--;
            if (bad < MAX_CONTRACT_REP)
                bad++;
        }
    }
    SetReputationValue(reputation, std::string(PASSAGE_GOOD_KEY), good);
    SetReputationValue(reputation, std::string(PASSAGE_BAD_KEY), bad);
    SetReputationValue(reputation, std::string(PASSAGE_UNKNOWN_KEY), unknown);
}

- (int)parcelReputation
{
    int good = ReputationValue(reputation, std::string(PARCEL_GOOD_KEY));
    int bad = ReputationValue(reputation, std::string(PARCEL_BAD_KEY));
    int unknown = ReputationValue(reputation, std::string(PARCEL_UNKNOWN_KEY));

    if (unknown > 0)
        unknown = MAX_CONTRACT_REP - (((2 * unknown) + (market_rnd % unknown)) / 3);
    else
        unknown = MAX_CONTRACT_REP;

    return (good + unknown - 3 * bad) / 2; // return a number from -MAX_CONTRACT_REP to +MAX_CONTRACT_REP
}

- (void)increaseParcelReputation:(unsigned)amount
{
    int good = ReputationValue(reputation, std::string(PARCEL_GOOD_KEY));
    int bad = ReputationValue(reputation, std::string(PARCEL_BAD_KEY));
    int unknown = ReputationValue(reputation, std::string(PARCEL_UNKNOWN_KEY));

    for (unsigned i = 0; i < amount; i++) {
        if (bad > 0) {
            // shift a bean from bad to unknown
            bad--;
            if (unknown < MAX_CONTRACT_REP)
                unknown++;
        } else {
            // shift a bean from unknown to good
            if (unknown > 0)
                unknown--;
            if (good < MAX_CONTRACT_REP)
                good++;
        }
    }
    SetReputationValue(reputation, std::string(PARCEL_GOOD_KEY), good);
    SetReputationValue(reputation, std::string(PARCEL_BAD_KEY), bad);
    SetReputationValue(reputation, std::string(PARCEL_UNKNOWN_KEY), unknown);
}

- (void)decreaseParcelReputation:(unsigned)amount
{
    int good = ReputationValue(reputation, std::string(PARCEL_GOOD_KEY));
    int bad = ReputationValue(reputation, std::string(PARCEL_BAD_KEY));
    int unknown = ReputationValue(reputation, std::string(PARCEL_UNKNOWN_KEY));

    for (unsigned i = 0; i < amount; i++) {
        if (good > 0) {
            // shift a bean from good to bad
            good--;
            if (bad < MAX_CONTRACT_REP)
                bad++;
        } else {
            // shift a bean from unknown to bad
            if (unknown > 0)
                unknown--;
            if (bad < MAX_CONTRACT_REP)
                bad++;
        }
    }
    SetReputationValue(reputation, std::string(PARCEL_GOOD_KEY), good);
    SetReputationValue(reputation, std::string(PARCEL_BAD_KEY), bad);
    SetReputationValue(reputation, std::string(PARCEL_UNKNOWN_KEY), unknown);
}

- (int)contractReputation
{
    int good = ReputationValue(reputation, std::string(CONTRACTS_GOOD_KEY));
    int bad = ReputationValue(reputation, std::string(CONTRACTS_BAD_KEY));
    int unknown = ReputationValue(reputation, std::string(CONTRACTS_UNKNOWN_KEY));

    if (unknown > 0)
        unknown = MAX_CONTRACT_REP - (((2 * unknown) + (market_rnd % unknown)) / 3);
    else
        unknown = MAX_CONTRACT_REP;

    return (good + unknown - 3 * bad) / 2; // return a number from -MAX_CONTRACT_REP to +MAX_CONTRACT_REP
}

- (void)increaseContractReputation:(unsigned)amount
{
    int good = ReputationValue(reputation, std::string(CONTRACTS_GOOD_KEY));
    int bad = ReputationValue(reputation, std::string(CONTRACTS_BAD_KEY));
    int unknown = ReputationValue(reputation, std::string(CONTRACTS_UNKNOWN_KEY));

    for (unsigned i = 0; i < amount; i++) {
        if (bad > 0) {
            // shift a bean from bad to unknown
            bad--;
            if (unknown < MAX_CONTRACT_REP)
                unknown++;
        } else {
            // shift a bean from unknown to good
            if (unknown > 0)
                unknown--;
            if (good < MAX_CONTRACT_REP)
                good++;
        }
    }
    SetReputationValue(reputation, std::string(CONTRACTS_GOOD_KEY), good);
    SetReputationValue(reputation, std::string(CONTRACTS_BAD_KEY), bad);
    SetReputationValue(reputation, std::string(CONTRACTS_UNKNOWN_KEY), unknown);
}

- (void)decreaseContractReputation:(unsigned)amount
{
    int good = ReputationValue(reputation, std::string(CONTRACTS_GOOD_KEY));
    int bad = ReputationValue(reputation, std::string(CONTRACTS_BAD_KEY));
    int unknown = ReputationValue(reputation, std::string(CONTRACTS_UNKNOWN_KEY));

    for (unsigned i = 0; i < amount; i++) {
        if (good > 0) {
            // shift a bean from good to bad
            good--;
            if (bad < MAX_CONTRACT_REP)
                bad++;
        } else {
            // shift a bean from unknown to bad
            if (unknown > 0)
                unknown--;
            if (bad < MAX_CONTRACT_REP)
                bad++;
        }
    }
    SetReputationValue(reputation, std::string(CONTRACTS_GOOD_KEY), good);
    SetReputationValue(reputation, std::string(CONTRACTS_BAD_KEY), bad);
    SetReputationValue(reputation, std::string(CONTRACTS_UNKNOWN_KEY), unknown);
}

- (void)erodeReputation
{
    int c_good = ReputationValue(reputation, std::string(CONTRACTS_GOOD_KEY));
    int c_bad = ReputationValue(reputation, std::string(CONTRACTS_BAD_KEY));
    int c_unknown = ReputationValue(reputation, std::string(CONTRACTS_UNKNOWN_KEY));
    int p_good = ReputationValue(reputation, std::string(PASSAGE_GOOD_KEY));
    int p_bad = ReputationValue(reputation, std::string(PASSAGE_BAD_KEY));
    int p_unknown = ReputationValue(reputation, std::string(PASSAGE_UNKNOWN_KEY));
    int pl_good = ReputationValue(reputation, std::string(PARCEL_GOOD_KEY));
    int pl_bad = ReputationValue(reputation, std::string(PARCEL_BAD_KEY));
    int pl_unknown = ReputationValue(reputation, std::string(PARCEL_UNKNOWN_KEY));

    if (c_unknown < MAX_CONTRACT_REP) {
        if (c_bad > 0)
            c_bad--;
        else {
            if (c_good > 0)
                c_good--;
        }
        c_unknown++;
    }

    if (p_unknown < MAX_CONTRACT_REP) {
        if (p_bad > 0)
            p_bad--;
        else {
            if (p_good > 0)
                p_good--;
        }
        p_unknown++;
    }

    if (pl_unknown < MAX_CONTRACT_REP) {
        if (pl_bad > 0)
            pl_bad--;
        else {
            if (pl_good > 0)
                pl_good--;
        }
        pl_unknown++;
    }

    SetReputationValue(reputation, std::string(CONTRACTS_GOOD_KEY), c_good);
    SetReputationValue(reputation, std::string(CONTRACTS_BAD_KEY), c_bad);
    SetReputationValue(reputation, std::string(CONTRACTS_UNKNOWN_KEY), c_unknown);
    SetReputationValue(reputation, std::string(PASSAGE_GOOD_KEY), p_good);
    SetReputationValue(reputation, std::string(PASSAGE_BAD_KEY), p_bad);
    SetReputationValue(reputation, std::string(PASSAGE_UNKNOWN_KEY), p_unknown);
    SetReputationValue(reputation, std::string(PARCEL_GOOD_KEY), pl_good);
    SetReputationValue(reputation, std::string(PARCEL_BAD_KEY), pl_bad);
    SetReputationValue(reputation, std::string(PARCEL_UNKNOWN_KEY), pl_unknown);
}

/* Update reputation levels in case of change in MAX_CONTRACT_REP */
- (void)normaliseReputation
{
    int c_good = ReputationValue(reputation, std::string(CONTRACTS_GOOD_KEY));
    int c_bad = ReputationValue(reputation, std::string(CONTRACTS_BAD_KEY));
    int c_unknown = ReputationValue(reputation, std::string(CONTRACTS_UNKNOWN_KEY));
    int p_good = ReputationValue(reputation, std::string(PASSAGE_GOOD_KEY));
    int p_bad = ReputationValue(reputation, std::string(PASSAGE_BAD_KEY));
    int p_unknown = ReputationValue(reputation, std::string(PASSAGE_UNKNOWN_KEY));
    int pl_good = ReputationValue(reputation, std::string(PARCEL_GOOD_KEY));
    int pl_bad = ReputationValue(reputation, std::string(PARCEL_BAD_KEY));
    int pl_unknown = ReputationValue(reputation, std::string(PARCEL_UNKNOWN_KEY));

    int c = c_good + c_bad + c_unknown;
    if (c == 0) {
        c_unknown = MAX_CONTRACT_REP;
    } else if (c != MAX_CONTRACT_REP) {
        c_good = c_good * MAX_CONTRACT_REP / c;
        c_bad = c_bad * MAX_CONTRACT_REP / c;
        c_unknown = MAX_CONTRACT_REP - c_good - c_bad;
    }

    int p = p_good + p_bad + p_unknown;
    if (p == 0) {
        p_unknown = MAX_CONTRACT_REP;
    } else if (p != MAX_CONTRACT_REP) {
        p_good = p_good * MAX_CONTRACT_REP / p;
        p_bad = p_bad * MAX_CONTRACT_REP / p;
        p_unknown = MAX_CONTRACT_REP - p_good - p_bad;
    }

    int pl = pl_good + pl_bad + pl_unknown;
    if (pl == 0) {
        pl_unknown = MAX_CONTRACT_REP;
    } else if (pl != MAX_CONTRACT_REP) {
        pl_good = pl_good * MAX_CONTRACT_REP / pl;
        pl_bad = pl_bad * MAX_CONTRACT_REP / pl;
        pl_unknown = MAX_CONTRACT_REP - pl_good - pl_bad;
    }

    SetReputationValue(reputation, std::string(CONTRACTS_GOOD_KEY), c_good);
    SetReputationValue(reputation, std::string(CONTRACTS_BAD_KEY), c_bad);
    SetReputationValue(reputation, std::string(CONTRACTS_UNKNOWN_KEY), c_unknown);
    SetReputationValue(reputation, std::string(PASSAGE_GOOD_KEY), p_good);
    SetReputationValue(reputation, std::string(PASSAGE_BAD_KEY), p_bad);
    SetReputationValue(reputation, std::string(PASSAGE_UNKNOWN_KEY), p_unknown);
    SetReputationValue(reputation, std::string(PARCEL_GOOD_KEY), pl_good);
    SetReputationValue(reputation, std::string(PARCEL_BAD_KEY), pl_bad);
    SetReputationValue(reputation, std::string(PARCEL_UNKNOWN_KEY), pl_unknown);
}

- (BOOL)cxx_addPassenger:(const std::string&)Name start:(unsigned)start destination:(unsigned)Destination eta:(double)eta fee:(double)fee advance:(double)advance risk:(unsigned)risk
{
    // the number kinds the old dictionary held: +numberWithInt:, +numberWithDouble:, +numberWithUnsignedInt:
    const oo::PList passenger_info(oo::PList::Dict {
        { std::string(PASSENGER_KEY_NAME), oo::PList(Name) },
        { std::string(CONTRACT_KEY_START), oo::PList::signedInteger(static_cast<int>(start)) },
        { std::string(CONTRACT_KEY_DESTINATION), oo::PList::signedInteger(static_cast<int>(Destination)) },
        { std::string(CONTRACT_KEY_DEPARTURE_TIME), oo::PList([PLAYER clockTime]) },
        { std::string(CONTRACT_KEY_ARRIVAL_TIME), oo::PList(eta) },
        { std::string(CONTRACT_KEY_FEE), oo::PList(fee) },
        { std::string(CONTRACT_KEY_PREMIUM), oo::PList(advance) },
        { std::string(CONTRACT_KEY_RISK), oo::PList::unsignedInteger(risk) },
    });

    // extra checks, just in case.
    if (passengers.size() >= max_passengers || passenger_record.find(Name) != passenger_record.end())
        return NO;

    if (risk > 1) {
        [self cxx_addRoleToPlayer:"trader-courier+"];
    }

    passengers.push_back(passenger_info);
    passenger_record[Name] = oo::PList(eta); // +numberWithDouble:

    [self cxx_doScriptEvent:OOJSID("playerEnteredContract") withPListArguments:{ oo::PList("passenger"), passenger_info }];

    return YES;
}

- (BOOL)cxx_removePassenger:(const std::string&)Name // removes the first passenger that answers to Name, returns NO if none found
{
    // extra check, just in case.
    if (passengers.empty())
        return NO;

    unsigned i;

    for (i = 0; i < passengers.size(); i++) {
        const std::optional<std::string> this_name = OptionalStringForKey(passengers[i], std::string(PASSENGER_KEY_NAME));

        if (this_name == Name) {
            passengers.erase(passengers.begin() + i);
            passenger_record.erase(Name);
            return YES;
        }
    }

    return NO;
}

- (BOOL)cxx_addParcel:(const std::string&)Name start:(unsigned)start destination:(unsigned)Destination eta:(double)eta fee:(double)fee premium:(double)premium risk:(unsigned)risk
{
    // the number kinds the old dictionary held: +numberWithInt:, +numberWithDouble:, +numberWithUnsignedInt:
    const oo::PList parcel_info(oo::PList::Dict {
        { std::string(PASSENGER_KEY_NAME), oo::PList(Name) },
        { std::string(CONTRACT_KEY_START), oo::PList::signedInteger(static_cast<int>(start)) },
        { std::string(CONTRACT_KEY_DESTINATION), oo::PList::signedInteger(static_cast<int>(Destination)) },
        { std::string(CONTRACT_KEY_DEPARTURE_TIME), oo::PList([PLAYER clockTime]) },
        { std::string(CONTRACT_KEY_ARRIVAL_TIME), oo::PList(eta) },
        { std::string(CONTRACT_KEY_FEE), oo::PList(fee) },
        { std::string(CONTRACT_KEY_PREMIUM), oo::PList(premium) },
        { std::string(CONTRACT_KEY_RISK), oo::PList::unsignedInteger(risk) },
    });

    // extra checks, just in case.
    // FIXME: do we absolutely need this check? can we live
    // with parcels of senders who happen to have the same
    // name? - Nikos 20160527
    // if ([parcel_record objectForKey:Name] != nil) return NO;

    if (risk > 1) {
        [self cxx_addRoleToPlayer:"trader-courier+"];
    }

    parcels.push_back(parcel_info);
    parcel_record[Name] = oo::PList(eta); // +numberWithDouble:

    [self cxx_doScriptEvent:OOJSID("playerEnteredContract") withPListArguments:{ oo::PList("parcel"), parcel_info }];

    return YES;
}

- (BOOL)cxx_removeParcel:(const std::string&)Name // removes the first parcel that answers to Name, returns NO if none found
{
    // extra check, just in case.
    if (parcels.empty())
        return NO;

    unsigned i;

    for (i = 0; i < parcels.size(); i++) {
        const std::optional<std::string> this_name = OptionalStringForKey(parcels[i], std::string(PASSENGER_KEY_NAME));

        if (this_name == Name) {
            parcels.erase(parcels.begin() + i);
            parcel_record.erase(Name);
            return YES;
        }
    }

    return NO;
}

- (BOOL)cxx_awardContract:(unsigned)qty commodity:(const std::string&)type start:(unsigned)start
              destination:(unsigned)Destination
                      eta:(double)eta
                      fee:(double)fee
                  premium:(double)premium
{

    unsigned sr1 = Ranrot() & 0x111111;
    int sr2 = Ranrot() & 0x111111;

    std::string cargo_ID = oo::str::format("%06x-%06x", sr1, sr2);

    if (![[UNIVERSE commodities] cxx_goodDefined:type])
        return NO;
    if (qty < 1)
        return NO;

    // avoid duplicate cargo_IDs
    while (contract_record.find(cargo_ID) != contract_record.end()) {
        sr2++;
        cargo_ID = oo::str::format("%06x-%06x", sr1, sr2);
    }

    // the number kinds the old dictionary held: +numberWithInt:, +numberWithDouble:
    const oo::PList cargo_info(oo::PList::Dict {
        { std::string(CARGO_KEY_ID), oo::PList(cargo_ID) },
        { std::string(CARGO_KEY_TYPE), oo::PList(type) },
        { std::string(CARGO_KEY_AMOUNT), oo::PList::signedInteger(static_cast<int>(qty)) },
        { std::string(CARGO_KEY_DESCRIPTION), oo::PList([UNIVERSE cxx_describeCommodity:type amount:qty].value_or(std::string())) },
        { std::string(CONTRACT_KEY_START), oo::PList::signedInteger(static_cast<int>(start)) },
        { std::string(CONTRACT_KEY_DESTINATION), oo::PList::signedInteger(static_cast<int>(Destination)) },
        { std::string(CONTRACT_KEY_DEPARTURE_TIME), oo::PList([PLAYER clockTime]) },
        { std::string(CONTRACT_KEY_ARRIVAL_TIME), oo::PList(eta) },
        { std::string(CONTRACT_KEY_FEE), oo::PList(fee) },
        { std::string(CONTRACT_KEY_PREMIUM), oo::PList(premium) },
    });

    // check available space

    OOCargoQuantity cargoSpaceRequired = qty;
    OOMassUnit contractCargoUnits = [shipCommodityData massUnitForGood:type]; // shared selector (OOCommodities): an Objective-C string

    if (contractCargoUnits == UNITS_KILOGRAMS)
        cargoSpaceRequired /= 1000;
    if (contractCargoUnits == UNITS_GRAMS)
        cargoSpaceRequired /= 1000000;

    if (cargoSpaceRequired > [self availableCargoSpace])
        return NO;

    [shipCommodityData cxx_addQuantity:qty forGood:type];

    current_cargo = [self cargoQuantityOnBoard];

    // roleWeightFlags entries are signed integers, as +numberWithInt: was
    if ([shipCommodityData cxx_exportLegalityForGood:type] > 0) {
        [self cxx_addRoleToPlayer:"trader-smuggler"];
        roleWeightFlags.insert_or_assign("bought-illegal", oo::PList::signedInteger(1));
    } else {
        [self cxx_addRoleToPlayer:"trader"];
        roleWeightFlags.insert_or_assign("bought-legal", oo::PList::signedInteger(1));
    }

    contracts.push_back(cargo_info);
    contract_record[cargo_ID] = oo::PList(eta); // +numberWithDouble:

    [self cxx_doScriptEvent:OOJSID("playerEnteredContract") withPListArguments:{ oo::PList("cargo"), cargo_info }];

    return YES;
}

- (BOOL)cxx_removeContract:(const std::string&)type destination:(unsigned)dest // removes the first match found, returns NO if none found
{
    if (contracts.empty() || dest > 255)
        return NO;

    if (![[UNIVERSE commodities] cxx_goodDefined:type])
        return NO;

    unsigned i;

    for (i = 0; i < contracts.size(); i++) {
        const oo::PList& contractInfo = contracts[i];
        unsigned cargoDest = contractInfo.get<int>(std::string(CONTRACT_KEY_DESTINATION));
        const std::optional<std::string> cargoType = OptionalStringForKey(contractInfo, std::string(CARGO_KEY_TYPE));

        if (cargoType == type && cargoDest == dest) {
            const std::optional<std::string> cargoID = OptionalStringForKey(contractInfo, std::string(CARGO_KEY_ID));
            if (cargoID)
                contract_record.erase(*cargoID);
            contracts.erase(contracts.begin() + i);
            return YES;
        }
    }

    return NO;
}

- (std::vector<std::string>)cxx_passengerList
{
    return [self cxx_contractsListFromEntries:passengers forCargo:NO forParcels:NO];
}

- (std::vector<std::string>)cxx_parcelList
{
    return [self cxx_contractsListFromEntries:parcels forCargo:NO forParcels:YES];
}

- (std::vector<std::string>)cxx_contractList
{
    return [self cxx_contractsListFromEntries:contracts forCargo:YES forParcels:NO];
}

- (std::vector<std::string>)cxx_contractsListFromEntries:(const oo::PList::Array&)contracts_array forCargo:(BOOL)forCargo forParcels:(BOOL)forParcels
{
    // check  contracts
    std::vector<std::string> result;
    const char* formatString = (forCargo || forParcels) ? "oolite-manifest-item-delivery" : "oolite-manifest-person-travelling";
    unsigned i;
    for (i = 0; i < contracts_array.size(); i++) {
        const oo::PList& contract_info = contracts_array[i];
        const std::optional<std::string> label = OptionalStringForKey(contract_info, forCargo ? std::string(CARGO_KEY_DESCRIPTION) : std::string(PASSENGER_KEY_NAME));
        // the system name can change via script. The following PASSENGER_KEYs are identical to the corresponding CONTRACT_KEYs
        const std::optional<std::string> destination = [UNIVERSE cxx_getSystemName:contract_info.get<int>(std::string(CONTRACT_KEY_DESTINATION))];
        int dest_eta = contract_info.get<double>(std::string(CONTRACT_KEY_ARRIVAL_TIME)) - ship_clock;
        const std::optional<std::string> deadline = [UNIVERSE cxx_shortTimeDescription:dest_eta];

        OOCreditsQuantity fee = contract_info.get<int>(std::string(CONTRACT_KEY_FEE));
        const std::optional<std::string> feeDesc = std::optional<std::string>(cxx_OOIntCredits(fee));

        // cxx_OOExpandKey(formatString, label, destination, deadline, feeDesc), spelled out: the macro
        // names each argument after its expression, so the dictionary of named values is built here.
        oo::PList::Dict arguments;
        if (label)
            arguments["label"] = oo::PList(*label);
        if (destination)
            arguments["destination"] = oo::PList(*destination);
        if (deadline)
            arguments["deadline"] = oo::PList(*deadline);
        if (feeDesc)
            arguments["feeDesc"] = oo::PList(*feeDesc);
        result.push_back(cxx_OOExpandDescriptionString(OOStringExpanderDefaultRandomSeed(), std::string(formatString), oo::PList(std::move(arguments)), oo::PList(), std::nullopt, kOOExpandKey).value_or(std::string()));
    }

    return result;
}

// only use within setGuiToManifestScreen
#define SET_MANIFEST_ROW(obj, color, row) ([self setManifestScreenRow:obj inColor:color forRow:row ofRows:max_rows andOffset:page_offset inMultipage:multi_page])

- (void)setGuiToManifestScreen
{
    OOGUIScreenID oldScreen = gui_screen;

    GuiDisplayGen* gui = [UNIVERSE gui];
    gui_screen = GUI_SCREEN_MANIFEST;
    BOOL guiChanged = (oldScreen != gui_screen);
    if (guiChanged) {
        [gui setStatusPage:0]; // need to do this earlier than the rest
    }

    // GUI stuff
    {
        NSInteger current, max;
        OOColor* subheadColor = [gui cxx_colorFromSetting:cxx_kGuiManifestSubheadColor defaultValue:[OOColor greenColor]];
        OOColor* entryColor = [gui cxx_colorFromSetting:cxx_kGuiManifestEntryColor defaultValue:nil];
        OOColor* scrollColor = [gui cxx_colorFromSetting:cxx_kGuiManifestScrollColor defaultValue:[OOColor greenColor]];
        OOColor* noScrollColor = [gui cxx_colorFromSetting:cxx_kGuiManifestNoScrollColor defaultValue:[OOColor darkGrayColor]];

        const std::vector<std::string> cargoManifest = [self cxx_cargoList];
        const oo::PList missionsList = [self cxx_missionsList]; // strings and arrays of strings
        // Its entries as the Foundation array carried them: a null element was dropped.
        auto nonNull = [](const oo::PList& list) {
            oo::PList::Array result;
            if (const oo::PList::Array* elements = list.getIf<oo::PList::Array>()) {
                for (const oo::PList& element : *elements) {
                    if (!element.isNull())
                        result.push_back(element);
                }
            }
            return result;
        };
        const oo::PList::Array missionsManifest = nonNull(missionsList);

        NSUInteger i = 0;
        NSUInteger max_rows = 20;
        NSUInteger manifestCount = cargoManifest.size();
        NSUInteger cargoRowCount = (manifestCount + 1) / 2;
        OOGUIRow cargoRow = 2;
        OOGUIRow missionsRow = 2;

        OOGUIRow nextPageRow = MANIFEST_SCREEN_ROW_NEXT;
        // show extra lines if no HUD is displayed.
        if ([[self hud] isHidden] || [[self hud] allowBigGui]) {
            max_rows += 7;
            nextPageRow += 7;
        }

        NSUInteger mmRows = 0;
        for (const oo::PList& mmEntry : missionsManifest) {
            if (mmEntry.isString()) {
                ++mmRows;
            } else if (mmEntry.isArray()) {
                mmRows += nonNull(mmEntry).size();
            }
        }

        NSInteger page_offset = 0;
        BOOL multi_page = NO;
        //		NSUInteger total_rows = cargoRowCount + MAX(1U,[passengerManifest count]) + MAX(1U,[contractManifest count]) + mmRows + MAX(1U,[parcelManifest count]) + 5;
        NSUInteger total_rows = cargoRowCount + mmRows + 5;
        if (total_rows > max_rows) {
            max_rows -= 2;
            page_offset = ([gui statusPage] - 1) * max_rows;
            if (page_offset < 0 || (NSUInteger)page_offset >= total_rows) {
                [gui setStatusPage:0];
                page_offset = 0;
            }
            multi_page = YES;
        }

        OOGUITabSettings tab_stops;
        tab_stops[0] = 0;
        tab_stops[1] = 256;
        [gui cxx_overrideTabs:tab_stops from:cxx_kGuiManifestTabs length:3];
        [gui setTabStops:tab_stops];

        // Cargo Manifest
        current_cargo = [self cargoQuantityOnBoard];

        [gui clearAndKeepBackground:!guiChanged];
        [gui cxx_setTitle:OO_DESC("manifest-title")];

        current = current_cargo;
        max = [self maxAvailableCargoSpace];
        const std::string cargoString = cxx_OOExpandKey("oolite-manifest-cargo", current, max).value_or(std::string());
        current = [self cxx_passengerList].size();
        max = max_passengers;
        const std::string cabinString = cxx_OOExpandKey("oolite-manifest-cabins", current, max).value_or(std::string());
        const oo::PList manifestHeader(oo::PList::Array { oo::PList(cargoString), oo::PList(cabinString) });

        SET_MANIFEST_ROW(manifestHeader, entryColor, cargoRow - 1);

        if (manifestCount > 0) {
            for (i = 0; i < cargoRowCount; i++) {
                oo::PList::Array row_info;
                // i is always smaller than manifest_count, no need to test.
                row_info.push_back(oo::PList(cargoManifest[i]));
                if (i + cargoRowCount < manifestCount) {
                    row_info.push_back(oo::PList(cargoManifest[i + cargoRowCount]));
                } else {
                    row_info.push_back(oo::PList(std::string()));
                }
                SET_MANIFEST_ROW(oo::PList(std::move(row_info)), subheadColor, cargoRow + i);
            }
        } else {
            SET_MANIFEST_ROW((oo::PList(OO_DESC("manifest-none"))), subheadColor, cargoRow);
            cargoRowCount = 1;
        }

        missionsRow = cargoRow + cargoRowCount + 1;

        // Missions Manifest
        manifestCount = missionsManifest.size();

        if (manifestCount > 0) {
            if (missionsManifest[0].isString()) {
                // then there's at least one without its own heading
                // to go under the generic 'missions' heading
                SET_MANIFEST_ROW((oo::PList(OO_DESC("manifest-missions"))), entryColor, missionsRow - 1);
            } else {
                missionsRow--;
            }

            NSUInteger mmRow = 0;
            for (i = 0; i < manifestCount; i++) {
                const oo::PList& mmEntry = missionsManifest[i];
                if (mmEntry.isString()) {
                    const std::string mmItem = "\t" + oo::DescriptionOf(mmEntry); // @"\t%@"
                    SET_MANIFEST_ROW(oo::PList(mmItem), subheadColor, missionsRow + mmRow);
                    ++mmRow;
                } else if (mmEntry.isArray()) {
                    BOOL isHeading = YES;
                    for (const oo::PList& mmItem : nonNull(mmEntry)) {
                        if (isHeading) {
                            SET_MANIFEST_ROW(mmItem, entryColor, missionsRow + mmRow);
                        } else {
                            SET_MANIFEST_ROW(oo::PList("\t" + oo::DescriptionOf(mmItem)), subheadColor, missionsRow + mmRow); // @"\t%@"
                        }
                        isHeading = NO;
                        ++mmRow;
                    }
                }
            }
        }

        if (multi_page) {
            OOGUIRow r_start = MANIFEST_SCREEN_ROW_BACK;
            OOGUIRow r_end = nextPageRow;
            if (page_offset > 0) {
                [gui setColor:scrollColor forRow:MANIFEST_SCREEN_ROW_BACK];
                [gui cxx_setKey:std::string(GUI_KEY_OK) forRow:MANIFEST_SCREEN_ROW_BACK];
            } else {
                [gui setColor:noScrollColor forRow:MANIFEST_SCREEN_ROW_BACK];
                r_start = nextPageRow;
            }
            [gui cxx_setArray: { OO_DESC("gui-back"), " <-- " } forRow:MANIFEST_SCREEN_ROW_BACK];

            if (total_rows > max_rows + page_offset) {
                [gui setColor:scrollColor forRow:nextPageRow];
                [gui cxx_setKey:std::string(GUI_KEY_OK) forRow:nextPageRow];
            } else {
                [gui setColor:noScrollColor forRow:nextPageRow];
                r_end = MANIFEST_SCREEN_ROW_BACK;
            }
            [gui cxx_setArray: { OO_DESC("gui-more"), " --> " } forRow:nextPageRow];

            [gui setSelectableRange:NSMakeRange(r_start, r_end + 1 - r_start)];
            [gui setSelectedRow:r_start];
        }

        [gui setShowTextCursor:NO];
    }
    /* ends */

    lastTextKey.reset();

    [self setShowDemoShips:NO];
    [UNIVERSE enterGUIViewModeWithMouseInteraction:NO];

    if (guiChanged) {
        [gui cxx_setForegroundTextureKey:std::optional<std::string>([self status] == STATUS_DOCKED ? "docked_overlay" : "overlay")];
        [gui cxx_setBackgroundTextureKey:"manifest"];
        [self noteGUIDidChangeFrom:oldScreen to:gui_screen];
    }
}

- (void)setManifestScreenRow:(const oo::PList&)object inColor:(OOColor*)color forRow:(OOGUIRow)row ofRows:(OOGUIRow)max_rows andOffset:(OOGUIRow)offset inMultipage:(BOOL)multi
{
    OOGUIRow disp_row = row - offset;
    if (disp_row < 1 || disp_row > max_rows)
        return;
    if (multi)
        disp_row++;
    GuiDisplayGen* gui = [UNIVERSE gui];
    if (const std::string* text = object.getIf<std::string>()) {
        [gui cxx_setText:*text forRow:disp_row];
    } else if (const oo::PList::Array* elements = object.getIf<oo::PList::Array>()) {
        // its string elements; others were skipped
        std::vector<std::string> strings;
        for (const oo::PList& element : *elements) {
            if (const std::string* string = element.getIf<std::string>())
                strings.push_back(*string);
        }
        [gui cxx_setArray:strings forRow:disp_row];
    }
    [gui setColor:color forRow:disp_row];
}

- (void)setGuiToDockingReportScreen
{
    GuiDisplayGen* gui = [UNIVERSE gui];

    OOGUIScreenID oldScreen = gui_screen;
    gui_screen = GUI_SCREEN_REPORT;
    BOOL guiChanged = (oldScreen != gui_screen);

    OOGUIRow i, text_row = 1;

    dockingReport = oo::str::trimWhitespaceAndNewlines(dockingReport);

    // GUI stuff
    {
        [gui clearAndKeepBackground:!guiChanged];
        [gui cxx_setTitle:cxx_OOExpandKey("arrival-report-title")];

        for (i = 1; i <= 18; i++) {
            [gui setColor:[gui cxx_colorFromSetting:std::string(cxx_kGuiDockingReportColor) defaultValue:nil] forRow:21];
        }

        // dockingReport might be a multi-line message

        while ((!dockingReport.empty()) && (text_row < 18)) {
            if (dockingReport.find('\n') != std::string::npos) {
                while ((dockingReport.find('\n') != std::string::npos) && (text_row < 18)) {
                    const std::size_t line_break = dockingReport.find('\n');
                    const std::string line = dockingReport.substr(0, line_break);
                    dockingReport.erase(0, line_break + 1);
                    text_row = [gui cxx_addLongText:line startingAtRow:text_row align:GUI_ALIGN_LEFT];
                }
                dockingReport = oo::str::trimWhitespaceAndNewlines(dockingReport);
            } else {
                text_row = [gui cxx_addLongText:dockingReport startingAtRow:text_row align:GUI_ALIGN_LEFT];
                dockingReport.clear();
            }
        }

        [gui cxx_setText:oo::str::formatRuntime(OO_DESC_PLURAL("contracts-cash-@-load-d-of-d-passengers-d-of-d-berths", max_passengers), { cxx_OOCredits(credits), current_cargo, [self maxAvailableCargoSpace], passengers.size(), max_passengers }) forRow:GUI_ROW_MARKET_CASH];
        [gui setColor:[gui cxx_colorFromSetting:std::string(cxx_kGuiDockingSummaryColor) defaultValue:nil] forRow:GUI_ROW_MARKET_CASH];

        [gui cxx_setText:OO_DESC("press-space-commander") forRow:21 align:GUI_ALIGN_CENTER];
        [gui setColor:[gui cxx_colorFromSetting:std::string(cxx_kGuiDockingContinueColor) defaultValue:nil] forRow:21];
        [gui setShowTextCursor:NO];
    }
    /* ends */

    lastTextKey.reset();

    [self setShowDemoShips:NO];
    [UNIVERSE enterGUIViewModeWithMouseInteraction:NO];

    if (guiChanged) {
        [gui cxx_setForegroundTextureKey:std::string("docked_overlay")]; // has to be docked!

        oo::PList bgDescriptor = [UNIVERSE cxx_screenTextureDescriptorForKey:"report"];
        if (bgDescriptor.isNull())
            bgDescriptor = [UNIVERSE cxx_screenTextureDescriptorForKey:"status_docked"];
        if (bgDescriptor.isNull())
            bgDescriptor = [UNIVERSE cxx_screenTextureDescriptorForKey:"status"];
        [gui cxx_setBackgroundTextureDescriptor:bgDescriptor];
        [self noteGUIDidChangeFrom:oldScreen to:gui_screen];
    }
}

// ----------------------------------------------------------------------

namespace {

// Shipyard entries by SHIPYARD_KEY_ID, rebuilt by -setGuiToShipyardScreen:.
static oo::PList::Dict currentShipyard;

// -objectForKey: on currentShipyard (a copy: a script event may rebuild the screen); null if none.
oo::PList CurrentShipyardEntry(const std::optional<std::string>& key)
{
    if (!key)
        return oo::PList();
    const auto it = currentShipyard.find(*key);
    return it != currentShipyard.end() ? it->second : oo::PList();
}

// -oo_stringAtIndex: where the old code could read nil: a string, or a number's -stringValue.
std::optional<std::string> OptionalStringAt(const oo::PList& array, std::size_t index)
{
    const oo::PList* value = array.at(index);
    if (value == nullptr || !(value->isString() || value->isNumber()))
        return std::nullopt;
    return array.at<std::string>(index);
}

// cxx_OOExpandKey(key, ...) with the arguments it would have named after their variables; nothing
// expanded is "".
std::string ExpandKey(const char* key, oo::PList::Dict arguments)
{
    return cxx_OOExpandDescriptionString(OOStringExpanderDefaultRandomSeed(), std::string(key), oo::PList(std::move(arguments)), oo::PList(), std::nullopt, kOOExpandKey).value_or(std::string());
}

// The labels row as the GUI holds it, padded to four columns.
std::vector<std::string> ShipyardLabelsRow(GuiDisplayGen* gui)
{
    // its string columns, as oo::StringsFrom of the row's array kept them
    std::vector<std::string> row_info;
    const oo::PList row = [gui objectForRow:GUI_ROW_SHIPYARD_LABELS];
    if (const oo::PList::Array* columns = row.getIf<oo::PList::Array>()) {
        for (const oo::PList& column : *columns) {
            if (const std::string* text = column.getIf<std::string>())
                row_info.push_back(*text);
        }
    }
    while (row_info.size() < 4) {
        row_info.emplace_back();
    }
    return row_info;
}

} // namespace

- (OOCreditsQuantity)cxx_priceForShipKey:(const std::string&)key
{
    return CurrentShipyardEntry(key).get<unsigned long long>("price"); // SHIPYARD_KEY_PRICE
}

- (void)setGuiToShipyardScreen:(NSUInteger)skip
{
    OOGUIScreenID oldScreen = gui_screen;

    GuiDisplayGen* gui = [UNIVERSE gui];
    gui_screen = GUI_SCREEN_SHIPYARD;
    BOOL guiChanged = (oldScreen != gui_screen);

    unsigned i;

    // set up initial market if there is none
    OOTechLevelID stationTechLevel;
    StationEntity* station = [self dockedStation];

    if (station != nil) {
        stationTechLevel = [station equivalentTechLevel];
    } else {
        station = [UNIVERSE station];
        stationTechLevel = NSNotFound;
    }
    if ([station cxx_localShipyard] == nullptr) {
        [station generateShipyard:stationTechLevel];
    }

    std::vector<oo::PList>* stationShipyard = [station cxx_localShipyard];
    const std::vector<oo::PList> shipyard = stationShipyard != nullptr ? *stationShipyard : std::vector<oo::PList>(); // read only here

    currentShipyard.clear();

    for (i = 0; i < shipyard.size(); i++) {
        const std::optional<std::string> shipID = OptionalStringForKey(shipyard[i], "id"); // SHIPYARD_KEY_ID
        if (shipID)
            currentShipyard[*shipID] = shipyard[i]; // (a nil key raised)
    }

    NSUInteger shipCount = shipyard.size();

    // error check
    if (skip >= shipCount)
        skip = shipCount - 1;
    if (skip < 2)
        skip = 0;

    // GUI stuff
    {
        [gui clearAndKeepBackground:!guiChanged];
        const std::optional<std::string> systemName = [UNIVERSE cxx_getSystemName:system_id];
        [gui cxx_setTitle:ExpandKey("shipyard-title", { { "system", systemName.has_value() ? oo::PList(*systemName) : oo::PList() } })];

        OOGUITabSettings tab_stops;
        tab_stops[0] = 0;
        tab_stops[1] = -258;
        tab_stops[2] = 270;
        tab_stops[3] = 370;
        tab_stops[4] = 450;
        [gui cxx_overrideTabs:tab_stops from:cxx_kGuiShipyardTabs length:5];
        [gui setTabStops:tab_stops];

        int rowCount = MAX_ROWS_SHIPS_FOR_SALE;
        int startRow = GUI_ROW_SHIPYARD_START;
        NSInteger previous = 0;

        if (shipCount <= MAX_ROWS_SHIPS_FOR_SALE)
            skip = 0;
        else {
            if (skip > 0) {
                rowCount -= 1;
                startRow += 1;
                previous = skip - MAX_ROWS_SHIPS_FOR_SALE + 2;
                if (previous < 2)
                    previous = 0;
            }
            if (skip + rowCount < shipCount)
                rowCount -= 1;
        }

        if (shipCount > 0) {
            [gui setColor:[gui cxx_colorFromSetting:cxx_kGuiShipyardHeadingColor defaultValue:[OOColor greenColor]] forRow:GUI_ROW_SHIPYARD_LABELS];
            [gui cxx_setArray: { OO_DESC("shipyard-shiptype"), OO_DESC("shipyard-price-label"),
                                   OO_DESC("shipyard-cargo-label"), OO_DESC("shipyard-speed-label") }
                       forRow:GUI_ROW_SHIPYARD_LABELS];

            if (skip > 0) {
                [gui setColor:[gui cxx_colorFromSetting:cxx_kGuiShipyardScrollColor defaultValue:[OOColor greenColor]] forRow:GUI_ROW_SHIPYARD_START];
                [gui cxx_setArray: { OO_DESC("gui-back"), " <-- " } forRow:GUI_ROW_SHIPYARD_START];
                [gui cxx_setKey:oo::str::format("More:%zd", previous) forRow:GUI_ROW_SHIPYARD_START];
            }
            for (i = 0; i < (shipCount - skip) && (int)i < rowCount; i++) {
                const oo::PList& ship_info = shipyard[i + skip];
                OOCreditsQuantity ship_price = ship_info.get<unsigned long long>("price"); // SHIPYARD_KEY_PRICE
                const oo::PList* ship = ship_info.get<oo::PList::Dict>("ship"); // SHIPYARD_KEY_SHIP
                std::optional<std::string> shipName = ship != nullptr ? OptionalStringForKey(*ship, "display_name") : std::nullopt;
                if (!shipName && ship != nullptr)
                    shipName = OptionalStringForKey(*ship, "name"); // KEY_NAME
                [gui setColor:[gui cxx_colorFromSetting:cxx_kGuiShipyardEntryColor defaultValue:nil] forRow:startRow + i];
                [gui cxx_setArray: { " " + shipName.value_or("(null)") + " ", cxx_OOIntCredits(ship_price) }
                           forRow:startRow + i];
                [gui cxx_setKey:OptionalStringForKey(ship_info, "id").value_or("") forRow:startRow + i]; // SHIPYARD_KEY_ID
            }
            if (i < shipCount - skip) {
                [gui setColor:[gui cxx_colorFromSetting:cxx_kGuiShipyardScrollColor defaultValue:[OOColor greenColor]] forRow:startRow + i];
                [gui cxx_setArray: { OO_DESC("gui-more"), " --> " } forRow:startRow + i];
                [gui cxx_setKey:oo::str::format("More:%zu", rowCount + skip) forRow:startRow + i];
                i++;
            }

            [gui setSelectableRange:NSMakeRange(GUI_ROW_SHIPYARD_START, i + startRow - GUI_ROW_SHIPYARD_START)];
            // ensure that at least one row is selected at all times
            if (shipCount == 1)
                [gui setFirstSelectableRow];
            [self showShipyardInfoForSelection];
        } else {
            [gui cxx_setText:OO_DESC("shipyard-no-ships-available-for-purchase") forRow:GUI_ROW_NO_SHIPS align:GUI_ALIGN_CENTER];
            [gui setColor:[gui cxx_colorFromSetting:cxx_kGuiShipyardNoshipColor defaultValue:[OOColor greenColor]] forRow:GUI_ROW_NO_SHIPS];

            [gui setNoSelectedRow];
        }

        [self showTradeInInformationFooter];

        [gui setShowTextCursor:NO];
    }

    // the following are necessary...

    [self setShowDemoShips:(shipCount > 0)];
    [UNIVERSE enterGUIViewModeWithMouseInteraction:YES];

    if (guiChanged) {
        [gui cxx_setForegroundTextureKey:"docked_overlay"];
        [gui cxx_setBackgroundTextureKey:"shipyard"];
    }
}

- (void)showShipyardInfoForSelection
{
    NSUInteger i;
    GuiDisplayGen* gui = [UNIVERSE gui];
    OOGUIRow sel_row = [gui selectedRow];

    if (sel_row <= 0)
        return;

    std::vector<std::string> row_info = ShipyardLabelsRow(gui);

    const oo::PList info = CurrentShipyardEntry([gui cxx_keyForRow:sel_row]);

    // clean up the display ready for the newly-selected ship (if there is one)
    row_info[2] = "";
    row_info[3] = "";
    for (i = GUI_ROW_SHIPYARD_INFO_START; i < GUI_ROW_MARKET_CASH - 1; i++) {
        [gui cxx_setText:"" forRow:i];
        [gui setColor:[gui cxx_colorFromSetting:cxx_kGuiShipyardDescriptionColor defaultValue:[OOColor greenColor]] forRow:i];
    }
    [UNIVERSE removeDemoShips];

    if (!info.isNull()) {
        // the key is a particular ship - show the details
        const std::optional<std::string> salesPitch = OptionalStringForKey(info, "short_description"); // KEY_SHORT_DESCRIPTION
        const oo::PList* shipDictNode = info.get<oo::PList::Dict>("ship"); // SHIPYARD_KEY_SHIP
        const oo::PList shipDict = shipDictNode != nullptr ? *shipDictNode : oo::PList();

        int cargoRating = shipDict.get<int>("max_cargo");
        int cargo_extra;
        cargo_extra = shipDict.get<int>("extra_cargo", 15);
        float speedRating = 0.001 * shipDict.get<int>("max_flight_speed");

        const oo::PList* shipExtras = info.get<oo::PList::Array>("extras"); // KEY_EQUIPMENT_EXTRAS
        for (i = 0; shipExtras != nullptr && i < shipExtras->count(); i++) {
            if (shipExtras->at<std::string>(i) == "EQ_CARGO_BAY") {
                cargoRating += cargo_extra;
            } else if (shipExtras->at<std::string>(i) == "EQ_PASSENGER_BERTH") {
                cargoRating -= PASSENGER_BERTH_SPACE;
            }
        }

        row_info[2] = cxx_OOExpandKey("shipyard-cargo-value", cargoRating).value_or(std::string());
        row_info[3] = cxx_OOExpandKey("shipyard-speed-value", speedRating).value_or(std::string());

        // Show footer first. It'll be overwritten by the sales_pitch if that text is longer than usual.
        [self showTradeInInformationFooter];
        i = [gui cxx_addLongText:salesPitch startingAtRow:GUI_ROW_SHIPYARD_INFO_START align:GUI_ALIGN_LEFT];
        if (i - 1 >= GUI_ROW_MARKET_CASH - 1) {
            [gui setColor:[gui cxx_colorFromSetting:cxx_kGuiShipyardDescriptionColor defaultValue:[OOColor greenColor]] forRow:i - 1];
            [gui setColor:[gui cxx_colorFromSetting:cxx_kGuiShipyardDescriptionColor defaultValue:[OOColor greenColor]] forRow:GUI_ROW_MARKET_CASH - 1];
        }

        // now display the ship
        const std::optional<std::string> shipKey = OptionalStringForKey(info, "shipdata_key"); // SHIPYARD_KEY_SHIPDATA_KEY
        if (shipKey) {
            [self cxx_showShipyardModel:*shipKey
                               shipData:shipDict
                            personality:info.get<unsigned short>("personality")]; // SHIPYARD_KEY_PERSONALITY
        }
    } else {
        // the key is a particular model of ship which we must expand...
        // build an array from the entries for that model in the currentShipyard TODO
        //
    }

    [gui cxx_setArray:row_info forRow:GUI_ROW_SHIPYARD_LABELS];
}

- (void)showTradeInInformationFooter
{
    GuiDisplayGen* gui = [UNIVERSE gui];
    OOCreditsQuantity tradeIn = [self tradeInValue];
    OOCreditsQuantity total = tradeIn + credits;
    const oo::PList shipType = oo::PList([self displayName].value_or(""));

    [gui setColor:[gui cxx_colorFromSetting:cxx_kGuiShipyardTradeinColor defaultValue:nil] forRow:GUI_ROW_MARKET_CASH - 1];
    [gui setColor:[gui cxx_colorFromSetting:cxx_kGuiShipyardTradeinColor defaultValue:nil] forRow:GUI_ROW_MARKET_CASH];
    [gui cxx_setText:ExpandKey("shipyard-trade-in-value", { { "shipType", shipType }, { "tradeIn", oo::PList::unsignedInteger(tradeIn) } }) forRow:GUI_ROW_MARKET_CASH - 1];
    [gui cxx_setText:ExpandKey("shipyard-total-available-with-trade-in", { { "shipType", shipType }, { "total", oo::PList::unsignedInteger(total) }, { "credits", oo::PList::unsignedInteger(credits) }, { "tradeIn", oo::PList::unsignedInteger(tradeIn) } }) forRow:GUI_ROW_MARKET_CASH];
}

- (void)cxx_showShipyardModel:(const std::string&)shipKey shipData:(const oo::PList&)shipData personality:(uint16_t)personality
{
    if ([self dockedStation] == nil)
        return;
    [self cxx_showShipModelWithKey:shipKey shipData:shipData personality:personality factorX:1.2 factorY:0.8 factorZ:6.4 inContext:"shipyard"];
}

- (NSInteger)missingSubEntitiesAdjustment
{
    // each missing subentity depreciates the ship by 5%, up to a maximum of 35% depreciation.
    NSUInteger percent = 5 * ([self maxShipSubEntities] - [self cxx_shipSubEntities].size());
    return (percent > 35 ? 35 : percent);
}

- (OOCreditsQuantity)tradeInValue
{
    // returns down to ship_trade_in_factor% of the full credit value of your ship

    /*	FIXME: the trade-in value can be more than the sale value, and
            ship_trade_in_factor starts at 100%, so it can be profitable to sit
            and buy the same ship over and over again. This bug predates Oolite
            1.65.
            Partial fix: make effective trade-in value 75% * ship_trade_in_factor%
            of the "raw" trade-in value. This still allows profitability! A better
            solution would be to unify the price calculation for trade-in and
            for-sale ships.
            -- Ahruman 20070707, fix applied 20070708
    */
    unsigned long long value = [UNIVERSE cxx_tradeInValueForCommanderDictionary:[self cxx_commanderDataDictionary]];
    value -= value * 0.006 * [self missingSubEntitiesAdjustment]; // TODO: 0.006 might need rethinking.
    value = cunningFee(((value * 75 * ship_trade_in_factor) + 5000) / 10000, 0.005); // Multiply by two percentages, divide by 100*100. The +5000 is to get normal rounding.
    return value * 10;
}

- (BOOL)buySelectedShip
{
    GuiDisplayGen* gui = [UNIVERSE gui];
    OOGUIRow selectedRow = [gui selectedRow];

    if (selectedRow <= 0)
        return NO;

    const std::optional<std::string> key = [gui cxx_keyForRow:selectedRow];

    if (key && oo::str::hasPrefix(*key, "More:")) {
        const std::vector<std::string> keyParts = oo::str::split(*key, ":");
        NSInteger fromShip = keyParts.size() > 1 ? oo::str::longLongValue(keyParts[1]) : 0;
        if (fromShip < 0)
            fromShip = 0;

        [self setGuiToShipyardScreen:fromShip];
        if ([[UNIVERSE gui] selectedRow] < 0) {
            [[UNIVERSE gui] setSelectedRow:GUI_ROW_SHIPYARD_START];
        }
        if (fromShip == 0) {
            [[UNIVERSE gui] setSelectedRow:GUI_ROW_SHIPYARD_START + MAX_ROWS_SHIPS_FOR_SALE - 1];
        }
        // next bit or the first ship on the list gets wrongly previewed
        // clean up the display
        std::vector<std::string> row_info = ShipyardLabelsRow(gui);
        row_info[2] = "";
        row_info[3] = "";
        NSUInteger i;
        for (i = GUI_ROW_SHIPYARD_INFO_START; i < GUI_ROW_MARKET_CASH - 1; i++) {
            [gui cxx_setText:"" forRow:i];
            [gui setColor:[gui cxx_colorFromSetting:cxx_kGuiShipyardDescriptionColor defaultValue:[OOColor greenColor]] forRow:i];
        }
        [gui cxx_setArray:row_info forRow:GUI_ROW_SHIPYARD_LABELS];
        [UNIVERSE removeDemoShips];
        return YES;
    }

    // first check you can afford it!
    const oo::PList shipInfo = CurrentShipyardEntry(key);
    OOCreditsQuantity price = shipInfo.get<unsigned long long>("price"); // SHIPYARD_KEY_PRICE
    OOCreditsQuantity tradeIn = [self tradeInValue];

    if (credits + tradeIn < price * 10)
        return NO; // you can't afford it!

    // from this point, the player is committed to buying - raise a pre-buy script event
    const std::optional<std::string> shipDataKey = OptionalStringForKey(shipInfo, "shipdata_key"); // SHIPYARD_KEY_SHIPDATA_KEY
    std::vector<oo::PList>* dockedShipyard = [[self dockedStation] cxx_localShipyard];
    const NSUInteger boughtIndex = selectedRow - GUI_ROW_SHIPYARD_START;
    oo::PList::Array buyArguments;
    for (const oo::PList& argument : { shipDataKey ? oo::PList(*shipDataKey) : oo::PList(),
             (dockedShipyard != nullptr && boughtIndex < dockedShipyard->size()) ? (*dockedShipyard)[boughtIndex] : oo::PList(),
             oo::PList::unsignedInteger(price),
             oo::PList::unsignedInteger(tradeIn / 10) }) {
        if (argument.isNull())
            break; // +arrayWithObjects: stopped at the first nil
        buyArguments.push_back(argument);
    }
    [self cxx_doScriptEvent:OOJSID("playerWillBuyNewShip")
         withPListArguments:buyArguments];

    // sell all the commodities carried
    for (const std::string& good : [shipCommodityData goods]) {
        [self cxx_trySellingCommodity:good all:YES];
    }
    // We tried to sell everything. If there are still items present in our inventory, it
    // means that the market got saturated (quantity in station > 127 t) before we could sell
    // it all. Everything that could not be sold will be lost. -- Nikos 20083012

    // pay over the mazoolah
    credits -= 10 * price - tradeIn;

    const oo::PList* shipDictNode = shipInfo.get<oo::PList::Dict>("ship"); // SHIPYARD_KEY_SHIP
    [self newShipCommonSetup:shipDataKey.value_or("") yardInfo:shipInfo baseInfo:shipDictNode != nullptr ? *shipDictNode : oo::PList()];

    // this ship has a clean record
    legalStatus = 0;

    const oo::PList* extras = shipInfo.get<oo::PList::Array>("extras"); // KEY_EQUIPMENT_EXTRAS
    for (std::size_t i = 0; extras != nullptr && i < extras->count(); i++) {
        const std::optional<std::string> eq_key = OptionalStringAt(*extras, i);
        if (eq_key == "EQ_PASSENGER_BERTH") {
            max_passengers++;
            max_cargo -= PASSENGER_BERTH_SPACE;
        } else {
            [self addEquipmentItem:eq_key.value_or(std::string()) withValidation:YES inContext:"newShip"]; // none: "", as nil was
        }
    }

    // add bought ship to shipyard_record
    const std::optional<std::string> shipID = OptionalStringForKey(shipInfo, "id"); // SHIPYARD_KEY_ID
    if (shipID) {
        const std::optional<std::string> dataKey = [self cxx_shipDataKey];
        shipyard_record[*shipID] = dataKey ? oo::PList(*dataKey) : oo::PList(); // (a nil key raised)
    }

    // remove the ship from the localShipyard
    dockedShipyard = [[self dockedStation] cxx_localShipyard];
    if (dockedShipyard != nullptr)
        dockedShipyard->erase(dockedShipyard->begin() + (selectedRow - GUI_ROW_SHIPYARD_START));

    // perform the transformation
    if (![self cxx_setCommanderDataFromDictionary:[self cxx_commanderDataDictionary]])
        return NO; // gather up all the info

    [self setStatus:STATUS_DOCKED];
    [self setEntityPersonalityInt:shipInfo.get<unsigned short>("personality")]; // SHIPYARD_KEY_PERSONALITY

    // adjust the clock forward by an hour
    ship_clock_adjust += 3600.0;

    // finally we can get full hock if we sell it back
    ship_trade_in_factor = 100;

    if ([UNIVERSE autoSave])
        [UNIVERSE setAutoSaveNow:YES];

    return YES;
}

- (BOOL)cxx_replaceShipWithNamedShip:(const std::string&)shipKey
{

    const oo::PList ship_info = [[OOShipRegistry sharedRegistry] cxx_shipyardInfoForKey:shipKey];

    const oo::PList ship_base_dict = [[OOShipRegistry sharedRegistry] cxx_shipInfoForKey:shipKey];

    if (ship_info.isNull() || ship_base_dict.isNull()) {
        return NO;
    }

    // from this point, the player is committed to replacing - raise a pre-replace script event
    [self cxx_doScriptEvent:OOJSID("playerWillReplaceShip") withPListArguments:{ oo::PList(shipKey) }];

    [self newShipCommonSetup:shipKey yardInfo:ship_info baseInfo:ship_base_dict];

    // perform the transformation
    if (![self cxx_setCommanderDataFromDictionary:[self cxx_commanderDataDictionary]])
        return NO; // gather up all the info

    // refill from ship_info
    const oo::PList* standardEquipment = ship_info.get<oo::PList::Dict>("standard_equipment"); // KEY_STANDARD_EQUIPMENT
    const oo::PList* extrasNode = standardEquipment != nullptr ? standardEquipment->get<oo::PList::Array>("extras") : nullptr; // KEY_EQUIPMENT_EXTRAS
    const oo::PList extras = extrasNode != nullptr ? *extrasNode : oo::PList();
    for (unsigned i = 0; i < extras.count(); i++) {
        const std::optional<std::string> eq_key = OptionalStringAt(extras, i);
        if (eq_key == "EQ_PASSENGER_BERTH") {
            max_passengers++;
            max_cargo -= PASSENGER_BERTH_SPACE;
        } else {
            [self addEquipmentItem:eq_key.value_or(std::string()) withValidation:YES inContext:"newShip"]; // none: "", as nil was
        }
    }

    [self setEntityPersonalityInt:ship_info.get<unsigned short>("personality")]; // SHIPYARD_KEY_PERSONALITY

    return YES;
}

- (void)newShipCommonSetup:(const std::string&)shipKey yardInfo:(const oo::PList&)ship_info baseInfo:(const oo::PList&)ship_base_dict
{
    // Zero out our manifest.
    [shipCommodityData removeAllGoods];
    current_cargo = 0;

    // drop all passengers
    passengers.clear();
    passenger_record.clear();

    // parcels stay the same; easy to transfer between ships
    // contracts stay the same, so if you default - tough!
    // okay we need to switch the model used, lots of the stats, and add all the extras

    [self clearSubEntities];

    [self cxx_setShipDataKey:shipKey];

    const oo::PList& shipDict = ship_base_dict;

    // get a full tank for free
    [self setFuel:[self fuelCapacity]];

    // get forward_weapon aft_weapon port_weapon starboard_weapon from ship_info
    int base_facings = shipDict.get<unsigned int>("weapon_facings", 15); // KEY_WEAPON_FACINGS
    int available_facings = ship_info.get<unsigned int>("weapon_facings", base_facings);

    // not retained - weapon types are references to the objects in OOEquipmentType's cache
    if (available_facings & WEAPON_FACING_AFT)
        aft_weapon_type = cxx_OOWeaponTypeFromEquipmentIdentifierSloppy(OptionalStringForKey(shipDict, "aft_weapon_type").value_or(""));
    else
        aft_weapon_type = cxx_OOWeaponTypeFromEquipmentIdentifierSloppy("EQ_WEAPON_NONE");

    if (available_facings & WEAPON_FACING_PORT)
        port_weapon_type = cxx_OOWeaponTypeFromEquipmentIdentifierSloppy(OptionalStringForKey(shipDict, "port_weapon_type").value_or(""));
    else
        port_weapon_type = cxx_OOWeaponTypeFromEquipmentIdentifierSloppy("EQ_WEAPON_NONE");

    if (available_facings & WEAPON_FACING_STARBOARD)
        starboard_weapon_type = cxx_OOWeaponTypeFromEquipmentIdentifierSloppy(OptionalStringForKey(shipDict, "starboard_weapon_type").value_or(""));
    else
        starboard_weapon_type = cxx_OOWeaponTypeFromEquipmentIdentifierSloppy("EQ_WEAPON_NONE");

    if (available_facings & WEAPON_FACING_FORWARD)
        forward_weapon_type = cxx_OOWeaponTypeFromEquipmentIdentifierSloppy(OptionalStringForKey(shipDict, "forward_weapon_type").value_or(""));
    else
        forward_weapon_type = cxx_OOWeaponTypeFromEquipmentIdentifierSloppy("EQ_WEAPON_NONE");

    // new ships start with weapons online
    weapons_online = 1;

    // get basic max_cargo
    max_cargo = [UNIVERSE cxx_maxCargoForShip:[self cxx_shipDataKey].value_or(std::string())];

    // ensure all missiles are tidied up and start at pylon 0
    [self tidyMissilePylons];

    // get missiles from ship_info
    missiles = shipDict.get<unsigned int>("missiles");

    // reset max_passengers
    max_passengers = 0;

    // reset and refill extra_equipment then set flags from it

    // keep track of portable equipment..

    std::set<std::string> portable_equipment;

    for (const std::string& eq_desc : [self cxx_equipmentKeys]) {
        OOEquipmentType* item = [OOEquipmentType cxx_equipmentTypeWithIdentifier:eq_desc];
        if ([item isPortableBetweenShips])
            portable_equipment.insert(eq_desc);
    }

    // remove ALL
    [self removeAllEquipment];

    // restore  portable equipment (in key order; the set it replaced gave hash order)
    for (const std::string& eq_desc : portable_equipment) {
        [self addEquipmentItem:eq_desc withValidation:NO inContext:"portable"];
    }

    // set up subentities from scratch; new ship could carry more or fewer than the old one
    [self setUpSubEntities];

    // clear old ship names
    [self cxx_setShipClassName:OptionalStringForKey(shipDict, "name")];
    [self cxx_setShipUniqueName:""];

    // new ship, so lose some memory of actions
    // new ship, so lose some memory of player actions
    if (ship_kills >= 6400) {
        [self clearRolesFromPlayer:0.1];
    } else if (ship_kills >= 2560) {
        [self clearRolesFromPlayer:0.25];
    } else {
        [self clearRolesFromPlayer:0.5];
    }
}

@end

static unsigned RepForRisk(unsigned risk)
{
    switch (risk) {
    case 0:
        return 1;
    case 1:
        return 2;
    case 2:
    default:
        return 4;
    }
}
