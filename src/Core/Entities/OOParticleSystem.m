/*

OOParticleSystem.m

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

#import "OOParticleSystem.h"

#import "Universe.h"
#import "OOTexture.h"
#import "PlayerEntity.h"


static void DrawQuadForView(GLfloat x, GLfloat y, GLfloat z, GLfloat xx, GLfloat yy);


@implementation OOParticleSystem

- (id) init
{
	[self release];
	return nil;
}


/*	Initialize shared aspects of the fragburst entities.
	Also stashes generated particle speeds in _particleSize[] array.
*/
- (id) initWithPosition:(Vector)pos
			   velocity:(Vector)vel
				  count:(unsigned)count
			   minSpeed:(unsigned)minSpeed
			   maxSpeed:(unsigned)maxSpeed
			   duration:(OOTimeDelta)duration
			  baseColor:(GLfloat[4])baseColor
{
	NSParameterAssert(count <= kFragmentBurstMaxParticles);
	
	if ((self = [super init]))
	{
		_count = count;
		position = pos;
		velocity = vel;
		_duration = duration;
		_texture = [[OOTexture textureWithName:@"blur256.png" inFolder:@"Textures"] retain];
		
		for (unsigned i = 0; i < count; i++)
		{
			GLfloat speed = minSpeed + 0.5f * (randf()+randf()) * (maxSpeed - minSpeed);	// speed tends toward middle of range
			_particleVelocity[i] = vector_multiply_scalar(OORandomUnitVector(), speed);
			
			Vector color = make_vector(baseColor[0] * 0.1f * (9.5f + randf()), baseColor[1] * 0.1f * (9.5f + randf()), baseColor[2] * 0.1f * (9.5f + randf()));
			color = vector_normal(color);
			_particleColor[i][0] = color.x;
			_particleColor[i][1] = color.y;
			_particleColor[i][2] = color.z;
			_particleColor[i][3] = baseColor[3];
			
			_particleSize[i] = speed;
		}
		
		[self setStatus:STATUS_EFFECT];
		scanClass = CLASS_NO_DRAW;
	}
	
	return self;
}


- (void) dealloc
{
	[_texture release];
	
	[super dealloc];
}


- (NSString *) descriptionComponents
{
	return [NSString stringWithFormat:@"ttl: %.3fs", _duration - _timePassed];
}


- (BOOL) canCollide
{
	return NO;
}


- (BOOL) checkCloseCollisionWith:(Entity *)other
{
	if (other == [self owner])  return NO;
	return ![other isEffect];
}


- (void) update:(OOTimeDelta) delta_t
{
	[super update:delta_t];
	_timePassed += delta_t;
	
	/*	Rotate entire system towards camera. This looks odd if the player can
		move perpendicularly and observer the particles, but in short
		explosions it's hard to notice.
	*/
	rotMatrix = [PLAYER drawRotationMatrix];
	
	// disappear eventually.
	if (_timePassed > _duration)  [UNIVERSE removeEntity:self];
}


- (void) drawEntity:(BOOL)immediate :(BOOL)translucent
{
	if (!translucent || [UNIVERSE breakPatternHide])  return;
	
	OOGL(glPushAttrib(GL_ENABLE_BIT | GL_COLOR_BUFFER_BIT));
	
	if (translucent)
	{
		OOGL(glEnable(GL_TEXTURE_2D));
		[_texture apply];
		OOGL(glEnable(GL_BLEND));
		OOGL(glBlendFunc(GL_SRC_ALPHA, GL_ONE));
		
		// FIXME: use GL point sprites.
		OOGLBEGIN(GL_QUADS);
		for (unsigned i = 0; i < _count; i++)
		{
			glColor4fv(_particleColor[i]);
			DrawQuadForView(_particlePosition[i].x, _particlePosition[i].y, _particlePosition[i].z, _particleSize[i], _particleSize[i]);
		}
		OOGLEND();
	}
	
	OOGL(glPopAttrib());
	
	CheckOpenGLErrors(@"OOParticleSystem after drawing %@", self);
}


