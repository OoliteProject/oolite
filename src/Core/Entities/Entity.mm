/*

Entity.m

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

#import "Entity.h"
#import "EntityOOJavaScriptExtensions.h"
#import "OOPlanetEntity.h"
#import "PlayerEntity.h"
#include "oofnd/objc/OORuntime.h"

#import "GameController.h"
#import "OOConstToString.h"
#import "OOMaths.h"
#import "ResourceManager.h"
#import "Universe.h"

#import "CollisionRegion.h"

#import "NSObjectOOExtensions.h"
#import "OODebugFlags.h"
#include "oofnd/Log.hpp"
#include "oofnd/String.hpp"

#ifdef OO_DEBUG_MONITOR_ENABLED
uint32_t gLiveEntityCount = 0;
size_t gTotalEntityMemory = 0;
#endif

// Message-class constants for OO_LOG (const char *).
#ifdef OO_DEBUG_MONITOR_ENABLED
constexpr const char* kOOLogEntityAddToList = "entity.linkedList.add";
constexpr const char* kOOLogEntityAddToListError = "entity.linkedList.add.error";
constexpr const char* kOOLogEntityRemoveFromList = "entity.linkedList.remove";
constexpr const char* kOOLogEntityRemoveFromListError = "entity.linkedList.remove.error";
constexpr const char* kOOLogEntityUpdateError = "entity.linkedList.update.error";
#endif
constexpr const char* kOOLogEntityVerificationError = "entity.linkedList.verify.error";

namespace cxx {

// -init's body is init(), which the facade runs again when an initialised entity is sent -init.
Entity::Entity()
{
    init();
}

/*	-init. What needed the Objective-C object as self (counting the entity with its instance
        size) is in the facade's initialiser. Run by the constructor, and again when an initialised
        entity is sent -init (PlayerEntity's -deferredInit sends it through -[ShipEntity
        cxx_initWithKey:...]).
*/
void Entity::init()
{
    _sessionID = [UNIVERSE sessionID];

    orientation = kIdentityQuaternion;
    rotMatrix = kIdentityMatrix;
    position = kZeroHPVector;

    no_draw_distance = 100000.0; //  10 km

    scanClass = CLASS_NOT_SET;
    Entity::setStatus(STATUS_COCKPIT_DISPLAY); // the base's own: ShipEntity's override does the same for this status

    spawnTime = [UNIVERSE getTime];

    isSunlit = YES;

    atmosphereFogging = OOColor::colorWithRed(0.0, 0.0, 0.0, 0.0);

    lastDrawCounter = 0;
}

// -dealloc is the facade's: it tells the universe and the script about the Objective-C object.

std::optional<std::string> Entity::descriptionComponents() const
{
    // The getters read these ivars.
    return oo::str::format("position: %s scanClass: %s status: %s", cxx_HPVectorDescription(position).c_str(), cxx_OOStringFromScanClass(const_cast<Entity*>(this)->getScanClass()).c_str(), cxx_OOStringFromEntityStatus(_status).c_str());
}

NSUInteger Entity::sessionID()
{
    return _sessionID;
}

bool Entity::getIsShip()
{
    return isShip;
}

bool Entity::isDock()
{
    return NO;
}

bool Entity::getIsStation()
{
    return isStation;
}

bool Entity::getIsSubEntity()
{
    return isSubEntity;
}

bool Entity::getIsPlayer()
{
    return isPlayer;
}

bool Entity::isPlanet()
{
    return NO;
}

bool Entity::isSun()
{
    return NO;
}

bool Entity::getIsSunlit()
{
    return isSunlit;
}

bool Entity::isStellarObject()
{
    return isPlanet() || isSun();
}

bool Entity::isSky()
{
    return NO;
}

bool Entity::getIsWormhole()
{
    return isWormhole;
}

bool Entity::isEffect()
{
    return NO;
}

bool Entity::getIsVisualEffect()
{
    return NO;
}

bool Entity::isWaypoint()
{
    return NO;
}

