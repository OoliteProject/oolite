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

*/


// Temporarily disabled build flags: -O3 -falign-loops=32 -falign-loops-max-skip=31


#import "OOTextureScaling.h"
#import "OOFunctionAttributes.h"
#import <stdlib.h>
#import "OOLogging.h"
#import "OOMaths.h"
#import "OOCPUInfo.h"


#define SUPPORT_TWO_CHANNELS	0


static BOOL GenerateMipMaps1(void *textureBytes, uint32_t width, uint32_t height);
#if SUPPORT_TWO_CHANNELS
static BOOL GenerateMipMaps2(void *textureBytes, uint32_t width, uint32_t height);
#endif
static BOOL GenerateMipMaps4(void *textureBytes, uint32_t width, uint32_t height);


/*	ScaleToHalf_P_xN functions
	These scale a texture with P planes (components) to half its size in each
	dimension, handling N pixels at a time. srcWidth must be a multiple of N.
	Parameters are not validated -- bad parameters will lead to bad data or a
	crash.
	
	Scaling is an unweighted average. 8 bits per channel assumed.
*/
static void ScaleToHalf_1_x1(void *srcBytes, void *dstBytes, uint32_t srcWidth, uint32_t srcHeight) NONNULL_FUNC;
#if SUPPORT_TWO_CHANNELS
static void ScaleToHalf_2_x1(void *srcBytes, void *dstBytes, uint32_t srcWidth, uint32_t srcHeight) NONNULL_FUNC;
#endif
static void ScaleToHalf_4_x1(void *srcBytes, void *dstBytes, uint32_t srcWidth, uint32_t srcHeight) NONNULL_FUNC;

#if OOLITE_NATIVE_64_BIT
	static void ScaleToHalf_1_x8(void *srcBytes, void *dstBytes, uint32_t srcWidth, uint32_t srcHeight) NONNULL_FUNC;
	#if SUPPORT_TWO_CHANNELS
	static void ScaleToHalf_2_x4(void *srcBytes, void *dstBytes, uint32_t srcWidth, uint32_t srcHeight) NONNULL_FUNC;
	#endif
	static void ScaleToHalf_4_x2(void *srcBytes, void *dstBytes, uint32_t srcWidth, uint32_t srcHeight) NONNULL_FUNC;
#else
	static void ScaleToHalf_1_x4(void *srcBytes, void *dstBytes, uint32_t srcWidth, uint32_t srcHeight) NONNULL_FUNC;
	#if SUPPORT_TWO_CHANNELS
	static void ScaleToHalf_2_x2(void *srcBytes, void *dstBytes, uint32_t srcWidth, uint32_t srcHeight) NONNULL_FUNC;
	#endif
#endif



// #define DUMP_MIP_MAPS


#ifdef DUMP_MIP_MAPS
// NOTE: currently only works on OS X because of OTAtomicAdd32() (used to increment ID counter in thread-safe way). A simple increment would be sufficient if limited to a single thread (in OOTextureLoader).
SInt32 sPreviousDumpID		= 0;

#define DUMP_MIP_MAP_PREPARE(pl)		SInt32 dumpID = OTAtomicAdd32(1, &sPreviousDumpID); \
										uint32_t dumpLevel = 0;	 \
										uint32_t dumpPlanes = pl; \
										OOLog(@"texture.mipMap.dump", @"Dumping mip-maps as dump ID%u lv# %uch XxY.raw.", dumpID, dumpPlanes);
#define DUMP_MIP_MAP_DUMP(px, w, h)		DumpMipMap(px, w, h, dumpPlanes, dumpID, dumpLevel++);
static void DumpMipMap(void *data, uint32_t width, uint32_t height, uint32_t planes, SInt32 ID, uint32_t level);
#else
#define DUMP_MIP_MAP_PREPARE(pl)		do {} while (0)
#define DUMP_MIP_MAP_DUMP(px, w, h)		do {} while (0)
#endif


