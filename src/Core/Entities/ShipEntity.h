/*

 ShipEntity.h

 Entity subclass representing a ship, or various other flying things like cargo
 pods and stations (a subclass).

 The state is C++ since slice 1 of its slice plan (docs/phases/3-slices/ShipEntity.md, bead
 oo-60fwo; proposed ADR-0056, amendments oo-bj8 and oo-60fwo): cxx::ShipEntity holds the ivars,
 as public data members with the same names, while ShipEntity+ObjCBridge.h, imported at the end
 of this header, keeps the Objective-C ShipEntity, its methods (each moves to cxx::ShipEntity in
 its own slice) and its subclasses. The bridge's deletion bead moves the class out of namespace
 cxx.

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

#pragma once

#import "OOEntityWithDrawable.h"
#import "OOJSPropID.h"
#import "OOPlanetEntity.h"

#include "oofnd/PList.hpp"
#include "oofnd/StdLib.hpp"
#include "oofnd/objc/OOObjCRef.h"
#include <string_view>

@class OOColor, StationEntity, WormholeEntity, AI, Octree, OOMesh, OOScript, OOCharacter,
    OOJSScript, OORoleSet, OOShipGroup, OOEquipmentType, OOWeakSet,
    OOExhaustPlumeEntity, OOFlasherEntity;

#define MAX_TARGETS 24
#define RAIDER_MAX_CARGO 5
#define MERCHANTMAN_MAX_CARGO 125

#define PIRATES_PREFER_PLAYER YES

#define TURRET_MINIMUM_COS 0.20f

#define SHIP_THRUST_FACTOR 5.0f
#define AFTERBURNER_BURNRATE 0.25f

#define CLOAKING_DEVICE_ENERGY_RATE 12.8f
#define CLOAKING_DEVICE_MIN_ENERGY 128
#define CLOAKING_DEVICE_START_ENERGY 0.75f

#define MILITARY_JAMMER_ENERGY_RATE 3
#define MILITARY_JAMMER_MIN_ENERGY 128

#define COMBAT_IN_RANGE_FACTOR 0.035f
#define COMBAT_BROADSIDE_IN_RANGE_FACTOR 0.020f
#define COMBAT_OUT_RANGE_FACTOR 0.500f
#define COMBAT_BROADSIDE_RANGE_FACTOR 0.900f
#define COMBAT_WEAPON_RANGE_FACTOR 1.200f
#define COMBAT_JINK_OFFSET 500.0f

#define SHIP_COOLING_FACTOR 0.1f
// heat taken from energy damage depends on mass
// but limit maximum rate since masses vary so much
// Cobra III ~=215000
#define SHIP_ENERGY_DAMAGE_TO_HEAT_FACTOR (_cxxEntity->mass > 400000 ? 200000 / _cxxEntity->mass : 0.5)
#define SHIP_INSULATION_FACTOR 0.00175f
#define SHIP_MAX_CABIN_TEMP 256.0f
#define SHIP_MIN_CABIN_TEMP 60.0f
#define EJECTA_TEMP_FACTOR 0.85f
#define DEFAULT_HYPERSPACE_SPIN_TIME 15.0f

#define SUN_TEMPERATURE 1250.0f

#define MAX_ESCORTS 16
#define ESCORT_SPACING_FACTOR 3.0

#define SHIPENTITY_MAX_MISSILES 32

#define TURRET_TYPICAL_ENERGY 25.0f
#define TURRET_SHOT_SPEED 2000.0f
#define TURRET_SHOT_DURATION 3.0
#define TURRET_SHOT_RANGE (TURRET_SHOT_SPEED * TURRET_SHOT_DURATION)
#define TURRET_SHOT_FREQUENCY (TURRET_SHOT_DURATION * TURRET_SHOT_DURATION * TURRET_SHOT_DURATION / 100.0)

#define NPC_PLASMA_SPEED 1500.0f
#define MAIN_PLASMA_DURATION 5.0
#define NPC_PLASMA_RANGE (MAIN_PLASMA_DURATION * NPC_PLASMA_SPEED)

#define PLAYER_PLASMA_SPEED 1000.0f
#define PLAYER_PLASMA_RANGE (MAIN_PLASMA_DURATION * PLAYER_PLASMA_SPEED)

#define TRACTOR_FORCE 2500.0f

inline constexpr std::string_view AIMS_AGGRESSOR_SWITCHED_TARGET = "AGGRESSOR_SWITCHED_TARGET";

// number of vessels considered when scanning around
#define MAX_SCAN_NUMBER 32

#define BASELINE_SHIELD_LEVEL 128.0f // Max shield level with no boosters.
#define INITIAL_SHOT_TIME 100.0

#define MIN_FUEL 0 // minimum fuel required for afterburner use
#ifdef OO_DUMP_PLANETINFO
// debugging planetinfo needs rapid jumping
#define MAX_JUMP_RANGE 150.0
#else
#define MAX_JUMP_RANGE 7.0 // the 7 ly limit
#endif

#define ENTITY_PERSONALITY_MAX 0x7FFFU
#define ENTITY_PERSONALITY_INVALID 0xFFFFU

#define WEAPON_COOLING_FACTOR 6.0f
#define NPC_MAX_WEAPON_TEMP 256.0f
#define WEAPON_COOLING_CUTOUT 0.85f

#define COMBAT_AI_WEAPON_TEMP_READY 0.25f * NPC_MAX_WEAPON_TEMP
#define COMBAT_AI_WEAPON_TEMP_USABLE WEAPON_COOLING_CUTOUT* NPC_MAX_WEAPON_TEMP
// factor determining how close to target AI has to be to be confident in aim
// higher factor makes confident at longer ranges
#define COMBAT_AI_CONFIDENCE_FACTOR 1250000.0f
#define COMBAT_AI_ISNT_AWFUL 0.0f
// removes BEHAVIOUR_ATTACK_FLY_TO_TARGET_SIX/TWELVE (unless thargoid)
#define COMBAT_AI_IS_SMART 5.0f
// adds BEHAVIOUR_(FLEE_)EVASIVE_ACTION
#define COMBAT_AI_FLEES_BETTER 6.0f
// adds BEHAVIOUR_ATTACK_BREAK_OFF_TARGET
#define COMBAT_AI_DOGFIGHTER 6.5f
// adds BEHAVIOUR_ATTACK_SLOW_DOGFIGHT
#define COMBAT_AI_TRACKS_CLOSER 7.5f
#define COMBAT_AI_USES_SNIPING 8.5f
// adds BEHAVIOUR_ATTACK_SNIPER
#define COMBAT_AI_FLEES_BETTER_2 9.0f
// AI reacts to changes in target path in about 1.5 seconds.
#define COMBAT_AI_STANDARD_REACTION_TIME 1.5f

#define MAX_LANDING_SPEED 50.0
#define MAX_LANDING_SPEED2 (MAX_LANDING_SPEED * MAX_LANDING_SPEED)

#define MAX_COS 0.995 // cos(5 degrees) is close enough in most cases for navigation
#define MAX_COS2 (MAX_COS * MAX_COS)

#define ENTRY(label, value) label = value,

typedef enum OOBehaviour {
#include "OOBehaviour.tbl"
} OOBehaviour;

#undef ENTRY

/*typedef enum
{
        WEAPON_NONE						= 0U,
        WEAPON_PLASMA_CANNON			= 1,
        WEAPON_PULSE_LASER				= 2,
        WEAPON_BEAM_LASER				= 3,
        WEAPON_MINING_LASER				= 4,
        WEAPON_MILITARY_LASER			= 5,
        WEAPON_THARGOID_LASER			= 10,
        WEAPON_UNDEFINED
        } OOWeaponType; */
