/*

OOJSGlobal.m


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

#include "OOJSGlobal.h"
#include "OOJavaScriptEngine.h"

#include "OOJSPlayer.h"
#include "PlayerEntityScriptMethods.h"
#include "OOStringExpander.h"
#include "OOConstToString.h"
#include "OOConstToJSString.h"
#include "OOTexture.h"
#include "GuiDisplayGen.h"
#include "MyOpenGLView.h"
#include "ResourceManager.h"
#include "OOSystemDescriptionManager.h"
#include "OOJSGuiScreenKeyDefinition.h"
#include "oofnd/FileSystem.hpp"
#include "oofnd/ResourcePaths.hpp"
#include "oofnd/Scanner.hpp"

#include "ooscript/JSEngine.hpp"
#include <cstring>
#include "oofnd/String.hpp"

/*
	Retargeted onto the ooscript façade (JSEngine.hpp) per bead oo-8yi, the same way bead oo-sdz
	retargeted OOJSVector.mm (the exemplar for this sweep; see its header comment for the full
	rationale). This file's directly-spelled engine calls -- the ooscript::ClassDef hook-stub family
	(PropertyStub/EnumerateStub/ResolveStub/ConvertStub), NewNumberValue, ValueToNumber,
	ValueToBoolean, ValueToObject, GetProperty, DefineProperty, DefineProperties,
	DefineFunctions, NewCompartmentAndGlobalObject and SetGlobalObject -- become their
	ooscript:: façade equivalents per ooscript/README.md's retarget map; the OOJS_*
	argument-marshalling macros (OOJS_ARGV, OOJS_THIS, OOJS_NATIVE_ENTER/EXIT, OOJS_RETURN_*)
	are OOJS_*-spelled, not themselves the engine's own prefix at these call sites, and stay
	exactly as before, out of scope for the sweep.

	SetGlobalObject had no façade equivalent yet; ooscript::setGlobalObject is added to
	JSEngine.hpp/JSEngine_spidermonkey.cpp by this bead following the existing
	newGlobalObject/getGlobalObject pattern (the engine's SetGlobalObject entry point's only call site in the tree).

	Retargeting DefineProperties/DefineFunctions requires sGlobalProperties/sGlobalMethods to
	become ooscript::PropertySpec/FunctionSpec tables (the façade's DefineProperties and
	DefineFunctions take those, not the engine's ooscript::PropertySpec / ooscript::FunctionSpec pointers),
	every JS global method to take the façade's NativeFn hook signature
	(Context, CallArgs&) rather than the engine's (ooscript::Context, unsigned argc, ooscript::Value *vp). A small
	shim at the top of each recovers the old ooscript::Context, unsigned, and ooscript::Value * locals so the
	OOJS_* argument-marshalling macros and the rest of each body are UNCHANGED, exactly as
	OOJSVector.mm's own retarget does it. GlobalGetProperty/GlobalSetProperty take the façade's
	PropertyGetter/PropertySetter hook signature for the same reason (they are wired into
	sGlobalClass, now a ClassDef). `this` is renamed to `thisObj` because it is a reserved word
	once this file compiles as Objective-C++ (ADR-0001).
*/

