/*

ShipEntity+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, amendments oo-bj8 and oo-60fwo): the Objective-C ShipEntity, the
facade over the C++ cxx::ShipEntity (ShipEntity.h) while the class converts slice by slice
(docs/phases/3-slices/ShipEntity.md). Its interface is the one ShipEntity.h declared before slice 1,
copied exactly, with ShipEntity (Debug) and the category Entity (SubEntityRelationship), which the
header declared after it; only -cxx_initWithKey:definition: moved, to the category that implements
it beside -init and -dealloc. Its methods keep their Objective-C bodies until their slice moves them
to cxx::ShipEntity and leaves a forwarder here. It has one ivar, _cxxShip: the root's _cxxEntity,
typed, borrowed (the root owns the part), set by the initialiser; unconverted code reads the ship's
members through it by their old names (_cxxShip->fuel, ship->_cxxShip->fuel). Its initialisers make
an Objective-C ship's adapter over cxx::ShipEntity (ObjCShipEntity in the .mm), so
StationEntity, DockEntity, PlayerEntity and ProxyPlayerEntity reach the ship's members through it.
Imported as the last line of ShipEntity.h; do not import it directly. Never add to this file.
Deleted by its deletion bead once every slice, the categories and the subclasses are C++.

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

#ifndef SHIPENTITY_OBJCBRIDGE_H
#define SHIPENTITY_OBJCBRIDGE_H

@interface ShipEntity : OOEntityWithDrawable // <OOSubEntity> and <OOBeaconEntity>, by the categories ShipEntity (OOSubEntity) and ShipEntity (OOBeaconEntity)
{
@public
    cxx::ShipEntity* _cxxShip; // _cxxEntity, typed; borrowed, set by the initialiser
}

// ship brains

// The ship / exhaust subentities, a snapshot in subentity order (empty for a nil receiver).

// subentities management

// octree collision hunting

// beacons // definitions now in <OOBeaconEntity> protocol

// Equipment

// Internal, subject to change. Use the methods above instead.

// Passengers and parcels - not supported for NPCs, but interface is here for genericity.

// Tests for the various special-cased equipment items
// (Nowadays, more convenience methods)

// Shield information derived from equipment. NPCs can't have shields, but that should change at some point.

// Behaviours

// Pending escort count: number of escorts to set up "later".

// allow adjustment of escort numbers from shipdata.plist levels

// defense target handling

// collision exceptions

/**
        Convenience to set the crew to a single character of the given role,
        originating in the ship's home system. Does nothing if unpiloted.
 */

// Fuel and capacity in tenths of light-years.

/*
 Sets the bounty on this ship to amount.
 Does not check to see if the ship is allowed to have a bounty, for example if it is police.
 */

// the percentage of damage taken (100 is destroyed, 0 is fine)

// Dispatch shipTakingDamage() event.
// Dispatch shipDied() and possibly shipKilledOther() events. This is only for use by getDestroyedBy:damageType:, but needs to be visible to PlayerEntity's version.

Vector cxx_positionOffsetForShipInRotationToAlignment(ShipEntity* ship, Quaternion q, const std::string& align);

/*-----------------------------------------

 AI piloting methods

 -----------------------------------------*/

// return 0.0 if there is no primary target
/* This method returns a value between 0.0f and 1.0f, depending on how directly our view point
   faces the sun and is used for generating the "staring at the sun" glare effect. 0.0f means that
   we are not facing the sun, 1.0f means that we are looking directly at it. The cosine of the
   threshold angle between view point and sun, below which we consider the ship as looking
   at the sun, is passed as parameter to the method.
*/

/*
 Mark this ship as an offender, this is different to setBounty as some ships such as police
 are not markable.  The final bounty may not be equal to existing bounty plus offence_value.
 */

// Sun glare filter - 0 for no filter, 1 for full filter

// Unpiloted ships cannot broadcast messages, unless the unpilotedOverride is set to YES.

/*
 * Changes a ship to a hulk, for example when the pilot ejects.
 * Aso unsets hulkiness for example when a new pilot gets in.
 */

// Demo ship

/*	*** Script events.
        For NPC ships, these call doEvent: on the ship script.
        For the player, they do that and also call doWorldScriptEvent:.
*/
/*	Plist data as event arguments (ADR-0055 item 4): each converted by OOJSValueFromPList, so a
        string, number or collection gives the JS value the boxed Foundation object gave, and an entity
        is passed as oo::PListObject(entity). The id forms above stay for OOObject arguments.
*/

/*	Convenience to send an event with raw JS values, for example:
        ShipScriptEvent(context, ship, "doSomething", OOJSValueFromDouble(context, 42));
        The argument values are owned by the macro, which frees them (with
        OOJSFreeValue()) after the event has been sent, so they must be fresh
        values that are not used again afterwards.
*/
#define ShipScriptEvent(context, ship, event, ...)                                          \
    do {                                                                                    \
        OOJSVal argv[] = { __VA_ARGS__ };                                                   \
        int argc = sizeof argv / sizeof *argv;                                              \
        [ship doScriptEvent:OOJSID(event) inContext:context withArguments:argv count:argc]; \
        for (int oojsArgIndex = 0; oojsArgIndex < argc; oojsArgIndex++) {                   \
            OOJSFreeValue(context, argv[oojsArgIndex]);                                     \
        }                                                                                   \
    } while (0)

