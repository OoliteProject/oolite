/*

OOJavaScriptEngine.m

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

#import "OOJavaScriptEngine.h"
#import "OOJSScript.h"
#import "jsdbgapi.h"

#import "OOCollectionExtractors.h"
#import "Universe.h"
#import "OOPlanetEntity.h"
#import "NSStringOOExtensions.h"
#import "OOWeakReference.h"
#import "EntityOOJavaScriptExtensions.h"
#import "ResourceManager.h"
#import "NSNumberOOExtensions.h"

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
#import "OOJSManifest.h"
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

#import "OOProfilingStopwatch.h"
#import "OOLoggingExtended.h"

#import <stdlib.h>


#if OO_NEW_JS
#define OOJSENGINE_JSVERSION		JSVERSION_ECMA_5
#ifdef DEBUG
#define JIT_OPTIONS					0
#else
#define JIT_OPTIONS					JSOPTION_JIT | JSOPTION_METHODJIT | JSOPTION_PROFILING
#endif
#define OOJSENGINE_CONTEXT_OPTIONS	JSOPTION_VAROBJFIX | JSOPTION_STRICT | JSOPTION_RELIMIT | JSOPTION_ANONFUNFIX | JIT_OPTIONS
#else
#define OOJSENGINE_JSVERSION		JSVERSION_1_7
#define OOJSENGINE_CONTEXT_OPTIONS	JSOPTION_VAROBJFIX | JSOPTION_STRICT | JSOPTION_NATIVE_BRANCH_CALLBACK
#endif


#define OOJS_STACK_SIZE			8192


#if !OOLITE_NATIVE_EXCEPTIONS
#warning Native exceptions apparently not available. JavaScript functions are not exception-safe.
#endif
#if defined(JS_THREADSAFE) && !OO_NEW_JS
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
static id JSStringConverter(JSContext *context, JSObject *object);
static id JSNumberConverter(JSContext *context, JSObject *object);


static void ReportJSError(JSContext *context, const char *message, JSErrorReport *report)
{
	NSString		*severity = @"error";
	NSString		*messageText = nil;
	NSString		*lineBuf = nil;
	NSString		*messageClass = nil;
	NSString		*highlight = @"*****";
	NSString		*activeScript = nil;
	
	OOJSPauseTimeLimiter();
	
	jschar empty[1] = { 0 };
	JSErrorReport blankReport =
	{
		.filename = "<unspecified file>",
		.linebuf = "",
		.uclinebuf = empty,
		.uctokenptr = empty,
		.ucmessage = empty
	};
	if (EXPECT_NOT(report == NULL))  report = &blankReport;
	if (EXPECT_NOT(message == NULL || *message == '\0'))  message = "<unspecified error>";
	
	// Type of problem: error, warning or exception? (Strict flag wilfully ignored.)
	if (report->flags & JSREPORT_EXCEPTION) severity = @"exception";
	else if (report->flags & JSREPORT_WARNING)
	{
		severity = @"warning";
		highlight = @"-----";
	}
	
	// The error message itself
	messageText = [NSString stringWithUTF8String:message];
	
	// Get offending line, if present, and trim trailing line breaks
	lineBuf = [NSString stringWithUTF16String:report->uclinebuf];
	while ([lineBuf hasSuffix:@"\n"] || [lineBuf hasSuffix:@"\r"])  lineBuf = [lineBuf substringToIndex:[lineBuf length] - 1];
	
	// Get string for error number, for useful log message classes
	NSDictionary *errorNames = [ResourceManager dictionaryFromFilesNamed:@"javascript-errors.plist" inFolder:@"Config" andMerge:YES];
	NSString *errorNumberStr = [NSString stringWithFormat:@"%u", report->errorNumber];
	NSString *errorName = [errorNames oo_stringForKey:errorNumberStr];
	if (errorName == nil)  errorName = errorNumberStr;
	
	// Log message class
	messageClass = [NSString stringWithFormat:@"script.javaScript.%@.%@", severity, errorName];
	
	// First line: problem description
	
	// avoid windows DEP exceptions!
	OOJSScript *thisScript = [[OOJSScript currentlyRunningScript] weakRetain];
	activeScript = [[thisScript weakRefUnderlyingObject] displayName];
	[thisScript release];
	
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
	
#ifndef NDEBUG
	OOJSDumpStack([NSString stringWithFormat:@"script.javaScript.stackTrace.%@", severity], context);
#endif
	
#if OOJSENGINE_MONITOR_SUPPORT
	JSExceptionState *exState = JS_SaveExceptionState(context);
	[[OOJavaScriptEngine sharedEngine] sendMonitorError:report
											withMessage:messageText
											  inContext:context];
	JS_RestoreExceptionState(context, exState);
#endif
	
	OOJSResumeTimeLimiter();
}


//===========================================================================
// JavaScript engine initialisation and shutdown
//===========================================================================

@implementation OOJavaScriptEngine

+ (OOJavaScriptEngine *)sharedEngine
{
	if (sSharedEngine == nil)  sSharedEngine =[[self alloc] init];
	
	return sSharedEngine;
}


- (void) runMissionCallback
{
	MissionRunCallback();
}


- (id) init
{
	assert(sSharedEngine == nil);
	
#if OO_NEW_JS
	JS_SetCStringsAreUTF8();
#else
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
	
	JS_SetContextCallback(runtime, OOJSContextCallback);

	// create a context and associate it with the JS run time
	mainContext = JS_NewContext(runtime, OOJS_STACK_SIZE);
	
	// if context creation failed, end the program here
	if (mainContext == NULL)
	{
		OOLog(@"script.javaScript.init.error", @"***** FATAL ERROR: failed to create JavaScript %@.", @"context");
		exit(1);
	}
	
	JS_BeginRequest(mainContext);
	
	JS_SetOptions(mainContext, OOJSENGINE_CONTEXT_OPTIONS);
	JS_SetVersion(mainContext, OOJSENGINE_JSVERSION);
	
#if JS_GC_ZEAL
	uint8_t gcZeal = [[NSUserDefaults standardUserDefaults]  oo_unsignedCharForKey:@"js-gc-zeal"];
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
	InitOOJSManifest(mainContext, globalObject);
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
	
	JS_EndRequest(mainContext);
	
	sSharedEngine = self;
	
	// Run prefix script.
	[OOJSScript JSScriptFromFileNamed:@"oolite-global-prefix.js"
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


- (BOOL) callJSFunction:(jsval)function
			  forObject:(JSObject *)jsThis
				   argc:(uintN)argc
				   argv:(jsval *)argv
				 result:(jsval *)outResult
{
	JSContext					*context = NULL;
	BOOL						result;
	
	NSAssert(JSVAL_IS_OBJECT(function) && JS_ObjectIsFunction(context, JSVAL_TO_OBJECT(function)), @"Attempt to call a JavaScript value that isn't a function.");
	
	context = [self acquireContext];
	JS_BeginRequest(context);
	
	OOJSStartTimeLimiter();
	result = JS_CallFunctionValue(context, jsThis, function, argc, argv, outResult);
	OOJSStopTimeLimiter();
	
	JS_ReportPendingException(context);
	JS_EndRequest(context);
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
		
		context = JS_NewContext(runtime, OOJS_STACK_SIZE);
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


- (void) removeGCObjectRoot:(JSObject **)rootPtr
{
	JSContext				*context = NULL;
	
	context = [self acquireContext];
	JS_BeginRequest(context);
	JS_RemoveObjectRoot(context, rootPtr);
	JS_EndRequest(context);
	[self releaseContext:context];
}


- (void) removeGCValueRoot:(jsval *)rootPtr
{
	JSContext				*context = NULL;
	
	context = [self acquireContext];
	JS_BeginRequest(context);
	JS_RemoveValueRoot(context, rootPtr);
	JS_EndRequest(context);
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


#ifndef NDEBUG

void OOJSDumpStack(NSString *logMessageClass, JSContext *context)
{
	if (!OOLogWillDisplayMessagesInClass(logMessageClass))  return;
	
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	NS_DURING
		JSStackFrame *frame = NULL;
		unsigned idx = 0;
		while (JS_FrameIterator(context, &frame) != NULL)
		{
			JSScript *script = JS_GetFrameScript(context, frame);
			NSString *desc = nil;
			
			if (script != NULL)
			{
				const char *fileName = JS_GetScriptFilename(context, script);
				jsbytecode *PC = JS_GetFramePC(context, frame);
				unsigned lineNo = JS_PCToLineNumber(context, script, PC);
				
				NSString *fileNameObj = [NSString stringWithUTF8String:fileName];
				if (fileNameObj == nil)  fileNameObj = [NSString stringWithCString:fileName encoding:NSISOLatin1StringEncoding];
				NSString *shortFileName = [fileNameObj lastPathComponent];
				if (![[shortFileName lowercaseString] isEqualToString:@"script.js"])  fileNameObj = shortFileName;
				
				NSString *funcDesc = nil;
				JSFunction *function = JS_GetFrameFunction(context, frame);
				if (function != NULL)
				{
					JSString *funcName = JS_GetFunctionId(function);
					if (funcName != NULL)
					{
						funcDesc = [NSString stringWithJavaScriptString:funcName];
						if (!JS_IsConstructorFrame(context, frame))
						{
							funcDesc = [funcDesc stringByAppendingString:@"()"];
						}
						else
						{
							funcDesc = [NSString stringWithFormat:@"new %@()", funcDesc];
						}
						
					}
					else
					{
						funcDesc = @"<anonymous function>";
					}
				}
				else
				{
					funcDesc = @"<not a function frame>";
				}
				
				desc = [NSString stringWithFormat:@"%@:%u %@", fileNameObj, lineNo, funcDesc];
			}
			else if (JS_IsDebuggerFrame(context, frame))
			{
				desc = @"<debugger frame>";
			}
			else
			{
				desc = @"<Oolite native>";
			}
			
			OOLog(@"js.stackFrame", @"%4u %@", idx, desc);
			
			idx++;
		}
	NS_HANDLER
		OOLog(kOOLogException, @"Exception during JavaScript stack trace: %@:%@", [localException name], [localException reason]);
	NS_ENDHANDLER
	
	[pool release];
}

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
	
	NS_DURING
		va_start(args, format);
		msg = [[NSString alloc] initWithFormat:format arguments:args];
		va_end(args);
		
		OOReportJSError(context, @"%@%@", CallerPrefix(scriptClass, function), msg);
	NS_HANDLER
		// Squash any secondary errors during error handling.
	NS_ENDHANDLER
	[msg release];
}


void OOReportJSErrorWithArguments(JSContext *context, NSString *format, va_list args)
{
	NSString				*msg = nil;
	
	NS_DURING
		msg = [[NSString alloc] initWithFormat:format arguments:args];
		JS_ReportError(context, "%s", [msg UTF8String]);
	NS_HANDLER
		// Squash any secondary errors during error handling.
	NS_ENDHANDLER
	[msg release];
}


#if OOLITE_NATIVE_EXCEPTIONS

void OOJSReportWrappedException(JSContext *context, id exception)
{
	if (!JS_IsExceptionPending(context))
	{
		if ([exception isKindOfClass:[NSException class]])  OOReportJSError(context, @"Native exception: %@", [exception reason]);
		else  OOReportJSError(context, @"Unidentified native exception");
	}
	// Else, let the pending exception propagate.
}


#ifndef NDEBUG

void OOJSUnreachable(const char *function, const char *file, unsigned line)
{
	OOLog(@"fatal.unreachable", @"Supposedly unreachable statement reached in %s (%@:%u) -- terminating.", function, OOLogAbbreviatedFileName(file), line);
	abort();
}

#endif
#endif


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
	
	NS_DURING
		va_start(args, format);
		msg = [[NSString alloc] initWithFormat:format arguments:args];
		va_end(args);
		
		OOReportJSWarning(context, @"%@%@", CallerPrefix(scriptClass, function), msg);
	NS_HANDLER
	// Squash any secondary errors during error handling.
	NS_ENDHANDLER
	[msg release];
}


void OOReportJSWarningWithArguments(JSContext *context, NSString *format, va_list args)
{
	NSString				*msg = nil;
	
	NS_DURING
		msg = [[NSString alloc] initWithFormat:format arguments:args];
		JS_ReportWarning(context, "%s", [msg UTF8String]);
	NS_HANDLER
	// Squash any secondary errors during error handling.
	NS_ENDHANDLER
	[msg release];
}


void OOReportJSBadPropertySelector(JSContext *context, NSString *className, jsint selector)
{
	// FIXME: after API upgrade, should take a jsid and decode it.
	OOReportJSError(context, @"Internal error: bad property identifier %i in property accessor for class %@.", selector, className);
}


void OOReportJSBadArguments(JSContext *context, NSString *scriptClass, NSString *function, uintN argc, jsval *argv, NSString *message, NSString *expectedArgsDescription)
{
	NS_DURING
		if (message == nil)  message = @"Invalid arguments";
		message = [NSString stringWithFormat:@"%@ %@", message, [NSString stringWithJavaScriptParameters:argv count:argc inContext:context]];
		if (expectedArgsDescription != nil)  message = [NSString stringWithFormat:@"%@ -- expected %@", message, expectedArgsDescription];
		
		OOReportJSErrorForCaller(context, scriptClass, function, @"%@.", message);
	NS_HANDLER
	// Squash any secondary errors during error handling.
	NS_ENDHANDLER
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
	OOJS_PROFILE_ENTER
	
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
	
	OOJS_PROFILE_EXIT
}


static BOOL ExtractString(NSString *string, jschar **outString, size_t *outLength)
{
	OOJS_PROFILE_ENTER
	
	assert(outString != NULL && outLength != NULL);
	assert(sizeof (unichar) == sizeof (jschar));	// Should both be 16 bits
	
	*outLength = [string length];
	if (*outLength == 0)  return NO;	// nil/empty strings not accepted.
	
	*outString = malloc(sizeof (unichar) * *outLength);
	if (*outString == NULL)  return NO;
	
	[string getCharacters:(unichar *)*outString];
	return YES;
	
	OOJS_PROFILE_EXIT
}


BOOL JSGetNSProperty(JSContext *context, JSObject *object, NSString *name, jsval *value)
{
	OOJS_PROFILE_ENTER
	
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
	
	OOJS_PROFILE_EXIT
}


BOOL JSSetNSProperty(JSContext *context, JSObject *object, NSString *name, jsval *value)
{
	OOJS_PROFILE_ENTER
	
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
	
	OOJS_PROFILE_EXIT
}


BOOL JSDefineNSProperty(JSContext *context, JSObject *object, NSString *name, jsval value, JSPropertyOp getter, JSPropertyOp setter, uintN attrs)
{
	OOJS_PROFILE_ENTER
	
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
	
	OOJS_PROFILE_EXIT
}


static JSObject *JSArrayFromNSArray(JSContext *context, NSArray *array)
{
	OOJS_PROFILE_ENTER
	
	JSObject				*result = NULL;
	unsigned				i;
	unsigned				count;
	jsval					value;
	
	if (array == nil)  return NULL;
	
	NS_DURING
		result = JS_NewArrayObject(context, 0, NULL);
		if (result != NULL)
		{
			count = [array count];
			for (i = 0; i != count; ++i)
			{
				value = [[array objectAtIndex:i] javaScriptValueInContext:context];
				BOOL OK = JS_SetElement(context, result, i, &value);
				
				if (EXPECT_NOT(!OK))
				{
					result = NULL;
					break;
				}
			}
		}
	NS_HANDLER
		result = NULL;
	NS_ENDHANDLER
	
	return (JSObject *)result;
	
	OOJS_PROFILE_EXIT
}


static BOOL JSNewNSArrayValue(JSContext *context, NSArray *array, jsval *value)
{
	OOJS_PROFILE_ENTER
	
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
	
	JS_LeaveLocalRootScopeWithResult(context, *value);
	return OK;
	
	OOJS_PROFILE_EXIT
}


/*	Convert an NSDictionary to a JavaScript Object.
	Only properties whose keys are either strings or non-negative NSNumbers,
	and	whose values have a non-void JS representation, are converted.
*/
static JSObject *JSObjectFromNSDictionary(JSContext *context, NSDictionary *dictionary)
{
	OOJS_PROFILE_ENTER
	
	JSObject				*result = NULL;
	BOOL					OK = YES;
	NSEnumerator			*keyEnum = nil;
	id						key = nil;
	jsval					value;
	jsint					index;
	
	if (dictionary == nil)  return NULL;
	
	NS_DURING
		result = JS_NewObject(context, NULL, NULL, NULL);	// create object of class Object
		if (result != NULL)
		{
			for (keyEnum = [dictionary keyEnumerator]; (key = [keyEnum nextObject]); )
			{
				if ([key isKindOfClass:[NSString class]] && [key length] != 0)
				{
					value = [[dictionary objectForKey:key] javaScriptValueInContext:context];
					if (!JSVAL_IS_VOID(value))
					{
						OK = JSSetNSProperty(context, result, key, &value);
						if (EXPECT_NOT(!OK))  break;
					}
				}
				else if ([key isKindOfClass:[NSNumber class]])
				{
					index = [key intValue];
					if (0 < index)
					{
						value = [[dictionary objectForKey:key] javaScriptValueInContext:context];
						if (!JSVAL_IS_VOID(value))
						{
							OK = JS_SetElement(context, (JSObject *)result, index, &value);
							if (EXPECT_NOT(!OK))  break;
						}
					}
				}
				
				if (EXPECT_NOT(!OK))  break;
			}
		}
	NS_HANDLER
		OK = NO;
	NS_ENDHANDLER
	
	if (EXPECT_NOT(!OK))
	{
		result = NULL;
	}
	
	return (JSObject *)result;
	
	OOJS_PROFILE_EXIT
}


