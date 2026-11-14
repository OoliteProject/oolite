/*

ShipEntity+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, amendments oo-bj8 and oo-60fwo): the Objective-C ShipEntity
facade (see ShipEntity+ObjCBridge.h). Its initialisers and -dealloc are here, in a category while
the class's @implementation is still ShipEntity.mm, because they need the Objective-C object as
self (amendment oo-bj8 items 6 and 7), and so are the two SubEntityRelationship categories (item
12); the other methods are still in ShipEntity.mm until their slices move them. Deleted with
ShipEntity+ObjCBridge.h.

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

#import "AI.h"
#import "OOColor.h"
#import "OODescription.h"
#import "OOJSEngineTimeManagement.h"
#import "OOJSScript.h"
#import "OORoleSet.h"
#import "OOShipGroup.h"
#import "OOWeakSet.h"
#import "Octree.h"
#import "PlayerEntity.h"
#import "ShipEntity+ObjCAdapter.h"
#import "ShipEntity.h"
#import "ShipEntityAI.h"
#import "ShipEntityScriptMethods.h"
#include "oofnd/Log.hpp"
#include "oofnd/objc/OOAssert.h"

#include <cmath>

@implementation ShipEntity (OOObjCBridge)

- (id)init
{
    /*	-init used to set up a bunch of defaults that were different from
            those in -reinit and -setUpShipFromDictionary:. However, it seems that
            no ships are ever used which are not -setUpShipFromDictionary: (which
            is as it should be), so these different defaults were meaningless.
    */
    return [self cxx_initWithKey:std::string { } definition:oo::PList()];
}

- (id)initBypassForPlayer
{
    return [self initShipPart]; // [super init]
}

- (id)cxx_initWithKey:(const std::string&)key definition:(const oo::PList&)dict
{
    OOJS_PROFILE_ENTER

    self = [self initShipPart]; // [super init]
    if (self == nil)
        return nil;

    _cxxShip->initWithKey(key);

    if (![self setUpShipFromDictionary:dict]) {
        [self release];
        self = nil;
    }

    // Problem observed in testing -- Ahruman
    if (self != nil && !isfinite(_cxxShip->maxFlightSpeed)) {
        OO_LOG("ship.sanityCheck.failed", "Ship {} {} infinite top speed, clamped to 300.", oo::DescriptionOf(self), "generated with");
        _cxxShip->maxFlightSpeed = 300;
    }
    return self;

    OOJS_PROFILE_EXIT
}

/*	What [super init] did in the two initialisers, with the ship's adapter: an Objective-C ship, of
        this class or a subclass, has a C++ part over cxx::ShipEntity (amendment oo-bj8 item 5), as
        OOEntityWithDrawable's -init makes one over its class.
*/
- (id)initShipPart
{
    // -init sent again to an initialised ship keeps its C++ part (the root's -initWithCxxEntity:).
    if (_cxxEntity != nullptr)
        return [self initWithCxxEntity:_cxxEntity.get()];
    return [self initWithCxxEntity:oo::makeRef<oo::ObjCShipEntity<cxx::ShipEntity>>(self).get()];
}

// The root's designated initialiser, which also sets the typed alias of the part it stores.
- (id)initWithCxxEntity:(cxx::Entity*)entity
{
    self = [super initWithCxxEntity:entity];
    if (EXPECT_NOT(self == nil))
        return nil;

    _cxxShip = dynamic_cast<cxx::ShipEntity*>(_cxxEntity.get());
    OOCParameterAssert(_cxxShip != nullptr);
    return self;
}

- (void)dealloc
{
    /*	Released before its initialiser ran (a failing initialiser's [self release]; return nil;):
            there is no C++ part, as in the root's -dealloc (oo-s6ic6).
    */
    if (_cxxShip == nullptr) {
        [super dealloc];
        return;
    }

    /*	NOTE: we guarantee that entityDestroyed is sent immediately after the
            JS ship becomes invalid (as a result of dropping the weakref), i.e.
            with no intervening script activity.
            It has to be after the invalidation so that scripts can't directly or
            indirectly cause the ship to become strong-referenced. (Actually, we
            could handle that situation by breaking out of dealloc, but that's a
            nasty abuse of framework semantics and would require special-casing in
            subclasses.)
            -- Ahruman 2011-02-27
    */
    [weakSelf weakRefDrop];
    weakSelf = nil;
    [self doScriptEvent:OOJSID("entityDestroyed")];

    [self setTrackCloseContacts:NO]; // deallocs tracking dictionary
    [[self parentEntity] subEntityReallyDied:self]; // Will do nothing if we're not really a subentity
    [self clearSubEntities];

    DESTROY(_cxxShip->shipAI);
    DESTROY(_cxxShip->roleSet);
    DESTROY(_cxxShip->laser_color);
    DESTROY(_cxxShip->default_laser_color);
    DESTROY(_cxxShip->exhaust_emissive_color);
    DESTROY(_cxxShip->scanner_display_color1);
    DESTROY(_cxxShip->scanner_display_color2);
    DESTROY(_cxxShip->scanner_display_color_hostile1);
    DESTROY(_cxxShip->scanner_display_color_hostile2);
    DESTROY(_cxxShip->script);
    DESTROY(_cxxShip->aiScript);
    DESTROY(_cxxShip->octree);
    DESTROY(_cxxShip->_defenseTargets);
    DESTROY(_cxxShip->_collisionExceptions);

    [self setSubEntityTakingDamage:nil];
    [self removeAllEquipment];

    [_cxxShip->_group removeShip:self];
    DESTROY(_cxxShip->_group);
    [_cxxShip->_escortGroup removeShip:self];
    DESTROY(_cxxShip->_escortGroup);

    DESTROY(_cxxShip->_lastAegisLock);

    DESTROY(_cxxShip->_beaconDrawable);

    [super dealloc];
}

@end

double ShipEntityStellarBodyRadius(Entity<OOStellarBody>* stellar) { return [stellar radius]; }
GLfloat ShipEntityPlayerBaseMass(void) { return [PLAYER baseMass]; }

@implementation Entity (SubEntityRelationship)

- (BOOL)isShipWithSubEntityShip:(Entity*)other
{
    return NO;
}

- (void)drawSubEntityImmediate:(bool)immediate translucent:(bool)translucent
{
    // Do nothing.
}

@end

@implementation ShipEntity (SubEntityRelationship)

- (BOOL)isShipWithSubEntityShip:(Entity*)other
{
    return oo::ToCxx(self)->isShipWithSubEntityShip(other);
}

@end

@implementation ShipEntity (OOSlice2)

- (BOOL)cxx_setUpFromDictionary:(const oo::PList&)inShipDict
{
    return _cxxShip->setUpFromDictionary(inShipDict);
}

@end

@implementation ShipEntity (OOSlice3)

- (BOOL)setUpShipFromDictionary:(const oo::PList&)shipDict
{
    return _cxxShip->cxx::ShipEntity::setUpShipFromDictionary(shipDict);
}
- (void)setSubIdx:(NSUInteger)value
{
    _cxxShip->setSubIdx(value);
}
- (NSUInteger)subIdx
{
    return _cxxShip->subIdx();
}
- (NSUInteger)maxShipSubEntities
{
    return _cxxShip->maxShipSubEntities();
}
- (std::optional<std::string>)cxx_serializeShipSubEntities
{
    return _cxxShip->serializeShipSubEntities();
}
- (void)cxx_deserializeShipSubEntitiesFrom:(const std::string&)string
{
    _cxxShip->deserializeShipSubEntitiesFrom(string);
}
- (BOOL)setUpSubEntities
{
    return _cxxShip->cxx::ShipEntity::setUpSubEntities();
}
- (GLfloat)frustumRadius
{
    return _cxxShip->cxx::ShipEntity::frustumRadius();
}
- (BOOL)setUpOneSubentity:(const oo::PList&)subentDict
{
    return _cxxShip->setUpOneSubentity(subentDict);
}
- (BOOL)setUpOneFlasher:(const oo::PList&)subentDict
{
    return _cxxShip->setUpOneFlasher(subentDict);
}

@end

@implementation ShipEntity (OOSlice4)

- (BOOL)cxx_setUpOneStandardSubentity:(const oo::PList&)subentDict asTurret:(BOOL)asTurret
{
    return _cxxShip->setUpOneStandardSubentity(subentDict, asTurret);
}
- (BOOL)isTemplateCargoPod
{
    return _cxxShip->isTemplateCargoPod();
}
- (void)setUpCargoType:(const std::string&)cargoString
{
    _cxxShip->setUpCargoType(cargoString);
}
- (void)removeScript
{
    _cxxShip->removeScript();
}
- (void)clearSubEntities
{
    _cxxShip->clearSubEntities();
}
- (Quaternion)subEntityRotationalVelocity
{
    return _cxxShip->subEntityRotationalVelocity();
}
- (void)setSubEntityRotationalVelocity:(Quaternion)rv
{
    _cxxShip->setSubEntityRotationalVelocity(rv);
}
- (std::optional<std::string>)cxx_shortDescriptionComponents
{
    return _cxxShip->shortDescriptionComponents();
}
- (GLfloat)sunGlareFilter
{
    return _cxxShip->getSunGlareFilter();
}
- (void)setSunGlareFilter:(GLfloat)newValue
{
    _cxxShip->setSunGlareFilter(newValue);
}
- (GLfloat)accuracy
{
    return _cxxShip->getAccuracy();
}
- (void)setAccuracy:(GLfloat)new_accuracy
{
    _cxxShip->setAccuracy(new_accuracy);
}
- (OOMesh*)mesh
{
    return _cxxShip->mesh();
}
- (void)setMesh:(OOMesh*)mesh
{
    _cxxShip->setMesh(mesh);
}
- (BoundingBox)totalBoundingBox
{
    return _cxxShip->getTotalBoundingBox();
}
- (Vector)forwardVector
{
    return _cxxShip->forwardVector();
}
- (Vector)upVector
{
    return _cxxShip->upVector();
}
- (Vector)rightVector
{
    return _cxxShip->rightVector();
}
- (BOOL)scriptedMisjump
{
    return _cxxShip->scriptedMisjump();
}
- (void)setScriptedMisjump:(BOOL)newValue
{
    _cxxShip->setScriptedMisjump(newValue);
}
- (GLfloat)scriptedMisjumpRange
{
    return _cxxShip->scriptedMisjumpRange();
}
- (void)setScriptedMisjumpRange:(GLfloat)newValue
{
    _cxxShip->setScriptedMisjumpRange(newValue);
}
- (std::vector<oo::ObjCRef<Entity*>>)subEntities
{
    return _cxxShip->getSubEntities();
}
- (NSUInteger)subEntityCount
{
    return _cxxShip->subEntityCount();
}
- (BOOL)hasSubEntity:(Entity<OOSubEntity>*)sub
{
    return _cxxShip->hasSubEntity(sub);
}
- (std::vector<oo::ObjCRef<Entity*>>)subEntityEnumerator
{
    return _cxxShip->subEntityEnumerator();
}
- (std::vector<oo::ObjCRef<ShipEntity*>>)cxx_shipSubEntities
{
    return _cxxShip->shipSubEntities();
}
- (std::vector<oo::ObjCRef<OOFlasherEntity*>>)flasherEnumerator
{
    return _cxxShip->flasherEnumerator();
}
- (std::vector<oo::ObjCRef<OOExhaustPlumeEntity*>>)cxx_exhausts
{
    return _cxxShip->exhausts();
}
- (ShipEntity*)subEntityTakingDamage
{
    return _cxxShip->subEntityTakingDamage();
}
- (void)setSubEntityTakingDamage:(ShipEntity*)sub
{
    _cxxShip->setSubEntityTakingDamage(sub);
}
- (OOScript*)shipScript
{
    return _cxxShip->shipScript();
}
- (OOScript*)shipAIScript
{
    return _cxxShip->shipAIScript();
}
- (OOTimeAbsolute)shipAIScriptWakeTime
{
    return _cxxShip->shipAIScriptWakeTime();
}
- (void)setAIScriptWakeTime:(OOTimeAbsolute)t
{
    _cxxShip->setAIScriptWakeTime(t);
}
- (std::optional<std::string>)cxx_descriptionComponents
{
    return _cxxShip->cxx::ShipEntity::descriptionComponents();
}

@end

@implementation ShipEntity (OOSlice5)

