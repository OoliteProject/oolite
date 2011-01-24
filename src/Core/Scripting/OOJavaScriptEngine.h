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


#import "OOCocoa.h"
#import "Universe.h"
#import "PlayerEntity.h"
#import "PlayerEntityLegacyScriptEngine.h"
#import <jsapi.h>


#define OOJSENGINE_MONITOR_SUPPORT	(!defined(NDEBUG))


// TEMP: macro for update to trunk SpiderMonkey.
#ifndef OO_NEW_JS
#define OO_NEW_JS				0
#endif


@protocol OOJavaScriptEngineMonitor;


@interface OOJavaScriptEngine: NSObject
{
@private
	JSRuntime						*runtime;
	JSObject						*globalObject;
	BOOL							_showErrorLocations;
	
	JSClass							*_objectClass;
	JSClass							*_stringClass;
	JSClass							*_arrayClass;
	JSClass							*_numberClass;
	JSClass							*_booleanClass;
	
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

- (void) removeGCObjectRoot:(JSObject **)rootPtr;
- (void) removeGCValueRoot:(jsval *)rootPtr;

- (void) garbageCollectionOpportunity;

- (BOOL) showErrorLocations;
- (void) setShowErrorLocations:(BOOL)value;

- (JSClass *) objectClass;
- (JSClass *) stringClass;
- (JSClass *) arrayClass;
- (JSClass *) numberClass;
- (JSClass *) booleanClass;

#ifndef NDEBUG
- (BOOL) dumpStackForErrors;
- (void) setDumpStackForErrors:(BOOL)value;

- (BOOL) dumpStackForWarnings;
- (void) setDumpStackForWarnings:(BOOL)value;

// Install handler for JS "debugger" statment.
- (void) enableDebuggerStatement;
#endif

@end


#if !JS_THREADSAFE
#define JS_IsInRequest(context)		(((void)(context)), YES)
#define JS_BeginRequest(context)	do {} while (0)
#define JS_EndRequest(context)		do {} while (0)
#endif


// Get the main thread's JS context, and begin a request on it.
OOINLINE JSContext *OOJSAcquireContext(void)
{
	extern JSContext *gOOJSMainThreadContext;
	NSCAssert(gOOJSMainThreadContext != NULL, @"Attempt to use JavaScript context before JavaScript engine is initialized.");
	JS_BeginRequest(gOOJSMainThreadContext);
	return gOOJSMainThreadContext;
}


// End a request on the main thread's context.
OOINLINE void OOJSRelinquishContext(JSContext *context)
{
#ifndef NDEBUG
	extern JSContext *gOOJSMainThreadContext;
	NSCParameterAssert(context == gOOJSMainThreadContext && JS_IsInRequest(context));
#endif
	JS_EndRequest(context);
}


/*	OOJSPropID
	A temporary type to identify JavaScript object properties/methods. When
	OO_NEW_JS is folded, it will be replaced with jsid.
	
	OOJSID(const char *)
	Macro to create a string-based ID. The string is interned and converted
	into a string by a helper the first time the macro is hit, then cached.
	
	OOStringFromJSPropID(propID)
	OOJSPropIDFromString(string)
	Converters.
*/
#import "OOJSPropID.h"
#if OO_NEW_JS
#define OOJSID(str) ({ static jsid idCache; static BOOL inited; if (EXPECT_NOT(!inited)) OOJSInitPropIDCachePRIVATE(str, &idCache, &inited); idCache; })
void OOJSInitPropIDCachePRIVATE(const char *name, jsid *idCache, BOOL *inited);
#else
#define OOJSID(str) (str)
#endif
NSString *OOStringFromJSPropID(OOJSPropID propID);
OOJSPropID OOJSPropIDFromString(NSString *string);


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
	
