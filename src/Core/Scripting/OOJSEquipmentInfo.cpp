/*

OOJSEquipmentInfo.mm


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

#include "OOJSEquipmentInfo.h"
#include "OOJavaScriptEngine.h"
#include "OOEquipmentType.h"
#include "OOJSPlayer.h"
#include "OODebugStandards.h"

#include "ooscript/JSEngine.hpp"
#include <cstring>
#include "OOObjCPList.h"
#include "oofnd/String.hpp"

/*
	Retargeted onto the ooscript façade (JSEngine.hpp) the way OOJSVector.mm does it (bead
	oo-sdz, the sweep exemplar): the class dispatch table becomes a static ooscript::ClassDef
	(the stub hooks are nullptr), InitClass becomes ooscript::initClass, and the directly
	spelled instance-check, private-storage, object-construction and numeric/integer-conversion
	calls become ooscript::instanceOf / ooscript::getPrivate / ooscript::setPrivate /
	ooscript::newObject / ooscript::newNumberValue / ooscript::valueToInt32. `this` is renamed
	to `thisObj` because it is a reserved word once this file compiles as Objective-C++
	(ADR-0001). Natives take the façade signature directly; the OOJS_* argument-marshalling
	macros (OOJS_NATIVE_ENTER, OOJS_ARGV, OOJS_RETURN_*) expand to the CallArgs accessors.
*/
/*
	C++20 since bead oo-supk, converted the way bead oo-ppc converted OOJSVector.mm (proposed
	ADR-0056 amendment oo-ppc). The JS class was already C++ on the ooscript façade;
	OOJS_NATIVE_ENTER/EXIT and OOJS_PROFILE_ENTER/EXIT are C++ try/catch and scope guards
	(OOJSEngineNativeWrappers.h); BOOL/YES/NO are bool/true/false. OOEquipmentType
	(OOJavaScriptExtensions), the category on the converted class's façade that owns its _jsSelf
	ivar, became three free functions that take the façade's ivar by reference, and its methods
	moved to the façade (OOEquipmentType+ObjCBridge.mm; amendment oo-6ia4 item 3, bead oo-9ht.102). OOEquipmentType and
	OOColor, which are C++ since beads oo-fg7i and oo-11m, are reached as cxx:: classes through
	oo::ToCxx/oo::ToObjC (amendment oo-ppc, item 4); the property hooks cross once, and Ask()
	answers what a message to nil answered for the prototype, which has no type.
	JSValueToEquipmentType() still answers the façade, and JSValueToEquipmentKeyRelaxed()'s
	out-parameter stays BOOL *, so their callers compile unchanged. Messages to classes that are
	still Objective-C (PlayerEntity) stay as they are, which is why the file is still .mm until
	Phase 4.
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
static ooscript::Object sEquipmentInfoPrototype;
} // namespace


namespace {

namespace {

// A colour's components as its -normalizedArray gave them to JavaScript: floats, null for no colour.
oo::PList NormalizedColorComponents(OOColor *color)
{
	if (color == nullptr)  return oo::PList();
	oo::PList::Array components;
	for (float component : color->normalizedArray())  components.push_back(oo::PList::singleReal(component));
	return oo::PList(std::move(components));
}


// What the type answers, or what a message to nil answered (0, false, nullopt, null, an empty
// list) when there is no type: the prototype's case (amendment oo-6ia4 item 2).
template <typename Result>
Result Ask(OOEquipmentType *type, Result (OOEquipmentType::*member)())
{
	return type != nullptr ? (type->*member)() : Result{};
}

// A string, or null for none (what a Foundation string or nil gave JavaScript).
oo::PList StringOrNull(const std::optional<std::string> &string)
{
	return string.has_value() ? oo::PList(*string) : oo::PList();
}

// Equipment keys as an array of strings; null for none. They are sorted and unique already, so
// this is the set they were, in key order (the Foundation set's -allObjects gave hash order).
oo::PList KeyArrayOrNull(const std::optional<std::vector<std::string>> &keys)
{
	if (!keys.has_value())  return oo::PList();
	return oo::PList(oo::PList::Array(keys->begin(), keys->end()));
}

}	// namespace


static bool EquipmentInfoGetProperty(Context cx, Object obj, PropertyId propID, Value *value);
} // namespace
namespace {
static bool EquipmentInfoSetProperty(Context cx, Object obj, PropertyId propID, bool strict, Value *value);
} // namespace

namespace {
static bool EquipmentInfoGetAllEqipment(Context cx, Object /*obj*/, PropertyId /*propID*/, Value *value);
} // namespace


