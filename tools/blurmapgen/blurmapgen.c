#include <stdlib.h>
#include <stdio.h>
#include <assert.h>
#include <math.h>
#include <stdint.h>
#include <time.h>


#define SIZE			512	// Side dimension
#define RADIUS			150
#define NOISE_FACTOR	0.01


static inline off_t Coord(int x, int y)
{
	assert(x < SIZE && y < SIZE);
	return y * SIZE + x;
}


static inline float Distance(float x1, float y1, float x2, float y2)
{
	float dx = x2 - x1;
	float dy = y2 - y1;
	return sqrtf(dx * dx + dy * dy);
}


static inline float OOClamp_0_1_f(float value)
{
	return fmaxf(0.0f, fminf(value, 1.0f));
}


// Random in -1..1
static inline float Random(void)
{
	float rval = (float)rand() / (float)RAND_MAX;
	return rval * 2.0f - 1.0f;
}


int main (int argc, const char * argv[])
{
	uint8_t *buffer;
	srand(time(NULL));
	
	buffer = malloc(SIZE * SIZE);
	if (buffer == NULL)  return EXIT_FAILURE;
	
	int x, y;
	for (y = 0; y < SIZE; ++y)
	{
		for (x = 0; x < SIZE; ++x)
		{
			float r = 1.0 - Distance(x, y, SIZE / 2.0f - 0.5f, SIZE / 2.0f - 0.5f) / (float)RADIUS;
			r = OOClamp_0_1_f(r * 1.0f - NOISE_FACTOR / 2.0f);
			
			// x^2 (3-2x), same as GLSL smoothstep() interpolation.
			float v = r * r * (3.0f - 2.0f * r);
			
			// mix in some noise, scaled by intensity.
			float noise = Random() * NOISE_FACTOR;
			v *= 1.0 + noise;
			
			buffer[Coord(x, y)] = 255 * OOClamp_0_1_f(v);
		}
	}
	
	FILE *result = fopen("oolite-particle-blur.raw", "wb");
	if (result == NULL)  return EXIT_FAILURE;
	fwrite(buffer, SIZE, SIZE, result);
	fclose(result);
	
	return 0;
}
