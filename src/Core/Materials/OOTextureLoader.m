/*

OOTextureLoader.m

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


This file may also be distributed under the MIT/X11 license:

Copyright (C) 2007-2009 Jens Ayton

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

#import "OOTextureLoader.h"
#import "OOPNGTextureLoader.h"
#import "OOFunctionAttributes.h"
#import "OOCollectionExtractors.h"
#import "OOMaths.h"
#import "Universe.h"
#import "OOTextureScaling.h"
#import <stdlib.h>


static unsigned				sGLMaxSize;
static uint32_t				sUserMaxSize;
static BOOL					sReducedDetail;
static BOOL					sHaveNPOTTextures = NO;	// TODO: support "true" non-power-of-two textures.
static BOOL					sHaveSetUp = NO;


@interface OOTextureLoader (OOPrivate)

+ (void)setUp;

- (void)applySettings;
- (void)getDesiredWidth:(uint32_t *)outDesiredWidth andHeight:(uint32_t *)outDesiredHeight;


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
		OOLog(@"textureLoader.unknownType", @"Can't use %@ as a texture - extension \"%@\" does not identify a known type.", inPath, extension);
	}
	
	if (result != nil)
	{
		if (![[OOAsyncWorkManager sharedAsyncWorkManager] addTask:result priority:kOOAsyncPriorityMedium])  result = nil;
	}
	
	return result;
}


- (id)initWithPath:(NSString *)inPath options:(uint32_t)options
{
	self = [super init];
	if (self == nil)  return nil;
	
	path = [inPath copy];
	if (EXPECT_NOT(path == nil))
	{
		[self release];
		return nil;
	}
	
	generateMipMaps = (options & kOOTextureMinFilterMask) == kOOTextureMinFilterMipMap;
	avoidShrinking = (options & kOOTextureNoShrink) != 0;
	noScalingWhatsoever = (options & kOOTextureNeverScale) != 0;
#if GL_ARB_texture_cube_map
	allowCubeMap = (options & kOOTextureAllowCubeMap) != 0;
#endif
	
	return self;
}


- (void)dealloc
{
	[path autorelease];
	if (data != NULL)  free(data);
	
	[super dealloc];
}


- (NSString *)descriptionComponents
{
	NSString			*state = nil;
	
	if (ready)
	{
		if (data != NULL)  state = @"ready";
		else  state = @"failed";
	}
	else
	{
		state = @"loading";
#if INSTRUMENT_TEXTURE_LOADING
		if (debugHasLoaded)  state = @"loaded";
#endif
	}
	
	return [NSString stringWithFormat:@"{%@ -- %@}", path, state];
}


- (NSString *)shortDescriptionComponents
{
	return [path lastPathComponent];
}


- (NSString *)path
{
	return path;
}


- (BOOL)isReady
{
	return ready;
}


- (BOOL)getResult:(void **)outData
		   format:(OOTextureDataFormat *)outFormat
			width:(uint32_t *)outWidth
		   height:(uint32_t *)outHeight
{
	if (!ready)
	{
		[[OOAsyncWorkManager sharedAsyncWorkManager] waitForTaskToComplete:self];
	}
	
	if (data != NULL)
	{
		if (outData != NULL)  *outData = data;
		if (outFormat != NULL)  *outFormat = format;
		if (outWidth != NULL)  *outWidth = width;
		if (outHeight != NULL)  *outHeight = height;
		
		data = NULL;
		return YES;
	}
	else
	{
		if (outData != NULL)  *outData = NULL;
		if (outFormat != NULL)  *outFormat = kOOTextureDataInvalid;
		if (outWidth != NULL)  *outWidth = 0;
		if (outHeight != NULL)  *outHeight = 0;
		
		return NO;
	}
}


- (void)loadTexture
{
	OOLogGenericSubclassResponsibility();
}


+ (void)setUp
{
	// Load two maximum sizes - graphics hardware limit and user-specified limit.
	GLint maxSize;
	glGetIntegerv(GL_MAX_TEXTURE_SIZE, &maxSize);
	sGLMaxSize = MAX(maxSize, 64);
	
	// Why 0x80000000? Because it's the biggest number OORoundUpToPowerOf2() can handle.
	sUserMaxSize = [[NSUserDefaults standardUserDefaults] oo_unsignedIntForKey:@"max-texture-size" defaultValue:0x80000000];
	sUserMaxSize = OORoundUpToPowerOf2(sUserMaxSize);
	sUserMaxSize = MAX(sUserMaxSize, 64U);
	
	sHaveSetUp = YES;
}


/*** Methods performed on the loader thread. ***/

- (void)performAsyncTask
{
	NS_DURING
		OOLog(@"textureLoader.asyncLoad", @"Loading texture %@", [path lastPathComponent]);
		
		[self loadTexture];
		if (data != NULL)  [self applySettings];
		
		OOLog(@"textureLoader.asyncLoad.done", @"Loading complete.");
	NS_HANDLER
		OOLog(@"textureLoader.asyncLoad.exception", @"***** Exception loading texture %@: %@ (%@).", path, [localException name], [localException reason]);
		
		// Be sure to signal load failure
		if (data != NULL)
		{
			free(data);
			data = NULL;
		}
	NS_ENDHANDLER
}


