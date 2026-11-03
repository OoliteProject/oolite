/*

OOEnumerationShuffle.m

See OOEnumerationShuffle.h for what this is for and how it is switched on.


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

#import "OOEnumerationShuffle.h"

/*	Outside the #if: in a non-debug build this file must still be a legal, non-empty
        translation unit, and meson compiles it in every flavour. With OO_DEBUG 0 everything
        below vanishes and what is left is one unused-free typedef, which is the whole point -
        there is no runtime check to get wrong, because there is no runtime code.
*/
#if OO_DEBUG

#import "OOEnumerationShufflePRNG.h"
#import "OOLogging.h"

#include <stdlib.h>

static BOOL sInitialised = NO;
static BOOL sEnabled = NO;
static uint32_t sSeed = 0;

/*	Read OO_SHUFFLE_ENUMERATION once.

        Unset, empty, or a value that parses as 0 means off. "1" means the fixed default seed
        rather than seed 1, because "=1" is what a human types when they mean "turn it on" and
        a documented fixed seed is more useful than an arbitrary one. Any other number is used
        as the seed verbatim.
*/
static void InitShuffleState(void)
{
    if (sInitialised)
        return;
    sInitialised = YES;

    const char* value = getenv("OO_SHUFFLE_ENUMERATION");
    if (value == NULL || *value == '\0')
        return;

    unsigned long parsed = strtoul(value, NULL, 10);
    if (parsed == 0)
        return;

    sEnabled = YES;
    sSeed = (parsed == 1) ? kOOEnumerationShuffleDefaultSeed : (uint32_t)parsed;

    OOLog(@"debug.shuffleEnumeration", @"NSDictionary/NSSet enumeration order is SHUFFLED, seed %u "
                                       @"(OO_SHUFFLE_ENUMERATION=%s). This is instrumentation: gameplay differences from an "
                                       @"unshuffled run are order-dependency bugs, not shuffle bugs.",
        sSeed, value);
}

BOOL OOEnumerationShuffleEnabled(void)
{
    InitShuffleState();
    return sEnabled;
}

uint32_t OOEnumerationShuffleSeed(void)
{
    InitShuffleState();
    return sSeed;
}

NSString* OOEnumerationShuffleReport(void)
{
    if (!OOEnumerationShuffleEnabled())
        return nil;
    return [NSString stringWithFormat:@"enumeration shuffle active, seed %u", OOEnumerationShuffleSeed()];
}

/*	Canonical order before shuffling.

        Without this the permutation would be applied to whatever order GNUstep happened to
        produce, so the shuffled order would inherit GNUstep's - and a second implementation
        with a different hash order would shuffle differently from the same seed. Sorting by
        -description first makes the result a function of the contents alone.

        -description is used rather than -compare: because the keys of Oolite's dictionaries
        are not all NSStrings and not everything implements -compare:. For plist-shaped data
        (which is what these dictionaries hold) -description is content-derived, so the sort is
        stable across runs. For objects whose description embeds an address it is not, and the
        shuffle degrades to "still a permutation, not reproducible" - noted rather than fixed,
        because no dictionary in the tree is keyed by such an object.
*/
static NSInteger CompareByDescription(id a, id b, void* context)
{
    (void)context;
    return (NSInteger)[[a description] compare:[b description]];
}

static NSArray* ShuffledArrayFromCollection(NSArray* members)
{
    NSUInteger count = [members count];
    if (count < 2)
        return members;

    NSArray* canonical = [members sortedArrayUsingFunction:CompareByDescription context:NULL];

    uint32_t* order = calloc(count, sizeof *order);
    if (order == NULL)
        return canonical; // Out of memory in instrumentation: degrade, do not crash.

    OOEnumerationShufflePermutation(OOEnumerationShuffleSeed(), (size_t)count, order);

    NSMutableArray* result = [NSMutableArray arrayWithCapacity:count];
    for (NSUInteger i = 0; i < count; i++) {
        [result addObject:[canonical objectAtIndex:(NSUInteger)order[i]]];
    }
    free(order);

    return result;
}

id OOShuffledKeys(id dictionary)
{
    // Disabled, or not a dictionary: hand back exactly what was passed, so the caller
    // enumerates precisely what it would have enumerated upstream.
    if (!OOEnumerationShuffleEnabled())
        return dictionary;
    if (![dictionary isKindOfClass:[NSDictionary class]])
        return dictionary;

    return ShuffledArrayFromCollection([dictionary allKeys]);
}

id OOShuffledObjects(id collection)
{
    if (!OOEnumerationShuffleEnabled())
        return collection;

    // NSArray order is specified by its contract; reordering one would be a bug, not
    // instrumentation. Only the unordered collections are touched.
    if ([collection isKindOfClass:[NSSet class]]) {
        return ShuffledArrayFromCollection([collection allObjects]);
    }
    if ([collection isKindOfClass:[NSDictionary class]]) {
        // foreach over a dictionary yields keys under fast enumeration.
        return ShuffledArrayFromCollection([collection allKeys]);
    }

    return collection;
}

#endif /* OO_DEBUG */
