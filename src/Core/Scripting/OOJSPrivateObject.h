/*

OOJSPrivateObject.h

The engine glue for a JS object whose private slot (QuickJS's opaque pointer) holds a C++ object.
While the slot held an Objective-C object, the engine reached it by selector: -oo_jsValueInContext:
to wrap it, -oo_clearJSSelf: when the wrapper was finalized, -cxx_oo_jsDescription for toString().
A converted class whose JS object holds it directly implements OOJSPrivateObject instead, and its
JS class uses the functions below in place of DEFINE_JS_OBJECT_GETTER, OOJSObjectWrapperFinalize
and OOJSObjectWrapperToString. The slot holds the object as an oo::RefCounted * with one retain,
which the finalizer releases.

Ownership follows OOJavaScriptEngine.h's conventions: JSValueConst parameters are borrowed,
returned JSValues are owned by the caller.

Plain C++: nothing here declares or messages an Objective-C class.

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

#ifndef OOJSPRIVATEOBJECT_H
#define OOJSPRIVATEOBJECT_H

#include "oofnd/Ref.hpp"

#include <quickjs.h>

#include <optional>
#include <string>

/*	The JS glue of a C++ object, the selectors of OOObject (OOJavaScriptConversion) as virtual
        members. A class implements it beside oo::RefCounted (class X : public Base, public
        OOJSPrivateObject); the engine reaches it from the slot's oo::RefCounted * by dynamic_cast.
*/
class OOJSPrivateObject {
public:
    virtual ~OOJSPrivateObject() = default;

    // -oo_jsValueInContext: the object's JS value, owned by the caller (its wrapper made on first
    // use); JS_UNDEFINED if it has none.
    virtual JSValue jsValueInContext(JSContext* context) = 0;

    // -oo_clearJSSelf: the wrapper selfVal is being finalized; forget it if it is the object's.
    // selfVal is borrowed and must not be freed.
    virtual void clearJSSelf(JSValueConst selfVal) = 0;

    // -cxx_oo_jsDescription: what toString() answers; nullopt for "[object <JS class name>]".
    virtual std::optional<std::string> jsDescription() { return std::nullopt; }
};

// The JS value of object (its virtual jsValueInContext()), owned by the caller; JS null for null,
// as OOJSValueFromNativeObject() gives for nil.
JSValue OOJSValueFromCxxObject(JSContext* context, OOJSPrivateObject* object);

// Puts object in jsObject's private slot with one retain, released by
// OOJSCxxObjectWrapperFinalize(). False, with nothing retained, if the slot cannot be set
// (jsObject is not an object of a class with a slot).
bool OOJSSetCxxPrivate(JSValueConst jsObject, oo::RefCounted* object);

/*	DEFINE_JS_OBJECT_GETTER for a slot that holds a C++ object: false, with the engine's error
        ("Native method expected <class>, got <object>.") pending, if object is not of
        requiredClassID or a subclass registered with OOJSRegisterSubclass(); else *outObject is the
        slot's object, borrowed, or null (a prototype has none).
*/
bool OOJSGetCxxPrivateImpl(JSContext* context, JSValueConst object, JSClassID requiredClassID, oo::RefCounted** outObject);

template <class T>
bool OOJSGetCxxPrivate(JSContext* context, JSValueConst object, JSClassID requiredClassID, T** outObject)
{
    oo::RefCounted* held = nullptr;
    if (!OOJSGetCxxPrivateImpl(context, object, requiredClassID, &held))
        return false;
    *outObject = static_cast<T*>(held);
    return true;
}

// The finalizer (JSClassDef.finalizer) of a JS class whose slot holds a C++ object: tells the
// object its wrapper is gone (clearJSSelf), releases the slot's retain and empties the slot.
void OOJSCxxObjectWrapperFinalize(JSRuntime* runtime, JSValueConst thisObj);

/*	toString() for such a class, called from a one-line native that names the class: the object's
        jsDescription(), else "[object <JS class name>]" (also for a prototype, which has no object).
        A `this` of another class is described as OOJSObjectWrapperToString() describes it. Returns
        an owned string, or JS_EXCEPTION.
*/
JSValue OOJSCxxObjectWrapperToString(JSContext* context, JSValueConst thisVal, JSClassID jsClassID);

#endif // OOJSPRIVATEOBJECT_H
