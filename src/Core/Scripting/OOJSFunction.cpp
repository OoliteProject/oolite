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

#include "OOJSFunction.h"

#include <climits>
#include <format>

#include "OOJSEngineTimeManagement.h"
#include "OOJSScript.h"
#include "oofnd/Notification.hpp"
#include "oofnd/String.hpp"
#include "oofnd/objc/OOAssert.h"

/*	OOJSFunction. The initialisers are static factories answering null for
   their input; the part of -initWithFunction:context: that cannot fail is the
   private constructor.
*/

oo::Ref<OOJSFunction> OOJSFunction::initWithFunction(JSValueConst function,
                                                     JSContext* context) {
  OOCParameterAssert(context != nullptr);

  if (!JS_IsFunction(context, function)) {
    return nullptr;
  }

  return oo::adopt(new OOJSFunction(function, context));
}

OOJSFunction::OOJSFunction(JSValueConst function, JSContext* context) {
  {
    _function = JS_DupValue(context, function);

    // QuickJS has no JS_GetFunctionId(); use the function's name property.
    JSValue nameValue = JS_GetPropertyStr(context, function, "name");
    if (JS_IsException(nameValue)) {
      JS_FreeValue(context, JS_GetException(context));
    } else {
      std::optional<std::string> name =
          cxx_OOStringFromJSValue(context, nameValue);
      if (name.has_value() && !name->empty()) _name = name;
    }
    JS_FreeValue(context, nameValue);

    oo::NotificationCenter::defaultCenter().addObserver(
        this, kOOJavaScriptEngineWillResetNotificationName,
        OOJavaScriptEngine::sharedEngine(),
        [this](const oo::Notification&) { deleteJSValue(); });
  }
}

oo::Ref<OOJSFunction> OOJSFunction::initWithName(
    const std::optional<std::string>& name, JSValueConst scope,
    const std::optional<std::string>& code, std::size_t argCount,
    const char** argNames, const std::optional<std::string>& fileName,
    std::size_t lineNumber, JSContext* context) {
  bool OK = true;
  bool releaseContext = false;
  JSValue function = JS_UNDEFINED;
  oo::Ref<OOJSFunction> result;

  if (context == nullptr) {
    context = OOJSAcquireContext();
    releaseContext = true;
  }

  /*	SpiderMonkey's JS_CompileUCFunction() could compile the function in an
          arbitrary scope object. QuickJS has no equivalent, so the function is
          always compiled in the global scope. (The only caller passed NULL,
          meaning the global object, anyway.)
  */
  (void)scope;

  if (!code.has_value() || (argCount > 0 && argNames == nullptr)) OK = false;

  if (OK) {
    assert(argCount < INT_MAX && lineNumber < INT_MAX);

    /*	QuickJS has no API to compile a function from a body and argument
            names, so evaluate a function expression. The wrapper is kept on
            the first line so that line numbers in the body are unchanged.
    */
    std::string source = "(function(";
    std::size_t i;
    for (i = 0; i < argCount; i++) {
      if (i != 0) source += ",";
      source += argNames[i];
    }
    source += "){" + *code + "\n})";

    JSEvalOptions options = {
        .version = JS_EVAL_OPTIONS_VERSION,
        .eval_flags = JS_EVAL_TYPE_GLOBAL,
        .filename = fileName.has_value() ? fileName->c_str() : "<anonymous>",
        .line_num = (int)lineNumber};
    // JS_Eval2() requires a NUL-terminated buffer, which c_str() is.
    function = JS_Eval2(context, source.c_str(), source.size(), &options);
    if (JS_IsException(function)) {
      OOJSReportPendingException(context);
      function = JS_UNDEFINED;
      OK = false;
    } else if (!JS_IsFunction(context, function)) {
      OK = false;
    }
  }

  if (OK && name.has_value()) {
    // Function expression names are read-only but configurable; redefine it.
    JS_DefinePropertyValueStr(
        context, function, "name",
        JS_NewStringLen(context, name->data(), name->size()),
        JS_PROP_CONFIGURABLE);
  }

  if (OK) {
    result = initWithFunction(function, context);
  }
  JS_FreeValue(context, function);

  if (releaseContext) OOJSRelinquishContext(context);

  return result;
}

void OOJSFunction::deleteJSValue() {
  // _function is JS_NULL (not an object) if never set.
  if (JS_IsObject(_function)) {
    JSContext* context = OOJSAcquireContext();
    JS_FreeValue(context, _function);
    OOJSRelinquishContext(context);

    _function = JS_NULL;
    oo::NotificationCenter::defaultCenter().removeObserver(
        this, kOOJavaScriptEngineWillResetNotificationName,
        OOJavaScriptEngine::sharedEngine());
  }
}

OOJSFunction::~OOJSFunction() { deleteJSValue(); }

std::optional<std::string> OOJSFunction::descriptionComponents() const {
  return std::format("{}()", _name.value_or("<anonymous>"));
}

std::optional<std::string> OOJSFunction::name() { return _name; }

bool OOJSFunction::isValid() const {
  // _function is JS_NULL until set, and after reset.
  return JS_IsObject(_function);
}

JSValueConst OOJSFunction::function() {
  return isValid() ? _function : JS_NULL;
}

JSValue OOJSFunction::functionValue() {
  if (EXPECT(isValid())) {
    return JS_DupValue(OOJSAcquireContext(), _function);
  } else {
    return JS_NULL;
  }
}

bool OOJSFunction::evaluateWithContext(JSContext* context, JSValueConst jsThis,
                                       int argc, JSValueConst* argv,
                                       JSValue* result) {
  OOCParameterAssert(result != nullptr);

  if (EXPECT_NOT(!isValid())) {
    *result = JS_UNDEFINED;
    return false;
  }

  // As with JS_CallFunction(), a missing this means the global object.
  JSValue global = JS_UNDEFINED;
  if (!JS_IsObject(jsThis)) {
    global = JS_GetGlobalObject(context);
    jsThis = global;
  }

  OOJSScript::pushScript(nullptr);
  OOJSStartTimeLimiter();
  JSValue rval = JS_Call(context, _function, jsThis, argc, argv);
  OOJSStopTimeLimiter();
  OOJSScript::popScript(nullptr);

  JS_FreeValue(context, global);

  if (JS_IsException(rval)) {
    *result = JS_UNDEFINED;
    return false;
  }
  *result = rval;
  return true;
}
