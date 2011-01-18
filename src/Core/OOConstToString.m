/*

OOConstToString.m

Oolite
Copyright (C) 2004-2011 Giles C Williams and contributors

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
#import <jsapi.h>
#import "OOCollectionExtractors.h"

#import "Universe.h"
#import "PlayerEntity.h"
#import "OOInstinct.h"


#define CASE(foo) case foo: return @#foo;
#define REVERSE_CASE(foo) if ([string isEqualToString:@#foo]) return foo;


#define ENTRY(label, value) case label: return @#label;

NSString *OOStringFromEntityStatus(OOEntityStatus status)
{
	switch (status)
	{
		#include "OOEntityStatus.tbl"
	}
	return @"UNDEFINED";
}


NSString *OOStringFromScanClass(OOScanClass scanClass)
{
	switch (scanClass)
	{
		#include "OOScanClass.tbl"
	}
	
	return @"UNDEFINED";
}


NSString *OOStringFromBehaviour(OOBehaviour behaviour)
{
	switch (behaviour)
	{
		#include "OOBehaviour.tbl"
	}
	
	return @"** BEHAVIOUR UNKNOWN **";
}

#undef ENTRY


#define ENTRY(label, value) if ([string isEqualToString:@#label]) return label;

OOEntityStatus OOEntityStatusFromString(NSString *string)
{
	#include "OOEntityStatus.tbl"
	
	return kOOEntityStatusDefault;
}


OOScanClass OOScanClassFromString(NSString *string)
{
	#include "OOScanClass.tbl"
	
	return kOOScanClassDefault;
}

#undef ENTRY


#ifdef OO_BRAIN_AI
NSString *OOStringFromInstinctID(OOInstinctID instinct)
{
	switch (instinct)
	{
		CASE(INSTINCT_ATTACK_PREY);
		CASE(INSTINCT_AVOID_PREDATORS);
		CASE(INSTINCT_AVOID_HAZARDS);
		CASE(INSTINCT_FIGHT_OR_FLIGHT);
		CASE(INSTINCT_FLOCK_ALIKE);
		CASE(INSTINCT_FOLLOW_AI);
		CASE(INSTINCT_NULL);
	}
	
	return @"INSTINCT_UNKNOWN";
}


OOInstinctID OOInstinctIDFromString(NSString *string)
{
	REVERSE_CASE(INSTINCT_ATTACK_PREY);
	REVERSE_CASE(INSTINCT_AVOID_PREDATORS);
	REVERSE_CASE(INSTINCT_AVOID_HAZARDS);
	REVERSE_CASE(INSTINCT_FIGHT_OR_FLIGHT);
	REVERSE_CASE(INSTINCT_FLOCK_ALIKE);
	REVERSE_CASE(INSTINCT_FOLLOW_AI);
	
	return kOOInstinctIDDefault;
}
#endif


NSString *ViewIDToString(OOViewID viewID)
{
	switch (viewID)
	{
		CASE(VIEW_FORWARD);
		CASE(VIEW_AFT);
		CASE(VIEW_PORT);
		CASE(VIEW_STARBOARD);
		CASE(VIEW_CUSTOM);
		CASE(VIEW_NONE);
		CASE(VIEW_GUI_DISPLAY);
		CASE(VIEW_BREAK_PATTERN);
	}
	
	return @"UNDEFINED";
}


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
			
		case CARGO_UNDEFINED:
			break;
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


/*
// post MNSR stuff.
NSString *CommodityTypeToOldString(OOCommodityType commodity) // returns the old commodity identifier
{
	switch (commodity)
	{
		case COMMODITY_LIQUOR_WINES: return @"liquor/wines";
		case COMMODITY_GEM_STONES: return @"gem-stones";
		case COMMODITY_ALIEN_ITEMS: return @"alien items";
	}
	return CommodityTypeToString(commodity);
}
*/


