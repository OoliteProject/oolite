/*

OOPlanetDescriptionManager.h

Singleton class responsible for planet description data.

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

#import "OOSystemDescriptionManager.h"
#import "OOStringParsing.h"
#import "OOCollectionExtractors.h"
#import "OOTypes.h"
#import "PlayerEntity.h"
#import "Universe.h"
#import "ResourceManager.h"

// character sequence which can't be in property name, system key or layer
// and is highly unlikely to be in a manifest identifier
static NSString * const kOOScriptedChangeJoiner = @"~|~";

// likely maximum number of planetinfo properties to be applied to a system
// just for efficiency - no harm in exceeding it
#define OO_LIKELY_PROPERTIES_PER_SYSTEM 50

@interface OOSystemDescriptionManager (OOPrivate)
- (void) setProperties:(NSDictionary *)properties inDescription:(OOSystemDescriptionEntry *)desc;
- (NSDictionary *) calculatePropertiesForSystemKey:(NSString *)key;
- (void) updateCacheEntry:(NSUInteger)i;
- (void) updateCacheEntry:(NSUInteger)i forProperty:(NSString *)property;
- (id) getProperty:(NSString *)property forSystemKey:(NSString *)key withUniversal:(BOOL)universal;
/* some planetinfo properties have two ways to specify
 * need to get the one with higher layer (if they're both at the same layer,
 * go with property1) */
- (id) getProperty:(NSString *)property1 orProperty:(NSString *)property2 forSystemKey:(NSString *)key withUniversal:(BOOL)universal;

- (void) saveScriptedChangeToProperty:(NSString *)property forSystemKey:(NSString *)key andLayer:(OOSystemLayer)layer toValue:(id)value fromManifest:(NSString *)manifest;

@end

static NSString *kOOSystemLayerProperty = @"layer";

@implementation OOSystemDescriptionManager

- (id) init
{
	self = [super init];
	if (self != nil)
	{
		universalProperties = [[NSMutableDictionary alloc] initWithCapacity:OO_LIKELY_PROPERTIES_PER_SYSTEM];
		interstellarSpace = [[OOSystemDescriptionEntry alloc] init];
		// assume specific interstellar settings are rare
		systemDescriptions = [[NSMutableDictionary alloc] initWithCapacity:OO_SYSTEM_CACHE_LENGTH];
		for (NSUInteger i=0;i<OO_SYSTEM_CACHE_LENGTH;i++)
		{
			propertyCache[i] = [[NSMutableDictionary alloc] initWithCapacity:OO_LIKELY_PROPERTIES_PER_SYSTEM];
			// hub count of 24 is considerably higher than occurs in
			// standard planetinfo
			neighbourCache[i] = [[NSMutableArray alloc] initWithCapacity:24];
		}
		propertiesInUse = [[NSMutableSet alloc] initWithCapacity:OO_LIKELY_PROPERTIES_PER_SYSTEM];
		scriptedChanges = [[NSMutableDictionary alloc] initWithCapacity:64];
	}
	return self;
}

- (void) dealloc
{
	DESTROY(universalProperties);
	DESTROY(interstellarSpace);
	DESTROY(systemDescriptions);
	for (NSUInteger i=0;i<OO_SYSTEM_CACHE_LENGTH;i++)
	{
		DESTROY(propertyCache[i]);
		DESTROY(neighbourCache[i]);
	}
	DESTROY(propertiesInUse);
	DESTROY(scriptedChanges);
	[super dealloc];
}


- (void) buildRouteCache
{
	NSUInteger i,j,k,jIndex,kIndex;
	// firstly, cache all coordinates
	for (i=0;i<OO_SYSTEM_CACHE_LENGTH;i++)
	{
		coordinatesCache[i] = PointFromString([propertyCache[i] oo_stringForKey:@"coordinates"]);
	}
	// now for each system find its neighbours
	for (i=0;i<OO_GALAXIES_AVAILABLE;i++)
	{
		// one galaxy at a time
		for (j=0;j<OO_SYSTEMS_PER_GALAXY;j++)
		{
			jIndex = j+(i*OO_SYSTEMS_PER_GALAXY);
			for (k=j+1;k<OO_SYSTEMS_PER_GALAXY;k++)
			{
				kIndex = k+(i*OO_SYSTEMS_PER_GALAXY);
				if (distanceBetweenPlanetPositions(coordinatesCache[jIndex].x,coordinatesCache[jIndex].y,coordinatesCache[kIndex].x,coordinatesCache[kIndex].y) <= MAX_JUMP_RANGE)
				{
					// arrays are of system number only
					[neighbourCache[jIndex] addObject:[NSNumber numberWithInt:k]];
					[neighbourCache[kIndex] addObject:[NSNumber numberWithInt:j]];
				}
			}
		}
	}

}


