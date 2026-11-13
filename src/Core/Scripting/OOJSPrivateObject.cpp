/*

OOJSPrivateObject.cpp

The engine glue for a JS object whose private slot holds a C++ object. Each
function is the C++ counterpart of the one named beside it in
OOJavaScriptEngine.cpp, dispatching to OOJSPrivateObject's virtual members.

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

#define OO_PLAIN_CPP_UNIT \
  1  // a plain C++ unit: the shared headers' game-unit parts stay out of it
#include "OOJSPrivateObject.h"

#include <format>
#include <memory>
#include <string>

#include "OOJSEngineCore.h"
#include "oofnd/String.hpp"

// OOJSValueFromNativeObject(): nil is null, anything else answers
// -oo_jsValueInContext:.
JSValue OOJSValueFromCxxObject(JSContext* context, OOJSPrivateObject* object) {
  if (object == nullptr) return JS_NULL;
  return object->jsValueInContext(context);
}

// JS_SetOpaque(jsObject, holder of object), the holder deleted on failure.
bool OOJSSetCxxPrivate(JSValueConst jsObject,
                       std::shared_ptr<oo::Object> object) {
  std::unique_ptr<std::shared_ptr<oo::Object>> holder;
  if (object != nullptr)
    holder = std::make_unique<std::shared_ptr<oo::Object>>(std::move(object));
  if (JS_SetOpaque(jsObject, holder.get()) != 0) return false;
  (void)holder.release();  // the slot owns it; the finalizer deletes it
  return true;
}

// OOJSObjectGetterImplPRIVATE(): the same JS class check and error; the slot's
// object is taken as it is (a C++ slot holds no weak reference to unpack).
bool OOJSGetCxxPrivateImpl(JSContext* context, JSValueConst object,
                           JSClassID requiredClassID, oo::Object** outObject) {
  OOJS_PROFILE_ENTER

  OOCParameterAssert(context != nullptr && requiredClassID != 0 &&
                     outObject != nullptr);

  /*
          Ensure it's a valid type of JS object. This is absolutely necessary,
     because if we don't check it we'll crash trying to get the private field of
     something that isn't a native object wrapper - for example,
     Ship.setAI.call(new Vector3D, "") is valid JavaScript.
  */
  JSClassID actualClassID = JS_GetClassID(object);
  if (EXPECT_NOT(!OOJSIsSubclass(actualClassID, requiredClassID))) {
    const char* className = OOJSClassName(requiredClassID);
    std::optional<std::string> got = OOStringFromJSValue(context, object);
    OOJSReportError(context, "Native method expected %s, got %s.",
                    className != nullptr ? className : "(null)",
                    got ? got->c_str() : "(null)");
    return false;
  }

  JSClassID ignored;
  *outObject = OOJSCxxPrivateFromOpaque(JS_GetAnyOpaque(object, &ignored));
  return true;

  OOJS_PROFILE_EXIT
}

// OOJSObjectWrapperFinalize(): -oo_clearJSSelf: to the object, then the slot is
// emptied and its holder deleted (the slot's release).
void OOJSCxxObjectWrapperFinalize(JSRuntime* /*runtime*/,
                                  JSValueConst thisObj) {
  OOJS_PROFILE_ENTER

  JSClassID ignored;
  std::unique_ptr<std::shared_ptr<oo::Object>> holder(
      static_cast<std::shared_ptr<oo::Object>*>(
          JS_GetAnyOpaque(thisObj, &ignored)));
  if (holder != nullptr) {
    if (OOJSPrivateObject* glue =
            dynamic_cast<OOJSPrivateObject*>(holder->get()))
      glue->clearJSSelf(thisObj);
    JS_SetOpaque(thisObj, nullptr);
    holder.reset();  // the slot's release
  }

  OOJS_PROFILE_EXIT_VOID
}

// OOJSObjectWrapperToString(): the object's -oo_jsDescription, else
// "[object <JS class name>]".
JSValue OOJSCxxObjectWrapperToString(JSContext* context, JSValueConst thisVal,
                                     JSClassID jsClassID) {
  OOJS_NATIVE_ENTER(context)

  if (!OOJSIsMemberOfSubclass(context, thisVal, jsClassID)) {
    return OOJSObjectWrapperToString(context, thisVal, 0, nullptr);
  }

  std::optional<std::string> description;
  JSClassID ignored;
  oo::Object* object =
      OOJSCxxPrivateFromOpaque(JS_GetAnyOpaque(thisVal, &ignored));
  if (OOJSPrivateObject* glue = dynamic_cast<OOJSPrivateObject*>(object))
    description = glue->jsDescription();
  if (!description.has_value()) {
    const char* className = OOJSClassName(JS_GetClassID(thisVal));
    description =
        std::format("[object {}]", className != nullptr ? className : "");
  }

  return JS_NewStringLen(context, description->data(), description->size());

  OOJS_NATIVE_EXIT
}
