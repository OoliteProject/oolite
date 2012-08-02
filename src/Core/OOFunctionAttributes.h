#ifndef INCLUDED_OOFUNCTIONATTRIBUTES_h
#define INCLUDED_OOFUNCTIONATTRIBUTES_h


#ifndef GCC_ATTR
	#ifdef __GNUC__
		#define GCC_ATTR(x)	__attribute__(x)
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


#if __cplusplus
#define OOINLINE			inline
#else
#define OOINLINE			static inline
#endif


#if !OO_DEBUG
#define ALWAYS_INLINE_FUNC	GCC_ATTR((always_inline))	// Force inlining of function
#else
#define ALWAYS_INLINE_FUNC								// Don't force inlining of function (because gdb is silly)
#endif

#define PURE_FUNC			GCC_ATTR((pure))			// result dependent only on params and globals
#define CONST_FUNC			GCC_ATTR((const))			// pure + no pointer dereferences or globals
#define NONNULL_FUNC		GCC_ATTR((nonnull))			// Pointer parameters may not be NULL
#define DEPRECATED_FUNC		GCC_ATTR((deprecated))		// Warn if this function is used
#define NO_RETURN_FUNC		GCC_ATTR((noreturn))		// Function can never return

#define INLINE_PURE_FUNC	ALWAYS_INLINE_FUNC PURE_FUNC
#define INLINE_CONST_FUNC	ALWAYS_INLINE_FUNC CONST_FUNC


#if __has_extension(attribute_deprecated_with_message)
#define DEPRECATED_MSG(msg)	__attribute__((deprecated(msg)))
#else
#define DEPRECATED_MSG(msg)	DEPRECATED_FUNC
#endif


#ifdef __GNUC__
	#define EXPECT(x)		__builtin_expect((x), 1)
	#define EXPECT_NOT(x)	__builtin_expect((x), 0)
#else
	#define EXPECT(x)		(x)
	#define EXPECT_NOT(x)	(x)
#endif


// OO_RETURNS_RETAINED: indicates the caller of a method owns a reference to the return value.
#if __has_feature(attribute_ns_returns_retained)
	#define OO_RETURNS_RETAINED __attribute__((ns_returns_retained))
#else
	#define OO_RETURNS_RETAINED
#endif

// OO_NS_CONSUMED: indicates that a reference to an object parameter is "consumed".
#ifndef OO_NS_CONSUMED
#if __has_feature(attribute_ns_consumed)
#define OO_NS_CONSUMED __attribute__((ns_consumed))
#else
#define OO_NS_CONSUMED
#endif
#endif

// OO_UNREACHABLE(): a statement that should never be executed (Clang optimization hint).
#if __has_feature(__builtin_unreachable)
	#define OO_UNREACHABLE() __builtin_unreachable()
#else
	#define OO_UNREACHABLE() do {} while (0)
#endif


/*
	OO_TAKES_FORMAT_STRING(stringIndex, firstToCheck): marks a function that
	applies [NSString stringWithFormat:]-type formatting to arguments.
	
	According to the fine manuals, mainline GCC supports basic checking of
	NSString format strings since 4.6, but doesn't validate the arguments.
*/
#if __has_attribute(format) || (defined(OOLITE_GCC_VERSION) && OOLITE_GCC_VERSION >= 40600)
	#define OO_TAKES_FORMAT_STRING(stringIndex, firstToCheck) __attribute__((format(NSString, stringIndex, firstToCheck)))
#else
	#define OO_TAKES_FORMAT_STRING(stringIndex, firstToCheck)
#endif


#if __OBJC__
/*	OOConsumeReference()
	Decrements the Clang Static Analyzer's notion of an object's reference
	count. This is used to work around cases where the analyzer claims an
	object is being leaked but it actually isn't, due to a pattern the
	analyzer doesn't understand (like singletons, or references being stored
	in JavaScript objects' private field).
	Do not use this blindly. If you aren't absolutely certain it's appropriate,
	don't use it.
	-- Ahruman 2011-01-28
*/
#if NDEBUG
OOINLINE id OOConsumeReference(id OO_NS_CONSUMED value) ALWAYS_INLINE_FUNC;
OOINLINE id OOConsumeReference(id OO_NS_CONSUMED value)
{
	return value;
}
#else
// Externed to work around analyzer being too "clever" and ignoring attributes
// when it's inlined.
id OOConsumeReference(id OO_NS_CONSUMED value);
#endif
#endif

#endif	/* INCLUDED_OOFUNCTIONATTRIBUTES_h */
