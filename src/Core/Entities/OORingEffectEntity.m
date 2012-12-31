/*

OORingEffectEntity.m


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

#import "OORingEffectEntity.h"
#import "Universe.h"
#import "OOMacroOpenGL.h"


#define kRingDuration					(2.0f)	// seconds
#define kRingAttack						(0.4f)	// fade-up time

// Dimensions and growth rates per second in terms of base size.
#define kInnerRingInitialSizeFactor		(0.5f)
#define kOuterRingInitialSizeFactor		(1.25f * kInnerRingInitialSizeFactor)
#define kInnerRingGrowthRateFactor		(1.1f * kInnerRingInitialSizeFactor)
#define kOuterRingGrowthRateFactor		(1.25f * kInnerRingInitialSizeFactor)

// These factors produce a ring that shrinks to nothing, then expands to the size of a "normal" ring.
#define kShrinkingRingInnerGrowthFactor	(-2.5)
#define kShrinkingRingOuterGrowthFactor	(-2.0)


enum
{
	kCircleSegments					= 65
};
static NSPoint sCircleVerts[kCircleSegments];	// holds vector coordinates for a unit circle


@implementation OORingEffectEntity

+ (void)initialize
{
	unsigned			i;
	for (i = 0; i < kCircleSegments; i++)
	{
		sCircleVerts[i].x = sin(i * 2 * M_PI / (kCircleSegments - 1));
		sCircleVerts[i].y = cos(i * 2 * M_PI / (kCircleSegments - 1));
	}
}


- (id) initRingFromEntity:(Entity *)sourceEntity
{
	if (sourceEntity == nil)
	{
		[self release];
		return nil;
	}
	
	if ((self = [super init]))
	{
		GLfloat baseSize = [sourceEntity collisionRadius];
		_innerRadius = baseSize * kInnerRingInitialSizeFactor;
		_outerRadius = baseSize * kOuterRingInitialSizeFactor;
		_innerGrowthRate = baseSize * kInnerRingGrowthRateFactor;
		_outerGrowthRate = baseSize * kOuterRingGrowthRateFactor;
		
		[self setPosition:[sourceEntity position]];
		[self setOrientation:[sourceEntity orientation]];
		[self setVelocity:[sourceEntity velocity]];
		
		[self setStatus:STATUS_EFFECT];
		[self setScanClass:CLASS_NO_DRAW];
		
		[self setOwner:sourceEntity];
	}
	
	return self;
}


+ (instancetype) ringFromEntity:(Entity *)sourceEntity
{
	return [[[self alloc] initRingFromEntity:sourceEntity] autorelease];
}


+ (instancetype) shrinkingRingFromEntity:(Entity *)sourceEntity
{
	OORingEffectEntity *result = [self ringFromEntity:sourceEntity];
	if (result != nil)
	{
		result->_innerGrowthRate *= kShrinkingRingInnerGrowthFactor;
		result->_outerGrowthRate *= kShrinkingRingOuterGrowthFactor;
	}
	return result;
}


- (NSString *) descriptionComponents
{
	return [NSString stringWithFormat:@"%f seconds passed of %f", _timePassed, kRingDuration];
}


- (void) update:(OOTimeDelta) delta_t
{
	[super update:delta_t];
	_timePassed += delta_t;
	
	_innerRadius += delta_t * _innerGrowthRate;
	_outerRadius += delta_t * _outerGrowthRate;
	
	if (_timePassed > kRingDuration)
	{
		[UNIVERSE removeEntity:self];
	}
}


- (void) drawImmediate:(bool)immediate translucent:(bool)translucent
{
	if (!translucent || [UNIVERSE breakPatternHide])  return;
	
	OO_ENTER_OPENGL();
	OOSetOpenGLState(OPENGL_STATE_ADDITIVE_BLENDING);
	
	GLfloat alpha = OOClamp_0_1_f((kRingDuration - _timePassed) / kRingAttack);
	
	GLfloat ex_em_hi[4]		= {0.6, 0.8, 1.0, alpha};   // pale blue
	GLfloat ex_em_lo[4]		= {0.2, 0.0, 1.0, 0.0};		// purplish-blue-black
	
	OOGLBEGIN(GL_TRIANGLE_STRIP);
		for (unsigned i = 0; i < kCircleSegments; i++)
		{
			glColor4fv(ex_em_lo);
			glVertex3f(_innerRadius * sCircleVerts[i].x, _innerRadius * sCircleVerts[i].y, 0.0f);
			glColor4fv(ex_em_hi);
			glVertex3f(_outerRadius * sCircleVerts[i].x, _outerRadius * sCircleVerts[i].y, 0.0f);
		}
	OOGLEND();
	
	OOVerifyOpenGLState();
	OOCheckOpenGLErrors(@"OOQuiriumCascadeEntity after drawing %@", self);
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
