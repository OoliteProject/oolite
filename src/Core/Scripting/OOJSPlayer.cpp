/*

OOJSPlayer.h

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
#include "OOJSEntity.h"
#include "OOJSShip.h"
#include "OOJSVector.h"
#include "OOJavaScriptEngine.h"
#include "EntityOOJavaScriptExtensions.h"

#include "PlayerEntity.h"
#include "PlayerEntityContracts.h"
#include "PlayerEntityScriptMethods.h"
#include "PlayerEntityLegacyScriptEngine.h"

#include "OOConstToString.h"
#include "OOFunctionAttributes.h"
#include "OOStringParsing.h"

#include "ooscript/JSEngine.hpp"
#include <cstring>
#include "OOObjCPList.h"

/*
	Retargeted onto the ooscript façade (JSEngine.hpp) the way OOJSVector.mm does it (bead
	oo-sdz, the sweep exemplar): the class dispatch table becomes a static ooscript::ClassDef
	(the stub hooks are nullptr), InitClass becomes ooscript::initClass, native methods and
	class hooks take the façade's hook signature (Context/Object/PropertyId/Value pointer/
	CallArgs reference), and the directly spelled numeric-conversion calls (NewNumberValue,
	ValueToInt32, ValueToNumber, ValueToECMAUint32, ValueToBoolean) become their ooscript::
	façade equivalents. Natives take the
	façade signature directly (ooscript::Context and a CallArgs reference) and the OOJS_*
	argument-marshalling macros expand to the CallArgs accessors, so the rest of each function
	body is UNCHANGED. `this` is renamed to
	`thisObj` because it is a reserved word once this file compiles as Objective-C++
	(ADR-0001).

	JSPlayerClass() returns &sPlayerClass, the same ooscript::ClassDef that ooscript::getClass()
	reports for the player object.
*/
/*
	C++20 since bead oo-5rva, converted the way bead oo-ppc converted OOJSVector.mm (proposed
	ADR-0056 amendment oo-ppc). The JS class was already C++ on the ooscript façade;
	OOJS_NATIVE_ENTER/EXIT and OOJS_PROFILE_ENTER/EXIT are C++ try/catch and scope guards
	(OOJSEngineNativeWrappers.h); BOOL/YES/NO are bool/true/false. Nothing else in the file was
	Objective-C: the player (PlayerEntity), the universe and ShipEntity, which are not converted,
	are still messaged, which is why the file is still .mm until Phase 4.
*/

namespace ooscript { }
using ooscript::Context;
using ooscript::Object;
using ooscript::Value;
using ooscript::PropertyId;
using ooscript::CallArgs;
using ooscript::ClassDef;
using ooscript::ClassFlag;
using ooscript::PropertyFlag;
using ooscript::PropertySpec;
using ooscript::FunctionSpec;

// Byte-identical façade <-> jsapi views, local to this call site (see OOJSVector.mm).


namespace {
static ooscript::Object sPlayerPrototype;
} // namespace
namespace {
static ooscript::Object sPlayerObject;
} // namespace


namespace {
static bool PlayerGetProperty(Context cx, Object obj, PropertyId propID, Value *value);
} // namespace
namespace {
static bool PlayerSetProperty(Context cx, Object obj, PropertyId propID, bool strict, Value *value);
} // namespace

