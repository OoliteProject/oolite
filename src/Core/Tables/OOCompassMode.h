/*	OOCompassMode.h

The values of the compass mode: shaders, saves, JS and callObjC (encoded "i",
OOTypeEncodings.h), and the names the game reads and writes for them.
It was OOCompassMode.tbl, an X-macro table.
*/

#pragma once

#include <cstdint>
#include <string_view>

#include "OOEnumFlags.h"
#include "OOEnumTable.h"

enum class OOCompassMode : std::int32_t {
  kInactive = -1,
  kBasic = 0,
  kPlanet = 1,
  kStation = 3,
  kSun = 4,
  kTarget = 5,
  kBeacons = 6,
};

// What an unknown name reads as.
inline constexpr OOCompassMode kOOCompassModeDefault = OOCompassMode::kBasic;

// The name of each value. No default: -Wswitch reports a value added without
// one.
constexpr std::string_view OOEnumName(OOCompassMode value) noexcept {
  switch (value) {
    case OOCompassMode::kInactive:
      return "COMPASS_MODE_INACTIVE";
    case OOCompassMode::kBasic:
      return "COMPASS_MODE_BASIC";
    case OOCompassMode::kPlanet:
      return "COMPASS_MODE_PLANET";
    case OOCompassMode::kStation:
      return "COMPASS_MODE_STATION";
    case OOCompassMode::kSun:
      return "COMPASS_MODE_SUN";
    case OOCompassMode::kTarget:
      return "COMPASS_MODE_TARGET";
    case OOCompassMode::kBeacons:
      return "COMPASS_MODE_BEACONS";
  }
  return {};
}

inline constexpr auto kOOCompassModeTable =
    oo::MakeEnumTable<OOCompassMode, OOCompassMode::kInactive,
                      OOCompassMode::kBasic, OOCompassMode::kPlanet,
                      OOCompassMode::kStation, OOCompassMode::kSun,
                      OOCompassMode::kTarget, OOCompassMode::kBeacons>();

// Every number that leaves the program, pinned.
static_assert(oo::ToUnderlying(OOCompassMode::kInactive) == -1);
static_assert(oo::ToUnderlying(OOCompassMode::kBasic) == 0);
static_assert(oo::ToUnderlying(OOCompassMode::kPlanet) == 1);
static_assert(oo::ToUnderlying(OOCompassMode::kStation) == 3);
static_assert(oo::ToUnderlying(OOCompassMode::kSun) == 4);
static_assert(oo::ToUnderlying(OOCompassMode::kTarget) == 5);
static_assert(oo::ToUnderlying(OOCompassMode::kBeacons) == 6);
