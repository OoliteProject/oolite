/*	oofnd/objc/OOFoundationTypes.h
        What is left of Foundation's plain C types: the geometry structs and
   NSRange, which have no standard equivalent, and oo::kNotFound.

        Since spec 009 (T033) game code uses the standard types for the rest:
   NSInteger/NSUInteger were intptr_t/uintptr_t and are std::ptrdiff_t/
   std::size_t (the same types on Windows x64, macOS and Linux 64-bit);
   NSIntegerMax/Min and NSUIntegerMax are PTRDIFF_MAX/MIN and SIZE_MAX;
   NSTimeInterval and CGFloat were double on every 64-bit target and are
   double; NSNotFound is oo::kNotFound, with the same value.

            NSPoint, NSSize, NSRect        struct CGPoint {x, y}, CGSize {width,
   height}, CGRect {origin, size} (NSGeometry.h), of double
            NSZeroPoint/Size/Rect          static const, all zero
            NSRange                        struct _NSRange {location, length},
   of std::size_t (NSRange.h); NSMakeRange, NSMaxRange, NSLocationInRange,
   NSEqualRanges
            NSMakePoint, NSMakeSize, NSMakeRect, NSEqualPoints, NSEqualSizes,
   NSEqualRects

        The layouts, values and results are pinned against numbers recorded
   from GNUstep on this toolchain by tests/unit/oofnd/test_foundation_types.cpp.

        One deliberate difference: NSMakeRange with location + length
   overflowing std::size_t raised Foundation's range exception; here it logs and
   aborts (as OOObject's -doesNotRecognizeSelector: does). Nothing in Oolite
   catches it.

        Foundation defines these names, so this header refuses to compile beside
   it: it is included by OOFoundation.h only when the Foundation import is
   removed.
*/

#pragma once

// Any Foundation header defines GNUSTEP_BASE_MAJOR_VERSION (GSConfig.h) or one
// of these guards. Included the other way round (this header first),
// Foundation's own NSNotFound and struct _NSRange collide with these, so the
// two cannot be mixed silently in either order.
#if defined(GNUSTEP_BASE_MAJOR_VERSION) || defined(NSINTEGER_DEFINED) || \
    defined(__NSRange_h_GNUSTEP_BASE_INCLUDE) ||                         \
    defined(__NSGeometry_h_GNUSTEP_BASE_INCLUDE)
#error \
    "oofnd/objc/OOFoundationTypes.h replaces Foundation's C types and cannot be used together with Foundation"
#endif

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#include <cstddef>

#ifdef __cplusplus
namespace oo {

// Foundation's NSNotFound: the largest pointer-sized signed integer
// (INTPTR_MAX). Game code compares indices with it, hands it to JavaScript as a
// number, casts it to int (-1) and stores it as a save default, so the value is
// load-bearing; it is not std::string::npos.
inline constexpr std::ptrdiff_t kNotFound = INTPTR_MAX;

}  // namespace oo
#endif

struct CGPoint {
  double x;
  double y;
};
typedef struct CGPoint CGPoint;
typedef struct CGPoint NSPoint;

struct CGSize {
  double width;
  double height;
};
typedef struct CGSize CGSize;
typedef struct CGSize NSSize;

struct CGRect {
  CGPoint origin;
  CGSize size;
};
typedef struct CGRect CGRect;
typedef struct CGRect NSRect;

static const NSPoint NSZeroPoint = {0.0, 0.0};
static const NSSize NSZeroSize = {0.0, 0.0};
static const NSRect NSZeroRect = {{0.0, 0.0}, {0.0, 0.0}};

typedef struct _NSRange NSRange;
struct _NSRange {
  std::size_t location;
  std::size_t length;
};

static inline std::size_t NSMaxRange(NSRange range) {
  return range.location + range.length;
}

static inline bool NSLocationInRange(std::size_t location, NSRange range) {
  return (location >= range.location) && (location < NSMaxRange(range));
}

static inline NSRange NSMakeRange(std::size_t location, std::size_t length) {
  NSRange range;
  std::size_t end = location + length;
  if (end < location || end < length) {
    fprintf(
        stderr,
        "oofnd: NSMakeRange(%llu, %llu): range location + length too great\n",
        (unsigned long long)location, (unsigned long long)length);
    abort();
  }
  range.location = location;
  range.length = length;
  return range;
}

static inline bool NSEqualRanges(NSRange range1, NSRange range2) {
  return ((range1.location == range2.location) &&
          (range1.length == range2.length));
}

static inline NSPoint NSMakePoint(double x, double y) {
  NSPoint point;
  point.x = x;
  point.y = y;
  return point;
}

static inline NSSize NSMakeSize(double w, double h) {
  NSSize size;
  size.width = w;
  size.height = h;
  return size;
}

static inline NSRect NSMakeRect(double x, double y, double w, double h) {
  NSRect rect;
  rect.origin.x = x;
  rect.origin.y = y;
  rect.size.width = w;
  rect.size.height = h;
  return rect;
}

// GNUstep exports these from NSGeometry.m; the bodies are its (plain ==, so
// -0.0 equals 0.0 and NaN equals nothing, as recorded by the unit test).
static inline bool NSEqualPoints(NSPoint aPoint, NSPoint bPoint) {
  return ((aPoint.x == bPoint.x) && (aPoint.y == bPoint.y)) ? true : false;
}

static inline bool NSEqualSizes(NSSize aSize, NSSize bSize) {
  return ((aSize.width == bSize.width) && (aSize.height == bSize.height))
             ? true
             : false;
}

static inline bool NSEqualRects(NSRect aRect, NSRect bRect) {
  return (NSEqualPoints(aRect.origin, bRect.origin) &&
          NSEqualSizes(aRect.size, bRect.size))
             ? true
             : false;
}
