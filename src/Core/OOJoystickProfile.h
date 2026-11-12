/*

OOJoystickProfile.h

JoystickProfile maintains settings such as deadzone and the mapping
from joystick movement to response.

JoystickSpline manages the mapping of the physical joystick movements
to the joystick response.  It holds a series of control points, with
the points (0,0) and (1,1) being assumed. It then interpolates
splines between the set of control points - the segment between (0,0)
and the first control point is linear, the remaining segments
quadratic with the gradients matching at the control point.

The three profile classes are C++ classes, the curve (rawValue) virtual; the
spline's segments are the private OOJoystickSplineSegment.

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

#pragma once

#include <algorithm>
#include <chrono>
#include <condition_variable>
#include <cstddef>
#include <cstdint>
#include <functional>
#include <map>
#include <memory>
#include <mutex>
#include <optional>
#include <set>
#include <string>
#include <string_view>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <vector>

#include "OOFoundation.h"
#include "oofnd/Ref.hpp"

inline constexpr int STICKPROFILE_TYPE_STANDARD = 1;
inline constexpr int STICKPROFILE_TYPE_SPLINE = 2;
#define STICKPROFILE_MAX_POWER 10.0

class OOJoystickSplineSegment;  // private to OOJoystickProfile.cpp

class OOJoystickAxisProfile : public oo::RefCounted {
 public:
  OOJoystickAxisProfile();                        // -init
  virtual oo::Ref<OOJoystickAxisProfile> copy();  // -copyWithZone:
  virtual double rawValue(double x);
  double value(double x);
  double deadzone();
  void setDeadzone(double newValue);

 private:
  double deadzone_ = {};  // the ivar deadzone (it clashes with deadzone())
};

class OOJoystickStandardAxisProfile : public OOJoystickAxisProfile {
 public:
  OOJoystickStandardAxisProfile();  // -init
  oo::Ref<OOJoystickAxisProfile> copy() override;
  void setPower(double newValue);
  double power();
  void setParameter(double newValue);
  double parameter();
  double rawValue(double x) override;

 private:
  double power_ =
      {};  // the ivars power and parameter (clash with power(), parameter())
  double parameter_ = {};
};

class OOJoystickSplineAxisProfile : public OOJoystickAxisProfile {
 public:
  OOJoystickSplineAxisProfile();            // -init
  ~OOJoystickSplineAxisProfile() override;  // -dealloc
  oo::Ref<OOJoystickAxisProfile> copy() override;
  int addControl(NSPoint point);
  NSPoint pointAtIndex(std::ptrdiff_t index);
  int countPoints();
  void removeControl(std::ptrdiff_t index);
  void clearControlPoints();
  void moveControl(std::ptrdiff_t index, NSPoint point);
  double rawValue(double x) override;
  double gradient(double x);
  std::vector<NSPoint> controlPoints();

 private:
  // Create the segments from the control points.  If there's a problem, e.g.
  // control points not in order or overlapping, leave segments as they are and
  // return NO.  Otherwise return YES.
  bool makeSegments();

  // The ivar controlPoints (clashes with controlPoints()).
  std::vector<NSPoint> controlPoints_ = {};
  std::vector<oo::Ref<OOJoystickSplineSegment>>
      segments;  // no `= {}`: GCC instantiates ~Ref<T> at a default member
                 // initializer, and T is incomplete here
};
