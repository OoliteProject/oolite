/*

OOTextureScaling.m

Oolite
Copyright (C) 2004-2007 Giles C Williams and contributors

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

Copyright (C) 2007 Jens Ayton

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/


// Temporarily disabled build flags: -O3 -falign-loops=32 -falign-loops-max-skip=31


#import "OOTextureScaling.h"
#import "OOFunctionAttributes.h"
#import <stdlib.h>
#import "OOLogging.h"
#import "OOMaths.h"
#import "OOCPUInfo.h"


// #define DUMP_MIP_MAPS


// Structure used to track buffers in OOScalePixMap() and its helpers.
typedef struct
{
	void					*pixels;
	OOTextureDimension		width, height;
	size_t					rowBytes;
	size_t					dataSize;
} OOScalerPixMap;


/*	Internal function declarations.
	
	NOTE: the function definitions are grouped together for best code cache
	coherence rather than the order listed here.
*/
static BOOL GenerateMipMaps1(void *textureBytes, OOTextureDimension width, OOTextureDimension height) NONNULL_FUNC;
static BOOL GenerateMipMaps4(void *textureBytes, OOTextureDimension width, OOTextureDimension height) NONNULL_FUNC;

static void ScaleDownByHalvingInPlace1(OOScalerPixMap *srcPx, OOTextureDimension dstWidth, OOTextureDimension dstHeight) NONNULL_FUNC;
static void ScaleDownByHalvingInPlace4(OOScalerPixMap *srcPx, OOTextureDimension dstWidth, OOTextureDimension dstHeight) NONNULL_FUNC;


/*	ScaleToHalf_P_xN functions
	These scale a texture with P planes (components) to half its size in each
	dimension, handling N pixels at a time. srcWidth must be a multiple of N.
	Parameters are not validated -- bad parameters will lead to bad data or a
	crash.
	
	Scaling is an unweighted average. 8 bits per channel assumed.
	It is safe and meaningful for srcBytes == dstBytes.
*/
static void ScaleToHalf_1_x1(void *srcBytes, void *dstBytes, OOTextureDimension srcWidth, OOTextureDimension srcHeight) NONNULL_FUNC;
static void ScaleToHalf_4_x1(void *srcBytes, void *dstBytes, OOTextureDimension srcWidth, OOTextureDimension srcHeight) NONNULL_FUNC;

#if OOLITE_NATIVE_64_BIT
	static void ScaleToHalf_1_x8(void *srcBytes, void *dstBytes, OOTextureDimension srcWidth, OOTextureDimension srcHeight) NONNULL_FUNC;
	static void ScaleToHalf_4_x2(void *srcBytes, void *dstBytes, OOTextureDimension srcWidth, OOTextureDimension srcHeight) NONNULL_FUNC;
#else
	static void ScaleToHalf_1_x4(void *srcBytes, void *dstBytes, OOTextureDimension srcWidth, OOTextureDimension srcHeight) NONNULL_FUNC;
#endif


OOINLINE void StretchVertically(OOScalerPixMap srcPx, OOScalerPixMap dstPx, OOTexturePlaneCount planes) ALWAYS_INLINE_FUNC;

static void StretchVerticallyN_x1(OOScalerPixMap srcPx, OOScalerPixMap dstPx, OOTexturePlaneCount planes);

static void SqueezeVertically4(OOScalerPixMap srcPx, OOTextureDimension dstHeight);
static void SqueezeVertically1(OOScalerPixMap srcPx, OOTextureDimension dstHeight);
static void StretchHorizontally1(OOScalerPixMap srcPx, OOScalerPixMap dstPx);
static void StretchHorizontally4(OOScalerPixMap srcPx, OOScalerPixMap dstPx);
static void SqueezeHorizontally4(OOScalerPixMap srcPx, OOTextureDimension dstWidth);
static void SqueezeHorizontally1(OOScalerPixMap srcPx, OOTextureDimension dstWidth);


static void EnsureCorrectDataSize(OOScalerPixMap *pixMap, BOOL leaveSpaceForMipMaps) NONNULL_FUNC;


#if !OOLITE_NATIVE_64_BIT

static void StretchVerticallyN_x4(OOScalerPixMap srcPx, OOScalerPixMap dstPx, OOTexturePlaneCount planes);

OOINLINE void StretchVertically(OOScalerPixMap srcPx, OOScalerPixMap dstPx, OOTexturePlaneCount planes)
{
	if (!((srcPx.rowBytes) & 3))
	{
		StretchVerticallyN_x4(srcPx, dstPx, planes);
	}
	else
	{
		StretchVerticallyN_x1(srcPx, dstPx, planes);
	}
}

#else	// OOLITE_NATIVE_64_BIT

static void StretchVerticallyN_x8(OOScalerPixMap srcPx, OOScalerPixMap dstPx, OOTexturePlaneCount planes);

OOINLINE void StretchVertically(OOScalerPixMap srcPx, OOScalerPixMap dstPx, OOTexturePlaneCount planes)
{
	if (!((srcPx.rowBytes) & 7))
	{
		StretchVerticallyN_x8(srcPx, dstPx, planes);
	}
	else
	{
		StretchVerticallyN_x1(srcPx, dstPx, planes);
	}
}

#endif


#ifdef DUMP_MIP_MAPS
// NOTE: currently only works on OS X because of OTAtomicAdd32() (used to increment ID counter in thread-safe way). A simple increment would be sufficient if limited to a single thread (in OOTextureLoader).
SInt32 sPreviousDumpID		= 0;

