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


void png_error(png_structp, png_const_charp) NO_RETURN_FUNC;


static void PNGError(png_structp png, png_const_charp message);
static void PNGWarning(png_structp png, png_const_charp message);
static void PNGRead(png_structp png, png_bytep bytes, png_size_t size);


@interface OOPNGTextureLoader (OOPrivate)

- (void)readBytes:(png_bytep)bytes count:(png_size_t)count;

@end


@implementation OOPNGTextureLoader

- (void)loadTexture
{
	png_bytepp					rows;
	png_uint_32					pngWidth,
								pngHeight;
	int							depth,
								colorType;
	uint32_t					i;
	
	// Get data from file
	fileData = [[NSData alloc] initWithContentsOfMappedFile:path];
	if (fileData == nil)  return;
	length = [fileData length];
	
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
	
	png_read_png(png, pngInfo, PNG_TRANSFORM_STRIP_16 | PNG_TRANSFORM_PACKING | PNG_TRANSFORM_SHIFT | PNG_TRANSFORM_SWAP_ALPHA, NULL);
	
	// We're done with the file now.
	[fileData release];
	fileData = nil;
	
	// Get format info and check that it meets our expectations.
	if (EXPECT_NOT(!png_get_IHDR(png, pngInfo, &pngWidth, &pngHeight, &depth, &colorType, NULL, NULL, NULL)))
	{
		OOLog(@"texture.load.png.failed", @"Failed to get metadata from PNG %@", path);
		return;
	}
	OOLog(@"texture.load.png.info", @"Loaded PNG %@\n\twidth: %u\n\theight: %u\n\tdepth: %i\n\tcolorType: %i", path, width, height, depth, colorType);
	
	// The png_read_png transformation options should have assured we got 8-bit ARGB.
	if (EXPECT_NOT(colorType != PNG_COLOR_TYPE_RGB_ALPHA || depth != 8))
	{
		OOLog(@"texture.load.png.failed", @"Unexpected PNG format (colour type %i, depth %i) for %@", colorType, depth, path);
		return;
	}
	
	// Data is good, allocate buffer and copy. TODO: avoid copying stage by using low-level PNG reading.
	width = pngWidth;
	height = pngHeight;
	rowBytes = width * 4;
	
	data = malloc(rowBytes * height);
	if (EXPECT_NOT(data == NULL))
	{
		OOLog(kOOLogAllocationFailure, @"Failed to allocate space (%u bytes) for texture %@", rowBytes * height, path);
		return;
	}
	
	rows = png_get_rows(png, pngInfo);
	if (EXPECT_NOT(data == NULL))
	{
		OOLog(@"texture.load.png.failed", @"Failed to get image rows for PNG %@", path);
		return;
	}
	
	for (i = 0; i != height; ++i)
	{
		memcpy(((uint8_t *)data) + height * rowBytes, rows[i], rowBytes);
	}
	
	if (png != NULL)
	{
		png_destroy_read_struct(&png, &pngInfo, &pngEndInfo);
	}
}


- (void)dealloc
{
	if (png != NULL)
	{
		png_destroy_read_struct(&png, &pngInfo, &pngEndInfo);
	}
	[fileData release];
	
	[super dealloc];
}

@end


@implementation OOPNGTextureLoader (OOPrivate)

- (void)readBytes:(png_bytep)bytes count:(png_size_t)count
{
	// Check that we're within the file's bounds
	if (EXPECT_NOT(length - offset < count))
	{
		NSString *message = [NSString stringWithFormat:@"attempt to read beyond end of file (%@), file may be truncated.", path];
		png_error(png, [message UTF8String]);	// Will not return
	}
	
	assert(bytes != NULL);
	
	OOLog(@"texture.load.png.read", @"Reading %u bytes starting at offset %u", count, offset);
	
	// Copy bytes
	memcpy(bytes, [fileData bytes], count);
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
