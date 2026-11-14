/*

ShipEntity+FoundationBridge.h

TRANSITIONAL (proposed ADR-0043, "Transitional bridges"; chunk beads oo-3rb.232-.242 of oo-3rb.73).
ShipEntity's Foundation-typed API as it was before its sweep, with the same selector names and
types, forwarding to the cxx_ API in ShipEntity.h. It exists so that ShipEntity's callers compile
unchanged; each caller moves to the cxx_ API in its own sweep bead. When `git grep` finds no caller
of anything declared here, the bridge bead deletes this file, ShipEntity+FoundationBridge.mm, its
line in Entities/meson.build and the #import at the end of ShipEntity.h. Never add to it outside the
ShipEntity.mm chunk beads; never call it from migrated code. oo-qps (the removal of gnustep-base)
cannot compile while it exists.

Registry: src/oofnd/README.md, "Transitional bridges".

Copyright (C) 2004-2013 Giles C Williams and contributors (ShipEntity.h)

*/

// Imported only from the end of ShipEntity.h (which declares everything used here); never import
// it directly, and never import ShipEntity.h from it (a cycle).
#ifndef SHIPENTITY_FOUNDATIONBRIDGE_H
#define SHIPENTITY_FOUNDATIONBRIDGE_H

@interface ShipEntity (OOFoundationBridge)

// oo-3rb.232: subentities
- (NSEnumerator*)shipSubEntityEnumerator; // -> -cxx_shipSubEntities
- (NSEnumerator*)exhaustEnumerator; // -> -cxx_exhausts
- (NSString*)serializeShipSubEntities; // -> -cxx_serializeShipSubEntities
- (void)deserializeShipSubEntitiesFrom:(NSString*)string; // -> -cxx_deserializeShipSubEntitiesFrom:
- (BOOL)setUpOneStandardSubentity:(NSDictionary*)subentDict asTurret:(BOOL)asTurret; // -> -cxx_setUpOneStandardSubentity:asTurret:

// oo-3rb.233: equipment
- (NSUInteger)countEquipmentItem:(NSString*)eqkey; // -> -cxx_countEquipmentItem:
- (NSString*)equipmentItemProviding:(NSString*)equipmentType; // -> -cxx_equipmentItemProviding:
- (BOOL)hasEquipmentItemProviding:(NSString*)equipmentType; // -> -cxx_hasEquipmentItemProviding:
- (BOOL)equipmentValidToAdd:(NSString*)equipmentKey inContext:(NSString*)context; // -> -cxx_equipmentValidToAdd:inContext:
- (BOOL)equipmentValidToAdd:(NSString*)equipmentKey whileLoading:(BOOL)loading inContext:(NSString*)context; // -> -cxx_equipmentValidToAdd:whileLoading:inContext:
- (NSEnumerator*)equipmentEnumerator; // -> -cxx_equipmentKeys
- (BOOL)hasOneEquipmentItem:(NSString*)itemKey includeWeapons:(BOOL)includeMissiles whileLoading:(BOOL)loading; // -> -cxx_hasOneEquipmentItem:includeWeapons:whileLoading:
- (BOOL)hasOneEquipmentItem:(NSString*)itemKey includeMissiles:(BOOL)includeMissiles whileLoading:(BOOL)loading; // -> -cxx_hasOneEquipmentItem:includeMissiles:whileLoading:
- (NSArray*)equipmentListForScripting; // -> -cxx_equipmentListForScripting

// oo-3rb.234: missiles and weapon mounts
- (NSArray*)aftWeaponOffset; // -> -cxx_aftWeaponOffset
- (NSArray*)forwardWeaponOffset; // -> -cxx_forwardWeaponOffset
- (NSArray*)portWeaponOffset; // -> -cxx_portWeaponOffset
- (NSArray*)starboardWeaponOffset; // -> -cxx_starboardWeaponOffset
- (NSArray*)laserPortOffset:(OOWeaponFacing)direction; // -> -cxx_laserPortOffset:
- (BOOL)fireLaserShotInDirection:(OOWeaponFacing)direction weaponIdentifier:(NSString*)weaponIdentifier; // -> -cxx_fireLaserShotInDirection:weaponIdentifier:
- (ShipEntity*)fireMissileWithIdentifier:(NSString*)identifier andTarget:(Entity*)target; // -> -cxx_fireMissileWithIdentifier:andTarget:

// oo-3rb.235: cargo API and commodities
- (void)setCommodity:(OOCommodityType)co_type andAmount:(OOCargoQuantity)co_amount; // -> -cxx_setCommodity:andAmount:
- (void)setCommodityForPod:(OOCommodityType)co_type andAmount:(OOCargoQuantity)co_amount; // -> -cxx_setCommodityForPod:andAmount:
- (OOCommodityType)commodityType; // -> -cxx_commodityType
- (BOOL)addCargo:(NSArray*)some_cargo; // -> -cxx_addCargo:
- (BOOL)removeCargo:(OOCommodityType)commodity amount:(OOCargoQuantity)amount; // -> -cxx_removeCargo:amount:
- (ShipEntity*)dumpCargoItem:(OOCommodityType)preferred; // -> -cxx_dumpCargoItem:

