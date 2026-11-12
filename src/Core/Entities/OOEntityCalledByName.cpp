/*

OOEntityCalledByName.cpp

An entity's method called by name, on its C++ part (declared in OOCallByName.h).
The by-name table is OOEntityCalledByNameTable.h: a tabled name is answered for
the C++ part it applies to, and called as OOCallByName calls the method (the
signature rules read from the declared types' encodings: @encode()'s, measured
literals). Any other name, and a tabled name that does not apply, are answered
from OOEntityObjectNamesTable.h. callObjC() reads a typed result through
oo::CallEntityByNameTyped. The table is the source: a tabled name that applies
but whose signature the call cannot use is logged here, and
oo::ScheduleEntityCall holds the deferred calls.

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

#include "OOEntityCalledByName.h"

#include <cstring>
#include <string_view>
#include <type_traits>
#include <unordered_map>

#include "AI.h"
#include "DockEntity.h"
#include "Entity.h"
#include "GameController.h"  // OOScheduleDeferredCall (oo::ScheduleEntityCall, the player's selectors called by name)
#include "OOCallByName.h"
#include "OODescription.h"
#include "OOEntityWithDrawable.h"
#include "OOPlanetEntity.h"  // the root-entity rows
#include "OOQuiriumCascadeEntity.h"
#include "OOTypeEncodings.h"  // the rows' measured encodings
#include "OOVisualEffectEntity.h"
#include "OOWaypointEntity.h"
#include "PlayerEntity.h"
#include "ProxyPlayerEntity.h"
#include "ShipEntity.h"
#include "ShipEntityAI.h"
#include "ShipEntityScriptMethods.h"
#include "StationEntity.h"
#include "Universe.h"
#include "oofnd/Log.hpp"

namespace {

// The parts the table's method bodies read.
ShipEntity* ShipPart(Entity* entity) {
  return dynamic_cast<ShipEntity*>(entity);
}
StationEntity* StationPart(Entity* entity) {
  return dynamic_cast<StationEntity*>(entity);
}
DockEntity* DockPart(Entity* entity) {
  return dynamic_cast<DockEntity*>(entity);
}
PlayerEntity* PlayerEntityPart(Entity* entity) {
  return dynamic_cast<PlayerEntity*>(entity);
}
ProxyPlayerEntity* ProxyPart(Entity* entity) {
  return dynamic_cast<ProxyPlayerEntity*>(entity);
}
OOVisualEffectEntity* EffectPart(Entity* entity) {
  return dynamic_cast<OOVisualEffectEntity*>(entity);
}

}  // namespace

// The generated table's row (OOEntityCalledByName.h declares the flags and the
// argument kinds).
namespace {

template <auto Function>
oo::PList OOEntityByNameAdaptNone(Entity* entity, const std::string*,
                                  const oo::PList*) {
  if constexpr (std::is_same_v<decltype(Function(entity)), oo::PList>)
    return Function(entity);
  else {
    (void)Function(entity);
    return oo::PList();
  }
}

template <auto Function>
oo::PList OOEntityByNameAdaptString(Entity* entity, const std::string* string,
                                    const oo::PList*) {
  if constexpr (std::is_same_v<decltype(Function(entity, *string)), oo::PList>)
    return Function(entity, *string);
  else {
    (void)Function(entity, *string);
    return oo::PList();
  }
}

template <auto Function>
oo::PList OOEntityByNameAdaptPList(Entity* entity, const std::string*,
                                   const oo::PList* plist) {
  if constexpr (std::is_same_v<decltype(Function(entity, *plist)), oo::PList>)
    return Function(entity, *plist);
  else {
    (void)Function(entity, *plist);
    return oo::PList();
  }
}

template <auto Function>
void OOEntityByNameTyped(Entity* entity, OOEntityByNameValue& value) {
  using Result = decltype(Function(entity));
  if constexpr (std::is_void_v<Result>)
    Function(entity);
  else if constexpr (std::is_same_v<Result, oo::PList>)
    value.plist = Function(entity);
  else if constexpr (std::is_integral_v<Result> && std::is_signed_v<Result> &&
                     sizeof(Result) == 1) {
    // a signed char (bool): its value, sign kept, as OOCallIntegerMethod()
    // converted it
    const long long bits = static_cast<unsigned char>(Function(entity));
    value.integer = (bits > 127) ? bits - 256 : bits;
  } else if constexpr (std::is_integral_v<Result> || std::is_enum_v<Result>)
    value.integer = static_cast<long long>(Function(entity));
  else if constexpr (std::is_floating_point_v<Result>)
    value.real = static_cast<double>(Function(entity));
  else if constexpr (std::is_same_v<Result, Vector>)
    value.vector = Function(entity);
  else if constexpr (std::is_same_v<Result, Quaternion>)
    value.quaternion = Function(entity);
  else if constexpr (std::is_same_v<Result, OOColor*>)
    value.color = Function(entity);  // borrowed
  else if constexpr (std::is_convertible_v<Result, Entity*>)
    value.entity = Function(entity);  // the C++ entity
  else
    (void)Function(entity);  // a result callObjC() cannot read (it does not
                             // call such a method)
}

}  // namespace

#include "OOEntityCalledByNameTable.h"

/*	The root entity's own names that callObjC() lists and the by-name table
   does not, so callObjC() asks and calls an entity's C++ part for every name of
   its table. Each function is the method's body on the C++ entity, after a
   guard for no entity (zero; the calls never pass one); a name whose result
        callObjC() cannot read (a string, a vector of objects, a matrix, a
   high-precision vector, a bounding box: "cannot be called", or no result) has
   no function. Every entity answers them but for the planet's shader selectors
   (a planet's part) and the beacon protocol's (a ship's, an effect's or a
   waypoint's part). The entity results (nextBeacon, prevBeacon, parentEntity,
   rootShipEntity) are the C++ entity: callObjC() makes its Object node.
*/
namespace {

bool AnswersPlanet(Entity* entity) {
  return dynamic_cast<OOPlanetEntity*>(entity) != nullptr;
}
bool AnswersBeacon(Entity* entity) {
  return dynamic_cast<OOWaypointEntity*>(entity) != nullptr ||
         ShipPart(entity) != nullptr || EffectPart(entity) != nullptr;
}

void Facade_addToLinkedLists(Entity* entity) {
  if (entity == nullptr) return;
  entity->addToLinkedLists();
}
Vector Facade_airColorAsVector(Entity* entity) {
  if (entity == nullptr) return {};
  OOPlanetEntity* planet = dynamic_cast<OOPlanetEntity*>(entity);
  return planet != nullptr ? planet->airColorAsVector() : kZeroVector;
}
float Facade_airColorMixRatio(Entity* entity) {
  if (entity == nullptr) return {};
  OOPlanetEntity* planet = dynamic_cast<OOPlanetEntity*>(entity);
  return planet != nullptr ? planet->airColorMixRatio() : 0.0f;
}
float Facade_airDensity(Entity* entity) {
  if (entity == nullptr) return {};
  OOPlanetEntity* planet = dynamic_cast<OOPlanetEntity*>(entity);
  return planet != nullptr ? planet->airDensity() : 0.0f;
}
OOHUDBeaconIcon* Facade_beaconDrawable(Entity* entity) {
  if (entity == nullptr) return {};
  if (ShipEntity* ship = ShipPart(entity)) return ship->beaconDrawable();
  if (OOVisualEffectEntity* effect = EffectPart(entity))
    return effect->beaconDrawable();
  OOWaypointEntity* waypoint = dynamic_cast<OOWaypointEntity*>(entity);
  return waypoint != nullptr ? waypoint->beaconDrawable() : nullptr;
}
double Facade_camZeroDistance(Entity* entity) {
  if (entity == nullptr) return {};
  return entity->camZeroDistance();
}
GLfloat Facade_cameraRangeBack(Entity* entity) {
  if (entity == nullptr) return {};
  return entity->cameraRangeBack();
}
GLfloat Facade_cameraRangeFront(Entity* entity) {
  if (entity == nullptr) return {};
  return entity->cameraRangeFront();
}
Vector Facade_cameraRelativePosition(Entity* entity) {
  if (entity == nullptr) return {};
  return entity->getCameraRelativePosition();
}
bool Facade_canCollide(Entity* entity) {
  if (entity == nullptr) return {};
  return entity->canCollide();
}
GLfloat Facade_collisionRadius(Entity* entity) {
  if (entity == nullptr) return {};
  return entity->collisionRadius();
}
void Facade_deleteJSSelf(Entity* entity) {
  if (entity == nullptr) return;
  entity->deleteJSSelf();
}
GLfloat Facade_distanceTravelled(Entity* entity) {
  if (entity == nullptr) return {};
  return entity->getDistanceTravelled();
}
void Facade_dumpSelfState(Entity* entity) {
  if (entity == nullptr) return;
  entity->dumpSelfState();
}
void Facade_dumpState(Entity* entity) {
  if (entity == nullptr) return;
  entity->dumpState();
}
GLfloat Facade_energy(Entity* entity) {
  if (entity == nullptr) return {};
  return entity->getEnergy();
}
double Facade_findCollisionRadius(Entity* entity) {
  if (entity == nullptr) return {};
  return entity->findCollisionRadius();
}
OOColor* Facade_fogUniform(Entity* entity) {
  if (entity == nullptr) return {};
  return entity->fogUniform().get();
}
GLfloat Facade_frustumRadius(Entity* entity) {
  if (entity == nullptr) return {};
  return entity->frustumRadius();
}
Vector Facade_illuminationColorAsVector(Entity* entity) {
  if (entity == nullptr) return {};
  OOPlanetEntity* planet = dynamic_cast<OOPlanetEntity*>(entity);
  return planet != nullptr ? planet->illuminationColorAsVector() : kZeroVector;
}
bool Facade_isBeacon(Entity* entity) {
  if (entity == nullptr) return {};
  if (ShipEntity* ship = ShipPart(entity)) return ship->isBeacon();
  if (OOVisualEffectEntity* effect = EffectPart(entity))
    return effect->isBeacon();
  OOWaypointEntity* waypoint = dynamic_cast<OOWaypointEntity*>(entity);
  return waypoint != nullptr ? waypoint->isBeacon() : false;
}
bool Facade_isCascadeWeapon(Entity* entity) {
  if (entity == nullptr) return {};
  OOQuiriumCascadeEntity* cascade =
      dynamic_cast<OOQuiriumCascadeEntity*>(entity);
  return cascade != nullptr ? cascade->isCascadeWeapon() : false;
}
bool Facade_isDock(Entity* entity) {
  if (entity == nullptr) return {};
  return entity->isDock();
}
bool Facade_isEffect(Entity* entity) {
  if (entity == nullptr) return {};
  return entity->isEffect();
}
bool Facade_isImmuneToBreakPatternHide(Entity* entity) {
  if (entity == nullptr) return {};
  return entity->getIsImmuneToBreakPatternHide();
}
bool Facade_isInSpace(Entity* entity) {
  if (entity == nullptr) return {};
  return entity->isInSpace();
}
bool Facade_isJammingScanning(Entity* entity) {
  if (entity == nullptr) return {};
  if (ShipEntity* ship = ShipPart(entity)) return ship->isJammingScanning();
  if (OOVisualEffectEntity* effect = EffectPart(entity))
    return effect->isJammingScanning();
  OOWaypointEntity* waypoint = dynamic_cast<OOWaypointEntity*>(entity);
  return waypoint != nullptr ? waypoint->isJammingScanning() : false;
}
bool Facade_isPlanet(Entity* entity) {
  if (entity == nullptr) return {};
  return entity->isPlanet();
}
bool Facade_isPlayer(Entity* entity) {
  if (entity == nullptr) return {};
  return entity->getIsPlayer();
}
bool Facade_isShip(Entity* entity) {
  if (entity == nullptr) return {};
  return entity->getIsShip();
}
bool Facade_isSky(Entity* entity) {
  if (entity == nullptr) return {};
  return entity->isSky();
}
bool Facade_isStation(Entity* entity) {
  if (entity == nullptr) return {};
  return entity->getIsStation();
}
bool Facade_isStellarObject(Entity* entity) {
  if (entity == nullptr) return {};
  return entity->isStellarObject();
}
bool Facade_isSubEntity(Entity* entity) {
  if (entity == nullptr) return {};
  return entity->getIsSubEntity();
}
bool Facade_isSun(Entity* entity) {
  if (entity == nullptr) return {};
  return entity->isSun();
}
bool Facade_isSunlit(Entity* entity) {
  if (entity == nullptr) return {};
  return entity->getIsSunlit();
}
bool Facade_isVisible(Entity* entity) {
  if (entity == nullptr) return {};
  return entity->isVisible();
}
bool Facade_isVisibleToScripts(Entity* entity) {
  if (entity == nullptr) return {};
  return entity->isVisibleToScripts();
}
bool Facade_isVisualEffect(Entity* entity) {
  if (entity == nullptr) return {};
  return entity->getIsVisualEffect();
}
bool Facade_isWaypoint(Entity* entity) {
  if (entity == nullptr) return {};
  return entity->isWaypoint();
}
bool Facade_isWormhole(Entity* entity) {
  if (entity == nullptr) return {};
  return entity->getIsWormhole();
}
std::size_t Facade_lastDrawCounter(Entity* entity) {
  if (entity == nullptr) return {};
  return entity->getLastDrawCounter();
}
GLfloat Facade_mass(Entity* entity) {
  if (entity == nullptr) return {};
  return entity->getMass();
}
GLfloat Facade_maxEnergy(Entity* entity) {
  if (entity == nullptr) return {};
  return entity->getMaxEnergy();
}
Entity* Facade_nextBeacon(Entity* entity) {
  if (entity == nullptr) return {};
  if (ShipEntity* ship = ShipPart(entity)) return ship->nextBeacon();
  if (OOVisualEffectEntity* effect = EffectPart(entity))
    return effect->nextBeacon();
  OOWaypointEntity* waypoint = dynamic_cast<OOWaypointEntity*>(entity);
  return waypoint != nullptr ? waypoint->nextBeacon() : nullptr;
}
Quaternion Facade_normalOrientation(Entity* entity) {
  if (entity == nullptr) return {};
  return entity->normalOrientation();
}
Quaternion Facade_orientation(Entity* entity) {
  if (entity == nullptr) return {};
  return entity->getOrientation();
}
void Facade_orientationChanged(Entity* entity) {
  if (entity == nullptr) return;
  entity->orientationChanged();
}
Entity* Facade_owner(Entity* entity)  // the owner's C++ entity
{
  if (entity == nullptr) return {};
  return entity->owner();
}
Entity* Facade_parentEntity(Entity* entity) {
  if (entity == nullptr) return {};
  return entity->parentEntity();
}
Entity* Facade_prevBeacon(Entity* entity) {
  if (entity == nullptr) return {};
  if (ShipEntity* ship = ShipPart(entity)) return ship->prevBeacon();
  if (OOVisualEffectEntity* effect = EffectPart(entity))
    return effect->prevBeacon();
  OOWaypointEntity* waypoint = dynamic_cast<OOWaypointEntity*>(entity);
  return waypoint != nullptr ? waypoint->prevBeacon() : nullptr;
}
Vector Facade_relativePosition(Entity* entity) {
  if (entity == nullptr) return {};
  return entity->relativePosition();
}
void Facade_removeFromLinkedLists(Entity* entity) {
  if (entity == nullptr) return;
  entity->removeFromLinkedLists();
}
Entity* Facade_rootShipEntity(Entity* entity) {
  if (entity == nullptr) return {};
  return entity->rootShipEntity();
}
OOScanClass Facade_scanClass(Entity* entity) {
  if (entity == nullptr) return {};
  return entity->getScanClass();
}
std::size_t Facade_sessionID(Entity* entity) {
  if (entity == nullptr) return {};
  return entity->sessionID();
}
GLfloat Facade_spawnTime(Entity* entity) {
  if (entity == nullptr) return {};
  return entity->getSpawnTime();
}
double Facade_speed(Entity* entity) {
  if (entity == nullptr) return {};
  return entity->speed();
}
OOEntityStatus Facade_status(Entity* entity) {
  if (entity == nullptr) return {};
  return entity->status();
}
Entity* Facade_superShaderBindingTarget(
    Entity* entity)  // the parent's C++ entity
{
  if (entity == nullptr) return {};
  return entity->superShaderBindingTarget();
}
Vector Facade_terminatorThresholdVector(Entity* entity) {
  if (entity == nullptr) return {};
  OOPlanetEntity* planet = dynamic_cast<OOPlanetEntity*>(entity);
  return planet != nullptr ? planet->terminatorThresholdVector() : kZeroVector;
}
void Facade_throwSparks(Entity* entity) {
  if (entity == nullptr) return;
  entity->throwSparks();
}
bool Facade_throwingSparks(Entity* entity) {
  if (entity == nullptr) return {};
  return entity->throwingSparks();
}
GLfloat Facade_timeElapsedSinceSpawn(Entity* entity) {
  if (entity == nullptr) return {};
  return entity->timeElapsedSinceSpawn();
}
OOUniversalID Facade_universalID(Entity* entity) {
  if (entity == nullptr) return {};
  return entity->getUniversalID();
}
GLfloat Facade_universalTime(Entity* entity) {
  if (entity == nullptr) return {};
  return entity->universalTime();
}
void Facade_updateCameraRelativePosition(Entity* entity) {
  if (entity == nullptr) return;
  entity->updateCameraRelativePosition();
}
void Facade_updateLinkedLists(Entity* entity) {
  if (entity == nullptr) return;
  entity->updateLinkedLists();
}
bool Facade_validForAddToUniverse(Entity* entity) {
  if (entity == nullptr) return {};
  return entity->validForAddToUniverse();
}
Vector Facade_velocity(Entity* entity) {
  if (entity == nullptr) return {};
  return entity->getVelocity();
}
void Facade_warnAboutHostiles(Entity* entity) {
  if (entity == nullptr) return;
  entity->warnAboutHostiles();
}
void Facade_wasAddedToUniverse(Entity* entity) {
  if (entity == nullptr) return;
  entity->wasAddedToUniverse();
}
void Facade_wasRemovedFromUniverse(Entity* entity) {
  if (entity == nullptr) return;
  entity->wasRemovedFromUniverse();
}
double Facade_zeroDistance(Entity* entity) {
  if (entity == nullptr) return {};
  return entity->zeroDistance();
}

const OOEntityFacadeRow kOOEntityFacadeRows[] = {
    {"absolutePositionForSubentity", nullptr, nullptr},
    {"addToLinkedLists", nullptr,
     &OOEntityByNameTyped<&Facade_addToLinkedLists>},
    {"airColorAsVector", &AnswersPlanet,
     &OOEntityByNameTyped<&Facade_airColorAsVector>},
    {"airColorMixRatio", &AnswersPlanet,
     &OOEntityByNameTyped<&Facade_airColorMixRatio>},
    {"airDensity", &AnswersPlanet, &OOEntityByNameTyped<&Facade_airDensity>},
    {"beaconCode", &AnswersBeacon, nullptr},
    {"beaconDrawable", &AnswersBeacon,
     &OOEntityByNameTyped<&Facade_beaconDrawable>},
    {"beaconLabel", &AnswersBeacon, nullptr},
    {"boundingBox", nullptr, nullptr},
    {"camZeroDistance", nullptr, &OOEntityByNameTyped<&Facade_camZeroDistance>},
    {"cameraRangeBack", nullptr, &OOEntityByNameTyped<&Facade_cameraRangeBack>},
    {"cameraRangeFront", nullptr,
     &OOEntityByNameTyped<&Facade_cameraRangeFront>},
    {"cameraRelativePosition", nullptr,
     &OOEntityByNameTyped<&Facade_cameraRelativePosition>},
    {"canCollide", nullptr, &OOEntityByNameTyped<&Facade_canCollide>},
    {"collisionRadius", nullptr, &OOEntityByNameTyped<&Facade_collisionRadius>},
#ifdef OO_DEBUG_MONITOR_ENABLED
    {"cxx_allTextures", nullptr, nullptr},
#endif
    {"cxx_collidingEntities", nullptr, nullptr},
    {"cxx_description", nullptr, nullptr},
    {"cxx_descriptionComponents", nullptr, nullptr},
    {"cxx_oo_jsClassName", nullptr, nullptr},
    {"deleteJSSelf", nullptr, &OOEntityByNameTyped<&Facade_deleteJSSelf>},
#ifdef OO_DEBUG_MONITOR_ENABLED
    {"descriptionForObjDump", nullptr, nullptr},
#endif
#ifdef OO_DEBUG_MONITOR_ENABLED
    {"descriptionForObjDumpBasic", nullptr, nullptr},
#endif
    {"distanceTravelled", nullptr,
     &OOEntityByNameTyped<&Facade_distanceTravelled>},
    {"drawRotationMatrix", nullptr, nullptr},
    {"drawTransformationMatrix", nullptr, nullptr},
    {"dumpSelfState", nullptr, &OOEntityByNameTyped<&Facade_dumpSelfState>},
    {"dumpState", nullptr, &OOEntityByNameTyped<&Facade_dumpState>},
    {"energy", nullptr, &OOEntityByNameTyped<&Facade_energy>},
    {"findCollisionRadius", nullptr,
     &OOEntityByNameTyped<&Facade_findCollisionRadius>},
    {"fogUniform", nullptr, &OOEntityByNameTyped<&Facade_fogUniform>},
    {"frustumRadius", nullptr, &OOEntityByNameTyped<&Facade_frustumRadius>},
    {"illuminationColorAsVector", &AnswersPlanet,
     &OOEntityByNameTyped<&Facade_illuminationColorAsVector>},
    {"isBeacon", &AnswersBeacon, &OOEntityByNameTyped<&Facade_isBeacon>},
    {"isCascadeWeapon", nullptr, &OOEntityByNameTyped<&Facade_isCascadeWeapon>},
    {"isDock", nullptr, &OOEntityByNameTyped<&Facade_isDock>},
    {"isEffect", nullptr, &OOEntityByNameTyped<&Facade_isEffect>},
    {"isImmuneToBreakPatternHide", nullptr,
     &OOEntityByNameTyped<&Facade_isImmuneToBreakPatternHide>},
    {"isInSpace", nullptr, &OOEntityByNameTyped<&Facade_isInSpace>},
    {"isJammingScanning", &AnswersBeacon,
     &OOEntityByNameTyped<&Facade_isJammingScanning>},
    {"isPlanet", nullptr, &OOEntityByNameTyped<&Facade_isPlanet>},
    {"isPlayer", nullptr, &OOEntityByNameTyped<&Facade_isPlayer>},
    {"isShip", nullptr, &OOEntityByNameTyped<&Facade_isShip>},
    {"isSky", nullptr, &OOEntityByNameTyped<&Facade_isSky>},
    {"isStation", nullptr, &OOEntityByNameTyped<&Facade_isStation>},
    {"isStellarObject", nullptr, &OOEntityByNameTyped<&Facade_isStellarObject>},
    {"isSubEntity", nullptr, &OOEntityByNameTyped<&Facade_isSubEntity>},
    {"isSun", nullptr, &OOEntityByNameTyped<&Facade_isSun>},
    {"isSunlit", nullptr, &OOEntityByNameTyped<&Facade_isSunlit>},
    {"isVisible", nullptr, &OOEntityByNameTyped<&Facade_isVisible>},
    {"isVisibleToScripts", nullptr,
     &OOEntityByNameTyped<&Facade_isVisibleToScripts>},
    {"isVisualEffect", nullptr, &OOEntityByNameTyped<&Facade_isVisualEffect>},
    {"isWaypoint", nullptr, &OOEntityByNameTyped<&Facade_isWaypoint>},
    {"isWormhole", nullptr, &OOEntityByNameTyped<&Facade_isWormhole>},
    {"lastDrawCounter", nullptr, &OOEntityByNameTyped<&Facade_lastDrawCounter>},
    {"mass", nullptr, &OOEntityByNameTyped<&Facade_mass>},
    {"maxEnergy", nullptr, &OOEntityByNameTyped<&Facade_maxEnergy>},
    {"nextBeacon", &AnswersBeacon, &OOEntityByNameTyped<&Facade_nextBeacon>},
    {"normalOrientation", nullptr,
     &OOEntityByNameTyped<&Facade_normalOrientation>},
    {"orientation", nullptr, &OOEntityByNameTyped<&Facade_orientation>},
    {"orientationChanged", nullptr,
     &OOEntityByNameTyped<&Facade_orientationChanged>},
    {"owner", nullptr, &OOEntityByNameTyped<&Facade_owner>},
    {"parentEntity", nullptr, &OOEntityByNameTyped<&Facade_parentEntity>},
    {"position", nullptr, nullptr},
    {"prevBeacon", &AnswersBeacon, &OOEntityByNameTyped<&Facade_prevBeacon>},
    {"relativePosition", nullptr,
     &OOEntityByNameTyped<&Facade_relativePosition>},
    {"removeFromLinkedLists", nullptr,
     &OOEntityByNameTyped<&Facade_removeFromLinkedLists>},
    {"rootShipEntity", nullptr, &OOEntityByNameTyped<&Facade_rootShipEntity>},
    {"rotationMatrix", nullptr, nullptr},
    {"scanClass", nullptr, &OOEntityByNameTyped<&Facade_scanClass>},
    {"sessionID", nullptr, &OOEntityByNameTyped<&Facade_sessionID>},
    {"spawnTime", nullptr, &OOEntityByNameTyped<&Facade_spawnTime>},
    {"speed", nullptr, &OOEntityByNameTyped<&Facade_speed>},
    {"status", nullptr, &OOEntityByNameTyped<&Facade_status>},
    {"superShaderBindingTarget", nullptr,
     &OOEntityByNameTyped<&Facade_superShaderBindingTarget>},
    {"terminatorThresholdVector", &AnswersPlanet,
     &OOEntityByNameTyped<&Facade_terminatorThresholdVector>},
    {"throwSparks", nullptr, &OOEntityByNameTyped<&Facade_throwSparks>},
    {"throwingSparks", nullptr, &OOEntityByNameTyped<&Facade_throwingSparks>},
    {"timeElapsedSinceSpawn", nullptr,
     &OOEntityByNameTyped<&Facade_timeElapsedSinceSpawn>},
    {"transformationMatrix", nullptr, nullptr},
    {"universalID", nullptr, &OOEntityByNameTyped<&Facade_universalID>},
    {"universalTime", nullptr, &OOEntityByNameTyped<&Facade_universalTime>},
    {"updateCameraRelativePosition", nullptr,
     &OOEntityByNameTyped<&Facade_updateCameraRelativePosition>},
    {"updateLinkedLists", nullptr,
     &OOEntityByNameTyped<&Facade_updateLinkedLists>},
    {"validForAddToUniverse", nullptr,
     &OOEntityByNameTyped<&Facade_validForAddToUniverse>},
    {"velocity", nullptr, &OOEntityByNameTyped<&Facade_velocity>},
    {"warnAboutHostiles", nullptr,
     &OOEntityByNameTyped<&Facade_warnAboutHostiles>},
    {"wasAddedToUniverse", nullptr,
     &OOEntityByNameTyped<&Facade_wasAddedToUniverse>},
    {"wasRemovedFromUniverse", nullptr,
     &OOEntityByNameTyped<&Facade_wasRemovedFromUniverse>},
    {"zeroDistance", nullptr, &OOEntityByNameTyped<&Facade_zeroDistance>},
};

#include "OOEntityObjectNamesTable.h"

}  // namespace

