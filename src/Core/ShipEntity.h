/*

ShipEntity.h

Entity subclass representing a ship, or various other flying things like cargo
pods and stations (a subclass).

Oolite
Copyright (C) 2004-2007 Giles C Williams and contributors

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

#import "Entity.h"
#import "OOMaths.h"

#define BEHAVIOUR_IDLE			0
#define BEHAVIOUR_TRACK_TARGET	1
#define BEHAVIOUR_FLY_TO_TARGET	2
#define BEHAVIOUR_HANDS_OFF		3
#define BEHAVIOUR_TUMBLE		4
#define BEHAVIOUR_STOP_STILL	5

#define BEHAVIOUR_STATION_KEEPING		10

#define IS_BEHAVIOUR_HOSTILE(c)					((c > 100)&&(c < 120))
#define BEHAVIOUR_ATTACK_TARGET					101
#define BEHAVIOUR_ATTACK_FLY_TO_TARGET			102
#define BEHAVIOUR_ATTACK_FLY_FROM_TARGET		103
#define BEHAVIOUR_RUNNING_DEFENSE				104
// fleeing
#define BEHAVIOUR_FLEE_TARGET					105
// advanced combat...
#define BEHAVIOUR_ATTACK_FLY_TO_TARGET_SIX		106
#define BEHAVIOUR_ATTACK_MINING_TARGET			107
// further advanced combat...
#define BEHAVIOUR_ATTACK_FLY_TO_TARGET_TWELVE	112

#define BEHAVIOUR_AVOID_COLLISION			130

#define BEHAVIOUR_TRACK_AS_TURRET			150

#define BEHAVIOUR_FLY_RANGE_FROM_DESTINATION	200
#define BEHAVIOUR_FLY_TO_DESTINATION			201
#define BEHAVIOUR_FLY_FROM_DESTINATION			202
#define BEHAVIOUR_FACE_DESTINATION				203

#define BEHAVIOUR_FLY_THRU_NAVPOINTS			210

#define BEHAVIOUR_COLLECT_TARGET			300
#define BEHAVIOUR_INTERCEPT_TARGET			350

#define BEHAVIOUR_MISSILE_FLY_TO_TARGET		901

#define BEHAVIOUR_FORMATION_FORM_UP			501
#define BEHAVIOUR_FORMATION_BREAK			502

#define BEHAVIOUR_ENERGY_BOMB_COUNTDOWN		601

#define BEHAVIOUR_TRACTORED					701

#define BEHAVIOUR_EXPERIMENTAL				54321


#define MAX_TARGETS							24
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
#define CARGO_ALLOY						9
#define CARGO_MINERALS					12
#define CARGO_THARGOID					16
#define CARGO_RANDOM					100
#define CARGO_SCRIPTED_ITEM				200
#define CARGO_CHARACTER					300

#define CARGO_FLAG_NONE					400
#define CARGO_FLAG_FULL_PLENTIFUL		501
#define CARGO_FLAG_FULL_SCARCE			502
#define CARGO_FLAG_PIRATE				505
#define CARGO_FLAG_FULL_UNIFORM			510
#define CARGO_FLAG_CANISTERS			600
#define CARGO_FLAG_FULL_PASSENGERS		700

#define PIRATES_PREFER_PLAYER			YES

#define AEGIS_NONE						0
#define AEGIS_CLOSE_TO_PLANET			1
#define AEGIS_IN_DOCKING_RANGE			2

#define TURRET_MINIMUM_COS				0.20

#define AFTERBURNER_BURNRATE			0.25
#define AFTERBURNER_NPC_BURNRATE		1.0
#define AFTERBURNER_TIME_PER_FUEL		4.0
#define AFTERBURNER_FACTOR				7.0

#define CLOAKING_DEVICE_ENERGY_RATE		12.8
#define CLOAKING_DEVICE_MIN_ENERGY		128
#define CLOAKING_DEVICE_START_ENERGY	0.75

#define MILITARY_JAMMER_ENERGY_RATE		3
#define MILITARY_JAMMER_MIN_ENERGY		128

#define COMBAT_IN_RANGE_FACTOR						0.035
#define COMBAT_OUT_RANGE_FACTOR						0.500
#define COMBAT_WEAPON_RANGE_FACTOR					1.200

#define SHIP_COOLING_FACTOR				1.0
#define SHIP_INSULATION_FACTOR			0.00175
#define SHIP_MAX_CABIN_TEMP				256.0
#define SHIP_MIN_CABIN_TEMP				60.0

#define SUN_TEMPERATURE					1250.0

#define MAX_ESCORTS						16
#define ESCORT_SPACING_FACTOR			3.0

#define SHIPENTITY_MAX_MISSILES			16

#define TURRET_SHOT_SPEED				2000.0

#define TRACTOR_FORCE					2500.0f

#define AIMS_AGGRESSOR_SWITCHED_TARGET	@"AGGRESSOR_SWITCHED_TARGET"

// number of vessels considered when scanning around
#define MAX_SCAN_NUMBER					16

@class OOBrain, OOColor, StationEntity, ParticleEntity, PlanetEntity, WormholeEntity, AI, Octree;

@interface ShipEntity : Entity {

	@public
		//
		NSArray*	sub_entities;
		ShipEntity*	subentity_taking_damage;	//	frangible => subentities can be damaged individually
		BOOL		isFrangible;				//	frangible => subentities can be damaged individually

		// derived variables
		//
		double  shot_time;			// time elapsed since last shot was fired

		// navigation
		//
		Vector v_forward, v_up, v_right;	// unit vectors derived from the direction faced

		// collision management
		//
		Octree*	octree;	// this is not retained by the ShipEntity but kept in a global dict.

		// expose cloaking device status
		//
		BOOL	cloaking_device_active;	// cloaking_device

		//	variables which are controlled by instincts/AI
		//
		Vector		destination;		// for flying to/from a set point
		int			primaryTarget;		// for combat or rendezvous
		GLfloat		desired_range;		// range to which to journey/scan
		GLfloat		desired_speed;		// speed at which to travel
		int			behaviour;			// ship's behavioural state

		BoundingBox				totalBoundingBox;	// records ship configuration

	@protected

		// per collision directions
		NSMutableDictionary* collisionInfoForEntity;

		//set-up
		NSDictionary*	shipinfoDictionary;

		//scripting
		NSMutableArray *launch_actions;
		NSMutableArray *script_actions;
		NSMutableArray *death_actions;

		//docking instructions
		NSDictionary* dockingInstructions;
		BOOL docking_match_rotation;

		int escort_ids[MAX_ESCORTS];	// replaces the mutable array
		int n_escorts;					// initially, number of escorts to set up, later number of escorts available
		int group_id;					// id of group leader
		int last_escort_target;			// last target an escort was deployed after
		int found_hostiles;				// number of hostiles found
		BOOL escortsAreSetUp;			// set to YES once escorts are initialised (a bit of a hack)

		OOColor *laser_color;

		// per ship-type variables
		//
		GLfloat  max_flight_speed;		// top speed			(160.0 for player)  (200.0 for fast raider)
		GLfloat  max_flight_roll;		// maximum roll rate	(2.0 for player)	(3.0 for fast raider)
		GLfloat  max_flight_pitch;		// maximum pitch rate   (1.0 for player)	(1.5 for fast raider) also radians/sec for (* turrets *)
		GLfloat  max_flight_yaw;

		GLfloat  thrust;					// acceleration

		BOOL	has_ecm;				// anti-missile system
		BOOL	has_scoop;				// fuel/cargo scoops
		BOOL	has_escape_pod;			// escape pod
		BOOL	has_energy_bomb;		// energy_bomb

		BOOL	has_cloaking_device;	// cloaking_device

		BOOL	has_military_jammer;	// military_jammer
		BOOL	military_jammer_active;	// military_jammer
		BOOL	has_military_scanner_filter;	// military_scanner

		BOOL	has_fuel_injection;		// afterburners
		int     fuel;					// witch-space fuel
		GLfloat	fuel_accumulator;

		int		likely_cargo;			// likely amount of cargo (for merchantmen, this is what is spilled as loot)
		int		max_cargo;				// capacity of cargo hold
		int		extra_cargo;			// capacity of cargo hold extension (if any)
		int		bounty;					// bounty (if any)
		int		cargo_type;				// if this is scooped, this is indicates contents
		int		cargo_flag;				// indicates contents for merchantmen

		GLfloat  energy_recharge_rate;   // recharge rate for energy banks

		int		forward_weapon_type;	// type of forward weapon (allows lasers, plasma cannon, others)
		int		aft_weapon_type;		// type of aft weapon (allows lasers, plasma cannon, others)
		GLfloat  weapon_energy;			// energy used/delivered by weapon
		GLfloat  weapon_range;			// range of the weapon (in meters)

		GLfloat	scanner_range;			// typically 25600

		int		missiles;				// number of on-board missiles

		OOBrain*	brain;				// brain controlling ship, could be a character brain or the autopilot
		AI*			shipAI;				// ship's AI system

		NSString*   name;				// descriptive name
		NSString*   roles;				// names fo roles a ship can take, eg. trader, hunter, police, pirate, scavenger &c.

		// AI stuff
		//
		Vector		jink;				// x and y set factors for offsetting a pursuing ship's position
		Vector		coordinates;		// for flying to/from a set point
		Vector		reference;			// a direction vector of magnitude 1 (* turrets *)
		int			primaryAggressor;   // recorded after an attack
		int			targetStation;		// for docking
		int			found_target;		// from scans
		int			target_laser_hit;   // u-id for the entity hit by the last laser shot
		int			owner_id;			// u-id for the controlling owner of this entity (* turrets *)
		double		launch_time;		// time at which launched


		GLfloat	frustration, success_factor;	// degree of dissatisfaction with the current behavioural state, factor used to test this

		int		patrol_counter;				// keeps track of where the ship is along a patrol route

		int		proximity_alert;			// id of a ShipEntity within 2x collision_radius
		NSMutableDictionary*	previousCondition;	// restored after collision avoidance

		// derived variables
		//
		double  weapon_recharge_rate;		// time between shots
		int		shot_counter;				// number of shots fired
		double  cargo_dump_time;			// time cargo was last dumped

		NSMutableArray* cargo;				// cargo containers go in here

		int commodity_type;					// type of commodity in a container
		int commodity_amount;				// 1 if unit is TONNES (0), possibly more if precious metals KILOGRAMS (1)
											// or gem stones GRAMS (2)

		// navigation
		//
		GLfloat flight_speed;				// current speed
		GLfloat flight_roll;					// current roll rate
		GLfloat flight_pitch;				// current pitch rate
		GLfloat flight_yaw;					// current yaw rate

		GLfloat pitch_tolerance;

		BOOL	pitching_over;				// set to YES if executing a sharp loop

		BOOL	within_station_aegis;		// set to YES when within the station's protective zone
		int		aegis_status;				// set to YES when within the station's protective zone

		BOOL	reportAImessages;			// normally NO, suppressing AI message reporting

		BOOL	being_mined;				// normally NO, set to Yes when fired on by mining laser

		BOOL	being_fined;

		double	message_time;				// counts down the seconds a radio message is active for

		double	next_spark_time;			// time of next spark when throwing sparks

		int		thanked_ship_id;			// last ship thanked

		Vector	collision_vector;			// direction of colliding thing.

		// beacons
		char	beaconChar;					// character displayed for this beacon
		int		nextBeaconID;				// next beacon in sequence

		//position of gun ports
		Vector forwardWeaponOffset, aftWeaponOffset, portWeaponOffset, starboardWeaponOffset;

		// crew (typically one OOCharacter - the pilot)
		NSArray*	crew;

		// close contact / collision tracking
		BOOL					trackCloseContacts;
		NSMutableDictionary*	closeContactsInfo;

		// check for landing on planet
		BOOL					isNearPlanetSurface;

		NSString*				lastRadioMessage;

		// scooping...
		Vector	tractor_position;

		// from player entity moved here now we're doing more complex heat stuff
		GLfloat					ship_temperature;
		GLfloat					heat_insulation;

		// for advanced scanning etc.
		ShipEntity*				scanned_ships[MAX_SCAN_NUMBER + 1];
		GLfloat					distance2_scanned_ships[MAX_SCAN_NUMBER + 1];
		int						n_scanned_ships;

		// advanced navigation
		Vector					navpoints[32];
		int						next_navpoint_index;
		int						number_of_navpoints;

		// DEBUGGING
		int debug_flag;
		int debug_condition;

		// shaders
		NSMutableDictionary* shader_info;
		
		BOOL					is_hulk; // This is used to distinguish abandoned ships from cargo
		
		uint16_t				entity_personality;	// Per-entity random number. Used for shaders, maybe scripting at some point.
}

// ship brains
- (OOBrain*)	brain;
- (void)		setBrain:(OOBrain*) aBrain;

// octree collision hunting
- (GLfloat) doesHitLine:(Vector) v0: (Vector) v1;
- (GLfloat) doesHitLine:(Vector) v0: (Vector) v1 :(ShipEntity**) hitEntity;
- (GLfloat) doesHitLine:(Vector) v0: (Vector) v1 withPosition:(Vector) o andIJK:(Vector) i :(Vector) j :(Vector) k;	// for subentities

- (Vector)	absoluteTractorPosition;

	// beacons
- (NSString*)	beaconCode;
- (BOOL)	isBeacon;
- (char)	beaconChar;
- (void)	setBeaconChar:(char) bchar;
- (int)		nextBeaconID;
- (void)	setNextBeacon:(ShipEntity*) beaconShip;

- (void) setUpEscorts;

- (void) reinit;

- (void) rescaleBy:(GLfloat) factor;

- (id) initWithDictionary:(NSDictionary *) dict;
- (void) setUpShipFromDictionary:(NSDictionary *) dict;
- (NSDictionary*)	 shipInfoDictionary;

- (void) setOctree:(Octree*) oct;

- (void) setDefaultWeaponOffsets;

////////////////
//            //
// behaviours //
//            //
- (void) behaviour_stop_still:(double) delta_t;
//            //
- (void) behaviour_idle:(double) delta_t;
//            //
- (void) behaviour_tumble:(double) delta_t;
//            //
- (void) behaviour_tractored:(double) delta_t;
//            //
- (void) behaviour_track_target:(double) delta_t;
//            //
- (void) behaviour_intercept_target:(double) delta_t;
//            //
- (void) behaviour_attack_target:(double) delta_t;
//            //
- (void) behaviour_fly_to_target_six:(double) delta_t;
//            //
- (void) behaviour_attack_mining_target:(double) delta_t;
//            //
- (void) behaviour_attack_fly_to_target:(double) delta_t;
//            //
- (void) behaviour_attack_fly_from_target:(double) delta_t;
//            //
- (void) behaviour_running_defense:(double) delta_t;
//            //
- (void) behaviour_flee_target:(double) delta_t;
//            //
- (void) behaviour_fly_range_from_destination:(double) delta_t;
//            //
- (void) behaviour_face_destination:(double) delta_t;
//            //
- (void) behaviour_formation_form_up:(double) delta_t;
//            //
- (void) behaviour_fly_to_destination:(double) delta_t;
//            //
- (void) behaviour_fly_from_destination:(double) delta_t;
//            //
- (void) behaviour_avoid_collision:(double) delta_t;
//            //
- (void) behaviour_track_as_turret:(double) delta_t;
//            //
- (void) behaviour_fly_thru_navpoints:(double) delta_t;
//            //
- (void) behaviour_experimental:(double) delta_t;
//            //
////////////////


- (void) resetTracking;

- (GLfloat *) scannerDisplayColorForShip:(ShipEntity*)otherShip :(BOOL)isHostile :(BOOL)flash;

- (BOOL) isJammingScanning;
- (BOOL) hasMilitaryScannerFilter;

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
- (NSString *) identFromShip:(ShipEntity*) otherShip; // name displayed to other ships
- (NSString *) roles;
- (void) setRoles:(NSString *) value;

- (BOOL) hasHostileTarget;

- (NSMutableArray *) launch_actions;
- (NSMutableArray *) death_actions;

- (GLfloat) weapon_range;
- (void) setWeaponRange: (GLfloat) value;
- (void) set_weapon_data_from_type: (int) weapon_type;

- (GLfloat) scanner_range;
- (void) setScannerRange: (GLfloat) value;

- (Vector) reference;
- (void) setReference:(Vector) v;

- (BOOL) reportAImessages;
- (void) setReportAImessages:(BOOL) yn;

- (int) checkForAegis;
- (BOOL) within_station_aegis;

- (NSArray*) crew;
- (void) setCrew: (NSArray*) crewArray;

- (void) setStateMachine:(NSString *) ai_desc;
- (void) setAI:(AI *) ai;
- (AI *) getAI;

- (int) fuel;
- (void) setFuel:(int) amount;

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
- (NSMutableArray*) cargo;
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
- (void) increase_flight_yaw:(double) delta;
- (void) decrease_flight_yaw:(double) delta;

- (GLfloat) flight_roll;
- (GLfloat) flight_pitch;
- (GLfloat) flight_yaw;
- (GLfloat) flight_speed;
- (GLfloat) max_flight_speed;
- (GLfloat) speed_factor;

- (void) setTemperature:(GLfloat) value;
- (void) setHeatInsulation:(GLfloat) value;

- (int) damage;
- (void) dealEnergyDamageWithinDesiredRange;
- (void) dealMomentumWithinDesiredRange:(double)amount;

- (void) becomeExplosion;
- (void) becomeLargeExplosion:(double) factor;
- (void) becomeEnergyBlast;
Vector randomPositionInBoundingBox(BoundingBox bb);

- (Vector) positionOffsetForAlignment:(NSString*) align;
Vector positionOffsetForShipInRotationToAlignment(ShipEntity* ship, Quaternion q, NSString* align);

- (void) collectBountyFor:(ShipEntity *)other;

- (BOOL) checkBoundingBoxCollisionWith:(Entity *)other;
- (BOOL) subentityCheckBoundingBoxCollisionWith:(Entity *)other;
- (BoundingBox) findSubentityBoundingBox;
- (BoundingBox) findSubentityBoundingBoxRelativeTo: (Entity*)other inVectors: (Vector)vi: (Vector)vj: (Vector)vk;
- (BoundingBox) findSubentityBoundingBoxRelativeToPosition: (Vector)othpos inVectors: (Vector)vi: (Vector)vj: (Vector)vk;

- (Vector) absolutePositionForSubentity;
- (Vector) absolutePositionForSubentityOffset:(Vector) offset;

- (Triangle) absoluteIJKForSubentity;

- (void) addSolidSubentityToCollisionRadius:(ShipEntity*) subent;

ShipEntity* doOctreesCollide(ShipEntity* prime, ShipEntity* other);

- (NSComparisonResult) compareBeaconCodeWith:(ShipEntity*) other;


/*-----------------------------------------

	AI piloting methods

-----------------------------------------*/

