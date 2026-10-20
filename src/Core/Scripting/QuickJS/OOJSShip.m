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

#import "OOJSShip.h"
#import "AI.h"
#import "EntityOOJavaScriptExtensions.h"
#import "OOCharacter.h"
#import "OOCollectionExtractors.h"
#import "OOConstToString.h"
#import "OOEntityFilterPredicate.h"
#import "OOEquipmentType.h"
#import "OOJSEntity.h"
#import "OOJSEquipmentInfo.h"
#import "OOJSPlayer.h"
#import "OOJSQuaternion.h"
#import "OOJSVector.h"
#import "OOJSWormhole.h"
#import "OOJavaScriptEngine.h"
#import "OOMesh.h"
#import "OORoleSet.h"
#import "OOShipGroup.h"
#import "OOShipRegistry.h"
#import "OOStringParsing.h"
#import "PlayerEntity.h"
#import "PlayerEntityScriptMethods.h"
#import "ResourceManager.h"
#import "ShipEntityAI.h"
#import "ShipEntityScriptMethods.h"
#import "StationEntity.h"
#import "WormholeEntity.h"

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

static JSValue RemoveOrExplodeShip(OOJS_NATIVE_ARGS, BOOL explode);
static JSValue ShipSetMaterialsInternal(OOJS_NATIVE_ARGS, ShipEntity* thisEnt, BOOL fromShaders);

static JSValue ShipStaticKeysForRole(OOJS_NATIVE_ARGS);
static JSValue ShipStaticKeys(OOJS_NATIVE_ARGS);
static JSValue ShipStaticRoles(OOJS_NATIVE_ARGS);
static JSValue ShipStaticRoleIsInCategory(OOJS_NATIVE_ARGS);
static JSValue ShipStaticShipDataForKey(OOJS_NATIVE_ARGS);
static JSValue ShipStaticSetShipDataForKey(OOJS_NATIVE_ARGS);

