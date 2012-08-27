/*

OOTextureLoader.m


Copyright (C) 2007-2012 Jens Ayton

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

#import "OOPNGTextureLoader.h"
#import "OOTextureLoader.h"
#import "OOFunctionAttributes.h"
#import "OOCollectionExtractors.h"
#import "OOMaths.h"
#import "Universe.h"
#import "OOTextureScaling.h"
#import "OOPixMapChannelOperations.h"
#import "OOConvertCubeMapToLatLong.h"
#include <stdlib.h>
#import "ResourceManager.h"
#import "OOOpenGLExtensionManager.h"


#define DUMP_CONVERTED_CUBE_MAPS	0


static unsigned				sGLMaxSize;
static uint32_t				sUserMaxSize;
static BOOL					sReducedDetail;
static BOOL					sHaveNPOTTextures = NO;	// TODO: support "true" non-power-of-two textures.
static BOOL					sHaveSetUp = NO;


@interface OOTextureLoader (OOPrivate)

+ (void)setUp;

- (void)applySettings;
- (void)getDesiredWidth:(OOPixMapDimension *)outDesiredWidth andHeight:(OOPixMapDimension *)outDesiredHeight;


@end


@implementation OOTextureLoader

+ (id)loaderWithPath:(NSString *)inPath options:(uint32_t)options
{
	NSString				*extension = nil;
	id						result = nil;
	
	if (EXPECT_NOT(inPath == nil)) return nil;
	if (EXPECT_NOT(!sHaveSetUp))  [self setUp];
	
	// Get reduced detail setting (every time, in case it changes; we don't want to call through to Universe on the loading thread in case the implementation becomes non-trivial).
	sReducedDetail = [UNIVERSE reducedDetail];
	
	// Get a suitable loader. FIXME -- this should sniff the data instead of relying on extensions.
	extension = [[inPath pathExtension] lowercaseString];
	if ([extension isEqualToString:@"png"])
	{
		result = [[[OOPNGTextureLoader alloc] initWithPath:inPath options:options] autorelease];
	}
	else
	{
		OOLog(@"texture.load.unknownType", @"Can't use %@ as a texture - extension \"%@\" does not identify a known type.", inPath, extension);
	}
	
	if (result != nil)
	{
		if (![[OOAsyncWorkManager sharedAsyncWorkManager] addTask:result priority:kOOAsyncPriorityMedium])  result = nil;
	}
	
	return result;
}


+ (id)loaderWithTextureSpecifier:(id)specifier extraOptions:(uint32_t)extraOptions folder:(NSString *)folder
{
	NSString		*name = nil;
	NSString		*path = nil;
	uint32_t		options = 0;
	
	if (!OOInterpretTextureSpecifier(specifier, &name, &options, NULL, NULL, NO))  return nil;
	options |= extraOptions;
	path = [ResourceManager pathForFileNamed:name inFolder:folder];
	if (path == nil)
	{
		if (!(options & kOOTextureNoFNFMessage))
		{
			OOLogWARN(kOOLogFileNotFound, @"Could not find texture file \"%@\".", name);
		}
		return nil;
	}
	
	return [self loaderWithPath:path options:options];
}


- (id)initWithPath:(NSString *)inPath options:(uint32_t)options
{
	self = [super init];
	if (self == nil)  return nil;
	
	_path = [inPath copy];
	if (EXPECT_NOT(_path == nil))
	{
		[self release];
		return nil;
	}
	
	_options = options;
	
	_generateMipMaps = (options & kOOTextureMinFilterMask) == kOOTextureMinFilterMipMap;
	_avoidShrinking = (options & kOOTextureNoShrink) != 0;
	_noScalingWhatsoever = (options & kOOTextureNeverScale) != 0;
#if OO_TEXTURE_CUBE_MAP
	_allowCubeMap = (options & kOOTextureAllowCubeMap) != 0;
#endif
	
	if (options & kOOTextureExtractChannelMask)
	{
		_extractChannel = YES;
		switch (options & kOOTextureExtractChannelMask)
		{
			case kOOTextureExtractChannelR:
				_extractChannelIndex = 0;
				break;
				
			case kOOTextureExtractChannelG:
				_extractChannelIndex = 1;
				break;
				
			case kOOTextureExtractChannelB:
				_extractChannelIndex = 2;
				break;
				
			case kOOTextureExtractChannelA:
				_extractChannelIndex = 3;
				break;
				
			default:
				OOLogERR(@"texture.load.unknownExtractChannelMask", @"Unknown texture extract channel mask (0x%.4X). This is an internal error, please report it.", options & kOOTextureExtractChannelMask);
				_extractChannel =  NO;
		}
	}
	
	return self;
}


- (void)dealloc
{
	[_path autorelease];
	_path = NULL;
	free(_data);
	_data = NULL;
	
	[super dealloc];
}


- (NSString *)descriptionComponents
{
	NSString			*state = nil;
	
	if (_ready)
	{
		if (_data != NULL)  state = @"ready";
		else  state = @"failed";
	}
	else
	{
		state = @"loading";
#if INSTRUMENT_TEXTURE_LOADING
		if (debugHasLoaded)  state = @"loaded";
#endif
	}
	
	return [NSString stringWithFormat:@"{%@ -- %@}", _path, state];
}


- (NSString *)shortDescriptionComponents
{
	return [_path lastPathComponent];
}


- (NSString *)path
{
	return _path;
}


- (BOOL)isReady
{
	return _ready;
}


- (BOOL) getResult:(OOPixMap *)result
			format:(OOTextureDataFormat *)outFormat
	 originalWidth:(uint32_t *)outWidth
	originalHeight:(uint32_t *)outHeight
{
	NSParameterAssert(result != NULL && outFormat != NULL);
	
	BOOL		OK = YES;
	
	if (!_ready)
	{
		[[OOAsyncWorkManager sharedAsyncWorkManager] waitForTaskToComplete:self];
	}
	if (_data == NULL)  OK = NO;
	
	if (OK)
	{
		*result = OOMakePixMap(_data, _width, _height, OOTextureComponentsForFormat(_format), 0, 0);
		_data = NULL;
		*outFormat = _format;
		OK = OOIsValidPixMap(*result);
		if (outWidth != NULL)  *outWidth = _originalWidth;
		if (outHeight != NULL)  *outHeight = _originalHeight;
	}
	
	if (!OK)
	{
		*result = kOONullPixMap;
		*outFormat = kOOTextureDataInvalid;
	}
	
	return OK;
}


- (NSString *) cacheKey
{
	return [NSString stringWithFormat:@"%@:0x%.4X", [[self path] lastPathComponent], _options];
}


- (void)loadTexture
{
	OOLogGenericSubclassResponsibility();
}


+ (void)setUp
{
	// Load two maximum sizes - graphics hardware limit and user-specified limit.
	GLint maxSize;
	OOGL(glGetIntegerv(GL_MAX_TEXTURE_SIZE, &maxSize));
	sGLMaxSize = MAX(maxSize, 64);
	OOLog(@"texture.load.rescale.maxSize", @"GL maximum texture size: %u", sGLMaxSize);
	
	// Why 0x80000000? Because it's the biggest number OORoundUpToPowerOf2() can handle.
	sUserMaxSize = [[NSUserDefaults standardUserDefaults] oo_unsignedIntForKey:@"max-texture-size" defaultValue:0x80000000];
	if (sUserMaxSize < 0x80000000)  OOLog(@"texture.load.rescale.maxSize", @"User maximum texture size: %u", sUserMaxSize);
	sUserMaxSize = OORoundUpToPowerOf2_32(sUserMaxSize);
	sUserMaxSize = MAX(sUserMaxSize, 64U);
	
	
	sHaveSetUp = YES;
}


/*** Methods performed on the loader thread. ***/

