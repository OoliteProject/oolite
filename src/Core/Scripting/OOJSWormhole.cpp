/*
OOJSWormhole.mm

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

#include "WormholeEntity.h"
#include "OOJSWormhole.h"
#include "OOJSEntity.h"
#include "OOJSVector.h"
#include "OOJavaScriptEngine.h"
#include "EntityOOJavaScriptExtensions.h"

#include "ooscript/JSEngine.hpp"
#include <cstring>
#include <cstdint>

// Retargeted onto the ooscript facade (JSEngine.hpp), the way OOJSVector.mm and
// OOJSWaypoint.mm do it (bead oo-sdz exemplar): stub hooks become nullptr, InitClass
// becomes ooscript::initClass, numeric conversion becomes ooscript::newNumberValue, and
// `this` is renamed to `thisObj` (reserved word in Objective-C++, ADR-0001).

/*
	C++20 since bead oo-ykoy, converted the way bead oo-ppc converted OOJSVector.mm (proposed
	ADR-0056 amendment oo-ppc). The JS class was already C++ on the ooscript façade;
	OOJS_NATIVE_ENTER/EXIT and OOJS_PROFILE_ENTER/EXIT are C++ try/catch and scope guards
	(OOJSEngineNativeWrappers.h); BOOL/YES/NO are bool/true/false. The category on WormholeEntity
	became three free functions, and its methods moved to a bridge file of the binding (amendment
	oo-ykoy), then onto the WormholeEntity facade in WormholeEntity+ObjCBridge.mm (bead oo-9ht.43,
	amendment oo-6ia4 item 3). Messages to classes that are still Objective-C (WormholeEntity,
	Entity) stay as they are, which is why the file is still .mm until Phase 4.
*/

namespace ooscript { }
using ooscript::Context;
using ooscript::Object;
using ooscript::Value;
using ooscript::PropertyId;
using ooscript::ClassDef;
using ooscript::ClassFlag;
using ooscript::PropertyFlag;
using ooscript::PropertySpec;
using ooscript::FunctionSpec;
using ooscript::CallArgs;

// Byte-identical facade <-> jsapi views, local to this call site (see OOJSVector.mm).


namespace {
static ooscript::Object sWormholePrototype;
} // namespace

namespace {
static bool JSWormholeGetWormholeEntity(ooscript::Context context, ooscript::Object stationObj, WormholeEntity **outEntity);
} // namespace


namespace {
static bool WormholeGetProperty(Context cx, Object obj, PropertyId propID, Value *value);
} // namespace
namespace {
static bool WormholeSetProperty(Context cx, Object obj, PropertyId propID, bool strict, Value *value);
} // namespace


namespace {
static ClassDef sWormholeClass =
{
	"Wormhole",
	ClassFlag::HasPrivate,
	
	nullptr,		// addProperty
	nullptr,		// delProperty
	WormholeGetProperty,		// getProperty
	WormholeSetProperty,		// setProperty
	nullptr,		// enumerate
	nullptr,			// newEnumerate (ooscript::ClassFlag::NewEnumerate not used)
	nullptr,			// resolve
	nullptr,			// convert
	OOJSCxxObjectWrapperFinalize,// finalize
	nullptr,			// call
	nullptr,			// construct
	nullptr,			// backend: owned by the facade backend, must start null
};
} // namespace


enum : std::uint8_t
{
	// Property IDs
	kWormhole_arrivalTime,
	kWormhole_destination,
	kWormhole_expiryTime,
	kWormhole_origin

};


namespace {
static PropertySpec sWormholeProperties[] =
{
	// JS name							ID									flags
	{ "arrivalTime",	     kWormhole_arrivalTime,	      PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Shared, nullptr, nullptr },
	{ "destination",	     kWormhole_destination,	      PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Shared, nullptr, nullptr },
	{ "expiryTime",	     kWormhole_expiryTime,	      PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Shared, nullptr, nullptr },
	{ "origin",	     kWormhole_origin,	      PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Shared, nullptr, nullptr },
	{ 0 }
};
} // namespace


// Raw jsapi mirror of sWormholeProperties for the shared error reporters that still take a
// ooscript::PropertySpec* (see OOJSVector.mm's sVectorPropertiesRaw).
namespace {
static ooscript::PropertySpec sWormholePropertiesRaw[] =
{
	// JS name							ID									flags
	{ "arrivalTime",	     kWormhole_arrivalTime,	      OOJS_PROP_READONLY_CB },
	{ "destination",	     kWormhole_destination,	      OOJS_PROP_READONLY_CB },
	{ "expiryTime",	     kWormhole_expiryTime,	      OOJS_PROP_READONLY_CB },
	{ "origin",	     kWormhole_origin,	      OOJS_PROP_READONLY_CB },
	{ 0 }
};
} // namespace


namespace {
static FunctionSpec sWormholeMethods[] =
{
	// JS name					Function						min args	flags
//	{ "",     WormholeDoStuff,    0,	0 },
	{ 0 }
};
} // namespace