#define	DUMP_CHANNELS		1		// Bitmap of channel counts - 5 for both 4-chan and 1-chan dumps

#define DUMP_MIP_MAP_PREPARE(pl)		uint32_t dumpPlanes = pl; \
										uint32_t dumpLevel = 0; \
										BOOL dumpThis = (dumpPlanes & DUMP_CHANNELS) != 0; \
										SInt32 dumpID = dumpThis ? OTAtomicAdd32(1, &sPreviousDumpID) : 0; \
										if (dumpThis) OOLog(@"texture.mipMap.dump", @"Dumping mip-maps as dump ID%u lv# %uch XxY.raw.", dumpID, dumpPlanes);
#define DUMP_MIP_MAP_DUMP(px, w, h)		if (dumpThis) DumpMipMap(px, w, h, dumpPlanes, dumpID, dumpLevel++);
static void DumpMipMap(void *data, OOTextureDimension width, OOTextureDimension height, OOTexturePlaneCount planes, SInt32 ID, uint32_t level);
#else
#define DUMP_MIP_MAP_PREPARE(pl)		do {} while (0)
#define DUMP_MIP_MAP_DUMP(px, w, h)		do {} while (0)
#endif


void *OOScalePixMap(void *srcPixels, OOTextureDimension srcWidth, OOTextureDimension srcHeight, OOTexturePlaneCount planes, size_t srcRowBytes, OOTextureDimension dstWidth, OOTextureDimension dstHeight, BOOL leaveSpaceForMipMaps)
{
	BOOL				haveScaled = NO;
	OOScalerPixMap		srcPx, dstPx = {0}, sparePx = {0};
	
	//	Sanity check.
	if (EXPECT_NOT(srcPixels == NULL || (planes != 4 && planes != 1) || (srcRowBytes < srcWidth * planes)))
	{
		OOLogGenericParameterError();
		free(srcPixels);
		return NULL;
	}
	
	srcPx.pixels = srcPixels;
	srcPx.width = srcWidth;
	srcPx.height = srcHeight;
	srcPx.rowBytes = srcRowBytes;
	srcPx.dataSize = srcRowBytes * srcHeight;
	
	/*	If src is at least twice as big as dst in both dimensions, scale using
		MIP map scalers (which provide better quality than the linear
		downscaler at this scale).
		
		This will do all the scaling in some cases when scaling down large
		textures to meet user or hardware requirements or for big textures in
		reduced-detail mode.
	*/
	if (EXPECT_NOT(dstWidth * 2 <= srcWidth && dstHeight * 2 <= srcHeight))
	{
		if (planes == 4)  ScaleDownByHalvingInPlace4(&srcPx, dstWidth, dstHeight);
		else /* planes == 1 */  ScaleDownByHalvingInPlace1(&srcPx, dstWidth, dstHeight);
		
		haveScaled = YES;
	}
	
	/*	If we were called with src == dst or the use of the MIP map scalers
		was sufficient, resize buffer if needed and return.
	*/
	if (EXPECT_NOT(srcWidth == dstWidth && srcHeight == dstHeight))
	{
		if (leaveSpaceForMipMaps)
		{
			dstPx.pixels = realloc(srcPx.pixels, dstWidth * dstHeight * planes * 4 / 3);
			if (EXPECT_NOT(dstPx.pixels == NULL))  free(srcPx.pixels);
		}
		else if (haveScaled)
		{
			dstPx.pixels = realloc(srcPx.pixels, dstWidth * dstHeight * planes);
			if (EXPECT_NOT(dstPx.pixels == NULL))  free(srcPx.pixels);
		}
		else
		{
			dstPx.pixels = srcPx.pixels;
		}
		return dstPx.pixels;
	}
	
	if (srcHeight < dstHeight)
	{
		// Stretch vertically. This requires a separate buffer.
		dstPx.width = srcPx.width;	// Not dstWidth!
		dstPx.height = dstHeight;
		dstPx.rowBytes = srcPx.width * planes;
		dstPx.dataSize = dstPx.rowBytes * dstPx.height;
		if (leaveSpaceForMipMaps && dstWidth <= srcWidth)  dstPx.dataSize = dstPx.dataSize * 4 / 3;
		dstPx.pixels = malloc(dstPx.dataSize);
		if (EXPECT_NOT(dstPx.pixels == NULL))  goto FAIL;
		
		StretchVertically(srcPx, dstPx, planes);
		
		sparePx = srcPx;
		srcPx = dstPx;
	}
	else if (dstHeight < srcHeight)
	{
		// Squeeze vertically. This can be done in-place.
		if (planes == 4)  SqueezeVertically4(srcPx, dstHeight);
		else /* planes == 1 */  SqueezeVertically1(srcPx, dstHeight);
		srcPx.height = dstHeight;
	}
	
	if (srcWidth < dstWidth)
	{
		// Stretch horizontally. This requires a separate buffer.
		dstPx.height = srcPx.height;
		dstPx.width = dstWidth;
		dstPx.rowBytes = dstPx.width * planes;
		dstPx.dataSize = dstPx.rowBytes * srcPx.height;
		if (leaveSpaceForMipMaps)  dstPx.dataSize = dstPx.dataSize * 4 / 3;
		if (dstPx.dataSize <= sparePx.dataSize)
		{
			dstPx.pixels = sparePx.pixels;
			dstPx.dataSize = sparePx.dataSize;
		}
		else
		{
			free(sparePx.pixels);
			sparePx.pixels = NULL;
			dstPx.pixels = malloc(dstPx.dataSize);
			if (EXPECT_NOT(dstPx.pixels == NULL))  goto FAIL;
		}
		
		if (planes == 4)  StretchHorizontally4(srcPx, dstPx);
		else /* planes == 1 */  StretchHorizontally1(srcPx, dstPx);
	}
	else if (dstWidth < srcWidth)
	{
		// Squeeze horizontally. This can be done in-place.
		if (planes == 4)  SqueezeHorizontally4(srcPx, dstWidth);
		else /* planes == 1 */  SqueezeHorizontally1(srcPx, dstWidth);
		
		dstPx = srcPx;
		dstPx.width = dstWidth;
		dstPx.rowBytes = dstPx.width * planes;
	}
	else
	{
		// No horizontal scaling.
		dstPx = srcPx;
	}
	
	// dstPx is now the result.
	EnsureCorrectDataSize(&dstPx, leaveSpaceForMipMaps);
	
FAIL:
	if (srcPx.pixels != NULL && srcPx.pixels != dstPx.pixels)  free(srcPx.pixels);
	if (sparePx.pixels != NULL && sparePx.pixels != dstPx.pixels && sparePx.pixels != srcPx.pixels)  free(sparePx.pixels);
	
	return dstPx.pixels;
}