static JSClassDef sShipClass = {
    .class_name = "Ship",
    .finalizer = OOJSObjectWrapperFinalize,
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
enum {
    // Property IDs
    kShip_accuracy = -128, // the ship's accuracy, float, read/write
    kShip_aftWeapon, // the ship's aft weapon, equipmentType, read/write
    kShip_AI, // AI state machine name, string, read-only
    kShip_AIScript, // AI script, Script, read-only
    kShip_AIScriptWakeTime, // next wakeup time, integer, read/write
    kShip_AIState, // AI state machine state, string, read/write
    kShip_AIFoundTarget, // AI "found target", entity, read/write
    kShip_AIPrimaryAggressor, // AI "primary aggressor", entity, read/write
    kShip_alertCondition, // number 0-3, read-only, combat alert level
    kShip_autoAI, // bool, read-only, auto_ai from shipdata
    kShip_autoWeapons, // bool, read-only, auto_weapons from shipdata
    kShip_beaconCode, // beacon code, string, read/write
    kShip_beaconLabel, // beacon label, string, read/write
    kShip_boundingBox, // boundingBox, vector, read-only
    kShip_bounty, // bounty, unsigned int, read/write
    kShip_cargoList, // cargo on board, array of objects, read-only
    kShip_cargoSpaceAvailable, // free cargo space, integer, read-only
    kShip_cargoSpaceCapacity, // maximum cargo, integer, read/write
    kShip_cargoSpaceUsed, // cargo on board, integer, read-only
    kShip_collisionExceptions, // collision exception list, array, read-only
    kShip_contracts, // cargo contracts contracts, array - strings & whatnot, read only
    kShip_commodity, // commodity of a ship, read only
    kShip_commodityAmount, // commodityAmount of a ship, read only
    kShip_cloakAutomatic, // should cloack start by itself or by script, read/write
    kShip_crew, // crew, list, read only
    kShip_cruiseSpeed, // desired cruising speed, number, read only
    kShip_currentWeapon, // the ship's active weapon, equipmentType, read/write
    kShip_dataKey, // string, read-only, shipdata.plist key
    kShip_defenseTargets, // array, read-only, defense targets
    kShip_desiredRange, // desired Range, double, read/write
    kShip_desiredSpeed, // AI desired flight speed, double, read/write
    kShip_destination, // flight destination, Vector, read/write
    kShip_destinationSystem, // destination system, number, read/write
    kShip_displayName, // name displayed on screen, string, read/write
    kShip_dockingInstructions, // name displayed on screen, string, read/write
    kShip_energyRechargeRate, // energy recharge rate, float, read-only
    kShip_entityPersonality, // per-ship random number, int, read-only
    kShip_equipment, // the ship's equipment, array of EquipmentInfo, read only
    kShip_escortGroup, // group, ShipGroup, read-only
    kShip_escorts, // deployed escorts, array of Ship, read-only
    kShip_exhaustEmissiveColor, // exhaust emissive color, array, read/write
    kShip_exhausts, // exhausts, array, read-only
    kShip_extraCargo, // cargo space increase granted by large cargo bay, int, read-only
    kShip_flashers, // flashers, array, read-only
    kShip_forwardWeapon, // the ship's forward weapon, equipmentType, read/write
    kShip_fuel, // fuel, float, read/write
    kShip_fuelChargeRate, // fuel scoop rate & charge multiplier, float, read-only
    kShip_group, // group, ShipGroup, read/write
    kShip_hasHostileTarget, // has hostile target, boolean, read-only
    kShip_hasHyperspaceMotor, // has hyperspace motor, boolean, read-only
    kShip_hasSuspendedAI, // AI has suspended states, boolean, read-only
    kShip_heading, // forwardVector of a ship, read-only
    kShip_heatInsulation, // hull heat insulation, double, read/write
    kShip_homeSystem, // home system, number, read/write
    kShip_hyperspaceSpinTime, // hyperspace spin time, float, read/write
    kShip_injectorBurnRate, // injector burn rate, number, read/write dLY/s
    kShip_injectorSpeedFactor, // injector speed factor, number, read/write
    kShip_isBeacon, // is beacon, boolean, read-only
    kShip_isBoulder, // is a boulder (generates splinters), boolean, read/write
    kShip_isCargo, // contains cargo, boolean, read-only
    kShip_isCloaked, // cloaked, boolean, read/write (if cloaking device installed)
    kShip_isDerelict, // is an abandoned ship, boolean, read-only
    kShip_isFrangible, // frangible, boolean, read-only
    kShip_isFleeing, // is fleeing, boolean, read-only
    kShip_isJamming, // jamming scanners, boolean, read/write (if jammer installed)
    kShip_isMinable, // is a sensible target for mining, boolean, read-only
    kShip_isMine, // is mine, boolean, read-only
    kShip_isMissile, // is missile, boolean, read-only
    kShip_isPiloted, // is piloted, boolean, read-only (includes stations)
    kShip_isPirate, // is pirate, boolean, read-only
    kShip_isPirateVictim, // is pirate victim, boolean, read-only
    kShip_isPolice, // is police, boolean, read-only
    kShip_isRock, // is a rock (hermits included), boolean, read-only
    kShip_isThargoid, // is thargoid, boolean, read-only
    kShip_isTurret, // is turret, boolean, read-only
    kShip_isTrader, // is trader, boolean, read-only
    kShip_isWeapon, // is missile or mine, boolean, read-only
    kShip_laserHeatLevel, // active laser temperature, float, read-only
    kShip_laserHeatLevelAft, // aft laser temperature, float, read-only
    kShip_laserHeatLevelForward, // fore laser temperature, float, read-only
    kShip_laserHeatLevelPort, // port laser temperature, float, read-only
    kShip_laserHeatLevelStarboard, // starboard laser temperature, float, read-only
    kShip_lightsActive, // flasher/shader light flag, boolean, read/write
    kShip_markedForFines, // has been marked for fines
    kShip_maxEscorts, // maximum escort count, int, read/write
    kShip_maxPitch, // maximum flight pitch, double, read-only
    kShip_maxSpeed, // maximum flight speed, double, read-only
    kShip_maxRoll, // maximum flight roll, double, read-only
    kShip_maxYaw, // maximum flight yaw, double, read-only
    kShip_maxThrust, // maximum thrust, double, read-only
    kShip_missileCapacity, // max missiles capacity, integer, read-only
    kShip_missileLoadTime, // missile load time, double, read/write
    kShip_missiles, // the ship's missiles / external storage, array of equipmentTypes, read only
    kShip_name, // name, string, read-only
    kShip_parcelCount, // number of parcels on ship, integer, read-only
    kShip_parcels, // parcel contracts, array - strings & whatnot, read only
    kShip_passengerCapacity, // amount of passenger space on ship, integer, read-only
    kShip_passengerCount, // number of passengers on ship, integer, read-only
    kShip_passengers, // passengers contracts, array - strings & whatnot, read only
    kShip_pitch, // pitch level, float, read-only
    kShip_portWeapon, // the ship's port weapon, equipmentType, read/write
    kShip_potentialCollider, // "proximity alert" ship, Entity, read-only
    kShip_primaryRole, // Primary role, string, read/write
    kShip_reactionTime, // AI reaction time, read/write
    kShip_reportAIMessages, // report AI messages, boolean, read/write
    kShip_roleWeights, // roles and weights, dictionary, read-only
    kShip_roles, // roles, array, read-only
    kShip_roll, // roll level, float, read-only
    kShip_savedCoordinates, // coordinates in system space for AI use, Vector, read/write
    kShip_scanDescription, // STE scan class label, string, read/write
    kShip_scannerDisplayColor1, // color of lollipop shown on scanner, array, read/write
    kShip_scannerDisplayColor2, // color of lollipop shown on scanner when flashing, array, read/write
    kShip_scannerHostileDisplayColor1, // color of lollipop shown on scanner, array, read/write
    kShip_scannerHostileDisplayColor2, // color of lollipop shown on scanner when flashing, array, read/write
    kShip_scannerRange, // scanner range, double, read-only
    kShip_script, // script, Script, read-only
    kShip_scriptedMisjump, // next jump will miss if set to true, boolean, read/write
    kShip_scriptedMisjumpRange, // 0..1 range of next misjump, float, read/write
    kShip_scriptInfo, // arbitrary data for scripts, dictionary, read-only
    kShip_shipClassName, // ship type name, string, read/write
    kShip_shipUniqueName, // uniqish name, string, read/write
    kShip_speed, // current flight speed, double, read-only
    kShip_starboardWeapon, // the ship's starboard weapon, equipmentType, read/write
    kShip_subEntities, // subentities, array of Ship, read-only
    kShip_subEntityCapacity, // max subentities for this ship, int, read-only
    kShip_subEntityRotation, // subentity rotation velocity, quaternion, read/write
    kShip_sunGlareFilter, // sun glare filter multiplier, float, read/write
    kShip_target, // target, Ship, read/write
    kShip_temperature, // hull temperature, double, read/write
    kShip_thrust, // the ship's thrust, double, read/write
    kShip_thrustVector, // thrust-related component of velocity, vector, read-only
    kShip_trackCloseContacts, // generate close contact events, boolean, read/write
    kShip_vectorForward, // forwardVector of a ship, read-only
    kShip_vectorRight, // rightVector of a ship, read-only
    kShip_vectorUp, // upVector of a ship, read-only
    kShip_velocity, // velocity, vector, read/write
    kShip_weaponFacings, // available facings, int, read-only
    kShip_weaponPositionAft, // weapon offset, vector, read-only
    kShip_weaponPositionForward, // weapon offset, vector, read-only
    kShip_weaponPositionPort, // weapon offset, vector, read-only
    kShip_weaponPositionStarboard, // weapon offset, vector, read-only
    kShip_weaponRange, // weapon range, double, read-only
    kShip_withinStationAegis, // within main station aegis, boolean, read/write
    kShip_yaw, // yaw level, float, read-only
};

static const JSCFunctionListEntry sShipProperties[] = {
    // JS name, getter, setter, ID
    OOJS_PROPERTY_RW("accuracy", ShipGetProperty, ShipSetProperty, kShip_accuracy),
    OOJS_PROPERTY_RW("aftWeapon", ShipGetProperty, ShipSetProperty, kShip_aftWeapon),
    OOJS_PROPERTY_RO("AI", ShipGetProperty, kShip_AI),
    OOJS_PROPERTY_RO("AIScript", ShipGetProperty, kShip_AIScript),
    OOJS_PROPERTY_RW("AIScriptWakeTime", ShipGetProperty, ShipSetProperty, kShip_AIScriptWakeTime),
    OOJS_PROPERTY_RW("AIState", ShipGetProperty, ShipSetProperty, kShip_AIState),
    OOJS_PROPERTY_RW("AIFoundTarget", ShipGetProperty, ShipSetProperty, kShip_AIFoundTarget),
    OOJS_PROPERTY_RW("AIPrimaryAggressor", ShipGetProperty, ShipSetProperty, kShip_AIPrimaryAggressor),
    OOJS_PROPERTY_RO("alertCondition", ShipGetProperty, kShip_alertCondition),
    OOJS_PROPERTY_RO("autoAI", ShipGetProperty, kShip_autoAI),
    OOJS_PROPERTY_RO("autoWeapons", ShipGetProperty, kShip_autoWeapons),
    OOJS_PROPERTY_RW("beaconCode", ShipGetProperty, ShipSetProperty, kShip_beaconCode),
    OOJS_PROPERTY_RW("beaconLabel", ShipGetProperty, ShipSetProperty, kShip_beaconLabel),
    OOJS_PROPERTY_RO("boundingBox", ShipGetProperty, kShip_boundingBox),
    OOJS_PROPERTY_RW("bounty", ShipGetProperty, ShipSetProperty, kShip_bounty),
    OOJS_PROPERTY_RO("cargoList", ShipGetProperty, kShip_cargoList),
    OOJS_PROPERTY_RO("cargoSpaceUsed", ShipGetProperty, kShip_cargoSpaceUsed),
    OOJS_PROPERTY_RW("cargoSpaceCapacity", ShipGetProperty, ShipSetProperty, kShip_cargoSpaceCapacity),
    OOJS_PROPERTY_RO("cargoSpaceAvailable", ShipGetProperty, kShip_cargoSpaceAvailable),
    OOJS_PROPERTY_RO("collisionExceptions", ShipGetProperty, kShip_collisionExceptions),
    OOJS_PROPERTY_RO("commodity", ShipGetProperty, kShip_commodity),
    OOJS_PROPERTY_RO("commodityAmount", ShipGetProperty, kShip_commodityAmount),
    // contracts instead of cargo to distinguish them from the manifest
    OOJS_PROPERTY_RO("contracts", ShipGetProperty, kShip_contracts),
    OOJS_PROPERTY_RW("cloakAutomatic", ShipGetProperty, ShipSetProperty, kShip_cloakAutomatic),
    OOJS_PROPERTY_RO("crew", ShipGetProperty, kShip_crew),
    OOJS_PROPERTY_RO("cruiseSpeed", ShipGetProperty, kShip_cruiseSpeed),
    OOJS_PROPERTY_RW("currentWeapon", ShipGetProperty, ShipSetProperty, kShip_currentWeapon),
    OOJS_PROPERTY_RO("dataKey", ShipGetProperty, kShip_dataKey),
    OOJS_PROPERTY_RO("defenseTargets", ShipGetProperty, kShip_defenseTargets),
    OOJS_PROPERTY_RW("desiredRange", ShipGetProperty, ShipSetProperty, kShip_desiredRange),
    OOJS_PROPERTY_RW("desiredSpeed", ShipGetProperty, ShipSetProperty, kShip_desiredSpeed),
    OOJS_PROPERTY_RW("destination", ShipGetProperty, ShipSetProperty, kShip_destination),
    OOJS_PROPERTY_RW("destinationSystem", ShipGetProperty, ShipSetProperty, kShip_destinationSystem),
    OOJS_PROPERTY_RW("displayName", ShipGetProperty, ShipSetProperty, kShip_displayName),
    OOJS_PROPERTY_RO("dockingInstructions", ShipGetProperty, kShip_dockingInstructions),
    OOJS_PROPERTY_RW("energyRechargeRate", ShipGetProperty, ShipSetProperty, kShip_energyRechargeRate),
    OOJS_PROPERTY_RW("entityPersonality", ShipGetProperty, ShipSetProperty, kShip_entityPersonality),
    OOJS_PROPERTY_RO("equipment", ShipGetProperty, kShip_equipment),
    OOJS_PROPERTY_RO("escorts", ShipGetProperty, kShip_escorts),
    OOJS_PROPERTY_RO("escortGroup", ShipGetProperty, kShip_escortGroup),
    OOJS_PROPERTY_RW("exhaustEmissiveColor", ShipGetProperty, ShipSetProperty, kShip_exhaustEmissiveColor),
    OOJS_PROPERTY_RO("exhausts", ShipGetProperty, kShip_exhausts),
    OOJS_PROPERTY_RO("extraCargo", ShipGetProperty, kShip_extraCargo),
    OOJS_PROPERTY_RO("flashers", ShipGetProperty, kShip_flashers),
    OOJS_PROPERTY_RW("forwardWeapon", ShipGetProperty, ShipSetProperty, kShip_forwardWeapon),
    OOJS_PROPERTY_RW("fuel", ShipGetProperty, ShipSetProperty, kShip_fuel),
    OOJS_PROPERTY_RO("fuelChargeRate", ShipGetProperty, kShip_fuelChargeRate),
    OOJS_PROPERTY_RW("group", ShipGetProperty, ShipSetProperty, kShip_group),
    OOJS_PROPERTY_RO("hasHostileTarget", ShipGetProperty, kShip_hasHostileTarget),
    OOJS_PROPERTY_RO("hasHyperspaceMotor", ShipGetProperty, kShip_hasHyperspaceMotor),
    OOJS_PROPERTY_RO("hasSuspendedAI", ShipGetProperty, kShip_hasSuspendedAI),
    OOJS_PROPERTY_RW("heatInsulation", ShipGetProperty, ShipSetProperty, kShip_heatInsulation),
    OOJS_PROPERTY_RO("heading", ShipGetProperty, kShip_heading),
    OOJS_PROPERTY_RW("homeSystem", ShipGetProperty, ShipSetProperty, kShip_homeSystem),
    OOJS_PROPERTY_RW("hyperspaceSpinTime", ShipGetProperty, ShipSetProperty, kShip_hyperspaceSpinTime),
    OOJS_PROPERTY_RW("injectorBurnRate", ShipGetProperty, ShipSetProperty, kShip_injectorBurnRate),
    OOJS_PROPERTY_RW("injectorSpeedFactor", ShipGetProperty, ShipSetProperty, kShip_injectorSpeedFactor),
    OOJS_PROPERTY_RW("homeSystem", ShipGetProperty, ShipSetProperty, kShip_homeSystem),
    OOJS_PROPERTY_RO("isBeacon", ShipGetProperty, kShip_isBeacon),
    OOJS_PROPERTY_RW("isCloaked", ShipGetProperty, ShipSetProperty, kShip_isCloaked),
    OOJS_PROPERTY_RO("isCargo", ShipGetProperty, kShip_isCargo),
    OOJS_PROPERTY_RO("isDerelict", ShipGetProperty, kShip_isDerelict),
    OOJS_PROPERTY_RO("isFrangible", ShipGetProperty, kShip_isFrangible),
    OOJS_PROPERTY_RO("isFleeing", ShipGetProperty, kShip_isFleeing),
    OOJS_PROPERTY_RO("isJamming", ShipGetProperty, kShip_isJamming),
    OOJS_PROPERTY_RO("isMinable", ShipGetProperty, kShip_isMinable),
    OOJS_PROPERTY_RO("isMine", ShipGetProperty, kShip_isMine),
    OOJS_PROPERTY_RO("isMissile", ShipGetProperty, kShip_isMissile),
    OOJS_PROPERTY_RO("isPiloted", ShipGetProperty, kShip_isPiloted),
    OOJS_PROPERTY_RO("isPirate", ShipGetProperty, kShip_isPirate),
    OOJS_PROPERTY_RO("isPirateVictim", ShipGetProperty, kShip_isPirateVictim),
    OOJS_PROPERTY_RO("isPolice", ShipGetProperty, kShip_isPolice),
    OOJS_PROPERTY_RO("isRock", ShipGetProperty, kShip_isRock),
    OOJS_PROPERTY_RW("isBoulder", ShipGetProperty, ShipSetProperty, kShip_isBoulder),
    OOJS_PROPERTY_RO("isThargoid", ShipGetProperty, kShip_isThargoid),
    OOJS_PROPERTY_RO("isTurret", ShipGetProperty, kShip_isTurret),
    OOJS_PROPERTY_RO("isTrader", ShipGetProperty, kShip_isTrader),
    OOJS_PROPERTY_RO("isWeapon", ShipGetProperty, kShip_isWeapon),
    OOJS_PROPERTY_RO("laserHeatLevel", ShipGetProperty, kShip_laserHeatLevel),
    OOJS_PROPERTY_RO("laserHeatLevelAft", ShipGetProperty, kShip_laserHeatLevelAft),
    OOJS_PROPERTY_RO("laserHeatLevelForward", ShipGetProperty, kShip_laserHeatLevelForward),
    OOJS_PROPERTY_RO("laserHeatLevelPort", ShipGetProperty, kShip_laserHeatLevelPort),
    OOJS_PROPERTY_RO("laserHeatLevelStarboard", ShipGetProperty, kShip_laserHeatLevelStarboard),
    OOJS_PROPERTY_RW("lightsActive", ShipGetProperty, ShipSetProperty, kShip_lightsActive),
    OOJS_PROPERTY_RO("markedForFines", ShipGetProperty, kShip_markedForFines),
    OOJS_PROPERTY_RW("maxEscorts", ShipGetProperty, ShipSetProperty, kShip_maxEscorts),
    OOJS_PROPERTY_RW("maxPitch", ShipGetProperty, ShipSetProperty, kShip_maxPitch),
    OOJS_PROPERTY_RW("maxSpeed", ShipGetProperty, ShipSetProperty, kShip_maxSpeed),
    OOJS_PROPERTY_RW("maxRoll", ShipGetProperty, ShipSetProperty, kShip_maxRoll),
    OOJS_PROPERTY_RW("maxYaw", ShipGetProperty, ShipSetProperty, kShip_maxYaw),
    OOJS_PROPERTY_RW("maxThrust", ShipGetProperty, ShipSetProperty, kShip_maxThrust),
    OOJS_PROPERTY_RO("missileCapacity", ShipGetProperty, kShip_missileCapacity),
    OOJS_PROPERTY_RW("missileLoadTime", ShipGetProperty, ShipSetProperty, kShip_missileLoadTime),
    OOJS_PROPERTY_RO("missiles", ShipGetProperty, kShip_missiles),
    OOJS_PROPERTY_RW("name", ShipGetProperty, ShipSetProperty, kShip_name),
    OOJS_PROPERTY_RO("parcelCount", ShipGetProperty, kShip_parcelCount),
    OOJS_PROPERTY_RO("parcels", ShipGetProperty, kShip_parcels),
    OOJS_PROPERTY_RO("passengerCount", ShipGetProperty, kShip_passengerCount),
    OOJS_PROPERTY_RO("passengerCapacity", ShipGetProperty, kShip_passengerCapacity),
    OOJS_PROPERTY_RO("passengers", ShipGetProperty, kShip_passengers),
    OOJS_PROPERTY_RO("pitch", ShipGetProperty, kShip_pitch),
    OOJS_PROPERTY_RW("portWeapon", ShipGetProperty, ShipSetProperty, kShip_portWeapon),
    OOJS_PROPERTY_RO("potentialCollider", ShipGetProperty, kShip_potentialCollider),
    OOJS_PROPERTY_RW("primaryRole", ShipGetProperty, ShipSetProperty, kShip_primaryRole),
    OOJS_PROPERTY_RW("reactionTime", ShipGetProperty, ShipSetProperty, kShip_reactionTime),
    OOJS_PROPERTY_RW("reportAIMessages", ShipGetProperty, ShipSetProperty, kShip_reportAIMessages),
    OOJS_PROPERTY_RO("roleWeights", ShipGetProperty, kShip_roleWeights),
    OOJS_PROPERTY_RO("roles", ShipGetProperty, kShip_roles),
    OOJS_PROPERTY_RO("roll", ShipGetProperty, kShip_roll),
    OOJS_PROPERTY_RW("savedCoordinates", ShipGetProperty, ShipSetProperty, kShip_savedCoordinates),
    OOJS_PROPERTY_RW("scanDescription", ShipGetProperty, ShipSetProperty, kShip_scanDescription),
    OOJS_PROPERTY_RW("scannerDisplayColor1", ShipGetProperty, ShipSetProperty, kShip_scannerDisplayColor1),
    OOJS_PROPERTY_RW("scannerDisplayColor2", ShipGetProperty, ShipSetProperty, kShip_scannerDisplayColor2),
    OOJS_PROPERTY_RW("scannerHostileDisplayColor1", ShipGetProperty, ShipSetProperty, kShip_scannerHostileDisplayColor1),
    OOJS_PROPERTY_RW("scannerHostileDisplayColor2", ShipGetProperty, ShipSetProperty, kShip_scannerHostileDisplayColor2),
    OOJS_PROPERTY_RO("scannerRange", ShipGetProperty, kShip_scannerRange),
    OOJS_PROPERTY_RO("script", ShipGetProperty, kShip_script),
    OOJS_PROPERTY_RW("scriptedMisjump", ShipGetProperty, ShipSetProperty, kShip_scriptedMisjump),
    OOJS_PROPERTY_RW("scriptedMisjumpRange", ShipGetProperty, ShipSetProperty, kShip_scriptedMisjumpRange),
    OOJS_PROPERTY_RO("scriptInfo", ShipGetProperty, kShip_scriptInfo),
    OOJS_PROPERTY_RW("shipClassName", ShipGetProperty, ShipSetProperty, kShip_shipClassName),
    OOJS_PROPERTY_RW("shipUniqueName", ShipGetProperty, ShipSetProperty, kShip_shipUniqueName),
    OOJS_PROPERTY_RO("speed", ShipGetProperty, kShip_speed),
    OOJS_PROPERTY_RW("starboardWeapon", ShipGetProperty, ShipSetProperty, kShip_starboardWeapon),
    OOJS_PROPERTY_RO("subEntities", ShipGetProperty, kShip_subEntities),
    OOJS_PROPERTY_RO("subEntityCapacity", ShipGetProperty, kShip_subEntityCapacity),
    OOJS_PROPERTY_RW("subEntityRotation", ShipGetProperty, ShipSetProperty, kShip_subEntityRotation),
    OOJS_PROPERTY_RW("sunGlareFilter", ShipGetProperty, ShipSetProperty, kShip_sunGlareFilter),
    OOJS_PROPERTY_RW("target", ShipGetProperty, ShipSetProperty, kShip_target),
    OOJS_PROPERTY_RW("temperature", ShipGetProperty, ShipSetProperty, kShip_temperature),
    OOJS_PROPERTY_RW("thrust", ShipGetProperty, ShipSetProperty, kShip_thrust),
    OOJS_PROPERTY_RO("thrustVector", ShipGetProperty, kShip_thrustVector),
    OOJS_PROPERTY_RW("trackCloseContacts", ShipGetProperty, ShipSetProperty, kShip_trackCloseContacts),
    OOJS_PROPERTY_RO("vectorForward", ShipGetProperty, kShip_vectorForward),
    OOJS_PROPERTY_RO("vectorRight", ShipGetProperty, kShip_vectorRight),
    OOJS_PROPERTY_RO("vectorUp", ShipGetProperty, kShip_vectorUp),
    OOJS_PROPERTY_RW("velocity", ShipGetProperty, ShipSetProperty, kShip_velocity),
    OOJS_PROPERTY_RO("weaponFacings", ShipGetProperty, kShip_weaponFacings),
    OOJS_PROPERTY_RO("weaponPositionAft", ShipGetProperty, kShip_weaponPositionAft),
    OOJS_PROPERTY_RO("weaponPositionForward", ShipGetProperty, kShip_weaponPositionForward),
    OOJS_PROPERTY_RO("weaponPositionPort", ShipGetProperty, kShip_weaponPositionPort),
    OOJS_PROPERTY_RO("weaponPositionStarboard", ShipGetProperty, kShip_weaponPositionStarboard),
    OOJS_PROPERTY_RO("weaponRange", ShipGetProperty, kShip_weaponRange),
    OOJS_PROPERTY_RO("withinStationAegis", ShipGetProperty, kShip_withinStationAegis),
    OOJS_PROPERTY_RO("yaw", ShipGetProperty, kShip_yaw),
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
    JS_CFUNC_DEF("getSafeCourseToDestination", 0, ShipGetSafeCourseToDestination),
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
    JS_CFUNC_DEF("performFlyToRangeFromDestination", 0, ShipPerformFlyToRangeFromDestination),
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
    JS_CFUNC_DEF("requestDockingInstructions", 0, ShipRequestDockingInstructions),
    JS_CFUNC_DEF("recallDockingInstructions", 0, ShipRecallDockingInstructions),
    JS_CFUNC_DEF("restoreSubEntities", 0, ShipRestoreSubEntities),
    JS_CFUNC_DEF("__runLegacyScriptActions", 2, ShipRunLegacyScriptActions), // Deliberately not documented
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

DEFINE_JS_OBJECT_GETTER(JSShipGetShipEntity, sShipClassID, ShipEntity)

void InitOOJSShip(JSContext* context, JSValueConst global)
{
    OOJSRegisterClass(&sShipClassID, &sShipClass);

    JSValue entityPrototype = JS_GetClassProto(context, JSEntityClassID());
    OOJSInitClass(context, global, sShipClassID, entityPrototype, OOJSUnconstructableConstruct, 0,
        sShipProperties, OOJS_COUNT(sShipProperties), sShipMethods, OOJS_COUNT(sShipMethods),
        sShipStaticMethods, OOJS_COUNT(sShipStaticMethods));
    JS_FreeValue(context, entityPrototype);

    OOJSRegisterObjectConverter(sShipClassID, OOJSBasicPrivateObjectConverter);
    OOJSRegisterSubclass(sShipClassID, JSEntityClassID());
}

JSClassID JSShipClassID(void)
{
    return sShipClassID;
}

static JSValue ShipGetProperty(OOJS_GETTER_ARGS)
{

    OOJS_NATIVE_ENTER(context)

    ShipEntity* entity = nil;
    id result = nil;

    if (EXPECT_NOT(!JSShipGetShipEntity(context, this, &entity)))
        return OOJSNativeFailure(context);
    if (OOIsStaleEntity(entity)) {
        return JS_UNDEFINED;
    }

    switch (magic) {
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

    case kShip_scanDescription:
        result = [entity scanDescriptionForScripting];
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
        return JS_NewNumber(context, [entity realAlertCondition]);

    case kShip_autoAI:
        return OOJSValueFromBOOL([entity hasAutoAI]);

    case kShip_autoWeapons:
        return OOJSValueFromBOOL([entity hasAutoWeapons]);

    case kShip_accuracy:
        return JS_NewNumber(context, [entity accuracy]);

    case kShip_fuel:
        return JS_NewNumber(context, [entity fuel] * 0.1);

    case kShip_fuelChargeRate:
        return JS_NewNumber(context, [entity fuelChargeRate]);

    case kShip_bounty:
        return JS_NewNumber(context, [entity bounty]);

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
        return JS_NewNumber(context, [entity maxShipSubEntities]);

    case kShip_subEntityRotation:
        OOJS_RETURN_QUATERNION([entity subEntityRotationalVelocity]);

    case kShip_hasSuspendedAI:
        return OOJSValueFromBOOL([[entity getAI] hasSuspendedStateMachines]);

    case kShip_target:
        result = [entity primaryTarget];
        break;

    case kShip_defenseTargets: {
        [entity validateDefenseTargets];
        result = [NSMutableArray arrayWithCapacity:[entity defenseTargetCount]];
        NSEnumerator* defTargets = [entity defenseTargetEnumerator];
        Entity* target = nil;
        while ((target = [[defTargets nextObject] weakRefUnderlyingObject])) {
            [result addObject:target];
        }
        break;
    }

    case kShip_crew:
        result = [entity crewForScripting];
        break;

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
        return JS_NewNumber(context, [entity temperature] / SHIP_MAX_CABIN_TEMP);

    case kShip_heatInsulation:
        return JS_NewNumber(context, [entity heatInsulation]);

    case kShip_heading:
        OOJS_RETURN_VECTOR([entity forwardVector]);

    case kShip_energyRechargeRate:
        return JS_NewNumber(context, [entity energyRechargeRate]);

    case kShip_entityPersonality:
        return JS_NewInt32(context, [entity entityPersonalityInt]);

    case kShip_isBeacon:
        return OOJSValueFromBOOL([entity isBeacon]);

    case kShip_beaconCode:
        result = [entity beaconCode];
        break;

    case kShip_beaconLabel:
        result = [entity beaconLabel];
        break;

    case kShip_isFrangible:
        return OOJSValueFromBOOL([entity isFrangible]);

    case kShip_isCloaked:
        return OOJSValueFromBOOL([entity isCloaked]);

    case kShip_cloakAutomatic:
        return OOJSValueFromBOOL([entity hasAutoCloak]);

    case kShip_isJamming:
        return OOJSValueFromBOOL([entity isJammingScanning]);

    case kShip_potentialCollider:
        result = [entity proximityAlert];
        break;

    case kShip_hasHostileTarget:
        return OOJSValueFromBOOL([entity hasHostileTarget]);

    case kShip_hasHyperspaceMotor:
        return OOJSValueFromBOOL([entity hasHyperspaceMotor]);

    case kShip_hyperspaceSpinTime:
        return JS_NewNumber(context, [entity hyperspaceSpinTime]);

    case kShip_weaponRange:
        return JS_NewNumber(context, [entity weaponRange]);

    case kShip_weaponFacings:
        if ([entity isPlayer]) {
            PlayerEntity* pent = (PlayerEntity*)entity;
            return JS_NewNumber(context, [pent availableFacings]);
        }
        return JS_NewNumber(context, [entity weaponFacings]);

    case kShip_weaponPositionAft:
        result = [entity aftWeaponOffset];
        break;

    case kShip_weaponPositionForward:
        result = [entity forwardWeaponOffset];
        break;
        //			OOJS_RETURN_VECTOR([entity forwardWeaponOffset]);

    case kShip_weaponPositionPort:
        result = [entity portWeaponOffset];
        break;

    case kShip_weaponPositionStarboard:
        result = [entity starboardWeaponOffset];
        break;

    case kShip_scannerRange:
        return JS_NewNumber(context, [entity scannerRange]);

    case kShip_reactionTime:
        return JS_NewNumber(context, [entity reactionTime]);

    case kShip_reportAIMessages:
        return OOJSValueFromBOOL([entity reportAIMessages]);

    case kShip_withinStationAegis:
        return OOJSValueFromBOOL([entity withinStationAegis]);

    case kShip_cargoSpaceCapacity:
        return JS_NewInt32(context, [entity maxAvailableCargoSpace]);

    case kShip_cargoSpaceUsed:
        return JS_NewInt32(context, [entity maxAvailableCargoSpace] - [entity availableCargoSpace]);

    case kShip_cargoSpaceAvailable:
        return JS_NewInt32(context, [entity availableCargoSpace]);

    case kShip_cargoList:
        result = [entity cargoListForScripting];
        break;

    case kShip_extraCargo:
        return JS_NewNumber(context, [entity extraCargo]);

    case kShip_commodity:
        if ([entity commodityAmount] > 0) {
            result = [entity commodityType];
        }
        break;

    case kShip_commodityAmount:
        return JS_NewInt32(context, [entity commodityAmount]);

    case kShip_collisionExceptions:
        result = [entity collisionExceptions];
        break;

    case kShip_speed:
        return JS_NewNumber(context, [entity flightSpeed]);

    case kShip_cruiseSpeed:
        return JS_NewNumber(context, [entity cruiseSpeed]);

    case kShip_dataKey:
        result = [entity shipDataKey];
        break;

    case kShip_desiredRange:
        return JS_NewNumber(context, [entity desiredRange]);

    case kShip_desiredSpeed:
        return JS_NewNumber(context, [entity desiredSpeed]);

    case kShip_destination:
        OOJS_RETURN_HPVECTOR([entity destination]);

    case kShip_markedForFines:
        return OOJSValueFromBOOL([entity markedForFines]);

    case kShip_maxEscorts:
        return JS_NewNumber(context, [entity maxEscortCount]);

    case kShip_maxPitch:
        return JS_NewNumber(context, [entity maxFlightPitch]);

    case kShip_maxSpeed:
        return JS_NewNumber(context, [entity maxFlightSpeed]);

    case kShip_maxRoll:
        return JS_NewNumber(context, [entity maxFlightRoll]);

    case kShip_maxYaw:
        return JS_NewNumber(context, [entity maxFlightYaw]);

    case kShip_injectorBurnRate:
        return JS_NewNumber(context, [entity afterburnerRate]);

    case kShip_injectorSpeedFactor:
        return JS_NewNumber(context, [entity afterburnerFactor]);

    case kShip_script:
        result = [entity shipScript];
        break;

    case kShip_AIScript:
        result = [entity shipAIScript];
        break;

    case kShip_AIScriptWakeTime:
        return JS_NewNumber(context, [entity shipAIScriptWakeTime]);
        break;

    case kShip_destinationSystem:
        return JS_NewNumber(context, [entity destinationSystem]);
        break;

    case kShip_homeSystem:
        return JS_NewNumber(context, [entity homeSystem]);
        break;

    case kShip_isPirate:
        return OOJSValueFromBOOL([entity isPirate]);

    case kShip_isPolice:
        return OOJSValueFromBOOL([entity isPolice]);

    case kShip_isThargoid:
        return OOJSValueFromBOOL([entity isThargoid]);

    case kShip_isTurret:
        return OOJSValueFromBOOL([entity isTurret]);

    case kShip_isTrader:
        return OOJSValueFromBOOL([entity isTrader]);

    case kShip_isPirateVictim:
        return OOJSValueFromBOOL([entity isPirateVictim]);

    case kShip_isMissile:
        return OOJSValueFromBOOL([entity isMissile]);

    case kShip_isMine:
        return OOJSValueFromBOOL([entity isMine]);

    case kShip_isWeapon:
        return OOJSValueFromBOOL([entity isWeapon]);

    case kShip_isRock:
        return OOJSValueFromBOOL([entity scanClass] == CLASS_ROCK); // hermits and asteroids!

    case kShip_isMinable:
        return OOJSValueFromBOOL([entity isMinable]);

    case kShip_isBoulder:
        return OOJSValueFromBOOL([entity isBoulder]);

    case kShip_isFleeing:
        if ([entity isPlayer]) {
            return OOJSValueFromBOOL([(PlayerEntity*)entity fleeingStatus] >= PLAYER_FLEEING_CARGO);
        } else {
            return OOJSValueFromBOOL([entity behaviour] == BEHAVIOUR_FLEE_TARGET || [entity behaviour] == BEHAVIOUR_FLEE_EVASIVE_ACTION);
        }

    case kShip_isCargo:
        return OOJSValueFromBOOL([entity scanClass] == CLASS_CARGO && [entity commodityAmount] > 0);

    case kShip_isDerelict:
        return OOJSValueFromBOOL([entity isHulk]);

    case kShip_isPiloted:
        return OOJSValueFromBOOL([entity isPlayer] || [[entity crew] count] > 0);

    case kShip_scriptedMisjump:
        return OOJSValueFromBOOL([entity scriptedMisjump]);

    case kShip_scriptedMisjumpRange:
        return JS_NewNumber(context, [entity scriptedMisjumpRange]);

    case kShip_scriptInfo:
        result = [entity scriptInfo];
        if (result == nil)
            result = [NSDictionary dictionary]; // empty rather than null
        break;

    case kShip_sunGlareFilter:
        return JS_NewNumber(context, [entity sunGlareFilter]);

    case kShip_trackCloseContacts:
        return OOJSValueFromBOOL([entity trackCloseContacts]);

    case kShip_passengerCount:
        return JS_NewNumber(context, [entity passengerCount]);

    case kShip_parcelCount:
        return JS_NewNumber(context, [entity parcelCount]);

    case kShip_passengerCapacity:
        return JS_NewNumber(context, [entity passengerCapacity]);

    case kShip_missileCapacity:
        return JS_NewNumber(context, [entity missileCapacity]);

    case kShip_missileLoadTime:
        return JS_NewNumber(context, [entity missileLoadTime]);

    case kShip_savedCoordinates:
        OOJS_RETURN_HPVECTOR([entity coordinates]);

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
        return JS_NewNumber(context, [entity laserHeatLevel]);

    case kShip_laserHeatLevelAft:
        return JS_NewNumber(context, [entity laserHeatLevelAft]);

    case kShip_laserHeatLevelForward:
        return JS_NewNumber(context, [entity laserHeatLevelForward]);

    case kShip_laserHeatLevelPort:
        return JS_NewNumber(context, [entity laserHeatLevelPort]);

    case kShip_laserHeatLevelStarboard:
        return JS_NewNumber(context, [entity laserHeatLevelStarboard]);

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

    case kShip_scannerHostileDisplayColor1:
        result = [[entity scannerDisplayColorHostile1] normalizedArray];
        break;

    case kShip_scannerHostileDisplayColor2:
        result = [[entity scannerDisplayColorHostile2] normalizedArray];
        break;

    case kShip_exhaustEmissiveColor:
        result = [[entity exhaustEmissiveColor] normalizedArray];
        break;

    case kShip_maxThrust:
        return JS_NewNumber(context, [entity maxThrust]);

    case kShip_thrust:
        return JS_NewNumber(context, [entity thrust]);

    case kShip_lightsActive:
        return OOJSValueFromBOOL([entity lightsActive]);

    case kShip_vectorRight:
        OOJS_RETURN_VECTOR([entity rightVector]);

    case kShip_vectorForward:
        OOJS_RETURN_VECTOR([entity forwardVector]);

    case kShip_vectorUp:
        OOJS_RETURN_VECTOR([entity upVector]);

    case kShip_velocity:
        OOJS_RETURN_VECTOR([entity velocity]);

    case kShip_thrustVector:
        OOJS_RETURN_VECTOR([entity thrustVector]);

    case kShip_pitch:
        return JS_NewNumber(context, [entity flightPitch]);

    case kShip_roll:
        return JS_NewNumber(context, [entity flightRoll]);

    case kShip_yaw:
        return JS_NewNumber(context, [entity flightYaw]);

    case kShip_boundingBox: {
        Vector bbvect;
        BoundingBox box;

        if ([entity isSubEntity]) {
            box = [entity boundingBox];
        } else {
            box = [entity totalBoundingBox];
        }
        bounding_box_get_dimensions(box, &bbvect.x, &bbvect.y, &bbvect.z);
        OOJS_RETURN_VECTOR(bbvect);
    }

    default:
        OOJSReportBadPropertySelector(context, this, magic, sShipProperties, OOJS_COUNT(sShipProperties));
        return OOJSNativeFailure(context);
    }

    return OOJSValueFromNativeObject(context, result);

    OOJS_NATIVE_EXIT
}

static JSValue ShipSetProperty(OOJS_SETTER_ARGS)
{

    OOJS_NATIVE_ENTER(context)

    ShipEntity* entity = nil;
    ShipEntity* target = nil;
    NSString* sValue = nil;
    double fValue;
    int32_t iValue;
    int bValue;
    Vector vValue;
    Quaternion qValue;
    HPVector hpvValue;
    OOShipGroup* group = nil;
    OOColor* colorForScript = nil;
    BOOL exists;

    if (EXPECT_NOT(!JSShipGetShipEntity(context, this, &entity)))
        return OOJSNativeFailure(context);
    if (OOIsStaleEntity(entity))
        return JS_UNDEFINED;

    NSCAssert(![entity isTemplateCargoPod], @"-OOJSShip: a template cargo pod has become accessible to Javascript");

    switch (magic) {
    case kShip_name:
        if (EXPECT_NOT([entity isPlayer]))
            goto playerReadOnly;

        sValue = OOStringFromJSValue(context, value);
        if (sValue != nil) {
            [entity setName:sValue];
            return JS_UNDEFINED;
        }
        break;

    case kShip_displayName:
        if (EXPECT_NOT([entity isPlayer]))
            goto playerReadOnly;

        sValue = OOStringFromJSValue(context, value);
        if (sValue != nil) {
            [entity setDisplayName:sValue];
            return JS_UNDEFINED;
        }
        break;

    case kShip_shipUniqueName:
        sValue = OOStringFromJSValue(context, value);
        if (sValue != nil) {
            [entity setShipUniqueName:sValue];
            return JS_UNDEFINED;
        }
        break;

    case kShip_shipClassName:
        sValue = OOStringFromJSValue(context, value);
        if (sValue != nil) {
            [entity setShipClassName:sValue];
            return JS_UNDEFINED;
        }
        break;

    case kShip_scanDescription:
        sValue = OOStringFromJSValue(context, value);
        // can set to nil
        [entity setScanDescription:sValue];
        return JS_UNDEFINED;

    case kShip_primaryRole:
        if (EXPECT_NOT([entity isPlayer]))
            goto playerReadOnly;

        sValue = OOStringFromJSValue(context, value);
        if (sValue != nil) {
            [entity setPrimaryRole:sValue];
            return JS_UNDEFINED;
        }
        break;

    case kShip_AIState:
        if (EXPECT_NOT([entity isPlayer]))
            goto playerReadOnly;

        sValue = OOStringFromJSValue(context, value);
        if (sValue != nil) {
            [[entity getAI] setState:sValue];
            return JS_UNDEFINED;
        }
        break;

    case kShip_beaconCode:
        if (EXPECT_NOT([entity isPlayer]))
            goto playerReadOnly;

        sValue = OOStringFromJSValue(context, value);
        if ([sValue length] == 0) {
            if ([entity isBeacon]) {
                [UNIVERSE clearBeacon:entity];
                if ([PLAYER nextBeacon] == entity) {
                    [PLAYER setCompassMode:COMPASS_MODE_PLANET];
                }
            }
        } else {
            if ([entity isBeacon]) {
                [entity setBeaconCode:sValue];
            } else // Universe needs to update beacon lists in this case only
            {
                [entity setBeaconCode:sValue];
                [UNIVERSE setNextBeacon:entity];
            }
        }
        return JS_UNDEFINED;
        break;

    case kShip_beaconLabel:
        if (EXPECT_NOT([entity isPlayer]))
            goto playerReadOnly;
        sValue = OOStringFromJSValue(context, value);
        if (sValue != nil) {
            [entity setBeaconLabel:sValue];
            return JS_UNDEFINED;
        }
        break;

    case kShip_accuracy:
        if (EXPECT_NOT([entity isPlayer]))
            goto playerReadOnly;

        if ((JS_ToFloat64(context, &fValue, value) == 0)) {
            [entity setAccuracy:fValue];
            return JS_UNDEFINED;
        }
        break;

    case kShip_fuel:
        if ((JS_ToFloat64(context, &fValue, value) == 0)) {
            fValue = OOClamp_0_max_d(fValue, MAX_JUMP_RANGE);
            [entity setFuel:lround(fValue * 10.0)];
            return JS_UNDEFINED;
        }
        break;

    case kShip_entityPersonality:
        if (OOJSValueToInt32(context, value, &iValue)) {
            if (iValue < 0 || iValue > (int32_t)ENTITY_PERSONALITY_MAX) {
                OOJSReportError(context, @"ship.%@ must be >= 0 and <= %u.", OOStringFromJSPropertyMagic(magic, sShipProperties, OOJS_COUNT(sShipProperties)), ENTITY_PERSONALITY_MAX);
                return OOJSNativeFailure(context);
            }
            [entity setEntityPersonalityInt:iValue];
            return JS_UNDEFINED;
        }

    case kShip_hyperspaceSpinTime:
        if ((JS_ToFloat64(context, &fValue, value) == 0)) {
            [entity setHyperspaceSpinTime:fValue];
            return JS_UNDEFINED;
        }
        break;

    case kShip_bounty:
        if (OOJSValueToInt32(context, value, &iValue)) {
            if (iValue < 0)
                iValue = 0;
            [entity setBounty:iValue withReason:kOOLegalStatusReasonByScript];
            return JS_UNDEFINED;
        }
        break;

    case kShip_cargoSpaceCapacity:
        if (OOJSValueToInt32(context, value, &iValue)) {
            if (iValue < 0)
                iValue = 0;
            // OXPs using equipment with weight requirements may make us end up with more allocated
            // cargo space than what we have available. Do not let iValue become negative.
            if ([entity maxAvailableCargoSpace] < [entity availableCargoSpace]) {
                iValue = 0;
            } else if ((OOCargoQuantity)iValue < [entity maxAvailableCargoSpace] - [entity availableCargoSpace]) {
                iValue = [entity maxAvailableCargoSpace] - [entity availableCargoSpace];
            }
            [entity setMaxAvailableCargoSpace:iValue];
            return JS_UNDEFINED;
        }
        break;

    case kShip_destinationSystem:
        if (OOJSValueToInt32(context, value, &iValue)) {
            if (iValue < 0)
                iValue = 0;
            [entity setDestinationSystem:iValue];
            return JS_UNDEFINED;
        }
        break;

    case kShip_homeSystem:
        if (OOJSValueToInt32(context, value, &iValue)) {
            if (iValue < 0)
                iValue = 0;
            [entity setHomeSystem:iValue];
            return JS_UNDEFINED;
        }
        break;

    case kShip_target:
        if (JS_IsNull(value)) {
            [entity setTargetForScript:nil];
            return JS_UNDEFINED;
        } else if (JSValueToEntity(context, value, &target) && [target isKindOfClass:[ShipEntity class]]) {
            [entity setTargetForScript:target];
            return JS_UNDEFINED;
        }
        break;

    case kShip_AIFoundTarget:
        if (EXPECT_NOT([entity isPlayer]))
            goto playerReadOnly;

        if (JS_IsNull(value)) {
            [entity setFoundTarget:nil];
            return JS_UNDEFINED;
        } else if (JSValueToEntity(context, value, &target) && [target isKindOfClass:[ShipEntity class]]) {
            [entity setFoundTarget:target];
            return JS_UNDEFINED;
        }
        break;

    case kShip_AIPrimaryAggressor:
        if (EXPECT_NOT([entity isPlayer]))
            goto playerReadOnly;

        if (JS_IsNull(value)) {
            [entity setPrimaryAggressor:nil];
            return JS_UNDEFINED;
        } else if (JSValueToEntity(context, value, &target) && [target isKindOfClass:[ShipEntity class]]) {
            [entity setPrimaryAggressor:target];
            return JS_UNDEFINED;
        }
        break;

    case kShip_group:
        group = OOJSNativeObjectOfClassFromJSValue(context, value, [OOShipGroup class]);
        if (group != nil || JS_IsNull(value)) {
            [entity setGroup:group];
            return JS_UNDEFINED;
        }
        break;

    case kShip_AIScriptWakeTime:
        if ((JS_ToFloat64(context, &fValue, value) == 0)) {
            [entity setAIScriptWakeTime:fValue];
            return JS_UNDEFINED;
        }
        break;

    case kShip_temperature:
        if ((JS_ToFloat64(context, &fValue, value) == 0)) {
            fValue = fmax(fValue, 0.0);
            [entity setTemperature:fValue * SHIP_MAX_CABIN_TEMP];
            return JS_UNDEFINED;
        }
        break;

    case kShip_heatInsulation:
        if ((JS_ToFloat64(context, &fValue, value) == 0)) {
            fValue = fmax(fValue, 0.125);
            [entity setHeatInsulation:fValue];
            return JS_UNDEFINED;
        }
        break;

    case kShip_isCloaked:
        if (((bValue = JS_ToBool(context, value)) >= 0)) {
            [entity setCloaked:bValue];
            return JS_UNDEFINED;
        }
        break;

    case kShip_cloakAutomatic:
        if (((bValue = JS_ToBool(context, value)) >= 0)) {
            [entity setAutoCloak:bValue];
            return JS_UNDEFINED;
        }
        break;

    case kShip_missileLoadTime:
        if ((JS_ToFloat64(context, &fValue, value) == 0)) {
            [entity setMissileLoadTime:fmax(0.0, fValue)];
            return JS_UNDEFINED;
        }
        break;

    case kShip_reactionTime:
        if (EXPECT_NOT([entity isPlayer]))
            goto playerReadOnly;

        if ((JS_ToFloat64(context, &fValue, value) == 0)) {
            [entity setReactionTime:fValue];
            return JS_UNDEFINED;
        }
        break;

    case kShip_reportAIMessages:
        if (((bValue = JS_ToBool(context, value)) >= 0)) {
            [entity setReportAIMessages:bValue];
            return JS_UNDEFINED;
        }
        break;

    case kShip_trackCloseContacts:
        if (((bValue = JS_ToBool(context, value)) >= 0)) {
            [entity setTrackCloseContacts:bValue];
            return JS_UNDEFINED;
        }
        break;

    case kShip_isBoulder:
        if (EXPECT_NOT([entity isPlayer]))
            goto playerReadOnly;

        if (((bValue = JS_ToBool(context, value)) >= 0)) {
            [entity setIsBoulder:bValue];
            return JS_UNDEFINED;
        }
        break;

    case kShip_destination:
        if (EXPECT_NOT([entity isPlayer]))
            goto playerReadOnly;

        if (JSValueToHPVector(context, value, &hpvValue)) {
            // use setEscortDestination rather than setDestination as
            // scripted amendments shouldn't necessarily reset frustration
            [entity setEscortDestination:hpvValue];
            return JS_UNDEFINED;
        }
        break;

    case kShip_desiredSpeed:
        if (EXPECT_NOT([entity isPlayer]))
            goto playerReadOnly;

        if ((JS_ToFloat64(context, &fValue, value) == 0)) {
            [entity setDesiredSpeed:fmax(fValue, 0.0)];
            return JS_UNDEFINED;
        }
        break;

    case kShip_desiredRange:
        if (EXPECT_NOT([entity isPlayer]))
            goto playerReadOnly;

        if ((JS_ToFloat64(context, &fValue, value) == 0)) {
            [entity setDesiredRange:fmax(fValue, 0.0)];
            return JS_UNDEFINED;
        }
        break;

    case kShip_savedCoordinates:
        if (JSValueToHPVector(context, value, &hpvValue)) {
            [entity setCoordinate:hpvValue];
            return JS_UNDEFINED;
        }
        break;

    case kShip_scannerDisplayColor1:
        colorForScript = [OOColor colorWithDescription:OOJSNativeObjectFromJSValue(context, value)];
        if (colorForScript != nil || JS_IsNull(value)) {
            [entity setScannerDisplayColor1:colorForScript];
            return JS_UNDEFINED;
        }
        break;

    case kShip_scannerDisplayColor2:
        colorForScript = [OOColor colorWithDescription:OOJSNativeObjectFromJSValue(context, value)];
        if (colorForScript != nil || JS_IsNull(value)) {
            [entity setScannerDisplayColor2:colorForScript];
            return JS_UNDEFINED;
        }
        break;

    case kShip_scannerHostileDisplayColor1:
        colorForScript = [OOColor colorWithDescription:OOJSNativeObjectFromJSValue(context, value)];
        if (colorForScript != nil || JS_IsNull(value)) {
            [entity setScannerDisplayColorHostile1:colorForScript];
            return JS_UNDEFINED;
        }
        break;

    case kShip_scannerHostileDisplayColor2:
        colorForScript = [OOColor colorWithDescription:OOJSNativeObjectFromJSValue(context, value)];
        if (colorForScript != nil || JS_IsNull(value)) {
            [entity setScannerDisplayColorHostile2:colorForScript];
            return JS_UNDEFINED;
        }
        break;

    case kShip_exhaustEmissiveColor:
        colorForScript = [OOColor colorWithDescription:OOJSNativeObjectFromJSValue(context, value)];
        if (colorForScript != nil || JS_IsNull(value)) {
            [entity setExhaustEmissiveColor:colorForScript];
            return JS_UNDEFINED;
        }
        break;

    case kShip_scriptedMisjump:
        if (((bValue = JS_ToBool(context, value)) >= 0)) {
            [entity setScriptedMisjump:bValue];
            return JS_UNDEFINED;
        }
        break;

    case kShip_scriptedMisjumpRange:
        if ((JS_ToFloat64(context, &fValue, value) == 0)) {
            if (fValue > 0.0 && fValue < 1.0) {
                [entity setScriptedMisjumpRange:fValue];
                return JS_UNDEFINED;
            } else {
                OOJSReportError(context, @"ship.%@ must be > 0.0 and < 1.0.", OOStringFromJSPropertyMagic(magic, sShipProperties, OOJS_COUNT(sShipProperties)));
                return OOJSNativeFailure(context);
            }
        }
        break;

    case kShip_subEntityRotation:
        if (JSValueToQuaternion(context, value, &qValue)) {
            [entity setSubEntityRotationalVelocity:qValue];
            return JS_UNDEFINED;
        }
        break;

    case kShip_sunGlareFilter:
        if ((JS_ToFloat64(context, &fValue, value) == 0)) {
            if (fValue >= 0.0f && fValue <= 1.0f) {
                [entity setSunGlareFilter:fValue];
                return JS_UNDEFINED;
            } else {
                OOJSReportError(context, @"ship.%@ must be > 0.0 and < 1.0.", OOStringFromJSPropertyMagic(magic, sShipProperties, OOJS_COUNT(sShipProperties)));
                return OOJSNativeFailure(context);
            }
        }
        break;

    case kShip_thrust:
        //			if (EXPECT_NOT([entity isPlayer]))  goto playerReadOnly;

        if ((JS_ToFloat64(context, &fValue, value) == 0)) {
            [entity setThrust:OOClamp_0_max_f(fValue, [entity maxThrust])];
            return JS_UNDEFINED;
        }
        break;

    case kShip_maxPitch:
        if ((JS_ToFloat64(context, &fValue, value) == 0)) {
            if (fValue < 0) {
                OOJSReportError(context, @"ship.maxPitch cannot be negative.");
                return OOJSNativeFailure(context);
            }
            [entity setMaxFlightPitch:fValue];
            return JS_UNDEFINED;
        }
        break;

    case kShip_maxSpeed:
        if ((JS_ToFloat64(context, &fValue, value) == 0)) {
            if (fValue < 0) {
                OOJSReportError(context, @"ship.maxSpeed cannot be negative.");
                return OOJSNativeFailure(context);
            }
            [entity setMaxFlightSpeed:fValue];
            return JS_UNDEFINED;
        }
        break;

    case kShip_maxRoll:
        if ((JS_ToFloat64(context, &fValue, value) == 0)) {
            if (fValue < 0) {
                OOJSReportError(context, @"ship.maxRoll cannot be negative.");
                return OOJSNativeFailure(context);
            }
            [entity setMaxFlightRoll:fValue];
            return JS_UNDEFINED;
        }
        break;

    case kShip_maxYaw:
        if ((JS_ToFloat64(context, &fValue, value) == 0)) {
            if (fValue < 0) {
                OOJSReportError(context, @"ship.maxYaw cannot be negative.");
                return OOJSNativeFailure(context);
            }
            [entity setMaxFlightYaw:fValue];
            return JS_UNDEFINED;
        }
        break;

    case kShip_injectorBurnRate:
        if ((JS_ToFloat64(context, &fValue, value) == 0)) {
            if (fValue < 0) {
                OOJSReportError(context, @"ship.injectorBurnRate cannot be negative.");
                return OOJSNativeFailure(context);
            }
            [entity setAfterburnerRate:fValue];
            return JS_UNDEFINED;
        }
        break;

    case kShip_injectorSpeedFactor:
        if ((JS_ToFloat64(context, &fValue, value) == 0)) {
            if (fValue < 1) {
                OOJSReportError(context, @"ship.injectorSpeedFactor cannot be less than 1.0.");
                return OOJSNativeFailure(context);
            }
#if OO_VARIABLE_TORUS_SPEED
            else if (fValue > MIN_HYPERSPEED_FACTOR) {
                OOJSReportError(context, @"ship.injectorSpeedFactor cannot be higher than minimum torus speed factor (%f).", MIN_HYPERSPEED_FACTOR);
#else
            else if (fValue > HYPERSPEED_FACTOR) {
                OOJSReportError(context, @"ship.injectorSpeedFactor cannot be higher than torus speed factor (%f).", HYPERSPEED_FACTOR);
#endif
                return OOJSNativeFailure(context);
            }
            [entity setAfterburnerFactor:fValue];
            return JS_UNDEFINED;
        }
        break;

    case kShip_maxThrust:
        if ((JS_ToFloat64(context, &fValue, value) == 0)) {
            if (fValue < 0) {
                OOJSReportError(context, @"ship.maxThrust cannot be negative.");
                return OOJSNativeFailure(context);
            }
            [entity setMaxThrust:fValue];
            return JS_UNDEFINED;
        }
        break;

    case kShip_energyRechargeRate:
        if ((JS_ToFloat64(context, &fValue, value) == 0)) {
            if (fValue < 0) {
                OOJSReportError(context, @"ship.energyRechargeRate cannot be negative.");
                return OOJSNativeFailure(context);
            }
            [entity setEnergyRechargeRate:fValue];
            return JS_UNDEFINED;
        }
        break;

    case kShip_lightsActive:
        if (((bValue = JS_ToBool(context, value)) >= 0)) {
            if (bValue)
                [entity switchLightsOn];
            else
                [entity switchLightsOff];
            return JS_UNDEFINED;
        }
        break;

    case kShip_velocity:
        if (JSValueToVector(context, value, &vValue)) {
            [entity setTotalVelocity:vValue];
            return JS_UNDEFINED;
        }
        break;

    case kShip_portWeapon:
    case kShip_starboardWeapon:
    case kShip_aftWeapon:
    case kShip_forwardWeapon:
    case kShip_currentWeapon:
        sValue = JSValueToEquipmentKeyRelaxed(context, value, &exists);
        if (sValue == nil) {
            sValue = @"EQ_WEAPON_NONE";
        }
        OOWeaponFacing facing = WEAPON_FACING_FORWARD;
        switch (magic) {
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
        if ([entity isPlayer]) {
            PlayerEntity* pent = (PlayerEntity*)entity;
            [pent setWeaponMount:facing toWeapon:sValue inContext:@"scripted"];
        } else {
            [entity setWeaponMount:facing toWeapon:sValue];
        }
        return JS_UNDEFINED;

    case kShip_maxEscorts:
        if (EXPECT_NOT([entity isPlayer]))
            goto playerReadOnly;

        if (OOJSValueToInt32(context, value, &iValue)) {
            if ((NSInteger)iValue < (NSInteger)[[entity escortGroup] count] - 1) {
                OOJSReportError(context, @"ship.%@ must be >= current escort numbers.", OOStringFromJSPropertyMagic(magic, sShipProperties, OOJS_COUNT(sShipProperties)));
                return OOJSNativeFailure(context);
            }
            if (iValue > MAX_ESCORTS) {
                OOJSReportError(context, @"ship.%@ must be <= %d.", OOStringFromJSPropertyMagic(magic, sShipProperties, OOJS_COUNT(sShipProperties)), MAX_ESCORTS);
                return OOJSNativeFailure(context);
            }
            [entity setMaxEscortCount:iValue];
            return JS_UNDEFINED;
        }

        break;

    default:
        OOJSReportBadPropertySelector(context, this, magic, sShipProperties, OOJS_COUNT(sShipProperties));
        return OOJSNativeFailure(context);
    }

    OOJSReportBadPropertyValue(context, this, magic, sShipProperties, OOJS_COUNT(sShipProperties), value);
    return OOJSNativeFailure(context);

playerReadOnly:
    OOJSReportError(context, @"player.ship.%@ is read-only.", OOStringFromJSPropertyMagic(magic, sShipProperties, OOJS_COUNT(sShipProperties)));
    return OOJSNativeFailure(context);

    // Not used (yet)
    /*
    npcReadOnly:
            OOJSReportError(context, @"npc.ship.%@ is read-only.", OOStringFromJSPropertyMagic(magic, sShipProperties, OOJS_COUNT(sShipProperties)));
            return OOJSNativeFailure(context);
    */

    OOJS_NATIVE_EXIT
}

// *** Methods ***

#define GET_THIS_SHIP(THISENT)                                              \
    do {                                                                    \
        if (EXPECT_NOT(!JSShipGetShipEntity(context, OOJS_THIS, &THISENT))) \
            return OOJSNativeFailure(context); /* Exception */              \
        if (OOIsStaleEntity(THISENT))                                       \
            OOJS_RETURN_VOID;                                               \
    } while (0)

// setScript(scriptName : String)
static JSValue ShipSetScript(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    ShipEntity* thisEnt = nil;
    NSString* name = nil;

    GET_THIS_SHIP(thisEnt);
    if (argc > 0)
        name = OOStringFromJSValue(context, OOJS_ARGV[0]);
    if (EXPECT_NOT(name == nil)) {
        OOJSReportBadArguments(context, @"Ship", @"setScript", MIN(argc, 1), OOJS_ARGV, nil, @"string (script name)");
        return OOJSNativeFailure(context);
    }
    if (EXPECT_NOT([thisEnt isPlayer])) {
        OOJSReportErrorForCaller(context, @"Ship", @"setScript", @"Not valid for player ship.");
        return OOJSNativeFailure(context);
    }

    [thisEnt setShipScript:name];
    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}

// setAI(aiName : String)
static JSValue ShipSetAI(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    ShipEntity* thisEnt = nil;
    NSString* name = nil;

    GET_THIS_SHIP(thisEnt);
    if (argc > 0)
        name = OOStringFromJSValue(context, OOJS_ARGV[0]);
    if (EXPECT_NOT(name == nil)) {
        OOJSReportBadArguments(context, @"Ship", @"setAI", MIN(argc, 1), OOJS_ARGV, nil, @"string (AI name)");
        return OOJSNativeFailure(context);
    }
    if (EXPECT_NOT([thisEnt isPlayer])) {
        OOJSReportErrorForCaller(context, @"Ship", @"setAI", @"Not valid for player ship.");
        return OOJSNativeFailure(context);
    }

    [thisEnt setAITo:name];
    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}

// switchAI(aiName : String)
static JSValue ShipSwitchAI(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    ShipEntity* thisEnt = nil;
    NSString* name = nil;

    GET_THIS_SHIP(thisEnt);
    if (argc > 0)
        name = OOStringFromJSValue(context, OOJS_ARGV[0]);
    if (EXPECT_NOT(name == nil)) {
        OOJSReportBadArguments(context, @"Ship", @"switchAI", MIN(argc, 1), OOJS_ARGV, nil, @"string (AI name)");
        return OOJSNativeFailure(context);
    }
    if (EXPECT_NOT([thisEnt isPlayer])) {
        OOJSReportErrorForCaller(context, @"Ship", @"switchAI", @"Not valid for player ship.");
        return OOJSNativeFailure(context);
    }

    [thisEnt switchAITo:name];
    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}

// exitAI()
static JSValue ShipExitAI(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    ShipEntity* thisEnt = nil;
    AI* thisAI = nil;
    NSString* message = nil;

    GET_THIS_SHIP(thisEnt);
    if (EXPECT_NOT([thisEnt isPlayer])) {
        OOJSReportErrorForCaller(context, @"Ship", @"exitAI", @"Not valid for player ship.");
        return OOJSNativeFailure(context);
    }
    thisAI = [thisEnt getAI];

    if ([thisAI hasSuspendedStateMachines]) {
        if (argc > 0) {
            message = OOStringFromJSValue(context, OOJS_ARGV[0]);
        }
        // Else AI will default to RESTARTED.

        [thisAI exitStateMachineWithMessage:message];
    } else {
        OOJSReportWarningForCaller(context, @"Ship", @"exitAI()", @"Cannot exit current AI state machine because there are no suspended state machines.");
    }
    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}

// reactToAIMessage(message : String)
static JSValue ShipReactToAIMessage(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    ShipEntity* thisEnt = nil;
    NSString* message = nil;

    GET_THIS_SHIP(thisEnt);
    if (argc > 0)
        message = OOStringFromJSValue(context, OOJS_ARGV[0]);
    if (EXPECT_NOT(message == nil)) {
        OOJSReportBadArguments(context, @"Ship", @"reactToAIMessage", MIN(argc, 1), OOJS_ARGV, nil, @"string");
        return OOJSNativeFailure(context);
    }
    if (EXPECT_NOT([thisEnt isPlayer])) {
        OOJSReportErrorForCaller(context, @"Ship", @"reactToAIMessage", @"Not valid for player ship.");
        return OOJSNativeFailure(context);
    }

    [thisEnt reactToAIMessage:message context:@"JavaScript reactToAIMessage()"];
    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}

// sendAIMessage(message : String)
static JSValue ShipSendAIMessage(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    ShipEntity* thisEnt = nil;
    NSString* message = nil;

    GET_THIS_SHIP(thisEnt);
    if (argc > 0)
        message = OOStringFromJSValue(context, OOJS_ARGV[0]);
    if (EXPECT_NOT(message == nil)) {
        OOJSReportBadArguments(context, @"Ship", @"sendAIMessage", MIN(argc, 1), OOJS_ARGV, nil, @"string");
        return OOJSNativeFailure(context);
    }
    if (EXPECT_NOT([thisEnt isPlayer])) {
        OOJSReportErrorForCaller(context, @"Ship", @"sendAIMessage", @"Not valid for player ship.");
        return OOJSNativeFailure(context);
    }

    [thisEnt sendAIMessage:message];
    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}

// deployEscorts()
static JSValue ShipDeployEscorts(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    ShipEntity* thisEnt = nil;

    GET_THIS_SHIP(thisEnt);

    [thisEnt deployEscorts];
    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}

// dockEscorts()
static JSValue ShipDockEscorts(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    ShipEntity* thisEnt = nil;

    GET_THIS_SHIP(thisEnt);

    [thisEnt dockEscorts];
    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}

// hasEquipmentProviding(equipment : String) : Boolean
static JSValue ShipHasEquipmentProviding(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    ShipEntity* thisEnt = nil;
    NSString* equipment = nil;

    GET_THIS_SHIP(thisEnt);

    if (argc > 0)
        equipment = OOStringFromJSValue(context, OOJS_ARGV[0]);
    if (EXPECT_NOT(equipment == nil)) {
        OOJSReportBadArguments(context, @"Ship", @"hasEquipmentProviding", MIN(argc, 1), OOJS_ARGV, nil, @"string (equipment)");
        return OOJSNativeFailure(context);
    }

    OOJS_RETURN_BOOL([thisEnt hasEquipmentItemProviding:equipment]);

    OOJS_NATIVE_EXIT
}

// hasRole(role : String) : Boolean
static JSValue ShipHasRole(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    ShipEntity* thisEnt = nil;
    NSString* role = nil;

    GET_THIS_SHIP(thisEnt);

    if (argc > 0)
        role = OOStringFromJSValue(context, OOJS_ARGV[0]);
    if (EXPECT_NOT(role == nil)) {
        OOJSReportBadArguments(context, @"Ship", @"hasRole", MIN(argc, 1), OOJS_ARGV, nil, @"string (role)");
        return OOJSNativeFailure(context);
    }

    OOJS_RETURN_BOOL([thisEnt hasRole:role]);

    OOJS_NATIVE_EXIT
}

// ejectItem(role : String) : Ship
static JSValue ShipEjectItem(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    ShipEntity* thisEnt = nil;
    NSString* role = nil;

    GET_THIS_SHIP(thisEnt);

    if (argc > 0)
        role = OOStringFromJSValue(context, OOJS_ARGV[0]);
    if (EXPECT_NOT(role == nil)) {
        OOJSReportBadArguments(context, @"Ship", @"ejectItem", MIN(argc, 1), OOJS_ARGV, nil, @"string (role)");
        return OOJSNativeFailure(context);
    }

    OOJS_RETURN_OBJECT([thisEnt ejectShipOfRole:role]);

    OOJS_NATIVE_EXIT
}

// addCargoEntity: ship
static JSValue ShipAddCargoEntity(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)
    ShipEntity* thisEnt = nil;
    ShipEntity* target = nil;
    int procEvents = NO;
    int procMessages = NO;

    GET_THIS_SHIP(thisEnt);

    if (EXPECT_NOT([thisEnt isPlayer] && [(PlayerEntity*)thisEnt isDocked])) {
        OOJSReportWarningForCaller(context, @"PlayerShip", @"addCargoEntity", @"Can't add cargo entity while docked, ignoring.");
        return OOJSNativeFailure(context);
    }
    if (EXPECT_NOT(argc == 0 || JS_IsNull(OOJS_ARGV[0]) || !JS_IsObject(OOJS_ARGV[0]) || !JSShipGetShipEntity(context, OOJS_ARGV[0], &target))) {
        OOJSReportBadArguments(context, @"PlayerShip", @"addCargoEntity", MIN(argc, 1), OOJS_ARGV, nil, @"scoopable entity.");
        return OOJSNativeFailure(context);
    }
    if ([target scanClass] != CLASS_CARGO) {
        OOJSReportWarningForCaller(context, @"PlayerShip", @"addCargoEntity", @"Scoopable entity not cargo.");
        return OOJSNativeFailure(context);
    }
    if ([target status] != STATUS_IN_FLIGHT) {
        OOJSReportWarningForCaller(context, @"PlayerShip", @"addCargoEntity", @"Scoopable entity not in flight.");
        return OOJSNativeFailure(context);
    }
    if (argc >= 2 && EXPECT_NOT(!((procEvents = JS_ToBool(context, OOJS_ARGV[1])) >= 0))) {
        OOJSReportBadArguments(context, @"PlayerShip", @"addCargoEntity", MIN(argc, 2), OOJS_ARGV, nil, @"boolean");
        return OOJSNativeFailure(context);
    }
    if (argc == 3 && EXPECT_NOT(!((procMessages = JS_ToBool(context, OOJS_ARGV[2])) >= 0))) {
        OOJSReportBadArguments(context, @"PlayerShip", @"addCargoEntity", MIN(argc, 3), OOJS_ARGV, nil, @"boolean");
        return OOJSNativeFailure(context);
    }

    // scoop the object, but don't process any events/messages unless requested
    OOJS_BEGIN_FULL_NATIVE(context)
    [thisEnt scoopUpProcess:target processEvents:procEvents processMessages:procMessages];
    OOJS_END_FULL_NATIVE

    OOJS_RETURN_BOOL([target status] == STATUS_IN_HOLD);

    OOJS_NATIVE_EXIT
}

// ejectSpecificItem(itemKey : String) : Ship
static JSValue ShipEjectSpecificItem(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    ShipEntity* thisEnt = nil;
    NSString* itemKey = nil;

    GET_THIS_SHIP(thisEnt);

    if (argc > 0)
        itemKey = OOStringFromJSValue(context, OOJS_ARGV[0]);
    if (EXPECT_NOT(itemKey == nil)) {
        OOJSReportBadArguments(context, @"Ship", @"ejectSpecificItem", MIN(argc, 1), OOJS_ARGV, nil, @"string (ship key)");
        return OOJSNativeFailure(context);
    }

    OOJS_RETURN_OBJECT([thisEnt ejectShipOfType:itemKey]);

    OOJS_NATIVE_EXIT
}

// dumpCargo() : Ship
static JSValue ShipDumpCargo(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    ShipEntity* thisEnt = nil;
    OOCommodityType pref = nil;

    GET_THIS_SHIP(thisEnt);

    if (EXPECT_NOT([thisEnt isPlayer] && [(PlayerEntity*)thisEnt isDocked])) {
        OOJSReportWarningForCaller(context, @"PlayerShip", @"dumpCargo", @"Can't dump cargo while docked, ignoring.");
        OOJS_RETURN_NULL;
    }

    if (argc > 1) {
        pref = OOStringFromJSValue(context, OOJS_ARGV[1]);
    }

    // NPCs can queue multiple items to dump
    if (!EXPECT_NOT([thisEnt isPlayer])) {
        int32_t i, count = 1;
        BOOL gotCount = YES;
        if (argc > 0)
            gotCount = OOJSValueToInt32(context, OOJS_ARGV[0], &count);
        if (EXPECT_NOT(!gotCount || count < 1 || count > 64)) {
            OOJSReportBadArguments(context, @"Ship", @"dumpCargo", MIN(argc, 1), OOJS_ARGV, nil, @"optional quantity (1 to 64), optional preferred commodity");
            return OOJSNativeFailure(context);
        }

        for (i = 1; i < count; i++) {
            [thisEnt performSelector:@selector(dumpCargo) withObject:nil afterDelay:0.75 * i]; // drop 3 canisters per 2 seconds
        }
    }

    OOJS_RETURN_OBJECT([thisEnt dumpCargoItem:pref]);

    OOJS_NATIVE_EXIT
}

// spawn(role : String [, number : count]) : Array
static JSValue ShipSpawn(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    ShipEntity* thisEnt = nil;
    NSString* role = nil;
    int32_t count = 1;
    BOOL gotCount = YES;
    NSArray* result = nil;

    GET_THIS_SHIP(thisEnt);

    if (argc > 0)
        role = OOStringFromJSValue(context, OOJS_ARGV[0]);
    if (argc > 1)
        gotCount = OOJSValueToInt32(context, OOJS_ARGV[1], &count);
    if (EXPECT_NOT(role == nil || !gotCount || count < 1 || count > 64)) {
        OOJSReportBadArguments(context, @"Ship", @"spawn", MIN(argc, 1), OOJS_ARGV, nil, @"role and optional quantity (1 to 64)");
        return OOJSNativeFailure(context);
    }

    OOJS_BEGIN_FULL_NATIVE(context)
    result = [thisEnt spawnShipsWithRole:role count:count];
    OOJS_END_FULL_NATIVE

    OOJS_RETURN_OBJECT(result);

    OOJS_NATIVE_EXIT
}

// dealEnergyDamage(). Replaces AI's dealEnergyDamageWithinDesiredRange
static JSValue ShipDealEnergyDamage(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    ShipEntity* thisEnt = nil;
    double baseDamage;
    double range;
    double velocityBias = 0.0;
    BOOL gotDamage;
    BOOL gotRange;
    BOOL gotVBias;
    GET_THIS_SHIP(thisEnt);

    if (argc < 2) {
        OOJSReportBadArguments(context, @"Ship", @"dealEnergyDamage", argc, OOJS_ARGV, nil, @"damage and range needed");
        return OOJSNativeFailure(context);
    }

    gotDamage = (JS_ToFloat64(context, &baseDamage, OOJS_ARGV[0]) == 0);
    if (EXPECT_NOT(!gotDamage || baseDamage < 0)) {
        OOJSReportBadArguments(context, @"Ship", @"dealEnergyDamage", argc, OOJS_ARGV, nil, @"damage must be positive");
        return OOJSNativeFailure(context);
    }
    gotRange = (JS_ToFloat64(context, &range, OOJS_ARGV[1]) == 0);
    if (EXPECT_NOT(!gotRange || range < 0)) {
        OOJSReportBadArguments(context, @"Ship", @"dealEnergyDamage", argc, OOJS_ARGV, nil, @"range must be positive");
        return OOJSNativeFailure(context);
    }
    if (argc >= 3) {
        gotVBias = (JS_ToFloat64(context, &velocityBias, OOJS_ARGV[2]) == 0);
        if (!gotVBias) {
            OOJSReportBadArguments(context, @"Ship", @"dealEnergyDamage", argc, OOJS_ARGV, nil, @"velocity bias must be a number");
            return OOJSNativeFailure(context);
        }
    }

    [thisEnt dealEnergyDamage:(GLfloat)baseDamage atRange:(GLfloat)range withBias:(GLfloat)velocityBias];

    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}

// explode()
static JSValue ShipExplode(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    return RemoveOrExplodeShip(context, OOJS_THIS, argc, OOJS_ARGV, YES);

    OOJS_NATIVE_EXIT
}

// remove([suppressDeathEvent : Boolean = false])
static JSValue ShipRemove(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    ShipEntity* thisEnt = nil;
    int suppressDeathEvent = NO;

    GET_THIS_SHIP(thisEnt);

    if ([thisEnt isPlayer]) {
        OOJSReportError(context, @"Cannot remove() player's ship.");
        return OOJSNativeFailure(context);
    }

    if (argc > 0 && EXPECT_NOT(!((suppressDeathEvent = JS_ToBool(context, OOJS_ARGV[0])) >= 0))) {
        OOJSReportBadArguments(context, @"Ship", @"remove", argc, OOJS_ARGV, nil, @"boolean");
        return OOJSNativeFailure(context);
    }

    [thisEnt doScriptEvent:OOJSID("shipRemoved") withArgument:[NSNumber numberWithBool:suppressDeathEvent]];

    if (suppressDeathEvent) {
        [thisEnt removeScript];
    }
    return RemoveOrExplodeShip(context, OOJS_THIS, argc, OOJS_ARGV, NO);

    OOJS_NATIVE_EXIT
}

// __runLegacyScriptActions(target : Ship, actions : Array)
static JSValue ShipRunLegacyScriptActions(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    ShipEntity* thisEnt = nil;
    PlayerEntity* player = nil;
    ShipEntity* target = nil;
    NSArray* actions = nil;

    player = OOPlayerForScripting();
    GET_THIS_SHIP(thisEnt);

    if (argc > 1)
        actions = OOJSNativeObjectFromJSValue(context, OOJS_ARGV[1]);
    if (EXPECT_NOT(argc != 2 || !JS_IsObject(OOJS_ARGV[0]) || !JSShipGetShipEntity(context, OOJS_ARGV[0], &target) || ![actions isKindOfClass:[NSArray class]])) {
        OOJSReportBadArguments(context, @"Ship", @"__runLegacyScriptActions", argc, OOJS_ARGV, nil, @"target and array of actions");
        return OOJSNativeFailure(context);
    }

    if (target != nil) // Not stale reference
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
static JSValue ShipCommsMessage(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    ShipEntity* thisEnt = nil;
    NSString* message = nil;
    ShipEntity* target = nil;

    GET_THIS_SHIP(thisEnt);

    if (argc > 0)
        message = OOStringFromJSValue(context, OOJS_ARGV[0]);
    if (EXPECT_NOT(message == nil || (argc > 1 && (JS_IsNull(OOJS_ARGV[1]) || !JS_IsObject(OOJS_ARGV[1]) || !JSShipGetShipEntity(context, OOJS_ARGV[1], &target))))) {
        OOJSReportBadArguments(context, @"Ship", @"commsMessage", MIN(argc, 1), OOJS_ARGV, nil, @"message and optional target");
        return OOJSNativeFailure(context);
    }

    if (argc < 2) {
        [thisEnt commsMessage:message withUnpilotedOverride:YES]; // generic broadcast
    } else if (target != nil) // Not stale reference
    {
        [thisEnt sendMessage:message toShip:target withUnpilotedOverride:YES]; // ship-to-ship narrowcast
    }
    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}

// fireECM()
static JSValue ShipFireECM(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    ShipEntity* thisEnt = nil;
    BOOL OK;

    GET_THIS_SHIP(thisEnt);

    OK = [thisEnt fireECM];
    if (!OK) {
        OOJSReportWarning(context, @"Ship %@ was requested to fire ECM burst but does not carry ECM equipment.", [thisEnt oo_jsDescription]);
    }

    OOJS_RETURN_BOOL(OK);

    OOJS_NATIVE_EXIT
}

// abandonShip()
static JSValue ShipAbandonShip(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    ShipEntity* thisEnt = nil;

    GET_THIS_SHIP(thisEnt);
    OOJS_RETURN_BOOL([thisEnt hasEscapePod] && [thisEnt abandonShip]);

    OOJS_NATIVE_EXIT
}

// canAwardEquipment(type : equipmentInfoExpression)
static JSValue ShipCanAwardEquipment(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    ShipEntity* thisEnt = nil;
    NSString* key = nil;
    NSString* ctx = @"scripted";
    BOOL result;
    BOOL exists;

    GET_THIS_SHIP(thisEnt);

    if (argc > 0)
        key = JSValueToEquipmentKeyRelaxed(context, OOJS_ARGV[0], &exists);
    if (EXPECT_NOT(key == nil)) {
        OOJSReportBadArguments(context, @"Ship", @"canAwardEquipment", MIN(argc, 1), OOJS_ARGV, nil, @"equipment type");
        return OOJSNativeFailure(context);
    }

    if (exists) {
        if (argc > 1) {
            ctx = OOStringFromJSValue(context, OOJS_ARGV[1]);
            if (![ctx isEqualToString:@"scripted"] && ![ctx isEqualToString:@"purchase"] && ![ctx isEqualToString:@"newShip"] && ![ctx isEqualToString:@"npc"]) {
                OOJSReportBadArguments(context, @"Ship", @"canAwardEquipment", MIN(argc, 2), OOJS_ARGV, nil, @"context");
                return OOJSNativeFailure(context);
            }
        }
        result = YES;

        // can't add fuel as equipment.
        if ([key isEqualToString:@"EQ_FUEL"])
            result = NO;

        if (result)
            result = [thisEnt canAddEquipment:key inContext:ctx];
    } else {
        // Unknown type.
        result = NO;
    }

    OOJS_RETURN_BOOL(result);

    OOJS_NATIVE_EXIT
}

// awardEquipment(type : equipmentInfoExpression) : Boolean
static JSValue ShipAwardEquipment(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    ShipEntity* thisEnt = nil;
    OOEquipmentType* eqType = nil;
    NSString* identifier = nil;
    BOOL OK = YES;
    BOOL berth;
    BOOL isRepair = NO;

    GET_THIS_SHIP(thisEnt);

    if (argc > 0)
        eqType = JSValueToEquipmentType(context, OOJS_ARGV[0]);
    if (EXPECT_NOT(eqType == nil)) {
        OOJSReportBadArguments(context, @"Ship", @"awardEquipment", MIN(argc, 1), OOJS_ARGV, nil, @"equipment type");
        return OOJSNativeFailure(context);
    }

    // Check that equipment is permitted.
    identifier = [eqType identifier];
    berth = [identifier isEqualToString:@"EQ_PASSENGER_BERTH"];
    if (berth) {
        OK = [thisEnt availableCargoSpace] >= [eqType requiredCargoSpace];
    } else if ([identifier isEqualToString:@"EQ_FUEL"]) {
        OK = NO;
    } else {
        OK = [eqType canCarryMultiple] || ![thisEnt hasEquipmentItem:identifier];
    }

    if (OK) {
        if ([thisEnt isPlayer]) {
            PlayerEntity* player = (PlayerEntity*)thisEnt;

            if ([identifier isEqualToString:@"EQ_MISSILE_REMOVAL"]) {
                [player removeMissiles];
            } else if ([eqType isMissileOrMine]) {
                OK = [player mountMissileWithRole:identifier];
            } else if (berth) {
                OK = [player changePassengerBerths:+1];
            } else if ([identifier isEqualToString:@"EQ_PASSENGER_BERTH_REMOVAL"]) {
                OK = [player changePassengerBerths:-1];
            } else {
                isRepair = [thisEnt hasEquipmentItem:[identifier stringByAppendingString:@"_DAMAGED"]];
                OK = [player addEquipmentItem:identifier withValidation:YES inContext:@"scripted"];
                if (OK && isRepair) {
                    [player doScriptEvent:OOJSID("equipmentRepaired") withArgument:identifier];
                }
            }
        } else {
            if ([identifier isEqualToString:@"EQ_MISSILE_REMOVAL"]) {
                [thisEnt removeMissiles];
            }
            // no passenger handling for NPCs. EQ_CARGO_BAY is dealt with inside addEquipmentItem
            else if (!berth && ![identifier isEqualToString:@"EQ_PASSENGER_BERTH_REMOVAL"]) {
                OK = [thisEnt addEquipmentItem:identifier withValidation:YES inContext:@"scripted"];
            } else {
                OK = NO;
            }
        }
    }

    OOJS_RETURN_BOOL(OK);

    OOJS_NATIVE_EXIT
}

// removeEquipment(type : equipmentInfoExpression)
static JSValue ShipRemoveEquipment(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    ShipEntity* thisEnt = nil;
    NSString* key = nil;
    BOOL OK = YES;

    GET_THIS_SHIP(thisEnt);

    if (argc > 0)
        key = JSValueToEquipmentKey(context, OOJS_ARGV[0]);
    if (EXPECT_NOT(key == nil)) {
        OOJSReportBadArguments(context, @"Ship", @"removeEquipment", MIN(argc, 1), OOJS_ARGV, nil, @"equipment type");
        return OOJSNativeFailure(context);
    }
    // berths are not in hasOneEquipmentItem
    OK = [thisEnt hasOneEquipmentItem:key includeMissiles:YES whileLoading:NO] || ([key isEqualToString:@"EQ_PASSENGER_BERTH"] && [thisEnt passengerCapacity] > 0);
    if (!OK) {
        // Allow removal of damaged equipment.
        key = [key stringByAppendingString:@"_DAMAGED"];
        OK = [thisEnt hasOneEquipmentItem:key includeMissiles:NO whileLoading:NO];
    }
    if (OK) {
        // exceptions
        if ([key isEqualToString:@"EQ_PASSENGER_BERTH"] || [key isEqualToString:@"EQ_CARGO_BAY"]) {
            if ([key isEqualToString:@"EQ_PASSENGER_BERTH"]) {
                if ([thisEnt passengerCapacity] > [thisEnt passengerCount]) {
                    // must be the player's ship!
                    if ([thisEnt isPlayer])
                        [(PlayerEntity*)thisEnt changePassengerBerths:-1];
                } else
                    OK = NO;
            } else // EQ_CARGO_BAY
            {
                // player cargo bay removal handled in script
                if ([thisEnt isPlayer] || [thisEnt extraCargo] <= [thisEnt availableCargoSpace]) {
                    [thisEnt removeEquipmentItem:key];
                } else
                    OK = NO;
            }
        } else
            [thisEnt removeEquipmentItem:key];
    }

    OOJS_RETURN_BOOL(OK);

    OOJS_NATIVE_EXIT
}

// restoreSubEntities(): boolean
static JSValue ShipRestoreSubEntities(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    ShipEntity* thisEnt = nil;
    NSUInteger numSubEntitiesRestored = 0U;

    GET_THIS_SHIP(thisEnt);

    NSUInteger subCount = [[thisEnt subEntitiesForScript] count];

    [thisEnt clearSubEntities];
    [thisEnt setUpSubEntities];

    if ([[thisEnt subEntitiesForScript] count] - subCount > 0)
        numSubEntitiesRestored = [[thisEnt subEntitiesForScript] count] - subCount;

    // for each subentity restored, slightly increase the trade-in factor
    if ([thisEnt isPlayer]) {
        int tradeInFactorChange = (int)MAX(PLAYER_SHIP_SUBENTITY_TRADE_IN_VALUE * numSubEntitiesRestored, 25U);
        [(PlayerEntity*)thisEnt adjustTradeInFactorBy:tradeInFactorChange];
    }

    OOJS_RETURN_BOOL(numSubEntitiesRestored > 0);

    OOJS_NATIVE_EXIT
}

// setEquipmentStatus(type : equipmentInfoExpression, status : String): boolean
static JSValue ShipSetEquipmentStatus(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    // equipment status accepted: @"EQUIPMENT_OK", @"EQUIPMENT_DAMAGED"

    ShipEntity* thisEnt = nil;
    OOEquipmentType* eqType = nil;
    NSString* key = nil;
    NSString* damagedKey = nil;
    NSString* status = nil;
    BOOL hasOK = NO, hasDamaged = NO;

    GET_THIS_SHIP(thisEnt);

    if (argc < 2) {
        OOJSReportBadArguments(context, @"Ship", @"setEquipmentStatus", argc, OOJS_ARGV, nil, @"equipment type and status");
        return OOJSNativeFailure(context);
    }

    eqType = JSValueToEquipmentType(context, OOJS_ARGV[0]);
    if (EXPECT_NOT(eqType == nil)) {
        OOJSReportBadArguments(context, @"Ship", @"setEquipmentStatus", 1, &OOJS_ARGV[0], nil, @"equipment type");
        return OOJSNativeFailure(context);
    }

    status = OOStringFromJSValue(context, OOJS_ARGV[1]);
    if (EXPECT_NOT(status == nil)) {
        OOJSReportBadArguments(context, @"Ship", @"setEquipmentStatus", 1, &OOJS_ARGV[1], nil, @"equipment status");
        return OOJSNativeFailure(context);
    }

    // EMMSTRAN: use interned strings.
    if (![status isEqualToString:@"EQUIPMENT_OK"] && ![status isEqualToString:@"EQUIPMENT_DAMAGED"]) {
        OOJSReportErrorForCaller(context, @"Ship", @"setEquipmentStatus", @"Second parameter for setEquipmentStatus must be either \"EQUIPMENT_OK\" or \"EQUIPMENT_DAMAGED\".");
        return OOJSNativeFailure(context);
    }

    key = [eqType identifier];
    hasOK = [thisEnt hasEquipmentItem:key];
    BOOL setOK = [status isEqualToString:@"EQUIPMENT_OK"];
    BOOL setDamaged = [status isEqualToString:@"EQUIPMENT_DAMAGED"];
    if ([eqType canBeDamaged]) {
        damagedKey = [key stringByAppendingString:@"_DAMAGED"];
        hasDamaged = [thisEnt hasEquipmentItem:damagedKey];

        if ((setOK && hasDamaged) || (setDamaged && hasOK)) {
            // the implementation is identical between player and ship.
            [thisEnt removeEquipmentItem:(setDamaged ? key : damagedKey)];
            if ([thisEnt isPlayer]) {
                // these player methods are different to the ship ones.
                [(PlayerEntity*)thisEnt addEquipmentItem:(setDamaged ? damagedKey : key) withValidation:NO inContext:@"scripted"];
                if (setDamaged) {
                    [(PlayerEntity*)thisEnt doScriptEvent:OOJSID("equipmentDamaged") withArgument:key];
                } else if (setOK) {
                    [(PlayerEntity*)thisEnt doScriptEvent:OOJSID("equipmentRepaired") withArgument:key];
                }

                // if player's Docking Computers are set to EQUIPMENT_DAMAGED while on, stop them
                // this is now done in a different method
                // if (hasOK && [key isEqualToString:@"EQ_DOCK_COMP"])  [(PlayerEntity*)thisEnt disengageAutopilot];
            } else {
                [thisEnt addEquipmentItem:(setDamaged ? damagedKey : key) withValidation:NO inContext:@"scripted"];
                if (hasOK)
                    [thisEnt doScriptEvent:OOJSID("equipmentDamaged") withArgument:key];
            }
        }
    } else {
        if (hasOK && ![status isEqualToString:@"EQUIPMENT_OK"]) {
            OOJSReportWarningForCaller(context, @"Ship", @"setEquipmentStatus", @"Equipment %@ cannot be damaged.", key);
            hasOK = NO;
        }
    }

    OOJS_RETURN_BOOL(hasOK || hasDamaged);

    OOJS_NATIVE_EXIT
}

// equipmentStatus(type : equipmentInfoExpression) : String
static JSValue ShipEquipmentStatus(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    ShipEntity* thisEnt = nil;
    NSString* key = nil;
    BOOL asDict = NO;
    NSDictionary* dict = nil;

    GET_THIS_SHIP(thisEnt);

    if (argc > 0)
        key = JSValueToEquipmentKey(context, OOJS_ARGV[0]);
    if (argc > 1)
        asDict = OOJSValueToBOOL(context, OOJS_ARGV[1]);
    if (EXPECT_NOT(key == nil)) {
        if (argc > 0 && JS_IsString(OOJS_ARGV[0])) {
            if (asDict) {
                dict = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:1], @"EQUIPMENT_UNKNOWN", nil];
                OOJS_RETURN_OBJECT(dict);
            } else {
                OOJS_RETURN(OOJSSTR("EQUIPMENT_UNKNOWN"));
            }
        }

        OOJSReportBadArguments(context, @"Ship", @"equipmentStatus", MIN(argc, 1), &OOJS_ARGV[0], nil, @"equipment type");
        return OOJSNativeFailure(context);
    }

    if (asDict) {
        dict = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithUnsignedInteger:[thisEnt countEquipmentItem:key]], @"EQUIPMENT_OK", [NSNumber numberWithUnsignedInteger:[thisEnt countEquipmentItem:[key stringByAppendingString:@"_DAMAGED"]]], @"EQUIPMENT_DAMAGED", nil];
        OOJS_RETURN_OBJECT(dict);
    } else {
        if ([thisEnt hasEquipmentItem:key includeWeapons:YES whileLoading:NO])
            OOJS_RETURN(OOJSSTR("EQUIPMENT_OK"));
        else if ([thisEnt hasEquipmentItem:[key stringByAppendingString:@"_DAMAGED"]])
            OOJS_RETURN(OOJSSTR("EQUIPMENT_DAMAGED"));

        OOJS_RETURN(OOJSSTR("EQUIPMENT_UNAVAILABLE"));
    }
    OOJS_NATIVE_EXIT
}

