/*	oofnd/Expected.hpp
	oo::Expected<T, E>: a C++20 polyfill with std::expected's API (C++23, [expected]).

	ADR-0011: conversion targets C++20; std::expected arrives with the Phase 6 upgrade to C++23.
	Until then every oofnd error path returns oo::Expected, and the Phase 6 swap is a rename:

	    oo::Expected           -> std::expected
	    oo::Unexpected         -> std::unexpected
	    oo::unexpect / _t      -> std::unexpect / std::unexpect_t
	    oo::BadExpectedAccess  -> std::bad_expected_access

	Everything else (member names, overload sets, constraints, the monadic operations and_then /
	or_else / transform / transform_error, error_or, the equality operators) follows the C++23
	standard, so no call site changes. std::in_place / std::in_place_t are used directly: they are
	C++17 and need no polyfill.

	Exceptions. oofnd APIs do not throw; they return Expected. value() on an Expected holding an
	error is a programming error, and like std::expected it throws BadExpectedAccess<E> when the TU
	is compiled with exceptions enabled. Built with -fno-exceptions it calls std::abort() instead,
	so the header is usable either way. The strong exception guarantee of assignment and swap is
	implemented as the standard specifies it when exceptions are on.

	Deliberately not provided: anything post-C++23 (e.g. C++26's constraint tweaks). Header-only;
	no third-party code (ADR-0011 permits either a small in-tree polyfill or tl::expected; this is
	the former, so nothing is vendored).
*/

#ifndef OOFND_EXPECTED_HPP
#define OOFND_EXPECTED_HPP

#include <cstdlib>
#include <exception>
#include <functional>
#include <initializer_list>
#include <memory>
#include <type_traits>
#include <utility>

#if defined(__cpp_exceptions) || defined(__EXCEPTIONS) || defined(_CPPUNWIND)
#define OOFND_EXPECTED_EXCEPTIONS 1
#else
#define OOFND_EXPECTED_EXCEPTIONS 0
#endif

namespace oo {

template <class T, class E> class Expected;
template <class E> class Unexpected;
template <class E> class BadExpectedAccess;

// --- BadExpectedAccess ----------------------------------------------------------------------

template <>
class BadExpectedAccess<void> : public std::exception
{
public:
	const char* what() const noexcept override { return "bad access to oo::Expected without expected value"; }

protected:
	BadExpectedAccess() noexcept = default;
	BadExpectedAccess(const BadExpectedAccess&) noexcept = default;
	BadExpectedAccess(BadExpectedAccess&&) noexcept = default;
	BadExpectedAccess& operator=(const BadExpectedAccess&) noexcept = default;
	BadExpectedAccess& operator=(BadExpectedAccess&&) noexcept = default;
	~BadExpectedAccess() override = default;
};

template <class E>
class BadExpectedAccess : public BadExpectedAccess<void>
{
public:
	explicit BadExpectedAccess(E e) : unex_(std::move(e)) {}

	E& error() & noexcept { return unex_; }
	const E& error() const& noexcept { return unex_; }
	E&& error() && noexcept { return std::move(unex_); }
	const E&& error() const&& noexcept { return std::move(unex_); }

private:
	E unex_;
};

// --- unexpect_t ------------------------------------------------------------------------------

struct unexpect_t
{
	explicit unexpect_t() = default;
};
inline constexpr unexpect_t unexpect{};

namespace detail {

template <class T> struct IsUnexpected : std::false_type {};
template <class E> struct IsUnexpected<Unexpected<E>> : std::true_type {};
template <class T> inline constexpr bool kIsUnexpected = IsUnexpected<T>::value;

template <class T> struct IsExpected : std::false_type {};
template <class T, class E> struct IsExpected<Expected<T, E>> : std::true_type {};
template <class T> inline constexpr bool kIsExpected = IsExpected<T>::value;

// [expected.un.general]/2: a valid error type.
template <class E>
inline constexpr bool kCanBeUnexpected = std::is_object_v<E> && !std::is_array_v<E> &&
	!kIsUnexpected<E> && !std::is_const_v<E> && !std::is_volatile_v<E>;

template <class Err>
[[noreturn]] inline void throwBadExpectedAccess([[maybe_unused]] Err&& e)
{
#if OOFND_EXPECTED_EXCEPTIONS
	throw BadExpectedAccess<std::decay_t<Err>>(std::forward<Err>(e));
#else
	std::abort();
#endif
}

// Tags for the private constructors the monadic operations use, so the result is constructed
// directly from the invocation (guaranteed elision) exactly as the standard requires.
struct InPlaceInvokeTag { explicit InPlaceInvokeTag() = default; };
struct UnexpectInvokeTag { explicit UnexpectInvokeTag() = default; };

// [expected.object.assign]/1: reinit-expected.
template <class NewT, class OldT, class... Args>
constexpr void reinitExpected(NewT& newval, OldT& oldval, Args&&... args)
{
	if constexpr (std::is_nothrow_constructible_v<NewT, Args...>)
	{
		std::destroy_at(std::addressof(oldval));
		std::construct_at(std::addressof(newval), std::forward<Args>(args)...);
	}
	else if constexpr (std::is_nothrow_move_constructible_v<NewT>)
	{
		NewT tmp(std::forward<Args>(args)...);
		std::destroy_at(std::addressof(oldval));
		std::construct_at(std::addressof(newval), std::move(tmp));
	}
	else
	{
		OldT tmp(std::move(oldval));
		std::destroy_at(std::addressof(oldval));
#if OOFND_EXPECTED_EXCEPTIONS
		try
		{
			std::construct_at(std::addressof(newval), std::forward<Args>(args)...);
		}
		catch (...)
		{
			std::construct_at(std::addressof(oldval), std::move(tmp));
			throw;
		}
#else
		std::construct_at(std::addressof(newval), std::forward<Args>(args)...);
#endif
	}
}

} // namespace detail

// --- Unexpected --------------------------------------------------------------------------------

template <class E>
class Unexpected
{
	static_assert(detail::kCanBeUnexpected<E>, "oo::Unexpected<E>: E must be a non-array, non-cv object type that is not itself an Unexpected");

public:
	constexpr Unexpected(const Unexpected&) = default;
	constexpr Unexpected(Unexpected&&) = default;