- (BoundingBox)findBoundingBoxRelativeToPosition:(HPVector)opv i:(Vector)_i j:(Vector)_j k:(Vector)_k
{
    return _cxxShip->findBoundingBoxRelativeToPosition(opv, _i, _j, _k);
}
- (Octree*)octree
{
    return _cxxShip->getOctree();
}
- (float)volume
{
    return _cxxShip->volume();
}
- (GLfloat)doesHitLine:(HPVector)v0 v1:(HPVector)v1
{
    return _cxxShip->doesHitLine(v0, v1);
}
- (GLfloat)doesHitLine:(HPVector)v0 v1:(HPVector)v1 hitEntity:(ShipEntity**)hitEntity
{
    return _cxxShip->cxx::ShipEntity::doesHitLine(v0, v1, hitEntity);
}
- (GLfloat)doesHitLine:(HPVector)v0 v1:(HPVector)v1 withPosition:(HPVector)o i:(Vector)i j:(Vector)j k:(Vector)k
{
    return _cxxShip->doesHitLine(v0, v1, o, i, j, k);
}
- (void)wasAddedToUniverse
{
    _cxxShip->cxx::ShipEntity::wasAddedToUniverse();
}
- (void)wasRemovedFromUniverse
{
    _cxxShip->cxx::ShipEntity::wasRemovedFromUniverse();
}
- (HPVector)absoluteTractorPosition
{
    return _cxxShip->absoluteTractorPosition();
}
- (std::optional<std::string>)beaconCode
{
    return _cxxShip->beaconCode();
}
- (void)setBeaconCode:(const std::optional<std::string>&)bcode
{
    _cxxShip->setBeaconCode(bcode);
}
- (std::optional<std::string>)beaconLabel
{
    return _cxxShip->beaconLabel();
}
- (void)setBeaconLabel:(const std::optional<std::string>&)blabel
{
    _cxxShip->setBeaconLabel(blabel);
}
- (BOOL)isVisible
{
    return _cxxShip->cxx::ShipEntity::isVisible();
}
- (BOOL)isBeacon
{
    return _cxxShip->isBeacon();
}
- (id<OOHUDBeaconIcon>)beaconDrawable
{
    return _cxxShip->beaconDrawable();
}
- (Entity<OOBeaconEntity>*)prevBeacon
{
    return (Entity<OOBeaconEntity>*)_cxxShip->prevBeacon();
}
- (Entity<OOBeaconEntity>*)nextBeacon
{
    return (Entity<OOBeaconEntity>*)_cxxShip->nextBeacon();
}
- (void)setPrevBeacon:(Entity<OOBeaconEntity>*)beaconShip
{
    _cxxShip->setPrevBeacon(beaconShip);
}
- (void)setNextBeacon:(Entity<OOBeaconEntity>*)beaconShip
{
    _cxxShip->setNextBeacon(beaconShip);
}
- (void)setIsBoulder:(BOOL)flag
{
    _cxxShip->setIsBoulder(flag);
}
- (BOOL)isBoulder
{
    return _cxxShip->isBoulder();
}
- (BOOL)isMinable
{
    return _cxxShip->isMinable();
}
- (BOOL)countsAsKill
{
    return _cxxShip->countsAsKill();
}
- (void)setUpEscorts
{
    _cxxShip->setUpEscorts();
}
- (void)setUpMixedEscorts
{
    _cxxShip->setUpMixedEscorts();
}

@end

@implementation ShipEntity (OOSlice6)

- (void)setUpOneEscort:(ShipEntity*)escorter inGroup:(OOShipGroup*)escortGroup withRole:(const std::string&)escortRole atPosition:(HPVector)ex_pos andCount:(uint8_t)currentEscortCount
{
    _cxxShip->setUpOneEscort(escorter, escortGroup, escortRole, ex_pos, currentEscortCount);
}
- (std::optional<std::string>)cxx_shipDataKey
{
    return _cxxShip->shipDataKey();
}
- (std::optional<std::string>)cxx_shipDataKeyAutoRole
{
    return _cxxShip->shipDataKeyAutoRole();
}
- (void)cxx_setShipDataKey:(const std::optional<std::string>&)key
{
    _cxxShip->setShipDataKey(key);
}
- (oo::PList)cxx_shipInfoDictionary
{
    return _cxxShip->shipInfoDictionary();
}
- (std::vector<Vector>)cxx_weaponOffsetsFrom:(const oo::PList&)dict withKey:(const std::string&)key inMode:(const std::string&)mode
{
    return _cxxShip->weaponOffsetsFrom(dict, key, mode);
}
- (std::vector<Vector>)cxx_aftWeaponOffset
{
    return _cxxShip->getAftWeaponOffset();
}
- (std::vector<Vector>)cxx_forwardWeaponOffset
{
    return _cxxShip->getForwardWeaponOffset();
}
- (std::vector<Vector>)cxx_portWeaponOffset
{
    return _cxxShip->getPortWeaponOffset();
}
- (std::vector<Vector>)cxx_starboardWeaponOffset
{
    return _cxxShip->getStarboardWeaponOffset();
}
- (BOOL)isFrangible
{
    return _cxxShip->getIsFrangible();
}
- (BOOL)suppressFlightNotifications
{
    return _cxxShip->suppressFlightNotifications();
}
- (OOScanClass)scanClass
{
    return _cxxShip->cxx::ShipEntity::getScanClass();
}
- (BOOL)canCollide
{
    return _cxxShip->cxx::ShipEntity::canCollide();
}
- (BOOL)checkCloseCollisionWith:(Entity*)other
{
    return _cxxShip->cxx::ShipEntity::checkCloseCollisionWith(oo::ToCxx(other));
}
- (BoundingBox)findSubentityBoundingBox
{
    return _cxxShip->findSubentityBoundingBox();
}
- (Triangle)absoluteIJKForSubentity
{
    return _cxxShip->absoluteIJKForSubentity();
}
- (void)addSubentityToCollisionRadius:(Entity<OOSubEntity>*)subent
{
    _cxxShip->addSubentityToCollisionRadius(subent);
}
- (ShipEntity*)launchPodWithCrew:(const std::vector<oo::ObjCRef<OOCharacter*>>&)podCrew
{
    return _cxxShip->launchPodWithCrew(podCrew);
}
- (BOOL)validForAddToUniverse
{
    return _cxxShip->cxx::ShipEntity::validForAddToUniverse();
}

@end

@implementation ShipEntity (OOSlice7)

- (void)update:(OOTimeDelta)delta_t
{
    _cxxShip->cxx::ShipEntity::update(delta_t);
}

@end

@implementation ShipEntity (OOSlice8)

- (void)processBehaviour:(OOTimeDelta)delta_t
{
    _cxxShip->processBehaviour(delta_t);
}
- (void)noteFrustration:(const std::string&)context
{
    _cxxShip->noteFrustration(context);
}
- (void)respondToAttackFrom:(Entity*)from becauseOf:(Entity*)other
{
    _cxxShip->respondToAttackFrom(from, other);
}
- (BOOL)cxx_hasOneEquipmentItem:(const std::string&)itemKey includeWeapons:(BOOL)includeWeapons whileLoading:(BOOL)loading
{
    return _cxxShip->hasOneEquipmentItem(itemKey, includeWeapons, loading);
}
- (BOOL)cxx_hasOneEquipmentItem:(const std::string&)itemKey includeMissiles:(BOOL)includeMissiles whileLoading:(BOOL)loading
{
    return _cxxShip->hasOneEquipmentItemIncludingMissiles(itemKey, includeMissiles, loading);
}
- (BOOL)hasPrimaryWeapon:(OOWeaponType)weaponType
{
    return _cxxShip->cxx::ShipEntity::hasPrimaryWeapon(weaponType);
}
- (NSUInteger)cxx_countEquipmentItem:(const std::string&)eqkey
{
    return _cxxShip->countEquipmentItem(eqkey);
}
- (BOOL)hasEquipmentItem:(const oo::PList&)equipmentKeys includeWeapons:(BOOL)includeWeapons whileLoading:(BOOL)loading
{
    return _cxxShip->hasEquipmentItem(equipmentKeys, includeWeapons, loading);
}
- (BOOL)hasEquipmentItem:(const oo::PList&)equipmentKeys
{
    return _cxxShip->hasEquipmentItem(equipmentKeys);
}
- (BOOL)cxx_hasEquipmentItemProviding:(const std::string&)equipmentType
{
    return _cxxShip->hasEquipmentItemProviding(equipmentType);
}
- (std::optional<std::string>)cxx_equipmentItemProviding:(const std::string&)equipmentType
{
    return _cxxShip->equipmentItemProviding(equipmentType);
}
- (BOOL)hasAllEquipment:(const oo::PList&)equipmentKeys includeWeapons:(BOOL)includeWeapons whileLoading:(BOOL)loading
{
    return _cxxShip->hasAllEquipment(equipmentKeys, includeWeapons, loading);
}
- (BOOL)hasAllEquipment:(const oo::PList&)equipmentKeys
{
    return _cxxShip->hasAllEquipment(equipmentKeys);
}
- (BOOL)hasHyperspaceMotor
{
    return _cxxShip->hasHyperspaceMotor();
}
- (float)hyperspaceSpinTime
{
    return _cxxShip->hyperspaceSpinTime();
}
- (void)setHyperspaceSpinTime:(float)newValue
{
    _cxxShip->setHyperspaceSpinTime(newValue);
}

@end

@implementation ShipEntity (OOSlice9)

- (BOOL)canAddEquipment:(const std::string&)equipmentKeyIn inContext:(const std::string&)context
{
    return _cxxShip->cxx::ShipEntity::canAddEquipment(equipmentKeyIn, context);
}
- (OOWeaponFacingSet)weaponFacings
{
    return _cxxShip->weaponFacings();
}
- (OOWeaponType)weaponTypeIDForFacing:(OOWeaponFacing)facing strict:(BOOL)strict
{
    return _cxxShip->weaponTypeIDForFacing(facing, strict);
}
- (OOEquipmentType*)weaponTypeForFacing:(OOWeaponFacing)facing strict:(BOOL)strict
{
    return _cxxShip->cxx::ShipEntity::weaponTypeForFacing(facing, strict);
}
- (std::vector<oo::ObjCRef<OOEquipmentType*>>)missilesList
{
    return _cxxShip->cxx::ShipEntity::missilesList();
}
- (oo::PList)passengerListForScripting
{
    return _cxxShip->cxx::ShipEntity::passengerListForScripting();
}
- (oo::PList)parcelListForScripting
{
    return _cxxShip->cxx::ShipEntity::parcelListForScripting();
}
- (oo::PList)contractListForScripting
{
    return _cxxShip->cxx::ShipEntity::contractListForScripting();
}
- (OOEquipmentType*)generateMissileEquipmentTypeFrom:(const std::string&)role
{
    return _cxxShip->generateMissileEquipmentTypeFrom(role);
}
- (std::vector<oo::ObjCRef<OOEquipmentType*>>)cxx_equipmentListForScripting
{
    return _cxxShip->equipmentListForScripting();
}
- (BOOL)cxx_equipmentValidToAdd:(const std::string&)equipmentKey inContext:(const std::string&)context
{
    return _cxxShip->equipmentValidToAdd(equipmentKey, context);
}
- (BOOL)cxx_equipmentValidToAdd:(const std::string&)fullEquipmentKey whileLoading:(BOOL)loading inContext:(const std::string&)context
{
    return _cxxShip->equipmentValidToAdd(fullEquipmentKey, loading, context);
}
- (BOOL)setWeaponMount:(OOWeaponFacing)facing toWeapon:(const std::string&)eqKey
{
    return _cxxShip->cxx::ShipEntity::setWeaponMount(facing, eqKey);
}
- (BOOL)addEquipmentItem:(const std::string&)equipmentKey inContext:(const std::string&)context
{
    return _cxxShip->cxx::ShipEntity::addEquipmentItem(equipmentKey, context);
}
- (BOOL)addEquipmentItem:(const std::string&)equipmentKeyIn withValidation:(BOOL)validateAddition inContext:(const std::string&)context
{
    return _cxxShip->cxx::ShipEntity::addEquipmentItem(equipmentKeyIn, validateAddition, context);
}
- (std::vector<std::string>)cxx_equipmentKeys
{
    return _cxxShip->equipmentKeys();
}
- (NSUInteger)equipmentCount
{
    return _cxxShip->equipmentCount();
}

@end

@implementation ShipEntity (OOSlice10)

