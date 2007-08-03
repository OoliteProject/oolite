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

#import "OOEntityWithDrawable.h"

@class	OOBrain, OOColor, StationEntity, ParticleEntity, PlanetEntity,
		WormholeEntity, AI, Octree, OOMesh;


#define MAX_TARGETS						24
#define RAIDER_MAX_CARGO				5
#define MERCHANTMAN_MAX_CARGO			125

#define LAUNCH_DELAY					2.0

#define PIRATES_PREFER_PLAYER			YES

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

#define COMBAT_IN_RANGE_FACTOR			0.035
#define COMBAT_OUT_RANGE_FACTOR			0.500
#define COMBAT_WEAPON_RANGE_FACTOR		1.200

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


@interface ShipEntity: OOEntityWithDrawable
{
@public
	NSMutableArray			*sub_entities;
	ShipEntity				*subentity_taking_damage;	//	frangible => subentities can be damaged individually
	
	// derived variables
	double					shot_time;					// time elapsed since last shot was fired
	
	// navigation
	Vector					v_forward, v_up, v_right;	// unit vectors derived from the direction faced
	
	// variables which are controlled by instincts/AI
	Vector					destination;				// for flying to/from a set point
	OOUniversalID			primaryTarget;				// for combat or rendezvous
	GLfloat					desired_range;				// range to which to journey/scan
	GLfloat					desired_speed;				// speed at which to travel
	OOBehaviour				behaviour;					// ship's behavioural state
	
	BoundingBox				totalBoundingBox;			// records ship configuration
	
@protected
	//set-up
	NSDictionary			*shipinfoDictionary;
	
	Quaternion				subentityRotationalVelocity;
	
	//scripting
	NSArray					*launch_actions;
	NSArray					*script_actions;			// used by cargo-containers with CARGO_SCRIPT_ACTION when you scoop them, used by Stations when you dock with them, used during custom system set up too
	NSArray					*death_actions;
	
	//docking instructions
	NSDictionary			*dockingInstructions;
	
	OOUniversalID			escort_ids[MAX_ESCORTS];	// replaces the mutable array
	unsigned				escortCount;				// initially, number of escorts to set up, later number of escorts available
	int						groupID;					// id of group leader
	OOUniversalID			last_escort_target;			// last target an escort was deployed after
	unsigned				found_hostiles;				// number of hostiles found
	
	OOColor					*laser_color;
	
	// per ship-type variables
	//
	GLfloat					maxFlightSpeed;			// top speed			(160.0 for player)  (200.0 for fast raider)
	GLfloat					max_flight_roll;			// maximum roll rate	(2.0 for player)	(3.0 for fast raider)
	GLfloat					max_flight_pitch;			// maximum pitch rate   (1.0 for player)	(1.5 for fast raider) also radians/sec for (* turrets *)
	GLfloat					max_flight_yaw;
	
	GLfloat					thrust;						// acceleration
	
	// TODO: stick all equipment in a list, and move list from playerEntity to shipEntity. -- Ahruman
	uint32_t				has_ecm: 1,					// anti-missile system
							has_scoop: 1,				// fuel/cargo scoops
							has_escape_pod: 1,			// escape pod
							has_energy_bomb: 1,			// energy_bomb
	
							has_cloaking_device: 1,		// cloaking_device
	
							has_military_jammer: 1,		// military_jammer
							military_jammer_active: 1,	// military_jammer
							has_military_scanner_filter: 1, // military_scanner
	
							has_fuel_injection: 1,		// afterburners
	
							docking_match_rotation: 1,
							escortsAreSetUp: 1,			// set to YES once escorts are initialised (a bit of a hack)
	
	
							pitching_over: 1,			// set to YES if executing a sharp loop
							reportAImessages: 1,		// normally NO, suppressing AI message reporting
	
							being_mined: 1,				// normally NO, set to Yes when fired on by mining laser
	
							being_fined: 1,
	
							is_hulk: 1,					// This is used to distinguish abandoned ships from cargo
							trackCloseContacts: 1,
	
	// check for landing on planet
							isNearPlanetSurface: 1,
							isFrangible: 1,				// frangible => subentities can be damaged individually
							cloaking_device_active: 1,	// cloaking_device
							canFragment: 1,				// Can it break into wreckage?
							suppressExplosion: 1;		// Avoid exploding on death (script hook)
	
	OOFuelQuantity			fuel;						// witch-space fuel
	GLfloat					fuel_accumulator;
	
