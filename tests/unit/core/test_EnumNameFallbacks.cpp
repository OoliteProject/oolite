/*	test_EnumNameFallbacks.cpp
        Spec 009 (T011, FR-016): the names the game reads and writes for its enums, pinned before
   the enums change. For every enum with a name lookup in OOConstToString.cpp and
   OOConstToJSString.cpp: each value's exact string, each known name's value, and the value an
   unknown name falls back to. Every string here is written out: written from today's
   OOConstToString.cpp and Tables/*.tbl by a script (the fallbacks resolved to the enumerators they name today), and only ever added to. Run:
   tests/run.sh unit
*/

#include <quickjs.h>

#include <string>

#include "OOConstToJSString.h"
#include "OOConstToString.h"
#include "OOOpenGL.h"
#include "OOTypes.h"
#include "PlayerEntity.h"
#include "ShipEntity.h"
#include "oo_test.hpp"

OO_TEST(OOStringFromEntityStatus) {
  OO_CHECK(OOStringFromEntityStatus(OOEntityStatus::kStartGame) == "STATUS_START_GAME");
  OO_CHECK(OOStringFromEntityStatus(OOEntityStatus::kRestartGame) == "STATUS_RESTART_GAME");
  OO_CHECK(OOStringFromEntityStatus(OOEntityStatus::kDead) == "STATUS_DEAD");
  OO_CHECK(OOStringFromEntityStatus(OOEntityStatus::kInactive) == "STATUS_INACTIVE");
  OO_CHECK(OOStringFromEntityStatus(OOEntityStatus::kTest) == "STATUS_TEST");
  OO_CHECK(OOStringFromEntityStatus(OOEntityStatus::kCockpitDisplay) == "STATUS_COCKPIT_DISPLAY");
  OO_CHECK(OOStringFromEntityStatus(OOEntityStatus::kActive) == "STATUS_ACTIVE");
  OO_CHECK(OOStringFromEntityStatus(OOEntityStatus::kEffect) == "STATUS_EFFECT");
  OO_CHECK(OOStringFromEntityStatus(OOEntityStatus::kInFlight) == "STATUS_IN_FLIGHT");
  OO_CHECK(OOStringFromEntityStatus(OOEntityStatus::kDocked) == "STATUS_DOCKED");
  OO_CHECK(OOStringFromEntityStatus(OOEntityStatus::kAutopilotEngaged) == "STATUS_AUTOPILOT_ENGAGED");
  OO_CHECK(OOStringFromEntityStatus(OOEntityStatus::kDocking) == "STATUS_DOCKING");
  OO_CHECK(OOStringFromEntityStatus(OOEntityStatus::kLaunching) == "STATUS_LAUNCHING");
  OO_CHECK(OOStringFromEntityStatus(OOEntityStatus::kWitchspaceCountdown) == "STATUS_WITCHSPACE_COUNTDOWN");
  OO_CHECK(OOStringFromEntityStatus(OOEntityStatus::kEnteringWitchspace) == "STATUS_ENTERING_WITCHSPACE");
  OO_CHECK(OOStringFromEntityStatus(OOEntityStatus::kExitingWitchspace) == "STATUS_EXITING_WITCHSPACE");
  OO_CHECK(OOStringFromEntityStatus(OOEntityStatus::kEscapeSequence) == "STATUS_ESCAPE_SEQUENCE");
  OO_CHECK(OOStringFromEntityStatus(OOEntityStatus::kInHold) == "STATUS_IN_HOLD");
  OO_CHECK(OOStringFromEntityStatus(OOEntityStatus::kBeingScooped) == "STATUS_BEING_SCOOPED");
  OO_CHECK(OOStringFromEntityStatus(OOEntityStatus::kHandlingError) == "STATUS_HANDLING_ERROR");
}

OO_TEST(OOStringFromBehaviour) {
  OO_CHECK(OOStringFromBehaviour(OOBehaviour::kIdle) == "BEHAVIOUR_IDLE");
  OO_CHECK(OOStringFromBehaviour(OOBehaviour::kTrackTarget) == "BEHAVIOUR_TRACK_TARGET");
  OO_CHECK(OOStringFromBehaviour(OOBehaviour::kTumble) == "BEHAVIOUR_TUMBLE");
  OO_CHECK(OOStringFromBehaviour(OOBehaviour::kStopStill) == "BEHAVIOUR_STOP_STILL");
  OO_CHECK(OOStringFromBehaviour(OOBehaviour::kStationKeeping) == "BEHAVIOUR_STATION_KEEPING");
  OO_CHECK(OOStringFromBehaviour(OOBehaviour::kAttackTarget) == "BEHAVIOUR_ATTACK_TARGET");
  OO_CHECK(OOStringFromBehaviour(OOBehaviour::kAttackFlyToTarget) == "BEHAVIOUR_ATTACK_FLY_TO_TARGET");
  OO_CHECK(OOStringFromBehaviour(OOBehaviour::kAttackFlyFromTarget) == "BEHAVIOUR_ATTACK_FLY_FROM_TARGET");
  OO_CHECK(OOStringFromBehaviour(OOBehaviour::kRunningDefense) == "BEHAVIOUR_RUNNING_DEFENSE");
  OO_CHECK(OOStringFromBehaviour(OOBehaviour::kFleeTarget) == "BEHAVIOUR_FLEE_TARGET");
  OO_CHECK(OOStringFromBehaviour(OOBehaviour::kAttackFlyToTargetSix) == "BEHAVIOUR_ATTACK_FLY_TO_TARGET_SIX");
  OO_CHECK(OOStringFromBehaviour(OOBehaviour::kAttackMiningTarget) == "BEHAVIOUR_ATTACK_MINING_TARGET");
  OO_CHECK(OOStringFromBehaviour(OOBehaviour::kEvasiveAction) == "BEHAVIOUR_EVASIVE_ACTION");
  OO_CHECK(OOStringFromBehaviour(OOBehaviour::kFleeEvasiveAction) == "BEHAVIOUR_FLEE_EVASIVE_ACTION");
  OO_CHECK(OOStringFromBehaviour(OOBehaviour::kAttackBreakOffTarget) == "BEHAVIOUR_ATTACK_BREAK_OFF_TARGET");
  OO_CHECK(OOStringFromBehaviour(OOBehaviour::kAttackSlowDogfight) == "BEHAVIOUR_ATTACK_SLOW_DOGFIGHT");
  OO_CHECK(OOStringFromBehaviour(OOBehaviour::kAttackFlyToTargetTwelve) == "BEHAVIOUR_ATTACK_FLY_TO_TARGET_TWELVE");
  OO_CHECK(OOStringFromBehaviour(OOBehaviour::kAttackSniper) == "BEHAVIOUR_ATTACK_SNIPER");
  OO_CHECK(OOStringFromBehaviour(OOBehaviour::kAttackBroadside) == "BEHAVIOUR_ATTACK_BROADSIDE");
  OO_CHECK(OOStringFromBehaviour(OOBehaviour::kAttackBroadsideLeft) == "BEHAVIOUR_ATTACK_BROADSIDE_LEFT");
  OO_CHECK(OOStringFromBehaviour(OOBehaviour::kAttackBroadsideRight) == "BEHAVIOUR_ATTACK_BROADSIDE_RIGHT");
  OO_CHECK(OOStringFromBehaviour(OOBehaviour::kCloseToBroadsideRange) == "BEHAVIOUR_CLOSE_TO_BROADSIDE_RANGE");
  OO_CHECK(OOStringFromBehaviour(OOBehaviour::kCloseWithTarget) == "BEHAVIOUR_CLOSE_WITH_TARGET");
  OO_CHECK(OOStringFromBehaviour(OOBehaviour::kAvoidCollision) == "BEHAVIOUR_AVOID_COLLISION");
  OO_CHECK(OOStringFromBehaviour(OOBehaviour::kTrackAsTurret) == "BEHAVIOUR_TRACK_AS_TURRET");
  OO_CHECK(OOStringFromBehaviour(OOBehaviour::kFlyRangeFromDestination) == "BEHAVIOUR_FLY_RANGE_FROM_DESTINATION");
  OO_CHECK(OOStringFromBehaviour(OOBehaviour::kFlyToDestination) == "BEHAVIOUR_FLY_TO_DESTINATION");
  OO_CHECK(OOStringFromBehaviour(OOBehaviour::kFlyFromDestination) == "BEHAVIOUR_FLY_FROM_DESTINATION");
  OO_CHECK(OOStringFromBehaviour(OOBehaviour::kFaceDestination) == "BEHAVIOUR_FACE_DESTINATION");
  OO_CHECK(OOStringFromBehaviour(OOBehaviour::kFlyThruNavpoints) == "BEHAVIOUR_FLY_THRU_NAVPOINTS");
  OO_CHECK(OOStringFromBehaviour(OOBehaviour::kLandOnPlanet) == "BEHAVIOUR_LAND_ON_PLANET");
  OO_CHECK(OOStringFromBehaviour(OOBehaviour::kCollectTarget) == "BEHAVIOUR_COLLECT_TARGET");
  OO_CHECK(OOStringFromBehaviour(OOBehaviour::kInterceptTarget) == "BEHAVIOUR_INTERCEPT_TARGET");
  OO_CHECK(OOStringFromBehaviour(OOBehaviour::kFormationFormUp) == "BEHAVIOUR_FORMATION_FORM_UP");
  OO_CHECK(OOStringFromBehaviour(OOBehaviour::kFormationBreak) == "BEHAVIOUR_FORMATION_BREAK");
  OO_CHECK(OOStringFromBehaviour(OOBehaviour::kEnergyBombCountdown) == "BEHAVIOUR_ENERGY_BOMB_COUNTDOWN");
  OO_CHECK(OOStringFromBehaviour(OOBehaviour::kTractored) == "BEHAVIOUR_TRACTORED");
  OO_CHECK(OOStringFromBehaviour(OOBehaviour::kScriptedAi) == "BEHAVIOUR_SCRIPTED_AI");
  OO_CHECK(OOStringFromBehaviour(OOBehaviour::kScriptedAttackAi) == "BEHAVIOUR_SCRIPTED_ATTACK_AI");
}

