/*

OOJSMissionVariables.h

JavaScript mission variables object.


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

#include "OOJSMissionVariables.h"
#include "OOJavaScriptEngine.h"
#include "OOIsNumberLiteral.h"

#include "OOJSPlayer.h"
#include "oofnd/objc/OOAssert.h"

#include "ooscript/JSEngine.hpp"
#include <cstring>
#include "oofnd/String.hpp"

/*
	Retargeted onto the ooscript façade (JSEngine.hpp) the way OOJSVector.mm does it (bead
	oo-sdz, the sweep exemplar; see also OOJSClock.mm): the class dispatch table becomes a
	static ooscript::ClassDef (the stub hooks are nullptr), the class-creation call becomes
	ooscript::defineObject, the property-name-to-id call in the enumerate hook becomes
	ooscript::valueToId, and the directly spelled numeric-conversion call becomes
	ooscript::newNumberValue. `this` is renamed to `thisObj` because it is a reserved word once
	this file compiles as Objective-C++ (ADR-0001). The class hooks (delProperty, getProperty,
	setProperty) and the new-enumerate protocol hook now take the façade's Context/Object/
	PropertyId/Value signature directly, so no conversion is needed anywhere in the file.
*/
/*
	C++20 since bead oo-s4ns, converted the way bead oo-ppc converted OOJSVector.mm (proposed
	ADR-0056 amendment oo-ppc). The JS class was already C++ on the ooscript façade;
	OOJS_NATIVE_ENTER/EXIT and OOJS_PROFILE_ENTER/EXIT are C++ try/catch and scope guards
	(OOJSEngineNativeWrappers.h); BOOL/YES/NO are bool/true/false. Nothing else in the file was
	Objective-C: the player (PlayerEntity), which is not converted, is still messaged, which is why
	the file is still .mm until Phase 4.
*/

namespace ooscript { }
using ooscript::Context;
using ooscript::Object;
using ooscript::Value;
using ooscript::PropertyId;
using ooscript::ClassDef;
using ooscript::ClassFlag;
using ooscript::PropertyFlag;
using ooscript::EnumerateOp;

namespace {
static std::optional<std::string> KeyForPropertyID(ooscript::Context context, ooscript::PropertyId propID)
{
	OOCParameterAssert(ooscript::isStringId(propID));
	
	std::string key = cxx_OOStringFromJSString(context, ooscript::idToString(propID)).value_or(std::string());
	if (oo::str::hasPrefix(key, "_"))  return std::nullopt;
	return "mission_" + key;
}


// The state of a missionVariables enumeration, kept in the enumeration's private slot (was a
// retained Foundation enumerator over a copy of the keys).
struct MissionVariablesEnumerationState
{
	std::vector<std::string>	keys;
	std::size_t					next = 0;
};
} // namespace


namespace {
static bool MissionVariablesDeleteProperty(Context cx, Object obj, PropertyId propID, Value *value);
} // namespace
namespace {
static bool MissionVariablesGetProperty(Context cx, Object obj, PropertyId propID, Value *value);
} // namespace
namespace {
static bool MissionVariablesSetProperty(Context cx, Object obj, PropertyId propID, bool strict, Value *value);
} // namespace
namespace {
static bool MissionVariablesEnumerate(Context cx, Object obj, EnumerateOp enumOp, Value *state, PropertyId *idp);
} // namespace

#ifndef NDEBUG
namespace {
static oo::PList MissionVariablesConverter(ooscript::Context context, ooscript::Object object);
} // namespace
#endif


namespace {
static ClassDef sMissionVariablesClass =
{
	"MissionVariables",
	ClassFlag::NewEnumerate,
	
	nullptr,							// addProperty (engine default: PropertyStub)
	MissionVariablesDeleteProperty,	// delProperty
	MissionVariablesGetProperty,		// getProperty
	MissionVariablesSetProperty,		// setProperty
	nullptr,							// enumerate (ooscript::ClassFlag::NewEnumerate: newEnumerate used instead)
	MissionVariablesEnumerate,			// newEnumerate
	nullptr,							// resolve (engine default: ResolveStub)
	nullptr,							// convert (engine default: ConvertStub)
	nullptr,							// finalize (engine default: FinalizeStub)
	nullptr,							// call
	nullptr,							// construct
	nullptr,							// backend: owned by the façade backend, must start null
};
} // namespace


void InitOOJSMissionVariables(ooscript::Context context, ooscript::Object global)
{
	ooscript::defineObject((context), (global), "missionVariables", &sMissionVariablesClass, nullptr, OOJS_PROP_READONLY);
	
#ifndef NDEBUG
	// Allow callObjC() on missionVariables to call methods on the mission variables dictionary.
	OOJSRegisterObjectConverter(&sMissionVariablesClass, MissionVariablesConverter);
#endif
}


#ifndef NDEBUG
namespace {
static oo::PList MissionVariablesConverter(ooscript::Context context, ooscript::Object object)
{
	(void)context;
	(void)object;
	return (PLAYER != nullptr ? PLAYER->missionVariables() : oo::PList());
}
} // namespace
#endif


namespace {
static bool MissionVariablesDeleteProperty(Context cx, Object obj, PropertyId propID, Value *value)
{
	ooscript::Context context = (cx);
	ooscript::Object thisObj = (obj);
	ooscript::PropertyId jsPropID = (propID);
	(void)thisObj;
	(void)value;
	
	OOJS_NATIVE_ENTER(context)
	
	PlayerEntity				*player = OOPlayerForScripting();
	
	if (ooscript::isStringId(jsPropID))
	{
		std::optional<std::string> key = KeyForPropertyID(context, jsPropID);
		if (key.has_value())  { if (player != nullptr)  player->setMissionVariable(oo::PList(), *key); }
	}
	return true;
	
	OOJS_NATIVE_EXIT
}
} // namespace


