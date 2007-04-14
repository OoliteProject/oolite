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


static void ScaleUpHorizontally(const char *srcPixels, unsigned srcWidth, unsigned srcHeight, unsigned srcRowBytes, uint8_t *dstPixels, unsigned dstWidth);
static void ScaleDownHorizontally(const char *srcPixels, unsigned srcWidth, unsigned srcHeight, unsigned srcRowBytes, uint8_t *dstPixels, unsigned dstWidth);
static void ScaleUpVertically(const char *srcPixels, unsigned srcWidth, unsigned srcHeight, unsigned srcRowBytes, uint8_t *dstPixels, unsigned dstHeight);
static void ScaleDownVertically(const char *srcPixels, unsigned srcWidth, unsigned srcHeight, unsigned srcRowBytes, uint8_t *dstPixels, unsigned dstHeight);
static void CopyRows(const char *srcPixels, unsigned srcWidth, unsigned srcHeight, unsigned srcRowBytes, uint8_t *dstPixels);


void ScalePixMap(void *srcPixels, unsigned srcWidth, unsigned srcHeight, unsigned srcRowBytes, void *dstPixels, unsigned dstWidth, unsigned dstHeight)
{
	// Divide and conquer - handle horizontal and vertical resizing in separate passes.
	
	void			*interData;
	unsigned		interWidth, interHeight, interRowBytes;
	
	// Sanity checks
	if (EXPECT_NOT(srcWidth == 0 || srcHeight == 0 || srcPixels == NULL || dstPixels == NULL || srcRowBytes < srcWidth * 4)) return;
	
	// Scale horizontally, if needed
	if (srcWidth < dstWidth)
	{
		ScaleUpHorizontally(srcPixels, srcWidth, srcHeight, srcRowBytes, dstPixels, dstWidth);
		interData = dstPixels;
		interWidth = dstWidth;
		interHeight = dstHeight;
		interRowBytes = interWidth * 4;
	}
	else if (dstWidth < srcWidth)
	{
		ScaleDownHorizontally(srcPixels, srcWidth, srcHeight, srcRowBytes, dstPixels, dstWidth);
		interData = dstPixels;
		interWidth = dstWidth;
		interHeight = dstHeight;
		interRowBytes = interWidth * 4;
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
		ScaleUpVertically(interData, interWidth, interHeight, interRowBytes, dstPixels, dstHeight);
	}
	else if (dstHeight < srcHeight)
	{
		ScaleDownVertically(interData, interWidth, interHeight, interRowBytes, dstPixels, dstHeight);
	}
	else
	{
		// This handles the no-scaling case as well as the horizontal-scaling-only case.
		CopyRows(interData, interWidth, interHeight, interRowBytes, dstPixels);
	}
}


void GenerateMipMaps(void *textureBytes, unsigned width, unsigned height)
{
	if (EXPECT_NOT(width != OORoundUpToPowerOf2(width) || height != OORoundUpToPowerOf2(height)))
	{
		OOLog(@"texture.generateMipMaps.skip", @"Non-power-of-two dimensions (%ux%u) passed to GenerateMipMaps() - ignoring, data will be junk.", width, height);
		return;
	}
	
	uint_fast32_t			w = width, h = height, x, y;
	uint32_t				*src0, *src1, *dst, *next;
	uint_fast32_t			px00, px01, px10, px11;
	uint_fast32_t			ag, rb;	// red and blue channel, green and alpha channel.
	
	next = textureBytes;
	
#define DUMP_MIP_MAPS 
#ifdef DUMP_MIP_MAPS
	static unsigned ID = -1;
	++ID;
	uint32_t *start;
	unsigned level = 0;
#endif
	
	while (1 < w && 1 < h)
	{
		src0 = next;
		next = src0 + w * h;
		src1 = src0 + w;
		dst = next;
		
#ifdef DUMP_MIP_MAPS
		start = src0;
#endif
		
		w >>= 1;
		h >>= 1;
		
		y = h;
		do
		{
			x = w;
			do
			{
				// Read four pixels in a square...
				px00 = *src0++;
				px01 = *src0++;
				px10 = *src1++;
				px11 = *src1++;
				
				// ...and add them together, channel by channel.
				ag = (px00 & 0xFF00FF00) >> 8;
				rb = (px00 & 0x00FF00FF);
				ag += (px01 & 0xFF00FF00) >> 8;
				rb += (px01 & 0x00FF00FF);
				ag += (px10 & 0xFF00FF00) >> 8;
				rb += (px10 & 0x00FF00FF);
				ag += (px11 & 0xFF00FF00) >> 8;
				rb += (px11 & 0x00FF00FF);
				
				// ...shift the sums into place...
				ag <<= 6;
				rb >>= 2;
				
				// ...and write output pixel.
				*dst++ = (ag & 0xFF00FF00) | (rb & 0x00FF00FF);
			} while (--x);
			
			// Skip a row for each source row
			src0 = src1;
			src1 += w << 1;
		} while (--y);
		
#ifdef DUMP_MIP_MAPS
		NSString *name = [NSString stringWithFormat:@"/Users/jayton/Desktop/tex-debug/dump-%u-%u.raw", ID, level++];
		FILE *dump = fopen([name UTF8String], "w");
		if (dump != NULL)
		{
			fwrite(start, w, h * 16, dump);
			fclose(dump);
		}
#endif
	}
}


static void ScaleUpHorizontally(const char *srcPixels, unsigned srcWidth, unsigned srcHeight, unsigned srcRowBytes, uint8_t *dstPixels, unsigned dstWidth)
{
	// TODO
	OOLog(@"scale.unimplemented", @"Attempt to scale texture, currently unsupported - expect noise.");
}


static void ScaleDownHorizontally(const char *srcPixels, unsigned srcWidth, unsigned srcHeight, unsigned srcRowBytes, uint8_t *dstPixels, unsigned dstWidth)
{
	// TODO
	OOLog(@"scale.unimplemented", @"Attempt to scale texture, currently unsupported - expect noise.");
}


static void ScaleUpVertically(const char *srcPixels, unsigned srcWidth, unsigned srcHeight, unsigned srcRowBytes, uint8_t *dstPixels, unsigned dstHeight)
{
	// TODO
	OOLog(@"scale.unimplemented", @"Attempt to scale texture, currently unsupported - expect noise.");
}


static void ScaleDownVertically(const char *srcPixels, unsigned srcWidth, unsigned srcHeight, unsigned srcRowBytes, uint8_t *dstPixels, unsigned dstHeight)
{
	// TODO
	OOLog(@"scale.unimplemented", @"Attempt to scale texture, currently unsupported - expect noise.");
}


static void CopyRows(const char *srcPixels, unsigned srcWidth, unsigned srcHeight, unsigned srcRowBytes, uint8_t *dstPixels)
{
	unsigned			y;
	unsigned			rowBytes;
	
	rowBytes = srcWidth * 4;
	
	if (rowBytes == srcRowBytes)
	{
		memcpy(dstPixels, srcPixels, srcHeight * rowBytes);
		return;
	}
	
	for (y = 0; y != srcHeight; ++y)
	{
		__builtin_memcpy(dstPixels, srcPixels, rowBytes);
		dstPixels += rowBytes;
		srcPixels += rowBytes;
	}
}
