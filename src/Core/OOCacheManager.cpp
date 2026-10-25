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

#include "OOCacheManager.h"
#include "OOJavaScriptEngine.h"

#include "oofnd/FileSystem.hpp"
#include "oofnd/PListParsing.hpp"
#include "oofnd/PListWriting.hpp"
#include "oofnd/String.hpp"
#include "oofnd/ResourcePaths.hpp"

/*
	Phase 1 sweep js-retarget (bead oo-vz2), exemplar OOJSVector.mm: this file has no
	directly-spelled scripting-engine call sites to move onto the ooscript facade (JSEngine.hpp)
	-- it only imports OOJavaScriptEngine.h for shared logging/plist helpers and never touches
	the engine's context, object or value types directly. The only change this bead makes is
	compiling it as Objective-C++ (.m -> .mm, ADR-0001, same as every other file in the sweep)
	and fixing constructs that are diagnosed defects only once compiled that way: an assignment
	inside an `if` condition, and file-scope statics that must move into an anonymous namespace.

	Foundation sweep (proposed ADR-0043, bead oo-19g0): the caches are std::maps of retained
	objects; the cache file is read and written as an oo::PList, in XML (proposed ADR-0027 item 3:
	oofnd does not parse GNUstep's binary format, and an unreadable cache is rebuilt).
*/


#define WRITE_ASYNC				1
#define PROFILE_WRITES			0


#if WRITE_ASYNC
#include "OOAsyncWorkManager.h"
#endif
#if PROFILE_WRITES
#include "OOProfilingStopwatch.h"
#endif
#include "oofnd/objc/OOAssert.h"


namespace {
constexpr const char *kCacheKeyVersion						= "version";
constexpr const char *kCacheKeyEndianTag					= "endian tag";
constexpr const char *kCacheKeyFormatVersion				= "format version";
constexpr const char *kCacheKeyCaches						= "caches";
} // namespace


enum
{
	kEndianTagValue			= 0x0123456789ABCDEFULL,
	kFormatVersionValue		= 219
};


namespace {
OOCacheManager *sSingleton = nullptr;	// +1, never released (the retained singleton)

using CacheEntries = std::map<std::string, oo::PList, std::less<>>;

// The cache named <name>, or nullptr (no such cache, or no caches at all), as -objectForKey: on
// the dictionary of caches (or on nil) answered.
CacheEntries *FindCache(std::optional<std::map<std::string, CacheEntries, std::less<>>> &caches, const std::string &name)
{
	if (!caches.has_value())  return nullptr;
	const auto it = caches->find(name);
	return it != caches->end() ? &it->second : nullptr;
}
} // namespace


namespace {

// Info-gnustep.plist string (CFBundleVersion / CFBundleName as the Override category used to expose).
std::optional<std::string> OoliteInfoString(std::string_view key)
{
	const oo::fs::Path plistPath = oo::ResourcePaths::current().builtInResourcesDirectory() / "Info-gnustep.plist";
	oo::PList info;
	if (const oo::fs::Result<oo::Data> bytes = oo::fs::readFile(plistPath); bytes && !bytes->empty())
	{
		if (oo::Expected<oo::PList, oo::PListError> parsed = oo::parsePropertyList(bytes->stringView());
		    parsed && parsed->isDict())
			info = std::move(*parsed);
	}
	if (const oo::PList *v = info.find(key); v != nullptr && v->isString())
		return *v->getIf<std::string>();
	return std::nullopt;
}

}  // namespace

void OOCacheManager::init()
{
	_permitWrites = YES;
	loadCache();
}


OOCacheManager::~OOCacheManager()
{
	clear();
}


// oo::DescriptionOf wraps this as "<OOCacheManager 0x...>{dirty=...}", which is what this
// class's own -description printed. (It reads _dirty, which -dirty returned.)
std::optional<std::string> OOCacheManager::descriptionComponents() const
{
	return oo::str::format("dirty=%s", _dirty ? "yes" : "no");
}


