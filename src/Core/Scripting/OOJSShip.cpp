/*

OOJSShip.m (QuickJS-ng)

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

#include <cstddef>
#include <cstdint>
#include <format>
#include <map>
#include <optional>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

#include "AI.h"
#include "EntityOOJavaScriptExtensions.h"
#include "GameController.h"
#include "OOCallByName.h"
#include "OOCharacter.h"
#include "OOColor.h"
#include "OOCommodities.h"
#include "OOConstToString.h"
#include "OODescription.h"
#include "OOEntityFilterPredicate.h"
#include "OOEquipmentType.h"
#include "OOJSEntity.h"
#include "OOJSEquipmentInfo.h"
#include "OOJSPlayer.h"
#include "OOJSQuaternion.h"
#include "OOJSVector.h"
#include "OOJSWormhole.h"
#include "OOJavaScriptEngine.h"
#include "OOMesh.h"
#include "OORoleSet.h"
#include "OOScript.h"
#include "OOShipGroup.h"
#include "OOShipRegistry.h"
#include "OOStringParsing.h"
#include "PlayerEntity.h"
#include "PlayerEntityLegacyScriptEngine.h"
#include "PlayerEntityScriptMethods.h"
#include "ResourceManager.h"
#include "ShipEntity.h"
#include "ShipEntityAI.h"
#include "ShipEntityScriptMethods.h"
#include "StationEntity.h"
#include "Universe.h"
#include "WormholeEntity.h"
#include "oofnd/PList.hpp"
#include "oofnd/String.hpp"
#include "oofnd/objc/OOAssert.h"

namespace {

// The weapon offsets as the old accessors handed them to JavaScript: an array
// of OONativeVector (as the Objective-C bridge built it).
oo::PList NativeVectorArray(const std::vector<Vector>& vectors) {
  oo::PList::Array result;
  result.reserve(vectors.size());
  for (Vector v : vectors) {
    // The box is the Object node's foreign object; the engine gives JavaScript
    // its Vector3D.
    result.push_back(
        oo::PList(oo::PList::Object(oo::makeRef<OONativeVector>(v))));
  }
  return oo::PList(std::move(result));
}

}  // namespace

static JSClassID sShipClassID;

static JSValue ShipGetProperty(OOJS_GETTER_ARGS);
static JSValue ShipSetProperty(OOJS_SETTER_ARGS);

static JSValue ShipSetScript(OOJS_NATIVE_ARGS);
static JSValue ShipSetAI(OOJS_NATIVE_ARGS);
static JSValue ShipSwitchAI(OOJS_NATIVE_ARGS);
static JSValue ShipExitAI(OOJS_NATIVE_ARGS);
static JSValue ShipReactToAIMessage(OOJS_NATIVE_ARGS);
static JSValue ShipSendAIMessage(OOJS_NATIVE_ARGS);
static JSValue ShipDeployEscorts(OOJS_NATIVE_ARGS);
static JSValue ShipDockEscorts(OOJS_NATIVE_ARGS);
static JSValue ShipHasRole(OOJS_NATIVE_ARGS);
static JSValue ShipEjectItem(OOJS_NATIVE_ARGS);
static JSValue ShipEjectSpecificItem(OOJS_NATIVE_ARGS);
static JSValue ShipDumpCargo(OOJS_NATIVE_ARGS);
static JSValue ShipAddCargoEntity(OOJS_NATIVE_ARGS);
static JSValue ShipSpawn(OOJS_NATIVE_ARGS);
static JSValue ShipDealEnergyDamage(OOJS_NATIVE_ARGS);
static JSValue ShipExplode(OOJS_NATIVE_ARGS);
static JSValue ShipRemove(OOJS_NATIVE_ARGS);
static JSValue ShipRunLegacyScriptActions(OOJS_NATIVE_ARGS);
static JSValue ShipCommsMessage(OOJS_NATIVE_ARGS);
static JSValue ShipFireECM(OOJS_NATIVE_ARGS);
static JSValue ShipAbandonShip(OOJS_NATIVE_ARGS);
static JSValue ShipCanAwardEquipment(OOJS_NATIVE_ARGS);
static JSValue ShipAwardEquipment(OOJS_NATIVE_ARGS);
static JSValue ShipAdjustCargo(OOJS_NATIVE_ARGS);
static JSValue ShipRequestHelpFromGroup(OOJS_NATIVE_ARGS);
static JSValue ShipPatrolReportIn(OOJS_NATIVE_ARGS);

static JSValue ShipRemoveEquipment(OOJS_NATIVE_ARGS);
static JSValue ShipRestoreSubEntities(OOJS_NATIVE_ARGS);
static JSValue ShipHasEquipmentProviding(OOJS_NATIVE_ARGS);
static JSValue ShipEquipmentStatus(OOJS_NATIVE_ARGS);
static JSValue ShipSetEquipmentStatus(OOJS_NATIVE_ARGS);
static JSValue ShipSelectNewMissile(OOJS_NATIVE_ARGS);
static JSValue ShipFireMissile(OOJS_NATIVE_ARGS);
static JSValue ShipFindNearestStation(OOJS_NATIVE_ARGS);
static JSValue ShipSetBounty(OOJS_NATIVE_ARGS);
static JSValue ShipSetCargo(OOJS_NATIVE_ARGS);
static JSValue ShipSetMaterials(OOJS_NATIVE_ARGS);
static JSValue ShipSetShaders(OOJS_NATIVE_ARGS);
static JSValue ShipExitSystem(OOJS_NATIVE_ARGS);
static JSValue ShipUpdateEscortFormation(OOJS_NATIVE_ARGS);
static JSValue ShipClearDefenseTargets(OOJS_NATIVE_ARGS);
static JSValue ShipAddDefenseTarget(OOJS_NATIVE_ARGS);
static JSValue ShipRemoveDefenseTarget(OOJS_NATIVE_ARGS);
static JSValue ShipAddCollisionException(OOJS_NATIVE_ARGS);
static JSValue ShipRemoveCollisionException(OOJS_NATIVE_ARGS);
static JSValue ShipGetMaterials(OOJS_NATIVE_ARGS);
static JSValue ShipGetShaders(OOJS_NATIVE_ARGS);
static JSValue ShipBecomeCascadeExplosion(OOJS_NATIVE_ARGS);
static JSValue ShipBroadcastCascadeImminent(OOJS_NATIVE_ARGS);
static JSValue ShipBroadcastDistressMessage(OOJS_NATIVE_ARGS);
static JSValue ShipOfferToEscort(OOJS_NATIVE_ARGS);
static JSValue ShipMarkTargetForFines(OOJS_NATIVE_ARGS);
static JSValue ShipEnterWormhole(OOJS_NATIVE_ARGS);
static JSValue ShipNotifyGroupOfWormhole(OOJS_NATIVE_ARGS);
static JSValue ShipThrowSpark(OOJS_NATIVE_ARGS);

static JSValue ShipPerformAttack(OOJS_NATIVE_ARGS);
static JSValue ShipPerformCollect(OOJS_NATIVE_ARGS);
static JSValue ShipPerformEscort(OOJS_NATIVE_ARGS);
static JSValue ShipPerformFaceDestination(OOJS_NATIVE_ARGS);
static JSValue ShipPerformFlee(OOJS_NATIVE_ARGS);
static JSValue ShipPerformFlyToRangeFromDestination(OOJS_NATIVE_ARGS);
static JSValue ShipPerformHold(OOJS_NATIVE_ARGS);
static JSValue ShipPerformIdle(OOJS_NATIVE_ARGS);
static JSValue ShipPerformIntercept(OOJS_NATIVE_ARGS);
static JSValue ShipPerformLandOnPlanet(OOJS_NATIVE_ARGS);
static JSValue ShipPerformMining(OOJS_NATIVE_ARGS);
static JSValue ShipPerformScriptedAI(OOJS_NATIVE_ARGS);
static JSValue ShipPerformScriptedAttackAI(OOJS_NATIVE_ARGS);
static JSValue ShipPerformStop(OOJS_NATIVE_ARGS);
static JSValue ShipPerformTumble(OOJS_NATIVE_ARGS);

static JSValue ShipRequestDockingInstructions(OOJS_NATIVE_ARGS);
static JSValue ShipRecallDockingInstructions(OOJS_NATIVE_ARGS);
static JSValue ShipCheckCourseToDestination(OOJS_NATIVE_ARGS);
static JSValue ShipGetSafeCourseToDestination(OOJS_NATIVE_ARGS);
static JSValue ShipCheckScanner(OOJS_NATIVE_ARGS);
static JSValue ShipThreatAssessment(OOJS_NATIVE_ARGS);
static JSValue ShipDamageAssessment(OOJS_NATIVE_ARGS);
static double ShipThreatAssessmentWeapon(OOWeaponType wt);

static JSValue ShipSetCargoType(OOJS_NATIVE_ARGS);
static JSValue ShipSetCrew(OOJS_NATIVE_ARGS);

namespace {
JSValue RemoveOrExplodeShip(OOJS_NATIVE_ARGS, bool explode);
JSValue ShipSetMaterialsInternal(OOJS_NATIVE_ARGS, ShipEntity* thisEnt,
                                 bool fromShaders);
}  // namespace

static JSValue ShipStaticKeysForRole(OOJS_NATIVE_ARGS);
static JSValue ShipStaticKeys(OOJS_NATIVE_ARGS);
static JSValue ShipStaticRoles(OOJS_NATIVE_ARGS);
static JSValue ShipStaticRoleIsInCategory(OOJS_NATIVE_ARGS);
static JSValue ShipStaticShipDataForKey(OOJS_NATIVE_ARGS);
static JSValue ShipStaticSetShipDataForKey(OOJS_NATIVE_ARGS);

static JSClassDef sShipClass = {
    .class_name = "Ship",
    .finalizer =
        OOJSCxxObjectWrapperFinalize,  // the slot holds an OOJSEntityHolder
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
namespace {

enum class ShipProperty : std::int16_t {
  // Property IDs
  kAccuracy = -128,      // the ship's accuracy, float, read/write
  kAftWeapon,            // the ship's aft weapon, equipmentType, read/write
  kAI,                   // AI state machine name, string, read-only
  kAIScript,             // AI script, Script, read-only
  kAIScriptWakeTime,     // next wakeup time, integer, read/write
  kAIState,              // AI state machine state, string, read/write
  kAIFoundTarget,        // AI "found target", entity, read/write
  kAIPrimaryAggressor,   // AI "primary aggressor", entity, read/write
  kAlertCondition,       // number 0-3, read-only, combat alert level
  kAutoAI,               // bool, read-only, auto_ai from shipdata
  kAutoWeapons,          // bool, read-only, auto_weapons from shipdata
  kBeaconCode,           // beacon code, string, read/write
  kBeaconLabel,          // beacon label, string, read/write
  kBoundingBox,          // boundingBox, vector, read-only
  kBounty,               // bounty, unsigned int, read/write
  kCargoList,            // cargo on board, array of objects, read-only
  kCargoSpaceAvailable,  // free cargo space, integer, read-only
  kCargoSpaceCapacity,   // maximum cargo, integer, read/write
  kCargoSpaceUsed,       // cargo on board, integer, read-only
  kCollisionExceptions,  // collision exception list, array, read-only
  kContracts,          // cargo contracts contracts, array - strings & whatnot,
                       // read only
  kCommodity,          // commodity of a ship, read only
  kCommodityAmount,    // commodityAmount of a ship, read only
  kCloakAutomatic,     // should cloack start by itself or by script,
                       // read/write
  kCrew,               // crew, list, read only
  kCruiseSpeed,        // desired cruising speed, number, read only
  kCurrentWeapon,      // the ship's active weapon, equipmentType, read/write
  kDataKey,            // string, read-only, shipdata.plist key
  kDefenseTargets,     // array, read-only, defense targets
  kDesiredRange,       // desired Range, double, read/write
  kDesiredSpeed,       // AI desired flight speed, double, read/write
  kDestination,        // flight destination, Vector, read/write
  kDestinationSystem,  // destination system, number, read/write
  kDisplayName,        // name displayed on screen, string, read/write
  kDockingInstructions,  // name displayed on screen, string, read/write
  kEnergyRechargeRate,   // energy recharge rate, float, read-only
  kEntityPersonality,    // per-ship random number, int, read-only
  kEquipment,    // the ship's equipment, array of EquipmentInfo, read only
  kEscortGroup,  // group, ShipGroup, read-only
  kEscorts,      // deployed escorts, array of Ship, read-only
  kExhaustEmissiveColor,  // exhaust emissive color, array, read/write
  kExhausts,              // exhausts, array, read-only
  kExtraCargo,          // cargo space increase granted by large cargo bay, int,
                        // read-only
  kFlashers,            // flashers, array, read-only
  kForwardWeapon,       // the ship's forward weapon, equipmentType, read/write
  kFuel,                // fuel, float, read/write
  kFuelChargeRate,      // fuel scoop rate & charge multiplier, float,
                        // read-only
  kGroup,               // group, ShipGroup, read/write
  kHasHostileTarget,    // has hostile target, boolean, read-only
  kHasHyperspaceMotor,  // has hyperspace motor, boolean, read-only
  kHasSuspendedAI,      // AI has suspended states, boolean, read-only
  kHeading,             // forwardVector of a ship, read-only
  kHeatInsulation,      // hull heat insulation, double, read/write
  kHomeSystem,          // home system, number, read/write
  kHyperspaceSpinTime,  // hyperspace spin time, float, read/write
  kInjectorBurnRate,    // injector burn rate, number, read/write dLY/s
  kInjectorSpeedFactor,  // injector speed factor, number, read/write
  kIsBeacon,             // is beacon, boolean, read-only
  kIsBoulder,       // is a boulder (generates splinters), boolean, read/write
  kIsCargo,         // contains cargo, boolean, read-only
  kIsCloaked,       // cloaked, boolean, read/write (if cloaking device
                    // installed)
  kIsDerelict,      // is an abandoned ship, boolean, read-only
  kIsFrangible,     // frangible, boolean, read-only
  kIsFleeing,       // is fleeing, boolean, read-only
  kIsJamming,       // jamming scanners, boolean, read/write (if jammer
                    // installed)
  kIsMinable,       // is a sensible target for mining, boolean, read-only
  kIsMine,          // is mine, boolean, read-only
  kIsMissile,       // is missile, boolean, read-only
  kIsPiloted,       // is piloted, boolean, read-only (includes stations)
  kIsPirate,        // is pirate, boolean, read-only
  kIsPirateVictim,  // is pirate victim, boolean, read-only
  kIsPolice,        // is police, boolean, read-only
  kIsRock,          // is a rock (hermits included), boolean, read-only
  kIsThargoid,      // is thargoid, boolean, read-only
  kIsTurret,        // is turret, boolean, read-only
  kIsTrader,        // is trader, boolean, read-only
  kIsWeapon,        // is missile or mine, boolean, read-only
  kLaserHeatLevel,  // active laser temperature, float, read-only
  kLaserHeatLevelAft,        // aft laser temperature, float, read-only
  kLaserHeatLevelForward,    // fore laser temperature, float, read-only
  kLaserHeatLevelPort,       // port laser temperature, float, read-only
  kLaserHeatLevelStarboard,  // starboard laser temperature, float,
                             // read-only
  kLightsActive,             // flasher/shader light flag, boolean, read/write
  kMarkedForFines,           // has been marked for fines
  kMaxEscorts,               // maximum escort count, int, read/write
  kMaxPitch,                 // maximum flight pitch, double, read-only
  kMaxSpeed,                 // maximum flight speed, double, read-only
  kMaxRoll,                  // maximum flight roll, double, read-only
  kMaxYaw,                   // maximum flight yaw, double, read-only
  kMaxThrust,                // maximum thrust, double, read-only
  kMissileCapacity,          // max missiles capacity, integer, read-only
  kMissileLoadTime,          // missile load time, double, read/write
  kMissiles,                 // the ship's missiles / external storage, array of
                             // equipmentTypes, read only
  kName,                     // name, string, read-only
  kParcelCount,              // number of parcels on ship, integer, read-only
  kParcels,            // parcel contracts, array - strings & whatnot, read only
  kPassengerCapacity,  // amount of passenger space on ship, integer,
                       // read-only
  kPassengerCount,     // number of passengers on ship, integer, read-only
  kPassengers,         // passengers contracts, array - strings & whatnot, read
                       // only
  kPitch,              // pitch level, float, read-only
  kPortWeapon,         // the ship's port weapon, equipmentType, read/write
  kPotentialCollider,  // "proximity alert" ship, Entity, read-only
  kPrimaryRole,        // Primary role, string, read/write
  kReactionTime,       // AI reaction time, read/write
  kReportAIMessages,   // report AI messages, boolean, read/write
  kRoleWeights,        // roles and weights, dictionary, read-only
  kRoles,              // roles, array, read-only
  kRoll,               // roll level, float, read-only
  kSavedCoordinates,   // coordinates in system space for AI use, Vector,
                       // read/write
  kScanDescription,    // STE scan class label, string, read/write
  kScannerDisplayColor1,         // color of lollipop shown on scanner, array,
                                 // read/write
  kScannerDisplayColor2,         // color of lollipop shown on scanner when
                                 // flashing, array, read/write
  kScannerHostileDisplayColor1,  // color of lollipop shown on scanner,
                                 // array, read/write
  kScannerHostileDisplayColor2,  // color of lollipop shown on scanner when
                                 // flashing, array, read/write
  kScannerRange,                 // scanner range, double, read-only
  kScript,                       // script, Script, read-only
  kScriptedMisjump,              // next jump will miss if set to true, boolean,
                                 // read/write
  kScriptedMisjumpRange,   // 0..1 range of next misjump, float, read/write
  kScriptInfo,             // arbitrary data for scripts, dictionary, read-only
  kShipClassName,          // ship type name, string, read/write
  kShipUniqueName,         // uniqish name, string, read/write
  kSpeed,                  // current flight speed, double, read/write
  kStarboardWeapon,        // the ship's starboard weapon, equipmentType,
                           // read/write
  kSubEntities,            // subentities, array of Ship, read-only
  kSubEntityCapacity,      // max subentities for this ship, int, read-only
  kSubEntityRotation,      // subentity rotation velocity, quaternion,
                           // read/write
  kSunGlareFilter,         // sun glare filter multiplier, float, read/write
  kTarget,                 // target, Ship, read/write
  kTemperature,            // hull temperature, double, read/write
  kThrust,                 // the ship's thrust, double, read/write
  kThrustVector,           // thrust-related component of velocity, vector,
                           // read-only
  kTrackCloseContacts,     // generate close contact events, boolean,
                           // read/write
  kVectorForward,          // forwardVector of a ship, read-only
  kVectorRight,            // rightVector of a ship, read-only
  kVectorUp,               // upVector of a ship, read-only
  kVelocity,               // velocity, vector, read/write
  kWeaponFacings,          // available facings, int, read-only
  kWeaponPositionAft,      // weapon offset, vector, read-only
  kWeaponPositionForward,  // weapon offset, vector, read-only
  kWeaponPositionPort,     // weapon offset, vector, read-only
  kWeaponPositionStarboard,  // weapon offset, vector, read-only
  kWeaponRange,              // weapon range, double, read-only
  kWithinStationAegis,       // within main station aegis, boolean, read/write
  kYaw,                      // yaw level, float, read-only
};

}  // namespace

static const JSCFunctionListEntry sShipProperties[] = {
    // JS name, getter, setter, ID
    OOJS_PROPERTY_RW("accuracy", ShipGetProperty, ShipSetProperty,
                     ShipProperty::kAccuracy),
    OOJS_PROPERTY_RW("aftWeapon", ShipGetProperty, ShipSetProperty,
                     ShipProperty::kAftWeapon),
    OOJS_PROPERTY_RO("AI", ShipGetProperty, ShipProperty::kAI),
    OOJS_PROPERTY_RO("AIScript", ShipGetProperty, ShipProperty::kAIScript),
    OOJS_PROPERTY_RW("AIScriptWakeTime", ShipGetProperty, ShipSetProperty,
                     ShipProperty::kAIScriptWakeTime),
    OOJS_PROPERTY_RW("AIState", ShipGetProperty, ShipSetProperty,
                     ShipProperty::kAIState),
    OOJS_PROPERTY_RW("AIFoundTarget", ShipGetProperty, ShipSetProperty,
                     ShipProperty::kAIFoundTarget),
    OOJS_PROPERTY_RW("AIPrimaryAggressor", ShipGetProperty, ShipSetProperty,
                     ShipProperty::kAIPrimaryAggressor),
    OOJS_PROPERTY_RO("alertCondition", ShipGetProperty,
                     ShipProperty::kAlertCondition),
    OOJS_PROPERTY_RO("autoAI", ShipGetProperty, ShipProperty::kAutoAI),
    OOJS_PROPERTY_RO("autoWeapons", ShipGetProperty,
                     ShipProperty::kAutoWeapons),
    OOJS_PROPERTY_RW("beaconCode", ShipGetProperty, ShipSetProperty,
                     ShipProperty::kBeaconCode),
    OOJS_PROPERTY_RW("beaconLabel", ShipGetProperty, ShipSetProperty,
                     ShipProperty::kBeaconLabel),
    OOJS_PROPERTY_RO("boundingBox", ShipGetProperty,
                     ShipProperty::kBoundingBox),
    OOJS_PROPERTY_RW("bounty", ShipGetProperty, ShipSetProperty,
                     ShipProperty::kBounty),
    OOJS_PROPERTY_RO("cargoList", ShipGetProperty, ShipProperty::kCargoList),
    OOJS_PROPERTY_RO("cargoSpaceUsed", ShipGetProperty,
                     ShipProperty::kCargoSpaceUsed),
    OOJS_PROPERTY_RW("cargoSpaceCapacity", ShipGetProperty, ShipSetProperty,
                     ShipProperty::kCargoSpaceCapacity),
    OOJS_PROPERTY_RO("cargoSpaceAvailable", ShipGetProperty,
                     ShipProperty::kCargoSpaceAvailable),
    OOJS_PROPERTY_RO("collisionExceptions", ShipGetProperty,
                     ShipProperty::kCollisionExceptions),
    OOJS_PROPERTY_RO("commodity", ShipGetProperty, ShipProperty::kCommodity),
    OOJS_PROPERTY_RO("commodityAmount", ShipGetProperty,
                     ShipProperty::kCommodityAmount),
    // contracts instead of cargo to distinguish them from the manifest
    OOJS_PROPERTY_RO("contracts", ShipGetProperty, ShipProperty::kContracts),
    OOJS_PROPERTY_RW("cloakAutomatic", ShipGetProperty, ShipSetProperty,
                     ShipProperty::kCloakAutomatic),
    OOJS_PROPERTY_RO("crew", ShipGetProperty, ShipProperty::kCrew),
    OOJS_PROPERTY_RO("cruiseSpeed", ShipGetProperty,
                     ShipProperty::kCruiseSpeed),
    OOJS_PROPERTY_RW("currentWeapon", ShipGetProperty, ShipSetProperty,
                     ShipProperty::kCurrentWeapon),
    OOJS_PROPERTY_RO("dataKey", ShipGetProperty, ShipProperty::kDataKey),
    OOJS_PROPERTY_RO("defenseTargets", ShipGetProperty,
                     ShipProperty::kDefenseTargets),
    OOJS_PROPERTY_RW("desiredRange", ShipGetProperty, ShipSetProperty,
                     ShipProperty::kDesiredRange),
    OOJS_PROPERTY_RW("desiredSpeed", ShipGetProperty, ShipSetProperty,
                     ShipProperty::kDesiredSpeed),
    OOJS_PROPERTY_RW("destination", ShipGetProperty, ShipSetProperty,
                     ShipProperty::kDestination),
    OOJS_PROPERTY_RW("destinationSystem", ShipGetProperty, ShipSetProperty,
                     ShipProperty::kDestinationSystem),
    OOJS_PROPERTY_RW("displayName", ShipGetProperty, ShipSetProperty,
                     ShipProperty::kDisplayName),
    OOJS_PROPERTY_RO("dockingInstructions", ShipGetProperty,
                     ShipProperty::kDockingInstructions),
    OOJS_PROPERTY_RW("energyRechargeRate", ShipGetProperty, ShipSetProperty,
                     ShipProperty::kEnergyRechargeRate),
    OOJS_PROPERTY_RW("entityPersonality", ShipGetProperty, ShipSetProperty,
                     ShipProperty::kEntityPersonality),
    OOJS_PROPERTY_RO("equipment", ShipGetProperty, ShipProperty::kEquipment),
    OOJS_PROPERTY_RO("escorts", ShipGetProperty, ShipProperty::kEscorts),
    OOJS_PROPERTY_RO("escortGroup", ShipGetProperty,
                     ShipProperty::kEscortGroup),
    OOJS_PROPERTY_RW("exhaustEmissiveColor", ShipGetProperty, ShipSetProperty,
                     ShipProperty::kExhaustEmissiveColor),
    OOJS_PROPERTY_RO("exhausts", ShipGetProperty, ShipProperty::kExhausts),
    OOJS_PROPERTY_RO("extraCargo", ShipGetProperty, ShipProperty::kExtraCargo),
    OOJS_PROPERTY_RO("flashers", ShipGetProperty, ShipProperty::kFlashers),
    OOJS_PROPERTY_RW("forwardWeapon", ShipGetProperty, ShipSetProperty,
                     ShipProperty::kForwardWeapon),
    OOJS_PROPERTY_RW("fuel", ShipGetProperty, ShipSetProperty,
                     ShipProperty::kFuel),
    OOJS_PROPERTY_RO("fuelChargeRate", ShipGetProperty,
                     ShipProperty::kFuelChargeRate),
    OOJS_PROPERTY_RW("group", ShipGetProperty, ShipSetProperty,
                     ShipProperty::kGroup),
    OOJS_PROPERTY_RO("hasHostileTarget", ShipGetProperty,
                     ShipProperty::kHasHostileTarget),
    OOJS_PROPERTY_RO("hasHyperspaceMotor", ShipGetProperty,
                     ShipProperty::kHasHyperspaceMotor),
    OOJS_PROPERTY_RO("hasSuspendedAI", ShipGetProperty,
                     ShipProperty::kHasSuspendedAI),
    OOJS_PROPERTY_RW("heatInsulation", ShipGetProperty, ShipSetProperty,
                     ShipProperty::kHeatInsulation),
    OOJS_PROPERTY_RO("heading", ShipGetProperty, ShipProperty::kHeading),
    OOJS_PROPERTY_RW("homeSystem", ShipGetProperty, ShipSetProperty,
                     ShipProperty::kHomeSystem),
    OOJS_PROPERTY_RW("hyperspaceSpinTime", ShipGetProperty, ShipSetProperty,
                     ShipProperty::kHyperspaceSpinTime),
    OOJS_PROPERTY_RW("injectorBurnRate", ShipGetProperty, ShipSetProperty,
                     ShipProperty::kInjectorBurnRate),
    OOJS_PROPERTY_RW("injectorSpeedFactor", ShipGetProperty, ShipSetProperty,
                     ShipProperty::kInjectorSpeedFactor),
    OOJS_PROPERTY_RW("homeSystem", ShipGetProperty, ShipSetProperty,
                     ShipProperty::kHomeSystem),
    OOJS_PROPERTY_RO("isBeacon", ShipGetProperty, ShipProperty::kIsBeacon),
    OOJS_PROPERTY_RW("isCloaked", ShipGetProperty, ShipSetProperty,
                     ShipProperty::kIsCloaked),
    OOJS_PROPERTY_RO("isCargo", ShipGetProperty, ShipProperty::kIsCargo),
    OOJS_PROPERTY_RO("isDerelict", ShipGetProperty, ShipProperty::kIsDerelict),
    OOJS_PROPERTY_RO("isFrangible", ShipGetProperty,
                     ShipProperty::kIsFrangible),
    OOJS_PROPERTY_RO("isFleeing", ShipGetProperty, ShipProperty::kIsFleeing),
    OOJS_PROPERTY_RO("isJamming", ShipGetProperty, ShipProperty::kIsJamming),
    OOJS_PROPERTY_RO("isMinable", ShipGetProperty, ShipProperty::kIsMinable),
    OOJS_PROPERTY_RO("isMine", ShipGetProperty, ShipProperty::kIsMine),
    OOJS_PROPERTY_RO("isMissile", ShipGetProperty, ShipProperty::kIsMissile),
    OOJS_PROPERTY_RO("isPiloted", ShipGetProperty, ShipProperty::kIsPiloted),
    OOJS_PROPERTY_RO("isPirate", ShipGetProperty, ShipProperty::kIsPirate),
    OOJS_PROPERTY_RO("isPirateVictim", ShipGetProperty,
                     ShipProperty::kIsPirateVictim),
    OOJS_PROPERTY_RO("isPolice", ShipGetProperty, ShipProperty::kIsPolice),
    OOJS_PROPERTY_RO("isRock", ShipGetProperty, ShipProperty::kIsRock),
    OOJS_PROPERTY_RW("isBoulder", ShipGetProperty, ShipSetProperty,
                     ShipProperty::kIsBoulder),
    OOJS_PROPERTY_RO("isThargoid", ShipGetProperty, ShipProperty::kIsThargoid),
    OOJS_PROPERTY_RO("isTurret", ShipGetProperty, ShipProperty::kIsTurret),
    OOJS_PROPERTY_RO("isTrader", ShipGetProperty, ShipProperty::kIsTrader),
    OOJS_PROPERTY_RO("isWeapon", ShipGetProperty, ShipProperty::kIsWeapon),
    OOJS_PROPERTY_RO("laserHeatLevel", ShipGetProperty,
                     ShipProperty::kLaserHeatLevel),
    OOJS_PROPERTY_RO("laserHeatLevelAft", ShipGetProperty,
                     ShipProperty::kLaserHeatLevelAft),
    OOJS_PROPERTY_RO("laserHeatLevelForward", ShipGetProperty,
                     ShipProperty::kLaserHeatLevelForward),
    OOJS_PROPERTY_RO("laserHeatLevelPort", ShipGetProperty,
                     ShipProperty::kLaserHeatLevelPort),
    OOJS_PROPERTY_RO("laserHeatLevelStarboard", ShipGetProperty,
                     ShipProperty::kLaserHeatLevelStarboard),
    OOJS_PROPERTY_RW("lightsActive", ShipGetProperty, ShipSetProperty,
                     ShipProperty::kLightsActive),
    OOJS_PROPERTY_RO("markedForFines", ShipGetProperty,
                     ShipProperty::kMarkedForFines),
    OOJS_PROPERTY_RW("maxEscorts", ShipGetProperty, ShipSetProperty,
                     ShipProperty::kMaxEscorts),
    OOJS_PROPERTY_RW("maxPitch", ShipGetProperty, ShipSetProperty,
                     ShipProperty::kMaxPitch),
    OOJS_PROPERTY_RW("maxSpeed", ShipGetProperty, ShipSetProperty,
                     ShipProperty::kMaxSpeed),
    OOJS_PROPERTY_RW("maxRoll", ShipGetProperty, ShipSetProperty,
                     ShipProperty::kMaxRoll),
    OOJS_PROPERTY_RW("maxYaw", ShipGetProperty, ShipSetProperty,
                     ShipProperty::kMaxYaw),
    OOJS_PROPERTY_RW("maxThrust", ShipGetProperty, ShipSetProperty,
                     ShipProperty::kMaxThrust),
    OOJS_PROPERTY_RO("missileCapacity", ShipGetProperty,
                     ShipProperty::kMissileCapacity),
    OOJS_PROPERTY_RW("missileLoadTime", ShipGetProperty, ShipSetProperty,
                     ShipProperty::kMissileLoadTime),
    OOJS_PROPERTY_RO("missiles", ShipGetProperty, ShipProperty::kMissiles),
    OOJS_PROPERTY_RW("name", ShipGetProperty, ShipSetProperty,
                     ShipProperty::kName),
    OOJS_PROPERTY_RO("parcelCount", ShipGetProperty,
                     ShipProperty::kParcelCount),
    OOJS_PROPERTY_RO("parcels", ShipGetProperty, ShipProperty::kParcels),
    OOJS_PROPERTY_RO("passengerCount", ShipGetProperty,
                     ShipProperty::kPassengerCount),
    OOJS_PROPERTY_RO("passengerCapacity", ShipGetProperty,
                     ShipProperty::kPassengerCapacity),
    OOJS_PROPERTY_RO("passengers", ShipGetProperty, ShipProperty::kPassengers),
    OOJS_PROPERTY_RO("pitch", ShipGetProperty, ShipProperty::kPitch),
    OOJS_PROPERTY_RW("portWeapon", ShipGetProperty, ShipSetProperty,
                     ShipProperty::kPortWeapon),
    OOJS_PROPERTY_RO("potentialCollider", ShipGetProperty,
                     ShipProperty::kPotentialCollider),
    OOJS_PROPERTY_RW("primaryRole", ShipGetProperty, ShipSetProperty,
                     ShipProperty::kPrimaryRole),
    OOJS_PROPERTY_RW("reactionTime", ShipGetProperty, ShipSetProperty,
                     ShipProperty::kReactionTime),
    OOJS_PROPERTY_RW("reportAIMessages", ShipGetProperty, ShipSetProperty,
                     ShipProperty::kReportAIMessages),
    OOJS_PROPERTY_RO("roleWeights", ShipGetProperty,
                     ShipProperty::kRoleWeights),
    OOJS_PROPERTY_RO("roles", ShipGetProperty, ShipProperty::kRoles),
    OOJS_PROPERTY_RO("roll", ShipGetProperty, ShipProperty::kRoll),
    OOJS_PROPERTY_RW("savedCoordinates", ShipGetProperty, ShipSetProperty,
                     ShipProperty::kSavedCoordinates),
    OOJS_PROPERTY_RW("scanDescription", ShipGetProperty, ShipSetProperty,
                     ShipProperty::kScanDescription),
    OOJS_PROPERTY_RW("scannerDisplayColor1", ShipGetProperty, ShipSetProperty,
                     ShipProperty::kScannerDisplayColor1),
    OOJS_PROPERTY_RW("scannerDisplayColor2", ShipGetProperty, ShipSetProperty,
                     ShipProperty::kScannerDisplayColor2),
    OOJS_PROPERTY_RW("scannerHostileDisplayColor1", ShipGetProperty,
                     ShipSetProperty,
                     ShipProperty::kScannerHostileDisplayColor1),
    OOJS_PROPERTY_RW("scannerHostileDisplayColor2", ShipGetProperty,
                     ShipSetProperty,
                     ShipProperty::kScannerHostileDisplayColor2),
    OOJS_PROPERTY_RO("scannerRange", ShipGetProperty,
                     ShipProperty::kScannerRange),
    OOJS_PROPERTY_RO("script", ShipGetProperty, ShipProperty::kScript),
    OOJS_PROPERTY_RW("scriptedMisjump", ShipGetProperty, ShipSetProperty,
                     ShipProperty::kScriptedMisjump),
    OOJS_PROPERTY_RW("scriptedMisjumpRange", ShipGetProperty, ShipSetProperty,
                     ShipProperty::kScriptedMisjumpRange),
    OOJS_PROPERTY_RO("scriptInfo", ShipGetProperty, ShipProperty::kScriptInfo),
    OOJS_PROPERTY_RW("shipClassName", ShipGetProperty, ShipSetProperty,
                     ShipProperty::kShipClassName),
    OOJS_PROPERTY_RW("shipUniqueName", ShipGetProperty, ShipSetProperty,
                     ShipProperty::kShipUniqueName),
    OOJS_PROPERTY_RW("speed", ShipGetProperty, ShipSetProperty,
                     ShipProperty::kSpeed),
    OOJS_PROPERTY_RW("starboardWeapon", ShipGetProperty, ShipSetProperty,
                     ShipProperty::kStarboardWeapon),
    OOJS_PROPERTY_RO("subEntities", ShipGetProperty,
                     ShipProperty::kSubEntities),
    OOJS_PROPERTY_RO("subEntityCapacity", ShipGetProperty,
                     ShipProperty::kSubEntityCapacity),
    OOJS_PROPERTY_RW("subEntityRotation", ShipGetProperty, ShipSetProperty,
                     ShipProperty::kSubEntityRotation),
    OOJS_PROPERTY_RW("sunGlareFilter", ShipGetProperty, ShipSetProperty,
                     ShipProperty::kSunGlareFilter),
    OOJS_PROPERTY_RW("target", ShipGetProperty, ShipSetProperty,
                     ShipProperty::kTarget),
    OOJS_PROPERTY_RW("temperature", ShipGetProperty, ShipSetProperty,
                     ShipProperty::kTemperature),
    OOJS_PROPERTY_RW("thrust", ShipGetProperty, ShipSetProperty,
                     ShipProperty::kThrust),
    OOJS_PROPERTY_RO("thrustVector", ShipGetProperty,
                     ShipProperty::kThrustVector),
    OOJS_PROPERTY_RW("trackCloseContacts", ShipGetProperty, ShipSetProperty,
                     ShipProperty::kTrackCloseContacts),
    OOJS_PROPERTY_RO("vectorForward", ShipGetProperty,
                     ShipProperty::kVectorForward),
    OOJS_PROPERTY_RO("vectorRight", ShipGetProperty,
                     ShipProperty::kVectorRight),
    OOJS_PROPERTY_RO("vectorUp", ShipGetProperty, ShipProperty::kVectorUp),
    OOJS_PROPERTY_RW("velocity", ShipGetProperty, ShipSetProperty,
                     ShipProperty::kVelocity),
    OOJS_PROPERTY_RO("weaponFacings", ShipGetProperty,
                     ShipProperty::kWeaponFacings),
    OOJS_PROPERTY_RO("weaponPositionAft", ShipGetProperty,
                     ShipProperty::kWeaponPositionAft),
    OOJS_PROPERTY_RO("weaponPositionForward", ShipGetProperty,
                     ShipProperty::kWeaponPositionForward),
    OOJS_PROPERTY_RO("weaponPositionPort", ShipGetProperty,
                     ShipProperty::kWeaponPositionPort),
    OOJS_PROPERTY_RO("weaponPositionStarboard", ShipGetProperty,
                     ShipProperty::kWeaponPositionStarboard),
    OOJS_PROPERTY_RO("weaponRange", ShipGetProperty,
                     ShipProperty::kWeaponRange),
    OOJS_PROPERTY_RO("withinStationAegis", ShipGetProperty,
                     ShipProperty::kWithinStationAegis),
    OOJS_PROPERTY_RO("yaw", ShipGetProperty, ShipProperty::kYaw),
};

static const JSCFunctionListEntry sShipMethods[] = {
    // JS name, min args, function
    JS_CFUNC_DEF("abandonShip", 0, ShipAbandonShip),
    JS_CFUNC_DEF("addCargoEntity", 1, ShipAddCargoEntity),
    JS_CFUNC_DEF("addCollisionException", 1, ShipAddCollisionException),
    JS_CFUNC_DEF("addDefenseTarget", 1, ShipAddDefenseTarget),
    JS_CFUNC_DEF("adjustCargo", 2, ShipAdjustCargo),
    JS_CFUNC_DEF("awardEquipment", 1, ShipAwardEquipment),
    JS_CFUNC_DEF("becomeCascadeExplosion", 0, ShipBecomeCascadeExplosion),
    JS_CFUNC_DEF("broadcastCascadeImminent", 0, ShipBroadcastCascadeImminent),
    JS_CFUNC_DEF("broadcastDistressMessage", 0, ShipBroadcastDistressMessage),
    JS_CFUNC_DEF("canAwardEquipment", 1, ShipCanAwardEquipment),
    JS_CFUNC_DEF("checkCourseToDestination", 0, ShipCheckCourseToDestination),
    JS_CFUNC_DEF("checkScanner", 0, ShipCheckScanner),
    JS_CFUNC_DEF("clearDefenseTargets", 0, ShipClearDefenseTargets),
    JS_CFUNC_DEF("commsMessage", 1, ShipCommsMessage),
    JS_CFUNC_DEF("damageAssessment", 0, ShipDamageAssessment),
    JS_CFUNC_DEF("dealEnergyDamage", 2, ShipDealEnergyDamage),
    JS_CFUNC_DEF("deployEscorts", 0, ShipDeployEscorts),
    JS_CFUNC_DEF("dockEscorts", 0, ShipDockEscorts),
    JS_CFUNC_DEF("dumpCargo", 0, ShipDumpCargo),
    JS_CFUNC_DEF("ejectItem", 1, ShipEjectItem),
    JS_CFUNC_DEF("ejectSpecificItem", 1, ShipEjectSpecificItem),
    JS_CFUNC_DEF("enterWormhole", 0, ShipEnterWormhole),
    JS_CFUNC_DEF("equipmentStatus", 1, ShipEquipmentStatus),
    JS_CFUNC_DEF("exitAI", 0, ShipExitAI),
    JS_CFUNC_DEF("exitSystem", 0, ShipExitSystem),
    JS_CFUNC_DEF("explode", 0, ShipExplode),
    JS_CFUNC_DEF("fireECM", 0, ShipFireECM),
    JS_CFUNC_DEF("fireMissile", 0, ShipFireMissile),
    JS_CFUNC_DEF("findNearestStation", 0, ShipFindNearestStation),
    JS_CFUNC_DEF("getMaterials", 0, ShipGetMaterials),
    JS_CFUNC_DEF("getSafeCourseToDestination", 0,
                 ShipGetSafeCourseToDestination),
    JS_CFUNC_DEF("getShaders", 0, ShipGetShaders),
    JS_CFUNC_DEF("hasEquipmentProviding", 1, ShipHasEquipmentProviding),
    JS_CFUNC_DEF("hasRole", 1, ShipHasRole),
    JS_CFUNC_DEF("markTargetForFines", 0, ShipMarkTargetForFines),
    JS_CFUNC_DEF("notifyGroupOfWormhole", 0, ShipNotifyGroupOfWormhole),
    JS_CFUNC_DEF("offerToEscort", 1, ShipOfferToEscort),
    JS_CFUNC_DEF("patrolReportIn", 1, ShipPatrolReportIn),
    JS_CFUNC_DEF("performAttack", 0, ShipPerformAttack),
    JS_CFUNC_DEF("performCollect", 0, ShipPerformCollect),
    JS_CFUNC_DEF("performEscort", 0, ShipPerformEscort),
    JS_CFUNC_DEF("performFaceDestination", 0, ShipPerformFaceDestination),
    JS_CFUNC_DEF("performFlee", 0, ShipPerformFlee),
    JS_CFUNC_DEF("performFlyToRangeFromDestination", 0,
                 ShipPerformFlyToRangeFromDestination),
    JS_CFUNC_DEF("performHold", 0, ShipPerformHold),
    JS_CFUNC_DEF("performIdle", 0, ShipPerformIdle),
    JS_CFUNC_DEF("performIntercept", 0, ShipPerformIntercept),
    JS_CFUNC_DEF("performLandOnPlanet", 0, ShipPerformLandOnPlanet),
    JS_CFUNC_DEF("performMining", 0, ShipPerformMining),
    JS_CFUNC_DEF("performScriptedAI", 0, ShipPerformScriptedAI),
    JS_CFUNC_DEF("performScriptedAttackAI", 0, ShipPerformScriptedAttackAI),
    JS_CFUNC_DEF("performStop", 0, ShipPerformStop),
    JS_CFUNC_DEF("performTumble", 0, ShipPerformTumble),

    JS_CFUNC_DEF("reactToAIMessage", 1, ShipReactToAIMessage),
    JS_CFUNC_DEF("remove", 0, ShipRemove),
    JS_CFUNC_DEF("removeCollisionException", 1, ShipRemoveCollisionException),
    JS_CFUNC_DEF("removeDefenseTarget", 1, ShipRemoveDefenseTarget),
    JS_CFUNC_DEF("removeEquipment", 1, ShipRemoveEquipment),
    JS_CFUNC_DEF("requestHelpFromGroup", 0, ShipRequestHelpFromGroup),
    JS_CFUNC_DEF("requestDockingInstructions", 0,
                 ShipRequestDockingInstructions),
    JS_CFUNC_DEF("recallDockingInstructions", 0, ShipRecallDockingInstructions),
    JS_CFUNC_DEF("restoreSubEntities", 0, ShipRestoreSubEntities),
    JS_CFUNC_DEF("__runLegacyScriptActions", 2,
                 ShipRunLegacyScriptActions),  // Deliberately not documented
    JS_CFUNC_DEF("selectNewMissile", 0, ShipSelectNewMissile),
    JS_CFUNC_DEF("sendAIMessage", 1, ShipSendAIMessage),
    JS_CFUNC_DEF("setAI", 1, ShipSetAI),
    JS_CFUNC_DEF("setBounty", 2, ShipSetBounty),
    JS_CFUNC_DEF("setCargo", 1, ShipSetCargo),
    JS_CFUNC_DEF("setCargoType", 1, ShipSetCargoType),
    JS_CFUNC_DEF("setCrew", 1, ShipSetCrew),
    JS_CFUNC_DEF("setEquipmentStatus", 2, ShipSetEquipmentStatus),
    JS_CFUNC_DEF("setMaterials", 1, ShipSetMaterials),
    JS_CFUNC_DEF("setScript", 1, ShipSetScript),
    JS_CFUNC_DEF("setShaders", 2, ShipSetShaders),
    JS_CFUNC_DEF("spawn", 1, ShipSpawn),
    // spawnOne() is defined in the prefix script.
    JS_CFUNC_DEF("switchAI", 1, ShipSwitchAI),
    JS_CFUNC_DEF("threatAssessment", 1, ShipThreatAssessment),
    JS_CFUNC_DEF("throwSpark", 0, ShipThrowSpark),
    JS_CFUNC_DEF("updateEscortFormation", 0, ShipUpdateEscortFormation),
};

static const JSCFunctionListEntry sShipStaticMethods[] = {
    // JS name, min args, function
    JS_CFUNC_DEF("keys", 0, ShipStaticKeys),
    JS_CFUNC_DEF("keysForRole", 1, ShipStaticKeysForRole),
    JS_CFUNC_DEF("roleIsInCategory", 2, ShipStaticRoleIsInCategory),
    JS_CFUNC_DEF("roles", 0, ShipStaticRoles),
    JS_CFUNC_DEF("shipDataForKey", 1, ShipStaticShipDataForKey),
    JS_CFUNC_DEF("setShipDataForKey", 2, ShipStaticSetShipDataForKey),
};

namespace {

/*	The ship a JS Ship object holds: its C++ ship, null where there is none.
   The slot holds the C++ entity (OOJSEntityGetEntityOfClass, with the JS class
   check).
*/
bool JSShipGetShipEntity(JSContext* context, JSValueConst inObject,
                         ShipEntity** outShip) {
  OOCParameterAssert(outShip != nullptr);
  Entity* entity = nullptr;
  if (EXPECT_NOT(!OOJSEntityGetEntityOfClass(context, inObject, sShipClassID,
                                             &entity)))
    return false;
  *outShip = oo::ToShip(entity);
  return true;
}
}  // namespace

