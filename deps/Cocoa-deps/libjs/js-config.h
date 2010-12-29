#ifndef js_config_h___
#define js_config_h___


#define XP_UNIX
#define XP_MACOSX

#define STATIC_JS_API



#ifdef DEBUG
// Debug flags.

// Support aggressive garbage collection (in Oolite, use the js-gc-zeal default, ranging from 0 to 2).
#define	JS_GC_ZEAL						1

// Thread safety required for API compatibility testing, not actually used.
// FIXME: TEMPORARILY OFF WHILE SETTING UP XCODE PROJECT
// #define	JS_THREADSAFE				1
#else
// Non-debug flags.
#define JS_NO_JSVAL_JSID_STRUCT_TYPES	1
#endif



// Don't implement CTypes (foreign function interface for XUL chrome).
#undef	JS_HAS_CTYPES

#define	JS_HAVE_STDINT_H				1
#undef	JS_SYS_TYPES_H_DEFINES_EXACT_SIZE_TYPES
#undef	JS_HAVE___INTN

#if __ppc__ || __i386__
#define JS_BYTES_PER_WORD				4
#define JS_BITS_PER_WORD_LOG2			5
#elif __ppc64__ || __x86_64__
#define JS_BYTES_PER_WORD				8
#define JS_BITS_PER_WORD_LOG2			6
#else
#error Unknown platform.
#endif

#define JS_ALIGN_OF_POINTER		JS_BYTES_PER_WORD

// TraceMonkey, YARR JIT and JaegerMonkey, aka the Go Faster Switches.
// FIXME: TEMPORARILY OFF WHILE SETTING UP XCODE PROJECT
//#define	JS_TRACER					1
//#define	JS_METHODJIT				1
//#define	ENABLE_YARR_JIT				1



#define HAVE_VA_LIST_AS_ARRAY			1
#define JS_HAS_NATIVE_COMPARE_AND_SWAP	1
#define NSPR_LOCK						1


#endif	// js_config_h___
