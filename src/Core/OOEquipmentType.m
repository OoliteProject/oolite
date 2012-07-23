/*

OOEquipmentType.m


Copyright (C) 2008-2012 Jens Ayton and contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/

#import "OOEquipmentType.h"
#import "Universe.h"
#import "OOCollectionExtractors.h"
#import "OOLegacyScriptWhitelist.h"
#import "OOCacheManager.h"


static NSArray			*sEquipmentTypes = nil;
static NSDictionary		*sEquipmentTypesByIdentifier = nil;
static NSDictionary		*sMissilesRegistry = nil;


@interface OOEquipmentType (Private)

- (id) initWithInfo:(NSArray *)info;

@end


@implementation OOEquipmentType

+ (void) loadEquipment
{
	NSArray				*equipmentData = nil;
	NSMutableArray		*equipmentTypes = nil;
	NSMutableDictionary	*equipmentTypesByIdentifier = nil;
	NSArray				*itemInfo = nil;
	OOEquipmentType		*item = nil;
	NSEnumerator		*itemEnum = nil;
	NSMutableArray *conditionScripts = nil;
	
	equipmentData = [UNIVERSE equipmentData];
	
	[sEquipmentTypes release];
	sEquipmentTypes = nil;
	equipmentTypes = [NSMutableArray arrayWithCapacity:[equipmentData count]];
	conditionScripts = [NSMutableArray arrayWithCapacity:[equipmentData count]];
	DESTROY(sEquipmentTypesByIdentifier);
	equipmentTypesByIdentifier = [NSMutableDictionary dictionaryWithCapacity:[equipmentData count]];
	
	for (itemEnum = [equipmentData objectEnumerator]; (itemInfo = [itemEnum nextObject]); )
	{
		item = [[[OOEquipmentType alloc] initWithInfo:itemInfo] autorelease];
		if (item != nil)
		{
			[equipmentTypes addObject:item];
			[equipmentTypesByIdentifier setObject:item forKey:[item identifier]];
		}
		NSString* condition_script = [item conditionScript];
		if (condition_script != nil)
		{
			if (![conditionScripts containsObject:condition_script])
			{
				[conditionScripts addObject:condition_script];
			}
		}
	}
	
	[[OOCacheManager sharedCache] setObject:conditionScripts forKey:@"equipment conditions" inCache:@"condition scripts"];

	sEquipmentTypes = [equipmentTypes copy];
	sEquipmentTypesByIdentifier = [[NSDictionary alloc] initWithDictionary:equipmentTypesByIdentifier];
}


+ (void) addEquipmentWithInfo:(NSArray *)itemInfo
{
	NSMutableArray		*equipmentTypes = [NSMutableArray arrayWithArray:sEquipmentTypes];
	NSMutableDictionary	*equipmentTypesByIdentifier = [[NSMutableDictionary alloc] initWithDictionary:sEquipmentTypesByIdentifier];
	OOEquipmentType		*item = [[[OOEquipmentType alloc] initWithInfo:itemInfo] autorelease];
	if (item != nil)
	{
		[equipmentTypes addObject:item];
		[equipmentTypesByIdentifier setObject:item forKey:[item identifier]];
		
		[sEquipmentTypes release];
		sEquipmentTypes = nil;
		DESTROY(sEquipmentTypesByIdentifier);
		sEquipmentTypes = [equipmentTypes copy];
		sEquipmentTypesByIdentifier = [[NSDictionary alloc] initWithDictionary:equipmentTypesByIdentifier];
	}
	DESTROY(equipmentTypesByIdentifier);
}


+ (NSString *) getMissileRegistryRoleForShip:(NSString *)shipKey
{
	return [sMissilesRegistry oo_stringForKey:shipKey];
}


+ (void) setMissileRegistryRole:(NSString *)role forShip:(NSString *)shipKey
{
	NSMutableDictionary	*missilesRegistry = [[NSMutableDictionary alloc] initWithDictionary:sMissilesRegistry];
	if (role != nil && shipKey != nil && ![shipKey isEqualToString:@""])
	{
		[missilesRegistry setValue:role forKey:shipKey];
		DESTROY(sMissilesRegistry);
		sMissilesRegistry = [[NSDictionary alloc] initWithDictionary:missilesRegistry];
	}
	DESTROY(missilesRegistry);
}


+ (NSArray *) allEquipmentTypes
{
	return sEquipmentTypes;
}


+ (NSEnumerator *) equipmentEnumerator
{
	return [sEquipmentTypes objectEnumerator];
}


+ (OOEquipmentType *) equipmentTypeWithIdentifier:(NSString *)identifier
{
	return [sEquipmentTypesByIdentifier objectForKey:identifier];
}


- (id) initWithInfo:(NSArray *)info
{
	BOOL				OK = YES;
	NSDictionary		*extra = nil;
	NSArray				*conditions = nil;
	NSString      *condition_script = nil;
	
	self = [super init];
	if (self == nil)  OK = NO;
	
	if (OK && [info count] <= EQUIPMENT_LONG_DESC_INDEX)  OK = NO;
	
	if (OK)
	{
		// Read required attributes
		_techLevel = [info oo_unsignedIntAtIndex:EQUIPMENT_TECH_LEVEL_INDEX];
		_price = [info oo_unsignedIntAtIndex:EQUIPMENT_PRICE_INDEX];
		_name = [[info oo_stringAtIndex:EQUIPMENT_SHORT_DESC_INDEX] retain];
		_identifier = [[info oo_stringAtIndex:EQUIPMENT_KEY_INDEX] retain];
		_description = [[info oo_stringAtIndex:EQUIPMENT_LONG_DESC_INDEX] retain];
		
		if (_name == nil || _identifier == nil || _description == nil)
		{
			OOLog(@"equipment.load", @"***** ERROR: Invalid equipment.plist entry - missing name, identifier or description (\"%@\", %@, \"%@\")", _name, _identifier, _description);
			OK = NO;
		}
	}
	
	if (OK)
	{
		// Implied attributes for backwards-compatibility
		if ([_identifier hasSuffix:@"_MISSILE"] || [_identifier hasSuffix:@"_MINE"])
		{
			_isMissileOrMine = YES;
			_requiresEmptyPylon = YES;
		}
		else if ([_identifier isEqualToString:@"EQ_PASSENGER_BERTH_REMOVAL"])
		{
			_requiresFreePassengerBerth = YES;
		}
		else if ([_identifier isEqualToString:@"EQ_FUEL"])
		{
			_requiresNonFullFuel = YES;
		}
		_isVisible = YES;
		_isAvailableToPlayer = YES;
		_isAvailableToNPCs = YES;
		_damageProbability = 1.0;
	}
	
	if (OK && [info count] > EQUIPMENT_EXTRA_INFO_INDEX)
	{
		// Read extra info dictionary
		extra = [info oo_dictionaryAtIndex:EQUIPMENT_EXTRA_INFO_INDEX];
		if (extra != nil)
		{
			// Note: currently strict_mode_compatible is already handled by Universe, but at some point we want to get rid of Universe's equipmentData.
			BOOL strictModeOnly = [extra oo_boolForKey:@"strict_mode_only" defaultValue:NO];
			//BOOL strictModeCompatible = [extra oo_boolForKey:@"strict_mode_compatible" defaultValue:strictModeOnly]; // Wrong! Interprets explicitly set strict_mode_only = false as strict_mode_ompatible = false
			BOOL strictModeCompatible = [extra oo_boolForKey:@"strict_mode_compatible" defaultValue:([extra objectForKey:@"strict_mode_only"] != nil)]; // if strict_mode_only is explicitely set, it's compatible with strict mode!
			BOOL strict = [UNIVERSE strict];
			if ((strict && !strictModeCompatible) || (!strict && strictModeOnly))  OK = NO;
			
			_isAvailableToAll = [extra oo_boolForKey:@"available_to_all" defaultValue:_isAvailableToAll];
			_isAvailableToPlayer = [extra oo_boolForKey:@"available_to_player" defaultValue:_isAvailableToPlayer];
			_isAvailableToNPCs = [extra oo_boolForKey:@"available_to_NPCs" defaultValue:_isAvailableToNPCs];
			
			_isMissileOrMine = [extra oo_boolForKey:@"is_external_store" defaultValue:_isMissileOrMine];
			_requiresEmptyPylon = [extra oo_boolForKey:@"requires_empty_pylon" defaultValue:_requiresEmptyPylon];
			_requiresMountedPylon = [extra oo_boolForKey:@"requires_mounted_pylon" defaultValue:_requiresMountedPylon];
			_requiresClean = [extra oo_boolForKey:@"requires_clean" defaultValue:_requiresClean];
			_requiresNotClean = [extra oo_boolForKey:@"requires_not_clean" defaultValue:_requiresNotClean];
			_portableBetweenShips = [extra oo_boolForKey:@"portable_between_ships" defaultValue:_portableBetweenShips];
			_requiresFreePassengerBerth = [extra oo_boolForKey:@"requires_free_passenger_berth" defaultValue:_requiresFreePassengerBerth];
			_requiresFullFuel = [extra oo_boolForKey:@"requires_full_fuel" defaultValue:_requiresFullFuel];
			_requiresNonFullFuel = [extra oo_boolForKey:@"requires_non_full_fuel" defaultValue:_requiresNonFullFuel];
			_isVisible = [extra oo_boolForKey:@"visible" defaultValue:_isVisible];
			
			_requiredCargoSpace = [extra oo_unsignedIntForKey:@"requires_cargo_space" defaultValue:_requiredCargoSpace];

			_damageProbability = [extra oo_floatForKey:@"damage_probability" defaultValue:(_isMissileOrMine?0.0:1.0)];
			
			id object = [extra objectForKey:@"requires_equipment"];
			if ([object isKindOfClass:[NSString class]])  _requiresEquipment = [[NSSet setWithObject:object] retain];
			else if ([object isKindOfClass:[NSArray class]])  _requiresEquipment = [[NSSet setWithArray:object] retain];
			else if (object != nil)
			{
				OOLog(@"equipment.load", @"***** ERROR: %@ for equipment item %@ is not a string or an array.", @"requires_equipment", _identifier);
			}
			
			object = [extra objectForKey:@"requires_any_equipment"];
			if ([object isKindOfClass:[NSString class]])  _requiresAnyEquipment = [[NSSet setWithObject:object] retain];
			else if ([object isKindOfClass:[NSArray class]])  _requiresAnyEquipment = [[NSSet setWithArray:object] retain];
			else if (object != nil)
			{
				OOLog(@"equipment.load", @"***** ERROR: %@ for equipment item %@ is not a string or an array.", @"requires_any_equipment", _identifier);
			}
			
			object = [extra objectForKey:@"incompatible_with_equipment"];
			if ([object isKindOfClass:[NSString class]])  _incompatibleEquipment = [[NSSet setWithObject:object] retain];
			else if ([object isKindOfClass:[NSArray class]])  _incompatibleEquipment = [[NSSet setWithArray:object] retain];
			else if (object != nil)
			{
				OOLog(@"equipment.load", @"***** ERROR: %@ for equipment item %@ is not a string or an array.", @"incompatible_with_equipment", _identifier);
			}
			
			object = [extra objectForKey:@"conditions"];
			if ([object isKindOfClass:[NSString class]])  conditions = [NSArray arrayWithObject:object];
			else if ([object isKindOfClass:[NSArray class]])  conditions = object;
			else if (object != nil)
			{
				OOLog(@"equipment.load", @"***** ERROR: %@ for equipment item %@ is not a string or an array.", @"conditions", _identifier);
			}
			if (conditions != nil)
			{
				_conditions = OOSanitizeLegacyScriptConditions(conditions, [NSString stringWithFormat:@"<equipment type \"%@\">", _name]);
				[_conditions retain];
			}

			object = [extra objectForKey:@"condition_script"];
			if ([object isKindOfClass:[NSString class]])
			{
				condition_script = object;
			}
			else if (object != nil)
			{
				OOLog(@"equipment.load", @"***** ERROR: %@ for equipment item %@ is not a string.", @"condition_script", _identifier);
			}
			if (condition_script != nil)
			{
				_condition_script = [condition_script retain];
			}
			/* Condition scripts are shared: all equipment/ships using the
			 * same condition script use one shared instance. Equipment
			 * scripts and ship scripts are not shared and get one instance
			 * per item. */
			
			_scriptInfo = [extra oo_dictionaryForKey:@"script_info"];
			[_scriptInfo retain];
			
			_script = [extra oo_stringForKey:@"script"];
			if (_script != nil && ![OOScript jsScriptFromFileNamed:_script properties:nil])  _script = nil;
			[_script retain];
		}
	}
	
	if (!OK)
	{
		[self release];
		self = nil;
	}
	return self;
}