- (void) setUniversalProperties:(NSDictionary *)properties
{
	[universalProperties addEntriesFromDictionary:properties];
	[propertiesInUse addObjectsFromArray:[properties allKeys]];
	for (NSUInteger i = 0; i<OO_SYSTEM_CACHE_LENGTH; i++)
	{
		[self updateCacheEntry:i];
	}
}


- (void) setInterstellarProperties:(NSDictionary *)properties
{
	[self setProperties:properties inDescription:interstellarSpace];
}


- (void) setProperties:(NSDictionary *)properties forSystemKey:(NSString *)key
{
	OOSystemDescriptionEntry *desc = [systemDescriptions objectForKey:key];
	if (desc == nil)
	{
		// create it
		desc = [[[OOSystemDescriptionEntry alloc] init] autorelease];
		[systemDescriptions setObject:desc forKey:key];
	}
	[self setProperties:properties inDescription:desc];
	[propertiesInUse addObjectsFromArray:[properties allKeys]];

	NSArray  *tokens = ScanTokensFromString(key);
	if ([tokens count] == 2 && [tokens oo_unsignedIntegerAtIndex:0] < OO_GALAXIES_AVAILABLE && [tokens oo_unsignedIntegerAtIndex:1] < OO_SYSTEMS_PER_GALAXY)
	{
		OOGalaxyID g = [tokens oo_unsignedIntegerAtIndex:0];
		OOSystemID s = [tokens oo_unsignedIntegerAtIndex:1];
		NSUInteger index = (g * OO_SYSTEMS_PER_GALAXY) + s;
		if (index >= OO_SYSTEM_CACHE_LENGTH)
		{
			OOLog(@"system.description.error",@"'%@' is an invalid system key. This is an internal error. Please report it.",key);
		}
		else
		{
			[self updateCacheEntry:index];
		}
	}
}


- (void) setProperty:(NSString *)property forSystemKey:(NSString *)key andLayer:(OOSystemLayer)layer toValue:(id)value fromManifest:(NSString *)manifest
{
	OOSystemDescriptionEntry *desc = [systemDescriptions objectForKey:key];
	if (desc == nil)
	{
		// create it
		desc = [[[OOSystemDescriptionEntry alloc] init] autorelease];
		[systemDescriptions setObject:desc forKey:key];
	}
	[desc setProperty:property forLayer:layer toValue:value];
	[propertiesInUse addObject:property];

	NSArray  *tokens = ScanTokensFromString(key);
	if ([tokens count] == 2 && [tokens oo_unsignedIntegerAtIndex:0] < OO_GALAXIES_AVAILABLE && [tokens oo_unsignedIntegerAtIndex:1] < OO_SYSTEMS_PER_GALAXY)
	{
		[self saveScriptedChangeToProperty:property forSystemKey:key andLayer:layer toValue:value fromManifest:manifest];
	
		OOGalaxyID g = [tokens oo_unsignedIntegerAtIndex:0];
		OOSystemID s = [tokens oo_unsignedIntegerAtIndex:1];
		NSUInteger index = (g * OO_SYSTEMS_PER_GALAXY) + s;
		if (index >= OO_SYSTEM_CACHE_LENGTH)
		{
			OOLog(@"system.description.error",@"'%@' is an invalid system key. This is an internal error. Please report it.",key);
		}
		else
		{
			[self updateCacheEntry:index forProperty:property];
		}
	}
}


