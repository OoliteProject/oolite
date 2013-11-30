/*

OOJSShip.m

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

#import "OOJSShip.h"
#import "OOJSEntity.h"
#import "OOJSWormhole.h"
#import "OOJSVector.h"
#import "OOJSEquipmentInfo.h"
#import "OOJavaScriptEngine.h"
#import "ShipEntity.h"
#import "ShipEntityAI.h"
#import "ShipEntityScriptMethods.h"
#import "StationEntity.h"
#import "WormholeEntity.h"
#import "AI.h"
#import "OOStringParsing.h"
#import "EntityOOJavaScriptExtensions.h"
#import "OORoleSet.h"
#import "OOJSPlayer.h"
#import "PlayerEntity.h"
#import "PlayerEntityScriptMethods.h"
#import "OOShipGroup.h"
#import "OOShipRegistry.h"
#import "OOEquipmentType.h"
#import "ResourceManager.h"
#import "OOCollectionExtractors.h"
#import "OOMesh.h"
#import "OOConstToString.h"
#import "OOEntityFilterPredicate.h"


static JSObject *sShipPrototype;


static JSBool ShipGetProperty(JSContext *context, JSObject *this, jsid propID, jsval *value);
static JSBool ShipSetProperty(JSContext *context, JSObject *this, jsid propID, JSBool strict, jsval *value);

static JSBool ShipSetScript(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipSetAI(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipSwitchAI(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipExitAI(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipReactToAIMessage(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipSendAIMessage(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipDeployEscorts(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipDockEscorts(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipHasRole(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipEjectItem(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipEjectSpecificItem(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipDumpCargo(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipSpawn(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipDealEnergyDamage(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipExplode(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipRemove(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipRunLegacyScriptActions(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipCommsMessage(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipFireECM(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipAbandonShip(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipCanAwardEquipment(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipAwardEquipment(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipRequestHelpFromGroup(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipPatrolReportIn(JSContext *context, uintN argc, jsval *vp);

static JSBool ShipRemoveEquipment(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipRestoreSubEntities(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipEquipmentStatus(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipSetEquipmentStatus(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipSelectNewMissile(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipFireMissile(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipFindNearestStation(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipSetBounty(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipSetCargo(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipSetMaterials(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipSetShaders(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipExitSystem(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipUpdateEscortFormation(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipClearDefenseTargets(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipAddDefenseTarget(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipRemoveDefenseTarget(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipGetMaterials(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipGetShaders(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipBecomeCascadeExplosion(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipBroadcastCascadeImminent(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipBroadcastDistressMessage(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipOfferToEscort(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipMarkTargetForFines(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipEnterWormhole(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipNotifyGroupOfWormhole(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipThrowSpark(JSContext *context, uintN argc, jsval *vp);

static JSBool ShipPerformAttack(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipPerformCollect(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipPerformEscort(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipPerformFaceDestination(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipPerformFlee(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipPerformFlyToRangeFromDestination(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipPerformHold(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipPerformIdle(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipPerformIntercept(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipPerformLandOnPlanet(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipPerformMining(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipPerformScriptedAI(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipPerformScriptedAttackAI(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipPerformStop(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipPerformTumble(JSContext *context, uintN argc, jsval *vp);

static JSBool ShipRequestDockingInstructions(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipRecallDockingInstructions(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipCheckCourseToDestination(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipGetSafeCourseToDestination(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipCheckScanner(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipThreatAssessment(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipDamageAssessment(JSContext *context, uintN argc, jsval *vp);
static double ShipThreatAssessmentWeapon(OOWeaponType wt);

static JSBool ShipSetCargoType(JSContext *context, uintN argc, jsval *vp);

static BOOL RemoveOrExplodeShip(JSContext *context, uintN argc, jsval *vp, BOOL explode);
static JSBool ShipSetMaterialsInternal(JSContext *context, uintN argc, jsval *vp, ShipEntity *thisEnt, BOOL fromShaders);

static JSBool ShipStaticKeysForRole(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipStaticKeys(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipStaticRoles(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipStaticRoleIsInCategory(JSContext *context, uintN argc, jsval *vp);


static JSClass sShipClass =
{
	"Ship",
	JSCLASS_HAS_PRIVATE,
	
	JS_PropertyStub,		// addProperty
	JS_PropertyStub,		// delProperty
	ShipGetProperty,		// getProperty
	ShipSetProperty,		// setProperty
	JS_EnumerateStub,		// enumerate
	JS_ResolveStub,			// resolve
	JS_ConvertStub,			// convert
	OOJSObjectWrapperFinalize,// finalize
	JSCLASS_NO_OPTIONAL_MEMBERS
};


/* It turns out that the value in SpiderMonkey used to identify these
 * enums is an 8-bit signed int:
 * developer.mozilla.org/en/docs/SpiderMonkey/JSAPI_Reference/JSPropertySpec
 * which puts a limit of 256 properties on the ship object.  Moved the
 * enum to start at -128, so we can use the full 256 rather than just
 * 128 of them. I don't think any of our other classes are getting
 * close to the limit yet.
 * - CIM 29/9/2013
 */
enum
{
	// Property IDs
	kShip_accuracy = -128,		// the ship's accuracy, float, read/write
	kShip_aftWeapon,			// the ship's aft weapon, equipmentType, read/write
	kShip_AI,					// AI state machine name, string, read-only
	kShip_AIScript,				// AI script, Script, read-only
	kShip_AIScriptWakeTime,				// next wakeup time, integer, read/write
	kShip_AIState,				// AI state machine state, string, read/write
	kShip_AIFoundTarget,		// AI "found target", entity, read/write
	kShip_AIPrimaryAggressor,	// AI "primary aggressor", entity, read/write
	kShip_alertCondition,		// number 0-3, read-only, combat alert level
	kShip_autoAI,				// bool, read-only, auto_ai from shipdata
	kShip_autoWeapons,			// bool, read-only, auto_weapons from shipdata
	kShip_beaconCode,			// beacon code, string, read/write
	kShip_beaconLabel,			// beacon label, string, read/write
	kShip_boundingBox,			// boundingBox, vector, read-only
	kShip_bounty,				// bounty, unsigned int, read/write
	kShip_cargoList,		// cargo on board, array of objects, read-only
	kShip_cargoSpaceAvailable,	// free cargo space, integer, read-only
	kShip_cargoSpaceCapacity,	// maximum cargo, integer, read-only
	kShip_cargoSpaceUsed,		// cargo on board, integer, read-only
	kShip_contracts,			// cargo contracts contracts, array - strings & whatnot, read only
	kShip_commodity,			// commodity of a ship, read only
	kShip_commodityAmount,		// commodityAmount of a ship, read only
	kShip_cloakAutomatic,		// should cloack start by itself or by script, read/write
	kShip_cruiseSpeed,			// desired cruising speed, number, read only
	kShip_currentWeapon,		// the ship's active weapon, equipmentType, read/write
	kShip_dataKey,				// string, read-only, shipdata.plist key
	kShip_defenseTargets,		// array, read-only, defense targets
	kShip_desiredRange,			// desired Range, double, read/write
	kShip_desiredSpeed,			// AI desired flight speed, double, read/write
	kShip_destination,			// flight destination, Vector, read/write
	kShip_destinationSystem,	// destination system, number, read/write
	kShip_displayName,			// name displayed on screen, string, read/write
	kShip_dockingInstructions,			// name displayed on screen, string, read/write
	kShip_energyRechargeRate,	// energy recharge rate, float, read-only
	kShip_entityPersonality,	// per-ship random number, int, read-only
	kShip_equipment,			// the ship's equipment, array of EquipmentInfo, read only
	kShip_escortGroup,			// group, ShipGroup, read-only
	kShip_escorts,				// deployed escorts, array of Ship, read-only
	kShip_exhaustEmissiveColor,	// exhaust emissive color, array, read/write
	kShip_exhausts,				// exhausts, array, read-only
	kShip_extraCargo,				// cargo space increase granted by large cargo bay, int, read-only
	kShip_flashers,				// flashers, array, read-only
	kShip_forwardWeapon,		// the ship's forward weapon, equipmentType, read/write
	kShip_fuel,					// fuel, float, read/write
	kShip_fuelChargeRate,		// fuel scoop rate & charge multiplier, float, read-only
	kShip_group,				// group, ShipGroup, read/write
	kShip_hasHostileTarget,		// has hostile target, boolean, read-only
	kShip_hasHyperspaceMotor,	// has hyperspace motor, boolean, read-only
	kShip_hasSuspendedAI,		// AI has suspended states, boolean, read-only
	kShip_heading,				// forwardVector of a ship, read-only
	kShip_heatInsulation,		// hull heat insulation, double, read/write
	kShip_homeSystem,			// home system, number, read/write
	kShip_isBeacon,				// is beacon, boolean, read-only
	kShip_isBoulder,			// is a boulder (generates splinters), boolean, read/write
	kShip_isCargo,				// contains cargo, boolean, read-only
	kShip_isCloaked,			// cloaked, boolean, read/write (if cloaking device installed)
	kShip_isDerelict,			// is an abandoned ship, boolean, read-only
	kShip_isFrangible,			// frangible, boolean, read-only
	kShip_isFleeing,			// is fleeing, boolean, read-only
	kShip_isJamming,			// jamming scanners, boolean, read/write (if jammer installed)
	kShip_isMine,				// is mine, boolean, read-only
	kShip_isMissile,			// is missile, boolean, read-only
	kShip_isPiloted,			// is piloted, boolean, read-only (includes stations)
	kShip_isPirate,				// is pirate, boolean, read-only
	kShip_isPirateVictim,		// is pirate victim, boolean, read-only
	kShip_isPolice,				// is police, boolean, read-only
	kShip_isRock,				// is a rock (hermits included), boolean, read-only
	kShip_isThargoid,			// is thargoid, boolean, read-only
	kShip_isTurret,			    // is turret, boolean, read-only
	kShip_isTrader,				// is trader, boolean, read-only
	kShip_isWeapon,				// is missile or mine, boolean, read-only
	kShip_laserHeatLevel,			// active laser temperature, float, read-only
	kShip_laserHeatLevelAft,		// aft laser temperature, float, read-only
	kShip_laserHeatLevelForward,	// fore laser temperature, float, read-only
	kShip_laserHeatLevelPort,		// port laser temperature, float, read-only
	kShip_laserHeatLevelStarboard,	// starboard laser temperature, float, read-only
	kShip_lightsActive,			// flasher/shader light flag, boolean, read/write
	kShip_markedForFines,   // has been marked for fines
	kShip_maxEscorts,     // maximum escort count, int, read/write
	kShip_maxPitch,				// maximum flight pitch, double, read-only
	kShip_maxSpeed,				// maximum flight speed, double, read-only
	kShip_maxRoll,				// maximum flight roll, double, read-only
	kShip_maxYaw,				// maximum flight yaw, double, read-only
	kShip_maxThrust,			// maximum thrust, double, read-only
	kShip_missileCapacity,		// max missiles capacity, integer, read-only
	kShip_missileLoadTime,		// missile load time, double, read/write
	kShip_missiles,				// the ship's missiles / external storage, array of equipmentTypes, read only
	kShip_name,					// name, string, read-only
	kShip_parcelCount,		// number of parcels on ship, integer, read-only
	kShip_parcels,			// parcel contracts, array - strings & whatnot, read only
	kShip_passengerCapacity,	// amount of passenger space on ship, integer, read-only
	kShip_passengerCount,		// number of passengers on ship, integer, read-only
	kShip_passengers,			// passengers contracts, array - strings & whatnot, read only
	kShip_pitch,				// pitch level, float, read-only
	kShip_portWeapon,			// the ship's port weapon, equipmentType, read/write
	kShip_potentialCollider,	// "proximity alert" ship, Entity, read-only
	kShip_primaryRole,			// Primary role, string, read/write
	kShip_reportAIMessages,		// report AI messages, boolean, read/write
	kShip_roleWeights,			// roles and weights, dictionary, read-only
	kShip_roles,				// roles, array, read-only
	kShip_roll,					// roll level, float, read-only
	kShip_savedCoordinates,		// coordinates in system space for AI use, Vector, read/write
	kShip_scannerDisplayColor1,	// color of lollipop shown on scanner, array, read/write
	kShip_scannerDisplayColor2,	// color of lollipop shown on scanner when flashing, array, read/write
	kShip_scannerRange,			// scanner range, double, read-only
	kShip_script,				// script, Script, read-only
	kShip_scriptedMisjump,		// next jump will miss if set to true, boolean, read/write
	kShip_scriptedMisjumpRange,  // 0..1 range of next misjump, float, read/write
	kShip_scriptInfo,			// arbitrary data for scripts, dictionary, read-only
	kShip_shipClassName,		// ship type name, string, read/write
	kShip_shipUniqueName,		// uniqish name, string, read/write
	kShip_speed,				// current flight speed, double, read-only
	kShip_starboardWeapon,		// the ship's starboard weapon, equipmentType, read/write
	kShip_subEntities,			// subentities, array of Ship, read-only
	kShip_subEntityCapacity,	// max subentities for this ship, int, read-only
	kShip_target,				// target, Ship, read/write
	kShip_temperature,			// hull temperature, double, read/write
	kShip_thrust,				// the ship's thrust, double, read/write
	kShip_thrustVector,			// thrust-related component of velocity, vector, read-only
	kShip_trackCloseContacts,	// generate close contact events, boolean, read/write
	kShip_vectorForward,		// forwardVector of a ship, read-only
	kShip_vectorRight,			// rightVector of a ship, read-only
	kShip_vectorUp,				// upVector of a ship, read-only
	kShip_velocity,				// velocity, vector, read/write
	kShip_weaponFacings,		// available facings, int, read-only
	kShip_weaponPositionAft,	// weapon offset, vector, read-only
	kShip_weaponPositionForward,	// weapon offset, vector, read-only
	kShip_weaponPositionPort,	// weapon offset, vector, read-only
	kShip_weaponPositionStarboard,	// weapon offset, vector, read-only
	kShip_weaponRange,			// weapon range, double, read-only
	kShip_withinStationAegis,	// within main station aegis, boolean, read/write
	kShip_yaw,					// yaw level, float, read-only
};


