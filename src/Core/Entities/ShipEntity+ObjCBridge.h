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
an Objective-C ship's adapter over cxx::ShipEntity (oo::ObjCEntity<cxx::ShipEntity>), so
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

@interface ShipEntity : OOEntityWithDrawable <OOSubEntity, OOBeaconEntity> {
@public
    cxx::ShipEntity* _cxxShip; // _cxxEntity, typed; borrowed, set by the initialiser
}

// ship brains
- (void)setStateMachine:(const std::string&)ai_desc; // shared selector (proposed ADR-0043), called by name (ADR-0055 item 5)
- (void)setAI:(AI*)ai;
- (AI*)getAI;
- (BOOL)hasAutoAI;
- (BOOL)hasNewAI;
- (void)cxx_setShipScript:(const std::optional<std::string>&)script_name;
- (void)removeScript;
- (OOScript*)shipScript;
- (OOScript*)shipAIScript;
- (OOTimeAbsolute)shipAIScriptWakeTime;
- (void)setAIScriptWakeTime:(OOTimeAbsolute)t;
- (double)frustration;
- (void)setLaunchDelay:(double)delay;

- (void)interpretAIMessage:(const std::string&)message; // shared selector (proposed ADR-0043), called by name (ADR-0055 item 5)

- (GLfloat)accuracy;
- (void)setAccuracy:(GLfloat)new_accuracy;

- (OOMesh*)mesh;
- (void)setMesh:(OOMesh*)mesh;

- (BoundingBox)totalBoundingBox;

- (Vector)forwardVector;
- (Vector)upVector;
- (Vector)rightVector;

- (std::vector<oo::ObjCRef<Entity*>>)subEntities; // a snapshot; empty when there are none
- (NSUInteger)subEntityCount;
- (BOOL)hasSubEntity:(Entity<OOSubEntity>*)sub;

- (std::vector<oo::ObjCRef<Entity*>>)subEntityEnumerator; // snapshot, same as -subEntities
- (std::vector<oo::ObjCRef<OOFlasherEntity*>>)flasherEnumerator; // flasher subentities, a snapshot
// The ship / exhaust subentities, a snapshot in subentity order (empty for a nil receiver).
- (std::vector<oo::ObjCRef<ShipEntity*>>)cxx_shipSubEntities;
- (std::vector<oo::ObjCRef<OOExhaustPlumeEntity*>>)cxx_exhausts;

- (ShipEntity*)subEntityTakingDamage;
- (void)setSubEntityTakingDamage:(ShipEntity*)sub;

- (void)clearSubEntities; // Releases and clears subentity array, after making sure subentities don't think ship is owner.

- (Quaternion)subEntityRotationalVelocity;
- (void)setSubEntityRotationalVelocity:(Quaternion)rv;

// subentities management
- (std::optional<std::string>)cxx_serializeShipSubEntities;
- (void)cxx_deserializeShipSubEntitiesFrom:(const std::string&)string;
- (NSUInteger)maxShipSubEntities;
- (void)setSubIdx:(NSUInteger)value;
- (NSUInteger)subIdx;

- (Octree*)octree;
- (float)volume;

// octree collision hunting
- (GLfloat)doesHitLine:(HPVector)v0 v1:(HPVector)v1;
- (GLfloat)doesHitLine:(HPVector)v0 v1:(HPVector)v1 hitEntity:(ShipEntity**)hitEntity;
- (GLfloat)doesHitLine:(HPVector)v0 v1:(HPVector)v1 withPosition:(HPVector)o i:(Vector)i j:(Vector)j k:(Vector)k; // for subentities

- (BoundingBox)findBoundingBoxRelativeToPosition:(HPVector)opv i:(Vector)i j:(Vector)j k:(Vector)k;

- (HPVector)absoluteTractorPosition;

// beacons // definitions now in <OOBeaconEntity> protocol

- (void)setIsBoulder:(BOOL)flag;
- (BOOL)isBoulder;
- (BOOL)isMinable;

- (BOOL)countsAsKill;

- (void)setUpEscorts;
- (void)updateEscortFormation;

- (BOOL)cxx_setUpFromDictionary:(const oo::PList&)shipDict;
- (BOOL)setUpShipFromDictionary:(const oo::PList&)shipDict; // flipped with its family (bead oo-3rb.282)
- (BOOL)setUpSubEntities;
- (BOOL)cxx_setUpOneStandardSubentity:(const oo::PList&)subentDict asTurret:(BOOL)asTurret;
- (GLfloat)frustumRadius;

