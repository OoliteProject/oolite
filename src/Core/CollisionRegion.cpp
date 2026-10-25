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

#include "CollisionRegion.h"
#include "OOMaths.h"
#include "Universe.h"
#include "Entity.h"
#include "ShipEntity.h"
#include "OOSunEntity.h"
#include "OOPlanetEntity.h"
#include "StationEntity.h"
#include "PlayerEntity.h"
#include "OODebugFlags.h"
#include "oofnd/objc/OOException.h"

#include "oofnd/Log.hpp"

#include "oofnd/String.hpp"


// basic alloc/ dealloc routines
//
static int crid_counter = 1;


namespace {

/*	What the root facade's selectors answered for an entity (bead oo-9ht.39.27): the C++ member each
	forwarded to (an Objective-C stand-in was messaged until bead oo-j12i2). -isPlayer, -isShip,
	-isPlanet and -status are oo::EntityIsPlayer() etc. (Entity+ObjCBridge.h, bead oo-9ht.39.16).
*/
bool EntityIsVisible(Entity *entity)
{
	return entity != nullptr && entity->isVisible();	// nil's answer for none
}

OOUniversalID EntityUniversalID(Entity *entity)
{
	return entity != nullptr ? entity->getUniversalID() : OOUniversalID{};
}

bool EntityChecksCloseCollisionWith(Entity *entity, Entity *other)
{
	return entity != nullptr && entity->checkCloseCollisionWith(other);
}

}	// namespace


CollisionRegion::CollisionRegion()	// Designated initializer.
{
	{
		max_entities = COLLISION_MAX_ENTITIES;
		entity_array = (Entity **)malloc(max_entities * sizeof(Entity *));
		if (entity_array == NULL)
		{
			// -init released itself and returned nil; a constructor cannot, so it raises what
			// -addEntity: raises when the list cannot grow (ADR-0056 amendment oo-44gg).
			OORaiseException(OOMallocException, "Not enough memory to create collision region member list.");
		}
		
		crid = crid_counter++;
	}
}


CollisionRegion::CollisionRegion(AsUniverse) : CollisionRegion()
{
	{
		isUniverse = YES;
	}
}


CollisionRegion::CollisionRegion(HPVector locn, GLfloat rad, CollisionRegion *otherRegion) : CollisionRegion()
{
	{
		location = locn;
		radius = rad;
		border_radius = COLLISION_REGION_BORDER_RADIUS;
		parentRegion = otherRegion;
	}
}


CollisionRegion::~CollisionRegion()
{
	free(entity_array);
	subregions.clear();
}


// OOObject's -description wraps this as "<CollisionRegion 0x...>{ID: ...}", which is what this
// class's own -description printed.
std::optional<std::string> CollisionRegion::descriptionComponents() const
{
	return oo::str::format("ID: %d, %zu subregions, %u ents", crid, subregions.size(), n_entities);
}


void CollisionRegion::clearSubregions()
{
	for (const auto &sub : subregions)  sub->clearSubregions();
	subregions.clear();
}


