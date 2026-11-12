/*	test_exception_std.cpp
        Unit tests for oo::Exception as a standard exception (oofnd/Exception.hpp,
   spec 009 FR-014): it is caught by a std::exception handler, what() is its
   reason, and an oo::Exception handler before it still sees the name and the
   reason unchanged. Run: tests/run.sh unit
*/

#include <exception>
#include <string>
#include <type_traits>

#include "oo_test.hpp"
#include "oofnd/Exception.hpp"

static_assert(std::is_base_of_v<std::exception, oo::Exception>);

OO_TEST(caughtAsStdExceptionWithTheReason) {
  bool caught = false;
  try {
    throw oo::Exception("OOTestException", "the reason, in UTF-8: \xc3\xa9");
  } catch (const std::exception& e) {
    caught = true;
    OO_CHECK_EQ(std::string(e.what()),
                std::string("the reason, in UTF-8: \xc3\xa9"));
  }
  OO_CHECK(caught);
}

OO_TEST(ooHandlerFirstStillSeesNameAndReason) {
  int which = 0;
  try {
    throw oo::Exception("OOTestException", "why");
  } catch (const oo::Exception& e) {
    which = 1;
    OO_CHECK_EQ(std::string(e.name()), std::string("OOTestException"));
    OO_CHECK_EQ(std::string(e.reason()), std::string("why"));
  } catch (const std::exception&) {
    which = 2;
  }
  OO_CHECK_EQ(which, 1);
}

OO_TEST(nullNameAndReasonBecomeEmpty) {
  const oo::Exception e(nullptr, nullptr);
  OO_CHECK_EQ(std::string(e.name()), std::string());
  OO_CHECK_EQ(std::string(e.what()), std::string());
}

OO_TEST_MAIN()
