/*

OOJSPlayer.m (QuickJS-ng)

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

#include "OOJSPlayer.h"
#include "EntityOOJavaScriptExtensions.h"
#include "OOJSEntity.h"
#include "OOJSShip.h"
#include "OOJSVector.h"
#include "OOJavaScriptEngine.h"

#include "PlayerEntity.h"
#include "PlayerEntityContracts.h"
#include "PlayerEntityLegacyScriptEngine.h"
#include "PlayerEntityScriptMethods.h"

#include "OOConstToString.h"
#include "OOFunctionAttributes.h"
#include "OOStringParsing.h"

#include "OOObjCPList.h"

/*
        C++20 since bead oo-5rva, converted the way bead oo-ppc converted OOJSVector.mm (proposed
        ADR-0056 amendment oo-ppc). The JS class was already C++ on QuickJS-ng;
        OOJS_NATIVE_ENTER/EXIT and OOJS_PROFILE_ENTER/EXIT are C++ try/catch and scope guards
        (OOJSEngineNativeWrappers.h); BOOL/YES/NO are bool/true/false. Nothing else in the file was
        Objective-C: the player (PlayerEntity), the universe and ShipEntity, which are not converted,
        are still messaged, which is why the file is still .mm until Phase 4.
*/

static JSClassID sPlayerClassID;

static JSClassDef sPlayerClass = {
    .class_name = "Player",
    .finalizer = OOJSObjectWrapperFinalize,
};

static JSValue PlayerGetProperty(OOJS_GETTER_ARGS);
static JSValue PlayerSetProperty(OOJS_SETTER_ARGS);

static JSValue PlayerAddMessageToArrivalReport(OOJS_NATIVE_ARGS);
static JSValue PlayerAudioMessage(OOJS_NATIVE_ARGS);
static JSValue PlayerCommsMessage(OOJS_NATIVE_ARGS);
static JSValue PlayerConsoleMessage(OOJS_NATIVE_ARGS);
static JSValue PlayerEndScenario(OOJS_NATIVE_ARGS);
static JSValue PlayerIncreaseContractReputation(OOJS_NATIVE_ARGS);
static JSValue PlayerDecreaseContractReputation(OOJS_NATIVE_ARGS);
static JSValue PlayerIncreasePassengerReputation(OOJS_NATIVE_ARGS);
static JSValue PlayerDecreasePassengerReputation(OOJS_NATIVE_ARGS);
static JSValue PlayerIncreaseParcelReputation(OOJS_NATIVE_ARGS);
static JSValue PlayerDecreaseParcelReputation(OOJS_NATIVE_ARGS);
static JSValue PlayerReplaceShip(OOJS_NATIVE_ARGS);
static JSValue PlayerSetEscapePodDestination(OOJS_NATIVE_ARGS);
static JSValue PlayerSetPlayerRole(OOJS_NATIVE_ARGS);
static JSValue PlayerStopAudioMessage(OOJS_NATIVE_ARGS);

enum {
    // Property IDs
    kPlayer_alertAltitude, // low altitude alert flag, boolean, read-only
    kPlayer_alertCondition, // alert level, integer, read-only
    kPlayer_alertEnergy, // low energy alert flag, boolean, read-only
    kPlayer_alertHostiles, // hostiles present alert flag, boolean, read-only
    kPlayer_alertMassLocked, // mass lock alert flag, boolean, read-only
    kPlayer_alertTemperature, // cabin temperature alert flag, boolean, read-only
    kPlayer_bounty, // bounty, unsigned int, read/write
    kPlayer_contractReputation, // reputation for cargo contracts, integer, read only
    kPlayer_contractReputationPrecise, // reputation for cargo contracts, float, read only
    kPlayer_credits, // credit balance, float, read/write
    kPlayer_dockingClearanceStatus, // docking clearance status, string, read only
    kPlayer_escapePodRescueTime, // override for the amount of time an escape pod rescue takes, read/write
    kPlayer_legalStatus, // legalStatus, string, read-only
    kPlayer_name, // Player name, string, read/write
    kPlayer_parcelReputation, // reputation for parcel contracts, integer, read-only
    kPlayer_parcelReputationPrecise, // reputation for parcel contracts, float, read-only
    kPlayer_passengerReputation, // reputation for passenger contracts, integer, read-only
    kPlayer_passengerReputationPrecise, // reputation for passenger contracts, float, read-only
    kPlayer_rank, // rank, string, read-only
    kPlayer_roleWeights, // role weights, array, read-only
    kPlayer_score, // kill count, integer, read/write
    kPlayer_trumbleCount, // number of trumbles, integer, read-only
};