static BOOL JSNewNSDictionaryValue(JSContext *context, NSDictionary *dictionary, jsval *value)
{
	OOJS_PROFILE_ENTER
	
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
	
	JS_LeaveLocalRootScopeWithResult(context, *value);
	return OK;
	
	OOJS_PROFILE_EXIT
}


@implementation NSObject (OOJavaScriptConversion)

- (jsval) javaScriptValueInContext:(JSContext *)context
{
	return JSVAL_VOID;
}


- (NSString *) jsClassName
{
	return nil;
}


- (NSString *) javaScriptDescription
{
	return [self javaScriptDescriptionWithClassName:[self jsClassName]];
}


- (NSString *) javaScriptDescriptionWithClassName:(NSString *)className
{
	OOJS_PROFILE_ENTER
	
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
	
	OOJS_PROFILE_EXIT
}


- (void) oo_clearJSSelf:(JSObject *)selfVal
{
	
}

@end


@implementation OOJSValue

+ (id) valueWithJSValue:(jsval)value inContext:(JSContext *)context
{
	OOJS_PROFILE_ENTER
	
	return [[[self alloc] initWithJSValue:value inContext:context] autorelease];
	
	OOJS_PROFILE_EXIT
}


+ (id) valueWithJSObject:(JSObject *)object inContext:(JSContext *)context
{
	OOJS_PROFILE_ENTER
	
	return [[[self alloc] initWithJSObject:object inContext:context] autorelease];
	
	OOJS_PROFILE_EXIT
}


