/*	test_plist_game_tuples.cpp
	oo::plist_get::tupleFrom / tuplePList / fuzzyProbabilityFrom (oofnd/PListGet.hpp, bead oo-9ftb):
	OOCollectionExtractors' OOVectorFromObject / OOHPVectorFromObject / OOQuaternionFromObject,
	OOPropertyListFrom{Vector,HPVector,Quaternion} and OOFuzzyBooleanFromObject's probability, over
	a PList.

	Expected values. The component conversions are realFrom<F>, the rows of test_plist_get.cpp's
	kCaptured (GNUstep base 1.31.1, captured). What this file pins on top is the routing the
	Foundation functions did around those conversions, read from OOCollectionExtractors.mm: an
	NSArray of exactly N (-oo_floatAtIndex:/-oo_doubleAtIndex:, fallback 0), an NSDictionary with at
	least one of the keys (missing keys 0, not the default's component), an NSString or the native
	vector handed to the game, anything else the default; +numberWithFloat: / +numberWithDouble: for
	the writers; FuzzyBooleanProbabilityFromString for a string whose -floatValue is 0. The game's
	own OO*FromObject forward to these functions (the goldens run every former caller through them).
	meson test --suite oofnd-plist
*/

// Included as Objective-C++ game code includes it, after OOCocoa.h's true/false macros.
#define true						1
#define false						0
#include "oofnd/PListGet.hpp"
#undef true
#undef false

#include "oo_test.hpp"

#include <array>
#include <cmath>
#include <string>
#include <string_view>

namespace {

using oo::PList;
using oo::plist_get::TupleSource;

constexpr std::array<std::string_view, 3> kXYZ{"x", "y", "z"};
constexpr std::array<std::string_view, 4> kWXYZ{"w", "x", "y", "z"};

template <class F, std::size_t N>
TupleSource Read(const PList* v, const std::array<std::string_view, N>& keys, std::array<F, N>& out)
{
	return oo::plist_get::tupleFrom<F, N>(v, keys, out);
}

}	// namespace

// No value, and values of other kinds, leave the default untouched.
OO_TEST(noneKeepsDefault)
{
	std::array<float, 3> out{7.5f, 7.5f, 7.5f};
	OO_CHECK(Read(nullptr, kXYZ, out) == TupleSource::none);
	const PList number(3.0);
	OO_CHECK(Read(&number, kXYZ, out) == TupleSource::none);
	const PList null;
	OO_CHECK(Read(&null, kXYZ, out) == TupleSource::none);
	const PList data(PList::Data{});
	OO_CHECK(Read(&data, kXYZ, out) == TupleSource::none);
	OO_CHECK(out[0] == 7.5f && out[1] == 7.5f && out[2] == 7.5f);
}

// A string is the game's to scan; an object node may be its native vector.
OO_TEST(stringAndObjectAreReported)
{
	std::array<double, 3> out{};
	const PList string("1 2 3");
	OO_CHECK(Read(&string, kXYZ, out) == TupleSource::string);
	const PList object{PList::Object{}};
	OO_CHECK(Read(&object, kXYZ, out) == TupleSource::object);
}

// An array of exactly N: element i converts as -oo_floatAtIndex:i (fallback 0).
OO_TEST(arrayOfExactlyN)
{
	std::array<float, 3> out{7.5f, 7.5f, 7.5f};
	const PList a(PList::Array{PList(1.5), PList("2.25"), PList("junk")});
	OO_CHECK(Read(&a, kXYZ, out) == TupleSource::components);
	OO_CHECK_EQ(out[0], 1.5f);
	OO_CHECK_EQ(out[1], 2.25f);
	OO_CHECK_EQ(out[2], 0.0f);   // not a number: the element's fallback, 0

	std::array<float, 3> keep{7.5f, 7.5f, 7.5f};
	const PList two(PList::Array{PList(1.0), PList(2.0)});
	OO_CHECK(Read(&two, kXYZ, keep) == TupleSource::none);
	const PList four(PList::Array{PList(1.0), PList(2.0), PList(3.0), PList(4.0)});
	OO_CHECK(Read(&four, kXYZ, keep) == TupleSource::none);
	OO_CHECK(keep[0] == 7.5f);

	// Four for a quaternion, w first.
	std::array<float, 4> q{};
	OO_CHECK(Read(&four, kWXYZ, q) == TupleSource::components);
	OO_CHECK(q[0] == 1.0f && q[1] == 2.0f && q[2] == 3.0f && q[3] == 4.0f);
}

// oo::ObjectFromPList dropped null elements before the Foundation function counted them.
OO_TEST(arrayNullsDropped)
{
	std::array<double, 3> out{};
	const PList a(PList::Array{PList(1.0), PList(), PList(2.0), PList(3.0)});
	OO_CHECK(Read(&a, kXYZ, out) == TupleSource::components);
	OO_CHECK(out[0] == 1.0 && out[1] == 2.0 && out[2] == 3.0);
}

