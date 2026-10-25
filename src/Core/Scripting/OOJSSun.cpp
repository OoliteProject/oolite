/*

OOJSSun.mm


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

#include "OOJSSun.h"
#include "OOJSEntity.h"
#include "OOJavaScriptEngine.h"

#include "OOSunEntity.h"

#include "ooscript/JSEngine.hpp"
#include <cstring>
#include <cstdint>

// Retargeted onto the ooscript façade (JSEngine.hpp) the way OOJSVector.mm does it (bead
// oo-sdz, exemplar): a static ClassDef is the class table (stub hooks nullptr), initClass replaces
// InitClass, natives take the façade's Context/Object/PropertyId/Value/CallArgs signature.

/*
	C++20 since bead oo-hgfh, converted the way bead oo-ppc converted OOJSVector.mm (proposed
	ADR-0056 amendment oo-ppc). The JS class was already C++ on the ooscript façade;
	OOJS_NATIVE_ENTER/EXIT and OOJS_PROFILE_ENTER/EXIT are C++ try/catch and scope guards
	(OOJSEngineNativeWrappers.h); BOOL/YES/NO are bool/true/false. The category on OOSunEntity
	became three free functions, and its methods moved to a bridge file of the binding (amendment
	oo-ykoy), then onto the OOSunEntity facade in OOSunEntity+ObjCBridge.mm (bead oo-9ht.51,
	amendment oo-6ia4 item 3). Messages to classes that are still Objective-C (OOSunEntity, Entity)
	stay as they are, which is why the file is still .mm until Phase 4.
*/

namespace ooscript { }
using ooscript::Context;
using ooscript::Object;
using ooscript::Value;
using ooscript::PropertyId;
using ooscript::CallArgs;
using ooscript::ClassDef;
using ooscript::ClassFlag;
using ooscript::PropertyFlag;
using ooscript::PropertySpec;
using ooscript::FunctionSpec;


namespace {
static ooscript::Object sSunPrototype;
}


