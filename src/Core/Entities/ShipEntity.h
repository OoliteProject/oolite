/*
 
 ShipEntity.h
 
 Entity subclass representing a ship, or various other flying things like cargo
 pods and stations (a subclass).
 
 The class is C++ (docs/phases/3-slices/ShipEntity.md, umbrella bead oo-k8a; proposed ADR-0056,
 amendments oo-bj8, oo-60fwo and oo-9ht.144). Since bead oo-9ht.144 deleted the Objective-C
 facade a ship's Objective-C object is the root's facade (OOEntityWithDrawable's until bead oo-9ht.40), made by oo::NewShipObject();
 the selectors the game still finds on a ship by name are the root facade's category
 Entity (OOShipSelectorsCalledByName) (Entity+ObjCBridge.mm).
 
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

#include "OOEntityWithDrawable.h"
#include "ooscript/JSEngine.hpp"
#include "OOPlanetEntity.h"
#include "OOJSPropID.h"

#include "oofnd/StdLib.hpp"
#include "oofnd/PList.hpp"
#include "oofnd/WeakSet.hpp"
#include "Octree.h"
#include "OORoleSet.h"
#include <string_view>

class StationEntity;
class OOMesh;	// C++ since bead oo-9ht.132
#include "OOScript.h"	// oo::Ref<OOScript> members and results (bead oo-9ht.133)
class WormholeEntity;	// C++ since bead oo-9ht.112
#include "OOColor.h"	// the colours are oo::Ref members
#include "OOCharacter.h"	// C++ since bead oo-9ht.10: the crew is oo::Ref
#include "OOShipGroup.h"	// C++ since bead oo-9ht.19: the groups are oo::Ref
#include "OOEquipmentType.h"	// C++ since bead oo-9ht.28: OOWeaponType is a C++ pointer
#include "OOPolygonSprite.h"	// OOHUDBeaconIcon (bead oo-7ae4p): the beacon drawable is oo::Ref
#include "AI.h"	// C++ since bead oo-9ht.73: shipAI is oo::Ref
class OOFlasherEntity;	// C++ only since bead oo-9ht.107
class OOExhaustPlumeEntity;	// C++ only since bead oo-9ht.110

// Universe.h's, for the members of ShipEntityAI.mm's scans (ADR-0056 amendment oo-42dr item 3).
typedef BOOL (*EntityFilterPredicate)(Entity *entity, void *parameter);	// the C++ entity since bead oo-9ht.39.23

#define MAX_TARGETS						24
#define RAIDER_MAX_CARGO				5
#define MERCHANTMAN_MAX_CARGO			125

#define PIRATES_PREFER_PLAYER			YES

#define TURRET_MINIMUM_COS				0.20f

#define SHIP_THRUST_FACTOR				5.0f
#define AFTERBURNER_BURNRATE			0.25f

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

#define SHIP_COOLING_FACTOR				0.1f
// heat taken from energy damage depends on mass
// but limit maximum rate since masses vary so much
// Cobra III ~=215000
#define SHIP_ENERGY_DAMAGE_TO_HEAT_FACTOR  (mass > 400000 ? 200000 / mass : 0.5)	// the ShipEntity member mass (the facade's part's until bead oo-9ht.39.23)
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

inline constexpr std::string_view AIMS_AGGRESSOR_SWITCHED_TARGET	= "AGGRESSOR_SWITCHED_TARGET";

// number of vessels considered when scanning around
#define MAX_SCAN_NUMBER					32

#define BASELINE_SHIELD_LEVEL			128.0f			// Max shield level with no boosters.
#define INITIAL_SHOT_TIME				100.0

#define	MIN_FUEL						0				// minimum fuel required for afterburner use
#ifdef OO_DUMP_PLANETINFO
// debugging planetinfo needs rapid jumping
#define MAX_JUMP_RANGE					150.0
#else
#define MAX_JUMP_RANGE					7.0				// the 7 ly limit
#endif

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
// AI reacts to changes in target path in about 1.5 seconds.
#define COMBAT_AI_STANDARD_REACTION_TIME	1.5f



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


typedef enum
{
	// Alert conditions are used by player and station entities.
	// NOTE: numerical values are available to scripts and shaders.
	ALERT_CONDITION_DOCKED	= 0,
	ALERT_CONDITION_GREEN	= 1,
	ALERT_CONDITION_YELLOW	= 2,
	ALERT_CONDITION_RED		= 3
} OOAlertCondition;


// OOShipDamageType (bead oo-9ht.64: plain header).
#include "OOEntityEnums.h"


struct OOShipSaveContext;	// ShipEntityLoadRestore.h
struct ShipEntityTestAccess;	// the unit tests' reader of the private members (bead oo-9ht.184.1)


/*	The ship's state and members (docs/phases/3-slices/ShipEntity.md).

	The ivars are data members with the same names, every one zero-initialised as the runtime
	zeroed them (amendment oo-bj8 item 1). Pointers to other entities' Objective-C objects stay
	what they were, retained by hand where they were (amendment oo-bj8 item 4; follow-up of bead
	oo-9ht.144, as for the player, amendment oo-9ht.177 item 6).
*/
class ShipEntity : public OOEntityWithDrawable, public cxx::OOSubEntityInterface	// <OOSubEntity> (amendment oo-9ht.107 item 3; bead oo-9ht.144)
{
public:
	/*	-cxx_initWithKey:definition:'s body between [super init] and the set-up from the
		dictionary. initShipSetUp() runs it, and then the set-up. Run again when an initialised ship
		is set up again (PlayerEntity::deferredInit()).
	*/
	void initWithKey(const std::string &key);

	/*	-cxx_initWithKey:definition:'s body after [super init] (the deleted facade's
		-initShipSetUpWithKey:definition:, bead oo-9ht.144): initWithKey(), then the set-up from the
		dictionary; false where the initialiser released the object and answered nil.
		oo::NewShipObject() and PlayerEntity::deferredInit() run it.
	*/
	bool initShipSetUp(const std::string &key, const oo::PList &dict);

	/*	The deleted facade's -dealloc body after the subclasses' parts and the weak reference's drop
		(the root facade's -dealloc runs them first for a ship's part, bead oo-9ht.144).
	*/
	void shipWillDealloc();

	// The category SubEntityRelationship: other is a ship that is a subentity of this ship, and
	// this ship agrees.
	bool isShipWithSubEntityShip(Entity *other);

	// Slice 2: set-up from the ship dictionary (cxx_setUpFromDictionary:).
	bool setUpFromDictionary(const oo::PList &inShipDict);

	// Slice 3: setUpShipFromDictionary:, subentity serialisation and set-up.
	virtual bool setUpShipFromDictionary(const oo::PList &shipDict);
	void setSubIdx(NSUInteger value);
	NSUInteger subIdx();
	NSUInteger maxShipSubEntities();
	std::optional<std::string> serializeShipSubEntities();
	void deserializeShipSubEntitiesFrom(const std::string &string);
	virtual bool setUpSubEntities();
	GLfloat frustumRadius() override;
	bool setUpOneSubentity(const oo::PList &subentDict);
	bool setUpOneFlasher(const oo::PList &subentDict);

	// Slice 4: standard subentities and cargo pods; descriptions, mesh, vectors, misjump, subentity lists, AI scripts.
	virtual bool setUpOneStandardSubentity(const oo::PList &subentDict, bool asTurret);	// virtual: a test seam (amendment oo-9ht.107 item 6; test_StationEntity's station overrides it since bead oo-9ht.175)
	bool isTemplateCargoPod();
	void setUpCargoType(const std::string &cargoString);
	void removeScript();
	void clearSubEntities();
	Quaternion subEntityRotationalVelocity();
	void setSubEntityRotationalVelocity(Quaternion rv);
	std::optional<std::string> shortDescriptionComponents();
	GLfloat getSunGlareFilter();
	void setSunGlareFilter(GLfloat newValue);
	GLfloat getAccuracy();
	void setAccuracy(GLfloat new_accuracy);
	::OOMesh *mesh();
	void setMesh(::OOMesh *mesh);
	BoundingBox getTotalBoundingBox();
	virtual Vector forwardVector();
	Vector upVector();
	Vector rightVector();
	bool scriptedMisjump();
	void setScriptedMisjump(bool newValue);
	GLfloat scriptedMisjumpRange();
	void setScriptedMisjumpRange(GLfloat newValue);
	std::vector<oo::EntityHold> getSubEntities();
	NSUInteger subEntityCount();
	bool hasSubEntity(Entity *sub);
	std::vector<oo::EntityHold> subEntityEnumerator();
	std::vector<oo::EntityHold> shipSubEntities();
	std::vector<oo::EntityHold> flasherEnumerator();	// the flashers' objects (the nearest façade left)
	std::vector<oo::EntityHold> exhausts();	// the plumes' objects (the root façade)
	::ShipEntity *subEntityTakingDamage();
	void setSubEntityTakingDamage(::ShipEntity *sub);
	::OOScript *shipScript();
	::OOScript *shipAIScript();
	OOTimeAbsolute shipAIScriptWakeTime();
	void setAIScriptWakeTime(OOTimeAbsolute t);
	std::optional<std::string> descriptionComponents() const override;

