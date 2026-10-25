/*

OOJSOolite.h

JavaScript proxy for Oolite (for version checking and similar).


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

#include "OOJSOolite.h"
#include "OOJavaScriptEngine.h"
#include "OOStringParsing.h"
#include "OOJSPlayer.h"
#include "ResourceManager.h"
#include "MyOpenGLView.h"
#include "OOConstToString.h"
#include "oofnd/PListParsing.hpp"
#include "oofnd/FileSystem.hpp"
#include "oofnd/ResourcePaths.hpp"

#include "ooscript/JSEngine.hpp"
#include <cstring>
#include "oofnd/String.hpp"

namespace {

// Info-gnustep.plist string (CFBundleVersion / CFBundleName as the Override category used to expose).
std::optional<std::string> OoliteInfoString(std::string_view key)
{
	const oo::fs::Path plistPath = oo::ResourcePaths::current().builtInResourcesDirectory() / "Info-gnustep.plist";
	oo::PList info;
	if (const oo::fs::Result<oo::Data> bytes = oo::fs::readFile(plistPath); bytes && !bytes->empty())
	{
		if (oo::Expected<oo::PList, oo::PListError> parsed = oo::parsePropertyList(bytes->stringView());
		    parsed && parsed->isDict())
			info = std::move(*parsed);
	}
	if (const oo::PList *v = info.find(key); v != nullptr && v->isString())
		return *v->getIf<std::string>();
	return std::nullopt;
}

}  // namespace


// Retargeted onto the ooscript facade (JSEngine.hpp), the way OOJSWormhole.mm and
// OOJSClock.mm do it (bead oo-sdz exemplar): the class dispatch table becomes a static
// ooscript::ClassDef (stub hooks become nullptr), InitClass becomes ooscript::initClass,
// numeric conversion becomes ooscript::newNumberValue/ooscript::valueToNumber, and `this` is
// renamed to `thisObj` (reserved word in Objective-C++, ADR-0001).
/*
	C++20 since bead oo-whvg, converted the way bead oo-ppc converted OOJSVector.mm (proposed
	ADR-0056 amendment oo-ppc). The JS class was already C++ on the ooscript façade;
	OOJS_NATIVE_ENTER/EXIT and OOJS_PROFILE_ENTER/EXIT are C++ try/catch and scope guards
	(OOJSEngineNativeWrappers.h); BOOL/YES/NO are bool/true/false. Nothing else in the file was
	Objective-C: the universe, its game view and the resource manager, which are not converted, are
	still messaged, which is why the file is still .mm until Phase 4.
*/

namespace ooscript { }
using ooscript::Context;
using ooscript::Object;
using ooscript::Value;
using ooscript::PropertyId;
using ooscript::ClassDef;
using ooscript::ClassFlag;
using ooscript::PropertyFlag;
using ooscript::PropertySpec;
using ooscript::FunctionSpec;
using ooscript::CallArgs;

namespace {
static bool OoliteGetProperty(Context cx, Object obj, PropertyId propID, Value *value);
} // namespace
namespace {
static bool OoliteSetProperty(Context cx, Object obj, PropertyId propID, bool strict, Value *value);
} // namespace

namespace {
static std::optional<std::string> VersionString(void);
} // namespace
namespace {
static std::vector<unsigned> VersionComponents(void);
static unsigned UnsignedIntValue(const oo::PList &number);
} // namespace

