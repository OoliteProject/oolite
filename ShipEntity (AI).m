//
//  ShipEntity (AI).m
//  Oolite
//
/*
 *
 *  Oolite
 *
 *  Created by Giles Williams on Sun Aug 08 2004.
 *  Copyright (c) 2004 for aegidian.org. All rights reserved.
 *

Copyright (c) 2004, Giles C Williams
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
//

#import "ShipEntity.h"
#import "entities.h"
#import "vector.h"
#import "Universe.h"
#import "AI.h"

@interface ShipEntity (AI)

/*-----------------------------------------

	methods for AI

-----------------------------------------*/

- (void) pauseAI:(NSString *)intervalString;

- (void) setDestinationToCurrentLocation;

- (void) setDesiredRangeTo:(NSString *)rangeString;

- (void) setSpeedTo:(NSString *)speedString;

- (void) setSpeedFactorTo:(NSString *)speedString;

- (void) performFlyToRangeFromDestination;

- (void) performIdle;

- (void) performHold;

- (void) setTargetToPrimaryAggressor;

- (void) performAttack;

- (void) scanForNearestMerchantmen;
- (void) scanForRandomMerchantmen;

- (void) scanForLoot;

- (void) scanForRandomLoot;

- (void) setTargetToFoundTarget;

- (void) checkForFullHold;

- (void) performCollect;

- (void) performIntercept;

- (void) performFlee;

- (void) requestDockingCoordinates;
//- (void) setSpeedAsAdvised;

- (void) getWitchspaceEntryCoordinates;

- (void) setDestinationFromCoordinates;

- (void) performDocking;

- (void) performFaceDestination;

- (void) performTumble;

- (void) fightOrFleeMissile;

- (PlanetEntity *) findNearestPlanet;

- (void) setCourseToPlanet;

- (void) setTakeOffFromPlanet;

- (void) landOnPlanet;

- (void) setAITo:(NSString *)aiString;

- (void) checkTargetLegalStatus;

- (void) exitAI;

- (void) setDestinationToTarget;

- (void) checkCourseToDestination;

- (void) scanForOffenders;

- (void) setCourseToWitchpoint;

- (void) performHyperSpaceExit;

- (void) commsMessage:(NSString *)valueString;
- (void) broadcastDistressMessage;
- (void) acceptDistressMessageFrom:(ShipEntity *)other;

- (void) ejectCargo;

- (void) scanForThargoid;
- (void) scanForNonThargoid;

- (void) initialiseTurret;

- (void) checkDistanceTravelled;

- (void) scanForHostiles;

- (void) fightOrFleeHostiles;

- (void) suggestEscort;

- (void) escortCheckMother;

- (void) performEscort;

- (int) numberOfShipsInGroup:(int) ship_group_id;

- (void) checkGroupOddsVersusTarget;

- (void) groupAttackTarget;

- (void) scanForFormationLeader;

- (void) messageMother:(NSString *)msgString;

- (void) setPlanetPatrolCoordinates;

- (void) setSunSkimStartCoordinates;

- (void) setSunSkimEndCoordinates;

- (void) setSunSkimExitCoordinates;

- (void) patrolReportIn;

- (void) checkForMotherStation;

- (void) sendTargetCommsMessage:(NSString*) message;

- (void) markTargetForFines;

- (void) scanForRocks;

- (void) performMining;

- (void) setDestinationToDockingAbort;

- (void) requestNewTarget;

@end


/*****************************************/


@implementation ShipEntity (AI)

/*-----------------------------------------

	methods for AI

-----------------------------------------*/

- (void) pauseAI:(NSString *)intervalString
{
	[shipAI setNextThinkTime:[universe getTime] + [intervalString doubleValue]];
}

- (void) setDestinationToCurrentLocation
{
	destination = position;
	destination.x += (ranrot_rand() % 100)*0.01 - 0.5;		// randomly add a .5m variance
	destination.y += (ranrot_rand() % 100)*0.01 - 0.5;
	destination.z += (ranrot_rand() % 100)*0.01 - 0.5;
}

- (void) setDesiredRangeTo:(NSString *)rangeString
{
	desired_range = [rangeString doubleValue];
}

- (void) performFlyToRangeFromDestination
{
	//NSLog(@"ShipEntity.performFlyToRangeFromDestination NOT YET IMPLEMENTED");
	condition = CONDITION_FLY_RANGE_FROM_DESTINATION;
}

- (void) setSpeedTo:(NSString *)speedString
{
	desired_speed = [speedString doubleValue];
}

- (void) setSpeedFactorTo:(NSString *)speedString
{
	desired_speed = max_flight_speed * [speedString doubleValue];
}

- (void) performIdle
{
	condition = CONDITION_IDLE;
}

- (void) performHold
{
	desired_speed = 0.0;
	condition = CONDITION_TRACK_TARGET;
}

- (void) setTargetToPrimaryAggressor
{
	if (![universe entityForUniversalID:primaryAggressor])
		return;
	if (primaryTarget == primaryAggressor)
		return;
		
	// a more considered approach here:
	// if we're already busy attacking a target we don't necessarily want to break off
	//
	switch (condition)
	{
		case CONDITION_ATTACK_FLY_FROM_TARGET:
		case CONDITION_ATTACK_FLY_TO_TARGET:
			if (randf() < 0.75)	// if I'm attacking, ignore 75% of new aggressor's attacks
				return;
			break;
		
		default:
			break;
	}
	
	// inform our old target of our new target
	//
	if ([[universe entityForUniversalID:primaryTarget] isKindOfClass:[ShipEntity class]])
	{
		ShipEntity* currentShip = (ShipEntity*)[universe entityForUniversalID:primaryTarget];
		[[currentShip getAI] message:[NSString stringWithFormat:@"%@ %d %d", AIMS_AGGRESSOR_SWITCHED_TARGET, universal_id, primaryAggressor]];
	}
	
	// okay, so let's now target the aggressor
	[self addTarget:[universe entityForUniversalID:primaryAggressor]];
}

- (void) performAttack
{
	condition = CONDITION_ATTACK_TARGET;
}

