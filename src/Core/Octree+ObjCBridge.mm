/*

Octree+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, bead oo-novu): the Objective-C Octree facade over cxx::Octree.
Every method forwards to its C++ member: arguments that were Octree * go through oo::ToCxx,
results that were Octree * come back through oo::ToObjC. -cxx_initWithDictionary: makes and owns
the C++ octree and records the facade as its peer (ADR-0056 amendment oo-86ek), or answers nil as
before. Deleted with Octree+ObjCBridge.h.

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

#import "Octree.h"
#include "oofnd/objc/OOException.h"

#include "oofnd/objc/OOObjCPeer.h"

namespace {

// Never destroyed: a facade may be released while the process exits.
oo::ObjCPeers& Peers()
{
    static oo::ObjCPeers* peers = new oo::ObjCPeers;
    return *peers;
}

} // namespace

@interface Octree (OOObjCBridgePrivate)

- (id)initWithCxxOctree:(cxx::Octree*)octree;

@end

@implementation Octree

// Inside the @implementation for the private ivar.
Octree* oo::ToObjC(cxx::Octree* octree)
{
    return Peers().peerFor(octree, [octree] { return [[Octree alloc] initWithCxxOctree:octree]; });
}

cxx::Octree* oo::ToCxx(Octree* octree)
{
    if (octree == nil)
        return nullptr;
    return octree->_cxxOctree.get();
}

- (id)init
{
    // -init makes no sense, since octrees are immutable.
    [self release];
    [OOException raise:OOInternalInconsistencyException format:"Call of invalid initializer %s", __FUNCTION__];
    return nil;
}

- (id)initWithCxxOctree:(cxx::Octree*)octree
{
    self = [super init];
    if (self != nil)
        _cxxOctree = oo::Ref<cxx::Octree>(octree);
    return self;
}

- (id)cxx_initWithDictionary:(const oo::PList&)representation
{
    oo::Ref<cxx::Octree> octree = cxx::Octree::initWithDictionary(representation);
    if (octree.get() == nullptr) {
        // Invalid representation.
        [self release];
        return nil;
    }

    self = [super init];
    if (self == nil)
        return nil;

    _cxxOctree = std::move(octree);
    @autoreleasepool {
        Peers().peerFor(_cxxOctree.get(), [self] { return [self retain]; });
    }
    return self;
}

- (void)dealloc
{
    Peers().forget(_cxxOctree.get());
    [super dealloc];
}

- (Octree*)octreeScaledBy:(GLfloat)factor
{
    return oo::ToObjC(_cxxOctree->octreeScaledBy(factor));
}

#ifndef OODEBUGLDRAWING_DISABLE

- (void)drawOctree
{
    _cxxOctree->drawOctree();
}

- (void)drawOctreeCollisions
{
    _cxxOctree->drawOctreeCollisions();
}

#endif

- (GLfloat)isHitByLine:(Vector)v0 v1:(Vector)v1
{
    return _cxxOctree->isHitByLine(v0, v1);
}

- (BOOL)isHitByOctree:(Octree*)other withOrigin:(Vector)v0 andIJK:(Triangle)ijk
{
    return _cxxOctree->isHitByOctree(oo::ToCxx(other), v0, ijk);
}

- (BOOL)isHitByOctree:(Octree*)other withOrigin:(Vector)v0 andIJK:(Triangle)ijk s1:(GLfloat)s1 s2:(GLfloat)s2
{
    return _cxxOctree->isHitByOctree(oo::ToCxx(other), v0, ijk, s1, s2);
}

- (oo::PList)cxx_dictionaryRepresentation
{
    return _cxxOctree->dictionaryRepresentation();
}

- (GLfloat)volume
{
    return _cxxOctree->volume();
}

- (Vector)randomPoint
{
    return _cxxOctree->randomPoint();
}

#ifndef NDEBUG
- (size_t)totalSize
{
    return _cxxOctree->totalSize();
}
#endif

@end
