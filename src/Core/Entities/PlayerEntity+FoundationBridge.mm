/*

PlayerEntity+FoundationBridge.mm

TRANSITIONAL: see PlayerEntity+FoundationBridge.h. Each method forwards to its cxx_ counterpart
and converts the result exactly as the old method produced it.

*/

#import "OOFoundationBridge.h"
#import "OOJavaScriptEngine.h" // OONull
#import "OOVector.h" // OONativeVector
#import "PlayerEntity.h" // declares the bridge category at its end

@implementation PlayerEntity (FoundationBridge)

// oo-3rb.164: a dictionary of arrays keyed by +numberWithInt: of the system ID, each array's
// markers in the order they were added (as -prepareMarkedDestination:: built it).
- (NSDictionary*)markedDestinations
{
    NSMutableDictionary* destinations = [NSMutableDictionary dictionaryWithCapacity:256];
    const std::optional<std::map<int, std::vector<oo::PList>>> markers = [self cxx_markedDestinations];
    if (markers.has_value()) {
        for (const auto& [system, list] : *markers) {
            NSMutableArray* array = [NSMutableArray arrayWithCapacity:list.size()];
            for (const oo::PList& marker : list) {
                id object = oo::ObjectFromPList(marker);
                if (object != nil)
                    [array addObject:object];
            }
            [destinations setObject:array forKey:[NSNumber numberWithInt:system]];
        }
    }
    return destinations;
}

// oo-3rb.243: HUD switching, custom dials and multi-function displays
- (BOOL)switchHudTo:(NSString*)hudFileName
{
    if (hudFileName == nil)
        return NO;
    return [self cxx_switchHudTo:oo::StdString(hudFileName)];
}

- (float)dialCustomFloat:(NSString*)dialKey
{
    return [self cxx_dialCustomFloat:oo::StdString(dialKey)];
}

- (NSString*)dialCustomString:(NSString*)dialKey
{
    return oo::NSStringFrom([self cxx_dialCustomString:oo::StdString(dialKey)]);
}

- (OOColor*)dialCustomColor:(NSString*)dialKey
{
    return [self cxx_dialCustomColor:oo::StdString(dialKey)];
}

- (void)setDialCustom:(id)value forKey:(NSString*)key
{
    [self cxx_setDialCustom:value forKey:oo::StdString(key)];
}

- (NSArray*)multiFunctionDisplayList
{
    NSMutableArray* list = [NSMutableArray array];
    for (const std::optional<std::string>& key : [self cxx_multiFunctionDisplayList]) {
        if (key.has_value())
            [list addObject:oo::NSStringFrom(*key)];
        else
            [list addObject:[OONull null]];
    }
    return list;
}

- (NSString*)multiFunctionText:(NSUInteger)index
{
    return oo::NSStringOrNil([self cxx_multiFunctionText:index]);
}

- (void)setMultiFunctionText:(NSString*)text forKey:(NSString*)key
{
    [self cxx_setMultiFunctionText:oo::OptionalString(text) forKey:oo::OptionalString(key)];
}

- (BOOL)setMultiFunctionDisplay:(NSUInteger)index toKey:(NSString*)key
{
    return [self cxx_setMultiFunctionDisplay:index toKey:oo::OptionalString(key)];
}

- (NSString*)dial_clock
{
    return oo::NSStringFrom([self cxx_dial_clock]);
}

- (NSString*)dial_clock_adjusted
{
    return oo::NSStringFrom([self cxx_dial_clock_adjusted]);
}

- (NSString*)dial_fpsinfo
{
    return oo::NSStringFrom([self cxx_dial_fpsinfo]);
}

- (NSString*)dial_objinfo
{
    return oo::NSStringFrom([self cxx_dial_objinfo]);
}

- (NSString*)compassTargetLabel
{
    return oo::NSStringOrNil([self cxx_compassTargetLabel]);
}

