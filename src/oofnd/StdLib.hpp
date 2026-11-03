/*	oofnd/StdLib.hpp
        The C++ standard library headers that game code uses in
   place of Foundation containers, clocks and locks
   (NSArray/NSSet/NSDictionary/NSValue boxing -> std containers, NSDate ->
        std::chrono, NSLock/NSConditionLock ->
   std::mutex/std::condition_variable).

        A game file or header that needs a standard container includes this
   header instead of <vector> etc. (test_stdlib.cpp checks it).

        Add a standard header here when game code first needs it; do not include standard headers
        directly from game code.
*/

#pragma once

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