- (void)removeEquipmentItem:(const std::string&)equipmentKey
{
    _cxxShip->cxx::ShipEntity::removeEquipmentItem(equipmentKey);
}
- (BOOL)removeExternalStore:(OOEquipmentType*)eqType
{
    return _cxxShip->cxx::ShipEntity::removeExternalStore(eqType);
}
- (OOEquipmentType*)verifiedMissileTypeFromRole:(const std::string&)requestedRole
{
    return _cxxShip->verifiedMissileTypeFromRole(requestedRole);
}
- (OOEquipmentType*)selectMissile
{
    return _cxxShip->selectMissile();
}
- (void)removeAllEquipment
{
    _cxxShip->removeAllEquipment();
}
- (OOCreditsQuantity)removeMissiles
{
    return _cxxShip->cxx::ShipEntity::removeMissiles();
}
- (NSUInteger)parcelCount
{
    return _cxxShip->cxx::ShipEntity::parcelCount();
}
- (NSUInteger)passengerCount
{
    return _cxxShip->cxx::ShipEntity::passengerCount();
}
- (NSUInteger)passengerCapacity
{
    return _cxxShip->cxx::ShipEntity::passengerCapacity();
}
- (NSUInteger)missileCount
{
    return _cxxShip->missileCount();
}
- (NSUInteger)missileCapacity
{
    return _cxxShip->missileCapacity();
}
- (NSUInteger)extraCargo
{
    return _cxxShip->extraCargo();
}
- (BOOL)hasScoop
{
    return _cxxShip->hasScoop();
}
- (BOOL)hasFuelScoop
{
    return _cxxShip->hasFuelScoop();
}
- (BOOL)hasCargoScoop
{
    return _cxxShip->hasCargoScoop();
}
- (BOOL)hasECM
{
    return _cxxShip->hasECM();
}
- (BOOL)hasCloakingDevice
{
    return _cxxShip->hasCloakingDevice();
}
- (BOOL)hasMilitaryScannerFilter
{
    return _cxxShip->hasMilitaryScannerFilter();
}
- (BOOL)hasMilitaryJammer
{
    return _cxxShip->hasMilitaryJammer();
}
- (BOOL)hasExpandedCargoBay
{
    return _cxxShip->hasExpandedCargoBay();
}
- (BOOL)hasShieldBooster
{
    return _cxxShip->hasShieldBooster();
}
- (BOOL)hasMilitaryShieldEnhancer
{
    return _cxxShip->hasMilitaryShieldEnhancer();
}
- (BOOL)hasHeatShield
{
    return _cxxShip->hasHeatShield();
}
- (BOOL)hasFuelInjection
{
    return _cxxShip->hasFuelInjection();
}
- (BOOL)hasCascadeMine
{
    return _cxxShip->hasCascadeMine();
}
- (BOOL)hasEscapePod
{
    return _cxxShip->hasEscapePod();
}
- (BOOL)hasDockingComputer
{
    return _cxxShip->hasDockingComputer();
}
- (BOOL)hasGalacticHyperdrive
{
    return _cxxShip->hasGalacticHyperdrive();
}
- (float)shieldBoostFactor
{
    return _cxxShip->shieldBoostFactor();
}
- (float)maxForwardShieldLevel
{
    return _cxxShip->cxx::ShipEntity::maxForwardShieldLevel();
}
- (float)maxAftShieldLevel
{
    return _cxxShip->cxx::ShipEntity::maxAftShieldLevel();
}
- (float)shieldRechargeRate
{
    return _cxxShip->shieldRechargeRate();
}
- (double)maxHyperspaceDistance
{
    return _cxxShip->maxHyperspaceDistance();
}

@end

@implementation ShipEntity (OOSlice11)

- (float)afterburnerFactor
{
    return _cxxShip->afterburnerFactor();
}
- (float)afterburnerRate
{
    return _cxxShip->afterburnerRate();
}
- (void)setAfterburnerFactor:(GLfloat)newValue
{
    _cxxShip->setAfterburnerFactor(newValue);
}
- (void)setAfterburnerRate:(GLfloat)newValue
{
    _cxxShip->setAfterburnerRate(newValue);
}
- (float)maxThrust
{
    return _cxxShip->maxThrust();
}
- (void)setMaxThrust:(GLfloat)newValue
{
    _cxxShip->setMaxThrust(newValue);
}
- (float)thrust
{
    return _cxxShip->getThrust();
}
- (void)behaviour_stop_still:(double)delta_t
{
    _cxxShip->behaviour_stop_still(delta_t);
}
- (void)behaviour_idle:(double)delta_t
{
    _cxxShip->behaviour_idle(delta_t);
}
- (void)behaviour_tumble:(double)delta_t
{
    _cxxShip->behaviour_tumble(delta_t);
}
- (void)behaviour_tractored:(double)delta_t
{
    _cxxShip->behaviour_tractored(delta_t);
}
- (void)behaviour_track_target:(double)delta_t
{
    _cxxShip->behaviour_track_target(delta_t);
}
- (void)behaviour_intercept_target:(double)delta_t
{
    _cxxShip->behaviour_intercept_target(delta_t);
}
- (void)behaviour_attack_break_off_target:(double)delta_t
{
    _cxxShip->behaviour_attack_break_off_target(delta_t);
}
- (void)behaviour_attack_slow_dogfight:(double)delta_t
{
    _cxxShip->behaviour_attack_slow_dogfight(delta_t);
}
- (void)behaviour_evasive_action:(double)delta_t
{
    _cxxShip->behaviour_evasive_action(delta_t);
}

@end

@implementation ShipEntity (OOSlice12)

- (void)behaviour_attack_target:(double)delta_t
{
    _cxxShip->behaviour_attack_target(delta_t);
}
- (void)behaviour_attack_broadside:(double)delta_t
{
    _cxxShip->behaviour_attack_broadside(delta_t);
}
- (void)behaviour_attack_broadside_left:(double)delta_t
{
    _cxxShip->behaviour_attack_broadside_left(delta_t);
}
- (void)behaviour_attack_broadside_right:(double)delta_t
{
    _cxxShip->behaviour_attack_broadside_right(delta_t);
}
- (void)behaviour_attack_broadside_target:(double)delta_t leftside:(BOOL)leftside
{
    _cxxShip->behaviour_attack_broadside_target(delta_t, leftside);
}
- (void)behaviour_close_to_broadside_range:(double)delta_t
{
    _cxxShip->behaviour_close_to_broadside_range(delta_t);
}
- (void)behaviour_close_with_target:(double)delta_t
{
    _cxxShip->behaviour_close_with_target(delta_t);
}

@end

@implementation ShipEntity (OOSlice13)

- (void)behaviour_attack_sniper:(double)delta_t
{
    _cxxShip->behaviour_attack_sniper(delta_t);
}
- (void)behaviour_fly_to_target_six:(double)delta_t
{
    _cxxShip->behaviour_fly_to_target_six(delta_t);
}
- (void)behaviour_attack_mining_target:(double)delta_t
{
    _cxxShip->behaviour_attack_mining_target(delta_t);
}
- (void)behaviour_attack_fly_to_target:(double)delta_t
{
    _cxxShip->behaviour_attack_fly_to_target(delta_t);
}

@end

@implementation ShipEntity (OOSlice14)

- (void)behaviour_attack_fly_from_target:(double)delta_t
{
    _cxxShip->behaviour_attack_fly_from_target(delta_t);
}
- (void)behaviour_running_defense:(double)delta_t
{
    _cxxShip->behaviour_running_defense(delta_t);
}
- (void)behaviour_flee_target:(double)delta_t
{
    _cxxShip->behaviour_flee_target(delta_t);
}
- (void)behaviour_fly_range_from_destination:(double)delta_t
{
    _cxxShip->behaviour_fly_range_from_destination(delta_t);
}
- (void)behaviour_face_destination:(double)delta_t
{
    _cxxShip->behaviour_face_destination(delta_t);
}
- (void)behaviour_land_on_planet:(double)delta_t
{
    _cxxShip->behaviour_land_on_planet(delta_t);
}
- (void)behaviour_formation_form_up:(double)delta_t
{
    _cxxShip->behaviour_formation_form_up(delta_t);
}

@end

@implementation ShipEntity (OOSlice15)

- (void)behaviour_fly_to_destination:(double)delta_t
{
    _cxxShip->behaviour_fly_to_destination(delta_t);
}
- (void)behaviour_fly_from_destination:(double)delta_t
{
    _cxxShip->behaviour_fly_from_destination(delta_t);
}
- (void)behaviour_avoid_collision:(double)delta_t
{
    _cxxShip->behaviour_avoid_collision(delta_t);
}
- (void)behaviour_track_as_turret:(double)delta_t
{
    _cxxShip->behaviour_track_as_turret(delta_t);
}
- (void)behaviour_fly_thru_navpoints:(double)delta_t
{
    _cxxShip->behaviour_fly_thru_navpoints(delta_t);
}
- (void)behaviour_scripted_ai:(double)delta_t
{
    _cxxShip->behaviour_scripted_ai(delta_t);
}
- (float)reactionTime
{
    return _cxxShip->getReactionTime();
}
- (void)setReactionTime:(float)newReactionTime
{
    _cxxShip->setReactionTime(newReactionTime);
}
- (HPVector)calculateTargetPosition
{
    return _cxxShip->calculateTargetPosition();
}

@end

@implementation ShipEntity (OOSlice16)

- (void)startTrackingCurve
{
    _cxxShip->startTrackingCurve();
}
- (void)updateTrackingCurve
{
    _cxxShip->updateTrackingCurve();
}
- (void)calculateTrackingCurve
{
    _cxxShip->calculateTrackingCurve();
}
- (void)drawImmediate:(bool)immediate translucent:(bool)translucent
{
    _cxxShip->cxx::ShipEntity::drawImmediate(immediate, translucent);
}
#ifdef OO_DEBUG_MONITOR_ENABLED
- (void)drawDebugStuff
{
    _cxxShip->drawDebugStuff();
}
#endif
- (void)drawSubEntityImmediate:(bool)immediate translucent:(bool)translucent
{
    _cxxShip->drawSubEntityImmediate(immediate, translucent);
}
- (GLfloat*)scannerDisplayColorForShip:(ShipEntity*)otherShip isHostile:(BOOL)isHostile flash:(BOOL)flash scannerDisplayColor1:(OOColor*)scannerDisplayColor1 scannerDisplayColor2:(OOColor*)scannerDisplayColor2 scannerDisplayColorH1:(OOColor*)scannerDisplayColorH1 scannerDisplayColorH2:(OOColor*)scannerDisplayColorH2
{
    return _cxxShip->scannerDisplayColorForShip(otherShip, isHostile, flash, scannerDisplayColor1, scannerDisplayColor2, scannerDisplayColorH1, scannerDisplayColorH2);
}
- (void)setScannerDisplayColor1:(OOColor*)color
{
    _cxxShip->setScannerDisplayColor1(color);
}
- (void)setScannerDisplayColor2:(OOColor*)color
{
    _cxxShip->setScannerDisplayColor2(color);
}
- (OOColor*)scannerDisplayColor1
{
    return _cxxShip->scannerDisplayColor1();
}
- (OOColor*)scannerDisplayColor2
{
    return _cxxShip->scannerDisplayColor2();
}
- (void)setScannerDisplayColorHostile1:(OOColor*)color
{
    _cxxShip->setScannerDisplayColorHostile1(color);
}
- (void)setScannerDisplayColorHostile2:(OOColor*)color
{
    _cxxShip->setScannerDisplayColorHostile2(color);
}
- (OOColor*)scannerDisplayColorHostile1
{
    return _cxxShip->scannerDisplayColorHostile1();
}
- (OOColor*)scannerDisplayColorHostile2
{
    return _cxxShip->scannerDisplayColorHostile2();
}
- (BOOL)isCloaked
{
    return _cxxShip->isCloaked();
}
- (BOOL)cloakPassive
{
    return _cxxShip->getCloakPassive();
}
- (void)setCloaked:(BOOL)cloak
{
    _cxxShip->setCloaked(cloak);
}
- (BOOL)hasAutoCloak
{
    return _cxxShip->hasAutoCloak();
}
- (void)setAutoCloak:(BOOL)automatic
{
    _cxxShip->setAutoCloak(automatic);
}
- (BOOL)isJammingScanning
{
    return _cxxShip->isJammingScanning();
}
- (void)addSubEntity:(Entity<OOSubEntity>*)sub
{
    _cxxShip->addSubEntity(sub);
}
- (void)setOwner:(Entity*)who_owns_entity
{
    _cxxShip->cxx::ShipEntity::setOwner(oo::ToCxx(who_owns_entity));
}
- (void)applyThrust:(double)delta_t
{
    _cxxShip->applyThrust(delta_t);
}
- (void)orientationChanged
{
    _cxxShip->cxx::ShipEntity::orientationChanged();
}

@end

@implementation ShipEntity (OOSlice17)

- (void)applyRoll:(GLfloat)roll1 andClimb:(GLfloat)climb1
{
    _cxxShip->cxx::ShipEntity::applyRoll(roll1, climb1);
}
- (void)applyRoll:(GLfloat)roll1 climb:(GLfloat)climb1 andYaw:(GLfloat)yaw1
{
    _cxxShip->cxx::ShipEntity::applyRoll(roll1, climb1, yaw1);
}
- (void)applyAttitudeChanges:(double)delta_t
{
    _cxxShip->cxx::ShipEntity::applyAttitudeChanges(delta_t);
}
- (void)avoidCollision
{
    _cxxShip->avoidCollision();
}
- (void)resumePostProximityAlert
{
    _cxxShip->resumePostProximityAlert();
}
- (double)messageTime
{
    return _cxxShip->getMessageTime();
}
- (void)setMessageTime:(double)value
{
    _cxxShip->setMessageTime(value);
}
- (OOShipGroup*)group
{
    return _cxxShip->group();
}
- (void)setGroup:(OOShipGroup*)group
{
    _cxxShip->setGroup(group);
}
- (OOShipGroup*)escortGroup
{
    return _cxxShip->escortGroup();
}
- (void)setEscortGroup:(OOShipGroup*)group
{
    _cxxShip->setEscortGroup(group);
}
#ifdef OO_DEBUG_MONITOR_ENABLED
- (OOShipGroup*)rawEscortGroup
{
    return _cxxShip->rawEscortGroup();
}
#endif
- (OOShipGroup*)stationGroup
{
    return _cxxShip->stationGroup();
}
- (BOOL)hasEscorts
{
    return _cxxShip->hasEscorts();
}
- (std::vector<oo::ObjCRef<ShipEntity*>>)cxx_escorts
{
    return _cxxShip->escorts();
}
- (std::vector<oo::ObjCRef<ShipEntity*>>)escortArray
{
    return _cxxShip->escortArray();
}
- (uint8_t)escortCount
{
    return _cxxShip->escortCount();
}
- (uint8_t)pendingEscortCount
{
    return _cxxShip->pendingEscortCount();
}
- (void)setPendingEscortCount:(uint8_t)count
{
    _cxxShip->setPendingEscortCount(count);
}
- (uint8_t)maxEscortCount
{
    return _cxxShip->maxEscortCount();
}
- (void)setMaxEscortCount:(uint8_t)newCount
{
    _cxxShip->setMaxEscortCount(newCount);
}
- (NSUInteger)turretCount
{
    return _cxxShip->turretCount();
}
- (Entity*)proximityAlert
{
    return _cxxShip->proximityAlert();
}
- (void)setProximityAlert:(ShipEntity*)other
{
    _cxxShip->setProximityAlert(other);
}
- (std::optional<std::string>)cxx_name
{
    return _cxxShip->getName();
}
- (std::optional<std::string>)cxx_shipUniqueName
{
    return _cxxShip->getShipUniqueName();
}
- (std::optional<std::string>)cxx_shipClassName
{
    return _cxxShip->getShipClassName();
}
- (std::optional<std::string>)displayName
{
    return _cxxShip->getDisplayName();
}
- (std::optional<std::string>)cxx_scanDescriptionForScripting
{
    return _cxxShip->scanDescriptionForScripting();
}
- (std::optional<std::string>)cxx_scanDescription
{
    return _cxxShip->scanDescription();
}
- (void)cxx_setName:(const std::optional<std::string>&)inName
{
    _cxxShip->cxx::ShipEntity::setName(inName);
}
- (void)cxx_setShipUniqueName:(const std::optional<std::string>&)inName
{
    _cxxShip->setShipUniqueName(inName);
}
- (void)cxx_setShipClassName:(const std::optional<std::string>&)inName
{
    _cxxShip->setShipClassName(inName);
}
- (void)cxx_setDisplayName:(const std::optional<std::string>&)inName
{
    _cxxShip->setDisplayName(inName);
}
- (void)cxx_setScanDescription:(const std::optional<std::string>&)inName
{
    _cxxShip->setScanDescription(inName);
}