/*
	C++20 since bead oo-3dj2, converted the way bead oo-ppc converted OOJSVector.mm (proposed
	ADR-0056 amendment oo-ppc). The JS class was already C++ on the ooscript façade;
	OOJS_NATIVE_ENTER/EXIT and OOJS_PROFILE_ENTER/EXIT are C++ try/catch and scope guards
	(OOJSEngineNativeWrappers.h); BOOL/YES/NO are bool/true/false. log() calls the C++ engine's
	monitor member directly (bead oo-9ht.98; amendments oo-9ht.66 and oo-6ia4 item 6). OOColor, which
	is C++ since bead oo-11m, is reached as a cxx:: class through oo::ToCxx/oo::ToObjC (amendment
	oo-ppc, item 4); OOJSGuiScreenKeyDefinition is C++ since bead oo-xg7g and has no façade since
	bead oo-9ht.62: the key definition is made with oo::makeRef and the player keeps it.
	Messages to classes that are still Objective-C (PlayerEntity, Universe, GuiDisplayGen,
	MyOpenGLView, ResourceManager) stay as they are, which is why the file is still .mm until Phase
	4.
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

// Byte-identical façade <-> jsapi views, local to this call site (JSEngine.hpp: Value/PropertyId
// and the handle types are byte copies of ooscript::Value/ooscript::PropertyId/JS*; see OOJSVector.mm for the same,
// non-exported, pattern).


static const char * const kOOLogDebugMessage = "script.debug.message";


namespace {
static bool GlobalGetProperty(Context cx, Object obj, PropertyId propID, Value *value);

// What -oo_stringForKey: made of the value it found: a string, or a number's text; nullopt (was
// nil) for no value or any other kind of value.
static std::optional<std::string> StringFromPList(const oo::PList *value)
{
	if (value == nullptr || !(value->isString() || value->isNumber()))  return std::nullopt;
	return oo::PListGet<std::string>::from(value, std::string());
}
} // namespace
#ifndef NDEBUG
namespace {
static bool GlobalSetProperty(Context cx, Object obj, PropertyId propID, bool strict, Value *value);
} // namespace
#endif

namespace {
static bool GlobalLog(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace
namespace {
static bool GlobalExpandDescription(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace
namespace {
static bool GlobalKeyBindingDescription(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace
namespace {
static bool GlobalExpandMissionText(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace
namespace {
static bool GlobalDisplayNameForCommodity(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace
namespace {
static bool GlobalRandomName(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace
namespace {
static bool GlobalRandomInhabitantsDescription(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace
namespace {
static bool GlobalSetScreenBackground(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace
namespace {
static bool GlobalSetScreenOverlay(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace
namespace {
static bool GlobalGetScreenBackgroundForKey(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace
namespace {
static bool GlobalSetScreenBackgroundForKey(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace
namespace {
static bool GlobalAutoAIForRole(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace
namespace {
static bool GlobalPauseGame(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace
namespace {
static bool GlobalQuitGame(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace
namespace {
static bool GlobalGetGuiColorSettingForKey(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace
namespace {
static bool GlobalSetGuiColorSettingForKey(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace
namespace {
static bool GlobalSetExtraGuiScreenKeys(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace
namespace {
static bool GlobalClearExtraGuiScreenKeys(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace

#ifndef NDEBUG
namespace {
static bool GlobalTakeSnapShot(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace
#endif


namespace {
static ClassDef sGlobalClass =
{
	"Global",
	ClassFlag::Global,

	nullptr,			// addProperty (engine default: PropertyStub)
	nullptr,			// delProperty (engine default: PropertyStub)
	GlobalGetProperty,	// getProperty
#ifndef NDEBUG
	GlobalSetProperty,	// setProperty
#else
	// No writeable properties in non-debug builds
	nullptr,			// setProperty (engine default: StrictPropertyStub)
#endif
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


enum : std::int8_t
{
	// Property IDs
	kGlobal_galaxyNumber,		// galaxy number, integer, read-only
	kGlobal_global,				// global.global.global.global, integer, read-only
	kGlobal_guiScreen,			// current GUI screen, string, read-only
#ifndef NDEBUG
	kGlobal_timeAccelerationFactor	// time acceleration, float, read/write
#endif
};


namespace {
static constexpr PropertyFlag kGlobalROPropFlags  = PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Shared;
#ifndef NDEBUG
static constexpr PropertyFlag kGlobalRWPropFlags  = PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared;
#endif
static PropertySpec sGlobalProperties[] =
{
	// JS name					ID							flags									getter	setter
	{ "galaxyNumber",			kGlobal_galaxyNumber,		kGlobalROPropFlags,	nullptr, nullptr },
	{ "guiScreen",				kGlobal_guiScreen,			kGlobalROPropFlags,	nullptr, nullptr },
#ifndef NDEBUG
	{ "timeAccelerationFactor",	kGlobal_timeAccelerationFactor,	kGlobalRWPropFlags,	nullptr, nullptr },
#endif
	{ 0 }
};
} // namespace


// A raw jsapi mirror of sGlobalProperties, used only for the two bad-property error reporters
// in OOJavaScriptEngine.m (OOJSReportBadPropertySelector/Value): those helpers are outside this
// bead's scope (they are shared across every binding file) and still take a ooscript::PropertySpec*,
// not ooscript::PropertySpec*, the same as OOJSVector.mm's sVectorPropertiesRaw.
namespace {
static ooscript::PropertySpec sGlobalPropertiesRaw[] =
{
	// JS name					ID							flags
	{ "galaxyNumber",			kGlobal_galaxyNumber,		OOJS_PROP_READONLY_CB },
	{ "guiScreen",				kGlobal_guiScreen,			OOJS_PROP_READONLY_CB },
#ifndef NDEBUG
	{ "timeAccelerationFactor",	kGlobal_timeAccelerationFactor,	OOJS_PROP_READWRITE_CB },
#endif
	{ 0 }
};
} // namespace


namespace {
static FunctionSpec sGlobalMethods[] =
{
	// JS name								Function								min args	flags
	{ "log",								GlobalLog,							1,			0 },
	{ "autoAIForRole",						GlobalAutoAIForRole,				1,			0 },
	{ "expandDescription",					GlobalExpandDescription,			1,			0 },
	{ "expandMissionText",					GlobalExpandMissionText,			1,			0 },
	{ "displayNameForCommodity",			GlobalDisplayNameForCommodity,		1,			0 },
	{ "randomName",							GlobalRandomName,					0,			0 },
	{ "randomInhabitantsDescription",		GlobalRandomInhabitantsDescription,	1,			0 },
	{ "setScreenBackground",				GlobalSetScreenBackground,			1,			0 },
	{ "getScreenBackgroundForKey",      GlobalGetScreenBackgroundForKey,    1,			0 },
	{ "setScreenBackgroundForKey",      GlobalSetScreenBackgroundForKey,    2,			0 },
	{ "setScreenOverlay",					GlobalSetScreenOverlay,				1,			0 },
	{ "getGuiColorSettingForKey",       GlobalGetGuiColorSettingForKey,     1,			0 },
	{ "setGuiColorSettingForKey",       GlobalSetGuiColorSettingForKey,     2,			0 },
	{ "keyBindingDescription",       	GlobalKeyBindingDescription,		1,			0 },
	{ "setExtraGuiScreenKeys",			GlobalSetExtraGuiScreenKeys,		2,			0 },
	{ "clearExtraGuiScreenKeys",		GlobalClearExtraGuiScreenKeys,		2,			0 },

#ifndef NDEBUG
	{ "takeSnapShot",					GlobalTakeSnapShot,					1,			0 },
	{ "quitGame",						GlobalQuitGame,						0,			0 },
#endif
	{ "pauseGame",						GlobalPauseGame,					0,			0 },
	{ 0 }
};
} // namespace


namespace {
static constexpr PropertyFlag kGlobalSelfPropertyFlags = PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly;
} // namespace


void CreateOOJSGlobal(ooscript::Context context, ooscript::Object *outGlobal)
{
	assert(outGlobal != NULL);
	
	Context cx = (context);
	Object global = ooscript::newGlobalObject(cx, &sGlobalClass);
	*outGlobal = (global);
	
	ooscript::setGlobalObject(cx, global);
	ooscript::defineProperty(cx, global, "global", ooscript::objectValue(global), nullptr, nullptr,
							  kGlobalSelfPropertyFlags);
}


void SetUpOOJSGlobal(ooscript::Context context, ooscript::Object global)
{
	Context cx = (context);
	Object obj = (global);
	ooscript::defineProperties(cx, obj, sGlobalProperties);
	ooscript::defineFunctions(cx, obj, sGlobalMethods);
}


namespace {
static bool GlobalGetProperty(Context cx, Object obj, PropertyId propID, Value *value)
{
	if (!ooscript::isInt32Id(propID))  return true;
	
	ooscript::Context context = (cx);
	ooscript::Object thisObj = (obj);
	
	OOJS_NATIVE_ENTER(context)
	
	PlayerEntity				*player = OOPlayerForScripting();
	
	switch (ooscript::idToInt32(propID))
	{
		case kGlobal_galaxyNumber:
			*value = ooscript::int32Value((player != nullptr ? player->PlayerEntity::currentGalaxyID() : OOGalaxyID{}));	// qualified: the final overrider (bead oo-9ht.177), so the binding test stands in for it
			return true;
			
		case kGlobal_guiScreen:
			*value = (OOJSValueFromGUIScreenID(context, (player != nullptr ? player->guiScreen() : OOGUIScreenID{})));
			return true;
			
#ifndef NDEBUG
		case kGlobal_timeAccelerationFactor:
			return ooscript::newNumberValue(cx, (UNIVERSE != nullptr ? UNIVERSE->getTimeAccelerationFactor() : 0.0), value);
#endif
			
		default:
			OOJSReportBadPropertySelector(context, thisObj, (propID), sGlobalPropertiesRaw);
			return false;
	}
	
	OOJS_NATIVE_EXIT
}
} // namespace


#ifndef NDEBUG
namespace {
static bool GlobalSetProperty(Context cx, Object obj, PropertyId propID, bool /*strict*/, Value *value)
{
	if (!ooscript::isInt32Id(propID))  return true;
	
	ooscript::Context context = (cx);
	ooscript::Object thisObj = (obj);
	
	OOJS_NATIVE_ENTER(context)
	
	double					fValue;
	
	switch (ooscript::idToInt32(propID))
	{
		case kGlobal_timeAccelerationFactor:
			if (ooscript::valueToNumber(cx, *value, &fValue))
			{
				if (UNIVERSE != nullptr)  UNIVERSE->setTimeAccelerationFactor(fValue);
				return true;
			}
			break;
	
		default:
			OOJSReportBadPropertySelector(context, thisObj, (propID), sGlobalPropertiesRaw);
	}
	
	OOJSReportBadPropertyValue(context, thisObj, (propID), sGlobalPropertiesRaw, *(value));
	return false;
	
	OOJS_NATIVE_EXIT
}
} // namespace
#endif


