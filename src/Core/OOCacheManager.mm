/*

OOCacheManager.m

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

#import "OOCacheManager.h"
#import "OOFoundationBridge.h"
#import "OOJavaScriptEngine.h"

#include "oofnd/FileSystem.hpp"
#include "oofnd/PListParsing.hpp"
#include "oofnd/PListWriting.hpp"
#include "oofnd/ResourcePaths.hpp"
#include "oofnd/String.hpp"

/*
        Foundation sweep (proposed ADR-0043, bead oo-19g0): the caches are std::maps of retained
        objects; the cache file is read and written as an oo::PList, in XML (proposed ADR-0027 item 3:
        oofnd does not parse GNUstep's binary format, and an unreadable cache is rebuilt).
*/

#define WRITE_ASYNC 1
#define PROFILE_WRITES 0

#if WRITE_ASYNC
#import "OOAsyncWorkManager.h"
#endif
#if PROFILE_WRITES
#import "OOProfilingStopwatch.h"
#endif
#include "oofnd/objc/OOAssert.h"

namespace {
constexpr const char* kCacheKeyVersion = "version";
constexpr const char* kCacheKeyEndianTag = "endian tag";
constexpr const char* kCacheKeyFormatVersion = "format version";
constexpr const char* kCacheKeyCaches = "caches";
} // namespace

enum {
    kEndianTagValue = 0x0123456789ABCDEFULL,
    kFormatVersionValue = 219
};

static OOCacheManager* sSingleton = nil;

namespace {
using CacheEntries = std::map<std::string, oo::ObjCRef<id>, std::less<>>;

// The cache named <name>, or nullptr (no such cache, or no caches at all), as -objectForKey: on
// the dictionary of caches (or on nil) answered.
CacheEntries* FindCache(std::optional<std::map<std::string, CacheEntries, std::less<>>>& caches, const std::string& name)
{
    if (!caches.has_value())
        return nullptr;
    const auto it = caches->find(name);
    return it != caches->end() ? &it->second : nullptr;
}
} // namespace

@interface OOCacheManager (Private)

- (void)loadCache;
- (void)write;
- (void)clear;
- (BOOL)dirty;
- (void)markClean;

- (oo::PList)loadDict; // null: no cache
- (BOOL)writeDict:(const oo::PList&)inDict;

- (void)buildCachesFromDictionary:(const oo::PList*)inDict; // nullptr: none
- (oo::PList)dictionaryOfCaches;

- (BOOL)directoryExists:(const std::string&)inPath create:(BOOL)inCreate;

@end

@interface OOCacheManager (PlatformSpecific)

- (std::optional<std::string>)cachePathCreatingIfNecessary:(BOOL)inCreate;

@end

#if WRITE_ASYNC
@interface OOAsyncCacheWriter : OOObject <OOAsyncWorkTask> {
@private
    oo::PList _cacheContents;
}

- (id)initWithCacheContents:(const oo::PList&)cacheContents;

@end
#endif

namespace {

// Info-gnustep.plist string (CFBundleVersion / CFBundleName as the Override category used to expose).
std::optional<std::string> OoliteInfoString(std::string_view key)
{
    const oo::fs::Path plistPath = oo::ResourcePaths::current().builtInResourcesDirectory() / "Info-gnustep.plist";
    oo::PList info;
    if (const oo::fs::Result<oo::Data> bytes = oo::fs::readFile(plistPath); bytes && !bytes->empty()) {
        if (oo::Expected<oo::PList, oo::PListError> parsed = oo::parsePropertyList(bytes->stringView());
            parsed && parsed->isDict())
            info = std::move(*parsed);
    }
    if (const oo::PList* v = info.find(key); v != nullptr && v->isString())
        return *v->getIf<std::string>();
    return std::nullopt;
}

} // namespace

@implementation OOCacheManager

- (id)init
{
    self = [super init];
    if (self != nil) {
        _permitWrites = YES;
        [self loadCache];
    }
    return self;
}

- (void)dealloc
{
    [self clear];

    [super dealloc];
}

