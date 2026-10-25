/*

OOConstToString.m

Oolite
Copyright (C) 2004-2013 Giles C Williams and contributors

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version );
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., ); Franklin Street, Fifth Floor, Boston,
MA );-);, USA.

*/

#include "OOConstToString.h"

#include "Universe.h"
#include "PlayerEntity.h"
#include "OOEquipmentType.h"
#include "OOCommodityMarket.h"

#include "oofnd/String.hpp"

#define CASE(foo) case foo: return #foo;
#define REVERSE_CASE(foo) if (string == #foo) return foo;


#define ENTRY(label, value) case label: return #label;
#define GALACTIC_HYPERSPACE_ENTRY(label, value) case GALACTIC_HYPERSPACE_##label: return #label;
#define DIFF_STRING_ENTRY(label, string) case label: return string;

std::string cxx_OOStringFromEntityStatus(OOEntityStatus value)
{
	switch (value)
	{
		#include "OOEntityStatus.tbl"
	}
	return "UNDEFINED";
}


std::string cxx_OOStringFromBehaviour(OOBehaviour value)
{
	switch (value)
	{
		#include "OOBehaviour.tbl"
	}
	
	return "** BEHAVIOUR UNKNOWN **";
}


std::string cxx_OOStringFromCompassMode(OOCompassMode value)
{
	switch (value)
	{
		#include "OOCompassMode.tbl"
	}
	
	return "UNDEFINED";
}

std::string cxx_OOStringFromLongRangeChartMode(OOLongRangeChartMode value)
{
	switch (value)
	{
		#include "OOLongRangeChartMode.tbl"
	}

	return "UNDEFINED";
}

std::string cxx_OOStringFromGalacticHyperspaceBehaviour(OOGalacticHyperspaceBehaviour value)
{
	switch (value)
	{
		#include "OOGalacticHyperspaceBehaviour.tbl"
	}
	
	return "UNDEFINED";
}


std::string cxx_OOStringFromGUIScreenID(OOGUIScreenID value)
{
	switch (value)
	{
		#include "OOGUIScreenID.tbl"
	}
	
	return "UNDEFINED";
}


std::string cxx_OOStringFromScanClass(OOScanClass value)
{
	switch (value)
	{
		#include "OOScanClass.tbl"
	}
	
	return "UNDEFINED";
}


std::string cxx_OOStringFromShipDamageType(OOShipDamageType value)
{
	switch (value)
	{
		#include "OOShipDamageType.tbl"
	}
	
	return "UNDEFINED";
}

std::string cxx_OOStringFromLegalStatusReason(OOLegalStatusReason value)
{
	switch (value)
	{
		#include "OOLegalStatusReason.tbl"
	}
	
	return "UNDEFINED";
}


#undef ENTRY
#undef GALACTIC_HYPERSPACE_ENTRY


#define ENTRY(label, value) if (string == #label)  return label;
#define GALACTIC_HYPERSPACE_ENTRY(label, value)	if (string == #label)  return GALACTIC_HYPERSPACE_##label;

OOEntityStatus cxx_OOEntityStatusFromString(const std::string &string)
{
	#include "OOEntityStatus.tbl"
	
	return (OOEntityStatus)kOOEntityStatusDefault;
}


OOCompassMode cxx_OOCompassModeFromString(const std::string &string)
{
	#include "OOCompassMode.tbl"
	
	return (OOCompassMode)kOOCompassModeDefault;
}


OOGalacticHyperspaceBehaviour cxx_OOGalacticHyperspaceBehaviourFromString(const std::string &string)
{
	#include "OOGalacticHyperspaceBehaviour.tbl"
	
	// Transparently (but inefficiently) support american spelling. FIXME: remove in EMMSTRAN.
	if (oo::str::hasPrefix(string, "BEHAVIOR_"))
	{
		return cxx_OOGalacticHyperspaceBehaviourFromString("BEHAVIOUR_" + string.substr(9));
	}
	
	return (OOGalacticHyperspaceBehaviour)kOOGalacticHyperspaceBehaviourDefault;
}


OOGUIScreenID cxx_OOGUIScreenIDFromString(const std::string &string)
{
	#include "OOGUIScreenID.tbl"
	
	return (OOGUIScreenID)kOOGUIScreenIDDefault;
}


OOScanClass cxx_OOScanClassFromString(const std::string &string)
{
	#include "OOScanClass.tbl"
	
	return (OOScanClass)kOOScanClassDefault;
}

