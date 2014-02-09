/*

OOTypes.h

Various simple types that don't require us to pull in the associated class
headers.

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

#include "OOFunctionAttributes.h"
#include "OOCocoa.h"


typedef enum
{
	OPTIMIZED_BY_NONE,
	OPTIMIZED_BY_JUMPS,
	OPTIMIZED_BY_TIME
} OORouteType;


#define ENTRY(label, value) label,

typedef enum
{
	#include "OOViewID.tbl"
		
	kOOViewIDDefault = VIEW_NONE
} OOViewID;

#undef ENTRY


typedef enum
{
	AEGIS_NONE,
	AEGIS_CLOSE_TO_ANY_PLANET,
	AEGIS_CLOSE_TO_MAIN_PLANET,
	AEGIS_IN_DOCKING_RANGE
} OOAegisStatus;


typedef enum
{
	CARGO_NOT_CARGO					= -1,
	CARGO_SLAVES					= 3,
	CARGO_ALLOY						= 9,
	CARGO_MINERALS					= 12,
	CARGO_THARGOID					= 16,
	CARGO_RANDOM					= 100,
	CARGO_SCRIPTED_ITEM				= 200,
	CARGO_CHARACTER					= 300
} OOCargoType;


enum
{
	COMMODITY_UNDEFINED		= -1,
	
	// FIXME: hard-coded commodity types are used in OOJSManifest. Everything else is data-driven.
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
};
typedef NSInteger OOCommodityType;


typedef enum
{
	CARGO_FLAG_NONE					= 400,
	CARGO_FLAG_FULL_PLENTIFUL		= 501,
	CARGO_FLAG_FULL_SCARCE			= 502,
	CARGO_FLAG_FULL_MEDICAL				= 503,
	CARGO_FLAG_FULL_CONTRABAND				= 504,
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


#define ENTRY(label, value) label = value,

typedef enum
{
	#include "OOCompassMode.tbl"
} OOCompassMode;

enum
{
	kOOCompassModeDefault		= COMPASS_MODE_BASIC
};

#undef ENTRY

typedef enum
{
#define DIFF_STRING_ENTRY(label, string) label,
	#include "OOLegalStatusReason.tbl"
#undef DIFF_STRING_ENTRY
	
	kOOLegalStatusReasonDefault = kOOLegalStatusReasonUnknown
} OOLegalStatusReason;


typedef enum
{
	DOCKING_CLEARANCE_STATUS_NONE,
	DOCKING_CLEARANCE_STATUS_NOT_REQUIRED,
	DOCKING_CLEARANCE_STATUS_REQUESTED,
	DOCKING_CLEARANCE_STATUS_GRANTED,
	DOCKING_CLEARANCE_STATUS_TIMING_OUT,
} OODockingClearanceStatus;


typedef uint32_t	OOCargoQuantity;
typedef int32_t		OOCargoQuantityDelta;

typedef uint16_t	OOFuelQuantity;


typedef uint64_t	OOCreditsQuantity;
#define kOOMaxCredits	ULLONG_MAX


typedef uint16_t	OOKeyCode;


typedef uint16_t	OOUniversalID;		// Valid IDs range from 100 to 1000.

enum
{
	UNIVERSE_MAX_ENTITIES	= 2048,
	NO_TARGET				= 0,
	MIN_ENTITY_UID			= 100,
	MAX_ENTITY_UID			= MIN_ENTITY_UID + UNIVERSE_MAX_ENTITIES + 1
};


enum
{
	kOOVariableTechLevel	= 99
};
typedef NSUInteger	OOTechLevelID;		// 0..14, 99 is special. NSNotFound is used, so NSUInteger required.

typedef uint8_t		OOGovernmentID;		// 0..7
typedef uint8_t		OOEconomyID;		// 0..7


typedef uint8_t		OOGalaxyID;			// 0..7
typedef int16_t		OOSystemID;			// 0..255, -1 for interstellar space (?)


enum
{
	kOOMaximumGalaxyID				= 7,
	kOOMaximumSystemID				= 255,
	kOOMinimumSystemID				= -1,
	kOOSystemIDInterstellarSpace	= kOOMinimumSystemID
};


typedef double OOTimeAbsolute;
typedef double OOTimeDelta;


typedef enum
{
	WEAPON_FACING_FORWARD				= 1,
	WEAPON_FACING_AFT					= 2,
	WEAPON_FACING_PORT					= 4,
	WEAPON_FACING_STARBOARD				= 8,
	
	WEAPON_FACING_NONE					= 0
} OOWeaponFacing;

typedef uint8_t OOWeaponFacingSet;	// May have multiple bits set.

#define VALID_WEAPON_FACINGS			(WEAPON_FACING_NONE | WEAPON_FACING_FORWARD | WEAPON_FACING_AFT | WEAPON_FACING_PORT | WEAPON_FACING_STARBOARD)


typedef enum
{
	DETAIL_LEVEL_MINIMUM		= 0,
	DETAIL_LEVEL_NORMAL			= 1,
	DETAIL_LEVEL_SHADERS		= 2,
	DETAIL_LEVEL_EXTRAS			= 3,



	DETAIL_LEVEL_MAXIMUM		= 3
} OOGraphicsDetail;
