/*
 
 ShipEntity.h
 
 Entity subclass representing a ship, or various other flying things like cargo
 pods and stations (a subclass).
 
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

#import "OOEntityWithDrawable.h"
#import "OOPlanetEntity.h"
#import "OOJSPropID.h"

@class	OOColor, StationEntity, WormholeEntity, AI, Octree, OOMesh, OOScript,
	OOJSScript, OORoleSet, OOShipGroup, OOEquipmentType, OOWeakSet,
	OOExhaustPlumeEntity, OOFlasherEntity;

#define MAX_TARGETS						24
#define RAIDER_MAX_CARGO				5
#define MERCHANTMAN_MAX_CARGO			125

#define PIRATES_PREFER_PLAYER			YES

#define TURRET_MINIMUM_COS				0.20f

#define AFTERBURNER_BURNRATE			0.25f
#define AFTERBURNER_NPC_BURNRATE		1.0f

#define CLOAKING_DEVICE_ENERGY_RATE		12.8f
#define CLOAKING_DEVICE_MIN_ENERGY		128
#define CLOAKING_DEVICE_START_ENERGY	0.75f

#define MILITARY_JAMMER_ENERGY_RATE		3
#define MILITARY_JAMMER_MIN_ENERGY		128

#define COMBAT_IN_RANGE_FACTOR			0.035f
#define COMBAT_BROADSIDE_IN_RANGE_FACTOR			0.020f
#define COMBAT_OUT_RANGE_FACTOR			0.500f
#define COMBAT_BROADSIDE_RANGE_FACTOR			0.900f
#define COMBAT_WEAPON_RANGE_FACTOR		1.200f
#define COMBAT_JINK_OFFSET				500.0f

#define SHIP_COOLING_FACTOR				1.0f
#define SHIP_INSULATION_FACTOR			0.00175f
#define SHIP_MAX_CABIN_TEMP				256.0f
#define SHIP_MIN_CABIN_TEMP				60.0f
#define EJECTA_TEMP_FACTOR				0.85f
#define DEFAULT_HYPERSPACE_SPIN_TIME	15.0f

#define SUN_TEMPERATURE					1250.0f

#define MAX_ESCORTS						16
#define ESCORT_SPACING_FACTOR			3.0

#define SHIPENTITY_MAX_MISSILES			32

#define TURRET_TYPICAL_ENERGY			25.0f
#define TURRET_SHOT_SPEED				2000.0f
#define TURRET_SHOT_DURATION			3.0
#define TURRET_SHOT_RANGE				(TURRET_SHOT_SPEED * TURRET_SHOT_DURATION)
#define TURRET_SHOT_FREQUENCY			(TURRET_SHOT_DURATION * TURRET_SHOT_DURATION * TURRET_SHOT_DURATION / 100.0)

#define NPC_PLASMA_SPEED				1500.0f
#define MAIN_PLASMA_DURATION			5.0
#define NPC_PLASMA_RANGE				(MAIN_PLASMA_DURATION * NPC_PLASMA_SPEED)

#define PLAYER_PLASMA_SPEED				1000.0f
#define PLAYER_PLASMA_RANGE				(MAIN_PLASMA_DURATION * PLAYER_PLASMA_SPEED)

#define TRACTOR_FORCE					2500.0f

#define AIMS_AGGRESSOR_SWITCHED_TARGET	@"AGGRESSOR_SWITCHED_TARGET"

// number of vessels considered when scanning around
#define MAX_SCAN_NUMBER					32

#define BASELINE_SHIELD_LEVEL			128.0f			// Max shield level with no boosters.
#define INITIAL_SHOT_TIME				100.0

#define	MIN_FUEL						0				// minimum fuel required for afterburner use
#define MAX_JUMP_RANGE					7.0				// the 7 ly limit

#define ENTITY_PERSONALITY_MAX			0x7FFFU
#define ENTITY_PERSONALITY_INVALID		0xFFFFU


#define WEAPON_COOLING_FACTOR			6.0f
#define NPC_MAX_WEAPON_TEMP				256.0f
#define WEAPON_COOLING_CUTOUT			0.85f

#define COMBAT_AI_WEAPON_TEMP_READY		0.25f * NPC_MAX_WEAPON_TEMP
#define COMBAT_AI_WEAPON_TEMP_USABLE	WEAPON_COOLING_CUTOUT * NPC_MAX_WEAPON_TEMP
// factor determining how close to target AI has to be to be confident in aim
// higher factor makes confident at longer ranges
#define COMBAT_AI_CONFIDENCE_FACTOR		1250000.0f
#define COMBAT_AI_ISNT_AWFUL			0.0f
// removes BEHAVIOUR_ATTACK_FLY_TO_TARGET_SIX/TWELVE (unless thargoid)
#define COMBAT_AI_IS_SMART				5.0f
// adds BEHAVIOUR_(FLEE_)EVASIVE_ACTION
#define COMBAT_AI_FLEES_BETTER			6.0f
// adds BEHAVIOUR_ATTACK_BREAK_OFF_TARGET
#define COMBAT_AI_DOGFIGHTER			6.5f
// adds BEHAVIOUR_ATTACK_SLOW_DOGFIGHT
#define COMBAT_AI_TRACKS_CLOSER			7.5f
#define COMBAT_AI_USES_SNIPING			8.5f
// adds BEHAVIOUR_ATTACK_SNIPER
#define COMBAT_AI_FLEES_BETTER_2		9.0f



#define MAX_LANDING_SPEED				50.0
#define MAX_LANDING_SPEED2				(MAX_LANDING_SPEED * MAX_LANDING_SPEED)

#define MAX_COS							0.995	// cos(5 degrees) is close enough in most cases for navigation
#define MAX_COS2						(MAX_COS * MAX_COS)


#define ENTRY(label, value) label = value,

typedef enum OOBehaviour
{
#include "OOBehaviour.tbl"
} OOBehaviour;

#undef ENTRY


typedef enum
{
	WEAPON_NONE						= 0U,
	WEAPON_PLASMA_CANNON			= 1,
	WEAPON_PULSE_LASER				= 2,
	WEAPON_BEAM_LASER				= 3,
	WEAPON_MINING_LASER				= 4,
	WEAPON_MILITARY_LASER			= 5,
	WEAPON_THARGOID_LASER			= 10,
	WEAPON_UNDEFINED
} OOWeaponType;


typedef enum
{
	// Alert conditions are used by player and station entities.
	// NOTE: numerical values are available to scripts and shaders.
	ALERT_CONDITION_DOCKED	= 0,
	ALERT_CONDITION_GREEN	= 1,
	ALERT_CONDITION_YELLOW	= 2,
	ALERT_CONDITION_RED		= 3
} OOAlertCondition;


typedef enum
{
#define DIFF_STRING_ENTRY(label, string) label,
#include "OOShipDamageType.tbl"
#undef DIFF_STRING_ENTRY
	
	kOOShipDamageTypeDefault = kOODamageTypeEnergy
} OOShipDamageType;


@interface ShipEntity: OOEntityWithDrawable <OOSubEntity, OOBeaconEntity>
{
@public
	// derived variables
	OOTimeDelta				shot_time;					// time elapsed since last shot was fired
	
	// navigation
	Vector					v_forward, v_up, v_right;	// unit vectors derived from the direction faced
	
	// variables which are controlled by AI
	HPVector					destination;				// for flying to/from a set point

	GLfloat					desired_range;				// range to which to journey/scan
	GLfloat					desired_speed;				// speed at which to travel
	// next three used to set desired attitude, flightRoll etc. gradually catch up to target
	GLfloat					stick_roll;					// stick roll
	GLfloat					stick_pitch;				// stick pitch
	GLfloat					stick_yaw;					// stick yaw
	OOBehaviour				behaviour;					// ship's behavioural state
	
	BoundingBox				totalBoundingBox;			// records ship configuration
	
@protected
	//set-up
	NSDictionary			*shipinfoDictionary;
	
	Quaternion				subentityRotationalVelocity;
	
	//scripting
	OOJSScript				*script;
	OOJSScript				*aiScript;
	OOTimeAbsolute    aiScriptWakeTime;
	
	//docking instructions
	NSDictionary			*dockingInstructions;
	
	OOColor					*laser_color;
	OOColor					*exhaust_emissive_color;
	OOColor					*scanner_display_color1;
	OOColor					*scanner_display_color2;
	
	// per ship-type variables
	//
	GLfloat					maxFlightSpeed;				// top speed			(160.0 for player)  (200.0 for fast raider)
	GLfloat					max_flight_roll;			// maximum roll rate	(2.0 for player)	(3.0 for fast raider)
	GLfloat					max_flight_pitch;			// maximum pitch rate   (1.0 for player)	(1.5 for fast raider) also radians/sec for (* turrets *)
	GLfloat					max_flight_yaw;
	GLfloat					cruiseSpeed;				// 80% of top speed
	
	GLfloat					max_thrust;					// acceleration
	GLfloat					thrust;						// acceleration
	float					hyperspaceMotorSpinTime;	// duration of hyperspace countdown
	
	unsigned				military_jammer_active: 1,	// military_jammer
	
							docking_match_rotation: 1,
	
							pitching_over: 1,			// set to YES if executing a sharp loop
							rolling_over: 1,			// set to YES if executing a sharp roll
							reportAIMessages: 1,		// normally NO, suppressing AI message reporting
	
							being_mined: 1,				// normally NO, set to Yes when fired on by mining laser
	
							being_fined: 1,
	
							isHulk: 1,					// This is used to distinguish abandoned ships from cargo
							trackCloseContacts: 1,
							isNearPlanetSurface: 1,		// check for landing on planet
							isFrangible: 1,				// frangible => subEntities can be damaged individually
							cloaking_device_active: 1,	// cloaking_device
							cloakPassive: 1,			// cloak deactivates when main weapons or missiles are fired
							cloakAutomatic: 1,			// cloak activates itself automatic during attack
							canFragment: 1,				// Can it break into wreckage?
							suppressExplosion: 1,		// Avoid exploding on death (script hook)
							suppressAegisMessages: 1,	// No script/AI messages sent by -checkForAegis,
							isMissile: 1,				// Whether this was launched by fireMissile (used to track submunitions).
							_explicitlyUnpiloted: 1,	// Is meant to not have crew
							hasScoopMessage: 1,			// suppress scoop messages when false.
							
							// scripting
							scripted_misjump: 1,
							haveExecutedSpawnAction: 1,
							noRocks: 1,
							_lightsActive: 1;

	GLfloat    _scriptedMisjumpRange; 
	
	OOFuelQuantity			fuel;						// witch-space fuel
	GLfloat					fuel_accumulator;
	
	OOCargoQuantity			likely_cargo;				// likely amount of cargo (for pirates, this is what is spilled as loot)
	OOCargoQuantity			max_cargo;					// capacity of cargo hold
	OOCargoQuantity			extra_cargo;				// capacity of cargo hold extension (if any)
	OOCargoQuantity			equipment_weight;			// amount of equipment using cargo space (excluding passenger_berth & extra_cargo_bay)
	OOCargoType				cargo_type;					// if this is scooped, this is indicates contents
	OOCargoFlag				cargo_flag;					// indicates contents for merchantmen
	OOCreditsQuantity		bounty;						// bounty (if any)
	
	GLfloat					energy_recharge_rate;		// recharge rate for energy banks
	
	OOWeaponFacingSet		weapon_facings;				// weapon mounts available (bitmask)
	OOWeaponType			forward_weapon_type;		// type of forward weapon (allows lasers, plasma cannon, others)
	OOWeaponType			aft_weapon_type;			// type of aft weapon (allows lasers, plasma cannon, others)
	OOWeaponType			port_weapon_type;			// type of port weapon
	OOWeaponType			starboard_weapon_type;			// type of starboard weapon
	GLfloat					weapon_damage;				// energy damage dealt by weapon
	GLfloat					weapon_damage_override;		// custom energy damage dealt by front laser, if applicable
	GLfloat					weaponRange;				// range of the weapon (in meters)
	OOWeaponFacing			currentWeaponFacing;		// not necessarily the same as view for the player
	
	GLfloat					weapon_temp, weapon_shot_temperature; // active weapon temp, delta-temp
	GLfloat					forward_weapon_temp, aft_weapon_temp, port_weapon_temp, starboard_weapon_temp; // current weapon temperatures

	GLfloat					scannerRange;				// typically 25600
	
	unsigned				missiles;					// number of on-board missiles
	unsigned				max_missiles;				// number of missile pylons
	NSString				*_missileRole;
	OOTimeDelta				missile_load_time;			// minimum time interval between missile launches
	OOTimeAbsolute			missile_launch_time;		// time of last missile launch
	
	AI						*shipAI;					// ship's AI system
	
	NSString				*name;						// descriptive name
	NSString				*shipUniqueName;			// uniqish name e.g. "Terror of Lave"
	NSString				*shipClassName;				// e.g. "Cobra III"
	NSString				*displayName;				// name shown on screen
	OORoleSet				*roleSet;					// Roles a ship can take, eg. trader, hunter, police, pirate, scavenger &c.
	NSString				*primaryRole;				// "Main" role of the ship.
	
	// AI stuff
	Vector					jink;						// x and y set factors for offsetting a pursuing ship's position
	HPVector					coordinates;				// for flying to/from a set point
	Vector					reference;					// a direction vector of magnitude 1 (* turrets *)
	
	NSUInteger				_subIdx;					// serialisation index - used only if this ship is a subentity
	NSUInteger				_maxShipSubIdx;				// serialisation index - the number of ship subentities inside the shipdata
	double					launch_time;				// time at which launched
	double					launch_delay;				// delay for thinking after launch
	OOUniversalID			planetForLanding;			// for landing
	
	GLfloat					frustration,				// degree of dissatisfaction with the current behavioural state, factor used to test this
	success_factor;
	
	int						patrol_counter;				// keeps track of where the ship is along a patrol route
	
	NSMutableDictionary		*previousCondition;			// restored after collision avoidance
	
	// derived variables
	float					weapon_recharge_rate;		// time between shots
	int						shot_counter;				// number of shots fired
	OOTimeAbsolute			cargo_dump_time;			// time cargo was last dumped
	OOTimeAbsolute			last_shot_time;				// time shot was last fired
	
	NSMutableArray			*cargo;						// cargo containers go in here
	
	OOCommodityType			commodity_type;				// type of commodity in a container
	OOCargoQuantity			commodity_amount;			// 1 if unit is TONNES (0), possibly more if precious metals KILOGRAMS (1)
	// or gem stones GRAMS (2)
	
	// navigation
	GLfloat					flightSpeed;				// current speed
	GLfloat					flightRoll;					// current roll rate
	GLfloat					flightPitch;				// current pitch rate
	GLfloat					flightYaw;					// current yaw rate
	
	GLfloat					accuracy;
	GLfloat					pitch_tolerance;
	GLfloat					aim_tolerance;
	int					_missed_shots;
	
	OOAegisStatus			aegis_status;				// set to YES when within the station's protective zone
	OOSystemID				home_system; 
	OOSystemID				destination_system; 
	
	double					messageTime;				// counts down the seconds a radio message is active for
	
	double					next_spark_time;			// time of next spark when throwing sparks
	
	Vector					collision_vector;			// direction of colliding thing.
	
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
	float					ship_temperature;
	
	// for advanced scanning etc.
	ShipEntity				*scanned_ships[MAX_SCAN_NUMBER + 1];
	GLfloat					distance2_scanned_ships[MAX_SCAN_NUMBER + 1];
	unsigned				n_scanned_ships;
	
	// advanced navigation
	HPVector					navpoints[32];
	unsigned				next_navpoint_index;
	unsigned				number_of_navpoints;
	
	// Collision detection
	Octree					*octree;
	
#ifndef NDEBUG
	// DEBUGGING
	OOBehaviour				debugLastBehaviour;
#endif
	
	uint16_t				entity_personality;			// Per-entity random number. Exposed to shaders and scripts.
	NSDictionary			*scriptInfo;				// script_info dictionary from shipdata.plist, exposed to scripts.
	
	NSMutableArray			*subEntities;
	OOEquipmentType			*missile_list[SHIPENTITY_MAX_MISSILES];

	// various types of target
	OOWeakReference			*_primaryTarget;			// for combat or rendezvous
	OOWeakReference			*_primaryAggressor;			// recorded after attack
	OOWeakReference			*_targetStation;			// for docking
	OOWeakReference			*_foundTarget;				// from scans
	OOWeakReference			*_lastEscortTarget;			// last target an escort was deployed after
	OOWeakReference			*_thankedShip;				// last ship thanked
	OOWeakReference			*_rememberedShip;			// ship being remembered
	OOWeakReference			*_proximityAlert;			// a ShipEntity within 2x collision_radius
	
	

	
@private
	OOWeakReference			*_subEntityTakingDamage;	//	frangible => subEntities can be damaged individually

	NSString				*_shipKey;
	
	NSMutableSet			*_equipment;
	float					_heatInsulation;
	
	OOWeakReference			*_lastAegisLock;			// remember last aegis planet/sun
	
	OOShipGroup				*_group;
	OOShipGroup				*_escortGroup;
	uint8_t					_maxEscortCount;
	uint8_t					_pendingEscortCount;
	// Cache of ship-relative positions, managed by -coordinatesForEscortPosition:.
	Vector					_escortPositions[MAX_ESCORTS];
	BOOL					_escortPositionsValid;
	
	OOWeakSet				*_defenseTargets;			 // defense targets
	
	GLfloat					_profileRadius;
	
	OOWeakReference			*_shipHitByLaser;			// entity hit by the last laser shot
	
	// beacons
	NSString				*_beaconCode;
	NSString				*_beaconLabel;
	OOWeakReference			*_prevBeacon;
	OOWeakReference			*_nextBeacon;
	id <OOHUDBeaconIcon>	_beaconDrawable;

	double			_nextAegisCheck;
}

// ship brains
- (void) setStateMachine:(NSString *)ai_desc;
- (void) setAI:(AI *)ai;
- (AI *) getAI;
- (BOOL) hasAutoAI;
- (BOOL) hasNewAI;
- (void) setShipScript:(NSString *)script_name;
- (void) removeScript;
- (OOScript *) shipScript;
- (OOScript *) shipAIScript;
- (OOTimeAbsolute) shipAIScriptWakeTime;
- (void) setAIScriptWakeTime:(OOTimeAbsolute) t;
- (double) frustration;
- (void) setLaunchDelay:(double)delay;

- (void) interpretAIMessage:(NSString *)message;

- (GLfloat)accuracy;
- (void)setAccuracy:(GLfloat) new_accuracy;

- (OOMesh *)mesh;
- (void)setMesh:(OOMesh *)mesh;

- (BoundingBox) totalBoundingBox;

- (Vector) forwardVector;
- (Vector) upVector;
- (Vector) rightVector;

- (NSArray *)subEntities;
- (NSUInteger) subEntityCount;
- (BOOL) hasSubEntity:(Entity<OOSubEntity> *)sub;

- (NSEnumerator *)subEntityEnumerator;
- (NSEnumerator *)shipSubEntityEnumerator;
- (NSEnumerator *)flasherEnumerator;
- (NSEnumerator *)exhaustEnumerator;

- (ShipEntity *) subEntityTakingDamage;
- (void) setSubEntityTakingDamage:(ShipEntity *)sub;

- (void) clearSubEntities;	// Releases and clears subentity array, after making sure subentities don't think ship is owner.

// subentities management
- (NSString *) serializeShipSubEntities;
- (void) deserializeShipSubEntitiesFrom:(NSString *)string;
- (NSUInteger) maxShipSubEntities;
- (void) setSubIdx:(NSUInteger)value;
- (NSUInteger) subIdx;

- (Octree *) octree;
- (float) volume;

// octree collision hunting
- (GLfloat)doesHitLine:(HPVector)v0 :(HPVector)v1;
- (GLfloat)doesHitLine:(HPVector)v0 :(HPVector)v1 :(ShipEntity**)hitEntity;
- (GLfloat)doesHitLine:(HPVector)v0 :(HPVector)v1 withPosition:(HPVector)o andIJK:(Vector)i :(Vector)j :(Vector)k;	// for subentities

- (BoundingBox) findBoundingBoxRelativeToPosition:(HPVector)opv InVectors:(Vector)i :(Vector)j :(Vector)k;

- (HPVector)absoluteTractorPosition;

// beacons // definitions now in <OOBeaconEntity> protocol

- (void) setIsBoulder:(BOOL)flag;
- (BOOL) isBoulder;

- (BOOL) countsAsKill;

- (void) setUpEscorts;
- (void) updateEscortFormation;

- (id)initWithKey:(NSString *)key definition:(NSDictionary *)dict;
- (BOOL)setUpFromDictionary:(NSDictionary *) shipDict;
- (BOOL)setUpShipFromDictionary:(NSDictionary *) shipDict;
- (BOOL)setUpSubEntities;
- (BOOL) setUpOneStandardSubentity:(NSDictionary *) subentDict asTurret:(BOOL)asTurret;
- (GLfloat)frustumRadius;

- (NSString *) shipDataKey;
- (NSString *) shipDataKeyAutoRole;
- (void)setShipDataKey:(NSString *)key;

- (NSDictionary *)shipInfoDictionary;

- (void) setDefaultWeaponOffsets;
- (Vector) aftWeaponOffset;
- (Vector) forwardWeaponOffset;
- (Vector) portWeaponOffset;
- (Vector) starboardWeaponOffset;
- (BOOL) hasAutoWeapons;

- (BOOL) isFrangible;
- (BOOL) suppressFlightNotifications;

- (void) respondToAttackFrom:(Entity *)from becauseOf:(Entity *)other;

// Equipment
- (OOWeaponFacingSet) weaponFacings;
- (BOOL) hasEquipmentItem:(id)equipmentKeys includeWeapons:(BOOL)includeWeapons whileLoading:(BOOL)loading;	// This can take a string or an set or array of strings. If a collection, returns YES if ship has _any_ of the specified equipment. If includeWeapons is NO, missiles and primary weapons are not checked.
- (BOOL) hasEquipmentItem:(id)equipmentKeys;			// Short for hasEquipmentItem:foo includeWeapons:NO whileLoading:NO
- (BOOL) hasAllEquipment:(id)equipmentKeys includeWeapons:(BOOL)includeWeapons whileLoading:(BOOL)loading;		// Like hasEquipmentItem:includeWeapons:, but requires _all_ elements in collection.
- (BOOL) hasAllEquipment:(id)equipmentKeys;				// Short for hasAllEquipment:foo includeWeapons:NO
- (BOOL) setWeaponMount:(OOWeaponFacing)facing toWeapon:(NSString *)eqKey;
- (BOOL) canAddEquipment:(NSString *)equipmentKey inContext:(NSString *)context;		// Test ability to add equipment, taking equipment-specific constriants into account. 
- (BOOL) equipmentValidToAdd:(NSString *)equipmentKey inContext:(NSString *)context;	// Actual test if equipment satisfies validation criteria.
- (BOOL) equipmentValidToAdd:(NSString *)equipmentKey whileLoading:(BOOL)loading inContext:(NSString *)context;
- (BOOL) addEquipmentItem:(NSString *)equipmentKey inContext:(NSString *)context;
- (BOOL) addEquipmentItem:(NSString *)equipmentKey withValidation:(BOOL)validateAddition inContext:(NSString *)context;
- (BOOL) hasHyperspaceMotor;
- (float) hyperspaceSpinTime;


- (NSEnumerator *) equipmentEnumerator;
- (NSUInteger) equipmentCount;
- (void) removeEquipmentItem:(NSString *)equipmentKey;
- (void) removeAllEquipment;
- (OOEquipmentType *) selectMissile;
- (OOCreditsQuantity) removeMissiles;

// Internal, subject to change. Use the methods above instead.
- (BOOL) hasOneEquipmentItem:(NSString *)itemKey includeWeapons:(BOOL)includeMissiles whileLoading:(BOOL)loading;
- (BOOL) hasOneEquipmentItem:(NSString *)itemKey includeMissiles:(BOOL)includeMissiles whileLoading:(BOOL)loading;
- (BOOL) hasPrimaryWeapon:(OOWeaponType)weaponType;
- (BOOL) removeExternalStore:(OOEquipmentType *)eqType;

// Passengers and parcels - not supported for NPCs, but interface is here for genericity.
- (NSUInteger) parcelCount;
- (NSUInteger) passengerCount;
- (NSUInteger) passengerCapacity;

- (NSUInteger) missileCount;
- (NSUInteger) missileCapacity;

- (NSUInteger) extraCargo;

// Tests for the various special-cased equipment items
- (BOOL) hasScoop;
- (BOOL) hasECM;
- (BOOL) hasCloakingDevice;
- (BOOL) hasMilitaryScannerFilter;
- (BOOL) hasMilitaryJammer;
- (BOOL) hasExpandedCargoBay;
- (BOOL) hasShieldBooster;
- (BOOL) hasMilitaryShieldEnhancer;
- (BOOL) hasHeatShield;
- (BOOL) hasFuelInjection;
- (BOOL) hasCascadeMine;
- (BOOL) hasEscapePod;
- (BOOL) hasDockingComputer;
- (BOOL) hasGalacticHyperdrive;

// Shield information derived from equipment. NPCs can't have shields, but that should change at some point.
- (float) shieldBoostFactor;
- (float) maxForwardShieldLevel;
- (float) maxAftShieldLevel;
- (float) shieldRechargeRate;

- (float) maxHyperspaceDistance;
- (float) afterburnerFactor;
- (float) maxThrust;
- (float) thrust;

- (void) processBehaviour:(OOTimeDelta)delta_t;
// Behaviours
- (void) behaviour_stop_still:(double) delta_t;
- (void) behaviour_idle:(double) delta_t;
- (void) behaviour_tumble:(double) delta_t;
- (void) behaviour_tractored:(double) delta_t;
- (void) behaviour_track_target:(double) delta_t;
- (void) behaviour_intercept_target:(double) delta_t;
- (void) behaviour_attack_target:(double) delta_t;
- (void) behaviour_attack_slow_dogfight:(double) delta_t;
- (void) behaviour_evasive_action:(double) delta_t;
- (void) behaviour_attack_break_off_target:(double) delta_t;
- (void) behaviour_fly_to_target_six:(double) delta_t;
- (void) behaviour_attack_mining_target:(double) delta_t;
- (void) behaviour_attack_fly_to_target:(double) delta_t;
- (void) behaviour_attack_fly_from_target:(double) delta_t;
- (void) behaviour_running_defense:(double) delta_t;
- (void) behaviour_flee_target:(double) delta_t;
- (void) behaviour_attack_broadside:(double) delta_t;
- (void) behaviour_attack_broadside_left:(double) delta_t;
- (void) behaviour_attack_broadside_right:(double) delta_t;
- (void) behaviour_close_to_broadside_range:(double) delta_t;
- (void) behaviour_close_with_target:(double) delta_t;
- (void) behaviour_attack_broadside_target:(double) delta_t leftside:(BOOL)leftside;
- (void) behaviour_attack_sniper:(double) delta_t;
- (void) behaviour_fly_range_from_destination:(double) delta_t;
- (void) behaviour_face_destination:(double) delta_t;
- (void) behaviour_land_on_planet:(double) delta_t;
- (void) behaviour_formation_form_up:(double) delta_t;
- (void) behaviour_fly_to_destination:(double) delta_t;
- (void) behaviour_fly_from_destination:(double) delta_t;
- (void) behaviour_avoid_collision:(double) delta_t;
- (void) behaviour_track_as_turret:(double) delta_t;
- (void) behaviour_fly_thru_navpoints:(double) delta_t;
- (void) behaviour_scripted_ai:(double) delta_t;

- (GLfloat *) scannerDisplayColorForShip:(ShipEntity*)otherShip :(BOOL)isHostile :(BOOL)flash :(OOColor *)scannerDisplayColor1 :(OOColor *)scannerDisplayColor2;
- (void)setScannerDisplayColor1:(OOColor *)color1;
- (void)setScannerDisplayColor2:(OOColor *)color2;
- (OOColor *)scannerDisplayColor1;
- (OOColor *)scannerDisplayColor2;

- (BOOL)isCloaked;
- (void)setCloaked:(BOOL)cloak;
- (BOOL)hasAutoCloak;
- (void)setAutoCloak:(BOOL)automatic;

- (void) applyThrust:(double) delta_t;
- (void) applyAttitudeChanges:(double) delta_t;

- (void) avoidCollision;
- (void) resumePostProximityAlert;

- (double) messageTime;
- (void) setMessageTime:(double) value;

- (OOShipGroup *) group;
- (void) setGroup:(OOShipGroup *)group;

- (OOShipGroup *) escortGroup;
- (void) setEscortGroup:(OOShipGroup *)group;	// Only for use in unconventional set-up situations.

- (OOShipGroup *) stationGroup; // should probably be defined in stationEntity.m

- (BOOL) hasEscorts;
- (NSEnumerator *) escortEnumerator;
- (NSArray *) escortArray;

- (uint8_t) escortCount;

// Pending escort count: number of escorts to set up "later".
- (uint8_t) pendingEscortCount;
- (void) setPendingEscortCount:(uint8_t)count;

// allow adjustment of escort numbers from shipdata.plist levels
- (uint8_t) maxEscortCount;
- (void) setMaxEscortCount:(uint8_t)newCount;

- (NSString *) name;
- (NSString *) shipUniqueName;
- (NSString *) shipClassName;
- (NSString *) displayName;
- (void) setName:(NSString *)inName;
- (void) setShipUniqueName:(NSString *)inName;
- (void) setShipClassName:(NSString *)inName;
- (void) setDisplayName:(NSString *)inName;
- (NSString *) identFromShip:(ShipEntity*) otherShip; // name displayed to other ships

- (BOOL) hasRole:(NSString *)role;
- (OORoleSet *)roleSet;

- (void) addRole:(NSString *)role;
- (void) addRole:(NSString *)role withProbability:(float)probability;
- (void) removeRole:(NSString *)role;

- (NSString *)primaryRole;
- (void)setPrimaryRole:(NSString *)role;
- (BOOL)hasPrimaryRole:(NSString *)role;

- (BOOL)isPolice;		// Scan class is CLASS_POLICE
- (BOOL)isThargoid;		// Scan class is CLASS_THARGOID
- (BOOL)isTrader;		// Primary role is "trader" || isPlayer
- (BOOL)isPirate;		// Primary role is "pirate"
- (BOOL)isMissile;		// Primary role has suffix "MISSILE"
- (BOOL)isMine;			// Primary role has suffix "MINE"
- (BOOL)isWeapon;		// isMissile || isWeapon
- (BOOL)isEscort;		// Primary role is "escort" or "wingman"
- (BOOL)isShuttle;		// Primary role is "shuttle"
- (BOOL)isTurret;		// Behaviour is BEHAVIOUR_TRACK_AS_TURRET
- (BOOL)isPirateVictim;	// Primary role is listed in pirate-victim-roles.plist
- (BOOL)isExplicitlyUnpiloted; // Has unpiloted = yes in its shipdata.plist entry
- (BOOL)isUnpiloted;	// Explicitly unpiloted, hulk, rock, cargo, debris etc; an open-ended criterion that may grow.

- (OOAlertCondition) alertCondition; // quick calc for shaders
- (OOAlertCondition) realAlertCondition; // full calculation for scripting
- (BOOL) hasHostileTarget;
- (BOOL) isHostileTo:(Entity *)entity;

// defense target handling
- (NSUInteger) defenseTargetCount;
- (NSArray *) allDefenseTargets;
- (NSEnumerator *) defenseTargetEnumerator;
- (void) validateDefenseTargets;
- (BOOL) addDefenseTarget:(Entity *)target;
- (BOOL) isDefenseTarget:(Entity *)target;
- (void) removeDefenseTarget:(Entity *)target;
- (void) removeAllDefenseTargets;


- (GLfloat) weaponRange;
- (void) setWeaponRange:(GLfloat) value;
- (void) setWeaponDataFromType:(OOWeaponType)weapon_type;
- (float) energyRechargeRate; // final rate after energy units
- (float) weaponRechargeRate;
- (void) setWeaponRechargeRate:(float)value;
- (void) setWeaponEnergy:(float)value;
- (OOWeaponFacing) currentWeaponFacing;

- (GLfloat) scannerRange;
- (void) setScannerRange:(GLfloat)value;

- (Vector) reference;
- (void) setReference:(Vector)v;

- (BOOL) reportAIMessages;
- (void) setReportAIMessages:(BOOL)yn;

- (void) transitionToAegisNone;
- (OOPlanetEntity *) findNearestPlanet;
- (Entity<OOStellarBody> *) findNearestStellarBody;		// NOTE: includes sun.
- (OOPlanetEntity *) findNearestPlanetExcludingMoons;
- (OOAegisStatus) checkForAegis;
- (void) forceAegisCheck;
- (BOOL) withinStationAegis;
- (void) setLastAegisLock:(Entity<OOStellarBody> *)lastAegisLock;

- (OOSystemID) homeSystem;
- (OOSystemID) destinationSystem;
- (void) setHomeSystem:(OOSystemID)s;
- (void) setDestinationSystem:(OOSystemID)s;


- (NSArray *) crew;
- (void) setCrew:(NSArray *)crewArray;
/**
	Convenience to set the crew to a single character of the given role,
	originating in the ship's home system. Does nothing if unpiloted.
 */