- (void)performAsyncTask
{
	NS_DURING
		OOLog(@"texture.load.asyncLoad", @"Loading texture %@", [_path lastPathComponent]);
		
		[self loadTexture];
		
		// Catch an error I've seen but not diagnosed yet.
		if (_data != NULL && OOTextureComponentsForFormat(_format) == 0)
		{
			OOLog(@"texture.load.failed.internalError", @"Texture loader internal error for %@: data is non-null but data format is invalid (%u).", _path, _format);
			free(_data);
			_data = NULL;
		}
		
		if (_data != NULL)  [self applySettings];
		
		OOLog(@"texture.load.asyncLoad.done", @"Loading complete.");
	NS_HANDLER
		OOLog(@"texture.load.asyncLoad.exception", @"***** Exception loading texture %@: %@ (%@).", _path, [localException name], [localException reason]);
		
		// Be sure to signal load failure
		if (_data != NULL)
		{
			free(_data);
			_data = NULL;
		}
	NS_ENDHANDLER
}


- (void) generateMipMapsForCubeMap
{
	// Generate mip maps for each cube face.
	NSParameterAssert(_data != NULL);
	
	uint8_t components = OOTextureComponentsForFormat(_format);
	size_t srcSideSize = _width * _width * components;	// Space for one side without mip-maps.
	size_t newSideSize = srcSideSize * 4 / 3;			// Space for one side with mip-maps.
	newSideSize = (newSideSize + 15) & ~15;				// Round up to multiple of 16 bytes.
	size_t newSize = newSideSize * 6;					// Space for all six sides.
	
	void *newData = malloc(newSize);
	if (EXPECT_NOT(newData == NULL))
	{
		_generateMipMaps = NO;
		_options = (_options & ~kOOTextureMinFilterMask) | kOOTextureMinFilterLinear;
		return;
	}
	
	unsigned i;
	for (i = 0; i < 6; i++)
	{
		void *srcBytes = ((uint8_t *)_data) + srcSideSize * i;
		void *dstBytes = ((uint8_t *)newData) + newSideSize * i;
		
		memcpy(dstBytes, srcBytes, srcSideSize);
		OOGenerateMipMaps(dstBytes, _width, _width, _format);
	}
	
	free(_data);
	_data = newData;
}


