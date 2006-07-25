//
//  OOInstinct.h
//  Oolite
//
//  Created by Giles Williams on 18/07/2006.
//  Copyright 2006 __MyCompanyName__. All rights reserved.
//

#include "OOCocoa.h"
#include "vector.h"
#include "legacy_random.h"

#define		INSTINCT_NULL				0

// basic behavioural instincts
//
#define		INSTINCT_AVOID_HAZARDS		101
#define		INSTINCT_FLOCK_ALIKE		102
//
// threats should be defined
#define		INSTINCT_FIGHT_OR_FLIGHT	103
//
// 'prey' should be defined
#define		INSTINCT_ATTACK_PREY		105
#define		INSTINCT_AVOID_PREDATORS	106
//
////

// advanced AI instincts
//
#define		INSTINCT_FOLLOW_AI			201
//
////

@class Entity, ShipEntity, OOCharacter, AI;

@interface OOInstinct : NSObject	{
	
	//
	// associations
	//
	id			owner;		// could be a ShipEntity or an OOCharacter
	//
	ShipEntity*	ship;		// to exchange information
	int			ship_id;	// to double check ship is within universe
	//
	int			type;		// what this instinct IS

	// AI (usually nil)
	//
	AI*			ai;			// will not be used except in INSTINCT_FOLLOW_AI

	//
	//	variables which will be controlled by instincts
	//
	Vector		destination;		// for flying to or from a set point, need not be used
	int			target_id;				// was primaryTarget;		// for combat or rendezvous, may be NO_TARGET
	GLfloat		desired_range;		// range to which to journey/scan
	GLfloat		desired_speed;		// speed at which to travel, may be much greater than max_flight_speed of ship
	int			behaviour;			// ship's intended behavioural state if this instinct is followed

	Vector		saved_destination;
	int			saved_target_id;
	GLfloat		saved_desired_range;
	GLfloat		saved_desired_speed;
	int			saved_behaviour;
	
	// priorities...
	//
	GLfloat		priority_in;		// how much this matters to the owner
	GLfloat		priority_out;		// how much important it is to follow this instinct
}

int instinctForString(NSString* instinctString);
NSString*	stringForInstinct(int value);

- (GLfloat)	evaluateInstinctWithEntities:(Entity**) entities;	// performs necessary calculations for the instinct and returns priority_out
- (GLfloat)	priority;			// returns priority_out without calculation

// main instincts
//
//				INSTINCT_NULL				0
- (void) instinct_null;
//
//				INSTINCT_AVOID_HAZARDS		101
- (void) instinct_avoid_hazards:(Entity**) entities;
//
//				INSTINCT_FLOCK_ALIKE		102
- (void) instinct_flock_alike:(Entity**) entities;
//
//				INSTINCT_FIGHT_OR_FLIGHT	103
- (void) instinct_fight_or_flight:(Entity**) entities;
//
//				INSTINCT_ATTACK_PREY		105
- (void) instinct_attack_prey:(Entity**) entities;
//
//				INSTINCT_AVOID_PREDATORS	106
- (void) instinct_avoid_predators:(Entity**) entities;
//
//				INSTINCT_FOLLOW_AI			201
- (void) instinct_follow_ai;
//
////


- (void) freezeShipVars;
- (void) unfreezeShipVars;

- (void) setShipVars;
- (void) getShipVars;

- (void) setDestination:(Vector) value;
- (void) setTargetID:(int) value;
- (void) setDesiredRange:(GLfloat) value;
- (void) setDesiredSpeed:(GLfloat) value;
- (void) setBehaviour:(int) value;
- (void) setPriority:(GLfloat) value;

- (id)	initInstinctOfType:(int) aType ofPriority:(GLfloat)aPriority forOwner:(id) anOwner withShip:(ShipEntity*) aShip;

@end