void InitOOJSShip(JSContext* context, JSValueConst global) {
  OOJSRegisterClass(&sShipClassID, &sShipClass);

  JSValue entityPrototype = JS_GetClassProto(context, JSEntityClassID());
  OOJSInitClass(context, global, sShipClassID, entityPrototype,
                OOJSUnconstructableConstruct, 0, sShipProperties,
                OOJS_COUNT(sShipProperties), sShipMethods,
                OOJS_COUNT(sShipMethods), sShipStaticMethods,
                OOJS_COUNT(sShipStaticMethods));
  JS_FreeValue(context, entityPrototype);

  OOJSRegisterObjectConverter(sShipClassID, OOJSEntityObjectConverter);
  OOJSRegisterSubclass(sShipClassID, JSEntityClassID());
}

JSClassID JSShipClassID() { return sShipClassID; }

namespace {

// A colour's components as its -normalizedArray gave them to JavaScript:
// floats, null for no colour.
oo::PList NormalizedColorComponents(OOColor* color) {
  if (color == nullptr) return oo::PList();
  oo::PList::Array components;
  for (float component : color->normalizedArray())
    components.push_back(oo::PList::singleReal(component));
  return oo::PList(std::move(components));
}

/*	The ship's AI is C++ (AI). A ship with no AI answers none or false to
   what the getter sends the AI; so does a null AI here.
*/
std::optional<std::string> AIName(ShipEntity* ship) {
  AI* ai = ship->getAI();
  return (ai != nullptr) ? ai->name() : std::nullopt;
}

std::optional<std::string> AIState(ShipEntity* ship) {
  AI* ai = ship->getAI();
  return (ai != nullptr) ? ai->state() : std::nullopt;
}

bool AIHasSuspendedStateMachines(ShipEntity* ship) {
  AI* ai = ship->getAI();
  return ai != nullptr && ai->hasSuspendedStateMachines();
}

// Whether an entity is a ShipEntity. False for none.
bool IsShip(Entity* entity) {
  return dynamic_cast<ShipEntity*>(entity) != nullptr;
}

/*	The ship's mesh is C++ (OOMesh). A ship with no mesh answers null to
   -materials and -shaders; so does a null mesh here.
*/
oo::PList MeshMaterials(ShipEntity* ship) {
  OOMesh* mesh = ship->mesh();
  return (mesh != nullptr) ? mesh->getMaterials() : oo::PList();
}

oo::PList MeshShaders(ShipEntity* ship) {
  OOMesh* mesh = ship->mesh();
  return (mesh != nullptr) ? mesh->shaders() : oo::PList();
}

// A string, or null for none (what a Foundation string or nil gave JavaScript).
oo::PList StringOrNull(const std::optional<std::string>& string) {
  return string.has_value() ? oo::PList(*string) : oo::PList();
}

// Strings as an array of strings, in order.
oo::PList StringArray(const std::vector<std::string>& strings) {
  return oo::PList(oo::PList::Array(strings.begin(), strings.end()));
}

}  // namespace