- (void) saveScriptedChangeToProperty:(NSString *)property forSystemKey:(NSString *)key andLayer:(OOSystemLayer)layer toValue:(id)value fromManifest:(NSString *)manifest
{
	// if OXP doesn't have a manifest, cancel saving the change
	if (manifest == nil)
	{
		return;
	}
//	OOLog(@"saving change",@"%@ %@ %@ %d",manifest,key,property,layer);
	NSArray *overrideKey = [NSArray arrayWithObjects:manifest,key,property,[[NSNumber numberWithInt:layer] stringValue],nil];
	// Obj-C copes with NSArray keys to dictionaries fine, but the
	// plist format doesn't, so they can't be saved.
	NSString *overrideKeyStr = [overrideKey componentsJoinedByString:kOOScriptedChangeJoiner];
	if (value != nil)
	{
		[scriptedChanges setObject:value forKey:overrideKeyStr];
	}
	else
	{
		[scriptedChanges removeObjectForKey:overrideKeyStr];
	}
}


- (void) importScriptedChanges:(NSDictionary *)scripted
{
	NSArray *key = nil;
	NSString *keyStr = nil;
	NSString *manifest = nil;
	foreachkey(keyStr, scripted)
	{
		key = [keyStr componentsSeparatedByString:kOOScriptedChangeJoiner];
		if ([key count] == 4)
		{
			manifest = [key oo_stringAtIndex:0];
			if ([ResourceManager manifestForIdentifier:manifest] != nil)
			{
//				OOLog(@"importing",@"%@ -> %@",keyStr,[scripted objectForKey:keyStr]);
				[self setProperty:[key oo_stringAtIndex:2]
					 forSystemKey:[key oo_stringAtIndex:1]
						 andLayer:[key oo_intAtIndex:3]
						  toValue:[scripted objectForKey:keyStr]
					 fromManifest:manifest];
				// and doing this set stores it into the manager's copy
				// of scripted changes
				// this means in theory we could import more than one
			}
			// else OXP not installed, do not load
		}
		else
		{
			OOLog(@"systemManager.import",@"Key '%@' has unexpected format - skipping",keyStr);
		}
	}

}


// import of the old local_planetinfo_overrides dictionary
- (void) importLegacyScriptedChanges:(NSDictionary *)scripted
{
	NSString *systemKey = nil;
	NSString *propertyKey = nil;
	NSString *defaultManifest = @"org.oolite.oolite";
	
	foreachkey(systemKey,scripted)
	{
		NSDictionary *legacyChanges = [scripted oo_dictionaryForKey:systemKey];
		if ([legacyChanges objectForKey:@"sun_gone_nova"] != nil)
		{
			// then this is a change to import even if we don't know
			// if the OXP is still installed
			foreachkey (propertyKey, legacyChanges)
			{
				[self setProperty:propertyKey
					 forSystemKey:systemKey
						 andLayer:OO_LAYER_OXP_DYNAMIC
						  toValue:[legacyChanges objectForKey:propertyKey]
					 fromManifest:defaultManifest];
			}
		}
	}

}


- (NSDictionary *) exportScriptedChanges
{
	return [[scriptedChanges copy] autorelease];
}


- (NSDictionary *) getPropertiesForCurrentSystem
{
	OOSystemID s = [UNIVERSE currentSystemID];
	if (s > 0)
	{
		NSUInteger index = ([PLAYER galaxyNumber] * OO_SYSTEMS_PER_GALAXY) + s;
		if (index >= OO_SYSTEM_CACHE_LENGTH)
		{
			OOLog(@"system.description.error",@"'%u' is an invalid system index for the current system. This is an internal error. Please report it.",index);
			return [NSDictionary dictionary];
		}
		return propertyCache[index];
	}
	else
	{
		OOLog(@"system.description.error",@"getPropertiesForCurrentSystem called while player in interstellar space. This is an internal error. Please report it.");
		// this shouldn't be called for interstellar space
		return [NSDictionary dictionary];
	}
}


