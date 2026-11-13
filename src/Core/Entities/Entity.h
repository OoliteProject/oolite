/*

Entity.h

Base class for entities, i.e. drawable world objects.

The C++ entity is its own identity and owns itself (oo::RefCounted; its last
release runs willDispose()). EntityHelpers.h,
imported at the end of this header, has the questions asked of an entity.

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

#pragma once

#include <quickjs.h>

#include <algorithm>
#include <chrono>
#include <condition_variable>
#include <cstddef>
#include <cstdint>
#include <functional>
#include <map>
#include <memory>
#include <mutex>
#include <optional>
#include <set>
#include <string>
#include <string_view>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <vector>

#include "CollisionRegion.h"
#include "EntityVirtualMembers.h"  // the virtual members
#include "OOCacheManager.h"
#include "OOColor.h"
#include "OOEntityHold.h"  // the owning entity lists
#include "OOFoundation.h"
#include "OOJSPrivateObject.h"
#include "OOMaths.h"
#include "OOTypes.h"
#include "oofnd/Ref.hpp"

class Entity;
class Universe;
#include "OOTexture.h"  // allTextures() answers oo::Ref<OOTexture>, which needs the class
class OOVisualEffectEntity;
class ShipEntity;

#ifdef OO_DEBUG_MONITOR_ENABLED

extern uint32_t gLiveEntityCount;
extern size_t gTotalEntityMemory;

#endif

#define NO_DRAW_DISTANCE_FACTOR 1024.0
#define ABSOLUTE_NO_DRAW_DISTANCE2 \
  (2500.0 * 2500.0 * NO_DRAW_DISTANCE_FACTOR * NO_DRAW_DISTANCE_FACTOR)
// ie. the furthest away thing we can draw is at 1280km (a 2.5km wide object
// would disappear at that range)

#define SCANNER_MAX_RANGE 25600.0
#define SCANNER_MAX_RANGE2 655360000.0

#define CLOSE_COLLISION_CHECK_MAX_RANGE2 1000000000.0

// OOEntityStatus, OOScanClass and their defaults (a plain header).
#include "OOEntityEnums.h"

/*	The base object for ships, stations, anything actually.

        Data members are public: the game reads them directly (ent->position). A
   getter with a data member's name is get + the name (position is read with
   getPosition()). The members that subclasses override are virtual.
*/
class Entity : public oo::RefCounted, public ::OOJSPrivateObject {
 public:
  Entity();

  // The constructor runs it, and PlayerEntity's deferred initialisation runs it
  // again.
  void init();

  // willDispose() zeroes the weak references to the entity.
  using oo::RefCounted::dropWeakReferences;

  /*	The entity's object: it "has" one from the creator that made it
          (oo::MadeEntity(), oo::NewShipObject(), ...) until its last release
     begins. Holds, retains, descriptions and nodes of an entity without one
     answer as nil (EntityHelpers.h, OOEntityHold.h).
  */
  bool hasObject() const noexcept { return _hasObject && !_disposing; }
  void setMadeWithObject() noexcept {
    _hasObject = true;
  }  // the creators' (oo::MadeEntity())

  // Teardown for an entity that had its object: the last release runs it
  // (oo::RefCounted::willDispose()).
  void willDispose() noexcept override;

  // The virtual members, declared once in EntityVirtualMembers.h in this order,
  // so that a narrow test's stand-in for the class has the same vtable
  // (tests/unit/core/EntityStandIn.h).
  OO_ENTITY_VIRTUAL_MEMBERS(;, ;)
  OO_ENTITY_DEBUG_VIRTUAL_MEMBERS(;, ;)

  // The session in which the entity was created.
  // sessionID(): virtual, in OO_ENTITY_VIRTUAL_MEMBERS (EntityVirtualMembers.h)

