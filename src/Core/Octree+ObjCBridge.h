/*

Octree+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, bead oo-novu): the Objective-C Octree, a facade over the C++
cxx::Octree (Octree.h), for callers that are not converted yet (ShipEntity, PlayerEntity, OOMesh
and its OOCacheManager category, OOMeshToOctreeConverter's result). Its interface is the one
Octree.h declared before the conversion, copied exactly (same selectors, same types), so those
callers compile and behave unchanged; each method forwards to its C++ member. OOOctreeBuilder has
no facade: its one caller, OOMeshToOctreeConverter.mm, uses the C++ class. Imported as the last
line of Octree.h; do not import it directly.

        a caller that is                       holds / passes                  crosses with
        -------------------------------------  ------------------------------  ----------------------------
        still Objective-C                      Octree * (this facade)          nothing: messages as before
        converted (C++)                        oo::Ref<cxx::Octree>, cxx::Octree *
          handing an octree to Objective-C                                      oo::ToObjC(octree)
          taking one from Objective-C                                           oo::ToCxx(objcOctree)

oo::ToObjC gives the octree's one live facade (oo::ObjCPeers), so identity survives a round trip:
oo::ToObjC(oo::ToCxx(o)) == o. Never add to this file; converted code does not message the facade.
Deleted by its deletion bead once no file outside Octree.* names the Objective-C Octree.

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

#ifndef OCTREE_OBJCBRIDGE_H
#define OCTREE_OBJCBRIDGE_H

#import "OOFoundation.h"
#import "oofnd/objc/OOObject.h"

@interface Octree : OOObject {
@private
    oo::Ref<cxx::Octree> _cxxOctree;
}

/*
        - (id) cxx_initWithDictionary:

        Deserialize an octree from cache representation.
        (To make a new octree, build it with OOOctreeBuilder.)
        (bead oo-3rb.292.1; the id -initWithDictionary: that forwarded to it retired with oo-qps.44.)
*/
- (id)cxx_initWithDictionary:(const oo::PList&)dictionary OO_RETURNS_RETAINED;

- (Octree*)octreeScaledBy:(GLfloat)factor;

#ifndef OODEBUGLDRAWING_DISABLE
- (void)drawOctree;
- (void)drawOctreeCollisions;
#endif

- (GLfloat)isHitByLine:(Vector)v0 v1:(Vector)v1;

- (BOOL)isHitByOctree:(Octree*)other withOrigin:(Vector)origin andIJK:(Triangle)ijk;
- (BOOL)isHitByOctree:(Octree*)other withOrigin:(Vector)origin andIJK:(Triangle)ijk s1:(GLfloat)s1 s2:(GLfloat)s2;

- (oo::PList)cxx_dictionaryRepresentation; // the cache representation: a dictionary (-dictionaryRepresentation is a Foundation selector)

- (GLfloat)volume;

- (Vector)randomPoint;

#ifdef OO_DEBUG_MONITOR_ENABLED
- (size_t)totalSize;
#endif

@end

namespace oo {

// The octree's Objective-C facade: its live one, else a new one; autoreleased. nil for null.
Octree* ToObjC(cxx::Octree* octree);
inline Octree* ToObjC(const Ref<cxx::Octree>& octree) { return ToObjC(octree.get()); }

// The C++ octree behind a facade, borrowed (the facade retains it); null for nil.
cxx::Octree* ToCxx(Octree* octree);

} // namespace oo

#endif // OCTREE_OBJCBRIDGE_H