// OOObject's -description wraps this as "<OOCacheManager 0x...>{dirty=...}", which is what this
// class's own -description printed.
- (id)descriptionComponents
{
    return oo::NSStringFrom(oo::str::format("dirty=%s", [self dirty] ? "yes" : "no"));
}

+ (OOCacheManager*)sharedCache
{
    // NOTE: assumes single-threaded access.
    if (sSingleton == nil) {
        sSingleton = [[self alloc] init];
    }

    return sSingleton;
}

- (id)cxx_objectForKey:(const std::string&)inKey inCache:(const std::string&)inCacheKey
{
    id result = nil;

    CacheEntries* cache = FindCache(_caches, inCacheKey);
    if (cache != nullptr) {
        const auto entry = cache->find(inKey);
        if (entry != cache->end())
            result = entry->second.get();
        if (result != nil) {
#if OO_DEBUG
            OO_LOG("dataCache.retrieve.success", "Retrieved \"{}\" cache object {}.", inCacheKey, inKey);
#endif
        } else {
#if OO_DEBUG
            OO_LOG("dataCache.retrieve.failed", "Failed to retrieve \"{}\" cache object {} -- no such entry.", inCacheKey, inKey);
#endif
        }
    } else {
#if OO_DEBUG
        OO_LOG("dataCache.retrieve.failed", "Failed to retrieve \"{}\" cache object {} -- no such cache.", inCacheKey, inKey);
#endif
    }

    return result;
}

- (void)cxx_setObject:(id)inObject forKey:(const std::string&)inKey inCache:(const std::string&)inCacheKey
{
    OOParameterAssert(inObject != nil);

    if (EXPECT_NOT(!_caches.has_value()))
        return;

    // A missing cache is created, empty, as before.
    (*_caches)[inCacheKey][inKey] = oo::ObjCRef<id>(inObject);
    _dirty = YES;
#if OO_DEBUG
    OO_LOG("dataCache.set.success", "Updated entry {} in cache \"{}\".", inKey, inCacheKey);
#endif
}

- (void)cxx_removeObjectForKey:(const std::string&)inKey inCache:(const std::string&)inCacheKey
{
    CacheEntries* cache = FindCache(_caches, inCacheKey);
    if (cache != nullptr) {
        if (cache->erase(inKey) != 0) {
            _dirty = YES;
#if OO_DEBUG
            OO_LOG("dataCache.remove.success", "Removed entry keyed {} from cache \"{}\".", inKey, inCacheKey);
#endif
        } else {
#if OO_DEBUG
            OO_LOG("dataCache.remove.success", "No need to remove non-existent entry keyed {} from cache \"{}\".", inKey, inCacheKey);
#endif
        }
    } else {
#if OO_DEBUG
        OO_LOG("dataCache.remove.success", "No need to remove entry keyed {} from non-existent cache \"{}\".", inKey, inCacheKey);
#endif
    }
}

- (void)cxx_clearCache:(const std::string&)inCacheKey
{
    if (FindCache(_caches, inCacheKey) != nullptr) {
        _caches->erase(inCacheKey);
        _dirty = YES;
#if OO_DEBUG
        OO_LOG("dataCache.clear.success", "Cleared cache \"{}\".", inCacheKey);
#endif
    } else {
#if OO_DEBUG
        OO_LOG("dataCache.clear.success", "No need to clear non-existent cache \"{}\".", inCacheKey);
#endif
    }
}

- (void)clearAllCaches
{
    [self clear];
    _caches.emplace();
    _dirty = YES;
}

- (void)reloadAllCaches
{
    [self clear];
    [self loadCache];
}

- (void)flush
{
    if (_permitWrites && [self dirty] && _scheduledWrite == nil) {
        [self write];
        [self markClean];
    }
}

- (void)finishOngoingFlush
{
#if WRITE_ASYNC
    [[OOAsyncWorkManager sharedAsyncWorkManager] waitForTaskToComplete:_scheduledWrite];
#endif
}

- (void)setAllowCacheWrites:(BOOL)flag
{
    _permitWrites = (flag != NO);
}

