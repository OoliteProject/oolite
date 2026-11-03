/*

ShipEntity+FoundationBridge.mm

TRANSITIONAL: see ShipEntity+FoundationBridge.h. Each method forwards to its cxx_ counterpart and
converts arguments and results at the boundary, as the old method produced them (nil for nil).

*/

#import "OOExhaustPlumeEntity.h"
#import "OOFoundationBridge.h"
#import "OOVector.h"
#import "ShipEntity.h" // declares the bridge category at its end

namespace {

// The weapon offsets as the old accessors held them: an array of OONativeVector.
NSArray* NativeVectorArray(const std::vector<Vector>& vectors)
{
    std::vector<oo::ObjCRef<OONativeVector*>> result;
    result.reserve(vectors.size());
    for (Vector v : vectors)
        result.push_back(oo::adoptObjC([[OONativeVector alloc] initWithVector:v]));
    return oo::NSArrayFromObjects(result);
}

} // namespace

@implementation ShipEntity (OOFoundationBridge)

// oo-3rb.232: subentities

- (NSEnumerator*)shipSubEntityEnumerator
{
    return [oo::NSArrayFromObjects([self cxx_shipSubEntities]) objectEnumerator];
}

- (NSEnumerator*)exhaustEnumerator
{
    return [oo::NSArrayFromObjects([self cxx_exhausts]) objectEnumerator];
}

- (NSString*)serializeShipSubEntities
{
    return oo::NSStringOrNil([self cxx_serializeShipSubEntities]);
}

- (void)deserializeShipSubEntitiesFrom:(NSString*)string
{
    [self cxx_deserializeShipSubEntitiesFrom:oo::StdString(string)];
}

- (BOOL)setUpOneStandardSubentity:(NSDictionary*)subentDict asTurret:(BOOL)asTurret
{
    return [self cxx_setUpOneStandardSubentity:oo::PListFrom(subentDict) asTurret:asTurret];
}

// oo-3rb.233: equipment

- (NSUInteger)countEquipmentItem:(NSString*)eqkey
{
    return [self cxx_countEquipmentItem:oo::StdString(eqkey)];
}

- (NSString*)equipmentItemProviding:(NSString*)equipmentType
{
    return oo::NSStringOrNil([self cxx_equipmentItemProviding:oo::StdString(equipmentType)]);
}

- (BOOL)hasEquipmentItemProviding:(NSString*)equipmentType
{
    return [self cxx_hasEquipmentItemProviding:oo::StdString(equipmentType)];
}

- (BOOL)equipmentValidToAdd:(NSString*)equipmentKey inContext:(NSString*)context
{
    return [self cxx_equipmentValidToAdd:oo::StdString(equipmentKey) inContext:oo::StdString(context)];
}

- (BOOL)equipmentValidToAdd:(NSString*)equipmentKey whileLoading:(BOOL)loading inContext:(NSString*)context
{
    return [self cxx_equipmentValidToAdd:oo::StdString(equipmentKey) whileLoading:loading inContext:oo::StdString(context)];
}

- (NSEnumerator*)equipmentEnumerator
{
    return [oo::NSArrayFromStrings([self cxx_equipmentKeys]) objectEnumerator];
}

- (BOOL)hasOneEquipmentItem:(NSString*)itemKey includeWeapons:(BOOL)includeMissiles whileLoading:(BOOL)loading
{
    return [self cxx_hasOneEquipmentItem:oo::StdString(itemKey) includeWeapons:includeMissiles whileLoading:loading];
}

- (BOOL)hasOneEquipmentItem:(NSString*)itemKey includeMissiles:(BOOL)includeMissiles whileLoading:(BOOL)loading
{
    return [self cxx_hasOneEquipmentItem:oo::StdString(itemKey) includeMissiles:includeMissiles whileLoading:loading];
}

- (NSArray*)equipmentListForScripting
{
    return oo::NSArrayFromObjects([self cxx_equipmentListForScripting]);
}

// oo-3rb.234: missiles and weapon mounts

- (NSArray*)aftWeaponOffset
{
    return NativeVectorArray([self cxx_aftWeaponOffset]);
}

- (NSArray*)forwardWeaponOffset
{
    return NativeVectorArray([self cxx_forwardWeaponOffset]);
}

- (NSArray*)portWeaponOffset
{
    return NativeVectorArray([self cxx_portWeaponOffset]);
}

