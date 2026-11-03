/*

PlayerEntityLegacyScriptEngine.h

Various utility methods used for scripting.

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

#import "PlayerEntity.h"

#include "oofnd/PList.hpp"
#include "oofnd/StdLib.hpp"

@class OOScript;

typedef enum {
    COMPARISON_EQUAL,
    COMPARISON_NOTEQUAL,
    COMPARISON_LESSTHAN,
    COMPARISON_GREATERTHAN,
    COMPARISON_ONEOF,
    COMPARISON_UNDEFINED
} OOComparisonType;

typedef enum {
    OP_STRING,
    OP_NUMBER,
    OP_BOOL,
    OP_MISSION_VAR,
    OP_LOCAL_VAR,
    OP_FALSE,

    OP_INVALID // Must be last.
} OOOperationType;

@interface PlayerEntity (Scripting)

- (void)checkScript;

- (void)setScriptTarget:(ShipEntity*)ship;
- (ShipEntity*)scriptTarget;

/*	Foundation sweep (proposed ADR-0043, chunk 1 of oo-j924: bead oo-3rb.190): scripts and
        conditions are oo::PList trees, context names std::optional (nullopt was nil).
*/
- (void)cxx_runScriptActions:(const oo::PList&)sanitizedActions withContextName:(const std::optional<std::string>&)contextName forTarget:(ShipEntity*)target;
- (void)cxx_runUnsanitizedScriptActions:(const oo::PList&)unsanitizedActions allowingAIMethods:(BOOL)allowAIMethods withContextName:(const std::optional<std::string>&)contextName forTarget:(ShipEntity*)target;

// Test (sanitized) legacy script conditions array.
- (BOOL)cxx_scriptTestConditions:(const oo::PList&)array;

/*	The mission-variable store (bead oo-3rb.191): a variable is an oo::PList (null = unset; a
        string, an array from -setMissionInstructionsList:, or whatever JavaScript stored).
*/
- (oo::PList)cxx_missionVariables; // a snapshot
- (oo::PList)cxx_missionVariableForKey:(const std::string&)key;
- (void)cxx_setMissionVariable:(const oo::PList&)value forKey:(const std::string&)key; // null removes

// A mission's local variables (bead oo-3rb.192): a snapshot Dict, null for no mission.
- (oo::PList)localVariablesForMission:(const std::optional<std::string>&)missionKey;
- (std::optional<std::string>)localVariableForKey:(const std::string&)variableName andMission:(const std::optional<std::string>&)missionKey;
- (void)setLocalVariable:(const std::optional<std::string>&)value forKey:(const std::string&)variableName andMission:(const std::optional<std::string>&)missionKey; // nullopt removes

/*-----------------------------------------------------*/

- (oo::PList)mission_string; // called by name (ADR-0043 item 21)
- (oo::PList)status_string; // called by name (ADR-0043 item 21)
- (oo::PList)gui_screen_string; // called by name (ADR-0043 item 21)
- (oo::PList)galaxy_number; // called by name (ADR-0043 item 21)
- (oo::PList)planet_number; // called by name (ADR-0043 item 21)
- (oo::PList)score_number; // called by name (ADR-0043 item 21)
- (oo::PList)credits_number; // called by name (ADR-0043 item 21)
- (oo::PList)scriptTimer_number; // called by name (ADR-0043 item 21)
- (oo::PList)shipsFound_number; // called by name (ADR-0043 item 21)

- (oo::PList)d100_number; // called by name (ADR-0043 item 21)
- (oo::PList)pseudoFixedD100_number; // called by name (ADR-0043 item 21)
- (oo::PList)d256_number; // called by name (ADR-0043 item 21)
- (oo::PList)pseudoFixedD256_number; // called by name (ADR-0043 item 21)

