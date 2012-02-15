/*

OOCombinedEmissionMapGenerator.m


Copyright (C) 2010-2012 Jens Ayton

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/

#import "OOCombinedEmissionMapGenerator.h"

#import "OOColor.h"
#import "OOPixMapChannelOperations.h"
#import "OOTextureScaling.h"
#import "OOMaterialSpecifier.h"


#define DUMP_COMBINER	0


static OOColor *ModulateColor(OOColor *a, OOColor *b);
static void ScaleToMatch(OOPixMap *pmA, OOPixMap *pmB);


@interface OOCombinedEmissionMapGenerator (Private)

- (id) initWithEmissionMap:(OOTextureLoader *)emissionMapLoader
			 emissionColor:(OOColor *)emissionColor
				diffuseMap:(OOTexture *)diffuseMap
			  diffuseColor:(OOColor *)diffuseColor
		   illuminationMap:(OOTextureLoader *)illuminationMapLoader
		 illuminationColor:(OOColor *)illuminationColor
			 isCombinedMap:(BOOL)isCombinedMap
		  optionsSpecifier:(NSDictionary *)spec;

@end


@implementation OOCombinedEmissionMapGenerator

- (id) initWithEmissionMap:(OOTextureLoader *)emissionMapLoader
			 emissionColor:(OOColor *)emissionColor
				diffuseMap:(OOTexture *)diffuseMap
			  diffuseColor:(OOColor *)diffuseColor
		   illuminationMap:(OOTextureLoader *)illuminationMapLoader
		 illuminationColor:(OOColor *)illuminationColor
		  optionsSpecifier:(NSDictionary *)spec
{
	return [self initWithEmissionMap:emissionMapLoader
					   emissionColor:emissionColor
						  diffuseMap:diffuseMap
						diffuseColor:diffuseColor
					 illuminationMap:illuminationMapLoader
				   illuminationColor:illuminationColor
					   isCombinedMap:NO
					optionsSpecifier:spec];
}


- (id) initWithEmissionAndIlluminationMap:(OOTextureLoader *)emissionAndIlluminationMapLoader
							   diffuseMap:(OOTexture *)diffuseMap
							 diffuseColor:(OOColor *)diffuseColor
							emissionColor:(OOColor *)emissionColor
						illuminationColor:(OOColor *)illuminationColor
						 optionsSpecifier:(NSDictionary *)spec
{
	return [self initWithEmissionMap:emissionAndIlluminationMapLoader
					   emissionColor:emissionColor
						  diffuseMap:diffuseMap
						diffuseColor:diffuseColor
					 illuminationMap:nil
				   illuminationColor:illuminationColor
					   isCombinedMap:YES
					optionsSpecifier:spec];
}


- (id) initWithEmissionMap:(OOTextureLoader *)emissionMapLoader
			 emissionColor:(OOColor *)emissionColor
				diffuseMap:(OOTexture *)diffuseMap
			  diffuseColor:(OOColor *)diffuseColor
		   illuminationMap:(OOTextureLoader *)illuminationMapLoader
		 illuminationColor:(OOColor *)illuminationColor
			 isCombinedMap:(BOOL)isCombinedMap
		  optionsSpecifier:(NSDictionary *)spec
{
	if (emissionMapLoader == nil && illuminationMapLoader == nil)
	{
		[self release];
		return nil;
	}
	
	NSParameterAssert(illuminationMapLoader == nil || !isCombinedMap);
	
	uint32_t options;
	GLfloat anisotropy;
	GLfloat lodBias;
	OOInterpretTextureSpecifier(spec, NULL, &options, &anisotropy, &lodBias, YES);
	options = OOApplyTextureOptionDefaults(options);
	
	if ((self = [super initWithPath:@"<generated emission map>" options:options]))
	{
		/*	Illumination contribution is:
			illuminationMap * illuminationColor * diffuseMap * diffuseColor
			Since illuminationColor and diffuseColor aren't used otherwise,
			we may as well combine them up front.
		*/
		illuminationColor = ModulateColor(diffuseColor, illuminationColor);
										  
		if ([emissionColor isWhite])  emissionColor = nil;
		if ([illuminationColor isWhite])  illuminationColor = nil;
		if (!isCombinedMap && illuminationMapLoader == nil)  diffuseMap = nil;	// Diffuse map is only used with illumination
		
		
		_cacheKey = [[NSString stringWithFormat:@"Combined emission map\nSingle source: %@\nemission:%@ * %@, illumination: %@ * %@ * %@",
					  isCombinedMap ? @"yes" : @"no",
					  [emissionMapLoader cacheKey],
					  [emissionColor rgbaDescription],
					  [illuminationMapLoader cacheKey],
					  [diffuseMap cacheKey],
					  [illuminationColor rgbaDescription]] copy];
		
		_emissionColor = [emissionColor retain];
		_illuminationColor = [illuminationColor retain];
		_isCombinedMap = isCombinedMap;
		
		_textureOptions = options;
		_anisotropy = anisotropy;
		_lodBias = lodBias;
		
		/*	Extract pixmap from diffuse map. This must be done in the main
			thread even if scheduling is fixed, because it might involve
			reading back pixels from OpenGL.
		*/
		if (diffuseMap != nil)
		{
			_diffusePx = [diffuseMap copyPixMapRepresentation];
#ifndef NDEBUG
			_diffuseDesc = [[diffuseMap shortDescription] copy];
#endif
		}
		
		/*	Extract emission and illumination pixmaps from loaders. Ideally,
			this would be done asynchronously, but that requires dependency
			management in OOAsyncWorkManager.
		*/
		OOTextureDataFormat format;
		if (emissionMapLoader != nil)
		{
			[emissionMapLoader getResult:&_emissionPx format:&format originalWidth:NULL originalHeight:NULL];
#ifndef NDEBUG
			_emissionDesc = [[emissionMapLoader shortDescription] copy];
#endif
		}
		if (illuminationMapLoader != nil)
		{
			[illuminationMapLoader getResult:&_illuminationPx format:&format originalWidth:NULL originalHeight:NULL];
#ifndef NDEBUG
			_illuminationDesc = [[illuminationMapLoader shortDescription] copy];
#endif
		}
	}
	
	return self;
}