// *** Methods ***

// log([messageClass : String,] message : string, ...)
namespace {
static bool GlobalLog(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_NATIVE_ENTER(context)
	
	std::optional<std::string>	message;
	std::string			messageClass;
	
	if (EXPECT_NOT(oojsArgs.count() < 1))
	{
		OOJS_RETURN_VOID;
	}
	if (oojsArgs.count() < 2)
	{
		messageClass = kOOLogDebugMessage;
		message = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
	}
	else
	{
		messageClass = cxx_OOStringFromJSValueEvenIfNull(context, OOJS_ARGV[0]).value_or(std::string());
		if (!oo::log::willDisplay(messageClass))
		{
			// Do nothing (and short-circuit) if message class is filtered out.
			OOJS_RETURN_VOID;
		}
		
		// The remaining arguments as strings, joined with ", " (as +concatenationOfStringsFromJavaScriptValues:... did).
		std::string joined;
		for (unsigned i = 1; i < oojsArgs.count(); i++)
		{
			if (i > 1)  joined += ", ";
			joined += cxx_OOStringFromJSValueEvenIfNull(context, OOJS_ARGV[i]).value_or(std::string());
		}
		message = joined;
	}
	
	OOJS_BEGIN_FULL_NATIVE(context)
	OO_LOG(messageClass, "{}", message.value_or("(null)"));
	
#if OOJSENGINE_MONITOR_SUPPORT
	OOJavaScriptEngine::sharedEngine()->sendMonitorLogMessage(message, std::nullopt, context);
#endif
	OOJS_END_FULL_NATIVE
	
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}
} // namespace


