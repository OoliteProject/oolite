/*	test_stdlib.cpp
	Regression test for bead oo-3rb.10: oofnd/StdLib.hpp, the standard containers and clocks
	Objective-C++ game code uses, must compile after OOCocoa.h's `#define true 1` /
	`#define false 0` and hand those macros back unchanged (see test_cocoa_macros.cpp).
*/

#define true						1
#define false						0

#include "oofnd/StdLib.hpp"

// Direct includes after StdLib.hpp are include-guarded no-ops, as game code relies on.
#include <vector>
#include <unordered_map>

#include <type_traits>

static_assert(std::is_same_v<decltype(true), int>, "StdLib.hpp must restore OOCocoa.h's true macro");
static_assert(std::is_same_v<decltype(false), int>, "StdLib.hpp must restore OOCocoa.h's false macro");
static constexpr int kTrueAfter = true;
static constexpr int kFalseAfter = false;

#undef true
#undef false

#include "oo_test.hpp"

namespace {

struct Matrix { float m[4][4]; };

OO_TEST(macrosAreRestoredWithTheirValues)
{
	OO_CHECK_EQ(kTrueAfter, 1);
	OO_CHECK_EQ(kFalseAfter, 0);
}

OO_TEST(containersWork)
{
	// The shapes the NSValue exemplars use: a value stack, a pointer set, a string-keyed map.
	std::vector<Matrix> stack;
	stack.push_back(Matrix{ { { 1.0f } } });
	OO_CHECK_EQ(stack.size(), 1u);
	OO_CHECK(stack.back().m[0][0] == 1.0f);

	int a = 0;
	std::unordered_set<int*> set;
	set.insert(&a);
	set.insert(&a);
	OO_CHECK_EQ(set.size(), 1u);

	std::unordered_map<std::string, int*> cache;
	cache["key"] = &a;
	OO_CHECK(cache.find("key")->second == &a);
	OO_CHECK(cache.find("other") == cache.end());

	const auto t0 = std::chrono::steady_clock::now();
	OO_CHECK(std::chrono::steady_clock::now() >= t0);
}

} // namespace

OO_TEST_MAIN()
