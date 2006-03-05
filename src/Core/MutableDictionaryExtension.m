/*

	Oolite

	MutableDictionaryExtension.m
	
	Created by Giles Williams on 01/05/2005.


Copyright (c) 2005, Giles C Williams
All rights reserved.

This work is licensed under the Creative Commons Attribution-NonCommercial-ShareAlike License.
To view a copy of this license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/
or send a letter to Creative Commons, 559 Nathan Abbott Way, Stanford, California 94305, USA.

You are free:

•	to copy, distribute, display, and perform the work
•	to make derivative works

Under the following conditions:

•	Attribution. You must give the original author credit.

•	Noncommercial. You may not use this work for commercial purposes.

•	Share Alike. If you alter, transform, or build upon this work,
you may distribute the resulting work only under a license identical to this one.

For any reuse or distribution, you must make clear to others the license terms of this work.

Any of these conditions can be waived if you get permission from the copyright holder.

Your fair use and other rights are in no way affected by the above.

*/

#import <Foundation/Foundation.h>
#import "MutableDictionaryExtension.h"

@implementation NSMutableDictionary (OoliteExtensions)

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