#define ShipScriptEventNoCx(ship, event, ...)                          \
    do {                                                               \
        JSContext* oojsEventContext = OOJSAcquireContext();            \
        ShipScriptEvent(oojsEventContext, ship, event, ##__VA_ARGS__); \
        OOJSRelinquishContext(oojsEventContext);                       \
    } while (0)

@end

#ifdef OO_DEBUG_MONITOR_ENABLED
@interface ShipEntity (Debug)

- (OOShipGroup*)rawEscortGroup;

@end
#endif

@interface Entity (SubEntityRelationship)

/*	For the common case of testing whether foo is a ship, bar is a ship, bar
        is a subentity of foo and this relationship is represented sanely.
*/
- (BOOL)isShipWithSubEntityShip:(Entity*)other;

@end

// Implemented by the facade's category in ShipEntity+ObjCBridge.mm with -init, -initBypassForPlayer
// and -dealloc (they need the Objective-C object as self), while the class's @implementation is
// still ShipEntity.mm; declared in the class's interface before slice 1.
@interface ShipEntity (OOObjCBridge)

- (id)cxx_initWithKey:(const std::string&)key definition:(const oo::PList&)dict OO_RETURNS_RETAINED;

@end

// Slice 2 of docs/phases/3-slices/ShipEntity.md: members of cxx::ShipEntity, forwarded by the
// category of the same name in ShipEntity+ObjCBridge.mm (the class's @implementation, still in
// ShipEntity.mm, stays complete). Declared in the class's interface before the slice.
@interface ShipEntity (OOSlice2)

- (BOOL)cxx_setUpFromDictionary:(const oo::PList&)shipDict;

@end

// Slice 3 of docs/phases/3-slices/ShipEntity.md: members of cxx::ShipEntity, forwarded by the
// category of the same name in ShipEntity+ObjCBridge.mm (the class's @implementation, still in
// ShipEntity.mm, stays complete). Declared in the class's interface before the slice.
@interface ShipEntity (OOSlice3)

- (BOOL)setUpShipFromDictionary:(const oo::PList&)shipDict; // flipped with its family (bead oo-3rb.282)
- (void)setSubIdx:(NSUInteger)value;
- (NSUInteger)subIdx;
- (NSUInteger)maxShipSubEntities;
- (std::optional<std::string>)cxx_serializeShipSubEntities;
- (void)cxx_deserializeShipSubEntitiesFrom:(const std::string&)string;
- (BOOL)setUpSubEntities;
- (GLfloat)frustumRadius;
- (BOOL)setUpOneSubentity:(const oo::PList&)subentDict;
- (BOOL)setUpOneFlasher:(const oo::PList&)subentDict;

@end

// Slice 4 of docs/phases/3-slices/ShipEntity.md: members of cxx::ShipEntity, forwarded by the
// category of the same name in ShipEntity+ObjCBridge.mm (the class's @implementation, still in
// ShipEntity.mm, stays complete). Declared in the class's interface before the slice.
@interface ShipEntity (OOSlice4)

- (BOOL)cxx_setUpOneStandardSubentity:(const oo::PList&)subentDict asTurret:(BOOL)asTurret;
- (BOOL)isTemplateCargoPod;
- (void)setUpCargoType:(const std::string&)cargoString;
- (void)removeScript;
- (void)clearSubEntities; // Releases and clears subentity array, after making sure subentities don't think ship is owner.
- (Quaternion)subEntityRotationalVelocity;
- (void)setSubEntityRotationalVelocity:(Quaternion)rv;
- (std::optional<std::string>)cxx_shortDescriptionComponents;
- (GLfloat)sunGlareFilter;
- (void)setSunGlareFilter:(GLfloat)newValue;
- (GLfloat)accuracy;
- (void)setAccuracy:(GLfloat)new_accuracy;
- (OOMesh*)mesh;
- (void)setMesh:(OOMesh*)mesh;
- (BoundingBox)totalBoundingBox;
- (Vector)forwardVector;
- (Vector)upVector;
- (Vector)rightVector;
- (BOOL)scriptedMisjump;
- (void)setScriptedMisjump:(BOOL)newValue;
- (GLfloat)scriptedMisjumpRange;
- (void)setScriptedMisjumpRange:(GLfloat)newValue;
- (std::vector<oo::ObjCRef<Entity*>>)subEntities; // a snapshot; empty when there are none
- (NSUInteger)subEntityCount;
- (BOOL)hasSubEntity:(Entity<OOSubEntity>*)sub;
- (std::vector<oo::ObjCRef<Entity*>>)subEntityEnumerator; // snapshot, same as -subEntities
- (std::vector<oo::ObjCRef<ShipEntity*>>)cxx_shipSubEntities;
- (std::vector<oo::ObjCRef<Entity*>>)flasherEnumerator; // flasher subentities, a snapshot (the C++ OOFlasherEntity's objects)
- (std::vector<oo::ObjCRef<Entity*>>)cxx_exhausts; // the C++ OOExhaustPlumeEntity's objects
- (ShipEntity*)subEntityTakingDamage;
- (void)setSubEntityTakingDamage:(ShipEntity*)sub;
- (OOScript*)shipScript;
- (OOScript*)shipAIScript;
- (OOTimeAbsolute)shipAIScriptWakeTime;
- (void)setAIScriptWakeTime:(OOTimeAbsolute)t;

@end

/*	The ship adopts <OOBeaconEntity> here and not in its interface (slice 5, bead oo-ddnn8): the
        protocol's methods are forwarders in the slices' categories, and a category that implements a
        method of a protocol the class itself adopts is warned about as one the class will implement
        (-Wobjc-protocol-method-implementation). Adopted by a category with no @implementation, the
        ship conforms as before and the protocol's other methods stay in ShipEntity.mm.
*/
@interface ShipEntity (OOBeaconEntity) <OOBeaconEntity>
@end

// Slice 5 of docs/phases/3-slices/ShipEntity.md: members of cxx::ShipEntity, forwarded by the
// category of the same name in ShipEntity+ObjCBridge.mm (the class's @implementation, still in
// ShipEntity.mm, stays complete). Declared in the class's interface before the slice.
@interface ShipEntity (OOSlice5)

- (BoundingBox)findBoundingBoxRelativeToPosition:(HPVector)opv i:(Vector)i j:(Vector)j k:(Vector)k;
- (Octree*)octree;
- (float)volume;
- (GLfloat)doesHitLine:(HPVector)v0 v1:(HPVector)v1;
- (GLfloat)doesHitLine:(HPVector)v0 v1:(HPVector)v1 hitEntity:(ShipEntity**)hitEntity;
- (GLfloat)doesHitLine:(HPVector)v0 v1:(HPVector)v1 withPosition:(HPVector)o i:(Vector)i j:(Vector)j k:(Vector)k; // for subentities
- (void)wasAddedToUniverse;
- (void)wasRemovedFromUniverse;
- (HPVector)absoluteTractorPosition;
- (std::optional<std::string>)beaconCode;
- (void)setBeaconCode:(const std::optional<std::string>&)bcode;
- (std::optional<std::string>)beaconLabel;
- (void)setBeaconLabel:(const std::optional<std::string>&)blabel;
- (BOOL)isVisible;
- (BOOL)isBeacon;
- (id<OOHUDBeaconIcon>)beaconDrawable;
- (Entity<OOBeaconEntity>*)prevBeacon;
- (Entity<OOBeaconEntity>*)nextBeacon;
- (void)setPrevBeacon:(Entity<OOBeaconEntity>*)beaconShip;
- (void)setNextBeacon:(Entity<OOBeaconEntity>*)beaconShip;
- (void)setIsBoulder:(BOOL)flag;
- (BOOL)isBoulder;
- (BOOL)isMinable;
- (BOOL)countsAsKill;
- (void)setUpEscorts;
- (void)setUpMixedEscorts;

@end

// Slice 6 of docs/phases/3-slices/ShipEntity.md: members of cxx::ShipEntity, forwarded by the
// category of the same name in ShipEntity+ObjCBridge.mm (the class's @implementation, still in
// ShipEntity.mm, stays complete). Declared in the class's interface before the slice.
@interface ShipEntity (OOSlice6)

- (void)setUpOneEscort:(ShipEntity*)escorter inGroup:(OOShipGroup*)escortGroup withRole:(const std::string&)escortRole atPosition:(HPVector)ex_pos andCount:(uint8_t)currentEscortCount;
- (std::optional<std::string>)cxx_shipDataKey;
- (std::optional<std::string>)cxx_shipDataKeyAutoRole; // "[key]"
- (void)cxx_setShipDataKey:(const std::optional<std::string>&)key;
- (oo::PList)cxx_shipInfoDictionary;
- (std::vector<Vector>)cxx_weaponOffsetsFrom:(const oo::PList&)dict withKey:(const std::string&)key inMode:(const std::string&)mode;
- (std::vector<Vector>)cxx_aftWeaponOffset;
- (std::vector<Vector>)cxx_forwardWeaponOffset;
- (std::vector<Vector>)cxx_portWeaponOffset;
- (std::vector<Vector>)cxx_starboardWeaponOffset;
- (BOOL)isFrangible;
- (BOOL)suppressFlightNotifications;
- (OOScanClass)scanClass;
- (BOOL)canCollide;
- (BoundingBox)findSubentityBoundingBox;
- (Triangle)absoluteIJKForSubentity;
- (void)addSubentityToCollisionRadius:(Entity<OOSubEntity>*)subent;
- (ShipEntity*)launchPodWithCrew:(const std::vector<oo::ObjCRef<OOCharacter*>>&)podCrew;
- (BOOL)validForAddToUniverse;

@end

// Slice 7 of docs/phases/3-slices/ShipEntity.md: members of cxx::ShipEntity, forwarded by the
// category of the same name in ShipEntity+ObjCBridge.mm (the class's @implementation, still in
// ShipEntity.mm, stays complete). Declared in the class's interface before the slice.
@interface ShipEntity (OOSlice7)

- (void)update:(OOTimeDelta)delta_t;

@end

// Slice 8 of docs/phases/3-slices/ShipEntity.md: members of cxx::ShipEntity, forwarded by the
// category of the same name in ShipEntity+ObjCBridge.mm (the class's @implementation, still in
// ShipEntity.mm, stays complete). Declared in the class's interface before the slice.
@interface ShipEntity (OOSlice8)

- (void)processBehaviour:(OOTimeDelta)delta_t;
- (void)noteFrustration:(const std::string&)context;
- (void)respondToAttackFrom:(Entity*)from becauseOf:(Entity*)other;
- (BOOL)cxx_hasOneEquipmentItem:(const std::string&)itemKey includeWeapons:(BOOL)includeMissiles whileLoading:(BOOL)loading;
- (BOOL)cxx_hasOneEquipmentItem:(const std::string&)itemKey includeMissiles:(BOOL)includeMissiles whileLoading:(BOOL)loading;
- (BOOL)hasPrimaryWeapon:(OOWeaponType)weaponType;
- (NSUInteger)cxx_countEquipmentItem:(const std::string&)eqkey;
- (BOOL)hasEquipmentItem:(const oo::PList&)equipmentKeys includeWeapons:(BOOL)includeWeapons whileLoading:(BOOL)loading; // This can take a string or an array of strings (a set's keys as an array). If a collection, returns YES if ship has _any_ of the specified equipment. If includeWeapons is NO, missiles and primary weapons are not checked.
- (BOOL)hasEquipmentItem:(const oo::PList&)equipmentKeys; // Short for hasEquipmentItem:foo includeWeapons:NO whileLoading:NO
- (BOOL)cxx_hasEquipmentItemProviding:(const std::string&)equipmentType;
- (std::optional<std::string>)cxx_equipmentItemProviding:(const std::string&)equipmentType;
- (BOOL)hasAllEquipment:(const oo::PList&)equipmentKeys includeWeapons:(BOOL)includeWeapons whileLoading:(BOOL)loading; // Like hasEquipmentItem:includeWeapons:, but requires _all_ elements in collection.
- (BOOL)hasAllEquipment:(const oo::PList&)equipmentKeys; // Short for hasAllEquipment:foo includeWeapons:NO
- (BOOL)hasHyperspaceMotor;
- (float)hyperspaceSpinTime;
- (void)setHyperspaceSpinTime:(float)newValue;

@end

// Slice 9 of docs/phases/3-slices/ShipEntity.md: members of cxx::ShipEntity, forwarded by the
// category of the same name in ShipEntity+ObjCBridge.mm (the class's @implementation, still in
// ShipEntity.mm, stays complete). Declared in the class's interface before the slice.
@interface ShipEntity (OOSlice9)

- (BOOL)canAddEquipment:(const std::string&)equipmentKey inContext:(const std::string&)context; // flipped with its family (bead oo-3rb.258). Test ability to add equipment, taking equipment-specific constriants into account.
- (OOWeaponFacingSet)weaponFacings;
- (OOWeaponType)weaponTypeIDForFacing:(OOWeaponFacing)facing strict:(BOOL)strict;
- (OOEquipmentType*)weaponTypeForFacing:(OOWeaponFacing)facing strict:(BOOL)strict;
- (std::vector<oo::ObjCRef<OOEquipmentType*>>)missilesList; // flipped with its family (bead oo-3rb.259)
- (oo::PList)passengerListForScripting; // flipped with its family (bead oo-3rb.259): an array
- (oo::PList)parcelListForScripting; // flipped with its family (bead oo-3rb.259): an array
- (oo::PList)contractListForScripting; // flipped with its family (bead oo-3rb.259): an array
- (OOEquipmentType*)generateMissileEquipmentTypeFrom:(const std::string&)role;
- (std::vector<oo::ObjCRef<OOEquipmentType*>>)cxx_equipmentListForScripting;
- (BOOL)cxx_equipmentValidToAdd:(const std::string&)equipmentKey inContext:(const std::string&)context; // Actual test if equipment satisfies validation criteria.
- (BOOL)cxx_equipmentValidToAdd:(const std::string&)equipmentKey whileLoading:(BOOL)loading inContext:(const std::string&)context;
- (BOOL)setWeaponMount:(OOWeaponFacing)facing toWeapon:(const std::string&)eqKey; // flipped with its family (bead oo-3rb.258)
- (BOOL)addEquipmentItem:(const std::string&)equipmentKey inContext:(const std::string&)context; // flipped with its family (bead oo-3rb.258)
- (BOOL)addEquipmentItem:(const std::string&)equipmentKey withValidation:(BOOL)validateAddition inContext:(const std::string&)context; // flipped with its family (bead oo-3rb.258)
- (std::vector<std::string>)cxx_equipmentKeys; // a snapshot, in order added
- (NSUInteger)equipmentCount;

@end

// Slice 10 of docs/phases/3-slices/ShipEntity.md: members of cxx::ShipEntity, forwarded by the
// category of the same name in ShipEntity+ObjCBridge.mm (the class's @implementation, still in
// ShipEntity.mm, stays complete). Declared in the class's interface before the slice.
@interface ShipEntity (OOSlice10)

- (void)removeEquipmentItem:(const std::string&)equipmentKey; // flipped with its family (bead oo-3rb.258)
- (BOOL)removeExternalStore:(OOEquipmentType*)eqType;
- (OOEquipmentType*)verifiedMissileTypeFromRole:(const std::string&)requestedRole;
- (OOEquipmentType*)selectMissile;
- (void)removeAllEquipment;
- (OOCreditsQuantity)removeMissiles;
- (NSUInteger)parcelCount;
- (NSUInteger)passengerCount;
- (NSUInteger)passengerCapacity;
- (NSUInteger)missileCount;
- (NSUInteger)missileCapacity;
- (NSUInteger)extraCargo;
- (BOOL)hasScoop;
- (BOOL)hasFuelScoop;
- (BOOL)hasCargoScoop;
- (BOOL)hasECM;
- (BOOL)hasCloakingDevice;
- (BOOL)hasMilitaryScannerFilter;
- (BOOL)hasMilitaryJammer;
- (BOOL)hasExpandedCargoBay;
- (BOOL)hasShieldBooster;
- (BOOL)hasMilitaryShieldEnhancer;
- (BOOL)hasHeatShield;
- (BOOL)hasFuelInjection;
- (BOOL)hasCascadeMine;
- (BOOL)hasEscapePod;
- (BOOL)hasDockingComputer;
- (BOOL)hasGalacticHyperdrive;
- (float)shieldBoostFactor;
- (float)maxForwardShieldLevel;
- (float)maxAftShieldLevel;
- (float)shieldRechargeRate;
- (double)maxHyperspaceDistance;

@end

// Slice 11 of docs/phases/3-slices/ShipEntity.md: members of cxx::ShipEntity, forwarded by the
// category of the same name in ShipEntity+ObjCBridge.mm (the class's @implementation, still in
// ShipEntity.mm, stays complete). Declared in the class's interface before the slice.
@interface ShipEntity (OOSlice11)

- (float)afterburnerFactor;
- (float)afterburnerRate;
- (void)setAfterburnerFactor:(GLfloat)newValue;
- (void)setAfterburnerRate:(GLfloat)newValue;
- (float)maxThrust;
- (void)setMaxThrust:(GLfloat)newValue;
- (float)thrust;
- (void)behaviour_stop_still:(double)delta_t;
- (void)behaviour_idle:(double)delta_t;
- (void)behaviour_tumble:(double)delta_t;
- (void)behaviour_tractored:(double)delta_t;
- (void)behaviour_track_target:(double)delta_t;
- (void)behaviour_intercept_target:(double)delta_t;
- (void)behaviour_attack_break_off_target:(double)delta_t;
- (void)behaviour_attack_slow_dogfight:(double)delta_t;
- (void)behaviour_evasive_action:(double)delta_t;

@end

// Slice 12 of docs/phases/3-slices/ShipEntity.md: members of cxx::ShipEntity, forwarded by the
// category of the same name in ShipEntity+ObjCBridge.mm (the class's @implementation, still in
// ShipEntity.mm, stays complete). Declared in the class's interface before the slice.
@interface ShipEntity (OOSlice12)

- (void)behaviour_attack_target:(double)delta_t;
- (void)behaviour_attack_broadside:(double)delta_t;
- (void)behaviour_attack_broadside_left:(double)delta_t;
- (void)behaviour_attack_broadside_right:(double)delta_t;
- (void)behaviour_attack_broadside_target:(double)delta_t leftside:(BOOL)leftside;
- (void)behaviour_close_to_broadside_range:(double)delta_t;
- (void)behaviour_close_with_target:(double)delta_t;

@end

// Slice 13 of docs/phases/3-slices/ShipEntity.md: members of cxx::ShipEntity, forwarded by the
// category of the same name in ShipEntity+ObjCBridge.mm (the class's @implementation, still in
// ShipEntity.mm, stays complete). Declared in the class's interface before the slice.
@interface ShipEntity (OOSlice13)

- (void)behaviour_attack_sniper:(double)delta_t;
- (void)behaviour_fly_to_target_six:(double)delta_t;
- (void)behaviour_attack_mining_target:(double)delta_t;
- (void)behaviour_attack_fly_to_target:(double)delta_t;

@end

// Slice 14 of docs/phases/3-slices/ShipEntity.md: members of cxx::ShipEntity, forwarded by the
// category of the same name in ShipEntity+ObjCBridge.mm (the class's @implementation, still in
// ShipEntity.mm, stays complete). Declared in the class's interface before the slice.
@interface ShipEntity (OOSlice14)

- (void)behaviour_attack_fly_from_target:(double)delta_t;
- (void)behaviour_running_defense:(double)delta_t;
- (void)behaviour_flee_target:(double)delta_t;
- (void)behaviour_fly_range_from_destination:(double)delta_t;
- (void)behaviour_face_destination:(double)delta_t;
- (void)behaviour_land_on_planet:(double)delta_t;
- (void)behaviour_formation_form_up:(double)delta_t;

@end

// Slice 15 of docs/phases/3-slices/ShipEntity.md: members of cxx::ShipEntity, forwarded by the
// category of the same name in ShipEntity+ObjCBridge.mm (the class's @implementation, still in
// ShipEntity.mm, stays complete). Declared in the class's interface before the slice.
@interface ShipEntity (OOSlice15)

- (void)behaviour_fly_to_destination:(double)delta_t;
- (void)behaviour_fly_from_destination:(double)delta_t;
- (void)behaviour_avoid_collision:(double)delta_t;
- (void)behaviour_track_as_turret:(double)delta_t;
- (void)behaviour_fly_thru_navpoints:(double)delta_t;
- (void)behaviour_scripted_ai:(double)delta_t;
- (float)reactionTime;
- (void)setReactionTime:(float)newReactionTime;
- (HPVector)calculateTargetPosition;

@end

/*	The ship adopts <OOSubEntity> here and not in its interface (slice 16, bead oo-d96oe), for the
        reason it adopts <OOBeaconEntity> by a category (slice 5): -drawSubEntityImmediate:translucent:
        is a forwarder in the slice's category (ADR-0056 amendment oo-xmajv item 2).
*/
@interface ShipEntity (OOSubEntity) <OOSubEntity>
@end

// Slice 16 of docs/phases/3-slices/ShipEntity.md: members of cxx::ShipEntity, forwarded by the
// category of the same name in ShipEntity+ObjCBridge.mm (the class's @implementation, still in
// ShipEntity.mm, stays complete). Declared in the class's interface before the slice.
@interface ShipEntity (OOSlice16)

- (void)startTrackingCurve;
- (void)updateTrackingCurve;
- (void)calculateTrackingCurve;
- (void)drawImmediate:(bool)immediate translucent:(bool)translucent;
#ifdef OO_DEBUG_MONITOR_ENABLED
- (void)drawDebugStuff;
#endif
- (void)drawSubEntityImmediate:(bool)immediate translucent:(bool)translucent;
- (GLfloat*)scannerDisplayColorForShip:(ShipEntity*)otherShip isHostile:(BOOL)isHostile flash:(BOOL)flash scannerDisplayColor1:(OOColor*)scannerDisplayColor1 scannerDisplayColor2:(OOColor*)scannerDisplayColor2 scannerDisplayColorH1:(OOColor*)scannerDisplayColorH1 scannerDisplayColorH2:(OOColor*)scannerDisplayColorH2;
- (void)setScannerDisplayColor1:(OOColor*)color1;
- (void)setScannerDisplayColor2:(OOColor*)color2;
- (OOColor*)scannerDisplayColor1;
- (OOColor*)scannerDisplayColor2;
- (void)setScannerDisplayColorHostile1:(OOColor*)color1;
- (void)setScannerDisplayColorHostile2:(OOColor*)color2;
- (OOColor*)scannerDisplayColorHostile1;
- (OOColor*)scannerDisplayColorHostile2;
- (BOOL)isCloaked;
- (BOOL)cloakPassive;
- (void)setCloaked:(BOOL)cloak;
- (BOOL)hasAutoCloak;
- (void)setAutoCloak:(BOOL)automatic;
- (BOOL)isJammingScanning;
- (void)addSubEntity:(Entity<OOSubEntity>*)sub;
- (void)setOwner:(Entity*)who_owns_entity;
- (void)applyThrust:(double)delta_t;
- (void)orientationChanged;

@end

// Slice 17 of docs/phases/3-slices/ShipEntity.md: members of cxx::ShipEntity, forwarded by the
// category of the same name in ShipEntity+ObjCBridge.mm (the class's @implementation, still in
// ShipEntity.mm, stays complete). Declared in the class's interface before the slice.
@interface ShipEntity (OOSlice17)

- (void)applyRoll:(GLfloat)roll1 andClimb:(GLfloat)climb1;
- (void)applyRoll:(GLfloat)roll1 climb:(GLfloat)climb1 andYaw:(GLfloat)yaw1;
- (void)applyAttitudeChanges:(double)delta_t;
- (void)avoidCollision;
- (void)resumePostProximityAlert;
- (double)messageTime;
- (void)setMessageTime:(double)value;
- (OOShipGroup*)group;
- (void)setGroup:(OOShipGroup*)group;
- (OOShipGroup*)escortGroup;
- (void)setEscortGroup:(OOShipGroup*)group; // Only for use in unconventional set-up situations.
- (OOShipGroup*)stationGroup; // should probably be defined in stationEntity.m
- (BOOL)hasEscorts;
- (std::vector<oo::ObjCRef<ShipEntity*>>)cxx_escorts; // the escorts (the group without self), a snapshot
- (std::vector<oo::ObjCRef<ShipEntity*>>)escortArray; // the same snapshot
- (uint8_t)escortCount;
- (uint8_t)pendingEscortCount;
- (void)setPendingEscortCount:(uint8_t)count;
- (uint8_t)maxEscortCount;
- (void)setMaxEscortCount:(uint8_t)newCount;
- (NSUInteger)turretCount;
- (Entity*)proximityAlert;
- (void)setProximityAlert:(ShipEntity*)targetEntity;
- (std::optional<std::string>)cxx_name; // nullopt: none (bead oo-3rb.289.13)
- (std::optional<std::string>)cxx_shipUniqueName;
- (std::optional<std::string>)cxx_shipClassName;
- (std::optional<std::string>)displayName; // flipped with its family (bead oo-3rb.267)
- (std::optional<std::string>)cxx_scanDescriptionForScripting;
- (std::optional<std::string>)cxx_scanDescription;
- (void)cxx_setName:(const std::optional<std::string>&)inName; // PlayerEntity blocks it
- (void)cxx_setShipUniqueName:(const std::optional<std::string>&)inName;
- (void)cxx_setShipClassName:(const std::optional<std::string>&)inName;
- (void)cxx_setDisplayName:(const std::optional<std::string>&)inName;
- (void)cxx_setScanDescription:(const std::optional<std::string>&)inName;

@end

// Slice 18 of docs/phases/3-slices/ShipEntity.md: members of cxx::ShipEntity, forwarded by the
// category of the same name in ShipEntity+ObjCBridge.mm (the class's @implementation, still in
// ShipEntity.mm, stays complete). Declared in the class's interface before the slice.
@interface ShipEntity (OOSlice18)

- (std::optional<std::string>)identFromShip:(ShipEntity*)otherShip; // Name displayed to other ships (flipped with its family, bead oo-3rb.279)
- (BOOL)hasRole:(const std::string&)role; // flipped with its family (bead oo-3rb.280)
- (OORoleSet*)roleSet;
- (void)addRole:(const std::string&)role;
- (void)cxx_addRole:(const std::string&)role withProbability:(float)probability;
- (void)cxx_removeRole:(const std::string&)role;
- (std::optional<std::string>)cxx_primaryRole;
- (void)setPrimaryRole:(const std::string&)role; // shared selector (proposed ADR-0043), called by name (ADR-0055 item 5)
- (BOOL)cxx_hasPrimaryRole:(const std::string&)role;
- (BOOL)isPolice; // Scan class is CLASS_POLICE
- (BOOL)isThargoid; // Scan class is CLASS_THARGOID
- (BOOL)isTrader; // Primary role is "trader" || isPlayer
- (BOOL)isPirate; // Primary role is "pirate"
- (BOOL)isMissile; // Primary role has suffix "MISSILE"
- (BOOL)isMine; // Primary role has suffix "MINE"
- (BOOL)isWeapon; // isMissile || isWeapon
- (BOOL)isEscort; // Primary role is "escort" or "wingman"
- (BOOL)isShuttle; // Primary role is "shuttle"
- (BOOL)isTurret; // Behaviour is BEHAVIOUR_TRACK_AS_TURRET
- (BOOL)isPirateVictim; // Primary role is listed in pirate-victim-roles.plist
- (BOOL)isExplicitlyUnpiloted; // Has unpiloted = yes in its shipdata.plist entry
- (BOOL)isUnpiloted; // Explicitly unpiloted, hulk, rock, cargo, debris etc; an open-ended criterion that may grow.
- (BOOL)hasHostileTarget;
- (BOOL)isHostileTo:(Entity*)entity;
- (GLfloat)weaponRange;
- (void)setWeaponRange:(GLfloat)value;
- (void)setWeaponDataFromType:(OOWeaponType)weapon_type;
- (float)energyRechargeRate; // final rate after energy units
- (void)setEnergyRechargeRate:(GLfloat)newValue;
- (float)weaponRechargeRate;
- (void)setWeaponRechargeRate:(float)value;
- (void)setWeaponEnergy:(float)value;
- (OOWeaponFacing)currentWeaponFacing;
- (GLfloat)scannerRange;
- (void)setScannerRange:(GLfloat)value;
- (Vector)reference;
- (void)setReference:(Vector)v;
- (BOOL)reportAIMessages;
- (void)setReportAIMessages:(BOOL)yn;
- (void)transitionToAegisNone;
- (OOPlanetEntity*)findNearestPlanet;
- (Entity<OOStellarBody>*)findNearestStellarBody; // NOTE: includes sun.
- (OOPlanetEntity*)findNearestPlanetExcludingMoons;

@end

// Slice 19 of docs/phases/3-slices/ShipEntity.md: members of cxx::ShipEntity, forwarded by the
// category of the same name in ShipEntity+ObjCBridge.mm (the class's @implementation, still in
// ShipEntity.mm, stays complete). Declared in the class's interface before the slice.
@interface ShipEntity (OOSlice19)

- (OOAegisStatus)checkForAegis;
- (void)forceAegisCheck;
- (BOOL)withinStationAegis;
- (Entity<OOStellarBody>*)lastAegisLock;
- (void)setLastAegisLock:(Entity<OOStellarBody>*)lastAegisLock;
- (OOSystemID)homeSystem;
- (OOSystemID)destinationSystem;
- (void)setHomeSystem:(OOSystemID)s;
- (void)setDestinationSystem:(OOSystemID)s;
- (void)setStatus:(OOEntityStatus)stat;
- (void)setLaunchDelay:(double)delay;
- (std::optional<std::vector<oo::ObjCRef<OOCharacter*>>>)cxx_crew; // nullopt: unpiloted
- (void)cxx_setCrew:(const std::optional<std::vector<oo::ObjCRef<OOCharacter*>>>&)crewArray;
- (void)cxx_setSingleCrewWithRole:(const std::string&)crewRole;
- (std::vector<oo::PList>)cxx_crewForScripting; // each member's -infoForScripting
- (void)setStateMachine:(const std::string&)ai_desc; // shared selector (proposed ADR-0043), called by name (ADR-0055 item 5)
- (void)setAI:(AI*)ai;
- (AI*)getAI;
- (BOOL)hasAutoAI;
- (BOOL)hasNewAI;
- (BOOL)hasAutoWeapons;
- (void)cxx_setShipScript:(const std::optional<std::string>&)script_name;
- (double)frustration;
- (OOFuelQuantity)fuel;
- (void)setFuel:(OOFuelQuantity)amount;
- (OOFuelQuantity)fuelCapacity;
- (GLfloat)fuelChargeRate;

@end

// Slice 20 of docs/phases/3-slices/ShipEntity.md: members of cxx::ShipEntity, forwarded by the
// category of the same name in ShipEntity+ObjCBridge.mm (the class's @implementation, still in
// ShipEntity.mm, stays complete). Declared in the class's interface before the slice.
@interface ShipEntity (OOSlice20)

- (void)applySticks:(double)delta_t;
- (void)setRoll:(double)amount;
- (void)setRawRoll:(double)amount; // does not multiply by PI/2
- (void)setPitch:(double)amount;
- (void)setYaw:(double)amount;
- (void)setThrust:(double)amount;
- (void)setThrustForDemo:(float)factor;
- (void)setBounty:(OOCreditsQuantity)amount;
- (void)setBounty:(OOCreditsQuantity)amount withReason:(OOLegalStatusReason)reason;
- (void)setBounty:(OOCreditsQuantity)amount withReasonAsString:(const std::string&)reason; // flipped with its family (bead oo-3rb.259)
- (OOCreditsQuantity)bounty;
- (int)legalStatus;
- (void)cxx_setCommodity:(const std::string&)co_type andAmount:(OOCargoQuantity)co_amount;
- (void)cxx_setCommodityForPod:(const std::optional<std::string>&)co_type andAmount:(OOCargoQuantity)co_amount; // nullopt empties the pod, as nil did
- (std::optional<std::string>)cxx_commodityType;
- (OOCargoQuantity)commodityAmount;
- (OOCargoQuantity)maxAvailableCargoSpace;
- (void)setMaxAvailableCargoSpace:(OOCargoQuantity)newValue;
- (OOCargoQuantity)availableCargoSpace;
- (OOCargoQuantity)cargoQuantityOnBoard;
- (OOCargoType)cargoType;
- (std::vector<oo::ObjCRef<ShipEntity*>>*)cxx_cargo; // the live cargo pods (nullptr for a nil receiver)
- (NSUInteger)cxx_cargoCount; // the number of cargo pods held
- (oo::PList)cargoListForScripting; // flipped with its family (bead oo-3rb.259): an array of dictionaries
- (void)setCargo:(const std::vector<oo::ObjCRef<ShipEntity*>>&)some_cargo;
- (BOOL)cxx_addCargo:(const std::vector<oo::ObjCRef<ShipEntity*>>&)some_cargo;
- (BOOL)cxx_removeCargo:(const std::string&)commodity amount:(OOCargoQuantity)amount;
- (BOOL)showScoopMessage;
- (OOCargoFlag)cargoFlag;
- (void)setCargoFlag:(OOCargoFlag)flag;
- (void)setSpeed:(double)amount;
- (void)setDesiredSpeed:(double)amount;
- (double)desiredSpeed;

@end

// Slice 21 of docs/phases/3-slices/ShipEntity.md: members of cxx::ShipEntity, forwarded by the
// category of the same name in ShipEntity+ObjCBridge.mm (the class's @implementation, still in
// ShipEntity.mm, stays complete). Declared in the class's interface before the slice.
@interface ShipEntity (OOSlice21)

- (double)desiredRange;
- (void)setDesiredRange:(double)amount;
- (double)cruiseSpeed;
- (void)increase_flight_speed:(double)delta;
- (void)decrease_flight_speed:(double)delta;
- (void)increase_flight_roll:(double)delta;
- (void)decrease_flight_roll:(double)delta;
- (void)increase_flight_pitch:(double)delta;
- (void)decrease_flight_pitch:(double)delta;
- (void)increase_flight_yaw:(double)delta;
- (void)decrease_flight_yaw:(double)delta;
- (GLfloat)flightRoll;
- (GLfloat)flightPitch;
- (GLfloat)flightYaw;
- (GLfloat)flightSpeed;
- (GLfloat)maxFlightPitch;
- (GLfloat)maxFlightSpeed;
- (GLfloat)maxFlightRoll;
- (GLfloat)maxFlightYaw;
- (void)setMaxFlightPitch:(GLfloat)newValue;
- (void)setMaxFlightSpeed:(GLfloat)newValue;
- (void)setMaxFlightRoll:(GLfloat)newValue;
- (void)setMaxFlightYaw:(GLfloat)newValue;
- (GLfloat)speedFactor;
- (GLfloat)temperature;
- (void)setTemperature:(GLfloat)value;
- (float)randomEjectaTemperature;
- (float)randomEjectaTemperatureWithMaxFactor:(float)factor;
- (GLfloat)heatInsulation;
- (void)setHeatInsulation:(GLfloat)value;
- (int)damage;
- (void)dealEnergyDamage:(GLfloat)baseDamage atRange:(GLfloat)range withBias:(GLfloat)velocityBias;
- (void)dealEnergyDamageWithinDesiredRange;
- (void)dealMomentumWithinDesiredRange:(double)amount;
- (BOOL)isHulk;
- (void)setHulk:(BOOL)isNowHulk;
- (void)noteTakingDamage:(double)amount from:(Entity*)entity type:(OOShipDamageType)type;
- (void)noteKilledBy:(Entity*)whom damageType:(OOShipDamageType)type;

@end

// Slice 22 of docs/phases/3-slices/ShipEntity.md: members of cxx::ShipEntity, forwarded by the
// category of the same name in ShipEntity+ObjCBridge.mm (the class's @implementation, still in
// ShipEntity.mm, stays complete). Declared in the class's interface before the slice.
@interface ShipEntity (OOSlice22)

- (void)getDestroyedBy:(Entity*)whom damageType:(OOShipDamageType)type;
- (void)rescaleBy:(GLfloat)factor;
- (void)rescaleBy:(GLfloat)factor writeToCache:(BOOL)writeToCache;
- (void)releaseCargoPodsDebris;
- (void)setIsWreckage:(BOOL)isw;
- (BOOL)showDamage;
- (void)becomeExplosion;
- (void)becomeEnergyBlast;
- (void)broadcastEnergyBlastImminent;
- (void)removeExhaust:(OOExhaustPlumeEntity*)exhaust; // the C++ plume (bead oo-9ht.110)

@end

// Slice 23 of docs/phases/3-slices/ShipEntity.md: members of cxx::ShipEntity, forwarded by the
// category of the same name in ShipEntity+ObjCBridge.mm (the class's @implementation, still in
// ShipEntity.mm, stays complete). Declared in the class's interface before the slice.
@interface ShipEntity (OOSlice23)

- (void)removeFlasher:(OOFlasherEntity*)flasher; // the C++ flasher (bead oo-9ht.107)
- (void)subEntityDied:(ShipEntity*)sub;
- (void)subEntityReallyDied:(ShipEntity*)sub;
- (Vector)positionOffsetForAlignment:(const std::string&)align;
- (void)becomeLargeExplosion:(double)factor;
- (void)collectBountyFor:(ShipEntity*)other;
- (OOComparisonResult)compareBeaconCodeWith:(Entity<OOBeaconEntity>*)other;
- (GLfloat)weaponRecoveryTime;
- (GLfloat)laserHeatLevel;
- (GLfloat)laserHeatLevelAft;
- (GLfloat)laserHeatLevelForward;
- (GLfloat)laserHeatLevelPort;
- (GLfloat)laserHeatLevelStarboard;
- (GLfloat)hullHeatLevel;
- (GLfloat)entityPersonality;
- (GLint)entityPersonalityInt;
- (uint32_t)randomSeedForShaders;
- (void)setEntityPersonalityInt:(uint16_t)value;
- (void)setSuppressExplosion:(BOOL)suppress;
- (void)resetExhaustPlumes;
- (void)checkScanner;
- (void)checkScannerIgnoringUnpowered;
- (ShipEntity**)scannedShips;
- (int)numberOfScannedShips;
- (Entity*)foundTarget;
- (void)setFoundTarget:(Entity*)targetEntity;
- (Entity*)primaryAggressor;
- (void)setPrimaryAggressor:(Entity*)targetEntity;
- (Entity*)lastEscortTarget;
- (void)setLastEscortTarget:(Entity*)targetEntity;

@end

// Slice 24 of docs/phases/3-slices/ShipEntity.md: members of cxx::ShipEntity, forwarded by the
// category of the same name in ShipEntity+ObjCBridge.mm (the class's @implementation, still in
// ShipEntity.mm, stays complete). Declared in the class's interface before the slice.
@interface ShipEntity (OOSlice24)

- (Entity*)thankedShip;
- (void)setThankedShip:(Entity*)targetEntity;
- (Entity*)rememberedShip;
- (void)setRememberedShip:(Entity*)targetEntity;
- (StationEntity*)targetStation;
- (void)setTargetStation:(Entity*)targetEntity;
- (BOOL)isValidTarget:(Entity*)target;
- (void)addTarget:(Entity*)targetEntity;
- (void)removeTarget:(Entity*)targetEntity;
- (BOOL)canStillTrackPrimaryTarget;
- (id)primaryTarget;
- (id)primaryTargetWithoutValidityCheck;
- (BOOL)isFriendlyTo:(ShipEntity*)otherShip;
- (ShipEntity*)shipHitByLaser;
- (void)setShipHitByLaser:(ShipEntity*)ship;
- (void)noteLostTarget;
- (void)noteLostTargetAndGoIdle;
- (void)noteTargetDestroyed:(ShipEntity*)target;
- (OOBehaviour)behaviour;
- (void)setBehaviour:(OOBehaviour)cond;
- (HPVector)destination;
- (HPVector)coordinates;
- (void)setCoordinate:(HPVector)coord;
- (HPVector)distance_six:(GLfloat)dist;
- (HPVector)distance_twelve:(GLfloat)dist withOffset:(GLfloat)offset;
- (void)trackOntoTarget:(double)delta_t withDForward:(GLfloat)dp;
- (double)ballTrackLeadingTarget:(double)delta_t atTarget:(Entity*)target;

@end

// Slice 25 of docs/phases/3-slices/ShipEntity.md: members of cxx::ShipEntity, forwarded by the
// category of the same name in ShipEntity+ObjCBridge.mm (the class's @implementation, still in
// ShipEntity.mm, stays complete). Declared in the class's interface before the slice.
@interface ShipEntity (OOSlice25)

- (void)setEvasiveJink:(GLfloat)z;
- (void)evasiveAction:(double)delta_t;
- (double)trackPrimaryTarget:(double)delta_t retreat:(BOOL)retreat;
- (double)trackSideTarget:(double)delta_t leftside:(BOOL)leftside;

@end

// Slice 26 of docs/phases/3-slices/ShipEntity.md: members of cxx::ShipEntity, forwarded by the
// category of the same name in ShipEntity+ObjCBridge.mm (the class's @implementation, still in
// ShipEntity.mm, stays complete). Declared in the class's interface before the slice.
@interface ShipEntity (OOSlice26)

- (double)missileTrackPrimaryTarget:(double)delta_t;
- (double)trackDestination:(double)delta_t retreat:(BOOL)retreat;
- (GLfloat)rollToMatchUp:(Vector)up_vec rotating:(GLfloat)match_roll;
- (GLfloat)rangeToDestination;
- (std::vector<oo::ObjCRef<ShipEntity*>>)cxx_collisionExceptions;
- (void)addCollisionException:(ShipEntity*)ship;
- (void)removeCollisionException:(ShipEntity*)ship;
- (BOOL)collisionExceptedFor:(ShipEntity*)ship;
- (NSUInteger)defenseTargetCount;
- (std::vector<oo::ObjCRef<ShipEntity*>>)allDefenseTargets; // the live ones (zeroed references skipped)
- (std::vector<oo::ObjCRef<ShipEntity*>>)cxx_defenseTargets; // a snapshot in the weak set's order, up to the first zeroed reference
- (BOOL)addDefenseTarget:(Entity*)target;
- (void)validateDefenseTargets;
- (BOOL)isDefenseTarget:(Entity*)target;
- (void)removeAllDefenseTargets;
- (void)removeDefenseTarget:(Entity*)target;
- (double)rangeToPrimaryTarget;
- (double)rangeToSecondaryTarget:(Entity*)target;
- (double)approachAspectToPrimaryTarget;
- (BOOL)hasProximityAlertIgnoringTarget:(BOOL)ignore_target;

@end

// Slice 27 of docs/phases/3-slices/ShipEntity.md: members of cxx::ShipEntity, forwarded by the
// category of the same name in ShipEntity+ObjCBridge.mm (the class's @implementation, still in
// ShipEntity.mm, stays complete). Declared in the class's interface before the slice.
@interface ShipEntity (OOSlice27)

- (GLfloat)currentAimTolerance;
- (GLfloat)lookingAtSunWithThresholdAngleCos:(GLfloat)thresholdAngleCos;
- (BOOL)onTarget:(OOWeaponFacing)direction withWeapon:(OOWeaponType)weapon;
- (BOOL)fireWeapon:(OOWeaponType)weapon_type direction:(OOWeaponFacing)direction range:(double)range;
- (BOOL)fireMainWeapon:(double)range;
- (BOOL)fireAftWeapon:(double)range;
- (BOOL)firePortWeapon:(double)range;
- (BOOL)fireStarboardWeapon:(double)range;
- (OOTimeDelta)shotTime;
- (void)resetShotTime;
- (BOOL)fireTurretCannon:(double)range;
- (void)setLaserColor:(OOColor*)color;
- (void)setExhaustEmissiveColor:(OOColor*)color;
- (OOColor*)laserColor;
- (OOColor*)exhaustEmissiveColor;

@end

// Slice 28 of docs/phases/3-slices/ShipEntity.md: members of cxx::ShipEntity, forwarded by the
// category of the same name in ShipEntity+ObjCBridge.mm (the class's @implementation, still in
// ShipEntity.mm, stays complete). Declared in the class's interface before the slice.
@interface ShipEntity (OOSlice28)

- (BOOL)fireSubentityLaserShot:(double)range;
- (BOOL)fireDirectLaserShot:(double)range;
- (BOOL)fireDirectLaserDefensiveShot;
- (BOOL)fireDirectLaserShotAt:(Entity*)my_target;
- (std::vector<Vector>)cxx_laserPortOffset:(OOWeaponFacing)direction;
- (BOOL)cxx_fireLaserShotInDirection:(OOWeaponFacing)direction weaponIdentifier:(const std::string&)weaponIdentifier;
- (void)adjustMissedShots:(int)delta;
- (int)missedShots;
- (void)throwSparks;
- (void)considerFiringMissile:(double)delta_t;
- (Vector)missileLaunchPosition;
- (ShipEntity*)fireMissile;

@end

// Slice 29 of docs/phases/3-slices/ShipEntity.md: members of cxx::ShipEntity, forwarded by the
// category of the same name in ShipEntity+ObjCBridge.mm (the class's @implementation, still in
// ShipEntity.mm, stays complete). Declared in the class's interface before the slice.
@interface ShipEntity (OOSlice29)

- (ShipEntity*)cxx_fireMissileWithIdentifier:(const std::optional<std::string>&)identifier andTarget:(Entity*)target; // nullopt: a random missile from the list
- (BOOL)isMissileFlagSet;
- (void)setIsMissileFlag:(BOOL)newValue;
- (OOTimeDelta)missileLoadTime;
- (void)setMissileLoadTime:(OOTimeDelta)newMissileLoadTime;
- (void)noticeECM;
- (BOOL)fireECM;
- (BOOL)activateCloakingDevice;
- (void)deactivateCloakingDevice;
- (BOOL)launchCascadeMine;
- (ShipEntity*)launchEscapeCapsule;
- (void)dumpCargo; // shared selector (proposed ADR-0043), called by name (ADR-0055 item 5)
- (ShipEntity*)cxx_dumpCargoItem:(const std::optional<std::string>&)preferred; // nullopt: the first pod
- (OOCargoType)dumpItem:(ShipEntity*)jetto;

@end

// Slice 30 of docs/phases/3-slices/ShipEntity.md: members of cxx::ShipEntity, forwarded by the
// category of the same name in ShipEntity+ObjCBridge.mm (the class's @implementation, still in
// ShipEntity.mm, stays complete). Declared in the class's interface before the slice.
@interface ShipEntity (OOSlice30)

- (void)manageCollisions;
- (BOOL)collideWithShip:(ShipEntity*)other;
- (Vector)thrustVector;
- (Vector)velocity;
- (void)setTotalVelocity:(Vector)vel; // Set velocity to vel - thrustVector, effectively setting the instanteneous velocity to vel.
- (void)adjustVelocity:(Vector)xVel;
- (void)addImpactMoment:(Vector)moment fraction:(GLfloat)howmuch;
- (BOOL)canScoop:(ShipEntity*)other;
- (void)getTractoredBy:(ShipEntity*)other;
- (void)scoopIn:(ShipEntity*)other;
- (void)suppressTargetLost;
- (void)scoopUp:(ShipEntity*)other;
- (void)scoopUpProcess:(ShipEntity*)other processEvents:(BOOL)proc_events processMessages:(BOOL)proc_messages;

@end

// Slice 31 of docs/phases/3-slices/ShipEntity.md: members of cxx::ShipEntity, forwarded by the
// category of the same name in ShipEntity+ObjCBridge.mm (the class's @implementation, still in
// ShipEntity.mm, stays complete). Declared in the class's interface before the slice.
@interface ShipEntity (OOSlice31)

- (BOOL)cascadeIfAppropriateWithDamageAmount:(double)amount cascadeOwner:(Entity*)owner;
- (void)takeEnergyDamage:(double)amount from:(Entity*)ent becauseOf:(Entity*)other weaponIdentifier:(const std::string&)weaponIdentifier;
- (BOOL)abandonShip;
- (void)takeScrapeDamage:(double)amount from:(Entity*)ent;
- (void)takeHeatDamage:(double)amount;
- (void)enterDock:(StationEntity*)station;
- (void)leaveDock:(StationEntity*)station;
- (void)enterWormhole:(WormholeEntity*)w_hole;
- (void)enterWormhole:(WormholeEntity*)w_hole replacing:(BOOL)replacing;
- (void)enterWitchspace;
- (void)leaveWitchspace;

@end

// Slice 32 of docs/phases/3-slices/ShipEntity.md: members of cxx::ShipEntity, forwarded by the
// category of the same name in ShipEntity+ObjCBridge.mm (the class's @implementation, still in
// ShipEntity.mm, stays complete). Declared in the class's interface before the slice.
@interface ShipEntity (OOSlice32)

- (BOOL)witchspaceLeavingEffects;
- (void)markAsOffender:(int)offence_value;
- (void)markAsOffender:(int)offence_value withReason:(OOLegalStatusReason)reason;
- (void)switchLightsOn;
- (void)switchLightsOff;
- (BOOL)lightsActive;
- (void)setDestination:(HPVector)dest;
- (void)setEscortDestination:(HPVector)dest;
- (BOOL)canAcceptEscort:(ShipEntity*)potentialEscort;
- (BOOL)acceptAsEscort:(ShipEntity*)other_ship;
- (void)updateEscortFormation;
- (void)refreshEscortPositions;
- (HPVector)coordinatesForEscortPosition:(unsigned)idx;
- (void)deployEscorts;
- (void)dockEscorts;
- (void)setTargetToNearestStationIncludingHostiles:(BOOL)includeHostiles;
- (void)setTargetToNearestFriendlyStation;
- (void)setTargetToNearestStation;
- (void)setTargetToSystemStation;

@end

// Slice 33 of docs/phases/3-slices/ShipEntity.md: members of cxx::ShipEntity, forwarded by the
// category of the same name in ShipEntity+ObjCBridge.mm (the class's @implementation, still in
// ShipEntity.mm, stays complete). Declared in the class's interface before the slice.
@interface ShipEntity (OOSlice33)

- (void)landOnPlanet:(OOPlanetEntity*)planet;
- (void)abortDocking;
- (oo::PList)cxx_dockingInstructions; // null: none
- (void)broadcastThargoidDestroyed;
- (void)broadcastHitByLaserFrom:(ShipEntity*)aggressor_ship;
- (void)cxx_sendMessage:(const std::string&)message_text toShip:(ShipEntity*)other_ship withUnpilotedOverride:(BOOL)unpilotedOverride;
- (void)cxx_sendExpandedMessage:(const std::string&)message_text toShip:(ShipEntity*)other_ship;
- (void)broadcastAIMessage:(const std::string&)ai_message;
- (void)broadcastMessage:(const std::string&)message_text withUnpilotedOverride:(BOOL)unpilotedOverride;
- (void)setCommsMessageColor;
- (void)receiveCommsMessage:(const std::string&)message_text from:(ShipEntity*)other; // flipped with its family (bead oo-3rb.259)
- (void)cxx_commsMessage:(const std::string&)valueString withUnpilotedOverride:(BOOL)unpilotedOverride;
- (BOOL)markedForFines;
- (BOOL)markForFines;
- (BOOL)isMining;
- (void)interpretAIMessage:(const std::string&)message; // shared selector (proposed ADR-0043), called by name (ADR-0055 item 5)
- (BoundingBox)findBoundingBoxRelativeTo:(Entity*)other i:(Vector)_i j:(Vector)_j k:(Vector)_k;
- (void)spawn:(const std::string&)roles_number; // shared selector (proposed ADR-0043), called by name (ADR-0055 item 5)
- (int)checkShipsInVicinityForWitchJumpExit;
- (BOOL)trackCloseContacts;
- (void)setTrackCloseContacts:(BOOL)value;
#if OO_SALVAGE_SUPPORT
- (void)claimAsSalvage;
- (void)sendCoordinatesToPilot;
#endif

@end

// Slice 34 of docs/phases/3-slices/ShipEntity.md: members of cxx::ShipEntity, forwarded by the
// category of the same name in ShipEntity+ObjCBridge.mm (the class's @implementation, still in
// ShipEntity.mm, stays complete). Declared in the class's interface before the slice.
@interface ShipEntity (OOSlice34)

#if OO_SALVAGE_SUPPORT
- (void)pilotArrived;
#endif
#ifdef OO_DEBUG_MONITOR_ENABLED
- (void)dumpSelfState;
#endif
- (OOJSScript*)script;
- (oo::PList)scriptInfo; // flipped with its family (bead oo-3rb.284): empty dict when there is none
- (void)overrideScriptInfo:(const oo::PList&)override; // Add items from override (a dictionary, or null for none) to scriptInfo, replacing in case of duplicates. Used for subentities.
- (Entity*)entityForShaderProperties;
- (void)setDemoShip:(OOScalar)demoRate;
- (BOOL)isDemoShip;
- (void)setDemoStartTime:(OOTimeAbsolute)time;
- (OOTimeAbsolute)getDemoStartTime;
- (void)doScriptEvent:(OOJSPropID)message;
- (void)doScriptEvent:(OOJSPropID)message withArgument:(id)argument;
- (void)doScriptEvent:(OOJSPropID)message withArgument:(id)argument1 andArgument:(id)argument2;
- (void)cxx_doScriptEvent:(OOJSPropID)message withPListArguments:(const std::vector<oo::PList>&)arguments;
// argv is borrowed: the caller remains responsible for freeing the values.
- (void)doScriptEvent:(OOJSPropID)message withArguments:(JSValue*)argv count:(int)argc;
- (void)doScriptEvent:(OOJSPropID)message inContext:(JSContext*)context withArguments:(JSValue*)argv count:(int)argc;
- (void)cxx_reactToAIMessage:(const std::string&)message context:(const std::optional<std::string>&)debugContext; // Immediate message
- (void)sendAIMessage:(const std::string&)message; // Queued message.
- (void)cxx_doScriptEvent:(OOJSPropID)scriptEvent andReactToAIMessage:(const std::string&)aiMessage;
- (void)cxx_doScriptEvent:(OOJSPropID)scriptEvent withArgument:(id)argument andReactToAIMessage:(const std::string&)aiMessage;
- (OOAlertCondition)alertCondition; // quick calc for shaders
- (OOAlertCondition)realAlertCondition; // full calculation for scripting
- (void)doNothing;
#ifdef OO_DEBUG_MONITOR_ENABLED
- (std::optional<std::string>)descriptionForObjDump;
#endif

@end

// The category ShipEntity (ScriptMethods) of ShipEntityScriptMethods.mm (bead oo-42dr): members of
// cxx::ShipEntity defined in that file (ADR-0056 amendments oo-o89 item 4 and oo-9fwb), forwarded
// by the category of the same name in ShipEntity+ObjCBridge.mm for the Objective-C callers that
// remain (OOJSShip, the legacy script engine).
@interface ShipEntity (ScriptMethods)

// Foundation sweep (proposed ADR-0043, bead oo-tm7d): std::nullopt ejects nothing, as nil did.
- (ShipEntity*)ejectShipOfType:(const std::optional<std::string>&)shipKey; // Note: ship type, not role.
- (ShipEntity*)ejectShipOfRole:(const std::optional<std::string>&)role;

- (std::vector<oo::ObjCRef<ShipEntity*>>)spawnShipsWithRole:(const std::string&)role count:(NSUInteger)count;

@end

// The category ShipEntity (LoadRestore) of ShipEntityLoadRestore.mm (bead oo-kw44): members of
// cxx::ShipEntity defined in that file (ADR-0056 amendment oo-42dr), forwarded by the category of
// the same name in ShipEntity+ObjCBridge.mm for the callers that still message the facade
// (cxx::WormholeEntity).
@interface ShipEntity (LoadRestore)

/*	Produces a property list representation of a specific ship. Intended for
        use with wormholes, but should probably generalize quite well.

        The optional "context" (nullptr for none) is used to synchronise certain
        state when saving multiple ships - currently, groups. It is not a property
        list and does not need to be saved alongside the ships.
*/
- (oo::PList)savedShipDictionaryWithContext:(OOShipSaveContext*)context;

/*	Restore a ship from a property list representation generated with
        -savedShipDictionary. If the ship can't be restored and fallback is YES,
        an attempt will be made to generate a new ship with the same primary role.
*/
+ (id)shipRestoredFromDictionary:(const oo::PList&)dictionary useFallback:(BOOL)fallback context:(OOShipSaveContext*)context;

@end

// The category ShipEntity (AI) of ShipEntityAI.mm, slice 1 of docs/phases/3-slices/ShipEntityAI.md
// (bead oo-iebuz): members of cxx::ShipEntity defined in that file (ADR-0056 amendment oo-42dr),
// forwarded by the category of the same name in ShipEntity+ObjCBridge.mm.
@interface ShipEntity (AI)

//	AI methods also used in other code.

- (void)setAITo:(const std::string&)aiString; // called by name (ADR-0055 item 5)
- (void)setAIScript:(const std::string&)aiString;
- (void)switchAITo:(const std::string&)aiString; // called by name (ADR-0055 item 5)

- (void)scanForHostiles;
- (BOOL)performHyperSpaceToSpecificSystem:(OOSystemID)systemID;
- (void)scanForNearestIncomingMissile;

- (void)enterTargetWormhole;
- (void)enterPlayerWormhole;

- (void)wormholeEscorts;
- (void)wormholeEntireGroup;

- (BOOL)suggestEscortTo:(ShipEntity*)mother;

- (void)groupAttackTarget;

- (void)performAttack;
- (void)performCollect;
- (void)performEscort;
- (void)performFaceDestination;
- (void)performFlee;
- (void)performFlyToRangeFromDestination;
- (void)performHold;
- (void)performIdle;
- (void)performIntercept;
- (void)performLandOnPlanet;
- (void)performMining;
- (void)performScriptedAI;
- (void)performScriptedAttackAI;
- (void)performStop;
- (void)performTumble;

- (void)broadcastDistressMessage;
- (void)broadcastDistressMessageWithDumping:(BOOL)dumpCargo;

- (void)requestDockingCoordinates;
- (void)recallDockingInstructions;

- (void)performBuoyTumble;

@end

// The category ShipEntity (OOAIPrivate) of ShipEntityAI.mm, slice 1 of docs/phases/3-slices/ShipEntityAI.md
// (bead oo-iebuz): members of cxx::ShipEntity defined in that file (ADR-0056 amendment oo-42dr),
// forwarded by the category of the same name in ShipEntity+ObjCBridge.mm.
@interface ShipEntity (OOAIPrivate)

- (void)checkFoundTarget;

- (BOOL)performHyperSpaceExitReplace:(BOOL)replace;
- (BOOL)performHyperSpaceExitReplace:(BOOL)replace toSystem:(OOSystemID)systemID;

- (void)scanForNearestShipWithPredicate:(EntityFilterPredicate)predicate parameter:(void*)parameter;
- (void)scanForNearestShipWithNegatedPredicate:(EntityFilterPredicate)predicate parameter:(void*)parameter;

- (void)acceptDistressMessageFrom:(ShipEntity*)other;

@end

// Slice 2 of docs/phases/3-slices/ShipEntityAI.md (bead oo-xurzn): methods of the category
// ShipEntity (PureAI) of ShipEntityAI.mm that are members of cxx::ShipEntity, forwarded by the category
// of the same name in ShipEntity+ObjCBridge.mm.
@interface ShipEntity (OOAISlice2)

- (void)setStateTo:(const std::string&)state; // called by name (ADR-0055 item 5)
- (void)pauseAI:(const std::string&)intervalString; // called by name (ADR-0055 item 5)
- (void)randomPauseAI:(const std::string&)intervalString; // called by name (ADR-0055 item 5)
- (void)dropMessages:(const std::string&)messageString; // called by name (ADR-0055 item 5)
- (void)debugDumpPendingMessages;
- (void)setDestinationToCurrentLocation;
- (void)setDestinationToJinkPosition;
- (void)setDesiredRangeTo:(const std::string&)rangeString; // called by name (ADR-0055 item 5)
- (void)setDesiredRangeForWaypoint;
- (void)setSpeedTo:(const std::string&)speedString; // called by name (ADR-0055 item 5)
- (void)setSpeedFactorTo:(const std::string&)speedString; // called by name (ADR-0055 item 5)
- (void)setSpeedToCruiseSpeed;
- (void)setThrustFactorTo:(const std::string&)thrustFactorString; // called by name (ADR-0055 item 5)
- (void)setTargetToPrimaryAggressor;
- (void)addPrimaryAggressorAsDefenseTarget;
- (void)scanForNearestMerchantman;
- (void)scanForRandomMerchantman;
- (void)scanForLoot;
- (void)scanForRandomLoot;
- (void)setTargetToFoundTarget;
- (void)addFoundTargetAsDefenseTarget;
- (void)checkForFullHold;
- (void)getWitchspaceEntryCoordinates;
- (void)setDestinationFromCoordinates;
- (void)setCoordinatesFromPosition;
- (void)fightOrFleeMissile;
- (void)setCourseToPlanet;
- (void)setTakeOffFromPlanet;
- (void)landOnPlanet;
- (void)checkTargetLegalStatus;
- (void)checkOwnLegalStatus;
- (void)exitAIWithMessage:(const std::string&)message; // called by name (ADR-0055 item 5)
- (void)setDestinationToTarget;
- (void)setDestinationWithinTarget;
- (void)checkCourseToDestination;

@end

// Slice 3 of docs/phases/3-slices/ShipEntityAI.md (bead oo-wc9o3): methods of the category
// ShipEntity (PureAI) of ShipEntityAI.mm that are members of cxx::ShipEntity, forwarded by the category
// of the same name in ShipEntity+ObjCBridge.mm.
@interface ShipEntity (OOAISlice3)

- (void)checkAegis;
- (void)checkEnergy;
- (void)checkHeatInsulation;
- (void)findNewDefenseTarget;
- (void)scanForOffenders;
- (void)setCourseToWitchpoint;
- (void)setDestinationToWitchpoint;
- (void)setDestinationToStationBeacon;
- (void)performHyperSpaceExit;
- (void)performHyperSpaceExitWithoutReplacing;
- (void)disengageAutopilot;
- (void)wormholeGroup;
- (void)commsMessage:(const std::string&)valueString; // called by name (ADR-0055 item 5)
- (void)commsMessageByUnpiloted:(const std::string&)valueString; // called by name (ADR-0055 item 5)
- (void)ejectCargo;
- (void)scanForThargoid;
- (void)scanForNonThargoid;
- (void)thargonCheckMother;
- (void)becomeUncontrolledThargon;
- (void)checkDistanceTravelled;
- (void)fightOrFleeHostiles;
- (void)suggestEscort;
- (void)escortCheckMother;
- (void)checkGroupOddsVersusTarget;
- (void)scanForFormationLeader;
- (void)messageMother:(const std::string&)msgString; // called by name (ADR-0055 item 5)
- (void)messageSelf:(const std::string&)msgString;
- (void)setPlanetPatrolCoordinates;
- (void)setSunSkimStartCoordinates;
- (void)setSunSkimEndCoordinates;
- (void)setSunSkimExitCoordinates;
- (void)patrolReportIn;
- (void)checkForMotherStation;
- (void)sendTargetCommsMessage:(const std::string&)message; // called by name (ADR-0055 item 5)
- (void)markTargetForFines;
- (void)markTargetForOffence:(const std::string&)valueString; // called by name (ADR-0055 item 5)
- (void)storeTarget;

@end

// The category ShipEntity (PureAI) of ShipEntityAI.mm, slice 4 of docs/phases/3-slices/ShipEntityAI.md
// (bead oo-lqyhf): members of cxx::ShipEntity defined in that file (ADR-0056 amendment oo-42dr),
// forwarded by the category of the same name in ShipEntity+ObjCBridge.mm.
@interface ShipEntity (PureAI)

// Methods used only by AI.

- (void)recallStoredTarget;

- (void)scanForRocks;

- (void)setDestinationToDockingAbort;

- (void)requestNewTarget;

- (void)rollD:(const std::string&)die_number; // called by name (ADR-0055 item 5)

- (void)scanForNearestShipWithPrimaryRole:(const std::string&)scanRole; // called by name (ADR-0055 item 5)
- (void)scanForNearestShipHavingRole:(const std::string&)scanRole; // called by name (ADR-0055 item 5)
- (void)scanForNearestShipWithAnyPrimaryRole:(const std::string&)scanRoles; // called by name (ADR-0055 item 5)
- (void)scanForNearestShipHavingAnyRole:(const std::string&)scanRoles; // called by name (ADR-0055 item 5)
- (void)scanForNearestShipWithScanClass:(const std::string&)scanScanClass; // called by name (ADR-0055 item 5)

- (void)scanForNearestShipWithoutPrimaryRole:(const std::string&)scanRole; // called by name (ADR-0055 item 5)
- (void)scanForNearestShipNotHavingRole:(const std::string&)scanRole; // called by name (ADR-0055 item 5)
- (void)scanForNearestShipWithoutAnyPrimaryRole:(const std::string&)scanRoles; // called by name (ADR-0055 item 5)
- (void)scanForNearestShipNotHavingAnyRole:(const std::string&)scanRoles; // called by name (ADR-0055 item 5)
- (void)scanForNearestShipWithoutScanClass:(const std::string&)scanScanClass; // called by name (ADR-0055 item 5)

- (void)setCoordinates:(const std::string&)system_x_y_z; // called by name (ADR-0055 item 5)

- (void)checkForNormalSpace;

- (void)setTargetToRandomStation;
- (void)setTargetToLastStation;

- (void)addFuel:(const std::string&)fuel_number; // called by name (ADR-0055 item 5)

- (void)scriptActionOnTarget:(const std::string&)action; // called by name (ADR-0055 item 5)

- (void)sendScriptMessage:(const std::string&)message; // called by name (ADR-0055 item 5)

- (void)ai_throwSparks;

- (void)explodeSelf;

- (void)ai_debugMessage:(const std::string&)message; // called by name (ADR-0055 item 5)

// racing code.
- (void)targetFirstBeaconWithCode:(const std::string&)code; // called by name (ADR-0055 item 5)
- (void)targetNextBeaconWithCode:(const std::string&)code; // called by name (ADR-0055 item 5)
- (void)setRacepointsFromTarget;
- (void)performFlyRacepoints;

// defense targets

- (void)scanForNearestShipMatchingPredicate:(const std::string&)predicateExpression;
- (void)safeScriptActionOnTarget:(const std::string&)action;

@end

// The sends of ShipEntity.mm's C functions to classes they reach as Objective-C objects (amendment
// oo-9ht.139 item 3); deleted with this header.
double ShipEntityStellarBodyRadius(Entity<OOStellarBody>* stellar); // [stellar radius]
GLfloat ShipEntityPlayerBaseMass(void); // [PLAYER baseMass]

namespace oo {

// The root's crossings, typed (amendment oo-up4b item 3).
inline cxx::ShipEntity* ToCxx(::ShipEntity* entity)
{
    return static_cast<cxx::ShipEntity*>(ToCxx(static_cast<::Entity*>(entity)));
}

inline ::ShipEntity* ToObjC(cxx::ShipEntity* entity)
{
    return (::ShipEntity*)ToObjC(static_cast<cxx::Entity*>(entity));
}

} // namespace oo

#endif // SHIPENTITY_OBJCBRIDGE_H
