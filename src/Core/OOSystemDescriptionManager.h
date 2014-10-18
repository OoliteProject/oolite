/*

OOSystemDescriptionManager.h

Class responsible for planet description data.

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

#import "OOCocoa.h"
#import "OOTypes.h"
#import "legacy_random.h"

typedef enum
{
	OO_LAYER_CORE = 0,
	OO_LAYER_OXP_STATIC = 1,
	OO_LAYER_OXP_DYNAMIC = 2,
	OO_LAYER_OXP_PRIORITY = 3
} OOSystemLayer;

#define OO_SYSTEM_LAYERS        4
#define OO_SYSTEMS_PER_GALAXY	(kOOMaximumSystemID+1)
#define OO_GALAXIES_AVAILABLE	8
#define OO_SYSTEMS_AVAILABLE    OO_SYSTEMS_PER_GALAXY * OO_GALAXIES_AVAILABLE
// don't bother caching interstellar properties
#define OO_SYSTEM_CACHE_LENGTH  OO_SYSTEMS_AVAILABLE

@interface OOSystemDescriptionEntry : NSObject
{
@private
	NSMutableDictionary			*layers[OO_SYSTEM_LAYERS];
}

- (void) setProperty:(NSString *)property forLayer:(OOSystemLayer)layer toValue:(id)value;
- (id) getProperty:(NSString *)property forLayer:(OOSystemLayer)layer;

@end


@interface OOSystemDescriptionManager : NSObject
{
@private
	NSMutableDictionary			*universalProperties;
	OOSystemDescriptionEntry	*interstellarSpace;
	NSMutableDictionary			*systemDescriptions;
	NSMutableDictionary			*propertyCache[OO_SYSTEM_CACHE_LENGTH];
	NSMutableSet				*propertiesInUse;
}

- (void) setUniversalProperties:(NSDictionary *)properties;
- (void) setInterstellarProperties:(NSDictionary *)properties;

// this is used by planetinfo.plist and has default layer 1
- (void) setProperties:(NSDictionary *)properties forSystemKey:(NSString *)key;

// this is used by Javascript property setting
- (void) setProperty:(NSString *)property forSystemKey:(NSString *)key andLayer:(OOSystemLayer)layer toValue:(id)value;

- (NSDictionary *) getPropertiesForSystemKey:(NSString *)key;
- (NSDictionary *) getPropertiesForCurrentSystem;
- (id) getProperty:(NSString *)property forSystemKey:(NSString *)key;
- (id) getProperty:(NSString *)property forSystem:(OOSystemID)s inGalaxy:(OOGalaxyID)g;

- (NSPoint) getCoordinatesForSystem:(OOSystemID)s inGalaxy:(OOGalaxyID)g;

- (Random_Seed) getRandomSeedForCurrentSystem;
- (Random_Seed) getRandomSeedForSystem:(OOSystemID)s inGalaxy:(OOGalaxyID)g;

@end