typedef OOEquipmentType* OOWeaponType;

typedef enum {
    // Alert conditions are used by player and station entities.
    // NOTE: numerical values are available to scripts and shaders.
    ALERT_CONDITION_DOCKED = 0,
    ALERT_CONDITION_GREEN = 1,
    ALERT_CONDITION_YELLOW = 2,
    ALERT_CONDITION_RED = 3
} OOAlertCondition;

// OOShipDamageType (bead oo-9ht.64: plain header).
#include "OOEntityEnums.h"

namespace cxx {

/*	The ship's state, and the members its slices have moved (docs/phases/3-slices/ShipEntity.md).

        The ivars are data members with the same names, every one zero-initialised as the runtime
        zeroed them (amendment oo-bj8 item 1). The facade's unconverted methods, the Objective-C
        subclasses and the other classes that read a ship's ivars reach them through the facade's
        _cxxShip, by the same names (amendment oo-60fwo), so each slice gets its bodies back verbatim
        by deleting "_cxxShip->". Pointers to other entities and to Objective-C objects stay what they
        were, retained by hand where they were (amendment oo-bj8 item 4).
*/
class ShipEntity : public OOEntityWithDrawable {
public:
    /*	-cxx_initWithKey:definition:'s body between [super init] and the set-up from the
            dictionary. The facade runs it, and then the set-up, which may release the object and answer
            nil. Run again when an initialised ship is sent the initialiser (PlayerEntity's
            -deferredInit).
    */
    void initWithKey(const std::string& key);

