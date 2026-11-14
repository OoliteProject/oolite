

/*	OOScanClass.h

The values of a scan class: shipdata, saves, JS and callObjC (encoded "i",
OOTypeEncodings.h), and the names the game reads and writes for them. It was
OOScanClass.tbl, an X-macro table.
*/

#pragma once

#include <cstdint>
#include <string_view>

#include "OOEnumFlags.h"
#include "OOEnumTable.h"

enum class OOScanClass : std::int32_t {
  kNotSet = -1,
  kNoDraw = 0,
  kNeutral = 1,
  kStation = 3,
  kTarget = 4,
  kCargo = 5,
  kMissile = 6,
  kRock = 7,
  kMine = 8,
  kThargoid = 9,
  kBuoy = 10,
  kVisualEffect = 11,
  kWormhole = 444,
  kPlayer = 100,
  kPolice = 999,
  kMilitary = 333,
};

// What an unknown name reads as.
inline constexpr OOScanClass kOOScanClassDefault = OOScanClass::kNotSet;

// The name of each value. No default: -Wswitch reports a value added without
// one.
constexpr std::string_view OOEnumName(OOScanClass value) noexcept {
  switch (value) {
    case OOScanClass::kNotSet:
      return "CLASS_NOT_SET";
    case OOScanClass::kNoDraw:
      return "CLASS_NO_DRAW";
    case OOScanClass::kNeutral:
      return "CLASS_NEUTRAL";
    case OOScanClass::kStation:
      return "CLASS_STATION";
    case OOScanClass::kTarget:
      return "CLASS_TARGET";
    case OOScanClass::kCargo:
      return "CLASS_CARGO";
    case OOScanClass::kMissile:
      return "CLASS_MISSILE";
    case OOScanClass::kRock:
      return "CLASS_ROCK";
    case OOScanClass::kMine:
      return "CLASS_MINE";
    case OOScanClass::kThargoid:
      return "CLASS_THARGOID";
    case OOScanClass::kBuoy:
      return "CLASS_BUOY";
    case OOScanClass::kVisualEffect:
      return "CLASS_VISUAL_EFFECT";
    case OOScanClass::kWormhole:
      return "CLASS_WORMHOLE";
    case OOScanClass::kPlayer:
      return "CLASS_PLAYER";
    case OOScanClass::kPolice:
      return "CLASS_POLICE";
    case OOScanClass::kMilitary:
      return "CLASS_MILITARY";
  }
  return {};
}

inline constexpr auto kOOScanClassTable = oo::MakeEnumTable<
    OOScanClass, OOScanClass::kNotSet, OOScanClass::kNoDraw,
    OOScanClass::kNeutral, OOScanClass::kStation, OOScanClass::kTarget,
    OOScanClass::kCargo, OOScanClass::kMissile, OOScanClass::kRock,
    OOScanClass::kMine, OOScanClass::kThargoid, OOScanClass::kBuoy,
    OOScanClass::kVisualEffect, OOScanClass::kWormhole, OOScanClass::kPlayer,
    OOScanClass::kPolice, OOScanClass::kMilitary>();

// Every number that leaves the program, pinned.
static_assert(oo::ToUnderlying(OOScanClass::kNotSet) == -1);
static_assert(oo::ToUnderlying(OOScanClass::kNoDraw) == 0);
static_assert(oo::ToUnderlying(OOScanClass::kNeutral) == 1);
static_assert(oo::ToUnderlying(OOScanClass::kStation) == 3);
static_assert(oo::ToUnderlying(OOScanClass::kTarget) == 4);
static_assert(oo::ToUnderlying(OOScanClass::kCargo) == 5);
static_assert(oo::ToUnderlying(OOScanClass::kMissile) == 6);
static_assert(oo::ToUnderlying(OOScanClass::kRock) == 7);
static_assert(oo::ToUnderlying(OOScanClass::kMine) == 8);
static_assert(oo::ToUnderlying(OOScanClass::kThargoid) == 9);
static_assert(oo::ToUnderlying(OOScanClass::kBuoy) == 10);
static_assert(oo::ToUnderlying(OOScanClass::kVisualEffect) == 11);
static_assert(oo::ToUnderlying(OOScanClass::kWormhole) == 444);
static_assert(oo::ToUnderlying(OOScanClass::kPlayer) == 100);
static_assert(oo::ToUnderlying(OOScanClass::kPolice) == 999);
static_assert(oo::ToUnderlying(OOScanClass::kMilitary) == 333);