- (void) dealloc
{
	OOFreePixMap(&_emissionPx);
	OOFreePixMap(&_illuminationPx);
	OOFreePixMap(&_diffusePx);
	DESTROY(_emissionColor);
	DESTROY(_illuminationColor);
	
#ifndef NDEBUG
	DESTROY(_diffuseDesc);
	DESTROY(_emissionDesc);
	DESTROY(_illuminationDesc);
#endif
	
	[super dealloc];
}


#ifndef NDEBUG
- (NSString *) descriptionComponents
{
	NSMutableString *result = [NSMutableString string];
	BOOL haveIllumination = NO;
	
	if (_emissionDesc != nil)
	{
		[result appendFormat:@"emission map: %@", _emissionDesc];
		if (_isCombinedMap)
		{
			[result appendString:@".rgb"];
		}
		if (_emissionColor != nil)
		{
			[result appendFormat:@" * %@", [_emissionColor rgbaDescription]];
		}
		
		if (_isCombinedMap)
		{
			[result appendFormat:@", illumination map: %@.a", _emissionDesc];
			haveIllumination = YES;
		}
	}
	
	if (_illuminationDesc != nil)
	{
		if (_emissionDesc != nil)  [result appendString:@", "];
		[result appendFormat:@"illumination map: %@", _illuminationDesc];
		haveIllumination = YES;
	}
	
	if (haveIllumination)
	{
		if (_diffuseDesc != nil)
		{
			[result appendFormat:@" * %@", _diffuseDesc];
		}
		if (_illuminationColor != nil)
		{
			[result appendFormat:@" * %@", [_illuminationColor rgbaDescription]];
		}
	}
	
	return result;
}
#endif


- (uint32_t) textureOptions
{
	return _textureOptions;
}


- (GLfloat) anisotropy
{
	return _anisotropy;
}


- (GLfloat) lodBias
{
	return _lodBias;
}


- (NSString *) cacheKey
{
	return _cacheKey;
}


