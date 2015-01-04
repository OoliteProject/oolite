/*

OOLogging.h
By Jens Ayton

More flexible alternative to NSLog().


Copyright (C) 2007-2013 Jens Ayton and contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/

#import "OOCocoa.h"
#import "OOFunctionAttributes.h"
#include <stdarg.h>


#ifndef OOLOG_POISON_NSLOG
	#define OOLOG_POISON_NSLOG	0
#endif


#ifndef OOLOG_FUNCTION_NAME
	#if defined (__GNUC__) && __GNUC__ >= 2
		#define OOLOG_FUNCTION_NAME	__FUNCTION__
	#elif 199901L <= __STDC_VERSION__
		#define OOLOG_FUNCTION_NAME	__func__
	#else
		#define OOLOG_FUNCTION_NAME	NULL
	#endif
#endif

#ifndef OOLOG_FILE_NAME
	#ifdef OOLOG_NO_FILE_NAME
		#define OOLOG_FILE_NAME NULL
	#else
		#define OOLOG_FILE_NAME __FILE__
	#endif
#endif


/*	OOLOG_SHORT_CIRCUIT:
	If nonzero, the test of whether to display a message before evaluating the
	other parameters of the call. This saves time, but could cause weird bugs
	if the parameters involve calls with side effects.
*/
#ifndef OOLOG_SHORT_CIRCUIT
	#define OOLOG_SHORT_CIRCUIT		1
#endif


/*	General usage:
		OOLog(messageClass, format, parameters);
	is conceptually equivalent to:
		NSLog(format, parameters);
	except that it will do nothing if logging is disabled for messageClass.
	
	A message class is a hierarchical string, such as:
		@"all.script.debug"
	
	To determine whether scripting is enabled for this class, a setting for
	@"all.script.debug" is looked up in a settings table. If it is not found,
	@"all.script" is tried, followed by @"all".
	
	Message class display settings can be manipulated with
	OOLogSetDisplayMessagesInClass() and tested with
	OOLogWillDisplayMessagesInClass().
*/
#if OOLOG_SHORT_CIRCUIT
	#define OOLog(class, format, ...)				do { if (OOLogWillDisplayMessagesInClass(class)) { OOLogWithFunctionFileAndLine(class, OOLOG_FUNCTION_NAME, OOLOG_FILE_NAME, __LINE__, format, ## __VA_ARGS__); }} while (0)
	#define OOLogWithArguments(class, format, args)	do { if (OOLogWillDisplayMessagesInClass(class)) { OOLogWithFunctionFileAndLineAndArguments(class, OOLOG_FUNCTION_NAME, OOLOG_FILE_NAME, __LINE__, format, args); }} while (0)
#else
	#define OOLog(class, format, ...)				OOLogWithFunctionFileAndLine(class, OOLOG_FUNCTION_NAME, OOLOG_FILE_NAME, __LINE__, format, ## __VA_ARGS__)
	#define OOLogWithArguments(class, format, args)	OOLogWithFunctionFileAndLineAndArguments(class, OOLOG_FUNCTION_NAME, OOLOG_FILE_NAME, __LINE__, format, args)
#endif

BOOL OOLogWillDisplayMessagesInClass(NSString *inMessageClass);

void OOLogIndent(void);
void OOLogOutdent(void);

#if OOLOG_SHORT_CIRCUIT
#define OOLogIndentIf(class)		do { if (OOLogWillDisplayMessagesInClass(class)) OOLogIndent(); } while (0)
#define OOLogOutdentIf(class)		do { if (OOLogWillDisplayMessagesInClass(class)) OOLogOutdent(); } while (0)
#else
void OOLogIndentIf(NSString *inMessageClass);
void OOLogOutdentIf(NSString *inMessageClass);
#endif


#define OOLOG_ERROR_PREFIX		@"***** ERROR: "
#define OOLOG_WARNING_PREFIX	@"----- WARNING: "