// expandDescription(description : String [, overrides : object (dictionary)]) : String
namespace {
static bool GlobalExpandDescription(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_NATIVE_ENTER(context)
	
	std::optional<std::string>	string;
	oo::PList			overrides;
	
	if (oojsArgs.count() > 0)  string = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (!string.has_value())
	{
		cxx_OOJSReportBadArguments(context, std::nullopt, "expandDescription", MIN(oojsArgs.count(), 1U), OOJS_ARGV, std::nullopt, "string");
		return false;
	}
	if (oojsArgs.count() > 1)
	{
		overrides = OOJSDictionaryFromStringTable(context, OOJS_ARGV[1]);
	}
	
	OOJS_BEGIN_FULL_NATIVE(context)
	string = cxx_OOExpandDescriptionString(kNilRandomSeed, *string, overrides, oo::PList(), std::nullopt, kOOExpandForJavaScript | kOOExpandGoodRNG);
	OOJS_END_FULL_NATIVE
	
	OOJS_RETURN_STRING_OR_NULL(string);
	
	OOJS_NATIVE_EXIT
}
} // namespace

namespace {
static bool GlobalKeyBindingDescription(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_NATIVE_ENTER(context)
	
	std::optional<std::string>	string;
	PlayerEntity				*player = OOPlayerForScripting();
	
	if (oojsArgs.count() > 0)  string = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (!string.has_value())
	{
		cxx_OOJSReportBadArguments(context, std::nullopt, "keyBindingDescription", MIN(oojsArgs.count(), 1U), OOJS_ARGV, std::nullopt, "string");
		return false;
	}
	
	OOJS_BEGIN_FULL_NATIVE(context)
	string = (player != nullptr ? player->keyBindingDescription2(*string) : std::optional<std::string>());
	OOJS_END_FULL_NATIVE
	
	OOJS_RETURN_STRING_OR_NULL(string);
	
	OOJS_NATIVE_EXIT
}
} // namespace


// expandMissionText(textKey : String [, overrides : object (dictionary)]) : String
namespace {
static bool GlobalExpandMissionText(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_NATIVE_ENTER(context)
	
	std::optional<std::string>	string;
	oo::PList			overrides;
	
	if (oojsArgs.count() > 0)  string = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (!string.has_value())
	{
		cxx_OOJSReportBadArguments(context, std::nullopt, "expandMissionText", MIN(oojsArgs.count(), 1U), OOJS_ARGV, std::nullopt, "string");
		return false;
	}
	if (oojsArgs.count() > 1)
	{
		overrides = OOJSDictionaryFromStringTable(context, OOJS_ARGV[1]);
	}
	
	const oo::PList missionText = (UNIVERSE != nullptr ? UNIVERSE->getMissiontext() : oo::PList());
	string = StringFromPList(missionText.find(*string));	// -objectForKey:
	if (string.has_value())  string = cxx_OOExpandDescriptionString(kNilRandomSeed, *string, overrides, oo::PList(), std::nullopt, kOOExpandForJavaScript | kOOExpandBackslashN | kOOExpandGoodRNG);	// nil expanded to nil
	
	OOJS_RETURN_STRING_OR_NULL(string);
	
	OOJS_NATIVE_EXIT
}
} // namespace


// displayNameForCommodity(commodityName : String) : String
namespace {
static bool GlobalDisplayNameForCommodity(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_NATIVE_ENTER(context)
	
	std::optional<std::string>	string;
	
	if (oojsArgs.count() > 0)  string = cxx_OOStringFromJSValue(context,OOJS_ARGV[0]);
	if (!string.has_value())
	{
		cxx_OOJSReportBadArguments(context, std::nullopt, "displayNameForCommodity", MIN(oojsArgs.count(), 1U), OOJS_ARGV, std::nullopt, "string");
		return false;
	}
	OOJS_RETURN_PLIST(oo::PList(cxx_CommodityDisplayNameForSymbolicName(*string)));
	
	OOJS_NATIVE_EXIT
}
} // namespace


// randomName() : String
namespace {
static bool GlobalRandomName(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_NATIVE_ENTER(context)
	
	/*	Temporarily set the system generation seed to a "really random" seed,
		so randomName() isn't repeatable.
	*/
	RNG_Seed savedSeed = currentRandomSeed();
	setRandomSeed((RNG_Seed){ (int32_t)Ranrot(), (int32_t)Ranrot(), (int32_t)Ranrot(), (int32_t)Ranrot() });
	
	std::optional<std::string> result = cxx_OOExpand("%N");
	
	// Restore seed.
	setRandomSeed(savedSeed);
	
	OOJS_RETURN_STRING_OR_NULL(result);
	
	OOJS_NATIVE_EXIT
}
} // namespace


