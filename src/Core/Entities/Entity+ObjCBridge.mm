/*

Entity+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, amendment oo-bj8): the Objective-C Entity facade (see
Entity+ObjCBridge.h). Every method forwards to its C++ member. An Objective-C entity's C++ part
is an oo::ObjCEntity adapter, whose virtual members message the entity; for the members its
subclasses override, the facade calls the adapter's super...() member, the base's own. The
facade's -init and -dealloc keep what needs the Objective-C object as self. Deleted with
Entity+ObjCBridge.h.

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

#import "DustEntity.h"
#import "Entity.h"
#import "EntityOOJavaScriptExtensions.h"
#import "NSObjectOOExtensions.h"
#import "OOBreakPatternEntity.h"
#import "OODescription.h"
#import "OOEntityWithDrawable.h"
#import "OOExhaustPlumeEntity.h"
#import "OOFlashEffectEntity.h"
#import "OOFlasherEntity.h"
#import "OOLaserShotEntity.h"
#import "OOLightParticleEntity.h"
#import "OOPlanetEntity.h"
#import "OOSunEntity.h"
#import "OOWaypointEntity.h"
#import "SkyEntity.h"
#import "Universe.h"
#import "WormholeEntity.h"
#include "oofnd/String.hpp"
#include "oofnd/objc/OOAssert.h"
#include "oofnd/objc/OOObjCPeer.h"
#include "oofnd/objc/OORuntime.h"

#include <cstdlib>
#include <cxxabi.h>
#include <typeinfo>

namespace {

// Never destroyed: a facade may be released while the process exits.
oo::ObjCPeers& Peers()
{
    static oo::ObjCPeers* peers = new oo::ObjCPeers;
    return *peers;
}

} // namespace

::Entity* oo::ToObjC(cxx::Entity* entity)
{
    if (entity == nullptr)
        return nil;
    if (ObjCEntityLink* link = AsObjCEntity(entity))
        return link->objcOwner();
    // A C++ entity's facade made it and owns it (oo::NewEntityFacade): never a new one here.
    return Peers().peerFor(entity, [] { return nil; });
}

::Entity* oo::NewEntityFacade(const Ref<cxx::Entity>& entity)
{
    if (entity == nullptr)
        return nil;
    OOCParameterAssert(AsObjCEntity(entity.get()) == nullptr);
    Class facadeClass = [::Entity class];
    if (dynamic_cast<cxx::OOEntityWithDrawable*>(entity.get()) != nullptr)
        facadeClass = [::OOEntityWithDrawable class];
    if (dynamic_cast<cxx::OOBreakPatternEntity*>(entity.get()) != nullptr)
        facadeClass = [::OOBreakPatternEntity class];
    if (dynamic_cast<cxx::OOLaserShotEntity*>(entity.get()) != nullptr)
        facadeClass = [::OOLaserShotEntity class];
    if (dynamic_cast<cxx::DustEntity*>(entity.get()) != nullptr)
        facadeClass = [::DustEntity class];
    if (dynamic_cast<cxx::OOLightParticleEntity*>(entity.get()) != nullptr)
        facadeClass = [::OOLightParticleEntity class];
    if (dynamic_cast<cxx::WormholeEntity*>(entity.get()) != nullptr)
        facadeClass = [::WormholeEntity class];
    if (dynamic_cast<cxx::OOSunEntity*>(entity.get()) != nullptr)
        facadeClass = [::OOSunEntity class];
    if (dynamic_cast<cxx::OOExhaustPlumeEntity*>(entity.get()) != nullptr)
        facadeClass = [::OOExhaustPlumeEntity class];
    if (dynamic_cast<cxx::SkyEntity*>(entity.get()) != nullptr)
        facadeClass = [::SkyEntity class];
    if (dynamic_cast<cxx::OOWaypointEntity*>(entity.get()) != nullptr)
        facadeClass = [::OOWaypointEntity class];
    if (dynamic_cast<cxx::OOFlasherEntity*>(entity.get()) != nullptr)
        facadeClass = [::OOFlasherEntity class];
    if (dynamic_cast<cxx::OOFlashEffectEntity*>(entity.get()) != nullptr)
        facadeClass = [::OOFlashEffectEntity class];
    if (dynamic_cast<cxx::OOPlanetEntity*>(entity.get()) != nullptr)
        facadeClass = [::OOPlanetEntity class];
    return [[(::Entity*)[facadeClass alloc] initWithCxxEntity:entity.get()] autorelease];
}

std::string oo::EntityClassName(cxx::Entity* entity)
{
    if (ObjCEntityLink* link = AsObjCEntity(entity))
        return OOClassName([link->objcOwner() class]);
    int status = 0;
    char* demangled = abi::__cxa_demangle(typeid(*entity).name(), nullptr, nullptr, &status);
    std::string result = (status == 0 && demangled != nullptr) ? demangled : typeid(*entity).name();
    std::free(demangled);
    if (result.starts_with("cxx::"))
        result.erase(0, 5);
    return result;
}

@interface Entity (OOObjCBridgePrivate)

// Found by selector (the shader bindings).
- (Vector)relativePosition;

@end

@implementation Entity

// An Objective-C entity: [[X alloc] init] of a subclass (or of this class).
- (id)init
{
    // -init sent again to an initialised entity keeps its C++ part (see -initWithCxxEntity:).
    if (_cxxEntity != nullptr)
        return [self initWithCxxEntity:_cxxEntity.get()];
    return [self initWithCxxEntity:oo::makeRef<oo::ObjCEntity<cxx::Entity>>(self).get()];
}

- (id)initWithCxxEntity:(cxx::Entity*)entity
{
    self = [super init];
    if (EXPECT_NOT(self == nil))
        return nil;

    if (_cxxEntity != nullptr) {
        /*	An initialised entity sent -init again (PlayerEntity's -deferredInit): the Objective-C
                -init re-ran its body over the same ivars, so the body runs again over the same C++
                part, and the rest of its state (the script object, the flags set since) stays.
        */
        OOCParameterAssert(entity == _cxxEntity.get());
        _cxxEntity->init();
    } else {
        _cxxEntity = oo::Ref<cxx::Entity>(entity);
        if (oo::AsObjCEntity(entity) == nullptr) {
            @autoreleasepool {
                Peers().peerFor(entity, [self] { return [self retain]; });
            }
        }
    }

