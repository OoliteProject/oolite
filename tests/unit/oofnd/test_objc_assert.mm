/*	test_objc_assert.mm
	Unit tests for OOAssert.h, the Foundation-free assertions (bead oo-diow). Linked against
	libobjc2 alone, like test_objc_exception.mm. The expected reasons are gnustep-base 1.31.1's
	text for NSAssert / NSCAssert / NSParameterAssert, pinned with a throwaway harness when the
	seam was written:

	    probe.m:15  Assertion failed in Probe(instance), method fail:.  x is 3 here
	    probe.m:16  Assertion failed in Probe(instance), method param:.  Invalid parameter not satisfying: p != NULL
	    probe.m:17  Assertion failed in Probe(instance), method classFail.  class side
	    probe.m:20  Assertion failed in void CFail(int).  y is 4

	all raised as NSInternalInconsistencyException. This test builds without NDEBUG, so the macros
	are live.
*/

#include "oofnd/objc/OOAssert.h"

#include "oo_test.hpp"

#include <objc/objc-arc.h>

#include <string>

#ifdef NDEBUG
#error test_objc_assert.mm tests the live macros; it must not be built with NDEBUG
#endif

namespace {

long sLine = 0;

struct Outcome
{
	bool raised = false;
	std::string name;
	std::string reason;
};

template <class F>
Outcome Run(F body)
{
	Outcome outcome;
	void *pool = objc_autoreleasePoolPush();
	@try
	{
		body();
	}
	@catch (OOException *e)
	{
		outcome.raised = true;
		outcome.name = [e name];
		outcome.reason = [e reason];
	}
	objc_autoreleasePoolPop(pool);
	return outcome;
}

std::string At(long line)
{
	return std::string(__FILE__) + ":" + std::to_string(line) + "  Assertion failed in ";
}

void CFail(int y) { sLine = __LINE__; OOCAssert(y == 0, "y is %d", y); }
void CParam(void *p) { sLine = __LINE__; OOCParameterAssert(p != NULL); }

} // namespace

@interface OOAssertProbe : OOObject
- (void) fail:(int)x;
- (void) param:(void *)p;
+ (void) classFail;
@end

@implementation OOAssertProbe
- (void) fail:(int)x { sLine = __LINE__; OOAssert(x == 0, "x is %d here", x); }
- (void) param:(void *)p { sLine = __LINE__; OOParameterAssert(p != NULL); }
+ (void) classFail { sLine = __LINE__; OOAssert(false, "class side"); }
@end


OO_TEST(methodAssertionReasonIsFoundations)
{
	OOAssertProbe *probe = [[OOAssertProbe alloc] init];
	Outcome o = Run([&] { [probe fail:3]; });
	OO_CHECK(o.raised);
	OO_CHECK_EQ(o.name, std::string("NSInternalInconsistencyException"));
	OO_CHECK_EQ(o.reason, At(sLine) + "OOAssertProbe(instance), method fail:.  x is 3 here");
	[probe release];
}

OO_TEST(parameterAssertionNamesTheCondition)
{
	OOAssertProbe *probe = [[OOAssertProbe alloc] init];
	Outcome o = Run([&] { [probe param:nullptr]; });
	OO_CHECK(o.raised);
	OO_CHECK_EQ(o.name, std::string("NSInternalInconsistencyException"));
	OO_CHECK_EQ(o.reason, At(sLine) + "OOAssertProbe(instance), method param:.  Invalid parameter not satisfying: p != NULL");
	[probe release];
}

OO_TEST(classMethodSaysInstanceAsFoundationDid)
{
	Outcome o = Run([] { [OOAssertProbe classFail]; });
	OO_CHECK(o.raised);
	OO_CHECK_EQ(o.reason, At(sLine) + "OOAssertProbe(instance), method classFail.  class side");
}

OO_TEST(functionAssertionUsesPrettyFunction)
{
	Outcome o = Run([] { CFail(4); });
	OO_CHECK(o.raised);
	OO_CHECK_EQ(o.name, std::string("NSInternalInconsistencyException"));
	OO_CHECK_EQ(o.reason, At(sLine) + "void (anonymous namespace)::CFail(int).  y is 4");

	Outcome p = Run([] { CParam(nullptr); });
	OO_CHECK(p.raised);
	OO_CHECK_EQ(p.reason, At(sLine) + "void (anonymous namespace)::CParam(void *).  Invalid parameter not satisfying: p != NULL");
}

OO_TEST(trueConditionsDoNotRaise)
{
	OOAssertProbe *probe = [[OOAssertProbe alloc] init];
	int dummy = 0;
	OO_CHECK(!Run([&] { [probe fail:0]; }).raised);
	OO_CHECK(!Run([&] { [probe param:&dummy]; }).raised);
	OO_CHECK(!Run([] { CFail(0); }).raised);
	OO_CHECK(!Run([&] { CParam(&dummy); }).raised);
	[probe release];
}

OO_TEST_MAIN()
