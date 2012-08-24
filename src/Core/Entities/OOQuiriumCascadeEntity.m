/*

OOQuiriumCascadeEntity.m


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

#import "OOQuiriumCascadeEntity.h"
#import "PlayerEntity.h"
#import "Universe.h"
#import "OOMacroOpenGL.h"


#define kQuiriumCascadeDuration			(20.0)	// seconds
#define kQuiriumCollisionDelay			(0.05)	// seconds before we start colliding with and damaging things.


@implementation OOQuiriumCascadeEntity

- (id) initQuiriumCascadeFromShip:(ShipEntity *)ship
{
	if (ship == nil)
	{
		[self release];
		return nil;
	}
	
	if ((self = [super init]))
	{
		[self setPosition:[ship position]];
		
		[self setStatus:STATUS_EFFECT];
		scanClass = CLASS_MINE;
		
		[self setOwner:[ship owner]];
		
		// Red and green channels are animated.
		_color[2] = 1.0f;
		_color[3] = 0.5f;
	}
	
	return self;
}


+ (instancetype) quiriumCascadeFromShip:(ShipEntity *)ship
{
	return [[[self alloc] initQuiriumCascadeFromShip:ship] autorelease];
}


- (NSString *) descriptionComponents
{
	return [NSString stringWithFormat:@"%f seconds passed of %f", _timePassed, kQuiriumCascadeDuration];
}


- (void) update:(OOTimeDelta) delta_t
{
	[super update:delta_t];
	_timePassed += delta_t;
	
	rotMatrix = OOMatrixForBillboard(position, [PLAYER position]);
	
	GLfloat tf = _timePassed / kQuiriumCascadeDuration;
	GLfloat stf = tf * tf;
	GLfloat expansionSpeed = 0.0;
	if (_timePassed > 0)	// Avoid divide by 0
	{
		expansionSpeed = fmin(240.0f + 10.0f / (tf * tf), 1000.0f);
	}
	
	velocity.z = expansionSpeed;	// What's this for? Velocity is never applied. -- Ahruman 2011-02-05
	
	collision_radius += delta_t * expansionSpeed;		// expand
	energy = delta_t * (100000 - 90000 * tf);	// adjusted to take into account delta_t
	
	_color[3] = OOClamp_0_1_f(0.5f * ((0.025f / tf) + 1.0f - stf));
	
	_color[0] = _color[1] = fmin(1.0f - 5.0f * tf, 1.0f);
	if (_color[0] < 0.0f)
	{
		_color[0] = 0.25f * tf * randf();
		_color[1] = 0.0f;
	}
	
	// manage collisions
	Entity *owner = [self owner];
	Entity *e = nil;
	foreach (e, collidingEntities)
	{
		[e takeEnergyDamage:energy from:self becauseOf:owner];
	}
	
	// expire after ttl
	if (_timePassed > kQuiriumCascadeDuration)
	{
		[UNIVERSE removeEntity:self];
	}
}


- (void) drawEntity:(BOOL)immediate :(BOOL)translucent
{
	if (!translucent || [UNIVERSE breakPatternHide])  return;
	
	OO_ENTER_OPENGL();
	
	OOGL(glPushAttrib(GL_ENABLE_BIT | GL_COLOR_BUFFER_BIT));
	
	OOGL(glDisable(GL_CULL_FACE));
	OOGL(glDisable(GL_TEXTURE_2D));
	OOGL(glEnable(GL_BLEND));
	OOGL(glBlendFunc(GL_SRC_ALPHA, GL_ONE));
	
	OOGL(glColor4fv(_color));
	OOGLBEGIN(GL_TRIANGLE_FAN);
		GLDrawBallBillboard(collision_radius, 4, sqrt(cam_zero_distance));
	OOGLEND();
	
	OOGL(glPopAttrib());
	
	CheckOpenGLErrors(@"OOQuiriumCascadeEntity after drawing %@", self);
}


- (BOOL) isEffect
{
	return YES;
}


- (BOOL) isCascadeWeapon
{
	return YES;
}


- (BOOL) canCollide
{
	return _timePassed > kQuiriumCollisionDelay;
}


- (BOOL) checkCloseCollisionWith:(Entity *)other
{
	return YES;
}

@end


@implementation Entity (OOQuiriumCascadeExtensions)

- (BOOL) isCascadeWeapon
{
	return NO;
}

@end