static const JSCFunctionListEntry sPlayerProperties[] = {
    // JS name, getter, setter, ID
    OOJS_PROPERTY_RO("alertAltitude", PlayerGetProperty, kPlayer_alertAltitude),
    OOJS_PROPERTY_RO("alertCondition", PlayerGetProperty, kPlayer_alertCondition),
    OOJS_PROPERTY_RO("alertEnergy", PlayerGetProperty, kPlayer_alertEnergy),
    OOJS_PROPERTY_RO("alertHostiles", PlayerGetProperty, kPlayer_alertHostiles),
    OOJS_PROPERTY_RO("alertMassLocked", PlayerGetProperty, kPlayer_alertMassLocked),
    OOJS_PROPERTY_RO("alertTemperature", PlayerGetProperty, kPlayer_alertTemperature),
    OOJS_PROPERTY_RW("bounty", PlayerGetProperty, PlayerSetProperty, kPlayer_bounty),
    OOJS_PROPERTY_RO("contractReputation", PlayerGetProperty, kPlayer_contractReputation),
    OOJS_PROPERTY_RO("contractReputationPrecise", PlayerGetProperty, kPlayer_contractReputationPrecise),
    OOJS_PROPERTY_RW("credits", PlayerGetProperty, PlayerSetProperty, kPlayer_credits),
    OOJS_PROPERTY_RO("dockingClearanceStatus", PlayerGetProperty, kPlayer_dockingClearanceStatus),
    OOJS_PROPERTY_RW("escapePodRescueTime", PlayerGetProperty, PlayerSetProperty, kPlayer_escapePodRescueTime),
    OOJS_PROPERTY_RO("legalStatus", PlayerGetProperty, kPlayer_legalStatus),
    OOJS_PROPERTY_RW("name", PlayerGetProperty, PlayerSetProperty, kPlayer_name),
    OOJS_PROPERTY_RO("parcelReputation", PlayerGetProperty, kPlayer_parcelReputation),
    OOJS_PROPERTY_RO("parcelReputationPrecise", PlayerGetProperty, kPlayer_parcelReputationPrecise),
    OOJS_PROPERTY_RO("passengerReputation", PlayerGetProperty, kPlayer_passengerReputation),
    OOJS_PROPERTY_RO("passengerReputationPrecise", PlayerGetProperty, kPlayer_passengerReputationPrecise),
    OOJS_PROPERTY_RO("rank", PlayerGetProperty, kPlayer_rank),
    OOJS_PROPERTY_RO("roleWeights", PlayerGetProperty, kPlayer_roleWeights),
    OOJS_PROPERTY_RW("score", PlayerGetProperty, PlayerSetProperty, kPlayer_score),
    OOJS_PROPERTY_RO("trumbleCount", PlayerGetProperty, kPlayer_trumbleCount),
};

static const JSCFunctionListEntry sPlayerMethods[] = {
    // JS name, min args, function
    JS_CFUNC_DEF("addMessageToArrivalReport", 1, PlayerAddMessageToArrivalReport),
    JS_CFUNC_DEF("audioMessage", 1, PlayerAudioMessage),
    JS_CFUNC_DEF("commsMessage", 1, PlayerCommsMessage),
    JS_CFUNC_DEF("consoleMessage", 1, PlayerConsoleMessage),
    JS_CFUNC_DEF("decreaseContractReputation", 0, PlayerDecreaseContractReputation),
    JS_CFUNC_DEF("decreaseParcelReputation", 0, PlayerDecreaseParcelReputation),
    JS_CFUNC_DEF("decreasePassengerReputation", 0, PlayerDecreasePassengerReputation),
    JS_CFUNC_DEF("endScenario", 1, PlayerEndScenario),
    JS_CFUNC_DEF("increaseContractReputation", 0, PlayerIncreaseContractReputation),
    JS_CFUNC_DEF("increaseParcelReputation", 0, PlayerIncreaseParcelReputation),
    JS_CFUNC_DEF("increasePassengerReputation", 0, PlayerIncreasePassengerReputation),
    JS_CFUNC_DEF("replaceShip", 1, PlayerReplaceShip),
    JS_CFUNC_DEF("setEscapePodDestination", 1, PlayerSetEscapePodDestination), // null destination must be set explicitly
    JS_CFUNC_DEF("setPlayerRole", 1, PlayerSetPlayerRole),
    JS_CFUNC_DEF("stopAudioMessage", 0, PlayerStopAudioMessage),
};

