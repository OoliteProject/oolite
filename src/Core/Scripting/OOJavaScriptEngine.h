/*

OOJavaScriptEngine.h

JavaScript support for Oolite
Copyright (C) 2007 David Taylor and Jens Ayton.

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

#define OOJSENGINE_MONITOR_SUPPORT	(!defined(NDEBUG))


// Macro to selectively compile with JS 1.8 support.
// To be removed when switching to JS 1.8 as default, once FF 3 is final.
#define OOJSENGINE_JS_18 (defined JSFUN_FAST_NATIVE)


@protocol OOJavaScriptEngineMonitor;


enum
{
	kOOJavaScriptEngineContextPoolCount = 5
};


@interface OOJavaScriptEngine : NSObject
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

- (BOOL) addGCRoot:(void *)rootPtr
			 named:(const char *)name;
- (void) removeGCRoot:(void *)rootPtr;

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


@interface NSObject (OOJavaScriptConversion)

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


/*	JSObjectWrapperToString
	
	Implementation of toString() for JS classes whose private storage is an
	Objective-C object reference (generally an OOWeakReference).
	
	Calls -javaScriptDescription and, if that fails, -description.
*/
JSBool JSObjectWrapperToString(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);


/*	JSObjectWrapperFinalize
	
	Finalizer for JS classes whose private storage is a retained object
	reference (generally an OOWeakReference, but doesn't have to be).
*/
void JSObjectWrapperFinalize(JSContext *context, JSObject *this);


/*	JSObjectWrapperEquality
	
	Comparator for JS classes whose private storage is a retained object;
	wraps isEqual.
*/
JSBool JSObjectWrapperEquality(JSContext *context, JSObject *this, jsval value, JSBool *outEqual);


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
	if (outObject == NULL)  return NO; \
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
