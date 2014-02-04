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
#import "OOLoggingExtended.h"
#import "Universe.h"

#define SPLINE_POINT_MIN_SPACING 0.02

@interface OOJoystickSplineSegment: NSObject <NSCopying>
{
@private
	double start;
	double end;
	double a[4];
}

- (id) init;

// Linear spline from left point to right point.  Returns nil if right.x - left.x <= 0.0.
- (id) initWithData: (NSPoint) left right: (NSPoint) right;

// Quadratic spline from left point to right point, with gradient specified at left.  returns nil if right.x - left.x <= 0.0.
- (id) initWithData: (NSPoint) left right: (NSPoint) right gradientleft: (double) gradientleft;

// Quadratic spline from left point to right point, with gradient specified at right.  returns nil if right.x - left.x <= 0.0.
- (id) initWithData: (NSPoint) left right: (NSPoint) right gradientright: (double) gradientright;

// Cubic spline from left point to right point, with gradients specified at end points.  returns nil if right.x - left.x <= 0.0.
- (id) initWithData: (NSPoint) left right: (NSPoint) right gradientleft: (double) gradientleft gradientright: (double) gradientright;

// Linear spline from left point to right point.  Returns nil if right.x - left.x <= 0.0.
+ (id) segmentWithData: (NSPoint) left right: (NSPoint) right;

// Quadratic spline from left point to right point, with gradient specified at left.  returns nil if right.x - left.x <= 0.0.
+ (id) segmentWithData: (NSPoint) left right: (NSPoint) right gradientleft: (double) gradientleft;

// Quadratic spline from left point to right point, with gradient specified at right.  returns nil if right.x - left.x <= 0.0.
+ (id) segmentWithData: (NSPoint) left right: (NSPoint) right gradientright: (double) gradientright;

// Cubic spline from left point to right point, with gradients specified at end points.  returns nil if right.x - left.x <= 0.0.
+ (id) segmentWithData: (NSPoint) left right: (NSPoint) right gradientleft: (double) gradientleft gradientright: (double) gradientright;

- (id) copyWithZone: (NSZone *) zone;
- (double) start;
- (double) end;
- (double) value: (double) t;
- (double) gradient: (double) t;

@end

@interface OOJoystickSplineAxisProfile (Private)

// Create the segments from the control points.  If there's a problem, e.g. control points not in order or overlapping,
// leave segments as they are and return NO.  Otherwise return YES.
- (BOOL) makeSegments;

@end


@implementation OOJoystickAxisProfile

- (id) init
{
	if ((self = [super init]))
	{
		deadzone = STICK_DEADZONE;
	}
	return self;
}

- (id) copyWithZone: (NSZone *) zone
{
	OOJoystickAxisProfile *copy = [[[self class] alloc] init];
	return copy;
}


- (double) rawValue: (double) x
{
	return x;
}

- (double) value: (double) x
{
	if (fabs(x) < deadzone)
	{
		return 0.0;
	}
	return x < 0 ? -[self rawValue: (-x-deadzone)/(1.0-deadzone)] : [self rawValue: (x-deadzone)/(1.0-deadzone)];
}

- (double) deadzone
{
	return deadzone;
}

- (void) setDeadzone: (double) newValue
{
	deadzone = OOClamp_0_max_d(newValue, STICK_MAX_DEADZONE);
}

@end

@implementation OOJoystickStandardAxisProfile

- (id) init
{
	if ((self = [super init]))
	{
		power = 1.0;
		parameter = 1.0;
	}
	return self;
}

- (id) copyWithZone: (NSZone *) zone
{
	OOJoystickStandardAxisProfile *copy = [[[self class] alloc] init];
	copy->power = power;
	copy->parameter = parameter;
	return copy;
}

- (void) setPower: (double) newValue
{
	if (newValue < 1.0)
	{
		power = 1.0;
	}
	else if (newValue > STICKPROFILE_MAX_POWER)
	{
		power = STICKPROFILE_MAX_POWER;
	}
	else
	{
		power = newValue;
	}
	return;
}

- (double) power
{
	return power;
}


- (void) setParameter: (double) newValue
{
	parameter = OOClamp_0_1_d(newValue);
	return;
}