	template <class Err = E>
		requires(!std::is_same_v<std::remove_cvref_t<Err>, Unexpected> &&
			!std::is_same_v<std::remove_cvref_t<Err>, std::in_place_t> &&
			std::is_constructible_v<E, Err>)
	constexpr explicit Unexpected(Err&& e) noexcept(std::is_nothrow_constructible_v<E, Err>)
		: unex_(std::forward<Err>(e)) {}

	template <class... Args>
		requires std::is_constructible_v<E, Args...>
	constexpr explicit Unexpected(std::in_place_t, Args&&... args) noexcept(std::is_nothrow_constructible_v<E, Args...>)
		: unex_(std::forward<Args>(args)...) {}

	template <class U, class... Args>
		requires std::is_constructible_v<E, std::initializer_list<U>&, Args...>
	constexpr explicit Unexpected(std::in_place_t, std::initializer_list<U> il, Args&&... args)
		noexcept(std::is_nothrow_constructible_v<E, std::initializer_list<U>&, Args...>)
		: unex_(il, std::forward<Args>(args)...) {}

	constexpr Unexpected& operator=(const Unexpected&) = default;
	constexpr Unexpected& operator=(Unexpected&&) = default;

	constexpr const E& error() const& noexcept { return unex_; }
	constexpr E& error() & noexcept { return unex_; }
	constexpr const E&& error() const&& noexcept { return std::move(unex_); }
	constexpr E&& error() && noexcept { return std::move(unex_); }

	constexpr void swap(Unexpected& other) noexcept(std::is_nothrow_swappable_v<E>)
		requires std::is_swappable_v<E>
	{
		using std::swap;
		swap(unex_, other.unex_);
	}

	template <class E2>
	friend constexpr bool operator==(const Unexpected& x, const Unexpected<E2>& y)
	{
		return static_cast<bool>(x.error() == y.error());
	}

	friend constexpr void swap(Unexpected& x, Unexpected& y) noexcept(noexcept(x.swap(y)))
		requires std::is_swappable_v<E>
	{
		x.swap(y);
	}

private:
	E unex_;
};

template <class E> Unexpected(E) -> Unexpected<E>;

// --- Expected<T, E> ----------------------------------------------------------------------------

template <class T, class E>
class Expected
{
	static_assert(!std::is_reference_v<T> && !std::is_function_v<T> && !std::is_array_v<T>,
		"oo::Expected<T, E>: T must be an object type or cv void");
	static_assert(!std::is_same_v<std::remove_cv_t<T>, std::in_place_t> &&
		!std::is_same_v<std::remove_cv_t<T>, unexpect_t> &&
		!detail::kIsUnexpected<std::remove_cv_t<T>>,
		"oo::Expected<T, E>: T must not be in_place_t, unexpect_t or an Unexpected");
	static_assert(detail::kCanBeUnexpected<E>, "oo::Expected<T, E>: E must be a valid Unexpected error type");

	template <class, class> friend class Expected;

	// [expected.object.cons]/17-18: converting from Expected<U, G> is disallowed when T (unless
	// it is bool) or Unexpected<E> could be built from the Expected itself.
	template <class U, class G>
	static constexpr bool kConvertsFromExpected =
		(!std::is_same_v<std::remove_cv_t<T>, bool> &&
			(std::is_constructible_v<T, Expected<U, G>&> ||
				std::is_constructible_v<T, Expected<U, G>> ||
				std::is_constructible_v<T, const Expected<U, G>&> ||
				std::is_constructible_v<T, const Expected<U, G>> ||
				std::is_convertible_v<Expected<U, G>&, T> ||
				std::is_convertible_v<Expected<U, G>, T> ||
				std::is_convertible_v<const Expected<U, G>&, T> ||
				std::is_convertible_v<const Expected<U, G>, T>)) ||
		std::is_constructible_v<Unexpected<E>, Expected<U, G>&> ||
		std::is_constructible_v<Unexpected<E>, Expected<U, G>> ||
		std::is_constructible_v<Unexpected<E>, const Expected<U, G>&> ||
		std::is_constructible_v<Unexpected<E>, const Expected<U, G>>;

public:
	using value_type = T;
	using error_type = E;
	using unexpected_type = Unexpected<E>;

	template <class U>
	using rebind = Expected<U, error_type>;

	// --- construction

	constexpr Expected() noexcept(std::is_nothrow_default_constructible_v<T>)
		requires std::is_default_constructible_v<T>
		: val_(), has_val_(true) {}

	constexpr Expected(const Expected&) = delete;
	constexpr Expected(const Expected&)
		requires(std::is_copy_constructible_v<T> && std::is_copy_constructible_v<E> &&
			std::is_trivially_copy_constructible_v<T> && std::is_trivially_copy_constructible_v<E>)
	= default;
	constexpr Expected(const Expected& rhs)
		noexcept(std::is_nothrow_copy_constructible_v<T> && std::is_nothrow_copy_constructible_v<E>)
		requires(std::is_copy_constructible_v<T> && std::is_copy_constructible_v<E> &&
			!(std::is_trivially_copy_constructible_v<T> && std::is_trivially_copy_constructible_v<E>))
		: has_val_(rhs.has_val_)
	{
		if (has_val_)  std::construct_at(std::addressof(val_), rhs.val_);
		else  std::construct_at(std::addressof(unex_), rhs.unex_);
	}

