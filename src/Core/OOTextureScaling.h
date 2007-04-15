/*

OOTextureScaling.h

Functions used to rescale texture maps.
These are bottlenecks! They should be optimized or, better, replaced with use
of an optimized library.

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

#import "OOMaths.h"


uint8_t *ScaleUpPixMap(uint8_t *srcPixels, unsigned srcWidth, unsigned srcHeight, unsigned srcBytesPerRow, unsigned planes, unsigned dstWidth, unsigned dstHeight);


/*	Assumes 8 bits per sample, interleaved.
	dstPixels must have space for dstWidth * dstHeight pixels (no row padding
	is generated).
*/
BOOL ScalePixMap(void *srcPixels, uint32_t srcWidth, uint32_t srcHeight, uint8_t planes, uint32_t srcRowBytes, void *dstPixels, uint32_t dstWidth, uint32_t dstHeight);


/*	Assumes 8 bits per sample, interleaved.
	Buffer must have space for (4 * width * height) / 3 pixels.
*/
BOOL GenerateMipMaps(void *textureBytes, uint32_t width, uint32_t height, uint8_t planes);