- (void)applySettings
{
	OOPixMapDimension	desiredWidth, desiredHeight;
	BOOL				rescale;
	size_t				newSize;
	uint8_t				components;
	OOPixMap			pixMap;
	
	components = OOTextureComponentsForFormat(_format);
	
	// Apply defaults.
	if (_originalWidth == 0)  _originalWidth = _width;
	if (_originalHeight == 0)  _originalHeight = _height;
	if (_rowBytes == 0)  _rowBytes = _width * components;
	
	pixMap = OOMakePixMap(_data, _width, _height, components, _rowBytes, 0);
	
	if (_extractChannel)
	{
		if (OOExtractPixMapChannel(&pixMap, _extractChannelIndex, NO))
		{
			_format = kOOTextureDataGrayscale;
			components = 1;
		}
		else
		{
			OOLogWARN(@"texture.load.extractChannel.invalid", @"Cannot extract channel from texture \"%@\"", [_path lastPathComponent]);
		}
	}
	
	[self getDesiredWidth:&desiredWidth andHeight:&desiredHeight];
	
	if (_isCubeMap && !OOCubeMapsAvailable())
	{
		OOPixMapToRGBA(&pixMap);
		desiredHeight = MIN(desiredWidth * 2, 512U);
		if (sReducedDetail && desiredHeight > 256)  desiredHeight /= 2;
		desiredWidth = desiredHeight * 2;
		
		OOPixMap converted = OOConvertCubeMapToLatLong(pixMap, desiredHeight, _generateMipMaps);
		OOFreePixMap(&pixMap);
		pixMap = converted;
		_isCubeMap = NO;
		
#if DUMP_CONVERTED_CUBE_MAPS
		OODumpPixMap(pixMap, [NSString stringWithFormat:@"converted cube map %@", [[_path lastPathComponent] stringByDeletingPathExtension]]);
#endif
	}
	
	// Rescale if needed.
	rescale = (_width != desiredWidth || _height != desiredHeight);
	if (rescale)
	{
		BOOL leaveSpaceForMipMaps = _generateMipMaps;
#if OO_TEXTURE_CUBE_MAP
		if (_isCubeMap)  leaveSpaceForMipMaps = NO;
#endif
		
		OOLog(@"texture.load.rescale", @"Rescaling texture \"%@\" from %u x %u to %u x %u.", [_path lastPathComponent], pixMap.width, pixMap.height, desiredWidth, desiredHeight);
		
		pixMap = OOScalePixMap(pixMap, desiredWidth, desiredHeight, leaveSpaceForMipMaps);
		if (EXPECT_NOT(!OOIsValidPixMap(pixMap)))  return;
		
		_data = pixMap.pixels;
		_width = pixMap.width;
		_height = pixMap.height;
		_rowBytes = pixMap.rowBytes;
	}
	
#if OO_TEXTURE_CUBE_MAP
	if (_isCubeMap)
	{
		if (_generateMipMaps)
		{
			[self generateMipMapsForCubeMap];
		}
		return;
	}
#endif
	
	// Generate mip maps if needed.
	if (_generateMipMaps)
	{
		// Make space if needed.
		newSize = desiredWidth * components * desiredHeight;
		newSize = (newSize * 4) / 3;
		_generateMipMaps = OOExpandPixMap(&pixMap, newSize);
		
		_data = pixMap.pixels;
		_width = pixMap.width;
		_height = pixMap.height;
		_rowBytes = pixMap.rowBytes;
	}
	if (_generateMipMaps)
	{
		OOGenerateMipMaps(_data, _width, _height, _format);
	}
	
	// All done.
}