	OOCargoQuantity			likely_cargo;				// likely amount of cargo (for merchantmen, this is what is spilled as loot)
	OOCargoQuantity			max_cargo;					// capacity of cargo hold
	OOCargoQuantity			extra_cargo;				// capacity of cargo hold extension (if any)
	OOCargoType				cargo_type;					// if this is scooped, this is indicates contents
	OOCargoFlag				cargo_flag;					// indicates contents for merchantmen
	OOCreditsQuantity		bounty;						// bounty (if any)
	
	GLfloat					energy_recharge_rate;		// recharge rate for energy banks
	
	OOWeaponType			forward_weapon_type;		// type of forward weapon (allows lasers, plasma cannon, others)
	OOWeaponType			aft_weapon_type;			// type of aft weapon (allows lasers, plasma cannon, others)
	GLfloat					weapon_energy;				// energy used/delivered by weapon
	GLfloat					weaponRange;				// range of the weapon (in meters)
	
	GLfloat					scannerRange;				// typically 25600
	
	unsigned				missiles;					// number of on-board missiles
	
	OOBrain					*brain;						// brain controlling ship, could be a character brain or the autopilot
	AI						*shipAI;					// ship's AI system
	
	NSString				*name;						// descriptive name
	NSString				*roles;						// names fo roles a ship can take, eg. trader, hunter, police, pirate, scavenger &c.
	
	// AI stuff
	Vector					jink;						// x and y set factors for offsetting a pursuing ship's position
	Vector					coordinates;				// for flying to/from a set point
	Vector					reference;					// a direction vector of magnitude 1 (* turrets *)
	OOUniversalID			primaryAggressor;			// recorded after an attack
	OOUniversalID			targetStation;				// for docking
	OOUniversalID			found_target;				// from scans
	OOUniversalID			target_laser_hit;			// u-id for the entity hit by the last laser shot
	OOUniversalID			owner_id;					// u-id for the controlling owner of this entity (* turrets *)
	double					launch_time;				// time at which launched
	
	GLfloat					frustration,				// degree of dissatisfaction with the current behavioural state, factor used to test this
							success_factor;
	
	int						patrol_counter;				// keeps track of where the ship is along a patrol route
	
	OOUniversalID			proximity_alert;			// id of a ShipEntity within 2x collision_radius
	NSMutableDictionary		*previousCondition;			// restored after collision avoidance
	
	// derived variables
	double					weapon_recharge_rate;		// time between shots
	int						shot_counter;				// number of shots fired
	double					cargo_dump_time;			// time cargo was last dumped
	
	NSMutableArray			*cargo;						// cargo containers go in here

	int						commodity_type;				// type of commodity in a container
	int						commodity_amount;			// 1 if unit is TONNES (0), possibly more if precious metals KILOGRAMS (1)
														// or gem stones GRAMS (2)
	
	// navigation
	GLfloat					flightSpeed;				// current speed
	GLfloat					flightRoll;					// current roll rate
	GLfloat					flightPitch;				// current pitch rate
	GLfloat					flightYaw;					// current yaw rate
	
	float					accuracy;
	float					pitch_tolerance;
	
	OOAegisStatus			aegis_status;				// set to YES when within the station's protective zone
	
	double					messageTime;				// counts down the seconds a radio message is active for
	
	double					next_spark_time;			// time of next spark when throwing sparks
	
	int						thanked_ship_id;			// last ship thanked
	
	Vector					collision_vector;			// direction of colliding thing.
	
	// beacons
	char					beaconChar;					// character displayed for this beacon
	int						nextBeaconID;				// next beacon in sequence
	
	//position of gun ports
	Vector					forwardWeaponOffset,
							aftWeaponOffset,
							portWeaponOffset,
							starboardWeaponOffset;
	
	// crew (typically one OOCharacter - the pilot)
	NSArray					*crew;
	
	// close contact / collision tracking
	NSMutableDictionary		*closeContactsInfo;
	
	NSString				*lastRadioMessage;
	
	// scooping...
	Vector					tractor_position;
	
	// from player entity moved here now we're doing more complex heat stuff
	GLfloat					ship_temperature;
	GLfloat					heat_insulation;
	
	// for advanced scanning etc.
	ShipEntity*				scanned_ships[MAX_SCAN_NUMBER + 1];
	GLfloat					distance2_scanned_ships[MAX_SCAN_NUMBER + 1];
	unsigned				n_scanned_ships;
	
	// advanced navigation
	Vector					navpoints[32];
	unsigned				next_navpoint_index;
	unsigned				number_of_navpoints;
	
