/*

OOShipGroup.m


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

#include "OOShipGroup.h"
#include "OOJSShipGroup.h"
#include "OOJavaScriptEngine.h"
#include "OOJSEntity.h"
#include "OOObjCPList.h"
#include "OOShipGroup.h"
#include "Universe.h"

#include "ooscript/JSEngine.hpp"
#include <cstring>
#include "oofnd/objc/OOAssert.h"
#include "oofnd/String.hpp"

/*
	Retargeted onto the ooscript façade (JSEngine.hpp) the way OOJSVector.mm does it (bead
	oo-sdz, the sweep exemplar): the class dispatch table becomes a static ooscript::ClassDef
	(the stub hooks are nullptr), InitClass becomes ooscript::initClass, and the directly
	spelled construction-check, object-construction and private-storage calls become
	ooscript::isConstructing (via CallArgs), ooscript::newObject and ooscript::setPrivate.
	`this` is renamed to `thisObj` because it is a reserved word once this file compiles as
	Objective-C++ (ADR-0001).

	ShipGroup has its own private-object getter (originally built by DEFINE_JS_OBJECT_GETTER(),
	OOJavaScriptEngine.h) the way OOJSSoundSource.mm's JSSoundSourceGetSoundSource does; it checks
	against &sShipGroupClass, the same ooscript::ClassDef that ooscript::getClass() reports.

	The finalizer (OOJSObjectWrapperFinalize) and toString() (OOJSObjectWrapperToString) are the
	shared natives, which already take the façade signatures and go into the tables directly.
*/
/*
	C++20 since bead oo-n64m, converted the way bead oo-ppc converted OOJSVector.mm (proposed
	ADR-0056 amendment oo-ppc). The JS class was already C++ on the ooscript façade;
	OOJS_NATIVE_ENTER/EXIT and OOJS_PROFILE_ENTER/EXIT are C++ try/catch and scope guards
	(OOJSEngineNativeWrappers.h); BOOL/YES/NO are bool/true/false. The category on the OOShipGroup
	façade became two members of the C++ group (amendments oo-ykoy, oo-bwrq and oo-6symp). The
	group, C++ since bead oo-bwrq, is called directly since its façade was deleted (bead oo-9ht.19),
	null-guarded where a message to nil answered. Messages to classes that are still
	Objective-C (ShipEntity) stay as they are, which is why the file is still .mm until Phase 4.
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

// Byte-identical façade <-> jsapi views, local to this call site (see OOJSVector.mm).


namespace {
static ooscript::Object sShipGroupPrototype;
} // namespace


namespace {
static bool ShipGroupGetProperty(Context cx, Object obj, PropertyId propID, Value *value);
} // namespace
namespace {
static bool ShipGroupSetProperty(Context cx, Object obj, PropertyId propID, bool strict, Value *value);
} // namespace
namespace {
static bool ShipGroupConstruct(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace

// Methods
namespace {
static bool ShipGroupToString(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace
namespace {
static bool ShipGroupAddShip(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace
namespace {
static bool ShipGroupRemoveShip(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace
namespace {
static bool ShipGroupContainsShip(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace


namespace {
static ClassDef sShipGroupClass =
{
	"ShipGroup",
	ClassFlag::HasPrivate,

	nullptr,				// addProperty (engine default: PropertyStub)
	nullptr,				// delProperty (engine default: PropertyStub)
	ShipGroupGetProperty,	// getProperty
	ShipGroupSetProperty,	// setProperty
	nullptr,				// enumerate (engine default: EnumerateStub)
	nullptr,				// newEnumerate (ooscript::ClassFlag::NewEnumerate not used)
	nullptr,				// resolve (engine default: ResolveStub)
	nullptr,				// convert (engine default: ConvertStub)
	OOJSCxxObjectWrapperFinalize,	// finalize
	nullptr,				// call
	nullptr,				// construct
	nullptr,				// backend: owned by the façade backend, must start null
};
} // namespace


enum : std::uint8_t
{
	// Property IDs
	kShipGroup_ships,			// array of ships, double, read-only
	kShipGroup_leader,			// leader, Ship, read/write
	kShipGroup_name,			// name, string, read/write
	kShipGroup_count,			// number of ships, integer, read-only
};


namespace {
static PropertySpec sShipGroupProperties[] =
{
	// JS name					ID							flags										getter	setter
	{ "count",					kShipGroup_count,			PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Shared, nullptr, nullptr },
	{ "leader",					kShipGroup_leader,			PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared,	nullptr, nullptr },
	{ "name",					kShipGroup_name,			PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared,	nullptr, nullptr },
	{ "ships",					kShipGroup_ships,			PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Shared, nullptr, nullptr },
	{ 0 }
};
} // namespace


// A raw jsapi mirror of sShipGroupProperties, used only for the two bad-property error
// reporters in OOJavaScriptEngine.m (OOJSReportBadPropertySelector/Value): those helpers are
// outside this bead's scope (shared across every binding file) and still take a
// ooscript::PropertySpec*, not ooscript::PropertySpec* (see OOJSVector.mm's sVectorPropertiesRaw).
namespace {
static ooscript::PropertySpec sShipGroupPropertiesRaw[] =
{
	// JS name					ID							flags
	{ "count",					kShipGroup_count,			OOJS_PROP_READONLY_CB },
	{ "leader",					kShipGroup_leader,			OOJS_PROP_READWRITE_CB },
	{ "name",					kShipGroup_name,			OOJS_PROP_READWRITE_CB },
	{ "ships",					kShipGroup_ships,			OOJS_PROP_READONLY_CB },
	{ 0 }
};
} // namespace


namespace {
static FunctionSpec sShipGroupMethods[] =
{
	// JS name					Function					min args	flags
	{ "toString",				ShipGroupToString,			0,			0 },
	{ "addShip",				ShipGroupAddShip,			1,			0 },
	{ "containsShip",			ShipGroupContainsShip,		1,			0 },
	{ "removeShip",				ShipGroupRemoveShip,		1,			0 },
	{ 0 }
};
} // namespace


// The private object getter, DEFINE_JS_OBJECT_GETTER's equivalent for a slot that holds the C++ group
// (OOJSPrivateObject.h): OOJSGetCxxPrivate<OOShipGroup>(cx, obj, &sShipGroupClass, &group).


// OOJSBasicPrivateObjectConverter for the C++ group the slot holds: its façade, which is what the
// slot held, for the Objective-C callers of OOJSNativeObjectFromJSObject (null for the prototype).
namespace {
static oo::PList ShipGroupConverter(ooscript::Context context, ooscript::Object object)
{
	OOShipGroup *group = static_cast<OOShipGroup *>(static_cast<oo::RefCounted *>(ooscript::getPrivate(context, object)));
	if (group == nullptr)  return oo::PList();
	return OOShipGroupObjectNode(group);
}
} // namespace


// *** Public ***

void InitOOJSShipGroup(ooscript::Context context, ooscript::Object global)
{
	Object proto = ooscript::initClass((context), (global), nullptr, &sShipGroupClass,
										ShipGroupConstruct, 0, sShipGroupProperties, sShipGroupMethods,
										nullptr, nullptr);
	sShipGroupPrototype = (proto);
	OOJSRegisterObjectConverter(&sShipGroupClass, ShipGroupConverter);
}


namespace {
static bool ShipGroupGetProperty(Context cx, Object obj, PropertyId propID, Value *value)
{
	if (!ooscript::isInt32Id(propID))  return true;

	ooscript::Context context = (cx);
	ooscript::Object thisObj = (obj);

	OOJS_NATIVE_ENTER(context)

	oo::PList				result;	// null: nil
	OOShipGroup		*cxxGroup = nullptr;

	if (EXPECT_NOT(!OOJSGetCxxPrivate(context, thisObj, &sShipGroupClass, &cxxGroup)))  return false;
	// (null for the prototype: each use answers what a message to nil did

	switch (ooscript::idToInt32(propID))
	{
		case kShipGroup_ships:
			result = oo::EntityNodesFrom((cxxGroup != nullptr) ? cxxGroup->memberArray() : std::vector<oo::EntityHold>());	// (no C++ value from a message to nil; an empty array)
			break;
			
		case kShipGroup_leader:
			result = oo::EntityObjectNode((cxxGroup != nullptr) ? cxxGroup->leader() : nullptr);
			break;
			
		case kShipGroup_name:
		{
			const std::optional<std::string> name = (cxxGroup != nullptr) ? cxxGroup->name() : std::nullopt;
			result = name.has_value() ? oo::PList(*name) : OONullObjectNode();
			break;
		}
			
		case kShipGroup_count:
			return ooscript::newNumberValue(cx, (cxxGroup != nullptr) ? cxxGroup->count() : 0, value);
			
		default:
			OOJSReportBadPropertySelector(context, thisObj, (propID), sShipGroupPropertiesRaw);
			return false;
	}
	
	*value = OOJSValueFromPList(context, result);
	return true;
	
	OOJS_NATIVE_EXIT
}
} // namespace


namespace {
static bool ShipGroupSetProperty(Context cx, Object obj, PropertyId propID, bool /*strict*/, Value *value)
{
	if (!ooscript::isInt32Id(propID))  return true;

	ooscript::Context context = (cx);
	ooscript::Object thisObj = (obj);

	OOJS_NATIVE_ENTER(context)

	ShipEntity				*shipValue = nil;
	OOShipGroup		*cxxGroup = nullptr;

	if (EXPECT_NOT(!OOJSGetCxxPrivate(context, thisObj, &sShipGroupClass, &cxxGroup)))  return false;
	// (null for the prototype: the setters do nothing, as messages to nil

	switch (ooscript::idToInt32(propID))
	{
		case kShipGroup_leader:
			shipValue = oo::ToShip(OOJSEntityFromJSValue(context, *(value)));
			if (shipValue != nil || ooscript::isNull(*value))
			{
				if (cxxGroup != nullptr)  cxxGroup->setLeader(shipValue);
				return true;
			}
			break;
			
		case kShipGroup_name:
			{ const std::optional<std::string> name = cxx_OOStringFromJSValueEvenIfNull(context, *(value)); if (cxxGroup != nullptr)  cxxGroup->setName(name); }
			return true;
			break;
			
		default:
			OOJSReportBadPropertySelector(context, thisObj, (propID), sShipGroupPropertiesRaw);
			return false;
	}
	
	OOJSReportBadPropertyValue(context, thisObj, (propID), sShipGroupPropertiesRaw, *(value));
	return false;
	
	OOJS_NATIVE_EXIT
}
} // namespace