OOCacheManager *OOCacheManager::sharedCache()
{
	// NOTE: assumes single-threaded access.
	if (sSingleton == nullptr)
	{
		// Recorded before -init's work ran, as +allocWithZone: recorded it (amendment oo-z1s4 item 2).
		sSingleton = oo::makeRef<OOCacheManager>().leakRef();
		sSingleton->init();
	}
	
	return sSingleton;
}


oo::PList OOCacheManager::pListForKey(const std::string &inKey, const std::string &inCacheKey)
{
	oo::PList				result;
	
	CacheEntries *cache = FindCache(_caches, inCacheKey);
	if (cache != nullptr)
	{
		const auto entry = cache->find(inKey);
		if (entry != cache->end())  result = entry->second;
		if (!result.isNull())
		{
#if OO_DEBUG
			OO_LOG("dataCache.retrieve.success", "Retrieved \"{}\" cache object {}.", inCacheKey, inKey);
#endif
		}
		else
		{
#if OO_DEBUG
			OO_LOG("dataCache.retrieve.failed", "Failed to retrieve \"{}\" cache object {} -- no such entry.", inCacheKey, inKey);
#endif
		}
	}
	else
	{
#if OO_DEBUG
		OO_LOG("dataCache.retrieve.failed", "Failed to retrieve \"{}\" cache object {} -- no such cache.", inCacheKey, inKey);
#endif
	}
	
	return result;
}


void OOCacheManager::setPList(const oo::PList &inValue, const std::string &inKey, const std::string &inCacheKey)
{
	OOCParameterAssert(!inValue.isNull());

	if (EXPECT_NOT(!_caches.has_value()))  return;
	
	// A missing cache is created, empty, as before.
	(*_caches)[inCacheKey][inKey] = inValue;
	_dirty = YES;
#if OO_DEBUG
	OO_LOG("dataCache.set.success", "Updated entry {} in cache \"{}\".", inKey, inCacheKey);
#endif
}


void OOCacheManager::removeObjectForKey(const std::string &inKey, const std::string &inCacheKey)
{
	CacheEntries *cache = FindCache(_caches, inCacheKey);
	if (cache != nullptr)
	{
		if (cache->erase(inKey) != 0)
		{
			_dirty = YES;
#if OO_DEBUG
			OO_LOG("dataCache.remove.success", "Removed entry keyed {} from cache \"{}\".", inKey, inCacheKey);
#endif
		}
		else
		{
#if OO_DEBUG
			OO_LOG("dataCache.remove.success", "No need to remove non-existent entry keyed {} from cache \"{}\".", inKey, inCacheKey);
#endif
		}
	}
	else
	{
#if OO_DEBUG
		OO_LOG("dataCache.remove.success", "No need to remove entry keyed {} from non-existent cache \"{}\".", inKey, inCacheKey);
#endif
	}
}


void OOCacheManager::clearCache(const std::string &inCacheKey)
{
	if (FindCache(_caches, inCacheKey) != nullptr)
	{
		_caches->erase(inCacheKey);
		_dirty = YES;
#if OO_DEBUG
		OO_LOG("dataCache.clear.success", "Cleared cache \"{}\".", inCacheKey);
#endif
	}
	else
	{
#if OO_DEBUG
		OO_LOG("dataCache.clear.success", "No need to clear non-existent cache \"{}\".", inCacheKey);
#endif
	}
}


void OOCacheManager::clearAllCaches()
{
	clear();
	_caches.emplace();
	_dirty = YES;
}


void OOCacheManager::reloadAllCaches()
{
	clear();
	loadCache();
}


void OOCacheManager::flush()
{
	if (_permitWrites && dirty() && _scheduledWrite == nullptr)
	{
		write();
		markClean();
	}
}


void OOCacheManager::finishOngoingFlush()
{
#if WRITE_ASYNC
	OOAsyncWorkManager::sharedAsyncWorkManager()->waitForTaskToComplete(_scheduledWrite.get());
#endif
}


void OOCacheManager::setAllowCacheWrites(bool flag)
{
	_permitWrites = (flag != NO);
}


