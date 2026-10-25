/*

OOJSMission.mm


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

#include "OOJSMission.h"
#include "OOJavaScriptEngine.h"
#include "OOJSScript.h"
#include "OOConstToJSString.h"
#include "OOJSVector.h"

#include "OOJSPlayer.h"
#include "PlayerEntityScriptMethods.h"
#include "OOStringExpander.h"
#include "OOMusicController.h"
#include "GuiDisplayGen.h"
#include "OODebugStandards.h"
#include "oofnd/objc/OOException.h"

#include "ooscript/JSEngine.hpp"
#include <cstring>

/*
	Retargeted onto the ooscript façade (JSEngine.hpp) the way OOJSVector.mm does it (bead
	oo-sdz, the sweep exemplar): the class dispatch table becomes a static ooscript::ClassDef
	(the stub hooks are nullptr), the class-creation calls become ooscript::initClass and
	ooscript::defineObject, and the directly spelled numeric/object/property calls become their
	ooscript:: equivalents (valueToObject, newNumberValue, getProperty, setProperty,
	deleteProperty, valueToNumber, valueToBoolean, valueToInt32). `this` is renamed to `thisObj`
	because it is a reserved word once this file compiles as Objective-C++ (ADR-0001). The class
	hooks (getProperty, setProperty) and every ooscript::FunctionSpec entry take the façade's
	Context/Object/PropertyId/Value/CallArgs signature directly.
*/
/*
	C++20 since bead oo-nge8, converted the way bead oo-ppc converted OOJSVector.mm (proposed
	ADR-0056 amendment oo-ppc). The JS class was already C++ on the ooscript façade;
	OOJS_NATIVE_ENTER/EXIT and OOJS_PROFILE_ENTER/EXIT are C++ try/catch and scope guards
	(OOJSEngineNativeWrappers.h); BOOL/YES/NO are bool/true/false. OOMusicController, which is C++
	since bead oo-lfkq, is reached as OOMusicController (amendment oo-ppc, item 4).
	MissionRunCallback()'s @try/@catch (OOException *) around the callback stayed verbatim (amendment
	oo-puw9 item 4) until bead oo-rskgl made it a C++ try/catch with the other exception sites.
	mission.markedSystems kept the destinations it reads in a local: it read them through a pointer
	into a temporary that had died (bead oo-nge8; the same defect in OOJSSystemInfo.mm is bead
	oo-f4241). Messages to classes that are still Objective-C (PlayerEntity, Universe,
	GuiDisplayGen, OOJSScript, OOJavaScriptEngine) stay as they are, which is why the file is still
	.mm until Phase 4.
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


namespace {
static bool MissionGetProperty(Context cx, Object thisObj, PropertyId propID, Value *value);
} // namespace
namespace {
static bool MissionSetProperty(Context cx, Object thisObj, PropertyId propID, bool strict, Value *value);
} // namespace

namespace {
static bool MissionMarkSystem(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace
namespace {
static bool MissionUnmarkSystem(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace
namespace {
static bool MissionAddMessageText(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace
namespace {
static bool MissionSetInstructions(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace
namespace {
static bool MissionSetInstructionsKey(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace
namespace {
static bool MissionRunScreen(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace
namespace {
static bool MissionRunShipLibrary(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace

namespace {
static bool MissionSetInstructionsInternal(ooscript::Context context, ooscript::CallArgs &oojsArgs, bool isKey);
} // namespace

namespace {
constexpr PropertyFlag kMissionObjectFlags = PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly;
} // namespace

//  Mission screen  callback varibables
namespace {
ooscript::Value			sCallbackFunction;
} // namespace
namespace {
ooscript::Value			sCallbackThis;
} // namespace
namespace {
OOJSScript		*sCallbackScript = nullptr;	// retained (was the script's Objective-C object)
} // namespace

namespace {
ooscript::Object sMissionObject;
} // namespace

namespace {
static ClassDef sMissionClass =
{
	"Mission",
	ClassFlag::None,

	nullptr,			// addProperty (engine default: PropertyStub)
	nullptr,			// delProperty (engine default: PropertyStub)
	MissionGetProperty,	// getProperty
	MissionSetProperty,	// setProperty
	nullptr,			// enumerate (engine default: EnumerateStub)
	nullptr,			// newEnumerate (ooscript::ClassFlag::NewEnumerate not used)
	nullptr,			// resolve (engine default: ResolveStub)
	nullptr,			// convert (engine default: ConvertStub)
	nullptr,			// finalize (engine default: FinalizeStub)
	nullptr,			// call
	nullptr,			// construct
	nullptr,			// backend: owned by the façade backend, must start null
};
} // namespace


namespace {
enum : std::uint8_t
{
	kMission_markedSystems,
	kMission_screenID,
	kMission_exitScreen
};
} // namespace


namespace {
static PropertySpec sMissionProperties[] = 
{
	// JS name					ID								flags
	{ "markedSystems", kMission_markedSystems, PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Shared, nullptr, nullptr },
	{ "screenID", kMission_screenID, PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Shared, nullptr, nullptr },
	{ "exitScreen", kMission_exitScreen, PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared, nullptr, nullptr },
	{ 0 }
};
} // namespace


namespace {
static FunctionSpec sMissionMethods[] =
{
	// JS name					Function					min args	flags
	{ "addMessageText",			MissionAddMessageText,		1,			0 },
	{ "markSystem",				MissionMarkSystem,			1,			0 },
	{ "runScreen",				MissionRunScreen,			1,			0 }, // the callback function is optional!
	{ "setInstructions",		MissionSetInstructions,	1,			0 },
	{ "setInstructionsKey",		MissionSetInstructionsKey,	1,			0 },
	{ "unmarkSystem",			MissionUnmarkSystem,		1,			0 },
	{ "runShipLibrary",			MissionRunShipLibrary,		0,			0 },
	{ 0 }
};
} // namespace


void InitOOJSMission(ooscript::Context context, ooscript::Object global)
{
	sCallbackFunction = ooscript::nullValue();
	sCallbackThis = ooscript::nullValue();
	
	Object missionPrototype = ooscript::initClass((context), (global), nullptr, &sMissionClass, OOJSUnconstructableConstruct, 0, sMissionProperties, sMissionMethods, nullptr, nullptr);
	sMissionObject = (ooscript::defineObject((context), (global), "mission", &sMissionClass, missionPrototype, kMissionObjectFlags));
	
	// Ensure JS objects are rooted.
	OOJSAddGCValueRoot(context, &sCallbackFunction, "Pending mission callback function");
	OOJSAddGCValueRoot(context, &sCallbackThis, "Pending mission callback this");
}


void MissionRunCallback()
{
	// don't do anything if we don't have a function.
	if (ooscript::isNull(sCallbackFunction) || ooscript::isUndefined(sCallbackFunction))  return;
	
	ooscript::Value				argval = ooscript::undefinedValue();
	ooscript::Value				argval2 = ooscript::undefinedValue();
	ooscript::Value				rval = ooscript::undefinedValue();
	PlayerEntity		*player = OOPlayerForScripting();
	OOJavaScriptEngine	*engine  = OOJavaScriptEngine::sharedEngine();
	ooscript::Context context = OOJSAcquireContext();
	
	/*	Create temporarily-rooted local copies of sCallbackFunction and
		sCallbackThis, then clear the statics. This must be done in advance
		since the callback might call runScreen() and clobber the statics.
	*/
	ooscript::Value				cbFunction = ooscript::undefinedValue();
	ooscript::Object cbThis = NULL;
	OOJSScript			*cbScript = nullptr;
	
	OOJSAddGCValueRoot(context, &cbFunction, "Mission callback function");
	OOJSAddGCObjectRoot(context, &cbThis, "Mission callback this");
	cbFunction = sCallbackFunction;
	cbScript = sCallbackScript;
	ooscript::valueToObject((context), (sCallbackThis), &cbThis);
	
	sCallbackScript = nullptr;
	sCallbackFunction = ooscript::nullValue();
	sCallbackThis = ooscript::nullValue();
	
	ooscript::Value args[2];
	argval = OOJSValueFromPList(context, (player != nullptr ? player->missionChoice_string() : oo::PList()));
	argval2 = OOJSValueFromPList(context, (player != nullptr ? player->missionKeyPress_string() : oo::PList()));
	args[0] = argval;
	args[1] = argval2;

	// now reset the mission choice silently, before calling the callback script.
	if (player != nullptr)  player->setMissionChoice(std::nullopt, "", false);
	
	// Call the callback.
	try
	{
		OOJSScript::pushScript(cbScript);
		engine->callJSFunction(cbFunction, cbThis, 2, args, &rval);
	}
	catch (...)
	{
		const auto exception = oo::CurrentOOException();
		if (!exception)  throw;	// not an OOException: it goes on up, as before
		// Squash any exception, allow cleanup to happen and so forth.
		OO_LOG(cxx_kOOLogException, "Ignoring exception {}:{} during handling of mission screen completion callback.", exception->name(), exception->reason());
	}
	OOJSScript::popScript(cbScript);
	
	// Manage that memory.
	if (cbScript != nullptr)  cbScript->release();
	ooscript::removeValueRoot((context), (&cbFunction));
	ooscript::removeObjectRoot((context), &cbThis);
	
	OOJSRelinquishContext(context);
}