- (void) setSingleCrewWithRole:(NSString *)crewRole;

// Fuel and capacity in tenths of light-years.
- (OOFuelQuantity) fuel;
- (void) setFuel:(OOFuelQuantity)amount;
- (OOFuelQuantity) fuelCapacity;

- (GLfloat) fuelChargeRate;

- (void) setRoll:(double)amount;
- (void) setRawRoll:(double)amount; // does not multiply by PI/2
- (void) setPitch:(double)amount;
- (void) setYaw:(double)amount;
- (void) setThrust:(double)amount;
- (void) applySticks:(double)delta_t;


- (void)setThrustForDemo:(float)factor;

/*
 Sets the bounty on this ship to amount.  
 Does not check to see if the ship is allowed to have a bounty, for example if it is police.
 */
- (void) setBounty:(OOCreditsQuantity)amount;
- (void) setBounty:(OOCreditsQuantity)amount withReason:(OOLegalStatusReason)reason;
- (void) setBounty:(OOCreditsQuantity)amount withReasonAsString:(NSString *)reason;
- (OOCreditsQuantity) bounty;

- (int) legalStatus;

- (BOOL) isTemplateCargoPod;
- (void) setUpCargoType:(NSString *)cargoString;
- (void) setCommodity:(OOCommodityType)co_type andAmount:(OOCargoQuantity)co_amount;
- (void) setCommodityForPod:(OOCommodityType)co_type andAmount:(OOCargoQuantity)co_amount;
- (OOCommodityType) commodityType;
- (OOCargoQuantity) commodityAmount;

