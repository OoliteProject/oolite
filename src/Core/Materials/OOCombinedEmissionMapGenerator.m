/*

OOCombinedEmissionMapGenerator.m


Oolite
Copyright (C) 2004-2010 Giles C Williams and contributors

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

Copyright (C) 2010 Jens Ayton

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
#import "OOTextureChannelExtractor.h"
#import "OOTextureScaling.h"
#import "OOMaterialSpecifier.h"


#define DUMP_COMBINER	0

/*	FIXME: the "correct" way for OOCombinedEmissionMapGenerator to work is to
	run asynchronously after the source textures are loaded. However,
	OOAsyncWorkManager doesn't currently support asynchronous operation, so we
	currently need to wait for completion in the initializer.
*/
#define FAKE_ASYNCHRONY	1


static OOColor *ModulateColor(OOColor *a, OOColor *b);
static void ScaleToMatch(OOPixMap *pmA, OOPixMap *pmB);


@interface OOCombinedEmissionMapGenerator (Private)

- (id) initWithEmissionMap:(OOTexture *)emissionMap
			 emissionColor:(OOColor *)emissionColor
				diffuseMap:(OOTexture *)diffuseMap
			  diffuseColor:(OOColor *)diffuseColor
		   illuminationMap:(OOTexture *)illuminationMap
		 illuminationColor:(OOColor *)illuminationColor
			 isCombinedMap:(BOOL)isCombinedMap;

@end


@implementation OOCombinedEmissionMapGenerator

- (id) initWithEmissionMap:(OOTexture *)emissionMap
			 emissionColor:(OOColor *)emissionColor
				diffuseMap:(OOTexture *)diffuseMap
			  diffuseColor:(OOColor *)diffuseColor
		   illuminationMap:(OOTexture *)illuminationMap
		 illuminationColor:(OOColor *)illuminationColor
{
	return [self initWithEmissionMap:emissionMap
					   emissionColor:emissionColor
						  diffuseMap:diffuseMap
						diffuseColor:diffuseColor
					 illuminationMap:illuminationMap
				   illuminationColor:illuminationColor
					   isCombinedMap:NO];
}


- (id) initWithEmissionAndIlluminationMap:(OOTexture *)emissionAndIlluminationMap
							   diffuseMap:(OOTexture *)diffuseMap
							 diffuseColor:(OOColor *)diffuseColor
							emissionColor:(OOColor *)emissionColor
						illuminationColor:(OOColor *)illuminationColor
{
	return [self initWithEmissionMap:emissionAndIlluminationMap
					   emissionColor:emissionColor
						  diffuseMap:diffuseMap
						diffuseColor:diffuseColor
					 illuminationMap:nil
				   illuminationColor:illuminationColor
					   isCombinedMap:YES];
}


- (id) initWithEmissionMap:(OOTexture *)emissionMap
			 emissionColor:(OOColor *)emissionColor
				diffuseMap:(OOTexture *)diffuseMap
			  diffuseColor:(OOColor *)diffuseColor
		   illuminationMap:(OOTexture *)illuminationMap
		 illuminationColor:(OOColor *)illuminationColor
			 isCombinedMap:(BOOL)isCombinedMap
{
	if (emissionMap == nil && illuminationMap == nil)
	{
		[self release];
		return nil;
	}
	
	NSParameterAssert(illuminationMap == nil || !isCombinedMap);
	
	if ((self = [super init]))
	{
		/*	Illumination contribution is:
			illuminationMap * illuminationColor * diffuseMap * diffuseColor
			Since illuminationColor and diffuseColor aren't used otherwise,
			we may as well combine them up front.
		*/
		illuminationColor = ModulateColor(diffuseColor, illuminationColor);
										  
		if ([emissionColor isWhite])  emissionColor = nil;
		if ([illuminationColor isWhite])  illuminationColor = nil;
		if (!isCombinedMap && illuminationMap == nil)  diffuseMap = nil;	// Diffuse map is only used with illumination
		
		_emissionMap = [emissionMap retain];
		_illuminationMap = [illuminationMap retain];
		_emissionColor = [emissionColor retain];
		_illuminationColor = [illuminationColor retain];
		_diffuseMap = [diffuseMap retain];
		_isCombinedMap = isCombinedMap;
		
#if FAKE_ASYNCHRONY
		[_emissionMap ensureFinishedLoading];
		[_illuminationMap ensureFinishedLoading];
		[_diffuseMap ensureFinishedLoading];
#endif
	}
	
	return self;
}


- (void) dealloc
{
	DESTROY(_emissionMap);
	DESTROY(_illuminationMap);
	DESTROY(_diffuseMap);
	DESTROY(_emissionColor);
	DESTROY(_illuminationColor);
	
	[super dealloc];
}


- (NSString *) descriptionComponents
{
	NSMutableString *result = [NSMutableString string];
	BOOL haveIllumination = NO;
	
	if (_emissionMap != nil)
	{
		[result appendFormat:@"emission map: %@", [_emissionMap shortDescription]];
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
			[result appendFormat:@", illumination map: %@.a", [_emissionMap shortDescription]];
			haveIllumination = YES;
		}
	}
	
	if (_illuminationMap != nil)
	{
		if (_emissionMap != nil)  [result appendString:@", "];
		[result appendFormat:@"illumination map: %@", [_illuminationMap shortDescription]];
		haveIllumination = YES;
	}
	
	if (haveIllumination)
	{
		if (_diffuseMap != nil)
		{
			[result appendFormat:@" * %@", [_diffuseMap shortDescription]];
		}
		if (_illuminationColor != nil)
		{
			[result appendFormat:@" * %@", [_illuminationColor rgbaDescription]];
		}
	}
	
	return result;
}