- (void) generateMipMapsForCubeMap
{
	// Generate mip maps for each cube face.
	NSParameterAssert(data != NULL);
	
	uint8_t planes = OOTexturePlanesForFormat(format);
	size_t srcSideSize = width * width * planes;	// Space for one side without mip-maps.
	size_t newSideSize = srcSideSize * 4 / 3;		// Space for one side with mip-maps.
	newSideSize = (newSideSize + 15) & ~15;			// Round up to multiple of 16 bytes.
	size_t newSize = newSideSize * 6;				// Space for all six sides.
	
	void *newData = malloc(newSize);
	if (EXPECT_NOT(newData == NULL))
	{
		free(data);
		data = NULL;
	}
	
	unsigned i;
	for (i = 0; i < 6; i++)
	{
		void *srcBytes = ((uint8_t *)data) + srcSideSize * i;
		void *dstBytes = ((uint8_t *)newData) + newSideSize * i;
		
		memcpy(dstBytes, srcBytes, srcSideSize);
		OOGenerateMipMaps(dstBytes, width, width, planes);
	}
	
	free(data);
	data = newData;
}


- (void)applySettings
{
	uint32_t			desiredWidth, desiredHeight;
	BOOL				rescale;
	void				*newData = NULL;
	size_t				newSize;
	uint8_t				planes;
	
	planes = OOTexturePlanesForFormat(format);
	
	if (rowBytes == 0)  rowBytes = width * planes;
	[self getDesiredWidth:&desiredWidth andHeight:&desiredHeight];
	
	// Rescale if needed.
	rescale = (width != desiredWidth || height != desiredHeight);
	if (rescale)
	{
		BOOL leaveSpaceForMipMaps = generateMipMaps;
#if GL_ARB_texture_cube_map
		if (isCubeMap)  leaveSpaceForMipMaps = NO;
#endif
		
		data = OOScalePixMap(data, width, height, planes, rowBytes, desiredWidth, desiredHeight, leaveSpaceForMipMaps);
		if (EXPECT_NOT(data == NULL))  return;
		
		width = desiredWidth;
		height = desiredHeight;
	}
	
#if GL_ARB_texture_cube_map
	if (isCubeMap)
	{
		if (generateMipMaps)
		{
			[self generateMipMapsForCubeMap];
		}
		return;
	}
#endif
	
	// Generate mip maps if needed.
	if (generateMipMaps && !rescale)
	{
		// Make space...
		newSize = desiredWidth * planes * desiredHeight;
		newSize = (newSize * 4) / 3;
		newData = realloc(data, newSize);
		if (newData != nil)  data = newData;
		else  generateMipMaps = NO;
	}
	if (generateMipMaps)
	{
		OOGenerateMipMaps(data, width, height, planes);
	}
	
	// All done.
}


- (void)getDesiredWidth:(uint32_t *)outDesiredWidth andHeight:(uint32_t *)outDesiredHeight
{
	uint32_t			desiredWidth, desiredHeight;
	
	// Work out appropriate final size for textures.
	if (!noScalingWhatsoever)
	{
#if GL_ARB_texture_cube_map
		// Cube maps are six times as high as they are wide, and we need to preserve that.
		// FIXME: should convert cube maps to lat/long maps here if cube map support not available!
		if (allowCubeMap && height == width * 6)
		{
			isCubeMap = YES;
			
			desiredWidth = OORoundUpToPowerOf2((2 * width) / 3);
			desiredWidth = MIN(desiredWidth, sGLMaxSize / 8);
			if (sReducedDetail)
			{
				if (256 < desiredWidth)  desiredWidth /= 2;
			}
			desiredWidth = MIN(desiredWidth, sUserMaxSize / 4);
			
			desiredHeight = desiredWidth * 6;
		}
		else
#endif
		{
			if (!sHaveNPOTTextures)
			{
				// Round to nearest power of two. NOTE: this is duplicated in OOTextureVerifierStage.m.
				desiredWidth = OORoundUpToPowerOf2((2 * width) / 3);
				desiredHeight = OORoundUpToPowerOf2((2 * height) / 3);
			}
			else
			{
				desiredWidth = width;
				desiredHeight = height;
			}
			
			desiredWidth = MIN(desiredWidth, sGLMaxSize);
			desiredHeight = MIN(desiredHeight, sGLMaxSize);
			
			if (!avoidShrinking)
			{
				desiredWidth = MIN(desiredWidth, sUserMaxSize);
				desiredHeight = MIN(desiredHeight, sUserMaxSize);
				
				if (sReducedDetail)
				{
					if (512 < desiredWidth)  desiredWidth /= 2;
					if (512 < desiredHeight)  desiredHeight /= 2;
				}
			}
			else
			{
				if (sReducedDetail || sUserMaxSize < desiredWidth || sUserMaxSize < desiredWidth)
				{
					// Permit a bit of shrinking for large textures
					if (512 < desiredWidth)  desiredWidth /= 2;
					if (512 < desiredHeight)  desiredHeight /= 2;
				}
			}
		}
	}
	else
	{
		desiredWidth = width;
		desiredHeight = height;
	}
	
	if (outDesiredWidth != NULL)  *outDesiredWidth = desiredWidth;
	if (outDesiredHeight != NULL)  *outDesiredHeight = desiredHeight;
}


- (void) completeAsyncTask
{
	ready = YES;
}

@end
