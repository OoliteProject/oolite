/*

OOShipRegistry+FoundationBridge.mm

TRANSITIONAL: see OOShipRegistry+FoundationBridge.h. Each method forwards to its cxx_ counterpart
and converts the result exactly as the old method produced it (nil for nil, immutable collections).
A ship or effect dictionary is built afresh on each call (the old methods returned the stored
dictionary).

*/

#import "OOFoundationBridge.h"
#import "OOShipRegistry.h" // declares the bridge category at its end

@implementation OOShipRegistry (OOFoundationBridge)

// oo-3rb.114: ship and effect data

- (NSDictionary*)shipInfoForKey:(NSString*)key
{
    if (key == nil)
        return nil; // -objectForKey:nil was nil
    return oo::ObjectFromPList([self cxx_shipInfoForKey:oo::StdString(key)]);
}

- (void)setShipInfoForKey:(NSString*)key with:(NSDictionary*)newShipData
{
    [self cxx_setShipInfoForKey:oo::StdString(key) with:oo::PListFrom(newShipData)];
}

- (NSDictionary*)effectInfoForKey:(NSString*)key
{
    if (key == nil)
        return nil;
    return oo::ObjectFromPList([self cxx_effectInfoForKey:oo::StdString(key)]);
}

- (NSDictionary*)shipyardInfoForKey:(NSString*)key
{
    if (key == nil)
        return nil;
    return oo::ObjectFromPList([self cxx_shipyardInfoForKey:oo::StdString(key)]);
}

- (NSArray*)playerShipKeys
{
    return oo::NSArrayFromStrings([self cxx_playerShipKeys]);
}

- (NSArray*)shipKeys
{
    return oo::NSArrayFromStrings([self cxx_shipKeys]);
}

// oo-3rb.115: role probability sets and demo ships

- (OOProbabilitySet*)probabilitySetForRole:(NSString*)role
{
    if (role == nil)
        return nil;
    return [self cxx_probabilitySetForRole:oo::StdString(role)];
}

- (NSArray*)demoShipKeys
{
    return oo::ObjectFromPList([self cxx_demoShipKeys]);
}

- (NSArray*)shipRoles
{
    return oo::NSArrayFromStrings([self cxx_shipRoles]);
}

- (NSArray*)shipKeysWithRole:(NSString*)role
{
    // nil where there was no set (a message to nil), else the set's objects
    if ([self probabilitySetForRole:role] == nil)
        return nil;
    return oo::NSArrayFromStrings([self cxx_shipKeysWithRole:oo::StdString(role)]);
}

- (NSString*)randomShipKeyForRole:(NSString*)role
{
    if (role == nil)
        return nil;
    return oo::NSStringOrNil([self cxx_randomShipKeyForRole:oo::StdString(role)]);
}

@end
