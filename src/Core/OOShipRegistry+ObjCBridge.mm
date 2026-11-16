/*

OOShipRegistry+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, bead oo-3bgz): the Objective-C OOShipRegistry facade. Every method
forwards to cxx::OOShipRegistry in one line. See OOShipRegistry+ObjCBridge.h.

Copyright (C) 2008-2013 Jens Ayton and contributors

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

#import "OOShipRegistry.h"

#include "oofnd/objc/OOObjCPeer.h"

namespace {

// Never destroyed: a facade may be released while the process exits.
oo::ObjCPeers& Peers()
{
    static oo::ObjCPeers* peers = new oo::ObjCPeers;
    return *peers;
}

// The cached facade of the current registry, retained once (amendment oo-r7m0 item 5).
OOShipRegistry* sFacade = nil;
cxx::OOShipRegistry* sFacadeRegistry = nullptr;

} // namespace

@interface OOShipRegistry (OOObjCBridgePrivate)

- (id)initWithCxxRegistry:(cxx::OOShipRegistry*)registry;

@end

@implementation OOShipRegistry

// Inside the @implementation for the private ivar.
OOShipRegistry* oo::ToObjC(cxx::OOShipRegistry* registry)
{
    return Peers().peerFor(registry, [registry] { return [[OOShipRegistry alloc] initWithCxxRegistry:registry]; });
}

cxx::OOShipRegistry* oo::ToCxx(OOShipRegistry* registry)
{
    if (registry == nil)
        return nullptr;
    return registry->_cxxRegistry.get();
}

+ (OOShipRegistry*)sharedRegistry
{
    cxx::OOShipRegistry* registry = cxx::OOShipRegistry::sharedRegistry();
    if (registry != sFacadeRegistry) {
        // A previous registry's facade is kept: its registry was never freed either.
        sFacade = [oo::ToObjC(registry) retain];
        sFacadeRegistry = registry;
    }
    return sFacade;
}

+ (void)reload
{
    cxx::OOShipRegistry::reload();
}

- (id)initWithCxxRegistry:(cxx::OOShipRegistry*)registry
{
    self = [super init];
    if (self != nil)
        _cxxRegistry = oo::Ref<cxx::OOShipRegistry>(registry);
    return self;
}

- (void)dealloc
{
    Peers().forget(_cxxRegistry.get());
    [super dealloc];
}

- (oo::PList)cxx_shipInfoForKey:(const std::string&)key
{
    return _cxxRegistry->shipInfoForKey(key);
}

- (void)cxx_setShipInfoForKey:(const std::string&)key with:(const oo::PList&)newShipData
{
    _cxxRegistry->setShipInfoForKey(key, newShipData);
}

- (oo::PList)cxx_effectInfoForKey:(const std::string&)key
{
    return _cxxRegistry->effectInfoForKey(key);
}

- (oo::PList)cxx_shipyardInfoForKey:(const std::string&)key
{
    return _cxxRegistry->shipyardInfoForKey(key);
}

- (OOProbabilitySet*)cxx_probabilitySetForRole:(const std::string&)role
{
    return _cxxRegistry->probabilitySetForRole(role);
}

- (oo::PList)cxx_demoShipKeys
{
    return _cxxRegistry->demoShipKeys();
}

- (std::vector<std::string>)cxx_playerShipKeys
{
    return _cxxRegistry->playerShipKeys();
}

@end

@implementation OOShipRegistry (OOConveniences)

- (std::vector<std::string>)cxx_shipKeys
{
    return _cxxRegistry->shipKeys();
}

- (std::vector<std::string>)cxx_shipRoles
{
    return _cxxRegistry->shipRoles();
}

- (std::vector<std::string>)cxx_shipKeysWithRole:(const std::string&)role
{
    return _cxxRegistry->shipKeysWithRole(role);
}

- (std::optional<std::string>)cxx_randomShipKeyForRole:(const std::string&)role
{
    return _cxxRegistry->randomShipKeyForRole(role);
}

@end
