/*

OOJSEntity.mm

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

#include "OOJSEntity.h"
#include "OOJSVector.h"
#include "OOJSQuaternion.h"
#include "OOJavaScriptEngine.h"
#include "OOConstToJSString.h"
#include "EntityOOJavaScriptExtensions.h"
#include "OOJSCall.h"
#include "OOObjCPList.h"

#include "OOJSPlayer.h"
#include "PlayerEntity.h"
#include "ShipEntity.h"

#include "ooscript/JSEngine.hpp"
#include <cstring>

/*
	Retargeted onto the ooscript façade (JSEngine.hpp) the way OOJSVector.mm does it (bead
	oo-sdz, exemplar for this sweep, bead oo-oap): the class table is a static ooscript::ClassDef
	(stub hooks become nullptr), initClass replaces the engine's InitClass, and the
	getProperty/setProperty class hooks and the natives take the façade's
	Context/Object/PropertyId/Value pointer/CallArgs signature directly.

	The Entity class, sEntityClass, is the shared base for every other entity binding file's
	OOJSRegisterSubclass()/DEFINE_JS_OBJECT_GETTER() call; JSEntityClass() returns it.

	`this` is renamed to `thisObj` because it is a reserved word once this file compiles as
	Objective-C++ (ADR-0001).
*/