  bool getIsShip();
  // isDock(): virtual, in OO_ENTITY_VIRTUAL_MEMBERS (EntityVirtualMembers.h)
  bool getIsStation();
  bool getIsSubEntity();
  bool getIsPlayer();
  // isPlanet(): virtual, in OO_ENTITY_VIRTUAL_MEMBERS (EntityVirtualMembers.h)
  // isSun(): virtual, in OO_ENTITY_VIRTUAL_MEMBERS (EntityVirtualMembers.h)
  bool getIsSunlit();
  bool isStellarObject();
  // isSky(): virtual, in OO_ENTITY_VIRTUAL_MEMBERS (EntityVirtualMembers.h)
  bool getIsWormhole();
  // isEffect(): virtual, in OO_ENTITY_VIRTUAL_MEMBERS (EntityVirtualMembers.h)
  // getIsVisualEffect(): virtual, in OO_ENTITY_VIRTUAL_MEMBERS
  // (EntityVirtualMembers.h) isWaypoint(): virtual, in
  // OO_ENTITY_VIRTUAL_MEMBERS (EntityVirtualMembers.h)

  // validForAddToUniverse(): virtual, in OO_ENTITY_VIRTUAL_MEMBERS
  // (EntityVirtualMembers.h)
  void addToLinkedLists();
  void removeFromLinkedLists();

  void updateLinkedLists();

  // wasAddedToUniverse(): virtual, in OO_ENTITY_VIRTUAL_MEMBERS
  // (EntityVirtualMembers.h) wasRemovedFromUniverse(): virtual, in
  // OO_ENTITY_VIRTUAL_MEMBERS (EntityVirtualMembers.h)

  // warnAboutHostiles(): virtual, in OO_ENTITY_VIRTUAL_MEMBERS
  // (EntityVirtualMembers.h)

  CollisionRegion* getCollisionRegion();
  void setCollisionRegion(CollisionRegion* region);

  void setUniversalID(OOUniversalID uid);
  OOUniversalID getUniversalID();

  bool throwingSparks();
  void setThrowSparks(bool value);
  // throwSparks(): virtual, in OO_ENTITY_VIRTUAL_MEMBERS
  // (EntityVirtualMembers.h)

  // setOwner(): virtual, in OO_ENTITY_VIRTUAL_MEMBERS (EntityVirtualMembers.h)
  Entity* owner();  // the owner while it has its object, null for none or once
                    // it has gone (what -owner answered the object of, +0)
  Entity* ownerEntity();     // the owner's C++ entity, null once it has gone
  Entity* parentEntity();    // owner if self is subentity of owner, otherwise
                             // null (the C++ entity).
  Entity* rootShipEntity();  // like parentEntity, but recursive.
  Entity* superShaderBindingTarget();  // the parent entity, +0 (what
                                       // -superShaderBindingTarget answered the
                                       // object of)

  // setPosition(): virtual, in OO_ENTITY_VIRTUAL_MEMBERS
  // (EntityVirtualMembers.h)
  void setPositionX(OOHPScalar x, OOHPScalar y, OOHPScalar z);
  HPVector getPosition();
  Vector getCameraRelativePosition();
  // cameraRangeFront(): virtual, in OO_ENTITY_VIRTUAL_MEMBERS
  // (EntityVirtualMembers.h) cameraRangeBack(): virtual, in
  // OO_ENTITY_VIRTUAL_MEMBERS (EntityVirtualMembers.h)

  // Exposed to uniform bindings.
  Vector relativePosition();

  // updateCameraRelativePosition(): virtual, in OO_ENTITY_VIRTUAL_MEMBERS
  // (EntityVirtualMembers.h) gets a low-position relative vector
  Vector vectorTo(Entity* entity);

  HPVector absolutePositionForSubentity();
  HPVector absolutePositionForSubentityOffset(HPVector offset);

  double zeroDistance();
  double camZeroDistance();
  // compareZeroDistance(): virtual, in OO_ENTITY_VIRTUAL_MEMBERS
  // (EntityVirtualMembers.h)

  BoundingBox getBoundingBox();

  GLfloat getMass();

  Quaternion getOrientation();
  // setOrientation(): virtual, in OO_ENTITY_VIRTUAL_MEMBERS
  // (EntityVirtualMembers.h) normalOrientation(): virtual, in
  // OO_ENTITY_VIRTUAL_MEMBERS (EntityVirtualMembers.h) setNormalOrientation():
  // virtual, in OO_ENTITY_VIRTUAL_MEMBERS (EntityVirtualMembers.h)
  // orientationChanged(): virtual, in OO_ENTITY_VIRTUAL_MEMBERS
  // (EntityVirtualMembers.h)

