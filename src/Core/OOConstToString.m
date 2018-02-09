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

#import "OOConstToString.h"
#include <jsapi.h>
#import "OOCollectionExtractors.h"

#import "Universe.h"
#import "PlayerEntity.h"
#import "OOEquipmentType.h"

#define CASE(foo) case foo: return @#foo;
#define REVERSE_CASE(foo) if ([string isEqualToString:@#foo]) return foo;


#define ENTRY(label, value) case label: return @#label;
#define GALACTIC_HYPERSPACE_ENTRY(label, value) case GALACTIC_HYPERSPACE_##label: return @#label;
#define DIFF_STRING_ENTRY(label, string) case label: return @string;

NSString *OOStringFromEntityStatus(OOEntityStatus value)
{
	switch (value)
	{
		#include "OOEntityStatus.tbl"
	}
	return @"UNDEFINED";
}


NSString *OOStringFromBehaviour(OOBehaviour value)
{
	switch (value)
	{
		#include "OOBehaviour.tbl"
	}
	
	return @"** BEHAVIOUR UNKNOWN **";
}


NSString *OOStringFromCompassMode(OOCompassMode value)
{
	switch (value)
	{
		#include "OOCompassMode.tbl"
	}
	
	return @"UNDEFINED";
}

NSString *OOStringFromLongRangeChartMode(OOLongRangeChartMode value)
{
	switch (value)
	{
		#include "OOLongRangeChartMode.tbl"
	}

	return @"UNDEFINED";
}

NSString *OOStringFromGalacticHyperspaceBehaviour(OOGalacticHyperspaceBehaviour value)
{
	switch (value)
	{
		#include "OOGalacticHyperspaceBehaviour.tbl"
	}
	
	return @"UNDEFINED";
}


NSString *OOStringFromGUIScreenID(OOGUIScreenID value)
{
	switch (value)
	{
		#include "OOGUIScreenID.tbl"
	}
	
	return @"UNDEFINED";
}


NSString *OOStringFromScanClass(OOScanClass value)
{
	switch (value)
	{
		#include "OOScanClass.tbl"
	}
	
	return @"UNDEFINED";
}


NSString *OOStringFromShipDamageType(OOShipDamageType value)
{
	switch (value)
	{
		#include "OOShipDamageType.tbl"
	}
	
	return @"UNDEFINED";
}

NSString *OOStringFromLegalStatusReason(OOLegalStatusReason value)
{
	switch (value)
	{
		#include "OOLegalStatusReason.tbl"
	}
	
	return @"UNDEFINED";
}


#undef ENTRY
#undef GALACTIC_HYPERSPACE_ENTRY


#define ENTRY(label, value) if ([string isEqualToString:@#label])  return label;
#define GALACTIC_HYPERSPACE_ENTRY(label, value)	if ([string isEqualToString:@#label])  return GALACTIC_HYPERSPACE_##label;

OOEntityStatus OOEntityStatusFromString(NSString *string)
{
	#include "OOEntityStatus.tbl"
	
	return kOOEntityStatusDefault;
}


OOCompassMode OOCompassModeFromString(NSString *string)
{
	#include "OOCompassMode.tbl"
	
	return kOOCompassModeDefault;
}


OOGalacticHyperspaceBehaviour OOGalacticHyperspaceBehaviourFromString(NSString *string)
{
	#include "OOGalacticHyperspaceBehaviour.tbl"
	
	// Transparently (but inefficiently) support american spelling. FIXME: remove in EMMSTRAN.
	if ([string hasPrefix:@"BEHAVIOR_"])
	{
		string = [string substringFromIndex:[@"BEHAVIOR_" length]];
		string = [@"BEHAVIOUR_" stringByAppendingString:string];
		return OOGalacticHyperspaceBehaviourFromString(string);
	}
	
	return kOOGalacticHyperspaceBehaviourDefault;
}