- (std::optional<std::string>)cxx_shipDataKey;
- (std::optional<std::string>)cxx_shipDataKeyAutoRole; // "[key]"
- (void)cxx_setShipDataKey:(const std::optional<std::string>&)key;

- (oo::PList)cxx_shipInfoDictionary;

- (std::vector<Vector>)cxx_weaponOffsetsFrom:(const oo::PList&)dict withKey:(const std::string&)key inMode:(const std::string&)mode;
- (std::vector<Vector>)cxx_aftWeaponOffset;
- (std::vector<Vector>)cxx_forwardWeaponOffset;
- (std::vector<Vector>)cxx_portWeaponOffset;
- (std::vector<Vector>)cxx_starboardWeaponOffset;
- (BOOL)hasAutoWeapons;

- (BOOL)isFrangible;
- (BOOL)suppressFlightNotifications;

- (void)respondToAttackFrom:(Entity*)from becauseOf:(Entity*)other;

// Equipment
- (OOWeaponFacingSet)weaponFacings;
- (BOOL)hasEquipmentItem:(const oo::PList&)equipmentKeys includeWeapons:(BOOL)includeWeapons whileLoading:(BOOL)loading; // This can take a string or an array of strings (a set's keys as an array). If a collection, returns YES if ship has _any_ of the specified equipment. If includeWeapons is NO, missiles and primary weapons are not checked.
- (BOOL)hasEquipmentItem:(const oo::PList&)equipmentKeys; // Short for hasEquipmentItem:foo includeWeapons:NO whileLoading:NO
- (NSUInteger)cxx_countEquipmentItem:(const std::string&)eqkey;
- (std::optional<std::string>)cxx_equipmentItemProviding:(const std::string&)equipmentType;
- (BOOL)cxx_hasEquipmentItemProviding:(const std::string&)equipmentType;
- (BOOL)hasAllEquipment:(const oo::PList&)equipmentKeys includeWeapons:(BOOL)includeWeapons whileLoading:(BOOL)loading; // Like hasEquipmentItem:includeWeapons:, but requires _all_ elements in collection.
- (BOOL)hasAllEquipment:(const oo::PList&)equipmentKeys; // Short for hasAllEquipment:foo includeWeapons:NO
- (BOOL)setWeaponMount:(OOWeaponFacing)facing toWeapon:(const std::string&)eqKey; // flipped with its family (bead oo-3rb.258)
- (BOOL)canAddEquipment:(const std::string&)equipmentKey inContext:(const std::string&)context; // flipped with its family (bead oo-3rb.258). Test ability to add equipment, taking equipment-specific constriants into account.
- (BOOL)cxx_equipmentValidToAdd:(const std::string&)equipmentKey inContext:(const std::string&)context; // Actual test if equipment satisfies validation criteria.
- (BOOL)cxx_equipmentValidToAdd:(const std::string&)equipmentKey whileLoading:(BOOL)loading inContext:(const std::string&)context;
- (BOOL)addEquipmentItem:(const std::string&)equipmentKey inContext:(const std::string&)context; // flipped with its family (bead oo-3rb.258)
- (BOOL)addEquipmentItem:(const std::string&)equipmentKey withValidation:(BOOL)validateAddition inContext:(const std::string&)context; // flipped with its family (bead oo-3rb.258)
- (BOOL)hasHyperspaceMotor;
- (float)hyperspaceSpinTime;
- (void)setHyperspaceSpinTime:(float)newValue;

- (std::vector<std::string>)cxx_equipmentKeys; // a snapshot, in order added
- (NSUInteger)equipmentCount;
- (void)removeEquipmentItem:(const std::string&)equipmentKey; // flipped with its family (bead oo-3rb.258)
- (void)removeAllEquipment;
- (OOEquipmentType*)selectMissile;
- (OOCreditsQuantity)removeMissiles;

// Internal, subject to change. Use the methods above instead.
- (BOOL)cxx_hasOneEquipmentItem:(const std::string&)itemKey includeWeapons:(BOOL)includeMissiles whileLoading:(BOOL)loading;
- (BOOL)cxx_hasOneEquipmentItem:(const std::string&)itemKey includeMissiles:(BOOL)includeMissiles whileLoading:(BOOL)loading;
- (BOOL)hasPrimaryWeapon:(OOWeaponType)weaponType;
- (BOOL)removeExternalStore:(OOEquipmentType*)eqType;