- (OOCargoQuantity) maxAvailableCargoSpace;
- (OOCargoQuantity) availableCargoSpace;
- (OOCargoQuantity) cargoQuantityOnBoard;
- (OOCargoType) cargoType;
- (NSArray *) cargoListForScripting;
- (NSMutableArray *) cargo;
- (void) setCargo:(NSArray *)some_cargo;
- (BOOL) showScoopMessage;

- (NSArray *) passengerListForScripting;
- (NSArray *) parcelListForScripting;
- (NSArray *) contractListForScripting;
- (NSArray *) equipmentListForScripting;
- (OOWeaponType) weaponTypeIDForFacing:(OOWeaponFacing)facing strict:(BOOL)strict;
- (OOEquipmentType *) weaponTypeForFacing:(OOWeaponFacing)facing strict:(BOOL)strict;
- (NSArray *) missilesList;

- (OOCargoFlag) cargoFlag;
- (void) setCargoFlag:(OOCargoFlag)flag;

- (void) setSpeed:(double)amount;
- (double) desiredSpeed;
- (void) setDesiredSpeed:(double)amount;
- (double) desiredRange;
- (void) setDesiredRange:(double)amount;

- (double) cruiseSpeed;

- (Vector) thrustVector;
- (void) setTotalVelocity:(Vector)vel;	// Set velocity to vel - thrustVector, effectively setting the instanteneous velocity to vel.