BOOL OOGenerateMipMaps(void *textureBytes, OOTextureDimension width, OOTextureDimension height, OOTexturePlaneCount planes)
{
	if (EXPECT_NOT(width != OORoundUpToPowerOf2(width) || height != OORoundUpToPowerOf2(height)))
	{
		OOLog(kOOLogParameterError, @"Non-power-of-two dimensions (%ux%u) passed to %s() - ignoring, data will be junk.", width, height, __FUNCTION__);
		return NO;
	}
	if (EXPECT_NOT(textureBytes == NULL))
	{
		OOLog(kOOLogParameterError, @"NULL texutre pointer passed to GenerateMipMaps().");
		return NO;
	}
	
	// In order of likelyhood, for very small optimization.
	if (planes == 4)  return GenerateMipMaps4(textureBytes, width, height);
	if (planes == 1)  return GenerateMipMaps1(textureBytes, width, height);
	
	OOLog(kOOLogParameterError, @"%s(): bad plane count (%u, should be 1 or 4) - ignoring, data will be junk.", __FUNCTION__, planes);
	return NO;
}


static BOOL GenerateMipMaps1(void *textureBytes, OOTextureDimension width, OOTextureDimension height)
{
	OOTextureDimension		w = width, h = height;
	uint8_t					*curr, *next;
	
	DUMP_MIP_MAP_PREPARE(1);
	curr = textureBytes;
	
#if OOLITE_NATIVE_64_BIT
	while (8 < w && 1 < h)
	{
		DUMP_MIP_MAP_DUMP(curr, w, h);
		
		next = curr + w * h;
		ScaleToHalf_1_x8(curr, next, w, h);
		
		w >>= 1;
		h >>= 1;
		curr = next;
	}
#else
	while (4 < w && 1 < h)
	{
		DUMP_MIP_MAP_DUMP(curr, w, h);
		
		next = curr + w * h;
		ScaleToHalf_1_x4(curr, next, w, h);
		
		w >>= 1;
		h >>= 1;
		curr = next;
	}
#endif
	
	while (1 < w && 1 < h)
	{
		DUMP_MIP_MAP_DUMP(curr, w, h);
		
		next = curr + w * h;
		ScaleToHalf_1_x1(curr, next, w, h);
		
		w >>= 1;
		h >>= 1;
		curr = next;
	}
	
	DUMP_MIP_MAP_DUMP(curr, w, h);
	
	// TODO: handle residual 1xN/Nx1 mips. For now, we just limit maximum mip level for non-square textures.
	return YES;
}


static void ScaleToHalf_1_x1(void *srcBytes, void *dstBytes, OOTextureDimension srcWidth, OOTextureDimension srcHeight)
{
	OOTextureDimension		x, y;
	uint8_t					*src0, *src1, *dst;
	uint_fast8_t			px00, px01, px10, px11;
	uint_fast16_t			sum;
	
	src0 = srcBytes;
	src1 = src0 + srcWidth;
	dst = dstBytes;
	
	y = srcHeight >> 1;
	do
	{
		x = srcWidth >> 1;
		do
		{
			// Read four pixels in a square...
			px00 = *src0++;
			px01 = *src0++;
			px10 = *src1++;
			px11 = *src1++;
			
			// ...add them together...
			sum = px00 + px01 + px10 + px11;
			
			// ...shift the sum into place...
			sum >>= 2;
			
			// ...and write output pixel.
				*dst++ = sum;
		} while (--x);
		
		// Skip a row for each source row
		src0 = src1;
		src1 += srcWidth;
	} while (--y);
}


#if !OOLITE_NATIVE_64_BIT