	constexpr Expected(Expected&&)
		requires(std::is_move_constructible_v<T> && std::is_move_constructible_v<E> &&
			std::is_trivially_move_constructible_v<T> && std::is_trivially_move_constructible_v<E>)
	= default;
	constexpr Expected(Expected&& rhs)
		noexcept(std::is_nothrow_move_constructible_v<T> && std::is_nothrow_move_constructible_v<E>)
		requires(std::is_move_constructible_v<T> && std::is_move_constructible_v<E> &&
			!(std::is_trivially_move_constructible_v<T> && std::is_trivially_move_constructible_v<E>))
		: has_val_(rhs.has_val_)
	{
		if (has_val_)  std::construct_at(std::addressof(val_), std::move(rhs.val_));
		else  std::construct_at(std::addressof(unex_), std::move(rhs.unex_));
	}

	template <class U, class G>
		requires(std::is_constructible_v<T, const U&> && std::is_constructible_v<E, const G&> &&
			!kConvertsFromExpected<U, G>)
	constexpr explicit(!std::is_convertible_v<const U&, T> || !std::is_convertible_v<const G&, E>)
	Expected(const Expected<U, G>& rhs)
		noexcept(std::is_nothrow_constructible_v<T, const U&> && std::is_nothrow_constructible_v<E, const G&>)
		: has_val_(rhs.has_val_)
	{
		if (has_val_)  std::construct_at(std::addressof(val_), rhs.val_);
		else  std::construct_at(std::addressof(unex_), rhs.unex_);
	}

	template <class U, class G>
		requires(std::is_constructible_v<T, U> && std::is_constructible_v<E, G> &&
			!kConvertsFromExpected<U, G>)
	constexpr explicit(!std::is_convertible_v<U, T> || !std::is_convertible_v<G, E>)
	Expected(Expected<U, G>&& rhs)
		noexcept(std::is_nothrow_constructible_v<T, U> && std::is_nothrow_constructible_v<E, G>)
		: has_val_(rhs.has_val_)
	{
		if (has_val_)  std::construct_at(std::addressof(val_), std::move(rhs.val_));
		else  std::construct_at(std::addressof(unex_), std::move(rhs.unex_));
	}

	template <class U = std::remove_cv_t<T>>
		requires(!std::is_same_v<std::remove_cvref_t<U>, std::in_place_t> &&
			!std::is_same_v<std::remove_cvref_t<U>, unexpect_t> &&
			!std::is_same_v<std::remove_cvref_t<U>, Expected> &&
			!detail::kIsUnexpected<std::remove_cvref_t<U>> &&
			std::is_constructible_v<T, U> &&
			(!std::is_same_v<std::remove_cv_t<T>, bool> || !detail::kIsExpected<std::remove_cvref_t<U>>))
	constexpr explicit(!std::is_convertible_v<U, T>)
	Expected(U&& v) noexcept(std::is_nothrow_constructible_v<T, U>)
		: val_(std::forward<U>(v)), has_val_(true) {}

	template <class G>
		requires std::is_constructible_v<E, const G&>
	constexpr explicit(!std::is_convertible_v<const G&, E>)
	Expected(const Unexpected<G>& e) noexcept(std::is_nothrow_constructible_v<E, const G&>)
		: unex_(e.error()), has_val_(false) {}

	template <class G>
		requires std::is_constructible_v<E, G>
	constexpr explicit(!std::is_convertible_v<G, E>)
	Expected(Unexpected<G>&& e) noexcept(std::is_nothrow_constructible_v<E, G>)
		: unex_(std::move(e).error()), has_val_(false) {}

	template <class... Args>
		requires std::is_constructible_v<T, Args...>
	constexpr explicit Expected(std::in_place_t, Args&&... args) noexcept(std::is_nothrow_constructible_v<T, Args...>)
		: val_(std::forward<Args>(args)...), has_val_(true) {}

	template <class U, class... Args>
		requires std::is_constructible_v<T, std::initializer_list<U>&, Args...>
	constexpr explicit Expected(std::in_place_t, std::initializer_list<U> il, Args&&... args)
		noexcept(std::is_nothrow_constructible_v<T, std::initializer_list<U>&, Args...>)
		: val_(il, std::forward<Args>(args)...), has_val_(true) {}

	template <class... Args>
		requires std::is_constructible_v<E, Args...>
	constexpr explicit Expected(unexpect_t, Args&&... args) noexcept(std::is_nothrow_constructible_v<E, Args...>)
		: unex_(std::forward<Args>(args)...), has_val_(false) {}

	template <class U, class... Args>
		requires std::is_constructible_v<E, std::initializer_list<U>&, Args...>
	constexpr explicit Expected(unexpect_t, std::initializer_list<U> il, Args&&... args)
		noexcept(std::is_nothrow_constructible_v<E, std::initializer_list<U>&, Args...>)
		: unex_(il, std::forward<Args>(args)...), has_val_(false) {}

	// --- destruction

	constexpr ~Expected()
		requires(std::is_trivially_destructible_v<T> && std::is_trivially_destructible_v<E>)
	= default;
	constexpr ~Expected()
		requires(!(std::is_trivially_destructible_v<T> && std::is_trivially_destructible_v<E>))
	{
		if (has_val_)  std::destroy_at(std::addressof(val_));
		else  std::destroy_at(std::addressof(unex_));
	}

	// --- assignment

	constexpr Expected& operator=(const Expected&) = delete;
	constexpr Expected& operator=(const Expected& rhs)
		noexcept(std::is_nothrow_copy_assignable_v<T> && std::is_nothrow_copy_constructible_v<T> &&
			std::is_nothrow_copy_assignable_v<E> && std::is_nothrow_copy_constructible_v<E>)
		requires(std::is_copy_assignable_v<T> && std::is_copy_constructible_v<T> &&
			std::is_copy_assignable_v<E> && std::is_copy_constructible_v<E> &&
			(std::is_nothrow_move_constructible_v<T> || std::is_nothrow_move_constructible_v<E>))
	{
		if (has_val_ && rhs.has_val_)  val_ = rhs.val_;
		else if (has_val_)  detail::reinitExpected(unex_, val_, rhs.unex_);
		else if (rhs.has_val_)  detail::reinitExpected(val_, unex_, rhs.val_);
		else  unex_ = rhs.unex_;
		has_val_ = rhs.has_val_;
		return *this;
	}