- (void) dealloc
{
	DESTROY(_name);
	DESTROY(_identifier);
	DESTROY(_description);
	DESTROY(_requiresEquipment);
	DESTROY(_requiresAnyEquipment);
	DESTROY(_incompatibleEquipment);
	DESTROY(_conditions);
	DESTROY(_condition_script);
	DESTROY(_scriptInfo);
	DESTROY(_script);
	
	[super dealloc];
}


- (id) copyWithZone:(NSZone *)zone
{
	// OOEquipmentTypes are immutable.
	return [self retain];
}


- (NSString *) descriptionComponents
{
	return [NSString stringWithFormat:@"%@ \"%@\"", _identifier, _name];
}


- (NSString *) identifier
{
	return _identifier;
}


- (NSString *) damagedIdentifier
{
	return [_identifier stringByAppendingString:@"_DAMAGED"];
}


- (NSString *) name
{
	return _name;
}


- (NSString *) descriptiveText
{
	return _description;
}


- (OOTechLevelID) techLevel
{
	return _techLevel;
}


- (OOCreditsQuantity) price
{
	return _price;
}


- (BOOL) isAvailableToAll
{
	return _isAvailableToAll;
}


- (BOOL) requiresEmptyPylon
{
	return _requiresEmptyPylon;
}