/*
	C++20 since bead oo-tq53, converted the way bead oo-ppc converted OOJSVector.mm (proposed
	ADR-0056 amendment oo-ppc). The JS class was already C++ on the ooscript façade;
	OOJS_NATIVE_ENTER/EXIT and OOJS_PROFILE_ENTER/EXIT are C++ try/catch and scope guards
	(OOJSEngineNativeWrappers.h); BOOL/YES/NO are bool/true/false. The C API in OOJSEntity.h
	(JSValueToEntity(), EntityFromArgumentList(), OOIsPlayerStale(), OOIsStaleEntity()) returns bool
	too; its callers compile unchanged. Nothing else in the file was Objective-C: an entity is still
	messaged through the Objective-C Entity, the façade every entity is while its subclasses are
	Objective-C (ShipEntity's own selectors included), as OOJSSun.mm does, which is why the file is
	still .mm until Phase 4.
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
static bool EntityGetProperty(Context cx, Object obj, PropertyId propID, Value *value);
} // namespace
namespace {
static bool EntitySetProperty(Context cx, Object obj, PropertyId propID, bool strict, Value *value);
} // namespace
#ifndef NDEBUG
namespace {
static bool EntityDumpState(ooscript::Context cx, ooscript::CallArgs &oojsArgs);
} // namespace
#endif


ooscript::Object gOOEntityJSPrototype;


namespace {
static ClassDef sEntityClass =
{
	"Entity",
	ClassFlag::HasPrivate,

	nullptr,				// addProperty (engine default: PropertyStub)
	nullptr,				// delProperty (engine default: PropertyStub)
	EntityGetProperty,		// getProperty
	EntitySetProperty,		// setProperty
	nullptr,				// enumerate (engine default: EnumerateStub)
	nullptr,				// newEnumerate (ooscript::ClassFlag::NewEnumerate not used)
	nullptr,				// resolve (engine default: ResolveStub)
	nullptr,				// convert (engine default: ConvertStub)
	OOJSCxxObjectWrapperFinalize,		// finalize (the slot holds an OOJSEntityHolder, bead oo-9ht.39.3)
	nullptr,				// call
	nullptr,				// construct
	nullptr,				// backend: owned by the façade backend, must start null
};
} // namespace


ooscript::ClassDef *JSEntityClass(void)
{
	return &sEntityClass;
}


enum : std::uint8_t
{
	// Property IDs
	kEntity_collisionRadius,	// collision radius, double, read-only.
	kEntity_distanceTravelled,	// distance travelled, double, read-only.
	kEntity_energy,				// energy, double, read-write.
	kEntity_heading,			// heading, vector, read-only (like orientation but ignoring twist angle)
	kEntity_mass,				// mass, double, read-only
	kEntity_maxEnergy,			// maxEnergy, double, read-only.
	kEntity_orientation,		// orientation, quaternion, read/write
	kEntity_owner,				// owner, Entity, read-only. (Parent ship for subentities, station for defense ships, launching ship for missiles etc)
	kEntity_position,			// position in system space, Vector, read/write
	kEntity_scanClass,			// scan class, string, read-only
	kEntity_spawnTime,			// spawn time, double, read-only.
	kEntity_status,				// entity status, string, read-only
	kEntity_isPlanet,			// is planet, boolean, read-only.
	kEntity_isPlayer,			// is player, boolean, read-only.
	kEntity_isShip,				// is ship, boolean, read-only.
	kEntity_isStation,			// is station, boolean, read-only.
	kEntity_isDock,				// is dock, boolean, read-only.
	kEntity_isSubEntity,		// is subentity, boolean, read-only.
	kEntity_isSun,				// is sun, boolean, read-only.
	kEntity_isSunlit,           // is sunlit, boolean, read-only.
	kEntity_isValid,			// is not stale, boolean, read-only.
	kEntity_isInSpace,			// is in space, boolean, read-only.
	kEntity_isVisible,			// is within drawing distance, boolean, read-only.
	kEntity_isVisualEffect,		// is visual effect, boolean, read-only.
	kEntity_isWormhole,		// is visual effect, boolean, read-only.
};


namespace {
static PropertySpec sEntityProperties[] =
{
	// JS name					ID							flags
	{ "collisionRadius",		kEntity_collisionRadius,	PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Shared, nullptr, nullptr },
	{ "distanceTravelled",		kEntity_distanceTravelled,	PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Shared, nullptr, nullptr },
	{ "energy",					kEntity_energy,				PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared, nullptr, nullptr },
	{ "heading",				kEntity_heading,			PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Shared, nullptr, nullptr },
	{ "mass",					kEntity_mass,				PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Shared, nullptr, nullptr },
	{ "maxEnergy",				kEntity_maxEnergy,			PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared, nullptr, nullptr },
	{ "orientation",			kEntity_orientation,		PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared, nullptr, nullptr },
	{ "owner",					kEntity_owner,				PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Shared, nullptr, nullptr },
	{ "position",				kEntity_position,			PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared, nullptr, nullptr },
	{ "scanClass",				kEntity_scanClass,			PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::Shared, nullptr, nullptr },
	{ "spawnTime",				kEntity_spawnTime,			PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Shared, nullptr, nullptr },
	{ "status",					kEntity_status,				PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Shared, nullptr, nullptr },
	{ "isPlanet",				kEntity_isPlanet,			PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Shared, nullptr, nullptr },
	{ "isPlayer",				kEntity_isPlayer,			PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Shared, nullptr, nullptr },
	{ "isShip",					kEntity_isShip,				PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Shared, nullptr, nullptr },
	{ "isDock",					kEntity_isDock,				PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Shared, nullptr, nullptr },
	{ "isStation",				kEntity_isStation,			PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Shared, nullptr, nullptr },
	{ "isSubEntity",			kEntity_isSubEntity,		PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Shared, nullptr, nullptr },
	{ "isSun",					kEntity_isSun,				PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Shared, nullptr, nullptr },
	{ "isSunlit",               kEntity_isSunlit,           PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Shared, nullptr, nullptr },
	{ "isValid",				kEntity_isValid,			PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Shared, nullptr, nullptr },
	{ "isInSpace",				kEntity_isInSpace,			PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Shared, nullptr, nullptr },
	{ "isVisible",				kEntity_isVisible,			PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Shared, nullptr, nullptr },
	{ "isVisualEffect",			kEntity_isVisualEffect,		PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Shared, nullptr, nullptr },
	{ "isWormhole",			kEntity_isWormhole,		PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Shared, nullptr, nullptr },
	{ 0 }
};
} // namespace


namespace {
static FunctionSpec sEntityMethods[] =
{
	// JS name					Function					min args
	{ "toString",				OOJSEntityToString,				0,	0 },
#ifndef NDEBUG
	{ "dumpState",				EntityDumpState,			0,	0 },
#endif
	{ 0 }
};
} // namespace


void InitOOJSEntity(ooscript::Context context, ooscript::Object global)
{
	Object proto = ooscript::initClass((context), (global), nullptr, &sEntityClass,
										OOJSUnconstructableConstruct, 0, sEntityProperties, sEntityMethods,
										nullptr, nullptr);
	gOOEntityJSPrototype = (proto);
	OOJSRegisterObjectConverter(&sEntityClass, OOJSEntityObjectConverter);
}


// The holder's glue (OOJSEntityHolder.h): the entity's own, while it lives.
ooscript::Value OOJSEntityHolder::jsValueInContext(ooscript::Context context)
{
	Entity *held = entity();
	return (held != nullptr) ? OOJSValueFromCxxObject(context, held) : ooscript::nullValue();
}


// OOObject's -oo_clearJSSelf:, which the facade did not override, did nothing (Entity's
// clearJSSelf() too): the entity's JS object is a GC root while the entity keeps it.
void OOJSEntityHolder::clearJSSelf(ooscript::Object /*selfVal*/)
{
}


