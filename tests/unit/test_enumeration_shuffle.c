/*	test_enumeration_shuffle.c

	Determinism tests for the enumeration shuffle's order logic
	(src/Core/OOEnumerationShufflePRNG.h, seam 0.1a / bead oo-r3r).

	Plain C against a header-only unit, so it builds and runs in about a second with no
	GNUstep, no SDL and no SpiderMonkey:

	    cc -std=c11 -Wall -Wextra -Werror -Isrc/Core \
	       -o build/test_enumeration_shuffle tests/unit/test_enumeration_shuffle.c
	    ./build/test_enumeration_shuffle

	What is actually being asserted is the property the whole instrumentation rests on: a
	shuffled run is REPRODUCIBLE. If the same seed did not give the same order, a shuffled
	failure could not be re-run, and the shuffle would only be able to tell you that
	something somewhere is order-dependent - which is not actionable.
*/

#include <stdio.h>
#include <string.h>

#include "OOEnumerationShufflePRNG.h"

static int sFailures = 0;

#define CHECK(cond, ...) \
	do { \
		if (!(cond)) { \
			printf("FAIL %s:%d: ", __FILE__, __LINE__); \
			printf(__VA_ARGS__); \
			printf("\n"); \
			sFailures++; \
		} \
	} while (0)


/*	A permutation must contain every index exactly once - a shuffle that dropped or
	duplicated a key would silently change what the game enumerates, turning the
	instrumentation itself into the bug it is hunting.
*/
static int IsPermutation(const uint32_t *indices, size_t count)
{
	static char seen[4096];
	if (count > sizeof seen)  return 0;
	memset(seen, 0, count);

	for (size_t i = 0; i < count; i++)
	{
		if (indices[i] >= count)  return 0;
		if (seen[indices[i]])  return 0;
		seen[indices[i]] = 1;
	}
	return 1;
}


static void TestIsAPermutation(void)
{
	uint32_t indices[257];
	const size_t sizes[] = { 0, 1, 2, 3, 7, 64, 257 };

	for (size_t s = 0; s < sizeof sizes / sizeof *sizes; s++)
	{
		size_t count = sizes[s];
		OOEnumerationShufflePermutation(0x9E3779B9U, count, indices);
		CHECK(IsPermutation(indices, count), "count %zu is not a permutation", count);
	}
}


static void TestSameSeedSameOrder(void)
{
	uint32_t a[128], b[128];

	OOEnumerationShufflePermutation(12345U, 128, a);
	OOEnumerationShufflePermutation(12345U, 128, b);
	CHECK(memcmp(a, b, sizeof a) == 0, "seed 12345 did not reproduce its own order");

	/*	And across a call with a different seed in between: the generator must carry no
		state between calls, or the order would depend on what else ran first and a
		re-run would not reproduce.
	*/
	uint32_t other[128];
	OOEnumerationShufflePermutation(999U, 128, other);
	OOEnumerationShufflePermutation(12345U, 128, b);
	CHECK(memcmp(a, b, sizeof a) == 0, "an intervening seed perturbed the order");
}


static void TestDifferentSeedsDiffer(void)
{
	uint32_t a[64], b[64];

	OOEnumerationShufflePermutation(1U, 64, a);
	OOEnumerationShufflePermutation(2U, 64, b);
	CHECK(memcmp(a, b, sizeof a) != 0, "seeds 1 and 2 produced the same order");
}


static void TestActuallyShuffles(void)
{
	/*	The identity permutation is a legal outcome, but at 64 elements it has probability
		1/64! - so seeing it means the shuffle is not running, not that we were unlucky.
	*/
	uint32_t indices[64];
	OOEnumerationShufflePermutation(kOOEnumerationShuffleDefaultSeed, 64, indices);

	int identity = 1;
	for (uint32_t i = 0; i < 64; i++)
	{
		if (indices[i] != i)  { identity = 0; break; }
	}
	CHECK(!identity, "the default seed leaves the order unchanged; the shuffle is not running");
}


static void TestCountAffectsOrder(void)
{
	/*	Two collections of different sizes in the same run must not receive the same
		prefix, or a run would shuffle every collection identically and whole classes of
		order dependency would stay hidden.
	*/
	uint32_t small[16], large[32];
	OOEnumerationShufflePermutation(7U, 16, small);
	OOEnumerationShufflePermutation(7U, 32, large);

	int samePrefix = 1;
	for (size_t i = 0; i < 16; i++)
	{
		if (small[i] != large[i])  { samePrefix = 0; break; }
	}
	CHECK(!samePrefix, "collections of different sizes share a permutation prefix");
}


static void TestBelowIsInRange(void)
{
	uint32_t state = OOEnumerationShuffleSeedFor(42U, 10);
	for (int i = 0; i < 10000; i++)
	{
		uint32_t v = OOEnumerationShuffleBelow(&state, 10);
		CHECK(v < 10, "OOEnumerationShuffleBelow returned %u for bound 10", v);
		if (sFailures)  break;
	}
	CHECK(OOEnumerationShuffleBelow(&state, 1) == 0, "bound 1 must always yield 0");
	CHECK(OOEnumerationShuffleBelow(&state, 0) == 0, "bound 0 must yield 0, not divide by zero");
}


int main(void)
{
	TestIsAPermutation();
	TestSameSeedSameOrder();
	TestDifferentSeedsDiffer();
	TestActuallyShuffles();
	TestCountAffectsOrder();
	TestBelowIsInRange();

	if (sFailures != 0)
	{
		printf("test_enumeration_shuffle: %d failure(s)\n", sFailures);
		return 1;
	}
	printf("test_enumeration_shuffle: OK\n");
	return 0;
}
