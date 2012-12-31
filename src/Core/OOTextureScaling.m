/*

OOTextureScaling.m

Copyright (C) 2007-2013 Jens Ayton

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


#import "OOTextureScaling.h"
#import "OOFunctionAttributes.h"
#include <stdlib.h>
#import "OOLogging.h"
#import "OOMaths.h"
#import "OOCPUInfo.h"


#define DUMP_MIP_MAPS	0
#define DUMP_SCALE		0


/*	Internal function declarations.
	
	NOTE: the function definitions are grouped together for best code cache
	coherence rather than the order listed here.
 */
static BOOL GenerateMipMaps1(void *textureBytes, OOPixMapDimension width, OOPixMapDimension height) NONNULL_FUNC;
static BOOL GenerateMipMaps2(void *textureBytes, OOPixMapDimension width, OOPixMapDimension height) NONNULL_FUNC;
static BOOL GenerateMipMaps4(void *textureBytes, OOPixMapDimension width, OOPixMapDimension height) NONNULL_FUNC;


/*	ScaleToHalf_P_xN functions
	These scale a texture with P planes (components) to half its size in each
	dimension, handling N pixels at a time. srcWidth must be a multiple of N.
	Parameters are not validated -- bad parameters will lead to bad data or a
	crash.
	
	Scaling is an unweighted average. 8 bits per channel assumed.
	It is safe and meaningful for srcBytes == dstBytes.
*/
static void ScaleToHalf_1_x1(void *srcBytes, void *dstBytes, OOPixMapDimension srcWidth, OOPixMapDimension srcHeight) NONNULL_FUNC;
static void ScaleToHalf_2_x1(void *srcBytes, void *dstBytes, OOPixMapDimension srcWidth, OOPixMapDimension srcHeight) NONNULL_FUNC;
static void ScaleToHalf_4_x1(void *srcBytes, void *dstBytes, OOPixMapDimension srcWidth, OOPixMapDimension srcHeight) NONNULL_FUNC;

#if OOLITE_NATIVE_64_BIT
	static void ScaleToHalf_1_x8(void *srcBytes, void *dstBytes, OOPixMapDimension srcWidth, OOPixMapDimension srcHeight) NONNULL_FUNC;
//	static void ScaleToHalf_2_x4(void *srcBytes, void *dstBytes, OOPixMapDimension srcWidth, OOPixMapDimension srcHeight) NONNULL_FUNC;
	static void ScaleToHalf_4_x2(void *srcBytes, void *dstBytes, OOPixMapDimension srcWidth, OOPixMapDimension srcHeight) NONNULL_FUNC;
#else
	static void ScaleToHalf_1_x4(void *srcBytes, void *dstBytes, OOPixMapDimension srcWidth, OOPixMapDimension srcHeight) NONNULL_FUNC;
//	static void ScaleToHalf_2_x2(void *srcBytes, void *dstBytes, OOPixMapDimension srcWidth, OOPixMapDimension srcHeight) NONNULL_FUNC;
#endif


OOINLINE void StretchVertically(OOPixMap srcPx, OOPixMap dstPx) ALWAYS_INLINE_FUNC;
OOINLINE void SqueezeVertically(OOPixMap pixMap, OOPixMapDimension dstHeight) ALWAYS_INLINE_FUNC;
OOINLINE void StretchHorizontally(OOPixMap srcPx, OOPixMap dstPx) ALWAYS_INLINE_FUNC;
OOINLINE void SqueezeHorizontally(OOPixMap pixMap, OOPixMapDimension dstHeight) ALWAYS_INLINE_FUNC;

static void StretchVerticallyN_x1(OOPixMap srcPx, OOPixMap dstPx);

static void SqueezeVertically1(OOPixMap srcPx, OOPixMapDimension dstHeight);
static void SqueezeVertically2(OOPixMap srcPx, OOPixMapDimension dstHeight);
static void SqueezeVertically4(OOPixMap srcPx, OOPixMapDimension dstHeight);
static void StretchHorizontally1(OOPixMap srcPx, OOPixMap dstPx);
static void StretchHorizontally2(OOPixMap srcPx, OOPixMap dstPx);
static void StretchHorizontally4(OOPixMap srcPx, OOPixMap dstPx);
static void SqueezeHorizontally1(OOPixMap srcPx, OOPixMapDimension dstWidth);
static void SqueezeHorizontally2(OOPixMap srcPx, OOPixMapDimension dstWidth);
static void SqueezeHorizontally4(OOPixMap srcPx, OOPixMapDimension dstWidth);


static BOOL EnsureCorrectDataSize(OOPixMap *pixMap, BOOL leaveSpaceForMipMaps) NONNULL_FUNC;


#if !OOLITE_NATIVE_64_BIT

static void StretchVerticallyN_x4(OOPixMap srcPx, OOPixMap dstPx);

OOINLINE void StretchVertically(OOPixMap srcPx, OOPixMap dstPx)
{
	if (!((srcPx.rowBytes) & 3))
	{
		StretchVerticallyN_x4(srcPx, dstPx);
	}
	else
	{
		StretchVerticallyN_x1(srcPx, dstPx);
	}
}

#else	// OOLITE_NATIVE_64_BIT

