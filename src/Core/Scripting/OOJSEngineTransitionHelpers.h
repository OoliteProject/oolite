/*

OOJSEngineTransitionHelpers.h
(Included by OOJavaScriptEngine.h)

Macros and inlines to help transition from SpiderMonkey 1.7 to
SpiderMonkey 1.8.5/1.9/whatever.


JavaScript support for Oolite
Copyright (C) 2007-2011 David Taylor and Jens Ayton.

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
MA 02110-1301, USA.

*/


#if !JS_THREADSAFE
#define JS_IsInRequest(context)  (((void)(context)), YES)
#endif


/***** Transitional compatibility stuff - remove when switching to OO_NEW_JS permanently. *****/


#if OO_NEW_JS
// Before removing, switch to DOUBLE_TOJSVAL() everywhere.
OOINLINE JSBool JS_NewDoubleValue(JSContext *cx, jsdouble d, jsval *rval)
{
	NSCParameterAssert(rval != NULL);
	*rval = DOUBLE_TO_JSVAL(d);
	return YES;
}


/*	HACK: JSAPI headers have no useful versioning information, and FF4.0b9
	changed some key string functions. It also added the macro
	JS_WARN_UNUSED_RESULT, so we use that for feature detection temporarily.
*/
#define OOJS_FF4B9	defined(JS_WARN_UNUSED_RESULT)


OOINLINE const jschar *OOJSGetStringCharsAndLength(JSContext *context, JSString *string, size_t *length)
{
	NSCParameterAssert(context != NULL && string != NULL && length != NULL);
	
#if OOJS_FF4B9
	// FireFox 4b9
	return JS_GetStringCharsAndLength(context, string, length);
#else
	// FireFox 4b8
	return JS_GetStringCharsAndLength(string, length);
#endif
}

#define OOJSVAL_TO_DOUBLE JSVAL_TO_DOUBLE


#define OOJSGetMethod		JS_GetMethodById
#define OOJSGetProperty		JS_GetPropertyById
#define OOJSSetProperty		JS_SetPropertyById
#define OOJSDefineProperty	JS_DefinePropertyById

#else	// !OO_NEW_JS

// In old API, jsvals could be pointers to doubles; in new, they're actual doubles.
#define OOJSVAL_TO_DOUBLE(val) (*JSVAL_TO_DOUBLE(val))

#define JS_GetGCParameter(...) (0)


OOINLINE const jschar *OOJSGetStringCharsAndLength(JSContext *context, JSString *string, size_t *length)
{
	NSCParameterAssert(context != NULL && string != NULL && length != NULL);
	
	*length = JS_GetStringLength(string);
	return JS_GetStringChars(string);
}

#define OOJS_FF4B9 0


#define OOJSGetMethod		JS_GetMethod
#define OOJSGetProperty		JS_GetProperty
#define OOJSSetProperty		JS_SetProperty
#define OOJSDefineProperty	JS_DefineProperty

#endif


#if OOJS_FF4B9
#define OOJSCompareStrings JS_CompareStrings
#else
static inline JSBool OOJSCompareStrings(JSContext *context, JSString *str1, JSString *str2, int32 *result)
{
	NSCParameterAssert(context != NULL && JS_IsInRequest(context) && result != NULL);
	*result = JS_CompareStrings(str1, str2);
	return YES;
}
#endif



#ifndef OO_NEW_JS
#warning The following compatibility stuff can be removed when OO_NEW_JS is.
#endif

#ifndef JS_TYPED_ROOTING_API
/*
	Compatibility functions to map new JS GC entry points to old ones.
	At the time of writing, the new versions in trunk SpiderMonkey all map
	to the same thing behind the scenes, they're just type-safe wrappers.
*/
static inline JSBool JS_AddValueRoot(JSContext *cx, jsval *vp) { return JS_AddRoot(cx, vp); }
static inline JSBool JS_AddStringRoot(JSContext *cx, JSString **rp) { return JS_AddRoot(cx, rp); }
static inline JSBool JS_AddObjectRoot(JSContext *cx, JSObject **rp) { return JS_AddRoot(cx, rp); }
static inline JSBool JS_AddGCThingRoot(JSContext *cx, void **rp) { return JS_AddRoot(cx, rp); }

