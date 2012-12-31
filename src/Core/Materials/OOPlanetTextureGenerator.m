/*
	OOPlanetTextureGenerator.m
	
	Generator for planet diffuse maps.
	
	
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

#define POLAR_CAPS			1
#define ALBEDO_FACTOR		0.7f	// Overall darkening of everything, allowing better contrast for snow and specular highlights.


#import "OOPlanetTextureGenerator.h"
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


@interface OOPlanetTextureGenerator (Private)

- (NSString *) cacheKeyForType:(NSString *)type;
- (OOTextureGenerator *) normalMapGenerator;	// Must be called before generator is enqueued for rendering.
- (OOTextureGenerator *) atmosphereGenerator;	// Must be called before generator is enqueued for rendering.

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


//	Doing the same as above for the atmosphere.
@interface OOPlanetAtmosphereGenerator: OOTextureGenerator
{
@private
	NSString				*_cacheKey;
	RANROTSeed				_seed;
}

- (id) initWithCacheKey:(NSString *)cacheKey seed:(RANROTSeed)seed;

- (void) completeWithData:(void *)data width:(unsigned)width height:(unsigned)height;

@end


static FloatRGB FloatRGBFromDictColor(NSDictionary *dictionary, NSString *key);

static BOOL FillFBMBuffer(OOPlanetTextureGeneratorInfo *info);

static float QFactor(float *accbuffer, int x, int y, unsigned width, float polar_y_value, float bias, float polar_y);
static float GetQ(float *qbuffer, int x, int y, unsigned width, unsigned height, unsigned widthMask, unsigned heightMask);

static FloatRGB Blend(float fraction, FloatRGB a, FloatRGB b);
static float BlendAlpha(float fraction, float a, float b);
static void SetMixConstants(OOPlanetTextureGeneratorInfo *info, float temperatureFraction);
static FloatRGBA CloudMix(OOPlanetTextureGeneratorInfo *info, float q, float nearPole);
static FloatRGBA PlanetMix(OOPlanetTextureGeneratorInfo *info, float q, float nearPole);


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


@implementation OOPlanetTextureGenerator

- (id) initWithPlanetInfo:(NSDictionary *)planetInfo
{
	if ((self = [super init]))
	{
		_info.landFraction = OOClamp_0_1_f([planetInfo oo_floatForKey:@"land_fraction" defaultValue:0.3]);
		_info.landColor = FloatRGBFromDictColor(planetInfo, @"land_color");
		_info.seaColor = FloatRGBFromDictColor(planetInfo, @"sea_color");
		_info.paleLandColor = FloatRGBFromDictColor(planetInfo, @"polar_land_color");
		_info.polarSeaColor = FloatRGBFromDictColor(planetInfo, @"polar_sea_color");
		[[planetInfo objectForKey:@"noise_map_seed"] getValue:&_info.seed];
		
		if ([planetInfo objectForKey:@"cloud_alpha"])
		{
			// we have an atmosphere:
			_info.cloudAlpha = [planetInfo oo_floatForKey:@"cloud_alpha" defaultValue:1.0f];
			_info.cloudFraction = OOClamp_0_1_f([planetInfo oo_floatForKey:@"cloud_fraction" defaultValue:0.3]);
			_info.cloudColor = FloatRGBFromDictColor(planetInfo, @"cloud_color");
			_info.paleCloudColor = FloatRGBFromDictColor(planetInfo, @"polar_cloud_color");
		}
		
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


+ (BOOL) generatePlanetTexture:(OOTexture **)texture andAtmosphere:(OOTexture **)atmosphere withInfo:(NSDictionary *)planetInfo
{
	NSParameterAssert(texture != NULL);
	
	OOPlanetTextureGenerator *diffuseGen = [[[self alloc] initWithPlanetInfo:planetInfo] autorelease];
	if (diffuseGen == nil)  return NO;
	
	OOTextureGenerator *atmoGen = [diffuseGen atmosphereGenerator];
	if (atmoGen == nil)  return NO;
	
	*atmosphere = [OOTexture textureWithGenerator:atmoGen];
	if (*atmosphere == nil)  return NO;
	
	*texture = [OOTexture textureWithGenerator:diffuseGen];
	
	return *texture != nil;
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


+ (BOOL) generatePlanetTexture:(OOTexture **)texture secondaryTexture:(OOTexture **)secondaryTexture andAtmosphere:(OOTexture **)atmosphere withInfo:(NSDictionary *)planetInfo
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
	
	OOTextureGenerator *atmoGen = [diffuseGen atmosphereGenerator];
	if (atmoGen == nil)  return NO;
	
	*atmosphere = [OOTexture textureWithGenerator:atmoGen];
	if (*atmosphere == nil)
	{
		if (secondaryTexture != NULL) {
			*secondaryTexture = nil;
		}
		return NO;
	}
	
	*texture = [OOTexture textureWithGenerator:diffuseGen];
	
	return *texture != nil;
}


- (void) dealloc
{
	DESTROY(_nMapGenerator);
	DESTROY(_atmoGenerator);
	
	[super dealloc];
}


- (NSString *) descriptionComponents
{
	return [NSString stringWithFormat:@"seed: %u,%u land: %g", _info.seed.high, _info.seed.low, _info.landFraction];
}


- (uint32_t) textureOptions
{
	return PLANET_TEXTURE_OPTIONS;
}


- (NSString *) cacheKey
{
	NSString *type =(_nMapGenerator == nil) ? @"diffuse-baked" : @"diffuse-raw";
	if (_atmoGenerator != nil) type = [NSString stringWithFormat:@"%@-atmo", type];
	return [self cacheKeyForType:type];
}


- (NSString *) cacheKeyForType:(NSString *)type
{
	return [NSString stringWithFormat:@"OOPlanetTextureGenerator-%@@%u\n%u,%u/%g/%u,%u/%f,%f,%f/%f,%f,%f/%f,%f,%f/%f,%f,%f",
			type, _planetScale,
			_info.width, _info.height, _info.landFraction, _info.seed.high, _info.seed.low,
			_info.landColor.r, _info.landColor.g, _info.landColor.b,
			_info.seaColor.r, _info.seaColor.g, _info.seaColor.b,
			_info.paleLandColor.r, _info.paleLandColor.g, _info.paleLandColor.b,
			_info.polarSeaColor.r, _info.polarSeaColor.g, _info.polarSeaColor.b];
}


- (OOTextureGenerator *) normalMapGenerator
{
	if (_nMapGenerator == nil)
	{
		_nMapGenerator = [[OOPlanetNormalMapGenerator alloc] initWithCacheKey:[self cacheKeyForType:@"normal"] seed:_info.seed];
	}
	return _nMapGenerator;
}


- (OOTextureGenerator *) atmosphereGenerator
{
	if (_atmoGenerator == nil)
	{
		_atmoGenerator = [[OOPlanetAtmosphereGenerator alloc] initWithCacheKey:[self cacheKeyForType:@"atmo"] seed:_info.seed];
	}
	return _atmoGenerator;
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


- (void) loadTexture
{
	OOLog(@"texture.planet.generate.begin", @"Started generator %@", self);
	
	BOOL success = NO;
	BOOL generateNormalMap = (_nMapGenerator != nil);
	BOOL generateAtmosphere = (_atmoGenerator != nil);
	
	uint8_t		*buffer = NULL, *px = NULL;
	uint8_t		*nBuffer = NULL, *npx = NULL;
	uint8_t		*aBuffer = NULL, *apx = NULL;
	float		*randomBuffer = NULL;
	
	_height = _info.height = 1 << (_planetScale + kPlanetScaleOffset);
	_width = _info.width = _height * kPlanetAspectRatio;
	
#define FAIL_IF(cond)  do { if (EXPECT_NOT(cond))  goto END; } while (0)
#define FAIL_IF_NULL(x)  FAIL_IF((x) == NULL)
	
	buffer = malloc(4 * _width * _height);
	FAIL_IF_NULL(buffer);
	px = buffer;
	
	if (generateNormalMap)
	{
		nBuffer = malloc(4 * _width * _height);
		FAIL_IF_NULL(nBuffer);
		npx = nBuffer;
	}
	
	if (generateAtmosphere)
	{
		aBuffer = malloc(4 * _width * _height);
		FAIL_IF_NULL(aBuffer);
		apx = aBuffer;
	}
	
	FAIL_IF(!FillFBMBuffer(&_info));
#if DEBUG_DUMP_RAW
	[self dumpNoiseBuffer:_info.fbmBuffer];
#endif
	
	float paleClouds = (_info.cloudFraction * _info.fbmBuffer[0] < 1.0f - _info.cloudFraction) ? 0.0f : 1.0f;
	float poleValue = (_info.landFraction > 0.5f) ? 0.5f * _info.landFraction : 0.0f;
	float seaBias = _info.landFraction - 1.0f;
	
	_info.paleSeaColor = Blend(0.35f, _info.polarSeaColor, Blend(0.7f, _info.seaColor, _info.landColor));
	float normalScale = 1 << _planetScale;
	if (!generateNormalMap)  normalScale *= 3.0f;
	
	// Deep sea colour: sea darker past the continental shelf.
	_info.deepSeaColor = Blend(0.85f, _info.seaColor, (FloatRGB){ 0, 0, 0 });
	
	int x, y;
	FloatRGBA color;
	Vector norm;
	float q, yN, yS, yW, yE, nearPole;
	GLfloat shade;
	float rHeight = 1.0f / _height;
	float fy, fHeight = _height;
	// The second parameter is the temperature fraction. Most favourable: 1.0f,  little ice. Most unfavourable: 0.0f, frozen planet. TODO: make it dependent on ranrot / planetinfo key...
	SetMixConstants(&_info, 0.95f);	// no need to recalculate them inside each loop!
	
	// first pass, calculate q.
	_info.qBuffer = malloc(_width * _height * sizeof (float));
	FAIL_IF_NULL(_info.qBuffer);
	
	for (y = (int)_height - 1, fy = (float)y; y >=0; y--, fy--)
	{
		nearPole = (2.0f * fy - fHeight) * rHeight;
		nearPole *= nearPole;
		
		for (x = (int)_width - 1; x >=0; x--)
		{
			_info.qBuffer[y * _width + x] = QFactor(_info.fbmBuffer, x, y, _width, poleValue, seaBias, nearPole);
		}
	}
	
	// second pass, use q.
	float cloudFraction = _info.cloudFraction;
	unsigned widthMask = _width - 1;
	unsigned heightMask = _height - 1;
	
	for (y = (int)_height - 1, fy = (float)y; y >= 0; y--, fy--)
	{
		nearPole = (2.0f * fy - fHeight) * rHeight;
		nearPole *= nearPole;
		
		for (x = (int)_width - 1; x >= 0; x--)
		{
			q = _info.qBuffer[y * _width + x];	// no need to use GetQ, x and y are always within bounds.
			yN = GetQ(_info.qBuffer, x, y - 1, _width, _height, widthMask, heightMask);	// recalculates x & y if they go out of bounds.
			yS = GetQ(_info.qBuffer, x, y + 1, _width, _height, widthMask, heightMask);
			yW = GetQ(_info.qBuffer, x - 1, y, _width, _height, widthMask, heightMask);
			yE = GetQ(_info.qBuffer, x + 1, y, _width, _height, widthMask, heightMask);
			
			color = PlanetMix(&_info, q, nearPole);
			
			norm = vector_normal(make_vector(normalScale * (yE - yW), normalScale * (yN - yS), 1.0f));
			if (generateNormalMap)
			{
				shade = 1.0f;
				
				// Flatten the sea.
				norm = OOVectorInterpolate(norm, kBasisZVector, color.a);
				
				// Put norm in normal map, scaled from [-1..1] to [0..255].
				*npx++ = 127.5f * (norm.y + 1.0f);
				*npx++ = 127.5f * (-norm.x + 1.0f);
				*npx++ = 127.5f * (norm.z + 1.0f);
				
				*npx++ = 255.0f * color.a;	// Specular channel.
			}
			else
			{
				//	Terrain shading - lambertian lighting from straight above.
				shade = norm.z;
				
				/*	We don't want terrain shading in the sea. The alpha channel
					of color is a measure of "seaishness" for the specular map,
					so we can recycle that to avoid branching.
					-- Ahruman
				*/
				shade += color.a - color.a * shade;	// equivalent to - but slightly faster than - previous implementation.
			}
			
			*px++ = 255.0f * color.r * shade;
			*px++ = 255.0f * color.g * shade;
			*px++ = 255.0f * color.b * shade;
			
			*px++ = 0;	// FIXME: light map goes here.
			
			if (generateAtmosphere)
			{
				q = QFactor(_info.fbmBuffer, x, y, _width, paleClouds, cloudFraction, nearPole);
				color = CloudMix(&_info, q, nearPole);
				
				*apx++ = 255.0f * color.r;
				*apx++ = 255.0f * color.g;
				*apx++ = 255.0f * color.b;
				*apx++ = 255.0f * color.a * _info.cloudAlpha;
			}
		}
	}
	
	success = YES;
	_format = kOOTextureDataRGBA;
	