OOGUIScreenID OOGUIScreenIDFromString(NSString *string)
{
	#include "OOGUIScreenID.tbl"
	
	return kOOGUIScreenIDDefault;
}


OOScanClass OOScanClassFromString(NSString *string)
{
	#include "OOScanClass.tbl"
	
	return kOOScanClassDefault;
}

OOLongRangeChartMode OOLongRangeChartModeFromString(NSString *string)
{
	#include "OOLongRangeChartMode.tbl"
	
	return kOOLongRangeChartModeDefault;
}

#undef ENTRY
#undef GALACTIC_HYPERSPACE_ENTRY


NSString *RouteTypeToString(OORouteType routeType)
{
	switch (routeType)
	{
		CASE(OPTIMIZED_BY_NONE);
		CASE(OPTIMIZED_BY_JUMPS);
		CASE(OPTIMIZED_BY_TIME);
	}
	
	return @"** ROUTE TYPE UNKNOWN **";
}


NSString *OODisplayStringFromGovernmentID(OOGovernmentID government)
{
	NSArray		*strings = nil;
	NSString	*value = nil;
	
	strings = [[UNIVERSE descriptions] objectForKey:@"government"]; 
	if ([strings isKindOfClass:[NSArray class]] && government < [strings count])
	{
		value = [strings objectAtIndex:government];
		if ([value isKindOfClass:[NSString class]]) return value;
	}
	
	return nil;
}


NSString *OODisplayStringFromEconomyID(OOEconomyID economy)
{
	NSArray		*strings = nil;
	NSString	*value = nil;
	
	strings = [[UNIVERSE descriptions] objectForKey:@"economy"]; 
	if ([strings isKindOfClass:[NSArray class]] && economy < [strings count])
	{
		value = [strings objectAtIndex:economy];
		if ([value isKindOfClass:[NSString class]]) return value;
	}
	
	return nil;
}


NSString *JSTypeToString(int /* JSType */ type)
{
	switch ((JSType)type)
	{
		CASE(JSTYPE_VOID);
		CASE(JSTYPE_OBJECT);
		CASE(JSTYPE_FUNCTION);
		CASE(JSTYPE_STRING);
		CASE(JSTYPE_NUMBER);
		CASE(JSTYPE_BOOLEAN);
		CASE(JSTYPE_NULL);
		CASE(JSTYPE_XML);
		CASE(JSTYPE_LIMIT);
	}
	return [NSString stringWithFormat:@"unknown (%u)", type];
}


NSString *OOStringFromWeaponType(OOWeaponType weapon)
{
	if (weapon == nil) {
		return @"EQ_WEAPON_NONE";
	} else {
		return [weapon identifier];
	}
}


OOWeaponType OOWeaponTypeFromString(NSString *string)
{
	return OOWeaponTypeFromEquipmentIdentifierSloppy(string);
}


NSString *OOEquipmentIdentifierFromWeaponType(OOWeaponType weapon)
{
	return [weapon identifier];
}


OOWeaponType OOWeaponTypeFromEquipmentIdentifierSloppy(NSString *string)
{
	OOWeaponType w = [OOEquipmentType equipmentTypeWithIdentifier:string];
	if (w == nil)
	{
		if (![string hasPrefix:@"EQ_"])
		{
			w = [OOEquipmentType equipmentTypeWithIdentifier:[NSString stringWithFormat:@"EQ_%@",string]];
			if (w != nil)
			{
				return w;
			}
		}
		return [OOEquipmentType equipmentTypeWithIdentifier:@"EQ_WEAPON_NONE"];
	}
	return w;
}


/* Previous save games will have weapon types stored as ints to the
 * various weapon types */