static JSPropertySpec sShipProperties[] =
{
	// JS name					ID							flags
	{ "accuracy",				kShip_accuracy,				OOJS_PROP_READWRITE_CB },
	{ "aftWeapon",				kShip_aftWeapon,			OOJS_PROP_READWRITE_CB },
	{ "AI",						kShip_AI,					OOJS_PROP_READONLY_CB },
	{ "AIScript",					kShip_AIScript,				OOJS_PROP_READONLY_CB },
	{ "AIScriptWakeTime",					kShip_AIScriptWakeTime,				OOJS_PROP_READWRITE_CB },
	{ "AIState",				kShip_AIState,				OOJS_PROP_READWRITE_CB },
	{ "AIFoundTarget",			kShip_AIFoundTarget,		OOJS_PROP_READWRITE_CB },
	{ "AIPrimaryAggressor",		kShip_AIPrimaryAggressor,	OOJS_PROP_READWRITE_CB },
	{ "alertCondition",			kShip_alertCondition,		OOJS_PROP_READONLY_CB },
	{ "autoAI",					kShip_autoAI,				OOJS_PROP_READONLY_CB },
	{ "autoWeapons",			kShip_autoWeapons,			OOJS_PROP_READONLY_CB },
	{ "beaconCode",				kShip_beaconCode,			OOJS_PROP_READWRITE_CB },
	{ "beaconLabel",			kShip_beaconLabel,			OOJS_PROP_READWRITE_CB },
	{ "boundingBox",			kShip_boundingBox,			OOJS_PROP_READONLY_CB },
	{ "bounty",					kShip_bounty,				OOJS_PROP_READWRITE_CB },
	{ "cargoList",			kShip_cargoList,		OOJS_PROP_READONLY_CB },	
	{ "cargoSpaceUsed",			kShip_cargoSpaceUsed,		OOJS_PROP_READONLY_CB },
	{ "cargoSpaceCapacity",		kShip_cargoSpaceCapacity,	OOJS_PROP_READONLY_CB },
	{ "cargoSpaceAvailable",	kShip_cargoSpaceAvailable,	OOJS_PROP_READONLY_CB },
	{ "commodity",				kShip_commodity,			OOJS_PROP_READONLY_CB },
	{ "commodityAmount",		kShip_commodityAmount,		OOJS_PROP_READONLY_CB },
	// contracts instead of cargo to distinguish them from the manifest
	{ "contracts",				kShip_contracts,			OOJS_PROP_READONLY_CB },
	{ "cloakAutomatic",			kShip_cloakAutomatic,		OOJS_PROP_READWRITE_CB},
	{ "cruiseSpeed",			kShip_cruiseSpeed,			OOJS_PROP_READONLY_CB },
	{ "currentWeapon",			kShip_currentWeapon,		OOJS_PROP_READWRITE_CB },
	{ "dataKey",				kShip_dataKey,				OOJS_PROP_READONLY_CB },
	{ "defenseTargets",			kShip_defenseTargets,		OOJS_PROP_READONLY_CB },
	{ "desiredRange",			kShip_desiredRange,			OOJS_PROP_READWRITE_CB },
	{ "desiredSpeed",			kShip_desiredSpeed,			OOJS_PROP_READWRITE_CB },
	{ "destination",			kShip_destination,			OOJS_PROP_READWRITE_CB },
	{ "destinationSystem",		kShip_destinationSystem,	OOJS_PROP_READWRITE_CB },
	{ "displayName",			kShip_displayName,			OOJS_PROP_READWRITE_CB },
	{ "dockingInstructions",	kShip_dockingInstructions,	OOJS_PROP_READONLY_CB },
	{ "energyRechargeRate",		kShip_energyRechargeRate,	OOJS_PROP_READONLY_CB },
	{ "entityPersonality",		kShip_entityPersonality,	OOJS_PROP_READONLY_CB },
	{ "equipment",				kShip_equipment,			OOJS_PROP_READONLY_CB },
	{ "escorts",				kShip_escorts,				OOJS_PROP_READONLY_CB },
	{ "escortGroup",			kShip_escortGroup,			OOJS_PROP_READONLY_CB },
	{ "exhaustEmissiveColor",	kShip_exhaustEmissiveColor,	OOJS_PROP_READWRITE_CB },
	{ "exhausts",				kShip_exhausts,				OOJS_PROP_READONLY_CB },
	{ "extraCargo",				kShip_extraCargo,			OOJS_PROP_READONLY_CB },
	{ "flashers",				kShip_flashers,				OOJS_PROP_READONLY_CB },
	{ "forwardWeapon",			kShip_forwardWeapon,		OOJS_PROP_READWRITE_CB },
	{ "fuel",					kShip_fuel,					OOJS_PROP_READWRITE_CB },
	{ "fuelChargeRate",			kShip_fuelChargeRate,		OOJS_PROP_READONLY_CB },
	{ "group",					kShip_group,				OOJS_PROP_READWRITE_CB },
	{ "hasHostileTarget",		kShip_hasHostileTarget,		OOJS_PROP_READONLY_CB },
	{ "hasHyperspaceMotor",		kShip_hasHyperspaceMotor,	OOJS_PROP_READONLY_CB },
	{ "hasSuspendedAI",			kShip_hasSuspendedAI,		OOJS_PROP_READONLY_CB },
	{ "heatInsulation",			kShip_heatInsulation,		OOJS_PROP_READWRITE_CB },
	{ "heading",				kShip_heading,				OOJS_PROP_READONLY_CB },
	{ "homeSystem",				kShip_homeSystem,			OOJS_PROP_READWRITE_CB },
	{ "isBeacon",				kShip_isBeacon,				OOJS_PROP_READONLY_CB },
	{ "isCloaked",				kShip_isCloaked,			OOJS_PROP_READWRITE_CB },
	{ "isCargo",				kShip_isCargo,				OOJS_PROP_READONLY_CB },
	{ "isDerelict",				kShip_isDerelict,			OOJS_PROP_READONLY_CB },
	{ "isFrangible",			kShip_isFrangible,			OOJS_PROP_READONLY_CB },
	{ "isFleeing",				kShip_isFleeing,			OOJS_PROP_READONLY_CB },
	{ "isJamming",				kShip_isJamming,			OOJS_PROP_READONLY_CB },
	{ "isMine",					kShip_isMine,				OOJS_PROP_READONLY_CB },
	{ "isMissile",				kShip_isMissile,			OOJS_PROP_READONLY_CB },
	{ "isPiloted",				kShip_isPiloted,			OOJS_PROP_READONLY_CB },
	{ "isPirate",				kShip_isPirate,				OOJS_PROP_READONLY_CB },
	{ "isPirateVictim",			kShip_isPirateVictim,		OOJS_PROP_READONLY_CB },
	{ "isPolice",				kShip_isPolice,				OOJS_PROP_READONLY_CB },
	{ "isRock",					kShip_isRock,				OOJS_PROP_READONLY_CB },
	{ "isBoulder",				kShip_isBoulder,			OOJS_PROP_READWRITE_CB },
	{ "isThargoid",				kShip_isThargoid,			OOJS_PROP_READONLY_CB },
	{ "isTurret",				kShip_isTurret,				OOJS_PROP_READONLY_CB },
	{ "isTrader",				kShip_isTrader,				OOJS_PROP_READONLY_CB },
	{ "isWeapon",				kShip_isWeapon,				OOJS_PROP_READONLY_CB },
	{ "laserHeatLevel",			kShip_laserHeatLevel,		OOJS_PROP_READONLY_CB },
	{ "laserHeatLevelAft",		kShip_laserHeatLevelAft,	OOJS_PROP_READONLY_CB },
	{ "laserHeatLevelForward",	kShip_laserHeatLevelForward,	OOJS_PROP_READONLY_CB },
	{ "laserHeatLevelPort",		kShip_laserHeatLevelPort,	OOJS_PROP_READONLY_CB },
	{ "laserHeatLevelStarboard",	kShip_laserHeatLevelStarboard,	OOJS_PROP_READONLY_CB },
	{ "lightsActive",			kShip_lightsActive,			OOJS_PROP_READWRITE_CB },
	{ "markedForFines",				kShip_markedForFines,				OOJS_PROP_READONLY_CB },
	{ "maxEscorts",				kShip_maxEscorts,				OOJS_PROP_READWRITE_CB },
	{ "maxPitch",				kShip_maxPitch,				OOJS_PROP_READONLY_CB },
	{ "maxSpeed",				kShip_maxSpeed,				OOJS_PROP_READONLY_CB },
	{ "maxRoll",				kShip_maxRoll,				OOJS_PROP_READONLY_CB },
	{ "maxYaw",					kShip_maxYaw,				OOJS_PROP_READONLY_CB },
	{ "maxThrust",				kShip_maxThrust,			OOJS_PROP_READONLY_CB },
	{ "missileCapacity",		kShip_missileCapacity,		OOJS_PROP_READONLY_CB },
	{ "missileLoadTime",		kShip_missileLoadTime,		OOJS_PROP_READWRITE_CB },
	{ "missiles",				kShip_missiles,				OOJS_PROP_READONLY_CB },
	{ "name",					kShip_name,					OOJS_PROP_READWRITE_CB },
	{ "parcelCount",			kShip_parcelCount,		OOJS_PROP_READONLY_CB },
	{ "parcels",				kShip_parcels,			OOJS_PROP_READONLY_CB },
	{ "passengerCount",			kShip_passengerCount,		OOJS_PROP_READONLY_CB },
	{ "passengerCapacity",		kShip_passengerCapacity,	OOJS_PROP_READONLY_CB },
	{ "passengers",				kShip_passengers,			OOJS_PROP_READONLY_CB },
	{ "pitch",					kShip_pitch,				OOJS_PROP_READONLY_CB },
	{ "portWeapon",				kShip_portWeapon,			OOJS_PROP_READWRITE_CB },
	{ "potentialCollider",		kShip_potentialCollider,	OOJS_PROP_READONLY_CB },
	{ "primaryRole",			kShip_primaryRole,			OOJS_PROP_READWRITE_CB },
	{ "reportAIMessages",		kShip_reportAIMessages,		OOJS_PROP_READWRITE_CB },
	{ "roleWeights",			kShip_roleWeights,			OOJS_PROP_READONLY_CB },
	{ "roles",					kShip_roles,				OOJS_PROP_READONLY_CB },
	{ "roll",					kShip_roll,					OOJS_PROP_READONLY_CB },
	{ "savedCoordinates",		kShip_savedCoordinates,		OOJS_PROP_READWRITE_CB },
	{ "scannerDisplayColor1",	kShip_scannerDisplayColor1,	OOJS_PROP_READWRITE_CB },
	{ "scannerDisplayColor2",	kShip_scannerDisplayColor2,	OOJS_PROP_READWRITE_CB },
	{ "scannerRange",			kShip_scannerRange,			OOJS_PROP_READONLY_CB },
	{ "script",					kShip_script,				OOJS_PROP_READONLY_CB },
	{ "scriptedMisjump",		kShip_scriptedMisjump,		OOJS_PROP_READWRITE_CB },
	{ "scriptedMisjumpRange",		kShip_scriptedMisjumpRange,		OOJS_PROP_READWRITE_CB },
	{ "scriptInfo",				kShip_scriptInfo,			OOJS_PROP_READONLY_CB },
	{ "shipClassName",			kShip_shipClassName,		OOJS_PROP_READWRITE_CB },
	{ "shipUniqueName",				kShip_shipUniqueName,				OOJS_PROP_READWRITE_CB },
	{ "speed",					kShip_speed,				OOJS_PROP_READONLY_CB },
	{ "starboardWeapon",		kShip_starboardWeapon,		OOJS_PROP_READWRITE_CB },
	{ "subEntities",			kShip_subEntities,			OOJS_PROP_READONLY_CB },
	{ "subEntityCapacity",		kShip_subEntityCapacity,	OOJS_PROP_READONLY_CB },
	{ "target",					kShip_target,				OOJS_PROP_READWRITE_CB },
	{ "temperature",			kShip_temperature,			OOJS_PROP_READWRITE_CB },
	{ "thrust",					kShip_thrust,				OOJS_PROP_READWRITE_CB },
	{ "thrustVector",			kShip_thrustVector,			OOJS_PROP_READONLY_CB },
	{ "trackCloseContacts",		kShip_trackCloseContacts,	OOJS_PROP_READWRITE_CB },
	{ "vectorForward",			kShip_vectorForward,		OOJS_PROP_READONLY_CB },
	{ "vectorRight",			kShip_vectorRight,			OOJS_PROP_READONLY_CB },
	{ "vectorUp",				kShip_vectorUp,				OOJS_PROP_READONLY_CB },
	{ "velocity",				kShip_velocity,				OOJS_PROP_READWRITE_CB },
	{ "weaponFacings",			kShip_weaponFacings,		OOJS_PROP_READONLY_CB },
	{ "weaponPositionAft",		kShip_weaponPositionAft,	OOJS_PROP_READONLY_CB },
	{ "weaponPositionForward",	kShip_weaponPositionForward,	OOJS_PROP_READONLY_CB },
	{ "weaponPositionPort",		kShip_weaponPositionPort,	OOJS_PROP_READONLY_CB },	
	{ "weaponPositionStarboard",	kShip_weaponPositionStarboard,	OOJS_PROP_READONLY_CB },
	{ "weaponRange",			kShip_weaponRange,			OOJS_PROP_READONLY_CB },
	{ "withinStationAegis",		kShip_withinStationAegis,	OOJS_PROP_READONLY_CB },
	{ "yaw",					kShip_yaw,					OOJS_PROP_READONLY_CB },
	{ 0 }
};

static JSFunctionSpec sShipMethods[] =
{
	// JS name					Function					min args
	{ "abandonShip",			ShipAbandonShip,			0 },
	{ "addDefenseTarget",		ShipAddDefenseTarget,		1 },
	{ "awardEquipment",			ShipAwardEquipment,			1 },
	{ "becomeCascadeExplosion",			ShipBecomeCascadeExplosion,			0 },
	{ "broadcastCascadeImminent",			ShipBroadcastCascadeImminent,			0 },
	{ "broadcastDistressMessage",			ShipBroadcastDistressMessage,			0 },
	{ "canAwardEquipment",		ShipCanAwardEquipment,		1 },
	{ "checkCourseToDestination",		ShipCheckCourseToDestination,		0 },
	{ "checkScanner",		ShipCheckScanner,		0 },
	{ "clearDefenseTargets",	ShipClearDefenseTargets,	0 },
	{ "commsMessage",			ShipCommsMessage,			1 },
	{ "damageAssessment",		ShipDamageAssessment,		0 },
	{ "dealEnergyDamage",		ShipDealEnergyDamage,		2 },
	{ "deployEscorts",			ShipDeployEscorts,			0 },
	{ "dockEscorts",			ShipDockEscorts,			0 },
	{ "dumpCargo",				ShipDumpCargo,				0 },
	{ "ejectItem",				ShipEjectItem,				1 },
	{ "ejectSpecificItem",		ShipEjectSpecificItem,		1 },
	{ "enterWormhole",		ShipEnterWormhole,		0 },
	{ "equipmentStatus",		ShipEquipmentStatus,		1 },
	{ "exitAI",					ShipExitAI,					0 },
	{ "exitSystem",				ShipExitSystem,				0 },
	{ "explode",				ShipExplode,				0 },
	{ "fireECM",				ShipFireECM,				0 },
	{ "fireMissile",			ShipFireMissile,			0 },
	{ "findNearestStation",		ShipFindNearestStation,		0 },
	{ "getMaterials",			ShipGetMaterials,			0 },
	{ "getSafeCourseToDestination",		ShipGetSafeCourseToDestination,		0 },
	{ "getShaders",				ShipGetShaders,				0 },
	{ "hasRole",				ShipHasRole,				1 },
	{ "markTargetForFines",				ShipMarkTargetForFines,				0 },
	{ "notifyGroupOfWormhole",		ShipNotifyGroupOfWormhole,		0 },
	{ "offerToEscort",				ShipOfferToEscort,				1 },
	{ "patrolReportIn", ShipPatrolReportIn, 1},
  { "performAttack",		ShipPerformAttack, 		0 },
  { "performCollect",		ShipPerformCollect, 		0 },
  { "performEscort",		ShipPerformEscort, 		0 },
  { "performFaceDestination",		ShipPerformFaceDestination, 		0 },
  { "performFlee",		ShipPerformFlee, 		0 },
  { "performFlyToRangeFromDestination",		ShipPerformFlyToRangeFromDestination, 		0 },
  { "performHold",		ShipPerformHold, 		0 },
  { "performIdle",		ShipPerformIdle, 		0 },
  { "performIntercept",		ShipPerformIntercept, 		0 },
  { "performLandOnPlanet",		ShipPerformLandOnPlanet, 		0 },
  { "performMining",		ShipPerformMining, 		0 },
  { "performScriptedAI",		ShipPerformScriptedAI, 		0 },
  { "performScriptedAttackAI",		ShipPerformScriptedAttackAI, 		0 },
  { "performStop",		ShipPerformStop, 		0 },
  { "performTumble",		ShipPerformTumble, 		0 },

	{ "reactToAIMessage",		ShipReactToAIMessage,		1 },
	{ "remove",					ShipRemove,					0 },
	{ "removeDefenseTarget",   ShipRemoveDefenseTarget,   1 },
	{ "removeEquipment",		ShipRemoveEquipment,		1 },
	{ "requestHelpFromGroup", ShipRequestHelpFromGroup, 0},
	{ "requestDockingInstructions", ShipRequestDockingInstructions, 0},
	{ "recallDockingInstructions", ShipRecallDockingInstructions, 0},
	{ "restoreSubEntities",		ShipRestoreSubEntities,		0 },
	{ "__runLegacyScriptActions", ShipRunLegacyScriptActions, 2 },	// Deliberately not documented
	{ "selectNewMissile",		ShipSelectNewMissile,		0 },
	{ "sendAIMessage",			ShipSendAIMessage,			1 },
	{ "setAI",					ShipSetAI,					1 },
	{ "setBounty",				ShipSetBounty,				2 },
	{ "setCargo",				ShipSetCargo,				1 },
	{ "setCargoType",				ShipSetCargoType,				1 },
	{ "setEquipmentStatus",		ShipSetEquipmentStatus,		2 },
	{ "setMaterials",			ShipSetMaterials,			1 },
	{ "setScript",				ShipSetScript,				1 },
	{ "setShaders",				ShipSetShaders,				2 },
	{ "spawn",					ShipSpawn,					1 },
	// spawnOne() is defined in the prefix script.
	{ "switchAI",				ShipSwitchAI,				1 },
	{ "threatAssessment",		ShipThreatAssessment,		1 },
	{ "throwSpark",				ShipThrowSpark,				0 },
	{ "updateEscortFormation",	ShipUpdateEscortFormation,	0 },
	{ 0 }
};