    // The category SubEntityRelationship: other is a ship that is a subentity of this ship, and
    // this ship agrees.
    bool isShipWithSubEntityShip(::Entity* other);

    // @public in Objective-C
    // derived variables
    OOTimeDelta shot_time = { }; // time elapsed since last shot was fired

    // navigation
    Vector v_forward = { }, v_up = { }, v_right = { }; // unit vectors derived from the direction faced

    // variables which are controlled by AI
    HPVector _destination = { }; // for flying to/from a set point

    GLfloat desired_range = { }; // range to which to journey/scan
    GLfloat desired_speed = { }; // speed at which to travel
    // next three used to set desired attitude, flightRoll etc. gradually catch up to target
    GLfloat stick_roll = { }; // stick roll
    GLfloat stick_pitch = { }; // stick pitch
    GLfloat stick_yaw = { }; // stick yaw
    OOBehaviour behaviour = { }; // ship's behavioural state

    BoundingBox totalBoundingBox = { }; // records ship configuration

    // @protected in Objective-C: public while Objective-C subclasses read them
    // set-up
    oo::PList shipinfoDictionary; // null: not set up from a dictionary

    Quaternion subentityRotationalVelocity = { };

    // scripting
    ::OOJSScript* script = { };
    ::OOJSScript* aiScript = { };
    OOTimeAbsolute aiScriptWakeTime = { };

    // docking instructions
    oo::PList dockingInstructions; // null: none (was nil); the station is an Object node (a weak reference)

    ::OOColor* laser_color = { };
    ::OOColor* default_laser_color = { };
    ::OOColor* exhaust_emissive_color = { };
    ::OOColor* scanner_display_color1 = { };
    ::OOColor* scanner_display_color2 = { };
    ::OOColor* scanner_display_color_hostile1 = { };
    ::OOColor* scanner_display_color_hostile2 = { };

    // per ship-type variables
    //
    GLfloat maxFlightSpeed = { }; // top speed			(160.0 for player)  (200.0 for fast raider)
    GLfloat max_flight_roll = { }; // maximum roll rate	(2.0 for player)	(3.0 for fast raider)
    GLfloat max_flight_pitch = { }; // maximum pitch rate   (1.0 for player)	(1.5 for fast raider) also radians/sec for (* turrets *)
    GLfloat max_flight_yaw = { };
    GLfloat cruiseSpeed = { }; // 80% of top speed

    GLfloat max_thrust = { }; // acceleration
    GLfloat thrust = { }; // acceleration
    float hyperspaceMotorSpinTime = { }; // duration of hyperspace countdown

    unsigned military_jammer_active : 1 = 0, // military_jammer

        docking_match_rotation : 1 = 0,

                                      pitching_over : 1 = 0, // set to YES if executing a sharp loop
        rolling_over : 1 = 0, // set to YES if executing a sharp roll
        reportAIMessages : 1 = 0, // normally NO, suppressing AI message reporting

        being_mined : 1 = 0, // normally NO, set to Yes when fired on by mining laser

        being_fined : 1 = 0,

                                      isHulk : 1 = 0, // This is used to distinguish abandoned ships from cargo
        trackCloseContacts : 1 = 0,
                                      isNearPlanetSurface : 1 = 0, // check for landing on planet
        isFrangible : 1 = 0, // frangible => subEntities can be damaged individually
        cloaking_device_active : 1 = 0, // cloaking_device
        cloakPassive : 1 = 0, // cloak deactivates when main weapons or missiles are fired
        cloakAutomatic : 1 = 0, // cloak activates itself automatic during attack
        canFragment : 1 = 0, // Can it break into wreckage?
        isWreckage : 1 = 0, // Is it wreckage?
        _showDamage : 1 = 0, // Show damage?
        suppressExplosion : 1 = 0, // Avoid exploding on death (script hook)
        suppressAegisMessages : 1 = 0, // No script/AI messages sent by -checkForAegis,
        isMissile : 1 = 0, // Whether this was launched by fireMissile (used to track submunitions).
        _explicitlyUnpiloted : 1 = 0, // Is meant to not have crew
        hasScoopMessage : 1 = 0, // suppress scoop messages when false.

