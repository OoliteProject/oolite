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

#import "OOJoystickManager.h"
#import "OOJoystickProfile.h"
#import "OOMaths.h"

@implementation OOJoystickSplineSegment

- (id) init
{
	if ((self = [super init]))
	{
		max_t = 1.0;
		a[0] = 0.0;
		a[1] = 1.0;
		a[2] = 0.0;
	}
	return self;
}

- (id) copyWithZone: (NSZone *) zone
{
	OOJoystickSplineSegment *copy = [[OOJoystickSplineSegment allocWithZone: zone] init];
	copy->max_t = max_t;
	copy->a[0] = a[0];
	copy->a[1] = a[1];
	copy->a[2] = a[2];
	return copy;
}


- (double) value: (double) t
{
	// Don't want any sneaky people creating splines that take the joystick response above 1
	return OOClamp_0_1_d(a[0] + a[1]*t + a[2]*t*t);
}

- (double) gradient: (double) t
{
	return a[1]+2*a[2]*t;
}

- (void) set:
	(double) t0
	t1: (double) t1
	f0: (double) f0
	f1: (double) f1
	df0: (double) df0
{
	double dt;
	max_t = t1;
	dt = t1 - t0;
	if (dt == 0.0)
	{
		return;
	}
	a[0] = f0*(t1 - 2*t1)/(dt*dt) + f1*t0*t0/(dt*dt) - df0*t0*t1/dt;
	a[1] = f0*2*t0/(dt*dt) + f1*2*t0/(dt*dt) + df0*(t0+t1)/dt;
	a[2] = -f0/(dt*dt) + f1/(dt*dt) -df0/dt;
	return;
}

- (double) limit
{
	return max_t;
}

@end


@interface OOJoystickSpline (Private)

- (void) makeSegments;

@end

@implementation OOJoystickSpline

- (id) init
{
	if ((self = [super init]))
	{
		controlPoints = [NSMutableArray arrayWithCapacity: 0];
		segments = [NSMutableArray arrayWithCapacity: 1];
		[self makeSegments];
	}
	return self;
}

- (id) copyWithZone: (NSZone *) zone
{
	OOJoystickSpline *copy = [[OOJoystickSpline alloc] init];
	copy->controlPoints = [controlPoints copyWithZone: zone];
	copy->segments = [segments copyWithZone: zone];
	return copy;
}


- (int) addControl: (double) t
{
	NSPoint point1, point2;
	NSValue *value;
	int i;

	point2.x = t;
	point2.y = [self value:t];

	if (t <= 0.0 || t >= 1.0 )
	{
		return -1;
	}
	for (i = 0; i < [controlPoints count]; i++ )
	{
		point1 = [[controlPoints objectAtIndex: i] pointValue];
		if (fabs(point1.x - point2.x) < 0.01)
		{
			return i;
		}
		if (point1.x > t)
		{
			value = [NSValue valueWithPoint: point2];
			[controlPoints insertObject: value atIndex: i];
			[self makeSegments];
			return i;
		}
	}
	value = [NSValue valueWithPoint: point2];
	[controlPoints addObject: value];
	[self makeSegments];
	return [controlPoints count] - 1;
}


// Calculate segments from control points
- (void) makeSegments
{
	int i;
	NSPoint point1, point2;
	double gradient;
	OOJoystickSplineSegment* segment;
	[segments removeAllObjects];
	if ([controlPoints count] == 0)
	{
		segment = [[OOJoystickSplineSegment alloc] init];
		[segment set:0.0 t1:1.0 f0:0.0 f1:1.0 df0:1];
		[segments addObject:segment];
	}
	else
	{
		point1 = [[controlPoints objectAtIndex: 0] pointValue];
		segment = [[OOJoystickSplineSegment alloc] init];
		[segment set:0.0 t1:point1.x f0:0.0 f1:point1.y df0:point1.y/point1.x];
		[segments addObject:segment];
		gradient = [segment gradient:point1.x];
		for (i = 1; i < [controlPoints count]; i++)
		{
			point2 = [[controlPoints objectAtIndex: i] pointValue];
			segment = [[OOJoystickSplineSegment alloc] init];
			[segment set:point1.x t1:point2.x f0:point1.y f1:point2.y df0:gradient];
			[segments addObject:segment];
			gradient = [segment gradient:point2.x];
			point1 = point2;
		}
		segment = [[OOJoystickSplineSegment alloc] init];
		[segment set:point1.x t1:1.0 f0:point1.y f1:1.0 df0:gradient];
		[segments addObject:segment];
	}
	return;
}

- (void) removeControl: (int) index
{
	if (index >= 0 && index < [controlPoints count])
	{
		[controlPoints removeObjectAtIndex: index];
	}
	return;
}

- (void) moveControl: (int) index
	t: (double) t
	f: (double) f
{
	NSPoint point1, point2;
	if (index < 0 || index >= [controlPoints count])
	{
		return;
	}
	point1 = [[controlPoints objectAtIndex:index] pointValue];
	// preserve order of control points - if we attempt to move this control point beyond
	// either of its neighbours, abort
	if (index > 0)
	{
		point2 = [[controlPoints objectAtIndex: index - 1] pointValue];
		if (t - point2.x < 0.01)
		{
			return;
		}
	}
	if (index + 1 < [controlPoints count])
	{
		point2 = [[controlPoints objectAtIndex: index + 1] pointValue];
		if (point2.x - t < 0.01)
		{
			return;
		}
	}
	point1.x = t;
	point1.y = f;
	[controlPoints insertObject: [NSValue valueWithPoint: point1] atIndex: index];
	[self makeSegments];
	return;
}

