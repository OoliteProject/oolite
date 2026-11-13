/*

OOJSEntity.m (QuickJS-ng)

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

#include <optional>
#include <string>

#include "EntityOOJavaScriptExtensions.h"
#include "OOConstToJSString.h"
#include "OOJSCall.h"
#include "OOJSQuaternion.h"
#include "OOJSVector.h"
#include "OOJavaScriptEngine.h"
#include "PlayerEntity.h"
#include "ShipEntity.h"
#include "oofnd/PList.hpp"

/*
        The Entity class is the shared base for every other entity binding
        file's OOJSRegisterSubclass() call and entity getter; JSEntityClassID()
        returns its ID.
*/

static JSClassID sEntityClassID;

static JSValue EntityGetProperty(OOJS_GETTER_ARGS);
static JSValue EntitySetProperty(OOJS_SETTER_ARGS);
#ifdef OO_DEBUG_MONITOR_ENABLED
static JSValue EntityDumpState(OOJS_NATIVE_ARGS);
#endif

static JSClassDef sEntityClass = {
    .class_name = "Entity",
    .finalizer =
        OOJSCxxObjectWrapperFinalize,  // the slot holds an OOJSEntityHolder
};

namespace {

enum class EntityProperty : std::int16_t {
  // Property IDs
  kCollisionRadius,    // collision radius, double, read-only.
  kDistanceTravelled,  // distance travelled, double, read-only.
  kEnergy,             // energy, double, read-write.
  kHeading,      // heading, vector, read-only (like orientation but ignoring
                 // twist angle)
  kMass,         // mass, double, read-only
  kMaxEnergy,    // maxEnergy, double, read-only.
  kOrientation,  // orientation, quaternion, read/write
  kOwner,        // owner, Entity, read-only. (Parent ship for subentities,
                 // station for defense ships, launching ship for missiles etc)
  kPosition,     // position in system space, Vector, read/write
  kScanClass,    // scan class, string, read-only
  kSpawnTime,    // spawn time, double, read-only.
  kStatus,       // entity status, string, read-only
  kIsPlanet,     // is planet, boolean, read-only.
  kIsPlayer,     // is player, boolean, read-only.
  kIsShip,       // is ship, boolean, read-only.
  kIsStation,    // is station, boolean, read-only.
  kIsDock,       // is dock, boolean, read-only.
  kIsSubEntity,  // is subentity, boolean, read-only.
  kIsSun,        // is sun, boolean, read-only.
  kIsSunlit,     // is sunlit, boolean, read-only.
  kIsValid,      // is not stale, boolean, read-only.
  kIsInSpace,    // is in space, boolean, read-only.
  kIsVisible,    // is within drawing distance, boolean, read-only.
  kIsVisualEffect,  // is visual effect, boolean, read-only.
  kIsWormhole,      // is visual effect, boolean, read-only.
};

}  // namespace

static const JSCFunctionListEntry sEntityProperties[] = {
    // JS name, getter, setter, ID
    OOJS_PROPERTY_RO("collisionRadius", EntityGetProperty,
                     EntityProperty::kCollisionRadius),
    OOJS_PROPERTY_RO("distanceTravelled", EntityGetProperty,
                     EntityProperty::kDistanceTravelled),
    OOJS_PROPERTY_RW("energy", EntityGetProperty, EntitySetProperty,
                     EntityProperty::kEnergy),
    OOJS_PROPERTY_RO("heading", EntityGetProperty, EntityProperty::kHeading),
    OOJS_PROPERTY_RO("mass", EntityGetProperty, EntityProperty::kMass),
    OOJS_PROPERTY_RW("maxEnergy", EntityGetProperty, EntitySetProperty,
                     EntityProperty::kMaxEnergy),
    OOJS_PROPERTY_RW("orientation", EntityGetProperty, EntitySetProperty,
                     EntityProperty::kOrientation),
    OOJS_PROPERTY_RO("owner", EntityGetProperty, EntityProperty::kOwner),
    OOJS_PROPERTY_RW("position", EntityGetProperty, EntitySetProperty,
                     EntityProperty::kPosition),
    OOJS_PROPERTY_RW("scanClass", EntityGetProperty, EntitySetProperty,
                     EntityProperty::kScanClass),
    OOJS_PROPERTY_RO("spawnTime", EntityGetProperty,
                     EntityProperty::kSpawnTime),
    OOJS_PROPERTY_RO("status", EntityGetProperty, EntityProperty::kStatus),
    OOJS_PROPERTY_RO("isPlanet", EntityGetProperty, EntityProperty::kIsPlanet),
    OOJS_PROPERTY_RO("isPlayer", EntityGetProperty, EntityProperty::kIsPlayer),
    OOJS_PROPERTY_RO("isShip", EntityGetProperty, EntityProperty::kIsShip),
    OOJS_PROPERTY_RO("isDock", EntityGetProperty, EntityProperty::kIsDock),
    OOJS_PROPERTY_RO("isStation", EntityGetProperty,
                     EntityProperty::kIsStation),
    OOJS_PROPERTY_RO("isSubEntity", EntityGetProperty,
                     EntityProperty::kIsSubEntity),
    OOJS_PROPERTY_RO("isSun", EntityGetProperty, EntityProperty::kIsSun),
    OOJS_PROPERTY_RO("isSunlit", EntityGetProperty, EntityProperty::kIsSunlit),
    OOJS_PROPERTY_RO("isValid", EntityGetProperty, EntityProperty::kIsValid),
    OOJS_PROPERTY_RO("isInSpace", EntityGetProperty,
                     EntityProperty::kIsInSpace),
    OOJS_PROPERTY_RO("isVisible", EntityGetProperty,
                     EntityProperty::kIsVisible),
    OOJS_PROPERTY_RO("isVisualEffect", EntityGetProperty,
                     EntityProperty::kIsVisualEffect),
    OOJS_PROPERTY_RO("isWormhole", EntityGetProperty,
                     EntityProperty::kIsWormhole),
};

