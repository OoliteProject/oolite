#pragma once

#ifndef GCC_ATTR
#ifdef __GNUC__
#define GCC_ATTR(x) __attribute__(x)
#else
#define GCC_ATTR(x)
#endif
#endif

// Clang feature testing extensions.
#ifndef __has_feature
#define __has_feature(x) (0)
#endif

#ifndef __has_attribute
#define __has_attribute(x) (0)
#endif

#ifndef __has_extension
#define __has_extension(x) (0)
#endif

#define OOINLINE inline

#if !OO_DEBUG
#define ALWAYS_INLINE_FUNC \
  GCC_ATTR((always_inline))  // Force inlining of function
#else
#define ALWAYS_INLINE_FUNC  // Don't force inlining of function (because gdb is
                            // silly)
#endif

#define PURE_FUNC \
  GCC_ATTR((pure))  // result dependent only on params and globals
#define CONST_FUNC \
  GCC_ATTR((const))  // pure + no pointer dereferences or globals
#define NONNULL_FUNC GCC_ATTR((nonnull))  // Pointer parameters may not be NULL
#define DEPRECATED_FUNC GCC_ATTR((deprecated))  // Warn if this function is used
#define NO_RETURN_FUNC GCC_ATTR((noreturn))     // Function can never return
#define NO_INLINE_FUNC GCC_ATTR((noinline))  // Function must never be inlined

#define INLINE_PURE_FUNC ALWAYS_INLINE_FUNC PURE_FUNC
#define INLINE_CONST_FUNC ALWAYS_INLINE_FUNC CONST_FUNC

#if __has_extension(attribute_deprecated_with_message)
#define DEPRECATED_MSG(msg) __attribute__((deprecated(msg)))
#else
#define DEPRECATED_MSG(msg) DEPRECATED_FUNC
#endif

#if __clang__
#define DEPRECATED_METHOD(msg) DEPRECATED_MSG(msg)
#else
// GCC doesn't support attributes on Objective-C methods.
#define DEPRECATED_METHOD(msg)
#endif

#ifdef __GNUC__
#define EXPECT(x) __builtin_expect((x), 1)
#define EXPECT_NOT(x) __builtin_expect((x), 0)
#else
#define EXPECT(x) (x)
#define EXPECT_NOT(x) (x)
#endif

// OO_RETURNS_RETAINED: indicates the caller of a method owns a reference to the
// return value.
#if __has_feature(attribute_ns_returns_retained)
#define OO_RETURNS_RETAINED __attribute__((ns_returns_retained))
#else
#define OO_RETURNS_RETAINED
#endif

// OO_NS_CONSUMED: indicates that a reference to an object parameter is
// "consumed".
#ifndef OO_NS_CONSUMED
#if __has_feature(attribute_ns_consumed)
#define OO_NS_CONSUMED __attribute__((ns_consumed))
#else
#define OO_NS_CONSUMED
#endif
#endif

// OO_UNREACHABLE(): a statement that should never be executed (Clang
// optimization hint).
#if __has_feature(__builtin_unreachable)
#define OO_UNREACHABLE() __builtin_unreachable()
#else
#define OO_UNREACHABLE() \
  do {                   \
  } while (0)
#endif
