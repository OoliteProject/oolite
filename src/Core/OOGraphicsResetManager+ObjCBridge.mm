/*

OOGraphicsResetManager+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, bead oo-jpd8): the Objective-C OOGraphicsResetManager facade over
cxx::OOGraphicsResetManager. Every method forwards to its C++ member. Deleted with
OOGraphicsResetManager+ObjCBridge.h.


Copyright (C) 2007-2013 Jens Ayton and contributors

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

#import "OOGraphicsResetManager.h"

#include "oofnd/objc/OOObjCPeer.h"

namespace {

// Never destroyed: a facade may be released while the process exits.
oo::ObjCPeers& Peers()
{
    static oo::ObjCPeers* peers = new oo::ObjCPeers;
    return *peers;
}

} // namespace

@interface OOGraphicsResetManager (OOObjCBridgePrivate)

- (id)initWithCxxManager:(cxx::OOGraphicsResetManager*)manager;

@end

@implementation OOGraphicsResetManager

// Inside the @implementation for the private ivar.
OOGraphicsResetManager* oo::ToObjC(cxx::OOGraphicsResetManager* manager)
{
    return Peers().peerFor(manager, [manager] { return [[OOGraphicsResetManager alloc] initWithCxxManager:manager]; });
}

cxx::OOGraphicsResetManager* oo::ToCxx(OOGraphicsResetManager* manager)
{
    if (manager == nil)
        return nullptr;
    return manager->_cxxManager.get();
}

- (id)initWithCxxManager:(cxx::OOGraphicsResetManager*)manager
{
    self = [super init];
    if (self != nil)
        _cxxManager = oo::Ref<cxx::OOGraphicsResetManager>(manager);
    return self;
}

- (void)dealloc
{
    Peers().forget(_cxxManager.get());
    [super dealloc];
}

+ (OOGraphicsResetManager*)sharedManager
{
    // One facade for the life of the process, as there was one object (amendment oo-r7m0, item 5).
    static OOGraphicsResetManager* facade = nil;
    if (facade == nil)
        facade = [oo::ToObjC(cxx::OOGraphicsResetManager::sharedManager()) retain];
    return facade;
}

- (void)registerClient:(id<OOGraphicsResetClient>)client
{
    _cxxManager->registerClient(client);
}
- (void)unregisterClient:(id<OOGraphicsResetClient>)client
{
    _cxxManager->unregisterClient(client);
}
- (void)resetGraphicsState
{
    _cxxManager->resetGraphicsState();
}

@end
