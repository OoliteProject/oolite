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

#pragma once

#include <quickjs.h>

#include <algorithm>
#include <chrono>
#include <condition_variable>
#include <cstddef>
#include <cstdint>
#include <functional>
#include <map>
#include <memory>
#include <mutex>
#include <optional>
#include <set>
#include <string>
#include <string_view>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <vector>

#include "OOFoundation.h"
#include "oofnd/Ref.hpp"

class OOJSFunction : public oo::Object {
 public:
  // The initialisers' factories: null where the initialiser answered nil (not a
  // function; no code, missing argument names, or a compile error). function
  // must be a function value; the OOJSFunction takes its own reference.
  static std::shared_ptr<OOJSFunction> initWithFunction(JSValueConst function,
                                                        JSContext* context);
  static std::shared_ptr<OOJSFunction> initWithName(
      const std::optional<std::string>& name,
      JSValueConst scope,  // Ignored; QuickJS compiles functions in the global
                           // scope. Pass JS_UNDEFINED.
      const std::optional<std::string>& code,  // Function body.
      std::size_t argCount, const char** argNames,
      const std::optional<std::string>& fileName, std::size_t lineNumber,
      JSContext* context);  // may be NULL.

  ~OOJSFunction() override;

  std::optional<std::string> descriptionComponents() const;

  std::optional<std::string> name();  // nullopt: anonymous
  // Borrowed; valid while the receiver is alive and the engine is not reset.
  // JS_NULL if invalid.
  JSValueConst function();
  // Owned (caller must free). JS_NULL if invalid.
  JSValue functionValue();

  // Raw evaluation. *result is owned by the caller on success. On failure, any
  // exception is left pending (not reported).
  bool evaluateWithContext(JSContext* context, JSValueConst jsThis, int argc,
                           JSValueConst* argv, JSValue* result);

 private:
  // The part of -initWithFunction:context: that cannot fail.
  OOJSFunction(JSValueConst function, JSContext* context);

  bool isValid() const;
  void deleteJSValue();

  JSValue _function = JS_NULL;  // Owned; JS_NULL when invalid.
  std::optional<std::string>
      _name;  // nullopt for an anonymous function (was nil)
};