@end

@implementation ShipEntity (OOSlice18)

- (std::optional<std::string>)identFromShip:(ShipEntity*)otherShip
{
    return _cxxShip->identFromShip(otherShip);
}
- (BOOL)hasRole:(const std::string&)role
{
    return _cxxShip->hasRole(role);
}
- (OORoleSet*)roleSet
{
    return _cxxShip->getRoleSet();
}
- (void)addRole:(const std::string&)role
{
    _cxxShip->addRole(role);
}
- (void)cxx_addRole:(const std::string&)role withProbability:(float)probability
{
    _cxxShip->addRole(role, probability);
}
- (void)cxx_removeRole:(const std::string&)role
{
    _cxxShip->removeRole(role);
}
- (std::optional<std::string>)cxx_primaryRole
{
    return _cxxShip->getPrimaryRole();
}
- (void)setPrimaryRole:(const std::string&)role
{
    _cxxShip->setPrimaryRole(role);
}
- (BOOL)cxx_hasPrimaryRole:(const std::string&)role
{
    return _cxxShip->hasPrimaryRole(role);
}
- (BOOL)isPolice
{
    return _cxxShip->isPolice();
}
- (BOOL)isThargoid
{
    return _cxxShip->isThargoid();
}
- (BOOL)isTrader
{
    return _cxxShip->isTrader();
}
- (BOOL)isPirate
{
    return _cxxShip->isPirate();
}
- (BOOL)isMissile
{
    return _cxxShip->getIsMissile();
}
- (BOOL)isMine
{
    return _cxxShip->isMine();
}
- (BOOL)isWeapon
{
    return _cxxShip->isWeapon();
}
- (BOOL)isEscort
{
    return _cxxShip->isEscort();
}
- (BOOL)isShuttle
{
    return _cxxShip->isShuttle();
}
- (BOOL)isTurret
{
    return _cxxShip->isTurret();
}
- (BOOL)isPirateVictim
{
    return _cxxShip->isPirateVictim();
}
- (BOOL)isExplicitlyUnpiloted
{
    return _cxxShip->isExplicitlyUnpiloted();
}
- (BOOL)isUnpiloted
{
    return _cxxShip->cxx::ShipEntity::isUnpiloted();
}
- (BOOL)hasHostileTarget
{
    return _cxxShip->cxx::ShipEntity::hasHostileTarget();
}
- (BOOL)isHostileTo:(Entity*)entity
{
    return _cxxShip->isHostileTo(entity);
}
- (GLfloat)weaponRange
{
    return _cxxShip->getWeaponRange();
}
- (void)setWeaponRange:(GLfloat)value
{
    _cxxShip->setWeaponRange(value);
}
- (void)setWeaponDataFromType:(OOWeaponType)weapon_type
{
    _cxxShip->setWeaponDataFromType(weapon_type);
}
- (float)energyRechargeRate
{
    return _cxxShip->energyRechargeRate();
}
- (void)setEnergyRechargeRate:(GLfloat)newValue
{
    _cxxShip->setEnergyRechargeRate(newValue);
}
- (float)weaponRechargeRate
{
    return _cxxShip->weaponRechargeRate();
}
- (void)setWeaponRechargeRate:(float)value
{
    _cxxShip->setWeaponRechargeRate(value);
}
- (void)setWeaponEnergy:(float)value
{
    _cxxShip->setWeaponEnergy(value);
}
- (OOWeaponFacing)currentWeaponFacing
{
    return _cxxShip->getCurrentWeaponFacing();
}
- (GLfloat)scannerRange
{
    return _cxxShip->getScannerRange();
}
- (void)setScannerRange:(GLfloat)value
{
    _cxxShip->setScannerRange(value);
}
- (Vector)reference
{
    return _cxxShip->getReference();
}
- (void)setReference:(Vector)v
{
    _cxxShip->setReference(v);
}
- (BOOL)reportAIMessages
{
    return _cxxShip->getReportAIMessages();
}
- (void)setReportAIMessages:(BOOL)yn
{
    _cxxShip->setReportAIMessages(yn);
}
- (void)transitionToAegisNone
{
    _cxxShip->transitionToAegisNone();
}
- (OOPlanetEntity*)findNearestPlanet
{
    return _cxxShip->findNearestPlanet();
}
- (Entity<OOStellarBody>*)findNearestStellarBody
{
    return (Entity<OOStellarBody>*)_cxxShip->findNearestStellarBody();
}
- (OOPlanetEntity*)findNearestPlanetExcludingMoons
{
    return _cxxShip->findNearestPlanetExcludingMoons();
}

@end

@implementation ShipEntity (OOSlice19)

- (OOAegisStatus)checkForAegis
{
    return _cxxShip->checkForAegis();
}
- (void)forceAegisCheck
{
    _cxxShip->forceAegisCheck();
}
- (BOOL)withinStationAegis
{
    return _cxxShip->withinStationAegis();
}
- (Entity<OOStellarBody>*)lastAegisLock
{
    return (Entity<OOStellarBody>*)_cxxShip->lastAegisLock();
}
- (void)setLastAegisLock:(Entity<OOStellarBody>*)lastAegisLock
{
    _cxxShip->setLastAegisLock(lastAegisLock);
}
- (OOSystemID)homeSystem
{
    return _cxxShip->homeSystem();
}
- (OOSystemID)destinationSystem
{
    return _cxxShip->destinationSystem();
}
- (void)setHomeSystem:(OOSystemID)s
{
    _cxxShip->setHomeSystem(s);
}
- (void)setDestinationSystem:(OOSystemID)s
{
    _cxxShip->setDestinationSystem(s);
}
- (void)setStatus:(OOEntityStatus)stat
{
    _cxxShip->cxx::ShipEntity::setStatus(stat);
}
- (void)setLaunchDelay:(double)delay
{
    _cxxShip->setLaunchDelay(delay);
}
- (std::optional<std::vector<oo::ObjCRef<OOCharacter*>>>)cxx_crew
{
    return _cxxShip->getCrew();
}
- (void)cxx_setCrew:(const std::optional<std::vector<oo::ObjCRef<OOCharacter*>>>&)crewArray
{
    _cxxShip->setCrew(crewArray);
}
- (void)cxx_setSingleCrewWithRole:(const std::string&)crewRole
{
    _cxxShip->setSingleCrewWithRole(crewRole);
}
- (std::vector<oo::PList>)cxx_crewForScripting
{
    return _cxxShip->crewForScripting();
}
- (void)setStateMachine:(const std::string&)smName
{
    _cxxShip->setStateMachine(smName);
}
- (void)setAI:(AI*)ai
{
    _cxxShip->setAI(ai);
}
- (AI*)getAI
{
    return _cxxShip->getAI();
}
- (BOOL)hasAutoAI
{
    return _cxxShip->hasAutoAI();
}
- (BOOL)hasNewAI
{
    return _cxxShip->hasNewAI();
}
- (BOOL)hasAutoWeapons
{
    return _cxxShip->hasAutoWeapons();
}
- (void)cxx_setShipScript:(const std::optional<std::string>&)script_name
{
    _cxxShip->setShipScript(script_name);
}
- (double)frustration
{
    return _cxxShip->getFrustration();
}
- (OOFuelQuantity)fuel
{
    return _cxxShip->getFuel();
}
- (void)setFuel:(OOFuelQuantity)amount
{
    _cxxShip->setFuel(amount);
}
- (OOFuelQuantity)fuelCapacity
{
    return _cxxShip->fuelCapacity();
}
- (GLfloat)fuelChargeRate
{
    return _cxxShip->cxx::ShipEntity::fuelChargeRate();
}

@end

@implementation ShipEntity (OOSlice20)

- (void)applySticks:(double)delta_t
{
    _cxxShip->applySticks(delta_t);
}
- (void)setRoll:(double)amount
{
    _cxxShip->setRoll(amount);
}
- (void)setRawRoll:(double)amount
{
    _cxxShip->setRawRoll(amount);
}
- (void)setPitch:(double)amount
{
    _cxxShip->setPitch(amount);
}
- (void)setYaw:(double)amount
{
    _cxxShip->setYaw(amount);
}
- (void)setThrust:(double)amount
{
    _cxxShip->setThrust(amount);
}
- (void)setThrustForDemo:(float)factor
{
    _cxxShip->setThrustForDemo(factor);
}
- (void)setBounty:(OOCreditsQuantity)amount
{
    _cxxShip->cxx::ShipEntity::setBounty(amount);
}
- (void)setBounty:(OOCreditsQuantity)amount withReason:(OOLegalStatusReason)reason
{
    _cxxShip->cxx::ShipEntity::setBounty(amount, reason);
}
- (void)setBounty:(OOCreditsQuantity)amount withReasonAsString:(const std::string&)reason
{
    _cxxShip->cxx::ShipEntity::setBounty(amount, reason);
}
- (OOCreditsQuantity)bounty
{
    return _cxxShip->cxx::ShipEntity::getBounty();
}
- (int)legalStatus
{
    return _cxxShip->cxx::ShipEntity::legalStatus();
}
- (void)cxx_setCommodity:(const std::string&)co_type andAmount:(OOCargoQuantity)co_amount
{
    _cxxShip->setCommodity(co_type, co_amount);
}
- (void)cxx_setCommodityForPod:(const std::optional<std::string>&)co_type andAmount:(OOCargoQuantity)co_amount
{
    _cxxShip->setCommodityForPod(co_type, co_amount);
}
- (std::optional<std::string>)cxx_commodityType
{
    return _cxxShip->commodityType();
}
- (OOCargoQuantity)commodityAmount
{
    return _cxxShip->commodityAmount();
}
- (OOCargoQuantity)maxAvailableCargoSpace
{
    return _cxxShip->maxAvailableCargoSpace();
}
- (void)setMaxAvailableCargoSpace:(OOCargoQuantity)newValue
{
    _cxxShip->setMaxAvailableCargoSpace(newValue);
}
- (OOCargoQuantity)availableCargoSpace
{
    return _cxxShip->availableCargoSpace();
}
- (OOCargoQuantity)cargoQuantityOnBoard
{
    return _cxxShip->cxx::ShipEntity::cargoQuantityOnBoard();
}
- (OOCargoType)cargoType
{
    return _cxxShip->cargoType();
}
- (std::vector<oo::ObjCRef<ShipEntity*>>*)cxx_cargo
{
    return _cxxShip->getCargo();
}
- (NSUInteger)cxx_cargoCount
{
    return _cxxShip->cargoCount();
}
- (oo::PList)cargoListForScripting
{
    return _cxxShip->cxx::ShipEntity::cargoListForScripting();
}
- (void)setCargo:(const std::vector<oo::ObjCRef<ShipEntity*>>&)some_cargo
{
    _cxxShip->setCargo(some_cargo);
}
- (BOOL)cxx_addCargo:(const std::vector<oo::ObjCRef<ShipEntity*>>&)some_cargo
{
    return _cxxShip->addCargo(some_cargo);
}
- (BOOL)cxx_removeCargo:(const std::string&)commodity amount:(OOCargoQuantity)amount
{
    return _cxxShip->removeCargo(commodity, amount);
}
- (BOOL)showScoopMessage
{
    return _cxxShip->showScoopMessage();
}
- (OOCargoFlag)cargoFlag
{
    return _cxxShip->cargoFlag();
}
- (void)setCargoFlag:(OOCargoFlag)flag
{
    _cxxShip->setCargoFlag(flag);
}
- (void)setSpeed:(double)amount
{
    _cxxShip->setSpeed(amount);
}
- (void)setDesiredSpeed:(double)amount
{
    _cxxShip->setDesiredSpeed(amount);
}
- (double)desiredSpeed
{
    return _cxxShip->desiredSpeed();
}

