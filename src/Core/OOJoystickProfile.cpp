/*

OOJoystickProfile.m

Oolite
Copyright (C) 2004-2013 Giles C Williams and contributors

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
MA 02110-1301, USA.

*/

#include "OOJoystickProfile.h"
#include "OOJoystickManager.h"
#include "OOLoggingExtended.h"
#include "OOMaths.h"
#include "Universe.h"

#define SPLINE_POINT_MIN_SPACING 0.02

class OOJoystickSplineSegment : public oo::RefCounted {
public:
    OOJoystickSplineSegment(); // -init

    // Linear spline from left point to right point.  Returns nil if right.x - left.x <= 0.0.
    static oo::Ref<OOJoystickSplineSegment> segmentWithData(NSPoint left, NSPoint right);

    // Quadratic spline from left point to right point, with gradient specified at left.  returns nil if right.x - left.x <= 0.0.
    static oo::Ref<OOJoystickSplineSegment> segmentWithData(NSPoint left, NSPoint right, double gradientleft);

    // Quadratic spline from left point to right point, with gradient specified at right.  returns nil if right.x - left.x <= 0.0.
    // (+segmentWithData:right:gradientright: has the same argument types as the one above, so it keeps its last keyword.)
    static oo::Ref<OOJoystickSplineSegment> segmentWithDataGradientRight(NSPoint left, NSPoint right, double gradientright);

    // Cubic spline from left point to right point, with gradients specified at end points.  returns nil if right.x - left.x <= 0.0.
    static oo::Ref<OOJoystickSplineSegment> segmentWithData(NSPoint left, NSPoint right, double gradientleft, double gradientright);

    oo::Ref<OOJoystickSplineSegment> copy(); // -copyWithZone:
    double start();
    double end();
    double value(double t);
    double gradient(double t);

private:
    // The -initWithData:... initialisers, which could fail (amendment oo-bhb9 item 1).
    bool initWithData(NSPoint left, NSPoint right);
    bool initWithData(NSPoint left, NSPoint right, double gradientleft);
    bool initWithDataGradientRight(NSPoint left, NSPoint right, double gradientright);
    bool initWithData(NSPoint left, NSPoint right, double gradientleft, double gradientright);

    double start_ = { }; // the ivars start and end (amendment oo-z1s4 item 1: they clash with start(), end())
    double end_ = { };
    double a[4] = { };
};

OOJoystickAxisProfile::OOJoystickAxisProfile()
{
    deadzone_ = STICK_DEADZONE;
}

oo::Ref<OOJoystickAxisProfile> OOJoystickAxisProfile::copy()
{
    // [[[self class] alloc] init]: only an OOJoystickAxisProfile itself gets here; both subclasses override.
    oo::Ref<OOJoystickAxisProfile> copy = oo::makeRef<OOJoystickAxisProfile>();
    return copy;
}

double OOJoystickAxisProfile::rawValue(double x)
{
    return x;
}

double OOJoystickAxisProfile::value(double x)
{
    if (fabs(x) < deadzone_) {
        return 0.0;
    }
    return x < 0 ? -rawValue((-x - deadzone_) / (1.0 - deadzone_)) : rawValue((x - deadzone_) / (1.0 - deadzone_));
}

double OOJoystickAxisProfile::deadzone()
{
    return deadzone_;
}

void OOJoystickAxisProfile::setDeadzone(double newValue)
{
    deadzone_ = OOClamp_0_max_d(newValue, STICK_MAX_DEADZONE);
}

OOJoystickStandardAxisProfile::OOJoystickStandardAxisProfile()
{
    power_ = 1.0;
    parameter_ = 1.0;
}

oo::Ref<OOJoystickAxisProfile> OOJoystickStandardAxisProfile::copy()
{
    oo::Ref<OOJoystickStandardAxisProfile> copy = oo::makeRef<OOJoystickStandardAxisProfile>();
    copy->power_ = power_;
    copy->parameter_ = parameter_;
    return copy;
}

void OOJoystickStandardAxisProfile::setPower(double newValue)
{
    if (newValue < 1.0) {
        power_ = 1.0;
    } else if (newValue > STICKPROFILE_MAX_POWER) {
        power_ = STICKPROFILE_MAX_POWER;
    } else {
        power_ = newValue;
    }
    return;
}

double OOJoystickStandardAxisProfile::power()
{
    return power_;
}