// selectNewMissile()
static JSValue ShipSelectNewMissile(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    ShipEntity* thisEnt = nil;

    GET_THIS_SHIP(thisEnt);

    NSString* result = [[thisEnt selectMissile] identifier];
    // if there's a badly defined missile, selectMissile may return nil
    if (result == nil)
        result = @"EQ_MISSILE";

    OOJS_RETURN_OBJECT(result);

    OOJS_NATIVE_EXIT
}

// fireMissile()
static JSValue ShipFireMissile(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    ShipEntity* thisEnt = nil;
    id result = nil;

    GET_THIS_SHIP(thisEnt);

    if (argc > 0)
        result = [thisEnt fireMissileWithIdentifier:OOStringFromJSValue(context, OOJS_ARGV[0]) andTarget:[thisEnt primaryTarget]];
    else
        result = [thisEnt fireMissile];

    OOJS_RETURN_OBJECT(result);

    OOJS_NATIVE_EXIT
}

// findNearestStation
static JSValue ShipFindNearestStation(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    ShipEntity* thisEnt = nil;
    StationEntity* result = nil;

    GET_THIS_SHIP(thisEnt);

    double sdist, distance = 1E32;

    StationEntity* se = nil;
    foreach (se, [UNIVERSE stations]) {
        sdist = HPdistance2([thisEnt position], [se position]);

        if (sdist < distance) {
            distance = sdist;
            result = se;
        }
    }

    OOJS_RETURN_OBJECT(result);

    OOJS_NATIVE_EXIT
}