static void StretchVerticallyN_x8(OOPixMap srcPx, OOPixMap dstPx);

OOINLINE void StretchVertically(OOPixMap srcPx, OOPixMap dstPx)
{
	if (!((srcPx.rowBytes) & 7))
	{
		StretchVerticallyN_x8(srcPx, dstPx);
	}
	else
	{
		StretchVerticallyN_x1(srcPx, dstPx);
	}
}

#endif


OOINLINE void SqueezeVertically(OOPixMap pixMap, OOPixMapDimension dstHeight)
{
	switch (pixMap.format)
	{
		case kOOPixMapRGBA:
			SqueezeVertically4(pixMap, dstHeight);
			return;
			
		case kOOPixMapGrayscale:
			SqueezeVertically1(pixMap, dstHeight);
			return;
			
		case kOOPixMapGrayscaleAlpha:
			SqueezeVertically2(pixMap, dstHeight);
			return;
			
		case kOOPixMapInvalidFormat:
			break;
	}
	
#ifndef NDEBUG
	[NSException raise:NSInternalInconsistencyException format:@"Unsupported pixmap format in scaler: %@", OOPixMapFormatName(pixMap.format)];
#else
	abort();
#endif
}


OOINLINE void StretchHorizontally(OOPixMap srcPx, OOPixMap dstPx)
{
	NSCParameterAssert(srcPx.format == dstPx.format);
	
	switch (srcPx.format)
	{
		case kOOPixMapRGBA:
			StretchHorizontally4(srcPx, dstPx);
			return;
			
		case kOOPixMapGrayscale:
			StretchHorizontally1(srcPx, dstPx);
			return;
			
		case kOOPixMapGrayscaleAlpha:
			StretchHorizontally2(srcPx, dstPx);
			return;
			
		case kOOPixMapInvalidFormat:
			break;
	}
	
#ifndef NDEBUG
	[NSException raise:NSInternalInconsistencyException format:@"Unsupported pixmap format in scaler: %@", OOPixMapFormatName(srcPx.format)];
#else
	abort();
#endif
}


OOINLINE void SqueezeHorizontally(OOPixMap pixMap, OOPixMapDimension dstHeight)
{
	switch (pixMap.format)
	{
		case kOOPixMapRGBA:
			SqueezeHorizontally4(pixMap, dstHeight);
			return;
			
		case kOOPixMapGrayscale:
			SqueezeHorizontally1(pixMap, dstHeight);
			return;
			
		case kOOPixMapGrayscaleAlpha:
			SqueezeHorizontally2(pixMap, dstHeight);
			return;
			
		case kOOPixMapInvalidFormat:
			break;
	}
	
#ifndef NDEBUG
	[NSException raise:NSInternalInconsistencyException format:@"Unsupported pixmap format in scaler: %@", OOPixMapFormatName(pixMap.format)];
#else
	abort();
#endif	
}


#if DUMP_MIP_MAPS || DUMP_SCALE
// NOTE: currently only works on OS X because of OSAtomicAdd32() (used to increment ID counter in thread-safe way). A simple increment would be sufficient if limited to a single thread (in OOTextureLoader).
volatile int32_t sPreviousDumpID		= 0;
int32_t	OSAtomicAdd32(int32_t __theAmount, volatile int32_t *__theValue);

#endif

#if DUMP_MIP_MAPS
#define	DUMP_CHANNELS		-1		// Bitmap of channel counts - -1 for all dumps

#define DUMP_MIP_MAP_PREPARE(pl)		uint32_t dumpPlanes = pl; \
										uint32_t dumpLevel = 0; \
										BOOL dumpThis = (dumpPlanes & DUMP_CHANNELS) != 0; \
										SInt32 dumpID = dumpThis ? OSAtomicAdd32(1, &sPreviousDumpID) : 0;
#define DUMP_MIP_MAP_DUMP(px, w, h)		if (dumpThis) DumpMipMap(px, w, h, dumpPlanes, dumpID, dumpLevel++);
static void DumpMipMap(void *data, OOPixMapDimension width, OOPixMapDimension height, OOPixMapFormat format, SInt32 ID, uint32_t level);
#else
#define DUMP_MIP_MAP_PREPARE(pl)		do { (void)pl; } while (0)
#define DUMP_MIP_MAP_DUMP(px, w, h)		do { (void)px; (void)w; (void)h; } while (0)
#endif

#if DUMP_SCALE
#define DUMP_SCALE_PREPARE()			SInt32 dumpID = OSAtomicAdd32(1, &sPreviousDumpID), dumpCount = 0;
#define DUMP_SCALE_DUMP(PM, stage)		do { OOPixMap *pm = &(PM); OODumpPixMap(*pm, [NSString stringWithFormat:@"scaling dump ID %u stage %u-%@ %ux%u", dumpID, dumpCount++, stage, pm->width, pm->height]); } while (0)
#else
#define DUMP_SCALE_PREPARE()
#define DUMP_SCALE_DUMP(PM, stage)		do {} while (0)
#endif