  void setVelocity(Vector vel);
  // getVelocity(): virtual, in OO_ENTITY_VIRTUAL_MEMBERS
  // (EntityVirtualMembers.h)
  double speed();

  GLfloat getDistanceTravelled();
  void setDistanceTravelled(GLfloat value);

  // setStatus(): virtual, in OO_ENTITY_VIRTUAL_MEMBERS (EntityVirtualMembers.h)
  OOEntityStatus status();

  void setScanClass(OOScanClass sClass);
  // getScanClass(): virtual, in OO_ENTITY_VIRTUAL_MEMBERS
  // (EntityVirtualMembers.h)

  void setEnergy(GLfloat amount);
  GLfloat getEnergy();

  void setMaxEnergy(GLfloat amount);
  GLfloat getMaxEnergy();

  // applyRoll(): virtual, in OO_ENTITY_VIRTUAL_MEMBERS (EntityVirtualMembers.h)
  // applyRoll(): virtual, in OO_ENTITY_VIRTUAL_MEMBERS (EntityVirtualMembers.h)
  // moveForward(): virtual, in OO_ENTITY_VIRTUAL_MEMBERS
  // (EntityVirtualMembers.h)

  OOMatrix rotationMatrix();
  // drawRotationMatrix(): virtual, in OO_ENTITY_VIRTUAL_MEMBERS
  // (EntityVirtualMembers.h)
  OOMatrix transformationMatrix();
  // drawTransformationMatrix(): virtual, in OO_ENTITY_VIRTUAL_MEMBERS
  // (EntityVirtualMembers.h)

  // canCollide(): virtual, in OO_ENTITY_VIRTUAL_MEMBERS
  // (EntityVirtualMembers.h) collisionRadius(): virtual, in
  // OO_ENTITY_VIRTUAL_MEMBERS (EntityVirtualMembers.h) frustumRadius():
  // virtual, in OO_ENTITY_VIRTUAL_MEMBERS (EntityVirtualMembers.h)
  void setCollisionRadius(GLfloat amount);
  std::vector<oo::EntityHold>* getCollidingEntities();  // the live list

  // update(): virtual, in OO_ENTITY_VIRTUAL_MEMBERS (EntityVirtualMembers.h)

  void applyVelocity(OOTimeDelta delta_t);
  // checkCloseCollisionWith(): virtual, in OO_ENTITY_VIRTUAL_MEMBERS
  // (EntityVirtualMembers.h)

  // takeEnergyDamage(): virtual, in OO_ENTITY_VIRTUAL_MEMBERS
  // (EntityVirtualMembers.h)

  void dumpState();  // General "describe situtation verbosely in log" command.
  // dumpSelfState(): virtual, in OO_ENTITY_VIRTUAL_MEMBERS
  // (EntityVirtualMembers.h)

  // subEntityReallyDied(): virtual, in OO_ENTITY_VIRTUAL_MEMBERS
  // (EntityVirtualMembers.h)

  std::size_t getLastDrawCounter();
  void setLastDrawCounter(std::size_t drawCounter);

  // Subclass repsonsibilities
  // findCollisionRadius(): virtual, in OO_ENTITY_VIRTUAL_MEMBERS
  // (EntityVirtualMembers.h) drawImmediate(): virtual, in
  // OO_ENTITY_VIRTUAL_MEMBERS (EntityVirtualMembers.h) isVisible(): virtual, in
  // OO_ENTITY_VIRTUAL_MEMBERS (EntityVirtualMembers.h)
  bool isInSpace();
  bool getIsImmuneToBreakPatternHide();

  // For shader bindings.
  GLfloat universalTime();
  GLfloat getSpawnTime();
  GLfloat timeElapsedSinceSpawn();
  void setAtmosphereFogging(OOColor* fogging);
  std::shared_ptr<OOColor> fogUniform();