- (void) increase_flight_speed:(double)delta;
- (void) decrease_flight_speed:(double)delta;
- (void) increase_flight_roll:(double)delta;
- (void) decrease_flight_roll:(double)delta;
- (void) increase_flight_pitch:(double)delta;
- (void) decrease_flight_pitch:(double)delta;
- (void) increase_flight_yaw:(double)delta;
- (void) decrease_flight_yaw:(double)delta;

- (GLfloat) flightRoll;
- (GLfloat) flightPitch;
- (GLfloat) flightYaw;
- (GLfloat) flightSpeed;
- (GLfloat) maxFlightPitch;
- (GLfloat) maxFlightSpeed;
- (GLfloat) maxFlightRoll;
- (GLfloat) maxFlightYaw;
- (GLfloat) speedFactor;

- (GLfloat) temperature;
- (void) setTemperature:(GLfloat) value;
- (GLfloat) heatInsulation;
- (void) setHeatInsulation:(GLfloat) value;

- (float) randomEjectaTemperature;
- (float) randomEjectaTemperatureWithMaxFactor:(float)factor;

// the percentage of damage taken (100 is destroyed, 0 is fine)
- (int) damage;

- (void) dealEnergyDamage:(GLfloat) baseDamage atRange:(GLfloat) range withBias:(GLfloat) velocityBias;
- (void) dealEnergyDamageWithinDesiredRange;
- (void) dealMomentumWithinDesiredRange:(double)amount;

