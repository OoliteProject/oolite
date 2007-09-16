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

#import "OOJavaScriptEngine.h"
#import "OOJSScript.h"

#import "OOJSGlobal.h"
#import "OOJSMissionVariables.h"
#import "OOJSMission.h"
#import "OOJSVector.h"
#import "OOJSQuaternion.h"
#import "OOJSEntity.h"
#import "OOJSShip.h"
#import "OOJSStation.h"
#import "OOJSPlayer.h"
#import "OOJSSystem.h"
#import "OOJSOolite.h"
#import "OOJSTimer.h"
#import "OOJSClock.h"

#import "OOCollectionExtractors.h"
#import "Universe.h"
#import "PlanetEntity.h"
#import "NSStringOOExtensions.h"
#import "OOWeakReference.h"

#include <stdio.h>
#include <string.h>


static OOJavaScriptEngine *sSharedEngine = nil;


#if OOJSENGINE_MONITOR_SUPPORT

@interface OOJavaScriptEngine (OOMonitorSupportInternal)

- (void)sendMonitorError:(JSErrorReport *)errorReport
			 withMessage:(NSString *)message
			   inContext:(JSContext *)context;

- (void)sendMonitorLogMessage:(NSString *)message
			 withMessageClass:(NSString *)messageClass
					inContext:(JSContext *)context;

@end

#endif


static void ReportJSError(JSContext *context, const char *message, JSErrorReport *report);


static void RegisterStandardObjectConverters(JSContext *context);

static id JSArrayConverter(JSContext *context, JSObject *object);
static id JSGenericObjectConverter(JSContext *context, JSObject *object);


static void ReportJSError(JSContext *context, const char *message, JSErrorReport *report)
{
	NSString		*severity = nil;
	NSString		*messageText = nil;
	NSString		*lineBuf = nil;
	NSString		*messageClass = nil;
	NSString		*highlight = @"*****";
	
	// Type of problem: error, warning or exception? (Strict flag wilfully ignored.)
	if (report->flags & JSREPORT_EXCEPTION) severity = @"exception";
	else if (report->flags & JSREPORT_WARNING)
	{
		severity = @"warning";
		highlight = @"-----";
	}
	else severity = @"error";
	
	// The error message itself
	messageText = [NSString stringWithUTF8String:message];
	
	// Get offending line, if present, and trim trailing line breaks
	lineBuf = [NSString stringWithUTF16String:report->uclinebuf];
	while ([lineBuf hasSuffix:@"\n"] || [lineBuf hasSuffix:@"\r"])  lineBuf = [lineBuf substringToIndex:[lineBuf length] - 1];
	
	// Log message class
	messageClass = [NSString stringWithFormat:@"script.javaScript.%@.%u", severity, report->errorNumber];
	
	// First line: problem description
	OOLog(messageClass, @"%@ JavaScript %@: %@", highlight, severity, messageText);
	
	// Second line: where error occured, and line if provided. (The line is only provided for compile-time errors, not run-time errors.)
	if ([lineBuf length] != 0)
	{
		OOLog(messageClass, @"      %s, line %d: %@", report->filename, report->lineno, lineBuf);
	}
	else
	{
		OOLog(messageClass, @"      %s, line %d.", report->filename, report->lineno);
	}
	
#if OOJSENGINE_MONITOR_SUPPORT
	[[OOJavaScriptEngine sharedEngine] sendMonitorError:report
											withMessage:messageText
											  inContext:context];
#endif
}


//===========================================================================
// JavaScript engine initialisation and shutdown
//===========================================================================

@implementation OOJavaScriptEngine

+ (OOJavaScriptEngine *)sharedEngine
{
	if (sSharedEngine == nil) [[self alloc] init];
	
	return sSharedEngine;
}