std::optional<std::string> OOCacheManager::cacheDirectoryPathCreatingIfNecessary(bool create)
{
	/*	Construct the path to the directory for cache files, which is:
			~/Library/Caches/org.aegidian.oolite/
			or
			~/GNUStep/Library/Caches/org.aegidian.oolite/
		In addition to generally being the right place to put caches,
		~/Library/Caches has the particular advantage of not being indexed by
		Spotlight or backed up by Time Machine.
	*/
	std::string cachePath = oo::fs::utf8String(oo::ResourcePaths::current().cachesDirectory());
	if (!directoryExists(cachePath, create)) return std::nullopt;

#if !OOLITE_MAC_OS_X
	// the old cache file on GNUstep was one level up, so remove it if it exists
	(void)oo::fs::removeItem(oo::fs::pathFromUTF8(oo::str::appendingPathComponent(cachePath, "Oolite-cache.plist")));
#endif

	cachePath = oo::str::appendingPathComponent(cachePath, "org.aegidian.oolite");
	if (!directoryExists(cachePath, create)) return std::nullopt;
	return cachePath;
}


void OOCacheManager::loadCache()
{
	BOOL					accept = YES;
	uint64_t				endianTagValue = 0;
	
	const std::optional<std::string> ooliteVersion = OoliteInfoString("CFBundleVersion");
	
	clear();
	
	const oo::PList cache = loadDict();
	if (!cache.isNull())
	{
		// We have a cache
		OO_LOG("dataCache.found", "{}", "Found data cache.");
		oo::log::indentIf("dataCache.found");
		
		const oo::PList *cacheVersion = cache.find(kCacheKeyVersion);
		const std::string *cacheVersionString = cacheVersion != nullptr ? cacheVersion->getIf<std::string>() : nullptr;
		// -isEqual: between the two; a missing version on either side never matched.
		if (cacheVersionString == nullptr || !ooliteVersion.has_value() || *cacheVersionString != *ooliteVersion)
		{
			OO_LOG("dataCache.rebuild", "Data cache version ({}) does not match Oolite version ({}), rebuilding cache.", oo::DescriptionOf(cacheVersion != nullptr ? *cacheVersion : oo::PList()), ooliteVersion.value_or("(null)"));
			accept = NO;
		}
		
		const oo::PList *formatVersion = cache.find(kCacheKeyFormatVersion);
		if (accept && (formatVersion != nullptr ? static_cast<unsigned>(formatVersion->uint64Value()) : 0U) != kFormatVersionValue)
		{
			OO_LOG("dataCache.rebuild", "Data cache format ({}) is not supported format ({}), rebuilding cache.", oo::DescriptionOf(formatVersion != nullptr ? *formatVersion : oo::PList()), static_cast<std::size_t>(kFormatVersionValue));
			accept = NO;
		}
		
		if (accept)
		{
			const oo::PList *endianTagObject = cache.find(kCacheKeyEndianTag);
			const oo::Data *endianTag = endianTagObject != nullptr ? endianTagObject->getIf<oo::Data>() : nullptr;
			if (endianTag == nullptr || endianTag->length() != sizeof endianTagValue)
			{
				OO_LOG("dataCache.rebuild", "{}", "Data cache endian tag is invalid, rebuilding cache.");
				accept = NO;
			}
			else
			{
				memcpy(&endianTagValue, endianTag->bytes(), sizeof endianTagValue);
				if (endianTagValue != kEndianTagValue)
				{
					OO_LOG("dataCache.rebuild", "{}", "Data cache endianness is inappropriate for this system, rebuilding cache.");
					accept = NO;
				}
			}
		}
		
		if (accept)
		{
			// We have a cache, and it's the right format.
			buildCachesFromDictionary(cache.find(kCacheKeyCaches));
		}
		
		oo::log::outdentIf("dataCache.found");
	}
	else
	{
		// No cache
		OO_LOG("dataCache.notFound", "{}", "No data cache found, starting from scratch.");
	}
	
	// If loading failed, or there was a version or endianness conflict
	if (!_caches.has_value())  _caches.emplace();
	markClean();
}


