#ifndef js_config_h___
#define js_config_h___


#include "js-oolite-prefix.h"


#define XP_UNIX
#define XP_MACOSX

#define STATIC_JS_API



#ifdef DEBUG
// Debug flags.

// Support aggressive garbage collection (in Oolite, use the js-gc-zeal default, ranging from 0 to 2).
#define	JS_GC_ZEAL						1

// Thread safety required for API compatibility testing, not actually used.
// Defined in js-oolite-prefix.h because jslock uses it before including js-config.h.
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



#define JS_ALIGN_OF_POINTER		JS_BYTES_PER_WORD


#define HAVE_VA_LIST_AS_ARRAY			1
#define NSPR_LOCK						1


#ifndef NDEBUG
#define MOZ_TRACE_JSCALLS				1
#endif


#endif	// js_config_h___
