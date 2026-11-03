/*

PlayerEntity+FoundationBridge.h

TRANSITIONAL (proposed ADR-0043, "Transitional bridges"; bead oo-3rb.164, a chunk of oo-3rb.75).
PlayerEntity's Foundation-typed API as it was before its sweep, with the same selector names and
types, forwarding to the cxx_ API in PlayerEntity.h. It exists so that the callers (GuiDisplayGen
for -markedDestinations) compile unchanged; each caller moves to the cxx_ API in its own sweep
bead. When `git grep` finds no caller of anything declared here, the bridge bead deletes this
file, PlayerEntity+FoundationBridge.mm, its line in Core/Entities/meson.build and the #import at
the end of PlayerEntity.h. Never add to it outside the PlayerEntity chunks; never call it from
migrated code. oo-qps (the removal of gnustep-base) cannot compile while it exists.

Registry: src/oofnd/README.md, "Transitional bridges".

Copyright (C) 2004-2013 Giles C Williams and contributors (PlayerEntity.h)

*/

// Imported only from the end of PlayerEntity.h (which declares everything used here); never
// import it directly, and never import PlayerEntity.h from it (a cycle).
#ifndef PLAYERENTITY_FOUNDATIONBRIDGE_H
#define PLAYERENTITY_FOUNDATIONBRIDGE_H

@interface PlayerEntity (FoundationBridge)

// oo-3rb.164: marked destinations
- (NSDictionary*)markedDestinations; // -> -cxx_markedDestinations

// oo-3rb.243: HUD switching, custom dials and multi-function displays
- (BOOL)switchHudTo:(NSString*)hudFileName; // -> -cxx_switchHudTo: (nil: NO)
- (float)dialCustomFloat:(NSString*)dialKey; // -> -cxx_dialCustomFloat:
- (NSString*)dialCustomString:(NSString*)dialKey; // -> -cxx_dialCustomString:
- (OOColor*)dialCustomColor:(NSString*)dialKey; // -> -cxx_dialCustomColor:
- (void)setDialCustom:(id)value forKey:(NSString*)key; // -> -cxx_setDialCustom:forKey:
- (NSArray*)multiFunctionDisplayList; // -> -cxx_multiFunctionDisplayList (a snapshot, [OONull null] for inactive)
- (NSString*)multiFunctionText:(NSUInteger)index; // -> -cxx_multiFunctionText:
- (void)setMultiFunctionText:(NSString*)text forKey:(NSString*)key; // -> -cxx_setMultiFunctionText:forKey:
- (BOOL)setMultiFunctionDisplay:(NSUInteger)index toKey:(NSString*)key; // -> -cxx_setMultiFunctionDisplay:toKey:
- (NSString*)dial_clock; // -> -cxx_dial_clock
- (NSString*)dial_clock_adjusted; // -> -cxx_dial_clock_adjusted
- (NSString*)dial_fpsinfo; // -> -cxx_dial_fpsinfo
- (NSString*)dial_objinfo; // -> -cxx_dial_objinfo
- (NSString*)compassTargetLabel; // -> -cxx_compassTargetLabel
- (NSString*)dialTargetName; // -> -cxx_dialTargetName

// oo-3rb.244: commander identity, fast equipment, comm log, target memory, wormholes and last shot
- (NSString*)commanderName; // -> -cxx_commanderName
- (void)setCommanderName:(NSString*)value; // -> -cxx_setCommanderName:
- (NSString*)lastsaveName; // -> -cxx_lastsaveName
- (void)setLastsaveName:(NSString*)value; // -> -cxx_setLastsaveName:
- (NSString*)jumpCause; // -> -cxx_jumpCause
- (void)setJumpCause:(NSString*)value; // -> -cxx_setJumpCause:
- (NSArray*)currentLaserOffset; // -> -cxx_currentLaserOffset
- (NSString*)fastEquipmentA; // -> -cxx_fastEquipmentA
- (NSString*)fastEquipmentB; // -> -cxx_fastEquipmentB
- (void)setFastEquipmentA:(NSString*)eqKey; // -> -cxx_setFastEquipmentA:
- (void)setFastEquipmentB:(NSString*)eqKey; // -> -cxx_setFastEquipmentB:
- (NSMutableArray*)commLog; // -> -cxx_commLog (a snapshot: read-only callers)
- (NSMutableArray*)targetMemory; // -> -cxx_targetMemory (a snapshot, [OONull null] for empty slots)
- (NSArray*)scannedWormholes; // -> -cxx_scannedWormholes
- (void)setLastShot:(NSArray*)shot; // -> -cxx_setLastShot:

// oo-3rb.245: custom views, screen background descriptors and script-defined keys
- (NSDictionary*)keyConfig; // -> -cxx_keyConfig
- (NSString*)customViewDescription; // -> -cxx_customViewDescription
- (void)setCustomViewDataFromDictionary:(NSDictionary*)viewDict withScaling:(BOOL)withScaling; // -> -cxx_setCustomViewDataFromDictionary:withScaling:
- (NSDictionary*)missionOverlayDescriptor; // -> -cxx_missionOverlayDescriptor
- (NSDictionary*)missionOverlayDescriptorOrDefault; // -> -cxx_missionOverlayDescriptorOrDefault
- (void)setMissionOverlayDescriptor:(NSDictionary*)descriptor; // -> -cxx_setMissionOverlayDescriptor:
- (NSDictionary*)missionBackgroundDescriptor; // -> -cxx_missionBackgroundDescriptor
- (NSDictionary*)missionBackgroundDescriptorOrDefault; // -> -cxx_missionBackgroundDescriptorOrDefault
- (void)setMissionBackgroundDescriptor:(NSDictionary*)descriptor; // -> -cxx_setMissionBackgroundDescriptor:
- (void)setMissionBackgroundSpecial:(NSString*)special; // -> -cxx_setMissionBackgroundSpecial:
- (void)setExtraMissionKeys:(NSDictionary*)keys; // -> -cxx_setExtraMissionKeys:
- (void)clearExtraGuiScreenKeys:(OOGUIScreenID)gui key:(NSString*)key; // -> -cxx_clearExtraGuiScreenKeys:key:
- (NSDictionary*)equipScreenBackgroundDescriptor; // -> -cxx_equipScreenBackgroundDescriptor
- (void)setEquipScreenBackgroundDescriptor:(NSDictionary*)descriptor; // -> -cxx_setEquipScreenBackgroundDescriptor:

