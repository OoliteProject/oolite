/*

CollisionRegion.m

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

#import "CollisionRegion.h"
#import "OOMaths.h"
#import "Universe.h"
#import "Entity.h"
#import "ShipEntity.h"
#import "OOSunEntity.h"
#import "OOPlanetEntity.h"
#import "StationEntity.h"
#import "PlayerEntity.h"
#import "OODebugFlags.h"


@implementation CollisionRegion

- (NSString *) description
{
	int n_subs = [subregions count];
	return [NSString stringWithFormat:@"ID: %d, %d subregions, %d ents", crid, n_subs, n_entities];
}


// basic alloc/ dealloc routines
//
static int crid_counter = 1;
//
- (id) initAsUniverse
{
	self = [super init];
	
	location = kZeroVector;
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


- (void) findCollisions
{
	//
	// According to Shark, when this was in Universe this was where Oolite spent most time!
	//
	Entity *e1,*e2;
	Vector p1, p2;
	double dist2, r1, r2, r0, min_dist2;
	int i;
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
		if (!(e1->collisionTestFilter))
			entities_to_test[n_entities_to_test++] = e1;
	}
	
#ifndef NDEBUG
	if (gDebugFlags & DEBUG_COLLISIONS)
		OOLog(@"collisionRegion.debug", @"DEBUG in collision region %@ testing %d out of %d entities", self, n_entities_to_test, n_entities);
#endif
	
	if (n_entities_to_test < 2)
		return;

	//	clear collision variables
	//
	for (i = 0; i < n_entities_to_test; i++)
	{
		e1 = entities_to_test[i];
		if (e1->hasCollided)
			[[e1 collisionArray] removeAllObjects];
		e1->hasCollided = NO;
		if (e1->isShip)
			[(ShipEntity*)e1 setProximity_alert:nil];
		e1->collider = nil;
	}
	
	// test for collisions in each subregion
	//
	/* There are never subregions created in the current code, so skip this check for now.
	 
	int n_subs = [subregions count];
	for (i = 0; i < n_subs; i++)
		[(CollisionRegion*)[subregions objectAtIndex: i] findCollisions];
	 
	*/
	//
	
	checks_this_tick = 0;
	checks_within_range = 0;
	
	// test each entity in this region against the entities in its collision chain
	//
	for (i = 0; i < n_entities_to_test; i++)
	{
		e1 = entities_to_test[i];
		p1 = e1->position;
		r1 = e1->collision_radius;
		
		// check against the first in the collision chain
		e2 = e1->collision_chain;
		while (e2 != nil)
		{
			checks_this_tick++;
			
			p2 = e2->position;
			r2 = e2->collision_radius;
			r0 = r1 + r2;
			p2 = vector_subtract(p2, p1);
			dist2 = magnitude2(p2);
			min_dist2 = r0 * r0;
			if (dist2 < PROXIMITY_WARN_DISTANCE2 * min_dist2)
			{
#ifndef NDEBUG
				if (gDebugFlags & DEBUG_COLLISIONS)
				{
					OOLog(@"collisionRegion.debug", @"DEBUG Testing collision between %@ (%@) and %@ (%@)",
						  e1, (e1->collisionTestFilter)?@"YES":@"NO", e2, (e2->collisionTestFilter)?@"YES":@"NO");
				}
#endif
				checks_within_range++;
				
				if ((e1->isShip) && (e2->isShip))
				{
					if ((dist2 < PROXIMITY_WARN_DISTANCE2 * r2 * r2) || (dist2 < PROXIMITY_WARN_DISTANCE2 * r1 * r1))
					{
						[(ShipEntity*)e1 setProximity_alert:(ShipEntity*)e2];
						[(ShipEntity*)e2 setProximity_alert:(ShipEntity*)e1];
					}
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
						e1->hasCollided = YES;
						//
						if (e2->collider)
							[[e2 collisionArray] addObject:e2->collider];
						else
							[[e2 collisionArray] addObject:e1];
						e2->hasCollided = YES;
					}
				}
			}
			// check the next in the collision chain
			e2 = e2->collision_chain;
		}
	}
}


