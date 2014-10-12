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


// likely maximum number of planetinfo properties to be applied to a system
// just for efficiency - no harm in exceeding it
#define OO_LIKELY_PROPERTIES_PER_SYSTEM 50

@interface OOSystemDescriptionManager (OOPrivate)
- (void) setProperties:(NSDictionary *)properties inDescription:(OOSystemDescriptionEntry *)desc;
- (NSDictionary *) calculatePropertiesForSystemKey:(NSString *)key;
- (void) updateCacheEntry:(NSUInteger)i;
- (void) updateCacheEntry:(NSUInteger)i forProperty:(NSString *)property;
- (id) getProperty:(NSString *)property forSystemKey:(NSString *)key withUniversal:(BOOL)universal;

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
		}
		propertiesInUse = [[NSMutableSet alloc] initWithCapacity:OO_LIKELY_PROPERTIES_PER_SYSTEM];

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
	}
	DESTROY(propertiesInUse);
	[super dealloc];
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


- (void) setProperty:(NSString *)property forSystemKey:(NSString *)key andLayer:(OOSystemLayer)layer toValue:(id)value
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


- (id) getProperty:(NSString *)property1 orProperty:(NSString *)property2 forSystemKey:(NSString *)key
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
	if (result == nil)
	{
		result = [universalProperties objectForKey:property1];
	}
	if (result == nil)
	{
		result = [universalProperties objectForKey:property2];
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
	BOOL interstellar = [key hasPrefix:@"interstellar:"];
	foreach (property, propertiesInUse)
	{
		// don't use universal properties on interstellar specific regions
		id val = [self getProperty:property forSystemKey:key withUniversal:!interstellar];

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
	if (property == nil)
	{
		[layers[layer] removeObjectForKey:property];
	}
	else
	{
		[layers[layer] setObject:value forKey:property];
	}
}


- (id) getProperty:(NSString *)property forLayer:(OOSystemLayer)layer
{
	return [layers[layer] objectForKey:property];
}

@end