- (oo::PList)clock_number; // called by name (ADR-0043 item 21); returns the game time in seconds
- (oo::PList)clock_secs_number; // called by name (ADR-0043 item 21); returns the game time in seconds
- (oo::PList)clock_mins_number; // called by name (ADR-0043 item 21); returns the game time in minutes
- (oo::PList)clock_hours_number; // called by name (ADR-0043 item 21); returns the game time in hours
- (oo::PList)clock_days_number; // called by name (ADR-0043 item 21); returns the game time in days

- (oo::PList)fuelLevel_number; // called by name (ADR-0043 item 21); returns the fuel level in LY

- (oo::PList)dockedAtMainStation_bool; // called by name (ADR-0043 item 21)
- (oo::PList)foundEquipment_bool; // called by name (ADR-0043 item 21)

- (oo::PList)sunWillGoNova_bool; // called by name (ADR-0043 item 21); returns whether the sun is going to go nova
- (oo::PList)sunGoneNova_bool; // called by name (ADR-0043 item 21); returns whether the sun has gone nova

- (oo::PList)missionChoice_string; // called by name (ADR-0043 item 21); returns nil or the key for the chosen option
- (oo::PList)missionKeyPress_string; // called by name (ADR-0043 item 21)

- (oo::PList)dockedTechLevel_number; // called by name (ADR-0043 item 21)
- (oo::PList)dockedStationName_string; // called by name (ADR-0043 item 21); returns 'NONE' if the player isn't docked, [station name] if it is, 'UNKNOWN' otherwise

- (oo::PList)systemGovernment_number; // called by name (ADR-0043 item 21)
- (oo::PList)systemGovernment_string; // called by name (ADR-0043 item 21)
- (oo::PList)systemEconomy_number; // called by name (ADR-0043 item 21)
- (oo::PList)systemEconomy_string; // called by name (ADR-0043 item 21)
- (oo::PList)systemTechLevel_number; // called by name (ADR-0043 item 21)
- (oo::PList)systemPopulation_number; // called by name (ADR-0043 item 21)
- (oo::PList)systemProductivity_number; // called by name (ADR-0043 item 21)

- (oo::PList)commanderName_string; // called by name (ADR-0043 item 21)
- (oo::PList)commanderRank_string; // called by name (ADR-0043 item 21)
- (oo::PList)commanderShip_string; // called by name (ADR-0043 item 21)
- (oo::PList)commanderShipDisplayName_string; // called by name (ADR-0043 item 21)
- (oo::PList)commanderLegalStatus_string; // called by name (ADR-0043 item 21)
- (oo::PList)commanderLegalStatus_number; // called by name (ADR-0043 item 21)

/*-----------------------------------------------------*/

// The F5 manifest (bead oo-3rb.193): strings first, then arrays of a header and its entries.
- (oo::PList)cxx_missionsList;

- (void)setMissionDescription:(const std::string&)textKey; // called by name (ADR-0043 item 21)
- (void)clearMissionDescription;
- (void)cxx_setMissionInstructions:(const std::string&)text forMission:(const std::optional<std::string>&)key; // nullopt key: logged, ignored
- (void)cxx_setMissionInstructionsList:(const oo::PList&)list forMission:(const std::optional<std::string>&)key;
- (void)setMissionDescription:(const std::string&)textKey forMission:(const std::optional<std::string>&)key;
- (void)clearMissionDescriptionForMission:(const std::string&)key; // called by name (ADR-0043 item 21)

- (void)commsMessage:(const std::string&)valueString; // called by name (ADR-0055 item 5); shared selector (proposed ADR-0043)
- (void)commsMessageByUnpiloted:(const std::string&)valueString; // called by name (ADR-0055 item 5); shared selector (proposed ADR-0043)// Enabled 02-May-2008 - Nikos. Same as commsMessage, but
                                                                 // can be used by scripts to have unpiloted ships sending
                                                                 // commsMessages, if we want to.

- (void)consoleMessage3s:(const std::string&)valueString; // called by name (ADR-0043 item 21)
- (void)consoleMessage6s:(const std::string&)valueString; // called by name (ADR-0043 item 21)

