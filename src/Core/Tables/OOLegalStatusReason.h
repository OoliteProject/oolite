/*	OOLegalStatusReason.h

The values of the reason a legal status changed: JS sees its name, and the names
the game reads and writes for them. It was OOLegalStatusReason.tbl, an X-macro
table.
*/

#pragma once

#include <cstdint>
#include <string_view>

#include "OOEnumFlags.h"
#include "OOEnumTable.h"

enum class OOLegalStatusReason : std::int32_t {
  kUnknown,
  kSetup,
  kByScript,
  kAttackedPolice,
  kAttackedMainStation,
  kAttackedInnocent,
  kSeenByPolice,
  kDistressCall,
  kIllegalExports,
  kIllegalImports,
  kAssistingOffender,
  kNewGalaxy,
  kNewSystem,
  kPaidFine,
  kEscapePod,
  kAssistingPolice,
  kPoliceAreClean,
  // kThereCanBeOnlyOne,
};

// What an unknown name reads as.
inline constexpr OOLegalStatusReason kOOLegalStatusReasonDefault =
    OOLegalStatusReason::kUnknown;

// The name of each value. No default: -Wswitch reports a value added without
// one.
constexpr std::string_view OOEnumName(OOLegalStatusReason value) noexcept {
  switch (value) {
    case OOLegalStatusReason::kUnknown:
      return "unknown";
    case OOLegalStatusReason::kSetup:
      return "setup actions";
    case OOLegalStatusReason::kByScript:
      return "scripted";
    case OOLegalStatusReason::kAttackedPolice:
      return "attacked police";
    case OOLegalStatusReason::kAttackedMainStation:
      return "attacked main station";
    case OOLegalStatusReason::kAttackedInnocent:
      return "attacked innocent";
    case OOLegalStatusReason::kSeenByPolice:
      return "seen by police";
    case OOLegalStatusReason::kDistressCall:
      return "distress call";
    case OOLegalStatusReason::kIllegalExports:
      return "illegal exports";
    case OOLegalStatusReason::kIllegalImports:
      return "illegal imports";
    case OOLegalStatusReason::kAssistingOffender:
      return "assisting offenders";
    case OOLegalStatusReason::kNewGalaxy:
      return "new galaxy";
    case OOLegalStatusReason::kNewSystem:
      return "new system";
    case OOLegalStatusReason::kPaidFine:
      return "paid fine";
    case OOLegalStatusReason::kEscapePod:
      return "escape pod";
    case OOLegalStatusReason::kAssistingPolice:
      return "assisting police";
    case OOLegalStatusReason::kPoliceAreClean:
      return "police are clean";
      // case OOLegalStatusReason::kThereCanBeOnlyOne:
      //   return "there can be only one";
  }
  return {};
}

inline constexpr auto kOOLegalStatusReasonTable = oo::MakeEnumTable<
    OOLegalStatusReason, OOLegalStatusReason::kUnknown,
    OOLegalStatusReason::kSetup, OOLegalStatusReason::kByScript,
    OOLegalStatusReason::kAttackedPolice,
    OOLegalStatusReason::kAttackedMainStation,
    OOLegalStatusReason::kAttackedInnocent, OOLegalStatusReason::kSeenByPolice,
    OOLegalStatusReason::kDistressCall, OOLegalStatusReason::kIllegalExports,
    OOLegalStatusReason::kIllegalImports,
    OOLegalStatusReason::kAssistingOffender, OOLegalStatusReason::kNewGalaxy,
    OOLegalStatusReason::kNewSystem, OOLegalStatusReason::kPaidFine,
    OOLegalStatusReason::kEscapePod, OOLegalStatusReason::kAssistingPolice,
    OOLegalStatusReason::kPoliceAreClean>();

// Every number that leaves the program, pinned.
static_assert(oo::ToUnderlying(OOLegalStatusReason::kUnknown) == 0);
static_assert(oo::ToUnderlying(OOLegalStatusReason::kSetup) == 1);
static_assert(oo::ToUnderlying(OOLegalStatusReason::kByScript) == 2);
static_assert(oo::ToUnderlying(OOLegalStatusReason::kAttackedPolice) == 3);
static_assert(oo::ToUnderlying(OOLegalStatusReason::kAttackedMainStation) == 4);
static_assert(oo::ToUnderlying(OOLegalStatusReason::kAttackedInnocent) == 5);
static_assert(oo::ToUnderlying(OOLegalStatusReason::kSeenByPolice) == 6);
static_assert(oo::ToUnderlying(OOLegalStatusReason::kDistressCall) == 7);
static_assert(oo::ToUnderlying(OOLegalStatusReason::kIllegalExports) == 8);
static_assert(oo::ToUnderlying(OOLegalStatusReason::kIllegalImports) == 9);
static_assert(oo::ToUnderlying(OOLegalStatusReason::kAssistingOffender) == 10);
static_assert(oo::ToUnderlying(OOLegalStatusReason::kNewGalaxy) == 11);
static_assert(oo::ToUnderlying(OOLegalStatusReason::kNewSystem) == 12);
static_assert(oo::ToUnderlying(OOLegalStatusReason::kPaidFine) == 13);
static_assert(oo::ToUnderlying(OOLegalStatusReason::kEscapePod) == 14);
static_assert(oo::ToUnderlying(OOLegalStatusReason::kAssistingPolice) == 15);
static_assert(oo::ToUnderlying(OOLegalStatusReason::kPoliceAreClean) == 16);
