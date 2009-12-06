#if __LP64__
	/*	HACK: Spidermonkey and Security.framework (included indirectly) define
		uint64 in conflicting ways. To work around this, we pre-include
		Spidermonkey's definition, and set a macro to stop Security.framework
		from defining it. The Spidermonkey definition won't work with
		Security.framework, but that's OK since we don't use
		Security.framework.
		-- Ahruman 2009-09-03
	*/
	
	#include <jstypes.h>
	#define _UINT64
#endif