	// Slice 5: bounding boxes, octree hit tests, universe add / remove, beacons, boulders, escort set-up.
	BoundingBox findBoundingBoxRelativeToPosition(HPVector opv, Vector _i, Vector _j, Vector _k);
	Octree *getOctree();
	float volume();
	GLfloat doesHitLine(HPVector v0, HPVector v1);
	virtual GLfloat doesHitLine(HPVector v0, HPVector v1, ::ShipEntity **hitEntity);
	GLfloat doesHitLine(HPVector v0, HPVector v1, HPVector o, Vector i, Vector j, Vector k);
	void wasAddedToUniverse() override;
	void wasRemovedFromUniverse() override;
	HPVector absoluteTractorPosition();
	std::optional<std::string> beaconCode();
	void setBeaconCode(const std::optional<std::string> &bcode);
	std::optional<std::string> beaconLabel();
	void setBeaconLabel(const std::optional<std::string> &blabel);
	bool isVisible() override;
	bool isBeacon();
	OOHUDBeaconIcon *beaconDrawable();	// borrowed (the protocol type until bead oo-7ae4p)
	Entity *prevBeacon();	// C++ since bead oo-9ht.39.23
	virtual Entity *nextBeacon();
	Entity *nextBeaconEntity();	// nextBeacon(), null for none (bead oo-9ht.39.8.10)
	void setPrevBeacon(Entity *beaconShip);
	void setNextBeacon(Entity *beaconShip);
	void setIsBoulder(bool flag);
	bool isBoulder();
	bool isMinable();
	bool countsAsKill();
	void setUpEscorts();
	void setUpMixedEscorts();

	// Slice 6: escort creation, ship data key, weapon offsets, octree collision checks, subentity geometry, escape-pod launch.
	void setUpOneEscort(::ShipEntity *escorter, ::OOShipGroup *escortGroup, const std::string &escortRole, HPVector ex_pos, uint8_t currentEscortCount);
	std::optional<std::string> shipDataKey();
	std::optional<std::string> shipDataKeyAutoRole();
	void setShipDataKey(const std::optional<std::string> &key);
	oo::PList shipInfoDictionary();
	std::vector<Vector> weaponOffsetsFrom(const oo::PList &dict, const std::string &key, const std::string &mode);
	std::vector<Vector> getAftWeaponOffset();
	std::vector<Vector> getForwardWeaponOffset();
	std::vector<Vector> getPortWeaponOffset();
	std::vector<Vector> getStarboardWeaponOffset();
	bool getIsFrangible();
	bool suppressFlightNotifications();
	OOScanClass getScanClass() override;
	bool canCollide() override;
	bool checkCloseCollisionWith(Entity *other) override;
	BoundingBox findSubentityBoundingBox();
	Triangle absoluteIJKForSubentity();
	void addSubentityToCollisionRadius(Entity *subent);
	::ShipEntity *launchPodWithCrew(const std::vector<oo::Ref<OOCharacter>> &podCrew);
	bool validForAddToUniverse() override;

	// Slice 7: update:.
	void update(OOTimeDelta delta_t) override;

	// Slice 8: behaviour dispatch, attack response, equipment queries.
	void processBehaviour(OOTimeDelta delta_t);
	void noteFrustration(const std::string &context);
	void respondToAttackFrom(Entity *from, Entity *other);
	bool hasOneEquipmentItem(const std::string &itemKey, bool includeWeapons, bool loading);
	bool hasOneEquipmentItemIncludingMissiles(const std::string &itemKey, bool includeMissiles, bool loading);
	virtual bool hasPrimaryWeapon(OOWeaponType weaponType);
	NSUInteger countEquipmentItem(const std::string &eqkey);
	bool hasEquipmentItem(const oo::PList &equipmentKeys, bool includeWeapons, bool loading);
	bool hasEquipmentItem(const oo::PList &equipmentKeys);
	virtual bool hasEquipmentItemProviding(const std::string &equipmentType);
	std::optional<std::string> equipmentItemProviding(const std::string &equipmentType);
	bool hasAllEquipment(const oo::PList &equipmentKeys, bool includeWeapons, bool loading);
	bool hasAllEquipment(const oo::PList &equipmentKeys);
	virtual bool hasHyperspaceMotor();
	float hyperspaceSpinTime();
	void setHyperspaceSpinTime(float newValue);

	// Slice 9: equipment validity and adding, weapon mounts, scripting lists.
	virtual bool canAddEquipment(const std::string &equipmentKeyIn, const std::string &context);
	OOWeaponFacingSet weaponFacings();
	OOWeaponType weaponTypeIDForFacing(OOWeaponFacing facing, bool strict);
	virtual ::OOEquipmentType *weaponTypeForFacing(OOWeaponFacing facing, bool strict);
	virtual std::vector<oo::Ref<::OOEquipmentType>> missilesList();
	virtual oo::PList passengerListForScripting();
	virtual oo::PList parcelListForScripting();
	virtual oo::PList contractListForScripting();
	::OOEquipmentType *generateMissileEquipmentTypeFrom(const std::string &role);
	std::vector<oo::Ref<::OOEquipmentType>> equipmentListForScripting();
	bool equipmentValidToAdd(const std::string &equipmentKey, const std::string &context);
	bool equipmentValidToAdd(const std::string &fullEquipmentKey, bool loading, const std::string &context);
	virtual bool setWeaponMount(OOWeaponFacing facing, const std::string &eqKey);
	virtual bool addEquipmentItem(const std::string &equipmentKey, const std::string &context);
	virtual bool addEquipmentItem(const std::string &equipmentKeyIn, bool validateAddition, const std::string &context);
	std::vector<std::string> equipmentKeys();
	NSUInteger equipmentCount();

	// Slice 10: equipment removal, missile selection, capacities and has-equipment predicates, shields.
	virtual void removeEquipmentItem(const std::string &equipmentKey);
	virtual bool removeExternalStore(::OOEquipmentType *eqType);
	::OOEquipmentType *verifiedMissileTypeFromRole(const std::string &requestedRole);
	::OOEquipmentType *selectMissile();
	void removeAllEquipment();
	virtual OOCreditsQuantity removeMissiles();
	virtual NSUInteger parcelCount();
	virtual NSUInteger passengerCount();
	virtual NSUInteger passengerCapacity();
	NSUInteger missileCount();
	NSUInteger missileCapacity();
	NSUInteger extraCargo();
	bool hasScoop();
	bool hasFuelScoop();
	bool hasCargoScoop();
	bool hasECM();
	bool hasCloakingDevice();
	bool hasMilitaryScannerFilter();
	bool hasMilitaryJammer();
	bool hasExpandedCargoBay();
	bool hasShieldBooster();
	bool hasMilitaryShieldEnhancer();
	bool hasHeatShield();
	bool hasFuelInjection();
	bool hasCascadeMine();
	bool hasEscapePod();
	bool hasDockingComputer();
	bool hasGalacticHyperdrive();
	float shieldBoostFactor();
	virtual float maxForwardShieldLevel();
	virtual float maxAftShieldLevel();
	float shieldRechargeRate();
	double maxHyperspaceDistance();

	// Slice 11: thrust and afterburner; behaviours: idle, tumble, tractored, track, intercept, break off, dogfight, evasive.
	float afterburnerFactor();
	float afterburnerRate();
	void setAfterburnerFactor(GLfloat newValue);
	void setAfterburnerRate(GLfloat newValue);
	float maxThrust();
	void setMaxThrust(GLfloat newValue);
	float getThrust();
	void behaviour_stop_still(double delta_t);
	void behaviour_idle(double delta_t);
	void behaviour_tumble(double delta_t);
	void behaviour_tractored(double delta_t);
	void behaviour_track_target(double delta_t);
	void behaviour_intercept_target(double delta_t);
	void behaviour_attack_break_off_target(double delta_t);
	void behaviour_attack_slow_dogfight(double delta_t);
	void behaviour_evasive_action(double delta_t);

	// Slice 12: behaviours: attack target, broadside, close with target.
	void behaviour_attack_target(double delta_t);
	void behaviour_attack_broadside(double delta_t);
	void behaviour_attack_broadside_left(double delta_t);
	void behaviour_attack_broadside_right(double delta_t);
	void behaviour_attack_broadside_target(double delta_t, bool leftside);
	void behaviour_close_to_broadside_range(double delta_t);
	void behaviour_close_with_target(double delta_t);

