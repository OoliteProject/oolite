/*	OOBehaviour.h

The values of a ship's behaviour: callObjC (encoded "i", OOTypeEncodings.h) and
the AI's logs, and the names the game reads and writes for them. It was
OOBehaviour.tbl, an X-macro table.
*/

#pragma once

#include <cstdint>
#include <string_view>

#include "OOEnumFlags.h"
#include "OOEnumTable.h"

enum class OOBehaviour : std::int32_t {
  kIdle = 0,
  kTrackTarget = 1,
  kTumble = 4,
  kStopStill = 5,
  kStationKeeping = 10,
  kAttackTarget = 101,
  kAttackFlyToTarget = 102,
  kAttackFlyFromTarget = 103,
  kRunningDefense = 104,
  // fleeing
  kFleeTarget = 105,
  // advanced combat...
  kAttackFlyToTargetSix = 106,
  kAttackMiningTarget = 107,
  kEvasiveAction = 108,
  kFleeEvasiveAction = 109,
  kAttackBreakOffTarget = 110,
  kAttackSlowDogfight = 111,
  // further advanced combat...
  kAttackFlyToTargetTwelve = 112,
  kAttackSniper = 113,
  // side weapon combat...
  kAttackBroadside = 115,
  kAttackBroadsideLeft = 116,
  kAttackBroadsideRight = 117,
  kCloseToBroadsideRange = 118,
  kCloseWithTarget = 125,
  kAvoidCollision = 130,
  kTrackAsTurret = 150,
  kFlyRangeFromDestination = 200,
  kFlyToDestination = 201,
  kFlyFromDestination = 202,
  kFaceDestination = 203,
  kFlyThruNavpoints = 210,
  kLandOnPlanet = 250,
  kCollectTarget = 300,
  kInterceptTarget = 350,
  kFormationFormUp = 501,
  kFormationBreak = 502,
  kEnergyBombCountdown = 601,
  kTractored = 701,
  kScriptedAi = 801,
  kScriptedAttackAi = 811,
};

