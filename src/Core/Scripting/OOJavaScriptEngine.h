/*

OOJavaScriptEngine.h

JavaScript support for Oolite
Copyright (C) 2007-2010 David Taylor and Jens Ayton.

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


#import <Foundation/Foundation.h>
#import "Universe.h"
#import "PlayerEntity.h"
#import "PlayerEntityLegacyScriptEngine.h"
#import <jsapi.h>

#import "OOJSEngineTimeManagement.h"

#define OOJSENGINE_MONITOR_SUPPORT	(!defined(NDEBUG))


// TEMP: macro for update to trunk SpiderMonkey.
#ifndef OO_NEW_JS
#define OO_NEW_JS				0
#endif


@protocol OOJavaScriptEngineMonitor;


enum
{
	kOOJavaScriptEngineContextPoolCount = 5
};


@interface OOJavaScriptEngine: NSObject
{
	JSRuntime						*runtime;
	JSContext						*mainContext;
	JSContext						*contextPool[kOOJavaScriptEngineContextPoolCount];
	uint8_t							contextPoolCount;
	uint8_t							mainContextInUse;
	JSObject						*globalObject;
#if OOJSENGINE_MONITOR_SUPPORT
	id<OOJavaScriptEngineMonitor>	monitor;
#endif
}

+ (OOJavaScriptEngine *)sharedEngine;

- (JSObject *)globalObject;

- (void) runMissionCallback;

// The current context. NULL if nothing executing.
// - (JSContext *)context;

// Call a JS function, setting up new contexts as necessary. Caller is responsible for ensuring the jsval passed really is a function.
- (BOOL) callJSFunction:(jsval)function
			  forObject:(JSObject *)jsThis
				   argc:(uintN)argc
				   argv:(jsval *)argv
				 result:(jsval *)outResult;

// Get a context for doing something other than calling a function.
- (JSContext *)acquireContext;
- (void)releaseContext:(JSContext *)context;

- (void) removeGCObjectRoot:(JSObject **)rootPtr;
- (void) removeGCValueRoot:(jsval *)rootPtr;

@end


/*	Error and warning reporters.
	
	Note that after reporting an error in a JavaScript callback, the caller
	must return NO to signal an error.
*/
void OOReportJSError(JSContext *context, NSString *format, ...);
void OOReportJSErrorWithArguments(JSContext *context, NSString *format, va_list args);
void OOReportJSErrorForCaller(JSContext *context, NSString *scriptClass, NSString *function, NSString *format, ...);

void OOReportJSWarning(JSContext *context, NSString *format, ...);
void OOReportJSWarningWithArguments(JSContext *context, NSString *format, va_list args);
void OOReportJSWarningForCaller(JSContext *context, NSString *scriptClass, NSString *function, NSString *format, ...);

void OOReportJSBadPropertySelector(JSContext *context, NSString *className, jsint selector);
void OOReportJSBadArguments(JSContext *context, NSString *scriptClass, NSString *function, uintN argc, jsval *argv, NSString *message, NSString *expectedArgsDescription);

/*	OOSetJSWarningOrErrorStackSkip()
	
	Indicate that the direct call site is not relevant for error handler.
	Currently, if non-zero, no call site information is provided.
	Ideally, we'd stack crawl instead.
*/
void OOSetJSWarningOrErrorStackSkip(unsigned skip);


/*	NumberFromArgumentList()
	
	Get a single number from an argument list. The optional outConsumed
	argument can be used to find out how many parameters were used (currently,
	this will be 0 on failure, otherwise 1).
	
	On failure, it will return NO and raise an error. If the caller is a JS
	callback, it must return NO to signal an error.
*/
BOOL NumberFromArgumentList(JSContext *context, NSString *scriptClass, NSString *function, uintN argc, jsval *argv, double *outNumber, uintN *outConsumed);

/*	NumberFromArgumentListNoError()
	
	Like NumberFromArgumentList(), but does not report an error on failure.
*/
BOOL NumberFromArgumentListNoError(JSContext *context, uintN argc, jsval *argv, double *outNumber, uintN *outConsumed);


// Typed as int rather than BOOL to work with more general expressions such as bitfield tests.
OOINLINE jsval BOOLToJSVal(int b) INLINE_CONST_FUNC;
OOINLINE jsval BOOLToJSVal(int b)
{
	return BOOLEAN_TO_JSVAL(b != NO);
}