	// Slice 13: behaviours: sniper, fly to target six, mining target, attack fly to target.
	void behaviour_attack_sniper(double delta_t);
	void behaviour_fly_to_target_six(double delta_t);
	void behaviour_attack_mining_target(double delta_t);
	void behaviour_attack_fly_to_target(double delta_t);

	// Slice 14: behaviours: fly from target, running defence, flee, range from destination, face destination, land on planet, formation.
	void behaviour_attack_fly_from_target(double delta_t);
	void behaviour_running_defense(double delta_t);
	void behaviour_flee_target(double delta_t);
	void behaviour_fly_range_from_destination(double delta_t);
	void behaviour_face_destination(double delta_t);
	void behaviour_land_on_planet(double delta_t);
	void behaviour_formation_form_up(double delta_t);

	// Slice 15: behaviours: fly to / from destination, avoid collision, turret, navpoints, scripted AI; reaction time.
	void behaviour_fly_to_destination(double delta_t);
	void behaviour_fly_from_destination(double delta_t);
	void behaviour_avoid_collision(double delta_t);
	void behaviour_track_as_turret(double delta_t);
	void behaviour_fly_thru_navpoints(double delta_t);
	void behaviour_scripted_ai(double delta_t);
	float getReactionTime();
	void setReactionTime(float newReactionTime);
	HPVector calculateTargetPosition();

	// Slice 16: tracking curve, drawing, scanner colours, cloaking, subentities and owner, thrust.
	void startTrackingCurve();
	void updateTrackingCurve();
	void calculateTrackingCurve();
	void drawImmediate(bool immediate, bool translucent) override;
#ifndef NDEBUG
	void drawDebugStuff();
#endif
	void drawSubEntityImmediate(bool immediate, bool translucent) override;
	GLfloat *scannerDisplayColorForShip(::ShipEntity *otherShip, bool isHostile, bool flash, ::OOColor *scannerDisplayColor1, ::OOColor *scannerDisplayColor2, ::OOColor *scannerDisplayColorH1, ::OOColor *scannerDisplayColorH2);
	void setScannerDisplayColor1(::OOColor *color);
	void setScannerDisplayColor2(::OOColor *color);
	::OOColor *scannerDisplayColor1();
	::OOColor *scannerDisplayColor2();
	void setScannerDisplayColorHostile1(::OOColor *color);
	void setScannerDisplayColorHostile2(::OOColor *color);
	::OOColor *scannerDisplayColorHostile1();
	::OOColor *scannerDisplayColorHostile2();
	bool isCloaked();
	bool getCloakPassive();
	void setCloaked(bool cloak);
	bool hasAutoCloak();
	void setAutoCloak(bool automatic);
	bool isJammingScanning();
	void addSubEntity(Entity *sub);	// an OOSubEntity (amendment oo-mvzmb item 5); the C++ entity since bead oo-9ht.39.23
	void setOwner(Entity *who_owns_entity) override;
	void applyThrust(double delta_t);
	void orientationChanged() override;

	// Slice 17: attitude, collision avoidance, messages, groups and escort accessors, proximity alert, names and descriptions.
	void applyRoll(GLfloat roll1, GLfloat climb1) override;
	void applyRoll(GLfloat roll1, GLfloat climb1, GLfloat yaw1) override;
	virtual void applyAttitudeChanges(double delta_t);	// PlayerEntity overrides
	void avoidCollision();
	void resumePostProximityAlert();
	double getMessageTime();
	void setMessageTime(double value);
	::OOShipGroup *group();
	void setGroup(::OOShipGroup *group);
	::OOShipGroup *escortGroup();
	void setEscortGroup(::OOShipGroup *group);
#ifndef NDEBUG
	::OOShipGroup *rawEscortGroup();
#endif
	::OOShipGroup *stationGroup();
	bool hasEscorts();
	std::vector<oo::EntityHold> escorts();
	std::vector<oo::EntityHold> escortArray();
	uint8_t escortCount();
	uint8_t pendingEscortCount();
	void setPendingEscortCount(uint8_t count);
	uint8_t maxEscortCount();
	void setMaxEscortCount(uint8_t newCount);
	NSUInteger turretCount();
	Entity *proximityAlert();	// C++ since bead oo-9ht.39.23.2
	void setProximityAlert(::ShipEntity *other);
	std::optional<std::string> getName();
	std::optional<std::string> getShipUniqueName();
	std::optional<std::string> getShipClassName();
	std::optional<std::string> getDisplayName();
	std::optional<std::string> scanDescriptionForScripting();
	std::optional<std::string> scanDescription();
	virtual void setName(const std::optional<std::string> &inName);	// PlayerEntity overrides
	void setShipUniqueName(const std::optional<std::string> &inName);
	void setShipClassName(const std::optional<std::string> &inName);
	void setDisplayName(const std::optional<std::string> &inName);
	void setScanDescription(const std::optional<std::string> &inName);

	// Slice 18: roles, ship-type predicates, hostility, weapon data, scanner range, aegis transition, nearest planet.
	std::optional<std::string> identFromShip(::ShipEntity *otherShip);
	bool hasRole(const std::string &role);
	oo::Ref<::OORoleSet> getRoleSet();	// null where the facade's -roleSet was nil
	void addRole(const std::string &role);
	void addRole(const std::string &role, float probability);
	void removeRole(const std::string &role);
	std::optional<std::string> getPrimaryRole();
	void setPrimaryRole(const std::string &role);
	bool hasPrimaryRole(const std::string &role);
	bool isPolice();
	bool isThargoid();
	bool isTrader();
	bool isPirate();
	bool getIsMissile();
	bool isMine();
	bool isWeapon();
	bool isEscort();
	bool isShuttle();
	bool isTurret();
	bool isPirateVictim();
	bool isExplicitlyUnpiloted();
	virtual bool isUnpiloted();	// StationEntity overrides
	void getJSClass(ooscript::ClassDef **outClass, ooscript::Object *outPrototype) override;	// StationEntity overrides
	std::optional<std::string> jsClassName() override;	// StationEntity overrides
	bool isVisibleToScripts() override;	// YES, as the Objective-C ShipEntity answered (bead oo-ak1km); StationEntity and DockEntity override with the same answer
	virtual bool hasHostileTarget();	// PlayerEntity and StationEntity override
	bool isHostileTo(Entity *entity);
	GLfloat getWeaponRange();
	void setWeaponRange(GLfloat value);
	void setWeaponDataFromType(OOWeaponType weapon_type);
	float energyRechargeRate();
	void setEnergyRechargeRate(GLfloat newValue);
	float weaponRechargeRate();
	void setWeaponRechargeRate(float value);
	void setWeaponEnergy(float value);
	virtual OOWeaponFacing getCurrentWeaponFacing();
	GLfloat getScannerRange();
	void setScannerRange(GLfloat value);
	Vector getReference();
	void setReference(Vector v);
	bool getReportAIMessages();
	void setReportAIMessages(bool yn);
	void transitionToAegisNone();
	virtual ::OOPlanetEntity *findNearestPlanet();
	Entity *findNearestStellarBody();	// an OOStellarBody (amendment oo-mvzmb item 5); the C++ entity since bead oo-9ht.39.23
	::OOPlanetEntity *findNearestPlanetExcludingMoons();

	// Slice 19: aegis, home and destination systems, status, crew, AI and ship script, fuel.
	OOAegisStatus checkForAegis();
	void forceAegisCheck();
	bool withinStationAegis();
	Entity *lastAegisLock();	// a planet or sun (amendment oo-mvzmb item 5), its C++ entity
	void setLastAegisLock(Entity *lastAegisLock);	// C++ since bead oo-9ht.39.23.3
	OOSystemID homeSystem();
	OOSystemID destinationSystem();
	void setHomeSystem(OOSystemID s);
	void setDestinationSystem(OOSystemID s);
	void setStatus(OOEntityStatus stat) override;
	void setLaunchDelay(double delay);
	std::optional<std::vector<oo::Ref<OOCharacter>>> getCrew();
	void setCrew(const std::optional<std::vector<oo::Ref<OOCharacter>>> &crewArray);
	void setSingleCrewWithRole(const std::string &crewRole);
	std::vector<oo::PList> crewForScripting();
	void setStateMachine(const std::string &smName);
	void setAI(::AI *ai);
	::AI *getAI();	// borrowed: the ship owns it (shipAI)
	bool hasAutoAI();
	bool hasNewAI();
	bool hasAutoWeapons();
	void setShipScript(const std::optional<std::string> &script_name);
	double getFrustration();
	OOFuelQuantity getFuel();
	void setFuel(OOFuelQuantity amount);
	OOFuelQuantity fuelCapacity();
	virtual GLfloat fuelChargeRate();	// PlayerEntity overrides