OOLongRangeChartMode cxx_OOLongRangeChartModeFromString(const std::string &string)
{
	#include "OOLongRangeChartMode.tbl"
	
	return kOOLongRangeChartModeDefault;
}

#undef ENTRY
#undef GALACTIC_HYPERSPACE_ENTRY


std::string cxx_RouteTypeToString(OORouteType routeType)
{
	switch (routeType)
	{
		CASE(OPTIMIZED_BY_NONE);
		CASE(OPTIMIZED_BY_JUMPS);
		CASE(OPTIMIZED_BY_TIME);
	}
	
	return "** ROUTE TYPE UNKNOWN **";
}


namespace
{
// PListView's string rule (OOCollectionExtractors' StringForObject): the element if it is a
// string, or a number's -stringValue; nullopt (was nil) for anything else or a missing element.
std::optional<std::string> DescriptionStringAt(const oo::PList &strings, std::size_t index)
{
	const oo::PList *value = strings.at(index);
	if (value == nullptr || !(value->isString() || value->isNumber()))  return std::nullopt;
	return strings.at<std::string>(index);
}
}


std::optional<std::string> cxx_OODisplayStringFromGovernmentID(OOGovernmentID government)
{
	// Only the one sub-array of the descriptions; a missing key reads as the null PList PListFrom(nil) gave.
	const oo::PList *stringsEntry = UNIVERSE->descriptions()->find("government");
	const oo::PList strings = (stringsEntry != nullptr) ? *stringsEntry : oo::PList();
	if (strings.isArray() && government < strings.count())
	{
		if (const std::string *value = strings.at(government)->getIf<std::string>())  return *value;
	}

	return std::nullopt;
}


std::optional<std::string> cxx_OODisplayStringFromEconomyID(OOEconomyID economy)
{
	const oo::PList *stringsEntry = UNIVERSE->descriptions()->find("economy");
	const oo::PList strings = (stringsEntry != nullptr) ? *stringsEntry : oo::PList();
	if (strings.isArray() && economy < strings.count())
	{
		if (const std::string *value = strings.at(economy)->getIf<std::string>())  return *value;
	}

	return std::nullopt;
}


std::string cxx_JSTypeToString(int /* ooscript::Type */ type)
{
	// The strings are the engine's own type-constant names, as this function has always returned.
	switch ((ooscript::Type)type)
	{
		case ooscript::Type::Void: return "JSTYPE_VOID";
		case ooscript::Type::Object: return "JSTYPE_OBJECT";
		case ooscript::Type::Function: return "JSTYPE_FUNCTION";
		case ooscript::Type::String: return "JSTYPE_STRING";
		case ooscript::Type::Number: return "JSTYPE_NUMBER";
		case ooscript::Type::Boolean: return "JSTYPE_BOOLEAN";
		case ooscript::Type::Null: return "JSTYPE_NULL";
		case ooscript::Type::XML: return "JSTYPE_XML";
	}
	if (type == (int)ooscript::Type::XML + 1)  return "JSTYPE_LIMIT";
	return oo::str::format("unknown (%u)", type);
}


std::optional<std::string> cxx_OOStringFromWeaponType(OOWeaponType weapon)
{
	if (weapon == nil) {
		return "EQ_WEAPON_NONE";
	} else {
		return weapon->identifier();
	}
}


OOWeaponType cxx_OOWeaponTypeFromString(const std::string &string)
{
	return cxx_OOWeaponTypeFromEquipmentIdentifierSloppy(string);
}


std::optional<std::string> cxx_OOEquipmentIdentifierFromWeaponType(OOWeaponType weapon)
{
	// No weapon: a message to nil answered a zeroed std::optional, no identifier.
	OOEquipmentType *type = weapon;
	return (type != nullptr) ? type->identifier() : std::nullopt;
}


OOWeaponType cxx_OOWeaponTypeFromEquipmentIdentifierSloppy(const std::string &string)
{
	// The weapon type is the C++ type since bead oo-9ht.28, borrowed: the registry holds it.
	oo::Ref<OOEquipmentType> w = OOEquipmentType::equipmentTypeWithIdentifier(string);
	if (w == nullptr)
	{
		if (!oo::str::hasPrefix(string, "EQ_"))
		{
			w = OOEquipmentType::equipmentTypeWithIdentifier("EQ_" + string);
			if (w != nullptr)
			{
				return w.get();
			}
		}
		return OOEquipmentType::equipmentTypeWithIdentifier("EQ_WEAPON_NONE").get();
	}
	return w.get();
}


/* Previous save games will have weapon types stored as ints to the
 * various weapon types */
