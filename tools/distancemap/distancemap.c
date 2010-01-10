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


static void PerformDistanceMapping(GrayMap *source, GrayMap *dmap, GrayMap *amap);
static void DistanceMapOnePixel(GrayMap *source, GrayMap *dmap, GrayMap *amap, uint32_t x, uint32_t y);


static bool wrap = false;


static inline uint32_t RoundSize(uint32_t size)
{
	return (size + kDownscale - 1) / kDownscale;
}


int main (int argc, char * argv[])
{
	GrayMap						*source = NULL;
	GrayMap						*dmap = NULL;
	GrayMap						*amap = NULL;
	bool						printUsage = false;
	bool						angleMap = false;
	
	// Get options
	for (;;)
	{
		int option = getopt(argc, argv, "wa");
		if (option == -1)  break;
		
		switch (option)
		{
			case 'w':
				wrap = true;
				break;
			
			case 'a':
				angleMap = true;
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
	if (angleMap)  amap = NewGrayMap(RoundSize(source->width), RoundSize(source->height), 0);
	if (dmap == NULL || (angleMap && amap == NULL))
	{
		fprintf(stderr, "Could not allocate memory for output image.\n");
		return EXIT_FAILURE;
	}
	
	PerformDistanceMapping(source, dmap, amap);
	
	WriteGrayMap("distance_map.png", dmap);
	if (angleMap)  WriteGrayMap("angle_map.png", amap);
	
    return 0;
}

static void PerformDistanceMapping(GrayMap *source, GrayMap *dmap, GrayMap *amap)
{
	uint32_t				width, height, x, y;
	
	assert(source && dmap);
	
	width = dmap->width;
	height = dmap->height;
	
	for (y = 0; y != height; ++y)
	{
		for (x = 0; x != width; ++x)
		{
			DistanceMapOnePixel(source, dmap, amap, x, y);
		}
		
		putchar('.');
		fflush(stdout);
	}
}


static bool ReadPx(GrayMap *source, uint32_t x, uint32_t y, int16_t dx, int16_t dy);


static inline int32_t Max(int32_t a, int32_t b)
{
	return (a > b) ? a : b;
}


static inline int32_t Min(int32_t a, int32_t b)
{
	return (a < b) ? a : b;
}


static inline int32_t Abs(int32_t a)
{
	return (a >= 0) ? a : -a;
}


static void DistanceMapOnePixel(GrayMap *source, GrayMap *dmap, GrayMap *amap, uint32_t x, uint32_t y)
{
	int32_t					dx, dy;
	bool					target;
	uint32_t				distanceSq, bestDistanceSq = UINT32_MAX;
	uint32_t				bestDistance;
	float					bestAngle;
	uint32_t				currDistance, maxDistance = Max(source->width, source->height);
	int8_t					ddx = 1, ddy = 0, ddt;
	uint8_t					countdown = 3;
	uint32_t				i, length = 2;
	int32_t					bestDx = 1, bestDy = 1;
	
	dx = 0;
	dy = -1;
	if (amap == NULL)  maxDistance = Min(maxDistance, 128);
	target = !ReadPx(source, x, y, 0, 0);
	
	for (;;)
	{
		// Spiral outwards.
		do
		{
			for (i = 0; i < length; i++)
			{
				if (ReadPx(source, x, y, dx, dy) == target)
				{
					distanceSq = dx * dx + dy * dy;
					if (distanceSq < bestDistanceSq)
					{
						bestDistanceSq = distanceSq;
						bestDx = dx;
						bestDy = dy;
					}
				}
				
				dx += ddx;
				dy += ddy;
			}
			// Turn a corner.
			ddt = ddx;
			ddx = -ddy;
			ddy = ddt;
		}
		while (--countdown);
		
		currDistance = Max(Abs(dx), Abs(dy));
		if ((currDistance * currDistance) > bestDistanceSq || currDistance > maxDistance)  break;
		
		countdown = 2;
		length++;
	}
	
	bestDistance = sqrt(bestDistanceSq);
	if (target)
	{
		if (bestDistance > 128)  bestDistance = 0;
		else  bestDistance = 128 - bestDistance;
		bestDx = -bestDx;
		bestDy = -bestDy;
	}
	else
	{
		bestDistance = 127 + bestDistance;
		if (bestDistance > 255)  bestDistance = 255;
	}
	
	GrayMapSet(dmap, x, y, bestDistance);
	
	if (amap != NULL)
	{
		bestAngle = atan2(bestDx, bestDy);
		bestAngle = (bestAngle + M_PI) * 127.5 / M_PI;	// Convert from +/-pi to 0..255
		GrayMapSet(amap, x, y, bestAngle);
	}
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