	// Slice 20: sticks, bounty and legal status, commodities and cargo, speed.
	void applySticks(double delta_t);
	void setRoll(double amount);
	void setRawRoll(double amount);
	void setPitch(double amount);
	void setYaw(double amount);
	void setThrust(double amount);
	void setThrustForDemo(float factor);
	virtual void setBounty(OOCreditsQuantity amount);
	virtual void setBounty(OOCreditsQuantity amount, OOLegalStatusReason reason);
	virtual void setBounty(OOCreditsQuantity amount, const std::string &reason);
	virtual OOCreditsQuantity getBounty();
	virtual int legalStatus();
	void setCommodity(const std::string &co_type, OOCargoQuantity co_amount);
	void setCommodityForPod(const std::optional<std::string> &co_type, OOCargoQuantity co_amount);
	std::optional<std::string> commodityType();
	OOCargoQuantity commodityAmount();
	OOCargoQuantity maxAvailableCargoSpace();
	void setMaxAvailableCargoSpace(OOCargoQuantity newValue);
	OOCargoQuantity availableCargoSpace();
	virtual OOCargoQuantity cargoQuantityOnBoard();
	OOCargoType cargoType();
	std::vector<oo::EntityHold> *getCargo();
	NSUInteger cargoCount();
	virtual oo::PList cargoListForScripting();
	void setCargo(const std::vector<oo::EntityHold> &some_cargo);
	bool addCargo(const std::vector<oo::EntityHold> &some_cargo);
	bool removeCargo(const std::string &commodity, OOCargoQuantity amount);
	bool showScoopMessage();
	OOCargoFlag cargoFlag();
	void setCargoFlag(OOCargoFlag flag);
	void setSpeed(double amount);
	void setDesiredSpeed(double amount);
	double desiredSpeed();

	// Slice 21: flight controls and limits, temperature, dealing damage, hulks, damage notes.
	double desiredRange();
	void setDesiredRange(double amount);
	double getCruiseSpeed();
	void increase_flight_speed(double delta);
	void decrease_flight_speed(double delta);
	void increase_flight_roll(double delta);
	virtual void decrease_flight_roll(double delta);
	void increase_flight_pitch(double delta);
	virtual void decrease_flight_pitch(double delta);
	void increase_flight_yaw(double delta);
	virtual void decrease_flight_yaw(double delta);
	virtual GLfloat getFlightRoll();
	virtual GLfloat getFlightPitch();
	virtual GLfloat getFlightYaw();
	GLfloat getFlightSpeed();
	GLfloat maxFlightPitch();
	GLfloat getMaxFlightSpeed();
	GLfloat maxFlightRoll();
	GLfloat maxFlightYaw();
	virtual void setMaxFlightPitch(GLfloat newValue);
	void setMaxFlightSpeed(GLfloat newValue);
	virtual void setMaxFlightRoll(GLfloat newValue);
	virtual void setMaxFlightYaw(GLfloat newValue);
	GLfloat speedFactor();
	GLfloat temperature();
	void setTemperature(GLfloat value);
	float randomEjectaTemperature();
	float randomEjectaTemperatureWithMaxFactor(float factor);
	GLfloat heatInsulation();
	void setHeatInsulation(GLfloat value);
	int damage();
	void dealEnergyDamage(GLfloat baseDamage, GLfloat range, GLfloat velocityBias);
	void dealEnergyDamageWithinDesiredRange();
	void dealMomentumWithinDesiredRange(double amount);
	bool getIsHulk();
	void setHulk(bool isNowHulk);
	virtual void noteTakingDamage(double amount, Entity *entity, OOShipDamageType type);
	void noteKilledBy(Entity *whom, OOShipDamageType type);

	// Slice 22: destruction, rescaling, cargo debris, explosions, energy blast.
	virtual void getDestroyedBy(Entity *whom, OOShipDamageType type);
	void rescaleBy(GLfloat factor) override;
	void rescaleBy(GLfloat factor, bool writeToCache) override;
	void releaseCargoPodsDebris();
	void setIsWreckage(bool isw);
	bool showDamage();
	virtual void becomeExplosion();
	virtual void becomeEnergyBlast();
	void broadcastEnergyBlastImminent();
	void removeExhaust(OOExhaustPlumeEntity *exhaust);

	// Slice 23: subentity death, alignment offsets, large explosion, laser heat, personality, scanner, remembered ships.
	void removeFlasher(OOFlasherEntity *flasher);
	void subEntityDied(::ShipEntity *sub);
	void subEntityReallyDied(::ShipEntity *sub) override;
	Vector positionOffsetForAlignment(const std::string &align);
	virtual void becomeLargeExplosion(double factor);
	virtual void collectBountyFor(::ShipEntity *other);
	OOComparisonResult compareBeaconCodeWith(Entity *other);	// an OOBeaconEntity (amendment oo-mvzmb item 5); the C++ entity since bead oo-9ht.39.23
	GLfloat weaponRecoveryTime();
	virtual GLfloat laserHeatLevel();
	virtual GLfloat laserHeatLevelAft();
	virtual GLfloat laserHeatLevelForward();
	virtual GLfloat laserHeatLevelPort();
	virtual GLfloat laserHeatLevelStarboard();
	GLfloat hullHeatLevel();
	GLfloat entityPersonality();
	GLint entityPersonalityInt();
	uint32_t randomSeedForShaders();
	void setEntityPersonalityInt(uint16_t value);
	void setSuppressExplosion(bool suppress);
	void resetExhaustPlumes();
	void checkScanner();
	void checkScannerIgnoringUnpowered();
	::ShipEntity * *scannedShips();
	int numberOfScannedShips();
	Entity *foundTarget();	// C++ since bead oo-9ht.39.23
	virtual void setFoundTarget(Entity *targetEntity);
	Entity *primaryAggressor();	// C++ since bead oo-9ht.39.23
	void setPrimaryAggressor(Entity *targetEntity);
	Entity *lastEscortTarget();	// C++ since bead oo-9ht.39.23.1
	void setLastEscortTarget(Entity *targetEntity);

	// Slice 24: target memory and validity, behaviour and destination accessors, distances, leading the target.
	Entity *thankedShip();	// C++ since bead oo-9ht.39.23.1
	void setThankedShip(Entity *targetEntity);
	Entity *rememberedShip();
	void setRememberedShip(Entity *targetEntity);
	Entity *targetStation();	// the target station (or the mother an escort docks with), its C++ entity since bead oo-9ht.39.23.4 (its object before; ::StationEntity * until bead oo-9ht.175)
	void setTargetStation(Entity *targetEntity);	// C++ since bead oo-9ht.39.23.4
	virtual bool isValidTarget(Entity *target);	// C++ since bead oo-9ht.39.23
	virtual void addTarget(Entity *targetEntity);
	virtual void removeTarget(Entity *targetEntity);	// virtual: a test seam (amendment oo-9ht.107 item 6; test_EntityOOJavaScriptExtensions' ship overrides it since bead oo-9ht.144)
	bool canStillTrackPrimaryTarget();
	virtual Entity *primaryTarget();	// C++ since bead oo-9ht.39.23 (its object, typed id, before)
	Entity *primaryTargetWithoutValidityCheck();
	bool isFriendlyTo(::ShipEntity *otherShip);
	::ShipEntity *shipHitByLaser();
	void setShipHitByLaser(::ShipEntity *ship);
	virtual void noteLostTarget();
	void noteLostTargetAndGoIdle();
	void noteTargetDestroyed(::ShipEntity *target);
	OOBehaviour getBehaviour();
	void setBehaviour(OOBehaviour cond);
	HPVector destination();
	HPVector getCoordinates();
	void setCoordinate(HPVector coord);
	HPVector distance_six(GLfloat dist);
	HPVector distance_twelve(GLfloat dist, GLfloat offset);
	void trackOntoTarget(double delta_t, GLfloat dp);
	double ballTrackLeadingTarget(double delta_t, Entity *target);

	// Slice 25: evasive jink, primary and side target tracking.
	void setEvasiveJink(GLfloat z);
	void evasiveAction(double delta_t);
	double trackPrimaryTarget(double delta_t, bool retreat);
	double trackSideTarget(double delta_t, bool leftside);

	// Slice 26: missile and destination tracking, collision exceptions, defence targets, ranges.
	double missileTrackPrimaryTarget(double delta_t);
	double trackDestination(double delta_t, bool retreat);
	GLfloat rollToMatchUp(Vector up_vec, GLfloat match_roll);
	GLfloat rangeToDestination();
	std::vector<oo::EntityHold> collisionExceptions();
	void addCollisionException(::ShipEntity *ship);
	void removeCollisionException(::ShipEntity *ship);
	bool collisionExceptedFor(::ShipEntity *ship);
	NSUInteger defenseTargetCount();
	std::vector<oo::EntityHold> allDefenseTargets();
	std::vector<oo::EntityHold> defenseTargets();
	bool addDefenseTarget(Entity *target);	// C++ since bead oo-9ht.39.23
	void validateDefenseTargets();
	bool isDefenseTarget(Entity *target);
	void removeAllDefenseTargets();
	void removeDefenseTarget(Entity *target);
	double rangeToPrimaryTarget();
	double rangeToSecondaryTarget(Entity *target);
	double approachAspectToPrimaryTarget();
	bool hasProximityAlertIgnoringTarget(bool ignore_target);