void CollisionRegion::addSubregionAtPosition(HPVector pos, GLfloat rad)
{
	// check if this can be fitted within any of the subregions
	//
	for (const auto &subRef : subregions)
	{
		CollisionRegion *sub = subRef.get();
		if (sphereIsWithinRegion(pos, rad, sub))
		{
			// if it fits, put it in!
			sub->addSubregionAtPosition(pos, rad);
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
	if (subregions.empty())  subregions.reserve(32);
	subregions.push_back(oo::makeRef<CollisionRegion>(pos, rad, this));
}


// update routines to check if a position is within the radius or within its borders
//
bool CollisionRegion::positionIsWithinRegion(HPVector position, CollisionRegion *region)
{
	if (region == nullptr)  return NO;
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


bool CollisionRegion::sphereIsWithinRegion(HPVector position, GLfloat rad, CollisionRegion *region)
{
	if (region == nullptr)  return NO;
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


bool CollisionRegion::positionIsWithinBorders(HPVector position, CollisionRegion *region)
{
	if (region == nullptr)  return NO;
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
void CollisionRegion::clearEntityList()
{
	for (const auto &sub : subregions)  sub->clearEntityList();
	n_entities = 0;
	isPlayerInRegion = NO;
}


void CollisionRegion::addEntity(Entity *ent)
{
	// expand if necessary
	//	
	if (n_entities == max_entities)
	{
		max_entities = 1 + max_entities * 2;
		Entity **new_store = (Entity **)realloc(static_cast<void *>(entity_array), max_entities * sizeof(Entity *));
		if (new_store == NULL)
		{
			OORaiseException(OOMallocException, "Not enough memory to grow collision region member list.");
		}
		
		entity_array = new_store;
	}
	
	if (EntityIsPlayer(ent))  isPlayerInRegion = YES;
	entity_array[n_entities++] = ent;
}


bool CollisionRegion::checkEntity(Entity *ent)
{
	HPVector position = ent->position;
	
	// check subregions
	for (const auto &sub : subregions)
	{
		if (positionIsWithinBorders(position, sub.get()) && sub->checkEntity(ent))
		{
			return YES;
		}
	}
	
	if (!positionIsWithinBorders(position, this))
	{
		return NO;
	}
	
	addEntity(ent);
	ent->setCollisionRegion(this);
	return YES;
}


void CollisionRegion::findCollisions()
{
	// test for collisions in each subregion
	for (const auto &sub : subregions)  sub->findCollisions();
	
	// reject trivial cases
	if (n_entities < 2)  return;
	
	//
	// According to Shark, when this was in Universe this was where Oolite spent most time!
	//
	Entity		*e1, *e2;	// C++ parts (bead oo-9ht.39.4)
	HPVector		p1;
	double		dist2, r1, r2, r0, min_dist2;
	unsigned	i;
	std::vector<Entity *>	entities_to_test(n_entities);
	
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
		OO_LOG("collisionRegion.debug", "DEBUG in collision region {} testing {} out of {} entities", oo::str::format("<CollisionRegion %s>{%s}", oo::str::pointerDescription(this).c_str(), descriptionComponents().value_or("").c_str()), n_entities_to_test, n_entities);
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
			if (std::vector<oo::EntityHold> *colliding = e1->getCollidingEntities())  colliding->clear();
			e1->hasCollided = NO;
		}
		if (e1->isShip)
		{
			if (oo::ToShip(e1) != nullptr)  oo::ToShip(e1)->setProximityAlert(nullptr);
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
			if (e1->isShip && e2->isShip && 
				(oo::ToShip(e1) != nullptr ? oo::ToShip(e1)->collisionExceptedFor(oo::ToShip(e2)) : false)) 
			{
				// nothing happens
			} 
			else
			{

				r2 = e2->collision_radius;
				r0 = r1 + r2;
				dist2 = HPdistance2(e2->position, p1);
				min_dist2 = r0 * r0;
				if (dist2 < PROXIMITY_WARN_DISTANCE2 * min_dist2)
				{
#ifndef NDEBUG
					if (gDebugFlags & DEBUG_COLLISIONS)
					{
						OO_LOG("collisionRegion.debug", "DEBUG Testing collision between {} ({}) and {} ({})",
							  oo::EntityDescription(e1), (e1->collisionTestFilter==3)?"YES":"NO", oo::EntityDescription(e2), (e2->collisionTestFilter==3)?"YES":"NO");
					}
#endif
					checks_within_range++;
				
					if (e1->isShip && e2->isShip)
					{
						if ((dist2 < PROXIMITY_WARN_DISTANCE2 * r2 * r2) || (dist2 < PROXIMITY_WARN_DISTANCE2 * r1 * r1))
						{
							if (oo::ToShip(e1) != nullptr)  oo::ToShip(e1)->setProximityAlert(oo::ToShip(e2));
							if (oo::ToShip(e2) != nullptr)  oo::ToShip(e2)->setProximityAlert(oo::ToShip(e1));
						}

						if (dist2 >= min_dist2)
						{
							if (e1->isStation)
							{
								::StationEntity* se1 = oo::ToStation(e1);
								if (se1 != nullptr)  se1->shipIsInDockingCorridor(oo::ToShip(e2));
							}
							else if (e2->isStation)
							{
								::StationEntity* se2 = oo::ToStation(e2);
								if (se2 != nullptr)  se2->shipIsInDockingCorridor(oo::ToShip(e1));
							}
						}

					}
					if (dist2 < min_dist2)
					{
						BOOL collision = NO;
					
						if (e1->isStation)
						{
							::StationEntity* se1 = oo::ToStation(e1);
							if ((se1 != nullptr ? se1->shipIsInDockingCorridor(oo::ToShip(e2)) : false))
							{
								collision = NO;
							}
							else
							{
								collision = EntityChecksCloseCollisionWith(e1, e2);
							}
						}
						else if (e2->isStation)
						{
							::StationEntity* se2 = oo::ToStation(e2);
							if ((se2 != nullptr ? se2->shipIsInDockingCorridor(oo::ToShip(e1)) : false))
							{
								collision = NO;
							}
							else
							{
								collision = EntityChecksCloseCollisionWith(e2, e1);
							}
						}
						else
						{
							collision = EntityChecksCloseCollisionWith(e1, e2);
						}
				
						if (collision)
						{
							// now we have no need to check the e2-e1 collision
							if (e1->collider)
							{
								if (std::vector<oo::EntityHold> *colliding = e1->getCollidingEntities())  colliding->emplace_back(e1->collider);
							}
							else
							{
								if (std::vector<oo::EntityHold> *colliding = e1->getCollidingEntities())  colliding->emplace_back(e2);
							}
							e1->hasCollided = YES;
						
							if (e2->collider)
							{
								if (std::vector<oo::EntityHold> *colliding = e2->getCollidingEntities())  colliding->emplace_back(e2->collider);
							}
							else
							{
								if (std::vector<oo::EntityHold> *colliding = e2->getCollidingEntities())  colliding->emplace_back(e1);
							}
							e2->hasCollided = YES;
						}
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
		OO_LOG("collisionRegion.debug","Collision test checks {}, within range {}, for {} entities",checks_this_tick,checks_within_range,n_entities_to_test);
	}
#endif
}



namespace {

// an outValue of 1 means it's just being occluded.
BOOL entityByEntityOcclusionToValue(Entity *e1, Entity *e2, OOSunEntity *the_sun, float *outValue)
{
	if (EXPECT_NOT(e1 == e2))
	{
		// you can't shade self
		return NO;
	}
	return shadowAtPointOcclusionToValue(e1->position,e1->collision_radius,e2,the_sun,outValue);
}

}	// namespace

// an outValue of 1 means it's just being occluded.
BOOL shadowAtPointOcclusionToValue(HPVector e1pos, GLfloat e1rad, Entity *e2, OOSunEntity *the_sun, float *outValue)
{
	*outValue = 1.5f;	// initial 'fully lit' value
	
	GLfloat cr_e2;
	if (EntityIsShip(e2))
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
	GLfloat d2_e2 = HPdistance2( e1pos, e2->position);

	if (d2_e2sun > d2_sun)
	{
		// you are nearer the sun than the potential occluder, so it
		// probably can't shade you
		if (d2_e2 < cr_e2 * cr_e2 && EntityIsShip(e2))
		{
			// exception: if within the collision radius of the other
			// object, might still be shadowed by it.
			GLfloat bbx = 0.0f, bby = 0.0f, bbz = 0.0f;
			BoundingBox bb = (oo::ToShip(e2) != nullptr ? oo::ToShip(e2)->getTotalBoundingBox() : BoundingBox{});
			bounding_box_get_dimensions(bb,&bbx,&bby,&bbz);
			float minbb = bbx;
			if (bby < minbb) { minbb = bby; }
			if (bbz < minbb) { minbb = bbz; }
			minbb -= e1rad; // subtract object's size
			/* closer to the object than the shortest axis. This check
			 * branch is basically for docking at a rock hermit facing
			 * away from the sun, but it checks the shortest bounding
			 * box size rather than the collision radius to avoid
			 * getting weird shadowing effects around large planar
			 * entities like the OXP Torus Station.
			 *
			 * Well... more weird shadowing effects than there already
			 * are, anyway.
			 *
			 * There are more accurate ways to check "sphere inside
			 * bounding box" but this seems accurate enough and is
			 * simpler.
			 *
			 * - CIM
			 */ 
			if (d2_e2 < minbb * minbb)
			{
				*outValue = 0.1;
				return YES;
			}
		}
		return NO;
	}
	
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
	float d2_e = sqrt(d2_e2);
	float theta_diff;
	if (d2_e < cr_e2)
	{
		// then we're "inside" the object. Calculate as if we were on
		// the edge of it to avoid taking asin(x>1)
		theta_diff = asin(1) - asin(cr_sun / sqrt(d2_sun));
	}
	else
	{
		theta_diff = asin(cr_e2 / d2_e) - asin(cr_sun / sqrt(d2_sun));
	}
	
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


namespace {

inline BOOL testEntityOccludedByEntity(Entity *e1, Entity *e2, OOSunEntity *the_sun)
{
	float tmp;		// we're not interested in the amount of occlusion just now.
	return entityByEntityOcclusionToValue(e1, e2, the_sun, &tmp);
}

}	// namespace


void CollisionRegion::findShadowedEntities()
{
	// reject trivial cases
	if (n_entities < 2)  return;
	
	//
	// Copy/pasting the collision code to detect occlusion!
	//
	unsigned i, j;
	
	if ((UNIVERSE != nullptr ? UNIVERSE->reducedDetail() : false))  return;	// don't do this in reduced detail mode
	
	::OOSunEntity* the_sun = (UNIVERSE != nullptr ? UNIVERSE->sun() : nullptr);
	
	if (the_sun == nil)
	{
		return;	// sun is required
	}
	
	unsigned	ent_count =	UNIVERSE->n_entities;
	Entity		**uni_entities = UNIVERSE->sortedEntities;	// grab the public sorted list
	std::vector<Entity *>	planets(ent_count);
	unsigned	n_planets = 0;
	std::vector<Entity *>	ships(ent_count);
	unsigned	n_ships = 0;
	
	for (i = 0; i < ent_count; i++)
	{
		if (uni_entities[i]->isSunlit)
		{
			// get a list of planet entities because they can shade across regions
			if (EntityIsPlanet(uni_entities[i]))
			{
				//	don't bother retaining - nothing will happen to them!
				planets[n_planets++] = uni_entities[i];
			}
			
			// and a list of shipentities large enough that they might cast a noticeable shadow
			// if we can't see it, it can't be shadowing anything important
			else if (EntityIsShip(uni_entities[i]) &&
					 EntityIsVisible(uni_entities[i]) && 
					 uni_entities[i]->collision_radius >= MINIMUM_SHADOWING_ENTITY_RADIUS)
			{
				ships[n_ships++] = uni_entities[i];		//	don't bother retaining - nothing will happen to them!
			}
		}
	}
	
	// test for shadows in each subregion
	for (const auto &sub : subregions)  sub->findShadowedEntities();
	
	// test each entity in this region against the others
	for (i = 0; i < n_entities; i++)
	{
		Entity *e1 = entity_array[i];
		if (!EntityIsVisible(e1))
		{
			continue; // don't check shading of objects we can't see
		}
		BOOL occluder_moved = NO;
		if (EntityStatus(e1) == STATUS_COCKPIT_DISPLAY)
		{
			e1->isSunlit = YES;
			e1->shadingEntityID = NO_TARGET;
			continue;	// don't check shading in demo mode
		}
		Entity *occluder = nullptr;
		if (e1->isSunlit == NO)
		{
			occluder = (UNIVERSE != nullptr ? UNIVERSE->entityForUniversalID(e1->shadingEntityID) : nullptr);
			if (occluder != nil)
			{
				occluder_moved = occluder->hasMoved;
			}
		}
		if ((EntityIsShip(e1) || EntityIsPlanet(e1)) && (e1->hasMoved || occluder_moved))
		{
			e1->isSunlit = YES;				// sunlit by default
			e1->shadingEntityID = NO_TARGET;
			//
			// check demo mode here..
			if (EntityIsPlayer(e1) && (static_cast<PlayerEntity *>(e1)->getShowDemoShips()))
			{
				continue;	// don't check shading in demo mode
			}
			
			// test last occluder (most likely case)
			if (occluder)
			{
				if (testEntityOccludedByEntity(e1, occluder, the_sun))	
				{
					e1->isSunlit = NO;
					e1->shadingEntityID = EntityUniversalID(occluder);
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
					e1->shadingEntityID = EntityUniversalID(planets[j]);
					break;
				}
				if (EntityIsPlayer(e1))
				{
					static_cast<PlayerEntity *>(e1)->setOcclusionLevel(occlusionNumber);
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
					e1->shadingEntityID = EntityUniversalID(ships[j]);
					break;
				}
			}
		}
	}
}


std::string CollisionRegion::collisionDescription()
{
	return oo::str::format("p%u - c%u", checks_this_tick, checks_within_range);
}


std::optional<std::string> CollisionRegion::debugOut()
{
	std::string result = oo::str::format("%d:", n_entities);
	for (const auto &sub : subregions)
	{
		if (const auto subOut = sub->debugOut())  result += *subOut;
	}
	return result;
}