bool Entity::validForAddToUniverse()
{
    NSUInteger mySessionID = sessionID();
    NSUInteger currentSessionID = [UNIVERSE sessionID];
    if (EXPECT_NOT(mySessionID != currentSessionID)) {
        OO_LOG_ERR("entity.invalidSession", "Entity {} from session {} cannot be added to universe in session {}. This is an internal error, please report it.", oo::ShortDescriptionOf(oo::ToObjC(this)), static_cast<size_t>(mySessionID), static_cast<size_t>(currentSessionID));
        return NO;
    }

    return YES;
}

void Entity::addToLinkedLists()
{
    ::Entity* self = oo::ToObjC(this); // the lists link the entities' Objective-C objects
#ifdef OO_DEBUG_MONITOR_ENABLED
    if (gDebugFlags & DEBUG_LINKED_LISTS)
        OO_LOG(kOOLogEntityAddToList, "DEBUG adding entity {} to linked lists", oo::DescriptionOf(self));
#endif
    //
    // insert at the start
    if (UNIVERSE) {
        x_previous = nil;
        x_next = UNIVERSE->_cxxUniverse->x_list_start;
        // move UP the list
        while ((x_next) && (x_next->_cxxEntity->position.x - x_next->_cxxEntity->collision_radius < position.x - collision_radius)) {
            x_previous = x_next;
            x_next = x_next->_cxxEntity->x_next;
        }
        if (x_next)
            x_next->_cxxEntity->x_previous = self;
        if (x_previous)
            x_previous->_cxxEntity->x_next = self;
        else
            UNIVERSE->_cxxUniverse->x_list_start = self;

        y_previous = nil;
        y_next = UNIVERSE->_cxxUniverse->y_list_start;
        // move UP the list
        while ((y_next) && (y_next->_cxxEntity->position.y - y_next->_cxxEntity->collision_radius < position.y - collision_radius)) {
            y_previous = y_next;
            y_next = y_next->_cxxEntity->y_next;
        }
        if (y_next)
            y_next->_cxxEntity->y_previous = self;
        if (y_previous)
            y_previous->_cxxEntity->y_next = self;
        else
            UNIVERSE->_cxxUniverse->y_list_start = self;

        z_previous = nil;
        z_next = UNIVERSE->_cxxUniverse->z_list_start;
        // move UP the list
        while ((z_next) && (z_next->_cxxEntity->position.z - z_next->_cxxEntity->collision_radius < position.z - collision_radius)) {
            z_previous = z_next;
            z_next = z_next->_cxxEntity->z_next;
        }
        if (z_next)
            z_next->_cxxEntity->z_previous = self;
        if (z_previous)
            z_previous->_cxxEntity->z_next = self;
        else
            UNIVERSE->_cxxUniverse->z_list_start = self;
    }

#ifdef OO_DEBUG_MONITOR_ENABLED
    if (gDebugFlags & DEBUG_LINKED_LISTS) {
        if (!checkLinkedLists()) {
            OO_LOG(kOOLogEntityAddToListError, "DEBUG LINKED LISTS - problem encountered while adding {} to linked lists", oo::DescriptionOf(self));
            [UNIVERSE debugDumpEntities];
        }
    }
#endif
}

