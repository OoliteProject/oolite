/*

	Oolite

	CollisionRegion.m
	
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

#import "CollisionRegion.h"
#import "vector.h"
#import "Universe.h"
#import "Entity.h"


@implementation CollisionRegion

- (NSString*) description
{
	int n_subs = [subregions count];
	NSMutableString* result = [[NSMutableString alloc] initWithFormat:@"<CollisionRegion containing %d subregions and %d entities:", n_subs, n_entities];
	int i;
	for (i = 0; i < n_subs; i++)
		[result appendFormat:@" %@", [subregions objectAtIndex:i]];
	[result appendString:@" >"];
	return [result autorelease];
}

// basic alloc/ dealloc routines
//
- (id) initAsUniverse
{
	self = [super init];
	
	location = make_vector( 0.0f, 0.0f, 0.0f);
	radius = 0.0f;
	border_radius = 0.0f;
	isUniverse = YES;
	
	max_entities = COLLISION_MAX_ENTITIES;
	n_entities = 0;
	entity_array = (Entity**) malloc( max_entities * sizeof(Entity*));
	
	subregions = [[NSMutableArray alloc] initWithCapacity: 32];	// retained
	
	parentRegion = nil;
	
	return self;
}

- (id) initAtLocation:(Vector) locn withRadius:(GLfloat) rad withinRegion:(CollisionRegion*) otherRegion
{
	self = [super init];
	
	location = locn;
	radius = rad;
	border_radius = COLLISION_REGION_BORDER_RADIUS;
	isUniverse = NO;
	
	max_entities = COLLISION_MAX_ENTITIES;
	n_entities = 0;
	entity_array = (Entity**) malloc( max_entities * sizeof(Entity*));
	
	subregions = [[NSMutableArray alloc] initWithCapacity: 32];	// retained
	
	if (otherRegion)
		parentRegion = otherRegion;
	
	return self;
}

- (void) dealloc
{
	if (entity_array)
		free((void *)entity_array);	// free up the allocated space
	if (subregions)
		[subregions release];
	[super dealloc];
}

- (void) clearSubregions
{
	int i;
	int n_subs = [subregions count];
	for (i = 0; i < n_subs; i++)
		[(CollisionRegion*)[subregions objectAtIndex: i] clearSubregions];
	[subregions removeAllObjects];
}

- (void) addSubregionAtPosition:(Vector) pos withRadius:(GLfloat) rad
{
	// check if this can be fitted within any of the subregions
	//
	int i;
	int n_subs = [subregions count];
	for (i = 0; i < n_subs; i++)
	{
		CollisionRegion* sub = (CollisionRegion*)[subregions objectAtIndex: i];
		if (sphereIsWithinRegion( pos, rad, sub))
		{
			// if it fits, put it in!
			[sub addSubregionAtPosition: pos withRadius: rad];
			return;
		}
		if (positionIsWithinRegion( pos, sub))
		{
			// crosses the border of this region already - leave it out
			return;
		}
	}
	// no subregion fit - move on...
	//
	CollisionRegion* sub = [[CollisionRegion alloc] initAtLocation: pos withRadius: rad withinRegion: self];
	[subregions addObject:sub];
	[sub release];
}


// update routines to check if a position is within the radius or within it's borders
//
BOOL positionIsWithinRegion( Vector position, CollisionRegion* region)
{
	if (!region)
		return NO;
		
	if (region->isUniverse)
		return YES;
	
	Vector loc = region->location;
	GLfloat r1 = region->radius;
	
	 if ((position.x < loc.x - r1)||(position.x > loc.x + r1)||
		(position.y < loc.y - r1)||(position.y > loc.y + r1)||
		(position.z < loc.z - r1)||(position.z > loc.z + r1))
		return NO;
	
//	return (magnitude2(vector_between( position, loc)) < r1 * r1);
	return YES;
}

BOOL sphereIsWithinRegion( Vector position, GLfloat rad, CollisionRegion* region)
{
	if (!region)
		return NO;
		
	if (region->isUniverse)
		return YES;
	
	Vector loc = region->location;
	GLfloat r1 = region->radius;
	
	 if ((position.x - rad < loc.x - r1)||(position.x + rad > loc.x + r1)||
		(position.y - rad < loc.y - r1)||(position.y + rad > loc.y + r1)||
		(position.z - rad < loc.z - r1)||(position.z + rad > loc.z + r1))
		return NO;
	
	return YES;
}

BOOL positionIsWithinBorders( Vector position, CollisionRegion* region)
{
	if (!region)
		return NO;
		
	if (region->isUniverse)
		return YES;
	
	Vector loc = region->location;
	GLfloat r1 = region->radius + region->border_radius;
	
	 if ((position.x < loc.x - r1)||(position.x > loc.x + r1)||
		(position.y < loc.y - r1)||(position.y > loc.y + r1)||
		(position.z < loc.z - r1)||(position.z > loc.z + r1))
		return NO;
	
//	return (magnitude2(vector_between( position, loc)) < r1 * r1);
	return YES;
}

BOOL positionIsOnBorders( Vector position, CollisionRegion* region)
{
	if (!region)
		return NO;
		
	if (region->isUniverse)
		return NO;
	
	Vector loc = region->location;
//	GLfloat r1 = region->radius;
	GLfloat r2 = region->radius + region->border_radius;
	
	 if ((position.x < loc.x - r2)||(position.x > loc.x + r2)||
		(position.y < loc.y - r2)||(position.y > loc.y + r2)||
		(position.z < loc.z - r2)||(position.z > loc.z + r2))
		return NO;

//	GLfloat d2 = magnitude2(vector_between( position, loc));
//	
//	return ((d2 > r1 * r1)&&(d2 < r2 * r2));
	return (!positionIsWithinRegion( position, region));
}

NSArray* subregionsContainingPosition( Vector position, CollisionRegion* region)
{
	NSArray* subs = region->subregions;
	NSMutableArray* result = [NSMutableArray array];	// autoreleased
	
	if (!subs)
		return result;	// empty array
	
	int i;
	int n_subs = [subs count];
	for (i = 0; i < n_subs; i++)
		if (positionIsWithinBorders( position, (CollisionRegion*)[subs objectAtIndex: i]))
			[result addObject: [subs objectAtIndex: i]];
	return result;
}


// collision checking
//
- (void) clearEntityList
{
	n_entities = 0;
	int i;
	int n_subs = [subregions count];
	for (i = 0; i < n_subs; i++)
		[(CollisionRegion*)[subregions objectAtIndex: i] clearEntityList];
}

- (void) addEntity:(Entity*) ent
{
	// expand if necessary
	//	
	if (n_entities == max_entities)
	{
		max_entities = 1 + max_entities * 2;
		Entity** new_store = (Entity**) malloc( max_entities * sizeof(Entity*));
		int i;
		for (i = 0; i < n_entities; i++)
			new_store[i] = entity_array[i];
		free( (void*)entity_array);
		entity_array = new_store;
	}
	
	entity_array[n_entities++] = ent;
}

- (BOOL) checkEntity:(Entity*) ent
{
	Vector position = ent->position;
	
	// check subregions
	BOOL foundRegion = NO;
	int n_subs = [subregions count];
	int i;
	for (i = 0; i < n_subs; i++)
	{
		CollisionRegion* sub = (CollisionRegion*)[subregions objectAtIndex:i];
		if (positionIsWithinBorders( position, sub))
			foundRegion |= [sub checkEntity:ent];
	}
	if (foundRegion)
		return YES;	// it's in a subregion so no further action is neccesary
	
	if (!positionIsWithinBorders( position, self))
		return NO;
	
	[self addEntity: ent];
	return YES;
}


- (void) findCollisionsInUniverse:(Universe*) universe
{
	//
	// According to Shark, when this was in Universe this was where Oolite spent most time!
	//
	Entity *e1,*e2;
	Vector p1, p2;
	double dist2, r1, r2, r0, min_dist2;
	int i,j;
	//
	
	// reject trivial cases
	//
	if (n_entities < 2)
		return;
	
	//	clear collision variables
	//
	for (i = 0; i < n_entities; i++)
	{
		e1 = entity_array[i];
		if (e1->has_collided)
			[[e1 collisionArray] removeAllObjects];
		e1->has_collided = NO;
		if (e1->isShip)
			[(ShipEntity*)e1 setProximity_alert:nil];
		e1->collider = nil;
	}
	
	// test for collisions in each subregion
	//
	int n_subs = [subregions count];
	for (i = 0; i < n_subs; i++)
		[(CollisionRegion*)[subregions objectAtIndex: i] findCollisionsInUniverse: universe];
	//
	
	// test each entity in this region against the others
	//
	for (i = 0; i < n_entities; i++)
	{
		e1 = entity_array[i];
		p1 = e1->position;
		r1 = e1->collision_radius;
		for (j = i + 1; j < n_entities; j++)
		{
			e2 = entity_array[j];
			p2 = e2->position;
			r2 = e2->collision_radius;
			r0 = r1 + r2;
			p2.x -= p1.x;   p2.y -= p1.y;   p2.z -= p1.z;
			if ((p2.x > r0)||(p2.x < -r0))	// test for simple x distance
				continue;	// next j
			if ((p2.y > r0)||(p2.y < -r0))	// test for simple y distance
				continue;	// next j
			if ((p2.z > r0)||(p2.z < -r0))	// test for simple z distance
				continue;	// next j
			dist2 = p2.x*p2.x + p2.y*p2.y + p2.z*p2.z;
			min_dist2 = r0 * r0;
			if (dist2 < PROXIMITY_WARN_DISTANCE2 * min_dist2)
			{
				if ((e1->isShip) && (e2->isShip))
				{
					if (dist2 < PROXIMITY_WARN_DISTANCE2 * r2 * r2) [(ShipEntity*)e1 setProximity_alert:(ShipEntity*)e2];
					if (dist2 < PROXIMITY_WARN_DISTANCE2 * r1 * r1) [(ShipEntity*)e2 setProximity_alert:(ShipEntity*)e1];
				}
				if (dist2 < min_dist2)
				{
					BOOL	coll1 = [e1 checkCloseCollisionWith:e2];
					BOOL	coll2 = [e2 checkCloseCollisionWith:e1];
					if ( coll1 && coll2 )
					{
						if (e1->collider)
							[[e1 collisionArray] addObject:e1->collider];
						else
							[[e1 collisionArray] addObject:e2];
						e1->has_collided = YES;
						//
						if (e2->collider)
							[[e2 collisionArray] addObject:e2->collider];
						else
							[[e2 collisionArray] addObject:e1];
						e2->has_collided = YES;
					}
				}
			}
		}
	}
}

- (NSString*) debugOut
{
	int i;
	int n_subs = [subregions count];
	NSMutableString* result = [[NSMutableString alloc] initWithFormat:@"%d:", n_entities];
	for (i = 0; i < n_subs; i++)
		[result appendString:[(CollisionRegion*)[subregions objectAtIndex:i] debugOut]];
	return [result autorelease];
}

@end