	// Slice 27: aim tolerance, sun glare, main weapons and turret fire, laser colours.
	GLfloat currentAimTolerance();
	virtual GLfloat lookingAtSunWithThresholdAngleCos(GLfloat thresholdAngleCos);
	bool onTarget(OOWeaponFacing direction, OOWeaponType weapon_type);
	bool fireWeapon(OOWeaponType weapon_type, OOWeaponFacing direction, double range);
	bool fireMainWeapon(double range);
	bool fireAftWeapon(double range);
	bool firePortWeapon(double range);
	bool fireStarboardWeapon(double range);
	OOTimeDelta shotTime();
	void resetShotTime();
	bool fireTurretCannon(double range);
	void setLaserColor(::OOColor *color);
	void setExhaustEmissiveColor(::OOColor *color);
	::OOColor *laserColor();
	::OOColor *exhaustEmissiveColor();

	// Slice 28: laser shots, missed shots, sparks, missile launch decision.
	bool fireSubentityLaserShot(double range);
	bool fireDirectLaserShot(double range);
	bool fireDirectLaserDefensiveShot();
	bool fireDirectLaserShotAt(Entity *my_target);
	std::vector<Vector> laserPortOffset(OOWeaponFacing direction);
	bool fireLaserShotInDirection(OOWeaponFacing direction, const std::string &weaponIdentifier);
	void adjustMissedShots(int delta);
	int missedShots();
	void throwSparks() override;
	void considerFiringMissile(double delta_t);
	Vector missileLaunchPosition();
	virtual ::ShipEntity *fireMissile();

	// Slice 29: missile firing, ECM, cloak, cascade mine, escape capsule, cargo dumping.
	::ShipEntity *fireMissileWithIdentifier(const std::optional<std::string> &requestedIdentifier, Entity *target);
	bool isMissileFlagSet();
	void setIsMissileFlag(bool newValue);
	OOTimeDelta missileLoadTime();
	void setMissileLoadTime(OOTimeDelta newMissileLoadTime);
	virtual void noticeECM();
	virtual bool fireECM();
	virtual bool activateCloakingDevice();
	virtual void deactivateCloakingDevice();
	bool launchCascadeMine();
	virtual ::ShipEntity *launchEscapeCapsule();
	virtual void dumpCargo();
	::ShipEntity *dumpCargoItem(const std::optional<std::string> &preferred);
	OOCargoType dumpItem(::ShipEntity *cargoObj);

	// Slice 30: collisions, velocity, tractoring and scooping.
	void manageCollisions();
	virtual bool collideWithShip(::ShipEntity *other);
	Vector thrustVector();
	Vector getVelocity() override;
	void setTotalVelocity(Vector vel);
	virtual void adjustVelocity(Vector xVel);
	void addImpactMoment(Vector moment, GLfloat howmuch);
	virtual bool canScoop(::ShipEntity *other);
	void getTractoredBy(::ShipEntity *other);
	void scoopIn(::ShipEntity *other);
	virtual void suppressTargetLost();
	void scoopUp(::ShipEntity *other);
	void scoopUpProcess(::ShipEntity *other, bool procEvents, bool procMessages);

	// Slice 31: cascades, energy / scrape / heat damage, abandoning ship, docks, wormholes, witchspace.
	bool cascadeIfAppropriateWithDamageAmount(double amount, Entity *owner);
	void takeEnergyDamage(double amount, Entity *ent, Entity *other, const std::string &weaponIdentifier) override;
	bool abandonShip();
	virtual void takeScrapeDamage(double amount, Entity *ent);
	virtual void takeHeatDamage(double amount);
	virtual void enterDock(::StationEntity *station);
	virtual void leaveDock(::StationEntity *station);
	virtual void enterWormhole(::WormholeEntity *w_hole);
	void enterWormhole(::WormholeEntity *w_hole, bool replacing);
	virtual void enterWitchspace();
	virtual void leaveWitchspace();

	// Slice 32: witchspace effects, offences, lights, escort formation and deployment, nearest stations.
	bool witchspaceLeavingEffects();
	virtual void markAsOffender(int offence_value);
	virtual void markAsOffender(int offence_value, OOLegalStatusReason reason);
	void switchLightsOn();
	void switchLightsOff();
	bool lightsActive();
	void setDestination(HPVector dest);
	void setEscortDestination(HPVector dest);
	bool canAcceptEscort(::ShipEntity *potentialEscort);
	bool acceptAsEscort(::ShipEntity *other_ship);
	void updateEscortFormation();
	void refreshEscortPositions();
	HPVector coordinatesForEscortPosition(unsigned idx);
	void deployEscorts();
	void dockEscorts();
	void setTargetToNearestStationIncludingHostiles(bool includeHostiles);
	void setTargetToNearestFriendlyStation();
	void setTargetToNearestStation();
	void setTargetToSystemStation();

	// Slice 33: landing, docking abort, broadcasts and comms, fines, AI messages, spawning, close contacts, salvage.
	void landOnPlanet(::OOPlanetEntity *planet);
	void abortDocking();
	oo::PList getDockingInstructions();
	void broadcastThargoidDestroyed();
	void broadcastHitByLaserFrom(::ShipEntity *aggressor_ship);
	void sendMessage(const std::string &message_text, ::ShipEntity *other_ship, bool unpilotedOverride);
	void sendExpandedMessage(const std::string &message_text, ::ShipEntity *other_ship);
	void broadcastAIMessage(const std::string &ai_message);
	void broadcastMessage(const std::string &message_text, bool unpilotedOverride);
	void setCommsMessageColor();
	virtual void receiveCommsMessage(const std::string &message_text, ::ShipEntity *other);
	void commsMessage(const std::string &valueString, bool unpilotedOverride);
	bool markedForFines();
	bool markForFines();
	virtual bool isMining();
	virtual void interpretAIMessage(const std::string &ms);
	BoundingBox findBoundingBoxRelativeTo(Entity *other, Vector _i, Vector _j, Vector _k);
	void spawn(const std::string &roles_number);
	int checkShipsInVicinityForWitchJumpExit();
	bool getTrackCloseContacts();
	void setTrackCloseContacts(bool value);
#if OO_SALVAGE_SUPPORT
	void claimAsSalvage();
	void sendCoordinatesToPilot();
#endif

	// Slice 34: salvage pilot, debug dump, script info, demo ship, script events and AI reactions, alert condition, shader helpers.
#if OO_SALVAGE_SUPPORT
	void pilotArrived();
#endif
#ifndef NDEBUG
	void dumpSelfState() override;
#endif
	::OOScript *getScript();
	oo::PList getScriptInfo();
	void overrideScriptInfo(const oo::PList &override);
	Entity *entityForShaderProperties();	// C++ since bead oo-9ht.39.23
	void setDemoShip(OOScalar rate);
	bool getIsDemoShip();
	void setDemoStartTime(OOTimeAbsolute time);
	OOTimeAbsolute getDemoStartTime();
	virtual void doScriptEvent(ooscript::PropertyId message);
	void doScriptEvent(ooscript::PropertyId message, Entity *argument);	// the entity's JS value, as its object's (bead oo-9ht.39.16)
	void doScriptEvent(ooscript::PropertyId message, Entity *argument1, Entity *argument2);
	virtual void doScriptEvent(ooscript::PropertyId message, const std::vector<oo::PList> &arguments);
	void doScriptEvent(ooscript::PropertyId message, ooscript::Value *argv, unsigned argc);
	virtual void doScriptEvent(ooscript::PropertyId message, ooscript::Context context, ooscript::Value *argv, unsigned argc);
	void reactToAIMessage(const std::string &message, const std::optional<std::string> &debugContext);
	void sendAIMessage(const std::string &message);
	void doScriptEvent(ooscript::PropertyId scriptEvent, const std::string &aiMessage);
	void doScriptEvent(ooscript::PropertyId scriptEvent, Entity *argument, const std::string &aiMessage);
	virtual OOAlertCondition alertCondition();
	virtual OOAlertCondition realAlertCondition();
	void doNothing();
#ifndef NDEBUG
	std::optional<std::string> descriptionForObjDump() override;
#endif

	// Category ScriptMethods (ShipEntityScriptMethods.mm, bead oo-42dr): methods for use by scripting mechanisms.
	// std::nullopt ejects nothing, as nil did (proposed ADR-0043, bead oo-tm7d).
	::ShipEntity *ejectShipOfType(const std::optional<std::string> &shipKey);	// Note: ship type, not role.
	::ShipEntity *ejectShipOfRole(const std::optional<std::string> &role);
	std::vector<oo::EntityHold> spawnShipsWithRole(const std::string &role, NSUInteger count);