void OOJoystickStandardAxisProfile::setParameter(double newValue)
{
    parameter_ = OOClamp_0_1_d(newValue);
    return;
}

double OOJoystickStandardAxisProfile::parameter()
{
    return parameter_;
}

double OOJoystickStandardAxisProfile::rawValue(double x)
{
    if (x < 0) {
        return -OOClamp_0_1_d(parameter_ * pow(-x, power_) - (parameter_ - 1.0) * (-x));
    }
    return OOClamp_0_1_d(parameter_ * pow(x, power_) - (parameter_ - 1.0) * (x));
}

OOJoystickSplineSegment::OOJoystickSplineSegment()
{
    start_ = 0.0;
    end_ = 1.0;
    a[0] = 0.0;
    a[1] = 1.0;
    a[2] = 0.0;
    a[3] = 0.0;
}

oo::Ref<OOJoystickSplineSegment> OOJoystickSplineSegment::copy()
{
    oo::Ref<OOJoystickSplineSegment> copy = oo::makeRef<OOJoystickSplineSegment>();
    copy->start_ = start_;
    copy->end_ = end_;
    copy->a[0] = a[0];
    copy->a[1] = a[1];
    copy->a[2] = a[2];
    copy->a[3] = a[3];
    return copy;
}

/*	The -initWithData:... bodies ran on a zeroed object ([super init], not [self init]); here the
        constructor above has run first. Every path that returns true sets start, end and a[0..2], and
        the two that leave a[3] alone leave it 0 either way, so the segment is the same.
*/
bool OOJoystickSplineSegment::initWithData(NSPoint left, NSPoint right)
{
    double dx = right.x - left.x;
    if (dx <= 0.0) {
        return false;
    }
    start_ = left.x;
    end_ = right.x;
    a[1] = (right.y - left.y) / dx;
    a[0] = left.y - a[1] * left.x;
    a[2] = 0.0;
    a[3] = 0.0;
    return true;
}

bool OOJoystickSplineSegment::initWithData(NSPoint left, NSPoint right, double gradientleft)
{
    double dx = right.x - left.x;
    if (dx <= 0.0) {
        return false;
    }
    start_ = left.x;
    end_ = right.x;
    a[0] = left.y * right.x * (right.x - 2 * left.x) / (dx * dx) + right.y * left.x * left.x / (dx * dx) - gradientleft * left.x * right.x / dx;
    a[1] = 2 * left.x * (left.y - right.y) / (dx * dx) + gradientleft * (left.x + right.x) / dx;
    a[2] = (right.y - left.y) / (dx * dx) - gradientleft / dx;
    return true;
}

bool OOJoystickSplineSegment::initWithDataGradientRight(NSPoint left, NSPoint right, double gradientright)
{
    double dx = right.x - left.x;
    if (dx <= 0.0) {
        return false;
    }
    start_ = left.x;
    end_ = right.x;
    a[0] = (left.y * right.x * right.x + right.y * left.x * (left.x - 2 * right.x)) / (dx * dx) + gradientright * left.x * right.x / dx;
    a[1] = 2 * right.x * (right.y - left.y) / (dx * dx) - gradientright * (left.x + right.x) / dx;
    a[2] = (left.y - right.y) / (dx * dx) + gradientright / dx;
    return true;
}

bool OOJoystickSplineSegment::initWithData(NSPoint left, NSPoint right, double gradientleft, double gradientright)
{
    double dx = right.x - left.x;
    if (dx <= 0.0) {
        return false;
    }
    start_ = left.x;
    end_ = right.x;
    a[0] = (left.y * right.x * right.x * (right.x - 3 * left.x) - right.y * left.x * left.x * (left.x - 3 * right.x)) / (dx * dx * dx) - (gradientleft * right.x + gradientright * left.x) * left.x * right.x / (dx * dx);
    a[1] = 6 * left.x * right.x * (left.y - right.y) / (dx * dx * dx) + (gradientleft * right.x * (right.x + 2 * left.x) + gradientright * left.x * (left.x + 2 * right.x)) / (dx * dx);
    a[2] = 3 * (left.x + right.x) * (right.y - left.y) / (dx * dx * dx) - (gradientleft * (2 * right.x + left.x) + gradientright * (2 * left.x + right.x)) / (dx * dx);
    a[3] = 2 * (left.y - right.y) / (dx * dx * dx) + (gradientleft + gradientright) / (dx * dx);
    return true;
}

