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
#define OOLog(class, format, ...)				OOLogWithFunctionFileAndLine(class, OOLOG_FUNCTION_NAME, __FILE__, __LINE__, format, ## __VA_ARGS__)
#define OOLogWithArgmuents(class, format, args)	OOLogWithFunctionFileAndLine(class, OOLOG_FUNCTION_NAME, __FILE__, __LINE__, format, args)

BOOL OOLogWillDisplayMessagesInClass(NSString *inMessageClass);
void OOLogSetDisplayMessagesInClass(NSString *inClass, BOOL inFlag);
NSString *OOLogGetParentMessageClass(NSString *inClass);

void OOLogIndent(void);
void OOLogOutdent(void);

void OOLogWithFunctionFileAndLine(NSString *inMessageClass, const char *inFunction, const char *inFile, unsigned long inLine, NSString *inFormat, ...);
void OOLogWithFunctionFileAndLineAndArguments(NSString *inMessageClass, const char *inFunction, const char *inFile, unsigned long inLine, NSString *inFormat, va_list inArguments);



/* Predefined message classes. */
extern NSString * const kOOLogClassScripting;			// @"scripting"
extern NSString * const kOOLogClassScripDebug;			// @"scripting.debug"
extern NSString * const kOOLogClassScripDebugOnOff;		// @"scripting.debug.onoff"
extern NSString * const kOOLogClassRendering;			// @"rendering"
extern NSString * const kOOLogClassOpenGL;				// @"rendering.opengl"
extern NSString * const kOOLogClassOpenGLError;			// @"rendering.opengl.errors"
extern NSString * const kOOLogClassOpenGLVersion;		// @"rendering.opengl.version"
extern NSString * const kOOLogClassOpenGLShaderSupport;	// @"rendering.opengl.shaders.support"
extern NSString * const kOOLogClassOpenGLExtensions;	// @"rendering.opengl.extensions"
extern NSString * const kOOLogClassSearchPaths;			// @"searchpaths"
extern NSString * const kOOLogClassDumpSearchPaths;		// @"searchpaths.dumpall"
