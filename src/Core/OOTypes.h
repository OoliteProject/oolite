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

#pragma once

#include <cstdint>
#include <string_view>

#include "OOEnumFlags.h"
#include "OOFunctionAttributes.h"
#ifndef OO_PLAIN_CPP_UNIT
#include "OOFoundation.h"
#else
/*	A plain C or C++ translation unit (OOConstToJSString) needs only the C
   types OOFoundation.h's floor gives (std::ptrdiff_t, std::size_t).
   OOFoundation.h itself declares more.
*/
#include <limits.h>

#include "oofnd/objc/OOFoundationTypes.h"
#endif

typedef enum {
  OPTIMIZED_BY_NONE,
  OPTIMIZED_BY_JUMPS,
  OPTIMIZED_BY_TIME
} OORouteType;

// The names the game writes for OORouteType (saves, logs and plists).
constexpr std::string_view OOEnumName(OORouteType value) noexcept {
  switch (value) {
    case OPTIMIZED_BY_NONE:
      return "OPTIMIZED_BY_NONE";
    case OPTIMIZED_BY_JUMPS:
      return "OPTIMIZED_BY_JUMPS";
    case OPTIMIZED_BY_TIME:
      return "OPTIMIZED_BY_TIME";
  }
  return {};
}

#define ENTRY(label, value) label,

typedef enum {
#include "OOViewID.tbl"

  kOOViewIDDefault = VIEW_NONE
} OOViewID;

typedef enum {
#include "OOLongRangeChartMode.tbl"

  kOOLongRangeChartModeDefault = OOLRC_MODE_UNKNOWN
} OOLongRangeChartMode;

#undef ENTRY

// Encoded "i" (OOTypeEncodings.h): a by-name call answers it as a number.
enum class OOAegisStatus : std::int32_t {
  kNone,
  kCloseToAnyPlanet,
  kCloseToMainPlanet,
  kInDockingRange
};

typedef enum {
  CARGO_NOT_CARGO = -1,
  CARGO_SLAVES = 3,
  CARGO_ALLOY = 9,
  CARGO_MINERALS = 12,
  CARGO_THARGOID = 16,
  CARGO_RANDOM = 100,
  CARGO_SCRIPTED_ITEM = 200,
  CARGO_CHARACTER = 300
} OOCargoType;

// The names the game writes for OOCargoType (saves, logs and plists).
constexpr std::string_view OOEnumName(OOCargoType value) noexcept {
  switch (value) {
    case CARGO_NOT_CARGO:
      return "CARGO_NOT_CARGO";
    case CARGO_SLAVES:
      return "CARGO_SLAVES";
    case CARGO_ALLOY:
      return "CARGO_ALLOY";
    case CARGO_MINERALS:
      return "CARGO_MINERALS";
    case CARGO_THARGOID:
      return "CARGO_THARGOID";
    case CARGO_RANDOM:
      return "CARGO_RANDOM";
    case CARGO_SCRIPTED_ITEM:
      return "CARGO_SCRIPTED_ITEM";
    case CARGO_CHARACTER:
      return "CARGO_CHARACTER";
  }
  return {};
}

/*
enum
{
        COMMODITY_UNDEFINED		= -1,

        // FIXME: hard-coded commodity types are used in OOJSManifest.
Everything else is data-driven. COMMODITY_FOOD,		//	=  0
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
typedef std::ptrdiff_t OOCommodityType;
*/

enum class OOCargoFlag : int {
  kNone = 400,
  kFullPlentiful = 501,
  kFullScarce = 502,
  kFullMedical = 503,
  kFullContraband = 504,
  kPirate = 505,
  kFullUniform = 510,
  kCanisters = 600,
  kFullPassengers = 700
};

// trade-goods.plist's quantity_unit numbers (OOMassUnitFromNumber).
enum class OOMassUnit : unsigned {
  kTons,
  kKilograms,
  kGrams,
  kUnknown  // a quantity_unit that is none of the above; displays as "??"
};
static_assert(oo::ToUnderlying(OOMassUnit::kTons) == 0);
static_assert(oo::ToUnderlying(OOMassUnit::kKilograms) == 1);
static_assert(oo::ToUnderlying(OOMassUnit::kGrams) == 2);

typedef enum {
  ENERGY_UNIT_NONE,
  ENERGY_UNIT_NORMAL_DAMAGED,
  ENERGY_UNIT_NAVAL_DAMAGED,
  OLD_ENERGY_UNIT_NORMAL = 15,
  OLD_ENERGY_UNIT_NAVAL = 20,
  ENERGY_UNIT_NORMAL = 8,
  ENERGY_UNIT_NAVAL = 16
} OOEnergyUnitType;

// The names the game writes for OOEnergyUnitType (saves, logs and plists).
constexpr std::string_view OOEnumName(OOEnergyUnitType value) noexcept {
  switch (value) {
    case ENERGY_UNIT_NONE:
      return "ENERGY_UNIT_NONE";
    case ENERGY_UNIT_NORMAL:
      return "ENERGY_UNIT_NORMAL";
    case ENERGY_UNIT_NAVAL:
      return "ENERGY_UNIT_NAVAL";
    case ENERGY_UNIT_NORMAL_DAMAGED:
      return "ENERGY_UNIT_NORMAL_DAMAGED";
    case ENERGY_UNIT_NAVAL_DAMAGED:
      return "ENERGY_UNIT_NAVAL_DAMAGED";
    case OLD_ENERGY_UNIT_NORMAL:  // a legacy save's number only: no name
    case OLD_ENERGY_UNIT_NAVAL:
      return {};
  }
  return {};
}

#define ENTRY(label, value) label = value,

typedef enum {
#include "OOCompassMode.tbl"
} OOCompassMode;

