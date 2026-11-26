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
        conditions are oo::PList trees, context names std::optional (nullopt was nil). The
        Foundation-typed forms moved to PlayerEntityLegacyScriptEngine+FoundationBridge.h
        (transitional), forwarding to these.
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

- (id)mission_string; // called by name (ADR-0043 item 21)
- (id)status_string; // called by name (ADR-0043 item 21)
- (id)gui_screen_string; // called by name (ADR-0043 item 21)
- (id)galaxy_number; // called by name (ADR-0043 item 21)
- (id)planet_number; // called by name (ADR-0043 item 21)
- (id)score_number; // called by name (ADR-0043 item 21)
- (id)credits_number; // called by name (ADR-0043 item 21)
- (id)scriptTimer_number; // called by name (ADR-0043 item 21)
- (id)shipsFound_number; // called by name (ADR-0043 item 21)

- (id)d100_number; // called by name (ADR-0043 item 21)
- (id)pseudoFixedD100_number; // called by name (ADR-0043 item 21)
- (id)d256_number; // called by name (ADR-0043 item 21)
- (id)pseudoFixedD256_number; // called by name (ADR-0043 item 21)

- (id)clock_number; // called by name (ADR-0043 item 21); returns the game time in seconds
- (id)clock_secs_number; // called by name (ADR-0043 item 21); returns the game time in seconds
- (id)clock_mins_number; // called by name (ADR-0043 item 21); returns the game time in minutes
- (id)clock_hours_number; // called by name (ADR-0043 item 21); returns the game time in hours
- (id)clock_days_number; // called by name (ADR-0043 item 21); returns the game time in days

- (id)fuelLevel_number; // called by name (ADR-0043 item 21); returns the fuel level in LY

- (id)dockedAtMainStation_bool; // called by name (ADR-0043 item 21)
- (id)foundEquipment_bool; // called by name (ADR-0043 item 21)

- (id)sunWillGoNova_bool; // called by name (ADR-0043 item 21); returns whether the sun is going to go nova
- (id)sunGoneNova_bool; // called by name (ADR-0043 item 21); returns whether the sun has gone nova

- (id)missionChoice_string; // called by name (ADR-0043 item 21); returns nil or the key for the chosen option
- (id)missionKeyPress_string; // called by name (ADR-0043 item 21)

- (id)dockedTechLevel_number; // called by name (ADR-0043 item 21)
- (id)dockedStationName_string; // called by name (ADR-0043 item 21); returns 'NONE' if the player isn't docked, [station name] if it is, 'UNKNOWN' otherwise

- (id)systemGovernment_number; // called by name (ADR-0043 item 21)
- (id)systemGovernment_string; // called by name (ADR-0043 item 21)
- (id)systemEconomy_number; // called by name (ADR-0043 item 21)
- (id)systemEconomy_string; // called by name (ADR-0043 item 21)
- (id)systemTechLevel_number; // called by name (ADR-0043 item 21)
- (id)systemPopulation_number; // called by name (ADR-0043 item 21)
- (id)systemProductivity_number; // called by name (ADR-0043 item 21)

- (id)commanderName_string; // called by name (ADR-0043 item 21)
- (id)commanderRank_string; // called by name (ADR-0043 item 21)
- (id)commanderShip_string; // called by name (ADR-0043 item 21)
- (id)commanderShipDisplayName_string; // called by name (ADR-0043 item 21)
- (id)commanderLegalStatus_string; // called by name (ADR-0043 item 21)
- (id)commanderLegalStatus_number; // called by name (ADR-0043 item 21)

/*-----------------------------------------------------*/

// The F5 manifest (bead oo-3rb.193): strings first, then arrays of a header and its entries.
- (oo::PList)cxx_missionsList;

- (void)setMissionDescription:(id)textKey; // called by name (ADR-0043 item 21)
- (void)clearMissionDescription;
- (void)cxx_setMissionInstructions:(const std::string&)text forMission:(const std::optional<std::string>&)key; // nullopt key: logged, ignored
- (void)cxx_setMissionInstructionsList:(const oo::PList&)list forMission:(const std::optional<std::string>&)key;
- (void)setMissionDescription:(const std::string&)textKey forMission:(const std::optional<std::string>&)key;
- (void)clearMissionDescriptionForMission:(id)key; // called by name (ADR-0043 item 21)

- (void)commsMessage:(id)valueString; // called by name (ADR-0043 item 21); shared selector (proposed ADR-0043)
- (void)commsMessageByUnpiloted:(id)valueString; // called by name (ADR-0043 item 21); shared selector (proposed ADR-0043)// Enabled 02-May-2008 - Nikos. Same as commsMessage, but
                                                 // can be used by scripts to have unpiloted ships sending
                                                 // commsMessages, if we want to.

- (void)consoleMessage3s:(id)valueString; // called by name (ADR-0043 item 21)
- (void)consoleMessage6s:(id)valueString; // called by name (ADR-0043 item 21)

- (void)setLegalStatus:(id)valueString; // called by name (ADR-0043 item 21); shared selector (proposed ADR-0043)
- (void)awardCredits:(id)valueString; // called by name (ADR-0043 item 21)
- (void)awardShipKills:(id)valueString; // called by name (ADR-0043 item 21)
- (void)awardEquipment:(id)equipString; // called by name (ADR-0043 item 21); eg. EQ_NAVAL_ENERGY_UNIT
- (void)removeEquipment:(id)equipString; // called by name (ADR-0043 item 21); eg. EQ_NAVAL_ENERGY_UNIT