static void ScaleToHalf_1_x4(void *srcBytes, void *dstBytes, OOTextureDimension srcWidth, OOTextureDimension srcHeight)
{
	OOTextureDimension		x, y;
	uint32_t				*src0, *src1, *dst;
	uint_fast32_t			px00, px01, px10, px11;
	uint_fast32_t			sum0, sum1;
	
	srcWidth >>= 2;	// Four (output) pixels at a time
	src0 = srcBytes;
	src1 = src0 + srcWidth;
	dst = dstBytes;
	
	y = srcHeight >> 1;
	do
	{
		x = srcWidth >> 1;
		do
		{
			// Read 8 pixels in a 4x2 rectangle...
			px00 = *src0++;
			px01 = *src0++;
			px10 = *src1++;
			px11 = *src1++;
			
			// ...add them together.
			sum0 =	(px00 & 0x00FF00FF) +
					(px10 & 0x00FF00FF) +
					((px00 & 0xFF00FF00) >> 8) +
					((px10 & 0xFF00FF00) >> 8);
			sum1 =	(px01 & 0x00FF00FF) +
					(px11 & 0x00FF00FF) +
					((px01 & 0xFF00FF00) >> 8) +
					((px11 & 0xFF00FF00) >> 8);
			
			// ...swizzle the sums around...
#if OOLITE_BIG_ENDIAN
			sum0 = ((sum0 << 6) & 0xFF000000) | ((sum0 << 14) & 0x00FF0000);
			sum1 = ((sum1 >> 10) & 0x0000FF00) | ((sum1 >>2) & 0x000000FF);
#elif OOLITE_LITTLE_ENDIAN
			sum0 = ((sum0 >> 10) & 0x0000FF00) | ((sum0 >>2) & 0x000000FF);
			sum1 = ((sum1 << 6) & 0xFF000000) | ((sum1 << 14) & 0x00FF0000);
#else
			#error Neither OOLITE_BIG_ENDIAN nor OOLITE_LITTLE_ENDIAN is defined as nonzero!
#endif
			
			// ...and write output pixel.
				*dst++ = sum0 | sum1;
		} while (--x);
		
		// Skip a row for each source row
		src0 = src1;
		src1 += srcWidth;
	} while (--y);
}

#else	// OOLITE_NATIVE_64_BIT

static void ScaleToHalf_1_x8(void *srcBytes, void *dstBytes, OOTextureDimension srcWidth, OOTextureDimension srcHeight)
{
	OOTextureDimension		x, y;
	uint64_t				*src0, *src1;
	uint64_t				*dst;
	uint_fast64_t			px00, px01, px10, px11;
	uint_fast64_t			sum0, sum1;
	
	srcWidth >>= 3;	// Eight (output) pixels at a time
	src0 = srcBytes;
	src1 = src0 + srcWidth;
	dst = dstBytes;
	
	y = srcHeight >> 1;
	do
	{
		x = srcWidth >> 1;
		do
		{
			// Read 16 pixels in an 8x2 rectangle...
			px00 = *src0++;
			px01 = *src0++;
			px10 = *src1++;
			px11 = *src1++;
			
			// ...add them together...
			sum0 =	((px00 & 0x00FF00FF00FF00FFULL)) +
					((px10 & 0x00FF00FF00FF00FFULL)) +
					((px00 & 0xFF00FF00FF00FF00ULL) >> 8) +
					((px10 & 0xFF00FF00FF00FF00ULL) >> 8);
			sum1 =	((px01 & 0x00FF00FF00FF00FFULL)) +
					((px11 & 0x00FF00FF00FF00FFULL)) +
					((px01 & 0xFF00FF00FF00FF00ULL) >> 8) +
					((px11 & 0xFF00FF00FF00FF00ULL) >> 8);
			
			// ...swizzle the sums around...
#if OOLITE_BIG_ENDIAN
			sum0 =	((sum0 << 06) & 0xFF00000000000000ULL) |
					((sum0 << 14) & 0x00FF000000000000ULL) |
					((sum0 << 22) & 0x0000FF0000000000ULL) |
					((sum0 << 30) & 0x000000FF00000000ULL);
			sum1 =	((sum1 >> 26) & 0x00000000FF000000ULL) |
					((sum1 >> 18) & 0x0000000000FF0000ULL) |
					((sum1 >> 10) & 0x000000000000FF00ULL) |
					((sum1 >> 02) & 0x00000000000000FFULL);
#elif OOLITE_LITTLE_ENDIAN
			sum0 =	((sum0 >> 26) & 0x00000000FF000000ULL) |
					((sum0 >> 18) & 0x0000000000FF0000ULL) |
					((sum0 >> 10) & 0x000000000000FF00ULL) |
					((sum0 >> 02) & 0x00000000000000FFULL);
			sum1 =	((sum1 << 06) & 0xFF00000000000000ULL) |
					((sum1 << 14) & 0x00FF000000000000ULL) |
					((sum1 << 22) & 0x0000FF0000000000ULL) |
					((sum1 << 30) & 0x000000FF00000000ULL);
#else
			#error Neither OOLITE_BIG_ENDIAN nor OOLITE_LITTLE_ENDIAN is defined as nonzero!
#endif
			// ...and write output pixel.
				*dst++ = sum0 | sum1;
		} while (--x);
		
		// Skip a row for each source row
		src0 = src1;
		src1 += srcWidth;
	} while (--y);
}

#endif