void InitOOJSPlayer(JSContext* context, JSValueConst global)
{
    OOJSRegisterClass(&sPlayerClassID, &sPlayerClass);
    OOJSInitClass(context, global, sPlayerClassID, JS_UNDEFINED, OOJSUnconstructableConstruct, 0,
        sPlayerProperties, OOJS_COUNT(sPlayerProperties), sPlayerMethods, OOJS_COUNT(sPlayerMethods), NULL, 0);
    OOJSRegisterObjectConverter(sPlayerClassID, OOJSBasicPrivateObjectConverter);

    /*	Create player object as a property of the global object. As before, it
            has no private data. The global object owns the only reference; the
            property is read-only and permanent, so JSPlayerObject() can look it
            up there rather than keeping a reference that must be dropped on
            reset.
    */
    JSValue playerObject = JS_NewObjectClass(context, (int)sPlayerClassID);
    JS_DefinePropertyValueStr(context, global, "player", playerObject, OOJS_PROP_READONLY);
}

JSClassID JSPlayerClassID(void)
{
    return sPlayerClassID;
}

JSValue JSPlayerObject(void)
{
    JSContext* context = OOJSAcquireContext();
    // Not -[OOJavaScriptEngine globalObject]: this is used while the engine is being set up.
    JSValue global = JS_GetGlobalObject(context);
    JSValue result = JS_GetPropertyStr(context, global, "player");
    JS_FreeValue(context, global);
    OOJSRelinquishContext(context);
    return result;
}

PlayerEntity* OOPlayerForScripting(void)
{
    PlayerEntity* player = PLAYER;
    if (player != nullptr)
        player->setScriptTargetToSelf();

    return player;
}