// oo-3rb.246: system data, chart, game options, load/save and equip-ship screens
- (void)setGuiToEquipShipScreen:(int)skip selectingFacingFor:(NSString*)eqKeyForSelectFacing; // -> -cxx_setGuiToEquipShipScreen:selectingFacingFor:
- (void)showInformationForSelectedUpgradeWithFormatString:(NSString*)extraString; // -> -cxx_showInformationForSelectedUpgradeWithFormatString:
- (NSString*)screenModeStringForWidth:(unsigned)inWidth height:(unsigned)inHeight refreshRate:(float)inRate; // -> -cxx_screenModeStringForWidth:height:refreshRate:

// oo-3rb.247: market screens, commodity trading and cargo quantities
- (OOCargoQuantity)cargoQuantityForType:(OOCommodityType)type; // -> -cxx_cargoQuantityForType:
- (OOCargoQuantity)setCargoQuantityForType:(OOCommodityType)type amount:(OOCargoQuantity)amount; // -> -cxx_setCargoQuantityForType:amount:
- (NSArray*)applyMarketFilter:(NSArray*)goods onMarket:(OOCommodityMarket*)market; // -> -cxx_applyMarketFilter:onMarket:
- (NSArray*)applyMarketSorter:(NSArray*)goods onMarket:(OOCommodityMarket*)market; // -> -cxx_applyMarketSorter:onMarket:
- (BOOL)tryBuyingCommodity:(OOCommodityType)type all:(BOOL)all; // -> -cxx_tryBuyingCommodity:all:
- (BOOL)trySellingCommodity:(OOCommodityType)type all:(BOOL)all; // -> -cxx_trySellingCommodity:all:

// oo-3rb.248: missiles, pylons, damage, bounty, equipment add/remove and comms
- (BOOL)assignToActivePylon:(NSString*)identifierKey; // -> -cxx_assignToActivePylon:
- (BOOL)mountMissileWithRole:(NSString*)role; // -> -cxx_mountMissileWithRole:
- (BOOL)endScenario:(NSString*)key; // -> -cxx_endScenario: (nil: NO)

// oo-3rb.249: flight, cargo pods, docking, witchspace, targeting, ship model, trumbles and state dump
- (void)showShipModelWithKey:(NSString*)shipKey shipData:(NSDictionary*)shipData personality:(uint16_t)personality factorX:(GLfloat)factorX factorY:(GLfloat)factorY factorZ:(GLfloat)factorZ inContext:(NSString*)context; // -> -cxx_showShipModelWithKey:... (nil key: nothing)

// oo-3rb.250: interfaces, start and intro screens, buying equipment and weapon mounts
- (OOCreditsQuantity)adjustPriceByScriptForEqKey:(NSString*)eqKey withCurrent:(OOCreditsQuantity)price; // -> -cxx_adjustPriceByScriptForEqKey:withCurrent: (nil: price)
- (BOOL)setWeaponMount:(OOWeaponFacing)facing toWeapon:(NSString*)eqKey inContext:(NSString*)context; // -> -cxx_setWeaponMount:toWeapon:inContext: (nil key: "")

// oo-3rb.251: roles, system memory and mission destinations
- (NSMutableArray*)roleWeights; // -> -cxx_roleWeights (a snapshot)
- (void)addRoleToPlayer:(NSString*)role; // -> -cxx_addRoleToPlayer:
- (void)addRoleToPlayer:(NSString*)role inSlot:(NSUInteger)slot; // -> -cxx_addRoleToPlayer:inSlot:
- (void)addMissionDestinationMarker:(NSDictionary*)marker; // -> -cxx_addMissionDestinationMarker:
- (BOOL)removeMissionDestinationMarker:(NSDictionary*)marker; // -> -cxx_removeMissionDestinationMarker:
- (NSMutableDictionary*)getMissionDestinations; // -> -cxx_getMissionDestinations (a snapshot)

// oo-3rb.252: status screen and manifest lists
- (NSArray*)equipmentList; // -> -cxx_equipmentList
- (NSArray*)cargoList; // -> -cxx_cargoList

// oo-3rb.255: mission strings, special cargo and equipment scripts
- (NSString*)specialCargo; // -> -cxx_specialCargo
- (BOOL)setPrimedEquipment:(NSString*)eqKey showMessage:(BOOL)showMsg; // -> -cxx_setPrimedEquipment:showMessage: (nil: NO, unchanged)
- (NSString*)primedEquipmentName:(NSInteger)offset; // -> -cxx_primedEquipmentName:
- (NSString*)currentPrimedEquipment; // -> -cxx_currentPrimedEquipment

@end

#endif // PLAYERENTITY_FOUNDATIONBRIDGE_H
