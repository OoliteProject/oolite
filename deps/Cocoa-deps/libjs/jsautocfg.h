#ifndef js_cpucfg___
#define js_cpucfg___

/* MANUALLY GENERATED - DO EDIT. IF YOU ACTUALLY NEED TO. */

#if __LITTLE_ENDIAN__
#define	IS_LITTLE_ENDIAN			1
#undef	IS_BIG_ENDIAN
#elif __BIG_ENDIAN__
#define	IS_BIG_ENDIAN				1
#undef	IS_LITTLE_ENDIAN
#else
#error Unknown platform endianness.
#undef	IS_BIG_ENDIAN
#undef	IS_LITTLE_ENDIAN
#endif

#define	JS_STACK_GROWTH_DIRECTION	(-1)

#endif	// js_cpucfg___

