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

#include "OOJSShip.h"
#include "OOJSEntity.h"
#include "OOJSWormhole.h"
#include "OOJSVector.h"
#include "OOJSQuaternion.h"
#include "OOJSEquipmentInfo.h"
#include "OOJavaScriptEngine.h"
#include "ShipEntity.h"
#include "ShipEntityAI.h"
#include "ShipEntityScriptMethods.h"
#include "StationEntity.h"
#include "WormholeEntity.h"
#include "AI.h"
#include "OOStringParsing.h"
#include "EntityOOJavaScriptExtensions.h"
#include "OORoleSet.h"
#include "OOJSPlayer.h"
#include "PlayerEntity.h"
#include "PlayerEntityScriptMethods.h"
#include "OOShipGroup.h"
#include "GameController.h"
#include "OOShipRegistry.h"
#include "OOEquipmentType.h"
#include "ResourceManager.h"
#include "OOMesh.h"
#include "OOConstToString.h"
#include "OOEntityFilterPredicate.h"
#include "OOCharacter.h"
#include "OOCallByName.h"
#include "oofnd/objc/OOAssert.h"
#include "OOObjCPList.h"
#include "OOColor.h"
#include "OOCommodities.h"
#include "OOScript.h"
#include "PlayerEntityLegacyScriptEngine.h"
#include "Universe.h"
#include "oofnd/String.hpp"

/*
	Converted slice by slice to C++20 (docs/phases/3-slices/OOJSShip.md; proposed ADR-0056,
	amendments oo-ppc, oo-luhd, oo-ft5n and oo-9ht.139). A converted native or helper has no
	Objective-C: BOOL/YES/NO/nil are bool/true/false/nullptr; the ship it wraps is reached as
	ShipEntity through oo::ToCxx (its members an Objective-C subclass overrides are virtual,
	so dispatch is as before), the converted classes the ship hands out (AI, OORoleSet,
	OOShipGroup, OOColor, OONativeVector) as cxx:: classes, null-guarded where a message to nil
	answered; and a send to a class that was still Objective-C (the player, the universe) was a
	one-line function in the binding's bridge file until bead oo-9ht.181 inlined each one at its
	call (a member call on the C++ player, a message to the universe) and deleted the file.
	Slice 1 (bead oo-18mg2): ShipGetProperty() and
	its helpers. Slice 2 (bead oo-chjz4): ShipSetProperty(). Slice 3 (bead oo-08plt): the AI and
	script, escort, role, cargo, spawn, damage, removal, legacy-action, comms, ECM and abandon
	natives. Slice 4 (bead oo-hqe5l): equipment, missiles, nearest station, bounty, cargo, crew,
	materials and shaders. Slice 5 (bead oo-qzn25): system exit, escort formation, defence targets,
	collision exceptions, cascades, group, escort and patrol, wormholes, docking instructions,
	distress and course. Slice 6 (bead oo-ljuy1): the perform* behaviours, the scanner, cargo
	adjustment, damage and threat assessment, and the static methods (the ship registry is
	OOShipRegistry). Since oo-9ht.181 the file sends the universe its messages directly, as
	OOJSStation.mm does, until the universe is C++ (oo-pas).
*/


namespace {

// The weapon offsets as the old accessors handed them to JavaScript: an array of OONativeVector
// (as ShipEntity+FoundationBridge.mm built it).
oo::PList NativeVectorArray(const std::vector<Vector> &vectors)
{
	oo::PList::Array result;
	result.reserve(vectors.size());
	for (Vector v : vectors)
	{
		// The box is the Object node's foreign object; the engine gives JavaScript its Vector3D.
		result.push_back(oo::PList(oo::PList::Object(oo::makeRef<OONativeVector>(v))));
	}
	return oo::PList(std::move(result));
}

}	// namespace


static ooscript::Object sShipPrototype;


static bool ShipGetProperty(ooscript::Context context, ooscript::Object thisObject, ooscript::PropertyId propID, ooscript::Value *value);
static bool ShipSetProperty(ooscript::Context context, ooscript::Object thisObject, ooscript::PropertyId propID, bool strict, ooscript::Value *value);