static JSValue ShipGetProperty(OOJS_GETTER_ARGS) {
  OOJS_NATIVE_ENTER(context)

  ShipEntity* entity = nullptr;
  oo::PList result;  // null maps to null

  if (EXPECT_NOT(!JSShipGetShipEntity(context, thisObj, &entity)))
    return OOJSNativeFailure(context);
  if (OOIsStaleEntity(entity)) {
    return JS_UNDEFINED;
  }
  ShipEntity* ship = entity;  // not null: entity is not

  switch (static_cast<ShipProperty>(magic)) {
    using enum ShipProperty;
    case kName:
      result = StringOrNull(ship->getName());
      break;

    case kDisplayName:
      result = StringOrNull(ship->getDisplayName());
      break;

    case kShipUniqueName:
      result = StringOrNull(ship->getShipUniqueName());
      break;

    case kShipClassName:
      result = StringOrNull(ship->getShipClassName());
      break;

    case kScanDescription:
      result = StringOrNull(ship->scanDescriptionForScripting());
      break;

    case kRoles: {
      const oo::Ref<OORoleSet> roleSet = ship->getRoleSet();
      result = roleSet != nullptr ? StringArray(roleSet->sortedRoles())
                                  : oo::PList();
    } break;

    case kRoleWeights: {
      // Floats, as numberWithFloat: made them; nil when there is no role set.
      const oo::Ref<OORoleSet> roleSet = ship->getRoleSet();
      if (const auto roleWeights = (roleSet != nullptr)
                                       ? roleSet->rolesAndProbabilities()
                                       : std::nullopt) {
        oo::PList::Dict weights;
        for (const auto& [role, weight] : *roleWeights) {
          weights[role] = oo::PList::singleReal(weight);
        }
        result = oo::PList(std::move(weights));
      }
    } break;

    case kPrimaryRole:
      result = StringOrNull(ship->getPrimaryRole());
      break;

    case kAI:
      result = StringOrNull(AIName(ship));
      break;

    case kAIState:
      result = StringOrNull(AIState(ship));
      break;

    case kAIFoundTarget:
      result = oo::EntityObjectNode(ship->foundTarget());
      break;

    case kAIPrimaryAggressor:
      result = oo::EntityObjectNode(ship->primaryAggressor());
      break;

    case kAlertCondition:
      return JS_NewNumber(context,
                          oo::ToUnderlying(ship->realAlertCondition()));

    case kAutoAI:
      return OOJSValueFromBOOL(ship->hasAutoAI());

    case kAutoWeapons:
      return OOJSValueFromBOOL(ship->hasAutoWeapons());

    case kAccuracy:
      return JS_NewNumber(context, ship->getAccuracy());

    case kFuel:
      return JS_NewNumber(context, ship->getFuel() * 0.1);

    case kFuelChargeRate:
      return JS_NewNumber(context, ship->fuelChargeRate());

    case kBounty:
      return JS_NewNumber(context, ship->getBounty());

    case kSubEntities:
      // What -subEntitiesForScript answered: ShipEntity's
      // (OOJavaScriptExtensions) method, which no subclass overrides, forwards
      // to this function.
      result = oo::EntityNodesFrom(ShipEntityJSSubEntitiesForScript(entity));
      break;

    case kExhausts:
      result = oo::EntityNodesFrom(ship->exhausts());
      break;

    case kFlashers:
      result = oo::EntityNodesFrom(ship->flasherEnumerator());
      break;

    case kSubEntityCapacity:
      return JS_NewNumber(context, ship->maxShipSubEntities());

    case kSubEntityRotation:
      OOJS_RETURN_QUATERNION(ship->subEntityRotationalVelocity());

    case kHasSuspendedAI:
      return OOJSValueFromBOOL(AIHasSuspendedStateMachines(ship));

    case kTarget:
      result = oo::EntityObjectNode(
          ship->primaryTarget());  // the C++ entity's object node or nil
      break;

    case kDefenseTargets: {
      ship->validateDefenseTargets();
      std::vector<oo::EntityHold> targets;
      targets.reserve(ship->defenseTargetCount());
      for (const auto& candidate : ship->defenseTargets()) {
        // The set's snapshot holds the ships themselves, whose underlying
        // object (OOObject's weak-reference answer) was self.
        if (!candidate)
          break;  // the old loop stopped at the first zeroed reference
        targets.push_back(candidate);
      }
      result = oo::EntityNodesFrom(targets);
      break;
    }

    case kCrew:
      if (ship->getCrew().has_value())  // unpiloted: nil, as before
      {
        const std::vector<oo::PList> entries = ship->crewForScripting();
        result = oo::PList(oo::PList::Array(entries.begin(), entries.end()));
      }
      break;

    case kEscorts: {
      OOShipGroup* escortGroup = ship->escortGroup();
      result =
          (escortGroup != nullptr)
              ? oo::EntityNodesFrom(escortGroup->memberArrayExcludingLeader())
              : oo::PList();
    } break;

    case kGroup:
      result = OOShipGroupObjectNode(ship->group());
      break;

    case kEscortGroup:
      result = OOShipGroupObjectNode(ship->escortGroup());
      break;

    case kTemperature:
      return JS_NewNumber(context, ship->temperature() / SHIP_MAX_CABIN_TEMP);

    case kHeatInsulation:
      return JS_NewNumber(context, ship->heatInsulation());

    case kHeading:
      OOJS_RETURN_VECTOR(ship->forwardVector());

    case kEnergyRechargeRate:
      return JS_NewNumber(context, ship->energyRechargeRate());

    case kEntityPersonality:
      return JS_NewInt32(context, ship->entityPersonalityInt());

    case kIsBeacon:
      return OOJSValueFromBOOL(ship->isBeacon());

    case kBeaconCode:
      result = StringOrNull(ship->beaconCode());
      break;

    case kBeaconLabel:
      result = StringOrNull(ship->beaconLabel());
      break;

    case kIsFrangible:
      return OOJSValueFromBOOL(ship->getIsFrangible());

    case kIsCloaked:
      return OOJSValueFromBOOL(ship->isCloaked());

    case kCloakAutomatic:
      return OOJSValueFromBOOL(ship->hasAutoCloak());

    case kIsJamming:
      return OOJSValueFromBOOL(ship->isJammingScanning());

    case kPotentialCollider:
      result = oo::EntityObjectNode(ship->proximityAlert());
      break;

    case kHasHostileTarget:
      return OOJSValueFromBOOL(ship->hasHostileTarget());

    case kHasHyperspaceMotor:
      return OOJSValueFromBOOL(ship->hasHyperspaceMotor());

    case kHyperspaceSpinTime:
      return JS_NewNumber(context, ship->hyperspaceSpinTime());

    case kWeaponRange:
      return JS_NewNumber(context, ship->getWeaponRange());

    case kWeaponFacings:
      if (ship->getIsPlayer()) {
        PlayerEntity* pent = static_cast<PlayerEntity*>(entity);
        return JS_NewNumber(context, (pent != nullptr ? pent->availableFacings()
                                                      : OOWeaponFacingSet{}));
      }
      return JS_NewNumber(context, ship->weaponFacings());

    case kWeaponPositionAft:
      result = NativeVectorArray(ship->getAftWeaponOffset());
      break;

    case kWeaponPositionForward:
      result = NativeVectorArray(ship->getForwardWeaponOffset());
      break;
      //			OOJS_RETURN_VECTOR([entity
      // forwardWeaponOffset]);

    case kWeaponPositionPort:
      result = NativeVectorArray(ship->getPortWeaponOffset());
      break;

    case kWeaponPositionStarboard:
      result = NativeVectorArray(ship->getStarboardWeaponOffset());
      break;

    case kScannerRange:
      return JS_NewNumber(context, ship->getScannerRange());

    case kReactionTime:
      return JS_NewNumber(context, ship->getReactionTime());

    case kReportAIMessages:
      return OOJSValueFromBOOL(ship->getReportAIMessages());

    case kWithinStationAegis:
      return OOJSValueFromBOOL(ship->withinStationAegis());

    case kCargoSpaceCapacity:
      return JS_NewInt32(context, ship->maxAvailableCargoSpace());

    case kCargoSpaceUsed:
      return JS_NewInt32(context, ship->maxAvailableCargoSpace() -
                                      ship->availableCargoSpace());

    case kCargoSpaceAvailable:
      return JS_NewInt32(context, ship->availableCargoSpace());

    case kCargoList:
      result = ship->cargoListForScripting();
      break;

    case kExtraCargo:
      return JS_NewNumber(context, ship->extraCargo());

    case kCommodity:
      if (ship->commodityAmount() > 0) {
        result = StringOrNull(ship->commodityType());
      }
      break;

    case kCommodityAmount:
      return JS_NewInt32(context, ship->commodityAmount());

    case kCollisionExceptions:
      result = oo::EntityNodesFrom(ship->collisionExceptions());
      break;

    case kSpeed:
      return JS_NewNumber(context, ship->getFlightSpeed());

    case kCruiseSpeed:
      return JS_NewNumber(context, ship->getCruiseSpeed());

    case kDataKey:
      result = StringOrNull(ship->shipDataKey());
      break;

    case kDesiredRange:
      return JS_NewNumber(context, ship->desiredRange());

    case kDesiredSpeed:
      return JS_NewNumber(context, ship->desiredSpeed());

    case kDestination:
      OOJS_RETURN_HPVECTOR(ship->destination());

    case kMarkedForFines:
      return OOJSValueFromBOOL(ship->markedForFines());

    case kMaxEscorts:
      return JS_NewNumber(context, ship->maxEscortCount());

    case kMaxPitch:
      return JS_NewNumber(context, ship->maxFlightPitch());

    case kMaxSpeed:
      return JS_NewNumber(context, ship->getMaxFlightSpeed());

    case kMaxRoll:
      return JS_NewNumber(context, ship->maxFlightRoll());

    case kMaxYaw:
      return JS_NewNumber(context, ship->maxFlightYaw());

    case kInjectorBurnRate:
      return JS_NewNumber(context, ship->afterburnerRate());

    case kInjectorSpeedFactor:
      return JS_NewNumber(context, ship->afterburnerFactor());

    case kScript:
      result = OOScriptObjectNode(ship->shipScript());
      break;

    case kAIScript:
      result = OOScriptObjectNode(ship->shipAIScript());
      break;

    case kAIScriptWakeTime:
      return JS_NewNumber(context, ship->shipAIScriptWakeTime());
      break;

    case kDestinationSystem:
      return JS_NewNumber(context, ship->destinationSystem());
      break;

    case kHomeSystem:
      return JS_NewNumber(context, ship->homeSystem());
      break;

    case kIsPirate:
      return OOJSValueFromBOOL(ship->isPirate());

    case kIsPolice:
      return OOJSValueFromBOOL(ship->isPolice());

    case kIsThargoid:
      return OOJSValueFromBOOL(ship->isThargoid());

    case kIsTurret:
      return OOJSValueFromBOOL(ship->isTurret());

    case kIsTrader:
      return OOJSValueFromBOOL(ship->isTrader());

    case kIsPirateVictim:
      return OOJSValueFromBOOL(ship->isPirateVictim());

    case kIsMissile:
      return OOJSValueFromBOOL(ship->getIsMissile());

    case kIsMine:
      return OOJSValueFromBOOL(ship->isMine());

    case kIsWeapon:
      return OOJSValueFromBOOL(ship->isWeapon());

    case kIsRock:
      return OOJSValueFromBOOL(ship->getScanClass() ==
                               OOScanClass::kRock);  // hermits and asteroids!

    case kIsMinable:
      return OOJSValueFromBOOL(ship->isMinable());

    case kIsBoulder:
      return OOJSValueFromBOOL(ship->isBoulder());

    case kIsFleeing:
      if (ship->getIsPlayer()) {
        return OOJSValueFromBOOL(
            (static_cast<PlayerEntity*>(entity) != nullptr
                 ? static_cast<PlayerEntity*>(entity)->fleeingStatus()
                 : OOPlayerFleeingStatus{}) >= OOPlayerFleeingStatus::kCargo);
      } else {
        return OOJSValueFromBOOL(
            ship->getBehaviour() == OOBehaviour::kFleeTarget ||
            ship->getBehaviour() == OOBehaviour::kFleeEvasiveAction);
      }

    case kIsCargo:
      return OOJSValueFromBOOL(ship->getScanClass() == OOScanClass::kCargo &&
                               ship->commodityAmount() > 0);

    case kIsDerelict:
      return OOJSValueFromBOOL(ship->getIsHulk());

    case kIsPiloted:
      return OOJSValueFromBOOL(
          ship->getIsPlayer() ||
          ship->getCrew().value_or(std::vector<oo::Ref<OOCharacter>>()).size() >
              0);

    case kScriptedMisjump:
      return OOJSValueFromBOOL(ship->scriptedMisjump());

    case kScriptedMisjumpRange:
      return JS_NewNumber(context, ship->scriptedMisjumpRange());

    case kScriptInfo:
      result = ship->getScriptInfo();  // empty dict, never null
      break;

    case kSunGlareFilter:
      return JS_NewNumber(context, ship->getSunGlareFilter());

    case kTrackCloseContacts:
      return OOJSValueFromBOOL(ship->getTrackCloseContacts());

    case kPassengerCount:
      return JS_NewNumber(context, ship->passengerCount());

    case kParcelCount:
      return JS_NewNumber(context, ship->parcelCount());

    case kPassengerCapacity:
      return JS_NewNumber(context, ship->passengerCapacity());

    case kMissileCapacity:
      return JS_NewNumber(context, ship->missileCapacity());

    case kMissileLoadTime:
      return JS_NewNumber(context, ship->missileLoadTime());

    case kSavedCoordinates:
      OOJS_RETURN_HPVECTOR(ship->getCoordinates());

    case kEquipment:
      result = OOEquipmentTypeObjectNodes(ship->equipmentListForScripting());
      break;

    case kCurrentWeapon:
      result = OOEquipmentTypeObjectNode(
          ship->weaponTypeForFacing(ship->getCurrentWeaponFacing(), true));
      break;

    case kForwardWeapon:
      result = OOEquipmentTypeObjectNode(
          ship->weaponTypeForFacing(OOWeaponFacing::kForward, true));
      break;

    case kAftWeapon:
      result = OOEquipmentTypeObjectNode(
          ship->weaponTypeForFacing(OOWeaponFacing::kAft, true));
      break;

    case kPortWeapon:
      result = OOEquipmentTypeObjectNode(
          ship->weaponTypeForFacing(OOWeaponFacing::kPort, true));
      break;

    case kStarboardWeapon:
      result = OOEquipmentTypeObjectNode(
          ship->weaponTypeForFacing(OOWeaponFacing::kStarboard, true));
      break;

    case kLaserHeatLevel:
      return JS_NewNumber(context, ship->laserHeatLevel());

    case kLaserHeatLevelAft:
      return JS_NewNumber(context, ship->laserHeatLevelAft());

    case kLaserHeatLevelForward:
      return JS_NewNumber(context, ship->laserHeatLevelForward());

    case kLaserHeatLevelPort:
      return JS_NewNumber(context, ship->laserHeatLevelPort());

    case kLaserHeatLevelStarboard:
      return JS_NewNumber(context, ship->laserHeatLevelStarboard());

    case kMissiles:
      result = OOEquipmentTypeObjectNodes(ship->missilesList());
      break;

    case kPassengers:
      result = ship->passengerListForScripting();
      break;

    case kParcels:
      result = ship->parcelListForScripting();
      break;

    case kContracts:
      result = ship->contractListForScripting();
      break;

    case kDockingInstructions:
      result = ship->getDockingInstructions();
      break;

    case kScannerDisplayColor1:
      result = NormalizedColorComponents(ship->scannerDisplayColor1());
      break;

    case kScannerDisplayColor2:
      result = NormalizedColorComponents(ship->scannerDisplayColor2());
      break;

    case kScannerHostileDisplayColor1:
      result = NormalizedColorComponents(ship->scannerDisplayColorHostile1());
      break;

    case kScannerHostileDisplayColor2:
      result = NormalizedColorComponents(ship->scannerDisplayColorHostile2());
      break;

    case kExhaustEmissiveColor:
      result = NormalizedColorComponents(ship->exhaustEmissiveColor());
      break;

    case kMaxThrust:
      return JS_NewNumber(context, ship->maxThrust());

    case kThrust:
      return JS_NewNumber(context, ship->getThrust());

    case kLightsActive:
      return OOJSValueFromBOOL(ship->lightsActive());

    case kVectorRight:
      OOJS_RETURN_VECTOR(ship->rightVector());

    case kVectorForward:
      OOJS_RETURN_VECTOR(ship->forwardVector());

    case kVectorUp:
      OOJS_RETURN_VECTOR(ship->upVector());

    case kVelocity:
      OOJS_RETURN_VECTOR(ship->getVelocity());

    case kThrustVector:
      OOJS_RETURN_VECTOR(ship->thrustVector());

    case kPitch:
      return JS_NewNumber(context, ship->getFlightPitch());

    case kRoll:
      return JS_NewNumber(context, ship->getFlightRoll());

    case kYaw:
      return JS_NewNumber(context, ship->getFlightYaw());

    case kBoundingBox: {
      Vector bbvect;
      BoundingBox box;

      if (ship->getIsSubEntity()) {
        box = ship->getBoundingBox();
      } else {
        box = ship->getTotalBoundingBox();
      }
      bounding_box_get_dimensions(box, &bbvect.x, &bbvect.y, &bbvect.z);
      OOJS_RETURN_VECTOR(bbvect);
    }

    default:
      OOJSReportBadPropertySelector(context, thisObj, magic, sShipProperties,
                                    OOJS_COUNT(sShipProperties));
      return OOJSNativeFailure(context);
  }

  return OOJSValueFromPList(context, result);

  OOJS_NATIVE_EXIT
}