- (id) init
{
	assert(sSharedEngine == nil);
	assert(JS_CStringsAreUTF8());
	
	self = [super init];
	
	assert(sizeof(jschar) == sizeof(unichar));

	// set up global JS variables, including global and custom objects

	// initialize the JS run time, and return result in runtime
	runtime = JS_NewRuntime(8L * 1024L * 1024L);
	
	// if runtime does not have a value, end the program here
	if (!runtime)
	{
		OOLog(@"script.javaScript.init.error", @"FATAL ERROR: failed to create JavaScript %@.", @"runtime");
		exit(1);
	}

	// create a context and associate it with the JS run time
	context = JS_NewContext(runtime, 8192);
	JS_SetOptions(context, JSOPTION_VAROBJFIX | JSOPTION_STRICT | JSOPTION_COMPILE_N_GO | JSOPTION_NATIVE_BRANCH_CALLBACK);
	JS_SetVersion(context, JSVERSION_1_7);
	
	// if context does not have a value, end the program here
	if (!context)
	{
		OOLog(@"script.javaScript.init.error", @"FATAL ERROR: failed to create JavaScript %@.", @"context");
		exit(1);
	}
	
	JS_SetErrorReporter(context, ReportJSError);
	
	// Create the global object.
	CreateOOJSGlobal(context, &globalObject);

	// Initialize the built-in JS objects and the global object.
	JS_InitStandardClasses(context, globalObject);
	RegisterStandardObjectConverters(context);
	
	SetUpOOJSGlobal(context, globalObject);
	
	// Initialize Oolite classes.
	InitOOJSMissionVariables(context, globalObject);
	InitOOJSMission(context, globalObject);
	InitOOJSOolite(context, globalObject);
	InitOOJSVector(context, globalObject);
	InitOOJSQuaternion(context, globalObject);
	InitOOJSSystem(context, globalObject);
	InitOOJSEntity(context, globalObject);
	InitOOJSShip(context, globalObject);
	InitOOJSStation(context, globalObject);
	InitOOJSPlayer(context, globalObject);
	InitOOJSScript(context, globalObject);
	InitOOJSTimer(context, globalObject);
	InitOOJSClock(context, globalObject);
	
	OOLog(@"script.javaScript.init.success", @"Set up JavaScript context.");
	
	sSharedEngine = self;
	return self;
}


- (void) dealloc
{
	sSharedEngine = nil;
	
	JS_DestroyContext(context);
	JS_DestroyRuntime(runtime);
	
	[super dealloc];
}


- (JSContext *) context
{
	return context;
}


- (JSObject *) globalObject
{
	return globalObject;
}

@end


#if OOJSENGINE_MONITOR_SUPPORT

@implementation OOJavaScriptEngine (OOMonitorSupport)

- (void)setMonitor:(id<OOJavaScriptEngineMonitor>)inMonitor
{
	[monitor autorelease];
	monitor = [inMonitor retain];
}

@end


@implementation OOJavaScriptEngine (OOMonitorSupportInternal)

- (void)sendMonitorError:(JSErrorReport *)errorReport
			 withMessage:(NSString *)message
			   inContext:(JSContext *)theContext
{
	if ([monitor respondsToSelector:@selector(jsEngine:context:error:withMessage:)])
	{
		[monitor jsEngine:self context:theContext error:errorReport withMessage:message];
	}
}


- (void)sendMonitorLogMessage:(NSString *)message
			 withMessageClass:(NSString *)messageClass
					inContext:(JSContext *)theContext
{
	if ([monitor respondsToSelector:@selector(jsEngine:context:logMessage:ofClass:)])
	{
		[monitor jsEngine:self context:theContext logMessage:message ofClass:messageClass];
	}
}

@end

#endif


void OOReportJavaScriptError(JSContext *context, NSString *format, ...)
{
	va_list					args;
	
	va_start(args, format);
	OOReportJavaScriptErrorWithArguments(context, format, args);
	va_end(args);
}


void OOReportJavaScriptErrorWithArguments(JSContext *context, NSString *format, va_list args)
{
	NSString				*msg = nil;
	
	msg = [[NSString alloc] initWithFormat:format arguments:args];
	JS_ReportError(context, "%s", [msg UTF8String]);
	[msg release];
}