OO_TEST(OOStringFromCompassMode) {
  OO_CHECK(OOStringFromCompassMode(OOCompassMode::kInactive) == "COMPASS_MODE_INACTIVE");
  OO_CHECK(OOStringFromCompassMode(OOCompassMode::kBasic) == "COMPASS_MODE_BASIC");
  OO_CHECK(OOStringFromCompassMode(OOCompassMode::kPlanet) == "COMPASS_MODE_PLANET");
  OO_CHECK(OOStringFromCompassMode(OOCompassMode::kStation) == "COMPASS_MODE_STATION");
  OO_CHECK(OOStringFromCompassMode(OOCompassMode::kSun) == "COMPASS_MODE_SUN");
  OO_CHECK(OOStringFromCompassMode(OOCompassMode::kTarget) == "COMPASS_MODE_TARGET");
  OO_CHECK(OOStringFromCompassMode(OOCompassMode::kBeacons) == "COMPASS_MODE_BEACONS");
}

OO_TEST(OOStringFromLongRangeChartMode) {
  OO_CHECK(OOStringFromLongRangeChartMode(OOLongRangeChartMode::kUnknown) == "OOLRC_MODE_UNKNOWN");
  OO_CHECK(OOStringFromLongRangeChartMode(OOLongRangeChartMode::kSunColor) == "OOLRC_MODE_SUNCOLOR");
  OO_CHECK(OOStringFromLongRangeChartMode(OOLongRangeChartMode::kEconomy) == "OOLRC_MODE_ECONOMY");
  OO_CHECK(OOStringFromLongRangeChartMode(OOLongRangeChartMode::kGovernment) == "OOLRC_MODE_GOVERNMENT");
  OO_CHECK(OOStringFromLongRangeChartMode(OOLongRangeChartMode::kTechLevel) == "OOLRC_MODE_TECHLEVEL");
}

OO_TEST(OOStringFromGalacticHyperspaceBehaviour) {
  OO_CHECK(OOStringFromGalacticHyperspaceBehaviour(OOGalacticHyperspaceBehaviour::kStandard) == "BEHAVIOUR_STANDARD");
  OO_CHECK(OOStringFromGalacticHyperspaceBehaviour(OOGalacticHyperspaceBehaviour::kAllSystemsReachable) == "BEHAVIOUR_ALL_SYSTEMS_REACHABLE");
  OO_CHECK(OOStringFromGalacticHyperspaceBehaviour(OOGalacticHyperspaceBehaviour::kFixedCoordinates) == "BEHAVIOUR_FIXED_COORDINATES");
  OO_CHECK(OOStringFromGalacticHyperspaceBehaviour(OOGalacticHyperspaceBehaviour::kUnknown) == "BEHAVIOUR_UNKNOWN");
}

OO_TEST(OOStringFromGUIScreenID) {
  OO_CHECK(OOStringFromGUIScreenID(OOGUIScreenID::kMain) == "GUI_SCREEN_MAIN");
  OO_CHECK(OOStringFromGUIScreenID(OOGUIScreenID::kIntro1) == "GUI_SCREEN_INTRO1");
  OO_CHECK(OOStringFromGUIScreenID(OOGUIScreenID::kShipLibrary) == "GUI_SCREEN_SHIPLIBRARY");
  OO_CHECK(OOStringFromGUIScreenID(OOGUIScreenID::kKeyboard) == "GUI_SCREEN_KEYBOARD");
  OO_CHECK(OOStringFromGUIScreenID(OOGUIScreenID::kNewGame) == "GUI_SCREEN_NEWGAME");
  OO_CHECK(OOStringFromGUIScreenID(OOGUIScreenID::kOXZManager) == "GUI_SCREEN_OXZMANAGER");
  OO_CHECK(OOStringFromGUIScreenID(OOGUIScreenID::kStatus) == "GUI_SCREEN_STATUS");
  OO_CHECK(OOStringFromGUIScreenID(OOGUIScreenID::kManifest) == "GUI_SCREEN_MANIFEST");
  OO_CHECK(OOStringFromGUIScreenID(OOGUIScreenID::kEquipShip) == "GUI_SCREEN_EQUIP_SHIP");
  OO_CHECK(OOStringFromGUIScreenID(OOGUIScreenID::kShipyard) == "GUI_SCREEN_SHIPYARD");
  OO_CHECK(OOStringFromGUIScreenID(OOGUIScreenID::kLongRangeChart) == "GUI_SCREEN_LONG_RANGE_CHART");
  OO_CHECK(OOStringFromGUIScreenID(OOGUIScreenID::kShortRangeChart) == "GUI_SCREEN_SHORT_RANGE_CHART");
  OO_CHECK(OOStringFromGUIScreenID(OOGUIScreenID::kSystemData) == "GUI_SCREEN_SYSTEM_DATA");
  OO_CHECK(OOStringFromGUIScreenID(OOGUIScreenID::kMarket) == "GUI_SCREEN_MARKET");
  OO_CHECK(OOStringFromGUIScreenID(OOGUIScreenID::kMarketInfo) == "GUI_SCREEN_MARKETINFO");
  OO_CHECK(OOStringFromGUIScreenID(OOGUIScreenID::kOptions) == "GUI_SCREEN_OPTIONS");
  OO_CHECK(OOStringFromGUIScreenID(OOGUIScreenID::kGameOptions) == "GUI_SCREEN_GAMEOPTIONS");
  OO_CHECK(OOStringFromGUIScreenID(OOGUIScreenID::kLoad) == "GUI_SCREEN_LOAD");
  OO_CHECK(OOStringFromGUIScreenID(OOGUIScreenID::kSave) == "GUI_SCREEN_SAVE");
  OO_CHECK(OOStringFromGUIScreenID(OOGUIScreenID::kSaveOverwrite) == "GUI_SCREEN_SAVE_OVERWRITE");
  OO_CHECK(OOStringFromGUIScreenID(OOGUIScreenID::kStickMapper) == "GUI_SCREEN_STICKMAPPER");
  OO_CHECK(OOStringFromGUIScreenID(OOGUIScreenID::kStickProfile) == "GUI_SCREEN_STICKPROFILE");
  OO_CHECK(OOStringFromGUIScreenID(OOGUIScreenID::kMission) == "GUI_SCREEN_MISSION");
  OO_CHECK(OOStringFromGUIScreenID(OOGUIScreenID::kReport) == "GUI_SCREEN_REPORT");
  OO_CHECK(OOStringFromGUIScreenID(OOGUIScreenID::kInterfaces) == "GUI_SCREEN_INTERFACES");
  OO_CHECK(OOStringFromGUIScreenID(OOGUIScreenID::kKeyboardConfirmClear) == "GUI_SCREEN_KEYBOARD_CONFIRMCLEAR");
  OO_CHECK(OOStringFromGUIScreenID(OOGUIScreenID::kKeyboardConfig) == "GUI_SCREEN_KEYBOARD_CONFIG");
  OO_CHECK(OOStringFromGUIScreenID(OOGUIScreenID::kKeyboardEntry) == "GUI_SCREEN_KEYBOARD_ENTRY");
  OO_CHECK(OOStringFromGUIScreenID(OOGUIScreenID::kKeyboardLayout) == "GUI_SCREEN_KEYBOARD_LAYOUT");
}

OO_TEST(OOStringFromScanClass) {
  OO_CHECK(OOStringFromScanClass(OOScanClass::kNotSet) == "CLASS_NOT_SET");
  OO_CHECK(OOStringFromScanClass(OOScanClass::kNoDraw) == "CLASS_NO_DRAW");
  OO_CHECK(OOStringFromScanClass(OOScanClass::kNeutral) == "CLASS_NEUTRAL");
  OO_CHECK(OOStringFromScanClass(OOScanClass::kStation) == "CLASS_STATION");
  OO_CHECK(OOStringFromScanClass(OOScanClass::kTarget) == "CLASS_TARGET");
  OO_CHECK(OOStringFromScanClass(OOScanClass::kCargo) == "CLASS_CARGO");
  OO_CHECK(OOStringFromScanClass(OOScanClass::kMissile) == "CLASS_MISSILE");
  OO_CHECK(OOStringFromScanClass(OOScanClass::kRock) == "CLASS_ROCK");
  OO_CHECK(OOStringFromScanClass(OOScanClass::kMine) == "CLASS_MINE");
  OO_CHECK(OOStringFromScanClass(OOScanClass::kThargoid) == "CLASS_THARGOID");
  OO_CHECK(OOStringFromScanClass(OOScanClass::kBuoy) == "CLASS_BUOY");
  OO_CHECK(OOStringFromScanClass(OOScanClass::kVisualEffect) == "CLASS_VISUAL_EFFECT");
  OO_CHECK(OOStringFromScanClass(OOScanClass::kWormhole) == "CLASS_WORMHOLE");
  OO_CHECK(OOStringFromScanClass(OOScanClass::kPlayer) == "CLASS_PLAYER");
  OO_CHECK(OOStringFromScanClass(OOScanClass::kPolice) == "CLASS_POLICE");
  OO_CHECK(OOStringFromScanClass(OOScanClass::kMilitary) == "CLASS_MILITARY");
}

OO_TEST(OOStringFromShipDamageType) {
  OO_CHECK(OOStringFromShipDamageType(OOShipDamageType::kScrape) == "scrape damage");
  OO_CHECK(OOStringFromShipDamageType(OOShipDamageType::kHeat) == "heat damage");
  OO_CHECK(OOStringFromShipDamageType(OOShipDamageType::kEnergy) == "energy damage");
  OO_CHECK(OOStringFromShipDamageType(OOShipDamageType::kCascadeWeapon) == "cascade weapon");
  OO_CHECK(OOStringFromShipDamageType(OOShipDamageType::kHitAPlanet) == "hit a planet");
  OO_CHECK(OOStringFromShipDamageType(OOShipDamageType::kHitASun) == "hit a sun");
  OO_CHECK(OOStringFromShipDamageType(OOShipDamageType::kRemoved) == "removed");
}