uint8_t *ScaleUpPixMap(uint8_t *srcPixels, unsigned srcWidth, unsigned srcHeight, unsigned srcBytesPerRow, unsigned planes, unsigned dstWidth, unsigned dstHeight)
{
	uint8_t			*texBytes;
	int				x, y, n;
	float			texel_w, texel_h;
	float			y_lo, y_hi, x_lo, x_hi;
	int				y0, y1, x0, x1, acc;
	float			py0, py1, px0, px1;
	int				xy00, xy01, xy10, xy11;
	int				texi = 0;
	
	if (EXPECT_NOT(srcPixels == NULL)) return NULL;
	texBytes = malloc(dstWidth * dstHeight * planes);
	if (EXPECT_NOT(texBytes == NULL)) return NULL;
	
//	OOLog(@"image.scale.up", @"Scaling up %u planes from %ux%u to %ux%u", planes, srcWidth, srcHeight, dstWidth, dstHeight);

	// do bilinear scaling
	texel_w = (float)srcWidth / (float)dstWidth;
	texel_h = (float)srcHeight / (float)dstHeight;

	for ( y = 0; y < dstHeight; y++)
	{
		y_lo = texel_h * y;
		y_hi = y_lo + texel_h - 0.001f;
		y0 = floor(y_lo);
		y1 = floor(y_hi);

		py0 = 1.0f;
		py1 = 0.0f;
		if (y1 > y0)
		{
			py0 = (y1 - y_lo) / texel_h;
			py1 = 1.0f - py0;
		}

		for ( x = 0; x < dstWidth; x++)
		{
			x_lo = texel_w * x;
			x_hi = x_lo + texel_w - 0.001f;
			x0 = floor(x_lo);
			x1 = floor(x_hi);
			acc = 0;

			px0 = 1.0f;
			px1 = 0.0f;
			if (x1 > x0)
			{
				px0 = (x1 - x_lo) / texel_w;
				px1 = 1.0f - px0;
			}

			xy00 = y0 * srcBytesPerRow + planes * x0;
			xy01 = y0 * srcBytesPerRow + planes * x1;
			xy10 = y1 * srcBytesPerRow + planes * x0;
			xy11 = y1 * srcBytesPerRow + planes * x1;
			
			// SLOW_CODE This is a bottleneck. Should be reimplemented without float maths or, better, using an optimized library. -- ahruman
			for (n = 0; n < planes; n++)
			{
				acc = py0 * (px0 * srcPixels[ xy00 + n] + px1 * srcPixels[ xy10 + n])
					+ py1 * (px0 * srcPixels[ xy01 + n] + px1 * srcPixels[ xy11 + n]);
				texBytes[texi++] = (char)acc;	// float -> char
			}
		}
	}
	
	return texBytes;
}


static void ScaleUpHorizontally4(const char *srcPixels, uint32_t srcWidth, uint32_t srcHeight, uint32_t srcRowBytes, char *dstPixels, uint32_t dstWidth);
static void ScaleDownHorizontally4(const char *srcPixels, uint32_t srcWidth, uint32_t srcHeight, uint32_t srcRowBytes, char *dstPixels, uint32_t dstWidth);
static void ScaleUpHorizontally1(const char *srcPixels, uint32_t srcWidth, uint32_t srcHeight, uint32_t srcRowBytes, char *dstPixels, uint32_t dstWidth);
static void ScaleDownHorizontally1(const char *srcPixels, uint32_t srcWidth, uint32_t srcHeight, uint32_t srcRowBytes, char *dstPixels, uint32_t dstWidth);
static void ScaleUpVertically(const char *srcPixels, uint32_t srcWidth, uint32_t srcHeight, uint32_t srcRowBytes, char *dstPixels, unsigned dstHeight);
static void ScaleDownVertically(const char *srcPixels, uint32_t srcWidth, uint32_t srcHeight, uint32_t srcRowBytes, char *dstPixels, unsigned dstHeight);
static void CopyRows(const char *srcPixels, uint32_t widthInBytes, uint32_t height, uint32_t srcRowBytes, char *dstPixels);


BOOL ScalePixMap(void *srcPixels, uint32_t srcWidth, uint32_t srcHeight, uint8_t planes, uint32_t srcRowBytes, void *dstPixels, uint32_t dstWidth, uint32_t dstHeight)
{
	// Divide and conquer - handle horizontal and vertical resizing in separate passes.
	
	void			*interData;
	unsigned		interWidth, interHeight, interRowBytes;
	
	// Sanity checks
	if (EXPECT_NOT(srcWidth == 0 || srcHeight == 0 || srcPixels == NULL || dstPixels == NULL || srcRowBytes < srcWidth * 4 || (planes != 1 && planes != 4)))
	{
		OOLog(kOOLogParameterError, @"***** Internal error: bad parameters -- %s(%p, %u, %u, %u, %u, %p, %u, %u)", srcPixels, srcWidth, srcHeight, planes, srcRowBytes, dstPixels, dstWidth, dstHeight);
		return NO;
	}
	
	// Scale horizontally, if needed
	if (srcWidth < dstWidth)
	{
		if (planes == 4)  ScaleUpHorizontally4(srcPixels, srcWidth, srcHeight, srcRowBytes, dstPixels, dstWidth);
		else if (planes == 1)  ScaleUpHorizontally1(srcPixels, srcWidth, srcHeight, srcRowBytes, dstPixels, dstWidth);
		interData = dstPixels;
		interWidth = dstWidth;
		interHeight = dstHeight;
		interRowBytes = interWidth * planes;
	}
	else if (dstWidth < srcWidth)
	{
		if (planes == 4)  ScaleDownHorizontally4(srcPixels, srcWidth, srcHeight, srcRowBytes, dstPixels, dstWidth);
		else if (planes == 1)  ScaleDownHorizontally1(srcPixels, srcWidth, srcHeight, srcRowBytes, dstPixels, dstWidth);
		interData = dstPixels;
		interWidth = dstWidth;
		interHeight = dstHeight;
		interRowBytes = interWidth * planes;
	}
	else
	{
		interData = srcPixels;
		interWidth = srcWidth;
		interHeight = srcHeight;
		interRowBytes = srcRowBytes;
	}
	
	// Scale vertically, if needed.
	if (srcHeight < dstHeight)
	{
		ScaleUpVertically(interData, interWidth * planes, interHeight, interRowBytes, dstPixels, dstHeight);
	}
	else if (dstHeight < srcHeight)
	{
		ScaleDownVertically(interData, interWidth * planes, interHeight, interRowBytes, dstPixels, dstHeight);
	}
	else
	{
		// This handles the no-scaling case as well as the horizontal-scaling-only case.
		CopyRows(interData, interWidth * planes, interHeight, interRowBytes, dstPixels);
	}
	return YES;
}


