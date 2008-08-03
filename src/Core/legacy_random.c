/*

legacy_random.c

Class handling interface elements, primarily text, that are not part of the 3D
game world, together with GuiDisplayGen.

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
#include "legacy_random.h"


const Random_Seed	kNilRandomSeed = {0};


static RNG_Seed		rnd_seed;


// TODO: Why is this based on a static? Should change to MungeCheckSum(&checkSum, value);
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
double cunningFee(double value)
{
	double fee = value;
	double superfee = 100000.0;
	unsigned long long rounded_fee = superfee * floor(0.5 + fee / superfee);
	if (rounded_fee == 0)  rounded_fee = 1;
	double ratio = fee / (double)rounded_fee;
	
	while ((ratio < 0.95 || ratio > 1.05) && superfee > 1)
	{
		rounded_fee = superfee * floor(0.5 + fee / superfee);
		if (rounded_fee == 0)  rounded_fee = 1;
		ratio = fee / (double)rounded_fee;
		superfee /= 10.0;
	}
	
	if (ratio > 0.95 && ratio < 1.05)
		fee = rounded_fee;
	
	return fee;
}


// an implementation of RANROT
// pseudo random number generator
//
static RANROTSeed		sRANROT;


void ranrot_srand(unsigned int seed)
{
	sRANROT.low = seed;
	sRANROT.high = ~seed;
	Ranrot();	Ranrot();	Ranrot();  // mix it up a bit
}


unsigned Ranrot(void)
{
	sRANROT.high = (sRANROT.high << 16) + (sRANROT.high >> 16);
	sRANROT.high += sRANROT.low;
	sRANROT.low += sRANROT.high;
	return sRANROT.high & 0x7FFFFFFF;
}


float randf (void)
{
	return (Ranrot() & 0xffff) * (1.0f / 65536.0f);
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
	unsigned int x;
	unsigned int y;

	x = seed_ptr->a + seed_ptr->c;
	y = seed_ptr->b + seed_ptr->d;


	if (x > 0xFF)  y++;

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