- (id) initWithJSValue:(jsval)value inContext:(JSContext *)context
{
	OOJS_PROFILE_ENTER
	
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
		JS_BeginRequest(context);
		JS_AddNamedValueRoot(context, &_val, "OOJSValue");
		JS_EndRequest(context);
		
		if (tempCtxt)  [[OOJavaScriptEngine sharedEngine] releaseContext:context];
	}
	return self;
	
	OOJS_PROFILE_EXIT
}


- (id) initWithJSObject:(JSObject *)object inContext:(JSContext *)context
{
	return [self initWithJSValue:OBJECT_TO_JSVAL(object) inContext:context];
}


- (void) dealloc
{
	JSContext *context = [[OOJavaScriptEngine sharedEngine] acquireContext];
	JS_BeginRequest(context);
	JS_RemoveValueRoot(context, &_val);
	JS_EndRequest(context);
	[[OOJavaScriptEngine sharedEngine] releaseContext:context];
	
	[super dealloc];
}


- (jsval) javaScriptValueInContext:(JSContext *)context
{
	return _val;
}

@end


@implementation NSString (OOJavaScriptExtensions)

// Convert a JSString to an NSString.
+ (id) stringWithJavaScriptString:(JSString *)string
{
	OOJS_PROFILE_ENTER
	
	jschar					*chars = NULL;
	size_t					length;
	
	if (string == NULL)  return nil;
	
	chars = JS_GetStringChars(string);
	length = JS_GetStringLength(string);
	
	return [NSString stringWithCharacters:chars length:length];
	
	OOJS_PROFILE_EXIT
}