void Entity::removeFromLinkedLists()
{
    ::Entity* self = oo::ToObjC(this); // the lists link the entities' Objective-C objects
#ifdef OO_DEBUG_MONITOR_ENABLED
    if (gDebugFlags & DEBUG_LINKED_LISTS)
        OO_LOG(kOOLogEntityRemoveFromList, "DEBUG removing entity {} from linked lists", oo::DescriptionOf(self));
#endif

    if ((x_next == nil) && (x_previous == nil)) // removed already!
        return;

    // make sure the starting point is still correct
    if (UNIVERSE) {
        if ((UNIVERSE->_cxxUniverse->x_list_start == self) && (x_next))
            UNIVERSE->_cxxUniverse->x_list_start = x_next;
        if ((UNIVERSE->_cxxUniverse->y_list_start == self) && (y_next))
            UNIVERSE->_cxxUniverse->y_list_start = y_next;
        if ((UNIVERSE->_cxxUniverse->z_list_start == self) && (z_next))
            UNIVERSE->_cxxUniverse->z_list_start = z_next;
    }
    //
    if (x_previous)
        x_previous->_cxxEntity->x_next = x_next;
    if (x_next)
        x_next->_cxxEntity->x_previous = x_previous;
    //
    if (y_previous)
        y_previous->_cxxEntity->y_next = y_next;
    if (y_next)
        y_next->_cxxEntity->y_previous = y_previous;
    //
    if (z_previous)
        z_previous->_cxxEntity->z_next = z_next;
    if (z_next)
        z_next->_cxxEntity->z_previous = z_previous;
    //
    x_previous = nil;
    x_next = nil;
    y_previous = nil;
    y_next = nil;
    z_previous = nil;
    z_next = nil;

#ifdef OO_DEBUG_MONITOR_ENABLED
    if (gDebugFlags & DEBUG_LINKED_LISTS) {
        if (!checkLinkedLists()) {
            OO_LOG(kOOLogEntityRemoveFromListError, "DEBUG LINKED LISTS - problem encountered while removing {} from linked lists", oo::DescriptionOf(self));
            [UNIVERSE debugDumpEntities];
        }
    }
#endif
}

bool Entity::checkLinkedLists()
{
    // DEBUG check for loops
    if (UNIVERSE->_cxxUniverse->n_entities > 0) {
        int n;
        ::Entity *check, *last;
        //
        last = nil;
        //
        n = UNIVERSE->_cxxUniverse->n_entities;
        check = UNIVERSE->_cxxUniverse->x_list_start;
        while ((n--) && (check)) {
            last = check;
            check = check->_cxxEntity->x_next;
        }
        if ((check) || (n > 0)) {
            OO_LOG(kOOLogEntityVerificationError, "Broken x_next {} list ({}) ***", oo::DescriptionOf(UNIVERSE->_cxxUniverse->x_list_start), n);
            return NO;
        }
        //
        n = UNIVERSE->_cxxUniverse->n_entities;
        check = last;
        while ((n--) && (check))
            check = check->_cxxEntity->x_previous;
        if ((check) || (n > 0)) {
            OO_LOG(kOOLogEntityVerificationError, "Broken x_previous {} list ({}) ***", oo::DescriptionOf(UNIVERSE->_cxxUniverse->x_list_start), n);
            return NO;
        }
        //
        n = UNIVERSE->_cxxUniverse->n_entities;
        check = UNIVERSE->_cxxUniverse->y_list_start;
        while ((n--) && (check)) {
            last = check;
            check = check->_cxxEntity->y_next;
        }
        if ((check) || (n > 0)) {
            OO_LOG(kOOLogEntityVerificationError, "Broken y_next {} list ({}) ***", oo::DescriptionOf(UNIVERSE->_cxxUniverse->y_list_start), n);
            return NO;
        }
        //
        n = UNIVERSE->_cxxUniverse->n_entities;
        check = last;
        while ((n--) && (check))
            check = check->_cxxEntity->y_previous;
        if ((check) || (n > 0)) {
            OO_LOG(kOOLogEntityVerificationError, "Broken y_previous {} list ({}) ***", oo::DescriptionOf(UNIVERSE->_cxxUniverse->y_list_start), n);
            return NO;
        }
        //
        n = UNIVERSE->_cxxUniverse->n_entities;
        check = UNIVERSE->_cxxUniverse->z_list_start;
        while ((n--) && (check)) {
            last = check;
            check = check->_cxxEntity->z_next;
        }
        if ((check) || (n > 0)) {
            OO_LOG(kOOLogEntityVerificationError, "Broken z_next {} list ({}) ***", oo::DescriptionOf(UNIVERSE->_cxxUniverse->z_list_start), n);
            return NO;
        }
        //
        n = UNIVERSE->_cxxUniverse->n_entities;
        check = last;
        while ((n--) && (check))
            check = check->_cxxEntity->z_previous;
        if ((check) || (n > 0)) {
            OO_LOG(kOOLogEntityVerificationError, "Broken z_previous {} list ({}) ***", oo::DescriptionOf(UNIVERSE->_cxxUniverse->z_list_start), n);
            return NO;
        }
    }
    return YES;
}