static JSFunctionSpec sShipStaticMethods[] =
{
	// JS name				Function						min args
	{ "keys",				ShipStaticKeys,					0 },
	{ "keysForRole",		ShipStaticKeysForRole,			1 },
	{ "roleIsInCategory",	ShipStaticRoleIsInCategory,		2 },
	{ "roles",				ShipStaticRoles,				0 },
	{ 0 }
};


DEFINE_JS_OBJECT_GETTER(JSShipGetShipEntity, &sShipClass, sShipPrototype, ShipEntity)


void InitOOJSShip(JSContext *context, JSObject *global)
{
	sShipPrototype = JS_InitClass(context, global, JSEntityPrototype(), &sShipClass, OOJSUnconstructableConstruct, 0, sShipProperties, sShipMethods, NULL, sShipStaticMethods);
	OOJSRegisterObjectConverter(&sShipClass, OOJSBasicPrivateObjectConverter);
	OOJSRegisterSubclass(&sShipClass, JSEntityClass());
}


JSClass *JSShipClass(void)
{
	return &sShipClass;
}


JSObject *JSShipPrototype(void)
{
	return sShipPrototype;
}


static JSBool ShipGetProperty(JSContext *context, JSObject *this, jsid propID, jsval *value)
{
	if (!JSID_IS_INT(propID))  return YES;
	
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity					*entity = nil;
	id							result = nil;
	
	if (EXPECT_NOT(!JSShipGetShipEntity(context, this, &entity)))  return NO;
	if (OOIsStaleEntity(entity)) { *value = JSVAL_VOID; return YES; }
	
	switch (JSID_TO_INT(propID))
	{
		case kShip_name:
			result = [entity name];
			break;
			
		case kShip_displayName:
			result = [entity displayName];
			break;

		case kShip_shipUniqueName:
			result = [entity shipUniqueName];
			break;

		case kShip_shipClassName:
			result = [entity shipClassName];
			break;
		
		case kShip_roles:
			result = [[entity roleSet] sortedRoles];
			break;
		
		case kShip_roleWeights:
			result = [[entity roleSet] rolesAndProbabilities];
			break;
		
		case kShip_primaryRole:
			result = [entity primaryRole];
			break;
		
		case kShip_AI:
			result = [[entity getAI] name];
			break;
		
		case kShip_AIState:
			result = [[entity getAI] state];
			break;
		
		case kShip_AIFoundTarget:
			result = [entity foundTarget];
			break;
		
		case kShip_AIPrimaryAggressor:
			result = [entity primaryAggressor];
			break;
		
		case kShip_alertCondition:
			return JS_NewNumberValue(context, [entity realAlertCondition], value);

		case kShip_autoAI:
			*value = OOJSValueFromBOOL([entity hasAutoAI]);
			return YES;

		case kShip_autoWeapons:
			*value = OOJSValueFromBOOL([entity hasAutoWeapons]);
			return YES;
		
		case kShip_accuracy:
			return JS_NewNumberValue(context, [entity accuracy], value);
			
		case kShip_fuel:
			return JS_NewNumberValue(context, [entity fuel] * 0.1, value);
			
		case kShip_fuelChargeRate:
			return JS_NewNumberValue(context, [entity fuelChargeRate], value);
			
		case kShip_bounty:
			return JS_NewNumberValue(context, [entity bounty], value);
			return YES;
			
		case kShip_subEntities:
			result = [entity subEntitiesForScript];
			break;

		case kShip_exhausts:
			result = [[entity exhaustEnumerator] allObjects];
			break;

		case kShip_flashers:
			result = [[entity flasherEnumerator] allObjects];
			break;
			
		case kShip_subEntityCapacity:
			return JS_NewNumberValue(context, [entity maxShipSubEntities], value);
			return YES;
			
		case kShip_hasSuspendedAI:
			*value = OOJSValueFromBOOL([[entity getAI] hasSuspendedStateMachines]);
			return YES;
			
		case kShip_target:
			result = [entity primaryTarget];
			break;
		
		case kShip_defenseTargets:
		{
			[entity validateDefenseTargets];
			result = [NSMutableArray arrayWithCapacity:[entity defenseTargetCount]];
			NSEnumerator *defTargets = [entity defenseTargetEnumerator];
			Entity *target = nil;
			while ((target = [[defTargets nextObject] weakRefUnderlyingObject]))
			{
				[result addObject:target];
			}
			break;
		}		
	
		case kShip_escorts:
			result = [[entity escortGroup] memberArrayExcludingLeader];
			break;
			
		case kShip_group:
			result = [entity group];
			break;
			
		case kShip_escortGroup:
			result = [entity escortGroup];
			break;
			
		case kShip_temperature:
			return JS_NewNumberValue(context, [entity temperature] / SHIP_MAX_CABIN_TEMP, value);
			
		case kShip_heatInsulation:
			return JS_NewNumberValue(context, [entity heatInsulation], value);
			
		case kShip_heading:
			return VectorToJSValue(context, [entity forwardVector], value);
			
		case kShip_energyRechargeRate:
			return JS_NewNumberValue(context, [entity energyRechargeRate], value);

		case kShip_entityPersonality:
			*value = INT_TO_JSVAL([entity entityPersonalityInt]);
			return YES;
			
		case kShip_isBeacon:
			*value = OOJSValueFromBOOL([entity isBeacon]);
			return YES;
			
		case kShip_beaconCode:
			result = [entity beaconCode];
			break;

		case kShip_beaconLabel:
			result = [entity beaconLabel];
			break;
		
		case kShip_isFrangible:
			*value = OOJSValueFromBOOL([entity isFrangible]);
			return YES;
		
		case kShip_isCloaked:
			*value = OOJSValueFromBOOL([entity isCloaked]);
			return YES;
			
		case kShip_cloakAutomatic:
			*value = OOJSValueFromBOOL([entity hasAutoCloak]);
			return YES;
			
		case kShip_isJamming:
			*value = OOJSValueFromBOOL([entity isJammingScanning]);
			return YES;
		
		case kShip_potentialCollider:
			result = [entity proximityAlert];
			break;
		
		case kShip_hasHostileTarget:
			*value = OOJSValueFromBOOL([entity hasHostileTarget]);
			return YES;
		
		case kShip_hasHyperspaceMotor:
			*value = OOJSValueFromBOOL([entity hasHyperspaceMotor]);
			return YES;
		
		case kShip_weaponRange:
			return JS_NewNumberValue(context, [entity weaponRange], value);

		case kShip_weaponFacings:
			if ([entity isPlayer])
			{
				PlayerEntity *pent = (PlayerEntity*)entity;
				return JS_NewNumberValue(context, [pent availableFacings], value);
			}
			return JS_NewNumberValue(context, [entity weaponFacings], value);
		
		case kShip_weaponPositionAft:
			return VectorToJSValue(context, [entity aftWeaponOffset], value);
		
		case kShip_weaponPositionForward:
			return VectorToJSValue(context, [entity forwardWeaponOffset], value);
		
		case kShip_weaponPositionPort:
			return VectorToJSValue(context, [entity portWeaponOffset], value);
		
		case kShip_weaponPositionStarboard:
			return VectorToJSValue(context, [entity starboardWeaponOffset], value);
		
		case kShip_scannerRange:
			return JS_NewNumberValue(context, [entity scannerRange], value);
		
		case kShip_reportAIMessages:
			*value = OOJSValueFromBOOL([entity reportAIMessages]);
			return YES;
		
		case kShip_withinStationAegis:
			*value = OOJSValueFromBOOL([entity withinStationAegis]);
			return YES;
		
		case kShip_cargoSpaceCapacity:
			*value = INT_TO_JSVAL([entity maxAvailableCargoSpace]);
			return YES;
		
		case kShip_cargoSpaceUsed:
			*value = INT_TO_JSVAL([entity maxAvailableCargoSpace] - [entity availableCargoSpace]);
			return YES;
		
		case kShip_cargoSpaceAvailable:
			*value = INT_TO_JSVAL([entity availableCargoSpace]);
			return YES;

	  case kShip_cargoList:
			result = [entity cargoListForScripting];
			break;

		case kShip_extraCargo:
			return JS_NewNumberValue(context, [entity extraCargo], value);
			return YES;
		
		case kShip_commodity:
			if ([entity commodityAmount] > 0)
			{
				result = CommodityTypeToString([entity commodityType]);
			}
			break;
			
		case kShip_commodityAmount:
			*value = INT_TO_JSVAL([entity commodityAmount]);
			return YES;
			
		case kShip_speed:
			return JS_NewNumberValue(context, [entity flightSpeed], value);
			
		case kShip_cruiseSpeed:
			return JS_NewNumberValue(context, [entity cruiseSpeed], value);
		
		case kShip_dataKey:
			result = [entity shipDataKey];
			break;
			
		case kShip_desiredRange:
			return JS_NewNumberValue(context, [entity desiredRange], value);
		
		case kShip_desiredSpeed:
			return JS_NewNumberValue(context, [entity desiredSpeed], value);
			
		case kShip_destination:
			return HPVectorToJSValue(context, [entity destination], value);
		
		case kShip_markedForFines:
			*value = OOJSValueFromBOOL([entity markedForFines]);
			return YES;

		case kShip_maxEscorts:
			return JS_NewNumberValue(context, [entity maxEscortCount], value);

		case kShip_maxPitch:
			return JS_NewNumberValue(context, [entity maxFlightPitch], value);
		
		case kShip_maxSpeed:
			return JS_NewNumberValue(context, [entity maxFlightSpeed], value);
		
		case kShip_maxRoll:
			return JS_NewNumberValue(context, [entity maxFlightRoll], value);
		
		case kShip_maxYaw:
			return JS_NewNumberValue(context, [entity maxFlightYaw], value);
			
		case kShip_script:
			result = [entity shipScript];
			break;

		case kShip_AIScript:
			result = [entity shipAIScript];
			break;

		case kShip_AIScriptWakeTime:
			return JS_NewNumberValue(context, [entity shipAIScriptWakeTime], value);
			break;

		case kShip_destinationSystem:
			return JS_NewNumberValue(context, [entity destinationSystem], value);
			break;

		case kShip_homeSystem:
			return JS_NewNumberValue(context, [entity homeSystem], value);
			break;
			
		case kShip_isPirate:
			*value = OOJSValueFromBOOL([entity isPirate]);
			return YES;
			
		case kShip_isPolice:
			*value = OOJSValueFromBOOL([entity isPolice]);
			return YES;
			
		case kShip_isThargoid:
			*value = OOJSValueFromBOOL([entity isThargoid]);
			return YES;
			
		case kShip_isTurret:
			*value = OOJSValueFromBOOL([entity isTurret]);
			return YES;

		case kShip_isTrader:
			*value = OOJSValueFromBOOL([entity isTrader]);
			return YES;
			
		case kShip_isPirateVictim:
			*value = OOJSValueFromBOOL([entity isPirateVictim]);
			return YES;
			
		case kShip_isMissile:
			*value = OOJSValueFromBOOL([entity isMissile]);
			return YES;
			
		case kShip_isMine:
			*value = OOJSValueFromBOOL([entity isMine]);
			return YES;
			
		case kShip_isWeapon:
			*value = OOJSValueFromBOOL([entity isWeapon]);
			return YES;
			
		case kShip_isRock:
			*value = OOJSValueFromBOOL([entity scanClass] == CLASS_ROCK);	// hermits and asteroids!
			return YES;
			
		case kShip_isBoulder:
			*value = OOJSValueFromBOOL([entity isBoulder]);
			return YES;

		case kShip_isFleeing:
			if ([entity isPlayer])
			{
				*value = OOJSValueFromBOOL([(PlayerEntity*)entity fleeingStatus] >= PLAYER_FLEEING_CARGO);
			}
			else
			{
				*value = OOJSValueFromBOOL([entity behaviour] == BEHAVIOUR_FLEE_TARGET || [entity behaviour] == BEHAVIOUR_FLEE_EVASIVE_ACTION);
			}
			return YES;
			
		case kShip_isCargo:
			*value = OOJSValueFromBOOL([entity scanClass] == CLASS_CARGO && [entity commodityAmount] > 0);
			return YES;
			
		case kShip_isDerelict:
			*value = OOJSValueFromBOOL([entity isHulk]);
			return YES;
			
		case kShip_isPiloted:
			*value = OOJSValueFromBOOL([entity isPlayer] || [[entity crew] count] > 0);
			return YES;
			
		case kShip_scriptedMisjump:
			*value = OOJSValueFromBOOL([entity scriptedMisjump]);
			return YES;

		case kShip_scriptedMisjumpRange:
			return JS_NewNumberValue(context, [entity scriptedMisjumpRange], value);
			
		case kShip_scriptInfo:
			result = [entity scriptInfo];
			if (result == nil)  result = [NSDictionary dictionary];	// empty rather than null
			break;
			
		case kShip_trackCloseContacts:
			*value = OOJSValueFromBOOL([entity trackCloseContacts]);
			return YES;
			
		case kShip_passengerCount:
			return JS_NewNumberValue(context, [entity passengerCount], value);

		case kShip_parcelCount:
			return JS_NewNumberValue(context, [entity parcelCount], value);
			
		case kShip_passengerCapacity:
			return JS_NewNumberValue(context, [entity passengerCapacity], value);
		
		case kShip_missileCapacity:
			return JS_NewNumberValue(context, [entity missileCapacity], value);
			
		case kShip_missileLoadTime:
			return JS_NewNumberValue(context, [entity missileLoadTime], value);
		
		case kShip_savedCoordinates:
			return HPVectorToJSValue(context,[entity coordinates], value);
		
		case kShip_equipment:
			result = [entity equipmentListForScripting];
			break;
			
		case kShip_currentWeapon:
			result = [entity weaponTypeForFacing:[entity currentWeaponFacing] strict:YES];
			break;
		
		case kShip_forwardWeapon:
			result = [entity weaponTypeForFacing:WEAPON_FACING_FORWARD strict:YES];
			break;
		
		case kShip_aftWeapon:
			result = [entity weaponTypeForFacing:WEAPON_FACING_AFT strict:YES];
			break;
		
		case kShip_portWeapon:
			result = [entity weaponTypeForFacing:WEAPON_FACING_PORT strict:YES];
			break;
		
		case kShip_starboardWeapon:
			result = [entity weaponTypeForFacing:WEAPON_FACING_STARBOARD strict:YES];
			break;
		
		case kShip_laserHeatLevel:
			return JS_NewNumberValue(context, [entity laserHeatLevel], value);
		
		case kShip_laserHeatLevelAft:
			return JS_NewNumberValue(context, [entity laserHeatLevelAft], value);
		
		case kShip_laserHeatLevelForward:
			return JS_NewNumberValue(context, [entity laserHeatLevelForward], value);
		
		case kShip_laserHeatLevelPort:
			return JS_NewNumberValue(context, [entity laserHeatLevelPort], value);
		
		case kShip_laserHeatLevelStarboard:
			return JS_NewNumberValue(context, [entity laserHeatLevelStarboard], value);
		
		case kShip_missiles:
			result = [entity missilesList];
			break;
		
		case kShip_passengers:
			result = [entity passengerListForScripting];
			break;

		case kShip_parcels:
			result = [entity parcelListForScripting];
			break;
		
		case kShip_contracts:
			result = [entity contractListForScripting];
			break;
			
  	case kShip_dockingInstructions:
			result = [entity dockingInstructions];
			break;

		case kShip_scannerDisplayColor1:
			result = [[entity scannerDisplayColor1] normalizedArray];
			break;
			
		case kShip_scannerDisplayColor2:
			result = [[entity scannerDisplayColor2] normalizedArray];
			break;
			
		case kShip_exhaustEmissiveColor:
			result = [[entity exhaustEmissiveColor] normalizedArray];
			break;
			
		case kShip_maxThrust:
			return JS_NewNumberValue(context, [entity maxThrust], value);
			
		case kShip_thrust:
			return JS_NewNumberValue(context, [entity thrust], value);
			
		case kShip_lightsActive:
			*value = OOJSValueFromBOOL([entity lightsActive]);
			return YES;
			
		case kShip_vectorRight:
			return VectorToJSValue(context, [entity rightVector], value);
			
		case kShip_vectorForward:
			return VectorToJSValue(context, [entity forwardVector], value);
			
		case kShip_vectorUp:
			return VectorToJSValue(context, [entity upVector], value);
			
		case kShip_velocity:
			return VectorToJSValue(context, [entity velocity], value);
			
		case kShip_thrustVector:
			return VectorToJSValue(context, [entity thrustVector], value);
		
		case kShip_pitch:
			return JS_NewNumberValue(context, [entity flightPitch], value);
		
		case kShip_roll:
			return JS_NewNumberValue(context, [entity flightRoll], value);
		
		case kShip_yaw:
			return JS_NewNumberValue(context, [entity flightYaw], value);
		
		case kShip_boundingBox:
			{
				Vector bbvect;
				BoundingBox box;
				
				if ([entity isSubEntity])
				{
					box = [entity boundingBox];
				}
				else
				{
					box = [entity totalBoundingBox];
				}
				bounding_box_get_dimensions(box,&bbvect.x,&bbvect.y,&bbvect.z);
				return VectorToJSValue(context, bbvect, value);
			}
			
		default:
			OOJSReportBadPropertySelector(context, this, propID, sShipProperties);
			return NO;
	}
	
	*value = OOJSValueFromNativeObject(context, result);
	return YES;
	
	OOJS_NATIVE_EXIT
}


