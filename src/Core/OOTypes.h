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

enum class OORouteType : std::int32_t { kNone, kJumps, kTime };
// The numbers JS and the saved game's chart_ana_mode use.
static_assert(oo::ToUnderlying(OORouteType::kNone) == 0);
static_assert(oo::ToUnderlying(OORouteType::kJumps) == 1);
static_assert(oo::ToUnderlying(OORouteType::kTime) == 2);

// The names the game writes for OORouteType (saves, logs and plists).
constexpr std::string_view OOEnumName(OORouteType value) noexcept {
  switch (value) {
    case OORouteType::kNone:
      return "OPTIMIZED_BY_NONE";
    case OORouteType::kJumps:
      return "OPTIMIZED_BY_JUMPS";
    case OORouteType::kTime:
      return "OPTIMIZED_BY_TIME";
  }
  return {};
}

#include "OOCompassMode.h"
#include "OOLongRangeChartMode.h"
#include "OOViewID.h"

// Encoded "i" (OOTypeEncodings.h): a by-name call answers it as a number.
enum class OOAegisStatus : std::int32_t {
  kNone,
  kCloseToAnyPlanet,
  kCloseToMainPlanet,
  kInDockingRange
};

enum class OOCargoType : std::int32_t {
  kNotCargo = -1,
  kSlaves = 3,
  kAlloy = 9,
  kMinerals = 12,
  kThargoid = 16,
  kRandom = 100,
  kScriptedItem = 200,
  kCharacter = 300
};
// The numbers shipdata's cargo_type uses.
static_assert(oo::ToUnderlying(OOCargoType::kNotCargo) == -1);
static_assert(oo::ToUnderlying(OOCargoType::kSlaves) == 3);
static_assert(oo::ToUnderlying(OOCargoType::kAlloy) == 9);
static_assert(oo::ToUnderlying(OOCargoType::kMinerals) == 12);
static_assert(oo::ToUnderlying(OOCargoType::kThargoid) == 16);
static_assert(oo::ToUnderlying(OOCargoType::kRandom) == 100);
static_assert(oo::ToUnderlying(OOCargoType::kScriptedItem) == 200);
static_assert(oo::ToUnderlying(OOCargoType::kCharacter) == 300);

