/*
 *  legacy_random.c
 *
 *  Oolite
 *
 *  Created by Giles Williams on Sat Apr 03 2004.
 *  Copyright (c) 2004 for aegidian.org. All rights reserved.
 *

Copyright (c) 2004, Giles C Williams
All rights reserved.

This work is licensed under the Creative Commons Attribution-NonCommercial-ShareAlike License.
To view a copy of this license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/
or send a letter to Creative Commons, 559 Nathan Abbott Way, Stanford, California 94305, USA.

You are free:

•	to copy, distribute, display, and perform the work
•	to make derivative works

Under the following conditions:

•	Attribution. You must give the original author credit.

•	Noncommercial. You may not use this work for commercial purposes.

•	Share Alike. If you alter, transform, or build upon this work,
you may distribute the resulting work only under a license identical to this one.

For any reuse or distribution, you must make clear to others the license terms of this work.

Any of these conditions can be waived if you get permission from the copyright holder.

Your fair use and other rights are in no way affected by the above.

*/

#include "legacy_random.h"

static struct random_seed   rnd_seed;

static int					carry_flag;

static int checksum;
void clear_checksum()
{
	checksum = 0;
}

int munge_checksum(int value)
{
	int mult1 = (value & 15) + 8;
	checksum += value;
	checksum *= mult1;
	checksum += mult1;
	checksum &= 0xffff;
	return checksum;
}

// an implementation of RANROT
// pseudo random number generator
//
unsigned int m_high;
unsigned int m_low;
inline void ranrot_srand(unsigned int seed)
{

//	printf("***** DEBUG Random seed %d\n", seed);
//	
	m_low = seed;
	m_high = ~seed;
	ranrot_rand();	ranrot_rand();	ranrot_rand();  // mix it up a bit
}
inline int ranrot_rand()
{
	m_high = (m_high<<16) + (m_high>>16);
	m_high += m_low;
	m_low += m_high;
	return m_high & 0x7FFFFFFF;
}
 
// a method used to determine interplanetary distances,
// if accurate, it has to scale distance down by a factor of 7.15:7.0
// to allow routes navigable in the original!
double distanceBetweenPlanetPositions ( int x1, int y1, int x2, int y2)
{
	int dx = x1 - x2;
	int dy = (y1 - y2)/2;
	int dist = sqrt(dx*dx + dy*dy); // here's where the rounding errors come in!
	return 0.4*dist;
}

double accurateDistanceBetweenPlanetPositions ( int x1, int y1, int x2, int y2)
{
	double dx = x1 - x2;
	double dy = (y1 - y2)/2;
	double dist = sqrt(dx*dx + dy*dy); // here's where the rounding errors come in!
	return 0.4*dist;
}

void seed_for_planet_description (Random_Seed s_seed)
{
	rnd_seed.a = s_seed.c;
	rnd_seed.b = s_seed.d;
	rnd_seed.c = s_seed.e;
	rnd_seed.d = s_seed.f;
		
	ranrot_srand(rnd_seed.a * 0x1000000 + rnd_seed.b * 0x10000 + rnd_seed.c * 0x100 + rnd_seed.d);
}

void seed_RNG_only_for_planet_description (Random_Seed s_seed)
{
	rnd_seed.a = s_seed.c;
	rnd_seed.b = s_seed.d;
	rnd_seed.c = s_seed.e;
	rnd_seed.d = s_seed.f;
}

RNG_Seed currentRandomSeed (void)
{
	return rnd_seed;
}

void setRandomSeed (RNG_Seed a_seed)
{
	rnd_seed = a_seed;
}


int get_carry_flag (void)
{
	return carry_flag;
}

void clear_carry_flag (void)
{
	carry_flag = 0;
}

inline float randf (void)
{
	return 0.0009765625 * (ranrot_rand() & 1023);
}

inline float bellf (int n)
{
	int i = n;
	float total = 0;
	
	if (i <= 0)
	{
		printf("***** ERROR - attempt to generate bellf(%d)\n", n);
		return 0.0;	// catch possible div-by-zero problem
	}
	
	while (i-- > 0)
		total += (ranrot_rand() & 1023);
	return 0.0009765625 * total / n;
}

int gen_rnd_number (void)
{
	int a,x;

	x = (rnd_seed.a * 2) & 0xFF;
	a = x + rnd_seed.c;
	if (rnd_seed.a > 127)
		a++;
	rnd_seed.a = a & 0xFF;
	rnd_seed.c = x;

	a = a / 256;	/* a = any carry left from above */
	x = rnd_seed.b;
	a = (a + x + rnd_seed.d) & 0xFF;
	rnd_seed.b = a;
	rnd_seed.d = x;
	return a;
}


void rotate_seed (struct rand_seed_6uc *seed_ptr)
{
    unsigned int x;
	unsigned int y;
	extern int carry_flag;

	x = seed_ptr->a + seed_ptr->c;
    y = seed_ptr->b + seed_ptr->d;


	if (x > 0xFF)
	    y++;

	x &= 0xFF;
	y &= 0xFF;

	seed_ptr->a = seed_ptr->c;
	seed_ptr->b = seed_ptr->d;
	seed_ptr->c = seed_ptr->e;
	seed_ptr->d = seed_ptr->f;

    x += seed_ptr->c;
	y += seed_ptr->d;


	if (x > 0xFF)
		y++;

	if (y > 0xFF)
		carry_flag = 1;
	else
		carry_flag = 0;

    x &= 0xFF;
	y &= 0xFF;

	seed_ptr->e = x;
	seed_ptr->f = y;
}

int rotate_byte_left (int x)
{
	return ((x << 1) | (x >> 7)) & 255;
}


int equal_seeds (Random_Seed seed1, Random_Seed seed2)
{
	return ((seed1.a == seed2.a)&&(seed1.b == seed2.b)&&(seed1.c == seed2.c)&&(seed1.d == seed2.d)&&(seed1.e == seed2.e)&&(seed1.f == seed2.f));
}

