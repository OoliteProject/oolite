/*	oofnd/StdLib.hpp
        The C++ standard library headers that game code uses in
   place of Foundation containers, clocks and locks
   (NSArray/NSSet/NSDictionary/NSValue boxing -> std containers, NSDate ->
        std::chrono, NSLock/NSConditionLock ->
   std::mutex/std::condition_variable).

        No longer used by game code: since spec 009 (T031) each game file
   includes the standard headers it uses directly. Kept, unchanged in content,
   for tests/unit/oofnd/test_stdlib.cpp until Jon decides whether that test is
   retired.
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
