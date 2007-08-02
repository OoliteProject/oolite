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

@interface OOJavaScriptEngine : NSObject
{
	JSRuntime			*runtime;
	JSContext			*context;
	JSObject			*globalObject;
}

+ (OOJavaScriptEngine *)sharedEngine;

- (JSContext *) context;

@end


void OOReportJavaScriptError(JSContext *context, NSString *format, ...);
void OOReportJavaScriptErrorWithArguments(JSContext *context, NSString *format, va_list args);
void OOReportJavaScriptWarning(JSContext *context, NSString *format, ...);
void OOReportJavaScriptWarningWithArguments(JSContext *context, NSString *format, va_list args);
void OOReportJavaScriptBadPropertySelector(JSContext *context, NSString *className, jsint selector);

/*	NumberFromArgumentList()
	
	Get a single number from an argument list. The optional outConsumed
	argument can be used to find out how many parameters were used (currently,
	this will be 0 on failure, otherwise 1).
	
	On failure, it will return NO, annd the number will be unaltered. If
	scriptClass and function are non-nil, a warning will be reported to the
	log.
*/
BOOL NumberFromArgumentList(JSContext *context, NSString *scriptClass, NSString *function, uintN argc, jsval *argv, double *outNumber, uintN *outConsumed);


/*	JSArgumentsFromArray()
	
	Convert an ObjC array to an array of JavaScript values. For objects which
	don't respond to -javaScriptValueInContext:, JSVAL_VOID will be used.
	
	*outArgv will be NULL if *outArgc is 0. If *outArgv is not NULL, it should
	be free()d when finished with.
*/
BOOL JSArgumentsFromArray(JSContext *context, NSArray *array, uintN *outArgc, jsval **outArgv);

/*	JSArrayFromArray()
	
	Convert an ObjC array to a JavaScript array. This is a wrapper around
	JSArgumentsFromArray() and js_NewArrayObject().
*/
JSObject *JSArrayFromNSArray(JSContext *context, NSArray *array);


OOINLINE jsval BOOLToJSVal(BOOL b) INLINE_CONST_FUNC;
OOINLINE jsval BOOLToJSVal(BOOL b)
{
	return BOOLEAN_TO_JSVAL(b != NO);
}


@interface NSObject (OOJavaScriptConversion)

/*	-javaScriptValueInContext:
	
	Return the JavaScript object representation of an object. The default
	implementation returns JSVAL_NULL. At this time, NSString, NSNumber,
	NSArray and Entity override this.
*/
- (jsval)javaScriptValueInContext:(JSContext *)context;

@end


@interface NSString (OOJavaScriptExtensions)

// Convert a JSString to an NSString.
+ (id)stringWithJavaScriptString:(JSString *)string;

// Convert an arbitrary JS object to an NSString, using JS_ValueToString.
+ (id)stringWithJavaScriptValue:(jsval)value inContext:(JSContext *)context;

// For diagnostic messages; produces things like @"(42, true, "a string", an object description)".
+ (id)stringWithJavaScriptParameters:(jsval *)params count:(uintN)count inContext:(JSContext *)context;

// Concatenate sequence of arbitrary JS objects into string.
+ (id)concatenationOfStringsFromJavaScriptValues:(jsval *)values count:(size_t)count separator:(NSString *)separator inContext:(JSContext *)context;

@end


OOINLINE NSString *JSValToNSString(JSContext *context, jsval value)
{
	return [NSString stringWithJavaScriptValue:value inContext:context];
}


NSString *JSPropertyAsString(JSContext *context, JSObject *object, const char *name);