std::span<const OOEntityObjectName> oo::EntityObjectNames() {
  return kOOEntityObjectNames;
}

const OOEntityObjectName* oo::EntityObjectNameNamed(const std::string& name) {
  static const std::unordered_map<std::string_view, const OOEntityObjectName*>
      names = [] {
        std::unordered_map<std::string_view, const OOEntityObjectName*> result;
        for (const OOEntityObjectName& row : kOOEntityObjectNames)
          result.emplace(row.name, &row);
        return result;
      }();
  auto found = names.find(name);
  return found != names.end() ? found->second : nullptr;
}

std::span<const OOEntityFacadeRow> oo::EntityFacadeRows() {
  return kOOEntityFacadeRows;
}

const OOEntityFacadeRow* oo::EntityFacadeRowNamed(const std::string& name) {
  static const std::unordered_map<std::string_view, const OOEntityFacadeRow*>
      rows = [] {
        std::unordered_map<std::string_view, const OOEntityFacadeRow*> result;
        for (const OOEntityFacadeRow& row : kOOEntityFacadeRows)
          result.emplace(row.name, &row);
        return result;
      }();
  auto found = rows.find(name);
  return found != rows.end() ? found->second : nullptr;
}

std::span<const OOEntityByNameRow> oo::EntityByNameRows() {
  return kOOEntityByNameRows;
}