- (void)getDesiredWidth:(OOPixMapDimension *)outDesiredWidth andHeight:(OOPixMapDimension *)outDesiredHeight
{
	OOPixMapDimension	desiredWidth, desiredHeight;
	
	// Work out appropriate final size for textures.
	if (!_noScalingWhatsoever)
	{
		// Cube maps are six times as high as they are wide, and we need to preserve that.
		if (_allowCubeMap && _height == _width * 6)
		{
			_isCubeMap = YES;
			
			desiredWidth = OORoundUpToPowerOf2_PixMap((2 * _width) / 3);
			desiredWidth = MIN(desiredWidth, sGLMaxSize / 8);
			if (sReducedDetail)
			{
				if (256 < desiredWidth)  desiredWidth /= 2;
			}
			desiredWidth = MIN(desiredWidth, sUserMaxSize / 4);
			
			desiredHeight = desiredWidth * 6;
		}
		else
		{
			if (!sHaveNPOTTextures)
			{
				// Round to nearest power of two. NOTE: this is duplicated in OOTextureVerifierStage.m.
				desiredWidth = OORoundUpToPowerOf2_PixMap((2 * _width) / 3);
				desiredHeight = OORoundUpToPowerOf2_PixMap((2 * _height) / 3);
			}
			else
			{
				desiredWidth = _width;
				desiredHeight = _height;
			}
			
			desiredWidth = MIN(desiredWidth, sGLMaxSize);
			desiredHeight = MIN(desiredHeight, sGLMaxSize);
			
			if (!_avoidShrinking)
			{
				desiredWidth = MIN(desiredWidth, sUserMaxSize);
				desiredHeight = MIN(desiredHeight, sUserMaxSize);
				
				if (sReducedDetail)
				{
					if (512 < desiredWidth)  desiredWidth /= 2;
					if (512 < desiredHeight)  desiredHeight /= 2;
				}
			}
		}
	}
	else
	{
		desiredWidth = _width;
		desiredHeight = _height;
	}
	
	if (outDesiredWidth != NULL)  *outDesiredWidth = desiredWidth;
	if (outDesiredHeight != NULL)  *outDesiredHeight = desiredHeight;
}


- (void) completeAsyncTask
{
	_ready = YES;
}

@end