- (void) scanForNearestMerchantmen
{
	//-- Locates the nearest merchantman in range --//
	NSArray* entList = [[universe getAllEntities] retain];
	int i;
//	double found_d2 = desired_range*desired_range;
	double found_d2 = scanner_range * scanner_range;
	found_target = NO_TARGET;
	for (i = 0; i < [entList count] ; i++)
	{
		Entity* thing = (Entity *)[entList objectAtIndex:i];
		if (([thing isKindOfClass:[ShipEntity class]])&&(thing != (Entity *)self))
		{
			ShipEntity* ship = (ShipEntity *)thing;
			if ((([[ship roles] isEqual:@"trader"])||([ship isKindOfClass:[PlayerEntity class]]))&&([ship getStatus] != STATUS_DEAD)&&([ship getStatus] != STATUS_DOCKED))
			{
				double d2;
				Vector delta = [ship getPosition];
				delta.x -= position.x;  delta.y -= position.y;  delta.z -= position.z;
				d2 = delta.x*delta.x + delta.y*delta.y + delta.z*delta.z;
				if (([roles isEqual:@"pirate"])&&(d2*d2 < desired_range)&&([ship isKindOfClass:[PlayerEntity class]])&&(PIRATES_PREFER_PLAYER))
					d2 = 0.0;
				if (d2 < found_d2)
				{
					found_d2 = d2;
					found_target = [ship universal_id];
				}
			}
		}
	}
	[entList release];
	if (found_target != NO_TARGET)
		[shipAI message:@"TARGET_FOUND"];
	else
		[shipAI message:@"NOTHING_FOUND"];
}

- (void) scanForRandomMerchantmen
{
	//-- Locates one of the merchantman in range --//
	NSArray* entList = [[universe getAllEntities] retain];
	int ids_found[[entList count]];
	int n_found = 0;
	int i;
//	double found_d2 = desired_range*desired_range;
	double found_d2 = scanner_range * scanner_range;
	found_target = NO_TARGET;
	for (i = 0; i < [entList count] ; i++)
	{
		Entity* thing = (Entity *)[entList objectAtIndex:i];
		if (([thing isKindOfClass:[ShipEntity class]])&&(thing != (Entity *)self))
		{
			ShipEntity* ship = (ShipEntity *)thing;
			if ((([[ship roles] isEqual:@"trader"])||([ship isKindOfClass:[PlayerEntity class]]))&&([ship getStatus] != STATUS_DEAD)&&([ship getStatus] != STATUS_DOCKED))
			{
				double d2;
				Vector delta = [ship getPosition];
				delta.x -= position.x;  delta.y -= position.y;  delta.z -= position.z;
				d2 = delta.x*delta.x + delta.y*delta.y + delta.z*delta.z;
				if (d2 < found_d2)
				{
					ids_found[n_found] = [ship universal_id];
					n_found++;
				}
			}
		}
	}
	[entList release];
	if (n_found == 0)
	{
		[shipAI message:@"NOTHING_FOUND"];
		return;
	}
	i = ranrot_rand() % n_found;	// pick a number from 0 -> (n_found - 1)
	found_target = ids_found[i];
	[shipAI message:@"TARGET_FOUND"];
	return;
}

- (void) scanForLoot
{
	/*-- Locates the nearest debris in range --*/
	if ((![self isKindOfClass:[StationEntity class]])&&(!has_scoop))
	{
		[shipAI message:@"NOTHING_FOUND"];		//can't collect loot if you have no scoop!
		return;
	}
	NSArray* entList = [[universe getAllEntities] retain];
	int i;
//	double found_d2 = desired_range*desired_range;
	double found_d2 = scanner_range * scanner_range;
	found_target = NO_TARGET;
	for (i = 0; i < [entList count]; i++)
	{
		Entity* thing = (Entity *)[entList objectAtIndex:i];
		if ([thing isKindOfClass:[ShipEntity class]])
		{
			ShipEntity *other = (ShipEntity *)thing;
			if (([other scanClass] == CLASS_CARGO)&&([other getCargoType] != CARGO_NOT_CARGO))
			{
				double d2;
				Vector delta = [thing getPosition];
				delta.x -= position.x;  delta.y -= position.y;  delta.z -= position.z;
				d2 = delta.x*delta.x + delta.y*delta.y + delta.z*delta.z;
				if (d2 < found_d2)
				{
					found_d2 = d2;
					found_target = [thing universal_id];
				}
			}
		}
	}
	[entList release];
	if (found_target != NO_TARGET)
		[shipAI message:@"TARGET_FOUND"];
	else
		[shipAI message:@"NOTHING_FOUND"];
}

- (void) scanForRandomLoot
{
	/*-- Locates the all debris in range and chooses a piece at random from the first sixteen found --*/
	NSArray* entList = [[universe getAllEntities] retain];
	int thing_uids_found[16];
	int i, things_found;
//	double found_d2 = desired_range*desired_range;
	double found_d2 = scanner_range * scanner_range;
	found_target = NO_TARGET;
	if ((![self isKindOfClass:[StationEntity class]])&&(!has_scoop))
	{
		[shipAI message:@"NOTHING_FOUND"];		//can't collect loot if you have no scoop!
		return;
	}
	things_found = 0;
	for (i = 0; (i < [entList count])&&(things_found < 16) ; i++)
	{
		Entity* thing = (Entity *)[entList objectAtIndex:i];
		if ([thing isKindOfClass:[ShipEntity class]])
		{
			ShipEntity *other = (ShipEntity *)thing;
			if (([other scanClass] == CLASS_CARGO)&&([other getCargoType] != CARGO_NOT_CARGO))
			{
				double d2;
				Vector delta = [thing getPosition];
				delta.x -= position.x;  delta.y -= position.y;  delta.z -= position.z;
				d2 = delta.x*delta.x + delta.y*delta.y + delta.z*delta.z;
				if (d2 < found_d2)
				{
					found_target = [thing universal_id];
					thing_uids_found[things_found++] = [thing universal_id];
				}
			}
		}
	}
	[entList release];
	if (found_target != NO_TARGET)
	{
		found_target = thing_uids_found[ranrot_rand() % things_found];
		[shipAI message:@"TARGET_FOUND"];
	}
	else
		[shipAI message:@"NOTHING_FOUND"];
}

- (void) setTargetToFoundTarget
{
	if ([universe entityForUniversalID:found_target])
		[self addTarget:[universe entityForUniversalID:found_target]];
}

- (void) checkForFullHold
{
	if ([cargo count] >= max_cargo)
		[shipAI message:@"HOLD_FULL"];
}

- (void) performCollect
{
	condition = CONDITION_COLLECT_TARGET;
}

- (void) performIntercept
{
	condition = CONDITION_INTERCEPT_TARGET;
}

- (void) performFlee
{
	condition = CONDITION_FLEE_TARGET;
}