const OOEntityByNameRow* oo::EntityByNameRowNamed(const std::string& name) {
  static const std::unordered_map<std::string_view, const OOEntityByNameRow*>
      rows = [] {
        std::unordered_map<std::string_view, const OOEntityByNameRow*> result;
        for (const OOEntityByNameRow& row : kOOEntityByNameRows)
          result.emplace(row.name, &row);
        return result;
      }();
  auto found = rows.find(name);
  return found != rows.end() ? found->second : nullptr;
}

// The name sets (the visual
// effect's first). A name only the effect's set holds is answered by the root
// for any entity; its body answers zero for any part
// but an effect's.
bool oo::EntityByNameRowApplies(const OOEntityByNameRow& row, Entity* entity) {
  if (entity == nullptr) return false;
  const OOByName flags = row.flags;
  if (oo::Any(flags & OOByName::kEffect) && EffectPart(entity) != nullptr)
    return true;
  if (!oo::Any(flags & (OOByName::kShip | OOByName::kPlayer |
                        OOByName::kStation | OOByName::kDock)))
    return true;
  if (oo::Any(flags & OOByName::kShip) && ShipPart(entity) != nullptr)
    return true;
  if (oo::Any(flags & OOByName::kPlayer) && oo::Any(flags & OOByName::kProxy) &&
      ProxyPart(entity) != nullptr)
    return true;
  if (oo::Any(flags & OOByName::kPlayer) && PlayerEntityPart(entity) != nullptr)
    return true;
  return (oo::Any(flags & OOByName::kStation) &&
          StationPart(entity) != nullptr) ||
         (oo::Any(flags & OOByName::kDock) && DockPart(entity) != nullptr);
}

