/*	test_string_compare.cpp
	oo::str::compare / caseInsensitiveCompare (oofnd/String.hpp; the Foundation sweep, proposed
	ADR-0043) against -[NSString compare:] / -caseInsensitiveCompare: of GNUstep base 1.31.1.

	The digests were captured on this toolchain by a throwaway Objective-C++ probe linked against
	gnustep-base: it built the two corpora below exactly as corpus1()/corpus2() do, compared every
	ordered pair (x, y) with both methods, mapped NSOrderedAscending/Same/Descending to 0/1/2 and
	folded them as h = h * 33 + v (uint32_t, h0 = 5381) in row-major order. To find the pair that
	differs after a failure, rebuild that probe and diff its per-pair output against this test's.
*/

#include "oofnd/String.hpp"

#include "oo_test.hpp"

#include <cstdint>
#include <string>
#include <vector>

namespace {

// Every printable ASCII string of length 1.
std::vector<std::string> corpus1()
{
	std::vector<std::string> c;
	for (int a = 32; a < 127; ++a) c.push_back(std::string(1, static_cast<char>(a)));
	return c;
}

// "", and every string of length 1 and 2 over characters that straddle the case gaps.
std::vector<std::string> corpus2()
{
	const std::string alpha = " -0AZ[_az~Bb";
	std::vector<std::string> c{""};
	for (char x : alpha) c.push_back(std::string(1, x));
	for (char x : alpha)
		for (char y : alpha) c.push_back(std::string{x, y});
	return c;
}

template <class F>
std::uint32_t digest(const std::vector<std::string>& corpus, F order)
{
	std::uint32_t h = 5381;
	for (const std::string& x : corpus)
		for (const std::string& y : corpus) h = h * 33u + static_cast<std::uint32_t>(order(x, y) + 1);
	return h;
}

} // namespace

OO_TEST(compare_matches_gnustep_on_every_ascii_pair)
{
	OO_CHECK_EQ(corpus1().size(), 95u);
	OO_CHECK_EQ(corpus2().size(), 157u);
	OO_CHECK_EQ(digest(corpus1(), oo::str::compare), 2377555174u);
	OO_CHECK_EQ(digest(corpus2(), oo::str::compare), 3348300654u);
}

OO_TEST(case_insensitive_compare_matches_gnustep_on_every_ascii_pair)
{
	OO_CHECK_EQ(digest(corpus1(), oo::str::caseInsensitiveCompare), 3032232806u);
	OO_CHECK_EQ(digest(corpus2(), oo::str::caseInsensitiveCompare), 4004246510u);
}

OO_TEST(readable_rows_captured_from_gnustep)
{
	// (x, y, caseInsensitiveCompare, compare) as GNUstep answered.
	struct Row { const char* x; const char* y; int ci; int cs; };
	const Row rows[] = {
		{"a_", "aB", -1, 1},        // folds to lower case: '_' < 'b'
		{"A", "a", 0, -1},
		{"ab", "abc", -1, -1},      // a prefix orders first
		{"Ab", "aB", 0, -1},
		{"trader", "Trader-courier", -1, 1},
		{"Z", "_", 1, -1},
		{"\xC3\xA9", "e", 1, 1},                // U+00E9 after 'e'
		{"\xC3\x89", "\xC3\xA9", 0, -1},        // U+00C9 / U+00E9: equal ignoring case
		{"\xEF\xBC\xA1", "a", 1, 1},            // U+FF21 lowers to U+FF41, after 'a'
	};
	for (const Row& r : rows)
	{
		OO_CHECK_EQ(oo::str::caseInsensitiveCompare(r.x, r.y), r.ci);
		OO_CHECK_EQ(oo::str::compare(r.x, r.y), r.cs);
	}
}

OO_TEST(not_modelled_composed_sequences)
{
	// GNUstep answers 0 for both ("e" + U+0301 is U+00E9 there); the units decide here.
	OO_CHECK_EQ(oo::str::compare("e\xCC\x81", "\xC3\xA9"), -1);
}

OO_TEST_MAIN()
