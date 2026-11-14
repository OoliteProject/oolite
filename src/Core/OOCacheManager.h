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

#include "oofnd/StdLib.hpp"
#include "oofnd/objc/OOObjCRef.h"

/*	Foundation sweep (proposed ADR-0043, bead oo-19g0): cache names and keys are UTF-8
        std::strings; cached values stay Objective-C objects (property-list data), held by
        oo::ObjCRef. The cache directory is std::nullopt where it was nil.
*/
@interface OOCacheManager : OOObject {
@private
    // cache name -> key -> cached object; std::nullopt before loading, as nil was.
    std::optional<std::map<std::string, std::map<std::string, oo::ObjCRef<id>, std::less<>>, std::less<>>> _caches;
    id _scheduledWrite;
    BOOL _permitWrites;
    BOOL _dirty;
}

+ (OOCacheManager*)sharedCache;

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

/*	TRANSITIONAL (proposed ADR-0043, "Transitional bridges"): the Foundation-typed API this header
        declared before bead oo-19g0, forwarding to the cxx_ methods above, so unmigrated callers compile
        unchanged. Callers move to the cxx_ API in their own sweep beads; the bridge goes in its own bead.
*/
#import "OOCacheManager+FoundationBridge.h"
