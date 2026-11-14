/*

OOEnumerationShufflePRNG.h

The order-deciding core of the debug enumeration shuffle (OOEnumerationShuffle.h), as plain
C with no Objective-C and no dependency on the rest of Oolite.

It is a separate header for one reason: it is the part whose determinism has to be TESTED,
and a test that has to link GNUstep, SDL and SpiderMonkey to check a permutation is a test
nobody runs. tests/unit/test_enumeration_shuffle.c includes this file directly and compiles
in about a second. The Objective-C side then contains no order logic of its own, so the
thing under test is the thing that ships.

Do not use this for anything the game's behaviour depends on. It deliberately does NOT
touch RANROT: consuming numbers from the game's own generator would change gameplay in
exactly the runs this instrumentation is supposed to be observing, which would make every
finding suspect.


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

#ifndef INCLUDED_OOENUMERATIONSHUFFLEPRNG_h
#define INCLUDED_OOENUMERATIONSHUFFLEPRNG_h

#include <stddef.h>
#include <stdint.h>

/*	The seed used when OO_SHUFFLE_ENUMERATION=1. Arbitrary but fixed, so "=1" is a
        reproducible run rather than a random one. It lives in this header, not the
        Objective-C one, so the unit test can use the real value rather than a copy of it.
*/
#define kOOEnumerationShuffleDefaultSeed 0x9E3779B9U

/*	splitmix32. Chosen because its whole state is the seed: there is no warm-up and no
        hidden state between calls, so a permutation is a pure function of (seed, count) and
        the test can assert exact values.
*/
static inline uint32_t OOEnumerationShuffleNext(uint32_t* state)
{
    uint32_t z = (*state += 0x9E3779B9U);
    z = (z ^ (z >> 16)) * 0x21F0AAADU;
    z = (z ^ (z >> 15)) * 0x735A2D97U;
    return z ^ (z >> 15);
}

/*	Uniform in [0, bound), by rejection. Modulo would bias the low indices, which for a
        1000-key ship registry is a visible skew rather than a theoretical one.
*/
static inline uint32_t OOEnumerationShuffleBelow(uint32_t* state, uint32_t bound)
{
    if (bound <= 1)
        return 0;

    uint32_t limit = UINT32_MAX - (UINT32_MAX % bound) - 1;
    uint32_t value;
    do {
        value = OOEnumerationShuffleNext(state);
    } while (value > limit);
    return value % bound;
}

/*	OOEnumerationShuffleSeedFor(seed, count)

        The starting PRNG state for one collection. Mixing the element count in means two
        collections enumerated in the same run get different permutations, while the run as a
        whole stays reproducible from the seed alone.
*/
static inline uint32_t OOEnumerationShuffleSeedFor(uint32_t seed, size_t count)
{
    uint32_t state = seed ^ 0x85EBCA6BU;
    state += (uint32_t)(count * 0x9E3779B9U);
    (void)OOEnumerationShuffleNext(&state);
    return state;
}

/*	OOEnumerationShufflePermutation(seed, count, outIndices)

        Writes a permutation of 0..count-1 into outIndices, which must have room for count
        entries. Fisher-Yates, so every permutation is reachable and none is favoured.

        Pure: the same (seed, count) always produces the same permutation, on any platform,
        in any build. That is what makes a shuffled run reproducible.
*/
static inline void OOEnumerationShufflePermutation(uint32_t seed, size_t count, uint32_t* outIndices)
{
    if (count == 0 || outIndices == NULL)
        return;

    for (size_t i = 0; i < count; i++)
        outIndices[i] = (uint32_t)i;

    uint32_t state = OOEnumerationShuffleSeedFor(seed, count);
    for (size_t i = count - 1; i > 0; i--) {
        uint32_t j = OOEnumerationShuffleBelow(&state, (uint32_t)(i + 1));
        uint32_t tmp = outIndices[i];
        outIndices[i] = outIndices[j];
        outIndices[j] = tmp;
    }
}

#endif /* INCLUDED_OOENUMERATIONSHUFFLEPRNG_h */
