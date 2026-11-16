/*

OOSystemDescriptionManager+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, bead oo-0sr1): the Objective-C OOSystemDescriptionManager
facade. See OOSystemDescriptionManager+ObjCBridge.h.

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

#include "oofnd/objc/OOObjCPeer.h"

namespace {

// Never destroyed: a facade may be released while the process exits.
oo::ObjCPeers& Peers()
{
    static oo::ObjCPeers* peers = new oo::ObjCPeers;
    return *peers;
}

} // namespace

@interface OOSystemDescriptionManager (OOObjCBridgePrivate)

- (id)initWithCxxManager:(cxx::OOSystemDescriptionManager*)manager;

@end

@implementation OOSystemDescriptionManager

// Inside the @implementation for the private ivar.
OOSystemDescriptionManager* oo::ToObjC(cxx::OOSystemDescriptionManager* manager)
{
    return Peers().peerFor(manager, [manager] { return [[OOSystemDescriptionManager alloc] initWithCxxManager:manager]; });
}

cxx::OOSystemDescriptionManager* oo::ToCxx(OOSystemDescriptionManager* manager)
{
    if (manager == nil)
        return nullptr;
    return manager->_cxxManager.get();
}

- (id)init
{
    // A new manager (ResourceManager's), recorded as its facade.
    self = [super init];
    if (self != nil) {
        _cxxManager = oo::makeRef<cxx::OOSystemDescriptionManager>();
        @autoreleasepool {
            Peers().peerFor(_cxxManager.get(), [self] { return [self retain]; });
        }
    }
    return self;
}

- (id)initWithCxxManager:(cxx::OOSystemDescriptionManager*)manager
{
    self = [super init];
    if (self != nil)
        _cxxManager = oo::Ref<cxx::OOSystemDescriptionManager>(manager);
    return self;
}

- (void)dealloc
{
    Peers().forget(_cxxManager.get());
    [super dealloc];
}

- (void)buildRouteCache
{
    _cxxManager->buildRouteCache();
}
- (void)cxx_setUniversalProperties:(const oo::PList&)properties
{
    _cxxManager->setUniversalProperties(properties);
}
- (void)cxx_setInterstellarProperties:(const oo::PList&)properties
{
    _cxxManager->setInterstellarProperties(properties);
}

- (void)cxx_setProperties:(const oo::PList&)properties forSystemKey:(const std::string&)key
{
    _cxxManager->setProperties(properties, key);
}

- (void)cxx_setProperty:(const std::string&)property forSystemKey:(const std::string&)key andLayer:(OOSystemLayer)layer toValue:(const oo::PList&)value fromManifest:(const std::optional<std::string>&)manifest
{
    _cxxManager->setProperty(property, key, layer, value, manifest);
}

- (void)cxx_importScriptedChanges:(const oo::PList&)scripted
{
    _cxxManager->importScriptedChanges(scripted);
}
- (void)cxx_importLegacyScriptedChanges:(const oo::PList&)scripted
{
    _cxxManager->importLegacyScriptedChanges(scripted);
}
- (oo::PList)cxx_exportScriptedChanges
{
    return _cxxManager->exportScriptedChanges();
}

- (oo::PList)cxx_getPropertiesForSystemKey:(const std::string&)key
{
    return _cxxManager->getPropertiesForSystemKey(key);
}

- (oo::PList)cxx_getPropertiesForSystem:(OOSystemID)s inGalaxy:(OOGalaxyID)g
{
    return _cxxManager->getPropertiesForSystem(s, g);
}

- (oo::PList)cxx_getPropertiesForCurrentSystem
{
    return _cxxManager->getPropertiesForCurrentSystem();
}

- (oo::PList)cxx_getProperty:(const std::string&)property forSystemKey:(const std::string&)key
{
    return _cxxManager->getProperty(property, key);
}

- (oo::PList)cxx_getProperty:(const std::string&)property forSystem:(OOSystemID)s inGalaxy:(OOGalaxyID)g
{
    return _cxxManager->getProperty(property, s, g);
}

- (NSPoint)getCoordinatesForSystem:(OOSystemID)s inGalaxy:(OOGalaxyID)g
{
    return _cxxManager->getCoordinatesForSystem(s, g);
}

- (std::vector<OOSystemID>)cxx_getNeighbourIDsForSystem:(OOSystemID)s inGalaxy:(OOGalaxyID)g
{
    return _cxxManager->getNeighbourIDsForSystem(s, g);
}

- (Random_Seed)getRandomSeedForCurrentSystem
{
    return _cxxManager->getRandomSeedForCurrentSystem();
}

- (Random_Seed)getRandomSeedForSystem:(OOSystemID)s inGalaxy:(OOGalaxyID)g
{
    return _cxxManager->getRandomSeedForSystem(s, g);
}

@end
