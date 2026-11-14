/*

OOSystemDescriptionManager+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, bead oo-0sr1): the Objective-C OOSystemDescriptionManager, a
facade over the C++ cxx::OOSystemDescriptionManager (OOSystemDescriptionManager.h), for callers
that are not converted yet. Its interface is the one OOSystemDescriptionManager.h declared before
the conversion, copied exactly (same selectors, same types), so those callers compile and behave
unchanged; each method forwards to its C++ member. Imported as the last line of
OOSystemDescriptionManager.h; do not import it directly.

        a caller that is                       holds / passes                  crosses with
        -------------------------------------  ------------------------------  ----------------------------
        still Objective-C                      OOSystemDescriptionManager *    nothing
        converted (C++)                        oo::Ref<cxx::OOSystemDescriptionManager>   oo::ToObjC / oo::ToCxx

[[OOSystemDescriptionManager alloc] init] (ResourceManager's) makes a new C++ manager and records
the facade as its peer (amendment oo-vt0o item 1), so oo::ToObjC of it is that facade.
Never add to this file; converted code does not message the facade. Deleted by its deletion bead
once no file outside OOSystemDescriptionManager.* names the Objective-C class.

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

#ifndef OOSYSTEMDESCRIPTIONMANAGER_OBJCBRIDGE_H
#define OOSYSTEMDESCRIPTIONMANAGER_OBJCBRIDGE_H

#import "OOFoundation.h"
#import "oofnd/objc/OOObject.h"

/**
 * Note: forSystem: inGalaxy: returns from the (fast) propertyCache
 *
 * forSystemKey calculates the values - but is necessary for
 * interstellar space
 */
@interface OOSystemDescriptionManager : OOObject {
@private
    oo::Ref<cxx::OOSystemDescriptionManager> _cxxManager;
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

namespace oo {

// The manager's Objective-C facade: its live one, else a new one; autoreleased. nil for null.
OOSystemDescriptionManager* ToObjC(cxx::OOSystemDescriptionManager* manager);
// The C++ manager behind a facade, borrowed (the facade retains it); null for nil.
cxx::OOSystemDescriptionManager* ToCxx(OOSystemDescriptionManager* manager);

} // namespace oo

#endif // OOSYSTEMDESCRIPTIONMANAGER_OBJCBRIDGE_H