  // The category ShaderBindings (EntityShaderBindings.cpp): more values the
  // shader uniforms bind to by name, through the entities' shader binding
  // member table (EntityShaderBindings.cpp).
  GLfloat clock();
  unsigned pseudoFixedD100();
  unsigned pseudoFixedD256();
  unsigned systemGovernment();
  unsigned systemEconomy();
  unsigned systemTechLevel();
  unsigned systemPopulation();
  unsigned systemProductivity();

  // What "%@" prints between the braces of <Class 0x...>{...}
  // (OODescription.h). descriptionComponents(): virtual, in
  // OO_ENTITY_VIRTUAL_MEMBERS (EntityVirtualMembers.h)

  /*	The class questions the engine asks an entity: a C++ entity answers for
     its class by overriding them (EntityOOJavaScriptExtensions.h). The engine
     asks the C++ entity (OOJSEntityIsVisibleToScripts(),
     OOJSEntityJSClassName(), OOJSEntityJSClassID()).
  */
  // jsClassID(): virtual, in OO_ENTITY_VIRTUAL_MEMBERS
  // (EntityVirtualMembers.h) jsClassName(): virtual, in
  // OO_ENTITY_VIRTUAL_MEMBERS (EntityVirtualMembers.h) isVisibleToScripts():
  // virtual, in OO_ENTITY_VIRTUAL_MEMBERS (EntityVirtualMembers.h)

  /*	The entity's JS glue (OOJSPrivateObject):
          the engine wraps a C++ entity with
     OOJSValueFromCxxObject(). Its JS object's private slot holds an
     OOJSEntityHolder (OOJSEntity.h), a weak reference to the entity. The bodies
     are EntityOOJavaScriptExtensions.cpp's. deleteJSSelf() is the engine's
     reset; destruction calls it.
  */
  // jsValueInContext(): virtual, in OO_ENTITY_VIRTUAL_MEMBERS
  // (EntityVirtualMembers.h) clearJSSelf(): virtual, in
  // OO_ENTITY_VIRTUAL_MEMBERS (EntityVirtualMembers.h) jsDescription():
  // virtual, in OO_ENTITY_VIRTUAL_MEMBERS (EntityVirtualMembers.h)
  void deleteJSSelf();

#ifdef OO_DEBUG_MONITOR_ENABLED
  std::optional<std::string> descriptionForObjDumpBasic();
  // descriptionForObjDump(): virtual, in OO_ENTITY_DEBUG_VIRTUAL_MEMBERS
  // (EntityVirtualMembers.h)

  // allTextures(): virtual, in OO_ENTITY_DEBUG_VIRTUAL_MEMBERS
  // (EntityVirtualMembers.h)
#endif

  // the base object for ships/stations/anything actually
  //////////////////////////////////////////////////////
  //
  // @public variables:
  //
  // we forego encapsulation for some variables in order to
  // lose the overheads of accessor methods...
  //
  OOUniversalID universalID = {};  // used to reference the entity

  unsigned isShip : 1 = 0, isStation : 1 = 0, isPlayer : 1 = 0,
                    isWormhole : 1 = 0, isSubEntity : 1 = 0, hasMoved : 1 = 0,
                    hasRotated : 1 = 0, hasCollided : 1 = 0, isSunlit : 1 = 0,
                    collisionTestFilter : 2 = 0, throw_sparks : 1 = 0,
                    isImmuneToBreakPatternHide : 1 = 0,
                    isExplicitlyNotMainStation : 1 = 0, isVisualEffect : 1 = 0;

  OOScanClass scanClass = {};

  GLfloat zero_distance = {};
  GLfloat cam_zero_distance = {};
  GLfloat no_draw_distance = {};  // 10 km initially
  GLfloat collision_radius = {};
  HPVector position = {};  // use high-precision vectors for global position
  Vector cameraRelativePosition = {};
  Quaternion orientation = {};
  std::shared_ptr<OOColor> atmosphereFogging;

  int zero_index = {};

  // Linked lists of entites, sorted by position on each (world) axis. Pointers
  // to other entities are their C++ parts, borrowed as the objects were.
  Entity *x_previous = {}, *x_next = {};
  Entity *y_previous = {}, *y_next = {};
  Entity *z_previous = {}, *z_next = {};

  Entity* collision_chain = {};

  OOUniversalID shadingEntityID = {};