static void ScaleDownByHalvingInPlace1(OOScalerPixMap *srcPx, OOTextureDimension dstWidth, OOTextureDimension dstHeight)
{
	#if OOLITE_NATIVE_64_BIT
		while ((dstWidth * 2 <= srcPx->width && dstHeight * 2 <= srcPx->height) && 8 <= dstWidth && !(srcPx->width & 1) && !(srcPx->height & 1))
		{
			ScaleToHalf_1_x8(srcPx->pixels, srcPx->pixels, srcPx->width, srcPx->height);
			srcPx->width /= 2;
			srcPx->height /= 2;
		}
		while (dstWidth * 2 <= srcPx->width && dstHeight * 2 <= srcPx->height && !(srcPx->width & 1) && !(srcPx->height & 1))
		{
			ScaleToHalf_1_x1(srcPx->pixels, srcPx->pixels, srcPx->width, srcPx->height);
			srcPx->width /= 2;
			srcPx->height /= 2;
		}
	#else
		while ((dstWidth * 2 <= srcPx->width && dstHeight * 2 <= srcPx->height) && 4 <= dstWidth && !(srcPx->width & 1) && !(srcPx->height & 1))
		{
			ScaleToHalf_1_x4(srcPx->pixels, srcPx->pixels, srcPx->width, srcPx->height);
			srcPx->width /= 2;
			srcPx->height /= 2;
		}
		while (dstWidth * 2 <= srcPx->width && dstHeight * 2 <= srcPx->height && !(srcPx->width & 1) && !(srcPx->height & 1))
		{
			ScaleToHalf_1_x1(srcPx->pixels, srcPx->pixels, srcPx->width, srcPx->height);
			srcPx->width /= 2;
			srcPx->height /= 2;
		}
	#endif
}


static BOOL GenerateMipMaps4(void *textureBytes, OOTextureDimension width, OOTextureDimension height)
{
	OOTextureDimension		w = width, h = height;
	uint32_t				*curr, *next;
	
	DUMP_MIP_MAP_PREPARE(4);
	curr = textureBytes;
	
#if OOLITE_NATIVE_64_BIT
	while (2 < w && 1 < h)
	{
		DUMP_MIP_MAP_DUMP(curr, w, h);
		
		next = curr + w * h;
		ScaleToHalf_4_x2(curr, next, w, h);
		
		w >>= 1;
		h >>= 1;
		curr = next;
	}
	if (EXPECT(1 < w && 1 < h))
	{
		DUMP_MIP_MAP_DUMP(curr, w, h);
		
		next = curr + w * h;
		ScaleToHalf_4_x1(curr, next, w, h);
		
		w >>= 1;
		h >>= 1;
	}
#else
	while (1 < w && 1 < h)
	{
		DUMP_MIP_MAP_DUMP(curr, w, h);
		
		next = curr + w * h;
		ScaleToHalf_4_x1(curr, next, w, h);
		
		w >>= 1;
		h >>= 1;
		curr = next;
	}
#endif
	
	DUMP_MIP_MAP_DUMP(curr, w, h);
	
	// TODO: handle residual 1xN/Nx1 mips. For now, we just limit maximum mip level for non-square textures.
	return YES;
}


static void ScaleToHalf_4_x1(void *srcBytes, void *dstBytes, OOTextureDimension srcWidth, OOTextureDimension srcHeight)
{
	OOTextureDimension		x, y;
	uint32_t				*src0, *src1, *dst;
	uint_fast32_t			px00, px01, px10, px11;
	
	/*	We treat channel layout as ABGR -- actual layout doesn't matter since
		each channel is handled the same. We use two accumulators, with
		alternating channels, so overflow doesn't cross channel boundaries,
		while having less overhead than one accumulator per channel.
	*/
	uint_fast32_t			ag, br;
	
	src0 = srcBytes;
	src1 = src0 + srcWidth;
	dst = dstBytes;
	
	y = srcHeight >> 1;
	do
	{
		x = srcWidth >> 1;
		do
		{
			// Read four pixels in a square...
			px00 = *src0++;
			px01 = *src0++;
			px10 = *src1++;
			px11 = *src1++;
			
			// ...and add them together, channel by channel.
			ag =  (px00 & 0xFF00FF00) >> 8;
			br =  (px00 & 0x00FF00FF);
			ag += (px01 & 0xFF00FF00) >> 8;
			br += (px01 & 0x00FF00FF);
			ag += (px10 & 0xFF00FF00) >> 8;
			br += (px10 & 0x00FF00FF);
			ag += (px11 & 0xFF00FF00) >> 8;
			br += (px11 & 0x00FF00FF);
			
			// Shift the sums into place...
			ag <<= 6;
			br >>= 2;
			
			// ...and write output pixel.
			*dst++ = (ag & 0xFF00FF00) | (br & 0x00FF00FF);
		} while (--x);
		
		// Skip a row for each source row
		src0 = src1;
		src1 += srcWidth;
	} while (--y);
}


#if OOLITE_NATIVE_64_BIT

