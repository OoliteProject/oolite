/*

OOCacheManager+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, bead oo-rmd7): the Objective-C OOCacheManager, a facade over the
C++ cxx::OOCacheManager (OOCacheManager.h), for callers that are not converted yet. Its interface
is the one OOCacheManager.h declared before the conversion, copied exactly (same selectors, same
types), so those callers, and the categories other files add to it (OOMesh.mm's OOMesh and Octree
caches), compile and behave unchanged; each method forwards to its C++ member.
Imported as the last line of OOCacheManager.h; do not import it directly.

        a caller that is                       holds / passes                  crosses with
        -------------------------------------  ------------------------------  ----------------------------
        still Objective-C                      [OOCacheManager sharedCache]    nothing
        converted (C++)                        cxx::OOCacheManager::sharedCache()   nothing

The manager is a singleton: +sharedCache answers one facade for the life of the process, as it
answered one object before (proposed ADR-0056 amendment oo-r7m0, item 5).

OOAsyncCacheWriter, the task that writes the cache on a worker thread, is also here: it adopts
the Objective-C protocol OOAsyncWorkTask (in its @implementation, so this header does not need
OOAsyncWorkManager.h), and becomes a C++ task when that protocol becomes a C++ interface
(proposed ADR-0056 amendment oo-rmd7). Never add to this file; converted code does not message
the facade. Deleted by its deletion bead once no file outside OOCacheManager.* names the
Objective-C class.

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

#ifndef OOCACHEMANAGER_OBJCBRIDGE_H
#define OOCACHEMANAGER_OBJCBRIDGE_H

#import "OOFoundation.h"
#import "oofnd/objc/OOObject.h"

@interface OOCacheManager : OOObject {
@private
    oo::Ref<cxx::OOCacheManager> _cxxCache;
}

+ (OOCacheManager*)sharedCache;

- (oo::PList)cxx_pListForKey:(const std::string&)key inCache:(const std::string&)cache; // null PList: absent
- (void)cxx_setPList:(const oo::PList&)value forKey:(const std::string&)key inCache:(const std::string&)cache; // value: not null

- (void)cxx_removeObjectForKey:(const std::string&)inKey inCache:(const std::string&)inCacheKey;
- (void)cxx_clearCache:(const std::string&)inCacheKey;
- (void)clearAllCaches;
- (void)reloadAllCaches;

- (void)setAllowCacheWrites:(BOOL)flag;

- (std::optional<std::string>)cxx_cacheDirectoryPathCreatingIfNecessary:(BOOL)create;

- (void)flush;
- (void)finishOngoingFlush; // Wait for flush to complete. Does nothing if async flushing is disabled.

@end

// The write task that cxx::OOCacheManager::write() schedules (nil for a null contents).
@interface OOAsyncCacheWriter : OOObject

- (id)initWithCacheContents:(const oo::PList&)cacheContents;

@end

namespace oo {

// The manager's Objective-C facade: its live one, else a new one; autoreleased. nil for null.
OOCacheManager* ToObjC(cxx::OOCacheManager* cache);
// The C++ manager behind a facade, borrowed (the facade retains it); null for nil.
cxx::OOCacheManager* ToCxx(OOCacheManager* cache);

} // namespace oo

#endif // OOCACHEMANAGER_OBJCBRIDGE_H
