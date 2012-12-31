/*

OOConvertCubeMapToLatLong.h

Convert a cube map texture to a lat/long texture.


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


/*	OOConvertCubeMapToLatLong
	
	Given an RGBA pixmap containing a cube map texture, convert it to a latlong
	texture of (height * 2) by height pixels. The texture is also flipped, to
	account for Oolite texture coordianate conventions.
	
	The source pix map must have four components and be six times as high as
	it is wide.
	
	2 x 2 pixel supersampling is used.
*/
OOPixMap OOConvertCubeMapToLatLong(OOPixMap sourcePixMap, OOPixMapDimension height, BOOL leaveSpaceForMipMaps);