// Passengers and parcels - not supported for NPCs, but interface is here for genericity.
- (NSUInteger)parcelCount;
- (NSUInteger)passengerCount;
- (NSUInteger)passengerCapacity;

- (NSUInteger)missileCount;
- (NSUInteger)missileCapacity;

- (NSUInteger)extraCargo;

// Tests for the various special-cased equipment items
// (Nowadays, more convenience methods)
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

// Shield information derived from equipment. NPCs can't have shields, but that should change at some point.
- (float)shieldBoostFactor;
- (float)maxForwardShieldLevel;
- (float)maxAftShieldLevel;
- (float)shieldRechargeRate;

- (double)maxHyperspaceDistance;
- (float)afterburnerFactor;
- (float)afterburnerRate;
- (void)setAfterburnerFactor:(GLfloat)newValue;
- (void)setAfterburnerRate:(GLfloat)newValue;
- (float)maxThrust;
- (float)thrust;

- (void)setMaxThrust:(GLfloat)newValue;
- (void)setMaxFlightPitch:(GLfloat)newValue;
- (void)setMaxFlightSpeed:(GLfloat)newValue;
- (void)setMaxFlightRoll:(GLfloat)newValue;
- (void)setMaxFlightYaw:(GLfloat)newValue;
- (void)setEnergyRechargeRate:(GLfloat)newValue;

- (void)processBehaviour:(OOTimeDelta)delta_t;
// Behaviours
- (void)behaviour_stop_still:(double)delta_t;
- (void)behaviour_idle:(double)delta_t;
- (void)behaviour_tumble:(double)delta_t;
- (void)behaviour_tractored:(double)delta_t;
- (void)behaviour_track_target:(double)delta_t;
- (void)behaviour_intercept_target:(double)delta_t;
- (void)behaviour_attack_target:(double)delta_t;
- (void)behaviour_attack_slow_dogfight:(double)delta_t;
- (void)behaviour_evasive_action:(double)delta_t;
- (void)behaviour_attack_break_off_target:(double)delta_t;
- (void)behaviour_fly_to_target_six:(double)delta_t;
- (void)behaviour_attack_mining_target:(double)delta_t;
- (void)behaviour_attack_fly_to_target:(double)delta_t;
- (void)behaviour_attack_fly_from_target:(double)delta_t;
- (void)behaviour_running_defense:(double)delta_t;
- (void)behaviour_flee_target:(double)delta_t;
- (void)behaviour_attack_broadside:(double)delta_t;
- (void)behaviour_attack_broadside_left:(double)delta_t;
- (void)behaviour_attack_broadside_right:(double)delta_t;
- (void)behaviour_close_to_broadside_range:(double)delta_t;
- (void)behaviour_close_with_target:(double)delta_t;
- (void)behaviour_attack_broadside_target:(double)delta_t leftside:(BOOL)leftside;
- (void)behaviour_attack_sniper:(double)delta_t;
- (void)behaviour_fly_range_from_destination:(double)delta_t;
- (void)behaviour_face_destination:(double)delta_t;
- (void)behaviour_land_on_planet:(double)delta_t;
- (void)behaviour_formation_form_up:(double)delta_t;
- (void)behaviour_fly_to_destination:(double)delta_t;
- (void)behaviour_fly_from_destination:(double)delta_t;
- (void)behaviour_avoid_collision:(double)delta_t;
- (void)behaviour_track_as_turret:(double)delta_t;
- (void)behaviour_fly_thru_navpoints:(double)delta_t;
- (void)behaviour_scripted_ai:(double)delta_t;

- (float)reactionTime;
- (void)setReactionTime:(float)newReactionTime;
- (HPVector)calculateTargetPosition;
- (void)startTrackingCurve;
- (void)updateTrackingCurve;
- (void)calculateTrackingCurve;

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
- (void)setCloaked:(BOOL)cloak;
- (BOOL)hasAutoCloak;
- (void)setAutoCloak:(BOOL)automatic;

- (void)applyThrust:(double)delta_t;
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

// Pending escort count: number of escorts to set up "later".
- (uint8_t)pendingEscortCount;
- (void)setPendingEscortCount:(uint8_t)count;

// allow adjustment of escort numbers from shipdata.plist levels
- (uint8_t)maxEscortCount;
- (void)setMaxEscortCount:(uint8_t)newCount;

- (NSUInteger)turretCount;

