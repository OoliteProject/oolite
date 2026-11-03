/*	test_OOVector.mm
        Unit tests for OONativeVector (src/Core/OOVector.h), the box that stores
   a Vector in a property list. The box is a PList::Object node's foreign
   object itself, and the cases below ask the C++ box. The rest of OOVector.mm
   is plain C and stays verbatim; the free functions the box shares a file with
   are pinned here too.

        The tests pin that the box hands back the vector it was made with, is
   an OONativeVector, and survives an Object node (as OOJSShip.mm and
   OOPListGameTypes.mm use it). Run: tests/run.sh unit
*/

#include "OOMaths.h"
#include "OOObjCPList.h"
#include "oo_test.hpp"

namespace {

bool Same(Vector a, Vector b) { return a.x == b.x && a.y == b.y && a.z == b.z; }

}  // namespace

OO_TEST(boxHoldsItsVector) {
  {
    Vector v = make_vector(1.5f, -2.0f, 3.25f);
    oo::Ref<OONativeVector> box = oo::makeRef<OONativeVector>(v);
    OO_CHECK(box != nullptr);
    OO_CHECK(box->className() == "OONativeVector");
    OO_CHECK(Same(box->getVector(), v));

    oo::Ref<OONativeVector> zero = oo::makeRef<OONativeVector>(kZeroVector);
    OO_CHECK(Same(zero->getVector(), kZeroVector));
    OO_CHECK(zero != box);
  }
}

OO_TEST(boxSurvivesAnObjectNode) {
  {
    Vector v = make_vector(4.0f, 5.0f, 6.0f);
    oo::Ref<OONativeVector> box = oo::makeRef<OONativeVector>(v);
    oo::PList node = oo::PList(oo::PList::Object(box));
    const oo::PList::Object* object = node.getIf<oo::PList::Object>();
    OO_CHECK(object != nullptr && object->get() == box.get());
    OONativeVector* held = dynamic_cast<OONativeVector*>(object->get());
    OO_CHECK(held != nullptr);
    OO_CHECK(Same(held->getVector(), v));
  }
}

OO_TEST(freeFunctions) {
  OO_CHECK(VectorDescription(make_vector(1.0f, 0.5f, -2.0f)) == "(1, 0.5, -2)");
  OO_CHECK(Same(kBasisXVector, make_vector(1, 0, 0)) &&
           Same(kBasisYVector, make_vector(0, 1, 0)) &&
           Same(kBasisZVector, make_vector(0, 0, 1)));
  OO_CHECK(
      Same(OORandomPositionInBoundingBox((BoundingBox){{2, 3, 4}, {2, 3, 4}}),
           make_vector(2, 3, 4)));
  ranrot_srand(12345);  // unseeded, randf() is always 0 and
                        // OORandomUnitVector() never returns
  for (int i = 0; i < 100; i++) {
    OO_CHECK(fabs(magnitude(OORandomUnitVector()) - 1.0f) < 1e-5f);
    OO_CHECK(magnitude(OOVectorRandomSpatial(2.0f)) <= 2.0f + 1e-5f);
    OO_CHECK(magnitude(OOVectorRandomRadial(3.0f)) <= 3.0f + 1e-5f);
  }
}

OO_TEST(cxxBox) {
  Vector v = make_vector(-1.0f, 0.25f, 8.0f);
  oo::Ref<OONativeVector> box = oo::makeRef<OONativeVector>(v);
  OO_CHECK(Same(box->getVector(), v));
}

OO_TEST_MAIN()