static JSValue ShipSetProperty(OOJS_SETTER_ARGS) {
  OOJS_NATIVE_ENTER(context)

  ShipEntity* entity = nullptr;
  Entity* target = nullptr;  // as JSValueToEntity() answers (the C++ entity)
  std::optional<std::string> sValue;
  double fValue;
  int32_t iValue;
  int bValue;
  Vector vValue;
  Quaternion qValue;
  HPVector hpvValue;
  OOShipGroup* group = nullptr;
  oo::Ref<OOColor> colorForScript;
  bool exists;  // JSValueToEquipmentKeyRelaxed()'s out parameter

  if (EXPECT_NOT(!JSShipGetShipEntity(context, thisObj, &entity)))
    return OOJSNativeFailure(context);
  if (OOIsStaleEntity(entity)) return JS_UNDEFINED;
  ShipEntity* ship = entity;  // not null: entity is not

  OOCAssert(
      !ship->isTemplateCargoPod(),
      "-OOJSShip: a template cargo pod has become accessible to Javascript");

  switch (static_cast<ShipProperty>(magic)) {
    using enum ShipProperty;
    case kName:
      if (EXPECT_NOT(ship->getIsPlayer())) goto playerReadOnly;

      sValue = cxx_OOStringFromJSValue(context, value);
      if (sValue.has_value()) {
        ship->setName(sValue);
        return JS_UNDEFINED;
      }
      break;

    case kDisplayName:
      if (EXPECT_NOT(ship->getIsPlayer())) goto playerReadOnly;

      sValue = cxx_OOStringFromJSValue(context, value);
      if (sValue.has_value()) {
        ship->setDisplayName(sValue);
        return JS_UNDEFINED;
      }
      break;

    case kShipUniqueName:
      sValue = cxx_OOStringFromJSValue(context, value);
      if (sValue.has_value()) {
        ship->setShipUniqueName(sValue);
        return JS_UNDEFINED;
      }
      break;

    case kShipClassName:
      sValue = cxx_OOStringFromJSValue(context, value);
      if (sValue.has_value()) {
        ship->setShipClassName(sValue);
        return JS_UNDEFINED;
      }
      break;

    case kScanDescription:
      sValue = cxx_OOStringFromJSValue(context, value);
      // can set to nil
      ship->setScanDescription(sValue);
      return JS_UNDEFINED;

    case kPrimaryRole:
      if (EXPECT_NOT(ship->getIsPlayer())) goto playerReadOnly;

      sValue = cxx_OOStringFromJSValue(context, value);
      if (sValue.has_value()) {
        ship->setPrimaryRole(*sValue);
        return JS_UNDEFINED;
      }
      break;

    case kAIState:
      if (EXPECT_NOT(ship->getIsPlayer())) goto playerReadOnly;

      sValue = cxx_OOStringFromJSValue(context, value);
      if (sValue.has_value()) {
        if (AI* ai = ship->getAI())
          ai->setState(*sValue);  // no AI: nothing, as a message to nil
        return JS_UNDEFINED;
      }
      break;

    case kBeaconCode:
      if (EXPECT_NOT(ship->getIsPlayer())) goto playerReadOnly;

      sValue = cxx_OOStringFromJSValue(context, value);
      if (!sValue.has_value() ||
          sValue->empty())  // nil and "" alike, as -length gave 0 for both
      {
        if (ship->isBeacon()) {
          if (UNIVERSE != nullptr)
            UNIVERSE->clearBeacon(entity);  // the C++ entity
          if ((PLAYER != nullptr ? PLAYER->nextBeaconEntity() : nullptr) ==
              entity) {
            if (PLAYER != nullptr)
              PLAYER->setCompassMode(OOCompassMode::kPlanet);
          }
        }
      } else {
        if (ship->isBeacon()) {
          ship->setBeaconCode(sValue);
        } else  // Universe needs to update beacon lists in this case only
        {
          ship->setBeaconCode(sValue);
          if (UNIVERSE != nullptr)
            UNIVERSE->setNextBeacon(entity);  // the C++ entity
        }
      }
      return JS_UNDEFINED;
      break;

    case kBeaconLabel:
      if (EXPECT_NOT(ship->getIsPlayer())) goto playerReadOnly;
      sValue = cxx_OOStringFromJSValue(context, value);
      if (sValue.has_value()) {
        ship->setBeaconLabel(sValue);
        return JS_UNDEFINED;
      }
      break;

    case kAccuracy:
      if (EXPECT_NOT(ship->getIsPlayer())) goto playerReadOnly;

      if ((JS_ToFloat64(context, &fValue, value) == 0)) {
        ship->setAccuracy(fValue);
        return JS_UNDEFINED;
      }
      break;

    case kFuel:
      if ((JS_ToFloat64(context, &fValue, value) == 0)) {
        fValue = OOClamp_0_max_d(fValue, MAX_JUMP_RANGE);
        ship->setFuel(lround(fValue * 10.0));
        return JS_UNDEFINED;
      }
      break;

    case kEntityPersonality:
      if (OOJSValueToInt32(context, value, &iValue)) {
        if (iValue < 0 ||
            iValue > static_cast<int32_t>(ENTITY_PERSONALITY_MAX)) {
          cxx_OOJSReportError(
              context, "ship.%s must be >= 0 and <= %u.",
              cxx_OOStringFromJSPropertyMagic(magic, sShipProperties,
                                              OOJS_COUNT(sShipProperties))
                  .c_str(),
              ENTITY_PERSONALITY_MAX);
          return OOJSNativeFailure(context);
        }
        ship->setEntityPersonalityInt(iValue);
        return JS_UNDEFINED;
      }

    case kHyperspaceSpinTime:
      if ((JS_ToFloat64(context, &fValue, value) == 0)) {
        ship->setHyperspaceSpinTime(fValue);
        return JS_UNDEFINED;
      }
      break;

    case kBounty:
      if (OOJSValueToInt32(context, value, &iValue)) {
        if (iValue < 0) iValue = 0;
        ship->setBounty(iValue, OOLegalStatusReason::kByScript);
        return JS_UNDEFINED;
      }
      break;

    case kCargoSpaceCapacity:
      if (OOJSValueToInt32(context, value, &iValue)) {
        if (iValue < 0) iValue = 0;
        // OXPs using equipment with weight requirements may make us end up with
        // more allocated cargo space than what we have available. Do not let
        // iValue become negative.
        if (ship->maxAvailableCargoSpace() < ship->availableCargoSpace()) {
          iValue = 0;
        } else if (static_cast<OOCargoQuantity>(iValue) <
                   ship->maxAvailableCargoSpace() -
                       ship->availableCargoSpace()) {
          iValue = ship->maxAvailableCargoSpace() - ship->availableCargoSpace();
        }
        ship->setMaxAvailableCargoSpace(iValue);
        return JS_UNDEFINED;
      }
      break;

    case kDestinationSystem:
      if (OOJSValueToInt32(context, value, &iValue)) {
        if (iValue < 0) iValue = 0;
        ship->setDestinationSystem(iValue);
        return JS_UNDEFINED;
      }
      break;

    case kHomeSystem:
      if (OOJSValueToInt32(context, value, &iValue)) {
        if (iValue < 0) iValue = 0;
        ship->setHomeSystem(iValue);
        return JS_UNDEFINED;
      }
      break;

    case kTarget:
      if (JS_IsNull(value)) {
        ShipEntityJSSetTargetForScript(
            entity,
            nullptr);  // -setTargetForScript:, which no subclass overrides
        return JS_UNDEFINED;
      } else if (JSValueToEntity(context, value, &target) && IsShip(target)) {
        ShipEntityJSSetTargetForScript(entity, oo::ToShip(target));
        return JS_UNDEFINED;
      }
      break;

    case kAIFoundTarget:
      if (EXPECT_NOT(ship->getIsPlayer())) goto playerReadOnly;

      if (JS_IsNull(value)) {
        ship->setFoundTarget(nullptr);
        return JS_UNDEFINED;
      } else if (JSValueToEntity(context, value, &target) && IsShip(target)) {
        ship->setFoundTarget(target);  // the C++ entity (the member takes it)
        return JS_UNDEFINED;
      }
      break;

    case kAIPrimaryAggressor:
      if (EXPECT_NOT(ship->getIsPlayer())) goto playerReadOnly;

      if (JS_IsNull(value)) {
        ship->setPrimaryAggressor(nullptr);
        return JS_UNDEFINED;
      } else if (JSValueToEntity(context, value, &target) && IsShip(target)) {
        ship->setPrimaryAggressor(
            target);  // the C++ entity (the member takes it)
        return JS_UNDEFINED;
      }
      break;

    case kGroup:
      group = OOShipGroupInObjectNode(cxx_OOJSPListFromJSValue(
          context, value));  // a ShipGroup's group, else null
      if (group != nullptr || JS_IsNull(value)) {
        ship->setGroup(group);
        return JS_UNDEFINED;
      }
      break;

    case kAIScriptWakeTime:
      if ((JS_ToFloat64(context, &fValue, value) == 0)) {
        ship->setAIScriptWakeTime(fValue);
        return JS_UNDEFINED;
      }
      break;

    case kTemperature:
      if ((JS_ToFloat64(context, &fValue, value) == 0)) {
        fValue = fmax(fValue, 0.0);
        ship->setTemperature(fValue * SHIP_MAX_CABIN_TEMP);
        return JS_UNDEFINED;
      }
      break;

    case kHeatInsulation:
      if ((JS_ToFloat64(context, &fValue, value) == 0)) {
        fValue = fmax(fValue, 0.125);
        ship->setHeatInsulation(fValue);
        return JS_UNDEFINED;
      }
      break;

    case kIsCloaked:
      if (((bValue = JS_ToBool(context, value)) >= 0)) {
        ship->setCloaked(bValue);
        return JS_UNDEFINED;
      }
      break;

    case kCloakAutomatic:
      if (((bValue = JS_ToBool(context, value)) >= 0)) {
        ship->setAutoCloak(bValue);
        return JS_UNDEFINED;
      }
      break;

    case kMissileLoadTime:
      if ((JS_ToFloat64(context, &fValue, value) == 0)) {
        ship->setMissileLoadTime(fmax(0.0, fValue));
        return JS_UNDEFINED;
      }
      break;

    case kReactionTime:
      if (EXPECT_NOT(ship->getIsPlayer())) goto playerReadOnly;

      if ((JS_ToFloat64(context, &fValue, value) == 0)) {
        ship->setReactionTime(fValue);
        return JS_UNDEFINED;
      }
      break;

    case kReportAIMessages:
      if (((bValue = JS_ToBool(context, value)) >= 0)) {
        ship->setReportAIMessages(bValue);
        return JS_UNDEFINED;
      }
      break;

    case kTrackCloseContacts:
      if (((bValue = JS_ToBool(context, value)) >= 0)) {
        ship->setTrackCloseContacts(bValue);
        return JS_UNDEFINED;
      }
      break;

    case kIsBoulder:
      if (EXPECT_NOT(ship->getIsPlayer())) goto playerReadOnly;

      if (((bValue = JS_ToBool(context, value)) >= 0)) {
        ship->setIsBoulder(bValue);
        return JS_UNDEFINED;
      }
      break;

    case kDestination:
      if (EXPECT_NOT(ship->getIsPlayer())) goto playerReadOnly;

      if (JSValueToHPVector(context, value, &hpvValue)) {
        // use setEscortDestination rather than setDestination as
        // scripted amendments shouldn't necessarily reset frustration
        ship->setEscortDestination(hpvValue);
        return JS_UNDEFINED;
      }
      break;

    case kDesiredSpeed:
      if (EXPECT_NOT(ship->getIsPlayer())) goto playerReadOnly;

      if ((JS_ToFloat64(context, &fValue, value) == 0)) {
        ship->setDesiredSpeed(fmax(fValue, 0.0));
        return JS_UNDEFINED;
      }
      break;

    case kSpeed:
      // Writable so a script can put a ship at a KNOWN flight speed, and in
      // particular can hold it at rest.
      //
      // PLAYER: read-only, as for desiredSpeed just above. The player's
      // flightSpeed is driven by the throttle every frame through
      // PlayerEntity's control path, so a write here would be silently
      // reverted.
      if (EXPECT_NOT(ship->getIsPlayer())) goto playerReadOnly;

      if ((JS_ToFloat64(context, &fValue, value) == 0)) {
        // NEGATIVE IS REFUSED, NOT CLAMPED, matching maxSpeed/maxPitch/maxRoll
        // below. flightSpeed is a magnitude - thrustVector is v_forward scaled
        // by it - so a negative value means the caller wanted to reverse and
        // got a ship flying backwards along its own nose instead. Silently
        // clamping that to 0 would hide the mistake; refusing names it. NaN is
        // refused for the same reason and by the same idiom as
        // OOJSPlayerShip.m:811 ("guard against undefined"): NaN propagates into
        // position on the next frame and poisons the entity beyond recovery.
        if (isnan(fValue) || fValue < 0) {
          cxx_OOJSReportError(context, "ship.speed must be a number >= 0.");
          return OOJSNativeFailure(context);
        }
        // NOT clamped to maxSpeed at the top end, deliberately. The engine
        // itself puts flightSpeed above maxFlightSpeed on purpose - missiles
        // (ShipEntity.m:12381, `maxFlightSpeed + 300`) and fuel injectors both
        // do - so an upper clamp here would make the scripted seam weaker than
        // the engine's own and would silently rewrite a legal value.
        // -applyThrust: already pulls flightSpeed back towards desired_speed,
        // which IS clamped to max_available_speed (ShipEntity.m:6756-6757), so
        // an over-speed write decays on its own rather than sticking.
        ship->setSpeed(fValue);
        return JS_UNDEFINED;
      }
      break;

    case kDesiredRange:
      if (EXPECT_NOT(ship->getIsPlayer())) goto playerReadOnly;

      if ((JS_ToFloat64(context, &fValue, value) == 0)) {
        ship->setDesiredRange(fmax(fValue, 0.0));
        return JS_UNDEFINED;
      }
      break;

    case kSavedCoordinates:
      if (JSValueToHPVector(context, value, &hpvValue)) {
        ship->setCoordinate(hpvValue);
        return JS_UNDEFINED;
      }
      break;

    case kScannerDisplayColor1:
      colorForScript = OOColor::colorWithDescription(
          cxx_OOJSPListFromJSValue(context, value));
      if (colorForScript != nullptr || JS_IsNull(value)) {
        ship->setScannerDisplayColor1(colorForScript.get());
        return JS_UNDEFINED;
      }
      break;

    case kScannerDisplayColor2:
      colorForScript = OOColor::colorWithDescription(
          cxx_OOJSPListFromJSValue(context, value));
      if (colorForScript != nullptr || JS_IsNull(value)) {
        ship->setScannerDisplayColor2(colorForScript.get());
        return JS_UNDEFINED;
      }
      break;

    case kScannerHostileDisplayColor1:
      colorForScript = OOColor::colorWithDescription(
          cxx_OOJSPListFromJSValue(context, value));
      if (colorForScript != nullptr || JS_IsNull(value)) {
        ship->setScannerDisplayColorHostile1(colorForScript.get());
        return JS_UNDEFINED;
      }
      break;

    case kScannerHostileDisplayColor2:
      colorForScript = OOColor::colorWithDescription(
          cxx_OOJSPListFromJSValue(context, value));
      if (colorForScript != nullptr || JS_IsNull(value)) {
        ship->setScannerDisplayColorHostile2(colorForScript.get());
        return JS_UNDEFINED;
      }
      break;

    case kExhaustEmissiveColor:
      colorForScript = OOColor::colorWithDescription(
          cxx_OOJSPListFromJSValue(context, value));
      if (colorForScript != nullptr || JS_IsNull(value)) {
        ship->setExhaustEmissiveColor(colorForScript.get());
        return JS_UNDEFINED;
      }
      break;

    case kScriptedMisjump:
      if (((bValue = JS_ToBool(context, value)) >= 0)) {
        ship->setScriptedMisjump(bValue);
        return JS_UNDEFINED;
      }
      break;

    case kScriptedMisjumpRange:
      if ((JS_ToFloat64(context, &fValue, value) == 0)) {
        if (fValue > 0.0 && fValue < 1.0) {
          ship->setScriptedMisjumpRange(fValue);
          return JS_UNDEFINED;
        } else {
          cxx_OOJSReportError(
              context, "ship.%s must be > 0.0 and < 1.0.",
              cxx_OOStringFromJSPropertyMagic(magic, sShipProperties,
                                              OOJS_COUNT(sShipProperties))
                  .c_str());
          return OOJSNativeFailure(context);
        }
      }
      break;

    case kSubEntityRotation:
      if (JSValueToQuaternion(context, value, &qValue)) {
        ship->setSubEntityRotationalVelocity(qValue);
        return JS_UNDEFINED;
      }
      break;

    case kSunGlareFilter:
      if ((JS_ToFloat64(context, &fValue, value) == 0)) {
        if (fValue >= 0.0f && fValue <= 1.0f) {
          ship->setSunGlareFilter(fValue);
          return JS_UNDEFINED;
        } else {
          cxx_OOJSReportError(
              context, "ship.%s must be > 0.0 and < 1.0.",
              cxx_OOStringFromJSPropertyMagic(magic, sShipProperties,
                                              OOJS_COUNT(sShipProperties))
                  .c_str());
          return OOJSNativeFailure(context);
        }
      }
      break;

    case kThrust:
      //			if (EXPECT_NOT(ship->getIsPlayer()))  goto
      // playerReadOnly;

      if ((JS_ToFloat64(context, &fValue, value) == 0)) {
        ship->setThrust(OOClamp_0_max_f(fValue, ship->maxThrust()));
        return JS_UNDEFINED;
      }
      break;

    case kMaxPitch:
      if ((JS_ToFloat64(context, &fValue, value) == 0)) {
        if (fValue < 0) {
          cxx_OOJSReportError(context, "ship.maxPitch cannot be negative.");
          return OOJSNativeFailure(context);
        }
        ship->setMaxFlightPitch(fValue);
        return JS_UNDEFINED;
      }
      break;

    case kMaxSpeed:
      if ((JS_ToFloat64(context, &fValue, value) == 0)) {
        if (fValue < 0) {
          cxx_OOJSReportError(context, "ship.maxSpeed cannot be negative.");
          return OOJSNativeFailure(context);
        }
        ship->setMaxFlightSpeed(fValue);
        return JS_UNDEFINED;
      }
      break;

    case kMaxRoll:
      if ((JS_ToFloat64(context, &fValue, value) == 0)) {
        if (fValue < 0) {
          cxx_OOJSReportError(context, "ship.maxRoll cannot be negative.");
          return OOJSNativeFailure(context);
        }
        ship->setMaxFlightRoll(fValue);
        return JS_UNDEFINED;
      }
      break;

    case kMaxYaw:
      if ((JS_ToFloat64(context, &fValue, value) == 0)) {
        if (fValue < 0) {
          cxx_OOJSReportError(context, "ship.maxYaw cannot be negative.");
          return OOJSNativeFailure(context);
        }
        ship->setMaxFlightYaw(fValue);
        return JS_UNDEFINED;
      }
      break;

    case kInjectorBurnRate:
      if ((JS_ToFloat64(context, &fValue, value) == 0)) {
        if (fValue < 0) {
          cxx_OOJSReportError(context,
                              "ship.injectorBurnRate cannot be negative.");
          return OOJSNativeFailure(context);
        }
        ship->setAfterburnerRate(fValue);
        return JS_UNDEFINED;
      }
      break;

    case kInjectorSpeedFactor:
      if ((JS_ToFloat64(context, &fValue, value) == 0)) {
        if (fValue < 1) {
          cxx_OOJSReportError(
              context, "ship.injectorSpeedFactor cannot be less than 1.0.");
          return OOJSNativeFailure(context);
        }
#if OO_VARIABLE_TORUS_SPEED
        else if (fValue > MIN_HYPERSPEED_FACTOR) {
          cxx_OOJSReportError(context,
                              "ship.injectorSpeedFactor cannot be higher than "
                              "minimum torus speed factor (%f).",
                              MIN_HYPERSPEED_FACTOR);
          return OOJSNativeFailure(context);
        }
#else
        else if (fValue > HYPERSPEED_FACTOR) {
          cxx_OOJSReportError(context,
                              "ship.injectorSpeedFactor cannot be higher than "
                              "torus speed factor (%f).",
                              HYPERSPEED_FACTOR);
          return OOJSNativeFailure(context);
        }
#endif
        ship->setAfterburnerFactor(fValue);
        return JS_UNDEFINED;
      }
      break;

    case kMaxThrust:
      if ((JS_ToFloat64(context, &fValue, value) == 0)) {
        if (fValue < 0) {
          cxx_OOJSReportError(context, "ship.maxThrust cannot be negative.");
          return OOJSNativeFailure(context);
        }
        ship->setMaxThrust(fValue);
        return JS_UNDEFINED;
      }
      break;

    case kEnergyRechargeRate:
      if ((JS_ToFloat64(context, &fValue, value) == 0)) {
        if (fValue < 0) {
          cxx_OOJSReportError(context,
                              "ship.energyRechargeRate cannot be negative.");
          return OOJSNativeFailure(context);
        }
        ship->setEnergyRechargeRate(fValue);
        return JS_UNDEFINED;
      }
      break;

    case kLightsActive:
      if (((bValue = JS_ToBool(context, value)) >= 0)) {
        if (bValue)
          ship->switchLightsOn();
        else
          ship->switchLightsOff();
        return JS_UNDEFINED;
      }
      break;

    case kVelocity:
      if (JSValueToVector(context, value, &vValue)) {
        ship->setTotalVelocity(vValue);
        return JS_UNDEFINED;
      }
      break;

    case kPortWeapon:
    case kStarboardWeapon:
    case kAftWeapon:
    case kForwardWeapon:
    case kCurrentWeapon: {
      const std::string weaponKey =
          JSValueToEquipmentKeyRelaxed(context, value, &exists)
              .value_or("EQ_WEAPON_NONE");
      OOWeaponFacing facing = OOWeaponFacing::kForward;
      switch (static_cast<ShipProperty>(magic)) {
        case kAftWeapon:
          facing = OOWeaponFacing::kAft;
          break;
        case kForwardWeapon:
          facing = OOWeaponFacing::kForward;
          break;
        case kPortWeapon:
          facing = OOWeaponFacing::kPort;
          break;
        case kStarboardWeapon:
          facing = OOWeaponFacing::kStarboard;
          break;
        case kCurrentWeapon:
          facing = ship->getCurrentWeaponFacing();
          break;
        default:  // only the weapon properties reach here
          break;
      }
      if (ship->getIsPlayer()) {
        PlayerEntity* pent = static_cast<PlayerEntity*>(entity);
        if (pent != nullptr)
          pent->setWeaponMount(facing, weaponKey, "scripted");
      } else {
        ship->setWeaponMount(facing, weaponKey);
      }
      return JS_UNDEFINED;
    }

    case kMaxEscorts:
      if (EXPECT_NOT(ship->getIsPlayer())) goto playerReadOnly;

      if (OOJSValueToInt32(context, value, &iValue)) {
        OOShipGroup* escortGroup = ship->escortGroup();
        if (static_cast<std::ptrdiff_t>(iValue) <
            static_cast<std::ptrdiff_t>(
                escortGroup != nullptr ? escortGroup->count() : 0) -
                1) {
          cxx_OOJSReportError(
              context, "ship.%s must be >= current escort numbers.",
              cxx_OOStringFromJSPropertyMagic(magic, sShipProperties,
                                              OOJS_COUNT(sShipProperties))
                  .c_str());
          return OOJSNativeFailure(context);
        }
        if (iValue > MAX_ESCORTS) {
          cxx_OOJSReportError(
              context, "ship.%s must be <= %d.",
              cxx_OOStringFromJSPropertyMagic(magic, sShipProperties,
                                              OOJS_COUNT(sShipProperties))
                  .c_str(),
              MAX_ESCORTS);
          return OOJSNativeFailure(context);
        }
        ship->setMaxEscortCount(iValue);
        return JS_UNDEFINED;
      }

      break;

    default:
      OOJSReportBadPropertySelector(context, thisObj, magic, sShipProperties,
                                    OOJS_COUNT(sShipProperties));
      return OOJSNativeFailure(context);
  }

  OOJSReportBadPropertyValue(context, thisObj, magic, sShipProperties,
                             OOJS_COUNT(sShipProperties), value);
  return OOJSNativeFailure(context);

playerReadOnly:
  cxx_OOJSReportError(context, "player.ship.%s is read-only.",
                      cxx_OOStringFromJSPropertyMagic(
                          magic, sShipProperties, OOJS_COUNT(sShipProperties))
                          .c_str());
  return OOJSNativeFailure(context);

  // Not used (yet)
  /*
  npcReadOnly:
          cxx_OOJSReportError(context, "npc.ship.%s is read-only.",
  cxx_OOStringFromJSPropertyMagic(magic, sShipProperties,
  OOJS_COUNT(sShipProperties)).c_str()); return OOJSNativeFailure(context);
  */

  OOJS_NATIVE_EXIT
}

