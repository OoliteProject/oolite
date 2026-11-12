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
#include "OOEntityEnums.h"
#include "OOOpenGL.h"
#include "OOTypes.h"
#include "PlayerEntity.h"
#include "ShipEntity.h"
#include "WormholeEntity.h"
#include "oo_test.hpp"

OO_TEST(cxx_OOStringFromEntityStatus) {
  OO_CHECK(cxx_OOStringFromEntityStatus(STATUS_START_GAME) == "STATUS_START_GAME");
  OO_CHECK(cxx_OOStringFromEntityStatus(STATUS_RESTART_GAME) == "STATUS_RESTART_GAME");
  OO_CHECK(cxx_OOStringFromEntityStatus(STATUS_DEAD) == "STATUS_DEAD");
  OO_CHECK(cxx_OOStringFromEntityStatus(STATUS_INACTIVE) == "STATUS_INACTIVE");
  OO_CHECK(cxx_OOStringFromEntityStatus(STATUS_TEST) == "STATUS_TEST");
  OO_CHECK(cxx_OOStringFromEntityStatus(STATUS_COCKPIT_DISPLAY) == "STATUS_COCKPIT_DISPLAY");
  OO_CHECK(cxx_OOStringFromEntityStatus(STATUS_ACTIVE) == "STATUS_ACTIVE");
  OO_CHECK(cxx_OOStringFromEntityStatus(STATUS_EFFECT) == "STATUS_EFFECT");
  OO_CHECK(cxx_OOStringFromEntityStatus(STATUS_IN_FLIGHT) == "STATUS_IN_FLIGHT");
  OO_CHECK(cxx_OOStringFromEntityStatus(STATUS_DOCKED) == "STATUS_DOCKED");
  OO_CHECK(cxx_OOStringFromEntityStatus(STATUS_AUTOPILOT_ENGAGED) == "STATUS_AUTOPILOT_ENGAGED");
  OO_CHECK(cxx_OOStringFromEntityStatus(STATUS_DOCKING) == "STATUS_DOCKING");
  OO_CHECK(cxx_OOStringFromEntityStatus(STATUS_LAUNCHING) == "STATUS_LAUNCHING");
  OO_CHECK(cxx_OOStringFromEntityStatus(STATUS_WITCHSPACE_COUNTDOWN) == "STATUS_WITCHSPACE_COUNTDOWN");
  OO_CHECK(cxx_OOStringFromEntityStatus(STATUS_ENTERING_WITCHSPACE) == "STATUS_ENTERING_WITCHSPACE");
  OO_CHECK(cxx_OOStringFromEntityStatus(STATUS_EXITING_WITCHSPACE) == "STATUS_EXITING_WITCHSPACE");
  OO_CHECK(cxx_OOStringFromEntityStatus(STATUS_ESCAPE_SEQUENCE) == "STATUS_ESCAPE_SEQUENCE");
  OO_CHECK(cxx_OOStringFromEntityStatus(STATUS_IN_HOLD) == "STATUS_IN_HOLD");
  OO_CHECK(cxx_OOStringFromEntityStatus(STATUS_BEING_SCOOPED) == "STATUS_BEING_SCOOPED");
  OO_CHECK(cxx_OOStringFromEntityStatus(STATUS_HANDLING_ERROR) == "STATUS_HANDLING_ERROR");
}

OO_TEST(cxx_OOStringFromBehaviour) {
  OO_CHECK(cxx_OOStringFromBehaviour(BEHAVIOUR_IDLE) == "BEHAVIOUR_IDLE");
  OO_CHECK(cxx_OOStringFromBehaviour(BEHAVIOUR_TRACK_TARGET) == "BEHAVIOUR_TRACK_TARGET");
  OO_CHECK(cxx_OOStringFromBehaviour(BEHAVIOUR_TUMBLE) == "BEHAVIOUR_TUMBLE");
  OO_CHECK(cxx_OOStringFromBehaviour(BEHAVIOUR_STOP_STILL) == "BEHAVIOUR_STOP_STILL");
  OO_CHECK(cxx_OOStringFromBehaviour(BEHAVIOUR_STATION_KEEPING) == "BEHAVIOUR_STATION_KEEPING");
  OO_CHECK(cxx_OOStringFromBehaviour(BEHAVIOUR_ATTACK_TARGET) == "BEHAVIOUR_ATTACK_TARGET");
  OO_CHECK(cxx_OOStringFromBehaviour(BEHAVIOUR_ATTACK_FLY_TO_TARGET) == "BEHAVIOUR_ATTACK_FLY_TO_TARGET");
  OO_CHECK(cxx_OOStringFromBehaviour(BEHAVIOUR_ATTACK_FLY_FROM_TARGET) == "BEHAVIOUR_ATTACK_FLY_FROM_TARGET");
  OO_CHECK(cxx_OOStringFromBehaviour(BEHAVIOUR_RUNNING_DEFENSE) == "BEHAVIOUR_RUNNING_DEFENSE");
  OO_CHECK(cxx_OOStringFromBehaviour(BEHAVIOUR_FLEE_TARGET) == "BEHAVIOUR_FLEE_TARGET");
  OO_CHECK(cxx_OOStringFromBehaviour(BEHAVIOUR_ATTACK_FLY_TO_TARGET_SIX) == "BEHAVIOUR_ATTACK_FLY_TO_TARGET_SIX");
  OO_CHECK(cxx_OOStringFromBehaviour(BEHAVIOUR_ATTACK_MINING_TARGET) == "BEHAVIOUR_ATTACK_MINING_TARGET");
  OO_CHECK(cxx_OOStringFromBehaviour(BEHAVIOUR_EVASIVE_ACTION) == "BEHAVIOUR_EVASIVE_ACTION");
  OO_CHECK(cxx_OOStringFromBehaviour(BEHAVIOUR_FLEE_EVASIVE_ACTION) == "BEHAVIOUR_FLEE_EVASIVE_ACTION");
  OO_CHECK(cxx_OOStringFromBehaviour(BEHAVIOUR_ATTACK_BREAK_OFF_TARGET) == "BEHAVIOUR_ATTACK_BREAK_OFF_TARGET");
  OO_CHECK(cxx_OOStringFromBehaviour(BEHAVIOUR_ATTACK_SLOW_DOGFIGHT) == "BEHAVIOUR_ATTACK_SLOW_DOGFIGHT");
  OO_CHECK(cxx_OOStringFromBehaviour(BEHAVIOUR_ATTACK_FLY_TO_TARGET_TWELVE) == "BEHAVIOUR_ATTACK_FLY_TO_TARGET_TWELVE");
  OO_CHECK(cxx_OOStringFromBehaviour(BEHAVIOUR_ATTACK_SNIPER) == "BEHAVIOUR_ATTACK_SNIPER");
  OO_CHECK(cxx_OOStringFromBehaviour(BEHAVIOUR_ATTACK_BROADSIDE) == "BEHAVIOUR_ATTACK_BROADSIDE");
  OO_CHECK(cxx_OOStringFromBehaviour(BEHAVIOUR_ATTACK_BROADSIDE_LEFT) == "BEHAVIOUR_ATTACK_BROADSIDE_LEFT");
  OO_CHECK(cxx_OOStringFromBehaviour(BEHAVIOUR_ATTACK_BROADSIDE_RIGHT) == "BEHAVIOUR_ATTACK_BROADSIDE_RIGHT");
  OO_CHECK(cxx_OOStringFromBehaviour(BEHAVIOUR_CLOSE_TO_BROADSIDE_RANGE) == "BEHAVIOUR_CLOSE_TO_BROADSIDE_RANGE");
  OO_CHECK(cxx_OOStringFromBehaviour(BEHAVIOUR_CLOSE_WITH_TARGET) == "BEHAVIOUR_CLOSE_WITH_TARGET");
  OO_CHECK(cxx_OOStringFromBehaviour(BEHAVIOUR_AVOID_COLLISION) == "BEHAVIOUR_AVOID_COLLISION");
  OO_CHECK(cxx_OOStringFromBehaviour(BEHAVIOUR_TRACK_AS_TURRET) == "BEHAVIOUR_TRACK_AS_TURRET");
  OO_CHECK(cxx_OOStringFromBehaviour(BEHAVIOUR_FLY_RANGE_FROM_DESTINATION) == "BEHAVIOUR_FLY_RANGE_FROM_DESTINATION");
  OO_CHECK(cxx_OOStringFromBehaviour(BEHAVIOUR_FLY_TO_DESTINATION) == "BEHAVIOUR_FLY_TO_DESTINATION");
  OO_CHECK(cxx_OOStringFromBehaviour(BEHAVIOUR_FLY_FROM_DESTINATION) == "BEHAVIOUR_FLY_FROM_DESTINATION");
  OO_CHECK(cxx_OOStringFromBehaviour(BEHAVIOUR_FACE_DESTINATION) == "BEHAVIOUR_FACE_DESTINATION");
  OO_CHECK(cxx_OOStringFromBehaviour(BEHAVIOUR_FLY_THRU_NAVPOINTS) == "BEHAVIOUR_FLY_THRU_NAVPOINTS");
  OO_CHECK(cxx_OOStringFromBehaviour(BEHAVIOUR_LAND_ON_PLANET) == "BEHAVIOUR_LAND_ON_PLANET");
  OO_CHECK(cxx_OOStringFromBehaviour(BEHAVIOUR_COLLECT_TARGET) == "BEHAVIOUR_COLLECT_TARGET");
  OO_CHECK(cxx_OOStringFromBehaviour(BEHAVIOUR_INTERCEPT_TARGET) == "BEHAVIOUR_INTERCEPT_TARGET");
  OO_CHECK(cxx_OOStringFromBehaviour(BEHAVIOUR_FORMATION_FORM_UP) == "BEHAVIOUR_FORMATION_FORM_UP");
  OO_CHECK(cxx_OOStringFromBehaviour(BEHAVIOUR_FORMATION_BREAK) == "BEHAVIOUR_FORMATION_BREAK");
  OO_CHECK(cxx_OOStringFromBehaviour(BEHAVIOUR_ENERGY_BOMB_COUNTDOWN) == "BEHAVIOUR_ENERGY_BOMB_COUNTDOWN");
  OO_CHECK(cxx_OOStringFromBehaviour(BEHAVIOUR_TRACTORED) == "BEHAVIOUR_TRACTORED");
  OO_CHECK(cxx_OOStringFromBehaviour(BEHAVIOUR_SCRIPTED_AI) == "BEHAVIOUR_SCRIPTED_AI");
  OO_CHECK(cxx_OOStringFromBehaviour(BEHAVIOUR_SCRIPTED_ATTACK_AI) == "BEHAVIOUR_SCRIPTED_ATTACK_AI");
}

