/*

OOCache.m
By Jens Ayton

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

#import "OOCache.h"
#import "OOCacheManager.h"


@implementation OOCache

- (void)dealloc
{
	[cache release];
	
	[super dealloc];
}


- (NSString *)description
{
	return [NSString stringWithFormat:@"<%@ %p>{%u elements, prune threshold=%u, dirty=%s}", [self class], self, [cache count], pruneThreshold, dirty ? "yes" : "no"];
}


- (id)init
{
	return [self initWithPList:nil];
}


- (id)initWithPList:(id)inPList
{
	self = [super init];
	if (self != nil)
	{
		if (inPList != nil)  cache = [[NSMutableDictionary alloc] initWithDictionary:inPList];
		else  cache = [[NSMutableDictionary alloc] init];
	}
	
	return self;
}


- (id)pListRepresentation
{
	return cache;
}


- (id)objectForKey:(NSString *)inKey
{
	return [cache objectForKey:inKey];
}


- (void)setObject:inObject forKey:(NSString *)inKey
{
	[cache setObject:inObject forKey:inKey];
	dirty = YES;
}


- (void)removeObjectForKey:(NSString *)inKey
{
	[cache removeObjectForKey:inKey];
	dirty = YES;
}


- (void)setPruneThreshold:(unsigned)inThreshold
{
	pruneThreshold = inThreshold;
}


- (unsigned)pruneThreshold
{
	return pruneThreshold;
}


- (BOOL)dirty
{
	return dirty;
}


- (void)markClean
{
	dirty = NO;
}

@end