- (NSString*)dialTargetName
{
    return oo::NSStringOrNil([self cxx_dialTargetName]);
}

// oo-3rb.244: commander identity, fast equipment, comm log, target memory, wormholes and last shot
- (NSString*)commanderName
{
    return oo::NSStringOrNil([self cxx_commanderName]);
}

- (void)setCommanderName:(NSString*)value
{
    [self cxx_setCommanderName:oo::OptionalString(value)];
}

- (NSString*)lastsaveName
{
    return oo::NSStringOrNil([self cxx_lastsaveName]);
}

- (void)setLastsaveName:(NSString*)value
{
    [self cxx_setLastsaveName:oo::OptionalString(value)];
}

- (NSString*)jumpCause
{
    return oo::NSStringOrNil([self cxx_jumpCause]);
}

- (void)setJumpCause:(NSString*)value
{
    [self cxx_setJumpCause:oo::OptionalString(value)];
}

// An array of OONativeVector, as ShipEntity's -laserPortOffset: builds it.
- (NSArray*)currentLaserOffset
{
    std::vector<oo::ObjCRef<OONativeVector*>> offsets;
    for (Vector v : [self cxx_currentLaserOffset])
        offsets.push_back(oo::adoptObjC([[OONativeVector alloc] initWithVector:v]));
    return oo::NSArrayFromObjects(offsets);
}

- (NSString*)fastEquipmentA
{
    return oo::NSStringOrNil([self cxx_fastEquipmentA]);
}

- (NSString*)fastEquipmentB
{
    return oo::NSStringOrNil([self cxx_fastEquipmentB]);
}

- (void)setFastEquipmentA:(NSString*)eqKey
{
    [self cxx_setFastEquipmentA:oo::OptionalString(eqKey)];
}

- (void)setFastEquipmentB:(NSString*)eqKey
{
    [self cxx_setFastEquipmentB:oo::OptionalString(eqKey)];
}

- (NSMutableArray*)commLog
{
    const std::vector<std::string>* log = [self cxx_commLog];
    if (log == nullptr)
        return nil;
    return [NSMutableArray arrayWithArray:oo::NSArrayFromStrings(*log)];
}

- (NSMutableArray*)targetMemory
{
    NSMutableArray* memory = [NSMutableArray array];
    for (const oo::ObjCRef<OOWeakReference*>& slot : [self cxx_targetMemory]) {
        if (slot)
            [memory addObject:slot.get()];
        else
            [memory addObject:[OONull null]];
    }
    return memory;
}

- (NSArray*)scannedWormholes
{
    return oo::NSArrayFromObjects([self cxx_scannedWormholes]);
}

- (void)setLastShot:(NSArray*)shot
{
    [self cxx_setLastShot:oo::ObjCRefsFrom<OOLaserShotEntity*>(shot)];
}

// oo-3rb.245: custom views, screen background descriptors and script-defined keys
- (NSDictionary*)keyConfig
{
    return oo::ObjectFromPList([self cxx_keyConfig]);
}

- (NSString*)customViewDescription
{
    return oo::NSStringOrNil([self cxx_customViewDescription]);
}

- (void)setCustomViewDataFromDictionary:(NSDictionary*)viewDict withScaling:(BOOL)withScaling
{
    [self cxx_setCustomViewDataFromDictionary:oo::PListFrom(viewDict) withScaling:withScaling];
}

- (NSDictionary*)missionOverlayDescriptor
{
    return oo::ObjectFromPList([self cxx_missionOverlayDescriptor]);
}

- (NSDictionary*)missionOverlayDescriptorOrDefault
{
    return oo::ObjectFromPList([self cxx_missionOverlayDescriptorOrDefault]);
}

- (void)setMissionOverlayDescriptor:(NSDictionary*)descriptor
{
    [self cxx_setMissionOverlayDescriptor:oo::PListFrom(descriptor)];
}

- (NSDictionary*)missionBackgroundDescriptor
{
    return oo::ObjectFromPList([self cxx_missionBackgroundDescriptor]);
}