OO_TEST(cxx_OOStringFromCompassMode) {
  OO_CHECK(cxx_OOStringFromCompassMode(COMPASS_MODE_INACTIVE) == "COMPASS_MODE_INACTIVE");
  OO_CHECK(cxx_OOStringFromCompassMode(COMPASS_MODE_BASIC) == "COMPASS_MODE_BASIC");
  OO_CHECK(cxx_OOStringFromCompassMode(COMPASS_MODE_PLANET) == "COMPASS_MODE_PLANET");
  OO_CHECK(cxx_OOStringFromCompassMode(COMPASS_MODE_STATION) == "COMPASS_MODE_STATION");
  OO_CHECK(cxx_OOStringFromCompassMode(COMPASS_MODE_SUN) == "COMPASS_MODE_SUN");
  OO_CHECK(cxx_OOStringFromCompassMode(COMPASS_MODE_TARGET) == "COMPASS_MODE_TARGET");
  OO_CHECK(cxx_OOStringFromCompassMode(COMPASS_MODE_BEACONS) == "COMPASS_MODE_BEACONS");
}

OO_TEST(cxx_OOStringFromLongRangeChartMode) {
  OO_CHECK(cxx_OOStringFromLongRangeChartMode(OOLRC_MODE_UNKNOWN) == "OOLRC_MODE_UNKNOWN");
  OO_CHECK(cxx_OOStringFromLongRangeChartMode(OOLRC_MODE_SUNCOLOR) == "OOLRC_MODE_SUNCOLOR");
  OO_CHECK(cxx_OOStringFromLongRangeChartMode(OOLRC_MODE_ECONOMY) == "OOLRC_MODE_ECONOMY");
  OO_CHECK(cxx_OOStringFromLongRangeChartMode(OOLRC_MODE_GOVERNMENT) == "OOLRC_MODE_GOVERNMENT");
  OO_CHECK(cxx_OOStringFromLongRangeChartMode(OOLRC_MODE_TECHLEVEL) == "OOLRC_MODE_TECHLEVEL");
}

OO_TEST(cxx_OOStringFromGalacticHyperspaceBehaviour) {
  OO_CHECK(cxx_OOStringFromGalacticHyperspaceBehaviour(GALACTIC_HYPERSPACE_BEHAVIOUR_STANDARD) == "BEHAVIOUR_STANDARD");
  OO_CHECK(cxx_OOStringFromGalacticHyperspaceBehaviour(GALACTIC_HYPERSPACE_BEHAVIOUR_ALL_SYSTEMS_REACHABLE) == "BEHAVIOUR_ALL_SYSTEMS_REACHABLE");
  OO_CHECK(cxx_OOStringFromGalacticHyperspaceBehaviour(GALACTIC_HYPERSPACE_BEHAVIOUR_FIXED_COORDINATES) == "BEHAVIOUR_FIXED_COORDINATES");
  OO_CHECK(cxx_OOStringFromGalacticHyperspaceBehaviour(GALACTIC_HYPERSPACE_BEHAVIOUR_UNKNOWN) == "BEHAVIOUR_UNKNOWN");
}

OO_TEST(cxx_OOStringFromGUIScreenID) {
  OO_CHECK(cxx_OOStringFromGUIScreenID(GUI_SCREEN_MAIN) == "GUI_SCREEN_MAIN");
  OO_CHECK(cxx_OOStringFromGUIScreenID(GUI_SCREEN_INTRO1) == "GUI_SCREEN_INTRO1");
  OO_CHECK(cxx_OOStringFromGUIScreenID(GUI_SCREEN_SHIPLIBRARY) == "GUI_SCREEN_SHIPLIBRARY");
  OO_CHECK(cxx_OOStringFromGUIScreenID(GUI_SCREEN_KEYBOARD) == "GUI_SCREEN_KEYBOARD");
  OO_CHECK(cxx_OOStringFromGUIScreenID(GUI_SCREEN_NEWGAME) == "GUI_SCREEN_NEWGAME");
  OO_CHECK(cxx_OOStringFromGUIScreenID(GUI_SCREEN_OXZMANAGER) == "GUI_SCREEN_OXZMANAGER");
  OO_CHECK(cxx_OOStringFromGUIScreenID(GUI_SCREEN_STATUS) == "GUI_SCREEN_STATUS");
  OO_CHECK(cxx_OOStringFromGUIScreenID(GUI_SCREEN_MANIFEST) == "GUI_SCREEN_MANIFEST");
  OO_CHECK(cxx_OOStringFromGUIScreenID(GUI_SCREEN_EQUIP_SHIP) == "GUI_SCREEN_EQUIP_SHIP");
  OO_CHECK(cxx_OOStringFromGUIScreenID(GUI_SCREEN_SHIPYARD) == "GUI_SCREEN_SHIPYARD");
  OO_CHECK(cxx_OOStringFromGUIScreenID(GUI_SCREEN_LONG_RANGE_CHART) == "GUI_SCREEN_LONG_RANGE_CHART");
  OO_CHECK(cxx_OOStringFromGUIScreenID(GUI_SCREEN_SHORT_RANGE_CHART) == "GUI_SCREEN_SHORT_RANGE_CHART");
  OO_CHECK(cxx_OOStringFromGUIScreenID(GUI_SCREEN_SYSTEM_DATA) == "GUI_SCREEN_SYSTEM_DATA");
  OO_CHECK(cxx_OOStringFromGUIScreenID(GUI_SCREEN_MARKET) == "GUI_SCREEN_MARKET");
  OO_CHECK(cxx_OOStringFromGUIScreenID(GUI_SCREEN_MARKETINFO) == "GUI_SCREEN_MARKETINFO");
  OO_CHECK(cxx_OOStringFromGUIScreenID(GUI_SCREEN_OPTIONS) == "GUI_SCREEN_OPTIONS");
  OO_CHECK(cxx_OOStringFromGUIScreenID(GUI_SCREEN_GAMEOPTIONS) == "GUI_SCREEN_GAMEOPTIONS");
  OO_CHECK(cxx_OOStringFromGUIScreenID(GUI_SCREEN_LOAD) == "GUI_SCREEN_LOAD");
  OO_CHECK(cxx_OOStringFromGUIScreenID(GUI_SCREEN_SAVE) == "GUI_SCREEN_SAVE");
  OO_CHECK(cxx_OOStringFromGUIScreenID(GUI_SCREEN_SAVE_OVERWRITE) == "GUI_SCREEN_SAVE_OVERWRITE");
  OO_CHECK(cxx_OOStringFromGUIScreenID(GUI_SCREEN_STICKMAPPER) == "GUI_SCREEN_STICKMAPPER");
  OO_CHECK(cxx_OOStringFromGUIScreenID(GUI_SCREEN_STICKPROFILE) == "GUI_SCREEN_STICKPROFILE");
  OO_CHECK(cxx_OOStringFromGUIScreenID(GUI_SCREEN_MISSION) == "GUI_SCREEN_MISSION");
  OO_CHECK(cxx_OOStringFromGUIScreenID(GUI_SCREEN_REPORT) == "GUI_SCREEN_REPORT");
  OO_CHECK(cxx_OOStringFromGUIScreenID(GUI_SCREEN_INTERFACES) == "GUI_SCREEN_INTERFACES");
  OO_CHECK(cxx_OOStringFromGUIScreenID(GUI_SCREEN_KEYBOARD_CONFIRMCLEAR) == "GUI_SCREEN_KEYBOARD_CONFIRMCLEAR");
  OO_CHECK(cxx_OOStringFromGUIScreenID(GUI_SCREEN_KEYBOARD_CONFIG) == "GUI_SCREEN_KEYBOARD_CONFIG");
  OO_CHECK(cxx_OOStringFromGUIScreenID(GUI_SCREEN_KEYBOARD_ENTRY) == "GUI_SCREEN_KEYBOARD_ENTRY");
  OO_CHECK(cxx_OOStringFromGUIScreenID(GUI_SCREEN_KEYBOARD_LAYOUT) == "GUI_SCREEN_KEYBOARD_LAYOUT");
}

OO_TEST(cxx_OOStringFromScanClass) {
  OO_CHECK(cxx_OOStringFromScanClass(CLASS_NOT_SET) == "CLASS_NOT_SET");
  OO_CHECK(cxx_OOStringFromScanClass(CLASS_NO_DRAW) == "CLASS_NO_DRAW");
  OO_CHECK(cxx_OOStringFromScanClass(CLASS_NEUTRAL) == "CLASS_NEUTRAL");
  OO_CHECK(cxx_OOStringFromScanClass(CLASS_STATION) == "CLASS_STATION");
  OO_CHECK(cxx_OOStringFromScanClass(CLASS_TARGET) == "CLASS_TARGET");
  OO_CHECK(cxx_OOStringFromScanClass(CLASS_CARGO) == "CLASS_CARGO");
  OO_CHECK(cxx_OOStringFromScanClass(CLASS_MISSILE) == "CLASS_MISSILE");
  OO_CHECK(cxx_OOStringFromScanClass(CLASS_ROCK) == "CLASS_ROCK");
  OO_CHECK(cxx_OOStringFromScanClass(CLASS_MINE) == "CLASS_MINE");
  OO_CHECK(cxx_OOStringFromScanClass(CLASS_THARGOID) == "CLASS_THARGOID");
  OO_CHECK(cxx_OOStringFromScanClass(CLASS_BUOY) == "CLASS_BUOY");
  OO_CHECK(cxx_OOStringFromScanClass(CLASS_VISUAL_EFFECT) == "CLASS_VISUAL_EFFECT");
  OO_CHECK(cxx_OOStringFromScanClass(CLASS_WORMHOLE) == "CLASS_WORMHOLE");
  OO_CHECK(cxx_OOStringFromScanClass(CLASS_PLAYER) == "CLASS_PLAYER");
  OO_CHECK(cxx_OOStringFromScanClass(CLASS_POLICE) == "CLASS_POLICE");
  OO_CHECK(cxx_OOStringFromScanClass(CLASS_MILITARY) == "CLASS_MILITARY");
}

OO_TEST(cxx_OOStringFromShipDamageType) {
  OO_CHECK(cxx_OOStringFromShipDamageType(kOODamageTypeScrape) == "scrape damage");
  OO_CHECK(cxx_OOStringFromShipDamageType(kOODamageTypeHeat) == "heat damage");
  OO_CHECK(cxx_OOStringFromShipDamageType(kOODamageTypeEnergy) == "energy damage");
  OO_CHECK(cxx_OOStringFromShipDamageType(kOODamageTypeCascadeWeapon) == "cascade weapon");
  OO_CHECK(cxx_OOStringFromShipDamageType(kOODamageTypeHitAPlanet) == "hit a planet");
  OO_CHECK(cxx_OOStringFromShipDamageType(kOODamageTypeHitASun) == "hit a sun");
  OO_CHECK(cxx_OOStringFromShipDamageType(kOODamageTypeRemoved) == "removed");
}

