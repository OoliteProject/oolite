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

#pragma once

#include "OOFoundation.h"
#include "oofnd/PList.hpp"
#include "oofnd/Ref.hpp"
#include "oofnd/StdLib.hpp"

enum {
    kOOCacheMinimumPruneThreshold = 25U,
    kOOCacheDefaultPruneThreshold = 200U,
    kOOCacheNoPrune = 0xFFFFFFFFU
};

/*	C++20 since bead oo-rdfh (proposed ADR-0056, the OOColor house style). Its two callers
        (OOTexture, OOEncodingConverter) were adapted in the same bead, so there is no Objective-C
        facade and the class is global.
*/
class OOCache : public oo::RefCounted {
public:
    // [[OOCache alloc] init] is cacheWithPList(oo::PList()), as -init was.
    // An array of {key = string; value = plist;} entries, oldest first (a null PList: empty); null for
    // anything else. pListRepresentation() is the same form, null for an empty cache.
    static oo::Ref<OOCache> cacheWithPList(const oo::PList& pList);
    oo::PList pListRepresentation();

    ~OOCache() override;

    oo::PList pListForKey(const std::string& key); // null PList: absent
    void setPList(const oo::PList& value, const std::string& key); // a null value is not stored
    void removePListForKey(const std::string& key);

    void setPruneThreshold(unsigned threshold);
    unsigned pruneThreshold();

    void setAutoPrune(bool flag);
    bool autoPrune();

    void prune();

    bool dirty();
    void markClean();

    std::optional<std::string> name(); // nullopt: unnamed (bead oo-3rb.289.9)
    void setName(const std::optional<std::string>& name);

    std::vector<oo::PList> pListsByAge(); // the values, youngest first; empty for an empty cache

    // What "%@" printed between the braces of <OOCache 0x...>{...} (OODescription.h).
    std::optional<std::string> descriptionComponents() const;

#if DEBUG_GRAPHVIZ
    std::optional<std::string> generateGraphVizBodyWithRootNamed(const std::string& rootName);
    std::string generateGraphViz();
    void writeGraphVizToPath(const std::string& path);
#endif

private:
    bool initWithPList(const oo::PList& pList); // false where -cxx_initWithPList: returned nil

    void loadFromArray(const oo::PList& inArray);

#if DEBUG_GRAPHVIZ
    void appendNodesFromSubTree(struct OOCacheNode* subTree, std::string& ioString);
#endif

    struct OOCacheImpl* cache = { };
    unsigned _pruneThreshold = { }; // (the ivar was pruneThreshold, now the getter's name)
    bool _autoPrune = { }; // (autoPrune, likewise)
    bool _dirty = { }; // (dirty, likewise)
};