OOPixMap OOScalePixMap(OOPixMap srcPx, OOPixMapDimension dstWidth, OOPixMapDimension dstHeight, BOOL leaveSpaceForMipMaps)
{
	OOPixMap			dstPx = {0}, sparePx = {0};
	BOOL				OK = YES;
	
	//	Sanity check.
	if (EXPECT_NOT(!OOIsValidPixMap(srcPx)))
	{
		OOLogGenericParameterError();
		free(srcPx.pixels);
		return kOONullPixMap;
	}
	
	DUMP_SCALE_PREPARE();
	DUMP_SCALE_DUMP(srcPx, @"initial");
	
	if (srcPx.height < dstHeight)
	{
		// Stretch vertically. This requires a separate buffer.
		size_t dstSize = srcPx.rowBytes * dstHeight;
		if (leaveSpaceForMipMaps && dstWidth <= srcPx.width)  dstSize = dstSize * 4 / 3;
		
		dstPx = OOAllocatePixMap(srcPx.width, dstHeight, srcPx.format, 0, dstSize);
		if (EXPECT_NOT(!OOIsValidPixMap(dstPx)))  { OK = NO; goto FAIL; }
		
		StretchVertically(srcPx, dstPx);
		DUMP_SCALE_DUMP(dstPx, @"stretched vertically");
		
		sparePx = srcPx;
		srcPx = dstPx;
	}
	else if (dstHeight < srcPx.height)
	{
		// Squeeze vertically. This can be done in-place.
		SqueezeVertically(srcPx, dstHeight);
		srcPx.height = dstHeight;
		DUMP_SCALE_DUMP(srcPx, @"squeezed vertically");
	}
	
	if (srcPx.width < dstWidth)
	{
		// Stretch horizontally. This requires a separate buffer.
		size_t dstSize = OOPixMapBytesPerPixel(srcPx) * dstWidth * srcPx.height;
		if (leaveSpaceForMipMaps)  dstSize = dstSize * 4 / 3;
		
		if (dstSize <= sparePx.bufferSize)
		{
			dstPx = OOMakePixMap(sparePx.pixels, dstWidth, srcPx.height, srcPx.format, 0, sparePx.bufferSize);
			sparePx = kOONullPixMap;
		}
		else
		{
			dstPx = OOAllocatePixMap(dstWidth, srcPx.height, srcPx.format, 0, dstSize);
		}
		if (EXPECT_NOT(!OOIsValidPixMap(dstPx)))  { OK = NO; goto FAIL; }
		
		StretchHorizontally(srcPx, dstPx);
		DUMP_SCALE_DUMP(dstPx, @"stretched horizontally");
	}
	else if (dstWidth < srcPx.width)
	{
		// Squeeze horizontally. This can be done in-place.
		SqueezeHorizontally(srcPx, dstWidth);
		
		dstPx = srcPx;
		dstPx.width = dstWidth;
		dstPx.rowBytes = dstPx.width * OOPixMapBytesPerPixel(dstPx);
		DUMP_SCALE_DUMP(dstPx, @"squeezed horizontally");
	}
	else
	{
		// No horizontal scaling.
		dstPx = srcPx;
	}
	
	// Avoid a potential double free (if the realloc in EnsureCorrectDataSize() relocates the block).
	if (srcPx.pixels == dstPx.pixels)  srcPx.pixels = NULL;
	
	// dstPx is now the result.
	OK = EnsureCorrectDataSize(&dstPx, leaveSpaceForMipMaps);
	
FAIL:
	free(srcPx.pixels);
	if (sparePx.pixels != dstPx.pixels && sparePx.pixels != srcPx.pixels)
	{
		free(sparePx.pixels);
	}
	if (!OK)
	{
		free(dstPx.pixels);
		dstPx.pixels = NULL;
	}
	
	return OK ? dstPx : kOONullPixMap;
}


// FIXME: should take an OOPixMap.
BOOL OOGenerateMipMaps(void *textureBytes, OOPixMapDimension width, OOPixMapDimension height, OOPixMapFormat format)
{
	if (EXPECT_NOT(width != OORoundUpToPowerOf2_PixMap(width) || height != OORoundUpToPowerOf2_PixMap(height)))
	{
		OOLog(kOOLogParameterError, @"Non-power-of-two dimensions (%ux%u) passed to %s() - ignoring, data will be junk.", width, height, __PRETTY_FUNCTION__);
		return NO;
	}
	if (EXPECT_NOT(textureBytes == NULL))
	{
		OOLog(kOOLogParameterError, @"NULL texutre pointer passed to GenerateMipMaps().");
		return NO;
	}
	
	switch (format)
	{
		case kOOPixMapRGBA:
			return GenerateMipMaps4(textureBytes, width, height);
			
		case kOOPixMapGrayscale:
			return GenerateMipMaps1(textureBytes, width, height);
			
		case kOOPixMapGrayscaleAlpha:
			return GenerateMipMaps2(textureBytes, width, height);
			
		case kOOPixMapInvalidFormat:
			break;
	}
	

	OOLog(kOOLogParameterError, @"%s(): bad pixmap format (%@) - ignoring, data will be junk.", __PRETTY_FUNCTION__, OOPixMapFormatName(format));
	return NO;
}


