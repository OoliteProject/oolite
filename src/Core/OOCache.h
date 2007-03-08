/*

OOCache.h
By Jens Ayton

OOCache is an implementation detail of OOCacheManager. Don't use it directly.

This is a simple implementation which doesn't support pruning.

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
	NSMutableDictionary		*cache;
	unsigned				pruneThreshold;
	BOOL					dirty;
}

- (id)init;
- (id)initWithPList:(id)inPList;
- (id)pListRepresentation;

- (id)objectForKey:(NSString *)inKey;
- (void)setObject:(id)inValue forKey:(NSString *)inKey;
- (void)removeObjectForKey:(NSString *)inKey;

- (void)setPruneThreshold:(unsigned)inThreshold;
- (unsigned)pruneThreshold;

- (BOOL)dirty;
- (void)markClean;

@end