	constexpr Expected& operator=(Expected&& rhs)
		noexcept(std::is_nothrow_move_assignable_v<T> && std::is_nothrow_move_constructible_v<T> &&
			std::is_nothrow_move_assignable_v<E> && std::is_nothrow_move_constructible_v<E>)
		requires(std::is_move_constructible_v<T> && std::is_move_assignable_v<T> &&
			std::is_move_constructible_v<E> && std::is_move_assignable_v<E> &&
			(std::is_nothrow_move_constructible_v<T> || std::is_nothrow_move_constructible_v<E>))
	{
		if (has_val_ && rhs.has_val_)  val_ = std::move(rhs.val_);
		else if (has_val_)  detail::reinitExpected(unex_, val_, std::move(rhs.unex_));
		else if (rhs.has_val_)  detail::reinitExpected(val_, unex_, std::move(rhs.val_));
		else  unex_ = std::move(rhs.unex_);
		has_val_ = rhs.has_val_;
		return *this;
	}

	template <class U = std::remove_cv_t<T>>
		requires(!std::is_same_v<Expected, std::remove_cvref_t<U>> &&
			!detail::kIsUnexpected<std::remove_cvref_t<U>> &&
			std::is_constructible_v<T, U> && std::is_assignable_v<T&, U> &&
			(std::is_nothrow_constructible_v<T, U> || std::is_nothrow_move_constructible_v<T> ||
				std::is_nothrow_move_constructible_v<E>))
	constexpr Expected& operator=(U&& v)
	{
		if (has_val_)  val_ = std::forward<U>(v);
		else
		{
			detail::reinitExpected(val_, unex_, std::forward<U>(v));
			has_val_ = true;
		}
		return *this;
	}

	template <class G>
		requires(std::is_constructible_v<E, const G&> && std::is_assignable_v<E&, const G&> &&
			(std::is_nothrow_constructible_v<E, const G&> || std::is_nothrow_move_constructible_v<T> ||
				std::is_nothrow_move_constructible_v<E>))
	constexpr Expected& operator=(const Unexpected<G>& e)
	{
		if (has_val_)
		{
			detail::reinitExpected(unex_, val_, e.error());
			has_val_ = false;
		}
		else  unex_ = e.error();
		return *this;
	}

	template <class G>
		requires(std::is_constructible_v<E, G> && std::is_assignable_v<E&, G> &&
			(std::is_nothrow_constructible_v<E, G> || std::is_nothrow_move_constructible_v<T> ||
				std::is_nothrow_move_constructible_v<E>))
	constexpr Expected& operator=(Unexpected<G>&& e)
	{
		if (has_val_)
		{
			detail::reinitExpected(unex_, val_, std::move(e).error());
			has_val_ = false;
		}
		else  unex_ = std::move(e).error();
		return *this;
	}

	template <class... Args>
		requires std::is_nothrow_constructible_v<T, Args...>
	constexpr T& emplace(Args&&... args) noexcept
	{
		if (has_val_)  std::destroy_at(std::addressof(val_));
		else
		{
			std::destroy_at(std::addressof(unex_));
			has_val_ = true;
		}
		return *std::construct_at(std::addressof(val_), std::forward<Args>(args)...);
	}

	template <class U, class... Args>
		requires std::is_nothrow_constructible_v<T, std::initializer_list<U>&, Args...>
	constexpr T& emplace(std::initializer_list<U> il, Args&&... args) noexcept
	{
		if (has_val_)  std::destroy_at(std::addressof(val_));
		else
		{
			std::destroy_at(std::addressof(unex_));
			has_val_ = true;
		}
		return *std::construct_at(std::addressof(val_), il, std::forward<Args>(args)...);
	}

	// --- swap

	constexpr void swap(Expected& rhs)
		noexcept(std::is_nothrow_move_constructible_v<T> && std::is_nothrow_swappable_v<T> &&
			std::is_nothrow_move_constructible_v<E> && std::is_nothrow_swappable_v<E>)
		requires(std::is_swappable_v<T> && std::is_swappable_v<E> &&
			std::is_move_constructible_v<T> && std::is_move_constructible_v<E> &&
			(std::is_nothrow_move_constructible_v<T> || std::is_nothrow_move_constructible_v<E>))
	{
		using std::swap;
		if (has_val_ && rhs.has_val_)  swap(val_, rhs.val_);
		else if (!has_val_ && !rhs.has_val_)  swap(unex_, rhs.unex_);
		else if (!has_val_)  rhs.swap(*this);
		else  swapValueWithError(rhs);
	}

	friend constexpr void swap(Expected& x, Expected& y) noexcept(noexcept(x.swap(y)))
		requires requires { x.swap(y); }
	{
		x.swap(y);
	}

	// --- observers

	constexpr const T* operator->() const noexcept { return std::addressof(val_); }
	constexpr T* operator->() noexcept { return std::addressof(val_); }
	constexpr const T& operator*() const& noexcept { return val_; }
	constexpr T& operator*() & noexcept { return val_; }
	constexpr const T&& operator*() const&& noexcept { return std::move(val_); }
	constexpr T&& operator*() && noexcept { return std::move(val_); }

	constexpr explicit operator bool() const noexcept { return has_val_; }
	constexpr bool has_value() const noexcept { return has_val_; }

	constexpr const T& value() const&
	{
		static_assert(std::is_copy_constructible_v<E>, "oo::Expected::value() const& requires a copyable E");
		if (!has_val_)  detail::throwBadExpectedAccess(std::as_const(unex_));
		return val_;
	}
	constexpr T& value() &
	{
		static_assert(std::is_copy_constructible_v<E>, "oo::Expected::value() & requires a copyable E");
		if (!has_val_)  detail::throwBadExpectedAccess(std::as_const(unex_));
		return val_;
	}
	constexpr const T&& value() const&&
	{
		static_assert(std::is_copy_constructible_v<E>, "oo::Expected::value() const&& requires a copyable E");
		if (!has_val_)  detail::throwBadExpectedAccess(std::move(unex_));
		return std::move(val_);
	}
	constexpr T&& value() &&
	{
		static_assert(std::is_copy_constructible_v<E> && std::is_constructible_v<E, decltype(std::move(unex_))>,
			"oo::Expected::value() && requires a copyable, movable E");
		if (!has_val_)  detail::throwBadExpectedAccess(std::move(unex_));
		return std::move(val_);
	}

