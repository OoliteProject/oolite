#ifndef INCLUDED_JS_OOLITE_PREFIX_h
#define INCLUDED_JS_OOLITE_PREFIX_h

/*
	A bunch of stuff is defined in a prefix header because there's no common
	header file. Some files look at macros before including js-config.h, some
	don't include it at all.
	
	Some of it also has to be seen by client (Oolite) code, so this is
	included from js-config.h as well.
*/

#define __STDC_LIMIT_MACROS				1

#ifdef DEBUG
// Thread safety required for API compatibility testing, not actually used.
#define	JS_THREADSAFE					1
#endif

// TraceMonkey, JaegerMonkey, and YARR (regexp) JIT, aka the Go Faster Switches.
#define	JS_TRACER						1
#define	JS_METHODJIT					1
#define	ENABLE_YARR_JIT					1


#if JS_TRACER || JS_METHODJIT
#define	FEATURE_NANOJIT					1
#endif

#if JS_METHODJIT
#define JS_MONOIC						1
#define JS_POLYIC						1
#endif


#if __i386__
#define JS_BYTES_PER_WORD				4
#define JS_BITS_PER_WORD_LOG2			5
#define AVMPLUS_IA32					1
#define JS_CPU_X86						1
#define JS_NUNBOX32						1
#define WTF_CPU_X86						1
#elif __x86_64__
#define JS_BYTES_PER_WORD				8
#define JS_BITS_PER_WORD_LOG2			6
#define AVMPLUS_64BIT					1
#define AVMPLUS_AMD64					1
#define JS_CPU_X64						1
#define JS_PUNBOX64						1
#define WTF_CPU_X86_64					1
#else
#error Unknown platform.
#endif


#define AVMPLUS_UNIX					1
#define AVMPLUS_MAC						1


#if !AVMPLUS_64BIT
/*
	Nanojit on 32-bit Mac platforms requires MakeDataExecutable(), which is
	declared in CoreServices, but if we include that we get AssertMacros.h
	which includes a "check()" macro that breaks the build.
*/
#if __cplusplus
extern "C" void MakeDataExecutable(void *baseAddress, unsigned long length);
#endif
#endif


#endif	// INCLUDED_JS_OOLITE_PREFIX_h
