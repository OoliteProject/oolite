/*

OOJSPrivateObject.h

The engine glue for a JS object whose private slot holds a C++ object (proposed ADR-0056
amendment oo-6symp, which carries out amendment oo-ppc item 5). While the slot held an
Objective-C object, the engine reached it by selector: -oo_jsValueInContext: to wrap it,
-oo_clearJSSelf: when the wrapper was finalized, -cxx_oo_jsDescription for toString(). A
converted class whose JS object holds it directly implements OOJSPrivateObject instead, and its
JS class uses the functions below in place of DEFINE_JS_OBJECT_GETTER, OOJSObjectWrapperFinalize
and OOJSObjectWrapperToString. The slot holds the object as an oo::RefCounted * with one retain,
which the finalizer releases.

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

#include "ooscript/JSEngine.hpp"
#include "oofnd/Ref.hpp"

#include <optional>
#include <string>


/*	The JS glue of a C++ object, the selectors of OOObject (OOJavaScriptConversion) as virtual
	members. A class implements it beside oo::RefCounted (class X : public Base, public
	OOJSPrivateObject); the engine reaches it from the slot's oo::RefCounted * by dynamic_cast.
*/
class OOJSPrivateObject
{
public:
	virtual ~OOJSPrivateObject() = default;

	// -oo_jsValueInContext: the object's JS value, its wrapper made on first use.
	virtual ooscript::Value jsValueInContext(ooscript::Context context) = 0;

	// -oo_clearJSSelf: the wrapper selfVal is being finalized; forget it if it is the object's.
	virtual void clearJSSelf(ooscript::Object selfVal) = 0;

	// -cxx_oo_jsDescription: what toString() answers; nullopt for "[object <JS class name>]".
	virtual std::optional<std::string> jsDescription()  { return std::nullopt; }
};


// The JS value of object (its virtual jsValueInContext()); JS null for null, as for nil.
ooscript::Value OOJSValueFromCxxObject(ooscript::Context context, OOJSPrivateObject *object);

// Puts object in jsObject's private slot with one retain, released by
// OOJSCxxObjectWrapperFinalize(). False, with nothing retained, if the slot cannot be set.
bool OOJSSetCxxPrivate(ooscript::Context context, ooscript::Object jsObject, oo::RefCounted *object);

/*	DEFINE_JS_OBJECT_GETTER for a slot that holds a C++ object: false, with the engine's error
	("Native method expected <class>, got <object>."), if object is not of requiredJSClass or a
	subclass registered with OOJSRegisterSubclass(); else *outObject is the slot's object,
	borrowed, or null (a prototype has none). Requires a request on context.
*/
bool OOJSGetCxxPrivateImpl(ooscript::Context context, ooscript::Object object, ooscript::ClassDef *requiredJSClass, oo::RefCounted **outObject);

template <class T>
bool OOJSGetCxxPrivate(ooscript::Context context, ooscript::Object object, ooscript::ClassDef *requiredJSClass, T **outObject)
{
	oo::RefCounted *held = nullptr;
	if (!OOJSGetCxxPrivateImpl(context, object, requiredJSClass, &held))  return false;
	*outObject = static_cast<T *>(held);
	return true;
}

// The finalize hook of a JS class whose slot holds a C++ object: tells the object its wrapper is
// gone (clearJSSelf), releases the slot's retain and empties the slot.
void OOJSCxxObjectWrapperFinalize(ooscript::Context context, ooscript::Object thisObj);

/*	toString() for such a class, called from a one-line native that names the class: the object's
	jsDescription(), else "[object <JS class name>]" (also for a prototype, which has no object).
	A `this` of another class is described as OOJSObjectWrapperToString() describes it.
*/
bool OOJSCxxObjectWrapperToString(ooscript::Context context, ooscript::CallArgs &oojsArgs, ooscript::ClassDef *jsClass);

#endif	// OOJSPRIVATEOBJECT_H