- (BOOL) requiresMountedPylon
{
	return _requiresMountedPylon;
}


- (BOOL) requiresCleanLegalRecord
{
	return _requiresClean;
}


- (BOOL) requiresNonCleanLegalRecord
{
	return _requiresNotClean;
}


- (BOOL) requiresFreePassengerBerth
{
	return _requiresFreePassengerBerth;
}


- (BOOL) requiresFullFuel
{
	return _requiresFullFuel;
}


- (BOOL) requiresNonFullFuel
{
	return _requiresNonFullFuel;
}


- (BOOL) isPrimaryWeapon
{
	return [[self identifier] hasPrefix:@"EQ_WEAPON"];
}


- (BOOL) isMissileOrMine
{
	return _isMissileOrMine;	
}


- (BOOL) isPortableBetweenShips
{
	return _portableBetweenShips;
}


- (BOOL) canCarryMultiple
{
	/*	Hard-coded for now. What would be the ramifications of making this
		a plist attribute?
	*/
	if ([self isMissileOrMine])  return YES;
	
	if ([_identifier isEqualToString:@"EQ_PASSENGER_BERTH"] ||
		[_identifier isEqualToString:@"EQ_TRUMBLE"])
	{
		return YES;
	}
	
	return NO;
}


- (GLfloat) damageProbability 
{
	if ([self isMissileOrMine])  return 0.0;

	return _damageProbability;
}


