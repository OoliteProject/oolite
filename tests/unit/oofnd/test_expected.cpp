/*	test_expected.cpp
	Unit tests for oofnd/Expected.hpp (bead oo-fde): oo::Expected<T, E>, oo::Unexpected<E>,
	oo::unexpect and oo::BadExpectedAccess, checked against the behaviour C++23 specifies for
	std::expected so that the Phase 6 swap (ADR-0011) is a rename.

	A Tracked value type counts its live instances, so every construction path, assignment
	transition (value <-> error) and swap case is also checked for leaks and double destruction;
	tools/check-oofnd.sh runs this file under AddressSanitizer as well.
*/

#include "oofnd/Expected.hpp"

#include "oo_test.hpp"

#include <memory>
#include <string>
#include <type_traits>
#include <utility>
#include <vector>

namespace {

enum class Err { kNone, kParse, kIO };

// A non-trivial type that counts live instances and remembers whether it was moved from.
struct Tracked
{
	static inline int live = 0;
	int v;
	bool movedFrom = false;

	Tracked() : v(0) { ++live; }
	explicit Tracked(int x) : v(x) { ++live; }
	Tracked(int a, int b) noexcept : v(a * 100 + b) { ++live; }
	Tracked(std::initializer_list<int> il, int extra) noexcept : v(extra) { for (int i : il)  v += i; ++live; }
	Tracked(const Tracked& o) : v(o.v) { ++live; }
	Tracked(Tracked&& o) noexcept : v(o.v) { o.movedFrom = true; ++live; }
	Tracked& operator=(const Tracked& o) { v = o.v; return *this; }
	Tracked& operator=(Tracked&& o) noexcept { v = o.v; o.movedFrom = true; return *this; }
	~Tracked() { --live; }
	bool operator==(const Tracked& o) const { return v == o.v; }
};

using ExpT = oo::Expected<Tracked, std::string>;
using ExpI = oo::Expected<int, Err>;
using ExpV = oo::Expected<void, Err>;

ExpI parsePositive(int x)
{
	if (x < 0)  return oo::Unexpected(Err::kParse);
	return x;
}

ExpV checkNonZero(int x)
{
	if (x == 0)  return oo::Unexpected(Err::kIO);
	return {};
}

// --- compile-time contract --------------------------------------------------------------------

static_assert(std::is_same_v<ExpI::value_type, int>);
static_assert(std::is_same_v<ExpI::error_type, Err>);
static_assert(std::is_same_v<ExpI::unexpected_type, oo::Unexpected<Err>>);
static_assert(std::is_same_v<ExpI::rebind<double>, oo::Expected<double, Err>>);
static_assert(std::is_same_v<ExpV::value_type, void>);

// Triviality propagates where the standard requires it.
static_assert(std::is_trivially_copy_constructible_v<ExpI>);
static_assert(std::is_trivially_move_constructible_v<ExpI>);
static_assert(std::is_trivially_destructible_v<ExpI>);
static_assert(std::is_trivially_destructible_v<ExpV>);
static_assert(!std::is_trivially_destructible_v<ExpT>);

// Move-only payloads make a move-only Expected.
using ExpU = oo::Expected<std::unique_ptr<int>, Err>;
static_assert(!std::is_copy_constructible_v<ExpU>);
static_assert(std::is_move_constructible_v<ExpU>);
static_assert(std::is_move_assignable_v<ExpU>);
static_assert(!std::is_copy_assignable_v<ExpU>);

// Implicit from a value and from Unexpected; explicit from in_place / unexpect.
static_assert(std::is_convertible_v<int, ExpI>);
static_assert(std::is_convertible_v<oo::Unexpected<Err>, ExpI>);
static_assert(!std::is_convertible_v<Err, ExpI>);          // a bare error is not an error
static_assert(!std::is_convertible_v<std::in_place_t, ExpI>);
static_assert(!std::is_convertible_v<int, Tracked>);
static_assert(!std::is_convertible_v<int, ExpT>);          // explicit(!is_convertible_v<U, T>)
static_assert(std::is_constructible_v<ExpT, int>);

// Unexpected CTAD and constraints.
static_assert(std::is_same_v<decltype(oo::Unexpected(Err::kIO)), oo::Unexpected<Err>>);
static_assert(!std::is_convertible_v<Err, oo::Unexpected<Err>>);   // explicit

// constexpr use: the polyfill is usable in constant expressions like std::expected.
constexpr int constexprUse()
{
	ExpI a = 5;
	ExpI b = oo::Unexpected(Err::kIO);
	ExpI c = a.transform([](int x) { return x * 3; });
	b = 7;
	a = oo::Unexpected(Err::kParse);
	return *c + *b + (a.error() == Err::kParse ? 100 : 0) + a.value_or(1000);
}
static_assert(constexprUse() == 15 + 7 + 100 + 1000);

constexpr bool constexprVoid()
{
	ExpV v;
	ExpV e(oo::unexpect, Err::kIO);
	return v.has_value() && !e.has_value() && e.error() == Err::kIO && e.error_or(Err::kNone) == Err::kIO;
}
static_assert(constexprVoid());

// --- construction -----------------------------------------------------------------------------

OO_TEST(defaultConstructsValue)
{
	ExpI a;
	OO_CHECK(a.has_value());
	OO_CHECK(static_cast<bool>(a));
	OO_CHECK_EQ(*a, 0);
	{
		ExpT t;
		OO_CHECK(t.has_value());
		OO_CHECK_EQ(Tracked::live, 1);
	}
	OO_CHECK_EQ(Tracked::live, 0);
}

OO_TEST(constructFromValueAndUnexpected)
{
	ExpI v = 42;
	OO_CHECK(v.has_value());
	OO_CHECK_EQ(v.value(), 42);
	OO_CHECK_EQ(*v, 42);

	ExpI e = oo::Unexpected(Err::kParse);
	OO_CHECK(!e.has_value());
	OO_CHECK(!e);
	OO_CHECK(e.error() == Err::kParse);

	// Converting Unexpected<G> -> Expected<T, E>.
	oo::Expected<int, std::string> s = oo::Unexpected("bad");
	OO_CHECK(!s.has_value());
	OO_CHECK_EQ(s.error(), std::string("bad"));
	const oo::Unexpected<const char*> lvalueUnex("lvalue");
	oo::Expected<int, std::string> s2 = lvalueUnex;
	OO_CHECK_EQ(s2.error(), std::string("lvalue"));
}

OO_TEST(inPlaceAndUnexpectConstruction)
{
	{
		ExpT a(std::in_place, 3, 4);
		OO_CHECK(a.has_value());
		OO_CHECK_EQ(a->v, 304);
		ExpT b(std::in_place, {1, 2, 3}, 10);
		OO_CHECK_EQ(b->v, 16);
		OO_CHECK_EQ(Tracked::live, 2);

		ExpT c(oo::unexpect, 5, 'x');
		OO_CHECK(!c.has_value());
		OO_CHECK_EQ(c.error(), std::string("xxxxx"));
		OO_CHECK_EQ(Tracked::live, 2);

		oo::Expected<int, std::vector<int>> d(oo::unexpect, {1, 2, 3});
		OO_CHECK_EQ(d.error().size(), 3u);

		oo::Unexpected<std::vector<int>> u(std::in_place, {4, 5});
		OO_CHECK_EQ(u.error().size(), 2u);
		oo::Unexpected<std::string> u2(std::in_place, 3, 'z');
		OO_CHECK_EQ(u2.error(), std::string("zzz"));
	}
	OO_CHECK_EQ(Tracked::live, 0);
}

OO_TEST(copyAndMoveConstruction)
{
	{
		ExpT a(std::in_place, 7);
		ExpT b = a;
		OO_CHECK(b.has_value());
		OO_CHECK_EQ(b->v, 7);
		OO_CHECK_EQ(Tracked::live, 2);

		ExpT c = std::move(a);
		OO_CHECK_EQ(c->v, 7);
		OO_CHECK(a->movedFrom);
		OO_CHECK(a.has_value());   // a moved-from Expected still holds a (moved-from) value
		OO_CHECK_EQ(Tracked::live, 3);

		ExpT e(oo::unexpect, "oops");
		ExpT f = e;
		ExpT g = std::move(e);
		OO_CHECK(!f.has_value() && !g.has_value());
		OO_CHECK_EQ(f.error(), std::string("oops"));
		OO_CHECK_EQ(g.error(), std::string("oops"));
		OO_CHECK_EQ(Tracked::live, 3);
	}
	OO_CHECK_EQ(Tracked::live, 0);
}

OO_TEST(convertingConstructionFromOtherExpected)
{
	oo::Expected<int, const char*> src = 9;
	oo::Expected<long, std::string> dst = src;
	OO_CHECK(dst.has_value());
	OO_CHECK_EQ(*dst, 9L);

	oo::Expected<int, const char*> srcErr = oo::Unexpected("e");
	oo::Expected<long, std::string> dstErr = std::move(srcErr);
	OO_CHECK(!dstErr.has_value());
	OO_CHECK_EQ(dstErr.error(), std::string("e"));

	oo::Expected<void, const char*> vsrc = oo::Unexpected("v");
	oo::Expected<void, std::string> vdst = vsrc;
	OO_CHECK_EQ(vdst.error(), std::string("v"));

	// Expected<bool, E> from an Expected is the special case the standard carves out: it
	// converts element-wise, never via Expected's own operator bool.
	oo::Expected<int, Err> fromInt = 0;
	oo::Expected<bool, Err> b = fromInt;
	OO_CHECK(b.has_value());
	OO_CHECK(*b == false);
}

OO_TEST(moveOnlyPayload)
{
	ExpU a(std::make_unique<int>(5));
	OO_CHECK(a.has_value());
	OO_CHECK_EQ(**a, 5);
	ExpU b = std::move(a);
	OO_CHECK_EQ(**b, 5);
	OO_CHECK(*a == nullptr);
	std::unique_ptr<int> taken = std::move(b).value();
	OO_CHECK_EQ(*taken, 5);

	oo::Expected<int, std::unique_ptr<int>> e(oo::unexpect, std::make_unique<int>(8));
	std::unique_ptr<int> err = std::move(e).error();
	OO_CHECK_EQ(*err, 8);
}

// --- assignment -------------------------------------------------------------------------------

OO_TEST(assignmentAllTransitions)
{
	{
		ExpT a(std::in_place, 1);
		ExpT b(std::in_place, 2);
		ExpT e1(oo::unexpect, "one");
		ExpT e2(oo::unexpect, "two");
		OO_CHECK_EQ(Tracked::live, 2);

		a = b;                   // value <- value
		OO_CHECK_EQ(a->v, 2);
		OO_CHECK_EQ(Tracked::live, 2);

		a = e1;                  // value <- error: the Tracked is destroyed
		OO_CHECK(!a.has_value());
		OO_CHECK_EQ(a.error(), std::string("one"));
		OO_CHECK_EQ(Tracked::live, 1);

		a = e2;                  // error <- error
		OO_CHECK_EQ(a.error(), std::string("two"));

		a = b;                   // error <- value: a Tracked is constructed
		OO_CHECK(a.has_value());
		OO_CHECK_EQ(a->v, 2);
		OO_CHECK_EQ(Tracked::live, 2);

		a = std::move(e1);       // move: value <- error
		OO_CHECK(!a.has_value());
		OO_CHECK_EQ(Tracked::live, 1);
		a = std::move(b);        // move: error <- value
		OO_CHECK(a.has_value());
		OO_CHECK_EQ(Tracked::live, 2);

		a = Tracked(11);         // from a value
		OO_CHECK_EQ(a->v, 11);
		a = oo::Unexpected(std::string("u"));   // from an Unexpected
		OO_CHECK_EQ(a.error(), std::string("u"));
		OO_CHECK_EQ(Tracked::live, 1);
		a = Tracked(12);         // value into an error-holding Expected
		OO_CHECK_EQ(a->v, 12);
		const oo::Unexpected<std::string> lu("lvalue");
		a = lu;
		OO_CHECK_EQ(a.error(), std::string("lvalue"));

		const ExpT& self = a;
		a = self;                // self-assignment is harmless
		OO_CHECK_EQ(a.error(), std::string("lvalue"));
	}
	OO_CHECK_EQ(Tracked::live, 0);
}

OO_TEST(emplace)
{
	{
		ExpT a(oo::unexpect, "err");
		Tracked& t = a.emplace(4, 2);
		OO_CHECK(a.has_value());
		OO_CHECK_EQ(t.v, 402);
		OO_CHECK_EQ(&t, &*a);
		a.emplace({1, 1}, 1);
		OO_CHECK_EQ(a->v, 3);
		OO_CHECK_EQ(Tracked::live, 1);

		ExpV v(oo::unexpect, Err::kIO);
		v.emplace();
		OO_CHECK(v.has_value());
	}
	OO_CHECK_EQ(Tracked::live, 0);
}

// --- swap -------------------------------------------------------------------------------------

OO_TEST(swapAllCases)
{
	{
		ExpT a(std::in_place, 1), b(std::in_place, 2);
		a.swap(b);
		OO_CHECK_EQ(a->v, 2);
		OO_CHECK_EQ(b->v, 1);

		ExpT e1(oo::unexpect, "x"), e2(oo::unexpect, "y");
		swap(e1, e2);
		OO_CHECK_EQ(e1.error(), std::string("y"));
		OO_CHECK_EQ(e2.error(), std::string("x"));

		a.swap(e1);              // value <-> error
		OO_CHECK(!a.has_value());
		OO_CHECK_EQ(a.error(), std::string("y"));
		OO_CHECK(e1.has_value());
		OO_CHECK_EQ(e1->v, 2);

		a.swap(e1);              // error <-> value
		OO_CHECK(a.has_value());
		OO_CHECK_EQ(a->v, 2);
		OO_CHECK_EQ(e1.error(), std::string("y"));
		OO_CHECK_EQ(Tracked::live, 2);

		ExpV v1, v2(oo::unexpect, Err::kIO);
		v1.swap(v2);
		OO_CHECK(!v1.has_value() && v2.has_value());
		OO_CHECK(v1.error() == Err::kIO);
		swap(v1, v2);
		OO_CHECK(v1.has_value() && !v2.has_value());

		oo::Unexpected<int> u1(1), u2(2);
		swap(u1, u2);
		OO_CHECK_EQ(u1.error(), 2);
		OO_CHECK_EQ(u2.error(), 1);
	}
	OO_CHECK_EQ(Tracked::live, 0);
}

// --- observers --------------------------------------------------------------------------------

OO_TEST(valueThrowsBadExpectedAccess)
{
	ExpI e = oo::Unexpected(Err::kIO);
	bool caught = false;
	try
	{
		(void)e.value();
	}
	catch (const oo::BadExpectedAccess<Err>& ex)
	{
		caught = true;
		OO_CHECK(ex.error() == Err::kIO);
		OO_CHECK(std::string(ex.what()).size() > 0);
	}
	OO_CHECK(caught);

	// The base class catches every error type, as bad_expected_access<void> does.
	caught = false;
	try
	{
		oo::Expected<int, std::string> s(oo::unexpect, "moved");
		(void)std::move(s).value();
	}
	catch (const oo::BadExpectedAccess<void>&)
	{
		caught = true;
	}
	OO_CHECK(caught);

	caught = false;
	try
	{
		checkNonZero(0).value();
	}
	catch (const oo::BadExpectedAccess<Err>& ex)
	{
		caught = ex.error() == Err::kIO;
	}
	OO_CHECK(caught);

	checkNonZero(1).value();    // no throw
}

OO_TEST(valueOrAndErrorOr)
{
	ExpI v = 3;
	ExpI e = oo::Unexpected(Err::kParse);
	OO_CHECK_EQ(v.value_or(9), 3);
	OO_CHECK_EQ(e.value_or(9), 9);
	OO_CHECK(v.error_or(Err::kNone) == Err::kNone);
	OO_CHECK(e.error_or(Err::kNone) == Err::kParse);

	oo::Expected<std::string, int> s(oo::unexpect, 1);
	OO_CHECK_EQ(std::move(s).value_or("fallback"), std::string("fallback"));
	oo::Expected<std::string, int> s2("have");
	OO_CHECK_EQ(std::move(s2).value_or("fallback"), std::string("have"));

	ExpV vv;
	OO_CHECK(vv.error_or(Err::kNone) == Err::kNone);
}

OO_TEST(refQualifiedAccessors)
{
	ExpT a(std::in_place, 5);
	const ExpT& ca = a;
	static_assert(std::is_same_v<decltype(*a), Tracked&>);
	static_assert(std::is_same_v<decltype(*ca), const Tracked&>);
	static_assert(std::is_same_v<decltype(*std::move(a)), Tracked&&>);
	static_assert(std::is_same_v<decltype(*std::move(ca)), const Tracked&&>);
	static_assert(std::is_same_v<decltype(a.value()), Tracked&>);
	static_assert(std::is_same_v<decltype(std::move(a).value()), Tracked&&>);
	static_assert(std::is_same_v<decltype(ca.error()), const std::string&>);
	static_assert(std::is_same_v<decltype(std::move(a).error()), std::string&&>);
	OO_CHECK_EQ(ca->v, 5);
	a->v = 6;
	OO_CHECK_EQ(ca.value().v, 6);
	Tracked moved = *std::move(a);
	OO_CHECK_EQ(moved.v, 6);
	OO_CHECK(a->movedFrom);
}

// --- monadic operations -----------------------------------------------------------------------

OO_TEST(andThen)
{
	auto half = [](int x) -> ExpI { if (x % 2)  return oo::Unexpected(Err::kParse); return x / 2; };
	OO_CHECK_EQ(*parsePositive(8).and_then(half), 4);
	OO_CHECK(parsePositive(7).and_then(half).error() == Err::kParse);
	OO_CHECK(parsePositive(-1).and_then(half).error() == Err::kParse);

	int calls = 0;
	auto count = [&calls](int) -> ExpI { ++calls; return 0; };
	ExpI err = oo::Unexpected(Err::kIO);
	OO_CHECK(err.and_then(count).error() == Err::kIO);
	OO_CHECK_EQ(calls, 0);    // short-circuits

	// Into void and out of void.
	ExpV r = parsePositive(0).and_then(checkNonZero);
	OO_CHECK(r.error() == Err::kIO);
	ExpI fromVoid = checkNonZero(1).and_then([]() -> ExpI { return 17; });
	OO_CHECK_EQ(*fromVoid, 17);

	// Value category is forwarded: an rvalue Expected hands the callable an rvalue.
	ExpU u(std::make_unique<int>(3));
	auto next = std::move(u).and_then([](std::unique_ptr<int>&& p) -> oo::Expected<int, Err> { return *p + 1; });
	OO_CHECK_EQ(*next, 4);
}

OO_TEST(orElse)
{
	auto recover = [](Err e) -> ExpI { return e == Err::kIO ? ExpI(0) : ExpI(oo::unexpect, e); };
	ExpI io = oo::Unexpected(Err::kIO);
	ExpI parse = oo::Unexpected(Err::kParse);
	OO_CHECK_EQ(*io.or_else(recover), 0);
	OO_CHECK(parse.or_else(recover).error() == Err::kParse);
	OO_CHECK_EQ(*ExpI(5).or_else(recover), 5);

	// or_else may change the error type.
	oo::Expected<int, std::string> described = parse.or_else(
		[](Err) -> oo::Expected<int, std::string> { return oo::Unexpected(std::string("parse")); });
	OO_CHECK_EQ(described.error(), std::string("parse"));

	ExpV v = checkNonZero(0).or_else([](Err) -> ExpV { return {}; });
	OO_CHECK(v.has_value());
}

OO_TEST(transform)
{
	auto r = parsePositive(4).transform([](int x) { return std::to_string(x * 2); });
	static_assert(std::is_same_v<decltype(r), oo::Expected<std::string, Err>>);
	OO_CHECK_EQ(*r, std::string("8"));
	OO_CHECK(parsePositive(-4).transform([](int x) { return x; }).error() == Err::kParse);

	// To void, and from void.
	int seen = 0;
	auto toVoid = parsePositive(6).transform([&seen](int x) { seen = x; });
	static_assert(std::is_same_v<decltype(toVoid), ExpV>);
	OO_CHECK(toVoid.has_value());
	OO_CHECK_EQ(seen, 6);
	auto fromVoid = checkNonZero(1).transform([] { return 2.5; });
	OO_CHECK(*fromVoid == 2.5);

	// The result is built directly from the call (no move of the value type needed).
	struct Immovable
	{
		int v;
		explicit Immovable(int x) : v(x) {}
		Immovable(Immovable&&) = delete;
	};
	auto imm = parsePositive(3).transform([](int x) { return Immovable(x); });
	OO_CHECK_EQ(imm->v, 3);
}

OO_TEST(transformError)
{
	auto describe = [](Err e) { return e == Err::kParse ? std::string("parse") : std::string("io"); };
	auto r = parsePositive(-2).transform_error(describe);
	static_assert(std::is_same_v<decltype(r), oo::Expected<int, std::string>>);
	OO_CHECK_EQ(r.error(), std::string("parse"));
	OO_CHECK_EQ(*parsePositive(2).transform_error(describe), 2);

	auto rv = checkNonZero(0).transform_error(describe);
	static_assert(std::is_same_v<decltype(rv), oo::Expected<void, std::string>>);
	OO_CHECK_EQ(rv.error(), std::string("io"));
	OO_CHECK(checkNonZero(1).transform_error(describe).has_value());
}

// --- equality ---------------------------------------------------------------------------------

OO_TEST(equality)
{
	ExpI a = 1, b = 1, c = 2;
	ExpI e1 = oo::Unexpected(Err::kIO), e2 = oo::Unexpected(Err::kIO), e3 = oo::Unexpected(Err::kParse);
	OO_CHECK(a == b);
	OO_CHECK(a != c);
	OO_CHECK(a != e1);
	OO_CHECK(e1 == e2);
	OO_CHECK(e1 != e3);
	OO_CHECK(a == 1);
	OO_CHECK(1 == a);              // C++20 reversed candidate, as with std::expected
	OO_CHECK(a != 2);
	OO_CHECK(e1 != 1);
	OO_CHECK(e1 == oo::Unexpected(Err::kIO));
	OO_CHECK(a != oo::Unexpected(Err::kIO));

	// Heterogeneous comparison.
	oo::Expected<long, Err> la = 1L;
	OO_CHECK(a == la);

	ExpV v1, v2, ve = oo::Unexpected(Err::kIO);
	OO_CHECK(v1 == v2);
	OO_CHECK(v1 != ve);
	OO_CHECK(ve == oo::Unexpected(Err::kIO));
	OO_CHECK(oo::Unexpected(1) == oo::Unexpected(1L));
	OO_CHECK(oo::Unexpected(1) != oo::Unexpected(2));
}

// --- the shape oofnd APIs use -----------------------------------------------------------------

struct ParseError
{
	std::string where;
	int line;
};

oo::Expected<std::vector<int>, ParseError> parseList(const std::string& s, const std::string& whereFrom)
{
	std::vector<int> out;
	int line = 1;
	for (char ch : s)
	{
		if (ch == '\n')  { ++line; continue; }
		if (ch < '0' || ch > '9')  return oo::Unexpected(ParseError{whereFrom, line});
		out.push_back(ch - '0');
	}
	return out;
}

OO_TEST(errorPathShape)
{
	auto ok = parseList("12\n3", "a.plist");
	OO_CHECK(ok.has_value());
	OO_CHECK_EQ(ok->size(), 3u);

	auto bad = parseList("1\n2\nx", "b.plist");
	OO_CHECK(!bad.has_value());
	OO_CHECK_EQ(bad.error().where, std::string("b.plist"));
	OO_CHECK_EQ(bad.error().line, 3);

	auto total = ok.transform([](const std::vector<int>& v) { int t = 0; for (int i : v)  t += i; return t; });
	OO_CHECK_EQ(*total, 6);
}

} // namespace

OO_TEST_MAIN()
