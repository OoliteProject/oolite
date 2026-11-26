/*	test_foundation_types.cpp
	Bead oo-3rb.21 (proposed ADR-0029 Decision 5): oofnd/objc/OOFoundationTypes.h must be
	GNUstep's NSInteger/NSRange/NSPoint/NSSize/NSRect family bit for bit.

	The header refuses to compile beside Foundation, so GNUstep's side cannot be in this TU. Every
	expected number below was recorded from a throwaway probe built against gnustep-base on this
	toolchain (MSYS2 UCRT64, clang 22.1.8, gnustep-base 1.31, -fobjc-runtime=gnustep-2.2,
	2026-09-23): sizeof/alignof/offsetof of each struct, the type identities, the constants, and
	the results of each function on the same arguments. A difference here is a difference from
	the game's current Foundation.
*/

#include "oofnd/objc/OOFoundationTypes.h"

#include <cmath>
#include <cstddef>
#include <cstdint>
#include <type_traits>

#include "oo_test.hpp"

// Recorded: sizeof NSInteger 8 align 8 signed, same as intptr_t and long long; NSUInteger 8,
// same as uintptr_t and unsigned long long.
static_assert(std::is_same_v<NSInteger, intptr_t>);
static_assert(std::is_same_v<NSUInteger, uintptr_t>);
static_assert(std::is_same_v<NSInteger, long long>);
static_assert(std::is_same_v<NSUInteger, unsigned long long>);
static_assert(sizeof(NSInteger) == 8 && alignof(NSInteger) == 8);
static_assert(sizeof(NSUInteger) == 8 && alignof(NSUInteger) == 8);

// Recorded: CGFloat is double (8 bytes), CGFLOAT_IS_DOUBLE 1; NSTimeInterval is double.
static_assert(std::is_same_v<CGFloat, double>);
static_assert(CGFLOAT_IS_DOUBLE == 1);
static_assert(std::is_same_v<NSTimeInterval, double>);

// Recorded: BOOL is signed char (libobjc2's), 1 byte.
static_assert(std::is_same_v<BOOL, signed char>);

// Recorded: NSPoint/NSSize/NSRect are CGPoint/CGSize/CGRect.
static_assert(std::is_same_v<NSPoint, CGPoint>);
static_assert(std::is_same_v<NSSize, CGSize>);
static_assert(std::is_same_v<NSRect, CGRect>);

// Recorded layouts.
static_assert(sizeof(NSRange) == 16 && alignof(NSRange) == 8);
static_assert(offsetof(NSRange, location) == 0 && offsetof(NSRange, length) == 8);
static_assert(sizeof(NSPoint) == 16 && alignof(NSPoint) == 8);
static_assert(offsetof(NSPoint, x) == 0 && offsetof(NSPoint, y) == 8);
static_assert(sizeof(NSSize) == 16 && alignof(NSSize) == 8);
static_assert(offsetof(NSSize, width) == 0 && offsetof(NSSize, height) == 8);
static_assert(sizeof(NSRect) == 32 && alignof(NSRect) == 8);
static_assert(offsetof(NSRect, origin) == 0 && offsetof(NSRect, size) == 16);
static_assert(offsetof(NSRect, origin.y) == 8 && offsetof(NSRect, size.height) == 24);

// Recorded: NSNotFound is a const NSInteger.
static_assert(std::is_same_v<std::remove_cv_t<decltype(NSNotFound)>, NSInteger>);

OO_TEST(constantsMatchGNUstep)
{
	// Recorded: NSNotFound 9223372036854775807, NSIntegerMax the same,
	// NSIntegerMin -9223372036854775808, NSUIntegerMax 18446744073709551615.
	OO_CHECK_EQ(static_cast<long long>(NSNotFound), 9223372036854775807LL);
	OO_CHECK_EQ(static_cast<long long>(NSIntegerMax), 9223372036854775807LL);
	OO_CHECK_EQ(static_cast<long long>(NSIntegerMin), -9223372036854775807LL - 1);
	OO_CHECK_EQ(static_cast<unsigned long long>(NSUIntegerMax), 18446744073709551615ULL);
}

OO_TEST(zeroGeometryIsZero)
{
	OO_CHECK(NSZeroPoint.x == 0.0 && NSZeroPoint.y == 0.0);
	OO_CHECK(NSZeroSize.width == 0.0 && NSZeroSize.height == 0.0);
	OO_CHECK(NSZeroRect.origin.x == 0.0 && NSZeroRect.origin.y == 0.0);
	OO_CHECK(NSZeroRect.size.width == 0.0 && NSZeroRect.size.height == 0.0);
}