// setBounty(amount, reason)
static JSValue ShipSetBounty(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    ShipEntity* thisEnt = nil;
    NSString* reason = nil;
    int32_t newbounty = 0;
    BOOL gotBounty = YES;

    GET_THIS_SHIP(thisEnt);

    if (argc > 0)
        gotBounty = OOJSValueToInt32(context, OOJS_ARGV[0], &newbounty);
    if (argc > 1)
        reason = OOStringFromJSValue(context, OOJS_ARGV[1]);
    if (EXPECT_NOT(reason == nil || !gotBounty || newbounty < 0)) {
        OOJSReportBadArguments(context, @"Ship", @"setBounty", argc, OOJS_ARGV, nil, @"new bounty and reason");
        return OOJSNativeFailure(context);
    }

    [thisEnt setBounty:(OOCreditsQuantity)newbounty withReasonAsString:reason];

    OOJS_RETURN_VOID;

    OOJS_NATIVE_EXIT
}

// setCargo(cargoType : String [, number : count])
static JSValue ShipSetCargo(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    ShipEntity* thisEnt = nil;
    OOCommodityType commodity = nil;
    int32_t count = 1;
    BOOL gotCount = YES;

    GET_THIS_SHIP(thisEnt);

    if (argc > 0)
        commodity = OOStringFromJSValue(context, OOJS_ARGV[0]);
    if (argc > 1)
        gotCount = OOJSValueToInt32(context, OOJS_ARGV[1], &count);
    if (EXPECT_NOT(commodity == nil || !gotCount || count < 1)) {
        OOJSReportBadArguments(context, @"Ship", @"setCargo", argc, OOJS_ARGV, nil, @"cargo name and optional positive quantity");
        return OOJSNativeFailure(context);
    }

    if ([[UNIVERSE commodities] goodDefined:commodity]) {
        [thisEnt setCommodityForPod:commodity andAmount:count];
    }

    OOJS_RETURN_BOOL([[UNIVERSE commodities] goodDefined:commodity]);

    OOJS_NATIVE_EXIT
}

