/*

OOJavaScriptEngine.m

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

#import "OOCollectionExtractors.h"
#import "Universe.h"
#import "PlanetEntity.h"
#import "NSStringOOExtensions.h"
#import "OOWeakReference.h"
#import "EntityOOJavaScriptExtensions.h"

#import "OOJSGlobal.h"
#import "OOJSMissionVariables.h"
#import "OOJSMission.h"
#import "OOJSVector.h"
#import "OOJSQuaternion.h"
#import "OOJSEntity.h"
#import "OOJSShip.h"
#import "OOJSStation.h"
#import "OOJSPlayer.h"
#import "OOJSPlayerShip.h"
#import "OOJSPlanet.h"
#import "OOJSSystem.h"
#import "OOJSOolite.h"
#import "OOJSTimer.h"
#import "OOJSClock.h"
#import "OOJSSun.h"
#import "OOJSWorldScripts.h"
#import "OOJSSound.h"
#import "OOJSSoundSource.h"
#import "OOJSSpecialFunctions.h"
#import "OOJSSystemInfo.h"
#import "OOJSEquipmentInfo.h"
#import "OOJSShipGroup.h"

#import <stdlib.h>


#if OOJSENGINE_JS_18
#define OOJSENGINE_JSVERSION		JSVERSION_1_8
#define OOJSENGINE_CONTEXT_OPTIONS	JSOPTION_VAROBJFIX | JSOPTION_STRICT | JSOPTION_NATIVE_BRANCH_CALLBACK | JSOPTION_RELIMIT | JSOPTION_ANONFUNFIX
#else
#define OOJSENGINE_JSVERSION		JSVERSION_1_7
#define OOJSENGINE_CONTEXT_OPTIONS	JSOPTION_VAROBJFIX | JSOPTION_STRICT | JSOPTION_NATIVE_BRANCH_CALLBACK
#endif


#ifdef MOZILLA_1_8_BRANCH
#error Oolite and libjs must be built with MOZILLA_1_8_BRANCH undefined.
#endif
#ifdef JS_THREADSAFE
#error Oolite and libjs must be built with JS_THREADSAFE undefined.
#endif


static OOJavaScriptEngine	*sSharedEngine = nil;
static unsigned				sErrorHandlerStackSkip = 0;


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
	NSString		*activeScript = nil;
	
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
	activeScript = [[OOJSScript currentlyRunningScript] displayName];
	if (activeScript == nil)  activeScript = @"<unidentified script>";
	OOLog(messageClass, @"%@ JavaScript %@ (%@): %@", highlight, severity, activeScript, messageText);
	
	if (sErrorHandlerStackSkip == 0)
	{
		// Second line: where error occured, and line if provided. (The line is only provided for compile-time errors, not run-time errors.)
		if ([lineBuf length] != 0)
		{
			OOLog(messageClass, @"      %s, line %d: %@", report->filename, report->lineno, lineBuf);
		}
		else
		{
			OOLog(messageClass, @"      %s, line %d.", report->filename, report->lineno);
		}
	}
	
#if OOJSENGINE_MONITOR_SUPPORT
	JSExceptionState *exState = JS_SaveExceptionState(context);
	[[OOJavaScriptEngine sharedEngine] sendMonitorError:report
											withMessage:messageText
											  inContext:context];
	 JS_RestoreExceptionState(context, exState);
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
	
#ifndef NDEBUG
	// This one is causing trouble for the Linux crowd. :-/
	if (!JS_CStringsAreUTF8())
	{
		OOLog(@"script.javaScript.init.badSpiderMonkey", @"SpiderMonkey (libjs/libmozjs) must be built with the JS_C_STRINGS_ARE_UTF8 macro defined. Additionally, JS_THREADSAFE must be undefined and MOZILLA_1_8_BRANCH must be undefined.");
		exit(EXIT_FAILURE);
	}
#endif
	
	self = [super init];
	
	assert(sizeof(jschar) == sizeof(unichar));

	// set up global JS variables, including global and custom objects

	// initialize the JS run time, and return result in runtime
	runtime = JS_NewRuntime(8L * 1024L * 1024L);
	
	// if runtime creation failed, end the program here
	if (runtime == NULL)
	{
		OOLog(@"script.javaScript.init.error", @"***** FATAL ERROR: failed to create JavaScript %@.", @"runtime");
		exit(1);
	}

	// create a context and associate it with the JS run time
	mainContext = JS_NewContext(runtime, 8192);
	
	// if context creation failed, end the program here
	if (mainContext == NULL)
	{
		OOLog(@"script.javaScript.init.error", @"***** FATAL ERROR: failed to create JavaScript %@.", @"context");
		exit(1);
	}
	
	JS_SetOptions(mainContext, OOJSENGINE_CONTEXT_OPTIONS);
	JS_SetVersion(mainContext, OOJSENGINE_JSVERSION);
	
#if JS_GC_ZEAL
	uint8_t gcZeal = [[NSUserDefaults standardUserDefaults] unsignedCharForKey:@"js-gc-zeal"];
	if (gcZeal > 0)
	{
		// Useful js-gc-zeal values are 0 (off), 1 and 2.
		OOLog(@"script.javaScript.debug.gcZeal", @"Setting JavaScript garbage collector zeal to %u.", gcZeal);
		JS_SetGCZeal(mainContext, gcZeal);
	}
#endif
	
	JS_SetErrorReporter(mainContext, ReportJSError);
	
	// Create the global object.
	CreateOOJSGlobal(mainContext, &globalObject);

	// Initialize the built-in JS objects and the global object.
	JS_InitStandardClasses(mainContext, globalObject);
	RegisterStandardObjectConverters(mainContext);
	
	SetUpOOJSGlobal(mainContext, globalObject);
	
	// Initialize Oolite classes.
	InitOOJSMissionVariables(mainContext, globalObject);
	InitOOJSMission(mainContext, globalObject);
	InitOOJSOolite(mainContext, globalObject);
	InitOOJSVector(mainContext, globalObject);
	InitOOJSQuaternion(mainContext, globalObject);
	InitOOJSSystem(mainContext, globalObject);
	InitOOJSEntity(mainContext, globalObject);
	InitOOJSShip(mainContext, globalObject);
	InitOOJSStation(mainContext, globalObject);
	InitOOJSPlayer(mainContext, globalObject);
	InitOOJSPlayerShip(mainContext, globalObject);
	InitOOJSSun(mainContext, globalObject);
	InitOOJSPlanet(mainContext, globalObject);
	InitOOJSScript(mainContext, globalObject);
	InitOOJSTimer(mainContext, globalObject);
	InitOOJSClock(mainContext, globalObject);
	InitOOJSWorldScripts(mainContext, globalObject);
	InitOOJSSound(mainContext, globalObject);
	InitOOJSSoundSource(mainContext, globalObject);
	InitOOJSSpecialFunctions(mainContext, globalObject);
	InitOOJSSystemInfo(mainContext, globalObject);
	InitOOJSEquipmentInfo(mainContext, globalObject);
	InitOOJSShipGroup(mainContext, globalObject);
	
	sSharedEngine = self;
	
	// Run prefix script.
	[OOJSScript nonLegacyScriptFromFileNamed:@"oolite-global-prefix.js"
								  properties:[NSDictionary dictionaryWithObject:JSSpecialFunctionsObjectWrapper(mainContext)
																		 forKey:@"special"]];
	
	OOLog(@"script.javaScript.init.success", @"Set up JavaScript context.");
	
	return self;
}


- (void) dealloc
{
	unsigned					i;
	
	sSharedEngine = nil;
	
	for (i = 0; i != contextPoolCount; ++i)
	{
		JS_DestroyContext(contextPool[i]);
	}
	JS_DestroyContext(mainContext);
	JS_DestroyRuntime(runtime);
	
	[super dealloc];
}


- (JSObject *) globalObject
{
	return globalObject;
}


- (BOOL) callJSFunction:(JSFunction *)function
			  forObject:(JSObject *)jsThis
				   argc:(uintN)argc
				   argv:(jsval *)argv
				 result:(jsval *)outResult
{
	JSContext					*context = NULL;
	BOOL						result;
	
	context = [self acquireContext];
	result = JS_CallFunction(context, jsThis, function, argc, argv, outResult);
	JS_ReportPendingException(context);
	[self releaseContext:context];
	
	return result;
}


- (JSContext *)acquireContext
{
	JSContext				*context = NULL;
	
	if (!mainContextInUse)
	{
		/*	Favour the main context.
			There's overhead to using objects from a different context. By
			having one preferred context, most objects will belong to that
			context and that context will be the one used in the common case
			of only one script running.
		*/
		mainContextInUse = YES;
		context = mainContext;
	}
	else if (contextPoolCount != 0)
	{
		context = contextPool[--contextPoolCount];
	}
	else
	{
		OOLog(@"script.javaScript.context.create", @"Creating JS context.");
		
		context = JS_NewContext(runtime, 8192);
		// if context creation failed, end the program here
		if (context == NULL)
		{
			OOLog(@"script.javaScript.error", @"***** FATAL ERROR: failed to create JavaScript %@.", @"context");
			exit(1);
		}
		
		JS_SetOptions(context, OOJSENGINE_CONTEXT_OPTIONS);
		JS_SetVersion(context, OOJSENGINE_JSVERSION);
		JS_SetErrorReporter(context, ReportJSError);
		JS_SetGlobalObject(context, globalObject);
	}
	
	return context;
}