	// Collision detection
	Octree					*octree;
	
	// DEBUGGING
	OOBehaviour				debug_condition;
	
	NSMutableDictionary		*materials;
	
	uint16_t				entity_personality;	// Per-entity random number. Used for shaders, maybe scripting at some point.
}

// ship brains
- (OOBrain *)brain;
- (void)setBrain:(OOBrain*) aBrain;

- (OOMesh *)mesh;
- (void)setMesh:(OOMesh *)mesh;

- (NSArray *)subEntities;

// octree collision hunting
- (GLfloat)doesHitLine:(Vector) v0: (Vector) v1;
- (GLfloat)doesHitLine:(Vector) v0: (Vector) v1 :(ShipEntity**) hitEntity;
- (GLfloat)doesHitLine:(Vector) v0: (Vector) v1 withPosition:(Vector) o andIJK:(Vector) i :(Vector) j :(Vector) k;	// for subentities

- (BoundingBox) findBoundingBoxRelativeToPosition:(Vector)opv InVectors:(Vector) _i :(Vector) _j :(Vector) _k;

- (Vector)absoluteTractorPosition;

// beacons
- (NSString *)beaconCode;
- (BOOL)isBeacon;
- (char)beaconChar;
- (void)setBeaconChar:(char) bchar;
- (int)nextBeaconID;
- (void)setNextBeacon:(ShipEntity*) beaconShip;

- (void) setUpEscorts;

- (id)initWithDictionary:(NSDictionary *) dict;
- (BOOL)setUpShipFromDictionary:(NSDictionary *) dict;
- (NSDictionary *)shipInfoDictionary;

- (void) setDefaultWeaponOffsets;

- (BOOL)isFrangible;
- (BOOL)isCloaked;

// Behaviours
- (void) behaviour_stop_still:(double) delta_t;
- (void) behaviour_idle:(double) delta_t;
- (void) behaviour_tumble:(double) delta_t;
- (void) behaviour_tractored:(double) delta_t;
- (void) behaviour_track_target:(double) delta_t;
- (void) behaviour_intercept_target:(double) delta_t;
- (void) behaviour_attack_target:(double) delta_t;
- (void) behaviour_fly_to_target_six:(double) delta_t;
- (void) behaviour_attack_mining_target:(double) delta_t;
- (void) behaviour_attack_fly_to_target:(double) delta_t;
- (void) behaviour_attack_fly_from_target:(double) delta_t;
- (void) behaviour_running_defense:(double) delta_t;
- (void) behaviour_flee_target:(double) delta_t;
- (void) behaviour_fly_range_from_destination:(double) delta_t;
- (void) behaviour_face_destination:(double) delta_t;
- (void) behaviour_formation_form_up:(double) delta_t;
- (void) behaviour_fly_to_destination:(double) delta_t;
- (void) behaviour_fly_from_destination:(double) delta_t;
- (void) behaviour_avoid_collision:(double) delta_t;
- (void) behaviour_track_as_turret:(double) delta_t;
- (void) behaviour_fly_thru_navpoints:(double) delta_t;
- (void) behaviour_experimental:(double) delta_t;


- (void) resetTracking;

- (GLfloat *) scannerDisplayColorForShip:(ShipEntity*)otherShip :(BOOL)isHostile :(BOOL)flash;

- (BOOL) isJammingScanning;
- (BOOL) hasMilitaryScannerFilter;

- (void) addExhaust:(ParticleEntity *) exhaust;

- (void) applyThrust:(double) delta_t;

- (void) avoidCollision;
- (void) resumePostProximityAlert;

- (double) messageTime;
- (void) setMessageTime:(double) value;

- (int) groupID;
- (void) setGroupID:(int) value;

- (unsigned) escortCount;
- (void) setEscortCount:(unsigned) value;

- (ShipEntity *) proximity_alert;
- (void) setProximity_alert:(ShipEntity*) other;

- (NSString *) name;
- (NSString *) identFromShip:(ShipEntity*) otherShip; // name displayed to other ships
- (NSString *) roles;
- (void) setRoles:(NSString *) value;

- (BOOL) hasHostileTarget;

- (GLfloat) weaponRange;
- (void) setWeaponRange:(GLfloat) value;
- (void) setWeaponDataFromType:(int) weapon_type;

- (GLfloat) scannerRange;
- (void) setScannerRange: (GLfloat) value;

- (Vector) reference;
- (void) setReference:(Vector) v;