namespace {
static bool PlayerAddMessageToArrivalReport(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
static bool PlayerAudioMessage(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
static bool PlayerCommsMessage(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
static bool PlayerConsoleMessage(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
static bool PlayerEndScenario(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
static bool PlayerIncreaseContractReputation(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
static bool PlayerDecreaseContractReputation(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
static bool PlayerIncreasePassengerReputation(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
static bool PlayerDecreasePassengerReputation(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
static bool PlayerIncreaseParcelReputation(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
static bool PlayerDecreaseParcelReputation(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
static bool PlayerReplaceShip(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
static bool PlayerSetEscapePodDestination(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
static bool PlayerSetPlayerRole(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
static bool PlayerStopAudioMessage(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace


namespace {
static ClassDef sPlayerClass =
{
	"Player",
	ClassFlag::HasPrivate,

	nullptr,				// addProperty (engine default: PropertyStub)
	nullptr,				// delProperty (engine default: PropertyStub)
	PlayerGetProperty,		// getProperty
	PlayerSetProperty,		// setProperty
	nullptr,				// enumerate (engine default: EnumerateStub)
	nullptr,				// newEnumerate (ooscript::ClassFlag::NewEnumerate not used)
	nullptr,				// resolve (engine default: ResolveStub)
	nullptr,				// convert (engine default: ConvertStub)
	OOJSObjectWrapperFinalize,			// finalize
	nullptr,				// call
	nullptr,				// construct
	nullptr,				// backend: owned by the façade backend, must start null
};
} // namespace


enum : std::uint8_t
{
	// Property IDs
	kPlayer_alertAltitude,			// low altitude alert flag, boolean, read-only
	kPlayer_alertCondition,			// alert level, integer, read-only
	kPlayer_alertEnergy,			// low energy alert flag, boolean, read-only
	kPlayer_alertHostiles,			// hostiles present alert flag, boolean, read-only
	kPlayer_alertMassLocked,		// mass lock alert flag, boolean, read-only
	kPlayer_alertTemperature,		// cabin temperature alert flag, boolean, read-only
	kPlayer_bounty,					// bounty, unsigned int, read/write
	kPlayer_contractReputation,		// reputation for cargo contracts, integer, read only
	kPlayer_contractReputationPrecise,	// reputation for cargo contracts, float, read only
	kPlayer_credits,				// credit balance, float, read/write
	kPlayer_dockingClearanceStatus,	// docking clearance status, string, read only
	kPlayer_escapePodRescueTime,    // override for the amount of time an escape pod rescue takes, read/write
	kPlayer_legalStatus,			// legalStatus, string, read-only
	kPlayer_name,					// Player name, string, read/write
	kPlayer_parcelReputation,	// reputation for parcel contracts, integer, read-only
	kPlayer_parcelReputationPrecise,	// reputation for parcel contracts, float, read-only
	kPlayer_passengerReputation,	// reputation for passenger contracts, integer, read-only
	kPlayer_passengerReputationPrecise,	// reputation for passenger contracts, float, read-only
	kPlayer_rank,					// rank, string, read-only
	kPlayer_roleWeights,			// role weights, array, read-only
	kPlayer_score,					// kill count, integer, read/write
	kPlayer_trumbleCount,			// number of trumbles, integer, read-only
};


namespace {
static PropertySpec sPlayerProperties[] =
{
	// JS name					ID							flags
	{ "alertAltitude",			kPlayer_alertAltitude,		PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Shared, nullptr, nullptr },
	{ "alertCondition",			kPlayer_alertCondition,		PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Shared, nullptr, nullptr },
	{ "alertEnergy",			kPlayer_alertEnergy,		PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Shared, nullptr, nullptr },
	{ "alertHostiles",			kPlayer_alertHostiles,		PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Shared, nullptr, nullptr },
	{ "alertMassLocked",		kPlayer_alertMassLocked,	PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Shared, nullptr, nullptr },
	{ "alertTemperature",		kPlayer_alertTemperature,	PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Shared, nullptr, nullptr },
	{ "bounty",					kPlayer_bounty,				PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared, nullptr, nullptr },
	{ "contractReputation",		kPlayer_contractReputation,	PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Shared, nullptr, nullptr },
	{ "contractReputationPrecise",		kPlayer_contractReputationPrecise,	PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Shared, nullptr, nullptr },
	{ "credits",				kPlayer_credits,			PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared, nullptr, nullptr },
	{ "dockingClearanceStatus",	kPlayer_dockingClearanceStatus,	PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Shared, nullptr, nullptr },
	{ "escapePodRescueTime",    kPlayer_escapePodRescueTime, PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared, nullptr, nullptr },
	{ "legalStatus",			kPlayer_legalStatus,		PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Shared, nullptr, nullptr },
	{ "name",					kPlayer_name,				PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared, nullptr, nullptr },
	{ "parcelReputation",		kPlayer_parcelReputation,	PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Shared, nullptr, nullptr },
	{ "parcelReputationPrecise",	kPlayer_parcelReputationPrecise,	PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Shared, nullptr, nullptr },
	{ "passengerReputation",	kPlayer_passengerReputation,	PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Shared, nullptr, nullptr },
	{ "passengerReputationPrecise",	kPlayer_passengerReputationPrecise,	PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Shared, nullptr, nullptr },
	{ "rank",					kPlayer_rank,				PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Shared, nullptr, nullptr },
	{ "roleWeights",			kPlayer_roleWeights,		PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Shared, nullptr, nullptr },
	{ "score",					kPlayer_score,				PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared, nullptr, nullptr },
	{ "trumbleCount",			kPlayer_trumbleCount,		PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Shared, nullptr, nullptr },
	{ 0 }
};
} // namespace


// A raw jsapi mirror of sPlayerProperties, used only for the bad-property error reporters
// in OOJavaScriptEngine.m (OOJSReportBadPropertySelector/Value): those helpers are outside
// this bead's scope (they are shared across every binding file and are retargeted, if at
// all, by a later seam) and still take a ooscript::PropertySpec*, not ooscript::PropertySpec*
// (see OOJSVector.mm/OOJSStation.mm for the same pattern).
namespace {
static ooscript::PropertySpec sPlayerPropertiesRaw[] =
{
	// JS name					ID							flags
	{ "alertAltitude",			kPlayer_alertAltitude,		OOJS_PROP_READONLY_CB },
	{ "alertCondition",			kPlayer_alertCondition,		OOJS_PROP_READONLY_CB },
	{ "alertEnergy",			kPlayer_alertEnergy,		OOJS_PROP_READONLY_CB },
	{ "alertHostiles",			kPlayer_alertHostiles,		OOJS_PROP_READONLY_CB },
	{ "alertMassLocked",		kPlayer_alertMassLocked,	OOJS_PROP_READONLY_CB },
	{ "alertTemperature",		kPlayer_alertTemperature,	OOJS_PROP_READONLY_CB },
	{ "bounty",					kPlayer_bounty,				OOJS_PROP_READWRITE_CB },
	{ "contractReputation",		kPlayer_contractReputation,	OOJS_PROP_READONLY_CB },
	{ "contractReputationPrecise",		kPlayer_contractReputationPrecise,	OOJS_PROP_READONLY_CB },
	{ "credits",				kPlayer_credits,			OOJS_PROP_READWRITE_CB },
	{ "dockingClearanceStatus",	kPlayer_dockingClearanceStatus,	OOJS_PROP_READONLY_CB },
	{ "escapePodRescueTime",    kPlayer_escapePodRescueTime, OOJS_PROP_READWRITE_CB },
	{ "legalStatus",			kPlayer_legalStatus,		OOJS_PROP_READONLY_CB },
	{ "name",					kPlayer_name,				OOJS_PROP_READWRITE_CB },
	{ "parcelReputation",		kPlayer_parcelReputation,	OOJS_PROP_READONLY_CB },
	{ "parcelReputationPrecise",	kPlayer_parcelReputationPrecise,	OOJS_PROP_READONLY_CB },
	{ "passengerReputation",	kPlayer_passengerReputation,	OOJS_PROP_READONLY_CB },
	{ "passengerReputationPrecise",	kPlayer_passengerReputationPrecise,	OOJS_PROP_READONLY_CB },
	{ "rank",					kPlayer_rank,				OOJS_PROP_READONLY_CB },
	{ "roleWeights",			kPlayer_roleWeights,		OOJS_PROP_READONLY_CB },
	{ "score",					kPlayer_score,				OOJS_PROP_READWRITE_CB },
	{ "trumbleCount",			kPlayer_trumbleCount,		OOJS_PROP_READONLY_CB },
	{ 0 }
};
} // namespace


namespace {
static FunctionSpec sPlayerMethods[] =
{
	// JS name							Function							min args	flags
	{ "addMessageToArrivalReport",		PlayerAddMessageToArrivalReport,	1,			0 },
	{ "audioMessage",					PlayerAudioMessage,					1,			0 },
	{ "commsMessage",					PlayerCommsMessage,					1,			0 },
	{ "consoleMessage",					PlayerConsoleMessage,				1,			0 },
	{ "decreaseContractReputation",		PlayerDecreaseContractReputation,	0,			0 },
	{ "decreaseParcelReputation",	    PlayerDecreaseParcelReputation,		0,			0 },
	{ "decreasePassengerReputation",	PlayerDecreasePassengerReputation,	0,			0 },
	{ "endScenario",					PlayerEndScenario,					1,			0 },
	{ "increaseContractReputation",		PlayerIncreaseContractReputation,	0,			0 },
	{ "increaseParcelReputation",	    PlayerIncreaseParcelReputation,		0,			0 },
	{ "increasePassengerReputation",	PlayerIncreasePassengerReputation,	0,			0 },
	{ "replaceShip",					PlayerReplaceShip,					1,			0 },
	{ "setEscapePodDestination",		PlayerSetEscapePodDestination,		1,			0 },	// null destination must be set explicitly
	{ "setPlayerRole",					PlayerSetPlayerRole,				1,			0 },
	{ "stopAudioMessage",				PlayerStopAudioMessage,				0,			0 },
	{ 0 }
};
} // namespace


// *** Public ***

void InitOOJSPlayer(ooscript::Context context, ooscript::Object global)
{
	Object proto = ooscript::initClass((context), (global), nullptr, &sPlayerClass,
										OOJSUnconstructableConstruct, 0, sPlayerProperties, sPlayerMethods,
										nullptr, nullptr);
	sPlayerPrototype = (proto);
	OOJSRegisterObjectConverter(&sPlayerClass, OOJSBasicPrivateObjectConverter);

	// Create player object as a property of the global object.
	Object playerObj = ooscript::defineObject((context), (global), "player", &sPlayerClass, proto, OOJS_PROP_READONLY);
	sPlayerObject = (playerObj);
}


ooscript::ClassDef *JSPlayerClass(void)
{
	return &sPlayerClass;
}


ooscript::Object JSPlayerPrototype(void)
{
	return sPlayerPrototype;
}


ooscript::Object JSPlayerObject(void)
{
	return sPlayerObject;
}


PlayerEntity *OOPlayerForScripting(void)
{
	PlayerEntity *player = PLAYER;
	if (player != nullptr)  player->setScriptTargetToSelf();
	
	return player;
}


namespace {
static bool PlayerGetProperty(Context cx, Object obj, PropertyId propID, Value *value)
{
	if (!ooscript::isInt32Id(propID))  return true;
	
	ooscript::Context context = (cx);
	
	OOJS_NATIVE_ENTER(context)
	
	oo::PList					result;	// null maps to null
	PlayerEntity				*player = OOPlayerForScripting();
	
	switch (ooscript::idToInt32(propID))
	{
		case kPlayer_name:
			if (const std::optional<std::string> name = (player != nullptr ? player->commanderName() : std::optional<std::string>()))  result = oo::PList(*name);
			break;
			
		case kPlayer_score:
			*(value) = ooscript::int32Value((player != nullptr ? player->PlayerEntity::score() : unsigned{}));	// qualified: the final overrider (bead oo-9ht.177), so the binding test stands in for it
			return true;
			
		case kPlayer_credits:
			return ooscript::newNumberValue(cx, (player != nullptr ? player->creditBalance() : 0.0), value);
			
		case kPlayer_rank:
			{
				const std::optional<std::string> text = cxx_OODisplayRatingStringFromKillCount((player != nullptr ? player->PlayerEntity::score() : unsigned{}));	// qualified: the final overrider (bead oo-9ht.177), so the binding test stands in for it
				*(value) = OOJSValueFromPList(context, text.has_value() ? oo::PList(*text) : oo::PList());
			}
			return true;
			
		case kPlayer_legalStatus:
			{
				const std::optional<std::string> text = cxx_OODisplayStringFromLegalStatus((player != nullptr ? player->getLegalStatus() : int{}));
				*(value) = OOJSValueFromPList(context, text.has_value() ? oo::PList(*text) : oo::PList());
			}
			return true;
			
		case kPlayer_alertCondition:
			*(value) = ooscript::int32Value((player != nullptr ? player->PlayerEntity::getAlertCondition() : OOAlertCondition{}));	// qualified: the final overrider (bead oo-9ht.177), so the binding test stands in for it
			return true;
			
		case kPlayer_alertTemperature:
			*(value) = OOJSValueFromBOOL((player != nullptr ? player->getAlertFlags() : int{}) & ALERT_FLAG_TEMP);
			return true;
			
		case kPlayer_alertMassLocked:
			*(value) = OOJSValueFromBOOL((player != nullptr ? player->getAlertFlags() : int{}) & ALERT_FLAG_MASS_LOCK);
			return true;
			
		case kPlayer_alertAltitude:
			*(value) = OOJSValueFromBOOL((player != nullptr ? player->getAlertFlags() : int{}) & ALERT_FLAG_ALT);
			return true;
			
		case kPlayer_alertEnergy:
			*(value) = OOJSValueFromBOOL((player != nullptr ? player->getAlertFlags() : int{}) & ALERT_FLAG_ENERGY);
			return true;
			
		case kPlayer_alertHostiles:
			*(value) = OOJSValueFromBOOL((player != nullptr ? player->getAlertFlags() : int{}) & ALERT_FLAG_HOSTILES);
			return true;
			
		case kPlayer_escapePodRescueTime:
			return ooscript::newNumberValue(cx, (player != nullptr ? player->escapePodRescueTime() : 0.0), value);
			
		case kPlayer_trumbleCount:
			return ooscript::newNumberValue(cx, (player != nullptr ? player->PlayerEntity::getTrumbleCount() : 0), value);	// qualified: the final overrider (bead oo-9ht.177), so the binding test stands in for it
			
			/* For compatibility with previous versions, these are still on
			 * a -7 to +7 scale */
		case kPlayer_contractReputation:
			return ooscript::newNumberValue(cx, (int)(((float)(player != nullptr ? player->contractReputation() : int{}))/10.0), value);
			
		case kPlayer_passengerReputation:
			return ooscript::newNumberValue(cx, (int)(((float)(player != nullptr ? player->passengerReputation() : int{}))/10.0), value);

		case kPlayer_parcelReputation:
			return ooscript::newNumberValue(cx, (int)(((float)(player != nullptr ? player->parcelReputation() : int{}))/10.0), value);

			/* Full-precision reputations */
		case kPlayer_contractReputationPrecise:
			return ooscript::newNumberValue(cx, ((float)(player != nullptr ? player->contractReputation() : int{}))/10.0, value);
			
		case kPlayer_passengerReputationPrecise:
			return ooscript::newNumberValue(cx, ((float)(player != nullptr ? player->passengerReputation() : int{}))/10.0, value);

		case kPlayer_parcelReputationPrecise:
			return ooscript::newNumberValue(cx, ((float)(player != nullptr ? player->parcelReputation() : int{}))/10.0, value);
			
		case kPlayer_dockingClearanceStatus:
			// EMMSTRAN: OOConstToJSString-ify this.
			*(value) = OOJSValueFromPList(context, oo::PList(cxx_DockingClearanceStatusToString((player != nullptr ? player->getDockingClearanceStatus() : OODockingClearanceStatus{}))));
			return true;
			
		case kPlayer_bounty:
			*(value) = ooscript::int32Value((player != nullptr ? player->getLegalStatus() : int{}));
			return true;

		case kPlayer_roleWeights:
			{
				const std::vector<std::string> roleWeights = (player != nullptr ? player->getRoleWeights() : std::vector<std::string>());
				result = oo::PList(oo::PList::Array(roleWeights.begin(), roleWeights.end()));
			}
			break;
		
		default:
			OOJSReportBadPropertySelector(context, (obj), (propID), sPlayerPropertiesRaw);
			return false;
	}
	
	*(value) = OOJSValueFromPList(context, result);
	return true;
	
	OOJS_NATIVE_EXIT
}
} // namespace


namespace {
static bool PlayerSetProperty(Context cx, Object obj, PropertyId propID, bool /*strict*/, Value *value)
{
	if (!ooscript::isInt32Id(propID))  return true;
	
	ooscript::Context context = (cx);
	
	OOJS_NATIVE_ENTER(context)
	
	PlayerEntity				*player = OOPlayerForScripting();
	double					fValue;
	int32_t						iValue;
	std::optional<std::string>					sValue;
	
	switch (ooscript::idToInt32(propID))
	{
		case kPlayer_name:
			sValue = cxx_OOStringFromJSValue(context, *(value));
			if (sValue.has_value())
			{
				if (player != nullptr)  player->setCommanderName(sValue);
				return true;
			}
			break;

		case kPlayer_score:
		{
			std::int32_t iValue32 = 0;
			if (ooscript::valueToInt32(cx, *value, &iValue32))
			{
				iValue = (int32_t)iValue32;
				iValue = MAX(iValue, 0);
				if (player != nullptr)  player->setScore(iValue);
				return true;
			}
			break;
		}
			
		case kPlayer_credits:
			if (ooscript::valueToNumber(cx, *value, &fValue))
			{
				if (player != nullptr)  player->setCreditBalance(fValue);
				return true;
			}
			break;
			
		case kPlayer_bounty:
		{
			std::int32_t iValue32 = 0;
			if (ooscript::valueToInt32(cx, *value, &iValue32))
			{
				iValue = (int32_t)iValue32;
				if (iValue < 0)  iValue = 0;
				if (player != nullptr)  player->PlayerEntity::setBounty(iValue, kOOLegalStatusReasonByScript);	// qualified: the final overrider (bead oo-9ht.177), so the binding test stands in for it
				return true;
			}
			break;
		}

		case kPlayer_escapePodRescueTime:
			if (ooscript::valueToNumber(cx, *value, &fValue))
			{
				if (player != nullptr)  player->setEscapePodRescueTime(fValue);
				return true;
			}
			break;

		default:
			OOJSReportBadPropertySelector(context, (obj), (propID), sPlayerPropertiesRaw);
			return false;
	}
	
	OOJSReportBadPropertyValue(context, (obj), (propID), sPlayerPropertiesRaw, *(value));
	return false;
	
	OOJS_NATIVE_EXIT
}
} // namespace


// *** Methods ***

// commsMessage(message : String [, duration : Number])
namespace {
static bool PlayerCommsMessage(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_NATIVE_ENTER(context)
	
	std::optional<std::string>				message;
	double					time = 4.5;
	bool					gotTime = true;
	
	if (oojsArgs.count() > 0)  message = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (oojsArgs.count() > 1)  gotTime = ooscript::valueToNumber((context), (OOJS_ARGV[1]), &time) ? true : false;
	if (!message.has_value() || !gotTime)
	{
		cxx_OOJSReportBadArguments(context, "Player", "commsMessage", oojsArgs.count(), OOJS_ARGV, std::nullopt, "message and optional duration");
		return false;
	}
	
	if (UNIVERSE != nullptr)  UNIVERSE->addCommsMessage(message, time);
	if (PLAYER != nullptr)  PLAYER->ShipEntity::doScriptEvent(OOJSID("commsMessageReceived"), { oo::PList(*message), oo::PList() });	// qualified: the final overrider (bead oo-9ht.177), so the binding test stands in for it
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}
} // namespace


// consoleMessage(message : String [, duration : Number])
namespace {
static bool PlayerConsoleMessage(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_NATIVE_ENTER(context)
	
	std::optional<std::string>				message;
	double					time = 3.0;
	bool					gotTime = true;
	
	if (oojsArgs.count() > 0)  message = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (oojsArgs.count() > 1)  gotTime = ooscript::valueToNumber((context), (OOJS_ARGV[1]), &time) ? true : false;
	if (!message.has_value() || !gotTime)
	{
		cxx_OOJSReportBadArguments(context, "Player", "consoleMessage", oojsArgs.count(), OOJS_ARGV, std::nullopt, "message and optional duration");
		return false;
	}
	
	if (UNIVERSE != nullptr)  UNIVERSE->addMessage(message, time);
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}
} // namespace


// endScenario(scenario : String)
namespace {
static bool PlayerEndScenario(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_NATIVE_ENTER(context)
	
	std::optional<std::string>				scenario;
	
	if (oojsArgs.count() > 0)  scenario = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (!scenario.has_value())
	{
		cxx_OOJSReportBadArguments(context, "Player", "endScenario", oojsArgs.count(), OOJS_ARGV, std::nullopt, "scenario key");
		return false;
	}
	
	OOJS_RETURN_BOOL((PLAYER != nullptr ? PLAYER->endScenario(*scenario) : false));
	
	OOJS_NATIVE_EXIT
}
} // namespace


// increaseContractReputation()
namespace {
static bool PlayerIncreaseContractReputation(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_NATIVE_ENTER(context)
	
	if (PlayerEntity *player = OOPlayerForScripting())  player->increaseContractReputation(1);
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}
} // namespace


// decreaseContractReputation()
namespace {
static bool PlayerDecreaseContractReputation(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_NATIVE_ENTER(context)
	
	if (PlayerEntity *player = OOPlayerForScripting())  player->decreaseContractReputation(1);
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}
} // namespace


// increaseParcelReputation()
namespace {
static bool PlayerIncreaseParcelReputation(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_NATIVE_ENTER(context)
	
	if (PlayerEntity *player = OOPlayerForScripting())  player->increaseParcelReputation(1);
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}
} // namespace


// decreaseParcelReputation()
namespace {
static bool PlayerDecreaseParcelReputation(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_NATIVE_ENTER(context)
	
	if (PlayerEntity *player = OOPlayerForScripting())  player->decreaseParcelReputation(1);
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}
} // namespace


// increasePassengerReputation()
namespace {
static bool PlayerIncreasePassengerReputation(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_NATIVE_ENTER(context)
	
	if (PlayerEntity *player = OOPlayerForScripting())  player->increasePassengerReputation(1);
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}
} // namespace


// decreasePassengerReputation()
namespace {
static bool PlayerDecreasePassengerReputation(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_NATIVE_ENTER(context)
	
	if (PlayerEntity *player = OOPlayerForScripting())  player->decreasePassengerReputation(1);
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}
} // namespace

// addMessageToArrivalReport(message : String)
namespace {
static bool PlayerAddMessageToArrivalReport(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_NATIVE_ENTER(context)
	
	std::optional<std::string>				report;
	PlayerEntity			*player = OOPlayerForScripting();
	
	if (oojsArgs.count() > 0)  report = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (!report.has_value())
	{
		cxx_OOJSReportBadArguments(context, "Player", "addMessageToArrivalReport", MIN(oojsArgs.count(), 1U), OOJS_ARGV, std::nullopt, "string (arrival message)");
		return false;
	}
	
	if (player != nullptr)  player->addMessageToReport(*report);
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}
} // namespace


namespace {
static bool PlayerAudioMessage(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_NATIVE_ENTER(context)
	
	std::optional<std::string>				audioMessage;
	PlayerEntity			*player = OOPlayerForScripting();
	
	if (oojsArgs.count() > 0)  audioMessage = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (!audioMessage.has_value())
	{
		cxx_OOJSReportBadArguments(context, "Player", "audioMessage", oojsArgs.count(), OOJS_ARGV, std::nullopt, "audiomessage (string)");
		return false;
	}
	
	if ((player != nullptr ? player->getIsSpeechOn() : OOSpeechSettings{}) >= OOSPEECHSETTINGS_COMMS)  { if (UNIVERSE != nullptr)  UNIVERSE->startSpeakingString(*audioMessage); }
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}
} // namespace


// replaceShip (shipyard-key : String)
namespace {
static bool PlayerReplaceShip(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_NATIVE_ENTER(context)
	
	std::optional<std::string>				shipKey;
	PlayerEntity			*player = OOPlayerForScripting();
	bool success = false;
	int personality = 0;

	if (oojsArgs.count() > 0)  shipKey = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (!shipKey.has_value())
	{
		cxx_OOJSReportBadArguments(context, "Player", "replaceShip", MIN(oojsArgs.count(), 1U), OOJS_ARGV, std::nullopt, "string (shipyard key)");
		return false;
	}

	if (EXPECT_NOT(!((player != nullptr ? player->status() : OOEntityStatus{}) == STATUS_DOCKED)))
	{
		cxx_OOJSReportError(context, "Player.replaceShip() only works while the player is docked.");
		return false;
	}
	
	success = (player != nullptr ? player->replaceShipWithNamedShip(*shipKey) : false);
	if (oojsArgs.count() > 1)
	{
		std::int32_t personality32 = 0;
		ooscript::valueToInt32((context), (OOJS_ARGV[1]), &personality32);
		personality = personality32;
		if (personality >= 0 && (uint16_t)personality < ENTITY_PERSONALITY_MAX)
		{
			if (player != nullptr)  player->setEntityPersonalityInt((uint16_t)personality);
		}
	}

	if (success) 
	{ 
		// The player's entity node (bead oo-9ht.39.8.8), as the next event's: its JS value is the C++ player's, which its
		// object's -oo_jsValueInContext: answered; qualified: the final overrider, so the binding test stands in for it.
		if (player != nullptr)  player->ShipEntity::doScriptEvent(OOJSID("playerReplacedShip"), { oo::EntityObjectNode(player) });
		// slightly misnamed world event now - to be deprecated
		if (player != nullptr)  player->ShipEntity::doScriptEvent(OOJSID("playerBoughtNewShip"), { oo::EntityObjectNode(player), oo::PList::signedInteger(0) });	// qualified: the final overrider (bead oo-9ht.177), so the binding test stands in for it
	}

	OOJS_RETURN_BOOL(success);
	
	OOJS_NATIVE_EXIT
}
} // namespace


// setEscapePodDestination(Entity | 'NEARBY_SYSTEM')
namespace {
static bool PlayerSetEscapePodDestination(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_NATIVE_ENTER(context)
	
	if (EXPECT_NOT(!OOIsPlayerStale()))
	{
		cxx_OOJSReportError(context, "Player.setEscapePodDestination() only works while the escape pod is in flight.");
		return false;
	}
	
	bool			OK = false;
	oo::PList		destValue;
	PlayerEntity	*player = OOPlayerForScripting();
	
	if (oojsArgs.count() == 1)
	{
		destValue = cxx_OOJSPListFromJSValue(context, OOJS_ARGV[0]);
		Entity *destEntity = oo::EntityIn(destValue);	// the entity node's (its object until bead oo-dpyk8)
		
		if (destValue.isNull())
		{
			if (player != nullptr)  player->setDockTarget(NULL);
			OK = true;
		}
		else if ((oo::ToShip(destEntity) != nullptr) && destEntity->getIsStation())	// what -isStation forwarded to
		{
			if (player != nullptr)  player->setDockTarget(oo::ToShip(destEntity));
			OK = true;
		}
		else if (const std::string *destString = destValue.getIf<std::string>())
		{
			if (*destString == "NEARBY_SYSTEM")
			{
				// find the nearest system with a main station, or die in the attempt!
				if (player != nullptr)  player->setDockTarget(NULL);
				
				double rescueRange = MAX_JUMP_RANGE;	// reach at least 1 other system!
				if ((UNIVERSE != nullptr ? UNIVERSE->inInterstellarSpace() : false))
				{
					// Set 3.5 ly as the limit, enough to reach at least 2 systems!
					rescueRange = MAX_JUMP_RANGE / 2.0;
				}
				oo::PList		destinations = (UNIVERSE != nullptr ? UNIVERSE->nearbyDestinationsWithinRange(rescueRange) : oo::PList());
				oo::PList::Array	sDests;
				if (const oo::PList::Array *array = destinations.getIf<oo::PList::Array>())  sDests = *array;
				NSUInteger		i = 0, nDests = sDests.size();
				
				if (nDests > 0)	for (i = --nDests; i > 0; i--)
				{
					if (sDests[i].get<bool>("nova"))
					{
						sDests.erase(sDests.begin() + i);
					}
				}
				
				// i is back to 0, nDests could have changed...
				nDests = sDests.size();
				if (nDests > 0)	// we have a system with a main station!
				{
					if (nDests > 1)  i = ranrot_rand() % nDests;	// any nearby system will do.
					const oo::PList &dest = sDests[i];
					
					// add more time until rescue, with overheads for entering witchspace in case of overlapping systems.
					double dist = dest.get<double>("distance");
					if (player != nullptr)  player->addToAdjustTime((.2 + dist * dist) * 3600.0 + 5400.0 * (ranrot_rand() & 127));
					
					// at the end of the docking sequence we'll check if the target system is the same as the system we're in...
					if (player != nullptr)  player->PlayerEntity::setTargetSystemID(i);	// qualified: the final overrider (bead oo-9ht.177), so the binding test stands in for it
				}
				OK = true;
			}
		}
		else
		{
			bool bValue;
			if (ooscript::valueToBoolean((context), (OOJS_ARGV[0]), &bValue) && bValue == false)
			{
				if (player != nullptr)  player->setDockTarget(NULL);
				OK = true;
			}
		}
	}
	
	if (OK == false)
	{
		cxx_OOJSReportBadArguments(context, "Player", "setEscapePodDestination", oojsArgs.count(), OOJS_ARGV, std::nullopt, "a valid station, null, or 'NEARBY_SYSTEM'");
	}
	return OK;
	
	OOJS_NATIVE_EXIT
}
} // namespace


// setPlayerRole (role-key : String [, index : Number])
namespace {
static bool PlayerSetPlayerRole(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_NATIVE_ENTER(context)
	
	std::optional<std::string>				role;
	PlayerEntity			*player = OOPlayerForScripting();
	uint32_t index = 0;

	if (oojsArgs.count() > 0)  role = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (!role.has_value())
	{
		cxx_OOJSReportBadArguments(context, "Player", "setPlayerRole", MIN(oojsArgs.count(), 1U), OOJS_ARGV, std::nullopt, "string (role) [, number (index)]");
		return false;
	}

	if (oojsArgs.count() > 1)
	{
		std::uint32_t index32 = 0;
		if (ooscript::valueToECMAUint32((context), (OOJS_ARGV[1]), &index32))
		{
			index = index32;
			if (player != nullptr)  player->PlayerEntity::addRoleToPlayer(*role, index);	// qualified: the final overrider (bead oo-9ht.177), so the binding test stands in for it
			return true;
		}
	}
	if (player != nullptr)  player->PlayerEntity::addRoleToPlayer(*role);	// qualified: the final overrider (bead oo-9ht.177), so the binding test stands in for it
	return true;

	OOJS_NATIVE_EXIT
}
} // namespace


namespace {
static bool PlayerStopAudioMessage(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_NATIVE_ENTER(context)
	if ((UNIVERSE != nullptr ? UNIVERSE->isSpeaking() : false))  { if (UNIVERSE != nullptr)  UNIVERSE->stopSpeaking(); }
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}
} // namespace