static const JSCFunctionListEntry sEntityMethods[] = {
    // JS name, min args, function
    JS_CFUNC_DEF("toString", 0, OOJSEntityToString),
#ifdef OO_DEBUG_MONITOR_ENABLED
    JS_CFUNC_DEF("dumpState", 0, EntityDumpState),
#endif
};

JSClassID JSEntityClassID() { return sEntityClassID; }

void InitOOJSEntity(JSContext* context, JSValueConst global) {
  OOJSRegisterClass(&sEntityClassID, &sEntityClass);
  OOJSInitClass(context, global, sEntityClassID, JS_UNDEFINED,
                OOJSUnconstructableConstruct, 0, sEntityProperties,
                OOJS_COUNT(sEntityProperties), sEntityMethods,
                OOJS_COUNT(sEntityMethods), nullptr, 0);
  OOJSRegisterObjectConverter(sEntityClassID, OOJSEntityObjectConverter);
}

// The holder's glue (OOJSEntityHolder.h): the entity's own, while it lives.
// Owned by the caller.
JSValue OOJSEntityHolder::jsValueInContext(JSContext* context) {
  Entity* held = entity();
  return (held != nullptr) ? OOJSValueFromCxxObject(context, held) : JS_NULL;
}

// Does nothing (Entity's clearJSSelf() too): the entity keeps its own reference
// to its JS object while it lives.
void OOJSEntityHolder::clearJSSelf(JSValueConst /*selfVal*/) {}

std::optional<std::string> OOJSEntityHolder::jsDescription() {
  Entity* held = entity();
  return (held != nullptr) ? held->jsDescription() : std::nullopt;
}

JSValue OOJSEntityToString(OOJS_NATIVE_ARGS) {
  return OOJSCxxObjectWrapperToString(context, OOJS_THIS, sEntityClassID);
}

namespace {
// The C++ entity in an entity object's slot (of the Entity class or a
// subclass): the holder's entity, null for none (a prototype) or a stale one.
Entity* EntityOfJSObject(JSValueConst object) {
  JSClassID ignored;
  OOJSEntityHolder* holder = static_cast<OOJSEntityHolder*>(
      OOJSCxxPrivateFromOpaque(JS_GetAnyOpaque(object, &ignored)));
  return (holder != nullptr) ? holder->entity() : nullptr;
}
}  // namespace

oo::PList OOJSEntityObjectConverter(JSContext* /*context*/,
                                    JSValueConst object) {
  return oo::EntityObjectNode(EntityOfJSObject(object));  // nil: a null PList
}

HPVector OOJSEntityPositionOfJSObject(JSContext* /*context*/,
                                      JSValueConst object) {
  Entity* entity = EntityOfJSObject(object);
  return entity != nullptr
             ? entity->getPosition()
             : HPVector{};  // zero for none, as the message to nil
}

Quaternion OOJSEntityOrientationOfJSObject(JSContext* /*context*/,
                                           JSValueConst object) {
  Entity* entity = EntityOfJSObject(object);
  return entity != nullptr
             ? entity->getOrientation()
             : Quaternion{};  // zero for none, as the message to nil
}

Entity* OOJSEntityFromJSValue(JSContext* context, JSValueConst value) {
  if (!OOJSIsMemberOfSubclass(context, value, sEntityClassID)) return nullptr;
  return EntityOfJSObject(value);
}