#ifdef OO_DEBUG_MONITOR_ENABLED
    gLiveEntityCount++;
    gTotalEntityMemory += [self oo_objectSize];
#endif
    return self;
}

- (void)dealloc
{
    /*	Released before -init ran (a failing initialiser's [self release]; return nil;): there is no
            C++ part, and nothing was counted or registered. The Objective-C body's messages went to nil
            ivars here.
    */
    if (_cxxEntity == nullptr) {
        [super dealloc];
        return;
    }

    [UNIVERSE ensureEntityReallyRemoved:self];
    [self setCollisionRegion:nil]; // DESTROY(collisionRegion)
    [self deleteJSSelf];
    [self setOwner:nil];
    [self setAtmosphereFogging:nil]; // [atmosphereFogging release]

#ifdef OO_DEBUG_MONITOR_ENABLED
    gLiveEntityCount--;
    gTotalEntityMemory -= [self oo_objectSize];
#endif

    if (oo::ObjCEntityLink* link = oo::AsObjCEntity(_cxxEntity.get()))
        link->objcOwnerDeallocated();
    else
        Peers().forget(_cxxEntity.get());
    _cxxEntity = nullptr; // the C++ part goes with the object, before its superclass's -dealloc

    [super dealloc];
}

// A C++ entity's facade describes itself with the C++ class's name and components.
- (std::optional<std::string>)cxx_description
{
    if (oo::AsObjCEntity(_cxxEntity.get()) != nullptr)
        return [super cxx_description];
    std::string result = oo::str::format("<%s %s>", oo::EntityClassName(_cxxEntity.get()).c_str(), oo::str::pointerDescription(self).c_str());
    if (const std::optional<std::string> components = _cxxEntity->descriptionComponents())
        result += "{" + *components + "}";
    return result;
}

/*	The members that subclasses override are virtual. On an Objective-C entity these methods are
        reached only when the subclass does not override them, or by [super ...]: the adapter's
        super...() member, the nearest C++ base's own, answers. On a C++ entity's facade the C++
        override answers. The rest forward to their member.
*/
- (std::optional<std::string>)cxx_descriptionComponents
{
    if (oo::ObjCEntityLink* link = oo::AsObjCEntity(_cxxEntity.get()))
        return link->superDescriptionComponents();
    return _cxxEntity->descriptionComponents();
}

