/*

OOLaserShotEntity.m


Oolite
Copyright (C) 2004-2012 Giles C Williams and contributors

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
#import "OOMacroOpenGL.h"


#define kLaserDuration		(0.175)	// seconds

// Default colour
#define kLaserRed			(1.0f)
#define kLaserGreen			(0.0f)
#define kLaserBlue			(0.0f)

// Constant alpha
#define kLaserAlpha			(0.75f)

#define kLaserHalfWidth		(0.25f)


@implementation OOLaserShotEntity

- (instancetype) initLaserFromShip:(ShipEntity *)srcEntity direction:(OOWeaponFacing)direction offset:(Vector)offset
{
	if (!(self = [super init]))  return nil;
	
	ShipEntity			*ship = [srcEntity rootShipEntity];
	Vector				middle = OOBoundingBoxCenter([srcEntity boundingBox]);
	
	NSCParameterAssert([srcEntity isShip] && [ship isShip]);
	
	[self setStatus:STATUS_EFFECT];
	
	if (ship == srcEntity) 
	{
		// main laser offset
		position = vector_add([ship position], OOVectorMultiplyMatrix(offset, [ship drawRotationMatrix]));
	}
	else
	{
		// subentity laser
		position = [srcEntity absolutePositionForSubentityOffset:middle];
	}
	
	Quaternion q = kIdentityQuaternion;
	Vector q_up = vector_up_from_quaternion(q);
	Quaternion q0 = [ship normalOrientation];
	velocity = vector_multiply_scalar(vector_forward_from_quaternion(q0), [ship flightSpeed]);
	
	switch (direction)
	{
		case WEAPON_FACING_NONE:
		case WEAPON_FACING_FORWARD:
			break;
			
		case WEAPON_FACING_AFT:
			quaternion_rotate_about_axis(&q, q_up, M_PI);
			
		case WEAPON_FACING_PORT:
			quaternion_rotate_about_axis(&q, q_up, M_PI/2.0);
			break;
			
		case WEAPON_FACING_STARBOARD:
			quaternion_rotate_about_axis(&q, q_up, -M_PI/2.0);
			break;
	}
	
	[self setOrientation:quaternion_multiply(q,q0)];
	[self setOwner:ship];
	_range = [srcEntity weaponRange];
	_lifetime = kLaserDuration;
	
	_color[0] = kLaserRed;
	_color[1] = kLaserGreen;
	_color[2] = kLaserBlue;
	_color[3] = kLaserAlpha;
	
	_offset = (ship == srcEntity) ? offset : middle;
	_relOrientation = q;
	
	return self;
}


+ (instancetype) laserFromShip:(ShipEntity *)ship direction:(OOWeaponFacing)direction offset:(Vector)offset
{
	return [[[self alloc] initLaserFromShip:ship direction:direction offset:offset] autorelease];
}


- (void) dealloc
{
	[self setColor:nil];
	
	[super dealloc];
}


- (NSString *) descriptionComponents
{
	return [NSString stringWithFormat:@"ttl: %.3fs - %@ orientation %@", _lifetime, [super descriptionComponents], QuaternionDescription([self orientation])];
}


- (void) setColor:(OOColor *)color
{
	_color[0] = [color redComponent];
	_color[1] = [color greenComponent];
	_color[2] = [color blueComponent];
	// Ignore alpha; _color[3] is constant.
}


- (void) setRange:(GLfloat)range
{
	_range = range;
}


- (void) update:(OOTimeDelta)delta_t
{
	[super update:delta_t];
	_lifetime -= delta_t;
	ShipEntity		*ship = [self owner];
	
	if ([ship isPlayer]) 
	{
		// reposition this shot accurately.
		position = vector_add([ship position], OOVectorMultiplyMatrix(_offset, [ship drawRotationMatrix]));
		[self setOrientation:quaternion_multiply(_relOrientation,[ship normalOrientation])];
	}
	else
	{
		// NPCs will make do with approximate repositioning.
		[self applyVelocityWithTimeDelta:delta_t];
	}

	if (_lifetime < 0)  
	{
		[UNIVERSE removeEntity:self];
	}
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
	
	OO_ENTER_OPENGL();
	
	OOGL(glPushAttrib(GL_ENABLE_BIT | GL_COLOR_BUFFER_BIT));
	
	OOGL(glDisable(GL_CULL_FACE));	// face culling
	OOGL(glDisable(GL_TEXTURE_2D));
	OOGL(glEnable(GL_BLEND));
	OOGL(glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA));
	OOGL(glEnableClientState(GL_VERTEX_ARRAY));
	
	
	/*	FIXME: spread damage across the lifetime of the shot,
		hurting whatever is hit in a given frame.
		-- Ahruman 2011-01-31
	*/
	
	OOGL(glColor4fv(_color));
	glScaled(kLaserHalfWidth, kLaserHalfWidth, _range);
	glVertexPointer(3, GL_FLOAT, 0, kLaserVertices);
	glDrawArrays(GL_QUADS, 0, 8);
	
	OOGL(glDisableClientState(GL_VERTEX_ARRAY));
	OOGL(glPopAttrib());
	
	CheckOpenGLErrors(@"OOLaserShotEntity after drawing %@", self);
}


- (BOOL) isEffect
{
	return YES;
}


- (BOOL) canCollide
{
	return NO;
}

@end