/*	JSFooNSBar()
	
	Wrappers to corresponding JS_FooBar()/JS_FooUCBar() functions, but taking
	an NSString. Additionally, a NULL context parameter may be used.
*/
BOOL JSGetNSProperty(JSContext *context, JSObject *object, NSString *name, jsval *value);
BOOL JSSetNSProperty(JSContext *context, JSObject *object, NSString *name, jsval *value);
BOOL JSDefineNSProperty(JSContext *context, JSObject *object, NSString *name, jsval value, JSPropertyOp getter, JSPropertyOp setter, uintN attrs);


@interface NSObject (OOJavaScript)

/*	-javaScriptValueInContext:
	
	Return the JavaScript object representation of an object. The default
	implementation returns JSVAL_VOID. At this time, NSString, NSNumber,
	NSArray, NSDictionary, NSNull, Entity, OOScript and OOJSTimer override this.
*/
- (jsval)javaScriptValueInContext:(JSContext *)context;

/*	-javaScriptDescription
	-javaScriptDescriptionWithClassName:
	-jsClassName
	
	See comments for -descriptionComponents in OOCocoa.h.
*/
- (NSString *)javaScriptDescription;
- (NSString *)javaScriptDescriptionWithClassName:(NSString *)className;
- (NSString *)jsClassName;

/*	oo_clearJSSelf:
	This is called by JSObjectWrapperFinalize() when a JS object wrapper is
	collected. The default implementation does nothing.
*/
- (void) oo_clearJSSelf:(JSObject *)selfVal;

@end


/*	OOJSValue: an object whose purpose in life is to hold a JavaScript value.
	This is somewhat useful for putting JavaScript objects in ObjC collections,
	for instance to pass as properties to script loaders. The value is
	GC rooted for the lifetime of the OOJSValue.
*/
@interface OOJSValue: NSObject
{
	jsval					_val;
}

+ (id) valueWithJSValue:(jsval)value inContext:(JSContext *)context;
+ (id) valueWithJSObject:(JSObject *)object inContext:(JSContext *)context;

- (id) initWithJSValue:(jsval)value inContext:(JSContext *)context;
- (id) initWithJSObject:(JSObject *)object inContext:(JSContext *)context;

@end


/*	JSObjectWrapperFinalize
	
	Finalizer for JS classes whose private storage is a retained object
	reference (generally an OOWeakReference, but doesn't have to be).
*/
void JSObjectWrapperFinalize(JSContext *context, JSObject *this);


@interface NSString (OOJavaScriptExtensions)

// Convert a JSString to an NSString.
+ (id)stringWithJavaScriptString:(JSString *)string;

// Convert an arbitrary JS object to an NSString, using JS_ValueToString.
+ (id) stringWithJavaScriptValue:(jsval)value inContext:(JSContext *)context;
+ (id)stringOrNilWithJavaScriptValue:(jsval)value inContext:(JSContext *)context;


// For diagnostic messages; produces things like @"(42, true, "a string", an object description)".
+ (id)stringWithJavaScriptParameters:(jsval *)params count:(uintN)count inContext:(JSContext *)context;

// Concatenate sequence of arbitrary JS objects into string.
+ (id)concatenationOfStringsFromJavaScriptValues:(jsval *)values count:(size_t)count separator:(NSString *)separator inContext:(JSContext *)context;

// Add escape codes for string so that it's a valid JavaScript literal (if you put "" or '' around it).
- (NSString *)escapedForJavaScriptLiteral;

@end


OOINLINE NSString *JSValToNSString(JSContext *context, jsval value)
{
	return [NSString stringOrNilWithJavaScriptValue:value inContext:context];
}


// OOEntityFilterPredicate wrapping a JavaScript function.
typedef struct
{
	JSContext				*context;
	jsval					function;	// Caller is responsible for ensuring this is a function object (using JS_ObjectIsFunction()).
	JSObject				*jsThis;
	BOOL					errorFlag;	// Set if a JS exception occurs. The
										// exception will have been reported.
										// This also supresses further filtering.
} JSFunctionPredicateParameter;
BOOL JSFunctionPredicate(Entity *entity, void *parameter);

// YES for ships and planets. Parameter: ignored.
BOOL JSEntityIsJavaScriptVisiblePredicate(Entity *entity, void *parameter);

