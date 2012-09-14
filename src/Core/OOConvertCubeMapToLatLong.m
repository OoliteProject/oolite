/*

OOConvertCubeMapToLatLong.m

Convert a cube map texture to a lat/long texture.


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

#import "OOConvertCubeMapToLatLong.h"
#import "OOTextureScaling.h"


#define kPiF			(3.14159265358979323846264338327950288f)


OOPixMap OOConvertCubeMapToLatLong(OOPixMap sourcePixMap, OOPixMapDimension height, BOOL leaveSpaceForMipMaps)
{
	if (!OOIsValidPixMap(sourcePixMap) || sourcePixMap.format != kOOPixMapRGBA || sourcePixMap.height != sourcePixMap.width * 6)
	{
		return kOONullPixMap;
	}
	
	NSCParameterAssert(height > 0);
	
	height *= 2;
	OOPixMapDimension width = height * 2;
	OOPixMap outPixMap = OOAllocatePixMap(width, height, 4, 0, 0);
	if (!OOIsValidPixMap(outPixMap))  return kOONullPixMap;
	
	OOPixMapDimension x, y;
	uint32_t *pixel = outPixMap.pixels;
	float fheight = height;
	float rheight = 1.0f / fheight;
	
	float halfSize = (sourcePixMap.width - 1) * 0.5f;
	uint8_t *srcBytes = sourcePixMap.pixels;
	
	// Build tables of sin/cos of longitude.
	float sinTable[width];
	float cosTable[width];
	for (x = 0; x < width; x++)
	{
		float lon = ((float)x * rheight) * kPiF;
		sinTable[x] = sin(lon);
		cosTable[x] = cos(lon);
	}
	
	for (y = 0; y < height; y++)
	{
		// Calcuate sin/cos of latitude.
		/*
			Clang static analyzer (Xcode 3.2.5 version, through to Xcode 4.4
			and freestanding checker-268 at least) says:
			"Assigned value is garbage or undefined."
			Memsetting sinTable to all-zeros moves this to the cosTable line.
			Since every value in each of those tables is in fact defined, this
			is an error in the analyzer.
			-- Ahruman 2011-01-25/2012-09-14
		*/
		float cy = -sinTable[width * 3 / 4 - y];
		float lac = -cosTable[width * 3 / 4 - y];
		float ay = fabs(cy);
		
		for (x = 0; x < width; x++)
		{
			float cx = sinTable[x] * lac;
			float cz = cosTable[x] * lac;
			
			float ax = fabs(cx);
			float az = fabs(cz);
			
			// Y offset of start of this face in image.
			OOPixMapDimension yOffset;
			
			// Coordinates within selected face.
			float x, y, r;
			
			// Select source face.
			if (ax >= ay && ax >= az)
			{
				x = cz;
				y = -cy;
				r = ax;
				if (0.0f < cx)
				{
					yOffset = 0;
				}
				else
				{
					x = -x;
					yOffset = 1;
				}
			}
			else if (ay >= ax && ay >= az)
			{
				x = cx;
				y = cz;
				r = ay;
				if (0.0f < cy)
				{
					y = -y;
					yOffset = 2;
				}
				else
				{
					yOffset = 3;
				}
			}
			else
			{
				x = cx;
				y = -cy;
				r = az;
				if (0.0f < cz)
				{
					x = -x;
					yOffset = 5;
				}
				else
				{
					yOffset = 4;
				}		
			}
			
			// Scale coordinates.
			r = 1.0f / r;
			OOPixMapDimension ix = (x * r + 1.0f) * halfSize;
			OOPixMapDimension iy = (y * r + 1.0f) * halfSize;
			
#ifndef NDEBUG
			assert(ix < sourcePixMap.width && iy < sourcePixMap.width);
#endif
			
			// Look up pixel.
			iy += sourcePixMap.width * yOffset;
			
			uint32_t *row = (uint32_t *)(srcBytes + iy * sourcePixMap.rowBytes);
			*pixel++ = row[ix];
		}
	}
	
	// Scale to half size for supersamplingness.
	return OOScalePixMap(outPixMap, width / 2, height / 2, leaveSpaceForMipMaps);
}