- (NSArray*)starboardWeaponOffset
{
    return NativeVectorArray([self cxx_starboardWeaponOffset]);
}

- (NSArray*)laserPortOffset:(OOWeaponFacing)direction
{
    return NativeVectorArray([self cxx_laserPortOffset:direction]);
}

- (BOOL)fireLaserShotInDirection:(OOWeaponFacing)direction weaponIdentifier:(NSString*)weaponIdentifier
{
    return [self cxx_fireLaserShotInDirection:direction weaponIdentifier:oo::StdString(weaponIdentifier)];
}

- (ShipEntity*)fireMissileWithIdentifier:(NSString*)identifier andTarget:(Entity*)target
{
    return [self cxx_fireMissileWithIdentifier:oo::OptionalString(identifier) andTarget:target];
}

// oo-3rb.235: cargo API and commodities

- (void)setCommodity:(OOCommodityType)co_type andAmount:(OOCargoQuantity)co_amount
{
    if (co_type != nil)
        [self cxx_setCommodity:oo::StdString(co_type) andAmount:co_amount]; // nil: no change, as before
}

- (void)setCommodityForPod:(OOCommodityType)co_type andAmount:(OOCargoQuantity)co_amount
{
    [self cxx_setCommodityForPod:oo::OptionalString(co_type) andAmount:co_amount];
}

- (OOCommodityType)commodityType
{
    return oo::NSStringOrNil([self cxx_commodityType]);
}

- (BOOL)addCargo:(NSArray*)some_cargo
{
    return [self cxx_addCargo:oo::ObjCRefsFrom<ShipEntity*>(some_cargo)];
}

- (BOOL)removeCargo:(OOCommodityType)commodity amount:(OOCargoQuantity)amount
{
    // nil matched no pod (-isEqualToString:nil); "" matches none either (a commodity key is never empty).
    return [self cxx_removeCargo:oo::StdString(commodity) amount:amount];
}

- (ShipEntity*)dumpCargoItem:(OOCommodityType)preferred
{
    return [self cxx_dumpCargoItem:oo::OptionalString(preferred)];
}

// oo-3rb.237: crew, escorts, groups and escape pods

- (NSEnumerator*)escortEnumerator
{
    return [oo::NSArrayFromObjects([self cxx_escorts]) objectEnumerator];
}

- (NSArray*)crew
{
    const std::optional<std::vector<oo::ObjCRef<OOCharacter*>>> members = [self cxx_crew];
    return members.has_value() ? oo::NSArrayFromObjects(*members) : nil; // nil: unpiloted (callers test it)
}

- (NSArray*)crewForScripting
{
    if (![self cxx_crew].has_value())
        return nil; // no crew (or a nil receiver): nil, as before
    const std::vector<oo::PList> entries = [self cxx_crewForScripting];
    return oo::ObjectFromPList(oo::PList(oo::PList::Array(entries.begin(), entries.end())));
}

- (void)setCrew:(NSArray*)crewArray
{
    if (crewArray == nil)
        [self cxx_setCrew:std::nullopt];
    else
        [self cxx_setCrew:oo::ObjCRefsFrom<OOCharacter*>(crewArray)];
}

- (void)setSingleCrewWithRole:(NSString*)crewRole
{
    [self cxx_setSingleCrewWithRole:oo::StdString(crewRole)];
}

// oo-3rb.238: combat, collisions, defense targets, explosions, docking instructions

- (NSEnumerator*)defenseTargetEnumerator
{
    return [oo::NSArrayFromObjects([self cxx_defenseTargets]) objectEnumerator];
}

- (NSArray*)collisionExceptions
{
    return oo::NSArrayFromObjects([self cxx_collisionExceptions]);
}

- (NSDictionary*)dockingInstructions
{
    return oo::ObjectFromPList([self cxx_dockingInstructions]); // nil for none
}

// oo-3rb.239: messages, comms and AI dispatch

- (void)sendExpandedMessage:(NSString*)message_text toShip:(ShipEntity*)other_ship
{
    if (message_text == nil)
        return; // nothing to send (the old method expanded nil to nothing)
    [self cxx_sendExpandedMessage:oo::StdString(message_text) toShip:other_ship];
}

