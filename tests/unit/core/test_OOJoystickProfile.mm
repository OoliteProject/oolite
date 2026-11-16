/*	test_OOJoystickProfile.mm
	Unit tests for the joystick axis profiles (src/Core/OOJoystickProfile.h): bead oo-fn2f,
	converted in the Phase 3 house style (proposed ADR-0056, hierarchy amendments oo-cwz/oo-up4b).

	OOJoystickAxisProfile maps a raw axis position through a dead zone and a response curve:
	OOJoystickStandardAxisProfile's power curve, or OOJoystickSplineAxisProfile's spline through
	control points (made of private OOJoystickSplineSegment pieces). The expectations were written
	against the Objective-C API and run on the unconverted classes first: the defaults and clamps,
	the dead zone, both curves at pinned sample points, the spline's control-point editing rules,
	and what a copy keeps (a copy does NOT keep the dead zone; the spline copy keeps the points).
	The C++ test then pins the same answers through the C++ API. Bead oo-9ht.16 deleted the
	Objective-C facades: the cases that sent their selectors ask the C++ classes (alloc/init as
	makeRef, -copy as copy(), class checks as dynamic_cast/typeid) with every expectation kept, and
	the facades' contract case went with them (standing approval oo-9n5p9).
	Run: bash tools/check-core-tests.sh
*/

#import "OOJoystickManager.h"

#include "oo_test.hpp"

#include <cmath>
#include <typeinfo>
#include <vector>


namespace {

bool Near(double a, double b)
{
	return std::fabs(a - b) < 1e-9;
}


bool SamePoint(NSPoint p, double x, double y)
{
	return Near(p.x, x) && Near(p.y, y);
}


// Whether profile is exactly a T (bead oo-9ht.168: typeid of a plain pointer's object, not of a
// Ref's overloaded operator*, which clang counts as a side effect).
template <class T>
bool IsExactly(OOJoystickAxisProfile *profile)
{
	return profile != nullptr && typeid(*profile) == typeid(T);
}

}	// namespace


OO_TEST(axisProfileDeadzone)
{
	@autoreleasepool
	{
		oo::Ref<OOJoystickAxisProfile> profile = oo::makeRef<OOJoystickAxisProfile>();
		OO_CHECK(Near(profile->deadzone(), STICK_DEADZONE));
		OO_CHECK(Near(profile->rawValue(0.3), 0.3));	// identity curve
		OO_CHECK(profile->value(STICK_DEADZONE / 2) == 0.0);
		OO_CHECK(profile->value(-STICK_DEADZONE / 2) == 0.0);
		OO_CHECK(Near(profile->value(1.0), 1.0));
		OO_CHECK(Near(profile->value(-1.0), -1.0));
		OO_CHECK(Near(profile->value(0.5), (0.5 - STICK_DEADZONE) / (1.0 - STICK_DEADZONE)));
		OO_CHECK(Near(profile->value(-0.5), -(0.5 - STICK_DEADZONE) / (1.0 - STICK_DEADZONE)));

		profile->setDeadzone(1.0);
		OO_CHECK(Near(profile->deadzone(), STICK_MAX_DEADZONE));
		profile->setDeadzone(-1.0);
		OO_CHECK(profile->deadzone() == 0.0);
		profile->setDeadzone(STICK_DEADZONE * 1.5);
		OO_CHECK(Near(profile->deadzone(), STICK_DEADZONE * 1.5));

		oo::Ref<OOJoystickAxisProfile> copy = profile->copy();
		OO_CHECK(copy != profile && IsExactly<OOJoystickAxisProfile>(copy.get()));
		OO_CHECK(Near(copy->deadzone(), STICK_DEADZONE));	// the dead zone is not copied
	}
}


