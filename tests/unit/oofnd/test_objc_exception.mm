/*	test_objc_exception.mm
	Unit tests for OOException, the Foundation-free Objective-C exception (bead oo-3rb.5, proposed
	ADR-0029 Decision 4). Linked against libobjc2 alone, like test_objc_floor.mm: the point is
	that @throw/@catch/@finally need nothing from GNUstep's Foundation.
*/

#include "oofnd/objc/OOException.h"

#include "oo_test.hpp"

#include <objc/objc-arc.h>

#include <cstring>
#include <string>

namespace {

bool Same(const char *a, const char *b)
{
	return a != nullptr && b != nullptr && std::strcmp(a, b) == 0;
}

void RaiseFormatted(int value)
{
	[OOException raise:OOInvalidArgumentException format:"value %d is %s", value, "bad"];
}

} // namespace

@interface OOTestSubException : OOException
@end

@implementation OOTestSubException
@end


OO_TEST(namesKeepFoundationText)
{
	OO_CHECK(Same(OOGenericException, "NSGenericException"));
	OO_CHECK(Same(OOInvalidArgumentException, "NSInvalidArgumentException"));
	OO_CHECK(Same(OORangeException, "NSRangeException"));
	OO_CHECK(Same(OOInternalInconsistencyException, "NSInternalInconsistencyException"));
	OO_CHECK(Same(OOMallocException, "NSMallocException"));
}

OO_TEST(caughtByClassWithReasonIntact)
{
	void *pool = objc_autoreleasePoolPush();
	bool caught = false;
	std::string name, reason;
	@try
	{
		RaiseFormatted(42);
		OO_CHECK(false);   // unreachable
	}
	@catch (OOException *e)
	{
		caught = true;
		name = [e name];
		reason = [e reason];
	}
	OO_CHECK(caught);
	OO_CHECK_EQ(name, std::string("NSInvalidArgumentException"));
	OO_CHECK_EQ(reason, std::string("value 42 is bad"));
	objc_autoreleasePoolPop(pool);
}

OO_TEST(caughtById)
{
	void *pool = objc_autoreleasePoolPush();
	id caught = nil;
	@try
	{
		[OOException raise:OORangeException format:"index %u out of range", 7u];
	}
	@catch (id e)
	{
		caught = e;
	}
	OO_CHECK(caught != nil);
	OO_CHECK([caught isKindOfClass:[OOException class]]);
	OO_CHECK(Same([(OOException *)caught reason], "index 7 out of range"));
	objc_autoreleasePoolPop(pool);
}

OO_TEST(finallyRunsAndOuterCatches)
{
	void *pool = objc_autoreleasePoolPush();
	int finallies = 0;
	bool outer = false;
	@try
	{
		@try
		{
			[[OOException exceptionWithName:OOGenericException reason:"inner"] raise];
		}
		@finally
		{
			++finallies;
		}
	}
	@catch (OOException *e)
	{
		outer = Same([e reason], "inner");
	}
	OO_CHECK_EQ(finallies, 1);
	OO_CHECK(outer);
	objc_autoreleasePoolPop(pool);
}

OO_TEST(subclassCaughtBySuperclassAndThrowSyntax)
{
	void *pool = objc_autoreleasePoolPush();
	Class seen = Nil;
	@try
	{
		@throw [[[OOTestSubException alloc] initWithName:"OOTestSub" reason:"sub"] autorelease];
	}
	@catch (OOException *e)
	{
		seen = [e class];
		OO_CHECK(Same([e name], "OOTestSub"));
	}
	OO_CHECK(seen == [OOTestSubException class]);
	objc_autoreleasePoolPop(pool);
}

OO_TEST(nullStringsAndEmptyFormat)
{
	void *pool = objc_autoreleasePoolPush();
	OOException *e = [OOException exceptionWithName:nullptr reason:nullptr];
	OO_CHECK(Same([e name], ""));
	OO_CHECK(Same([e reason], ""));
	bool caught = false;
	@try
	{
		[OOException raise:OOGenericException format:"%s", ""];
	}
	@catch (OOException *x)
	{
		caught = Same([x reason], "") && Same([x name], "NSGenericException");
	}
	OO_CHECK(caught);
	objc_autoreleasePoolPop(pool);
}

OO_TEST(longReasonIsNotTruncated)
{
	void *pool = objc_autoreleasePoolPush();
	std::string big(5000, 'x');
	std::string got;
	@try
	{
		[OOException raise:OOGenericException format:"<%s>", big.c_str()];
	}
	@catch (OOException *e)
	{
		got = [e reason];
	}
	OO_CHECK_EQ(got, "<" + big + ">");
	objc_autoreleasePoolPop(pool);
}

OO_TEST_MAIN()