- (NSDictionary *) getPropertiesForSystemKey:(NSString *)key
{
	NSArray  *tokens = ScanTokensFromString(key);
	if ([tokens count] == 2 && [tokens oo_unsignedIntegerAtIndex:0] < OO_GALAXIES_AVAILABLE && [tokens oo_unsignedIntegerAtIndex:1] < OO_SYSTEMS_PER_GALAXY)
	{
		OOGalaxyID g = [tokens oo_unsignedIntegerAtIndex:0];
		OOSystemID s = [tokens oo_unsignedIntegerAtIndex:1];
		NSUInteger index = (g * OO_SYSTEMS_PER_GALAXY) + s;
		if (index >= OO_SYSTEM_CACHE_LENGTH)
		{
			OOLog(@"system.description.error",@"'%@' is an invalid system key. This is an internal error. Please report it.",key);
			return [NSDictionary dictionary];
		}
		return propertyCache[index];
	}
	// interstellar spaces aren't cached
	return [self calculatePropertiesForSystemKey:key];
}


- (id) getProperty:(NSString *)property forSystemKey:(NSString *)key
{
	return [self getProperty:property forSystemKey:key withUniversal:YES];
}

- (id) getProperty:(NSString *)property forSystem:(OOSystemID)s inGalaxy:(OOGalaxyID)g
{
	if (s < 0)
	{
		OOLog(@"system.description.error",@"'%d %d' is an invalid system key. This is an internal error. Please report it.",g,s);
		return nil;
	}
	NSUInteger index = (g * OO_SYSTEMS_PER_GALAXY) + s;
	if (index >= OO_SYSTEM_CACHE_LENGTH)
	{
		OOLog(@"system.description.error",@"'%d %d' is an invalid system key. This is an internal error. Please report it.",g,s);
		return nil;
	}
	return [propertyCache[index] objectForKey:property];
}


- (id) getProperty:(NSString *)property forSystemKey:(NSString *)key withUniversal:(BOOL)universal
{
	OOSystemDescriptionEntry *desc = nil;
	if (EXPECT_NOT([key isEqualToString:@"interstellar"]))
	{
		desc = interstellarSpace;
	}
	else
	{
		desc = [systemDescriptions objectForKey:key];
	}
	if (desc == nil)
	{
		return nil;
	}
	id result = nil;
	result = [desc getProperty:property forLayer:OO_LAYER_OXP_PRIORITY];
	if (result == nil)
	{
		result = [desc getProperty:property forLayer:OO_LAYER_OXP_DYNAMIC];
	}
	if (result == nil)
	{
		result = [desc getProperty:property forLayer:OO_LAYER_OXP_STATIC];
	}
	if (result == nil && universal)
	{
		result = [universalProperties objectForKey:property];
	}
	if (result == nil)
	{
		result = [desc getProperty:property forLayer:OO_LAYER_CORE];
	}
	return result;
}


- (id) getProperty:(NSString *)property1 orProperty:(NSString *)property2 forSystemKey:(NSString *)key withUniversal:(BOOL)universal
{
	OOSystemDescriptionEntry *desc = [systemDescriptions objectForKey:key];
	if (desc == nil)
	{
		return nil;
	}
	id result = nil;
	result = [desc getProperty:property1 forLayer:OO_LAYER_OXP_PRIORITY];
	if (result == nil)
	{
		result = [desc getProperty:property2 forLayer:OO_LAYER_OXP_PRIORITY];
	}
	if (result == nil)
	{
		result = [desc getProperty:property1 forLayer:OO_LAYER_OXP_DYNAMIC];
	}
	if (result == nil)
	{
		result = [desc getProperty:property2 forLayer:OO_LAYER_OXP_DYNAMIC];
	}
	if (result == nil)
	{
		result = [desc getProperty:property1 forLayer:OO_LAYER_OXP_STATIC];
	}
	if (result == nil)
	{
		result = [desc getProperty:property2 forLayer:OO_LAYER_OXP_STATIC];
	}
	if (universal)
	{
		if (result == nil)
		{
			result = [universalProperties objectForKey:property1];
		}
		if (result == nil)
		{
			result = [universalProperties objectForKey:property2];
		}
	}
	if (result == nil)
	{
		result = [desc getProperty:property1 forLayer:OO_LAYER_CORE];
	}
	if (result == nil)
	{
		result = [desc getProperty:property2 forLayer:OO_LAYER_CORE];
	}
	return result;
}