void Entity::updateLinkedLists()
{
    ::Entity* self = oo::ToObjC(this); // the lists link the entities' Objective-C objects
    if (!UNIVERSE)
        return; // not in the UNIVERSE - don't do this!
    if ((x_next == nil) && (x_previous == nil))
        return; // not in the lists - don't do this!

#ifdef OO_DEBUG_MONITOR_ENABLED
    if (gDebugFlags & DEBUG_LINKED_LISTS) {
        if (!checkLinkedLists()) {
            OO_LOG(kOOLogEntityVerificationError, "DEBUG LINKED LISTS problem encountered before updating linked lists for {}", oo::DescriptionOf(self));
            [UNIVERSE debugDumpEntities];
        }
    }
#endif

    // update position in linked list for position.x
    // take self out of list..
    if (x_previous)
        x_previous->_cxxEntity->x_next = x_next;
    if (x_next)
        x_next->_cxxEntity->x_previous = x_previous;
    // sink DOWN the list
    while ((x_previous) && (x_previous->_cxxEntity->position.x - x_previous->_cxxEntity->collision_radius > position.x - collision_radius)) {
        x_next = x_previous;
        x_previous = x_previous->_cxxEntity->x_previous;
    }
    // bubble UP the list
    while ((x_next) && (x_next->_cxxEntity->position.x - x_next->_cxxEntity->collision_radius < position.x - collision_radius)) {
        x_previous = x_next;
        x_next = x_next->_cxxEntity->x_next;
    }
    if (x_next) // insert self into the list before x_next..
        x_next->_cxxEntity->x_previous = self;
    if (x_previous) // insert self into the list after x_previous..
        x_previous->_cxxEntity->x_next = self;
    if ((x_previous == nil) && (UNIVERSE)) // if we're the first then tell the UNIVERSE!
        UNIVERSE->_cxxUniverse->x_list_start = self;

    // update position in linked list for position.y
    // take self out of list..
    if (y_previous)
        y_previous->_cxxEntity->y_next = y_next;
    if (y_next)
        y_next->_cxxEntity->y_previous = y_previous;
    // sink DOWN the list
    while ((y_previous) && (y_previous->_cxxEntity->position.y - y_previous->_cxxEntity->collision_radius > position.y - collision_radius)) {
        y_next = y_previous;
        y_previous = y_previous->_cxxEntity->y_previous;
    }
    // bubble UP the list
    while ((y_next) && (y_next->_cxxEntity->position.y - y_next->_cxxEntity->collision_radius < position.y - collision_radius)) {
        y_previous = y_next;
        y_next = y_next->_cxxEntity->y_next;
    }
    if (y_next) // insert self into the list before y_next..
        y_next->_cxxEntity->y_previous = self;
    if (y_previous) // insert self into the list after y_previous..
        y_previous->_cxxEntity->y_next = self;
    if ((y_previous == nil) && (UNIVERSE)) // if we're the first then tell the UNIVERSE!
        UNIVERSE->_cxxUniverse->y_list_start = self;

    // update position in linked list for position.z
    // take self out of list..
    if (z_previous)
        z_previous->_cxxEntity->z_next = z_next;
    if (z_next)
        z_next->_cxxEntity->z_previous = z_previous;
    // sink DOWN the list
    while ((z_previous) && (z_previous->_cxxEntity->position.z - z_previous->_cxxEntity->collision_radius > position.z - collision_radius)) {
        z_next = z_previous;
        z_previous = z_previous->_cxxEntity->z_previous;
    }
    // bubble UP the list
    while ((z_next) && (z_next->_cxxEntity->position.z - z_next->_cxxEntity->collision_radius < position.z - collision_radius)) {
        z_previous = z_next;
        z_next = z_next->_cxxEntity->z_next;
    }
    if (z_next) // insert self into the list before z_next..
        z_next->_cxxEntity->z_previous = self;
    if (z_previous) // insert self into the list after z_previous..
        z_previous->_cxxEntity->z_next = self;
    if ((z_previous == nil) && (UNIVERSE)) // if we're the first then tell the UNIVERSE!
        UNIVERSE->_cxxUniverse->z_list_start = self;

    // done
#ifdef OO_DEBUG_MONITOR_ENABLED
    if (gDebugFlags & DEBUG_LINKED_LISTS) {
        if (!checkLinkedLists()) {
            OO_LOG(kOOLogEntityUpdateError, "DEBUG LINKED LISTS problem encountered after updating linked lists for {}", oo::DescriptionOf(self));
            [UNIVERSE debugDumpEntities];
        }
    }
#endif
}