- (NSUInteger)sessionID
{
    if (oo::ObjCEntityLink* link = oo::AsObjCEntity(_cxxEntity.get()))
        return link->superSessionID();
    return _cxxEntity->sessionID();
}

- (BOOL)isShip
{
    return _cxxEntity->getIsShip();
}

- (BOOL)isDock
{
    if (oo::ObjCEntityLink* link = oo::AsObjCEntity(_cxxEntity.get()))
        return link->superIsDock();
    return _cxxEntity->isDock();
}

- (BOOL)isStation
{
    return _cxxEntity->getIsStation();
}
- (BOOL)isSubEntity
{
    return _cxxEntity->getIsSubEntity();
}
- (BOOL)isPlayer
{
    return _cxxEntity->getIsPlayer();
}

- (BOOL)isPlanet
{
    if (oo::ObjCEntityLink* link = oo::AsObjCEntity(_cxxEntity.get()))
        return link->superIsPlanet();
    return _cxxEntity->isPlanet();
}

- (BOOL)isSun
{
    if (oo::ObjCEntityLink* link = oo::AsObjCEntity(_cxxEntity.get()))
        return link->superIsSun();
    return _cxxEntity->isSun();
}

- (BOOL)isSunlit
{
    return _cxxEntity->getIsSunlit();
}
- (BOOL)isStellarObject
{
    return _cxxEntity->isStellarObject();
}

- (BOOL)isSky
{
    if (oo::ObjCEntityLink* link = oo::AsObjCEntity(_cxxEntity.get()))
        return link->superIsSky();
    return _cxxEntity->isSky();
}

- (BOOL)isWormhole
{
    return _cxxEntity->getIsWormhole();
}

- (BOOL)isEffect
{
    if (oo::ObjCEntityLink* link = oo::AsObjCEntity(_cxxEntity.get()))
        return link->superIsEffect();
    return _cxxEntity->isEffect();
}

- (BOOL)isVisualEffect
{
    if (oo::ObjCEntityLink* link = oo::AsObjCEntity(_cxxEntity.get()))
        return link->superGetIsVisualEffect();
    return _cxxEntity->getIsVisualEffect();
}

- (BOOL)isWaypoint
{
    if (oo::ObjCEntityLink* link = oo::AsObjCEntity(_cxxEntity.get()))
        return link->superIsWaypoint();
    return _cxxEntity->isWaypoint();
}

- (BOOL)validForAddToUniverse
{
    if (oo::ObjCEntityLink* link = oo::AsObjCEntity(_cxxEntity.get()))
        return link->superValidForAddToUniverse();
    return _cxxEntity->validForAddToUniverse();
}

- (void)addToLinkedLists
{
    _cxxEntity->addToLinkedLists();
}
- (void)removeFromLinkedLists
{
    _cxxEntity->removeFromLinkedLists();
}
- (void)updateLinkedLists
{
    _cxxEntity->updateLinkedLists();
}

- (void)wasAddedToUniverse
{
    if (oo::ObjCEntityLink* link = oo::AsObjCEntity(_cxxEntity.get()))
        link->superWasAddedToUniverse();
    else
        _cxxEntity->wasAddedToUniverse();
}

- (void)wasRemovedFromUniverse
{
    if (oo::ObjCEntityLink* link = oo::AsObjCEntity(_cxxEntity.get()))
        link->superWasRemovedFromUniverse();
    else
        _cxxEntity->wasRemovedFromUniverse();
}

- (void)warnAboutHostiles
{
    if (oo::ObjCEntityLink* link = oo::AsObjCEntity(_cxxEntity.get()))
        link->superWarnAboutHostiles();
    else
        _cxxEntity->warnAboutHostiles();
}

- (CollisionRegion*)collisionRegion
{
    return oo::ToObjC(_cxxEntity->getCollisionRegion());
}
- (void)setCollisionRegion:(CollisionRegion*)region
{
    _cxxEntity->setCollisionRegion(oo::ToCxx(region));
}
- (void)setUniversalID:(OOUniversalID)uid
{
    _cxxEntity->setUniversalID(uid);
}
- (OOUniversalID)universalID
{
    return _cxxEntity->getUniversalID();
}
- (BOOL)throwingSparks
{
    return _cxxEntity->throwingSparks();
}
- (void)setThrowSparks:(BOOL)value
{
    _cxxEntity->setThrowSparks(value);
}

- (void)throwSparks
{
    if (oo::ObjCEntityLink* link = oo::AsObjCEntity(_cxxEntity.get()))
        link->superThrowSparks();
    else
        _cxxEntity->throwSparks();
}