@end

@implementation ShipEntity (OOSlice21)

- (double)desiredRange
{
    return _cxxShip->desiredRange();
}
- (void)setDesiredRange:(double)amount
{
    _cxxShip->setDesiredRange(amount);
}
- (double)cruiseSpeed
{
    return _cxxShip->getCruiseSpeed();
}
- (void)increase_flight_speed:(double)delta
{
    _cxxShip->increase_flight_speed(delta);
}
- (void)decrease_flight_speed:(double)delta
{
    _cxxShip->decrease_flight_speed(delta);
}
- (void)increase_flight_roll:(double)delta
{
    _cxxShip->increase_flight_roll(delta);
}
- (void)decrease_flight_roll:(double)delta
{
    _cxxShip->decrease_flight_roll(delta);
}
- (void)increase_flight_pitch:(double)delta
{
    _cxxShip->increase_flight_pitch(delta);
}
- (void)decrease_flight_pitch:(double)delta
{
    _cxxShip->decrease_flight_pitch(delta);
}
- (void)increase_flight_yaw:(double)delta
{
    _cxxShip->increase_flight_yaw(delta);
}
- (void)decrease_flight_yaw:(double)delta
{
    _cxxShip->decrease_flight_yaw(delta);
}
- (GLfloat)flightRoll
{
    return _cxxShip->getFlightRoll();
}
- (GLfloat)flightPitch
{
    return _cxxShip->getFlightPitch();
}
- (GLfloat)flightYaw
{
    return _cxxShip->getFlightYaw();
}
- (GLfloat)flightSpeed
{
    return _cxxShip->getFlightSpeed();
}
- (GLfloat)maxFlightPitch
{
    return _cxxShip->maxFlightPitch();
}
- (GLfloat)maxFlightSpeed
{
    return _cxxShip->getMaxFlightSpeed();
}
- (GLfloat)maxFlightRoll
{
    return _cxxShip->maxFlightRoll();
}
- (GLfloat)maxFlightYaw
{
    return _cxxShip->maxFlightYaw();
}
- (void)setMaxFlightPitch:(GLfloat)newValue
{
    _cxxShip->cxx::ShipEntity::setMaxFlightPitch(newValue);
}
- (void)setMaxFlightSpeed:(GLfloat)newValue
{
    _cxxShip->setMaxFlightSpeed(newValue);
}
- (void)setMaxFlightRoll:(GLfloat)newValue
{
    _cxxShip->cxx::ShipEntity::setMaxFlightRoll(newValue);
}
- (void)setMaxFlightYaw:(GLfloat)newValue
{
    _cxxShip->cxx::ShipEntity::setMaxFlightYaw(newValue);
}
- (GLfloat)speedFactor
{
    return _cxxShip->speedFactor();
}
- (GLfloat)temperature
{
    return _cxxShip->temperature();
}
- (void)setTemperature:(GLfloat)value
{
    _cxxShip->setTemperature(value);
}
- (float)randomEjectaTemperature
{
    return _cxxShip->randomEjectaTemperature();
}
- (float)randomEjectaTemperatureWithMaxFactor:(float)factor
{
    return _cxxShip->randomEjectaTemperatureWithMaxFactor(factor);
}
- (GLfloat)heatInsulation
{
    return _cxxShip->heatInsulation();
}
- (void)setHeatInsulation:(GLfloat)value
{
    _cxxShip->setHeatInsulation(value);
}
- (int)damage
{
    return _cxxShip->damage();
}
- (void)dealEnergyDamage:(GLfloat)baseDamage atRange:(GLfloat)range withBias:(GLfloat)velocityBias
{
    _cxxShip->dealEnergyDamage(baseDamage, range, velocityBias);
}
- (void)dealEnergyDamageWithinDesiredRange
{
    _cxxShip->dealEnergyDamageWithinDesiredRange();
}
- (void)dealMomentumWithinDesiredRange:(double)amount
{
    _cxxShip->dealMomentumWithinDesiredRange(amount);
}
- (BOOL)isHulk
{
    return _cxxShip->getIsHulk();
}
- (void)setHulk:(BOOL)isNowHulk
{
    _cxxShip->setHulk(isNowHulk);
}
- (void)noteTakingDamage:(double)amount from:(Entity*)entity type:(OOShipDamageType)type
{
    _cxxShip->cxx::ShipEntity::noteTakingDamage(amount, entity, type);
}
- (void)noteKilledBy:(Entity*)whom damageType:(OOShipDamageType)type
{
    _cxxShip->noteKilledBy(whom, type);
}

@end

@implementation ShipEntity (OOSlice22)

- (void)getDestroyedBy:(Entity*)whom damageType:(OOShipDamageType)type
{
    _cxxShip->cxx::ShipEntity::getDestroyedBy(whom, type);
}
- (void)rescaleBy:(GLfloat)factor
{
    _cxxShip->rescaleBy(factor);
}
- (void)rescaleBy:(GLfloat)factor writeToCache:(BOOL)writeToCache
{
    _cxxShip->rescaleBy(factor, writeToCache);
}
- (void)releaseCargoPodsDebris
{
    _cxxShip->releaseCargoPodsDebris();
}
- (void)setIsWreckage:(BOOL)isw
{
    _cxxShip->setIsWreckage(isw);
}
- (BOOL)showDamage
{
    return _cxxShip->showDamage();
}
- (void)becomeExplosion
{
    _cxxShip->cxx::ShipEntity::becomeExplosion();
}
- (void)becomeEnergyBlast
{
    _cxxShip->cxx::ShipEntity::becomeEnergyBlast();
}
- (void)broadcastEnergyBlastImminent
{
    _cxxShip->broadcastEnergyBlastImminent();
}
- (void)removeExhaust:(OOExhaustPlumeEntity*)exhaust
{
    _cxxShip->removeExhaust(exhaust);
}

@end

@implementation ShipEntity (OOSlice23)

- (void)removeFlasher:(OOFlasherEntity*)flasher
{
    _cxxShip->removeFlasher(flasher);
}
- (void)subEntityDied:(ShipEntity*)sub
{
    _cxxShip->subEntityDied(sub);
}
- (void)subEntityReallyDied:(ShipEntity*)sub
{
    _cxxShip->cxx::ShipEntity::subEntityReallyDied(sub);
}
- (Vector)positionOffsetForAlignment:(const std::string&)align
{
    return _cxxShip->positionOffsetForAlignment(align);
}
- (void)becomeLargeExplosion:(double)factor
{
    _cxxShip->cxx::ShipEntity::becomeLargeExplosion(factor);
}
- (void)collectBountyFor:(ShipEntity*)other
{
    _cxxShip->cxx::ShipEntity::collectBountyFor(other);
}
- (OOComparisonResult)compareBeaconCodeWith:(Entity<OOBeaconEntity>*)other
{
    return _cxxShip->compareBeaconCodeWith(other);
}
- (GLfloat)weaponRecoveryTime
{
    return _cxxShip->weaponRecoveryTime();
}
- (GLfloat)laserHeatLevel
{
    return _cxxShip->cxx::ShipEntity::laserHeatLevel();
}
- (GLfloat)laserHeatLevelAft
{
    return _cxxShip->cxx::ShipEntity::laserHeatLevelAft();
}
- (GLfloat)laserHeatLevelForward
{
    return _cxxShip->cxx::ShipEntity::laserHeatLevelForward();
}
- (GLfloat)laserHeatLevelPort
{
    return _cxxShip->cxx::ShipEntity::laserHeatLevelPort();
}
- (GLfloat)laserHeatLevelStarboard
{
    return _cxxShip->cxx::ShipEntity::laserHeatLevelStarboard();
}
- (GLfloat)hullHeatLevel
{
    return _cxxShip->hullHeatLevel();
}
- (GLfloat)entityPersonality
{
    return _cxxShip->entityPersonality();
}
- (GLint)entityPersonalityInt
{
    return _cxxShip->entityPersonalityInt();
}
- (uint32_t)randomSeedForShaders
{
    return _cxxShip->randomSeedForShaders();
}
- (void)setEntityPersonalityInt:(uint16_t)value
{
    _cxxShip->setEntityPersonalityInt(value);
}
- (void)setSuppressExplosion:(BOOL)suppress
{
    _cxxShip->setSuppressExplosion(suppress);
}
- (void)resetExhaustPlumes
{
    _cxxShip->resetExhaustPlumes();
}
- (void)checkScanner
{
    _cxxShip->checkScanner();
}
- (void)checkScannerIgnoringUnpowered
{
    _cxxShip->checkScannerIgnoringUnpowered();
}
- (ShipEntity**)scannedShips
{
    return _cxxShip->scannedShips();
}
- (int)numberOfScannedShips
{
    return _cxxShip->numberOfScannedShips();
}
- (Entity*)foundTarget
{
    return _cxxShip->foundTarget();
}
- (void)setFoundTarget:(Entity*)targetEntity
{
    _cxxShip->cxx::ShipEntity::setFoundTarget(targetEntity);
}
- (Entity*)primaryAggressor
{
    return _cxxShip->primaryAggressor();
}
- (void)setPrimaryAggressor:(Entity*)targetEntity
{
    _cxxShip->setPrimaryAggressor(targetEntity);
}
- (Entity*)lastEscortTarget
{
    return _cxxShip->lastEscortTarget();
}
- (void)setLastEscortTarget:(Entity*)targetEntity
{
    _cxxShip->setLastEscortTarget(targetEntity);
}

@end

@implementation ShipEntity (OOSlice24)

- (Entity*)thankedShip
{
    return _cxxShip->thankedShip();
}
- (void)setThankedShip:(Entity*)targetEntity
{
    _cxxShip->setThankedShip(targetEntity);
}
- (Entity*)rememberedShip
{
    return _cxxShip->rememberedShip();
}
- (void)setRememberedShip:(Entity*)targetEntity
{
    _cxxShip->setRememberedShip(targetEntity);
}
- (StationEntity*)targetStation
{
    return _cxxShip->targetStation();
}
- (void)setTargetStation:(Entity*)targetEntity
{
    _cxxShip->setTargetStation(targetEntity);
}
- (BOOL)isValidTarget:(Entity*)target
{
    return _cxxShip->cxx::ShipEntity::isValidTarget(target);
}
- (void)addTarget:(Entity*)targetEntity
{
    _cxxShip->cxx::ShipEntity::addTarget(targetEntity);
}
- (void)removeTarget:(Entity*)targetEntity
{
    _cxxShip->removeTarget(targetEntity);
}
- (BOOL)canStillTrackPrimaryTarget
{
    return _cxxShip->canStillTrackPrimaryTarget();
}
- (id)primaryTarget
{
    return _cxxShip->primaryTarget();
}
- (id)primaryTargetWithoutValidityCheck
{
    return _cxxShip->primaryTargetWithoutValidityCheck();
}
- (BOOL)isFriendlyTo:(ShipEntity*)otherShip
{
    return _cxxShip->isFriendlyTo(otherShip);
}
- (ShipEntity*)shipHitByLaser
{
    return _cxxShip->shipHitByLaser();
}
- (void)setShipHitByLaser:(ShipEntity*)ship
{
    _cxxShip->setShipHitByLaser(ship);
}
- (void)noteLostTarget
{
    _cxxShip->noteLostTarget();
}
- (void)noteLostTargetAndGoIdle
{
    _cxxShip->noteLostTargetAndGoIdle();
}
- (void)noteTargetDestroyed:(ShipEntity*)target
{
    _cxxShip->noteTargetDestroyed(target);
}
- (OOBehaviour)behaviour
{
    return _cxxShip->getBehaviour();
}
- (void)setBehaviour:(OOBehaviour)cond
{
    _cxxShip->setBehaviour(cond);
}
- (HPVector)destination
{
    return _cxxShip->destination();
}
- (HPVector)coordinates
{
    return _cxxShip->getCoordinates();
}
- (void)setCoordinate:(HPVector)coord
{
    _cxxShip->setCoordinate(coord);
}
- (HPVector)distance_six:(GLfloat)dist
{
    return _cxxShip->distance_six(dist);
}
- (HPVector)distance_twelve:(GLfloat)dist withOffset:(GLfloat)offset
{
    return _cxxShip->distance_twelve(dist, offset);
}
- (void)trackOntoTarget:(double)delta_t withDForward:(GLfloat)dp
{
    _cxxShip->trackOntoTarget(delta_t, dp);
}
- (double)ballTrackLeadingTarget:(double)delta_t atTarget:(Entity*)target
{
    return _cxxShip->ballTrackLeadingTarget(delta_t, target);
}

@end

@implementation ShipEntity (OOSlice25)

