/*

OOPixMapChannelOperations.m


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

#include "OOPixMapChannelOperations.h"
#import "OOCPUInfo.h"


static void ExtractChannel_4(OOPixMap *ioPixMap, uint8_t channelIndex);
static void ToRGBA_1(OOPixMap srcPx, OOPixMap dstPx);
static void ToRGBA_2(OOPixMap srcPx, OOPixMap dstPx);
static void ModulateUniform_4(OOPixMap pixMap, uint16_t f0, uint16_t f1, uint16_t f2, uint16_t f3);
static void ModulatePixMap_4(OOPixMap mainPx, OOPixMap otherPx);
static void AddPixMap_4(OOPixMap mainPx, OOPixMap otherPx);


BOOL OOExtractPixMapChannel(OOPixMap *ioPixMap, uint8_t channelIndex, BOOL compactWhenDone)
{
	if (EXPECT_NOT(ioPixMap == NULL || !OOIsValidPixMap(*ioPixMap) || ioPixMap->format != kOOPixMapRGBA || channelIndex > 3))
	{
		return NO;
	}
	
	ExtractChannel_4(ioPixMap, channelIndex);
	
	ioPixMap->format = kOOPixMapGrayscale;
	ioPixMap->rowBytes = ioPixMap->width;
	
	if (compactWhenDone)
	{
		OOCompactPixMap(ioPixMap);
	}
	
	return YES;
}


static void ExtractChannel_4(OOPixMap *ioPixMap, uint8_t channelIndex)
{
	NSCParameterAssert(ioPixMap != NULL);
	
	uint32_t			*src;
	uint8_t				*dst;
	uint_fast8_t		shift;
	uint_fast32_t		xCount, y;
	
	dst = ioPixMap->pixels;
	shift = 8 * channelIndex;
	
	for (y = 0; y < ioPixMap->height; y++)
	{
		src = (uint32_t *)((char *)ioPixMap->pixels + y * ioPixMap->rowBytes);
		xCount = ioPixMap->width;
		
		do
		{
			*dst++ = (*src++ >> shift) & 0xFF;
		}
		while (--xCount);
	}
}


BOOL OOPixMapToRGBA(OOPixMap *ioPixMap)
{
	if (EXPECT_NOT(ioPixMap == NULL || !OOIsValidPixMap(*ioPixMap)))  return NO;
	if (ioPixMap->format == kOOPixMapRGBA)  return YES;
	
	OOPixMap temp = OOAllocatePixMap(ioPixMap->width, ioPixMap->height, 4, 0, 0);
	if (EXPECT_NOT(OOIsNullPixMap(temp)))  return NO;
	
	BOOL OK = NO;
	switch (ioPixMap->format)
	{
		case kOOPixMapGrayscale:
			ToRGBA_1(*ioPixMap, temp);
			OK = YES;
			break;
			
		case kOOPixMapGrayscaleAlpha:
			ToRGBA_2(*ioPixMap, temp);
			OK = YES;
			break;
			
		case kOOPixMapRGBA:
		case kOOPixMapInvalidFormat:
			OK = NO;
			break;
			// No default, because -Wswitch-enum is our friend.
	}
	
	if (OK)
	{
		free(ioPixMap->pixels);
		*ioPixMap = temp;
	}
	else
	{
		free(temp.pixels);
	}

	return OK;
}


static void ToRGBA_1(OOPixMap srcPx, OOPixMap dstPx)
{
	NSCParameterAssert(OOPixMapBytesPerPixel(srcPx) == 1 && dstPx.format == kOOPixMapRGBA && srcPx.width == dstPx.width && srcPx.height == dstPx.height);
	
	uint8_t				*src;
	uint32_t			*dst;
	uint_fast32_t		xCount, y;
	
	dst = dstPx.pixels;
	
	for (y = 0; y < srcPx.height; y++)
	{
		src = (uint8_t *)((char *)srcPx.pixels + y * srcPx.rowBytes);
		xCount = srcPx.width;
		
		do
		{
			*dst++ = (*src++ * 0x00010101) | 0xFF000000;
		}
		while (--xCount);
	}
}


static void ToRGBA_2(OOPixMap srcPx, OOPixMap dstPx)
{
	NSCParameterAssert(OOPixMapBytesPerPixel(srcPx) == 2 && dstPx.format == kOOPixMapRGBA && srcPx.width == dstPx.width && srcPx.height == dstPx.height);
	
	uint16_t			*src;
	uint_fast32_t		px;
	uint32_t			*dst;
	uint_fast32_t		xCount, y;
	
	dst = dstPx.pixels;
	
	for (y = 0; y < srcPx.height; y++)
	{
		src = (uint16_t *)((char *)srcPx.pixels + y * srcPx.rowBytes);
		xCount = srcPx.width;
		
		do
		{
			px = *src++;
#if OOLITE_BIG_ENDIAN
			*dst++ = (((px & 0xFF00) >> 8) * 0x00010101) | ((px & 0x00FF) << 24);
#elif OOLITE_LITTLE_ENDIAN
			*dst++ = ((px & 0x00FF) * 0x00010101) | ((px & 0xFF00) << 16);
#else
#error Unknown byte order.
#endif
		}
		while (--xCount);
	}
}


BOOL OOPixMapModulateUniform(OOPixMap *ioPixMap, float f0, float f1, float f2, float f3)
{
	if (EXPECT_NOT(ioPixMap == NULL || !OOIsValidPixMap(*ioPixMap)))  return NO;
	if (EXPECT_NOT(!OOPixMapToRGBA(ioPixMap)))  return NO;
	
	ModulateUniform_4(*ioPixMap, f0 * 256.0f, f1 * 256.0f, f2 * 256.0f, f3 * 256.0f);
	
	return YES;
}


static void ModulateUniform_4(OOPixMap pixMap, uint16_t f3, uint16_t f2, uint16_t f1, uint16_t f0)
{
	NSCParameterAssert(OOPixMapBytesPerPixel(pixMap) == 4);
	
	uint32_t			*curr;
	uint_fast32_t		px;
	uint_fast32_t		p0, p1, p2, p3;
	uint_fast32_t		xCount, y;
	
	for (y = 0; y < pixMap.height; y++)
	{
		curr = (uint32_t *)((char *)pixMap.pixels + y * pixMap.rowBytes);
		xCount = pixMap.width;
		
		do
		{
			px = *curr;
			
			/*	Principle of operation:
				Each pixel component is in the range 0..0xFF.
				Each constant factor component is in the range 0..0x100.
				Multiplying them therefore gives us a result in the range
				0x0000..0xFF00. The bottom byte is discarded by shifting
				and masking.
			*/
			
			p0 = px & 0xFF000000;
			p0 = ((p0 >> 8) * f0) & 0xFF000000;
			
			p1 = px & 0x00FF0000;
			p1 = ((p1 * f1) >> 8) & 0x00FF0000;
			
			p2 = px & 0x0000FF00;
			p2 = ((p2 * f2) >> 8) & 0x0000FF00;
			
			p3 = px & 0x000000FF;
			p3 = ((p3 * f3) >> 8) & 0x000000FF;
			
			px = p0 | p1 | p2 | p3;
			*curr++ = px;
		}
		while (--xCount);
	}
}