- (void)setOwner:(Entity*)ent
{
    if (oo::ObjCEntityLink* link = oo::AsObjCEntity(_cxxEntity.get()))
        link->superSetOwner(oo::ToCxx(ent));
    else
        _cxxEntity->setOwner(oo::ToCxx(ent));
}

- (id)owner
{
    return _cxxEntity->owner();
}
- (ShipEntity*)parentEntity
{
    return _cxxEntity->parentEntity();
}
- (id<OOWeakReferenceSupport>)superShaderBindingTarget
{
    return _cxxEntity->superShaderBindingTarget();
}
- (ShipEntity*)rootShipEntity
{
    return _cxxEntity->rootShipEntity();
}

- (void)setPosition:(HPVector)posn
{
    if (oo::ObjCEntityLink* link = oo::AsObjCEntity(_cxxEntity.get()))
        link->superSetPosition(posn);
    else
        _cxxEntity->setPosition(posn);
}

- (void)setPositionX:(OOHPScalar)x y:(OOHPScalar)y z:(OOHPScalar)z
{
    _cxxEntity->setPositionX(x, y, z);
}
- (HPVector)position
{
    return _cxxEntity->getPosition();
}
- (Vector)cameraRelativePosition
{
    return _cxxEntity->getCameraRelativePosition();
}

- (GLfloat)cameraRangeFront
{
    if (oo::ObjCEntityLink* link = oo::AsObjCEntity(_cxxEntity.get()))
        return link->superCameraRangeFront();
    return _cxxEntity->cameraRangeFront();
}

- (GLfloat)cameraRangeBack
{
    if (oo::ObjCEntityLink* link = oo::AsObjCEntity(_cxxEntity.get()))
        return link->superCameraRangeBack();
    return _cxxEntity->cameraRangeBack();
}

- (Vector)relativePosition
{
    return _cxxEntity->relativePosition();
}

- (void)updateCameraRelativePosition
{
    if (oo::ObjCEntityLink* link = oo::AsObjCEntity(_cxxEntity.get()))
        link->superUpdateCameraRelativePosition();
    else
        _cxxEntity->updateCameraRelativePosition();
}

- (Vector)vectorTo:(Entity*)entity
{
    return _cxxEntity->vectorTo(oo::ToCxx(entity));
}
- (HPVector)absolutePositionForSubentity
{
    return _cxxEntity->absolutePositionForSubentity();
}
- (HPVector)absolutePositionForSubentityOffset:(HPVector)offset
{
    return _cxxEntity->absolutePositionForSubentityOffset(offset);
}
- (double)zeroDistance
{
    return _cxxEntity->zeroDistance();
}
- (double)camZeroDistance
{
    return _cxxEntity->camZeroDistance();
}

- (OOComparisonResult)compareZeroDistance:(Entity*)otherEntity
{
    if (oo::ObjCEntityLink* link = oo::AsObjCEntity(_cxxEntity.get()))
        return link->superCompareZeroDistance(oo::ToCxx(otherEntity));
    return _cxxEntity->compareZeroDistance(oo::ToCxx(otherEntity));
}

- (BoundingBox)boundingBox
{
    return _cxxEntity->getBoundingBox();
}
- (GLfloat)mass
{
    return _cxxEntity->getMass();
}

- (void)setOrientation:(Quaternion)quat
{
    if (oo::ObjCEntityLink* link = oo::AsObjCEntity(_cxxEntity.get()))
        link->superSetOrientation(quat);
    else
        _cxxEntity->setOrientation(quat);
}

- (Quaternion)orientation
{
    return _cxxEntity->getOrientation();
}

- (Quaternion)normalOrientation
{
    if (oo::ObjCEntityLink* link = oo::AsObjCEntity(_cxxEntity.get()))
        return link->superNormalOrientation();
    return _cxxEntity->normalOrientation();
}

- (void)setNormalOrientation:(Quaternion)quat
{
    if (oo::ObjCEntityLink* link = oo::AsObjCEntity(_cxxEntity.get()))
        link->superSetNormalOrientation(quat);
    else
        _cxxEntity->setNormalOrientation(quat);
}

- (void)orientationChanged
{
    if (oo::ObjCEntityLink* link = oo::AsObjCEntity(_cxxEntity.get()))
        link->superOrientationChanged();
    else
        _cxxEntity->orientationChanged();
}