std::optional<std::string> OOJSEntityHolder::jsDescription()
{
	Entity *held = entity();
	return (held != nullptr) ? held->jsDescription() : std::nullopt;
}


bool OOJSEntityToString(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	return OOJSCxxObjectWrapperToString(context, oojsArgs, &sEntityClass);
}


oo::PList OOJSEntityObjectConverter(ooscript::Context context, ooscript::Object object)
{
	OOJSEntityHolder *holder = static_cast<OOJSEntityHolder *>(static_cast<oo::RefCounted *>(ooscript::getPrivate(context, object)));
	Entity *entity = (holder != nullptr) ? holder->entity() : nullptr;
	return oo::EntityObjectNode(entity);	// nil: a null PList
}


HPVector OOJSEntityPositionOfJSObject(ooscript::Context context, ooscript::Object object)
{
	OOJSEntityHolder *holder = static_cast<OOJSEntityHolder *>(static_cast<oo::RefCounted *>(ooscript::getPrivate(context, object)));
	Entity *entity = (holder != nullptr) ? holder->entity() : nullptr;
	return entity != nullptr ? entity->getPosition() : HPVector{};	// zero for none, as the message to nil
}


Quaternion OOJSEntityOrientationOfJSObject(ooscript::Context context, ooscript::Object object)
{
	OOJSEntityHolder *holder = static_cast<OOJSEntityHolder *>(static_cast<oo::RefCounted *>(ooscript::getPrivate(context, object)));
	Entity *entity = (holder != nullptr) ? holder->entity() : nullptr;
	return entity != nullptr ? entity->getOrientation() : Quaternion{};	// zero for none, as the message to nil
}


Entity *OOJSEntityFromJSValue(ooscript::Context context, ooscript::Value value)
{
	if (!ooscript::isObject(value))  return nullptr;
	ooscript::Object object = ooscript::toObject(value);
	if (object == nullptr || !OOJSIsMemberOfSubclass(context, object, &sEntityClass))  return nullptr;
	OOJSEntityHolder *holder = static_cast<OOJSEntityHolder *>(static_cast<oo::RefCounted *>(ooscript::getPrivate(context, object)));
	return (holder != nullptr) ? holder->entity() : nullptr;
}


bool JSValueToEntity(ooscript::Context context, ooscript::Value value, Entity **outEntity)
{
	if (ooscript::isObjectOrNull(value))
	{
		return OOJSEntityGetEntity(context, ooscript::toObject(value), outEntity);
	}
	
	return false;
}


bool EntityFromArgumentList(ooscript::Context context, const std::optional<std::string> &scriptClass, const std::optional<std::string> &function, unsigned argc, ooscript::Value *argv, Entity **outEntity, unsigned *outConsumed)
{
	OOJS_PROFILE_ENTER
	
	// Sanity checks.
	if (outConsumed != NULL)  *outConsumed = 0;
	if (EXPECT_NOT(argc == 0 || argv == NULL || outEntity == NULL))
	{
		OOLogGenericParameterError();
		return false;
	}
	
	// Get value, if possible.
	if (EXPECT_NOT(!JSValueToEntity(context, argv[0], outEntity)))
	{
		// Failed; report bad parameters, if given a class and function.
		if (scriptClass.has_value() && function.has_value())
		{
			// The argument described as +stringWithJavaScriptParameters:count:1 described it: "(value)".
			const std::string parameters = "(" + cxx_OOJSDescribeValue(context, argv[0], false) + ")";
			cxx_OOJSReportWarning(context, "%s.%s(): expected entity, got %s.", scriptClass->c_str(), function->c_str(), parameters.c_str());
			return false;
		}
	}
	
	// Success.
	if (outConsumed != NULL)  *outConsumed = 1;
	return true;
	
	OOJS_PROFILE_EXIT
}


