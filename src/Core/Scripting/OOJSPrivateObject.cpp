/*

OOJSPrivateObject.cpp

The engine glue for a JS object whose private slot holds a C++ object. Each function is the C++
counterpart of the Objective-C one named beside it in OOJavaScriptEngine.mm, dispatching to
OOJSPrivateObject's virtual members where that one sent a selector to an id.

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

#define OO_PLAIN_CPP_UNIT 1 // a plain C++ unit: the shared headers' game-unit parts stay out of it (bead oo-dbz)
#include "OOJSPrivateObject.h"
#include "OOJSEngineCore.h"
#include "oofnd/String.hpp"

#include <string>

// OOJSValueFromNativeObject(): nil is null, anything else answers -oo_jsValueInContext:.
JSValue OOJSValueFromCxxObject(JSContext* context, OOJSPrivateObject* object)
{
    if (object == nullptr)
        return JS_NULL;
    return object->jsValueInContext(context);
}

// JS_SetOpaque(jsObject, [object retain]), without the retain on failure.
bool OOJSSetCxxPrivate(JSValueConst jsObject, oo::RefCounted* object)
{
    if (object != nullptr)
        object->retain();
    if (JS_SetOpaque(jsObject, object) == 0)
        return true;
    if (object != nullptr)
        object->release();
    return false;
}

// OOJSObjectGetterImplPRIVATE(): the same JS class check and error; the slot's object is taken as
// it is (a C++ slot holds no weak reference to unpack).
bool OOJSGetCxxPrivateImpl(JSContext* context, JSValueConst object, JSClassID requiredClassID, oo::RefCounted** outObject)
{
    OOJS_PROFILE_ENTER

    OOCParameterAssert(context != NULL && requiredClassID != 0 && outObject != NULL);

    /*
            Ensure it's a valid type of JS object. This is absolutely necessary, because if we
            don't check it we'll crash trying to get the private field of something that isn't a
            native object wrapper - for example, Ship.setAI.call(new Vector3D, "") is valid
            JavaScript.
    */
    JSClassID actualClassID = JS_GetClassID(object);
    if (EXPECT_NOT(!OOJSIsSubclass(actualClassID, requiredClassID))) {
        const char* className = OOJSClassName(requiredClassID);
        std::optional<std::string> got = cxx_OOStringFromJSValue(context, object);
        cxx_OOJSReportError(context, "Native method expected %s, got %s.", className != NULL ? className : "(null)", got ? got->c_str() : "(null)");
        return false;
    }

    JSClassID ignored;
    *outObject = static_cast<oo::RefCounted*>(JS_GetAnyOpaque(object, &ignored));
    return true;

    OOJS_PROFILE_EXIT
}

// OOJSObjectWrapperFinalize(): -oo_clearJSSelf: to the object, then the slot's release.
void OOJSCxxObjectWrapperFinalize(JSRuntime* /*runtime*/, JSValueConst thisObj)
{
    OOJS_PROFILE_ENTER

    JSClassID ignored;
    oo::RefCounted* object = static_cast<oo::RefCounted*>(JS_GetAnyOpaque(thisObj, &ignored));
    if (object != nullptr) {
        if (OOJSPrivateObject* glue = dynamic_cast<OOJSPrivateObject*>(object))
            glue->clearJSSelf(thisObj);
        JS_SetOpaque(thisObj, nullptr);
        object->release();
    }

    OOJS_PROFILE_EXIT_VOID
}

// OOJSObjectWrapperToString(): the object's -cxx_oo_jsDescription, else "[object <JS class name>]".
JSValue OOJSCxxObjectWrapperToString(JSContext* context, JSValueConst thisVal, JSClassID jsClassID)
{
    OOJS_NATIVE_ENTER(context)

    if (!OOJSIsMemberOfSubclass(context, thisVal, jsClassID)) {
        return OOJSObjectWrapperToString(context, thisVal, 0, nullptr);
    }

    std::optional<std::string> description;
    JSClassID ignored;
    oo::RefCounted* object = static_cast<oo::RefCounted*>(JS_GetAnyOpaque(thisVal, &ignored));
    if (OOJSPrivateObject* glue = dynamic_cast<OOJSPrivateObject*>(object))
        description = glue->jsDescription();
    if (!description.has_value()) {
        const char* className = OOJSClassName(JS_GetClassID(thisVal));
        description = oo::str::format("[object %s]", className != NULL ? className : "");
    }

    return JS_NewStringLen(context, description->data(), description->size());

    OOJS_NATIVE_EXIT
}