	constexpr const E& error() const& noexcept { return unex_; }
	constexpr E& error() & noexcept { return unex_; }
	constexpr const E&& error() const&& noexcept { return std::move(unex_); }
	constexpr E&& error() && noexcept { return std::move(unex_); }

	template <class U>
	constexpr T value_or(U&& v) const&
	{
		static_assert(std::is_copy_constructible_v<T> && std::is_convertible_v<U, T>,
			"oo::Expected::value_or() const& requires a copyable T and a U convertible to T");
		return has_val_ ? val_ : static_cast<T>(std::forward<U>(v));
	}
	template <class U>
	constexpr T value_or(U&& v) &&
	{
		static_assert(std::is_move_constructible_v<T> && std::is_convertible_v<U, T>,
			"oo::Expected::value_or() && requires a movable T and a U convertible to T");
		return has_val_ ? std::move(val_) : static_cast<T>(std::forward<U>(v));
	}

	template <class G = E>
	constexpr E error_or(G&& e) const&
	{
		static_assert(std::is_copy_constructible_v<E> && std::is_convertible_v<G, E>,
			"oo::Expected::error_or() const& requires a copyable E and a G convertible to E");
		return has_val_ ? static_cast<E>(std::forward<G>(e)) : unex_;
	}
	template <class G = E>
	constexpr E error_or(G&& e) &&
	{
		static_assert(std::is_move_constructible_v<E> && std::is_convertible_v<G, E>,
			"oo::Expected::error_or() && requires a movable E and a G convertible to E");
		return has_val_ ? static_cast<E>(std::forward<G>(e)) : std::move(unex_);
	}

	// --- monadic operations

	template <class F> constexpr auto and_then(F&& f) & { return andThenImpl(*this, std::forward<F>(f)); }
	template <class F> constexpr auto and_then(F&& f) const& { return andThenImpl(*this, std::forward<F>(f)); }
	template <class F> constexpr auto and_then(F&& f) && { return andThenImpl(std::move(*this), std::forward<F>(f)); }
	template <class F> constexpr auto and_then(F&& f) const&& { return andThenImpl(std::move(*this), std::forward<F>(f)); }

	template <class F> constexpr auto or_else(F&& f) & { return orElseImpl(*this, std::forward<F>(f)); }
	template <class F> constexpr auto or_else(F&& f) const& { return orElseImpl(*this, std::forward<F>(f)); }
	template <class F> constexpr auto or_else(F&& f) && { return orElseImpl(std::move(*this), std::forward<F>(f)); }
	template <class F> constexpr auto or_else(F&& f) const&& { return orElseImpl(std::move(*this), std::forward<F>(f)); }

	template <class F> constexpr auto transform(F&& f) & { return transformImpl(*this, std::forward<F>(f)); }
	template <class F> constexpr auto transform(F&& f) const& { return transformImpl(*this, std::forward<F>(f)); }
	template <class F> constexpr auto transform(F&& f) && { return transformImpl(std::move(*this), std::forward<F>(f)); }
	template <class F> constexpr auto transform(F&& f) const&& { return transformImpl(std::move(*this), std::forward<F>(f)); }

	template <class F> constexpr auto transform_error(F&& f) & { return transformErrorImpl(*this, std::forward<F>(f)); }
	template <class F> constexpr auto transform_error(F&& f) const& { return transformErrorImpl(*this, std::forward<F>(f)); }
	template <class F> constexpr auto transform_error(F&& f) && { return transformErrorImpl(std::move(*this), std::forward<F>(f)); }
	template <class F> constexpr auto transform_error(F&& f) const&& { return transformErrorImpl(std::move(*this), std::forward<F>(f)); }

	// --- equality

	template <class T2, class E2>
		requires(!std::is_void_v<T2>)
	friend constexpr bool operator==(const Expected& x, const Expected<T2, E2>& y)
	{
		if (x.has_value() != y.has_value())  return false;
		return x.has_value() ? static_cast<bool>(*x == *y) : static_cast<bool>(x.error() == y.error());
	}

	template <class T2>
		requires(!detail::kIsExpected<T2> && !detail::kIsUnexpected<T2>)
	friend constexpr bool operator==(const Expected& x, const T2& v)
	{
		return x.has_value() && static_cast<bool>(*x == v);
	}

	template <class E2>
	friend constexpr bool operator==(const Expected& x, const Unexpected<E2>& e)
	{
		return !x.has_value() && static_cast<bool>(x.error() == e.error());
	}

private:
	template <class F, class... Args>
	constexpr explicit Expected(detail::InPlaceInvokeTag, F&& f, Args&&... args)
		: val_(std::invoke(std::forward<F>(f), std::forward<Args>(args)...)), has_val_(true) {}

	template <class F, class... Args>
	constexpr explicit Expected(detail::UnexpectInvokeTag, F&& f, Args&&... args)
		: unex_(std::invoke(std::forward<F>(f), std::forward<Args>(args)...)), has_val_(false) {}

	template <class Self, class F>
	static constexpr auto andThenImpl(Self&& self, F&& f)
	{
		using U = std::remove_cvref_t<std::invoke_result_t<F, decltype(std::forward<Self>(self).val_)>>;
		static_assert(detail::kIsExpected<U>, "oo::Expected::and_then: F must return an oo::Expected");
		static_assert(std::is_same_v<typename U::error_type, E>, "oo::Expected::and_then: F must return the same error_type");
		if (self.has_val_)  return std::invoke(std::forward<F>(f), std::forward<Self>(self).val_);
		return U(unexpect, std::forward<Self>(self).unex_);
	}

