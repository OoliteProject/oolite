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
#import "OOCollectionExtractors.h"

#define kExplosionCloudDuration		0.9
#define kGrowthRateFactor			1.5f
#define kExplosionCloudAlpha		0.85f
#define kExplosionDefaultSize		2.5f

// keys for plist file
static NSString * const kExplosionAlpha			= @"alpha";
static NSString * const kExplosionColors		= @"color_order";
static NSString * const kExplosionCount			= @"count";
static NSString * const kExplosionDuration		= @"duration";
static NSString * const kExplosionGrowth		= @"growth_rate";
static NSString * const kExplosionSize			= @"size";
static NSString * const kExplosionSpread		= @"spread";
static NSString * const kExplosionTexture		= @"texture";


@interface OOExplosionCloudEntity (OOPrivate)
- (id) initExplosionCloudWithEntity:(Entity *)entity size:(float)size andSettings:(NSDictionary *)settings;
@end 

@implementation OOExplosionCloudEntity

- (id) initExplosionCloudWithEntity:(Entity *)entity size:(float)size andSettings:(NSDictionary *)settings
{
	unsigned i;
	unsigned maxCount = [UNIVERSE detailLevel] <= DETAIL_LEVEL_SHADERS ? 10 : 25;
	HPVector pos = [entity position];
	Vector vel = [entity velocity];

	if (settings == nil) {
		_settings = [[NSDictionary dictionary] retain];
	} else {
		_settings = [settings retain];
	}

	unsigned count = [_settings oo_unsignedIntegerForKey:kExplosionCount defaultValue:25];
	if (count > maxCount) {
		count = maxCount;
	}

	if (size == 0.0) {
		size = [entity collisionRadius]*[_settings oo_floatForKey:kExplosionSize defaultValue:kExplosionDefaultSize];
	}

	_growthRate = [_settings oo_floatForKey:kExplosionGrowth defaultValue:kGrowthRateFactor] * size;
	_alpha = [_settings oo_floatForKey:kExplosionAlpha defaultValue:kExplosionCloudAlpha];
	_cloudDuration = [_settings oo_doubleForKey:kExplosionDuration defaultValue:kExplosionCloudDuration];

	GLfloat spread = [_settings oo_floatForKey:kExplosionSpread defaultValue:1.0];

	NSString *textureFile = [_settings oo_stringForKey:kExplosionTexture defaultValue:@"oolite-particle-cloud2.png"];
	
	_texture = [[OOTexture textureWithName:textureFile
								  inFolder:@"Textures"
								   options:kOOTextureMinFilterMipMap | kOOTextureMagFilterLinear | kOOTextureAlphaMask
								anisotropy:kOOTextureDefaultAnisotropy
								   lodBias:0.0] retain];	
	if (_texture == nil) 
	{
		[self release];
		return nil;
	}

	GLfloat baseColor[4] = {1.0,1.0,1.0,1.0};

	if (magnitude2(vel) > 1000000)
	{
		// slow down rapidly translating explosions
		vel = vector_multiply_scalar(vector_normal(vel),1000);
	}

	if ((self = [super initWithPosition:pos velocity:vel count:count minSpeed:size*0.8f*spread maxSpeed:size*1.2f*spread duration:_cloudDuration baseColor:baseColor]))
	{
		NSString *color_order = [_settings oo_stringForKey:kExplosionColors defaultValue:@"rgb"];
		
		for (i=0;i<count;i++) 
		{
			if ([color_order isEqualToString:@"white"]) {
				// grey
				_particleColor[i][0] = _particleColor[i][1] = _particleColor[i][2] = randf();
			} else {
				float c1 = randf();
				float c2 = randf();
				float c3 = randf();
				if (c2 > c1) {
					c2 = c1;
				}
				if (c3 > c2) {
					c3 = c2;
				}
				if ([color_order isEqualToString:@"rgb"]) 
				{
					_particleColor[i][0] = c1;
					_particleColor[i][1] = c2;
					_particleColor[i][2] = c3;
				}
				else if ([color_order isEqualToString:@"rbg"]) 
				{
					_particleColor[i][0] = c1;
					_particleColor[i][1] = c3;
					_particleColor[i][2] = c2;
				}
				else if ([color_order isEqualToString:@"grb"]) 
				{
					_particleColor[i][0] = c2;
					_particleColor[i][1] = c1;
					_particleColor[i][2] = c3;
				}
				else if ([color_order isEqualToString:@"gbr"]) 
				{
					_particleColor[i][0] = c3;
					_particleColor[i][1] = c1;
					_particleColor[i][2] = c2;
				}
				else if ([color_order isEqualToString:@"brg"]) 
				{
					_particleColor[i][0] = c2;
					_particleColor[i][1] = c3;
					_particleColor[i][2] = c1;
				}
				else if ([color_order isEqualToString:@"bgr"]) 
				{
					_particleColor[i][0] = c3;
					_particleColor[i][1] = c2;
					_particleColor[i][2] = c1;
				}

			}

			_particleColor[i][3] = _alpha;
		}
	}
	return self;
}