OOWeaponType OOWeaponTypeFromEquipmentIdentifierLegacy(NSString *string)
{
	if ([string intValue] > 0)
	{
		switch ([string intValue])
		{
		case 2:
			return OOWeaponTypeFromEquipmentIdentifierSloppy(@"EQ_WEAPON_PULSE_LASER");
		case 3:
			return OOWeaponTypeFromEquipmentIdentifierSloppy(@"EQ_WEAPON_BEAM_LASER");
		case 4:
			return OOWeaponTypeFromEquipmentIdentifierSloppy(@"EQ_WEAPON_MINING_LASER");
		case 5:
			return OOWeaponTypeFromEquipmentIdentifierSloppy(@"EQ_WEAPON_MILITARY_LASER");
		case 10:
			return OOWeaponTypeFromEquipmentIdentifierSloppy(@"EQ_WEAPON_THARGOID_LASER");
		default:
			return OOWeaponTypeFromEquipmentIdentifierSloppy(string);
		}
	}
	return OOWeaponTypeFromEquipmentIdentifierSloppy(string);
}


OOWeaponType OOWeaponTypeFromEquipmentIdentifierStrict(NSString *string)
{
	// there is no difference between the two any more
	return OOWeaponTypeFromEquipmentIdentifierSloppy(string);
}


NSString *CargoTypeToString(OOCargoType cargo)
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
	return @"Unknown cargo";
}


OOCargoType StringToCargoType(NSString *string)
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
	if ([string isEqual:@"CARGO_CARRIED"]) return CARGO_RANDOM;
	
	return kOOCargoTypeDefault;
}


NSString *EnergyUnitTypeToString(OOEnergyUnitType unit)
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
	
	return @"Unsupported energy unit";
}


OOEnergyUnitType StringToEnergyUnitType(NSString *string)
{
	REVERSE_CASE(ENERGY_UNIT_NONE);
	REVERSE_CASE(ENERGY_UNIT_NORMAL);
	REVERSE_CASE(ENERGY_UNIT_NAVAL);
	REVERSE_CASE(ENERGY_UNIT_NORMAL_DAMAGED);
	REVERSE_CASE(ENERGY_UNIT_NAVAL_DAMAGED);
	
	return kOOEnergyUnitTypeDefault;
}


NSString *OODisplayRatingStringFromKillCount(unsigned kills)
{
	enum { kRatingCount = 9 };
	
	NSArray				*ratingNames = nil;
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
	
	ratingNames = [[UNIVERSE descriptions] oo_arrayForKey:@"rating"];
	for (i = 0; i < kRatingCount - 1; ++i)
	{
		if (kills < killThresholds[i])  return [ratingNames oo_stringAtIndex:i];
	}
	
	return [ratingNames oo_stringAtIndex:kRatingCount - 1];
}


NSString *KillCountToRatingAndKillString(unsigned kills)
{
	return [NSString stringWithFormat:@"%@   (%u)", OODisplayRatingStringFromKillCount(kills), kills];
}


NSString *OODisplayStringFromLegalStatus(int legalStatus)
{
	enum { kStatusCount = 3 };
	
	NSArray				*statusNames = nil;
	const int			statusThresholds[kStatusCount - 1] =
						{
							1,
							51
						};
	unsigned			i;
	
	statusNames = [[UNIVERSE descriptions] oo_arrayForKey:@"legal_status"];
	for (i = 0; i != kStatusCount - 1; ++i)
	{
		if (legalStatus < statusThresholds[i])  return [statusNames oo_stringAtIndex:i];
	}
	
	return [statusNames oo_stringAtIndex:kStatusCount - 1];
}


NSString *OODisplayStringFromAlertCondition(OOAlertCondition alertCondition)
{
	NSArray *conditionNames = [[UNIVERSE descriptions] oo_arrayForKey:@"condition"];
	return [conditionNames oo_stringAtIndex:alertCondition];
}


NSString *OODisplayStringFromShaderSetting(OOShaderSetting setting)
{
	switch (setting)
	{
		case SHADERS_NOT_SUPPORTED:	return DESC(@"shaderfx-not-available");
		case SHADERS_OFF:			return DESC(@"shaderfx-off");
		case SHADERS_SIMPLE:		return DESC(@"shaderfx-simple");
		case SHADERS_FULL:			return DESC(@"shaderfx-full");
	}
	
	return @"??";
}