- (void)setEvasiveJink:(GLfloat)z
{
    _cxxShip->setEvasiveJink(z);
}
- (void)evasiveAction:(double)delta_t
{
    _cxxShip->evasiveAction(delta_t);
}
- (double)trackPrimaryTarget:(double)delta_t retreat:(BOOL)retreat
{
    return _cxxShip->trackPrimaryTarget(delta_t, retreat);
}
- (double)trackSideTarget:(double)delta_t leftside:(BOOL)leftside
{
    return _cxxShip->trackSideTarget(delta_t, leftside);
}

@end

@implementation ShipEntity (OOSlice26)

- (double)missileTrackPrimaryTarget:(double)delta_t
{
    return _cxxShip->missileTrackPrimaryTarget(delta_t);
}
- (double)trackDestination:(double)delta_t retreat:(BOOL)retreat
{
    return _cxxShip->trackDestination(delta_t, retreat);
}
- (GLfloat)rollToMatchUp:(Vector)up_vec rotating:(GLfloat)match_roll
{
    return _cxxShip->rollToMatchUp(up_vec, match_roll);
}
- (GLfloat)rangeToDestination
{
    return _cxxShip->rangeToDestination();
}
- (std::vector<oo::ObjCRef<ShipEntity*>>)cxx_collisionExceptions
{
    return _cxxShip->collisionExceptions();
}
- (void)addCollisionException:(ShipEntity*)ship
{
    _cxxShip->addCollisionException(ship);
}
- (void)removeCollisionException:(ShipEntity*)ship
{
    _cxxShip->removeCollisionException(ship);
}
- (BOOL)collisionExceptedFor:(ShipEntity*)ship
{
    return _cxxShip->collisionExceptedFor(ship);
}
- (NSUInteger)defenseTargetCount
{
    return _cxxShip->defenseTargetCount();
}
- (std::vector<oo::ObjCRef<ShipEntity*>>)allDefenseTargets
{
    return _cxxShip->allDefenseTargets();
}
- (std::vector<oo::ObjCRef<ShipEntity*>>)cxx_defenseTargets
{
    return _cxxShip->defenseTargets();
}
- (BOOL)addDefenseTarget:(Entity*)target
{
    return _cxxShip->addDefenseTarget(target);
}
- (void)validateDefenseTargets
{
    _cxxShip->validateDefenseTargets();
}
- (BOOL)isDefenseTarget:(Entity*)target
{
    return _cxxShip->isDefenseTarget(target);
}
- (void)removeAllDefenseTargets
{
    _cxxShip->removeAllDefenseTargets();
}
- (void)removeDefenseTarget:(Entity*)target
{
    _cxxShip->removeDefenseTarget(target);
}
- (double)rangeToPrimaryTarget
{
    return _cxxShip->rangeToPrimaryTarget();
}
- (double)rangeToSecondaryTarget:(Entity*)target
{
    return _cxxShip->rangeToSecondaryTarget(target);
}
- (double)approachAspectToPrimaryTarget
{
    return _cxxShip->approachAspectToPrimaryTarget();
}
- (BOOL)hasProximityAlertIgnoringTarget:(BOOL)ignore_target
{
    return _cxxShip->hasProximityAlertIgnoringTarget(ignore_target);
}

@end

@implementation ShipEntity (OOSlice27)

- (GLfloat)currentAimTolerance
{
    return _cxxShip->currentAimTolerance();
}
- (GLfloat)lookingAtSunWithThresholdAngleCos:(GLfloat)thresholdAngleCos
{
    return _cxxShip->cxx::ShipEntity::lookingAtSunWithThresholdAngleCos(thresholdAngleCos);
}
- (BOOL)onTarget:(OOWeaponFacing)direction withWeapon:(OOWeaponType)weapon_type
{
    return _cxxShip->onTarget(direction, weapon_type);
}
- (BOOL)fireWeapon:(OOWeaponType)weapon_type direction:(OOWeaponFacing)direction range:(double)range
{
    return _cxxShip->fireWeapon(weapon_type, direction, range);
}
- (BOOL)fireMainWeapon:(double)range
{
    return _cxxShip->fireMainWeapon(range);
}
- (BOOL)fireAftWeapon:(double)range
{
    return _cxxShip->fireAftWeapon(range);
}
- (BOOL)firePortWeapon:(double)range
{
    return _cxxShip->firePortWeapon(range);
}
- (BOOL)fireStarboardWeapon:(double)range
{
    return _cxxShip->fireStarboardWeapon(range);
}
- (OOTimeDelta)shotTime
{
    return _cxxShip->shotTime();
}
- (void)resetShotTime
{
    _cxxShip->resetShotTime();
}
- (BOOL)fireTurretCannon:(double)range
{
    return _cxxShip->fireTurretCannon(range);
}
- (void)setLaserColor:(OOColor*)color
{
    _cxxShip->setLaserColor(color);
}
- (void)setExhaustEmissiveColor:(OOColor*)color
{
    _cxxShip->setExhaustEmissiveColor(color);
}
- (OOColor*)laserColor
{
    return _cxxShip->laserColor();
}
- (OOColor*)exhaustEmissiveColor
{
    return _cxxShip->exhaustEmissiveColor();
}

@end

@implementation ShipEntity (OOSlice28)

- (BOOL)fireSubentityLaserShot:(double)range
{
    return _cxxShip->fireSubentityLaserShot(range);
}
- (BOOL)fireDirectLaserShot:(double)range
{
    return _cxxShip->fireDirectLaserShot(range);
}
- (BOOL)fireDirectLaserDefensiveShot
{
    return _cxxShip->fireDirectLaserDefensiveShot();
}
- (BOOL)fireDirectLaserShotAt:(Entity*)my_target
{
    return _cxxShip->fireDirectLaserShotAt(my_target);
}
- (std::vector<Vector>)cxx_laserPortOffset:(OOWeaponFacing)direction
{
    return _cxxShip->laserPortOffset(direction);
}
- (BOOL)cxx_fireLaserShotInDirection:(OOWeaponFacing)direction weaponIdentifier:(const std::string&)weaponIdentifier
{
    return _cxxShip->fireLaserShotInDirection(direction, weaponIdentifier);
}
- (void)adjustMissedShots:(int)delta
{
    _cxxShip->adjustMissedShots(delta);
}
- (int)missedShots
{
    return _cxxShip->missedShots();
}
- (void)throwSparks
{
    _cxxShip->cxx::ShipEntity::throwSparks();
}
- (void)considerFiringMissile:(double)delta_t
{
    _cxxShip->considerFiringMissile(delta_t);
}
- (Vector)missileLaunchPosition
{
    return _cxxShip->missileLaunchPosition();
}
- (ShipEntity*)fireMissile
{
    return _cxxShip->cxx::ShipEntity::fireMissile();
}

@end

@implementation ShipEntity (OOSlice29)

- (ShipEntity*)cxx_fireMissileWithIdentifier:(const std::optional<std::string>&)requestedIdentifier andTarget:(Entity*)target
{
    return _cxxShip->fireMissileWithIdentifier(requestedIdentifier, target);
}
- (BOOL)isMissileFlagSet
{
    return _cxxShip->isMissileFlagSet();
}
- (void)setIsMissileFlag:(BOOL)newValue
{
    _cxxShip->setIsMissileFlag(newValue);
}
- (OOTimeDelta)missileLoadTime
{
    return _cxxShip->missileLoadTime();
}
- (void)setMissileLoadTime:(OOTimeDelta)newMissileLoadTime
{
    _cxxShip->setMissileLoadTime(newMissileLoadTime);
}
- (void)noticeECM
{
    _cxxShip->cxx::ShipEntity::noticeECM();
}
- (BOOL)fireECM
{
    return _cxxShip->cxx::ShipEntity::fireECM();
}
- (BOOL)activateCloakingDevice
{
    return _cxxShip->cxx::ShipEntity::activateCloakingDevice();
}
- (void)deactivateCloakingDevice
{
    _cxxShip->cxx::ShipEntity::deactivateCloakingDevice();
}
- (BOOL)launchCascadeMine
{
    return _cxxShip->launchCascadeMine();
}
- (ShipEntity*)launchEscapeCapsule
{
    return _cxxShip->cxx::ShipEntity::launchEscapeCapsule();
}
- (void)dumpCargo
{
    _cxxShip->cxx::ShipEntity::dumpCargo();
}
- (ShipEntity*)cxx_dumpCargoItem:(const std::optional<std::string>&)preferred
{
    return _cxxShip->dumpCargoItem(preferred);
}
- (OOCargoType)dumpItem:(ShipEntity*)cargoObj
{
    return _cxxShip->dumpItem(cargoObj);
}

@end

@implementation ShipEntity (OOSlice30)

- (void)manageCollisions
{
    _cxxShip->manageCollisions();
}
- (BOOL)collideWithShip:(ShipEntity*)other
{
    return _cxxShip->cxx::ShipEntity::collideWithShip(other);
}
- (Vector)thrustVector
{
    return _cxxShip->thrustVector();
}
- (Vector)velocity
{
    return _cxxShip->cxx::ShipEntity::getVelocity();
}
- (void)setTotalVelocity:(Vector)vel
{
    _cxxShip->setTotalVelocity(vel);
}
- (void)adjustVelocity:(Vector)xVel
{
    _cxxShip->cxx::ShipEntity::adjustVelocity(xVel);
}
- (void)addImpactMoment:(Vector)moment fraction:(GLfloat)howmuch
{
    _cxxShip->addImpactMoment(moment, howmuch);
}
- (BOOL)canScoop:(ShipEntity*)other
{
    return _cxxShip->cxx::ShipEntity::canScoop(other);
}
- (void)getTractoredBy:(ShipEntity*)other
{
    _cxxShip->getTractoredBy(other);
}
- (void)scoopIn:(ShipEntity*)other
{
    _cxxShip->scoopIn(other);
}
- (void)suppressTargetLost
{
    _cxxShip->cxx::ShipEntity::suppressTargetLost();
}
- (void)scoopUp:(ShipEntity*)other
{
    _cxxShip->scoopUp(other);
}
- (void)scoopUpProcess:(ShipEntity*)other processEvents:(BOOL)procEvents processMessages:(BOOL)procMessages
{
    _cxxShip->scoopUpProcess(other, procEvents, procMessages);
}

@end

@implementation ShipEntity (OOSlice31)

- (BOOL)cascadeIfAppropriateWithDamageAmount:(double)amount cascadeOwner:(Entity*)owner
{
    return _cxxShip->cascadeIfAppropriateWithDamageAmount(amount, owner);
}
- (void)takeEnergyDamage:(double)amount from:(Entity*)ent becauseOf:(Entity*)other weaponIdentifier:(const std::string&)weaponIdentifier
{
    _cxxShip->cxx::ShipEntity::takeEnergyDamage(amount, oo::ToCxx(ent), oo::ToCxx(other), weaponIdentifier);
}
- (BOOL)abandonShip
{
    return _cxxShip->abandonShip();
}
- (void)takeScrapeDamage:(double)amount from:(Entity*)ent
{
    _cxxShip->cxx::ShipEntity::takeScrapeDamage(amount, ent);
}
- (void)takeHeatDamage:(double)amount
{
    _cxxShip->cxx::ShipEntity::takeHeatDamage(amount);
}
- (void)enterDock:(StationEntity*)station
{
    _cxxShip->cxx::ShipEntity::enterDock(station);
}
- (void)leaveDock:(StationEntity*)station
{
    _cxxShip->cxx::ShipEntity::leaveDock(station);
}
- (void)enterWormhole:(WormholeEntity*)w_hole
{
    _cxxShip->cxx::ShipEntity::enterWormhole(w_hole);
}
- (void)enterWormhole:(WormholeEntity*)w_hole replacing:(BOOL)replacing
{
    _cxxShip->enterWormhole(w_hole, replacing);
}
- (void)enterWitchspace
{
    _cxxShip->cxx::ShipEntity::enterWitchspace();
}
- (void)leaveWitchspace
{
    _cxxShip->cxx::ShipEntity::leaveWitchspace();
}

@end

@implementation ShipEntity (OOSlice32)

- (BOOL)witchspaceLeavingEffects
{
    return _cxxShip->witchspaceLeavingEffects();
}
- (void)markAsOffender:(int)offence_value
{
    _cxxShip->cxx::ShipEntity::markAsOffender(offence_value);
}
- (void)markAsOffender:(int)offence_value withReason:(OOLegalStatusReason)reason
{
    _cxxShip->cxx::ShipEntity::markAsOffender(offence_value, reason);
}
- (void)switchLightsOn
{
    _cxxShip->switchLightsOn();
}
- (void)switchLightsOff
{
    _cxxShip->switchLightsOff();
}
- (BOOL)lightsActive
{
    return _cxxShip->lightsActive();
}
- (void)setDestination:(HPVector)dest
{
    _cxxShip->setDestination(dest);
}
- (void)setEscortDestination:(HPVector)dest
{
    _cxxShip->setEscortDestination(dest);
}
- (BOOL)canAcceptEscort:(ShipEntity*)potentialEscort
{
    return _cxxShip->canAcceptEscort(potentialEscort);
}
- (BOOL)acceptAsEscort:(ShipEntity*)other_ship
{
    return _cxxShip->acceptAsEscort(other_ship);
}
- (void)updateEscortFormation
{
    _cxxShip->updateEscortFormation();
}
- (void)refreshEscortPositions
{
    _cxxShip->refreshEscortPositions();
}
- (HPVector)coordinatesForEscortPosition:(unsigned)idx
{
    return _cxxShip->coordinatesForEscortPosition(idx);
}
- (void)deployEscorts
{
    _cxxShip->deployEscorts();
}
- (void)dockEscorts
{
    _cxxShip->dockEscorts();
}
- (void)setTargetToNearestStationIncludingHostiles:(BOOL)includeHostiles
{
    _cxxShip->setTargetToNearestStationIncludingHostiles(includeHostiles);
}
- (void)setTargetToNearestFriendlyStation
{
    _cxxShip->setTargetToNearestFriendlyStation();
}
- (void)setTargetToNearestStation
{
    _cxxShip->setTargetToNearestStation();
}
- (void)setTargetToSystemStation
{
    _cxxShip->setTargetToSystemStation();
}

