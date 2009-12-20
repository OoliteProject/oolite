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


#define DEBUG_DUMP			(	0	&& !defined(NDEBUG))
#define DEBUG_DUMP_RAW		(	0	&& DEBUG_DUMP)

// Hermite interpolation provides continuous normals, at a cost of about 35 % slower rendering.
#define HERMITE					1


#import "OOPlanetTextureGenerator.h"
#import "OOCollectionExtractors.h"

#ifndef TEXGEN_TEST_RIG
#import "OOColor.h"
#import "OOTexture.h"
#import "Universe.h"
#endif

#if DEBUG_DUMP
#import "MyOpenGLView.h"
#endif


#define PLANET_TEXTURE_OPTIONS	(kOOTextureMinFilterLinear | kOOTextureMagFilterLinear | kOOTextureRepeatS | kOOTextureNoShrink)


enum
{
	kNoiseBufferSize		= 128
};


@interface OOPlanetTextureGenerator (Private)

- (NSString *) cacheKeyForType:(NSString *)type;
- (OOTextureGenerator *) normalMapGenerator;	// Must be called before generator is enqueued for rendering.

#if DEBUG_DUMP_RAW
- (void) dumpNoiseBuffer:(float *)noise;
#endif

@end



/*	The planet generator actually generates two textures when shaders are
	active, but the texture loader interface assumes we only load/generate
	one texture per loader. Rather than complicate that, we use a mock
	generator for the normal/light map.
*/
@interface OOPlanetNormalMapGenerator: OOTextureGenerator
{
@private
	NSString				*_cacheKey;
	RANROTSeed				_seed;
}

- (id) initWithCacheKey:(NSString *)cacheKey seed:(RANROTSeed)seed;

- (void) completeWithData:(void *)data width:(unsigned)width height:(unsigned)height;

@end


static int heightMask, widthMask;

static FloatRGB FloatRGBFromDictColor(NSDictionary *dictionary, NSString *key);

static void FillNoiseBuffer(float *noiseBuffer, RANROTSeed seed);
static void AddNoise(float *buffer, unsigned width, unsigned height, float octave, unsigned octaveMask, float scale, const float *noiseBuffer);

static float QFactor(float *accbuffer, int x, int y, unsigned width, unsigned height, float rHeight, float polar_y_value, float bias);

static FloatRGB Blend(float fraction, FloatRGB a, FloatRGB b);
//static FloatRGBA PolarMix(float q, float maxQ, FloatRGB cloudColor, float alpha);
static FloatRGBA PlanetMix(float q, float maxQ, FloatRGB landColor, FloatRGB seaColor, FloatRGB paleLandColor, FloatRGB paleSeaColor);


enum
{
	kPlanetAspectRatio			= 1,		// Ideally, aspect ratio would be 2:1 - keeping it as 1:1 for now - Kaks 20091211
	kPlanetScaleOffset			= 8 - kPlanetAspectRatio,
	
	kPlanetScale256x256			= 1,
	kPlanetScale512x512,
	kPlanetScale1024x1024,
	kPlanetScale2048x2048,
	kPlanetScale4096x4096,
	
	kPlanetScaleReducedDetail	= kPlanetScale512x512,
	kPlanetScaleFullDetail		= kPlanetScale1024x1024
};


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
		[[planetInfo objectForKey:@"noise_map_seed"] getValue:&_seed];
		
#ifndef TEXGEN_TEST_RIG
		if ([UNIVERSE reducedDetail])
		{
			_planetScale = kPlanetScaleReducedDetail;
		}
		else
		{
			_planetScale = kPlanetScaleFullDetail;
		}
#else
		_planetScale = kPlanetScale4096x4096;
#endif
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


+ (BOOL) generatePlanetTexture:(OOTexture **)texture secondaryTexture:(OOTexture **)secondaryTexture withInfo:(NSDictionary *)planetInfo
{
	NSParameterAssert(texture != NULL);
	
	OOPlanetTextureGenerator *diffuseGen = [[[self alloc] initWithPlanetInfo:planetInfo] autorelease];
	if (diffuseGen == nil)  return NO;
	
	if (secondaryTexture != NULL)
	{
		OOTextureGenerator *normalGen = [diffuseGen normalMapGenerator];
		if (normalGen == nil)  return NO;
		
		*secondaryTexture = [OOTexture textureWithGenerator:normalGen];
		if (*secondaryTexture == nil)  return NO;
	}
	
	*texture = [OOTexture textureWithGenerator:diffuseGen];
	
	return *texture != nil;
}