void OOReportJavaScriptWarning(JSContext *context, NSString *format, ...)
{
	va_list					args;
	
	va_start(args, format);
	OOReportJavaScriptWarningWithArguments(context, format, args);
	va_end(args);
}


void OOReportJavaScriptWarningWithArguments(JSContext *context, NSString *format, va_list args)
{
	NSString				*msg = nil;
	
	msg = [[NSString alloc] initWithFormat:format arguments:args];
	JS_ReportWarning(context, "%s", [msg UTF8String]);
	[msg release];
}


void OOReportJavaScriptBadPropertySelector(JSContext *context, NSString *className, jsint selector)
{
	OOReportJavaScriptError(context, @"Internal error: bad property identifier %i in property accessor for class %@.", selector, className);
}


BOOL NumberFromArgumentList(JSContext *context, NSString *scriptClass, NSString *function, uintN argc, jsval *argv, double *outNumber, uintN *outConsumed)
{
	double					value;
	
	// Sanity checks.
	if (outConsumed != NULL)  *outConsumed = 0;
	if (EXPECT_NOT(argc == 0 || argv == NULL || outNumber == NULL))
	{
		OOLogGenericParameterError();
		return NO;
	}
	
	// Get value, if possible.
	if (EXPECT_NOT(!JS_ValueToNumber(context, argv[0], &value) || isnan(value)))
	{
		// Failed; report bad parameters, if given a class and function.
		if (scriptClass != nil && function != nil)
		{
			OOReportJavaScriptWarning(context, @"%@.%@(): expected number, got %@.", scriptClass, function, [NSString stringWithJavaScriptParameters:argv count:1 inContext:context]);
			return NO;
		}
	}
	
	// Success.
	*outNumber = value;
	if (outConsumed != NULL)  *outConsumed = 1;
	return YES;
}


static BOOL ExtractString(NSString *string, jschar **outString, size_t *outLength)
{
	assert(outString != NULL && outLength != NULL);
	assert(sizeof (unichar) == sizeof (jschar));	// Should both be 16 bits
	
	*outLength = [string length];
	if (*outLength == 0)  return NO;	// nil/empty strings not accepted.
	
	*outString = malloc(sizeof (unichar) * *outLength);
	if (*outString == NULL)  return NO;
	
	[string getCharacters:(unichar *)*outString];
	return YES;
}


BOOL JSSetNSProperty(JSContext *context, JSObject *object, NSString *name, jsval *value)
{
	jschar					*buffer = NULL;
	size_t					length;
	BOOL					OK = NO;
	
	if (ExtractString(name, &buffer, &length))
	{
		OK = JS_SetUCProperty(context, object, buffer, length, value);
		free(buffer);
	}
	return OK;
}


BOOL JSGetNSProperty(JSContext *context, JSObject *object, NSString *name, jsval *value)
{
	jschar					*buffer = NULL;
	size_t					length;
	BOOL					OK = NO;
	
	if (ExtractString(name, &buffer, &length))
	{
		OK = JS_GetUCProperty(context, object, buffer, length, value);
		free(buffer);
	}
	return OK;
}


static JSObject *JSArrayFromNSArray(JSContext *context, NSArray *array)
{
	volatile JSObject		*result = NULL;
	volatile unsigned		i;
	unsigned				count;
	jsval					value;
	BOOL					OK = YES;
	
	if (array == nil)  return NULL;
	
	result = JS_NewArrayObject(context, 0, NULL);
	if (result == NULL)  return NULL;
	
	NS_DURING
		count = [array count];
		for (i = 0; i != count; ++i)
		{
			value = [[array objectAtIndex:i] javaScriptValueInContext:context];
			OK = JS_SetElement(context, (JSObject *)result, i, &value);
			if (!OK)  return NULL;
		}
	NS_HANDLER
		result = NULL;
	NS_ENDHANDLER
	
	return (JSObject *)result;
}