NSString *CommodityTypeToString(OOCommodityType commodity) // returns the commodity identifier
{
#define CO_CASE(foo) case COMMODITY_##foo: return [@""#foo lowercaseString];
	switch (commodity)
	{
		case COMMODITY_LIQUOR_WINES: return @"liquor/wines";
		case COMMODITY_GEM_STONES: return @"gem-stones";
		case COMMODITY_ALIEN_ITEMS: return @"alien items";
/*
		// normalised commodity identifiers, for post MNSR
		
		//case COMMODITY_LIQUOR_WINES: return @"liquor_wines";
		//case COMMODITY_GEM_STONES: return @"gem_stones";
		//case COMMODITY_ALIEN_ITEMS: return @"alien_items";
		
		CO_CASE(LIQUOR_WINES);
		CO_CASE(GEM_STONES);
		CO_CASE(ALIEN_ITEMS);
 
*/	
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
	return @"unknown commodity";
#undef CO_CASE
}


OOCommodityType StringToCommodityType(NSString *string) // needs commodity identifier
{
#define CO_REVERSE_CASE(foo) if ([[string uppercaseString] isEqual:@""#foo]) return COMMODITY_##foo;

	if ([[string lowercaseString] isEqual:@"liquor/wines"]) return COMMODITY_LIQUOR_WINES;
	if ([[string lowercaseString] isEqual:@"gem-stones"]) return COMMODITY_GEM_STONES;
	if ([[string lowercaseString] isEqual:@"alien items"]) return COMMODITY_ALIEN_ITEMS;
	// also test for normalised commodity identifiers - in readiness for post MNSR
	if ([[string lowercaseString] isEqual:@"liquor_wines"]) return COMMODITY_LIQUOR_WINES;
	if ([[string lowercaseString] isEqual:@"gem_stones"]) return COMMODITY_GEM_STONES;
	if ([[string lowercaseString] isEqual:@"alien_items"]) return COMMODITY_ALIEN_ITEMS;

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
	
	return kOOCommodityTypeDefault;
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


NSString *GUIScreenIDToString(OOGUIScreenID screen)
{
	switch (screen)
	{
		CASE(GUI_SCREEN_MAIN);
		CASE(GUI_SCREEN_INTRO1);
		CASE(GUI_SCREEN_INTRO2);
		CASE(GUI_SCREEN_STATUS);
		CASE(GUI_SCREEN_MANIFEST);
		CASE(GUI_SCREEN_EQUIP_SHIP);
		CASE(GUI_SCREEN_SHIPYARD);
		CASE(GUI_SCREEN_LONG_RANGE_CHART);
		CASE(GUI_SCREEN_SHORT_RANGE_CHART);
		CASE(GUI_SCREEN_SYSTEM_DATA);
		CASE(GUI_SCREEN_MARKET);
		CASE(GUI_SCREEN_CONTRACTS);
		CASE(GUI_SCREEN_OPTIONS);
		CASE(GUI_SCREEN_GAMEOPTIONS);
		CASE(GUI_SCREEN_LOAD);
		CASE(GUI_SCREEN_SAVE);
		CASE(GUI_SCREEN_SAVE_OVERWRITE);
		CASE(GUI_SCREEN_STICKMAPPER);
		CASE(GUI_SCREEN_MISSION);
		CASE(GUI_SCREEN_REPORT);
	}
	
	return @"UNDEFINED";
}


OOGUIScreenID StringToGUIScreenID(NSString *string)
{
	REVERSE_CASE(GUI_SCREEN_MAIN);
	REVERSE_CASE(GUI_SCREEN_INTRO1);
	REVERSE_CASE(GUI_SCREEN_INTRO2);
	REVERSE_CASE(GUI_SCREEN_STATUS);
	REVERSE_CASE(GUI_SCREEN_MANIFEST);
	REVERSE_CASE(GUI_SCREEN_EQUIP_SHIP);
	REVERSE_CASE(GUI_SCREEN_SHIPYARD);
	REVERSE_CASE(GUI_SCREEN_LONG_RANGE_CHART);
	REVERSE_CASE(GUI_SCREEN_SHORT_RANGE_CHART);
	REVERSE_CASE(GUI_SCREEN_SYSTEM_DATA);
	REVERSE_CASE(GUI_SCREEN_MARKET);
	REVERSE_CASE(GUI_SCREEN_CONTRACTS);
	REVERSE_CASE(GUI_SCREEN_OPTIONS);
	REVERSE_CASE(GUI_SCREEN_LOAD);
	REVERSE_CASE(GUI_SCREEN_SAVE);
	REVERSE_CASE(GUI_SCREEN_SAVE_OVERWRITE);
	REVERSE_CASE(GUI_SCREEN_STICKMAPPER);
	REVERSE_CASE(GUI_SCREEN_MISSION);
	REVERSE_CASE(GUI_SCREEN_REPORT);
	
	return kOOGUIScreenIDDefault;
}


OOGalacticHyperspaceBehaviour StringToGalacticHyperspaceBehaviour(NSString *string)
{
	if ([string isEqualToString:@"BEHAVIOUR_STANDARD"] || [string isEqualToString:@"BEHAVIOR_STANDARD"])
	{
		return GALACTIC_HYPERSPACE_BEHAVIOUR_STANDARD;
	}
	if ([string isEqualToString:@"BEHAVIOUR_ALL_SYSTEMS_REACHABLE"] || [string isEqualToString:@"BEHAVIOR_ALL_SYSTEMS_REACHABLE"])
	{
		return GALACTIC_HYPERSPACE_BEHAVIOUR_ALL_SYSTEMS_REACHABLE;
	}
	if ([string isEqualToString:@"BEHAVIOUR_FIXED_COORDINATES"] || [string isEqualToString:@"BEHAVIOR_FIXED_COORDINATES"])
	{
		return GALACTIC_HYPERSPACE_BEHAVIOUR_FIXED_COORDINATES;
	}
	
	return kOOGalacticHyperspaceBehaviourDefault;
}


NSString *GalacticHyperspaceBehaviourToString(OOGalacticHyperspaceBehaviour behaviour)
{
	switch (behaviour)
	{
		case GALACTIC_HYPERSPACE_BEHAVIOUR_STANDARD:
			return @"BEHAVIOUR_STANDARD";
			
		case GALACTIC_HYPERSPACE_BEHAVIOUR_ALL_SYSTEMS_REACHABLE:
			return @"BEHAVIOUR_ALL_SYSTEMS_REACHABLE";
			
		case GALACTIC_HYPERSPACE_BEHAVIOUR_FIXED_COORDINATES:
			return @"BEHAVIOUR_FIXED_COORDINATES";
		
		case GALACTIC_HYPERSPACE_BEHAVIOUR_UNKNOWN:
			break;
	}
	
	return @"UNDEFINED";
}


NSString *KillCountToRatingString(unsigned kills)
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
	return [NSString stringWithFormat:@"%@   (%u)", KillCountToRatingString(kills), kills];
}


NSString *LegalStatusToString(int legalStatus)
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


NSString *DisplayStringForMassUnitForCommodity(OOCargoType commodity)
{
	return DisplayStringForMassUnit([UNIVERSE unitsForCommodity:commodity]);
}


NSString *CompassModeToString(OOCompassMode mode)
{
	switch (mode)
	{
		CASE(COMPASS_MODE_BASIC);
		CASE(COMPASS_MODE_PLANET);
		CASE(COMPASS_MODE_STATION);
		CASE(COMPASS_MODE_SUN);
		CASE(COMPASS_MODE_TARGET);
		CASE(COMPASS_MODE_BEACONS);
	}
	
	return @"Unsupported";
}

OOCompassMode StringToCompassMode(NSString *string)
{
	REVERSE_CASE(COMPASS_MODE_BASIC);
	REVERSE_CASE(COMPASS_MODE_PLANET);
	REVERSE_CASE(COMPASS_MODE_STATION);
	REVERSE_CASE(COMPASS_MODE_SUN);
	REVERSE_CASE(COMPASS_MODE_TARGET);
	REVERSE_CASE(COMPASS_MODE_BEACONS);
	
	return kOOCompassModeDefault;
}


OORouteType StringToRouteType(NSString *string)
{
	REVERSE_CASE(OPTIMIZED_BY_NONE);
	REVERSE_CASE(OPTIMIZED_BY_JUMPS);
	REVERSE_CASE(OPTIMIZED_BY_TIME);
	
	return kOORouteTypeDefault;
}


#if DOCKING_CLEARANCE_ENABLED
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
#endif