namespace {
static bool MissionGetProperty(Context cx, Object thisObj, PropertyId propID, Value *value)
{
	if (!ooscript::isInt32Id(propID))  return true;
	
	ooscript::Context context = (cx);
	
	OOJS_NATIVE_ENTER(context)

	oo::PList result;	// null maps to null
	PlayerEntity		*player = OOPlayerForScripting();

	switch (ooscript::idToInt32(propID))
	{
		case kMission_markedSystems:
			{
				// The destinations' values, in key order (-allValues gave hash order).
				oo::PList::Array values;
				// Kept in a local: getIf() points into it, and the temporary the message answered died
				// at the end of the if's initialiser (a dangling pointer until bead oo-nge8).
				const oo::PList missionDestinations = (player != nullptr ? player->getMissionDestinations() : oo::PList());
				if (const oo::PList::Dict *destinations = missionDestinations.getIf<oo::PList::Dict>())
				{
					for (const auto &entry : *destinations)
					{
						if (!entry.second.isNull())  values.push_back(entry.second);
					}
				}
				result = oo::PList(std::move(values));
			}
			break;

		case kMission_screenID:
			if (const std::optional<std::string> screenID = (player != nullptr ? player->missionScreenID() : std::optional<std::string>()))  result = oo::PList(*screenID);
			break;

		case kMission_exitScreen:
			*value = OOJSValueFromGUIScreenID(context, (player != nullptr ? player->missionExitScreen() : OOGUIScreenID{}));
			return true;

		default:
			OOJSReportBadPropertySelector(context, thisObj, propID, sMissionProperties);
			return false;
	}

	*value = OOJSValueFromPList(context, result);
	return true;
	
	OOJS_NATIVE_EXIT
}
} // namespace


