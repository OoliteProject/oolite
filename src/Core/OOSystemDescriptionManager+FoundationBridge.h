/*

OOSystemDescriptionManager+FoundationBridge.h

TRANSITIONAL (proposed ADR-0043, "Transitional bridges"; bead oo-868e, made by chunk oo-3rb.107 and
extended by its later chunks). OOSystemDescriptionManager's Foundation-typed API as it was before
its sweep, with the same selector names and types, forwarding to the cxx_ API in
OOSystemDescriptionManager.h. It exists so that OOSystemDescriptionManager's callers compile
unchanged; each caller moves to the cxx_ API in its own sweep bead. When `git grep` finds no caller
of anything declared here, the bridge bead deletes this file, OOSystemDescriptionManager+
FoundationBridge.mm, its line in Core/meson.build and the #import at the end of
OOSystemDescriptionManager.h. Never add to it outside the oo-868e chunks; never call it from
migrated code. oo-qps (the removal of gnustep-base) cannot compile while it exists.

Registry: src/oofnd/README.md, "Transitional bridges".

Oolite
Copyright (C) 2004-2013 Giles C Williams and contributors (OOSystemDescriptionManager.h)

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

// Imported only from the end of OOSystemDescriptionManager.h (which declares everything used
// here); never import it directly, and never import OOSystemDescriptionManager.h from it (a cycle).
#ifndef OOSYSTEMDESCRIPTIONMANAGER_FOUNDATIONBRIDGE_H
#define OOSYSTEMDESCRIPTIONMANAGER_FOUNDATIONBRIDGE_H

@interface OOSystemDescriptionManager (OOFoundationBridge)

// oo-3rb.107: scripted changes
- (void)importScriptedChanges:(NSDictionary*)scripted; // -> -cxx_importScriptedChanges:
- (void)importLegacyScriptedChanges:(NSDictionary*)scripted; // -> -cxx_importLegacyScriptedChanges:
- (NSDictionary*)exportScriptedChanges; // -> -cxx_exportScriptedChanges

// oo-3rb.108: storage and write side
- (void)setUniversalProperties:(NSDictionary*)properties; // -> -cxx_setUniversalProperties:
- (void)setInterstellarProperties:(NSDictionary*)properties; // -> -cxx_setInterstellarProperties:
- (void)setProperties:(NSDictionary*)properties forSystemKey:(NSString*)key; // -> -cxx_setProperties:forSystemKey:
- (void)setProperty:(NSString*)property forSystemKey:(NSString*)key andLayer:(OOSystemLayer)layer toValue:(id)value fromManifest:(NSString*)manifest; // -> -cxx_setProperty:forSystemKey:andLayer:toValue:fromManifest:

// oo-3rb.109: property cache and read side
- (NSDictionary*)getPropertiesForSystemKey:(NSString*)key; // -> -cxx_getPropertiesForSystemKey:
- (NSDictionary*)getPropertiesForSystem:(OOSystemID)s inGalaxy:(OOGalaxyID)g; // -> -cxx_getPropertiesForSystem:inGalaxy:
- (NSDictionary*)getPropertiesForCurrentSystem; // -> -cxx_getPropertiesForCurrentSystem
- (id)getProperty:(NSString*)property forSystemKey:(NSString*)key; // -> -cxx_getProperty:forSystemKey:
- (id)getProperty:(NSString*)property forSystem:(OOSystemID)s inGalaxy:(OOGalaxyID)g; // -> -cxx_getProperty:forSystem:inGalaxy:
- (NSArray*)getNeighbourIDsForSystem:(OOSystemID)s inGalaxy:(OOGalaxyID)g; // -> -cxx_getNeighbourIDsForSystem:inGalaxy:

@end

#endif // OOSYSTEMDESCRIPTIONMANAGER_FOUNDATIONBRIDGE_H