static JSBool ShipSetProperty(JSContext *context, JSObject *this, jsid propID, JSBool strict, jsval *value)
{
	if (!JSID_IS_INT(propID))  return YES;
	
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity					*entity = nil;
	ShipEntity					*target = nil;
	NSString					*sValue = nil;
	jsdouble					fValue;
	int32						iValue;
	JSBool						bValue;
	Vector						vValue;
	HPVector						hpvValue;
	OOShipGroup					*group = nil;
	OOColor						*colorForScript = nil;
	BOOL exists;
	
	if (EXPECT_NOT(!JSShipGetShipEntity(context, this, &entity)))  return NO;
	if (OOIsStaleEntity(entity))  return YES;

	NSCAssert(![entity isTemplateCargoPod], @"-OOJSShip: a template cargo pod has become accessible to Javascript");
	
	switch (JSID_TO_INT(propID))
	{
		case kShip_name:
			if (EXPECT_NOT([entity isPlayer]))  goto playerReadOnly;
			
			sValue = OOStringFromJSValue(context,*value);
			if (sValue != nil)
			{
				[entity setName:sValue];
				return YES;
			}
			break;
			
		case kShip_displayName:
			if (EXPECT_NOT([entity isPlayer]))  goto playerReadOnly;
			
			sValue = OOStringFromJSValue(context,*value);
			if (sValue != nil)
			{
				[entity setDisplayName:sValue];
				return YES;
			}
			break;

		case kShip_shipUniqueName:
			sValue = OOStringFromJSValue(context,*value);
			if (sValue != nil)
			{
				[entity setShipUniqueName:sValue];
				return YES;
			}
			break;

		case kShip_shipClassName:
			sValue = OOStringFromJSValue(context,*value);
			if (sValue != nil)
			{
				[entity setShipClassName:sValue];
				return YES;
			}
			break;

		
		case kShip_primaryRole:
			if (EXPECT_NOT([entity isPlayer]))  goto playerReadOnly;
			
			sValue = OOStringFromJSValue(context,*value);
			if (sValue != nil)
			{
				[entity setPrimaryRole:sValue];
				return YES;
			}
			break;
		
		case kShip_AIState:
			if (EXPECT_NOT([entity isPlayer]))  goto playerReadOnly;
			
			sValue = OOStringFromJSValue(context,*value);
			if (sValue != nil)
			{
				[[entity getAI] setState:sValue];
				return YES;
			}
			break;
		
		case kShip_beaconCode:
			if (EXPECT_NOT([entity isPlayer]))  goto playerReadOnly;
			
			sValue = OOStringFromJSValue(context,*value);
			if ([sValue length] == 0) 
			{
				if ([entity isBeacon]) 
				{
					[UNIVERSE clearBeacon:entity];
					if ([PLAYER nextBeacon] == entity)
					{
						[PLAYER setCompassMode:COMPASS_MODE_PLANET];
					}
				}
			}
			else 
			{
				if ([entity isBeacon]) 
				{
					[entity setBeaconCode:sValue];
				}
				else // Universe needs to update beacon lists in this case only
				{
					[entity setBeaconCode:sValue];
					[UNIVERSE setNextBeacon:entity];
				}
			}
			return YES;
			break;

		case kShip_beaconLabel:
			if (EXPECT_NOT([entity isPlayer]))  goto playerReadOnly;
			sValue = OOStringFromJSValue(context,*value);
			if (sValue != nil)
			{
				[entity setBeaconLabel:sValue];
				return YES;
			}
			break;
			
		case kShip_accuracy:
			if (EXPECT_NOT([entity isPlayer]))  goto playerReadOnly;
			
			if (JS_ValueToNumber(context, *value, &fValue))
			{
				[entity setAccuracy:fValue];
				return YES;
			}
			break;
		
		case kShip_fuel:
			if (JS_ValueToNumber(context, *value, &fValue))
			{
				fValue = OOClamp_0_max_d(fValue, MAX_JUMP_RANGE);
				[entity setFuel:lround(fValue * 10.0)];
				return YES;
			}
			break;
			
		case kShip_bounty:
			if (JS_ValueToInt32(context, *value, &iValue))
			{
				if (iValue < 0)  iValue = 0;
				[entity setBounty:iValue withReason:kOOLegalStatusReasonByScript];
				return YES;
			}
			break;

		case kShip_destinationSystem:
			if (JS_ValueToInt32(context, *value, &iValue))
			{
				if (iValue < 0)  iValue = 0;
				[entity setDestinationSystem:iValue];
				return YES;
			}
			break;

		case kShip_homeSystem:
			if (JS_ValueToInt32(context, *value, &iValue))
			{
				if (iValue < 0)  iValue = 0;
				[entity setHomeSystem:iValue];
				return YES;
			}
			break;
		
		case kShip_target:
			if (JSVAL_IS_NULL(*value))
			{
				[entity setTargetForScript:nil];
				return YES;
			}
			else if (JSValueToEntity(context, *value, &target) && [target isKindOfClass:[ShipEntity class]])
			{
				[entity setTargetForScript:target];
				return YES;
			}
			break;
		
		case kShip_AIFoundTarget:
			if (EXPECT_NOT([entity isPlayer]))  goto playerReadOnly;
			
			if (JSVAL_IS_NULL(*value))
			{
				[entity setFoundTarget:nil];
				return YES;
			}
			else if (JSValueToEntity(context, *value, &target) && [target isKindOfClass:[ShipEntity class]])
			{
				[entity setFoundTarget:target];
				return YES;
			}
			break;
		
		case kShip_AIPrimaryAggressor:
			if (EXPECT_NOT([entity isPlayer]))  goto playerReadOnly;
			
			if (JSVAL_IS_NULL(*value))
			{
				[entity setPrimaryAggressor:nil];
				return YES;
			}
			else if (JSValueToEntity(context, *value, &target) && [target isKindOfClass:[ShipEntity class]])
			{
				[entity setPrimaryAggressor:target];
				return YES;
			}
			break;
			
		case kShip_group:
			group = OOJSNativeObjectOfClassFromJSValue(context, *value, [OOShipGroup class]);
			if (group != nil || JSVAL_IS_NULL(*value))
			{
				[entity setGroup:group];
				return YES;
			}
			break;
		
		case kShip_AIScriptWakeTime:
			if (JS_ValueToNumber(context, *value, &fValue))
			{
				[entity setAIScriptWakeTime:fValue];
				return YES;
			}
			break;

		case kShip_temperature:
			if (JS_ValueToNumber(context, *value, &fValue))
			{
				fValue = fmax(fValue, 0.0);
				[entity setTemperature:fValue * SHIP_MAX_CABIN_TEMP];
				return YES;
			}
			break;
		
		case kShip_heatInsulation:
			if (EXPECT_NOT([entity isPlayer]))  goto playerReadOnly;
			
			if (JS_ValueToNumber(context, *value, &fValue))
			{
				fValue = fmax(fValue, 0.125);
				[entity setHeatInsulation:fValue];
				return YES;
			}
			break;
		
		case kShip_isCloaked:
			if (JS_ValueToBoolean(context, *value, &bValue))
			{
				[entity setCloaked:bValue];
				return YES;
			}
			break;
			
		case kShip_cloakAutomatic:
			if (JS_ValueToBoolean(context, *value, &bValue))
			{
				[entity setAutoCloak:bValue];
				return YES;
			}
			break;
			
		case kShip_missileLoadTime:
			if (JS_ValueToNumber(context, *value, &fValue))
			{
				[entity setMissileLoadTime:fmax(0.0, fValue)];
				return YES;
			}
			break;
		
		case kShip_reportAIMessages:
			if (JS_ValueToBoolean(context, *value, &bValue))
			{
				[entity setReportAIMessages:bValue];
				return YES;
			}
			break;
			
		case kShip_trackCloseContacts:
			if (JS_ValueToBoolean(context, *value, &bValue))
			{
				[entity setTrackCloseContacts:bValue];
				return YES;
			}
			break;
		
		case kShip_isBoulder:
			if (EXPECT_NOT([entity isPlayer]))  goto playerReadOnly;
			
			if (JS_ValueToBoolean(context, *value, &bValue))
			{
				[entity setIsBoulder:bValue];
				return YES;
			}
			break;
		
		case kShip_destination:
			if (EXPECT_NOT([entity isPlayer]))  goto playerReadOnly;
			
			if (JSValueToHPVector(context, *value, &hpvValue))
			{
				// use setEscortDestination rather than setDestination as
				// scripted amendments shouldn't necessarily reset frustration
				[entity setEscortDestination:hpvValue];
				return YES;
			}
			break;
			
		case kShip_desiredSpeed:
			if (EXPECT_NOT([entity isPlayer]))  goto playerReadOnly;
			
			if (JS_ValueToNumber(context, *value, &fValue))
			{
				[entity setDesiredSpeed:fmax(fValue, 0.0)];
				return YES;
			}
			break;
		
		case kShip_desiredRange:
			if (EXPECT_NOT([entity isPlayer]))  goto playerReadOnly;
			
			if (JS_ValueToNumber(context, *value, &fValue))
			{
				[entity setDesiredRange:fmax(fValue, 0.0)];
				return YES;
			}
			break;
		
		case kShip_savedCoordinates:
			if (JSValueToHPVector(context, *value, &hpvValue))
			{
				[entity setCoordinate:hpvValue];
				return YES;
			}
			break;
			
		case kShip_scannerDisplayColor1:
			colorForScript = [OOColor colorWithDescription:OOJSNativeObjectFromJSValue(context, *value)];
			if (colorForScript != nil || JSVAL_IS_NULL(*value))
			{
				[entity setScannerDisplayColor1:colorForScript];
				return YES;
			}
			break;
			
		case kShip_scannerDisplayColor2:
			colorForScript = [OOColor colorWithDescription:OOJSNativeObjectFromJSValue(context, *value)];
			if (colorForScript != nil || JSVAL_IS_NULL(*value))
			{
				[entity setScannerDisplayColor2:colorForScript];
				return YES;
			}
			break;
			
		case kShip_exhaustEmissiveColor:
			colorForScript = [OOColor colorWithDescription:OOJSNativeObjectFromJSValue(context, *value)];
			if (colorForScript != nil || JSVAL_IS_NULL(*value))
			{
				[entity setExhaustEmissiveColor:colorForScript];
				return YES;
			}
			break;
			
		case kShip_scriptedMisjump:
			if (JS_ValueToBoolean(context, *value, &bValue))
			{
				[entity setScriptedMisjump:bValue];
				return YES;
			}
			break;

		case kShip_scriptedMisjumpRange:
			if (JS_ValueToNumber(context, *value, &fValue))
			{
				if (fValue > 0.0 && fValue < 1.0)
				{
					[entity setScriptedMisjumpRange:fValue];
					return YES;
				}
				else
				{
					OOJSReportError(context, @"ship.%@ must be > 0.0 and < 1.0.", OOStringFromJSPropertyIDAndSpec(context, propID, sShipProperties));
					return NO;
				}
			}
			break;

			
		case kShip_thrust:
			if (EXPECT_NOT([entity isPlayer]))  goto playerReadOnly;
			
			if (JS_ValueToNumber(context, *value, &fValue))
			{
				[entity setThrust:OOClamp_0_max_f(fValue, [entity maxThrust])];
				return YES;
			}
			break;
			
		case kShip_lightsActive:
			if (JS_ValueToBoolean(context, *value, &bValue))
			{
				if (bValue)  [entity switchLightsOn];
				else  [entity switchLightsOff];
				return YES;
			}
			break;
			
		case kShip_velocity:
			if (JSValueToVector(context, *value, &vValue))
			{
				[entity setTotalVelocity:vValue];
				return YES;
			}
			break;
			
		case kShip_portWeapon:
		case kShip_starboardWeapon:
		case kShip_aftWeapon:
		case kShip_forwardWeapon:
		case kShip_currentWeapon:
			sValue = JSValueToEquipmentKeyRelaxed(context, *value, &exists);
			if (sValue == nil) 
			{
				sValue = @"EQ_WEAPON_NONE";
			}
			OOWeaponFacing facing = WEAPON_FACING_FORWARD;
			switch (JSID_TO_INT(propID))
			{
				case kShip_aftWeapon: 
					facing = WEAPON_FACING_AFT;
					break;
				case kShip_forwardWeapon: 
					facing = WEAPON_FACING_FORWARD;
					break;
				case kShip_portWeapon: 
					facing = WEAPON_FACING_PORT;
					break;
				case kShip_starboardWeapon:
					facing = WEAPON_FACING_STARBOARD;
					break;
				case kShip_currentWeapon:
					facing = [entity currentWeaponFacing];
					break;
			}
			[entity setWeaponMount:facing toWeapon:sValue];
			return YES;

		case kShip_maxEscorts:
			if (EXPECT_NOT([entity isPlayer]))  goto playerReadOnly;
			
			if (JS_ValueToInt32(context, *value, &iValue))
			{
				if ((NSInteger)iValue < (NSInteger)[[entity escortGroup] count] - 1)
				{
					OOJSReportError(context, @"ship.%@ must be >= current escort numbers.", OOStringFromJSPropertyIDAndSpec(context, propID, sShipProperties));
					return NO;
				}
				if (iValue > MAX_ESCORTS)
				{
					OOJSReportError(context, @"ship.%@ must be <= %d.", OOStringFromJSPropertyIDAndSpec(context, propID, sShipProperties),MAX_ESCORTS);
					return NO;
				}
				[entity setMaxEscortCount:iValue];
				return YES;
			}

			break;

			
		default:
			OOJSReportBadPropertySelector(context, this, propID, sShipProperties);
			return NO;
	}
	
	OOJSReportBadPropertyValue(context, this, propID, sShipProperties, *value);
	return NO;
	
playerReadOnly:
	OOJSReportError(context, @"player.ship.%@ is read-only.", OOStringFromJSPropertyIDAndSpec(context, propID, sShipProperties));
	return NO;

// Not used (yet)
/*
npcReadOnly:
	OOJSReportError(context, @"npc.ship.%@ is read-only.", OOStringFromJSPropertyIDAndSpec(context, propID, sShipProperties));
	return NO;
*/

	OOJS_NATIVE_EXIT
}