// Methods
namespace {
static bool EquipmentInfoStaticInfoForKey(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace



enum : std::uint8_t
{
	// Property IDs
	kEquipmentInfo_calculatedPrice,
	kEquipmentInfo_canBeDamaged,
	kEquipmentInfo_canCarryMultiple,
	kEquipmentInfo_damageProbability,
	kEquipmentInfo_description,
	kEquipmentInfo_displayColor,
	kEquipmentInfo_effectiveTechLevel,
	kEquipmentInfo_equipmentKey,
	kEquipmentInfo_fastAffinityDefensive,
	kEquipmentInfo_fastAffinityOffensive,
	kEquipmentInfo_defaultActivateKey,
	kEquipmentInfo_defaultModeKey,
	kEquipmentInfo_incompatibleEquipment,
	kEquipmentInfo_installationTime,
	kEquipmentInfo_isAvailableToAll,
	kEquipmentInfo_isAvailableToNPCs,
	kEquipmentInfo_isAvailableToPlayer,
	kEquipmentInfo_isExternalStore,				// is missile or mine
	kEquipmentInfo_isPortableBetweenShips,
	kEquipmentInfo_isVisible,
	kEquipmentInfo_name,
	kEquipmentInfo_price,
	kEquipmentInfo_provides,
	kEquipmentInfo_repairTime,
	kEquipmentInfo_requiredCargoSpace,
	kEquipmentInfo_requiresAnyEquipment,
	kEquipmentInfo_requiresCleanLegalRecord,
	kEquipmentInfo_requiresEmptyPylon,
	kEquipmentInfo_requiresEquipment,
	kEquipmentInfo_requiresFreePassengerBerth,
	kEquipmentInfo_requiresFullFuel,
	kEquipmentInfo_requiresMountedPylon,
	kEquipmentInfo_requiresNonCleanLegalRecord,
	kEquipmentInfo_requiresNonFullFuel,
	kEquipmentInfo_scriptInfo,					// arbitrary data for scripts, dictionary, read-only
	kEquipmentInfo_scriptName,
	kEquipmentInfo_techLevel,
	kEquipmentInfo_weaponInfo
};


namespace {
constexpr PropertyFlag kEquipmentInfoPropertyFlags = PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared;
} // namespace
namespace {
constexpr PropertyFlag kEquipmentInfoPropertyFlagsReadOnly = kEquipmentInfoPropertyFlags | PropertyFlag::ReadOnly;
} // namespace


namespace {
static PropertySpec sEquipmentInfoProperties[] =
{
	// JS name								ID											flags								getter	setter
	{ "calculatedPrice",				kEquipmentInfo_calculatedPrice,			kEquipmentInfoPropertyFlagsReadOnly, nullptr, nullptr },
	{ "canBeDamaged",					kEquipmentInfo_canBeDamaged,				kEquipmentInfoPropertyFlagsReadOnly, nullptr, nullptr },
	{ "canCarryMultiple",				kEquipmentInfo_canCarryMultiple,			kEquipmentInfoPropertyFlagsReadOnly, nullptr, nullptr },
	{ "damageProbability",				kEquipmentInfo_damageProbability,			kEquipmentInfoPropertyFlagsReadOnly, nullptr, nullptr },
	{ "description",					kEquipmentInfo_description,				kEquipmentInfoPropertyFlagsReadOnly, nullptr, nullptr },
	{ "displayColor",					kEquipmentInfo_displayColor,				kEquipmentInfoPropertyFlags,		nullptr, nullptr },
	{ "effectiveTechLevel",				kEquipmentInfo_effectiveTechLevel,			kEquipmentInfoPropertyFlags,		nullptr, nullptr },
	{ "equipmentKey",					kEquipmentInfo_equipmentKey,				kEquipmentInfoPropertyFlagsReadOnly, nullptr, nullptr },
	{ "fastAffinityDefensive",			kEquipmentInfo_fastAffinityDefensive,		kEquipmentInfoPropertyFlagsReadOnly, nullptr, nullptr },
	{ "fastAffinityOffensive",			kEquipmentInfo_fastAffinityOffensive,		kEquipmentInfoPropertyFlagsReadOnly, nullptr, nullptr },
	{ "defaultActivateKey",				kEquipmentInfo_defaultActivateKey,			kEquipmentInfoPropertyFlagsReadOnly, nullptr, nullptr },
	{ "defaultModeKey",					kEquipmentInfo_defaultModeKey,				kEquipmentInfoPropertyFlagsReadOnly, nullptr, nullptr },
	{ "incompatibleEquipment",			kEquipmentInfo_incompatibleEquipment,		kEquipmentInfoPropertyFlagsReadOnly, nullptr, nullptr },
	{ "installationTime",				kEquipmentInfo_installationTime,           kEquipmentInfoPropertyFlagsReadOnly, nullptr, nullptr },
	{ "isAvailableToAll",				kEquipmentInfo_isAvailableToAll,			kEquipmentInfoPropertyFlagsReadOnly, nullptr, nullptr },
	{ "isAvailableToNPCs",				kEquipmentInfo_isAvailableToNPCs,			kEquipmentInfoPropertyFlagsReadOnly, nullptr, nullptr },
	{ "isAvailableToPlayer",			kEquipmentInfo_isAvailableToPlayer,		kEquipmentInfoPropertyFlagsReadOnly, nullptr, nullptr },
	{ "isExternalStore",				kEquipmentInfo_isExternalStore,			kEquipmentInfoPropertyFlagsReadOnly, nullptr, nullptr },
	{ "isPortableBetweenShips",			kEquipmentInfo_isPortableBetweenShips,		kEquipmentInfoPropertyFlagsReadOnly, nullptr, nullptr },
	{ "isVisible",						kEquipmentInfo_isVisible,					kEquipmentInfoPropertyFlagsReadOnly, nullptr, nullptr },
	{ "name",							kEquipmentInfo_name,						kEquipmentInfoPropertyFlagsReadOnly, nullptr, nullptr },
	{ "price",							kEquipmentInfo_price,						kEquipmentInfoPropertyFlagsReadOnly, nullptr, nullptr },
	{ "provides",						kEquipmentInfo_provides,					kEquipmentInfoPropertyFlagsReadOnly, nullptr, nullptr },
	{ "repairTime",                     kEquipmentInfo_repairTime,                  kEquipmentInfoPropertyFlagsReadOnly, nullptr, nullptr },
	{ "requiredCargoSpace",				kEquipmentInfo_requiredCargoSpace,			kEquipmentInfoPropertyFlagsReadOnly, nullptr, nullptr },
	{ "requiresAnyEquipment",			kEquipmentInfo_requiresAnyEquipment,		kEquipmentInfoPropertyFlagsReadOnly, nullptr, nullptr },
	{ "requiresCleanLegalRecord",		kEquipmentInfo_requiresCleanLegalRecord,	kEquipmentInfoPropertyFlagsReadOnly, nullptr, nullptr },
	{ "requiresEmptyPylon",				kEquipmentInfo_requiresEmptyPylon,			kEquipmentInfoPropertyFlagsReadOnly, nullptr, nullptr },
	{ "requiresEquipment",				kEquipmentInfo_requiresEquipment,			kEquipmentInfoPropertyFlagsReadOnly, nullptr, nullptr },
	{ "requiresFreePassengerBerth",		kEquipmentInfo_requiresFreePassengerBerth,	kEquipmentInfoPropertyFlagsReadOnly, nullptr, nullptr },
	{ "requiresFullFuel",				kEquipmentInfo_requiresFullFuel,			kEquipmentInfoPropertyFlagsReadOnly, nullptr, nullptr },
	{ "requiresMountedPylon",			kEquipmentInfo_requiresMountedPylon,		kEquipmentInfoPropertyFlagsReadOnly, nullptr, nullptr },
	{ "requiresNonCleanLegalRecord",	kEquipmentInfo_requiresNonCleanLegalRecord,	kEquipmentInfoPropertyFlagsReadOnly, nullptr, nullptr },
	{ "requiresNonFullFuel",			kEquipmentInfo_requiresNonFullFuel,		kEquipmentInfoPropertyFlagsReadOnly, nullptr, nullptr },
	{ "scriptInfo",						kEquipmentInfo_scriptInfo,					kEquipmentInfoPropertyFlagsReadOnly, nullptr, nullptr },
	{ "scriptName",						kEquipmentInfo_scriptName,					kEquipmentInfoPropertyFlagsReadOnly, nullptr, nullptr },
	{ "techLevel",						kEquipmentInfo_techLevel,					kEquipmentInfoPropertyFlagsReadOnly, nullptr, nullptr },
	{ "weaponInfo",						kEquipmentInfo_weaponInfo,					kEquipmentInfoPropertyFlagsReadOnly, nullptr, nullptr },
	{ 0 }
};
} // namespace

namespace {
static PropertySpec sEquipmentInfoStaticProperties[] =
{
	{ "allEquipment",					0, kEquipmentInfoPropertyFlagsReadOnly, EquipmentInfoGetAllEqipment, nullptr },
	{ 0 }
};
} // namespace


namespace {
static bool EquipmentInfoToString(ooscript::Context context, ooscript::CallArgs &oojsArgs);
}


namespace {
static FunctionSpec sEquipmentInfoMethods[] =
{
	// JS name					Function						min args
	{ "toString",				EquipmentInfoToString,		0,	0 },
	{ 0 }
};
} // namespace


namespace {
static FunctionSpec sEquipmentInfoStaticMethods[] =
{
	// JS name					Function						min args
	{ "infoForKey",				EquipmentInfoStaticInfoForKey,	0,	0 },
	{ 0 }
};
} // namespace


namespace {
static ClassDef sEquipmentInfoClass =
{
	"EquipmentInfo",
	ClassFlag::HasPrivate,

	nullptr,					// addProperty (engine default: PropertyStub)
	nullptr,					// delProperty (engine default: PropertyStub)
	EquipmentInfoGetProperty,	// getProperty
	EquipmentInfoSetProperty,	// setProperty
	nullptr,					// enumerate (engine default: EnumerateStub)
	nullptr,					// newEnumerate (ooscript::ClassFlag::NewEnumerate not used)
	nullptr,					// resolve (engine default: ResolveStub)
	nullptr,					// convert (engine default: ConvertStub)
	OOJSCxxObjectWrapperFinalize,	// finalize
	nullptr,					// call
	nullptr,					// construct
	nullptr,					// backend: owned by the façade backend, must start null
};
} // namespace


namespace {
// DEFINE_JS_OBJECT_GETTER for the C++ type the slot holds (null for the prototype).
bool JSEquipmentInfoGetEquipmentType(ooscript::Context context, ooscript::Object inObject, OOEquipmentType **outObject)
{
	return OOJSGetCxxPrivate(context, inObject, &sEquipmentInfoClass, outObject);
}


// OOJSBasicPrivateObjectConverter for the C++ type the slot holds: the type itself as an Object
// node (bead oo-9ht.28; it was its facade), for the callers of cxx_OOJSPListFromJSValue (null for
// the prototype).
oo::PList EquipmentInfoConverter(ooscript::Context context, ooscript::Object object)
{
	OOEquipmentType *type = static_cast<OOEquipmentType *>(static_cast<oo::RefCounted *>(ooscript::getPrivate(context, object)));
	return OOEquipmentTypeObjectNode(type);
}
} // namespace


// *** Public ***

void InitOOJSEquipmentInfo(ooscript::Context context, ooscript::Object global)
{
	Object proto = ooscript::initClass((context), (global), nullptr, &sEquipmentInfoClass, OOJSUnconstructableConstruct, 0, sEquipmentInfoProperties, sEquipmentInfoMethods, sEquipmentInfoStaticProperties, sEquipmentInfoStaticMethods);
	sEquipmentInfoPrototype = (proto);
	
	OOJSRegisterObjectConverter(&sEquipmentInfoClass, EquipmentInfoConverter);
}


OOEquipmentType *JSValueToEquipmentType(ooscript::Context context, ooscript::Value value)
{
	OOJS_PROFILE_ENTER
	
	if (ooscript::isObjectOrNull(value))
	{
		ooscript::Object object = ooscript::toObject(value);
		if (ooscript::instanceOf((context), (ooscript::toObject(value)), &sEquipmentInfoClass, nullptr))
		{
			return static_cast<OOEquipmentType *>(static_cast<oo::RefCounted *>(ooscript::getPrivate((context), (object))));	// borrowed: the slot holds it
		}
	}
	
	std::optional<std::string> string = cxx_OOStringFromJSValue(context, value);
	if (string.has_value())  return OOEquipmentType::equipmentTypeWithIdentifier(*string).get();	// borrowed: the registry holds it
	return nullptr;
	
	OOJS_PROFILE_EXIT
}


std::optional<std::string> JSValueToEquipmentKey(ooscript::Context context, ooscript::Value value)
{
	return Ask(JSValueToEquipmentType(context, value), &OOEquipmentType::identifier);
}


std::optional<std::string> JSValueToEquipmentKeyRelaxed(ooscript::Context context, ooscript::Value value, BOOL *outExists)
{
	OOJS_PROFILE_ENTER
	
	std::optional<std::string> result;
	bool exists = false;
	const oo::PList plistValue = cxx_OOJSPListFromJSValue(context, value);
	
	if (OOEquipmentType *typeValue = OOEquipmentTypeInObjectNode(plistValue))
	{
		result = typeValue->identifier();
		exists = true;
	}
	else if (const std::string *stringValue = plistValue.getIf<std::string>())
	{
		/*	To enforce deliberate backwards incompatibility, reject strings
			ending with _DAMAGED unless someone actually named an equip that
			way.
		 */
		exists = OOEquipmentType::equipmentTypeWithIdentifier(*stringValue) != nullptr;
		std::string string = *stringValue;
		if (exists || !oo::str::hasSuffix(string, "_DAMAGED"))
		{
			result = string;
		}
	}
	
	if (outExists != NULL)  *outExists = exists;
	return result;
	
	OOJS_PROFILE_EXIT_VAL(std::nullopt)
}


// *** Implementation stuff ***

namespace {
static bool EquipmentInfoGetProperty(Context cx, Object obj, PropertyId propID, Value *value)
{
	if (!ooscript::isInt32Id(propID))  return true;
	
	ooscript::Context context = (cx);
	ooscript::Object thisObj = (obj);
	
	OOJS_NATIVE_ENTER(context)
	
	oo::PList					result;	// null maps to null
	NSUInteger 					inst_time;
	
	OOEquipmentType		*type = nullptr;	// null for the prototype: see Ask()
	if (EXPECT_NOT(!JSEquipmentInfoGetEquipmentType(context, thisObj, &type)))  return false;
	
	switch (ooscript::idToInt32(propID))
	{
		case kEquipmentInfo_equipmentKey:
			result = StringOrNull(Ask(type, &OOEquipmentType::identifier));
			break;
			
		case kEquipmentInfo_name:
			result = StringOrNull(Ask(type, &OOEquipmentType::name));
			break;

		case kEquipmentInfo_calculatedPrice:
			if (Ask(type, &OOEquipmentType::identifier) == "EQ_FUEL") 
			{
				PlayerEntity *player = OOPlayerForScripting();	// fuelChargeRate qualified: the final overrider, so the binding test stands in for it (bead oo-9ht.177)
				return ooscript::newNumberValue(cx, (PLAYER_MAX_FUEL - (player != nullptr ? player->getFuel() : 0)) * Ask(type, &OOEquipmentType::price) * (player != nullptr ? player->PlayerEntity::fuelChargeRate() : 0.0f), value);
			}
			else if (Ask(type, &OOEquipmentType::identifier) == "EQ_RENOVATION") 
			{
				PlayerEntity *player = OOPlayerForScripting();
				return ooscript::newNumberValue(cx, (player != nullptr ? player->PlayerEntity::renovationCosts() : 0), value);	// qualified: the final overrider (bead oo-9ht.177), so the binding test stands in for it
			}
			else 
			{
				PlayerEntity *player = OOPlayerForScripting();
				return ooscript::newNumberValue(cx, (Ask(type, &OOEquipmentType::identifier).has_value() ? (player != nullptr ? player->adjustPriceByScriptForEqKey(*Ask(type, &OOEquipmentType::identifier), Ask(type, &OOEquipmentType::price)) : 0) : Ask(type, &OOEquipmentType::price)), value);
			}
		case kEquipmentInfo_canCarryMultiple:
			*value = OOJSValueFromBOOL(Ask(type, &OOEquipmentType::canCarryMultiple));
			return true;
			
		case kEquipmentInfo_canBeDamaged:
			*value = OOJSValueFromBOOL(Ask(type, &OOEquipmentType::canBeDamaged));
			return true;
			
		case kEquipmentInfo_description:
			result = StringOrNull(Ask(type, &OOEquipmentType::descriptiveText));
			break;
			
		case kEquipmentInfo_damageProbability:
			return ooscript::newNumberValue(cx, Ask(type, &OOEquipmentType::damageProbability), value);

		case kEquipmentInfo_displayColor:
			result = NormalizedColorComponents(Ask(type, &OOEquipmentType::displayColor).get());
			break;

		case kEquipmentInfo_fastAffinityDefensive:
			*value = OOJSValueFromBOOL(Ask(type, &OOEquipmentType::fastAffinityDefensive));
			return true;

		case kEquipmentInfo_fastAffinityOffensive:
			*value = OOJSValueFromBOOL(Ask(type, &OOEquipmentType::fastAffinityOffensive));
			return true;

		case kEquipmentInfo_defaultActivateKey:
			result = Ask(type, &OOEquipmentType::defaultActivateKey);
			break;		

		case kEquipmentInfo_defaultModeKey:
			result = Ask(type, &OOEquipmentType::defaultModeKey);
			break;		

		case kEquipmentInfo_techLevel:
			*value = ooscript::int32Value((int32_t)Ask(type, &OOEquipmentType::techLevel));
			return true;
			
		case kEquipmentInfo_effectiveTechLevel:
			*value = ooscript::int32Value((int32_t)Ask(type, &OOEquipmentType::effectiveTechLevel));
			return true;
			
		case kEquipmentInfo_price:
			return ooscript::newNumberValue(cx, Ask(type, &OOEquipmentType::price), value);

		case kEquipmentInfo_provides:
			{
				const std::vector<std::string> provides = Ask(type, &OOEquipmentType::providesForScripting);
				result = oo::PList(oo::PList::Array(provides.begin(), provides.end()));
			}
			break;
		
		case kEquipmentInfo_installationTime:
			inst_time = Ask(type, &OOEquipmentType::installTime);
			if (inst_time == 0) 
			{
				inst_time = Ask(type, &OOEquipmentType::price) + 600;
			}
			*value = ooscript::int32Value((int32_t)inst_time);
			return true;

		case kEquipmentInfo_isAvailableToAll:
			*value = OOJSValueFromBOOL(Ask(type, &OOEquipmentType::isAvailableToAll));
			return true;
			
		case kEquipmentInfo_isAvailableToNPCs:
			*value = OOJSValueFromBOOL(Ask(type, &OOEquipmentType::isAvailableToNPCs));
			return true;
			
		case kEquipmentInfo_isAvailableToPlayer:
			*value = OOJSValueFromBOOL(Ask(type, &OOEquipmentType::isAvailableToPlayer));
			return true;

		case kEquipmentInfo_repairTime:
			*value = ooscript::int32Value((int32_t)Ask(type, &OOEquipmentType::repairTime));
			return true;

		case kEquipmentInfo_requiresEmptyPylon:
			*value = OOJSValueFromBOOL(Ask(type, &OOEquipmentType::requiresEmptyPylon));
			return true;
			
		case kEquipmentInfo_requiresMountedPylon:
			*value = OOJSValueFromBOOL(Ask(type, &OOEquipmentType::requiresMountedPylon));
			return true;
			
		case kEquipmentInfo_requiresCleanLegalRecord:
			*value = OOJSValueFromBOOL(Ask(type, &OOEquipmentType::requiresCleanLegalRecord));
			return true;
			
		case kEquipmentInfo_requiresNonCleanLegalRecord:
			*value = OOJSValueFromBOOL(Ask(type, &OOEquipmentType::requiresNonCleanLegalRecord));
			return true;
			
		case kEquipmentInfo_requiresFreePassengerBerth:
			*value = OOJSValueFromBOOL(Ask(type, &OOEquipmentType::requiresFreePassengerBerth));
			return true;
			
		case kEquipmentInfo_requiresFullFuel:
			*value = OOJSValueFromBOOL(Ask(type, &OOEquipmentType::requiresFullFuel));
			return true;
			
		case kEquipmentInfo_requiresNonFullFuel:
			*value = OOJSValueFromBOOL(Ask(type, &OOEquipmentType::requiresNonFullFuel));
			return true;
			
		case kEquipmentInfo_isExternalStore:
			*value = OOJSValueFromBOOL(Ask(type, &OOEquipmentType::isMissileOrMine));
			return true;
			
		case kEquipmentInfo_isPortableBetweenShips:
			*value = OOJSValueFromBOOL(Ask(type, &OOEquipmentType::isPortableBetweenShips));
			return true;
			
		case kEquipmentInfo_isVisible:
			*value = OOJSValueFromBOOL(Ask(type, &OOEquipmentType::isVisible));
			return true;
			
		case kEquipmentInfo_requiredCargoSpace:
			*value = ooscript::int32Value((int32_t)Ask(type, &OOEquipmentType::requiredCargoSpace));
			return true;
			
		case kEquipmentInfo_requiresEquipment:
			result = KeyArrayOrNull(Ask(type, &OOEquipmentType::requiresEquipment));
			break;
			
		case kEquipmentInfo_requiresAnyEquipment:
			result = KeyArrayOrNull(Ask(type, &OOEquipmentType::requiresAnyEquipment));
			break;
			
		case kEquipmentInfo_incompatibleEquipment:
			result = KeyArrayOrNull(Ask(type, &OOEquipmentType::incompatibleEquipment));
			break;
			
		case kEquipmentInfo_scriptInfo:
			{
				const oo::PList info = Ask(type, &OOEquipmentType::scriptInfo);
				result = info.isNull() ? oo::PList(oo::PList::Dict{}) : info;	// empty rather than null
			}
			break;
			
		case kEquipmentInfo_scriptName:
			result = oo::PList(Ask(type, &OOEquipmentType::scriptName).value_or(std::string()));
			break;
			
		case kEquipmentInfo_weaponInfo:
			result = Ask(type, &OOEquipmentType::weaponInfo);
			if (result.isNull())  result = oo::PList(oo::PList::Dict{});	// empty rather than null
			break;
			
		default:
			OOJSReportBadPropertySelector(context, thisObj, (propID), sEquipmentInfoProperties);
			return false;
	}
	
	*value = OOJSValueFromPList(context, result);
	return true;
	
	OOJS_NATIVE_EXIT
}
} // namespace


namespace {
static bool EquipmentInfoSetProperty(Context cx, Object obj, PropertyId propID, bool /*strict*/, Value *value)
{
	if (!ooscript::isInt32Id(propID))  return true;
	
	ooscript::Context context = (cx);
	ooscript::Object thisObj = (obj);
	
	OOJS_NATIVE_ENTER(context)
	
	int32_t						iValue;
	oo::Ref<OOColor>		colorForScript;
	
	OOEquipmentType		*type = nullptr;	// null for the prototype: see Ask()
	if (EXPECT_NOT(!JSEquipmentInfoGetEquipmentType(context, thisObj, &type)))  return false;
	
	switch (ooscript::idToInt32(propID))
	{
		case kEquipmentInfo_displayColor:
			colorForScript = OOColor::colorWithDescription(cxx_OOJSPListFromJSValue(context, *value));
			if (colorForScript != nullptr || ooscript::isNull(*value))
			{
				if (type != nullptr)  type->setDisplayColor(colorForScript.get());	// (a message to nil did nothing)
				return true;
			}
			break;
		case kEquipmentInfo_effectiveTechLevel:
			cxx_OOStandardsDeprecated(oo::str::format("TL99 for variable tech level is deprecated for %s", Ask(type, &OOEquipmentType::identifier).value_or("(null)").c_str()));
			if (!OOEnforceStandards() && Ask(type, &OOEquipmentType::techLevel) == kOOVariableTechLevel)
			{
				if (ooscript::isNull(*value)) 
				{
					// reset mission variable
					if (PlayerEntity *player = OOPlayerForScripting())  player->setMissionVariable(oo::PList(), "mission_TL_FOR_" + Ask(type, &OOEquipmentType::identifier).value_or(""));
					return true;
				}
				if (ooscript::valueToInt32(cx, *value, &iValue))
				{
					if (iValue < 0)  iValue = 0;
					if (15 < iValue && iValue != kOOVariableTechLevel)  iValue = 15;
					if (PlayerEntity *player = OOPlayerForScripting())  player->setMissionVariable(oo::PList(oo::str::format("%u", iValue)), "mission_TL_FOR_" + Ask(type, &OOEquipmentType::identifier).value_or(""));
					return true;
				}
			}
			else
			{
				cxx_OOJSReportWarning(context, "Cannot modify effective tech level for %s, because its base tech level is not 99.", Ask(type, &OOEquipmentType::identifier).value_or("(null)").c_str());
				return true;
			}
			break;
			
		default:
			OOJSReportBadPropertySelector(context, thisObj, (propID), sEquipmentInfoProperties);
			return false;
	}
	
	OOJSReportBadPropertyValue(context, thisObj, (propID), sEquipmentInfoProperties, *value);
	return false;
	
	OOJS_NATIVE_EXIT
}
} // namespace


namespace {
static bool EquipmentInfoGetAllEqipment(Context cx, Object /*obj*/, PropertyId /*propID*/, Value *value)
{
	ooscript::Context context = (cx);
	
	OOJS_NATIVE_ENTER(context)
	
	*value = OOJSValueFromPList(context, OOEquipmentTypeObjectNodes(OOEquipmentType::allEquipmentTypes()));
	return true;
	
	OOJS_NATIVE_EXIT
}
} // namespace
	

// The JS glue of OOEquipmentType (OOJSPrivateObject; amendment oo-6symp item 5), which the
// engine reaches through the slot's C++ object or an Object node that holds the type.
ooscript::Value OOEquipmentType::jsValueInContext(ooscript::Context context)
{
	if (_jsSelf == NULL)
	{
		_jsSelf = (ooscript::newObject((context), &sEquipmentInfoClass, (sEquipmentInfoPrototype), nullptr));
		if (_jsSelf != NULL)
		{
			if (!OOJSSetCxxPrivate(context, _jsSelf, this))  _jsSelf = NULL;
		}
	}

	return ooscript::objectValue(_jsSelf);
}


void OOEquipmentType::clearJSSelf(ooscript::Object selfVal)
{
	if (_jsSelf == selfVal)  _jsSelf = NULL;
}


// What the facade's -cxx_oo_jsDescription answered (OOObject (OOJavaScriptConversion)): the JS
// class name and the components.
std::optional<std::string> OOEquipmentType::jsDescription()
{
	const std::optional<std::string> components = descriptionComponents();
	const std::string name = OOJSEquipmentInfoJSClassName().value_or("EquipmentInfo");
	if (components.has_value())  return oo::str::format("[%s %s]", name.c_str(), components->c_str());
	return oo::str::format("[object %s]", name.c_str());
}


std::optional<std::string> OOJSEquipmentInfoJSClassName(void)
{
	return std::string("EquipmentInfo");
}


// *** Static methods ***

// infoForKey(key : String): EquipmentInfo
namespace {
static bool EquipmentInfoStaticInfoForKey(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_NATIVE_ENTER(context)
	
	std::optional<std::string>	key;
	
	if (oojsArgs.count() > 0)  key = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (!key.has_value())
	{
		cxx_OOJSReportBadArguments(context, "EquipmentInfo", "infoForKey", MIN(oojsArgs.count(), 1U), OOJS_ARGV, std::nullopt, "string");
		return false;
	}
	
	OOJS_RETURN(OOJSValueFromCxxObject(context, OOEquipmentType::equipmentTypeWithIdentifier(*key).get()));
	
	OOJS_NATIVE_EXIT
}
} // namespace


// toString(): the C++ type's jsDescription().
namespace {
static bool EquipmentInfoToString(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	return OOJSCxxObjectWrapperToString(context, oojsArgs, &sEquipmentInfoClass);
}
} // namespace
