/*	oofnd/StdLib.hpp
	The C++ standard library headers that Objective-C++ game code uses in place of Foundation
	containers, clocks and locks (NSArray/NSSet/NSDictionary/NSValue boxing -> std containers, NSDate ->
	std::chrono, NSLock/NSConditionLock -> std::mutex/std::condition_variable (bead oo-3rb.7);
	ADR-0029 Decision 5), included under the OOCocoa.h macro guard (bead oo-3rb.10).

	Game code sees OOCocoa.h's `#define true 1` / `#define false 0`, which break the standard
	headers' keywords (requires-clauses, concepts, <=>). A game file or header that needs a
	standard container includes this header instead of <vector> etc.; the first inclusion parses
	the standard headers with the macros suspended, and later direct includes of the same headers
	are then no-ops (proposed ADR-0028; test_stdlib.cpp checks it).

	Add a standard header here when game code first needs it; do not include standard headers
	directly from game code.
*/

#ifndef OOFND_STDLIB_HPP
#define OOFND_STDLIB_HPP

#pragma push_macro("true")
#pragma push_macro("false")
#undef true
#undef false

#include <algorithm>
#include <chrono>
#include <condition_variable>
#include <cstddef>
#include <cstdint>
#include <functional>
#include <map>
#include <memory>
#include <mutex>
#include <optional>
#include <set>
#include <string>
#include <string_view>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <vector>

#pragma pop_macro("false")
#pragma pop_macro("true")

#endif // OOFND_STDLIB_HPP