- (std::optional<std::string>)cxx_name; // nullopt: none (bead oo-3rb.289.13)
- (std::optional<std::string>)cxx_shipUniqueName;
- (std::optional<std::string>)cxx_shipClassName;
- (std::optional<std::string>)displayName; // flipped with its family (bead oo-3rb.267)
- (std::optional<std::string>)cxx_scanDescription;
- (std::optional<std::string>)cxx_scanDescriptionForScripting;
- (void)cxx_setName:(const std::optional<std::string>&)inName; // PlayerEntity blocks it
- (void)cxx_setShipUniqueName:(const std::optional<std::string>&)inName;
- (void)cxx_setShipClassName:(const std::optional<std::string>&)inName;
- (void)cxx_setDisplayName:(const std::optional<std::string>&)inName;
- (void)cxx_setScanDescription:(const std::optional<std::string>&)inName;
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

- (OOAlertCondition)alertCondition; // quick calc for shaders
- (OOAlertCondition)realAlertCondition; // full calculation for scripting
- (BOOL)hasHostileTarget;
- (BOOL)isHostileTo:(Entity*)entity;

// defense target handling
- (NSUInteger)defenseTargetCount;
- (std::vector<oo::ObjCRef<ShipEntity*>>)allDefenseTargets; // the live ones (zeroed references skipped)
- (std::vector<oo::ObjCRef<ShipEntity*>>)cxx_defenseTargets; // a snapshot in the weak set's order, up to the first zeroed reference
- (void)validateDefenseTargets;
- (BOOL)addDefenseTarget:(Entity*)target;
- (BOOL)isDefenseTarget:(Entity*)target;
- (void)removeDefenseTarget:(Entity*)target;
- (void)removeAllDefenseTargets;

// collision exceptions
- (std::vector<oo::ObjCRef<ShipEntity*>>)cxx_collisionExceptions;
- (void)addCollisionException:(ShipEntity*)ship;
- (void)removeCollisionException:(ShipEntity*)ship;
- (BOOL)collisionExceptedFor:(ShipEntity*)ship;

- (GLfloat)weaponRange;
- (void)setWeaponRange:(GLfloat)value;
- (void)setWeaponDataFromType:(OOWeaponType)weapon_type;
- (float)energyRechargeRate; // final rate after energy units
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
- (OOAegisStatus)checkForAegis;
- (void)forceAegisCheck;
- (BOOL)withinStationAegis;
- (void)setLastAegisLock:(Entity<OOStellarBody>*)lastAegisLock;

- (OOSystemID)homeSystem;
- (OOSystemID)destinationSystem;
- (void)setHomeSystem:(OOSystemID)s;
- (void)setDestinationSystem:(OOSystemID)s;

- (std::optional<std::vector<oo::ObjCRef<OOCharacter*>>>)cxx_crew; // nullopt: unpiloted
- (std::vector<oo::PList>)cxx_crewForScripting; // each member's -infoForScripting
- (void)cxx_setCrew:(const std::optional<std::vector<oo::ObjCRef<OOCharacter*>>>&)crewArray;
/**
        Convenience to set the crew to a single character of the given role,
        originating in the ship's home system. Does nothing if unpiloted.
 */
- (void)cxx_setSingleCrewWithRole:(const std::string&)crewRole;

// Fuel and capacity in tenths of light-years.
- (OOFuelQuantity)fuel;
- (void)setFuel:(OOFuelQuantity)amount;
- (OOFuelQuantity)fuelCapacity;

- (GLfloat)fuelChargeRate;

- (void)setRoll:(double)amount;
- (void)setRawRoll:(double)amount; // does not multiply by PI/2
- (void)setPitch:(double)amount;
- (void)setYaw:(double)amount;
- (void)setThrust:(double)amount;
- (void)applySticks:(double)delta_t;

- (void)setThrustForDemo:(float)factor;

/*
 Sets the bounty on this ship to amount.
 Does not check to see if the ship is allowed to have a bounty, for example if it is police.
 */
- (void)setBounty:(OOCreditsQuantity)amount;
- (void)setBounty:(OOCreditsQuantity)amount withReason:(OOLegalStatusReason)reason;
- (void)setBounty:(OOCreditsQuantity)amount withReasonAsString:(const std::string&)reason; // flipped with its family (bead oo-3rb.259)
- (OOCreditsQuantity)bounty;

- (int)legalStatus;