- (void)releaseContext:(JSContext *)context
{
	if (context == NULL)  return;
	
	if (context == mainContext)
	{
		mainContextInUse = NO;
	}
	else if (contextPoolCount < kOOJavaScriptEngineContextPoolCount)
	{
		contextPool[contextPoolCount++] = context;
	}
	else
	{
		OOLog(@"script.javaScript.context.destroy", @"Destroying JS context.");
		
		JS_DestroyContextMaybeGC(context);
	}
}


- (BOOL) addGCRoot:(void *)rootPtr
			 named:(const char *)name
{
	BOOL					result;
	JSContext				*context = NULL;
	
	context = [self acquireContext];
	result = JS_AddNamedRoot(context, rootPtr, name);
	[self releaseContext:context];
	return result;
}


- (void) removeGCRoot:(void *)rootPtr
{
	JSContext				*context = NULL;
	
	context = [self acquireContext];
	JS_RemoveRoot(context, rootPtr);
	[self releaseContext:context];
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
	if ([monitor respondsToSelector:@selector(jsEngine:context:error:stackSkip:withMessage:)])
	{
		[monitor jsEngine:self context:theContext error:errorReport stackSkip:sErrorHandlerStackSkip withMessage:message];
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


static NSString *CallerPrefix(NSString *scriptClass, NSString *function)
{
	if (function == nil)  return @"";
	if (scriptClass == nil)  return [function stringByAppendingString:@": "];
	return  [NSString stringWithFormat:@"%@.%@: ", scriptClass, function];
}


void OOReportJSError(JSContext *context, NSString *format, ...)
{
	va_list					args;
	
	va_start(args, format);
	OOReportJSErrorWithArguments(context, format, args);
	va_end(args);
}


void OOReportJSErrorForCaller(JSContext *context, NSString *scriptClass, NSString *function, NSString *format, ...)
{
	va_list					args;
	NSString				*msg = nil;
	
	va_start(args, format);
	msg = [[NSString alloc] initWithFormat:format arguments:args];
	va_end(args);
	
	OOReportJSError(context, @"%@%@", CallerPrefix(scriptClass, function), msg);
	[msg release];
}


void OOReportJSErrorWithArguments(JSContext *context, NSString *format, va_list args)
{
	NSString				*msg = nil;
	
	msg = [[NSString alloc] initWithFormat:format arguments:args];
	JS_ReportError(context, "%s", [msg UTF8String]);
	[msg release];
}


void OOReportJSWarning(JSContext *context, NSString *format, ...)
{
	va_list					args;
	
	va_start(args, format);
	OOReportJSWarningWithArguments(context, format, args);
	va_end(args);
}


void OOReportJSWarningForCaller(JSContext *context, NSString *scriptClass, NSString *function, NSString *format, ...)
{
	va_list					args;
	NSString				*msg = nil;
	
	va_start(args, format);
	msg = [[NSString alloc] initWithFormat:format arguments:args];
	va_end(args);
	
	OOReportJSWarning(context, @"%@%@", CallerPrefix(scriptClass, function), msg);
	[msg release];
}


void OOReportJSWarningWithArguments(JSContext *context, NSString *format, va_list args)
{
	NSString				*msg = nil;
	
	msg = [[NSString alloc] initWithFormat:format arguments:args];
	JS_ReportWarning(context, "%s", [msg UTF8String]);
	[msg release];
}


void OOReportJSBadPropertySelector(JSContext *context, NSString *className, jsint selector)
{
	OOReportJSError(context, @"Internal error: bad property identifier %i in property accessor for class %@.", selector, className);
}


void OOReportJSBadArguments(JSContext *context, NSString *scriptClass, NSString *function, uintN argc, jsval *argv, NSString *message, NSString *expectedArgsDescription)
{
	if (message == nil)  message = @"Invalid arguments";
	message = [NSString stringWithFormat:@"%@ %@", message, [NSString stringWithJavaScriptParameters:argv count:argc inContext:context]];
	if (expectedArgsDescription != nil)  message = [NSString stringWithFormat:@"%@ -- expected %@", message, expectedArgsDescription];
	
	OOReportJSErrorForCaller(context, scriptClass, function, @"%@.", message);
}


void OOSetJSWarningOrErrorStackSkip(unsigned skip)
{
	sErrorHandlerStackSkip = skip;
}


BOOL NumberFromArgumentList(JSContext *context, NSString *scriptClass, NSString *function, uintN argc, jsval *argv, double *outNumber, uintN *outConsumed)
{
	if (NumberFromArgumentListNoError(context, argc, argv, outNumber, outConsumed))  return YES;
	else
	{
		OOReportJSBadArguments(context, scriptClass, function, argc, argv,
									   @"Expected number, got", NULL);
		return NO;
	}
}


BOOL NumberFromArgumentListNoError(JSContext *context, uintN argc, jsval *argv, double *outNumber, uintN *outConsumed)
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
		return NO;
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


BOOL JSGetNSProperty(JSContext *context, JSObject *object, NSString *name, jsval *value)
{
	jschar					*buffer = NULL;
	size_t					length;
	BOOL					OK = NO;
	BOOL					tempCtxt = NO;
	
	if (context == NULL)
	{
		context = [[OOJavaScriptEngine sharedEngine] acquireContext];
		tempCtxt = YES;
	}
	if (ExtractString(name, &buffer, &length))
	{
		OK = JS_GetUCProperty(context, object, buffer, length, value);
		free(buffer);
	}
	
	if (tempCtxt)  [[OOJavaScriptEngine sharedEngine] releaseContext:context];
	return OK;
}


BOOL JSSetNSProperty(JSContext *context, JSObject *object, NSString *name, jsval *value)
{
	jschar					*buffer = NULL;
	size_t					length;
	BOOL					OK = NO;
	BOOL					tempCtxt = NO;
	
	if (context == NULL)
	{
		context = [[OOJavaScriptEngine sharedEngine] acquireContext];
		tempCtxt = YES;
	}
	if (ExtractString(name, &buffer, &length))
	{
		OK = JS_SetUCProperty(context, object, buffer, length, value);
		free(buffer);
	}
	
	if (tempCtxt)  [[OOJavaScriptEngine sharedEngine] releaseContext:context];
	return OK;
}


BOOL JSDefineNSProperty(JSContext *context, JSObject *object, NSString *name, jsval value, JSPropertyOp getter, JSPropertyOp setter, uintN attrs)
{
	jschar					*buffer = NULL;
	size_t					length;
	BOOL					OK = NO;
	BOOL					tempCtxt = NO;
	
	if (context == NULL)
	{
		context = [[OOJavaScriptEngine sharedEngine] acquireContext];
		tempCtxt = YES;
	}
	if (ExtractString(name, &buffer, &length))
	{
		OK = JS_DefineUCProperty(context, object, buffer, length, value, getter, setter, attrs);
		free(buffer);
	}
	
	if (tempCtxt)  [[OOJavaScriptEngine sharedEngine] releaseContext:context];
	return OK;
}


static JSObject *JSArrayFromNSArray(JSContext *context, NSArray *array)
{
	JSObject				*result = NULL;
	unsigned				i;
	unsigned				count;
	jsval					value;
	BOOL					OK = YES;
	
	if (array == nil)  return NULL;
	
	NS_DURING
		result = JS_NewArrayObject(context, 0, NULL);
		if (result == NULL)  NS_VALUERETURN(NULL, JSObject *);
		
		count = [array count];
		for (i = 0; i != count; ++i)
		{
			value = [[array objectAtIndex:i] javaScriptValueInContext:context];
			OK = JS_SetElement(context, result, i, &value);
			if (!OK)  NS_VALUERETURN(NULL, JSObject *);
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
	JSObject				*result = NULL;
	BOOL					OK = YES;
	NSEnumerator			*keyEnum = nil;
	id						key = nil;
	jsval					value;
	jsint					index;
	
	if (dictionary == nil)  return NULL;
	
	NS_DURING
		result = JS_NewObject(context, NULL, NULL, NULL);	// create object of class Object
		if (result == NULL)  NS_VALUERETURN(NULL, JSObject *);
		
		for (keyEnum = [dictionary keyEnumerator]; (key = [keyEnum nextObject]); )
		{
			if ([key isKindOfClass:[NSString class]] && [key length] != 0)
			{
				value = [[dictionary objectForKey:key] javaScriptValueInContext:context];
				if (value != JSVAL_VOID)
				{
					OK = JSSetNSProperty(context, result, key, &value);
					if (!OK)  NS_VALUERETURN(NULL, JSObject *);
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
						if (!OK)  NS_VALUERETURN(NULL, JSObject *);
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

@end


@implementation OOJSValue

+ (id) valueWithJSValue:(jsval)value inContext:(JSContext *)context
{
	return [[[self alloc] initWithJSValue:value inContext:context] autorelease];
}


+ (id) valueWithJSObject:(JSObject *)object inContext:(JSContext *)context
{
	return [[[self alloc] initWithJSObject:object inContext:context] autorelease];
}


- (id) initWithJSValue:(jsval)value inContext:(JSContext *)context
{
	self = [super init];
	if (self != nil)
	{
		BOOL tempCtxt = NO;
		if (context == NULL)
		{
			context = [[OOJavaScriptEngine sharedEngine] acquireContext];
			tempCtxt = YES;
		}
		
		_val = value;
		JS_AddNamedRoot(context, &_val, "OOJSValue");
		
		if (tempCtxt)  [[OOJavaScriptEngine sharedEngine] releaseContext:context];
	}
	return self;
}


- (id) initWithJSObject:(JSObject *)object inContext:(JSContext *)context
{
	return [self initWithJSValue:OBJECT_TO_JSVAL(object) inContext:context];
}


- (void) dealloc
{
	JSContext *context = [[OOJavaScriptEngine sharedEngine] acquireContext];
	JS_RemoveRoot(context, &_val);
	[[OOJavaScriptEngine sharedEngine] releaseContext:context];
	
	[super dealloc];
}


- (jsval)javaScriptValueInContext:(JSContext *)context
{
	return _val;
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
	BOOL					tempCtxt = NO;
	
	//make sure to return a string -  if this function returns nil we can get a CTD!
	if (JSVAL_IS_VOID(value))  return @"undefined";
	if (JSVAL_IS_NULL(value))  return @"null";
	
	if (context == NULL)
	{
		context = [[OOJavaScriptEngine sharedEngine] acquireContext];
		tempCtxt = YES;
	}
	string = JS_ValueToString(context, value);	// Calls the value's toString method if needed.
	if (tempCtxt)  [[OOJavaScriptEngine sharedEngine] releaseContext:context];
	
	return [NSString stringWithJavaScriptString:string];
}


+ (id)stringWithJavaScriptParameters:(jsval *)params count:(uintN)count inContext:(JSContext *)context
{
	if (params == NULL && count != 0) return nil;
	
	uintN					i;
	jsval					val;
	NSMutableString			*result = [NSMutableString stringWithString:@"("];
	NSString				*valString = nil;
	
	for (i = 0; i < count; ++i)
	{
		if (i != 0)  [result appendString:@", "];
		
		val = params[i];
		valString = [self stringWithJavaScriptValue:val inContext:context];
		if (JSVAL_IS_STRING(val))
		{
			[result appendFormat:@"\"%@\"", valString];
		}
		else if (JSVAL_IS_OBJECT(val) && JS_IsArrayObject(context, JSVAL_TO_OBJECT(val)))
		{
			[result appendFormat:@"[%@]", valString ];
		}
		else
		{
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
	if (length == 0)  return JS_GetEmptyStringValue(context);
	
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
		if (result == nil)  result = [[element mutableCopy] autorelease];
		else
		{
			if (separator != nil)  [result appendString:separator];
			[result appendString:element];
		}
	}
	
	return result;
}


- (NSString *)escapedForJavaScriptLiteral
{
	NSMutableString			*result = nil;
	unsigned				i, length;
	unichar					c;
	NSAutoreleasePool		*pool = nil;
	
	length = [self length];
	result = [NSMutableString stringWithCapacity:[self length]];
	
	// Not hugely efficient.
	pool = [[NSAutoreleasePool alloc] init];
	for (i = 0; i != length; ++i)
	{
		c = [self characterAtIndex:i];
		switch (c)
		{
			case '\\':
				[result appendString:@"\\\\"];
				break;
				
			case '\b':
				[result appendString:@"\\b"];
				break;
				
			case '\f':
				[result appendString:@"\\f"];
				break;
				
			case '\n':
				[result appendString:@"\\n"];
				break;
				
			case '\r':
				[result appendString:@"\\r"];
				break;
				
			case '\t':
				[result appendString:@"\\t"];
				break;
				
			case '\v':
				[result appendString:@"\\v"];
				break;
				
			case '\'':
				[result appendString:@"\\\'"];
				break;
				
			case '\"':
				[result appendString:@"\\\""];
				break;
			
			default:
				[result appendString:[NSString stringWithCharacters:&c length:1]];
		}
	}
	[pool release];
	return result;
}

@end


#ifndef NDEBUG

// For use in debugger
const char *JSValueToStrDbg(jsval val)
{
	return [JSValToNSString(NULL, val) UTF8String];
}


const char *JSObjectToStrDbg(JSObject *obj)
{
	return [JSValToNSString(NULL, OBJECT_TO_JSVAL(obj)) UTF8String];
}


const char *JSValueTypeDbg(jsval val)
{
	if (JSVAL_IS_INT(val))  return "integer";
	if (JSVAL_IS_DOUBLE(val))  return "double";
	if (JSVAL_IS_STRING(val))  return "string";
	if (JSVAL_IS_BOOLEAN(val))  return "boolean";
	if (JSVAL_IS_NULL(val))  return "null";
	if (JSVAL_IS_VOID(val))  return "void";
	if (JSVAL_IS_OBJECT(val))  return JS_GetClass(JSVAL_TO_OBJECT(val))->name;
	return "unknown";
}

#endif


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


void JSObjectWrapperFinalize(JSContext *context, JSObject *this)
{
	[(id)JS_GetPrivate(context, this) release];
	JS_SetPrivate(context, this, nil);
}


JSBool JSObjectWrapperEquality(JSContext *context, JSObject *this, jsval value, JSBool *outEqual)
{
	id						thisObj, thatObj;
	
	thisObj = JSObjectToObject(context, this);
	thatObj = JSValueToObject(context, value);
	
	*outEqual = [thisObj isEqual:thatObj];
	return YES;
}


BOOL JSFunctionPredicate(Entity *entity, void *parameter)
{
	JSFunctionPredicateParameter	*param = parameter;
	jsval							args[1];
	jsval							rval = JSVAL_VOID;
	JSBool							result = NO;
	
	if (param->errorFlag)  return NO;
	
	args[0] = [entity javaScriptValueInContext:param->context];
	if (JS_CallFunction(param->context, param->jsThis, param->function, 1, args, &rval))
	{
		if (!JS_ValueToBoolean(param->context, rval, &result))  result = NO;
		if (JS_IsExceptionPending(param->context))
		{
			JS_ReportPendingException(param->context);
			param->errorFlag = YES;
		}
	}
	
	return result;
}


BOOL JSEntityIsJavaScriptVisiblePredicate(Entity *entity, void *parameter)
{
	return [entity isVisibleToScripts];
}


BOOL JSEntityIsJavaScriptSearchablePredicate(Entity *entity, void *parameter)
{
	if (![entity isVisibleToScripts])  return NO;
	if ([entity isShip])
	{
		if ([entity isSubEntity])  return NO;
		if ([entity status] == STATUS_COCKPIT_DISPLAY)  return NO;	// Demo ship
		return YES;
	}
	else if ([entity isPlanet])
	{
		switch ([(PlanetEntity *)entity planetType])
		{
			case PLANET_TYPE_MOON:
			case PLANET_TYPE_GREEN:
			case PLANET_TYPE_SUN:
				return YES;
				
			case PLANET_TYPE_ATMOSPHERE:
			case PLANET_TYPE_MINIATURE:
				return NO;
		}
	}
	
	return YES;	// would happen if we added a new script-visible class
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


id JSValueToObjectOfClass(JSContext *context, jsval value, Class requiredClass)
{
	id result = JSValueToObject(context, value);
	if (![result isKindOfClass:requiredClass])  result = nil;
	return result;
}


id JSObjectToObjectOfClass(JSContext *context, JSObject *object, Class requiredClass)
{
	id result = JSObjectToObject(context, object);
	if (![result isKindOfClass:requiredClass])  result = nil;
	return result;
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