// Dispatch shipTakingDamage() event.
- (void) noteTakingDamage:(double)amount from:(Entity *)entity type:(OOShipDamageType)type;
// Dispatch shipDied() and possibly shipKilledOther() events. This is only for use by getDestroyedBy:damageType:, but needs to be visible to PlayerEntity's version.
- (void) noteKilledBy:(Entity *)whom damageType:(OOShipDamageType)type;

- (void) getDestroyedBy:(Entity *)whom damageType:(OOShipDamageType)type;
- (void) becomeExplosion;
- (void) becomeLargeExplosion:(double) factor;
- (void) becomeEnergyBlast;
- (void) broadcastEnergyBlastImminent;

- (Vector) positionOffsetForAlignment:(NSString*) align;
Vector positionOffsetForShipInRotationToAlignment(ShipEntity* ship, Quaternion q, NSString* align);

- (void) collectBountyFor:(ShipEntity *)other;

- (BoundingBox) findSubentityBoundingBox;

- (Triangle) absoluteIJKForSubentity;

- (GLfloat)weaponRecoveryTime;
- (GLfloat)laserHeatLevel;
- (GLfloat)laserHeatLevelAft;
- (GLfloat)laserHeatLevelForward;
- (GLfloat)laserHeatLevelPort;
- (GLfloat)laserHeatLevelStarboard;
- (GLfloat)hullHeatLevel;
- (GLfloat)entityPersonality;
- (GLint)entityPersonalityInt;
- (void) setEntityPersonalityInt:(uint16_t)value;

