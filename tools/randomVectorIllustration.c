// Code to generate http://wiki.alioth.net/index.php/Image:Randomvectordistribution.png

#import <math.h>
#import <stdio.h>


static inline float randf(void)
{
	return ((float)random()) / ((float)0x7FFFFFFF);
}


static inline float randcoord(void)
{
	return (randf() * 2.0f) - 1.0f;
}


typedef struct
{
	float x, y;
} Vector;


static Vector randv(void)
{
	Vector r = { randcoord(), randcoord() };
	return r;
}


static float magnitude2(Vector v)
{
	return v.x * v.x + v.y * v.y;
}


static Vector scalev(Vector v, float s)
{
	v.x *= s;
	v.y *= s;
	return v;
}


static Vector normal(Vector v)
{
	float m = magnitude2(v);
	return scalev(v, 1.0f / sqrtf(m));
}


static Vector uniformrandomv(void)
{
	Vector v;
	float m;
	
	do
	{
		v = randv();
		m = magnitude2(v);
	}
	while (m > 1.0f);
	
	return v;
}


static Vector radialrandomv(void)
{
	Vector v;
	float m;
	
	do
	{
		v = randv();
		m = magnitude2(v);
	}
	while (m > 1.0f || m == 0.0f);
	
	return scalev(normal(v), randf());
}


#define SIZE 200


static inline unsigned scalecoord(float c)
{
	return (c + 1.0) * ((float)SIZE) * 0.5;
}


int main (int argc, const char * argv[])
{
    unsigned char img[SIZE * SIZE] = {0};
	
	srandomdev();
	
	unsigned i;
	for (i = 0; i < 2500; ++i)
	{
		Vector v = uniformrandomv();
		
		unsigned x = scalecoord(v.x);
		unsigned y = scalecoord(v.y);
		
		img[y * SIZE + x] = 0xFF;
	}
	
	FILE *f = fopen("/dump.raw", "w");
	fwrite(img, SIZE, SIZE, f);
	fclose(f);
	
    return 0;
}