// *** Methods ***

#define GET_THIS_SHIP(THISENT)                                            \
  do {                                                                    \
    if (EXPECT_NOT(!JSShipGetShipEntity(context, OOJS_THIS, &(THISENT)))) \
      return OOJSNativeFailure(context); /* Exception */                  \
    if (OOIsStaleEntity(THISENT)) OOJS_RETURN_VOID;                       \
  } while (0)

// setScript(scriptName : String)
static JSValue ShipSetScript(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  ShipEntity* thisEnt = nullptr;
  std::optional<std::string> name;

  GET_THIS_SHIP(thisEnt);
  ShipEntity* ship = thisEnt;  // not null: thisEnt is not
  if (argc > 0) name = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
  if (EXPECT_NOT(!name.has_value())) {
    cxx_OOJSReportBadArguments(context, "Ship", "setScript", MIN(argc, 1),
                               OOJS_ARGV, std::nullopt, "string (script name)");
    return OOJSNativeFailure(context);
  }
  if (EXPECT_NOT(ship->getIsPlayer())) {
    cxx_OOJSReportErrorForCaller(context, "Ship", "setScript",
                                 "Not valid for player ship.");
    return OOJSNativeFailure(context);
  }

  ship->setShipScript(name);
  OOJS_RETURN_VOID;

  OOJS_NATIVE_EXIT
}

// setAI(aiName : String)
static JSValue ShipSetAI(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  ShipEntity* thisEnt = nullptr;
  std::optional<std::string> name;

  GET_THIS_SHIP(thisEnt);
  ShipEntity* ship = thisEnt;  // not null: thisEnt is not
  if (argc > 0) name = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
  if (EXPECT_NOT(!name.has_value())) {
    cxx_OOJSReportBadArguments(context, "Ship", "setAI", MIN(argc, 1),
                               OOJS_ARGV, std::nullopt, "string (AI name)");
    return OOJSNativeFailure(context);
  }
  if (EXPECT_NOT(ship->getIsPlayer())) {
    cxx_OOJSReportErrorForCaller(context, "Ship", "setAI",
                                 "Not valid for player ship.");
    return OOJSNativeFailure(context);
  }

  ship->setAITo(*name);
  OOJS_RETURN_VOID;

  OOJS_NATIVE_EXIT
}

// switchAI(aiName : String)
static JSValue ShipSwitchAI(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  ShipEntity* thisEnt = nullptr;
  std::optional<std::string> name;

  GET_THIS_SHIP(thisEnt);
  ShipEntity* ship = thisEnt;  // not null: thisEnt is not
  if (argc > 0) name = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
  if (EXPECT_NOT(!name.has_value())) {
    cxx_OOJSReportBadArguments(context, "Ship", "switchAI", MIN(argc, 1),
                               OOJS_ARGV, std::nullopt, "string (AI name)");
    return OOJSNativeFailure(context);
  }
  if (EXPECT_NOT(ship->getIsPlayer())) {
    cxx_OOJSReportErrorForCaller(context, "Ship", "switchAI",
                                 "Not valid for player ship.");
    return OOJSNativeFailure(context);
  }

  ship->switchAITo(*name);
  OOJS_RETURN_VOID;

  OOJS_NATIVE_EXIT
}

// exitAI()
static JSValue ShipExitAI(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  ShipEntity* thisEnt = nullptr;
  AI* thisAI = nullptr;
  std::optional<std::string> message;  // nullopt: the AI defaults to RESTARTED

  GET_THIS_SHIP(thisEnt);
  ShipEntity* ship = thisEnt;  // not null: thisEnt is not
  if (EXPECT_NOT(ship->getIsPlayer())) {
    cxx_OOJSReportErrorForCaller(context, "Ship", "exitAI",
                                 "Not valid for player ship.");
    return OOJSNativeFailure(context);
  }
  thisAI = ship->getAI();

  if (thisAI != nullptr &&
      thisAI->hasSuspendedStateMachines())  // no AI: none, as a message to nil
  {
    if (argc > 0) {
      message = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
    }
    // Else AI will default to RESTARTED.

    thisAI->exitStateMachineWithMessage(message);
  } else {
    cxx_OOJSReportWarningForCaller(
        context, "Ship", "exitAI()",
        "Cannot exit current AI state machine because there are no suspended "
        "state machines.");
  }
  OOJS_RETURN_VOID;

  OOJS_NATIVE_EXIT
}

// reactToAIMessage(message : String)
static JSValue ShipReactToAIMessage(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  ShipEntity* thisEnt = nullptr;
  std::optional<std::string> message;

  GET_THIS_SHIP(thisEnt);
  ShipEntity* ship = thisEnt;  // not null: thisEnt is not
  if (argc > 0) message = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
  if (EXPECT_NOT(!message.has_value())) {
    cxx_OOJSReportBadArguments(context, "Ship", "reactToAIMessage",
                               MIN(argc, 1), OOJS_ARGV, std::nullopt, "string");
    return OOJSNativeFailure(context);
  }
  if (EXPECT_NOT(ship->getIsPlayer())) {
    cxx_OOJSReportErrorForCaller(context, "Ship", "reactToAIMessage",
                                 "Not valid for player ship.");
    return OOJSNativeFailure(context);
  }

  ship->reactToAIMessage(*message, "JavaScript reactToAIMessage()");
  OOJS_RETURN_VOID;

  OOJS_NATIVE_EXIT
}

// sendAIMessage(message : String)
static JSValue ShipSendAIMessage(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  ShipEntity* thisEnt = nullptr;
  std::optional<std::string> message;

  GET_THIS_SHIP(thisEnt);
  ShipEntity* ship = thisEnt;  // not null: thisEnt is not
  if (argc > 0) message = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
  if (EXPECT_NOT(!message.has_value())) {
    cxx_OOJSReportBadArguments(context, "Ship", "sendAIMessage", MIN(argc, 1),
                               OOJS_ARGV, std::nullopt, "string");
    return OOJSNativeFailure(context);
  }
  if (EXPECT_NOT(ship->getIsPlayer())) {
    cxx_OOJSReportErrorForCaller(context, "Ship", "sendAIMessage",
                                 "Not valid for player ship.");
    return OOJSNativeFailure(context);
  }

  ship->sendAIMessage(*message);
  OOJS_RETURN_VOID;

  OOJS_NATIVE_EXIT
}

// deployEscorts()
static JSValue ShipDeployEscorts(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  ShipEntity* thisEnt = nullptr;

  GET_THIS_SHIP(thisEnt);
  ShipEntity* ship = thisEnt;  // not null: thisEnt is not

  ship->deployEscorts();
  OOJS_RETURN_VOID;

  OOJS_NATIVE_EXIT
}

// dockEscorts()
static JSValue ShipDockEscorts(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  ShipEntity* thisEnt = nullptr;

  GET_THIS_SHIP(thisEnt);
  ShipEntity* ship = thisEnt;  // not null: thisEnt is not

  ship->dockEscorts();
  OOJS_RETURN_VOID;

  OOJS_NATIVE_EXIT
}

// hasEquipmentProviding(equipment : String) : Boolean
static JSValue ShipHasEquipmentProviding(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  ShipEntity* thisEnt = nullptr;
  std::optional<std::string> equipment;

  GET_THIS_SHIP(thisEnt);
  ShipEntity* ship = thisEnt;  // not null: thisEnt is not

  if (argc > 0) equipment = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
  if (EXPECT_NOT(!equipment.has_value())) {
    cxx_OOJSReportBadArguments(context, "Ship", "hasEquipmentProviding",
                               MIN(argc, 1), OOJS_ARGV, std::nullopt,
                               "string (equipment)");
    return OOJSNativeFailure(context);
  }

  OOJS_RETURN_BOOL(ship->hasEquipmentItemProviding(*equipment));

  OOJS_NATIVE_EXIT
}

// hasRole(role : String) : Boolean
static JSValue ShipHasRole(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  ShipEntity* thisEnt = nullptr;
  std::optional<std::string> role;

  GET_THIS_SHIP(thisEnt);
  ShipEntity* ship = thisEnt;  // not null: thisEnt is not

  if (argc > 0) role = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
  if (EXPECT_NOT(!role.has_value())) {
    cxx_OOJSReportBadArguments(context, "Ship", "hasRole", MIN(argc, 1),
                               OOJS_ARGV, std::nullopt, "string (role)");
    return OOJSNativeFailure(context);
  }

  OOJS_RETURN_BOOL(ship->hasRole(*role));

  OOJS_NATIVE_EXIT
}

// ejectItem(role : String) : Ship
static JSValue ShipEjectItem(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  ShipEntity* thisEnt = nullptr;
  std::optional<std::string> role;

  GET_THIS_SHIP(thisEnt);
  ShipEntity* ship = thisEnt;  // not null: thisEnt is not

  if (argc > 0) role = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
  if (EXPECT_NOT(!role.has_value())) {
    cxx_OOJSReportBadArguments(context, "Ship", "ejectItem", MIN(argc, 1),
                               OOJS_ARGV, std::nullopt, "string (role)");
    return OOJSNativeFailure(context);
  }

  OOJS_RETURN(OOJSValueFromCxxObject(
      context, ship->ejectShipOfRole(role)));  // the C++ ship's JS value

  OOJS_NATIVE_EXIT
}

// addCargoEntity: ship
static JSValue ShipAddCargoEntity(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)
  ShipEntity* thisEnt = nullptr;
  ShipEntity* target = nullptr;
  int procEvents = false;
  int procMessages = false;

  GET_THIS_SHIP(thisEnt);
  ShipEntity* ship = thisEnt;  // not null: thisEnt is not

  if (EXPECT_NOT(ship->getIsPlayer() &&
                 (static_cast<PlayerEntity*>(thisEnt) != nullptr
                      ? static_cast<PlayerEntity*>(thisEnt)->isDocked()
                      : false))) {
    cxx_OOJSReportWarningForCaller(
        context, "PlayerShip", "addCargoEntity",
        "Can't add cargo entity while docked, ignoring.");
    return OOJSNativeFailure(context);
  }
  if (EXPECT_NOT(argc == 0 || JS_IsNull(OOJS_ARGV[0]) ||
                 !JS_IsObject(OOJS_ARGV[0]) ||
                 !JSShipGetShipEntity(context, OOJS_ARGV[0], &target))) {
    cxx_OOJSReportBadArguments(context, "PlayerShip", "addCargoEntity",
                               MIN(argc, 1), OOJS_ARGV, std::nullopt,
                               "scoopable entity.");
    return OOJSNativeFailure(context);
  }
  if (target == nullptr ||
      target->getScanClass() !=
          OOScanClass::kCargo)  // none: OOScanClass::kNoDraw, as a message to
                                // nil
  {
    cxx_OOJSReportWarningForCaller(context, "PlayerShip", "addCargoEntity",
                                   "Scoopable entity not cargo.");
    return OOJSNativeFailure(context);
  }
  if (target->status() != OOEntityStatus::kInFlight) {
    cxx_OOJSReportWarningForCaller(context, "PlayerShip", "addCargoEntity",
                                   "Scoopable entity not in flight.");
    return OOJSNativeFailure(context);
  }
  if (argc >= 2 &&
      EXPECT_NOT(!((procEvents = JS_ToBool(context, OOJS_ARGV[1])) >= 0))) {
    cxx_OOJSReportBadArguments(context, "PlayerShip", "addCargoEntity",
                               MIN(argc, 2), OOJS_ARGV, std::nullopt,
                               "boolean");
    return OOJSNativeFailure(context);
  }
  if (argc == 3 &&
      EXPECT_NOT(!((procMessages = JS_ToBool(context, OOJS_ARGV[2])) >= 0))) {
    cxx_OOJSReportBadArguments(context, "PlayerShip", "addCargoEntity",
                               MIN(argc, 3), OOJS_ARGV, std::nullopt,
                               "boolean");
    return OOJSNativeFailure(context);
  }

  // scoop the object, but don't process any events/messages unless requested
  OOJS_BEGIN_FULL_NATIVE(context)
  ship->scoopUpProcess(target, procEvents, procMessages);
  OOJS_END_FULL_NATIVE

  OOJS_RETURN_BOOL(target->status() == OOEntityStatus::kInHold);

  OOJS_NATIVE_EXIT
}

// ejectSpecificItem(itemKey : String) : Ship
static JSValue ShipEjectSpecificItem(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  ShipEntity* thisEnt = nullptr;
  std::optional<std::string> itemKey;

  GET_THIS_SHIP(thisEnt);
  ShipEntity* ship = thisEnt;  // not null: thisEnt is not

  if (argc > 0) itemKey = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
  if (EXPECT_NOT(!itemKey.has_value())) {
    cxx_OOJSReportBadArguments(context, "Ship", "ejectSpecificItem",
                               MIN(argc, 1), OOJS_ARGV, std::nullopt,
                               "string (ship key)");
    return OOJSNativeFailure(context);
  }

  OOJS_RETURN(OOJSValueFromCxxObject(
      context, ship->ejectShipOfType(itemKey)));  // the C++ ship's JS value

  OOJS_NATIVE_EXIT
}

// dumpCargo() : Ship
static JSValue ShipDumpCargo(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  ShipEntity* thisEnt = nullptr;
  std::optional<std::string> pref;  // nullopt: no preference

  GET_THIS_SHIP(thisEnt);
  ShipEntity* ship = thisEnt;  // not null: thisEnt is not

  if (EXPECT_NOT(ship->getIsPlayer() &&
                 (static_cast<PlayerEntity*>(thisEnt) != nullptr
                      ? static_cast<PlayerEntity*>(thisEnt)->isDocked()
                      : false))) {
    cxx_OOJSReportWarningForCaller(context, "PlayerShip", "dumpCargo",
                                   "Can't dump cargo while docked, ignoring.");
    OOJS_RETURN_NULL;
  }

  if (argc > 1) {
    pref = cxx_OOStringFromJSValue(context, OOJS_ARGV[1]);
  }

  // NPCs can queue multiple items to dump
  if (!EXPECT_NOT(ship->getIsPlayer())) {
    int32_t i, count = 1;
    bool gotCount = true;
    if (argc > 0) gotCount = OOJSValueToInt32(context, OOJS_ARGV[0], &count);
    if (EXPECT_NOT(!gotCount || count < 1 || count > 64)) {
      cxx_OOJSReportBadArguments(
          context, "Ship", "dumpCargo", MIN(argc, 1), OOJS_ARGV, std::nullopt,
          "optional quantity (1 to 64), optional preferred commodity");
      return OOJSNativeFailure(context);
    }

    for (i = 1; i < count; i++) {
      // drop 3 canisters per 2 seconds (a deferred call on the C++ ship)
      oo::ScheduleEntityCall(
          thisEnt,
          [](Entity* entity) {
            if (ShipEntity* ship = dynamic_cast<ShipEntity*>(entity))
              ship->dumpCargo();
          },
          (0.75 * i));
    }
  }

  OOJS_RETURN(OOJSValueFromCxxObject(
      context, ship->dumpCargoItem(pref)));  // the C++ pod's JS value

  OOJS_NATIVE_EXIT
}

// spawn(role : String [, number : count]) : Array
static JSValue ShipSpawn(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  ShipEntity* thisEnt = nullptr;
  std::optional<std::string> role;
  int32_t count = 1;
  bool gotCount = true;
  std::vector<oo::EntityHold> result;

  GET_THIS_SHIP(thisEnt);
  ShipEntity* ship = thisEnt;  // not null: thisEnt is not

  if (argc > 0) role = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
  if (argc > 1) gotCount = OOJSValueToInt32(context, OOJS_ARGV[1], &count);
  if (EXPECT_NOT(!role.has_value() || !gotCount || count < 1 || count > 64)) {
    cxx_OOJSReportBadArguments(context, "Ship", "spawn", MIN(argc, 1),
                               OOJS_ARGV, std::nullopt,
                               "role and optional quantity (1 to 64)");
    return OOJSNativeFailure(context);
  }

  OOJS_BEGIN_FULL_NATIVE(context)
  result = ship->spawnShipsWithRole(*role, count);
  OOJS_END_FULL_NATIVE

  OOJS_RETURN_PLIST(oo::EntityNodesFrom(result));

  OOJS_NATIVE_EXIT
}

// dealEnergyDamage(). Replaces AI's dealEnergyDamageWithinDesiredRange
static JSValue ShipDealEnergyDamage(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  ShipEntity* thisEnt = nullptr;
  double baseDamage;
  double range;
  double velocityBias = 0.0;
  bool gotDamage;
  bool gotRange;
  bool gotVBias;
  GET_THIS_SHIP(thisEnt);
  ShipEntity* ship = thisEnt;  // not null: thisEnt is not

  if (argc < 2) {
    cxx_OOJSReportBadArguments(context, "Ship", "dealEnergyDamage", argc,
                               OOJS_ARGV, std::nullopt,
                               "damage and range needed");
    return OOJSNativeFailure(context);
  }

  gotDamage = (JS_ToFloat64(context, &baseDamage, OOJS_ARGV[0]) == 0);
  if (EXPECT_NOT(!gotDamage || baseDamage < 0)) {
    cxx_OOJSReportBadArguments(context, "Ship", "dealEnergyDamage", argc,
                               OOJS_ARGV, std::nullopt,
                               "damage must be positive");
    return OOJSNativeFailure(context);
  }
  gotRange = (JS_ToFloat64(context, &range, OOJS_ARGV[1]) == 0);
  if (EXPECT_NOT(!gotRange || range < 0)) {
    cxx_OOJSReportBadArguments(context, "Ship", "dealEnergyDamage", argc,
                               OOJS_ARGV, std::nullopt,
                               "range must be positive");
    return OOJSNativeFailure(context);
  }
  if (argc >= 3) {
    gotVBias = (JS_ToFloat64(context, &velocityBias, OOJS_ARGV[2]) == 0);
    if (!gotVBias) {
      cxx_OOJSReportBadArguments(context, "Ship", "dealEnergyDamage", argc,
                                 OOJS_ARGV, std::nullopt,
                                 "velocity bias must be a number");
      return OOJSNativeFailure(context);
    }
  }

  ship->dealEnergyDamage(static_cast<GLfloat>(baseDamage),
                         static_cast<GLfloat>(range),
                         static_cast<GLfloat>(velocityBias));

  OOJS_RETURN_VOID;

  OOJS_NATIVE_EXIT
}

// explode()
static JSValue ShipExplode(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  return RemoveOrExplodeShip(context, OOJS_THIS, argc, OOJS_ARGV, true);

  OOJS_NATIVE_EXIT
}

// remove([suppressDeathEvent : Boolean = false])
static JSValue ShipRemove(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  ShipEntity* thisEnt = nullptr;
  int suppressDeathEvent = false;

  GET_THIS_SHIP(thisEnt);
  ShipEntity* ship = thisEnt;  // not null: thisEnt is not

  if (ship->getIsPlayer()) {
    cxx_OOJSReportError(context, "Cannot remove() player's ship.");
    return OOJSNativeFailure(context);
  }

  if (argc > 0 && EXPECT_NOT(!((suppressDeathEvent =
                                    JS_ToBool(context, OOJS_ARGV[0])) >= 0))) {
    cxx_OOJSReportBadArguments(context, "Ship", "remove", argc, OOJS_ARGV,
                               std::nullopt, "boolean");
    return OOJSNativeFailure(context);
  }

  ship->doScriptEvent(OOJSID("shipRemoved"),
                      {oo::PList(static_cast<bool>(suppressDeathEvent))});

  if (suppressDeathEvent) {
    ship->removeScript();
  }
  return RemoveOrExplodeShip(context, OOJS_THIS, argc, OOJS_ARGV, false);

  OOJS_NATIVE_EXIT
}

