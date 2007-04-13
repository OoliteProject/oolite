#ifndef INCLUDED_OOFUNCTIONATTRIBUTES_h
#define INCLUDED_OOFUNCTIONATTRIBUTES_h


#ifndef GCC_ATTR
	#ifdef __GNUC__
		#define GCC_ATTR(x)	__attribute__(x)
	#else
		#define GCC_ATTR(x)
	#endif
#endif


#define OOINLINE			static inline


#define PURE_FUNC			GCC_ATTR((pure))			// result dependent only on params and globals
#define CONST_FUNC			GCC_ATTR((const))			// pure + no pointer dereferences or globals
#define NONNULL_FUNC		GCC_ATTR((nonnull))			// Pointer parameters may not be NULL
#define ALWAYS_INLINE_FUNC	GCC_ATTR((always_inline))	// Force inlining of function
#define DEPRECATED_FUNC		GCC_ATTR((deprecated))		// Warn if this function is used
#define NO_RETURN_FUNC		GCC_ATTR((noreturn))		// Function can never return

#define INLINE_PURE_FUNC	ALWAYS_INLINE_FUNC PURE_FUNC
#define INLINE_CONST_FUNC	ALWAYS_INLINE_FUNC CONST_FUNC


#ifdef __GNUC__
	#define EXPECT(x)		__builtin_expect((x), 1)
	#define EXPECT_NOT(x)	__builtin_expect((x), 0)
#else
	#define EXPECT(x)		(x)
	#define EXPECT_NOT(x)	(x)
#endif


#endif	/* INCLUDED_OOFUNCTIONATTRIBUTES_h */