- (void)setSuppressExplosion:(BOOL)suppress;

- (void) resetExhaustPlumes;

- (void) removeExhaust:(OOExhaustPlumeEntity *)exhaust;
- (void) removeFlasher:(OOFlasherEntity *)flasher;


/*-----------------------------------------
 
 AI piloting methods
 
 -----------------------------------------*/

- (void) checkScanner;
- (void) checkScannerIgnoringUnpowered;
- (ShipEntity**) scannedShips;
- (int) numberOfScannedShips;

- (Entity *)foundTarget;
- (Entity *)primaryAggressor;
- (Entity *)lastEscortTarget;
- (Entity *)thankedShip;
- (Entity *)rememberedShip;
- (Entity *)proximityAlert;
- (void) setFoundTarget:(Entity *) targetEntity;
- (void) setPrimaryAggressor:(Entity *) targetEntity;
- (void) setLastEscortTarget:(Entity *) targetEntity;
- (void) setThankedShip:(Entity *) targetEntity;
- (void) setRememberedShip:(Entity *) targetEntity;
- (void) setProximityAlert:(ShipEntity *) targetEntity;
- (void) setTargetStation:(Entity *) targetEntity;
- (BOOL) isValidTarget:(Entity *) target;
- (void) addTarget:(Entity *) targetEntity;
- (void) removeTarget:(Entity *) targetEntity;
- (id) primaryTarget;
- (id) primaryTargetWithoutValidityCheck;
- (StationEntity *) targetStation;

