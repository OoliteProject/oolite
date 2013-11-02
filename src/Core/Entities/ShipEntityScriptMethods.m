/*

ShipEntityScriptMethods.m


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

#import "ShipEntityScriptMethods.h"
#import "Universe.h"
#import "OOCollectionExtractors.h"


static NSString * const kOOLogNoteAddShips = @"script.debug.note.addShips";


@implementation ShipEntity (ScriptMethods)

- (ShipEntity *) ejectShipOfType:(NSString *)shipKey
{
	ShipEntity		*item = nil;
	
	if (shipKey != nil)
	{
		item = [[UNIVERSE newShipWithName:shipKey] autorelease];
		if (item != nil)  [self dumpItem:item];
	}
	
	return item;
}


- (ShipEntity *) ejectShipOfRole:(NSString *)role
{
	ShipEntity		*item = nil;
	
	if (role != nil)
	{
		item = [[UNIVERSE newShipWithRole:role] autorelease];
		if (item != nil)  [self dumpItem:item];
	}
	
	return item;
}


- (NSArray *) spawnShipsWithRole:(NSString *)role count:(NSUInteger)count
{
	ShipEntity				*ship = [self rootShipEntity];	// FIXME: (EMMSTRAN) implement an -absolutePosition method, use that in spawnShipWithRole:near:, and use self instead of root.
	ShipEntity				*spawned = nil;
	NSMutableArray			*result = nil;
	
	if (count == 0)  return [NSArray array];
	
	OOLog(kOOLogNoteAddShips, @"Spawning %ld x '%@' near %@ %d", count, role, [self shortDescription], [self universalID]);
	
	result = [NSMutableArray arrayWithCapacity:count];
	
	do
	{
		spawned = [UNIVERSE spawnShipWithRole:role near:ship];
		if (spawned != nil)
		{
			[spawned setTemperature:[self randomEjectaTemperature]];
			if ([self isMissileFlagSet] && [[spawned shipInfoDictionary] oo_boolForKey:@"is_submunition"])
			{
				[spawned setOwner:[self owner]];
				[spawned addTarget:[self primaryTarget]];
				[spawned setIsMissileFlag:YES];
			}
			[result addObject:spawned];
		}
	}
	while (--count);
	
	return result;
}

@end
