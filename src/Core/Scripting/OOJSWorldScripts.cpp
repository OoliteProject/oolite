/*

OOJSWorldScripts.mm


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

#include "OOJSWorldScripts.h"
#include "OOJavaScriptEngine.h"
#include "PlayerEntity.h"
#include "OOJSPlayer.h"
#include "OOScript.h"

#include "ooscript/JSEngine.hpp"
#include <cstring>

/*
	Retargeted onto the ooscript façade (JSEngine.hpp) per the OOJSVector.mm exemplar (bead
	oo-sdz): the class dispatch table (PropertyStub / StrictPropertyStub / ResolveStub /
	ConvertStub / FinalizeStub) is replaced by nullptr hooks in ooscript::ClassDef, and the two
	directly-spelled engine calls (DefineObject, DefineProperty) go through the façade. The hook
	functions (WorldScriptsGetProperty, WorldScriptsEnumerate) take the façade's hook signature
	(ooscript::Context / Object / PropertyId) directly rather than the engine's, so the OOJS_*
	macros and the rest of each function body need no conversion. `this` is renamed to `thisObj`
	because it is a reserved word once this file compiles as Objective-C++ (ADR-0001).
*/

namespace ooscript { }
using ooscript::Context;
using ooscript::Object;
using ooscript::Value;
using ooscript::PropertyId;
using ooscript::ClassDef;
using ooscript::ClassFlag;
using ooscript::PropertyFlag;

namespace {
static bool WorldScriptsGetProperty(Context context, Object thisObj, PropertyId propID, Value *value);
} // namespace
namespace {
static bool WorldScriptsEnumerate(Context cx, Object obj);
} // namespace


static const PropertyFlag kWorldScriptsObjectFlags = PropertyFlag::ReadOnly | PropertyFlag::Enumerate | PropertyFlag::Permanent;
static const PropertyFlag kWorldScriptsPropertyFlags = PropertyFlag::ReadOnly | PropertyFlag::Shared | PropertyFlag::Permanent | PropertyFlag::Enumerate;


namespace {
static ClassDef sWorldScriptsClass =
{
	"WorldScripts",
	ClassFlag::None,

	nullptr,				// addProperty (engine default: PropertyStub)
	nullptr,				// delProperty (engine default: PropertyStub)
	WorldScriptsGetProperty,	// getProperty
	nullptr,				// setProperty (engine default: StrictPropertyStub)
	WorldScriptsEnumerate,	// enumerate
	nullptr,				// newEnumerate (ooscript::ClassFlag::NewEnumerate not used)
	nullptr,				// resolve (engine default: ResolveStub)
	nullptr,				// convert (engine default: ConvertStub)
	nullptr,				// finalize (engine default: FinalizeStub)
	nullptr,				// call
	nullptr,				// construct
	nullptr,				// backend: owned by the façade backend, must start null
};
} // namespace


void InitOOJSWorldScripts(ooscript::Context context, ooscript::Object global)
{
	ooscript::defineObject((context), (global), "worldScripts", &sWorldScriptsClass, nullptr, kWorldScriptsObjectFlags);
}


namespace {
static bool WorldScriptsGetProperty(Context cx, Object obj, PropertyId propID, Value *value)
{
	ooscript::Context context = (cx);
	ooscript::PropertyId jsPropID = (propID);
	ooscript::Value *jsValue = (value);
	(void)obj;
	
	OOJS_NATIVE_ENTER(context)
	
	PlayerEntity				*player = OOPlayerForScripting();
	std::optional<std::string>	scriptName;
	OOScript					*script = nullptr;
	
	if (!ooscript::isStringId(jsPropID))  return YES;
	scriptName = cxx_OOStringFromJSString(context, ooscript::idToString(jsPropID));
	
	if (scriptName.has_value())
	{
		script = nullptr;
		const auto worldScripts = (player != nullptr ? player->worldScriptsByName() : std::vector<std::pair<std::string, oo::Ref<OOScript>>>());	// kept while script is used
		for (const auto &[name, scriptRef] : worldScripts)	// the last of a name, as the dictionary kept
		{
			if (name == *scriptName && scriptRef.get() != nullptr)  script = scriptRef.get();
		}
		if (script != nullptr)
		{
			/*	If script is an OOJSScript, this should return a JS Script
				object. For other OOScript subclasses, it will return
				ooscript::nullValue(). If no script exists, the value will be
				ooscript::undefinedValue().
			*/
			*jsValue = script->jsValueInContext(context);
		}
		else
		{
			*jsValue = ooscript::undefinedValue();
		}

	}
	
	return YES;
	
	OOJS_NATIVE_EXIT
}
} // namespace


namespace {
static bool WorldScriptsEnumerate(Context cx, Object obj)
{
	ooscript::Context context = (cx);
	
	OOJS_NATIVE_ENTER(context)
	
	/*	In order to support enumeration of world scripts (e.g.,
		for (name in worldScripts) { ... }), define each property on demand.
		Since world scripts cannot be deleted, we don't need to worry about
		that case (as in OOJSMissionVariables).
		
		Since WorldScriptsGetProperty() will be called for each access anyway,
		we define the value as null here.
	*/
	
	PlayerEntity *player = OOPlayerForScripting();
	const std::vector<std::string> names = (player != nullptr ? player->worldScriptNames() : std::vector<std::string>());
	
	for (const std::string &name : names)
	{
		Value nullVal = ooscript::nullValue();
		if (!ooscript::defineProperty(cx, obj, name.c_str(), nullVal, WorldScriptsGetProperty, nullptr, kWorldScriptsPropertyFlags))  return NO;
	}
	
	return YES;
	
	OOJS_NATIVE_EXIT
}
} // namespace