inline constexpr OOCompassMode kOOCompassModeDefault = COMPASS_MODE_BASIC;

#undef ENTRY

typedef enum {
#define DIFF_STRING_ENTRY(label, string) label,
#include "OOLegalStatusReason.tbl"
#undef DIFF_STRING_ENTRY

  kOOLegalStatusReasonDefault = kOOLegalStatusReasonUnknown
} OOLegalStatusReason;

typedef enum {
  DOCKING_CLEARANCE_STATUS_NONE,
  DOCKING_CLEARANCE_STATUS_NOT_REQUIRED,
  DOCKING_CLEARANCE_STATUS_REQUESTED,
  DOCKING_CLEARANCE_STATUS_GRANTED,
  DOCKING_CLEARANCE_STATUS_TIMING_OUT,
} OODockingClearanceStatus;

// The names the game writes for OODockingClearanceStatus (saves, logs and
// plists).
constexpr std::string_view OOEnumName(OODockingClearanceStatus value) noexcept {
  switch (value) {
    case DOCKING_CLEARANCE_STATUS_NONE:
      return "DOCKING_CLEARANCE_STATUS_NONE";
    case DOCKING_CLEARANCE_STATUS_REQUESTED:
      return "DOCKING_CLEARANCE_STATUS_REQUESTED";
    case DOCKING_CLEARANCE_STATUS_NOT_REQUIRED:
      return "DOCKING_CLEARANCE_STATUS_NOT_REQUIRED";
    case DOCKING_CLEARANCE_STATUS_GRANTED:
      return "DOCKING_CLEARANCE_STATUS_GRANTED";
    case DOCKING_CLEARANCE_STATUS_TIMING_OUT:
      return "DOCKING_CLEARANCE_STATUS_TIMING_OUT";
  }
  return {};
}

typedef uint32_t OOCargoQuantity;
typedef int32_t OOCargoQuantityDelta;

typedef uint16_t OOFuelQuantity;

typedef uint64_t OOCreditsQuantity;
#define kOOMaxCredits ULLONG_MAX

typedef uint16_t OOKeyCode;

typedef uint16_t OOUniversalID;  // Valid IDs range from 100 to 1000.

enum {
  UNIVERSE_MAX_ENTITIES = 2048,
  NO_TARGET = 0,
  MIN_ENTITY_UID = 100,
  MAX_ENTITY_UID = MIN_ENTITY_UID + UNIVERSE_MAX_ENTITIES + 1
};

inline constexpr int kOOVariableTechLevel = 99;
typedef std::size_t OOTechLevelID;  // 0..14, 99 is special. oo::kNotFound is
                                    // used, so std::size_t required.

typedef uint8_t OOGovernmentID;  // 0..7
typedef uint8_t OOEconomyID;     // 0..7

typedef uint8_t OOGalaxyID;  // 0..7
typedef int16_t OOSystemID;  // 0..255, -1 for interstellar space (?)

enum {
  kOOMaximumGalaxyID = 7,
  kOOMaximumSystemID = 255,
  kOOMinimumSystemID = -1,
  kOOSystemIDInterstellarSpace = kOOMinimumSystemID
};

typedef double OOTimeAbsolute;
typedef double OOTimeDelta;

// One weapon mount. Encoded "i" (OOTypeEncodings.h): a by-name call answers it
// as a number.
enum class OOWeaponFacing : std::uint8_t {
  kNone = 0,
  kForward = 1,
  kAft = 2,
  kPort = 4,
  kStarboard = 8
};
constexpr std::true_type OOEnableFlagOperators(OOWeaponFacing);

// The numbers of shipdata's weapon_facings bits and of JS's weaponFacings.
static_assert(oo::ToUnderlying(OOWeaponFacing::kNone) == 0);
static_assert(oo::ToUnderlying(OOWeaponFacing::kForward) == 1);
static_assert(oo::ToUnderlying(OOWeaponFacing::kAft) == 2);
static_assert(oo::ToUnderlying(OOWeaponFacing::kPort) == 4);
static_assert(oo::ToUnderlying(OOWeaponFacing::kStarboard) == 8);

// A set of mounts, as shipdata, shipyard.plist and JS give it: a number with an
// OOWeaponFacing bit per mount.
typedef std::uint8_t OOWeaponFacingSet;

inline constexpr OOWeaponFacingSet kOOValidWeaponFacings = oo::ToUnderlying(
    OOWeaponFacing::kNone | OOWeaponFacing::kForward | OOWeaponFacing::kAft |
    OOWeaponFacing::kPort | OOWeaponFacing::kStarboard);

// Takes any unsigned number of facings: the sets read from plists are unsigned.
inline bool OOWeaponFacingIsIn(unsigned facings,
                               OOWeaponFacing facing) noexcept {
  return (facings & oo::ToUnderlying(facing)) != 0;
}

typedef enum {
  DETAIL_LEVEL_MINIMUM = 0,
  DETAIL_LEVEL_NORMAL = 1,
  DETAIL_LEVEL_SHADERS = 2,
  DETAIL_LEVEL_EXTRAS = 3,

  DETAIL_LEVEL_MAXIMUM = 3
} OOGraphicsDetail;

// The names the game writes for OOGraphicsDetail (saves, logs and plists).
constexpr std::string_view OOEnumName(OOGraphicsDetail value) noexcept {
  switch (value) {
    case DETAIL_LEVEL_MINIMUM:
      return "DETAIL_LEVEL_MINIMUM";
    case DETAIL_LEVEL_NORMAL:
      return "DETAIL_LEVEL_NORMAL";
    case DETAIL_LEVEL_SHADERS:
      return "DETAIL_LEVEL_SHADERS";
    case DETAIL_LEVEL_EXTRAS:
      return "DETAIL_LEVEL_EXTRAS";
  }
  return {};
}
