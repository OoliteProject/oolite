/*

OOExplosionCloudEntity.m


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

#import "OOExplosionCloudEntity.h"
#import "Universe.h"
#import "PlayerEntity.h"
#import "OOColor.h"
#import "OOTexture.h"
#import "OOGraphicsResetManager.h"


#define kExplosionCloudDuration		0.9f
#define kGrowthRateFactor			1.5f
#define kExplosionCloudAlpha		0.85f

static OOTexture *sCloudTexture1 = nil;
static OOTexture *sCloudTexture2 = nil;


@interface OOExplosionCloudEntity (Private)

+ (void) resetGraphicsState;

@end


@implementation OOExplosionCloudEntity

- (id) initExplosionCloudWithPosition:(HPVector)pos velocity:(Vector)vel size:(float)size
{
	unsigned i;
	unsigned count = 25;
	GLfloat baseColor[4] = {1.0,1.0,1.0,1.0};
	_growthRate = kGrowthRateFactor * size;

	if (magnitude2(vel) > 1000000)
	{
		vel = vector_multiply_scalar(vector_normal(vel),1000);
	}

	if ((self = [super initWithPosition:pos velocity:vel count:count minSpeed:size*0.8 maxSpeed:size*1.2 duration:kExplosionCloudDuration baseColor:baseColor]))
	{
		for (i=0;i<count;i++) 
		{
			float r,g,b;
			r = randf();
			g = randf();
			if (g > r) {
				r = 1.0f;
			}
			b = randf();
			if (b > g) {
				b = g;
			}
			_particleColor[i][0] = r;
			_particleColor[i][1] = g;
			_particleColor[i][2] = b;
			_particleColor[i][3] = kExplosionCloudAlpha;
		}
	}
	return self;
}


+ (instancetype) explosionCloudFromEntity:(Entity *)entity
{
	return [[[self alloc] initExplosionCloudWithPosition:[entity position] velocity:[entity velocity] size:[entity collisionRadius]*2.5] autorelease];
}


+ (instancetype) explosionCloudFromEntity:(Entity *)entity withSize:(float)size
{
	return [[[self alloc] initExplosionCloudWithPosition:[entity position] velocity:[entity velocity] size:size] autorelease];
}


- (void) update:(OOTimeDelta)delta_t
{
	[super update:delta_t];
	
	// Fade out.
	unsigned	i, count = _count;
	GLfloat		(*particleColor)[4] = _particleColor;
	
	float newAlpha = kExplosionCloudAlpha * (1-(_timePassed / kExplosionCloudDuration));
	for (i=0;i<count;i++) {
		
		_particleSize[i] += delta_t * _growthRate;

		particleColor[i][3] = newAlpha;
		if (particleColor[i][2] > 0.0) // fade blue (white to yellow)
		{
			particleColor[i][2] -= delta_t/2.0;
			if (particleColor[i][2] < 0.0)
			{
				particleColor[i][2] = 0.0f;
			}
		}
		else if (particleColor[i][1] > 0.0) // fade green (yellow to red)
		{
			particleColor[i][1] -= delta_t;
			if (particleColor[i][1] < 0.0)
			{
				particleColor[i][1] = 0.0f;
			}
		}
		else if (particleColor[i][0] > 0.0) // fade red (red to black)
		{
			particleColor[i][0] -= delta_t*2.0;
			if (particleColor[i][0] < 0.0)
			{
				particleColor[i][0] = 0.0f;
			}
		}
	}
	
}


- (OOTexture *) texture
{
	// TODO: some way to vary cloud textures
	if (sCloudTexture2 == nil)  [OOExplosionCloudEntity	setUpTexture];
	return sCloudTexture2;
}


+ (void) setUpTexture
{
	if (sCloudTexture1 == nil)
	{
		sCloudTexture1 = [[OOTexture textureWithName:@"oolite-particle-cloud.png"
										   inFolder:@"Textures"
											options:kOOTextureMinFilterMipMap | kOOTextureMagFilterLinear | kOOTextureAlphaMask
										 anisotropy:kOOTextureDefaultAnisotropy
											lodBias:0.0] retain];
		sCloudTexture2 = [[OOTexture textureWithName:@"oolite-particle-cloud2.png"
										   inFolder:@"Textures"
											options:kOOTextureMinFilterMipMap | kOOTextureMagFilterLinear | kOOTextureAlphaMask
										 anisotropy:kOOTextureDefaultAnisotropy
											lodBias:0.0] retain];
		[[OOGraphicsResetManager sharedManager] registerClient:(id<OOGraphicsResetClient>)[OOExplosionCloudEntity class]];
	}
}


+ (void) resetGraphicsState
{
	[sCloudTexture1 release];
	sCloudTexture1 = nil;
	[sCloudTexture2 release];
	sCloudTexture2 = nil;
}

@end
