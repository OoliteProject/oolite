/*

OOCacheManager.h
By Jens Ayton

Singleton class responsible for handling Olite's data cache.
The cache manager stores arbitrary property lists in separate namespaces
(referred to simply as caches). The cache is emptied if it was created with a
different verison of Oolite, or if it was created on a system with a different
byte sex.

Oolite
Copyright (C) 2004-2007 Giles C Williams and contributors

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

#import "OOCocoa.h"


enum
{
	kOOCacheMinimumPruneThreshold			= 25U,
	kOOCacheDefaultPruneThreshold			= 125U,
	kOOCacheNoPrune							= -1U
};


@interface OOCacheManager: NSObject
{
@private
	NSMutableDictionary		*caches;
}

+ (id)sharedCache;

- (id)objectForKey:(NSString *)inKey inCache:(NSString *)inCacheKey;
- (void)setObject:(id)inElement forKey:(NSString *)inKey inCache:(NSString *)inCacheKey;
- (void)removeObjectForKey:(NSString *)inKey inCache:(NSString *)inCacheKey;
- (void)clearCache:(NSString *)inCacheKey;
- (void)clearAllCaches;

/*	Prune thresholds:
	when the number of objects in a cache reaches the prune threshold, old
	objects are removed until the object count is no more than 80% of the
	prune threshold.
*/
- (void)setPruneThreshold:(unsigned)inThreshold forCache:(NSString *)inCacheKey;
- (unsigned)pruneThresholdForCache:(NSString *)inCacheKey;

- (void)flush;

@end
