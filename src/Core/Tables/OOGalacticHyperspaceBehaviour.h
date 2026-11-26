/*	OOGalacticHyperspaceBehaviour.h

The values of the galactic hyperspace behaviour: planetinfo.plist, JS and
callObjC (encoded "i", OOTypeEncodings.h), and the names the game reads and
writes for them. It was OOGalacticHyperspaceBehaviour.tbl, an X-macro table.
*/

#pragma once

#include <cstdint>
#include <string_view>

#include "OOEnumFlags.h"
#include "OOEnumTable.h"

enum class OOGalacticHyperspaceBehaviour : std::int32_t {
  kStandard = 0,
  kAllSystemsReachable = 1,
  kFixedCoordinates = 2,
  kUnknown = -1,
};

// What an unknown name reads as.
inline constexpr OOGalacticHyperspaceBehaviour
    kOOGalacticHyperspaceBehaviourDefault =
        OOGalacticHyperspaceBehaviour::kUnknown;

// The largest behaviour setGalacticHyperspaceBehaviour() accepts. An alias, so
// it takes no switch case and no row.
inline constexpr OOGalacticHyperspaceBehaviour
    kOOGalacticHyperspaceBehaviourMax =
        OOGalacticHyperspaceBehaviour::kFixedCoordinates;

// The name of each value. No default: -Wswitch reports a value added without
// one.
constexpr std::string_view OOEnumName(
    OOGalacticHyperspaceBehaviour value) noexcept {
  switch (value) {
    case OOGalacticHyperspaceBehaviour::kStandard:
      return "BEHAVIOUR_STANDARD";
    case OOGalacticHyperspaceBehaviour::kAllSystemsReachable:
      return "BEHAVIOUR_ALL_SYSTEMS_REACHABLE";
    case OOGalacticHyperspaceBehaviour::kFixedCoordinates:
      return "BEHAVIOUR_FIXED_COORDINATES";
    case OOGalacticHyperspaceBehaviour::kUnknown:
      return "BEHAVIOUR_UNKNOWN";
  }
  return {};
}

inline constexpr auto kOOGalacticHyperspaceBehaviourTable =
    oo::MakeEnumTable<OOGalacticHyperspaceBehaviour,
                      OOGalacticHyperspaceBehaviour::kStandard,
                      OOGalacticHyperspaceBehaviour::kAllSystemsReachable,
                      OOGalacticHyperspaceBehaviour::kFixedCoordinates,
                      OOGalacticHyperspaceBehaviour::kUnknown>();

// Every number that leaves the program, pinned.
static_assert(oo::ToUnderlying(OOGalacticHyperspaceBehaviour::kStandard) == 0);
static_assert(
    oo::ToUnderlying(OOGalacticHyperspaceBehaviour::kAllSystemsReachable) == 1);
static_assert(
    oo::ToUnderlying(OOGalacticHyperspaceBehaviour::kFixedCoordinates) == 2);
static_assert(oo::ToUnderlying(OOGalacticHyperspaceBehaviour::kUnknown) == -1);