// __runLegacyScriptActions(target : Ship, actions : Array)
static JSValue ShipRunLegacyScriptActions(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  ShipEntity* thisEnt = nullptr;
  PlayerEntity* player = nullptr;
  ShipEntity* target = nullptr;
  oo::PList actions;  // null when absent

  player = OOPlayerForScripting();
  GET_THIS_SHIP(thisEnt);
  ShipEntity* ship = thisEnt;  // not null: thisEnt is not

  if (argc > 1) actions = cxx_OOJSPListFromJSValue(context, OOJS_ARGV[1]);
  if (EXPECT_NOT(argc != 2 || !JS_IsObject(OOJS_ARGV[0]) ||
                 !JSShipGetShipEntity(context, OOJS_ARGV[0], &target) ||
                 !actions.isArray())) {
    cxx_OOJSReportBadArguments(context, "Ship", "__runLegacyScriptActions",
                               argc, OOJS_ARGV, std::nullopt,
                               "target and array of actions");
    return OOJSNativeFailure(context);
  }

  if (target != nullptr)  // Not stale reference
  {
    if (player != nullptr) player->setScriptTarget(thisEnt);
    if (player != nullptr)
      player->runUnsanitizedScriptActions(
          actions, true,
          std::format("<ship \"{}\" legacy actions>",
                      ship->getName().value_or("(null)")),
          target);
  }

  OOJS_RETURN_VOID;

  OOJS_NATIVE_EXIT
}

// commsMessage(message : String[,target : Ship])
static JSValue ShipCommsMessage(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  ShipEntity* thisEnt = nullptr;
  std::optional<std::string> message;
  ShipEntity* target = nullptr;

  GET_THIS_SHIP(thisEnt);
  ShipEntity* ship = thisEnt;  // not null: thisEnt is not

  if (argc > 0) message = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
  if (EXPECT_NOT(!message.has_value() ||
                 (argc > 1 &&
                  (JS_IsNull(OOJS_ARGV[1]) || !JS_IsObject(OOJS_ARGV[1]) ||
                   !JSShipGetShipEntity(context, OOJS_ARGV[1], &target))))) {
    cxx_OOJSReportBadArguments(context, "Ship", "commsMessage", MIN(argc, 1),
                               OOJS_ARGV, std::nullopt,
                               "message and optional target");
    return OOJSNativeFailure(context);
  }

  if (argc < 2) {
    ship->commsMessage(*message, true);  // generic broadcast
  } else if (target != nullptr)          // Not stale reference
  {
    ship->sendMessage(*message, target, true);  // ship-to-ship narrowcast
  }
  OOJS_RETURN_VOID;

  OOJS_NATIVE_EXIT
}

// fireECM()
static JSValue ShipFireECM(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  ShipEntity* thisEnt = nullptr;
  bool OK;

  GET_THIS_SHIP(thisEnt);
  ShipEntity* ship = thisEnt;  // not null: thisEnt is not

  OK = ship->fireECM();
  if (!OK) {
    // The C++ ship's JS description: made of its jsClassName() and
    // descriptionComponents().
    cxx_OOJSReportWarning(
        context,
        "Ship %s was requested to fire ECM burst but does not carry ECM "
        "equipment.",
        EntityJSDescription(thisEnt).value_or("(null)").c_str());
  }

  OOJS_RETURN_BOOL(OK);

  OOJS_NATIVE_EXIT
}

// abandonShip()
static JSValue ShipAbandonShip(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  ShipEntity* thisEnt = nullptr;

  GET_THIS_SHIP(thisEnt);
  ShipEntity* ship = thisEnt;  // not null: thisEnt is not
  OOJS_RETURN_BOOL(ship->hasEscapePod() && ship->abandonShip());

  OOJS_NATIVE_EXIT
}

// canAwardEquipment(type : equipmentInfoExpression)
static JSValue ShipCanAwardEquipment(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  ShipEntity* thisEnt = nullptr;
  std::optional<std::string> key;
  std::string ctx =
      "scripted";  // a nil context fails the check below, as "" does
  bool result;
  bool exists;

  GET_THIS_SHIP(thisEnt);
  ShipEntity* ship = thisEnt;  // not null: thisEnt is not

  if (argc > 0)
    key = JSValueToEquipmentKeyRelaxed(context, OOJS_ARGV[0], &exists);
  if (EXPECT_NOT(!key.has_value())) {
    cxx_OOJSReportBadArguments(context, "Ship", "canAwardEquipment",
                               MIN(argc, 1), OOJS_ARGV, std::nullopt,
                               "equipment type");
    return OOJSNativeFailure(context);
  }

  if (exists) {
    if (argc > 1) {
      ctx = cxx_OOStringFromJSValue(context, OOJS_ARGV[1])
                .value_or(std::string());
      if (ctx != "scripted" && ctx != "purchase" && ctx != "newShip" &&
          ctx != "npc") {
        cxx_OOJSReportBadArguments(context, "Ship", "canAwardEquipment",
                                   MIN(argc, 2), OOJS_ARGV, std::nullopt,
                                   "context");
        return OOJSNativeFailure(context);
      }
    }
    result = true;

    // can't add fuel as equipment.
    if (*key == "EQ_FUEL") result = false;

    if (result) result = ship->canAddEquipment(*key, ctx);
  } else {
    // Unknown type.
    result = false;
  }

  OOJS_RETURN_BOOL(result);

  OOJS_NATIVE_EXIT
}

// awardEquipment(type : equipmentInfoExpression) : Boolean
static JSValue ShipAwardEquipment(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  ShipEntity* thisEnt = nullptr;
  OOEquipmentType* eqType = nullptr;
  std::string identifier;
  bool OK = true;
  bool berth;
  bool isRepair = false;

  GET_THIS_SHIP(thisEnt);
  ShipEntity* ship = thisEnt;  // not null: thisEnt is not

  if (argc > 0) eqType = JSValueToEquipmentType(context, OOJS_ARGV[0]);
  if (EXPECT_NOT(eqType == nullptr)) {
    cxx_OOJSReportBadArguments(context, "Ship", "awardEquipment", MIN(argc, 1),
                               OOJS_ARGV, std::nullopt, "equipment type");
    return OOJSNativeFailure(context);
  }

  // Check that equipment is permitted.
  OOEquipmentType* cxxEqType = eqType;  // not null: eqType is not
  identifier = cxxEqType->identifier().value_or("");
  berth = identifier == "EQ_PASSENGER_BERTH";
  if (berth) {
    OK = ship->availableCargoSpace() >= cxxEqType->requiredCargoSpace();
  } else if (identifier == "EQ_FUEL") {
    OK = false;
  } else {
    OK = cxxEqType->canCarryMultiple() ||
         !ship->hasEquipmentItem(oo::PList(identifier));
  }

  if (OK) {
    if (ship->getIsPlayer()) {
      PlayerEntity* player = static_cast<PlayerEntity*>(thisEnt);

      if (identifier == "EQ_MISSILE_REMOVAL") {
        ship->removeMissiles();  // PlayerEntity's, through the virtual
      } else if (cxxEqType->isMissileOrMine()) {
        OK = (player != nullptr ? player->mountMissileWithRole(identifier)
                                : false);
      } else if (berth) {
        OK = (player != nullptr ? player->changePassengerBerths(+1) : false);
      } else if (identifier == "EQ_PASSENGER_BERTH_REMOVAL") {
        OK = (player != nullptr ? player->changePassengerBerths(-1) : false);
      } else {
        isRepair = ship->hasEquipmentItem(oo::PList(identifier + "_DAMAGED"));
        OK = ship->addEquipmentItem(
            identifier, true,
            "scripted");  // PlayerEntity's, through the virtual
        if (OK && isRepair) {
          ship->doScriptEvent(OOJSID("equipmentRepaired"),
                              {oo::PList(identifier)});
        }
      }
    } else {
      if (identifier == "EQ_MISSILE_REMOVAL") {
        ship->removeMissiles();
      }
      // no passenger handling for NPCs. EQ_CARGO_BAY is dealt with inside
      // addEquipmentItem
      else if (!berth && identifier != "EQ_PASSENGER_BERTH_REMOVAL") {
        OK = ship->addEquipmentItem(identifier, true, "scripted");
      } else {
        OK = false;
      }
    }
  }

  OOJS_RETURN_BOOL(OK);

  OOJS_NATIVE_EXIT
}

// removeEquipment(type : equipmentInfoExpression)
static JSValue ShipRemoveEquipment(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  ShipEntity* thisEnt = nullptr;
  std::optional<std::string> key;
  bool OK = true;

  GET_THIS_SHIP(thisEnt);
  ShipEntity* ship = thisEnt;  // not null: thisEnt is not

  if (argc > 0) key = JSValueToEquipmentKey(context, OOJS_ARGV[0]);
  if (EXPECT_NOT(!key.has_value())) {
    cxx_OOJSReportBadArguments(context, "Ship", "removeEquipment", MIN(argc, 1),
                               OOJS_ARGV, std::nullopt, "equipment type");
    return OOJSNativeFailure(context);
  }
  // berths are not in hasOneEquipmentItem
  OK = ship->hasOneEquipmentItemIncludingMissiles(*key, true, false) ||
       (*key == "EQ_PASSENGER_BERTH" && ship->passengerCapacity() > 0);
  if (!OK) {
    // Allow removal of damaged equipment.
    key = *key + "_DAMAGED";
    OK = ship->hasOneEquipmentItemIncludingMissiles(*key, false, false);
  }
  if (OK) {
    // exceptions
    if (*key == "EQ_PASSENGER_BERTH" || *key == "EQ_CARGO_BAY") {
      if (*key == "EQ_PASSENGER_BERTH") {
        if (ship->passengerCapacity() > ship->passengerCount()) {
          // must be the player's ship!
          if (ship->getIsPlayer())
            static_cast<PlayerEntity*>(thisEnt)->changePassengerBerths(
                -1);  // thisEnt is not null here
        } else
          OK = false;
      } else  // EQ_CARGO_BAY
      {
        // player cargo bay removal handled in script
        if (ship->getIsPlayer() ||
            ship->extraCargo() <= ship->availableCargoSpace()) {
          ship->removeEquipmentItem(*key);
        } else
          OK = false;
      }
    } else
      ship->removeEquipmentItem(*key);
  }

  OOJS_RETURN_BOOL(OK);

  OOJS_NATIVE_EXIT
}

// restoreSubEntities(): boolean
static JSValue ShipRestoreSubEntities(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  ShipEntity* thisEnt = nullptr;
  std::size_t numSubEntitiesRestored = 0U;

  GET_THIS_SHIP(thisEnt);
  ShipEntity* ship = thisEnt;  // not null: thisEnt is not

  std::size_t subCount = ShipEntityJSSubEntitiesForScript(thisEnt).size();

  ship->clearSubEntities();
  ship->setUpSubEntities();

  if (ShipEntityJSSubEntitiesForScript(thisEnt).size() - subCount > 0)
    numSubEntitiesRestored =
        ShipEntityJSSubEntitiesForScript(thisEnt).size() - subCount;

  // for each subentity restored, slightly increase the trade-in factor
  if (ship->getIsPlayer()) {
    int tradeInFactorChange = static_cast<int>(MAX(
        PLAYER_SHIP_SUBENTITY_TRADE_IN_VALUE * numSubEntitiesRestored, 25U));
    if (static_cast<PlayerEntity*>(thisEnt) != nullptr)
      static_cast<PlayerEntity*>(thisEnt)->adjustTradeInFactorBy(
          tradeInFactorChange);
  }

  OOJS_RETURN_BOOL(numSubEntitiesRestored > 0);

  OOJS_NATIVE_EXIT
}

// setEquipmentStatus(type : equipmentInfoExpression, status : String): boolean
static JSValue ShipSetEquipmentStatus(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  // equipment status accepted: @"EQUIPMENT_OK", @"EQUIPMENT_DAMAGED"

  ShipEntity* thisEnt = nullptr;
  OOEquipmentType* eqType = nullptr;
  std::string key;
  std::string damagedKey;
  std::optional<std::string> status;
  bool hasOK = false, hasDamaged = false;

  GET_THIS_SHIP(thisEnt);
  ShipEntity* ship = thisEnt;  // not null: thisEnt is not

  if (argc < 2) {
    cxx_OOJSReportBadArguments(context, "Ship", "setEquipmentStatus", argc,
                               OOJS_ARGV, std::nullopt,
                               "equipment type and status");
    return OOJSNativeFailure(context);
  }

  eqType = JSValueToEquipmentType(context, OOJS_ARGV[0]);
  if (EXPECT_NOT(eqType == nullptr)) {
    cxx_OOJSReportBadArguments(context, "Ship", "setEquipmentStatus", 1,
                               &OOJS_ARGV[0], std::nullopt, "equipment type");
    return OOJSNativeFailure(context);
  }

  status = cxx_OOStringFromJSValue(context, OOJS_ARGV[1]);
  if (EXPECT_NOT(!status.has_value())) {
    cxx_OOJSReportBadArguments(context, "Ship", "setEquipmentStatus", 1,
                               &OOJS_ARGV[1], std::nullopt, "equipment status");
    return OOJSNativeFailure(context);
  }

  // EMMSTRAN: use interned strings.
  if (*status != "EQUIPMENT_OK" && *status != "EQUIPMENT_DAMAGED") {
    cxx_OOJSReportErrorForCaller(
        context, "Ship", "setEquipmentStatus",
        "Second parameter for setEquipmentStatus must be either "
        "\"EQUIPMENT_OK\" or \"EQUIPMENT_DAMAGED\".");
    return OOJSNativeFailure(context);
  }

  OOEquipmentType* cxxEqType = eqType;  // not null: eqType is not
  key = cxxEqType->identifier().value_or("");
  hasOK = ship->hasEquipmentItem(oo::PList(key));
  bool setOK = *status == "EQUIPMENT_OK";
  bool setDamaged = *status == "EQUIPMENT_DAMAGED";
  if (cxxEqType->canBeDamaged()) {
    damagedKey = key + "_DAMAGED";
    hasDamaged = ship->hasEquipmentItem(oo::PList(damagedKey));

    if ((setOK && hasDamaged) || (setDamaged && hasOK)) {
      // the implementation is identical between player and ship.
      ship->removeEquipmentItem(setDamaged ? key : damagedKey);
      if (ship->getIsPlayer()) {
        // these player methods are different to the ship ones.
        ship->addEquipmentItem(
            setDamaged ? damagedKey : key, false,
            "scripted");  // PlayerEntity's, through the virtual
        if (setDamaged) {
          ship->doScriptEvent(OOJSID("equipmentDamaged"), {oo::PList(key)});
        } else if (setOK) {
          ship->doScriptEvent(OOJSID("equipmentRepaired"), {oo::PList(key)});
        }

        // if player's Docking Computers are set to EQUIPMENT_DAMAGED while on,
        // stop them this is now done in a different method if (hasOK && [key
        // isEqualToString:@"EQ_DOCK_COMP"])  [(PlayerEntity*)thisEnt
        // disengageAutopilot];
      } else {
        ship->addEquipmentItem(setDamaged ? damagedKey : key, false,
                               "scripted");
        if (hasOK)
          ship->doScriptEvent(OOJSID("equipmentDamaged"), {oo::PList(key)});
      }
    }
  } else {
    if (hasOK && *status != "EQUIPMENT_OK") {
      cxx_OOJSReportWarningForCaller(context, "Ship", "setEquipmentStatus",
                                     "Equipment %s cannot be damaged.",
                                     key.c_str());
      hasOK = false;
    }
  }

  OOJS_RETURN_BOOL(hasOK || hasDamaged);

  OOJS_NATIVE_EXIT
}

// equipmentStatus(type : equipmentInfoExpression) : String
static JSValue ShipEquipmentStatus(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  ShipEntity* thisEnt = nullptr;
  std::optional<std::string> key;
  bool asDict = false;

  GET_THIS_SHIP(thisEnt);
  ShipEntity* ship = thisEnt;  // not null: thisEnt is not

  if (argc > 0) key = JSValueToEquipmentKey(context, OOJS_ARGV[0]);
  if (argc > 1) asDict = OOJSValueToBOOL(context, OOJS_ARGV[1]);
  if (EXPECT_NOT(!key.has_value())) {
    if (argc > 0 && JS_IsString(OOJS_ARGV[0])) {
      if (asDict) {
        OOJS_RETURN_PLIST(oo::PList(oo::PList::Dict{
            {"EQUIPMENT_UNKNOWN", oo::PList::signedInteger(1)}}));
      } else {
        OOJS_RETURN(OOJSSTR("EQUIPMENT_UNKNOWN"));
      }
    }

    cxx_OOJSReportBadArguments(context, "Ship", "equipmentStatus", MIN(argc, 1),
                               &OOJS_ARGV[0], std::nullopt, "equipment type");
    return OOJSNativeFailure(context);
  }

  if (asDict) {
    oo::PList::Dict dict;
    dict["EQUIPMENT_OK"] =
        oo::PList::unsignedInteger(ship->countEquipmentItem(*key));
    dict["EQUIPMENT_DAMAGED"] =
        oo::PList::unsignedInteger(ship->countEquipmentItem(*key + "_DAMAGED"));
    OOJS_RETURN_PLIST(oo::PList(std::move(dict)));
  } else {
    if (ship->hasEquipmentItem(oo::PList(*key), true, false))
      OOJS_RETURN(OOJSSTR("EQUIPMENT_OK"));
    else if (ship->hasEquipmentItem(oo::PList(*key + "_DAMAGED")))
      OOJS_RETURN(OOJSSTR("EQUIPMENT_DAMAGED"));

    OOJS_RETURN(OOJSSTR("EQUIPMENT_UNAVAILABLE"));
  }
  OOJS_NATIVE_EXIT
}

// selectNewMissile()
static JSValue ShipSelectNewMissile(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  ShipEntity* thisEnt = nullptr;

  GET_THIS_SHIP(thisEnt);
  ShipEntity* ship = thisEnt;  // not null: thisEnt is not

  // if there's a badly defined missile, selectMissile may return nil
  OOEquipmentType* missile = ship->selectMissile();
  const std::string result =
      ((missile != nullptr) ? missile->identifier() : std::nullopt)
          .value_or("EQ_MISSILE");

  OOJS_RETURN_PLIST(oo::PList(result));

  OOJS_NATIVE_EXIT
}

// fireMissile()
static JSValue ShipFireMissile(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  ShipEntity* thisEnt = nullptr;
  ShipEntity* result = nullptr;

  GET_THIS_SHIP(thisEnt);
  ShipEntity* ship = thisEnt;  // not null: thisEnt is not

  if (argc > 0)
    result = ship->fireMissileWithIdentifier(
        cxx_OOStringFromJSValue(context, OOJS_ARGV[0]), ship->primaryTarget());
  else
    result = ship->fireMissile();

  OOJS_RETURN(
      OOJSValueFromCxxObject(context, result));  // the C++ missile's JS value

  OOJS_NATIVE_EXIT
}

// findNearestStation
static JSValue ShipFindNearestStation(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  ShipEntity* thisEnt = nullptr;
  ShipEntity* result = nullptr;  // a station

  GET_THIS_SHIP(thisEnt);
  ShipEntity* ship = thisEnt;  // not null: thisEnt is not

  double sdist, distance = 1E32;

  ShipEntity* se = nullptr;
  for (const auto& stationRef :
       (UNIVERSE != nullptr ? UNIVERSE->stations()
                            : std::vector<oo::EntityHold>())) {
    se = oo::ToShip(stationRef.get());
    sdist = HPdistance2(
        ship->getPosition(),
        (se != nullptr ? se->getPosition()
                       : kZeroHPVector));  // (a message to nil answered zero)

    if (sdist < distance) {
      distance = sdist;
      result = se;
    }
  }

  OOJS_RETURN(
      OOJSValueFromCxxObject(context, result));  // the C++ station's JS value

  OOJS_NATIVE_EXIT
}

// setBounty(amount, reason)
static JSValue ShipSetBounty(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  ShipEntity* thisEnt = nullptr;
  std::optional<std::string> reason;
  int32_t newbounty = 0;
  bool gotBounty = true;

  GET_THIS_SHIP(thisEnt);
  ShipEntity* ship = thisEnt;  // not null: thisEnt is not

  if (argc > 0) gotBounty = OOJSValueToInt32(context, OOJS_ARGV[0], &newbounty);
  if (argc > 1) reason = cxx_OOStringFromJSValue(context, OOJS_ARGV[1]);
  if (EXPECT_NOT(!reason.has_value() || !gotBounty || newbounty < 0)) {
    cxx_OOJSReportBadArguments(context, "Ship", "setBounty", argc, OOJS_ARGV,
                               std::nullopt, "new bounty and reason");
    return OOJSNativeFailure(context);
  }

  ship->setBounty(static_cast<OOCreditsQuantity>(newbounty), *reason);

  OOJS_RETURN_VOID;

  OOJS_NATIVE_EXIT
}

// setCargo(cargoType : String [, number : count])
static JSValue ShipSetCargo(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  ShipEntity* thisEnt = nullptr;
  std::optional<std::string> commodity;
  int32_t count = 1;
  bool gotCount = true;

  GET_THIS_SHIP(thisEnt);
  ShipEntity* ship = thisEnt;  // not null: thisEnt is not

  if (argc > 0) commodity = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
  if (argc > 1) gotCount = OOJSValueToInt32(context, OOJS_ARGV[1], &count);
  if (EXPECT_NOT(!commodity.has_value() || !gotCount || count < 1)) {
    cxx_OOJSReportBadArguments(context, "Ship", "setCargo", argc, OOJS_ARGV,
                               std::nullopt,
                               "cargo name and optional positive quantity");
    return OOJSNativeFailure(context);
  }

  OOCommodities* commodities =
      (UNIVERSE != nullptr
           ? UNIVERSE->getCommodities()
           : nullptr);  // null: no good is defined, as a message to nil
  if (commodities != nullptr && commodities->goodDefined(*commodity)) {
    ship->setCommodityForPod(commodity, count);
  }

  OOJS_RETURN_BOOL(commodities != nullptr &&
                   commodities->goodDefined(*commodity));

  OOJS_NATIVE_EXIT
}