- (BOOL)isTemplateCargoPod;
- (void)setUpCargoType:(const std::string&)cargoString;
- (void)cxx_setCommodity:(const std::string&)co_type andAmount:(OOCargoQuantity)co_amount;
- (void)cxx_setCommodityForPod:(const std::optional<std::string>&)co_type andAmount:(OOCargoQuantity)co_amount; // nullopt empties the pod, as nil did
- (std::optional<std::string>)cxx_commodityType;
- (OOCargoQuantity)commodityAmount;

- (OOCargoQuantity)maxAvailableCargoSpace;
- (void)setMaxAvailableCargoSpace:(OOCargoQuantity)newValue;
- (OOCargoQuantity)availableCargoSpace;
- (OOCargoQuantity)cargoQuantityOnBoard;
- (OOCargoType)cargoType;
- (oo::PList)cargoListForScripting; // flipped with its family (bead oo-3rb.259): an array of dictionaries
- (std::vector<oo::ObjCRef<ShipEntity*>>*)cxx_cargo; // the live cargo pods (nullptr for a nil receiver)
- (NSUInteger)cxx_cargoCount; // the number of cargo pods held
- (void)setCargo:(const std::vector<oo::ObjCRef<ShipEntity*>>&)some_cargo;
- (BOOL)cxx_addCargo:(const std::vector<oo::ObjCRef<ShipEntity*>>&)some_cargo;
- (BOOL)cxx_removeCargo:(const std::string&)commodity amount:(OOCargoQuantity)amount;
- (BOOL)showScoopMessage;

- (oo::PList)passengerListForScripting; // flipped with its family (bead oo-3rb.259): an array
- (oo::PList)parcelListForScripting; // flipped with its family (bead oo-3rb.259): an array
- (oo::PList)contractListForScripting; // flipped with its family (bead oo-3rb.259): an array
- (std::vector<oo::ObjCRef<OOEquipmentType*>>)cxx_equipmentListForScripting;
- (OOWeaponType)weaponTypeIDForFacing:(OOWeaponFacing)facing strict:(BOOL)strict;
- (OOEquipmentType*)weaponTypeForFacing:(OOWeaponFacing)facing strict:(BOOL)strict;
- (std::vector<oo::ObjCRef<OOEquipmentType*>>)missilesList; // flipped with its family (bead oo-3rb.259)

- (OOCargoFlag)cargoFlag;
- (void)setCargoFlag:(OOCargoFlag)flag;

- (void)setSpeed:(double)amount;
- (double)desiredSpeed;
- (void)setDesiredSpeed:(double)amount;
- (double)desiredRange;
- (void)setDesiredRange:(double)amount;

- (double)cruiseSpeed;

- (Vector)thrustVector;
- (void)setTotalVelocity:(Vector)vel; // Set velocity to vel - thrustVector, effectively setting the instanteneous velocity to vel.

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
- (GLfloat)speedFactor;

- (GLfloat)temperature;
- (void)setTemperature:(GLfloat)value;
- (GLfloat)heatInsulation;
- (void)setHeatInsulation:(GLfloat)value;

- (float)randomEjectaTemperature;
- (float)randomEjectaTemperatureWithMaxFactor:(float)factor;

// the percentage of damage taken (100 is destroyed, 0 is fine)
- (int)damage;

- (void)dealEnergyDamage:(GLfloat)baseDamage atRange:(GLfloat)range withBias:(GLfloat)velocityBias;
- (void)dealEnergyDamageWithinDesiredRange;
- (void)dealMomentumWithinDesiredRange:(double)amount;

// Dispatch shipTakingDamage() event.
- (void)noteTakingDamage:(double)amount from:(Entity*)entity type:(OOShipDamageType)type;
// Dispatch shipDied() and possibly shipKilledOther() events. This is only for use by getDestroyedBy:damageType:, but needs to be visible to PlayerEntity's version.
- (void)noteKilledBy:(Entity*)whom damageType:(OOShipDamageType)type;

- (void)getDestroyedBy:(Entity*)whom damageType:(OOShipDamageType)type;
- (void)becomeExplosion;
- (void)becomeLargeExplosion:(double)factor;
- (void)becomeEnergyBlast;
- (void)broadcastEnergyBlastImminent;
- (void)setIsWreckage:(BOOL)isw;
- (BOOL)showDamage;

- (Vector)positionOffsetForAlignment:(const std::string&)align;
Vector cxx_positionOffsetForShipInRotationToAlignment(ShipEntity* ship, Quaternion q, const std::string& align);

- (void)collectBountyFor:(ShipEntity*)other;

- (BoundingBox)findSubentityBoundingBox;

- (Triangle)absoluteIJKForSubentity;

