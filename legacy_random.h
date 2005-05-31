/*
 *  legacy_random.h
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

#ifndef GNUSTEP
#include <Carbon/Carbon.h>
#endif

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

// checksum stuff
void clear_checksum();
int munge_checksum(int value);


// an implementation of RANROT
// pseudo random number generator
//
inline void ranrot_srand(unsigned int seed);
inline int ranrot_rand();

double distanceBetweenPlanetPositions ( int x1, int y1, int x2, int y2);
double accurateDistanceBetweenPlanetPositions ( int x1, int y1, int x2, int y2);

void seed_for_planet_description (Random_Seed s_seed);
void seed_RNG_only_for_planet_description (Random_Seed s_seed);
RNG_Seed currentRandomSeed (void);
void setRandomSeed (RNG_Seed a_seed);
int get_carry_flag (void);
void clear_carry_flag (void);

inline float randf (void);
inline float bellf (int n);

int gen_rnd_number (void);

void rotate_seed (struct rand_seed_6uc *seed_ptr);
int rotate_byte_left (int x);

int equal_seeds (Random_Seed seed1, Random_Seed seed2);