- (std::optional<std::string>)cxx_cacheDirectoryPathCreatingIfNecessary:(BOOL)create
{
    /*	Construct the path to the directory for cache files, which is:
                    ~/Library/Caches/org.aegidian.oolite/
                    or
                    ~/GNUStep/Library/Caches/org.aegidian.oolite/
            In addition to generally being the right place to put caches,
            ~/Library/Caches has the particular advantage of not being indexed by
            Spotlight or backed up by Time Machine.
    */
    std::string cachePath = oo::StdString([NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0]);
    if (![self directoryExists:cachePath create:create])
        return std::nullopt;

#if !OOLITE_MAC_OS_X
    // the old cache file on GNUstep was one level up, so remove it if it exists
    (void)oo::fs::removeItem(oo::fs::pathFromUTF8(oo::str::appendingPathComponent(cachePath, "Oolite-cache.plist")));
#endif

    cachePath = oo::str::appendingPathComponent(cachePath, "org.aegidian.oolite");
    if (![self directoryExists:cachePath create:create])
        return std::nullopt;
    return cachePath;
}

@end

@implementation OOCacheManager (Private)

- (void)loadCache
{
    BOOL accept = YES;
    uint64_t endianTagValue = 0;

    const std::optional<std::string> ooliteVersion = OoliteInfoString("CFBundleVersion");

    [self clear];

    const oo::PList cache = [self loadDict];
    if (!cache.isNull()) {
        // We have a cache
        OO_LOG("dataCache.found", "{}", "Found data cache.");
        oo::log::indentIf("dataCache.found");

        const oo::PList* cacheVersion = cache.find(kCacheKeyVersion);
        const std::string* cacheVersionString = cacheVersion != nullptr ? cacheVersion->getIf<std::string>() : nullptr;
        // -isEqual: between the two; a missing version on either side never matched.
        if (cacheVersionString == nullptr || !ooliteVersion.has_value() || *cacheVersionString != *ooliteVersion) {
            OO_LOG("dataCache.rebuild", "Data cache version ({}) does not match Oolite version ({}), rebuilding cache.", oo::DescriptionOf(oo::ObjectFromPList(cacheVersion != nullptr ? *cacheVersion : oo::PList())), ooliteVersion.value_or("(null)"));
            accept = NO;
        }

        const oo::PList* formatVersion = cache.find(kCacheKeyFormatVersion);
        if (accept && (formatVersion != nullptr ? static_cast<unsigned>(formatVersion->uint64Value()) : 0U) != kFormatVersionValue) {
            OO_LOG("dataCache.rebuild", "Data cache format ({}) is not supported format ({}), rebuilding cache.", oo::DescriptionOf(oo::ObjectFromPList(formatVersion != nullptr ? *formatVersion : oo::PList())), static_cast<std::size_t>(kFormatVersionValue));
            accept = NO;
        }

        if (accept) {
            const oo::PList* endianTagObject = cache.find(kCacheKeyEndianTag);
            const oo::Data* endianTag = endianTagObject != nullptr ? endianTagObject->getIf<oo::Data>() : nullptr;
            if (endianTag == nullptr || endianTag->length() != sizeof endianTagValue) {
                OO_LOG("dataCache.rebuild", "{}", "Data cache endian tag is invalid, rebuilding cache.");
                accept = NO;
            } else {
                memcpy(&endianTagValue, endianTag->bytes(), sizeof endianTagValue);
                if (endianTagValue != kEndianTagValue) {
                    OO_LOG("dataCache.rebuild", "{}", "Data cache endianness is inappropriate for this system, rebuilding cache.");
                    accept = NO;
                }
            }
        }

        if (accept) {
            // We have a cache, and it's the right format.
            [self buildCachesFromDictionary:cache.find(kCacheKeyCaches)];
        }

        oo::log::outdentIf("dataCache.found");
    } else {
        // No cache
        OO_LOG("dataCache.notFound", "{}", "No data cache found, starting from scratch.");
    }

    // If loading failed, or there was a version or endianness conflict
    if (!_caches.has_value())
        _caches.emplace();
    [self markClean];
}