- (GLfloat)weaponRecoveryTime;
- (GLfloat)laserHeatLevel;
- (GLfloat)laserHeatLevelAft;
- (GLfloat)laserHeatLevelForward;
- (GLfloat)laserHeatLevelPort;
- (GLfloat)laserHeatLevelStarboard;
- (GLfloat)hullHeatLevel;
- (GLfloat)entityPersonality;
- (GLint)entityPersonalityInt;
- (void)setEntityPersonalityInt:(uint16_t)value;

- (void)setSuppressExplosion:(BOOL)suppress;

- (void)resetExhaustPlumes;

- (void)removeExhaust:(OOExhaustPlumeEntity*)exhaust;
- (void)removeFlasher:(OOFlasherEntity*)flasher;

/*-----------------------------------------

 AI piloting methods

 -----------------------------------------*/

- (void)checkScanner;
- (void)checkScannerIgnoringUnpowered;
- (ShipEntity**)scannedShips;
- (int)numberOfScannedShips;

- (Entity*)foundTarget;
- (Entity*)primaryAggressor;
- (Entity*)lastEscortTarget;
- (Entity*)thankedShip;
- (Entity*)rememberedShip;
- (Entity*)proximityAlert;
- (void)setFoundTarget:(Entity*)targetEntity;
- (void)setPrimaryAggressor:(Entity*)targetEntity;
- (void)setLastEscortTarget:(Entity*)targetEntity;
- (void)setThankedShip:(Entity*)targetEntity;
- (void)setRememberedShip:(Entity*)targetEntity;
- (void)setProximityAlert:(ShipEntity*)targetEntity;
- (void)setTargetStation:(Entity*)targetEntity;
- (BOOL)isValidTarget:(Entity*)target;
- (void)addTarget:(Entity*)targetEntity;
- (void)removeTarget:(Entity*)targetEntity;
- (BOOL)canStillTrackPrimaryTarget;
- (id)primaryTarget;
- (id)primaryTargetWithoutValidityCheck;
- (StationEntity*)targetStation;

- (BOOL)isFriendlyTo:(ShipEntity*)otherShip;

- (ShipEntity*)shipHitByLaser;

- (void)noteLostTarget;
- (void)noteLostTargetAndGoIdle;
- (void)noteTargetDestroyed:(ShipEntity*)target;

- (OOBehaviour)behaviour;
- (void)setBehaviour:(OOBehaviour)cond;

- (void)trackOntoTarget:(double)delta_t withDForward:(GLfloat)dp;

- (double)ballTrackLeadingTarget:(double)delta_t atTarget:(Entity*)target;

- (GLfloat)rollToMatchUp:(Vector)up_vec rotating:(GLfloat)match_roll;

- (GLfloat)rangeToDestination;
- (double)trackDestination:(double)delta_t retreat:(BOOL)retreat;

- (void)setCoordinate:(HPVector)coord;
- (HPVector)coordinates;
- (HPVector)destination;
- (HPVector)distance_six:(GLfloat)dist;
- (HPVector)distance_twelve:(GLfloat)dist withOffset:(GLfloat)offset;

- (void)setEvasiveJink:(GLfloat)z;
- (void)evasiveAction:(double)delta_t;
- (double)trackPrimaryTarget:(double)delta_t retreat:(BOOL)retreat;
- (double)trackSideTarget:(double)delta_t leftside:(BOOL)leftside;
- (double)missileTrackPrimaryTarget:(double)delta_t;

// return 0.0 if there is no primary target
- (double)rangeToPrimaryTarget;
- (double)approachAspectToPrimaryTarget;
- (double)rangeToSecondaryTarget:(Entity*)target;
- (BOOL)hasProximityAlertIgnoringTarget:(BOOL)ignore_target;
- (GLfloat)currentAimTolerance;
/* This method returns a value between 0.0f and 1.0f, depending on how directly our view point
   faces the sun and is used for generating the "staring at the sun" glare effect. 0.0f means that
   we are not facing the sun, 1.0f means that we are looking directly at it. The cosine of the
   threshold angle between view point and sun, below which we consider the ship as looking
   at the sun, is passed as parameter to the method.
*/
- (GLfloat)lookingAtSunWithThresholdAngleCos:(GLfloat)thresholdAngleCos;

- (BOOL)onTarget:(OOWeaponFacing)direction withWeapon:(OOWeaponType)weapon;

- (OOTimeDelta)shotTime;
- (void)resetShotTime;

