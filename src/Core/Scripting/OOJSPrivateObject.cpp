/*

OOJSPrivateObject.cpp

The engine glue for a JS object whose private slot holds a C++ object (proposed ADR-0056
amendment oo-6symp). Each function is the C++ counterpart of the Objective-C one named beside it
in OOJavaScriptEngine.mm, dispatching to OOJSPrivateObject's virtual members where that one sent
a selector to an id.

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

#define OO_PLAIN_CPP_UNIT 1	// a plain C++ unit: the shared headers' game-unit parts stay out of it (bead oo-dbz)
#include "OOJSPrivateObject.h"
#include "OOJSEngineCore.h"
#include "oofnd/String.hpp"

#include <cstdint>
#include <string>


// OOJSValueFromNativeObject(): nil is null, anything else answers -oo_jsValueInContext:.
ooscript::Value OOJSValueFromCxxObject(ooscript::Context context, OOJSPrivateObject *object)
{
	if (object == nullptr)  return ooscript::nullValue();
	return object->jsValueInContext(context);
}


// ooscript::setPrivate(context, jsObject, [object retain]), without the retain on failure.
bool OOJSSetCxxPrivate(ooscript::Context context, ooscript::Object jsObject, oo::RefCounted *object)
{
	if (object != nullptr)  object->retain();
	if (ooscript::setPrivate(context, jsObject, object))  return true;
	if (object != nullptr)  object->release();
	return false;
}


// OOJSObjectGetterImplPRIVATE(): the same JS class check and error; the slot's object is taken as
// it is (a C++ slot holds no weak reference to unpack).
bool OOJSGetCxxPrivateImpl(ooscript::Context context, ooscript::Object object, ooscript::ClassDef *requiredJSClass, oo::RefCounted **outObject)
{
	OOJS_PROFILE_ENTER

	OOCParameterAssert(context != NULL && object != NULL && requiredJSClass != NULL && outObject != NULL);

	ooscript::ClassDef *actualClass = OOJSGetClass(context, object);
	if (EXPECT_NOT(!OOJSIsSubclass(actualClass, requiredJSClass)))
	{
		std::optional<std::string> got = cxx_OOStringFromJSValue(context, ooscript::objectValue(object));
		cxx_OOJSReportError(context, "Native method expected %s, got %s.", requiredJSClass->name, got ? got->c_str() : "(null)");
		return false;
	}
	OOCAssert(static_cast<std::uint32_t>(actualClass->flags) & static_cast<std::uint32_t>(ooscript::ClassFlag::HasPrivate), "Native object accessor requires JS class with private storage.");

	*outObject = static_cast<oo::RefCounted *>(ooscript::getPrivate(context, object));
	return true;

	OOJS_PROFILE_EXIT
}


// OOJSObjectWrapperFinalize(): -oo_clearJSSelf: to the object, then the slot's release.
void OOJSCxxObjectWrapperFinalize(ooscript::Context context, ooscript::Object thisObj)
{
	OOJS_PROFILE_ENTER

	oo::RefCounted *object = static_cast<oo::RefCounted *>(ooscript::getPrivate(context, thisObj));
	if (object != nullptr)
	{
		if (OOJSPrivateObject *glue = dynamic_cast<OOJSPrivateObject *>(object))  glue->clearJSSelf(thisObj);
		object->release();
		ooscript::setPrivate(context, thisObj, nullptr);
	}

	OOJS_PROFILE_EXIT_VOID
}


// OOJSObjectWrapperToString(): the object's -cxx_oo_jsDescription, else "[object <JS class name>]".
bool OOJSCxxObjectWrapperToString(ooscript::Context context, ooscript::CallArgs &oojsArgs, ooscript::ClassDef *jsClass)
{
	OOJS_NATIVE_ENTER(context)

	ooscript::Object thisObj = OOJS_THIS;
	if (thisObj == nullptr || !OOJSIsSubclass(OOJSGetClass(context, thisObj), jsClass))
	{
		return OOJSObjectWrapperToString(context, oojsArgs);
	}

	std::optional<std::string> description;
	oo::RefCounted *object = static_cast<oo::RefCounted *>(ooscript::getPrivate(context, thisObj));
	if (OOJSPrivateObject *glue = dynamic_cast<OOJSPrivateObject *>(object))  description = glue->jsDescription();
	if (!description.has_value())  description = oo::str::format("[object %s]", OOJSGetClass(context, thisObj)->name);

	const std::u16string units = oo::utf8ToUtf16(*description);
	OOJS_RETURN(ooscript::stringValue(ooscript::newUCStringCopyN(context, reinterpret_cast<const ooscript::Char16 *>(units.data()), units.size())));

	OOJS_NATIVE_EXIT
}
