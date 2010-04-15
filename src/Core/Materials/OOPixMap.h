/*

OOPixMap.h

Types for low-level pixel map manipulation.


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

#import "OOMaths.h"


typedef uint_fast32_t		OOPixMapDimension;		// Note: dimensions are assumed to be less than 1048576 (2^20) pixels.
typedef uint_fast8_t		OOPixMapComponentCount;	// Currently supported values are 1, 2 and 4.


typedef struct
{
	void					*pixels;
	OOPixMapDimension		width, height;
	OOPixMapComponentCount	components;
	size_t					rowBytes;
	size_t					bufferSize;
} OOPixMap;


extern const OOPixMap kOONullPixMap;


OOINLINE BOOL OOIsNullPixMap(OOPixMap pixMap)  { return pixMap.pixels == NULL; }
BOOL OOIsValidPixMap(OOPixMap pixMap);


/*	OOMakePixMap()
	Stuff an OOPixMap struct. Returns kOONullPixMap if the result would be
	invalid. If rowBytes or bufferSize are zero, minimum valid values will be
	used.
*/
OOPixMap OOMakePixMap(void *pixels, OOPixMapDimension width, OOPixMapDimension height, OOPixMapComponentCount components, size_t rowBytes, size_t bufferSize);

/*	OOAllocatePixMap()
	Create an OOPixMap, allocating storage. If rowBytes or bufferSize are zero,
	minimum valid values will be used.
*/
OOPixMap OOAllocatePixMap(OOPixMapDimension width, OOPixMapDimension height, OOPixMapComponentCount components, size_t rowBytes, size_t bufferSize);


/*	OOCompactPixMap()
	Remove any trailing space in a pixmap's buffer, if possible.
*/
void OOCompactPixMap(OOPixMap *ioPixMap);


/*	OOExpandPixMap()
	Expand pixmap to at least desiredSize bytes. Returns false on failure.
*/
BOOL OOExpandPixMap(OOPixMap *ioPixMap, size_t desiredSize);


#ifndef NDEBUG
void OODumpPixMap(OOPixMap pixMap, NSString *name);
#endif