- (BOOL)fireMainWeapon:(double)range;
- (BOOL)fireAftWeapon:(double)range;
- (BOOL)firePortWeapon:(double)range;
- (BOOL)fireStarboardWeapon:(double)range;
- (BOOL)fireTurretCannon:(double)range;
- (void)setLaserColor:(OOColor*)color;
- (void)setExhaustEmissiveColor:(OOColor*)color;
- (OOColor*)laserColor;
- (OOColor*)exhaustEmissiveColor;
- (BOOL)fireSubentityLaserShot:(double)range;
- (BOOL)fireDirectLaserShot:(double)range;
- (BOOL)fireDirectLaserDefensiveShot;
- (BOOL)fireDirectLaserShotAt:(Entity*)my_target;
- (std::vector<Vector>)cxx_laserPortOffset:(OOWeaponFacing)direction;
- (BOOL)cxx_fireLaserShotInDirection:(OOWeaponFacing)direction weaponIdentifier:(const std::string&)weaponIdentifier;
- (void)adjustMissedShots:(int)delta;
- (int)missedShots;
- (void)considerFiringMissile:(double)delta_t;
- (Vector)missileLaunchPosition;
- (ShipEntity*)fireMissile;
- (ShipEntity*)cxx_fireMissileWithIdentifier:(const std::optional<std::string>&)identifier andTarget:(Entity*)target; // nullopt: a random missile from the list
- (BOOL)isMissileFlagSet;
- (void)setIsMissileFlag:(BOOL)newValue;
- (OOTimeDelta)missileLoadTime;
- (void)setMissileLoadTime:(OOTimeDelta)newMissileLoadTime;
- (void)noticeECM;
- (BOOL)fireECM;
- (BOOL)cascadeIfAppropriateWithDamageAmount:(double)amount cascadeOwner:(Entity*)owner;
- (BOOL)activateCloakingDevice;
- (void)deactivateCloakingDevice;
- (BOOL)launchCascadeMine;
- (ShipEntity*)launchEscapeCapsule;
- (void)dumpCargo; // shared selector (proposed ADR-0043), called by name (ADR-0055 item 5)
- (ShipEntity*)cxx_dumpCargoItem:(const std::optional<std::string>&)preferred; // nullopt: the first pod
- (OOCargoType)dumpItem:(ShipEntity*)jetto;

- (void)manageCollisions;
- (BOOL)collideWithShip:(ShipEntity*)other;
- (void)adjustVelocity:(Vector)xVel;
- (void)addImpactMoment:(Vector)moment fraction:(GLfloat)howmuch;
- (BOOL)canScoop:(ShipEntity*)other;
- (void)getTractoredBy:(ShipEntity*)other;
- (void)scoopIn:(ShipEntity*)other;
- (void)scoopUp:(ShipEntity*)other;
- (void)scoopUpProcess:(ShipEntity*)other processEvents:(BOOL)proc_events processMessages:(BOOL)proc_messages;

- (BOOL)abandonShip;

- (void)takeScrapeDamage:(double)amount from:(Entity*)ent;
- (void)takeHeatDamage:(double)amount;

- (void)enterDock:(StationEntity*)station;
- (void)leaveDock:(StationEntity*)station;

- (void)enterWormhole:(WormholeEntity*)w_hole;
- (void)enterWormhole:(WormholeEntity*)w_hole replacing:(BOOL)replacing;
- (void)enterWitchspace;
- (void)leaveWitchspace;
- (BOOL)witchspaceLeavingEffects;

/*
 Mark this ship as an offender, this is different to setBounty as some ships such as police
 are not markable.  The final bounty may not be equal to existing bounty plus offence_value.
 */
- (void)markAsOffender:(int)offence_value;
- (void)markAsOffender:(int)offence_value withReason:(OOLegalStatusReason)reason;

- (void)switchLightsOn;
- (void)switchLightsOff;
- (BOOL)lightsActive;

- (void)setDestination:(HPVector)dest;
- (void)setEscortDestination:(HPVector)dest;

- (BOOL)canAcceptEscort:(ShipEntity*)potentialEscort;
- (BOOL)acceptAsEscort:(ShipEntity*)other_ship;
- (void)deployEscorts;
- (void)dockEscorts;

- (void)setTargetToNearestFriendlyStation;
- (void)setTargetToNearestStation;
- (void)setTargetToSystemStation;

- (void)landOnPlanet:(OOPlanetEntity*)planet;

- (void)abortDocking;
- (oo::PList)cxx_dockingInstructions; // null: none

