/*

OOJSFunction.m
 

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

#import "OOJSFunction.h"
#import "OOJSScript.h"


@implementation OOJSFunction

- (id) initWithFunction:(JSFunction *)function context:(JSContext *)context
{
	NSParameterAssert(context != NULL);
	
	if (function == NULL)
	{
		[self release];
		return nil;
	}
	
	if ((self = [super init]))
	{
		_function = function;
		OO_AddJSGCRoot(context, &_function, "OOJSFunction._function");
	}
	
	return self;
}


- (id) initWithName:(NSString *)name
			  scope:(JSObject *)scope
			   code:(NSString *)code
	  argumentCount:(OOUInteger)argCount
	  argumentNames:(const char **)argNames
		   fileName:(NSString *)fileName
		 lineNumber:(OOUInteger)lineNumber
			context:(JSContext *)context
{
	BOOL						OK = YES;
	BOOL						releaseContext = NO;
	jschar						*buffer = NULL;
	size_t						length;
	JSFunction					*function;
	
	if (context == NULL)
	{
		context = [[OOJavaScriptEngine sharedEngine] acquireContext];
		releaseContext = YES;
	}
	if (scope == NULL)  scope = [[OOJavaScriptEngine sharedEngine] globalObject];
	
	if (code == nil || (argCount > 0 && argNames == NULL))  OK = NO;
	
	if (OK)
	{
		// jschar and unichar are both defined to be 16-bit elements.
		assert(sizeof(jschar) == sizeof(unichar));
		
		length = [code length];
		buffer = malloc(sizeof(jschar) * length);
		if (buffer == NULL)  OK = NO;
	}
	
	if (OK)
	{
		[code getCharacters:buffer];
		function = JS_CompileUCFunction(context, scope, [name UTF8String], argCount, argNames, buffer, length, [fileName UTF8String], lineNumber);
		if (function == NULL)  OK = NO;
		
		free(buffer);
	}
	
	if (OK)
	{
		self = [self initWithFunction:function context:context];
	}
	else
	{
		DESTROY(self);
	}
	
	if (releaseContext)  [[OOJavaScriptEngine sharedEngine] releaseContext:context];
	
	return self;
}


- (void) dealloc
{
	[[OOJavaScriptEngine sharedEngine] removeGCObjectRoot:(JSObject **)&_function];
	
	[super dealloc];
}


- (NSString *) descriptionComponents
{
	NSString *name = [self name];
	if (name == nil)  name = @"<anonymous>";
	return [NSString stringWithFormat:@"%@()", name];
}


- (NSString *) name
{
	JSString *name = JS_GetFunctionId(_function);
	return [NSString stringWithJavaScriptString:name];
}


- (JSFunction *) function
{
	return _function;
}


- (BOOL) evaluateWithContext:(JSContext *)context
					   scope:(JSObject *)jsThis
						argc:(uintN)argc
						argv:(jsval *)argv
					  result:(jsval *)result
{
	[OOJSScript pushScript:nil];
	OOJSStartTimeLimiter();
	BOOL OK = JS_CallFunction(context, jsThis, _function, argc, argv, result);
	OOJSStopTimeLimiter();
	[OOJSScript popScript:nil];
	
	return OK;
}

// Semi-raw evaluation shared by convenience methods below.
- (BOOL) evaluateWithContext:(JSContext *)context
					   scope:(id)jsThis
				   arguments:(NSArray *)arguments
					  result:(jsval *)result
{
	OOUInteger i, argc = [arguments count];
	jsval argv[argc];
	
	for (i = 0; i < argc; i++)
	{
		argv[i] = [[arguments objectAtIndex:i] javaScriptValueInContext:context];
		OO_AddJSGCRoot(context, &argv[i], "OOJSFunction argv");
	}
	
	JSObject *scopeObj = NULL;
	BOOL OK = YES;
	if (jsThis != nil)  OK = JS_ValueToObject(context, [jsThis javaScriptValueInContext:context], &scopeObj);
	if (OK)  OK = [self evaluateWithContext:context
									  scope:scopeObj
									   argc:argc
									   argv:argv
									 result:result];
	
	for (i = 0; i < argc; i++)
	{
		JS_RemoveRoot(context, &argv[i]);
	}
	
	return OK;
}


- (id) evaluateWithContext:(JSContext *)context
					 scope:(id)jsThis
				 arguments:(NSArray *)arguments
{
	jsval result;
	BOOL OK = [self evaluateWithContext:context
								  scope:jsThis
							  arguments:arguments
								 result:&result];
	if (!OK)  return nil;
	
	return JSValueToObject(context, result);
}
			   

- (BOOL) evaluatePredicateWithContext:(JSContext *)context
								scope:(id)jsThis
							arguments:(NSArray *)arguments
{
	jsval result;
	BOOL OK = [self evaluateWithContext:context
								  scope:jsThis
							  arguments:arguments
								 result:&result];
	JSBool retval = NO;
	if (OK)  OK = JS_ValueToBoolean(context, result, &retval);
	
	return OK && retval;
}

@end