- (void) requestDockingCoordinates
{
	/*- requests coordinates from the nearest station it can find (which may be a rock hermit) -*/
	StationEntity* station =  nil;
	
	if ([[universe entityForUniversalID:targetStation] isKindOfClass:[StationEntity class]])
	{
		station = (StationEntity*)[universe entityForUniversalID:targetStation];
	}
	else
	{
		NSArray* entList = [[universe getAllEntities] retain];
		Vector  p1 = position;
		double nearest2 = SCANNER_MAX_RANGE2 * 1000000.0; // 1000x scanner range (25600 km), squared.
		int i;
		for (i = 0; i < [entList count]; i++)
		{
			Entity* thing = (Entity *)[entList objectAtIndex:i];
			if ([thing isKindOfClass:[StationEntity class]])
			{
				Vector p2 = [thing getPosition];
				p2.x -= p1.x;   p2.y -= p1.y; p2.z -= p1.z;
				double range2 = (p2.x * p2.x + p2.y * p2.y + p2.z * p2.z);
				if (range2 < nearest2)
				{
					station = (StationEntity *)thing;
					targetStation = [station universal_id];
					nearest2 = range2;
				}
			}
		}
		[entList release];
	}
	//
	if (station)
	{
		//NSLog(@"Station '%@' %@ with universal_id %d",[station name],station,[station universal_id]);
		coordinates = [station nextDockingCoordinatesForShip:self];
	}
	else
	{
		[shipAI message:@"NO_STATION_FOUND"];
	}
}

//- (void) setSpeedAsAdvised
//{
//	StationEntity* station = (StationEntity*)[universe entityForUniversalID:targetStation];
//	if (station)
//		desired_speed = [station approachSpeedForShip:self];
//	else
//		desired_speed = 50.0;
//}
//

- (void) getWitchspaceEntryCoordinates
{
	/*- calculates coordinates from the nearest station it can find, or just fly 10s forward -*/
	NSArray* entList = [[universe getAllEntities] retain];
	StationEntity* station =  nil;
	Vector  p1 = position;
	double nearest2 = SCANNER_MAX_RANGE2 * 1000000.0; // 1000x scanner range (25600 km), squared.
	int i;
	for (i = 0; i < [entList count]; i++)
	{
		Entity* thing = (Entity *)[entList objectAtIndex:i];
		if ([thing isKindOfClass:[StationEntity class]])
		{
			Vector p2 = [thing getPosition];
			p2.x -= p1.x;   p2.y -= p1.y; p2.z -= p1.z;
			double range2 = (p2.x * p2.x + p2.y * p2.y + p2.z * p2.z);
			if (range2 < nearest2)
			{
				station = (StationEntity *)thing;
				nearest2 = range2;
			}
		}
	}
	[entList release];
	if (station)
	{
		coordinates = [station getPosition];
		Vector  vr = vector_right_from_quaternion([station QRotation]);
		coordinates.x += 10000 * vr.x;  // 10km from station
		coordinates.y += 10000 * vr.y;
		coordinates.z += 10000 * vr.z;
	}
	else
	{
		coordinates = position;
		coordinates.x += v_forward.x * max_flight_speed * 10.0;
		coordinates.y += v_forward.y * max_flight_speed * 10.0;
		coordinates.z += v_forward.z * max_flight_speed * 10.0;
	}
	//[shipAI message:@"OKAY"];
}

- (void) setDestinationFromCoordinates
{
	destination = coordinates;
}

- (void) performDocking
{
	//NSLog(@"ShipEntity.performDocking NOT IMPLEMENTED!");
}

- (void) performFaceDestination
{
	condition = CONDITION_FACE_DESTINATION;
}

- (void) performTumble
{
	flight_roll = max_flight_roll*2.0*(randf() - 0.5);
	flight_pitch = max_flight_pitch*2.0*(randf() - 0.5);
//	velocity = make_vector( flight_speed*2.0*(randf() - 0.5), flight_speed*2.0*(randf() - 0.5), flight_speed*2.0*(randf() - 0.5));
	condition = CONDITION_TUMBLE;
}

- (void) fightOrFleeMissile
{
	NSArray* entList = [[universe getAllEntities] retain];
	ShipEntity* missile =  nil;
	int i;
	for (i = 0; (i < [entList count])&&(missile == nil); i++)
	{
		Entity* thing = (Entity *)[entList objectAtIndex:i];
		if ([thing scanClass] == CLASS_MISSILE)
		{
			if ([(ShipEntity *)thing getPrimaryTarget] == self)
				missile = (ShipEntity *)thing;
			if ((n_escorts > 0)&&(missile == nil))
			{
				int j;
				for (j = 0; j < n_escorts; j++)
				{
					if ([(ShipEntity *)thing getPrimaryTargetID] == escort_ids[j])
						missile = (ShipEntity *)thing;
				}
			}
		}
	}
	[entList release];
	
	//NSLog(@"---> %@ %d targetting the Missile %d", name, universal_id, [missile universal_id]);
	if (missile)
	{
		[self addTarget:missile];
	}
	
	if ((missile)&&(has_ecm))
	{
		// use the ECM and battle on
		//NSLog(@"---> and firing ecm!");
		ShipEntity* hunter = (ShipEntity*)[missile owner];
		
		[self setPrimaryAggressor:hunter];	// lets get them now for that!
		found_target = primaryAggressor;
		
		if ([roles isEqual:@"police"]||[roles isEqual:@"interceptor"]||[roles isEqual:@"wingman"])
		{
			NSArray	*fellow_police = [self shipsInGroup:group_id];
			int i;
			for (i = 0; i < [fellow_police count]; i++)
			{
				ShipEntity *other_police = (ShipEntity *)[fellow_police objectAtIndex:i];
				[other_police setFound_target:hunter];
				[other_police setPrimaryAggressor:hunter];
			}
		}
		
		// if I'm a copper and you're not, then mark the other as an offender!
		BOOL iAmTheLaw = ([roles isEqual:@"police"]||[roles isEqual:@"wingman"]||[roles isEqual:@"interceptor"]);
		BOOL uAreTheLaw = ([[hunter roles] isEqual:@"police"]||[[hunter roles] isEqual:@"wingman"]||[[hunter roles] isEqual:@"interceptor"]);
		if ((iAmTheLaw)&&(!uAreTheLaw))
			[hunter markAsOffender:64];
		
		[self fireECM];
		return;
	}
	
	if (missile)
	{
		//NSLog(@"---> and running away!");
		jink.x = 0.0;
		jink.y = 0.0;
		jink.z = 1000.0;
		desired_range = 10000;
		[self performFlee];
		[shipAI message:@"FLEEING"];
	}
}

// new