oo::Ref<OOJoystickSplineSegment> OOJoystickSplineSegment::segmentWithData(NSPoint left, NSPoint right)
{
    oo::Ref<OOJoystickSplineSegment> segment = oo::makeRef<OOJoystickSplineSegment>();
    if (!segment->initWithData(left, right))
        return nullptr;
    return segment;
}

oo::Ref<OOJoystickSplineSegment> OOJoystickSplineSegment::segmentWithData(NSPoint left, NSPoint right, double gradientleft)
{
    oo::Ref<OOJoystickSplineSegment> segment = oo::makeRef<OOJoystickSplineSegment>();
    if (!segment->initWithData(left, right, gradientleft))
        return nullptr;
    return segment;
}

oo::Ref<OOJoystickSplineSegment> OOJoystickSplineSegment::segmentWithDataGradientRight(NSPoint left, NSPoint right, double gradientright)
{
    oo::Ref<OOJoystickSplineSegment> segment = oo::makeRef<OOJoystickSplineSegment>();
    if (!segment->initWithDataGradientRight(left, right, gradientright))
        return nullptr;
    return segment;
}

oo::Ref<OOJoystickSplineSegment> OOJoystickSplineSegment::segmentWithData(NSPoint left, NSPoint right, double gradientleft, double gradientright)
{
    oo::Ref<OOJoystickSplineSegment> segment = oo::makeRef<OOJoystickSplineSegment>();
    if (!segment->initWithData(left, right, gradientleft, gradientright))
        return nullptr;
    return segment;
}

double OOJoystickSplineSegment::start()
{
    return start_;
}

double OOJoystickSplineSegment::end()
{
    return end_;
}

double OOJoystickSplineSegment::value(double x)
{
    return a[0] + (a[1] + (a[2] + a[3] * x) * x) * x;
}

double OOJoystickSplineSegment::gradient(double x)
{
    return a[1] + (2 * a[2] + 3 * a[3] * x) * x;
}

OOJoystickSplineAxisProfile::OOJoystickSplineAxisProfile()
{
    controlPoints_.reserve(2);
    segments.clear();
    makeSegments();
}

OOJoystickSplineAxisProfile::~OOJoystickSplineAxisProfile()
{
    return;
}

oo::Ref<OOJoystickAxisProfile> OOJoystickSplineAxisProfile::copy()
{
    oo::Ref<OOJoystickSplineAxisProfile> copy = oo::makeRef<OOJoystickSplineAxisProfile>();
    copy->controlPoints_ = controlPoints_;
    copy->segments = segments; // the same segment objects, as the array copy held
    return copy;
}

int OOJoystickSplineAxisProfile::addControl(NSPoint point)
{
    NSPoint left, right;
    NSUInteger i;

    if (point.x <= SPLINE_POINT_MIN_SPACING || point.x >= 1 - SPLINE_POINT_MIN_SPACING) {
        return -1;
    }

    left.x = 0.0;
    left.y = 0.0;
    for (i = 0; i <= controlPoints_.size(); i++) {
        if (i < controlPoints_.size()) {
            right = controlPoints_[i];
        } else {
            right = NSMakePoint(1.0, 1.0);
        }
        if ((point.x - left.x) < SPLINE_POINT_MIN_SPACING) {
            if (i == 0) {
                return -1;
            }
            controlPoints_[i - 1] = point;
            makeSegments();
            return i - 1;
        }
        if ((right.x - point.x) >= SPLINE_POINT_MIN_SPACING) {
            controlPoints_.insert(controlPoints_.begin() + i, point);
            makeSegments();
            return i;
        }
        left = right;
    }
    return -1;
}

NSPoint OOJoystickSplineAxisProfile::pointAtIndex(NSInteger index)
{
    NSPoint point;
    if (index < 0) {
        point.x = 0.0;
        point.y = 0.0;
    } else if (index >= (NSInteger)controlPoints_.size()) {
        point.x = 1.0;
        point.y = 1.0;
    } else {
        point = controlPoints_[index];
    }
    return point;
}

int OOJoystickSplineAxisProfile::countPoints()
{
    return controlPoints_.size();
}

std::vector<NSPoint> OOJoystickSplineAxisProfile::controlPoints()
{
    return controlPoints_;
}

