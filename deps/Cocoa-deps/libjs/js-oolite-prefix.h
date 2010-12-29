#define	ENABLE_YARR_JIT					0
#define __STDC_LIMIT_MACROS				1

#ifdef DEBUG
// Thread safety required for API compatibility testing, not actually used.
#define	JS_THREADSAFE					1
#endif
