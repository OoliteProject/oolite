/*

OOTypes.h

Various simple types that don't require us to pull in the associated class
headers.

Oolite
Copyright (C) 2004-2010 Giles C Williams and contributors

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

#include "OOFunctionAttributes.h"
#include "OOCocoa.h"

#define ARRAY_LENGTH(array) (sizeof (array) / sizeof (array)[0])


typedef enum
{
	STATUS_EFFECT					= 10,
	STATUS_ACTIVE					= 5,
	STATUS_COCKPIT_DISPLAY			= 2,
	STATUS_TEST						= 1,
	STATUS_INACTIVE					= 0,
	STATUS_DEAD						= -1,
	STATUS_START_GAME				= -10,
	STATUS_IN_FLIGHT				= 100,
	STATUS_DOCKED					= 200,
	STATUS_AUTOPILOT_ENGAGED		= 300,
	STATUS_DOCKING					= 401,
	STATUS_LAUNCHING				= 402,
	STATUS_WITCHSPACE_COUNTDOWN 	= 410,
	STATUS_ENTERING_WITCHSPACE  	= 411,
	STATUS_EXITING_WITCHSPACE   	= 412,
	STATUS_ESCAPE_SEQUENCE			= 500,
	STATUS_IN_HOLD					= 600,
	STATUS_BEING_SCOOPED			= 700,
	STATUS_HANDLING_ERROR			= 999
} OOEntityStatus;


typedef enum
{
	CLASS_NOT_SET					= -1,
	CLASS_NO_DRAW					= 0,
	CLASS_NEUTRAL					= 1,
	CLASS_STATION					= 3,
	CLASS_TARGET					= 4,
	CLASS_CARGO						= 5,
	CLASS_MISSILE					= 6,
	CLASS_ROCK						= 7,
	CLASS_MINE						= 8,
	CLASS_THARGOID					= 9,
	CLASS_BUOY						= 10,
	CLASS_WORMHOLE					= 444,
	CLASS_PLAYER					= 100,
	CLASS_POLICE					= 999,
	CLASS_MILITARY					= 333
} OOScanClass;


typedef enum
{
	GALACTIC_HYPERSPACE_BEHAVIOUR_STANDARD,
	GALACTIC_HYPERSPACE_BEHAVIOUR_ALL_SYSTEMS_REACHABLE,
	GALACTIC_HYPERSPACE_BEHAVIOUR_FIXED_COORDINATES,
	
	GALACTIC_HYPERSPACE_BEHAVIOUR_UNKNOWN	= -1,
	GALACTIC_HYPERSPACE_MAX = GALACTIC_HYPERSPACE_BEHAVIOUR_FIXED_COORDINATES
} OOGalacticHyperspaceBehaviour;


typedef enum
{
// NOTE: numerical values are available to scripts and shaders.
	ALERT_CONDITION_DOCKED,
	ALERT_CONDITION_GREEN,
	ALERT_CONDITION_YELLOW,
	ALERT_CONDITION_RED
} OOAlertCondition;


typedef enum
{
	OPTIMIZED_BY_NONE,
	OPTIMIZED_BY_JUMPS,
	OPTIMIZED_BY_TIME
} OORouteType;


typedef enum
{
	GUI_SCREEN_MAIN,
	GUI_SCREEN_INTRO1,
	GUI_SCREEN_INTRO2,
	GUI_SCREEN_STATUS,
	GUI_SCREEN_MANIFEST,
	GUI_SCREEN_EQUIP_SHIP,
	GUI_SCREEN_SHIPYARD,
	GUI_SCREEN_LONG_RANGE_CHART,
	GUI_SCREEN_SHORT_RANGE_CHART,
	GUI_SCREEN_SYSTEM_DATA,
	GUI_SCREEN_MARKET,
	GUI_SCREEN_CONTRACTS,
	GUI_SCREEN_OPTIONS,
	GUI_SCREEN_GAMEOPTIONS,
	GUI_SCREEN_LOAD,
	GUI_SCREEN_SAVE,
	GUI_SCREEN_SAVE_OVERWRITE,
	GUI_SCREEN_STICKMAPPER,
	GUI_SCREEN_MISSION,
	GUI_SCREEN_REPORT
} OOGUIScreenID;


#ifdef OO_BRAIN_AI
typedef enum
{
	INSTINCT_NULL					= 0U,
	
	// basic behavioural instincts
	INSTINCT_AVOID_HAZARDS			= 101,
	INSTINCT_FLOCK_ALIKE			= 102,
	
	// threats should be defined
	INSTINCT_FIGHT_OR_FLIGHT		= 103,
	
// 'prey' should be defined
	INSTINCT_ATTACK_PREY			= 105,
	INSTINCT_AVOID_PREDATORS		= 106,
	
	// advanced AI instincts
	INSTINCT_FOLLOW_AI				= 201
} OOInstinctID;
#endif


typedef enum
{
	// NOTE: numerical values are available to scripts.
	SHADERS_NOT_SUPPORTED,
	SHADERS_OFF,
	SHADERS_SIMPLE,
	SHADERS_FULL
} OOShaderSetting;

#define SHADERS_MIN SHADERS_OFF


typedef enum
{
	BEHAVIOUR_IDLE							= 0U,
	BEHAVIOUR_TRACK_TARGET					= 1,
	BEHAVIOUR_TUMBLE						= 4,
	BEHAVIOUR_STOP_STILL					= 5,
	
	BEHAVIOUR_STATION_KEEPING				= 10,
	
	BEHAVIOUR_ATTACK_TARGET					= 101,
	BEHAVIOUR_ATTACK_FLY_TO_TARGET			= 102,
	BEHAVIOUR_ATTACK_FLY_FROM_TARGET		= 103,
	BEHAVIOUR_RUNNING_DEFENSE				= 104,
	
// fleeing
	BEHAVIOUR_FLEE_TARGET					= 105,
	
// advanced combat...
	BEHAVIOUR_ATTACK_FLY_TO_TARGET_SIX		= 106,
	BEHAVIOUR_ATTACK_MINING_TARGET			= 107,
	
// further advanced combat...
	BEHAVIOUR_ATTACK_FLY_TO_TARGET_TWELVE	= 112,
	
	BEHAVIOUR_AVOID_COLLISION				= 130,
	
	BEHAVIOUR_TRACK_AS_TURRET				= 150,
	
	BEHAVIOUR_FLY_RANGE_FROM_DESTINATION	= 200,
	BEHAVIOUR_FLY_TO_DESTINATION			= 201,
	BEHAVIOUR_FLY_FROM_DESTINATION			= 202,
	BEHAVIOUR_FACE_DESTINATION				= 203,
	
	BEHAVIOUR_FLY_THRU_NAVPOINTS			= 210,
	
	BEHAVIOUR_COLLECT_TARGET				= 300,
	BEHAVIOUR_INTERCEPT_TARGET				= 350,
	
	BEHAVIOUR_FORMATION_FORM_UP				= 501,
	BEHAVIOUR_FORMATION_BREAK				= 502,
	
	BEHAVIOUR_ENERGY_BOMB_COUNTDOWN			= 601,
	
	BEHAVIOUR_TRACTORED						= 701
} OOBehaviour;


OOINLINE BOOL IsBehaviourHostile(OOBehaviour behaviour) INLINE_CONST_FUNC;
OOINLINE BOOL IsBehaviourHostile(OOBehaviour behaviour)
{
	switch (behaviour)
	{
		case BEHAVIOUR_ATTACK_TARGET:
		case BEHAVIOUR_ATTACK_FLY_TO_TARGET:
		case BEHAVIOUR_ATTACK_FLY_FROM_TARGET:
		case BEHAVIOUR_RUNNING_DEFENSE:
		case BEHAVIOUR_FLEE_TARGET:
		case BEHAVIOUR_ATTACK_FLY_TO_TARGET_SIX:
	//	case BEHAVIOUR_ATTACK_MINING_TARGET:
		case BEHAVIOUR_ATTACK_FLY_TO_TARGET_TWELVE:
			return YES;
			
		default:
			return NO;
	}
	
	return 100 < behaviour && behaviour < 120;
}


typedef enum
{
	VIEW_FORWARD			= 0,
	VIEW_AFT				= 1,
	VIEW_PORT				= 2,
	VIEW_STARBOARD			= 3,
	VIEW_CUSTOM				= 7,
	VIEW_NONE				= -1,
	VIEW_GUI_DISPLAY		= 10,
	VIEW_BREAK_PATTERN		= 20
} OOViewID;


typedef enum
{
	DEMO_NO_DEMO		= 0,
	DEMO_FLY_IN			= 101,
	DEMO_SHOW_THING,
	DEMO_FLY_OUT
} OODemoMode;


typedef enum
{
	WEAPON_NONE						= 0U,
	WEAPON_PLASMA_CANNON			= 1,
	WEAPON_PULSE_LASER				= 2,
	WEAPON_BEAM_LASER				= 3,
	WEAPON_MINING_LASER				= 4,
	WEAPON_MILITARY_LASER			= 5,
	WEAPON_THARGOID_LASER			= 10,
	WEAPON_UNDEFINED
} OOWeaponType;


typedef enum
{
	AEGIS_NONE,
	AEGIS_CLOSE_TO_ANY_PLANET,
	AEGIS_CLOSE_TO_MAIN_PLANET,
	AEGIS_IN_DOCKING_RANGE
} OOAegisStatus;


typedef enum
{
	CARGO_UNDEFINED					= -2,	// FIXME: it's unclear whether there's a useful distinction between CARGO_UNDEFINED (previously NSNotFound) and CARGO_NOT_CARGO.
	CARGO_NOT_CARGO					= -1,
	CARGO_SLAVES					= 3,
	CARGO_ALLOY						= 9,
	CARGO_MINERALS					= 12,
	CARGO_THARGOID					= 16,
	CARGO_RANDOM					= 100,
	CARGO_SCRIPTED_ITEM				= 200,
	CARGO_CHARACTER					= 300
} OOCargoType;


typedef enum
{
	COMMODITY_UNDEFINED		= -1,
	COMMODITY_FOOD,		//	=  0 
	COMMODITY_TEXTILES,
	COMMODITY_RADIOACTIVES,
	COMMODITY_SLAVES,
	COMMODITY_LIQUOR_WINES,
	COMMODITY_LUXURIES,
	COMMODITY_NARCOTICS,
	COMMODITY_COMPUTERS,
	COMMODITY_MACHINERY,
	COMMODITY_ALLOYS,
	COMMODITY_FIREARMS,
	COMMODITY_FURS,
	COMMODITY_MINERALS,
	COMMODITY_GOLD,
	COMMODITY_PLATINUM,
	COMMODITY_GEM_STONES,
	COMMODITY_ALIEN_ITEMS
} OOCommodityType;


typedef enum
{
	CARGO_FLAG_NONE					= 400,
	CARGO_FLAG_FULL_PLENTIFUL		= 501,
	CARGO_FLAG_FULL_SCARCE			= 502,
	CARGO_FLAG_PIRATE				= 505,
	CARGO_FLAG_FULL_UNIFORM			= 510,
	CARGO_FLAG_CANISTERS			= 600,
	CARGO_FLAG_FULL_PASSENGERS		= 700
} OOCargoFlag;


typedef enum
{
	UNITS_TONS,
	UNITS_KILOGRAMS,
	UNITS_GRAMS
} OOMassUnit;


typedef enum
{
	ENERGY_UNIT_NONE,
	ENERGY_UNIT_NORMAL_DAMAGED,
	ENERGY_UNIT_NAVAL_DAMAGED,
	OLD_ENERGY_UNIT_NORMAL			=15,
	OLD_ENERGY_UNIT_NAVAL			= 20,
	ENERGY_UNIT_NORMAL				= 8,
	ENERGY_UNIT_NAVAL				= 16
} OOEnergyUnitType;


typedef enum
{
	// NOTE: numerical values are available to scripts and shaders.
	COMPASS_MODE_BASIC,
	COMPASS_MODE_PLANET,
	COMPASS_MODE_STATION,
	COMPASS_MODE_SUN,
	COMPASS_MODE_TARGET,
	COMPASS_MODE_BEACONS
} OOCompassMode;


#if DOCKING_CLEARANCE_ENABLED
typedef enum
{
	DOCKING_CLEARANCE_STATUS_NONE,
	DOCKING_CLEARANCE_STATUS_NOT_REQUIRED,
	DOCKING_CLEARANCE_STATUS_REQUESTED,
	DOCKING_CLEARANCE_STATUS_GRANTED,
	DOCKING_CLEARANCE_STATUS_TIMING_OUT,
} OODockingClearanceStatus;
#endif


typedef uint32_t	OOCargoQuantity;
typedef int32_t		OOCargoQuantityDelta;

typedef uint16_t	OOFuelQuantity;


typedef uint64_t	OOCreditsQuantity;


typedef uint16_t	OOKeyCode;


typedef uint16_t	OOUniversalID;		// Valid IDs range from 100 to 1000.

enum
{
	UNIVERSE_MAX_ENTITIES	= 2048,
	NO_TARGET				= 0,
	MIN_ENTITY_UID			= 100,
	MAX_ENTITY_UID			= MIN_ENTITY_UID + UNIVERSE_MAX_ENTITIES + 1
};


typedef OOUInteger	OOTechLevelID;		// 0..14, 99 is special. NSNotFound is used, so OOUInteger required.
typedef uint8_t		OOGovernmentID;		// 0..7
typedef uint8_t		OOEconomyID;		// 0..7

enum
{
	kOOVariableTechLevel	= 99
};


typedef uint8_t		OOGalaxyID;			// 0..7
typedef int16_t		OOSystemID;			// 0..255, -1 for interstellar space (?)


enum
{
	kOOMaximumGalaxyID		= 7,
	kOOMaximumSystemID		= 255,
	kOOMinimumSystemID		= -1
};


typedef double OOTimeAbsolute;
typedef double OOTimeDelta;
