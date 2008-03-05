/*

OOConstToString.m

Oolite
Copyright (C) 2004-2008 Giles C Williams and contributors

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
#import "Entity.h"
#import "Universe.h"
#import <jsapi.h>
#import "OOCollectionExtractors.h"


#define CASE(foo) case foo: return @#foo;
#define REVERSE_CASE(foo) if ([string isEqualToString:@#foo]) return foo;


NSString *EntityStatusToString(OOEntityStatus status)
{
	switch (status)
	{
		CASE(STATUS_EFFECT);
		CASE(STATUS_ACTIVE);
		CASE(STATUS_COCKPIT_DISPLAY);
		CASE(STATUS_TEST);
		CASE(STATUS_INACTIVE);
		CASE(STATUS_DEAD);
		CASE(STATUS_START_GAME);
		CASE(STATUS_IN_FLIGHT);
		CASE(STATUS_DOCKED);
		CASE(STATUS_AUTOPILOT_ENGAGED);
		CASE(STATUS_DOCKING);
		CASE(STATUS_LAUNCHING);
		CASE(STATUS_WITCHSPACE_COUNTDOWN);
		CASE(STATUS_ENTERING_WITCHSPACE);
		CASE(STATUS_EXITING_WITCHSPACE);
		CASE(STATUS_ESCAPE_SEQUENCE);
		CASE(STATUS_IN_HOLD);
		CASE(STATUS_BEING_SCOOPED);
		CASE(STATUS_HANDLING_ERROR);
	}
	
	return @"UNDEFINED";
}


OOEntityStatus StringToEntityStatus(NSString *string)
{
	REVERSE_CASE(STATUS_EFFECT);
	REVERSE_CASE(STATUS_ACTIVE);
	REVERSE_CASE(STATUS_COCKPIT_DISPLAY);
	REVERSE_CASE(STATUS_TEST);
	REVERSE_CASE(STATUS_INACTIVE);
	REVERSE_CASE(STATUS_DEAD);
	REVERSE_CASE(STATUS_START_GAME);
	REVERSE_CASE(STATUS_IN_FLIGHT);
	REVERSE_CASE(STATUS_DOCKED);
	REVERSE_CASE(STATUS_AUTOPILOT_ENGAGED);
	REVERSE_CASE(STATUS_DOCKING);
	REVERSE_CASE(STATUS_LAUNCHING);
	REVERSE_CASE(STATUS_WITCHSPACE_COUNTDOWN);
	REVERSE_CASE(STATUS_ENTERING_WITCHSPACE);
	REVERSE_CASE(STATUS_EXITING_WITCHSPACE);
	REVERSE_CASE(STATUS_ESCAPE_SEQUENCE);
	REVERSE_CASE(STATUS_IN_HOLD);
	REVERSE_CASE(STATUS_BEING_SCOOPED);
	REVERSE_CASE(STATUS_HANDLING_ERROR);
	
	return STATUS_INACTIVE;
}


NSString *ScanClassToString(OOScanClass scanClass)
{
	switch (scanClass)
	{
		CASE(CLASS_NOT_SET);
		CASE(CLASS_NO_DRAW);
		CASE(CLASS_NEUTRAL);
		CASE(CLASS_STATION);
		CASE(CLASS_TARGET);
		CASE(CLASS_CARGO);
		CASE(CLASS_MISSILE);
		CASE(CLASS_ROCK);
		CASE(CLASS_MINE);
		CASE(CLASS_THARGOID);
		CASE(CLASS_BUOY);
		CASE(CLASS_WORMHOLE);
		CASE(CLASS_PLAYER);
		CASE(CLASS_POLICE);
		CASE(CLASS_MILITARY);
	}
	
	return @"UNDEFINED";
}


OOScanClass StringToScanClass(NSString *string)
{
	REVERSE_CASE(CLASS_NOT_SET);
	REVERSE_CASE(CLASS_NO_DRAW);
	REVERSE_CASE(CLASS_NEUTRAL);
	REVERSE_CASE(CLASS_STATION);
	REVERSE_CASE(CLASS_TARGET);
	REVERSE_CASE(CLASS_CARGO);
	REVERSE_CASE(CLASS_MISSILE);
	REVERSE_CASE(CLASS_ROCK);
	REVERSE_CASE(CLASS_MINE);
	REVERSE_CASE(CLASS_THARGOID);
	REVERSE_CASE(CLASS_BUOY);
	REVERSE_CASE(CLASS_WORMHOLE);
	REVERSE_CASE(CLASS_PLAYER);
	REVERSE_CASE(CLASS_POLICE);
	REVERSE_CASE(CLASS_MILITARY);
	
	return CLASS_NOT_SET;
}


NSString *InstinctToString(OOInstinctID instinct)
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


OOInstinctID StringToInstinct(NSString *string)
{
	REVERSE_CASE(INSTINCT_ATTACK_PREY);
	REVERSE_CASE(INSTINCT_AVOID_PREDATORS);
	REVERSE_CASE(INSTINCT_AVOID_HAZARDS);
	REVERSE_CASE(INSTINCT_FIGHT_OR_FLIGHT);
	REVERSE_CASE(INSTINCT_FLOCK_ALIKE);
	REVERSE_CASE(INSTINCT_FOLLOW_AI);
	
	return INSTINCT_NULL;
}


NSString *BehaviourToString(OOBehaviour behaviour)
{
	switch (behaviour)
	{
		CASE(BEHAVIOUR_IDLE);
		CASE(BEHAVIOUR_TRACK_TARGET);
	//	CASE(BEHAVIOUR_FLY_TO_TARGET);
	//	CASE(BEHAVIOUR_HANDS_OFF);
		CASE(BEHAVIOUR_TUMBLE);
		CASE(BEHAVIOUR_STOP_STILL);
		CASE(BEHAVIOUR_STATION_KEEPING);
		CASE(BEHAVIOUR_ATTACK_TARGET);
		CASE(BEHAVIOUR_ATTACK_FLY_TO_TARGET);
		CASE(BEHAVIOUR_ATTACK_FLY_FROM_TARGET);
		CASE(BEHAVIOUR_RUNNING_DEFENSE);
		CASE(BEHAVIOUR_FLEE_TARGET);
		CASE(BEHAVIOUR_ATTACK_FLY_TO_TARGET_SIX);
		CASE(BEHAVIOUR_ATTACK_MINING_TARGET);
		CASE(BEHAVIOUR_ATTACK_FLY_TO_TARGET_TWELVE);
		CASE(BEHAVIOUR_AVOID_COLLISION);
		CASE(BEHAVIOUR_TRACK_AS_TURRET);
		CASE(BEHAVIOUR_FLY_RANGE_FROM_DESTINATION);
		CASE(BEHAVIOUR_FLY_TO_DESTINATION);
		CASE(BEHAVIOUR_FLY_FROM_DESTINATION);
		CASE(BEHAVIOUR_FACE_DESTINATION);
		CASE(BEHAVIOUR_COLLECT_TARGET);
		CASE(BEHAVIOUR_INTERCEPT_TARGET);
	//	CASE(BEHAVIOUR_MISSILE_FLY_TO_TARGET);
		CASE(BEHAVIOUR_FORMATION_FORM_UP);
		CASE(BEHAVIOUR_FORMATION_BREAK);
		CASE(BEHAVIOUR_ENERGY_BOMB_COUNTDOWN);
		CASE(BEHAVIOUR_TRACTORED);
		CASE(BEHAVIOUR_FLY_THRU_NAVPOINTS);
	}
	
	return @"** BEHAVIOUR UNKNOWN **";
}


NSString *GovernmentToString(OOGovernmentID government)
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


NSString *EconomyToString(OOEconomyID economy)
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


NSString *WeaponTypeToString(OOWeaponType weapon)
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
	}
	return @"Unknown weapon";
}


OOWeaponType StringToWeaponType(NSString *string)
{
	REVERSE_CASE(WEAPON_PLASMA_CANNON);
	REVERSE_CASE(WEAPON_PULSE_LASER);
	REVERSE_CASE(WEAPON_BEAM_LASER);
	REVERSE_CASE(WEAPON_MINING_LASER);
	REVERSE_CASE(WEAPON_MILITARY_LASER);
	REVERSE_CASE(WEAPON_THARGOID_LASER);
	
	return WEAPON_NONE;
}


NSString *WeaponTypeToEquipmentString(OOWeaponType weapon)
{
#define EQ_CASE(foo) case foo: return @"EQ_"#foo;
	
	switch (weapon)
	{
//		EQ_CASE(WEAPON_PLASMA_CANNON);
		EQ_CASE(WEAPON_PULSE_LASER);
		EQ_CASE(WEAPON_BEAM_LASER);
		EQ_CASE(WEAPON_MINING_LASER);
		EQ_CASE(WEAPON_MILITARY_LASER);
		EQ_CASE(WEAPON_THARGOID_LASER);
		
		case WEAPON_PLASMA_CANNON:
		case WEAPON_NONE:
			break;
	}
	return nil;
}


OOWeaponType EquipmentStringToWeaponType(NSString *string)
{
#define EQ_REVERSE_CASE(foo) if ([string hasSuffix:@#foo]) return WEAPON_##foo;
//	EQ_REVERSE_CASE(PLASMA_CANNON);
	EQ_REVERSE_CASE(PULSE_LASER);
	EQ_REVERSE_CASE(BEAM_LASER);
	EQ_REVERSE_CASE(MINING_LASER);
	EQ_REVERSE_CASE(MILITARY_LASER);
	EQ_REVERSE_CASE(THARGOID_LASER);
	
	return WEAPON_NONE;
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
	
	return CARGO_NOT_CARGO;
}


NSString *EnergyUnitTypeToString(OOEnergyUnitType unit)
{
	switch (unit)
	{
		CASE(ENERGY_UNIT_NONE);
		CASE(ENERGY_UNIT_NORMAL);
		CASE(ENERGY_UNIT_NAVAL);
	}
	
	return @"Unknown energy unit";
}


OOEnergyUnitType StringToEnergyUnitType(NSString *string)
{
	REVERSE_CASE(ENERGY_UNIT_NONE);
	REVERSE_CASE(ENERGY_UNIT_NORMAL);
	REVERSE_CASE(ENERGY_UNIT_NAVAL);
	
	return ENERGY_UNIT_NONE;
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


OOEnergyUnitType StringToGUIScreenID(NSString *string)
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
	
	return GUI_SCREEN_MAIN;
}


OOGalacticHyperspaceBehaviour StringToGalacticHyperspaceBehaviour(NSString *string)
{
	REVERSE_CASE(GALACTIC_HYPERSPACE_BEHAVIOUR_STANDARD);
	REVERSE_CASE(GALACTIC_HYPERSPACE_BEHAVIOUR_ALL_SYSTEMS_REACHABLE);
	REVERSE_CASE(GALACTIC_HYPERSPACE_BEHAVIOUR_FIXED_COORDINATES);
	
	return GALACTIC_HYPERSPACE_BEHAVIOUR_STANDARD;
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
	
	ratingNames = [[UNIVERSE descriptions] arrayForKey:@"rating"];
	for (i = 0; i != kRatingCount - 1; ++i)
	{
		if (kills < killThresholds[i])  return [ratingNames stringAtIndex:i];
	}
	
	return [ratingNames stringAtIndex:kRatingCount - 1];
}


NSString *KillCountToRatingAndKillString(unsigned kills)
{
	return [NSString stringWithFormat:@"%@ (%u)", KillCountToRatingString(kills), kills];
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
	
	statusNames = [[UNIVERSE descriptions] arrayForKey:@"legal_status"];
	for (i = 0; i != kStatusCount - 1; ++i)
	{
		if (legalStatus < statusThresholds[i])  return [statusNames stringAtIndex:i];
	}
	
	return [statusNames stringAtIndex:kStatusCount - 1];
}


NSString *AlertConditionToString(OOAlertCondition alertCondition)
{
	NSArray *conditionNames = [[UNIVERSE descriptions] arrayForKey:@"condition"];
	return [conditionNames stringAtIndex:alertCondition];
}


NSString *ShaderSettingToDisplayString(OOShaderSetting setting)
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


NSString *CommodityDisplayNameForSymbolicName(NSString *symbolicName)
{
	NSString *key = [@"commodity-name " stringByAppendingString:[symbolicName lowercaseString]];
	return [UNIVERSE descriptionForKey:key];
}


NSString *CommodityDisplayNameForCommodityArray(NSArray *commodityDefinition)
{
	return CommodityDisplayNameForSymbolicName([commodityDefinition stringAtIndex:MARKET_NAME]);
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