namespace {
static bool MissionSetProperty(Context cx, Object thisObj, PropertyId propID, bool /*strict*/, Value *value)
{
	if (!ooscript::isInt32Id(propID))  return true;
	
	ooscript::Context context = (cx);
	
	OOJS_NATIVE_ENTER(context)
	
	OOGUIScreenID exitScreen;
	PlayerEntity		*player = OOPlayerForScripting();

	switch (ooscript::idToInt32(propID))
	{
		case kMission_exitScreen:
			exitScreen = OOGUIScreenIDFromJSValue(context, *value);
			if (player != nullptr)  player->setMissionExitScreen(exitScreen);
			return true;
	
		default:
			OOJSReportBadPropertySelector(context, thisObj, propID, sMissionProperties);
	}
	
	OOJSReportBadPropertyValue(context, thisObj, propID, sMissionProperties, *value);
	return false;
	
	OOJS_NATIVE_EXIT
}
} // namespace



// *** Methods ***

// markSystem(integer+)
namespace {
static bool MissionMarkSystem(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_NATIVE_ENTER(context)
	
	PlayerEntity		*player = OOPlayerForScripting();
	unsigned i;
	int dest;

	// two pass. Once to validate, once to apply if they validate
	for (i=0;i<oojsArgs.count();i++)
	{
		if (!ooscript::valueToInt32(context, (OOJS_ARGV[i]), &dest)) 
		{
			ooscript::clearPendingException(context); // or valueToInt32 exception crashes JS engine
			if (!ooscript::isObjectOrNull(OOJS_ARGV[i]))
			{
				cxx_OOJSReportBadArguments(context, "Mission", "markSystem", MIN(oojsArgs.count(), 1U), OOJS_ARGV, std::nullopt, "numbers or objects");
				return false;
			}
		}
	}

	for (i=0;i<oojsArgs.count();i++)
	{
		if (ooscript::valueToInt32(context, (OOJS_ARGV[i]), &dest)) 
		{
			cxx_OOStandardsDeprecated("Use of numbers for mission.markSystem is deprecated");
			if (!OOEnforceStandards())
			{
				if (player != nullptr)  player->addMissionDestinationMarker((player != nullptr ? player->defaultMarker(dest) : oo::PList()));
			}
		}
		else // must be object, from above
		{
			ooscript::clearPendingException(context); // or valueToInt32 exception crashes JS engine
			oo::PList marker = cxx_OOJSPListFromJSObject(context, ooscript::toObject(OOJS_ARGV[i]));
			OOSystemID system = marker.get<int>("system", -1);
			if (system >= 0)
			{
				if (player != nullptr)  player->addMissionDestinationMarker(marker);
			}
		}
	}
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}
} // namespace


