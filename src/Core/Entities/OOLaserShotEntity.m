/*

OOLaserShotEntity.m


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

#import "OOLaserShotEntity.h"
#import "Universe.h"
#import "ShipEntity.h"
#import "OOMacroOpenGL.h"

#import "OOTexture.h"
#import "OOGraphicsResetManager.h"


#define kLaserDuration		(0.09)	// seconds

// Default colour
#define kLaserRed			(1.0f)
#define kLaserGreen			(0.0f)
#define kLaserBlue			(0.0f)

// Constant alpha
#define kLaserAlpha			(0.45f)

#define kLaserCoreWidth		(0.4f)
#define kLaserFlareWidth		(1.8f)
#define kLaserHalfWidth		(3.6f)

static OOTexture *sShotTexture = nil;
static OOTexture *sShotTexture2 = nil;

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
		[self setPosition:HPvector_add([ship position], vectorToHPVector(OOVectorMultiplyMatrix(offset, [ship drawRotationMatrix])))];
	}
	else
	{
		// subentity laser
		[self setPosition:[srcEntity absolutePositionForSubentityOffset:vectorToHPVector(middle)]];
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
			break;
			
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
	
	_color[0] = kLaserRed/3.0;
	_color[1] = kLaserGreen/3.0;
	_color[2] = kLaserBlue/3.0;
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
	_color[0] = [color redComponent]/3.0;
	_color[1] = [color greenComponent]/3.0;
	_color[2] = [color blueComponent]/3.0;
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
		/*
			Reposition this shot accurately. This overrides integration over
			velocity in -[Entity update:], which is considered sufficient for
			NPC ships.
		*/
		[self setPosition:HPvector_add([ship position], vectorToHPVector(OOVectorMultiplyMatrix(_offset, [ship drawRotationMatrix])))];
		[self setOrientation:quaternion_multiply(_relOrientation, [ship normalOrientation])];
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
	 0.0f, -1.0f, 0.0f,
};


- (void) drawImmediate:(bool)immediate translucent:(bool)translucent
{
	if (!translucent || [UNIVERSE breakPatternHide])  return;
	
	OO_ENTER_OPENGL();
	OOSetOpenGLState(OPENGL_STATE_ADDITIVE_BLENDING);
	

	/*	FIXME: spread damage across the lifetime of the shot,
		hurting whatever is hit in a given frame.
		-- Ahruman 2011-01-31
	*/
	OOGL(glEnableClientState(GL_TEXTURE_COORD_ARRAY));
	OOGL(glEnable(GL_TEXTURE_2D));
	OOGL(glPushMatrix());
	
	[[self texture1] apply];
	GLfloat s = sin([UNIVERSE getTime]);
	GLfloat phase = s*(_range/200.0);
	GLfloat phase2 = (1.0+s)*(_range/200.0);
	GLfloat phase3 = -s*(_range/500.0);
	GLfloat phase4 = -(1.0+s)*(_range/500.0);

	GLfloat laserTexCoords[] = 
		{
			0.0f, phase,	0.0f, phase2,	1.0f, phase2,	1.0f, phase,

			0.0f, phase,	0.0f, phase2,	1.0f, phase2,	1.0f, phase
		};
	GLfloat laserTexCoords2[] = 
		{
			0.0f, phase3,	0.0f, phase4,	1.0f, phase4,	1.0f, phase3,

			0.0f, phase3,	0.0f, phase4,	1.0f, phase4,	1.0f, phase3
		};
	
	OOGL(glColor4fv(_color));
	glScaled(kLaserHalfWidth, kLaserHalfWidth, _range);
	glVertexPointer(3, GL_FLOAT, 0, kLaserVertices);
	glTexCoordPointer(2, GL_FLOAT, 0, laserTexCoords2);
	glDrawArrays(GL_QUADS, 0, 8);
	
	glScaled(kLaserCoreWidth / kLaserHalfWidth, kLaserCoreWidth / kLaserHalfWidth, 1.0);
	OOGL(glColor4f(1.0,1.0,1.0,0.9));
	glDrawArrays(GL_QUADS, 0, 8);

	[[self texture2] apply];
	glScaled(kLaserFlareWidth / kLaserCoreWidth, kLaserFlareWidth / kLaserCoreWidth, 1.0);
	OOGL(glColor4f(_color[0],_color[1],_color[2],0.9));
	glTexCoordPointer(2, GL_FLOAT, 0, laserTexCoords);
	glDrawArrays(GL_QUADS, 0, 8);
	
	OOGL(glPopMatrix());
	OOGL(glDisableClientState(GL_TEXTURE_COORD_ARRAY));
	OOGL(glDisable(GL_TEXTURE_2D));
	
	OOVerifyOpenGLState();
	OOCheckOpenGLErrors(@"OOLaserShotEntity after drawing %@", self);
}


- (BOOL) isEffect
{
	return YES;
}


- (BOOL) canCollide
{
	return NO;
}

- (OOTexture *) texture1
{
	return [OOLaserShotEntity outerTexture];
}


- (OOTexture *) texture2
{
	return [OOLaserShotEntity innerTexture];
}


+ (void) setUpTexture
{
	if (sShotTexture == nil)
	{
		sShotTexture = [[OOTexture textureWithName:@"oolite-laser-blur.png"
										  inFolder:@"Textures"
										   options:kOOTextureMinFilterMipMap | kOOTextureMagFilterLinear | kOOTextureAlphaMask | kOOTextureRepeatT
										anisotropy:kOOTextureDefaultAnisotropy / 2.0
										   lodBias:0.0] retain];
		[[OOGraphicsResetManager sharedManager] registerClient:(id<OOGraphicsResetClient>)[OOLaserShotEntity class]];

		sShotTexture2 = [[OOTexture textureWithName:@"oolite-laser-blur2.png"
										  inFolder:@"Textures"
										   options:kOOTextureMinFilterMipMap | kOOTextureMagFilterLinear | kOOTextureAlphaMask | kOOTextureRepeatT
										anisotropy:kOOTextureDefaultAnisotropy / 2.0
										   lodBias:0.0] retain];
	}
}


+ (OOTexture *) innerTexture
{
	if (sShotTexture2 == nil)  [self setUpTexture];
	return sShotTexture2;
}


+ (OOTexture *) outerTexture
{
	if (sShotTexture == nil)  [self setUpTexture];
	return sShotTexture;
}


+ (void) resetGraphicsState
{
	[sShotTexture release];
	sShotTexture = nil;
	[sShotTexture2 release];
	sShotTexture2 = nil;
}


@end


