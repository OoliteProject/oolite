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
#import "OOLightParticleEntity.h"


//	Testing toy: cause particle systems to stop after half a second.
#define FREEZE_PARTICLES	0


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
	
	unsigned	i, count = _count;
	Vector		*particlePosition = _particlePosition;
	Vector		*particleVelocity = _particleVelocity;
	
	for (i = 0; i < count; i++)
	{
		particlePosition[i] = vector_add(particlePosition[i], vector_multiply_scalar(particleVelocity[i], delta_t));
	}
	
	// disappear eventually.
	if (_timePassed > _duration)  [UNIVERSE removeEntity:self];
}


OOINLINE void DrawQuadForView(GLfloat x, GLfloat y, GLfloat z, GLfloat sz)
{
	glTexCoord2f(0.0, 1.0);	glVertex3f(x-sz, y-sz, z);
	glTexCoord2f(1.0, 1.0);	glVertex3f(x+sz, y-sz, z);
	glTexCoord2f(1.0, 0.0);	glVertex3f(x+sz, y+sz, z);
	glTexCoord2f(0.0, 0.0);	glVertex3f(x-sz, y+sz, z);
}


- (void) drawEntity:(BOOL)immediate :(BOOL)translucent
{
	if (!translucent || [UNIVERSE breakPatternHide])  return;
	
	OOGL(glPushAttrib(GL_ENABLE_BIT | GL_COLOR_BUFFER_BIT));
	
	OOGL(glEnable(GL_TEXTURE_2D));
	[[OOLightParticleEntity defaultParticleTexture] apply];
	OOGL(glEnable(GL_BLEND));
	OOGL(glBlendFunc(GL_SRC_ALPHA, GL_ONE));
	
	OOMatrix bbMatrix = OOMatrixForBillboard(position, [PLAYER position]);
	// FIXME: use GL point sprites.
	
	unsigned	i, count = _count;
	Vector		*particlePosition = _particlePosition;
	GLfloat		(*particleColor)[4] = _particleColor;
	GLfloat		*particleSize = _particleSize;
	
	if ([UNIVERSE reducedDetail])
	{
		OOGL(glPushMatrix());
		GLMultOOMatrix(bbMatrix);
		
		OOGLBEGIN(GL_QUADS);
		for (i = 0; i < count; i++)
		{
			glColor4fv(particleColor[i]);
			DrawQuadForView(particlePosition[i].x, particlePosition[i].y, particlePosition[i].z, particleSize[i]);
		}
		OOGLEND();
		
		OOGL(glPopMatrix());
	}
	else
	{
		for (i = 0; i < count; i++)
		{
			OOGL(glPushMatrix());
			GLTranslateOOVector(particlePosition[i]);
			GLMultOOMatrix(bbMatrix);
			
			glColor4fv(particleColor[i]);
			OOGLBEGIN(GL_QUADS);
				DrawQuadForView(0, 0, 0, particleSize[i]);
			OOGLEND();
			
			OOGL(glPopMatrix());
		}
	}
	
	OOGL(glPopAttrib());
	
	CheckOpenGLErrors(@"OOParticleSystem after drawing %@", self);
}


- (BOOL) isEffect
{
	return YES;
}


#ifndef NDEBUG
- (NSSet *) allTextures
{
	return [NSSet setWithObject:[OOLightParticleEntity defaultParticleTexture]];
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
			_particleSize[i] = 32.0f * kMinSpeed / _particleSize[i];
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
#if FREEZE_PARTICLES
	if (_timePassed + delta_t > 0.5) delta_t = 0.5 - _timePassed;
#endif
	
	[super update:delta_t];
	
	unsigned	i, count = _count;
	GLfloat		(*particleColor)[4] = _particleColor;
	GLfloat		timePassed = _timePassed;
	
	for (i = 0; i < count; i++)
	{
		GLfloat du = 0.5f + (1.0f/32.0f) * (32 - i);
		particleColor[i][3] = OOClamp_0_1_f(1.0f - timePassed / du);
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
	
	size *= 2.0f;	 // Account for margins in particle texture.
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
#if FREEZE_PARTICLES
	if (_timePassed + delta_t > 0.5) delta_t = 0.5 - _timePassed;
#endif
	
	[super update:delta_t];
	
	unsigned	i, count = _count;
	GLfloat		(*particleColor)[4] = _particleColor;
	GLfloat		*particleSize = _particleSize;
	GLfloat		timePassed = _timePassed;
	GLfloat		duration = _duration;
	
	GLfloat size = (1.0f + timePassed) * _baseSize;
	GLfloat di = 1.0f / (count - 1);
	
	for (i = 0; i < count; i++)
	{
		GLfloat du = duration * (0.5 + di * i);
		particleColor[i][3] = OOClamp_0_1_f(1.0f - timePassed / du);
		
		particleSize[i] = size;
	}
}

@end
