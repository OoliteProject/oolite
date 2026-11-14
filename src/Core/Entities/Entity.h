/*

Entity.h

Base class for entities, i.e. drawable world objects.

C++20 since bead oo-bj8, the Entities pattern seam (proposed ADR-0056, amendment oo-bj8). The
class is cxx::Entity while Entity+ObjCBridge.h, imported at the end of this header, keeps the
Objective-C Entity: the facade its callers message, the base its unconverted subclasses
(ShipEntity, PlanetEntity, the effects, ...) derive from, and each entity's identity (the object
the universe, weak references and JavaScript hold). The entity's state lives here, in the C++
class. Unconverted code that read an ivar directly reads the member through the facade's one
ivar: ent->_cxxEntity->position, and _cxxEntity->position in an Objective-C subclass's method.
The bridge's deletion bead moves the class out of namespace cxx.

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

#import "CollisionRegion.h"
#import "OOCacheManager.h"
#import "OOColor.h"
#import "OOFoundation.h"
#import "OOMaths.h"
#import "OOTypes.h"
#import "OOWeakReference.h"

#include "oofnd/Ref.hpp"
#include "oofnd/StdLib.hpp"
#include "oofnd/objc/OOObjCRef.h"
#include <quickjs.h>

@class Universe, ShipEntity, OOVisualEffectEntity, OOTexture, Entity;

#ifdef OO_DEBUG_MONITOR_ENABLED

extern uint32_t gLiveEntityCount;
extern size_t gTotalEntityMemory;

#endif

#define NO_DRAW_DISTANCE_FACTOR 1024.0
#define ABSOLUTE_NO_DRAW_DISTANCE2 (2500.0 * 2500.0 * NO_DRAW_DISTANCE_FACTOR * NO_DRAW_DISTANCE_FACTOR)
// ie. the furthest away thing we can draw is at 1280km (a 2.5km wide object would disappear at that range)

#define SCANNER_MAX_RANGE 25600.0
#define SCANNER_MAX_RANGE2 655360000.0

#define CLOSE_COLLISION_CHECK_MAX_RANGE2 1000000000.0

// OOEntityStatus, OOScanClass and their defaults (bead oo-9ht.64: plain header).
#include "OOEntityEnums.h"

namespace cxx {

/*	The base object for ships, stations, anything actually.

        Data members that were @public or @protected ivars are public: the game reads them directly
        (ent->position), and Objective-C subclasses cannot be granted protected access to a C++
        class. A getter that had its ivar's name is get + the name (-position is getPosition(),
        amendment oo-862e), so the bodies, and the subclasses' reads, keep the names. The members
        that subclasses override are virtual (amendment oo-cwz item 2).
*/
class Entity : public oo::RefCounted {
public:
    Entity();

    // -init's body: the constructor runs it, and the facade runs it again when an initialised
    // entity is sent -init (PlayerEntity's deferred initialisation). Only then does it re-run.
    void init();

    // The session in which the entity was created.
    virtual NSUInteger sessionID();

    bool getIsShip();
    virtual bool isDock();
    bool getIsStation();
    bool getIsSubEntity();
    bool getIsPlayer();
    virtual bool isPlanet();
    virtual bool isSun();
    bool getIsSunlit();
    bool isStellarObject();
    virtual bool isSky();
    bool getIsWormhole();
    virtual bool isEffect();
    virtual bool getIsVisualEffect();
    virtual bool isWaypoint();

    virtual bool validForAddToUniverse();
    void addToLinkedLists();
    void removeFromLinkedLists();

    void updateLinkedLists();

    virtual void wasAddedToUniverse();
    virtual void wasRemovedFromUniverse();

    virtual void warnAboutHostiles();

    CollisionRegion* getCollisionRegion();
    void setCollisionRegion(CollisionRegion* region);

    void setUniversalID(OOUniversalID uid);
    OOUniversalID getUniversalID();

    bool throwingSparks();
    void setThrowSparks(bool value);
    virtual void throwSparks();

