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


@class OOScript;


typedef enum
{
	COMPARISON_EQUAL,
	COMPARISON_NOTEQUAL,
	COMPARISON_LESSTHAN,
	COMPARISON_GREATERTHAN,
	COMPARISON_ONEOF,
	COMPARISON_UNDEFINED
} OOComparisonType;


typedef enum
{
	OP_STRING,
	OP_NUMBER,
	OP_BOOL,
	OP_MISSION_VAR,
	OP_LOCAL_VAR,
	OP_FALSE,
	
	OP_INVALID	// Must be last.
} OOOperationType;


@interface PlayerEntity (Scripting)

- (void) checkScript;

- (void) setScriptTarget:(ShipEntity *)ship;
- (ShipEntity*) scriptTarget;

- (void) runScriptActions:(NSArray *)sanitizedActions withContextName:(NSString *)contextName forTarget:(ShipEntity *)target;
- (void) runUnsanitizedScriptActions:(NSArray *)unsanitizedActions allowingAIMethods:(BOOL)allowAIMethods withContextName:(NSString *)contextName forTarget:(ShipEntity *)target;

// Test (sanitized) legacy script conditions array.
- (BOOL) scriptTestConditions:(NSArray *)array;

- (NSDictionary*) missionVariables;

- (NSString *)missionVariableForKey:(NSString *)key;
- (void)setMissionVariable:(NSString *)value forKey:(NSString *)key;

- (NSMutableDictionary *)localVariablesForMission:(NSString *)missionKey;
- (NSString *)localVariableForKey:(NSString *)variableName andMission:(NSString *)missionKey;
- (void)setLocalVariable:(NSString *)value forKey:(NSString *)variableName andMission:(NSString *)missionKey;

/*-----------------------------------------------------*/

- (NSString *) mission_string;
- (NSString *) status_string;
- (NSString *) gui_screen_string;
- (NSNumber *) galaxy_number;
- (NSNumber *) planet_number;
- (NSNumber *) score_number;
- (NSNumber *) credits_number;
- (NSNumber *) scriptTimer_number;
- (NSNumber *) shipsFound_number;

- (NSNumber *) d100_number;
- (NSNumber *) pseudoFixedD100_number;
- (NSNumber *) d256_number;
- (NSNumber *) pseudoFixedD256_number;

- (NSNumber *) clock_number;			// returns the game time in seconds
- (NSNumber *) clock_secs_number;		// returns the game time in seconds
- (NSNumber *) clock_mins_number;		// returns the game time in minutes
- (NSNumber *) clock_hours_number;		// returns the game time in hours
- (NSNumber *) clock_days_number;		// returns the game time in days

- (NSNumber *) fuelLevel_number;		// returns the fuel level in LY

- (NSString *) dockedAtMainStation_bool;
- (NSString *) foundEquipment_bool;

- (NSString *) sunWillGoNova_bool;		// returns whether the sun is going to go nova
- (NSString *) sunGoneNova_bool;		// returns whether the sun has gone nova

- (NSString *) missionChoice_string;	// returns nil or the key for the chosen option

- (NSNumber *) dockedTechLevel_number;
- (NSString *) dockedStationName_string;	// returns 'NONE' if the player isn't docked, [station name] if it is, 'UNKNOWN' otherwise

- (NSNumber *) systemGovernment_number;
- (NSString *) systemGovernment_string;
- (NSNumber *) systemEconomy_number;
- (NSString *) systemEconomy_string;
- (NSNumber *) systemTechLevel_number;
- (NSNumber *) systemPopulation_number;
- (NSNumber *) systemProductivity_number;

- (NSString *) commanderName_string;
- (NSString *) commanderRank_string;
- (NSString *) commanderShip_string;
- (NSString *) commanderShipDisplayName_string;
- (NSString *) commanderLegalStatus_string;
- (NSNumber *) commanderLegalStatus_number;

/*-----------------------------------------------------*/

- (NSArray *) missionsList;

- (void) setMissionDescription:(NSString *)textKey;
- (void) clearMissionDescription;
- (void) setMissionInstructions:(NSString *)text forMission:(NSString *)key;
- (void) setMissionDescription:(NSString *)textKey forMission:(NSString *)key;
- (void) clearMissionDescriptionForMission:(NSString *)key;

- (void) commsMessage:(NSString *)valueString;
- (void) commsMessageByUnpiloted:(NSString *)valueString;  // Enabled 02-May-2008 - Nikos. Same as commsMessage, but
							   // can be used by scripts to have unpiloted ships sending
							   // commsMessages, if we want to.

- (void) consoleMessage3s:(NSString *)valueString;
- (void) consoleMessage6s:(NSString *)valueString;

