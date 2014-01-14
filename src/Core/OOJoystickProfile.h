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

#define STICKPROFILE_TYPE_POLYNOMIAL	1
#define STICKPROFILE_TYPE_SPLINE	2
#define STICKPROFILE_MAX_POWER		10.0

enum JOYSTICK_PROFILE_TYPES {
	JOYSTICK_PROFILE_TYPE_STANDARD,
	JOYSTICK_PROFILE_TYPE_POLYNOMIAL,
	JOYSTICK_PROFILE_TYPE_SPLINE
};

@interface OOJoystickAxisProfile : NSObject <NSCopying>

- (id) init;
- (id) copyWithZone: (NSZone *) zone;
- (double) value: (double) x;
- (double) value: (double) x deadzone: (double) deadzone;

@end

@interface OOJoystickPolynomialAxisProfile: OOJoystickAxisProfile
{
@private
	double power;
	double parameter;
}

- (id) init;
- (id) copyWithZone: (NSZone *) zone;
- (void) setPower: (double) newValue;
- (double) power;
- (void) setParameter: (double) newValue;
- (double) parameter;
- (double) value: (double) x;

@end

@interface OOJoystickSplineAxisProfile: OOJoystickAxisProfile
{
@private
	NSMutableArray *controlPoints;
	NSArray *segments;
}

- (id) init;
- (void) dealloc;
- (id) copyWithZone: (NSZone *) zone;
- (int) addControl: (NSPoint) point;
- (NSPoint) pointAtIndex: (int) index;
- (int) countPoints;
- (void) removeControl: (int) index;
- (void) clearControlPoints;
- (void) moveControl: (int) index point: (NSPoint) point;
- (double) value: (double) x;
- (double) gradient: (double) x;
- (NSArray *) controlPoints;

@end

