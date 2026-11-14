

/*	OOShipDamageType.h

The values of a damage type: JS events carry its name, and the
names the game reads and writes for them. It was OOShipDamageType.tbl, an
X-macro table.
*/

#pragma once

#include <cstdint>
#include <string_view>

#include "OOEnumFlags.h"
#include "OOEnumTable.h"

enum class OOShipDamageType : std::int32_t {
  kScrape,
  kHeat,
  kEnergy,
  kCascadeWeapon,
  kHitAPlanet,
  kHitASun,
  kRemoved,
};

// What an unknown name reads as.
inline constexpr OOShipDamageType kOOShipDamageTypeDefault =
    OOShipDamageType::kEnergy;

// The name of each value. No default: -Wswitch reports a value added without
// one.
constexpr std::string_view OOEnumName(OOShipDamageType value) noexcept {
  switch (value) {
    case OOShipDamageType::kScrape:
      return "scrape damage";
    case OOShipDamageType::kHeat:
      return "heat damage";
    case OOShipDamageType::kEnergy:
      return "energy damage";
    case OOShipDamageType::kCascadeWeapon:
      return "cascade weapon";
    case OOShipDamageType::kHitAPlanet:
      return "hit a planet";
    case OOShipDamageType::kHitASun:
      return "hit a sun";
    case OOShipDamageType::kRemoved:
      return "removed";
  }
  return {};
}

inline constexpr auto kOOShipDamageTypeTable =
    oo::MakeEnumTable<OOShipDamageType, OOShipDamageType::kScrape,
                      OOShipDamageType::kHeat, OOShipDamageType::kEnergy,
                      OOShipDamageType::kCascadeWeapon,
                      OOShipDamageType::kHitAPlanet, OOShipDamageType::kHitASun,
                      OOShipDamageType::kRemoved>();

// Every number that leaves the program, pinned.
static_assert(oo::ToUnderlying(OOShipDamageType::kScrape) == 0);
static_assert(oo::ToUnderlying(OOShipDamageType::kHeat) == 1);
static_assert(oo::ToUnderlying(OOShipDamageType::kEnergy) == 2);
static_assert(oo::ToUnderlying(OOShipDamageType::kCascadeWeapon) == 3);
static_assert(oo::ToUnderlying(OOShipDamageType::kHitAPlanet) == 4);
static_assert(oo::ToUnderlying(OOShipDamageType::kHitASun) == 5);
static_assert(oo::ToUnderlying(OOShipDamageType::kRemoved) == 6);
