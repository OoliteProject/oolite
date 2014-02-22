/*

CollisionRegion.m

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
#import "OOMaths.h"
#import "Universe.h"
#import "Entity.h"
#import "ShipEntity.h"
#import "OOSunEntity.h"
#import "OOPlanetEntity.h"
#import "StationEntity.h"
#import "PlayerEntity.h"
#import "OODebugFlags.h"


static BOOL positionIsWithinRegion(HPVector position, CollisionRegion *region);
static BOOL sphereIsWithinRegion(HPVector position, GLfloat rad, CollisionRegion *region);
static BOOL positionIsWithinBorders(HPVector position, CollisionRegion *region);


@implementation CollisionRegion

// basic alloc/ dealloc routines
//
static int crid_counter = 1;


- (id) init	// Designated initializer.
{
	if ((self = [super init]))
	{
		max_entities = COLLISION_MAX_ENTITIES;
		entity_array = (Entity **)malloc(max_entities * sizeof(Entity *));
		if (entity_array == NULL)
		{
			[self release];
			return nil;
		}
		
		crid = crid_counter++;
	}
	return self;
}


- (id) initAsUniverse
{
	if ((self = [self init]))
	{
		isUniverse = YES;
	}
	return self;
}


- (id) initAtLocation:(HPVector)locn withRadius:(GLfloat)rad withinRegion:(CollisionRegion *)otherRegion
{
	if ((self = [self init]))
	{
		location = locn;
		radius = rad;
		border_radius = COLLISION_REGION_BORDER_RADIUS;
		parentRegion = otherRegion;
	}
	return self;
}


- (void) dealloc
{
	free(entity_array);
	DESTROY(subregions);
	
	[super dealloc];
}


- (NSString *) description
{
	return [NSString stringWithFormat:@"<%@ %p>{ID: %d, %lu subregions, %u ents}", [self class], self, crid, [subregions count], n_entities];
}


- (void) clearSubregions
{
	[subregions makeObjectsPerformSelector:@selector(clearSubregions)];
	[subregions removeAllObjects];
}


- (void) addSubregionAtPosition:(HPVector)pos withRadius:(GLfloat)rad
{
	// check if this can be fitted within any of the subregions
	//
	CollisionRegion *sub = nil;
	foreach (sub, subregions)
	{
		if (sphereIsWithinRegion(pos, rad, sub))
		{
			// if it fits, put it in!
			[sub addSubregionAtPosition:pos withRadius:rad];
			return;
		}
		if (positionIsWithinRegion(pos, sub))
		{
			// crosses the border of this region already - leave it out
			return;
		}
	}
	// no subregion fit - move on...
	//
	sub = [[CollisionRegion alloc] initAtLocation:pos withRadius:rad withinRegion:self];
	if (subregions == nil)  subregions = [[NSMutableArray alloc] initWithCapacity:32];
	[subregions addObject:sub];
	[sub release];
}


// update routines to check if a position is within the radius or within its borders
//
static BOOL positionIsWithinRegion(HPVector position, CollisionRegion *region)
{
	if (region == nil)  return NO;
	if (region->isUniverse)  return YES;
	
	HPVector loc = region->location;
	GLfloat r1 = region->radius;
	
	 if ((position.x < loc.x - r1)||(position.x > loc.x + r1)||
		 (position.y < loc.y - r1)||(position.y > loc.y + r1)||
		 (position.z < loc.z - r1)||(position.z > loc.z + r1))
	 {
		 return NO;
	 }
	
	return YES;
}


static BOOL sphereIsWithinRegion(HPVector position, GLfloat rad, CollisionRegion *region)
{
	if (region == nil)  return NO;
	if (region->isUniverse)  return YES;
	
	HPVector loc = region->location;
	GLfloat r1 = region->radius;
	
	 if ((position.x - rad < loc.x - r1)||(position.x + rad > loc.x + r1)||
		 (position.y - rad < loc.y - r1)||(position.y + rad > loc.y + r1)||
		 (position.z - rad < loc.z - r1)||(position.z + rad > loc.z + r1))
	 {
		 return NO;
	 }
	
	return YES;
}


static BOOL positionIsWithinBorders(HPVector position, CollisionRegion *region)
{
	if (region == nil)  return NO;
	if (region->isUniverse)  return YES;
	
	HPVector loc = region->location;
	GLfloat r1 = region->radius + region->border_radius;
	
	 if ((position.x < loc.x - r1)||(position.x > loc.x + r1)||
		 (position.y < loc.y - r1)||(position.y > loc.y + r1)||
		 (position.z < loc.z - r1)||(position.z > loc.z + r1))
	 {
		 return NO;
	 }
	
	return YES;
}


// collision checking
//
- (void) clearEntityList
{
	[subregions makeObjectsPerformSelector:@selector(clearEntityList)];
	n_entities = 0;
	isPlayerInRegion = NO;
}


- (void) addEntity:(Entity *)ent
{
	// expand if necessary
	//	
	if (n_entities == max_entities)
	{
		max_entities = 1 + max_entities * 2;
		Entity **new_store = (Entity **)realloc(entity_array, max_entities * sizeof(Entity *));
		if (new_store == NULL)
		{
			[NSException raise:NSMallocException format:@"Not enough memory to grow collision region member list."];
		}
		
		entity_array = new_store;
	}
	
	if ([ent isPlayer])  isPlayerInRegion = YES;
	entity_array[n_entities++] = ent;
}


- (BOOL) checkEntity:(Entity *)ent
{
	HPVector position = ent->position;
	
	// check subregions
	CollisionRegion *sub = nil;
	foreach (sub, subregions)
	{
		if (positionIsWithinBorders(position, sub) && [sub checkEntity:ent])
		{
			return YES;
		}
	}
	
	if (!positionIsWithinBorders(position, self))
	{
		return NO;
	}
	
	[self addEntity:ent];
	[ent setCollisionRegion:self];
	return YES;
}


- (void) findCollisions
{
	// test for collisions in each subregion
	[subregions makeObjectsPerformSelector:@selector(findCollisions)];
	
	// reject trivial cases
	if (n_entities < 2)  return;
	
	//
	// According to Shark, when this was in Universe this was where Oolite spent most time!
	//
	Entity		*e1, *e2;
	HPVector		p1;
	double		dist2, r1, r2, r0, min_dist2;
	unsigned	i;
	Entity		*entities_to_test[n_entities];
	
	// only check unfiltered entities
	unsigned n_entities_to_test = 0;
	for (i = 0; i < n_entities; i++)
	{
		e1 = entity_array[i];
		if (e1->collisionTestFilter != 3)
		{
			entities_to_test[n_entities_to_test++] = e1;
		}
	}

#ifndef NDEBUG
	if (gDebugFlags & DEBUG_COLLISIONS)
	{
		OOLog(@"collisionRegion.debug", @"DEBUG in collision region %@ testing %d out of %d entities", self, n_entities_to_test, n_entities);
	}
#endif
	
	if (n_entities_to_test < 2)  return;

	//	clear collision variables
	//
	for (i = 0; i < n_entities_to_test; i++)
	{
		e1 = entities_to_test[i];
		if (e1->hasCollided)
		{
			[[e1 collisionArray] removeAllObjects];
			e1->hasCollided = NO;
		}
		if (e1->isShip)
		{
			[(ShipEntity*)e1 setProximityAlert:nil];
		}
		e1->collider = nil;
	}
	
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
			
			r2 = e2->collision_radius;
			r0 = r1 + r2;
			dist2 = HPdistance2(e2->position, p1);
			min_dist2 = r0 * r0;
			if (dist2 < PROXIMITY_WARN_DISTANCE2 * min_dist2)
			{
#ifndef NDEBUG
				if (gDebugFlags & DEBUG_COLLISIONS)
				{
					OOLog(@"collisionRegion.debug", @"DEBUG Testing collision between %@ (%@) and %@ (%@)",
						  e1, (e1->collisionTestFilter==3)?@"YES":@"NO", e2, (e2->collisionTestFilter==3)?@"YES":@"NO");
				}
#endif
				checks_within_range++;
				
				if (e1->isShip && e2->isShip)
				{
					if ((dist2 < PROXIMITY_WARN_DISTANCE2 * r2 * r2) || (dist2 < PROXIMITY_WARN_DISTANCE2 * r1 * r1))
					{
						[(ShipEntity*)e1 setProximityAlert:(ShipEntity*)e2];
						[(ShipEntity*)e2 setProximityAlert:(ShipEntity*)e1];
					}
				}
				if (dist2 < min_dist2)
				{
					BOOL collision = NO;
					
					if (e1->isStation)
					{
						StationEntity* se1 = (StationEntity *)e1;
						if ([se1 shipIsInDockingCorridor:(ShipEntity *)e2])
						{
							collision = NO;
						}
						else
						{
							collision = [e1 checkCloseCollisionWith:e2];
						}
					}
					else if (e2->isStation)
					{
						StationEntity* se2 = (StationEntity *)e2;
						if ([se2 shipIsInDockingCorridor:(ShipEntity *)e1])
						{
							collision = NO;
						}
						else
						{
							collision = [e2 checkCloseCollisionWith:e1];
						}
					}
					else
					{
						collision = [e1 checkCloseCollisionWith:e2];
					}
				
					if (collision)
					{
						// now we have no need to check the e2-e1 collision
						if (e1->collider)
						{
							[[e1 collisionArray] addObject:e1->collider];
						}
						else
						{
							[[e1 collisionArray] addObject:e2];
						}
						e1->hasCollided = YES;
						
						if (e2->collider)
						{
							[[e2 collisionArray] addObject:e2->collider];
						}
						else
						{
							[[e2 collisionArray] addObject:e1];
						}
						e2->hasCollided = YES;
					}
				}
			}
			// check the next in the collision chain
			e2 = e2->collision_chain;
		}
	}

#ifndef NDEBUG
	if (gDebugFlags & DEBUG_COLLISIONS)
	{
		OOLog(@"collisionRegion.debug",@"Collision test checks %d, within range %d, for %d entities",checks_this_tick,checks_within_range,n_entities_to_test);
	}
#endif
}


// an outValue of 1 means it's just being occluded.
static BOOL entityByEntityOcclusionToValue(Entity *e1, Entity *e2, OOSunEntity *the_sun, float *outValue)
{
	if (EXPECT_NOT(e1 == e2))
	{
		// you can't shade self
		return NO;
	}
	return shadowAtPointOcclusionToValue(e1->position,e1->collision_radius,e2,the_sun,outValue);
}

// an outValue of 1 means it's just being occluded.
BOOL shadowAtPointOcclusionToValue(HPVector e1pos, GLfloat e1rad, Entity *e2, OOSunEntity *the_sun, float *outValue)
{
	*outValue = 1.5f;	// initial 'fully lit' value
	
	GLfloat cr_e2;
	if ([e2 isShip])
	{
		cr_e2 = e2->collision_radius * 0.90f;
		// 10% smaller shadow for ships
	}
	else
	{
		cr_e2 = e2->collision_radius;
	}
	if (cr_e2 < e1rad)
	{
		// smaller can't shade bigger
		return NO;
	}
	
	// tested in construction of e2 list
//	if (e2->isSunlit == NO)
//		return NO;	// things already /in/ shade can't shade things more.
	//
	// check projected sizes of discs
	GLfloat d2_sun = HPdistance2(e1pos, the_sun->position);
	GLfloat d2_e2sun = HPdistance2(e2->position, the_sun->position);
	if (d2_e2sun > d2_sun)
	{
		// you are nearer the sun than the potential occluder, so it can't shade you
		return NO;
	}
	
	GLfloat d2_e2 = HPdistance2( e1pos, e2->position);
	GLfloat cr_sun = the_sun->collision_radius;
	
	GLfloat cr2_sun_scaled = cr_sun * cr_sun * d2_e2 / d2_sun;
	if (cr_e2 * cr_e2 < cr2_sun_scaled)
	{
		// if solar disc projected to the distance of e2 > collision radius it can't be shaded by e2
		return NO;
	}
	
	// check angles subtended by sun and occluder
	// double theta_sun = asin( cr_sun / sqrt(d2_sun));	// 1/2 angle subtended by sun
	// double theta_e2 = asin( cr_e2 / sqrt(d2_e2));		// 1/2 angle subtended by e2
	// find the difference between the angles subtended by occluder and sun
	float theta_diff = asin(cr_e2 / sqrt(d2_e2)) - asin(cr_sun / sqrt(d2_sun));
	
	HPVector p_sun = the_sun->position;
	HPVector p_e2 = e2->position;
	HPVector p_e1 = e1pos;
	Vector v_sun = HPVectorToVector(HPvector_subtract(p_sun, p_e1));
	v_sun = vector_normal_or_zbasis(v_sun);
	
	Vector v_e2 = HPVectorToVector(HPvector_subtract(p_e2, p_e1));
	v_e2 = vector_normal_or_xbasis(v_e2);
	
	float phi = acos(dot_product(v_sun, v_e2));		// angle between sun and e2 from e1's viewpoint
	*outValue = (phi / theta_diff);	// 1 means just occluded, < 1 means in shadow
	
	if (phi > theta_diff)
	{
		// sun is not occluded
		return NO;
	}
	
	// all tests done e1 is in shade!
	return YES;
}


static inline BOOL testEntityOccludedByEntity(Entity *e1, Entity *e2, OOSunEntity *the_sun)
{
	float tmp;		// we're not interested in the amount of occlusion just now.
	return entityByEntityOcclusionToValue(e1, e2, the_sun, &tmp);
}


- (void) findShadowedEntities
{
	// reject trivial cases
	if (n_entities < 2)  return;
	
	//
	// Copy/pasting the collision code to detect occlusion!
	//
	unsigned i, j;
	
	if ([UNIVERSE reducedDetail])  return;	// don't do this in reduced detail mode
	
	OOSunEntity* the_sun = [UNIVERSE sun];
	
	if (the_sun == nil)
	{
		return;	// sun is required
	}
	
	unsigned	ent_count =	UNIVERSE->n_entities;
	Entity		**uni_entities = UNIVERSE->sortedEntities;	// grab the public sorted list
	Entity		*planets[ent_count];
	unsigned	n_planets = 0;
	Entity		*ships[ent_count];
	unsigned	n_ships = 0;
	
	for (i = 0; i < ent_count; i++)
	{
		if (uni_entities[i]->isSunlit)
		{
			// get a list of planet entities because they can shade across regions
			if ([uni_entities[i] isPlanet])
			{
				//	don't bother retaining - nothing will happen to them!
				planets[n_planets++] = uni_entities[i];
			}
			
			// and a list of shipentities large enough that they might cast a noticeable shadow
			// if we can't see it, it can't be shadowing anything important
			else if ([uni_entities[i] isShip] &&
					 [uni_entities[i] isVisible] && 
					 uni_entities[i]->collision_radius >= MINIMUM_SHADOWING_ENTITY_RADIUS)
			{
				ships[n_ships++] = uni_entities[i];		//	don't bother retaining - nothing will happen to them!
			}
		}
	}
	
	// test for shadows in each subregion
	[subregions makeObjectsPerformSelector:@selector(findShadowedEntities)];
	
	// test each entity in this region against the others
	for (i = 0; i < n_entities; i++)
	{
		Entity *e1 = entity_array[i];
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
		Entity *occluder = nil;
		if (e1->isSunlit == NO)
		{
			occluder = [UNIVERSE entityForUniversalID:e1->shadingEntityID];
			if (occluder != nil)
			{
				occluder_moved = occluder->hasMoved;
			}
		}
		if (([e1 isShip] ||[e1 isPlanet]) && (e1->hasMoved || occluder_moved))
		{
			e1->isSunlit = YES;				// sunlit by default
			e1->shadingEntityID = NO_TARGET;
			//
			// check demo mode here..
			if ([e1 isPlayer] && ([(PlayerEntity*)e1 showDemoShips]))
			{
				continue;	// don't check shading in demo mode
			}
			
			// test last occluder (most likely case)
			if (occluder)
			{
				if (testEntityOccludedByEntity(e1, occluder, the_sun))	
				{
					e1->isSunlit = NO;
					e1->shadingEntityID = [occluder universalID];
				}
			}
			if (!e1->isSunlit)
			{
				// no point in continuing tests
				continue;
			}
			
			// test planets
			for (j = 0; j < n_planets; j++)
			{
				float occlusionNumber;
				if (entityByEntityOcclusionToValue(e1, planets[j], the_sun, &occlusionNumber))
				{
					e1->isSunlit = NO;
					e1->shadingEntityID = [planets[j] universalID];
					break;
				}
				if ([e1 isPlayer])
				{
					[(PlayerEntity *)e1 setOcclusionLevel:occlusionNumber];
				}
			}
			if (!e1->isSunlit)
			{
				// no point in continuing tests
				continue;
			}
			
			// test local entities
			for (j = 0; j < n_ships; j++)
			{
				if (testEntityOccludedByEntity(e1, ships[j], the_sun))
				{
					e1->isSunlit = NO;
					e1->shadingEntityID = [ships[j] universalID];
					break;
				}
			}
		}
	}
}


- (NSString *) collisionDescription
{
	return [NSString stringWithFormat:@"p%u - c%u", checks_this_tick, checks_within_range];
}


- (NSString *) debugOut
{
	NSMutableString *result = [[NSMutableString alloc] initWithFormat:@"%d:", n_entities];
	CollisionRegion *sub = nil;
	foreach (sub, subregions)
	{
		[result appendString:[sub debugOut]];
	}
	return [result autorelease];
}

@end
