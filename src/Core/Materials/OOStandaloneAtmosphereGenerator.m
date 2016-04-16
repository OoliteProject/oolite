/*
	OOStandaloneAtmosphereGenerator.m
	
	Generator for atmosphere textures when the planet is using a
	non-generated diffuse map.
	
	
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

#import "OOStellarBody.h"

#if NEW_PLANETS


#define DEBUG_DUMP			(	0	&& !defined(NDEBUG))
#define DEBUG_DUMP_RAW		(	1	&& DEBUG_DUMP)

#define ALBEDO_FACTOR		0.7f	// Overall darkening of everything, allowing better contrast for snow and specular highlights.

#import "OOStandaloneAtmosphereGenerator.h"
#import "OOCollectionExtractors.h"
#import "OOColor.h"

#ifndef TEXGEN_TEST_RIG
#import "OOTexture.h"
#import "Universe.h"
#endif

#if DEBUG_DUMP
#import "MyOpenGLView.h"
#endif


#define FREE(x) do { if (0) { void *x__ = x; x__ = x__; } /* Preceeding is for type checking only. */ void **x_ = (void **)&(x); free(*x_); *x_ = NULL; } while (0)


#define PLANET_TEXTURE_OPTIONS	(kOOTextureMinFilterLinear | kOOTextureMagFilterLinear | kOOTextureRepeatS | kOOTextureNoShrink)


enum
{
	kRandomBufferSize		= 128
};


@interface OOStandaloneAtmosphereGenerator (Private)

#if DEBUG_DUMP_RAW
- (void) dumpNoiseBuffer:(float *)noise;
#endif

@end


static FloatRGB FloatRGBFromDictColor(NSDictionary *dictionary, NSString *key);

static BOOL FillFBMBuffer(OOStandaloneAtmosphereGeneratorInfo *info);
static float QFactor(float *accbuffer, int x, int y, unsigned width, float polar_y_value, float bias, float polar_y);
static float BlendAlpha(float fraction, float a, float b);
static FloatRGBA CloudMix(OOStandaloneAtmosphereGeneratorInfo *info, float q, float nearPole);


enum
{
#if PERLIN_3D && !TEXGEN_TEST_RIG
	kPlanetAspectRatio			= 2,
#else
	kPlanetAspectRatio			= 1,		// Ideally, aspect ratio would be 2:1 - keeping it as 1:1 for now - Kaks 20091211
#endif
	kPlanetScaleOffset			= 8 - kPlanetAspectRatio,
	
	kPlanetScale256x256			= 1,
	kPlanetScale512x512,
	kPlanetScale1024x1024,
	kPlanetScale2048x2048,
	kPlanetScale4096x4096,
	
	kPlanetScaleReducedDetail	= kPlanetScale512x512,
	kPlanetScaleFullDetail		= kPlanetScale1024x1024
};


@implementation OOStandaloneAtmosphereGenerator