bool oo::CallEntityByNameTyped(Entity* entity, const std::string& name,
                               OOEntityByNameValue& value) {
  if (entity == nullptr) return false;
  if (const OOEntityByNameRow* row = EntityByNameRowNamed(name)) {
    if (row->typed == nullptr || !EntityByNameRowApplies(*row, entity))
      return false;
    row->typed(entity, value);
    return true;
  }
  // A root-entity row: the method's body, for an entity that answers it.
  const OOEntityFacadeRow* facade = EntityFacadeRowNamed(name);
  if (facade == nullptr || facade->typed == nullptr ||
      (facade->answers != nullptr && !facade->answers(entity)))
    return false;
  facade->typed(entity, value);
  return true;
}

namespace {

enum class Kind : std::uint8_t {
  Void,    // a void result, or a scalar result the call ignores
  PList,   // an oo::PList result
  Object,  // an object result, ignored
  Unsupported
};

// Classifies a method's return type encoding as the Objective-C dispatcher did.
Kind ResultKind(std::string_view encoding) {
  std::string_view type = encoding;
  while (!type.empty() && std::string_view("rnNoORV").find(type.front()) !=
                              std::string_view::npos)
    type.remove_prefix(1);
  if (type == "v") return Kind::Void;
  if (type == "@") return Kind::Object;
  if (encoding == kOOTypeEncoding<oo::PList>) return Kind::PList;
  if (type.size() == 1 &&
      std::string_view("cCsSiIlLqQfdB").find(type.front()) !=
          std::string_view::npos)
    return Kind::Void;
  return Kind::Unsupported;
}

// The tabled row the name names, if it applies to the entity; null for any
// other name.
const OOEntityByNameRow* ApplyingRow(Entity* entity, const std::string& name) {
  const OOEntityByNameRow* row = oo::EntityByNameRowNamed(name);
  return (row != nullptr && oo::EntityByNameRowApplies(*row, entity)) ? row
                                                                      : nullptr;
}

// The row's call with the argument, if OOCallByName would make it (its usable
// signatures); none if the signature is unusable.
std::optional<oo::PList> CallRow(const OOEntityByNameRow& row, Entity* entity,
                                 const std::string* string,
                                 const oo::PList* plist) {
  const Kind result = ResultKind(row.result);
  const bool hasArgument = (string != nullptr || plist != nullptr);
  if (hasArgument != (row.argument != OOEntityByNameArgument::None) ||
      result == Kind::Unsupported)
    return std::nullopt;

  // A string reaches a PList parameter as a string PList; a PList reaches a
  // string parameter only when it is a string.
  oo::PList stringAsPList;
  if (row.argument == OOEntityByNameArgument::String && plist != nullptr) {
    string = plist->getIf<std::string>();
    if (string == nullptr) return std::nullopt;
  }
  if (row.argument == OOEntityByNameArgument::PList) {
    if (result != Kind::Void && result != Kind::Object) return std::nullopt;
    if (string != nullptr) {
      stringAsPList = oo::PList(*string);
      plist = &stringAsPList;
    }
  }

  oo::PList answer = row.call(entity, string, plist);
  // only a PList result is the call's result; a void, scalar or object result
  // is ignored
  return (result == Kind::PList) ? std::move(answer) : oo::PList();
}

/*	The class OOCallByName's lines name: the entity's object's, of class
 * Entity (not asked).
 */
std::string_view ObjectClassName(Entity*) { return "Entity"; }

/*	The line OOCallByName logged for a method whose signature the call
   cannot use (LogBadSignature), for a tabled name that applies:
   the class of the entity's object, as the category method was its; the type
   encoding is the row's, @encode() of the result, of self and _cmd and of the
   argument, without the frame offsets the method's encoding had.
*/
void LogBadSignature(Entity* entity, const OOEntityByNameRow& row) {
  std::string encoding = std::string(row.result) + kOOTypeEncoding<OOObjCId> +
                         kOOTypeEncoding<OOObjCSelector>;
  if (row.argument == OOEntityByNameArgument::String)
    encoding += kOOTypeEncoding<const std::string&>;
  if (row.argument == OOEntityByNameArgument::PList)
    encoding += kOOTypeEncoding<const oo::PList&>;
  OO_LOG_ERR(
      "callByName.badSignature",
      "-[{} {}] has no signature a by-name call can use (type encoding {}).",
      ObjectClassName(entity), row.name, encoding);
}

// A tabled name that applies, called or logged; none for any other name (the
// object's path).
std::optional<oo::PList> CallTabled(Entity* entity, const std::string& name,
                                    const std::string* string,
                                    const oo::PList* plist) {
  const OOEntityByNameRow* row = ApplyingRow(entity, name);
  if (row == nullptr) return std::nullopt;
  if (std::optional<oo::PList> result = CallRow(*row, entity, string, plist))
    return result;
  LogBadSignature(entity, *row);
  return oo::PList();
}

// The name, if the entity's object answered it for this entity; else null.
const OOEntityObjectName* AnsweredObjectName(Entity* entity,
                                             const std::string& name) {
  const OOEntityObjectName* row = oo::EntityObjectNameNamed(name);
  return (row != nullptr && (row->answers == nullptr || row->answers(entity)))
             ? row
             : nullptr;
}

/*	A C++ entity's name outside the by-name table: a root-entity row's
   method with no argument that the call called is the row's body (its result
   ignored); any other name the object answers is logged (the method's type
   encoding), a root-class or lifetime method included, which is never called;
   any other name does not respond. The texts are the Objective-C dispatcher's
   (its unknown-selector and bad-signature lines).
*/
oo::PList CallObjectName(Entity* entity, const std::string& name,
                         bool hasArgument) {
  const OOEntityObjectName* row = AnsweredObjectName(entity, name);
  if (row == nullptr) {
    OO_LOG_ERR("callByName.unknownSelector", "{} does not respond to {}.",
               ObjectClassName(entity), name);
    return oo::PList();
  }
  if (row->kind == OOEntityObjectNameKind::kCalled && !hasArgument) {
    const OOEntityFacadeRow* facade = oo::EntityFacadeRowNamed(name);
    if (facade != nullptr && facade->typed != nullptr) {
      OOEntityByNameValue ignored;
      facade->typed(entity, ignored);
      return oo::PList();
    }
  }
  OO_LOG_ERR(
      "callByName.badSignature",
      "-[{} {}] has no signature a by-name call can use (type encoding {}).",
      ObjectClassName(entity), name, row->encoding);
  return oo::PList();
}

}  // namespace

