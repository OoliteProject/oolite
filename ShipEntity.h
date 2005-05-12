//
//  ShipEntity.h
/*
 *
 *  Oolite
 *
 *  Created by Giles Williams on Sat Apr 03 2004.
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

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

#import "Entity.h"

#define CONDITION_IDLE			0
#define CONDITION_TRACK_TARGET	1
#define CONDITION_FLY_TO_TARGET	2
#define CONDITION_HANDS_OFF		3
#define CONDITION_TUMBLE		4

#define IS_CONDITION_HOSTILE(c)				((c > 100)&&(c < 110))
#define CONDITION_ATTACK_TARGET				101
#define CONDITION_ATTACK_FLY_TO_TARGET		102
#define CONDITION_ATTACK_FLY_FROM_TARGET	103
#define CONDITION_RUNNING_DEFENSE			104
// advanced combat...
#define CONDITION_ATTACK_FLY_TO_TARGET_SIX	106
#define CONDITION_ATTACK_MINING_TARGET		107


#define CONDITION_FLEE_TARGET				105

#define CONDITION_AVOID_COLLISION			110

#define CONDITION_TRACK_AS_TURRET			150

#define CONDITION_FLY_RANGE_FROM_DESTINATION	200
#define CONDITION_FLY_TO_DESTINATION			201
#define CONDITION_FLY_FROM_DESTINATION			202
#define CONDITION_FACE_DESTINATION				203

#define CONDITION_COLLECT_TARGET			300
#define CONDITION_INTERCEPT_TARGET			350

#define CONDITION_MISSILE_FLY_TO_TARGET		901

#define CONDITION_EXPERIMENTAL				54321

#define CONDITION_FORMATION_FORM_UP			501
#define CONDITION_FORMATION_BREAK			502

#define CONDITION_ENERGY_BOMB_COUNTDOWN		601


#define MAX_TARGETS				24
#define RAIDER_MAX_CARGO					5
#define MERCHANTMAN_MAX_CARGO				125

#define LAUNCH_DELAY					2.0

#define WEAPON_NONE						0
#define WEAPON_PLASMA_CANNON			1
#define WEAPON_PULSE_LASER				2
#define WEAPON_BEAM_LASER				3
#define WEAPON_MINING_LASER				4
#define WEAPON_MILITARY_LASER			5
#define WEAPON_THARGOID_LASER			10

#define CARGO_NOT_CARGO					-1
#define CARGO_SLAVES					3
#define CARGO_MINERALS					12
#define CARGO_ALLOY						9
#define CARGO_THARGOID					16
#define CARGO_RANDOM					100
#define CARGO_SCRIPTED_ITEM				200

#define CARGO_FLAG_NONE					400
#define CARGO_FLAG_FULL_PLENTIFUL		501
#define CARGO_FLAG_FULL_SCARCE			502
#define CARGO_FLAG_FULL_UNIFORM			510
#define CARGO_FLAG_CANISTERS			600

#define PIRATES_PREFER_PLAYER			YES

#define AEGIS_NONE						0
#define AEGIS_CLOSE_TO_PLANET			1
#define AEGIS_IN_DOCKING_RANGE			2

#define TURRET_MINIMUM_COS				0.20

#define AFTERBURNER_BURNRATE			0.25
#define AFTERBURNER_TIME_PER_FUEL		4.0
#define AFTERBURNER_FACTOR				7.0

#define CLOAKING_DEVICE_ENERGY_RATE		12.8
#define CLOAKING_DEVICE_MIN_ENERGY		128
#define CLOAKING_DEVICE_START_ENERGY	0.75

#define COMBAT_IN_RANGE_FACTOR						0.035
#define COMBAT_OUT_RANGE_FACTOR						0.500
#define COMBAT_WEAPON_RANGE_FACTOR					1.200

#define MAX_ESCORTS						16
#define ESCORT_SPACING_FACTOR			3.0

#define SHIPENTITY_MAX_MISSILES			16

#define TURRET_SHOT_SPEED				2000.0

#define AIMS_AGGRESSOR_SWITCHED_TARGET	@"AGGRESSOR_SWITCHED_TARGET"

@class StationEntity, ParticleEntity, PlanetEntity, AI;

@interface ShipEntity : Entity {
	
	// per poly collisions...
	BOOL	face_hit[MAX_FACES_PER_ENTITY];
	// per collision directions
	NSMutableDictionary* collisionVectorForEntity;
	
	//set-up
	NSDictionary*	shipinfoDictionary;
	
	//scripting
	NSMutableArray *launch_actions;
	NSMutableArray *script_actions;
	NSMutableArray *death_actions;
	
	int escort_ids[MAX_ESCORTS];	// replaces the mutable array
	int n_escorts;					// initially, number of escorts to set up, later number of escorts available
	int group_id;					// id of group leader
	int last_escort_target;			// last target an escort was deployed after
	int found_hostiles;				// number of hostiles found
	BOOL escortsAreSetUp;			// set to YES once escorts are initialised (a bit of a hack)
	
	NSArray *sub_entities;
	NSColor *laser_color;
	
	// per ship-type variables
	//
	double  max_flight_speed;		// top speed			(160.0 for player)  (200.0 for fast raider)
	double  max_flight_roll;		// maximum roll rate	(2.0 for player)	(3.0 for fast raider)	
	double  max_flight_pitch;		// maximum pitch rate   (1.0 for player)	(1.5 for fast raider) also radians/sec for (* turrets *)
	
	double  thrust;					// acceleration
	
	BOOL	has_ecm;				// anti-missile system
	BOOL	has_scoop;				// fuel/cargo scoops
	BOOL	has_escape_pod;			// escape pod
	BOOL	has_energy_bomb;		// energy_bomb

	BOOL	has_cloaking_device;	// cloaking_device
	BOOL	cloaking_device_active;	// cloaking_device

	BOOL	has_fuel_injection;		// afterburners
	int     fuel;					// witch-space fuel
	double	fuel_accumulator;
	
	int		likely_cargo;			// likely amount of cargo (for merchantmen, this is what is spilled as loot)
	int		max_cargo;				// capacity of cargo hold
	int		bounty;					// bounty (if any)
	int		cargo_type;				// if this is scooped, this is indicates contents
	int		cargo_flag;				// indicates contents for merchantmen
	
	double  energy_recharge_rate;   // recharge rate for energy banks
	
	int		forward_weapon_type;	// type of forward weapon (allows lasers, plasma cannon, others)
	int		aft_weapon_type;	// type of forward weapon (allows lasers, plasma cannon, others)
	double  weapon_energy;			// energy used/delivered by weapon
	double  weapon_range;			// range of the weapon (in meters)
	double  weapon_offset_x;		// if weapon is in twin configuration this is the distance from the centerline to the weapon
	
	double	scanner_range;			// typically 25600
	
	int		missiles;				// number of on-board missiles
	
	AI*		shipAI;					// ship's AI system
	
	NSString*   name;				// descriptive name
	NSString*   roles;				// names fo roles a ship can take, eg. trader, hunter, police, pirate, scavenger &c.
	
	// AI stuff
	//
	Vector		jink;				// x and y set factors for offsetting a pursuing ship's position
	Vector		destination;		// for flying to/from a set point
	Vector		coordinates;		// for flying to/from a set point
	Vector		reference;			// a direction vector of magnitude 1 (* turrets *)
	int			primaryTarget;		// for combat or rendezvous
	int			primaryAggressor;   // recorded after an attack
	int			targetStation;		// for docking
	int			found_target;		// from scans
	int			target_laser_hit;   // u-id for the entity hit by the last laser shot
	int			owner_id;			// u-id for the controlling owner of this entity (* turrets *)
	double		desired_range;		// range to which to journey/scan
	double		desired_speed;		// speed at which to travel
	double		launch_time;		// time at which launched
	
	int		condition;						// ship's behavioural state
	double	frustration, success_factor;	// degree of dissatisfaction with the current behavioural state, factor used to test this
	
	int		patrol_counter;				// keeps track of where the ship is along a patrol route
	
	int		proximity_alert;			// id of a ShipEntity within 2x collision_radius
	NSMutableDictionary*	previousCondition;	// restored after collision avoidance
	
	// derived variables
	//
	double  shot_time;					// time elapsed since last shot was fired
	double  weapon_recharge_rate;		// time between shots
	int		shot_counter;				// number of shots fired
	double  cargo_dump_time;			// time cargo was last dumped
	
	NSMutableArray* cargo;				// cargo containers go in here
	
	int commodity_type;					// type of commodity in a container
	int commodity_amount;				// 1 if unit is TONNES (0), possibly more if precious metals KILOGRAMS (1)
										// or gem stones GRAMS (2) 
	
	// navigation
	//
	Vector v_forward, v_up, v_right;	// unit vectors derived from the direction faced
		
	double flight_speed;				// current speed
	double flight_roll;					// current roll rate
	double flight_pitch;				// current pitch rate
	
	double pitch_tolerance;
	
	BOOL	pitching_over;				// set to YES if executing a sharp loop

	BOOL	within_station_aegis;		// set to YES when within the station's protective zone
	int		aegis_status;				// set to YES when within the station's protective zone
	
	BOOL	reportAImessages;			// normally NO, suppressing AI message reporting
	
	BOOL	being_mined;				// normally NO, set to Yes when fired on by mining laser
	
	BOOL	being_fined;
	
	double	message_time;				// counts down the seconds a radio message is active for
	
	double	next_spark_time;			// time of next spark when throwing sparks
	
	int		thanked_ship_id;			// last ship thanked
	
	Vector	momentum;					// accumulates impacts
	Vector	collision_vector;			// direction of colliding thing.
	
	// beacons
	char	beaconChar;					// character displayed for this beacon
	int		nextBeaconID;				// next beacon in sequence
	
}

	// beacons
- (BOOL)	isBeacon;
- (char)	beaconChar;
- (void)	setBeaconChar:(char) bchar;
- (int)		nextBeaconID;
- (void)	setNextBeacon:(ShipEntity*) beaconShip;

- (void) setUpEscorts;

- (void) reinit;

- (id) initWithDictionary:(NSDictionary *) dict;
- (void) setUpShipFromDictionary:(NSDictionary *) dict;

- (void) addExhaust:(ParticleEntity *) exhaust;
- (void) addExhaustAt:(Vector) ex_position withScale:(Vector) ex_scale;

- (void) applyThrust:(double) delta_t;

- (void) avoidCollision;
- (void) resumePostProximityAlert;

- (double) message_time;
- (void) setMessage_time:(double) value;

- (int) group_id;
- (void) setGroup_id:(int) value;

- (int) n_escorts;
- (void) setN_escorts:(int) value;

- (ShipEntity*) proximity_alert;
- (void) setProximity_alert:(ShipEntity*) other;

- (NSString *) name;
- (NSString *) roles;
- (void) setRoles:(NSString *) value;

- (BOOL) hasHostileTarget;

- (NSMutableArray *) launch_actions;
- (NSMutableArray *) death_actions;

- (double) weapon_range;
- (void) setWeaponRange: (double) value;
- (void) set_weapon_data_from_type: (int) weapon_type;

- (double) scanner_range;
- (void) setScannerRange: (double) value;

- (Vector) reference;
- (void) setReference:(Vector) v;

- (BOOL) reportAImessages;
- (void) setReportAImessages:(BOOL) yn;

- (int) checkForAegis;
- (BOOL) within_station_aegis;

- (void) setAI:(AI *) ai;
- (AI *) getAI;

- (void) setRoll:(double) amount;
- (void) setPitch:(double) amount;

- (void) setThrust:(double) amount;

- (void) setBounty:(int) amount;
- (int) getBounty;
- (int) legal_status;

- (void) setCommodity:(int) co_type andAmount:(int) co_amount;
- (int) getCommodityType;
- (int) getCommodityAmount;

- (int) getMaxCargo;
- (int) getCargoType;
- (void) setCargo:(NSArray *) some_cargo;

- (int) cargoFlag;
- (void) setCargoFlag:(int) flag;

- (void) setSpeed:(double) amount;
- (void) setDesiredSpeed:(double) amount;

- (void) increase_flight_speed:(double) delta;
- (void) decrease_flight_speed:(double) delta;
- (void) increase_flight_roll:(double) delta;
- (void) decrease_flight_roll:(double) delta;
- (void) increase_flight_pitch:(double) delta;
- (void) decrease_flight_pitch:(double) delta;

- (double) flight_roll;
- (double) flight_pitch;
- (double) flight_speed;
- (double) max_flight_speed;
- (double) speed_factor;

- (int) damage;

- (void) becomeExplosion;
- (void) becomeLargeExplosion:(double) factor;
- (void) becomeEnergyBlast;
Vector randomPositionInBoundingBox(BoundingBox bb);

- (void) collectBountyFor:(ShipEntity *)other;

//- (BOOL) checkPerPolyCollisionWith:(Entity *)other;
- (BOOL) checkPerPolyCollisionWithShip:(ShipEntity *)other;
- (BOOL) checkPerPolyCollisionWithParticle:(ParticleEntity *)other;
- (Vector) collisionVectorForEntity:(Entity *)other;

/*-----------------------------------------

	AI piloting methods

-----------------------------------------*/

