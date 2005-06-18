/*
 *  PlayerEntity Additions.h
 *
 *  Oolite
 *
 *  Created by Giles Williams on Sat Apr 03 2004.
 *  Copyright (c) 2004 for aegidian.org. All rights reserved.
 *

Copyright (c) 2004, Giles C Williams
All rights reserved.

This work is licensed under the Creative Commons Attribution-NonCommercial-ShareAlike License.
To view a copy of this license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/
or send a letter to Creative Commons, 559 Nathan Abbott Way, Stanford, California 94305, USA.

You are free:

•	to copy, distribute, display, and perform the work
•	to make derivative works

Under the following conditions:

•	Attribution. You must give the original author credit.

•	Noncommercial. You may not use this work for commercial purposes.

•	Share Alike. If you alter, transform, or build upon this work,
you may distribute the resulting work only under a license identical to this one.

For any reuse or distribution, you must make clear to others the license terms of this work.

Any of these conditions can be waived if you get permission from the copyright holder.

Your fair use and other rights are in no way affected by the above.

*/

#import <Foundation/Foundation.h>

#define COMPARISON_NO			000
#define COMPARISON_EQUAL		001
#define COMPARISON_LESSTHAN		002
#define COMPARISON_GREATERTHAN  003
// +dajt: black ops
#define COMPARISON_ONEOF        004
// -dajt: black ops
#define COMPARISON_UNDEFINED	010

@interface PlayerEntity (Scripting)

- (void) checkScript;
- (void) checkCouplet:(NSDictionary *) couplet onEntity:(Entity *) entity;
- (void) scriptAction:(NSString *) scriptAction onEntity:(Entity *) entity;
- (BOOL) scriptTestCondition:(NSString *) scriptCondition;

/*-----------------------------------------------------*/

- (NSString *) mission_string;
- (NSString *) status_string;
- (NSString *) gui_screen_string;
- (NSNumber *) galaxy_number;
- (NSNumber *) planet_number;
- (NSNumber *) score_number;
- (NSNumber *) scriptTimer_number;
- (NSNumber *) shipsFound_number;

- (NSNumber *) legalStatus_number;
- (NSNumber *) d100_number;
- (NSNumber *) pseudoFixedD100_number;

- (NSNumber *) clock_number;			// returns the game time in seconds
- (NSNumber *) clock_mins_number;		// returns the game time in minutes
- (NSNumber *) clock_hours_number;		// returns the game time in hours
- (NSNumber *) clock_days_number;		// returns the game time in days

- (NSString *) dockedAtMainStation_bool;
- (NSString *) foundEquipment_bool;

- (NSString *) sunWillGoNova_bool;		// returns whether the sun is going to go nova

- (NSString *) missionChoice_string;	// returns nil or the key for the chosen option

/*-----------------------------------------------------*/

- (NSArray*) missionsList;

- (void) setMissionDescription:(NSString *)textKey;
- (void) clearMissionDescription;

- (void) commsMessage:(NSString *)valueString;

- (void) setLegalStatus:(NSString *)valueString;
- (void) awardCredits:(NSString *)valueString;
- (void) awardShipKills:(NSString *)valueString;
- (void) awardEquipment:(NSString *)equipString;  //eg. EQ_NAVAL_ENERGY_UNIT
- (void) removeEquipment:(NSString *)equipString;  //eg. EQ_NAVAL_ENERGY_UNIT

- (void) setPlanetinfo:(NSString *)key_valueString;	// uses key=value format

- (void) awardCargo:(NSString *)amount_typeString;
- (void) removeAllCargo;
- (void) useSpecialCargo:(NSString *)descriptionString;

- (void) testForEquipment:(NSString *)equipString;  //eg. EQ_NAVAL_ENERGY_UNIT

- (void) messageShipAIs:(NSString *)roles_message;
- (void) ejectItem:(NSString *)item_key;
- (void) addShips:(NSString *)roles_number;
- (void) addSystemShips:(NSString *)roles_number_position;
- (void) addShipsAt:(NSString *)roles_number_system_x_y_z;
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

- (void) setMissionChoices:(NSString *)choicesKey;	// choicesKey is a key for a dictionary of
													// choices/choice phrases in missiontext.plist and also..
- (void) resetMissionChoice;						// resets MissionChoice to nil

- (void) showShipModel: (NSString *)shipKey;
- (void) setMissionMusic: (NSString *)value;
- (void) setMissionImage: (NSString *)value;

- (void) setFuelLeak: (NSString *)value;
- (void) setSunNovaIn: (NSString *)time_value;
- (void) launchFromStation;
- (void) sendAllShipsAway;

- (void) debugOn;
- (void) debugOff;
- (void) debugMessage:(NSString *)args;

/*-----------------------------------------------------*/

- (void) setGuiToMissionScreen;

@end