    virtual void setOwner(Entity* ent);
    id owner();
    ShipEntity* parentEntity(); // owner if self is subentity of owner, otherwise nil.
    ShipEntity* rootShipEntity(); // like parentEntity, but recursive.
    id<OOWeakReferenceSupport> superShaderBindingTarget();

    virtual void setPosition(HPVector posn);
    void setPositionX(OOHPScalar x, OOHPScalar y, OOHPScalar z);
    HPVector getPosition();
    Vector getCameraRelativePosition();
    virtual GLfloat cameraRangeFront();
    virtual GLfloat cameraRangeBack();

    // Exposed to uniform bindings.
    Vector relativePosition();

    virtual void updateCameraRelativePosition();
    // gets a low-position relative vector
    Vector vectorTo(Entity* entity);

    HPVector absolutePositionForSubentity();
    HPVector absolutePositionForSubentityOffset(HPVector offset);

    double zeroDistance();
    double camZeroDistance();
    virtual OOComparisonResult compareZeroDistance(Entity* otherEntity);

    BoundingBox getBoundingBox();

    GLfloat getMass();

    Quaternion getOrientation();
    virtual void setOrientation(Quaternion quat);
    virtual Quaternion normalOrientation(); // Historical wart: orientation.w is reversed for player; -normalOrientation corrects this.
    virtual void setNormalOrientation(Quaternion quat);
    virtual void orientationChanged();

    void setVelocity(Vector vel);
    virtual Vector getVelocity();
    double speed();

    GLfloat getDistanceTravelled();
    void setDistanceTravelled(GLfloat value);

    virtual void setStatus(OOEntityStatus stat);
    OOEntityStatus status();

    void setScanClass(OOScanClass sClass);
    virtual OOScanClass getScanClass();

    void setEnergy(GLfloat amount);
    GLfloat getEnergy();

    void setMaxEnergy(GLfloat amount);
    GLfloat getMaxEnergy();

    virtual void applyRoll(GLfloat roll, GLfloat climb);
    virtual void applyRoll(GLfloat roll, GLfloat climb, GLfloat yaw);
    virtual void moveForward(double amount);

    OOMatrix rotationMatrix();
    virtual OOMatrix drawRotationMatrix();
    OOMatrix transformationMatrix();
    virtual OOMatrix drawTransformationMatrix();

    virtual bool canCollide();
    virtual GLfloat collisionRadius();
    virtual GLfloat frustumRadius();
    void setCollisionRadius(GLfloat amount);
    std::vector<oo::ObjCRef<::Entity*>>* getCollidingEntities(); // the live list (ADR-0043 item 22)

    virtual void update(OOTimeDelta delta_t);

    void applyVelocity(OOTimeDelta delta_t);
    virtual bool checkCloseCollisionWith(Entity* other);

    virtual void takeEnergyDamage(double amount, Entity* ent, Entity* other, const std::string& weaponIdentifier);

    void dumpState(); // General "describe situtation verbosely in log" command.
    virtual void dumpSelfState(); // Subclasses should override this, not -dumpState, and call throught to super first.

    virtual void subEntityReallyDied(ShipEntity* sub);

    NSUInteger getLastDrawCounter();
    void setLastDrawCounter(NSUInteger drawCounter);

    // Subclass repsonsibilities
    virtual double findCollisionRadius();
    virtual void drawImmediate(bool immediate, bool translucent);
    virtual bool isVisible();
    bool isInSpace();
    bool getIsImmuneToBreakPatternHide();

    // For shader bindings.
    GLfloat universalTime();
    GLfloat getSpawnTime();
    GLfloat timeElapsedSinceSpawn();
    void setAtmosphereFogging(OOColor* fogging);
    oo::Ref<OOColor> fogUniform();

    // The category ShaderBindings (EntityShaderBindings.mm, bead oo-aeev; amendment oo-9fwb): more
    // values the shader uniforms bind to by name. The facade's category answers the selectors.
    GLfloat clock();
    unsigned pseudoFixedD100();
    unsigned pseudoFixedD256();
    unsigned systemGovernment();
    unsigned systemEconomy();
    unsigned systemTechLevel();
    unsigned systemPopulation();
    unsigned systemProductivity();