// randomInhabitantsDescription() : String
namespace {
static bool GlobalRandomInhabitantsDescription(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_NATIVE_ENTER(context)
	
	std::optional<std::string>	string;
	Random_Seed			aSeed;
	bool				isPlural = true;
	
	if (oojsArgs.count() > 0 && !ooscript::valueToBoolean(context, (OOJS_ARGV[0]), &isPlural))
	{
		cxx_OOJSReportBadArguments(context, std::nullopt, "randomInhabitantsDescription", 1, OOJS_ARGV, std::nullopt, "boolean");
		return false;
	}
	
	make_pseudo_random_seed(&aSeed);
	string = (UNIVERSE != nullptr ? UNIVERSE->getSystemInhabitants(Ranrot()%OO_SYSTEMS_PER_GALAXY, (isPlural ? true : false)) : std::optional<std::string>());
	OOJS_RETURN_STRING_OR_NULL(string);
	
	OOJS_NATIVE_EXIT
}
} // namespace


namespace {
static bool GlobalClearExtraGuiScreenKeys(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_NATIVE_ENTER(context)

	bool				result = false;
	PlayerEntity		*player = OOPlayerForScripting();

	if (EXPECT_NOT(oojsArgs.count() < 2))
	{
		cxx_OOJSReportBadArguments(context, std::nullopt, "setExtraGuiScreenKeys", 0, OOJS_ARGV, std::nullopt, "missing arguments");
		return false;
	}

	std::optional<std::string> key = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (EXPECT_NOT(!key.has_value() || key->empty()))
	{
		cxx_OOJSReportBadArguments(context, std::nullopt, "clearExtraGuiScreenKeys", 1, OOJS_ARGV, std::nullopt, "key");
		return false;
	}

	OOGUIScreenID gui = OOGUIScreenIDFromJSValue(context, OOJS_ARGV[1]);
	if (!gui)
	{
		cxx_OOJSReportBadArguments(context, std::nullopt, "clearExtraGuiScreenKeys", 0, OOJS_ARGV, std::nullopt, "guiScreen invalid entry");
		return false;
	}

	if (player != nullptr)  player->clearExtraGuiScreenKeys(gui, *key);

	result = true;
	OOJS_RETURN_BOOL(result);
	
	OOJS_NATIVE_EXIT
}
} // namespace

namespace {
static bool GlobalSetExtraGuiScreenKeys(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_NATIVE_ENTER(context)

	bool				result = false;
	ooscript::Value				callback = ooscript::nullValue();
	ooscript::Object callbackThis = NULL;
	ooscript::Value				value = ooscript::nullValue();
	std::optional<std::string>	key;
	OOGUIScreenID 		gui;
	oo::PList			keydefs;
	ooscript::Object params = NULL;
	PlayerEntity		*player = OOPlayerForScripting();

	if (EXPECT_NOT(oojsArgs.count() < 1))
	{
		cxx_OOJSReportBadArguments(context, std::nullopt, "setExtraGuiScreenKeys", 0, OOJS_ARGV, std::nullopt, "key, definition");
		return false;
	}
	key = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);

	// Validate arguments.
	{
		Object paramsObj = nullptr;
		if (oojsArgs.count() < 2 || !ooscript::valueToObject(context, (OOJS_ARGV[1]), &paramsObj))
		{
			cxx_OOJSReportBadArguments(context, "global", "setExtraGuiScreenKeys", 2, &OOJS_ARGV[1], std::nullopt, "key, definition: definition is not a valid dictionary.");
			return false;
		}
		params = (paramsObj);
	}

	if (!ooscript::getProperty(context, (params), "guiScreen", (&value)) || ooscript::isUndefined(value))
	{
		cxx_OOJSReportBadArguments(context, "global", "setExtraGuiScreenKeys", 2, &OOJS_ARGV[1], std::nullopt, "key, definition: must have a 'guiScreen' property.");
		return false;
	}

	gui = OOGUIScreenIDFromJSValue(context, value);
	// gui will be 0 for invalid screen id's as well as GUI_SCREEN_MAIN
	if (gui == 0 || gui == GUI_SCREEN_LOAD || gui == GUI_SCREEN_SAVE || gui == GUI_SCREEN_STICKMAPPER || gui == GUI_SCREEN_OXZMANAGER || 
		gui == GUI_SCREEN_NEWGAME || gui == GUI_SCREEN_SAVE_OVERWRITE || gui == GUI_SCREEN_KEYBOARD || gui == GUI_SCREEN_STICKPROFILE || gui == GUI_SCREEN_KEYBOARD_CONFIRMCLEAR ||
		gui == GUI_SCREEN_KEYBOARD_CONFIG || gui == GUI_SCREEN_KEYBOARD_ENTRY || gui == GUI_SCREEN_KEYBOARD_LAYOUT)
	{
		cxx_OOJSReportBadArguments(context, "global", "setExtraGuiScreenKeys", 2, &OOJS_ARGV[1], std::nullopt, "key, definition: 'guiScreen' property must be a permitted and valid GUI_SCREEN idenfifier.");
		return false;
	}

	if (!ooscript::getProperty(context, (params), "registerKeys", (&value)) || ooscript::isUndefined(value))
	{
		cxx_OOJSReportBadArguments(context, "global", "setExtraGuiScreenKeys", 2, &OOJS_ARGV[1], std::nullopt, "key, definition: must have a 'registerKeys' property.");
		return false;
	}
	if (!ooscript::isNull(value))
	{
		if (ooscript::isObjectOrNull(value))
		{
			keydefs = cxx_OOJSPListFromJSObject(context, ooscript::toObject(value));
		}
		else 
		{
			cxx_OOJSReportBadArguments(context, "global", "setExtraGuiScreenKeys", 2, &OOJS_ARGV[1], std::nullopt, "key, definition: registerKeys is not a valid dictionary.");
			return false;
		}
	}