// setCrew(crewDefinition : Object)
static JSValue ShipSetCrew(OOJS_NATIVE_ARGS)
{
    /* TODO: ships can in theory have multiple crew, so this could
     * allow that to be set. Probably not necessary for now. */
    OOJS_NATIVE_ENTER(context)

    ShipEntity* thisEnt = nil;
    NSDictionary* crewDefinition = nil;

    GET_THIS_SHIP(thisEnt);

    // SpiderMonkey's JS_ValueToObject() check let primitives through to an invalid object cast; require an object or null.
    if (argc < 1 || (!JS_IsNull(OOJS_ARGV[0]) && !JS_IsObject(OOJS_ARGV[0]))) {
        OOJSReportBadArguments(context, @"Ship", @"setCrew", MIN(argc, 1), OOJS_ARGV, NULL, @"definition");
        return OOJSNativeFailure(context);
    }
    BOOL success = YES;

    if (![thisEnt isExplicitlyUnpiloted]) {
        if (JS_IsNull(OOJS_ARGV[0])) {
            [thisEnt setCrew:nil];
        } else {
            crewDefinition = OOJSNativeObjectFromJSObject(context, OOJS_ARGV[0]);
            OOCharacter* crew = [OOCharacter characterWithDictionary:crewDefinition];
            [thisEnt setCrew:[NSArray arrayWithObject:crew]];
        }
    } else {
        success = NO;
    }

    OOJS_RETURN_BOOL(success);

    OOJS_NATIVE_EXIT
}

