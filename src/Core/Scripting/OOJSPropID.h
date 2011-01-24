/*
	Temporary header to avoid pulling OOJavaScriptEngine.h into even more stuff.
	
	When OO_NEW_JS is removed, replace use of this header with jsapi.h, and
	OOJSPropID with jsid.
*/

#import <jsapi.h>


#ifndef OO_NEW_JS
#define OO_NEW_JS				0
#endif


#if OO_NEW_JS
typedef jsid OOJSPropID;
#else
typedef const char *OOJSPropID;
#endif