BOOL GenerateMipMaps(void *textureBytes, unsigned width, unsigned height, uint8_t planes)
{
	if (EXPECT_NOT(width != OORoundUpToPowerOf2(width) || height != OORoundUpToPowerOf2(height)))
	{
		OOLog(kOOLogParameterError, @"Non-power-of-two dimensions (%ux%u) passed to GenerateMipMaps() - ignoring, data will be junk.", width, height);
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
#if SUPPORT_TWO_CHANNELS
	if (planes == 2)  return GenerateMipMaps2(textureBytes, width, height);
#endif
	
	OOLog(kOOLogParameterError, @"Bad plane count (%u, should be 1 or 4) - ignoring, data will be junk.", planes);
	return NO;
}


static BOOL GenerateMipMaps1(void *textureBytes, uint32_t width, uint32_t height)
{
	uint_fast32_t			w = width, h = height;
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
		ScaleToHalf_4_x1(curr, next, w >> 2, h);
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


static void ScaleToHalf_1_x1(void *srcBytes, void *dstBytes, uint32_t srcWidth, uint32_t srcHeight)
{
	uint_fast32_t			x, y;
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

static void ScaleToHalf_1_x4(void *srcBytes, void *dstBytes, uint32_t srcWidth, uint32_t srcHeight)
{
	uint_fast32_t			x, y;
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
			sum0 = ((sum0 << 6) & 0xFF000000) | ((sum0 << 14) & 0x00FF0000);
			sum1 = ((sum1 >> 10) & 0x0000FF00) | ((sum1 >>2) & 0x000000FF);
			
			// ...and write output pixel.
				*dst++ = sum0 | sum1;
		} while (--x);
		
		// Skip a row for each source row
		src0 = src1;
		src1 += srcWidth;
	} while (--y);
}

#else	// OOLITE_NATIVE_64_BIT

static void ScaleToHalf_1_x8(void *srcBytes, void *dstBytes, uint32_t srcWidth, uint32_t srcHeight)
{
	uint_fast32_t			x, y;
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
			sum0 =	((sum0 << 06) & 0xFF00000000000000ULL) |
					((sum0 << 14) & 0x00FF000000000000ULL) |
					((sum0 << 22) & 0x0000FF0000000000ULL) |
					((sum0 << 30) & 0x000000FF00000000ULL);
			sum1 =	((sum1 >> 26) & 0x00000000FF000000ULL) |
					((sum1 >> 18) & 0x0000000000FF0000ULL) |
					((sum1 >> 10) & 0x000000000000FF00ULL) |
					((sum1 >> 02) & 0x00000000000000FFULL);
			
			// ...and write output pixel.
				*dst++ = sum0 | sum1;
		} while (--x);
		
		// Skip a row for each source row
		src0 = src1;
		src1 += srcWidth;
	} while (--y);
}

#endif


