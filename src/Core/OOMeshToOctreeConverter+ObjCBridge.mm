/*

OOMeshToOctreeConverter+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, bead oo-rsk8): the Objective-C OOMeshToOctreeConverter facade
over cxx::OOMeshToOctreeConverter. Every method forwards to its C++ member; the octree it finds
comes back through oo::ToObjC. -initWithCapacity: makes and owns the C++ converter and records the
facade as its peer (ADR-0056 amendment oo-86ek). Deleted with OOMeshToOctreeConverter+ObjCBridge.h.

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

#import "OOMeshToOctreeConverter.h"

#include "oofnd/objc/OOObjCPeer.h"

namespace {

// Never destroyed: a facade may be released while the process exits.
oo::ObjCPeers& Peers()
{
    static oo::ObjCPeers* peers = new oo::ObjCPeers;
    return *peers;
}

} // namespace

@interface OOMeshToOctreeConverter (OOObjCBridgePrivate)

- (id)initWithCxxConverter:(cxx::OOMeshToOctreeConverter*)converter;

@end

@implementation OOMeshToOctreeConverter

// Inside the @implementation for the private ivar.
OOMeshToOctreeConverter* oo::ToObjC(cxx::OOMeshToOctreeConverter* converter)
{
    return Peers().peerFor(converter, [converter] { return [[OOMeshToOctreeConverter alloc] initWithCxxConverter:converter]; });
}

cxx::OOMeshToOctreeConverter* oo::ToCxx(OOMeshToOctreeConverter* converter)
{
    if (converter == nil)
        return nullptr;
    return converter->_cxxConverter.get();
}

- (id)initWithCxxConverter:(cxx::OOMeshToOctreeConverter*)converter
{
    self = [super init];
    if (self != nil)
        _cxxConverter = oo::Ref<cxx::OOMeshToOctreeConverter>(converter);
    return self;
}

- (id)initWithCapacity:(NSUInteger)capacity
{
    self = [super init];
    if (self == nil)
        return nil;

    _cxxConverter = oo::makeRef<cxx::OOMeshToOctreeConverter>(capacity);
    @autoreleasepool {
        Peers().peerFor(_cxxConverter.get(), [self] { return [self retain]; });
    }
    return self;
}

- (void)dealloc
{
    Peers().forget(_cxxConverter.get());
    [super dealloc];
}

+ (instancetype)converterWithCapacity:(NSUInteger)capacity
{
    return oo::ToObjC(cxx::OOMeshToOctreeConverter::converterWithCapacity(capacity));
}

- (std::optional<std::string>)cxx_descriptionComponents
{
    return _cxxConverter->descriptionComponents();
}

- (void)addTriangle:(Triangle)tri
{
    _cxxConverter->addTriangle(tri);
}

- (Octree*)findOctreeToDepth:(NSUInteger)depth
{
    return oo::ToObjC(_cxxConverter->findOctreeToDepth(depth));
}

@end
