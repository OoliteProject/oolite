/*

legacy_random.h

Pseudo-random number generator designed to produce identical results to that
used in BBC Elite (for dynamic world generation), and related functions.

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

#ifndef LEGACY_RANDOM_H
#define LEGACY_RANDOM_H

#import "OOFunctionAttributes.h"


struct rand_seed_6uc
{
	unsigned char a;	/* 6c */
	unsigned char b;	/* 6d */
	unsigned char c;	/* 6e */
	unsigned char d;	/* 6f */
	unsigned char e;	/* 70 */
	unsigned char f;	/* 71 */
};

typedef struct rand_seed_6uc Random_Seed;

struct random_seed
{
	int a;
	int b;
	int c;
	int d;
};

typedef struct random_seed RNG_Seed;


extern const Random_Seed	kNilRandomSeed;


// checksum stuff
void clear_checksum();
int munge_checksum(int value);

// cunning price rounding routine:
//
float cunningFee(float value) CONST_FUNC;

// an implementation of RANROT
// pseudo random number generator
//
inline void ranrot_srand(unsigned int seed);
inline int ranrot_rand();

OOINLINE double distanceBetweenPlanetPositions(int x1, int y1, int x2, int y2) INLINE_CONST_FUNC;
OOINLINE double accurateDistanceBetweenPlanetPositions(int x1, int y1, int x2, int y2) INLINE_CONST_FUNC;

void seed_for_planet_description(Random_Seed s_seed);
void seed_RNG_only_for_planet_description(Random_Seed s_seed);
RNG_Seed currentRandomSeed(void);
void setRandomSeed(RNG_Seed a_seed);

inline float randf (void);
inline float bellf (int n);

int gen_rnd_number (void);

void make_pseudo_random_seed (struct rand_seed_6uc *seed_ptr);

Random_Seed nil_seed() DEPRECATED_FUNC;
OOINLINE int is_nil_seed(Random_Seed a_seed) INLINE_CONST_FUNC;

void rotate_seed (struct rand_seed_6uc *seed_ptr);
OOINLINE int rotate_byte_left (int x) INLINE_CONST_FUNC;

OOINLINE int equal_seeds(Random_Seed seed1, Random_Seed seed2) INLINE_CONST_FUNC;



/*** Only inline definitions beyond this point ***/

OOINLINE int equal_seeds(Random_Seed seed1, Random_Seed seed2)
{
	return ((seed1.a == seed2.a)&&(seed1.b == seed2.b)&&(seed1.c == seed2.c)&&(seed1.d == seed2.d)&&(seed1.e == seed2.e)&&(seed1.f == seed2.f));
}


OOINLINE int is_nil_seed(Random_Seed a_seed)
{
	return equal_seeds(a_seed, kNilRandomSeed);
}


OOINLINE int rotate_byte_left(int x)
{
	return ((x << 1) | (x >> 7)) & 255;
}

 
// a method used to determine interplanetary distances,
// if accurate, it has to scale distance down by a factor of 7.15:7.0
// to allow routes navigable in the original!
OOINLINE double distanceBetweenPlanetPositions ( int x1, int y1, int x2, int y2)
{
	int dx = x1 - x2;
	int dy = (y1 - y2)/2;
	int dist = sqrtf(dx*dx + dy*dy); // here's where the rounding errors come in!
	return 0.4 * dist;
}


OOINLINE double accurateDistanceBetweenPlanetPositions ( int x1, int y1, int x2, int y2)
{
	double dx = x1 - x2;
	double dy = (y1 - y2) / 2.0;
	double dist = sqrt(dx*dx + dy*dy); // here's where the rounding errors come in!
	return 0.4 * dist;
}

#endif
