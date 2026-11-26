/*

OOEnumerationShuffle.h

Debug-only instrumentation that randomises NSDictionary and NSSet enumeration order so
gameplay paths which silently depend on the current GNUstep order can be found.

Phase 0, seam 0.1a. Objective-C leaves the enumeration order of NSDictionary and NSSet
unspecified; GNUstep happens to produce one order and the C++ port will produce another.
Any code that reads correct today only because of GNUstep's hash order is a latent bug that
would surface after the migration, when there is no reference implementation left to diff
against. Shuffling the order NOW turns those into failures we can see while the reference
still exists.

HOW IT IS TURNED ON

    OO_SHUFFLE_ENUMERATION unset   no shuffle, and in a non-debug build there is not even
                                   a branch: the macros below expand to exactly the
                                   upstream `for (VAR in COLLECTION)`.
    OO_SHUFFLE_ENUMERATION=1       shuffle with the fixed default seed
                                   (kOOEnumerationShuffleDefaultSeed). Reproducible.
    OO_SHUFFLE_ENUMERATION=<n>     shuffle with seed <n>, any unsigned 32-bit decimal.
                                   Reproducible: the same seed and the same collection
                                   contents always yield the same order.
    OO_SHUFFLE_ENUMERATION=0       explicitly off.

Reproducibility is the point. A per-run random order tells you only that *something* is
order-dependent; a seeded order lets you re-run the failure, bisect it, and attach the seed
to a bug report. The seed is mixed with a hash of the collection's contents, so different
collections in one run get different permutations while the whole run stays deterministic.

The shuffle is applied at the *start* of enumeration only: it snapshots the collection into
a shuffled NSArray and enumerates that. It therefore has no effect on mutation-during-
enumeration behaviour beyond what a snapshot already implies, and it never reorders an
NSArray (whose order IS specified, and must not change).

RELEASE BUILDS

Everything here is inside `#if OO_DEBUG`. OO_DEBUG is 0 unless meson was configured with
debug=true or optimization=0 (see the project meson.build), so in the deployment, test and
dev flavours the function declarations do not exist, the .m compiles to an empty
translation unit, and foreach/foreachkey are character-for-character the upstream macros.
That is what makes "byte-identical when unset" checkable by reading the preprocessor output
rather than by trusting a runtime branch.


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

#import "OOFoundation.h"

#if OO_DEBUG

/*	The seed used when OO_SHUFFLE_ENUMERATION=1; defined in OOEnumerationShufflePRNG.h so
        that the unit test can reach it without Objective-C. Re-stated here only as a pointer.
*/
#import "OOEnumerationShufflePRNG.h"

/*	OOEnumerationShuffleEnabled()
        YES if OO_SHUFFLE_ENUMERATION names a non-zero seed. The environment is read once, on
        first call, and cached; changing the variable mid-run has no effect.
*/
BOOL OOEnumerationShuffleEnabled(void);

/*	OOEnumerationShuffleSeed()
        The seed in force, or 0 when disabled. Logged at startup so a failing run can be
        reproduced from its log alone.
*/
uint32_t OOEnumerationShuffleSeed(void);

/*	OOShuffledKeys(dictionary) / OOShuffledObjects(collection)

        Return a shuffled snapshot of the collection's keys/objects when the shuffle is on, and
        the collection itself when it is off (so the disabled path allocates nothing and
        enumerates exactly what upstream enumerated).

        Only NSDictionary and NSSet are reordered. Anything else - notably NSArray, whose order
        is part of its contract - is returned untouched even when the shuffle is on.
*/
id OOShuffledKeys(id dictionary);
id OOShuffledObjects(id collection);

/*	OOEnumerationShuffleReport()
        One line for the log at startup, or nil when disabled.
*/
NSString* OOEnumerationShuffleReport(void);

#endif /* OO_DEBUG */
