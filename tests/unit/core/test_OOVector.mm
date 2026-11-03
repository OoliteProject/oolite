/*	test_OOVector.mm
	Unit tests for cxx::OONativeVector (src/Core/OOVector.h), the box that stores a Vector in an
	Objective-C collection, and its Objective-C facade (OOVector+ObjCBridge.h): bead oo-86ek
	(Phase 3, house style of proposed ADR-0056). The rest of OOVector.mm is plain C (ADR-0012) and
	stays verbatim; the free functions the box shares a file with are pinned here too.

	The expectations were written against the Objective-C API and run on the unconverted class
	first: the box hands back the vector it was made with, is an OONativeVector, and survives an
	Object node (as OOJSShip.mm and OOPListGameTypes.mm use it). The later tests pin the C++ class
	and the facade's contract: the same answers, nil stays nil, one facade per C++ object.
	Run: bash tools/check-core-tests.sh
*/

#import "OOMaths.h"
#import "OOObjCPList.h"

#include "oo_test.hpp"


namespace {

bool Same(Vector a, Vector b)
{
	return a.x == b.x && a.y == b.y && a.z == b.z;
}

}	// namespace


OO_TEST(boxHoldsItsVector)
{
	@autoreleasepool
	{
		Vector v = make_vector(1.5f, -2.0f, 3.25f);
		OONativeVector *box = [[[OONativeVector alloc] initWithVector:v] autorelease];
		OO_CHECK(box != nil);
		OO_CHECK([box isKindOfClass:[OONativeVector class]]);
		OO_CHECK(Same([box getVector], v));

		OONativeVector *zero = [[[OONativeVector alloc] initWithVector:kZeroVector] autorelease];
		OO_CHECK(Same([zero getVector], kZeroVector));
		OO_CHECK(zero != box);
	}
}


OO_TEST(boxSurvivesAnObjectNode)
{
	@autoreleasepool
	{
		Vector v = make_vector(4.0f, 5.0f, 6.0f);
		OONativeVector *box = [[[OONativeVector alloc] initWithVector:v] autorelease];
		oo::PList node = oo::PListObject(box);
		id object = oo::ObjectIn(node);
		OO_CHECK(object == box);
		OO_CHECK([object isKindOfClass:[OONativeVector class]]);
		OO_CHECK(Same([object getVector], v));
	}
}


OO_TEST(nilBoxAnswersZero)
{
	OONativeVector *none = nil;
	OO_CHECK(Same([none getVector], kZeroVector));
}


OO_TEST(freeFunctions)
{
	OO_CHECK(VectorDescription(make_vector(1.0f, 0.5f, -2.0f)) == "(1, 0.5, -2)");
	OO_CHECK(Same(kBasisXVector, make_vector(1, 0, 0)) && Same(kBasisYVector, make_vector(0, 1, 0)) && Same(kBasisZVector, make_vector(0, 0, 1)));
	OO_CHECK(Same(OORandomPositionInBoundingBox((BoundingBox){ { 2, 3, 4 }, { 2, 3, 4 } }), make_vector(2, 3, 4)));
	ranrot_srand(12345);	// unseeded, randf() is always 0 and OORandomUnitVector() never returns
	for (int i = 0; i < 100; i++)
	{
		OO_CHECK(fabs(magnitude(OORandomUnitVector()) - 1.0f) < 1e-5f);
		OO_CHECK(magnitude(OOVectorRandomSpatial(2.0f)) <= 2.0f + 1e-5f);
		OO_CHECK(magnitude(OOVectorRandomRadial(3.0f)) <= 3.0f + 1e-5f);
	}
}


OO_TEST(cxxBox)
{
	Vector v = make_vector(-1.0f, 0.25f, 8.0f);
	oo::Ref<cxx::OONativeVector> box = oo::makeRef<cxx::OONativeVector>(v);
	OO_CHECK(Same(box->getVector(), v));
}


OO_TEST(facadeNilStaysNil)
{
	OONativeVector *none = nil;
	OO_CHECK(oo::ToCxx(none) == nullptr);
	OO_CHECK(oo::ToObjC(static_cast<cxx::OONativeVector *>(nullptr)) == nil);
}


OO_TEST(facadeIdentity)
{
	@autoreleasepool
	{
		// A box made by alloc/init is its C++ box's facade, and crosses back to itself.
		Vector v = make_vector(7.0f, 8.0f, 9.0f);
		OONativeVector *box = [[[OONativeVector alloc] initWithVector:v] autorelease];
		cxx::OONativeVector *cxxBox = oo::ToCxx(box);
		OO_CHECK(cxxBox != nullptr && Same(cxxBox->getVector(), v));
		OO_CHECK(oo::ToObjC(cxxBox) == box);

		// A C++ box crosses to one facade, and back to itself.
		oo::Ref<cxx::OONativeVector> made = oo::makeRef<cxx::OONativeVector>(v);
		OONativeVector *facade = oo::ToObjC(made);
		OO_CHECK(facade != nil && facade == oo::ToObjC(made.get()));
		OO_CHECK(oo::ToCxx(facade) == made.get());
		OO_CHECK([facade isKindOfClass:[OONativeVector class]] && Same([facade getVector], v));
		OO_CHECK(facade != box);	// two boxes, two facades
	}
}


OO_TEST_MAIN()