OO_TEST(OOStringFromLegalStatusReason) {
  OO_CHECK(OOStringFromLegalStatusReason(OOLegalStatusReason::kUnknown) == "unknown");
  OO_CHECK(OOStringFromLegalStatusReason(OOLegalStatusReason::kSetup) == "setup actions");
  OO_CHECK(OOStringFromLegalStatusReason(OOLegalStatusReason::kByScript) == "scripted");
  OO_CHECK(OOStringFromLegalStatusReason(OOLegalStatusReason::kAttackedPolice) == "attacked police");
  OO_CHECK(OOStringFromLegalStatusReason(OOLegalStatusReason::kAttackedMainStation) == "attacked main station");
  OO_CHECK(OOStringFromLegalStatusReason(OOLegalStatusReason::kAttackedInnocent) == "attacked innocent");
  OO_CHECK(OOStringFromLegalStatusReason(OOLegalStatusReason::kSeenByPolice) == "seen by police");
  OO_CHECK(OOStringFromLegalStatusReason(OOLegalStatusReason::kDistressCall) == "distress call");
  OO_CHECK(OOStringFromLegalStatusReason(OOLegalStatusReason::kIllegalExports) == "illegal exports");
  OO_CHECK(OOStringFromLegalStatusReason(OOLegalStatusReason::kIllegalImports) == "illegal imports");
  OO_CHECK(OOStringFromLegalStatusReason(OOLegalStatusReason::kAssistingOffender) == "assisting offenders");
  OO_CHECK(OOStringFromLegalStatusReason(OOLegalStatusReason::kNewGalaxy) == "new galaxy");
  OO_CHECK(OOStringFromLegalStatusReason(OOLegalStatusReason::kNewSystem) == "new system");
  OO_CHECK(OOStringFromLegalStatusReason(OOLegalStatusReason::kPaidFine) == "paid fine");
  OO_CHECK(OOStringFromLegalStatusReason(OOLegalStatusReason::kEscapePod) == "escape pod");
  OO_CHECK(OOStringFromLegalStatusReason(OOLegalStatusReason::kAssistingPolice) == "assisting police");
  OO_CHECK(OOStringFromLegalStatusReason(OOLegalStatusReason::kPoliceAreClean) == "police are clean");
}

OO_TEST(OOEntityStatusFromString) {
  OO_CHECK(OOEntityStatusFromString("STATUS_START_GAME") == OOEntityStatus::kStartGame);
  OO_CHECK(OOEntityStatusFromString("STATUS_RESTART_GAME") == OOEntityStatus::kRestartGame);
  OO_CHECK(OOEntityStatusFromString("STATUS_DEAD") == OOEntityStatus::kDead);
  OO_CHECK(OOEntityStatusFromString("STATUS_INACTIVE") == OOEntityStatus::kInactive);
  OO_CHECK(OOEntityStatusFromString("STATUS_TEST") == OOEntityStatus::kTest);
  OO_CHECK(OOEntityStatusFromString("STATUS_COCKPIT_DISPLAY") == OOEntityStatus::kCockpitDisplay);
  OO_CHECK(OOEntityStatusFromString("STATUS_ACTIVE") == OOEntityStatus::kActive);
  OO_CHECK(OOEntityStatusFromString("STATUS_EFFECT") == OOEntityStatus::kEffect);
  OO_CHECK(OOEntityStatusFromString("STATUS_IN_FLIGHT") == OOEntityStatus::kInFlight);
  OO_CHECK(OOEntityStatusFromString("STATUS_DOCKED") == OOEntityStatus::kDocked);
  OO_CHECK(OOEntityStatusFromString("STATUS_AUTOPILOT_ENGAGED") == OOEntityStatus::kAutopilotEngaged);
  OO_CHECK(OOEntityStatusFromString("STATUS_DOCKING") == OOEntityStatus::kDocking);
  OO_CHECK(OOEntityStatusFromString("STATUS_LAUNCHING") == OOEntityStatus::kLaunching);
  OO_CHECK(OOEntityStatusFromString("STATUS_WITCHSPACE_COUNTDOWN") == OOEntityStatus::kWitchspaceCountdown);
  OO_CHECK(OOEntityStatusFromString("STATUS_ENTERING_WITCHSPACE") == OOEntityStatus::kEnteringWitchspace);
  OO_CHECK(OOEntityStatusFromString("STATUS_EXITING_WITCHSPACE") == OOEntityStatus::kExitingWitchspace);
  OO_CHECK(OOEntityStatusFromString("STATUS_ESCAPE_SEQUENCE") == OOEntityStatus::kEscapeSequence);
  OO_CHECK(OOEntityStatusFromString("STATUS_IN_HOLD") == OOEntityStatus::kInHold);
  OO_CHECK(OOEntityStatusFromString("STATUS_BEING_SCOOPED") == OOEntityStatus::kBeingScooped);
  OO_CHECK(OOEntityStatusFromString("STATUS_HANDLING_ERROR") == OOEntityStatus::kHandlingError);
  OO_CHECK(OOEntityStatusFromString("NOT_A_NAME") == OOEntityStatus::kInactive);  // the fallback
  OO_CHECK(OOEntityStatusFromString("") == OOEntityStatus::kInactive);
}

OO_TEST(OOCompassModeFromString) {
  OO_CHECK(OOCompassModeFromString("COMPASS_MODE_INACTIVE") == OOCompassMode::kInactive);
  OO_CHECK(OOCompassModeFromString("COMPASS_MODE_BASIC") == OOCompassMode::kBasic);
  OO_CHECK(OOCompassModeFromString("COMPASS_MODE_PLANET") == OOCompassMode::kPlanet);
  OO_CHECK(OOCompassModeFromString("COMPASS_MODE_STATION") == OOCompassMode::kStation);
  OO_CHECK(OOCompassModeFromString("COMPASS_MODE_SUN") == OOCompassMode::kSun);
  OO_CHECK(OOCompassModeFromString("COMPASS_MODE_TARGET") == OOCompassMode::kTarget);
  OO_CHECK(OOCompassModeFromString("COMPASS_MODE_BEACONS") == OOCompassMode::kBeacons);
  OO_CHECK(OOCompassModeFromString("NOT_A_NAME") == OOCompassMode::kBasic);  // the fallback
  OO_CHECK(OOCompassModeFromString("") == OOCompassMode::kBasic);
}

OO_TEST(OOGalacticHyperspaceBehaviourFromString) {
  OO_CHECK(OOGalacticHyperspaceBehaviourFromString("BEHAVIOUR_STANDARD") == OOGalacticHyperspaceBehaviour::kStandard);
  OO_CHECK(OOGalacticHyperspaceBehaviourFromString("BEHAVIOUR_ALL_SYSTEMS_REACHABLE") == OOGalacticHyperspaceBehaviour::kAllSystemsReachable);
  OO_CHECK(OOGalacticHyperspaceBehaviourFromString("BEHAVIOUR_FIXED_COORDINATES") == OOGalacticHyperspaceBehaviour::kFixedCoordinates);
  OO_CHECK(OOGalacticHyperspaceBehaviourFromString("BEHAVIOUR_UNKNOWN") == OOGalacticHyperspaceBehaviour::kUnknown);
  OO_CHECK(OOGalacticHyperspaceBehaviourFromString("NOT_A_NAME") == OOGalacticHyperspaceBehaviour::kUnknown);  // the fallback
  OO_CHECK(OOGalacticHyperspaceBehaviourFromString("") == OOGalacticHyperspaceBehaviour::kUnknown);
}

OO_TEST(OOGUIScreenIDFromString) {
  OO_CHECK(OOGUIScreenIDFromString("GUI_SCREEN_MAIN") == OOGUIScreenID::kMain);
  OO_CHECK(OOGUIScreenIDFromString("GUI_SCREEN_INTRO1") == OOGUIScreenID::kIntro1);
  OO_CHECK(OOGUIScreenIDFromString("GUI_SCREEN_SHIPLIBRARY") == OOGUIScreenID::kShipLibrary);
  OO_CHECK(OOGUIScreenIDFromString("GUI_SCREEN_KEYBOARD") == OOGUIScreenID::kKeyboard);
  OO_CHECK(OOGUIScreenIDFromString("GUI_SCREEN_NEWGAME") == OOGUIScreenID::kNewGame);
  OO_CHECK(OOGUIScreenIDFromString("GUI_SCREEN_OXZMANAGER") == OOGUIScreenID::kOXZManager);
  OO_CHECK(OOGUIScreenIDFromString("GUI_SCREEN_STATUS") == OOGUIScreenID::kStatus);
  OO_CHECK(OOGUIScreenIDFromString("GUI_SCREEN_MANIFEST") == OOGUIScreenID::kManifest);
  OO_CHECK(OOGUIScreenIDFromString("GUI_SCREEN_EQUIP_SHIP") == OOGUIScreenID::kEquipShip);
  OO_CHECK(OOGUIScreenIDFromString("GUI_SCREEN_SHIPYARD") == OOGUIScreenID::kShipyard);
  OO_CHECK(OOGUIScreenIDFromString("GUI_SCREEN_LONG_RANGE_CHART") == OOGUIScreenID::kLongRangeChart);
  OO_CHECK(OOGUIScreenIDFromString("GUI_SCREEN_SHORT_RANGE_CHART") == OOGUIScreenID::kShortRangeChart);
  OO_CHECK(OOGUIScreenIDFromString("GUI_SCREEN_SYSTEM_DATA") == OOGUIScreenID::kSystemData);
  OO_CHECK(OOGUIScreenIDFromString("GUI_SCREEN_MARKET") == OOGUIScreenID::kMarket);
  OO_CHECK(OOGUIScreenIDFromString("GUI_SCREEN_MARKETINFO") == OOGUIScreenID::kMarketInfo);
  OO_CHECK(OOGUIScreenIDFromString("GUI_SCREEN_OPTIONS") == OOGUIScreenID::kOptions);
  OO_CHECK(OOGUIScreenIDFromString("GUI_SCREEN_GAMEOPTIONS") == OOGUIScreenID::kGameOptions);
  OO_CHECK(OOGUIScreenIDFromString("GUI_SCREEN_LOAD") == OOGUIScreenID::kLoad);
  OO_CHECK(OOGUIScreenIDFromString("GUI_SCREEN_SAVE") == OOGUIScreenID::kSave);
  OO_CHECK(OOGUIScreenIDFromString("GUI_SCREEN_SAVE_OVERWRITE") == OOGUIScreenID::kSaveOverwrite);
  OO_CHECK(OOGUIScreenIDFromString("GUI_SCREEN_STICKMAPPER") == OOGUIScreenID::kStickMapper);
  OO_CHECK(OOGUIScreenIDFromString("GUI_SCREEN_STICKPROFILE") == OOGUIScreenID::kStickProfile);
  OO_CHECK(OOGUIScreenIDFromString("GUI_SCREEN_MISSION") == OOGUIScreenID::kMission);
  OO_CHECK(OOGUIScreenIDFromString("GUI_SCREEN_REPORT") == OOGUIScreenID::kReport);
  OO_CHECK(OOGUIScreenIDFromString("GUI_SCREEN_INTERFACES") == OOGUIScreenID::kInterfaces);
  OO_CHECK(OOGUIScreenIDFromString("GUI_SCREEN_KEYBOARD_CONFIRMCLEAR") == OOGUIScreenID::kKeyboardConfirmClear);
  OO_CHECK(OOGUIScreenIDFromString("GUI_SCREEN_KEYBOARD_CONFIG") == OOGUIScreenID::kKeyboardConfig);
  OO_CHECK(OOGUIScreenIDFromString("GUI_SCREEN_KEYBOARD_ENTRY") == OOGUIScreenID::kKeyboardEntry);
  OO_CHECK(OOGUIScreenIDFromString("GUI_SCREEN_KEYBOARD_LAYOUT") == OOGUIScreenID::kKeyboardLayout);
  OO_CHECK(OOGUIScreenIDFromString("NOT_A_NAME") == OOGUIScreenID::kMain);  // the fallback
  OO_CHECK(OOGUIScreenIDFromString("") == OOGUIScreenID::kMain);
}