- (double) value: (double) t
{
	int i;
	OOJoystickSplineSegment *segment;
	for (i = 0; i < [segments count]; i++)
	{
		segment = [segments objectAtIndex: i];
		if ([segment limit] > t)
		{
			return [segment value:t];
		}
	}
	return 1.0;
}

- (double) gradient: (double) t
{
	int i;
	OOJoystickSplineSegment *segment;
	for (i = 0; i < [segments count]; i++)
	{
		segment = [segments objectAtIndex: i];
		if ([segment limit] > t)
		{
			return [segment gradient:t];
		}
	}
	return 1.0;
}


@end

@implementation OOJoystickProfile

- (id) init
{
	if ((self = [super init]))
	{
		profiles = [NSMutableDictionary dictionaryWithCapacity:1];
		OOJoystickSpline *basic_spline = [[OOJoystickSpline alloc] init];
		[profiles setObject: basic_spline forKey: @"Spline"];
		axis_profiles = [NSMutableDictionary dictionaryWithCapacity: 3];
		[axis_profiles setObject: @"Linear" forKey: [NSNumber numberWithInt: AXIS_PITCH]];
		[axis_profiles setObject: @"Linear" forKey: [NSNumber numberWithInt: AXIS_ROLL]];
		[axis_profiles setObject: @"Linear" forKey: [NSNumber numberWithInt: AXIS_YAW]];
		deadzone = STICK_DEADZONE;
	}
	return self;
}

- (void) addProfile: (NSString *) name
	spline: (OOJoystickSpline *) spline
{
	[profiles setObject: spline forKey: name];
	return;
}

- (OOJoystickSpline *) getProfileCopy: (NSString *) name
{
	 OOJoystickSpline *profile = [profiles objectForKey: name];
	return [profile copy];
}

- (void) setProfile: (NSString *) name
	spline: (OOJoystickSpline *) spline
{
	[profiles setObject: spline forKey: spline];
	return;
}

- (void) setCubicParam: (double) param
{
	cubicParam = OOClamp_0_1_d(param);
}

- (void) setQuinticParam: (double) param
{
	quinticParam = OOClamp_0_1_d(param);
}

- (double) cubicParam
{
	return cubicParam;
}

- (double) quinticParam
{
	return quinticParam;
}

- (NSArray *) listProfiles
{
	NSMutableArray *list = [[NSMutableArray arrayWithCapacity:[[profiles allKeys] count]] autorelease];
	[list addObjectsFromArray: [profiles allKeys]];
	[list sortUsingSelector: @selector(localizedCaseInsensitiveCompare)];
	[list insertObject: @"Linear" atIndex: 0];
	[list insertObject: @"Cubic" atIndex: 1];
	[list insertObject: @"Quintic" atIndex: 2];
	return [NSArray arrayWithArray: list];
}

- (NSString *) getAxisProfile: (int) axis
{
	NSString *profile = [axis_profiles objectForKey: [[NSNumber numberWithInt: axis] autorelease]];
	if (profile == nil)
	{
		return @"Linear";
	}
	return profile;
}

- (bool) setAxisProfile: (int) axis profile:(NSString *) profileName
{
	NSNumber *key = [NSNumber numberWithInt: axis];
	if ([profiles objectForKey:key] == nil)
	{
		[key release];
		return NO;
	}
	[profiles setObject: [profileName retain] forKey: key];
	return YES;
}

- (double) deadzone
{
	return deadzone;
}

- (void) setDeadzone: (double) newValue
{
	deadzone = newValue;
	return;
}

- (double) apply: (int) axis axisvalue: (double) axisvalue
{
	if (fabs(axisvalue) < deadzone) return 0.0;
	int sign;
	NSString *profile = [axis_profiles objectForKey: [[NSNumber numberWithInt: axis] autorelease]];
	if (profile == nil)
	{
		profile = @"Linear";
	}
	if (axisvalue < 0.0)
	{
		axisvalue = (-axisvalue - deadzone)/(1.0 - deadzone);
		sign = -1;
	}
	else
	{
		axisvalue = (axisvalue - deadzone)/(1.0 - deadzone);
		sign = 1;
	}
	if (profile == @"Linear")
	{
		return sign * OOClamp_0_1_d(axisvalue);
	}
	if (profile == @"Cubic")
	{
		return sign * OOClamp_0_1_d(cubicParam*pow(axisvalue, 3)-(1.0-cubicParam)*axisvalue);
	}
	if (profile == @"Quintic")
	{
		return sign * OOClamp_0_1_d(quinticParam*pow(axisvalue, 5)-(1.0-quinticParam)*axisvalue);
	}
	OOJoystickSpline *spline = [[axis_profiles objectForKey: profile] autorelease];
	if (spline == nil)
	{
		return sign * OOClamp_0_1_d(axisvalue);
	}
	return sign * [spline value: axisvalue];
}

@end

