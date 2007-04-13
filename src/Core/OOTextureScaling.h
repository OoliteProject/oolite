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

#import <stdint.h>


uint8_t *ScaleUpPixMap(uint8_t *srcPixels, unsigned srcWidth, unsigned srcHeight, unsigned srcBytesPerRow, unsigned planes, unsigned dstWidth, unsigned dstHeight);


/*	Assumes 4 planes, 8 bits per sample, interleaved.
	dstPixels must have space for dstWidth * dstHeight pixels (no row padding
	is generated).
*/
void ScalePixMap(void *srcPixels, unsigned srcWidth, unsigned srcHeight, unsigned srcRowBytes, void *dstPixels, unsigned dstWidth, unsigned dstHeight);

/*	Assumes 4 planes, 8 bits per sample, interleaved, with the first three
	forming a normalized vector.
	dstPixels must have space for dstWidth * dstHeight pixels (no row padding
	is generated).
*/
void ScaleNormalMap(void *srcTexels, unsigned srcWidth, unsigned srcHeight, unsigned srcRowBytes, void *dstTexels, unsigned dstWidth, unsigned dstHeight);


/*	Assumes 4 planes, 8 bits per sample, interleaved.
	Buffer must have space for (4 * width * height) / 3 pixels.
*/
void GenerateMipMaps(void *textureBytes, unsigned width, unsigned height);


/*	Assumes 4 planes, 8 bits per sample, interleaved.
	Buffer must have space for (4 * width * height) / 3 pixels.
*/
void GenerateNormalMapMipMaps(void *textureBytes, unsigned width, unsigned height);