static void DrawQuadForView(GLfloat x, GLfloat y, GLfloat z, GLfloat xx, GLfloat yy)
{
	int viewdir = [UNIVERSE viewDirection];

	switch (viewdir)
	{
		case VIEW_FORWARD:
			glTexCoord2f(0.0, 1.0);	glVertex3f(x-xx, y-yy, z);
			glTexCoord2f(1.0, 1.0);	glVertex3f(x+xx, y-yy, z);
			glTexCoord2f(1.0, 0.0);	glVertex3f(x+xx, y+yy, z);
			glTexCoord2f(0.0, 0.0);	glVertex3f(x-xx, y+yy, z);
		case	VIEW_AFT:
			glTexCoord2f(0.0, 1.0);	glVertex3f(x+xx, y-yy, z);
			glTexCoord2f(1.0, 1.0);	glVertex3f(x-xx, y-yy, z);
			glTexCoord2f(1.0, 0.0);	glVertex3f(x-xx, y+yy, z);
			glTexCoord2f(0.0, 0.0);	glVertex3f(x+xx, y+yy, z);
			break;
		case	VIEW_STARBOARD:
			glTexCoord2f(0.0, 1.0);	glVertex3f(x, y-yy, z+xx);
			glTexCoord2f(1.0, 1.0);	glVertex3f(x, y-yy, z-xx);
			glTexCoord2f(1.0, 0.0);	glVertex3f(x, y+yy, z-xx);
			glTexCoord2f(0.0, 0.0);	glVertex3f(x, y+yy, z+xx);
			break;
		case	VIEW_PORT:
			glTexCoord2f(0.0, 1.0);	glVertex3f(x, y-yy, z-xx);
			glTexCoord2f(1.0, 1.0);	glVertex3f(x, y-yy, z+xx);
			glTexCoord2f(1.0, 0.0);	glVertex3f(x, y+yy, z+xx);
			glTexCoord2f(0.0, 0.0);	glVertex3f(x, y+yy, z-xx);
			break;
		case	VIEW_CUSTOM:
		{
			PlayerEntity *player = PLAYER;
			Vector vi = [player customViewRightVector];		vi.x *= xx;	vi.y *= xx;	vi.z *= xx;
			Vector vj = [player customViewUpVector];		vj.x *= yy;	vj.y *= yy;	vj.z *= yy;
			glTexCoord2f(0.0, 1.0);	glVertex3f(x - vi.x - vj.x, y - vi.y - vj.y, z - vi.z - vj.z);
			glTexCoord2f(1.0, 1.0);	glVertex3f(x + vi.x - vj.x, y + vi.y - vj.y, z + vi.z - vj.z);
			glTexCoord2f(1.0, 0.0);	glVertex3f(x + vi.x + vj.x, y + vi.y + vj.y, z + vi.z + vj.z);
			glTexCoord2f(0.0, 0.0);	glVertex3f(x - vi.x + vj.x, y - vi.y + vj.y, z - vi.z + vj.z);
			break;
		}
		default:
			glTexCoord2f(0.0, 1.0);	glVertex3f(x-xx, y-yy, z);
			glTexCoord2f(1.0, 1.0);	glVertex3f(x+xx, y-yy, z);
			glTexCoord2f(1.0, 0.0);	glVertex3f(x+xx, y+yy, z);
			glTexCoord2f(0.0, 0.0);	glVertex3f(x-xx, y+yy, z);
			break;
	}
}


- (BOOL) isEffect
{
	return YES;
}


#ifndef NDEBUG
- (NSSet *) allTextures
{
	if (_texture)
	{
		return [NSSet setWithObject:_texture];
	}
	else
	{
		return nil;
	}
}
#endif

@end


@implementation OOSmallFragmentBurstEntity: OOParticleSystem

- (id) initFragmentBurstFrom:(Vector)fragPosition size:(GLfloat)size
{
	enum
	{
		kMinSpeed = 100, kMaxSpeed = 400
	};
	
	unsigned count = 0.4f * size;
	count = MIN(count | 12, (unsigned)kFragmentBurstMaxParticles);
	
	// Select base colour
	// yellow/orange (0.12) through yellow (0.1667) to yellow/slightly green (0.20)
	OOColor *hsvColor = [OOColor colorWithCalibratedHue:0.12 + 0.08 * randf() saturation:1.0 brightness:1.0 alpha:1.0];
	GLfloat baseColor[4];
	[hsvColor getGLRed:&baseColor[0] green:&baseColor[1] blue:&baseColor[2] alpha:&baseColor[3]];
	
	if ((self = [super initWithPosition:fragPosition velocity:kZeroVector count:count minSpeed:kMinSpeed maxSpeed:kMaxSpeed duration:1.5 baseColor:baseColor]))
	{
		for (unsigned i = 0; i < count; i++)
		{
			// Note: initWithPosition:... stashes speeds in _particleSize[].
			_particleSize[i] = 16.0f * kMinSpeed / _particleSize[i];
		}
	}
	
	return self;
}


+ (id) fragmentBurstFrom:(Vector)fragPosition size:(GLfloat)size
{
	return [[[self alloc] initFragmentBurstFrom:fragPosition size:size] autorelease];
}


- (void) update:(OOTimeDelta) delta_t
{
	[super update:delta_t];
	
	for (unsigned i = 0; i < _count; i++)
	{
		GLfloat du = 0.5f + (1.0f/32.0f) * (32 - i);
		_particleColor[i][3] = OOClamp_0_1_f(1.0f - _timePassed / du);
		
		_particlePosition[i] = vector_add(_particlePosition[i], vector_multiply_scalar(_particleVelocity[i], delta_t));
	}
}

@end


@implementation OOBigFragmentBurstEntity: OOParticleSystem

- (id) initFragmentBurstFrom:(Vector)fragPosition size:(GLfloat)size
{
	unsigned minSpeed = 1 + size * 0.5f;
	unsigned maxSpeed = minSpeed * 4;
	
	unsigned count = 0.2f * size;
	count = MIN(count | 3, (unsigned)kBigFragmentBurstMaxParticles);
	
	GLfloat baseColor[4] = { 1.0, 1.0, 0.5, 1.0 };
	
	if ((self = [super initWithPosition:fragPosition velocity:kZeroVector count:count minSpeed:minSpeed maxSpeed:maxSpeed duration:1.0 baseColor:baseColor]))
	{
		_baseSize = size;
		
		for (unsigned i = 0; i < count; i++)
		{
			_particleSize[i] = size;
		}
	}
	
	return self;
}


+ (id) fragmentBurstFrom:(Vector)fragPosition size:(GLfloat)size
{
	return [[[self alloc] initFragmentBurstFrom:fragPosition size:size] autorelease];
}


- (void) update:(double)delta_t
{
	[super update:delta_t];
	
	GLfloat size = (1.0f + _timePassed) * _baseSize;
	GLfloat di = 1.0f / (_count - 1);
	
	for (unsigned i = 0; i < _count; i++)
	{
		GLfloat du = _duration * (0.5 + di * i);
		_particleColor[i][3] = OOClamp_0_1_f(1.0f - _timePassed / du);
		
		_particlePosition[i] = vector_add(_particlePosition[i], vector_multiply_scalar(_particleVelocity[i], delta_t));
		_particleSize[i] = size;
	}
}

@end