// unmarkSystem(integer+)
namespace {
static bool MissionUnmarkSystem(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_NATIVE_ENTER(context)
	
	PlayerEntity		*player = OOPlayerForScripting();
	unsigned i;
	int dest;

	// two pass. Once to validate, once to apply if they validate
	for (i=0;i<oojsArgs.count();i++)
	{
		if (!ooscript::valueToInt32(context, (OOJS_ARGV[i]), &dest)) 
		{
			ooscript::clearPendingException(context); // or valueToInt32 exception crashes JS engine
			if (!ooscript::isObjectOrNull(OOJS_ARGV[i]))
			{
				cxx_OOJSReportBadArguments(context, "Mission", "unmarkSystem", MIN(oojsArgs.count(), 1U), OOJS_ARGV, std::nullopt, "numbers or objects");
				return false;
			}
		}
	}

	bool result = true;
	for (i=0;i<oojsArgs.count();i++)
	{
		if (ooscript::valueToInt32(context, (OOJS_ARGV[i]), &dest)) 
		{
			cxx_OOStandardsDeprecated("Use of numbers for mission.unmarkSystem is deprecated");
			if (!OOEnforceStandards())
			{
				if (!(player != nullptr ? player->removeMissionDestinationMarker((player != nullptr ? player->defaultMarker(dest) : oo::PList())) : false)) {
					result = false;
				}
			}
		}
		else // must be object, from above
		{
			ooscript::clearPendingException(context); // or valueToInt32 exception crashes JS engine
			oo::PList marker = cxx_OOJSPListFromJSObject(context, ooscript::toObject(OOJS_ARGV[i]));
			OOSystemID system = marker.get<int>("system", -1);
			if (system >= 0)
			{
				if (!(player != nullptr ? player->removeMissionDestinationMarker(marker) : false)) {
					result = false;
				}
			}
		}
	}
	
	OOJS_RETURN_BOOL(result);
	
	OOJS_NATIVE_EXIT
}
} // namespace


// addMessageText(text : String)
namespace {
static bool MissionAddMessageText(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_NATIVE_ENTER(context)
	
	PlayerEntity		*player = OOPlayerForScripting();
	std::optional<std::string>			text;
	
	if (EXPECT_NOT(oojsArgs.count() == 0))
	{
		OOJS_RETURN_VOID;
	}
	
	// Found "FIXME: warning if no mission screen running.",,,
	// However: used routinely by the Constrictor mission in F7, without mission screens.
	text = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (text.has_value())  { if (player != nullptr)  player->addLiteralMissionText(*text); }	// (nil added nothing)
	
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}
} // namespace


// setInstructionsKey(instructionsKey: String [, missionKey : String])
namespace {
static bool MissionSetInstructionsKey(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	return MissionSetInstructionsInternal(context, oojsArgs, true);
}
} // namespace