- (PlanetEntity *) findNearestPlanet
{
	/*- selects the nearest planet it can find -*/
	NSArray			*entList = [[universe getAllEntities] retain];
	PlanetEntity	*the_planet =  nil;
	Vector  p1 = position;
	double nearest2 = SCANNER_MAX_RANGE2 * 10000000000.0; // 100 000x scanner range (2 560 000 km), squared.
	int i;
	for (i = 0; i < [entList count]; i++)
	{
		Entity  *thing = (Entity *)[entList objectAtIndex:i];
		if ([thing isKindOfClass:[PlanetEntity class]])
		{
			if ([(PlanetEntity *)thing getPlanetType] == PLANET_TYPE_GREEN)
			{
				Vector p2 = [thing getPosition];
				p2.x -= p1.x;   p2.y -= p1.y; p2.z -= p1.z;
				double range2 = (p2.x * p2.x + p2.y * p2.y + p2.z * p2.z);
				if ((!the_planet)||(range2 < nearest2))
				{
					the_planet = (PlanetEntity *)thing;
					nearest2 = range2;
				}
			}
		}
	}
	[entList release];
	return the_planet;
}

- (void) setCourseToPlanet
{
	/*- selects the nearest planet it can find -*/
	PlanetEntity	*the_planet =  [self findNearestPlanet];
	if (the_planet)
	{
		destination = [the_planet getPosition];
		desired_range = [the_planet collisionRadius] + 100.0;   // 100m from the surface
	}
}

- (void) setTakeOffFromPlanet
{
	/*- selects the nearest planet it can find -*/
	PlanetEntity	*the_planet =  [self findNearestPlanet];
	if (the_planet)
	{
		destination = [the_planet getPosition];
		desired_range = [the_planet collisionRadius] + 10000.0;   // 10km from the surface
	}
	else
		NSLog(@"***** Ackk!! planet not found!!!");
}

- (void) landOnPlanet
{
	/*- selects the nearest planet it can find -*/
	PlanetEntity	*the_planet =  [self findNearestPlanet];
	if (the_planet)
	{
		[the_planet welcomeShuttle:self];   // 10km from the surface
	}
	[shipAI message:@"LANDED_ON_PLANET"];
	[universe removeEntity:self];
}

- (void) setAITo:(NSString *)aiString
{
	[[self getAI] setStateMachine:aiString];
}

- (void) checkTargetLegalStatus
{
	ShipEntity  *other_ship = (ShipEntity *)[universe entityForUniversalID:primaryTarget];
	if (!other_ship)
	{
		[shipAI message:@"NO_TARGET"];
		return;
	}
	else
	{
		int ls = [other_ship legal_status];
		if (ls > 50)
		{
			[shipAI message:@"TARGET_FUGITIVE"];
			return;
		}
		if (ls > 20)
		{
			[shipAI message:@"TARGET_OFFENDER"];
			return;
		}
		if (ls > 0)
		{
			[shipAI message:@"TARGET_MINOR_OFFENDER"];
			return;
		}
		[shipAI message:@"TARGET_CLEAN"];
	}
}

- (void) exitAI
{
	[shipAI exitStateMachine];
}

- (void) setDestinationToTarget
{
	destination = [[universe entityForUniversalID:primaryTarget] getPosition];
}

- (void) checkCourseToDestination
{
	if ([universe isVectorClearFromEntity:self toDistance:desired_range fromPoint:destination])
		[shipAI message:@"COURSE_OK"];
	else
	{
		destination = [universe getSafeVectorFromEntity:self toDistance:desired_range fromPoint:destination];
		[shipAI message:@"WAYPOINT_SET"];
	}
}

- (void) scanForOffenders
{
	/*-- Locates all the ships in range and compares their legal status or bounty against ranrot_rand() & 255 - chooses the worst offender --*/
	NSDictionary		*systeminfo = [universe currentSystemData];
	float gov_factor =	0.4 * [(NSNumber *)[systeminfo objectForKey:KEY_GOVERNMENT] intValue]; // 0 .. 7 (0 anarchic .. 7 most stable) --> [0.0, 0.4, 0.8, 1.2, 1.6, 2.0, 2.4, 2.8]

	NSArray* entList = [[universe getAllEntities] retain];
	int i;
	float	worst_legal_factor;
//	double found_d2 = desired_range*desired_range;
	double found_d2 = scanner_range * scanner_range;
	found_target = NO_TARGET;
	worst_legal_factor = 0;
	for (i = 0; i < [entList count] ; i++)
	{
		Entity* thing = (Entity *)[entList objectAtIndex:i];
		if (([thing isKindOfClass:[ShipEntity class]])&&([thing scanClass] != CLASS_CARGO))
		{
			ShipEntity* ship = (ShipEntity *)thing;
			if (([ship getStatus] != STATUS_DEAD)&&([ship getStatus] != STATUS_DOCKED))
			{
				double	d2;
				BOOL	is_thargoid = [[ship roles] isEqual:@"thargoid"];
				float	legal_factor = [ship legal_status] * gov_factor;
				if (is_thargoid)
					legal_factor += 500;
				int random_factor = ranrot_rand() & 255;   // 25% chance of spotting a fugitive in 15s
				Vector delta = [ship getPosition];
				delta.x -= position.x;  delta.y -= position.y;  delta.z -= position.z;
				d2 = delta.x*delta.x + delta.y*delta.y + delta.z*delta.z;
				if ((d2 < found_d2)&&(random_factor < legal_factor)&&(legal_factor > worst_legal_factor))
				{
					found_target = [ship universal_id];
					worst_legal_factor = legal_factor;
				}
			}
		}
	}
	[entList release];
	if (found_target != NO_TARGET)
		[shipAI message:@"TARGET_FOUND"];
	else
		[shipAI message:@"NOTHING_FOUND"];
}

- (void) setCourseToWitchpoint
{
	if (universe)
	{
		destination = [universe getWitchspaceExitPosition];
		desired_range = 10000.0;   // 10km away
	}
}

- (void) performHyperSpaceExit
{
	[self enterWitchspace];
}

- (void) commsMessage:(NSString *)valueString
{
	Random_Seed very_random_seed;
	very_random_seed.a = rand() & 255;
	very_random_seed.b = rand() & 255;
	very_random_seed.c = rand() & 255;
	very_random_seed.d = rand() & 255;
	very_random_seed.e = rand() & 255;
	very_random_seed.f = rand() & 255;
	seed_RNG_only_for_planet_description(very_random_seed);
	NSString* expandedMessage = [universe expandDescription:valueString forSystem:[universe systemSeed]];

//	NSLog(@"%@ %d sends message '%@'", name, universal_id, expandedMessage);
	[self broadcastMessage:expandedMessage];
}

