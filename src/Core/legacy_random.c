/*

legacy_random.c
Created by Giles Williams on 2004-04-03.

Class handling interface elements, primarily text, that are not part of the 3D
game world, together with GuiDisplayGen.

For Oolite
Copyright (C) 2004  Giles C Williams

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

#include <stdio.h>
#include <math.h>
#include "legacy_random.h"

static struct random_seed   rnd_seed;

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

// cunning price rounding routine:
//
float cunningFee(float value)
{
	float fee = value;
	float superfee = 100000;
	int rounded_fee = superfee * floor(0.5 + fee / superfee);
	if (!rounded_fee)
		rounded_fee = 1;
	float ratio = fee / (float)rounded_fee;
	while (((ratio < 0.95)||(ratio > 1.05))&&(superfee > 1))
	{
		superfee /= 10;
		rounded_fee = superfee * floor(0.5 + fee / superfee);
		if (!rounded_fee)
			rounded_fee = 1;
		ratio = fee / (float)rounded_fee;
	}
	if ((ratio > 0.95)&&(ratio < 1.05))
		fee = rounded_fee;
	return fee;
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


inline float randf (void)
{
//	return 0.0009765625 * (ranrot_rand() & 1023);
	return (ranrot_rand() & 0x00ffff) / (float)0x010000;
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

void make_pseudo_random_seed (struct rand_seed_6uc *seed_ptr)
{
	seed_ptr->a = gen_rnd_number();
	seed_ptr->b = gen_rnd_number();
	seed_ptr->c = gen_rnd_number();
	seed_ptr->d = gen_rnd_number();
	seed_ptr->e = gen_rnd_number();
	seed_ptr->f = gen_rnd_number();
}

Random_Seed nil_seed()
{
	Random_Seed result = { (unsigned char)0,  (unsigned char)0,  (unsigned char)0,  (unsigned char)0,  (unsigned char)0,  (unsigned char)0};
	return result;
}

int is_nil_seed(Random_Seed a_seed)
{
	if (a_seed.a | a_seed.b | a_seed.c | a_seed.d | a_seed.e | a_seed.f)
		return 0;
	else
		return -1;
}

void rotate_seed (struct rand_seed_6uc *seed_ptr)
{
    unsigned int x;
	unsigned int y;

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

