/*	GrayMap.c
	
	Simple library for dealing with 8-bit greyscale images.
	
	This file is hereby placed in the public domain.
*/

#import <stdlib.h>
#import <assert.h>
#include "GrayMap.h"
#import "png.h"


static png_bytepp MakeGrayMapRowPointers(GrayMap *grayMap);	// Free with free()


GrayMap *ReadGrayMap(const char *path)
{
	FILE						*file = NULL;
	GrayMap						*result = NULL;
	
	file = fopen(path, "rb");
	if (file == NULL)
	{
		fprintf(stderr, "Could not open %s.\n", path);
		return NULL;
	}
	
	result = ReadGrayMapFile(file, path);
	fclose(file);
	
	return result;
}


GrayMap *NewGrayMap(uint32_t width, uint32_t height, uint32_t rowBytes)
{
	GrayMap						*result = NULL;
	
	if (rowBytes == 0)  rowBytes = width;
	else  assert(rowBytes >= width);
	
	result = malloc(sizeof *result);
	if (result != NULL)
	{
		result->pixels = malloc(rowBytes * height);
		if (result->pixels == NULL)
		{
			free(result);
			result = NULL;
		}
		else
		{
			result->width = width;
			result->height = height;
			result->rowBytes = rowBytes;
		}
	}
	
	return result;
}


void DisposeGrayMap(GrayMap *grayMap)
{
	if (grayMap != NULL)
	{
		free(grayMap->pixels);
		free(grayMap);
	}
}


static png_bytepp MakeGrayMapRowPointers(GrayMap *grayMap)
{
	if (grayMap == NULL)  return NULL;
	
	png_bytepp rows = malloc(sizeof (png_bytep) * grayMap->rowBytes);
	if (rows != NULL)
	{
		for (uint32_t i = 0; i != grayMap->height; ++i)
		{
			rows[i] = ((png_bytep)grayMap->pixels) + i * grayMap->rowBytes;
		}
	}
	
	return rows;
}


GrayMap *ReadGrayMapFile(FILE *file, const char *name)
{
	GrayMap						*result = NULL;
	struct png_struct_def		*png = NULL;
	struct png_info_struct		*pngInfo = NULL;
	struct png_info_struct		*pngEndInfo = NULL;
	png_bytepp					rows = NULL;
	png_uint_32					pngWidth,
	pngHeight;
	int							depth,
	colorType;
	
	if (file == NULL)  return NULL;
	
	// Set up PNG decoding.
	png = png_create_read_struct(PNG_LIBPNG_VER_STRING, NULL, NULL, NULL);
	if (png == NULL)
	{
		fprintf(stderr, "Error preparing to read %s.\n", name);
		return NULL;
	}
	
	pngInfo = png_create_info_struct(png);
	if (pngInfo == NULL)
	{
		fprintf(stderr, "Error preparing to read %s.\n", name);
		return NULL;
	}
	
	pngEndInfo = png_create_info_struct(png);
	if (pngInfo == NULL)
	{
		fprintf(stderr, "Error preparing to read %s.\n", name);
		return NULL;
	}
	
	if (setjmp(png_jmpbuf(png)))
	{
		// libpng will jump here on error.
		free(rows);
		return NULL;
	}
	
	png_init_io(png, file);
	png_read_info(png, pngInfo);
	
	if (!png_get_IHDR(png, pngInfo, &pngWidth, &pngHeight, &depth, &colorType, NULL, NULL, NULL))
	{
		fprintf(stderr, "Failed to get metadata from PNG %s", name);
		return NULL;
	}
	
	// Set to transform to 8-bit greyscale without alpha.
	if (colorType & PNG_COLOR_MASK_ALPHA)
	{
		png_set_strip_alpha(png);
	}
	
	if (colorType == PNG_COLOR_TYPE_GRAY ||
		colorType == PNG_COLOR_TYPE_GRAY_ALPHA)
	{
		png_set_strip_16(png);
		png_set_expand(png);
	}
	else if (colorType == PNG_COLOR_TYPE_PALETTE ||
			 colorType == PNG_COLOR_TYPE_RGB ||
			 colorType == PNG_COLOR_TYPE_RGB_ALPHA)
	{
		png_set_rgb_to_gray(png, 3, -1, -1);
	}
	else
	{
		fprintf(stderr, "Unknown colour type (0x%.X) in %s.\n", colorType, name);
		return NULL;
	}
	
	png_read_update_info(png, pngInfo);
	
	result = NewGrayMap(pngWidth, pngHeight, png_get_rowbytes(png, pngInfo));
	if (result == NULL)
	{
		fprintf(stderr, "Could not allocate memory for source image.\n");
		return NULL;
	}
	
	// Create array of row pointers.
	rows = MakeGrayMapRowPointers(result);
	if (rows == NULL)
	{
		fprintf(stderr, "Could not allocate memory for source image.\n");
		DisposeGrayMap(result);
		return NULL;
	}
	
	// Read.
	png_read_image(png, rows);
	png_read_end(png, pngEndInfo);
	
	free(rows);
	png_destroy_read_struct(&png, &pngInfo, &pngEndInfo);
	
	return result;
}


