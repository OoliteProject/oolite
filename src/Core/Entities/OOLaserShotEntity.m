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

#import "MyOpenGLView.h"


#define kLaserDuration		(0.09)	// seconds

// Default colour
#define kLaserRed			(1.0f)
#define kLaserGreen			(0.0f)
#define kLaserBlue			(0.0f)

// With this defined we use the ACES tonemapper desaturation
// at high luminance for the brightest parts of the beam
#define OO_LASER_ACES_BASED	1

// Brightness - set to 1.0 for legacy laser appearance
// For legacy appearance also set OO_LASER_ACES_BASED to 0
#define kLaserBrightness	(5.0f)

// Constant alpha
#define kLaserAlpha			(0.45f / kLaserBrightness)

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
	[self setRange:[srcEntity weaponRange]];
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
	_color[0] = kLaserBrightness * [color redComponent]/3.0;
	_color[1] = kLaserBrightness * [color greenComponent]/3.0;
	_color[2] = kLaserBrightness * [color blueComponent]/3.0;
	// Ignore alpha; _color[3] is constant.
}


- (void) setRange:(GLfloat)range
{
	_range = range;
	[self setCollisionRadius:range];
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
	OOGLPushModelView();
	
	OOGLScaleModelView(make_vector(kLaserHalfWidth, kLaserHalfWidth, _range));
	[[self texture1] apply];
	GLfloat s = sinf([UNIVERSE getTime]);
	GLfloat phase = s*(_range/200.0f);
	GLfloat phase2 = (1.0f+s)*(_range/200.0f);
	GLfloat phase3 = -s*(_range/500.0f);
	GLfloat phase4 = -(1.0f+s)*(_range/500.0f);

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
	glVertexPointer(3, GL_FLOAT, 0, kLaserVertices);
	glTexCoordPointer(2, GL_FLOAT, 0, laserTexCoords2);
	glDrawArrays(GL_QUADS, 0, 8);
	
	OOGLScaleModelView(make_vector(kLaserCoreWidth / kLaserHalfWidth, kLaserCoreWidth / kLaserHalfWidth, 1.0));
#if OO_LASER_ACES_BASED
	// 80% core laser color, 20% brightness boost
	OOGL(glColor4f(_color[0] * 35.0 * 0.8 + kLaserBrightness * 0.2,
					_color[1] * 35.0 * 0.8 + kLaserBrightness * 0.2,
					_color[2] * 35.0 * 0.8 + kLaserBrightness * 0.2, 0.9));
#else
	OOGL(glColor4f(kLaserBrightness,kLaserBrightness,kLaserBrightness,0.9));
#endif
	glDrawArrays(GL_QUADS, 0, 8);

	[[self texture2] apply];
	OOGLScaleModelView(make_vector(kLaserFlareWidth / kLaserCoreWidth, kLaserFlareWidth / kLaserCoreWidth, 1.0));
	OOGL(glColor4f(_color[0],_color[1],_color[2],0.9));
	glTexCoordPointer(2, GL_FLOAT, 0, laserTexCoords);
	glDrawArrays(GL_QUADS, 0, 8);
	
	OOGLPopModelView();
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