void Entity::wasAddedToUniverse()
{
    // Do nothing
}

void Entity::wasRemovedFromUniverse()
{
    // Do nothing
}

void Entity::warnAboutHostiles()
{
    // do nothing for now, this can be expanded in sub classes
    OO_LOG("general.error.subclassResponsibility.Entity-warnAboutHostiles", "{}", "***** Entity does nothing in warnAboutHostiles");
}

CollisionRegion* Entity::getCollisionRegion()
{
    return collisionRegion.get();
}

void Entity::setCollisionRegion(CollisionRegion* region)
{
    collisionRegion = oo::Ref<CollisionRegion>(region);
}

void Entity::setUniversalID(OOUniversalID uid)
{
    universalID = uid;
}

OOUniversalID Entity::getUniversalID()
{
    return universalID;
}

bool Entity::throwingSparks()
{
    return throw_sparks;
}

void Entity::setThrowSparks(bool value)
{
    throw_sparks = value;
}

void Entity::throwSparks()
{
    // do nothing for now
}

void Entity::setOwner(Entity* ent)
{
    _owner = oo::ObjCRef<::OOWeakReference*>::adopt([oo::ToObjC(ent) weakRetain]);
}

id Entity::owner()
{
    ::OOWeakReference* ownerRef = _owner.get();
    return ownerRef != nil ? oo::ToCxx(ownerRef)->weakRefUnderlyingObject() : nil;
}

::ShipEntity* Entity::parentEntity()
{
    id owner = this->owner();
    if ([owner isShipWithSubEntityShip:oo::ToObjC(this)])
        return owner;
    return nil;
}

id<OOWeakReferenceSupport> Entity::superShaderBindingTarget()
{
    return parentEntity();
}

::ShipEntity* Entity::rootShipEntity()
{
    ::ShipEntity* parent = parentEntity();
    if (parent != nil)
        return oo::ToCxx(parent)->rootShipEntity();
    if (getIsShip())
        return (::ShipEntity*)oo::ToObjC(this);
    return nil;
}

HPVector Entity::getPosition()
{
    return position;
}

Vector Entity::getCameraRelativePosition()
{
    return cameraRelativePosition;
}

GLfloat Entity::cameraRangeFront()
{
    return magnitude(cameraRelativePosition) - frustumRadius();
}

GLfloat Entity::cameraRangeBack()
{
    return magnitude(cameraRelativePosition) + frustumRadius();
}

// Exposed to uniform bindings.
// so needs to remain at OpenGL precision levels
Vector Entity::relativePosition()
{
    return HPVectorToVector(HPvector_subtract(getPosition(), [PLAYER position]));
}

Vector Entity::vectorTo(Entity* entity)
{
    // A message to nil answered the zero vector.
    return HPVectorToVector(HPvector_subtract(entity != nullptr ? entity->getPosition() : kZeroHPVector, getPosition()));
}

void Entity::setPosition(HPVector posn)
{
    position = posn;
    updateCameraRelativePosition();
}

void Entity::setPositionX(OOHPScalar x, OOHPScalar y, OOHPScalar z)
{
    position.x = x;
    position.y = y;
    position.z = z;
    updateCameraRelativePosition();
}

void Entity::updateCameraRelativePosition()
{
    cameraRelativePosition = HPVectorToVector(HPvector_subtract(absolutePositionForSubentity(), [PLAYER viewpointPosition]));
}

HPVector Entity::absolutePositionForSubentity()
{
    return absolutePositionForSubentityOffset(kZeroHPVector);
}