OOWeaponType cxx_OOWeaponTypeFromEquipmentIdentifierLegacy(const std::string &string)
{
	if (oo::str::intValue(string) > 0)
	{
		switch (oo::str::intValue(string))
		{
		case 2:
			return cxx_OOWeaponTypeFromEquipmentIdentifierSloppy("EQ_WEAPON_PULSE_LASER");
		case 3:
			return cxx_OOWeaponTypeFromEquipmentIdentifierSloppy("EQ_WEAPON_BEAM_LASER");
		case 4:
			return cxx_OOWeaponTypeFromEquipmentIdentifierSloppy("EQ_WEAPON_MINING_LASER");
		case 5:
			return cxx_OOWeaponTypeFromEquipmentIdentifierSloppy("EQ_WEAPON_MILITARY_LASER");
		case 10:
			return cxx_OOWeaponTypeFromEquipmentIdentifierSloppy("EQ_WEAPON_THARGOID_LASER");
		default:
			return cxx_OOWeaponTypeFromEquipmentIdentifierSloppy(string);
		}
	}
	return cxx_OOWeaponTypeFromEquipmentIdentifierSloppy(string);
}


OOWeaponType cxx_OOWeaponTypeFromEquipmentIdentifierStrict(const std::string &string)
{
	// there is no difference between the two any more
	return cxx_OOWeaponTypeFromEquipmentIdentifierSloppy(string);
}


std::string cxx_CargoTypeToString(OOCargoType cargo)
{
	switch (cargo)
	{
		CASE(CARGO_NOT_CARGO);
		CASE(CARGO_SLAVES);
		CASE(CARGO_ALLOY);
		CASE(CARGO_MINERALS);
		CASE(CARGO_THARGOID);
		CASE(CARGO_RANDOM);
		CASE(CARGO_SCRIPTED_ITEM);
		CASE(CARGO_CHARACTER);
	}
	return "Unknown cargo";
}


OOCargoType cxx_StringToCargoType(const std::string &string)
{
	REVERSE_CASE(CARGO_NOT_CARGO);
	REVERSE_CASE(CARGO_SLAVES);
	REVERSE_CASE(CARGO_ALLOY);
	REVERSE_CASE(CARGO_MINERALS);
	REVERSE_CASE(CARGO_THARGOID);
	REVERSE_CASE(CARGO_RANDOM);
	REVERSE_CASE(CARGO_SCRIPTED_ITEM);
	REVERSE_CASE(CARGO_CHARACTER);
	
	// Backwards compatibility.
	if (string == "CARGO_CARRIED") return CARGO_RANDOM;
	
	return (OOCargoType)kOOCargoTypeDefault;
}


std::string cxx_EnergyUnitTypeToString(OOEnergyUnitType unit)
{
	switch (unit)
	{
		CASE(ENERGY_UNIT_NONE);
		CASE(ENERGY_UNIT_NORMAL);
		CASE(ENERGY_UNIT_NAVAL);
		CASE(ENERGY_UNIT_NORMAL_DAMAGED);
		CASE(ENERGY_UNIT_NAVAL_DAMAGED);
			
		case OLD_ENERGY_UNIT_NORMAL:
		case OLD_ENERGY_UNIT_NAVAL:
			break;
	}
	
	return "Unsupported energy unit";
}


OOEnergyUnitType cxx_StringToEnergyUnitType(const std::string &string)
{
	REVERSE_CASE(ENERGY_UNIT_NONE);
	REVERSE_CASE(ENERGY_UNIT_NORMAL);
	REVERSE_CASE(ENERGY_UNIT_NAVAL);
	REVERSE_CASE(ENERGY_UNIT_NORMAL_DAMAGED);
	REVERSE_CASE(ENERGY_UNIT_NAVAL_DAMAGED);
	
	return (OOEnergyUnitType)kOOEnergyUnitTypeDefault;
}


std::optional<std::string> cxx_OODisplayRatingStringFromKillCount(unsigned kills)
{
	enum { kRatingCount = 9 };

	const unsigned		killThresholds[kRatingCount - 1] =
						{
							0x0008,
							0x0010,
							0x0020,
							0x0040,
							0x0080,
							0x0200,
							0x0A00,
							0x1900
						};
	unsigned			i;

	const oo::PList *ratingNamesEntry = UNIVERSE->descriptions()->find("rating");
	const oo::PList ratingNames = (ratingNamesEntry != nullptr) ? *ratingNamesEntry : oo::PList();
	for (i = 0; i < kRatingCount - 1; ++i)
	{
		if (kills < killThresholds[i])  return DescriptionStringAt(ratingNames, i);
	}

	return DescriptionStringAt(ratingNames, kRatingCount - 1);
}