- (NSDictionary*)missionBackgroundDescriptorOrDefault
{
    return oo::ObjectFromPList([self cxx_missionBackgroundDescriptorOrDefault]);
}

- (void)setMissionBackgroundDescriptor:(NSDictionary*)descriptor
{
    [self cxx_setMissionBackgroundDescriptor:oo::PListFrom(descriptor)];
}

- (void)setMissionBackgroundSpecial:(NSString*)special
{
    [self cxx_setMissionBackgroundSpecial:oo::StdString(special)]; // nil -> "" -> none, as before
}

- (void)setExtraMissionKeys:(NSDictionary*)keys
{
    [self cxx_setExtraMissionKeys:oo::PListFrom(keys)];
}

- (void)clearExtraGuiScreenKeys:(OOGUIScreenID)gui key:(NSString*)key
{
    [self cxx_clearExtraGuiScreenKeys:gui key:oo::StdString(key)];
}

- (NSDictionary*)equipScreenBackgroundDescriptor
{
    return oo::ObjectFromPList([self cxx_equipScreenBackgroundDescriptor]);
}

- (void)setEquipScreenBackgroundDescriptor:(NSDictionary*)descriptor
{
    [self cxx_setEquipScreenBackgroundDescriptor:oo::PListFrom(descriptor)];
}

// oo-3rb.246: system data, chart, game options, load/save and equip-ship screens
- (void)setGuiToEquipShipScreen:(int)skip selectingFacingFor:(NSString*)eqKeyForSelectFacing
{
    [self cxx_setGuiToEquipShipScreen:skip selectingFacingFor:oo::OptionalString(eqKeyForSelectFacing)];
}

- (void)showInformationForSelectedUpgradeWithFormatString:(NSString*)extraString
{
    [self cxx_showInformationForSelectedUpgradeWithFormatString:oo::OptionalString(extraString)];
}

- (NSString*)screenModeStringForWidth:(unsigned)inWidth height:(unsigned)inHeight refreshRate:(float)inRate
{
    return oo::NSStringOrNil([self cxx_screenModeStringForWidth:inWidth height:inHeight refreshRate:inRate]);
}

// oo-3rb.247: market screens, commodity trading and cargo quantities (a nil good is "")
- (OOCargoQuantity)cargoQuantityForType:(OOCommodityType)type
{
    return [self cxx_cargoQuantityForType:oo::StdString(type)];
}

- (OOCargoQuantity)setCargoQuantityForType:(OOCommodityType)type amount:(OOCargoQuantity)amount
{
    return [self cxx_setCargoQuantityForType:oo::StdString(type) amount:amount];
}

- (NSArray*)applyMarketFilter:(NSArray*)goods onMarket:(OOCommodityMarket*)market
{
    return oo::NSArrayFromStrings([self cxx_applyMarketFilter:oo::StringsFrom(goods) onMarket:market]);
}

- (NSArray*)applyMarketSorter:(NSArray*)goods onMarket:(OOCommodityMarket*)market
{
    return oo::NSArrayFromStrings([self cxx_applyMarketSorter:oo::StringsFrom(goods) onMarket:market]);
}

- (BOOL)tryBuyingCommodity:(OOCommodityType)type all:(BOOL)all
{
    return [self cxx_tryBuyingCommodity:oo::StdString(type) all:all];
}

- (BOOL)trySellingCommodity:(OOCommodityType)type all:(BOOL)all
{
    return [self cxx_trySellingCommodity:oo::StdString(type) all:all];
}

// oo-3rb.248: missiles, pylons, damage, bounty, equipment add/remove and comms
- (BOOL)assignToActivePylon:(NSString*)identifierKey
{
    return [self cxx_assignToActivePylon:oo::StdString(identifierKey)];
}

- (BOOL)mountMissileWithRole:(NSString*)role
{
    return [self cxx_mountMissileWithRole:oo::StdString(role)];
}