- (BOOL) reportAImessages;
- (void) setReportAImessages:(BOOL) yn;

- (OOAegisStatus) checkForAegis;
- (BOOL) withinStationAegis;

- (NSArray*) crew;
- (void) setCrew: (NSArray*) crewArray;

- (void) setStateMachine:(NSString *) ai_desc;
- (void) setAI:(AI *) ai;
- (AI *) getAI;

- (OOFuelQuantity) fuel;
- (void) setFuel:(OOFuelQuantity) amount;

- (void) setRoll:(double) amount;
- (void) setPitch:(double) amount;

- (void)setThrustForDemo:(float)factor;

- (void) setBounty:(OOCreditsQuantity) amount;
- (OOCreditsQuantity) bounty;

- (int) legalStatus;

- (void) setCommodity:(OOCargoType)co_type andAmount:(OOCargoQuantity)co_amount;
- (OOCargoType) commodityType;
- (OOCargoQuantity) commodityAmount;

- (OOCargoQuantity) maxCargo;
- (OOCargoType) cargoType;
- (NSMutableArray *) cargo;
- (void) setCargo:(NSArray *) some_cargo;

- (OOCargoFlag) cargoFlag;
- (void) setCargoFlag:(OOCargoFlag) flag;

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

- (GLfloat) flightRoll;
- (GLfloat) flightPitch;
- (GLfloat) flightYaw;
- (GLfloat) flightSpeed;
- (GLfloat) maxFlightSpeed;
- (GLfloat) speedFactor;

- (void) setTemperature:(GLfloat) value;
- (void) setHeatInsulation:(GLfloat) value;

- (int) damage;
- (void) dealEnergyDamageWithinDesiredRange;
- (void) dealMomentumWithinDesiredRange:(double)amount;

- (void) getDestroyedBy:(Entity *)whom context:(NSString *)why;
- (void) becomeExplosion;
- (void) becomeLargeExplosion:(double) factor;
- (void) becomeEnergyBlast;
Vector randomPositionInBoundingBox(BoundingBox bb);

- (Vector) positionOffsetForAlignment:(NSString*) align;
Vector positionOffsetForShipInRotationToAlignment(ShipEntity* ship, Quaternion q, NSString* align);

- (void) collectBountyFor:(ShipEntity *)other;

- (BoundingBox) findSubentityBoundingBox;

- (Vector) absolutePositionForSubentity;
- (Vector) absolutePositionForSubentityOffset:(Vector) offset;

- (Triangle) absoluteIJKForSubentity;

- (void) addSolidSubentityToCollisionRadius:(ShipEntity *)subent;

ShipEntity *doOctreesCollide(ShipEntity *prime, ShipEntity *other);

- (NSComparisonResult) compareBeaconCodeWith:(ShipEntity *)other;

- (float)laserHeatLevel;
- (float)hullHeatLevel;
- (float)entityPersonality;
- (int)entityPersonalityInt;

- (void)setSuppressExplosion:(BOOL)suppress;


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
- (Entity *) primaryTarget;
- (int) primaryTargetID;

- (OOBehaviour) behaviour;
- (void) setBehaviour:(OOBehaviour) cond;

- (void) trackOntoTarget:(double) delta_t withDForward: (GLfloat) dp;

- (double) ballTrackTarget:(double) delta_t;
- (double) ballTrackLeadingTarget:(double) delta_t;

- (GLfloat) rollToMatchUp:(Vector) up_vec rotating:(GLfloat) match_roll;

- (GLfloat) rangeToDestination;
- (double) trackDestination:(double) delta_t :(BOOL) retreat;
//- (double) trackPosition:(Vector) track_pos :(double) delta_t :(BOOL) retreat;

- (Vector) destination;
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
- (OOColor *)laserColor;
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
- (void) enterWormhole:(WormholeEntity *) w_hole replacing:(BOOL)replacing;
- (void) enterWitchspace;
- (void) leaveWitchspace;

- (void) markAsOffender:(int)offence_value;

- (void) switchLightsOn;
- (void) switchLightsOff;

- (void) setDestination:(Vector) dest;

inline BOOL pairOK(NSString* my_role, NSString* their_role);
- (BOOL) acceptAsEscort:(ShipEntity *) other_ship;
- (Vector) coordinatesForEscortPosition:(int) f_pos;
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

- (Entity *)entityForShaderProperties;

@end


BOOL ship_canCollide (ShipEntity* ship);


NSDictionary *DefaultShipShaderMacros(void);