- (void)setLegalStatus:(const std::string&)valueString; // called by name (ADR-0043 item 21)
- (void)awardCredits:(const std::string&)valueString; // called by name (ADR-0043 item 21)
- (void)awardShipKills:(const std::string&)valueString; // called by name (ADR-0043 item 21)
- (void)awardEquipment:(const std::string&)equipString; // called by name (ADR-0043 item 21); eg. EQ_NAVAL_ENERGY_UNIT
- (void)removeEquipment:(const std::string&)equipString; // called by name (ADR-0043 item 21); eg. EQ_NAVAL_ENERGY_UNIT

- (void)setPlanetinfo:(const std::string&)key_valueString; // called by name (ADR-0043 item 21); uses key=value format
- (void)setSpecificPlanetInfo:(const std::string&)key_valueString; // called by name (ADR-0043 item 21); uses galaxy#=planet#=key=value

- (void)awardCargo:(const std::string&)amount_typeString; // called by name (ADR-0043 item 21)
- (void)removeAllCargo;
- (void)removeAllCargo:(BOOL)forceRemoval;

- (void)useSpecialCargo:(const std::string&)descriptionString; // called by name (ADR-0043 item 21)

- (void)testForEquipment:(const std::string&)equipString; // called by name (ADR-0043 item 21); eg. EQ_NAVAL_ENERGY_UNIT

- (void)awardFuel:(const std::string&)valueString; // called by name (ADR-0043 item 21); add to fuel up to 7.0 LY

- (void)messageShipAIs:(const std::string&)roles_message; // called by name (ADR-0043 item 21)
- (void)ejectItem:(const std::string&)item_key; // called by name (ADR-0043 item 21)
- (void)addShips:(const std::string&)roles_number; // called by name (ADR-0043 item 21)
- (void)addSystemShips:(const std::string&)roles_number_position; // called by name (ADR-0043 item 21)
- (void)addShipsAt:(const std::string&)roles_number_system_x_y_z; // called by name (ADR-0043 item 21)
- (void)addShipsAtPrecisely:(const std::string&)roles_number_system_x_y_z; // called by name (ADR-0043 item 21)
- (void)addShipsWithinRadius:(const std::string&)roles_number_system_x_y_z_r; // called by name (ADR-0043 item 21)
- (void)spawnShip:(const std::string&)ship_key; // called by name (ADR-0055 item 5)
- (void)set:(const std::string&)missionvariable_value; // called by name (ADR-0043 item 21)
- (void)reset:(const std::string&)missionvariable; // called by name (ADR-0043 item 21)
/*
        set:missionvariable_value
        add:missionvariable_value
        subtract:missionvariable_value

        the value may be a string constant or one of the above calls
        ending in _bool, _number, or _string

        egs.
                set: mission_my_mission_status MISSION_START
                set: mission_my_mission_value 12.345
                set: mission_my_mission_clock clock_number
                add: mission_my_mission_clock 86400
                subtract: mission_my_mission_clock d100_number
*/

- (void)increment:(const std::string&)missionVariableString; // called by name (ADR-0043 item 21)
- (void)decrement:(const std::string&)missionVariableString; // called by name (ADR-0043 item 21)

- (void)add:(const std::string&)missionVariableString_value; // called by name (ADR-0043 item 21)
- (void)subtract:(const std::string&)missionVariableString_value; // called by name (ADR-0043 item 21)

- (void)checkForShips:(const std::string&)roleString; // called by name (ADR-0043 item 21)
- (void)resetScriptTimer;
- (void)addMissionText:(const std::string&)textKey; // called by name (ADR-0043 item 21)
- (void)addLiteralMissionText:(const std::string&)text; // called by name (ADR-0043 item 21)

- (void)setMissionChoiceByTextEntry:(BOOL)enable;
- (void)setMissionChoices:(const std::string&)choicesKey; // called by name (ADR-0043 item 21); choicesKey is a key for a dictionary of
                                                          // choices/choice phrases in missiontext.plist and also..
