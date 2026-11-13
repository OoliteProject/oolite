/*

OOJSPrivateObject.h

The engine glue for a JS object whose private slot (QuickJS's opaque pointer)
holds a C++ object. A class whose JS object holds it directly implements
OOJSPrivateObject, and its JS class uses the functions below in place of
DEFINE_JS_OBJECT_GETTER, OOJSObjectWrapperFinalize and
OOJSObjectWrapperToString. The slot holds a heap std::shared_ptr<oo::Object>
owning the object, which the finalizer deletes.

Ownership follows OOJavaScriptEngine.h's conventions: JSValueConst parameters
are borrowed, returned JSValues are owned by the caller.

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

#pragma once

#include <quickjs.h>

#include <memory>
#include <optional>
#include <string>

#include "oofnd/Object.hpp"

/*	The JS glue of a C++ object, the selectors of OOObject
   (OOJavaScriptConversion) as virtual members. A class implements it beside
   oo::Object (class X : public Base, public OOJSPrivateObject); the engine
   reaches it from the slot's oo::Object by dynamic_cast.
*/
class OOJSPrivateObject {
 public:
  virtual ~OOJSPrivateObject() = default;

  // -oo_jsValueInContext: the object's JS value, owned by the caller (its
  // wrapper made on first use); JS_UNDEFINED if it has none.
  virtual JSValue jsValueInContext(JSContext* context) = 0;

  // -oo_clearJSSelf: the wrapper selfVal is being finalized; forget it if it is
  // the object's. selfVal is borrowed and must not be freed.
  virtual void clearJSSelf(JSValueConst selfVal) = 0;

  // -cxx_oo_jsDescription: what toString() answers; nullopt for "[object <JS
  // class name>]".
  virtual std::optional<std::string> jsDescription() { return std::nullopt; }
};

// The JS value of object (its virtual jsValueInContext()), owned by the caller;
// JS null for null, as OOJSValueFromNativeObject() gives for nil.
JSValue OOJSValueFromCxxObject(JSContext* context, OOJSPrivateObject* object);

// Puts object in jsObject's private slot: the slot holds a heap
// std::shared_ptr<oo::Object> (one owner), which OOJSCxxObjectWrapperFinalize()
// deletes; null leaves the slot empty. False, holding nothing, if the slot
// cannot be set (jsObject is not an object of a class with a slot).
bool OOJSSetCxxPrivate(JSValueConst jsObject,
                       std::shared_ptr<oo::Object> object);

// The object a C++ object's slot holds, borrowed (null for an empty slot), from
// what JS_GetOpaque() or JS_GetAnyOpaque() answered for it.
inline oo::Object* OOJSCxxPrivateFromOpaque(void* opaque) noexcept {
  return opaque != nullptr
             ? static_cast<std::shared_ptr<oo::Object>*>(opaque)->get()
             : nullptr;
}

/*	DEFINE_JS_OBJECT_GETTER for a slot that holds a C++ object: false, with
   the engine's error
        ("Native method expected <class>, got <object>.") pending, if object is
   not of requiredClassID or a subclass registered with OOJSRegisterSubclass();
   else *outObject is the slot's object, borrowed, or null (a prototype has
   none).
*/
bool OOJSGetCxxPrivateImpl(JSContext* context, JSValueConst object,
                           JSClassID requiredClassID, oo::Object** outObject);

template <class T>
bool OOJSGetCxxPrivate(JSContext* context, JSValueConst object,
                       JSClassID requiredClassID, T** outObject) {
  oo::Object* held = nullptr;
  if (!OOJSGetCxxPrivateImpl(context, object, requiredClassID, &held))
    return false;
  *outObject = static_cast<T*>(held);
  return true;
}

// The finalizer (JSClassDef.finalizer) of a JS class whose slot holds a C++
// object: tells the object its wrapper is gone (clearJSSelf), empties the slot
// and deletes its holder (releasing the object).
void OOJSCxxObjectWrapperFinalize(JSRuntime* runtime, JSValueConst thisObj);

/*	toString() for such a class, called from a one-line native that names
   the class: the object's jsDescription(), else "[object <JS class name>]"
   (also for a prototype, which has no object). A `this` of another class is
   described as OOJSObjectWrapperToString() describes it. Returns an owned
   string, or JS_EXCEPTION.
*/
JSValue OOJSCxxObjectWrapperToString(JSContext* context, JSValueConst thisVal,
                                     JSClassID jsClassID);
