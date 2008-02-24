/*

OOTextureScaling.h

Functions used to rescale texture maps.
These are bottlenecks! They should be optimized or, better, replaced with use
of an optimized library.

Oolite
Copyright (C) 2004-2008 Giles C Williams and contributors

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

#import "OOMaths.h"


typedef uint_fast32_t		OOTextureDimension;		// Note: dimensions are assumed to be less than 1048576 (2^20) pixels.
typedef uint_fast8_t		OOTexturePlaneCount;	// Currently supported values are 1 and 4.


/*	Assumes 8 bits per sample, interleaved.
	dstPixels must have space for dstWidth * dstHeight pixels (no row padding
	is generated).
	
	IMPORTANT: this will free() srcPixels.
*/
void *OOScalePixMap(void *srcPixels, OOTextureDimension srcWidth, OOTextureDimension srcHeight, OOTexturePlaneCount planes, size_t srcRowBytes, OOTextureDimension dstWidth, OOTextureDimension dstHeight, BOOL leaveSpaceForMipMaps);


/*	Assumes 8 bits per sample, interleaved.
	Buffer must have space for (4 * width * height) / 3 pixels.
*/
BOOL OOGenerateMipMaps(void *textureBytes, OOTextureDimension width, OOTextureDimension height, OOTexturePlaneCount planes);