- (void) setProperties:(NSDictionary *)properties inDescription:(OOSystemDescriptionEntry *)desc
{
	OOSystemLayer layer = [properties oo_unsignedIntegerForKey:kOOSystemLayerProperty defaultValue:OO_LAYER_OXP_STATIC];
	if (layer > OO_LAYER_OXP_PRIORITY)
	{
		OOLog(@"system.description.error",@"Layer %u is not a valid layer number in system information.",layer);
		layer = OO_LAYER_OXP_PRIORITY;
	}
	NSString *key = nil;
	foreachkey(key, properties)
	{
		if (![key isEqualToString:kOOSystemLayerProperty])
		{
			[desc setProperty:key forLayer:layer toValue:[properties objectForKey:key]];
		}
	}
}


- (NSDictionary *) calculatePropertiesForSystemKey:(NSString *)key
{
	NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithCapacity:OO_LIKELY_PROPERTIES_PER_SYSTEM];
	NSString *property = nil;
	id val = nil;
	BOOL interstellar = [key hasPrefix:@"interstellar:"];
	foreach (property, propertiesInUse)
	{
		// don't use universal properties on interstellar specific regions
		val = [self getProperty:property forSystemKey:key withUniversal:!interstellar];

		if (val != nil)
		{
			[dict setObject:val forKey:property];
		}
		else if (interstellar)
		{
			// interstellar is always overridden by specific regions
			// universal properties for interstellar get picked up here
			val = [self getProperty:property forSystemKey:@"interstellar"];
			if (val != nil)
			{
				[dict setObject:val forKey:property];
			}
		}
	}
	return dict;
}


- (void) updateCacheEntry:(NSUInteger)i
{
	NSAssert(i < OO_SYSTEM_CACHE_LENGTH,@"Invalid cache entry number");
	NSString *key = [NSString stringWithFormat:@"%u %u",i/OO_SYSTEMS_PER_GALAXY,i%OO_SYSTEMS_PER_GALAXY];
	NSDictionary *current = [self calculatePropertiesForSystemKey:key];

	[propertyCache[i] removeAllObjects];
	[propertyCache[i] addEntriesFromDictionary:current];
}


- (void) updateCacheEntry:(NSUInteger)i forProperty:(NSString *)property
{
	NSAssert(i < OO_SYSTEM_CACHE_LENGTH,@"Invalid cache entry number");
	NSString *key = [NSString stringWithFormat:@"%u %u",i/OO_SYSTEMS_PER_GALAXY,i%OO_SYSTEMS_PER_GALAXY];
	id current = [self getProperty:property forSystemKey:key];
	if (current == nil)
	{
		[propertyCache[i] removeObjectForKey:property];
	}
	else
	{
		[propertyCache[i] setObject:current forKey:property];
	}
}


- (NSPoint) getCoordinatesForSystem:(OOSystemID)s inGalaxy:(OOGalaxyID)g
{
	if (s < 0)
	{
		OOLog(@"system.description.error",@"'%d %d' is an invalid system key. This is an internal error. Please report it.",g,s);
		return (NSPoint){0,0};
	}
	NSUInteger index = (g * OO_SYSTEMS_PER_GALAXY) + s;
	if (index >= OO_SYSTEM_CACHE_LENGTH)
	{
		OOLog(@"system.description.error",@"'%d %d' is an invalid system key. This is an internal error. Please report it.",g,s);
		return (NSPoint){0,0};
	}
	return coordinatesCache[index];
}


- (NSArray *) getNeighbourIDsForSystem:(OOSystemID)s inGalaxy:(OOGalaxyID)g
{
	if (s < 0)
	{
		OOLog(@"system.description.error",@"'%d %d' is an invalid system key. This is an internal error. Please report it.",g,s);
		return nil;
	}
	NSUInteger index = (g * OO_SYSTEMS_PER_GALAXY) + s;
	if (index >= OO_SYSTEM_CACHE_LENGTH)
	{
		OOLog(@"system.description.error",@"'%d %d' is an invalid system key. This is an internal error. Please report it.",g,s);
		return nil;
	}
	return neighbourCache[index];
}


- (Random_Seed) getRandomSeedForCurrentSystem
{
	if ([UNIVERSE currentSystemID] < 0)
	{
		return kNilRandomSeed;
	}
	else
	{
		OOSystemID s = [UNIVERSE currentSystemID];
		NSUInteger index = ([PLAYER galaxyNumber] * OO_SYSTEMS_PER_GALAXY) + s;
		if (index >= OO_SYSTEM_CACHE_LENGTH)
		{
			OOLog(@"system.description.error",@"'%u' is an invalid system index for the current system. This is an internal error. Please report it.",index);
			return kNilRandomSeed;
		}
		return RandomSeedFromString([propertyCache[index] oo_stringForKey:@"random_seed"]);
	}
}


