#import <stdlib.h>
#import <stdint.h>
#import <assert.h>
#import <math.h>
#import <unistd.h>
#import "GrayMap.h"


enum
{
	kDownscale					= 16,
	kHalfDownscale				= kDownscale / 2,
	kThreshold					= 128
};


static void PerformDistanceMapping(GrayMap *source, GrayMap *dmap);
static void DistanceMapOnePixel(GrayMap *source, GrayMap *dmap, uint32_t x, uint32_t y);


static bool wrap = false;


static inline uint32_t RoundSize(uint32_t size)
{
	return (size + kDownscale - 1) / kDownscale;
}


int main (int argc, char * argv[])
{
	GrayMap						*source = NULL;
	GrayMap						*dmap = NULL;
	BOOL						printUsage = false;
	
	// Get options
	for (;;)
	{
		int option = getopt(argc, argv, "w");
		if (option == -1)  break;
		
		switch (option)
		{
			case 'w':
				wrap = true;
				break;
			
			default:
				printUsage = true;
		}
	}
	
	if (argc <= optind) printUsage = true;
	
	if (printUsage)
	{
		fprintf(stderr, "Usage: %s [-w] <filename.png>\n", argv[0]);
		return EXIT_FAILURE;
	}
	
	source = ReadGrayMap(argv[optind]);
	if (source == NULL)  return EXIT_FAILURE;
	
	dmap = NewGrayMap(RoundSize(source->width), RoundSize(source->height), 0);
	if (dmap == NULL)
	{
		fprintf(stderr, "Could not allocate memory for output image.\n");
		return EXIT_FAILURE;
	}
	
	PerformDistanceMapping(source, dmap);
	
	WriteGrayMap("distance_map.png", dmap);
	
    return 0;
}

static void PerformDistanceMapping(GrayMap *source, GrayMap *dmap)
{
	uint32_t				width, height, x, y;
	
	assert(source && dmap);
	
	width = dmap->width;
	height = dmap->height;
	
	for (y = 0; y != height; ++y)
	{
		for (x = 0; x != width; ++x)
		{
			DistanceMapOnePixel(source, dmap, x, y);
		}
		
		putchar('.');
		fflush(stdout);
	}
}


static bool ReadPx(GrayMap *source, uint32_t x, uint32_t y, int16_t dx, int16_t dy);


static void DistanceMapOnePixel(GrayMap *source, GrayMap *dmap, uint32_t x, uint32_t y)
{
	int16_t					dx, dy;
	bool					target;
	uint8_t					count;
	uint32_t				distanceSq, bestDistanceSq = UINT32_MAX;
	uint32_t				bestDistance;
	
	/*	Count number of pixels at middle that are inside. If three or four are
		inside, we're deemed to be overall inside and search for outside
		pixels. Otherwise, we're deemed overall outside and search for inside
		pixels.
	*/
	
	count = 0;
	if (ReadPx(source, x, y, 0, 0))  count++;
	if (ReadPx(source, x, y, 0, 1))  count++;
	if (ReadPx(source, x, y, 1, 0))  count++;
	if (ReadPx(source, x, y, 1, 1))  count++;
	
	target = count < 3;
	
	for (dy = -128; dy != 128; dy++)
	{
		for (dx = -128; dx != 128; dx++)
		{
			if (ReadPx(source, x, y, dx, dy) == target)
			{
				distanceSq = dx * dx + dy * dy;
				if (distanceSq < bestDistanceSq)  bestDistanceSq = distanceSq;
			}
		}
	}
	
	bestDistance = sqrt(bestDistanceSq);
	if (target)
	{
		if (bestDistance > 128)  bestDistance = 0;
		else  bestDistance = 128 - bestDistance;
	}
	else
	{
		bestDistance = 127 + bestDistance;
		if (bestDistance > 255)  bestDistance = 255;
	}
	
	GrayMapSet(dmap, x, y, bestDistance);
}


static bool ReadPx(GrayMap *source, uint32_t x, uint32_t y, int16_t dx, int16_t dy)
{
	int32_t				ax = x * kDownscale + dx - kHalfDownscale;
	int32_t				ay = y * kDownscale + dy - kHalfDownscale;
	
	if (wrap)
	{
		ax = ax % source->width;
		if (ax < 0)  ax += source->width;
		ay = ay % source->height;
		if (ay < 0)  ay += source->height;
	}
	
	return GrayMapGet(source, ax, ay) >= kThreshold;
}
