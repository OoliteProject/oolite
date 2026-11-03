/*

OOCache.h
By Jens Ayton

An OOCache handles storage of a limited number of elements for quick reuse. It
may be used directly for in-memory cache, or indirectly through OOCacheManager
for on-disk cache.

Every OOCache has a 'prune threshold', which controls how many elements it
contains, and an 'auto-prune' flag, which determines how pruning is managed.

If auto-pruning is on, the cache will pruned to 80% of the prune threshold
whenever the prune threshold is exceeded. If auto-pruning is off, the cache
can be pruned to the prune threshold by explicitly calling -prune.

Keys are UTF-8 std::strings and values are oo::PList (proposed ADR-0055 item 2, bead
oo-qps.36): property-list data, or a PList::Object node (OOObjCPList.h) for a live
object such as a texture. An OOCache is essentially a string-keyed dictionary with a
prune limit. A null PList is "no value": it is never stored, and it is what a lookup of
an absent key returns.


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

enum {
    kOOCacheMinimumPruneThreshold = 25U,
    kOOCacheDefaultPruneThreshold = 200U,
    kOOCacheNoPrune = 0xFFFFFFFFU
};

@interface OOCache : OOObject {
@private
    struct OOCacheImpl* cache;
    unsigned pruneThreshold;
    BOOL autoPrune;
    BOOL dirty;
}

- (id)init;
// An array of {key = string; value = plist;} entries, oldest first (a null PList: empty); nil for
// anything else. -cxx_pListRepresentation is the same form, null for an empty cache.
- (id)cxx_initWithPList:(const oo::PList&)pList;
- (oo::PList)cxx_pListRepresentation;

- (oo::PList)cxx_pListForKey:(const std::string&)key; // null PList: absent
- (void)cxx_setPList:(const oo::PList&)value forKey:(const std::string&)key; // a null value is not stored
- (void)cxx_removePListForKey:(const std::string&)key;

- (void)setPruneThreshold:(unsigned)threshold;
- (unsigned)pruneThreshold;

- (void)setAutoPrune:(BOOL)flag;
- (BOOL)autoPrune;

- (void)prune;

- (BOOL)dirty;
- (void)markClean;

- (std::optional<std::string>)cxx_name; // nullopt: unnamed (bead oo-3rb.289.9)
- (void)cxx_setName:(const std::optional<std::string>&)name;

- (std::vector<oo::PList>)pListsByAge; // the values, youngest first; empty for an empty cache

@end