- (NSString *) cacheKey
{
	return [NSString stringWithFormat:@"Combined emission map\nSingle source: %@\nemission:%@ * %@, illumination: %@ * %@ * %@", _isCombinedMap ? @"yes" : @"no", [_emissionMap cacheKey], [_emissionColor rgbaDescription],[_illuminationMap cacheKey], [_diffuseMap cacheKey], [_illuminationColor rgbaDescription]];
}


- (void) loadTexture
{
	OOPixMap emissionPx = kOONullPixMap, diffusePx = kOONullPixMap, illuminationPx = kOONullPixMap;
	BOOL haveEmission = NO, haveIllumination = NO, haveDiffuse = NO;
	
#if DUMP_COMBINER
	static unsigned sTexID = 0;
	unsigned texID = ++sTexID, dumpCount = 0;
	
#define DUMP(pm, label) OODumpPixMap(pm, [NSString stringWithFormat:@"envmap %u.%u - %@", texID, ++dumpCount, label]);
#else
#define DUMP(pm, label) do {} while (0)
#endif
	
	// Load emission map.
	if (_emissionMap != nil)
	{
#if !FAKE_ASYNCHRONY
		[_emissionMap ensureFinishedLoading];
#endif
		emissionPx = [_emissionMap copyPixMapRepresentation];
		DESTROY(_emissionMap);
		haveEmission = !OOIsNullPixMap(emissionPx);
		DUMP(emissionPx, @"source emission map");
	}
	
	// Extract illumination component if emission_and_illumination_map.
	if (haveEmission && _isCombinedMap && emissionPx.components > 1)
	{
		OOPixMapToRGBA(&emissionPx);
		illuminationPx = OODuplicatePixMap(emissionPx, 0);
		OOExtractPixMapChannel(&illuminationPx, 3, YES);
		haveIllumination = YES;
		DUMP(illuminationPx, @"extracted illumination map");
	}
	
	// Tint if necessary.
	if (haveEmission && _emissionColor != nil)
	{
		OOPixMapModulateUniform(&emissionPx, [_emissionColor redComponent], [_emissionColor greenComponent], [_emissionColor blueComponent], 1.0);
		DUMP(emissionPx, @"modulated emission map");
	}
	
	// Load and tint illumination map.
	if (_illuminationMap != nil)
	{
		NSAssert(!_isCombinedMap, @"OOCombinedEmissionMapGenerator configured with both illumination map and combined emission/illumination map.");
		
#if !FAKE_ASYNCHRONY
		[_illuminationMap ensureFinishedLoading];
#endif
		illuminationPx = [_illuminationMap copyPixMapRepresentation];
		DESTROY(_illuminationMap);
		haveIllumination = !OOIsNullPixMap(illuminationPx);	// This will be true for both separate and combined illumination maps.
		DUMP(illuminationPx, @"source illumination map");
	}
	
	if (haveIllumination && _illuminationColor != nil)
	{
		OOPixMapModulateUniform(&illuminationPx, [_illuminationColor redComponent], [_illuminationColor greenComponent], [_illuminationColor blueComponent], 1.0);
		DUMP(illuminationPx, @"modulated illumination map");
	}
	
	// Load diffuse map and combine with illumination map.
	if (_diffuseMap != nil)
	{
#if !FAKE_ASYNCHRONY
		[_diffuseMap ensureFinishedLoading];
#endif
		diffusePx = [_diffuseMap copyPixMapRepresentation];
		DESTROY(_diffuseMap);
		haveDiffuse = !OOIsNullPixMap(diffusePx);
		DUMP(diffusePx, @"source diffuse map");
	}
	
	if (haveIllumination && haveDiffuse)
	{
		// Modulate illumination with diffuse map.
		ScaleToMatch(&diffusePx, &illuminationPx);
		OOPixMapToRGBA(&diffusePx);
		OOPixMapModulatePixMap(&illuminationPx, diffusePx);
		DUMP(illuminationPx, @"combined diffuse and illumination map");
	}
	OOFreePixMap(&diffusePx);
	
	if (haveIllumination && haveEmission)
	{
		OOPixMapToRGBA(&illuminationPx);
		OOPixMapAddPixMap(&emissionPx, illuminationPx);
		OOFreePixMap(&illuminationPx);
		DUMP(emissionPx, @"combined emission and illumination map");
	}
	else if (haveIllumination)
	{
		emissionPx = illuminationPx;
		illuminationPx.pixels = NULL;
	}
	
	// Done: emissionPx now contains combined emission map.
	OOCompactPixMap(&emissionPx);
	if (OOIsValidPixMap(emissionPx))
	{
		data = emissionPx.pixels;
		width = emissionPx.width;
		height = emissionPx.height;
		rowBytes = emissionPx.rowBytes;
		switch (emissionPx.components)
		{
			case 1:
				format = kOOTextureDataGrayscale;
				break;
				
			case 2:
				format = kOOTextureDataGrayscaleAlpha;
				break;
				
			case 4:
				format = kOOTextureDataRGBA;
				break;
				
			default:
				OOLogERR(@"texture.combinedEmissionMap.error", @"Unexepected component count %u for %@", emissionPx.components, self);
				data = NULL;
		}
	}
	if (data == NULL)
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
		OOScalePixMap(*pmA, minWidth, minHeight, NO);
	}
	if (pmB->width != minWidth || pmB->height != minHeight)
	{
		OOScalePixMap(*pmB, minWidth, minHeight, NO);
	}
}
