/*

OOCacheManager+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, bead oo-rmd7): the Objective-C OOCacheManager facade, and the
Objective-C write task OOAsyncCacheWriter. See OOCacheManager+ObjCBridge.h.

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

#import "OOAsyncWorkManager.h"
#import "OOCacheManager.h"
#import "OOLogging.h"

#include "oofnd/objc/OOObjCPeer.h"

namespace {

// Never destroyed: a facade may be released while the process exits.
oo::ObjCPeers& Peers()
{
    static oo::ObjCPeers* peers = new oo::ObjCPeers;
    return *peers;
}

} // namespace

@interface OOCacheManager (OOObjCBridgePrivate)

- (id)initWithCxxCache:(cxx::OOCacheManager*)cache;

@end

@implementation OOCacheManager

// Inside the @implementation for the private ivar.
OOCacheManager* oo::ToObjC(cxx::OOCacheManager* cache)
{
    return Peers().peerFor(cache, [cache] { return [[OOCacheManager alloc] initWithCxxCache:cache]; });
}

cxx::OOCacheManager* oo::ToCxx(OOCacheManager* cache)
{
    if (cache == nil)
        return nullptr;
    return cache->_cxxCache.get();
}

- (id)initWithCxxCache:(cxx::OOCacheManager*)cache
{
    self = [super init];
    if (self != nil)
        _cxxCache = oo::Ref<cxx::OOCacheManager>(cache);
    return self;
}

- (void)dealloc
{
    Peers().forget(_cxxCache.get());
    [super dealloc];
}

- (std::optional<std::string>)cxx_descriptionComponents
{
    return _cxxCache->descriptionComponents();
}

+ (OOCacheManager*)sharedCache
{
    // One facade for the life of the process, as there was one object (amendment oo-r7m0, item 5).
    static OOCacheManager* facade = nil;
    if (facade == nil)
        facade = [oo::ToObjC(cxx::OOCacheManager::sharedCache()) retain];
    return facade;
}

- (oo::PList)cxx_pListForKey:(const std::string&)key inCache:(const std::string&)cache
{
    return _cxxCache->pListForKey(key, cache);
}

- (void)cxx_setPList:(const oo::PList&)value forKey:(const std::string&)key inCache:(const std::string&)cache
{
    _cxxCache->setPList(value, key, cache);
}

- (void)cxx_removeObjectForKey:(const std::string&)inKey inCache:(const std::string&)inCacheKey
{
    _cxxCache->removeObjectForKey(inKey, inCacheKey);
}

- (void)cxx_clearCache:(const std::string&)inCacheKey
{
    _cxxCache->clearCache(inCacheKey);
}
- (void)clearAllCaches
{
    _cxxCache->clearAllCaches();
}
- (void)reloadAllCaches
{
    _cxxCache->reloadAllCaches();
}
- (void)setAllowCacheWrites:(BOOL)flag
{
    _cxxCache->setAllowCacheWrites(flag);
}

- (std::optional<std::string>)cxx_cacheDirectoryPathCreatingIfNecessary:(BOOL)create
{
    return _cxxCache->cacheDirectoryPathCreatingIfNecessary(create);
}

- (void)flush
{
    _cxxCache->flush();
}
- (void)finishOngoingFlush
{
    _cxxCache->finishOngoingFlush();
}

@end

// The protocol is adopted here, so that OOCacheManager+ObjCBridge.h need not import
// OOAsyncWorkManager.h (amendment oo-rmd7).
@interface OOAsyncCacheWriter () <OOAsyncWorkTask>
@end

@implementation OOAsyncCacheWriter {
@private
    oo::PList _cacheContents;
}

- (id)initWithCacheContents:(const oo::PList&)cacheContents
{
    if ((self = [super init])) {
        _cacheContents = cacheContents;
        if (_cacheContents.isNull()) {
            [self release];
            self = nil;
        }
    }

    return self;
}

- (void)performAsyncTask
{
    if (cxx::OOCacheManager::sharedCache()->writeDict(_cacheContents)) {
        OO_LOG("dataCache.write.success", "{}", "Wrote data cache.");
    } else {
        OO_LOG("dataCache.write.failed", "{}", "Failed to write data cache.");
    }
    _cacheContents = oo::PList();
}

- (void)completeAsyncTask
{
    // Don't need to do anything, but this needs to be here so we can wait on it.
}

@end
