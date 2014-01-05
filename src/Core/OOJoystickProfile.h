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

@interface OOJoystickSplineSegment: NSObject <NSCopying>
{
@private
	double max_t;
	double a[3];
}

- (id) init;
- (id) copyWithZone: (NSZone *) zone;
- (double) value: (double) t;
- (double) gradient: (double) t;
// Set the segment parameters so that f(t0) = f0, f(t1) = f1 and the gradient at t0 = df0
- (void) set: (double) t0 t1:(double) t1 f0:(double) f0 f1:(double) f1 df0:(double) df0;
- (double) limit;

@end

@interface OOJoystickSpline: NSObject <NSCopying>
{
@private
	NSMutableArray *controlPoints;
	NSMutableArray *segments;
}

- (id) init;
- (id) copyWithZone: (NSZone *) zone;
- (int) addControl: (double) t;
- (void) removeControl: (int) index;
- (void) moveControl: (int) index t: (double) t f: (double) f;
- (double) value: (double) t;
- (double) gradient: (double) t;

@end

@interface OOJoystickProfile: NSObject
{
@private
	NSMutableDictionary *profiles;
	NSMutableDictionary *axis_profiles;
	double cubicParam;
	double quinticParam;
	double deadzone;
}

- (id) init;
- (void) addProfile: (NSString *) name spline: (OOJoystickSpline *) spline;
- (OOJoystickSpline *) getProfileCopy: (NSString *) name;
- (void) setProfile: (NSString *) name spline: (OOJoystickSpline *) spline;
- (void) setCubicParam: (double) param;
- (void) setQuinticParam: (double) param;
- (double) cubicParam;
- (double) quinticParam;
- (NSArray *) listProfiles;
- (NSString *) getAxisProfile: (int) axis;
- (bool) setAxisProfile: (int) axis profile:(NSString *) profileName;
- (double) deadzone;
- (void) setDeadzone: (double) newValue;
- (double) apply: (int) axis axisvalue: (double) axisvalue;


@end