// YES for ships other than sub-entities and menu-display ships, and planets other than atmospheres and menu miniatures. Parameter: ignored.
BOOL JSEntityIsJavaScriptSearchablePredicate(Entity *entity, void *parameter);


id JSValueToObject(JSContext *context, jsval value);
id JSObjectToObject(JSContext *context, JSObject *object);
id JSValueToObjectOfClass(JSContext *context, jsval value, Class requiredClass);
id JSObjectToObjectOfClass(JSContext *context, JSObject *object, Class requiredClass);

#define DEFINE_JS_OBJECT_GETTER(NAME, CLASS) \
OOINLINE BOOL NAME(JSContext *context, JSObject *inObject, CLASS **outObject) \
{ \
	if (EXPECT_NOT(outObject == NULL))  return NO; \
	*outObject = JSObjectToObjectOfClass(context, inObject, [CLASS class]); \
	return *outObject != nil; \
}


/*	Support for JSValueToObject()
	
	JSClassConverterCallback specifies the prototype for a callback function
	which converts a JavaScript object to an Objective-C object.
	
	JSBasicPrivateObjectConverter() is a JSClassConverterCallback which
	returns the JS object's private storage value. It automatically unpacks
	OOWeakReferences if relevant.
	
	JSRegisterObjectConverter() registers a callback for a specific JS class.
	It is not automatically propagated to subclasses.
*/
typedef id (*JSClassConverterCallback)(JSContext *context, JSObject *object);
id JSBasicPrivateObjectConverter(JSContext *context, JSObject *object);

void JSRegisterObjectConverter(JSClass *theClass, JSClassConverterCallback converter);


/*	JS root handling
	
	The name parameter to JS_AddNamed*Root is assigned with no overhead, not
	copied, but the strings serve no purpose in a release build so we may as
	well strip them out.
	
	In debug builds, this will deliberately cause an error if name is not a
	string literal.
*/
#ifdef NDEBUG
#define OOJS_AddGCValueRoot(context, root, name)	JS_AddValueRoot((context), (root))
#define OOJS_AddGCStringRoot(context, root, name)	JS_AddStringRoot((context), (root))
#define OOJS_AddGCObjectRoot(context, root, name)	JS_AddObjectRoot((context), (root))
#define OOJS_AddGCThingRoot(context, root, name)	JS_AddGCThingRoot((context), (root))
#else
#define OOJS_AddGCValueRoot(context, root, name)	JS_AddNamedValueRoot((context), (root), "" name)
#define OOJS_AddGCStringRoot(context, root, name)	JS_AddNamedStringRoot((context), (root), "" name)
#define OOJS_AddGCObjectRoot(context, root, name)	JS_AddNamedObjectRoot((context), (root), "" name)
#define OOJS_AddGCThingRoot(context, root, name)	JS_AddNamedGCThingRoot((context), (root), "" name)
#endif


#if OOJSENGINE_MONITOR_SUPPORT

/*	Protocol for debugging "monitor" object.
	The monitor is an object -- in Oolite, or via Distributed Objects -- which
	is provided with debugging information by the OOJavaScriptEngine.
	Currently, this is implemented in the Debug OXP.
*/

@protocol OOJavaScriptEngineMonitor <NSObject>

// Sent for JS errors or warnings.
- (oneway void)jsEngine:(in byref OOJavaScriptEngine *)engine
				context:(in JSContext *)context
				  error:(in JSErrorReport *)errorReport
			  stackSkip:(in unsigned)stackSkip
			withMessage:(in NSString *)message;

// Sent for JS log messages. Note: messageClass will be nil of Log() is used rather than LogWithClass().
- (oneway void)jsEngine:(in byref OOJavaScriptEngine *)engine
				context:(in JSContext *)context
			 logMessage:(in NSString *)message
				ofClass:(in NSString *)messageClass;

@end


@interface OOJavaScriptEngine (OOMonitorSupport)

- (void)setMonitor:(id<OOJavaScriptEngineMonitor>)monitor;

@end

#endif


/*
	Exception safety and profiling macros.
	
	Every JavaScript native callback that could concievably cause an
	Objective-C exception should begin with OOJS_NATIVE_ENTER() and end with
	OOJS_NATIVE_EXIT. Callbacks which have been carefully audited for potential
	exceptions, and support functions called from JavaScript native callbacks,
	may start with OOJS_PROFILE_ENTER and end with OOJS_PROFILE_EXIT to be
	included in profiling reports.
	
	Functions using either of these pairs _must_ return before
	OOJS_NATIVE_EXIT/OOJS_PROFILE_EXIT, or they will crash in OOJSUnreachable()
	in debug builds.
	
	For functions with a non-scalar return type, OOJS_PROFILE_EXIT should be
	replaced with OOJS_PROFILE_EXIT_VAL(returnValue). The returnValue is never
	used (and should be a constant expression), but is required to placate the
	compiler.
*/

