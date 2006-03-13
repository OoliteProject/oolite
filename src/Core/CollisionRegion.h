/*

	Oolite

	CollisionRegion.h
	
	Created by Giles Williams on 01/03/2006.


Copyright (c) 2005, Giles C Williams
All rights reserved.

This work is licensed under the Creative Commons Attribution-NonCommercial-ShareAlike License.
To view a copy of this license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/
or send a letter to Creative Commons, 559 Nathan Abbott Way, Stanford, California 94305, USA.

You are free:

•	to copy, distribute, display, and perform the work
•	to make derivative works

Under the following conditions:

•	Attribution. You must give the original author credit.

•	Noncommercial. You may not use this work for commercial purposes.

•	Share Alike. If you alter, transform, or build upon this work,
you may distribute the resulting work only under a license identical to this one.

For any reuse or distribution, you must make clear to others the license terms of this work.

Any of these conditions can be waived if you get permission from the copyright holder.

Your fair use and other rights are in no way affected by the above.

*/

#import "OOCocoa.h"
#import "vector.h"

#define	COLLISION_REGION_BORDER_RADIUS	32000.0f
#define	COLLISION_MAX_ENTITIES			128

@class	Entity, Universe;

@interface CollisionRegion : NSObject {

@public

	BOOL	isUniverse;			// if YES location is origin and radius is 0.0f
	
	Vector	location;			// center of the region
	GLfloat	radius;				// inner radius of the region
	GLfloat	border_radius;		// additiønal, border radius of the region (typically 32km or some value > the scanner range)

	NSMutableArray*		subregions;
	
@protected
	
	Entity**	entity_array;	// entities within the region
	int			n_entities;		// number of entities
	int			max_entities;	// so storage can be expanded
	
	CollisionRegion*	parentRegion;

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
- (void) findCollisionsInUniverse:(Universe*) universe;
//
- (void) findShadowedEntitiesIn:(Universe*) universe;

- (NSString*) debugOut;

@end