// setInstructions(instructions: String [, missionKey : String])
namespace {
static bool MissionSetInstructions(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	return MissionSetInstructionsInternal(context, oojsArgs, false);
}
} // namespace


namespace {
static bool MissionSetInstructionsInternal(ooscript::Context context, ooscript::CallArgs &oojsArgs, bool isKey)
{
	OOJS_NATIVE_ENTER(context)
	
	PlayerEntity		*player = OOPlayerForScripting();
	std::optional<std::string>			text;
	oo::PList			texts;
	std::optional<std::string>			missionKey;
	
	if (EXPECT_NOT(oojsArgs.count() == 0))
	{
		cxx_OOJSReportWarning(context, "Usage error: mission.%s() called with no arguments. Treating as Mission.%s(null). This call may fail in a future version of Oolite.", (isKey ? "setInstructionsKey" : "setInstructions"), (isKey ? "setInstructionsKey" : "setInstructions"));
	}
	else if (EXPECT_NOT(ooscript::isUndefined(OOJS_ARGV[0])))
	{
		cxx_OOJSReportBadArguments(context, "Mission", std::string(isKey ? "setInstructionsKey" : "setInstructions"), 1, OOJS_ARGV, std::nullopt, "string or null");
		return false;
	}
	else if (!ooscript::isNull(OOJS_ARGV[0]) && ooscript::isObjectOrNull(OOJS_ARGV[0]))
	{
		texts = cxx_OOJSPListFromJSValue(context, OOJS_ARGV[0]);
	}
	else
	{
		text = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
	}
	
	if (oojsArgs.count() > 1)
	{
		missionKey = cxx_OOStringFromJSValueEvenIfNull(context, OOJS_ARGV[1]);
	}
	else
	{
		OOJSScript *runningScript = OOJSScript::currentlyRunningScript();
		missionKey = (runningScript != nullptr) ? runningScript->name() : std::nullopt;
	}
	
	if (text.has_value())
	{
		if (isKey)
		{
			if (player != nullptr)  player->setMissionDescription(*text, missionKey);
		}
		else
		{
			if (player != nullptr)  player->setMissionInstructions(*text, missionKey);
		}
	}
	else if (!texts.isNull() && !isKey)
	{
		if (player != nullptr)  player->setMissionInstructionsList(texts, missionKey);
	}
	else
	{
		if (missionKey.has_value())  { if (player != nullptr)  player->clearMissionDescriptionForMission(*missionKey); }
		else  { if (player != nullptr)  player->setMissionInstructions(std::string(), std::nullopt); }	// logs "mission key not set", as a nil key did
	}
	
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}
} // namespace


namespace {
static oo::PList GetParameterDictionary(ooscript::Context context, ooscript::Object object, const char *key)
{
	ooscript::Value value = ooscript::nullValue();
	if (ooscript::getProperty((context), (object), key, (&value)))
	{
		if (ooscript::isObjectOrNull(value))
		{
			return cxx_OOJSPListFromJSObject(context, ooscript::toObject(value));
		}
	}
	return oo::PList();	// was nil
}
} // namespace


namespace {
static std::optional<std::string> GetParameterString(ooscript::Context context, ooscript::Object object, const char *key)
{
	ooscript::Value value = ooscript::nullValue();
	if (ooscript::getProperty((context), (object), key, (&value)))
	{
		return cxx_OOStringFromJSValue(context, value);
	}
	return std::nullopt;
}


// What -oo_stringForKey: made of the value it found: a string, or a number's text; nullopt (was
// nil) for no value or any other kind of value.
static std::optional<std::string> StringFromPList(const oo::PList *value)
{
	if (value == nullptr || !(value->isString() || value->isNumber()))  return std::nullopt;
	return oo::PListGet<std::string>::from(value, std::string());
}
} // namespace


namespace {
static oo::PList GetParameterImageDescriptor(ooscript::Context context, ooscript::Object object, const char *key)
{
	ooscript::Value value = ooscript::nullValue();
	if (ooscript::getProperty((context), (object), key, (&value)))
	{
		return UNIVERSE->getGui()->textureDescriptorFromJSValue(value, context, "mission.runScreen()");
	}
	else
	{
		return oo::PList();	// was nil
	}
}
} // namespace