static BOOL GenerateMipMaps1(void *textureBytes, OOPixMapDimension width, OOPixMapDimension height)
{
	OOPixMapDimension		w = width, h = height;
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


static void ScaleToHalf_1_x1(void *srcBytes, void *dstBytes, OOPixMapDimension srcWidth, OOPixMapDimension srcHeight)
{
	OOPixMapDimension		x, y;
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

static void ScaleToHalf_1_x4(void *srcBytes, void *dstBytes, OOPixMapDimension srcWidth, OOPixMapDimension srcHeight)
{
	OOPixMapDimension		x, y;
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

static void ScaleToHalf_1_x8(void *srcBytes, void *dstBytes, OOPixMapDimension srcWidth, OOPixMapDimension srcHeight)
{
	OOPixMapDimension		x, y;
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


static BOOL GenerateMipMaps2(void *textureBytes, OOPixMapDimension width, OOPixMapDimension height)
{
	OOPixMapDimension		w = width, h = height;
	uint16_t				*curr, *next;
	
	DUMP_MIP_MAP_PREPARE(2);
	curr = textureBytes;
	
	// TODO: multiple pixel two-plane scalers.
#if 0
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
#endif
#endif
	
	while (1 < w && 1 < h)
	{
		DUMP_MIP_MAP_DUMP(curr, w, h);
		
		next = curr + w * h;
		ScaleToHalf_2_x1(curr, next, w, h);
		
		w >>= 1;
		h >>= 1;
		curr = next;
	}
	
	DUMP_MIP_MAP_DUMP(curr, w, h);
	
	// TODO: handle residual 1xN/Nx1 mips. For now, we just limit maximum mip level for non-square textures.
	return YES;
}


static void ScaleToHalf_2_x1(void *srcBytes, void *dstBytes, OOPixMapDimension srcWidth, OOPixMapDimension srcHeight)
{
	OOPixMapDimension		x, y;
	uint16_t				*src0, *src1, *dst;
	uint_fast16_t			px00, px01, px10, px11;
	uint_fast32_t			sumHi, sumLo;
	
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
			sumHi = (px00 & 0xFF00) + (px01 & 0xFF00) + (px10 & 0xFF00) + (px11 & 0xFF00);
			sumLo = (px00 & 0x00FF) + (px01 & 0x00FF) + (px10 & 0x00FF) + (px11 & 0x00FF);
			
			// ...merge and shift the sum into place...
			sumLo = ((sumHi & 0x3FC00) | sumLo) >> 2;
			
			// ...and write output pixel.
			*dst++ = sumLo;
		} while (--x);
		
		// Skip a row for each source row
		src0 = src1;
		src1 += srcWidth;
	} while (--y);
}


static BOOL GenerateMipMaps4(void *textureBytes, OOPixMapDimension width, OOPixMapDimension height)
{
	OOPixMapDimension		w = width, h = height;
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


static void ScaleToHalf_4_x1(void *srcBytes, void *dstBytes, OOPixMapDimension srcWidth, OOPixMapDimension srcHeight)
{
	OOPixMapDimension		x, y;
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

static void ScaleToHalf_4_x2(void *srcBytes, void *dstBytes, OOPixMapDimension srcWidth, OOPixMapDimension srcHeight)
{
	OOPixMapDimension		x, y;
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
			// Read eight pixels (4x2)...
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
			
#if OOLITE_BIG_ENDIAN
			// Shift and add some more...
			ag0 = ag0 + (ag0 << 32);
			br0 = br0 + (br0 << 32);
			ag1 = ag1 + (ag1 >> 32);
			br1 = br1 + (br1 >> 32);
			
			// ...merge and shift some more...
			ag0 = ((ag0 & 0x03FC03FC00000000ULL) | (ag1 & 0x0000000003FC03FCULL)) << 6;
			br0 = ((br0 & 0x03FC03FC00000000ULL) | (br1 & 0x0000000003FC03FCULL)) >> 2;
#elif OOLITE_LITTLE_ENDIAN
			// Shift and add some more...
			ag0 = ag0 + (ag0 >> 32);
			br0 = br0 + (br0 >> 32);
			ag1 = ag1 + (ag1 << 32);
			br1 = br1 + (br1 << 32);
			
			// ...merge and shift some more...
			ag0 = ((ag0 & 0x0000000003FC03FCULL) | (ag1 & 0x03FC03FC00000000ULL)) << 6;
			br0 = ((br0 & 0x0000000003FC03FCULL) | (br1 & 0x03FC03FC00000000ULL)) >> 2;
#else
	#error Unknown architecture.
#endif
			
			// ...and write output pixel.
			*dst++ = ag0 | br0;
		} while (--x);
		
		// Skip a row for each source row
		src0 = src1;
		src1 += srcWidth;
	} while (--y);
}

#endif


#if DUMP_MIP_MAPS
static void DumpMipMap(void *data, OOPixMapDimension width, OOPixMapDimension height, OOPixMapFormat format, SInt32 ID, uint32_t level)
{
	OOPixMap pixMap = OOMakePixMap(data, width, height, format, 0, 0);
	OODumpPixMap(pixMap, [NSString stringWithFormat:@"mipmap dump ID %u lv%u %@ %ux%u", ID, level, OOPixMapFormatName(format), width, height]);
}
#endif


static void StretchVerticallyN_x1(OOPixMap srcPx, OOPixMap dstPx)
{
	uint8_t				*src, *src0, *src1, *prev, *dst;
	uint8_t				px0, px1;
	uint_fast32_t		x, y, xCount;
	size_t				srcRowBytes;
	uint_fast16_t		weight0, weight1;
	uint_fast32_t		fractY;	// Y coordinate, fixed-point (24.8)
	
	src = srcPx.pixels;
	srcRowBytes = srcPx.rowBytes;
	dst = dstPx.pixels;	// Assumes dstPx.width == dstPx.rowBytes.
	
	src0 = prev = src;
	
	xCount = srcPx.width * OOPixMapBytesPerPixel(srcPx);
	
	for (y = 1; y != dstPx.height; ++y)
	{
		fractY = ((srcPx.height * y) << 8) / dstPx.height;
		
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
	
	// Copy last row (without referring to the last-plus-oneth row)
	x = xCount;
	while (x--)
	{
		*dst++ = *src0++;
	}
}


#if !OOLITE_NATIVE_64_BIT

static void StretchVerticallyN_x4(OOPixMap srcPx, OOPixMap dstPx)
{
	uint8_t				*src;
	uint32_t			*src0, *src1, *prev, *dst;
	uint32_t			px0, px1, ag, br;
	uint_fast32_t		x, y, xCount;
	size_t				srcRowBytes;
	uint_fast16_t		weight0, weight1;
	uint_fast32_t		fractY;	// Y coordinate, fixed-point (24.8)
	
	src = srcPx.pixels;
	srcRowBytes = srcPx.rowBytes;
	dst = dstPx.pixels;	// Assumes no row padding.
	
	src0 = prev = (uint32_t *)src;
	
	xCount = (srcPx.width * OOPixMapBytesPerPixel(srcPx)) >> 2;
	
	for (y = 1; y != dstPx.height; ++y)
	{
		fractY = ((srcPx.height * y) << 8) / dstPx.height;
		
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
	
	// Copy last row (without referring to the last-plus-oneth row)
	x = xCount;
	while (x--)
	{
		*dst++ = *src0++;
	}
}

#else	// OOLITE_NATIVE_64_BIT

static void StretchVerticallyN_x8(OOPixMap srcPx, OOPixMap dstPx)
{
	uint8_t				*src;
	uint64_t			*src0, *src1, *prev, *dst;
	uint64_t			px0, px1, agag, brbr;
	uint_fast32_t		x, y, xCount;
	size_t				srcRowBytes;
	uint_fast16_t		weight0, weight1;
	uint_fast32_t		fractY;	// Y coordinate, fixed-point (24.8)
	
	src = srcPx.pixels;
	srcRowBytes = srcPx.rowBytes;
	dst = dstPx.pixels;	// Assumes dstPx.width == dstPx.rowBytes.
	
	src0 = prev = (uint64_t *)src;
	
	xCount = (srcPx.width * OOPixMapBytesPerPixel(srcPx)) >> 3;
	
	for (y = 1; y != dstPx.height; ++y)
	{
		fractY = ((srcPx.height * y) << 8) / dstPx.height;
		
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
	
	// Copy last row (without referring to the last-plus-oneth row)
	x = xCount;
	while (x--)
	{
		*dst++ = *src0++;
	}
}
#endif


static void StretchHorizontally1(OOPixMap srcPx, OOPixMap dstPx)
{
	uint8_t				*src, *srcStart, *dst;
	uint8_t				px0, px1;
	uint_fast32_t		x, y, xCount;
	size_t				srcRowBytes;
	uint_fast16_t		weight0, weight1;
	uint_fast32_t		fractX, deltaX;	// X coordinate, fixed-point (20.12), allowing widths up to 1 mebipixel
	
	NSCParameterAssert(OOIsValidPixMap(srcPx) && OOPixMapBytesPerPixel(srcPx) == 1 && OOIsValidPixMap(dstPx) && OOPixMapBytesPerPixel(dstPx) == 1);
	
	srcStart = srcPx.pixels;
	srcRowBytes = srcPx.rowBytes;
	xCount = dstPx.width;
	dst = dstPx.pixels;	// Assumes no row padding
	
	deltaX = (srcPx.width << 12) / dstPx.width;
	px1 = *srcStart;
	
	for (y = 0; y < dstPx.height - 1; ++y)
	{
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
		px1 = *srcStart;
	}
	
	// Copy last row without reading off end of buffer
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
}


static void StretchHorizontally2(OOPixMap srcPx, OOPixMap dstPx)
{
	uint16_t			*src, *srcStart, *dst;
	uint16_t			px0, px1;
	uint_fast32_t		hi, lo;
	uint_fast32_t		x, y, xCount;
	size_t				srcRowBytes;
	uint_fast16_t		weight0, weight1;
	uint_fast32_t		fractX, deltaX;	// X coordinate, fixed-point (20.12), allowing widths up to 1 mebipixel
	
	NSCParameterAssert(OOIsValidPixMap(srcPx) && OOPixMapBytesPerPixel(srcPx) == 2 && OOIsValidPixMap(dstPx) && OOPixMapBytesPerPixel(dstPx) == 2);
	
	srcStart = srcPx.pixels;
	srcRowBytes = srcPx.rowBytes;
	xCount = dstPx.width;
	dst = dstPx.pixels;	// Assumes no row padding
	
	deltaX = (srcPx.width << 12) / dstPx.width;
	px1 = *srcStart;
	
	for (y = 0; y < dstPx.height - 1; ++y)
	{
		fractX = 0;
		
		for (x = 0; x!= xCount; ++x)
		{
			fractX += deltaX;
			
			weight1 = (fractX >> 4) & 0xFF;
			weight0 = 0x100 - weight1;
			
			px0 = px1;
			src = srcStart + (fractX >> 12);
			px1 = *src;
			
			hi = (px0 & 0xFF00) * weight0 + (px1 & 0xFF00) * weight1;
			lo = (px0 & 0x00FF) * weight0 + (px1 & 0x00FF) * weight1;
			
			*dst++ = ((hi & 0xFF0000) | (lo & 0x00FF00)) >> 8;
		}
		
		srcStart = (uint16_t *)((char *)srcStart + srcRowBytes);
		px1 = *srcStart;
	}
	
	// Copy last row without reading off end of buffer
	fractX = 0;
	for (x = 0; x!= xCount; ++x)
	{
		fractX += deltaX;
		
		weight1 = (fractX >> 4) & 0xFF;
		weight0 = 0x100 - weight1;
		
		px0 = px1;
		src = srcStart + (fractX >> 12);
		px1 = *src;
		
		hi = (px0 & 0xFF00) * weight0 + (px1 & 0xFF00) * weight1;
		lo = (px0 & 0x00FF) * weight0 + (px1 & 0x00FF) * weight1;
		
		*dst++ = ((hi & 0xFF0000) | (lo & 0x00FF00)) >> 8;
	}
}


static void StretchHorizontally4(OOPixMap srcPx, OOPixMap dstPx)
{
	uint32_t			*src, *srcStart, *dst;
	uint32_t			px0, px1;
	uint32_t			ag, br;
	uint_fast32_t		x, y, xCount;
	size_t				srcRowBytes;
	uint_fast16_t		weight0, weight1;
	uint_fast32_t		fractX, deltaX;	// X coordinate, fixed-point (20.12), allowing widths up to 1 mebipixel
	
	NSCParameterAssert(OOIsValidPixMap(srcPx) && OOPixMapBytesPerPixel(srcPx) == 4 && OOIsValidPixMap(dstPx) && OOPixMapBytesPerPixel(dstPx) == 4);
	
	srcStart = srcPx.pixels;
	srcRowBytes = srcPx.rowBytes;
	xCount = dstPx.width;
	dst = dstPx.pixels;	// Assumes no row padding
	
	deltaX = (srcPx.width << 12) / dstPx.width;
	px1 = *srcStart;
	
	for (y = 0; y < dstPx.height - 1; ++y)
	{
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
		px1 = *srcStart;
	}
	
	// Copy last row without reading off end of buffer
	fractX = 0;
	for (x = 0; x!= xCount; ++x)
	{
		fractX += deltaX;
		
		weight1 = (fractX >> 4) & 0xFF;
		weight0 = 0x100 - weight1;
		
		px0 = px1;
		src = srcStart + (fractX >> 12);
		if (EXPECT(x < xCount - 1))  px1 = *src;
		
		ag = ((px0 & 0xFF00FF00) >> 8) * weight0 + ((px1 & 0xFF00FF00) >> 8) * weight1;
		br = (px0 & 0x00FF00FF) * weight0 + (px1 & 0x00FF00FF) * weight1;
		
		*dst++ = (ag & 0xFF00FF00) | ((br & 0xFF00FF00) >> 8);
	}
}


static void SqueezeHorizontally1(OOPixMap srcPx, OOPixMapDimension dstWidth)
{
	uint8_t				*src, *srcStart, *dst;
	uint8_t				borderPx;
	uint_fast32_t		x, y, xCount, endX;
	size_t				srcRowBytes;
	uint_fast32_t		endFractX, deltaX;
	uint_fast32_t		accum, weight;
	uint_fast8_t		borderWeight;
	
	NSCParameterAssert(OOIsValidPixMap(srcPx) && OOPixMapBytesPerPixel(srcPx) == 1);
	
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
				if (EXPECT(x == endX))
				{
					if (EXPECT(xCount))  borderPx = *++src;
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


static void SqueezeVertically1(OOPixMap srcPx, OOPixMapDimension dstHeight)
{
	uint8_t				*src, *srcStart, *dst;
	uint_fast32_t		x, y, xCount, startY, endY, lastRow;
	size_t				srcRowBytes;
	uint_fast32_t		endFractY, deltaY;
	uint_fast32_t		accum, weight;
	uint_fast8_t		startWeight, endWeight;
	
	NSCParameterAssert(OOIsValidPixMap(srcPx) && OOPixMapBytesPerPixel(srcPx) == 1);
	
	dst = srcPx.pixels;	// Output is placed in same buffer, without line padding.
	srcRowBytes = srcPx.rowBytes;
	xCount = srcPx.width;
	
	deltaY = (srcPx.height << 12) / dstHeight;
	endFractY = 0;
	
	endWeight = 0;
	endY = 0;
	
	lastRow = srcPx.height - 1;
	
	while (endY < lastRow)
	{
		endFractY += deltaY;
		startY = endY;
		endY = endFractY >> 12;
		
		startWeight = 0xFF - endWeight;
		endWeight = (endFractY >> 4) & 0xFF;
		
		srcStart = (uint8_t *)((char *)srcPx.pixels + srcRowBytes * startY);
		
		for (x = 0; x != xCount; ++x)
		{
			src = srcStart++;
			accum = startWeight * *src;
			weight = startWeight + endWeight;
			
			y = startY;
			for (;;)
			{
				++y;
				src = (uint8_t *)((char *)src + srcRowBytes);
				if (EXPECT_NOT(y == endY))
				{
					if (EXPECT(endY < lastRow))  accum += *src * endWeight;
					break;
				}
				else
				{
					accum += *src * 0xFF;
					weight += 0xFF;
				}
			}
			
			*dst++ = accum / weight;
		}
	}	
}


/*	Macros to manage 2-channel accumulators in 2-channel squeeze scalers.
	accumHi is the sum of weighted high-channel pixels, shifted left 8 bits.
	accumLo is the sum of weighted low-channel pixels.
	weight is the sum of all pixel weights.
*/
#define ACCUM2(PX, WT) do {							\
			uint16_t px = PX;						\
			uint_fast32_t wt = WT;					\
			accumHi += (px & 0xFF00) * wt;			\
			accumLo += (px & 0x00FF) * wt;			\
			weight += wt;							\
		} while (0)

#define CLEAR_ACCUM2() do {							\
			accumHi = 0;							\
			accumLo = 0;							\
			weight = 0;								\
		} while (0)

#define ACCUM2TOPX()	(							\
			((accumHi / weight) & 0xFF00) |			\
			((accumLo / weight) & 0x00FF)			\
		)


static void SqueezeHorizontally2(OOPixMap srcPx, OOPixMapDimension dstWidth)
{
	uint16_t			*src, *srcStart, *dst;
	uint16_t			borderPx;
	uint_fast32_t		x, y, xCount, endX;
	size_t				srcRowBytes;
	uint_fast32_t		endFractX, deltaX;
	uint_fast32_t		accumHi, accumLo, weight;
	uint_fast8_t		borderWeight;
	
	NSCParameterAssert(OOIsValidPixMap(srcPx) && OOPixMapBytesPerPixel(srcPx) == 2);
	
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
			endFractX += deltaX;
			endX = endFractX >> 12;
			
			CLEAR_ACCUM2();
			
			borderWeight = 0xFF - borderWeight;
			ACCUM2(borderPx, borderWeight);
			
			borderWeight = (endFractX >> 4) & 0xFF;
			
			for (;;)
			{
				++x;
				if (EXPECT(x == endX))
				{
					if (EXPECT(xCount))  borderPx = *++src;
					ACCUM2(borderPx, borderWeight);
					break;
				}
				else
				{
					ACCUM2(*++src, 0xFF);
				}
			}
			
			*dst++ = ACCUM2TOPX();
		}
		
		srcStart = (uint16_t *)((char *)srcStart + srcRowBytes);
	}
}


static void SqueezeVertically2(OOPixMap srcPx, OOPixMapDimension dstHeight)
{
	uint16_t			*src, *srcStart, *dst;
	uint_fast32_t		x, y, xCount, startY, endY, lastRow;
	size_t				srcRowBytes;
	uint_fast32_t		endFractY, deltaY;
	uint_fast32_t		accumHi, accumLo, weight;
	uint_fast8_t		startWeight, endWeight;
	
	NSCParameterAssert(OOIsValidPixMap(srcPx) && OOPixMapBytesPerPixel(srcPx) == 2);
	
	dst = srcPx.pixels;	// Output is placed in same buffer, without line padding.
	srcRowBytes = srcPx.rowBytes;
	xCount = srcPx.width;
	
	deltaY = (srcPx.height << 12) / dstHeight;
	endFractY = 0;
	
	endWeight = 0;
	endY = 0;
	
	lastRow = srcPx.height - 1;
	
	while (endY < lastRow)
	{
		endFractY += deltaY;
		startY = endY;
		endY = endFractY >> 12;
		
		startWeight = 0xFF - endWeight;
		endWeight = (endFractY >> 4) & 0xFF;
		
		srcStart = (uint16_t *)((char *)srcPx.pixels + srcRowBytes * startY);
		
		for (x = 0; x != xCount; ++x)
		{
			src = srcStart++;
			
			CLEAR_ACCUM2();
			ACCUM2(*src, startWeight);
			
			y = startY;
			for (;;)
			{
				++y;
				src = (uint16_t *)((char *)src + srcRowBytes);
				if (EXPECT_NOT(y == endY))
				{
					if (EXPECT(endY <= lastRow))  ACCUM2(*src, endWeight);
					break;
				}
				else
				{
					ACCUM2(*src, 0xFF);
				}
			}
			
			*dst++ = ACCUM2TOPX();
		}
	}
}


/*	Macros to manage 4-channel accumulators in 4-channel squeeze scalers.
	The approach is similar to the ACCUM2 family above, except that the wt
	multiplication works on two channels at a time before splitting into four
	accumulators, all of which are shifted to the low end of the value.
*/
#define ACCUM4(PX, WT) do {							\
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

#define CLEAR_ACCUM4() do {							\
			accum1 = 0;								\
			accum2 = 0;								\
			accum3 = 0;								\
			accum4 = 0;								\
			weight = 0;								\
		} while (0)

/*	These integer divisions cause a stall -- this is the biggest
	bottleneck in this file. Unrolling the loop might help on PPC.
	Linear interpolation instead of box filtering would help, with
	a quality hit. Given that scaling doesn't happen very often,
	I think I'll leave it this way. -- Ahruman
*/
#define ACCUM4TOPX()	(							\
			(((accum1 / weight) & 0xFF) << 24) |	\
			(((accum3 / weight) & 0xFF) << 8)  |	\
			(((accum2 / weight) & 0xFF) << 16) |	\
			((accum4 / weight) & 0xFF)				\
		)