BOOL	class_masslocks(int some_class);
- (BOOL) checkTorusJumpClear;

- (void) checkScanner;
- (ShipEntity**) scannedShips;
- (int) numberOfScannedShips;

- (void) setFound_target:(Entity *) targetEntity;
- (void) setPrimaryAggressor:(Entity *) targetEntity;
- (void) addTarget:(Entity *) targetEntity;
- (void) removeTarget:(Entity *) targetEntity;
- (Entity *) getPrimaryTarget;
- (int) getPrimaryTargetID;

- (int) behaviour;
- (void) setBehaviour:(int) cond;

- (void) trackOntoTarget:(double) delta_t withDForward: (GLfloat) dp;

- (double) ballTrackTarget:(double) delta_t;
- (double) ballTrackLeadingTarget:(double) delta_t;

- (GLfloat) rollToMatchUp:(Vector) up_vec rotating:(GLfloat) match_roll;

- (GLfloat) rangeToDestination;
- (double) trackDestination:(double) delta_t :(BOOL) retreat;
//- (double) trackPosition:(Vector) track_pos :(double) delta_t :(BOOL) retreat;

- (Vector) destination;
- (Vector) one_km_six;
- (Vector) distance_six: (GLfloat) dist;
- (Vector) distance_twelve: (GLfloat) dist;

