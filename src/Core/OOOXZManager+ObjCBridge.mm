/*

OOOXZManager+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, bead oo-bwjb): the Objective-C OOOXZManager facade. Every converted
method forwards to cxx::OOOXZManager in one line; the whole class is C++
(OOOXZManager.mm). See OOOXZManager+ObjCBridge.h.

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

#import "OOOXZManager.h"

#include "oofnd/objc/OOObjCPeer.h"

namespace {

// Never destroyed: a facade may be released while the process exits.
oo::ObjCPeers& Peers()
{
    static oo::ObjCPeers* peers = new oo::ObjCPeers;
    return *peers;
}

} // namespace

@interface OOOXZManager (OOObjCBridgePrivate)

- (id)initWithCxxManager:(cxx::OOOXZManager*)manager;

@end

@implementation OOOXZManager

// Inside the @implementation for the private ivar.
OOOXZManager* oo::ToObjC(cxx::OOOXZManager* manager)
{
    return Peers().peerFor(manager, [manager] { return [[OOOXZManager alloc] initWithCxxManager:manager]; });
}

cxx::OOOXZManager* oo::ToCxx(OOOXZManager* manager)
{
    if (manager == nil)
        return nullptr;
    return manager->_cxxManager.get();
}

- (id)initWithCxxManager:(cxx::OOOXZManager*)manager
{
    self = [super init];
    if (self != nil)
        _cxxManager = oo::Ref<cxx::OOOXZManager>(manager);
    return self;
}

- (void)dealloc
{
    Peers().forget(_cxxManager.get());
    [super dealloc];
}

+ (OOOXZManager*)sharedManager
{
    // One facade for the life of the process, as there was one object (amendment oo-r7m0, item 5).
    static OOOXZManager* facade = nil;
    if (facade == nil)
        facade = [oo::ToObjC(cxx::OOOXZManager::sharedManager()) retain];
    return facade;
}

- (std::optional<std::string>)installPath
{
    return _cxxManager->installPath();
}
- (std::optional<std::string>)extractAddOnsPath
{
    return _cxxManager->extractAddOnsPath();
}
- (std::vector<std::string>)additionalAddOnsPaths
{
    return _cxxManager->additionalAddOnsPaths();
}
- (BOOL)updateManifests
{
    return _cxxManager->updateManifests();
}
- (BOOL)cancelUpdate
{
    return _cxxManager->cancelUpdate();
}
- (void)processDownloadEvents
{
    _cxxManager->processDownloadEvents();
}
- (oo::PList)manifests
{
    return _cxxManager->manifests();
}
- (oo::PList)managedOXZs
{
    return _cxxManager->managedOXZs();
}
- (BOOL)isRestarting
{
    return _cxxManager->isRestarting();
}
- (void)gui
{
    _cxxManager->gui();
}
- (BOOL)isAcceptingTextInput
{
    return _cxxManager->isAcceptingTextInput();
}
- (BOOL)isAcceptingGUIInput
{
    return _cxxManager->isAcceptingGUIInput();
}
- (void)processSelection
{
    _cxxManager->processSelection();
}
- (void)processTextInput:(const std::string&)input
{
    _cxxManager->processTextInput(input);
}
- (void)refreshTextInput:(const std::string&)input
{
    _cxxManager->refreshTextInput(input);
}
- (void)processFilterKey
{
    _cxxManager->processFilterKey();
}
- (void)processShowInfoKey
{
    _cxxManager->processShowInfoKey();
}
- (void)processCopyUrlKey
{
    _cxxManager->processCopyUrlKey();
}
- (void)processExtractKey
{
    _cxxManager->processExtractKey();
}
- (OOGUIRow)showInstallOptions
{
    return _cxxManager->showInstallOptions();
}
- (OOGUIRow)showRemoveOptions
{
    return _cxxManager->showRemoveOptions();
}
- (void)showOptionsUpdate
{
    _cxxManager->showOptionsUpdate();
}
- (void)showOptionsPrev
{
    _cxxManager->showOptionsPrev();
}
- (void)showOptionsNext
{
    _cxxManager->showOptionsNext();
}
- (void)processOptionsPrev
{
    _cxxManager->processOptionsPrev();
}
- (void)processOptionsNext
{
    _cxxManager->processOptionsNext();
}

@end

@implementation OOOXZManager (OOPrivateForwarded)

- (std::optional<std::string>)downloadPath
{
    return _cxxManager->downloadPath();
}
- (std::optional<std::string>)extractionBasePathForIdentifier:(const std::string&)identifier andVersion:(const std::string&)version
{
    return _cxxManager->extractionBasePathForIdentifier(identifier, version);
}
- (std::optional<std::string>)humanSize:(NSUInteger)bytes
{
    return _cxxManager->humanSize(bytes);
}
- (BOOL)ensureInstallPath
{
    return _cxxManager->ensureInstallPath();
}
- (BOOL)validateFilter:(const std::string&)input
{
    return _cxxManager->validateFilter(input);
}
- (void)setFilteredList:(const oo::PList&)list
{
    _cxxManager->setFilteredList(list);
}
- (void)setFilter:(const std::string&)filter
{
    _cxxManager->setFilter(filter);
}
- (oo::PList)applyCurrentFilter:(const oo::PList&)list
{
    return _cxxManager->applyCurrentFilter(list);
}
- (void)setProgressStatus:(const std::string&)newStatus
{
    _cxxManager->setProgressStatus(newStatus);
}
- (OOColor*)colorForManifest:(const oo::PList&)manifest
{
    return oo::ToObjC(_cxxManager->colorForManifest(manifest));
}
- (std::optional<std::string>)installStatusForManifest:(const oo::PList&)manifest
{
    return _cxxManager->installStatusForManifest(manifest);
}
- (BOOL)installOXZ:(NSUInteger)item
{
    return _cxxManager->installOXZ(item);
}
- (BOOL)updateAllOXZ
{
    return _cxxManager->updateAllOXZ();
}
- (BOOL)removeOXZ:(NSUInteger)item
{
    return _cxxManager->removeOXZ(item);
}
- (std::string)extractOXZ:(NSUInteger)item
{
    return _cxxManager->extractOXZ(item);
}

@end
