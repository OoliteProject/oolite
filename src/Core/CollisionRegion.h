/*

CollisionRegion.h

Collision regions are used to group entities which may potentially collide, to
reduce the number of collision checks required.

Oolite
Copyright (C) 2004-2012 Giles C Williams and contributors

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

#import "OOCocoa.h"
#import "OOMaths.h"

#define	COLLISION_REGION_BORDER_RADIUS	32000.0f
#define	COLLISION_MAX_ENTITIES			128
#define MINIMUM_SHADOWING_ENTITY_RADIUS 75.0

@class	Entity;

@interface CollisionRegion : NSObject
{
@public

	BOOL				isUniverse;			// if YES location is origin and radius is 0.0f
	
	int					crid;				// identifier
	Vector				location;			// center of the region
	GLfloat				radius;				// inner radius of the region
	GLfloat				border_radius;		// additiønal, border radius of the region (typically 32km or some value > the scanner range)

	int					checks_this_tick;
	int					checks_within_range;

	NSMutableArray		*subregions;
	
@protected
	
	BOOL				isPlayerInRegion;
	
	Entity				**entity_array;	// entities within the region
	int					n_entities;		// number of entities
	int					max_entities;	// so storage can be expanded
	
	
	CollisionRegion		*parentRegion;

}

- (id) initAsUniverse;
- (id) initAtLocation:(Vector) locn withRadius:(GLfloat) rad withinRegion:(CollisionRegion*) otherRegion;

- (void) clearSubregions;
- (void) addSubregionAtPosition:(Vector) pos withRadius:(GLfloat) rad;

// update routines to check if a position is within the radius or within it's borders
//
BOOL positionIsWithinRegion( Vector position, CollisionRegion* region);
BOOL sphereIsWithinRegion( Vector position, GLfloat rad, CollisionRegion* region);
BOOL positionIsWithinBorders( Vector position, CollisionRegion* region);
BOOL positionIsOnBorders( Vector position, CollisionRegion* region);
NSArray* subregionsContainingPosition( Vector position, CollisionRegion* region);

// collision checking
//
- (void) clearEntityList;
- (void) addEntity:(Entity*) ent;
//
- (BOOL) checkEntity:(Entity*) ent;
//
- (void) findCollisions;
- (void) findShadowedEntities;

- (NSString*) debugOut;

@end