- (void)write
{
    uint64_t endianTagValue = kEndianTagValue;

    if (!_caches.has_value())
        return;
    if (_scheduledWrite != nil)
        return;

#if PROFILE_WRITES
    OOProfilingStopwatch* stopwatch = [OOProfilingStopwatch stopwatch];
#endif

#if WRITE_ASYNC
    OO_LOG("dataCache.willWrite", "{}", "Scheduling data cache write.");
#else
    OO_LOG("dataCache.willWrite", "{}", "About to write cache.");
#endif

    const std::optional<std::string> ooliteVersion = OoliteInfoString("CFBundleVersion");

    oo::PList pListRep = [self dictionaryOfCaches];
    if (!ooliteVersion.has_value() || pListRep.isNull()) {
        OO_LOG("dataCache.cantWrite", "{}", "Failed to write data cache -- prerequisites not fulfilled. This is an internal error, please report it.");
        return;
    }

    oo::PList::Dict newCache;
    newCache.emplace(kCacheKeyVersion, oo::PList(*ooliteVersion));
    newCache.emplace(kCacheKeyFormatVersion, oo::PList::unsignedInteger(kFormatVersionValue)); // was +numberWithUnsignedInt:
    newCache.emplace(kCacheKeyEndianTag, oo::PList(oo::Data(&endianTagValue, sizeof endianTagValue)));
    newCache.emplace(kCacheKeyCaches, std::move(pListRep));

#if PROFILE_WRITES && !WRITE_ASYNC
    OOTimeDelta prepareT = [stopwatch reset];
#endif

#if WRITE_ASYNC
    _scheduledWrite = [[OOAsyncCacheWriter alloc] initWithCacheContents:oo::PList(std::move(newCache))];

#if PROFILE_WRITES
    OOTimeDelta endT = [stopwatch reset];
    OO_LOG("dataCache.profile", "Time to prepare cache data: {:g} seconds.", endT);
#endif

    [[OOAsyncWorkManager sharedAsyncWorkManager] addTask:_scheduledWrite
                                                priority:kOOAsyncPriorityLow];
#else
#if PROFILE_WRITES
    OO_LOG("dataCache.profile", "Time to prepare cache data: {:g} seconds.", prepareT);
#endif

    if ([self writeDict:oo::PList(std::move(newCache))]) {
        [self markClean];
        OO_LOG("dataCache.write.success", "{}", "Wrote data cache.");
    } else {
        OO_LOG("dataCache.write.failed", "{}", "Failed to write data cache.");
    }
#endif
}

- (void)clear
{
    _caches.reset();
}

- (BOOL)dirty
{
    return _dirty;
}

- (void)markClean
{
    _dirty = NO;
}

- (oo::PList)loadDict
{
    const std::optional<std::string> path = [self cachePathCreatingIfNecessary:NO];
    if (!path.has_value())
        return oo::PList();

    const auto data = oo::fs::readFile(oo::fs::pathFromUTF8(*path));
    if (!data.has_value())
        return oo::PList();

    auto contents = oo::parsePropertyListData(std::string_view(reinterpret_cast<const char*>(data->bytes()), data->length()));
    if (!contents.has_value()) {
        OO_LOG("dataCache.badData", "Could not read data cache: {}", contents.error().message);
        return oo::PList();
    }
    if (!contents->isDict())
        return oo::PList();

    return std::move(*contents);
}

- (BOOL)writeDict:(const oo::PList&)inDict
{
    const std::optional<std::string> path = [self cachePathCreatingIfNecessary:YES];
    if (!path.has_value())
        return NO;

#if PROFILE_WRITES
    OOProfilingStopwatch* stopwatch = [OOProfilingStopwatch stopwatch];
#endif

    const auto plist = oo::writeXMLPList(inDict);
    if (!plist.has_value()) {
        OO_LOG("dataCache.write.serialize.failed", "Could not convert data cache to property list data: {}", plist.error().message);
        return NO;
    }

#if PROFILE_WRITES
    OOTimeDelta serializeT = [stopwatch reset];
#endif

    BOOL result = oo::fs::writeFile(oo::fs::pathFromUTF8(*path), *plist, oo::fs::WriteMode::direct).has_value();

#if PROFILE_WRITES
    OOTimeDelta writeT = [stopwatch reset];

    OO_LOG("dataCache.profile", "Time to serialize cache: {:g} seconds. Time to write data: {:g} seconds.", serializeT, writeT);
#endif

#if WRITE_ASYNC
    DESTROY(_scheduledWrite);
#endif
    return result;
}

