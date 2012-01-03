/*

OOInstinct.h

Part of NPC behaviour implementation.

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

#ifdef OO_BRAIN_AI

#import "OOCocoa.h"
#import "OOMaths.h"
#import "legacy_random.h"
#import "OOTypes.h"


typedef enum
{
	INSTINCT_NULL					= 0U,
	
	// basic behavioural instincts
	INSTINCT_AVOID_HAZARDS			= 101,
	INSTINCT_FLOCK_ALIKE			= 102,
	
	// threats should be defined
	INSTINCT_FIGHT_OR_FLIGHT		= 103,
	
// 'prey' should be defined
	INSTINCT_ATTACK_PREY			= 105,
	INSTINCT_AVOID_PREDATORS		= 106,
	
	// advanced AI instincts
	INSTINCT_FOLLOW_AI				= 201,
	
	kOOInstinctIDDefault		= INSTINCT_NULL,
} OOInstinctID;


@class Entity, ShipEntity, OOCharacter, AI;

@interface OOInstinct : NSObject	{
	
	//
	// associations
	//
	id					owner;		// could be a ShipEntity or an OOCharacter
	//
	ShipEntity			*ship;		// to exchange information
	OOUniversalID		ship_id;	// to double check ship is within universe
	//
	OOInstinctID		type;		// what this instinct IS

	// AI (usually nil)
	AI*					ai;			// will not be used except in INSTINCT_FOLLOW_AI

	//	variables which will be controlled by instincts
	Vector				destination;		// for flying to or from a set point, need not be used
	OOUniversalID		target_id;			// was primaryTarget;		// for combat or rendezvous, may be NO_TARGET
	GLfloat				desired_range;		// range to which to journey/scan
	GLfloat				desired_speed;		// speed at which to travel, may be much greater than maxFlightSpeed of ship
	OOBehaviour			behaviour;			// ship's intended behavioural state if this instinct is followed

	Vector				saved_destination;
	OOUniversalID		saved_target_id;
	GLfloat				saved_desired_range;
	GLfloat				saved_desired_speed;
	OOBehaviour			saved_behaviour;
	
	// priorities...
	GLfloat				priority_in;		// how much this matters to the owner
	GLfloat				priority_out;		// how much important it is to follow this instinct
}


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

- (void)dumpState;

@end


NSString *OOStringFromInstinctID(OOInstinctID instinct) CONST_FUNC;
OOInstinctID OOInstinctIDFromString(NSString *string) PURE_FUNC;

#endif	/* OO_BRAIN_AI */
