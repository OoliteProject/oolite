/*

OOTextureChannelExtractor.m


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

Copyright (C) 2007-2010 Jens Ayton

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

#include "OOTextureChannelExtractor.h"
#import "OOCPUInfo.h"


static void ExtractChannel_4(OOPixMap *ioPixMap, OOPixMapComponentCount channelIndex);


BOOL OOExtractPixMapChannel(OOPixMap *ioPixMap, OOPixMapComponentCount channelIndex, BOOL compactWhenDone)
{
	if (EXPECT_NOT(ioPixMap == NULL || !OOIsValidPixMap(*ioPixMap) || ioPixMap->components != 4 || channelIndex > 3))
	{
		return NO;
	}
	
	OODumpPixMap(*ioPixMap, @"pre-extraction");
	
	ExtractChannel_4(ioPixMap, channelIndex);
	
	ioPixMap->components = 1;
	ioPixMap->rowBytes = ioPixMap->width;
	
	if (compactWhenDone)
	{
		OOCompactPixMap(ioPixMap);
	}
	
	OODumpPixMap(*ioPixMap, @"extracted");
	
	return YES;
}


static void ExtractChannel_4(OOPixMap *ioPixMap, OOPixMapComponentCount channelIndex)
{
	uint32_t			*src;
	uint8_t				*dst;
	uint_fast8_t		shift;
	uint_fast32_t		xCount, y;
	
	NSCParameterAssert(ioPixMap != NULL);
	
	dst = ioPixMap->pixels;
	
#if OOLITE_BIG_ENDIAN
	// FIXME: Not flipping here gives right result. Either we're doing something wrong somewhere, or I'm confused.
//	shift = 24 - 8 * channelIndex;
	shift = 8 * channelIndex;
#elif OOLITE_LITTLE_ENDIAN
	shift = 8 * channelIndex;
#else
#error Unknown byte order.
#endif
	
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