- (void) dealloc 
{
	DESTROY(_texture);
	DESTROY(_settings);
	[super dealloc];
}


+ (instancetype) explosionCloudFromEntity:(Entity *)entity withSettings:(NSDictionary *)settings
{
	return [[[self alloc] initExplosionCloudWithEntity:entity size:0 andSettings:settings] autorelease];
}


+ (instancetype) explosionCloudFromEntity:(Entity *)entity withSize:(float)size andSettings:(NSDictionary *)settings
{
	return [[[self alloc] initExplosionCloudWithEntity:entity size:size andSettings:settings] autorelease];
}


- (void) update:(OOTimeDelta)delta_t
{
	[super update:delta_t];
	
	// Fade out.
	GLfloat		fadeRate = _count / 25.0;
	unsigned	i, count = _count;
	GLfloat		(*particleColor)[4] = _particleColor;
	
	float newAlpha = _alpha * (1-(_timePassed / _cloudDuration));
	NSString *color_order = [_settings oo_stringForKey:kExplosionColors defaultValue:@"rgb"];
	NSUInteger primary = 0, secondary = 1, tertiary = 2;
			
	if ([color_order isEqualToString:@"rgb"]) 
	{
		primary = 0;
		secondary = 1;
		tertiary = 2;
	}
	else if ([color_order isEqualToString:@"rbg"]) 
	{
		primary = 0;
		secondary = 2;
		tertiary = 1;
	}
	else if ([color_order isEqualToString:@"grb"]) 
	{
		primary = 1;
		secondary = 0;
		tertiary = 2;
	}
	else if ([color_order isEqualToString:@"gbr"]) 
	{
		primary = 1;
		secondary = 2;
		tertiary = 0;
	}
	else if ([color_order isEqualToString:@"brg"]) 
	{
		primary = 2;
		secondary = 0;
		tertiary = 1;
	}
	else if ([color_order isEqualToString:@"bgr"]) 
	{
		primary = 2;
		secondary = 1;
		tertiary = 0;
	}


	float fdelta_t = delta_t;
	for (i=0;i<count;i++) {
		
		_particleSize[i] += delta_t * _growthRate;

		particleColor[i][3] = newAlpha;
		if (![color_order isEqualToString:@"white"])
		{

			if (particleColor[i][tertiary] > 0.0f) // fade blue (white to yellow)
			{
				particleColor[i][tertiary] -= fdelta_t * 0.5f * fadeRate;
				if (particleColor[i][tertiary] < 0.0f)
				{
					particleColor[i][tertiary] = 0.0f;
				}
			}
			else if (particleColor[i][secondary] > 0.0f) // fade green (yellow to red)
			{
				particleColor[i][secondary] -= fdelta_t * fadeRate;
				if (particleColor[i][secondary] < 0.0f)
				{
					particleColor[i][secondary] = 0.0f;
				}
			}
			else if (particleColor[i][primary] > 0.0f) // fade red (red to black)
			{
				particleColor[i][primary] -= fdelta_t * 2.0f * fadeRate;
				if (particleColor[i][primary] < 0.0f)
				{
					particleColor[i][primary] = 0.0f;
				}
			}

		}
	}
	
}


- (OOTexture *) texture
{
	return _texture;
}

@end