static void ScaleToHalf_4_x2(void *srcBytes, void *dstBytes, OOTextureDimension srcWidth, OOTextureDimension srcHeight)
{
	OOTextureDimension		x, y;
	uint_fast64_t			*src0, *src1, *dst;
	uint_fast64_t			px00, px01, px10, px11;
	
	/*	We treat channel layout as ABGR -- actual layout doesn't matter since
		each channel is handled the same. We use two accumulators, with
		alternating channels, so overflow doesn't cross channel boundaries,
		while having less overhead than one accumulator per channel.
	*/
	uint_fast64_t			ag0, ag1, br0, br1;
	
	srcWidth >>= 1;		// Two bytes at a time
	src0 = srcBytes;
	src1 = src0 + srcWidth;
	dst = dstBytes;
	
	y = srcHeight >> 1;
	do
	{
		x = srcWidth >> 1;
		do
		{
			// Read four pixels in a square...
			px00 = *src0++;
			px01 = *src0++;
			px10 = *src1++;
			px11 = *src1++;
			
			// ...and add them together, channel by channel.
			ag0 =  (px00 & 0xFF00FF00FF00FF00ULL) >> 8;
			br0 =  (px00 & 0x00FF00FF00FF00FFULL);
			ag0 += (px10 & 0xFF00FF00FF00FF00ULL) >> 8;
			br0 += (px10 & 0x00FF00FF00FF00FFULL);
			ag1 =  (px01 & 0xFF00FF00FF00FF00ULL) >> 8;
			br1 =  (px01 & 0x00FF00FF00FF00FFULL);
			ag1 += (px11 & 0xFF00FF00FF00FF00ULL) >> 8;
			br1 += (px11 & 0x00FF00FF00FF00FFULL);
			
			// Shift and add some more...
			ag0 = ag0 + (ag0 << 32);
			br0 = br0 + (br0 << 32);
			ag1 = ag1 + (ag1 >> 32);
			br1 = br1 + (br1 >> 32);
			
			// ...merge and shift some more...
			ag0 = ((ag0 & 0x03FC03FC00000000ULL) | (ag1 & 0x0000000003FC03FCULL)) << 6;
			br0 = ((br0 & 0x03FC03FC00000000ULL) | (br1 & 0x0000000003FC03FCULL)) >> 2;
			
			// ...and write output pixel.
			*dst++ = ag0 | br0;
		} while (--x);
		
		// Skip a row for each source row
		src0 = src1;
		src1 += srcWidth;
	} while (--y);
}

#endif


static void ScaleDownByHalvingInPlace4(OOScalerPixMap *srcPx, OOTextureDimension dstWidth, OOTextureDimension dstHeight)
{
	#if OOLITE_NATIVE_64_BIT
		while ((dstWidth * 2 <= srcPx->width && dstHeight * 2 <= srcPx->height) && 2 <= dstWidth && !(srcPx->width & 1) && !(srcPx->height & 1))
		{
			ScaleToHalf_4_x2(srcPx->pixels, srcPx->pixels, srcPx->width, srcPx->height);
			srcPx->width /= 2;
			srcPx->height /= 2;
		}
		if (EXPECT_NOT(dstWidth == 1 && dstHeight * 2 <= srcPx->height && !(srcPx->height & 1)))
		{
			ScaleToHalf_4_x1(srcPx->pixels, srcPx->pixels, srcPx->width, srcPx->height);
			srcPx->width = 1;
			srcPx->height /= 2;
		}
	#else
		while ((dstWidth * 2 <= srcPx->width && dstHeight * 2 <= srcPx->height) && !(srcPx->width & 1) && !(srcPx->height & 1))
		{
			ScaleToHalf_4_x1(srcPx->pixels, srcPx->pixels, srcPx->width, srcPx->height);
			srcPx->width /= 2;
			srcPx->height /= 2;
		}
	#endif
}


#ifdef DUMP_MIP_MAPS

static void DumpMipMap(void *data, OOTextureDimension width, OOTextureDimension height, OOTexturePlaneCount planes, SInt32 ID, uint32_t level)
{
	NSString *name = [NSString stringWithFormat:@"tex-debug/dump ID %u lv%u %uch %ux%u.raw", ID, level, planes, width, height];
	FILE *dump = fopen([name UTF8String], "w");
	if (dump != NULL)
	{
		fwrite(data, width * planes, height, dump);
		fclose(dump);
	}
}

#endif


static void StretchVerticallyN_x1(OOScalerPixMap srcPx, OOScalerPixMap dstPx, OOTexturePlaneCount planes)
{
	uint8_t				*src, *src0, *src1, *prev, *dst;
	uint8_t				px0, px1;
	uint_fast32_t		x, y, xCount, srcRowBytes;
	uint_fast16_t		weight0, weight1;
	uint_fast32_t		fractY;	// Y coordinate, fixed-point (24.8)
	
	src = srcPx.pixels;
	srcRowBytes = srcPx.rowBytes;
	dst = dstPx.pixels;	// Assumes dstPx.width == dstPx.rowBytes.
	
	prev = src;
	
	xCount = srcPx.width * planes;
	
	for (y = 0; y != dstPx.height; ++y)
	{
		fractY = ((srcPx.height * (y + 1)) << 8) / dstPx.height;
		
		src0 = prev;
		prev = src1 = src + srcRowBytes * (fractY >> 8);
		
		weight1 = fractY & 0xFF;
		weight0 = 0x100 - weight1;
		
		x = xCount;
		while (x--)
		{
			px0 = *src0++;
			px1 = *src1++;
			
			*dst++ = (px0 * weight0 + px1 * weight1) >> 8;
		}
	}
}


#if !OOLITE_NATIVE_64_BIT