- (Random_Seed) getRandomSeedForSystem:(OOSystemID)s inGalaxy:(OOGalaxyID)g
{
	if (s < 0)
	{
		OOLog(@"system.description.error",@"'%d %d' is an invalid system key. This is an internal error. Please report it.",g,s);
		return kNilRandomSeed;
	}
	NSUInteger index = (g * OO_SYSTEMS_PER_GALAXY) + s;
	if (index >= OO_SYSTEM_CACHE_LENGTH)
	{
		OOLog(@"system.description.error",@"'%d %d' is an invalid system key. This is an internal error. Please report it.",g,s);
		return kNilRandomSeed;
	}
	return RandomSeedFromString([propertyCache[index] oo_stringForKey:@"random_seed"]);
}


@end


@interface OOSystemDescriptionEntry (OOPrivate)
- (id) validateProperty:(NSString *)property withValue:(id)value;
@end

@implementation OOSystemDescriptionEntry 

- (id) init
{
	self = [super init];
	if (self != nil)
	{
		for (NSUInteger i=0;i<OO_SYSTEM_LAYERS;i++)
		{
			layers[i] = [[NSMutableDictionary alloc] initWithCapacity:OO_LIKELY_PROPERTIES_PER_SYSTEM];
		}
	}
	return self;
}


- (void) dealloc
{
	for (NSUInteger i=0;i<OO_SYSTEM_LAYERS;i++)
	{
		DESTROY(layers[i]);
	}
	[super dealloc];
}


- (void) setProperty:(NSString *)property forLayer:(OOSystemLayer)layer toValue:(id)value
{
	if (value == nil)
	{
		[layers[layer] removeObjectForKey:property];
	}
	else
	{
		// validate type of object for certain properties
		value = [self validateProperty:property withValue:value];
		// if it's nil now, validation failed and could not be recovered
		// so don't actually set anything
		if (value != nil)
		{
			[layers[layer] setObject:value forKey:property];
		}
	}
}


- (id) getProperty:(NSString *)property forLayer:(OOSystemLayer)layer
{
	return [layers[layer] objectForKey:property];
}


/* Mostly the rest of the game gets a system dictionary from
 * [UNIVERSE currentSystemData] or similar, which means that it uses
 * safe methods like oo_stringForKey: - a few things use a direct call
 * to getProperty for various reasons, so need some type validation
 * here instead. */
- (id) validateProperty:(NSString *)property withValue:(id)value
{
	if ([property isEqualToString:@"coordinates"])
	{
		// must be a string with two numbers in it
		// TODO: convert two element arrays
		if (![value isKindOfClass:[NSString class]])
		{
			OOLog(@"system.description.error",@"'%@' is not a valid format for coordinates",value);
			return nil;
		}
		NSArray		*tokens = ScanTokensFromString((NSString *)value);
		if ([tokens count] != 2)
		{
			OOLog(@"system.description.error",@"'%@' is not a valid format for coordinates (must have exactly two numbers)",value);
			return nil;
		}
	} 
	else if ([property isEqualToString:@"radius"] || [property isEqualToString:@"government"]) 
	{ 
		// read in a context which expects a string, but it's a string representation of a number
		if (![value isKindOfClass:[NSString class]])
		{
			if ([value isKindOfClass:[NSNumber class]])
			{
				return [value stringValue];
			}
			else
			{
				OOLog(@"system.description.error",@"'%@' is not a valid value for '%@' (string required)",value,property);
				return nil;
			}
		}
	}
	else if ([property isEqualToString:@"inhabitant"] || [property isEqualToString:@"inhabitants"] || [property isEqualToString:@"name"] ) 
	{
		// read in a context which expects a string
		if (![value isKindOfClass:[NSString class]])
		{
			OOLog(@"system.description.error",@"'%@' is not a valid value for '%@' (string required)",value,property);
			return nil;
		}
	}

	return value;
}

@end
