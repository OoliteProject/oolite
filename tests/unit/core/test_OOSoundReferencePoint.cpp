/*	test_OOSoundReferencePoint.mm
        Unit tests for OOSoundReferencePoint
   (src/Core/OOBasicSoundReferencePoint.h).

        The class is the no-op reference point of the OpenAL sound code
   (OOSound.h: positional sound is not implemented). A point can be made, takes
   a position, a velocity and an orientation without effect, and is freed by
   its last release. Run: tests/run.sh unit
   tests/run.sh unit
*/

#include "OOBasicSoundReferencePoint.h"
#include "oo_test.hpp"

OO_TEST(settersAreNoOps) {
  oo::Ref<OOSoundReferencePoint> point = oo::makeRef<OOSoundReferencePoint>();
  OO_CHECK(point != nullptr);
  point->setPosition(make_vector(1.0f, 2.0f, 3.0f));
  point->setVelocity(make_vector(-1.0f, 0.0f, 0.5f));
  point->setOrientation(make_vector(0.0f, 0.0f, 1.0f));
  OO_CHECK(point->retainCount() == 1);
}

OO_TEST(lastReleaseFrees) {
  OOSoundReferencePoint* point =
      new OOSoundReferencePoint;  // +1, as +alloc was
  oo::WeakRef<OOSoundReferencePoint> weak = point;
  OO_CHECK(weak.get() == point);
  point->release();
  OO_CHECK(weak.get() == nullptr);
}

OO_TEST_MAIN()