// Calculate segments from control points
bool OOJoystickSplineAxisProfile::makeSegments()
{
    NSUInteger i;
    NSPoint left, right, next;
    double gradientleft, gradientright;
    oo::Ref<OOJoystickSplineSegment> segment;
    bool first_segment = true;
    std::vector<oo::Ref<OOJoystickSplineSegment>> new_segments;
    new_segments.reserve(controlPoints_.size() + 1);

    left.x = 0.0;
    left.y = 0.0;
    if (controlPoints_.size() == 0) {
        right.x = 1.0;
        right.y = 1.0;
        segment = OOJoystickSplineSegment::segmentWithData(left, right);
        new_segments.emplace_back(segment);
    } else {
        gradientleft = 1.0;
        right = controlPoints_[0];
        for (i = 0; i < controlPoints_.size(); i++) {
            next = pointAtIndex(i + 1);
            if (next.x - left.x > 0.0) {
                // we make the gradient at right equal to the gradient of a straight line between the neighcouring points
                gradientright = (next.y - left.y) / (next.x - left.x);
                if (first_segment) {
                    segment = OOJoystickSplineSegment::segmentWithDataGradientRight(left, right, gradientright);
                } else {
                    segment = OOJoystickSplineSegment::segmentWithData(left, right, gradientleft, gradientright);
                }
                if (segment == nullptr) {
                    return false;
                } else {
                    new_segments.emplace_back(segment);
                    gradientleft = gradientright;
                    first_segment = false;
                    left = right;
                }
            }
            right = next;
        }
        right.x = 1.0;
        right.y = 1.0;
        segment = OOJoystickSplineSegment::segmentWithData(left, right, gradientleft);
        if (segment == nullptr) {
            return false;
        }
        new_segments.emplace_back(segment);
    }
    segments = std::move(new_segments);
    return true;
}

void OOJoystickSplineAxisProfile::removeControl(NSInteger index)
{
    if (index >= 0 && index < (NSInteger)controlPoints_.size()) {
        controlPoints_.erase(controlPoints_.begin() + index);
        makeSegments();
    }
    return;
}

void OOJoystickSplineAxisProfile::clearControlPoints()
{
    controlPoints_.clear();
    makeSegments();
}

void OOJoystickSplineAxisProfile::moveControl(NSInteger index, NSPoint point)
{
    NSPoint left, right;

    point.x = OOClamp_0_1_d(point.x);
    point.y = OOClamp_0_1_d(point.y);
    if (index < 0 || index >= (NSInteger)controlPoints_.size()) {
        return;
    }
    if (index == 0) {
        left.x = 0.0;
        right.x = 0.0;
    } else {
        left = controlPoints_[index - 1];
    }
    if (index == (NSInteger)controlPoints_.size() - 1) {
        right.x = 1.0;
        right.y = 1.0;
    } else {
        right = controlPoints_[index + 1];
    }
    // preserve order of control points - if we attempt to move this control point beyond
    // either of its neighbours, move it back inside.  Also keep neighbours a distance of at least SPLINE_POINT_MIN_SPACING apart
    if (point.x - left.x < SPLINE_POINT_MIN_SPACING) {
        point.x = left.x + SPLINE_POINT_MIN_SPACING;
        if (right.x - point.x < SPLINE_POINT_MIN_SPACING) {
            point.x = (left.x + right.x) / 2;
        }
    } else if (right.x - point.x < SPLINE_POINT_MIN_SPACING) {
        point.x = right.x - SPLINE_POINT_MIN_SPACING;
        if (point.x - left.x < SPLINE_POINT_MIN_SPACING) {
            point.x = (left.x + right.x) / 2;
        }
    }
    controlPoints_[index] = point;
    makeSegments();
    return;
}

double OOJoystickSplineAxisProfile::rawValue(double x)
{
    NSUInteger i;
    OOJoystickSplineSegment* segment;
    double sign;

    if (x < 0) {
        sign = -1.0;
        x = -x;
    } else {
        sign = 1.0;
    }
    for (i = 0; i < segments.size(); i++) {
        segment = segments[i].get();
        if (segment->end() > x) {
            return sign * OOClamp_0_1_d(segment->value(x));
        }
    }
    return 1.0;
}

double OOJoystickSplineAxisProfile::gradient(double x)
{
    NSUInteger i;
    OOJoystickSplineSegment* segment;
    for (i = 0; i < segments.size(); i++) {
        segment = segments[i].get();
        if (segment->end() > x) {
            return segment->gradient(x);
        }
    }
    return 1.0;
}