	if (!ooscript::getProperty(context, (params), "callback", (&callback)) || ooscript::isUndefined(callback))
	{
		cxx_OOJSReportBadArguments(context, "global", "setExtraGuiScreenKeys", 2, &OOJS_ARGV[1], std::nullopt, "key, definition; must have a 'callback' property.");
		return false;
	}
	if (!OOJSValueIsFunction(context,callback))
	{
		cxx_OOJSReportBadArguments(context, "global", "setExtraGuiScreenKeys", 2, &OOJS_ARGV[1], std::nullopt, "key, definition; 'callback' property must be a function.");
		return false;
	}

	// C++ since bead oo-9ht.62 deleted its façade; the player keeps it (oo::Ref).
	const oo::Ref<OOJSGuiScreenKeyDefinition> definition = oo::makeRef<OOJSGuiScreenKeyDefinition>();
	OOJSGuiScreenKeyDefinition *cxxDefinition = definition.get();
	cxxDefinition->setName(key);
	cxxDefinition->setRegisterKeys(keydefs);
	cxxDefinition->setCallback(callback);

	// get callback 'this'
	if (ooscript::getProperty(context, (params), "cbThis", (&value)) && !ooscript::isUndefined(value))
	{
		Object callbackThisObj = nullptr;
		ooscript::valueToObject(context, (value), &callbackThisObj);
		callbackThis = (callbackThisObj);
		cxxDefinition->setCallbackThis(callbackThis);
		// can do .bind(this) for callback instead
	}

	result = (player != nullptr ? player->setExtraGuiScreenKeys(gui, definition.get()) : false);

	OOJS_RETURN_BOOL(result);
	
	OOJS_NATIVE_EXIT
}
} // namespace


// setScreenBackground(descriptor : guiTextureDescriptor) : Boolean
namespace {
static bool GlobalSetScreenBackground(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_NATIVE_ENTER(context)
	
	bool			result = false;
	ooscript::Value			value = (oojsArgs.count() > 0) ? OOJS_ARGV[0] : ooscript::nullValue();
	
	if (EXPECT_NOT(oojsArgs.count() == 0))
	{
		cxx_OOJSReportWarning(context, "Usage error: %s() called with no arguments. Treating as %s(null). This call may fail in a future version of Oolite.", "setScreenBackground", "setScreenBackground");
	}
	else if (EXPECT_NOT(ooscript::isUndefined(value)))
	{
		cxx_OOJSReportBadArguments(context, std::nullopt, "setScreenBackground", 1, &value, std::nullopt, "GUI texture descriptor");
		return false;
	}
	
	if ((UNIVERSE != nullptr ? UNIVERSE->getViewDirection() : OOViewID{}) == VIEW_GUI_DISPLAY)
	{
		GuiDisplayGen	*gui = (UNIVERSE != nullptr ? UNIVERSE->getGui() : nullptr);
		oo::PList		descriptor = gui->textureDescriptorFromJSValue(value, context, "setScreenBackground()");
		
		result = gui->setBackgroundTextureDescriptor(descriptor);
		
		// add some permanence to the override if we're in the equip ship screen
		if (result && (PLAYER != nullptr ? PLAYER->guiScreen() : OOGUIScreenID{}) == GUI_SCREEN_EQUIP_SHIP)  { if (PLAYER != nullptr)  PLAYER->setEquipScreenBackgroundDescriptor(descriptor); }
	}
	
	OOJS_RETURN_BOOL(result);
	
	OOJS_NATIVE_EXIT
}
} // namespace


namespace {
static bool GlobalGetScreenBackgroundForKey(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_NATIVE_ENTER(context)
	
	if (EXPECT_NOT(oojsArgs.count() == 0))
	{
		cxx_OOJSReportBadArguments(context, std::nullopt, "getScreenBackgroundDefault", 0, OOJS_ARGV, std::nullopt, "missing arguments");
		return false;
	}
	std::optional<std::string>	key = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (EXPECT_NOT(!key.has_value() || key->empty()))
	{
		cxx_OOJSReportBadArguments(context, std::nullopt, "getScreenBackgroundDefault", 0, OOJS_ARGV, std::nullopt, "key");
		return false;
	}
	OOJS_RETURN_PLIST((UNIVERSE != nullptr ? UNIVERSE->screenTextureDescriptorForKey(*key) : oo::PList()));
	
	OOJS_NATIVE_EXIT
} 
} // namespace