// The name of each value. No default: -Wswitch reports a value added without
// one.
constexpr std::string_view OOEnumName(OOBehaviour value) noexcept {
  switch (value) {
    case OOBehaviour::kIdle:
      return "BEHAVIOUR_IDLE";
    case OOBehaviour::kTrackTarget:
      return "BEHAVIOUR_TRACK_TARGET";
    case OOBehaviour::kTumble:
      return "BEHAVIOUR_TUMBLE";
    case OOBehaviour::kStopStill:
      return "BEHAVIOUR_STOP_STILL";
    case OOBehaviour::kStationKeeping:
      return "BEHAVIOUR_STATION_KEEPING";
    case OOBehaviour::kAttackTarget:
      return "BEHAVIOUR_ATTACK_TARGET";
    case OOBehaviour::kAttackFlyToTarget:
      return "BEHAVIOUR_ATTACK_FLY_TO_TARGET";
    case OOBehaviour::kAttackFlyFromTarget:
      return "BEHAVIOUR_ATTACK_FLY_FROM_TARGET";
    case OOBehaviour::kRunningDefense:
      return "BEHAVIOUR_RUNNING_DEFENSE";
    case OOBehaviour::kFleeTarget:
      return "BEHAVIOUR_FLEE_TARGET";
    case OOBehaviour::kAttackFlyToTargetSix:
      return "BEHAVIOUR_ATTACK_FLY_TO_TARGET_SIX";
    case OOBehaviour::kAttackMiningTarget:
      return "BEHAVIOUR_ATTACK_MINING_TARGET";
    case OOBehaviour::kEvasiveAction:
      return "BEHAVIOUR_EVASIVE_ACTION";
    case OOBehaviour::kFleeEvasiveAction:
      return "BEHAVIOUR_FLEE_EVASIVE_ACTION";
    case OOBehaviour::kAttackBreakOffTarget:
      return "BEHAVIOUR_ATTACK_BREAK_OFF_TARGET";
    case OOBehaviour::kAttackSlowDogfight:
      return "BEHAVIOUR_ATTACK_SLOW_DOGFIGHT";
    case OOBehaviour::kAttackFlyToTargetTwelve:
      return "BEHAVIOUR_ATTACK_FLY_TO_TARGET_TWELVE";
    case OOBehaviour::kAttackSniper:
      return "BEHAVIOUR_ATTACK_SNIPER";
    case OOBehaviour::kAttackBroadside:
      return "BEHAVIOUR_ATTACK_BROADSIDE";
    case OOBehaviour::kAttackBroadsideLeft:
      return "BEHAVIOUR_ATTACK_BROADSIDE_LEFT";
    case OOBehaviour::kAttackBroadsideRight:
      return "BEHAVIOUR_ATTACK_BROADSIDE_RIGHT";
    case OOBehaviour::kCloseToBroadsideRange:
      return "BEHAVIOUR_CLOSE_TO_BROADSIDE_RANGE";
    case OOBehaviour::kCloseWithTarget:
      return "BEHAVIOUR_CLOSE_WITH_TARGET";
    case OOBehaviour::kAvoidCollision:
      return "BEHAVIOUR_AVOID_COLLISION";
    case OOBehaviour::kTrackAsTurret:
      return "BEHAVIOUR_TRACK_AS_TURRET";
    case OOBehaviour::kFlyRangeFromDestination:
      return "BEHAVIOUR_FLY_RANGE_FROM_DESTINATION";
    case OOBehaviour::kFlyToDestination:
      return "BEHAVIOUR_FLY_TO_DESTINATION";
    case OOBehaviour::kFlyFromDestination:
      return "BEHAVIOUR_FLY_FROM_DESTINATION";
    case OOBehaviour::kFaceDestination:
      return "BEHAVIOUR_FACE_DESTINATION";
    case OOBehaviour::kFlyThruNavpoints:
      return "BEHAVIOUR_FLY_THRU_NAVPOINTS";
    case OOBehaviour::kLandOnPlanet:
      return "BEHAVIOUR_LAND_ON_PLANET";
    case OOBehaviour::kCollectTarget:
      return "BEHAVIOUR_COLLECT_TARGET";
    case OOBehaviour::kInterceptTarget:
      return "BEHAVIOUR_INTERCEPT_TARGET";
    case OOBehaviour::kFormationFormUp:
      return "BEHAVIOUR_FORMATION_FORM_UP";
    case OOBehaviour::kFormationBreak:
      return "BEHAVIOUR_FORMATION_BREAK";
    case OOBehaviour::kEnergyBombCountdown:
      return "BEHAVIOUR_ENERGY_BOMB_COUNTDOWN";
    case OOBehaviour::kTractored:
      return "BEHAVIOUR_TRACTORED";
    case OOBehaviour::kScriptedAi:
      return "BEHAVIOUR_SCRIPTED_AI";
    case OOBehaviour::kScriptedAttackAi:
      return "BEHAVIOUR_SCRIPTED_ATTACK_AI";
  }
  return {};
}

inline constexpr auto kOOBehaviourTable = oo::MakeEnumTable<
    OOBehaviour, OOBehaviour::kIdle, OOBehaviour::kTrackTarget,
    OOBehaviour::kTumble, OOBehaviour::kStopStill, OOBehaviour::kStationKeeping,
    OOBehaviour::kAttackTarget, OOBehaviour::kAttackFlyToTarget,
    OOBehaviour::kAttackFlyFromTarget, OOBehaviour::kRunningDefense,
    OOBehaviour::kFleeTarget, OOBehaviour::kAttackFlyToTargetSix,
    OOBehaviour::kAttackMiningTarget, OOBehaviour::kEvasiveAction,
    OOBehaviour::kFleeEvasiveAction, OOBehaviour::kAttackBreakOffTarget,
    OOBehaviour::kAttackSlowDogfight, OOBehaviour::kAttackFlyToTargetTwelve,
    OOBehaviour::kAttackSniper, OOBehaviour::kAttackBroadside,
    OOBehaviour::kAttackBroadsideLeft, OOBehaviour::kAttackBroadsideRight,
    OOBehaviour::kCloseToBroadsideRange, OOBehaviour::kCloseWithTarget,
    OOBehaviour::kAvoidCollision, OOBehaviour::kTrackAsTurret,
    OOBehaviour::kFlyRangeFromDestination, OOBehaviour::kFlyToDestination,
    OOBehaviour::kFlyFromDestination, OOBehaviour::kFaceDestination,
    OOBehaviour::kFlyThruNavpoints, OOBehaviour::kLandOnPlanet,
    OOBehaviour::kCollectTarget, OOBehaviour::kInterceptTarget,
    OOBehaviour::kFormationFormUp, OOBehaviour::kFormationBreak,
    OOBehaviour::kEnergyBombCountdown, OOBehaviour::kTractored,
    OOBehaviour::kScriptedAi, OOBehaviour::kScriptedAttackAi>();