// The names the game writes for OOCargoType (saves, logs and plists).
constexpr std::string_view OOEnumName(OOCargoType value) noexcept {
  switch (value) {
    case OOCargoType::kNotCargo:
      return "CARGO_NOT_CARGO";
    case OOCargoType::kSlaves:
      return "CARGO_SLAVES";
    case OOCargoType::kAlloy:
      return "CARGO_ALLOY";
    case OOCargoType::kMinerals:
      return "CARGO_MINERALS";
    case OOCargoType::kThargoid:
      return "CARGO_THARGOID";
    case OOCargoType::kRandom:
      return "CARGO_RANDOM";
    case OOCargoType::kScriptedItem:
      return "CARGO_SCRIPTED_ITEM";
    case OOCargoType::kCharacter:
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

enum class OOEnergyUnitType : std::int32_t {
  kNone,
  kNormalDamaged,
  kNavalDamaged,
  kOldNormal = 15,
  kOldNaval = 20,
  kNormal = 8,
  kNaval = 16
};
// The numbers a legacy saved game's energy_unit uses.
static_assert(oo::ToUnderlying(OOEnergyUnitType::kNone) == 0);
static_assert(oo::ToUnderlying(OOEnergyUnitType::kNormalDamaged) == 1);
static_assert(oo::ToUnderlying(OOEnergyUnitType::kNavalDamaged) == 2);
static_assert(oo::ToUnderlying(OOEnergyUnitType::kOldNormal) == 15);
static_assert(oo::ToUnderlying(OOEnergyUnitType::kOldNaval) == 20);
static_assert(oo::ToUnderlying(OOEnergyUnitType::kNormal) == 8);
static_assert(oo::ToUnderlying(OOEnergyUnitType::kNaval) == 16);

// The names the game writes for OOEnergyUnitType (saves, logs and plists).
constexpr std::string_view OOEnumName(OOEnergyUnitType value) noexcept {
  switch (value) {
    case OOEnergyUnitType::kNone:
      return "ENERGY_UNIT_NONE";
    case OOEnergyUnitType::kNormal:
      return "ENERGY_UNIT_NORMAL";
    case OOEnergyUnitType::kNaval:
      return "ENERGY_UNIT_NAVAL";
    case OOEnergyUnitType::kNormalDamaged:
      return "ENERGY_UNIT_NORMAL_DAMAGED";
    case OOEnergyUnitType::kNavalDamaged:
      return "ENERGY_UNIT_NAVAL_DAMAGED";
    case OOEnergyUnitType::kOldNormal:  // a legacy save's number only: no name
    case OOEnergyUnitType::kOldNaval:
      return {};
  }
  return {};
}

#include "OOLegalStatusReason.h"

enum class OODockingClearanceStatus : std::int32_t {
  kNone,
  kNotRequired,
  kRequested,
  kGranted,
  kTimingOut,
};
// The numbers JS sees.
static_assert(oo::ToUnderlying(OODockingClearanceStatus::kNone) == 0);
static_assert(oo::ToUnderlying(OODockingClearanceStatus::kNotRequired) == 1);
static_assert(oo::ToUnderlying(OODockingClearanceStatus::kRequested) == 2);
static_assert(oo::ToUnderlying(OODockingClearanceStatus::kGranted) == 3);
static_assert(oo::ToUnderlying(OODockingClearanceStatus::kTimingOut) == 4);

// The names the game writes for OODockingClearanceStatus (saves, logs and
// plists).
constexpr std::string_view OOEnumName(OODockingClearanceStatus value) noexcept {
  switch (value) {
    case OODockingClearanceStatus::kNone:
      return "DOCKING_CLEARANCE_STATUS_NONE";
    case OODockingClearanceStatus::kRequested:
      return "DOCKING_CLEARANCE_STATUS_REQUESTED";
    case OODockingClearanceStatus::kNotRequired:
      return "DOCKING_CLEARANCE_STATUS_NOT_REQUIRED";
    case OODockingClearanceStatus::kGranted:
      return "DOCKING_CLEARANCE_STATUS_GRANTED";
    case OODockingClearanceStatus::kTimingOut:
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

inline constexpr int UNIVERSE_MAX_ENTITIES = 2048;
inline constexpr int NO_TARGET = 0;
inline constexpr int MIN_ENTITY_UID = 100;
inline constexpr int MAX_ENTITY_UID =
    MIN_ENTITY_UID + UNIVERSE_MAX_ENTITIES + 1;

inline constexpr int kOOVariableTechLevel = 99;
typedef std::size_t OOTechLevelID;  // 0..14, 99 is special. oo::kNotFound is
                                    // used, so std::size_t required.

typedef uint8_t OOGovernmentID;  // 0..7
typedef uint8_t OOEconomyID;     // 0..7

typedef uint8_t OOGalaxyID;  // 0..7
typedef int16_t OOSystemID;  // 0..255, -1 for interstellar space (?)

inline constexpr int kOOMaximumGalaxyID = 7;
inline constexpr int kOOMaximumSystemID = 255;
inline constexpr int kOOMinimumSystemID = -1;
inline constexpr int kOOSystemIDInterstellarSpace = kOOMinimumSystemID;

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

enum class OOGraphicsDetail : std::int32_t {
  kMinimum = 0,
  kNormal = 1,
  kShaders = 2,
  kExtras = 3
};
inline constexpr OOGraphicsDetail kOOGraphicsDetailMaximum =
    OOGraphicsDetail::kExtras;
// The numbers the preferences' detailLevel, the debug console and the
// description keys use.
static_assert(oo::ToUnderlying(OOGraphicsDetail::kMinimum) == 0);
static_assert(oo::ToUnderlying(OOGraphicsDetail::kNormal) == 1);
static_assert(oo::ToUnderlying(OOGraphicsDetail::kShaders) == 2);
static_assert(oo::ToUnderlying(OOGraphicsDetail::kExtras) == 3);

// The names the game writes for OOGraphicsDetail (saves, logs and plists).
constexpr std::string_view OOEnumName(OOGraphicsDetail value) noexcept {
  switch (value) {
    case OOGraphicsDetail::kMinimum:
      return "DETAIL_LEVEL_MINIMUM";
    case OOGraphicsDetail::kNormal:
      return "DETAIL_LEVEL_NORMAL";
    case OOGraphicsDetail::kShaders:
      return "DETAIL_LEVEL_SHADERS";
    case OOGraphicsDetail::kExtras:
      return "DETAIL_LEVEL_EXTRAS";
  }
  return {};
}
