/*

OOJSPopulatorDefinition+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, bead oo-1h0h): the Objective-C OOJSPopulatorDefinition facade;
see OOJSPopulatorDefinition+ObjCBridge.h. Each method forwards in one line to
cxx::OOJSPopulatorDefinition.


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

#import "OOJSPopulatorDefinition.h"

#include "oofnd/objc/OOObjCPeer.h"

namespace {

// Never destroyed: a facade may be released while the process exits.
oo::ObjCPeers& Peers()
{
    static oo::ObjCPeers* peers = new oo::ObjCPeers;
    return *peers;
}

} // namespace

@implementation OOJSPopulatorDefinition

// Inside the @implementation for the private ivar.
::OOJSPopulatorDefinition* oo::ToObjC(cxx::OOJSPopulatorDefinition* definition)
{
    return Peers().peerFor(definition, [] { return (id)nil; });
}

cxx::OOJSPopulatorDefinition* oo::ToCxx(::OOJSPopulatorDefinition* definition)
{
    if (definition == nil)
        return nullptr;
    return definition->_cxxDefinition.get();
}

- (id)init
{
    self = [super init];
    if (self != nil) {
        _cxxDefinition = oo::makeRef<cxx::OOJSPopulatorDefinition>();
        @autoreleasepool {
            Peers().peerFor(_cxxDefinition.get(), [self] { return [self retain]; });
        }
    }
    return self;
}

- (void)dealloc
{
    Peers().forget(_cxxDefinition.get());
    [super dealloc];
}

- (JSValue)callback
{
    return _cxxDefinition->callback();
}
- (void)setCallback:(JSValueConst)callback
{
    _cxxDefinition->setCallback(callback);
}
- (JSValue)callbackThis
{
    return _cxxDefinition->callbackThis();
}
- (void)setCallbackThis:(JSValueConst)callbackthis
{
    _cxxDefinition->setCallbackThis(callbackthis);
}
- (void)runPopulatorCallback:(HPVector)location
{
    _cxxDefinition->runPopulatorCallback(location);
}

@end
