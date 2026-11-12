/*	test_OOEnumFlags.cpp
        Spec 009 (US5, design D3): the flag operators of OOEnumFlags.h, the name table of
        OOEnumTable.h and the exemplar converted enum, OODebugFlags. Header-only; no game
        objects. Run: tests/run.sh unit
*/

#include <cstdint>
#include <string_view>

#include "OODebugFlags.h"
#include "OOEnumFlags.h"
#include "OOEnumTable.h"
#include "oo_test.hpp"

namespace {

enum class Plain : std::uint8_t { kA = 1, kB = 2 };  // no OOEnableFlagOperators
static_assert(!oo::FlagEnum<Plain>);
static_assert(oo::FlagEnum<OODebugFlags>);

}  // namespace

// Inside namespace oo, beside an unrelated operator|, a global flag enum's operators are still
// found (argument-dependent lookup looks in the global namespace, the enum's own).
namespace oo {
struct Unrelated {};
constexpr Unrelated operator|(Unrelated, Unrelated) { return {}; }
constexpr OODebugFlags kInsideOo = OODebugFlags::kCollisions | OODebugFlags::kDocking;
}  // namespace oo

OO_TEST(flagOperators) {
  constexpr auto both = OODebugFlags::kCollisions | OODebugFlags::kDocking;
  static_assert(oo::ToUnderlying(both) == 0x0c);
  static_assert(oo::ToUnderlying(oo::kInsideOo) == 0x0c);
  OO_CHECK(oo::Any(both & OODebugFlags::kDocking));
  OO_CHECK(!oo::Any(both & OODebugFlags::kNoDust));
  OO_CHECK(oo::ToUnderlying(both ^ OODebugFlags::kDocking) == 0x04);
  OO_CHECK(oo::ToUnderlying(~OODebugFlags::kNone) == 0xffffffffu);
  OO_CHECK(~OODebugFlags::kNone == OODebugFlags::kAll);

  auto f = OODebugFlags::kNone;
  f |= OODebugFlags::kMisc;
  OO_CHECK(f == OODebugFlags::kMisc);
  f ^= OODebugFlags::kLinkedLists;
  OO_CHECK(oo::ToUnderlying(f) == 0x10000001u);
  f &= OODebugFlags::kLinkedLists;
  OO_CHECK(f == OODebugFlags::kLinkedLists);
  OO_CHECK(!oo::Any(OODebugFlags::kNone));
}

OO_TEST(debugFlagNames) {
  OO_CHECK(OOEnumName(OODebugFlags::kLinkedLists) == "DEBUG_LINKED_LISTS");
  OO_CHECK(OOEnumName(OODebugFlags::kNoShaderFallback) == "DEBUG_NO_SHADER_FALLBACK");
  OO_CHECK(OOEnumName(OODebugFlags::kMisc) == "DEBUG_MISC");
  OO_CHECK(OOEnumName(OODebugFlags::kNone).empty());
  OO_CHECK(OOEnumName(OODebugFlags::kAll).empty());
  // The name is a null-terminated literal, so .data() can name a JS property.
  OO_CHECK(OOEnumName(OODebugFlags::kDocking).data()[13] == '\0');
}

OO_TEST(enumTableLooksUpBothWays) {
  constexpr auto table = oo::MakeEnumTable<OODebugFlags, OODebugFlags::kLinkedLists,
                                           OODebugFlags::kCollisions, OODebugFlags::kMisc>();
  static_assert(table.entries.size() == 3);
  static_assert(table.name(OODebugFlags::kCollisions) == "DEBUG_COLLISIONS");
  static_assert(table.value("DEBUG_MISC") == OODebugFlags::kMisc);
  OO_CHECK(table.name(OODebugFlags::kDocking).empty());  // not in the table
  OO_CHECK(!table.value("DEBUG_DOCKING").has_value());
  OO_CHECK(!table.value("debug_misc").has_value());  // case-sensitive
  OO_CHECK(!table.value("").has_value());
}

OO_TEST_MAIN()