static void StretchVerticallyN_x4(OOScalerPixMap srcPx, OOScalerPixMap dstPx, OOTexturePlaneCount planes)
{
	uint8_t				*src;
	uint32_t			*src0, *src1, *prev, *dst;
	uint32_t			px0, px1, ag, br;
	uint_fast32_t		x, y, xCount, srcRowBytes;
	uint_fast16_t		weight0, weight1;
	uint_fast32_t		fractY;	// Y coordinate, fixed-point (24.8)
	
	src = srcPx.pixels;
	srcRowBytes = srcPx.rowBytes;
	dst = dstPx.pixels;	// Assumes no row padding.
	
	prev = (uint32_t *)src;
	
	xCount = (srcPx.width * planes) >> 2;
	
	for (y = 0; y != dstPx.height; ++y)
	{
		fractY = ((srcPx.height * (y + 1)) << 8) / dstPx.height;
		
		src0 = prev;
		prev = src1 = (uint32_t *)(src + srcRowBytes * (fractY >> 8));
		
		weight1 = fractY & 0xFF;
		weight0 = 0x100 - weight1;
		
		x = xCount;
		while (x--)
		{
			px0 = *src0++;
			px1 = *src1++;
			
			ag = ((px0 & 0xFF00FF00) >> 8) * weight0 + ((px1 & 0xFF00FF00) >> 8) * weight1;
			br = (px0 & 0x00FF00FF) * weight0 + (px1 & 0x00FF00FF) * weight1;
			
			*dst++ = (ag & 0xFF00FF00) | ((br >> 8) & 0x00FF00FF);
		}
	}
}

#else	// OOLITE_NATIVE_64_BIT

static void StretchVerticallyN_x8(OOScalerPixMap srcPx, OOScalerPixMap dstPx, OOTexturePlaneCount planes)
{
	uint8_t				*src;
	uint64_t			*src0, *src1, *prev, *dst;
	uint64_t			px0, px1, agag, brbr;
	uint_fast32_t		x, y, xCount, srcRowBytes;
	uint_fast16_t		weight0, weight1;
	uint_fast32_t		fractY;	// Y coordinate, fixed-point (24.8)
	
	src = srcPx.pixels;
	srcRowBytes = srcPx.rowBytes;
	dst = dstPx.pixels;	// Assumes dstPx.width == dstPx.rowBytes.
	
	prev = (uint64_t *)src;
	
	xCount = (srcPx.width * planes) >> 3;
	
	for (y = 0; y != dstPx.height; ++y)
	{
		fractY = ((srcPx.height * (y + 1)) << 8) / dstPx.height;
		
		src0 = prev;
		prev = src1 = (uint64_t *)(src + srcRowBytes * (fractY >> 8));
		
		weight1 = fractY & 0xFF;
		weight0 = 0x100 - weight1;
		
		x = xCount;
		while (x--)
		{
			px0 = *src0++;
			px1 = *src1++;
			
			agag = ((px0 & 0xFF00FF00FF00FF00ULL) >> 8) * weight0 + ((px1 & 0xFF00FF00FF00FF00ULL) >> 8) * weight1;
			brbr = (px0 & 0x00FF00FF00FF00FFULL) * weight0 + (px1 & 0x00FF00FF00FF00FFULL) * weight1;
			
			*dst++ = (agag & 0xFF00FF00FF00FF00ULL) | ((brbr >> 8) & 0x00FF00FF00FF00FFULL);
		}
	}
}
#endif


static void StretchHorizontally1(OOScalerPixMap srcPx, OOScalerPixMap dstPx)
{
	uint8_t				*src, *srcStart, *dst;
	uint8_t				px0, px1;
	uint_fast32_t		x, y, xCount, srcRowBytes;
	uint_fast16_t		weight0, weight1;
	uint_fast32_t		fractX, deltaX;	// X coordinate, fixed-point (20.12), allowing widths up to 1 mebipixel
	
	srcStart = srcPx.pixels;
	srcRowBytes = srcPx.rowBytes;
	xCount = dstPx.width;
	dst = dstPx.pixels;	// Assumes no row padding
	
	deltaX = (srcPx.width << 12) / dstPx.width;
	
	for (y = 0; y != dstPx.height; ++y)
	{
		px1 = *srcStart;
		fractX = 0;
		for (x = 0; x!= xCount; ++x)
		{
			fractX += deltaX;
			
			weight1 = (fractX >> 4) & 0xFF;
			weight0 = 0x100 - weight1;
			
			px0 = px1;
			src = srcStart + (fractX >> 12);
			px1 = *src;
			
			*dst++ = (px0 * weight0 + px1 * weight1) >> 8;
		}
		
		srcStart = (uint8_t *)((char *)srcStart + srcRowBytes);
	}
}


static void StretchHorizontally4(OOScalerPixMap srcPx, OOScalerPixMap dstPx)
{
	uint32_t			*src, *srcStart, *dst;
	uint32_t			px0, px1;
	uint32_t			ag, br;
	uint_fast32_t		x, y, xCount, srcRowBytes;
	uint_fast16_t		weight0, weight1;
	uint_fast32_t		fractX, deltaX;	// X coordinate, fixed-point (20.12), allowing widths up to 1 mebipixel
	
	srcStart = srcPx.pixels;
	srcRowBytes = srcPx.rowBytes;
	xCount = dstPx.width;
	dst = dstPx.pixels;	// Assumes no row padding
	
	deltaX = (srcPx.width << 12) / dstPx.width;
	
	for (y = 0; y != dstPx.height; ++y)
	{
		px1 = *srcStart;
		fractX = 0;
		for (x = 0; x!= xCount; ++x)
		{
			fractX += deltaX;
			
			weight1 = (fractX >> 4) & 0xFF;
			weight0 = 0x100 - weight1;
			
			px0 = px1;
			src = srcStart + (fractX >> 12);
			px1 = *src;
			
			ag = ((px0 & 0xFF00FF00) >> 8) * weight0 + ((px1 & 0xFF00FF00) >> 8) * weight1;
			br = (px0 & 0x00FF00FF) * weight0 + (px1 & 0x00FF00FF) * weight1;
			
			*dst++ = (ag & 0xFF00FF00) | ((br & 0xFF00FF00) >> 8);
		}
		
		srcStart = (uint32_t *)((char *)srcStart + srcRowBytes);
	}
}