// new ShipGroup([name : String [, leader : Ship]]) : ShipGroup
namespace {
static bool ShipGroupConstruct(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{

	OOJS_NATIVE_ENTER(context)
	
	if (EXPECT_NOT(!oojsArgs.isConstructing()))
	{
		cxx_OOJSReportError(context, "ShipGroup() cannot be called as a function, it must be used as a constructor (as in new ShipGroup(...)).");
		return false;
	}
	
	std::optional<std::string>	name;
	ShipEntity				*leader = nil;
	
	if (oojsArgs.count() >= 1)
	{
		if (!ooscript::isString(OOJS_ARGV[0]))
		{
			cxx_OOJSReportBadArguments(context, std::nullopt, "ShipGroup()", 1, OOJS_ARGV, "Could not create ShipGroup", "group name");
			return false;
		}
		name = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
	}
	
	if (oojsArgs.count() >= 2)
	{
		leader = oo::ToShip(OOJSEntityFromJSValue(context, OOJS_ARGV[1]));
		if (leader == nil && !ooscript::isNull(OOJS_ARGV[1]))
		{
			cxx_OOJSReportBadArguments(context, std::nullopt, "ShipGroup()", 1, OOJS_ARGV + 1, "Could not create ShipGroup", "ship");
			return false;
		}
	}
	
	const oo::Ref<OOShipGroup> group = OOShipGroup::groupWithName(name, leader);	// kept until the JS object holds it
	OOJS_RETURN(OOJSValueFromCxxObject(context, group.get()));
	
	OOJS_NATIVE_EXIT
}
} // namespace


/*	The JS glue of the C++ group (OOJSPrivateObject). The group's JS object is its _jsSelf (amendment
	oo-6symp, item 5): the object's private slot holds the group, retained.
*/

ooscript::Value OOShipGroup::jsValueInContext(ooscript::Context context)
{
	ooscript::Value					result = ooscript::nullValue();
	
	if (_jsSelf == NULL)
	{
		_jsSelf = (ooscript::newObject((context), &sShipGroupClass, (sShipGroupPrototype), nullptr));
		if (_jsSelf != NULL)
		{
			if (!OOJSSetCxxPrivate(context, _jsSelf, this))  _jsSelf = NULL;
		}
	}
	
	if (_jsSelf != NULL)  result = ooscript::objectValue(_jsSelf);
	
	return result;
}


void OOShipGroup::clearJSSelf(ooscript::Object selfVal)
{
	if (_jsSelf == selfVal)  _jsSelf = NULL;
}


// What the façade's -cxx_oo_jsDescription answered (OOObject (OOJavaScriptConversion)): the class
// name (the façade had no jsClassName) and the components.
std::optional<std::string> OOShipGroup::jsDescription()
{
	const std::optional<std::string> components = descriptionComponents();
	if (components.has_value())  return oo::str::format("[OOShipGroup %s]", components->c_str());
	return std::string("[object OOShipGroup]");
}


// *** Methods ***

// toString() : String
namespace {
static bool ShipGroupToString(ooscript::Context cx, ooscript::CallArgs &oojsArgs)
{
	return OOJSCxxObjectWrapperToString(cx, oojsArgs, &sShipGroupClass);
}
} // namespace


// addShip(ship : Ship)
namespace {
static bool ShipGroupAddShip(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{

	OOJS_NATIVE_ENTER(context)
	
	OOShipGroup		*cxxGroup = nullptr;
	ShipEntity				*ship = nil;
	bool					OK = true;
	
	if (EXPECT_NOT(!OOJSGetCxxPrivate(context, OOJS_THIS, &sShipGroupClass, &cxxGroup)))  return false;
	
	if (oojsArgs.count() > 0)  ship = oo::ToShip(OOJSEntityFromJSValue(context, OOJS_ARGV[0]));
	if (ship == nil)
	{
		if (oojsArgs.count() > 0 && ooscript::isNull(OOJS_ARGV[0]))  OOJS_RETURN_VOID;	// OK, do nothing for null ship.
		
		cxx_OOJSReportBadArguments(context, "ShipGroup", "addShip", MIN(oojsArgs.count(), 1U), OOJS_ARGV, std::nullopt, "ship");
		return false;
	}
	
	// The groups are C++; a null one (the prototype's, or a ship's that has none) answers what a
	// message to nil did.
	OOShipGroup				*thisGroup = cxxGroup;
	
	if (cxxGroup != nullptr && cxxGroup->containsShip(ship))
	{
		// nothing to do...
		OOJS_RETURN_VOID;
	}
	else
	{
		ShipEntity				*thisGroupLeader = (cxxGroup != nullptr) ? cxxGroup->leader() : nil;
		
		if ((thisGroupLeader != nullptr ? thisGroupLeader->escortGroup() : (OOShipGroup *)nullptr) == thisGroup) // escort group!
		{
			if (((cxxGroup != nullptr) ? cxxGroup->count() : 0) > 1) // already with some escorts
			{
				OOShipGroup			*thatGroup = (ship != nullptr ? ship->group() : (OOShipGroup *)nullptr);
				OOShipGroup			*cxxThatGroup = thatGroup;
				if (((cxxThatGroup != nullptr) ? cxxThatGroup->count() : 0) > 1 && (((cxxThatGroup != nullptr) ? cxxThatGroup->leader() : nil) != nullptr ? ((cxxThatGroup != nullptr) ? cxxThatGroup->leader() : nil)->escortGroup() : (OOShipGroup *)nullptr) == thatGroup)	// new escort already escorting!
				{
					cxx_OOJSReportWarningForCaller(context, "ShipGroup", "addShip", "Ship %s cannot be assigned to two escort groups, ignoring.", oo::EntityDescription(ship).c_str());
					OK = false;
				}
				else
				{
					OK = (thisGroupLeader != nullptr ? thisGroupLeader->acceptAsEscort(ship) : false);
				}
			}
			else // [thisGroup count] == 1, default unescorted ship?
			{
				if ((thisGroupLeader != nullptr ? thisGroupLeader->escortGroup() : (OOShipGroup *)nullptr) == (thisGroupLeader != nullptr ? thisGroupLeader->group() : (OOShipGroup *)nullptr))
				{
					// Default unescorted, unescortable, ship. Create new group and use that instead.
					if (thisGroupLeader != nullptr)  thisGroupLeader->setGroup(OOShipGroup::groupWithName(std::string("ship group")).leakRef());	// +1 kept, as [[OOShipGroup alloc] cxx_initWithName:] was
					thisGroup = (thisGroupLeader != nullptr ? thisGroupLeader->group() : (OOShipGroup *)nullptr);
					cxxGroup = thisGroup;
				}
				else
				{
					// Unescorted ship with custom group. See if it accepts escorts.
					OK = (thisGroupLeader != nullptr ? thisGroupLeader->acceptAsEscort(ship) : false);
				}
			}
		}
		if (OK)
		{
			OOJS_RETURN_BOOL(cxxGroup != nullptr && cxxGroup->addShip(ship));	// if ship is there already, noop & YES
		}
		else  OOJS_RETURN_BOOL(false);
	}
	
	OOJS_NATIVE_EXIT
}
} // namespace


// removeShip(ship : Ship)
namespace {
static bool ShipGroupRemoveShip(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{

	OOJS_NATIVE_ENTER(context)
	
	OOShipGroup		*cxxGroup = nullptr;
	ShipEntity				*ship = nil;
	
	if (EXPECT_NOT(!OOJSGetCxxPrivate(context, OOJS_THIS, &sShipGroupClass, &cxxGroup)))  return false;
	
	if (oojsArgs.count() > 0)  ship = oo::ToShip(OOJSEntityFromJSValue(context, OOJS_ARGV[0]));
	if (ship == nil)
	{
		if (oojsArgs.count() > 0 && ooscript::isNull(OOJS_ARGV[0]))  OOJS_RETURN_VOID;	// OK, do nothing for null ship.
		
		cxx_OOJSReportBadArguments(context, "ShipGroup", "removeShip", MIN(oojsArgs.count(), 1U), OOJS_ARGV, std::nullopt, "ship");
		return false;
	}
	
	// (null for the prototype: false, as a message to nil)
	OOJS_RETURN_BOOL(cxxGroup != nullptr && cxxGroup->removeShip(ship));
	
	OOJS_NATIVE_EXIT
}
} // namespace


// containsShip(ship : Ship) : Boolean
namespace {
static bool ShipGroupContainsShip(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{

	OOJS_NATIVE_ENTER(context)
	
	OOShipGroup		*cxxGroup = nullptr;
	ShipEntity				*ship = nil;
	
	if (EXPECT_NOT(!OOJSGetCxxPrivate(context, OOJS_THIS, &sShipGroupClass, &cxxGroup)))  return false;
	
	if (oojsArgs.count() > 0)  ship = oo::ToShip(OOJSEntityFromJSValue(context, OOJS_ARGV[0]));
	if (ship == nil)
	{
		if (oojsArgs.count() > 0 && ooscript::isNull(OOJS_ARGV[0]))  OOJS_RETURN_BOOL(false); // OK, return false for null ship.
		
		cxx_OOJSReportBadArguments(context, "ShipGroup", "containsShip", MIN(oojsArgs.count(), 1U), OOJS_ARGV, std::nullopt, "ship");
		return false;
	}
	
	// (null for the prototype: false, as a message to nil)
	OOJS_RETURN_BOOL(cxxGroup != nullptr && cxxGroup->containsShip(ship));
	
	OOJS_NATIVE_EXIT
}
} // namespace