namespace {
static bool EntityGetProperty(Context cx, Object obj, PropertyId propID, Value *value)
{
	if (!ooscript::isInt32Id(propID))  return true;
	
	ooscript::Context context = (cx);
	ooscript::Object thisObj = (obj);
	
	OOJS_NATIVE_ENTER(context)
	
	Entity					*cxxEntity = nullptr;
	Entity					*result = nullptr;
	
	if (EXPECT_NOT(!OOJSEntityGetEntity(context, thisObj, &cxxEntity))) return false;
	if (OOIsStaleEntity(cxxEntity))
	{ 
		if (ooscript::idToInt32(propID) == kEntity_isValid)  *value = ooscript::falseValue();
		else  { *value = ooscript::undefinedValue(); }
		return true;
	}
	
	// The C++ members the root facade's selectors called (bead oo-9ht.39.8.21; ADR-0056 amendment
	// oo-9ht.39.8.21): a virtual one reaches an Objective-C entity's override as the selector did.
	switch (ooscript::idToInt32(propID))
	{
		case kEntity_collisionRadius:
			return ooscript::newNumberValue(cx, cxxEntity->collisionRadius(), value);
	
		case kEntity_position:
			return HPVectorToJSValue(context, cxxEntity->getPosition(), value);
		
		case kEntity_orientation:
			return QuaternionToJSValue(context, cxxEntity->normalOrientation(), value);
		
		case kEntity_heading:
			return VectorToJSValue(context, vector_forward_from_quaternion(cxxEntity->normalOrientation()), value);
		
		case kEntity_status:
			*value = OOJSValueFromEntityStatus(context, cxxEntity->status());
			return true;
		
		case kEntity_scanClass:
			*value = OOJSValueFromScanClass(context, cxxEntity->getScanClass());
			return true;
		
		case kEntity_mass:
			return ooscript::newNumberValue(cx, cxxEntity->getMass(), value);
		
		case kEntity_owner:
			result = cxxEntity->ownerEntity();	// the owner's C++ entity (-owner answered its object)
			if (result == cxxEntity)  result = nullptr;
			break;
		
		case kEntity_energy:
			return ooscript::newNumberValue(cx, cxxEntity->getEnergy(), value);
		
		case kEntity_maxEnergy:
			return ooscript::newNumberValue(cx, cxxEntity->getMaxEnergy(), value);
		
		case kEntity_isValid:
			*value = cxxEntity->status() == STATUS_DEAD ? ooscript::falseValue() : ooscript::trueValue();
			return true;

		case kEntity_isInSpace:
			*value = OOJSValueFromBOOL(cxxEntity->isInSpace());
			return true;
		
		case kEntity_isShip:
			*value = OOJSValueFromBOOL(cxxEntity->getIsShip());
			return true;
		
		case kEntity_isStation:
			*value = OOJSValueFromBOOL(cxxEntity->getIsStation());
			return true;

		case kEntity_isDock:
			*value = OOJSValueFromBOOL(cxxEntity->isDock());
			return true;
			
		case kEntity_isSubEntity:
			*value = OOJSValueFromBOOL(cxxEntity->getIsSubEntity());
			return true;
		
		case kEntity_isPlayer:
			*value = OOJSValueFromBOOL(cxxEntity->getIsPlayer());
			return true;
			
		case kEntity_isPlanet:
			*value = OOJSValueFromBOOL(cxxEntity->isPlanet());
			return true;
			
		case kEntity_isSun:
			*value = OOJSValueFromBOOL(cxxEntity->isSun());
			return true;
		
		case kEntity_isSunlit:
			*value = OOJSValueFromBOOL(cxxEntity->getIsSunlit());
			return true;
			
		case kEntity_isVisible:
			*value = OOJSValueFromBOOL(cxxEntity->isVisible());
			return true;

		case kEntity_isVisualEffect:
			*value = OOJSValueFromBOOL(cxxEntity->getIsVisualEffect());
			return true;

		case kEntity_isWormhole:
			*value = OOJSValueFromBOOL(cxxEntity->getIsWormhole());
			return true;
			
		case kEntity_distanceTravelled:
			return ooscript::newNumberValue(cx, cxxEntity->getDistanceTravelled(), value);
		
		case kEntity_spawnTime:
			return ooscript::newNumberValue(cx, cxxEntity->getSpawnTime(), value);
		
		default:
			OOJSReportBadPropertySelector(context, thisObj, (propID), sEntityProperties);
	}
	
	*value = OOJSValueFromCxxObject(context, result);	// the owner's JS value, its object's (null for none)
	return true;
	
	OOJS_NATIVE_EXIT
}
} // namespace