// oo-3rb.237: crew, escorts, groups and escape pods
- (NSEnumerator*)escortEnumerator; // -> -cxx_escorts
- (NSArray*)crew; // -> -cxx_crew
- (NSArray*)crewForScripting; // -> -cxx_crewForScripting
- (void)setCrew:(NSArray*)crewArray; // -> -cxx_setCrew:
- (void)setSingleCrewWithRole:(NSString*)crewRole; // -> -cxx_setSingleCrewWithRole:

// oo-3rb.238: combat, collisions, defense targets, explosions, docking instructions
- (NSEnumerator*)defenseTargetEnumerator; // -> -cxx_defenseTargets
- (NSArray*)collisionExceptions; // -> -cxx_collisionExceptions
- (NSDictionary*)dockingInstructions; // -> -cxx_dockingInstructions

// oo-3rb.239: messages, comms and AI dispatch
- (void)sendExpandedMessage:(NSString*)message_text toShip:(ShipEntity*)other_ship; // -> -cxx_sendExpandedMessage:toShip:
- (void)sendMessage:(NSString*)message_text toShip:(ShipEntity*)other_ship withUnpilotedOverride:(BOOL)unpilotedOverride; // -> -cxx_sendMessage:toShip:withUnpilotedOverride:
- (void)commsMessage:(NSString*)valueString withUnpilotedOverride:(BOOL)unpilotedOverride; // -> -cxx_commsMessage:withUnpilotedOverride:
- (void)doScriptEvent:(OOJSPropID)message withArguments:(NSArray*)arguments; // -> -cxx_doScriptEvent:withArguments:
- (void)reactToAIMessage:(NSString*)message context:(NSString*)debugContext; // -> -cxx_reactToAIMessage:context:
- (void)doScriptEvent:(OOJSPropID)scriptEvent andReactToAIMessage:(NSString*)aiMessage; // -> -cxx_doScriptEvent:andReactToAIMessage:
- (void)doScriptEvent:(OOJSPropID)scriptEvent withArgument:(id)argument andReactToAIMessage:(NSString*)aiMessage; // -> -cxx_doScriptEvent:withArgument:andReactToAIMessage:

// oo-3rb.241: setup
- (BOOL)setUpFromDictionary:(NSDictionary*)shipDict; // -> -cxx_setUpFromDictionary:
- (NSDictionary*)shipInfoDictionary; // -> -cxx_shipInfoDictionary

// oo-3rb.242: script
- (void)setShipScript:(NSString*)script_name; // -> -cxx_setShipScript:

// oo-3rb.240: identity: names, roles, ship key, descriptions
- (NSString*)shipDataKey; // -> -cxx_shipDataKey
- (NSString*)shipDataKeyAutoRole; // -> -cxx_shipDataKeyAutoRole
- (void)setShipDataKey:(NSString*)key; // -> -cxx_setShipDataKey:
- (NSString*)shipUniqueName; // -> -cxx_shipUniqueName
- (NSString*)shipClassName; // -> -cxx_shipClassName
- (NSString*)scanDescription; // -> -cxx_scanDescription
- (NSString*)scanDescriptionForScripting; // -> -cxx_scanDescriptionForScripting
- (void)setShipUniqueName:(NSString*)inName; // -> -cxx_setShipUniqueName:
- (void)setShipClassName:(NSString*)inName; // -> -cxx_setShipClassName:
- (void)setDisplayName:(NSString*)inName; // -> -cxx_setDisplayName:
- (void)setScanDescription:(NSString*)inName; // -> -cxx_setScanDescription:
- (void)addRole:(NSString*)role withProbability:(float)probability; // -> -cxx_addRole:withProbability:
- (void)removeRole:(NSString*)role; // -> -cxx_removeRole:
- (NSString*)primaryRole; // -> -cxx_primaryRole
- (BOOL)hasPrimaryRole:(NSString*)role; // -> -cxx_hasPrimaryRole:

@end

// oo-3rb.234
Vector positionOffsetForShipInRotationToAlignment(ShipEntity* ship, Quaternion q, NSString* align); // -> cxx_positionOffsetForShipInRotationToAlignment

// oo-3rb.242: the OOConstToString functions ShipEntity.h declared, moved here verbatim with their
// linkage (bead oo-nts1's rule); defined in OOConstToString+FoundationBridge.mm, forwarding to the
// cxx_ forms that ShipEntity.h still declares.
// Defined in OOConstToString.m
NSString* OOStringFromBehaviour(OOBehaviour behaviour) CONST_FUNC;

// Weapon strings prefixed with EQ_, used in shipyard.plist.
NSString* OOEquipmentIdentifierFromWeaponType(OOWeaponType weapon) CONST_FUNC;
#ifdef __cplusplus
extern "C" {
#endif
OOWeaponType OOWeaponTypeFromEquipmentIdentifierSloppy(NSString* string) PURE_FUNC; // Uses suffix match for backwards compatibility.
#ifdef __cplusplus
}
#endif
OOWeaponType OOWeaponTypeFromEquipmentIdentifierStrict(NSString* string) PURE_FUNC;
OOWeaponType OOWeaponTypeFromEquipmentIdentifierLegacy(NSString* string);

NSString* OOStringFromWeaponType(OOWeaponType weapon) CONST_FUNC;
OOWeaponType OOWeaponTypeFromString(NSString* string) PURE_FUNC;

NSString* OODisplayStringFromAlertCondition(OOAlertCondition alertCondition);

NSString* OOStringFromShipDamageType(OOShipDamageType type) CONST_FUNC;

#endif // SHIPENTITY_FOUNDATIONBRIDGE_H