- (void) broadcastDistressMessage
{
	/*-- Locates all the stations, bounty hunters and police ships in range and tells them that you are under attack --*/
	NSArray* entList = [[universe getAllEntities] retain];
	int i;
	double d2;
	double found_d2 = SCANNER_MAX_RANGE2;
	NSString* distress_message;
	found_target = NO_TARGET;
	BOOL	is_buoy = (scan_class == CLASS_BUOY);
	
	if (message_time > 2.0 * randf())
		return;					// don't send too many distress messages at once, space them out semi-randomly
	
	if (is_buoy)
		distress_message = @"[buoy-distress-call]";
	else
		distress_message = @"[distress-call]";
	
	for (i = 0; i < [entList count] ; i++)
	{
		Entity* thing = (Entity *)[entList objectAtIndex:i];
		if ([thing isKindOfClass:[ShipEntity class]])
		{
			Vector delta = [thing getPosition];
			delta.x -= position.x;  delta.y -= position.y;  delta.z -= position.z;
			d2 = delta.x*delta.x + delta.y*delta.y + delta.z*delta.z;
			if (d2 < found_d2)
			{
				ShipEntity  *ship = (ShipEntity *)thing;
				// tell it! //
				if ([ship isKindOfClass:[PlayerEntity class]])
				{
					if ((primaryAggressor == [ship universal_id])&&(energy < 0.375 * max_energy)&&(!is_buoy))
					{
						[self sendExpandedMessage:[universe expandDescription:@"[beg-for-mercy]" forSystem:[universe systemSeed]] toShip:ship];
						[self ejectCargo];
						[self performFlee];
					}
					else
						[self sendExpandedMessage:[universe expandDescription:distress_message forSystem:[universe systemSeed]] toShip:ship];
					// reset the thanked_ship_id
					//
					thanked_ship_id = NO_TARGET;
				}
				if ([ship isKindOfClass:[StationEntity class]])
					[ship acceptDistressMessageFrom:self];
				if ([[ship roles] isEqual:@"police"])
					[ship acceptDistressMessageFrom:self];
				if ([[ship roles] isEqual:@"hunter"])
					[ship acceptDistressMessageFrom:self];
			}
		}
	}
	[entList release];
}

- (void) acceptDistressMessageFrom:(ShipEntity *)other
{
	found_target = [[other getPrimaryTarget] universal_id];
	switch (condition)
	{
		case CONDITION_ATTACK_TARGET :
		case CONDITION_ATTACK_FLY_TO_TARGET :
		case CONDITION_ATTACK_FLY_FROM_TARGET :
			// busy - ignore the request
			break;
			
		case CONDITION_FLEE_TARGET :
			// scared - ignore the request;
			break;
			
		default :
			//NSLog(@"%@ %d responding to distress message from %@ %d", name, universal_id, [other name], [other universal_id]);
			if ([roles isEqual:@"police"]||[roles isEqual:@"interceptor"]||[roles isEqual:@"wingman"])
				[(ShipEntity *)[universe entityForUniversalID:found_target] markAsOffender:8];  // you have been warned!!
			[shipAI reactToMessage:@"ACCEPT_DISTRESS_CALL"];
			break;
	}
}

- (void) ejectCargo
{
	SEL _dumpCargoSelector = @selector(dumpCargo);
	int i;
	if ((cargo_flag == CARGO_FLAG_FULL_PLENTIFUL)||(cargo_flag == CARGO_FLAG_FULL_SCARCE))
	{
		NSArray* jetsam;
		int cargo_to_go = 0.1 * max_cargo;
		while (cargo_to_go > 15)
			cargo_to_go = ranrot_rand() % cargo_to_go;
		if (cargo_flag == CARGO_FLAG_FULL_PLENTIFUL)
			jetsam = [universe getContainersOfPlentifulGoods:cargo_to_go];
		else
			jetsam = [universe getContainersOfScarceGoods:cargo_to_go];
		if (!cargo)
			cargo = [[NSMutableArray alloc] initWithCapacity:max_cargo];
		[cargo addObjectsFromArray:jetsam];
		cargo_flag = CARGO_FLAG_CANISTERS;
	}
	[self dumpCargo];
	for (i = 1; i < [cargo count]; i++)
	{
		[self performSelector:_dumpCargoSelector withObject:nil afterDelay:0.75 * i];	// drop 3 canisters per 2 seconds
	}
}

- (void) scanForThargoid
{
	/*-- Locates all the thargoid warships in range and chooses the nearest --*/
	NSArray* entList = [[universe getAllEntities] retain];
	int i;
	double found_d2 = scanner_range * scanner_range;
	found_target = NO_TARGET;
	for (i = 0; i < [entList count] ; i++)
	{
		Entity* thing = (Entity *)[entList objectAtIndex:i];
		if ([thing isKindOfClass:[ShipEntity class]])
		{
			double d2;
			ShipEntity *ship = (ShipEntity *)thing;
			Vector delta = [thing getPosition];
			delta.x -= position.x;  delta.y -= position.y;  delta.z -= position.z;
			d2 = delta.x*delta.x + delta.y*delta.y + delta.z*delta.z;
			if (([[ship roles] isEqual:@"thargoid"])&&(d2 < found_d2))
			{
				found_target = [thing universal_id];
				found_d2 = d2;
			}
		}
	}
	if (found_target != NO_TARGET)
		[shipAI message:@"TARGET_FOUND"];
	else
	{
		if ([roles isEqual:@"tharglet"])
		{
			// now we're just a bunch of alien artefacts!
			scan_class = CLASS_CARGO;
			reportAImessages = NO;
			[shipAI setStateMachine:@"dumbAI.plist"];
			[shipAI setState:@"GLOBAL"];
			primaryTarget = NO_TARGET;
			[self setSpeed:0.0];
			for (i = 0; i < [entList count] ; i++)
			{
				Entity* thing = (Entity *)[entList objectAtIndex:i];
				if ([thing isKindOfClass:[ShipEntity class]])
				{
					ShipEntity* other = (ShipEntity*)thing;
					if (([other getPrimaryTarget] == self)&&([other hasHostileTarget]))
						[[other getAI] message:@"TARGET_LOST"];
				}
			}
		}
		[shipAI message:@"NOTHING_FOUND"];
	}
	[entList release];
}