namespace {
static bool SunGetProperty(Context cx, Object obj, PropertyId propID, Value *value);
static bool SunGoNova(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
static bool SunCancelNova(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
}

namespace {
static ClassDef sSunClass =
{
	"Sun",
	ClassFlag::HasPrivate,
	
	nullptr,				// addProperty
	nullptr,				// delProperty
	SunGetProperty,			// getProperty
	nullptr,				// setProperty
	nullptr,				// enumerate
	nullptr,				// newEnumerate
	nullptr,				// resolve
	nullptr,				// convert
	OOJSCxxObjectWrapperFinalize,	// finalize
	nullptr,				// call
	nullptr,				// construct
	nullptr,				// backend
};
}


enum : std::uint8_t
{
	// Property IDs
	kSun_radius,				// Radius of sun in metres, number, read-only
	kSun_hasGoneNova,			// Has sun gone nova, boolean, read-only
	kSun_isGoingNova,			// Will sun go nova, boolean, read-only
	kSun_name					// Name of sun, string, read-only (writable via systeminfo)
};


namespace {
static PropertySpec sSunProperties[] =
{
	// JS name					ID							flags														getter	setter
	{ "hasGoneNova",			kSun_hasGoneNova,			PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Shared,	nullptr, nullptr },
	{ "isGoingNova",			kSun_isGoingNova,			PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Shared,	nullptr, nullptr },
	{ "name",					kSun_name,					PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Shared,	nullptr, nullptr },
	{ "radius",					kSun_radius,				PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Shared,	nullptr, nullptr },
	{ 0 }
};
}


namespace {
static FunctionSpec sSunMethods[] =
{
	// JS name					Function					min args	flags
	{ "cancelNova",				SunCancelNova,				0,			0 },
	{ "goNova",					SunGoNova,					1,			0 },
	{ 0 }
};
}


namespace {
// The sun is C++ behind the root's facade since bead oo-9ht.111: the getter checks the JS class
// (a Sun object's private slot holds the sun's Objective-C object, so -isKindOfClass: of the
// facade class always held) and answers the C++ sun; null for a stale entity, as nil before.
// Since bead oo-9ht.39.3 the slot holds the C++ entity (OOJSEntityGetEntityOfClass for the Sun
// class, DEFINE_JS_OBJECT_GETTER(JSSunGetSunObject, &sSunClass, ...) before).
bool JSSunGetSunEntity(ooscript::Context context, ooscript::Object inObject, OOSunEntity **outObject)
{
	Entity *entity = nullptr;
	if (!OOJSEntityGetEntityOfClass(context, inObject, &sSunClass, &entity))  return false;
	*outObject = dynamic_cast<OOSunEntity *>(entity);
	return true;
}
}


void InitOOJSSun(ooscript::Context context, ooscript::Object global)
{
	Object proto = ooscript::initClass((context), (global), (JSEntityPrototype()), &sSunClass, OOJSUnconstructableConstruct, 0, sSunProperties, sSunMethods, NULL, NULL);
	sSunPrototype = (proto);
	OOJSRegisterObjectConverter(&sSunClass, OOJSEntityObjectConverter);
	OOJSRegisterSubclass(&sSunClass, JSEntityClass());
}


// The bodies of OOSunEntity (OOJavaScriptExtensions), whose methods are on the OOSunEntity facade,
// in OOSunEntity+ObjCBridge.mm (bead oo-9ht.51), until that facade goes (oo-9ht.111; proposed
// ADR-0056 amendments oo-ppc, oo-ykoy and oo-6ia4).
bool OOJSSunIsVisibleToScripts(void)
{
	return true;
}

void OOJSSunGetJSClass(ooscript::ClassDef **outClass, ooscript::Object *outPrototype)
{
	*outClass = &sSunClass;
	*outPrototype = sSunPrototype;
}

std::optional<std::string> OOJSSunJSClassName(void)
{
	return std::string("Sun");
}


namespace {
static bool SunGetProperty(Context cx, Object obj, PropertyId propID, Value *value)
{
	if (!ooscript::isInt32Id(propID))  return true;
	
	ooscript::Context context = (cx);
	ooscript::Object thisObj = (obj);
	
	OOJS_NATIVE_ENTER(context)
	
	OOSunEntity					*sun = nil;
	
	if (EXPECT_NOT(!JSSunGetSunEntity(context, thisObj, &sun)))  return false;
	
	switch (ooscript::idToInt32(propID))
	{
		case kSun_radius:
			return ooscript::newNumberValue(cx, (sun != nullptr ? sun->radius() : 0.0), value);

		case kSun_name:
		{
			const std::optional<std::string> name = (sun != nullptr ? sun->name() : std::optional<std::string>());
			*value = OOJSValueFromPList(context, name.has_value() ? oo::PList(*name) : oo::PList());
			return true;
		}
			
		case kSun_hasGoneNova:
			*value = OOJSValueFromBOOL((sun != nullptr ? sun->goneNova() : false));
			return true;
			
		case kSun_isGoingNova:
			*value = OOJSValueFromBOOL((sun != nullptr ? sun->willGoNova() : false) && !(sun != nullptr ? sun->goneNova() : false));
			return true;
			
		default:
			OOJSReportBadPropertySelector(context, thisObj, (propID), sSunProperties);
			return false;
	}
	
	OOJS_NATIVE_EXIT
}
}


// *** Methods ***

// goNova([delay : Number])
namespace {
static bool SunGoNova(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_NATIVE_ENTER(context)
	
	OOSunEntity					*sun = nil;
	double					delay = 0;
	
	if (EXPECT_NOT(!JSSunGetSunEntity(context, OOJS_THIS, &sun)))  return false;
	if (oojsArgs.count() > 0 && EXPECT_NOT(!ooscript::valueToNumber(context, (OOJS_ARGV[0]), &delay)))  return false;
	
	if (sun != nullptr)  sun->setGoingNova(true, delay);
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}
}


// cancelNova()
namespace {
static bool SunCancelNova(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	
	OOJS_NATIVE_ENTER(context)
	
	OOSunEntity					*sun = nil;
	
	if (EXPECT_NOT(!JSSunGetSunEntity(context, OOJS_THIS, &sun)))  return false;
	
	if ((sun != nullptr ? sun->willGoNova() : false) && !(sun != nullptr ? sun->goneNova() : false))
	{
		if (sun != nullptr)  sun->setGoingNova(false, 0);
	}
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}
}
