/*

OOPixMapChannelOperations.h

Utility to convert one channel of an RGBA texture into a greyscale texture.


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


/*	OOExtractPixMapChannel()
	Given a 4-channel pixmap, extract one channel, producing a single-channel
	pixmap. This is done in place, destroying the original data.
	ChannelIndex specifies which component to extract. This is a per-pixel
	byte index: 0 means bytes bytes 0, 4, 8 etc. will be used, 2 means bytes
	2, 6, 10 etc. will be used.
	Returns false (without modifying the pixmap) if passed NULL, an invalid
	pixmap, a pixmap whose channel count is not 4, or a channel index greater
	than 3.
*/
BOOL OOExtractPixMapChannel(OOPixMap *ioPixMap, OOPixMapComponentCount channelIndex, BOOL compactWhenDone);


/*	OOPixMapToRGBA()
	Convert a pixmap to RGBA format. If it has one component, it is assumed to
	be greyscale. If it has two components, it is assumed to be greyscale+alpha.
	If it has four components, it is left as-is.
	NOTE: if successful, this will free() the original buffer and replace it.
*/
BOOL OOPixMapToRGBA(OOPixMap *ioPixMap);


/*	OOPixMapModulateUniform()
	Multiply all pixels by specified per-component factors. Pixmap must have
	four components. The effect of using factors outside the range [0..1] is
	undefined.
	OOPixMapToRGBA() is called on ioPixMap.
*/
BOOL OOPixMapModulateUniform(OOPixMap *ioPixMap, float f0, float f1, float f2, float f3);


/*	OOPixMapModulatePixMap()
	Multiply each pixel of ioDstPixMap by the corresponding pixel of otherPixMap,
	writing the result to ioDstPixMap.
	OOPixMapToRGBA() is called on ioDstPixMap; otherPixMap must have four components.
*/
BOOL OOPixMapModulatePixMap(OOPixMap *ioDstPixMap, OOPixMap otherPixMap);


/*	OOPixMapAddPixMap()
	Add each pixel of otherPixMap to the corresponding pixel of ioDstPixMap,
	writing the result to ioDstPixMap.
	OOPixMapToRGBA() is called on ioDstPixMap; otherPixMap must have four components.
*/
BOOL OOPixMapAddPixMap(OOPixMap *ioDstPixMap, OOPixMap otherPixMap);