BOOL OOPixMapModulatePixMap(OOPixMap *ioDstPixMap, OOPixMap otherPixMap)
{
	if (EXPECT_NOT(ioDstPixMap == NULL || !OOIsValidPixMap(*ioDstPixMap)))  return NO;
	if (EXPECT_NOT(!OOIsValidPixMap(otherPixMap) || otherPixMap.format != kOOPixMapRGBA))  return NO;
	if (EXPECT_NOT(!OOPixMapToRGBA(ioDstPixMap)))  return NO;
	if (EXPECT_NOT(ioDstPixMap->width != otherPixMap.width || ioDstPixMap->height != otherPixMap.height))  return NO;
	
	ModulatePixMap_4(*ioDstPixMap, otherPixMap);
	
	return YES;
}


static void ModulatePixMap_4(OOPixMap mainPx, OOPixMap otherPx)
{
	uint32_t			*dst, *other;
	uint_fast32_t		px;
	uint_fast16_t		m0, m1, m2, m3;
	uint_fast16_t		o0, o1, o2, o3;
	uint_fast32_t		xCount, y;
	
	for (y = 0; y < mainPx.height; y++)
	{
		dst = (uint32_t *)((char *)mainPx.pixels + y * mainPx.rowBytes);
		other = (uint32_t *)((char *)otherPx.pixels + y * otherPx.rowBytes);
		xCount = mainPx.width;
		
		do
		{
			px = *dst;
			m0 = (px >> 24) & 0xFF;
			m1 = (px >> 16) & 0xFF;
			m2 = (px >> 8) & 0xFF;
			m3 = px & 0xFF;
			
			px = *other;
			o0 = (px >> 24) & 0xFF;
			o1 = (px >> 16) & 0xFF;
			o2 = (px >> 8) & 0xFF;
			o3 = px & 0xFF;
			
			/*	Unlike in ModulateUniform(), neither side here goes to 256, so
				we have to divide by 255 rather than shifting. However, the
				compiler should be able to optimize this to a multiplication
				by a magic number.
			*/
			m0 = (m0 * o0) / 255;
			m1 = (m1 * o1) / 255;
			m2 = (m2 * o2) / 255;
			m3 = (m3 * o3) / 255;
			
			*dst++ = ((uint_fast32_t)m0 << 24) | ((uint_fast32_t)m1 << 16) | (m2 << 8) | m3;
			other++;
		}
		while (--xCount);
	}
}