static void SqueezeHorizontally1(OOScalerPixMap srcPx, OOTextureDimension dstWidth)
{
	uint8_t				*src, *srcStart, *dst;
	uint8_t				borderPx;
	uint_fast32_t		x, y, xCount, endX, srcRowBytes;
	uint_fast32_t		fractX, endFractX, deltaX;
	uint_fast32_t		accum, weight;
	uint_fast8_t		borderWeight;
	
	srcStart = srcPx.pixels;
	dst = srcStart;	// Output is placed in same buffer, without line padding.
	srcRowBytes = srcPx.rowBytes;
	
	deltaX = (srcPx.width << 12) / dstWidth;
	
	for (y = 0; y != srcPx.height; ++y)
	{
		borderPx = *srcStart;
		endFractX = 0;
		borderWeight = 0;
		
		src = srcStart;
		
		x = 0;
		xCount = dstWidth;
		while (xCount--)
		{
			fractX = endFractX;
			endFractX += deltaX;
			endX = endFractX >> 12;
			
			borderWeight = 0xFF - borderWeight;
			accum = borderPx * borderWeight;
			weight = borderWeight;
			
			borderWeight = (endFractX >> 4) & 0xFF;
			weight += borderWeight;
			
			for (;;)
			{
				++x;
				if (x == endX)
				{
					if (xCount)  borderPx = *++src;
					accum += borderPx * borderWeight;
					break;
				}
				else
				{
					accum += *++src * 0xFF;
					weight += 0xFF;
				}
			}
			
			*dst++ = accum / weight;
		}
		
		srcStart = (uint8_t *)((char *)srcStart + srcRowBytes);
	}
}


static void SqueezeHorizontally4(OOScalerPixMap srcPx, OOTextureDimension dstWidth)
{
	uint32_t			*src, *srcStart, *dst;
	uint32_t			borderPx, ag, br;
	uint_fast32_t		x, y, xCount, endX, srcRowBytes;
	uint_fast32_t		fractX, endFractX, deltaX;
	uint_fast32_t		accum1, accum2, accum3, accum4, weight;
	uint_fast8_t		borderWeight;
	
	srcStart = srcPx.pixels;
	dst = srcStart;	// Output is placed in same buffer, without line padding.
	srcRowBytes = srcPx.rowBytes;
	
	deltaX = (srcPx.width << 12) / dstWidth;
	
	#define ACCUM(PX, WT) do {						\
			uint32_t px = PX;						\
			uint_fast32_t wt = WT;					\
			ag = ((px & 0xFF00FF00) >> 8) * wt;		\
			br = (px & 0x00FF00FF) * wt;			\
			accum1 += ag >> 16;						\
			accum2 += br >> 16;						\
			accum3 += ag & 0xFFFF;					\
			accum4 += br & 0xFFFF;					\
			weight += wt;							\
			} while (0)
	
	for (y = 0; y != srcPx.height; ++y)
	{
		borderPx = *srcStart;
		endFractX = 0;
		borderWeight = 0;
		
		src = srcStart;
		
		x = 0;
		xCount = dstWidth;
		while (xCount--)
		{
			fractX = endFractX;
			endFractX += deltaX;
			endX = endFractX >> 12;
			
			accum1 = 0;
			accum2 = 0;
			accum3 = 0;
			accum4 = 0;
			weight = 0;
			
			borderWeight = 0xFF - borderWeight;
			ACCUM(borderPx, borderWeight);
			
			borderWeight = (endFractX >> 4) & 0xFF;
			
			for (;;)
			{
				++x;
				if (x == endX)
				{
					if (xCount)  borderPx = *++src;
					ACCUM(borderPx, borderWeight);
					break;
				}
				else
				{
					ACCUM(*++src, 0xFF);
				}
			}
			
			accum1 = (accum1 / weight) & 0xFF;
			accum2 = (accum2 / weight) & 0xFF;
			accum3 = (accum3 / weight) & 0xFF;
			accum4 = (accum4 / weight) & 0xFF;
			
			ag = (accum1 << 24) | (accum3 << 8);
			br = (accum2 << 16) | accum4;
			*dst++ = ag | br;
		}
		
		srcStart = (uint32_t *)((char *)srcStart + srcRowBytes);
	}
}


#warning Several scalers still do nothing!
static void SqueezeVertically1(OOScalerPixMap srcPx, OOTextureDimension dstHeight) {}
static void SqueezeVertically4(OOScalerPixMap srcPx, OOTextureDimension dstHeight) {}


static void EnsureCorrectDataSize(OOScalerPixMap *pixMap, BOOL leaveSpaceForMipMaps)
{
	size_t				correctSize;
	void				*bytes = NULL;
	
	correctSize = pixMap->rowBytes * pixMap->height;
	if (leaveSpaceForMipMaps)  correctSize = correctSize * 4 / 3;
	if (correctSize < pixMap->dataSize)
	{
		bytes = realloc(pixMap->pixels, correctSize);
		if (EXPECT_NOT(bytes == NULL))  free(pixMap->pixels);
		pixMap->pixels = bytes;
		pixMap->dataSize = correctSize;
	}
	else if (EXPECT_NOT(pixMap->dataSize < correctSize))
	{
		OOLogGenericParameterError();
		free(pixMap->pixels);
		pixMap->pixels = NULL;
	}
}