// A dictionary with at least one key: every component read, missing ones 0 (not the default's).
OO_TEST(dictionaryComponents)
{
	std::array<double, 3> out{7.25, 7.25, 7.25};
	const PList d(PList::Dict{{"y", PList(PList::signedInteger(4))}, {"other", PList(9.0)}});
	OO_CHECK(Read(&d, kXYZ, out) == TupleSource::components);
	OO_CHECK(out[0] == 0.0 && out[1] == 4.0 && out[2] == 0.0);

	std::array<double, 3> keep{7.25, 7.25, 7.25};
	const PList none(PList::Dict{{"other", PList(9.0)}, {"x", PList()}});   // a null value is absent
	OO_CHECK(Read(&none, kXYZ, keep) == TupleSource::none);
	OO_CHECK(keep[0] == 7.25);

	std::array<float, 4> q{};
	const PList qd(PList::Dict{{"w", PList("0.5")}, {"z", PList(true)}});
	OO_CHECK(Read(&qd, kWXYZ, q) == TupleSource::components);
	OO_CHECK(q[0] == 0.5f && q[1] == 0.0f && q[2] == 0.0f && q[3] == 1.0f);
}

// The writers: +numberWithFloat: (single-precision reals) / +numberWithDouble:.
OO_TEST(writers)
{
	const PList v = oo::plist_get::tuplePList<float, 3>(kXYZ, {0.1f, -2.0f, 3.5f});
	OO_CHECK(v.find("x") != nullptr && v.find("x")->isSinglePrecision());
	OO_CHECK_EQ(static_cast<float>(v.find("x")->doubleValue()), 0.1f);
	OO_CHECK_EQ(v.find("y")->doubleValue(), -2.0);
	OO_CHECK_EQ(v.getIf<PList::Dict>()->size(), std::size_t(3));

	const PList hp = oo::plist_get::tuplePList<double, 3>(kXYZ, {0.1, 1e300, -0.0});
	OO_CHECK(!hp.find("x")->isSinglePrecision());
	OO_CHECK_EQ(hp.find("x")->doubleValue(), 0.1);
	OO_CHECK_EQ(hp.find("y")->doubleValue(), 1e300);

	const PList q = oo::plist_get::tuplePList<float, 4>(kWXYZ, {1.0f, 0.0f, 0.0f, 0.0f});
	OO_CHECK_EQ(q.find("w")->doubleValue(), 1.0);
	OO_CHECK_EQ(q.getIf<PList::Dict>()->size(), std::size_t(4));

	// Round trip through the reader.
	std::array<float, 3> out{};
	OO_CHECK(Read(&v, kXYZ, out) == TupleSource::components);
	OO_CHECK(out[0] == 0.1f && out[1] == -2.0f && out[2] == 3.5f);
}

// OOFuzzyBooleanFromObject's probability.
OO_TEST(fuzzyProbability)
{
	using oo::plist_get::fuzzyProbabilityFrom;
	OO_CHECK_EQ(fuzzyProbabilityFrom(nullptr, 0.25f), 0.25f);
	const PList half(0.5), yes("YES"), no("off"), zero(" 0"), minusZero("-0"), junk("maybe"), fraction("0.3"), tiny("1e-50");
	const PList t(true), n(PList::signedInteger(2)), a(PList::Array{});
	OO_CHECK_EQ(fuzzyProbabilityFrom(&half, 0.25f), 0.5f);
	OO_CHECK_EQ(fuzzyProbabilityFrom(&yes, 0.25f), 1.0f);
	OO_CHECK_EQ(fuzzyProbabilityFrom(&no, 0.25f), 0.0f);
	OO_CHECK_EQ(fuzzyProbabilityFrom(&zero, 0.25f), 0.0f);		// a zero string keeps its 0
	OO_CHECK_EQ(fuzzyProbabilityFrom(&minusZero, 0.25f), 0.25f);	// "-0" is not a zero string (quirk)
	OO_CHECK_EQ(fuzzyProbabilityFrom(&junk, 0.25f), 0.25f);
	OO_CHECK_EQ(fuzzyProbabilityFrom(&fraction, 0.25f), 0.3f);
	OO_CHECK_EQ(fuzzyProbabilityFrom(&tiny, 0.25f), 1.0f);		// -floatValue 0, -doubleValue not
	OO_CHECK_EQ(fuzzyProbabilityFrom(&t, 0.25f), 1.0f);
	OO_CHECK_EQ(fuzzyProbabilityFrom(&n, 0.25f), 2.0f);
	OO_CHECK_EQ(fuzzyProbabilityFrom(&a, 0.25f), 0.25f);
}

OO_TEST_MAIN()