- (double) parameter
{
	return parameter;
}


- (double) rawValue: (double) x
{
	if (x < 0)
	{
		return -OOClamp_0_1_d(parameter * pow(-x,power)-(parameter - 1.0)*(-x));
	}
	return OOClamp_0_1_d(parameter * pow(x,power)-(parameter - 1.0)*(x));
}

@end

@implementation OOJoystickSplineSegment

- (id) init
{
	if ((self = [super init]))
	{
		start = 0.0;
		end = 1.0;
		a[0] = 0.0;
		a[1] = 1.0;
		a[2] = 0.0;
		a[3] = 0.0;
	}
	return self;
}

- (id) copyWithZone: (NSZone *) zone
{
	OOJoystickSplineSegment *copy = [[OOJoystickSplineSegment allocWithZone: zone] init];
	copy->start = start;
	copy->end = end;
	copy->a[0] = a[0];
	copy->a[1] = a[1];
	copy->a[2] = a[2];
	copy->a[3] = a[3];
	return copy;
}

- (id) initWithData: (NSPoint) left right: (NSPoint) right
{
	double dx = right.x - left.x;
	if (dx <= 0.0)
	{
		return nil;
	}
	if ((self = [super init]))
	{
		start = left.x;
		end = right.x;
		a[1] = (right.y - left.y)/dx;
		a[0] = left.y-a[1]*left.x;
		a[2] = 0.0;
		a[3] = 0.0;
	}
	return self;
}

- (id) initWithData:(NSPoint) left right: (NSPoint) right gradientleft: (double) gradientleft
{
	double dx = right.x - left.x;
	if (dx <= 0.0)
	{
		return nil;
	}
	if ((self = [super init]))
	{
		start = left.x;
		end = right.x;
		a[0] = left.y*right.x*(right.x - 2*left.x)/(dx*dx) + right.y*left.x*left.x/(dx*dx) - gradientleft*left.x*right.x/dx;
		a[1] = 2*left.x*(left.y-right.y)/(dx*dx) + gradientleft*(left.x+right.x)/dx;
		a[2] = (right.y-left.y)/(dx*dx) - gradientleft/dx;
	}
	return self;
}

- (id) initWithData: (NSPoint) left right: (NSPoint) right gradientright: (double) gradientright
{
	double dx = right.x - left.x;
	if (dx <= 0.0)
	{
		return nil;
	}
	if ((self = [super init]))
	{
		start = left.x;
		end = right.x;
		a[0] = (left.y*right.x*right.x + right.y*left.x*(left.x-2*right.x))/(dx*dx) + gradientright*left.x*right.x/dx;
		a[1] = 2*right.x*(right.y-left.y)/(dx*dx) - gradientright*(left.x+right.x)/dx;
		a[2] = (left.y-right.y)/(dx*dx) + gradientright/dx;
	}
	return self;
}

- (id) initWithData: (NSPoint) left right: (NSPoint) right gradientleft: (double) gradientleft gradientright: (double) gradientright
{
	double dx = right.x - left.x;
	if (dx <= 0.0)
	{
		return nil;
	}
	if ((self = [super init]))
	{
		start = left.x;
		end = right.x;
		a[0] = (left.y*right.x*right.x*(right.x-3*left.x) - right.y*left.x*left.x*(left.x-3*right.x))/(dx*dx*dx) - (gradientleft*right.x + gradientright*left.x)*left.x*right.x/(dx*dx);
		a[1] = 6*left.x*right.x*(left.y-right.y)/(dx*dx*dx) + (gradientleft*right.x*(right.x+2*left.x) + gradientright*left.x*(left.x+2*right.x))/(dx*dx);
		a[2] = 3*(left.x+right.x)*(right.y-left.y)/(dx*dx*dx) - (gradientleft*(2*right.x+left.x)+gradientright*(2*left.x+right.x))/(dx*dx);
		a[3] = 2*(left.y-right.y)/(dx*dx*dx) + (gradientleft+gradientright)/(dx*dx);
	}
	return self;
}

+ (id) segmentWithData: (NSPoint) left right: (NSPoint) right
{
	OOJoystickSplineSegment *segment = [[OOJoystickSplineSegment alloc] initWithData: left right:right];
	return [segment autorelease];
}


