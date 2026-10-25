/*
OOJSWaypoint.m

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

#include "OOWaypointEntity.h"
#include "OOJSWaypoint.h"
#include "OOJSEntity.h"
#include "OOJSVector.h"
#include "OOJSQuaternion.h"
#include "OOJavaScriptEngine.h"
#include "EntityOOJavaScriptExtensions.h"

#include "ooscript/JSEngine.hpp"
#include <cstring>
#include <cstdint>

/*
	Retargeted onto the ooscript façade (JSEngine.hpp) the way OOJSVector.mm does it (bead
	oo-sdz, the sweep exemplar): the class dispatch table becomes a static ooscript::ClassDef
	(the stub hooks are nullptr), InitClass becomes ooscript::initClass, and the two directly
	spelled numeric-conversion calls become ooscript::newNumberValue/valueToNumber. `this` is
	renamed to `thisObj` because it is a reserved word once this file compiles as
	Objective-C++ (ADR-0001).

	Waypoint is registered as an Entity subclass and object converter with &sWaypointClass, the
	same ooscript::ClassDef that ooscript::getClass() reports for its instances.
*/

/*
	C++20 since bead oo-mae5, converted the way bead oo-ppc converted OOJSVector.mm (proposed
	ADR-0056 amendment oo-ppc). The JS class was already C++ on the ooscript façade;
	OOJS_NATIVE_ENTER/EXIT and OOJS_PROFILE_ENTER/EXIT are C++ try/catch and scope guards
	(OOJSEngineNativeWrappers.h); BOOL/YES/NO are bool/true/false. The category on OOWaypointEntity
	became three free functions, and its methods and interface moved to a bridge file of the binding
	(amendment oo-ykoy), then onto the OOWaypointEntity facade in OOWaypointEntity+ObjCBridge.mm
	(bead oo-9ht.50, amendment oo-6ia4 item 3). Messages to classes that are still Objective-C
	(OOWaypointEntity, Entity, Universe, PlayerEntity) stay as they are, which is why the file is
	still .mm until Phase 4.
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

// Byte-identical façade <-> jsapi views, local to this call site (see OOJSVector.mm).


namespace {
static ooscript::Object sWaypointPrototype;
} // namespace

namespace {
static bool JSWaypointGetWaypointEntity(ooscript::Context context, ooscript::Object stationObj, OOWaypointEntity **outEntity);
} // namespace


namespace {
static bool WaypointGetProperty(Context cx, Object obj, PropertyId propID, Value *value);
} // namespace
namespace {
static bool WaypointSetProperty(Context cx, Object obj, PropertyId propID, bool strict, Value *value);
} // namespace


namespace {
static ClassDef sWaypointClass =
{
	"Waypoint",
	ClassFlag::HasPrivate,
	
	nullptr,			// addProperty (engine default: PropertyStub)
	nullptr,			// delProperty (engine default: PropertyStub)
	WaypointGetProperty,		// getProperty
	WaypointSetProperty,		// setProperty
	nullptr,			// enumerate (engine default: EnumerateStub)
	nullptr,			// newEnumerate (ooscript::ClassFlag::NewEnumerate not used)
	nullptr,			// resolve (engine default: ResolveStub)
	nullptr,			// convert (engine default: ConvertStub)
	OOJSCxxObjectWrapperFinalize,		// finalize
	nullptr,			// call
	nullptr,			// construct
	nullptr,			// backend: owned by the façade backend, must start null
};
} // namespace


enum : std::uint8_t
{
	// Property IDs
	kWaypoint_beaconCode,
	kWaypoint_beaconLabel,
	kWaypoint_orientation, // overrides entity as waypoints can be unoriented
	kWaypoint_size
};


namespace {
static PropertySpec sWaypointProperties[] =
{
	// JS name							ID						flags								getter	setter
	{ "beaconCode",	    kWaypoint_beaconCode,	PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared,	nullptr, nullptr },
	{ "beaconLabel",	kWaypoint_beaconLabel,	PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared,	nullptr, nullptr },
	{ "orientation",	kWaypoint_orientation,	PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared,	nullptr, nullptr },
	{ "size",	     	kWaypoint_size,	      	PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared,	nullptr, nullptr },
	{ 0 }
};
} // namespace


// A raw jsapi mirror of sWaypointProperties, used only for the two bad-property error
// reporters in OOJavaScriptEngine.m (OOJSReportBadPropertySelector/Value): those helpers are
// outside this bead's scope (shared across every binding file) and still take a
// ooscript::PropertySpec*, not ooscript::PropertySpec* (see OOJSVector.mm's sVectorPropertiesRaw).
namespace {
static ooscript::PropertySpec sWaypointPropertiesRaw[] =
{
	// JS name							ID						flags
	{ "beaconCode",	    kWaypoint_beaconCode,	OOJS_PROP_READWRITE_CB },
	{ "beaconLabel",	kWaypoint_beaconLabel,	OOJS_PROP_READWRITE_CB },
	{ "orientation",	kWaypoint_orientation,	OOJS_PROP_READWRITE_CB },
	{ "size",	     	kWaypoint_size,	      	OOJS_PROP_READWRITE_CB },
	{ 0 }
};
} // namespace


namespace {
static FunctionSpec sWaypointMethods[] =
{
	// JS name					Function						min args	flags
//	{ "",     WaypointDoStuff,    0,	0 },
	{ 0 }
};
} // namespace


void InitOOJSWaypoint(ooscript::Context context, ooscript::Object global)
{
	Object proto = ooscript::initClass((context), (global), (JSEntityPrototype()), &sWaypointClass, OOJSUnconstructableConstruct, 0, sWaypointProperties, sWaypointMethods, nullptr, nullptr);
	sWaypointPrototype = (proto);
	OOJSRegisterObjectConverter(&sWaypointClass, OOJSEntityObjectConverter);
	OOJSRegisterSubclass(&sWaypointClass, JSEntityClass());
}


namespace {
static bool JSWaypointGetWaypointEntity(ooscript::Context context, ooscript::Object wormholeObj, OOWaypointEntity **outEntity)
{
	OOJS_PROFILE_ENTER
	
	bool						result;
	Entity					*entity = nullptr;	// the slot holds the C++ entity (bead oo-9ht.39.3)
	
	if (outEntity == NULL)  return false;
	*outEntity = nullptr;
	
	result = OOJSEntityGetEntity(context, wormholeObj, &entity);
	if (!result)  return false;
	
	// A waypoint is the C++ OOWaypointEntity (a nil or other entity is not, as -isKindOfClass:
	// answered). The natives call its members (bead oo-9ht.39.8.18), where they messaged its object.
	OOWaypointEntity *waypoint = dynamic_cast<OOWaypointEntity *>(entity);
	if (waypoint == nullptr)  return false;
	
	*outEntity = waypoint;
	return true;
	
	OOJS_PROFILE_EXIT
}
} // namespace


// The bodies of OOWaypointEntity (OOJavaScriptExtensions), which the C++ class's overrides of the
// root's JS members call since bead oo-9ht.108 deleted the facade that forwarded to them (bead
// oo-9ht.50; proposed ADR-0056 amendments oo-ppc, oo-ykoy, oo-6ia4 and oo-9ht.107).
void OOJSWaypointGetJSClass(ooscript::ClassDef **outClass, ooscript::Object *outPrototype)
{
	*outClass = &sWaypointClass;
	*outPrototype = sWaypointPrototype;
}

std::optional<std::string> OOJSWaypointJSClassName(void)
{
	return std::string("Waypoint");
}

bool OOJSWaypointIsVisibleToScripts(void)
{
	return true;
}


namespace {
static bool WaypointGetProperty(Context cx, Object obj, PropertyId propID, Value *value)
{
	if (!ooscript::isInt32Id(propID))  return true;
	
	ooscript::Context context = reinterpret_cast<ooscript::Context >(cx);
	ooscript::Object thisObj = (obj);
	ooscript::Value *value_raw = reinterpret_cast<ooscript::Value*>(value);
	
	OOJS_NATIVE_ENTER(context)
	
	OOWaypointEntity				*waypoint = nullptr;
	oo::PList result;	// null: nil
	std::optional<std::string> text;
	Quaternion q = kIdentityQuaternion;

	if (!JSWaypointGetWaypointEntity(context, thisObj, &waypoint))  return false;	// not null after this (its object, nil only without a facade, is not asked since bead oo-9ht.39.8.18)
	
	switch (ooscript::idToInt32(propID))
	{
	case kWaypoint_beaconCode:
		text = waypoint->beaconCode();
		if (text.has_value())  result = oo::PList(*text);
		break;

	case kWaypoint_beaconLabel:
		text = waypoint->beaconLabel();
		if (text.has_value())  result = oo::PList(*text);
		break;

	case kWaypoint_orientation:
		q = waypoint->getOrientation();	// what the object's -orientation answered
		if (!waypoint->getOriented())
		{
			q = kZeroQuaternion;
		}
		return QuaternionToJSValue(context, q, value_raw);
		
	case kWaypoint_size:
		return ooscript::newNumberValue(cx, waypoint->size(), value);

	default:
		OOJSReportBadPropertySelector(context, thisObj, (propID), sWaypointPropertiesRaw);
		return false;
	}

	*value_raw = OOJSValueFromPList(context, result);
	return true;
	
	OOJS_NATIVE_EXIT
}
} // namespace


namespace {
static bool WaypointSetProperty(Context cx, Object obj, PropertyId propID, bool /*strict*/, Value *value)
{
	if (!ooscript::isInt32Id(propID))  return true;
	
	ooscript::Context context = reinterpret_cast<ooscript::Context >(cx);
	ooscript::Object thisObj = (obj);
	ooscript::Value *value_raw = reinterpret_cast<ooscript::Value*>(value);

	OOJS_NATIVE_ENTER(context)

	OOWaypointEntity				*waypoint = nullptr;
	double        fValue;
	std::optional<std::string>	sValue;
	Quaternion			qValue;

	if (!JSWaypointGetWaypointEntity(context, thisObj, &waypoint)) return false;	// not null after this (bead oo-9ht.39.8.18)
	
	switch (ooscript::idToInt32(propID))
	{
		case kWaypoint_beaconCode:
			sValue = cxx_OOStringFromJSValue(context,*value_raw);
			if (!sValue.has_value() || sValue->empty()) 
			{
				if (waypoint->isBeacon()) 
				{
					if (UNIVERSE != nullptr)  UNIVERSE->clearBeacon(waypoint);	// the C++ waypoint (bead oo-9ht.39.8.10)
					if ((PLAYER != nullptr ? PLAYER->nextBeaconEntity() : nullptr) == waypoint)	// the C++ entities (bead oo-9ht.39.8.10; not virtual, so the binding test stands in for it)
					{
						if (PLAYER != nullptr)  PLAYER->PlayerEntity::setCompassMode(COMPASS_MODE_PLANET);	// qualified: the final overrider (bead oo-9ht.177), so the binding test stands in for it
					}
				}
			}
			else 
			{
				if (waypoint->isBeacon()) 
				{
					waypoint->setBeaconCode(sValue);
				}
				else // Universe needs to update beacon lists in this case only
				{
					waypoint->setBeaconCode(sValue);
					if (UNIVERSE != nullptr)  UNIVERSE->setNextBeacon(waypoint);	// the C++ waypoint (bead oo-9ht.39.8.10)
				}
			}
			return true;
			break;

		case kWaypoint_beaconLabel:
			sValue = cxx_OOStringFromJSValue(context,*value_raw);
			if (sValue.has_value())
			{
				waypoint->setBeaconLabel(sValue);
				return true;
			}
			break;

		case kWaypoint_orientation:
			if (JSValueToQuaternion(context, *value_raw, &qValue))
			{
				waypoint->Entity::setNormalOrientation(qValue);	// what the object's selector called; qualified: the final overrider for a waypoint (no override, no subclass), so the binding test stands in for it
				return true;
			}
			break;

		case kWaypoint_size:
			if (ooscript::valueToNumber(cx, *value, &fValue))
			{
				if (fValue > 0.0)
				{
					waypoint->setSize(fValue);
					return true;
				}
			}
			break;

		default:
			OOJSReportBadPropertySelector(context, thisObj, (propID), sWaypointPropertiesRaw);
			return false;
	}
	
	OOJSReportBadPropertyValue(context, thisObj, (propID), sWaypointPropertiesRaw, *value_raw);
	return false;
	
	OOJS_NATIVE_EXIT
}
} // namespace


// *** Methods ***