#if SUPPORT_TWO_CHANNELS
static BOOL GenerateMipMaps2(void *textureBytes, uint32_t width, uint32_t height)
{
	uint_fast32_t			w = width, h = height;
	uint16_t				*curr, *next;
	
	DUMP_MIP_MAP_PREPARE(2);
	curr = textureBytes;
	
#if OOLITE_NATIVE_64_BIT
	while (4 < w && 1 < h)
	{
		DUMP_MIP_MAP_DUMP(curr, w, h);
		
		next = curr + w * h;
		ScaleToHalf_2_x4(curr, next, w, h);
		
		w >>= 1;
		h >>= 1;
		curr = next;
	}
	
	while (1 < w && 1 < h)
	{
		DUMP_MIP_MAP_DUMP(curr, w, h);
		
		next = curr + w * h;
		ScaleToHalf_2_x1(curr, next, w, h);
		
		w >>= 1;
		h >>= 1;
		curr = next;
	}
#else
	while (2 < w && 1 < h)
	{
		DUMP_MIP_MAP_DUMP(curr, w, h);
		
		next = curr + w * h;
		ScaleToHalf_2_x2(curr, next, w, h);
		
		w >>= 1;
		h >>= 1;
		curr = next;
	}
	if (EXPECT(1 < w && 1 < h))
	{
		DUMP_MIP_MAP_DUMP(curr, w, h);
		ScaleToHalf_2_x1(curr, next, w, h);
		#if DUMP_MIP_MAPS
			w >>= 1;
			h >>= 1;
		#endif
	}
#endif
	
	DUMP_MIP_MAP_DUMP(curr, w, h);
	
	// TODO: handle residual 1xN/Nx1 mips. For now, we just limit maximum mip level for non-square textures.
	return YES;
}
#endif	// SUPPORT_TWO_CHANNELS


static BOOL GenerateMipMaps4(void *textureBytes, uint32_t width, uint32_t height)
{
	uint_fast32_t			w = width, h = height;
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
		ScaleToHalf_4_x1(curr, next, w, h);
		#if DUMP_MIP_MAPS
			w >>= 1;
			h >>= 1;
		#endif
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


static void ScaleToHalf_4_x1(void *srcBytes, void *dstBytes, uint32_t srcWidth, uint32_t srcHeight)
{
	uint_fast32_t			x, y;
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

static void ScaleToHalf_4_x2(void *srcBytes, void *dstBytes, uint32_t srcWidth, uint32_t srcHeight)
{
	uint_fast32_t			x, y;
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


#ifdef DUMP_MIP_MAPS

static void DumpMipMap(void *data, uint32_t width, uint32_t height, uint32_t planes, SInt32 ID, uint32_t level)
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


static void ScaleUpHorizontally4(const char *srcPixels, uint32_t srcWidth, uint32_t srcHeight, uint32_t srcRowBytes, char *dstPixels, uint32_t dstWidth)
{
	// TODO
	OOLog(@"scale.unimplemented", @"Attempt to scale texture, currently unsupported - expect noise.");
}


static void ScaleDownHorizontally4(const char *srcPixels, uint32_t srcWidth, uint32_t srcHeight, uint32_t srcRowBytes, char *dstPixels, uint32_t dstWidth)
{
	// TODO
	OOLog(@"scale.unimplemented", @"Attempt to scale texture, currently unsupported - expect noise.");
}


static void ScaleUpHorizontally1(const char *srcPixels, uint32_t srcWidth, uint32_t srcHeight, uint32_t srcRowBytes, char *dstPixels, uint32_t dstWidth)
{
	// TODO
	OOLog(@"scale.unimplemented", @"Attempt to scale texture, currently unsupported - expect noise.");
}


static void ScaleDownHorizontally1(const char *srcPixels, uint32_t srcWidth, uint32_t srcHeight, uint32_t srcRowBytes, char *dstPixels, uint32_t dstWidth)
{
	// TODO
	OOLog(@"scale.unimplemented", @"Attempt to scale texture, currently unsupported - expect noise.");
}


static void ScaleUpVertically(const char *srcPixels, uint32_t srcWidthInBytes, uint32_t srcHeight, uint32_t srcRowBytes, char *dstPixels, unsigned dstHeight)
{
	// TODO
	OOLog(@"scale.unimplemented", @"Attempt to scale texture, currently unsupported - expect noise.");
}


static void ScaleDownVertically(const char *srcPixels, uint32_t srcWidthInBytes, uint32_t srcHeight, uint32_t srcRowBytes, char *dstPixels, unsigned dstHeight)
{
	// TODO
	OOLog(@"scale.unimplemented", @"Attempt to scale texture, currently unsupported - expect noise.");
}


static void CopyRows(const char *srcPixels, uint32_t widthInBytes, uint32_t height, uint32_t srcRowBytes, char *dstPixels)
{
	unsigned			y;
	
	if (srcRowBytes == widthInBytes)
	{
		memcpy(dstPixels, srcPixels, height * widthInBytes);
		return;
	}
	
	for (y = 0; y != height; ++y)
	{
		__builtin_memcpy(dstPixels, srcPixels, widthInBytes);
		dstPixels += srcRowBytes;
		srcPixels += widthInBytes;
	}
}
