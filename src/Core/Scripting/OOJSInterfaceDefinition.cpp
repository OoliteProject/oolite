/*

OOJSInterfaceDefinition.mm


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

#include "OOJSInterfaceDefinition.h"
#include "OOJSScript.h"
#include "OOJavaScriptEngine.h"

#include "ooscript/JSEngine.hpp"
#include "oofnd/Notification.hpp"
#include "oofnd/String.hpp"

/*
	Retargeted (bead oo-mqb) onto the ooscript façade (JSEngine.hpp), same pattern as the
	Phase 1 exemplar OOJSVector.mm (bead oo-sdz): the two directly spelled engine calls this
	file makes (RemoveValueRoot, RemoveObjectRoot) go through ooscript::removeValueRoot/
	removeObjectRoot. OOJSAddGCValueRoot/OOJSAddGCObjectRoot are OOJS_* macros, not engine calls, so
	they are out of scope for this sweep and unchanged. The instance variables are façade
	Value/Object values, so their addresses go to the façade calls directly.
*/

namespace {
// -caseInsensitiveCompare: as the definitions used it: a nil receiver answers
// OOOrderedSame (a message to nil); a nil argument compares as the empty string.
static OOComparisonResult CaseInsensitiveCompare(const std::optional<std::string> &a, const std::optional<std::string> &b)
{
	if (!a.has_value())  return OOOrderedSame;
	int order = oo::str::caseInsensitiveCompare(*a, b.value_or(std::string()));
	return (order < 0) ? OOOrderedAscending : ((order > 0) ? OOOrderedDescending : OOOrderedSame);
}
} // namespace


/*	C++20 since bead oo-8fpc (proposed ADR-0056 amendment oo-o89): OOJSInterfaceDefinition. -init after
	[super init] is the constructor, -dealloc the destructor; the engine, the script stack and the
	owning script's weak reference are Objective-C and are messaged as before.
*/

OOJSInterfaceDefinition::OOJSInterfaceDefinition() {
	_callback = ooscript::undefinedValue();
	_callbackThis = NULL;

	_owningScript = OOJSScript::currentlyRunningScript();

	oo::NotificationCenter::defaultCenter().addObserver(this, kOOJavaScriptEngineWillResetNotificationName,
														OOJavaScriptEngine::sharedEngine(),
														[this](const oo::Notification &) { deleteJSPointers(); });
}

void OOJSInterfaceDefinition::deleteJSPointers()
{

	ooscript::Context context = OOJSAcquireContext();
	_callback = ooscript::undefinedValue();
	_callbackThis = NULL;
	ooscript::removeValueRoot((context), (&_callback));
	ooscript::removeObjectRoot((context), &_callbackThis);

	OOJSRelinquishContext(context);

	oo::NotificationCenter::defaultCenter().removeObserver(this, kOOJavaScriptEngineWillResetNotificationName,
															OOJavaScriptEngine::sharedEngine());

}

OOJSInterfaceDefinition::~OOJSInterfaceDefinition()
{
	_owningScript = nullptr;

	deleteJSPointers();
}

std::optional<std::string> OOJSInterfaceDefinition::title()
{
	return _title;
}


void OOJSInterfaceDefinition::setTitle(const std::optional<std::string> &title)
{
	_title = title;
}


std::optional<std::string> OOJSInterfaceDefinition::category()
{
	return _category;
}


void OOJSInterfaceDefinition::setCategory(const std::string &category)
{
	_category = category;
}


std::optional<std::string> OOJSInterfaceDefinition::summary()
{
	return _summary;
}


void OOJSInterfaceDefinition::setSummary(const std::string &summary)
{
	_summary = summary;
}


ooscript::Value OOJSInterfaceDefinition::callback()
{
	return _callback;
}


void OOJSInterfaceDefinition::setCallback(ooscript::Value callback)
{
	ooscript::Context context = OOJSAcquireContext();
	ooscript::removeValueRoot((context), (&_callback));
	_callback = callback;
	OOJSAddGCValueRoot(context, &_callback, "OOJSInterfaceDefinition callback function");
	OOJSRelinquishContext(context);
}


ooscript::Object OOJSInterfaceDefinition::callbackThis()
{
	return _callbackThis;
}


void OOJSInterfaceDefinition::setCallbackThis(ooscript::Object callbackThis)
{
	ooscript::Context context = OOJSAcquireContext();
	ooscript::removeObjectRoot((context), &_callbackThis);
	_callbackThis = callbackThis;
	OOJSAddGCObjectRoot(context, &_callbackThis, "OOJSInterfaceDefinition callback this");
	OOJSRelinquishContext(context);
}


void OOJSInterfaceDefinition::runCallback(const std::string &key)
{
	::OOJavaScriptEngine *engine = OOJavaScriptEngine::sharedEngine();
	ooscript::Context context = OOJSAcquireContext();		
	ooscript::Value					rval = ooscript::undefinedValue();

	ooscript::Value         cKey = OOJSValueFromPList(context, oo::PList(key));

	const oo::WeakRef<OOJSScript> owner = _owningScript; // local copy needed
	OOJSScript::pushScript(owner);
	
	engine->callJSFunction(_callback, _callbackThis, 1, &cKey, &rval);
	
	OOJSScript::popScript(owner.get());

	OOJSRelinquishContext(context);
}


OOComparisonResult OOJSInterfaceDefinition::interfaceCompare(OOJSInterfaceDefinition *other)
{
	OOComparisonResult byCategory = CaseInsensitiveCompare(_category, (other != nullptr) ? other->category() : std::nullopt);
	if (byCategory == OOOrderedSame)
	{
		return CaseInsensitiveCompare(_title, (other != nullptr) ? other->title() : std::nullopt);
	}
	else
	{
		return byCategory;
	}
}