static JSValue PlayerGetProperty(OOJS_GETTER_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    oo::PList result; // null maps to null
    PlayerEntity* player = OOPlayerForScripting();

    switch (magic) {
    case kPlayer_name:
        if (const std::optional<std::string> name = (player != nullptr ? player->commanderName() : std::optional<std::string>()))
            result = oo::PList(*name);
        break;

    case kPlayer_score:
        return JS_NewInt32(context, (player != nullptr ? player->PlayerEntity::score() : unsigned { })); // qualified: the final overrider, so the binding test stands in for it

    case kPlayer_credits:
        return JS_NewNumber(context, (player != nullptr ? player->creditBalance() : 0.0));

    case kPlayer_rank: {
        const std::optional<std::string> text = cxx_OODisplayRatingStringFromKillCount((player != nullptr ? player->PlayerEntity::score() : unsigned { })); // qualified: the final overrider, so the binding test stands in for it
        return OOJSValueFromPList(context, text.has_value() ? oo::PList(*text) : oo::PList());
    }

    case kPlayer_legalStatus: {
        const std::optional<std::string> text = cxx_OODisplayStringFromLegalStatus((player != nullptr ? player->getLegalStatus() : int { }));
        return OOJSValueFromPList(context, text.has_value() ? oo::PList(*text) : oo::PList());
    }

    case kPlayer_alertCondition:
        return JS_NewInt32(context, (player != nullptr ? player->PlayerEntity::getAlertCondition() : OOAlertCondition { })); // qualified: the final overrider, so the binding test stands in for it

    case kPlayer_alertTemperature:
        return OOJSValueFromBOOL((player != nullptr ? player->getAlertFlags() : int { }) & ALERT_FLAG_TEMP);

    case kPlayer_alertMassLocked:
        return OOJSValueFromBOOL((player != nullptr ? player->getAlertFlags() : int { }) & ALERT_FLAG_MASS_LOCK);

    case kPlayer_alertAltitude:
        return OOJSValueFromBOOL((player != nullptr ? player->getAlertFlags() : int { }) & ALERT_FLAG_ALT);

    case kPlayer_alertEnergy:
        return OOJSValueFromBOOL((player != nullptr ? player->getAlertFlags() : int { }) & ALERT_FLAG_ENERGY);

    case kPlayer_alertHostiles:
        return OOJSValueFromBOOL((player != nullptr ? player->getAlertFlags() : int { }) & ALERT_FLAG_HOSTILES);

    case kPlayer_escapePodRescueTime:
        return JS_NewNumber(context, (player != nullptr ? player->escapePodRescueTime() : 0.0));

    case kPlayer_trumbleCount:
        return JS_NewNumber(context, (player != nullptr ? player->PlayerEntity::getTrumbleCount() : 0)); // qualified: the final overrider, so the binding test stands in for it

        /* For compatibility with previous versions, these are still on
         * a -7 to +7 scale */
    case kPlayer_contractReputation:
        return JS_NewNumber(context, (int)(((float)(player != nullptr ? player->contractReputation() : int { })) / 10.0));

    case kPlayer_passengerReputation:
        return JS_NewNumber(context, (int)(((float)(player != nullptr ? player->passengerReputation() : int { })) / 10.0));

    case kPlayer_parcelReputation:
        return JS_NewNumber(context, (int)(((float)(player != nullptr ? player->parcelReputation() : int { })) / 10.0));

        /* Full-precision reputations */
    case kPlayer_contractReputationPrecise:
        return JS_NewNumber(context, ((float)(player != nullptr ? player->contractReputation() : int { })) / 10.0);

    case kPlayer_passengerReputationPrecise:
        return JS_NewNumber(context, ((float)(player != nullptr ? player->passengerReputation() : int { })) / 10.0);

    case kPlayer_parcelReputationPrecise:
        return JS_NewNumber(context, ((float)(player != nullptr ? player->parcelReputation() : int { })) / 10.0);

    case kPlayer_dockingClearanceStatus:
        // EMMSTRAN: OOConstToJSString-ify this.
        return OOJSValueFromPList(context, oo::PList(cxx_DockingClearanceStatusToString((player != nullptr ? player->getDockingClearanceStatus() : OODockingClearanceStatus { }))));

    case kPlayer_bounty:
        return JS_NewInt32(context, (player != nullptr ? player->getLegalStatus() : int { }));

    case kPlayer_roleWeights: {
        const std::vector<std::string> roleWeights = (player != nullptr ? player->getRoleWeights() : std::vector<std::string>());
        result = oo::PList(oo::PList::Array(roleWeights.begin(), roleWeights.end()));
    } break;

    default:
        OOJSReportBadPropertySelector(context, thisObj, magic, sPlayerProperties, OOJS_COUNT(sPlayerProperties));
        return OOJSNativeFailure(context);
    }

    return OOJSValueFromPList(context, result);

    OOJS_NATIVE_EXIT
}

static JSValue PlayerSetProperty(OOJS_SETTER_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    PlayerEntity* player = OOPlayerForScripting();
    double fValue;
    int32_t iValue;
    std::optional<std::string> sValue;

    switch (magic) {
    case kPlayer_name:
        sValue = cxx_OOStringFromJSValue(context, value);
        if (sValue.has_value()) {
            if (player != nullptr)
                player->setCommanderName(sValue);
            return JS_UNDEFINED;
        }
        break;

    case kPlayer_score:
        if (OOJSValueToInt32(context, value, &iValue)) {
            iValue = MAX(iValue, 0);
            if (player != nullptr)
                player->setScore(iValue);
            return JS_UNDEFINED;
        }
        break;

    case kPlayer_credits:
        if (JS_ToFloat64(context, &fValue, value) == 0) {
            if (player != nullptr)
                player->setCreditBalance(fValue);
            return JS_UNDEFINED;
        }
        break;

    case kPlayer_bounty:
        if (OOJSValueToInt32(context, value, &iValue)) {
            if (iValue < 0)
                iValue = 0;
            if (player != nullptr)
                player->PlayerEntity::setBounty(iValue, kOOLegalStatusReasonByScript); // qualified: the final overrider, so the binding test stands in for it
            return JS_UNDEFINED;
        }
        break;

    case kPlayer_escapePodRescueTime:
        if (JS_ToFloat64(context, &fValue, value) == 0) {
            if (player != nullptr)
                player->setEscapePodRescueTime(fValue);
            return JS_UNDEFINED;
        }
        break;

    default:
        OOJSReportBadPropertySelector(context, thisObj, magic, sPlayerProperties, OOJS_COUNT(sPlayerProperties));
        return OOJSNativeFailure(context);
    }

    OOJSReportBadPropertyValue(context, thisObj, magic, sPlayerProperties, OOJS_COUNT(sPlayerProperties), value);
    return OOJSNativeFailure(context);

    OOJS_NATIVE_EXIT
}