- (void) setFound_target:(Entity *) targetEntity;
- (void) setPrimaryAggressor:(Entity *) targetEntity;
- (void) addTarget:(Entity *) targetEntity;
- (void) removeTarget:(Entity *) targetEntity;
- (Entity *) getPrimaryTarget;
- (int) getPrimaryTargetID;

- (int) condition;
- (void) setCondition:(int) cond;

- (void) trackOntoTarget:(double) delta_t;

- (double) ballTrackTarget:(double) delta_t;
- (double) ballTrackLeadingTarget:(double) delta_t;

- (double) rangeToDestination;
- (double) trackDestination:(double) delta_t :(BOOL) retreat;

- (Vector) destination;
- (Vector) one_km_six;

- (double) trackPrimaryTarget:(double) delta_t :(BOOL) retreat;
- (double) rangeToPrimaryTarget;
- (BOOL) onTarget:(BOOL) fwd_weapon;

- (BOOL) fireMainWeapon:(double) range;
- (BOOL) fireAftWeapon:(double) range;
- (BOOL) fireTurretCannon:(double) range;
- (void) setLaserColor:(NSColor *) color;
- (BOOL) fireLaserShot;
- (BOOL) fireDirectLaserShot;
- (BOOL) fireLaserShotInDirection: (int) direction;
- (BOOL) firePlasmaShot:(double) offset :(double) speed :(NSColor *) color;
- (BOOL) fireMissile;
- (BOOL) fireTharglet;
- (BOOL) fireECM;
- (BOOL) activateCloakingDevice;
- (void) deactivateCloakingDevice;
- (BOOL) launchEnergyBomb;
- (int) launchEscapeCapsule;
- (int) dumpCargo;
- (int) dumpItem: (ShipEntity*) jetto;