// setScreenBackgroundDefault (key : String, descriptor : guiTextureDescriptor) : boolean
namespace {
static bool GlobalSetScreenBackgroundForKey(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_NATIVE_ENTER(context)
	
	bool			result = false;
	
	if (EXPECT_NOT(oojsArgs.count() < 2))
	{
		cxx_OOJSReportBadArguments(context, std::nullopt, "setScreenBackgroundDefault", 0, OOJS_ARGV, std::nullopt, "missing arguments");
		return false;
	}

	std::optional<std::string>	key = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
	ooscript::Value			value = OOJS_ARGV[1];
	if (EXPECT_NOT(!key.has_value() || key->empty()))
	{
		cxx_OOJSReportBadArguments(context, std::nullopt, "setScreenBackgroundDefault", 0, OOJS_ARGV, std::nullopt, "key");
		return false;
	}

	GuiDisplayGen	*gui = (UNIVERSE != nullptr ? UNIVERSE->getGui() : nullptr);
	oo::PList		descriptor = gui->textureDescriptorFromJSValue(value, context, "setScreenBackgroundDefault()");
	
	if (UNIVERSE != nullptr)  UNIVERSE->setScreenTextureDescriptorForKey(*key, descriptor);	// (its Foundation round trip was the identity for this JavaScript-derived dictionary)
	result = true;
	
	OOJS_RETURN_BOOL(result);
	
	OOJS_NATIVE_EXIT
}
} // namespace


// setScreenOverlay(descriptor : guiTextureDescriptor) : Boolean
namespace {
static bool GlobalSetScreenOverlay(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_NATIVE_ENTER(context)
	
	bool			result = false;
	ooscript::Value			value = (oojsArgs.count() > 0) ? OOJS_ARGV[0] : ooscript::nullValue();
	
	if (EXPECT_NOT(oojsArgs.count() == 0))
	{
		cxx_OOJSReportWarning(context, "Usage error: %s() called with no arguments. Treating as %s(null). This call may fail in a future version of Oolite.", "setScreenOverlay", "setScreenOverlay");
	}
	else if (EXPECT_NOT(ooscript::isUndefined(value)))
	{
		cxx_OOJSReportBadArguments(context, std::nullopt, "setScreenOverlay", 1, &value, std::nullopt, "GUI texture descriptor");
		return false;
	}
	
	if ((UNIVERSE != nullptr ? UNIVERSE->getViewDirection() : OOViewID{}) == VIEW_GUI_DISPLAY)
	{
		GuiDisplayGen	*gui = (UNIVERSE != nullptr ? UNIVERSE->getGui() : nullptr);
		oo::PList		descriptor = gui->textureDescriptorFromJSValue(value, context, "setScreenOverlay()");
		
		result = gui->setForegroundTextureDescriptor(descriptor);
	}
	
	OOJS_RETURN_BOOL(result);
	
	OOJS_NATIVE_EXIT
}
} // namespace


namespace {
static bool GlobalGetGuiColorSettingForKey(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_NATIVE_ENTER(context)
	
	if (EXPECT_NOT(oojsArgs.count() == 0))
	{
		cxx_OOJSReportBadArguments(context, std::nullopt, "getGuiColorForKey", 0, OOJS_ARGV, std::nullopt, "missing arguments");
		return false;
	}
	std::optional<std::string>	key = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (EXPECT_NOT(!key.has_value() || key->empty()))
	{
		cxx_OOJSReportBadArguments(context, std::nullopt, "getGuiColorForKey", 0, OOJS_ARGV, std::nullopt, "key");
		return false;
	}
	if (key->find("color") == std::string::npos)
	{
		cxx_OOJSReportBadArguments(context, std::nullopt, "getGuiColorForKey", 0, OOJS_ARGV, std::nullopt, "valid color key setting");
		return false;
	}

	GuiDisplayGen	*gui = (UNIVERSE != nullptr ? UNIVERSE->getGui() : nullptr);
	oo::Ref<OOColor>	col = gui->colorFromSetting(key, nil);

	// The components as the colour's -normalizedArray gave them: floats, nil for no colour.
	oo::PList::Array components;
	if (col != nullptr)  for (float component : col->normalizedArray())  components.push_back(oo::PList::singleReal(component));
	OOJS_RETURN_PLIST(col != nullptr ? oo::PList(components) : oo::PList());
	
	OOJS_NATIVE_EXIT
}
} // namespace


// setGuiColorForKey(descriptor : OOColor) : boolean
namespace {
static bool GlobalSetGuiColorSettingForKey(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_NATIVE_ENTER(context)
	
	bool			result = false;
	oo::Ref<OOColor>	col;
	
	if (EXPECT_NOT(oojsArgs.count() != 2))
	{
		cxx_OOJSReportBadArguments(context, std::nullopt, "setGuiColorForKey", 0, OOJS_ARGV, std::nullopt, "missing arguments");
		return false;
	}

	std::optional<std::string>	key = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
	ooscript::Value			value = OOJS_ARGV[1];
	if (EXPECT_NOT(!key.has_value() || key->empty()))
	{
		cxx_OOJSReportBadArguments(context, std::nullopt, "setGuiColorForKey", 0, OOJS_ARGV, std::nullopt, "key");
		return false;
	}
	if (key->find("color") == std::string::npos)
	{
		cxx_OOJSReportBadArguments(context, std::nullopt, "setGuiColorForKey", 0, OOJS_ARGV, std::nullopt, "valid color key setting");
		return false;
	}

	if (!ooscript::isNull(value))
	{
		col = OOColor::colorWithDescription(cxx_OOJSPListFromJSValue(context, value));
		if (col == nullptr)
		{
			cxx_OOJSReportBadArguments(context, std::nullopt, "setGuiColorForKey", 1, OOJS_ARGV, std::nullopt, "color descriptor");
			return false;
		}
	}

	GuiDisplayGen	*gui = (UNIVERSE != nullptr ? UNIVERSE->getGui() : nullptr);
	gui->setGuiColorSettingFromKey(*key, col.get());
	result = true;
	
	OOJS_RETURN_BOOL(result);
	
	OOJS_NATIVE_EXIT
}
} // namespace