OO_TEST(OOScanClassFromString) {
  OO_CHECK(OOScanClassFromString("CLASS_NOT_SET") == OOScanClass::kNotSet);
  OO_CHECK(OOScanClassFromString("CLASS_NO_DRAW") == OOScanClass::kNoDraw);
  OO_CHECK(OOScanClassFromString("CLASS_NEUTRAL") == OOScanClass::kNeutral);
  OO_CHECK(OOScanClassFromString("CLASS_STATION") == OOScanClass::kStation);
  OO_CHECK(OOScanClassFromString("CLASS_TARGET") == OOScanClass::kTarget);
  OO_CHECK(OOScanClassFromString("CLASS_CARGO") == OOScanClass::kCargo);
  OO_CHECK(OOScanClassFromString("CLASS_MISSILE") == OOScanClass::kMissile);
  OO_CHECK(OOScanClassFromString("CLASS_ROCK") == OOScanClass::kRock);
  OO_CHECK(OOScanClassFromString("CLASS_MINE") == OOScanClass::kMine);
  OO_CHECK(OOScanClassFromString("CLASS_THARGOID") == OOScanClass::kThargoid);
  OO_CHECK(OOScanClassFromString("CLASS_BUOY") == OOScanClass::kBuoy);
  OO_CHECK(OOScanClassFromString("CLASS_VISUAL_EFFECT") == OOScanClass::kVisualEffect);
  OO_CHECK(OOScanClassFromString("CLASS_WORMHOLE") == OOScanClass::kWormhole);
  OO_CHECK(OOScanClassFromString("CLASS_PLAYER") == OOScanClass::kPlayer);
  OO_CHECK(OOScanClassFromString("CLASS_POLICE") == OOScanClass::kPolice);
  OO_CHECK(OOScanClassFromString("CLASS_MILITARY") == OOScanClass::kMilitary);
  OO_CHECK(OOScanClassFromString("NOT_A_NAME") == OOScanClass::kNotSet);  // the fallback
  OO_CHECK(OOScanClassFromString("") == OOScanClass::kNotSet);
}

OO_TEST(OOLongRangeChartModeFromString) {
  OO_CHECK(OOLongRangeChartModeFromString("OOLRC_MODE_UNKNOWN") == OOLongRangeChartMode::kUnknown);
  OO_CHECK(OOLongRangeChartModeFromString("OOLRC_MODE_SUNCOLOR") == OOLongRangeChartMode::kSunColor);
  OO_CHECK(OOLongRangeChartModeFromString("OOLRC_MODE_ECONOMY") == OOLongRangeChartMode::kEconomy);
  OO_CHECK(OOLongRangeChartModeFromString("OOLRC_MODE_GOVERNMENT") == OOLongRangeChartMode::kGovernment);
  OO_CHECK(OOLongRangeChartModeFromString("OOLRC_MODE_TECHLEVEL") == OOLongRangeChartMode::kTechLevel);
  OO_CHECK(OOLongRangeChartModeFromString("NOT_A_NAME") == OOLongRangeChartMode::kUnknown);  // the fallback
  OO_CHECK(OOLongRangeChartModeFromString("") == OOLongRangeChartMode::kUnknown);
}

OO_TEST(RouteTypeToString) {
  OO_CHECK(RouteTypeToString(OORouteType::kNone) == "OPTIMIZED_BY_NONE");
  OO_CHECK(RouteTypeToString(OORouteType::kJumps) == "OPTIMIZED_BY_JUMPS");
  OO_CHECK(RouteTypeToString(OORouteType::kTime) == "OPTIMIZED_BY_TIME");
}

OO_TEST(CargoTypeToString) {
  OO_CHECK(CargoTypeToString(OOCargoType::kNotCargo) == "CARGO_NOT_CARGO");
  OO_CHECK(CargoTypeToString(OOCargoType::kSlaves) == "CARGO_SLAVES");
  OO_CHECK(CargoTypeToString(OOCargoType::kAlloy) == "CARGO_ALLOY");
  OO_CHECK(CargoTypeToString(OOCargoType::kMinerals) == "CARGO_MINERALS");
  OO_CHECK(CargoTypeToString(OOCargoType::kThargoid) == "CARGO_THARGOID");
  OO_CHECK(CargoTypeToString(OOCargoType::kRandom) == "CARGO_RANDOM");
  OO_CHECK(CargoTypeToString(OOCargoType::kScriptedItem) == "CARGO_SCRIPTED_ITEM");
  OO_CHECK(CargoTypeToString(OOCargoType::kCharacter) == "CARGO_CHARACTER");
}

OO_TEST(StringToCargoType) {
  OO_CHECK(StringToCargoType("CARGO_NOT_CARGO") == OOCargoType::kNotCargo);
  OO_CHECK(StringToCargoType("CARGO_SLAVES") == OOCargoType::kSlaves);
  OO_CHECK(StringToCargoType("CARGO_ALLOY") == OOCargoType::kAlloy);
  OO_CHECK(StringToCargoType("CARGO_MINERALS") == OOCargoType::kMinerals);
  OO_CHECK(StringToCargoType("CARGO_THARGOID") == OOCargoType::kThargoid);
  OO_CHECK(StringToCargoType("CARGO_RANDOM") == OOCargoType::kRandom);
  OO_CHECK(StringToCargoType("CARGO_SCRIPTED_ITEM") == OOCargoType::kScriptedItem);
  OO_CHECK(StringToCargoType("CARGO_CHARACTER") == OOCargoType::kCharacter);
  OO_CHECK(StringToCargoType("CARGO_CARRIED") == OOCargoType::kRandom);
  OO_CHECK(StringToCargoType("NOT_A_NAME") == OOCargoType::kNotCargo);  // the fallback
  OO_CHECK(StringToCargoType("") == OOCargoType::kNotCargo);
}

OO_TEST(EnergyUnitTypeToString) {
  OO_CHECK(EnergyUnitTypeToString(OOEnergyUnitType::kNone) == "ENERGY_UNIT_NONE");
  OO_CHECK(EnergyUnitTypeToString(OOEnergyUnitType::kNormal) == "ENERGY_UNIT_NORMAL");
  OO_CHECK(EnergyUnitTypeToString(OOEnergyUnitType::kNaval) == "ENERGY_UNIT_NAVAL");
  OO_CHECK(EnergyUnitTypeToString(OOEnergyUnitType::kNormalDamaged) == "ENERGY_UNIT_NORMAL_DAMAGED");
  OO_CHECK(EnergyUnitTypeToString(OOEnergyUnitType::kNavalDamaged) == "ENERGY_UNIT_NAVAL_DAMAGED");
  OO_CHECK(EnergyUnitTypeToString(OOEnergyUnitType::kOldNormal) == "Unsupported energy unit");
  OO_CHECK(EnergyUnitTypeToString(OOEnergyUnitType::kOldNaval) == "Unsupported energy unit");
}

OO_TEST(StringToEnergyUnitType) {
  OO_CHECK(StringToEnergyUnitType("ENERGY_UNIT_NONE") == OOEnergyUnitType::kNone);
  OO_CHECK(StringToEnergyUnitType("ENERGY_UNIT_NORMAL") == OOEnergyUnitType::kNormal);
  OO_CHECK(StringToEnergyUnitType("ENERGY_UNIT_NAVAL") == OOEnergyUnitType::kNaval);
  OO_CHECK(StringToEnergyUnitType("ENERGY_UNIT_NORMAL_DAMAGED") == OOEnergyUnitType::kNormalDamaged);
  OO_CHECK(StringToEnergyUnitType("ENERGY_UNIT_NAVAL_DAMAGED") == OOEnergyUnitType::kNavalDamaged);
  OO_CHECK(StringToEnergyUnitType("NOT_A_NAME") == OOEnergyUnitType::kNone);  // the fallback
  OO_CHECK(StringToEnergyUnitType("") == OOEnergyUnitType::kNone);
}

OO_TEST(OOStringFromShaderSetting) {
  OO_CHECK(OOStringFromShaderSetting(OOShaderSetting::kOff) == "SHADERS_OFF");
  OO_CHECK(OOStringFromShaderSetting(OOShaderSetting::kSimple) == "SHADERS_SIMPLE");
  OO_CHECK(OOStringFromShaderSetting(OOShaderSetting::kFull) == "SHADERS_FULL");
  OO_CHECK(OOStringFromShaderSetting(OOShaderSetting::kNotSupported) == "SHADERS_NOT_SUPPORTED");
}

OO_TEST(OOShaderSettingFromString) {
  OO_CHECK(OOShaderSettingFromString("SHADERS_OFF") == OOShaderSetting::kOff);
  OO_CHECK(OOShaderSettingFromString("SHADERS_SIMPLE") == OOShaderSetting::kSimple);
  OO_CHECK(OOShaderSettingFromString("SHADERS_FULL") == OOShaderSetting::kFull);
  OO_CHECK(OOShaderSettingFromString("SHADERS_NOT_SUPPORTED") == OOShaderSetting::kNotSupported);
  OO_CHECK(OOShaderSettingFromString("NOT_A_NAME") == OOShaderSetting::kNotSupported);  // the fallback
  OO_CHECK(OOShaderSettingFromString("") == OOShaderSetting::kNotSupported);
}

