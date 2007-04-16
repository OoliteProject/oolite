/*

OOPNGTextureLoader.m

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

#import "OOPNGTextureLoader.h"
#import "png.h"
#import "OOFunctionAttributes.h"
#import "OOCPUInfo.h"


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
	fileData = [[NSData alloc] initWithContentsOfMappedFile:path];
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
	BOOL						grayscale;
	uint8_t						planes;
	
	// Set up PNG decoding
	png = png_create_read_struct(PNG_LIBPNG_VER_STRING, NULL, PNGError, PNGWarning);
	if (png == NULL)
	{
		OOLog(@"texture.load.png.setup.failed", @"***** Error preparing to read %@.", path);
		return;
	}
	
	pngInfo = png_create_info_struct(png);
	if (pngInfo == NULL)
	{
		OOLog(@"texture.load.png.setup.failed", @"***** Error preparing to read %@.", path);
		return;
	}
	
	pngEndInfo = png_create_info_struct(png);
	if (pngInfo == NULL)
	{
		OOLog(@"texture.load.png.setup.failed", @"***** Error preparing to read %@.", path);
		return;
	}
	
	if (EXPECT_NOT(setjmp(png_jmpbuf(png))))
	{
		// libpng will jump here on error.
		if (data)
		{
			free(data);
			data = NULL;
		}
		return;
	}
	
	png_set_read_fn(png, self, PNGRead);
	
	png_read_info(png, pngInfo);
	// Read header, get format info and check that it meets our expectations.
	if (EXPECT_NOT(!png_get_IHDR(png, pngInfo, &pngWidth, &pngHeight, &depth, &colorType, NULL, NULL, NULL)))
	{
		OOLog(@"texture.load.png.failed", @"Failed to get metadata from PNG %@", path);
		return;
	}
	png_set_strip_16(png);			// 16 bits per channel -> 8 bpc
	png_set_packing(png);			// <8 bpc -> 8 bpc (is this needed with png_set_expand()?)
	if (depth < 8 || colorType == PNG_COLOR_TYPE_PALETTE)
	{
		png_set_expand(png);		// Paletted -> RGB, greyscale -> 8 bpc
	}
	if (colorType == PNG_COLOR_TYPE_GRAY)
	{
		// TODO: what about PNG_COLOR_TYPE_GRAY_ALPHA ?
		grayscale = YES;
		planes = 1;
		format = kOOTextureDataGrayscale;
		
	//	png_set_invert_mono(png);
	}
	else
	{
		grayscale = NO;
		planes = 4;
		format = kOOTextureDataRGBA;
		
#if OOLITE_BIG_ENDIAN
		png_set_bgr(png);
		png_set_swap_alpha(png);		// RGBA->ARGB
#endif
		
	//	if ((colorType & PNG_COLOR_MASK_ALPHA) == 0)
		{
			png_set_filler(png, 0xFF, PNG_FILLER_BEFORE);	// PNG_FILLER_AFTER for little-endian?
		}
	}
	
	png_read_update_info(png, pngInfo);
	
	// Metadata is acceptable; load data.
	width = pngWidth;
	height = pngHeight;
	rowBytes = png_get_rowbytes(png, pngInfo);
	
	// png_read_png
	rows = malloc(sizeof *rows * height);
	data = malloc(rowBytes * height);
	if (EXPECT_NOT(rows == NULL || data == NULL))
	{
		if (rows != NULL)  free(rows);
		if (data != NULL)
		{
			free(data);
			data = NULL;
		}
		OOLog(kOOLogAllocationFailure, @"Failed to allocate space (%u bytes) for texture %@", rowBytes * height, path);
		return;
	}
	
	for (i = 0; i != height; ++i)
	{
		rows[i] = ((png_bytep)data) + i * rowBytes;
	}
	png_set_rows(png, pngInfo, rows);
	png_read_image(png, rows);
	png_read_end(png, pngEndInfo);
	
	free(rows);
	
	png_destroy_read_struct(&png, &pngInfo, &pngEndInfo);
}


- (void)readBytes:(png_bytep)bytes count:(png_size_t)count
{
	// Check that we're within the file's bounds
	if (EXPECT_NOT(length - offset < count))
	{
		NSString *message = [NSString stringWithFormat:@"attempt to read beyond end of file (%@), file may be truncated.", path];
		png_error(png, [message UTF8String]);	// Will not return
	}
	
	assert(bytes != NULL);
	
	// Copy bytes
	memcpy(bytes, [fileData bytes] + offset, count);
	offset += count;
}

@end


static void PNGError(png_structp png, png_const_charp message)
{
	OOLog(@"texture.load.png.error", @"***** A PNG loading error occurred: %s", message);
}


static void PNGWarning(png_structp png, png_const_charp message)
{
	OOLog(@"texture.load.png.warning", @"***** A PNG loading warning occurred: %s", message);
}


static void PNGRead(png_structp png, png_bytep bytes, png_size_t size)
{
	OOPNGTextureLoader *loader = png_get_io_ptr(png);
	[loader readBytes:bytes count:size];
}