- (void) manageCollisions;
- (BOOL) collideWithShip:(ShipEntity *)other;
- (void) addImpactMoment:(Vector) moment fraction:(GLfloat) howmuch;
- (BOOL) canScoop:(ShipEntity *)other;
- (void) scoopUp:(ShipEntity *)other;
- (void) takeScrapeDamage:(double) amount from:(Entity *) ent;

- (void) enterDock:(StationEntity *)station;
- (void) leaveDock:(StationEntity *)station;

- (void) enterWitchspace;
- (void) leaveWitchspace;

- (void) markAsOffender:(int)offence_value;

- (void) switchLightsOn;
- (void) switchLightsOff;

- (void) setDestination:(Vector) dest;
- (BOOL) acceptAsEscort:(ShipEntity *) other_ship;
- (Vector) getCoordinatesForEscortPosition:(int) f_pos;
- (void) deployEscorts;
- (void) dockEscorts;

- (void) setTargetToStation;

- (PlanetEntity *) findNearestLargeBody;

- (void) abortDocking;

- (void) broadcastThargoidDestroyed;

- (NSArray *) shipsInGroup:(int) ship_group_id;

- (void) sendExpandedMessage:(NSString *) message_text toShip:(ShipEntity*) other_ship;
- (void) broadcastMessage:(NSString *) message_text;
- (void) setCommsMessageColor;
- (void) receiveCommsMessage:(NSString *) message_text;

- (BOOL) markForFines;

- (BOOL) isMining;

- (void) spawn:(NSString *)roles_number;

- (BOOL *) face_hit;

@end