HPVector Entity::absolutePositionForSubentityOffset(HPVector offset)
{
    HPVector abspos = HPvector_add(position, OOHPVectorMultiplyMatrix(offset, rotMatrix));
    Entity* last = nil;
    Entity* father = oo::ToCxx(parentEntity());

    while (father != nil && father != last) {
        abspos = HPvector_add(OOHPVectorMultiplyMatrix(abspos, father->drawRotationMatrix()), father->getPosition());
        last = father;
        if (!last->getIsSubEntity())
            break;
        father = oo::ToCxx(static_cast<::Entity*>(father->owner()));
    }
    return abspos;
}

double Entity::zeroDistance()
{
    return zero_distance;
}

double Entity::camZeroDistance()
{
    return cam_zero_distance;
}

OOComparisonResult Entity::compareZeroDistance(Entity* otherEntity)
{
    if ((otherEntity) && (zero_distance > otherEntity->zero_distance))
        return OOOrderedAscending;
    else
        return OOOrderedDescending;
}

BoundingBox Entity::getBoundingBox()
{
    return boundingBox;
}

GLfloat Entity::getMass()
{
    return mass;
}

void Entity::setOrientation(Quaternion quat)
{
    orientation = quat;
    orientationChanged();
}

Quaternion Entity::getOrientation()
{
    return orientation;
}

Quaternion Entity::normalOrientation()
{
    return getOrientation();
}

void Entity::setNormalOrientation(Quaternion quat)
{
    setOrientation(quat);
}

void Entity::orientationChanged()
{
    quaternion_normalize(&orientation);
    rotMatrix = OOMatrixForQuaternionRotation(orientation);
}

void Entity::setVelocity(Vector vel)
{
    velocity = vel;
}

Vector Entity::getVelocity()
{
    return velocity;
}

double Entity::speed()
{
    return magnitude(getVelocity());
}

GLfloat Entity::getDistanceTravelled()
{
    return distanceTravelled;
}

void Entity::setDistanceTravelled(GLfloat value)
{
    distanceTravelled = value;
}

void Entity::setStatus(OOEntityStatus stat)
{
    _status = stat;
}

OOEntityStatus Entity::status()
{
    return _status;
}

void Entity::setScanClass(OOScanClass sClass)
{
    scanClass = sClass;
}

OOScanClass Entity::getScanClass()
{
    return scanClass;
}

void Entity::setEnergy(GLfloat amount)
{
    energy = amount;
}

GLfloat Entity::getEnergy()
{
    return energy;
}

void Entity::setMaxEnergy(GLfloat amount)
{
    maxEnergy = amount;
}

GLfloat Entity::getMaxEnergy()
{
    return maxEnergy;
}

void Entity::applyRoll(GLfloat roll, GLfloat climb)
{
    if ((roll == 0.0) && (climb == 0.0) && (!hasRotated))
        return;

    if (roll)
        quaternion_rotate_about_z(&orientation, -roll);
    if (climb)
        quaternion_rotate_about_x(&orientation, -climb);

    orientationChanged();
}

void Entity::applyRoll(GLfloat roll, GLfloat climb, GLfloat yaw)
{
    if ((roll == 0.0) && (climb == 0.0) && (yaw == 0.0) && (!hasRotated))
        return;

    if (roll)
        quaternion_rotate_about_z(&orientation, -roll);
    if (climb)
        quaternion_rotate_about_x(&orientation, -climb);
    if (yaw)
        quaternion_rotate_about_y(&orientation, -yaw);

    orientationChanged();
}

void Entity::moveForward(double amount)
{
    HPVector forward = HPvector_multiply_scalar(HPvector_forward_from_quaternion(orientation), amount);
    position = HPvector_add(position, forward);
    distanceTravelled += amount;
}

OOMatrix Entity::rotationMatrix()
{
    return rotMatrix;
}

OOMatrix Entity::drawRotationMatrix()
{
    return rotMatrix;
}

OOMatrix Entity::transformationMatrix()
{
    OOMatrix result = rotMatrix;
    return OOMatrixHPTranslate(result, position);
}

OOMatrix Entity::drawTransformationMatrix()
{
    OOMatrix result = rotMatrix;
    return OOMatrixHPTranslate(result, position);
}