static BOOL JSNewNSArrayValue(JSContext *context, NSArray *array, jsval *value)
{
	JSObject				*object = NULL;
	BOOL					OK = YES;
	
	if (value == NULL)  return NO;
	
	// NOTE: should be called within a local root scope or have *value be a set root for GC reasons.
	if (!JS_EnterLocalRootScope(context))  return NO;
	
	object = JSArrayFromNSArray(context, array);
	if (object == NULL)
	{
		*value = JSVAL_VOID;
		OK = NO;
	}
	else
	{
		*value = OBJECT_TO_JSVAL(object);
	}
	
	JS_LeaveLocalRootScope(context);
	return OK;
}


/*	Convert an NSDictionary to a JavaScript Object.
	Only properties whose keys are either strings or non-negative NSNumbers,
	and	whose values have a non-void JS representation, are converted.
*/
static JSObject *JSObjectFromNSDictionary(JSContext *context, NSDictionary *dictionary)
{
	volatile JSObject		*result = NULL;
	BOOL					OK = YES;
	NSEnumerator			*keyEnum = nil;
	id						key = nil;
	jsval					value;
	jsint					index;
	
	if (dictionary == nil)  return NULL;
	
	result = JS_NewObject(context, NULL, NULL, NULL);	// create object of class Object
	if (result == NULL)  return NULL;
	
	NS_DURING
		for (keyEnum = [dictionary keyEnumerator]; (key = [keyEnum nextObject]); )
		{
			if ([key isKindOfClass:[NSString class]] && [key length] != 0)
			{
				value = [[dictionary objectForKey:key] javaScriptValueInContext:context];
				if (value != JSVAL_VOID)
				{
					OK = JSSetNSProperty(context, (JSObject *)result, key, &value);
					if (!OK)  return NULL;
				}
			}
			else if ([key isKindOfClass:[NSNumber class]])
			{
				index = [key intValue];
				if (0 < index)
				{
					value = [[dictionary objectForKey:key] javaScriptValueInContext:context];
					if (value != JSVAL_VOID)
					{
						OK = JS_SetElement(context, (JSObject *)result, index, &value);
						if (!OK)  return NULL;
					}
				}
			}
		}
	NS_HANDLER
		result = NULL;
	NS_ENDHANDLER
	
	return (JSObject *)result;
}


static BOOL JSNewNSDictionaryValue(JSContext *context, NSDictionary *dictionary, jsval *value)
{
	JSObject				*object = NULL;
	BOOL					OK = YES;
	
	if (value == NULL)  return NO;
	
	// NOTE: should be called within a local root scope or have *value be a set root for GC reasons.
	if (!JS_EnterLocalRootScope(context))  return NO;
	
	object = JSObjectFromNSDictionary(context, dictionary);
	if (object == NULL)
	{
		*value = JSVAL_VOID;
		OK = NO;
	}
	else
	{
		*value = OBJECT_TO_JSVAL(object);
	}
	
	JS_LeaveLocalRootScope(context);
	return OK;
}


@implementation NSObject (OOJavaScriptConversion)

- (jsval)javaScriptValueInContext:(JSContext *)context
{
	return JSVAL_VOID;
}


- (NSString *)descriptionComponents
{
	return nil;
}


- (NSString *)jsClassName
{
	return nil;
}


- (NSString *)javaScriptDescription
{
	return [self javaScriptDescriptionWithClassName:[self jsClassName]];
}


- (NSString *)javaScriptDescriptionWithClassName:(NSString *)className
{
	NSString				*components = nil;
	NSString				*description = nil;
	
	components = [self descriptionComponents];
	if (className == nil)  className = [[self class] description];
	
	if (components != nil)
	{
		description = [NSString stringWithFormat:@"[%@ %@]", className, components];
	}
	else
	{
		description = [NSString stringWithFormat:@"[object %@]", className];
	}
	
	return description;
}


- (NSString *)description
{
	NSString				*components = nil;
	
	components = [self descriptionComponents];
	if (components != nil)
	{
		return [NSString stringWithFormat:@"<%@ %p>{%@}", [self class], self, components];
	}
	else
	{
		return [NSString stringWithFormat:@"<%@ %p>", [self class], self];
	}
}

