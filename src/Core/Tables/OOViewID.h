/*	OOViewID.h

The values of a view direction: JS sees its name. The values are the program's
ordinals; OOViewID.tbl's value column was never used (its macro discarded it),
and the names the game reads and writes for them. It was OOViewID.tbl, an
X-macro table.
*/

#pragma once

#include <cstdint>
#include <string_view>

#include "OOEnumFlags.h"
#include "OOEnumTable.h"

enum class OOViewID : std::int32_t {
  kForward = 0,
  kAft = 1,
  kPort = 2,
  kStarboard = 3,
  kCustom = 4,
  kNone = 5,
  kGUIDisplay = 6,
  kBreakPattern = 7,
};

// What an unknown name reads as.
inline constexpr OOViewID kOOViewIDDefault = OOViewID::kNone;

// The name of each value. No default: -Wswitch reports a value added without
// one.
constexpr std::string_view OOEnumName(OOViewID value) noexcept {
  switch (value) {
    case OOViewID::kForward:
      return "VIEW_FORWARD";
    case OOViewID::kAft:
      return "VIEW_AFT";
    case OOViewID::kPort:
      return "VIEW_PORT";
    case OOViewID::kStarboard:
      return "VIEW_STARBOARD";
    case OOViewID::kCustom:
      return "VIEW_CUSTOM";
    case OOViewID::kNone:
      return "VIEW_NONE";
    case OOViewID::kGUIDisplay:
      return "VIEW_GUI_DISPLAY";
    case OOViewID::kBreakPattern:
      return "VIEW_BREAK_PATTERN";
  }
  return {};
}

inline constexpr auto kOOViewIDTable =
    oo::MakeEnumTable<OOViewID, OOViewID::kForward, OOViewID::kAft,
                      OOViewID::kPort, OOViewID::kStarboard, OOViewID::kCustom,
                      OOViewID::kNone, OOViewID::kGUIDisplay,
                      OOViewID::kBreakPattern>();

// Every number that leaves the program, pinned.
static_assert(oo::ToUnderlying(OOViewID::kForward) == 0);
static_assert(oo::ToUnderlying(OOViewID::kAft) == 1);
static_assert(oo::ToUnderlying(OOViewID::kPort) == 2);
static_assert(oo::ToUnderlying(OOViewID::kStarboard) == 3);
static_assert(oo::ToUnderlying(OOViewID::kCustom) == 4);
static_assert(oo::ToUnderlying(OOViewID::kNone) == 5);
static_assert(oo::ToUnderlying(OOViewID::kGUIDisplay) == 6);
static_assert(oo::ToUnderlying(OOViewID::kBreakPattern) == 7);
