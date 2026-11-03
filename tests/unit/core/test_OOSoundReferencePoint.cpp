/*	test_OOSoundReferencePoint.mm
	Unit tests for OOSoundReferencePoint (src/Core/OOBasicSoundReferencePoint.h): bead oo-odlx,
	converted in the Phase 3 house style (proposed ADR-0056).

	The class is the no-op reference point of the OpenAL sound code (OOSound.h: positional sound
	is not implemented). The expectations were written against the Objective-C API and run on the
	unconverted class first: a point can be made, takes a position, a velocity and an orientation
	without effect, and is freed by its last release. The class has no Objective-C facade (no file
	outside it messages it), so there is no facade contract to pin.
	Run: bash tools/check-core-tests.sh
*/

#include "OOBasicSoundReferencePoint.h"

#include "oo_test.hpp"


OO_TEST(settersAreNoOps)
{
	oo::Ref<OOSoundReferencePoint> point = oo::makeRef<OOSoundReferencePoint>();
	OO_CHECK(point != nullptr);
	point->setPosition(make_vector(1.0f, 2.0f, 3.0f));
	point->setVelocity(make_vector(-1.0f, 0.0f, 0.5f));
	point->setOrientation(make_vector(0.0f, 0.0f, 1.0f));
	OO_CHECK(point->retainCount() == 1);
}


OO_TEST(lastReleaseFrees)
{
	OOSoundReferencePoint *point = new OOSoundReferencePoint;	// +1, as +alloc was
	oo::WeakRef<OOSoundReferencePoint> weak = point;
	OO_CHECK(weak.get() == point);
	point->release();
	OO_CHECK(weak.get() == nullptr);
}


OO_TEST_MAIN()
