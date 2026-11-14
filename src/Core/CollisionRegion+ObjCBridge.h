/*

CollisionRegion+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, bead oo-44gg): the Objective-C CollisionRegion, a facade over the
C++ cxx::CollisionRegion (CollisionRegion.h), for callers that are not converted yet (Universe
makes and drives the universe region; Entity retains the region it is filed in). Its interface is
the one CollisionRegion.h declared before the conversion, copied exactly (same selectors, same
types), so those callers compile and behave unchanged; each method forwards to its C++ member.
Imported as the last line of CollisionRegion.h; do not import it directly.

        a caller that is                       holds / passes                  crosses with
        -------------------------------------  ------------------------------  ----------------------------
        still Objective-C                      CollisionRegion * (this facade) nothing: messages as before
        converted (C++)                        oo::Ref<cxx::CollisionRegion>, cxx::CollisionRegion *
          handing a region to Objective-C                                       oo::ToObjC(region)
          taking one from Objective-C                                           oo::ToCxx(objcRegion)

oo::ToObjC gives the region's one live facade (oo::ObjCPeers), so identity survives a round trip:
oo::ToObjC(oo::ToCxx(r)) == r, and an entity filed twice in one subregion holds the same object.
Never add to this file; converted code does not message the facade. Deleted by its deletion bead
once no file outside CollisionRegion.* names the Objective-C CollisionRegion.

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

#ifndef COLLISIONREGION_OBJCBRIDGE_H
#define COLLISIONREGION_OBJCBRIDGE_H

#import "OOFoundation.h"
#import "oofnd/objc/OOObject.h"

@interface CollisionRegion : OOObject {
@private
    oo::Ref<cxx::CollisionRegion> _cxxRegion;
}

- (id)initAsUniverse;
- (id)initAtLocation:(HPVector)locn withRadius:(GLfloat)rad withinRegion:(CollisionRegion*)otherRegion;

- (void)clearSubregions;
- (void)addSubregionAtPosition:(HPVector)pos withRadius:(GLfloat)rad;

// collision checking
- (void)clearEntityList;
- (void)addEntity:(Entity*)ent;
- (BOOL)checkEntity:(Entity*)ent;

- (void)findCollisions;
- (void)findShadowedEntities;

// Description for FPS HUD
- (std::string)collisionDescription; // flipped with its family (bead oo-3rb.277)

- (std::optional<std::string>)debugOut;

@end

namespace oo {

// The region's Objective-C facade: its live one, else a new one; autoreleased. nil for null.
CollisionRegion* ToObjC(cxx::CollisionRegion* region);
inline CollisionRegion* ToObjC(const Ref<cxx::CollisionRegion>& region) { return ToObjC(region.get()); }

// The C++ region behind a facade, borrowed (the facade retains it); null for nil.
cxx::CollisionRegion* ToCxx(CollisionRegion* region);

} // namespace oo

#endif // COLLISIONREGION_OBJCBRIDGE_H