std::string cxx_KillCountToRatingAndKillString(unsigned kills)
{
	// %@ of a nil rating printed "(null)".
	const std::optional<std::string> rating = cxx_OODisplayRatingStringFromKillCount(kills);
	return oo::str::format("%s   (%u)", rating.has_value() ? rating->c_str() : "(null)", kills);
}


std::optional<std::string> cxx_OODisplayStringFromLegalStatus(int legalStatus)
{
	enum { kStatusCount = 3 };

	const int			statusThresholds[kStatusCount - 1] =
						{
							1,
							51
						};
	unsigned			i;

	const oo::PList *statusNamesEntry = UNIVERSE->descriptions()->find("legal_status");
	const oo::PList statusNames = (statusNamesEntry != nullptr) ? *statusNamesEntry : oo::PList();
	for (i = 0; i != kStatusCount - 1; ++i)
	{
		if (legalStatus < statusThresholds[i])  return DescriptionStringAt(statusNames, i);
	}

	return DescriptionStringAt(statusNames, kStatusCount - 1);
}


std::optional<std::string> cxx_OODisplayStringFromAlertCondition(OOAlertCondition alertCondition)
{
	const oo::PList *conditionNamesEntry = UNIVERSE->descriptions()->find("condition");
	const oo::PList conditionNames = (conditionNamesEntry != nullptr) ? *conditionNamesEntry : oo::PList();
	return DescriptionStringAt(conditionNames, alertCondition);
}


std::optional<std::string> cxx_OODisplayStringFromShaderSetting(OOShaderSetting setting)
{
	// DESC() is Universe's description lookup (not migrated yet), converted at the call.
	switch (setting)
	{
		case SHADERS_NOT_SUPPORTED:	return OO_DESC("shaderfx-not-available");
		case SHADERS_OFF:			return OO_DESC("shaderfx-off");
		case SHADERS_SIMPLE:		return OO_DESC("shaderfx-simple");
		case SHADERS_FULL:			return OO_DESC("shaderfx-full");
	}

	return "??";
}


std::string cxx_OOStringFromShaderSetting(OOShaderSetting setting)
{
	switch (setting)
	{
		CASE(SHADERS_OFF);
		CASE(SHADERS_SIMPLE);
		CASE(SHADERS_FULL);
		CASE(SHADERS_NOT_SUPPORTED);
	}

	return "UNDEFINED";
}


OOShaderSetting cxx_OOShaderSettingFromString(const std::string &string)
{
	REVERSE_CASE(SHADERS_OFF);
	REVERSE_CASE(SHADERS_SIMPLE);
	REVERSE_CASE(SHADERS_FULL);
	REVERSE_CASE(SHADERS_NOT_SUPPORTED);

	return (OOShaderSetting)kOOShaderSettingDefault;
}


std::string cxx_CommodityDisplayNameForSymbolicName(const std::string &symbolicName)
{
	// -descriptionForKey: was NSStringOrNil of -cxx_descriptionForKey:, so nullopt reads as before.
	const std::optional<std::string> ret = (UNIVERSE != nullptr ? UNIVERSE->descriptionForKey("commodity-name " + oo::str::lowercase(symbolicName)) : std::optional<std::string>());
	return ret.has_value() ? *ret : symbolicName;
}


std::string cxx_CommodityDisplayNameForCommodityArray(const oo::PList &commodityDefinition)
{
	return cxx_CommodityDisplayNameForSymbolicName(commodityDefinition.at<std::string>(MARKET_NAME));
}


std::optional<std::string> cxx_DisplayStringForMassUnit(OOMassUnit unit)
{
	// DESC() is Universe's description lookup (not migrated yet), converted at the call.
	switch (unit)
	{
		case UNITS_TONS:  return OO_DESC("cargo-tons-symbol");
		case UNITS_KILOGRAMS:  return OO_DESC("cargo-kilograms-symbol");
		case UNITS_GRAMS:  return OO_DESC("cargo-grams-symbol");
		case UNITS_UNKNOWN:  break;
	}

	return "??";
}


std::optional<std::string> cxx_DisplayStringForMassUnitForCommodity(const std::string &commodity)
{
	// No market: -massUnitForGood: sent to nil answered 0, UNITS_TONS.
	OOCommodityMarket *market = (UNIVERSE != nullptr ? UNIVERSE->getCommodityMarket() : nullptr);
	return cxx_DisplayStringForMassUnit((market != nullptr) ? market->massUnitForGood(commodity) : UNITS_TONS);
}