OO_TEST(rangeFunctionsMatchGNUstep)
{
	const NSRange r = NSMakeRange(3, 4);
	// Recorded: NSMakeRange(3,4) = {3, 4}, NSMaxRange 7.
	OO_CHECK_EQ(r.location, 3u);
	OO_CHECK_EQ(r.length, 4u);
	OO_CHECK_EQ(NSMaxRange(r), 7u);
	// Recorded: NSLocationInRange 2 -> 0, 3 -> 1, 6 -> 1, 7 -> 0; 0 in {0,0} -> 0.
	OO_CHECK_EQ(NSLocationInRange(2, r), NO);
	OO_CHECK_EQ(NSLocationInRange(3, r), YES);
	OO_CHECK_EQ(NSLocationInRange(6, r), YES);
	OO_CHECK_EQ(NSLocationInRange(7, r), NO);
	OO_CHECK_EQ(NSLocationInRange(0, NSMakeRange(0, 0)), NO);
	// Recorded: NSMakeRange(NSNotFound, 0) = {9223372036854775807, 0} (not an overflow).
	const NSRange notFound = NSMakeRange(NSNotFound, 0);
	OO_CHECK_EQ(notFound.location, static_cast<NSUInteger>(NSNotFound));
	OO_CHECK_EQ(notFound.length, 0u);
	// Recorded: NSEqualRanges same -> 1, different length -> 0.
	OO_CHECK_EQ(NSEqualRanges(r, NSMakeRange(3, 4)), YES);
	OO_CHECK_EQ(NSEqualRanges(r, NSMakeRange(3, 5)), NO);
	// (Recorded: NSMakeRange(NSUIntegerMax, 2) raised NSRangeException; here it aborts, by design.)
}

OO_TEST(geometryConstructorsMatchGNUstep)
{
	// Recorded: NSMakePoint 1.5 -2.25, NSMakeSize 3 4.5, NSMakeRect 1 2 3 4.
	const NSPoint p = NSMakePoint(1.5, -2.25);
	const NSSize s = NSMakeSize(3.0, 4.5);
	const NSRect rc = NSMakeRect(1, 2, 3, 4);
	OO_CHECK(p.x == 1.5 && p.y == -2.25);
	OO_CHECK(s.width == 3.0 && s.height == 4.5);
	OO_CHECK(rc.origin.x == 1.0 && rc.origin.y == 2.0 && rc.size.width == 3.0 && rc.size.height == 4.0);
}

OO_TEST(geometryEqualityMatchesGNUstep)
{
	const NSPoint p = NSMakePoint(1.5, -2.25);
	const NSSize s = NSMakeSize(3.0, 4.5);
	const NSRect rc = NSMakeRect(1, 2, 3, 4);
	// Recorded: NSEqualPoints same 1, diff 0, {0,-0} vs {-0,0} 1, NaN 0.
	OO_CHECK_EQ(NSEqualPoints(p, NSMakePoint(1.5, -2.25)), YES);
	OO_CHECK_EQ(NSEqualPoints(p, NSMakePoint(1.5, 2.25)), NO);
	OO_CHECK_EQ(NSEqualPoints(NSMakePoint(0.0, -0.0), NSMakePoint(-0.0, 0.0)), YES);
	OO_CHECK_EQ(NSEqualPoints(NSMakePoint(NAN, 0), NSMakePoint(NAN, 0)), NO);
	// Recorded: NSEqualSizes same 1, diff 0, -0 vs 0 1, NaN 0.
	OO_CHECK_EQ(NSEqualSizes(s, NSMakeSize(3, 4.5)), YES);
	OO_CHECK_EQ(NSEqualSizes(s, NSMakeSize(3, 4)), NO);
	OO_CHECK_EQ(NSEqualSizes(NSMakeSize(-0.0, 0), NSMakeSize(0, 0)), YES);
	OO_CHECK_EQ(NSEqualSizes(NSMakeSize(NAN, 0), NSMakeSize(NAN, 0)), NO);
	// Recorded: NSEqualRects same 1, diff 0, -0 origin vs NSZeroRect 1, NaN 0, and two empty
	// rects at different origins 0 (equality is by all four fields, not by emptiness).
	OO_CHECK_EQ(NSEqualRects(rc, NSMakeRect(1, 2, 3, 4)), YES);
	OO_CHECK_EQ(NSEqualRects(rc, NSMakeRect(1, 2, 3, 5)), NO);
	OO_CHECK_EQ(NSEqualRects(NSMakeRect(-0.0, 0, 0, 0), NSZeroRect), YES);
	OO_CHECK_EQ(NSEqualRects(NSMakeRect(NAN, 0, 0, 0), NSMakeRect(NAN, 0, 0, 0)), NO);
	OO_CHECK_EQ(NSEqualRects(NSMakeRect(5, 5, 0, 0), NSMakeRect(9, 9, 0, 0)), NO);
}

OO_TEST_MAIN()