OO_TEST(StringToRouteType) {
  OO_CHECK(StringToRouteType("OPTIMIZED_BY_NONE") == OORouteType::kNone);
  OO_CHECK(StringToRouteType("OPTIMIZED_BY_JUMPS") == OORouteType::kJumps);
  OO_CHECK(StringToRouteType("OPTIMIZED_BY_TIME") == OORouteType::kTime);
  OO_CHECK(StringToRouteType("NOT_A_NAME") == OORouteType::kJumps);  // the fallback
  OO_CHECK(StringToRouteType("") == OORouteType::kJumps);
}

OO_TEST(DockingClearanceStatusToString) {
  OO_CHECK(DockingClearanceStatusToString(OODockingClearanceStatus::kNone) == "DOCKING_CLEARANCE_STATUS_NONE");
  OO_CHECK(DockingClearanceStatusToString(OODockingClearanceStatus::kRequested) == "DOCKING_CLEARANCE_STATUS_REQUESTED");
  OO_CHECK(DockingClearanceStatusToString(OODockingClearanceStatus::kNotRequired) == "DOCKING_CLEARANCE_STATUS_NOT_REQUIRED");
  OO_CHECK(DockingClearanceStatusToString(OODockingClearanceStatus::kGranted) == "DOCKING_CLEARANCE_STATUS_GRANTED");
  OO_CHECK(DockingClearanceStatusToString(OODockingClearanceStatus::kTimingOut) == "DOCKING_CLEARANCE_STATUS_TIMING_OUT");
}

OO_TEST(OOStringFromGraphicsDetail) {
  OO_CHECK(OOStringFromGraphicsDetail(OOGraphicsDetail::kMinimum) == "DETAIL_LEVEL_MINIMUM");
  OO_CHECK(OOStringFromGraphicsDetail(OOGraphicsDetail::kNormal) == "DETAIL_LEVEL_NORMAL");
  OO_CHECK(OOStringFromGraphicsDetail(OOGraphicsDetail::kShaders) == "DETAIL_LEVEL_SHADERS");
  OO_CHECK(OOStringFromGraphicsDetail(OOGraphicsDetail::kExtras) == "DETAIL_LEVEL_EXTRAS");
}

OO_TEST(OOGraphicsDetailFromString) {
  OO_CHECK(OOGraphicsDetailFromString("DETAIL_LEVEL_MINIMUM") == OOGraphicsDetail::kMinimum);
  OO_CHECK(OOGraphicsDetailFromString("DETAIL_LEVEL_NORMAL") == OOGraphicsDetail::kNormal);
  OO_CHECK(OOGraphicsDetailFromString("DETAIL_LEVEL_SHADERS") == OOGraphicsDetail::kShaders);
  OO_CHECK(OOGraphicsDetailFromString("DETAIL_LEVEL_EXTRAS") == OOGraphicsDetail::kExtras);
  OO_CHECK(OOGraphicsDetailFromString("NOT_A_NAME") == OOGraphicsDetail::kMinimum);  // the fallback
  OO_CHECK(OOGraphicsDetailFromString("") == OOGraphicsDetail::kMinimum);
}

OO_TEST(OOStringFromHDRToneMapper) {
  OO_CHECK(OOStringFromHDRToneMapper(OOHDRToneMapper::kNone) == "OOHDR_TONEMAPPER_NONE");
  OO_CHECK(OOStringFromHDRToneMapper(OOHDRToneMapper::kAcesApprox) == "OOHDR_TONEMAPPER_ACES_APPROX");
  OO_CHECK(OOStringFromHDRToneMapper(OOHDRToneMapper::kDice) == "OOHDR_TONEMAPPER_DICE");
  OO_CHECK(OOStringFromHDRToneMapper(OOHDRToneMapper::kUchimura) == "OOHDR_TONEMAPPER_UCHIMURA");
  OO_CHECK(OOStringFromHDRToneMapper(OOHDRToneMapper::kReinhard) == "OOHDR_TONEMAPPER_REINHARD");
}

OO_TEST(OOHDRToneMapperFromString) {
  OO_CHECK(OOHDRToneMapperFromString("OOHDR_TONEMAPPER_NONE") == OOHDRToneMapper::kNone);
  OO_CHECK(OOHDRToneMapperFromString("OOHDR_TONEMAPPER_ACES_APPROX") == OOHDRToneMapper::kAcesApprox);
  OO_CHECK(OOHDRToneMapperFromString("OOHDR_TONEMAPPER_DICE") == OOHDRToneMapper::kDice);
  OO_CHECK(OOHDRToneMapperFromString("OOHDR_TONEMAPPER_UCHIMURA") == OOHDRToneMapper::kUchimura);
  OO_CHECK(OOHDRToneMapperFromString("OOHDR_TONEMAPPER_REINHARD") == OOHDRToneMapper::kReinhard);
  OO_CHECK(OOHDRToneMapperFromString("NOT_A_NAME") == OOHDRToneMapper::kAcesApprox);  // the fallback
  OO_CHECK(OOHDRToneMapperFromString("") == OOHDRToneMapper::kAcesApprox);
}

OO_TEST(OOStringFromSDRToneMapper) {
  OO_CHECK(OOStringFromSDRToneMapper(OOSDRToneMapper::kNone) == "OOSDR_TONEMAPPER_NONE");
  OO_CHECK(OOStringFromSDRToneMapper(OOSDRToneMapper::kAces) == "OOSDR_TONEMAPPER_ACES");
  OO_CHECK(OOStringFromSDRToneMapper(OOSDRToneMapper::kAgX) == "OOSDR_TONEMAPPER_AgX");
  OO_CHECK(OOStringFromSDRToneMapper(OOSDRToneMapper::kHejlDawson) == "OOSDR_TONEMAPPER_HEJLDAWSON");
  OO_CHECK(OOStringFromSDRToneMapper(OOSDRToneMapper::kUC2) == "OOSDR_TONEMAPPER_UC2");
  OO_CHECK(OOStringFromSDRToneMapper(OOSDRToneMapper::kUchimura) == "OOSDR_TONEMAPPER_UCHIMURA");
  OO_CHECK(OOStringFromSDRToneMapper(OOSDRToneMapper::kReinhard) == "OOSDR_TONEMAPPER_REINHARD");
}

OO_TEST(OOSDRToneMapperFromString) {
  OO_CHECK(OOSDRToneMapperFromString("OOSDR_TONEMAPPER_NONE") == OOSDRToneMapper::kNone);
  OO_CHECK(OOSDRToneMapperFromString("OOSDR_TONEMAPPER_ACES") == OOSDRToneMapper::kAces);
  OO_CHECK(OOSDRToneMapperFromString("OOSDR_TONEMAPPER_AgX") == OOSDRToneMapper::kAgX);
  OO_CHECK(OOSDRToneMapperFromString("OOSDR_TONEMAPPER_HEJLDAWSON") == OOSDRToneMapper::kHejlDawson);
  OO_CHECK(OOSDRToneMapperFromString("OOSDR_TONEMAPPER_UC2") == OOSDRToneMapper::kUC2);
  OO_CHECK(OOSDRToneMapperFromString("OOSDR_TONEMAPPER_UCHIMURA") == OOSDRToneMapper::kUchimura);
  OO_CHECK(OOSDRToneMapperFromString("OOSDR_TONEMAPPER_REINHARD") == OOSDRToneMapper::kReinhard);
  OO_CHECK(OOSDRToneMapperFromString("NOT_A_NAME") == OOSDRToneMapper::kAces);  // the fallback
  OO_CHECK(OOSDRToneMapperFromString("") == OOSDRToneMapper::kAces);
}

namespace {

// A bare QuickJS context with the constant tables' atoms. The atoms are interned once per process
// and belong to the runtime, so one runtime serves every case and is kept to the end.
struct JSStrings {
  JSRuntime* runtime = JS_NewRuntime();
  JSContext* context = JS_NewContext(runtime);
  JSStrings() { OOConstToJSStringInit(context); }
  std::string text(JSValue value) const {
    const char* chars = JS_ToCString(context, value);
    std::string result = chars != nullptr ? chars : "(not a string)";
    JS_FreeCString(context, chars);
    JS_FreeValue(context, value);
    return result;
  }
  JSValue string(const char* chars) const { return JS_NewString(context, chars); }
};

JSStrings& Strings() {
  static JSStrings* strings = new JSStrings;
  return *strings;
}

}  // namespace

