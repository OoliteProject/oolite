/*	test_OOHPVector.cpp
	Unit tests for the double-precision vectors (src/Core/OOHPVector.h).

	The cases pin the arithmetic (add, subtract, scale, dot, cross, distance,
	normal and its fallbacks), the conversions to and from the float Vector,
	and the "(x, y, z)" description. Positions far from the origin are where
	HPVector matters, so one case checks a difference that a float would lose.
	Run: tests/run.sh unit
*/

#include <cmath>

#include "OOMaths.h"
#include "oo_test.hpp"

// The test links the whole game but main, which defines the debug flags.
#ifndef NDEBUG
uint32_t gDebugFlags = 0;
#endif

namespace {

bool Near(double a, double b, double tolerance = 1e-12) { return std::fabs(a - b) <= tolerance; }

bool NearHP(HPVector a, HPVector b, double tolerance = 1e-12) {
	return Near(a.x, b.x, tolerance) && Near(a.y, b.y, tolerance) && Near(a.z, b.z, tolerance);
}

}  // namespace

OO_TEST(arithmetic) {
	const HPVector a = make_HPvector(1, 2, 3);
	const HPVector b = make_HPvector(-4, 5, 0.5);
	OO_CHECK(NearHP(HPvector_add(a, b), make_HPvector(-3, 7, 3.5)));
	OO_CHECK(NearHP(HPvector_subtract(a, b), make_HPvector(5, -3, 2.5)));
	OO_CHECK(NearHP(HPvector_multiply_scalar(a, 2), make_HPvector(2, 4, 6)));
	OO_CHECK(NearHP(HPvector_flip(a), make_HPvector(-1, -2, -3)));
	OO_CHECK(Near(HPdot_product(a, b), -4 + 10 + 1.5));
	OO_CHECK(Near(HPmagnitude2(a), 14));
	OO_CHECK(Near(HPdistance(a, a), 0));
	OO_CHECK(Near(HPdistance2(a, b), 25 + 9 + 6.25));
	OO_CHECK(HPvector_equal(a, make_HPvector(1, 2, 3)));
	OO_CHECK(!HPvector_equal(a, b));
}

OO_TEST(theTrueCrossProductIsPerpendicular) {
	const HPVector a = make_HPvector(1, 2, 3);
	const HPVector b = make_HPvector(-4, 5, 0.5);
	const HPVector c = HPtrue_cross_product(a, b);
	OO_CHECK(Near(HPdot_product(c, a), 0, 1e-9));
	OO_CHECK(Near(HPdot_product(c, b), 0, 1e-9));
	OO_CHECK(NearHP(HPtrue_cross_product(make_HPvector(1, 0, 0), make_HPvector(0, 1, 0)), make_HPvector(0, 0, 1)));
}

OO_TEST(normalAndItsFallbacks) {
	OO_CHECK(Near(HPmagnitude(HPvector_normal(make_HPvector(3, 4, 12))), 1));
	OO_CHECK(NearHP(HPvector_normal(make_HPvector(0, 0, -7)), make_HPvector(0, 0, -1)));
	OO_CHECK(NearHP(HPvector_normal_or_xbasis(kZeroHPVector), make_HPvector(1, 0, 0)));
	OO_CHECK(NearHP(HPvector_normal_or_ybasis(kZeroHPVector), make_HPvector(0, 1, 0)));
	OO_CHECK(NearHP(HPvector_normal_or_zbasis(kZeroHPVector), make_HPvector(0, 0, 1)));
}

OO_TEST(farFromTheOriginTheDifferenceSurvives) {
	const HPVector station = make_HPvector(123456789.0, -98765432.0, 5.0e8);
	const HPVector ship = HPvector_add(station, make_HPvector(0.25, -0.5, 0.125));
	OO_CHECK(NearHP(HPvector_subtract(ship, station), make_HPvector(0.25, -0.5, 0.125), 1e-6));
}

OO_TEST(conversionsToAndFromVector) {
	const Vector v = make_vector(1.5f, -2.25f, 3.0f);
	OO_CHECK(NearHP(vectorToHPVector(v), make_HPvector(1.5, -2.25, 3.0)));
	const Vector back = HPVectorToVector(make_HPvector(1.5, -2.25, 3.0));
	OO_CHECK(back.x == 1.5f && back.y == -2.25f && back.z == 3.0f);
}

OO_TEST(theDescriptionIsTheComponents) {
	OO_CHECK_EQ(cxx_HPVectorDescription(make_HPvector(1, -2.5, 0)), std::string("(1, -2.5, 0)"));
	const std::vector<double> parts = cxx_ArrayFromHPVector(make_HPvector(1, -2.5, 0));
	OO_CHECK(parts.size() == 3 && parts[0] == 1 && parts[1] == -2.5 && parts[2] == 0);
}

OO_TEST_MAIN()
