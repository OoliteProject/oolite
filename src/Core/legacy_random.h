/*

legacy_random.h

Pseudo-random number generator designed to produce identical results to that
used in BBC Elite (for dynamic world generation), and related functions.


Oolite
Copyright (C) 2004-2013 Giles C Williams and contributors

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

#include "OOFunctionAttributes.h"
#include <math.h>
#include <stdint.h>


typedef struct Random_Seed
{
	uint8_t				a,	/* 6c */
						b,	/* 6d */
						c,	/* 6e */
						d,	/* 6f */
						e,	/* 70 */
						f;	/* 71 */
} Random_Seed;


typedef struct RNG_Seed
{
	int32_t				a,
						b,
						c,
						d;
} RNG_Seed;


typedef struct RANROTSeed
{
	uint32_t			high,
						low;
} RANROTSeed;


extern const Random_Seed	kNilRandomSeed;


// checksum stuff
void clear_checksum();
int16_t munge_checksum(long long value);

// cunning price rounding routine:
double cunningFee(double value, double precision); // precision is the fraction below which numbers become insignificant.

// an implementation of RANROT
// pseudo random number generator
void ranrot_srand(uint32_t seed);
unsigned Ranrot(void);
#define ranrot_rand() ((int)Ranrot())	// Some uses perform arithmetic that does weird things if result is unsigned -- DustEntity.m, for instance.
float randf(void);
float bellf(int n);

RANROTSeed RANROTGetFullSeed(void);
void RANROTSetFullSeed(RANROTSeed seed);

RANROTSeed MakeRanrotSeed(uint32_t seed);
RANROTSeed RanrotSeedFromRNGSeed(RNG_Seed seed);
RANROTSeed RanrotSeedFromRandomSeed(Random_Seed seed);

unsigned RanrotWithSeed(RANROTSeed *ioSeed);
float randfWithSeed(RANROTSeed *ioSeed);


OOINLINE double distanceBetweenPlanetPositions(int x1, int y1, int x2, int y2) INLINE_CONST_FUNC;
OOINLINE double accurateDistanceBetweenPlanetPositions(int x1, int y1, int x2, int y2) INLINE_CONST_FUNC;

void seed_for_planet_description(Random_Seed s_seed);
void seed_RNG_only_for_planet_description(Random_Seed s_seed);
RNG_Seed currentRandomSeed(void);
void setRandomSeed(RNG_Seed a_seed);

// Range: 0..255
int gen_rnd_number (void);

void make_pseudo_random_seed (Random_Seed *seed_ptr);

OOINLINE int is_nil_seed(Random_Seed a_seed) INLINE_CONST_FUNC;

void rotate_seed (Random_Seed *seed_ptr);
OOINLINE int rotate_byte_left (int x) INLINE_CONST_FUNC;

OOINLINE int equal_seeds(Random_Seed seed1, Random_Seed seed2) INLINE_CONST_FUNC;


/*
	The "really really random" PRNG. This is a separate RANROT seed that is
	seeded once at startup and never reset under any circumstances. It can
	also be used to seed get_rnd_number and the main RANROT seed. If doing this,
	save and restore the seeds using the functions above ore OOSaveRandomState()
	and OORestoreRandomState().
	
	Since these use a global seed, they may only be used from the main thread.
*/

uint32_t OOReallyRandom(void);
void OOInitReallyRandom(uint64_t seed);

void OOSetReallyRandomRANROTSeed(void);
void OOSetReallyRandomRndSeed(void);
void OOSetReallyRandomRANROTAndRndSeeds(void);

/*
	OOSaveRandomState()/OORestoreRandomState(): save and restore both the main
	RANROT seed and the rnd seed in one shot.
*/
typedef struct
{
	RANROTSeed	ranrot;
	RNG_Seed	rnd;
} OORandomState;

OORandomState OOSaveRandomState(void);
void OORestoreRandomState(OORandomState state);



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
OOINLINE double distanceBetweenPlanetPositions(int x1, int y1, int x2, int y2)
{
	int dx = x1 - x2;
	int dy = (y1 - y2)/2;
	int dist = sqrt(dx*dx + dy*dy);	// N.b. Rounding error due to truncation is desired.
	return 0.4 * dist;
}


OOINLINE double accurateDistanceBetweenPlanetPositions(int x1, int y1, int x2, int y2)
{
	double dx = x1 - x2;
	double dy = (y1 - y2) / 2.0;
	double dist = hypot(dx, dy);
	return 0.4 * dist;
}


OOINLINE double travelTimeBetweenPlanetPositions(int x1, int y1, int x2, int y2)
{
	double distance = distanceBetweenPlanetPositions(x1, y1, x2, y2);
	return distance * distance;
}

#endif
