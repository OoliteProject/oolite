/*

PlayerEntity.m

Entity subclass nominally representing the player's ship, but also
implementing much of the interaction, menu system etc. Breaking it up into
ten or so different classes is a perennial to-do item.

Oolite
Copyright (C) 2004-2007 Giles C Williams and contributors

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

#import <Foundation/Foundation.h>
#import "ShipEntity.h"
#import "OOTypes.h"

@class GuiDisplayGen, OOTrumble, MyOpenGLView, HeadUpDisplay, ShipEntity;
@class OOSound, OOMusic, OOSoundSource, OOSoundReferencePoint;
@class JoystickHandler, OOTexture;

#define SCRIPT_TIMER_INTERVAL			10.0

enum
{
	GUI_ROW_OPTIONS_QUICKSAVE			= 6,
	GUI_ROW_OPTIONS_SAVE,
	GUI_ROW_OPTIONS_LOAD,
	GUI_ROW_OPTIONS_BEGIN_NEW,
	GUI_ROW_OPTIONS_OPTIONS,
	GUI_ROW_OPTIONS_DISPLAY,
	
#if OOLITE_MAC_OS_X
	GUI_ROW_OPTIONS_SPEECH,
	GUI_ROW_OPTIONS_VOLUME,
	GUI_ROW_OPTIONS_GROWL,
	GUI_ROW_OPTIONS_OOTUNES,
	GUI_ROW_OPTIONS_DETAIL,
	GUI_ROW_OPTIONS_STRICT,
#endif

#if OOLITE_SDL
	GUI_ROW_OPTIONS_DISPLAYSTYLE,
	GUI_ROW_OPTIONS_VOLUME,
	GUI_ROW_OPTIONS_DETAIL,
	GUI_ROW_OPTIONS_STRICT,
	GUI_ROW_OPTIONS_STICKMAPPER,
	GUI_ROW_OPTIONS_QUIT,
#endif
	
	GUI_ROW_OPTIONS_END_OF_LIST,
	
	GUI_ROW_EQUIPMENT_START				= 3,
	GUI_MAX_ROWS_EQUIPMENT				= 12,
	GUI_ROW_EQUIPMENT_DETAIL			= GUI_ROW_EQUIPMENT_START + GUI_MAX_ROWS_EQUIPMENT + 1,
	GUI_ROW_EQUIPMENT_CASH				= 1,
	GUI_ROW_MARKET_KEY					= 1,
	GUI_ROW_MARKET_START				= 2,
	GUI_ROW_MARKET_CASH					= 20
};

enum
{
	// Exposed to shaders.
	SCOOP_STATUS_NOT_INSTALLED			= 0,
	SCOOP_STATUS_FULL_HOLD,
	SCOOP_STATUS_OKAY,
	SCOOP_STATUS_ACTIVE
};


enum
{
	ALERT_FLAG_DOCKED				= 0x010,
	ALERT_FLAG_MASS_LOCK			= 0x020,
	ALERT_FLAG_YELLOW_LIMIT			= 0x03f,
	ALERT_FLAG_TEMP					= 0x040,
	ALERT_FLAG_ALT					= 0x080,
	ALERT_FLAG_ENERGY				= 0x100,
	ALERT_FLAG_HOSTILES				= 0x200
};
typedef uint16_t OOAlertFlags;


typedef enum
{
	// Exposed to shaders.
	MISSILE_STATUS_SAFE,
	MISSILE_STATUS_ARMED,
	MISSILE_STATUS_TARGET_LOCKED
} OOMissileStatus;

#define WEAPON_COOLING_FACTOR			6.0
#define ENERGY_RECHARGE_FACTOR			energy_recharge_rate
#define SHIELD_RECHARGE_FACTOR			(2.0 + shield_enhancer)
#define ECM_ENERGY_DRAIN_FACTOR			20.0
#define ECM_DURATION					2.5

#define ROLL_DAMPING_FACTOR				1.0
#define PITCH_DAMPING_FACTOR			1.0

#define PLAYER_MAX_FORWARD_SHIELD		(128.0 * (shield_booster + shield_enhancer))
#define PLAYER_MAX_AFT_SHIELD			(128.0 * (shield_booster + shield_enhancer))
#define PLAYER_MAX_WEAPON_TEMP			256.0
#define PLAYER_MAX_FUEL					70
#define PLAYER_MAX_MISSILES				4
#define PLAYER_STARTING_MISSILES		3
#define PLAYER_DIAL_MAX_ALTITUDE		40000.0
#define PLAYER_SUPER_ALTITUDE2			10000000000.0

#define PLAYER_MAX_TRUMBLES				24

#define	PLAYER_TARGET_MEMORY_SIZE		16

	//  ~~~~~~~~~~~~~~~~~~~~~~~~	= 40km

#define SHOT_RELOAD						0.25

#define HYPERSPEED_FACTOR				32.0

#define PLAYER_SHIP_DESC				@"cobra3-player"
#define PLAYER_MODEL					@"cobra3_redux.dat"

#define KEY_DOCKING_MUSIC				@"docking_music"

#define ESCAPE_SEQUENCE_TIME			10.0

#define MS_WITCHSPACE_SF				@"[witch-to-@-in-f-seconds]"
#define MS_GAL_WITCHSPACE_F				@"[witch-galactic-in-f-seconds]"


#define WEAPON_FACING_NONE				0
#define WEAPON_FACING_FORWARD			1
#define WEAPON_FACING_AFT				2
#define WEAPON_FACING_PORT				4
#define WEAPON_FACING_STARBOARD			8

#define WEAPON_OFFSET_DOWN				20

#define FORWARD_FACING_STRING			@"\tForward "
#define AFT_FACING_STRING				@"\tAft "
#define PORT_FACING_STRING				@"\tPort "
#define STARBOARD_FACING_STRING			@"\tStarboard "

#define KEY_REPEAT_INTERVAL				0.20

#define OOTUNES_ON						ootunes_on

#define PLAYER_SHIP_CLOCK_START			(2084004 * 86400.0)

#define CONTRACTS_GOOD_KEY				@"contracts_fulfilled"
#define CONTRACTS_BAD_KEY				@"contracts_expired"
#define CONTRACTS_UNKNOWN_KEY			@"contracts_unknown"
#define PASSAGE_GOOD_KEY				@"passage_fulfilled"
#define PASSAGE_BAD_KEY					@"passage_expired"
#define PASSAGE_UNKNOWN_KEY				@"passage_unknown"


typedef enum
{
	// Exposed to shaders.
	COMPASS_MODE_BASIC,
	COMPASS_MODE_PLANET,
	COMPASS_MODE_STATION,
	COMPASS_MODE_SUN,
	COMPASS_MODE_TARGET,
	COMPASS_MODE_BEACONS
} OOCompassMode;


#define SCANNER_ZOOM_RATE_UP			2.0
#define SCANNER_ZOOM_RATE_DOWN			-8.0

#define PLAYER_INTERNAL_DAMAGE_FACTOR	31

#define PLAYER_DOCKING_AI_NAME			@"dockingAI.plist"

@interface PlayerEntity: ShipEntity
{
@public
	
	Random_Seed				system_seed;
	Random_Seed				target_system_seed;
	
@protected
	
	NSString				*ship_desc;
	int						ship_trade_in_factor;
	
	NSDictionary			*script;
	NSMutableDictionary		*mission_variables;
	NSMutableDictionary		*local_variables;
	int						missionTextRow;
	ShipEntity				*script_target;
	NSString				*missionChoice;
	
	NSString				*specialCargo;
	
	NSMutableArray			*comm_log;

	NSMutableDictionary		*oxpKeys;
	
	OOTexture				*missionBackgroundTexture;
	
	NSMutableDictionary		*extra_equipment;	// TODO: this seems to be a dictionary whose values are all [NSNumber numberWithBool:YES]. Should be a set; remember to convert to dictionary for savinh.
	BOOL					found_equipment;
	
	NSMutableDictionary		*reputation;
	
	unsigned				max_passengers;
	NSMutableArray			*passengers;
	NSMutableDictionary		*passenger_record;
	
	NSMutableArray			*contracts;
	NSMutableDictionary		*contract_record;
	
	NSMutableDictionary		*shipyard_record;
	
	NSMutableArray			*missionDestinations;

	double					script_time;
	double					script_time_check;
	double					script_time_interval;
	NSString				*lastTextKey;
	
	double					ship_clock;
	double					ship_clock_adjust;
	
	double					fps_check_time;
	int						fps_counter;
	
	NSString				*planetSearchString;
	
	gl_matrix				playerRotMatrix;
	
	// For OO-GUI based save screen
	NSString				*commanderNameString;
	NSMutableArray			*cdrDetailArray;
	int						currentPage;
	BOOL					pollControls;
// ...end save screen   

	StationEntity			*docked_station;
	
	HeadUpDisplay			*hud;
	
	GLfloat					roll_delta, pitch_delta, yaw_delta;
	
	GLfloat					forward_shield, aft_shield;
	GLfloat					weapon_temp;
	GLfloat					forward_weapon_temp, aft_weapon_temp, port_weapon_temp, starboard_weapon_temp;
	GLfloat					weapon_energy_per_shot, weapon_heat_increment_per_shot, weapon_reload_time;
	
	int						chosen_weapon_facing;   // for purchasing weapons
	
	double					ecm_start_time;
	
	OOMusic					*themeMusic;
	OOMusic					*missionMusic;
	OOMusic					*dockingMusic;
	
	OOSound					*beepSound;
	OOSound					*boopSound;
	OOSound					*weaponSound;
	OOSound					*weaponHitSound;
	OOSound					*missileSound;
	OOSound					*damageSound;
	OOSound					*scrapeDamageSound;
	OOSound					*destructionSound;
	OOSound					*breakPatternSound;
	OOSound					*ecmSound;
	OOSound					*buySound;
	OOSound					*sellSound;
	OOSound					*warningSound;
	OOSound					*afterburner1Sound;
	OOSound					*afterburner2Sound;
	OOSound					*witchAbortSound;
	OOSound					*fuelScoopSound;
	
	OOSoundReferencePoint	*refPoint;
	OOSoundSource			*interfaceBeepSource;
	OOSoundSource			*ecmSource;
	OOSoundSource			*breakPatternSource;
	
	OOGUIScreenID			gui_screen;
	OOAlertFlags			alertFlags;
	OOAlertCondition		alertCondition;
	OOMissileStatus			missile_status;
	unsigned				activeMissile;
	
	OOCargoQuantity			current_cargo;
	
	NSPoint					cursor_coordinates;
	double					witchspaceCountdown;
	
	// player commander data
	NSString				*player_name;
	NSPoint					galaxy_coordinates;
	
	Random_Seed				galaxy_seed;
	
	OOCreditsQuantity		credits;	
	uint8_t					galaxy_number;
	OOWeaponType			forward_weapon;		// Is there a reason for having both this and forward_weapon_type? -- ahruman
	OOWeaponType			aft_weapon;			// ditto
	OOWeaponType			port_weapon;
	OOWeaponType			starboard_weapon;
	
	NSMutableArray			*shipCommodityData;
	
	OOEnergyUnitType		energy_unit;
	int						shield_booster, shield_enhancer;
	
	unsigned				max_missiles;		// no. of missile pylons
	ShipEntity				*missile_entity[SHIPENTITY_MAX_MISSILES];	// holds the actual missile entities or equivalents

	int						legalStatus;
	int						market_rnd;
	unsigned				ship_kills;
	
	OOCompassMode			compassMode;
	
	GLfloat					fuel_leak_rate;
        
	// keys!
	OOKeyCode				key_roll_left;
	OOKeyCode				key_roll_right;
	OOKeyCode				key_pitch_forward;
	OOKeyCode				key_pitch_back;
	OOKeyCode				key_yaw_left;
	OOKeyCode				key_yaw_right;
	
	OOKeyCode				key_increase_speed;
	OOKeyCode				key_decrease_speed;
	OOKeyCode				key_inject_fuel;
	
	OOKeyCode				key_fire_lasers;
	OOKeyCode				key_launch_missile;
	OOKeyCode				key_next_missile;
	OOKeyCode				key_ecm;
	
	OOKeyCode				key_target_missile;
	OOKeyCode				key_untarget_missile;
	OOKeyCode				key_ident_system;
	
	OOKeyCode				key_scanner_zoom;
	OOKeyCode				key_scanner_unzoom;
	
	OOKeyCode				key_launch_escapepod;
	OOKeyCode				key_energy_bomb;
	
	OOKeyCode				key_galactic_hyperspace;
	OOKeyCode				key_hyperspace;
	OOKeyCode				key_jumpdrive;
	
	OOKeyCode				key_dump_cargo;
	OOKeyCode				key_rotate_cargo;
	
	OOKeyCode				key_autopilot;
	OOKeyCode				key_autopilot_target;
	OOKeyCode				key_autodock;
	
	OOKeyCode				key_snapshot;
	OOKeyCode				key_docking_music;
	
	OOKeyCode				key_advanced_nav_array;
	OOKeyCode				key_map_home;
	OOKeyCode				key_map_info;
	
	OOKeyCode				key_pausebutton;
	OOKeyCode				key_show_fps;
	OOKeyCode				key_mouse_control;
	
	OOKeyCode				key_comms_log;
	OOKeyCode				key_next_compass_mode;
	
	OOKeyCode				key_cloaking_device;
	
	OOKeyCode				key_contract_info;
	
	OOKeyCode				key_next_target;
	OOKeyCode				key_previous_target;
	
	OOKeyCode				key_custom_view;
	
	OOKeyCode				key_dump_target_state;
        
        // save-file
	NSString				*save_path;
        
        // position of viewports
	Vector					forwardViewOffset, aftViewOffset, portViewOffset, starboardViewOffset;
        
        // DEBUG
	ParticleEntity			*drawDebugParticle;
	OOUniversalID			debugShipID;
        
        // trumbles
	int						trumbleCount;
	OOTrumble				*trumble[PLAYER_MAX_TRUMBLES];
        
        // smart zoom
	GLfloat					scanner_zoom_rate;
        
        // target memory
	int						target_memory[PLAYER_TARGET_MEMORY_SIZE];
	int						target_memory_index;
	
	// custom view points
	NSMutableArray			*custom_views;
	Quaternion				customViewQuaternion;
	GLfloat					customViewMatrix[16];
	Vector					customViewOffset, customViewForwardVector, customViewUpVector, customViewRightVector;
	NSString				*customViewDescription;
	
	OOViewID				currentWeaponFacing;	// decoupled from view direction
	
        // docking reports
	NSMutableString			*dockingReport;
	
	// Woo, flags.
	unsigned				has_energy_unit: 1,
							has_docking_computer: 1,
							has_galactic_hyperdrive: 1,
							saved: 1,
							suppressTargetLost: 1,		// smart target lst reports
							scoopsActive: 1,			// smart fuelscoops
	
							game_over: 1,
							docked: 1,
							finished: 1,
							bomb_detonated: 1,
							autopilot_engaged: 1,
	
							afterburner_engaged: 1,
							afterburnerSoundLooping: 1,
	
							hyperspeed_engaged: 1,
							travelling_at_hyperspeed: 1,
							hyperspeed_locked: 1,
	
							ident_engaged: 1,
	
							galactic_witchjump: 1,
	
							ecm_in_operation: 1,
	
							show_info_flag: 1,
	
							showDemoShips: 1,
	
							rolling, pitching, yawing: 1,
							using_mining_laser: 1,
	
							mouse_control_on: 1,
	
							speech_on: 1,
							ootunes_on: 1,
	
							docking_music_on: 1,
	
							keyboardRollPitchOverride: 1,
							waitingForStickCallback: 1;
	
	// Note: joystick stuff does nothing under OS X.
	// Keeping track of joysticks
	int						numSticks;
	JoystickHandler			*stickHandler;
  
	// For PlayerEntity (StickMapper)
	int						selFunctionIdx;
	NSArray					*stickFunctions; 
}

+ (id)sharedPlayer;

- (void) warnAboutHostiles;

- (void) unloadCargoPods;
- (void) loadCargoPods;

- (int) random_factor;
- (Random_Seed) galaxy_seed;
- (NSPoint) galaxy_coordinates;
- (NSPoint) cursor_coordinates;

- (Random_Seed) system_seed;
- (void) setSystem_seed:(Random_Seed) s_seed;
- (Random_Seed) target_system_seed;

- (NSDictionary *) commanderDataDictionary;
- (BOOL)setCommanderDataFromDictionary:(NSDictionary *) dict;

- (void) set_up;

- (void) doBookkeeping:(double) delta_t;

- (BOOL) massLocked;
- (BOOL) atHyperspeed;
- (Vector) velocityVector;

- (NSString *) ship_desc;

- (StationEntity *) docked_station;

- (HeadUpDisplay *) hud;

- (void) setShowDemoShips:(BOOL) value;
- (BOOL) showDemoShips;

- (GLfloat) dialRoll;
- (GLfloat) dialPitch;
- (GLfloat) dialSpeed;
- (GLfloat) dialHyperSpeed;

- (GLfloat) dialForwardShield;
- (GLfloat) dialAftShield;

- (GLfloat) dialEnergy;
- (GLfloat) dialMaxEnergy;

- (GLfloat) dialFuel;
- (GLfloat) dialHyperRange;

- (GLfloat) dialAltitude;

- (unsigned) countMissiles;
- (OOMissileStatus) dialMissileStatus;

- (int) dialFuelScoopStatus;

- (NSString *) dial_clock;
- (NSString *) dial_clock_adjusted;
- (NSString *) dial_fpsinfo;
- (NSString *) dial_objinfo;

- (NSMutableArray *) comm_log;

- (OOCompassMode) compassMode;
- (void) setCompassMode:(OOCompassMode)value;
- (void) setNextCompassMode;

- (unsigned) activeMissile;
- (void) setActiveMissile:(unsigned)value;
- (unsigned) dialMaxMissiles;
- (BOOL) dialIdentEngaged;
- (NSString *) dialTargetName;
- (ShipEntity *) missileForStation:(unsigned)value;
- (void) sortMissiles;
- (void) safeAllMissiles;
- (void) selectNextMissile;
- (void) tidyMissilePylons;

- (void) clearAlertFlags;
- (int) alertFlags;
- (void) setAlertFlag:(int)flag to:(BOOL)value;
- (OOAlertCondition) alertCondition;

- (BOOL) mountMissile:(ShipEntity *)missile;

- (BOOL) fireEnergyBomb;
- (BOOL) launchMine:(ShipEntity *)mine;

- (BOOL) fireMainWeapon;
- (OOWeaponType) weaponForView:(OOViewID)view;

- (void) rotateCargo;

- (void) enterGalacticWitchspace;

- (void) interpretAIMessage:(NSString *)ms;

- (void) takeInternalDamage;
- (NSDictionary *)damageInformation;

- (void) loseTargetStatus;

- (void) docked;

- (void) setGuiToStatusScreen;
- (NSArray *) equipmentList;
- (NSArray *) cargoList;
- (void) setGuiToSystemDataScreen;
- (NSArray *) markedDestinations;
- (void) setGuiToLongRangeChartScreen;
- (void) setGuiToShortRangeChartScreen;
- (void) setGuiToLoadSaveScreen;
- (void) setGuiToEquipShipScreen:(int) skip :(int) itemForSelectFacing;
- (void) showInformationForSelectedUpgrade;
- (void) calculateCurrentCargo;
- (void) setGuiToMarketScreen;

- (void) setGuiToIntro1Screen;
- (void) setGuiToIntro2Screen;

- (OOGUIScreenID) guiScreen;

- (void) buySelectedItem;
- (BOOL) tryBuyingItem:(int) index;
- (BOOL) marketFlooded:(int) index;
- (BOOL) tryBuyingCommodity:(int) index;
- (BOOL) trySellingCommodity:(int) index;

- (BOOL) speech_on;

- (BOOL) has_extra_equipment:(NSString *) eq_key;
- (void) add_extra_equipment:(NSString *) eq_key;
- (void) remove_extra_equipment:(NSString *) eq_key;
- (void) set_extra_equipment_from_flags;
- (void) set_flags_from_extra_equipment;

- (void) loopAfterburnerSound;
- (void) stopAfterburnerSound;

- (void) setScriptTarget:(ShipEntity *)ship;
- (ShipEntity*) script_target;
 
- (void) getFined;

- (void) setDefaultViewOffsets;
- (Vector) weaponViewOffset;

- (void) setUpTrumbles;
- (void) addTrumble:(OOTrumble*) papaTrumble;
- (void) removeTrumble:(OOTrumble*) deadTrumble;
- (OOTrumble**)trumbleArray;
- (int) trumbleCount;
// loading and saving trumbleCount
- (id)trumbleValue;
- (void) setTrumbleValueFrom:(NSObject*) trumbleValue;

- (void) mungChecksumWithNSString:(NSString *)str;

- (NSString *)screenModeStringForWidth:(unsigned)inWidth height:(unsigned)inHeight refreshRate:(float)inRate;

- (void) suppressTargetLost;

- (void) setScoopsActive;

- (void) clearTargetMemory;
- (BOOL) selectNextTargetFromMemory;
- (BOOL) selectPreviousTargetFromMemory;

- (void) applyYaw:(GLfloat) yaw;
- (void) setCredits: (int)newCredits;
- (void) setKills: (int)newKills;

/* GILES custom viewpoints */

// custom view points
- (Quaternion)customViewQuaternion;
- (GLfloat *)customViewMatrix;
- (Vector)customViewOffset;
- (Vector)customViewForwardVector;
- (Vector)customViewUpVector;
- (Vector)customViewRightVector;
- (NSString *)customViewDescription;
- (void)setCustomViewDataFromDictionary:(NSDictionary*) viewDict;

/* -- */

- (void) sendMessageToScripts:(NSString *)message;
- (void) sendMessageToScripts:(NSString *)message withString:(NSString *)argument;
- (void) sendMessageToScripts:(NSString *)message withArguments:(NSArray *)arguments;

- (BOOL)showInfoFlag;

@end