static void SqueezeHorizontally4(OOPixMap srcPx, OOPixMapDimension dstWidth)
{
	uint32_t			*src, *srcStart, *dst;
	uint32_t			borderPx, ag, br;
	uint_fast32_t		x, y, xCount, endX;
	size_t				srcRowBytes;
	uint_fast32_t		endFractX, deltaX;
	uint_fast32_t		accum1, accum2, accum3, accum4, weight;
	uint_fast8_t		borderWeight;
	
	NSCParameterAssert(OOIsValidPixMap(srcPx) && OOPixMapBytesPerPixel(srcPx) == 4);
	
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
			endFractX += deltaX;
			endX = endFractX >> 12;
			
			CLEAR_ACCUM4();
			
			borderWeight = 0xFF - borderWeight;
			ACCUM4(borderPx, borderWeight);
			
			borderWeight = (endFractX >> 4) & 0xFF;
			
			for (;;)
			{
				++x;
				if (EXPECT(x == endX))
				{
					if (EXPECT(xCount))  borderPx = *++src;
					ACCUM4(borderPx, borderWeight);
					break;
				}
				else
				{
					ACCUM4(*++src, 0xFF);
				}
			}
			
			*dst++ = ACCUM4TOPX();
		}
		
		srcStart = (uint32_t *)((char *)srcStart + srcRowBytes);
	}
}