- (void)broadcastThargoidDestroyed;

- (void)broadcastHitByLaserFrom:(ShipEntity*)aggressor_ship;

// Sun glare filter - 0 for no filter, 1 for full filter
- (GLfloat)sunGlareFilter;
- (void)setSunGlareFilter:(GLfloat)newValue;

// Unpiloted ships cannot broadcast messages, unless the unpilotedOverride is set to YES.
- (void)cxx_sendExpandedMessage:(const std::string&)message_text toShip:(ShipEntity*)other_ship;
- (void)cxx_sendMessage:(const std::string&)message_text toShip:(ShipEntity*)other_ship withUnpilotedOverride:(BOOL)unpilotedOverride;
- (void)broadcastAIMessage:(const std::string&)ai_message;
- (void)broadcastMessage:(const std::string&)message_text withUnpilotedOverride:(BOOL)unpilotedOverride;
- (void)setCommsMessageColor;
- (void)receiveCommsMessage:(const std::string&)message_text from:(ShipEntity*)other; // flipped with its family (bead oo-3rb.259)
- (void)cxx_commsMessage:(const std::string&)valueString withUnpilotedOverride:(BOOL)unpilotedOverride;

- (BOOL)markedForFines;
- (BOOL)markForFines;

- (BOOL)isMining;

- (void)spawn:(const std::string&)roles_number; // shared selector (proposed ADR-0043), called by name (ADR-0055 item 5)

- (int)checkShipsInVicinityForWitchJumpExit;

- (BOOL)trackCloseContacts;
- (void)setTrackCloseContacts:(BOOL)value;

/*
 * Changes a ship to a hulk, for example when the pilot ejects.
 * Aso unsets hulkiness for example when a new pilot gets in.
 */
- (void)setHulk:(BOOL)isNowHulk;
- (BOOL)isHulk;
#if OO_SALVAGE_SUPPORT
- (void)claimAsSalvage;
- (void)sendCoordinatesToPilot;
- (void)pilotArrived;
#endif

- (OOJSScript*)script;
- (oo::PList)scriptInfo; // flipped with its family (bead oo-3rb.284): empty dict when there is none
- (void)overrideScriptInfo:(const oo::PList&)override; // Add items from override (a dictionary, or null for none) to scriptInfo, replacing in case of duplicates. Used for subentities.

- (BOOL)scriptedMisjump;
- (void)setScriptedMisjump:(BOOL)newValue;
- (GLfloat)scriptedMisjumpRange;
- (void)setScriptedMisjumpRange:(GLfloat)newValue;

- (Entity*)entityForShaderProperties;

// Demo ship
- (void)setDemoShip:(OOScalar)demoRate;
- (BOOL)isDemoShip;
- (void)setDemoStartTime:(OOTimeAbsolute)time;

/*	*** Script events.
        For NPC ships, these call doEvent: on the ship script.
        For the player, they do that and also call doWorldScriptEvent:.
*/
- (void)doScriptEvent:(OOJSPropID)message;
- (void)doScriptEvent:(OOJSPropID)message withArgument:(id)argument;
- (void)doScriptEvent:(OOJSPropID)message withArgument:(id)argument1 andArgument:(id)argument2;
/*	Plist data as event arguments (ADR-0055 item 4): each converted by OOJSValueFromPList, so a
        string, number or collection gives the JS value the boxed Foundation object gave, and an entity
        is passed as oo::PListObject(entity). The id forms above stay for OOObject arguments.
*/
- (void)cxx_doScriptEvent:(OOJSPropID)message withPListArguments:(const std::vector<oo::PList>&)arguments;
// argv is borrowed: the caller remains responsible for freeing the values.
- (void)doScriptEvent:(OOJSPropID)message withArguments:(JSValue*)argv count:(int)argc;
- (void)doScriptEvent:(OOJSPropID)message inContext:(JSContext*)context withArguments:(JSValue*)argv count:(int)argc;

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

- (void)cxx_reactToAIMessage:(const std::string&)message context:(const std::optional<std::string>&)debugContext; // Immediate message
- (void)sendAIMessage:(const std::string&)message; // Queued message.
- (void)cxx_doScriptEvent:(OOJSPropID)scriptEvent andReactToAIMessage:(const std::string&)aiMessage;
- (void)cxx_doScriptEvent:(OOJSPropID)scriptEvent withArgument:(id)argument andReactToAIMessage:(const std::string&)aiMessage;

@end

#ifndef NDEBUG
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
