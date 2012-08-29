/*

OOJSFunction.h

Object encapsulating a runnable JavaScript function.


JavaScript support for Oolite
Copyright (C) 2007-2012 David Taylor and Jens Ayton.

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
#include <jsapi.h>


@interface OOJSFunction: NSObject
{
@private
	JSFunction					*_function;
	NSString					*_name;
}

- (id) initWithFunction:(JSFunction *)function context:(JSContext *)context;
- (id) initWithName:(NSString *)name
			  scope:(JSObject *)scope		// may be NULL, in which case global object is used.
			   code:(NSString *)code		// full JS code for function, including function declaration.
	  argumentCount:(NSUInteger)argCount
	  argumentNames:(const char **)argNames
		   fileName:(NSString *)fileName
		 lineNumber:(NSUInteger)lineNumber
			context:(JSContext *)context;	// may be NULL. If not null, must be in a request.

- (NSString *) name;
- (JSFunction *) function;
- (jsval) functionValue;

// Raw evaluation. Context may not be NULL and must be in a request.
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