        // scripting
        scripted_misjump : 1 = 0,
                                      haveExecutedSpawnAction : 1 = 0,
                                      haveStartedJSAI : 1 = 0,
                                      noRocks : 1 = 0,
                                      _lightsActive : 1 = 0;

    GLfloat _scriptedMisjumpRange = { };

    GLfloat sunGlareFilter = { }; // Range 0.0 - 1.0, where 0 means no sun glare filter, 1 means glare fully filtered

    OOFuelQuantity fuel = { }; // witch-space fuel
    GLfloat fuel_accumulator = { };

    GLfloat afterburner_rate = { };
    GLfloat afterburner_speed_factor = { };

    OOCargoQuantity likely_cargo = { }; // likely amount of cargo (for pirates, this is what is spilled as loot)
    OOCargoQuantity max_cargo = { }; // capacity of cargo hold
    OOCargoQuantity extra_cargo = { }; // capacity of cargo hold extension (if any)
    OOCargoQuantity equipment_weight = { }; // amount of equipment using cargo space (excluding passenger_berth & extra_cargo_bay)
    OOCargoType cargo_type = { }; // if this is scooped, this is indicates contents
    OOCargoFlag cargo_flag = { }; // indicates contents for merchantmen
    OOCreditsQuantity bounty = { }; // bounty (if any)

    GLfloat energy_recharge_rate = { }; // recharge rate for energy banks

    OOWeaponFacingSet weapon_facings = { }; // weapon mounts available (bitmask)
    OOWeaponType forward_weapon_type = { }; // type of forward weapon (allows lasers, plasma cannon, others)
    OOWeaponType aft_weapon_type = { }; // type of aft weapon (allows lasers, plasma cannon, others)
    OOWeaponType port_weapon_type = { }; // type of port weapon
    OOWeaponType starboard_weapon_type = { }; // type of starboard weapon
    GLfloat weapon_damage = { }; // energy damage dealt by weapon
    GLfloat weapon_damage_override = { }; // custom energy damage dealt by front laser, if applicable
    GLfloat weaponRange = { }; // range of the weapon (in meters)
    OOWeaponFacing currentWeaponFacing = { }; // not necessarily the same as view for the player

    GLfloat weapon_energy_use = { }, weapon_temp = { }, weapon_shot_temperature = { }; // active weapon temp, delta-temp
    GLfloat forward_weapon_temp = { }, aft_weapon_temp = { }, port_weapon_temp = { }, starboard_weapon_temp = { }; // current weapon temperatures

    GLfloat scannerRange = { }; // typically 25600

    unsigned missiles = { }; // number of on-board missiles
    unsigned max_missiles = { }; // number of missile pylons
    std::optional<std::string> _missileRole; // nullopt: no missile_role (the generic fallback)
    OOTimeDelta missile_load_time = { }; // minimum time interval between missile launches
    OOTimeAbsolute missile_launch_time = { }; // time of last missile launch

    ::AI* shipAI = { }; // ship's AI system

    std::optional<std::string> name; // descriptive name; nullopt: nil
    std::optional<std::string> shipUniqueName; // uniqish name e.g. "Terror of Lave"; nullopt: nil
    std::optional<std::string> shipClassName; // e.g. "Cobra III"; nullopt: nil
    std::optional<std::string> displayName; // name shown on screen; nullopt: nil
    std::optional<std::string> scan_description; // scan class name; nullopt: nil
    ::OORoleSet* roleSet = { }; // Roles a ship can take, eg. trader, hunter, police, pirate, scavenger &c.
    std::optional<std::string> primaryRole; // "Main" role of the ship; nullopt: not chosen yet

    oo::PList explosionType; // explosion.plist entries; null: absent

    // AI stuff
    Vector jink = { }; // x and y set factors for offsetting a pursuing ship's position
    HPVector coordinates = { }; // for flying to/from a set point
    Vector reference = { }; // a direction vector of magnitude 1 (* turrets *)

