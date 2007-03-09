/*

OOCache.h
By Jens Ayton

OOCache is an implementation detail of OOCacheManager. Don't use it directly.

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

#import <Foundation/Foundation.h>


@interface OOCache: NSObject
{
@private
	struct OOCacheImpl		*cache;
	unsigned				pruneThreshold;
	BOOL					dirty;
}

- (id)init;
- (id)initWithPList:(id)pList;
- (id)pListRepresentation;

- (id)objectForKey:(NSString *)key;
- (void)setObject:(id)value forKey:(NSString *)key;
- (void)removeObjectForKey:(NSString *)key;

- (void)setPruneThreshold:(unsigned)threshold;
- (unsigned)pruneThreshold;

- (BOOL)dirty;
- (void)markClean;

@end