- (BOOL) isFriendlyTo:(ShipEntity *)otherShip;

- (ShipEntity *) shipHitByLaser;

- (void) noteLostTarget;
- (void) noteLostTargetAndGoIdle;
- (void) noteTargetDestroyed:(ShipEntity *)target;

- (OOBehaviour) behaviour;
- (void) setBehaviour:(OOBehaviour) cond;

- (void) trackOntoTarget:(double) delta_t withDForward: (GLfloat) dp;

- (double) ballTrackLeadingTarget:(double) delta_t atTarget:(Entity *)target;

- (GLfloat) rollToMatchUp:(Vector) up_vec rotating:(GLfloat) match_roll;

- (GLfloat) rangeToDestination;
- (double) trackDestination:(double) delta_t :(BOOL) retreat;

- (void) setCoordinate:(HPVector)coord;
- (HPVector) coordinates;
- (HPVector) destination;
- (HPVector) distance_six: (GLfloat) dist;
- (HPVector) distance_twelve: (GLfloat) dist withOffset:(GLfloat)offset;

- (void) setEvasiveJink:(GLfloat) z;
- (void) evasiveAction:(double) delta_t;
- (double) trackPrimaryTarget:(double) delta_t :(BOOL) retreat;
- (double) trackSideTarget:(double) delta_t :(BOOL) leftside;
- (double) missileTrackPrimaryTarget:(double) delta_t;

//return 0.0 if there is no primary target
- (double) rangeToPrimaryTarget;
- (double) approachAspectToPrimaryTarget;
- (double) rangeToSecondaryTarget:(Entity *)target;
- (BOOL) hasProximityAlertIgnoringTarget:(BOOL)ignore_target;
- (GLfloat) currentAimTolerance;
/* This method returns a value between 0.0f and 1.0f, depending on how directly our view point
   faces the sun and is used for generating the "staring at the sun" glare effect. 0.0f means that
   we are not facing the sun, 1.0f means that we are looking directly at it. The cosine of the 
   threshold angle between view point and sun, below which we consider the ship as looking
   at the sun, is passed as parameter to the method.
*/
- (GLfloat) lookingAtSunWithThresholdAngleCos:(GLfloat) thresholdAngleCos;

- (BOOL) onTarget:(OOWeaponFacing)direction withWeapon:(OOWeaponType)weapon;

- (OOTimeDelta) shotTime;
- (void) resetShotTime;

- (BOOL) fireMainWeapon:(double)range;
- (BOOL) fireAftWeapon:(double)range;
- (BOOL) firePortWeapon:(double)range;
- (BOOL) fireStarboardWeapon:(double)range;
- (BOOL) fireTurretCannon:(double)range;
- (void) setLaserColor:(OOColor *)color;
- (void) setExhaustEmissiveColor:(OOColor *)color;
- (OOColor *)laserColor;
- (OOColor *)exhaustEmissiveColor;
- (BOOL) fireSubentityLaserShot:(double)range;
- (BOOL) fireDirectLaserShot:(double)range;
- (BOOL) fireDirectLaserDefensiveShot;
- (BOOL) fireDirectLaserShotAt:(Entity *)my_target;
- (Vector) laserPortOffset:(OOWeaponFacing)direction;
- (BOOL) fireLaserShotInDirection:(OOWeaponFacing)direction;
- (void) adjustMissedShots:(int)delta;
- (int) missedShots;
- (BOOL) firePlasmaShotAtOffset:(double)offset speed:(double)speed color:(OOColor *)color;
- (void) considerFiringMissile:(double)delta_t;
- (Vector) missileLaunchPosition;
- (ShipEntity *) fireMissile;
- (ShipEntity *) fireMissileWithIdentifier:(NSString *) identifier andTarget:(Entity *) target;
- (BOOL) isMissileFlagSet;
- (void) setIsMissileFlag:(BOOL)newValue;
- (OOTimeDelta) missileLoadTime;
- (void) setMissileLoadTime:(OOTimeDelta)newMissileLoadTime;
- (void) noticeECM;
- (BOOL) fireECM;
- (BOOL) cascadeIfAppropriateWithDamageAmount:(double)amount cascadeOwner:(Entity *)owner;
- (BOOL) activateCloakingDevice;
- (void) deactivateCloakingDevice;
- (BOOL) launchCascadeMine;
- (ShipEntity *) launchEscapeCapsule;
- (OOCommodityType) dumpCargo;
- (ShipEntity *) dumpCargoItem;
- (OOCargoType) dumpItem: (ShipEntity*) jetto;

- (void) manageCollisions;
- (BOOL) collideWithShip:(ShipEntity *)other;
- (void) adjustVelocity:(Vector) xVel;
- (void) addImpactMoment:(Vector) moment fraction:(GLfloat) howmuch;
- (BOOL) canScoop:(ShipEntity *)other;
- (void) getTractoredBy:(ShipEntity *)other;
- (void) scoopIn:(ShipEntity *)other;
- (void) scoopUp:(ShipEntity *)other;

- (BOOL) abandonShip;

- (void) takeScrapeDamage:(double) amount from:(Entity *) ent;
- (void) takeHeatDamage:(double) amount;

- (void) enterDock:(StationEntity *)station;
- (void) leaveDock:(StationEntity *)station;

- (void) enterWormhole:(WormholeEntity *) w_hole;
- (void) enterWormhole:(WormholeEntity *) w_hole replacing:(BOOL)replacing;
- (void) enterWitchspace;
- (void) leaveWitchspace;
- (BOOL) witchspaceLeavingEffects;

