/*

OOJSFunction.m
 

JavaScript support for Oolite
Copyright (C) 2007-2013 David Taylor and Jens Ayton.

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
#import "OOJSEngineTimeManagement.h"


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
		OOJSAddGCObjectRoot(context, (JSObject **)&_function, "OOJSFunction._function");
		_name = [OOStringFromJSString(context, JS_GetFunctionId(function)) retain];
		
		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(deleteJSValue)
													 name:kOOJavaScriptEngineWillResetNotification
												   object:[OOJavaScriptEngine sharedEngine]];
	}
	
	return self;
}


- (id) initWithName:(NSString *)name
			  scope:(JSObject *)scope
			   code:(NSString *)code
	  argumentCount:(NSUInteger)argCount
	  argumentNames:(const char **)argNames
		   fileName:(NSString *)fileName
		 lineNumber:(NSUInteger)lineNumber
			context:(JSContext *)context
{
	BOOL						OK = YES;
	BOOL						releaseContext = NO;
	jschar						*buffer = NULL;
	size_t						length = 0;
	JSFunction					*function;
	
	if (context == NULL)
	{
		context = OOJSAcquireContext();
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
		assert(argCount < UINT32_MAX);
		
		[code getCharacters:buffer];
		
		function = JS_CompileUCFunction(context, scope, [name UTF8String], (uint32_t)argCount, argNames, buffer, length, [fileName UTF8String], (uint32_t)lineNumber);
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
	
	if (releaseContext)  OOJSRelinquishContext(context);
	
	return self;
}


- (void) deleteJSValue
{
	if (_function != NULL)
	{
		JSContext *context = OOJSAcquireContext();
		JS_RemoveObjectRoot(context, (JSObject **)&_function);
		OOJSRelinquishContext(context);
		
		_function = NULL;
		[[NSNotificationCenter defaultCenter] removeObserver:self
														name:kOOJavaScriptEngineWillResetNotification
													  object:[OOJavaScriptEngine sharedEngine]];
	}
}


- (void) dealloc
{
	[self deleteJSValue];
	DESTROY(_name);
	
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
	return _name;
}


- (JSFunction *) function
{
	return _function;
}


- (jsval) functionValue
{
	if (EXPECT(_function != NULL))
	{
		return OBJECT_TO_JSVAL(JS_GetFunctionObject(_function));
	}
	else
	{
		return JSVAL_NULL;
	}

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
	NSUInteger i, argc = [arguments count];
	assert(argc < UINT32_MAX);
	jsval argv[argc];
	
	for (i = 0; i < argc; i++)
	{
		argv[i] = [[arguments objectAtIndex:i] oo_jsValueInContext:context];
		OOJSAddGCValueRoot(context, &argv[i], "OOJSFunction argv");
	}
	
	JSObject *scopeObj = NULL;
	BOOL OK = YES;
	if (jsThis != nil)  OK = JS_ValueToObject(context, [jsThis oo_jsValueInContext:context], &scopeObj);
	if (OK)  OK = [self evaluateWithContext:context
									  scope:scopeObj
									   argc:(uint32_t)argc
									   argv:argv
									 result:result];
	
	for (i = 0; i < argc; i++)
	{
		JS_RemoveValueRoot(context, &argv[i]);
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
	
	return OOJSNativeObjectFromJSValue(context, result);
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
