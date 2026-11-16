/*	OOLongRangeChartMode.h

The values of the long-range chart's colour mode: saved games hold it as
chart_colour_mode (PlayerEntity.cpp), so the numbers are the program's ordinals,
pinned below, and not OOLongRangeChartMode.tbl's value column, which its macro
discarded. JS and callObjC (encoded "i", OOTypeEncodings.h) see it too; and the
names the game reads and writes for them. It was OOLongRangeChartMode.tbl, an
X-macro table.
*/

#pragma once

#include <cstdint>
#include <string_view>

#include "OOEnumFlags.h"
#include "OOEnumTable.h"

enum class OOLongRangeChartMode : std::int32_t {
  kUnknown = 0,
  kSunColor = 1,
  kEconomy = 2,
  kGovernment = 3,
  kTechLevel = 4,
};

// What an unknown name reads as.
inline constexpr OOLongRangeChartMode kOOLongRangeChartModeDefault =
    OOLongRangeChartMode::kUnknown;

// The name of each value. No default: -Wswitch reports a value added without
// one.
constexpr std::string_view OOEnumName(OOLongRangeChartMode value) noexcept {
  switch (value) {
    case OOLongRangeChartMode::kUnknown:
      return "OOLRC_MODE_UNKNOWN";
    case OOLongRangeChartMode::kSunColor:
      return "OOLRC_MODE_SUNCOLOR";
    case OOLongRangeChartMode::kEconomy:
      return "OOLRC_MODE_ECONOMY";
    case OOLongRangeChartMode::kGovernment:
      return "OOLRC_MODE_GOVERNMENT";
    case OOLongRangeChartMode::kTechLevel:
      return "OOLRC_MODE_TECHLEVEL";
  }
  return {};
}

inline constexpr auto kOOLongRangeChartModeTable = oo::MakeEnumTable<
    OOLongRangeChartMode, OOLongRangeChartMode::kUnknown,
    OOLongRangeChartMode::kSunColor, OOLongRangeChartMode::kEconomy,
    OOLongRangeChartMode::kGovernment, OOLongRangeChartMode::kTechLevel>();

// Every number that leaves the program, pinned.
static_assert(oo::ToUnderlying(OOLongRangeChartMode::kUnknown) == 0);
static_assert(oo::ToUnderlying(OOLongRangeChartMode::kSunColor) == 1);
static_assert(oo::ToUnderlying(OOLongRangeChartMode::kEconomy) == 2);
static_assert(oo::ToUnderlying(OOLongRangeChartMode::kGovernment) == 3);
static_assert(oo::ToUnderlying(OOLongRangeChartMode::kTechLevel) == 4);