// *** Methods ***

// commsMessage(message : String [, duration : Number])
static JSValue PlayerCommsMessage(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    std::optional<std::string> message;
    double time = 4.5;
    bool gotTime = true;

    if (argc > 0)
        message = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
    if (argc > 1)
        gotTime = (JS_ToFloat64(context, &time, OOJS_ARGV[1]) == 0);
    if (!message.has_value() || !gotTime) {
        cxx_OOJSReportBadArguments(context, "Player", "commsMessage", argc, OOJS_ARGV, std::nullopt, "message and optional duration");
        return OOJSNativeFailure(context);
    }

    if (UNIVERSE != nullptr)
        UNIVERSE->addCommsMessage(message, time);
    if (PLAYER != nullptr)
        PLAYER->ShipEntity::doScriptEvent(OOJSID("commsMessageReceived"), { oo::PList(*message), oo::PList() }); // qualified: the final overrider, so the binding test stands in for it
    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}

// consoleMessage(message : String [, duration : Number])
static JSValue PlayerConsoleMessage(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    std::optional<std::string> message;
    double time = 3.0;
    bool gotTime = true;

    if (argc > 0)
        message = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
    if (argc > 1)
        gotTime = (JS_ToFloat64(context, &time, OOJS_ARGV[1]) == 0);
    if (!message.has_value() || !gotTime) {
        cxx_OOJSReportBadArguments(context, "Player", "consoleMessage", argc, OOJS_ARGV, std::nullopt, "message and optional duration");
        return OOJSNativeFailure(context);
    }

    if (UNIVERSE != nullptr)
        UNIVERSE->addMessage(message, time);
    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}

// endScenario(scenario : String)
static JSValue PlayerEndScenario(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    std::optional<std::string> scenario;

    if (argc > 0)
        scenario = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
    if (!scenario.has_value()) {
        cxx_OOJSReportBadArguments(context, "Player", "endScenario", argc, OOJS_ARGV, std::nullopt, "scenario key");
        return OOJSNativeFailure(context);
    }

    OOJS_RETURN_BOOL((PLAYER != nullptr ? PLAYER->endScenario(*scenario) : false));

    OOJS_NATIVE_EXIT
}

// increaseContractReputation()
static JSValue PlayerIncreaseContractReputation(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    if (PlayerEntity* player = OOPlayerForScripting())
        player->increaseContractReputation(1);
    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}

// decreaseContractReputation()
static JSValue PlayerDecreaseContractReputation(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    if (PlayerEntity* player = OOPlayerForScripting())
        player->decreaseContractReputation(1);
    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}

// increaseParcelReputation()
static JSValue PlayerIncreaseParcelReputation(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    if (PlayerEntity* player = OOPlayerForScripting())
        player->increaseParcelReputation(1);
    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}

// decreaseParcelReputation()
static JSValue PlayerDecreaseParcelReputation(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    if (PlayerEntity* player = OOPlayerForScripting())
        player->decreaseParcelReputation(1);
    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}

// increasePassengerReputation()
static JSValue PlayerIncreasePassengerReputation(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    if (PlayerEntity* player = OOPlayerForScripting())
        player->increasePassengerReputation(1);
    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}

// decreasePassengerReputation()
static JSValue PlayerDecreasePassengerReputation(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    if (PlayerEntity* player = OOPlayerForScripting())
        player->decreasePassengerReputation(1);
    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}

