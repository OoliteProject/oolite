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

#import "OOFoundation.h"
#import "OOTypes.h"
#import "legacy_random.h"
#import "oofnd/objc/OOObject.h"

#include "oofnd/PList.hpp"
#include "oofnd/StdLib.hpp"
#include "oofnd/objc/OOObjCRef.h"

typedef enum {
    OO_LAYER_CORE = 0,
    OO_LAYER_OXP_STATIC = 1,
    OO_LAYER_OXP_DYNAMIC = 2,
    OO_LAYER_OXP_PRIORITY = 3
} OOSystemLayer;

typedef enum {
    OO_SYSTEMCONCEALMENT_NONE = 0,
    OO_SYSTEMCONCEALMENT_NODATA = 100,
    OO_SYSTEMCONCEALMENT_NONAME = 200,
    OO_SYSTEMCONCEALMENT_NOTHING = 300
} OOSystemConcealment;

#define OO_SYSTEM_LAYERS 4
#define OO_SYSTEMS_PER_GALAXY (kOOMaximumSystemID + 1)
#define OO_GALAXIES_AVAILABLE (kOOMaximumGalaxyID + 1)
#define OO_SYSTEMS_AVAILABLE OO_SYSTEMS_PER_GALAXY* OO_GALAXIES_AVAILABLE
// don't bother caching interstellar properties
#define OO_SYSTEM_CACHE_LENGTH OO_SYSTEMS_AVAILABLE

@interface OOSystemDescriptionEntry : OOObject {
@private
    oo::PList layers[OO_SYSTEM_LAYERS]; // each a Dict: property -> value
}

// value / result null = nil (setting nil removes the property)
- (void)setProperty:(const std::string&)property forLayer:(OOSystemLayer)layer toValue:(const oo::PList&)value;
- (oo::PList)getProperty:(const std::string&)property forLayer:(OOSystemLayer)layer;

@end

/**
 * Note: forSystem: inGalaxy: returns from the (fast) propertyCache
 *
 * forSystemKey calculates the values - but is necessary for
 * interstellar space
 */
@interface OOSystemDescriptionManager : OOObject {
@private
    oo::PList universalProperties; // a Dict: property -> value
    OOSystemDescriptionEntry* interstellarSpace;
    std::map<std::string, oo::ObjCRef<OOSystemDescriptionEntry*>, std::less<>> systemDescriptions;
    oo::PList propertyCache[OO_SYSTEM_CACHE_LENGTH]; // each a Dict: property -> value
    std::set<std::string> propertiesInUse;
    NSPoint coordinatesCache[OO_SYSTEM_CACHE_LENGTH];
    std::vector<OOSystemID> neighbourCache[OO_SYSTEM_CACHE_LENGTH]; // system numbers
    oo::PList scriptedChanges; // a Dict: joined override key -> value
}

// this needs to be re-called every time system coordinates change
// changing system coordinates after plist loading is probably
// too much of a can of worms *anyway*, so currently it's only
// called just after the manager data is loaded.
- (void)buildRouteCache;

// Property dictionaries are oo::PList Dicts whose values are the properties' values (any objects:
// Object nodes where they are not property-list data); a single value is an oo::PList (null = nil).
- (void)cxx_setUniversalProperties:(const oo::PList&)properties;
- (void)cxx_setInterstellarProperties:(const oo::PList&)properties;

// this is used by planetinfo.plist and has default layer 1
- (void)cxx_setProperties:(const oo::PList&)properties forSystemKey:(const std::string&)key;

// this is used by Javascript property setting (manifest nullopt = nil: the change is not saved)
- (void)cxx_setProperty:(const std::string&)property forSystemKey:(const std::string&)key andLayer:(OOSystemLayer)layer toValue:(const oo::PList&)value fromManifest:(const std::optional<std::string>&)manifest;

// The save game's scripted overrides: property lists (Dicts) whose values are the properties'
// values (any objects: Object nodes where they are not property-list data).
- (void)cxx_importScriptedChanges:(const oo::PList&)scripted;
- (void)cxx_importLegacyScriptedChanges:(const oo::PList&)scripted;
- (oo::PList)cxx_exportScriptedChanges; // a Dict, empty when there are none

// Property dictionaries (Dicts; empty for an invalid system) and single values (null = nil).
- (oo::PList)cxx_getPropertiesForSystemKey:(const std::string&)key;
- (oo::PList)cxx_getPropertiesForSystem:(OOSystemID)s inGalaxy:(OOGalaxyID)g;
- (oo::PList)cxx_getPropertiesForCurrentSystem;
- (oo::PList)cxx_getProperty:(const std::string&)property forSystemKey:(const std::string&)key;
- (oo::PList)cxx_getProperty:(const std::string&)property forSystem:(OOSystemID)s inGalaxy:(OOGalaxyID)g;

- (NSPoint)getCoordinatesForSystem:(OOSystemID)s inGalaxy:(OOGalaxyID)g;
- (std::vector<OOSystemID>)cxx_getNeighbourIDsForSystem:(OOSystemID)s inGalaxy:(OOGalaxyID)g; // empty for an invalid system

- (Random_Seed)getRandomSeedForCurrentSystem;
- (Random_Seed)getRandomSeedForSystem:(OOSystemID)s inGalaxy:(OOGalaxyID)g;

@end

/*	TRANSITIONAL (proposed ADR-0043, "Transitional bridges"): the Foundation-typed API as it was
        declared before its sweep (bead oo-868e, chunks oo-3rb.107 ff.), forwarding to the cxx_ methods
        above, so unmigrated callers compile unchanged. Callers move to the cxx_ API in their own sweep
        beads; the bridge goes in its own bead.
*/
#import "OOSystemDescriptionManager+FoundationBridge.h"
