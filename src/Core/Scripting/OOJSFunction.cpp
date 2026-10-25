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
#include "OOJSScript.h"
#include "OOJSEngineTimeManagement.h"
#include "oofnd/Notification.hpp"
#include "oofnd/objc/OOAssert.h"
#include "oofnd/String.hpp"


/*	C++20 since bead oo-3smy (proposed ADR-0056): OOJSFunction. The initialisers answered nil
	for their input, so they are static factories of the same name (amendment oo-novu item 1); the
	part of -initWithFunction:context: that cannot fail is the private constructor. The engine,
	the script stack and the wrapped arguments are Objective-C and are messaged as before.
*/

oo::Ref<OOJSFunction> OOJSFunction::initWithFunction(ooscript::Function function, ooscript::Context context)
{
	OOCParameterAssert(context != NULL);

	if (function == NULL)
	{
		return nullptr;
	}

	return oo::adopt(new OOJSFunction(function, context));
}


OOJSFunction::OOJSFunction(ooscript::Function function, ooscript::Context context)
{
	{
		_function = function;
		OOJSAddGCObjectRoot(context, (ooscript::Object *)&_function, "OOJSFunction._function");
		_name = cxx_OOStringFromJSString(context, ooscript::getFunctionId(function));

		oo::NotificationCenter::defaultCenter().addObserver(this, kOOJavaScriptEngineWillResetNotificationName,
															OOJavaScriptEngine::sharedEngine(),
															[this](const oo::Notification &) { deleteJSValue(); });
	}
}


oo::Ref<OOJSFunction> OOJSFunction::initWithName(const std::optional<std::string> &name,
												 ooscript::Object scope,
												 const std::optional<std::string> &code,
												 NSUInteger argCount,
												 const char **argNames,
												 const std::optional<std::string> &fileName,
												 NSUInteger lineNumber,
												 ooscript::Context context)
{
	bool						OK = true;
	bool						releaseContext = false;
	ooscript::Char16						*buffer = NULL;
	size_t						length = 0;
	ooscript::Function function = NULL;
	oo::Ref<OOJSFunction>		result;

	if (context == NULL)
	{
		context = OOJSAcquireContext();
		releaseContext = true;
	}
	if (scope == NULL)  scope = OOJavaScriptEngine::sharedEngine()->globalObject();

	if (!code.has_value() || (argCount > 0 && argNames == NULL))  OK = false;

	// ooscript::Char16 is a 16-bit element; the code's UTF-16 units go in as -getCharacters: gave them.
	std::u16string units;
	if (OK)
	{
		units = oo::utf8ToUtf16(*code);

		length = units.size();
		buffer = (ooscript::Char16 *)malloc(sizeof(ooscript::Char16) * length);
		if (buffer == NULL)  OK = false;
	}

	if (OK)
	{
		assert(argCount < UINT32_MAX);

		std::copy(units.begin(), units.end(), buffer);

		function = ooscript::compileUCFunction(context, scope, name.has_value() ? name->c_str() : NULL, (uint32_t)argCount, argNames, buffer, length, fileName.has_value() ? fileName->c_str() : NULL, (uint32_t)lineNumber);
		if (function == NULL)  OK = false;

		free(buffer);
	}

	if (OK)
	{
		result = initWithFunction(function, context);
	}

	if (releaseContext)  OOJSRelinquishContext(context);

	return result;
}


void OOJSFunction::deleteJSValue()
{
	if (_function != NULL)
	{
		ooscript::Context context = OOJSAcquireContext();
		ooscript::removeObjectRoot(context, (ooscript::Object *)&_function);
		OOJSRelinquishContext(context);

		_function = NULL;
		oo::NotificationCenter::defaultCenter().removeObserver(this, kOOJavaScriptEngineWillResetNotificationName,
																OOJavaScriptEngine::sharedEngine());
	}
}


OOJSFunction::~OOJSFunction()
{
	deleteJSValue();
}


std::optional<std::string> OOJSFunction::descriptionComponents() const
{
	return oo::str::format("%s()", _name.value_or("<anonymous>").c_str());
}


std::optional<std::string> OOJSFunction::name()
{
	return _name;
}


ooscript::Function OOJSFunction::function()
{
	return _function;
}


ooscript::Value OOJSFunction::functionValue()
{
	if (EXPECT(_function != NULL))
	{
		return ooscript::objectValue(ooscript::getFunctionObject(_function));
	}
	else
	{
		return ooscript::nullValue();
	}

}


bool OOJSFunction::evaluateWithContext(ooscript::Context context,
									   ooscript::Object jsThis,
									   unsigned argc,
									   ooscript::Value *argv,
									   ooscript::Value *result)
{
	OOJSScript::pushScript(nullptr);
	OOJSStartTimeLimiter();
	bool OK = ooscript::callFunction(context, jsThis, _function, argc, argv, result);
	OOJSStopTimeLimiter();
	OOJSScript::popScript(nullptr);

	return OK;
}

// (The object-wrapper evaluations, evaluateWithContext(id jsThis, arguments) and
// evaluatePredicateWithContext(), went with OOJSValueFromNativeObject(), bead oo-4aq6a.6.2.)

