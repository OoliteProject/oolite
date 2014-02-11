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
	switch (weapon)
	{
		CASE(WEAPON_NONE);
		CASE(WEAPON_PLASMA_CANNON);
		CASE(WEAPON_PULSE_LASER);
		CASE(WEAPON_BEAM_LASER);
		CASE(WEAPON_MINING_LASER);
		CASE(WEAPON_MILITARY_LASER);
		CASE(WEAPON_THARGOID_LASER);
		CASE(WEAPON_UNDEFINED);
	}
	return @"Unknown weapon";
}


OOWeaponType OOWeaponTypeFromString(NSString *string)
{
	REVERSE_CASE(WEAPON_PLASMA_CANNON);
	REVERSE_CASE(WEAPON_PULSE_LASER);
	REVERSE_CASE(WEAPON_BEAM_LASER);
	REVERSE_CASE(WEAPON_MINING_LASER);
	REVERSE_CASE(WEAPON_MILITARY_LASER);
	REVERSE_CASE(WEAPON_THARGOID_LASER);
	
	return kOOWeaponTypeDefault;
}


NSString *OOEquipmentIdentifierFromWeaponType(OOWeaponType weapon)
{
#define EQ_CASE(foo) case foo: return @"EQ_"#foo;
	
	switch (weapon)
	{
	//	EQ_CASE(WEAPON_PLASMA_CANNON);
		case WEAPON_PLASMA_CANNON: return @"EQ_WEAPON_TWIN_PLASMA_CANNON";
		EQ_CASE(WEAPON_PULSE_LASER);
		EQ_CASE(WEAPON_BEAM_LASER);
		EQ_CASE(WEAPON_MINING_LASER);
		EQ_CASE(WEAPON_MILITARY_LASER);
		EQ_CASE(WEAPON_THARGOID_LASER);
		
		case WEAPON_NONE:
		case WEAPON_UNDEFINED:
			break;
	}
	return nil;
#undef EQ_CASE
}


OOWeaponType OOWeaponTypeFromEquipmentIdentifierSloppy(NSString *string)
{
#define EQ_REVERSE_CASE(foo) if ([string hasSuffix:@#foo]) return WEAPON_##foo;
	EQ_REVERSE_CASE(PLASMA_CANNON); // required in playerEntityControls (case GUI_SCREEN_EQUIP_SHIP)
	EQ_REVERSE_CASE(PULSE_LASER);
	EQ_REVERSE_CASE(BEAM_LASER);
	EQ_REVERSE_CASE(MINING_LASER);
	EQ_REVERSE_CASE(MILITARY_LASER);
	EQ_REVERSE_CASE(THARGOID_LASER);
	
	return kOOWeaponTypeDefault;
#undef EQ_REVERSE_CASE
}


OOWeaponType OOWeaponTypeFromEquipmentIdentifierStrict(NSString *string)
{
#define EQ_REVERSE_CASE(foo) if ([string isEqualToString:@"EQ_WEAPON_" #foo]) return WEAPON_##foo;
//	EQ_REVERSE_CASE(PLASMA_CANNON);
	if ([string isEqual:@"EQ_WEAPON_TWIN_PLASMA_CANNON"]) return WEAPON_PLASMA_CANNON;
	EQ_REVERSE_CASE(PULSE_LASER);
	EQ_REVERSE_CASE(BEAM_LASER);
	EQ_REVERSE_CASE(MINING_LASER);
	EQ_REVERSE_CASE(MILITARY_LASER);
	EQ_REVERSE_CASE(THARGOID_LASER);
	
	return kOOWeaponTypeDefault;
#undef EQ_REVERSE_CASE
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


NSString *CommodityTypeToString(OOCommodityType commodity) // returns the commodity identifier
{
#define CO_CASE(foo) case COMMODITY_##foo: return [@""#foo lowercaseString];
	switch (commodity)
	{
/*
		// 'old style' commodity identifiers.
		case COMMODITY_LIQUOR_WINES: return @"liquor/wines";
		case COMMODITY_GEM_STONES: return @"gem-stones";
		case COMMODITY_ALIEN_ITEMS: return @"alien items";
*/

		// normalised commodity identifiers
		CO_CASE(LIQUOR_WINES);
		CO_CASE(GEM_STONES);
		CO_CASE(ALIEN_ITEMS);
		
		CO_CASE(FOOD);
		CO_CASE(TEXTILES);
		CO_CASE(RADIOACTIVES);
		CO_CASE(SLAVES);
		CO_CASE(LUXURIES);
		CO_CASE(NARCOTICS);
		CO_CASE(COMPUTERS);
		CO_CASE(MACHINERY);
		CO_CASE(ALLOYS);
		CO_CASE(FIREARMS);
		CO_CASE(FURS);
		CO_CASE(MINERALS);
		CO_CASE(GOLD);
		CO_CASE(PLATINUM);
			
		case COMMODITY_UNDEFINED:
			break;
	}
	return @"goods";	// was "unknown commodity"
#undef CO_CASE
}


OOCommodityType StringToCommodityType(NSString *string) // needs commodity identifier
{
#define CO_REVERSE_CASE(foo) if ([[string uppercaseString] isEqual:@""#foo]) return COMMODITY_##foo;

	// Backward compatibility - 'old style' commodity identifier strings.
	if ([[string lowercaseString] isEqual:@"liquor/wines"]) return COMMODITY_LIQUOR_WINES;
	if ([[string lowercaseString] isEqual:@"gem-stones"]) return COMMODITY_GEM_STONES;
	if ([[string lowercaseString] isEqual:@"alien items"]) return COMMODITY_ALIEN_ITEMS;
	
	CO_REVERSE_CASE(LIQUOR_WINES);
	CO_REVERSE_CASE(GEM_STONES);
	CO_REVERSE_CASE(ALIEN_ITEMS);
	CO_REVERSE_CASE(FOOD);
	CO_REVERSE_CASE(TEXTILES);
	CO_REVERSE_CASE(RADIOACTIVES);
	CO_REVERSE_CASE(SLAVES);
	CO_REVERSE_CASE(LUXURIES);
	CO_REVERSE_CASE(NARCOTICS);
	CO_REVERSE_CASE(COMPUTERS);
	CO_REVERSE_CASE(MACHINERY);
	CO_REVERSE_CASE(ALLOYS);
	CO_REVERSE_CASE(FIREARMS);
	CO_REVERSE_CASE(FURS);
	CO_REVERSE_CASE(MINERALS);
	CO_REVERSE_CASE(GOLD);
	CO_REVERSE_CASE(PLATINUM);
	
	return kOOCommodityTypeDefault;	//COMMODITY_UNDEFINED
#undef CO_REVERSE_CASE
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
	return DisplayStringForMassUnit([UNIVERSE unitsForCommodity:commodity]);
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