- (BOOL)endScenario:(NSString*)key
{
    if (key == nil)
        return NO; // -isEqualToString: on nil
    return [self cxx_endScenario:oo::StdString(key)];
}

// oo-3rb.249: flight, cargo pods, docking, witchspace, targeting, ship model, trumbles and state dump
- (void)showShipModelWithKey:(NSString*)shipKey shipData:(NSDictionary*)shipData personality:(uint16_t)personality factorX:(GLfloat)factorX factorY:(GLfloat)factorY factorZ:(GLfloat)factorZ inContext:(NSString*)context
{
    if (shipKey == nil)
        return;
    [self cxx_showShipModelWithKey:oo::StdString(shipKey) shipData:oo::PListFrom(shipData) personality:personality factorX:factorX factorY:factorY factorZ:factorZ inContext:oo::OptionalString(context)];
}

// oo-3rb.250: interfaces, start and intro screens, buying equipment and weapon mounts
- (OOCreditsQuantity)adjustPriceByScriptForEqKey:(NSString*)eqKey withCurrent:(OOCreditsQuantity)price
{
    if (eqKey == nil)
        return price; // no equipment type, so no condition script
    return [self cxx_adjustPriceByScriptForEqKey:oo::StdString(eqKey) withCurrent:price];
}

- (BOOL)setWeaponMount:(OOWeaponFacing)facing toWeapon:(NSString*)eqKey inContext:(NSString*)context
{
    // canAddEquipment: read a nil key as ""; the weapon type of both is none
    return [self cxx_setWeaponMount:facing toWeapon:oo::StdString(eqKey) inContext:oo::OptionalString(context)];
}

// oo-3rb.251: roles, system memory and mission destinations
- (NSMutableArray*)roleWeights
{
    return [[oo::NSArrayFromStrings([self cxx_roleWeights]) mutableCopy] autorelease];
}

- (void)addRoleToPlayer:(NSString*)role
{
    [self cxx_addRoleToPlayer:oo::StdString(role)];
}

- (void)addRoleToPlayer:(NSString*)role inSlot:(NSUInteger)slot
{
    [self cxx_addRoleToPlayer:oo::StdString(role) inSlot:slot];
}

- (void)addMissionDestinationMarker:(NSDictionary*)marker
{
    [self cxx_addMissionDestinationMarker:oo::PListFrom(marker)]; // nil: null, which -cxx_validatedMarker: reads as nil did
}

- (BOOL)removeMissionDestinationMarker:(NSDictionary*)marker
{
    return [self cxx_removeMissionDestinationMarker:oo::PListFrom(marker)];
}

- (NSMutableDictionary*)getMissionDestinations
{
    return [[oo::ObjectFromPList([self cxx_getMissionDestinations]) mutableCopy] autorelease];
}

// oo-3rb.252: status screen and manifest lists
- (NSArray*)equipmentList
{
    return oo::ObjectFromPList(oo::PList([self cxx_equipmentList])); // colours come back as the OOColor objects
}

- (NSArray*)cargoList
{
    return oo::NSArrayFromStrings([self cxx_cargoList]);
}

// oo-3rb.255: mission strings, special cargo and equipment scripts
- (NSString*)specialCargo
{
    return oo::NSStringOrNil([self cxx_specialCargo]);
}

- (BOOL)setPrimedEquipment:(NSString*)eqKey showMessage:(BOOL)showMsg
{
    // nil matched no script and was not "": primed equipment unchanged, NO
    if (eqKey == nil)
        return NO;
    return [self cxx_setPrimedEquipment:oo::StdString(eqKey) showMessage:showMsg];
}

- (NSString*)primedEquipmentName:(NSInteger)offset
{
    return oo::NSStringOrNil([self cxx_primedEquipmentName:offset]);
}

- (NSString*)currentPrimedEquipment
{
    return oo::NSStringFrom([self cxx_currentPrimedEquipment]);
}

@end