	template <class Self, class F>
	static constexpr auto orElseImpl(Self&& self, F&& f)
	{
		using G = std::remove_cvref_t<std::invoke_result_t<F, decltype(std::forward<Self>(self).unex_)>>;
		static_assert(detail::kIsExpected<G>, "oo::Expected::or_else: F must return an oo::Expected");
		static_assert(std::is_same_v<typename G::value_type, T>, "oo::Expected::or_else: F must return the same value_type");
		if (self.has_val_)  return G(std::in_place, std::forward<Self>(self).val_);
		return std::invoke(std::forward<F>(f), std::forward<Self>(self).unex_);
	}

	template <class Self, class F>
	static constexpr auto transformImpl(Self&& self, F&& f)
	{
		using U = std::remove_cv_t<std::invoke_result_t<F, decltype(std::forward<Self>(self).val_)>>;
		using Result = Expected<U, E>;
		if (!self.has_val_)  return Result(unexpect, std::forward<Self>(self).unex_);
		if constexpr (std::is_void_v<U>)
		{
			std::invoke(std::forward<F>(f), std::forward<Self>(self).val_);
			return Result();
		}
		else
		{
			return Result(detail::InPlaceInvokeTag{}, std::forward<F>(f), std::forward<Self>(self).val_);
		}
	}

	template <class Self, class F>
	static constexpr auto transformErrorImpl(Self&& self, F&& f)
	{
		using G = std::remove_cv_t<std::invoke_result_t<F, decltype(std::forward<Self>(self).unex_)>>;
		using Result = Expected<T, G>;
		if (self.has_val_)  return Result(std::in_place, std::forward<Self>(self).val_);
		return Result(detail::UnexpectInvokeTag{}, std::forward<F>(f), std::forward<Self>(self).unex_);
	}

	// Precondition: *this holds a value, rhs holds an error ([expected.object.swap] table).
	constexpr void swapValueWithError(Expected& rhs)
	{
		if constexpr (std::is_nothrow_move_constructible_v<E>)
		{
			E tmp(std::move(rhs.unex_));
			std::destroy_at(std::addressof(rhs.unex_));
#if OOFND_EXPECTED_EXCEPTIONS
			try
			{
				std::construct_at(std::addressof(rhs.val_), std::move(val_));
			}
			catch (...)
			{
				std::construct_at(std::addressof(rhs.unex_), std::move(tmp));
				throw;
			}
#else
			std::construct_at(std::addressof(rhs.val_), std::move(val_));
#endif
			std::destroy_at(std::addressof(val_));
			std::construct_at(std::addressof(unex_), std::move(tmp));
		}
		else
		{
			T tmp(std::move(val_));
			std::destroy_at(std::addressof(val_));
#if OOFND_EXPECTED_EXCEPTIONS
			try
			{
				std::construct_at(std::addressof(unex_), std::move(rhs.unex_));
			}
			catch (...)
			{
				std::construct_at(std::addressof(val_), std::move(tmp));
				throw;
			}
#else
			std::construct_at(std::addressof(unex_), std::move(rhs.unex_));
#endif
			std::destroy_at(std::addressof(rhs.unex_));
			std::construct_at(std::addressof(rhs.val_), std::move(tmp));
		}
		has_val_ = false;
		rhs.has_val_ = true;
	}

	union
	{
		T val_;
		E unex_;
	};
	bool has_val_;
};

// --- Expected<void, E> -------------------------------------------------------------------------

template <class T, class E>
	requires std::is_void_v<T>
class Expected<T, E>
{
	static_assert(detail::kCanBeUnexpected<E>, "oo::Expected<void, E>: E must be a valid Unexpected error type");

	template <class, class> friend class Expected;

	template <class U, class G>
	static constexpr bool kConvertsFromExpected =
		std::is_constructible_v<Unexpected<E>, Expected<U, G>&> ||
		std::is_constructible_v<Unexpected<E>, Expected<U, G>> ||
		std::is_constructible_v<Unexpected<E>, const Expected<U, G>&> ||
		std::is_constructible_v<Unexpected<E>, const Expected<U, G>>;

public:
	using value_type = T;
	using error_type = E;
	using unexpected_type = Unexpected<E>;

	template <class U>
	using rebind = Expected<U, error_type>;

	// --- construction

	constexpr Expected() noexcept : dummy_(), has_val_(true) {}

	constexpr Expected(const Expected&) = delete;
	constexpr Expected(const Expected&)
		requires(std::is_copy_constructible_v<E> && std::is_trivially_copy_constructible_v<E>)
	= default;
	constexpr Expected(const Expected& rhs) noexcept(std::is_nothrow_copy_constructible_v<E>)
		requires(std::is_copy_constructible_v<E> && !std::is_trivially_copy_constructible_v<E>)
		: has_val_(rhs.has_val_)
	{
		if (!has_val_)  std::construct_at(std::addressof(unex_), rhs.unex_);
	}

	constexpr Expected(Expected&&)
		requires(std::is_move_constructible_v<E> && std::is_trivially_move_constructible_v<E>)
	= default;
	constexpr Expected(Expected&& rhs) noexcept(std::is_nothrow_move_constructible_v<E>)
		requires(std::is_move_constructible_v<E> && !std::is_trivially_move_constructible_v<E>)
		: has_val_(rhs.has_val_)
	{
		if (!has_val_)  std::construct_at(std::addressof(unex_), std::move(rhs.unex_));
	}

	template <class U, class G>
		requires(std::is_void_v<U> && std::is_constructible_v<E, const G&> && !kConvertsFromExpected<U, G>)
	constexpr explicit(!std::is_convertible_v<const G&, E>)
	Expected(const Expected<U, G>& rhs) noexcept(std::is_nothrow_constructible_v<E, const G&>)
		: has_val_(rhs.has_val_)
	{
		if (!has_val_)  std::construct_at(std::addressof(unex_), rhs.unex_);
	}

