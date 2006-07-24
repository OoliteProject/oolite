//
//  OOInstinct.m
//  Oolite
//
//  Created by Giles Williams on 18/07/2006.
//  Copyright 2006 __MyCompanyName__. All rights reserved.
//

#import "OOInstinct.h"
#import "ShipEntity.h"
#import "Universe.h"
#import "AI.h"


@implementation OOInstinct

int instinctForString(NSString* instinctString)
{
	if ([instinctString isEqual:@"INSTINCT_ATTACK_PREY"])
		return INSTINCT_ATTACK_PREY;
	if ([instinctString isEqual:@"INSTINCT_AVOID_PREDATORS"])
		return INSTINCT_AVOID_PREDATORS;
	if ([instinctString isEqual:@"INSTINCT_AVOID_HAZARDS"])
		return INSTINCT_AVOID_HAZARDS;
	if ([instinctString isEqual:@"INSTINCT_FIGHT_OR_FLIGHT"])
		return INSTINCT_FIGHT_OR_FLIGHT;
	if ([instinctString isEqual:@"INSTINCT_FLOCK_ALIKE"])
		return INSTINCT_FLOCK_ALIKE;
	if ([instinctString isEqual:@"INSTINCT_FOLLOW_AI"])
		return INSTINCT_FOLLOW_AI;
	return INSTINCT_NULL;
}

NSString*	stringForInstinct(int value)
{
	switch (value)
	{
		case INSTINCT_ATTACK_PREY:
			return @"INSTINCT_ATTACK_PREY";
		case INSTINCT_AVOID_PREDATORS:
			return @"INSTINCT_AVOID_PREDATORS";
		case INSTINCT_AVOID_HAZARDS:
			return @"INSTINCT_AVOID_HAZARDS";
		case INSTINCT_FIGHT_OR_FLIGHT:
			return @"INSTINCT_FIGHT_OR_FLIGHT";
		case INSTINCT_FLOCK_ALIKE:
			return @"INSTINCT_FLOCK_ALIKE";
		case INSTINCT_FOLLOW_AI:
			return @"INSTINCT_FOLLOW_AI";
		case INSTINCT_NULL:
			return @"INSTINCT_ATTACK_PREY";
	}
	return @"INSTINCT_UNKNOWN";
}

- (GLfloat)	evaluateInstinctWithEntities:(Entity**) entities	// performs necessary calculations for the instinct and returns priority_out
{
	// is the ship in the universe?
	if (![ship universe])
		return 0.0f;
	
	// is the ship still as set when initialised?
	if (ship_id != ship->universal_id)
		return 0.0f;
	
	// does this instinct have any priority?
	if (priority_in == 0.0f)
		return 0.0f;
		
	priority_out = 0.0f;	// reset
	//
	// todo by type
	switch (type)
	{
		case INSTINCT_FOLLOW_AI:
			[self instinct_follow_ai];
		break;
		
		default :
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
- (void) instinct_follow_ai
{
	double ut = [[ship universe] getTime];
	if (ut > [ai nextThinkTime])
	{
		[ai think];
		[ai setNextThinkTime: ut + [ai thinkTimeInterval]];
	}
	priority_out = 1.0f;	// constant - only adjusted by priority_in 
}


- (void) freezeShipVars
{
	if ((ship)&&[ship universe])
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
	if ((ship)&&[ship universe])
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
	if ((ship)&&[ship universe])
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
	if ((ship)&&[ship universe])
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
		ship_id =	[ship universal_id];
		
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

@end
