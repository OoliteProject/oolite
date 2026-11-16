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
#import "oofnd/objc/OOObject.h"

#include "oofnd/PList.hpp"
#include "oofnd/StdLib.hpp"

/*	Foundation sweep (proposed ADR-0043, bead oo-19g0): cache names and keys are UTF-8
        std::strings. The cache directory is std::nullopt where it was nil. Every cached value is
        property-list data, held as an oo::PList (proposed ADR-0055 item 2, bead oo-qps.36) and
        written to the cache file as it is; a null PList is "no value".
*/
@interface OOCacheManager : OOObject {
@private
    // cache name -> key -> cached value; std::nullopt before loading, as nil was.
    std::optional<std::map<std::string, std::map<std::string, oo::PList, std::less<>>, std::less<>>> _caches;
    id _scheduledWrite;
    BOOL _permitWrites;
    BOOL _dirty;
}

+ (OOCacheManager*)sharedCache;

- (oo::PList)cxx_pListForKey:(const std::string&)key inCache:(const std::string&)cache; // null PList: absent
- (void)cxx_setPList:(const oo::PList&)value forKey:(const std::string&)key inCache:(const std::string&)cache; // value: not null

// The id forms of the two above (oo::ObjectFromPList / oo::PListFrom of the value), until
// oo-qps.72 deletes them once their callers have moved.
- (id)cxx_objectForKey:(const std::string&)inKey inCache:(const std::string&)inCacheKey;
- (void)cxx_setObject:(id)inElement forKey:(const std::string&)inKey inCache:(const std::string&)inCacheKey;
- (void)cxx_removeObjectForKey:(const std::string&)inKey inCache:(const std::string&)inCacheKey;
- (void)cxx_clearCache:(const std::string&)inCacheKey;
- (void)clearAllCaches;
- (void)reloadAllCaches;

- (void)setAllowCacheWrites:(BOOL)flag;

- (std::optional<std::string>)cxx_cacheDirectoryPathCreatingIfNecessary:(BOOL)create;

- (void)flush;
- (void)finishOngoingFlush; // Wait for flush to complete. Does nothing if async flushing is disabled.

@end