bool Entity::canCollide()
{
    return YES;
}

GLfloat Entity::collisionRadius()
{
    return collision_radius;
}

GLfloat Entity::frustumRadius()
{
    return collision_radius;
}

void Entity::setCollisionRadius(GLfloat amount)
{
    collision_radius = amount;
}

std::vector<oo::ObjCRef<::Entity*>>* Entity::getCollidingEntities()
{
    return &collidingEntities;
}

void Entity::update(OOTimeDelta delta_t)
{
    if (_status != STATUS_COCKPIT_DISPLAY) {
        if (getIsSubEntity()) {
            // A message to a nil owner answered 0.
            Entity* ownerEntity = oo::ToCxx(static_cast<::Entity*>(owner()));
            zero_distance = ownerEntity != nullptr ? ownerEntity->zeroDistance() : 0;
            cam_zero_distance = ownerEntity != nullptr ? ownerEntity->camZeroDistance() : 0;
            updateCameraRelativePosition();
        } else {
            zero_distance = HPdistance2(oo::ToCxx(PLAYER)->position, position);
            cam_zero_distance = HPdistance2([PLAYER viewpointPosition], position);
            updateCameraRelativePosition();
        }
    } else {
        zero_distance = HPmagnitude2(position);
        cam_zero_distance = zero_distance;
        cameraRelativePosition = HPVectorToVector(position);
    }

    if (status() != STATUS_COCKPIT_DISPLAY) {
        applyVelocity(delta_t);
    }

    hasMoved = !HPvector_equal(position, lastPosition);
    hasRotated = !quaternion_equal(orientation, lastOrientation);
    lastPosition = position;
    lastOrientation = orientation;
}

void Entity::applyVelocity(OOTimeDelta delta_t)
{
    position = HPvector_add(position, HPvector_multiply_scalar(vectorToHPVector(velocity), delta_t));
}

bool Entity::checkCloseCollisionWith(Entity* other)
{
    return other != nil;
}

double Entity::findCollisionRadius()
{
    OOLogGenericSubclassResponsibility();
    return 0;
}

void Entity::drawImmediate(bool /*immediate*/, bool /*translucent*/)
{
    OOLogGenericSubclassResponsibility();
}

void Entity::takeEnergyDamage(double /*amount*/, Entity* /*ent*/, Entity* /*other*/, const std::string& /*weaponIdentifier*/)
{
}

void Entity::dumpState()
{
    if (oo::log::willDisplay("dumpState")) {
        OO_LOG("dumpState", "State for {}:", oo::DescriptionOf(oo::ToObjC(this)));
        oo::log::pushIndent();
        oo::log::indent();
        @try {
            dumpSelfState();
        }
        @catch (id exception) {
        }
        oo::log::popIndent();
    }
}