static bool ShipSetScript(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ShipSetAI(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ShipSwitchAI(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ShipExitAI(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ShipReactToAIMessage(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ShipSendAIMessage(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ShipDeployEscorts(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ShipDockEscorts(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ShipHasRole(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ShipEjectItem(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ShipEjectSpecificItem(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ShipDumpCargo(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ShipAddCargoEntity(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ShipSpawn(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ShipDealEnergyDamage(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ShipExplode(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ShipRemove(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ShipRunLegacyScriptActions(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ShipCommsMessage(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ShipFireECM(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ShipAbandonShip(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ShipCanAwardEquipment(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ShipAwardEquipment(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ShipAdjustCargo(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ShipRequestHelpFromGroup(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ShipPatrolReportIn(ooscript::Context context, ooscript::CallArgs &oojsArgs);

static bool ShipRemoveEquipment(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ShipRestoreSubEntities(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ShipHasEquipmentProviding(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ShipEquipmentStatus(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ShipSetEquipmentStatus(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ShipSelectNewMissile(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ShipFireMissile(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ShipFindNearestStation(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ShipSetBounty(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ShipSetCargo(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ShipSetMaterials(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ShipSetShaders(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ShipExitSystem(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ShipUpdateEscortFormation(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ShipClearDefenseTargets(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ShipAddDefenseTarget(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ShipRemoveDefenseTarget(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ShipAddCollisionException(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ShipRemoveCollisionException(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ShipGetMaterials(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ShipGetShaders(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ShipBecomeCascadeExplosion(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ShipBroadcastCascadeImminent(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ShipBroadcastDistressMessage(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ShipOfferToEscort(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ShipMarkTargetForFines(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ShipEnterWormhole(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ShipNotifyGroupOfWormhole(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ShipThrowSpark(ooscript::Context context, ooscript::CallArgs &oojsArgs);

static bool ShipPerformAttack(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ShipPerformCollect(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ShipPerformEscort(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ShipPerformFaceDestination(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ShipPerformFlee(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ShipPerformFlyToRangeFromDestination(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ShipPerformHold(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ShipPerformIdle(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ShipPerformIntercept(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ShipPerformLandOnPlanet(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ShipPerformMining(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ShipPerformScriptedAI(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ShipPerformScriptedAttackAI(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ShipPerformStop(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ShipPerformTumble(ooscript::Context context, ooscript::CallArgs &oojsArgs);

static bool ShipRequestDockingInstructions(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ShipRecallDockingInstructions(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ShipCheckCourseToDestination(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ShipGetSafeCourseToDestination(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ShipCheckScanner(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ShipThreatAssessment(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ShipDamageAssessment(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static double ShipThreatAssessmentWeapon(OOWeaponType wt);

static bool ShipSetCargoType(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ShipSetCrew(ooscript::Context context, ooscript::CallArgs &oojsArgs);

namespace {
bool RemoveOrExplodeShip(ooscript::Context context, ooscript::CallArgs &oojsArgs, bool explode);
bool ShipSetMaterialsInternal(ooscript::Context context, ooscript::CallArgs &oojsArgs, ShipEntity *thisEnt, bool fromShaders);
}

static bool ShipStaticKeysForRole(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ShipStaticKeys(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ShipStaticRoles(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ShipStaticRoleIsInCategory(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ShipStaticShipDataForKey(ooscript::Context context, ooscript::CallArgs &oojsArgs);
static bool ShipStaticSetShipDataForKey(ooscript::Context context, ooscript::CallArgs &oojsArgs);

static ooscript::ClassDef sShipClass =
{
	"Ship",
	ooscript::ClassFlag::HasPrivate,
	
	nullptr,		// addProperty
	nullptr,		// delProperty
	ShipGetProperty,		// getProperty
	ShipSetProperty,		// setProperty
	nullptr,		// enumerate
	nullptr,		// newEnumerate
	nullptr,			// resolve
	nullptr,			// convert
	OOJSCxxObjectWrapperFinalize,// finalize (the slot holds an OOJSEntityHolder, bead oo-9ht.39.3)
	nullptr,		// call
	nullptr,		// construct
	nullptr,		// backend
};


/* It turns out that the value in SpiderMonkey used to identify these
 * enums is an 8-bit signed int:
 * (see the engine reference for its property-spec table)
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
	kShip_cargoSpaceCapacity,	// maximum cargo, integer, read/write
	kShip_cargoSpaceUsed,		// cargo on board, integer, read-only
	kShip_collisionExceptions,   // collision exception list, array, read-only
	kShip_contracts,			// cargo contracts contracts, array - strings & whatnot, read only
	kShip_commodity,			// commodity of a ship, read only
	kShip_commodityAmount,		// commodityAmount of a ship, read only
	kShip_cloakAutomatic,		// should cloack start by itself or by script, read/write
	kShip_crew,					// crew, list, read only
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
	kShip_hyperspaceSpinTime,	// hyperspace spin time, float, read/write
	kShip_injectorBurnRate,		// injector burn rate, number, read/write dLY/s
	kShip_injectorSpeedFactor,  // injector speed factor, number, read/write
	kShip_isBeacon,				// is beacon, boolean, read-only
	kShip_isBoulder,			// is a boulder (generates splinters), boolean, read/write
	kShip_isCargo,				// contains cargo, boolean, read-only
	kShip_isCloaked,			// cloaked, boolean, read/write (if cloaking device installed)
	kShip_isDerelict,			// is an abandoned ship, boolean, read-only
	kShip_isFrangible,			// frangible, boolean, read-only
	kShip_isFleeing,			// is fleeing, boolean, read-only
	kShip_isJamming,			// jamming scanners, boolean, read/write (if jammer installed)
	kShip_isMinable,			// is a sensible target for mining, boolean, read-only
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
	kShip_reactionTime,		// AI reaction time, read/write
	kShip_reportAIMessages,		// report AI messages, boolean, read/write
	kShip_roleWeights,			// roles and weights, dictionary, read-only
	kShip_roles,				// roles, array, read-only
	kShip_roll,					// roll level, float, read-only
	kShip_savedCoordinates,		// coordinates in system space for AI use, Vector, read/write
	kShip_scanDescription,		// STE scan class label, string, read/write
	kShip_scannerDisplayColor1,	// color of lollipop shown on scanner, array, read/write
	kShip_scannerDisplayColor2,	// color of lollipop shown on scanner when flashing, array, read/write
	kShip_scannerHostileDisplayColor1,	// color of lollipop shown on scanner, array, read/write
	kShip_scannerHostileDisplayColor2,	// color of lollipop shown on scanner when flashing, array, read/write
	kShip_scannerRange,			// scanner range, double, read-only
	kShip_script,				// script, Script, read-only
	kShip_scriptedMisjump,		// next jump will miss if set to true, boolean, read/write
	kShip_scriptedMisjumpRange,  // 0..1 range of next misjump, float, read/write
	kShip_scriptInfo,			// arbitrary data for scripts, dictionary, read-only
	kShip_shipClassName,		// ship type name, string, read/write
	kShip_shipUniqueName,		// uniqish name, string, read/write
	kShip_speed,				// current flight speed, double, read/write
	kShip_starboardWeapon,		// the ship's starboard weapon, equipmentType, read/write
	kShip_subEntities,			// subentities, array of Ship, read-only
 	kShip_subEntityCapacity,	// max subentities for this ship, int, read-only
	kShip_subEntityRotation,	// subentity rotation velocity, quaternion, read/write
	kShip_sunGlareFilter,		// sun glare filter multiplier, float, read/write
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


static ooscript::PropertySpec sShipProperties[] =
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
	{ "cargoSpaceCapacity",		kShip_cargoSpaceCapacity,	OOJS_PROP_READWRITE_CB },
	{ "cargoSpaceAvailable",	kShip_cargoSpaceAvailable,	OOJS_PROP_READONLY_CB },
	{ "collisionExceptions",	kShip_collisionExceptions,	OOJS_PROP_READONLY_CB },
	{ "commodity",				kShip_commodity,			OOJS_PROP_READONLY_CB },
	{ "commodityAmount",		kShip_commodityAmount,		OOJS_PROP_READONLY_CB },
	// contracts instead of cargo to distinguish them from the manifest
	{ "contracts",				kShip_contracts,			OOJS_PROP_READONLY_CB },
	{ "cloakAutomatic",			kShip_cloakAutomatic,		OOJS_PROP_READWRITE_CB},
	{ "crew",					kShip_crew,					OOJS_PROP_READONLY_CB },
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
	{ "energyRechargeRate",		kShip_energyRechargeRate,	OOJS_PROP_READWRITE_CB },
	{ "entityPersonality",		kShip_entityPersonality,	OOJS_PROP_READWRITE_CB },
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
	{ "hyperspaceSpinTime",		kShip_hyperspaceSpinTime,	OOJS_PROP_READWRITE_CB },
	{ "injectorBurnRate",		kShip_injectorBurnRate,		OOJS_PROP_READWRITE_CB },
	{ "injectorSpeedFactor",	kShip_injectorSpeedFactor,	OOJS_PROP_READWRITE_CB },
	{ "homeSystem",				kShip_homeSystem,			OOJS_PROP_READWRITE_CB },
	{ "isBeacon",				kShip_isBeacon,				OOJS_PROP_READONLY_CB },
	{ "isCloaked",				kShip_isCloaked,			OOJS_PROP_READWRITE_CB },
	{ "isCargo",				kShip_isCargo,				OOJS_PROP_READONLY_CB },
	{ "isDerelict",				kShip_isDerelict,			OOJS_PROP_READONLY_CB },
	{ "isFrangible",			kShip_isFrangible,			OOJS_PROP_READONLY_CB },
	{ "isFleeing",				kShip_isFleeing,			OOJS_PROP_READONLY_CB },
	{ "isJamming",				kShip_isJamming,			OOJS_PROP_READONLY_CB },
	{ "isMinable",				kShip_isMinable,			OOJS_PROP_READONLY_CB },
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
	{ "maxPitch",				kShip_maxPitch,				OOJS_PROP_READWRITE_CB },
	{ "maxSpeed",				kShip_maxSpeed,				OOJS_PROP_READWRITE_CB },
	{ "maxRoll",				kShip_maxRoll,				OOJS_PROP_READWRITE_CB },
	{ "maxYaw",					kShip_maxYaw,				OOJS_PROP_READWRITE_CB },
	{ "maxThrust",				kShip_maxThrust,			OOJS_PROP_READWRITE_CB },
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
	{ "reactionTime",		kShip_reactionTime,		OOJS_PROP_READWRITE_CB },
	{ "reportAIMessages",		kShip_reportAIMessages,		OOJS_PROP_READWRITE_CB },
	{ "roleWeights",			kShip_roleWeights,			OOJS_PROP_READONLY_CB },
	{ "roles",					kShip_roles,				OOJS_PROP_READONLY_CB },
	{ "roll",					kShip_roll,					OOJS_PROP_READONLY_CB },
	{ "savedCoordinates",		kShip_savedCoordinates,		OOJS_PROP_READWRITE_CB },
	{ "scanDescription",		kShip_scanDescription,		OOJS_PROP_READWRITE_CB },
	{ "scannerDisplayColor1",	kShip_scannerDisplayColor1,	OOJS_PROP_READWRITE_CB },
	{ "scannerDisplayColor2",	kShip_scannerDisplayColor2,	OOJS_PROP_READWRITE_CB },
	{ "scannerHostileDisplayColor1",	kShip_scannerHostileDisplayColor1,	OOJS_PROP_READWRITE_CB },
	{ "scannerHostileDisplayColor2",	kShip_scannerHostileDisplayColor2,	OOJS_PROP_READWRITE_CB },
	{ "scannerRange",			kShip_scannerRange,			OOJS_PROP_READONLY_CB },
	{ "script",					kShip_script,				OOJS_PROP_READONLY_CB },
	{ "scriptedMisjump",		kShip_scriptedMisjump,		OOJS_PROP_READWRITE_CB },
	{ "scriptedMisjumpRange",		kShip_scriptedMisjumpRange,		OOJS_PROP_READWRITE_CB },
	{ "scriptInfo",				kShip_scriptInfo,			OOJS_PROP_READONLY_CB },
	{ "shipClassName",			kShip_shipClassName,		OOJS_PROP_READWRITE_CB },
	{ "shipUniqueName",				kShip_shipUniqueName,				OOJS_PROP_READWRITE_CB },
	{ "speed",					kShip_speed,				OOJS_PROP_READWRITE_CB },
	{ "starboardWeapon",		kShip_starboardWeapon,		OOJS_PROP_READWRITE_CB },
	{ "subEntities",			kShip_subEntities,			OOJS_PROP_READONLY_CB },
	{ "subEntityCapacity",		kShip_subEntityCapacity,	OOJS_PROP_READONLY_CB },
	{ "subEntityRotation",		kShip_subEntityRotation,	OOJS_PROP_READWRITE_CB },
	{ "sunGlareFilter",			kShip_sunGlareFilter,		OOJS_PROP_READWRITE_CB },
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

static ooscript::FunctionSpec sShipMethods[] =
{
	// JS name					Function					min args
	{ "abandonShip",			ShipAbandonShip,			0 },
	{ "addCargoEntity",			ShipAddCargoEntity,			1 },
	{ "addCollisionException",	ShipAddCollisionException,	1 },
	{ "addDefenseTarget",		ShipAddDefenseTarget,		1 },
	{ "adjustCargo",			ShipAdjustCargo,			2 },
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
	{ "hasEquipmentProviding",	ShipHasEquipmentProviding,		1 },
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
	{ "removeCollisionException",	ShipRemoveCollisionException,	1 },
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
	{ "setCrew",				ShipSetCrew,				1 },
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

static ooscript::FunctionSpec sShipStaticMethods[] =
{
	// JS name				Function						min args
	{ "keys",				ShipStaticKeys,					0 },
	{ "keysForRole",		ShipStaticKeysForRole,			1 },
	{ "roleIsInCategory",	ShipStaticRoleIsInCategory,		2 },
	{ "roles",				ShipStaticRoles,				0 },
	{ "shipDataForKey",		ShipStaticShipDataForKey,		1 },
	{ "setShipDataForKey",  ShipStaticSetShipDataForKey,    2 },
	{ 0 }
};


namespace {

/*	The ship a JS Ship object holds. DEFINE_JS_OBJECT_GETTER's getter answered the ship's object until
	bead oo-9ht.144 deleted the ship's facade (the object is now the drawable's facade, so the getter
	checks the root's class); this answers its C++ ship, null where the object was nil. Since bead
	oo-9ht.39.3 the slot holds the C++ entity (OOJSEntityGetEntityOfClass, the same JS class check).
*/
BOOL JSShipGetShipEntity(ooscript::Context context, ooscript::Object inObject, ShipEntity **outShip)
{
	OOCParameterAssert(outShip != NULL);
	Entity *entity = nullptr;
	if (EXPECT_NOT(!OOJSEntityGetEntityOfClass(context, inObject, &sShipClass, &entity)))  return NO;
	*outShip = oo::ToShip(entity);
	return YES;
}
} // namespace


void InitOOJSShip(ooscript::Context context, ooscript::Object global)
{
	sShipPrototype = ooscript::initClass(context, global, JSEntityPrototype(), &sShipClass, OOJSUnconstructableConstruct, 0, sShipProperties, sShipMethods, NULL, sShipStaticMethods);
	OOJSRegisterObjectConverter(&sShipClass, OOJSEntityObjectConverter);
	OOJSRegisterSubclass(&sShipClass, JSEntityClass());
}


ooscript::ClassDef *JSShipClass(void)
{
	return &sShipClass;
}


ooscript::Object JSShipPrototype(void)
{
	return sShipPrototype;
}


namespace {

// A colour's components as its -normalizedArray gave them to JavaScript: floats, null for no colour.
oo::PList NormalizedColorComponents(OOColor *color)
{
	if (color == nullptr)  return oo::PList();
	oo::PList::Array components;
	for (float component : color->normalizedArray())  components.push_back(oo::PList::singleReal(component));
	return oo::PList(std::move(components));
}

/*	The ship's AI is C++ (AI, since bead oo-9ht.73 without a facade). A ship with no AI
	answered none or false to what the getter sent the AI; so does a null AI here (ADR-0056
	amendment oo-6ia4 item 2).
*/
std::optional<std::string> AIName(ShipEntity *ship)
{
	AI *ai = ship->getAI();
	return (ai != nullptr) ? ai->name() : std::nullopt;
}

std::optional<std::string> AIState(ShipEntity *ship)
{
	AI *ai = ship->getAI();
	return (ai != nullptr) ? ai->state() : std::nullopt;
}

bool AIHasSuspendedStateMachines(ShipEntity *ship)
{
	AI *ai = ship->getAI();
	return ai != nullptr && ai->hasSuspendedStateMachines();
}

// Whether an entity is a ship, as -isKindOfClass:[ShipEntity class] answered: a ship's C++ part is a
// ShipEntity (Entity+ObjCBridge.mm picks the facade class from it). False for none.
bool IsShip(Entity *entity)
{
	return dynamic_cast<ShipEntity *>(entity) != nullptr;
}

/*	The ship's mesh is C++ (OOMesh, global since bead oo-9ht.132). A ship with no mesh answered
	null to -materials and -shaders; so does a null mesh here.
*/
oo::PList MeshMaterials(ShipEntity *ship)
{
	OOMesh *mesh = ship->mesh();
	return (mesh != nullptr) ? mesh->getMaterials() : oo::PList();
}

oo::PList MeshShaders(ShipEntity *ship)
{
	OOMesh *mesh = ship->mesh();
	return (mesh != nullptr) ? mesh->shaders() : oo::PList();
}

// A string, or null for none (what a Foundation string or nil gave JavaScript).
oo::PList StringOrNull(const std::optional<std::string> &string)
{
	return string.has_value() ? oo::PList(*string) : oo::PList();
}

// Strings as an array of strings, in order.
oo::PList StringArray(const std::vector<std::string> &strings)
{
	return oo::PList(oo::PList::Array(strings.begin(), strings.end()));
}

}	// namespace


static bool ShipGetProperty(ooscript::Context context, ooscript::Object thisObject, ooscript::PropertyId propID, ooscript::Value *value)
{
	if (!ooscript::isInt32Id(propID))  return true;
	
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity					*entity = nullptr;
	oo::PList					result;	// null maps to null
	
	if (EXPECT_NOT(!JSShipGetShipEntity(context, thisObject, &entity)))  return false;
	if (OOIsStaleEntity(entity)) { *value = ooscript::undefinedValue(); return true; }
	ShipEntity				*ship = entity;	// not null: entity is not
	
	switch (ooscript::idToInt32(propID))
	{
		case kShip_name:
			result = StringOrNull(ship->getName());
			break;
			
		case kShip_displayName:
			result = StringOrNull(ship->getDisplayName());
			break;

		case kShip_shipUniqueName:
			result = StringOrNull(ship->getShipUniqueName());
			break;

		case kShip_shipClassName:
			result = StringOrNull(ship->getShipClassName());
			break;
		
		case kShip_scanDescription:
			result = StringOrNull(ship->scanDescriptionForScripting());
			break;

		case kShip_roles:
			{
				const oo::Ref<OORoleSet> roleSet = ship->getRoleSet();
				result = roleSet != nullptr ? StringArray(roleSet->sortedRoles()) : oo::PList();
			}
			break;
		
		case kShip_roleWeights:
			{
				// Floats, as numberWithFloat: made them; nil when there is no role set.
				const oo::Ref<OORoleSet> roleSet = ship->getRoleSet();
				if (const auto roleWeights = (roleSet != nullptr) ? roleSet->rolesAndProbabilities() : std::nullopt)
				{
					oo::PList::Dict weights;
					for (const auto &[role, weight] : *roleWeights)
					{
						weights[role] = oo::PList::singleReal(weight);
					}
					result = oo::PList(std::move(weights));
				}
			}
			break;
		
		case kShip_primaryRole:
			result = StringOrNull(ship->getPrimaryRole());
			break;
		
		case kShip_AI:
			result = StringOrNull(AIName(ship));
			break;
		
		case kShip_AIState:
			result = StringOrNull(AIState(ship));
			break;
		
		case kShip_AIFoundTarget:
			result = oo::EntityObjectNode(ship->foundTarget());
			break;
		
		case kShip_AIPrimaryAggressor:
			result = oo::EntityObjectNode(ship->primaryAggressor());
			break;
		
		case kShip_alertCondition:
			return ooscript::newNumberValue(context, ship->realAlertCondition(), value);

		case kShip_autoAI:
			*value = OOJSValueFromBOOL(ship->hasAutoAI());
			return true;

		case kShip_autoWeapons:
			*value = OOJSValueFromBOOL(ship->hasAutoWeapons());
			return true;
		
		case kShip_accuracy:
			return ooscript::newNumberValue(context, ship->getAccuracy(), value);
			
		case kShip_fuel:
			return ooscript::newNumberValue(context, ship->getFuel() * 0.1, value);
			
		case kShip_fuelChargeRate:
			return ooscript::newNumberValue(context, ship->fuelChargeRate(), value);
			
		case kShip_bounty:
			return ooscript::newNumberValue(context, ship->getBounty(), value);
			return true;
			
		case kShip_subEntities:
			// What -subEntitiesForScript answered: ShipEntity's (OOJavaScriptExtensions) method, which no
			// subclass overrides, forwards to this function.
			result = oo::EntityNodesFrom(ShipEntityJSSubEntitiesForScript(entity));
			break;

		case kShip_exhausts:
			result = oo::EntityNodesFrom(ship->exhausts());
			break;

		case kShip_flashers:
			result = oo::EntityNodesFrom(ship->flasherEnumerator());
			break;
			
		case kShip_subEntityCapacity:
			return ooscript::newNumberValue(context, ship->maxShipSubEntities(), value);
			return true;
			
		case kShip_subEntityRotation:
			return QuaternionToJSValue(context, ship->subEntityRotationalVelocity(), value);

		case kShip_hasSuspendedAI:
			*value = OOJSValueFromBOOL(AIHasSuspendedStateMachines(ship));
			return true;
			
		case kShip_target:
			result = oo::EntityObjectNode(ship->primaryTarget());	// the C++ entity's object node or nil (bead oo-9ht.39.5.2; the getter answers the C++ entity since oo-9ht.39.23)
			break;
		
		case kShip_defenseTargets:
		{
			ship->validateDefenseTargets();
			std::vector<oo::EntityHold> targets;
			targets.reserve(ship->defenseTargetCount());
			for (const auto &candidate : ship->defenseTargets())
			{
				// The set's snapshot holds the ships themselves, whose underlying object (OOObject's
				// weak-reference answer) was self.
				if (!candidate)  break;	// the old loop stopped at the first zeroed reference
				targets.push_back(candidate);
			}
			result = oo::EntityNodesFrom(targets);
			break;
		}		

		case kShip_crew:
			if (ship->getCrew().has_value())	// unpiloted: nil, as before
			{
				const std::vector<oo::PList> entries = ship->crewForScripting();
				result = oo::PList(oo::PList::Array(entries.begin(), entries.end()));
			}
			break;
	
		case kShip_escorts:
			{
				OOShipGroup *escortGroup = ship->escortGroup();
				result = (escortGroup != nullptr) ? oo::EntityNodesFrom(escortGroup->memberArrayExcludingLeader()) : oo::PList();
			}
			break;
			
		case kShip_group:
			result = OOShipGroupObjectNode(ship->group());
			break;
			
		case kShip_escortGroup:
			result = OOShipGroupObjectNode(ship->escortGroup());
			break;
			
		case kShip_temperature:
			return ooscript::newNumberValue(context, ship->temperature() / SHIP_MAX_CABIN_TEMP, value);
			
		case kShip_heatInsulation:
			return ooscript::newNumberValue(context, ship->heatInsulation(), value);
			
		case kShip_heading:
			return VectorToJSValue(context, ship->forwardVector(), value);
			
		case kShip_energyRechargeRate:
			return ooscript::newNumberValue(context, ship->energyRechargeRate(), value);

		case kShip_entityPersonality:
			*value = ooscript::int32Value(ship->entityPersonalityInt());
			return true;
			
		case kShip_isBeacon:
			*value = OOJSValueFromBOOL(ship->isBeacon());
			return true;
			
		case kShip_beaconCode:
			result = StringOrNull(ship->beaconCode());
			break;

		case kShip_beaconLabel:
			result = StringOrNull(ship->beaconLabel());
			break;
		
		case kShip_isFrangible:
			*value = OOJSValueFromBOOL(ship->getIsFrangible());
			return true;
		
		case kShip_isCloaked:
			*value = OOJSValueFromBOOL(ship->isCloaked());
			return true;
			
		case kShip_cloakAutomatic:
			*value = OOJSValueFromBOOL(ship->hasAutoCloak());
			return true;
			
		case kShip_isJamming:
			*value = OOJSValueFromBOOL(ship->isJammingScanning());
			return true;
		
		case kShip_potentialCollider:
			result = oo::EntityObjectNode(ship->proximityAlert());
			break;
		
		case kShip_hasHostileTarget:
			*value = OOJSValueFromBOOL(ship->hasHostileTarget());
			return true;
		
		case kShip_hasHyperspaceMotor:
			*value = OOJSValueFromBOOL(ship->hasHyperspaceMotor());
			return true;
		
		case kShip_hyperspaceSpinTime:
			return ooscript::newNumberValue(context, ship->hyperspaceSpinTime(), value);

		case kShip_weaponRange:
			return ooscript::newNumberValue(context, ship->getWeaponRange(), value);

		case kShip_weaponFacings:
			if (ship->getIsPlayer())
			{
				PlayerEntity *pent = static_cast<PlayerEntity *>(entity);
				return ooscript::newNumberValue(context, (pent != nullptr ? pent->availableFacings() : OOWeaponFacingSet{}), value);
			}
			return ooscript::newNumberValue(context, ship->weaponFacings(), value);
		
		case kShip_weaponPositionAft:
			result = NativeVectorArray(ship->getAftWeaponOffset());
			break;
		
		case kShip_weaponPositionForward:
			result = NativeVectorArray(ship->getForwardWeaponOffset());
			break;
//			return VectorToJSValue(context, [entity forwardWeaponOffset], value);
		
		case kShip_weaponPositionPort:
			result = NativeVectorArray(ship->getPortWeaponOffset());
			break;
		
		case kShip_weaponPositionStarboard:
			result = NativeVectorArray(ship->getStarboardWeaponOffset());
			break;
		
		case kShip_scannerRange:
			return ooscript::newNumberValue(context, ship->getScannerRange(), value);
		
		case kShip_reactionTime:
			return ooscript::newNumberValue(context, ship->getReactionTime(), value);
			
		case kShip_reportAIMessages:
			*value = OOJSValueFromBOOL(ship->getReportAIMessages());
			return true;
		
		case kShip_withinStationAegis:
			*value = OOJSValueFromBOOL(ship->withinStationAegis());
			return true;
		
		case kShip_cargoSpaceCapacity:
			*value = ooscript::int32Value(ship->maxAvailableCargoSpace());
			return true;
		
		case kShip_cargoSpaceUsed:
			*value = ooscript::int32Value(ship->maxAvailableCargoSpace() - ship->availableCargoSpace());
			return true;
		
		case kShip_cargoSpaceAvailable:
			*value = ooscript::int32Value(ship->availableCargoSpace());
			return true;

	  case kShip_cargoList:
			result = ship->cargoListForScripting();
			break;

		case kShip_extraCargo:
			return ooscript::newNumberValue(context, ship->extraCargo(), value);
			return true;
		
		case kShip_commodity:
			if (ship->commodityAmount() > 0)
			{
				result = StringOrNull(ship->commodityType());
			}
			break;
			
		case kShip_commodityAmount:
			*value = ooscript::int32Value(ship->commodityAmount());
			return true;

	  case kShip_collisionExceptions:
			result = oo::EntityNodesFrom(ship->collisionExceptions());
			break;

			
		case kShip_speed:
			return ooscript::newNumberValue(context, ship->getFlightSpeed(), value);
			
		case kShip_cruiseSpeed:
			return ooscript::newNumberValue(context, ship->getCruiseSpeed(), value);
		
		case kShip_dataKey:
			result = StringOrNull(ship->shipDataKey());
			break;
			
		case kShip_desiredRange:
			return ooscript::newNumberValue(context, ship->desiredRange(), value);
		
		case kShip_desiredSpeed:
			return ooscript::newNumberValue(context, ship->desiredSpeed(), value);
			
		case kShip_destination:
			return HPVectorToJSValue(context, ship->destination(), value);
		
		case kShip_markedForFines:
			*value = OOJSValueFromBOOL(ship->markedForFines());
			return true;

		case kShip_maxEscorts:
			return ooscript::newNumberValue(context, ship->maxEscortCount(), value);

		case kShip_maxPitch:
			return ooscript::newNumberValue(context, ship->maxFlightPitch(), value);
		
		case kShip_maxSpeed:
			return ooscript::newNumberValue(context, ship->getMaxFlightSpeed(), value);
		
		case kShip_maxRoll:
			return ooscript::newNumberValue(context, ship->maxFlightRoll(), value);
		
		case kShip_maxYaw:
			return ooscript::newNumberValue(context, ship->maxFlightYaw(), value);

		case kShip_injectorBurnRate:
			return ooscript::newNumberValue(context, ship->afterburnerRate(), value);

		case kShip_injectorSpeedFactor:
			return ooscript::newNumberValue(context, ship->afterburnerFactor(), value);
			
		case kShip_script:
			result = OOScriptObjectNode(ship->shipScript());
			break;

		case kShip_AIScript:
			result = OOScriptObjectNode(ship->shipAIScript());
			break;

		case kShip_AIScriptWakeTime:
			return ooscript::newNumberValue(context, ship->shipAIScriptWakeTime(), value);
			break;

		case kShip_destinationSystem:
			return ooscript::newNumberValue(context, ship->destinationSystem(), value);
			break;

		case kShip_homeSystem:
			return ooscript::newNumberValue(context, ship->homeSystem(), value);
			break;
			
		case kShip_isPirate:
			*value = OOJSValueFromBOOL(ship->isPirate());
			return true;
			
		case kShip_isPolice:
			*value = OOJSValueFromBOOL(ship->isPolice());
			return true;
			
		case kShip_isThargoid:
			*value = OOJSValueFromBOOL(ship->isThargoid());
			return true;
			
		case kShip_isTurret:
			*value = OOJSValueFromBOOL(ship->isTurret());
			return true;

		case kShip_isTrader:
			*value = OOJSValueFromBOOL(ship->isTrader());
			return true;
			
		case kShip_isPirateVictim:
			*value = OOJSValueFromBOOL(ship->isPirateVictim());
			return true;
			
		case kShip_isMissile:
			*value = OOJSValueFromBOOL(ship->getIsMissile());
			return true;
			
		case kShip_isMine:
			*value = OOJSValueFromBOOL(ship->isMine());
			return true;
			
		case kShip_isWeapon:
			*value = OOJSValueFromBOOL(ship->isWeapon());
			return true;
			
		case kShip_isRock:
			*value = OOJSValueFromBOOL(ship->getScanClass() == CLASS_ROCK);	// hermits and asteroids!
			return true;

		case kShip_isMinable:
			*value = OOJSValueFromBOOL(ship->isMinable());
			return true;
			
		case kShip_isBoulder:
			*value = OOJSValueFromBOOL(ship->isBoulder());
			return true;

		case kShip_isFleeing:
			if (ship->getIsPlayer())
			{
				*value = OOJSValueFromBOOL((static_cast<PlayerEntity *>(entity) != nullptr ? static_cast<PlayerEntity *>(entity)->fleeingStatus() : OOPlayerFleeingStatus{}) >= PLAYER_FLEEING_CARGO);
			}
			else
			{
				*value = OOJSValueFromBOOL(ship->getBehaviour() == BEHAVIOUR_FLEE_TARGET || ship->getBehaviour() == BEHAVIOUR_FLEE_EVASIVE_ACTION);
			}
			return true;
			
		case kShip_isCargo:
			*value = OOJSValueFromBOOL(ship->getScanClass() == CLASS_CARGO && ship->commodityAmount() > 0);
			return true;
			
		case kShip_isDerelict:
			*value = OOJSValueFromBOOL(ship->getIsHulk());
			return true;
			
		case kShip_isPiloted:
			*value = OOJSValueFromBOOL(ship->getIsPlayer() || ship->getCrew().value_or(std::vector<oo::Ref<OOCharacter>>()).size() > 0);
			return true;
			
		case kShip_scriptedMisjump:
			*value = OOJSValueFromBOOL(ship->scriptedMisjump());
			return true;

		case kShip_scriptedMisjumpRange:
			return ooscript::newNumberValue(context, ship->scriptedMisjumpRange(), value);
			
		case kShip_scriptInfo:
			result = ship->getScriptInfo();	// empty dict, never null
			break;
			
		case kShip_sunGlareFilter:
			return ooscript::newNumberValue(context, ship->getSunGlareFilter(), value);
			
		case kShip_trackCloseContacts:
			*value = OOJSValueFromBOOL(ship->getTrackCloseContacts());
			return true;
			
		case kShip_passengerCount:
			return ooscript::newNumberValue(context, ship->passengerCount(), value);

		case kShip_parcelCount:
			return ooscript::newNumberValue(context, ship->parcelCount(), value);
			
		case kShip_passengerCapacity:
			return ooscript::newNumberValue(context, ship->passengerCapacity(), value);
		
		case kShip_missileCapacity:
			return ooscript::newNumberValue(context, ship->missileCapacity(), value);
			
		case kShip_missileLoadTime:
			return ooscript::newNumberValue(context, ship->missileLoadTime(), value);
		
		case kShip_savedCoordinates:
			return HPVectorToJSValue(context,ship->getCoordinates(), value);
		
		case kShip_equipment:
			result = OOEquipmentTypeObjectNodes(ship->equipmentListForScripting());
			break;
			
		case kShip_currentWeapon:
			result = OOEquipmentTypeObjectNode(ship->weaponTypeForFacing(ship->getCurrentWeaponFacing(), true));
			break;
		
		case kShip_forwardWeapon:
			result = OOEquipmentTypeObjectNode(ship->weaponTypeForFacing(WEAPON_FACING_FORWARD, true));
			break;
		
		case kShip_aftWeapon:
			result = OOEquipmentTypeObjectNode(ship->weaponTypeForFacing(WEAPON_FACING_AFT, true));
			break;
		
		case kShip_portWeapon:
			result = OOEquipmentTypeObjectNode(ship->weaponTypeForFacing(WEAPON_FACING_PORT, true));
			break;
		
		case kShip_starboardWeapon:
			result = OOEquipmentTypeObjectNode(ship->weaponTypeForFacing(WEAPON_FACING_STARBOARD, true));
			break;
		
		case kShip_laserHeatLevel:
			return ooscript::newNumberValue(context, ship->laserHeatLevel(), value);
		
		case kShip_laserHeatLevelAft:
			return ooscript::newNumberValue(context, ship->laserHeatLevelAft(), value);
		
		case kShip_laserHeatLevelForward:
			return ooscript::newNumberValue(context, ship->laserHeatLevelForward(), value);
		
		case kShip_laserHeatLevelPort:
			return ooscript::newNumberValue(context, ship->laserHeatLevelPort(), value);
		
		case kShip_laserHeatLevelStarboard:
			return ooscript::newNumberValue(context, ship->laserHeatLevelStarboard(), value);
		
		case kShip_missiles:
			result = OOEquipmentTypeObjectNodes(ship->missilesList());
			break;
		
		case kShip_passengers:
			result = ship->passengerListForScripting();
			break;

		case kShip_parcels:
			result = ship->parcelListForScripting();
			break;
		
		case kShip_contracts:
			result = ship->contractListForScripting();
			break;
			
  	case kShip_dockingInstructions:
			result = ship->getDockingInstructions();
			break;

		case kShip_scannerDisplayColor1:
			result = NormalizedColorComponents(ship->scannerDisplayColor1());
			break;

		case kShip_scannerDisplayColor2:
			result = NormalizedColorComponents(ship->scannerDisplayColor2());
			break;

		case kShip_scannerHostileDisplayColor1:
			result = NormalizedColorComponents(ship->scannerDisplayColorHostile1());
			break;

		case kShip_scannerHostileDisplayColor2:
			result = NormalizedColorComponents(ship->scannerDisplayColorHostile2());
			break;

		case kShip_exhaustEmissiveColor:
			result = NormalizedColorComponents(ship->exhaustEmissiveColor());
			break;
			
		case kShip_maxThrust:
			return ooscript::newNumberValue(context, ship->maxThrust(), value);
			
		case kShip_thrust:
			return ooscript::newNumberValue(context, ship->getThrust(), value);
			
		case kShip_lightsActive:
			*value = OOJSValueFromBOOL(ship->lightsActive());
			return true;
			
		case kShip_vectorRight:
			return VectorToJSValue(context, ship->rightVector(), value);
			
		case kShip_vectorForward:
			return VectorToJSValue(context, ship->forwardVector(), value);
			
		case kShip_vectorUp:
			return VectorToJSValue(context, ship->upVector(), value);
			
		case kShip_velocity:
			return VectorToJSValue(context, ship->getVelocity(), value);
			
		case kShip_thrustVector:
			return VectorToJSValue(context, ship->thrustVector(), value);
		
		case kShip_pitch:
			return ooscript::newNumberValue(context, ship->getFlightPitch(), value);
		
		case kShip_roll:
			return ooscript::newNumberValue(context, ship->getFlightRoll(), value);
		
		case kShip_yaw:
			return ooscript::newNumberValue(context, ship->getFlightYaw(), value);
		
		case kShip_boundingBox:
			{
				Vector bbvect;
				BoundingBox box;
				
				if (ship->getIsSubEntity())
				{
					box = ship->getBoundingBox();
				}
				else
				{
					box = ship->getTotalBoundingBox();
				}
				bounding_box_get_dimensions(box,&bbvect.x,&bbvect.y,&bbvect.z);
				return VectorToJSValue(context, bbvect, value);
			}
			
		default:
			OOJSReportBadPropertySelector(context, thisObject, propID, sShipProperties);
			return false;
	}
	
	*value = OOJSValueFromPList(context, result);
	return true;
	
	OOJS_NATIVE_EXIT
}


bool ShipSetProperty(ooscript::Context context, ooscript::Object thisObject, ooscript::PropertyId propID, bool /*strict*/, ooscript::Value *value)
{
	if (!ooscript::isInt32Id(propID))  return true;
	
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity					*entity = nullptr;
	Entity					*target = nullptr;	// as JSValueToEntity() answers (the C++ entity since bead oo-9ht.39.3)
	std::optional<std::string>	sValue;
	double					fValue;
	int32_t						iValue;
	bool						bValue;
	Vector						vValue;
	Quaternion					qValue;
	HPVector						hpvValue;
	OOShipGroup					*group = nullptr;
	oo::Ref<OOColor>		colorForScript;
	BOOL exists;	// JSValueToEquipmentKeyRelaxed()'s out parameter
	
	if (EXPECT_NOT(!JSShipGetShipEntity(context, thisObject, &entity)))  return false;
	if (OOIsStaleEntity(entity))  return true;
	ShipEntity				*ship = entity;	// not null: entity is not

	OOCAssert(!ship->isTemplateCargoPod(), "-OOJSShip: a template cargo pod has become accessible to Javascript");
	
	switch (ooscript::idToInt32(propID))
	{
		case kShip_name:
			if (EXPECT_NOT(ship->getIsPlayer()))  goto playerReadOnly;
			
			sValue = cxx_OOStringFromJSValue(context,*value);
			if (sValue.has_value())
			{
				ship->setName(sValue);
				return true;
			}
			break;
			
		case kShip_displayName:
			if (EXPECT_NOT(ship->getIsPlayer()))  goto playerReadOnly;
			
			sValue = cxx_OOStringFromJSValue(context,*value);
			if (sValue.has_value())
			{
				ship->setDisplayName(sValue);
				return true;
			}
			break;

		case kShip_shipUniqueName:
			sValue = cxx_OOStringFromJSValue(context,*value);
			if (sValue.has_value())
			{
				ship->setShipUniqueName(sValue);
				return true;
			}
			break;

		case kShip_shipClassName:
			sValue = cxx_OOStringFromJSValue(context,*value);
			if (sValue.has_value())
			{
				ship->setShipClassName(sValue);
				return true;
			}
			break;


		case kShip_scanDescription:
			sValue = cxx_OOStringFromJSValue(context,*value);
			// can set to nil
			ship->setScanDescription(sValue);
			return true;
		
		case kShip_primaryRole:
			if (EXPECT_NOT(ship->getIsPlayer()))  goto playerReadOnly;
			
			sValue = cxx_OOStringFromJSValue(context,*value);
			if (sValue.has_value())
			{
				ship->setPrimaryRole(*sValue);
				return true;
			}
			break;
		
		case kShip_AIState:
			if (EXPECT_NOT(ship->getIsPlayer()))  goto playerReadOnly;
			
			sValue = cxx_OOStringFromJSValue(context,*value);
			if (sValue.has_value())
			{
				if (AI *ai = ship->getAI())  ai->setState(*sValue);	// no AI: nothing, as a message to nil
				return true;
			}
			break;
		
		case kShip_beaconCode:
			if (EXPECT_NOT(ship->getIsPlayer()))  goto playerReadOnly;
			
			sValue = cxx_OOStringFromJSValue(context,*value);
			if (!sValue.has_value() || sValue->empty())	// nil and "" alike, as -length gave 0 for both
			{
				if (ship->isBeacon()) 
				{
					if (UNIVERSE != nullptr)  UNIVERSE->clearBeacon(entity);	// the C++ entity (bead oo-9ht.39.8.10)
					if ((PLAYER != nullptr ? PLAYER->nextBeaconEntity() : nullptr) == entity)
					{
						if (PLAYER != nullptr)  PLAYER->setCompassMode(COMPASS_MODE_PLANET);
					}
				}
			}
			else 
			{
				if (ship->isBeacon())
				{
					ship->setBeaconCode(sValue);
				}
				else // Universe needs to update beacon lists in this case only
				{
					ship->setBeaconCode(sValue);
					if (UNIVERSE != nullptr)  UNIVERSE->setNextBeacon(entity);	// the C++ entity (bead oo-9ht.39.8.10)
				}
			}
			return true;
			break;

		case kShip_beaconLabel:
			if (EXPECT_NOT(ship->getIsPlayer()))  goto playerReadOnly;
			sValue = cxx_OOStringFromJSValue(context,*value);
			if (sValue.has_value())
			{
				ship->setBeaconLabel(sValue);
				return true;
			}
			break;
			
		case kShip_accuracy:
			if (EXPECT_NOT(ship->getIsPlayer()))  goto playerReadOnly;
			
			if (ooscript::valueToNumber(context, *value, &fValue))
			{
				ship->setAccuracy(fValue);
				return true;
			}
			break;
		
		case kShip_fuel:
			if (ooscript::valueToNumber(context, *value, &fValue))
			{
				fValue = OOClamp_0_max_d(fValue, MAX_JUMP_RANGE);
				ship->setFuel(lround(fValue * 10.0));
				return true;
			}
			break;

		case kShip_entityPersonality:
			if (ooscript::valueToInt32(context, *value, &iValue))
			{
				if (iValue < 0 || iValue > (int32_t)ENTITY_PERSONALITY_MAX)
				{
					cxx_OOJSReportError(context, "ship.%s must be >= 0 and <= %u.", cxx_OOStringFromJSPropertyIDAndSpec(context, propID, sShipProperties).value_or("(null)").c_str(),ENTITY_PERSONALITY_MAX);
					return false;
				}
				ship->setEntityPersonalityInt(iValue);
				return true;
			}

		case kShip_hyperspaceSpinTime:
			if (ooscript::valueToNumber(context, *value, &fValue))
			{
				ship->setHyperspaceSpinTime(fValue);
				return true;
			}
			break;
			
		case kShip_bounty:
			if (ooscript::valueToInt32(context, *value, &iValue))
			{
				if (iValue < 0)  iValue = 0;
				ship->setBounty(iValue, kOOLegalStatusReasonByScript);
				return true;
			}
			break;

		case kShip_cargoSpaceCapacity:
			if (ooscript::valueToInt32(context, *value, &iValue))
			{
				if (iValue < 0)  iValue = 0;
				// OXPs using equipment with weight requirements may make us end up with more allocated
				// cargo space than what we have available. Do not let iValue become negative.
				if (ship->maxAvailableCargoSpace() < ship->availableCargoSpace())
				{
					iValue = 0;
				}
				else if ((OOCargoQuantity)iValue < ship->maxAvailableCargoSpace() - ship->availableCargoSpace())
				{
					iValue = ship->maxAvailableCargoSpace() - ship->availableCargoSpace();
				}
				ship->setMaxAvailableCargoSpace(iValue);
				return true;
			}
			break;


		case kShip_destinationSystem:
			if (ooscript::valueToInt32(context, *value, &iValue))
			{
				if (iValue < 0)  iValue = 0;
				ship->setDestinationSystem(iValue);
				return true;
			}
			break;

		case kShip_homeSystem:
			if (ooscript::valueToInt32(context, *value, &iValue))
			{
				if (iValue < 0)  iValue = 0;
				ship->setHomeSystem(iValue);
				return true;
			}
			break;
		
		case kShip_target:
			if (ooscript::isNull(*value))
			{
				ShipEntityJSSetTargetForScript(entity, nullptr);	// -setTargetForScript:, which no subclass overrides
				return true;
			}
			else if (JSValueToEntity(context, *value, &target) && IsShip(target))
			{
				ShipEntityJSSetTargetForScript(entity, oo::ToShip(target));
				return true;
			}
			break;
		
		case kShip_AIFoundTarget:
			if (EXPECT_NOT(ship->getIsPlayer()))  goto playerReadOnly;
			
			if (ooscript::isNull(*value))
			{
				ship->setFoundTarget(nullptr);
				return true;
			}
			else if (JSValueToEntity(context, *value, &target) && IsShip(target))
			{
				ship->setFoundTarget(target);	// the C++ entity (bead oo-9ht.39.8.11; the member takes it since oo-9ht.39.23)
				return true;
			}
			break;
		
		case kShip_AIPrimaryAggressor:
			if (EXPECT_NOT(ship->getIsPlayer()))  goto playerReadOnly;
			
			if (ooscript::isNull(*value))
			{
				ship->setPrimaryAggressor(nullptr);
				return true;
			}
			else if (JSValueToEntity(context, *value, &target) && IsShip(target))
			{
				ship->setPrimaryAggressor(target);	// the C++ entity (bead oo-9ht.39.8.11; the member takes it since oo-9ht.39.23)
				return true;
			}
			break;
			
		case kShip_group:
			group = OOShipGroupInObjectNode(cxx_OOJSPListFromJSValue(context, *value));	// a ShipGroup's group, else null
			if (group != nullptr || ooscript::isNull(*value))
			{
				ship->setGroup(group);
				return true;
			}
			break;
		
		case kShip_AIScriptWakeTime:
			if (ooscript::valueToNumber(context, *value, &fValue))
			{
				ship->setAIScriptWakeTime(fValue);
				return true;
			}
			break;

		case kShip_temperature:
			if (ooscript::valueToNumber(context, *value, &fValue))
			{
				fValue = fmax(fValue, 0.0);
				ship->setTemperature(fValue * SHIP_MAX_CABIN_TEMP);
				return true;
			}
			break;
		
		case kShip_heatInsulation:
			if (ooscript::valueToNumber(context, *value, &fValue))
			{
				fValue = fmax(fValue, 0.125);
				ship->setHeatInsulation(fValue);
				return true;
			}
			break;
		
		case kShip_isCloaked:
			if (ooscript::valueToBoolean(context, *value, &bValue))
			{
				ship->setCloaked(bValue);
				return true;
			}
			break;
			
		case kShip_cloakAutomatic:
			if (ooscript::valueToBoolean(context, *value, &bValue))
			{
				ship->setAutoCloak(bValue);
				return true;
			}
			break;
			
		case kShip_missileLoadTime:
			if (ooscript::valueToNumber(context, *value, &fValue))
			{
				ship->setMissileLoadTime(fmax(0.0, fValue));
				return true;
			}
			break;
		
		case kShip_reactionTime:
			if (EXPECT_NOT(ship->getIsPlayer()))  goto playerReadOnly;
			
			if (ooscript::valueToNumber(context, *value, &fValue))
			{
				ship->setReactionTime(fValue);
				return true;
			}
			break;

		case kShip_reportAIMessages:
			if (ooscript::valueToBoolean(context, *value, &bValue))
			{
				ship->setReportAIMessages(bValue);
				return true;
			}
			break;
			
		case kShip_trackCloseContacts:
			if (ooscript::valueToBoolean(context, *value, &bValue))
			{
				ship->setTrackCloseContacts(bValue);
				return true;
			}
			break;
		
		case kShip_isBoulder:
			if (EXPECT_NOT(ship->getIsPlayer()))  goto playerReadOnly;
			
			if (ooscript::valueToBoolean(context, *value, &bValue))
			{
				ship->setIsBoulder(bValue);
				return true;
			}
			break;
		
		case kShip_destination:
			if (EXPECT_NOT(ship->getIsPlayer()))  goto playerReadOnly;
			
			if (JSValueToHPVector(context, *value, &hpvValue))
			{
				// use setEscortDestination rather than setDestination as
				// scripted amendments shouldn't necessarily reset frustration
				ship->setEscortDestination(hpvValue);
				return true;
			}
			break;
			
		case kShip_desiredSpeed:
			if (EXPECT_NOT(ship->getIsPlayer()))  goto playerReadOnly;
			
			if (ooscript::valueToNumber(context, *value, &fValue))
			{
				ship->setDesiredSpeed(fmax(fValue, 0.0));
				return true;
			}
			break;
		
		case kShip_speed:
			// Writable so a script can put a ship at a KNOWN flight speed, and in particular can
			// hold it at rest. Writing ship.velocity is not enough on its own: that calls
			// -setTotalVelocity:, documented at ShipEntity.h:944 as setting velocity to
			// `vel - thrustVector`, i.e. the INSTANTANEOUS velocity. The engine is untouched, so
			// -applyThrust: (ShipEntity.m:6734) rebuilds thrustVector from flightSpeed on the very
			// next frame and the ship carries on. performStop() already zeroes desired_speed and
			// selects BEHAVIOUR_STOP_STILL, but flightSpeed still DECAYS to zero over several
			// frames at the ship's thrust rate rather than arriving there; this is the direct
			// write, the JS counterpart of -setSpeed: (ShipEntity.m:8575), which the engine itself
			// uses for exactly this purpose (DockEntity.m:919 launch speed, WormholeEntity.m:448
			// exit speed, ShipEntityAI.m:1765 when a ship becomes wreckage).
			//
			// PLAYER: read-only, as for desiredSpeed just above. The player's flightSpeed is
			// driven by the throttle every frame through PlayerEntity's control path, so a write
			// here would be silently reverted - a setter that does not stick is worse than none.
			if (EXPECT_NOT(ship->getIsPlayer()))  goto playerReadOnly;
			
			if (ooscript::valueToNumber(context, *value, &fValue))
			{
				// NEGATIVE IS REFUSED, NOT CLAMPED, matching maxSpeed/maxPitch/maxRoll below.
				// flightSpeed is a magnitude - thrustVector is v_forward scaled by it - so a
				// negative value means the caller wanted to reverse and got a ship flying
				// backwards along its own nose instead. Silently clamping that to 0 would hide
				// the mistake; refusing names it. NaN is refused for the same reason and by the
				// same idiom as OOJSPlayerShip.m:811 ("guard against undefined"): NaN propagates
				// into position on the next frame and poisons the entity beyond recovery.
				if (isnan(fValue) || fValue < 0)
				{
					cxx_OOJSReportError(context, "ship.speed must be a number >= 0.");
					return false;
				}
				// NOT clamped to maxSpeed at the top end, deliberately. The engine itself puts
				// flightSpeed above maxFlightSpeed on purpose - missiles (ShipEntity.m:12381,
				// `maxFlightSpeed + 300`) and fuel injectors both do - so an upper clamp here
				// would make the scripted seam weaker than the engine's own and would silently
				// rewrite a legal value. -applyThrust: already pulls flightSpeed back towards
				// desired_speed, which IS clamped to max_available_speed (ShipEntity.m:6756-6757),
				// so an over-speed write decays on its own rather than sticking.
				ship->setSpeed(fValue);
				return true;
			}
			break;
		
		case kShip_desiredRange:
			if (EXPECT_NOT(ship->getIsPlayer()))  goto playerReadOnly;
			
			if (ooscript::valueToNumber(context, *value, &fValue))
			{
				ship->setDesiredRange(fmax(fValue, 0.0));
				return true;
			}
			break;
		
		case kShip_savedCoordinates:
			if (JSValueToHPVector(context, *value, &hpvValue))
			{
				ship->setCoordinate(hpvValue);
				return true;
			}
			break;
			
		case kShip_scannerDisplayColor1:
			colorForScript = OOColor::colorWithDescription(cxx_OOJSPListFromJSValue(context, *value));
			if (colorForScript != nullptr || ooscript::isNull(*value))
			{
				ship->setScannerDisplayColor1(colorForScript.get());
				return true;
			}
			break;
			
		case kShip_scannerDisplayColor2:
			colorForScript = OOColor::colorWithDescription(cxx_OOJSPListFromJSValue(context, *value));
			if (colorForScript != nullptr || ooscript::isNull(*value))
			{
				ship->setScannerDisplayColor2(colorForScript.get());
				return true;
			}
			break;
			
		case kShip_scannerHostileDisplayColor1:
			colorForScript = OOColor::colorWithDescription(cxx_OOJSPListFromJSValue(context, *value));
			if (colorForScript != nullptr || ooscript::isNull(*value))
			{
				ship->setScannerDisplayColorHostile1(colorForScript.get());
				return true;
			}
			break;
			
		case kShip_scannerHostileDisplayColor2:
			colorForScript = OOColor::colorWithDescription(cxx_OOJSPListFromJSValue(context, *value));
			if (colorForScript != nullptr || ooscript::isNull(*value))
			{
				ship->setScannerDisplayColorHostile2(colorForScript.get());
				return true;
			}
			break;
			
		case kShip_exhaustEmissiveColor:
			colorForScript = OOColor::colorWithDescription(cxx_OOJSPListFromJSValue(context, *value));
			if (colorForScript != nullptr || ooscript::isNull(*value))
			{
				ship->setExhaustEmissiveColor(colorForScript.get());
				return true;
			}
			break;
			
		case kShip_scriptedMisjump:
			if (ooscript::valueToBoolean(context, *value, &bValue))
			{
				ship->setScriptedMisjump(bValue);
				return true;
			}
			break;

		case kShip_scriptedMisjumpRange:
			if (ooscript::valueToNumber(context, *value, &fValue))
			{
				if (fValue > 0.0 && fValue < 1.0)
				{
					ship->setScriptedMisjumpRange(fValue);
					return true;
				}
				else
				{
					cxx_OOJSReportError(context, "ship.%s must be > 0.0 and < 1.0.", cxx_OOStringFromJSPropertyIDAndSpec(context, propID, sShipProperties).value_or("(null)").c_str());
					return false;
				}
			}
			break;

		case kShip_subEntityRotation:
			if (JSValueToQuaternion(context, *value, &qValue))
			{
				ship->setSubEntityRotationalVelocity(qValue);
				return true;
			}
			break;

			
		case kShip_sunGlareFilter:
			if (ooscript::valueToNumber(context, *value, &fValue))
			{
				if (fValue >= 0.0f && fValue <= 1.0f)
				{
					ship->setSunGlareFilter(fValue);
					return true;
				}
				else
				{
					cxx_OOJSReportError(context, "ship.%s must be > 0.0 and < 1.0.", cxx_OOStringFromJSPropertyIDAndSpec(context, propID, sShipProperties).value_or("(null)").c_str());
					return false;
				}
			}
			break;
			
		case kShip_thrust:
//			if (EXPECT_NOT(ship->getIsPlayer()))  goto playerReadOnly;
			
			if (ooscript::valueToNumber(context, *value, &fValue))
			{
				ship->setThrust(OOClamp_0_max_f(fValue, ship->maxThrust()));
				return true;
			}
			break;

		case kShip_maxPitch:
			if (ooscript::valueToNumber(context, *value, &fValue))
			{
				if (fValue < 0)
				{
					cxx_OOJSReportError(context, "ship.maxPitch cannot be negative.");
					return false;
				}
				ship->setMaxFlightPitch(fValue);
				return true;
			}
			break;

		
		case kShip_maxSpeed:
			if (ooscript::valueToNumber(context, *value, &fValue))
			{
				if (fValue < 0)
				{
					cxx_OOJSReportError(context, "ship.maxSpeed cannot be negative.");
					return false;
				}
				ship->setMaxFlightSpeed(fValue);
				return true;
			}
			break;
		
		case kShip_maxRoll:
			if (ooscript::valueToNumber(context, *value, &fValue))
			{
				if (fValue < 0)
				{
					cxx_OOJSReportError(context, "ship.maxRoll cannot be negative.");
					return false;
				}
				ship->setMaxFlightRoll(fValue);
				return true;
			}
			break;
		
		case kShip_maxYaw:
			if (ooscript::valueToNumber(context, *value, &fValue))
			{
				if (fValue < 0)
				{
					cxx_OOJSReportError(context, "ship.maxYaw cannot be negative.");
					return false;
				}
				ship->setMaxFlightYaw(fValue);
				return true;
			}
			break;

		case kShip_injectorBurnRate:
			if (ooscript::valueToNumber(context, *value, &fValue))
			{
				if (fValue < 0)
				{
					cxx_OOJSReportError(context, "ship.injectorBurnRate cannot be negative.");
					return false;
				}
				ship->setAfterburnerRate(fValue);
				return true;
			}
			break;

		case kShip_injectorSpeedFactor:
			if (ooscript::valueToNumber(context, *value, &fValue))
			{
				if (fValue < 1)
				{
					cxx_OOJSReportError(context, "ship.injectorSpeedFactor cannot be less than 1.0.");
					return false;
				}
#if OO_VARIABLE_TORUS_SPEED
				else if (fValue > MIN_HYPERSPEED_FACTOR)
				{
					cxx_OOJSReportError(context, "ship.injectorSpeedFactor cannot be higher than minimum torus speed factor (%f).",MIN_HYPERSPEED_FACTOR);
					return false;
				}
#else
				else if (fValue > HYPERSPEED_FACTOR)
				{
					cxx_OOJSReportError(context, "ship.injectorSpeedFactor cannot be higher than torus speed factor (%f).",HYPERSPEED_FACTOR);
					return false;
				}
#endif
				ship->setAfterburnerFactor(fValue);
				return true;
			}
			break;


		case kShip_maxThrust:
			if (ooscript::valueToNumber(context, *value, &fValue))
			{
				if (fValue < 0)
				{
					cxx_OOJSReportError(context, "ship.maxThrust cannot be negative.");
					return false;
				}
				ship->setMaxThrust(fValue);
				return true;
			}
			break;

		case kShip_energyRechargeRate:
			if (ooscript::valueToNumber(context, *value, &fValue))
			{
				if (fValue < 0)
				{
					cxx_OOJSReportError(context, "ship.energyRechargeRate cannot be negative.");
					return false;
				}
				ship->setEnergyRechargeRate(fValue);
				return true;
			}
			break;
			

		case kShip_lightsActive:
			if (ooscript::valueToBoolean(context, *value, &bValue))
			{
				if (bValue)  ship->switchLightsOn();
				else  ship->switchLightsOff();
				return true;
			}
			break;
			
		case kShip_velocity:
			if (JSValueToVector(context, *value, &vValue))
			{
				ship->setTotalVelocity(vValue);
				return true;
			}
			break;
			
		case kShip_portWeapon:
		case kShip_starboardWeapon:
		case kShip_aftWeapon:
		case kShip_forwardWeapon:
		case kShip_currentWeapon:
			{
			const std::string weaponKey = JSValueToEquipmentKeyRelaxed(context, *value, &exists).value_or("EQ_WEAPON_NONE");
			OOWeaponFacing facing = WEAPON_FACING_FORWARD;
			switch (ooscript::idToInt32(propID))
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
					facing = ship->getCurrentWeaponFacing();
					break;
			}
			if (ship->getIsPlayer())
			{
				PlayerEntity *pent = static_cast<PlayerEntity *>(entity);
				if (pent != nullptr)  pent->setWeaponMount(facing, weaponKey, "scripted");
			}
			else
			{
				ship->setWeaponMount(facing, weaponKey);
			}
			return true;
			}

		case kShip_maxEscorts:
			if (EXPECT_NOT(ship->getIsPlayer()))  goto playerReadOnly;
			
			if (ooscript::valueToInt32(context, *value, &iValue))
			{
				OOShipGroup *escortGroup = ship->escortGroup();
				if ((NSInteger)iValue < (NSInteger)(escortGroup != nullptr ? escortGroup->count() : 0) - 1)
				{
					cxx_OOJSReportError(context, "ship.%s must be >= current escort numbers.", cxx_OOStringFromJSPropertyIDAndSpec(context, propID, sShipProperties).value_or("(null)").c_str());
					return false;
				}
				if (iValue > MAX_ESCORTS)
				{
					cxx_OOJSReportError(context, "ship.%s must be <= %d.", cxx_OOStringFromJSPropertyIDAndSpec(context, propID, sShipProperties).value_or("(null)").c_str(),MAX_ESCORTS);
					return false;
				}
				ship->setMaxEscortCount(iValue);
				return true;
			}

			break;

			
		default:
			OOJSReportBadPropertySelector(context, thisObject, propID, sShipProperties);
			return false;
	}
	
	OOJSReportBadPropertyValue(context, thisObject, propID, sShipProperties, *value);
	return false;
	
playerReadOnly:
	cxx_OOJSReportError(context, "player.ship.%s is read-only.", cxx_OOStringFromJSPropertyIDAndSpec(context, propID, sShipProperties).value_or("(null)").c_str());
	return false;

// Not used (yet)
/*
npcReadOnly:
	cxx_OOJSReportError(context, "npc.ship.%s is read-only.", cxx_OOStringFromJSPropertyIDAndSpec(context, propID, sShipProperties).value_or("(null)").c_str());
	return false;
*/

	OOJS_NATIVE_EXIT
}


// *** Methods ***

#define GET_THIS_SHIP(THISENT) do { \
	if (EXPECT_NOT(!JSShipGetShipEntity(context, OOJS_THIS, &THISENT)))  return NO; /* Exception */ \
	if (OOIsStaleEntity(THISENT))  OOJS_RETURN_VOID; \
} while (0)


// setScript(scriptName : String)
static bool ShipSetScript(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nullptr;
	std::optional<std::string>	name;
	
	GET_THIS_SHIP(thisEnt);
	ShipEntity			*ship = thisEnt;	// not null: thisEnt is not
	if (oojsArgs.count() > 0)  name = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (EXPECT_NOT(!name.has_value()))
	{
		cxx_OOJSReportBadArguments(context, "Ship", "setScript", MIN(oojsArgs.count(), 1U), OOJS_ARGV, std::nullopt, "string (script name)");
		return false;
	}
	if (EXPECT_NOT(ship->getIsPlayer()))
	{
		cxx_OOJSReportErrorForCaller(context, "Ship", "setScript", "Not valid for player ship.");
		return false;
	}
	
	ship->setShipScript(name);
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// setAI(aiName : String)
static bool ShipSetAI(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nullptr;
	std::optional<std::string>	name;
	
	GET_THIS_SHIP(thisEnt);
	ShipEntity			*ship = thisEnt;	// not null: thisEnt is not
	if (oojsArgs.count() > 0)  name = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (EXPECT_NOT(!name.has_value()))
	{
		cxx_OOJSReportBadArguments(context, "Ship", "setAI", MIN(oojsArgs.count(), 1U), OOJS_ARGV, std::nullopt, "string (AI name)");
		return false;
	}
	if (EXPECT_NOT(ship->getIsPlayer()))
	{
		cxx_OOJSReportErrorForCaller(context, "Ship", "setAI", "Not valid for player ship.");
		return false;
	}
	
	ship->setAITo(*name);
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// switchAI(aiName : String)
static bool ShipSwitchAI(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nullptr;
	std::optional<std::string>	name;
	
	GET_THIS_SHIP(thisEnt);
	ShipEntity			*ship = thisEnt;	// not null: thisEnt is not
	if (oojsArgs.count() > 0)  name = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (EXPECT_NOT(!name.has_value()))
	{
		cxx_OOJSReportBadArguments(context, "Ship", "switchAI", MIN(oojsArgs.count(), 1U), OOJS_ARGV, std::nullopt, "string (AI name)");
		return false;
	}
	if (EXPECT_NOT(ship->getIsPlayer()))
	{
		cxx_OOJSReportErrorForCaller(context, "Ship", "switchAI", "Not valid for player ship.");
		return false;
	}
	
	ship->switchAITo(*name);
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// exitAI()
static bool ShipExitAI(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nullptr;
	AI					*thisAI = nullptr;
	std::optional<std::string>	message;	// nullopt: the AI defaults to RESTARTED
	
	GET_THIS_SHIP(thisEnt);
	ShipEntity			*ship = thisEnt;	// not null: thisEnt is not
	if (EXPECT_NOT(ship->getIsPlayer()))
	{
		cxx_OOJSReportErrorForCaller(context, "Ship", "exitAI", "Not valid for player ship.");
		return false;
	}
	thisAI = ship->getAI();
	
	if (thisAI != nullptr && thisAI->hasSuspendedStateMachines())	// no AI: none, as a message to nil
	{
		if (oojsArgs.count() > 0)
		{
			message = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
		}
		// Else AI will default to RESTARTED.
		
		thisAI->exitStateMachineWithMessage(message);
	}
	else
	{
		cxx_OOJSReportWarningForCaller(context, "Ship", "exitAI()", "Cannot exit current AI state machine because there are no suspended state machines.");
	}
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// reactToAIMessage(message : String)
static bool ShipReactToAIMessage(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nullptr;
	std::optional<std::string>	message;
	
	GET_THIS_SHIP(thisEnt);
	ShipEntity			*ship = thisEnt;	// not null: thisEnt is not
	if (oojsArgs.count() > 0)  message = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (EXPECT_NOT(!message.has_value()))
	{
		cxx_OOJSReportBadArguments(context, "Ship", "reactToAIMessage", MIN(oojsArgs.count(), 1U), OOJS_ARGV, std::nullopt, "string");
		return false;
	}
	if (EXPECT_NOT(ship->getIsPlayer()))
	{
		cxx_OOJSReportErrorForCaller(context, "Ship", "reactToAIMessage", "Not valid for player ship.");
		return false;
	}
	
	ship->reactToAIMessage(*message, "JavaScript reactToAIMessage()");
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// sendAIMessage(message : String)
static bool ShipSendAIMessage(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nullptr;
	std::optional<std::string>	message;
	
	GET_THIS_SHIP(thisEnt);
	ShipEntity			*ship = thisEnt;	// not null: thisEnt is not
	if (oojsArgs.count() > 0)  message = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (EXPECT_NOT(!message.has_value()))
	{
		cxx_OOJSReportBadArguments(context, "Ship", "sendAIMessage", MIN(oojsArgs.count(), 1U), OOJS_ARGV, std::nullopt, "string");
		return false;
	}
	if (EXPECT_NOT(ship->getIsPlayer()))
	{
		cxx_OOJSReportErrorForCaller(context, "Ship", "sendAIMessage", "Not valid for player ship.");
		return false;
	}
	
	ship->sendAIMessage(*message);
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// deployEscorts()
static bool ShipDeployEscorts(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nullptr;
	
	GET_THIS_SHIP(thisEnt);
	ShipEntity			*ship = thisEnt;	// not null: thisEnt is not
	
	ship->deployEscorts();
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// dockEscorts()
static bool ShipDockEscorts(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nullptr;
	
	GET_THIS_SHIP(thisEnt);
	ShipEntity			*ship = thisEnt;	// not null: thisEnt is not
	
	ship->dockEscorts();
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// hasEquipmentProviding(equipment : String) : Boolean
static bool ShipHasEquipmentProviding(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nullptr;
	std::optional<std::string>	equipment;
	
	GET_THIS_SHIP(thisEnt);
	ShipEntity			*ship = thisEnt;	// not null: thisEnt is not
	
	if (oojsArgs.count() > 0)  equipment = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (EXPECT_NOT(!equipment.has_value()))
	{
		cxx_OOJSReportBadArguments(context, "Ship", "hasEquipmentProviding", MIN(oojsArgs.count(), 1U), OOJS_ARGV, std::nullopt, "string (equipment)");
		return false;
	}
	
	OOJS_RETURN_BOOL(ship->hasEquipmentItemProviding(*equipment));
	
	OOJS_NATIVE_EXIT
}


// hasRole(role : String) : Boolean
static bool ShipHasRole(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nullptr;
	std::optional<std::string>	role;
	
	GET_THIS_SHIP(thisEnt);
	ShipEntity			*ship = thisEnt;	// not null: thisEnt is not
	
	if (oojsArgs.count() > 0)  role = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (EXPECT_NOT(!role.has_value()))
	{
		cxx_OOJSReportBadArguments(context, "Ship", "hasRole", MIN(oojsArgs.count(), 1U), OOJS_ARGV, std::nullopt, "string (role)");
		return false;
	}
	
	OOJS_RETURN_BOOL(ship->hasRole(*role));
	
	OOJS_NATIVE_EXIT
}


// ejectItem(role : String) : Ship
static bool ShipEjectItem(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nullptr;
	std::optional<std::string>	role;
	
	GET_THIS_SHIP(thisEnt);
	ShipEntity			*ship = thisEnt;	// not null: thisEnt is not
	
	if (oojsArgs.count() > 0)  role = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (EXPECT_NOT(!role.has_value()))
	{
		cxx_OOJSReportBadArguments(context, "Ship", "ejectItem", MIN(oojsArgs.count(), 1U), OOJS_ARGV, std::nullopt, "string (role)");
		return false;
	}
	
	OOJS_RETURN(OOJSValueFromCxxObject(context, ship->ejectShipOfRole(role)));	// the C++ ship's JS value (its object's until bead oo-9ht.39.8.1)
	
	OOJS_NATIVE_EXIT
}


// addCargoEntity: ship
static bool ShipAddCargoEntity(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_NATIVE_ENTER(context)
	ShipEntity				*thisEnt = nullptr;
	ShipEntity              *target = nullptr;
	bool					procEvents = false;
	bool					procMessages = false;

	GET_THIS_SHIP(thisEnt);
	ShipEntity			*ship = thisEnt;	// not null: thisEnt is not

	if (EXPECT_NOT(ship->getIsPlayer() && (static_cast<PlayerEntity *>(thisEnt) != nullptr ? static_cast<PlayerEntity *>(thisEnt)->isDocked() : false)))
	{
		cxx_OOJSReportWarningForCaller(context, "PlayerShip", "addCargoEntity", "Can't add cargo entity while docked, ignoring.");
		return false;
	}
	if (EXPECT_NOT(oojsArgs.count() == 0 ||
				   ooscript::isNull(OOJS_ARGV[0]) ||
				   !ooscript::isObjectOrNull(OOJS_ARGV[0]) ||
				   !JSShipGetShipEntity(context, ooscript::toObject(OOJS_ARGV[0]), &target)))
	{
		cxx_OOJSReportBadArguments(context, "PlayerShip", "addCargoEntity", MIN(oojsArgs.count(), 1U), OOJS_ARGV, std::nullopt, "scoopable entity.");
		return false;
	}
	if (target == nullptr || target->getScanClass() != CLASS_CARGO)	// none: CLASS_NO_DRAW, as a message to nil
	{
		cxx_OOJSReportWarningForCaller(context, "PlayerShip", "addCargoEntity", "Scoopable entity not cargo.");
		return false;
	}
	if (target->status() != STATUS_IN_FLIGHT) 
	{
		cxx_OOJSReportWarningForCaller(context, "PlayerShip", "addCargoEntity", "Scoopable entity not in flight.");
		return false;
	}
	if (oojsArgs.count() >= 2 && EXPECT_NOT(!ooscript::valueToBoolean(context, OOJS_ARGV[1], &procEvents)))
	{
		cxx_OOJSReportBadArguments(context, "PlayerShip", "addCargoEntity", MIN(oojsArgs.count(), 2U), OOJS_ARGV, std::nullopt, "boolean");
		return false;
	}
	if (oojsArgs.count() == 3 && EXPECT_NOT(!ooscript::valueToBoolean(context, OOJS_ARGV[2], &procMessages)))
	{
		cxx_OOJSReportBadArguments(context, "PlayerShip", "addCargoEntity", MIN(oojsArgs.count(), 3U), OOJS_ARGV, std::nullopt, "boolean");
		return false;
	}
	
	// scoop the object, but don't process any events/messages unless requested
	OOJS_BEGIN_FULL_NATIVE(context)
	ship->scoopUpProcess(target, procEvents, procMessages);
	OOJS_END_FULL_NATIVE

	OOJS_RETURN_BOOL(target->status() == STATUS_IN_HOLD);

	OOJS_NATIVE_EXIT
}


// ejectSpecificItem(itemKey : String) : Ship
static bool ShipEjectSpecificItem(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nullptr;
	std::optional<std::string>	itemKey;
	
	GET_THIS_SHIP(thisEnt);
	ShipEntity			*ship = thisEnt;	// not null: thisEnt is not
	
	if (oojsArgs.count() > 0)  itemKey = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (EXPECT_NOT(!itemKey.has_value()))
	{
		cxx_OOJSReportBadArguments(context, "Ship", "ejectSpecificItem", MIN(oojsArgs.count(), 1U), OOJS_ARGV, std::nullopt, "string (ship key)");
		return false;
	}
	
	OOJS_RETURN(OOJSValueFromCxxObject(context, ship->ejectShipOfType(itemKey)));	// the C++ ship's JS value (its object's until bead oo-9ht.39.8.1)
	
	OOJS_NATIVE_EXIT
}


// dumpCargo() : Ship
static bool ShipDumpCargo(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nullptr;
	std::optional<std::string>	pref;	// nullopt: no preference

	GET_THIS_SHIP(thisEnt);
	ShipEntity			*ship = thisEnt;	// not null: thisEnt is not
	
	if (EXPECT_NOT(ship->getIsPlayer() && (static_cast<PlayerEntity *>(thisEnt) != nullptr ? static_cast<PlayerEntity *>(thisEnt)->isDocked() : false)))
	{
		cxx_OOJSReportWarningForCaller(context, "PlayerShip", "dumpCargo", "Can't dump cargo while docked, ignoring.");
		OOJS_RETURN_NULL;
	}
	
	if (oojsArgs.count() > 1)
	{
		pref = cxx_OOStringFromJSValue(context, OOJS_ARGV[1]);
	}

	// NPCs can queue multiple items to dump
	if (!EXPECT_NOT(ship->getIsPlayer()))
	{
		int32_t					i, count = 1;
		bool					gotCount = true;
		if (oojsArgs.count() > 0)  gotCount = ooscript::valueToInt32(context, OOJS_ARGV[0], &count);
		if (EXPECT_NOT(!gotCount || count < 1 || count > 64))
		{
			cxx_OOJSReportBadArguments(context, "Ship", "dumpCargo", MIN(oojsArgs.count(), 1U), OOJS_ARGV, std::nullopt, "optional quantity (1 to 64), optional preferred commodity");
			return false;
		}

		for (i = 1; i < count; i++)
		{
			// drop 3 canisters per 2 seconds (a deferred call on the C++ ship since bead oo-9ht.39.7.3; by name on its object before)
			oo::ScheduleEntityCall(thisEnt, [](Entity *entity) { if (ShipEntity *ship = dynamic_cast<ShipEntity *>(entity))  ship->dumpCargo(); }, (0.75 * i));
		}
	}

	OOJS_RETURN(OOJSValueFromCxxObject(context, ship->dumpCargoItem(pref)));	// the C++ pod's JS value (its object's until bead oo-9ht.39.8.1)
	
	OOJS_NATIVE_EXIT
}


// spawn(role : String [, number : count]) : Array
static bool ShipSpawn(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nullptr;
	std::optional<std::string>	role;
	int32_t					count = 1;
	bool					gotCount = true;
	std::vector<oo::EntityHold>	result;
	
	GET_THIS_SHIP(thisEnt);
	ShipEntity			*ship = thisEnt;	// not null: thisEnt is not
	
	if (oojsArgs.count() > 0)  role = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (oojsArgs.count() > 1)  gotCount = ooscript::valueToInt32(context, OOJS_ARGV[1], &count);
	if (EXPECT_NOT(!role.has_value() || !gotCount || count < 1 || count > 64))
	{
		cxx_OOJSReportBadArguments(context, "Ship", "spawn", MIN(oojsArgs.count(), 1U), OOJS_ARGV, std::nullopt, "role and optional quantity (1 to 64)");
		return false;
	}
	
	OOJS_BEGIN_FULL_NATIVE(context)
	result = ship->spawnShipsWithRole(*role, count);
	OOJS_END_FULL_NATIVE

	OOJS_RETURN_PLIST(oo::EntityNodesFrom(result));
	
	OOJS_NATIVE_EXIT
}


// dealEnergyDamage(). Replaces AI's dealEnergyDamageWithinDesiredRange
static bool ShipDealEnergyDamage(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nullptr;
	double baseDamage;
	double range;
	double velocityBias = 0.0;
	bool gotDamage;
	bool gotRange;
	bool gotVBias;
	GET_THIS_SHIP(thisEnt);
	ShipEntity			*ship = thisEnt;	// not null: thisEnt is not

	if (oojsArgs.count() < 2)
	{
		cxx_OOJSReportBadArguments(context, "Ship", "dealEnergyDamage", oojsArgs.count(), OOJS_ARGV, std::nullopt, "damage and range needed");
		return false;
	}
	
	gotDamage = ooscript::valueToNumber(context, OOJS_ARGV[0], &baseDamage);
	if (EXPECT_NOT(!gotDamage || baseDamage < 0))
	{
		cxx_OOJSReportBadArguments(context, "Ship", "dealEnergyDamage", oojsArgs.count(), OOJS_ARGV, std::nullopt, "damage must be positive");
		return false;
	}
	gotRange = ooscript::valueToNumber(context, OOJS_ARGV[1], &range);
	if (EXPECT_NOT(!gotRange || range < 0))
	{
		cxx_OOJSReportBadArguments(context, "Ship", "dealEnergyDamage", oojsArgs.count(), OOJS_ARGV, std::nullopt, "range must be positive");
		return false;
	}
	if (oojsArgs.count() >= 3) 
	{
		gotVBias = ooscript::valueToNumber(context, OOJS_ARGV[2], &velocityBias);
		if (!gotVBias)
		{
			cxx_OOJSReportBadArguments(context, "Ship", "dealEnergyDamage", oojsArgs.count(), OOJS_ARGV, std::nullopt, "velocity bias must be a number");
			return false;
		}
	}

	ship->dealEnergyDamage((GLfloat)baseDamage, (GLfloat)range, (GLfloat)velocityBias);

	OOJS_RETURN_VOID;

	OOJS_NATIVE_EXIT
}


// explode()
static bool ShipExplode(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_NATIVE_ENTER(context)
	
	return RemoveOrExplodeShip(context, oojsArgs, YES);
	
	OOJS_NATIVE_EXIT
}


// remove([suppressDeathEvent : Boolean = false])
static bool ShipRemove(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nullptr;
	bool					suppressDeathEvent = false;
	
	GET_THIS_SHIP(thisEnt);
	ShipEntity			*ship = thisEnt;	// not null: thisEnt is not
	
	if (ship->getIsPlayer())
	{
		cxx_OOJSReportError(context, "Cannot remove() player's ship.");
		return false;
	}
	
	if (oojsArgs.count() > 0 && EXPECT_NOT(!ooscript::valueToBoolean(context, OOJS_ARGV[0], &suppressDeathEvent)))
	{
		cxx_OOJSReportBadArguments(context, "Ship", "remove", oojsArgs.count(), OOJS_ARGV, std::nullopt, "boolean");
		return false;
	}

	ship->doScriptEvent(OOJSID("shipRemoved"), { oo::PList(static_cast<bool>(suppressDeathEvent)) });

	if (suppressDeathEvent)
	{
		ship->removeScript();
	}
	return RemoveOrExplodeShip(context, oojsArgs, false);
	
	OOJS_NATIVE_EXIT
}


// __runLegacyScriptActions(target : Ship, actions : Array)
static bool ShipRunLegacyScriptActions(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nullptr;
	PlayerEntity			*player = nullptr;
	ShipEntity				*target = nullptr;
	oo::PList				actions;	// null when absent
	
	player = OOPlayerForScripting();
	GET_THIS_SHIP(thisEnt);
	ShipEntity			*ship = thisEnt;	// not null: thisEnt is not
	
	if (oojsArgs.count() > 1)  actions = cxx_OOJSPListFromJSValue(context, OOJS_ARGV[1]);
	if (EXPECT_NOT(oojsArgs.count() != 2 ||
				   !ooscript::isObjectOrNull(OOJS_ARGV[0]) ||
				   !JSShipGetShipEntity(context, ooscript::toObject(OOJS_ARGV[0]), &target) ||
				   !actions.isArray()))
	{
		cxx_OOJSReportBadArguments(context, "Ship", "__runLegacyScriptActions", oojsArgs.count(), OOJS_ARGV, std::nullopt, "target and array of actions");
		return false;
	}
	
	if (target != nullptr)	// Not stale reference
	{
		if (player != nullptr)  player->setScriptTarget(thisEnt);
		if (player != nullptr)  player->runUnsanitizedScriptActions(actions, true, oo::str::format("<ship \"%s\" legacy actions>", ship->getName().value_or("(null)").c_str()), target);
	}
	
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// commsMessage(message : String[,target : Ship])
static bool ShipCommsMessage(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nullptr;
	std::optional<std::string>	message;
	ShipEntity				*target = nullptr;
	
	GET_THIS_SHIP(thisEnt);
	ShipEntity			*ship = thisEnt;	// not null: thisEnt is not
	
	if (oojsArgs.count() > 0)  message = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (EXPECT_NOT(!message.has_value() || (oojsArgs.count() > 1 && (ooscript::isNull(OOJS_ARGV[1]) || !ooscript::isObjectOrNull(OOJS_ARGV[1]) || !JSShipGetShipEntity(context, ooscript::toObject(OOJS_ARGV[1]), &target)))))
	{
		cxx_OOJSReportBadArguments(context, "Ship", "commsMessage", MIN(oojsArgs.count(), 1U), OOJS_ARGV, std::nullopt, "message and optional target");
		return false;
	}
	
	if (oojsArgs.count() < 2)
	{
		ship->commsMessage(*message, true);	// generic broadcast
	}
	else if (target != nullptr)  // Not stale reference
	{
		ship->sendMessage(*message, target, true);	// ship-to-ship narrowcast
	}
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// fireECM()
static bool ShipFireECM(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nullptr;
	bool					OK;
	
	GET_THIS_SHIP(thisEnt);
	ShipEntity			*ship = thisEnt;	// not null: thisEnt is not
	
	OK = ship->fireECM();
	if (!OK)
	{
		// The C++ ship's JS description (bead oo-9ht.39.8.8): what its object's OOObjectJSDescription() made of the same
		// jsClassName() and descriptionComponents().
		cxx_OOJSReportWarning(context, "Ship %s was requested to fire ECM burst but does not carry ECM equipment.", EntityJSDescription(thisEnt).value_or("(null)").c_str());
	}
	
	OOJS_RETURN_BOOL(OK);
	
	OOJS_NATIVE_EXIT
}


// abandonShip()
static bool ShipAbandonShip(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nullptr;
	
	GET_THIS_SHIP(thisEnt);
	ShipEntity			*ship = thisEnt;	// not null: thisEnt is not
	OOJS_RETURN_BOOL(ship->hasEscapePod() && ship->abandonShip());
	
	OOJS_NATIVE_EXIT
}


// canAwardEquipment(type : equipmentInfoExpression)
static bool ShipCanAwardEquipment(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity					*thisEnt = nullptr;
	std::optional<std::string>	key;
	std::string					ctx = "scripted";	// a nil context fails the check below, as "" does
	bool						result;
	BOOL						exists;
	
	GET_THIS_SHIP(thisEnt);
	ShipEntity			*ship = thisEnt;	// not null: thisEnt is not
	
	if (oojsArgs.count() > 0)  key = JSValueToEquipmentKeyRelaxed(context, OOJS_ARGV[0], &exists);
	if (EXPECT_NOT(!key.has_value()))
	{
		cxx_OOJSReportBadArguments(context, "Ship", "canAwardEquipment", MIN(oojsArgs.count(), 1U), OOJS_ARGV, std::nullopt, "equipment type");
		return false;
	}
	
	if (exists)
	{
		if (oojsArgs.count() > 1)
		{
			ctx = cxx_OOStringFromJSValue(context, OOJS_ARGV[1]).value_or(std::string());
			if (ctx != "scripted" && ctx != "purchase" && ctx != "newShip" && ctx != "npc")
			{
				cxx_OOJSReportBadArguments(context, "Ship", "canAwardEquipment", MIN(oojsArgs.count(), 2U), OOJS_ARGV, std::nullopt, "context");
				return false;
			}
		}
		result = true;
		
		// can't add fuel as equipment.
		if (*key == "EQ_FUEL")  result = false;
		
		if (result)  result = ship->canAddEquipment(*key, ctx);
	}
	else
	{
		// Unknown type.
		result = false;
	}
	
	OOJS_RETURN_BOOL(result);
	
	OOJS_NATIVE_EXIT
}


// awardEquipment(type : equipmentInfoExpression) : Boolean
static bool ShipAwardEquipment(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity					*thisEnt = nullptr;
	OOEquipmentType				*eqType = nullptr;
	std::string					identifier;
	bool						OK = true;
	bool						berth;
	bool            isRepair = false;
	
	GET_THIS_SHIP(thisEnt);
	ShipEntity			*ship = thisEnt;	// not null: thisEnt is not
	
	if (oojsArgs.count() > 0)  eqType = JSValueToEquipmentType(context, OOJS_ARGV[0]);
	if (EXPECT_NOT(eqType == nullptr))
	{
		cxx_OOJSReportBadArguments(context, "Ship", "awardEquipment", MIN(oojsArgs.count(), 1U), OOJS_ARGV, std::nullopt, "equipment type");
		return false;
	}
	
	// Check that equipment is permitted.
	OOEquipmentType *cxxEqType = eqType;	// not null: eqType is not
	identifier = cxxEqType->identifier().value_or("");
	berth = identifier == "EQ_PASSENGER_BERTH";
	if (berth)
	{
		OK = ship->availableCargoSpace() >= cxxEqType->requiredCargoSpace();
	}
	else if (identifier == "EQ_FUEL")
	{
		OK = false;
	}
	else
	{
		OK = cxxEqType->canCarryMultiple() || !ship->hasEquipmentItem(oo::PList(identifier));
	}
	
	if (OK)
	{
		if (ship->getIsPlayer())
		{
			PlayerEntity *player = static_cast<PlayerEntity *>(thisEnt);
			
			if (identifier == "EQ_MISSILE_REMOVAL")
			{
				ship->removeMissiles();	// PlayerEntity's, through the virtual
			}
			else if (cxxEqType->isMissileOrMine())
			{
				OK = (player != nullptr ? player->mountMissileWithRole(identifier) : false);
			}
			else if (berth)
			{
				OK = (player != nullptr ? player->changePassengerBerths(+1) : false);
			}
			else if (identifier == "EQ_PASSENGER_BERTH_REMOVAL")
			{
				OK = (player != nullptr ? player->changePassengerBerths(-1) : false);
			}
			else
			{
				isRepair = ship->hasEquipmentItem(oo::PList(identifier + "_DAMAGED"));
				OK = ship->addEquipmentItem(identifier, true, "scripted");	// PlayerEntity's, through the virtual
				if (OK && isRepair) 
				{
					ship->doScriptEvent(OOJSID("equipmentRepaired"), { oo::PList(identifier) });
				}
			}
		}
		else
		{
			if (identifier == "EQ_MISSILE_REMOVAL")
			{
				ship->removeMissiles();
			}
			// no passenger handling for NPCs. EQ_CARGO_BAY is dealt with inside addEquipmentItem
			else if (!berth && identifier != "EQ_PASSENGER_BERTH_REMOVAL")
			{
				OK = ship->addEquipmentItem(identifier, true, "scripted");	
			}
			else
			{
				OK = false;
			}
		}
	}
	
	OOJS_RETURN_BOOL(OK);
	
	OOJS_NATIVE_EXIT
}


// removeEquipment(type : equipmentInfoExpression)
static bool ShipRemoveEquipment(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity					*thisEnt = nullptr;
	std::optional<std::string>	key;
	bool						OK = true;
	
	GET_THIS_SHIP(thisEnt);
	ShipEntity			*ship = thisEnt;	// not null: thisEnt is not
	
	if (oojsArgs.count() > 0)  key = JSValueToEquipmentKey(context, OOJS_ARGV[0]);
	if (EXPECT_NOT(!key.has_value()))
	{
		cxx_OOJSReportBadArguments(context, "Ship", "removeEquipment", MIN(oojsArgs.count(), 1U), OOJS_ARGV, std::nullopt, "equipment type");
		return false;
	}
	// berths are not in hasOneEquipmentItem
	OK = ship->hasOneEquipmentItemIncludingMissiles(*key, true, false) || (*key == "EQ_PASSENGER_BERTH" && ship->passengerCapacity() > 0);
	if (!OK)
	{
		// Allow removal of damaged equipment.
		key = *key + "_DAMAGED";
		OK = ship->hasOneEquipmentItemIncludingMissiles(*key, false, false);
	}
	if (OK)
	{
		//exceptions
		if (*key == "EQ_PASSENGER_BERTH" || *key == "EQ_CARGO_BAY")
		{
			if (*key == "EQ_PASSENGER_BERTH")
			{
				if (ship->passengerCapacity() > ship->passengerCount())
				{
					// must be the player's ship!
					if (ship->getIsPlayer())  static_cast<PlayerEntity *>(thisEnt)->changePassengerBerths(-1);	// thisEnt is not null here
				}
				else OK = false;
			}
			else	// EQ_CARGO_BAY
			{
				// player cargo bay removal handled in script
				if (ship->getIsPlayer() || ship->extraCargo() <= ship->availableCargoSpace())
				{
					ship->removeEquipmentItem(*key);
				}
				else OK = false;
			}
		}
		else
			ship->removeEquipmentItem(*key);
	}
	
	OOJS_RETURN_BOOL(OK);
	
	OOJS_NATIVE_EXIT
}


// restoreSubEntities(): boolean
static bool ShipRestoreSubEntities(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nullptr;
	NSUInteger				numSubEntitiesRestored = 0U;
	
	GET_THIS_SHIP(thisEnt);
	ShipEntity			*ship = thisEnt;	// not null: thisEnt is not
	
	NSUInteger subCount = ShipEntityJSSubEntitiesForScript(thisEnt).size();	// -subEntitiesForScript
	
	ship->clearSubEntities();
	ship->setUpSubEntities();
	
	if (ShipEntityJSSubEntitiesForScript(thisEnt).size() - subCount > 0)  numSubEntitiesRestored = ShipEntityJSSubEntitiesForScript(thisEnt).size() - subCount;
	
	// for each subentity restored, slightly increase the trade-in factor
	if (ship->getIsPlayer())
	{
		int tradeInFactorChange = (int)MAX(PLAYER_SHIP_SUBENTITY_TRADE_IN_VALUE * numSubEntitiesRestored, 25U);
		if (static_cast<PlayerEntity *>(thisEnt) != nullptr)  static_cast<PlayerEntity *>(thisEnt)->adjustTradeInFactorBy(tradeInFactorChange);
	}
	
	OOJS_RETURN_BOOL(numSubEntitiesRestored > 0);
	
	OOJS_NATIVE_EXIT
}



// setEquipmentStatus(type : equipmentInfoExpression, status : String): boolean
static bool ShipSetEquipmentStatus(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_NATIVE_ENTER(context)
	
	// equipment status accepted: @"EQUIPMENT_OK", @"EQUIPMENT_DAMAGED"
	
	ShipEntity				*thisEnt = nullptr;
	OOEquipmentType			*eqType = nullptr;
	std::string				key;
	std::string				damagedKey;
	std::optional<std::string>	status;
	bool					hasOK = false, hasDamaged = false;
	
	GET_THIS_SHIP(thisEnt);
	ShipEntity			*ship = thisEnt;	// not null: thisEnt is not
	
	if (oojsArgs.count() < 2)
	{
		cxx_OOJSReportBadArguments(context, "Ship", "setEquipmentStatus", oojsArgs.count(), OOJS_ARGV, std::nullopt, "equipment type and status");
		return false;
	}
	
	eqType = JSValueToEquipmentType(context, OOJS_ARGV[0]);
	if (EXPECT_NOT(eqType == nullptr))
	{
		cxx_OOJSReportBadArguments(context, "Ship", "setEquipmentStatus", 1, &OOJS_ARGV[0], std::nullopt, "equipment type");
		return false;
	}
	
	status = cxx_OOStringFromJSValue(context, OOJS_ARGV[1]);
	if (EXPECT_NOT(!status.has_value()))
	{
		cxx_OOJSReportBadArguments(context, "Ship", "setEquipmentStatus", 1, &OOJS_ARGV[1], std::nullopt, "equipment status");
		return false;
	}
	
	// EMMSTRAN: use interned strings.
	if (*status != "EQUIPMENT_OK" && *status != "EQUIPMENT_DAMAGED")
	{
		cxx_OOJSReportErrorForCaller(context, "Ship", "setEquipmentStatus", "Second parameter for setEquipmentStatus must be either \"EQUIPMENT_OK\" or \"EQUIPMENT_DAMAGED\".");
		return false;
	}
	
	OOEquipmentType *cxxEqType = eqType;	// not null: eqType is not
	key = cxxEqType->identifier().value_or("");
	hasOK = ship->hasEquipmentItem(oo::PList(key));
	bool setOK = *status == "EQUIPMENT_OK";
	bool setDamaged = *status == "EQUIPMENT_DAMAGED";
	if (cxxEqType->canBeDamaged())
	{
		damagedKey = key + "_DAMAGED";
		hasDamaged = ship->hasEquipmentItem(oo::PList(damagedKey));
		
		if ((setOK && hasDamaged) || (setDamaged && hasOK))
		{
			// the implementation is identical between player and ship.
			ship->removeEquipmentItem(setDamaged ? key : damagedKey);
			if (ship->getIsPlayer())
			{
				// these player methods are different to the ship ones.
				ship->addEquipmentItem(setDamaged ? damagedKey : key, false, "scripted");	// PlayerEntity's, through the virtual
				if (setDamaged)
				{
					ship->doScriptEvent(OOJSID("equipmentDamaged"), { oo::PList(key) });
				}
				else if (setOK)
				{
					ship->doScriptEvent(OOJSID("equipmentRepaired"), { oo::PList(key) });
				}
				
				// if player's Docking Computers are set to EQUIPMENT_DAMAGED while on, stop them
				// this is now done in a different method
				// if (hasOK && [key isEqualToString:@"EQ_DOCK_COMP"])  [(PlayerEntity*)thisEnt disengageAutopilot];
			}
			else
			{
				ship->addEquipmentItem(setDamaged ? damagedKey : key, false, "scripted");
				if (hasOK) ship->doScriptEvent(OOJSID("equipmentDamaged"), { oo::PList(key) });
			}
		}
	}
	else
	{
		if (hasOK && *status != "EQUIPMENT_OK")
		{
			cxx_OOJSReportWarningForCaller(context, "Ship", "setEquipmentStatus", "Equipment %s cannot be damaged.", key.c_str());
			hasOK = false;
		}
	}
	
	OOJS_RETURN_BOOL(hasOK || hasDamaged);
	
	OOJS_NATIVE_EXIT
}


// equipmentStatus(type : equipmentInfoExpression) : String
static bool ShipEquipmentStatus(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_NATIVE_ENTER(context)
	
	/*
		Interned string constants.
		Interned strings are guaranteed to survive for the lifetime of the JS
		runtime, which lasts as long as Oolite is running.
	*/
	static ooscript::Value strOK, strDamaged, strUnavailable, strUnknown;
	static bool inited = false;
	if (EXPECT_NOT(!inited))
	{
		inited = true;
		strOK = ooscript::stringValue(ooscript::internString(context, "EQUIPMENT_OK"));
		strDamaged = ooscript::stringValue(ooscript::internString(context, "EQUIPMENT_DAMAGED"));
		strUnavailable = ooscript::stringValue(ooscript::internString(context, "EQUIPMENT_UNAVAILABLE"));
		strUnknown = ooscript::stringValue(ooscript::internString(context, "EQUIPMENT_UNKNOWN"));
	}
	
	ShipEntity				*thisEnt = nullptr;
	std::optional<std::string>	key;
	bool					asDict = false;

	GET_THIS_SHIP(thisEnt);
	ShipEntity			*ship = thisEnt;	// not null: thisEnt is not
	
	if (oojsArgs.count() > 0)  key = JSValueToEquipmentKey(context, OOJS_ARGV[0]);
	if (oojsArgs.count() > 1)  ooscript::valueToBoolean(context, OOJS_ARGV[1], &asDict);
	if (EXPECT_NOT(!key.has_value()))
	{
		if (oojsArgs.count() > 0 && ooscript::isString(OOJS_ARGV[0]))
		{
			if (asDict)
			{
				OOJS_RETURN_PLIST(oo::PList(oo::PList::Dict{ { "EQUIPMENT_UNKNOWN", oo::PList::signedInteger(1) } }));
			}
			else
			{
				OOJS_RETURN(strUnknown);
			}
		}
		
		cxx_OOJSReportBadArguments(context, "Ship", "equipmentStatus", MIN(oojsArgs.count(), 1U), &OOJS_ARGV[0], std::nullopt, "equipment type");
		return false;
	}
	

	if (asDict)
	{
		oo::PList::Dict dict;
		dict["EQUIPMENT_OK"] = oo::PList::unsignedInteger(ship->countEquipmentItem(*key));
		dict["EQUIPMENT_DAMAGED"] = oo::PList::unsignedInteger(ship->countEquipmentItem(*key + "_DAMAGED"));
		OOJS_RETURN_PLIST(oo::PList(std::move(dict)));
	}
	else
	{
		if (ship->hasEquipmentItem(oo::PList(*key), true, false))  OOJS_RETURN(strOK);
		else if (ship->hasEquipmentItem(oo::PList(*key + "_DAMAGED")))  OOJS_RETURN(strDamaged);
	
		OOJS_RETURN(strUnavailable);
	}
	OOJS_NATIVE_EXIT
}


// selectNewMissile()
static bool ShipSelectNewMissile(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nullptr;
	
	GET_THIS_SHIP(thisEnt);
	ShipEntity			*ship = thisEnt;	// not null: thisEnt is not
	
	// if there's a badly defined missile, selectMissile may return nil
	OOEquipmentType *missile = ship->selectMissile();
	const std::string result = ((missile != nullptr) ? missile->identifier() : std::nullopt).value_or("EQ_MISSILE");
	
	OOJS_RETURN_PLIST(oo::PList(result));
	
	OOJS_NATIVE_EXIT
}


// fireMissile()
static bool ShipFireMissile(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity			*thisEnt = nullptr;
	ShipEntity			*result = nullptr;
	
	GET_THIS_SHIP(thisEnt);
	ShipEntity			*ship = thisEnt;	// not null: thisEnt is not
	
	if (oojsArgs.count() > 0)  result = ship->fireMissileWithIdentifier(cxx_OOStringFromJSValue(context, OOJS_ARGV[0]), ship->primaryTarget());
	else  result = ship->fireMissile();
	
	OOJS_RETURN(OOJSValueFromCxxObject(context, result));	// the C++ missile's JS value (its object's until bead oo-9ht.39.8.1)
	
	OOJS_NATIVE_EXIT
}


// findNearestStation
static bool ShipFindNearestStation(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity			*thisEnt = nullptr;
	ShipEntity			*result = nullptr;	// a station (its object until bead oo-9ht.144)

	GET_THIS_SHIP(thisEnt);
	ShipEntity			*ship = thisEnt;	// not null: thisEnt is not

	double				sdist, distance = 1E32;
	
	ShipEntity			*se = nullptr;
	for (const auto &stationRef : (UNIVERSE != nullptr ? UNIVERSE->stations() : std::vector<oo::EntityHold>()))
	{
		se = oo::ToShip(stationRef.get());
		sdist = HPdistance2(ship->getPosition(), (se != nullptr ? se->getPosition() : kZeroHPVector));	// (a message to nil answered zero)

		if (sdist < distance)
		{
			distance = sdist;
			result = se;
		}
	}
	
	OOJS_RETURN(OOJSValueFromCxxObject(context, result));	// the C++ station's JS value (its object's until bead oo-9ht.39.8.1)
	
	OOJS_NATIVE_EXIT
}


// setBounty(amount, reason)
static bool ShipSetBounty(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nullptr;
	std::optional<std::string>	reason;
	int32_t					newbounty = 0;
	bool					gotBounty = true;
	
	GET_THIS_SHIP(thisEnt);
	ShipEntity			*ship = thisEnt;	// not null: thisEnt is not
	
	if (oojsArgs.count() > 0)  gotBounty = ooscript::valueToInt32(context, OOJS_ARGV[0], &newbounty);
	if (oojsArgs.count() > 1)  reason = cxx_OOStringFromJSValue(context, OOJS_ARGV[1]);
	if (EXPECT_NOT(!reason.has_value() || !gotBounty || newbounty < 0))
	{
		cxx_OOJSReportBadArguments(context, "Ship", "setBounty", oojsArgs.count(), OOJS_ARGV, std::nullopt, "new bounty and reason");
		return false;
	}
	
	ship->setBounty((OOCreditsQuantity)newbounty, *reason);
	
	return true;
	
	OOJS_NATIVE_EXIT
}


// setCargo(cargoType : String [, number : count])
static bool ShipSetCargo(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nullptr;
	std::optional<std::string>	commodity;
	int32_t					count = 1;
	bool					gotCount = true;
	
	GET_THIS_SHIP(thisEnt);
	ShipEntity			*ship = thisEnt;	// not null: thisEnt is not
	
	if (oojsArgs.count() > 0)  commodity = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (oojsArgs.count() > 1)  gotCount = ooscript::valueToInt32(context, OOJS_ARGV[1], &count);
	if (EXPECT_NOT(!commodity.has_value() || !gotCount || count < 1))
	{
		cxx_OOJSReportBadArguments(context, "Ship", "setCargo", oojsArgs.count(), OOJS_ARGV, std::nullopt, "cargo name and optional positive quantity");
		return false;
	}
	
	OOCommodities *commodities = (UNIVERSE != nullptr ? UNIVERSE->getCommodities() : nullptr);	// null: no good is defined, as a message to nil
	if (commodities != nullptr && commodities->goodDefined(*commodity))
	{
		ship->setCommodityForPod(commodity, count);
	}
	
	OOJS_RETURN_BOOL(commodities != nullptr && commodities->goodDefined(*commodity));
	
	OOJS_NATIVE_EXIT
}


// setCrew(crewDefinition : Object)
static bool ShipSetCrew(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	/* TODO: ships can in theory have multiple crew, so this could
	 * allow that to be set. Probably not necessary for now. */
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nullptr;
	ooscript::Object params = NULL;

	GET_THIS_SHIP(thisEnt);
	ShipEntity			*ship = thisEnt;	// not null: thisEnt is not
	
	if (oojsArgs.count() < 1 || (!ooscript::isNull(OOJS_ARGV[0]) && !ooscript::valueToObject(context, OOJS_ARGV[0], &params)))
	{
		cxx_OOJSReportBadArguments(context, "Ship", "setCrew", MIN(oojsArgs.count(), 1U), OOJS_ARGV, std::nullopt, "definition");
		return false;
	}
	bool success = true;

	if (!ship->isExplicitlyUnpiloted())
	{
		if (ooscript::isNull(OOJS_ARGV[0]))
		{
			ship->setCrew(std::nullopt);
		}
		else
		{
			const oo::Ref<OOCharacter> crew = OOCharacter::characterWithDictionary(cxx_OOJSPListFromJSObject(context, ooscript::toObject(OOJS_ARGV[0])));
			std::vector<oo::Ref<OOCharacter>> members;
			if (crew != nullptr)  members.emplace_back(crew);	// a nil character was skipped (a Foundation array cannot hold nil)
			ship->setCrew(members);
		}
	}
	else
	{
		success = false;
	}

	OOJS_RETURN_BOOL(success);
	
	OOJS_NATIVE_EXIT
}


// setCargoType(cargoType : String)
static bool ShipSetCargoType(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nullptr;
	std::optional<std::string>	cargoType;
	
	GET_THIS_SHIP(thisEnt);
	ShipEntity			*ship = thisEnt;	// not null: thisEnt is not
	
	if (oojsArgs.count() > 0)  cargoType = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (EXPECT_NOT(!cargoType.has_value()))
	{
		cxx_OOJSReportBadArguments(context, "Ship", "setCargoType", oojsArgs.count(), OOJS_ARGV, std::nullopt, "cargo type name");
		return false;
	}
	if (ship->cargoType() != CARGO_NOT_CARGO)
	{
		cxx_OOJSReportBadArguments(context, "Ship", "setCargoType", oojsArgs.count(), OOJS_ARGV, std::nullopt, oo::str::format("Can only be used on cargo pod carriers, not cargo pods (%s)", ship->shipDataKey().value_or("(null)").c_str()));
		return false;
	}
	bool ok = true;
	if (*cargoType == "SCARCE_GOODS")
	{
		ship->setCargoFlag(CARGO_FLAG_FULL_SCARCE);
	}
	else if (*cargoType == "PLENTIFUL_GOODS")
	{
		ship->setCargoFlag(CARGO_FLAG_FULL_PLENTIFUL);
	}
	else if (*cargoType == "MEDICAL_GOODS")
	{
		ship->setCargoFlag(CARGO_FLAG_FULL_MEDICAL);
	}
	else if (*cargoType == "ILLEGAL_GOODS")
	{
		ship->setCargoFlag(CARGO_FLAG_FULL_CONTRABAND);
	}
	else if (*cargoType == "PIRATE_GOODS")
	{
		ship->setCargoFlag(CARGO_FLAG_PIRATE);
	}	
	else
	{
		ok = false;
	}
	OOJS_RETURN_BOOL(ok);

	OOJS_NATIVE_EXIT
}

// setMaterials(params: dict, [shaders: dict])  // sets materials dictionary. Optional parameter sets the shaders dictionary too.
static bool ShipSetMaterials(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nil;
	
	if (oojsArgs.count() < 1)
	{
		cxx_OOJSReportBadArguments(context, "Ship", "setMaterials", 0, OOJS_ARGV, std::nullopt, "parameter object");
		return NO;
	}
	
	GET_THIS_SHIP(thisEnt);
	
	return ShipSetMaterialsInternal(context, oojsArgs, thisEnt, NO);
	
	OOJS_NATIVE_EXIT
}


// setShaders(params: dict) 
static bool ShipSetShaders(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nil;
	
	GET_THIS_SHIP(thisEnt);
	
	if (oojsArgs.count() < 1)
	{
		cxx_OOJSReportBadArguments(context, "Ship", "setShaders", 0, OOJS_ARGV, std::nullopt, "parameter object");
		return NO;
	}
	
	if (ooscript::isNull(OOJS_ARGV[0]) || (!ooscript::isNull(OOJS_ARGV[0]) && !ooscript::isObjectOrNull(OOJS_ARGV[0])))
	{
		// EMMSTRAN: ooscript::valueToObject() and normal error handling here.
		cxx_OOJSReportWarning(context, "Ship.%s: expected %s instead of '%s'.", "setShaders", "object", cxx_OOStringFromJSValueEvenIfNull(context, OOJS_ARGV[0]).value_or("(null)").c_str());
		OOJS_RETURN_BOOL(NO);
	}
	
	OOJS_ARGV[1] = OOJS_ARGV[0];
	return ShipSetMaterialsInternal(context, oojsArgs, thisEnt, YES);
	
	OOJS_NATIVE_EXIT
}


namespace {
bool ShipSetMaterialsInternal(ooscript::Context context, ooscript::CallArgs &oojsArgs, ShipEntity *thisEnt, bool fromShaders)
{
	OOJS_PROFILE_ENTER
	
	ooscript::Object params = NULL;
	oo::PList				materials;
	oo::PList				shaders;
	bool					withShaders = false;
	bool					success = false;
	
	GET_THIS_SHIP(thisEnt);
	ShipEntity			*ship = thisEnt;	// not null: thisEnt is not
	
	if (ooscript::isNull(OOJS_ARGV[0]) || (!ooscript::isNull(OOJS_ARGV[0]) && !ooscript::isObjectOrNull(OOJS_ARGV[0])))
	{
		cxx_OOJSReportWarning(context, "Ship.%s: expected %s instead of '%s'.", "setMaterials", "object", cxx_OOStringFromJSValueEvenIfNull(context, OOJS_ARGV[0]).value_or("(null)").c_str());
		OOJS_RETURN_BOOL(false);
	}
	
	if (oojsArgs.count() > 1)
	{
		withShaders = true;
		if (ooscript::isNull(OOJS_ARGV[1]) || (!ooscript::isNull(OOJS_ARGV[1]) && !ooscript::isObjectOrNull(OOJS_ARGV[1])))
		{
			cxx_OOJSReportWarning(context, "Ship.%s: expected %s instead of '%s'.",  "setMaterials", "object as second parameter", cxx_OOStringFromJSValueEvenIfNull(context, OOJS_ARGV[1]).value_or("(null)").c_str());
			withShaders = false;
		}
	}
	
	if (fromShaders)
	{
		materials = MeshMaterials(ship);
		params = ooscript::toObject(OOJS_ARGV[0]);
		shaders = cxx_OOJSPListFromJSObject(context, params);
	}
	else
	{
		params = ooscript::toObject(OOJS_ARGV[0]);
		materials = cxx_OOJSPListFromJSObject(context, params);
		if (withShaders)
		{
			params = ooscript::toObject(OOJS_ARGV[1]);
			shaders = cxx_OOJSPListFromJSObject(context, params);
		}
		else
		{
			shaders = MeshShaders(ship);
		}
	}

	OOJS_BEGIN_FULL_NATIVE(context)
	const oo::PList			shipDict = ship->shipInfoDictionary();
	// "ship-prefix-macros": a dictionary, else null (as the dictionary reader gave nil).
	const oo::PList			materialDefaults = ResourceManager::materialDefaults();
	const oo::PList			*prefixMacros = materialDefaults.find("ship-prefix-macros");

	// First we test to see if we can create the mesh.
	const oo::Ref<OOMesh> mesh = OOMesh::meshWithName(shipDict.get<std::string>("model"),
							   std::nullopt,
					 materials,
					  shaders,
								 shipDict.get<bool>("smooth", false),
						   (prefixMacros != nullptr && prefixMacros->isDict()) ? *prefixMacros : oo::PList(),
					thisEnt);	// the C++ ship (bead oo-9ht.39.6)
	
	if (mesh != nullptr)
	{
		ship->setMesh(mesh.get());
		success = true;
	}
	OOJS_END_FULL_NATIVE
	
	OOJS_RETURN_BOOL(success);
	
	OOJS_PROFILE_EXIT
}
}


// exitSystem([int systemID])
static bool ShipExitSystem(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity			*thisEnt = nullptr;
	int32_t				systemID = -1;
	bool				OK = false;
	
	GET_THIS_SHIP(thisEnt);
	ShipEntity			*ship = thisEnt;	// not null: thisEnt is not
	if (EXPECT_NOT(ship->getIsPlayer()))
	{
		cxx_OOJSReportErrorForCaller(context, "Ship", "exitSystem", "Not valid for player ship.");
		return false;
	}
	
	if (oojsArgs.count() > 0)
	{
		if (!ooscript::valueToInt32(context, OOJS_ARGV[0], &systemID) || systemID < 0 || 255 < systemID)
		{
			cxx_OOJSReportBadArguments(context, "Ship", "exitSystem", MIN(oojsArgs.count(), 1U), OOJS_ARGV, std::nullopt, "system ID");
			return false;
		}
	}
	
	OK = ship->performHyperSpaceToSpecificSystem(systemID); 	// -1 == random destination system
	
	OOJS_RETURN_BOOL(OK);
	
	OOJS_NATIVE_EXIT
}


static bool ShipUpdateEscortFormation(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity *thisEnt = nullptr;
	GET_THIS_SHIP(thisEnt);
	ShipEntity			*ship = thisEnt;	// not null: thisEnt is not
	ship->updateEscortFormation();
	
	OOJS_RETURN_VOID;
	
	OOJS_PROFILE_EXIT
}

namespace {
bool RemoveOrExplodeShip(ooscript::Context context, ooscript::CallArgs &oojsArgs, bool explode)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity				*thisEnt = nullptr;
	
	GET_THIS_SHIP(thisEnt);
	ShipEntity			*ship = thisEnt;	// not null: thisEnt is not
	
	if (EXPECT_NOT(ship->getIsPlayer()))
	{
		OOCAssert(explode, "RemoveOrExplodeShip(): shouldn't be called for player with !explode.");	// player.ship.remove() is blocked by caller.
		PlayerEntity *player = static_cast<PlayerEntity *>(thisEnt);
		
		if ((player != nullptr ? player->isDocked() : false))
		{
			cxx_OOJSReportError(context, "Cannot explode() player's ship while docked.");
			return false;
		}
	}
	
	if (thisEnt == oo::ToShip((UNIVERSE != nullptr ? UNIVERSE->station() : nullptr)))	// the C++ station (through its object until bead oo-9ht.39.8.1)
	{
		// Allow exploding of main station (e.g. nova mission)
		if (UNIVERSE != nullptr)  UNIVERSE->unMagicMainStation();
	}
	
	if (EXPECT_NOT(ship->status() == STATUS_DOCKED))
	{
		/* If it's in the launch queue and hasn't yet been added to
		 * the universe, set the status to DEAD (so it gets removed
		 * from the launch queue) */
		ship->setStatus(STATUS_DEAD);
		/* No shipDied event occurs in this place - it never really
		 * existed. This case is just to prevent an error from the
		 * usual code branch - removing ships while they're still
		 * docked is not recommended. */
	}
	else
	{
		ship->setSuppressExplosion(!explode);
		ship->setEnergy(1);
		ship->takeEnergyDamage(500000000.0, nullptr, nullptr, std::string());
	}
	
	OOJS_RETURN_VOID;
	
	OOJS_PROFILE_EXIT
}
}

static bool ShipClearDefenseTargets(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity *thisEnt = nullptr;
	GET_THIS_SHIP(thisEnt);
	ShipEntity			*ship = thisEnt;	// not null: thisEnt is not
	ship->removeAllDefenseTargets();
	
	OOJS_RETURN_VOID;
	
	OOJS_PROFILE_EXIT
}


static bool ShipAddDefenseTarget(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity *thisEnt = nullptr;
	ShipEntity				*target = nullptr;

	GET_THIS_SHIP(thisEnt);
	ShipEntity			*ship = thisEnt;	// not null: thisEnt is not
	if (EXPECT_NOT(oojsArgs.count() == 0 || (oojsArgs.count() > 0 && (ooscript::isNull(OOJS_ARGV[0]) || !ooscript::isObjectOrNull(OOJS_ARGV[0]) || !JSShipGetShipEntity(context, ooscript::toObject(OOJS_ARGV[0]), &target)))))
	{
		cxx_OOJSReportBadArguments(context, "Ship", "addDefenseTarget", 1U, OOJS_ARGV, std::nullopt, "target");
		return false;
	}
	
	ship->addDefenseTarget(target);	// the C++ ship (bead oo-9ht.39.8.11; the member takes it since oo-9ht.39.23)

	OOJS_RETURN_VOID;
	
	OOJS_PROFILE_EXIT
}


static bool ShipRemoveDefenseTarget(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity *thisEnt = nullptr;
	ShipEntity				*target = nullptr;

	GET_THIS_SHIP(thisEnt);
	ShipEntity			*ship = thisEnt;	// not null: thisEnt is not
	if (EXPECT_NOT(oojsArgs.count() == 0 || (oojsArgs.count() > 0 && (ooscript::isNull(OOJS_ARGV[0]) || !ooscript::isObjectOrNull(OOJS_ARGV[0]) || !JSShipGetShipEntity(context, ooscript::toObject(OOJS_ARGV[0]), &target)))))
	{
		cxx_OOJSReportBadArguments(context, "Ship", "removeDefenseTarget", 1U, OOJS_ARGV, std::nullopt, "target");
		return false;
	}
	
	ship->removeDefenseTarget(target);	// the C++ ship (bead oo-9ht.39.8.11; the member takes it since oo-9ht.39.23)

	OOJS_RETURN_VOID;
	
	OOJS_PROFILE_EXIT
}


static bool ShipAddCollisionException(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity *thisEnt = nullptr;
	ShipEntity				*target = nullptr;

	GET_THIS_SHIP(thisEnt);
	ShipEntity			*ship = thisEnt;	// not null: thisEnt is not
	if (EXPECT_NOT(oojsArgs.count() == 0 || (oojsArgs.count() > 0 && (ooscript::isNull(OOJS_ARGV[0]) || !ooscript::isObjectOrNull(OOJS_ARGV[0]) || !JSShipGetShipEntity(context, ooscript::toObject(OOJS_ARGV[0]), &target)))))
	{
		cxx_OOJSReportBadArguments(context, "Ship", "addCollisionException", 1U, OOJS_ARGV, std::nullopt, "other ship");
		return false;
	}
	
	// have to do it both ways because it's not defined which order
	// the collisions get tested in. More efficient to add both ways
    // than to test both ways
	ship->addCollisionException(target);
	if (target != nullptr)  target->addCollisionException(thisEnt);	// none: nothing, as a message to nil

	OOJS_RETURN_VOID;
	
	OOJS_PROFILE_EXIT
}


static bool ShipRemoveCollisionException(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity *thisEnt = nullptr;
	ShipEntity				*target = nullptr;

	GET_THIS_SHIP(thisEnt);
	ShipEntity			*ship = thisEnt;	// not null: thisEnt is not
	if (EXPECT_NOT(oojsArgs.count() == 0 || (oojsArgs.count() > 0 && (ooscript::isNull(OOJS_ARGV[0]) || !ooscript::isObjectOrNull(OOJS_ARGV[0]) || !JSShipGetShipEntity(context, ooscript::toObject(OOJS_ARGV[0]), &target)))))
	{
		cxx_OOJSReportBadArguments(context, "Ship", "removeCollisionException", 1U, OOJS_ARGV, std::nullopt, "other ship");
		return false;
	}
	
	// doesn't need a check to see if it was already gone
	ship->removeCollisionException(target);
	if (target != nullptr)  target->removeCollisionException(thisEnt);	// none: nothing, as a message to nil

	OOJS_RETURN_VOID;
	
	OOJS_PROFILE_EXIT
}


//getMaterials()
static bool ShipGetMaterials(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity		*thisEnt = nullptr;

	GET_THIS_SHIP(thisEnt);
	ShipEntity			*ship = thisEnt;	// not null: thisEnt is not

	oo::PList result = MeshMaterials(ship);
	if (result.isNull())  result = oo::PList(oo::PList::Dict{});	// empty rather than null
	OOJS_RETURN_PLIST(result);
	
	OOJS_PROFILE_EXIT
}

//getShaders()
static bool ShipGetShaders(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity		*thisEnt = nullptr;

	GET_THIS_SHIP(thisEnt);
	ShipEntity			*ship = thisEnt;	// not null: thisEnt is not

	oo::PList result = MeshShaders(ship);
	if (result.isNull())  result = oo::PList(oo::PList::Dict{});	// empty rather than null
	OOJS_RETURN_PLIST(result);
	
	OOJS_PROFILE_EXIT
}

static bool ShipBroadcastCascadeImminent(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity *thisEnt = nullptr;
	GET_THIS_SHIP(thisEnt);
	ShipEntity			*ship = thisEnt;	// not null: thisEnt is not
	ship->broadcastEnergyBlastImminent();
	
	OOJS_RETURN_VOID;
	
	OOJS_PROFILE_EXIT
}

static bool ShipBecomeCascadeExplosion(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity *thisEnt = nullptr;
	GET_THIS_SHIP(thisEnt);
	ShipEntity			*ship = thisEnt;	// not null: thisEnt is not
	ship->becomeEnergyBlast();
	
	OOJS_RETURN_VOID;
	
	OOJS_PROFILE_EXIT
}


static bool ShipOfferToEscort(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity *thisEnt = nullptr;
	ShipEntity				*mother = nullptr;

	GET_THIS_SHIP(thisEnt);
	ShipEntity			*ship = thisEnt;	// not null: thisEnt is not
	if (EXPECT_NOT(oojsArgs.count() == 0 || (oojsArgs.count() > 0 && (ooscript::isNull(OOJS_ARGV[0]) || !ooscript::isObjectOrNull(OOJS_ARGV[0]) || !JSShipGetShipEntity(context, ooscript::toObject(OOJS_ARGV[0]), &mother)))))
	{
		cxx_OOJSReportBadArguments(context, "Ship", "offerToEscort", 1U, OOJS_ARGV, std::nullopt, "target");
		return false;
	}
	
	bool result = ship->suggestEscortTo(mother);

	OOJS_RETURN_BOOL(result);
	
	OOJS_PROFILE_EXIT
}


static bool ShipRequestHelpFromGroup(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity *thisEnt = nullptr;

	GET_THIS_SHIP(thisEnt);
	ShipEntity			*ship = thisEnt;	// not null: thisEnt is not
	
	ship->groupAttackTarget();

	OOJS_RETURN_VOID;
	
	OOJS_PROFILE_EXIT
}


static bool ShipPatrolReportIn(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity *thisEnt = nullptr;
	ShipEntity				*target = nullptr;

	GET_THIS_SHIP(thisEnt);
	if (EXPECT_NOT(oojsArgs.count() == 0 || (oojsArgs.count() > 0 && (ooscript::isNull(OOJS_ARGV[0]) || !ooscript::isObjectOrNull(OOJS_ARGV[0]) || !JSShipGetShipEntity(context, ooscript::toObject(OOJS_ARGV[0]), &target)))))
	{
		cxx_OOJSReportBadArguments(context, "Ship", "addDefenseTarget", 1U, OOJS_ARGV, std::nullopt, "target");
		return false;
	}
	if (target != nullptr && target->getIsStation())	// none: not a station, as a message to nil
	{
		StationEntity *station = oo::ToStation(target);	// the C++ ship (through its object until bead oo-9ht.39.8.1)
		station->acceptPatrolReportFrom(thisEnt);
	}

	OOJS_RETURN_VOID;
	
	OOJS_PROFILE_EXIT
}


static bool ShipMarkTargetForFines(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity *thisEnt = nullptr;

	GET_THIS_SHIP(thisEnt);

	ShipEntity *ship = oo::ToShip(thisEnt->primaryTarget());
	bool ok = false;
	if ((ship != nullptr) && (ship->status() != STATUS_DEAD) && (ship->status() != STATUS_DOCKED))
	{
		ok = ship->markForFines();
	}

	OOJS_RETURN_BOOL(ok);
	
	OOJS_PROFILE_EXIT
}


static bool ShipEnterWormhole(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity *thisEnt = nullptr;
	Entity	*hole = nullptr;

	if ((PLAYER != nullptr ? PLAYER->status() : OOEntityStatus{}) != STATUS_ENTERING_WITCHSPACE)
	{
		cxx_OOJSReportError(context, "Cannot use this function while player's ship not entering witchspace.");
		return false;
	}

	GET_THIS_SHIP(thisEnt);
	ShipEntity			*ship = thisEnt;	// not null: thisEnt is not
	if (EXPECT_NOT(oojsArgs.count() == 0 || (oojsArgs.count() > 0 && !ooscript::isNull(OOJS_ARGV[0]) && (!ooscript::isObjectOrNull(OOJS_ARGV[0]) || !OOJSEntityGetEntity(context, ooscript::toObject(OOJS_ARGV[0]), &hole)))))
	{
		ship->enterPlayerWormhole();
	}
	else 
	{
		if (hole == nullptr || !hole->getIsWormhole())	// none: not a wormhole, as a message to nil
		{
			cxx_OOJSReportBadArguments(context, "Ship", "enterWormhole", 1U, OOJS_ARGV, std::nullopt, "[wormhole]");
			return false;
		}

		ship->enterWormhole(static_cast<WormholeEntity *>(hole));	// the C++ wormhole (a C-style cast of its object until bead oo-9ht.144)
	}

	OOJS_RETURN_VOID;
	
	OOJS_PROFILE_EXIT
}


static bool ShipNotifyGroupOfWormhole(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity *thisEnt = nullptr;
	GET_THIS_SHIP(thisEnt);
	ShipEntity			*ship = thisEnt;	// not null: thisEnt is not

	ship->wormholeEntireGroup();

	OOJS_RETURN_VOID;
	
	OOJS_PROFILE_EXIT
}


static bool ShipThrowSpark(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity *thisEnt = nullptr;
	GET_THIS_SHIP(thisEnt);
	ShipEntity			*ship = thisEnt;	// not null: thisEnt is not
	ship->setThrowSparks(true);
	
	OOJS_RETURN_VOID;
	
	OOJS_PROFILE_EXIT
}



static bool ShipPerformAttack(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity *thisEnt = nullptr;
	GET_THIS_SHIP(thisEnt);
	ShipEntity			*ship = thisEnt;	// not null: thisEnt is not
	ship->performAttack();
	
	OOJS_RETURN_VOID;
	
	OOJS_PROFILE_EXIT
}


static bool ShipPerformCollect(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity *thisEnt = nullptr;
	GET_THIS_SHIP(thisEnt);
	ShipEntity			*ship = thisEnt;	// not null: thisEnt is not
	ship->performCollect();
	
	OOJS_RETURN_VOID;
	
	OOJS_PROFILE_EXIT
}


static bool ShipPerformEscort(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity *thisEnt = nullptr;
	GET_THIS_SHIP(thisEnt);
	ShipEntity			*ship = thisEnt;	// not null: thisEnt is not
	ship->performEscort();
	
	OOJS_RETURN_VOID;
	
	OOJS_PROFILE_EXIT
}


static bool ShipPerformFaceDestination(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity *thisEnt = nullptr;
	GET_THIS_SHIP(thisEnt);
	ShipEntity			*ship = thisEnt;	// not null: thisEnt is not
	ship->performFaceDestination();
	
	OOJS_RETURN_VOID;
	
	OOJS_PROFILE_EXIT
}


static bool ShipPerformFlee(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity *thisEnt = nullptr;
	GET_THIS_SHIP(thisEnt);
	ShipEntity			*ship = thisEnt;	// not null: thisEnt is not
	ship->performFlee();
	
	OOJS_RETURN_VOID;
	
	OOJS_PROFILE_EXIT
}


static bool ShipPerformFlyToRangeFromDestination(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity *thisEnt = nullptr;
	GET_THIS_SHIP(thisEnt);
	ShipEntity			*ship = thisEnt;	// not null: thisEnt is not
	ship->performFlyToRangeFromDestination();
	
	OOJS_RETURN_VOID;
	
	OOJS_PROFILE_EXIT
}


static bool ShipPerformHold(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity *thisEnt = nullptr;
	GET_THIS_SHIP(thisEnt);
	ShipEntity			*ship = thisEnt;	// not null: thisEnt is not
	ship->performHold();
	
	OOJS_RETURN_VOID;
	
	OOJS_PROFILE_EXIT
}


static bool ShipPerformIdle(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity *thisEnt = nullptr;
	GET_THIS_SHIP(thisEnt);
	ShipEntity			*ship = thisEnt;	// not null: thisEnt is not
	ship->performIdle();
	
	OOJS_RETURN_VOID;
	
	OOJS_PROFILE_EXIT
}


static bool ShipPerformIntercept(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity *thisEnt = nullptr;
	GET_THIS_SHIP(thisEnt);
	ShipEntity			*ship = thisEnt;	// not null: thisEnt is not
	ship->performIntercept();
	
	OOJS_RETURN_VOID;
	
	OOJS_PROFILE_EXIT
}


static bool ShipPerformLandOnPlanet(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity *thisEnt = nullptr;
	GET_THIS_SHIP(thisEnt);
	ShipEntity			*ship = thisEnt;	// not null: thisEnt is not
	ship->performLandOnPlanet();
	
	OOJS_RETURN_VOID;
	
	OOJS_PROFILE_EXIT
}


static bool ShipPerformMining(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity *thisEnt = nullptr;
	GET_THIS_SHIP(thisEnt);
	ShipEntity			*ship = thisEnt;	// not null: thisEnt is not
	ship->performMining();
	
	OOJS_RETURN_VOID;
	
	OOJS_PROFILE_EXIT
}


static bool ShipPerformScriptedAI(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity *thisEnt = nullptr;
	GET_THIS_SHIP(thisEnt);
	ShipEntity			*ship = thisEnt;	// not null: thisEnt is not
	ship->performScriptedAI();
	
	OOJS_RETURN_VOID;
	
	OOJS_PROFILE_EXIT
}


static bool ShipPerformScriptedAttackAI(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity *thisEnt = nullptr;
	GET_THIS_SHIP(thisEnt);
	ShipEntity			*ship = thisEnt;	// not null: thisEnt is not
	ship->performScriptedAttackAI();
	
	OOJS_RETURN_VOID;
	
	OOJS_PROFILE_EXIT
}


static bool ShipPerformStop(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity *thisEnt = nullptr;
	GET_THIS_SHIP(thisEnt);
	ShipEntity			*ship = thisEnt;	// not null: thisEnt is not
	ship->performStop();
	
	OOJS_RETURN_VOID;
	
	OOJS_PROFILE_EXIT
}


static bool ShipPerformTumble(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity *thisEnt = nullptr;
	GET_THIS_SHIP(thisEnt);
	ShipEntity			*ship = thisEnt;	// not null: thisEnt is not
	ship->performTumble();
	
	OOJS_RETURN_VOID;
	
	OOJS_PROFILE_EXIT
}


static bool ShipRequestDockingInstructions(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity *thisEnt = nullptr;
	GET_THIS_SHIP(thisEnt);
	ShipEntity			*ship = thisEnt;	// not null: thisEnt is not
	ship->requestDockingCoordinates();
	
	OOJS_RETURN_PLIST(ship->getDockingInstructions());	// nil maps to null
	
	OOJS_PROFILE_EXIT
}


static bool ShipRecallDockingInstructions(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity *thisEnt = nullptr;
	GET_THIS_SHIP(thisEnt);
	ShipEntity			*ship = thisEnt;	// not null: thisEnt is not
	ship->recallDockingInstructions();
	
	OOJS_RETURN_PLIST(ship->getDockingInstructions());	// nil maps to null
	
	OOJS_PROFILE_EXIT
}


static bool ShipBroadcastDistressMessage(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity *thisEnt = nullptr;
	GET_THIS_SHIP(thisEnt);
	ShipEntity			*ship = thisEnt;	// not null: thisEnt is not
	ship->broadcastDistressMessageWithDumping(false);
	
	OOJS_RETURN_VOID;
	
	OOJS_PROFILE_EXIT
}


static bool ShipCheckCourseToDestination(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity *thisEnt = nullptr;
	GET_THIS_SHIP(thisEnt);
	ShipEntity			*ship = thisEnt;	// not null: thisEnt is not

	Entity *hazard = (UNIVERSE != nullptr ? UNIVERSE->hazardOnRouteFromEntity(thisEnt, ship->desiredRange(), ship->destination()) : nullptr);	// the C++ entities (bead oo-9ht.39.8.6)

	OOJS_RETURN(OOJSValueFromCxxObject(context, hazard));	// the C++ hazard's JS value (its object's until bead oo-9ht.39.8.6)

	OOJS_PROFILE_EXIT
}


static bool ShipGetSafeCourseToDestination(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity *thisEnt = nullptr;
	GET_THIS_SHIP(thisEnt);
	ShipEntity			*ship = thisEnt;	// not null: thisEnt is not

	HPVector waypoint = (UNIVERSE != nullptr ? UNIVERSE->getSafeVectorFromEntity(thisEnt, ship->desiredRange(), ship->destination()) : HPVector{});	// the C++ ship (bead oo-9ht.39.8.6)

	OOJS_RETURN_HPVECTOR(waypoint);

	OOJS_PROFILE_EXIT

}


static bool ShipCheckScanner(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity *thisEnt = nullptr;
	bool	onlyCheckPowered = false;
	
	GET_THIS_SHIP(thisEnt);
	ShipEntity			*ship = thisEnt;	// not null: thisEnt is not
	
	if (oojsArgs.count() > 0 && EXPECT_NOT(!ooscript::valueToBoolean(context, OOJS_ARGV[0], &onlyCheckPowered)))
	{
		cxx_OOJSReportBadArguments(context, "Ship", "checkScanner", oojsArgs.count(), OOJS_ARGV, std::nullopt, "boolean");
		return false;
	}

	if (onlyCheckPowered)
	{
		ship->checkScannerIgnoringUnpowered();
	}
	else
	{
		ship->checkScanner();
	}
	ShipEntity **scannedShips = ship->scannedShips();
	unsigned num = ship->numberOfScannedShips();
	oo::PList::Array scanResult;
	for (unsigned i = 0; i < num; i++)
	{
		if (scannedShips[i] != nullptr)  scanResult.push_back(oo::EntityObjectNode(scannedShips[i]));	// nil skipped, as a Foundation array skipped it
	}
	OOJS_RETURN_PLIST(oo::PList(std::move(scanResult)));

	OOJS_PROFILE_EXIT
}


static bool ShipAdjustCargo(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity *thisEnt = nullptr;
	std::optional<std::string> commodity;
	int32_t adjustment = 0;

	GET_THIS_SHIP(thisEnt);
	ShipEntity			*ship = thisEnt;	// not null: thisEnt is not
	
	if (oojsArgs.count() < 2)
	{
		cxx_OOJSReportBadArguments(context, "Ship", "adjustCargo", oojsArgs.count(), OOJS_ARGV, std::nullopt, "commodity, amount");
		return false;
	}

	commodity = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (!ooscript::valueToInt32(context, OOJS_ARGV[1], &adjustment))
	{
		cxx_OOJSReportBadArguments(context, "Ship", "adjustCargo", oojsArgs.count(), OOJS_ARGV, std::nullopt, "commodity, amount");
		return false;
	}

	if (ship->cargoType() != CARGO_NOT_CARGO || ship->getIsPlayer())
	{
		cxx_OOJSReportError(context, "ship.adjustCargo may only be used on NPC cargo carriers");
		return false;
	}

	bool ok = true;

	if (adjustment > 0)
	{
		ok = ship->addCargo((UNIVERSE != nullptr ? UNIVERSE->getContainersOfCommodity(commodity.value_or(""), adjustment) : std::vector<oo::EntityHold>())); // non-reified templates
	}
	else if (adjustment < 0)
	{
		OOCargoQuantity r = (OOCargoQuantity)(-adjustment);
		ok = ship->removeCargo(commodity.value_or(""), r);
	}


	OOJS_RETURN_BOOL(ok);

	OOJS_PROFILE_EXIT
}


/* 0 = no significant damage or consumable loss, higher numbers mean some */
static bool ShipDamageAssessment(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity *thisEnt = nullptr;
	int			assessment = 0;
	
	GET_THIS_SHIP(thisEnt);
	ShipEntity			*ship = thisEnt;	// not null: thisEnt is not
	
	// if could have missiles but doesn't, consumables low
	if (ship->missileCapacity() > 0 && ship->missilesList().empty())
	{
		assessment++;
	}
	// if has injectors but fuel is low, consumables low
	// if no injectors, not a problem
	if (ship->hasFuelInjection() && ship->getFuel() < 35)
	{
		assessment++;
	}

	/* TODO: when NPC equipment can be damaged in combat, assess this
	 * here */

	OOJS_RETURN_INT(assessment);

	OOJS_PROFILE_EXIT
}



static bool ShipThreatAssessment(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity *thisEnt = nullptr;
	bool	fullCheck = false;
	
	GET_THIS_SHIP(thisEnt);
	ShipEntity			*ship = thisEnt;	// not null: thisEnt is not
	
	if (oojsArgs.count() > 0 && EXPECT_NOT(!ooscript::valueToBoolean(context, OOJS_ARGV[0], &fullCheck)))
	{
		cxx_OOJSReportBadArguments(context, "Ship", "threatAssessment", oojsArgs.count(), OOJS_ARGV, std::nullopt, "boolean");
		return false;
	}
	// start with 2.5 per ship
	double assessment = 2.5;
	// +/- 0.1 for speed, larger subtraction for very slow ships
	GLfloat maxspeed = ship->getMaxFlightSpeed();
	assessment += (maxspeed-300)/1000;
	if (maxspeed < 200)
	{
		assessment += (maxspeed-200)/500;
	}
	
	/* FIXME: at the moment this means NPCs can detect other NPCs shield
	 * boosters, since they're implemented as extra energy */
	assessment += (ship->getMaxEnergy()-200)/1000; 
	
	// add on some for missiles. Mostly ignore 3rd and subsequent
	// missiles: either they can be ECMd or the first two are already
	// too many.
	if (ship->missileCapacity() > 2)
	{
		assessment += 0.5;
	}
	else
	{
		assessment += ((double)ship->missileCapacity())/5.0;
	}

	/* Turret count is public knowledge */
	/* TODO: consider making ship combat behaviour try to
	 * stay at long range from enemies with turrets. Then
	 * we could perhaps reduce this bonus a bit. */
	assessment += ship->turretCount();

	if (fullCheck)
	{
		// consider pilot skill
		if (ship->getIsPlayer())
		{
			double score = (double)(PLAYER != nullptr ? PLAYER->score() : unsigned{});
			if (score > 6400) 
			{
				score = 6400;
			}
			assessment += pow(score,0.33)/10;
			// 0 - 1.8
		}
		else
		{
			assessment += ship->getAccuracy()/5;
		}

		// check lasers
		OOWeaponType wt = ship->weaponTypeIDForFacing(WEAPON_FACING_FORWARD, false);
		/* Not affected by multiple mounts here: they're either just a
		 * split of the power, or only more dangerous until they
		 * overheat */
		assessment += ShipThreatAssessmentWeapon(wt);
		if (isWeaponNone(wt))
		{
			assessment -= 1.5; // further penalty for ships with no forward laser
		}

		wt = ship->weaponTypeIDForFacing(WEAPON_FACING_AFT, false);
		if (!isWeaponNone(wt))
		{
			assessment += 1 + ShipThreatAssessmentWeapon(wt);
		}
		// port and starboard weapons less important
		wt = ship->weaponTypeIDForFacing(WEAPON_FACING_PORT, false);
		if (!isWeaponNone(wt))
		{
			assessment += 0.2 + ShipThreatAssessmentWeapon(wt)/5.0;
		}
		wt = ship->weaponTypeIDForFacing(WEAPON_FACING_STARBOARD, false);
		if (!isWeaponNone(wt))
		{
			assessment += 0.2 + ShipThreatAssessmentWeapon(wt)/5.0;
		}

		// combat-related secondary equipment
		if (ship->hasECM())
		{
			assessment += 0.5;
		}
		if (ship->hasFuelInjection())
		{
			assessment += 0.5;
		}

	}
	else
	{
		// consider thargoids dangerous
		if (ship->isThargoid())
		{
			assessment *= 1.5;
			if (ship->hasRole("thargoid-mothership"))
			{
				assessment += 5;
			}
		}
		else
		{
			// consider that armed ships might have a trick or two
			if (ship->weaponFacings() == 1)
			{
				assessment += 0.25;
			}
			else
			{
				// and more than one trick if they can mount multiple lasers
				assessment += 0.5;
			}
		}
	}

	// mostly ignore fleeing ships as threats
	if (ship->getBehaviour() == BEHAVIOUR_FLEE_TARGET || ship->getBehaviour() == BEHAVIOUR_FLEE_EVASIVE_ACTION)
	{
		assessment *= 0.2;
	}
	else if (ship->getIsPlayer() && (static_cast<PlayerEntity *>(thisEnt) != nullptr ? static_cast<PlayerEntity *>(thisEnt)->fleeingStatus() : OOPlayerFleeingStatus{}) >= PLAYER_FLEEING_CARGO)
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
	if (wt == nullptr)
	{
		return -1.0;
	}
	return wt->weaponThreatAssessment();
}


/** Static methods */

static bool ShipStaticKeys(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_NATIVE_ENTER(context);
	OOShipRegistry		*registry = OOShipRegistry::sharedRegistry();

	OOJS_RETURN_PLIST(StringArray(registry->shipKeys()));

	OOJS_NATIVE_EXIT
}

static bool ShipStaticKeysForRole(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_NATIVE_ENTER(context);
	OOShipRegistry		*registry = OOShipRegistry::sharedRegistry();

	if (oojsArgs.count() > 0)
	{
		const std::string role = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]).value_or(std::string());	// nil as "", as the registry bridge sent it
		// null where there is no probability set for the role, as before
		if (registry->probabilitySetForRole(role) == nullptr)  OOJS_RETURN_NULL;
		OOJS_RETURN_PLIST(StringArray(registry->shipKeysWithRole(role)));
	}
	else
	{
		cxx_OOJSReportBadArguments(context, "Ship", "shipKeysForRole", MIN(oojsArgs.count(), 1U), OOJS_ARGV, std::nullopt, "ship role");
		return false;
	}

	OOJS_NATIVE_EXIT
}


static bool ShipStaticRoleIsInCategory(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_NATIVE_ENTER(context);

	if (oojsArgs.count() > 1)
	{
		const std::optional<std::string> role = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
		const std::optional<std::string> category = cxx_OOStringFromJSValue(context, OOJS_ARGV[1]);

		OOJS_RETURN_BOOL(role.has_value() && category.has_value() && (UNIVERSE != nullptr ? UNIVERSE->role(*role, *category) : false));	// a nil role or category matched nothing
	}
	else
	{
		cxx_OOJSReportBadArguments(context, "Ship", "roleIsInCategory", MIN(oojsArgs.count(), 2U), OOJS_ARGV, std::nullopt, "role, category");
		return false;
	}

	OOJS_NATIVE_EXIT
}


static bool ShipStaticRoles(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_NATIVE_ENTER(context);
	OOShipRegistry		*registry = OOShipRegistry::sharedRegistry();

	OOJS_RETURN_PLIST(StringArray(registry->shipRoles()));

	OOJS_NATIVE_EXIT
}


static bool ShipStaticShipDataForKey(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_NATIVE_ENTER(context);
	OOShipRegistry		*registry = OOShipRegistry::sharedRegistry();

	if (oojsArgs.count() > 0)
	{
		const std::optional<std::string> key = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
		if (!key.has_value())  OOJS_RETURN_NULL;	// a nil key found nothing
		OOJS_RETURN_PLIST(registry->shipInfoForKey(*key));
	}
	else
	{
		cxx_OOJSReportBadArguments(context, "Ship", "shipDataForKey", MIN(oojsArgs.count(), 1U), OOJS_ARGV, std::nullopt, "key");
		return false;
	}
	OOJS_NATIVE_EXIT
}


static bool ShipStaticSetShipDataForKey(ooscript::Context context, ooscript::CallArgs &oojsArgs)
{
	OOJS_NATIVE_ENTER(context);
	OOShipRegistry				*registry = OOShipRegistry::sharedRegistry();

	if (oojsArgs.count() >= 2)
	{
		registry->setShipInfoForKey(cxx_OOStringFromJSValue(context, OOJS_ARGV[0]).value_or(std::string()), cxx_OOJSPListFromJSObject(context, ooscript::toObject(OOJS_ARGV[1])));
		OOJS_RETURN_BOOL(true);
	}
	else
	{
		cxx_OOJSReportBadArguments(context, "Ship", "setShipInfoForKey", MIN(oojsArgs.count(), 2U), OOJS_ARGV, std::nullopt, "key shipdata");
		return false;
	}
	OOJS_NATIVE_EXIT
}
