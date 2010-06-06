/*

OOJSFunction.h

Object encapsulating a runnable JavaScript function. This is mostly a holder
for a JSFunction *; NSValue can't be used for this purpose because a GC root
is needed.


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


@interface OOJSFunction: NSObject
{
@private
	JSFunction					*_function;
}

- (id) initWithFunction:(JSFunction *)function context:(JSContext *)context;
- (id) initWithName:(NSString *)name
			  scope:(JSObject *)scope		// may be NULL, in which case global object is used.
			   code:(NSString *)code		// full JS code for function, including function declaration.
	  argumentCount:(OOUInteger)argCount
	  argumentNames:(const char **)argNames
		   fileName:(NSString *)fileName
		 lineNumber:(OOUInteger)lineNumber
			context:(JSContext *)context;	// may be NULL.

- (NSString *) name;
- (JSFunction *) function;

// Raw evaluation. Context may not be NULL.
- (BOOL) evaluateWithContext:(JSContext *)context
					   scope:(JSObject *)jsThis
						argc:(uintN)argc
						argv:(jsval *)argv
					  result:(jsval *)result;

// Object-wrapper evaluation.
- (id) evaluateWithContext:(JSContext *)context
					 scope:(id)jsThis
				 arguments:(NSArray *)arguments;

// As above, but converts result to a boolean.
- (BOOL) evaluatePredicateWithContext:(JSContext *)context
								scope:(id)jsThis
							arguments:(NSArray *)arguments;

@end