void Entity::dumpSelfState()
{
    std::vector<std::string> flags;
    std::string flagsString;
    id owner = this->owner();
    std::string ownerDescription; // the literals were @"self" and @"none"

    if (owner == oo::ToObjC(this))
        ownerDescription = "self";
    else if (owner == nil)
        ownerDescription = "none";
    else
        ownerDescription = oo::DescriptionOf(owner);

    OO_LOG("dumpState.entity", "Universal ID: {}", static_cast<unsigned>(universalID));
    OO_LOG("dumpState.entity", "Scan class: {}", cxx_OOStringFromScanClass(scanClass));
    OO_LOG("dumpState.entity", "Status: {}", cxx_OOStringFromEntityStatus(status()));
    OO_LOG("dumpState.entity", "Position: {}", cxx_HPVectorDescription(position));
    OO_LOG("dumpState.entity", "Orientation: {}", QuaternionDescription(orientation));
    OO_LOG("dumpState.entity", "Distance travelled: {:g}", distanceTravelled);
    OO_LOG("dumpState.entity", "Energy: {:g} of {:g}", energy, maxEnergy);
    OO_LOG("dumpState.entity", "Mass: {:g}", mass);
    OO_LOG("dumpState.entity", "Owner: {}", ownerDescription);

#define ADD_FLAG_IF_SET(x)   \
    if (x) {                 \
        flags.push_back(#x); \
    }
    ADD_FLAG_IF_SET(isShip);
    ADD_FLAG_IF_SET(isStation);
    ADD_FLAG_IF_SET(isPlayer);
    ADD_FLAG_IF_SET(isWormhole);
    ADD_FLAG_IF_SET(isSubEntity);
    ADD_FLAG_IF_SET(hasMoved);
    ADD_FLAG_IF_SET(hasRotated);
    ADD_FLAG_IF_SET(isSunlit);
    ADD_FLAG_IF_SET(throw_sparks);
    for (const std::string& flag : flags) {
        if (!flagsString.empty())
            flagsString += ", "; // -componentsJoinedByString:
        flagsString += flag;
    }
    if (flags.empty())
        flagsString = "none";
    OO_LOG("dumpState.entity", "Flags: {}", flagsString);
    OO_LOG("dumpState.entity", "Collision Test Filter: {}", static_cast<unsigned>(collisionTestFilter));
}

void Entity::subEntityReallyDied(::ShipEntity* sub)
{
    OO_LOG("entity.bug", "{} called for non-ship entity {} by {}", __PRETTY_FUNCTION__, oo::str::pointerDescription(oo::ToObjC(this)), oo::str::pointerDescription(sub));
}

NSUInteger Entity::getLastDrawCounter()
{
    return lastDrawCounter;
}

void Entity::setLastDrawCounter(NSUInteger drawCounter)
{
    lastDrawCounter = drawCounter;
    return;
}

// For shader bindings.
GLfloat Entity::universalTime()
{
    return [UNIVERSE getTime];
}

GLfloat Entity::getSpawnTime()
{
    return spawnTime;
}

GLfloat Entity::timeElapsedSinceSpawn()
{
    return [UNIVERSE getTime] - spawnTime;
}

void Entity::setAtmosphereFogging(OOColor* fogging)
{
    atmosphereFogging = oo::Ref<OOColor>(fogging);
}

oo::Ref<OOColor> Entity::fogUniform()
{
    return atmosphereFogging;
}

#ifdef OO_DEBUG_MONITOR_ENABLED
std::optional<std::string> Entity::descriptionForObjDumpBasic()
{
    const std::optional<std::string> components = descriptionComponents();
    if (components.has_value())
        return oo::str::format("%s %s", oo::EntityClassName(this).c_str(), components->c_str());
    return [oo::ToObjC(this) cxx_description];
}

std::optional<std::string> Entity::descriptionForObjDump()
{
    const std::optional<std::string> result = descriptionForObjDumpBasic();
    if (!result)
        return std::nullopt; // -stringByAppendingFormat: sent to nil

    return *result + oo::str::format(" range: %g (visible: %s)", HPdistance(getPosition(), [PLAYER position]), isVisible() ? "yes" : "no");
}

std::vector<oo::ObjCRef<::OOTexture*>> Entity::allTextures()
{
    return { };
}
#endif

bool Entity::isVisible()
{
    return cam_zero_distance <= ABSOLUTE_NO_DRAW_DISTANCE2;
}

bool Entity::isInSpace()
{
    switch (status()) {
    case STATUS_IN_FLIGHT:
    case STATUS_DOCKING:
    case STATUS_LAUNCHING:
    case STATUS_AUTOPILOT_ENGAGED:
    case STATUS_WITCHSPACE_COUNTDOWN:
    case STATUS_BEING_SCOOPED:
    case STATUS_EFFECT:
    case STATUS_ACTIVE:
        return YES;
    default:
        return NO;
    }
}

bool Entity::getIsImmuneToBreakPatternHide()
{
    return isImmuneToBreakPatternHide;
}

// Entity (OOJavaScriptExtensions)'s answers for the class, which the root category forwards here:
// the category's bodies, which a C++ subclass overrides.
JSClassID Entity::jsClassID()
{
    return ::EntityJSClassID();
}

std::optional<std::string> Entity::jsClassName()
{
    return ::EntityJSClassName();
}

bool Entity::isVisibleToScripts()
{
    return ::EntityJSIsVisibleToScripts();
}

} // namespace cxx