- (void)setVelocity:(Vector)vel
{
    _cxxEntity->setVelocity(vel);
}

- (Vector)velocity
{
    if (oo::ObjCEntityLink* link = oo::AsObjCEntity(_cxxEntity.get()))
        return link->superGetVelocity();
    return _cxxEntity->getVelocity();
}

- (double)speed
{
    return _cxxEntity->speed();
}
- (GLfloat)distanceTravelled
{
    return _cxxEntity->getDistanceTravelled();
}
- (void)setDistanceTravelled:(GLfloat)value
{
    _cxxEntity->setDistanceTravelled(value);
}

- (void)setStatus:(OOEntityStatus)stat
{
    if (oo::ObjCEntityLink* link = oo::AsObjCEntity(_cxxEntity.get()))
        link->superSetStatus(stat);
    else
        _cxxEntity->setStatus(stat);
}

- (OOEntityStatus)status
{
    return _cxxEntity->status();
}
- (void)setScanClass:(OOScanClass)sClass
{
    _cxxEntity->setScanClass(sClass);
}

- (OOScanClass)scanClass
{
    if (oo::ObjCEntityLink* link = oo::AsObjCEntity(_cxxEntity.get()))
        return link->superGetScanClass();
    return _cxxEntity->getScanClass();
}

- (void)setEnergy:(GLfloat)amount
{
    _cxxEntity->setEnergy(amount);
}
- (GLfloat)energy
{
    return _cxxEntity->getEnergy();
}
- (void)setMaxEnergy:(GLfloat)amount
{
    _cxxEntity->setMaxEnergy(amount);
}
- (GLfloat)maxEnergy
{
    return _cxxEntity->getMaxEnergy();
}

- (void)applyRoll:(GLfloat)roll andClimb:(GLfloat)climb
{
    if (oo::ObjCEntityLink* link = oo::AsObjCEntity(_cxxEntity.get()))
        link->superApplyRoll(roll, climb);
    else
        _cxxEntity->applyRoll(roll, climb);
}

- (void)applyRoll:(GLfloat)roll climb:(GLfloat)climb andYaw:(GLfloat)yaw
{
    if (oo::ObjCEntityLink* link = oo::AsObjCEntity(_cxxEntity.get()))
        link->superApplyRoll(roll, climb, yaw);
    else
        _cxxEntity->applyRoll(roll, climb, yaw);
}

- (void)moveForward:(double)amount
{
    if (oo::ObjCEntityLink* link = oo::AsObjCEntity(_cxxEntity.get()))
        link->superMoveForward(amount);
    else
        _cxxEntity->moveForward(amount);
}

- (OOMatrix)rotationMatrix
{
    return _cxxEntity->rotationMatrix();
}

- (OOMatrix)drawRotationMatrix
{
    if (oo::ObjCEntityLink* link = oo::AsObjCEntity(_cxxEntity.get()))
        return link->superDrawRotationMatrix();
    return _cxxEntity->drawRotationMatrix();
}

- (OOMatrix)transformationMatrix
{
    return _cxxEntity->transformationMatrix();
}

- (OOMatrix)drawTransformationMatrix
{
    if (oo::ObjCEntityLink* link = oo::AsObjCEntity(_cxxEntity.get()))
        return link->superDrawTransformationMatrix();
    return _cxxEntity->drawTransformationMatrix();
}

- (BOOL)canCollide
{
    if (oo::ObjCEntityLink* link = oo::AsObjCEntity(_cxxEntity.get()))
        return link->superCanCollide();
    return _cxxEntity->canCollide();
}

- (GLfloat)collisionRadius
{
    if (oo::ObjCEntityLink* link = oo::AsObjCEntity(_cxxEntity.get()))
        return link->superCollisionRadius();
    return _cxxEntity->collisionRadius();
}

- (GLfloat)frustumRadius
{
    if (oo::ObjCEntityLink* link = oo::AsObjCEntity(_cxxEntity.get()))
        return link->superFrustumRadius();
    return _cxxEntity->frustumRadius();
}

- (void)setCollisionRadius:(GLfloat)amount
{
    _cxxEntity->setCollisionRadius(amount);
}
- (std::vector<oo::ObjCRef<Entity*>>*)cxx_collidingEntities
{
    return _cxxEntity->getCollidingEntities();
}