OO_TEST(jsEntityStatus) {
  JSStrings& js = Strings();
  OO_CHECK(js.text(OOJSValueFromEntityStatus(js.context, OOEntityStatus::kStartGame)) == "STATUS_START_GAME");
  { JSValue v = js.string("STATUS_START_GAME"); OO_CHECK(OOEntityStatusFromJSValue(js.context, v) == OOEntityStatus::kStartGame); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromEntityStatus(js.context, OOEntityStatus::kRestartGame)) == "STATUS_RESTART_GAME");
  { JSValue v = js.string("STATUS_RESTART_GAME"); OO_CHECK(OOEntityStatusFromJSValue(js.context, v) == OOEntityStatus::kRestartGame); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromEntityStatus(js.context, OOEntityStatus::kDead)) == "STATUS_DEAD");
  { JSValue v = js.string("STATUS_DEAD"); OO_CHECK(OOEntityStatusFromJSValue(js.context, v) == OOEntityStatus::kDead); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromEntityStatus(js.context, OOEntityStatus::kInactive)) == "STATUS_INACTIVE");
  { JSValue v = js.string("STATUS_INACTIVE"); OO_CHECK(OOEntityStatusFromJSValue(js.context, v) == OOEntityStatus::kInactive); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromEntityStatus(js.context, OOEntityStatus::kTest)) == "STATUS_TEST");
  { JSValue v = js.string("STATUS_TEST"); OO_CHECK(OOEntityStatusFromJSValue(js.context, v) == OOEntityStatus::kTest); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromEntityStatus(js.context, OOEntityStatus::kCockpitDisplay)) == "STATUS_COCKPIT_DISPLAY");
  { JSValue v = js.string("STATUS_COCKPIT_DISPLAY"); OO_CHECK(OOEntityStatusFromJSValue(js.context, v) == OOEntityStatus::kCockpitDisplay); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromEntityStatus(js.context, OOEntityStatus::kActive)) == "STATUS_ACTIVE");
  { JSValue v = js.string("STATUS_ACTIVE"); OO_CHECK(OOEntityStatusFromJSValue(js.context, v) == OOEntityStatus::kActive); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromEntityStatus(js.context, OOEntityStatus::kEffect)) == "STATUS_EFFECT");
  { JSValue v = js.string("STATUS_EFFECT"); OO_CHECK(OOEntityStatusFromJSValue(js.context, v) == OOEntityStatus::kEffect); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromEntityStatus(js.context, OOEntityStatus::kInFlight)) == "STATUS_IN_FLIGHT");
  { JSValue v = js.string("STATUS_IN_FLIGHT"); OO_CHECK(OOEntityStatusFromJSValue(js.context, v) == OOEntityStatus::kInFlight); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromEntityStatus(js.context, OOEntityStatus::kDocked)) == "STATUS_DOCKED");
  { JSValue v = js.string("STATUS_DOCKED"); OO_CHECK(OOEntityStatusFromJSValue(js.context, v) == OOEntityStatus::kDocked); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromEntityStatus(js.context, OOEntityStatus::kAutopilotEngaged)) == "STATUS_AUTOPILOT_ENGAGED");
  { JSValue v = js.string("STATUS_AUTOPILOT_ENGAGED"); OO_CHECK(OOEntityStatusFromJSValue(js.context, v) == OOEntityStatus::kAutopilotEngaged); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromEntityStatus(js.context, OOEntityStatus::kDocking)) == "STATUS_DOCKING");
  { JSValue v = js.string("STATUS_DOCKING"); OO_CHECK(OOEntityStatusFromJSValue(js.context, v) == OOEntityStatus::kDocking); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromEntityStatus(js.context, OOEntityStatus::kLaunching)) == "STATUS_LAUNCHING");
  { JSValue v = js.string("STATUS_LAUNCHING"); OO_CHECK(OOEntityStatusFromJSValue(js.context, v) == OOEntityStatus::kLaunching); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromEntityStatus(js.context, OOEntityStatus::kWitchspaceCountdown)) == "STATUS_WITCHSPACE_COUNTDOWN");
  { JSValue v = js.string("STATUS_WITCHSPACE_COUNTDOWN"); OO_CHECK(OOEntityStatusFromJSValue(js.context, v) == OOEntityStatus::kWitchspaceCountdown); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromEntityStatus(js.context, OOEntityStatus::kEnteringWitchspace)) == "STATUS_ENTERING_WITCHSPACE");
  { JSValue v = js.string("STATUS_ENTERING_WITCHSPACE"); OO_CHECK(OOEntityStatusFromJSValue(js.context, v) == OOEntityStatus::kEnteringWitchspace); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromEntityStatus(js.context, OOEntityStatus::kExitingWitchspace)) == "STATUS_EXITING_WITCHSPACE");
  { JSValue v = js.string("STATUS_EXITING_WITCHSPACE"); OO_CHECK(OOEntityStatusFromJSValue(js.context, v) == OOEntityStatus::kExitingWitchspace); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromEntityStatus(js.context, OOEntityStatus::kEscapeSequence)) == "STATUS_ESCAPE_SEQUENCE");
  { JSValue v = js.string("STATUS_ESCAPE_SEQUENCE"); OO_CHECK(OOEntityStatusFromJSValue(js.context, v) == OOEntityStatus::kEscapeSequence); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromEntityStatus(js.context, OOEntityStatus::kInHold)) == "STATUS_IN_HOLD");
  { JSValue v = js.string("STATUS_IN_HOLD"); OO_CHECK(OOEntityStatusFromJSValue(js.context, v) == OOEntityStatus::kInHold); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromEntityStatus(js.context, OOEntityStatus::kBeingScooped)) == "STATUS_BEING_SCOOPED");
  { JSValue v = js.string("STATUS_BEING_SCOOPED"); OO_CHECK(OOEntityStatusFromJSValue(js.context, v) == OOEntityStatus::kBeingScooped); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromEntityStatus(js.context, OOEntityStatus::kHandlingError)) == "STATUS_HANDLING_ERROR");
  { JSValue v = js.string("STATUS_HANDLING_ERROR"); OO_CHECK(OOEntityStatusFromJSValue(js.context, v) == OOEntityStatus::kHandlingError); JS_FreeValue(js.context, v); }
  { JSValue v = js.string("NOT_A_NAME"); OO_CHECK(OOEntityStatusFromJSValue(js.context, v) == (OOEntityStatus)(OOEntityStatus::kInactive)); JS_FreeValue(js.context, v); }  // the fallback
  OO_CHECK(OOEntityStatusFromJSValue(js.context, JS_NewInt32(js.context, 1)) == (OOEntityStatus)(OOEntityStatus::kInactive));  // not a string
}

OO_TEST(jsScanClass) {
  JSStrings& js = Strings();
  OO_CHECK(js.text(OOJSValueFromScanClass(js.context, OOScanClass::kNotSet)) == "CLASS_NOT_SET");
  { JSValue v = js.string("CLASS_NOT_SET"); OO_CHECK(OOScanClassFromJSValue(js.context, v) == OOScanClass::kNotSet); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromScanClass(js.context, OOScanClass::kNoDraw)) == "CLASS_NO_DRAW");
  { JSValue v = js.string("CLASS_NO_DRAW"); OO_CHECK(OOScanClassFromJSValue(js.context, v) == OOScanClass::kNoDraw); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromScanClass(js.context, OOScanClass::kNeutral)) == "CLASS_NEUTRAL");
  { JSValue v = js.string("CLASS_NEUTRAL"); OO_CHECK(OOScanClassFromJSValue(js.context, v) == OOScanClass::kNeutral); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromScanClass(js.context, OOScanClass::kStation)) == "CLASS_STATION");
  { JSValue v = js.string("CLASS_STATION"); OO_CHECK(OOScanClassFromJSValue(js.context, v) == OOScanClass::kStation); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromScanClass(js.context, OOScanClass::kTarget)) == "CLASS_TARGET");
  { JSValue v = js.string("CLASS_TARGET"); OO_CHECK(OOScanClassFromJSValue(js.context, v) == OOScanClass::kTarget); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromScanClass(js.context, OOScanClass::kCargo)) == "CLASS_CARGO");
  { JSValue v = js.string("CLASS_CARGO"); OO_CHECK(OOScanClassFromJSValue(js.context, v) == OOScanClass::kCargo); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromScanClass(js.context, OOScanClass::kMissile)) == "CLASS_MISSILE");
  { JSValue v = js.string("CLASS_MISSILE"); OO_CHECK(OOScanClassFromJSValue(js.context, v) == OOScanClass::kMissile); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromScanClass(js.context, OOScanClass::kRock)) == "CLASS_ROCK");
  { JSValue v = js.string("CLASS_ROCK"); OO_CHECK(OOScanClassFromJSValue(js.context, v) == OOScanClass::kRock); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromScanClass(js.context, OOScanClass::kMine)) == "CLASS_MINE");
  { JSValue v = js.string("CLASS_MINE"); OO_CHECK(OOScanClassFromJSValue(js.context, v) == OOScanClass::kMine); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromScanClass(js.context, OOScanClass::kThargoid)) == "CLASS_THARGOID");
  { JSValue v = js.string("CLASS_THARGOID"); OO_CHECK(OOScanClassFromJSValue(js.context, v) == OOScanClass::kThargoid); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromScanClass(js.context, OOScanClass::kBuoy)) == "CLASS_BUOY");
  { JSValue v = js.string("CLASS_BUOY"); OO_CHECK(OOScanClassFromJSValue(js.context, v) == OOScanClass::kBuoy); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromScanClass(js.context, OOScanClass::kVisualEffect)) == "CLASS_VISUAL_EFFECT");
  { JSValue v = js.string("CLASS_VISUAL_EFFECT"); OO_CHECK(OOScanClassFromJSValue(js.context, v) == OOScanClass::kVisualEffect); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromScanClass(js.context, OOScanClass::kWormhole)) == "CLASS_WORMHOLE");
  { JSValue v = js.string("CLASS_WORMHOLE"); OO_CHECK(OOScanClassFromJSValue(js.context, v) == OOScanClass::kWormhole); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromScanClass(js.context, OOScanClass::kPlayer)) == "CLASS_PLAYER");
  { JSValue v = js.string("CLASS_PLAYER"); OO_CHECK(OOScanClassFromJSValue(js.context, v) == OOScanClass::kPlayer); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromScanClass(js.context, OOScanClass::kPolice)) == "CLASS_POLICE");
  { JSValue v = js.string("CLASS_POLICE"); OO_CHECK(OOScanClassFromJSValue(js.context, v) == OOScanClass::kPolice); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromScanClass(js.context, OOScanClass::kMilitary)) == "CLASS_MILITARY");
  { JSValue v = js.string("CLASS_MILITARY"); OO_CHECK(OOScanClassFromJSValue(js.context, v) == OOScanClass::kMilitary); JS_FreeValue(js.context, v); }
  { JSValue v = js.string("NOT_A_NAME"); OO_CHECK(OOScanClassFromJSValue(js.context, v) == (OOScanClass)(OOScanClass::kNotSet)); JS_FreeValue(js.context, v); }  // the fallback
  OO_CHECK(OOScanClassFromJSValue(js.context, JS_NewInt32(js.context, 1)) == (OOScanClass)(OOScanClass::kNotSet));  // not a string
}

