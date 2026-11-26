/*	test_OOMatrix.cpp
	Unit tests for the 4x4 matrix maths (src/Core/OOMatrix.h).

	The cases pin properties that hold whatever the rotation convention: the
	identity is neutral, a rotation and its opposite cancel and keep lengths,
	the inverse undoes the matrix, a translation moves a point, and the
	description is the "{{#, #, #, #}, ...}" text the header documents. The
	build pins -ffp-contract=off, so these also catch a fused multiply-add
	sneaking into a platform's build. Run: tests/run.sh unit
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

bool NearMatrix(OOMatrix a, OOMatrix b, float tolerance = 1e-5f) {
	for (int i = 0; i < 4; i++) {
		for (int j = 0; j < 4; j++) {
			if (!Near(a.m[i][j], b.m[i][j], tolerance)) return false;
		}
	}
	return true;
}

const float kQuarterTurn = static_cast<float>(std::numbers::pi / 2.0);

}  // namespace

OO_TEST(identityIsNeutral) {
	OOMatrix m = OOMatrixConstruct(1, 2, 3, 0, 4, 5, 6, 0, 7, 8, 10, 0, 1, 2, 3, 1);
	OO_CHECK(OOMatrixIsIdentity(kIdentityMatrix));
	OO_CHECK(!OOMatrixIsIdentity(m));
	OO_CHECK(OOMatrixEqual(OOMatrixMultiply(kIdentityMatrix, m), m));
	OO_CHECK(OOMatrixEqual(OOMatrixMultiply(m, kIdentityMatrix), m));
	OO_CHECK(OOMatrixEqual(OOMatrixTranspose(OOMatrixTranspose(m)), m));
}

OO_TEST(aRotationAndItsOppositeCancel) {
	const Vector v = make_vector(1.0f, 2.0f, 3.0f);
	// The general axis is (0, 1, 1): OOMatrixForRotation's third row starts t*x*y + s*y where a
	// rotation has t*x*z + s*y, here and upstream, so an axis with x != 0 and y != z gives a matrix
	// that is not a rotation. Whether to fix it is open (the migration repo's parity notes).
	const OOMatrix rotations[] = {OOMatrixForRotationX(kQuarterTurn), OOMatrixForRotationY(kQuarterTurn),
								  OOMatrixForRotationZ(kQuarterTurn),
								  OOMatrixForRotation(vector_normal(make_vector(0, 1, 1)), 0.7f)};
	const OOMatrix opposites[] = {OOMatrixForRotationX(-kQuarterTurn), OOMatrixForRotationY(-kQuarterTurn),
								  OOMatrixForRotationZ(-kQuarterTurn),
								  OOMatrixForRotation(vector_normal(make_vector(0, 1, 1)), -0.7f)};
	for (int i = 0; i < 4; i++) {
		const Vector turned = OOVectorMultiplyMatrix(v, rotations[i]);
		OO_CHECK(Near(magnitude(turned), magnitude(v)));
		OO_CHECK(NearVector(OOVectorMultiplyMatrix(turned, opposites[i]), v));
		OO_CHECK(NearMatrix(OOMatrixMultiply(rotations[i], opposites[i]), kIdentityMatrix));
	}
}

OO_TEST(aQuarterTurnAboutZKeepsZAndMovesXIntoTheXYPlane) {
	const Vector x = OOVectorMultiplyMatrix(make_vector(1, 0, 0), OOMatrixForRotationZ(kQuarterTurn));
	OO_CHECK(Near(x.x, 0.0f));
	OO_CHECK(Near(std::fabs(x.y), 1.0f));
	OO_CHECK(Near(x.z, 0.0f));
	const Vector z = OOVectorMultiplyMatrix(make_vector(0, 0, 1), OOMatrixForRotationZ(kQuarterTurn));
	OO_CHECK(NearVector(z, make_vector(0, 0, 1)));
}

OO_TEST(theInverseUndoesTheMatrix) {
	OOMatrix m = OOMatrixConstruct(2, 0, 0, 0, 0, 3, 0, 0, 0, 0, 4, 0, 5, 6, 7, 1);
	m = OOMatrixMultiply(OOMatrixForRotationY(0.3f), m);
	OO_CHECK(NearMatrix(OOMatrixMultiply(OOMatrixInverse(m), m), kIdentityMatrix, 1e-4f));
	OO_CHECK(NearMatrix(OOMatrixMultiply(m, OOMatrixInverse(m)), kIdentityMatrix, 1e-4f));
}

OO_TEST(aTranslationMovesAPoint) {
	const Vector moved = OOVectorMultiplyMatrix(make_vector(1, 2, 3), OOMatrixForTranslation(make_vector(10, 20, 30)));
	OO_CHECK(NearVector(moved, make_vector(11, 22, 33)));
	const Vector scaled = OOVectorMultiplyMatrix(make_vector(1, 2, 3), OOMatrixForScale(2, 3, 4));
	OO_CHECK(NearVector(scaled, make_vector(2, 6, 12)));
}

OO_TEST(theDescriptionListsTheRows) {
	OO_CHECK_EQ(OOMatrixDescription(kIdentityMatrix),
				std::string("{{1, 0, 0, 0}, {0, 1, 0, 0}, {0, 0, 1, 0}, {0, 0, 0, 1}}"));
	OO_CHECK_EQ(OOMatrixDescription(OOMatrixForTranslationComponents(1.5f, -2, 0)),
				std::string("{{1, 0, 0, 0}, {0, 1, 0, 0}, {0, 0, 1, 0}, {1.5, -2, 0, 1}}"));
}

OO_TEST_MAIN()
