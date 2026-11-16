/*	OOEnumTable.h
        The name table of an enum that has external names: the names a save
   game, a plist or a script uses. Each name is the enum's OOEnumName, written
   out in the enum's header, never derived from the identifier. Lookups are
   exact and case-sensitive.

            inline constexpr auto kViewTable =
                oo::MakeEnumTable<OOViewID, OOViewID::kForward,
   OOViewID::kAft>(); kViewTable.name(OOViewID::kAft);   // "VIEW_AFT"
            kViewTable.value("VIEW_AFT");      // OOViewID::kAft
*/

#pragma once

#include <array>
#include <cstddef>
#include <optional>
#include <string_view>
#include <utility>

namespace oo {

template <class E, std::size_t N>
struct EnumTable {
  std::array<std::pair<E, std::string_view>, N> entries;

  // The name of e, or "" if e is not in the table.
  constexpr std::string_view name(E e) const noexcept {
    for (const auto& [value, entryName] : entries) {
      if (value == e) return entryName;
    }
    return {};
  }

  // The value named name, or nullopt if no entry has that name.
  constexpr std::optional<E> value(std::string_view name) const noexcept {
    for (const auto& [entryValue, entryName] : entries) {
      if (entryName == name) return entryValue;
    }
    return std::nullopt;
  }
};

// Builds the table from E's OOEnumName over the listed values.
template <class E, E... Values>
constexpr EnumTable<E, sizeof...(Values)> MakeEnumTable() noexcept {
  return {{{std::pair<E, std::string_view>{Values, OOEnumName(Values)}...}}};
}

}  // namespace oo