OO_TEST(cxx_OOStringFromLegalStatusReason) {
  OO_CHECK(cxx_OOStringFromLegalStatusReason(kOOLegalStatusReasonUnknown) == "unknown");
  OO_CHECK(cxx_OOStringFromLegalStatusReason(kOOLegalStatusReasonSetup) == "setup actions");
  OO_CHECK(cxx_OOStringFromLegalStatusReason(kOOLegalStatusReasonByScript) == "scripted");
  OO_CHECK(cxx_OOStringFromLegalStatusReason(kOOLegalStatusReasonAttackedPolice) == "attacked police");
  OO_CHECK(cxx_OOStringFromLegalStatusReason(kOOLegalStatusReasonAttackedMainStation) == "attacked main station");
  OO_CHECK(cxx_OOStringFromLegalStatusReason(kOOLegalStatusReasonAttackedInnocent) == "attacked innocent");
  OO_CHECK(cxx_OOStringFromLegalStatusReason(kOOLegalStatusReasonSeenByPolice) == "seen by police");
  OO_CHECK(cxx_OOStringFromLegalStatusReason(kOOLegalStatusReasonDistressCall) == "distress call");
  OO_CHECK(cxx_OOStringFromLegalStatusReason(kOOLegalStatusReasonIllegalExports) == "illegal exports");
  OO_CHECK(cxx_OOStringFromLegalStatusReason(kOOLegalStatusReasonIllegalImports) == "illegal imports");
  OO_CHECK(cxx_OOStringFromLegalStatusReason(kOOLegalStatusReasonAssistingOffender) == "assisting offenders");
  OO_CHECK(cxx_OOStringFromLegalStatusReason(kOOLegalStatusReasonNewGalaxy) == "new galaxy");
  OO_CHECK(cxx_OOStringFromLegalStatusReason(kOOLegalStatusReasonNewSystem) == "new system");
  OO_CHECK(cxx_OOStringFromLegalStatusReason(kOOLegalStatusReasonPaidFine) == "paid fine");
  OO_CHECK(cxx_OOStringFromLegalStatusReason(kOOLegalStatusReasonEscapePod) == "escape pod");
  OO_CHECK(cxx_OOStringFromLegalStatusReason(kOOLegalStatusReasonAssistingPolice) == "assisting police");
  OO_CHECK(cxx_OOStringFromLegalStatusReason(kOOLegalStatusReasonPoliceAreClean) == "police are clean");
}

OO_TEST(cxx_OOEntityStatusFromString) {
  OO_CHECK(cxx_OOEntityStatusFromString("STATUS_START_GAME") == STATUS_START_GAME);
  OO_CHECK(cxx_OOEntityStatusFromString("STATUS_RESTART_GAME") == STATUS_RESTART_GAME);
  OO_CHECK(cxx_OOEntityStatusFromString("STATUS_DEAD") == STATUS_DEAD);
  OO_CHECK(cxx_OOEntityStatusFromString("STATUS_INACTIVE") == STATUS_INACTIVE);
  OO_CHECK(cxx_OOEntityStatusFromString("STATUS_TEST") == STATUS_TEST);
  OO_CHECK(cxx_OOEntityStatusFromString("STATUS_COCKPIT_DISPLAY") == STATUS_COCKPIT_DISPLAY);
  OO_CHECK(cxx_OOEntityStatusFromString("STATUS_ACTIVE") == STATUS_ACTIVE);
  OO_CHECK(cxx_OOEntityStatusFromString("STATUS_EFFECT") == STATUS_EFFECT);
  OO_CHECK(cxx_OOEntityStatusFromString("STATUS_IN_FLIGHT") == STATUS_IN_FLIGHT);
  OO_CHECK(cxx_OOEntityStatusFromString("STATUS_DOCKED") == STATUS_DOCKED);
  OO_CHECK(cxx_OOEntityStatusFromString("STATUS_AUTOPILOT_ENGAGED") == STATUS_AUTOPILOT_ENGAGED);
  OO_CHECK(cxx_OOEntityStatusFromString("STATUS_DOCKING") == STATUS_DOCKING);
  OO_CHECK(cxx_OOEntityStatusFromString("STATUS_LAUNCHING") == STATUS_LAUNCHING);
  OO_CHECK(cxx_OOEntityStatusFromString("STATUS_WITCHSPACE_COUNTDOWN") == STATUS_WITCHSPACE_COUNTDOWN);
  OO_CHECK(cxx_OOEntityStatusFromString("STATUS_ENTERING_WITCHSPACE") == STATUS_ENTERING_WITCHSPACE);
  OO_CHECK(cxx_OOEntityStatusFromString("STATUS_EXITING_WITCHSPACE") == STATUS_EXITING_WITCHSPACE);
  OO_CHECK(cxx_OOEntityStatusFromString("STATUS_ESCAPE_SEQUENCE") == STATUS_ESCAPE_SEQUENCE);
  OO_CHECK(cxx_OOEntityStatusFromString("STATUS_IN_HOLD") == STATUS_IN_HOLD);
  OO_CHECK(cxx_OOEntityStatusFromString("STATUS_BEING_SCOOPED") == STATUS_BEING_SCOOPED);
  OO_CHECK(cxx_OOEntityStatusFromString("STATUS_HANDLING_ERROR") == STATUS_HANDLING_ERROR);
  OO_CHECK(cxx_OOEntityStatusFromString("NOT_A_NAME") == STATUS_INACTIVE);  // the fallback
  OO_CHECK(cxx_OOEntityStatusFromString("") == STATUS_INACTIVE);
}

OO_TEST(cxx_OOCompassModeFromString) {
  OO_CHECK(cxx_OOCompassModeFromString("COMPASS_MODE_INACTIVE") == COMPASS_MODE_INACTIVE);
  OO_CHECK(cxx_OOCompassModeFromString("COMPASS_MODE_BASIC") == COMPASS_MODE_BASIC);
  OO_CHECK(cxx_OOCompassModeFromString("COMPASS_MODE_PLANET") == COMPASS_MODE_PLANET);
  OO_CHECK(cxx_OOCompassModeFromString("COMPASS_MODE_STATION") == COMPASS_MODE_STATION);
  OO_CHECK(cxx_OOCompassModeFromString("COMPASS_MODE_SUN") == COMPASS_MODE_SUN);
  OO_CHECK(cxx_OOCompassModeFromString("COMPASS_MODE_TARGET") == COMPASS_MODE_TARGET);
  OO_CHECK(cxx_OOCompassModeFromString("COMPASS_MODE_BEACONS") == COMPASS_MODE_BEACONS);
  OO_CHECK(cxx_OOCompassModeFromString("NOT_A_NAME") == COMPASS_MODE_BASIC);  // the fallback
  OO_CHECK(cxx_OOCompassModeFromString("") == COMPASS_MODE_BASIC);
}

OO_TEST(cxx_OOGalacticHyperspaceBehaviourFromString) {
  OO_CHECK(cxx_OOGalacticHyperspaceBehaviourFromString("BEHAVIOUR_STANDARD") == GALACTIC_HYPERSPACE_BEHAVIOUR_STANDARD);
  OO_CHECK(cxx_OOGalacticHyperspaceBehaviourFromString("BEHAVIOUR_ALL_SYSTEMS_REACHABLE") == GALACTIC_HYPERSPACE_BEHAVIOUR_ALL_SYSTEMS_REACHABLE);
  OO_CHECK(cxx_OOGalacticHyperspaceBehaviourFromString("BEHAVIOUR_FIXED_COORDINATES") == GALACTIC_HYPERSPACE_BEHAVIOUR_FIXED_COORDINATES);
  OO_CHECK(cxx_OOGalacticHyperspaceBehaviourFromString("BEHAVIOUR_UNKNOWN") == GALACTIC_HYPERSPACE_BEHAVIOUR_UNKNOWN);
  OO_CHECK(cxx_OOGalacticHyperspaceBehaviourFromString("NOT_A_NAME") == GALACTIC_HYPERSPACE_BEHAVIOUR_UNKNOWN);  // the fallback
  OO_CHECK(cxx_OOGalacticHyperspaceBehaviourFromString("") == GALACTIC_HYPERSPACE_BEHAVIOUR_UNKNOWN);
}

OO_TEST(cxx_OOGUIScreenIDFromString) {
  OO_CHECK(cxx_OOGUIScreenIDFromString("GUI_SCREEN_MAIN") == GUI_SCREEN_MAIN);
  OO_CHECK(cxx_OOGUIScreenIDFromString("GUI_SCREEN_INTRO1") == GUI_SCREEN_INTRO1);
  OO_CHECK(cxx_OOGUIScreenIDFromString("GUI_SCREEN_SHIPLIBRARY") == GUI_SCREEN_SHIPLIBRARY);
  OO_CHECK(cxx_OOGUIScreenIDFromString("GUI_SCREEN_KEYBOARD") == GUI_SCREEN_KEYBOARD);
  OO_CHECK(cxx_OOGUIScreenIDFromString("GUI_SCREEN_NEWGAME") == GUI_SCREEN_NEWGAME);
  OO_CHECK(cxx_OOGUIScreenIDFromString("GUI_SCREEN_OXZMANAGER") == GUI_SCREEN_OXZMANAGER);
  OO_CHECK(cxx_OOGUIScreenIDFromString("GUI_SCREEN_STATUS") == GUI_SCREEN_STATUS);
  OO_CHECK(cxx_OOGUIScreenIDFromString("GUI_SCREEN_MANIFEST") == GUI_SCREEN_MANIFEST);
  OO_CHECK(cxx_OOGUIScreenIDFromString("GUI_SCREEN_EQUIP_SHIP") == GUI_SCREEN_EQUIP_SHIP);
  OO_CHECK(cxx_OOGUIScreenIDFromString("GUI_SCREEN_SHIPYARD") == GUI_SCREEN_SHIPYARD);
  OO_CHECK(cxx_OOGUIScreenIDFromString("GUI_SCREEN_LONG_RANGE_CHART") == GUI_SCREEN_LONG_RANGE_CHART);
  OO_CHECK(cxx_OOGUIScreenIDFromString("GUI_SCREEN_SHORT_RANGE_CHART") == GUI_SCREEN_SHORT_RANGE_CHART);
  OO_CHECK(cxx_OOGUIScreenIDFromString("GUI_SCREEN_SYSTEM_DATA") == GUI_SCREEN_SYSTEM_DATA);
  OO_CHECK(cxx_OOGUIScreenIDFromString("GUI_SCREEN_MARKET") == GUI_SCREEN_MARKET);
  OO_CHECK(cxx_OOGUIScreenIDFromString("GUI_SCREEN_MARKETINFO") == GUI_SCREEN_MARKETINFO);
  OO_CHECK(cxx_OOGUIScreenIDFromString("GUI_SCREEN_OPTIONS") == GUI_SCREEN_OPTIONS);
  OO_CHECK(cxx_OOGUIScreenIDFromString("GUI_SCREEN_GAMEOPTIONS") == GUI_SCREEN_GAMEOPTIONS);
  OO_CHECK(cxx_OOGUIScreenIDFromString("GUI_SCREEN_LOAD") == GUI_SCREEN_LOAD);
  OO_CHECK(cxx_OOGUIScreenIDFromString("GUI_SCREEN_SAVE") == GUI_SCREEN_SAVE);
  OO_CHECK(cxx_OOGUIScreenIDFromString("GUI_SCREEN_SAVE_OVERWRITE") == GUI_SCREEN_SAVE_OVERWRITE);
  OO_CHECK(cxx_OOGUIScreenIDFromString("GUI_SCREEN_STICKMAPPER") == GUI_SCREEN_STICKMAPPER);
  OO_CHECK(cxx_OOGUIScreenIDFromString("GUI_SCREEN_STICKPROFILE") == GUI_SCREEN_STICKPROFILE);
  OO_CHECK(cxx_OOGUIScreenIDFromString("GUI_SCREEN_MISSION") == GUI_SCREEN_MISSION);
  OO_CHECK(cxx_OOGUIScreenIDFromString("GUI_SCREEN_REPORT") == GUI_SCREEN_REPORT);
  OO_CHECK(cxx_OOGUIScreenIDFromString("GUI_SCREEN_INTERFACES") == GUI_SCREEN_INTERFACES);
  OO_CHECK(cxx_OOGUIScreenIDFromString("GUI_SCREEN_KEYBOARD_CONFIRMCLEAR") == GUI_SCREEN_KEYBOARD_CONFIRMCLEAR);
  OO_CHECK(cxx_OOGUIScreenIDFromString("GUI_SCREEN_KEYBOARD_CONFIG") == GUI_SCREEN_KEYBOARD_CONFIG);
  OO_CHECK(cxx_OOGUIScreenIDFromString("GUI_SCREEN_KEYBOARD_ENTRY") == GUI_SCREEN_KEYBOARD_ENTRY);
  OO_CHECK(cxx_OOGUIScreenIDFromString("GUI_SCREEN_KEYBOARD_LAYOUT") == GUI_SCREEN_KEYBOARD_LAYOUT);
  OO_CHECK(cxx_OOGUIScreenIDFromString("NOT_A_NAME") == GUI_SCREEN_MAIN);  // the fallback
  OO_CHECK(cxx_OOGUIScreenIDFromString("") == GUI_SCREEN_MAIN);
}