- (void)update:(OOTimeDelta)delta_t
{
    if (oo::ObjCEntityLink* link = oo::AsObjCEntity(_cxxEntity.get()))
        link->superUpdate(delta_t);
    else
        _cxxEntity->update(delta_t);
}

- (void)applyVelocity:(OOTimeDelta)delta_t
{
    _cxxEntity->applyVelocity(delta_t);
}

- (BOOL)checkCloseCollisionWith:(Entity*)other
{
    if (oo::ObjCEntityLink* link = oo::AsObjCEntity(_cxxEntity.get()))
        return link->superCheckCloseCollisionWith(oo::ToCxx(other));
    return _cxxEntity->checkCloseCollisionWith(oo::ToCxx(other));
}

- (void)takeEnergyDamage:(double)amount from:(Entity*)ent becauseOf:(Entity*)other weaponIdentifier:(const std::string&)weaponIdentifier
{
    if (oo::ObjCEntityLink* link = oo::AsObjCEntity(_cxxEntity.get()))
        link->superTakeEnergyDamage(amount, oo::ToCxx(ent), oo::ToCxx(other), weaponIdentifier);
    else
        _cxxEntity->takeEnergyDamage(amount, oo::ToCxx(ent), oo::ToCxx(other), weaponIdentifier);
}

- (void)dumpState
{
    _cxxEntity->dumpState();
}

- (void)dumpSelfState
{
    if (oo::ObjCEntityLink* link = oo::AsObjCEntity(_cxxEntity.get()))
        link->superDumpSelfState();
    else
        _cxxEntity->dumpSelfState();
}

- (void)subEntityReallyDied:(ShipEntity*)sub
{
    if (oo::ObjCEntityLink* link = oo::AsObjCEntity(_cxxEntity.get()))
        link->superSubEntityReallyDied(sub);
    else
        _cxxEntity->subEntityReallyDied(sub);
}

- (NSUInteger)lastDrawCounter
{
    return _cxxEntity->getLastDrawCounter();
}
- (void)setLastDrawCounter:(NSUInteger)drawCounter
{
    _cxxEntity->setLastDrawCounter(drawCounter);
}

- (double)findCollisionRadius
{
    if (oo::ObjCEntityLink* link = oo::AsObjCEntity(_cxxEntity.get()))
        return link->superFindCollisionRadius();
    return _cxxEntity->findCollisionRadius();
}

- (void)drawImmediate:(bool)immediate translucent:(bool)translucent
{
    if (oo::ObjCEntityLink* link = oo::AsObjCEntity(_cxxEntity.get()))
        link->superDrawImmediate(immediate, translucent);
    else
        _cxxEntity->drawImmediate(immediate, translucent);
}

- (BOOL)isVisible
{
    if (oo::ObjCEntityLink* link = oo::AsObjCEntity(_cxxEntity.get()))
        return link->superIsVisible();
    return _cxxEntity->isVisible();
}

- (BOOL)isInSpace
{
    return _cxxEntity->isInSpace();
}
- (BOOL)isImmuneToBreakPatternHide
{
    return _cxxEntity->getIsImmuneToBreakPatternHide();
}
- (GLfloat)universalTime
{
    return _cxxEntity->universalTime();
}
- (GLfloat)spawnTime
{
    return _cxxEntity->getSpawnTime();
}
- (GLfloat)timeElapsedSinceSpawn
{
    return _cxxEntity->timeElapsedSinceSpawn();
}
- (void)setAtmosphereFogging:(OOColor*)fogging
{
    _cxxEntity->setAtmosphereFogging(oo::ToCxx(fogging));
}
- (OOColor*)fogUniform
{
    return oo::ToObjC(_cxxEntity->fogUniform());
}

#ifdef OO_DEBUG_MONITOR_ENABLED
- (std::optional<std::string>)descriptionForObjDumpBasic
{
    return _cxxEntity->descriptionForObjDumpBasic();
}

- (std::optional<std::string>)descriptionForObjDump
{
    if (oo::ObjCEntityLink* link = oo::AsObjCEntity(_cxxEntity.get()))
        return link->superDescriptionForObjDump();
    return _cxxEntity->descriptionForObjDump();
}

- (std::vector<oo::ObjCRef<OOTexture*>>)cxx_allTextures
{
    if (oo::ObjCEntityLink* link = oo::AsObjCEntity(_cxxEntity.get()))
        return link->superAllTextures();
    return _cxxEntity->allTextures();
}
#endif

@end