bool WriteGrayMap(const char *path, GrayMap *grayMap)
{
	FILE						*file = NULL;
	bool						result = NULL;
	
	file = fopen(path, "wb");
	if (file == NULL)
	{
		fprintf(stderr, "Could not open %s.\n", path);
		return false;
	}
	
	result = WriteGrayMapFile(file, path, grayMap);
	fclose(file);
	
	
	return result;
}


bool WriteGrayMapFile(FILE *file, const char *name, GrayMap *grayMap)
{
	struct png_struct_def		*png = NULL;
	struct png_info_struct		*pngInfo = NULL;
	png_bytepp					rows = NULL;
	
	if (grayMap == NULL || file == NULL)  return false;
	
	// Set up PNG encoding.
	png = png_create_write_struct(PNG_LIBPNG_VER_STRING, NULL, NULL, NULL);
	if (png == NULL)
	{
		fprintf(stderr, "Error preparing to write %s.\n", name);
		return false;
	}
	
	pngInfo = png_create_info_struct(png);
	if (pngInfo == NULL)
	{
		fprintf(stderr, "Error preparing to write %s.\n", name);
		return false;
	}
	
	if (setjmp(png_jmpbuf(png)))
	{
		// libpng will jump here on error.
		free(rows);
		return false;
	}
	
	// Create array of row pointers.
	rows = MakeGrayMapRowPointers(grayMap);
	if (rows == NULL)
	{
		fprintf(stderr, "Could not allocate memory to write image.\n");
		return NULL;
	}
	
	// Write.
	png_init_io(png, file);
	
	png_set_IHDR(png, pngInfo, grayMap->width, grayMap->height, 8, PNG_COLOR_TYPE_GRAY, PNG_INTERLACE_NONE, PNG_COMPRESSION_TYPE_DEFAULT, PNG_FILTER_TYPE_DEFAULT);
	png_write_info(png, pngInfo);
	
	png_write_image(png, rows);
	png_write_end(png, NULL);
	
	free(rows);
	return true;
}


uint8_t GrayMapGet(GrayMap *grayMap, int32_t x, int32_t y)
{
	// Out-of-range values or NULL grayMap result in 0.
	if (grayMap == NULL || x < 0 || y < 0 || grayMap->width <= x || grayMap->height <= y)  return 0;
	return grayMap->pixels[y * grayMap->rowBytes + x];
}


void GrayMapSet(GrayMap *grayMap, int32_t x, int32_t y, uint8_t value)
{
	// Out-if-range values or NULL grayMap are ignored.
	if (grayMap == NULL || x < 0 || y < 0 || grayMap->width <= x || grayMap->height <= y)  return;
	grayMap->pixels[y * grayMap->rowBytes + x] = value;
}