OO_TEST(cxx_OOScanClassFromString) {
  OO_CHECK(cxx_OOScanClassFromString("CLASS_NOT_SET") == CLASS_NOT_SET);
  OO_CHECK(cxx_OOScanClassFromString("CLASS_NO_DRAW") == CLASS_NO_DRAW);
  OO_CHECK(cxx_OOScanClassFromString("CLASS_NEUTRAL") == CLASS_NEUTRAL);
  OO_CHECK(cxx_OOScanClassFromString("CLASS_STATION") == CLASS_STATION);
  OO_CHECK(cxx_OOScanClassFromString("CLASS_TARGET") == CLASS_TARGET);
  OO_CHECK(cxx_OOScanClassFromString("CLASS_CARGO") == CLASS_CARGO);
  OO_CHECK(cxx_OOScanClassFromString("CLASS_MISSILE") == CLASS_MISSILE);
  OO_CHECK(cxx_OOScanClassFromString("CLASS_ROCK") == CLASS_ROCK);
  OO_CHECK(cxx_OOScanClassFromString("CLASS_MINE") == CLASS_MINE);
  OO_CHECK(cxx_OOScanClassFromString("CLASS_THARGOID") == CLASS_THARGOID);
  OO_CHECK(cxx_OOScanClassFromString("CLASS_BUOY") == CLASS_BUOY);
  OO_CHECK(cxx_OOScanClassFromString("CLASS_VISUAL_EFFECT") == CLASS_VISUAL_EFFECT);
  OO_CHECK(cxx_OOScanClassFromString("CLASS_WORMHOLE") == CLASS_WORMHOLE);
  OO_CHECK(cxx_OOScanClassFromString("CLASS_PLAYER") == CLASS_PLAYER);
  OO_CHECK(cxx_OOScanClassFromString("CLASS_POLICE") == CLASS_POLICE);
  OO_CHECK(cxx_OOScanClassFromString("CLASS_MILITARY") == CLASS_MILITARY);
  OO_CHECK(cxx_OOScanClassFromString("NOT_A_NAME") == CLASS_NOT_SET);  // the fallback
  OO_CHECK(cxx_OOScanClassFromString("") == CLASS_NOT_SET);
}

OO_TEST(cxx_OOLongRangeChartModeFromString) {
  OO_CHECK(cxx_OOLongRangeChartModeFromString("OOLRC_MODE_UNKNOWN") == OOLRC_MODE_UNKNOWN);
  OO_CHECK(cxx_OOLongRangeChartModeFromString("OOLRC_MODE_SUNCOLOR") == OOLRC_MODE_SUNCOLOR);
  OO_CHECK(cxx_OOLongRangeChartModeFromString("OOLRC_MODE_ECONOMY") == OOLRC_MODE_ECONOMY);
  OO_CHECK(cxx_OOLongRangeChartModeFromString("OOLRC_MODE_GOVERNMENT") == OOLRC_MODE_GOVERNMENT);
  OO_CHECK(cxx_OOLongRangeChartModeFromString("OOLRC_MODE_TECHLEVEL") == OOLRC_MODE_TECHLEVEL);
  OO_CHECK(cxx_OOLongRangeChartModeFromString("NOT_A_NAME") == OOLRC_MODE_UNKNOWN);  // the fallback
  OO_CHECK(cxx_OOLongRangeChartModeFromString("") == OOLRC_MODE_UNKNOWN);
}

OO_TEST(cxx_RouteTypeToString) {
  OO_CHECK(cxx_RouteTypeToString(OORouteType::kNone) == "OPTIMIZED_BY_NONE");
  OO_CHECK(cxx_RouteTypeToString(OORouteType::kJumps) == "OPTIMIZED_BY_JUMPS");
  OO_CHECK(cxx_RouteTypeToString(OORouteType::kTime) == "OPTIMIZED_BY_TIME");
}

OO_TEST(cxx_CargoTypeToString) {
  OO_CHECK(cxx_CargoTypeToString(OOCargoType::kNotCargo) == "CARGO_NOT_CARGO");
  OO_CHECK(cxx_CargoTypeToString(OOCargoType::kSlaves) == "CARGO_SLAVES");
  OO_CHECK(cxx_CargoTypeToString(OOCargoType::kAlloy) == "CARGO_ALLOY");
  OO_CHECK(cxx_CargoTypeToString(OOCargoType::kMinerals) == "CARGO_MINERALS");
  OO_CHECK(cxx_CargoTypeToString(OOCargoType::kThargoid) == "CARGO_THARGOID");
  OO_CHECK(cxx_CargoTypeToString(OOCargoType::kRandom) == "CARGO_RANDOM");
  OO_CHECK(cxx_CargoTypeToString(OOCargoType::kScriptedItem) == "CARGO_SCRIPTED_ITEM");
  OO_CHECK(cxx_CargoTypeToString(OOCargoType::kCharacter) == "CARGO_CHARACTER");
}

OO_TEST(cxx_StringToCargoType) {
  OO_CHECK(cxx_StringToCargoType("CARGO_NOT_CARGO") == OOCargoType::kNotCargo);
  OO_CHECK(cxx_StringToCargoType("CARGO_SLAVES") == OOCargoType::kSlaves);
  OO_CHECK(cxx_StringToCargoType("CARGO_ALLOY") == OOCargoType::kAlloy);
  OO_CHECK(cxx_StringToCargoType("CARGO_MINERALS") == OOCargoType::kMinerals);
  OO_CHECK(cxx_StringToCargoType("CARGO_THARGOID") == OOCargoType::kThargoid);
  OO_CHECK(cxx_StringToCargoType("CARGO_RANDOM") == OOCargoType::kRandom);
  OO_CHECK(cxx_StringToCargoType("CARGO_SCRIPTED_ITEM") == OOCargoType::kScriptedItem);
  OO_CHECK(cxx_StringToCargoType("CARGO_CHARACTER") == OOCargoType::kCharacter);
  OO_CHECK(cxx_StringToCargoType("CARGO_CARRIED") == OOCargoType::kRandom);
  OO_CHECK(cxx_StringToCargoType("NOT_A_NAME") == OOCargoType::kNotCargo);  // the fallback
  OO_CHECK(cxx_StringToCargoType("") == OOCargoType::kNotCargo);
}

OO_TEST(cxx_EnergyUnitTypeToString) {
  OO_CHECK(cxx_EnergyUnitTypeToString(OOEnergyUnitType::kNone) == "ENERGY_UNIT_NONE");
  OO_CHECK(cxx_EnergyUnitTypeToString(OOEnergyUnitType::kNormal) == "ENERGY_UNIT_NORMAL");
  OO_CHECK(cxx_EnergyUnitTypeToString(OOEnergyUnitType::kNaval) == "ENERGY_UNIT_NAVAL");
  OO_CHECK(cxx_EnergyUnitTypeToString(OOEnergyUnitType::kNormalDamaged) == "ENERGY_UNIT_NORMAL_DAMAGED");
  OO_CHECK(cxx_EnergyUnitTypeToString(OOEnergyUnitType::kNavalDamaged) == "ENERGY_UNIT_NAVAL_DAMAGED");
  OO_CHECK(cxx_EnergyUnitTypeToString(OOEnergyUnitType::kOldNormal) == "Unsupported energy unit");
  OO_CHECK(cxx_EnergyUnitTypeToString(OOEnergyUnitType::kOldNaval) == "Unsupported energy unit");
}

OO_TEST(cxx_StringToEnergyUnitType) {
  OO_CHECK(cxx_StringToEnergyUnitType("ENERGY_UNIT_NONE") == OOEnergyUnitType::kNone);
  OO_CHECK(cxx_StringToEnergyUnitType("ENERGY_UNIT_NORMAL") == OOEnergyUnitType::kNormal);
  OO_CHECK(cxx_StringToEnergyUnitType("ENERGY_UNIT_NAVAL") == OOEnergyUnitType::kNaval);
  OO_CHECK(cxx_StringToEnergyUnitType("ENERGY_UNIT_NORMAL_DAMAGED") == OOEnergyUnitType::kNormalDamaged);
  OO_CHECK(cxx_StringToEnergyUnitType("ENERGY_UNIT_NAVAL_DAMAGED") == OOEnergyUnitType::kNavalDamaged);
  OO_CHECK(cxx_StringToEnergyUnitType("NOT_A_NAME") == OOEnergyUnitType::kNone);  // the fallback
  OO_CHECK(cxx_StringToEnergyUnitType("") == OOEnergyUnitType::kNone);
}