bool oo::EntityRespondsToName(Entity* entity, const std::string& name) {
  if (entity == nullptr) return false;
  if (const OOEntityByNameRow* row = EntityByNameRowNamed(name))
    return EntityByNameRowApplies(*row, entity);
  // A root-entity row's answer.
  if (const OOEntityFacadeRow* facade = EntityFacadeRowNamed(name))
    return facade->answers == nullptr || facade->answers(entity);
  // Any other name the entity's object answered: the object is not asked.
  return AnsweredObjectName(entity, name) != nullptr;
}

oo::PList oo::CallEntityByName(Entity* entity, const std::string& name) {
  if (entity == nullptr) return PList();
  if (std::optional<PList> result = CallTabled(entity, name, nullptr, nullptr))
    return *result;
  return CallObjectName(entity, name, false);
}

oo::PList oo::CallEntityByName(Entity* entity, const std::string& name,
                               const std::string& argument) {
  if (entity == nullptr) return PList();
  if (std::optional<PList> result =
          CallTabled(entity, name, &argument, nullptr))
    return *result;
  return CallObjectName(entity, name, true);
}

oo::PList oo::CallEntityByName(Entity* entity, const std::string& name,
                               const PList& argument) {
  if (entity == nullptr) return PList();
  if (std::optional<PList> result =
          CallTabled(entity, name, nullptr, &argument))
    return *result;
  return CallObjectName(entity, name, true);
}

void oo::ScheduleEntityCall(Entity* entity, void (*call)(Entity* entity),
                            double delay) {
  if (entity == nullptr || call == nullptr) return;
  // The call holds the entity, so it keeps the entity alive until it has run.
  oo::Ref<Entity> held(entity);
  OOScheduleDeferredCall([held, call]() { call(held.get()); }, delay);
}