// setCrew(crewDefinition : Object)
static JSValue ShipSetCrew(OOJS_NATIVE_ARGS) {
  /* TODO: ships can in theory have multiple crew, so this could
   * allow that to be set. Probably not necessary for now. */
  OOJS_NATIVE_ENTER(context)

  ShipEntity* thisEnt = nullptr;

  GET_THIS_SHIP(thisEnt);
  ShipEntity* ship = thisEnt;  // not null: thisEnt is not

  // SpiderMonkey's JS_ValueToObject() check let primitives through to an
  // invalid object cast; require an object or null.
  if (argc < 1 || (!JS_IsNull(OOJS_ARGV[0]) && !JS_IsObject(OOJS_ARGV[0]))) {
    cxx_OOJSReportBadArguments(context, "Ship", "setCrew", MIN(argc, 1),
                               OOJS_ARGV, std::nullopt, "definition");
    return OOJSNativeFailure(context);
  }
  bool success = true;

  if (!ship->isExplicitlyUnpiloted()) {
    if (JS_IsNull(OOJS_ARGV[0])) {
      ship->setCrew(std::nullopt);
    } else {
      const oo::Ref<OOCharacter> crew = OOCharacter::characterWithDictionary(
          cxx_OOJSPListFromJSObject(context, OOJS_ARGV[0]));
      std::vector<oo::Ref<OOCharacter>> members;
      if (crew != nullptr)
        members.emplace_back(crew);  // a nil character was skipped (a
                                     // Foundation array cannot hold nil)
      ship->setCrew(members);
    }
  } else {
    success = false;
  }

  OOJS_RETURN_BOOL(success);

  OOJS_NATIVE_EXIT
}

// setCargoType(cargoType : String)
static JSValue ShipSetCargoType(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  ShipEntity* thisEnt = nullptr;
  std::optional<std::string> cargoType;

  GET_THIS_SHIP(thisEnt);
  ShipEntity* ship = thisEnt;  // not null: thisEnt is not

  if (argc > 0) cargoType = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
  if (EXPECT_NOT(!cargoType.has_value())) {
    cxx_OOJSReportBadArguments(context, "Ship", "setCargoType", argc, OOJS_ARGV,
                               std::nullopt, "cargo type name");
    return OOJSNativeFailure(context);
  }
  if (ship->cargoType() != OOCargoType::kNotCargo) {
    cxx_OOJSReportBadArguments(
        context, "Ship", "setCargoType", argc, OOJS_ARGV, std::nullopt,
        std::format(
            "Can only be used on cargo pod carriers, not cargo pods ({})",
            ship->shipDataKey().value_or("(null)")));
    return OOJSNativeFailure(context);
  }
  bool ok = true;
  if (*cargoType == "SCARCE_GOODS") {
    ship->setCargoFlag(OOCargoFlag::kFullScarce);
  } else if (*cargoType == "PLENTIFUL_GOODS") {
    ship->setCargoFlag(OOCargoFlag::kFullPlentiful);
  } else if (*cargoType == "MEDICAL_GOODS") {
    ship->setCargoFlag(OOCargoFlag::kFullMedical);
  } else if (*cargoType == "ILLEGAL_GOODS") {
    ship->setCargoFlag(OOCargoFlag::kFullContraband);
  } else if (*cargoType == "PIRATE_GOODS") {
    ship->setCargoFlag(OOCargoFlag::kPirate);
  } else {
    ok = false;
  }
  OOJS_RETURN_BOOL(ok);

  OOJS_NATIVE_EXIT
}

// setMaterials(params: dict, [shaders: dict])  // sets materials dictionary.
// Optional parameter sets the shaders dictionary too.
static JSValue ShipSetMaterials(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  ShipEntity* thisEnt = nullptr;

  if (argc < 1) {
    cxx_OOJSReportBadArguments(context, "Ship", "setMaterials", 0, OOJS_ARGV,
                               std::nullopt, "parameter object");
    return OOJSNativeFailure(context);
  }

  GET_THIS_SHIP(thisEnt);

  return ShipSetMaterialsInternal(context, OOJS_THIS, argc, OOJS_ARGV, thisEnt,
                                  false);

  OOJS_NATIVE_EXIT
}

// setShaders(params: dict)
static JSValue ShipSetShaders(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  ShipEntity* thisEnt = nullptr;

  GET_THIS_SHIP(thisEnt);

  if (argc < 1) {
    cxx_OOJSReportBadArguments(context, "Ship", "setShaders", 0, OOJS_ARGV,
                               std::nullopt, "parameter object");
    return OOJSNativeFailure(context);
  }

  if (JS_IsNull(OOJS_ARGV[0]) ||
      (!JS_IsNull(OOJS_ARGV[0]) && !JS_IsObject(OOJS_ARGV[0]))) {
    // EMMSTRAN: JS_ValueToObject() and normal error handling here.
    cxx_OOJSReportWarning(
        context, "Ship.%s: expected %s instead of '%s'.", "setShaders",
        "object",
        cxx_OOStringFromJSValueEvenIfNull(context, OOJS_ARGV[0])
            .value_or("(null)")
            .c_str());
    OOJS_RETURN_BOOL(false);
  }

  // SpiderMonkey version: OOJS_ARGV[1] = OOJS_ARGV[0]. QuickJS's argv may be
  // the caller's own stack slots, so copy.
  JSValueConst shaderArgv[2] = {OOJS_ARGV[0], OOJS_ARGV[0]};
  return ShipSetMaterialsInternal(context, OOJS_THIS, argc, shaderArgv, thisEnt,
                                  true);

  OOJS_NATIVE_EXIT
}

namespace {
JSValue ShipSetMaterialsInternal(OOJS_NATIVE_ARGS, ShipEntity* thisEnt,
                                 bool fromShaders) {
  OOJS_PROFILE_ENTER

  JSValueConst params = JS_UNDEFINED;
  oo::PList materials;
  oo::PList shaders;
  bool withShaders = false;
  bool success = false;

  GET_THIS_SHIP(thisEnt);
  ShipEntity* ship = thisEnt;  // not null: thisEnt is not

  if (JS_IsNull(OOJS_ARGV[0]) ||
      (!JS_IsNull(OOJS_ARGV[0]) && !JS_IsObject(OOJS_ARGV[0]))) {
    cxx_OOJSReportWarning(
        context, "Ship.%s: expected %s instead of '%s'.", "setMaterials",
        "object",
        cxx_OOStringFromJSValueEvenIfNull(context, OOJS_ARGV[0])
            .value_or("(null)")
            .c_str());
    OOJS_RETURN_BOOL(false);
  }

  if (argc > 1) {
    withShaders = true;
    if (JS_IsNull(OOJS_ARGV[1]) ||
        (!JS_IsNull(OOJS_ARGV[1]) && !JS_IsObject(OOJS_ARGV[1]))) {
      cxx_OOJSReportWarning(
          context, "Ship.%s: expected %s instead of '%s'.", "setMaterials",
          "object as second parameter",
          cxx_OOStringFromJSValueEvenIfNull(context, OOJS_ARGV[1])
              .value_or("(null)")
              .c_str());
      withShaders = false;
    }
  }

  if (fromShaders) {
    materials = MeshMaterials(ship);
    params = OOJS_ARGV[0];
    shaders = cxx_OOJSPListFromJSObject(context, params);
  } else {
    params = OOJS_ARGV[0];
    materials = cxx_OOJSPListFromJSObject(context, params);
    if (withShaders) {
      params = OOJS_ARGV[1];
      shaders = cxx_OOJSPListFromJSObject(context, params);
    } else {
      shaders = MeshShaders(ship);
    }
  }

  OOJS_BEGIN_FULL_NATIVE(context)
  const oo::PList shipDict = ship->shipInfoDictionary();
  // "ship-prefix-macros": a dictionary, else null (as the dictionary reader
  // gave nil).
  const oo::PList materialDefaults = ResourceManager::materialDefaults();
  const oo::PList* prefixMacros = materialDefaults.find("ship-prefix-macros");

  // First we test to see if we can create the mesh.
  const oo::Ref<OOMesh> mesh = OOMesh::meshWithName(
      shipDict.get<std::string>("model"), std::nullopt, materials, shaders,
      shipDict.get<bool>("smooth", false),
      (prefixMacros != nullptr && prefixMacros->isDict()) ? *prefixMacros
                                                          : oo::PList(),
      thisEnt);  // the C++ ship

  if (mesh != nullptr) {
    ship->setMesh(mesh.get());
    success = true;
  }
  OOJS_END_FULL_NATIVE

  OOJS_RETURN_BOOL(success);

  OOJS_PROFILE_EXIT
}
}  // namespace

// namespace

// exitSystem([int systemID])
static JSValue ShipExitSystem(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  ShipEntity* thisEnt = nullptr;
  int32_t systemID = -1;
  bool OK = false;

  GET_THIS_SHIP(thisEnt);
  ShipEntity* ship = thisEnt;  // not null: thisEnt is not
  if (EXPECT_NOT(ship->getIsPlayer())) {
    cxx_OOJSReportErrorForCaller(context, "Ship", "exitSystem",
                                 "Not valid for player ship.");
    return OOJSNativeFailure(context);
  }

  if (argc > 0) {
    if (!OOJSValueToInt32(context, OOJS_ARGV[0], &systemID) || systemID < 0 ||
        255 < systemID) {
      cxx_OOJSReportBadArguments(context, "Ship", "exitSystem", MIN(argc, 1),
                                 OOJS_ARGV, std::nullopt, "system ID");
      return OOJSNativeFailure(context);
    }
  }

  OK = ship->performHyperSpaceToSpecificSystem(
      systemID);  // -1 == random destination system

  OOJS_RETURN_BOOL(OK);

  OOJS_NATIVE_EXIT
}

static JSValue ShipUpdateEscortFormation(OOJS_NATIVE_ARGS) {
  OOJS_PROFILE_ENTER

  ShipEntity* thisEnt = nullptr;
  GET_THIS_SHIP(thisEnt);
  ShipEntity* ship = thisEnt;  // not null: thisEnt is not
  ship->updateEscortFormation();

  OOJS_RETURN_VOID;

  OOJS_PROFILE_EXIT
}

namespace {
JSValue RemoveOrExplodeShip(OOJS_NATIVE_ARGS, bool explode) {
  OOJS_PROFILE_ENTER

  ShipEntity* thisEnt = nullptr;

  GET_THIS_SHIP(thisEnt);
  ShipEntity* ship = thisEnt;  // not null: thisEnt is not

  if (EXPECT_NOT(ship->getIsPlayer())) {
    OOCAssert(explode,
              "RemoveOrExplodeShip(): shouldn't be called for player with "
              "!explode.");  // player.ship.remove() is blocked by caller.
    PlayerEntity* player = static_cast<PlayerEntity*>(thisEnt);

    if ((player != nullptr ? player->isDocked() : false)) {
      cxx_OOJSReportError(context,
                          "Cannot explode() player's ship while docked.");
      return OOJSNativeFailure(context);
    }
  }

  if (thisEnt ==
      oo::ToShip((UNIVERSE != nullptr ? UNIVERSE->station()
                                      : nullptr)))  // the C++ station
  {
    // Allow exploding of main station (e.g. nova mission)
    if (UNIVERSE != nullptr) UNIVERSE->unMagicMainStation();
  }

  if (EXPECT_NOT(ship->status() == OOEntityStatus::kDocked)) {
    /* If it's in the launch queue and hasn't yet been added to
     * the universe, set the status to DEAD (so it gets removed
     * from the launch queue) */
    ship->setStatus(OOEntityStatus::kDead);
    /* No shipDied event occurs in this place - it never really
     * existed. This case is just to prevent an error from the
     * usual code branch - removing ships while they're still
     * docked is not recommended. */
  } else {
    ship->setSuppressExplosion(!explode);
    ship->setEnergy(1);
    ship->takeEnergyDamage(500000000.0, nullptr, nullptr, std::string());
  }

  OOJS_RETURN_VOID;

  OOJS_PROFILE_EXIT
}
}  // namespace

static JSValue ShipClearDefenseTargets(OOJS_NATIVE_ARGS) {
  OOJS_PROFILE_ENTER

  ShipEntity* thisEnt = nullptr;
  GET_THIS_SHIP(thisEnt);
  ShipEntity* ship = thisEnt;  // not null: thisEnt is not
  ship->removeAllDefenseTargets();

  OOJS_RETURN_VOID;

  OOJS_PROFILE_EXIT
}

static JSValue ShipAddDefenseTarget(OOJS_NATIVE_ARGS) {
  OOJS_PROFILE_ENTER

  ShipEntity* thisEnt = nullptr;
  ShipEntity* target = nullptr;

  GET_THIS_SHIP(thisEnt);
  ShipEntity* ship = thisEnt;  // not null: thisEnt is not
  if (EXPECT_NOT(argc == 0 ||
                 (argc > 0 &&
                  (JS_IsNull(OOJS_ARGV[0]) || !JS_IsObject(OOJS_ARGV[0]) ||
                   !JSShipGetShipEntity(context, OOJS_ARGV[0], &target))))) {
    cxx_OOJSReportBadArguments(context, "Ship", "addDefenseTarget", 1U,
                               OOJS_ARGV, std::nullopt, "target");
    return OOJSNativeFailure(context);
  }

  ship->addDefenseTarget(target);  // the C++ ship (the member takes it)

  OOJS_RETURN_VOID;

  OOJS_PROFILE_EXIT
}

static JSValue ShipRemoveDefenseTarget(OOJS_NATIVE_ARGS) {
  OOJS_PROFILE_ENTER

  ShipEntity* thisEnt = nullptr;
  ShipEntity* target = nullptr;

  GET_THIS_SHIP(thisEnt);
  ShipEntity* ship = thisEnt;  // not null: thisEnt is not
  if (EXPECT_NOT(argc == 0 ||
                 (argc > 0 &&
                  (JS_IsNull(OOJS_ARGV[0]) || !JS_IsObject(OOJS_ARGV[0]) ||
                   !JSShipGetShipEntity(context, OOJS_ARGV[0], &target))))) {
    cxx_OOJSReportBadArguments(context, "Ship", "removeDefenseTarget", 1U,
                               OOJS_ARGV, std::nullopt, "target");
    return OOJSNativeFailure(context);
  }

  ship->removeDefenseTarget(target);  // the C++ ship (the member takes it)

  OOJS_RETURN_VOID;

  OOJS_PROFILE_EXIT
}

static JSValue ShipAddCollisionException(OOJS_NATIVE_ARGS) {
  OOJS_PROFILE_ENTER

  ShipEntity* thisEnt = nullptr;
  ShipEntity* target = nullptr;

  GET_THIS_SHIP(thisEnt);
  ShipEntity* ship = thisEnt;  // not null: thisEnt is not
  if (EXPECT_NOT(argc == 0 ||
                 (argc > 0 &&
                  (JS_IsNull(OOJS_ARGV[0]) || !JS_IsObject(OOJS_ARGV[0]) ||
                   !JSShipGetShipEntity(context, OOJS_ARGV[0], &target))))) {
    cxx_OOJSReportBadArguments(context, "Ship", "addCollisionException", 1U,
                               OOJS_ARGV, std::nullopt, "other ship");
    return OOJSNativeFailure(context);
  }

  // have to do it both ways because it's not defined which order
  // the collisions get tested in. More efficient to add both ways
  // than to test both ways
  ship->addCollisionException(target);
  if (target != nullptr)
    target->addCollisionException(
        thisEnt);  // none: nothing, as a message to nil

  OOJS_RETURN_VOID;

  OOJS_PROFILE_EXIT
}

static JSValue ShipRemoveCollisionException(OOJS_NATIVE_ARGS) {
  OOJS_PROFILE_ENTER

  ShipEntity* thisEnt = nullptr;
  ShipEntity* target = nullptr;

  GET_THIS_SHIP(thisEnt);
  ShipEntity* ship = thisEnt;  // not null: thisEnt is not
  if (EXPECT_NOT(argc == 0 ||
                 (argc > 0 &&
                  (JS_IsNull(OOJS_ARGV[0]) || !JS_IsObject(OOJS_ARGV[0]) ||
                   !JSShipGetShipEntity(context, OOJS_ARGV[0], &target))))) {
    cxx_OOJSReportBadArguments(context, "Ship", "removeCollisionException", 1U,
                               OOJS_ARGV, std::nullopt, "other ship");
    return OOJSNativeFailure(context);
  }

  // doesn't need a check to see if it was already gone
  ship->removeCollisionException(target);
  if (target != nullptr)
    target->removeCollisionException(
        thisEnt);  // none: nothing, as a message to nil

  OOJS_RETURN_VOID;

  OOJS_PROFILE_EXIT
}

// getMaterials()
static JSValue ShipGetMaterials(OOJS_NATIVE_ARGS) {
  OOJS_PROFILE_ENTER

  ShipEntity* thisEnt = nullptr;

  GET_THIS_SHIP(thisEnt);
  ShipEntity* ship = thisEnt;  // not null: thisEnt is not

  oo::PList result = MeshMaterials(ship);
  if (result.isNull())
    result = oo::PList(oo::PList::Dict{});  // empty rather than null
  OOJS_RETURN_PLIST(result);

  OOJS_PROFILE_EXIT
}

// getShaders()
static JSValue ShipGetShaders(OOJS_NATIVE_ARGS) {
  OOJS_PROFILE_ENTER

  ShipEntity* thisEnt = nullptr;

  GET_THIS_SHIP(thisEnt);
  ShipEntity* ship = thisEnt;  // not null: thisEnt is not

  oo::PList result = MeshShaders(ship);
  if (result.isNull())
    result = oo::PList(oo::PList::Dict{});  // empty rather than null
  OOJS_RETURN_PLIST(result);

  OOJS_PROFILE_EXIT
}

static JSValue ShipBroadcastCascadeImminent(OOJS_NATIVE_ARGS) {
  OOJS_PROFILE_ENTER

  ShipEntity* thisEnt = nullptr;
  GET_THIS_SHIP(thisEnt);
  ShipEntity* ship = thisEnt;  // not null: thisEnt is not
  ship->broadcastEnergyBlastImminent();

  OOJS_RETURN_VOID;

  OOJS_PROFILE_EXIT
}

static JSValue ShipBecomeCascadeExplosion(OOJS_NATIVE_ARGS) {
  OOJS_PROFILE_ENTER

  ShipEntity* thisEnt = nullptr;
  GET_THIS_SHIP(thisEnt);
  ShipEntity* ship = thisEnt;  // not null: thisEnt is not
  ship->becomeEnergyBlast();

  OOJS_RETURN_VOID;

  OOJS_PROFILE_EXIT
}

static JSValue ShipOfferToEscort(OOJS_NATIVE_ARGS) {
  OOJS_PROFILE_ENTER

  ShipEntity* thisEnt = nullptr;
  ShipEntity* mother = nullptr;

  GET_THIS_SHIP(thisEnt);
  ShipEntity* ship = thisEnt;  // not null: thisEnt is not
  if (EXPECT_NOT(argc == 0 ||
                 (argc > 0 &&
                  (JS_IsNull(OOJS_ARGV[0]) || !JS_IsObject(OOJS_ARGV[0]) ||
                   !JSShipGetShipEntity(context, OOJS_ARGV[0], &mother))))) {
    cxx_OOJSReportBadArguments(context, "Ship", "offerToEscort", 1U, OOJS_ARGV,
                               std::nullopt, "target");
    return OOJSNativeFailure(context);
  }

  bool result = ship->suggestEscortTo(mother);

  OOJS_RETURN_BOOL(result);

  OOJS_PROFILE_EXIT
}

static JSValue ShipRequestHelpFromGroup(OOJS_NATIVE_ARGS) {
  OOJS_PROFILE_ENTER

  ShipEntity* thisEnt = nullptr;

  GET_THIS_SHIP(thisEnt);
  ShipEntity* ship = thisEnt;  // not null: thisEnt is not

  ship->groupAttackTarget();

  OOJS_RETURN_VOID;

  OOJS_PROFILE_EXIT
}

static JSValue ShipPatrolReportIn(OOJS_NATIVE_ARGS) {
  OOJS_PROFILE_ENTER

  ShipEntity* thisEnt = nullptr;
  ShipEntity* target = nullptr;

  GET_THIS_SHIP(thisEnt);
  if (EXPECT_NOT(argc == 0 ||
                 (argc > 0 &&
                  (JS_IsNull(OOJS_ARGV[0]) || !JS_IsObject(OOJS_ARGV[0]) ||
                   !JSShipGetShipEntity(context, OOJS_ARGV[0], &target))))) {
    cxx_OOJSReportBadArguments(context, "Ship", "addDefenseTarget", 1U,
                               OOJS_ARGV, std::nullopt, "target");
    return OOJSNativeFailure(context);
  }
  if (target != nullptr &&
      target->getIsStation())  // none: not a station, as a message to nil
  {
    StationEntity* station = oo::ToStation(target);  // the C++ ship
    station->acceptPatrolReportFrom(thisEnt);
  }

  OOJS_RETURN_VOID;

  OOJS_PROFILE_EXIT
}

static JSValue ShipMarkTargetForFines(OOJS_NATIVE_ARGS) {
  OOJS_PROFILE_ENTER

  ShipEntity* thisEnt = nullptr;

  GET_THIS_SHIP(thisEnt);

  ShipEntity* ship = oo::ToShip(thisEnt->primaryTarget());
  bool ok = false;
  if ((ship != nullptr) && (ship->status() != OOEntityStatus::kDead) &&
      (ship->status() != OOEntityStatus::kDocked)) {
    ok = ship->markForFines();
  }

  OOJS_RETURN_BOOL(ok);

  OOJS_PROFILE_EXIT
}

static JSValue ShipEnterWormhole(OOJS_NATIVE_ARGS) {
  OOJS_PROFILE_ENTER

  ShipEntity* thisEnt = nullptr;
  Entity* hole = nullptr;

  if ((PLAYER != nullptr ? PLAYER->status() : OOEntityStatus{}) !=
      OOEntityStatus::kEnteringWitchspace) {
    cxx_OOJSReportError(context,
                        "Cannot use this function while player's ship not "
                        "entering witchspace.");
    return OOJSNativeFailure(context);
  }

  GET_THIS_SHIP(thisEnt);
  ShipEntity* ship = thisEnt;  // not null: thisEnt is not
  if (EXPECT_NOT(argc == 0 ||
                 (argc > 0 && !JS_IsNull(OOJS_ARGV[0]) &&
                  (!JS_IsObject(OOJS_ARGV[0]) ||
                   !OOJSEntityGetEntity(context, OOJS_ARGV[0], &hole))))) {
    ship->enterPlayerWormhole();
  } else {
    if (hole == nullptr ||
        !hole->getIsWormhole())  // none: not a wormhole, as a message to nil
    {
      cxx_OOJSReportBadArguments(context, "Ship", "enterWormhole", 1U,
                                 OOJS_ARGV, std::nullopt, "[wormhole]");
      return OOJSNativeFailure(context);
    }

    ship->enterWormhole(
        static_cast<WormholeEntity*>(hole));  // the C++ wormhole
  }

  OOJS_RETURN_VOID;

  OOJS_PROFILE_EXIT
}

