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
	NSString* result = [NSString stringWithFormat:@"<CollisionRegion %d (%d subregions, %d ents) >", crid, n_subs, n_entities];
	return result;
}

// basic alloc/ dealloc routines
//
static int crid_counter = 1;
//
- (id) initAsUniverse
{
	self = [super init];
	
	location = make_vector( 0.0f, 0.0f, 0.0f);
	radius = 0.0f;
	border_radius = 0.0f;
	isUniverse = YES;
	isPlayerInRegion = NO;
	
	max_entities = COLLISION_MAX_ENTITIES;
	n_entities = 0;
	entity_array = (Entity**) malloc( max_entities * sizeof(Entity*));
	
	subregions = [[NSMutableArray alloc] initWithCapacity: 32];	// retained
	
	parentRegion = nil;
	
	crid = crid_counter++;
	
	return self;
}

- (id) initAtLocation:(Vector) locn withRadius:(GLfloat) rad withinRegion:(CollisionRegion*) otherRegion
{
	self = [super init];
	
	location = locn;
	radius = rad;
	border_radius = COLLISION_REGION_BORDER_RADIUS;
	isUniverse = NO;
	isPlayerInRegion = NO;
	
	max_entities = COLLISION_MAX_ENTITIES;
	n_entities = 0;
	entity_array = (Entity**) malloc( max_entities * sizeof(Entity*));
	
	subregions = [[NSMutableArray alloc] initWithCapacity: 32];	// retained
	
	if (otherRegion)
		parentRegion = otherRegion;
	
	crid = crid_counter++;
	
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
	
	return YES;
}