	template <class U, class G>
		requires(std::is_void_v<U> && std::is_constructible_v<E, G> && !kConvertsFromExpected<U, G>)
	constexpr explicit(!std::is_convertible_v<G, E>)
	Expected(Expected<U, G>&& rhs) noexcept(std::is_nothrow_constructible_v<E, G>)
		: has_val_(rhs.has_val_)
	{
		if (!has_val_)  std::construct_at(std::addressof(unex_), std::move(rhs.unex_));
	}

	template <class G>
		requires std::is_constructible_v<E, const G&>
	constexpr explicit(!std::is_convertible_v<const G&, E>)
	Expected(const Unexpected<G>& e) noexcept(std::is_nothrow_constructible_v<E, const G&>)
		: unex_(e.error()), has_val_(false) {}

	template <class G>
		requires std::is_constructible_v<E, G>
	constexpr explicit(!std::is_convertible_v<G, E>)
	Expected(Unexpected<G>&& e) noexcept(std::is_nothrow_constructible_v<E, G>)
		: unex_(std::move(e).error()), has_val_(false) {}

	constexpr explicit Expected(std::in_place_t) noexcept : dummy_(), has_val_(true) {}

	template <class... Args>
		requires std::is_constructible_v<E, Args...>
	constexpr explicit Expected(unexpect_t, Args&&... args) noexcept(std::is_nothrow_constructible_v<E, Args...>)
		: unex_(std::forward<Args>(args)...), has_val_(false) {}

	template <class U, class... Args>
		requires std::is_constructible_v<E, std::initializer_list<U>&, Args...>
	constexpr explicit Expected(unexpect_t, std::initializer_list<U> il, Args&&... args)
		noexcept(std::is_nothrow_constructible_v<E, std::initializer_list<U>&, Args...>)
		: unex_(il, std::forward<Args>(args)...), has_val_(false) {}

	// --- destruction

	constexpr ~Expected() requires std::is_trivially_destructible_v<E> = default;
	constexpr ~Expected() requires(!std::is_trivially_destructible_v<E>)
	{
		if (!has_val_)  std::destroy_at(std::addressof(unex_));
	}

	// --- assignment

	constexpr Expected& operator=(const Expected&) = delete;
	constexpr Expected& operator=(const Expected& rhs)
		noexcept(std::is_nothrow_copy_assignable_v<E> && std::is_nothrow_copy_constructible_v<E>)
		requires(std::is_copy_assignable_v<E> && std::is_copy_constructible_v<E>)
	{
		if (has_val_ && !rhs.has_val_)
		{
			std::construct_at(std::addressof(unex_), rhs.unex_);
			has_val_ = false;
		}
		else if (!has_val_ && rhs.has_val_)
		{
			std::destroy_at(std::addressof(unex_));
			has_val_ = true;
		}
		else if (!has_val_)  unex_ = rhs.unex_;
		return *this;
	}

	constexpr Expected& operator=(Expected&& rhs)
		noexcept(std::is_nothrow_move_constructible_v<E> && std::is_nothrow_move_assignable_v<E>)
		requires(std::is_move_constructible_v<E> && std::is_move_assignable_v<E>)
	{
		if (has_val_ && !rhs.has_val_)
		{
			std::construct_at(std::addressof(unex_), std::move(rhs.unex_));
			has_val_ = false;
		}
		else if (!has_val_ && rhs.has_val_)
		{
			std::destroy_at(std::addressof(unex_));
			has_val_ = true;
		}
		else if (!has_val_)  unex_ = std::move(rhs.unex_);
		return *this;
	}

	template <class G>
		requires(std::is_constructible_v<E, const G&> && std::is_assignable_v<E&, const G&>)
	constexpr Expected& operator=(const Unexpected<G>& e)
	{
		if (has_val_)
		{
			std::construct_at(std::addressof(unex_), e.error());
			has_val_ = false;
		}
		else  unex_ = e.error();
		return *this;
	}

	template <class G>
		requires(std::is_constructible_v<E, G> && std::is_assignable_v<E&, G>)
	constexpr Expected& operator=(Unexpected<G>&& e)
	{
		if (has_val_)
		{
			std::construct_at(std::addressof(unex_), std::move(e).error());
			has_val_ = false;
		}
		else  unex_ = std::move(e).error();
		return *this;
	}

	constexpr void emplace() noexcept
	{
		if (!has_val_)
		{
			std::destroy_at(std::addressof(unex_));
			has_val_ = true;
		}
	}

	// --- swap

	constexpr void swap(Expected& rhs)
		noexcept(std::is_nothrow_move_constructible_v<E> && std::is_nothrow_swappable_v<E>)
		requires(std::is_swappable_v<E> && std::is_move_constructible_v<E>)
	{
		using std::swap;
		if (has_val_ && rhs.has_val_)  return;
		if (!has_val_ && !rhs.has_val_)  swap(unex_, rhs.unex_);
		else if (!has_val_)  rhs.swap(*this);
		else
		{
			std::construct_at(std::addressof(unex_), std::move(rhs.unex_));
			std::destroy_at(std::addressof(rhs.unex_));
			has_val_ = false;
			rhs.has_val_ = true;
		}
	}

	friend constexpr void swap(Expected& x, Expected& y) noexcept(noexcept(x.swap(y)))
		requires requires { x.swap(y); }
	{
		x.swap(y);
	}

	// --- observers

	constexpr explicit operator bool() const noexcept { return has_val_; }
	constexpr bool has_value() const noexcept { return has_val_; }
	constexpr void operator*() const noexcept {}

	constexpr void value() const&
	{
		static_assert(std::is_copy_constructible_v<E>, "oo::Expected<void, E>::value() const& requires a copyable E");
		if (!has_val_)  detail::throwBadExpectedAccess(unex_);
	}
	constexpr void value() &&
	{
		static_assert(std::is_copy_constructible_v<E> && std::is_move_constructible_v<E>,
			"oo::Expected<void, E>::value() && requires a copyable, movable E");
		if (!has_val_)  detail::throwBadExpectedAccess(std::move(unex_));
	}