static JSValue ShipNotifyGroupOfWormhole(OOJS_NATIVE_ARGS) {
  OOJS_PROFILE_ENTER

  ShipEntity* thisEnt = nullptr;
  GET_THIS_SHIP(thisEnt);
  ShipEntity* ship = thisEnt;  // not null: thisEnt is not

  ship->wormholeEntireGroup();

  OOJS_RETURN_VOID;

  OOJS_PROFILE_EXIT
}

static JSValue ShipThrowSpark(OOJS_NATIVE_ARGS) {
  OOJS_PROFILE_ENTER

  ShipEntity* thisEnt = nullptr;
  GET_THIS_SHIP(thisEnt);
  ShipEntity* ship = thisEnt;  // not null: thisEnt is not
  ship->setThrowSparks(true);

  OOJS_RETURN_VOID;

  OOJS_PROFILE_EXIT
}

static JSValue ShipPerformAttack(OOJS_NATIVE_ARGS) {
  OOJS_PROFILE_ENTER

  ShipEntity* thisEnt = nullptr;
  GET_THIS_SHIP(thisEnt);
  ShipEntity* ship = thisEnt;  // not null: thisEnt is not
  ship->performAttack();

  OOJS_RETURN_VOID;

  OOJS_PROFILE_EXIT
}

static JSValue ShipPerformCollect(OOJS_NATIVE_ARGS) {
  OOJS_PROFILE_ENTER

  ShipEntity* thisEnt = nullptr;
  GET_THIS_SHIP(thisEnt);
  ShipEntity* ship = thisEnt;  // not null: thisEnt is not
  ship->performCollect();

  OOJS_RETURN_VOID;

  OOJS_PROFILE_EXIT
}

static JSValue ShipPerformEscort(OOJS_NATIVE_ARGS) {
  OOJS_PROFILE_ENTER

  ShipEntity* thisEnt = nullptr;
  GET_THIS_SHIP(thisEnt);
  ShipEntity* ship = thisEnt;  // not null: thisEnt is not
  ship->performEscort();

  OOJS_RETURN_VOID;

  OOJS_PROFILE_EXIT
}

static JSValue ShipPerformFaceDestination(OOJS_NATIVE_ARGS) {
  OOJS_PROFILE_ENTER

  ShipEntity* thisEnt = nullptr;
  GET_THIS_SHIP(thisEnt);
  ShipEntity* ship = thisEnt;  // not null: thisEnt is not
  ship->performFaceDestination();

  OOJS_RETURN_VOID;

  OOJS_PROFILE_EXIT
}

static JSValue ShipPerformFlee(OOJS_NATIVE_ARGS) {
  OOJS_PROFILE_ENTER

  ShipEntity* thisEnt = nullptr;
  GET_THIS_SHIP(thisEnt);
  ShipEntity* ship = thisEnt;  // not null: thisEnt is not
  ship->performFlee();

  OOJS_RETURN_VOID;

  OOJS_PROFILE_EXIT
}

static JSValue ShipPerformFlyToRangeFromDestination(OOJS_NATIVE_ARGS) {
  OOJS_PROFILE_ENTER

  ShipEntity* thisEnt = nullptr;
  GET_THIS_SHIP(thisEnt);
  ShipEntity* ship = thisEnt;  // not null: thisEnt is not
  ship->performFlyToRangeFromDestination();

  OOJS_RETURN_VOID;

  OOJS_PROFILE_EXIT
}

static JSValue ShipPerformHold(OOJS_NATIVE_ARGS) {
  OOJS_PROFILE_ENTER

  ShipEntity* thisEnt = nullptr;
  GET_THIS_SHIP(thisEnt);
  ShipEntity* ship = thisEnt;  // not null: thisEnt is not
  ship->performHold();

  OOJS_RETURN_VOID;

  OOJS_PROFILE_EXIT
}

static JSValue ShipPerformIdle(OOJS_NATIVE_ARGS) {
  OOJS_PROFILE_ENTER

  ShipEntity* thisEnt = nullptr;
  GET_THIS_SHIP(thisEnt);
  ShipEntity* ship = thisEnt;  // not null: thisEnt is not
  ship->performIdle();

  OOJS_RETURN_VOID;

  OOJS_PROFILE_EXIT
}

static JSValue ShipPerformIntercept(OOJS_NATIVE_ARGS) {
  OOJS_PROFILE_ENTER

  ShipEntity* thisEnt = nullptr;
  GET_THIS_SHIP(thisEnt);
  ShipEntity* ship = thisEnt;  // not null: thisEnt is not
  ship->performIntercept();

  OOJS_RETURN_VOID;

  OOJS_PROFILE_EXIT
}

static JSValue ShipPerformLandOnPlanet(OOJS_NATIVE_ARGS) {
  OOJS_PROFILE_ENTER

  ShipEntity* thisEnt = nullptr;
  GET_THIS_SHIP(thisEnt);
  ShipEntity* ship = thisEnt;  // not null: thisEnt is not
  ship->performLandOnPlanet();

  OOJS_RETURN_VOID;

  OOJS_PROFILE_EXIT
}

static JSValue ShipPerformMining(OOJS_NATIVE_ARGS) {
  OOJS_PROFILE_ENTER

  ShipEntity* thisEnt = nullptr;
  GET_THIS_SHIP(thisEnt);
  ShipEntity* ship = thisEnt;  // not null: thisEnt is not
  ship->performMining();

  OOJS_RETURN_VOID;

  OOJS_PROFILE_EXIT
}

static JSValue ShipPerformScriptedAI(OOJS_NATIVE_ARGS) {
  OOJS_PROFILE_ENTER

  ShipEntity* thisEnt = nullptr;
  GET_THIS_SHIP(thisEnt);
  ShipEntity* ship = thisEnt;  // not null: thisEnt is not
  ship->performScriptedAI();

  OOJS_RETURN_VOID;

  OOJS_PROFILE_EXIT
}

static JSValue ShipPerformScriptedAttackAI(OOJS_NATIVE_ARGS) {
  OOJS_PROFILE_ENTER

  ShipEntity* thisEnt = nullptr;
  GET_THIS_SHIP(thisEnt);
  ShipEntity* ship = thisEnt;  // not null: thisEnt is not
  ship->performScriptedAttackAI();

  OOJS_RETURN_VOID;

  OOJS_PROFILE_EXIT
}

static JSValue ShipPerformStop(OOJS_NATIVE_ARGS) {
  OOJS_PROFILE_ENTER

  ShipEntity* thisEnt = nullptr;
  GET_THIS_SHIP(thisEnt);
  ShipEntity* ship = thisEnt;  // not null: thisEnt is not
  ship->performStop();

  OOJS_RETURN_VOID;

  OOJS_PROFILE_EXIT
}

static JSValue ShipPerformTumble(OOJS_NATIVE_ARGS) {
  OOJS_PROFILE_ENTER

  ShipEntity* thisEnt = nullptr;
  GET_THIS_SHIP(thisEnt);
  ShipEntity* ship = thisEnt;  // not null: thisEnt is not
  ship->performTumble();

  OOJS_RETURN_VOID;

  OOJS_PROFILE_EXIT
}

static JSValue ShipRequestDockingInstructions(OOJS_NATIVE_ARGS) {
  OOJS_PROFILE_ENTER

  ShipEntity* thisEnt = nullptr;
  GET_THIS_SHIP(thisEnt);
  ShipEntity* ship = thisEnt;  // not null: thisEnt is not
  ship->requestDockingCoordinates();

  OOJS_RETURN_PLIST(ship->getDockingInstructions());  // nil maps to null

  OOJS_PROFILE_EXIT
}

static JSValue ShipRecallDockingInstructions(OOJS_NATIVE_ARGS) {
  OOJS_PROFILE_ENTER

  ShipEntity* thisEnt = nullptr;
  GET_THIS_SHIP(thisEnt);
  ShipEntity* ship = thisEnt;  // not null: thisEnt is not
  ship->recallDockingInstructions();

  OOJS_RETURN_PLIST(ship->getDockingInstructions());  // nil maps to null

  OOJS_PROFILE_EXIT
}

static JSValue ShipBroadcastDistressMessage(OOJS_NATIVE_ARGS) {
  OOJS_PROFILE_ENTER

  ShipEntity* thisEnt = nullptr;
  GET_THIS_SHIP(thisEnt);
  ShipEntity* ship = thisEnt;  // not null: thisEnt is not
  ship->broadcastDistressMessageWithDumping(false);

  OOJS_RETURN_VOID;

  OOJS_PROFILE_EXIT
}

static JSValue ShipCheckCourseToDestination(OOJS_NATIVE_ARGS) {
  OOJS_PROFILE_ENTER

  ShipEntity* thisEnt = nullptr;
  GET_THIS_SHIP(thisEnt);
  ShipEntity* ship = thisEnt;  // not null: thisEnt is not

  Entity* hazard = (UNIVERSE != nullptr ? UNIVERSE->hazardOnRouteFromEntity(
                                              thisEnt, ship->desiredRange(),
                                              ship->destination())
                                        : nullptr);  // the C++ entities

  OOJS_RETURN(
      OOJSValueFromCxxObject(context, hazard));  // the C++ hazard's JS value

  OOJS_PROFILE_EXIT
}

static JSValue ShipGetSafeCourseToDestination(OOJS_NATIVE_ARGS) {
  OOJS_PROFILE_ENTER

  ShipEntity* thisEnt = nullptr;
  GET_THIS_SHIP(thisEnt);
  ShipEntity* ship = thisEnt;  // not null: thisEnt is not

  HPVector waypoint = (UNIVERSE != nullptr ? UNIVERSE->getSafeVectorFromEntity(
                                                 thisEnt, ship->desiredRange(),
                                                 ship->destination())
                                           : HPVector{});  // the C++ ship

  OOJS_RETURN_HPVECTOR(waypoint);

  OOJS_PROFILE_EXIT
}

static JSValue ShipCheckScanner(OOJS_NATIVE_ARGS) {
  OOJS_PROFILE_ENTER

  ShipEntity* thisEnt = nullptr;
  int onlyCheckPowered = false;

  GET_THIS_SHIP(thisEnt);
  ShipEntity* ship = thisEnt;  // not null: thisEnt is not

  if (argc > 0 && EXPECT_NOT(!((onlyCheckPowered =
                                    JS_ToBool(context, OOJS_ARGV[0])) >= 0))) {
    cxx_OOJSReportBadArguments(context, "Ship", "checkScanner", argc, OOJS_ARGV,
                               std::nullopt, "boolean");
    return OOJSNativeFailure(context);
  }

  if (onlyCheckPowered) {
    ship->checkScannerIgnoringUnpowered();
  } else {
    ship->checkScanner();
  }
  ShipEntity** scannedShips = ship->scannedShips();
  unsigned num = ship->numberOfScannedShips();
  oo::PList::Array scanResult;
  for (unsigned i = 0; i < num; i++) {
    if (scannedShips[i] != nullptr)
      scanResult.push_back(oo::EntityObjectNode(
          scannedShips[i]));  // nil skipped, as a Foundation array skipped it
  }
  OOJS_RETURN_PLIST(oo::PList(std::move(scanResult)));

  OOJS_PROFILE_EXIT
}

static JSValue ShipAdjustCargo(OOJS_NATIVE_ARGS) {
  OOJS_PROFILE_ENTER

  ShipEntity* thisEnt = nullptr;
  std::optional<std::string> commodity;
  int32_t adjustment = 0;

  GET_THIS_SHIP(thisEnt);
  ShipEntity* ship = thisEnt;  // not null: thisEnt is not

  if (argc < 2) {
    cxx_OOJSReportBadArguments(context, "Ship", "adjustCargo", argc, OOJS_ARGV,
                               std::nullopt, "commodity, amount");
    return OOJSNativeFailure(context);
  }

  commodity = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
  if (!OOJSValueToInt32(context, OOJS_ARGV[1], &adjustment)) {
    cxx_OOJSReportBadArguments(context, "Ship", "adjustCargo", argc, OOJS_ARGV,
                               std::nullopt, "commodity, amount");
    return OOJSNativeFailure(context);
  }

  if (ship->cargoType() != OOCargoType::kNotCargo || ship->getIsPlayer()) {
    cxx_OOJSReportError(
        context, "ship.adjustCargo may only be used on NPC cargo carriers");
    return OOJSNativeFailure(context);
  }

  bool ok = true;

  if (adjustment > 0) {
    ok = ship->addCargo(
        (UNIVERSE != nullptr
             ? UNIVERSE->getContainersOfCommodity(commodity.value_or(""),
                                                  adjustment)
             : std::vector<oo::EntityHold>()));  // non-reified templates
  } else if (adjustment < 0) {
    OOCargoQuantity r = static_cast<OOCargoQuantity>(-adjustment);
    ok = ship->removeCargo(commodity.value_or(""), r);
  }

  OOJS_RETURN_BOOL(ok);

  OOJS_PROFILE_EXIT
}

/* 0 = no significant damage or consumable loss, higher numbers mean some */
static JSValue ShipDamageAssessment(OOJS_NATIVE_ARGS) {
  OOJS_PROFILE_ENTER

  ShipEntity* thisEnt = nullptr;
  int assessment = 0;

  GET_THIS_SHIP(thisEnt);
  ShipEntity* ship = thisEnt;  // not null: thisEnt is not

  // if could have missiles but doesn't, consumables low
  if (ship->missileCapacity() > 0 && ship->missilesList().empty()) {
    assessment++;
  }
  // if has injectors but fuel is low, consumables low
  // if no injectors, not a problem
  if (ship->hasFuelInjection() && ship->getFuel() < 35) {
    assessment++;
  }

  /* TODO: when NPC equipment can be damaged in combat, assess this
   * here */

  OOJS_RETURN_INT(assessment);

  OOJS_PROFILE_EXIT
}

static JSValue ShipThreatAssessment(OOJS_NATIVE_ARGS) {
  OOJS_PROFILE_ENTER

  ShipEntity* thisEnt = nullptr;
  int fullCheck = false;

  GET_THIS_SHIP(thisEnt);
  ShipEntity* ship = thisEnt;  // not null: thisEnt is not

  if (argc > 0 &&
      EXPECT_NOT(!((fullCheck = JS_ToBool(context, OOJS_ARGV[0])) >= 0))) {
    cxx_OOJSReportBadArguments(context, "Ship", "threatAssessment", argc,
                               OOJS_ARGV, std::nullopt, "boolean");
    return OOJSNativeFailure(context);
  }
  // start with 2.5 per ship
  double assessment = 2.5;
  // +/- 0.1 for speed, larger subtraction for very slow ships
  GLfloat maxspeed = ship->getMaxFlightSpeed();
  assessment += (maxspeed - 300) / 1000;
  if (maxspeed < 200) {
    assessment += (maxspeed - 200) / 500;
  }

  /* FIXME: at the moment this means NPCs can detect other NPCs shield
   * boosters, since they're implemented as extra energy */
  assessment += (ship->getMaxEnergy() - 200) / 1000;

  // add on some for missiles. Mostly ignore 3rd and subsequent
  // missiles: either they can be ECMd or the first two are already
  // too many.
  if (ship->missileCapacity() > 2) {
    assessment += 0.5;
  } else {
    assessment += (static_cast<double>(ship->missileCapacity())) / 5.0;
  }

  /* Turret count is public knowledge */
  /* TODO: consider making ship combat behaviour try to
   * stay at long range from enemies with turrets. Then
   * we could perhaps reduce this bonus a bit. */
  assessment += ship->turretCount();

  if (fullCheck) {
    // consider pilot skill
    if (ship->getIsPlayer()) {
      double score =
          static_cast<double>(PLAYER != nullptr ? PLAYER->score() : unsigned{});
      if (score > 6400) {
        score = 6400;
      }
      assessment += pow(score, 0.33) / 10;
      // 0 - 1.8
    } else {
      assessment += ship->getAccuracy() / 5;
    }

    // check lasers
    OOWeaponType wt =
        ship->weaponTypeIDForFacing(OOWeaponFacing::kForward, false);
    /* Not affected by multiple mounts here: they're either just a
     * split of the power, or only more dangerous until they
     * overheat */
    assessment += ShipThreatAssessmentWeapon(wt);
    if (isWeaponNone(wt)) {
      assessment -= 1.5;  // further penalty for ships with no forward laser
    }

    wt = ship->weaponTypeIDForFacing(OOWeaponFacing::kAft, false);
    if (!isWeaponNone(wt)) {
      assessment += 1 + ShipThreatAssessmentWeapon(wt);
    }
    // port and starboard weapons less important
    wt = ship->weaponTypeIDForFacing(OOWeaponFacing::kPort, false);
    if (!isWeaponNone(wt)) {
      assessment += 0.2 + ShipThreatAssessmentWeapon(wt) / 5.0;
    }
    wt = ship->weaponTypeIDForFacing(OOWeaponFacing::kStarboard, false);
    if (!isWeaponNone(wt)) {
      assessment += 0.2 + ShipThreatAssessmentWeapon(wt) / 5.0;
    }

    // combat-related secondary equipment
    if (ship->hasECM()) {
      assessment += 0.5;
    }
    if (ship->hasFuelInjection()) {
      assessment += 0.5;
    }

  } else {
    // consider thargoids dangerous
    if (ship->isThargoid()) {
      assessment *= 1.5;
      if (ship->hasRole("thargoid-mothership")) {
        assessment += 5;
      }
    } else {
      // consider that armed ships might have a trick or two
      if (ship->weaponFacings() == 1) {
        assessment += 0.25;
      } else {
        // and more than one trick if they can mount multiple lasers
        assessment += 0.5;
      }
    }
  }

  // mostly ignore fleeing ships as threats
  if (ship->getBehaviour() == OOBehaviour::kFleeTarget ||
      ship->getBehaviour() == OOBehaviour::kFleeEvasiveAction) {
    assessment *= 0.2;
  } else if (ship->getIsPlayer() &&
             (static_cast<PlayerEntity*>(thisEnt) != nullptr
                  ? static_cast<PlayerEntity*>(thisEnt)->fleeingStatus()
                  : OOPlayerFleeingStatus{}) >= OOPlayerFleeingStatus::kCargo) {
    assessment *= 0.2;
  }

  // don't go too low.
  if (assessment < 0.1) {
    assessment = 0.1;
  }

  OOJS_RETURN_DOUBLE(assessment);

  OOJS_PROFILE_EXIT
}

static double ShipThreatAssessmentWeapon(OOWeaponType wt) {
  if (wt == nullptr) {
    return -1.0;
  }
  return wt->weaponThreatAssessment();
}

/** Static methods */

static JSValue ShipStaticKeys(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context);
  OOShipRegistry* registry = OOShipRegistry::sharedRegistry();

  OOJS_RETURN_PLIST(StringArray(registry->shipKeys()));

  OOJS_NATIVE_EXIT
}

static JSValue ShipStaticKeysForRole(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context);
  OOShipRegistry* registry = OOShipRegistry::sharedRegistry();

  if (argc > 0) {
    const std::string role =
        cxx_OOStringFromJSValue(context, OOJS_ARGV[0])
            .value_or(
                std::string());  // nil as "", as the registry bridge sent it
    // null where there is no probability set for the role, as before
    if (registry->probabilitySetForRole(role) == nullptr) OOJS_RETURN_NULL;
    OOJS_RETURN_PLIST(StringArray(registry->shipKeysWithRole(role)));
  } else {
    cxx_OOJSReportBadArguments(context, "Ship", "shipKeysForRole", MIN(argc, 1),
                               OOJS_ARGV, std::nullopt, "ship role");
    return OOJSNativeFailure(context);
  }

  OOJS_NATIVE_EXIT
}

static JSValue ShipStaticRoleIsInCategory(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context);

  if (argc > 1) {
    const std::optional<std::string> role =
        cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
    const std::optional<std::string> category =
        cxx_OOStringFromJSValue(context, OOJS_ARGV[1]);

    OOJS_RETURN_BOOL(role.has_value() && category.has_value() &&
                     (UNIVERSE != nullptr
                          ? UNIVERSE->role(*role, *category)
                          : false));  // a nil role or category matched nothing
  } else {
    cxx_OOJSReportBadArguments(context, "Ship", "roleIsInCategory",
                               MIN(argc, 2), OOJS_ARGV, std::nullopt,
                               "role, category");
    return OOJSNativeFailure(context);
  }

  OOJS_NATIVE_EXIT
}

static JSValue ShipStaticRoles(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context);
  OOShipRegistry* registry = OOShipRegistry::sharedRegistry();

  OOJS_RETURN_PLIST(StringArray(registry->shipRoles()));

  OOJS_NATIVE_EXIT
}

static JSValue ShipStaticShipDataForKey(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context);
  OOShipRegistry* registry = OOShipRegistry::sharedRegistry();

  if (argc > 0) {
    const std::optional<std::string> key =
        cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
    if (!key.has_value()) OOJS_RETURN_NULL;  // a nil key found nothing
    OOJS_RETURN_PLIST(registry->shipInfoForKey(*key));
  } else {
    cxx_OOJSReportBadArguments(context, "Ship", "shipDataForKey", MIN(argc, 1),
                               OOJS_ARGV, std::nullopt, "key");
    return OOJSNativeFailure(context);
  }
  OOJS_NATIVE_EXIT
}

static JSValue ShipStaticSetShipDataForKey(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context);
  OOShipRegistry* registry = OOShipRegistry::sharedRegistry();

  if (argc >= 2) {
    registry->setShipInfoForKey(
        cxx_OOStringFromJSValue(context, OOJS_ARGV[0]).value_or(std::string()),
        cxx_OOJSPListFromJSObject(context, OOJS_ARGV[1]));
    OOJS_RETURN_BOOL(true);
  } else {
    cxx_OOJSReportBadArguments(context, "Ship", "setShipInfoForKey",
                               MIN(argc, 2), OOJS_ARGV, std::nullopt,
                               "key shipdata");
    return OOJSNativeFailure(context);
  }
  OOJS_NATIVE_EXIT
}
