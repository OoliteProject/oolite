/*

OOLogging.h
By Jens Ayton

More flexible alternative to NSLog().

Oolite
Copyright (C) 2004-2007 Giles C Williams and contributors

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
#import <stdarg.h>


// #pragma GCC poison NSLog	// Use OOLog instead


#ifndef OOLOG_FUNCTION_NAME
	#if defined (__GNUC__) && __GNUC__ >= 2
		#define OOLOG_FUNCTION_NAME	__PRETTY_FUNCTION__
	#elif 199901L <= __STDC_VERSION__
		#define OOLOG_FUNCTION_NAME	__func__
	#else
		#define OOLOG_FUNCTION_NAME	NULL
	#endif
#endif


/*	OOLOG_SHORT_CIRCUIT:
	If nonzero, the test of whether to display a message before evaluating the
	other parameters of the call. This saves time, but could cause weird bugs
	if the parameters involve calls with side effects.
	
	Disabled for 1.68, will be tried leading up to 1.69.
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
	#define OOLog(class, format, ...)				do { if (OOLogWillDisplayMessagesInClass(class)) { OOLogWithFunctionFileAndLine(class, OOLOG_FUNCTION_NAME, __FILE__, __LINE__, format, ## __VA_ARGS__); }} while (0)
	#define OOLogWithArgmuents(class, format, args)	do { if (OOLogWillDisplayMessagesInClass(class)) { OOLogWithFunctionFileAndLineAndArguments(class, OOLOG_FUNCTION_NAME, __FILE__, __LINE__, format, args); }} while (0)
#else
	#define OOLog(class, format, ...)				OOLogWithFunctionFileAndLine(class, OOLOG_FUNCTION_NAME, __FILE__, __LINE__, format, ## __VA_ARGS__)
	#define OOLogWithArgmuents(class, format, args)	OOLogWithFunctionFileAndLineAndArguments(class, OOLOG_FUNCTION_NAME, __FILE__, __LINE__, format, args)
#endif

BOOL OOLogWillDisplayMessagesInClass(NSString *inMessageClass);
void OOLogSetDisplayMessagesInClass(NSString *inClass, BOOL inFlag);
NSString *OOLogGetParentMessageClass(NSString *inClass);

void OOLogIndent(void);
void OOLogOutdent(void);

void OOLogIndentIf(NSString *inMessageClass);
void OOLogOutdentIf(NSString *inMessageClass);

// Remember/restore indent levels, for cases where an exception may occur while indented.
void OOLogPushIndent(void);
void OOLogPopIndent(void);

void OOLogWithFunctionFileAndLine(NSString *inMessageClass, const char *inFunction, const char *inFile, unsigned long inLine, NSString *inFormat, ...);
void OOLogWithFunctionFileAndLineAndArguments(NSString *inMessageClass, const char *inFunction, const char *inFile, unsigned long inLine, NSString *inFormat, va_list inArguments);

// OOLogGenericParameterError(): general parameter error message, "***** $function_name: bad parameters. (This is an internal programming error, please report it.)"
#define OOLogGenericParameterError()	OOLogGenericParameterErrorForFunction(OOLOG_FUNCTION_NAME)
void OOLogGenericParameterErrorForFunction(const char *inFunction);


void OOLoggingInit(void);


// Hijack NSLog. Buahahahaha.
#define NSLog(format, ...)		OOLog(kOOLogUnconvertedNSLog, format, ## __VA_ARGS__)
#define NSLogv(NSLogv, args)	OOLogWithArgmuents(kOOLogUnconvertedNSLog, format, args)


// *** Predefined message classes.
/*	These are general coding error types. Generally a subclass should be used
	for each instance -- for instance, -[Entity warnAboutHostiles] uses
	@"general.error.subclassResponsibility.Entity-warnAboutHostiles".
*/
extern NSString * const kOOLogSubclassResponsibility;		// @"general.error.subclassResponsibility"
extern NSString * const kOOLogParameterError;				// @"general.error.parameterError"
extern NSString * const kOOLogDeprecatedMethod;				// @"general.error.deprecatedMethod"
extern NSString * const kOOLogAllocationFailure;			// @"general.error.allocationFailure"
extern NSString * const kOOLogException;					// @"exception"

extern NSString * const kOOLogFileNotFound;					// @"files.notfound"
extern NSString * const kOOLogFileNotLoaded;				// @"files.notloaded"

extern NSString * const kOOLogOpenGLError;					// @"rendering.opengl.error"

// Don't use. However, #defining it as @"unclassified.module" can be used as a stepping stone to OOLog support.
extern NSString * const kOOLogUnconvertedNSLog;				// @"unclassified"