#ifndef NDEBUG
// takeSnapShot([name : alphanumeric String]) : Boolean
namespace {
static bool GlobalTakeSnapShot(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_NATIVE_ENTER(context)
	
	std::optional<std::string>	value;
	const oo::str::CharacterSet	alphanumerics = oo::str::CharacterSet::alphanumeric();
	bool					result = false;	
	
	// Allowed: the alphanumeric character set plus "_-", tested per UTF-16 unit as -rangeOfCharacterFromSet: did.
	auto isAllowed = [&alphanumerics](const std::string &name) {
		for (char16_t unit : oo::utf8ToUtf16(name))
		{
			if (unit != u'_' && unit != u'-' && !alphanumerics.contains(unit))  return false;
		}
		return true;
	};
	
	if (oojsArgs.count() > 0)
	{
		value = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
		if (EXPECT_NOT(!value.has_value() || !isAllowed(*value)))
		{
			cxx_OOJSReportBadArguments(context, std::nullopt, "takeSnapShot", oojsArgs.count(), OOJS_ARGV, std::nullopt, "alphanumeric string");
			return false;
		}
	}
	
	const oo::ResourcePaths resourcePaths = oo::ResourcePaths::current();
	const oo::fs::Path savedir = resourcePaths.saveDirectory();
	const oo::fs::FileType saveType = oo::fs::fileType(savedir);
	std::string playerFileDirectory;
	if (saveType == oo::fs::FileType::none)
	{
		if (oo::fs::createDirectories(savedir))
			playerFileDirectory = oo::fs::utf8String(savedir);
		else
			playerFileDirectory = oo::fs::utf8String(resourcePaths.homeDirectory());
	}
	else if (saveType != oo::fs::FileType::directory)
	{
		playerFileDirectory = oo::fs::utf8String(resourcePaths.homeDirectory());
	}
	else
	{
		playerFileDirectory = oo::fs::utf8String(savedir);
	}
	const auto				freeBytes = oo::fs::freeSpace(oo::fs::pathFromUTF8(playerFileDirectory));
	
	if (freeBytes.has_value())
	{
		double freeSpace = static_cast<double>(*freeBytes);
		if (freeSpace < 1073741824) // less than 1 GB free on disk?
		{
			cxx_OOJSReportWarning(context, "takeSnapShot: function disabled when free disk space is less than 1GB.");
			OOJS_RETURN_BOOL(false);
		}
	}
	
	
	OOJS_BEGIN_FULL_NATIVE(context)
	result = (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr ? UNIVERSE->getGameView()->snapShot(value) : false);
	OOJS_END_FULL_NATIVE
	
	OOJS_RETURN_BOOL(result);
	
	OOJS_NATIVE_EXIT
}
} // namespace
#endif

// autoAIForRole(role : String) : String
namespace {
static bool GlobalAutoAIForRole(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_NATIVE_ENTER(context)
	
	std::optional<std::string>	string;
	
	if (oojsArgs.count() > 0)  string = cxx_OOStringFromJSValue(context,OOJS_ARGV[0]);
	if (!string.has_value())
	{
		cxx_OOJSReportBadArguments(context, std::nullopt, "autoAIForRole", MIN(oojsArgs.count(), 1U), OOJS_ARGV, std::nullopt, "string");
		return false;
	}

	const oo::PList autoAIMap = ResourceManager::dictionaryFromFilesNamed("autoAImap.plist", "Config", true);
	std::optional<std::string> autoAI = StringFromPList(autoAIMap.find(*string));

	OOJS_RETURN_STRING_OR_NULL(autoAI);
	
	OOJS_NATIVE_EXIT
}
} // namespace

// pauseGame() : Boolean
namespace {
static bool GlobalPauseGame(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_NATIVE_ENTER(context)
	
	bool			result = false;
	PlayerEntity	*player = PLAYER;
	
	if (player)
	{
		OOGUIScreenID guiScreen = (player != nullptr ? player->guiScreen() : OOGUIScreenID{});
		
		if 	(guiScreen != GUI_SCREEN_LONG_RANGE_CHART &&
			 guiScreen != GUI_SCREEN_MISSION &&
			 guiScreen != GUI_SCREEN_REPORT &&
			 guiScreen != GUI_SCREEN_KEYBOARD_ENTRY &&
			 guiScreen != GUI_SCREEN_SAVE)
		{
			if (UNIVERSE != nullptr)  UNIVERSE->pauseGame();
			result = true;
		}
	}
	
	OOJS_RETURN_BOOL(result);
	
	OOJS_NATIVE_EXIT
}
} // namespace

// quitGame() : Boolean
namespace {
static bool GlobalQuitGame(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_NATIVE_ENTER(context)

	OO_LOG("script.debug.quit", "{}", "Quit requested via JavaScript global.quitGame()");

	if (UNIVERSE != nullptr)  UNIVERSE->quitGame();

	OOJS_RETURN_BOOL(true);

	OOJS_NATIVE_EXIT
}
} // namespace