- (double) trackPrimaryTarget:(double) delta_t :(BOOL) retreat;
- (double) missileTrackPrimaryTarget:(double) delta_t;
- (double) rangeToPrimaryTarget;
- (BOOL) onTarget:(BOOL) fwd_weapon;

- (BOOL) fireMainWeapon:(double) range;
- (BOOL) fireAftWeapon:(double) range;
- (BOOL) fireTurretCannon:(double) range;
- (void) setLaserColor:(OOColor *) color;
- (BOOL) fireSubentityLaserShot: (double) range;
- (BOOL) fireDirectLaserShot;
- (BOOL) fireLaserShotInDirection: (int) direction;
- (BOOL) firePlasmaShot:(double) offset :(double) speed :(OOColor *) color;
- (BOOL) fireMissile;
- (BOOL) fireECM;
- (BOOL) activateCloakingDevice;
- (void) deactivateCloakingDevice;
- (BOOL) launchEnergyBomb;
- (int) launchEscapeCapsule;
- (int) dumpCargo;
- (int) dumpItem: (ShipEntity*) jetto;

- (void) manageCollisions;
- (BOOL) collideWithShip:(ShipEntity *)other;
- (void) adjustVelocity:(Vector) xVel;
- (void) addImpactMoment:(Vector) moment fraction:(GLfloat) howmuch;
- (BOOL) canScoop:(ShipEntity *)other;
- (void) getTractoredBy:(ShipEntity *)other;
- (void) scoopIn:(ShipEntity *)other;
- (void) scoopUp:(ShipEntity *)other;
- (void) takeScrapeDamage:(double) amount from:(Entity *) ent;