- (void) scanForNonThargoid
{
	/*-- Locates all the non thargoid ships in range and chooses the nearest --*/
	NSArray* entList = [[universe getAllEntities] retain];
	int i;
	double found_d2 = scanner_range * scanner_range;
	found_target = NO_TARGET;
	for (i = 0; i < [entList count] ; i++)
	{
		Entity* thing = (Entity *)[entList objectAtIndex:i];
		if ([thing isKindOfClass:[ShipEntity class]])
		{
			double d2;
			NSString *shiproles = [(ShipEntity *)thing roles];
			Vector delta = [thing getPosition];
			delta.x -= position.x;  delta.y -= position.y;  delta.z -= position.z;
			d2 = delta.x*delta.x + delta.y*delta.y + delta.z*delta.z;
			if (([thing scanClass] != CLASS_CARGO)&&([thing getStatus] != STATUS_DOCKED)&&(![shiproles hasPrefix:@"tharg"])&&(d2 < found_d2))
			{
				found_target = [thing universal_id];
				if ([thing isKindOfClass:[PlayerEntity class]]) d2 = 0.0;   // prefer the player
				found_d2 = d2;
			}
		}
	}
	[entList release];
	if (found_target != NO_TARGET)
		[shipAI message:@"TARGET_FOUND"];
	else
		[shipAI message:@"NOTHING_FOUND"];
}

- (void) initialiseTurret
{
//	NSLog(@"DEBUG initialising ball turret %@ (%@)", self, basefile);
	[self setCondition: CONDITION_TRACK_AS_TURRET];
	weapon_recharge_rate = 0.5;	// test
//	weapon_energy = 0.1;		// test
	[self setStatus: STATUS_ACTIVE];
	
}

- (void) checkDistanceTravelled
{
	if (distance_travelled > desired_range)
		[shipAI message:@"GONE_BEYOND_RANGE"];
}

- (void) scanForHostiles
{
	/*-- Locates all the ships in range targetting the receiver and chooses the nearest --*/
	
	NSArray* entList = [[universe getAllEntities] retain];
	int i;
//	double found_d2 = desired_range*desired_range;
	double found_d2 = scanner_range * scanner_range;
	found_target = NO_TARGET;
	found_hostiles = 0;
	for (i = 0; i < [entList count] ; i++)
	{
		Entity* thing = (Entity *)[entList objectAtIndex:i];
		if ([thing isKindOfClass:[ShipEntity class]])
		{
			double d2;
			Vector delta = [thing getPosition];
			delta.x -= position.x;  delta.y -= position.y;  delta.z -= position.z;
			d2 = delta.x*delta.x + delta.y*delta.y + delta.z*delta.z;
			if ((([thing scanClass] == CLASS_THARGOID)||(([(ShipEntity *)thing getPrimaryTarget] == self)&&([(ShipEntity *)thing hasHostileTarget])))&&(d2 < found_d2))
			{
				found_target = [thing universal_id];
				found_d2 = d2;
				found_hostiles++;
			}
		}
	}
	[entList release];
		
	if (found_target != NO_TARGET)
	{
		//NSLog(@"DEBUG %@ %d scanForHostiles ----> found %@ %@ %d", name, universal_id, [(ShipEntity *)[universe entityForUniversalID:found_target] roles], [(ShipEntity *)[universe entityForUniversalID:found_target] name], found_target);
		//[self setReportAImessages:YES];
		
		[shipAI message:@"TARGET_FOUND"];
	}
	else
		[shipAI message:@"NOTHING_FOUND"];
}

- (void) fightOrFleeHostiles
{
	//NSLog(@"DEBUG %@ %d considers fightOrFleeHostiles", name, universal_id);
	// consider deploying escorts
	//if ([escorts count] > 0)
	if (n_escorts > 0)
	{
		if (found_target == last_escort_target)
		{
			//NSLog(@"DEBUG exit fightOrFleeHostiles because found_target == last_escort_target == %d", found_target);
			return;
		}
		
		//NSLog(@"DEBUG %@ %d decides to deploy escorts and flee", name, universal_id);
		
		primaryAggressor = found_target;
		primaryTarget = found_target;
		[self deployEscorts];
		[shipAI message:@"DEPLOYING_ESCORTS"];
		[shipAI message:@"FLEEING"];
		return;
	}
	
	// consider launching a missile
	if (missiles > 2)   // keep a reserve
	{
		if (randf() < 0.50)
		{
			//NSLog(@"DEBUG %@ %d decides to launch missile and flee", name, universal_id);
		
			primaryAggressor = found_target;
			primaryTarget = found_target;
			[self fireMissile];
			[shipAI message:@"FLEEING"];
			return;
		}
	}
	
	// consider fighting
	if (energy > max_energy * 0.80)
	{
		//NSLog(@"DEBUG %@ %d decides to fight hostiles", name, universal_id);
		
		primaryAggressor = found_target;
		//[self performAttack];
		[shipAI message:@"FIGHTING"];
		return;
	}

	//NSLog(@"DEBUG %@ %d decides to flee hostiles", name, universal_id);
	[shipAI message:@"FLEEING"];
}

- (void) suggestEscort
{
	ShipEntity   *mother = (ShipEntity *)[universe entityForUniversalID:primaryTarget];
	if (mother)
	{
		if ([mother acceptAsEscort:self])
		{
			[self setOwner:mother];
			[shipAI message:@"ESCORTING"];
			return;
		}
	}
	[self setOwner:NO_TARGET];
	[shipAI message:@"NOT_ESCORTING"];
}

- (void) escortCheckMother
{
	ShipEntity   *mother = (ShipEntity *)[universe entityForUniversalID:owner];
	if (mother)
	{
		if ([mother acceptAsEscort:self])
		{
			[self setOwner:mother];
			[shipAI message:@"ESCORTING"];
			return;
		}
	}
	[self setOwner:self];
	[shipAI message:@"NOT_ESCORTING"];
}

- (void) performEscort
{
	condition = CONDITION_FORMATION_FORM_UP;
}

- (int) numberOfShipsInGroup:(int) ship_group_id
{
	if (ship_group_id == NO_TARGET)
		return 1;
	return [[self shipsInGroup:ship_group_id] count];
}

- (void) checkGroupOddsVersusTarget
{
	int own_group_id = group_id;
	int target_group_id = [(ShipEntity *)[universe entityForUniversalID:primaryTarget] group_id];

	int own_group_numbers = [self numberOfShipsInGroup:own_group_id] + (ranrot_rand() & 3);			// add a random fudge factor
	int target_group_numbers = [self numberOfShipsInGroup:target_group_id] + (ranrot_rand() & 3);	// add a random fudge factor

	//debug
	//NSLog(@"DEBUG pirates of group %d (%d ships) considering an attack on group %d (%d ships)", own_group_id, own_group_numbers, target_group_id, target_group_numbers);

	if (own_group_numbers == target_group_numbers)
	{
		[shipAI message:@"ODDS_LEVEL"];
		return;
	}
	if (own_group_numbers > target_group_numbers)
		[shipAI message:@"ODDS_GOOD"];
	else
		[shipAI message:@"ODDS_BAD"];
	return;
}