END:
	FREE(_info.fbmBuffer);
	FREE(_info.qBuffer);
	FREE(randomBuffer);
	if (success)
	{
		_data = buffer;
		if (generateNormalMap) [_nMapGenerator completeWithData:nBuffer width:_width height:_height];
		if (generateAtmosphere) [_atmoGenerator completeWithData:aBuffer width:_width height:_height];
	}
	else
	{
		FREE(buffer);
		FREE(nBuffer);
		FREE(aBuffer);
	}
	DESTROY(_nMapGenerator);
	DESTROY(_atmoGenerator);
	
	OOLog(@"texture.planet.generate.complete", @"Completed generator %@ %@successfully", self, success ? @"" : @"un");
	
#if DEBUG_DUMP
	if (success)
	{
		NSString *diffuseName = [NSString stringWithFormat:@"planet-%u-%u-diffuse-new", _info.seed.high, _info.seed.low];
		NSString *lightsName = [NSString stringWithFormat:@"planet-%u-%u-lights-new", _info.seed.high, _info.seed.low];
		
		[[UNIVERSE gameView] dumpRGBAToRGBFileNamed:diffuseName
								   andGrayFileNamed:lightsName
											  bytes:buffer
											  width:_width
											 height:_height
										   rowBytes:_width * 4];
	}