- (void) loadTexture
{
	OOPixMap illuminationPx = kOONullPixMap;
	BOOL haveEmission = NO, haveIllumination = NO, haveDiffuse = NO;
	
#if DUMP_COMBINER
	static unsigned sTexID = 0;
	unsigned texID = ++sTexID, dumpCount = 0;
	
#define DUMP(pm, label) OODumpPixMap(pm, [NSString stringWithFormat:@"envmap %u.%u - %@", texID, ++dumpCount, label]);
#else
#define DUMP(pm, label) do {} while (0)
#endif
	
	haveEmission = !OOIsNullPixMap(_emissionPx);
	if (haveEmission)  DUMP(_emissionPx, @"source emission map");
	
	// Extract illumination component if emission_and_illumination_map.
	if (haveEmission && _isCombinedMap && OOPixMapFormatHasAlpha(_emissionPx.format))
	{
		OOPixMapToRGBA(&_emissionPx);
		illuminationPx = OODuplicatePixMap(_emissionPx, 0);
		OOExtractPixMapChannel(&illuminationPx, 3, YES);
		haveIllumination = YES;
		DUMP(illuminationPx, @"extracted illumination map");
	}
	
	// Tint emission map if necessary.
	if (haveEmission && _emissionColor != nil)
	{
		OOPixMapModulateUniform(&_emissionPx, [_emissionColor redComponent], [_emissionColor greenComponent], [_emissionColor blueComponent], 1.0);
		DUMP(_emissionPx, @"modulated emission map");
	}
	
	if (!OOIsNullPixMap(_illuminationPx))
	{
		NSAssert(!_isCombinedMap, @"OOCombinedEmissionMapGenerator configured with both illumination map and combined emission/illumination map.");
		
		illuminationPx = _illuminationPx;
		_illuminationPx.pixels = NULL;
		haveIllumination = YES;
		DUMP(illuminationPx, @"source illumination map");
	}
	
	// Tint illumination map if necessary.
	if (haveIllumination && _illuminationColor != nil)
	{
		OOPixMapModulateUniform(&illuminationPx, [_illuminationColor redComponent], [_illuminationColor greenComponent], [_illuminationColor blueComponent], 1.0);
		DUMP(illuminationPx, @"modulated illumination map");
	}
	
	// Load diffuse map and combine with illumination map.
	haveDiffuse = !OOIsNullPixMap(_diffusePx);
	if (haveDiffuse)  DUMP(_diffusePx, @"source diffuse map");
	
	if (haveIllumination && haveDiffuse)
	{
		// Modulate illumination with diffuse map.
		ScaleToMatch(&_diffusePx, &illuminationPx);
		OOPixMapToRGBA(&_diffusePx);
		OOPixMapModulatePixMap(&illuminationPx, _diffusePx);
		DUMP(illuminationPx, @"combined diffuse and illumination map");
	}
	OOFreePixMap(&_diffusePx);
	
	if (haveIllumination)
	{
		if (haveEmission)
		{
			OOPixMapToRGBA(&illuminationPx);
			OOPixMapAddPixMap(&_emissionPx, illuminationPx);
			OOFreePixMap(&illuminationPx);
			DUMP(_emissionPx, @"combined emission and illumination map");
		}
		else if (haveIllumination)
		{
			// No explicit emission map -> modulated illumination map is our only emission map.
			_emissionPx = illuminationPx;
			haveEmission = YES;
			illuminationPx.pixels = NULL;
		}
		haveIllumination = NO;	// Either way, illumination is now baked into emission.
	}
	
	(void)haveEmission;
	(void)haveIllumination;
	
	// Done: emissionPx now contains combined emission map.
	OOCompactPixMap(&_emissionPx);
	if (OOIsValidPixMap(_emissionPx))
	{
		_data = _emissionPx.pixels;
		_width = _emissionPx.width;
		_height = _emissionPx.height;
		_rowBytes = _emissionPx.rowBytes;
		_format = _emissionPx.format;
		
		_emissionPx.pixels = NULL;	// So it won't be freed by -dealloc.
	}
	if (_data == NULL)
	{
		OOLogERR(@"texture.combinedEmissionMap.error", @"Unknown error loading %@", self);
	}
}

@end


static OOColor *ModulateColor(OOColor *a, OOColor *b)
{
	if (a == nil)  return b;
	if (b == nil)  return a;
	
	OORGBAComponents ac, bc;
	ac = [a rgbaComponents];
	bc = [b rgbaComponents];
	
	ac.r *= bc.r;
	ac.g *= bc.g;
	ac.b *= bc.b;
	ac.a *= bc.a;
	
	return [OOColor colorWithRGBAComponents:ac];
}


static void ScaleToMatch(OOPixMap *pmA, OOPixMap *pmB)
{
	NSCParameterAssert(pmA != NULL && pmB != NULL && OOIsValidPixMap(*pmA) && OOIsValidPixMap(*pmB));
	
	OOPixMapDimension minWidth = MIN(pmA->width, pmB->width);
	OOPixMapDimension minHeight = MIN(pmA->height, pmB->height);
	
	if (pmA->width != minWidth || pmA->height != minHeight)
	{
		*pmA = OOScalePixMap(*pmA, minWidth, minHeight, NO);
	}
	if (pmB->width != minWidth || pmB->height != minHeight)
	{
		*pmB = OOScalePixMap(*pmB, minWidth, minHeight, NO);
	}
}