OO_TEST(cxx_OOStringFromShaderSetting) {
  OO_CHECK(cxx_OOStringFromShaderSetting(OOShaderSetting::kOff) == "SHADERS_OFF");
  OO_CHECK(cxx_OOStringFromShaderSetting(OOShaderSetting::kSimple) == "SHADERS_SIMPLE");
  OO_CHECK(cxx_OOStringFromShaderSetting(OOShaderSetting::kFull) == "SHADERS_FULL");
  OO_CHECK(cxx_OOStringFromShaderSetting(OOShaderSetting::kNotSupported) == "SHADERS_NOT_SUPPORTED");
}

OO_TEST(cxx_OOShaderSettingFromString) {
  OO_CHECK(cxx_OOShaderSettingFromString("SHADERS_OFF") == OOShaderSetting::kOff);
  OO_CHECK(cxx_OOShaderSettingFromString("SHADERS_SIMPLE") == OOShaderSetting::kSimple);
  OO_CHECK(cxx_OOShaderSettingFromString("SHADERS_FULL") == OOShaderSetting::kFull);
  OO_CHECK(cxx_OOShaderSettingFromString("SHADERS_NOT_SUPPORTED") == OOShaderSetting::kNotSupported);
  OO_CHECK(cxx_OOShaderSettingFromString("NOT_A_NAME") == OOShaderSetting::kNotSupported);  // the fallback
  OO_CHECK(cxx_OOShaderSettingFromString("") == OOShaderSetting::kNotSupported);
}

OO_TEST(cxx_StringToRouteType) {
  OO_CHECK(cxx_StringToRouteType("OPTIMIZED_BY_NONE") == OORouteType::kNone);
  OO_CHECK(cxx_StringToRouteType("OPTIMIZED_BY_JUMPS") == OORouteType::kJumps);
  OO_CHECK(cxx_StringToRouteType("OPTIMIZED_BY_TIME") == OORouteType::kTime);
  OO_CHECK(cxx_StringToRouteType("NOT_A_NAME") == OORouteType::kJumps);  // the fallback
  OO_CHECK(cxx_StringToRouteType("") == OORouteType::kJumps);
}

OO_TEST(cxx_DockingClearanceStatusToString) {
  OO_CHECK(cxx_DockingClearanceStatusToString(OODockingClearanceStatus::kNone) == "DOCKING_CLEARANCE_STATUS_NONE");
  OO_CHECK(cxx_DockingClearanceStatusToString(OODockingClearanceStatus::kRequested) == "DOCKING_CLEARANCE_STATUS_REQUESTED");
  OO_CHECK(cxx_DockingClearanceStatusToString(OODockingClearanceStatus::kNotRequired) == "DOCKING_CLEARANCE_STATUS_NOT_REQUIRED");
  OO_CHECK(cxx_DockingClearanceStatusToString(OODockingClearanceStatus::kGranted) == "DOCKING_CLEARANCE_STATUS_GRANTED");
  OO_CHECK(cxx_DockingClearanceStatusToString(OODockingClearanceStatus::kTimingOut) == "DOCKING_CLEARANCE_STATUS_TIMING_OUT");
}

OO_TEST(cxx_OOStringFromGraphicsDetail) {
  OO_CHECK(cxx_OOStringFromGraphicsDetail(OOGraphicsDetail::kMinimum) == "DETAIL_LEVEL_MINIMUM");
  OO_CHECK(cxx_OOStringFromGraphicsDetail(OOGraphicsDetail::kNormal) == "DETAIL_LEVEL_NORMAL");
  OO_CHECK(cxx_OOStringFromGraphicsDetail(OOGraphicsDetail::kShaders) == "DETAIL_LEVEL_SHADERS");
  OO_CHECK(cxx_OOStringFromGraphicsDetail(OOGraphicsDetail::kExtras) == "DETAIL_LEVEL_EXTRAS");
}

OO_TEST(cxx_OOGraphicsDetailFromString) {
  OO_CHECK(cxx_OOGraphicsDetailFromString("DETAIL_LEVEL_MINIMUM") == OOGraphicsDetail::kMinimum);
  OO_CHECK(cxx_OOGraphicsDetailFromString("DETAIL_LEVEL_NORMAL") == OOGraphicsDetail::kNormal);
  OO_CHECK(cxx_OOGraphicsDetailFromString("DETAIL_LEVEL_SHADERS") == OOGraphicsDetail::kShaders);
  OO_CHECK(cxx_OOGraphicsDetailFromString("DETAIL_LEVEL_EXTRAS") == OOGraphicsDetail::kExtras);
  OO_CHECK(cxx_OOGraphicsDetailFromString("NOT_A_NAME") == OOGraphicsDetail::kMinimum);  // the fallback
  OO_CHECK(cxx_OOGraphicsDetailFromString("") == OOGraphicsDetail::kMinimum);
}

OO_TEST(cxx_OOStringFromHDRToneMapper) {
  OO_CHECK(cxx_OOStringFromHDRToneMapper(OOHDRToneMapper::kNone) == "OOHDR_TONEMAPPER_NONE");
  OO_CHECK(cxx_OOStringFromHDRToneMapper(OOHDRToneMapper::kAcesApprox) == "OOHDR_TONEMAPPER_ACES_APPROX");
  OO_CHECK(cxx_OOStringFromHDRToneMapper(OOHDRToneMapper::kDice) == "OOHDR_TONEMAPPER_DICE");
  OO_CHECK(cxx_OOStringFromHDRToneMapper(OOHDRToneMapper::kUchimura) == "OOHDR_TONEMAPPER_UCHIMURA");
  OO_CHECK(cxx_OOStringFromHDRToneMapper(OOHDRToneMapper::kReinhard) == "OOHDR_TONEMAPPER_REINHARD");
}

OO_TEST(cxx_OOHDRToneMapperFromString) {
  OO_CHECK(cxx_OOHDRToneMapperFromString("OOHDR_TONEMAPPER_NONE") == OOHDRToneMapper::kNone);
  OO_CHECK(cxx_OOHDRToneMapperFromString("OOHDR_TONEMAPPER_ACES_APPROX") == OOHDRToneMapper::kAcesApprox);
  OO_CHECK(cxx_OOHDRToneMapperFromString("OOHDR_TONEMAPPER_DICE") == OOHDRToneMapper::kDice);
  OO_CHECK(cxx_OOHDRToneMapperFromString("OOHDR_TONEMAPPER_UCHIMURA") == OOHDRToneMapper::kUchimura);
  OO_CHECK(cxx_OOHDRToneMapperFromString("OOHDR_TONEMAPPER_REINHARD") == OOHDRToneMapper::kReinhard);
  OO_CHECK(cxx_OOHDRToneMapperFromString("NOT_A_NAME") == OOHDRToneMapper::kAcesApprox);  // the fallback
  OO_CHECK(cxx_OOHDRToneMapperFromString("") == OOHDRToneMapper::kAcesApprox);
}

OO_TEST(cxx_OOStringFromSDRToneMapper) {
  OO_CHECK(cxx_OOStringFromSDRToneMapper(OOSDRToneMapper::kNone) == "OOSDR_TONEMAPPER_NONE");
  OO_CHECK(cxx_OOStringFromSDRToneMapper(OOSDRToneMapper::kAces) == "OOSDR_TONEMAPPER_ACES");
  OO_CHECK(cxx_OOStringFromSDRToneMapper(OOSDRToneMapper::kAgX) == "OOSDR_TONEMAPPER_AgX");
  OO_CHECK(cxx_OOStringFromSDRToneMapper(OOSDRToneMapper::kHejlDawson) == "OOSDR_TONEMAPPER_HEJLDAWSON");
  OO_CHECK(cxx_OOStringFromSDRToneMapper(OOSDRToneMapper::kUC2) == "OOSDR_TONEMAPPER_UC2");
  OO_CHECK(cxx_OOStringFromSDRToneMapper(OOSDRToneMapper::kUchimura) == "OOSDR_TONEMAPPER_UCHIMURA");
  OO_CHECK(cxx_OOStringFromSDRToneMapper(OOSDRToneMapper::kReinhard) == "OOSDR_TONEMAPPER_REINHARD");
}