@end


@implementation NSString (OOJavaScriptExtensions)

// Convert a JSString to an NSString.
+ (id)stringWithJavaScriptString:(JSString *)string
{
	jschar					*chars = NULL;
	size_t					length;
	
	chars = JS_GetStringChars(string);
	length = JS_GetStringLength(string);
	
	return [NSString stringWithCharacters:chars length:length];
}


+ (id)stringWithJavaScriptValue:(jsval)value inContext:(JSContext *)context
{
	JSString				*string = NULL;
	
	if (JSVAL_IS_NULL(value) || JSVAL_IS_VOID(value))  return nil;
	string = JS_ValueToString(context, value);	// Calls the value's toString method if needed.
	return [NSString stringWithJavaScriptString:string];
}


+ (id)stringWithJavaScriptParameters:(jsval *)params count:(uintN)count inContext:(JSContext *)context
{
	if (params == NULL && count != 0) return nil;
	
	uintN					i;
	jsval					val;
	NSMutableString			*result = [NSMutableString string];
	NSString				*valString = nil;
	
	for (i = 0; i != count; ++i)
	{
		if (i != 0)  [result appendString:@", "];
		else  [result appendString:@"("];
		
		val = params[i];
		valString = [self stringWithJavaScriptValue:val inContext:context];
		if (JSVAL_IS_STRING(val))
		{
			[result appendFormat:@"\"%@\"", valString];
		}
		else
		{
			if (valString == nil)
			{
				if (JSVAL_IS_VOID(val))  valString = @"undefined";
				else valString = @"null";
			}
			[result appendString:valString];
		}
	}
	
	[result appendString:@")"];
	return result;
}


- (jsval)javaScriptValueInContext:(JSContext *)context
{
	size_t					length;
	unichar					*buffer = NULL;
	JSString				*string = NULL;
	
	length = [self length];
	buffer = malloc(length * sizeof *buffer);
	if (buffer == NULL) return JSVAL_VOID;
	
	[self getCharacters:buffer];
	
	string = JS_NewUCStringCopyN(context, buffer, length);
	free(buffer);
	
	return STRING_TO_JSVAL(string);
}


+ (id)concatenationOfStringsFromJavaScriptValues:(jsval *)values count:(size_t)count separator:(NSString *)separator inContext:(JSContext *)context
{
	size_t					i;
	NSMutableString			*result = nil;
	NSString				*element = nil;
	
	if (count < 1) return nil;
	if (values == NULL) return NULL;
	
	for (i = 0; i != count; ++i)
	{
		element = [NSString stringWithJavaScriptValue:values[i] inContext:context];
		if (result == nil) result = [element mutableCopy];
		else
		{
			if (separator != nil) [result appendString:separator];
			[result appendString:element];
		}
	}
	
	return result;
}

@end


@implementation NSArray (OOJavaScriptConversion)

- (jsval)javaScriptValueInContext:(JSContext *)context
{
	jsval value = JSVAL_VOID;
	JSNewNSArrayValue(context, self, &value);
	return value;
}

@end


@implementation NSDictionary (OOJavaScriptConversion)

- (jsval)javaScriptValueInContext:(JSContext *)context
{
	jsval value = JSVAL_VOID;
	JSNewNSDictionaryValue(context, self, &value);
	return value;
}

@end


@implementation NSNumber (OOJavaScriptConversion)