#if OOLITE_NATIVE_EXCEPTIONS

#if OOJS_PROFILE

#define OOJS_PROFILE_ENTER \
	{ \
		OOJS_DECLARE_PROFILE_STACK_FRAME(oojsProfilerStackFrame) \
		@try { \
			OOJSProfileEnter(&oojsProfilerStackFrame, __PRETTY_FUNCTION__);

	#define OOJS_PROFILE_EXIT_VAL(rval) \
		} @finally { \
			OOJSProfileExit(&oojsProfilerStackFrame); \
		} \
		OO_UNREACHABLE(); \
		OOJSUnreachable(__PRETTY_FUNCTION__, __FILE__, __LINE__); \
		return rval; \
	}
#define OOJS_PROFILE_EXIT_VOID return; OOJS_PROFILE_EXIT_VAL()

#define OOJS_PROFILE_ENTER_FOR_NATIVE OOJS_PROFILE_ENTER

#else

#define OOJS_PROFILE_ENTER			{
#define OOJS_PROFILE_EXIT_VAL(rval)	} return (rval);
#define OOJS_PROFILE_EXIT_VOID		} return;
#define OOJS_PROFILE_ENTER_FOR_NATIVE @try {

#endif	// OOJS_PROFILE

#define OOJS_NATIVE_ENTER(cx) \
	{ \
		JSContext *oojsNativeContext = (cx); \
		OOJS_PROFILE_ENTER_FOR_NATIVE

#define OOJS_NATIVE_EXIT \
		} @catch(id exception) { \
			OOJSReportWrappedException(oojsNativeContext, exception); \
			return NO; \
		OOJS_PROFILE_EXIT_VAL(NO) \
	}


void OOJSReportWrappedException(JSContext *context, id exception);

#ifndef NDEBUG
void OOJSUnreachable(const char *function, const char *file, unsigned line)  NO_RETURN_FUNC;
#else
#define OOJSUnreachable(function, line) do {} while (0)
#endif

#else	// OOLITE_NATIVE_EXCEPTIONS

// These introduce a scope to ensure proper nesting.
#define OOJS_PROFILE_ENTER			{
#define OOJS_PROFILE_EXIT_VAL(rval)	} return (rval);
#define OOJS_PROFILE_EXIT_VOID		} return;

#define OOJS_NATIVE_ENTER(cx)	OOJS_PROFILE_ENTER
#define OOJS_NATIVE_EXIT	OOJS_PROFILE_EXIT_VAL(NO)

#endif	// OOLITE_NATIVE_EXCEPTIONS


#define OOJS_PROFILE_EXIT		OOJS_PROFILE_EXIT_VAL(0)
#define OOJS_PROFILE_EXIT_JSVAL	OOJS_PROFILE_EXIT_VAL(JSVAL_VOID)



/*	OOJSDumpStack()
	
	Write JavaScript stack to log.
*/
#ifndef NDEBUG
void OOJSDumpStack(NSString *logMessageClass, JSContext *context);
#else
#define OOJSDumpStack(lmc, cx)  do {} while (0)
#endif



/***** Helpers to write callbacks and abstract API changes. *****/

#if OO_NEW_JS
// Native callback conventions have changed.
#define OOJS_NATIVE_ARGS				JSContext *context, uintN argc, jsval *vp
#define OOJS_NATIVE_CALLTHROUGH			context, argc, vp
#define OOJS_CALLEE						JS_CALLEE(context, vp)
#define OOJS_THIS_VAL					JS_THIS(context, vp)
#define OOJS_THIS						JS_THIS_OBJECT(context, vp)
#define OOJS_ARGV						JS_ARGV(context, vp)
#define OOJS_RVAL						JS_RVAL(context, vp)
#define OOJS_SET_RVAL(v)				JS_SET_RVAL(context, vp, v)

#define OOJS_IS_CONSTRUCTING			JS_IsConstructing(context, vp)