void InitOOJSWormhole(ooscript::Context context, ooscript::Object global)
{
	Object proto = ooscript::initClass((context), (global), (JSEntityPrototype()), &sWormholeClass, OOJSUnconstructableConstruct, 0, sWormholeProperties, sWormholeMethods, NULL, NULL);
	sWormholePrototype = (proto);
	OOJSRegisterObjectConverter(&sWormholeClass, OOJSEntityObjectConverter);
	OOJSRegisterSubclass(&sWormholeClass, JSEntityClass());
}


namespace {
static bool JSWormholeGetWormholeEntity(ooscript::Context context, ooscript::Object wormholeObj, WormholeEntity **outEntity)
{
	OOJS_PROFILE_ENTER
	
	bool						result;
	Entity					*entity = nullptr;	// the slot holds the C++ entity (bead oo-9ht.39.3)
	
	if (outEntity == NULL)  return false;
	*outEntity = nullptr;
	
	result = OOJSEntityGetEntity(context, wormholeObj, &entity);
	if (!result)  return false;
	
	// The wormhole is C++ behind the root's facade since bead oo-9ht.112 (-isKindOfClass: before).
	*outEntity = dynamic_cast<WormholeEntity *>(entity);
	return *outEntity != nullptr;
	
	OOJS_PROFILE_EXIT
}
} // namespace


// The bodies of WormholeEntity (OOJavaScriptExtensions), whose methods are on the WormholeEntity
// facade, in WormholeEntity+ObjCBridge.mm (bead oo-9ht.43), until that facade goes (oo-9ht.112;
// proposed ADR-0056 amendments oo-ppc, oo-ykoy and oo-6ia4).
void OOJSWormholeGetJSClass(ooscript::ClassDef **outClass, ooscript::Object *outPrototype)
{
	*outClass = &sWormholeClass;
	*outPrototype = sWormholePrototype;
}

std::optional<std::string> OOJSWormholeJSClassName(void)
{
	return std::string("Wormhole");
}

bool OOJSWormholeIsVisibleToScripts(void)
{
	return true;
}


namespace {
static bool WormholeGetProperty(Context cx, Object obj, PropertyId propID, Value *value)
{
	if (!ooscript::isInt32Id(propID))  return true;
	
	ooscript::Context context = reinterpret_cast<ooscript::Context >(cx);
	ooscript::Object thisObj = (obj);
	ooscript::Value *value_raw = reinterpret_cast<ooscript::Value*>(value);
	
	OOJS_NATIVE_ENTER(context)
	
	WormholeEntity				*entity = nil;
	
	if (!JSWormholeGetWormholeEntity(context, thisObj, &entity))  return false;
	if (entity == nil)  { *value_raw = ooscript::undefinedValue(); return true; }
	
	switch (ooscript::idToInt32(propID))
	{
  case kWormhole_arrivalTime:
		return ooscript::newNumberValue(cx, (entity != nullptr ? entity->arrivalTime() : 0.0), value);

  case kWormhole_destination:
		return ooscript::newNumberValue(cx, (entity != nullptr ? entity->getDestination() : 0), value);

  case kWormhole_expiryTime:
		return ooscript::newNumberValue(cx, (entity != nullptr ? entity->expiryTime() : 0.0), value);
		
  case kWormhole_origin:
		return ooscript::newNumberValue(cx, (entity != nullptr ? entity->getOrigin() : 0), value);

	default:
		OOJSReportBadPropertySelector(context, thisObj, (propID), sWormholePropertiesRaw);
		return false;
	}

	*value_raw = ooscript::nullValue();	// what OOJSValueFromNativeObject() gave for the nil result (unreached: every case returns; bead oo-4aq6a.6)
	return true;
	
	OOJS_NATIVE_EXIT
}
} // namespace


namespace {
static bool WormholeSetProperty(Context cx, Object obj, PropertyId propID, bool /*strict*/, Value *value)
{
	if (!ooscript::isInt32Id(propID))  return true;
	
	ooscript::Context context = reinterpret_cast<ooscript::Context >(cx);
	ooscript::Object thisObj = (obj);
	ooscript::Value *value_raw = reinterpret_cast<ooscript::Value*>(value);

	OOJS_NATIVE_ENTER(context)

	WormholeEntity				*entity = nil;

	if (!JSWormholeGetWormholeEntity(context, thisObj, &entity)) return false;
	if (entity == nil)  return true;
	
	switch (ooscript::idToInt32(propID))
	{

		default:
			OOJSReportBadPropertySelector(context, thisObj, (propID), sWormholePropertiesRaw);
			return false;
	}
	
	OOJSReportBadPropertyValue(context, thisObj, (propID), sWormholePropertiesRaw, *value_raw);
	return false;
	
	OOJS_NATIVE_EXIT
}
} // namespace


// *** Methods ***