OO_TEST(cxx_OOSDRToneMapperFromString) {
  OO_CHECK(cxx_OOSDRToneMapperFromString("OOSDR_TONEMAPPER_NONE") == OOSDRToneMapper::kNone);
  OO_CHECK(cxx_OOSDRToneMapperFromString("OOSDR_TONEMAPPER_ACES") == OOSDRToneMapper::kAces);
  OO_CHECK(cxx_OOSDRToneMapperFromString("OOSDR_TONEMAPPER_AgX") == OOSDRToneMapper::kAgX);
  OO_CHECK(cxx_OOSDRToneMapperFromString("OOSDR_TONEMAPPER_HEJLDAWSON") == OOSDRToneMapper::kHejlDawson);
  OO_CHECK(cxx_OOSDRToneMapperFromString("OOSDR_TONEMAPPER_UC2") == OOSDRToneMapper::kUC2);
  OO_CHECK(cxx_OOSDRToneMapperFromString("OOSDR_TONEMAPPER_UCHIMURA") == OOSDRToneMapper::kUchimura);
  OO_CHECK(cxx_OOSDRToneMapperFromString("OOSDR_TONEMAPPER_REINHARD") == OOSDRToneMapper::kReinhard);
  OO_CHECK(cxx_OOSDRToneMapperFromString("NOT_A_NAME") == OOSDRToneMapper::kAces);  // the fallback
  OO_CHECK(cxx_OOSDRToneMapperFromString("") == OOSDRToneMapper::kAces);
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
  OO_CHECK(js.text(OOJSValueFromEntityStatus(js.context, STATUS_START_GAME)) == "STATUS_START_GAME");
  { JSValue v = js.string("STATUS_START_GAME"); OO_CHECK(OOEntityStatusFromJSValue(js.context, v) == STATUS_START_GAME); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromEntityStatus(js.context, STATUS_RESTART_GAME)) == "STATUS_RESTART_GAME");
  { JSValue v = js.string("STATUS_RESTART_GAME"); OO_CHECK(OOEntityStatusFromJSValue(js.context, v) == STATUS_RESTART_GAME); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromEntityStatus(js.context, STATUS_DEAD)) == "STATUS_DEAD");
  { JSValue v = js.string("STATUS_DEAD"); OO_CHECK(OOEntityStatusFromJSValue(js.context, v) == STATUS_DEAD); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromEntityStatus(js.context, STATUS_INACTIVE)) == "STATUS_INACTIVE");
  { JSValue v = js.string("STATUS_INACTIVE"); OO_CHECK(OOEntityStatusFromJSValue(js.context, v) == STATUS_INACTIVE); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromEntityStatus(js.context, STATUS_TEST)) == "STATUS_TEST");
  { JSValue v = js.string("STATUS_TEST"); OO_CHECK(OOEntityStatusFromJSValue(js.context, v) == STATUS_TEST); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromEntityStatus(js.context, STATUS_COCKPIT_DISPLAY)) == "STATUS_COCKPIT_DISPLAY");
  { JSValue v = js.string("STATUS_COCKPIT_DISPLAY"); OO_CHECK(OOEntityStatusFromJSValue(js.context, v) == STATUS_COCKPIT_DISPLAY); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromEntityStatus(js.context, STATUS_ACTIVE)) == "STATUS_ACTIVE");
  { JSValue v = js.string("STATUS_ACTIVE"); OO_CHECK(OOEntityStatusFromJSValue(js.context, v) == STATUS_ACTIVE); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromEntityStatus(js.context, STATUS_EFFECT)) == "STATUS_EFFECT");
  { JSValue v = js.string("STATUS_EFFECT"); OO_CHECK(OOEntityStatusFromJSValue(js.context, v) == STATUS_EFFECT); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromEntityStatus(js.context, STATUS_IN_FLIGHT)) == "STATUS_IN_FLIGHT");
  { JSValue v = js.string("STATUS_IN_FLIGHT"); OO_CHECK(OOEntityStatusFromJSValue(js.context, v) == STATUS_IN_FLIGHT); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromEntityStatus(js.context, STATUS_DOCKED)) == "STATUS_DOCKED");
  { JSValue v = js.string("STATUS_DOCKED"); OO_CHECK(OOEntityStatusFromJSValue(js.context, v) == STATUS_DOCKED); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromEntityStatus(js.context, STATUS_AUTOPILOT_ENGAGED)) == "STATUS_AUTOPILOT_ENGAGED");
  { JSValue v = js.string("STATUS_AUTOPILOT_ENGAGED"); OO_CHECK(OOEntityStatusFromJSValue(js.context, v) == STATUS_AUTOPILOT_ENGAGED); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromEntityStatus(js.context, STATUS_DOCKING)) == "STATUS_DOCKING");
  { JSValue v = js.string("STATUS_DOCKING"); OO_CHECK(OOEntityStatusFromJSValue(js.context, v) == STATUS_DOCKING); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromEntityStatus(js.context, STATUS_LAUNCHING)) == "STATUS_LAUNCHING");
  { JSValue v = js.string("STATUS_LAUNCHING"); OO_CHECK(OOEntityStatusFromJSValue(js.context, v) == STATUS_LAUNCHING); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromEntityStatus(js.context, STATUS_WITCHSPACE_COUNTDOWN)) == "STATUS_WITCHSPACE_COUNTDOWN");
  { JSValue v = js.string("STATUS_WITCHSPACE_COUNTDOWN"); OO_CHECK(OOEntityStatusFromJSValue(js.context, v) == STATUS_WITCHSPACE_COUNTDOWN); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromEntityStatus(js.context, STATUS_ENTERING_WITCHSPACE)) == "STATUS_ENTERING_WITCHSPACE");
  { JSValue v = js.string("STATUS_ENTERING_WITCHSPACE"); OO_CHECK(OOEntityStatusFromJSValue(js.context, v) == STATUS_ENTERING_WITCHSPACE); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromEntityStatus(js.context, STATUS_EXITING_WITCHSPACE)) == "STATUS_EXITING_WITCHSPACE");
  { JSValue v = js.string("STATUS_EXITING_WITCHSPACE"); OO_CHECK(OOEntityStatusFromJSValue(js.context, v) == STATUS_EXITING_WITCHSPACE); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromEntityStatus(js.context, STATUS_ESCAPE_SEQUENCE)) == "STATUS_ESCAPE_SEQUENCE");
  { JSValue v = js.string("STATUS_ESCAPE_SEQUENCE"); OO_CHECK(OOEntityStatusFromJSValue(js.context, v) == STATUS_ESCAPE_SEQUENCE); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromEntityStatus(js.context, STATUS_IN_HOLD)) == "STATUS_IN_HOLD");
  { JSValue v = js.string("STATUS_IN_HOLD"); OO_CHECK(OOEntityStatusFromJSValue(js.context, v) == STATUS_IN_HOLD); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromEntityStatus(js.context, STATUS_BEING_SCOOPED)) == "STATUS_BEING_SCOOPED");
  { JSValue v = js.string("STATUS_BEING_SCOOPED"); OO_CHECK(OOEntityStatusFromJSValue(js.context, v) == STATUS_BEING_SCOOPED); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromEntityStatus(js.context, STATUS_HANDLING_ERROR)) == "STATUS_HANDLING_ERROR");
  { JSValue v = js.string("STATUS_HANDLING_ERROR"); OO_CHECK(OOEntityStatusFromJSValue(js.context, v) == STATUS_HANDLING_ERROR); JS_FreeValue(js.context, v); }
  { JSValue v = js.string("NOT_A_NAME"); OO_CHECK(OOEntityStatusFromJSValue(js.context, v) == (OOEntityStatus)(STATUS_INACTIVE)); JS_FreeValue(js.context, v); }  // the fallback
  OO_CHECK(OOEntityStatusFromJSValue(js.context, JS_NewInt32(js.context, 1)) == (OOEntityStatus)(STATUS_INACTIVE));  // not a string
}

OO_TEST(jsScanClass) {
  JSStrings& js = Strings();
  OO_CHECK(js.text(OOJSValueFromScanClass(js.context, CLASS_NOT_SET)) == "CLASS_NOT_SET");
  { JSValue v = js.string("CLASS_NOT_SET"); OO_CHECK(OOScanClassFromJSValue(js.context, v) == CLASS_NOT_SET); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromScanClass(js.context, CLASS_NO_DRAW)) == "CLASS_NO_DRAW");
  { JSValue v = js.string("CLASS_NO_DRAW"); OO_CHECK(OOScanClassFromJSValue(js.context, v) == CLASS_NO_DRAW); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromScanClass(js.context, CLASS_NEUTRAL)) == "CLASS_NEUTRAL");
  { JSValue v = js.string("CLASS_NEUTRAL"); OO_CHECK(OOScanClassFromJSValue(js.context, v) == CLASS_NEUTRAL); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromScanClass(js.context, CLASS_STATION)) == "CLASS_STATION");
  { JSValue v = js.string("CLASS_STATION"); OO_CHECK(OOScanClassFromJSValue(js.context, v) == CLASS_STATION); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromScanClass(js.context, CLASS_TARGET)) == "CLASS_TARGET");
  { JSValue v = js.string("CLASS_TARGET"); OO_CHECK(OOScanClassFromJSValue(js.context, v) == CLASS_TARGET); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromScanClass(js.context, CLASS_CARGO)) == "CLASS_CARGO");
  { JSValue v = js.string("CLASS_CARGO"); OO_CHECK(OOScanClassFromJSValue(js.context, v) == CLASS_CARGO); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromScanClass(js.context, CLASS_MISSILE)) == "CLASS_MISSILE");
  { JSValue v = js.string("CLASS_MISSILE"); OO_CHECK(OOScanClassFromJSValue(js.context, v) == CLASS_MISSILE); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromScanClass(js.context, CLASS_ROCK)) == "CLASS_ROCK");
  { JSValue v = js.string("CLASS_ROCK"); OO_CHECK(OOScanClassFromJSValue(js.context, v) == CLASS_ROCK); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromScanClass(js.context, CLASS_MINE)) == "CLASS_MINE");
  { JSValue v = js.string("CLASS_MINE"); OO_CHECK(OOScanClassFromJSValue(js.context, v) == CLASS_MINE); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromScanClass(js.context, CLASS_THARGOID)) == "CLASS_THARGOID");
  { JSValue v = js.string("CLASS_THARGOID"); OO_CHECK(OOScanClassFromJSValue(js.context, v) == CLASS_THARGOID); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromScanClass(js.context, CLASS_BUOY)) == "CLASS_BUOY");
  { JSValue v = js.string("CLASS_BUOY"); OO_CHECK(OOScanClassFromJSValue(js.context, v) == CLASS_BUOY); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromScanClass(js.context, CLASS_VISUAL_EFFECT)) == "CLASS_VISUAL_EFFECT");
  { JSValue v = js.string("CLASS_VISUAL_EFFECT"); OO_CHECK(OOScanClassFromJSValue(js.context, v) == CLASS_VISUAL_EFFECT); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromScanClass(js.context, CLASS_WORMHOLE)) == "CLASS_WORMHOLE");
  { JSValue v = js.string("CLASS_WORMHOLE"); OO_CHECK(OOScanClassFromJSValue(js.context, v) == CLASS_WORMHOLE); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromScanClass(js.context, CLASS_PLAYER)) == "CLASS_PLAYER");
  { JSValue v = js.string("CLASS_PLAYER"); OO_CHECK(OOScanClassFromJSValue(js.context, v) == CLASS_PLAYER); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromScanClass(js.context, CLASS_POLICE)) == "CLASS_POLICE");
  { JSValue v = js.string("CLASS_POLICE"); OO_CHECK(OOScanClassFromJSValue(js.context, v) == CLASS_POLICE); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromScanClass(js.context, CLASS_MILITARY)) == "CLASS_MILITARY");
  { JSValue v = js.string("CLASS_MILITARY"); OO_CHECK(OOScanClassFromJSValue(js.context, v) == CLASS_MILITARY); JS_FreeValue(js.context, v); }
  { JSValue v = js.string("NOT_A_NAME"); OO_CHECK(OOScanClassFromJSValue(js.context, v) == (OOScanClass)(CLASS_NOT_SET)); JS_FreeValue(js.context, v); }  // the fallback
  OO_CHECK(OOScanClassFromJSValue(js.context, JS_NewInt32(js.context, 1)) == (OOScanClass)(CLASS_NOT_SET));  // not a string
}