- (void)sendMessage:(NSString*)message_text toShip:(ShipEntity*)other_ship withUnpilotedOverride:(BOOL)unpilotedOverride
{
    if (message_text == nil)
        return; // as the old method returned at once for nil
    [self cxx_sendMessage:oo::StdString(message_text) toShip:other_ship withUnpilotedOverride:unpilotedOverride];
}

- (void)commsMessage:(NSString*)valueString withUnpilotedOverride:(BOOL)unpilotedOverride
{
    [self cxx_commsMessage:oo::StdString(valueString) withUnpilotedOverride:unpilotedOverride];
}

- (void)doScriptEvent:(OOJSPropID)message withArguments:(NSArray*)arguments
{
    [self cxx_doScriptEvent:message withArguments:oo::ObjCRefsFrom<id>(arguments)];
}

- (void)reactToAIMessage:(NSString*)message context:(NSString*)debugContext
{
    [self cxx_reactToAIMessage:oo::StdString(message) context:oo::OptionalString(debugContext)];
}

- (void)doScriptEvent:(OOJSPropID)scriptEvent andReactToAIMessage:(NSString*)aiMessage
{
    [self cxx_doScriptEvent:scriptEvent andReactToAIMessage:oo::StdString(aiMessage)];
}

- (void)doScriptEvent:(OOJSPropID)scriptEvent withArgument:(id)argument andReactToAIMessage:(NSString*)aiMessage
{
    [self cxx_doScriptEvent:scriptEvent withArgument:argument andReactToAIMessage:oo::StdString(aiMessage)];
}

// oo-3rb.240: identity: names, roles, ship key, descriptions

- (NSString*)shipDataKey
{
    return oo::NSStringOrNil([self cxx_shipDataKey]);
}

- (NSString*)shipDataKeyAutoRole
{
    return oo::NSStringOrNil([self cxx_shipDataKeyAutoRole]);
}

- (void)setShipDataKey:(NSString*)key
{
    [self cxx_setShipDataKey:oo::OptionalString(key)];
}

- (NSString*)shipUniqueName
{
    return oo::NSStringOrNil([self cxx_shipUniqueName]);
}

- (NSString*)shipClassName
{
    return oo::NSStringOrNil([self cxx_shipClassName]);
}

- (NSString*)scanDescription
{
    return oo::NSStringOrNil([self cxx_scanDescription]);
}

- (NSString*)scanDescriptionForScripting
{
    return oo::NSStringOrNil([self cxx_scanDescriptionForScripting]);
}

- (void)setShipUniqueName:(NSString*)inName
{
    [self cxx_setShipUniqueName:oo::OptionalString(inName)];
}

- (void)setShipClassName:(NSString*)inName
{
    [self cxx_setShipClassName:oo::OptionalString(inName)];
}

- (void)setDisplayName:(NSString*)inName
{
    [self cxx_setDisplayName:oo::OptionalString(inName)];
}

- (void)setScanDescription:(NSString*)inName
{
    [self cxx_setScanDescription:oo::OptionalString(inName)];
}

- (void)addRole:(NSString*)role withProbability:(float)probability
{
    [self cxx_addRole:oo::StdString(role) withProbability:probability];
}

- (void)removeRole:(NSString*)role
{
    [self cxx_removeRole:oo::StdString(role)];
}

- (NSString*)primaryRole
{
    return oo::NSStringOrNil([self cxx_primaryRole]);
}

- (BOOL)hasPrimaryRole:(NSString*)role
{
    if (role == nil) {
        (void)[self cxx_primaryRole]; // still chooses a primary role if there is none, as before
        return NO; // -isEqual: nil was NO
    }
    return [self cxx_hasPrimaryRole:oo::StdString(role)];
}

// oo-3rb.241: setup

- (BOOL)setUpFromDictionary:(NSDictionary*)shipDict
{
    return [self cxx_setUpFromDictionary:oo::PListFrom(shipDict)];
}

- (NSDictionary*)shipInfoDictionary
{
    return oo::ObjectFromPList([self cxx_shipInfoDictionary]); // nil when not set up
}

// oo-3rb.242: script

- (void)setShipScript:(NSString*)script_name
{
    [self cxx_setShipScript:oo::OptionalString(script_name)];
}

@end

Vector positionOffsetForShipInRotationToAlignment(ShipEntity* ship, Quaternion q, NSString* align)
{
    // nil printed "(null)---" through %@, whose first three units select nothing, as "" does.
    return cxx_positionOffsetForShipInRotationToAlignment(ship, q, oo::StdString(align));
}