- (void) dealloc
{
	DESTROY(_nMapGenerator);
	
	[super dealloc];
}


- (NSString *) descriptionComponents
{
	return [NSString stringWithFormat:@"seed: %u,%u", _seed.high, _seed.low];
}


- (uint32_t) textureOptions
{
	return PLANET_TEXTURE_OPTIONS;
}


- (NSString *) cacheKey
{
	return [self cacheKeyForType:(_nMapGenerator == nil) ? @"diffuse-baked" : @"diffuse-raw"];
}


- (NSString *) cacheKeyForType:(NSString *)type
{
	return [NSString stringWithFormat:@"OOPlanetTextureGenerator-%@@%u\n%u,%u/%g/%u,%u/%f,%f,%f/%f,%f,%f/%f,%f,%f/%f,%f,%f",
			type, _planetScale,
			width, height, _landFraction, _seed.high, _seed.low,
			_landColor.r, _landColor.g, _landColor.b,
			_seaColor.r, _seaColor.g, _seaColor.b,
			_polarLandColor.r, _polarLandColor.g, _polarLandColor.b,
			_polarSeaColor.r, _polarSeaColor.g, _polarSeaColor.b];
}


- (OOTextureGenerator *) normalMapGenerator
{
	if (_nMapGenerator == nil)
	{
		_nMapGenerator = [[OOPlanetNormalMapGenerator alloc] initWithCacheKey:[self cacheKeyForType:@"normal"] seed:_seed];
	}
	return _nMapGenerator;
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
		OOLog(@"planetTex.temp", @"%s generator %@", "Waiting for", self);
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


- (void) loadTexture
{
	OOLog(@"planetTex.temp", @"Started generator %@", self);
	
	BOOL success = NO;
	BOOL generateNormalMap = (_nMapGenerator != nil);
	
	uint8_t		*buffer = NULL, *px = NULL;
	uint8_t		*nBuffer = NULL, *npx = NULL;
	float		*accBuffer = NULL;
	float		*randomBuffer = NULL;
	
	height = 1 << (_planetScale + kPlanetScaleOffset);
	width = height * kPlanetAspectRatio;
	heightMask = height - 1;
	widthMask = width - 1;
	
	buffer = malloc(4 * width * height);
	if (buffer == NULL)  goto END;
	px = buffer;
	
	if (generateNormalMap)
	{
		nBuffer = malloc(4 * width * height);
		if (nBuffer == NULL)  goto END;
		npx = nBuffer;
	}
	
	accBuffer = calloc(sizeof (float), width * height);
	if (accBuffer == NULL)  goto END;
	
	randomBuffer = calloc(sizeof (float), kNoiseBufferSize * kNoiseBufferSize);
	if (randomBuffer == NULL)  goto END;
	FillNoiseBuffer(randomBuffer, _seed);
	
	// Generate basic Perlin noise.
	unsigned octaveMask = 8 * kPlanetAspectRatio;
	float octave = octaveMask;
	octaveMask -= 1;
	float scale = 0.5f;
	while ((octaveMask + 1) < height)
	{
		// AddNoise() still accounts for about 50 % of rendering time.
		AddNoise(accBuffer, width, height, octave, octaveMask, scale, randomBuffer);
		octave *= 2.0f;
		octaveMask = (octaveMask << 1) | 1;
		scale *= 0.5f;
	}
	free(randomBuffer);
	randomBuffer = NULL;
	
#if DEBUG_DUMP_RAW
	[self dumpNoiseBuffer:accBuffer];
#endif
	
	float poleValue = (_landFraction > 0.5f) ? 0.5f * _landFraction : 0.0f;
	float seaBias = _landFraction - 1.0;
	
	/*	The system key 'polar_sea_colour' is used here as 'paleSeaColour'.
		While most polar seas would be covoered in ice, and therefore white,
		paleSeaColour doesn't seem  to take latitutde into account, resulting
		in all coastal areas to be white, or whatever defined as polar sea
		colours.
		For now, I'm overriding paleSeaColour to be pale blend of sea and land,
		and widened the shallows.
		TODO: investigate the use of polar land colour for the sea at higher latitudes.
		-- Kaks
	*/
	
	FloatRGB paleSeaColor = Blend(0.45, _polarSeaColor, Blend(0.7, _seaColor, _landColor));
	float normalScale = 1 << _planetScale;
	if (!generateNormalMap)  normalScale *= 3.0f;
	
	unsigned x, y;
	FloatRGBA color;
	Vector norm;
	float q, yN, yS, yW, yE;
	GLfloat shade;
	float rHeight = 1.0f / height;
	
	for (y = 0; y < height; y++)
	{
		for (x = 0; x < width; x++)
		{
			q = QFactor(accBuffer, x, y, width, height, rHeight, poleValue, seaBias);
			
			/*	FIXME: is it worth calculating this per point in a separate
				pass instead of calculating each value five times? (QFactor()
				accounts for 25 % to 30 % of rendering time.)
				Also, splitting the loop to handle the poleFactor = 0 case
				separately would greatly simplify QFactor in that case.
				-- Ahruman
			 */
			yN = QFactor(accBuffer, x, y - 1, width, height, rHeight, poleValue, seaBias);
			yS = QFactor(accBuffer, x, y + 1, width, height, rHeight, poleValue, seaBias);
			yW = QFactor(accBuffer, x - 1, y, width, height, rHeight, poleValue, seaBias);
			yE = QFactor(accBuffer, x + 1, y, width, height, rHeight, poleValue, seaBias);
			
			color = PlanetMix(q, _landFraction, _landColor, _seaColor, _polarLandColor, paleSeaColor);
			
			norm = vector_normal(make_vector(normalScale * (yW - yE), normalScale * (yS - yN), 1.0f));
			if (generateNormalMap)
			{
				shade = 1.0f;
				
				// Flatten in the sea.
				norm = OOVectorInterpolate(norm, kBasisZVector, color.a);
				
				// Put norm in normal map, scaled from [-1..1] to [0..255].
				*npx++ = 127.5f * (norm.y + 1.0f);
				*npx++ = 127.5f * (-norm.x + 1.0f);
				*npx++ = 127.5f * (norm.z + 1.0f);
				
				*npx++ = 255.0f * color.a;	// Specular channel.
			}
			else
			{
				/*	Terrain shading
					was: _powf(norm.z, 3.2). Changing exponent to 3 makes very
					little difference, other than being faster.
					
					FIXME: need to work out a decent way to scale this with texture
					size, so overall darkness is constant. Should probably be based
					on normalScale.
					-- Ahruman
				*/
				shade = norm.z * norm.z * norm.z;
				
				/*	We don't want terrain shading in the sea. The alpha channel
					of color is a measure of "seaishness" for the specular map,
					so we can recycle that to avoid branching.
					-- Ahruman
				*/
				shade = color.a + (1.0f - color.a) * shade;
			}
			
			*px++ = 255.0f * color.r * shade;
			*px++ = 255.0f * color.g * shade;
			*px++ = 255.0f * color.b * shade;
			
			*px++ = 0;	// FIXME: light map goes here.
		}
	}
	
	success = YES;
	format = kOOTextureDataRGBA;
	
END:
	free(accBuffer);
	free(randomBuffer);
	if (success)
	{
		data = buffer;
		[_nMapGenerator completeWithData:nBuffer width:width height:height];
	}
	else
	{
		free(buffer);
		free(nBuffer);
	}
	DESTROY(_nMapGenerator);
	
	OOLog(@"planetTex.temp", @"Completed generator %@ %@successfully", self, success ? @"" : @"un");
	
#if DEBUG_DUMP
	if (success)
	{
		NSString *diffuseName = [NSString stringWithFormat:@"planet-%u-%u-diffuse-new", _seed.high, _seed.low];
		NSString *lightsName = [NSString stringWithFormat:@"planet-%u-%u-lights-new", _seed.high, _seed.low];
		
		[[UNIVERSE gameView] dumpRGBAToRGBFileNamed:diffuseName
								   andGrayFileNamed:lightsName
											  bytes:buffer
											  width:width
											 height:height
										   rowBytes:width * 4];
	}
#endif
}


#if DEBUG_DUMP_RAW

- (void) dumpNoiseBuffer:(float *)noise
{
	NSString *noiseName = [NSString stringWithFormat:@"planet-%u-%u-noise-new", _seed.high, _seed.low];
	
	uint8_t *noiseMap = malloc(width * height);
	unsigned x, y;
	for (y = 0; y < height; y++)
	{
		for (x = 0; x < width; x++)
		{
			noiseMap[y * width + x] = 255.0f * noise[y * width + x];
		}
	}
	
	[[UNIVERSE gameView] dumpGrayToFileNamed:noiseName
									   bytes:noiseMap
									   width:width
									  height:height
									rowBytes:width];
	free(noiseMap);
}

#endif

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


static FloatRGBA PlanetMix(float q, float maxQ, FloatRGB landColor, FloatRGB seaColor, FloatRGB paleLandColor, FloatRGB paleSeaColor)
{
	float hi = 0.66667f * maxQ;
	float oh = 1.0f / hi;
	float ih = 1.0f / (1.0f - hi);
	
#define RECIP_COASTLINE_PORTION		(160.0f)
#define COASTLINE_PORTION			(1.0f / RECIP_COASTLINE_PORTION)
#define SHALLOWS					(2.0f * COASTLINE_PORTION)	// increased shallows area.
#define RECIP_SHALLOWS				(1.0f / SHALLOWS)
	
	const FloatRGB white = { 1.0f, 1.0f, 1.0f };
	FloatRGB diffuse;
	float specular = 0.0f;
	
#if !HERMITE
	// Offset to reduce coastline-lowering effect of r2823 coastline smoothing improvement.
	q -= COASTLINE_PORTION;
#endif
	
	if (q <= 0.0f)
	{
		// Below datum - sea.
		if (q > -SHALLOWS)
		{
			// Coastal waters.
			diffuse = Blend(-q * RECIP_SHALLOWS, seaColor, paleSeaColor);
		}
		else
		{
			// Open sea.
			diffuse = seaColor;
		}
		specular = 1.0f;
	}
	else if (q < COASTLINE_PORTION)
	{
		// Coastline.
		diffuse = Blend(q * RECIP_COASTLINE_PORTION, landColor, paleSeaColor);
		specular = (1.0f - (q * RECIP_COASTLINE_PORTION));
	//	specular = specular * specular * specular;
	}
	else if (q > 1.0f)
	{
		// High up - snow-capped peaks.
		diffuse = white;
	}
	else if (q > hi)
	{
		diffuse = Blend((q - hi) * ih, white, paleLandColor);	// Snowline.
	}
	else
	{
		// Normal land.
		diffuse = Blend((hi - q) * oh, landColor, paleLandColor);
	}
	
	return (FloatRGBA){ diffuse.r, diffuse.g, diffuse.b, specular };
}


static FloatRGB FloatRGBFromDictColor(NSDictionary *dictionary, NSString *key)
{
	OOColor *color = [dictionary objectForKey:key];
	NSCAssert1([color isKindOfClass:[OOColor class]], @"Expected OOColor, got %@", [color class]);
	
	return (FloatRGB){ [color redComponent], [color greenComponent], [color blueComponent] };
}


#if 1
static void FillNoiseBuffer(float *noiseBuffer, RANROTSeed seed)
{
	NSCParameterAssert(noiseBuffer != NULL);
	
	unsigned i;
	for (i = 0; i < kNoiseBufferSize * kNoiseBufferSize; i++)
	{
		noiseBuffer[i] = randfWithSeed(&seed);
	}
}
#else
// Inlining RANROT has no appreciable performance effect; AddNoise dominates.
static void FillNoiseBuffer(float *noiseBuffer, RANROTSeed seed)
{
	NSCParameterAssert(noiseBuffer != NULL);
	
	unsigned i;
	uint32_t high = seed.high, low = seed.low;
	const float scale = 1.0f / 65536.0f;
	
	for (i = 0; i < kNoiseBufferSize * kNoiseBufferSize; i++)
	{
		// Inline RANROT
		high = (high << 16) + (high >> 16);
		high += low;
		low += high;
		float val = (high & 0xffff) * scale;
		
		noiseBuffer[i] = val;
	}
}
#endif


OOINLINE float Lerp(float v0, float v1, float q)
{
	return v0 + q * (v1 - v0);
}


#if HERMITE
OOINLINE float Hermite(float q)
{
	return 3.0f * q * q - 2.0f * q * q * q;
}
#endif


static void AddNoise(float *buffer, unsigned width, unsigned height, float octave, unsigned octaveMask, float scale, const float *noiseBuffer)
{
	unsigned x, y;
	float rr = octave / width;
	float *dst = buffer;
	float fx, fy;
	
	for (fy = 0, y = 0; y < height; fy++, y++)
	{
		for (fx = 0, x = 0; x < width; fx++, x++)
		{
			// FIXME: do this with less float/int conversions.
			int ix = fx * rr;	// FLOAT->INT
			int jx = (ix + 1) & octaveMask;
			int iy = fy  * rr;	// FLOAT->INT
			int jy = (iy + 1) & octaveMask;
			float qx = fx * rr - ix;
			float qy = fy * rr - iy;
			ix &= (kNoiseBufferSize - 1);
			iy &= (kNoiseBufferSize - 1);
			jx &= (kNoiseBufferSize - 1);
			jy &= (kNoiseBufferSize - 1);
			
#if HERMITE
			qx = Hermite(qx);
			qy = Hermite(qy);
#endif
			
			float rix = Lerp(noiseBuffer[iy * kNoiseBufferSize + ix], noiseBuffer[iy * kNoiseBufferSize + jx], qx);
			float rjx = Lerp(noiseBuffer[jy * kNoiseBufferSize + ix], noiseBuffer[jy * kNoiseBufferSize + jx], qx);
			float rfinal = scale * Lerp(rix, rjx, qy);
			
			*dst++ += rfinal;
		}
	}
}


static float QFactor(float *accbuffer, int x, int y, unsigned width, unsigned height, float rHeight, float polar_y_value, float bias)
{
	// Correct Y wrapping mode, unoptimised.
	//if (y < 0) { y = -y; x += width / 2; }
	//else if (y >= height) { y -= y + 1  - height; x += width / 2; }

	// Correct Y wrapping mode, faster method. In the following lines of code, both
	// width and height are assumed to be powers of 2: 512, 1024, 2048, etc...
	if (y & height) { y = (y ^ heightMask) & heightMask; x += width >> 1; }
	x &= widthMask;
	
	float q = accbuffer[y * width + x];	// 0.0 -> 1.0
	q += bias;
	
	// Polar Y smooth.
	float polar_y = (2.0f * y - height) * rHeight;
	polar_y *= polar_y;
	q = q * (1.0f - polar_y) + polar_y * polar_y_value;
	
	return q;
}


@implementation OOPlanetNormalMapGenerator

- (id) initWithCacheKey:(NSString *)cacheKey seed:(RANROTSeed)seed
{
	if ((self = [super init]))
	{
		_cacheKey = [cacheKey copy];
		_seed = seed;
	}
	return self;
}


- (void) dealloc
{
	DESTROY(_cacheKey);
	
	[super dealloc];
}


- (NSString *) cacheKey
{
	return _cacheKey;
}


- (uint32_t) textureOptions
{
	return PLANET_TEXTURE_OPTIONS;
}


- (BOOL) enqueue
{
	/*	This generator doesn't do any work, so it doesn't need to be queued
		at the normal time.
		(The alternative would be for it to block a work thread waiting for
		the real generator to complete, which seemed silly.)
	*/
	return YES;
}


- (void) loadTexture
{
	// Do nothing.
}


- (void) completeWithData:(void *)data_ width:(unsigned)width_ height:(unsigned)height_
{
	data = data_;
	width = width_;
	height = height_;
	format = kOOTextureDataRGBA;
	
	// Enqueue so superclass can apply texture options and so forth.
	[super enqueue];
	
#if DEBUG_DUMP
	NSString *normalName = [NSString stringWithFormat:@"planet-%u-%u-normal-new", _seed.high, _seed.low];
	NSString *specularName = [NSString stringWithFormat:@"planet-%u-%u-specular-new", _seed.high, _seed.low];
	
	[[UNIVERSE gameView] dumpRGBAToRGBFileNamed:normalName
							   andGrayFileNamed:specularName
										  bytes:data
										  width:width
										 height:height
									   rowBytes:width * 4];
#endif
}

@end