    NSUInteger _subIdx = { }; // serialisation index - used only if this ship is a subentity
    NSUInteger _maxShipSubIdx = { }; // serialisation index - the number of ship subentities inside the shipdata
    double launch_time = { }; // time at which launched
    double launch_delay = { }; // delay for thinking after launch
    OOUniversalID planetForLanding = { }; // for landing

    GLfloat frustration = { }, // degree of dissatisfaction with the current behavioural state, factor used to test this
        success_factor = { };

    int patrol_counter = { }; // keeps track of where the ship is along a patrol route

    oo::PList previousCondition; // restored after collision avoidance; null: none

    // derived variables
    float weapon_recharge_rate = { }; // time between shots
    int shot_counter = { }; // number of shots fired
    OOTimeAbsolute cargo_dump_time = { }; // time cargo was last dumped
    OOTimeAbsolute last_shot_time = { }; // time shot was last fired

    std::vector<oo::ObjCRef<::ShipEntity*>> cargo; // cargo containers go in here (index 0 is the eject position); edited in place through -cxx_cargo

    std::optional<std::string> commodity_type; // type of commodity in a container; nullopt: not a pod (was nil)
    OOCargoQuantity commodity_amount = { }; // 1 if unit is TONNES (0), possibly more if precious metals KILOGRAMS (1)
    // or gem stones GRAMS (2)

    // navigation
    GLfloat flightSpeed = { }; // current speed
    GLfloat flightRoll = { }; // current roll rate
    GLfloat flightPitch = { }; // current pitch rate
    GLfloat flightYaw = { }; // current yaw rate

    GLfloat accuracy = { };
    GLfloat pitch_tolerance = { };
    GLfloat aim_tolerance = { };
    int _missed_shots = { };

    OOAegisStatus aegis_status = { }; // set to YES when within the station's protective zone
    OOSystemID home_system = { };
    OOSystemID destination_system = { };

    double messageTime = { }; // counts down the seconds a radio message is active for

    double next_spark_time = { }; // time of next spark when throwing sparks

    Vector collision_vector = { }; // direction of colliding thing.

    GLfloat _scaleFactor = { }; // scale factor for size variation

    BOOL _multiplyWeapons = { }; // multiply instead of splitting weapons
    // position of gun ports
    std::vector<Vector> forwardWeaponOffset,
        aftWeaponOffset,
        portWeaponOffset,
        starboardWeaponOffset;

    // crew (typically one OOCharacter - the pilot); nullopt: unpiloted (was nil); an empty vector is crewed
    std::optional<std::vector<oo::ObjCRef<::OOCharacter*>>> crew;

    // close contact / collision tracking
    std::map<std::string, std::string, std::less<>> closeContactsInfo; // "%d" universal ID -> "%f %f %f" relative position

    std::optional<std::string> lastRadioMessage; // nullopt: none yet

    // scooping...
    Vector tractor_position = { };

    // from player entity moved here now we're doing more complex heat stuff
    float ship_temperature = { };

    // for advanced scanning etc.
    ::ShipEntity* scanned_ships[MAX_SCAN_NUMBER + 1] = { };
    GLfloat distance2_scanned_ships[MAX_SCAN_NUMBER + 1] = { };
    unsigned n_scanned_ships = { };

    // advanced navigation
    HPVector navpoints[32] = { };
    unsigned next_navpoint_index = { };
    unsigned number_of_navpoints = { };

    // Collision detection
    ::Octree* octree = { };

#ifdef OO_DEBUG_MONITOR_ENABLED
    // DEBUGGING
    OOBehaviour debugLastBehaviour = { };
#endif

    uint16_t entity_personality = { }; // Per-entity random number. Exposed to shaders and scripts.
    oo::PList scriptInfo; // script_info dictionary from shipdata.plist, exposed to scripts; null: none

    std::vector<oo::ObjCRef<::Entity*>> subEntities; // empty == none (was nil)
    ::OOEquipmentType* missile_list[SHIPENTITY_MAX_MISSILES] = { };

    // various types of target
    ::OOWeakReference* _primaryTarget = { }; // for combat or rendezvous
    ::OOWeakReference* _primaryAggressor = { }; // recorded after attack
    ::OOWeakReference* _targetStation = { }; // for docking
    ::OOWeakReference* _foundTarget = { }; // from scans
    ::OOWeakReference* _lastEscortTarget = { }; // last target an escort was deployed after
    ::OOWeakReference* _thankedShip = { }; // last ship thanked
    ::OOWeakReference* _rememberedShip = { }; // ship being remembered
    ::OOWeakReference* _proximityAlert = { }; // a ShipEntity within 2x collision_radius

