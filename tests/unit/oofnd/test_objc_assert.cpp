/*	test_objc_assert.mm
        Unit tests for OOAssert.h, the Foundation-free assertions (bead
   oo-diow). Linked against libobjc2 alone, like test_objc_exception.mm, until
   bead oo-dbz. The expected reasons are gnustep-base 1.31.1's text for NSAssert
   / NSCAssert / NSParameterAssert, pinned with a throwaway harness when the
        seam was written:

            probe.m:15  Assertion failed in Probe(instance), method fail:.  x is
   3 here probe.m:16  Assertion failed in Probe(instance), method param:.
   Invalid parameter not satisfying: p != NULL probe.m:17  Assertion failed in
   Probe(instance), method classFail.  class side probe.m:20  Assertion failed
   in void CFail(int).  y is 4

        all raised as NSInternalInconsistencyException. This test builds without
   NDEBUG, so the macros are live. The method forms (OOAssert,
   OOParameterAssert) and their cases (the first three probe lines) went with
   libobjc2, bead oo-dbz.4: no game code called them; the function forms stay.
*/

#include <string>

#include "oo_test.hpp"
#include "oofnd/objc/OOAssert.h"

#ifdef NDEBUG
#error test_objc_assert.mm tests the live macros; it must not be built with NDEBUG
#endif

namespace {

long sLine = 0;

struct Outcome {
  bool raised = false;
  std::string name;
  std::string reason;
};

template <class F>
Outcome Run(F body) {
  Outcome outcome;
  try {
    body();
  } catch (
      const oo::Exception& e)  // was @catch (OOException *e) (bead oo-rskgl.1)
  {
    outcome.raised = true;
    outcome.name = e.name();
    outcome.reason = e.reason();
  }
  return outcome;  // (an Objective-C autorelease pool was pushed and popped
                   // around the body until bead oo-dbz.4; it held nothing)
}

std::string At(long line) {
  return std::string(__FILE__) + ":" + std::to_string(line) +
         "  Assertion failed in ";
}

// clang-format off: each assertion must be on the line sLine records.
void CFail(int y) { sLine = __LINE__; OOCAssert(y == 0, "y is %d", y); }
void CParam(void *p) { sLine = __LINE__; OOCParameterAssert(p != NULL); }
// clang-format on

}  // namespace

OO_TEST(functionAssertionUsesPrettyFunction) {
  Outcome o = Run([] { CFail(4); });
  OO_CHECK(o.raised);
  OO_CHECK_EQ(o.name, std::string("NSInternalInconsistencyException"));
#if defined(__GNUC__) && !defined(__clang__)
  OO_CHECK_EQ(o.reason, At(sLine) + "void {anonymous}::CFail(int).  y is 4");
#else
  OO_CHECK_EQ(o.reason,
              At(sLine) + "void (anonymous namespace)::CFail(int).  y is 4");
#endif

  Outcome p = Run([] { CParam(nullptr); });
  OO_CHECK(p.raised);
#if defined(__GNUC__) && !defined(__clang__)
  OO_CHECK_EQ(p.reason, At(sLine) +
                            "void {anonymous}::CParam(void*).  Invalid "
                            "parameter not satisfying: p != NULL");
#else
  OO_CHECK_EQ(p.reason, At(sLine) +
                            "void (anonymous namespace)::CParam(void *).  "
                            "Invalid parameter not satisfying: p != NULL");
#endif
}

OO_TEST(trueConditionsDoNotRaise) {
  int dummy = 0;
  OO_CHECK(!Run([] { CFail(0); }).raised);
  OO_CHECK(!Run([&] { CParam(&dummy); }).raised);
}

OO_TEST_MAIN()