namespace {
static bool OoliteCompareVersion(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace



namespace {
static ClassDef sOoliteClass =
{
	"Oolite",
	ClassFlag::None,
	
	nullptr,		// addProperty (engine default: PropertyStub)
	nullptr,		// delProperty (engine default: PropertyStub)
	OoliteGetProperty,		// getProperty
	OoliteSetProperty,		// setProperty
	nullptr,		// enumerate (engine default: EnumerateStub)
	nullptr,			// newEnumerate (ooscript::ClassFlag::NewEnumerate not used)
	nullptr,			// resolve (engine default: ResolveStub)
	nullptr,			// convert (engine default: ConvertStub)
	nullptr,			// finalize (engine default: FinalizeStub)
	nullptr,			// call
	nullptr,			// construct
	nullptr,			// backend: owned by the facade backend, must start null
};
} // namespace


enum : std::uint8_t
{
	// Property IDs
	kOolite_version,			// version number components, array, read-only
	kOolite_versionString,		// version number as string, string, read-only
	kOolite_jsVersion,			// JavaScript version, integer, read-only
	kOolite_jsVersionString,	// JavaScript version as string, string, read-only
	kOolite_gameSettings,		// Various game settings, object, read-only
	kOolite_resourcePaths,		// Paths containing resources, built-in plus oxp/oxz, read-only
	kOolite_colorSaturation,	// Color saturation, integer, read/write
	kOolite_postFX,				// current post processing effect, integer, read/write
	kOolite_hdrToneMapper,		// currently active HDR tone mapper, string, read/write
	kOolite_sdrToneMapper,		// currently active SDR tone mapper, string, read/write
#ifndef NDEBUG
	kOolite_timeAccelerationFactor,	// time acceleration, float, read/write
#endif
};


namespace {
constexpr PropertyFlag kOolitePropertyFlagsRO = PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Shared;
constexpr PropertyFlag kOolitePropertyFlagsRW = PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared;
} // namespace


namespace {
static PropertySpec sOoliteProperties[] =
{
	// JS name					ID							flags						getter	setter
	{ "gameSettings",			kOolite_gameSettings,		kOolitePropertyFlagsRO, nullptr, nullptr },
	{ "jsVersion",				kOolite_jsVersion,			kOolitePropertyFlagsRO, nullptr, nullptr },
	{ "jsVersionString",		kOolite_jsVersionString,	kOolitePropertyFlagsRO, nullptr, nullptr },
	{ "version",				kOolite_version,			kOolitePropertyFlagsRO, nullptr, nullptr },
	{ "versionString",			kOolite_versionString,		kOolitePropertyFlagsRO, nullptr, nullptr },
	{ "resourcePaths",			kOolite_resourcePaths,		kOolitePropertyFlagsRO, nullptr, nullptr },
	{ "colorSaturation",		kOolite_colorSaturation,	kOolitePropertyFlagsRW, nullptr, nullptr },
	{ "postFX",					kOolite_postFX,				kOolitePropertyFlagsRW, nullptr, nullptr },
	{ "hdrToneMapper",			kOolite_hdrToneMapper, 		kOolitePropertyFlagsRW, nullptr, nullptr },
	{ "sdrToneMapper",			kOolite_sdrToneMapper, 		kOolitePropertyFlagsRW, nullptr, nullptr },
#ifndef NDEBUG
	{ "timeAccelerationFactor",	kOolite_timeAccelerationFactor,	kOolitePropertyFlagsRW, nullptr, nullptr },
#endif
	{ 0 }
};
} // namespace


// Mirror of sOoliteProperties with the read-only/read-write flags the shared error reporters
// describe the properties by (see OOJSVector.mm's sVectorPropertiesRaw).
namespace {
static ooscript::PropertySpec sOolitePropertiesRaw[] =
{
	// JS name					ID							flags
	{ "gameSettings",			kOolite_gameSettings,		OOJS_PROP_READONLY_CB },
	{ "jsVersion",				kOolite_jsVersion,			OOJS_PROP_READONLY_CB },
	{ "jsVersionString",		kOolite_jsVersionString,	OOJS_PROP_READONLY_CB },
	{ "version",				kOolite_version,			OOJS_PROP_READONLY_CB },
	{ "versionString",			kOolite_versionString,		OOJS_PROP_READONLY_CB },
	{ "resourcePaths",			kOolite_resourcePaths,		OOJS_PROP_READONLY_CB },
	{ "colorSaturation",		kOolite_colorSaturation,	OOJS_PROP_READWRITE_CB },
	{ "postFX",					kOolite_postFX,				OOJS_PROP_READWRITE_CB },
	{ "hdrToneMapper",			kOolite_hdrToneMapper, 		OOJS_PROP_READWRITE_CB },
	{ "sdrToneMapper",			kOolite_sdrToneMapper, 		OOJS_PROP_READWRITE_CB },
#ifndef NDEBUG
	{ "timeAccelerationFactor",	kOolite_timeAccelerationFactor,	OOJS_PROP_READWRITE_CB },
#endif
	{ 0 }
};
} // namespace


namespace {
static FunctionSpec sOoliteMethods[] =
{
	// JS name					Function					min args
	{ "compareVersion",			OoliteCompareVersion,		1 },
	{ 0 }
};
} // namespace


namespace {
constexpr PropertyFlag kOoliteObjectFlags = PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly;
} // namespace


void InitOOJSOolite(ooscript::Context context, ooscript::Object global)
{
	Object oolitePrototype = ooscript::initClass((context), (global), nullptr, &sOoliteClass, OOJSUnconstructableConstruct, 0, sOoliteProperties, sOoliteMethods, nullptr, nullptr);
	ooscript::defineObject((context), (global), "oolite", &sOoliteClass, oolitePrototype, kOoliteObjectFlags);
}


namespace {
static bool OoliteGetProperty(Context cx, Object obj, PropertyId propID, Value *value)
{
	if (!ooscript::isInt32Id(propID))  return true;
	
	ooscript::Context context = (cx);
	ooscript::Object thisObj = (obj);
	ooscript::Value *value_raw = value;
	
	OOJS_NATIVE_ENTER(context)
	
	oo::PList				result;	// null: nil
	MyOpenGLView			*gameView = (UNIVERSE != nullptr ? UNIVERSE->getGameView() : nullptr);
	
	switch (ooscript::idToInt32(propID))
	{
		case kOolite_version:
		{
			// The components as ComponentsFromVersionString() gave them: an array of unsigned numbers.
			oo::PList::Array components;
			for (unsigned component : VersionComponents())  components.push_back(oo::PList::unsignedInteger(component));
			result = oo::PList(std::move(components));
			break;
		}
		
		case kOolite_versionString:
		{
			const std::optional<std::string> version = VersionString();
			if (version.has_value())  result = oo::PList(*version);
			break;
		}
		
		case kOolite_jsVersion:
			*value_raw = ooscript::int32Value(static_cast<int>(ooscript::getVersion(cx)));
			return true;
		
		case kOolite_jsVersionString:
			*value_raw = ooscript::stringValue((ooscript::newStringCopyZ(cx, ooscript::versionToString(ooscript::getVersion(cx)))));
			return true;
		
		case kOolite_gameSettings:
			result = (UNIVERSE != nullptr ? UNIVERSE->gameSettings() : oo::PList());
			break;
			
		case kOolite_resourcePaths:
			// user name in displayed paths masked for privacy - remember that the console can be run remotely too
		{
			oo::PList::Array paths;
			for (const std::string &path : ResourceManager::maskUserNameInPathArray(ResourceManager::paths()))  paths.push_back(oo::PList(path));
			result = oo::PList(std::move(paths));
			break;
		}
			
		case kOolite_colorSaturation:
			return ooscript::newNumberValue(cx, (gameView != nullptr ? gameView->colorSaturation() : 0.0f), value);
			
		case kOolite_postFX:
			*value_raw = ooscript::int32Value((UNIVERSE != nullptr ? UNIVERSE->currentPostFX() : 0));
			return true;
			
		case kOolite_hdrToneMapper:
		{
			std::optional<std::string> toneMapperStr = "OOHDR_TONEMAPPER_UNDEFINED";
#if OOLITE_WINDOWS
			if ((gameView != nullptr ? gameView->hdrOutput() : false))
			{
				toneMapperStr = cxx_OOStringFromHDRToneMapper((gameView != nullptr ? gameView->hdrToneMapper() : OOHDRToneMapper{}));
			}
#endif
			if (toneMapperStr.has_value())  result = oo::PList(*toneMapperStr);
			break;
		}
		
		case kOolite_sdrToneMapper:
		{
			std::optional<std::string> toneMapperStr = "OOSDR_TONEMAPPER_UNDEFINED";
			if (!(gameView != nullptr ? gameView->hdrOutput() : false))
			{
				toneMapperStr = cxx_OOStringFromSDRToneMapper((gameView != nullptr ? gameView->sdrToneMapper() : OOSDRToneMapper{}));
			}
			if (toneMapperStr.has_value())  result = oo::PList(*toneMapperStr);
			break;
		}
			
#ifndef NDEBUG
		case kOolite_timeAccelerationFactor:
			return ooscript::newNumberValue(cx, (UNIVERSE != nullptr ? UNIVERSE->getTimeAccelerationFactor() : 0.0), value);
#endif
		
		default:
			OOJSReportBadPropertySelector(context, thisObj, (propID), sOolitePropertiesRaw);
			return false;
	}
	
	*value_raw = OOJSValueFromPList(context, result);
	return true;
	
	OOJS_NATIVE_EXIT
}
} // namespace


namespace {
static bool OoliteSetProperty(Context cx, Object obj, PropertyId propID, bool /*strict*/, Value *value)
{
	if (!ooscript::isInt32Id(propID))  return true;
	
	ooscript::Context context = (cx);
	ooscript::Object thisObj = (obj);
	ooscript::Value *value_raw = value;
	
	OOJS_NATIVE_ENTER(context)
	
	double					fValue;
	int32_t					iValue;
	std::optional<std::string>	sValue;
	MyOpenGLView 			*gameView = (UNIVERSE != nullptr ? UNIVERSE->getGameView() : nullptr);
	
	switch (ooscript::idToInt32(propID))
	{
		case kOolite_colorSaturation:
			if (ooscript::valueToNumber(cx, *value, &fValue))
			{
				float currentColorSaturation = (gameView != nullptr ? gameView->colorSaturation() : 0.0f);
				if (gameView != nullptr)  gameView->adjustColorSaturation(fValue - currentColorSaturation);
				return true;
			}
			break;
			
		case kOolite_postFX:
			if (ooscript::valueToInt32(cx, *value, &iValue))
			{
				iValue = MAX(iValue, 0);
				if (UNIVERSE != nullptr)  UNIVERSE->setCurrentPostFX(iValue);
				return true;
			}
			break;
			
		case kOolite_hdrToneMapper:
			if (!ooscript::isString(*value_raw))  break; // non-string is not allowed
			sValue = cxx_OOStringFromJSValue(context,*value_raw);
			if (sValue.has_value())
			{
#if OOLITE_WINDOWS
				if ((gameView != nullptr ? gameView->hdrOutput() : false))  { if (gameView != nullptr)  gameView->setHDRToneMapper(cxx_OOHDRToneMapperFromString(*sValue)); }
				else  cxx_OOJSReportWarning(context, "hdrToneMapper cannot be set if not running in HDR mode");
#endif
				return true;
			}
			break;
			
		case kOolite_sdrToneMapper:
			if (!ooscript::isString(*value_raw))  break; // non-string is not allowed
			sValue = cxx_OOStringFromJSValue(context,*value_raw);
			if (sValue.has_value())
			{
				if (!(gameView != nullptr ? gameView->hdrOutput() : false))  { if (gameView != nullptr)  gameView->setSDRToneMapper(cxx_OOSDRToneMapperFromString(*sValue)); }
				else  cxx_OOJSReportWarning(context, "sdrToneMapper cannot be set if not running in SDR mode");
				return true;
			}
			break;
			
#ifndef NDEBUG
		case kOolite_timeAccelerationFactor:
			if (ooscript::valueToNumber(cx, *value, &fValue))
			{
				if (UNIVERSE != nullptr)  UNIVERSE->setTimeAccelerationFactor(fValue);
				return true;
			}
			break;
#endif
			
		default:
			OOJSReportBadPropertySelector(context, thisObj, (propID), sOolitePropertiesRaw);
			return false;
	}
	
	OOJSReportBadPropertyValue(context, thisObj, (propID), sOolitePropertiesRaw, *value_raw);
	return false;
	
	OOJS_NATIVE_EXIT
}
} // namespace


namespace {
static std::optional<std::string> VersionString(void)
{
	return OoliteInfoString("CFBundleVersion");
}
} // namespace


namespace {
static std::vector<unsigned> VersionComponents(void)
{
	const std::optional<std::string> version = VersionString();
	if (!version.has_value())  return {};	// ComponentsFromVersionString(nil) was empty
	return oo::str::versionComponents(*version);
}


// A JavaScript number's -unsignedIntValue, as CompareVersions() read it: C conversions.
static unsigned UnsignedIntValue(const oo::PList &number)
{
	if (const bool *boolean = number.getIf<bool>())  return *boolean ? 1u : 0u;
	if (const oo::PList::Integer *integer = number.getIf<oo::PList::Integer>())  return static_cast<unsigned>(integer->value);
	return static_cast<unsigned>(*number.getIf<double>());
}
} // namespace


/*	oolite.compareVersion(versionSpec) : Number
	returns -1 if the current version of Oolite is less than versionSpec, 0 if
	they are equal, and 1 if the current version is newer. versionSpec may be
	a string or an array. Example:
	if (0 < oolite.compareVersion("1.70"))  log("Old version of Oolite!")
	else  this.doStuffThatRequires170()
*/
namespace {
static bool OoliteCompareVersion(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_NATIVE_ENTER(context)
	
	oo::PList				components;
	std::optional<std::vector<unsigned>>	versionSpec;
	
	if (oojsArgs.count() == 0)  OOJS_RETURN_VOID;	// Backwards-compatibility: be overly lenient.
	
	components = cxx_OOJSPListFromJSValue(context, OOJS_ARGV[0]);
	if (const oo::PList::Array *componentArray = components.getIf<oo::PList::Array>())
	{
		// Require each element to be a number
		std::vector<unsigned> numbers;
		bool allNumbers = true;
		for (const oo::PList &component : *componentArray)
		{
			if (!component.isNumber())
			{
				allNumbers = false;
				break;
			}
			numbers.push_back(UnsignedIntValue(component));
		}
		if (allNumbers)  versionSpec = std::move(numbers);
	}
	else if (const std::string *componentString = components.getIf<std::string>())
	{
		versionSpec = oo::str::versionComponents(*componentString);
	}
	
	if (versionSpec.has_value())
	{
		OOJS_RETURN_INT((int32_t)oo::str::compareVersions(*versionSpec, VersionComponents()));
	}
	else
	{
		OOJS_RETURN_VOID;
	}
	
	OOJS_NATIVE_EXIT
}
} // namespace
