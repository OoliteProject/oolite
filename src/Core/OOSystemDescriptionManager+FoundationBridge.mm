/*

OOSystemDescriptionManager+FoundationBridge.mm

TRANSITIONAL: see OOSystemDescriptionManager+FoundationBridge.h. Each method forwards to its cxx_
counterpart and converts the result exactly as the old method produced it (nil for nil, immutable
collections, the property values' own objects and NSNumber types).

*/

#import "OOFoundationBridge.h"
#import "OOSystemDescriptionManager.h" // declares the bridge category at its end

@implementation OOSystemDescriptionManager (OOFoundationBridge)

// oo-3rb.107: scripted changes

- (void)importScriptedChanges:(NSDictionary*)scripted
{
    [self cxx_importScriptedChanges:oo::PListFrom(scripted)];
}

- (void)importLegacyScriptedChanges:(NSDictionary*)scripted
{
    [self cxx_importLegacyScriptedChanges:oo::PListFrom(scripted)];
}

- (NSDictionary*)exportScriptedChanges
{
    // an immutable copy (never nil), as -copy of the dictionary was
    return oo::ObjectFromPList([self cxx_exportScriptedChanges]);
}

// oo-3rb.108: storage and write side

- (void)setUniversalProperties:(NSDictionary*)properties
{
    [self cxx_setUniversalProperties:oo::PListFrom(properties)];
}

- (void)setInterstellarProperties:(NSDictionary*)properties
{
    [self cxx_setInterstellarProperties:oo::PListFrom(properties)];
}

- (void)setProperties:(NSDictionary*)properties forSystemKey:(NSString*)key
{
    [self cxx_setProperties:oo::PListFrom(properties) forSystemKey:oo::StdString(key)];
}

- (void)setProperty:(NSString*)property forSystemKey:(NSString*)key andLayer:(OOSystemLayer)layer toValue:(id)value fromManifest:(NSString*)manifest
{
    [self cxx_setProperty:oo::StdString(property) forSystemKey:oo::StdString(key) andLayer:layer toValue:oo::PListFrom(value) fromManifest:oo::OptionalString(manifest)];
}

// oo-3rb.109: property cache and read side (a fresh immutable dictionary per call where the old
// methods returned the cached one; the property values' own objects and NSNumber types)

- (NSDictionary*)getPropertiesForSystemKey:(NSString*)key
{
    return oo::ObjectFromPList([self cxx_getPropertiesForSystemKey:oo::StdString(key)]);
}

- (NSDictionary*)getPropertiesForSystem:(OOSystemID)s inGalaxy:(OOGalaxyID)g
{
    return oo::ObjectFromPList([self cxx_getPropertiesForSystem:s inGalaxy:g]);
}

- (NSDictionary*)getPropertiesForCurrentSystem
{
    return oo::ObjectFromPList([self cxx_getPropertiesForCurrentSystem]);
}

- (id)getProperty:(NSString*)property forSystemKey:(NSString*)key
{
    return oo::ObjectFromPList([self cxx_getProperty:oo::StdString(property) forSystemKey:oo::StdString(key)]);
}

- (id)getProperty:(NSString*)property forSystem:(OOSystemID)s inGalaxy:(OOGalaxyID)g
{
    return oo::ObjectFromPList([self cxx_getProperty:oo::StdString(property) forSystem:s inGalaxy:g]);
}

- (NSArray*)getNeighbourIDsForSystem:(OOSystemID)s inGalaxy:(OOGalaxyID)g
{
    const std::vector<OOSystemID> neighbours = [self cxx_getNeighbourIDsForSystem:s inGalaxy:g]; // logs an invalid system
    // nil for an invalid system, as the old method answered
    if (s < 0)
        return nil;
    NSUInteger index = (static_cast<NSUInteger>(g) * OO_SYSTEMS_PER_GALAXY) + static_cast<NSUInteger>(s);
    if (index >= static_cast<NSUInteger>(OO_SYSTEM_CACHE_LENGTH))
        return nil;
    NSMutableArray* result = [NSMutableArray arrayWithCapacity:neighbours.size()];
    for (OOSystemID neighbour : neighbours)
        [result addObject:[NSNumber numberWithUnsignedInteger:static_cast<NSUInteger>(neighbour)]];
    return [[result copy] autorelease];
}

@end
