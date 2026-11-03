/*

OOJSFunction.h

Object encapsulating a runnable JavaScript function.

C++20 since bead oo-3smy (proposed ADR-0056, the OOColor house style). The Objective-C facade
was deleted once ShipEntityAI and OORegExpMatcher held the C++ object, and the class moved out of
namespace cxx.


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

#ifndef OOJSFUNCTION_H
#define OOJSFUNCTION_H

#import "OOFoundation.h"
#include "oofnd/Ref.hpp"
#include "oofnd/StdLib.hpp"
#include "oofnd/objc/OOObjCRef.h"
#include <quickjs.h>

#include <optional>
#include <string>
#include <vector>

class OOJSFunction : public oo::RefCounted {
public:
    // The initialisers' factories (proposed ADR-0056 amendment oo-novu): null where the
    // initialiser answered nil (not a function; no code, missing argument names, or a compile
    // error).
    // function must be a function value; the OOJSFunction takes its own reference.
    static oo::Ref<OOJSFunction> initWithFunction(JSValueConst function, JSContext* context);
    static oo::Ref<OOJSFunction> initWithName(const std::optional<std::string>& name,
        JSValueConst scope, // Ignored; QuickJS compiles functions in the global scope. Pass JS_UNDEFINED.
        const std::optional<std::string>& code, // Function body.
        NSUInteger argCount,
        const char** argNames,
        const std::optional<std::string>& fileName,
        NSUInteger lineNumber,
        JSContext* context); // may be NULL.

    ~OOJSFunction() override;

    std::optional<std::string> descriptionComponents() const;

    std::optional<std::string> name(); // nullopt: anonymous (bead oo-3rb.289.7)
    // Borrowed; valid while the receiver is alive and the engine is not reset. JS_NULL if invalid.
    JSValueConst function();
    // Owned (caller must free). JS_NULL if invalid.
    JSValue functionValue();

    // Raw evaluation. *result is owned by the caller on success. On failure, any exception is left pending (not reported).
    bool evaluateWithContext(JSContext* context,
        JSValueConst jsThis,
        int argc,
        JSValueConst* argv,
        JSValue* result);

    // Object-wrapper evaluation, converting the result to a boolean.
    bool evaluatePredicateWithContext(JSContext* context,
        id jsThis,
        const std::vector<oo::ObjCRef<id>>& arguments);

private:
    // The part of -initWithFunction:context: that cannot fail.
    OOJSFunction(JSValueConst function, JSContext* context);

    bool isValid() const;
    void deleteJSValue();

    // Semi-raw evaluation shared by convenience methods below. *result is owned on success; exceptions are reported.
    bool evaluateWithContext(JSContext* context,
        id jsThis,
        const std::vector<oo::ObjCRef<id>>& arguments,
        JSValue* result);

    JSValue _function = JS_NULL; // Owned; JS_NULL when invalid.
    std::optional<std::string> _name; // nullopt for an anonymous function (was nil)
};

#endif // OOJSFUNCTION_H
