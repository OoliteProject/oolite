/*

CollisionRegion.h

Collision regions are used to group entities which may potentially collide, to
reduce the number of collision checks required.

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

#ifndef COLLISIONREGION_H
#define COLLISIONREGION_H

#import "OOFoundation.h"
#import "OOMaths.h"
#import "oofnd/objc/OOObject.h"

#include "oofnd/Ref.hpp"
#include "oofnd/StdLib.hpp"

#define COLLISION_REGION_BORDER_RADIUS 32000.0f
#define COLLISION_MAX_ENTITIES 128
#define MINIMUM_SHADOWING_ENTITY_RADIUS 75.0

@class Entity, OOSunEntity;

namespace cxx {

class CollisionRegion : public oo::RefCounted {
public:
    struct AsUniverse { };
    explicit CollisionRegion(AsUniverse); // -initAsUniverse
    CollisionRegion(HPVector locn, GLfloat rad, CollisionRegion* otherRegion); // -initAtLocation:withRadius:withinRegion:
    ~CollisionRegion() override;

    void clearSubregions();
    void addSubregionAtPosition(HPVector pos, GLfloat rad);

    // collision checking
    void clearEntityList();
    void addEntity(::Entity* ent);
    bool checkEntity(::Entity* ent);

    void findCollisions();
    void findShadowedEntities();

    // Description for FPS HUD
    std::string collisionDescription(); // flipped with its family (bead oo-3rb.277)

    std::optional<std::string> debugOut();

    // What "%@" prints between the braces of <CollisionRegion 0x...>{...} (OODescription.h).
    std::optional<std::string> descriptionComponents() const;

private:
    CollisionRegion(); // the designated -init, less [super init]

    // update routines to check if a position is within the radius or within its borders
    static bool positionIsWithinRegion(HPVector position, CollisionRegion* region);
    static bool sphereIsWithinRegion(HPVector position, GLfloat rad, CollisionRegion* region);
    static bool positionIsWithinBorders(HPVector position, CollisionRegion* region);

    bool isUniverse = { }; // if YES location is origin and radius is 0.0f

    int crid = { }; // identifier
    HPVector location = { }; // center of the region
    GLfloat radius = { }; // inner radius of the region
    GLfloat border_radius = { }; // additiønal, border radius of the region (typically 32km or some value > the scanner range)

    unsigned checks_this_tick = { };
    unsigned checks_within_range = { };

    std::vector<oo::Ref<CollisionRegion>> subregions; // Foundation sweep (proposed ADR-0043, bead oo-a87x)

    bool isPlayerInRegion = { };

    ::Entity** entity_array = { }; // entities within the region
    unsigned n_entities = { }; // number of entities
    unsigned max_entities = { }; // so storage can be expanded

    CollisionRegion* parentRegion = { };
};

} // namespace cxx

/* Given a region centred at e1pos with a radius of e1rad, the depth
 * of shadowing cast by e2 from the_sun is recorded in outValue, with
 * >1 = no shadow, <1 = shadow */
BOOL shadowAtPointOcclusionToValue(HPVector e1pos, GLfloat e1rad, ::Entity* e2, OOSunEntity* the_sun, float* outValue);

// Transitional: the Objective-C CollisionRegion, for callers not yet converted. Deleted, with
// namespace cxx above, by the bridge's deletion bead.
#import "CollisionRegion+ObjCBridge.h"

#endif // COLLISIONREGION_H