OORouteType cxx_StringToRouteType(const std::string &string)
{
	REVERSE_CASE(OPTIMIZED_BY_NONE);
	REVERSE_CASE(OPTIMIZED_BY_JUMPS);
	REVERSE_CASE(OPTIMIZED_BY_TIME);
	
	return (OORouteType)kOORouteTypeDefault;
}


std::string cxx_DockingClearanceStatusToString(OODockingClearanceStatus dockingClearanceStatus)
{
	switch (dockingClearanceStatus)
	{
		CASE(DOCKING_CLEARANCE_STATUS_NONE);
		CASE(DOCKING_CLEARANCE_STATUS_REQUESTED);
		CASE(DOCKING_CLEARANCE_STATUS_NOT_REQUIRED);
		CASE(DOCKING_CLEARANCE_STATUS_GRANTED);
		CASE(DOCKING_CLEARANCE_STATUS_TIMING_OUT);
	}
	
	return "DOCKING_CLEARANCE_STATUS_UNKNOWN";
}


std::string cxx_OOStringFromGraphicsDetail(OOGraphicsDetail detail)
{
	switch (detail)
	{
		CASE(DETAIL_LEVEL_MINIMUM);
		CASE(DETAIL_LEVEL_NORMAL);
		CASE(DETAIL_LEVEL_SHADERS);
		CASE(DETAIL_LEVEL_EXTRAS);
	}
	
	return "DETAIL_LEVEL_UNKNOWN";
}


OOGraphicsDetail cxx_OOGraphicsDetailFromString(const std::string &string)
{
	REVERSE_CASE(DETAIL_LEVEL_MINIMUM);
	REVERSE_CASE(DETAIL_LEVEL_NORMAL);
	REVERSE_CASE(DETAIL_LEVEL_SHADERS);
	REVERSE_CASE(DETAIL_LEVEL_EXTRAS);
	
	return DETAIL_LEVEL_MINIMUM;
}


std::string cxx_OOStringFromHDRToneMapper(OOHDRToneMapper toneMapper)
{
	switch (toneMapper)
	{
		CASE(OOHDR_TONEMAPPER_NONE);
		CASE(OOHDR_TONEMAPPER_ACES_APPROX);
		CASE(OOHDR_TONEMAPPER_DICE);
		CASE(OOHDR_TONEMAPPER_UCHIMURA);
		CASE(OOHDR_TONEMAPPER_REINHARD);
	}
	
	return "OOHDR_TONEMAPPER_UNDEFINED";
}


OOHDRToneMapper cxx_OOHDRToneMapperFromString(const std::string &string)
{
	REVERSE_CASE(OOHDR_TONEMAPPER_NONE);
	REVERSE_CASE(OOHDR_TONEMAPPER_ACES_APPROX);
	REVERSE_CASE(OOHDR_TONEMAPPER_DICE);
	REVERSE_CASE(OOHDR_TONEMAPPER_UCHIMURA);
	REVERSE_CASE(OOHDR_TONEMAPPER_REINHARD);
	
	return OOHDR_TONEMAPPER_ACES_APPROX;
}


std::string cxx_OOStringFromSDRToneMapper(OOSDRToneMapper toneMapper)
{
	switch (toneMapper)
	{
		CASE(OOSDR_TONEMAPPER_NONE);
		CASE(OOSDR_TONEMAPPER_ACES);
		CASE(OOSDR_TONEMAPPER_AgX);
		CASE(OOSDR_TONEMAPPER_HEJLDAWSON);
		CASE(OOSDR_TONEMAPPER_UC2);
		CASE(OOSDR_TONEMAPPER_UCHIMURA);
		CASE(OOSDR_TONEMAPPER_REINHARD);
	}
	
	return "OOSDR_TONEMAPPER_UNDEFINED";
}


OOSDRToneMapper cxx_OOSDRToneMapperFromString(const std::string &string)
{
	REVERSE_CASE(OOSDR_TONEMAPPER_NONE);
	REVERSE_CASE(OOSDR_TONEMAPPER_ACES);
	REVERSE_CASE(OOSDR_TONEMAPPER_AgX);
	REVERSE_CASE(OOSDR_TONEMAPPER_HEJLDAWSON);
	REVERSE_CASE(OOSDR_TONEMAPPER_UC2);
	REVERSE_CASE(OOSDR_TONEMAPPER_UCHIMURA);
	REVERSE_CASE(OOSDR_TONEMAPPER_REINHARD);
	
	return OOSDR_TONEMAPPER_ACES;
}
