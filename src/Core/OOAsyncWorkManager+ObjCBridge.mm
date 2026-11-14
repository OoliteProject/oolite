/*

OOAsyncWorkManager+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, bead oo-x2wy): the Objective-C OOAsyncWorkManager facade over
cxx::OOAsyncWorkManager. Every method forwards to its C++ member. Deleted with
OOAsyncWorkManager+ObjCBridge.h.


Copyright (C) 2009-2013 Jens Ayton

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

#import "OOAsyncWorkManager.h"

#include "oofnd/objc/OOObjCPeer.h"

namespace {

// Never destroyed: a facade may be released while the process exits.
oo::ObjCPeers& Peers()
{
    static oo::ObjCPeers* peers = new oo::ObjCPeers;
    return *peers;
}

} // namespace

@interface OOAsyncWorkManager (OOObjCBridgePrivate)

- (id)initWithCxxManager:(cxx::OOAsyncWorkManager*)manager;

@end

@implementation OOAsyncWorkManager

// Inside the @implementation for the private ivar.
OOAsyncWorkManager* oo::ToObjC(cxx::OOAsyncWorkManager* manager)
{
    return Peers().peerFor(manager, [manager] { return [[OOAsyncWorkManager alloc] initWithCxxManager:manager]; });
}

cxx::OOAsyncWorkManager* oo::ToCxx(OOAsyncWorkManager* manager)
{
    if (manager == nil)
        return nullptr;
    return manager->_cxxManager.get();
}

- (id)initWithCxxManager:(cxx::OOAsyncWorkManager*)manager
{
    self = [super init];
    if (self != nil)
        _cxxManager = oo::Ref<cxx::OOAsyncWorkManager>(manager);
    return self;
}

- (void)dealloc
{
    Peers().forget(_cxxManager.get());
    [super dealloc];
}

+ (OOAsyncWorkManager*)sharedAsyncWorkManager
{
    // One facade for the life of the process, as there was one object (amendment oo-r7m0, item 5).
    // Two threads racing here get the same facade from the peer table, and retain it twice.
    static OOAsyncWorkManager* facade = nil;
    if (facade == nil)
        facade = [oo::ToObjC(cxx::OOAsyncWorkManager::sharedAsyncWorkManager()) retain];
    return facade;
}

- (BOOL)addTask:(id<OOAsyncWorkTask>)task priority:(OOAsyncWorkPriority)priority
{
    return _cxxManager->addTask(task, priority);
}

- (void)completePendingTasks
{
    _cxxManager->completePendingTasks();
}

- (void)waitForTaskToComplete:(id<OOAsyncWorkTask>)task
{
    _cxxManager->waitForTaskToComplete(task);
}

@end