- (void)cxx_setMissionChoicesDictionary:(const oo::PList&)choicesDict; // keys are strings (bead oo-3rb.194)
- (void)resetMissionChoice; // resets MissionChoice to nil

- (void)clearMissionScreen;

- (void)addMissionDestination:(const std::string&)destinations; // called by name (ADR-0043 item 21); mark a system on the star charts
- (void)removeMissionDestination:(const std::string&)destinations; // called by name (ADR-0043 item 21); stop a system being marked on star charts

- (void)showShipModel:(const std::string&)shipKey; // called by name (ADR-0043 item 21)
- (void)setMissionMusic:(const std::string&)value; // called by name (ADR-0043 item 21)

- (std::optional<std::string>)cxx_missionTitle;
- (void)cxx_setMissionTitle:(const std::optional<std::string>&)value;

- (void)setFuelLeak:(const std::string&)value; // called by name (ADR-0043 item 21)
- (oo::PList)fuelLeakRate_number; // called by name (ADR-0043 item 21)
- (void)setSunNovaIn:(const std::string&)time_value; // called by name (ADR-0043 item 21)
- (void)launchFromStation;
- (void)blowUpStation;
- (void)sendAllShipsAway;

- (void)addPlanet:(const std::string&)planetKey; // called by name (ADR-0043 item 21)
- (void)addMoon:(const std::string&)moonKey; // called by name (ADR-0043 item 21)
- (OOPlanetEntity*)cxx_addPlanet:(const std::string&)planetKey; // system.addPlanet(): the planet added, or nil
- (OOPlanetEntity*)cxx_addMoon:(const std::string&)moonKey; // system.addMoon(): the moon added, or nil

- (void)debugOn;
- (void)debugOff;
- (void)debugMessage:(const std::string&)args; // called by name (ADR-0043 item 21)

- (std::optional<std::string>)replaceVariablesInString:(const std::string&)args;

- (void)playSound:(const std::string&)soundName; // called by name (ADR-0043 item 21)

// Equipment scripts (bead oo-3rb.195): no equipment has an empty key.
- (BOOL)cxx_addEqScriptForKey:(const std::string&)eq_key;
- (void)cxx_removeEqScriptForKey:(const std::string&)eq_key;
- (NSUInteger)cxx_eqScriptIndexForKey:(const std::string&)eq_key; // the count of scripts if none

- (void)targetNearestHostile;
- (void)targetNearestIncomingMissile;

- (void)setGalacticHyperspaceBehaviourTo:(const std::string&)galacticHyperspaceBehaviourString; // called by name (ADR-0043 item 21)
- (void)setGalacticHyperspaceFixedCoordsTo:(const std::string&)galacticHyperspaceFixedCoordsString; // called by name (ADR-0043 item 21)

/*-----------------------------------------------------*/

- (void)clearMissionScreenID;
- (void)cxx_setMissionScreenID:(const std::optional<std::string>&)msid;
- (std::optional<std::string>)cxx_missionScreenID;
- (void)setGuiToMissionScreen;
- (void)refreshMissionScreenTextEntry;
- (void)setGuiToMissionScreenWithCallback:(BOOL)callback;
- (void)doMissionCallback;
- (void)endMissionScreenAndNoteOpportunity;
- (void)cxx_setBackgroundFromDescriptionsKey:(const std::string&)d_key;
// Scenes (bead oo-3rb.197): a scene is an array of strings, arrays and couplet dictionaries.
- (void)addScene:(const oo::PList&)items atOffset:(Vector)off;
- (BOOL)processSceneDictionary:(const oo::PList&)couplet atOffset:(Vector)off;
- (BOOL)processSceneString:(const std::string&)item atOffset:(Vector)off;

@end

std::string cxx_OOComparisonTypeToString(OOComparisonType type);
