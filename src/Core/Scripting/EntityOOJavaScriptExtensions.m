/*

EntityOOJavaScriptExtensions.m

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


#import "EntityOOJavaScriptExtensions.h"
#import "OOJSEntity.h"
#import "OOJSShip.h"
#import "OOJSStation.h"
#import "StationEntity.h"
#import "PlanetEntity.h"


@implementation Entity (OOJavaScriptExtensions)


- (BOOL)isVisibleToScripts
{
	return	self->isShip ||
		//	self->isStation ||	// Stations are always ships
		//	self->isPlayer ||	// The player is also a ship
			self->isPlanet;
}


- (NSString *)jsClassName
{
	return @"Entity";
}


- (BOOL)isShip
{
	return isShip;
}


- (BOOL)isStation
{
	return isStation;
}


- (BOOL)isSubEntity
{
	return isSubentity;
}


- (BOOL)isPlayer
{
	return isPlayer;
}


- (BOOL)isPlanet
{
	return isPlanet;
}


- (jsval)javaScriptValueInContext:(JSContext *)context
{
	jsval result = JSVAL_NULL;
	if ([self isVisibleToScripts])
	{
		EntityToJSValue(context, self, &result);
	}
	return result;
}


- (void)getJSClass:(JSClass **)outClass andPrototype:(JSObject **)outPrototype
{
	*outClass = JSEntityClass();
	*outPrototype = JSEntityPrototype();
}

@end


@implementation ShipEntity (OOJavaScriptExtensions)

- (void)getJSClass:(JSClass **)outClass andPrototype:(JSObject **)outPrototype
{
	*outClass = JSShipClass();
	*outPrototype = JSShipPrototype();
}


- (NSString *)jsClassName
{
	return @"Ship";
}


- (NSArray *)subEntitiesForScript
{
	unsigned			i, count;
	NSMutableArray		*result = nil;
	id					object = nil;
	
	count = [sub_entities count];
	if (count == 0)  return nil;
	
	result = [[NSMutableArray alloc] initWithCapacity:count];
	for (i = 0; i != count; ++i)
	{
		object = [sub_entities objectAtIndex:i];
		if ([object isKindOfClass:[ShipEntity class]])
		{
			[result addObject:object];
		}
	}
	
	if ([result count] == 0)
	{
		[result release];
		return nil;
	}
	else
	{
		return [result autorelease];
	}
}


- (NSArray *)escorts
{
	unsigned			i;
	NSMutableArray		*result = nil;
	id					object = nil;
	
	if (escortCount == 0)  return nil;
	result = [NSMutableArray arrayWithCapacity:escortCount];
	
	for (i = 0; i != escortCount; ++i)
	{
		object = [UNIVERSE entityForUniversalID:escort_ids[i]];
		if ([object isKindOfClass:[ShipEntity class]])
		{
			[result addObject:object];
		}
	}
	
	if ([result count] == 0)
	{
		[result release];
		return nil;
	}
	else
	{
		return [result autorelease];
	}
}


- (void)setTargetForScript:(ShipEntity *)target
{
	ShipEntity			*me = self;
	
	// Ensure coherence by not fiddling with subentities
	while ([me isSubEntity])  me = (ShipEntity *)[me owner];
	while ([target isSubEntity])  target = (ShipEntity *)[target owner];
	
	if (![me isKindOfClass:[ShipEntity class]])  return;
	if (target != nil)  [me addTarget:target];
	else  [me removeTarget:[me primaryTarget]];
}

@end


@implementation PlayerEntity (OOJavaScriptExtensions)

- (NSString *)jsClassName
{
	return @"Player";
}

@end


@implementation StationEntity (OOJavaScriptExtensions)

- (void)getJSClass:(JSClass **)outClass andPrototype:(JSObject **)outPrototype
{
	*outClass = JSStationClass();
	*outPrototype = JSStationPrototype();
}


- (NSString *)jsClassName
{
	return @"Station";
}

@end


@implementation PlanetEntity (OOJavaScriptExtensions)

- (NSString *)jsClassName
{
	return @"Planet";
}

@end
