/*	OOEnumFlags.h
        Bit operators for flag enums, opt-in per enum, and ToUnderlying.

        A flag enum opts in by declaring, in its own namespace,

            constexpr std::true_type OOEnableFlagOperators(MyFlags);

        which argument-dependent lookup finds. The operators are global
   templates. Uses of a flag enum declared in the global namespace find them
   through argument-dependent lookup from anywhere, inside namespace oo
   included. A flag enum declared inside a namespace finds them only by ordinary
   lookup, which stops at the first enclosing namespace that declares any
   operator of that name; such a namespace adds `using ::operator|;` and the
   others.
*/

#pragma once

#include <concepts>
#include <type_traits>
#include <utility>

namespace oo {

template <class E>
  requires std::is_enum_v<E>
constexpr std::underlying_type_t<E> ToUnderlying(E e) noexcept {
  return static_cast<std::underlying_type_t<E>>(e);
}

template <class E>
concept FlagEnum = std::is_enum_v<E> && requires(E e) {
  { OOEnableFlagOperators(e) } -> std::same_as<std::true_type>;
};

// True if any bit of v is set.
template <FlagEnum E>
constexpr bool Any(E v) noexcept {
  return ToUnderlying(v) != 0;
}

}  // namespace oo

template <oo::FlagEnum E>
constexpr E operator|(E a, E b) noexcept {
  return static_cast<E>(oo::ToUnderlying(a) | oo::ToUnderlying(b));
}
template <oo::FlagEnum E>
constexpr E operator&(E a, E b) noexcept {
  return static_cast<E>(oo::ToUnderlying(a) & oo::ToUnderlying(b));
}
template <oo::FlagEnum E>
constexpr E operator^(E a, E b) noexcept {
  return static_cast<E>(oo::ToUnderlying(a) ^ oo::ToUnderlying(b));
}
template <oo::FlagEnum E>
constexpr E operator~(E a) noexcept {
  return static_cast<E>(~oo::ToUnderlying(a));
}
template <oo::FlagEnum E>
constexpr E& operator|=(E& a, E b) noexcept {
  return a = a | b;
}
template <oo::FlagEnum E>
constexpr E& operator&=(E& a, E b) noexcept {
  return a = a & b;
}
template <oo::FlagEnum E>
constexpr E& operator^=(E& a, E b) noexcept {
  return a = a ^ b;
}