- (jsval)javaScriptValueInContext:(JSContext *)context
{
	jsval					result;
	BOOL					isFloat = NO;
	const char				*type;
	long long				longLongValue;
	
	if (self == [NSNumber numberWithBool:YES])
	{
		/*	Under OS X, at least, numberWithBool: returns one of two singletons.
			There is no other way to reliably identify a boolean NSNumber.
			Fun, eh? */
		result = JSVAL_TRUE;
	}
	else if (self == [NSNumber numberWithBool:NO])
	{
		result = JSVAL_FALSE;
	}
	else
	{
		longLongValue = [self longLongValue];
		if (longLongValue < (long long)JSVAL_INT_MIN || (long long)JSVAL_INT_MAX < longLongValue)
		{
			// values outside JSVAL_INT range are returned as doubles.
			isFloat = YES;
		}
		else
		{
			// Check value type.
			type = [self objCType];
			if (type[0] == 'f' || type[0] == 'd') isFloat = YES;
		}
		
		if (isFloat)
		{
			if (!JS_NewDoubleValue(context, [self doubleValue], &result)) result = JSVAL_VOID;
		}
		else
		{
			result = INT_TO_JSVAL(longLongValue);
		}
	}
	
	return result;
}

@end


@implementation NSNull (OOJavaScriptConversion)

- (jsval)javaScriptValueInContext:(JSContext *)context
{
	return JSVAL_NULL;
}

@end


JSBool JSObjectWrapperToString(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	id						object = nil;
	NSString				*description = nil;
	JSClass					*jsClass = NULL;
	
	object = JSObjectToObject(context, this);
	if (object != nil)
	{
		description = [object javaScriptDescription];
		if (description == nil)  description = [object description];
	}
	if (description == nil)
	{
		jsClass = JS_GetClass(this);
		if (jsClass != NULL)
		{
			description = [NSString stringWithFormat:@"[object %@]", [NSString stringWithUTF8String:jsClass->name]];
		}
	}
	if (description == nil)  description = @"[object]";
	
	*outResult = [description javaScriptValueInContext:context];
	return YES;
}


static NSMutableDictionary *sObjectConverters;

id JSValueToObject(JSContext *context, jsval value)
{
	if (JSVAL_IS_NULL(value) || JSVAL_IS_VOID(value))  return nil;
	
	if (JSVAL_IS_INT(value))
	{
		return [NSNumber numberWithInt:JSVAL_TO_INT(value)];
	}
	if (JSVAL_IS_DOUBLE(value))
	{
		return [NSNumber numberWithDouble:*JSVAL_TO_DOUBLE(value)];
	}
	if (JSVAL_IS_BOOLEAN(value))
	{
		return [NSNumber numberWithBool:JSVAL_TO_BOOLEAN(value)];
	}
	if (JSVAL_IS_STRING(value))
	{
		return JSValToNSString(context, value);
	}
	if (JSVAL_IS_OBJECT(value))
	{
		return JSObjectToObject(context, JSVAL_TO_OBJECT(value));
	}
	return nil;
}


id JSObjectToObject(JSContext *context, JSObject *object)
{
	NSValue					*wrappedClass = nil;
	NSValue					*wrappedConverter = nil;
	JSClassConverterCallback converter = NULL;
	JSClass					*class = NULL;
	
	if (object == NULL)  return nil;
	
	class = JS_GetClass(object);
	wrappedClass = [NSValue valueWithPointer:class];
	if (wrappedClass != nil)  wrappedConverter = [sObjectConverters objectForKey:wrappedClass];
	if (wrappedConverter != nil)
	{
		converter = [wrappedConverter pointerValue];
		return converter(context, object);
	}
	return nil;
}


id JSBasicPrivateObjectConverter(JSContext *context, JSObject *object)
{
	id						result;
	
	/*	This will do the right thing - for non-OOWeakReferences,
		weakRefUnderlyingObject returns the object itself. For nil, of course,
		it returns nil.
	*/
	result = JS_GetPrivate(context, object);
	return [result weakRefUnderlyingObject];
}


void JSRegisterObjectConverter(JSClass *theClass, JSClassConverterCallback converter)
{
	NSValue					*wrappedClass = nil;
	NSValue					*wrappedConverter = nil;
	
	if (theClass == NULL)  return;
	if (sObjectConverters == nil)  sObjectConverters = [[NSMutableDictionary alloc] init];
	
	wrappedClass = [NSValue valueWithPointer:theClass];
	if (converter != NULL)
	{
		wrappedConverter = [NSValue valueWithPointer:converter];
		[sObjectConverters setObject:wrappedConverter forKey:wrappedClass];
	}
	else
	{
		[sObjectConverters removeObjectForKey:wrappedClass];
	}
}