	// Category LoadRestore (ShipEntityLoadRestore.mm, bead oo-kw44): saving and restoring individual
	// non-player ships. The context (nullptr for none) synchronises the groups of ships saved together.
	oo::PList savedShipDictionaryWithContext(OOShipSaveContext *context);
	static ::ShipEntity *shipRestoredFromDictionary(const oo::PList &dictionary, bool fallback, OOShipSaveContext *context);	// autoreleased; nil if it can't
	void simplifyShipdata(oo::PList::Dict &data, std::vector<std::string> *deletes);	// the file's private category LoadRestoreInternal

	// ShipEntityAI.mm slice 1: AI category, OOAIPrivate (ship and station) and the station stubs.
	void setAITo(const std::string &aiString);
	void setAIScript(const std::string &aiString);
	void switchAITo(const std::string &aiString);
	void scanForHostiles();
	void groupAttackTarget();
	void performAttack();
	void performCollect();
	void performEscort();
	void performFaceDestination();
	void performFlee();
	void performFlyToRangeFromDestination();
	void performHold();
	void performIdle();
	void performIntercept();
	void performLandOnPlanet();
	void performMining();
	void performScriptedAI();
	void performScriptedAttackAI();
	void performBuoyTumble();
	void performStop();
	void performTumble();
	bool performHyperSpaceToSpecificSystem(OOSystemID systemID);
	void requestDockingCoordinates();
	void recallDockingInstructions();
	void scanForNearestIncomingMissile();
	void enterPlayerWormhole();
	void enterTargetWormhole();
	void wormholeEscorts();
	void wormholeEntireGroup();
	bool suggestEscortTo(::ShipEntity *mother);
	void broadcastDistressMessage();
	void broadcastDistressMessageWithDumping(bool dumpCargo);
	void checkFoundTarget();
	bool performHyperSpaceExitReplace(bool replace);
	bool performHyperSpaceExitReplace(bool replace, OOSystemID systemID);
	void scanForNearestShipWithPredicate(EntityFilterPredicate predicate, void *parameter);
	void scanForNearestShipWithNegatedPredicate(EntityFilterPredicate predicate, void *parameter);
	virtual void acceptDistressMessageFrom(::ShipEntity *other);
	// ShipEntityAI.mm slice 1: the category OOAIStationStubs (StationEntity's ObjC methods answer for a station).
	void increaseAlertLevel();
	void decreaseAlertLevel();
	oo::PList launchPolice();
	void launchDefenseShip();
	void launchScavenger();
	void launchMiner();
	void launchPirateShip();
	void launchShuttle();
	void launchTrader();
	void launchEscort();
	bool launchPatrol();
	void launchShipWithRole(const std::string &param);
	void abortAllDockings();

	// ShipEntityAI.mm slice 2: PureAI part 1: state, speed, scans for prey and loot, planets, legal status.
	void setStateTo(const std::string &state);
	void pauseAI(const std::string &intervalString);
	void randomPauseAI(const std::string &intervalString);
	void dropMessages(const std::string &messageString);
	void debugDumpPendingMessages();
	void setDestinationToCurrentLocation();
	void setDestinationToJinkPosition();
	void setDesiredRangeTo(const std::string &rangeString);
	void setDesiredRangeForWaypoint();
	void setSpeedTo(const std::string &speedString);
	void setSpeedFactorTo(const std::string &speedString);
	void setSpeedToCruiseSpeed();
	void setThrustFactorTo(const std::string &thrustFactorString);
	void setTargetToPrimaryAggressor();
	void addPrimaryAggressorAsDefenseTarget();
	void scanForNearestMerchantman();
	void scanForRandomMerchantman();
	void scanForLoot();
	void scanForRandomLoot();
	void setTargetToFoundTarget();
	void addFoundTargetAsDefenseTarget();
	void checkForFullHold();
	void getWitchspaceEntryCoordinates();
	void setDestinationFromCoordinates();
	void setCoordinatesFromPosition();
	void fightOrFleeMissile();
	void setCourseToPlanet();
	void setTakeOffFromPlanet();
	void landOnPlanet();
	void checkTargetLegalStatus();
	void checkOwnLegalStatus();
	void exitAIWithMessage(const std::string &message);
	void setDestinationToTarget();
	void setDestinationWithinTarget();
	void checkCourseToDestination();

	// ShipEntityAI.mm slice 3: PureAI part 2: checks, comms, Thargoids, escorts, patrols, target marking.
	void checkAegis();
	void checkEnergy();
	void checkHeatInsulation();
	void findNewDefenseTarget();
	void scanForOffenders();
	void setCourseToWitchpoint();
	void setDestinationToWitchpoint();
	void setDestinationToStationBeacon();
	void performHyperSpaceExit();
	void performHyperSpaceExitWithoutReplacing();
	virtual void disengageAutopilot();
	void wormholeGroup();
	virtual void commsMessage(const std::string &valueString);
	virtual void commsMessageByUnpiloted(const std::string &valueString);
	void ejectCargo();
	void scanForThargoid();
	void scanForNonThargoid();
	void thargonCheckMother();
	void becomeUncontrolledThargon();
	void checkDistanceTravelled();
	void fightOrFleeHostiles();
	void suggestEscort();
	void escortCheckMother();
	void checkGroupOddsVersusTarget();
	void scanForFormationLeader();
	void messageMother(const std::string &msgString);
	void messageSelf(const std::string &msgString);
	void setPlanetPatrolCoordinates();
	void setSunSkimStartCoordinates();
	void setSunSkimEndCoordinates();
	void setSunSkimExitCoordinates();
	void patrolReportIn();
	void checkForMotherStation();
	void sendTargetCommsMessage(const std::string &message);
	void markTargetForFines();
	void markTargetForOffence(const std::string &valueString);
	void storeTarget();

	// ShipEntityAI.mm slice 4: PureAI part 3: stored targets, nearest-ship scans, stations, script actions, beacons.
	void recallStoredTarget();
	void scanForRocks();
	void setDestinationToDockingAbort();
	void requestNewTarget();
	void rollD(const std::string &die_number);
	void scanForNearestShipWithPrimaryRole(const std::string &scanRole);
	void scanForNearestShipHavingRole(const std::string &scanRole);
	void scanForNearestShipWithAnyPrimaryRole(const std::string &scanRoles);
	void scanForNearestShipHavingAnyRole(const std::string &scanRoles);
	void scanForNearestShipWithScanClass(const std::string &scanScanClass);
	void scanForNearestShipWithoutPrimaryRole(const std::string &scanRole);
	void scanForNearestShipNotHavingRole(const std::string &scanRole);
	void scanForNearestShipWithoutAnyPrimaryRole(const std::string &scanRoles);
	void scanForNearestShipNotHavingAnyRole(const std::string &scanRoles);
	void scanForNearestShipWithoutScanClass(const std::string &scanScanClass);
	void scanForNearestShipMatchingPredicate(const std::string &predicateExpression);
	void setCoordinates(const std::string &system_x_y_z);
	void checkForNormalSpace();
	void setTargetToRandomStation();
	void setTargetToLastStation();
	void addFuel(const std::string &fuel_number);
	void scriptActionOnTarget(const std::string &action);
	void safeScriptActionOnTarget(const std::string &action);
	void sendScriptMessage(const std::string &message);
	void ai_throwSparks();
	void explodeSelf();
	void ai_debugMessage(const std::string &message);
	void targetFirstBeaconWithCode(const std::string &code);
	void targetNextBeaconWithCode(const std::string &code);
	void setRacepointsFromTarget();
	void performFlyRacepoints();

	// @public in Objective-C
	// derived variables
	OOTimeDelta				shot_time = {};					// time elapsed since last shot was fired
	
	// navigation
	Vector					v_forward = {}, v_up = {}, v_right = {};	// unit vectors derived from the direction faced
	
	// variables which are controlled by AI
	HPVector				_destination = {};				// for flying to/from a set point

	GLfloat					desired_range = {};				// range to which to journey/scan
	GLfloat					desired_speed = {};				// speed at which to travel
	// next three used to set desired attitude, flightRoll etc. gradually catch up to target
	GLfloat					stick_roll = {};					// stick roll
	GLfloat					stick_pitch = {};				// stick pitch
	GLfloat					stick_yaw = {};					// stick yaw
	OOBehaviour				behaviour = {};					// ship's behavioural state
	
	BoundingBox				totalBoundingBox = {};			// records ship configuration
	
	// @protected in Objective-C: public while Objective-C subclasses read them
	//set-up
	oo::PList				shipinfoDictionary;	// null: not set up from a dictionary
	