@end

@implementation ShipEntity (OOSlice33)

- (void)landOnPlanet:(OOPlanetEntity*)planet
{
    _cxxShip->landOnPlanet(planet);
}
- (void)abortDocking
{
    _cxxShip->abortDocking();
}
- (oo::PList)cxx_dockingInstructions
{
    return _cxxShip->getDockingInstructions();
}
- (void)broadcastThargoidDestroyed
{
    _cxxShip->broadcastThargoidDestroyed();
}
- (void)broadcastHitByLaserFrom:(ShipEntity*)aggressor_ship
{
    _cxxShip->broadcastHitByLaserFrom(aggressor_ship);
}
- (void)cxx_sendMessage:(const std::string&)message_text toShip:(ShipEntity*)other_ship withUnpilotedOverride:(BOOL)unpilotedOverride
{
    _cxxShip->sendMessage(message_text, other_ship, unpilotedOverride);
}
- (void)cxx_sendExpandedMessage:(const std::string&)message_text toShip:(ShipEntity*)other_ship
{
    _cxxShip->sendExpandedMessage(message_text, other_ship);
}
- (void)broadcastAIMessage:(const std::string&)ai_message
{
    _cxxShip->broadcastAIMessage(ai_message);
}
- (void)broadcastMessage:(const std::string&)message_text withUnpilotedOverride:(BOOL)unpilotedOverride
{
    _cxxShip->broadcastMessage(message_text, unpilotedOverride);
}
- (void)setCommsMessageColor
{
    _cxxShip->setCommsMessageColor();
}
- (void)receiveCommsMessage:(const std::string&)message_text from:(ShipEntity*)other
{
    _cxxShip->cxx::ShipEntity::receiveCommsMessage(message_text, other);
}
- (void)cxx_commsMessage:(const std::string&)valueString withUnpilotedOverride:(BOOL)unpilotedOverride
{
    _cxxShip->commsMessage(valueString, unpilotedOverride);
}
- (BOOL)markedForFines
{
    return _cxxShip->markedForFines();
}
- (BOOL)markForFines
{
    return _cxxShip->markForFines();
}
- (BOOL)isMining
{
    return _cxxShip->cxx::ShipEntity::isMining();
}
- (void)interpretAIMessage:(const std::string&)ms
{
    _cxxShip->cxx::ShipEntity::interpretAIMessage(ms);
}
- (BoundingBox)findBoundingBoxRelativeTo:(Entity*)other i:(Vector)_i j:(Vector)_j k:(Vector)_k
{
    return _cxxShip->findBoundingBoxRelativeTo(other, _i, _j, _k);
}
- (void)spawn:(const std::string&)roles_number
{
    _cxxShip->spawn(roles_number);
}
- (int)checkShipsInVicinityForWitchJumpExit
{
    return _cxxShip->checkShipsInVicinityForWitchJumpExit();
}
- (BOOL)trackCloseContacts
{
    return _cxxShip->getTrackCloseContacts();
}
- (void)setTrackCloseContacts:(BOOL)value
{
    _cxxShip->setTrackCloseContacts(value);
}
#if OO_SALVAGE_SUPPORT
- (void)claimAsSalvage
{
    _cxxShip->claimAsSalvage();
}
- (void)sendCoordinatesToPilot
{
    _cxxShip->sendCoordinatesToPilot();
}
#endif

@end

@implementation ShipEntity (OOSlice34)

#if OO_SALVAGE_SUPPORT
- (void)pilotArrived
{
    _cxxShip->pilotArrived();
}
#endif
#ifdef OO_DEBUG_MONITOR_ENABLED
- (void)dumpSelfState
{
    _cxxShip->cxx::ShipEntity::dumpSelfState();
}
#endif
- (OOJSScript*)script
{
    return _cxxShip->getScript();
}
- (oo::PList)scriptInfo
{
    return _cxxShip->getScriptInfo();
}
- (void)overrideScriptInfo:(const oo::PList&)override
{
    _cxxShip->overrideScriptInfo(override);
}
- (Entity*)entityForShaderProperties
{
    return _cxxShip->entityForShaderProperties();
}
- (void)setDemoShip:(OOScalar)rate
{
    _cxxShip->setDemoShip(rate);
}
- (BOOL)isDemoShip
{
    return _cxxShip->getIsDemoShip();
}
- (void)setDemoStartTime:(OOTimeAbsolute)time
{
    _cxxShip->setDemoStartTime(time);
}
- (OOTimeAbsolute)getDemoStartTime
{
    return _cxxShip->getDemoStartTime();
}
- (void)doScriptEvent:(OOJSPropID)message
{
    _cxxShip->doScriptEvent(message);
}
- (void)doScriptEvent:(OOJSPropID)message withArgument:(id)argument
{
    _cxxShip->doScriptEvent(message, argument);
}
- (void)doScriptEvent:(OOJSPropID)message withArgument:(id)argument1 andArgument:(id)argument2
{
    _cxxShip->doScriptEvent(message, argument1, argument2);
}
- (void)cxx_doScriptEvent:(OOJSPropID)message withPListArguments:(const std::vector<oo::PList>&)arguments
{
    _cxxShip->doScriptEvent(message, arguments);
}
- (void)doScriptEvent:(OOJSPropID)message withArguments:(JSValue*)argv count:(int)argc
{
    _cxxShip->doScriptEvent(message, argv, argc);
}
- (void)doScriptEvent:(OOJSPropID)message inContext:(JSContext*)context withArguments:(JSValue*)argv count:(int)argc
{
    _cxxShip->cxx::ShipEntity::doScriptEvent(message, context, argv, argc);
}
- (void)cxx_reactToAIMessage:(const std::string&)message context:(const std::optional<std::string>&)debugContext
{
    _cxxShip->reactToAIMessage(message, debugContext);
}
- (void)sendAIMessage:(const std::string&)message
{
    _cxxShip->sendAIMessage(message);
}
- (void)cxx_doScriptEvent:(OOJSPropID)scriptEvent andReactToAIMessage:(const std::string&)aiMessage
{
    _cxxShip->doScriptEvent(scriptEvent, aiMessage);
}
- (void)cxx_doScriptEvent:(OOJSPropID)scriptEvent withArgument:(id)argument andReactToAIMessage:(const std::string&)aiMessage
{
    _cxxShip->doScriptEvent(scriptEvent, argument, aiMessage);
}
- (OOAlertCondition)alertCondition
{
    return _cxxShip->cxx::ShipEntity::alertCondition();
}
- (OOAlertCondition)realAlertCondition
{
    return _cxxShip->cxx::ShipEntity::realAlertCondition();
}
- (void)doNothing
{
    _cxxShip->doNothing();
}
#ifdef OO_DEBUG_MONITOR_ENABLED
- (std::optional<std::string>)descriptionForObjDump
{
    return _cxxShip->cxx::ShipEntity::descriptionForObjDump();
}
#endif

@end

// The category ShipEntity (ScriptMethods) of ShipEntityScriptMethods.mm (bead oo-42dr), whose
// members are cxx::ShipEntity's, defined in that file.
@implementation ShipEntity (ScriptMethods)

- (ShipEntity*)ejectShipOfType:(const std::optional<std::string>&)shipKey
{
    return _cxxShip->ejectShipOfType(shipKey);
}
- (ShipEntity*)ejectShipOfRole:(const std::optional<std::string>&)role
{
    return _cxxShip->ejectShipOfRole(role);
}
- (std::vector<oo::ObjCRef<ShipEntity*>>)spawnShipsWithRole:(const std::string&)role count:(NSUInteger)count
{
    return _cxxShip->spawnShipsWithRole(role, count);
}

@end

// The category ShipEntity (LoadRestore) of ShipEntityLoadRestore.mm (bead oo-kw44), whose members
// are cxx::ShipEntity's, defined in that file.
@implementation ShipEntity (LoadRestore)

- (oo::PList)savedShipDictionaryWithContext:(OOShipSaveContext*)context
{
    return _cxxShip->savedShipDictionaryWithContext(context);
}
+ (id)shipRestoredFromDictionary:(const oo::PList&)dictionary useFallback:(BOOL)fallback context:(OOShipSaveContext*)context
{
    return cxx::ShipEntity::shipRestoredFromDictionary(dictionary, fallback, context);
}

@end

// ShipEntityAI.mm slice 1 (bead oo-iebuz): the category ShipEntity (AI).
@implementation ShipEntity (AI)

- (void)setAITo:(const std::string&)aiString
{
    _cxxShip->setAITo(aiString);
}
- (void)setAIScript:(const std::string&)aiString
{
    _cxxShip->setAIScript(aiString);
}
- (void)switchAITo:(const std::string&)aiString
{
    _cxxShip->switchAITo(aiString);
}
- (void)scanForHostiles
{
    _cxxShip->scanForHostiles();
}
- (void)groupAttackTarget
{
    _cxxShip->groupAttackTarget();
}
- (void)performAttack
{
    _cxxShip->performAttack();
}
- (void)performCollect
{
    _cxxShip->performCollect();
}
- (void)performEscort
{
    _cxxShip->performEscort();
}
- (void)performFaceDestination
{
    _cxxShip->performFaceDestination();
}
- (void)performFlee
{
    _cxxShip->performFlee();
}
- (void)performFlyToRangeFromDestination
{
    _cxxShip->performFlyToRangeFromDestination();
}
- (void)performHold
{
    _cxxShip->performHold();
}
- (void)performIdle
{
    _cxxShip->performIdle();
}
- (void)performIntercept
{
    _cxxShip->performIntercept();
}
- (void)performLandOnPlanet
{
    _cxxShip->performLandOnPlanet();
}
- (void)performMining
{
    _cxxShip->performMining();
}
- (void)performScriptedAI
{
    _cxxShip->performScriptedAI();
}
- (void)performScriptedAttackAI
{
    _cxxShip->performScriptedAttackAI();
}
- (void)performBuoyTumble
{
    _cxxShip->performBuoyTumble();
}
- (void)performStop
{
    _cxxShip->performStop();
}
- (void)performTumble
{
    _cxxShip->performTumble();
}
- (BOOL)performHyperSpaceToSpecificSystem:(OOSystemID)systemID
{
    return _cxxShip->performHyperSpaceToSpecificSystem(systemID);
}
- (void)requestDockingCoordinates
{
    _cxxShip->requestDockingCoordinates();
}
- (void)recallDockingInstructions
{
    _cxxShip->recallDockingInstructions();
}
- (void)scanForNearestIncomingMissile
{
    _cxxShip->scanForNearestIncomingMissile();
}
- (void)enterPlayerWormhole
{
    _cxxShip->enterPlayerWormhole();
}
- (void)enterTargetWormhole
{
    _cxxShip->enterTargetWormhole();
}
- (void)wormholeEscorts
{
    _cxxShip->wormholeEscorts();
}
- (void)wormholeEntireGroup
{
    _cxxShip->wormholeEntireGroup();
}
- (BOOL)suggestEscortTo:(ShipEntity*)mother
{
    return _cxxShip->suggestEscortTo(mother);
}
- (void)broadcastDistressMessage
{
    _cxxShip->broadcastDistressMessage();
}
- (void)broadcastDistressMessageWithDumping:(BOOL)dumpCargo
{
    _cxxShip->broadcastDistressMessageWithDumping(dumpCargo);
}

@end

// ShipEntityAI.mm slice 1 (bead oo-iebuz): the category ShipEntity (OOAIPrivate).
@implementation ShipEntity (OOAIPrivate)

- (void)checkFoundTarget
{
    _cxxShip->checkFoundTarget();
}
- (BOOL)performHyperSpaceExitReplace:(BOOL)replace
{
    return _cxxShip->performHyperSpaceExitReplace(replace);
}
- (BOOL)performHyperSpaceExitReplace:(BOOL)replace toSystem:(OOSystemID)systemID
{
    return _cxxShip->performHyperSpaceExitReplace(replace, systemID);
}
- (void)scanForNearestShipWithPredicate:(EntityFilterPredicate)predicate parameter:(void*)parameter
{
    _cxxShip->scanForNearestShipWithPredicate(predicate, parameter);
}
- (void)scanForNearestShipWithNegatedPredicate:(EntityFilterPredicate)predicate parameter:(void*)parameter
{
    _cxxShip->scanForNearestShipWithNegatedPredicate(predicate, parameter);
}
- (void)acceptDistressMessageFrom:(ShipEntity*)other
{
    _cxxShip->cxx::ShipEntity::acceptDistressMessageFrom(other);
}

@end