static void RegisterStandardObjectConverters(JSContext *context)
{
	JSObject				*templateObject = NULL;
	JSClass					*class = NULL;
	
	// Create an array in order to get array class.
	templateObject = JS_NewArrayObject(context, 0, NULL);
	class = JS_GetClass(templateObject);
	JSRegisterObjectConverter(class, JSArrayConverter);
	
	// Likewise, create a blank object to get its class.
	// This is not documented (not much is) but JS_NewObject falls back to Object if passed a NULL class.
	templateObject = JS_NewObject(context, NULL, NULL, NULL);
	class = JS_GetClass(templateObject);
	JSRegisterObjectConverter(class, JSGenericObjectConverter);
}

static id JSArrayConverter(JSContext *context, JSObject *array)
{
	jsuint						i, count;
	id							*values = NULL;
	jsval						value = JSVAL_VOID;
	id							object = nil;
	NSArray						*result = nil;
	
	// Convert a JS array to an NSArray by calling JSValueToObject() on all its elements.
	if (!JS_IsArrayObject(context, array)) return nil;
	if (!JS_GetArrayLength(context, array, &count)) return nil;
	
	if (count == 0)  return [NSArray array];
	
	values = calloc(count, sizeof *values);
	if (values == NULL)  return nil;
	
	for (i = 0; i != count; ++i)
	{
		value = JSVAL_VOID;
		if (!JS_GetElement(context, array, i, &value))  value = JSVAL_VOID;
		
		object = JSValueToObject(context, value);
		if (object == nil)  object = [NSNull null];
		values[i] = object;
	}
	
	result = [NSArray arrayWithObjects:values count:count];
	free(values);
	return result;
}


static id JSGenericObjectConverter(JSContext *context, JSObject *object)
{
	JSIdArray					*ids;
	jsint						i;
	NSMutableDictionary			*result = nil;
	jsval						propKey = JSVAL_VOID,
								value = JSVAL_VOID;
	id							objKey = nil;
	id							objValue = nil;
	jsint						intKey;
	JSString					*stringKey = NULL;
	
	/*	Convert a JS Object to an NSDictionary by calling
		JSValueToObject() on all its enumerable properties. This is desireable
		because it allows objects declared with JavaScript property list
		syntax to be converted to native property lists.
		
		This won't convert all objects, since JS has no concept of a class
		heirarchy. Also, note that prototype properties are not included.
	*/
	
	ids = JS_Enumerate(context, object);
	if (ids == NULL)  return nil;
	
	result = [NSMutableDictionary dictionaryWithCapacity:ids->length];
	for (i = 0; i != ids->length; ++i)
	{
		propKey = value = JSVAL_VOID;
		objKey = nil;
		
		if (JS_IdToValue(context, ids->vector[i], &propKey))
		{
			// Properties with string keys
			if (JSVAL_IS_STRING(propKey))
			{
				stringKey = JSVAL_TO_STRING(propKey);
				if (JS_LookupProperty(context, object, JS_GetStringBytes(stringKey), &value))
				{
					objKey = [NSString stringWithJavaScriptString:stringKey];
				}
			}
			
			// Properties with int keys
			else if (JSVAL_IS_INT(propKey))
			{
				intKey = JSVAL_TO_INT(propKey);
				if (JS_GetElement(context, object, intKey, &value))
				{
					objKey = [NSNumber numberWithInt:intKey];
				}
			}
		}
		
		if (objKey != nil && value != JSVAL_VOID)
		{
			objValue = JSValueToObject(context, value);
			if (objValue != nil)
			{
				[result setObject:objValue forKey:objKey];
			}
		}
	}
	
	JS_DestroyIdArray(context, ids);
	return result;
}