void OOCacheManager::write()
{
	uint64_t				endianTagValue = kEndianTagValue;
	
	if (!_caches.has_value()) return;
	if (_scheduledWrite != nullptr)  return;
	
#if PROFILE_WRITES
	oo::Ref<OOProfilingStopwatch> stopwatch = OOProfilingStopwatch::stopwatch();
#endif
	
#if WRITE_ASYNC
	OO_LOG("dataCache.willWrite", "{}", "Scheduling data cache write.");
#else
	OO_LOG("dataCache.willWrite", "{}", "About to write cache.");
#endif
	
	const std::optional<std::string> ooliteVersion = OoliteInfoString("CFBundleVersion");
	
	oo::PList pListRep = dictionaryOfCaches();
	if (!ooliteVersion.has_value() || pListRep.isNull())
	{
		OO_LOG("dataCache.cantWrite", "{}", "Failed to write data cache -- prerequisites not fulfilled. This is an internal error, please report it.");
		return;
	}
	
	oo::PList::Dict newCache;
	newCache.emplace(kCacheKeyVersion, oo::PList(*ooliteVersion));
	newCache.emplace(kCacheKeyFormatVersion, oo::PList::unsignedInteger(kFormatVersionValue));	// was +numberWithUnsignedInt:
	newCache.emplace(kCacheKeyEndianTag, oo::PList(oo::Data(&endianTagValue, sizeof endianTagValue)));
	newCache.emplace(kCacheKeyCaches, std::move(pListRep));
	
#if PROFILE_WRITES && !WRITE_ASYNC
	OOTimeDelta prepareT = stopwatch->reset();
#endif
	
#if WRITE_ASYNC
	_scheduledWrite = OOAsyncCacheWriter::writerWithCacheContents(oo::PList(std::move(newCache)));
	
#if PROFILE_WRITES
	OOTimeDelta endT = stopwatch->reset();
	OO_LOG("dataCache.profile", "Time to prepare cache data: {:g} seconds.", endT);
#endif
	
	OOAsyncWorkManager::sharedAsyncWorkManager()->addTask(_scheduledWrite.get(), kOOAsyncPriorityLow);
#else
#if PROFILE_WRITES
	OO_LOG("dataCache.profile", "Time to prepare cache data: {:g} seconds.", prepareT);
#endif
	
	if (writeDict(oo::PList(std::move(newCache))))
	{
		markClean();
		OO_LOG("dataCache.write.success", "{}", "Wrote data cache.");
	}
	else
	{
		OO_LOG("dataCache.write.failed", "{}", "Failed to write data cache.");
	}
#endif
}


void OOCacheManager::clear()
{
	_caches.reset();
}


bool OOCacheManager::dirty()
{
	return _dirty;
}


void OOCacheManager::markClean()
{
	_dirty = NO;
}


oo::PList OOCacheManager::loadDict()
{
	const std::optional<std::string> path = cachePathCreatingIfNecessary(NO);
	if (!path.has_value()) return oo::PList();
	
	const auto data = oo::fs::readFile(oo::fs::pathFromUTF8(*path));
	if (!data.has_value())  return oo::PList();
	
	auto contents = oo::parsePropertyListData(std::string_view(reinterpret_cast<const char *>(data->bytes()), data->length()));
	if (!contents.has_value())
	{
		OO_LOG("dataCache.badData", "Could not read data cache: {}", contents.error().message);
		return oo::PList();
	}
	if (!contents->isDict())  return oo::PList();
		
	return std::move(*contents);
}


bool OOCacheManager::writeDict(const oo::PList &inDict)
{
	const std::optional<std::string> path = cachePathCreatingIfNecessary(YES);
	if (!path.has_value()) return NO;
	
#if PROFILE_WRITES
	oo::Ref<OOProfilingStopwatch> stopwatch = OOProfilingStopwatch::stopwatch();
#endif
	
	const auto plist = oo::writeXMLPList(inDict);
	if (!plist.has_value())
	{
		OO_LOG("dataCache.write.serialize.failed", "Could not convert data cache to property list data: {}", plist.error().message);
		return NO;
	}
	
#if PROFILE_WRITES
	OOTimeDelta serializeT = stopwatch->reset();
#endif
	
	BOOL result = oo::fs::writeFile(oo::fs::pathFromUTF8(*path), *plist, oo::fs::WriteMode::direct).has_value();
	
#if PROFILE_WRITES
	OOTimeDelta writeT = stopwatch->reset();
	
	OO_LOG("dataCache.profile", "Time to serialize cache: {:g} seconds. Time to write data: {:g} seconds.", serializeT, writeT);
#endif
	
#if WRITE_ASYNC
	_scheduledWrite = nullptr;
#endif
	return result;
}