bool JSValueToEntity(JSContext* context, JSValueConst value,
                     Entity** outEntity) {
  if (JS_IsObject(value)) {
    return OOJSEntityGetEntity(context, value, outEntity);
  }

  return false;
}

bool EntityFromArgumentList(JSContext* context,
                            const std::optional<std::string>& scriptClass,
                            const std::optional<std::string>& function,
                            int argc, JSValueConst* argv, Entity** outEntity,
                            int* outConsumed) {
  OOJS_PROFILE_ENTER

  // Sanity checks.
  if (outConsumed != nullptr) *outConsumed = 0;
  if (EXPECT_NOT(argc == 0 || argv == nullptr || outEntity == nullptr)) {
    OOLogGenericParameterError();
    return false;
  }

  // Get value, if possible.
  if (EXPECT_NOT(!JSValueToEntity(context, argv[0], outEntity))) {
    // Failed; report bad parameters, if given a class and function.
    if (scriptClass.has_value() && function.has_value()) {
      // The argument described as +stringWithJavaScriptParameters:count:1
      // described it: "(value)".
      const std::string parameters =
          "(" + OOJSDescribeValue(context, argv[0], false) + ")";
      OOJSReportWarning(context, "%s.%s(): expected entity, got %s.",
                        scriptClass->c_str(), function->c_str(),
                        parameters.c_str());
      return false;
    }
  }

  // Success.
  if (outConsumed != nullptr) *outConsumed = 1;
  return true;

  OOJS_PROFILE_EXIT
}

static JSValue EntityGetProperty(OOJS_GETTER_ARGS) {
  OOJS_NATIVE_ENTER(context)

  Entity* cxxEntity = nullptr;
  Entity* result = nullptr;

  if (EXPECT_NOT(!OOJSEntityGetEntity(context, thisObj, &cxxEntity)))
    return JS_EXCEPTION;
  if (OOIsStaleEntity(cxxEntity)) {
    if (static_cast<EntityProperty>(magic) == EntityProperty::kIsValid)
      return JS_FALSE;
    else
      return JS_UNDEFINED;
  }

  // The C++ members the properties call: a virtual one reaches the
  // entity's override.
  switch (static_cast<EntityProperty>(magic)) {
    using enum EntityProperty;
    case kCollisionRadius:
      return JS_NewFloat64(context, cxxEntity->collisionRadius());

    case kPosition:
      OOJS_RETURN_HPVECTOR(cxxEntity->getPosition());

    case kOrientation:
      OOJS_RETURN_QUATERNION(cxxEntity->normalOrientation());

    case kHeading:
      OOJS_RETURN_VECTOR(
          vector_forward_from_quaternion(cxxEntity->normalOrientation()));

    case kStatus:
      return OOJSValueFromEntityStatus(context, cxxEntity->status());

    case kScanClass:
      return OOJSValueFromScanClass(context, cxxEntity->getScanClass());

    case kMass:
      return JS_NewFloat64(context, cxxEntity->getMass());

    case kOwner:
      result = cxxEntity->ownerEntity();  // the owner's C++ entity (-owner
                                          // answered its object)
      if (result == cxxEntity) result = nullptr;
      break;

    case kEnergy:
      return JS_NewFloat64(context, cxxEntity->getEnergy());

    case kMaxEnergy:
      return JS_NewFloat64(context, cxxEntity->getMaxEnergy());

    case kIsValid:
      return cxxEntity->status() == OOEntityStatus::kDead ? JS_FALSE : JS_TRUE;

    case kIsInSpace:
      return OOJSValueFromBOOL(cxxEntity->isInSpace());

    case kIsShip:
      return OOJSValueFromBOOL(cxxEntity->getIsShip());

    case kIsStation:
      return OOJSValueFromBOOL(cxxEntity->getIsStation());

    case kIsDock:
      return OOJSValueFromBOOL(cxxEntity->isDock());

    case kIsSubEntity:
      return OOJSValueFromBOOL(cxxEntity->getIsSubEntity());

    case kIsPlayer:
      return OOJSValueFromBOOL(cxxEntity->getIsPlayer());

    case kIsPlanet:
      return OOJSValueFromBOOL(cxxEntity->isPlanet());

    case kIsSun:
      return OOJSValueFromBOOL(cxxEntity->isSun());

    case kIsSunlit:
      return OOJSValueFromBOOL(cxxEntity->getIsSunlit());

    case kIsVisible:
      return OOJSValueFromBOOL(cxxEntity->isVisible());

    case kIsVisualEffect:
      return OOJSValueFromBOOL(cxxEntity->getIsVisualEffect());

    case kIsWormhole:
      return OOJSValueFromBOOL(cxxEntity->getIsWormhole());

    case kDistanceTravelled:
      return JS_NewFloat64(context, cxxEntity->getDistanceTravelled());

    case kSpawnTime:
      return JS_NewFloat64(context, cxxEntity->getSpawnTime());

    default:
      OOJSReportBadPropertySelector(context, thisObj, magic, sEntityProperties,
                                    OOJS_COUNT(sEntityProperties));
      return JS_EXCEPTION;
  }

  return OOJSValueFromCxxObject(
      context,
      result);  // the owner's JS value, its object's (null for none); owned

  OOJS_NATIVE_EXIT
}