	constexpr const E& error() const& noexcept { return unex_; }
	constexpr E& error() & noexcept { return unex_; }
	constexpr const E&& error() const&& noexcept { return std::move(unex_); }
	constexpr E&& error() && noexcept { return std::move(unex_); }

	template <class G = E>
	constexpr E error_or(G&& e) const&
	{
		static_assert(std::is_copy_constructible_v<E> && std::is_convertible_v<G, E>,
			"oo::Expected<void, E>::error_or() const& requires a copyable E and a G convertible to E");
		return has_val_ ? static_cast<E>(std::forward<G>(e)) : unex_;
	}
	template <class G = E>
	constexpr E error_or(G&& e) &&
	{
		static_assert(std::is_move_constructible_v<E> && std::is_convertible_v<G, E>,
			"oo::Expected<void, E>::error_or() && requires a movable E and a G convertible to E");
		return has_val_ ? static_cast<E>(std::forward<G>(e)) : std::move(unex_);
	}

	// --- monadic operations

	template <class F> constexpr auto and_then(F&& f) & { return andThenImpl(*this, std::forward<F>(f)); }
	template <class F> constexpr auto and_then(F&& f) const& { return andThenImpl(*this, std::forward<F>(f)); }
	template <class F> constexpr auto and_then(F&& f) && { return andThenImpl(std::move(*this), std::forward<F>(f)); }
	template <class F> constexpr auto and_then(F&& f) const&& { return andThenImpl(std::move(*this), std::forward<F>(f)); }

	template <class F> constexpr auto or_else(F&& f) & { return orElseImpl(*this, std::forward<F>(f)); }
	template <class F> constexpr auto or_else(F&& f) const& { return orElseImpl(*this, std::forward<F>(f)); }
	template <class F> constexpr auto or_else(F&& f) && { return orElseImpl(std::move(*this), std::forward<F>(f)); }
	template <class F> constexpr auto or_else(F&& f) const&& { return orElseImpl(std::move(*this), std::forward<F>(f)); }

	template <class F> constexpr auto transform(F&& f) & { return transformImpl(*this, std::forward<F>(f)); }
	template <class F> constexpr auto transform(F&& f) const& { return transformImpl(*this, std::forward<F>(f)); }
	template <class F> constexpr auto transform(F&& f) && { return transformImpl(std::move(*this), std::forward<F>(f)); }
	template <class F> constexpr auto transform(F&& f) const&& { return transformImpl(std::move(*this), std::forward<F>(f)); }

	template <class F> constexpr auto transform_error(F&& f) & { return transformErrorImpl(*this, std::forward<F>(f)); }
	template <class F> constexpr auto transform_error(F&& f) const& { return transformErrorImpl(*this, std::forward<F>(f)); }
	template <class F> constexpr auto transform_error(F&& f) && { return transformErrorImpl(std::move(*this), std::forward<F>(f)); }
	template <class F> constexpr auto transform_error(F&& f) const&& { return transformErrorImpl(std::move(*this), std::forward<F>(f)); }

	// --- equality

	template <class T2, class E2>
		requires std::is_void_v<T2>
	friend constexpr bool operator==(const Expected& x, const Expected<T2, E2>& y)
	{
		if (x.has_value() != y.has_value())  return false;
		return x.has_value() || static_cast<bool>(x.error() == y.error());
	}

	template <class E2>
	friend constexpr bool operator==(const Expected& x, const Unexpected<E2>& e)
	{
		return !x.has_value() && static_cast<bool>(x.error() == e.error());
	}

private:
	template <class F, class... Args>
	constexpr explicit Expected(detail::UnexpectInvokeTag, F&& f, Args&&... args)
		: unex_(std::invoke(std::forward<F>(f), std::forward<Args>(args)...)), has_val_(false) {}

	template <class Self, class F>
	static constexpr auto andThenImpl(Self&& self, F&& f)
	{
		using U = std::remove_cvref_t<std::invoke_result_t<F>>;
		static_assert(detail::kIsExpected<U>, "oo::Expected::and_then: F must return an oo::Expected");
		static_assert(std::is_same_v<typename U::error_type, E>, "oo::Expected::and_then: F must return the same error_type");
		if (self.has_val_)  return std::invoke(std::forward<F>(f));
		return U(unexpect, std::forward<Self>(self).unex_);
	}

	template <class Self, class F>
	static constexpr auto orElseImpl(Self&& self, F&& f)
	{
		using G = std::remove_cvref_t<std::invoke_result_t<F, decltype(std::forward<Self>(self).unex_)>>;
		static_assert(detail::kIsExpected<G>, "oo::Expected::or_else: F must return an oo::Expected");
		static_assert(std::is_same_v<typename G::value_type, T>, "oo::Expected::or_else: F must return the same value_type");
		if (self.has_val_)  return G();
		return std::invoke(std::forward<F>(f), std::forward<Self>(self).unex_);
	}

	template <class Self, class F>
	static constexpr auto transformImpl(Self&& self, F&& f)
	{
		using U = std::remove_cv_t<std::invoke_result_t<F>>;
		using Result = Expected<U, E>;
		if (!self.has_val_)  return Result(unexpect, std::forward<Self>(self).unex_);
		if constexpr (std::is_void_v<U>)
		{
			std::invoke(std::forward<F>(f));
			return Result();
		}
		else
		{
			return Result(detail::InPlaceInvokeTag{}, std::forward<F>(f));
		}
	}

	template <class Self, class F>
	static constexpr auto transformErrorImpl(Self&& self, F&& f)
	{
		using G = std::remove_cv_t<std::invoke_result_t<F, decltype(std::forward<Self>(self).unex_)>>;
		using Result = Expected<T, G>;
		if (self.has_val_)  return Result();
		return Result(detail::UnexpectInvokeTag{}, std::forward<F>(f), std::forward<Self>(self).unex_);
	}

	struct Empty {};
	union
	{
		Empty dummy_;
		E unex_;
	};
	bool has_val_;
};

} // namespace oo

#undef OOFND_EXPECTED_EXCEPTIONS

#endif // OOFND_EXPECTED_HPP
