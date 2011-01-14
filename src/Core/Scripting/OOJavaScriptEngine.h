/*

OOJavaScriptEngine.h

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
@private
	JSRuntime						*runtime;
	JSContext						*mainContext;
	JSContext						*contextPool[kOOJavaScriptEngineContextPoolCount];
	uint8_t							contextPoolCount;
	uint8_t							mainContextInUse;
	JSObject						*globalObject;
	BOOL							_showErrorLocations;
#ifndef NDEBUG
	BOOL							_dumpStackForErrors;
	BOOL							_dumpStackForWarnings;
#endif
#if OOJSENGINE_MONITOR_SUPPORT
	id<OOJavaScriptEngineMonitor>	monitor;
#endif
}

+ (OOJavaScriptEngine *) sharedEngine;

- (JSObject *) globalObject;

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

- (void) garbageCollectionOpportunity;

- (BOOL) showErrorLocations;
- (void) setShowErrorLocations:(BOOL)value;

#ifndef NDEBUG
- (BOOL) dumpStackForErrors;
- (void) setDumpStackForErrors:(BOOL)value;

- (BOOL) dumpStackForWarnings;
- (void) setDumpStackForWarnings:(BOOL)value;

// Install handler for JS "debugger" statment.
- (void) enableDebuggerStatement;
#endif

@end


/*	Error and warning reporters.
	
	Note that after reporting an error in a JavaScript callback, the caller
	must return NO to signal an error.
*/
void OOJSReportError(JSContext *context, NSString *format, ...);
void OOJSReportErrorWithArguments(JSContext *context, NSString *format, va_list args);
void OOJSReportErrorForCaller(JSContext *context, NSString *scriptClass, NSString *function, NSString *format, ...);

void OOJSReportWarning(JSContext *context, NSString *format, ...);
void OOJSReportWarningWithArguments(JSContext *context, NSString *format, va_list args);
void OOJSReportWarningForCaller(JSContext *context, NSString *scriptClass, NSString *function, NSString *format, ...);

void OOJSReportBadPropertySelector(JSContext *context, NSString *className, jsint selector);
void OOJSReportBadArguments(JSContext *context, NSString *scriptClass, NSString *function, uintN argc, jsval *argv, NSString *message, NSString *expectedArgsDescription);

/*	OOJSSetWarningOrErrorStackSkip()
	
	Indicate that the direct call site is not relevant for error handler.
	Currently, if non-zero, no call site information is provided.
	Ideally, we'd stack crawl instead.
*/
void OOJSSetWarningOrErrorStackSkip(unsigned skip);


/*	OOJSArgumentListGetNumber()
	
	Get a single number from an argument list. The optional outConsumed
	argument can be used to find out how many parameters were used (currently,
	this will be 0 on failure, otherwise 1).
	
	On failure, it will return NO and raise an error. If the caller is a JS
	callback, it must return NO to signal an error.
*/
BOOL OOJSArgumentListGetNumber(JSContext *context, NSString *scriptClass, NSString *function, uintN argc, jsval *argv, double *outNumber, uintN *outConsumed);

/*	OOJSArgumentListGetNumberNoError()
	
	Like OOJSArgumentListGetNumber(), but does not report an error on failure.
*/
BOOL OOJSArgumentListGetNumberNoError(JSContext *context, uintN argc, jsval *argv, double *outNumber, uintN *outConsumed);


// Typed as int rather than BOOL to work with more general expressions such as bitfield tests.
OOINLINE jsval OOJSValueFromBOOL(int b) INLINE_CONST_FUNC;
OOINLINE jsval OOJSValueFromBOOL(int b)
{
	return BOOLEAN_TO_JSVAL(b != NO);
}


/*	OOJSFooProperty()
	
	Wrappers to corresponding JS_FooProperty()/JS_FooUCProperty() functions,
	but taking an NSString.
	
	Require a request on context.
*/
BOOL OOJSGetProperty(JSContext *context, JSObject *object, NSString *name, jsval *value);
BOOL OOJSSetProperty(JSContext *context, JSObject *object, NSString *name, jsval *value);
BOOL OOJSDefineProperty(JSContext *context, JSObject *object, NSString *name, jsval value, JSPropertyOp getter, JSPropertyOp setter, uintN attrs);