// setCargoType(cargoType : String)
static JSValue ShipSetCargoType(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    ShipEntity* thisEnt = nil;
    NSString* cargoType = nil;

    GET_THIS_SHIP(thisEnt);

    if (argc > 0)
        cargoType = OOStringFromJSValue(context, OOJS_ARGV[0]);
    if (EXPECT_NOT(cargoType == nil)) {
        OOJSReportBadArguments(context, @"Ship", @"setCargoType", argc, OOJS_ARGV, nil, @"cargo type name");
        return OOJSNativeFailure(context);
    }
    if ([thisEnt cargoType] != CARGO_NOT_CARGO) {
        OOJSReportBadArguments(context, @"Ship", @"setCargoType", argc, OOJS_ARGV, nil, [NSString stringWithFormat:@"Can only be used on cargo pod carriers, not cargo pods (%@)", [thisEnt shipDataKey]]);
        return OOJSNativeFailure(context);
    }
    BOOL ok = YES;
    if ([cargoType isEqualToString:@"SCARCE_GOODS"]) {
        [thisEnt setCargoFlag:CARGO_FLAG_FULL_SCARCE];
    } else if ([cargoType isEqualToString:@"PLENTIFUL_GOODS"]) {
        [thisEnt setCargoFlag:CARGO_FLAG_FULL_PLENTIFUL];
    } else if ([cargoType isEqualToString:@"MEDICAL_GOODS"]) {
        [thisEnt setCargoFlag:CARGO_FLAG_FULL_MEDICAL];
    } else if ([cargoType isEqualToString:@"ILLEGAL_GOODS"]) {
        [thisEnt setCargoFlag:CARGO_FLAG_FULL_CONTRABAND];
    } else if ([cargoType isEqualToString:@"PIRATE_GOODS"]) {
        [thisEnt setCargoFlag:CARGO_FLAG_PIRATE];
    } else {
        ok = NO;
    }
    OOJS_RETURN_BOOL(ok);

    OOJS_NATIVE_EXIT
}

// setMaterials(params: dict, [shaders: dict])  // sets materials dictionary. Optional parameter sets the shaders dictionary too.
static JSValue ShipSetMaterials(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    ShipEntity* thisEnt = nil;

    if (argc < 1) {
        OOJSReportBadArguments(context, @"Ship", @"setMaterials", 0, OOJS_ARGV, nil, @"parameter object");
        return OOJSNativeFailure(context);
    }

    GET_THIS_SHIP(thisEnt);

    return ShipSetMaterialsInternal(context, OOJS_THIS, argc, OOJS_ARGV, thisEnt, NO);

    OOJS_NATIVE_EXIT
}

// setShaders(params: dict)
static JSValue ShipSetShaders(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    ShipEntity* thisEnt = nil;

    GET_THIS_SHIP(thisEnt);

    if (argc < 1) {
        OOJSReportBadArguments(context, @"Ship", @"setShaders", 0, OOJS_ARGV, nil, @"parameter object");
        return OOJSNativeFailure(context);
    }

    if (JS_IsNull(OOJS_ARGV[0]) || (!JS_IsNull(OOJS_ARGV[0]) && !JS_IsObject(OOJS_ARGV[0]))) {
        // EMMSTRAN: JS_ValueToObject() and normal error handling here.
        OOJSReportWarning(context, @"Ship.%@: expected %@ instead of '%@'.", @"setShaders", @"object", OOStringFromJSValueEvenIfNull(context, OOJS_ARGV[0]));
        OOJS_RETURN_BOOL(NO);
    }

    // SpiderMonkey version: OOJS_ARGV[1] = OOJS_ARGV[0]. QuickJS's argv may be the caller's own stack slots, so copy.
    JSValueConst shaderArgv[2] = { OOJS_ARGV[0], OOJS_ARGV[0] };
    return ShipSetMaterialsInternal(context, OOJS_THIS, argc, shaderArgv, thisEnt, YES);

    OOJS_NATIVE_EXIT
}

