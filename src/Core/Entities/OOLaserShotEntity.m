/*

OOLaserShotEntity.m


Oolite
Copyright (C) 2004-2011 Giles C Williams and contributors

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

#import "OOLaserShotEntity.h"
#import "Universe.h"
#import "ShipEntity.h"


#define kLaserDuration		(0.175)	// seconds

// Default colour
#define kLaserRed			(1.0f)
#define kLaserGreen			(0.0f)
#define kLaserBlue			(0.0f)

// Constant alpha
#define kLaserAlpha			(0.75f)

#define kLaserHalfWidth		(0.25f)


@implementation OOLaserShotEntity

- (id) initLaserFromShip:(ShipEntity *)srcEntity view:(OOViewID)view offset:(Vector)offset
{
	ShipEntity			*ship = [srcEntity rootShipEntity];
	BoundingBox 		bbox = [srcEntity boundingBox];
	
	if (!(self = [super init]))  return nil;
	
	NSCParameterAssert([srcEntity isShip] && [ship isShip]);
	
	[self setStatus:STATUS_EFFECT];
	
	Vector middle = OOBoundingBoxCenter(bbox);
	Vector pos;
	if (ship == srcEntity) 
	{
		// main laser offset
		pos = vector_add([ship position], OOVectorMultiplyMatrix(offset, [ship drawRotationMatrix]));
	}
	else
	{
		// subentity laser
		pos = [srcEntity absolutePositionForSubentityOffset:middle];
	}
	
	// FIXME: use rotation matrix. We should have corresponding extractors.
	Quaternion q = [ship normalOrientation];
	Vector v_up = vector_up_from_quaternion(q);
	Vector v_forward = vector_forward_from_quaternion(q);
	Vector v_right = vector_right_from_quaternion(q);
	velocity = vector_multiply_scalar(v_forward, [ship flightSpeed]);
	
	Vector	viewOffset;
	switch (view)
	{
		default:
		case VIEW_AFT:
			quaternion_rotate_about_axis(&q, v_up, M_PI);	
		case VIEW_FORWARD:
			viewOffset = vector_multiply_scalar(v_forward, middle.z);
			break;
			
		case VIEW_PORT:
			quaternion_rotate_about_axis(&q, v_up, M_PI/2.0);
			viewOffset = vector_multiply_scalar(v_right, middle.x);
			break;
			
		case VIEW_STARBOARD:
			quaternion_rotate_about_axis(&q, v_up, -M_PI/2.0);
			viewOffset = vector_multiply_scalar(v_right, middle.x);
			break;
	}
	
	position = vector_add(pos, viewOffset);
	[self setOrientation:q];
	
	[self setCollisionRadius:[srcEntity weaponRange]];
	[self setOwner:ship];
	
	_color[0] = kLaserRed;
	_color[1] = kLaserGreen;
	_color[2] = kLaserBlue;
	_color[3] = kLaserAlpha;
	
	_lifetime = kLaserDuration;
	
	return self;
}


- (void) dealloc
{
	[self setColor:nil];
	
	[super dealloc];
}


- (NSString *) descriptionComponents
{
	return [NSString stringWithFormat:@"ttl: %.3fs", _lifetime];
}


- (void) setColor:(OOColor *)color
{
	_color[0] = [color redComponent];
	_color[1] = [color greenComponent];
	_color[2] = [color blueComponent];
	// Ignore alpha; _color[3] is constant.
}


- (void) update:(OOTimeDelta)delta_t
{
	[super update:delta_t];
	_lifetime -= delta_t;
	
	[self applyVelocityWithTimeDelta:delta_t];
	
	if (_lifetime < 0)  [UNIVERSE removeEntity:self];
}


static const GLfloat kLaserVertices[] =
{
	 1.0f, 0.0f, 0.0f,
	 1.0f, 0.0f, 1.0f,
	-1.0f, 0.0f, 1.0f,
	-1.0f, 0.0f, 0.0f,
	
	0.0f,  1.0f, 0.0f,
	0.0f,  1.0f, 1.0f,
	0.0f, -1.0f, 1.0f,
	0.0f, -1.0f, 0.0f
};


- (void) drawEntity:(BOOL)immediate :(BOOL)translucent
{
	if (!translucent || [UNIVERSE breakPatternHide])  return;
	
	OOGL(glPushAttrib(GL_ENABLE_BIT | GL_COLOR_BUFFER_BIT));
	
	OOGL(glDisable(GL_CULL_FACE));	// face culling
	OOGL(glDisable(GL_TEXTURE_2D));
	OOGL(glEnable(GL_BLEND));
	OOGL(glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA));
	OOGL(glEnableClientState(GL_VERTEX_ARRAY));
	
	
	/*	FIXME: ideally, collision_radius would be updated by tracing along the
		initial firing vector. Even ideallier, we should spread damage across
		the lifetime of the shot, hurting whatever is hit in a given frame.
		Something for EMMSTRAN.
		-- Ahruman 2011-01-31
	*/
	
	OOGL(glColor4fv(_color));
	glScaled(kLaserHalfWidth, kLaserHalfWidth, collision_radius);
	glVertexPointer(3, GL_FLOAT, 0, kLaserVertices);
	glDrawArrays(GL_QUADS, 0, 8);
	
	OOGL(glDisableClientState(GL_VERTEX_ARRAY));
	OOGL(glPopAttrib());
	
	CheckOpenGLErrors(@"OOLaserShotEntity after drawing %@", self);
}

@end