@interface NSObject (OOJavaScript)

/*	-oo_jsValueInContext:
	
	Return the JavaScript value representation of an object. The default
	implementation returns JSVAL_VOID.
	Note that sending this to nil does not return JSVAL_NULL. For that
	behaviour, use OOJSValueFromNativeObject() below.
	
	Requires a request on context.
*/
- (jsval) oo_jsValueInContext:(JSContext *)context;

/*	-oo_jsDescription
	-oo_jsDescriptionWithClassName:
	-oo_jsClassName
	
	See comments for -descriptionComponents in OOCocoa.h.
*/
- (NSString *) oo_jsDescription;
- (NSString *) oo_jsDescriptionWithClassName:(NSString *)className;
- (NSString *) oo_jsClassName;

/*	oo_clearJSSelf:
	This is called by OOJSObjectWrapperFinalize() when a JS object wrapper is
	collected. The default implementation does nothing.
*/
- (void) oo_clearJSSelf:(JSObject *)selfVal;

@end


/*	OOJSValueFromNativeObject()
	Return a JavaScript value representation of an object, or null if passed
	nil.
	
	Requires a request on context.
*/
OOINLINE jsval OOJSValueFromNativeObject(JSContext *context, id object)
{
	if (object != nil)  return [object oo_jsValueInContext:context];
	return  JSVAL_NULL;
}


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



/**** String utilities ****/

// Convert a JSString to an NSString.
NSString *OOStringFromJSString(JSContext *context, JSString *string);

/*	Convert an arbitrary JS object to an NSString, calling JS_ValueToString.
	OOStringFromJSValue() returns nil if value is null or undefined,
	OOStringFromJSValueEvenIfNull() returns "null" or "undefined".
*/
NSString *OOStringFromJSValue(JSContext *context, jsval value);
NSString *OOStringFromJSValueEvenIfNull(JSContext *context, jsval value);


/*	Describe a value for various debuggy purposes. Strings are quoted, escaped
	and limited in length. Functions are described as "function foo" (or just
	"function" if they're anonymous).
*/
NSString *OOJSDebugDescribe(JSContext *context, jsval value);


@interface NSString (OOJavaScriptExtensions)

// For diagnostic messages; produces things like @"(42, true, "a string", an object description)".
+ (id) stringWithJavaScriptParameters:(jsval *)params count:(uintN)count inContext:(JSContext *)context;

// Concatenate sequence of arbitrary JS objects into string.
+ (id) concatenationOfStringsFromJavaScriptValues:(jsval *)values count:(size_t)count separator:(NSString *)separator inContext:(JSContext *)context;

// Add escape codes for string so that it's a valid JavaScript literal (if you put "" or '' around it).
- (NSString *) escapedForJavaScriptLiteral;


// Wrapper for OOStringFromJSValueEvenIfNull(). DEPRECATED
+ (id) stringWithJavaScriptValue:(jsval)value inContext:(JSContext *)context;

// Wrapper for OOStringFromJSValue(). DEPRECATED
+ (id) stringOrNilWithJavaScriptValue:(jsval)value inContext:(JSContext *)context;

@end