- (void) takeHeatDamage:(double) amount;

- (void) enterDock:(StationEntity *)station;
- (void) leaveDock:(StationEntity *)station;

- (void) enterWormhole:(WormholeEntity *) w_hole;
- (void) enterWitchspace;
- (void) leaveWitchspace;

- (void) markAsOffender:(int)offence_value;

- (void) switchLightsOn;
- (void) switchLightsOff;

- (void) setDestination:(Vector) dest;

inline BOOL pairOK(NSString* my_role, NSString* their_role);
- (BOOL) acceptAsEscort:(ShipEntity *) other_ship;
- (Vector) getCoordinatesForEscortPosition:(int) f_pos;
- (void) deployEscorts;
- (void) dockEscorts;

- (void) setTargetToStation;
- (void) setTargetToSystemStation;

- (PlanetEntity *) findNearestLargeBody;

- (void) abortDocking;

- (void) broadcastThargoidDestroyed;

- (void) broadcastHitByLaserFrom:(ShipEntity*) aggressor_ship;

- (NSArray *) shipsInGroup:(int) ship_group_id;

- (void) sendExpandedMessage:(NSString *) message_text toShip:(ShipEntity*) other_ship;
- (void) broadcastAIMessage:(NSString *) ai_message;
- (void) broadcastMessage:(NSString *) message_text;
- (void) setCommsMessageColor;
- (void) receiveCommsMessage:(NSString *) message_text;

- (BOOL) markForFines;

- (BOOL) isMining;
- (void) setNumberOfMinedRocks:(int) value;

- (void) spawn:(NSString *)roles_number;

- (int) checkShipsInVicinityForWitchJumpExit;

- (void) setTrackCloseContacts:(BOOL) value;

- (BOOL) isHulk;
- (void) claimAsSalvage;
- (void) sendCoordinatesToPilot;
- (void) pilotArrived;

/****************************************************************

straight c stuff

****************************************************************/

BOOL ship_canCollide (ShipEntity* ship);

@end


@interface OOCacheManager (Octree)

+ (Octree *)octreeForModel:(NSString *)inKey;
+ (void)setOctree:(Octree *)inOctree forModel:(NSString *)inKey;

@end