static inline JSBool JS_AddNamedValueRoot(JSContext *cx, jsval *vp, const char *name) { return JS_AddNamedRoot(cx, vp, name); }
static inline JSBool JS_AddNamedStringRoot(JSContext *cx, JSString **rp, const char *name) { return JS_AddNamedRoot(cx, rp, name); }
static inline JSBool JS_AddNamedObjectRoot(JSContext *cx, JSObject **rp, const char *name) { return JS_AddNamedRoot(cx, rp, name); }
static inline JSBool JS_AddNamedGCThingRoot(JSContext *cx, void **rp, const char *name) { return JS_AddNamedRoot(cx, rp, name); }

static inline void JS_RemoveValueRoot(JSContext *cx, jsval *vp) { JS_RemoveRoot(cx, vp); }
static inline void JS_RemoveStringRoot(JSContext *cx, JSString **rp) { JS_RemoveRoot(cx, rp); }
static inline void JS_RemoveObjectRoot(JSContext *cx, JSObject **rp) { JS_RemoveRoot(cx, rp); }
static inline void JS_RemoveGCThingRoot(JSContext *cx, void **rp) { JS_RemoveRoot(cx, rp); }

#define JS_BeginRequest(cx)  do {} while (0)
#define JS_EndRequest(cx)  do {} while (0)

#endif




/***** Helpers to write callbacks and abstract API changes. *****/

#if OO_NEW_JS

// Native callback conventions have changed.
#define OOJS_NATIVE_CALLTHROUGH				context, argc, vp
#define OOJS_CALLEE							JS_CALLEE(context, vp)
#define OOJS_THIS_VAL						JS_THIS(context, vp)
#define OOJS_THIS							JS_THIS_OBJECT(context, vp)
#define OOJS_ARGV							JS_ARGV(context, vp)
#define OOJS_RVAL							JS_RVAL(context, vp)
#define OOJS_SET_RVAL(v)					JS_SET_RVAL(context, vp, v)

#define OOJS_IS_CONSTRUCTING				JS_IsConstructing(context, vp)
#define OOJS_CASTABLE_CONSTRUCTOR_CREATE	1

#define OOJS_PROP_ARGS						JSContext *context, JSObject *this, jsid propID, jsval *value
#define OOJS_PROPID_IS_INT					JSID_IS_INT(propID)
#define OOJS_PROPID_INT						JSID_TO_INT(propID)
#define OOJS_PROPID_IS_STRING				JSID_IS_STRING(propID)
#define OOJS_PROPID_STRING					JSID_TO_STRING(propID)

#else	// !OO_NEW_JS

#define OOJS_NATIVE_CALLTHROUGH				context, this_, argc, argv_, outResult
#define OOJS_CALLEE							argv_[-2]
#define OOJS_THIS_VAL						OBJECT_TO_JSVAL(this_)
#define OOJS_THIS							this_
#define OOJS_ARGV							argv_
#define OOJS_RVAL							(*outResult)
#define OOJS_SET_RVAL(v)					do { *outResult = (v); } while (0)

#define OOJS_IS_CONSTRUCTING				JS_IsConstructing(context)
#define OOJS_CASTABLE_CONSTRUCTOR_CREATE	(!OOJS_IS_CONSTRUCTING)

#define OOJS_PROP_ARGS						JSContext *context, JSObject *this, jsval propID, jsval *value
#define OOJS_PROPID_IS_INT					JSVAL_IS_INT(propID)
#define OOJS_PROPID_INT						JSVAL_TO_INT(propID)
#define OOJS_PROPID_IS_STRING				JSVAL_IS_STRING(propID)
#define OOJS_PROPID_STRING					JSVAL_TO_STRING(propID)

#endif

#define OOJS_ARG(n)						(OOJS_ARGV[(n)])




/***** Debug API *****
	These are only defined if jsdbgapi.h is included before OOJavaScriptEngine.h.
*/

#ifdef jsdbgapi_h___

#if OO_NEW_JS
static inline JSBool OOJS_GetFrameThis(JSContext *cx, JSStackFrame *fp, jsval *thisp)
{
	return JS_GetFrameThis(cx, fp, thisp);
}
#else
static inline JSBool OOJS_GetFrameThis(JSContext *cx, JSStackFrame *fp, jsval *thisp)
{
	JSObject *thiso = JS_GetFrameThis(cx, fp);
	if (thiso != NULL)
	{
		*thisp = OBJECT_TO_JSVAL(thiso);
		return YES;
	}
	else
	{
		return false;
	}
	
}
#endif

#endif