// OOEntityFilterPredicate wrapping a JavaScript function.
typedef struct
{
	JSContext				*context;
	jsval					function;	// Caller is responsible for ensuring this is a function object (using OOJSValueIsFunction()).
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


// These require a request on context.
id OOJSNativeObjectFromJSValue(JSContext *context, jsval value);
id OOJSNativeObjectFromJSObject(JSContext *context, JSObject *object);
id OOJSNativeObjectOfClassFromJSValue(JSContext *context, jsval value, Class requiredClass);
id OOJSNativeObjectOfClassFromJSObject(JSContext *context, JSObject *object, Class requiredClass);


OOINLINE JSClass *OOJSGetClass(JSContext *cx, JSObject *obj)  ALWAYS_INLINE_FUNC;
OOINLINE JSClass *OOJSGetClass(JSContext *cx, JSObject *obj)
{
#if JS_THREADSAFE
	return JS_GetClass(cx, obj);
#else
	return JS_GetClass(obj);
#endif
}


/*	OOJSValueIsFunction(context, value)
	
	Test whether a jsval is a function object. The main tripping point here
	is that JSVAL_IS_OBJECT() is true for JSVAL_NULL, but JS_ObjectIsFunction()
	crashes if passed null.
*/
OOINLINE BOOL OOJSValueIsFunction(JSContext *context, jsval value)
{
	return JSVAL_IS_OBJECT(value) && !JSVAL_IS_NULL(value) && JS_ObjectIsFunction(context, JSVAL_TO_OBJECT(value));
}


/*	OOJSValueIsArray(context, value)
	
	Test whether a jsval is an array object. The main tripping point here
	is that JSVAL_IS_OBJECT() is true for JSVAL_NULL, but JS_IsArrayObject()
	crashes if passed null.
	
	Also, it should be called JS_ObjectIsArray() for consistency.
*/
OOINLINE BOOL OOJSValueIsArray(JSContext *context, jsval value)
{
	return JSVAL_IS_OBJECT(value) && !JSVAL_IS_NULL(value) && JS_IsArrayObject(context, JSVAL_TO_OBJECT(value));
}


/*	OOJSDictionaryFromStringTable(context, value);
	
	Treat an arbitrary JavaScript object as a dictionary mapping strings to
	strings, and convert to a corresponding NSDictionary. The values are
	converted to strings using JS_ValueToString().
	
	Only enumerable own (i.e., not inherited) properties with string keys are
	included.
	
	Requires a request on context.
*/
NSDictionary *OOJSDictionaryFromStringTable(JSContext *context, jsval value);


/*
	DEFINE_JS_OBJECT_GETTER()
	Defines a helper to extract Objective-C objects from the private field of
	JS objects, with runtime type checking. The generated accessor requires
	a request on context. Weakrefs are automatically unpacked.
	
	Types which extend other types, such as entity subtypes, must register
	their relationships with OOJSRegisterSubclass() below.
	
	The signature of the generator is:
	BOOL <name(JSContext *context, JSObject *inObject, <class>** outObject)
	If it returns NO, inObject is of the wrong class and an error has been
	raised. Otherwise, outOjbect is either a native object of the specified
	class (or a subclass) or nil.
*/
#ifndef NDEBUG
#define DEFINE_JS_OBJECT_GETTER(NAME, JSCLASS, JSPROTO, OBJCCLASSNAME) \
static BOOL NAME(JSContext *context, JSObject *inObject, OBJCCLASSNAME **outObject)  GCC_ATTR((unused)); \
static BOOL NAME(JSContext *context, JSObject *inObject, OBJCCLASSNAME **outObject) \
{ \
	NSCParameterAssert(outObject != NULL); \
	static Class cls = Nil; \
	if (EXPECT_NOT(cls == Nil))  cls = [OBJCCLASSNAME class]; \
	return OOJSObjectGetterImpl(context, inObject, JSCLASS, cls, (id *)outObject); \
}
#else
#define DEFINE_JS_OBJECT_GETTER(NAME, JSCLASS, JSPROTO, OBJCCLASSNAME) \
OOINLINE BOOL NAME(JSContext *context, JSObject *inObject, OBJCCLASSNAME **outObject) \
{ \
	return OOJSObjectGetterImpl(context, inObject, JSCLASS, (id *)outObject); \
}
#endif

// For DEFINE_JS_OBJECT_GETTER()'s use.
#ifndef NDEBUG
BOOL OOJSObjectGetterImpl(JSContext *context, JSObject *object, JSClass *requiredJSClass, Class requiredObjCClass, id *outObject);
#else
BOOL OOJSObjectGetterImpl(JSContext *context, JSObject *object, JSClass *requiredJSClass, id *outObject);
#endif


/*
	Subclass relationships.
	
	JSAPI doesn't have a concept of subclassing, as JavaScript doesn't have a
	concept of classes, but Oolite reflects part of its class hierarchy as
	related JSClasses whose prototypes inherit each other. For instance,
	JS Entity methods work on JS Ships. In order for this to work,
	OOJSEntityGetEntity() must be able to know that Ship is a subclass of
	Entity. This is done using OOJSIsSubclass().
	
	void OOJSRegisterSubclass(JSClass *subclass, JSClass *superclass)
	Register subclass as a subclass of superclass. Subclass must not previously
	have been registered as a subclass of any class (i.e., single inheritance
	is required).
 
	BOOL OOJSIsSubclass(JSClass *putativeSubclass, JSClass *superclass)
	Test whether putativeSubclass is a equal to superclass or a registered
	subclass of superclass, recursively.
*/
void OOJSRegisterSubclass(JSClass *subclass, JSClass *superclass);
BOOL OOJSIsSubclass(JSClass *putativeSubclass, JSClass *superclass);
OOINLINE BOOL OOJSIsMemberOfSubclass(JSContext *context, JSObject *object, JSClass *superclass)
{
	return OOJSIsSubclass(OOJSGetClass(context, object), superclass);
}


/*	Support for OOJSNativeObjectFromJSValue() family
	
	OOJSClassConverterCallback specifies the prototype for a callback function
	which converts a JavaScript object to an Objective-C object.
	
	OOJSBasicPrivateObjectConverter() is a OOJSClassConverterCallback which
	returns the JS object's private storage value. It automatically unpacks
	OOWeakReferences if relevant.
	
	OOJSRegisterObjectConverter() registers a callback for a specific JS class.
	It is not automatically propagated to subclasses.
*/
typedef id (*OOJSClassConverterCallback)(JSContext *context, JSObject *object);
id OOJSBasicPrivateObjectConverter(JSContext *context, JSObject *object);

void OOJSRegisterObjectConverter(JSClass *theClass, OOJSClassConverterCallback converter);


/*	JS root handling
	
	The name parameter to JS_AddNamed*Root is assigned with no overhead, not
	copied, but the strings serve no purpose in a release build so we may as
	well strip them out.
	
	In debug builds, this will deliberately cause an error if name is not a
	string literal.
*/
#ifdef NDEBUG
#define OOJSAddGCValueRoot(context, root, name)		JS_AddValueRoot((context), (root))
#define OOJSAddGCStringRoot(context, root, name)	JS_AddStringRoot((context), (root))
#define OOJSAddGCObjectRoot(context, root, name)	JS_AddObjectRoot((context), (root))
#define OOJSAddGCThingRoot(context, root, name)		JS_AddGCThingRoot((context), (root))
#else
#define OOJSAddGCValueRoot(context, root, name)		JS_AddNamedValueRoot((context), (root), "" name)
#define OOJSAddGCStringRoot(context, root, name)	JS_AddNamedStringRoot((context), (root), "" name)
#define OOJSAddGCObjectRoot(context, root, name)	JS_AddNamedObjectRoot((context), (root), "" name)
#define OOJSAddGCThingRoot(context, root, name)		JS_AddNamedGCThingRoot((context), (root), "" name)
#endif


#if OOJSENGINE_MONITOR_SUPPORT

/*	Protocol for debugging "monitor" object.
	The monitor is an object -- in Oolite, or via Distributed Objects -- which
	is provided with debugging information by the OOJavaScriptEngine.
*/

@protocol OOJavaScriptEngineMonitor <NSObject>

// Sent for JS errors or warnings.
- (oneway void)jsEngine:(in byref OOJavaScriptEngine *)engine
				context:(in JSContext *)context
				  error:(in JSErrorReport *)errorReport
			  stackSkip:(in unsigned)stackSkip
		showingLocation:(in BOOL)showLocation
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
	OOJS_NATIVE_EXIT/OOJS_PROFILE_EXIT, or they will crash.
	
	For functions with a non-scalar return type, OOJS_PROFILE_EXIT should be
	replaced with OOJS_PROFILE_EXIT_VAL(returnValue). The returnValue is never
	used (and should be a constant expression), but is required to placate the
	compiler.
	
	For values with void return, use OOJS_PROFILE_EXIT_VOID. It is not
	necessary to insert a return statement before OOJS_PROFILE_EXIT_VOID.
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
#define OOJS_PROFILE_EXIT_VAL(rval)	} OO_UNREACHABLE(); OOJSUnreachable(__PRETTY_FUNCTION__, __FILE__, __LINE__); return (rval);
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
#else	// OOLITE_NATIVE_EXCEPTIONS

// These introduce a scope to ensure proper nesting.
#define OOJS_PROFILE_ENTER			{
#define OOJS_PROFILE_EXIT_VAL(rval)	} OO_UNREACHABLE(); OOJSUnreachable(__PRETTY_FUNCTION__, __FILE__, __LINE__); return (rval);
#define OOJS_PROFILE_EXIT_VOID		} return;

#define OOJS_NATIVE_ENTER(cx)	OOJS_PROFILE_ENTER
#define OOJS_NATIVE_EXIT		OOJS_PROFILE_EXIT_VAL(NO)

#endif	// OOLITE_NATIVE_EXCEPTIONS

#ifndef NDEBUG
void OOJSUnreachable(const char *function, const char *file, unsigned line)  NO_RETURN_FUNC;
#else
#define OOJSUnreachable(function, file, line) do {} while (0)
#endif


#define OOJS_PROFILE_EXIT		OOJS_PROFILE_EXIT_VAL(0)
#define OOJS_PROFILE_EXIT_JSVAL	OOJS_PROFILE_EXIT_VAL(JSVAL_VOID)


/*
	OOJS_BEGIN_FULL_NATIVE() and OOJS_END_FULL_NATIVE
	These macros are used to bracket sections of native Oolite code within JS
	callbacks which may take a long time. Thet do two things: pause the
	time limiter, and (in JS_THREADSAFE builds) suspend the current JS context
	request.
	
	These macros must be used in balanced pairs. They introduce a scope.
	
	JSAPI functions may not be used, directly or indirectily, between these
	macros unless explicitly opening a request first.
*/
#if JS_THREADSAFE
#define OOJS_BEGIN_FULL_NATIVE(context) \
	{ \
		OOJSPauseTimeLimiter(); \
		JSContext *oojsRequestContext = (context); \
		jsrefcount oojsRequestRefCount = JS_SuspendRequest(oojsRequestContext);

#define OOJS_END_FULL_NATIVE \
		JS_ResumeRequest(oojsRequestContext, oojsRequestRefCount); \
		OOJSResumeTimeLimiter(); \
	}
#else
#define OOJS_BEGIN_FULL_NATIVE(context) \
	{ \
		(void)(context); \
		OOJSPauseTimeLimiter(); \

#define OOJS_END_FULL_NATIVE \
		OOJSResumeTimeLimiter(); \
	}
#endif


/*	OOJSDumpStack()
	
	Write JavaScript stack to log.
*/
#ifndef NDEBUG
void OOJSDumpStack(JSContext *context);
#else
#define OOJSDumpStack(cx)  do {} while (0)
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
#define OOJS_CASTABLE_CONSTRUCTOR_CREATE	1

#define OOJS_RETURN_VECTOR(value)		do { jsval jsresult; BOOL OK = VectorToJSValue(context, value, &jsresult); JS_SET_RVAL(context, vp, jsresult); return OK; } while (0)
#define OOJS_RETURN_QUATERNION(value)	do { jsval jsresult; BOOL OK = QuaternionToJSValue(context, value, &jsresult); JS_SET_RVAL(context, vp, jsresult); return OK; } while (0)
#define OOJS_RETURN_DOUBLE(value)		do { JS_SET_RVAL(context, vp, DOUBLE_TO_JSVAL(value)); return YES; } while (0)

#define OOJS_PROP_ARGS					JSContext *context, JSObject *this, jsid propID, jsval *value
#define OOJS_PROPID_IS_INT				JSID_IS_INT(propID)
#define OOJS_PROPID_INT					JSID_TO_INT(propID)
#define OOJS_PROPID_IS_STRING			JSID_IS_STRING(propID)
#define OOJS_PROPID_STRING				JSID_TO_STRING(propID)

#else
#define OOJS_NATIVE_ARGS				JSContext *context, JSObject *this_, uintN argc, jsval *argv_, jsval *outResult
#define OOJS_NATIVE_CALLTHROUGH			context, this_, argc, argv_, outResult
#define OOJS_CALLEE						argv_[-2]
#define OOJS_THIS_VAL					OBJECT_TO_JSVAL(this_)
#define OOJS_THIS						this_
#define OOJS_ARGV						argv_
#define OOJS_RVAL						(*outResult)
#define OOJS_SET_RVAL(v)				do { *outResult = (v); } while (0)

#define OOJS_IS_CONSTRUCTING			JS_IsConstructing(context)
#define OOJS_CASTABLE_CONSTRUCTOR_CREATE	(!OOJS_IS_CONSTRUCTING)

#define OOJS_RETURN_VECTOR(value)		do { return VectorToJSValue(context, value, outResult); } while (0)
#define OOJS_RETURN_QUATERNION(value)	do { return QuaternionToJSValue(context, value, outResult); } while (0)
#define OOJS_RETURN_DOUBLE(value)		do { return JS_NewDoubleValue(context, value, outResult); } while (0)

#define OOJS_PROP_ARGS					JSContext *context, JSObject *this, jsval propID, jsval *value
#define OOJS_PROPID_IS_INT				JSVAL_IS_INT(propID)
#define OOJS_PROPID_INT					JSVAL_TO_INT(propID)
#define OOJS_PROPID_IS_STRING			JSVAL_IS_STRING(propID)
#define OOJS_PROPID_STRING				JSVAL_TO_STRING(propID)
#endif

#define OOJS_ARG(n)						(OOJS_ARGV[(n)])
#define OOJS_RETURN(v)					do { OOJS_SET_RVAL(v); return YES; } while (0)
#define OOJS_RETURN_JSOBJECT(o)			OOJS_RETURN(OBJECT_TO_JSVAL(o))
#define OOJS_RETURN_VOID				OOJS_RETURN(JSVAL_VOID)
#define OOJS_RETURN_NULL				OOJS_RETURN(JSVAL_NULL)
#define OOJS_RETURN_BOOL(v)				OOJS_RETURN(OOJSValueFromBOOL(v))
#define OOJS_RETURN_INT(v)				OOJS_RETURN(INT_TO_JSVAL(v))
#define OOJS_RETURN_OBJECT(o)			do { id o_ = (o); OOJS_RETURN(o_ ? [o_ oo_jsValueInContext:context] : JSVAL_NULL); } while (0)





/***** Reusable JS callbacks ****/

/*	OOJSUnconstructableConstruct
	
	Constructor callback for pseudo-classes which can't be constructed. This
	is needed because the instanceof operator only works on objects with a
	constructor.
*/
JSBool OOJSUnconstructableConstruct(OOJS_NATIVE_ARGS);


/*	OOJSObjectWrapperFinalize
	
	Finalizer for JS classes whose private storage is a retained object
	reference (generally an OOWeakReference, but doesn't have to be).
*/
void OOJSObjectWrapperFinalize(JSContext *context, JSObject *this);


/*	OOJSObjectWrapperToString
	
	Implementation of toString() for JS classes whose private storage is an
	Objective-C object reference (generally an OOWeakReference).
	
	Calls -oo_jsDescription and, if that fails, -description.
*/
JSBool OOJSObjectWrapperToString(OOJS_NATIVE_ARGS);




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


#if !OOJS_FF4B9
OOINLINE const jschar *JS_GetInternedStringChars(JSString *string) { return NULL; }
#endif


#define OOJSVAL_TO_DOUBLE JSVAL_TO_DOUBLE
#else
// In old API, jsvals could be pointers to doubles; in new, they're actual doubles.
#define OOJSVAL_TO_DOUBLE(val) (*JSVAL_TO_DOUBLE(val))

#define JS_GetGCParameter(...) (0)


OOINLINE const jschar *OOJSGetStringCharsAndLength(JSContext *context, JSString *string, size_t *length)
{
	NSCParameterAssert(context != NULL && string != NULL && length != NULL);
	
	*length = JS_GetStringLength(string);
	return JS_GetStringChars(string);
}


OOINLINE const jschar *JS_GetInternedStringChars(JSString *string) { return NULL; }
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