BOOL OOPixMapAddPixMap(OOPixMap *ioDstPixMap, OOPixMap otherPixMap)
{
	if (EXPECT_NOT(ioDstPixMap == NULL || !OOIsValidPixMap(*ioDstPixMap)))  return NO;
	if (EXPECT_NOT(!OOIsValidPixMap(otherPixMap) || otherPixMap.format != kOOPixMapRGBA))  return NO;
	if (EXPECT_NOT(!OOPixMapToRGBA(ioDstPixMap)))  return NO;
	if (EXPECT_NOT(ioDstPixMap->width != otherPixMap.width || ioDstPixMap->height != otherPixMap.height))  return NO;
	
	AddPixMap_4(*ioDstPixMap, otherPixMap);
	
	return YES;
}


static void AddPixMap_4(OOPixMap mainPx, OOPixMap otherPx)
{
	uint32_t			*dst, *other;
	uint_fast32_t		px;
	uint_fast32_t		m02, m13;
	uint_fast32_t		o02, o13;
	uint_fast32_t		xCount, y;
	
	for (y = 0; y < mainPx.height; y++)
	{
		dst = (uint32_t *)((char *)mainPx.pixels + y * mainPx.rowBytes);
		other = (uint32_t *)((char *)otherPx.pixels + y * otherPx.rowBytes);
		xCount = mainPx.width;
		
		do
		{
			px = *dst;
			m02 = (px & 0xFF00FF00) >> 8;
			m13 = px & 0x00FF00FF;
			
			px = *other;
			o02 = (px & 0xFF00FF00) >> 8;
			o13 = px & 0x00FF00FF;
			
			/*	Saturated adds, two components at a time.
				By masking out the overflow bits of each component,
				multiplying them by 0xFF and shifting right one byte, we get a
				mask that's oxFF for components that overflowed and 0x00 for
				components that did not, without any conditionals.
			*/
			m02 += o02;
			m02 |= ((m02 & 0x01000100) * 0xFF) >> 8;
			m13 += o13;
			m13 |= ((m13 & 0x01000100) * 0xFF) >> 8;
			
			*dst++ = ((m02 << 8) & 0xFF00FF00) | (m13 & 0x00FF00FF);
			other++;
		}
		while (--xCount);
	}
}