// addMessageToArrivalReport(message : String)
static JSValue PlayerAddMessageToArrivalReport(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    std::optional<std::string> report;
    PlayerEntity* player = OOPlayerForScripting();

    if (argc > 0)
        report = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
    if (!report.has_value()) {
        cxx_OOJSReportBadArguments(context, "Player", "addMessageToArrivalReport", MIN(argc, 1), OOJS_ARGV, std::nullopt, "string (arrival message)");
        return OOJSNativeFailure(context);
    }

    if (player != nullptr)
        player->addMessageToReport(*report);
    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}

static JSValue PlayerAudioMessage(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    std::optional<std::string> audioMessage;
    PlayerEntity* player = OOPlayerForScripting();

    if (argc > 0)
        audioMessage = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
    if (!audioMessage.has_value()) {
        cxx_OOJSReportBadArguments(context, "Player", "audioMessage", argc, OOJS_ARGV, std::nullopt, "audiomessage (string)");
        return OOJSNativeFailure(context);
    }

    if ((player != nullptr ? player->getIsSpeechOn() : OOSpeechSettings { }) >= OOSPEECHSETTINGS_COMMS) {
        if (UNIVERSE != nullptr)
            UNIVERSE->startSpeakingString(*audioMessage);
    }
    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}

// replaceShip (shipyard-key : String)
static JSValue PlayerReplaceShip(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    std::optional<std::string> shipKey;
    PlayerEntity* player = OOPlayerForScripting();
    bool success = false;
    int32_t personality = 0;

    if (argc > 0)
        shipKey = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
    if (!shipKey.has_value()) {
        cxx_OOJSReportBadArguments(context, "Player", "replaceShip", MIN(argc, 1), OOJS_ARGV, std::nullopt, "string (shipyard key)");
        return OOJSNativeFailure(context);
    }

    if (EXPECT_NOT(!((player != nullptr ? player->status() : OOEntityStatus { }) == STATUS_DOCKED))) {
        cxx_OOJSReportError(context, "Player.replaceShip() only works while the player is docked.");
        return OOJSNativeFailure(context);
    }

    success = (player != nullptr ? player->replaceShipWithNamedShip(*shipKey) : false);
    if (argc > 1) {
        // As before, an invalid personality is ignored (personality stays 0); don't leave the conversion error pending.
        if (!OOJSValueToInt32(context, OOJS_ARGV[1], &personality))
            JS_FreeValue(context, JS_GetException(context));
        if (personality >= 0 && (uint16_t)personality < ENTITY_PERSONALITY_MAX) {
            if (player != nullptr)
                player->setEntityPersonalityInt((uint16_t)personality);
        }
    }

    if (success) {
        // The player's entity node, as the next event's: its JS value is the C++ player's, which its
        // object's -oo_jsValueInContext: answered; qualified: the final overrider, so the binding test stands in for it.
        if (player != nullptr)
            player->ShipEntity::doScriptEvent(OOJSID("playerReplacedShip"), { oo::EntityObjectNode(player) });
        // slightly misnamed world event now - to be deprecated
        if (player != nullptr)
            player->ShipEntity::doScriptEvent(OOJSID("playerBoughtNewShip"), { oo::EntityObjectNode(player), oo::PList::signedInteger(0) }); // qualified: the final overrider, so the binding test stands in for it
    }

    OOJS_RETURN_BOOL(success);

    OOJS_NATIVE_EXIT
}