// an outValue of 1 means it's just being occluded.
static BOOL entityByEntityOcclusionToValue(Entity *e1, Entity *e2, OOSunEntity *the_sun, double *outValue)
{
	*outValue = 1.5;	// initial 'fully lit' value
	// simple tests
	if (EXPECT_NOT(e1 == e2 || e2 == the_sun))
		return NO;	// you can't shade self and sun can't shade itself
	//
	if (![e2 isShip] && ![e2 isPlanet])
		return NO;	// only ships and planets shade.
	//
	if (e2->collision_radius < e1->collision_radius)
		return NO;	// smaller can't shade bigger
	//
	if (e2->isSunlit == NO)
		return NO;	// things already /in/ shade can't shade things more.
	//
	// check projected sizes of discs
	GLfloat d2_sun = distance2(e1->position, the_sun->position);
	GLfloat d2_e2sun = distance2(e2->position, the_sun->position);
	if (d2_e2sun > d2_sun)
		return NO;	// you are nearer the sun than the potential occluder, so it can't shade you
	//
	GLfloat d2_e2 = distance2( e1->position, e2->position);
	GLfloat cr_sun = the_sun->collision_radius;
	GLfloat cr_e2 = e2->collision_radius;	// use collision radius as planets shadow
	if (e2->isShip) cr_e2 *= 0.90f;	// and a 10% smaller shadow for ships
	//
	GLfloat cr2_sun_scaled = cr_sun * cr_sun * d2_e2 / d2_sun;
	if (cr_e2 * cr_e2 < cr2_sun_scaled)
		return NO;	// if solar disc projected to the distance of e2 > collision radius it can't be shaded by e2
	//
	// check angles subtended by sun and occluder
	// double theta_sun = asin( cr_sun / sqrt(d2_sun));	// 1/2 angle subtended by sun
	// double theta_e2 = asin( cr_e2 / sqrt(d2_e2));		// 1/2 angle subtended by e2
	// find the difference between the angles subtended by occluder and sun
	double theta_diff = asin(cr_e2 / sqrt(d2_e2)) - asin(cr_sun / sqrt(d2_sun));
	
	Vector p_sun = the_sun->position;
	Vector p_e2 = e2->position;
	Vector p_e1 = e1->position;
	Vector v_sun = make_vector( p_sun.x - p_e1.x, p_sun.y - p_e1.y, p_sun.z - p_e1.z);
	if (v_sun.x||v_sun.y||v_sun.z)
		v_sun = vector_normal(v_sun);
	else
		v_sun.z = 1.0f;
	//
	Vector v_e2 = make_vector( p_e2.x - p_e1.x, p_e2.y - p_e1.y, p_e2.z - p_e1.z);
	if (v_e2.x||v_e2.y||v_e2.z)
		v_e2 = vector_normal(v_e2);
	else
		v_e2.x = 1.0f;
	double phi = acos( dot_product( v_sun, v_e2));		// angle between sun and e2 from e1's viewpoint
	*outValue = (phi / theta_diff);	// 1 means just occluded, < 1 means in shadow
	//
	//if (theta_sun + phi > theta_e2)
	if (phi > theta_diff)
		return NO;	// sun is not occluded
	//
	// all tests done e1 is in shade!
	//
	return YES;
}


static BOOL testEntityOccludedByEntity(Entity *e1, Entity *e2, OOSunEntity *the_sun)
{
	double tmp;		// we're not interested in the amount of occlusion just now.
	return entityByEntityOcclusionToValue(e1, e2, the_sun, &tmp);
}


- (void) findShadowedEntities
{
	//
	// Copy/pasting the collision code to detect occlusion!
	//
	Entity* e1;
	int i,j;
	
	if ([UNIVERSE reducedDetail])  return;	// don't do this in reduced detail mode
	
	OOSunEntity* the_sun = [UNIVERSE sun];
	
	if (!the_sun)
		return;	// sun is required
		
	//
	// get a list of planet entities because they can shade across regions
	int			ent_count =		UNIVERSE->n_entities;
	Entity**	uni_entities =	UNIVERSE->sortedEntities;	// grab the public sorted list
	Entity*		planets[ent_count];
	int n_planets = 0;
	for (i = 0; i < ent_count; i++)
	{
		if ([uni_entities[i] isPlanet])
			planets[n_planets++] = uni_entities[i];		//	don't bother retaining - nothing will happen to them!
	}
	
	// reject trivial cases
	//
	if (n_entities < 2)
		return;
	
	// test for shadows in each subregion
	//
	int n_subs = [subregions count];
	for (i = 0; i < n_subs; i++)
		[[subregions objectAtIndex: i] findShadowedEntities];
	//
	
	// test each entity in this region against the others
	//
	for (i = 0; i < n_entities; i++)
	{
		e1 = entity_array[i];
		if (![e1 isVisible])
		{
			continue; // don't check shading of objects we can't see
		}
		BOOL occluder_moved = NO;
		if ([e1 status] == STATUS_COCKPIT_DISPLAY)
		{
			e1->isSunlit = YES;
			e1->shadingEntityID = NO_TARGET;
			continue;	// don't check shading in demo mode
		}
		if (e1->isSunlit == NO)
		{
			Entity* occluder = [UNIVERSE entityForUniversalID:e1->shadingEntityID];
			if (occluder)
				occluder_moved = occluder->hasMoved;
		}
		if (([e1 isShip] ||[e1 isPlanet]) && (e1->hasMoved || occluder_moved))
		{
			e1->isSunlit = YES;				// sunlit by default
			e1->shadingEntityID = NO_TARGET;
			//
			// check demo mode here..
			if ([e1 isPlayer] && ([(PlayerEntity*)e1 showDemoShips]))
				continue;	// don't check shading in demo mode
			//
			//	test planets
			//
			double occlusionNumber;
			for (j = 0; j < n_planets; j++)
			{
				if (entityByEntityOcclusionToValue(e1, planets[j], the_sun, &occlusionNumber))
				{
					e1->isSunlit = NO;
					e1->shadingEntityID = [planets[j] universalID];
				}
				if (EXPECT_NOT([e1 isPlayer])) ((PlayerEntity *)e1)->occlusion_dial = occlusionNumber;
			}
			//
			// test local entities
			//
			for (j = i + 1; j < n_entities; j++)
			{
				if (testEntityOccludedByEntity(e1, entity_array[j], the_sun))
				{
					e1->isSunlit = NO;
					e1->shadingEntityID = [entity_array[j] universalID];
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