- (void)buildCachesFromDictionary:(const oo::PList*)inDict
{
    const oo::PList::Dict* caches = inDict != nullptr ? inDict->getIf<oo::PList::Dict>() : nullptr;
    if (caches == nullptr)
        return;

    _caches.emplace();

    for (const auto& [key, value] : *caches) {
        const oo::PList::Dict* cache = value.getIf<oo::PList::Dict>();
        if (cache != nullptr) {
            CacheEntries& entries = (*_caches)[key];
            for (const auto& [entryKey, entryValue] : *cache) {
                id object = oo::ObjectFromPList(entryValue);
                if (object != nil)
                    entries.emplace(entryKey, oo::ObjCRef<id>(object));
            }
        }
    }
}

// A deep copy of the caches as property-list data (was OODeepCopy of the dictionary of caches).
- (oo::PList)dictionaryOfCaches
{
    oo::PList::Dict result;
    for (const auto& [cacheKey, cache] : *_caches) {
        oo::PList::Dict entries;
        for (const auto& [key, object] : cache)
            entries.emplace(key, oo::PListFrom(object.get()));
        result.emplace(cacheKey, oo::PList(std::move(entries)));
    }
    return oo::PList(std::move(result));
}

- (BOOL)directoryExists:(const std::string&)inPath create:(BOOL)inCreate
{
    const oo::fs::Path path = oo::fs::pathFromUTF8(inPath);
    const oo::fs::FileType type = oo::fs::fileType(path);
    const bool exists = type != oo::fs::FileType::none;

    if (exists && type != oo::fs::FileType::directory) {
        OO_LOG("dataCache.write.buildPath.failed", "Expected {} to be a folder, but it is a file.", inPath);
        return NO;
    }
    if (!exists) {
        if (!inCreate)
            return NO;
        if (!oo::fs::createDirectories(path).has_value()) {
            OO_LOG("dataCache.write.buildPath.failed", "Could not create folder {}.", inPath);
            return NO;
        }
    }

    return YES;
}

#if OOLITE_MAC_OS_X

- (std::optional<std::string>)cachePathCreatingIfNecessary:(BOOL)create
{
    const std::optional<std::string> cachePath = [self cxx_cacheDirectoryPathCreatingIfNecessary:create];
    if (!cachePath.has_value())
        return std::nullopt;
    return oo::str::appendingPathComponent(*cachePath, "Data Cache.plist");
}

#else

- (std::optional<std::string>)cachePathCreatingIfNecessary:(BOOL)create
{
    const std::optional<std::string> cachePath = [self cxx_cacheDirectoryPathCreatingIfNecessary:create];
    if (!cachePath.has_value())
        return std::nullopt;
    return oo::str::appendingPathComponent(*cachePath, "Oolite-cache.plist");
}

#endif

@end

@implementation OOCacheManager (Singleton)

/*	Canonical singleton boilerplate.
        See Cocoa Fundamentals Guide: Creating a Singleton Instance.
        See also +sharedCache above.

        NOTE: assumes single-threaded access.
*/

+ (id)allocWithZone:(OOZone*)inZone
{
    if (sSingleton == nil) {
        sSingleton = [super allocWithZone:inZone];
        return sSingleton;
    }
    return nil;
}

- (id)copyWithZone:(OOZone*)inZone
{
    return self;
}

- (id)retain
{
    return self;
}

- (NSUInteger)retainCount
{
    return UINT_MAX;
}

- (void)release
{
}

- (id)autorelease
{
    return self;
}

@end

#if WRITE_ASYNC
@implementation OOAsyncCacheWriter

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
    if ([[OOCacheManager sharedCache] writeDict:_cacheContents]) {
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
#endif // WRITE_ASYNC