OO_TEST(jsCompassMode) {
  JSStrings& js = Strings();
  OO_CHECK(js.text(OOJSValueFromCompassMode(js.context, COMPASS_MODE_INACTIVE)) == "COMPASS_MODE_INACTIVE");
  { JSValue v = js.string("COMPASS_MODE_INACTIVE"); OO_CHECK(OOCompassModeFromJSValue(js.context, v) == COMPASS_MODE_INACTIVE); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromCompassMode(js.context, COMPASS_MODE_BASIC)) == "COMPASS_MODE_BASIC");
  { JSValue v = js.string("COMPASS_MODE_BASIC"); OO_CHECK(OOCompassModeFromJSValue(js.context, v) == COMPASS_MODE_BASIC); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromCompassMode(js.context, COMPASS_MODE_PLANET)) == "COMPASS_MODE_PLANET");
  { JSValue v = js.string("COMPASS_MODE_PLANET"); OO_CHECK(OOCompassModeFromJSValue(js.context, v) == COMPASS_MODE_PLANET); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromCompassMode(js.context, COMPASS_MODE_STATION)) == "COMPASS_MODE_STATION");
  { JSValue v = js.string("COMPASS_MODE_STATION"); OO_CHECK(OOCompassModeFromJSValue(js.context, v) == COMPASS_MODE_STATION); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromCompassMode(js.context, COMPASS_MODE_SUN)) == "COMPASS_MODE_SUN");
  { JSValue v = js.string("COMPASS_MODE_SUN"); OO_CHECK(OOCompassModeFromJSValue(js.context, v) == COMPASS_MODE_SUN); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromCompassMode(js.context, COMPASS_MODE_TARGET)) == "COMPASS_MODE_TARGET");
  { JSValue v = js.string("COMPASS_MODE_TARGET"); OO_CHECK(OOCompassModeFromJSValue(js.context, v) == COMPASS_MODE_TARGET); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromCompassMode(js.context, COMPASS_MODE_BEACONS)) == "COMPASS_MODE_BEACONS");
  { JSValue v = js.string("COMPASS_MODE_BEACONS"); OO_CHECK(OOCompassModeFromJSValue(js.context, v) == COMPASS_MODE_BEACONS); JS_FreeValue(js.context, v); }
  { JSValue v = js.string("NOT_A_NAME"); OO_CHECK(OOCompassModeFromJSValue(js.context, v) == (OOCompassMode)(COMPASS_MODE_BASIC)); JS_FreeValue(js.context, v); }  // the fallback
  OO_CHECK(OOCompassModeFromJSValue(js.context, JS_NewInt32(js.context, 1)) == (OOCompassMode)(COMPASS_MODE_BASIC));  // not a string
}

OO_TEST(jsGUIScreenID) {
  JSStrings& js = Strings();
  OO_CHECK(js.text(OOJSValueFromGUIScreenID(js.context, GUI_SCREEN_MAIN)) == "GUI_SCREEN_MAIN");
  { JSValue v = js.string("GUI_SCREEN_MAIN"); OO_CHECK(OOGUIScreenIDFromJSValue(js.context, v) == GUI_SCREEN_MAIN); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromGUIScreenID(js.context, GUI_SCREEN_INTRO1)) == "GUI_SCREEN_INTRO1");
  { JSValue v = js.string("GUI_SCREEN_INTRO1"); OO_CHECK(OOGUIScreenIDFromJSValue(js.context, v) == GUI_SCREEN_INTRO1); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromGUIScreenID(js.context, GUI_SCREEN_SHIPLIBRARY)) == "GUI_SCREEN_SHIPLIBRARY");
  { JSValue v = js.string("GUI_SCREEN_SHIPLIBRARY"); OO_CHECK(OOGUIScreenIDFromJSValue(js.context, v) == GUI_SCREEN_SHIPLIBRARY); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromGUIScreenID(js.context, GUI_SCREEN_KEYBOARD)) == "GUI_SCREEN_KEYBOARD");
  { JSValue v = js.string("GUI_SCREEN_KEYBOARD"); OO_CHECK(OOGUIScreenIDFromJSValue(js.context, v) == GUI_SCREEN_KEYBOARD); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromGUIScreenID(js.context, GUI_SCREEN_NEWGAME)) == "GUI_SCREEN_NEWGAME");
  { JSValue v = js.string("GUI_SCREEN_NEWGAME"); OO_CHECK(OOGUIScreenIDFromJSValue(js.context, v) == GUI_SCREEN_NEWGAME); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromGUIScreenID(js.context, GUI_SCREEN_OXZMANAGER)) == "GUI_SCREEN_OXZMANAGER");
  { JSValue v = js.string("GUI_SCREEN_OXZMANAGER"); OO_CHECK(OOGUIScreenIDFromJSValue(js.context, v) == GUI_SCREEN_OXZMANAGER); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromGUIScreenID(js.context, GUI_SCREEN_STATUS)) == "GUI_SCREEN_STATUS");
  { JSValue v = js.string("GUI_SCREEN_STATUS"); OO_CHECK(OOGUIScreenIDFromJSValue(js.context, v) == GUI_SCREEN_STATUS); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromGUIScreenID(js.context, GUI_SCREEN_MANIFEST)) == "GUI_SCREEN_MANIFEST");
  { JSValue v = js.string("GUI_SCREEN_MANIFEST"); OO_CHECK(OOGUIScreenIDFromJSValue(js.context, v) == GUI_SCREEN_MANIFEST); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromGUIScreenID(js.context, GUI_SCREEN_EQUIP_SHIP)) == "GUI_SCREEN_EQUIP_SHIP");
  { JSValue v = js.string("GUI_SCREEN_EQUIP_SHIP"); OO_CHECK(OOGUIScreenIDFromJSValue(js.context, v) == GUI_SCREEN_EQUIP_SHIP); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromGUIScreenID(js.context, GUI_SCREEN_SHIPYARD)) == "GUI_SCREEN_SHIPYARD");
  { JSValue v = js.string("GUI_SCREEN_SHIPYARD"); OO_CHECK(OOGUIScreenIDFromJSValue(js.context, v) == GUI_SCREEN_SHIPYARD); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromGUIScreenID(js.context, GUI_SCREEN_LONG_RANGE_CHART)) == "GUI_SCREEN_LONG_RANGE_CHART");
  { JSValue v = js.string("GUI_SCREEN_LONG_RANGE_CHART"); OO_CHECK(OOGUIScreenIDFromJSValue(js.context, v) == GUI_SCREEN_LONG_RANGE_CHART); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromGUIScreenID(js.context, GUI_SCREEN_SHORT_RANGE_CHART)) == "GUI_SCREEN_SHORT_RANGE_CHART");
  { JSValue v = js.string("GUI_SCREEN_SHORT_RANGE_CHART"); OO_CHECK(OOGUIScreenIDFromJSValue(js.context, v) == GUI_SCREEN_SHORT_RANGE_CHART); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromGUIScreenID(js.context, GUI_SCREEN_SYSTEM_DATA)) == "GUI_SCREEN_SYSTEM_DATA");
  { JSValue v = js.string("GUI_SCREEN_SYSTEM_DATA"); OO_CHECK(OOGUIScreenIDFromJSValue(js.context, v) == GUI_SCREEN_SYSTEM_DATA); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromGUIScreenID(js.context, GUI_SCREEN_MARKET)) == "GUI_SCREEN_MARKET");
  { JSValue v = js.string("GUI_SCREEN_MARKET"); OO_CHECK(OOGUIScreenIDFromJSValue(js.context, v) == GUI_SCREEN_MARKET); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromGUIScreenID(js.context, GUI_SCREEN_MARKETINFO)) == "GUI_SCREEN_MARKETINFO");
  { JSValue v = js.string("GUI_SCREEN_MARKETINFO"); OO_CHECK(OOGUIScreenIDFromJSValue(js.context, v) == GUI_SCREEN_MARKETINFO); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromGUIScreenID(js.context, GUI_SCREEN_OPTIONS)) == "GUI_SCREEN_OPTIONS");
  { JSValue v = js.string("GUI_SCREEN_OPTIONS"); OO_CHECK(OOGUIScreenIDFromJSValue(js.context, v) == GUI_SCREEN_OPTIONS); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromGUIScreenID(js.context, GUI_SCREEN_GAMEOPTIONS)) == "GUI_SCREEN_GAMEOPTIONS");
  { JSValue v = js.string("GUI_SCREEN_GAMEOPTIONS"); OO_CHECK(OOGUIScreenIDFromJSValue(js.context, v) == GUI_SCREEN_GAMEOPTIONS); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromGUIScreenID(js.context, GUI_SCREEN_LOAD)) == "GUI_SCREEN_LOAD");
  { JSValue v = js.string("GUI_SCREEN_LOAD"); OO_CHECK(OOGUIScreenIDFromJSValue(js.context, v) == GUI_SCREEN_LOAD); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromGUIScreenID(js.context, GUI_SCREEN_SAVE)) == "GUI_SCREEN_SAVE");
  { JSValue v = js.string("GUI_SCREEN_SAVE"); OO_CHECK(OOGUIScreenIDFromJSValue(js.context, v) == GUI_SCREEN_SAVE); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromGUIScreenID(js.context, GUI_SCREEN_SAVE_OVERWRITE)) == "GUI_SCREEN_SAVE_OVERWRITE");
  { JSValue v = js.string("GUI_SCREEN_SAVE_OVERWRITE"); OO_CHECK(OOGUIScreenIDFromJSValue(js.context, v) == GUI_SCREEN_SAVE_OVERWRITE); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromGUIScreenID(js.context, GUI_SCREEN_STICKMAPPER)) == "GUI_SCREEN_STICKMAPPER");
  { JSValue v = js.string("GUI_SCREEN_STICKMAPPER"); OO_CHECK(OOGUIScreenIDFromJSValue(js.context, v) == GUI_SCREEN_STICKMAPPER); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromGUIScreenID(js.context, GUI_SCREEN_STICKPROFILE)) == "GUI_SCREEN_STICKPROFILE");
  { JSValue v = js.string("GUI_SCREEN_STICKPROFILE"); OO_CHECK(OOGUIScreenIDFromJSValue(js.context, v) == GUI_SCREEN_STICKPROFILE); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromGUIScreenID(js.context, GUI_SCREEN_MISSION)) == "GUI_SCREEN_MISSION");
  { JSValue v = js.string("GUI_SCREEN_MISSION"); OO_CHECK(OOGUIScreenIDFromJSValue(js.context, v) == GUI_SCREEN_MISSION); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromGUIScreenID(js.context, GUI_SCREEN_REPORT)) == "GUI_SCREEN_REPORT");
  { JSValue v = js.string("GUI_SCREEN_REPORT"); OO_CHECK(OOGUIScreenIDFromJSValue(js.context, v) == GUI_SCREEN_REPORT); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromGUIScreenID(js.context, GUI_SCREEN_INTERFACES)) == "GUI_SCREEN_INTERFACES");
  { JSValue v = js.string("GUI_SCREEN_INTERFACES"); OO_CHECK(OOGUIScreenIDFromJSValue(js.context, v) == GUI_SCREEN_INTERFACES); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromGUIScreenID(js.context, GUI_SCREEN_KEYBOARD_CONFIRMCLEAR)) == "GUI_SCREEN_KEYBOARD_CONFIRMCLEAR");
  { JSValue v = js.string("GUI_SCREEN_KEYBOARD_CONFIRMCLEAR"); OO_CHECK(OOGUIScreenIDFromJSValue(js.context, v) == GUI_SCREEN_KEYBOARD_CONFIRMCLEAR); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromGUIScreenID(js.context, GUI_SCREEN_KEYBOARD_CONFIG)) == "GUI_SCREEN_KEYBOARD_CONFIG");
  { JSValue v = js.string("GUI_SCREEN_KEYBOARD_CONFIG"); OO_CHECK(OOGUIScreenIDFromJSValue(js.context, v) == GUI_SCREEN_KEYBOARD_CONFIG); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromGUIScreenID(js.context, GUI_SCREEN_KEYBOARD_ENTRY)) == "GUI_SCREEN_KEYBOARD_ENTRY");
  { JSValue v = js.string("GUI_SCREEN_KEYBOARD_ENTRY"); OO_CHECK(OOGUIScreenIDFromJSValue(js.context, v) == GUI_SCREEN_KEYBOARD_ENTRY); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromGUIScreenID(js.context, GUI_SCREEN_KEYBOARD_LAYOUT)) == "GUI_SCREEN_KEYBOARD_LAYOUT");
  { JSValue v = js.string("GUI_SCREEN_KEYBOARD_LAYOUT"); OO_CHECK(OOGUIScreenIDFromJSValue(js.context, v) == GUI_SCREEN_KEYBOARD_LAYOUT); JS_FreeValue(js.context, v); }
  { JSValue v = js.string("NOT_A_NAME"); OO_CHECK(OOGUIScreenIDFromJSValue(js.context, v) == (OOGUIScreenID)(GUI_SCREEN_MAIN)); JS_FreeValue(js.context, v); }  // the fallback
  OO_CHECK(OOGUIScreenIDFromJSValue(js.context, JS_NewInt32(js.context, 1)) == (OOGUIScreenID)(GUI_SCREEN_MAIN));  // not a string
}

