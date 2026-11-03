/*

OOCacheManager+FoundationBridge.mm

TRANSITIONAL: see OOCacheManager+FoundationBridge.h. Each method forwards to its cxx_ counterpart
and converts the result exactly as the old method produced it (nil for nil). The nil-argument
assertions the old methods made are made here, before the conversion.

*/

#import "OOCacheManager.h" // declares the bridge category at its end
#import "OOFoundationBridge.h"

@implementation OOCacheManager (OOFoundationBridge)

- (id)objectForKey:(NSString*)inKey inCache:(NSString*)inCacheKey
{
    NSParameterAssert(inKey != nil && inCacheKey != nil);
    return [self cxx_objectForKey:oo::StdString(inKey) inCache:oo::StdString(inCacheKey)];
}

- (void)setObject:(id)inElement forKey:(NSString*)inKey inCache:(NSString*)inCacheKey
{
    NSParameterAssert(inElement != nil && inKey != nil && inCacheKey != nil);
    [self cxx_setObject:inElement forKey:oo::StdString(inKey) inCache:oo::StdString(inCacheKey)];
}

- (void)removeObjectForKey:(NSString*)inKey inCache:(NSString*)inCacheKey
{
    NSParameterAssert(inKey != nil && inCacheKey != nil);
    [self cxx_removeObjectForKey:oo::StdString(inKey) inCache:oo::StdString(inCacheKey)];
}

- (void)clearCache:(NSString*)inCacheKey
{
    NSParameterAssert(inCacheKey != nil);
    [self cxx_clearCache:oo::StdString(inCacheKey)];
}

- (NSString*)cacheDirectoryPathCreatingIfNecessary:(BOOL)create
{
    return oo::NSStringOrNil([self cxx_cacheDirectoryPathCreatingIfNecessary:create]);
}

@end
