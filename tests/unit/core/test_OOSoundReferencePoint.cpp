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
  std::shared_ptr<OOSoundReferencePoint> point = oo::makeShared<OOSoundReferencePoint>();
  OO_CHECK(point != nullptr);
  point->setPosition(make_vector(1.0f, 2.0f, 3.0f));
  point->setVelocity(make_vector(-1.0f, 0.0f, 0.5f));
  point->setOrientation(make_vector(0.0f, 0.0f, 1.0f));
  OO_CHECK(point.use_count() == 1);
}

OO_TEST(lastReleaseFrees) {
  std::shared_ptr<OOSoundReferencePoint> point =
      oo::makeShared<OOSoundReferencePoint>();  // the one owner, as +alloc's +1 was
  std::weak_ptr<OOSoundReferencePoint> weak = point;
  OO_CHECK(weak.lock().get() == point.get());
  point.reset();  // the last release
  OO_CHECK(weak.lock().get() == nullptr);
}

OO_TEST_MAIN()
