/*

OOJSFunction.h

Object encapsulating a runnable JavaScript function.


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

#import "OOFoundation.h"
#include "oofnd/StdLib.hpp"
#include "oofnd/objc/OOObjCRef.h"
#import "oofnd/objc/OOObject.h"
#include <quickjs.h>

@interface OOJSFunction : OOObject {
@private
    JSValue _function; // Owned; zero-filled (not an object) when invalid.
    std::optional<std::string> _name; // nullopt for an anonymous function (was nil)
}

// function must be a function value; the OOJSFunction takes its own reference.
- (id)initWithFunction:(JSValueConst)function context:(JSContext*)context;
- (id)initWithName:(const std::optional<std::string>&)name
             scope:(JSValueConst)scope // Ignored; QuickJS compiles functions in the global scope. Pass JS_UNDEFINED.
              code:(const std::optional<std::string>&)code // Function body.
     argumentCount:(NSUInteger)argCount
     argumentNames:(const char**)argNames
          fileName:(const std::optional<std::string>&)fileName
        lineNumber:(NSUInteger)lineNumber
           context:(JSContext*)context; // may be NULL.

- (id)name; // shared selector (Foundation declares -name too): -cxx_name as an Objective-C string, or nil
- (std::optional<std::string>)cxx_name; // nullopt: anonymous (bead oo-3rb.289.7)
// Borrowed; valid while the receiver is alive and the engine is not reset. JS_NULL if invalid.
- (JSValueConst)function;
// Owned (caller must free). JS_NULL if invalid.
- (JSValue)functionValue;

// Raw evaluation. *result is owned by the caller on success. On failure, any exception is left pending (not reported).
- (BOOL)evaluateWithContext:(JSContext*)context
                      scope:(JSValueConst)jsThis
                       argc:(int)argc
                       argv:(JSValueConst*)argv
                     result:(JSValue*)result;

// Object-wrapper evaluation, converting the result to a boolean.
- (BOOL)evaluatePredicateWithContext:(JSContext*)context
                               scope:(id)jsThis
                           arguments:(const std::vector<oo::ObjCRef<id>>&)arguments;

@end