- (void)setPlanetinfo:(id)key_valueString; // called by name (ADR-0043 item 21); uses key=value format
- (void)setSpecificPlanetInfo:(id)key_valueString; // called by name (ADR-0043 item 21); uses galaxy#=planet#=key=value

- (void)awardCargo:(id)amount_typeString; // called by name (ADR-0043 item 21)
- (void)removeAllCargo;
- (void)removeAllCargo:(BOOL)forceRemoval;

- (void)useSpecialCargo:(id)descriptionString; // called by name (ADR-0043 item 21)

- (void)testForEquipment:(id)equipString; // called by name (ADR-0043 item 21); eg. EQ_NAVAL_ENERGY_UNIT

- (void)awardFuel:(id)valueString; // called by name (ADR-0043 item 21); add to fuel up to 7.0 LY

- (void)messageShipAIs:(id)roles_message; // called by name (ADR-0043 item 21)
- (void)ejectItem:(id)item_key; // called by name (ADR-0043 item 21)
- (void)addShips:(id)roles_number; // called by name (ADR-0043 item 21)
- (void)addSystemShips:(id)roles_number_position; // called by name (ADR-0043 item 21)
- (void)addShipsAt:(id)roles_number_system_x_y_z; // called by name (ADR-0043 item 21)
- (void)addShipsAtPrecisely:(id)roles_number_system_x_y_z; // called by name (ADR-0043 item 21)
- (void)addShipsWithinRadius:(id)roles_number_system_x_y_z_r; // called by name (ADR-0043 item 21)
- (void)spawnShip:(id)ship_key; // called by name (ADR-0043 item 21); shared selector (proposed ADR-0043)
- (void)set:(id)missionvariable_value; // called by name (ADR-0043 item 21)
- (void)reset:(id)missionvariable; // called by name (ADR-0043 item 21)
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

- (void)increment:(id)missionVariableString; // called by name (ADR-0043 item 21)
- (void)decrement:(id)missionVariableString; // called by name (ADR-0043 item 21)

- (void)add:(id)missionVariableString_value; // called by name (ADR-0043 item 21)
- (void)subtract:(id)missionVariableString_value; // called by name (ADR-0043 item 21)

- (void)checkForShips:(id)roleString; // called by name (ADR-0043 item 21)
- (void)resetScriptTimer;
- (void)addMissionText:(id)textKey; // called by name (ADR-0043 item 21)
- (void)addLiteralMissionText:(id)text; // called by name (ADR-0043 item 21)

- (void)setMissionChoiceByTextEntry:(BOOL)enable;
- (void)setMissionChoices:(id)choicesKey; // called by name (ADR-0043 item 21); choicesKey is a key for a dictionary of
                                          // choices/choice phrases in missiontext.plist and also..
- (void)cxx_setMissionChoicesDictionary:(const oo::PList&)choicesDict; // keys are strings (bead oo-3rb.194)
- (void)resetMissionChoice; // resets MissionChoice to nil

- (void)clearMissionScreen;

- (void)addMissionDestination:(id)destinations; // called by name (ADR-0043 item 21); mark a system on the star charts
- (void)removeMissionDestination:(id)destinations; // called by name (ADR-0043 item 21); stop a system being marked on star charts

- (void)showShipModel:(id)shipKey; // called by name (ADR-0043 item 21)
- (void)setMissionMusic:(id)value; // called by name (ADR-0043 item 21); shared selector (proposed ADR-0043)

- (std::optional<std::string>)cxx_missionTitle;
- (void)cxx_setMissionTitle:(const std::optional<std::string>&)value;

- (void)setFuelLeak:(id)value; // called by name (ADR-0043 item 21)
- (id)fuelLeakRate_number; // called by name (ADR-0043 item 21)
- (void)setSunNovaIn:(id)time_value; // called by name (ADR-0043 item 21)
- (void)launchFromStation;
- (void)blowUpStation;
- (void)sendAllShipsAway;

- (OOPlanetEntity*)addPlanet:(id)planetKey; // called by name (ADR-0043 item 21)
- (OOPlanetEntity*)addMoon:(id)moonKey; // called by name (ADR-0043 item 21)

- (void)debugOn;
- (void)debugOff;
- (void)debugMessage:(id)args; // called by name (ADR-0043 item 21)

- (std::optional<std::string>)replaceVariablesInString:(const std::string&)args;

- (void)playSound:(id)soundName; // called by name (ADR-0043 item 21); shared selector (proposed ADR-0043)

// Equipment scripts (bead oo-3rb.195): no equipment has an empty key.
- (BOOL)cxx_addEqScriptForKey:(const std::string&)eq_key;
- (void)cxx_removeEqScriptForKey:(const std::string&)eq_key;
- (NSUInteger)cxx_eqScriptIndexForKey:(const std::string&)eq_key; // the count of scripts if none

- (void)targetNearestHostile;
- (void)targetNearestIncomingMissile;

- (void)setGalacticHyperspaceBehaviourTo:(id)galacticHyperspaceBehaviourString; // called by name (ADR-0043 item 21)
- (void)setGalacticHyperspaceFixedCoordsTo:(id)galacticHyperspaceFixedCoordsString; // called by name (ADR-0043 item 21)

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

/*	TRANSITIONAL (proposed ADR-0043, "Transitional bridges"): the Foundation-typed API this header
        declared before its sweep (beads oo-3rb.190 onwards, chunks of oo-j924), forwarding to the cxx_
        methods above, so unmigrated callers compile unchanged. Callers move to the cxx_ API in their
        own sweep beads; the bridge goes in its own bead.
*/
#import "PlayerEntityLegacyScriptEngine+FoundationBridge.h"