	Quaternion				subentityRotationalVelocity = {};
	
	//scripting
	oo::Ref<OOScript> script;
	oo::Ref<OOScript> aiScript;
	OOTimeAbsolute    aiScriptWakeTime = {};
	
	//docking instructions
	oo::PList				dockingInstructions;		// null: none (was nil); the station is an Object node (a weak reference)
	
	oo::Ref<OOColor>			laser_color;
	oo::Ref<OOColor>			default_laser_color;
	oo::Ref<OOColor>			exhaust_emissive_color;
	oo::Ref<OOColor>			scanner_display_color1;
	oo::Ref<OOColor>			scanner_display_color2;
	oo::Ref<OOColor>			scanner_display_color_hostile1;
	oo::Ref<OOColor>			scanner_display_color_hostile2;
	
	// per ship-type variables
	//
	GLfloat					maxFlightSpeed = {};				// top speed			(160.0 for player)  (200.0 for fast raider)
	GLfloat					max_flight_roll = {};			// maximum roll rate	(2.0 for player)	(3.0 for fast raider)
	GLfloat					max_flight_pitch = {};			// maximum pitch rate   (1.0 for player)	(1.5 for fast raider) also radians/sec for (* turrets *)
	GLfloat					max_flight_yaw = {};
	GLfloat					cruiseSpeed = {};				// 80% of top speed
	
	GLfloat					max_thrust = {};					// acceleration
	GLfloat					thrust = {};						// acceleration
	float					hyperspaceMotorSpinTime = {};	// duration of hyperspace countdown
	
	unsigned				military_jammer_active: 1 = 0,	// military_jammer
	
							docking_match_rotation: 1 = 0,
	
							pitching_over: 1 = 0,			// set to YES if executing a sharp loop
							rolling_over: 1 = 0,			// set to YES if executing a sharp roll
							reportAIMessages: 1 = 0,		// normally NO, suppressing AI message reporting
	
							being_mined: 1 = 0,				// normally NO, set to Yes when fired on by mining laser
	
							being_fined: 1 = 0,
	
							isHulk: 1 = 0,					// This is used to distinguish abandoned ships from cargo
							trackCloseContacts: 1 = 0,
							isNearPlanetSurface: 1 = 0,		// check for landing on planet
							isFrangible: 1 = 0,				// frangible => subEntities can be damaged individually
							cloaking_device_active: 1 = 0,	// cloaking_device
							cloakPassive: 1 = 0,			// cloak deactivates when main weapons or missiles are fired
							cloakAutomatic: 1 = 0,			// cloak activates itself automatic during attack
							canFragment: 1 = 0,				// Can it break into wreckage?
							isWreckage: 1 = 0,              // Is it wreckage?
							_showDamage: 1 = 0,             // Show damage?
							suppressExplosion: 1 = 0,		// Avoid exploding on death (script hook)
							suppressAegisMessages: 1 = 0,	// No script/AI messages sent by -checkForAegis,
							isMissile: 1 = 0,				// Whether this was launched by fireMissile (used to track submunitions).
							_explicitlyUnpiloted: 1 = 0,	// Is meant to not have crew
							hasScoopMessage: 1 = 0,			// suppress scoop messages when false.
							
							// scripting
							scripted_misjump: 1 = 0,
							haveExecutedSpawnAction: 1 = 0,
							haveStartedJSAI: 1 = 0,
							noRocks: 1 = 0,
							_lightsActive: 1 = 0;

	GLfloat    _scriptedMisjumpRange = {}; 
	
	GLfloat		sunGlareFilter = {};							// Range 0.0 - 1.0, where 0 means no sun glare filter, 1 means glare fully filtered
	
	OOFuelQuantity			fuel = {};						// witch-space fuel
	GLfloat					fuel_accumulator = {};
	
	GLfloat					afterburner_rate = {};
	GLfloat					afterburner_speed_factor = {};

	OOCargoQuantity			likely_cargo = {};				// likely amount of cargo (for pirates, this is what is spilled as loot)
	OOCargoQuantity			max_cargo = {};					// capacity of cargo hold
	OOCargoQuantity			extra_cargo = {};				// capacity of cargo hold extension (if any)
	OOCargoQuantity			equipment_weight = {};			// amount of equipment using cargo space (excluding passenger_berth & extra_cargo_bay)
	OOCargoType				cargo_type = {};					// if this is scooped, this is indicates contents
	OOCargoFlag				cargo_flag = {};					// indicates contents for merchantmen
	OOCreditsQuantity		bounty = {};						// bounty (if any)
	
	GLfloat					energy_recharge_rate = {};		// recharge rate for energy banks
	
	OOWeaponFacingSet		weapon_facings = {};				// weapon mounts available (bitmask)
	OOWeaponType			forward_weapon_type = {};		// type of forward weapon (allows lasers, plasma cannon, others)
	OOWeaponType			aft_weapon_type = {};			// type of aft weapon (allows lasers, plasma cannon, others)
	OOWeaponType			port_weapon_type = {};			// type of port weapon
	OOWeaponType			starboard_weapon_type = {};			// type of starboard weapon
	GLfloat					weapon_damage = {};				// energy damage dealt by weapon
	GLfloat					weapon_damage_override = {};		// custom energy damage dealt by front laser, if applicable
	GLfloat					weaponRange = {};				// range of the weapon (in meters)
	OOWeaponFacing			currentWeaponFacing = {};		// not necessarily the same as view for the player
	
	GLfloat					weapon_energy_use = {}, weapon_temp = {}, weapon_shot_temperature = {}; // active weapon temp, delta-temp
	GLfloat					forward_weapon_temp = {}, aft_weapon_temp = {}, port_weapon_temp = {}, starboard_weapon_temp = {}; // current weapon temperatures

	GLfloat					scannerRange = {};				// typically 25600
	
	unsigned				missiles = {};					// number of on-board missiles
	unsigned				max_missiles = {};				// number of missile pylons
	std::optional<std::string>	_missileRole;	// nullopt: no missile_role (the generic fallback)
	OOTimeDelta				missile_load_time = {};			// minimum time interval between missile launches
	OOTimeAbsolute			missile_launch_time = {};		// time of last missile launch
	
	oo::Ref<::AI>				shipAI = {};					// ship's AI system
	
	std::optional<std::string>	name;					// descriptive name; nullopt: nil
	std::optional<std::string>	shipUniqueName;			// uniqish name e.g. "Terror of Lave"; nullopt: nil
	std::optional<std::string>	shipClassName;			// e.g. "Cobra III"; nullopt: nil
	std::optional<std::string>	displayName;			// name shown on screen; nullopt: nil
	std::optional<std::string>	scan_description;		// scan class name; nullopt: nil
	oo::Ref<::OORoleSet>		roleSet;					// Roles a ship can take, eg. trader, hunter, police, pirate, scavenger &c.
	std::optional<std::string>	primaryRole;			// "Main" role of the ship; nullopt: not chosen yet

	oo::PList				explosionType;				// explosion.plist entries; null: absent
	
	// AI stuff
	Vector					jink = {};						// x and y set factors for offsetting a pursuing ship's position
	HPVector					coordinates = {};				// for flying to/from a set point
	Vector					reference = {};					// a direction vector of magnitude 1 (* turrets *)
	
	NSUInteger				_subIdx = {};					// serialisation index - used only if this ship is a subentity
	NSUInteger				_maxShipSubIdx = {};				// serialisation index - the number of ship subentities inside the shipdata
	double					launch_time = {};				// time at which launched
	double					launch_delay = {};				// delay for thinking after launch
	OOUniversalID			planetForLanding = {};			// for landing
	
	GLfloat					frustration = {},				// degree of dissatisfaction with the current behavioural state, factor used to test this
	success_factor = {};
	
	int						patrol_counter = {};				// keeps track of where the ship is along a patrol route
	
	oo::PList				previousCondition;			// restored after collision avoidance; null: none
	
	// derived variables
	float					weapon_recharge_rate = {};		// time between shots
	int						shot_counter = {};				// number of shots fired
	OOTimeAbsolute			cargo_dump_time = {};			// time cargo was last dumped
	OOTimeAbsolute			last_shot_time = {};				// time shot was last fired
	
	std::vector<oo::EntityHold>	cargo;	// cargo containers go in here (index 0 is the eject position); edited in place through -cxx_cargo
	
	std::optional<std::string>	commodity_type;			// type of commodity in a container; nullopt: not a pod (was nil)
	OOCargoQuantity			commodity_amount = {};			// 1 if unit is TONNES (0), possibly more if precious metals KILOGRAMS (1)
	// or gem stones GRAMS (2)
	
	// navigation
	GLfloat					flightSpeed = {};				// current speed
	GLfloat					flightRoll = {};					// current roll rate
	GLfloat					flightPitch = {};				// current pitch rate
	GLfloat					flightYaw = {};					// current yaw rate
	
