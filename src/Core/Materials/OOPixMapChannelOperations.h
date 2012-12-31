/*

OOPixMapChannelOperations.h

Utility to convert one channel of an RGBA texture into a greyscale texture.


Copyright (C) 2010-2013 Jens Ayton

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
BOOL OOExtractPixMapChannel(OOPixMap *ioPixMap, uint8_t channelIndex, BOOL compactWhenDone);


/*	OOPixMapToRGBA()
	Convert a pixmap to RGBA format.
	NOTE: if successful, this will free() the original buffer and replace it.
*/
BOOL OOPixMapToRGBA(OOPixMap *ioPixMap);


/*	OOPixMapModulateUniform()
	Multiply all pixels by specified per-component factors. Pixmap must be in
	RGBA format. The effect of using factors outside the range [0..1] is
	undefined.
	OOPixMapToRGBA() is called on ioPixMap.
*/
BOOL OOPixMapModulateUniform(OOPixMap *ioPixMap, float f0, float f1, float f2, float f3);


/*	OOPixMapModulatePixMap()
	Multiply each pixel of ioDstPixMap by the corresponding pixel of otherPixMap,
	writing the result to ioDstPixMap.
	OOPixMapToRGBA() is called on ioDstPixMap; otherPixMap must be RGBA.
*/
BOOL OOPixMapModulatePixMap(OOPixMap *ioDstPixMap, OOPixMap otherPixMap);


/*	OOPixMapAddPixMap()
	Add each pixel of otherPixMap to the corresponding pixel of ioDstPixMap,
	writing the result to ioDstPixMap.
	OOPixMapToRGBA() is called on ioDstPixMap; otherPixMap must be RGBA.
*/
BOOL OOPixMapAddPixMap(OOPixMap *ioDstPixMap, OOPixMap otherPixMap);