/* 
 Mark this ship as an offender, this is different to setBounty as some ships such as police 
 are not markable.  The final bounty may not be equal to existing bounty plus offence_value.
 */
- (void) markAsOffender:(int)offence_value;
- (void) markAsOffender:(int)offence_value withReason:(OOLegalStatusReason)reason;

- (void) switchLightsOn;
- (void) switchLightsOff;
- (BOOL) lightsActive;

- (void) setDestination:(HPVector) dest;
- (void) setEscortDestination:(HPVector) dest;

- (BOOL) canAcceptEscort:(ShipEntity *)potentialEscort;
- (BOOL) acceptAsEscort:(ShipEntity *) other_ship;
- (void) deployEscorts;
- (void) dockEscorts;

- (void) setTargetToNearestFriendlyStation;
- (void) setTargetToNearestStation;
- (void) setTargetToSystemStation;

- (void) landOnPlanet:(OOPlanetEntity *)planet;

- (void) abortDocking;
- (NSDictionary *) dockingInstructions;

- (void) broadcastThargoidDestroyed;

- (void) broadcastHitByLaserFrom:(ShipEntity*) aggressor_ship;

// Unpiloted ships cannot broadcast messages, unless the unpilotedOverride is set to YES.
- (void) sendExpandedMessage:(NSString *) message_text toShip:(ShipEntity*) other_ship;
- (void) sendMessage:(NSString *) message_text toShip:(ShipEntity*) other_ship withUnpilotedOverride:(BOOL)unpilotedOverride;
- (void) broadcastAIMessage:(NSString *) ai_message;
- (void) broadcastMessage:(NSString *) message_text withUnpilotedOverride:(BOOL) unpilotedOverride;
- (void) setCommsMessageColor;
- (void) receiveCommsMessage:(NSString *) message_text from:(ShipEntity *) other;
- (void) commsMessage:(NSString *)valueString withUnpilotedOverride:(BOOL)unpilotedOverride;

- (BOOL) markedForFines;
- (BOOL) markForFines;

- (BOOL) isMining;

- (void) spawn:(NSString *)roles_number;

- (int) checkShipsInVicinityForWitchJumpExit;

- (BOOL) trackCloseContacts;
- (void) setTrackCloseContacts:(BOOL) value;

/*
 * Changes a ship to a hulk, for example when the pilot ejects.
 * Aso unsets hulkiness for example when a new pilot gets in.
 */
- (void) setHulk:(BOOL) isNowHulk;
- (BOOL) isHulk;
#if OO_SALVAGE_SUPPORT
- (void) claimAsSalvage;
- (void) sendCoordinatesToPilot;
- (void) pilotArrived;
#endif

- (OOJSScript *) script;
- (NSDictionary *) scriptInfo;
- (void) overrideScriptInfo:(NSDictionary *)override;	// Add items from override (if not nil) to scriptInfo, replacing in case of duplicates. Used for subentities.

- (BOOL) scriptedMisjump;
- (void) setScriptedMisjump:(BOOL)newValue;
- (GLfloat) scriptedMisjumpRange;
- (void) setScriptedMisjumpRange:(GLfloat)newValue;


- (Entity *)entityForShaderProperties;

/*	*** Script events.
	For NPC ships, these call doEvent: on the ship script.
	For the player, they do that and also call doWorldScriptEvent:.
*/
- (void) doScriptEvent:(jsid)message;
- (void) doScriptEvent:(jsid)message withArgument:(id)argument;
- (void) doScriptEvent:(jsid)message withArgument:(id)argument1 andArgument:(id)argument2;
- (void) doScriptEvent:(jsid)message withArguments:(NSArray *)arguments;
- (void) doScriptEvent:(jsid)message withArguments:(jsval *)argv count:(uintN)argc;
- (void) doScriptEvent:(jsid)message inContext:(JSContext *)context withArguments:(jsval *)argv count:(uintN)argc;

/*	Convenience to send an event with raw JS values, for example:
	ShipScriptEventNoCx(ship, "doSomething", INT_TO_JSVAL(42));
*/
#define ShipScriptEvent(context, ship, event, ...) do { \
jsval argv[] = { __VA_ARGS__ }; \
uintN argc = sizeof argv / sizeof *argv; \
[ship doScriptEvent:OOJSID(event) inContext:context withArguments:argv count:argc]; \
} while (0)

#define ShipScriptEventNoCx(ship, event, ...) do { \
jsval argv[] = { __VA_ARGS__ }; \
uintN argc = sizeof argv / sizeof *argv; \
[ship doScriptEvent:OOJSID(event) withArguments:argv count:argc]; \
} while (0)

- (void) reactToAIMessage:(NSString *)message context:(NSString *)debugContext;	// Immediate message
- (void) sendAIMessage:(NSString *)message;		// Queued message
- (void) doScriptEvent:(jsid)scriptEvent andReactToAIMessage:(NSString *)aiMessage;
- (void) doScriptEvent:(jsid)scriptEvent withArgument:(id)argument andReactToAIMessage:(NSString *)aiMessage;

@end


#ifndef NDEBUG
@interface ShipEntity (Debug)

- (OOShipGroup *) rawEscortGroup;

@end
#endif


@interface Entity (SubEntityRelationship)

/*	For the common case of testing whether foo is a ship, bar is a ship, bar
	is a subentity of foo and this relationship is represented sanely.
*/
- (BOOL) isShipWithSubEntityShip:(Entity *)other;

@end


NSDictionary *OODefaultShipShaderMacros(void);

GLfloat getWeaponRangeFromType(OOWeaponType weapon_type);

// Stuff implemented in OOConstToString.m
enum
{
	// Values used for unknown strings.
	kOOWeaponTypeDefault		= WEAPON_NONE
};

NSString *OOStringFromBehaviour(OOBehaviour behaviour) CONST_FUNC;

// Weapon strings prefixed with EQ_, used in shipyard.plist.
NSString *OOEquipmentIdentifierFromWeaponType(OOWeaponType weapon) CONST_FUNC;
OOWeaponType OOWeaponTypeFromEquipmentIdentifierSloppy(NSString *string) PURE_FUNC;	// Uses suffix match for backwards compatibility.
OOWeaponType OOWeaponTypeFromEquipmentIdentifierStrict(NSString *string) PURE_FUNC;

NSString *OOStringFromWeaponType(OOWeaponType weapon) CONST_FUNC;
OOWeaponType OOWeaponTypeFromString(NSString *string) PURE_FUNC;

NSString *OODisplayStringFromAlertCondition(OOAlertCondition alertCondition);

NSString *OOStringFromShipDamageType(OOShipDamageType type) CONST_FUNC;
