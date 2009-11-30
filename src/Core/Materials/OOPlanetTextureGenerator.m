/*

OOPlanetTextureGenerator.m

Generator for planet diffuse maps.


Oolite
Copyright (C) 2004-2009 Giles C Williams and contributors

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

#import "OOPlanetTextureGenerator.h"
#import "OOCollectionExtractors.h"
#import "OOColor.h"
#import "OOTexture.h"


enum
{
	kNoiseBufferSize		= 128
};


static FloatRGB FloatRGBFromDictColor(NSDictionary *dictionary, NSString *key);

static void FillNoiseBuffer(float *noiseBuffer, RANROTSeed seed);
static void AddNoise(float *buffer, unsigned width, unsigned height, unsigned octave, float scale, const float *noiseBuffer);

float QFactor(float *accbuffer, int x, int y, unsigned width, unsigned height, float polar_y_value, float impress, float bias);

static FloatRGB PlanetMix(float q, float impress, float seaBias, FloatRGB landColor, FloatRGB seaColor, FloatRGB paleLandColor, FloatRGB paleSeaColor);


@implementation OOPlanetTextureGenerator

- (id) initWithPlanetInfo:(NSDictionary *)planetInfo
{
	if ((self = [super init]))
	{
		_landFraction = OOClamp_0_1_f([planetInfo oo_floatForKey:@"land_fraction" defaultValue:0.3]);
		_landColor = FloatRGBFromDictColor(planetInfo, @"land_color");
		_seaColor = FloatRGBFromDictColor(planetInfo, @"sea_color");
		_polarLandColor = FloatRGBFromDictColor(planetInfo, @"polar_land_color");
		_polarSeaColor = FloatRGBFromDictColor(planetInfo, @"polar_sea_color");
		_seed = RANROTGetFullSeed();
		
		_width = _height = 512;
	}
	
	return self;
}


+ (OOTexture *) planetTextureWithInfo:(NSDictionary *)planetInfo
{
	OOTexture *result = nil;
	OOPlanetTextureGenerator *generator = [[self alloc] initWithPlanetInfo:planetInfo];
	if (generator != nil)
	{
		result = [OOTexture textureWithGenerator:generator];
		[generator release];
	}
	
	return result;
}


- (NSString *) descriptionComponents
{
	return [NSString stringWithFormat:@"seed: %u,%u", _seed.high, _seed.low];
}


- (uint32_t) textureOptions
{
	return [super textureOptions] | kOOTextureRepeatS | kOOTextureNoShrink;
}


- (NSString *) cacheKey
{
	return [NSString stringWithFormat:@"OOPlanetTextureGenerator-base\n\n%u,%u/%u,%u/%f,%f,%f/%f,%f,%f/%f,%f,%f/%f,%f,%f",
			_width, _height, _seed.high, _seed.low,
			_landColor.r, _landColor.g, _landColor.b,
			_seaColor.r, _seaColor.g, _seaColor.b,
			_polarLandColor.r, _polarLandColor.g, _polarLandColor.b,
			_polarSeaColor.r, _polarSeaColor.g, _polarSeaColor.b];
}


- (BOOL)getResult:(void **)outData
		   format:(OOTextureDataFormat *)outFormat
			width:(uint32_t *)outWidth
		   height:(uint32_t *)outHeight
{
	BOOL waiting = NO;
	if (![self isReady])
	{
		waiting = true;
		OOLog(@"planetTex.temp", @"Waiting for generator %@", self);
	}
	
	BOOL result = [super getResult:outData format:outFormat width:outWidth height:outHeight];
	
	if (waiting)
	{
		OOLog(@"planetTex.temp", @"%s generator %@", result ? "Dequeued" : "Failed to dequeue", self);
	}
	else
	{
		OOLog(@"planetTex.temp", @"%s generator %@ without waiting.", result ? "Dequeued" : "Failed to dequeue", self);
	}
	
	return result;
}


static FloatRGB PlanetMix(float q, float impress, float seaBias, FloatRGB landColor, FloatRGB seaColor, FloatRGB polarLandColor, FloatRGB polarSeaColor);


- (void) loadTexture
{
	OOLog(@"planetTex.temp", @"Started generator %@", self);
	
	BOOL success = NO;
	
	uint8_t		*buffer = NULL, *px;
	float		*accBuffer = NULL;
	float		*randomBuffer = NULL;
	
	width = _width;
	height = _height;
	float seaBias = 1.0 - _landFraction;
	
	buffer = malloc(4 * width * height);
	if (buffer == NULL)  goto END;
	px = buffer;
	
	accBuffer = calloc(sizeof (float), width * height);
	if (accBuffer == NULL)  goto END;
	
	randomBuffer = calloc(sizeof (float), kNoiseBufferSize * kNoiseBufferSize);
	if (randomBuffer == NULL)  goto END;
	FillNoiseBuffer(randomBuffer, _seed);
	
	// Generate basic Perlin noise.
	unsigned octave = 8;
	float scale = 0.5f;
	while (octave < height)
	{
		AddNoise(accBuffer, width, height, octave, scale, randomBuffer);
		octave *= 2;
		scale *= 0.5;
	}
	
	float impress = 1.0f;
	float poleValue = (impress + seaBias > 0.5f) ? 0.5f * (impress + seaBias) : 0.0f;
	
	unsigned x, y;
	for (y = 0; y < height; y++)
	{
		for (x = 0; x < width; x++)
		{
			float q = QFactor(accBuffer, x, y, width, height, poleValue, impress, seaBias);
			
			// FIXME: is it worth calculating this per point in a separate pass instead of calculating each value five times?
			float yN = QFactor(accBuffer, x, y - 1, width, height, poleValue, impress, seaBias);
			float yS = QFactor(accBuffer, x, y + 1, width, height, poleValue, impress, seaBias);
			float yW = QFactor(accBuffer, x - 1, y, width, height, poleValue, impress, seaBias);
			float yE = QFactor(accBuffer, x + 1, y, width, height, poleValue, impress, seaBias);
			
			Vector norm = vector_normal(make_vector(24.0f * (yW - yE), 24.0f * (yS - yN), 2.0f));
			
			// FIXME: powf() is very expensive, can we use an approximation or change exponent to 3.0?
			GLfloat shade = powf(norm.z, 3.2);
			
			FloatRGB color = PlanetMix(q, impress, seaBias, _landColor, _seaColor, _polarLandColor, _polarSeaColor);
			
			*px++ = 255 * color.r * shade;
			*px++ = 255 * color.g * shade;
			*px++ = 255 * color.b * shade;
			*px++ = 255;
		}
	}
	success = YES;
	format = kOOTextureDataRGBA;
	
END:
	free(accBuffer);
	free(randomBuffer);
	if (success)  data = buffer;
	else  free(buffer);
	
	OOLog(@"planetTex.temp", @"Completed generator %@ %@successfully", self, success ? @"" : @"un");
}

@end


static FloatRGB Blend(float fraction, FloatRGB a, FloatRGB b)
{
	float prime = 1.0f - fraction;
	
	return (FloatRGB)
	{
		fraction * a.r + prime * b.r,
		fraction * a.g + prime * b.g,
		fraction * a.b + prime * b.b
	};
}


static FloatRGB PlanetMix(float q, float impress, float seaBias, FloatRGB landColor, FloatRGB seaColor, FloatRGB paleLandColor, FloatRGB paleSeaColor)
{
	float maxq = impress + seaBias;
	
	float hi = 0.66667 * maxq;
	float oh = 1.0 / hi;
	float ih = 1.0 / (1.0 - hi);
	
	const FloatRGB white = { 1.0f, 1.0f, 1.0f };
	
	if (q <= 0.0f)  return seaColor;
	if (q > 1.0)  return white;
	
	if (q < 0.01)  return Blend(q * 100.0f, landColor, paleSeaColor);	// Coastline
	
	if (q > hi)  return Blend((q - hi) * ih, white, paleLandColor);	// Snow-capped peaks
	
	return Blend((hi - q) * oh, landColor, paleLandColor);
}


static FloatRGB FloatRGBFromDictColor(NSDictionary *dictionary, NSString *key)
{
	OOColor *color = [dictionary objectForKey:key];
	NSCAssert1([color isKindOfClass:[OOColor class]], @"Expected OOColor, got %@", [color class]);
	
	return (FloatRGB){ [color redComponent], [color greenComponent], [color blueComponent] };
}


static void FillNoiseBuffer(float *noiseBuffer, RANROTSeed seed)
{
	NSCParameterAssert(noiseBuffer != NULL);
	
	unsigned i;
	for (i = 0; i < kNoiseBufferSize * kNoiseBufferSize; i++)
	{
		noiseBuffer[i] = randfWithSeed(&seed);
	}
}


static float lerp(float v0, float v1, float q)
{
	return v0 + q * (v1 - v0);
}


static void AddNoise(float *buffer, unsigned width, unsigned height, unsigned octave, float scale, const float *noiseBuffer)
{
	unsigned x, y;
	float r = (float)height / (float)octave;
	
	for (y = 0; y < height; y++)
	{
		for (x = 0; x < width; x++)
		{
			// FIXME: do this with less float/int conversions.
			int ix = floor( (float)x / r);
			int jx = (ix + 1) % octave;
			int iy = floor( (float)y / r);
			int jy = (iy + 1) % octave;
			float qx = x / r - ix;
			float qy = y / r - iy;
			ix &= 127;
			iy &= 127;
			jx &= 127;
			jy &= 127;
			float rix = lerp( noiseBuffer[iy * kNoiseBufferSize + ix], noiseBuffer[iy * kNoiseBufferSize + jx], qx);
			float rjx = lerp( noiseBuffer[jy * kNoiseBufferSize + ix], noiseBuffer[jy * kNoiseBufferSize + jx], qx);
			float rfinal = scale * lerp( rix, rjx, qy);
			
			buffer[ y * width + x ] += rfinal;
		}
	}
}


float QFactor(float *accbuffer, int x, int y, unsigned width, unsigned height, float polar_y_value, float impress, float bias)
{
	x = (x + height) % height;
	// FIXME: wrong wrapping mode for Y, should flip to other hemisphere.
	y = (y + width) % width;
	
	float q = accbuffer[y * width + x];	// 0.0 -> 1.0
	
	q = q * impress + bias;
	
	// Polar Y smooth. FIXME: float/int conversions.
	float polar_y = (2.0f * y - width) / (float) width;
	polar_y *= polar_y;
	q = q * (1.0 - polar_y) + polar_y * polar_y_value;
	
	q = OOClamp_0_1_f(q);
	
	return q;
}
