/*	test_objc_assert_ndebug.cpp
        OOAssert.h compiled the way a deployment build compiles it: with NDEBUG.

        Upstream's Foundation assertions were live in every flavour:
   OOFoundation.h defines NS_BLOCK_ASSERTIONS only after importing the
   Foundation umbrella header, too late for gnustep-base's include-guarded
   exception header. Blocking OOCAssert under NDEBUG skips the side effect in PlayerEntity::deferredInit's assertion (the
   player's ship set-up), so a deployment build cannot launch. This test is
   built with NDEBUG in every flavour, so the test flavour catches a regression
        that only a deployment build would show: the condition (and its side
   effects) must be evaluated and a false one must still raise. The reasons' text is
	test_objc_assert.cpp's subject; here only that the macros are live.
*/

#ifndef NDEBUG
#define NDEBUG 1 // the deployment flavour's macro (meson.build, deployment_release)
#endif

#include "oofnd/Exception.hpp"
#include "oofnd/objc/OOAssert.h"

#include "oo_test.hpp"

namespace {

int sCalls = 0;

bool CountedTrue()
{
	++sCalls;
	return true;
}

template <class F>
bool Raises(F body)
{
	try
	{
		body();
	}
	catch (const oo::Exception &)
	{
		return true;
	}
	return false;
}

// They return their argument so a macro that compiles its arguments out still builds (and the
// checks below, not -Wunused-parameter, report it).
int CFail(int y) { OOCAssert(y == 0, "y is %d", y); return y; }
void *CParam(void *p) { OOCParameterAssert(p != nullptr); return p; }

} // namespace

OO_TEST(conditionSideEffectsRunUnderNDEBUG)
{
	sCalls = 0;
	OOCAssert(CountedTrue(), "never fails");
	OOCParameterAssert(CountedTrue());
	OO_CHECK_EQ(sCalls, 2);
	OO_CHECK(CountedTrue()); // and referenced here, so a macro that drops its argument still builds
}

OO_TEST(falseConditionsRaiseUnderNDEBUG)
{
	OO_CHECK(Raises([] { CFail(4); }));
	OO_CHECK(Raises([] { CParam(nullptr); }));
	OO_CHECK(!Raises([] { CFail(0); }));
}

OO_TEST_MAIN()
