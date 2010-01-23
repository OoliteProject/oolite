/*

ShipEntityLoadRestore.m


Oolite
Copyright (C) 2004-2008 Giles C Williams and contributors

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

#import "ShipEntityLoadRestore.h"
#import "Universe.h"

#import "OOShipRegistry.h"
#import "OORoleSet.h"
#import "OOCollectionExtractors.h"
#import "OOConstToString.h"
#import "OOShipGroup.h"


#define KEY_SHIP_KEY				@"ship_key"
#define KEY_SHIPDATA_OVERRIDES		@"shipdata_overrides"
#define KEY_SHIPDATA_DELETES		@"shipdata_deletes"
#define KEY_PRIMARY_ROLE			@"primary_role"
#define KEY_POSITION				@"position"
#define KEY_ORIENTATION				@"orientation"
#define KEY_ROLES					@"roles"
#define KEY_FUEL					@"fuel"
#define KEY_BOUNTY					@"bounty"
#define KEY_ENERGY_LEVEL			@"energy_level"
#define KEY_EQUIPMENT				@"equipment"
#define KEY_MISSILES				@"missiles"
#define KEY_FORWARD_WEAPON			@"forward_weapon_type"
#define KEY_AFT_WEAPON				@"aft_weapon_type"

// AI is a complete pickled AI state.
#define KEY_AI						@"AI"

// Escort IDs are numbers synchronised through the context object.
#define KEY_GROUP_ID				@"group"
#define	KEY_IS_GROUP_LEADER			@"is_group_leader"
#define	KEY_ESCORT_GROUP_ID			@"escort_group"
#define	KEY_IS_ESCORT_GROUP_LEADER	@"is_escort_group_leader"


static void StripIgnoredKeys(NSMutableDictionary *dict);
static unsigned GroupIDForGroup(OOShipGroup *group, NSMutableDictionary *context);


@interface ShipEntity (LoadRestoreInternal)

- (void) simplifyShipdata:(NSMutableDictionary *)data andGetDeletes:(NSArray **)deletes;

@end


@implementation ShipEntity (LoadRestore)

- (NSDictionary *) savedShipDictionaryWithContext:(NSMutableDictionary *)context
{
	NSMutableDictionary *result = [NSMutableDictionary dictionary];
	if (context == nil)  context = [NSMutableDictionary dictionary];
	
	[result setObject:_shipKey forKey:KEY_SHIP_KEY];
	
	NSMutableDictionary *updatedShipInfo = [[shipinfoDictionary mutableCopy] autorelease];
	
	[updatedShipInfo setObject:[[self roleSet] roleString] forKey:KEY_ROLES];
	[updatedShipInfo oo_setUnsignedInteger:fuel forKey:KEY_FUEL];
	[updatedShipInfo oo_setUnsignedInteger:bounty forKey:KEY_BOUNTY];
	[updatedShipInfo setObject:WeaponTypeToString(forward_weapon_type) forKey:KEY_FORWARD_WEAPON];
	[updatedShipInfo setObject:WeaponTypeToString(aft_weapon_type) forKey:KEY_AFT_WEAPON];
	
	NSArray *deletes = nil;
	[self simplifyShipdata:updatedShipInfo andGetDeletes:&deletes];
	
	[result setObject:updatedShipInfo forKey:KEY_SHIPDATA_OVERRIDES];
	if (deletes != nil)  [result setObject:deletes forKey:KEY_SHIPDATA_DELETES];
	
	if (!vector_equal([self position], kZeroVector))
	{
		[result oo_setVector:[self position] forKey:KEY_POSITION];
	}
	if (!quaternion_equal([self normalOrientation], kIdentityQuaternion))
	{
		[result oo_setQuaternion:[self normalOrientation] forKey:KEY_ORIENTATION];
	}
	
	if (energy != maxEnergy)  [result oo_setFloat:(float)energy / (float)maxEnergy forKey:KEY_ENERGY_LEVEL];
	
	[result setObject:[self primaryRole] forKey:KEY_PRIMARY_ROLE];
	
	// Add equipment.
	NSArray *equipment = [[self equipmentEnumerator] allObjects];
	if ([equipment count] != 0)  [result setObject:equipment forKey:KEY_EQUIPMENT];
	
	// Add missiles.
	if (missiles > 0)
	{
		NSMutableArray *missileArray = [NSMutableArray array];
		unsigned i;
		for (i = 0; i < missiles; i++)
		{
			NSString *missileType = [missile_list[i] identifier];
			if (missileType != nil)  [missileArray addObject:missileType];
		}
		[result setObject:missileArray forKey:KEY_MISSILES];
	}
	
	// Add groups.
	if (_group != nil)
	{
		[result oo_setUnsignedInteger:GroupIDForGroup(_group, context) forKey:KEY_GROUP_ID];
		if ([_group leader] == self)  [result oo_setBool:YES forKey:KEY_IS_GROUP_LEADER];
	}
	if (_escortGroup != nil)
	{
		[result oo_setUnsignedInteger:GroupIDForGroup(_escortGroup, context) forKey:KEY_ESCORT_GROUP_ID];
		if ([_escortGroup leader] == self)  [result oo_setBool:YES forKey:KEY_IS_ESCORT_GROUP_LEADER];
	}
	
	// FIXME: AI.
	
	return result;
}


+ (id) shipRestoredFromDictionary:(NSDictionary *)dict
					  useFallback:(BOOL)fallback
						  context:(NSMutableDictionary *)context
{
	if (dict == nil)  return nil;
	if (context == nil)  context = [NSMutableDictionary dictionary];
	
	ShipEntity *ship = nil;
	
	NSString *shipKey = [dict oo_stringForKey:KEY_SHIP_KEY];
	NSDictionary *shipData = [[OOShipRegistry sharedRegistry] shipInfoForKey:shipKey];
	
	if (shipData != nil)
	{
		NSMutableDictionary *mergedData = [NSMutableDictionary dictionaryWithDictionary:shipData];
		
		StripIgnoredKeys(mergedData);
		NSArray *deletes = [dict oo_arrayForKey:KEY_SHIPDATA_DELETES];
		if (deletes != nil)  [mergedData removeObjectsForKeys:deletes];
		[mergedData addEntriesFromDictionary:[dict oo_dictionaryForKey:KEY_SHIPDATA_OVERRIDES]];
		[mergedData oo_setBool:NO forKey:@"auto_ai"];
		
		Class shipClass = [UNIVERSE shipClassForShipDictionary:mergedData];
		ship = [[[shipClass alloc] initWithKey:shipKey definition:mergedData] autorelease];
		
		// FIXME: restore AI.
	}
	else
	{
		// Unknown ship; fall back on role if desired and possible.
		NSString *primaryRole = [dict oo_stringForKey:KEY_PRIMARY_ROLE];
		if (!fallback || primaryRole == nil)  return nil;
		
		ship = [[UNIVERSE newShipWithRole:primaryRole] autorelease];
		if (ship == nil)  return nil;
	}
	
	// The following stuff is deliberately set up the same way even if using role fallback.
	[ship setPosition:[dict oo_vectorForKey:KEY_POSITION]];
	[ship setNormalOrientation:[dict oo_quaternionForKey:KEY_ORIENTATION]];
	
	float energyLevel = [dict oo_floatForKey:KEY_ENERGY_LEVEL defaultValue:1.0f];
	[ship setEnergy:energyLevel * [ship maxEnergy]];
	
	[ship removeAllEquipment];
	NSEnumerator *eqEnum = nil;
	NSString *eqKey = nil;
	for (eqEnum = [[dict oo_arrayForKey:KEY_EQUIPMENT] objectEnumerator]; (eqKey = [eqEnum nextObject]); )
	{
		[ship addEquipmentItem:eqKey];
	}
	
	[ship removeMissiles];
	for (eqEnum = [[dict oo_arrayForKey:KEY_MISSILES] objectEnumerator]; (eqKey = [eqEnum nextObject]); )
	{
		[ship addEquipmentItem:eqKey];
	}
	
	// FIXME: groups.
	
	return ship;
}


- (void) simplifyShipdata:(NSMutableDictionary *)data andGetDeletes:(NSArray **)deletes
{
	NSParameterAssert(data != nil && deletes != NULL);
	*deletes = nil;
	
	// Get original ship data.
	NSDictionary *shipData = [[OOShipRegistry sharedRegistry] shipInfoForKey:[self shipDataKey]];
	NSMutableDictionary *referenceData = [[shipData mutableCopy] autorelease];
	
	// Discard stuff that we handle separately.
	StripIgnoredKeys(referenceData);
	StripIgnoredKeys(data);
	
	// Note items that are in referenceData, but not data.
	NSMutableArray *foundDeletes = [NSMutableArray array];
	NSEnumerator *enumerator = nil;
	NSString *key = nil;
	for (enumerator = [referenceData keyEnumerator]; (key = [enumerator nextObject]); )
	{
		if ([data objectForKey:key] == nil)
		{
			[foundDeletes addObject:key];
		}
	}
	if ([foundDeletes count] != 0)  *deletes = foundDeletes;
	
	// Discard anything that hasn't changed.
	for (enumerator = [data keyEnumerator]; (key = [enumerator nextObject]); )
	{
		id referenceVal = [referenceData objectForKey:key];
		id myVal = [data objectForKey:key];
		if ([referenceVal isEqual:myVal])
		{
			[data removeObjectForKey:key];
		}
	}
}

@end


static void StripIgnoredKeys(NSMutableDictionary *dict)
{
	static NSArray *ignoredKeys = nil;
	if (ignoredKeys == nil)  ignoredKeys = [NSArray arrayWithObjects:@"ai_type", @"has_ecm", @"has_scoop", @"has_escape_pod", @"has_energy_bomb", @"has_fuel_injection", @"has_cloaking_device", @"has_military_jammer", @"has_military_scanner_filter", @"has_shield_booster", @"has_shield_enhancer", @"escort_role", @"escort-ship", @"conditions", @"missiles", @"auto_ai", nil];
	
	NSEnumerator *keyEnum = nil;
	NSString *key = nil;
	for (keyEnum = [ignoredKeys objectEnumerator]; (key = [keyEnum nextObject]); )
	{
		[dict removeObjectForKey:key];
	}
}


static unsigned GroupIDForGroup(OOShipGroup *group, NSMutableDictionary *context)
{
	NSMutableDictionary *groupIDs = [context objectForKey:@"groupIDs"];
	if (groupIDs == nil)
	{
		groupIDs = [NSMutableDictionary dictionary];
		[context setObject:groupIDs forKey:@"groupIDs"];
	}
	
	NSValue *key = [NSValue valueWithNonretainedObject:group];
	NSNumber *groupIDObj = [groupIDs objectForKey:key];
	unsigned groupID;
	if (groupIDObj == nil)
	{
		// Assign a new group ID.
		groupID = [context oo_unsignedIntForKey:@"nextGroupID"];
		groupIDObj = [NSNumber numberWithUnsignedInt:groupID];
		[context oo_setUnsignedInteger:groupID + 1 forKey:@"nextGroupID"];
		[groupIDs setObject:groupIDObj forKey:key];
		
		/*	Also keep references to the groups. This isn't necessary at the
			time of writing, but would be if we e.g. switched to pickling
			ships in wormholes all the time (each wormhole would then need a
			persistent context). We can't simply use the groups instead of
			NSValues as keys, becuase dictionary keys must be copyable.
		*/
		NSMutableSet *groups = [context objectForKey:@"groups"];
		if (groups == nil)
		{
			groups = [NSMutableSet set];
			[context setObject:groups forKey:@"groups"];
		}
		[groups addObject:group];
	}
	else
	{
		groupID = [groupIDObj unsignedIntValue];
	}

	
	return groupID;
}