// Every number that leaves the program, pinned.
static_assert(oo::ToUnderlying(OOBehaviour::kIdle) == 0);
static_assert(oo::ToUnderlying(OOBehaviour::kTrackTarget) == 1);
static_assert(oo::ToUnderlying(OOBehaviour::kTumble) == 4);
static_assert(oo::ToUnderlying(OOBehaviour::kStopStill) == 5);
static_assert(oo::ToUnderlying(OOBehaviour::kStationKeeping) == 10);
static_assert(oo::ToUnderlying(OOBehaviour::kAttackTarget) == 101);
static_assert(oo::ToUnderlying(OOBehaviour::kAttackFlyToTarget) == 102);
static_assert(oo::ToUnderlying(OOBehaviour::kAttackFlyFromTarget) == 103);
static_assert(oo::ToUnderlying(OOBehaviour::kRunningDefense) == 104);
static_assert(oo::ToUnderlying(OOBehaviour::kFleeTarget) == 105);
static_assert(oo::ToUnderlying(OOBehaviour::kAttackFlyToTargetSix) == 106);
static_assert(oo::ToUnderlying(OOBehaviour::kAttackMiningTarget) == 107);
static_assert(oo::ToUnderlying(OOBehaviour::kEvasiveAction) == 108);
static_assert(oo::ToUnderlying(OOBehaviour::kFleeEvasiveAction) == 109);
static_assert(oo::ToUnderlying(OOBehaviour::kAttackBreakOffTarget) == 110);
static_assert(oo::ToUnderlying(OOBehaviour::kAttackSlowDogfight) == 111);
static_assert(oo::ToUnderlying(OOBehaviour::kAttackFlyToTargetTwelve) == 112);
static_assert(oo::ToUnderlying(OOBehaviour::kAttackSniper) == 113);
static_assert(oo::ToUnderlying(OOBehaviour::kAttackBroadside) == 115);
static_assert(oo::ToUnderlying(OOBehaviour::kAttackBroadsideLeft) == 116);
static_assert(oo::ToUnderlying(OOBehaviour::kAttackBroadsideRight) == 117);
static_assert(oo::ToUnderlying(OOBehaviour::kCloseToBroadsideRange) == 118);
static_assert(oo::ToUnderlying(OOBehaviour::kCloseWithTarget) == 125);
static_assert(oo::ToUnderlying(OOBehaviour::kAvoidCollision) == 130);
static_assert(oo::ToUnderlying(OOBehaviour::kTrackAsTurret) == 150);
static_assert(oo::ToUnderlying(OOBehaviour::kFlyRangeFromDestination) == 200);
static_assert(oo::ToUnderlying(OOBehaviour::kFlyToDestination) == 201);
static_assert(oo::ToUnderlying(OOBehaviour::kFlyFromDestination) == 202);
static_assert(oo::ToUnderlying(OOBehaviour::kFaceDestination) == 203);
static_assert(oo::ToUnderlying(OOBehaviour::kFlyThruNavpoints) == 210);
static_assert(oo::ToUnderlying(OOBehaviour::kLandOnPlanet) == 250);
static_assert(oo::ToUnderlying(OOBehaviour::kCollectTarget) == 300);
static_assert(oo::ToUnderlying(OOBehaviour::kInterceptTarget) == 350);
static_assert(oo::ToUnderlying(OOBehaviour::kFormationFormUp) == 501);
static_assert(oo::ToUnderlying(OOBehaviour::kFormationBreak) == 502);
static_assert(oo::ToUnderlying(OOBehaviour::kEnergyBombCountdown) == 601);
static_assert(oo::ToUnderlying(OOBehaviour::kTractored) == 701);
static_assert(oo::ToUnderlying(OOBehaviour::kScriptedAi) == 801);
static_assert(oo::ToUnderlying(OOBehaviour::kScriptedAttackAi) == 811);