+ (id) stringWithJavaScriptValue:(jsval)value inContext:(JSContext *)context
{
	OOJS_PROFILE_ENTER
	
	// In some cases we didn't test the original stringWith... function for nil, causing difficult
	// to track crashes. We now have two similar functions: stringWith... which never returns nil and 
	// stringOrNilWith... (alias JSValToNSString) which can return nil and is used in most cases.

	if (JSVAL_IS_VOID(value))  return @"undefined";
	if (JSVAL_IS_NULL(value))  return @"null";

	return [self stringOrNilWithJavaScriptValue:value inContext:context];
	
	OOJS_PROFILE_EXIT
}


+ (id) stringOrNilWithJavaScriptValue:(jsval)value inContext:(JSContext *)context
{
	OOJS_PROFILE_ENTER
	
	JSString				*string = NULL;
	BOOL					tempCtxt = NO;

	if (JSVAL_IS_NULL(value) || JSVAL_IS_VOID(value))  return nil;
	
	if (context == NULL)
	{
		context = [[OOJavaScriptEngine sharedEngine] acquireContext];
		tempCtxt = YES;
	}
	string = JS_ValueToString(context, value);	// Calls the value's toString method if needed.
	if (tempCtxt)  [[OOJavaScriptEngine sharedEngine] releaseContext:context];
	
	return [NSString stringWithJavaScriptString:string];
	
	OOJS_PROFILE_EXIT
}


