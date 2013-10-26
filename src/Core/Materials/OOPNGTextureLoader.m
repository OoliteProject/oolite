/*

OOPNGTextureLoader.m


Copyright (C) 2007-2013 Jens Ayton

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

#import "OOPNGTextureLoader.h"
#import "OOFunctionAttributes.h"
#import "OOLogging.h"
#import "OOCPUInfo.h"
#import "NSDataOOExtensions.h"

void png_error(png_structp, png_const_charp) NO_RETURN_FUNC;


static void PNGError(png_structp png, png_const_charp message);
static void PNGWarning(png_structp png, png_const_charp message);
static void PNGRead(png_structp png, png_bytep bytes, png_size_t size);


@interface OOPNGTextureLoader (OOPrivate)

- (void)doLoadTexture;
- (void)readBytes:(png_bytep)bytes count:(png_size_t)count;

@end


@implementation OOPNGTextureLoader

- (void)loadTexture
{
	// Get data from file
	fileData = [[NSData oo_dataWithOXZFile:_path] retain];
	if (fileData == nil)  return;
	length = [fileData length];
	
	[self doLoadTexture];
	
	[fileData release];
	fileData = nil;
}


- (void)dealloc
{
	[fileData release];
	if (png != NULL)
	{
		png_destroy_read_struct(&png, &pngInfo, &pngEndInfo);
	}
	
	[super dealloc];
}

@end


@implementation OOPNGTextureLoader (OOPrivate)

- (void)doLoadTexture
{
	png_bytepp					rows = NULL;
	png_uint_32					pngWidth,
								pngHeight;
	int							depth,
								colorType;
	uint32_t					i;
	
	// Set up PNG decoding
	png = png_create_read_struct(PNG_LIBPNG_VER_STRING, self, PNGError, PNGWarning);
	if (png != NULL)  pngInfo = png_create_info_struct(png);
	if (pngInfo != NULL)  pngEndInfo = png_create_info_struct(png);
	if (pngEndInfo == NULL)
	{
		OOLog(@"texture.load.png.setup.failed", @"***** Error preparing to read %@.", _path);
		goto FAIL;
	}
	
	if (EXPECT_NOT(setjmp(png_jmpbuf(png))))
	{
		// libpng will jump here on error.
		if (_data)
		{
			free(_data);
			_data = NULL;
		}
		goto FAIL;
	}
	
	png_set_read_fn(png, self, PNGRead);
	
	png_read_info(png, pngInfo);
	// Read header, get format info and check that it meets our expectations.
	if (EXPECT_NOT(!png_get_IHDR(png, pngInfo, &pngWidth, &pngHeight, &depth, &colorType, NULL, NULL, NULL)))
	{
		OOLog(@"texture.load.png.failed", @"Failed to get metadata from PNG %@", _path);
		goto FAIL;
	}
	png_set_strip_16(png);			// 16 bits per channel -> 8 bpc
	if (depth < 8 || colorType == PNG_COLOR_TYPE_PALETTE)
	{
		png_set_expand(png);		// Paletted -> RGB, greyscale -> 8 bpc
	}
	
	if (colorType == PNG_COLOR_TYPE_GRAY)
	{
		_format = kOOTextureDataGrayscale;
	}
	else if (colorType == PNG_COLOR_TYPE_GRAY_ALPHA)
	{
		_format = kOOTextureDataGrayscaleAlpha;
	}
	else
	{
		_format = kOOTextureDataRGBA;
		
#if OOLITE_BIG_ENDIAN
		png_set_bgr(png);
		png_set_swap_alpha(png);		// RGBA->ARGB
		png_set_filler(png, 0xFF, PNG_FILLER_BEFORE);
#elif OOLITE_LITTLE_ENDIAN
		png_set_filler(png, 0xFF, PNG_FILLER_AFTER);
#else
#error Unknown handle byte order.
#endif
	}
	
	png_read_update_info(png, pngInfo);
	png_set_interlace_handling(png);
	
	// Metadata is acceptable; load data.
	_width = pngWidth;
	_height = pngHeight;
	_rowBytes = png_get_rowbytes(png, pngInfo);
	
	// png_read_png
	rows = malloc(sizeof *rows * _height);
	_data = malloc(_rowBytes * _height);
	if (EXPECT_NOT(rows == NULL || _data == NULL))
	{
		if (rows != NULL)
		{
			free(rows);
			rows = NULL;
		}
		if (_data != NULL)
		{
			free(_data);
			_data = NULL;
		}
		OOLog(kOOLogAllocationFailure, @"Failed to allocate space (%zu bytes) for texture %@", _rowBytes * _height, _path);
		goto FAIL;
	}
	
	for (i = 0; i != _height; ++i)
	{
		rows[i] = ((png_bytep)_data) + i * _rowBytes;
	}
	png_read_image(png, rows);
	png_read_end(png, pngEndInfo);
	
FAIL:
	free(rows);
	png_destroy_read_struct(&png, &pngInfo, &pngEndInfo);
}


- (void)readBytes:(png_bytep)bytes count:(png_size_t)count
{
	// Check that we're within the file's bounds
	if (EXPECT_NOT(length - offset < count))
	{
		NSString *message = [NSString stringWithFormat:@"attempt to read beyond end of file (%@), file may be truncated.", _path];
		png_error(png, [message UTF8String]);	// Will not return
	}
	
	assert(bytes != NULL);
	
	// Copy bytes
	memcpy(bytes, [fileData bytes] + offset, count);
	offset += count;
}

@end


/*	Minor detail: libpng 1.4.0 removed trailing .s from error and warning
	messages. It's also binary-incompatible with 1.2 and earlier, so it's
	reasonable to make this test at build time.
*/
#if PNG_LIBPNG_VER >= 10400
#define MSG_TERMINATOR "."
#else
#define MSG_TERMINATOR ""
#endif


static void PNGError(png_structp png, png_const_charp message)
{
	OOPNGTextureLoader *loader = png_get_io_ptr(png);
	OOLog(@"texture.load.png.error", @"***** A PNG loading error occurred for %@: %s" MSG_TERMINATOR, [loader path], message);
	
#if PNG_LIBPNG_VER >= 10500
	png_longjmp(png, 1);
#else
	longjmp(png_jmpbuf(png), 1);
#endif
}


static void PNGWarning(png_structp png, png_const_charp message)
{
	OOPNGTextureLoader *loader = png_get_io_ptr(png);
	OOLog(@"texture.load.png.warning", @"----- A PNG loading warning occurred for %@: %s" MSG_TERMINATOR, [loader path], message);
}


static void PNGRead(png_structp png, png_bytep bytes, png_size_t size)
{
	OOPNGTextureLoader *loader = png_get_io_ptr(png);
	[loader readBytes:bytes count:size];
}
