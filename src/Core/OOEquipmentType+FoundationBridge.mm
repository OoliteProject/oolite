/*

OOEquipmentType+FoundationBridge.mm

TRANSITIONAL: see OOEquipmentType+FoundationBridge.h. Each method forwards to its cxx_
counterpart and converts arguments and results at the boundary (nil for nil).

*/

#import "OOEquipmentType.h" // declares the bridge category at its end
#import "OOFoundationBridge.h"

@implementation OOEquipmentType (OOFoundationBridge)

+ (void)addEquipmentWithInfo:(NSArray*)itemInfo
{
    [self cxx_addEquipmentWithInfo:oo::PListFrom(itemInfo)];
}

+ (NSArray*)allEquipmentTypes
{
    return oo::NSArrayFromObjects([self cxx_allEquipmentTypes]);
}

+ (NSEnumerator*)equipmentEnumerator
{
    return [oo::NSArrayFromObjects([self cxx_allEquipmentTypes]) objectEnumerator];
}

+ (NSEnumerator*)reverseEquipmentEnumerator
{
    return [oo::NSArrayFromObjects([self cxx_allEquipmentTypes]) reverseObjectEnumerator];
}

+ (NSEnumerator*)equipmentEnumeratorOutfitting
{
    return [oo::NSArrayFromObjects([self cxx_allEquipmentTypesOutfitting]) objectEnumerator];
}

+ (NSString*)getMissileRegistryRoleForShip:(NSString*)shipKey
{
    if (shipKey == nil)
        return nil;
    return oo::NSStringOrNil([self cxx_getMissileRegistryRoleForShip:oo::StdString(shipKey)]);
}

+ (void)setMissileRegistryRole:(NSString*)role forShip:(NSString*)shipKey
{
    if (role != nil && shipKey != nil) {
        [self cxx_setMissileRegistryRole:oo::StdString(role) forShip:oo::StdString(shipKey)];
    }
}

+ (OOEquipmentType*)equipmentTypeWithIdentifier:(NSString*)identifier
{
    if (identifier == nil)
        return nil;
    return [self cxx_equipmentTypeWithIdentifier:oo::StdString(identifier)];
}

- (NSString*)identifier
{
    return oo::NSStringOrNil([self cxx_identifier]);
}

- (NSString*)damagedIdentifier
{
    return oo::NSStringOrNil([self cxx_damagedIdentifier]);
}

- (NSString*)descriptiveText
{
    return oo::NSStringOrNil([self cxx_descriptiveText]);
}

- (NSSet*)requiresEquipment
{
    const std::optional<std::vector<std::string>> keys = [self cxx_requiresEquipment];
    return keys.has_value() ? oo::NSSetFromStrings(*keys) : nil;
}

- (NSSet*)requiresAnyEquipment
{
    const std::optional<std::vector<std::string>> keys = [self cxx_requiresAnyEquipment];
    return keys.has_value() ? oo::NSSetFromStrings(*keys) : nil;
}

- (NSSet*)incompatibleEquipment
{
    const std::optional<std::vector<std::string>> keys = [self cxx_incompatibleEquipment];
    return keys.has_value() ? oo::NSSetFromStrings(*keys) : nil;
}

- (NSArray*)conditions
{
    return oo::ObjectFromPList([self cxx_conditions]);
}

- (NSString*)conditionScript
{
    return oo::NSStringOrNil([self cxx_conditionScript]);
}

- (NSString*)scriptName
{
    return oo::NSStringOrNil([self cxx_scriptName]);
}

- (NSArray*)defaultActivateKey
{
    return oo::ObjectFromPList([self cxx_defaultActivateKey]);
}

- (NSArray*)defaultModeKey
{
    return oo::ObjectFromPList([self cxx_defaultModeKey]);
}

- (NSArray*)providesForScripting
{
    return oo::NSArrayFromStrings([self cxx_providesForScripting]);
}

- (BOOL)provides:(NSString*)key
{
    if (key == nil)
        return NO;
    return [self cxx_provides:oo::StdString(key)];
}

- (NSDictionary*)weaponInfo
{
    return oo::ObjectFromPList([self cxx_weaponInfo]);
}

- (NSString*)fxShotMissName
{
    return oo::NSStringOrNil([self cxx_fxShotMissName]);
}

- (NSString*)fxShotHitName
{
    return oo::NSStringOrNil([self cxx_fxShotHitName]);
}

- (NSString*)fxShieldHitName
{
    return oo::NSStringOrNil([self cxx_fxShieldHitName]);
}

- (NSString*)fxUnshieldedHitName
{
    return oo::NSStringOrNil([self cxx_fxUnshieldedHitName]);
}

- (NSString*)fxWeaponLaunchedName
{
    return oo::NSStringOrNil([self cxx_fxWeaponLaunchedName]);
}

@end
