/*

OOPixMap.h

Types for low-level pixel map manipulation.


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

#import "OOMaths.h"


typedef uint_fast32_t		OOPixMapDimension;		// Note: dimensions are assumed to be less than 1048576 (2^20) pixels.

#define OORoundUpToPowerOf2_PixMap OORoundUpToPowerOf2_32


typedef enum
{
	kOOPixMapInvalidFormat		= 0,
	kOOPixMapGrayscale			= 1,
	kOOPixMapGrayscaleAlpha		= 2,
	kOOPixMapRGBA				= 4
} OOPixMapFormat;


typedef struct OOPixMap
{
	void					*pixels;
	OOPixMapDimension		width, height;
	OOPixMapFormat			format;
	size_t					rowBytes;
	size_t					bufferSize;
} OOPixMap;


extern const OOPixMap kOONullPixMap;


OOINLINE BOOL OOIsNullPixMap(OOPixMap pixMap)  { return pixMap.pixels == NULL; }
BOOL OOIsValidPixMap(OOPixMap pixMap);
OOINLINE size_t OOMinimumPixMapBufferSize(OOPixMap pixMap)  { return pixMap.rowBytes * pixMap.height; }


/*	OOMakePixMap()
	Stuff an OOPixMap struct. Returns kOONullPixMap if the result would be
	invalid. If rowBytes or bufferSize are zero, minimum valid values will be
	used.
*/
OOPixMap OOMakePixMap(void *pixels, OOPixMapDimension width, OOPixMapDimension height, OOPixMapFormat format, size_t rowBytes, size_t bufferSize);

/*	OOAllocatePixMap()
	Create an OOPixMap, allocating storage. If rowBytes or bufferSize are zero,
	minimum valid values will be used.
*/
OOPixMap OOAllocatePixMap(OOPixMapDimension width, OOPixMapDimension height, OOPixMapFormat format, size_t rowBytes, size_t bufferSize);


/*	OOFreePixMap()
	Deallocate a pixmap's buffer (with free()), and clear out the struct.
*/
void OOFreePixMap(OOPixMap *ioPixMap);


/*	OODuplicatePixMap()
	Create a pixmap with the same pixel contents as a source pixmap, and
	optional padding. If desiredSize is less than the required space for the
	pixmap, it will be ignored. The contents of padding bytes are unspecified.
*/
OOPixMap OODuplicatePixMap(OOPixMap srcPixMap, size_t desiredSize);


/*	OOResizePixMap()
	Set the size of a pixmap's buffer. Fails if specified size is smaller than
	required to fit the current pixels.
*/
BOOL OOResizePixMap(OOPixMap *ioPixMap, size_t desiredSize);


/*	OOCompactPixMap()
	Remove any trailing space in a pixmap's buffer, if possible.
*/
OOINLINE void OOCompactPixMap(OOPixMap *ioPixMap)  { OOResizePixMap(ioPixMap, OOMinimumPixMapBufferSize(*ioPixMap)); }


/*	OOExpandPixMap()
	Expand pixmap to at least desiredSize bytes. Returns false on failure.
*/
BOOL OOExpandPixMap(OOPixMap *ioPixMap, size_t desiredSize);


#ifndef NDEBUG
void OODumpPixMap(OOPixMap pixMap, NSString *name);
#else
#define OODumpPixMap(p, n)  do {} while (0)
#endif


BOOL OOIsValidPixMapFormat(OOPixMapFormat format);


#ifndef NDEBUG
unsigned short OOPixMapBytesPerPixelForFormat(OOPixMapFormat format) PURE_FUNC;
#else
OOINLINE unsigned short OOPixMapBytesPerPixelForFormat(OOPixMapFormat format)
{
	// Currently, format values are component counts. This is subject to change.
	return format;
}
#endif

OOINLINE unsigned short OOPixMapBytesPerPixel(OOPixMap pixMap)
{
	return OOPixMapBytesPerPixelForFormat(pixMap.format);
}

NSString *OOPixMapFormatName(OOPixMapFormat format) PURE_FUNC;

BOOL OOPixMapFormatHasAlpha(OOPixMapFormat format) PURE_FUNC;
