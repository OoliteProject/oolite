/*

OOJSFunction.m
 

JavaScript support for Oolite
Copyright (C) 2007-2009 David Taylor and Jens Ayton.

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


@implementation OOJSFunction

- (id) initWithFunction:(JSFunction *)function
{
	if (function == NULL)
	{
		[self release];
		return nil;
	}
	
	if ((self = [super init]))
	{
		_function = function;
		[[OOJavaScriptEngine sharedEngine] addGCRoot:&function named:"OOJSFunction._function"];
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
		self = [self initWithFunction:function];
	}
	else
	{
		[self release];
		self = nil;
	}
	
	if (releaseContext)  [[OOJavaScriptEngine sharedEngine] releaseContext:context];
	
	return self;
}


- (void) dealloc
{
	[[OOJavaScriptEngine sharedEngine] removeGCRoot:&_function];
	
	[super dealloc];
}


- (NSString *) descriptionComponents
{
	NSString *name = [self name];
	if (name == nil)  name = @"<anonymous>";
	return [NSString stringWithFormat:@"%@()", [self name]];
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

@end