#define OOLogERR(class, format, ...) OOLogWithPrefix(class, OOLOG_FUNCTION_NAME, OOLOG_FILE_NAME, __LINE__, OOLOG_ERROR_PREFIX ,format, ## __VA_ARGS__)
#define OOLogWARN(class, format, ...) OOLogWithPrefix(class, OOLOG_FUNCTION_NAME, OOLOG_FILE_NAME, __LINE__, OOLOG_WARNING_PREFIX, format, ## __VA_ARGS__)


// Remember/restore indent levels, for cases where an exception may occur while indented.
void OOLogPushIndent(void);
void OOLogPopIndent(void);

void OOLogWithPrefix(NSString *inMessageClass, const char *inFunction, const char *inFile, unsigned long inLine, NSString *inPrefix, NSString *inFormat, ...)  OO_TAKES_FORMAT_STRING(6, 7);
void OOLogWithFunctionFileAndLine(NSString *inMessageClass, const char *inFunction, const char *inFile, unsigned long inLine, NSString *inFormat, ...)  OO_TAKES_FORMAT_STRING(5, 6);
void OOLogWithFunctionFileAndLineAndArguments(NSString *inMessageClass, const char *inFunction, const char *inFile, unsigned long inLine, NSString *inFormat, va_list inArguments)  OO_TAKES_FORMAT_STRING(5, 0);

// OOLogGenericParameterError(): general parameter error message, "***** $function_name: bad parameters. (This is an internal programming error, please report it.)"
#define OOLogGenericParameterError()	OOLogGenericParameterErrorForFunction(OOLOG_FUNCTION_NAME)
void OOLogGenericParameterErrorForFunction(const char *inFunction);

// OOLogGenericSubclassResponsibility(): general subclass responsibility message, "***** $function_name is a subclass responsibility. (This is an internal programming error, please report it.)"
#define OOLogGenericSubclassResponsibility()	OOLogGenericSubclassResponsibilityForFunction(OOLOG_FUNCTION_NAME)
void OOLogGenericSubclassResponsibilityForFunction(const char *inFunction);


#if OOLOG_POISON_NSLOG
	#pragma GCC poison NSLog	// Use OOLog instead
#elif !OOLOG_NO_HIJACK_NSLOG
	// Hijack NSLog. Buahahahaha.
	#define NSLog(format, ...)		OOLog(kOOLogUnconvertedNSLog, format, ## __VA_ARGS__)
	#define NSLogv(format, args)	OOLogWithArguments(kOOLogUnconvertedNSLog, format, args)
#endif


// OODebugLog() is only included in debug builds.
#if OO_DEBUG
#define OODebugLog OOLog
#else
#define OODebugLog(class, format, ...)  do { (void)class; if (0) (void)format; } while (0)
#endif


// OOExtraLog() is included in debug and test-release builds, but not deployment builds.
#ifndef NDEBUG
#define OOExtraLog OOLog
#else
#define OOExtraLog(class, format, ...)  do { (void)class; if (0) (void)format; } while (0)
#endif


// *** Predefined message classes.
/*	These are general coding error types. Generally a subclass should be used
	for each instance -- for instance, -[Entity warnAboutHostiles] uses
	@"general.error.subclassResponsibility.Entity-warnAboutHostiles".
*/

extern NSString * const kOOLogSubclassResponsibility;		// @"general.error.subclassResponsibility"
extern NSString * const kOOLogParameterError;				// @"general.error.parameterError"
extern NSString * const kOOLogDeprecatedMethod;				// @"general.error.deprecatedMethod"
extern NSString * const kOOLogAllocationFailure;			// @"general.error.allocationFailure"
extern NSString * const kOOLogInconsistentState;			// @"general.error.inconsistentState"
extern NSString * const kOOLogException;					// @"exception"

extern NSString * const kOOLogFileNotFound;					// @"files.notFound"
extern NSString * const kOOLogFileNotLoaded;				// @"files.notLoaded"

extern NSString * const kOOLogOpenGLError;					// @"rendering.opengl.error"

// Don't use. However, #defining it as @"unclassified.module" can be used as a stepping stone to OOLog support.
extern NSString * const kOOLogUnconvertedNSLog;				// @"unclassified"