	All methods take a context parameter, which must either be nil or a context
	in a request.
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


/*	OOStringFromJSPropertyIDAndSpec(context, propID, propertySpec)
	
	Returns the name of a property given either a name or a tinyid. (Intended
	for error reporting inside JSPropertyOps.)
*/
#if OO_NEW_JS
NSString *OOStringFromJSPropertyIDAndSpec(JSContext *context, jsid propID, JSPropertySpec *propertySpec);
#else
NSString *OOStringFromJSPropertyIDAndSpec(JSContext *context, jsval propID, JSPropertySpec *propertySpec);
#endif


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


/*	OOJSDictionaryFromJSValue(context, value)
	OOJSDictionaryFromJSObject(context, object)
	
	Converts a JavaScript value to a dictionary by calling
	OOJSNativeObjectFromJSValue() on each of its values.
	
	Only enumerable own (i.e., not inherited) properties with string keys are
	included.
	
	Requires a request on context.
*/
NSDictionary *OOJSDictionaryFromJSValue(JSContext *context, jsval value);
NSDictionary *OOJSDictionaryFromJSObject(JSContext *context, JSObject *object);


/*	OOJSDictionaryFromStringTable(context, value)
	
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
	BOOL <name>(JSContext *context, JSObject *inObject, <class>** outObject)
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
	return OOJSObjectGetterImplPRIVATE(context, inObject, JSCLASS, cls, #NAME, (id *)outObject); \
}
#else
#define DEFINE_JS_OBJECT_GETTER(NAME, JSCLASS, JSPROTO, OBJCCLASSNAME) \
OOINLINE BOOL NAME(JSContext *context, JSObject *inObject, OBJCCLASSNAME **outObject) \
{ \
	return OOJSObjectGetterImplPRIVATE(context, inObject, JSCLASS, (id *)outObject); \
}
#endif

// For DEFINE_JS_OBJECT_GETTER()'s use.
#ifndef NDEBUG
BOOL OOJSObjectGetterImplPRIVATE(JSContext *context, JSObject *object, JSClass *requiredJSClass, Class requiredObjCClass, const char *name, id *outObject);
#else
BOOL OOJSObjectGetterImplPRIVATE(JSContext *context, JSObject *object, JSClass *requiredJSClass, id *outObject);
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


#import "OOJSEngineNativeWrappers.h"

/*	See comments on time limiter in OOJSEngineTimeManagement.h.
*/
void OOJSPauseTimeLimiter(void);
void OOJSResumeTimeLimiter(void);


/*	OOJSDumpStack()
	Write JavaScript stack to log.
	
	OOJSDescribeLocation()
	Get script and line number for a stack frame.
	
	OOJSMarkConsoleEvalLocation()
	Specify that a given stack frame identifies eval()ed code from the debug
	console, so that matching locations can be described specially by
	OOJSDescribeLocation().
*/
#ifndef NDEBUG
void OOJSDumpStack(JSContext *context);

NSString *OOJSDescribeLocation(JSContext *context, JSStackFrame *stackFrame);
void OOJSMarkConsoleEvalLocation(JSContext *context, JSStackFrame *stackFrame);
#else
#define OOJSDumpStack(cx)						do {} while (0)
#define OOJSDescribeLocation(cx, frame)			do {} while (0)
#define OOJSMarkConsoleEvalLocation(cx, frame)  do {} while (0)
#endif


#if OO_NEW_JS
// Native callback conventions have changed.
#define OOJS_NATIVE_ARGS				JSContext *context, uintN argc, jsval *vp
#else

#define OOJS_NATIVE_ARGS				JSContext *context, JSObject *this_, uintN argc, jsval *argv_, jsval *outResult
#endif




/***** Reusable JS callbacks ****/

/*	OOJSUnconstructableConstruct
	
	Constructor callback for pseudo-classes which can't be constructed.
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




/***** Helpers to return values from native callbacks. *****/

#if OO_NEW_JS

#define OOJS_RETURN_VECTOR(value)		do { jsval jsresult; BOOL OK = VectorToJSValue(context, value, &jsresult); JS_SET_RVAL(context, vp, jsresult); return OK; } while (0)
#define OOJS_RETURN_QUATERNION(value)	do { jsval jsresult; BOOL OK = QuaternionToJSValue(context, value, &jsresult); JS_SET_RVAL(context, vp, jsresult); return OK; } while (0)
#define OOJS_RETURN_DOUBLE(value)		do { JS_SET_RVAL(context, vp, DOUBLE_TO_JSVAL(value)); return YES; } while (0)

#else

#define OOJS_RETURN_VECTOR(value)		do { return VectorToJSValue(context, value, outResult); } while (0)
#define OOJS_RETURN_QUATERNION(value)	do { return QuaternionToJSValue(context, value, outResult); } while (0)
#define OOJS_RETURN_DOUBLE(value)		do { return JS_NewDoubleValue(context, value, outResult); } while (0)

#endif

#define OOJS_RETURN(v)					do { OOJS_SET_RVAL(v); return YES; } while (0)
#define OOJS_RETURN_JSOBJECT(o)			OOJS_RETURN(OBJECT_TO_JSVAL(o))
#define OOJS_RETURN_VOID				OOJS_RETURN(JSVAL_VOID)
#define OOJS_RETURN_NULL				OOJS_RETURN(JSVAL_NULL)
#define OOJS_RETURN_BOOL(v)				OOJS_RETURN(OOJSValueFromBOOL(v))
#define OOJS_RETURN_INT(v)				OOJS_RETURN(INT_TO_JSVAL(v))
#define OOJS_RETURN_OBJECT(o)			do { id o_ = (o); OOJS_RETURN(o_ ? [o_ oo_jsValueInContext:context] : JSVAL_NULL); } while (0)


#import "OOJSEngineTransitionHelpers.h"