- (void) groupAttackTarget
{
	if (group_id == NO_TARGET)		// ship is alone!
	{
		//debug
		//NSLog(@"DEBUG Lone ship %@ %d attacking target %d", name, universal_id, found_target);
		
		found_target = primaryTarget;
		[shipAI reactToMessage:@"GROUP_ATTACK_TARGET"];
		return;
	}
	
	NSArray	*fellow_ships = [self shipsInGroup:group_id];
	//debug
	//NSLog(@"DEBUG %d %@ ships of group %d attacking target %d", [fellow_ships count], roles, group_id, found_target);
	
	int i;
	for (i = 0; i < [fellow_ships count]; i++)
	{
		ShipEntity *other_ship = (ShipEntity *)[fellow_ships objectAtIndex:i];
		[other_ship setFound_target:[universe entityForUniversalID:primaryTarget]];
		[[other_ship getAI] reactToMessage:@"GROUP_ATTACK_TARGET"];
	}
	return;
}

- (void) scanForFormationLeader
{
	//-- Locates the nearest suitable formation leader in range --//
	BOOL pair_okay;
	NSArray* entList = [[universe getAllEntities] retain];
	int i;
//	double found_d2 = desired_range*desired_range;
	double found_d2 = scanner_range * scanner_range;
	found_target = NO_TARGET;
	for (i = 0; i < [entList count] ; i++)
	{
		Entity* thing = (Entity *)[entList objectAtIndex:i];
		if (([thing isKindOfClass:[ShipEntity class]])&&(thing != (Entity *)self))
		{
			ShipEntity* ship = (ShipEntity *)thing;
			pair_okay = ([roles isEqual:@"escort"]&&[[ship roles] isEqual:@"trader"]);
			pair_okay |= ([roles isEqual:@"wingman"]&&[[ship roles] isEqual:@"police"]);
			pair_okay |= ([roles isEqual:@"wingman"]&&[[ship roles] isEqual:@"interceptor"]);
			if (pair_okay)
			{
				double d2;
				Vector delta = [ship getPosition];
				delta.x -= position.x;  delta.y -= position.y;  delta.z -= position.z;
				d2 = delta.x*delta.x + delta.y*delta.y + delta.z*delta.z;
				if (d2 < found_d2)
				{
					found_d2 = d2;
					found_target = [ship universal_id];
				}
			}
		}
	}
	[entList release];
	if (found_target != NO_TARGET)
		[shipAI message:@"TARGET_FOUND"];
	else
	{
		[shipAI message:@"NOTHING_FOUND"];
		if ([roles isEqual:@"wingman"])
		{
			// become free-lance police :)
			[shipAI release];
			shipAI = [[AI alloc] initWithStateMachine:@"route1patrolAI.plist" andState:@"GLOBAL"];
			[shipAI setOwner: self];
		}
	}

}

- (void) messageMother:(NSString *)msgString
{
	ShipEntity   *mother = (ShipEntity *)[universe entityForUniversalID:owner];
	if (mother)
	{
		[[mother getAI] reactToMessage:msgString];
	}
}

- (void) setPlanetPatrolCoordinates
{
	// check we've arrived near the last given coordinates
	Vector r_pos = make_vector( position.x - coordinates.x, position.y - coordinates.y, position.z - coordinates.z);
	if ((magnitude2(r_pos) < 1000000)||(patrol_counter == 0))
	{
//		NSLog(@"DEBUG patrol ship %@ %d has reached patrol check point... %d", name, universal_id, patrol_counter);
//
		Vector sun_pos = [[universe sun] getPosition];
		Vector stn_pos = [[universe station] getPosition];
		Vector sun_dir =  make_vector( sun_pos.x - stn_pos.x, sun_pos.y - stn_pos.y, sun_pos.z - stn_pos.z);
		Vector vSun = unit_vector( &sun_dir);
		Vector v0 = vector_forward_from_quaternion([[universe station] QRotation]);
		Vector v1 = cross_product( v0, vSun);
		Vector v2 = cross_product( v0, v1);
		switch (patrol_counter)
		{
			case 0:		// first go to 5km ahead of the station
				coordinates = make_vector( stn_pos.x + 5000 * v0.x, stn_pos.y + 5000 * v0.y, stn_pos.z + 5000 * v0.z);
				desired_range = 250.0;
				break;
			case 1:		// go to 25km N of the station
				coordinates = make_vector( stn_pos.x + 25000 * v1.x, stn_pos.y + 25000 * v1.y, stn_pos.z + 25000 * v1.z);
				desired_range = 250.0;
				break;
			case 2:		// go to 25km E of the station
				coordinates = make_vector( stn_pos.x + 25000 * v2.x, stn_pos.y + 25000 * v2.y, stn_pos.z + 25000 * v2.z);
				desired_range = 250.0;
				break;
			case 3:		// go to 25km S of the station
				coordinates = make_vector( stn_pos.x - 25000 * v1.x, stn_pos.y - 25000 * v1.y, stn_pos.z - 25000 * v1.z);
				desired_range = 250.0;
				break;
			case 4:		// go to 25km W of the station
				coordinates = make_vector( stn_pos.x - 25000 * v2.x, stn_pos.y - 25000 * v2.y, stn_pos.z - 25000 * v2.z);
				desired_range = 250.0;
				break;
		}
		patrol_counter++;
		if (patrol_counter > 4)
		{
			if (randf() < .25)
			{
				// consider docking
				[self setAITo:@"dockingAI.plist"];
			}
			else
			{
				// go around again
				patrol_counter = 1;
			}
		}
	}
//	else
//		NSLog(@"DEBUG MWARP-MARP!!");
	[shipAI message:@"APPROACH_COORDINATES"];
}

- (void) setSunSkimStartCoordinates
{
	Vector v0 = [universe getSunSkimStartPositionForShip:self];
	
	if ((v0.x != 0.0)||(v0.y != 0.0)||(v0.z != 0.0))
	{
		coordinates = v0;
		[shipAI message:@"APPROACH_COORDINATES"];
	}
	else
	{
		[shipAI message:@"WAIT_FOR_SUN"];
	}
}

- (void) setSunSkimEndCoordinates
{
	coordinates = [universe getSunSkimEndPositionForShip:self];
	[shipAI message:@"APPROACH_COORDINATES"];
}