// runScreen(params: dict, callBack:function) - if the callback function is null, emulate the old style runMissionScreen
namespace {
static bool MissionRunScreen(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_NATIVE_ENTER(context)
	
	PlayerEntity		*player = OOPlayerForScripting();
	ooscript::Value				function = ooscript::nullValue();
	ooscript::Value				value = ooscript::nullValue();
	ooscript::Object params = NULL;
	
	// No mission screens during intro.
	if ((player != nullptr ? player->status() : OOEntityStatus{}) == STATUS_START_GAME)
	{
		// (though no JS should be loaded at this stage, so this
		// check may be obsolete - CIM)
		OOJS_RETURN_BOOL(false);
	}
	
	// Validate arguments.
	if (oojsArgs.count() < 1 || !ooscript::valueToObject(context, (OOJS_ARGV[0]), &params))
	{
		cxx_OOJSReportBadArguments(context, "mission", "runScreen", MIN(oojsArgs.count(), 1U), &OOJS_ARGV[0], std::nullopt, "parameter object");
		return false;
	}
	
	if (oojsArgs.count() > 1)  function = OOJS_ARGV[1];
	if (!ooscript::isNull(function) && !OOJSValueIsFunction(context, function))
	{
		cxx_OOJSReportBadArguments(context, "mission", "runScreen", 1, &OOJS_ARGV[1], std::nullopt, "function");
		return false;
	}
	
	// Not OOJS_BEGIN_FULL_NATIVE() - we use JSAPI while paused.
	OOJSPauseTimeLimiter();
	
	if (!ooscript::isNull(function))
	{

		/* CIM 30/12/12: This following line causes problems in certain
		 * cases, but has to be kept for backward
		 * compatibility. Documenting the third argument of
		 * mission.runScreen will at least help people get around it in
		 * multi-world-script mission screens. (Though, since no-one has
		 * complained yet, perhaps I'm the only one who uses them?) */

		sCallbackScript = OOJSScript::currentlyRunningScript();
		if (sCallbackScript != nullptr)  sCallbackScript->retain();
		if (oojsArgs.count() > 2)
		{
			sCallbackThis = OOJS_ARGV[2];
		}
		else
		{
			sCallbackThis = OOJSValueFromCxxObject(context, sCallbackScript);
		}
	}
	
	// Apply settings.
	if (ooscript::getProperty(context, (params), "title", (&value)) && !ooscript::isUndefined(value))
	{
		if (player != nullptr)  player->setMissionTitle(cxx_OOStringFromJSValue(context, value));
	}
	else
	{
		std::optional<std::string> titleKey = GetParameterString(context, params, "titleKey");
		if (titleKey.has_value())
		{
			const oo::PList missionText = (UNIVERSE != nullptr ? UNIVERSE->getMissiontext() : oo::PList());
			std::optional<std::string> message = StringFromPList(missionText.find(*titleKey));	// -objectForKey:
			if (message.has_value())
			{
				if (player != nullptr)  player->setMissionTitle(cxx_OOExpand(*message));
			}
			else
			{
				cxx_OOJSReportWarning(context, "Mission.runScreen: titleKey '%s' has no entry in missiontext.plist.", titleKey->c_str());
			}
		}
	}
	
	OOMusicController::sharedController()->setMissionMusic(GetParameterString(context, params, "music"));
	if (player != nullptr)  player->setMissionOverlayDescriptor(GetParameterImageDescriptor(context, params, "overlay"));
	if (player != nullptr)  player->setMissionBackgroundDescriptor(GetParameterImageDescriptor(context, params, "background"));
	if (player != nullptr)  player->setMissionBackgroundSpecial(GetParameterString(context, params, "backgroundSpecial").value_or(""));

	if (ooscript::getProperty(context, (params), "customChartZoom", (&value)) && !ooscript::isUndefined(value))
	{
		double zoom;
		if (ooscript::valueToNumber(context, (value), &zoom))
		{
			if (zoom >= 1 && zoom <= CHART_MAX_ZOOM)
			{
				if (player != nullptr)  player->setCustomChartZoom(zoom);
			}
			else 
			{
				cxx_OOJSReportWarning(context, "Mission.runScreen: invalid customChartZoom value specified.");
				if (player != nullptr)  player->setCustomChartZoom(1);
			}
		}
	}
	if (ooscript::getProperty(context, (params), "customChartCentre", (&value)) && !ooscript::isUndefined(value))
	{
		Vector vValue;
		if (JSValueToVector(context, value, &vValue))
		{
			NSPoint coords = { vValue.x, vValue.y };
			if (player != nullptr)  player->setCustomChartCentre(coords);
		}
		else 
		{
			if (player != nullptr)  player->setCustomChartCentre((player != nullptr ? player->PlayerEntity::getGalaxy_coordinates() : NSPoint{}));	// qualified: the final overrider (bead oo-9ht.177), so the binding test stands in for it
			cxx_OOJSReportWarning(context, "Mission.runScreen: invalid value for customChartCentre. Must be valid vector. Defaulting to current location.");
		}
	}
	if (ooscript::getProperty(context, (params), "customChartCentreInLY", (&value)) && !ooscript::isUndefined(value))
	{
		Vector vValue;
		if (JSValueToVector(context, value, &vValue))
		{
			NSPoint coords = OOInternalCoordinatesFromGalactic(vValue);
			if (player != nullptr)  player->setCustomChartCentre(coords);
		}
		else 
		{
			if (player != nullptr)  player->setCustomChartCentre((player != nullptr ? player->PlayerEntity::getGalaxy_coordinates() : NSPoint{}));	// qualified: the final overrider (bead oo-9ht.177), so the binding test stands in for it
			cxx_OOJSReportWarning(context, "Mission.runScreen: invalid value for customChartCentreInLY. Must be valid vector. Defaulting to current location.");
		}
	}

	if (UNIVERSE != nullptr)  UNIVERSE->removeDemoShips();	// remove any demoship or miniature planet that may be remaining from previous screens
	
	ShipEntity *demoShip = nil;
	if (ooscript::getProperty(context, (params), "model", (&value)) && !ooscript::isUndefined(value))
	{
		if ((player != nullptr ? player->status() : OOEntityStatus{}) == STATUS_IN_FLIGHT && ooscript::isString(value))
		{
			cxx_OOJSReportWarning(context, "Mission.runScreen: model cannot be displayed while in flight.");
		}
		else
		{
			std::optional<std::string> role = cxx_OOStringFromJSValue(context, value);
			
			bool spinning = true;
			if (ooscript::getProperty(context, (params), "spinModel", (&value)) && !ooscript::isUndefined(value))
			{
				ooscript::valueToBoolean(context, (value), &spinning);
			}
			
		//	[player showShipModel:oo::NSStringOrNil(cxx_OOStringFromJSValue(context, value))];
			demoShip = (UNIVERSE != nullptr ? UNIVERSE->makeDemoShipWithRole(role.value_or(""), (bool)spinning) : (::ShipEntity *)nil);
		}
	}
	if (demoShip != nil)
	{
		if (ooscript::getProperty(context, (params), "modelPersonality", (&value)) && !ooscript::isUndefined(value))
		{
			int32_t personality = 0;
			ooscript::valueToInt32(context, (value), &personality);
			if (demoShip != nullptr)  demoShip->setEntityPersonalityInt(personality);
		}
		ooscript::Value demoShipVal = OOJSValueFromCxxObject(context, demoShip);	// the C++ ship's JS value (its object's -oo_jsValueInContext: until bead oo-9ht.39.8.2)
		ooscript::setProperty(context, (sMissionObject), "displayModel", (&demoShipVal));
	}
	else
	{
		ooscript::deleteProperty(context, (sMissionObject), "displayModel");
	}

	bool allowInterrupt = false;
	// force the allowInterrupt to be YES while in flight
	if ((player != nullptr ? player->status() : OOEntityStatus{}) == STATUS_IN_FLIGHT) 
	{
		allowInterrupt = true;
	} 
	else
	{
		if (ooscript::getProperty(context, (params), "allowInterrupt", (&value)) && !ooscript::isUndefined(value))
		{
			ooscript::valueToBoolean(context, (value), &allowInterrupt);
		}
	}

	if (ooscript::getProperty(context, (params), "exitScreen", (&value)) && !ooscript::isUndefined(value))
	{
		if (player != nullptr)  player->setMissionExitScreen(OOGUIScreenIDFromJSValue(context, value));
	}
	else
	{
		if (player != nullptr)  player->setMissionExitScreen(GUI_SCREEN_STATUS);
	}

	if (ooscript::getProperty(context, (params), "screenID", (&value)) && !ooscript::isUndefined(value))
	{
		if (player != nullptr)  player->setMissionScreenID(cxx_OOStringFromJSValue(context, value));
	}
	else
	{
		if (player != nullptr)  player->clearMissionScreenID();
	}

	if (player != nullptr)  player->clearExtraMissionKeys();
	if (ooscript::getProperty(context, (params), "registerKeys", (&value)) && !ooscript::isUndefined(value))
	{
		if (player != nullptr)  player->setExtraMissionKeys(GetParameterDictionary(context, params, "registerKeys"));
	}

	bool textEntry = false;
	if (ooscript::getProperty(context, (params), "textEntry", (&value)) && !ooscript::isUndefined(value))
	{
		ooscript::valueToBoolean(context, (value), &textEntry);
	}
	if (textEntry)
	{
		if (player != nullptr)  player->setMissionChoiceByTextEntry(true);
	}
	else
	{
		if (player != nullptr)  player->setMissionChoiceByTextEntry(false);
	}

	// Start the mission screen.
	sCallbackFunction = function;
	if (player != nullptr)  player->setGuiToMissionScreenWithCallback(!ooscript::isNull(sCallbackFunction));

	// Apply more settings. (These must be done after starting the screen for legacy reasons.)
	if (allowInterrupt)
	{
		if (player != nullptr)  player->allowMissionInterrupt();
	}
	std::optional<std::string> message = GetParameterString(context, params, "message");
	if (message.has_value())
	{
		if (player != nullptr)  player->addLiteralMissionText(*message);
	}
	else
	{
		std::optional<std::string> messageKey = GetParameterString(context, params, "messageKey");
		if (messageKey.has_value())  { if (player != nullptr)  player->addMissionText(*messageKey); }
	}
	
	if (!textEntry)
	{
		oo::PList choices = GetParameterDictionary(context, params, "choices");
		if (choices.isNull())
		{
			if (player != nullptr)  player->setMissionChoices(GetParameterString(context, params, "choicesKey").value_or(std::string()));	// (nil was "")
		}
		else 
		{
			if (player != nullptr)  player->setMissionChoicesDictionary(choices);		
		}
	}

	std::optional<std::string> firstKey = GetParameterString(context, params, "initialChoicesKey");
	if (firstKey.has_value())
	{
		OOGUIRow row = UNIVERSE->getGui()->rowForKey(firstKey);
		if (row != -1)
		{
			UNIVERSE->getGui()->setSelectedRow(row);
		}
	}
	
	// now clean up!
	if (player != nullptr)  player->setMissionOverlayDescriptor(oo::PList());
	if (player != nullptr)  player->setMissionBackgroundDescriptor(oo::PList());
	if (player != nullptr)  player->setMissionTitle(std::nullopt);
	if (player != nullptr)  player->setMissionMusic(std::string());	// (nil was "none")
	
	OOJSResumeTimeLimiter();
	
	OOJS_RETURN_BOOL(true);
	
	OOJS_NATIVE_EXIT
}
} // namespace


namespace {
static bool MissionRunShipLibrary(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_NATIVE_ENTER(context)
	
	PlayerEntity	*player = OOPlayerForScripting();
	bool			OK = true;
	if ((player != nullptr ? player->status() : OOEntityStatus{}) != STATUS_DOCKED)
	{
		cxx_OOJSReportWarning(context, "Mission.runShipLibrary: must be docked.");
		OK = false;
	}
	else
	{
		if (PLAYER != nullptr)  PLAYER->setGuiToIntroFirstGo(false);
	}
	
	OOJS_RETURN_BOOL(OK);
	
	OOJS_NATIVE_EXIT
}
} // namespace