OO_TEST(jsCompassMode) {
  JSStrings& js = Strings();
  OO_CHECK(js.text(OOJSValueFromCompassMode(js.context, OOCompassMode::kInactive)) == "COMPASS_MODE_INACTIVE");
  { JSValue v = js.string("COMPASS_MODE_INACTIVE"); OO_CHECK(OOCompassModeFromJSValue(js.context, v) == OOCompassMode::kInactive); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromCompassMode(js.context, OOCompassMode::kBasic)) == "COMPASS_MODE_BASIC");
  { JSValue v = js.string("COMPASS_MODE_BASIC"); OO_CHECK(OOCompassModeFromJSValue(js.context, v) == OOCompassMode::kBasic); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromCompassMode(js.context, OOCompassMode::kPlanet)) == "COMPASS_MODE_PLANET");
  { JSValue v = js.string("COMPASS_MODE_PLANET"); OO_CHECK(OOCompassModeFromJSValue(js.context, v) == OOCompassMode::kPlanet); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromCompassMode(js.context, OOCompassMode::kStation)) == "COMPASS_MODE_STATION");
  { JSValue v = js.string("COMPASS_MODE_STATION"); OO_CHECK(OOCompassModeFromJSValue(js.context, v) == OOCompassMode::kStation); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromCompassMode(js.context, OOCompassMode::kSun)) == "COMPASS_MODE_SUN");
  { JSValue v = js.string("COMPASS_MODE_SUN"); OO_CHECK(OOCompassModeFromJSValue(js.context, v) == OOCompassMode::kSun); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromCompassMode(js.context, OOCompassMode::kTarget)) == "COMPASS_MODE_TARGET");
  { JSValue v = js.string("COMPASS_MODE_TARGET"); OO_CHECK(OOCompassModeFromJSValue(js.context, v) == OOCompassMode::kTarget); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromCompassMode(js.context, OOCompassMode::kBeacons)) == "COMPASS_MODE_BEACONS");
  { JSValue v = js.string("COMPASS_MODE_BEACONS"); OO_CHECK(OOCompassModeFromJSValue(js.context, v) == OOCompassMode::kBeacons); JS_FreeValue(js.context, v); }
  { JSValue v = js.string("NOT_A_NAME"); OO_CHECK(OOCompassModeFromJSValue(js.context, v) == (OOCompassMode)(OOCompassMode::kBasic)); JS_FreeValue(js.context, v); }  // the fallback
  OO_CHECK(OOCompassModeFromJSValue(js.context, JS_NewInt32(js.context, 1)) == (OOCompassMode)(OOCompassMode::kBasic));  // not a string
}

OO_TEST(jsGUIScreenID) {
  JSStrings& js = Strings();
  OO_CHECK(js.text(OOJSValueFromGUIScreenID(js.context, OOGUIScreenID::kMain)) == "GUI_SCREEN_MAIN");
  { JSValue v = js.string("GUI_SCREEN_MAIN"); OO_CHECK(OOGUIScreenIDFromJSValue(js.context, v) == OOGUIScreenID::kMain); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromGUIScreenID(js.context, OOGUIScreenID::kIntro1)) == "GUI_SCREEN_INTRO1");
  { JSValue v = js.string("GUI_SCREEN_INTRO1"); OO_CHECK(OOGUIScreenIDFromJSValue(js.context, v) == OOGUIScreenID::kIntro1); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromGUIScreenID(js.context, OOGUIScreenID::kShipLibrary)) == "GUI_SCREEN_SHIPLIBRARY");
  { JSValue v = js.string("GUI_SCREEN_SHIPLIBRARY"); OO_CHECK(OOGUIScreenIDFromJSValue(js.context, v) == OOGUIScreenID::kShipLibrary); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromGUIScreenID(js.context, OOGUIScreenID::kKeyboard)) == "GUI_SCREEN_KEYBOARD");
  { JSValue v = js.string("GUI_SCREEN_KEYBOARD"); OO_CHECK(OOGUIScreenIDFromJSValue(js.context, v) == OOGUIScreenID::kKeyboard); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromGUIScreenID(js.context, OOGUIScreenID::kNewGame)) == "GUI_SCREEN_NEWGAME");
  { JSValue v = js.string("GUI_SCREEN_NEWGAME"); OO_CHECK(OOGUIScreenIDFromJSValue(js.context, v) == OOGUIScreenID::kNewGame); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromGUIScreenID(js.context, OOGUIScreenID::kOXZManager)) == "GUI_SCREEN_OXZMANAGER");
  { JSValue v = js.string("GUI_SCREEN_OXZMANAGER"); OO_CHECK(OOGUIScreenIDFromJSValue(js.context, v) == OOGUIScreenID::kOXZManager); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromGUIScreenID(js.context, OOGUIScreenID::kStatus)) == "GUI_SCREEN_STATUS");
  { JSValue v = js.string("GUI_SCREEN_STATUS"); OO_CHECK(OOGUIScreenIDFromJSValue(js.context, v) == OOGUIScreenID::kStatus); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromGUIScreenID(js.context, OOGUIScreenID::kManifest)) == "GUI_SCREEN_MANIFEST");
  { JSValue v = js.string("GUI_SCREEN_MANIFEST"); OO_CHECK(OOGUIScreenIDFromJSValue(js.context, v) == OOGUIScreenID::kManifest); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromGUIScreenID(js.context, OOGUIScreenID::kEquipShip)) == "GUI_SCREEN_EQUIP_SHIP");
  { JSValue v = js.string("GUI_SCREEN_EQUIP_SHIP"); OO_CHECK(OOGUIScreenIDFromJSValue(js.context, v) == OOGUIScreenID::kEquipShip); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromGUIScreenID(js.context, OOGUIScreenID::kShipyard)) == "GUI_SCREEN_SHIPYARD");
  { JSValue v = js.string("GUI_SCREEN_SHIPYARD"); OO_CHECK(OOGUIScreenIDFromJSValue(js.context, v) == OOGUIScreenID::kShipyard); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromGUIScreenID(js.context, OOGUIScreenID::kLongRangeChart)) == "GUI_SCREEN_LONG_RANGE_CHART");
  { JSValue v = js.string("GUI_SCREEN_LONG_RANGE_CHART"); OO_CHECK(OOGUIScreenIDFromJSValue(js.context, v) == OOGUIScreenID::kLongRangeChart); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromGUIScreenID(js.context, OOGUIScreenID::kShortRangeChart)) == "GUI_SCREEN_SHORT_RANGE_CHART");
  { JSValue v = js.string("GUI_SCREEN_SHORT_RANGE_CHART"); OO_CHECK(OOGUIScreenIDFromJSValue(js.context, v) == OOGUIScreenID::kShortRangeChart); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromGUIScreenID(js.context, OOGUIScreenID::kSystemData)) == "GUI_SCREEN_SYSTEM_DATA");
  { JSValue v = js.string("GUI_SCREEN_SYSTEM_DATA"); OO_CHECK(OOGUIScreenIDFromJSValue(js.context, v) == OOGUIScreenID::kSystemData); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromGUIScreenID(js.context, OOGUIScreenID::kMarket)) == "GUI_SCREEN_MARKET");
  { JSValue v = js.string("GUI_SCREEN_MARKET"); OO_CHECK(OOGUIScreenIDFromJSValue(js.context, v) == OOGUIScreenID::kMarket); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromGUIScreenID(js.context, OOGUIScreenID::kMarketInfo)) == "GUI_SCREEN_MARKETINFO");
  { JSValue v = js.string("GUI_SCREEN_MARKETINFO"); OO_CHECK(OOGUIScreenIDFromJSValue(js.context, v) == OOGUIScreenID::kMarketInfo); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromGUIScreenID(js.context, OOGUIScreenID::kOptions)) == "GUI_SCREEN_OPTIONS");
  { JSValue v = js.string("GUI_SCREEN_OPTIONS"); OO_CHECK(OOGUIScreenIDFromJSValue(js.context, v) == OOGUIScreenID::kOptions); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromGUIScreenID(js.context, OOGUIScreenID::kGameOptions)) == "GUI_SCREEN_GAMEOPTIONS");
  { JSValue v = js.string("GUI_SCREEN_GAMEOPTIONS"); OO_CHECK(OOGUIScreenIDFromJSValue(js.context, v) == OOGUIScreenID::kGameOptions); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromGUIScreenID(js.context, OOGUIScreenID::kLoad)) == "GUI_SCREEN_LOAD");
  { JSValue v = js.string("GUI_SCREEN_LOAD"); OO_CHECK(OOGUIScreenIDFromJSValue(js.context, v) == OOGUIScreenID::kLoad); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromGUIScreenID(js.context, OOGUIScreenID::kSave)) == "GUI_SCREEN_SAVE");
  { JSValue v = js.string("GUI_SCREEN_SAVE"); OO_CHECK(OOGUIScreenIDFromJSValue(js.context, v) == OOGUIScreenID::kSave); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromGUIScreenID(js.context, OOGUIScreenID::kSaveOverwrite)) == "GUI_SCREEN_SAVE_OVERWRITE");
  { JSValue v = js.string("GUI_SCREEN_SAVE_OVERWRITE"); OO_CHECK(OOGUIScreenIDFromJSValue(js.context, v) == OOGUIScreenID::kSaveOverwrite); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromGUIScreenID(js.context, OOGUIScreenID::kStickMapper)) == "GUI_SCREEN_STICKMAPPER");
  { JSValue v = js.string("GUI_SCREEN_STICKMAPPER"); OO_CHECK(OOGUIScreenIDFromJSValue(js.context, v) == OOGUIScreenID::kStickMapper); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromGUIScreenID(js.context, OOGUIScreenID::kStickProfile)) == "GUI_SCREEN_STICKPROFILE");
  { JSValue v = js.string("GUI_SCREEN_STICKPROFILE"); OO_CHECK(OOGUIScreenIDFromJSValue(js.context, v) == OOGUIScreenID::kStickProfile); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromGUIScreenID(js.context, OOGUIScreenID::kMission)) == "GUI_SCREEN_MISSION");
  { JSValue v = js.string("GUI_SCREEN_MISSION"); OO_CHECK(OOGUIScreenIDFromJSValue(js.context, v) == OOGUIScreenID::kMission); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromGUIScreenID(js.context, OOGUIScreenID::kReport)) == "GUI_SCREEN_REPORT");
  { JSValue v = js.string("GUI_SCREEN_REPORT"); OO_CHECK(OOGUIScreenIDFromJSValue(js.context, v) == OOGUIScreenID::kReport); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromGUIScreenID(js.context, OOGUIScreenID::kInterfaces)) == "GUI_SCREEN_INTERFACES");
  { JSValue v = js.string("GUI_SCREEN_INTERFACES"); OO_CHECK(OOGUIScreenIDFromJSValue(js.context, v) == OOGUIScreenID::kInterfaces); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromGUIScreenID(js.context, OOGUIScreenID::kKeyboardConfirmClear)) == "GUI_SCREEN_KEYBOARD_CONFIRMCLEAR");
  { JSValue v = js.string("GUI_SCREEN_KEYBOARD_CONFIRMCLEAR"); OO_CHECK(OOGUIScreenIDFromJSValue(js.context, v) == OOGUIScreenID::kKeyboardConfirmClear); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromGUIScreenID(js.context, OOGUIScreenID::kKeyboardConfig)) == "GUI_SCREEN_KEYBOARD_CONFIG");
  { JSValue v = js.string("GUI_SCREEN_KEYBOARD_CONFIG"); OO_CHECK(OOGUIScreenIDFromJSValue(js.context, v) == OOGUIScreenID::kKeyboardConfig); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromGUIScreenID(js.context, OOGUIScreenID::kKeyboardEntry)) == "GUI_SCREEN_KEYBOARD_ENTRY");
  { JSValue v = js.string("GUI_SCREEN_KEYBOARD_ENTRY"); OO_CHECK(OOGUIScreenIDFromJSValue(js.context, v) == OOGUIScreenID::kKeyboardEntry); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromGUIScreenID(js.context, OOGUIScreenID::kKeyboardLayout)) == "GUI_SCREEN_KEYBOARD_LAYOUT");
  { JSValue v = js.string("GUI_SCREEN_KEYBOARD_LAYOUT"); OO_CHECK(OOGUIScreenIDFromJSValue(js.context, v) == OOGUIScreenID::kKeyboardLayout); JS_FreeValue(js.context, v); }
  { JSValue v = js.string("NOT_A_NAME"); OO_CHECK(OOGUIScreenIDFromJSValue(js.context, v) == (OOGUIScreenID)(OOGUIScreenID::kMain)); JS_FreeValue(js.context, v); }  // the fallback
  OO_CHECK(OOGUIScreenIDFromJSValue(js.context, JS_NewInt32(js.context, 1)) == (OOGUIScreenID)(OOGUIScreenID::kMain));  // not a string
}

