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

#include "PlayerEntityContracts.h"
#include "HeadUpDisplay.h"
#include "PlayerEntity.h"
#include "PlayerEntityControls.h"
#include "PlayerEntityLegacyScriptEngine.h"
#include "ProxyPlayerEntity.h"

#include "AI.h"
#include "GuiDisplayGen.h"
#include "MyOpenGLView.h"
#include "OOCharacter.h"
#include "OOColor.h"
#include "OOConstToString.h"
#include "OOEquipmentType.h"
#include "OOJavaScriptEngine.h"
#include "OOShipRegistry.h"
#include "OOStringExpander.h"
#include "OOStringParsing.h"
#include "OOTexture.h"
#include "ShipEntityAI.h"
#include "StationEntity.h"
#include "Universe.h"
#include "oofnd/PList.hpp"
#include "oofnd/String.hpp"

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

std::optional<std::string> PlayerEntity::processEscapePods() // removes pods from cargo bay and treats categories of characters carried
{
    unsigned i;
    BOOL added_entry = NO; // to prevent empty lines for slaves and the rare empty report.
    std::string result;
    std::vector<oo::Ref<OOCharacter>> rescuees;
    // -intValue of the system's government: a string's leading integer, a number truncated, nil 0
    const oo::PList systemData = (UNIVERSE != nullptr ? UNIVERSE->currentSystemData() : oo::PList());
    const oo::PList* governmentValue = systemData.find(KEY_GOVERNMENT);
    OOGovernmentID government = 0;
    if (governmentValue != nullptr && governmentValue->isString())
        government = oo::str::intValue(*governmentValue->getIf<std::string>());
    else if (governmentValue != nullptr)
        government = static_cast<int>(governmentValue->int64Value());
    if ((UNIVERSE != nullptr ? UNIVERSE->inInterstellarSpace() : false))
        government = 1; // equivalent to Feudal. I'm assuming any station in interstellar space is military. -- Ahruman 2008-05-29

    // step through the cargo removing crew from any escape pods
    // No enumerator because we're mutating the array -- Ahruman
    for (i = 0; i < cargo.size(); i++) {
        ::ShipEntity* cargoItem = oo::ToShip(cargo[i].get());

        const std::optional<std::vector<oo::Ref<OOCharacter>>> podCrew = (cargoItem != nullptr ? cargoItem->getCrew() : std::optional<std::vector<oo::Ref<OOCharacter>>>());
        if (podCrew.has_value()) {
            // Has crew -> is escape pod.
            rescuees.insert(rescuees.end(), podCrew->begin(), podCrew->end());
            if (cargoItem != nullptr)
                cargoItem->setCrew(std::nullopt);
            cargo.erase(cargo.begin() + i);
            i--;
        }
    }

    // step through the rescuees awarding insurance or bounty or adding to slaves
    for (i = 0; i < rescuees.size(); i++) {
        ::OOCharacter* rescuee = rescuees[i].get();

        if (rescuee->script()) {
            rescuee->doScriptEvent(OOJSID("unloadCharacter"));
        } else if (!rescuee->legacyScript().isNull()) {
            runUnsanitizedScriptActions(rescuee->legacyScript(), YES, oo::str::format("<character \"%s\" script>", rescuee->name().value_or("(null)").c_str()), nullptr);
        } else if (rescuee->insuranceCredits() && rescuee->legalStatus()) {
            float reward = (5.0 + government) * rescuee->legalStatus();
            float insurance = 10 * rescuee->insuranceCredits();
            if (government > (Ranrot() & 7) || reward >= insurance) {
                // claim bounty for capture, ignore insurance
                result += oo::str::formatRuntime(OO_DESC("capture-reward-for-@@-@-credits-@-alt"),
                    { rescuee->name().value_or("(null)"), rescuee->shortDescription().value_or("(null)"), cxx_OOStringFromDeciCredits(reward, YES, NO),
                        cxx_OOStringFromDeciCredits(insurance, YES, NO) });
                doScriptEvent(OOJSID("playerRescuedEscapePod"), { oo::PList::unsignedInteger(static_cast<NSUInteger>(reward)), oo::PList("bounty"), rescuee->infoForScripting() });
            } else {
                // claim insurance reward with reduction of bounty
                result += oo::str::formatRuntime(OO_DESC("rescue-reward-for-@@-@-credits-@-alt"),
                    { rescuee->name().value_or("(null)"), rescuee->shortDescription().value_or("(null)"), cxx_OOStringFromDeciCredits(insurance - reward, YES, NO),
                        cxx_OOStringFromDeciCredits(reward, YES, NO) });
                reward = insurance - reward;
                doScriptEvent(OOJSID("playerRescuedEscapePod"), { oo::PList::unsignedInteger(static_cast<NSUInteger>(reward)), oo::PList("insurance"), rescuee->infoForScripting() });
            }
            credits += reward;
            added_entry = YES;
        } else if (rescuee->insuranceCredits()) {
            // claim insurance reward
            result += oo::str::formatRuntime(OO_DESC("rescue-reward-for-@@-@-credits"),
                { rescuee->name().value_or("(null)"), rescuee->shortDescription().value_or("(null)"), cxx_OOStringFromDeciCredits(rescuee->insuranceCredits() * 10, YES, NO) });
            credits += 10 * rescuee->insuranceCredits();
            doScriptEvent(OOJSID("playerRescuedEscapePod"), { oo::PList::unsignedInteger(static_cast<NSUInteger>(10 * rescuee->insuranceCredits())), oo::PList("insurance"), rescuee->infoForScripting() });

            added_entry = YES;
        } else if (rescuee->legalStatus()) {
            // claim bounty for capture
            float reward = (5.0 + government) * rescuee->legalStatus();
            result += oo::str::formatRuntime(OO_DESC("capture-reward-for-@@-@-credits"),
                { rescuee->name().value_or("(null)"), rescuee->shortDescription().value_or("(null)"), cxx_OOStringFromDeciCredits(reward, YES, NO) });
            credits += reward;
            doScriptEvent(OOJSID("playerRescuedEscapePod"), { oo::PList::unsignedInteger(static_cast<NSUInteger>(reward)), oo::PList("bounty"), rescuee->infoForScripting() });
            added_entry = YES;
        } else {
            // sell as slave - increase no. of slaves in manifest
            if (shipCommodityData != nullptr)
                shipCommodityData->addQuantity(1, "slaves");
            doScriptEvent(OOJSID("playerRescuedEscapePod"), { oo::PList::unsignedInteger(0), oo::PList("slave"), rescuee->infoForScripting() });
        }
        if ((i < rescuees.size() - 1) && added_entry)
            result += "\n";
        added_entry = NO;
    }

    calculateCurrentCargo();

    return result; // never nil (the old method returned an empty string when nothing was reported)
}

