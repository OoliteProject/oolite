/*

MutableDictionaryExtension.m
Created by Giles Williams on 2005-05-01.

For Oolite
Copyright (C) 2005  Giles C Williams

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
#import "MutableDictionaryExtension.h"

@implementation NSMutableDictionary (OOExtensions)

- (void)mergeEntriesFromDictionary:(NSDictionary *)otherDictionary
{
	NSArray* otherKeys = [otherDictionary allKeys];
	NSEnumerator* otherKeysEnum = [otherKeys objectEnumerator];
	id key;
	 
	while (key = [otherKeysEnum nextObject])
	{
		if (![self objectForKey:key])
			[self setObject:[otherDictionary objectForKey:key] forKey:key];
		else
		{
			BOOL merged = NO;
			id thisObject = [self objectForKey:key];
			id otherObject = [otherDictionary objectForKey:key];
			
			if ([thisObject isKindOfClass:[NSDictionary class]]&&[otherObject isKindOfClass:[NSDictionary class]]&&(![thisObject isEqual:otherObject]))
			{
				NSMutableDictionary* mergeObject = [NSMutableDictionary dictionaryWithDictionary:(NSDictionary*)thisObject];
				[mergeObject mergeEntriesFromDictionary:(NSDictionary*)otherObject];
				[self setObject:mergeObject forKey:key];
				merged = YES;
			}
			
			if ([thisObject isKindOfClass:[NSArray class]]&&[otherObject isKindOfClass:[NSArray class]]&&(![thisObject isEqual:otherObject]))
			{
				NSMutableArray* mergeObject = [NSMutableArray arrayWithArray:(NSArray*)thisObject];
				[mergeObject addObjectsFromArray:(NSArray*)otherObject];
				[self setObject:mergeObject forKey:key];
				merged = YES;
			}
			
			if (!merged)
				[self setObject:otherObject forKey:key];
		}
	}	
}

@end