// setEscapePodDestination(Entity | 'NEARBY_SYSTEM')
static JSValue PlayerSetEscapePodDestination(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    if (EXPECT_NOT(!OOIsPlayerStale())) {
        cxx_OOJSReportError(context, "Player.setEscapePodDestination() only works while the escape pod is in flight.");
        return OOJSNativeFailure(context);
    }

    bool OK = false;
    oo::PList destValue;
    PlayerEntity* player = OOPlayerForScripting();

    if (argc == 1) {
        destValue = cxx_OOJSPListFromJSValue(context, OOJS_ARGV[0]);
        Entity* destEntity = oo::EntityIn(destValue); // the entity node's

        if (destValue.isNull()) {
            if (player != nullptr)
                player->setDockTarget(NULL);
            OK = true;
        } else if ((oo::ToShip(destEntity) != nullptr) && destEntity->getIsStation()) // what -isStation forwarded to
        {
            if (player != nullptr)
                player->setDockTarget(oo::ToShip(destEntity));
            OK = true;
        } else if (const std::string* destString = destValue.getIf<std::string>()) {
            if (*destString == "NEARBY_SYSTEM") {
                // find the nearest system with a main station, or die in the attempt!
                if (player != nullptr)
                    player->setDockTarget(NULL);

                double rescueRange = MAX_JUMP_RANGE; // reach at least 1 other system!
                if ((UNIVERSE != nullptr ? UNIVERSE->inInterstellarSpace() : false)) {
                    // Set 3.5 ly as the limit, enough to reach at least 2 systems!
                    rescueRange = MAX_JUMP_RANGE / 2.0;
                }
                oo::PList destinations = (UNIVERSE != nullptr ? UNIVERSE->nearbyDestinationsWithinRange(rescueRange) : oo::PList());
                oo::PList::Array sDests;
                if (const oo::PList::Array* array = destinations.getIf<oo::PList::Array>())
                    sDests = *array;
                NSUInteger i = 0, nDests = sDests.size();

                if (nDests > 0)
                    for (i = --nDests; i > 0; i--) {
                        if (sDests[i].get<bool>("nova")) {
                            sDests.erase(sDests.begin() + i);
                        }
                    }

                // i is back to 0, nDests could have changed...
                nDests = sDests.size();
                if (nDests > 0) // we have a system with a main station!
                {
                    if (nDests > 1)
                        i = ranrot_rand() % nDests; // any nearby system will do.
                    const oo::PList& dest = sDests[i];

                    // add more time until rescue, with overheads for entering witchspace in case of overlapping systems.
                    double dist = dest.get<double>("distance");
                    if (player != nullptr)
                        player->addToAdjustTime((.2 + dist * dist) * 3600.0 + 5400.0 * (ranrot_rand() & 127));

                    // at the end of the docking sequence we'll check if the target system is the same as the system we're in...
                    if (player != nullptr)
                        player->PlayerEntity::setTargetSystemID(i); // qualified: the final overrider, so the binding test stands in for it
                }
                OK = true;
            }
        } else {
            int bValue = JS_ToBool(context, OOJS_ARGV[0]);
            if (bValue == 0) {
                if (player != nullptr)
                    player->setDockTarget(NULL);
                OK = true;
            }
        }
    }

    if (OK == false) {
        cxx_OOJSReportBadArguments(context, "Player", "setEscapePodDestination", argc, OOJS_ARGV, std::nullopt, "a valid station, null, or 'NEARBY_SYSTEM'");
        return OOJSNativeFailure(context);
    }
    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}

// setPlayerRole (role-key : String [, index : Number])
static JSValue PlayerSetPlayerRole(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    std::optional<std::string> role;
    PlayerEntity* player = OOPlayerForScripting();
    uint32_t index = 0;

    if (argc > 0)
        role = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
    if (!role.has_value()) {
        cxx_OOJSReportBadArguments(context, "Player", "setPlayerRole", MIN(argc, 1), OOJS_ARGV, std::nullopt, "string (role) [, number (index)]");
        return OOJSNativeFailure(context);
    }

    if (argc > 1) {
        if (JS_ToUint32(context, &index, OOJS_ARGV[1]) == 0) {
            if (player != nullptr)
                player->PlayerEntity::addRoleToPlayer(*role, index); // qualified: the final overrider, so the binding test stands in for it
            OOJS_RETURN_VOID;
        }
        // As before, fall back to the default slot if the index can't be converted.
        JS_FreeValue(context, JS_GetException(context));
    }
    if (player != nullptr)
        player->PlayerEntity::addRoleToPlayer(*role); // qualified: the final overrider, so the binding test stands in for it
    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}

static JSValue PlayerStopAudioMessage(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)
    if ((UNIVERSE != nullptr ? UNIVERSE->isSpeaking() : false)) {
        if (UNIVERSE != nullptr)
            UNIVERSE->stopSpeaking();
    }
    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}
