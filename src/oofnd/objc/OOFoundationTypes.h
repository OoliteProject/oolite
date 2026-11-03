/*	oofnd/objc/OOFoundationTypes.h
        Foundation's plain C types, without Foundation (proposed ADR-0029 Decision 5, bead oo-3rb.21).

        NSInteger/NSUInteger (1,245 refs), NSRange/NSNotFound (232) and NSPoint/NSSize/NSRect (516) are
        C typedefs, structs and inline functions. Renaming ~2,000 sites is churn with no behaviour
        (the ADR-0012 argument), so the names stay and this header gives them GNUstep's exact
        definitions. The layouts, values and results are pinned against numbers recorded from GNUstep
        on this toolchain by tests/unit/oofnd/test_foundation_types.cpp.

            NSInteger, NSUInteger          intptr_t, uintptr_t (NSObjCRuntime.h)
            NSIntegerMax/Min, NSUIntegerMax INTPTR_MAX/MIN, UINTPTR_MAX
            NSNotFound                     static const NSInteger = NSIntegerMax
            NSTimeInterval                 double (Foundation's date header)
            CGFloat                        double on _WIN64 and LP64, else float (CoreFoundation/CFCGTypes.h)
            NSPoint, NSSize, NSRect        struct CGPoint {x, y}, CGSize {width, height},
                                           CGRect {origin, size} (NSGeometry.h)
            NSZeroPoint/Size/Rect          static const, all zero
            NSRange                        struct _NSRange {location, length} (NSRange.h)
            NSMakeRange, NSMaxRange, NSLocationInRange, NSEqualRanges
            NSMakePoint, NSMakeSize, NSMakeRect, NSEqualPoints, NSEqualSizes, NSEqualRects

        One deliberate difference: NSMakeRange with location + length overflowing NSUInteger raised
        Foundation's range exception; here it logs and aborts (as OOObject's
        -doesNotRecognizeSelector: does, ADR-0029). Nothing in Oolite catches it.

        Foundation defines every one of these names, so this header refuses to compile beside it: it is
        included by OOFoundation.h only when oo-qps removes the Foundation import. Plain C: usable from C,
        C++, Objective-C and Objective-C++.
*/

#ifndef OOFND_OBJC_OOFOUNDATIONTYPES_H
#define OOFND_OBJC_OOFOUNDATIONTYPES_H

// Any Foundation header defines GNUSTEP_BASE_MAJOR_VERSION (GSConfig.h) or one of these guards.
// Included the other way round (this header first), Foundation's own NSNotFound and struct
// _NSRange collide with these, so the two cannot be mixed silently in either order.
#if defined(GNUSTEP_BASE_MAJOR_VERSION) || defined(NSINTEGER_DEFINED) || defined(__NSRange_h_GNUSTEP_BASE_INCLUDE) || defined(__NSGeometry_h_GNUSTEP_BASE_INCLUDE)
#error "oofnd/objc/OOFoundationTypes.h replaces Foundation's C types and cannot be used together with Foundation"
#endif

/*	The Objective-C boolean and null names, as libobjc2's <objc/runtime.h> gave them to the game's
        Objective-C++ (built with STRICT_APPLE_COMPATIBILITY: BOOL is signed char, YES and NO are BOOL,
        nil and Nil are nullptr), kept for the game's C and C++ since libobjc2 went (bead oo-dbz).
*/
typedef signed char BOOL;
#define YES ((BOOL)1)
#define NO ((BOOL)0)
#ifdef __cplusplus
#define nil nullptr
#define Nil nullptr
#else
#define nil ((void*)0)
#define Nil ((void*)0)
#endif
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef intptr_t NSInteger;
typedef uintptr_t NSUInteger;
#define NSIntegerMax INTPTR_MAX
#define NSIntegerMin INTPTR_MIN
#define NSUIntegerMax UINTPTR_MAX
#define NSINTEGER_DEFINED 1

static const NSInteger NSNotFound = NSIntegerMax;

typedef double NSTimeInterval;

#if (defined(__LP64__) && __LP64__) || defined(_WIN64)
typedef double CGFloat;
#define CGFLOAT_IS_DOUBLE 1
#else
typedef float CGFloat;
#define CGFLOAT_IS_DOUBLE 0
#endif
#define CGFLOAT_DEFINED 1

struct CGPoint {
    CGFloat x;
    CGFloat y;
};
typedef struct CGPoint CGPoint;
typedef struct CGPoint NSPoint;

struct CGSize {
    CGFloat width;
    CGFloat height;
};
typedef struct CGSize CGSize;
typedef struct CGSize NSSize;

struct CGRect {
    CGPoint origin;
    CGSize size;
};
typedef struct CGRect CGRect;
typedef struct CGRect NSRect;

static const NSPoint NSZeroPoint = { 0.0, 0.0 };
static const NSSize NSZeroSize = { 0.0, 0.0 };
static const NSRect NSZeroRect = { { 0.0, 0.0 }, { 0.0, 0.0 } };

typedef struct _NSRange NSRange;
struct _NSRange {
    NSUInteger location;
    NSUInteger length;
};

static inline NSUInteger NSMaxRange(NSRange range)
{
    return range.location + range.length;
}

static inline BOOL NSLocationInRange(NSUInteger location, NSRange range)
{
    return (location >= range.location) && (location < NSMaxRange(range));
}

static inline NSRange NSMakeRange(NSUInteger location, NSUInteger length)
{
    NSRange range;
    NSUInteger end = location + length;
    if (end < location || end < length) {
        fprintf(stderr, "oofnd: NSMakeRange(%llu, %llu): range location + length too great\n",
            (unsigned long long)location, (unsigned long long)length);
        abort();
    }
    range.location = location;
    range.length = length;
    return range;
}

static inline BOOL NSEqualRanges(NSRange range1, NSRange range2)
{
    return ((range1.location == range2.location) && (range1.length == range2.length));
}

static inline NSPoint NSMakePoint(CGFloat x, CGFloat y)
{
    NSPoint point;
    point.x = x;
    point.y = y;
    return point;
}

static inline NSSize NSMakeSize(CGFloat w, CGFloat h)
{
    NSSize size;
    size.width = w;
    size.height = h;
    return size;
}

static inline NSRect NSMakeRect(CGFloat x, CGFloat y, CGFloat w, CGFloat h)
{
    NSRect rect;
    rect.origin.x = x;
    rect.origin.y = y;
    rect.size.width = w;
    rect.size.height = h;
    return rect;
}

// GNUstep exports these from NSGeometry.m; the bodies are its (plain ==, so -0.0 equals 0.0 and
// NaN equals nothing, as recorded by the unit test).
static inline BOOL NSEqualPoints(NSPoint aPoint, NSPoint bPoint)
{
    return ((aPoint.x == bPoint.x) && (aPoint.y == bPoint.y)) ? YES : NO;
}

static inline BOOL NSEqualSizes(NSSize aSize, NSSize bSize)
{
    return ((aSize.width == bSize.width) && (aSize.height == bSize.height)) ? YES : NO;
}

static inline BOOL NSEqualRects(NSRect aRect, NSRect bRect)
{
    return (NSEqualPoints(aRect.origin, bRect.origin) && NSEqualSizes(aRect.size, bRect.size)) ? YES : NO;
}

#ifdef __cplusplus
}
#endif

#endif // OOFND_OBJC_OOFOUNDATIONTYPES_H