#endif
}


#if DEBUG_DUMP_RAW

- (void) dumpNoiseBuffer:(float *)noise
{
	NSString *noiseName = [NSString stringWithFormat:@"planet-%u-%u-noise-new", _info.seed.high, _info.seed.low];
	
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


static FloatRGBA CloudMix(OOPlanetTextureGeneratorInfo *info, float q, float nearPole)
{
#define AIR_ALPHA				(0.15f)
#define CLOUD_ALPHA				(1.0f)

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
	
	return (FloatRGBA){ cloudColor.r, cloudColor.g, cloudColor.b, alpha };
}


static FloatRGBA PlanetMix(OOPlanetTextureGeneratorInfo *info, float q, float nearPole)
{
#define RECIP_COASTLINE_PORTION		(160.0f)
#define COASTLINE_PORTION			(1.0f / RECIP_COASTLINE_PORTION)
#define SHALLOWS					(2.0f * COASTLINE_PORTION)	// increased shallows area.
#define RECIP_SHALLOWS				(1.0f / SHALLOWS)
// N.B.: DEEPS can't be more than RECIP_COASTLINE_PORTION * COASTLINE_PORTION!
#define DEEPS						(40.0f * COASTLINE_PORTION) 
#define RECIP_DEEPS					(1.0f / DEEPS)
	
	const FloatRGB white = { 1.0f, 1.0f, 1.0f };
	FloatRGB diffuse;
	// windows specular 'fix': 0 was showing pitch black continents when on the dark side, 0.01 shows the same shading as on Macs.
	// TODO: a less hack-like fix.
	float specular = 0.01f;
	
	if (q <= 0.0f)
	{
		// Below datum - sea.
		if (q > -SHALLOWS)
		{
			// Coastal waters.
			diffuse = Blend(-q * RECIP_SHALLOWS, info->seaColor, info->paleSeaColor);
			specular = 1.0f;
		}
		else
		{
			// Open sea.
			if (q > -DEEPS)  diffuse = Blend(-q * RECIP_DEEPS, info->deepSeaColor, info->seaColor);
			else  diffuse = info->deepSeaColor;
			specular = Lerp(1.0f, 0.85f, -q);
		}
	}
	else if (q < COASTLINE_PORTION)
	{
		// Coastline.
		specular = q * RECIP_COASTLINE_PORTION;
		diffuse = Blend(specular, info->landColor, info->paleSeaColor);
		specular = 1.0f - specular;
	}
	else if (q > 1.0f)
	{
		// High up - snow-capped peaks. With overrides q can range between -2 to +2.
		diffuse = white;
	}
	else if (q > info->mix_hi)
	{
		diffuse = Blend((q - info->mix_hi) * info->mix_ih, white, info->paleLandColor);	// Snowline.
	}
	else
	{
		// Normal land.
		diffuse = Blend((info->mix_hi - q) * info->mix_oh, info->landColor, info->paleLandColor);
	}
	
#if POLAR_CAPS
	// (q > mix_polarCap + mix_polarCap - nearPole) ==  ((nearPole + q) / 2 > mix_polarCap)
	float phi = info->mix_polarCap + info->mix_polarCap - nearPole;
	if (q > phi)	 // (nearPole + q) / 2 > pole
	{
		// thinner to thicker ice.
		specular = q > phi + 0.02f ? 1.0f : 0.2f + (q - phi) * 40.0f;	// (q - phi) * 40 == ((q-phi) / 0.02) * 0.8
		//diffuse = info->polarSeaColor;
		diffuse = Blend(specular, info->polarSeaColor, diffuse);
		specular = specular * 0.5f; // softer contours under ice, but still contours.
	}
#endif
	
	return (FloatRGBA){ diffuse.r, diffuse.g, diffuse.b, specular };
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


static BOOL GenerateFBMNoise(OOPlanetTextureGeneratorInfo *info);


static BOOL FillFBMBuffer(OOPlanetTextureGeneratorInfo *info)
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
static float SampleNoise3D(OOPlanetTextureGeneratorInfo *info, Vector p)
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
static BOOL MakePermutationTable(OOPlanetTextureGeneratorInfo *info)
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


static BOOL GenerateFBMNoise(OOPlanetTextureGeneratorInfo *info)
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


static void AddNoise(OOPlanetTextureGeneratorInfo *info, float *randomBuffer, float octave, unsigned octaveMask, float scale, float *qxBuffer, int *ixBuffer)
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


static BOOL GenerateFBMNoise(OOPlanetTextureGeneratorInfo *info)
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


static float GetQ(float *qbuffer, int x, int y, unsigned width, unsigned height, unsigned widthMask, unsigned heightMask)
{
	// Correct Y wrapping mode, unoptimised.
	//if (y < 0) { y = -y - 1; x += width / 2; }
	//else if (y >= height) { y = height - (y - height)  - 1; x += width / 2; }
	// now let's wrap x.
	//x = x % width;

	// Correct Y wrapping mode, faster method. In the following lines of code, both
	// width and height are assumed to be powers of 2: 512, 1024, 2048, etc...
	if (y & height) { y = (y ^ heightMask) & heightMask; x += width >> 1; }
	// x wrapping.
	x &= widthMask;
	return  qbuffer[y * width + x];
}


static void SetMixConstants(OOPlanetTextureGeneratorInfo *info, float temperatureFraction)
{
	info->mix_hi = 0.66667f * info->landFraction;
	info->mix_oh = 1.0f / info->mix_hi;
	info->mix_ih = 1.0f / (1.0f - info->mix_hi);
	info->mix_polarCap = temperatureFraction * (0.28f + 0.24f * info->landFraction);	// landmasses make the polar cap proportionally bigger, but not too much bigger.
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
	_data = data_;
	_width = width_;
	_height = height_;
	_format = kOOTextureDataRGBA;
	
	// Enqueue so superclass can apply texture options and so forth.
	[super enqueue];
	
#if DEBUG_DUMP
	NSString *normalName = [NSString stringWithFormat:@"planet-%u-%u-normal-new", _seed.high, _seed.low];
	NSString *specularName = [NSString stringWithFormat:@"planet-%u-%u-specular-new", _seed.high, _seed.low];
	
	[[UNIVERSE gameView] dumpRGBAToRGBFileNamed:normalName
							   andGrayFileNamed:specularName
										  bytes:_data
										  width:_width
										 height:_height
									   rowBytes:_width * 4];
#endif
}

@end


@implementation OOPlanetAtmosphereGenerator

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
	return YES;
}


- (void) loadTexture
{
	// Do nothing.
}


- (void) completeWithData:(void *)data_ width:(unsigned)width_ height:(unsigned)height_
{
	_data = data_;
	_width = width_;
	_height = height_;
	_format = kOOTextureDataRGBA;
	
	// Enqueue so superclass can apply texture options and so forth.
	[super enqueue];
	
#if DEBUG_DUMP
	NSString *rgbName = [NSString stringWithFormat:@"planet-%u-%u-atmosphere-rgb-new", _seed.high, _seed.low];
	NSString *alphaName = [NSString stringWithFormat:@"planet-%u-%u-atmosphere-alpha-new", _seed.high, _seed.low];
	
	[[UNIVERSE gameView] dumpRGBAToRGBFileNamed:rgbName
							   andGrayFileNamed:alphaName
										  bytes:_data
										  width:_width
										 height:_height
									   rowBytes:_width * 4];
#endif
}

@end

#endif	// NEW_PLANETS
