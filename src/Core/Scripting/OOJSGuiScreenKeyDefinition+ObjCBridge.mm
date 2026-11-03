/*

OOJSGuiScreenKeyDefinition+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, bead oo-xg7g): the Objective-C OOJSGuiScreenKeyDefinition facade;
see OOJSGuiScreenKeyDefinition+ObjCBridge.h. Each method forwards in one line to
cxx::OOJSGuiScreenKeyDefinition.


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

#import "OOJSGuiScreenKeyDefinition.h"

#include "oofnd/objc/OOObjCPeer.h"

namespace {

// Never destroyed: a facade may be released while the process exits.
oo::ObjCPeers& Peers()
{
    static oo::ObjCPeers* peers = new oo::ObjCPeers;
    return *peers;
}

} // namespace

@implementation OOJSGuiScreenKeyDefinition

// Inside the @implementation for the private ivar.
::OOJSGuiScreenKeyDefinition* oo::ToObjC(cxx::OOJSGuiScreenKeyDefinition* definition)
{
    return Peers().peerFor(definition, [] { return (id)nil; });
}

cxx::OOJSGuiScreenKeyDefinition* oo::ToCxx(::OOJSGuiScreenKeyDefinition* definition)
{
    if (definition == nil)
        return nullptr;
    return definition->_cxxDefinition.get();
}

- (id)init
{
    self = [super init];
    if (self != nil) {
        _cxxDefinition = oo::makeRef<cxx::OOJSGuiScreenKeyDefinition>();
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

- (std::optional<std::string>)cxx_name
{
    return _cxxDefinition->name();
}
- (void)cxx_setName:(const std::optional<std::string>&)name
{
    _cxxDefinition->setName(name);
}
- (oo::PList)registerKeys
{
    return _cxxDefinition->registerKeys();
}
- (void)setRegisterKeys:(const oo::PList&)registerKeys
{
    _cxxDefinition->setRegisterKeys(registerKeys);
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
- (void)runCallback:(const std::string&)key
{
    _cxxDefinition->runCallback(key);
}
- (OOComparisonResult)interfaceCompare:(OOJSGuiScreenKeyDefinition*)other
{
    return _cxxDefinition->interfaceCompare(oo::ToCxx(other));
}

@end
