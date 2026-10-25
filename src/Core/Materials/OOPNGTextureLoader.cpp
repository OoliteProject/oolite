/*

OOPNGTextureLoader.mm


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

#include "OOPNGTextureLoader.h"
#include "OOFunctionAttributes.h"
#include "OOLogging.h"
#include "OOCPUInfo.h"
#include "oofnd/FileSystem.hpp"
#include "oofnd/String.hpp"

//void png_error(png_structp, png_const_charp) NO_RETURN_FUNC;


namespace {

void PNGError(png_structp png, png_const_charp message);
void PNGWarning(png_structp png, png_const_charp message);
void PNGRead(png_structp png, png_bytep bytes, png_size_t size);

}	// namespace


void OOPNGTextureLoader::loadTexture()
{
	// Get data from file
	fileData = OODataFromOXZFile(_path);
	if (!fileData.has_value())  return;
	length = fileData->length();
	
	doLoadTexture();
	
	fileData.reset();
}


OOPNGTextureLoader::~OOPNGTextureLoader()
{
	fileData.reset();
	if (png != NULL)
	{
		png_destroy_read_struct(&png, &pngInfo, &pngEndInfo);
	}
}


void OOPNGTextureLoader::doLoadTexture()
{
	png_bytepp					rows = NULL;
	png_uint_32					pngWidth,
								pngHeight;
	int							depth,
								colorType;
	uint32_t					i;
	
	// Set up PNG decoding
	png = png_create_read_struct(PNG_LIBPNG_VER_STRING, this, PNGError, PNGWarning);
	if (png != NULL)  pngInfo = png_create_info_struct(png);
	if (pngInfo != NULL)  pngEndInfo = png_create_info_struct(png);
	if (pngEndInfo == NULL)
	{
		OO_LOG("texture.load.png.setup.failed", "***** Error preparing to read {}.", _path);
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
	
	png_set_read_fn(png, this, PNGRead);
	
	png_read_info(png, pngInfo);
	// Read header, get format info and check that it meets our expectations.
	if (EXPECT_NOT(!png_get_IHDR(png, pngInfo, &pngWidth, &pngHeight, &depth, &colorType, NULL, NULL, NULL)))
	{
		OO_LOG("texture.load.png.failed", "Failed to get metadata from PNG {}", _path);
		goto FAIL;
	}
	png_set_strip_16(png);			// 16 bits per channel -> 8 bpc
	if (depth < 8 || colorType == PNG_COLOR_TYPE_PALETTE)
	{
		png_set_expand(png);		// Paletted -> RGB, greyscale -> 8 bpc
	}
	
	if (colorType == PNG_COLOR_TYPE_GRAY)
	{
		_format = (OOTextureDataFormat)kOOTextureDataGrayscale;
	}
	else if (colorType == PNG_COLOR_TYPE_GRAY_ALPHA)
	{
		_format = (OOTextureDataFormat)kOOTextureDataGrayscaleAlpha;
	}
	else
	{
		_format = (OOTextureDataFormat)kOOTextureDataRGBA;
		
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
	rows = (png_bytepp)malloc(sizeof *rows * _height);
	_data = malloc(_rowBytes * _height);
	if (EXPECT_NOT(rows == NULL || _data == NULL))
	{
		if (rows != NULL)
		{
			free(static_cast<void *>(rows));
			rows = NULL;
		}
		if (_data != NULL)
		{
			free(_data);
			_data = NULL;
		}
		OO_LOG(cxx_kOOLogAllocationFailure, "Failed to allocate space ({} bytes) for texture {}", _rowBytes * _height, _path);
		goto FAIL;
	}
	
	for (i = 0; i != _height; ++i)
	{
		rows[i] = ((png_bytep)_data) + i * _rowBytes;
	}
	png_read_image(png, rows);
	png_read_end(png, pngEndInfo);
	
FAIL:
	free(static_cast<void *>(rows));
	png_destroy_read_struct(&png, &pngInfo, &pngEndInfo);
}


void OOPNGTextureLoader::readBytes(png_bytep bytes, png_size_t count)
{
	// Check that we're within the file's bounds
	if (EXPECT_NOT(length - offset < count))
	{
		// (static: png_error() longjmps out of this frame, so nothing here may need destroying)
		static thread_local std::string message;
		message = oo::str::format("attempt to read beyond end of file (%s), file may be truncated.", _path.c_str());
		png_error(png, message.c_str());	// Will not return
	}
	
	assert(bytes != NULL);
	
	// Copy bytes
	memcpy(bytes, (const char *)fileData->bytes() + offset, count);
	offset += count;
}


/*	Minor detail: libpng 1.4.0 removed trailing .s from error and warning
	messages. It's also binary-incompatible with 1.2 and earlier, so it's
	reasonable to make this test at build time.
*/
#if PNG_LIBPNG_VER >= 10400
#define MSG_TERMINATOR "."
#else
#define MSG_TERMINATOR ""
#endif


namespace {

// The path in a message, as [loader cxx_path] printed it: "(null)" before libpng has the loader as
// its I/O pointer (errors while it is set up).
std::string LoaderPath(OOPNGTextureLoader *loader)
{
	return loader != nullptr ? loader->path().value_or("(null)") : std::string("(null)");
}


void PNGError(png_structp png, png_const_charp message)
{
	OOPNGTextureLoader *loader = static_cast<OOPNGTextureLoader *>(png_get_io_ptr(png));
	OO_LOG("texture.load.png.error", "***** A PNG loading error occurred for {}: {}" MSG_TERMINATOR, LoaderPath(loader), message);
	
#if PNG_LIBPNG_VER >= 10500
	png_longjmp(png, 1);
#else
	longjmp(png_jmpbuf(png), 1);
#endif
}


void PNGWarning(png_structp png, png_const_charp message)
{
	OOPNGTextureLoader *loader = static_cast<OOPNGTextureLoader *>(png_get_io_ptr(png));
	OO_LOG("texture.load.png.warning", "----- A PNG loading warning occurred for {}: {}" MSG_TERMINATOR, LoaderPath(loader), message);
}


void PNGRead(png_structp png, png_bytep bytes, png_size_t size)
{
	OOPNGTextureLoader *loader = static_cast<OOPNGTextureLoader *>(png_get_io_ptr(png));
	if (loader != nullptr)  loader->readBytes(bytes, size);	// a nil loader read nothing
}

}	// namespace