static JSValue ShipSetMaterialsInternal(OOJS_NATIVE_ARGS, ShipEntity* thisEnt, BOOL fromShaders)
{
    OOJS_PROFILE_ENTER

    JSValueConst params = JS_UNDEFINED;
    NSDictionary* materials;
    NSDictionary* shaders;
    BOOL withShaders = NO;
    BOOL success = NO;

    GET_THIS_SHIP(thisEnt);

    if (JS_IsNull(OOJS_ARGV[0]) || (!JS_IsNull(OOJS_ARGV[0]) && !JS_IsObject(OOJS_ARGV[0]))) {
        OOJSReportWarning(context, @"Ship.%@: expected %@ instead of '%@'.", @"setMaterials", @"object", OOStringFromJSValueEvenIfNull(context, OOJS_ARGV[0]));
        OOJS_RETURN_BOOL(NO);
    }

    if (argc > 1) {
        withShaders = YES;
        if (JS_IsNull(OOJS_ARGV[1]) || (!JS_IsNull(OOJS_ARGV[1]) && !JS_IsObject(OOJS_ARGV[1]))) {
            OOJSReportWarning(context, @"Ship.%@: expected %@ instead of '%@'.", @"setMaterials", @"object as second parameter", OOStringFromJSValueEvenIfNull(context, OOJS_ARGV[1]));
            withShaders = NO;
        }
    }

    if (fromShaders) {
        materials = [[thisEnt mesh] materials];
        params = OOJS_ARGV[0];
        shaders = OOJSNativeObjectFromJSObject(context, params);
    } else {
        params = OOJS_ARGV[0];
        materials = OOJSNativeObjectFromJSObject(context, params);
        if (withShaders) {
            params = OOJS_ARGV[1];
            shaders = OOJSNativeObjectFromJSObject(context, params);
        } else {
            shaders = [[thisEnt mesh] shaders];
        }
    }

    OOJS_BEGIN_FULL_NATIVE(context)
    NSDictionary* shipDict = [thisEnt shipInfoDictionary];

    // First we test to see if we can create the mesh.
    OOMesh* mesh = [OOMesh meshWithName:[shipDict oo_stringForKey:@"model"]
                               cacheKey:nil
                     materialDictionary:materials
                      shadersDictionary:shaders
                                 smooth:[shipDict oo_boolForKey:@"smooth" defaultValue:NO]
                           shaderMacros:[[ResourceManager materialDefaults] oo_dictionaryForKey:@"ship-prefix-macros"]
                    shaderBindingTarget:thisEnt];

    if (mesh != nil) {
        [thisEnt setMesh:mesh];
        success = YES;
    }
    OOJS_END_FULL_NATIVE

    OOJS_RETURN_BOOL(success);

    OOJS_PROFILE_EXIT
}

// exitSystem([int systemID])
static JSValue ShipExitSystem(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    ShipEntity* thisEnt = nil;
    int32_t systemID = -1;
    BOOL OK = NO;

    GET_THIS_SHIP(thisEnt);
    if (EXPECT_NOT([thisEnt isPlayer])) {
        OOJSReportErrorForCaller(context, @"Ship", @"exitSystem", @"Not valid for player ship.");
        return OOJSNativeFailure(context);
    }

    if (argc > 0) {
        if (!OOJSValueToInt32(context, OOJS_ARGV[0], &systemID) || systemID < 0 || 255 < systemID) {
            OOJSReportBadArguments(context, @"Ship", @"exitSystem", MIN(argc, 1), OOJS_ARGV, nil, @"system ID");
            return OOJSNativeFailure(context);
        }
    }

    OK = [thisEnt performHyperSpaceToSpecificSystem:systemID]; // -1 == random destination system

    OOJS_RETURN_BOOL(OK);

    OOJS_NATIVE_EXIT
}

static JSValue ShipUpdateEscortFormation(OOJS_NATIVE_ARGS)
{
    OOJS_PROFILE_ENTER

    ShipEntity* thisEnt = nil;
    GET_THIS_SHIP(thisEnt);
    [thisEnt updateEscortFormation];

    OOJS_RETURN_VOID;

    OOJS_PROFILE_EXIT
}

static JSValue RemoveOrExplodeShip(OOJS_NATIVE_ARGS, BOOL explode)
{
    OOJS_PROFILE_ENTER

    ShipEntity* thisEnt = nil;

    GET_THIS_SHIP(thisEnt);

    if (EXPECT_NOT([thisEnt isPlayer])) {
        NSCAssert(explode, @"RemoveOrExplodeShip(): shouldn't be called for player with !explode."); // player.ship.remove() is blocked by caller.
        PlayerEntity* player = (PlayerEntity*)thisEnt;

        if ([player isDocked]) {
            OOJSReportError(context, @"Cannot explode() player's ship while docked.");
            return OOJSNativeFailure(context);
        }
    }

    if (thisEnt == (ShipEntity*)[UNIVERSE station]) {
        // Allow exploding of main station (e.g. nova mission)
        [UNIVERSE unMagicMainStation];
    }

    if (EXPECT_NOT([thisEnt status] == STATUS_DOCKED)) {
        /* If it's in the launch queue and hasn't yet been added to
         * the universe, set the status to DEAD (so it gets removed
         * from the launch queue) */
        [thisEnt setStatus:STATUS_DEAD];
        /* No shipDied event occurs in this place - it never really
         * existed. This case is just to prevent an error from the
         * usual code branch - removing ships while they're still
         * docked is not recommended. */
    } else {
        [thisEnt setSuppressExplosion:!explode];
        [thisEnt setEnergy:1];
        [thisEnt takeEnergyDamage:500000000.0 from:nil becauseOf:nil weaponIdentifier:@""];
    }

    OOJS_RETURN_VOID;

    OOJS_PROFILE_EXIT
}

static JSValue ShipClearDefenseTargets(OOJS_NATIVE_ARGS)
{
    OOJS_PROFILE_ENTER

    ShipEntity* thisEnt = nil;
    GET_THIS_SHIP(thisEnt);
    [thisEnt removeAllDefenseTargets];

    OOJS_RETURN_VOID;

    OOJS_PROFILE_EXIT
}

static JSValue ShipAddDefenseTarget(OOJS_NATIVE_ARGS)
{
    OOJS_PROFILE_ENTER

    ShipEntity* thisEnt = nil;
    ShipEntity* target = nil;

    GET_THIS_SHIP(thisEnt);
    if (EXPECT_NOT(argc == 0 || (argc > 0 && (JS_IsNull(OOJS_ARGV[0]) || !JS_IsObject(OOJS_ARGV[0]) || !JSShipGetShipEntity(context, OOJS_ARGV[0], &target))))) {
        OOJSReportBadArguments(context, @"Ship", @"addDefenseTarget", 1U, OOJS_ARGV, nil, @"target");
        return OOJSNativeFailure(context);
    }

    [thisEnt addDefenseTarget:target];

    OOJS_RETURN_VOID;

    OOJS_PROFILE_EXIT
}

static JSValue ShipRemoveDefenseTarget(OOJS_NATIVE_ARGS)
{
    OOJS_PROFILE_ENTER

    ShipEntity* thisEnt = nil;
    ShipEntity* target = nil;

    GET_THIS_SHIP(thisEnt);
    if (EXPECT_NOT(argc == 0 || (argc > 0 && (JS_IsNull(OOJS_ARGV[0]) || !JS_IsObject(OOJS_ARGV[0]) || !JSShipGetShipEntity(context, OOJS_ARGV[0], &target))))) {
        OOJSReportBadArguments(context, @"Ship", @"removeDefenseTarget", 1U, OOJS_ARGV, nil, @"target");
        return OOJSNativeFailure(context);
    }

    [thisEnt removeDefenseTarget:target];

    OOJS_RETURN_VOID;

    OOJS_PROFILE_EXIT
}

static JSValue ShipAddCollisionException(OOJS_NATIVE_ARGS)
{
    OOJS_PROFILE_ENTER

    ShipEntity* thisEnt = nil;
    ShipEntity* target = nil;

    GET_THIS_SHIP(thisEnt);
    if (EXPECT_NOT(argc == 0 || (argc > 0 && (JS_IsNull(OOJS_ARGV[0]) || !JS_IsObject(OOJS_ARGV[0]) || !JSShipGetShipEntity(context, OOJS_ARGV[0], &target))))) {
        OOJSReportBadArguments(context, @"Ship", @"addCollisionException", 1U, OOJS_ARGV, nil, @"other ship");
        return OOJSNativeFailure(context);
    }

    // have to do it both ways because it's not defined which order
    // the collisions get tested in. More efficient to add both ways
    // than to test both ways
    [thisEnt addCollisionException:target];
    [target addCollisionException:thisEnt];

    OOJS_RETURN_VOID;

    OOJS_PROFILE_EXIT
}

static JSValue ShipRemoveCollisionException(OOJS_NATIVE_ARGS)
{
    OOJS_PROFILE_ENTER

    ShipEntity* thisEnt = nil;
    ShipEntity* target = nil;

    GET_THIS_SHIP(thisEnt);
    if (EXPECT_NOT(argc == 0 || (argc > 0 && (JS_IsNull(OOJS_ARGV[0]) || !JS_IsObject(OOJS_ARGV[0]) || !JSShipGetShipEntity(context, OOJS_ARGV[0], &target))))) {
        OOJSReportBadArguments(context, @"Ship", @"removeCollisionException", 1U, OOJS_ARGV, nil, @"other ship");
        return OOJSNativeFailure(context);
    }

    // doesn't need a check to see if it was already gone
    [thisEnt removeCollisionException:target];
    [target removeCollisionException:thisEnt];

    OOJS_RETURN_VOID;

    OOJS_PROFILE_EXIT
}

// getMaterials()
static JSValue ShipGetMaterials(OOJS_NATIVE_ARGS)
{
    OOJS_PROFILE_ENTER

    ShipEntity* thisEnt = nil;
    NSObject* result = nil;

    GET_THIS_SHIP(thisEnt);

    result = [[thisEnt mesh] materials];
    if (result == nil)
        result = [NSDictionary dictionary];
    OOJS_RETURN_OBJECT(result);

    OOJS_PROFILE_EXIT
}

// getShaders()
static JSValue ShipGetShaders(OOJS_NATIVE_ARGS)
{
    OOJS_PROFILE_ENTER

    ShipEntity* thisEnt = nil;
    NSObject* result = nil;

    GET_THIS_SHIP(thisEnt);

    result = [[thisEnt mesh] shaders];
    if (result == nil)
        result = [NSDictionary dictionary];
    OOJS_RETURN_OBJECT(result);

    OOJS_PROFILE_EXIT
}

static JSValue ShipBroadcastCascadeImminent(OOJS_NATIVE_ARGS)
{
    OOJS_PROFILE_ENTER

    ShipEntity* thisEnt = nil;
    GET_THIS_SHIP(thisEnt);
    [thisEnt broadcastEnergyBlastImminent];

    OOJS_RETURN_VOID;

    OOJS_PROFILE_EXIT
}

static JSValue ShipBecomeCascadeExplosion(OOJS_NATIVE_ARGS)
{
    OOJS_PROFILE_ENTER

    ShipEntity* thisEnt = nil;
    GET_THIS_SHIP(thisEnt);
    [thisEnt becomeEnergyBlast];

    OOJS_RETURN_VOID;

    OOJS_PROFILE_EXIT
}

static JSValue ShipOfferToEscort(OOJS_NATIVE_ARGS)
{
    OOJS_PROFILE_ENTER

    ShipEntity* thisEnt = nil;
    ShipEntity* mother = nil;

    GET_THIS_SHIP(thisEnt);
    if (EXPECT_NOT(argc == 0 || (argc > 0 && (JS_IsNull(OOJS_ARGV[0]) || !JS_IsObject(OOJS_ARGV[0]) || !JSShipGetShipEntity(context, OOJS_ARGV[0], &mother))))) {
        OOJSReportBadArguments(context, @"Ship", @"offerToEscort", 1U, OOJS_ARGV, nil, @"target");
        return OOJSNativeFailure(context);
    }

    BOOL result = [thisEnt suggestEscortTo:mother];

    OOJS_RETURN_BOOL(result);

    OOJS_PROFILE_EXIT
}

static JSValue ShipRequestHelpFromGroup(OOJS_NATIVE_ARGS)
{
    OOJS_PROFILE_ENTER

    ShipEntity* thisEnt = nil;

    GET_THIS_SHIP(thisEnt);

    [thisEnt groupAttackTarget];

    OOJS_RETURN_VOID;

    OOJS_PROFILE_EXIT
}

static JSValue ShipPatrolReportIn(OOJS_NATIVE_ARGS)
{
    OOJS_PROFILE_ENTER

    ShipEntity* thisEnt = nil;
    ShipEntity* target = nil;

    GET_THIS_SHIP(thisEnt);
    if (EXPECT_NOT(argc == 0 || (argc > 0 && (JS_IsNull(OOJS_ARGV[0]) || !JS_IsObject(OOJS_ARGV[0]) || !JSShipGetShipEntity(context, OOJS_ARGV[0], &target))))) {
        OOJSReportBadArguments(context, @"Ship", @"addDefenseTarget", 1U, OOJS_ARGV, nil, @"target");
        return OOJSNativeFailure(context);
    }
    if ([target isStation]) {
        StationEntity* station = (StationEntity*)target;
        [station acceptPatrolReportFrom:thisEnt];
    }

    OOJS_RETURN_VOID;

    OOJS_PROFILE_EXIT
}

static JSValue ShipMarkTargetForFines(OOJS_NATIVE_ARGS)
{
    OOJS_PROFILE_ENTER

    ShipEntity* thisEnt = nil;

    GET_THIS_SHIP(thisEnt);

    ShipEntity* ship = [thisEnt primaryTarget];
    BOOL ok = NO;
    if ((ship != nil) && ([ship status] != STATUS_DEAD) && ([ship status] != STATUS_DOCKED)) {
        ok = [ship markForFines];
    }

    OOJS_RETURN_BOOL(ok);

    OOJS_PROFILE_EXIT
}

static JSValue ShipEnterWormhole(OOJS_NATIVE_ARGS)
{
    OOJS_PROFILE_ENTER

    ShipEntity* thisEnt = nil;
    Entity* hole = nil;

    if ([PLAYER status] != STATUS_ENTERING_WITCHSPACE) {
        OOJSReportError(context, @"Cannot use this function while player's ship not entering witchspace.");
        return OOJSNativeFailure(context);
    }

    GET_THIS_SHIP(thisEnt);
    if (EXPECT_NOT(argc == 0 || (argc > 0 && !JS_IsNull(OOJS_ARGV[0]) && (!JS_IsObject(OOJS_ARGV[0]) || !OOJSEntityGetEntity(context, OOJS_ARGV[0], &hole))))) {
        [thisEnt enterPlayerWormhole];
    } else {
        if (![hole isWormhole]) {
            OOJSReportBadArguments(context, @"Ship", @"enterWormhole", 1U, OOJS_ARGV, nil, @"[wormhole]");
            return OOJSNativeFailure(context);
        }

        [thisEnt enterWormhole:(WormholeEntity*)hole];
    }

    OOJS_RETURN_VOID;

    OOJS_PROFILE_EXIT
}

static JSValue ShipNotifyGroupOfWormhole(OOJS_NATIVE_ARGS)
{
    OOJS_PROFILE_ENTER

    ShipEntity* thisEnt = nil;
    GET_THIS_SHIP(thisEnt);

    [thisEnt wormholeEntireGroup];

    OOJS_RETURN_VOID;

    OOJS_PROFILE_EXIT
}

static JSValue ShipThrowSpark(OOJS_NATIVE_ARGS)
{
    OOJS_PROFILE_ENTER

    ShipEntity* thisEnt = nil;
    GET_THIS_SHIP(thisEnt);
    [thisEnt setThrowSparks:YES];

    OOJS_RETURN_VOID;

    OOJS_PROFILE_EXIT
}

static JSValue ShipPerformAttack(OOJS_NATIVE_ARGS)
{
    OOJS_PROFILE_ENTER

    ShipEntity* thisEnt = nil;
    GET_THIS_SHIP(thisEnt);
    [thisEnt performAttack];

    OOJS_RETURN_VOID;

    OOJS_PROFILE_EXIT
}

static JSValue ShipPerformCollect(OOJS_NATIVE_ARGS)
{
    OOJS_PROFILE_ENTER

    ShipEntity* thisEnt = nil;
    GET_THIS_SHIP(thisEnt);
    [thisEnt performCollect];

    OOJS_RETURN_VOID;

    OOJS_PROFILE_EXIT
}

static JSValue ShipPerformEscort(OOJS_NATIVE_ARGS)
{
    OOJS_PROFILE_ENTER

    ShipEntity* thisEnt = nil;
    GET_THIS_SHIP(thisEnt);
    [thisEnt performEscort];

    OOJS_RETURN_VOID;

    OOJS_PROFILE_EXIT
}

static JSValue ShipPerformFaceDestination(OOJS_NATIVE_ARGS)
{
    OOJS_PROFILE_ENTER

    ShipEntity* thisEnt = nil;
    GET_THIS_SHIP(thisEnt);
    [thisEnt performFaceDestination];

    OOJS_RETURN_VOID;

    OOJS_PROFILE_EXIT
}