static JSValue EntitySetProperty(OOJS_SETTER_ARGS) {
  OOJS_NATIVE_ENTER(context)

  Entity* cxxEntity = nullptr;
  double fValue;
  HPVector hpvValue;
  Quaternion qValue;

  if (EXPECT_NOT(!OOJSEntityGetEntity(context, thisObj, &cxxEntity)))
    return JS_EXCEPTION;
  if (OOIsStaleEntity(cxxEntity)) return JS_UNDEFINED;
  // The C++ members the properties call.

  switch (static_cast<EntityProperty>(magic)) {
    using enum EntityProperty;
    case kPosition:
      if (JSValueToHPVector(context, value, &hpvValue)) {
        cxxEntity->setPosition(hpvValue);
        if (cxxEntity->getIsShip()) {
          if (oo::ToShip(cxxEntity) != nullptr)
            oo::ToShip(cxxEntity)->resetExhaustPlumes();
          if (oo::ToShip(cxxEntity) != nullptr)
            oo::ToShip(cxxEntity)->forceAegisCheck();
        }
        return JS_UNDEFINED;
      }
      break;

    case kOrientation:
      if (JSValueToQuaternion(context, value, &qValue)) {
        cxxEntity->setNormalOrientation(qValue);
        return JS_UNDEFINED;
      }
      break;

    case kEnergy:
      if (JS_ToFloat64(context, &fValue, value) == 0) {
        fValue = OOClamp_0_max_d(fValue, cxxEntity->getMaxEnergy());
        cxxEntity->setEnergy(fValue);
        return JS_UNDEFINED;
      }
      JS_FreeValue(context, JS_GetException(context));
      break;

    case kMaxEnergy:
      if (JS_ToFloat64(context, &fValue, value) == 0) {
        if (fValue <= 0.0) {
          OOJSReportError(context, "entity.maxEnergy must be positive.");
          return JS_EXCEPTION;
        }
        cxxEntity->setMaxEnergy(fValue);
        return JS_UNDEFINED;
      }
      JS_FreeValue(context, JS_GetException(context));
      break;

    case kScanClass:
      if (cxxEntity->getIsShip() && !cxxEntity->getIsPlayer()) {
        OOScanClass newClass = OOScanClassFromJSValue(context, value);
        if (newClass == OOScanClass::kNotSet ||
            newClass == OOScanClass::kNoDraw ||
            newClass == OOScanClass::kTarget ||
            newClass == OOScanClass::kWormhole ||
            newClass == OOScanClass::kPlayer ||
            newClass == OOScanClass::kVisualEffect) {
          OOJSReportError(context,
                          "entity.scanClass cannot be set to that value.");
          return JS_EXCEPTION;
        }
        cxxEntity->setScanClass(newClass);
        return JS_UNDEFINED;
      } else {
        OOJSReportError(context,
                        "entity.scanClass is read-only except on NPC ships.");
        return JS_EXCEPTION;
      }
    default:
      OOJSReportBadPropertySelector(context, thisObj, magic, sEntityProperties,
                                    OOJS_COUNT(sEntityProperties));
      return JS_EXCEPTION;
  }

  OOJSReportBadPropertyValue(context, thisObj, magic, sEntityProperties,
                             OOJS_COUNT(sEntityProperties), value);
  return JS_EXCEPTION;

  OOJS_NATIVE_EXIT
}

#ifdef OO_DEBUG_MONITOR_ENABLED
static JSValue EntityDumpState(OOJS_NATIVE_ARGS) {
  OOJS_PROFILE_ENTER

  Entity* thisEnt = nullptr;
  OOJSEntityGetEntity(context, OOJS_THIS, &thisEnt);
  if (thisEnt != nullptr) thisEnt->dumpState();  // the C++ member

  OOJS_RETURN_VOID;

  OOJS_PROFILE_EXIT
}
#endif