+ (id) stringWithJavaScriptParameters:(jsval *)params count:(uintN)count inContext:(JSContext *)context
{
	OOJS_PROFILE_ENTER
	
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
			[result appendString:valString]; //crash if valString is nil
		}
	}
	
	[result appendString:@")"];
	return result;
	
	OOJS_PROFILE_EXIT
}


- (jsval) javaScriptValueInContext:(JSContext *)context
{
	OOJS_PROFILE_ENTER
	
	size_t					length = [self length];
	unichar					*buffer = NULL;
	JSString				*string = NULL;
	
	if (length == 0)
	{
		JS_BeginRequest(context);
		jsval result = JS_GetEmptyStringValue(context);
		JS_EndRequest(context);
		return result;
	}
	else
	{
		buffer = malloc(length * sizeof *buffer);
		if (buffer == NULL) return JSVAL_VOID;
		
		[self getCharacters:buffer];
		
		JS_BeginRequest(context);
		string = JS_NewUCStringCopyN(context, buffer, length);
		JS_EndRequest(context);
		
		free(buffer);
		return STRING_TO_JSVAL(string);
	}
	
	OOJS_PROFILE_EXIT_JSVAL
}


+ (id) concatenationOfStringsFromJavaScriptValues:(jsval *)values count:(size_t)count separator:(NSString *)separator inContext:(JSContext *)context
{
	OOJS_PROFILE_ENTER
	
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
	
	OOJS_PROFILE_EXIT
}


