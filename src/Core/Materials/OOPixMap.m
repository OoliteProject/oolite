/*

OOPixMap.c


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

#import "OOPixMap.h"


const OOPixMap kOONullPixMap =
{
	.pixels = NULL,
	.width = 0,
	.height = 0,
	.components = 0,
	.rowBytes = 0,
	.bufferSize = 0
};


BOOL OOIsValidPixMap(OOPixMap pixMap)
{
	return	pixMap.pixels != NULL &&
			pixMap.width > 0 &&
			pixMap.height > 0 &&
		   (pixMap.components == 1 || pixMap.components == 2 || pixMap.components == 4) &&
			pixMap.rowBytes >= pixMap.width * pixMap.components &&
			pixMap.bufferSize >= pixMap.rowBytes * pixMap.height;
}


OOPixMap OOMakePixMap(void *pixels, OOPixMapDimension width, OOPixMapDimension height, OOPixMapComponentCount components, size_t rowBytes, size_t bufferSize)
{
	if (rowBytes == 0)  rowBytes = width * components;
	if (bufferSize == 0)  bufferSize = rowBytes * height;
	
	OOPixMap result =
	{
		.pixels = pixels,
		.width = width,
		.height = height,
		.components = components,
		.rowBytes = rowBytes,
		.bufferSize = bufferSize
	};
	
	if (OOIsValidPixMap(result))  return result;
	else  return kOONullPixMap;
}


OOPixMap OOAllocatePixMap(OOPixMapDimension width, OOPixMapDimension height, OOPixMapComponentCount components, size_t rowBytes, size_t bufferSize)
{
	// Create pixmap struct with dummy pixel pointer to test validity.
	OOPixMap pixMap = OOMakePixMap((void *)-1, width, height, components, rowBytes, bufferSize);
	if (EXPECT_NOT(!OOIsValidPixMap(pixMap)))  return kOONullPixMap;
	
	pixMap.pixels = malloc(pixMap.bufferSize);
	if (EXPECT_NOT(pixMap.pixels == NULL))  return kOONullPixMap;
	
	return pixMap;
}


void OOFreePixMap(OOPixMap *ioPixMap)
{
	if (EXPECT_NOT(ioPixMap == NULL))  return;
	
	free(ioPixMap->pixels);
	*ioPixMap = kOONullPixMap;
}


OOPixMap OODuplicatePixMap(OOPixMap srcPixMap, size_t desiredSize)
{
	if (EXPECT_NOT(!OOIsValidPixMap(srcPixMap)))  return kOONullPixMap;
	
	size_t minSize = OOMinimumPixMapBufferSize(srcPixMap);
	if (desiredSize < minSize)  desiredSize = minSize;
	
	OOPixMap result = OOAllocatePixMap(srcPixMap.width, srcPixMap.width, srcPixMap.components, srcPixMap.rowBytes, desiredSize);
	if (EXPECT_NOT(!OOIsValidPixMap(result)))  return kOONullPixMap;
	
	memcpy(result.pixels, srcPixMap.pixels, minSize);
	return result;
}


BOOL OOResizePixMap(OOPixMap *ioPixMap, size_t desiredSize)
{
	if (EXPECT_NOT(ioPixMap == NULL || !OOIsValidPixMap(*ioPixMap)))  return NO;
	if (desiredSize == ioPixMap->bufferSize)  return YES;
	if (desiredSize < OOMinimumPixMapBufferSize(*ioPixMap))  return NO;
	
	void *newPixels = realloc(ioPixMap->pixels, desiredSize);
	if (newPixels != NULL)
	{
		ioPixMap->pixels = newPixels;
		ioPixMap->bufferSize = desiredSize;
		return YES;
	}
	else
	{
		return NO;
	}
}


BOOL OOExpandPixMap(OOPixMap *ioPixMap, size_t desiredSize)
{
	if (EXPECT_NOT(ioPixMap == NULL || !OOIsValidPixMap(*ioPixMap)))  return NO;
	if (desiredSize <= ioPixMap->bufferSize)  return YES;
	
	return OOResizePixMap(ioPixMap, desiredSize);
}


#ifndef NDEBUG

#import "Universe.h"
#import "MyOpenGLView.h"


void OODumpPixMap(OOPixMap pixMap, NSString *name)
{
	if (!OOIsValidPixMap(pixMap))  return;
	
	MyOpenGLView *gameView = [UNIVERSE gameView];
	
	switch (pixMap.components)
	{
		case 1:
			[gameView dumpGrayToFileNamed:name
									bytes:pixMap.pixels
									width:pixMap.width
								   height:pixMap.height
								 rowBytes:pixMap.rowBytes];
			break;
			
		case 2:
			[gameView dumpGrayAlphaToFileNamed:name
										 bytes:pixMap.pixels
										 width:pixMap.width
										height:pixMap.height
									  rowBytes:pixMap.rowBytes];
			break;
			
		case 3:
			[gameView dumpRGBAToFileNamed:name
									bytes:pixMap.pixels
									width:pixMap.width
								   height:pixMap.height
								 rowBytes:pixMap.rowBytes];
			break;
			
		case 4:
			[gameView dumpRGBAToRGBFileNamed:[name stringByAppendingString:@" rgb"]
							andGrayFileNamed:[name stringByAppendingString:@" alpha"]
									   bytes:pixMap.pixels
									   width:pixMap.width
									  height:pixMap.height
									rowBytes:pixMap.rowBytes];
			break;
	}
}

#endif
