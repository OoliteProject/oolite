/*

OOJavaScriptEngine.h

JavaScript support for Oolite
Copyright (C) 2007 David Taylor

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
#import "PlayerEntityScripting.h"
#import <jsapi.h>

@interface OOJavaScriptEngine : NSObject
{
	JSRuntime *rt;
	JSContext *cx;
	JSObject *glob;
	JSBool builtins;
}

+ (OOJavaScriptEngine *)sharedEngine;

- (JSContext *) context;

@end


@protocol OOJavaScriptConversion <NSObject>

- (jsval)javaScriptValueInContext:(JSContext *)context;

@end


@interface NSString (OOJavaScriptExtensions) <OOJavaScriptConversion>

// Convert a JSString to an NSString.
+ (id)stringWithJavaScriptString:(JSString *)string;

// Convert an arbitrary JS object to an NSString, using JS_ValueToString.
+ (id)stringWithJavaScriptValue:(jsval)value inContext:(JSContext *)context;

// Concatenate sequence of arbitrary JS objects into string.
+ (id)concatenationOfStringsFromJavaScriptValues:(jsval *)values count:(size_t)count separator:(NSString *)separator inContext:(JSContext *)context;

@end


@interface NSNumber (OOJavaScriptExtensions) <OOJavaScriptConversion>

@end
