/*

ShipEntityLoadRestore.m


Oolite
Copyright (C) 2004-2012 Giles C Williams and contributors

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
#import "OOEquipmentType.h"
#import "AI.h"


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
#define KEY_SCAN_CLASS				@"scan_class"

// AI is a complete pickled AI state.
#define KEY_AI						@"AI"

// Group IDs are numbers synchronised through the context object.
#define KEY_GROUP_ID				@"group"
#define KEY_GROUP_NAME				@"group_name"
#define	KEY_IS_GROUP_LEADER			@"is_group_leader"
#define	KEY_ESCORT_GROUP_ID			@"escort_group"


static void StripIgnoredKeys(NSMutableDictionary *dict);
static OOUInteger GroupIDForGroup(OOShipGroup *group, NSMutableDictionary *context);
static OOShipGroup *GroupForGroupID(OOUInteger groupID, NSMutableDictionary *context);


@interface ShipEntity (LoadRestoreInternal)

- (void) simplifyShipdata:(NSMutableDictionary *)data andGetDeletes:(NSArray **)deletes;

@end


@implementation ShipEntity (LoadRestore)

- (NSDictionary *) savedShipDictionaryWithContext:(NSMutableDictionary *)context
{
	NSMutableDictionary *result = [NSMutableDictionary dictionary];
	if (context == nil)  context = [NSMutableDictionary dictionary];
	
	[result setObject:_shipKey forKey:KEY_SHIP_KEY];
	
	NSMutableDictionary *updatedShipInfo = [NSMutableDictionary dictionaryWithDictionary:shipinfoDictionary];
	
	[updatedShipInfo setObject:[[self roleSet] roleString] forKey:KEY_ROLES];
	[updatedShipInfo oo_setUnsignedInteger:fuel forKey:KEY_FUEL];
	[updatedShipInfo oo_setUnsignedLongLong:bounty forKey:KEY_BOUNTY];
	[updatedShipInfo setObject:OOStringFromWeaponType(forward_weapon_type) forKey:KEY_FORWARD_WEAPON];
	[updatedShipInfo setObject:OOStringFromWeaponType(aft_weapon_type) forKey:KEY_AFT_WEAPON];
	[updatedShipInfo setObject:OOStringFromScanClass(scanClass) forKey:KEY_SCAN_CLASS];
	
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
		NSString *groupName = [_group name];
		if (groupName != nil)
		{
			[result setObject:groupName forKey:KEY_GROUP_NAME];
		}
	}
	if (_escortGroup != nil)
	{
		[result oo_setUnsignedInteger:GroupIDForGroup(_escortGroup, context) forKey:KEY_ESCORT_GROUP_ID];
	}
	/*	Eric: 
		The escortGroup property is removed from the lead ship, on entering witchspace.
		But it is needed in the save file to correctly restore an escorted group.
	*/
	else if (_group != nil && [_group leader] == self)
	{
		[result oo_setUnsignedInteger:GroupIDForGroup(_group, context) forKey:KEY_ESCORT_GROUP_ID];
	}
	
	// FIXME: AI.
	// Eric: I think storing the AI name should be enough. On entering a wormhole, the stack is cleared so there are no preserved AI states.
	// Also the AI restarts itself with the GLOBAL state, so no need to store any old state. 
	[result setObject:[[self getAI] name] forKey:KEY_AI];
	
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
		[mergedData oo_setUnsignedInteger:0 forKey:@"escorts"];
		
		Class shipClass = [UNIVERSE shipClassForShipDictionary:mergedData];
		ship = [[[shipClass alloc] initWithKey:shipKey definition:mergedData] autorelease];
		
		// FIXME: restore AI.
		[[ship getAI] setStateMachine:[dict oo_stringForKey:KEY_AI defaultValue:@"nullAI.plist"]];
		
		[ship setPrimaryRole:[dict oo_stringForKey:KEY_PRIMARY_ROLE]];
	
	}
	else
	{
		// Unknown ship; fall back on role if desired and possible.
		NSString *shipPrimaryRole = [dict oo_stringForKey:KEY_PRIMARY_ROLE];
		if (!fallback || shipPrimaryRole == nil)  return nil;
		
		ship = [[UNIVERSE newShipWithRole:shipPrimaryRole] autorelease];
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
		[ship addEquipmentItem:eqKey withValidation:NO];
	}
	
	[ship removeMissiles];
	for (eqEnum = [[dict oo_arrayForKey:KEY_MISSILES] objectEnumerator]; (eqKey = [eqEnum nextObject]); )
	{
		[ship addEquipmentItem:eqKey withValidation:NO];
	}
	
	// Groups.
	OOUInteger groupID = [dict oo_integerForKey:KEY_GROUP_ID defaultValue:NSNotFound];
	if (groupID != NSNotFound)
	{
		OOShipGroup *group = GroupForGroupID(groupID, context);
		[ship setGroup:group];	// Handles adding to group
		if ([dict oo_boolForKey:KEY_IS_GROUP_LEADER])  [group setLeader:ship];
		NSString *groupName = [dict oo_stringForKey:KEY_GROUP_NAME];
		if (groupName != nil)  [group setName:groupName];
		if ([ship hasPrimaryRole:@"escort"] && ship != [group leader])
		{
			[ship setOwner:[group leader]];
		}
	}
	
	groupID = [dict oo_integerForKey:KEY_ESCORT_GROUP_ID defaultValue:NSNotFound];
	if (groupID != NSNotFound)
	{
		OOShipGroup *group = GroupForGroupID(groupID, context);
		[group setLeader:ship];
		[group setName:@"escort group"];
		[ship setEscortGroup:group];
	}
	
	return ship;
}


