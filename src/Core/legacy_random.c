/*

legacy_random.c


Oolite
Copyright (C) 2004-2008 Giles C Williams and contributors

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
#include <stdint.h>
#include <stdbool.h>
#include <assert.h>
#include "legacy_random.h"


const Random_Seed	kNilRandomSeed = {0};


static RNG_Seed		rnd_seed;


// TODO: Why is this based on a static? Should change to OOMungeCheckSum(&checkSum, value);
static int32_t checksum;
void clear_checksum()
{
	checksum = 0;
}


int16_t munge_checksum(long long value_)
{
	uint32_t value = (uint32_t)value_;
	int32_t mult1 = (value & 15) + 8;
	checksum += value;
	checksum *= mult1;
	checksum += mult1;
	checksum &= 0xffff;
	return checksum;
}


// cunning price rounding routine:
//
double cunningFee(double value, double precision)
{
	double fee = value;
	double superfee = 100000.0;
	double max = 1 + precision;
	double min = 1 - precision;
	unsigned long long rounded_fee = superfee * floor(0.5 + fee / superfee);
	if (rounded_fee == 0)  rounded_fee = 1;
	double ratio = fee / (double)rounded_fee;
	
	while ((ratio < min || ratio > max) && superfee > 1)
	{
		rounded_fee = superfee * floor(0.5 + fee / superfee);
		if (rounded_fee == 0)  rounded_fee = 1;
		ratio = fee / (double)rounded_fee;
		superfee /= 10.0;
	}
	
	if (ratio > min && ratio < max)
		fee = rounded_fee;
	
	return fee;
}


// an implementation of RANROT
// pseudo random number generator
//
static RANROTSeed		sRANROT;


unsigned Ranrot(void)
{
	sRANROT.high = (sRANROT.high << 16) + (sRANROT.high >> 16);
	sRANROT.high += sRANROT.low;
	sRANROT.low += sRANROT.high;
	return sRANROT.high & 0x7FFFFFFF;
}


unsigned RanrotWithSeed(RANROTSeed *ioSeed)
{
	assert(ioSeed != NULL);
	
	ioSeed->high = (ioSeed->high << 16) + (ioSeed->high >> 16);
	ioSeed->high += ioSeed->low;
	ioSeed->low += ioSeed->high;
	return ioSeed->high & 0x7FFFFFFF;
}


RANROTSeed MakeRanrotSeed(uint32_t seed)
{
	RANROTSeed result =
	{
		.low = seed,
		.high = ~seed
	};
	
	// Mix it up a bit.
	RanrotWithSeed(&result);
	RanrotWithSeed(&result);
	RanrotWithSeed(&result);

	return result;
}


RANROTSeed RanrotSeedFromRNGSeed(RNG_Seed seed)
{
	return MakeRanrotSeed(seed.a * 0x1000000 + seed.b * 0x10000 + seed.c * 0x100 + seed.d);
}


RANROTSeed RanrotSeedFromRandomSeed(Random_Seed seed)
{
	// Same pattern as seed_for_planet_description().
	RNG_Seed s =
	{
		.a = seed.c,
		.b = seed.d,
		.c = seed.e,
		.d = seed.f
	};
	return RanrotSeedFromRNGSeed(s);
}


void ranrot_srand(uint32_t seed)
{
	sRANROT = MakeRanrotSeed(seed);
}


float randf (void)
{
	return (Ranrot() & 0xffff) * (1.0f / 65536.0f);
}


float randfWithSeed(RANROTSeed *ioSeed)
{
	return (RanrotWithSeed(ioSeed) & 0xffff) * (1.0f / 65536.0f);
}


float bellf (int n)
{
	int i = n;
	float total = 0;
	
	if (EXPECT_NOT(i <= 0))
	{
		printf("***** ERROR - attempt to generate bellf(%d)\n", n);
		return 0.0f; // catch possible div-by-zero problem
	}
	
	while (i-- > 0)
		total += (Ranrot() & 1023);
	return total / (1024.0f * n);
}


RANROTSeed RANROTGetFullSeed(void)
{
	return sRANROT;
}


void RANROTSetFullSeed(RANROTSeed seed)
{
	sRANROT = seed;
}


void seed_RNG_only_for_planet_description (Random_Seed s_seed)
{
	rnd_seed.a = s_seed.c;
	rnd_seed.b = s_seed.d;
	rnd_seed.c = s_seed.e;
	rnd_seed.d = s_seed.f;
}


void seed_for_planet_description (Random_Seed s_seed)
{
	seed_RNG_only_for_planet_description(s_seed);
	sRANROT = RanrotSeedFromRNGSeed(rnd_seed);
}


RNG_Seed currentRandomSeed (void)
{
	return rnd_seed;
}


void setRandomSeed (RNG_Seed a_seed)
{
	rnd_seed = a_seed;
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


static bool sReallyRandomInited = false;
static RANROTSeed sReallyRandomSeed;


uint32_t OOReallyRandom(void)
{
	assert(sReallyRandomInited);
	return RanrotWithSeed(&sReallyRandomSeed);
}


void OOInitReallyRandom(uint64_t seed)
{
	assert(!sReallyRandomInited);
	seed ^= 0xA471D52AEF3B6322ULL;
	sReallyRandomSeed.high = (seed >> 32) & 0xFFFFFFFF;
	sReallyRandomSeed.low = seed  & 0xFFFFFFFF;
	sReallyRandomInited = true;
	OOReallyRandom();
}


void OOSetReallyRandomRANROTSeed(void)
{
	assert(sReallyRandomInited);
	sRANROT = sReallyRandomSeed;
	OOReallyRandom();	// Don't go reusing it.
}


void OOSetReallyRandomRndSeed(void)
{
	uint32_t val = OOReallyRandom();
	rnd_seed.a = (val >> 24) & 0xFF;
	rnd_seed.b = (val >> 16) & 0xFF;
	rnd_seed.c = (val >> 8) & 0xFF;
	rnd_seed.d = val & 0xFF;
}


void OOSetReallyRandomRANROTAndRndSeeds(void)
{
	OOSetReallyRandomRANROTSeed();
	OOSetReallyRandomRndSeed();
}


OORandomState OOSaveRandomState(void)
{
	return (OORandomState)
	{
		.ranrot = sRANROT,
		.rnd = rnd_seed
	};
}


void OORestoreRandomState(OORandomState state)
{
	sRANROT = state.ranrot;
	rnd_seed = state.rnd;
}


void make_pseudo_random_seed (Random_Seed *seed_ptr)
{
	seed_ptr->a = gen_rnd_number();
	seed_ptr->b = gen_rnd_number();
	seed_ptr->c = gen_rnd_number();
	seed_ptr->d = gen_rnd_number();
	seed_ptr->e = gen_rnd_number();
	seed_ptr->f = gen_rnd_number();
}


void rotate_seed (Random_Seed *seed_ptr)
{
	uint_fast16_t x;
	uint_fast16_t y;
	
	/*	Note: this is equivalent to adding three (little-endian) 16-bit values
		together, rotating the three numbers and replacing one of them with
		the sum. The byte-oriented approach is presumably because it was
		reverse-engineered from eight-bit machine code. Switching to a plain
		sixteen-bit representation is more trouble than it's worth since so
		much code uses byte values from the seed struct directly.
	*/
	x = seed_ptr->a + seed_ptr->c + seed_ptr->e;
	y = seed_ptr->b + seed_ptr->d + seed_ptr->f;
	
	seed_ptr->a = seed_ptr->c;
	seed_ptr->b = seed_ptr->d;
	
	seed_ptr->c = seed_ptr->e;
	seed_ptr->d = seed_ptr->f;
	
	seed_ptr->e = x;
	seed_ptr->f = y + (x >> 8);
}
