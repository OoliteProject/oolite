/*

OOJSManifest.m

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

#include "OOJSManifest.h"
#include "OOJavaScriptEngine.h"
#include "PlayerEntity.h"
#include "PlayerEntityScriptMethods.h"
#include "PlayerEntityContracts.h"
#include "Universe.h"
#include "OOCommodities.h"
#include "OOCommodityMarket.h"
#include "OOJSPlayer.h"
#include "OOJSPlayerShip.h"
#include "OOIsNumberLiteral.h"

#include "ooscript/JSEngine.hpp"
#include <cstring>

/*
	Retargeted onto the ooscript façade (JSEngine.hpp) the way OOJSVector.mm does it (bead
	oo-sdz, the sweep exemplar; see also OOJSClock.mm/OOJSMissionVariables.mm): the class
	dispatch table becomes a static ooscript::ClassDef (the stub hook is nullptr), the
	class-creation call becomes ooscript::initClass, the two class-as-property registrations
	become ooscript::defineObject, and the directly spelled numeric-conversion call becomes
	ooscript::valueToInt32. `this` is renamed to `thisObj` because it is a reserved word once
	this file compiles as Objective-C++ (ADR-0001). The class hooks (deleteProperty,
	getProperty, setProperty) take the façade's Context/Object/PropertyId/Value signature
	directly, and the shared OOJSObjectWrapperFinalize is the class's finalize hook. The manual
	object construction in oo_jsValueInContext: (the engine's NewObject/SetPrivate) is
	retargeted the same way JSVectorWithVector() retargets it in OOJSVector.mm.
*/
/*
	C++20 since bead oo-7nfv, converted the way bead oo-ppc converted OOJSVector.mm (proposed
	ADR-0056 amendment oo-ppc). The JS class was already C++ on the ooscript façade;
	OOJS_NATIVE_ENTER/EXIT and OOJS_PROFILE_ENTER/EXIT are C++ try/catch and scope guards
	(OOJSEngineNativeWrappers.h); BOOL/YES/NO are bool/true/false. OOManifest, a helper class that
	nothing made, is gone (see where it stood). OOCommodities and OOCommodityMarket, which are C++
	since beads oo-fqyw and oo-ih7y, are reached as cxx:: classes through oo::ToCxx (amendment
	oo-ppc, item 4), null-guarded where a message to nil answered. Messages to classes that are
	still Objective-C (PlayerEntity, Universe) stay as they are, which is why the file is still .mm
	until Phase 4.
*/

namespace ooscript { }
using ooscript::Context;
using ooscript::Object;
using ooscript::Value;
using ooscript::PropertyId;
using ooscript::ClassDef;
using ooscript::ClassFlag;
using ooscript::PropertyFlag;
using ooscript::CallArgs;
using ooscript::PropertySpec;
using ooscript::FunctionSpec;


namespace {
static ooscript::Object sManifestPrototype;
} // namespace
namespace {
static ooscript::Object sManifestObject;
} // namespace