OO_TEST(jsGalacticHyperspaceBehaviour) {
  JSStrings& js = Strings();
  OO_CHECK(js.text(OOJSValueFromGalacticHyperspaceBehaviour(js.context, GALACTIC_HYPERSPACE_BEHAVIOUR_STANDARD)) == "BEHAVIOUR_STANDARD");
  { JSValue v = js.string("BEHAVIOUR_STANDARD"); OO_CHECK(OOGalacticHyperspaceBehaviourFromJSValue(js.context, v) == GALACTIC_HYPERSPACE_BEHAVIOUR_STANDARD); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromGalacticHyperspaceBehaviour(js.context, GALACTIC_HYPERSPACE_BEHAVIOUR_ALL_SYSTEMS_REACHABLE)) == "BEHAVIOUR_ALL_SYSTEMS_REACHABLE");
  { JSValue v = js.string("BEHAVIOUR_ALL_SYSTEMS_REACHABLE"); OO_CHECK(OOGalacticHyperspaceBehaviourFromJSValue(js.context, v) == GALACTIC_HYPERSPACE_BEHAVIOUR_ALL_SYSTEMS_REACHABLE); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromGalacticHyperspaceBehaviour(js.context, GALACTIC_HYPERSPACE_BEHAVIOUR_FIXED_COORDINATES)) == "BEHAVIOUR_FIXED_COORDINATES");
  { JSValue v = js.string("BEHAVIOUR_FIXED_COORDINATES"); OO_CHECK(OOGalacticHyperspaceBehaviourFromJSValue(js.context, v) == GALACTIC_HYPERSPACE_BEHAVIOUR_FIXED_COORDINATES); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromGalacticHyperspaceBehaviour(js.context, GALACTIC_HYPERSPACE_BEHAVIOUR_UNKNOWN)) == "BEHAVIOUR_UNKNOWN");
  { JSValue v = js.string("BEHAVIOUR_UNKNOWN"); OO_CHECK(OOGalacticHyperspaceBehaviourFromJSValue(js.context, v) == GALACTIC_HYPERSPACE_BEHAVIOUR_UNKNOWN); JS_FreeValue(js.context, v); }
  { JSValue v = js.string("NOT_A_NAME"); OO_CHECK(OOGalacticHyperspaceBehaviourFromJSValue(js.context, v) == (OOGalacticHyperspaceBehaviour)(GALACTIC_HYPERSPACE_BEHAVIOUR_UNKNOWN)); JS_FreeValue(js.context, v); }  // the fallback
  OO_CHECK(OOGalacticHyperspaceBehaviourFromJSValue(js.context, JS_NewInt32(js.context, 1)) == (OOGalacticHyperspaceBehaviour)(GALACTIC_HYPERSPACE_BEHAVIOUR_UNKNOWN));  // not a string
}

OO_TEST(jsViewID) {
  JSStrings& js = Strings();
  OO_CHECK(js.text(OOJSValueFromViewID(js.context, VIEW_FORWARD)) == "VIEW_FORWARD");
  { JSValue v = js.string("VIEW_FORWARD"); OO_CHECK(OOViewIDFromJSValue(js.context, v) == VIEW_FORWARD); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromViewID(js.context, VIEW_AFT)) == "VIEW_AFT");
  { JSValue v = js.string("VIEW_AFT"); OO_CHECK(OOViewIDFromJSValue(js.context, v) == VIEW_AFT); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromViewID(js.context, VIEW_PORT)) == "VIEW_PORT");
  { JSValue v = js.string("VIEW_PORT"); OO_CHECK(OOViewIDFromJSValue(js.context, v) == VIEW_PORT); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromViewID(js.context, VIEW_STARBOARD)) == "VIEW_STARBOARD");
  { JSValue v = js.string("VIEW_STARBOARD"); OO_CHECK(OOViewIDFromJSValue(js.context, v) == VIEW_STARBOARD); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromViewID(js.context, VIEW_CUSTOM)) == "VIEW_CUSTOM");
  { JSValue v = js.string("VIEW_CUSTOM"); OO_CHECK(OOViewIDFromJSValue(js.context, v) == VIEW_CUSTOM); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromViewID(js.context, VIEW_NONE)) == "VIEW_NONE");
  { JSValue v = js.string("VIEW_NONE"); OO_CHECK(OOViewIDFromJSValue(js.context, v) == VIEW_NONE); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromViewID(js.context, VIEW_GUI_DISPLAY)) == "VIEW_GUI_DISPLAY");
  { JSValue v = js.string("VIEW_GUI_DISPLAY"); OO_CHECK(OOViewIDFromJSValue(js.context, v) == VIEW_GUI_DISPLAY); JS_FreeValue(js.context, v); }
  OO_CHECK(js.text(OOJSValueFromViewID(js.context, VIEW_BREAK_PATTERN)) == "VIEW_BREAK_PATTERN");
  { JSValue v = js.string("VIEW_BREAK_PATTERN"); OO_CHECK(OOViewIDFromJSValue(js.context, v) == VIEW_BREAK_PATTERN); JS_FreeValue(js.context, v); }
  { JSValue v = js.string("NOT_A_NAME"); OO_CHECK(OOViewIDFromJSValue(js.context, v) == (OOViewID)(VIEW_NONE)); JS_FreeValue(js.context, v); }  // the fallback
  OO_CHECK(OOViewIDFromJSValue(js.context, JS_NewInt32(js.context, 1)) == (OOViewID)(VIEW_NONE));  // not a string
}

OO_TEST(jsShipDamageType) {
  JSStrings& js = Strings();
  OO_CHECK(js.text(OOJSValueFromShipDamageType(js.context, kOODamageTypeScrape)) == "scrape damage");
  OO_CHECK(js.text(OOJSValueFromShipDamageType(js.context, kOODamageTypeHeat)) == "heat damage");
  OO_CHECK(js.text(OOJSValueFromShipDamageType(js.context, kOODamageTypeEnergy)) == "energy damage");
  OO_CHECK(js.text(OOJSValueFromShipDamageType(js.context, kOODamageTypeCascadeWeapon)) == "cascade weapon");
  OO_CHECK(js.text(OOJSValueFromShipDamageType(js.context, kOODamageTypeHitAPlanet)) == "hit a planet");
  OO_CHECK(js.text(OOJSValueFromShipDamageType(js.context, kOODamageTypeHitASun)) == "hit a sun");
  OO_CHECK(js.text(OOJSValueFromShipDamageType(js.context, kOODamageTypeRemoved)) == "removed");
}

OO_TEST(jsLegalStatusReason) {
  JSStrings& js = Strings();
  OO_CHECK(js.text(OOJSValueFromLegalStatusReason(js.context, kOOLegalStatusReasonUnknown)) == "unknown");
  OO_CHECK(js.text(OOJSValueFromLegalStatusReason(js.context, kOOLegalStatusReasonSetup)) == "setup actions");
  OO_CHECK(js.text(OOJSValueFromLegalStatusReason(js.context, kOOLegalStatusReasonByScript)) == "scripted");
  OO_CHECK(js.text(OOJSValueFromLegalStatusReason(js.context, kOOLegalStatusReasonAttackedPolice)) == "attacked police");
  OO_CHECK(js.text(OOJSValueFromLegalStatusReason(js.context, kOOLegalStatusReasonAttackedMainStation)) == "attacked main station");
  OO_CHECK(js.text(OOJSValueFromLegalStatusReason(js.context, kOOLegalStatusReasonAttackedInnocent)) == "attacked innocent");
  OO_CHECK(js.text(OOJSValueFromLegalStatusReason(js.context, kOOLegalStatusReasonSeenByPolice)) == "seen by police");
  OO_CHECK(js.text(OOJSValueFromLegalStatusReason(js.context, kOOLegalStatusReasonDistressCall)) == "distress call");
  OO_CHECK(js.text(OOJSValueFromLegalStatusReason(js.context, kOOLegalStatusReasonIllegalExports)) == "illegal exports");
  OO_CHECK(js.text(OOJSValueFromLegalStatusReason(js.context, kOOLegalStatusReasonIllegalImports)) == "illegal imports");
  OO_CHECK(js.text(OOJSValueFromLegalStatusReason(js.context, kOOLegalStatusReasonAssistingOffender)) == "assisting offenders");
  OO_CHECK(js.text(OOJSValueFromLegalStatusReason(js.context, kOOLegalStatusReasonNewGalaxy)) == "new galaxy");
  OO_CHECK(js.text(OOJSValueFromLegalStatusReason(js.context, kOOLegalStatusReasonNewSystem)) == "new system");
  OO_CHECK(js.text(OOJSValueFromLegalStatusReason(js.context, kOOLegalStatusReasonPaidFine)) == "paid fine");
  OO_CHECK(js.text(OOJSValueFromLegalStatusReason(js.context, kOOLegalStatusReasonEscapePod)) == "escape pod");
  OO_CHECK(js.text(OOJSValueFromLegalStatusReason(js.context, kOOLegalStatusReasonAssistingPolice)) == "assisting police");
  OO_CHECK(js.text(OOJSValueFromLegalStatusReason(js.context, kOOLegalStatusReasonPoliceAreClean)) == "police are clean");
}

OO_TEST_MAIN()