NSString *OOStringFromShaderSetting(OOShaderSetting setting)
{
	switch (setting)
	{
		CASE(SHADERS_OFF);
		CASE(SHADERS_SIMPLE);
		CASE(SHADERS_FULL);
		CASE(SHADERS_NOT_SUPPORTED);
	}
	
	return @"UNDEFINED";
}


OOShaderSetting OOShaderSettingFromString(NSString *string)
{
	REVERSE_CASE(SHADERS_OFF);
	REVERSE_CASE(SHADERS_SIMPLE);
	REVERSE_CASE(SHADERS_FULL);
	REVERSE_CASE(SHADERS_NOT_SUPPORTED);
	
	return kOOShaderSettingDefault;
}


NSString *CommodityDisplayNameForSymbolicName(NSString *symbolicName)
{
	NSString *ret = [UNIVERSE descriptionForKey:[@"commodity-name " stringByAppendingString:[symbolicName lowercaseString]]];
	return ret ? ret : symbolicName;
}


NSString *CommodityDisplayNameForCommodityArray(NSArray *commodityDefinition)
{
	return CommodityDisplayNameForSymbolicName([commodityDefinition oo_stringAtIndex:MARKET_NAME]);
}


NSString *DisplayStringForMassUnit(OOMassUnit unit)
{
	switch (unit)
	{
		case UNITS_TONS:  return DESC(@"cargo-tons-symbol");
		case UNITS_KILOGRAMS:  return DESC(@"cargo-kilograms-symbol");
		case UNITS_GRAMS:  return DESC(@"cargo-grams-symbol");
	}
	
	return @"??";
}


NSString *DisplayStringForMassUnitForCommodity(OOCommodityType commodity)
{
	return DisplayStringForMassUnit([[UNIVERSE commodityMarket] massUnitForGood:commodity]);
}


OORouteType StringToRouteType(NSString *string)
{
	REVERSE_CASE(OPTIMIZED_BY_NONE);
	REVERSE_CASE(OPTIMIZED_BY_JUMPS);
	REVERSE_CASE(OPTIMIZED_BY_TIME);
	
	return kOORouteTypeDefault;
}


NSString *DockingClearanceStatusToString(OODockingClearanceStatus dockingClearanceStatus)
{
	switch (dockingClearanceStatus)
	{
		CASE(DOCKING_CLEARANCE_STATUS_NONE);
		CASE(DOCKING_CLEARANCE_STATUS_REQUESTED);
		CASE(DOCKING_CLEARANCE_STATUS_NOT_REQUIRED);
		CASE(DOCKING_CLEARANCE_STATUS_GRANTED);
		CASE(DOCKING_CLEARANCE_STATUS_TIMING_OUT);
	}
	
	return @"DOCKING_CLEARANCE_STATUS_UNKNOWN";
}


NSString *OOStringFromGraphicsDetail(OOGraphicsDetail detail)
{
	switch (detail)
	{
		CASE(DETAIL_LEVEL_MINIMUM);
		CASE(DETAIL_LEVEL_NORMAL);
		CASE(DETAIL_LEVEL_SHADERS);
		CASE(DETAIL_LEVEL_EXTRAS);
	}
	
	return @"DETAIL_LEVEL_UNKNOWN";
}


OOGraphicsDetail OOGraphicsDetailFromString(NSString *string)
{
	REVERSE_CASE(DETAIL_LEVEL_MINIMUM);
	REVERSE_CASE(DETAIL_LEVEL_NORMAL);
	REVERSE_CASE(DETAIL_LEVEL_SHADERS);
	REVERSE_CASE(DETAIL_LEVEL_EXTRAS);
	
	return DETAIL_LEVEL_MINIMUM;
}
