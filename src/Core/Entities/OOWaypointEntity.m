/*

OOWaypointEntity.m

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

#import "OOWaypointEntity.h"
#import "Entity.h"
#import "OOCollectionExtractors.h"
#import "OOStringExpander.h"
#import "Universe.h"
#import "PlayerEntity.h"
#import "OOPolygonSprite.h"
#import "OOOpenGL.h"
#import "OOMacroOpenGL.h"

#define OOWAYPOINT_KEY_POSITION		@"position"
#define OOWAYPOINT_KEY_ORIENTATION	@"orientation"
#define OOWAYPOINT_KEY_SIZE			@"size"
#define OOWAYPOINT_KEY_CODE			@"beaconCode"
#define OOWAYPOINT_KEY_LABEL		@"beaconLabel"

@implementation OOWaypointEntity

+ (instancetype) waypointWithDictionary:(NSDictionary *)info
{
	return [[[OOWaypointEntity alloc] initWithDictionary:info] autorelease];
}

- (id) initWithDictionary:(NSDictionary *)info
{
	self = [super init];
	if (EXPECT_NOT(self == nil))  return nil;

	oriented = YES;
	position = [info oo_hpvectorForKey:OOWAYPOINT_KEY_POSITION];
	Quaternion q = [info oo_quaternionForKey:OOWAYPOINT_KEY_ORIENTATION];
	[self setOrientation:q];
	[self setSize:[info oo_nonNegativeFloatForKey:OOWAYPOINT_KEY_SIZE defaultValue:1000.0]];
	[self setBeaconCode:[info oo_stringForKey:OOWAYPOINT_KEY_CODE defaultValue:@"W"]];
	[self setBeaconLabel:[info oo_stringForKey:OOWAYPOINT_KEY_LABEL defaultValue:@"Waypoint"]];
	
	[self setStatus:STATUS_EFFECT];
	[self setScanClass:CLASS_NO_DRAW];

	return self;
}


- (void) dealloc
{
	DESTROY(_beaconCode);
	DESTROY(_beaconLabel);
	DESTROY(_prevBeacon);
	DESTROY(_nextBeacon);
	DESTROY(_beaconDrawable);

	[super dealloc];
}


// override
- (void) setOrientation:(Quaternion)q
{
	if (quaternion_equal(q,kZeroQuaternion)) {
		q = kIdentityQuaternion;
		oriented = NO;
	} else {
		oriented = YES;
	}
	[super setOrientation:q];
}


- (BOOL) oriented
{
	return oriented;
}


- (OOScalar) size
{
	return _size;
}


- (void) setSize:(OOScalar)newSize
{
	if (newSize > 0)
	{
		_size = newSize;
		no_draw_distance = newSize * newSize * NO_DRAW_DISTANCE_FACTOR * NO_DRAW_DISTANCE_FACTOR * 2;
	}
}



- (BOOL) isEffect
{
	return YES;
}


- (BOOL) isWaypoint
{
	return YES;
}


- (void) drawImmediate:(bool)immediate translucent:(bool)translucent
{
	if (!translucent || no_draw_distance < cam_zero_distance)
	{
		return;
	}

	if (![PLAYER hasEquipmentItemProviding:@"EQ_ADVANCED_COMPASS"])
	{
		return;
	}

	int8_t i,j,k;

	GLfloat a = 0.75;
	if ([PLAYER compassTarget] != self)
	{
		a *= 0.25;
	}
	if (cam_zero_distance > _size * _size)
	{
		// dim out as gets further away; 2-D HUD display more
		// important at long range
		a -=  0.004f*(sqrtf(cam_zero_distance) / _size);
	}
	if (a < 0.01f)
	{
		return;
	}

	GLfloat s0 = _size;
	GLfloat s1 = _size * 0.75f;

	OO_ENTER_OPENGL();
	OOSetOpenGLState(OPENGL_STATE_TRANSLUCENT_PASS);
	OOGL(glEnable(GL_BLEND));
	GLScaledLineWidth(1.0);

	OOGL(glColor4f(0.0, 0.0, 1.0, a));
	OOGLBEGIN(GL_LINES);
	for (i = -1; i <= 1; i+=2)
	{
		for (j = -1; j <= 1; j+=2)
		{
			for (k = -1; k <= 1; k+=2)
			{
				glVertex3f(i*s0,j*s0,k*s1);	glVertex3f(i*s0,j*s1,k*s0);
				glVertex3f(i*s0,j*s1,k*s0);	glVertex3f(i*s1,j*s0,k*s0);
				glVertex3f(i*s1,j*s0,k*s0);	glVertex3f(i*s0,j*s0,k*s1);
			}
		}
	}
	if (oriented)
	{
		while (s1 > 20.0f)
		{
			glVertex3f(-20.0,0,-s1-20.0f);	glVertex3f(0,0,-s1);
			glVertex3f(20.0,0,-s1-20.0f);	glVertex3f(0,0,-s1);
			glVertex3f(-20.0,0,s1-20.0f);	glVertex3f(0,0,s1);
			glVertex3f(20.0,0,s1-20.0f);	glVertex3f(0,0,s1);
			s1 *= 0.5;
		}
	}
	OOGLEND();

	OOGL(glDisable(GL_BLEND));
	OOVerifyOpenGLState();
}


/* beacons */

