/*

OOInstinct.m

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

#import "OOInstinct.h"
#import "ShipEntity.h"
#import "Universe.h"
#import "AI.h"
#import "OOConstToString.h"

#define kOOLogUnconvertedNSLog @"unclassified.OOInstinct"


@implementation OOInstinct


- (GLfloat)	evaluateInstinctWithEntities:(Entity**) entities	// performs necessary calculations for the instinct and returns priority_out
{
	// is the ship in the universe?
	if (ship->universalID == NO_TARGET)  return 0.0f;
	
	// is the ship still as set when initialised?
	if (ship_id != ship->universalID)  return 0.0f;
	
	// does this instinct have any priority?
	if (priority_in == 0.0f)  return 0.0f;
	
	priority_out = 0.0f;	// reset
	//
	// todo by type
	switch (type)
	{
		case INSTINCT_NULL:
			[self instinct_null];
		break;
		
		case INSTINCT_FOLLOW_AI:
			[self instinct_follow_ai];
		break;
		
		default:
		break;
	}
	//
	priority_out *= priority_in;	// factor preference
	//
	return priority_out;
}

- (GLfloat)	priority			// returns priority_out without calculation
{
	return priority_out;
}

// main instincts
//				INSTINCT_NULL				0
- (void) instinct_null
{
	priority_out = 0.0f;	// TODO 
}

// basic behavioural instincts
//
//				INSTINCT_AVOID_HAZARDS		101
- (void) instinct_avoid_hazards:(Entity**) entities
{
	GLfloat max_so_far = 0.0;
	Entity* avoid_target = nil;
	int entity_index = 0;
	Vector u = [ship velocity];
	GLfloat cr = ship->collision_radius;
	//
		
	OOLog(@"instinct.test.avoidHazards", @"\nTESTING instinct_avoid hazards %@", self);
		
	while (entities[entity_index])
	{
		Entity* ent = entities[entity_index++];
		
		Vector	rp = vector_subtract([ent position], [ship position]);
		GLfloat	sz = ent->collision_radius + cr;
		GLfloat	d = magnitude(rp) - sz;
		d = fmax(d, 0.01);		// 1 cm is suitably small
		Vector	rv = vector_subtract([ent velocity], u);
		GLfloat	approach_v = dot_product(rv, vector_normal(rp));
		
		GLfloat assessment = sz * approach_v / d;		// == size x approach velocity / distance
		
		OOLog(@"instinct.test.avoidHazards", @"TESTING instinct_avoid hazards %@ assessment of %@ : %.2f", ship, ent, assessment);
		
		if (assessment > max_so_far)
		{
			avoid_target = ent;
			max_so_far = assessment;
		}
	}
	//
	if (!avoid_target)
	{
		priority_out = 0.0f;
		target_id = NO_TARGET;
		behaviour = BEHAVIOUR_FLEE_TARGET;
	}
	else
	{
		priority_out = max_so_far;
	}
	priority_out = 0.0f;	// TODO 
}
//
//				INSTINCT_FLOCK_ALIKE		102
- (void) instinct_flock_alike:(Entity**) entities
{
	priority_out = 0.0f;	// TODO 
}
//
//				INSTINCT_FIGHT_OR_FLIGHT	103
- (void) instinct_fight_or_flight:(Entity**) entities
{
	priority_out = 0.0f;	// TODO 
}
//
//				INSTINCT_ATTACK_PREY		105
- (void) instinct_attack_prey:(Entity**) entities
{
	priority_out = 0.0f;	// TODO 
}
//				INSTINCT_AVOID_PREDATORS	106
- (void) instinct_avoid_predators:(Entity**) entities
{
	priority_out = 0.0f;	// TODO 
}
//
//				INSTINCT_FOLLOW_AI			201
- (void) instinct_follow_ai
{
	double ut = [UNIVERSE getTime];
	if (ut > [ai nextThinkTime])
	{
		[ai think];
		[ai setNextThinkTime: ut + [ai thinkTimeInterval]];
	}
	priority_out = 1.0f;	// constant - only adjusted by priority_in 
}
//
////


- (void) freezeShipVars
{
	if ([ship universalID] != NO_TARGET)
	{
		saved_destination = ship->destination;
		saved_desired_range = ship->desired_range;
		saved_desired_speed = ship->desired_speed;
		saved_behaviour = ship->behaviour;
		saved_target_id = ship->primaryTarget;
	}
}

- (void) unfreezeShipVars
{
	if ([ship universalID] != NO_TARGET)
	{
		ship->destination = saved_destination;
		ship->desired_range	= saved_desired_range;
		ship->desired_speed = saved_desired_speed;
		ship->behaviour = saved_behaviour;
		ship->primaryTarget = saved_target_id;
	}
}

- (void) setShipVars
{
	if ([ship universalID] != NO_TARGET)
	{
		ship->destination = destination;
		ship->desired_range	= desired_range;
		ship->desired_speed = desired_speed;
		ship->behaviour = behaviour;
		ship->primaryTarget = target_id;
	}
}

- (void) getShipVars
{
	if ([ship universalID] != NO_TARGET)
	{
		destination = ship->destination;
		desired_range = ship->desired_range;
		desired_speed = ship->desired_speed;
		behaviour = ship->behaviour;
		target_id = ship->primaryTarget;
	}
}


- (void) setDestination:(Vector) value
{
	destination = value;
}

- (void) setTargetID:(int) value
{
	target_id = value;
}

- (void) setDesiredRange:(GLfloat) value
{
	desired_range = value;
}

- (void) setDesiredSpeed:(GLfloat) value
{
	desired_speed = value;
}

- (void) setBehaviour:(int) value
{
	behaviour = value;
}

- (void) setPriority:(GLfloat) value
{
	priority_in = value;
	priority_out = 0.0f;
}

// aShip must be in the universe for the following to work correctly
- (id)	initInstinctOfType:(int) aType ofPriority:(GLfloat)aPriority forOwner:(id) anOwner withShip:(ShipEntity*) aShip
{
	self = [super init];
	
		type =		aType;
		owner =		anOwner;
		ship =		aShip;
		ship_id =	[ship universalID];
		
		if (type == INSTINCT_FOLLOW_AI)
		{
			ai = [ship getAI];
			[ai setRulingInstinct:self];
		}
		else
		{
			ai = (AI*)nil;
		}
		
		priority_in =	aPriority;
		priority_out =	0.0f;

	return self;
}


- (void)dumpState
{
	OOLog(@"dumpState.instinct", @"Instinct type: %@", OOStringFromInstinctID(type));
	OOLog(@"dumpState.instinct", @"Destination: %@", VectorDescription(destination));
	if (target_id != NO_TARGET)  OOLog(@"dumpState.instinct", @"Target: %@", [UNIVERSE entityForUniversalID:target_id]);
	OOLog(@"dumpState.instinct", @"Desired speed: %g", desired_speed);
	OOLog(@"dumpState.instinct", @"Behaviour: %@", OOStringFromBehaviour(behaviour));
}

@end
