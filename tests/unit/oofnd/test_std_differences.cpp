/*	test_std_differences.cpp
        Spec 009 FR-014: what an oofnd component that stays does where the standard
   library has no equivalent or answers differently, for the cases no other test
   pins. Run: tests/run.sh unit
*/

#include <stdexcept>
#include <string>

#include "oo_test.hpp"
#include "oofnd/Exception.hpp"

// oo::Finally: @finally. C++23 has no scope guard (std::scope_exit is a TS).
OO_TEST(finallyRunsWhenTheScopeIsLeftNormally) {
  std::string order;
  {
    oo::Finally finally([&] { order += "finally"; });
    order += "body,";
  }
  OO_CHECK_EQ(order, std::string("body,finally"));
}

OO_TEST(finallyRunsWhenAnExceptionLeavesTheScope) {
  std::string order;
  try {
    oo::Finally finally([&] { order += "finally,"; });
    order += "body,";
    throw std::runtime_error("out");
  } catch (const std::runtime_error&) {
    order += "handler";
  }
  OO_CHECK_EQ(order, std::string("body,finally,handler"));
}

OO_TEST_MAIN()