static void SqueezeVertically4(OOPixMap srcPx, OOPixMapDimension dstHeight)
{
	uint32_t			*src, *srcStart, *dst;
	uint_fast32_t		x, y, xCount, startY, endY, lastRow;
	size_t				srcRowBytes;
	uint32_t			ag, br;
	uint_fast32_t		endFractY, deltaY;
	uint_fast32_t		accum1, accum2, accum3, accum4, weight;
	uint_fast8_t		startWeight, endWeight;
	
	NSCParameterAssert(OOIsValidPixMap(srcPx) && OOPixMapBytesPerPixel(srcPx) == 4);
	
	dst = srcPx.pixels;	// Output is placed in same buffer, without line padding.
	srcRowBytes = srcPx.rowBytes;
	xCount = srcPx.width;
	
	deltaY = (srcPx.height << 12) / dstHeight;
	endFractY = 0;
	
	endWeight = 0;
	endY = 0;
	
	lastRow = srcPx.height - 1;
	
	while (endY < lastRow)
	{
		endFractY += deltaY;
		startY = endY;
		endY = endFractY >> 12;
		
		startWeight = 0xFF - endWeight;
		endWeight = (endFractY >> 4) & 0xFF;
		
		srcStart = (uint32_t *)((char *)srcPx.pixels + srcRowBytes * startY);
		
		for (x = 0; x != xCount; ++x)
		{
			src = srcStart++;
			
			CLEAR_ACCUM4();
			ACCUM4(*src, startWeight);
			
			y = startY;
			for (;;)
			{
				++y;
				src = (uint32_t *)((char *)src + srcRowBytes);
				if (EXPECT_NOT(y == endY))
				{
					if (EXPECT(endY <= lastRow))  ACCUM4(*src, endWeight);
					break;
				}
				else
				{
					ACCUM4(*src, 0xFF);
				}
			}
			
			*dst++ = ACCUM4TOPX();
		}
	}
}


static BOOL EnsureCorrectDataSize(OOPixMap *pixMap, BOOL leaveSpaceForMipMaps)
{
	size_t				correctSize;
	void				*bytes = NULL;
	
	correctSize = pixMap->rowBytes * pixMap->height;
	
	// correctSize > 0 check is redundant, but static analyzer (checker-262) doesn't know that. -- Ahruman 2012-03-17
	NSCParameterAssert(OOIsValidPixMap(*pixMap) && correctSize > 0);
	
	/*	Ensure that the block is not too small. This needs to be done before
		adding the mip-map space, as the texture may have been shrunk in place
		without being grown for mip-maps.
	*/
	if (EXPECT_NOT(pixMap->bufferSize < correctSize))
	{
		OOLogGenericParameterError();
		return NO;
	}
	
	if (leaveSpaceForMipMaps)  correctSize = correctSize * 4 / 3;
	if (correctSize != pixMap->bufferSize)
	{
		bytes = realloc(pixMap->pixels, correctSize);
		if (EXPECT_NOT(bytes == NULL))  free(pixMap->pixels);
		pixMap->pixels = bytes;
		pixMap->bufferSize = correctSize;
	}
	
	return YES;
}