OO_TEST(jsGalacticHyperspaceBehaviour) {
  JSStrings& js = Strings();
  OO_CHECK(js.text(OOJSValueFromGalacticHyperspaceBehaviour(js.context, OOGalacticHyperspaceBehaviour::kStandard)) == "BEHAVIOUR_STANDARD");
  { JSValue v = js.string("BEHAVIOUR_STANDARD"); OO_CHECK(OOGalacticHyperspaceBehaviourFromJSValue(js.context, v) == OOGalacticHyperspaceBehaviour::kStandard); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromGalacticHyperspaceBehaviour(js.context, OOGalacticHyperspaceBehaviour::kAllSystemsReachable)) == "BEHAVIOUR_ALL_SYSTEMS_REACHABLE");
  { JSValue v = js.string("BEHAVIOUR_ALL_SYSTEMS_REACHABLE"); OO_CHECK(OOGalacticHyperspaceBehaviourFromJSValue(js.context, v) == OOGalacticHyperspaceBehaviour::kAllSystemsReachable); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromGalacticHyperspaceBehaviour(js.context, OOGalacticHyperspaceBehaviour::kFixedCoordinates)) == "BEHAVIOUR_FIXED_COORDINATES");
  { JSValue v = js.string("BEHAVIOUR_FIXED_COORDINATES"); OO_CHECK(OOGalacticHyperspaceBehaviourFromJSValue(js.context, v) == OOGalacticHyperspaceBehaviour::kFixedCoordinates); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromGalacticHyperspaceBehaviour(js.context, OOGalacticHyperspaceBehaviour::kUnknown)) == "BEHAVIOUR_UNKNOWN");
  { JSValue v = js.string("BEHAVIOUR_UNKNOWN"); OO_CHECK(OOGalacticHyperspaceBehaviourFromJSValue(js.context, v) == OOGalacticHyperspaceBehaviour::kUnknown); JS_FreeValue(js.context, v); }
  { JSValue v = js.string("NOT_A_NAME"); OO_CHECK(OOGalacticHyperspaceBehaviourFromJSValue(js.context, v) == (OOGalacticHyperspaceBehaviour)(OOGalacticHyperspaceBehaviour::kUnknown)); JS_FreeValue(js.context, v); }  // the fallback
  OO_CHECK(OOGalacticHyperspaceBehaviourFromJSValue(js.context, JS_NewInt32(js.context, 1)) == (OOGalacticHyperspaceBehaviour)(OOGalacticHyperspaceBehaviour::kUnknown));  // not a string
}

OO_TEST(jsViewID) {
  JSStrings& js = Strings();
  OO_CHECK(js.text(OOJSValueFromViewID(js.context, OOViewID::kForward)) == "VIEW_FORWARD");
  { JSValue v = js.string("VIEW_FORWARD"); OO_CHECK(OOViewIDFromJSValue(js.context, v) == OOViewID::kForward); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromViewID(js.context, OOViewID::kAft)) == "VIEW_AFT");
  { JSValue v = js.string("VIEW_AFT"); OO_CHECK(OOViewIDFromJSValue(js.context, v) == OOViewID::kAft); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromViewID(js.context, OOViewID::kPort)) == "VIEW_PORT");
  { JSValue v = js.string("VIEW_PORT"); OO_CHECK(OOViewIDFromJSValue(js.context, v) == OOViewID::kPort); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromViewID(js.context, OOViewID::kStarboard)) == "VIEW_STARBOARD");
  { JSValue v = js.string("VIEW_STARBOARD"); OO_CHECK(OOViewIDFromJSValue(js.context, v) == OOViewID::kStarboard); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromViewID(js.context, OOViewID::kCustom)) == "VIEW_CUSTOM");
  { JSValue v = js.string("VIEW_CUSTOM"); OO_CHECK(OOViewIDFromJSValue(js.context, v) == OOViewID::kCustom); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromViewID(js.context, OOViewID::kNone)) == "VIEW_NONE");
  { JSValue v = js.string("VIEW_NONE"); OO_CHECK(OOViewIDFromJSValue(js.context, v) == OOViewID::kNone); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromViewID(js.context, OOViewID::kGUIDisplay)) == "VIEW_GUI_DISPLAY");
  { JSValue v = js.string("VIEW_GUI_DISPLAY"); OO_CHECK(OOViewIDFromJSValue(js.context, v) == OOViewID::kGUIDisplay); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromViewID(js.context, OOViewID::kBreakPattern)) == "VIEW_BREAK_PATTERN");
  { JSValue v = js.string("VIEW_BREAK_PATTERN"); OO_CHECK(OOViewIDFromJSValue(js.context, v) == OOViewID::kBreakPattern); JS_FreeValue(js.context, v); }
  { JSValue v = js.string("NOT_A_NAME"); OO_CHECK(OOViewIDFromJSValue(js.context, v) == (OOViewID)(OOViewID::kNone)); JS_FreeValue(js.context, v); }  // the fallback
  OO_CHECK(OOViewIDFromJSValue(js.context, JS_NewInt32(js.context, 1)) == (OOViewID)(OOViewID::kNone));  // not a string
}

OO_TEST(jsShipDamageType) {
  JSStrings& js = Strings();
  OO_CHECK(js.text(OOJSValueFromShipDamageType(js.context, OOShipDamageType::kScrape)) == "scrape damage");
  OO_CHECK(js.text(OOJSValueFromShipDamageType(js.context, OOShipDamageType::kHeat)) == "heat damage");
  OO_CHECK(js.text(OOJSValueFromShipDamageType(js.context, OOShipDamageType::kEnergy)) == "energy damage");
  OO_CHECK(js.text(OOJSValueFromShipDamageType(js.context, OOShipDamageType::kCascadeWeapon)) == "cascade weapon");
  OO_CHECK(js.text(OOJSValueFromShipDamageType(js.context, OOShipDamageType::kHitAPlanet)) == "hit a planet");
  OO_CHECK(js.text(OOJSValueFromShipDamageType(js.context, OOShipDamageType::kHitASun)) == "hit a sun");
  OO_CHECK(js.text(OOJSValueFromShipDamageType(js.context, OOShipDamageType::kRemoved)) == "removed");
}

OO_TEST(jsLegalStatusReason) {
  JSStrings& js = Strings();
  OO_CHECK(js.text(OOJSValueFromLegalStatusReason(js.context, OOLegalStatusReason::kUnknown)) == "unknown");
  OO_CHECK(js.text(OOJSValueFromLegalStatusReason(js.context, OOLegalStatusReason::kSetup)) == "setup actions");
  OO_CHECK(js.text(OOJSValueFromLegalStatusReason(js.context, OOLegalStatusReason::kByScript)) == "scripted");
  OO_CHECK(js.text(OOJSValueFromLegalStatusReason(js.context, OOLegalStatusReason::kAttackedPolice)) == "attacked police");
  OO_CHECK(js.text(OOJSValueFromLegalStatusReason(js.context, OOLegalStatusReason::kAttackedMainStation)) == "attacked main station");
  OO_CHECK(js.text(OOJSValueFromLegalStatusReason(js.context, OOLegalStatusReason::kAttackedInnocent)) == "attacked innocent");
  OO_CHECK(js.text(OOJSValueFromLegalStatusReason(js.context, OOLegalStatusReason::kSeenByPolice)) == "seen by police");
  OO_CHECK(js.text(OOJSValueFromLegalStatusReason(js.context, OOLegalStatusReason::kDistressCall)) == "distress call");
  OO_CHECK(js.text(OOJSValueFromLegalStatusReason(js.context, OOLegalStatusReason::kIllegalExports)) == "illegal exports");
  OO_CHECK(js.text(OOJSValueFromLegalStatusReason(js.context, OOLegalStatusReason::kIllegalImports)) == "illegal imports");
  OO_CHECK(js.text(OOJSValueFromLegalStatusReason(js.context, OOLegalStatusReason::kAssistingOffender)) == "assisting offenders");
  OO_CHECK(js.text(OOJSValueFromLegalStatusReason(js.context, OOLegalStatusReason::kNewGalaxy)) == "new galaxy");
  OO_CHECK(js.text(OOJSValueFromLegalStatusReason(js.context, OOLegalStatusReason::kNewSystem)) == "new system");
  OO_CHECK(js.text(OOJSValueFromLegalStatusReason(js.context, OOLegalStatusReason::kPaidFine)) == "paid fine");
  OO_CHECK(js.text(OOJSValueFromLegalStatusReason(js.context, OOLegalStatusReason::kEscapePod)) == "escape pod");
  OO_CHECK(js.text(OOJSValueFromLegalStatusReason(js.context, OOLegalStatusReason::kAssistingPolice)) == "assisting police");
  OO_CHECK(js.text(OOJSValueFromLegalStatusReason(js.context, OOLegalStatusReason::kPoliceAreClean)) == "police are clean");
}

OO_TEST_MAIN()