- (NSString *)escapedForJavaScriptLiteral
{
	OOJS_PROFILE_ENTER
	
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
	
	OOJS_PROFILE_EXIT
}


- (NSString *) jsClassName
{
	return @"String";
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
	if (JSVAL_IS_OBJECT(val))  return OOJS_GetClass(NULL, JSVAL_TO_OBJECT(val))->name;	// Fun fact: although a context is required if JS_THREADSAFE is defined, it isn't actually used.
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
	OOJS_PROFILE_ENTER
	
	jsval					result;
	BOOL					isFloat = NO;
	long long				longLongValue;
	
#if 0
	/*	Under GNUstep, it is not possible to distinguish between boolean
		NSNumbers and integer NSNumbers - there is no such distinction.
		It is better to convert booleans to integers than vice versa.
	*/
	if ([self oo_isBoolean])
	{
		if ([self boolValue])  result = JSVAL_TRUE;
		else  result = JSVAL_FALSE;
	}
	else
#endif
	{
		isFloat = [self oo_isFloatingPointNumber];
		if (!isFloat)
		{
			longLongValue = [self longLongValue];
			if (longLongValue < (long long)JSVAL_INT_MIN || (long long)JSVAL_INT_MAX < longLongValue)
			{
				// values outside JSVAL_INT range are returned as doubles.
				isFloat = YES;
			}
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
	
	OOJS_PROFILE_EXIT_JSVAL
}


- (NSString *) jsClassName
{
	return @"Number";
}

@end


@implementation NSNull (OOJavaScriptConversion)

- (jsval)javaScriptValueInContext:(JSContext *)context
{
	return JSVAL_NULL;
}

@end


JSBool JSObjectWrapperToString(OOJS_NATIVE_ARGS)
{
	OOJS_PROFILE_ENTER
	
	id						object = nil;
	NSString				*description = nil;
	JSClass					*jsClass = NULL;
	
	object = JSObjectToObject(context, OOJS_THIS);
	if (object != nil)
	{
		description = [object javaScriptDescription];
		if (description == nil)  description = [object description];
	}
	if (description == nil)
	{
		jsClass = OOJS_GetClass(context, OOJS_THIS);
		if (jsClass != NULL)
		{
			description = [NSString stringWithFormat:@"[object %@]", [NSString stringWithUTF8String:jsClass->name]];
		}
	}
	if (description == nil)  description = @"[object]";
	
	OOJS_RETURN_OBJECT(description);
	
	OOJS_PROFILE_EXIT
}


void JSObjectWrapperFinalize(JSContext *context, JSObject *this)
{
	OOJS_PROFILE_ENTER
	
	id object = JS_GetPrivate(context, this);
	if (object != nil)
	{
		[[object weakRefUnderlyingObject] oo_clearJSSelf:this];
		[object release];
		JS_SetPrivate(context, this, nil);
	}
	
	OOJS_PROFILE_EXIT_VOID
}


BOOL JSFunctionPredicate(Entity *entity, void *parameter)
{
	OOJS_PROFILE_ENTER
	
	JSFunctionPredicateParameter	*param = parameter;
	jsval							args[1];
	jsval							rval = JSVAL_VOID;
	JSBool							result = NO;
	
	if (param->errorFlag)  return NO;
	
	args[0] = [entity javaScriptValueInContext:param->context];
	
	OOJSStartTimeLimiter();
	OOJSResumeTimeLimiter();
	BOOL success = JS_CallFunctionValue(param->context, param->jsThis, param->function, 1, args, &rval);
	OOJSPauseTimeLimiter();
	OOJSStopTimeLimiter();
	
	if (success)
	{
		if (!JS_ValueToBoolean(param->context, rval, &result))  result = NO;
		if (JS_IsExceptionPending(param->context))
		{
			JS_ReportPendingException(param->context);
			param->errorFlag = YES;
		}
	}
	else
	{
		param->errorFlag = YES;
	}
	
	return result;
	
	OOJS_PROFILE_EXIT
}


BOOL JSEntityIsJavaScriptVisiblePredicate(Entity *entity, void *parameter)
{
	OOJS_PROFILE_ENTER
	
	return [entity isVisibleToScripts];
	
	OOJS_PROFILE_EXIT
}


BOOL JSEntityIsJavaScriptSearchablePredicate(Entity *entity, void *parameter)
{
	OOJS_PROFILE_ENTER
	
	if (![entity isVisibleToScripts])  return NO;
	if ([entity isShip])
	{
		if ([entity isSubEntity])  return NO;
		if ([entity status] == STATUS_COCKPIT_DISPLAY)  return NO;	// Demo ship
		return YES;
	}
	else if ([entity isPlanet])
	{
		switch ([(OOPlanetEntity *)entity planetType])
		{
			case STELLAR_TYPE_MOON:
			case STELLAR_TYPE_NORMAL_PLANET:
			case STELLAR_TYPE_SUN:
				return YES;
				
#if !NEW_PLANETS
			case STELLAR_TYPE_ATMOSPHERE:
#endif
			case STELLAR_TYPE_MINIATURE:
				return NO;
		}
	}
	
	return YES;	// would happen if we added a new script-visible class
	
	OOJS_PROFILE_EXIT
}


static NSMapTable *sRegisteredSubClasses;

void OOJSRegisterSubclass(JSClass *subclass, JSClass *superclass)
{
	NSCParameterAssert(subclass != NULL && superclass != NULL);
	
	if (sRegisteredSubClasses == NULL)
	{
		sRegisteredSubClasses = NSCreateMapTable(NSNonOwnedPointerMapKeyCallBacks, NSNonOwnedPointerMapValueCallBacks, 0);
	}
	
	NSCAssert(NSMapGet(sRegisteredSubClasses, subclass) == NULL, @"A JS class cannot be registered as a subclass of multiple classes.");
	
	NSMapInsertKnownAbsent(sRegisteredSubClasses, subclass, superclass);
}


BOOL OOJSIsSubclass(JSClass *putativeSubclass, JSClass *superclass)
{
	NSCParameterAssert(putativeSubclass != NULL && superclass != NULL);
	NSCAssert(sRegisteredSubClasses != NULL, @"OOJSIsSubclass() called before any subclasses registered (disallowed for hot path efficiency).");
	
	do
	{
		if (putativeSubclass == superclass)  return YES;
		
		putativeSubclass = NSMapGet(sRegisteredSubClasses, putativeSubclass);
	}
	while (putativeSubclass != NULL);
	
	return NO;
}


BOOL OOJSObjectGetterImpl(JSContext *context, JSObject *object, JSClass *requiredJSClass, Class requiredObjCClass, id *outObject)
{
	NSCParameterAssert(context != NULL && object != NULL && requiredJSClass != NULL && requiredObjCClass != Nil && outObject != NULL);
	
	/*
		Ensure it's a valid type of JS object. This is absolutely necessary,
		because if we don't check it we'll crash trying to get the private
		field of something that isn't an ObjC object wrapper - for example,
		Ship.setAI.call(new Vector3D, "") is valid JavaScript.
		
		Alternatively, we could abuse JSCLASS_PRIVATE_IS_NSISUPPORTS as a
		flag for ObjC object wrappers (SpiderMonkey only uses it internally
		in a debug function we don't use), but we'd still need to do an
		Objective-C class test, and I don't think that's any faster.
		TODO: profile.
	*/
	JSClass *actualClass = JS_GetClass(context, object);
	if (EXPECT_NOT(!OOJSIsSubclass(actualClass, requiredJSClass)))
	{
		OOReportJSError(context, @"Native method expected %s, got %@.", requiredJSClass->name, JSObjectToNSString(context, object));
		return NO;
	}
	NSCAssert(actualClass->flags & JSCLASS_HAS_PRIVATE, @"Native object accessor requires JS class with private storage.");
	
	// Get the underlying object.
	*outObject = [(id)JS_GetPrivate(context, object) weakRefUnderlyingObject];
	
#ifndef NDEBUG
	// Double-check that the underlying object is of the expected ObjC class.
	if (EXPECT_NOT(*outObject != nil && ![*outObject isKindOfClass:requiredObjCClass]))
	{
		OOReportJSError(context, @"Native method expected %@ from %s and got correct JS type but incorrect native object %@", requiredObjCClass, requiredJSClass->name, *outObject);
		return NO;
	}
#endif
	
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
		return [NSNumber numberWithDouble:OOJSVAL_TO_DOUBLE(value)];
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
	
	class = OOJS_GetClass(context, object);
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
	class = OOJS_GetClass(context, templateObject);
	JSRegisterObjectConverter(class, JSArrayConverter);
	
	// Likewise, create a blank object to get its class.
	// This is not documented (not much is) but JS_NewObject falls back to Object if passed a NULL class.
	templateObject = JS_NewObject(context, NULL, NULL, NULL);
	class = OOJS_GetClass(context, templateObject);
	JSRegisterObjectConverter(class, JSGenericObjectConverter);
	
	// String object wrappers.
	if (JS_ValueToObject(context, JS_GetEmptyStringValue(context), &templateObject))
	{
		class = OOJS_GetClass(context, templateObject);
		JSRegisterObjectConverter(class, JSStringConverter);
	}
	
	// Number object wrappers.
	if (JS_ValueToObject(context, INT_TO_JSVAL(0), &templateObject))
	{
		class = OOJS_GetClass(context, templateObject);
		JSRegisterObjectConverter(class, JSNumberConverter);
	}
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
	jsval						value = JSVAL_VOID;
	id							objKey = nil;
	id							objValue = nil;
	
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
		jsid thisID = ids->vector[i];
		
#if OO_NEW_JS
		if (JSID_IS_STRING(thisID))
		{
			objKey = [NSString stringWithJavaScriptString:JSID_TO_STRING(thisID)];
		}
		else if (JSID_IS_INT(thisID))
		{
			objKey = [NSNumber numberWithInt:JSID_TO_INT(thisID)];
		}
		else
		{
			objKey = nil;
		}
		
		value = JSVAL_VOID;
		if (objKey != nil && !JS_LookupPropertyById(context, object, thisID, &value))  value = JSVAL_VOID;
#else
		jsval propKey = value = JSVAL_VOID;
		objKey = nil;
		
		if (JS_IdToValue(context, thisID, &propKey))
		{
			// Properties with string keys.
			if (JSVAL_IS_STRING(propKey))
			{
				JSString *stringKey = JSVAL_TO_STRING(propKey);
				if (JS_LookupProperty(context, object, JS_GetStringBytes(stringKey), &value))
				{
					objKey = [NSString stringWithJavaScriptString:stringKey];
				}
			}
			
			// Properties with int keys.
			else if (JSVAL_IS_INT(propKey))
			{
				jsint intKey = JSVAL_TO_INT(propKey);
				if (JS_GetElement(context, object, intKey, &value))
				{
					objKey = [NSNumber numberWithInt:intKey];
				}
			}
		}
#endif
		
		if (objKey != nil && !JSVAL_IS_VOID(value))
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


static id JSStringConverter(JSContext *context, JSObject *object)
{
	return [NSString stringOrNilWithJavaScriptValue:OBJECT_TO_JSVAL(object) inContext:context];
}


static id JSNumberConverter(JSContext *context, JSObject *object)
{
	jsdouble value;
	if (JS_ValueToNumber(context, OBJECT_TO_JSVAL(object), &value))
	{
		return [NSNumber numberWithDouble:value];
	}
	return nil;
}