- (id) initWithPlanetInfo:(NSDictionary *)planetInfo
{
	OOLog(@"texture.planet.generate", @"%@", @"Initialising standalone atmosphere generator");

	// AllowCubeMap not used yet but might be in future
	if ((self = [super initWithPath:[NSString stringWithFormat:@"OOStandaloneAtmosphereTexture@%p", self] options:kOOTextureAllowCubeMap]))
	{
		OOLog(@"texture.planet.generate",@"Extracting parameters for generator %@",self);
		[[planetInfo objectForKey:@"noise_map_seed"] getValue:&_info.seed];
		OOLog(@"texture.planet.generate", @"%@", @"Extracting atmosphere parameters");
		// we are an atmosphere:
		_info.cloudAlpha = [planetInfo oo_floatForKey:@"cloud_alpha" defaultValue:1.0f];
		_info.cloudFraction = OOClamp_0_1_f([planetInfo oo_floatForKey:@"cloud_fraction" defaultValue:0.3]);
		_info.cloudColor = FloatRGBFromDictColor(planetInfo, @"cloud_color");
		_info.paleCloudColor = FloatRGBFromDictColor(planetInfo, @"polar_cloud_color");
		
#ifndef TEXGEN_TEST_RIG
		if ([UNIVERSE detailLevel] < DETAIL_LEVEL_SHADERS)
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
	OOStandaloneAtmosphereGenerator *generator = [[self alloc] initWithPlanetInfo:planetInfo];
	if (generator != nil)
	{
		result = [OOTexture textureWithGenerator:generator];
		[generator release];
	}
	
	return result;
}


+ (BOOL) generateAtmosphereTexture:(OOTexture **)texture withInfo:(NSDictionary *)planetInfo
{
	NSParameterAssert(texture != NULL);
	
	OOStandaloneAtmosphereGenerator *atmoGen = [[[self alloc] initWithPlanetInfo:planetInfo] autorelease];
	if (atmoGen == nil)  return NO;
	
	*texture = [OOTexture textureWithGenerator:atmoGen];
	
	return *texture != nil;
}


- (void) dealloc
{
	[super dealloc];
}


- (NSString *) descriptionComponents
{
	return [NSString stringWithFormat:@"seed: %u,%u", _info.seed.high, _info.seed.low];
}


- (uint32_t) textureOptions
{
	return PLANET_TEXTURE_OPTIONS;
}


- (NSString *) cacheKey
{
	return [NSString stringWithFormat:@"OOStandaloneAtmosphereGenerator-@%u\n%u,%u/%u,%u/%f/%f/%f,%f,%f/%f,%f,%f/%f,%f,%f",
			_planetScale,
			_info.width, _info.height, _info.seed.high, _info.seed.low,
			_info.cloudAlpha, _info.cloudFraction,
			 _info.airColor.r, _info.airColor.g, _info.airColor.b,
			 _info.cloudColor.r, _info.cloudColor.g, _info.cloudColor.b,
			 _info.paleCloudColor.r, _info.paleCloudColor.g, _info.paleCloudColor.b					 
		];
}



- (BOOL)getResult:(OOPixMap *)outData
		   format:(OOTextureDataFormat *)outFormat
			width:(uint32_t *)outWidth
		   height:(uint32_t *)outHeight
{
	BOOL waiting = NO;
	if (![self isReady])
	{
		waiting = true;
		OOLog(@"texture.planet.generate.wait", @"%s generator %@", "Waiting for", self);
	}
	
	BOOL result = [super getResult:outData format:outFormat originalWidth:outWidth originalHeight:outHeight];
	
	if (waiting)
	{
		OOLog(@"texture.planet.generate.dequeue", @"%s generator %@", result ? "Dequeued" : "Failed to dequeue", self);
	}
	else
	{
		OOLog(@"texture.planet.generate.dequeue", @"%s generator %@ without waiting.", result ? "Dequeued" : "Failed to dequeue", self);
	}
	
	return result;
}

/* TODO: fix duplication between here and OOPlanetTextureGenerator of
 * various noise, interpolation, etc. functions */
- (void) loadTexture
{
	OOLog(@"texture.planet.generate.begin", @"Started generator %@", self);
	
	BOOL success = NO;
	
	uint8_t		*aBuffer = NULL, *apx = NULL;
	float		*randomBuffer = NULL;
	
	_height = _info.height = 1 << (_planetScale + kPlanetScaleOffset);
	_width = _info.width = _height * kPlanetAspectRatio;
	
#define FAIL_IF(cond)  do { if (EXPECT_NOT(cond))  goto END; } while (0)
#define FAIL_IF_NULL(x)  FAIL_IF((x) == NULL)
	
	aBuffer = malloc(4 * _width * _height);
	FAIL_IF_NULL(aBuffer);
	apx = aBuffer;
	
	FAIL_IF(!FillFBMBuffer(&_info));
#if DEBUG_DUMP_RAW
	[self dumpNoiseBuffer:_info.fbmBuffer];
#endif
	
	float paleClouds = (_info.cloudFraction * _info.fbmBuffer[0] < 1.0f - _info.cloudFraction) ? 0.0f : 1.0f;
	
	int x, y;
	FloatRGBA color;
	float q, nearPole;
	float rHeight = 1.0f / _height;
	float fy, fHeight = _height;
	
	float cloudFraction = _info.cloudFraction;
	
	for (y = (int)_height - 1, fy = (float)y; y >= 0; y--, fy--)
	{
		nearPole = (2.0f * fy - fHeight) * rHeight;
		nearPole *= nearPole;
		
		for (x = (int)_width - 1; x >= 0; x--)
		{
			q = QFactor(_info.fbmBuffer, x, y, _width, paleClouds, cloudFraction, nearPole);
			color = CloudMix(&_info, q, nearPole);
			*apx++ = 255.0f * color.r;
			*apx++ = 255.0f * color.g;
			*apx++ = 255.0f * color.b;
			*apx++ = 255.0f * color.a * _info.cloudAlpha;
		}
	}
	
	success = YES;
	_format = kOOTextureDataRGBA;
	
END:
	FREE(_info.fbmBuffer);
	FREE(randomBuffer);
	if (success)
	{
		_data = aBuffer;
	}
	else
	{
		FREE(aBuffer);
	}
	
	OOLog(@"texture.planet.generate.complete", @"Completed generator %@ %@successfully", self, success ? @"" : @"un");
	
#if DEBUG_DUMP
	if (success)
	{
		NSString *diffuseName = [NSString stringWithFormat:@"atmosphere-%u-%u-diffuse-new", _info.seed.high, _info.seed.low];
		NSString *lightsName = [NSString stringWithFormat:@"atmosphere-%u-%u-alpha-new", _info.seed.high, _info.seed.low];
		
		[[UNIVERSE gameView] dumpRGBAToRGBFileNamed:diffuseName
								   andGrayFileNamed:lightsName
											  bytes:aBuffer
											  width:_width
											 height:_height
										   rowBytes:_width * 4];
	}
#endif
}


#if DEBUG_DUMP_RAW

- (void) dumpNoiseBuffer:(float *)noise
{
	NSString *noiseName = [NSString stringWithFormat:@"atmosphere-%u-%u-noise-new", _info.seed.high, _info.seed.low];
	
	uint8_t *noisePx = malloc(_width * _height);
	unsigned x, y;
	for (y = 0; y < _height; y++)
	{
		for (x = 0; x < _width; x++)
		{
			noisePx[y * _width + x] = 255.0f * noise[y * _width + x];
		}
	}
	
	[[UNIVERSE gameView] dumpGrayToFileNamed:noiseName
									   bytes:noisePx
									   width:_width
									  height:_height
									rowBytes:_width];
	FREE(noisePx);
}

#endif

@end


OOINLINE float Lerp(float v0, float v1, float fraction)
{
	// Linear interpolation - equivalent to v0 * (1.0f - fraction) + v1 * fraction.
	return v0 + fraction * (v1 - v0);
}


static FloatRGB Blend(float fraction, FloatRGB a, FloatRGB b)
{
	return (FloatRGB)
	{
		Lerp(b.r, a.r, fraction),
		Lerp(b.g, a.g, fraction),
		Lerp(b.b, a.b, fraction)
	};
}


static float BlendAlpha(float fraction, float a, float b)
{
	return Lerp(b, a, fraction);
}


static FloatRGBA CloudMix(OOStandaloneAtmosphereGeneratorInfo *info, float q, float nearPole)
{
//#define AIR_ALPHA				(0.15f)
//#define CLOUD_ALPHA				(1.0f)
// CIM: make distinction between cloud and not-cloud bigger
#define AIR_ALPHA				(0.05f)
#define CLOUD_ALPHA				(2.0f)

#define POLAR_BOUNDARY			(0.33f)
#define CLOUD_BOUNDARY			(0.5f)
#define RECIP_CLOUD_BOUNDARY	(1.0f / CLOUD_BOUNDARY)

	FloatRGB cloudColor = info->cloudColor;
	float alpha = info->cloudAlpha, portion = 0.0f;
	
	q -= CLOUD_BOUNDARY * 0.5f;
	
	if (nearPole > POLAR_BOUNDARY)
	{
		portion = nearPole > POLAR_BOUNDARY + 0.2f ? 1.0f : (nearPole - POLAR_BOUNDARY) * 5.0f;
		cloudColor = Blend(portion, info->paleCloudColor, cloudColor);
		 
		portion = nearPole > POLAR_BOUNDARY + 0.625f ? 1.0f : (nearPole - POLAR_BOUNDARY) * 1.6f;
	}
	
	if (q <= 0.0f)
	{
		if (q >= -CLOUD_BOUNDARY)
		{
			alpha *= BlendAlpha(-q * 0.5f * RECIP_CLOUD_BOUNDARY + 0.5f, CLOUD_ALPHA, AIR_ALPHA);
		}
		else
		{
			alpha *= CLOUD_ALPHA;
		}
	}
	else
	{
		if (q < CLOUD_BOUNDARY)
		{
			alpha *= BlendAlpha( q * 0.5f * RECIP_CLOUD_BOUNDARY + 0.5f,  AIR_ALPHA,CLOUD_ALPHA);
		}
		else
		{
			alpha *= AIR_ALPHA;
		}
	}
	// magic numbers! at the poles we have fairly thin air.
	alpha *= BlendAlpha(portion, 0.6f, 1.0f);
	if (alpha > 1.0)
	{
		alpha = 1.0;
	}

	return (FloatRGBA){ cloudColor.r, cloudColor.g, cloudColor.b, alpha };
}


static FloatRGB FloatRGBFromDictColor(NSDictionary *dictionary, NSString *key)
{
	OOColor *color = [dictionary objectForKey:key];
	NSCAssert1([color isKindOfClass:[OOColor class]], @"Expected OOColor, got %@", [color class]);
	
	return (FloatRGB){ [color redComponent] * ALBEDO_FACTOR, [color greenComponent] * ALBEDO_FACTOR, [color blueComponent] * ALBEDO_FACTOR };
}


OOINLINE float Hermite(float q)
{
	return 3.0f * q * q - 2.0f * q * q * q;
}


#if __BIG_ENDIAN__
#define iman_ 1
#else
#define iman_ 0
#endif

 // (same behaviour as, but faster than, FLOAT->INT)
 //Works OK for -32728 to 32727.99999236688
OOINLINE int32_t fast_floor(double val)
{
   val += 68719476736.0 * 1.5;
   return (((int32_t*)&val)[iman_] >> 16);
}


static BOOL GenerateFBMNoise(OOStandaloneAtmosphereGeneratorInfo *info);


static BOOL FillFBMBuffer(OOStandaloneAtmosphereGeneratorInfo *info)
{
	NSCParameterAssert(info != NULL);
	
	// Allocate result buffer.
	info->fbmBuffer = calloc(info->width * info->height, sizeof (float));
	if (info->fbmBuffer != NULL)
	{
		GenerateFBMNoise(info);
	
		return YES;
	}
	return NO;
}


#if PERLIN_3D

enum
{
	//	Size of permutation buffer used to map integer coordinates to gradients. Must be power of two.
	kPermutationCount		= 1 << 10,
	kPermutationMask		= kPermutationCount - 1,
	
	// Number of different gradient vectors used. The most important thing is that the gradients are evenly distributed and sum to 0.
	kGradientCount			= 12
};


#define LUT_DOT	1


#if !LUT_DOT
static const Vector kGradients[kGradientCount] =
{
	{  1,  1,  0 },
	{ -1,  1,  0 },
	{  1, -1,  0 },
	{ -1, -1,  0 },
	{  1,  0,  1 },
	{ -1,  0,  1 },
	{  1,  0, -1 },
	{ -1,  0, -1 },
	{  0,  1,  1 },
	{  0, -1,  1 },
	{  0,  1, -1 },
	{  0, -1, -1 }
};
#else
static const uint8_t kGradients[kGradientCount][3] =
{
	{  2,  2,  1 },
	{  0,  2,  1 },
	{  2,  0,  1 },
	{  0,  0,  1 },
	{  2,  1,  2 },
	{  0,  1,  2 },
	{  2,  1,  0 },
	{  0,  1,  0 },
	{  1,  2,  2 },
	{  1,  0,  2 },
	{  1,  2,  0 },
	{  1,  0,  0 }
};


/*	Attempted speedup that didn't pan out, but might inspire something better.
	Since our gradient vectors' components are all -1, 0 or 1, we should be
	able to calculate the dot product without any multiplication at all, by
	simply summing the right combination of (x, y, z), (0, 0, 0) and (-x, -y, -z).
	
	This turns out to be slightly slower than using multiplication, even if
	the negations are precalculated.
*/
OOINLINE float TDot3(const uint8_t grad[3], float x, float y, float z)
{
	float xt[3] = { -x, 0.0f, x };
	float yt[3] = { -y, 0.0f, y };
	float zt[3] = { -z, 0.0f, z };
	
	return xt[grad[0]] + yt[grad[1]] + zt[grad[2]];
}
#endif


// Sample 3D noise function defined by kGradients and permutation table at point p.
static float SampleNoise3D(OOStandaloneAtmosphereGeneratorInfo *info, Vector p)
{
	uint16_t	*permutations = info->permutations;
	
	// Split coordinates into integer and fractional parts.
	float		fx = floor(p.x);
	float		fy = floor(p.y);
	float		fz = floor(p.z);
	int			X = fx;
	int			Y = fy;
	int			Z = fz;
	float		x = p.x - fx;
	float		y = p.y - fy;
	float		z = p.z - fz;
	
	// Select gradient for each corner.
#define PERM(v) permutations[(v) & kPermutationMask]
	
	unsigned PZ0 = PERM(Z);
	unsigned PZ1 = PERM(Z + 1);
	
	unsigned PY0Z0 = PERM(Y + PZ0);
	unsigned PY1Z0 = PERM(Y + 1 + PZ0);
	unsigned PY0Z1 = PERM(Y + PZ1);
	unsigned PY1Z1 = PERM(Y + 1 + PZ1);
	
	unsigned gi000 = PERM(X     + PY0Z0);
	unsigned gi010 = PERM(X     + PY1Z0);
	unsigned gi100 = PERM(X + 1 + PY0Z0);
	unsigned gi110 = PERM(X + 1 + PY1Z0);
	unsigned gi001 = PERM(X     + PY0Z1);
	unsigned gi011 = PERM(X     + PY1Z1);
	unsigned gi101 = PERM(X + 1 + PY0Z1);
	unsigned gi111 = PERM(X + 1 + PY1Z1);
	
#undef PERM
	
	//	Calculate noise contributions from each of the eight corners.
#if !LUT_DOT
#define DOT3(idx, x_, y_, z_)  dot_product(kGradients[(idx) % kGradientCount], (Vector){ (x_), (y_), (z_) })
#else
#define DOT3(idx, x_, y_, z_)  TDot3(kGradients[(idx) % kGradientCount], (x_), (y_), (z_))
#endif
	
	float x1 = x - 1.0f;
	float y1 = y - 1.0f;
	float z1 = z - 1.0f;
	float n000 = DOT3(gi000, x , y , z );
	float n010 = DOT3(gi010, x , y1, z );
	float n100 = DOT3(gi100, x1, y , z );
	float n110 = DOT3(gi110, x1, y1, z );
	float n001 = DOT3(gi001, x , y , z1);
	float n011 = DOT3(gi011, x , y1, z1);
	float n101 = DOT3(gi101, x1, y , z1);
	float n111 = DOT3(gi111, x1, y1, z1);
	
#undef DOT3
	
	// Compute the fade curve value for each of x, y, z
	float u = Hermite(x);
	float v = Hermite(y);
	float w = Hermite(z);
	
	// Interpolate along the contributions from each of the corners.
	float nx00 = Lerp(n000, n100, u);
	float nx01 = Lerp(n001, n101, u);
	float nx10 = Lerp(n010, n110, u);
	float nx11 = Lerp(n011, n111, u);
	
	float nxy0 = Lerp(nx00, nx10, v);
	float nxy1 = Lerp(nx01, nx11, v);
	
	float nxyz = Lerp(nxy0, nxy1, w);
	
	return nxyz;
}


/*	Generate shuffled permutation order - each value from 0 to
	kPermutationCount - 1 occurs exactly once. This shuffling provides all the
	randomness in the resulting noise. Don't worry, though - for
	kPermutationCount = 1024 this allows for 4e2567 different noise maps,
	which is a lot more than RanRot will actually give us.
*/
static BOOL MakePermutationTable(OOStandaloneAtmosphereGeneratorInfo *info)
{
	uint16_t *perms = malloc(sizeof *info->permutations * kPermutationCount);
	if (EXPECT_NOT(perms == NULL))  return NO;
	
	/*	Fisher-Yates/Durstenfeld/Knuth shuffle, "inside-out" variant.
		Based on pseudocode from http://en.wikipedia.org/wiki/Fisher-Yates_shuffle
		
		When comparing to the pseudocode, note that it generates a one-based
		series, but this version generates a zero-based series.
	*/
	perms[0] = 0;
	uint16_t *curr = perms;
	uint16_t n;
	for (n = 1; n < kPermutationCount; n++)
	{
		uint16_t j = RanrotWithSeed(&info->seed) & kPermutationMask;
		*++curr = perms[j];
		perms[j] = n - 1;
	}
	
	info->permutations = perms;
	return YES;
}


static BOOL GenerateFBMNoise(OOStandaloneAtmosphereGeneratorInfo *info)
{
	BOOL OK = NO;
	
	FAIL_IF(!MakePermutationTable(info));
	
	unsigned x, y, width = info->width, height = info->height;
	float lon, lat;	// Longitude and latitude in radians.
	float dlon = 2.0f * M_PI / width;
	float dlat = M_PI / height;
	float *px = info->fbmBuffer;
	
	for (y = 0, lat = -M_PI_2; y < height; y++, lat += dlat)
	{
		float las = sin(lat);
		float lac = cos(lat);
		
		for (x = 0, lon = -M_PI; x < width; x++, lon += dlon)
		{
			// FIXME: in real life, we really don't want sin and cos per pixel.
			// Convert spherical coordinates to vector.
			float los = sin(lon);
			float loc = cos(lon);
			
			Vector p =
			{
				los * lac,
				las,
				loc * lac
			};
			
#if 1
			// fBM
			unsigned octaveMask = 4;
			float octave = octaveMask;
			octaveMask -= 1;
			float scale = 0.4f;
			float sum = 0;
			
			while ((octaveMask + 1) < height)
			{
				Vector ps = vector_multiply_scalar(p, octave);
				sum += scale * SampleNoise3D(info, ps);
				
				octave *= 2.0f;
				octaveMask = (octaveMask << 1) | 1;
				scale *= 0.5f;
			}
#else
			// Single octave
			p = vector_multiply_scalar(p, 4.0f);
			float sum = 0.5f * SampleNoise3D(info, p);
#endif
			
			*px++ = sum + 0.5f;
		}
	}
	
END:
	FREE(info->permutations);
	return OK;
}

#else
// Old 2D value noise.

static void FillRandomBuffer(float *randomBuffer, RANROTSeed seed)
{
	unsigned i, len = kRandomBufferSize * kRandomBufferSize;
	for (i = 0; i < len; i++)
	{
		randomBuffer[i] = randfWithSeed(&seed);
	}
}


static void AddNoise(OOStandaloneAtmosphereGeneratorInfo *info, float *randomBuffer, float octave, unsigned octaveMask, float scale, float *qxBuffer, int *ixBuffer)
{
	unsigned	x, y;
	unsigned	width = info->width, height = info->height;
	int			ix, jx, iy, jy;
	float		rr = octave / width;
	float		fx, fy, qx, qy, rix, rjx, rfinal;
	float		*dst = info->fbmBuffer;
	
	for (fy = 0, y = 0; y < height; fy++, y++)
	{
		qy = fy * rr;
		iy = fast_floor(qy);
		jy = (iy + 1) & octaveMask;
		qy = Hermite(qy - iy);
		iy &= (kRandomBufferSize - 1);
		jy &= (kRandomBufferSize - 1);
		
		for (fx = 0, x = 0; x < width; fx++, x++)
		{
			if (y == 0)
			{
				// first pass: initialise buffers.
				qx = fx * rr;
				ix = fast_floor(qx);
				qx -= ix;
				ix &= (kRandomBufferSize - 1);
				ixBuffer[x] = ix;
				qxBuffer[x] = Hermite(qx);
			}
			else
			{
				// later passes: grab the stored values.
				ix = ixBuffer[x];
				qx = qxBuffer[x];
			}
			
			jx = (ix + 1) & octaveMask;
			jx &= (kRandomBufferSize - 1);
			
			rix = Lerp(randomBuffer[iy * kRandomBufferSize + ix], randomBuffer[iy * kRandomBufferSize + jx], qx);
			rjx = Lerp(randomBuffer[jy * kRandomBufferSize + ix], randomBuffer[jy * kRandomBufferSize + jx], qx);
			rfinal = Lerp(rix, rjx, qy);
			
			*dst++ += scale * rfinal;
		}
	}
}


static BOOL GenerateFBMNoise(OOStandaloneAtmosphereGeneratorInfo *info)
{
	// Allocate the temporary buffers we need in one fell swoop, to avoid administrative overhead.
	size_t randomBufferSize = kRandomBufferSize * kRandomBufferSize * sizeof (float);
	size_t qxBufferSize = info->width * sizeof (float);
	size_t ixBufferSize = info->width * sizeof (int);
	char *sharedBuffer = malloc(randomBufferSize + qxBufferSize + ixBufferSize);
	if (sharedBuffer == NULL)  return NO;
	
	float *randomBuffer = (float *)sharedBuffer;
	float *qxBuffer = (float *)(sharedBuffer + randomBufferSize);
	int *ixBuffer = (int *)(sharedBuffer + randomBufferSize + qxBufferSize);
	
	// Get us some value noise.
	FillRandomBuffer(randomBuffer, info->seed);
	
	// Generate basic fBM noise.
	unsigned height = info->height;
	unsigned octaveMask = 8 * kPlanetAspectRatio;
	float octave = octaveMask;
	octaveMask -= 1;
	float scale = 0.5f;
	
	while ((octaveMask + 1) < height)
	{
		AddNoise(info, randomBuffer, octave, octaveMask, scale, qxBuffer, ixBuffer);
		octave *= 2.0f;
		octaveMask = (octaveMask << 1) | 1;
		scale *= 0.5f;
	}
	
	FREE(sharedBuffer);
	return YES;
}

#endif


static float QFactor(float *accbuffer, int x, int y, unsigned width, float polar_y_value, float bias, float polar_y)
{
	float q = accbuffer[y * width + x];	// 0.0 -> 1.0
	q += bias;
	
	// Polar Y smooth.
	q = q * (1.0f - polar_y) + polar_y * polar_y_value;

	return q;
}








#endif	// NEW_PLANETS