- (NSComparisonResult) compareBeaconCodeWith:(Entity<OOBeaconEntity> *) other
{
	return [[self beaconCode] compare:[other beaconCode] options: NSCaseInsensitiveSearch];
}


- (NSString *) beaconCode
{
	return _beaconCode;
}


- (void) setBeaconCode:(NSString *)bcode
{
	if ([bcode length] == 0)  bcode = nil;
	
	if (_beaconCode != bcode)
	{
		[_beaconCode release];
		_beaconCode = [bcode copy];
		
		DESTROY(_beaconDrawable);
	}
	// if not blanking code and label is currently blank, default label to code
	if (bcode != nil && (_beaconLabel == nil || [_beaconLabel length] == 0))
	{
		[self setBeaconLabel:bcode];
	}

}


- (NSString *) beaconLabel
{
	return _beaconLabel;
}


- (void) setBeaconLabel:(NSString *)blabel
{
	if ([blabel length] == 0)  blabel = nil;
	
	if (_beaconLabel != blabel)
	{
		[_beaconLabel release];
		_beaconLabel = [OOExpand(blabel) retain];
	}
}


- (BOOL) isBeacon
{
	return [self beaconCode] != nil;
}


- (id <OOHUDBeaconIcon>) beaconDrawable
{
	if (_beaconDrawable == nil)
	{
		NSString	*beaconCode = [self beaconCode];
		NSUInteger	length = [beaconCode length];
		
		if (length > 1)
		{
			NSArray *iconData = [[UNIVERSE descriptions] oo_arrayForKey:beaconCode];
			if (iconData != nil)  _beaconDrawable = [[OOPolygonSprite alloc] initWithDataArray:iconData outlineWidth:0.5 name:beaconCode];
		}
		
		if (_beaconDrawable == nil)
		{
			if (length > 0)  _beaconDrawable = [[beaconCode substringToIndex:1] retain];
			else  _beaconDrawable = @"";
		}
	}
	
	return _beaconDrawable;
}


- (Entity <OOBeaconEntity> *) prevBeacon
{
	return [_prevBeacon weakRefUnderlyingObject];
}


- (Entity <OOBeaconEntity> *) nextBeacon
{
	return [_nextBeacon weakRefUnderlyingObject];
}


- (void) setPrevBeacon:(Entity <OOBeaconEntity> *)beaconShip
{
	if (beaconShip != [self prevBeacon])
	{
		[_prevBeacon release];
		_prevBeacon = [beaconShip weakRetain];
	}
}


- (void) setNextBeacon:(Entity <OOBeaconEntity> *)beaconShip
{
	if (beaconShip != [self nextBeacon])
	{
		[_nextBeacon release];
		_nextBeacon = [beaconShip weakRetain];
	}
}


- (BOOL) isJammingScanning 
{
	return NO;
}


@end