BOOL positionIsOnBorders( Vector position, CollisionRegion* region)
{
	if (!region)
		return NO;
		
	if (region->isUniverse)
		return NO;
	
	Vector loc = region->location;
	GLfloat r2 = region->radius + region->border_radius;
	
	 if ((position.x < loc.x - r2)||(position.x > loc.x + r2)||
		(position.y < loc.y - r2)||(position.y > loc.y + r2)||
		(position.z < loc.z - r2)||(position.z > loc.z + r2))
		return NO;

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
	isPlayerInRegion = NO;
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
	
	isPlayerInRegion |= (ent->isPlayer);
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
	[ent setCollisionRegion: self];
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
	Entity*	entities_to_test[n_entities];
	//
	
	// reject trivial cases
	//
	if (n_entities < 2)
		return;
	
	// only check unfiltered entities
	int n_entities_to_test = 0;
	for (i = 0; i < n_entities; i++)
	{
		e1 = entity_array[i];
		if (!e1->collisionTestFilter)
			entities_to_test[n_entities_to_test++] = e1;
	}
	if (n_entities_to_test < 2)
		return;

	
	//	clear collision variables
	//
	for (i = 0; i < n_entities_to_test; i++)
	{
		e1 = entities_to_test[i];
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
	for (i = 0; i < n_entities_to_test; i++)
	{
		e1 = entities_to_test[i];
		p1 = e1->position;
		r1 = e1->collision_radius;
		for (j = i + 1; j < n_entities_to_test; j++)
		{
			e2 = entities_to_test[j];
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
					BOOL collision = NO;
					
					if (e1->isStation)
					{
						StationEntity* se1 = (StationEntity*) e1;
						if ([se1 shipIsInDockingCorridor: (ShipEntity*)e2])
							collision = NO;
						else
							collision = [e1 checkCloseCollisionWith: e2];
					}
					else if (e2->isStation)
					{
						StationEntity* se2 = (StationEntity*) e2;
						if ([se2 shipIsInDockingCorridor: (ShipEntity*)e1])
							collision = NO;
						else
							collision = [e2 checkCloseCollisionWith: e1];
					}
					else
						collision = [e1 checkCloseCollisionWith: e2];
				
					if (collision)
					{
						// now we have no need to check the e2-e1 collision
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

BOOL testEntityOccludedByEntity(Entity* e1, Entity* e2, PlanetEntity* the_sun)
{
	// simple tests
	if (e1 == e2)
		return NO;	// you can't shade self
	//
	if (e2 == the_sun)
		return NO;	// sun can't shade itself
	//
	if ((e2->isShip == NO)&&(e2->isPlanet == NO))
		return NO;	// only ships and planets shade
	//
	if (e2->collision_radius < e1->collision_radius)
		return NO;	// smaller can't shade bigger
	//
	if (e2->isSunlit == NO)
		return NO;	// things already /in/ shade can't shade things more.
	//
	// check projected sizes of discs
	GLfloat d2_sun = distance2( e1->position, the_sun->position);
	GLfloat d2_e2sun = distance2( e2->position, the_sun->position);
	if (d2_e2sun > d2_sun)
		return NO;	// you are nearer the sun than the potential occluder, so it can't shade you
	//
	GLfloat d2_e2 = distance2( e1->position, e2->position);
	GLfloat cr_sun = the_sun->collision_radius;
	GLfloat cr_e2 = e2->actual_radius;
	if (e2->isShip)
		cr_e2 *= 0.90;	// 10% smaller shadow for ships
	if (e2->isPlanet)
		cr_e2 = e2->collision_radius;	// use collision radius for planets
	//
	GLfloat cr2_sun_scaled = cr_sun * cr_sun * d2_e2 / d2_sun;
	if (cr_e2 * cr_e2 < cr2_sun_scaled)
		return NO;	// if solar disc projected to the distance of e2 > collision radius it can't be shaded by e2
	//
	// check angles subtended by sun and occluder
	double theta_sun = asin( cr_sun / sqrt(d2_sun));	// 1/2 angle subtended by sun
	double theta_e2 = asin( cr_e2 / sqrt(d2_e2));		// 1/2 angle subtended by e2
	Vector p_sun = the_sun->position;
	Vector p_e2 = e2->position;
	Vector p_e1 = e1->position;
	Vector v_sun = make_vector( p_sun.x - p_e1.x, p_sun.y - p_e1.y, p_sun.z - p_e1.z);
	if (v_sun.x||v_sun.y||v_sun.z)
		v_sun = unit_vector( &v_sun);
	else
		v_sun.z = 1.0;
	//
	Vector v_e2 = make_vector( p_e2.x - p_e1.x, p_e2.y - p_e1.y, p_e2.z - p_e1.z);
	if (v_e2.x||v_e2.y||v_e2.z)
		v_e2 = unit_vector( &v_e2);
	else
		v_e2.x = 1.0;
	double phi = acos( dot_product( v_sun, v_e2));		// angle between sun and e2 from e1's viewpoint
	//
	if (theta_sun + phi > theta_e2)
		return NO;	// sun is not occluded
	//
	// all tests done e1 is in shade!
	//
	return YES;
}

- (void) findShadowedEntitiesIn:(Universe*) universe
{
	//
	// Copy/pasting the collision code to detect occlusion!
	//
	Entity* e1;
	int i,j;
	
	if (!universe)
		return;	// universe is required!
	
	if ([universe reducedDetail])
		return;	// don't do this in reduced detail mode
	
	PlanetEntity* the_sun = [universe sun];
	
	if (!the_sun)
		return;	// sun is required
		
	//
	// get a list of planet entities because they can shade across regions
	int			ent_count =		universe->n_entities;
	Entity**	uni_entities =	universe->sortedEntities;	// grab the public sorted list
	Entity*		planets[ent_count];
	int n_planets = 0;
	for (i = 0; i < ent_count; i++)
		if ((uni_entities[i]->isPlanet)&&(uni_entities[i] != the_sun))
			planets[n_planets++] = uni_entities[i];		//	don't bother retaining - nothing will happen to them!
	//
	
	// reject trivial cases
	//
	if (n_entities < 2)
		return;
	
	// test for shadows in each subregion
	//
	int n_subs = [subregions count];
	for (i = 0; i < n_subs; i++)
		[(CollisionRegion*)[subregions objectAtIndex: i] findShadowedEntitiesIn:(Universe*) universe];
	//
	
	// test each entity in this region against the others
	//
	for (i = 0; i < n_entities; i++)
	{
		e1 = entity_array[i];
		BOOL occluder_moved = NO;
		if (e1->status == STATUS_DEMO)
		{
			e1->isSunlit = YES;
			e1->shadingEntityID = NO_TARGET;
			continue;	// don't check shading in demo mode
		}
		if (e1->isSunlit == NO)
		{
			Entity* occluder = [universe entityForUniversalID:e1->shadingEntityID];
			if (occluder)
				occluder_moved = occluder->has_moved;
		}
		if (((e1->isShip)||(e1->isPlanet))&&((e1->has_moved)||occluder_moved))
		{
			e1->isSunlit = YES;				// sunlit by default
			e1->shadingEntityID = NO_TARGET;
			//
			// check demo mode here..
			if ((e1->isPlayer)&&([(PlayerEntity*)e1 showDemoShips]))
				continue;	// don't check shading in demo mode
			//
			//	test planets
			//
			for (j = 0; j < n_planets; j++)
			{
				if (testEntityOccludedByEntity(e1, planets[j], the_sun))
				{
					e1->isSunlit = NO;
					e1->shadingEntityID = [planets[j] universal_id];
				}
			}
			//
			// test local entities
			//
			for (j = i + 1; j < n_entities; j++)
			{
				if (testEntityOccludedByEntity(e1, entity_array[j], the_sun))
				{
					e1->isSunlit = NO;
					e1->shadingEntityID = [entity_array[j] universal_id];
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