- (void) setLegalStatus:(NSString *)valueString;
- (void) awardCredits:(NSString *)valueString;
- (void) awardShipKills:(NSString *)valueString;
- (void) awardEquipment:(NSString *)equipString;  //eg. EQ_NAVAL_ENERGY_UNIT
- (void) removeEquipment:(NSString *)equipString;  //eg. EQ_NAVAL_ENERGY_UNIT

- (void) setPlanetinfo:(NSString *)key_valueString;	// uses key=value format
- (void) setSpecificPlanetInfo:(NSString *)key_valueString;	// uses galaxy#=planet#=key=value

- (void) awardCargo:(NSString *)amount_typeString;
- (void) removeAllCargo;
- (void) removeAllCargo:(BOOL)forceRemoval;

- (void) useSpecialCargo:(NSString *)descriptionString;

- (void) testForEquipment:(NSString *)equipString;  //eg. EQ_NAVAL_ENERGY_UNIT

- (void) awardFuel:(NSString *)valueString;	// add to fuel up to 7.0 LY

- (void) messageShipAIs:(NSString *)roles_message;
- (void) ejectItem:(NSString *)item_key;
- (void) addShips:(NSString *)roles_number;
- (void) addSystemShips:(NSString *)roles_number_position;
- (void) addShipsAt:(NSString *)roles_number_system_x_y_z;
- (void) addShipsAtPrecisely:(NSString *)roles_number_system_x_y_z;
- (void) addShipsWithinRadius:(NSString *)roles_number_system_x_y_z_r;
- (void) spawnShip:(NSString *)ship_key;
- (void) set:(NSString *)missionvariable_value;
- (void) reset:(NSString *)missionvariable;
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

- (void) increment:(NSString *)missionVariableString;
- (void) decrement:(NSString *)missionVariableString;

- (void) add:(NSString *)missionVariableString_value;
- (void) subtract:(NSString *)missionVariableString_value;

- (void) checkForShips: (NSString *)roleString;
- (void) resetScriptTimer;
- (void) addMissionText: (NSString *)textKey;
- (void) addLiteralMissionText: (NSString *)text;

- (void) setMissionChoiceByTextEntry:(BOOL)enable;
- (void) setMissionChoices:(NSString *)choicesKey;	// choicesKey is a key for a dictionary of
													// choices/choice phrases in missiontext.plist and also..
- (void) setMissionChoicesDictionary:(NSDictionary *)choicesDict;
- (void) resetMissionChoice;						// resets MissionChoice to nil

- (void) clearMissionScreen;

- (void) addMissionDestination:(NSString *)destinations;	// mark a system on the star charts
- (void) removeMissionDestination:(NSString *)destinations; // stop a system being marked on star charts

- (void) showShipModel:(NSString *)shipKey;
- (void) setMissionMusic:(NSString *)value;

- (NSString *)missionTitle;
- (void) setMissionTitle:(NSString *)value;

- (void) setFuelLeak: (NSString *)value;
- (NSNumber *)fuelLeakRate_number;
- (void) setSunNovaIn: (NSString *)time_value;
- (void) launchFromStation;
- (void) blowUpStation;
- (void) sendAllShipsAway;

- (OOPlanetEntity *) addPlanet: (NSString *)planetKey;
- (OOPlanetEntity *) addMoon: (NSString *)moonKey;

- (void) debugOn;
- (void) debugOff;
- (void) debugMessage:(NSString *)args;

- (NSString*) replaceVariablesInString:(NSString*) args;

- (void) playSound:(NSString *) soundName;

- (BOOL) addEqScriptForKey:(NSString *)eq_key;
- (void) removeEqScriptForKey:(NSString *)eq_key;
- (NSUInteger) eqScriptIndexForKey:(NSString *)eq_key;

- (void) targetNearestHostile;
- (void) targetNearestIncomingMissile;

- (void) setGalacticHyperspaceBehaviourTo:(NSString *) galacticHyperspaceBehaviourString;
- (void) setGalacticHyperspaceFixedCoordsTo:(NSString *) galacticHyperspaceFixedCoordsString;

/*-----------------------------------------------------*/

- (void) clearMissionScreenID;
- (void) setMissionScreenID:(NSString *)msid;
- (NSString *) missionScreenID;
- (void) setGuiToMissionScreen;
- (void) refreshMissionScreenTextEntry;
- (void) setGuiToMissionScreenWithCallback:(BOOL) callback;
- (void) doMissionCallback;
- (void) endMissionScreenAndNoteOpportunity;
- (void) setBackgroundFromDescriptionsKey:(NSString*) d_key;
- (void) addScene:(NSArray *) items atOffset:(Vector) off;
- (BOOL) processSceneDictionary:(NSDictionary *) couplet atOffset:(Vector) off;
- (BOOL) processSceneString:(NSString*) item atOffset:(Vector) off;

@end

NSString *OOComparisonTypeToString(OOComparisonType type) CONST_FUNC;
