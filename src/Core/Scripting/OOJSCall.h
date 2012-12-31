/*

OOJSCall.h

Basic JavaScript-to-ObjC bridge implementation.

Oolite
Copyright (C) 2004-2013 Giles C Williams and contributors

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

#ifndef NDEBUG


#import <Foundation/Foundation.h>
#include <jsapi.h>


/*	OOJSCallObjCObjectMethod()
	
	Function for implementing JavaScript call() methods.
	
	The argument list is expected to be either a single string (selector), or
	a string ending with a : followed by arbitrary arguments which will be
	concatenated as a string. (This behaviour reflects Oolite's traditional
	scripting system and the expectations of its script methods. It also has
	the advantage that it can be done with GNUstep's buggy implementation of
	NSMethodSignature.)
	
	If the method returns an object, *outResult will be set to that object's
	-oo_jsValueInContext:. Otherwise, it will be left unchanged.
	
	argv is assumed to contain at least one value.
*/
BOOL OOJSCallObjCObjectMethod(JSContext *context, id object, NSString *oo_jsClassName, uintN argc, jsval *argv, jsval *outResult);

#endif