    // Stuff for the target tracking curve.  The ship records the position of the target every reactionTime/2 seconds, then fits a curve to the
    // last three recorded positions.  Instead of tracking the primary target's actual position it uses the curve to calculate the target's position.
    // This introduces a small amount of lag to the target tracking making the NPC more human.
    float reactionTime = { };
    HPVector trackingCurvePositions[4] = { };
    OOTimeAbsolute trackingCurveTimes[4] = { };
    HPVector trackingCurveCoeffs[3] = { };

    // @private in Objective-C: private once ShipEntity is converted (oo-k8a); public while the
    // facade's unconverted methods read them, since an Objective-C class cannot be a C++ friend
    ::OOWeakReference* _subEntityTakingDamage = { }; //	frangible => subEntities can be damaged individually

    std::optional<std::string> _shipKey; // nullopt: nil

    std::vector<std::string> _equipment; // equipment keys, in order added; empty == none (was nil)
    float _heatInsulation = { };

    ::OOWeakReference* _lastAegisLock = { }; // remember last aegis planet/sun

    ::OOShipGroup* _group = { };
    ::OOShipGroup* _escortGroup = { };
    uint8_t _maxEscortCount = { };
    uint8_t _pendingEscortCount = { };
    // Cache of ship-relative positions, managed by -coordinatesForEscortPosition:.
    Vector _escortPositions[MAX_ESCORTS] = { };
    BOOL _escortPositionsValid = { };

    ::OOWeakSet* _defenseTargets = { }; // defense targets

    // ships in this set can't be collided with
    ::OOWeakSet* _collisionExceptions = { };

    GLfloat _profileRadius = { };

    ::OOWeakReference* _shipHitByLaser = { }; // entity hit by the last laser shot

    // beacons
    std::optional<std::string> _beaconCode; // nullopt: nil (never empty)
    std::optional<std::string> _beaconLabel; // nullopt: nil (never empty)
    ::OOWeakReference* _prevBeacon = { };
    ::OOWeakReference* _nextBeacon = { };
    id<OOHUDBeaconIcon> _beaconDrawable = nil;

    double _nextAegisCheck = { };

    // Demo ship state
    BOOL isDemoShip = { };
    OOScalar demoRate = { };
    OOTimeAbsolute demoStartTime = { };
    Quaternion demoStartOrientation = { };
};

} // namespace cxx

oo::PList OODefaultShipShaderMacros(void);

GLfloat getWeaponRangeFromType(OOWeaponType weapon_type);

#ifdef __cplusplus
extern "C" {
#endif
BOOL isWeaponNone(OOWeaponType weapon);
#ifdef __cplusplus
}
#endif

// C++ forms, defined in OOConstToString.mm (bead oo-nts1, chunk oo-3rb.161).
std::string cxx_OOStringFromBehaviour(OOBehaviour behaviour);
std::string cxx_OOStringFromShipDamageType(OOShipDamageType type);

// Weapon identifiers and alert-condition names (chunk oo-3rb.162); nullopt where the old form gave nil.
std::optional<std::string> cxx_OOEquipmentIdentifierFromWeaponType(OOWeaponType weapon); // nullopt: no weapon
OOWeaponType cxx_OOWeaponTypeFromEquipmentIdentifierSloppy(const std::string& string); // Uses suffix match for backwards compatibility.
OOWeaponType cxx_OOWeaponTypeFromEquipmentIdentifierStrict(const std::string& string);
OOWeaponType cxx_OOWeaponTypeFromEquipmentIdentifierLegacy(const std::string& string);
std::optional<std::string> cxx_OOStringFromWeaponType(OOWeaponType weapon);
OOWeaponType cxx_OOWeaponTypeFromString(const std::string& string);
std::optional<std::string> cxx_OODisplayStringFromAlertCondition(OOAlertCondition alertCondition);

// Transitional: the Objective-C ShipEntity, for its unconverted methods, its subclasses and its
// callers. Deleted, with namespace cxx above, by the bridge's deletion bead.
#import "ShipEntity+ObjCBridge.h"
