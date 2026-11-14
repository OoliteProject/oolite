/*

OOCacheManager.h
By Jens Ayton

Singleton class responsible for handling Oolite's data cache.
The cache manager stores arbitrary property lists in separate namespaces
(referred to simply as caches). The cache is emptied if it was created with a
different verison of Oolite, or if it was created on a system with a different
byte sex.

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

#import "OOFoundation.h"

#include "oofnd/PList.hpp"
#include "oofnd/Ref.hpp"
#include "oofnd/StdLib.hpp"

/*	Foundation sweep (proposed ADR-0043, bead oo-19g0): cache names and keys are UTF-8
        std::strings. The cache directory is std::nullopt where it was nil. Every cached value is
        property-list data, held as an oo::PList (proposed ADR-0055 item 2, bead oo-qps.36) and
        written to the cache file as it is; a null PList is "no value".
*/
/*	C++20 since bead oo-rmd7 (proposed ADR-0056; a singleton, amendments oo-r7m0 and oo-z1s4).
        OOCacheManager+ObjCBridge.h, imported at the end of this header, keeps the Objective-C
        OOCacheManager as a facade over this class for the callers that are not converted yet, and
        holds the write task (OOAsyncCacheWriter), which stays Objective-C while OOAsyncWorkTask is an
        Objective-C protocol (amendment oo-rmd7). The bridge's deletion bead moves the class out of
        namespace cxx.
*/
namespace cxx {

class OOCacheManager : public oo::RefCounted {
public:
    static OOCacheManager* sharedCache(); // the one instance, made on first use and never released
    ~OOCacheManager() override;

    oo::PList pListForKey(const std::string& key, const std::string& cache); // null PList: absent
    void setPList(const oo::PList& value, const std::string& key, const std::string& cache); // value: not null

    void removeObjectForKey(const std::string& inKey, const std::string& inCacheKey);
    void clearCache(const std::string& inCacheKey);
    void clearAllCaches();
    void reloadAllCaches();

    void setAllowCacheWrites(bool flag);

    std::optional<std::string> cacheDirectoryPathCreatingIfNecessary(bool create);

    void flush();
    void finishOngoingFlush(); // Wait for flush to complete. Does nothing if async flushing is disabled.

    // What "%@" printed between the braces of <OOCacheManager 0x...>{...} (OODescription.h).
    std::optional<std::string> descriptionComponents() const;

    // Private before the conversion; public because the write task (OOAsyncCacheWriter, in
    // OOCacheManager+ObjCBridge.mm) calls it on a worker thread.
    bool writeDict(const oo::PList& inDict);

private:
    void init(); // -init's body, run after the instance is recorded as the singleton

    void loadCache();
    void write();
    void clear();
    bool dirty();
    void markClean();

    oo::PList loadDict(); // null: no cache

    void buildCachesFromDictionary(const oo::PList* inDict); // nullptr: none
    oo::PList dictionaryOfCaches();

    bool directoryExists(const std::string& inPath, bool inCreate);

    std::optional<std::string> cachePathCreatingIfNecessary(bool create);

    // cache name -> key -> cached value; std::nullopt before loading, as nil was.
    std::optional<std::map<std::string, std::map<std::string, oo::PList, std::less<>>, std::less<>>> _caches = { };
    id _scheduledWrite = { }; // the pending OOAsyncCacheWriter, retained
    bool _permitWrites = { };
    bool _dirty = { };
};

} // namespace cxx

// The Objective-C facade (and the write task) for code not converted yet. Deleted, with namespace
// cxx above, by the bridge's deletion bead.
#import "OOCacheManager+ObjCBridge.h"