- (BOOL) canBeDamaged
{
	if ([self isMissileOrMine])  return NO;
	
	if ([self damageProbability] > 0.0)
	{
		return YES;
	}
	
	return NO;
}


- (BOOL) isVisible
{
	return _isVisible;
}


- (BOOL) isAvailableToPlayer
{
	return _isAvailableToPlayer;
}


- (BOOL) isAvailableToNPCs
{
	return _isAvailableToNPCs;
}


- (OOCargoQuantity) requiredCargoSpace
{
	return _requiredCargoSpace;
}


- (NSSet *) requiresEquipment
{
	return _requiresEquipment;
}


- (NSSet *) requiresAnyEquipment
{
	return _requiresAnyEquipment;
}


- (NSSet *) incompatibleEquipment
{
	return _incompatibleEquipment;
}


- (NSArray *) conditions
{
	return _conditions;
}


- (NSString *) conditionScript
{
	return _condition_script;
}


- (NSDictionary *) scriptInfo
{
	return _scriptInfo;
}


- (NSString *) scriptName
{
	return _script;
}


/*	This method exists purely to suppress Clang static analyzer warnings that
	this ivar is unused (but may be used by categories, which it is).
	FIXME: there must be a feature macro we can use to avoid actually building
	this into the app, but I can't find it in docs.
*/
- (BOOL) suppressClangStuff
{
	return !_jsSelf;
}

@end


#import "PlayerEntityLegacyScriptEngine.h"

@implementation OOEquipmentType (Conveniences)

- (OOTechLevelID) effectiveTechLevel
{
	OOTechLevelID			tl;
	id						missionVar = nil;
	
	tl = [self techLevel];
	if (tl == kOOVariableTechLevel)
	{
		missionVar = [PLAYER missionVariableForKey:[@"mission_TL_FOR_" stringByAppendingString:[self identifier]]];
		tl = OOUIntegerFromObject(missionVar, tl);
	}
	
	return tl;
}

@end