+ (id) segmentWithData: (NSPoint) left right: (NSPoint) right gradientleft: (double) gradientleft
{
	OOJoystickSplineSegment *segment = [[OOJoystickSplineSegment alloc] initWithData: left right:right gradientleft:gradientleft];
	return [segment autorelease];
}


+ (id) segmentWithData: (NSPoint) left right: (NSPoint) right gradientright: (double) gradientright
{
	OOJoystickSplineSegment *segment = [[OOJoystickSplineSegment alloc] initWithData: left right:right gradientright:gradientright];
	return [segment autorelease];
}


+ (id) segmentWithData: (NSPoint) left right: (NSPoint) right gradientleft: (double) gradientleft gradientright: (double) gradientright
{
	OOJoystickSplineSegment *segment = [[OOJoystickSplineSegment alloc] initWithData: left right:right gradientleft:gradientleft gradientright:gradientright];
	return [segment autorelease];
}

- (double) start
{
	return start;
}


- (double) end
{
	return end;
}


- (double) value: (double) x
{
	return a[0] + (a[1] + (a[2] + a[3]*x)*x)*x;
}

- (double) gradient: (double) x
{
	return a[1]+(2*a[2] + 3*a[3]*x)*x;
}

@end


@implementation OOJoystickSplineAxisProfile

- (id) init
{
	if ((self = [super init]))
	{
		controlPoints = [[NSMutableArray alloc] initWithCapacity: 2];
		segments = nil;
		[self makeSegments];
	}
	return self;
}

- (void) dealloc
{
	[controlPoints release];
	[segments release];
	[super dealloc];
	return;
}

- (id) copyWithZone: (NSZone *) zone
{
	OOJoystickSplineAxisProfile *copy = [[[self class] alloc] init];
	copy->controlPoints = [controlPoints copyWithZone: zone];
	copy->segments = [segments copyWithZone: zone];
	return copy;
}


- (int) addControl: (NSPoint) point
{
	NSPoint left, right;
	int i;

	if (point.x <= SPLINE_POINT_MIN_SPACING || point.x >= 1 - SPLINE_POINT_MIN_SPACING )
	{
		return -1;
	}

	left.x = 0.0;
	left.y = 0.0;
	for (i = 0; i <= [controlPoints count]; i++ )
	{
		if (i < [controlPoints count])
		{
			right = [[controlPoints objectAtIndex: i] pointValue];
		}
		else
		{
			right = NSMakePoint(1.0,1.0);
		}
		if ((point.x - left.x) < SPLINE_POINT_MIN_SPACING)
		{
			if (i == 0)
			{
				return -1;
			}
			[controlPoints replaceObjectAtIndex: i - 1 withObject: [NSValue valueWithPoint: point]];
			[self makeSegments];
			return i - 1;
		}
		if ((right.x - point.x) >= SPLINE_POINT_MIN_SPACING)
		{
			[controlPoints insertObject: [NSValue valueWithPoint: point] atIndex: i];
			[self makeSegments];
			return i;
		}
		left = right;
	}
	return -1;
}

- (NSPoint) pointAtIndex: (int) index
{
	NSPoint point;
	if (index < 0)
	{
		point.x = 0.0;
		point.y = 0.0;
	}
	else if (index >= [controlPoints count])
	{
		point.x = 1.0;
		point.y = 1.0;
	}
	else
	{
		point = [[controlPoints objectAtIndex: index] pointValue];
	}
	return point;
}

- (int) countPoints
{
	return [controlPoints count];
}


- (NSArray *) controlPoints
{
	return [NSArray arrayWithArray: controlPoints];
}