#define OOJS_RETURN_VECTOR(value)		do { jsval jsresult; BOOL OK = VectorToJSValue(context, value, &jsresult); JS_SET_RVAL(context, vp, jsresult); return OK; } while (0)
#define OOJS_RETURN_QUATERNION(value)	do { jsval jsresult; BOOL OK = QuaternionToJSValue(context, value, &jsresult); JS_SET_RVAL(context, vp, jsresult); return OK; } while (0)
#define OOJS_RETURN_DOUBLE(value)		do { JS_SET_RVAL(context, vp, DOUBLE_TO_JSVAL(value)); return YES; } while (0)

#define OOJS_PROP_ARGS					JSContext *context, JSObject *this, jsid propID, jsval *value
#define OOJS_PROPID_IS_INT				JSID_IS_INT(propID)
#define OOJS_PROPID_INT					JSID_TO_INT(propID)
#define OOJS_PROPID_IS_STRING			JSID_IS_STRING(propID)
#define OOJS_PROPID_STRING				JSID_TO_STRING(propID)

#else
#define OOJS_NATIVE_ARGS				JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult
#define OOJS_NATIVE_CALLTHROUGH			context, this, argc, argv, outResult
#define OOJS_CALLEE						argv[-2]
#define OOJS_THIS_VAL					OBJECT_TO_JSVAL(this)
#define OOJS_THIS						this
#define OOJS_ARGV						argv
#define OOJS_RVAL						(*outResult)
#define OOJS_SET_RVAL(v)				do { *outResult = (v); } while (0)

#define OOJS_IS_CONSTRUCTING			JS_IsConstructing(context)

#define OOJS_RETURN_VECTOR(value)		do { return VectorToJSValue(context, value, outResult); } while (0)
#define OOJS_RETURN_QUATERNION(value)	do { return QuaternionToJSValue(context, value, outResult); } while (0)
#define OOJS_RETURN_DOUBLE(value)		do { return JS_NewDoubleValue(context, result, outResult); } while (0)

#define OOJS_PROP_ARGS					JSContext *context, JSObject *this, jsval propID, jsval *value
#define OOJS_PROPID_IS_INT				JSVAL_IS_INT(propID)
#define OOJS_PROPID_INT					JSVAL_TO_INT(propID)
#define OOJS_PROPID_IS_STRING			JSVAL_IS_STRING(propID)
#define OOJS_PROPID_STRING				JSVAL_TO_STRING(propID)
#endif

#define OOJS_ARG(n)						(OOJS_ARGV[(n)])
#define OOJS_RETURN_VOID				do { OOJS_SET_RVAL(JSVAL_VOID); return YES; } while (0)
#define OOJS_RETURN_BOOL(v)				do { OOJS_SET_RVAL(BOOLToJSVal(v)); return YES; } while (0)
#define OOJS_RETURN_INT(v)				do { OOJS_SET_RVAL(INT_TO_JSVAL(v)); return YES; } while (0)
#define OOJS_RETURN_OBJECT(o)			do { id o_ = (o); OOJS_SET_RVAL(o_ ? [o_ javaScriptValueInContext:context] : JSVAL_NULL); return YES; } while (0)




/*	JSObjectWrapperToString
	
	Implementation of toString() for JS classes whose private storage is an
	Objective-C object reference (generally an OOWeakReference).
	
	Calls -javaScriptDescription and, if that fails, -description.
*/
JSBool JSObjectWrapperToString(OOJS_NATIVE_ARGS);





/***** Transitional compatibility stuff - remove when switching to OO_NEW_JS permanently. *****/

static inline JSClass * OOJS_GetClass(JSContext *cx, JSObject *obj)
{
#if JS_THREADSAFE
	return JS_GetClass(cx, obj);
#else
	return JS_GetClass(obj);
#endif
}


#if OO_NEW_JS
// Before removing, switch to JSVAL_TO_DOUBLE() everywhere.
static inline JSBool JS_NewDoubleValue(JSContext *cx, jsdouble d, jsval *rval)
{
	NSCParameterAssert(rval != NULL);
	*rval = DOUBLE_TO_JSVAL(d);
	return YES;
}

#define OOJSVAL_TO_DOUBLE JSVAL_TO_DOUBLE
#else
// In old API, jsvals could be pointers to doubles; in new, they're actual doubles.
#define OOJSVAL_TO_DOUBLE(val) (*JSVAL_TO_DOUBLE(val))
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

#endif