namespace {
static bool MissionVariablesGetProperty(Context cx, Object obj, PropertyId propID, Value *value)
{
	ooscript::Context context = (cx);
	ooscript::Object thisObj = (obj);
	ooscript::PropertyId jsPropID = (propID);
	ooscript::Value *jsvalue = (value);
	(void)thisObj;
	
	OOJS_NATIVE_ENTER(context)
	
	PlayerEntity				*player = OOPlayerForScripting();
	
	if (ooscript::isStringId(jsPropID))
	{
		std::optional<std::string> key = KeyForPropertyID(context, jsPropID);
		if (!key.has_value())  return true;
		
		const oo::PList mvar = (player != nullptr ? player->missionVariableForKey(*key) : oo::PList());
		
		if (const std::string *string = mvar.getIf<std::string>())	// Currently there should only be strings, but we may want to change this.
		{
			if (OOIsNumberLiteral(*string, true))
			{
				return ooscript::newNumberValue(cx, oo::str::doubleValue(*string), value);	// -[NSString doubleValue]
			}
		}
		
		*jsvalue = OOJSValueFromPList(context, mvar);
	}
	return true;
	
	OOJS_NATIVE_EXIT
}
} // namespace


namespace {
static bool MissionVariablesSetProperty(Context cx, Object obj, PropertyId propID, bool /*strict*/, Value *value)
{
	ooscript::Context context = (cx);
	ooscript::Object thisObj = (obj);
	ooscript::PropertyId jsPropID = (propID);
	ooscript::Value *jsvalue = (value);
	(void)thisObj;
	
	OOJS_NATIVE_ENTER(context)
	
	PlayerEntity				*player = OOPlayerForScripting();
	
	if (ooscript::isStringId(jsPropID))
	{
		std::optional<std::string> key = KeyForPropertyID(context, jsPropID);
		if (!key.has_value())
		{
			const std::optional<std::string> badName = cxx_OOStringFromJSID(jsPropID);
			cxx_OOJSReportError(context, "Invalid mission variable name \"%s\".", badName.has_value() ? cxx_OOJSEscapedForJavaScriptLiteral(*badName).c_str() : "(null)");
			return false;
		}
		
		// nil (a value with no string form) clears the variable. (The old OONull test could not match
		// a string and is gone.)
		std::optional<std::string> objValue = cxx_OOStringFromJSValue(context, *jsvalue);
		
		if (player != nullptr)  player->setMissionVariable(objValue.has_value() ? oo::PList(*objValue) : oo::PList(), *key);
	}
	return true;
	
	OOJS_NATIVE_EXIT
}
} // namespace


namespace {
static bool MissionVariablesEnumerate(Context cx, Object /*obj*/, EnumerateOp enumOp, Value *state, PropertyId *idp)
{
	ooscript::Context context = (cx);
	ooscript::Value *jsstate = (state);
	ooscript::PropertyId *jsidp = idp;
	
	OOJS_NATIVE_ENTER(context)
	
	MissionVariablesEnumerationState *enumerator = nullptr;
	
	switch (enumOp)
	{
		case EnumerateOp::Init:
		case EnumerateOp::InitAll:	// For ES5 Object.getOwnPropertyNames(). Since we have no non-enumerable properties, this is the same as _INIT.
		{
			// A copy of the keys, which is good since the enumerating code might mutate. In key order
			// (-allKeys gave them in hash order).
			std::vector<std::string> keys;
			const oo::PList missionVariables = (PLAYER != nullptr ? PLAYER->missionVariables() : oo::PList());
			if (const oo::PList::Dict *dict = missionVariables.getIf<oo::PList::Dict>())
			{
				for (const auto &entry : *dict)  keys.push_back(entry.first);
			}
			enumerator = new MissionVariablesEnumerationState{ std::move(keys) };
			*jsstate = ooscript::privateValue(enumerator);
			
			NSUInteger count = enumerator->keys.size();
			assert(count <= INT32_MAX);
			if (jsidp != NULL)  *jsidp = ooscript::int32Id((uint32_t)count);
			return true;
		}
		
		case EnumerateOp::Next:
		{
			enumerator = static_cast<MissionVariablesEnumerationState *>(ooscript::toPrivate(*jsstate));
			while (enumerator->next < enumerator->keys.size())
			{
				std::string next = enumerator->keys[enumerator->next++];
				if (!oo::str::hasPrefix(next, "mission_"))  continue;	// Skip mission instructions, which aren't visible through missionVariables.
				
				next = next.substr(8);		// Cut off "mission_".
				
				ooscript::Value val = OOJSValueFromPList(context, oo::PList(next));
				return ooscript::valueToId(cx, (val), jsidp);
			}
			
			// If we got here, we've hit the end of the enumerator.
			*jsstate = ooscript::nullValue();
			// Fall through.
		}
		
		case EnumerateOp::Destroy:
		{
			if (enumerator == nullptr && ooscript::isDouble(*jsstate))
			{
				enumerator = static_cast<MissionVariablesEnumerationState *>(ooscript::toPrivate(*jsstate));
			}
			delete enumerator;
			
			if (jsidp != NULL)  *jsidp = ooscript::voidId();
			return true;
		}
	}
	
	OOJS_NATIVE_EXIT
}
} // namespace