// Calculate segments from control points
- (BOOL) makeSegments
{
	int i;
	NSPoint left, right, next;
	double gradientleft, gradientright;
	OOJoystickSplineSegment* segment;
	BOOL first_segment = YES;
	NSMutableArray *new_segments = [NSMutableArray arrayWithCapacity: ([controlPoints count] + 1)];

	left.x = 0.0;
	left.y = 0.0;
	if ([controlPoints count] == 0)
	{
		right.x = 1.0;
		right.y = 1.0;
		segment = [OOJoystickSplineSegment segmentWithData: left right: right];
		[new_segments addObject:segment];
	}
	else
	{
		gradientleft = 1.0;
		right = [[controlPoints objectAtIndex: 0] pointValue];
		for (i = 0; i < [controlPoints count]; i++)
		{
			next = [self pointAtIndex: i + 1];
			if (next.x - left.x > 0.0)
			{
				// we make the gradient at right equal to the gradient of a straight line between the neighcouring points
				gradientright = (next.y - left.y)/(next.x - left.x);
				if (first_segment)
				{
					segment = [OOJoystickSplineSegment segmentWithData: left right: right gradientright: gradientright];
				}
				else
				{
					segment = [OOJoystickSplineSegment segmentWithData: left right: right gradientleft: gradientleft gradientright: gradientright];
				}
				if (segment == nil)
				{
					return NO;
				}
				else
				{
					[new_segments addObject: segment];
					gradientleft = gradientright;
					first_segment = NO;
					left = right;
				}
			}
			right = next;
		}
		right.x = 1.0;
		right.y = 1.0;
		segment = [OOJoystickSplineSegment segmentWithData: left right: right gradientleft: gradientleft];
		if (segment == nil)
		{
			return NO;
		}
		[new_segments addObject: segment];
	}
	[segments release];
	segments = [[NSArray arrayWithArray: new_segments] retain];
	return YES;
}

- (void) removeControl: (int) index
{
	if (index >= 0 && index < [controlPoints count])
	{
		[controlPoints removeObjectAtIndex: index];
		[self makeSegments];
	}
	return;
}

- (void) clearControlPoints
{
	[controlPoints removeAllObjects];
	[self makeSegments];
}

- (void) moveControl: (int) index point: (NSPoint) point
{
	NSPoint left, right;

	point.x = OOClamp_0_1_d(point.x);
	point.y = OOClamp_0_1_d(point.y);
	if (index < 0 || index >= [controlPoints count])
	{
		return;
	}
	if (index == 0)
	{
		left.x = 0.0;
		right.x = 0.0;
	}
	else
	{
		left = [[controlPoints objectAtIndex: (index-1)] pointValue];
	}
	if (index == [controlPoints count] - 1)
	{
		right.x = 1.0;
		right.y = 1.0;
	}
	else
	{
		right = [[controlPoints objectAtIndex: (index+1)] pointValue];
	}
	// preserve order of control points - if we attempt to move this control point beyond
	// either of its neighbours, move it back inside.  Also keep neighbours a distance of at least SPLINE_POINT_MIN_SPACING apart
	if (point.x - left.x < SPLINE_POINT_MIN_SPACING)
	{
		point.x = left.x + SPLINE_POINT_MIN_SPACING;
		if (right.x - point.x < SPLINE_POINT_MIN_SPACING)
		{
			point.x = (left.x + right.x)/2;
		}
	}
	else if (right.x - point.x < SPLINE_POINT_MIN_SPACING)
	{
		point.x = right.x - SPLINE_POINT_MIN_SPACING;
		if (point.x - left.x < SPLINE_POINT_MIN_SPACING)
		{
			point.x = (left.x + right.x)/2;
		}
	}
	[controlPoints replaceObjectAtIndex: index withObject: [NSValue valueWithPoint: point]];
	[self makeSegments];
	return;
}

- (double) rawValue: (double) x
{
	int i;
	OOJoystickSplineSegment *segment;
	double sign;
	
	if (x < 0)
	{
		sign = -1.0;
		x = -x;
	}
	else
	{
		sign = 1.0;
	}
	for (i = 0; i < [segments count]; i++)
	{
		segment = [segments objectAtIndex: i];
		if ([segment end] > x)
		{
			return sign * OOClamp_0_1_d([segment value:x]);
		}
	}
	return 1.0;
}

- (double) gradient: (double) x
{
	int i;
	OOJoystickSplineSegment *segment;
	for (i = 0; i < [segments count]; i++)
	{
		segment = [segments objectAtIndex: i];
		if ([segment end] > x)
		{
			return [segment gradient:x];
		}
	}
	return 1.0;
}


@end

