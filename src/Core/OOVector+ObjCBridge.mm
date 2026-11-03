/*

OOVector+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, bead oo-86ek): the Objective-C OONativeVector facade over
cxx::OONativeVector. Every method forwards to its C++ member. -initWithVector: makes and owns the
C++ box and records itself as its facade, as callers still make boxes with alloc/init.
Deleted with OOVector+ObjCBridge.h.

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

#import "OOMaths.h"

#include "oofnd/objc/OOObjCPeer.h"

namespace {

// Never destroyed: a facade may be released while the process exits.
oo::ObjCPeers& Peers()
{
    static oo::ObjCPeers* peers = new oo::ObjCPeers;
    return *peers;
}

} // namespace

@interface OONativeVector (OOObjCBridgePrivate)

- (id)initWithCxxVector:(cxx::OONativeVector*)vector;

@end

@implementation OONativeVector

// Inside the @implementation for the private ivar.
OONativeVector* oo::ToObjC(cxx::OONativeVector* vector)
{
    return Peers().peerFor(vector, [vector] { return [[OONativeVector alloc] initWithCxxVector:vector]; });
}

cxx::OONativeVector* oo::ToCxx(OONativeVector* vector)
{
    if (vector == nil)
        return nullptr;
    return vector->_cxxVector.get();
}

- (id)initWithCxxVector:(cxx::OONativeVector*)vector
{
    self = [super init];
    if (self != nil)
        _cxxVector = oo::Ref<cxx::OONativeVector>(vector);
    return self;
}

- (id)initWithVector:(Vector)vect
{
    self = [super init];
    if (EXPECT_NOT(self == nil))
        return nil;

    _cxxVector = oo::makeRef<cxx::OONativeVector>(vect);
    @autoreleasepool {
        Peers().peerFor(_cxxVector.get(), [self] { return [self retain]; });
    }

    return self;
}

- (void)dealloc
{
    Peers().forget(_cxxVector.get());
    [super dealloc];
}

- (Vector)getVector
{
    return _cxxVector->getVector();
}

@end