  Entity* collider = {};

  oo::Ref<CollisionRegion> collisionRegion;  // initially nil - then maintained

  // Public: subclasses and the game read them.
  HPVector lastPosition = {};
  Quaternion lastOrientation = {};

  GLfloat distanceTravelled = {};  // set to zero initially

  OOMatrix rotMatrix = {};

  Vector velocity = {};

  GLfloat energy = {};
  GLfloat maxEnergy = {};

  BoundingBox boundingBox = {};
  GLfloat mass = {};

  std::vector<oo::EntityHold>
      collidingEntities;  // filled by CollisionRegion each frame

  OOTimeAbsolute spawnTime = {};

  JSValue _jsSelf = {};  // Zero-filled (not an object) until created; test with
                         // JS_IsObject().
  std::size_t lastDrawCounter = {};

 private:
  bool checkLinkedLists();

  bool _hasObject = false;  // made by a creator
  bool _disposing = false;  // in its last release

  std::size_t _sessionID = {};

  oo::WeakRef<Entity> _owner;  // the owner's C++ part
  OOEntityStatus _status = {};
};

namespace cxx {

/*	The subentity methods an owner calls when the subentity's
   C++ part adopts this interface: rescaleBy() and drawSubEntityImmediate().
*/
class OOSubEntityInterface {
 public:
  virtual ~OOSubEntityInterface() = default;

  virtual void rescaleBy(GLfloat factor) = 0;
  virtual void rescaleBy(GLfloat factor, bool writeToCache) = 0;
  virtual void drawSubEntityImmediate(bool immediate, bool translucent) = 0;
};

}  // namespace cxx

// C++ forms, defined in OOConstToString.cpp: std::string results (never nil),
// const std::string & parameters (nil arrived as "" and matched nothing: the
// defaults).
std::string cxx_OOStringFromEntityStatus(OOEntityStatus status);
OOEntityStatus cxx_OOEntityStatusFromString(const std::string& string);

std::string cxx_OOStringFromScanClass(OOScanClass scanClass);
OOScanClass cxx_OOScanClassFromString(const std::string& string);

/*	The entities' shader binding member table (EntityShaderBindings.cpp):
   the binding a uniform bound to the property name on this entity makes,
   reading the entity itself. False where no row has the name, the row does not
   apply to this entity, or its type is not bindable (as the selector path
   failed).
*/
struct OOShaderMemberBinding;  // OOShaderUniformMethodType.h
bool EntityShaderMemberBindingFor(Entity* entity, const char* property,
                                  OOShaderMemberBinding* outBinding);

#include "oofnd/PList.hpp"

namespace oo {

/*	An entity carried WEAKLY through plist data (the docking instructions'
   station, the collision-avoidance condition's primary target). The payload
   holds a weak reference to the C++ entity, which reads null once the entity is
   gone, so the node keeps nothing alive. Its JS value is the entity's,
   undefined once it has gone (OOJSValueFromPList).
*/
class EntityWeakPListForeign final : public PListForeign {
 public:
  explicit EntityWeakPListForeign(Entity* entity) : _entity(entity) {}
  Entity* entity() const noexcept { return _entity.get(); }
  std::string className() const override {
    return "OOWeakReference";
  }  // what the proxy's class was
  std::string description()
      const override;  // the entity's description, or <Dead OOWeakReference
                       // 0x...> (Entity.cpp)

 private:
  WeakRef<Entity> _entity;
};

// The entity's weak node; a null PList for null.
inline PList EntityWeakNode(Entity* entity) {
  if (entity == nullptr) return PList();
  return PList(PList::Object(makeRef<EntityWeakPListForeign>(entity)));
}

// The live C++ entity of a weak node; null once it has gone, and for any other
// node.
inline Entity* EntityInWeakNode(const PList& plist) {
  const PList::Object* node = plist.getIf<PList::Object>();
  if (node == nullptr) return nullptr;
  const auto* payload =
      dynamic_cast<const EntityWeakPListForeign*>(node->get());
  return payload != nullptr ? payload->entity() : nullptr;
}

}  // namespace oo

// The questions asked of an entity.
#include "EntityHelpers.h"