namespace {
static bool EntitySetProperty(Context cx, Object obj, PropertyId propID, bool /*strict*/, Value *value)
{
	if (!ooscript::isInt32Id(propID))  return true;
	
	ooscript::Context context = (cx);
	ooscript::Object thisObj = (obj);
	
	OOJS_NATIVE_ENTER(context)
	
	Entity			*cxxEntity = nullptr;
	double				fValue;
	HPVector				hpvValue;
	Quaternion			qValue;
	
	if (EXPECT_NOT(!OOJSEntityGetEntity(context, thisObj, &cxxEntity)))  return false;
	if (OOIsStaleEntity(cxxEntity))  return true;
	// The C++ members the root facade's selectors called (bead oo-9ht.39.8.21).
	
	switch (ooscript::idToInt32(propID))
	{
		case kEntity_position:
			if (JSValueToHPVector(context, *value, &hpvValue))
			{
				cxxEntity->setPosition(hpvValue);
				if (cxxEntity->getIsShip())
				{
					if (oo::ToShip(cxxEntity) != nullptr)  oo::ToShip(cxxEntity)->resetExhaustPlumes();
					if (oo::ToShip(cxxEntity) != nullptr)  oo::ToShip(cxxEntity)->forceAegisCheck();
				}
				return true;
			}
			break;
			
		case kEntity_orientation:
			if (JSValueToQuaternion(context, *value, &qValue))
			{
				cxxEntity->setNormalOrientation(qValue);
				return true;
			}
			break;
			
		case kEntity_energy:
			if (ooscript::valueToNumber(cx, *value, &fValue))
			{
				fValue = OOClamp_0_max_d(fValue, cxxEntity->getMaxEnergy());
				cxxEntity->setEnergy(fValue);
				return true;
			}
			break;

		case kEntity_maxEnergy:
			if (ooscript::valueToNumber(cx, *value, &fValue))
			{
				if (fValue <= 0.0)
				{
					cxx_OOJSReportError(context, "entity.maxEnergy must be positive.");
					return false;
				}
				cxxEntity->setMaxEnergy(fValue);
				return true;
			}
			break;


		case kEntity_scanClass:
			if (cxxEntity->getIsShip() && !cxxEntity->getIsPlayer())
			{
				OOScanClass newClass = OOScanClassFromJSValue(context, *value);
				if (newClass == CLASS_NOT_SET || newClass == CLASS_NO_DRAW || newClass == CLASS_TARGET || newClass == CLASS_WORMHOLE || newClass == CLASS_PLAYER || newClass == CLASS_VISUAL_EFFECT)
				{
					cxx_OOJSReportError(context, "entity.scanClass cannot be set to that value.");
					return false;
				}
				cxxEntity->setScanClass(newClass);
				return true;
			}
			else
			{
				cxx_OOJSReportError(context, "entity.scanClass is read-only except on NPC ships.");
				return false;
			}
		default:
			OOJSReportBadPropertySelector(context, thisObj, (propID), sEntityProperties);
			return false;
	}
	
	OOJSReportBadPropertyValue(context, thisObj, (propID), sEntityProperties, *value);
	return false;
	
	OOJS_NATIVE_EXIT
}
} // namespace


#ifndef NDEBUG
namespace {
static bool EntityDumpState(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_PROFILE_ENTER
	
	Entity *thisEnt = nullptr;
	OOJSEntityGetEntity(context, OOJS_THIS, &thisEnt);
	if (thisEnt != nullptr)  thisEnt->dumpState();	// the C++ member, which the object's -dumpState called (bead oo-9ht.39.8.2)
	
	OOJS_RETURN_VOID;
	
	OOJS_PROFILE_EXIT	
}
} // namespace
#endif