OO_TEST(standardProfile)
{
	@autoreleasepool
	{
		oo::Ref<OOJoystickStandardAxisProfile> profile = oo::makeRef<OOJoystickStandardAxisProfile>();
		OO_CHECK(dynamic_cast<OOJoystickAxisProfile *>(profile.get()) != nullptr);
		OO_CHECK(profile->power() == 1.0 && profile->parameter() == 1.0);
		OO_CHECK(Near(profile->deadzone(), STICK_DEADZONE));
		OO_CHECK(Near(profile->rawValue(0.4), 0.4));

		profile->setPower(0.5);
		OO_CHECK(profile->power() == 1.0);
		profile->setPower(25.0);
		OO_CHECK(profile->power() == STICKPROFILE_MAX_POWER);
		profile->setPower(3.0);
		OO_CHECK(profile->power() == 3.0);
		profile->setParameter(2.0);
		OO_CHECK(profile->parameter() == 1.0);
		profile->setParameter(-2.0);
		OO_CHECK(profile->parameter() == 0.0);
		profile->setParameter(0.5);
		OO_CHECK(profile->parameter() == 0.5);

		// parameter * x^power - (parameter - 1) * x, clamped to [0, 1], odd.
		OO_CHECK(Near(profile->rawValue(0.5), 0.5 * 0.125 + 0.5 * 0.5));
		OO_CHECK(Near(profile->rawValue(-0.5), -(0.5 * 0.125 + 0.5 * 0.5)));
		OO_CHECK(Near(profile->rawValue(1.0), 1.0));
		OO_CHECK(Near(profile->value(0.5), profile->rawValue((0.5 - STICK_DEADZONE) / (1.0 - STICK_DEADZONE))));	// value: reaches the override

		profile->setDeadzone(0.0);
		oo::Ref<OOJoystickStandardAxisProfile> copy(dynamic_cast<OOJoystickStandardAxisProfile *>(profile->copy().get()));
		OO_CHECK(copy != nullptr && IsExactly<OOJoystickStandardAxisProfile>(copy.get()));
		OO_CHECK(copy->power() == 3.0 && copy->parameter() == 0.5);
		OO_CHECK(Near(copy->deadzone(), STICK_DEADZONE));	// not copied
	}
}


OO_TEST(splineProfileEditing)
{
	@autoreleasepool
	{
		oo::Ref<OOJoystickSplineAxisProfile> profile = oo::makeRef<OOJoystickSplineAxisProfile>();
		OO_CHECK(dynamic_cast<OOJoystickAxisProfile *>(profile.get()) != nullptr);
		OO_CHECK(profile->countPoints() == 0 && profile->controlPoints().empty());
		OO_CHECK(Near(profile->rawValue(0.3), 0.3) && Near(profile->rawValue(-0.3), -0.3));	// the straight line
		OO_CHECK(Near(profile->gradient(0.3), 1.0));
		OO_CHECK(SamePoint(profile->pointAtIndex(-1), 0, 0) && SamePoint(profile->pointAtIndex(0), 1, 1));

		OO_CHECK(profile->addControl(NSMakePoint(0.01, 0.5)) == -1);	// too near the ends
		OO_CHECK(profile->addControl(NSMakePoint(0.99, 0.5)) == -1);
		OO_CHECK(profile->addControl(NSMakePoint(0.5, 0.25)) == 0);
		OO_CHECK(profile->addControl(NSMakePoint(0.25, 0.1)) == 0);	// inserted in x order
		OO_CHECK(profile->addControl(NSMakePoint(0.75, 0.6)) == 2);
		OO_CHECK(profile->addControl(NSMakePoint(0.26, 0.2)) == 0);	// within the spacing: replaces
		OO_CHECK(profile->countPoints() == 3);
		OO_CHECK(SamePoint(profile->pointAtIndex(0), 0.26, 0.2));
		OO_CHECK(SamePoint(profile->pointAtIndex(1), 0.5, 0.25));
		OO_CHECK(SamePoint(profile->pointAtIndex(2), 0.75, 0.6));
		OO_CHECK(SamePoint(profile->pointAtIndex(3), 1, 1));
		std::vector<NSPoint> points = profile->controlPoints();
		OO_CHECK(points.size() == 3 && SamePoint(points[1], 0.5, 0.25));

		profile->moveControl(1, NSMakePoint(0.1, 0.3));	// past its left neighbour: kept right of it
		OO_CHECK(SamePoint(profile->pointAtIndex(1), 0.26 + 0.02, 0.3));
		profile->moveControl(1, NSMakePoint(0.5, 1.5));	// y clamped
		OO_CHECK(SamePoint(profile->pointAtIndex(1), 0.5, 1.0));
		profile->moveControl(5, NSMakePoint(0.5, 0.5));	// out of range: nothing
		OO_CHECK(profile->countPoints() == 3);

		profile->removeControl(1);
		OO_CHECK(profile->countPoints() == 2 && SamePoint(profile->pointAtIndex(1), 0.75, 0.6));
		profile->removeControl(7);
		OO_CHECK(profile->countPoints() == 2);
		profile->clearControlPoints();
		OO_CHECK(profile->countPoints() == 0 && Near(profile->rawValue(0.6), 0.6));
	}
}