void OOCacheManager::buildCachesFromDictionary(const oo::PList *inDict)
{
	const oo::PList::Dict *caches = inDict != nullptr ? inDict->getIf<oo::PList::Dict>() : nullptr;
	if (caches == nullptr) return;
	
	_caches.emplace();
	
	for (const auto &[key, value] : *caches)
	{
		const oo::PList::Dict *cache = value.getIf<oo::PList::Dict>();
		if (cache != nullptr)
		{
			CacheEntries &entries = (*_caches)[key];
			for (const auto &[entryKey, entryValue] : *cache)
			{
				if (!entryValue.isNull())  entries.emplace(entryKey, entryValue);
			}
		}
	}
}


// A deep copy of the caches as property-list data (was a deep-copy of the dictionary of caches).
oo::PList OOCacheManager::dictionaryOfCaches()
{
	oo::PList::Dict result;
	for (const auto &[cacheKey, cache] : *_caches)
	{
		oo::PList::Dict entries;
		for (const auto &[key, value] : cache)  entries.emplace(key, value);
		result.emplace(cacheKey, oo::PList(std::move(entries)));
	}
	return oo::PList(std::move(result));
}


bool OOCacheManager::directoryExists(const std::string &inPath, bool inCreate)
{
	const oo::fs::Path path = oo::fs::pathFromUTF8(inPath);
	const oo::fs::FileType type = oo::fs::fileType(path);
	const bool exists = type != oo::fs::FileType::none;
	
	if (exists && type != oo::fs::FileType::directory)
	{
		OO_LOG("dataCache.write.buildPath.failed", "Expected {} to be a folder, but it is a file.", inPath);
		return NO;
	}
	if (!exists)
	{
		if (!inCreate) return NO;
		if (!oo::fs::createDirectories(path).has_value())
		{
			OO_LOG("dataCache.write.buildPath.failed", "Could not create folder {}.", inPath);
			return NO;
		}
	}
	
	return YES;
}


#if OOLITE_MAC_OS_X

std::optional<std::string> OOCacheManager::cachePathCreatingIfNecessary(bool create)
{
	const std::optional<std::string> cachePath = cacheDirectoryPathCreatingIfNecessary(create);
	if (!cachePath.has_value())  return std::nullopt;
	return oo::str::appendingPathComponent(*cachePath, "Data Cache.plist");
}

#else

std::optional<std::string> OOCacheManager::cachePathCreatingIfNecessary(bool create)
{
	const std::optional<std::string> cachePath = cacheDirectoryPathCreatingIfNecessary(create);
	if (!cachePath.has_value())  return std::nullopt;
	return oo::str::appendingPathComponent(*cachePath, "Oolite-cache.plist");
}

#endif


oo::Ref<OOAsyncCacheWriter> OOAsyncCacheWriter::writerWithCacheContents(const oo::PList &cacheContents)
{
	if (cacheContents.isNull())  return nullptr;
	return oo::adopt(new OOAsyncCacheWriter(cacheContents));
}


void OOAsyncCacheWriter::performAsyncTask()
{
	if (OOCacheManager::sharedCache()->writeDict(_cacheContents))
	{
		OO_LOG("dataCache.write.success", "{}", "Wrote data cache.");
	}
	else
	{
		OO_LOG("dataCache.write.failed", "{}", "Failed to write data cache.");
	}
	_cacheContents = oo::PList();
}


void OOAsyncCacheWriter::completeAsyncTask()
{
	// Don't need to do anything, but this needs to be here so we can wait on it.
}