	GLfloat					accuracy = {};
	GLfloat					pitch_tolerance = {};
	GLfloat					aim_tolerance = {};
	int					_missed_shots = {};
	
	OOAegisStatus			aegis_status = {};				// set to YES when within the station's protective zone
	OOSystemID				home_system = {}; 
	OOSystemID				destination_system = {}; 
	
	double					messageTime = {};				// counts down the seconds a radio message is active for
	
	double					next_spark_time = {};			// time of next spark when throwing sparks
	
	Vector					collision_vector = {};			// direction of colliding thing.
	
	GLfloat					_scaleFactor = {};  // scale factor for size variation


	BOOL					_multiplyWeapons = {}; // multiply instead of splitting weapons
	//position of gun ports
	std::vector<Vector>		forwardWeaponOffset,
							aftWeaponOffset,
							portWeaponOffset,
							starboardWeaponOffset;
	
	// crew (typically one OOCharacter - the pilot); nullopt: unpiloted (was nil); an empty vector is crewed
	std::optional<std::vector<oo::Ref<OOCharacter>>>	crew;
	
	// close contact / collision tracking
	std::map<std::string, std::string, std::less<>>	closeContactsInfo;	// "%d" universal ID -> "%f %f %f" relative position
	
	std::optional<std::string>	lastRadioMessage;	// nullopt: none yet
	
	// scooping...
	Vector					tractor_position = {};
	
	// from player entity moved here now we're doing more complex heat stuff
	float					ship_temperature = {};
	
	// for advanced scanning etc.
	::ShipEntity				*scanned_ships[MAX_SCAN_NUMBER + 1] = {};
	GLfloat					distance2_scanned_ships[MAX_SCAN_NUMBER + 1] = {};
	unsigned				n_scanned_ships = {};
	
	// advanced navigation
	HPVector					navpoints[32] = {};
	unsigned				next_navpoint_index = {};
	unsigned				number_of_navpoints = {};
	
	// Collision detection
	oo::Ref<Octree>				octree;
	
#ifndef NDEBUG
	// DEBUGGING
	OOBehaviour				debugLastBehaviour = {};
#endif
	
	uint16_t				entity_personality = {};			// Per-entity random number. Exposed to shaders and scripts.
	oo::PList				scriptInfo;				// script_info dictionary from shipdata.plist, exposed to scripts; null: none
	
	std::vector<oo::EntityHold>	subEntities;	// empty == none (was nil)
	::OOEquipmentType			*missile_list[SHIPENTITY_MAX_MISSILES] = {};

	// various types of target
	oo::WeakRef<Entity>		_primaryTarget;			// for combat or rendezvous
	oo::WeakRef<Entity>		_primaryAggressor;			// recorded after attack
	oo::WeakRef<Entity>		_targetStation;			// for docking
	oo::WeakRef<Entity>		_foundTarget;				// from scans
	oo::WeakRef<Entity>		_lastEscortTarget;			// last target an escort was deployed after
	oo::WeakRef<Entity>		_thankedShip;				// last ship thanked
	oo::WeakRef<Entity>		_rememberedShip;			// ship being remembered
	oo::WeakRef<Entity>		_proximityAlert;			// a ShipEntity within 2x collision_radius
	
	// Stuff for the target tracking curve.  The ship records the position of the target every reactionTime/2 seconds, then fits a curve to the
	// last three recorded positions.  Instead of tracking the primary target's actual position it uses the curve to calculate the target's position.
	// This introduces a small amount of lag to the target tracking making the NPC more human.
	float				reactionTime = {};
	HPVector			trackingCurvePositions[4] = {};
	OOTimeAbsolute			trackingCurveTimes[4] = {};
	HPVector			trackingCurveCoeffs[3] = {};
	

	
	// @private in Objective-C, private again in C++ (bead oo-9ht.184, ADR-0056 amendment
	// oo-9ht.184) in declaration order, so construction and destruction order are unchanged. The
	// unit tests read the ones they need through ShipEntityTestAccess (bead oo-9ht.184.1).
	friend struct ::ShipEntityTestAccess;
private:
	oo::WeakRef<Entity>		_subEntityTakingDamage;	//	frangible => subEntities can be damaged individually

	std::optional<std::string>	_shipKey;				// nullopt: nil
	
	std::vector<std::string>	_equipment;	// equipment keys, in order added; empty == none (was nil)
	float					_heatInsulation = {};
	
private:
	oo::WeakRef<Entity>		_lastAegisLock;			// remember last aegis planet/sun
	
	oo::Ref<::OOShipGroup>		_group;			// C++ since bead oo-9ht.19
private:
	oo::Ref<::OOShipGroup>		_escortGroup;
	uint8_t					_maxEscortCount = {};
	uint8_t					_pendingEscortCount = {};
private:
	// Cache of ship-relative positions, managed by -coordinatesForEscortPosition:.
	Vector					_escortPositions[MAX_ESCORTS] = {};
	BOOL					_escortPositionsValid = {};
	
private:
	// The ships' C++ parts, held weakly (OOWeakSets of their objects until bead oo-9ht.22.3)
	oo::WeakSet<Entity>	_defenseTargets = {};			 // defense targets
	
	// ships in this set can't be collided with
	oo::WeakSet<Entity>	_collisionExceptions = {};

	GLfloat					_profileRadius = {};
	
private:
	oo::WeakRef<Entity>		_shipHitByLaser;			// entity hit by the last laser shot
	
	// beacons
	std::optional<std::string>	_beaconCode;			// nullopt: nil (never empty)
	std::optional<std::string>	_beaconLabel;			// nullopt: nil (never empty)
	oo::WeakRef<Entity>		_prevBeacon;
	oo::WeakRef<Entity>		_nextBeacon;
	oo::Ref<OOHUDBeaconIcon>	_beaconDrawable;

	double			_nextAegisCheck = {};

	// Demo ship state
	BOOL			isDemoShip = {};
	OOScalar		demoRate = {};
private:
	OOTimeAbsolute		demoStartTime = {};
	Quaternion		demoStartOrientation = {};
};


/*	Script events with raw JS values, for example:
	ShipScriptEventNoCx(ship, "doSomething", ooscript::int32Value(42));
	The ship is the C++ ship; a null ship sends nothing, as the message to nil did (moved from the
	deleted facade's header, bead oo-9ht.144).
*/
#define ShipScriptEvent(context, ship, event, ...) do { ooscript::Value argv[] = { __VA_ARGS__ }; unsigned argc = sizeof argv / sizeof *argv; if (ShipEntity *ooScriptEventShip_ = (ship))  ooScriptEventShip_->doScriptEvent(OOJSID(event), context, argv, argc); } while (0)

#define ShipScriptEventNoCx(ship, event, ...) do { ooscript::Value argv[] = { __VA_ARGS__ }; unsigned argc = sizeof argv / sizeof *argv; if (ShipEntity *ooScriptEventShip_ = (ship))  ooScriptEventShip_->doScriptEvent(OOJSID(event), argv, argc); } while (0)


Vector cxx_positionOffsetForShipInRotationToAlignment(ShipEntity *ship, Quaternion q, const std::string &align);


namespace oo {

/*	A ship made in C++ (beads oo-9ht.183, oo-9ht.144; ADR-0056 amendments oo-9ht.183 and
	oo-9ht.144): made as its object was (oo::MadeEntityRetained(): it has its object and is counted;
	bead oo-dpyk8), set up from the definition as -cxx_initWithKey:definition: set up a ship;
	retained (+1), as +alloc/-init's object was, or null when the set-up fails (the failing
	initialiser released it).
*/
ShipEntity *NewShipObject(const Ref<ShipEntity> &ship, const std::string &key, const oo::PList &dict);

// The ship an entity is: nullptr for null or another entity (what -isKindOfClass:[ShipEntity class]
// and the cast after it found; the object overloads went with the facade, bead oo-dpyk8).
inline ShipEntity *ToShip(Entity *entity)
{
	return dynamic_cast<ShipEntity *>(entity);
}

}	// namespace oo


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
std::optional<std::string> cxx_OOEquipmentIdentifierFromWeaponType(OOWeaponType weapon);	// nullopt: no weapon
OOWeaponType cxx_OOWeaponTypeFromEquipmentIdentifierSloppy(const std::string &string);	// Uses suffix match for backwards compatibility.
OOWeaponType cxx_OOWeaponTypeFromEquipmentIdentifierStrict(const std::string &string);
OOWeaponType cxx_OOWeaponTypeFromEquipmentIdentifierLegacy(const std::string &string);
std::optional<std::string> cxx_OOStringFromWeaponType(OOWeaponType weapon);
OOWeaponType cxx_OOWeaponTypeFromString(const std::string &string);
std::optional<std::string> cxx_OODisplayStringFromAlertCondition(OOAlertCondition alertCondition);