- (void) simplifyShipdata:(NSMutableDictionary *)data andGetDeletes:(NSArray **)deletes
{
	NSParameterAssert(data != nil && deletes != NULL);
	*deletes = nil;
	
	// Get original ship data.
	NSMutableDictionary *referenceData = [NSMutableDictionary dictionaryWithDictionary:[[OOShipRegistry sharedRegistry] shipInfoForKey:[self shipDataKey]]];
	
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
	
	// after rev3010 this loop was using cycles without doing anything - commenting this whole loop out for now. -- kaks 20100207
/*
	// Discard anything that hasn't changed.
	for (enumerator = [data keyEnumerator]; (key = [enumerator nextObject]); )
	{
		id referenceVal = [referenceData objectForKey:key];
		id myVal = [data objectForKey:key];
		if ([referenceVal isEqual:myVal])
		{
		//	[data removeObjectForKey:key];
		}
	}
*/
}

@end


static void StripIgnoredKeys(NSMutableDictionary *dict)
{
	static NSArray *ignoredKeys = nil;
	if (ignoredKeys == nil)  ignoredKeys = [[NSArray alloc] initWithObjects:@"ai_type", @"has_ecm", @"has_scoop", @"has_escape_pod", @"has_energy_bomb", @"has_fuel_injection", @"has_cloaking_device", @"has_military_jammer", @"has_military_scanner_filter", @"has_shield_booster", @"has_shield_enhancer", @"escorts", @"escort_role", @"escort-ship", @"conditions", @"missiles", @"auto_ai", nil];
	
	NSEnumerator *keyEnum = nil;
	NSString *key = nil;
	for (keyEnum = [ignoredKeys objectEnumerator]; (key = [keyEnum nextObject]); )
	{
		[dict removeObjectForKey:key];
	}
}


static OOUInteger GroupIDForGroup(OOShipGroup *group, NSMutableDictionary *context)
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


static OOShipGroup *GroupForGroupID(OOUInteger groupID, NSMutableDictionary *context)
{
	NSNumber *key = [NSNumber numberWithUnsignedInteger:groupID];
	
	NSMutableDictionary *groups = [context objectForKey:@"groupsByID"];
	if (groups == nil)
	{
		groups = [NSMutableDictionary dictionary];
		[context setObject:groups forKey:@"groupsByID"];
	}
	
	OOShipGroup *group = [groups objectForKey:key];
	if (group == nil)
	{
		group = [[[OOShipGroup alloc] init] autorelease];
		[groups setObject:group forKey:key];
	}
	
	return group;
}
