/*	GrayMap.h
	
	Simple library for dealing with 8-bit greyscale images.
	
	This file is hereby placed in the public domain.
*/

#import <stdint.h>
#import <stdio.h>
#import <stdbool.h>


typedef struct
{
	uint8_t				*pixels;
	uint32_t			width;
	uint32_t			height;
	uint32_t			rowBytes;
} GrayMap;


GrayMap *NewGrayMap(uint32_t width, uint32_t height, uint32_t rowBytes);
void DisposeGrayMap(GrayMap *grayMap);

GrayMap *ReadGrayMap(const char *path);
GrayMap *ReadGrayMapFile(FILE *file, const char *name);

bool WriteGrayMap(const char *path, GrayMap *grayMap);
bool WriteGrayMapFile(FILE *file, const char *name, GrayMap *grayMap);

uint8_t GrayMapGet(GrayMap *grayMap, int32_t x, int32_t y);	// Out-of-bounds values return 0.
void GrayMapSet(GrayMap *grayMap, int32_t x, int32_t y, uint8_t value);