OO_TEST(splineProfileCurve)
{
	@autoreleasepool
	{
		oo::Ref<OOJoystickSplineAxisProfile> profile = oo::makeRef<OOJoystickSplineAxisProfile>();
		profile->addControl(NSMakePoint(0.5, 0.25));
		profile->addControl(NSMakePoint(0.8, 0.5));

		// Passes through its control points and the ends; odd; clamped to [0, 1].
		OO_CHECK(Near(profile->rawValue(0.0), 0.0));
		OO_CHECK(Near(profile->rawValue(0.5), 0.25));
		OO_CHECK(Near(profile->rawValue(0.8), 0.5));
		OO_CHECK(Near(profile->rawValue(1.0), 1.0));
		OO_CHECK(Near(profile->rawValue(-0.5), -0.25));
		// Pinned from the Objective-C classes: the linear-quadratic-quadratic curve and its slope.
		OO_CHECK(Near(profile->rawValue(0.05), 0.019375) && Near(profile->gradient(0.05), 0.4));
		OO_CHECK(Near(profile->rawValue(0.2), 0.085) && Near(profile->gradient(0.2), 0.475));
		OO_CHECK(Near(profile->rawValue(0.35), 0.161875) && Near(profile->gradient(0.35), 0.55));
		OO_CHECK(Near(profile->rawValue(0.65), 0.3421875) && Near(profile->gradient(0.65), 0.71875));
		OO_CHECK(Near(profile->rawValue(0.95), 0.8375) && Near(profile->gradient(0.95), 3.0));
		OO_CHECK(Near(profile->rawValue(-0.65), -0.3421875));

		oo::Ref<OOJoystickSplineAxisProfile> copy(dynamic_cast<OOJoystickSplineAxisProfile *>(profile->copy().get()));
		OO_CHECK(copy != nullptr && IsExactly<OOJoystickSplineAxisProfile>(copy.get()));
		OO_CHECK(copy->countPoints() == 2 && Near(copy->rawValue(0.3), profile->rawValue(0.3)));
		copy->addControl(NSMakePoint(0.3, 0.3));
		OO_CHECK(profile->countPoints() == 2);	// the original is untouched
		OO_CHECK(Near(copy->rawValue(0.3), 0.3));
	}
}


OO_TEST(cxxProfiles)
{
	oo::Ref<OOJoystickStandardAxisProfile> standard = oo::makeRef<OOJoystickStandardAxisProfile>();
	standard->setPower(3.0);
	standard->setParameter(0.5);
	OO_CHECK(Near(standard->rawValue(0.5), 0.5 * 0.125 + 0.5 * 0.5));
	OOJoystickAxisProfile *base = standard.get();
	OO_CHECK(Near(base->value(1.0), 1.0) && Near(base->rawValue(-0.5), -(0.5 * 0.125 + 0.5 * 0.5)));	// virtual

	standard->setDeadzone(0.0);
	oo::Ref<OOJoystickAxisProfile> copy = standard->copy();
	OOJoystickStandardAxisProfile *standardCopy = dynamic_cast<OOJoystickStandardAxisProfile *>(copy.get());
	OO_CHECK(standardCopy != nullptr && standardCopy->power() == 3.0 && standardCopy->parameter() == 0.5);
	OO_CHECK(Near(copy->deadzone(), STICK_DEADZONE));	// not copied

	oo::Ref<OOJoystickSplineAxisProfile> spline = oo::makeRef<OOJoystickSplineAxisProfile>();
	OO_CHECK(spline->addControl(NSMakePoint(0.5, 0.25)) == 0 && spline->addControl(NSMakePoint(0.8, 0.5)) == 1);
	OO_CHECK(Near(spline->rawValue(0.65), 0.3421875) && Near(spline->gradient(0.95), 3.0));
	oo::Ref<OOJoystickAxisProfile> splineCopy = spline->copy();
	OO_CHECK(dynamic_cast<OOJoystickSplineAxisProfile *>(splineCopy.get()) != nullptr);
	OO_CHECK(Near(splineCopy->rawValue(0.35), 0.161875));
	OO_CHECK(dynamic_cast<OOJoystickStandardAxisProfile *>(oo::makeRef<OOJoystickAxisProfile>()->copy().get()) == nullptr);
}


OO_TEST_MAIN()