namespace {
static bool ManifestComment(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace
namespace {
static bool ManifestSetComment(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace
namespace {
static bool ManifestShortComment(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace
namespace {
static bool ManifestSetShortComment(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace


namespace {
static bool ManifestDeleteProperty(Context cx, Object obj, PropertyId propID, Value * /*value*/);
} // namespace
namespace {
static bool ManifestGetProperty(Context cx, Object obj, PropertyId propID, Value *value);
} // namespace
namespace {
static bool ManifestSetProperty(Context cx, Object obj, PropertyId propID, bool /*strict*/, Value *value);
} // namespace

namespace {
static ClassDef sManifestClass =
{
	"Manifest",
	ClassFlag::HasPrivate,

	nullptr,				// addProperty (engine default: PropertyStub)
	ManifestDeleteProperty,	// delProperty
	ManifestGetProperty,	// getProperty
	ManifestSetProperty,	// setProperty
	nullptr,				// enumerate (engine default: EnumerateStub)
	nullptr,				// newEnumerate (ooscript::ClassFlag::NewEnumerate not used)
	nullptr,				// resolve (engine default: ResolveStub)
	nullptr,				// convert (engine default: ConvertStub)
	OOJSObjectWrapperFinalize,		// finalize
	nullptr,				// call
	nullptr,				// construct
	nullptr,				// backend: owned by the façade backend, must start null
};
} // namespace


enum : std::uint8_t
{
	kManifest_list				// manifest list, array of commodities: name, unit, quantity, displayName - read-only	
};


namespace {
static PropertySpec sManifestProperties[] =
{
	// JS name					ID							flags					getter	setter
	{ "list",				kManifest_list,				PropertyFlag::ReadOnly | PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared,	nullptr, nullptr },
	{ 0 }
};
} // namespace


namespace {
static FunctionSpec sManifestMethods[] =
{
	// JS name					Function					min args	flags
	{ "shortComment",			ManifestShortComment,			1,		0 },
	{ "setShortComment",		ManifestSetShortComment,		2,		0 },
	{ "comment",				ManifestComment,				1,		0 },
	{ "setComment",				ManifestSetComment,			2,		0 },
	{ 0 }
};
} // namespace


// OOManifest, the helper class "wrapped by JS Manifest objects", is gone (bead oo-7nfv): nothing
// made one. Both Manifest objects are defined with no private object (InitOOJSManifest), and no
// other file names the class, so its -oo_jsValueInContext: and -cxx_oo_jsClassName were never sent.


void InitOOJSManifest(ooscript::Context context, ooscript::Object global)
{
	Object proto = ooscript::initClass((context), (global), nullptr, &sManifestClass, OOJSUnconstructableConstruct, 0, sManifestProperties, sManifestMethods, nullptr, nullptr);
	sManifestPrototype = (proto);
	
	// Create manifest object as a property of the player.ship object.
	Object manifestObj = ooscript::defineObject((context), (JSPlayerShipObject()), "manifest", &sManifestClass, proto, OOJS_PROP_READONLY);
	sManifestObject = (manifestObj);
	ooscript::setPrivate((context), manifestObj, NULL);
	
	// Also define manifest object as a property of the global object.
	// Wait, what? Why? Oh well, too late now. Deprecate for EMMSTRAN? -- Ahruman 2011-02-10
	ooscript::defineObject((context), (global), "manifest", &sManifestClass, proto, OOJS_PROP_READONLY);
	
}


namespace {
static bool ManifestDeleteProperty(Context cx, Object obj, PropertyId propID, Value * /*value*/)
{
	ooscript::Value v = ooscript::undefinedValue();
	return ManifestSetProperty(cx, obj, propID, false, &v);
}
} // namespace


namespace {
static bool ManifestGetProperty(Context cx, Object obj, PropertyId propID, Value *value)
{
	ooscript::Context context = (cx);
	ooscript::Object thisObj = (obj);
	
	OOJS_NATIVE_ENTER(context)
	
	oo::PList					result;	// null: nil
	PlayerEntity				*entity = OOPlayerForScripting();
	
	if (ooscript::isInt32Id(propID))
	{
		switch (ooscript::idToInt32(propID))
		{
			case kManifest_list:
				result = (entity != nullptr ? entity->PlayerEntity::cargoListForScripting() : oo::PList());	// qualified: the final overrider (bead oo-9ht.177), so the binding test stands in for it
				break;
				
			default:
				OOJSReportBadPropertySelector(context, thisObj, propID, sManifestProperties);
				return false;
		}
	}
	else if (ooscript::isStringId(propID))
	{
		/* 'list' property is hard-coded
		 * others map to the commodity keys in trade-goods.plist
		 * compatible-ish with 1.80 and earlier except that
		 * alienItems and similar aliases don't work */
		std::string key = cxx_OOStringFromJSString(context, ooscript::idToString(propID)).value_or(std::string());
		OOCommodities *commodities = (UNIVERSE != nullptr ? UNIVERSE->getCommodities() : nullptr);	// null: no good is defined, as a message to nil
		if (commodities != nullptr && commodities->goodDefined(key))
		{
			*value = ooscript::int32Value((entity != nullptr ? entity->cargoQuantityForType(key) : 0));
			return true;
		}
		else
		{
			return true;
		}
	}
	
	*value = OOJSValueFromPList(context, result);
	return true;
	
	OOJS_NATIVE_EXIT
}
} // namespace


namespace {
static bool ManifestSetProperty(Context cx, Object obj, PropertyId propID, bool /*strict*/, Value *value)
{
	ooscript::Context context = (cx);
	ooscript::Object thisObj = (obj);
	
	OOJS_NATIVE_ENTER(context)
	
	PlayerEntity				*entity = OOPlayerForScripting();
	int32_t						iValue;
	
	if (ooscript::isStringId(propID))
	{
		std::string key = cxx_OOStringFromJSString(context, ooscript::idToString(propID)).value_or(std::string());

		OOCommodityMarket *market = (UNIVERSE != nullptr ? UNIVERSE->getCommodityMarket() : nullptr);
		OOMassUnit unit = (market != nullptr) ? market->massUnitForGood(key) : UNITS_TONS;	// UNITS_TONS (0): what a message to nil answered
		// we can always change gold, platinum & gem-stones quantities, even with special cargo
		if (unit == UNITS_TONS && (entity != nullptr ? entity->PlayerEntity::getSpecialCargo() : std::optional<std::string>()).has_value())	// qualified: the final overrider (bead oo-9ht.177), so the binding test stands in for it
		{
			cxx_OOJSReportWarning(context, "PlayerShip.manifest['foo'] - cannot modify cargo tonnage when Special Cargo is in use.");
			return true;
		}
	
		std::int32_t iValue32 = 0;
		if (ooscript::valueToInt32(cx, *value, &iValue32))
		{
			iValue = (int32_t)iValue32;
			if (iValue < 0)  iValue = 0;
			if (entity != nullptr)  entity->setCargoQuantityForType(key, iValue);
		}
		else
		{
			OOJSReportBadPropertyValue(context, thisObj, propID, sManifestProperties, *value);
		}
	}
	return true;
	
	OOJS_NATIVE_EXIT
}
} // namespace


// comment(good : String) : String
namespace {
static bool ManifestComment(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{

	OOJS_NATIVE_ENTER(context)

	std::optional<std::string>	good;
	std::optional<std::string>	information;

	if (oojsArgs.count() > 0)
	{
		good = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
	}
	if (!good.has_value())
	{
		cxx_OOJSReportBadArguments(context, "Manifest", "comment", MIN(oojsArgs.count(), 1U), OOJS_ARGV, std::nullopt, "good");
		return false;
	}

	OOCommodityMarket *market = (PLAYER != nullptr ? PLAYER->getShipCommodityData() : (OOCommodityMarket *)nullptr);	// null: no comment, as a message to nil
	if (market != nullptr)  information = market->commentForGood(*good);

	OOJS_RETURN_STRING_OR_NULL(information);
	
	OOJS_NATIVE_EXIT
}
} // namespace


// setComment(good : String, information : String) : Boolean
namespace {
static bool ManifestSetComment(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{

	OOJS_NATIVE_ENTER(context)

	bool 			OK;
	std::optional<std::string>	good;
	std::optional<std::string>	information;

	if (oojsArgs.count() > 1)
	{
		good = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
		information = cxx_OOStringFromJSValue(context, OOJS_ARGV[1]);
	}
	if (!good.has_value() || !information.has_value())
	{
		cxx_OOJSReportBadArguments(context, "Manifest", "setComment", MIN(oojsArgs.count(), 2U), OOJS_ARGV, std::nullopt, "good and information text");
		return false;
	}

	OOCommodityMarket *market = (PLAYER != nullptr ? PLAYER->getShipCommodityData() : (OOCommodityMarket *)nullptr);	// null: false, as a message to nil
	OK = market != nullptr && market->setComment(*information, *good);

	OOJS_RETURN_BOOL(OK);
	
	OOJS_NATIVE_EXIT
}
} // namespace


// shortComment(good : String) : String
namespace {
static bool ManifestShortComment(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{

	OOJS_NATIVE_ENTER(context)

	std::optional<std::string>	good;
	std::optional<std::string>	information;

	if (oojsArgs.count() > 0)
	{
		good = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
	}
	if (!good.has_value())
	{
		cxx_OOJSReportBadArguments(context, "Manifest", "shortComment", MIN(oojsArgs.count(), 1U), OOJS_ARGV, std::nullopt, "good");
		return false;
	}

	OOCommodityMarket *market = (PLAYER != nullptr ? PLAYER->getShipCommodityData() : (OOCommodityMarket *)nullptr);	// null: no comment, as a message to nil
	if (market != nullptr)  information = market->shortCommentForGood(*good);

	OOJS_RETURN_STRING_OR_NULL(information);
	
	OOJS_NATIVE_EXIT
}
} // namespace


// setShortComment(good : String, information : String) : Boolean
namespace {
static bool ManifestSetShortComment(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{

	OOJS_NATIVE_ENTER(context)

	bool 			OK;
	std::optional<std::string>	good;
	std::optional<std::string>	information;

	if (oojsArgs.count() > 1)
	{
		good = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
		information = cxx_OOStringFromJSValue(context, OOJS_ARGV[1]);
	}
	if (!good.has_value() || !information.has_value())
	{
		cxx_OOJSReportBadArguments(context, "Manifest", "setShortComment", MIN(oojsArgs.count(), 2U), OOJS_ARGV, std::nullopt, "good and information text");
		return false;
	}

	OOCommodityMarket *market = (PLAYER != nullptr ? PLAYER->getShipCommodityData() : (OOCommodityMarket *)nullptr);	// null: false, as a message to nil
	OK = market != nullptr && market->setShortComment(*information, *good);

	OOJS_RETURN_BOOL(OK);
	
	OOJS_NATIVE_EXIT
}
} // namespace