static JSValue ShipPerformFlee(OOJS_NATIVE_ARGS)
{
    OOJS_PROFILE_ENTER

    ShipEntity* thisEnt = nil;
    GET_THIS_SHIP(thisEnt);
    [thisEnt performFlee];

    OOJS_RETURN_VOID;

    OOJS_PROFILE_EXIT
}

static JSValue ShipPerformFlyToRangeFromDestination(OOJS_NATIVE_ARGS)
{
    OOJS_PROFILE_ENTER

    ShipEntity* thisEnt = nil;
    GET_THIS_SHIP(thisEnt);
    [thisEnt performFlyToRangeFromDestination];

    OOJS_RETURN_VOID;

    OOJS_PROFILE_EXIT
}

static JSValue ShipPerformHold(OOJS_NATIVE_ARGS)
{
    OOJS_PROFILE_ENTER

    ShipEntity* thisEnt = nil;
    GET_THIS_SHIP(thisEnt);
    [thisEnt performHold];

    OOJS_RETURN_VOID;

    OOJS_PROFILE_EXIT
}

static JSValue ShipPerformIdle(OOJS_NATIVE_ARGS)
{
    OOJS_PROFILE_ENTER

    ShipEntity* thisEnt = nil;
    GET_THIS_SHIP(thisEnt);
    [thisEnt performIdle];

    OOJS_RETURN_VOID;

    OOJS_PROFILE_EXIT
}

static JSValue ShipPerformIntercept(OOJS_NATIVE_ARGS)
{
    OOJS_PROFILE_ENTER

    ShipEntity* thisEnt = nil;
    GET_THIS_SHIP(thisEnt);
    [thisEnt performIntercept];

    OOJS_RETURN_VOID;

    OOJS_PROFILE_EXIT
}

static JSValue ShipPerformLandOnPlanet(OOJS_NATIVE_ARGS)
{
    OOJS_PROFILE_ENTER

    ShipEntity* thisEnt = nil;
    GET_THIS_SHIP(thisEnt);
    [thisEnt performLandOnPlanet];

    OOJS_RETURN_VOID;

    OOJS_PROFILE_EXIT
}

static JSValue ShipPerformMining(OOJS_NATIVE_ARGS)
{
    OOJS_PROFILE_ENTER

    ShipEntity* thisEnt = nil;
    GET_THIS_SHIP(thisEnt);
    [thisEnt performMining];

    OOJS_RETURN_VOID;

    OOJS_PROFILE_EXIT
}

static JSValue ShipPerformScriptedAI(OOJS_NATIVE_ARGS)
{
    OOJS_PROFILE_ENTER

    ShipEntity* thisEnt = nil;
    GET_THIS_SHIP(thisEnt);
    [thisEnt performScriptedAI];

    OOJS_RETURN_VOID;

    OOJS_PROFILE_EXIT
}

static JSValue ShipPerformScriptedAttackAI(OOJS_NATIVE_ARGS)
{
    OOJS_PROFILE_ENTER

    ShipEntity* thisEnt = nil;
    GET_THIS_SHIP(thisEnt);
    [thisEnt performScriptedAttackAI];

    OOJS_RETURN_VOID;

    OOJS_PROFILE_EXIT
}

static JSValue ShipPerformStop(OOJS_NATIVE_ARGS)
{
    OOJS_PROFILE_ENTER

    ShipEntity* thisEnt = nil;
    GET_THIS_SHIP(thisEnt);
    [thisEnt performStop];

    OOJS_RETURN_VOID;

    OOJS_PROFILE_EXIT
}

static JSValue ShipPerformTumble(OOJS_NATIVE_ARGS)
{
    OOJS_PROFILE_ENTER

    ShipEntity* thisEnt = nil;
    GET_THIS_SHIP(thisEnt);
    [thisEnt performTumble];

    OOJS_RETURN_VOID;

    OOJS_PROFILE_EXIT
}

static JSValue ShipRequestDockingInstructions(OOJS_NATIVE_ARGS)
{
    OOJS_PROFILE_ENTER

    ShipEntity* thisEnt = nil;
    GET_THIS_SHIP(thisEnt);
    [thisEnt requestDockingCoordinates];

    NSDictionary* dockingInstructions = [thisEnt dockingInstructions];
    if (dockingInstructions != nil) {
        OOJS_RETURN_OBJECT(dockingInstructions);
    } else {
        OOJS_RETURN_NULL;
    }

    OOJS_PROFILE_EXIT
}

static JSValue ShipRecallDockingInstructions(OOJS_NATIVE_ARGS)
{
    OOJS_PROFILE_ENTER

    ShipEntity* thisEnt = nil;
    GET_THIS_SHIP(thisEnt);
    [thisEnt recallDockingInstructions];

    NSDictionary* dockingInstructions = [thisEnt dockingInstructions];
    if (dockingInstructions != nil) {
        OOJS_RETURN_OBJECT(dockingInstructions);
    } else {
        OOJS_RETURN_NULL;
    }

    OOJS_PROFILE_EXIT
}

static JSValue ShipBroadcastDistressMessage(OOJS_NATIVE_ARGS)
{
    OOJS_PROFILE_ENTER

    ShipEntity* thisEnt = nil;
    GET_THIS_SHIP(thisEnt);
    [thisEnt broadcastDistressMessageWithDumping:NO];

    OOJS_RETURN_VOID;

    OOJS_PROFILE_EXIT
}

static JSValue ShipCheckCourseToDestination(OOJS_NATIVE_ARGS)
{
    OOJS_PROFILE_ENTER

    ShipEntity* thisEnt = nil;
    GET_THIS_SHIP(thisEnt);

    Entity* hazard = [UNIVERSE hazardOnRouteFromEntity:thisEnt toDistance:[thisEnt desiredRange] fromPoint:[thisEnt destination]];

    OOJS_RETURN_OBJECT(hazard);

    OOJS_PROFILE_EXIT
}

static JSValue ShipGetSafeCourseToDestination(OOJS_NATIVE_ARGS)
{
    OOJS_PROFILE_ENTER

    ShipEntity* thisEnt = nil;
    GET_THIS_SHIP(thisEnt);

    HPVector waypoint = [UNIVERSE getSafeVectorFromEntity:thisEnt toDistance:[thisEnt desiredRange] fromPoint:[thisEnt destination]];

    OOJS_RETURN_HPVECTOR(waypoint);

    OOJS_PROFILE_EXIT
}

static JSValue ShipCheckScanner(OOJS_NATIVE_ARGS)
{
    OOJS_PROFILE_ENTER

    ShipEntity* thisEnt = nil;
    int onlyCheckPowered = NO;

    GET_THIS_SHIP(thisEnt);

    if (argc > 0 && EXPECT_NOT(!((onlyCheckPowered = JS_ToBool(context, OOJS_ARGV[0])) >= 0))) {
        OOJSReportBadArguments(context, @"Ship", @"checkScanner", argc, OOJS_ARGV, nil, @"boolean");
        return OOJSNativeFailure(context);
    }

    if (onlyCheckPowered) {
        [thisEnt checkScannerIgnoringUnpowered];
    } else {
        [thisEnt checkScanner];
    }
    ShipEntity** scannedShips = [thisEnt scannedShips];
    unsigned num = [thisEnt numberOfScannedShips];
    NSMutableArray* scanResult = [NSMutableArray array];
    for (unsigned i = 0; i < num; i++) {
        [scanResult addObject:scannedShips[i]];
    }
    OOJS_RETURN_OBJECT(scanResult);

    OOJS_PROFILE_EXIT
}

static JSValue ShipAdjustCargo(OOJS_NATIVE_ARGS)
{
    OOJS_PROFILE_ENTER

    ShipEntity* thisEnt = nil;
    NSString* commodity = @"";
    int32_t adjustment = 0;

    GET_THIS_SHIP(thisEnt);

    if (argc < 2) {
        OOJSReportBadArguments(context, @"Ship", @"adjustCargo", argc, OOJS_ARGV, nil, @"commodity, amount");
        return OOJSNativeFailure(context);
    }

    commodity = OOStringFromJSValue(context, OOJS_ARGV[0]);
    if (!OOJSValueToInt32(context, OOJS_ARGV[1], &adjustment)) {
        OOJSReportBadArguments(context, @"Ship", @"adjustCargo", argc, OOJS_ARGV, nil, @"commodity, amount");
        return OOJSNativeFailure(context);
    }

    if ([thisEnt cargoType] != CARGO_NOT_CARGO || [thisEnt isPlayer]) {
        OOJSReportError(context, @"ship.adjustCargo may only be used on NPC cargo carriers");
        return OOJSNativeFailure(context);
    }

    BOOL ok = YES;

    if (adjustment > 0) {
        NSArray* cargo = [UNIVERSE getContainersOfCommodity:commodity how_much:adjustment]; // non-reified templates
        ok = [thisEnt addCargo:cargo];
    } else if (adjustment < 0) {
        OOCargoQuantity r = (OOCargoQuantity)(-adjustment);
        ok = [thisEnt removeCargo:commodity amount:r];
    }

    OOJS_RETURN_BOOL(ok);

    OOJS_PROFILE_EXIT
}

/* 0 = no significant damage or consumable loss, higher numbers mean some */
static JSValue ShipDamageAssessment(OOJS_NATIVE_ARGS)
{
    OOJS_PROFILE_ENTER

    ShipEntity* thisEnt = nil;
    int assessment = 0;

    GET_THIS_SHIP(thisEnt);

    // if could have missiles but doesn't, consumables low
    if ([thisEnt missileCapacity] > 0 && [[thisEnt missilesList] count] == 0) {
        assessment++;
    }
    // if has injectors but fuel is low, consumables low
    // if no injectors, not a problem
    if ([thisEnt hasFuelInjection] && [thisEnt fuel] < 35) {
        assessment++;
    }

    /* TODO: when NPC equipment can be damaged in combat, assess this
     * here */

    OOJS_RETURN_INT(assessment);

    OOJS_PROFILE_EXIT
}

static JSValue ShipThreatAssessment(OOJS_NATIVE_ARGS)
{
    OOJS_PROFILE_ENTER

    ShipEntity* thisEnt = nil;
    int fullCheck = NO;

    GET_THIS_SHIP(thisEnt);

    if (argc > 0 && EXPECT_NOT(!((fullCheck = JS_ToBool(context, OOJS_ARGV[0])) >= 0))) {
        OOJSReportBadArguments(context, @"Ship", @"threatAssessment", argc, OOJS_ARGV, nil, @"boolean");
        return OOJSNativeFailure(context);
    }
    // start with 2.5 per ship
    double assessment = 2.5;
    // +/- 0.1 for speed, larger subtraction for very slow ships
    GLfloat maxspeed = [thisEnt maxFlightSpeed];
    assessment += (maxspeed - 300) / 1000;
    if (maxspeed < 200) {
        assessment += (maxspeed - 200) / 500;
    }

    /* FIXME: at the moment this means NPCs can detect other NPCs shield
     * boosters, since they're implemented as extra energy */
    assessment += ([thisEnt maxEnergy] - 200) / 1000;

    // add on some for missiles. Mostly ignore 3rd and subsequent
    // missiles: either they can be ECMd or the first two are already
    // too many.
    if ([thisEnt missileCapacity] > 2) {
        assessment += 0.5;
    } else {
        assessment += ((double)[thisEnt missileCapacity]) / 5.0;
    }

    /* Turret count is public knowledge */
    /* TODO: consider making ship combat behaviour try to
     * stay at long range from enemies with turrets. Then
     * we could perhaps reduce this bonus a bit. */
    assessment += [thisEnt turretCount];

    if (fullCheck) {
        // consider pilot skill
        if ([thisEnt isPlayer]) {
            double score = (double)[PLAYER score];
            if (score > 6400) {
                score = 6400;
            }
            assessment += pow(score, 0.33) / 10;
            // 0 - 1.8
        } else {
            assessment += [thisEnt accuracy] / 5;
        }

        // check lasers
        OOWeaponType wt = [thisEnt weaponTypeIDForFacing:WEAPON_FACING_FORWARD strict:NO];
        /* Not affected by multiple mounts here: they're either just a
         * split of the power, or only more dangerous until they
         * overheat */
        assessment += ShipThreatAssessmentWeapon(wt);
        if (isWeaponNone(wt)) {
            assessment -= 1.5; // further penalty for ships with no forward laser
        }

        wt = [thisEnt weaponTypeIDForFacing:WEAPON_FACING_AFT strict:NO];
        if (!isWeaponNone(wt)) {
            assessment += 1 + ShipThreatAssessmentWeapon(wt);
        }
        // port and starboard weapons less important
        wt = [thisEnt weaponTypeIDForFacing:WEAPON_FACING_PORT strict:NO];
        if (!isWeaponNone(wt)) {
            assessment += 0.2 + ShipThreatAssessmentWeapon(wt) / 5.0;
        }
        wt = [thisEnt weaponTypeIDForFacing:WEAPON_FACING_STARBOARD strict:NO];
        if (!isWeaponNone(wt)) {
            assessment += 0.2 + ShipThreatAssessmentWeapon(wt) / 5.0;
        }

        // combat-related secondary equipment
        if ([thisEnt hasECM]) {
            assessment += 0.5;
        }
        if ([thisEnt hasFuelInjection]) {
            assessment += 0.5;
        }

    } else {
        // consider thargoids dangerous
        if ([thisEnt isThargoid]) {
            assessment *= 1.5;
            if ([thisEnt hasRole:@"thargoid-mothership"]) {
                assessment += 5;
            }
        } else {
            // consider that armed ships might have a trick or two
            if ([thisEnt weaponFacings] == 1) {
                assessment += 0.25;
            } else {
                // and more than one trick if they can mount multiple lasers
                assessment += 0.5;
            }
        }
    }

    // mostly ignore fleeing ships as threats
    if ([thisEnt behaviour] == BEHAVIOUR_FLEE_TARGET || [thisEnt behaviour] == BEHAVIOUR_FLEE_EVASIVE_ACTION) {
        assessment *= 0.2;
    } else if ([thisEnt isPlayer] && [(PlayerEntity*)thisEnt fleeingStatus] >= PLAYER_FLEEING_CARGO) {
        assessment *= 0.2;
    }

    // don't go too low.
    if (assessment < 0.1) {
        assessment = 0.1;
    }

    OOJS_RETURN_DOUBLE(assessment);

    OOJS_PROFILE_EXIT
}

static double ShipThreatAssessmentWeapon(OOWeaponType wt)
{
    if (wt == nil) {
        return -1.0;
    }
    return [wt weaponThreatAssessment];
}

/** Static methods */

static JSValue ShipStaticKeys(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context);
    OOShipRegistry* registry = [OOShipRegistry sharedRegistry];

    NSArray* keys = [registry shipKeys];
    OOJS_RETURN_OBJECT(keys);

    OOJS_NATIVE_EXIT
}

static JSValue ShipStaticKeysForRole(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context);
    OOShipRegistry* registry = [OOShipRegistry sharedRegistry];

    if (argc > 0) {
        NSString* role = OOStringFromJSValue(context, OOJS_ARGV[0]);
        NSArray* keys = [registry shipKeysWithRole:role];
        OOJS_RETURN_OBJECT(keys);
    } else {
        OOJSReportBadArguments(context, @"Ship", @"shipKeysForRole", MIN(argc, 1), OOJS_ARGV, nil, @"ship role");
        return OOJSNativeFailure(context);
    }

    OOJS_NATIVE_EXIT
}

static JSValue ShipStaticRoleIsInCategory(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context);

    if (argc > 1) {
        NSString* role = OOStringFromJSValue(context, OOJS_ARGV[0]);
        NSString* category = OOStringFromJSValue(context, OOJS_ARGV[1]);

        OOJS_RETURN_BOOL([UNIVERSE role:role isInCategory:category]);
    } else {
        OOJSReportBadArguments(context, @"Ship", @"roleIsInCategory", MIN(argc, 2), OOJS_ARGV, nil, @"role, category");
        return OOJSNativeFailure(context);
    }

    OOJS_NATIVE_EXIT
}

static JSValue ShipStaticRoles(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context);
    OOShipRegistry* registry = [OOShipRegistry sharedRegistry];

    NSArray* keys = [registry shipRoles];
    OOJS_RETURN_OBJECT(keys);

    OOJS_NATIVE_EXIT
}

static JSValue ShipStaticShipDataForKey(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context);
    OOShipRegistry* registry = [OOShipRegistry sharedRegistry];

    if (argc > 0) {
        NSString* key = OOStringFromJSValue(context, OOJS_ARGV[0]);
        NSDictionary* keys = [registry shipInfoForKey:key];
        OOJS_RETURN_OBJECT(keys);
    } else {
        OOJSReportBadArguments(context, @"Ship", @"shipDataForKey", MIN(argc, 1), OOJS_ARGV, nil, @"key");
        return OOJSNativeFailure(context);
    }
    OOJS_NATIVE_EXIT
}

static JSValue ShipStaticSetShipDataForKey(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context);
    OOShipRegistry* registry = [OOShipRegistry sharedRegistry];

    if (argc >= 2) {
        NSString* key = OOStringFromJSValue(context, OOJS_ARGV[0]);
        NSDictionary* newShipData = OOJSNativeObjectFromJSObject(context, OOJS_ARGV[1]);
        [registry setShipInfoForKey:key with:newShipData];
        OOJS_RETURN_BOOL(YES);
    } else {
        OOJSReportBadArguments(context, @"Ship", @"setShipInfoForKey", MIN(argc, 2), OOJS_ARGV, nil, @"key shipdata");
        return OOJSNativeFailure(context);
    }
    OOJS_NATIVE_EXIT
}