- (void) setSunSkimExitCoordinates
{
	Vector v1 = [universe getSunSkimEndPositionForShip:self];
	Vector vs = [[universe sun] getPosition];
	Vector vout = make_vector( v1.x - vs.x, v1.y - vs.y, v1.z - vs.z);
	vout = unit_vector(&vout);
	v1.x += 10000 * vout.x;	v1.y += 10000 * vout.y;	v1.z += 10000 * vout.z;
	coordinates = v1;
	[shipAI message:@"APPROACH_COORDINATES"];
}

- (void) patrolReportIn
{
	[[universe station] acceptPatrolReportFrom:self];
}

- (void) checkForMotherStation
{
	if (![[self owner] isKindOfClass:[StationEntity class]])
	{
		[shipAI message:@"NOTHING_FOUND"];
		return;
	}
	StationEntity* motherStation = (StationEntity*)[self owner];
	Vector v0 = [motherStation getPosition];
	Vector rpos = make_vector( position.x - v0.x, position.y - v0.y, position.z - v0.z);
	double found_d2 = scanner_range * scanner_range;
	if (magnitude2(rpos) > found_d2)
	{
		[shipAI message:@"NOTHING_FOUND"];
		return;
	}
	[shipAI message:@"STATION_FOUND"];		
}

- (void) sendTargetCommsMessage:(NSString*) message
{
	ShipEntity* ship = (ShipEntity*)[self getPrimaryTarget];
	if ((!ship)||([ship getStatus] == STATUS_DEAD)||([ship getStatus] == STATUS_DOCKED))
	{
		primaryTarget = NO_TARGET;
		[shipAI reactToMessage:@"TARGET_LOST"];
		return;
	}
	[self sendExpandedMessage:message toShip:(ShipEntity*)[self getPrimaryTarget]];
}

- (void) markTargetForFines
{
	ShipEntity* ship = (ShipEntity*)[self getPrimaryTarget];
	if ((!ship)||([ship getStatus] == STATUS_DEAD)||([ship getStatus] == STATUS_DOCKED))
	{
		primaryTarget = NO_TARGET;
		[shipAI reactToMessage:@"TARGET_LOST"];
		return;
	}
	if ([(ShipEntity*)[self getPrimaryTarget] markForFines])
		[shipAI message:@"TARGET_MARKED"];
}

- (void) scanForRocks
{
	/*-- Locates the all boulders and asteroids in range and selects one of up to 16 --*/
	NSArray* entList = [[universe getAllEntities] retain];
	int i;
	double found_d2 = scanner_range * scanner_range;
	found_target = NO_TARGET;
	for (i = 0; i < [entList count] ; i++)
	{
		Entity* thing = (Entity *)[entList objectAtIndex:i];
		if ([thing isKindOfClass:[ShipEntity class]])
		{
			NSString* ship_role = [(ShipEntity *)thing roles];
			if ([ship_role isEqual:@"boulder"])
			{
				double d2;
				Vector delta = [thing getPosition];
				delta.x -= position.x;  delta.y -= position.y;  delta.z -= position.z;
				d2 = delta.x*delta.x + delta.y*delta.y + delta.z*delta.z;
				if (d2 < found_d2)
				{
					found_target = [thing universal_id];
					found_d2 = d2;
				}
			}
		}
	}
	if (found_target == NO_TARGET)
	{
		for (i = 0; i < [entList count] ; i++)
		{
			Entity* thing = (Entity *)[entList objectAtIndex:i];
			if ([thing isKindOfClass:[ShipEntity class]])
			{
				NSString* ship_role = [(ShipEntity *)thing roles];
				if ([ship_role isEqual:@"asteroid"])
				{
					double d2;
					Vector delta = [thing getPosition];
					delta.x -= position.x;  delta.y -= position.y;  delta.z -= position.z;
					d2 = delta.x*delta.x + delta.y*delta.y + delta.z*delta.z;
					if (d2 < found_d2)
					{
						found_target = [thing universal_id];
						found_d2 = d2;
					}
				}
			}
		}
	}
	[entList release];
	if (found_target != NO_TARGET)
		[shipAI message:@"TARGET_FOUND"];
	else
		[shipAI message:@"NOTHING_FOUND"];
}

- (void) performMining
{
	condition = CONDITION_ATTACK_MINING_TARGET;
}

- (void) setDestinationToDockingAbort
{
	double bo_distance = 8000; //	8km back off
	Vector v0 = position;
	Vector d0 = [[self getPrimaryTarget] getPosition];
	v0.x += (randf() - 0.5)*collision_radius;	v0.y += (randf() - 0.5)*collision_radius;	v0.z += (randf() - 0.5)*collision_radius;
	v0.x -= d0.x;	v0.y -= d0.y;	v0.z -= d0.z;
	v0 = unit_vector(&v0);
	v0.x *= bo_distance;	v0.y *= bo_distance;	v0.z *= bo_distance;
	v0.x += d0.x;	v0.y += d0.y;	v0.z += d0.z;
	coordinates = v0;
	destination = v0;
}

- (void) requestNewTarget
{
	ShipEntity* mother = nil;
	if ([self owner])
		mother = (ShipEntity*)[self owner];
	if ((mother == nil)&&([universe entityForUniversalID:group_id]))
		mother = (ShipEntity*)[universe entityForUniversalID:group_id];
	if (!mother)
	{
		[shipAI message:@"MOTHER_LOST"];
		return;
	}
	
	/*-- Locates all the ships in range targetting the mother ship and chooses the nearest/biggest --*/
	
	NSArray* entList = [[universe getAllEntities] retain];
	int i;
	double found_d2 = scanner_range * scanner_range;
	double max_e = 0;
	found_target = NO_TARGET;
	found_hostiles = 0;
	for (i = 0; i < [entList count] ; i++)
	{
		Entity* thing = (Entity *)[entList objectAtIndex:i];
		if ([thing isKindOfClass:[ShipEntity class]])
		{
			double d2;
			double e1 = [thing getEnergy];
			Vector delta = [thing getPosition];
			delta.x -= position.x;  delta.y -= position.y;  delta.z -= position.z;
			d2 = delta.x*delta.x + delta.y*delta.y + delta.z*delta.z;
			if ((([thing scanClass] == CLASS_THARGOID)||(([(ShipEntity *)thing getPrimaryTarget] == mother)&&([(ShipEntity *)thing hasHostileTarget])))&&(d2 < found_d2))
			{
				if (e1 > max_e)
				{
					found_target = [thing universal_id];
					found_d2 = d2;
				}
				found_hostiles++;
			}
		}
	}
	[entList release];
		
	if (found_target != NO_TARGET)
		[shipAI message:@"TARGET_FOUND"];
	else
		[shipAI message:@"NOTHING_FOUND"];
}

@end