std::optional<std::string> PlayerEntity::checkPassengerContracts() // returns messages from any passengers whose status have changed
{
    if (dockedStation() != (UNIVERSE != nullptr ? UNIVERSE->station() : nullptr)) // only drop off passengers or fulfil contracts at main station
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
        const std::optional<std::string> passenger_dest_name = (UNIVERSE != nullptr ? UNIVERSE->getSystemName(dest) : std::optional<std::string>());
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
                    addRoleToPlayer("trader-courier+");
                }

                increasePassengerReputation(RepForRisk(passenger_info.get<unsigned int>(std::string(CONTRACT_KEY_RISK), 0)));
                passengers.erase(passengers.begin() + i--);
                doScriptEvent(OOJSID("playerCompletedContract"), { oo::PList("passenger"), oo::PList("success"), oo::PList::unsignedInteger(static_cast<NSUInteger>(10 * fee)), passenger_info });
            } else {
                // but we're late!
                long long fee = passenger_info.get<long long>(std::string(CONTRACT_KEY_FEE)) / 2; // halve fare
                while (randf() < 0.5) // maybe halve fare a few times!
                    fee /= 2;
                credits += 10 * fee;

                result += oo::str::formatRuntime(OO_DESC("passenger-delivered-late-@-@-@"), { TextArg(passenger_name), cxx_OOIntCredits(fee), TextArg(passenger_dest_name) }) + "\n";
                if (passenger_info.get<unsigned int>(std::string(CONTRACT_KEY_RISK), 0) > 0) {
                    addRoleToPlayer("trader-courier+");
                }

                passengers.erase(passengers.begin() + i--);
                doScriptEvent(OOJSID("playerCompletedContract"), { oo::PList("passenger"), oo::PList("late"), oo::PList::unsignedInteger(static_cast<NSUInteger>(10 * fee)), passenger_info });
            }
        } else {
            if (dest_eta < 0) {
                // we've run out of time!
                result += oo::str::formatRuntime(OO_DESC("passenger-failed-@"), { TextArg(passenger_name) }) + "\n";

                decreasePassengerReputation(RepForRisk(passenger_info.get<unsigned int>(std::string(CONTRACT_KEY_RISK), 0)));
                passengers.erase(passengers.begin() + i--);
                doScriptEvent(OOJSID("playerCompletedContract"), { oo::PList("passenger"), oo::PList("failed"), oo::PList::unsignedInteger(static_cast<NSUInteger>(0)), passenger_info });
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

                increaseParcelReputation(RepForRisk(parcel_info.get<unsigned int>(std::string(CONTRACT_KEY_RISK), 0)));

                parcels.erase(parcels.begin() + i--);
                if (parcel_info.get<unsigned int>(std::string(CONTRACT_KEY_RISK), 0) > 0) {
                    addRoleToPlayer("trader-courier+");
                }
                doScriptEvent(OOJSID("playerCompletedContract"), { oo::PList("parcel"), oo::PList("success"), oo::PList::unsignedInteger(static_cast<NSUInteger>(10 * fee)), parcel_info });

            } else {
                // but we're late!
                long long fee = parcel_info.get<long long>(std::string(CONTRACT_KEY_FEE)) / 2; // halve fare
                while (randf() < 0.5) // maybe halve fare a few times!
                    fee /= 2;
                credits += 10 * fee;

                result += oo::str::formatRuntime(OO_DESC("parcel-delivered-late-@-@"), { TextArg(parcel_name), cxx_OOIntCredits(fee) }) + "\n";
                if (parcel_info.get<unsigned int>(std::string(CONTRACT_KEY_RISK), 0) > 0) {
                    addRoleToPlayer("trader-courier+");
                }
                parcels.erase(parcels.begin() + i--);
                doScriptEvent(OOJSID("playerCompletedContract"), { oo::PList("parcel"), oo::PList("late"), oo::PList::unsignedInteger(static_cast<NSUInteger>(10 * fee)), parcel_info });
            }
        } else {
            if (dest_eta < 0) {
                // we've run out of time!
                result += oo::str::formatRuntime(OO_DESC("parcel-failed-@"), { TextArg(parcel_name) }) + "\n";

                decreaseParcelReputation(RepForRisk(parcel_info.get<unsigned int>(std::string(CONTRACT_KEY_RISK), 0)));
                parcels.erase(parcels.begin() + i--);
                doScriptEvent(OOJSID("playerCompletedContract"), { oo::PList("parcel"), oo::PList("failed"), oo::PList::unsignedInteger(static_cast<NSUInteger>(0)), parcel_info });
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

            int quantity_on_hand = (shipCommodityData != nullptr ? shipCommodityData->quantityForGood(contract_cargo_type) : 0);

            // we've arrived in system!
            if (dest_eta > 0) {
                // and in good time
                if (quantity_on_hand >= contract_amount) {
                    // with the goods too!

                    // remove the goods...
                    if (shipCommodityData != nullptr)
                        shipCommodityData->removeQuantity(contract_amount, contract_cargo_type);

                    // pay the premium and fee
                    // credits += fee + premium;
                    // not any more: all contracts initially awarded by JS, so fee
                    // is now all that needs to be paid - CIM

                    if ((shipCommodityData != nullptr ? shipCommodityData->exportLegalityForGood(contract_cargo_type) : 0) > 0) {
                        addRoleToPlayer("trader-smuggler");
                    } else {
                        addRoleToPlayer("trader");
                    }

                    credits += fee;
                    result += oo::str::formatRuntime(OO_DESC("cargo-delivered-okay-@-@"), { TextArg(contract_cargo_desc), cxx_OOCredits(fee) }) + "\n";

                    contracts.erase(contracts.begin() + i--);
                    // repute++
                    // +10 as cargo contracts don't have risk modifiers
                    increaseContractReputation(10);
                    doScriptEvent(OOJSID("playerCompletedContract"), { oo::PList("cargo"), oo::PList("success"), oo::PList::unsignedInteger(static_cast<NSUInteger>(fee)), contract_info });

                } else {
                    // see if the amount of goods delivered is acceptable

                    float percent_delivered = 100.0 * (float)quantity_on_hand / (float)contract_amount;
                    float acceptable_ratio = 100.0 - 10.0 * system_id / 256.0; // down to 90%

                    if (percent_delivered >= acceptable_ratio) {
                        // remove the goods...
                        if (shipCommodityData != nullptr)
                            shipCommodityData->setQuantity(0, contract_cargo_type);

                        // pay the fee
                        int shortfall = 100 - percent_delivered;
                        int payment = percent_delivered * (fee) / 100.0;
                        credits += payment;

                        if ((shipCommodityData != nullptr ? shipCommodityData->exportLegalityForGood(contract_cargo_type) : 0) > 0) {
                            addRoleToPlayer("trader-smuggler");
                        } else {
                            addRoleToPlayer("trader");
                        }

                        result += oo::str::formatRuntime(OO_DESC("cargo-delivered-short-@-@-d"), { TextArg(contract_cargo_desc), cxx_OOCredits(payment), shortfall }) + "\n";

                        contracts.erase(contracts.begin() + i--);
                        // repute unchanged
                        doScriptEvent(OOJSID("playerCompletedContract"), { oo::PList("cargo"), oo::PList("short"), oo::PList::unsignedInteger(static_cast<NSUInteger>(payment)), contract_info });

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
                decreaseContractReputation(10);
                doScriptEvent(OOJSID("playerCompletedContract"), { oo::PList("cargo"), oo::PList("late"), oo::PList::unsignedInteger(static_cast<NSUInteger>(0)), contract_info });
            }
        } else {
            if (dest_eta < 0) {
                // we've run out of time!
                result += oo::str::formatRuntime(OO_DESC("cargo-failed-@"), { TextArg(contract_cargo_desc) }) + "\n";

                contracts.erase(contracts.begin() + i--);
                // repute--
                decreaseContractReputation(10);
                doScriptEvent(OOJSID("playerCompletedContract"), { oo::PList("cargo"), oo::PList("failed"), oo::PList::unsignedInteger(static_cast<NSUInteger>(0)), contract_info });
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

OOCargoQuantity PlayerEntity::contractedVolumeForGood(const std::string& good)
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

void PlayerEntity::addMessageToReport(const std::string& report)
{
    if (!report.empty()) {
        if (dockingReport.empty())
            dockingReport += report;
        else
            dockingReport += "\n\n" + report; // @"\n\n%@"
    }
}

oo::PList PlayerEntity::getReputation()
{
    return oo::PList(reputation);
}

int PlayerEntity::passengerReputation()
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

void PlayerEntity::increasePassengerReputation(unsigned amount)
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

void PlayerEntity::decreasePassengerReputation(unsigned amount)
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

int PlayerEntity::parcelReputation()
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

void PlayerEntity::increaseParcelReputation(unsigned amount)
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

void PlayerEntity::decreaseParcelReputation(unsigned amount)
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

int PlayerEntity::contractReputation()
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

void PlayerEntity::increaseContractReputation(unsigned amount)
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

void PlayerEntity::decreaseContractReputation(unsigned amount)
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

void PlayerEntity::erodeReputation()
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
void PlayerEntity::normaliseReputation()
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

bool PlayerEntity::addPassenger(const std::string& Name, unsigned start, unsigned Destination, double eta, double fee, double advance, unsigned risk)
{
    // the number kinds the old dictionary held: +numberWithInt:, +numberWithDouble:, +numberWithUnsignedInt:
    const oo::PList passenger_info(oo::PList::Dict {
        { std::string(PASSENGER_KEY_NAME), oo::PList(Name) },
        { std::string(CONTRACT_KEY_START), oo::PList::signedInteger(static_cast<int>(start)) },
        { std::string(CONTRACT_KEY_DESTINATION), oo::PList::signedInteger(static_cast<int>(Destination)) },
        { std::string(CONTRACT_KEY_DEPARTURE_TIME), oo::PList((PLAYER != nullptr ? PLAYER->clockTime() : 0.0)) },
        { std::string(CONTRACT_KEY_ARRIVAL_TIME), oo::PList(eta) },
        { std::string(CONTRACT_KEY_FEE), oo::PList(fee) },
        { std::string(CONTRACT_KEY_PREMIUM), oo::PList(advance) },
        { std::string(CONTRACT_KEY_RISK), oo::PList::unsignedInteger(risk) },
    });

    // extra checks, just in case.
    if (passengers.size() >= max_passengers || passenger_record.find(Name) != passenger_record.end())
        return NO;

    if (risk > 1) {
        addRoleToPlayer("trader-courier+");
    }

    passengers.push_back(passenger_info);
    passenger_record[Name] = oo::PList(eta); // +numberWithDouble:

    doScriptEvent(OOJSID("playerEnteredContract"), { oo::PList("passenger"), passenger_info });

    return YES;
}

bool PlayerEntity::removePassenger(const std::string& Name) // removes the first passenger that answers to Name, returns NO if none found
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

bool PlayerEntity::addParcel(const std::string& Name, unsigned start, unsigned Destination, double eta, double fee, double premium, unsigned risk)
{
    // the number kinds the old dictionary held: +numberWithInt:, +numberWithDouble:, +numberWithUnsignedInt:
    const oo::PList parcel_info(oo::PList::Dict {
        { std::string(PASSENGER_KEY_NAME), oo::PList(Name) },
        { std::string(CONTRACT_KEY_START), oo::PList::signedInteger(static_cast<int>(start)) },
        { std::string(CONTRACT_KEY_DESTINATION), oo::PList::signedInteger(static_cast<int>(Destination)) },
        { std::string(CONTRACT_KEY_DEPARTURE_TIME), oo::PList((PLAYER != nullptr ? PLAYER->clockTime() : 0.0)) },
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
        addRoleToPlayer("trader-courier+");
    }

    parcels.push_back(parcel_info);
    parcel_record[Name] = oo::PList(eta); // +numberWithDouble:

    doScriptEvent(OOJSID("playerEnteredContract"), { oo::PList("parcel"), parcel_info });

    return YES;
}

bool PlayerEntity::removeParcel(const std::string& Name) // removes the first parcel that answers to Name, returns NO if none found
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

bool PlayerEntity::awardContract(unsigned qty, const std::string& type, unsigned start, unsigned Destination, double eta, double fee, double premium)
{

    unsigned sr1 = Ranrot() & 0x111111;
    int sr2 = Ranrot() & 0x111111;

    std::string cargo_ID = oo::str::format("%06x-%06x", sr1, sr2);

    if (!((UNIVERSE != nullptr ? UNIVERSE->getCommodities() : nullptr) != nullptr ? UNIVERSE->getCommodities()->goodDefined(type) : false))
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
        { std::string(CARGO_KEY_DESCRIPTION), oo::PList((UNIVERSE != nullptr ? UNIVERSE->describeCommodity(type, qty) : std::optional<std::string>()).value_or(std::string())) },
        { std::string(CONTRACT_KEY_START), oo::PList::signedInteger(static_cast<int>(start)) },
        { std::string(CONTRACT_KEY_DESTINATION), oo::PList::signedInteger(static_cast<int>(Destination)) },
        { std::string(CONTRACT_KEY_DEPARTURE_TIME), oo::PList((PLAYER != nullptr ? PLAYER->clockTime() : 0.0)) },
        { std::string(CONTRACT_KEY_ARRIVAL_TIME), oo::PList(eta) },
        { std::string(CONTRACT_KEY_FEE), oo::PList(fee) },
        { std::string(CONTRACT_KEY_PREMIUM), oo::PList(premium) },
    });

    // check available space

    OOCargoQuantity cargoSpaceRequired = qty;
    OOMassUnit contractCargoUnits = (shipCommodityData != nullptr ? shipCommodityData->massUnitForGood(type) : UNITS_TONS); // shared selector (OOCommodities): an Objective-C string

    if (contractCargoUnits == UNITS_KILOGRAMS)
        cargoSpaceRequired /= 1000;
    if (contractCargoUnits == UNITS_GRAMS)
        cargoSpaceRequired /= 1000000;

    if (cargoSpaceRequired > availableCargoSpace())
        return NO;

    if (shipCommodityData != nullptr)
        shipCommodityData->addQuantity(qty, type);

    current_cargo = cargoQuantityOnBoard();

    // roleWeightFlags entries are signed integers, as +numberWithInt: was
    if ((shipCommodityData != nullptr ? shipCommodityData->exportLegalityForGood(type) : 0) > 0) {
        addRoleToPlayer("trader-smuggler");
        roleWeightFlags.insert_or_assign("bought-illegal", oo::PList::signedInteger(1));
    } else {
        addRoleToPlayer("trader");
        roleWeightFlags.insert_or_assign("bought-legal", oo::PList::signedInteger(1));
    }

    contracts.push_back(cargo_info);
    contract_record[cargo_ID] = oo::PList(eta); // +numberWithDouble:

    doScriptEvent(OOJSID("playerEnteredContract"), { oo::PList("cargo"), cargo_info });

    return YES;
}

bool PlayerEntity::removeContract(const std::string& type, unsigned dest) // removes the first match found, returns NO if none found
{
    if (contracts.empty() || dest > 255)
        return NO;

    if (!((UNIVERSE != nullptr ? UNIVERSE->getCommodities() : nullptr) != nullptr ? UNIVERSE->getCommodities()->goodDefined(type) : false))
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

std::vector<std::string> PlayerEntity::passengerList()
{
    return contractsListFromEntries(passengers, NO, NO);
}

std::vector<std::string> PlayerEntity::parcelList()
{
    return contractsListFromEntries(parcels, NO, YES);
}

std::vector<std::string> PlayerEntity::contractList()
{
    return contractsListFromEntries(contracts, YES, NO);
}

std::vector<std::string> PlayerEntity::contractsListFromEntries(const oo::PList::Array& contracts_array, bool forCargo, bool forParcels)
{
    // check  contracts
    std::vector<std::string> result;
    const char* formatString = (forCargo || forParcels) ? "oolite-manifest-item-delivery" : "oolite-manifest-person-travelling";
    unsigned i;
    for (i = 0; i < contracts_array.size(); i++) {
        const oo::PList& contract_info = contracts_array[i];
        const std::optional<std::string> label = OptionalStringForKey(contract_info, forCargo ? std::string(CARGO_KEY_DESCRIPTION) : std::string(PASSENGER_KEY_NAME));
        // the system name can change via script. The following PASSENGER_KEYs are identical to the corresponding CONTRACT_KEYs
        const std::optional<std::string> destination = (UNIVERSE != nullptr ? UNIVERSE->getSystemName(contract_info.get<int>(std::string(CONTRACT_KEY_DESTINATION))) : std::optional<std::string>());
        int dest_eta = contract_info.get<double>(std::string(CONTRACT_KEY_ARRIVAL_TIME)) - ship_clock;
        const std::optional<std::string> deadline = (UNIVERSE != nullptr ? UNIVERSE->shortTimeDescription(dest_eta) : std::optional<std::string>());

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
#define SET_MANIFEST_ROW(obj, color, row) (setManifestScreenRow(obj, color, row, max_rows, page_offset, multi_page))

void PlayerEntity::setGuiToManifestScreen()
{
    OOGUIScreenID oldScreen = gui_screen;

    ::GuiDisplayGen* gui = (UNIVERSE != nullptr ? UNIVERSE->getGui() : nullptr);
    gui_screen = GUI_SCREEN_MANIFEST;
    BOOL guiChanged = (oldScreen != gui_screen);
    if (guiChanged) {
        gui->setStatusPage(0); // need to do this earlier than the rest
    }

    // GUI stuff
    {
        NSInteger current, max;
        oo::Ref<OOColor> subheadColor = gui->colorFromSetting(cxx_kGuiManifestSubheadColor, OOColor::greenColor().get());
        oo::Ref<OOColor> entryColor = gui->colorFromSetting(cxx_kGuiManifestEntryColor, nil);
        oo::Ref<OOColor> scrollColor = gui->colorFromSetting(cxx_kGuiManifestScrollColor, OOColor::greenColor().get());
        oo::Ref<OOColor> noScrollColor = gui->colorFromSetting(cxx_kGuiManifestNoScrollColor, OOColor::darkGrayColor().get());

        const std::vector<std::string> cargoManifest = cargoList();
        const oo::PList missionsList = this->missionsList(); // strings and arrays of strings
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
        if (getHud() != nullptr && (getHud()->isHidden() || getHud()->getAllowBigGui())) {
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
            page_offset = (gui->getStatusPage() - 1) * max_rows;
            if (page_offset < 0 || (NSUInteger)page_offset >= total_rows) {
                gui->setStatusPage(0);
                page_offset = 0;
            }
            multi_page = YES;
        }

        OOGUITabSettings tab_stops;
        tab_stops[0] = 0;
        tab_stops[1] = 256;
        gui->overrideTabs(tab_stops, cxx_kGuiManifestTabs, 3);
        gui->setTabStops(tab_stops);

        // Cargo Manifest
        current_cargo = cargoQuantityOnBoard();

        gui->clearAndKeepBackground(!guiChanged);
        gui->setTitle(OO_DESC("manifest-title"));

        current = current_cargo;
        max = maxAvailableCargoSpace();
        const std::string cargoString = cxx_OOExpandKey("oolite-manifest-cargo", current, max).value_or(std::string());
        current = passengerList().size();
        max = max_passengers;
        const std::string cabinString = cxx_OOExpandKey("oolite-manifest-cabins", current, max).value_or(std::string());
        const oo::PList manifestHeader(oo::PList::Array { oo::PList(cargoString), oo::PList(cabinString) });

        SET_MANIFEST_ROW(manifestHeader, entryColor.get(), cargoRow - 1);

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
                SET_MANIFEST_ROW(oo::PList(std::move(row_info)), subheadColor.get(), cargoRow + i);
            }
        } else {
            SET_MANIFEST_ROW((oo::PList(OO_DESC("manifest-none"))), subheadColor.get(), cargoRow);
            cargoRowCount = 1;
        }

        missionsRow = cargoRow + cargoRowCount + 1;

        // Missions Manifest
        manifestCount = missionsManifest.size();

        if (manifestCount > 0) {
            if (missionsManifest[0].isString()) {
                // then there's at least one without its own heading
                // to go under the generic 'missions' heading
                SET_MANIFEST_ROW((oo::PList(OO_DESC("manifest-missions"))), entryColor.get(), missionsRow - 1);
            } else {
                missionsRow--;
            }

            NSUInteger mmRow = 0;
            for (i = 0; i < manifestCount; i++) {
                const oo::PList& mmEntry = missionsManifest[i];
                if (mmEntry.isString()) {
                    const std::string mmItem = "\t" + oo::DescriptionOf(mmEntry); // @"\t%@"
                    SET_MANIFEST_ROW(oo::PList(mmItem), subheadColor.get(), missionsRow + mmRow);
                    ++mmRow;
                } else if (mmEntry.isArray()) {
                    BOOL isHeading = YES;
                    for (const oo::PList& mmItem : nonNull(mmEntry)) {
                        if (isHeading) {
                            SET_MANIFEST_ROW(mmItem, entryColor.get(), missionsRow + mmRow);
                        } else {
                            SET_MANIFEST_ROW(oo::PList("\t" + oo::DescriptionOf(mmItem)), subheadColor.get(), missionsRow + mmRow); // @"\t%@"
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
                gui->setColor(scrollColor.get(), MANIFEST_SCREEN_ROW_BACK);
                gui->setKey(std::string(GUI_KEY_OK), MANIFEST_SCREEN_ROW_BACK);
            } else {
                gui->setColor(noScrollColor.get(), MANIFEST_SCREEN_ROW_BACK);
                r_start = nextPageRow;
            }
            gui->setArray({ OO_DESC("gui-back"), " <-- " }, MANIFEST_SCREEN_ROW_BACK);

            if (total_rows > max_rows + page_offset) {
                gui->setColor(scrollColor.get(), nextPageRow);
                gui->setKey(std::string(GUI_KEY_OK), nextPageRow);
            } else {
                gui->setColor(noScrollColor.get(), nextPageRow);
                r_end = MANIFEST_SCREEN_ROW_BACK;
            }
            gui->setArray({ OO_DESC("gui-more"), " --> " }, nextPageRow);

            gui->setSelectableRange(NSMakeRange(r_start, r_end + 1 - r_start));
            gui->setSelectedRow(r_start);
        }

        gui->setShowTextCursor(NO);
    }
    /* ends */

    lastTextKey.reset();

    setShowDemoShips(NO);
    if (UNIVERSE != nullptr)
        UNIVERSE->enterGUIViewModeWithMouseInteraction(NO);

    if (guiChanged) {
        gui->setForegroundTextureKey(std::optional<std::string>(status() == STATUS_DOCKED ? "docked_overlay" : "overlay"));
        gui->setBackgroundTextureKey("manifest");
        noteGUIDidChangeFrom(oldScreen, gui_screen);
    }
}

void PlayerEntity::setManifestScreenRow(const oo::PList& object, ::OOColor* color, OOGUIRow row, OOGUIRow max_rows, OOGUIRow offset, bool multi)
{
    OOGUIRow disp_row = row - offset;
    if (disp_row < 1 || disp_row > max_rows)
        return;
    if (multi)
        disp_row++;
    ::GuiDisplayGen* gui = (UNIVERSE != nullptr ? UNIVERSE->getGui() : nullptr);
    if (const std::string* text = object.getIf<std::string>()) {
        gui->setText(*text, disp_row);
    } else if (const oo::PList::Array* elements = object.getIf<oo::PList::Array>()) {
        // its string elements; others were skipped
        std::vector<std::string> strings;
        for (const oo::PList& element : *elements) {
            if (const std::string* string = element.getIf<std::string>())
                strings.push_back(*string);
        }
        gui->setArray(strings, disp_row);
    }
    gui->setColor(color, disp_row);
}

void PlayerEntity::setGuiToDockingReportScreen()
{
    ::GuiDisplayGen* gui = (UNIVERSE != nullptr ? UNIVERSE->getGui() : nullptr);

    OOGUIScreenID oldScreen = gui_screen;
    gui_screen = GUI_SCREEN_REPORT;
    BOOL guiChanged = (oldScreen != gui_screen);

    OOGUIRow i, text_row = 1;

    dockingReport = oo::str::trimWhitespaceAndNewlines(dockingReport);

    // GUI stuff
    {
        gui->clearAndKeepBackground(!guiChanged);
        gui->setTitle(cxx_OOExpandKey("arrival-report-title"));

        for (i = 1; i <= 18; i++) {
            gui->setColor(gui->colorFromSetting(std::string(cxx_kGuiDockingReportColor), nil).get(), 21);
        }

        // dockingReport might be a multi-line message

        while ((!dockingReport.empty()) && (text_row < 18)) {
            if (dockingReport.find('\n') != std::string::npos) {
                while ((dockingReport.find('\n') != std::string::npos) && (text_row < 18)) {
                    const std::size_t line_break = dockingReport.find('\n');
                    const std::string line = dockingReport.substr(0, line_break);
                    dockingReport.erase(0, line_break + 1);
                    text_row = gui->addLongText(line, text_row, GUI_ALIGN_LEFT);
                }
                dockingReport = oo::str::trimWhitespaceAndNewlines(dockingReport);
            } else {
                text_row = gui->addLongText(dockingReport, text_row, GUI_ALIGN_LEFT);
                dockingReport.clear();
            }
        }

        gui->setText(oo::str::formatRuntime(OO_DESC_PLURAL("contracts-cash-@-load-d-of-d-passengers-d-of-d-berths", max_passengers), { cxx_OOCredits(credits), current_cargo, maxAvailableCargoSpace(), passengers.size(), max_passengers }), GUI_ROW_MARKET_CASH);
        gui->setColor(gui->colorFromSetting(std::string(cxx_kGuiDockingSummaryColor), nil).get(), GUI_ROW_MARKET_CASH);

        gui->setText(OO_DESC("press-space-commander"), 21, GUI_ALIGN_CENTER);
        gui->setColor(gui->colorFromSetting(std::string(cxx_kGuiDockingContinueColor), nil).get(), 21);
        gui->setShowTextCursor(NO);
    }
    /* ends */

    lastTextKey.reset();

    setShowDemoShips(NO);
    if (UNIVERSE != nullptr)
        UNIVERSE->enterGUIViewModeWithMouseInteraction(NO);

    if (guiChanged) {
        gui->setForegroundTextureKey(std::string("docked_overlay")); // has to be docked!

        oo::PList bgDescriptor = (UNIVERSE != nullptr ? UNIVERSE->screenTextureDescriptorForKey("report") : oo::PList());
        if (bgDescriptor.isNull())
            bgDescriptor = (UNIVERSE != nullptr ? UNIVERSE->screenTextureDescriptorForKey("status_docked") : oo::PList());
        if (bgDescriptor.isNull())
            bgDescriptor = (UNIVERSE != nullptr ? UNIVERSE->screenTextureDescriptorForKey("status") : oo::PList());
        gui->setBackgroundTextureDescriptor(bgDescriptor);
        noteGUIDidChangeFrom(oldScreen, gui_screen);
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
    GuiDisplayGen* cxxGui = gui; // a nil GUI had no row
    const oo::PList row = (cxxGui != nullptr) ? cxxGui->objectForRow(GUI_ROW_SHIPYARD_LABELS) : oo::PList();
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

OOCreditsQuantity PlayerEntity::priceForShipKey(const std::string& key)
{
    return CurrentShipyardEntry(key).get<unsigned long long>("price"); // SHIPYARD_KEY_PRICE
}

void PlayerEntity::setGuiToShipyardScreen(NSUInteger skip)
{
    OOGUIScreenID oldScreen = gui_screen;

    ::GuiDisplayGen* gui = (UNIVERSE != nullptr ? UNIVERSE->getGui() : nullptr);
    gui_screen = GUI_SCREEN_SHIPYARD;
    BOOL guiChanged = (oldScreen != gui_screen);

    unsigned i;

    // set up initial market if there is none
    OOTechLevelID stationTechLevel;
    ::StationEntity* station = dockedStation();

    if (station != nil) {
        stationTechLevel = (station != nullptr ? station->getEquivalentTechLevel() : 0);
    } else {
        station = (UNIVERSE != nullptr ? UNIVERSE->station() : nullptr);
        stationTechLevel = NSNotFound;
    }
    if ((station != nullptr ? station->getLocalShipyard() : (std::vector<oo::PList>*)nullptr) == nullptr) {
        if (station != nullptr)
            station->generateShipyard(stationTechLevel);
    }

    std::vector<oo::PList>* stationShipyard = (station != nullptr ? station->getLocalShipyard() : (std::vector<oo::PList>*)nullptr);
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
        gui->clearAndKeepBackground(!guiChanged);
        const std::optional<std::string> systemName = (UNIVERSE != nullptr ? UNIVERSE->getSystemName(system_id) : std::optional<std::string>());
        gui->setTitle(ExpandKey("shipyard-title", { { "system", systemName.has_value() ? oo::PList(*systemName) : oo::PList() } }));

        OOGUITabSettings tab_stops;
        tab_stops[0] = 0;
        tab_stops[1] = -258;
        tab_stops[2] = 270;
        tab_stops[3] = 370;
        tab_stops[4] = 450;
        gui->overrideTabs(tab_stops, cxx_kGuiShipyardTabs, 5);
        gui->setTabStops(tab_stops);

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
            gui->setColor(gui->colorFromSetting(cxx_kGuiShipyardHeadingColor, OOColor::greenColor().get()).get(), GUI_ROW_SHIPYARD_LABELS);
            gui->setArray({ OO_DESC("shipyard-shiptype"), OO_DESC("shipyard-price-label"), OO_DESC("shipyard-cargo-label"), OO_DESC("shipyard-speed-label") }, GUI_ROW_SHIPYARD_LABELS);

            if (skip > 0) {
                gui->setColor(gui->colorFromSetting(cxx_kGuiShipyardScrollColor, OOColor::greenColor().get()).get(), GUI_ROW_SHIPYARD_START);
                gui->setArray({ OO_DESC("gui-back"), " <-- " }, GUI_ROW_SHIPYARD_START);
                gui->setKey(oo::str::format("More:%zd", previous), GUI_ROW_SHIPYARD_START);
            }
            for (i = 0; i < (shipCount - skip) && (int)i < rowCount; i++) {
                const oo::PList& ship_info = shipyard[i + skip];
                OOCreditsQuantity ship_price = ship_info.get<unsigned long long>("price"); // SHIPYARD_KEY_PRICE
                const oo::PList* ship = ship_info.get<oo::PList::Dict>("ship"); // SHIPYARD_KEY_SHIP
                std::optional<std::string> shipName = ship != nullptr ? OptionalStringForKey(*ship, "display_name") : std::nullopt;
                if (!shipName && ship != nullptr)
                    shipName = OptionalStringForKey(*ship, "name"); // KEY_NAME
                gui->setColor(gui->colorFromSetting(cxx_kGuiShipyardEntryColor, nil).get(), startRow + i);
                gui->setArray({ " " + shipName.value_or("(null)") + " ", cxx_OOIntCredits(ship_price) }, startRow + i);
                gui->setKey(OptionalStringForKey(ship_info, "id").value_or(""), startRow + i); // SHIPYARD_KEY_ID
            }
            if (i < shipCount - skip) {
                gui->setColor(gui->colorFromSetting(cxx_kGuiShipyardScrollColor, OOColor::greenColor().get()).get(), startRow + i);
                gui->setArray({ OO_DESC("gui-more"), " --> " }, startRow + i);
                gui->setKey(oo::str::format("More:%zu", rowCount + skip), startRow + i);
                i++;
            }

            gui->setSelectableRange(NSMakeRange(GUI_ROW_SHIPYARD_START, i + startRow - GUI_ROW_SHIPYARD_START));
            // ensure that at least one row is selected at all times
            if (shipCount == 1)
                gui->setFirstSelectableRow();
            showShipyardInfoForSelection();
        } else {
            gui->setText(OO_DESC("shipyard-no-ships-available-for-purchase"), GUI_ROW_NO_SHIPS, GUI_ALIGN_CENTER);
            gui->setColor(gui->colorFromSetting(cxx_kGuiShipyardNoshipColor, OOColor::greenColor().get()).get(), GUI_ROW_NO_SHIPS);

            gui->setNoSelectedRow();
        }

        showTradeInInformationFooter();

        gui->setShowTextCursor(NO);
    }

    // the following are necessary...

    setShowDemoShips((shipCount > 0));
    if (UNIVERSE != nullptr)
        UNIVERSE->enterGUIViewModeWithMouseInteraction(YES);

    if (guiChanged) {
        gui->setForegroundTextureKey("docked_overlay");
        gui->setBackgroundTextureKey("shipyard");
    }
}

void PlayerEntity::showShipyardInfoForSelection()
{
    NSUInteger i;
    ::GuiDisplayGen* gui = (UNIVERSE != nullptr ? UNIVERSE->getGui() : nullptr);
    OOGUIRow sel_row = gui->getSelectedRow();

    if (sel_row <= 0)
        return;

    std::vector<std::string> row_info = ShipyardLabelsRow(gui);

    const oo::PList info = CurrentShipyardEntry(gui->keyForRow(sel_row));

    // clean up the display ready for the newly-selected ship (if there is one)
    row_info[2] = "";
    row_info[3] = "";
    for (i = GUI_ROW_SHIPYARD_INFO_START; i < GUI_ROW_MARKET_CASH - 1; i++) {
        gui->setText("", i);
        gui->setColor(gui->colorFromSetting(cxx_kGuiShipyardDescriptionColor, OOColor::greenColor().get()).get(), i);
    }
    if (UNIVERSE != nullptr)
        UNIVERSE->removeDemoShips();

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
        showTradeInInformationFooter();
        i = gui->addLongText(salesPitch, GUI_ROW_SHIPYARD_INFO_START, GUI_ALIGN_LEFT);
        if (i - 1 >= GUI_ROW_MARKET_CASH - 1) {
            gui->setColor(gui->colorFromSetting(cxx_kGuiShipyardDescriptionColor, OOColor::greenColor().get()).get(), i - 1);
            gui->setColor(gui->colorFromSetting(cxx_kGuiShipyardDescriptionColor, OOColor::greenColor().get()).get(), GUI_ROW_MARKET_CASH - 1);
        }

        // now display the ship
        const std::optional<std::string> shipKey = OptionalStringForKey(info, "shipdata_key"); // SHIPYARD_KEY_SHIPDATA_KEY
        if (shipKey) {
            showShipyardModel(*shipKey, shipDict, info.get<unsigned short>("personality")); // SHIPYARD_KEY_PERSONALITY
        }
    } else {
        // the key is a particular model of ship which we must expand...
        // build an array from the entries for that model in the currentShipyard TODO
        //
    }

    gui->setArray(row_info, GUI_ROW_SHIPYARD_LABELS);
}

void PlayerEntity::showTradeInInformationFooter()
{
    ::GuiDisplayGen* gui = (UNIVERSE != nullptr ? UNIVERSE->getGui() : nullptr);
    OOCreditsQuantity tradeIn = tradeInValue();
    OOCreditsQuantity total = tradeIn + credits;
    const oo::PList shipType = oo::PList(getDisplayName().value_or(""));

    gui->setColor(gui->colorFromSetting(cxx_kGuiShipyardTradeinColor, nil).get(), GUI_ROW_MARKET_CASH - 1);
    gui->setColor(gui->colorFromSetting(cxx_kGuiShipyardTradeinColor, nil).get(), GUI_ROW_MARKET_CASH);
    gui->setText(ExpandKey("shipyard-trade-in-value", { { "shipType", shipType }, { "tradeIn", oo::PList::unsignedInteger(tradeIn) } }), GUI_ROW_MARKET_CASH - 1);
    gui->setText(ExpandKey("shipyard-total-available-with-trade-in", { { "shipType", shipType }, { "total", oo::PList::unsignedInteger(total) }, { "credits", oo::PList::unsignedInteger(credits) }, { "tradeIn", oo::PList::unsignedInteger(tradeIn) } }), GUI_ROW_MARKET_CASH);
}

void PlayerEntity::showShipyardModel(const std::string& shipKey, const oo::PList& shipData, uint16_t personality)
{
    if (dockedStation() == nil)
        return;
    showShipModelWithKey(shipKey, shipData, personality, 1.2, 0.8, 6.4, "shipyard");
}

NSInteger PlayerEntity::missingSubEntitiesAdjustment()
{
    // each missing subentity depreciates the ship by 5%, up to a maximum of 35% depreciation.
    NSUInteger percent = 5 * (maxShipSubEntities() - shipSubEntities().size());
    return (percent > 35 ? 35 : percent);
}

OOCreditsQuantity PlayerEntity::tradeInValue()
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
    unsigned long long value = (UNIVERSE != nullptr ? UNIVERSE->tradeInValueForCommanderDictionary(commanderDataDictionary()) : 0);
    value -= value * 0.006 * missingSubEntitiesAdjustment(); // TODO: 0.006 might need rethinking.
    const unsigned long long rounded = ((value * 75 * ship_trade_in_factor) + 5000) / 10000; // Multiply by two percentages, divide by 100*100. The +5000 is to get normal rounding.
    value = cunningFee(rounded, 0.005);
    return value * 10;
}

bool PlayerEntity::buySelectedShip()
{
    ::GuiDisplayGen* gui = (UNIVERSE != nullptr ? UNIVERSE->getGui() : nullptr);
    OOGUIRow selectedRow = gui->getSelectedRow();

    if (selectedRow <= 0)
        return NO;

    const std::optional<std::string> key = gui->keyForRow(selectedRow);

    if (key && oo::str::hasPrefix(*key, "More:")) {
        const std::vector<std::string> keyParts = oo::str::split(*key, ":");
        NSInteger fromShip = keyParts.size() > 1 ? oo::str::longLongValue(keyParts[1]) : 0;
        if (fromShip < 0)
            fromShip = 0;

        setGuiToShipyardScreen(fromShip);
        if (UNIVERSE->getGui()->getSelectedRow() < 0) {
            UNIVERSE->getGui()->setSelectedRow(GUI_ROW_SHIPYARD_START);
        }
        if (fromShip == 0) {
            UNIVERSE->getGui()->setSelectedRow(GUI_ROW_SHIPYARD_START + MAX_ROWS_SHIPS_FOR_SALE - 1);
        }
        // next bit or the first ship on the list gets wrongly previewed
        // clean up the display
        std::vector<std::string> row_info = ShipyardLabelsRow(gui);
        row_info[2] = "";
        row_info[3] = "";
        NSUInteger i;
        for (i = GUI_ROW_SHIPYARD_INFO_START; i < GUI_ROW_MARKET_CASH - 1; i++) {
            gui->setText("", i);
            gui->setColor(gui->colorFromSetting(cxx_kGuiShipyardDescriptionColor, OOColor::greenColor().get()).get(), i);
        }
        gui->setArray(row_info, GUI_ROW_SHIPYARD_LABELS);
        if (UNIVERSE != nullptr)
            UNIVERSE->removeDemoShips();
        return YES;
    }

    // first check you can afford it!
    const oo::PList shipInfo = CurrentShipyardEntry(key);
    OOCreditsQuantity price = shipInfo.get<unsigned long long>("price"); // SHIPYARD_KEY_PRICE
    OOCreditsQuantity tradeIn = tradeInValue();

    if (credits + tradeIn < price * 10)
        return NO; // you can't afford it!

    // from this point, the player is committed to buying - raise a pre-buy script event
    const std::optional<std::string> shipDataKey = OptionalStringForKey(shipInfo, "shipdata_key"); // SHIPYARD_KEY_SHIPDATA_KEY
    std::vector<oo::PList>* dockedShipyard = (dockedStation() != nullptr ? dockedStation()->getLocalShipyard() : (std::vector<oo::PList>*)nullptr);
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
    doScriptEvent(OOJSID("playerWillBuyNewShip"), buyArguments);

    // sell all the commodities carried
    for (const std::string& good : (shipCommodityData != nullptr ? shipCommodityData->goods() : std::vector<std::string>())) {
        trySellingCommodity(good, YES);
    }
    // We tried to sell everything. If there are still items present in our inventory, it
    // means that the market got saturated (quantity in station > 127 t) before we could sell
    // it all. Everything that could not be sold will be lost. -- Nikos 20083012

    // pay over the mazoolah
    credits -= 10 * price - tradeIn;

    const oo::PList* shipDictNode = shipInfo.get<oo::PList::Dict>("ship"); // SHIPYARD_KEY_SHIP
    newShipCommonSetup(shipDataKey.value_or(""), shipInfo, shipDictNode != nullptr ? *shipDictNode : oo::PList());

    // this ship has a clean record
    legalStatusValue = 0;

    const oo::PList* extras = shipInfo.get<oo::PList::Array>("extras"); // KEY_EQUIPMENT_EXTRAS
    for (std::size_t i = 0; extras != nullptr && i < extras->count(); i++) {
        const std::optional<std::string> eq_key = OptionalStringAt(*extras, i);
        if (eq_key == "EQ_PASSENGER_BERTH") {
            max_passengers++;
            max_cargo -= PASSENGER_BERTH_SPACE;
        } else {
            addEquipmentItem(eq_key.value_or(std::string()), YES, "newShip"); // none: "", as nil was
        }
    }

    // add bought ship to shipyard_record
    const std::optional<std::string> shipID = OptionalStringForKey(shipInfo, "id"); // SHIPYARD_KEY_ID
    if (shipID) {
        const std::optional<std::string> dataKey = this->shipDataKey();
        shipyard_record[*shipID] = dataKey ? oo::PList(*dataKey) : oo::PList(); // (a nil key raised)
    }

    // remove the ship from the localShipyard
    dockedShipyard = (dockedStation() != nullptr ? dockedStation()->getLocalShipyard() : (std::vector<oo::PList>*)nullptr);
    if (dockedShipyard != nullptr)
        dockedShipyard->erase(dockedShipyard->begin() + (selectedRow - GUI_ROW_SHIPYARD_START));

    // perform the transformation
    if (!setCommanderDataFromDictionary(commanderDataDictionary()))
        return NO; // gather up all the info

    setStatus(STATUS_DOCKED);
    setEntityPersonalityInt(shipInfo.get<unsigned short>("personality")); // SHIPYARD_KEY_PERSONALITY

    // adjust the clock forward by an hour
    ship_clock_adjust += 3600.0;

    // finally we can get full hock if we sell it back
    ship_trade_in_factor = 100;

    if ((UNIVERSE != nullptr ? UNIVERSE->getAutoSave() : false)) {
        if (UNIVERSE != nullptr)
            UNIVERSE->setAutoSaveNow(YES);
    }

    return YES;
}

bool PlayerEntity::replaceShipWithNamedShip(const std::string& shipKey)
{

    const oo::PList ship_info = OOShipRegistry::sharedRegistry()->shipyardInfoForKey(shipKey);

    const oo::PList ship_base_dict = OOShipRegistry::sharedRegistry()->shipInfoForKey(shipKey);

    if (ship_info.isNull() || ship_base_dict.isNull()) {
        return NO;
    }

    // from this point, the player is committed to replacing - raise a pre-replace script event
    doScriptEvent(OOJSID("playerWillReplaceShip"), { oo::PList(shipKey) });

    newShipCommonSetup(shipKey, ship_info, ship_base_dict);

    // perform the transformation
    if (!setCommanderDataFromDictionary(commanderDataDictionary()))
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
            addEquipmentItem(eq_key.value_or(std::string()), YES, "newShip"); // none: "", as nil was
        }
    }

    setEntityPersonalityInt(ship_info.get<unsigned short>("personality")); // SHIPYARD_KEY_PERSONALITY

    return YES;
}

void PlayerEntity::newShipCommonSetup(const std::string& shipKey, const oo::PList& ship_info, const oo::PList& ship_base_dict)
{
    // Zero out our manifest.
    if (shipCommodityData != nullptr)
        shipCommodityData->removeAllGoods();
    current_cargo = 0;

    // drop all passengers
    passengers.clear();
    passenger_record.clear();

    // parcels stay the same; easy to transfer between ships
    // contracts stay the same, so if you default - tough!
    // okay we need to switch the model used, lots of the stats, and add all the extras

    clearSubEntities();

    setShipDataKey(shipKey);

    const oo::PList& shipDict = ship_base_dict;

    // get a full tank for free
    setFuel(fuelCapacity());

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
    max_cargo = (UNIVERSE != nullptr ? UNIVERSE->maxCargoForShip(shipDataKey().value_or(std::string())) : 0);

    // ensure all missiles are tidied up and start at pylon 0
    tidyMissilePylons();

    // get missiles from ship_info
    missiles = shipDict.get<unsigned int>("missiles");

    // reset max_passengers
    max_passengers = 0;

    // reset and refill extra_equipment then set flags from it

    // keep track of portable equipment..

    std::set<std::string> portable_equipment;

    for (const std::string& eq_desc : equipmentKeys()) {
        ::OOEquipmentType* item = OOEquipmentType::equipmentTypeWithIdentifier(eq_desc).get();
        if ((item != nullptr ? item->isPortableBetweenShips() : false))
            portable_equipment.insert(eq_desc);
    }

    // remove ALL
    removeAllEquipment();

    // restore  portable equipment (in key order; the set it replaced gave hash order)
    for (const std::string& eq_desc : portable_equipment) {
        addEquipmentItem(eq_desc, NO, "portable");
    }

    // set up subentities from scratch; new ship could carry more or fewer than the old one
    setUpSubEntities();

    // clear old ship names
    setShipClassName(OptionalStringForKey(shipDict, "name"));
    setShipUniqueName("");

    // new ship, so lose some memory of actions
    // new ship, so lose some memory of player actions
    if (ship_kills >= 6400) {
        clearRolesFromPlayer(0.1);
    } else if (ship_kills >= 2560) {
        clearRolesFromPlayer(0.25);
    } else {
        clearRolesFromPlayer(0.5);
    }
}

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