    // What "%@" prints between the braces of <Class 0x...>{...} (OODescription.h).
    virtual std::optional<std::string> descriptionComponents() const;

#ifdef OO_DEBUG_MONITOR_ENABLED
    std::optional<std::string> descriptionForObjDumpBasic();
    virtual std::optional<std::string> descriptionForObjDump();

    virtual std::vector<oo::ObjCRef<::OOTexture*>> allTextures();
#endif

    // the base object for ships/stations/anything actually
    //////////////////////////////////////////////////////
    //
    // @public variables:
    //
    // we forego encapsulation for some variables in order to
    // lose the overheads of Obj-C accessor methods...
    //
    OOUniversalID universalID = { }; // used to reference the entity

    unsigned isShip : 1 = 0,
                      isStation : 1 = 0,
                      isPlayer : 1 = 0,
                      isWormhole : 1 = 0,
                      isSubEntity : 1 = 0,
                      hasMoved : 1 = 0,
                      hasRotated : 1 = 0,
                      hasCollided : 1 = 0,
                      isSunlit : 1 = 0,
                      collisionTestFilter : 2 = 0,
                      throw_sparks : 1 = 0,
                      isImmuneToBreakPatternHide : 1 = 0,
                      isExplicitlyNotMainStation : 1 = 0,
                      isVisualEffect : 1 = 0;

    OOScanClass scanClass = { };

    GLfloat zero_distance = { };
    GLfloat cam_zero_distance = { };
    GLfloat no_draw_distance = { }; // 10 km initially
    GLfloat collision_radius = { };
    HPVector position = { }; // use high-precision vectors for global position
    Vector cameraRelativePosition = { };
    Quaternion orientation = { };
    oo::Ref<OOColor> atmosphereFogging;

    int zero_index = { };

    // Linked lists of entites, sorted by position on each (world) axis. Pointers to other entities
    // are their Objective-C objects, the entities' identity while any entity class is Objective-C.
    ::Entity *x_previous = { }, *x_next = { };
    ::Entity *y_previous = { }, *y_next = { };
    ::Entity *z_previous = { }, *z_next = { };

    ::Entity* collision_chain = { };

    OOUniversalID shadingEntityID = { };

    ::Entity* collider = { };

    oo::Ref<CollisionRegion> collisionRegion; // initially nil - then maintained

    // @protected in Objective-C: public while Objective-C subclasses read them.
    HPVector lastPosition = { };
    Quaternion lastOrientation = { };

    GLfloat distanceTravelled = { }; // set to zero initially

    OOMatrix rotMatrix = { };

    Vector velocity = { };

    GLfloat energy = { };
    GLfloat maxEnergy = { };

    BoundingBox boundingBox = { };
    GLfloat mass = { };

    std::vector<oo::ObjCRef<::Entity*>> collidingEntities; // filled by CollisionRegion each frame

    OOTimeAbsolute spawnTime = { };

    JSValue _jsSelf = { }; // Zero-filled (not an object) until created; test with JS_IsObject().
    NSUInteger lastDrawCounter = { };

private:
    bool checkLinkedLists();

    NSUInteger _sessionID = { };

    oo::ObjCRef<::OOWeakReference*> _owner;
    OOEntityStatus _status = { };
};

} // namespace cxx

#ifdef __cplusplus
#include "oofnd/StdLib.hpp"

// C++ forms, defined in OOConstToString.mm (bead oo-nts1, chunk oo-3rb.161): std::string results
// (never nil), const std::string & parameters (nil arrived as "" and matched nothing: the defaults).
// Former Foundation forms lived in a transitional bridge (deleted by oo-a8xp).
std::string cxx_OOStringFromEntityStatus(OOEntityStatus status);
OOEntityStatus cxx_OOEntityStatusFromString(const std::string& string);

std::string cxx_OOStringFromScanClass(OOScanClass scanClass);
OOScanClass cxx_OOScanClassFromString(const std::string& string);
#endif

// Transitional: the Objective-C Entity, for callers and subclasses not yet converted. Deleted,
// with namespace cxx above, by the bridge's deletion bead.
#import "Entity+ObjCBridge.h"