// ShipEntityAI.mm slice 1 (bead oo-iebuz): the category ShipEntity (OOAIStationStubs), which no
// header declares (StationEntity declares the selectors it answers for a station).
@implementation ShipEntity (OOAIStationStubs)

- (void)increaseAlertLevel
{
    _cxxShip->increaseAlertLevel();
}
- (void)decreaseAlertLevel
{
    _cxxShip->decreaseAlertLevel();
}
- (oo::PList)launchPolice
{
    return _cxxShip->launchPolice();
}
- (void)launchDefenseShip
{
    _cxxShip->launchDefenseShip();
}
- (void)launchScavenger
{
    _cxxShip->launchScavenger();
}
- (void)launchMiner
{
    _cxxShip->launchMiner();
}
- (void)launchPirateShip
{
    _cxxShip->launchPirateShip();
}
- (void)launchShuttle
{
    _cxxShip->launchShuttle();
}
- (void)launchTrader
{
    _cxxShip->launchTrader();
}
- (void)launchEscort
{
    _cxxShip->launchEscort();
}
- (BOOL)launchPatrol
{
    return _cxxShip->launchPatrol();
}
- (void)launchShipWithRole:(const std::string&)param
{
    _cxxShip->launchShipWithRole(param);
}
- (void)abortAllDockings
{
    _cxxShip->abortAllDockings();
}

@end

// ShipEntityAI.mm slice 2 (bead oo-xurzn): the category ShipEntity (PureAI).
@implementation ShipEntity (OOAISlice2)

- (void)setStateTo:(const std::string&)state
{
    _cxxShip->setStateTo(state);
}
- (void)pauseAI:(const std::string&)intervalString
{
    _cxxShip->pauseAI(intervalString);
}
- (void)randomPauseAI:(const std::string&)intervalString
{
    _cxxShip->randomPauseAI(intervalString);
}
- (void)dropMessages:(const std::string&)messageString
{
    _cxxShip->dropMessages(messageString);
}
- (void)debugDumpPendingMessages
{
    _cxxShip->debugDumpPendingMessages();
}
- (void)setDestinationToCurrentLocation
{
    _cxxShip->setDestinationToCurrentLocation();
}
- (void)setDestinationToJinkPosition
{
    _cxxShip->setDestinationToJinkPosition();
}
- (void)setDesiredRangeTo:(const std::string&)rangeString
{
    _cxxShip->setDesiredRangeTo(rangeString);
}
- (void)setDesiredRangeForWaypoint
{
    _cxxShip->setDesiredRangeForWaypoint();
}
- (void)setSpeedTo:(const std::string&)speedString
{
    _cxxShip->setSpeedTo(speedString);
}
- (void)setSpeedFactorTo:(const std::string&)speedString
{
    _cxxShip->setSpeedFactorTo(speedString);
}
- (void)setSpeedToCruiseSpeed
{
    _cxxShip->setSpeedToCruiseSpeed();
}
- (void)setThrustFactorTo:(const std::string&)thrustFactorString
{
    _cxxShip->setThrustFactorTo(thrustFactorString);
}
- (void)setTargetToPrimaryAggressor
{
    _cxxShip->setTargetToPrimaryAggressor();
}
- (void)addPrimaryAggressorAsDefenseTarget
{
    _cxxShip->addPrimaryAggressorAsDefenseTarget();
}
- (void)scanForNearestMerchantman
{
    _cxxShip->scanForNearestMerchantman();
}
- (void)scanForRandomMerchantman
{
    _cxxShip->scanForRandomMerchantman();
}
- (void)scanForLoot
{
    _cxxShip->scanForLoot();
}
- (void)scanForRandomLoot
{
    _cxxShip->scanForRandomLoot();
}
- (void)setTargetToFoundTarget
{
    _cxxShip->setTargetToFoundTarget();
}
- (void)addFoundTargetAsDefenseTarget
{
    _cxxShip->addFoundTargetAsDefenseTarget();
}
- (void)checkForFullHold
{
    _cxxShip->checkForFullHold();
}
- (void)getWitchspaceEntryCoordinates
{
    _cxxShip->getWitchspaceEntryCoordinates();
}
- (void)setDestinationFromCoordinates
{
    _cxxShip->setDestinationFromCoordinates();
}
- (void)setCoordinatesFromPosition
{
    _cxxShip->setCoordinatesFromPosition();
}
- (void)fightOrFleeMissile
{
    _cxxShip->fightOrFleeMissile();
}
- (void)setCourseToPlanet
{
    _cxxShip->setCourseToPlanet();
}
- (void)setTakeOffFromPlanet
{
    _cxxShip->setTakeOffFromPlanet();
}
- (void)landOnPlanet
{
    _cxxShip->landOnPlanet();
}
- (void)checkTargetLegalStatus
{
    _cxxShip->checkTargetLegalStatus();
}
- (void)checkOwnLegalStatus
{
    _cxxShip->checkOwnLegalStatus();
}
- (void)exitAIWithMessage:(const std::string&)message
{
    _cxxShip->exitAIWithMessage(message);
}
- (void)setDestinationToTarget
{
    _cxxShip->setDestinationToTarget();
}
- (void)setDestinationWithinTarget
{
    _cxxShip->setDestinationWithinTarget();
}
- (void)checkCourseToDestination
{
    _cxxShip->checkCourseToDestination();
}

@end

// ShipEntityAI.mm slice 3 (bead oo-wc9o3): the category ShipEntity (PureAI).
@implementation ShipEntity (OOAISlice3)

- (void)checkAegis
{
    _cxxShip->checkAegis();
}
- (void)checkEnergy
{
    _cxxShip->checkEnergy();
}
- (void)checkHeatInsulation
{
    _cxxShip->checkHeatInsulation();
}
- (void)findNewDefenseTarget
{
    _cxxShip->findNewDefenseTarget();
}
- (void)scanForOffenders
{
    _cxxShip->scanForOffenders();
}
- (void)setCourseToWitchpoint
{
    _cxxShip->setCourseToWitchpoint();
}
- (void)setDestinationToWitchpoint
{
    _cxxShip->setDestinationToWitchpoint();
}
- (void)setDestinationToStationBeacon
{
    _cxxShip->setDestinationToStationBeacon();
}
- (void)performHyperSpaceExit
{
    _cxxShip->performHyperSpaceExit();
}
- (void)performHyperSpaceExitWithoutReplacing
{
    _cxxShip->performHyperSpaceExitWithoutReplacing();
}
- (void)disengageAutopilot
{
    _cxxShip->cxx::ShipEntity::disengageAutopilot();
}
- (void)wormholeGroup
{
    _cxxShip->wormholeGroup();
}
- (void)commsMessage:(const std::string&)valueString
{
    _cxxShip->cxx::ShipEntity::commsMessage(valueString);
}
- (void)commsMessageByUnpiloted:(const std::string&)valueString
{
    _cxxShip->cxx::ShipEntity::commsMessageByUnpiloted(valueString);
}
- (void)ejectCargo
{
    _cxxShip->ejectCargo();
}
- (void)scanForThargoid
{
    _cxxShip->scanForThargoid();
}
- (void)scanForNonThargoid
{
    _cxxShip->scanForNonThargoid();
}
- (void)thargonCheckMother
{
    _cxxShip->thargonCheckMother();
}
- (void)becomeUncontrolledThargon
{
    _cxxShip->becomeUncontrolledThargon();
}
- (void)checkDistanceTravelled
{
    _cxxShip->checkDistanceTravelled();
}
- (void)fightOrFleeHostiles
{
    _cxxShip->fightOrFleeHostiles();
}
- (void)suggestEscort
{
    _cxxShip->suggestEscort();
}
- (void)escortCheckMother
{
    _cxxShip->escortCheckMother();
}
- (void)checkGroupOddsVersusTarget
{
    _cxxShip->checkGroupOddsVersusTarget();
}
- (void)scanForFormationLeader
{
    _cxxShip->scanForFormationLeader();
}
- (void)messageMother:(const std::string&)msgString
{
    _cxxShip->messageMother(msgString);
}
- (void)messageSelf:(const std::string&)msgString
{
    _cxxShip->messageSelf(msgString);
}
- (void)setPlanetPatrolCoordinates
{
    _cxxShip->setPlanetPatrolCoordinates();
}
- (void)setSunSkimStartCoordinates
{
    _cxxShip->setSunSkimStartCoordinates();
}
- (void)setSunSkimEndCoordinates
{
    _cxxShip->setSunSkimEndCoordinates();
}
- (void)setSunSkimExitCoordinates
{
    _cxxShip->setSunSkimExitCoordinates();
}
- (void)patrolReportIn
{
    _cxxShip->patrolReportIn();
}
- (void)checkForMotherStation
{
    _cxxShip->checkForMotherStation();
}
- (void)sendTargetCommsMessage:(const std::string&)message
{
    _cxxShip->sendTargetCommsMessage(message);
}
- (void)markTargetForFines
{
    _cxxShip->markTargetForFines();
}
- (void)markTargetForOffence:(const std::string&)valueString
{
    _cxxShip->markTargetForOffence(valueString);
}
- (void)storeTarget
{
    _cxxShip->storeTarget();
}

@end

// ShipEntityAI.mm slice 4 (bead oo-lqyhf): the category ShipEntity (PureAI).
@implementation ShipEntity (PureAI)

- (void)recallStoredTarget
{
    _cxxShip->recallStoredTarget();
}
- (void)scanForRocks
{
    _cxxShip->scanForRocks();
}
- (void)setDestinationToDockingAbort
{
    _cxxShip->setDestinationToDockingAbort();
}
- (void)requestNewTarget
{
    _cxxShip->requestNewTarget();
}
- (void)rollD:(const std::string&)die_number
{
    _cxxShip->rollD(die_number);
}
- (void)scanForNearestShipWithPrimaryRole:(const std::string&)scanRole
{
    _cxxShip->scanForNearestShipWithPrimaryRole(scanRole);
}
- (void)scanForNearestShipHavingRole:(const std::string&)scanRole
{
    _cxxShip->scanForNearestShipHavingRole(scanRole);
}
- (void)scanForNearestShipWithAnyPrimaryRole:(const std::string&)scanRoles
{
    _cxxShip->scanForNearestShipWithAnyPrimaryRole(scanRoles);
}
- (void)scanForNearestShipHavingAnyRole:(const std::string&)scanRoles
{
    _cxxShip->scanForNearestShipHavingAnyRole(scanRoles);
}
- (void)scanForNearestShipWithScanClass:(const std::string&)scanScanClass
{
    _cxxShip->scanForNearestShipWithScanClass(scanScanClass);
}
- (void)scanForNearestShipWithoutPrimaryRole:(const std::string&)scanRole
{
    _cxxShip->scanForNearestShipWithoutPrimaryRole(scanRole);
}
- (void)scanForNearestShipNotHavingRole:(const std::string&)scanRole
{
    _cxxShip->scanForNearestShipNotHavingRole(scanRole);
}
- (void)scanForNearestShipWithoutAnyPrimaryRole:(const std::string&)scanRoles
{
    _cxxShip->scanForNearestShipWithoutAnyPrimaryRole(scanRoles);
}
- (void)scanForNearestShipNotHavingAnyRole:(const std::string&)scanRoles
{
    _cxxShip->scanForNearestShipNotHavingAnyRole(scanRoles);
}
- (void)scanForNearestShipWithoutScanClass:(const std::string&)scanScanClass
{
    _cxxShip->scanForNearestShipWithoutScanClass(scanScanClass);
}
- (void)scanForNearestShipMatchingPredicate:(const std::string&)predicateExpression
{
    _cxxShip->scanForNearestShipMatchingPredicate(predicateExpression);
}
- (void)setCoordinates:(const std::string&)system_x_y_z
{
    _cxxShip->setCoordinates(system_x_y_z);
}
- (void)checkForNormalSpace
{
    _cxxShip->checkForNormalSpace();
}
- (void)setTargetToRandomStation
{
    _cxxShip->setTargetToRandomStation();
}
- (void)setTargetToLastStation
{
    _cxxShip->setTargetToLastStation();
}
- (void)addFuel:(const std::string&)fuel_number
{
    _cxxShip->addFuel(fuel_number);
}
- (void)scriptActionOnTarget:(const std::string&)action
{
    _cxxShip->scriptActionOnTarget(action);
}
- (void)safeScriptActionOnTarget:(const std::string&)action
{
    _cxxShip->safeScriptActionOnTarget(action);
}
- (void)sendScriptMessage:(const std::string&)message
{
    _cxxShip->sendScriptMessage(message);
}
- (void)ai_throwSparks
{
    _cxxShip->ai_throwSparks();
}
- (void)explodeSelf
{
    _cxxShip->explodeSelf();
}
- (void)ai_debugMessage:(const std::string&)message
{
    _cxxShip->ai_debugMessage(message);
}
- (void)targetFirstBeaconWithCode:(const std::string&)code
{
    _cxxShip->targetFirstBeaconWithCode(code);
}
- (void)targetNextBeaconWithCode:(const std::string&)code
{
    _cxxShip->targetNextBeaconWithCode(code);
}
- (void)setRacepointsFromTarget
{
    _cxxShip->setRacepointsFromTarget();
}
- (void)performFlyRacepoints
{
    _cxxShip->performFlyRacepoints();
}

@end