// *** Methods ***

#define GET_THIS_SHIP(THISENT) do { \
	if (EXPECT_NOT(!JSShipGetShipEntity(context, OOJS_THIS, &THISENT)))  return NO; /* Exception */ \
	if (OOIsStaleEntity(THISENT))  OOJS_RETURN_VOID; \
} while (0)


// setScript(scriptName : String)
static JSBool ShipSetScript(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nil;
	NSString				*name = nil;
	
	GET_THIS_SHIP(thisEnt);
	if (argc > 0)  name = OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (EXPECT_NOT(name == nil))
	{
		OOJSReportBadArguments(context, @"Ship", @"setScript", MIN(argc, 1U), OOJS_ARGV, nil, @"string (script name)");
		return NO;
	}
	if (EXPECT_NOT([thisEnt isPlayer]))
	{
		OOJSReportErrorForCaller(context, @"Ship", @"setScript", @"Not valid for player ship.");
		return NO;
	}
	
	[thisEnt setShipScript:name];
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// setAI(aiName : String)
static JSBool ShipSetAI(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nil;
	NSString				*name = nil;
	
	GET_THIS_SHIP(thisEnt);
	if (argc > 0)  name = OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (EXPECT_NOT(name == nil))
	{
		OOJSReportBadArguments(context, @"Ship", @"setAI", MIN(argc, 1U), OOJS_ARGV, nil, @"string (AI name)");
		return NO;
	}
	if (EXPECT_NOT([thisEnt isPlayer]))
	{
		OOJSReportErrorForCaller(context, @"Ship", @"setAI", @"Not valid for player ship.");
		return NO;
	}
	
	[thisEnt setAITo:name];
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// switchAI(aiName : String)
static JSBool ShipSwitchAI(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nil;
	NSString				*name = nil;
	
	GET_THIS_SHIP(thisEnt);
	if (argc > 0)  name = OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (EXPECT_NOT(name == nil))
	{
		OOJSReportBadArguments(context, @"Ship", @"switchAI", MIN(argc, 1U), OOJS_ARGV, nil, @"string (AI name)");
		return NO;
	}
	if (EXPECT_NOT([thisEnt isPlayer]))
	{
		OOJSReportErrorForCaller(context, @"Ship", @"switchAI", @"Not valid for player ship.");
		return NO;
	}
	
	[thisEnt switchAITo:name];
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// exitAI()
static JSBool ShipExitAI(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nil;
	AI						*thisAI = nil;
	NSString				*message = nil;
	
	GET_THIS_SHIP(thisEnt);
	if (EXPECT_NOT([thisEnt isPlayer]))
	{
		OOJSReportErrorForCaller(context, @"Ship", @"exitAI", @"Not valid for player ship.");
		return NO;
	}
	thisAI = [thisEnt getAI];
	
	if ([thisAI hasSuspendedStateMachines])
	{
		if (argc > 0)
		{
			message = OOStringFromJSValue(context, OOJS_ARGV[0]);
		}
		// Else AI will default to RESTARTED.
		
		[thisAI exitStateMachineWithMessage:message];
	}
	else
	{
		OOJSReportWarningForCaller(context, @"Ship", @"exitAI()", @"Cannot exit current AI state machine because there are no suspended state machines.");
	}
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// reactToAIMessage(message : String)
static JSBool ShipReactToAIMessage(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nil;
	NSString				*message = nil;
	
	GET_THIS_SHIP(thisEnt);
	if (argc > 0)  message = OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (EXPECT_NOT(message == nil))
	{
		OOJSReportBadArguments(context, @"Ship", @"reactToAIMessage", MIN(argc, 1U), OOJS_ARGV, nil, @"string");
		return NO;
	}
	if (EXPECT_NOT([thisEnt isPlayer]))
	{
		OOJSReportErrorForCaller(context, @"Ship", @"reactToAIMessage", @"Not valid for player ship.");
		return NO;
	}
	
	[thisEnt reactToAIMessage:message context:@"JavaScript reactToAIMessage()"];
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// sendAIMessage(message : String)
static JSBool ShipSendAIMessage(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nil;
	NSString				*message = nil;
	
	GET_THIS_SHIP(thisEnt);
	if (argc > 0)  message = OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (EXPECT_NOT(message == nil))
	{
		OOJSReportBadArguments(context, @"Ship", @"sendAIMessage", MIN(argc, 1U), OOJS_ARGV, nil, @"string");
		return NO;
	}
	if (EXPECT_NOT([thisEnt isPlayer]))
	{
		OOJSReportErrorForCaller(context, @"Ship", @"sendAIMessage", @"Not valid for player ship.");
		return NO;
	}
	
	[thisEnt sendAIMessage:message];
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// deployEscorts()
static JSBool ShipDeployEscorts(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nil;
	
	GET_THIS_SHIP(thisEnt);
	
	[thisEnt deployEscorts];
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// dockEscorts()
static JSBool ShipDockEscorts(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nil;
	
	GET_THIS_SHIP(thisEnt);
	
	[thisEnt dockEscorts];
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// hasRole(role : String) : Boolean
static JSBool ShipHasRole(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nil;
	NSString				*role = nil;
	
	GET_THIS_SHIP(thisEnt);
	
	if (argc > 0)  role = OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (EXPECT_NOT(role == nil))
	{
		OOJSReportBadArguments(context, @"Ship", @"hasRole", MIN(argc, 1U), OOJS_ARGV, nil, @"string (role)");
		return NO;
	}
	
	OOJS_RETURN_BOOL([thisEnt hasRole:role]);
	
	OOJS_NATIVE_EXIT
}


// ejectItem(role : String) : Ship
static JSBool ShipEjectItem(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nil;
	NSString				*role = nil;
	
	GET_THIS_SHIP(thisEnt);
	
	if (argc > 0)  role = OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (EXPECT_NOT(role == nil))
	{
		OOJSReportBadArguments(context, @"Ship", @"ejectItem", MIN(argc, 1U), OOJS_ARGV, nil, @"string (role)");
		return NO;
	}
	
	OOJS_RETURN_OBJECT([thisEnt ejectShipOfRole:role]);
	
	OOJS_NATIVE_EXIT
}


// ejectSpecificItem(itemKey : String) : Ship
static JSBool ShipEjectSpecificItem(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nil;
	NSString				*itemKey = nil;
	
	GET_THIS_SHIP(thisEnt);
	
	if (argc > 0)  itemKey = OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (EXPECT_NOT(itemKey == nil))
	{
		OOJSReportBadArguments(context, @"Ship", @"ejectSpecificItem", MIN(argc, 1U), OOJS_ARGV, nil, @"string (ship key)");
		return NO;
	}
	
	OOJS_RETURN_OBJECT([thisEnt ejectShipOfType:itemKey]);
	
	OOJS_NATIVE_EXIT
}


// dumpCargo() : Ship
static JSBool ShipDumpCargo(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nil;
	
	GET_THIS_SHIP(thisEnt);
	
	if (EXPECT_NOT([thisEnt isPlayer] && [(PlayerEntity *)thisEnt isDocked]))
	{
		OOJSReportWarningForCaller(context, @"PlayerShip", @"dumpCargo", @"Can't dump cargo while docked, ignoring.");
		OOJS_RETURN_NULL;
	}
	// NPCs can queue multiple items to dump
	if (!EXPECT_NOT([thisEnt isPlayer]))
	{
		int32					i, count = 1;
		BOOL					gotCount = YES;
		if (argc > 0)  gotCount = JS_ValueToInt32(context, OOJS_ARGV[0], &count);
		if (EXPECT_NOT(!gotCount || count < 1 || count > 64))
		{
			OOJSReportBadArguments(context, @"Ship", @"dumpCargo", MIN(argc, 1U), OOJS_ARGV, nil, @"optional quantity (1 to 64)");
			return NO;
		}

		for (i = 1; i < count; i++)
		{
			[thisEnt performSelector:@selector(dumpCargo) withObject:nil afterDelay:0.75 * i];	// drop 3 canisters per 2 seconds
		}
	}

	OOJS_RETURN_OBJECT([thisEnt dumpCargoItem]);
	
	OOJS_NATIVE_EXIT
}


// spawn(role : String [, number : count]) : Array
static JSBool ShipSpawn(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nil;
	NSString				*role = nil;
	int32					count = 1;
	BOOL					gotCount = YES;
	NSArray					*result = nil;
	
	GET_THIS_SHIP(thisEnt);
	
	if (argc > 0)  role = OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (argc > 1)  gotCount = JS_ValueToInt32(context, OOJS_ARGV[1], &count);
	if (EXPECT_NOT(role == nil || !gotCount || count < 1 || count > 64))
	{
		OOJSReportBadArguments(context, @"Ship", @"spawn", MIN(argc, 1U), OOJS_ARGV, nil, @"role and optional quantity (1 to 64)");
		return NO;
	}
	
	OOJS_BEGIN_FULL_NATIVE(context)
	result = [thisEnt spawnShipsWithRole:role count:count];
	OOJS_END_FULL_NATIVE

	OOJS_RETURN_OBJECT(result);
	
	OOJS_NATIVE_EXIT
}


// dealEnergyDamage(). Replaces AI's dealEnergyDamageWithinDesiredRange
static JSBool ShipDealEnergyDamage(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nil;
	jsdouble baseDamage;
	jsdouble range;
	jsdouble velocityBias = 0.0;
	BOOL gotDamage;
	BOOL gotRange;
	BOOL gotVBias;
	GET_THIS_SHIP(thisEnt);

	if (argc < 2)
	{
		OOJSReportBadArguments(context, @"Ship", @"dealEnergyDamage", argc, OOJS_ARGV, nil, @"damage and range needed");
		return NO;
	}
	
	gotDamage = JS_ValueToNumber(context, OOJS_ARGV[0], &baseDamage);
	if (EXPECT_NOT(!gotDamage || baseDamage < 0))
	{
		OOJSReportBadArguments(context, @"Ship", @"dealEnergyDamage", argc, OOJS_ARGV, nil, @"damage must be positive");
		return NO;
	}
	gotRange = JS_ValueToNumber(context, OOJS_ARGV[1], &range);
	if (EXPECT_NOT(!gotRange || range < 0))
	{
		OOJSReportBadArguments(context, @"Ship", @"dealEnergyDamage", argc, OOJS_ARGV, nil, @"range must be positive");
		return NO;
	}
	if (argc >= 3) 
	{
		gotVBias = JS_ValueToNumber(context, OOJS_ARGV[2], &velocityBias);
		if (!gotVBias)
		{
			OOJSReportBadArguments(context, @"Ship", @"dealEnergyDamage", argc, OOJS_ARGV, nil, @"velocity bias must be a number");
			return NO;
		}
	}

	[thisEnt dealEnergyDamage:(GLfloat)baseDamage atRange:(GLfloat)range withBias:(GLfloat)velocityBias];

	OOJS_RETURN_VOID;

	OOJS_NATIVE_EXIT
}


// explode()
static JSBool ShipExplode(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	return RemoveOrExplodeShip(context, argc, vp, YES);
	
	OOJS_NATIVE_EXIT
}


// remove([suppressDeathEvent : Boolean = false])
static JSBool ShipRemove(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nil;
	JSBool					suppressDeathEvent = NO;
	
	GET_THIS_SHIP(thisEnt);
	
	if ([thisEnt isPlayer])
	{
		OOJSReportError(context, @"Cannot remove() player's ship.");
		return NO;
	}
	
	if (argc > 0 && EXPECT_NOT(!JS_ValueToBoolean(context, OOJS_ARGV[0], &suppressDeathEvent)))
	{
		OOJSReportBadArguments(context, @"Ship", @"remove", argc, OOJS_ARGV, nil, @"boolean");
		return NO;
	}

	[thisEnt doScriptEvent:OOJSID("shipRemoved") withArgument:[NSNumber numberWithBool:suppressDeathEvent]];

	if (suppressDeathEvent)
	{
		[thisEnt removeScript];
	}
	return RemoveOrExplodeShip(context, argc, vp, NO);
	
	OOJS_NATIVE_EXIT
}


// __runLegacyScriptActions(target : Ship, actions : Array)
static JSBool ShipRunLegacyScriptActions(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nil;
	PlayerEntity			*player = nil;
	ShipEntity				*target = nil;
	NSArray					*actions = nil;
	
	player = OOPlayerForScripting();
	GET_THIS_SHIP(thisEnt);
	
	if (argc > 1)  actions = OOJSNativeObjectFromJSValue(context, OOJS_ARGV[1]);
	if (EXPECT_NOT(argc != 2 ||
				   !JSVAL_IS_OBJECT(OOJS_ARGV[0]) ||
				   !JSShipGetShipEntity(context, JSVAL_TO_OBJECT(OOJS_ARGV[0]), &target) ||
				   ![actions isKindOfClass:[NSArray class]]))
	{
		OOJSReportBadArguments(context, @"Ship", @"__runLegacyScriptActions", argc, OOJS_ARGV, nil, @"target and array of actions");
		return NO;
	}
	
	if (target != nil)	// Not stale reference
	{
		[player setScriptTarget:thisEnt];
		[player runUnsanitizedScriptActions:actions
						  allowingAIMethods:YES
							withContextName:[NSString stringWithFormat:@"<ship \"%@\" legacy actions>", [thisEnt name]]
								  forTarget:target];
	}
	
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// commsMessage(message : String[,target : Ship])
static JSBool ShipCommsMessage(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nil;
	NSString				*message = nil;
	ShipEntity				*target = nil;
	
	GET_THIS_SHIP(thisEnt);
	
	if (argc > 0)  message = OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (EXPECT_NOT(message == nil || (argc > 1 && (JSVAL_IS_NULL(OOJS_ARGV[1]) || !JSVAL_IS_OBJECT(OOJS_ARGV[1]) || !JSShipGetShipEntity(context, JSVAL_TO_OBJECT(OOJS_ARGV[1]), &target)))))
	{
		OOJSReportBadArguments(context, @"Ship", @"commsMessage", MIN(argc, 1U), OOJS_ARGV, nil, @"message and optional target");
		return NO;
	}
	
	if (argc < 2)
	{
		[thisEnt commsMessage:message withUnpilotedOverride:YES];	// generic broadcast
	}
	else if (target != nil)  // Not stale reference
	{
		[thisEnt sendMessage:message toShip:target withUnpilotedOverride:YES];	// ship-to-ship narrowcast
	}
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// fireECM()
static JSBool ShipFireECM(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nil;
	BOOL					OK;
	
	GET_THIS_SHIP(thisEnt);
	
	OK = [thisEnt fireECM];
	if (!OK)
	{
		OOJSReportWarning(context, @"Ship %@ was requested to fire ECM burst but does not carry ECM equipment.", [thisEnt oo_jsDescription]);
	}
	
	OOJS_RETURN_BOOL(OK);
	
	OOJS_NATIVE_EXIT
}


// abandonShip()
static JSBool ShipAbandonShip(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nil;
	
	GET_THIS_SHIP(thisEnt);
	OOJS_RETURN_BOOL([thisEnt hasEscapePod] && [thisEnt abandonShip]);
	
	OOJS_NATIVE_EXIT
}


// canAwardEquipment(type : equipmentInfoExpression)
static JSBool ShipCanAwardEquipment(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity					*thisEnt = nil;
	NSString					*key = nil;
	BOOL						result;
	BOOL						exists;
	
	GET_THIS_SHIP(thisEnt);
	
	if (argc > 0)  key = JSValueToEquipmentKeyRelaxed(context, OOJS_ARGV[0], &exists);
	if (EXPECT_NOT(key == nil))
	{
		OOJSReportBadArguments(context, @"Ship", @"canAwardEquipment", MIN(argc, 1U), OOJS_ARGV, nil, @"equipment type");
		return NO;
	}
	
	if (exists)
	{
		result = YES;
		
		// can't add fuel as equipment.
		if ([key isEqualToString:@"EQ_FUEL"])  result = NO;
		
		if (result)  result = [thisEnt canAddEquipment:key inContext:@"scripted"];
	}
	else
	{
		// Unknown type.
		result = NO;
	}
	
	OOJS_RETURN_BOOL(result);
	
	OOJS_NATIVE_EXIT
}


// awardEquipment(type : equipmentInfoExpression) : Boolean
static JSBool ShipAwardEquipment(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity					*thisEnt = nil;
	OOEquipmentType				*eqType = nil;
	NSString					*identifier = nil;
	BOOL						OK = YES;
	BOOL						berth;
	BOOL            isRepair = NO;
	
	GET_THIS_SHIP(thisEnt);
	
	if (argc > 0)  eqType = JSValueToEquipmentType(context, OOJS_ARGV[0]);
	if (EXPECT_NOT(eqType == nil))
	{
		OOJSReportBadArguments(context, @"Ship", @"awardEquipment", MIN(argc, 1U), OOJS_ARGV, nil, @"equipment type");
		return NO;
	}
	
	// Check that equipment is permitted.
	identifier = [eqType identifier];
	berth = [identifier isEqualToString:@"EQ_PASSENGER_BERTH"];
	if (berth)
	{
		OK = [thisEnt availableCargoSpace] >= [eqType requiredCargoSpace];
	}
	else if ([identifier isEqualToString:@"EQ_FUEL"])
	{
		OK = NO;
	}
	else
	{
		OK = [eqType canCarryMultiple] || ![thisEnt hasEquipmentItem:identifier];
	}
	
	if (OK)
	{
		if ([thisEnt isPlayer])
		{
			PlayerEntity *player = (PlayerEntity *)thisEnt;
			
			if ([identifier isEqualToString:@"EQ_MISSILE_REMOVAL"])
			{
				[player removeMissiles];
			}
			else if ([eqType isMissileOrMine])
			{
				OK = [player mountMissileWithRole:identifier];
			}
			else if (berth)
			{
				OK = [player changePassengerBerths: +1];
			}
			else if ([identifier isEqualToString:@"EQ_PASSENGER_BERTH_REMOVAL"])
			{
				OK = [player changePassengerBerths: -1];
			}
			else
			{
				isRepair = [thisEnt hasEquipmentItem:[identifier stringByAppendingString:@"_DAMAGED"]];
				OK = [player addEquipmentItem:identifier withValidation:YES inContext:@"scripted"];
				if (OK && isRepair) 
				{
					[player doScriptEvent:OOJSID("equipmentRepaired") withArgument:identifier];
				}
			}
		}
		else
		{
			if ([identifier isEqualToString:@"EQ_MISSILE_REMOVAL"])
			{
				[thisEnt removeMissiles];
			}
			// no passenger handling for NPCs. EQ_CARGO_BAY is dealt with inside addEquipmentItem
			else if (!berth && ![identifier isEqualToString:@"EQ_PASSENGER_BERTH_REMOVAL"])
			{
				OK = [thisEnt addEquipmentItem:identifier withValidation:YES inContext:@"scripted"];	
			}
			else
			{
				OK = NO;
			}
		}
	}
	
	OOJS_RETURN_BOOL(OK);
	
	OOJS_NATIVE_EXIT
}


// removeEquipment(type : equipmentInfoExpression)
static JSBool ShipRemoveEquipment(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity					*thisEnt = nil;
	NSString					*key = nil;
	BOOL						OK = YES;
	
	GET_THIS_SHIP(thisEnt);
	
	if (argc > 0)  key = JSValueToEquipmentKey(context, OOJS_ARGV[0]);
	if (EXPECT_NOT(key == nil))
	{
		OOJSReportBadArguments(context, @"Ship", @"removeEquipment", MIN(argc, 1U), OOJS_ARGV, nil, @"equipment type");
		return NO;
	}
	// berths are not in hasOneEquipmentItem
	OK = [thisEnt hasOneEquipmentItem:key includeMissiles:YES whileLoading:NO] || ([key isEqualToString:@"EQ_PASSENGER_BERTH"] && [thisEnt passengerCapacity] > 0);
	if (!OK)
	{
		// Allow removal of damaged equipment.
		key = [key stringByAppendingString:@"_DAMAGED"];
		OK = [thisEnt hasOneEquipmentItem:key includeMissiles:NO whileLoading:NO];
	}
	if (OK)
	{
		//exceptions
		if ([key isEqualToString:@"EQ_PASSENGER_BERTH"] || [key isEqualToString:@"EQ_CARGO_BAY"])
		{
			if ([key isEqualToString:@"EQ_PASSENGER_BERTH"])
			{
				if ([thisEnt passengerCapacity] > [thisEnt passengerCount])
				{
					// must be the player's ship!
					if ([thisEnt isPlayer]) [(PlayerEntity*)thisEnt changePassengerBerths:-1];
				}
				else OK = NO;
			}
			else	// EQ_CARGO_BAY
			{
				if ([thisEnt extraCargo] <= [thisEnt availableCargoSpace])
				{
					[thisEnt removeEquipmentItem:key];
				}
				else OK = NO;
			}
		}
		else
			[thisEnt removeEquipmentItem:key];
	}
	
	OOJS_RETURN_BOOL(OK);
	
	OOJS_NATIVE_EXIT
}


// restoreSubEntities(): boolean
static JSBool ShipRestoreSubEntities(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nil;
	NSUInteger				numSubEntitiesRestored = 0U;
	
	GET_THIS_SHIP(thisEnt);
	
	NSUInteger subCount = [[thisEnt subEntitiesForScript] count];
	
	[thisEnt clearSubEntities];
	[thisEnt setUpSubEntities];
	
	if ([[thisEnt subEntitiesForScript] count] - subCount > 0)  numSubEntitiesRestored = [[thisEnt subEntitiesForScript] count] - subCount;
	
	// for each subentity restored, slightly increase the trade-in factor
	if ([thisEnt isPlayer])
	{
		int tradeInFactorChange = (int)MAX(PLAYER_SHIP_SUBENTITY_TRADE_IN_VALUE * numSubEntitiesRestored, 25U);
		[(PlayerEntity *)thisEnt adjustTradeInFactorBy:tradeInFactorChange];
	}
	
	OOJS_RETURN_BOOL(numSubEntitiesRestored > 0);
	
	OOJS_NATIVE_EXIT
}



// setEquipmentStatus(type : equipmentInfoExpression, status : String): boolean
static JSBool ShipSetEquipmentStatus(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	// equipment status accepted: @"EQUIPMENT_OK", @"EQUIPMENT_DAMAGED"
	
	ShipEntity				*thisEnt = nil;
	OOEquipmentType			*eqType = nil;
	NSString				*key = nil;
	NSString				*damagedKey = nil;
	NSString				*status = nil;
	BOOL					hasOK = NO, hasDamaged = NO;
	
	GET_THIS_SHIP(thisEnt);
	
	if (argc < 2)
	{
		OOJSReportBadArguments(context, @"Ship", @"setEquipmentStatus", argc, OOJS_ARGV, nil, @"equipment type and status");
		return NO;
	}
	
	eqType = JSValueToEquipmentType(context, OOJS_ARGV[0]);
	if (EXPECT_NOT(eqType == nil))
	{
		OOJSReportBadArguments(context, @"Ship", @"setEquipmentStatus", 1, &OOJS_ARGV[0], nil, @"equipment type");
		return NO;
	}
	
	status = OOStringFromJSValue(context, OOJS_ARGV[1]);
	if (EXPECT_NOT(status == nil))
	{
		OOJSReportBadArguments(context, @"Ship", @"setEquipmentStatus", 1, &OOJS_ARGV[1], nil, @"equipment status");
		return NO;
	}
	
	// EMMSTRAN: use interned strings.
	if (![status isEqualToString:@"EQUIPMENT_OK"] && ![status isEqualToString:@"EQUIPMENT_DAMAGED"])
	{
		OOJSReportErrorForCaller(context, @"Ship", @"setEquipmentStatus", @"Second parameter for setEquipmentStatus must be either \"EQUIPMENT_OK\" or \"EQUIPMENT_DAMAGED\".");
		return NO;
	}
	
	key = [eqType identifier];
	hasOK = [thisEnt hasEquipmentItem:key];
	if ([eqType canBeDamaged])
	{
		damagedKey = [key stringByAppendingString:@"_DAMAGED"];
		hasDamaged = [thisEnt hasEquipmentItem:damagedKey];
		
		if (([status isEqualToString:@"EQUIPMENT_OK"] && hasDamaged) || ([status isEqualToString:@"EQUIPMENT_DAMAGED"] && hasOK))
		{
			// the implementation is identical between player and ship.
			[thisEnt removeEquipmentItem:key];
			if ([thisEnt isPlayer])
			{
				// these player methods are different to the ship ones.
				[(PlayerEntity*)thisEnt addEquipmentItem:(hasOK ? damagedKey : key) withValidation:NO inContext:@"scripted"];
				if (hasOK)
				{
					[(PlayerEntity*)thisEnt doScriptEvent:OOJSID("equipmentDamaged") withArgument:key];
				}
				else if (hasDamaged)
				{
					[(PlayerEntity*)thisEnt doScriptEvent:OOJSID("equipmentRepaired") withArgument:key];
				}
				
				// if player's Docking Computers are set to EQUIPMENT_DAMAGED while on, stop them
				if (hasOK && [key isEqualToString:@"EQ_DOCK_COMP"])  [(PlayerEntity*)thisEnt disengageAutopilot];
			}
			else
			{
				[thisEnt addEquipmentItem:(hasOK ? damagedKey : key) withValidation:NO  inContext:@"scripted"];
				if (hasOK) [thisEnt doScriptEvent:OOJSID("equipmentDamaged") withArgument:key];
			}
		}
	}
	else
	{
		if (hasOK && ![status isEqualToString:@"EQUIPMENT_OK"])
		{
			OOJSReportWarningForCaller(context, @"Ship", @"setEquipmentStatus", @"Equipment %@ cannot be damaged.", key);
			hasOK = NO;
		}
	}
	
	OOJS_RETURN_BOOL(hasOK || hasDamaged);
	
	OOJS_NATIVE_EXIT
}


// equipmentStatus(type : equipmentInfoExpression) : String
static JSBool ShipEquipmentStatus(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	/*
		Interned string constants.
		Interned strings are guaranteed to survive for the lifetime of the JS
		runtime, which lasts as long as Oolite is running.
	*/
	static jsval strOK, strDamaged, strUnavailable, strUnknown;
	static BOOL inited = NO;
	if (EXPECT_NOT(!inited))
	{
		inited = YES;
		strOK = STRING_TO_JSVAL(JS_InternString(context, "EQUIPMENT_OK"));
		strDamaged = STRING_TO_JSVAL(JS_InternString(context, "EQUIPMENT_DAMAGED"));
		strUnavailable = STRING_TO_JSVAL(JS_InternString(context, "EQUIPMENT_UNAVAILABLE"));
		strUnknown = STRING_TO_JSVAL(JS_InternString(context, "EQUIPMENT_UNKNOWN"));
	}
	
	ShipEntity				*thisEnt = nil;
	NSString				*key = nil;
	
	GET_THIS_SHIP(thisEnt);
	
	if (argc > 0)  key = JSValueToEquipmentKey(context, OOJS_ARGV[0]);
	if (EXPECT_NOT(key == nil))
	{
		if (argc > 0 && JSVAL_IS_STRING(OOJS_ARGV[0]))
		{
			OOJS_RETURN(strUnknown);
		}
		
		OOJSReportBadArguments(context, @"Ship", @"equipmentStatus", MIN(argc, 1U), &OOJS_ARGV[0], nil, @"equipment type");
		return NO;
	}
	
	if ([thisEnt hasEquipmentItem:key includeWeapons:YES whileLoading:NO])  OOJS_RETURN(strOK);
	else if ([thisEnt hasEquipmentItem:[key stringByAppendingString:@"_DAMAGED"]])  OOJS_RETURN(strDamaged);
	
	OOJS_RETURN(strUnavailable);
	
	OOJS_NATIVE_EXIT
}


// selectNewMissile()
static JSBool ShipSelectNewMissile(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nil;
	
	GET_THIS_SHIP(thisEnt);
	
	NSString *result = [[thisEnt selectMissile] identifier];
	// if there's a badly defined missile, selectMissile may return nil
	if (result == nil)  result = @"EQ_MISSILE";
	
	OOJS_RETURN_OBJECT(result);
	
	OOJS_NATIVE_EXIT
}


// fireMissile()
static JSBool ShipFireMissile(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity			*thisEnt = nil;
	id					result = nil;
	
	GET_THIS_SHIP(thisEnt);
	
	if (argc > 0)  result = [thisEnt fireMissileWithIdentifier:OOStringFromJSValue(context, OOJS_ARGV[0]) andTarget:[thisEnt primaryTarget]];
	else  result = [thisEnt fireMissile];
	
	OOJS_RETURN_OBJECT(result);
	
	OOJS_NATIVE_EXIT
}


// findNearestStation
static JSBool ShipFindNearestStation(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity			*thisEnt = nil;
	StationEntity		*result = nil;

	GET_THIS_SHIP(thisEnt);

	double				sdist, distance = 1E32;
	
	NSEnumerator		*statEnum = [[UNIVERSE stations] objectEnumerator];
	StationEntity		*se = nil;
	while ((se = [statEnum nextObject]))
	{
		sdist = HPdistance2([thisEnt position],[se position]);

		if (sdist < distance)
		{
			distance = sdist;
			result = se;
		}
	}
	
	OOJS_RETURN_OBJECT(result);
	
	OOJS_NATIVE_EXIT
}


// setBounty(amount, reason)
static JSBool ShipSetBounty(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nil;
	NSString				*reason = nil;
	int32					newbounty = 0;
	BOOL					gotBounty = YES;
	
	GET_THIS_SHIP(thisEnt);
	
	if (argc > 0)  gotBounty = JS_ValueToInt32(context, OOJS_ARGV[0], &newbounty);
	if (argc > 1)  reason = OOStringFromJSValue(context, OOJS_ARGV[1]);
	if (EXPECT_NOT(reason == nil || !gotBounty || newbounty < 0))
	{
		OOJSReportBadArguments(context, @"Ship", @"setBounty", argc, OOJS_ARGV, nil, @"new bounty and reason");
		return NO;
	}
	
	[thisEnt setBounty:(OOCreditsQuantity)newbounty withReasonAsString:reason];
	
	return YES;
	
	OOJS_NATIVE_EXIT
}


// setCargo(cargoType : String [, number : count])
static JSBool ShipSetCargo(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nil;
	NSString				*cargoType = nil;
	OOCommodityType			commodity = COMMODITY_UNDEFINED;
	int32					count = 1;
	BOOL					gotCount = YES;
	
	GET_THIS_SHIP(thisEnt);
	
	if (argc > 0)  cargoType = OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (argc > 1)  gotCount = JS_ValueToInt32(context, OOJS_ARGV[1], &count);
	if (EXPECT_NOT(cargoType == nil || !gotCount || count < 1))
	{
		OOJSReportBadArguments(context, @"Ship", @"setCargo", argc, OOJS_ARGV, nil, @"cargo name and optional positive quantity");
		return NO;
	}
	
	commodity = [UNIVERSE commodityForName:cargoType];
	if (commodity != COMMODITY_UNDEFINED)  [thisEnt setCommodityForPod:commodity andAmount:count];
	
	OOJS_RETURN_BOOL(commodity != COMMODITY_UNDEFINED);
	
	OOJS_NATIVE_EXIT
}


// setCargoType(cargoType : String)
static JSBool ShipSetCargoType(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nil;
	NSString				*cargoType = nil;
	
	GET_THIS_SHIP(thisEnt);
	
	if (argc > 0)  cargoType = OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (EXPECT_NOT(cargoType == nil))
	{
		OOJSReportBadArguments(context, @"Ship", @"setCargoType", argc, OOJS_ARGV, nil, @"cargo type name");
		return NO;
	}
	if ([thisEnt cargoType] != CARGO_NOT_CARGO)
	{
		OOJSReportBadArguments(context, @"Ship", @"setCargoType", argc, OOJS_ARGV, nil, [NSString stringWithFormat:@"Can only be used on cargo pod carriers, not cargo pods (%@)",[thisEnt shipDataKey]]);
		return NO;
	}
	BOOL ok = YES;
	if ([cargoType isEqualToString:@"SCARCE_GOODS"])
	{
		[thisEnt setCargoFlag:CARGO_FLAG_FULL_SCARCE];
	}
	else if ([cargoType isEqualToString:@"PLENTIFUL_GOODS"])
	{
		[thisEnt setCargoFlag:CARGO_FLAG_FULL_PLENTIFUL];
	}
	else if ([cargoType isEqualToString:@"MEDICAL_GOODS"])
	{
		[thisEnt setCargoFlag:CARGO_FLAG_FULL_MEDICAL];
	}
	else if ([cargoType isEqualToString:@"ILLEGAL_GOODS"])
	{
		[thisEnt setCargoFlag:CARGO_FLAG_FULL_CONTRABAND];
	}
	else if ([cargoType isEqualToString:@"PIRATE_GOODS"])
	{
		[thisEnt setCargoFlag:CARGO_FLAG_PIRATE];
	}	
	else
	{
		ok = NO;
	}
	OOJS_RETURN_BOOL(ok);

	OOJS_NATIVE_EXIT
}

// setMaterials(params: dict, [shaders: dict])  // sets materials dictionary. Optional parameter sets the shaders dictionary too.
static JSBool ShipSetMaterials(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nil;
	
	if (argc < 1)
	{
		OOJSReportBadArguments(context, @"Ship", @"setMaterials", 0, OOJS_ARGV, nil, @"parameter object");
		return NO;
	}
	
	GET_THIS_SHIP(thisEnt);
	
	return ShipSetMaterialsInternal(context, argc, vp, thisEnt, NO);
	
	OOJS_NATIVE_EXIT
}


// setShaders(params: dict) 
static JSBool ShipSetShaders(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nil;
	
	GET_THIS_SHIP(thisEnt);
	
	if (argc < 1)
	{
		OOJSReportBadArguments(context, @"Ship", @"setShaders", 0, OOJS_ARGV, nil, @"parameter object");
		return NO;
	}
	
	if (JSVAL_IS_NULL(OOJS_ARGV[0]) || (!JSVAL_IS_NULL(OOJS_ARGV[0]) && !JSVAL_IS_OBJECT(OOJS_ARGV[0])))
	{
		// EMMSTRAN: JS_ValueToObject() and normal error handling here.
		OOJSReportWarning(context, @"Ship.%@: expected %@ instead of '%@'.", @"setShaders", @"object", OOStringFromJSValueEvenIfNull(context, OOJS_ARGV[0]));
		OOJS_RETURN_BOOL(NO);
	}
	
	OOJS_ARGV[1] = OOJS_ARGV[0];
	return ShipSetMaterialsInternal(context, argc, vp, thisEnt, YES);
	
	OOJS_NATIVE_EXIT
}


static JSBool ShipSetMaterialsInternal(JSContext *context, uintN argc, jsval *vp, ShipEntity *thisEnt, BOOL fromShaders)
{
	OOJS_PROFILE_ENTER
	
	JSObject				*params = NULL;
	NSDictionary			*materials;
	NSDictionary			*shaders;
	BOOL					withShaders = NO;
	BOOL					success = NO;
	
	GET_THIS_SHIP(thisEnt);
	
	if (JSVAL_IS_NULL(OOJS_ARGV[0]) || (!JSVAL_IS_NULL(OOJS_ARGV[0]) && !JSVAL_IS_OBJECT(OOJS_ARGV[0])))
	{
		OOJSReportWarning(context, @"Ship.%@: expected %@ instead of '%@'.", @"setMaterials", @"object", OOStringFromJSValueEvenIfNull(context, OOJS_ARGV[0]));
		OOJS_RETURN_BOOL(NO);
	}
	
	if (argc > 1)
	{
		withShaders = YES;
		if (JSVAL_IS_NULL(OOJS_ARGV[1]) || (!JSVAL_IS_NULL(OOJS_ARGV[1]) && !JSVAL_IS_OBJECT(OOJS_ARGV[1])))
		{
			OOJSReportWarning(context, @"Ship.%@: expected %@ instead of '%@'.",  @"setMaterials", @"object as second parameter", OOStringFromJSValueEvenIfNull(context, OOJS_ARGV[1]));
			withShaders = NO;
		}
	}
	
	if (fromShaders)
	{
		materials = [[thisEnt mesh] materials];
		params = JSVAL_TO_OBJECT(OOJS_ARGV[0]);
		shaders = OOJSNativeObjectFromJSObject(context, params);
	}
	else
	{
		params = JSVAL_TO_OBJECT(OOJS_ARGV[0]);
		materials = OOJSNativeObjectFromJSObject(context, params);
		if (withShaders)
		{
			params = JSVAL_TO_OBJECT(OOJS_ARGV[1]);
			shaders = OOJSNativeObjectFromJSObject(context, params);
		}
		else
		{
			shaders = [[thisEnt mesh] shaders];
		}
	}
	
	OOJS_BEGIN_FULL_NATIVE(context)
	NSDictionary 			*shipDict = [thisEnt shipInfoDictionary];
	
	// First we test to see if we can create the mesh.
	OOMesh *mesh = [OOMesh meshWithName:[shipDict oo_stringForKey:@"model"]
							   cacheKey:nil
					 materialDictionary:materials
					  shadersDictionary:shaders
								 smooth:[shipDict oo_boolForKey:@"smooth" defaultValue:NO]
						   shaderMacros:[[ResourceManager materialDefaults] oo_dictionaryForKey:@"ship-prefix-macros"]
					shaderBindingTarget:thisEnt];
	
	if (mesh != nil)
	{
		[thisEnt setMesh:mesh];
		success = YES;
	}
	OOJS_END_FULL_NATIVE
	
	OOJS_RETURN_BOOL(success);
	
	OOJS_PROFILE_EXIT
}


// exitSystem([int systemID])
static JSBool ShipExitSystem(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity			*thisEnt = nil;
	int32				systemID = -1;
	BOOL				OK = NO;
	
	GET_THIS_SHIP(thisEnt);
	if (EXPECT_NOT([thisEnt isPlayer]))
	{
		OOJSReportErrorForCaller(context, @"Ship", @"exitSystem", @"Not valid for player ship.");
		return NO;
	}
	
	if (argc > 0)
	{
		if (!JS_ValueToInt32(context, OOJS_ARGV[0], &systemID) || systemID < 0 || 255 < systemID)
		{
			OOJSReportBadArguments(context, @"Ship", @"exitSystem", MIN(argc, 1U), OOJS_ARGV, nil, @"system ID");
			return NO;
		}
	}
	
	OK = [thisEnt performHyperSpaceToSpecificSystem:systemID]; 	// -1 == random destination system
	
	OOJS_RETURN_BOOL(OK);
	
	OOJS_NATIVE_EXIT
}


static JSBool ShipUpdateEscortFormation(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity *thisEnt = nil;
	GET_THIS_SHIP(thisEnt);
	[thisEnt updateEscortFormation];
	
	OOJS_RETURN_VOID;
	
	OOJS_PROFILE_EXIT
}

static BOOL RemoveOrExplodeShip(JSContext *context, uintN argc, jsval *vp, BOOL explode)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity				*thisEnt = nil;
	
	GET_THIS_SHIP(thisEnt);
	
	if (EXPECT_NOT([thisEnt isPlayer]))
	{
		NSCAssert(explode, @"RemoveOrExplodeShip(): shouldn't be called for player with !explode.");	// player.ship.remove() is blocked by caller.
		PlayerEntity *player = (PlayerEntity *)thisEnt;
		
		if ([player isDocked])
		{
			OOJSReportError(context, @"Cannot explode() player's ship while docked.");
			return NO;
		}
	}
	
	if (thisEnt == (ShipEntity *)[UNIVERSE station])
	{
		// Allow exploding of main station (e.g. nova mission)
		[UNIVERSE unMagicMainStation];
	}
	
	[thisEnt setSuppressExplosion:!explode];
	[thisEnt setEnergy:1];
	[thisEnt takeEnergyDamage:500000000.0 from:nil becauseOf:nil];
	
	OOJS_RETURN_VOID;
	
	OOJS_PROFILE_EXIT
}

static JSBool ShipClearDefenseTargets(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity *thisEnt = nil;
	GET_THIS_SHIP(thisEnt);
	[thisEnt removeAllDefenseTargets];
	
	OOJS_RETURN_VOID;
	
	OOJS_PROFILE_EXIT
}


static JSBool ShipAddDefenseTarget(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity *thisEnt = nil;
	ShipEntity				*target = nil;

	GET_THIS_SHIP(thisEnt);
	if (EXPECT_NOT(argc == 0 || (argc > 0 && (JSVAL_IS_NULL(OOJS_ARGV[0]) || !JSVAL_IS_OBJECT(OOJS_ARGV[0]) || !JSShipGetShipEntity(context, JSVAL_TO_OBJECT(OOJS_ARGV[0]), &target)))))
	{
		OOJSReportBadArguments(context, @"Ship", @"addDefenseTarget", 1U, OOJS_ARGV, nil, @"target");
		return NO;
	}
	
	[thisEnt addDefenseTarget:target];

	OOJS_RETURN_VOID;
	
	OOJS_PROFILE_EXIT
}


static JSBool ShipRemoveDefenseTarget(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity *thisEnt = nil;
	ShipEntity				*target = nil;

	GET_THIS_SHIP(thisEnt);
	if (EXPECT_NOT(argc == 0 || (argc > 0 && (JSVAL_IS_NULL(OOJS_ARGV[0]) || !JSVAL_IS_OBJECT(OOJS_ARGV[0]) || !JSShipGetShipEntity(context, JSVAL_TO_OBJECT(OOJS_ARGV[0]), &target)))))
	{
		OOJSReportBadArguments(context, @"Ship", @"removeDefenseTarget", 1U, OOJS_ARGV, nil, @"target");
		return NO;
	}
	
	[thisEnt removeDefenseTarget:target];

	OOJS_RETURN_VOID;
	
	OOJS_PROFILE_EXIT
}


//getMaterials()
static JSBool ShipGetMaterials(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity		*thisEnt = nil;
	NSObject			*result = nil;
	
	GET_THIS_SHIP(thisEnt);
	
	result = [[thisEnt mesh] materials];
	if (result == nil)  result = [NSDictionary dictionary];
	OOJS_RETURN_OBJECT(result);
	
	OOJS_PROFILE_EXIT
}

//getShaders()
static JSBool ShipGetShaders(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity		*thisEnt = nil;
	NSObject		*result = nil;
	
	GET_THIS_SHIP(thisEnt);
	
	result = [[thisEnt mesh] shaders];
	if (result == nil)  result = [NSDictionary dictionary];
	OOJS_RETURN_OBJECT(result);
	
	OOJS_PROFILE_EXIT
}

static JSBool ShipBroadcastCascadeImminent(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity *thisEnt = nil;
	GET_THIS_SHIP(thisEnt);
	[thisEnt broadcastEnergyBlastImminent];
	
	OOJS_RETURN_VOID;
	
	OOJS_PROFILE_EXIT
}

static JSBool ShipBecomeCascadeExplosion(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity *thisEnt = nil;
	GET_THIS_SHIP(thisEnt);
	[thisEnt becomeEnergyBlast];
	
	OOJS_RETURN_VOID;
	
	OOJS_PROFILE_EXIT
}


static JSBool ShipOfferToEscort(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity *thisEnt = nil;
	ShipEntity				*mother = nil;

	GET_THIS_SHIP(thisEnt);
	if (EXPECT_NOT(argc == 0 || (argc > 0 && (JSVAL_IS_NULL(OOJS_ARGV[0]) || !JSVAL_IS_OBJECT(OOJS_ARGV[0]) || !JSShipGetShipEntity(context, JSVAL_TO_OBJECT(OOJS_ARGV[0]), &mother)))))
	{
		OOJSReportBadArguments(context, @"Ship", @"offerToEscort", 1U, OOJS_ARGV, nil, @"target");
		return NO;
	}
	
	BOOL result = [thisEnt suggestEscortTo:mother];

	OOJS_RETURN_BOOL(result);
	
	OOJS_PROFILE_EXIT
}


static JSBool ShipRequestHelpFromGroup(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity *thisEnt = nil;

	GET_THIS_SHIP(thisEnt);
	
	[thisEnt groupAttackTarget];

	OOJS_RETURN_VOID;
	
	OOJS_PROFILE_EXIT
}


static JSBool ShipPatrolReportIn(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity *thisEnt = nil;
	ShipEntity				*target = nil;

	GET_THIS_SHIP(thisEnt);
	if (EXPECT_NOT(argc == 0 || (argc > 0 && (JSVAL_IS_NULL(OOJS_ARGV[0]) || !JSVAL_IS_OBJECT(OOJS_ARGV[0]) || !JSShipGetShipEntity(context, JSVAL_TO_OBJECT(OOJS_ARGV[0]), &target)))))
	{
		OOJSReportBadArguments(context, @"Ship", @"addDefenseTarget", 1U, OOJS_ARGV, nil, @"target");
		return NO;
	}
	if ([target isStation])
	{
		StationEntity *station = (StationEntity*)target;
		[station acceptPatrolReportFrom:thisEnt];
	}

	OOJS_RETURN_VOID;
	
	OOJS_PROFILE_EXIT
}


static JSBool ShipMarkTargetForFines(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity *thisEnt = nil;

	GET_THIS_SHIP(thisEnt);

	ShipEntity *ship = [thisEnt primaryTarget];
	BOOL ok = NO;
	if ((ship != nil) && ([ship status] != STATUS_DEAD) && ([ship status] != STATUS_DOCKED))
	{
		ok = [ship markForFines];
	}

	OOJS_RETURN_BOOL(ok);
	
	OOJS_PROFILE_EXIT
}


static JSBool ShipEnterWormhole(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity *thisEnt = nil;
	Entity	*hole = nil;

	if ([PLAYER status] != STATUS_ENTERING_WITCHSPACE)
	{
		OOJSReportError(context, @"Cannot use this function while player's ship not entering witchspace.");
		return NO;
	}

	GET_THIS_SHIP(thisEnt);
	if (EXPECT_NOT(argc == 0 || (argc > 0 && !JSVAL_IS_NULL(OOJS_ARGV[0]) && (!JSVAL_IS_OBJECT(OOJS_ARGV[0]) || !OOJSEntityGetEntity(context, JSVAL_TO_OBJECT(OOJS_ARGV[0]), &hole)))))
	{
		[thisEnt enterPlayerWormhole];
	}
	else 
	{
		if (![hole isWormhole])
		{
			OOJSReportBadArguments(context, @"Ship", @"enterWormhole", 1U, OOJS_ARGV, nil, @"[wormhole]");
			return NO;
		}

		[thisEnt enterWormhole:(WormholeEntity*)hole];
	}

	OOJS_RETURN_VOID;
	
	OOJS_PROFILE_EXIT
}


static JSBool ShipNotifyGroupOfWormhole(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity *thisEnt = nil;
	GET_THIS_SHIP(thisEnt);

	[thisEnt wormholeEntireGroup];

	OOJS_RETURN_VOID;
	
	OOJS_PROFILE_EXIT
}


static JSBool ShipThrowSpark(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity *thisEnt = nil;
	GET_THIS_SHIP(thisEnt);
	[thisEnt setThrowSparks:YES];
	
	OOJS_RETURN_VOID;
	
	OOJS_PROFILE_EXIT
}



static JSBool ShipPerformAttack(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity *thisEnt = nil;
	GET_THIS_SHIP(thisEnt);
	[thisEnt performAttack];
	
	OOJS_RETURN_VOID;
	
	OOJS_PROFILE_EXIT
}


static JSBool ShipPerformCollect(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity *thisEnt = nil;
	GET_THIS_SHIP(thisEnt);
	[thisEnt performCollect];
	
	OOJS_RETURN_VOID;
	
	OOJS_PROFILE_EXIT
}


static JSBool ShipPerformEscort(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity *thisEnt = nil;
	GET_THIS_SHIP(thisEnt);
	[thisEnt performEscort];
	
	OOJS_RETURN_VOID;
	
	OOJS_PROFILE_EXIT
}


static JSBool ShipPerformFaceDestination(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity *thisEnt = nil;
	GET_THIS_SHIP(thisEnt);
	[thisEnt performFaceDestination];
	
	OOJS_RETURN_VOID;
	
	OOJS_PROFILE_EXIT
}


static JSBool ShipPerformFlee(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity *thisEnt = nil;
	GET_THIS_SHIP(thisEnt);
	[thisEnt performFlee];
	
	OOJS_RETURN_VOID;
	
	OOJS_PROFILE_EXIT
}


static JSBool ShipPerformFlyToRangeFromDestination(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity *thisEnt = nil;
	GET_THIS_SHIP(thisEnt);
	[thisEnt performFlyToRangeFromDestination];
	
	OOJS_RETURN_VOID;
	
	OOJS_PROFILE_EXIT
}


static JSBool ShipPerformHold(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity *thisEnt = nil;
	GET_THIS_SHIP(thisEnt);
	[thisEnt performHold];
	
	OOJS_RETURN_VOID;
	
	OOJS_PROFILE_EXIT
}


static JSBool ShipPerformIdle(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity *thisEnt = nil;
	GET_THIS_SHIP(thisEnt);
	[thisEnt performIdle];
	
	OOJS_RETURN_VOID;
	
	OOJS_PROFILE_EXIT
}


static JSBool ShipPerformIntercept(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity *thisEnt = nil;
	GET_THIS_SHIP(thisEnt);
	[thisEnt performIntercept];
	
	OOJS_RETURN_VOID;
	
	OOJS_PROFILE_EXIT
}


static JSBool ShipPerformLandOnPlanet(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity *thisEnt = nil;
	GET_THIS_SHIP(thisEnt);
	[thisEnt performLandOnPlanet];
	
	OOJS_RETURN_VOID;
	
	OOJS_PROFILE_EXIT
}


static JSBool ShipPerformMining(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity *thisEnt = nil;
	GET_THIS_SHIP(thisEnt);
	[thisEnt performMining];
	
	OOJS_RETURN_VOID;
	
	OOJS_PROFILE_EXIT
}


static JSBool ShipPerformScriptedAI(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity *thisEnt = nil;
	GET_THIS_SHIP(thisEnt);
	[thisEnt performScriptedAI];
	
	OOJS_RETURN_VOID;
	
	OOJS_PROFILE_EXIT
}


static JSBool ShipPerformScriptedAttackAI(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity *thisEnt = nil;
	GET_THIS_SHIP(thisEnt);
	[thisEnt performScriptedAttackAI];
	
	OOJS_RETURN_VOID;
	
	OOJS_PROFILE_EXIT
}


static JSBool ShipPerformStop(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity *thisEnt = nil;
	GET_THIS_SHIP(thisEnt);
	[thisEnt performStop];
	
	OOJS_RETURN_VOID;
	
	OOJS_PROFILE_EXIT
}


static JSBool ShipPerformTumble(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity *thisEnt = nil;
	GET_THIS_SHIP(thisEnt);
	[thisEnt performTumble];
	
	OOJS_RETURN_VOID;
	
	OOJS_PROFILE_EXIT
}


static JSBool ShipRequestDockingInstructions(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity *thisEnt = nil;
	GET_THIS_SHIP(thisEnt);
	[thisEnt requestDockingCoordinates];
	
	OOJS_RETURN_OBJECT([thisEnt dockingInstructions]);
	
	OOJS_PROFILE_EXIT
}


static JSBool ShipRecallDockingInstructions(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity *thisEnt = nil;
	GET_THIS_SHIP(thisEnt);
	[thisEnt recallDockingInstructions];
	
	OOJS_RETURN_OBJECT([thisEnt dockingInstructions]);
	
	OOJS_PROFILE_EXIT
}


static JSBool ShipBroadcastDistressMessage(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity *thisEnt = nil;
	GET_THIS_SHIP(thisEnt);
	[thisEnt broadcastDistressMessageWithDumping:NO];
	
	OOJS_RETURN_VOID;
	
	OOJS_PROFILE_EXIT
}


static JSBool ShipCheckCourseToDestination(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity *thisEnt = nil;
	GET_THIS_SHIP(thisEnt);

	Entity *hazard = [UNIVERSE hazardOnRouteFromEntity:thisEnt toDistance:[thisEnt desiredRange] fromPoint:[thisEnt destination]];

	OOJS_RETURN_OBJECT(hazard);

	OOJS_PROFILE_EXIT
}


static JSBool ShipGetSafeCourseToDestination(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity *thisEnt = nil;
	GET_THIS_SHIP(thisEnt);

	HPVector waypoint = [UNIVERSE getSafeVectorFromEntity:thisEnt toDistance:[thisEnt desiredRange] fromPoint:[thisEnt destination]];

	OOJS_RETURN_HPVECTOR(waypoint);

	OOJS_PROFILE_EXIT

}


static JSBool ShipCheckScanner(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity *thisEnt = nil;
	JSBool	onlyCheckPowered = NO;
	
	GET_THIS_SHIP(thisEnt);
	
	if (argc > 0 && EXPECT_NOT(!JS_ValueToBoolean(context, OOJS_ARGV[0], &onlyCheckPowered)))
	{
		OOJSReportBadArguments(context, @"Ship", @"checkScanner", argc, OOJS_ARGV, nil, @"boolean");
		return NO;
	}

	if (onlyCheckPowered)
	{
		[thisEnt checkScannerIgnoringUnpowered];
	}
	else
	{
		[thisEnt checkScanner];
	}
	ShipEntity **scannedShips = [thisEnt scannedShips];
	unsigned num = [thisEnt numberOfScannedShips];
	NSMutableArray *scanResult = [NSMutableArray array];
	for (unsigned i = 0; i < num ; i++)
	{
		[scanResult addObject:scannedShips[i]];
	}
	OOJS_RETURN_OBJECT(scanResult);

	OOJS_PROFILE_EXIT
}


/* 0 = no significant damage or consumable loss, higher numbers mean some */
static JSBool ShipDamageAssessment(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity *thisEnt = nil;
	NSUInteger	assessment = 0;
	
	GET_THIS_SHIP(thisEnt);
	
	// if could have missiles but doesn't, consumables low
	if ([thisEnt missileCapacity] > 0 && [[thisEnt missilesList] count] == 0)
	{
		assessment++;
	}
	// if has injectors but fuel is low, consumables low
	// if no injectors, not a problem
	if ([thisEnt hasFuelInjection] && [thisEnt fuel] < 35)
	{
		assessment++;
	}

	/* TODO: when NPC equipment can be damaged in combat, assess this
	 * here */

	OOJS_RETURN_INT(assessment);

	OOJS_PROFILE_EXIT
}



static JSBool ShipThreatAssessment(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity *thisEnt = nil;
	JSBool	fullCheck = NO;
	
	GET_THIS_SHIP(thisEnt);
	
	if (argc > 0 && EXPECT_NOT(!JS_ValueToBoolean(context, OOJS_ARGV[0], &fullCheck)))
	{
		OOJSReportBadArguments(context, @"Ship", @"threatAssessment", argc, OOJS_ARGV, nil, @"boolean");
		return NO;
	}
	// start with 1 per ship
	double assessment = 1;
	// +/- 0.1 for speed, larger subtraction for very slow ships
	GLfloat maxspeed = [thisEnt maxFlightSpeed];
	assessment += (maxspeed-300)/1000;
	if (maxspeed < 200)
	{
		assessment += (maxspeed-200)/500;
	}
	
	/* FIXME: at the moment this means NPCs can detect other NPCs shield
	 * boosters, since they're implemented as extra energy */
	assessment += ([thisEnt maxEnergy]-200)/1000; 
	
	// add on some for missiles. Mostly ignore 3rd and subsequent
	// missiles: either they can be ECMd or the first two are already
	// too many.
	if ([thisEnt missileCapacity] > 2)
	{
		assessment += 0.5;
	}
	else
	{
		assessment += ((double)[thisEnt missileCapacity])/5.0;
	}

	/* Turret count is public knowledge */
	NSEnumerator	*subEnum = [thisEnt shipSubEntityEnumerator];
	ShipEntity		*se = nil;
	while ((se = [subEnum nextObject]))
	{
		if ([se isTurret])
		{
			/* TODO: consider making ship combat behaviour try to
			 * stay at long range from enemies with turrets. Then
			 * we could perhaps reduce this bonus a bit. */
			assessment += 1; 
		}
	}

	if (fullCheck)
	{
		// consider pilot skill
		if ([thisEnt isPlayer])
		{
			double score = (double)[PLAYER score];
			if (score > 6400) 
			{
				score = 6400;
			}
			assessment += pow(score,0.33)/10;
			// 0 - 1.8
		}
		else
		{
			assessment += [thisEnt accuracy]/10;
		}

		// check lasers
		OOWeaponType wt = [thisEnt weaponTypeIDForFacing:WEAPON_FACING_FORWARD strict:NO];
		if (wt == WEAPON_NONE)
		{
			assessment -= 1;
		}
		else
		{
			assessment += ShipThreatAssessmentWeapon(wt);
		}
		wt = [thisEnt weaponTypeIDForFacing:WEAPON_FACING_AFT strict:NO];
		if (wt != WEAPON_NONE)
		{
			assessment += 1 + ShipThreatAssessmentWeapon(wt);
		}
		// port and starboard weapons less important
		wt = [thisEnt weaponTypeIDForFacing:WEAPON_FACING_PORT strict:NO];
		if (wt != WEAPON_NONE)
		{
			assessment += 0.2 + ShipThreatAssessmentWeapon(wt)/5.0;
		}
		wt = [thisEnt weaponTypeIDForFacing:WEAPON_FACING_STARBOARD strict:NO];
		if (wt != WEAPON_NONE)
		{
			assessment += 0.2 + ShipThreatAssessmentWeapon(wt)/5.0;
		}

		// combat-related secondary equipment
		if ([thisEnt hasECM])
		{
			assessment += 0.5;
		}
		if ([thisEnt hasFuelInjection])
		{
			assessment += 0.5;
		}

	}
	else
	{
		// consider thargoids dangerous
		if ([thisEnt isThargoid])
		{
			assessment *= 1.5;
			if ([thisEnt hasRole:@"thargoid-mothership"])
			{
				assessment += 2.5;
			}
		}
		else
		{
			// consider that armed ships might have a trick or two
			if ([thisEnt weaponFacings] == 1)
			{
				assessment += 0.25;
			}
			else
			{
				// and more than one trick if they can mount multiple lasers
				assessment += 0.75;
			}
		}
	}

	// mostly ignore fleeing ships as threats
	if ([thisEnt behaviour] == BEHAVIOUR_FLEE_TARGET || [thisEnt behaviour] == BEHAVIOUR_FLEE_EVASIVE_ACTION)
	{
		assessment *= 0.2;
	}
	else if ([thisEnt isPlayer] && [(PlayerEntity*)thisEnt fleeingStatus] >= PLAYER_FLEEING_CARGO)
	{
		assessment *= 0.2;
	}
	
	// don't go too low.
	if (assessment < 0.1)
	{
		assessment = 0.1;
	}

	OOJS_RETURN_DOUBLE(assessment);

	OOJS_PROFILE_EXIT
}

static double ShipThreatAssessmentWeapon(OOWeaponType wt)
{
	switch (wt)
	{
	case WEAPON_NONE:
		return -1;
	case WEAPON_PULSE_LASER:
		return 0;
	case WEAPON_BEAM_LASER:
		return 0.33;
	case WEAPON_MINING_LASER:
		return -0.5;
	case WEAPON_MILITARY_LASER:
	case WEAPON_THARGOID_LASER:
		return 1.0;
	default:
		return 0;
	}
}


/** Static methods */

static JSBool ShipStaticKeys(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context);
	OOShipRegistry			*registry = [OOShipRegistry sharedRegistry];

	NSArray *keys = [registry shipKeys];
	OOJS_RETURN_OBJECT(keys);		

	OOJS_NATIVE_EXIT
}

static JSBool ShipStaticKeysForRole(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context);
	OOShipRegistry			*registry = [OOShipRegistry sharedRegistry];

	if (argc > 0)
	{
		NSString *role = OOStringFromJSValue(context, OOJS_ARGV[0]);
		NSArray *keys = [registry shipKeysWithRole:role];
		OOJS_RETURN_OBJECT(keys);		
	}
	else
	{
		OOJSReportBadArguments(context, @"Ship", @"shipKeysForRole", MIN(argc, 1U), OOJS_ARGV, nil, @"ship role");
		return NO;
	}

	OOJS_NATIVE_EXIT
}


static JSBool ShipStaticRoleIsInCategory(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context);

	if (argc > 1)
	{
		NSString *role = OOStringFromJSValue(context, OOJS_ARGV[0]);
		NSString *category = OOStringFromJSValue(context, OOJS_ARGV[1]);

		OOJS_RETURN_BOOL([UNIVERSE role:role isInCategory:category]);		
	}
	else
	{
		OOJSReportBadArguments(context, @"Ship", @"roleIsInCategory", MIN(argc, 2U), OOJS_ARGV, nil, @"role, category");
		return NO;
	}

	OOJS_NATIVE_EXIT
}


static JSBool ShipStaticRoles(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context);
	OOShipRegistry			*registry = [OOShipRegistry sharedRegistry];

	NSArray *keys = [registry shipRoles];
	OOJS_RETURN_OBJECT(keys);		

	OOJS_NATIVE_EXIT
}
