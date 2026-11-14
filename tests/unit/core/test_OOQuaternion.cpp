/*	test_OOQuaternion.cpp
	Unit tests for the quaternion maths (src/Core/OOQuaternion.h).

	The cases pin properties that hold whatever the rotation convention: the
	identity is neutral, normalising gives unit length, a rotation keeps
	lengths and its conjugate undoes it, the matrix of a rotation turns
	vectors as the quaternion does, quaternion_rotation_between takes one
	direction onto the other, and the description is "(w + xi + yj + zk)".
	Run: tests/run.sh unit
*/

#include <cmath>
#include <numbers>

#include "OOMaths.h"
#include "oo_test.hpp"

// The test links the whole game but main, which defines the debug flags.
#ifndef NDEBUG
uint32_t gDebugFlags = 0;
#endif

namespace {

bool Near(float a, float b, float tolerance = 1e-5f) { return std::fabs(a - b) <= tolerance; }

bool NearVector(Vector a, Vector b, float tolerance = 1e-5f) {
	return Near(a.x, b.x, tolerance) && Near(a.y, b.y, tolerance) && Near(a.z, b.z, tolerance);
}

bool NearQuaternion(Quaternion a, Quaternion b, float tolerance = 1e-5f) {
	return Near(a.w, b.w, tolerance) && Near(a.x, b.x, tolerance) && Near(a.y, b.y, tolerance) &&
		   Near(a.z, b.z, tolerance);
}

Quaternion Turn(Vector axis, float angle) {
	Quaternion q = kIdentityQuaternion;
	quaternion_set_rotate_about_axis(&q, vector_normal(axis), angle);
	return q;
}

}  // namespace

OO_TEST(identityIsNeutral) {
	const Quaternion q = make_quaternion(0.5f, 0.5f, -0.5f, 0.5f);
	OO_CHECK(NearQuaternion(quaternion_multiply(kIdentityQuaternion, q), q));
	OO_CHECK(NearQuaternion(quaternion_multiply(q, kIdentityQuaternion), q));
	OO_CHECK(NearVector(quaternion_rotate_vector(kIdentityQuaternion, make_vector(1, 2, 3)), make_vector(1, 2, 3)));
}

OO_TEST(normalisingGivesUnitLength) {
	Quaternion q = make_quaternion(1, 2, 3, 4);
	quaternion_normalize(&q);
	OO_CHECK(Near(quaternion_dot_product(q, q), 1.0f));
}

OO_TEST(aRotationKeepsLengthsAndItsConjugateUndoesIt) {
	const Vector v = make_vector(1.0f, -2.0f, 0.5f);
	const Quaternion turns[] = {Turn(make_vector(0, 0, 1), static_cast<float>(std::numbers::pi / 2.0)),
								Turn(make_vector(1, 1, 1), 0.9f), Turn(make_vector(-1, 0, 2), 2.5f)};
	for (const Quaternion& q : turns) {
		const Vector turned = quaternion_rotate_vector(q, v);
		OO_CHECK(Near(magnitude(turned), magnitude(v)));
		OO_CHECK(NearVector(quaternion_rotate_vector(quaternion_conjugate(q), turned), v));
		OO_CHECK(NearQuaternion(quaternion_multiply(q, quaternion_conjugate(q)), kIdentityQuaternion));
	}
}

OO_TEST(theRotationMatrixTurnsVectorsAsTheQuaternionDoes) {
	const Quaternion q = Turn(make_vector(1, 2, 3), 1.1f);
	const OOMatrix m = OOMatrixForQuaternionRotation(q);
	const Vector v = make_vector(0.3f, 0.6f, -0.9f);
	const Vector byQuaternion = quaternion_rotate_vector(q, v);
	const Vector byMatrix = OOVectorMultiplyMatrix(v, m);
	const Vector byMatrixTransposed = OOVectorMultiplyMatrix(v, OOMatrixTranspose(m));
	// The matrix is the quaternion's rotation in one of the two storage orders.
	OO_CHECK(NearVector(byMatrix, byQuaternion, 1e-4f) || NearVector(byMatrixTransposed, byQuaternion, 1e-4f));
	OO_CHECK(Near(magnitude(byMatrix), magnitude(v), 1e-4f));
}

OO_TEST(rotationBetweenTakesOneDirectionOntoTheOther) {
	const Vector from = vector_normal(make_vector(1, 0, 0));
	const Vector to = vector_normal(make_vector(0, 1, 1));
	const Quaternion q = quaternion_rotation_between(from, to);
	const bool forward = NearVector(quaternion_rotate_vector(q, from), to, 1e-4f);
	const bool backward = NearVector(quaternion_rotate_vector(quaternion_conjugate(q), from), to, 1e-4f);
	OO_CHECK(forward || backward);
}

OO_TEST(theDescriptionSpellsTheComponents) {
	OO_CHECK_EQ(QuaternionDescription(make_quaternion(1, 0, 0, 0)), std::string("(1 + 0i + 0j + 0k)"));
	OO_CHECK_EQ(QuaternionDescription(make_quaternion(0.5f, -0.5f, 0.25f, -2)), std::string("(0.5 - 0.5i + 0.25j - 2k)"));
}

OO_TEST_MAIN()
