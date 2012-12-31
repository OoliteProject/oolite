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

While OOCacheManager-managed caches must have string keys and property list
values, OOCaches used directly may have any keys allowable for a mutable
dictionary (that is, keys should conform to <NSCopying> and values may be
arbitrary objects) -- an 'unmanaged' cache is essentially a mutable dictionary
with a prune limit. (Project: with the addition of a -keyEnumerator method and
sutiable NSEnumerator subclass, and a -count method, it could be turned into a
subclass of NSMutableDictionary.)


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

#import <Foundation/Foundation.h>


enum
{
	kOOCacheMinimumPruneThreshold			= 25U,
	kOOCacheDefaultPruneThreshold			= 200U,
	kOOCacheNoPrune							= 0xFFFFFFFFU
};


@interface OOCache: NSObject
{
@private
	struct OOCacheImpl		*cache;
	unsigned				pruneThreshold;
	BOOL					autoPrune;
	BOOL					dirty;
}

- (id)init;
- (id)initWithPList:(id)pList;
- (id)pListRepresentation;

- (id)objectForKey:(id)key;
- (void)setObject:(id)value forKey:(id)key;
- (void)removeObjectForKey:(id)key;

- (void)setPruneThreshold:(unsigned)threshold;
- (unsigned)pruneThreshold;

- (void)setAutoPrune:(BOOL)flag;
- (BOOL)autoPrune;

- (void)prune;

- (BOOL)dirty;
- (void)markClean;

- (NSString *)name;
- (void)setName:(NSString *)name;

- (NSArray *) objectsByAge;

@end
