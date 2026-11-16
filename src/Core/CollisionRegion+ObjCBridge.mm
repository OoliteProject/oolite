/*

CollisionRegion+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, bead oo-44gg): the Objective-C CollisionRegion facade over
cxx::CollisionRegion. Every method forwards to its C++ member: arguments that were
CollisionRegion * go through oo::ToCxx. The two initialisers make and own the C++ region and
record the facade as its peer (ADR-0056 amendment oo-86ek). Deleted with
CollisionRegion+ObjCBridge.h.

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

#import "CollisionRegion.h"

#include "oofnd/objc/OOObjCPeer.h"

namespace {

// Never destroyed: a facade may be released while the process exits.
oo::ObjCPeers& Peers()
{
    static oo::ObjCPeers* peers = new oo::ObjCPeers;
    return *peers;
}

} // namespace

@interface CollisionRegion (OOObjCBridgePrivate)

- (id)initWithCxxRegion:(cxx::CollisionRegion*)region;
- (id)adoptCxxRegion:(oo::Ref<cxx::CollisionRegion>)region;

@end

@implementation CollisionRegion

// Inside the @implementation for the private ivar.
CollisionRegion* oo::ToObjC(cxx::CollisionRegion* region)
{
    return Peers().peerFor(region, [region] { return [[CollisionRegion alloc] initWithCxxRegion:region]; });
}

cxx::CollisionRegion* oo::ToCxx(CollisionRegion* region)
{
    if (region == nil)
        return nullptr;
    return region->_cxxRegion.get();
}

- (id)initWithCxxRegion:(cxx::CollisionRegion*)region
{
    self = [super init];
    if (self != nil)
        _cxxRegion = oo::Ref<cxx::CollisionRegion>(region);
    return self;
}

// The facade made by an initialiser owns its new C++ region and is its peer.
- (id)adoptCxxRegion:(oo::Ref<cxx::CollisionRegion>)region
{
    self = [super init];
    if (self == nil)
        return nil;

    _cxxRegion = std::move(region);
    @autoreleasepool {
        Peers().peerFor(_cxxRegion.get(), [self] { return [self retain]; });
    }
    return self;
}

- (id)initAsUniverse
{
    return [self adoptCxxRegion:oo::makeRef<cxx::CollisionRegion>(cxx::CollisionRegion::AsUniverse { })];
}

- (id)initAtLocation:(HPVector)locn withRadius:(GLfloat)rad withinRegion:(CollisionRegion*)otherRegion
{
    return [self adoptCxxRegion:oo::makeRef<cxx::CollisionRegion>(locn, rad, oo::ToCxx(otherRegion))];
}

- (void)dealloc
{
    Peers().forget(_cxxRegion.get());
    [super dealloc];
}

- (std::optional<std::string>)cxx_descriptionComponents
{
    return _cxxRegion->descriptionComponents();
}

- (void)clearSubregions
{
    _cxxRegion->clearSubregions();
}

- (void)addSubregionAtPosition:(HPVector)pos withRadius:(GLfloat)rad
{
    _cxxRegion->addSubregionAtPosition(pos, rad);
}

- (void)clearEntityList
{
    _cxxRegion->clearEntityList();
}

- (void)addEntity:(Entity*)ent
{
    _cxxRegion->addEntity(ent);
}

- (BOOL)checkEntity:(Entity*)ent
{
    return _cxxRegion->checkEntity(ent);
}

- (void)findCollisions
{
    _cxxRegion->findCollisions();
}

- (void)findShadowedEntities
{
    _cxxRegion->findShadowedEntities();
}

- (std::string)collisionDescription
{
    return _cxxRegion->collisionDescription();
}

- (std::optional<std::string>)debugOut
{
    return _cxxRegion->debugOut();
}

@end
