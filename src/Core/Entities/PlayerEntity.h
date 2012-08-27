/*

PlayerEntity.h

Entity subclass nominally representing the player's ship, but also
implementing much of the interaction, menu system etc. Breaking it up into
ten or so different classes is a perennial to-do item.

Oolite
Copyright (C) 2004-2012 Giles C Williams and contributors

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
#import "WormholeEntity.h"
#import "ShipEntity.h"
#import "OOTypes.h"
#import "OOJSPropID.h"


@class GuiDisplayGen, OOTrumble, MyOpenGLView, HeadUpDisplay, ShipEntity;
@class OOSound, OOSoundSource, OOSoundReferencePoint;
@class OOJoystickManager, OOTexture;


#define SCRIPT_TIMER_INTERVAL			10.0

#define GUI_ROW_INIT(GUI) /*int n_rows = [(GUI) rows]*/
#define GUI_FIRST_ROW(GROUP) ((GUI_DEFAULT_ROWS - GUI_ROW_##GROUP##OPTIONS_END_OF_LIST) / 2)
// reposition menu
#define GUI_ROW(GROUP,ITEM) (GUI_FIRST_ROW(GROUP) - 5 + GUI_ROW_##GROUP##OPTIONS_##ITEM)


#define ENTRY(label, value) label,

typedef enum
{
	#include "OOGUIScreenID.tbl"
} OOGUIScreenID;

#define GALACTIC_HYPERSPACE_ENTRY(label, value) GALACTIC_HYPERSPACE_##label = value,

typedef enum
{
	#include "OOGalacticHyperspaceBehaviour.tbl"
	
	GALACTIC_HYPERSPACE_MAX					= GALACTIC_HYPERSPACE_BEHAVIOUR_FIXED_COORDINATES
} OOGalacticHyperspaceBehaviour;

#undef ENTRY
#undef GALACTIC_HYPERSPACE_ENTRY


enum
{
	// Values used for unknown strings.
	kOOGUIScreenIDDefault					= GUI_SCREEN_MAIN,
	kOOGalacticHyperspaceBehaviourDefault	= GALACTIC_HYPERSPACE_BEHAVIOUR_UNKNOWN
};


// OO_RESOLUTION_OPTION: true if full screen resolution can be changed.
#if OOLITE_MAC_OS_X && OOLITE_64_BIT
#define OO_RESOLUTION_OPTION		0
#else
#define OO_RESOLUTION_OPTION		1
#endif


enum
{
	GUI_ROW_OPTIONS_QUICKSAVE,
	GUI_ROW_OPTIONS_SAVE,
	GUI_ROW_OPTIONS_LOAD,
	GUI_ROW_OPTIONS_BEGIN_NEW,
	GUI_ROW_OPTIONS_SPACER1,
	GUI_ROW_OPTIONS_GAMEOPTIONS,
	GUI_ROW_OPTIONS_SPACER2,
	GUI_ROW_OPTIONS_STRICT,
#if OOLITE_SDL
	GUI_ROW_OPTIONS_SPACER3,
	GUI_ROW_OPTIONS_QUIT,
#endif
	GUI_ROW_OPTIONS_END_OF_LIST,
	
	STATUS_EQUIPMENT_FIRST_ROW 			= 10,
	STATUS_EQUIPMENT_MAX_ROWS 			= 8,

	GUI_ROW_EQUIPMENT_START				= 3,
	GUI_MAX_ROWS_EQUIPMENT				= 12,
	GUI_ROW_EQUIPMENT_DETAIL			= GUI_ROW_EQUIPMENT_START + GUI_MAX_ROWS_EQUIPMENT + 1,
	GUI_ROW_EQUIPMENT_CASH				= 1,
	GUI_ROW_MARKET_KEY					= 1,
	GUI_ROW_MARKET_START				= 2,
	GUI_ROW_MARKET_CASH					= 20
};
#if GUI_FIRST_ROW() < 0
# error Too many items in OPTIONS list!
#endif

enum
{
	GUI_ROW_GAMEOPTIONS_AUTOSAVE,
	GUI_ROW_GAMEOPTIONS_SPACER1,
	GUI_ROW_GAMEOPTIONS_VOLUME,
#if OOLITE_SPEECH_SYNTH
	GUI_ROW_GAMEOPTIONS_SPEECH,
#if !OOLITE_MAC_OS_X
	// FIXME: should have voice option for OS X
	GUI_ROW_GAMEOPTIONS_SPEECH_LANGUAGE,
	GUI_ROW_GAMEOPTIONS_SPEECH_GENDER,
#endif
#endif
	GUI_ROW_GAMEOPTIONS_MUSIC,
#if OO_RESOLUTION_OPTION
	GUI_ROW_GAMEOPTIONS_SPACER2,
	GUI_ROW_GAMEOPTIONS_DISPLAY,
#endif
	GUI_ROW_GAMEOPTIONS_DISPLAYSTYLE,
	GUI_ROW_GAMEOPTIONS_DETAIL,
	GUI_ROW_GAMEOPTIONS_WIREFRAMEGRAPHICS,
	GUI_ROW_GAMEOPTIONS_PROCEDURALLYTEXTUREDPLANETS,
	GUI_ROW_GAMEOPTIONS_SHADEREFFECTS,
#if OOLITE_SDL
	GUI_ROW_GAMEOPTIONS_GAMMA,
#endif
	GUI_ROW_GAMEOPTIONS_SPACER_STICKMAPPER,
	GUI_ROW_GAMEOPTIONS_STICKMAPPER,
	GUI_ROW_GAMEOPTIONS_SPACER3,
	GUI_ROW_GAMEOPTIONS_BACK,
	
	GUI_ROW_GAMEOPTIONS_END_OF_LIST
};
#if GUI_FIRST_ROW() < 0
# error Too many items in GAMEOPTIONS list!
#endif


typedef enum
{
	// Exposed to shaders.
	SCOOP_STATUS_NOT_INSTALLED			= 0,
	SCOOP_STATUS_FULL_HOLD,
	SCOOP_STATUS_OKAY,
	SCOOP_STATUS_ACTIVE
} OOFuelScoopStatus;


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


#define ENERGY_RECHARGE_FACTOR			energy_recharge_rate
#define ECM_ENERGY_DRAIN_FACTOR			20.0f
#define ECM_DURATION					2.5f

#define ROLL_DAMPING_FACTOR				1.0f
#define PITCH_DAMPING_FACTOR			1.0f
#define YAW_DAMPING_FACTOR				1.0f

#define PLAYER_MAX_WEAPON_TEMP			256.0f
#define PLAYER_MAX_FUEL					70
#define PLAYER_MAX_MISSILES				16
#define PLAYER_STARTING_MAX_MISSILES	4
#define PLAYER_STARTING_MISSILES		3
#define PLAYER_DIAL_MAX_ALTITUDE		40000.0
#define PLAYER_SUPER_ALTITUDE2			10000000000.0

#define PLAYER_MAX_TRUMBLES				24

#define	PLAYER_TARGET_MEMORY_SIZE		16

	//  ~~~~~~~~~~~~~~~~~~~~~~~~	= 40km

#define SHOT_RELOAD						0.25

#define HYPERSPEED_FACTOR				32.0

#define PLAYER_SHIP_DESC				@"cobra3-player"

#define ESCAPE_SEQUENCE_TIME			10.0

#define MS_WITCHSPACE_SF				@"[witch-to-@-in-f-seconds]"
#define MS_GAL_WITCHSPACE_F				@"[witch-galactic-in-f-seconds]"

#define WEAPON_OFFSET_DOWN				20

#define FORWARD_FACING_STRING			DESC(@"forward-facing-string")
#define AFT_FACING_STRING				DESC(@"aft-facing-string")
#define PORT_FACING_STRING				DESC(@"port-facing-string")
#define STARBOARD_FACING_STRING			DESC(@"starboard-facing-string")

#define KEY_REPEAT_INTERVAL				0.20

#define PLAYER_SHIP_CLOCK_START			(2084004 * 86400.0)
// adding or removing a player ship subentity increases or decreases the ship's trade-in factor respectively by this amount
#define PLAYER_SHIP_SUBENTITY_TRADE_IN_VALUE	3

#define CONTRACTS_GOOD_KEY				@"contracts_fulfilled"
#define CONTRACTS_BAD_KEY				@"contracts_expired"
#define CONTRACTS_UNKNOWN_KEY			@"contracts_unknown"
#define PASSAGE_GOOD_KEY				@"passage_fulfilled"
#define PASSAGE_BAD_KEY					@"passage_expired"
#define PASSAGE_UNKNOWN_KEY				@"passage_unknown"


#define SCANNER_ZOOM_RATE_UP			2.0
#define SCANNER_ZOOM_RATE_DOWN			-8.0

#define PLAYER_INTERNAL_DAMAGE_FACTOR	31

#define PLAYER_DOCKING_AI_NAME			@"oolite-player-AI.plist"

#define	MANIFEST_SCREEN_ROW_BACK 1
#define	MANIFEST_SCREEN_ROW_NEXT [[PLAYER hud] isHidden]?27:20

#define MISSION_DEST_LEGACY   @"__oolite_legacy_destinations"

@interface PlayerEntity: ShipEntity
{
@private
	Random_Seed				system_seed;
	Random_Seed				target_system_seed;
	float					occlusion_dial;
	
	Random_Seed				found_system_seed;
	int						ship_trade_in_factor;
	
	NSDictionary			*worldScripts;
	NSMutableDictionary		*mission_variables;
	NSMutableDictionary		*localVariables;
	OOInteger /*OOGUIRow*/	missionTextRow;
	NSString				*missionChoice;
	BOOL					_missionWithCallback;
	
	NSString				*specialCargo;
	
	NSMutableArray			*commLog;

	NSMutableArray			*eqScripts;
	
	NSDictionary			*_missionOverlayDescriptor;
	NSDictionary			*_missionBackgroundDescriptor;
	NSDictionary			*_equipScreenBackgroundDescriptor;
	
	BOOL					found_equipment;
	
	NSMutableDictionary		*reputation;
	
	unsigned				max_passengers;
	NSMutableArray			*passengers;
	NSMutableDictionary		*passenger_record;
	
	NSMutableArray			*contracts;
	NSMutableDictionary		*contract_record;
	
	NSMutableDictionary		*shipyard_record;
	
	NSMutableDictionary			*missionDestinations;

	double					script_time;
	double					script_time_check;
	double					script_time_interval;
	NSString				*lastTextKey;
	
	double					ship_clock;
	double					ship_clock_adjust;
	
	double					fps_check_time;
	int						fps_counter;
	double					last_fps_check_time;
	
	NSString				*planetSearchString;
	
	OOMatrix				playerRotMatrix;
	
	BOOL					showingLongRangeChart;
	
	// For OO-GUI based save screen
	NSString				*commanderNameString;
	NSMutableArray			*cdrDetailArray;
	int						currentPage;
	BOOL					pollControls;
// ...end save screen   

	StationEntity			*dockedStation;
	
/* Used by the DOCKING_CLEARANCE code to implement docking at non-main
 * stations. Could possibly overload use of 'dockedStation' instead
 * but that needs futher investigation to ensure it doesn't break anything. */
	StationEntity			*targetDockStation; 
	
	HeadUpDisplay			*hud;
	
	GLfloat					roll_delta, pitch_delta, yaw_delta;
	GLfloat					launchRoll;
	
	GLfloat					forward_shield, aft_shield;
	OOTimeDelta				forward_shot_time, aft_shot_time, port_shot_time, starboard_shot_time;
	GLfloat					weapon_energy_use, weapon_reload_time;
	
	OOWeaponFacing			chosen_weapon_facing;   // for purchasing weapons
	
	double					ecm_start_time;
	
	OOGUIScreenID			gui_screen;
	OOAlertFlags			alertFlags;
	OOAlertCondition		alertCondition;
	OOAlertCondition		lastScriptAlertCondition;
	OOMissileStatus			missile_status;
	OOUInteger				activeMissile;
	OOUInteger				primedEquipment;
	
	OOCargoQuantity			current_cargo;
	
	NSPoint					cursor_coordinates;
	OOTimeDelta				witchspaceCountdown;
	
	// player commander data
	NSString				*_commanderName;
	NSPoint					galaxy_coordinates;
	
	Random_Seed				galaxy_seed;
	
	OOCreditsQuantity		credits;	
	OOGalaxyID				galaxy_number;
	
	NSMutableArray			*shipCommodityData;
	
	ShipEntity				*missile_entity[PLAYER_MAX_MISSILES];	// holds the actual missile entities or equivalents
	OOUniversalID			_dockTarget;	// used by the escape pod code
	
	int						legalStatus;	// legalStatus both is and isn't an OOCreditsQuantity, because of quantum.
	int						market_rnd;
	unsigned				ship_kills;
	
	OOCompassMode			compassMode;
	Entity 					*compassTarget;
	
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
	
	OOKeyCode				key_prime_equipment;
	OOKeyCode				key_activate_equipment;
#if FEATURE_REQUEST_5496
	OOKeyCode				key_mode_equipment;
#endif
	
	OOKeyCode				key_target_missile;
	OOKeyCode				key_untarget_missile;
	OOKeyCode				key_target_incoming_missile;
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
	OOKeyCode				key_autodock;
	
	OOKeyCode				key_snapshot;
	OOKeyCode				key_docking_music;
	
	OOKeyCode				key_advanced_nav_array;
	OOKeyCode				key_map_home;
	OOKeyCode				key_map_info;
	
	OOKeyCode				key_pausebutton;
	OOKeyCode				key_show_fps;
	OOKeyCode				key_mouse_control;
	OOKeyCode				key_hud_toggle;
	
	OOKeyCode				key_comms_log;
	OOKeyCode				key_prev_compass_mode;
	OOKeyCode				key_next_compass_mode;
	
	OOKeyCode				key_cloaking_device;
	
	OOKeyCode				key_contract_info;
	
	OOKeyCode				key_next_target;
	OOKeyCode				key_previous_target;
	
	OOKeyCode				key_custom_view;
	
	OOKeyCode				key_docking_clearance_request;
	
#ifndef NDEBUG
	OOKeyCode				key_dump_target_state;
#endif

	OOKeyCode				key_weapons_online_toggle;
	
	// save-file
	NSString				*save_path;
	
	// position of viewports
	Vector					forwardViewOffset, aftViewOffset, portViewOffset, starboardViewOffset;
	Vector					_sysInfoLight;
	
	// trumbles
	OOUInteger				trumbleCount;
	OOTrumble				*trumble[PLAYER_MAX_TRUMBLES];
	
	// smart zoom
	GLfloat					scanner_zoom_rate;
	
	// target memory
	int						target_memory[PLAYER_TARGET_MEMORY_SIZE];
	int						target_memory_index;
	
	// custom view points
	Quaternion				customViewQuaternion;
	OOMatrix				customViewMatrix;
	Vector					customViewOffset, customViewForwardVector, customViewUpVector, customViewRightVector;
	NSString				*customViewDescription;
	
	
	// docking reports
	NSMutableString			*dockingReport;
	
	// Woo, flags.
	unsigned				suppressTargetLost: 1,		// smart target lst reports
							scoopsActive: 1,			// smart fuelscoops
	
							scoopOverride: 1,			//scripted to just be on, ignoring normal rules
							game_over: 1,
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
	
							isSpeechOn: 1,
	
							keyboardRollOverride: 1,   // Handle keyboard roll...
							keyboardPitchOverride: 1,  // ...and pitch override separately - (fix for BUG #17490)  
							keyboardYawOverride: 1,
							waitingForStickCallback: 1,
							
							weapons_online: 1,
							
							launchingMissile: 1,
							replacingMissile: 1;
#if OOLITE_ESPEAK
	unsigned int			voice_no;
	BOOL					voice_gender_m;
#endif
  
	// For PlayerEntity (StickMapper)
	int						selFunctionIdx;
	NSArray					*stickFunctions; 
	
	OOGalacticHyperspaceBehaviour galacticHyperspaceBehaviour;
	NSPoint					galacticHyperspaceFixedCoords;
	
	NSArray					*_customViews;
	OOUInteger				_customViewIndex;
	
	OODockingClearanceStatus dockingClearanceStatus;
	
	NSMutableArray			*scannedWormholes;
	WormholeEntity			*wormhole;

	ShipEntity				*demoShip; // Used while docked to maintain demo ship rotation.
}

+ (PlayerEntity *) sharedPlayer;
- (void) deferredInit;

- (BOOL) setUpAndConfirmOK:(BOOL)stopOnError;
- (BOOL) setUpAndConfirmOK:(BOOL)stopOnError saveGame:(BOOL)loadingGame;
- (void) completeSetUp;
- (void) completeSetUpAndSetTarget:(BOOL)setTarget;

- (NSString *) commanderName;
- (void) setCommanderName:(NSString *)value;

- (BOOL) isDocked;

- (void) warnAboutHostiles;

- (void) unloadCargoPods;
- (void) loadCargoPods;
- (void) unloadAllCargoPodsForType:(OOCommodityType)type fromArray:(NSMutableArray *) manifest;
- (void) unloadCargoPodsForType:(OOCommodityType)type amount:(OOCargoQuantity) quantity;
- (void) loadCargoPodsForType:(OOCommodityType)type fromArray:(NSMutableArray *) manifest;
- (void) loadCargoPodsForType:(OOCommodityType)type amount:(OOCargoQuantity) quantity;
- (NSMutableArray *) shipCommodityData;

- (OOCreditsQuantity) deciCredits;

- (int) random_factor;
- (void) setRandom_factor:(int)rf;
- (Random_Seed) galaxy_seed;
- (NSPoint) galaxy_coordinates;
- (void) setGalaxyCoordinates:(NSPoint)newPosition;
- (NSPoint) cursor_coordinates;

- (Random_Seed) system_seed;
- (void) setSystem_seed:(Random_Seed) s_seed;
- (Random_Seed) target_system_seed;
- (void) setTargetSystemSeed:(Random_Seed) s_seed;

- (NSDictionary *) commanderDataDictionary;
- (BOOL)setCommanderDataFromDictionary:(NSDictionary *) dict;

- (void) doBookkeeping:(double) delta_t;
- (BOOL) isValidTarget:(Entity*)target;

- (BOOL) massLocked;
- (BOOL) atHyperspeed;

- (float) occlusionLevel;
- (void) setOcclusionLevel:(float)level;

- (void) setDockedAtMainStation;
- (StationEntity *) dockedStation;

- (BOOL) engageAutopilotToStation:(StationEntity *)stationForDocking;
- (void) disengageAutopilot;

- (void) resetAutopilotAI;

- (void) setTargetDockStationTo:(StationEntity *) value;
- (StationEntity *) getTargetDockStation;

- (HeadUpDisplay *) hud;
- (BOOL) switchHudTo:(NSString *)hudFileName;
- (void) resetHud;

- (void) setShowDemoShips:(BOOL) value;
- (BOOL) showDemoShips;

- (GLfloat) forwardShieldLevel;
- (GLfloat) aftShieldLevel;
- (GLfloat) baseMass;

- (void) setForwardShieldLevel:(GLfloat)level;
- (void) setAftShieldLevel:(GLfloat)level;

- (BOOL) isMouseControlOn;

- (GLfloat) dialRoll;
- (GLfloat) dialPitch;
- (GLfloat) dialYaw;
- (GLfloat) dialSpeed;
- (GLfloat) dialHyperSpeed;

- (void) currentWeaponStats;

- (GLfloat) dialForwardShield;
- (GLfloat) dialAftShield;

- (GLfloat) dialEnergy;
- (GLfloat) dialMaxEnergy;

- (GLfloat) dialFuel;
- (GLfloat) dialHyperRange;

- (GLfloat) dialAltitude;

- (unsigned) countMissiles;
- (OOMissileStatus) dialMissileStatus;

- (OOFuelScoopStatus) dialFuelScoopStatus;

- (float) fuelLeakRate;
- (void) setFuelLeakRate:(float)value;

- (double) clockTime;			// Note that this is not an OOTimeAbsolute
- (double) clockTimeAdjusted;	// Note that this is not an OOTimeAbsolute
- (BOOL) clockAdjusting;
- (void) addToAdjustTime:(double) seconds ;

- (NSString *) dial_clock;
- (NSString *) dial_clock_adjusted;
- (NSString *) dial_fpsinfo;
- (NSString *) dial_objinfo;

- (NSMutableArray *) commLog;

- (Entity *) compassTarget;
- (void) setCompassTarget:(Entity *)value;

- (OOCompassMode) compassMode;
- (void) setCompassMode:(OOCompassMode)value;
- (void) setPrevCompassMode;
- (void) setNextCompassMode;

- (OOUInteger) activeMissile;
- (void) setActiveMissile:(OOUInteger)value;
- (OOUInteger) dialMaxMissiles;
- (BOOL) dialIdentEngaged;
- (void) setDialIdentEngaged:(BOOL)newValue;
- (NSString *) specialCargo;
- (NSString *) dialTargetName;
- (ShipEntity *) missileForPylon:(OOUInteger)value;
- (void) safeAllMissiles;
- (void) selectNextMissile;
- (void) tidyMissilePylons;
- (BOOL) removeFromPylon:(OOUInteger) pylon;
- (BOOL) assignToActivePylon:(NSString *)identifierKey;

- (void) clearAlertFlags;
- (int) alertFlags;
- (void) setAlertFlag:(int)flag to:(BOOL)value;
- (OOAlertCondition) alertCondition;

- (BOOL) mountMissile:(ShipEntity *)missile;
- (BOOL) mountMissileWithRole:(NSString *)role;

- (OOEnergyUnitType) installedEnergyUnitType;
- (OOEnergyUnitType) energyUnitType;

- (BOOL) fireEnergyBomb;
- (ShipEntity *) launchMine:(ShipEntity *)mine;

- (BOOL) weaponsOnline;
- (void) setWeaponsOnline:(BOOL)newValue;

- (BOOL) fireMainWeapon;

- (OOWeaponType) weaponForFacing:(OOWeaponFacing)facing;
- (OOWeaponType) currentWeapon;

- (BOOL) hasEnergyBomb;

- (void) rotateCargo;

- (BOOL) hasSufficientFuelForJump;

- (BOOL) witchJumpChecklist:(BOOL)isGalacticJump;
- (void) enterGalacticWitchspace;

- (BOOL) takeInternalDamage;

- (void) loseTargetStatus;

- (void) docked;

- (void) setGuiToStatusScreen;
- (NSArray *) equipmentList;	// Each entry is an array with a string followed by a boolean indicating availability (NO = damaged).
- (NSArray *) cargoList;
- (NSArray *) cargoListForScripting;
- (void) setGuiToSystemDataScreen;
- (NSDictionary *) markedDestinations;
- (void) setGuiToLongRangeChartScreen;
- (void) setGuiToShortRangeChartScreen;
- (void) setGuiToLoadSaveScreen;
- (void) setGuiToGameOptionsScreen;
- (OOWeaponFacingSet) availableFacings;
- (void) setGuiToEquipShipScreen:(int)skip selectingFacingFor:(NSString *)eqKeyForSelectFacing;
- (void) setGuiToEquipShipScreen:(int)skip;
- (void) highlightEquipShipScreenKey:(NSString *)key;
- (void) showInformationForSelectedUpgrade;
- (void) showInformationForSelectedUpgradeWithFormatString:(NSString *)extraString;
- (BOOL) setWeaponMount:(OOWeaponFacing)chosen_weapon_facing toWeapon:(NSString *)eqKey;
- (BOOL) changePassengerBerths:(int) addRemove;
- (OOCargoQuantity) cargoQuantityForType:(OOCommodityType)type;
- (OOCargoQuantity) setCargoQuantityForType:(OOCommodityType)type amount:(OOCargoQuantity)amount;
- (void) calculateCurrentCargo;
- (void) setGuiToMarketScreen;

- (void) setGuiToIntroFirstGo:(BOOL)justCobra;

- (void) noteGUIWillChangeTo:(OOGUIScreenID)toScreen;
- (void) noteGUIDidChangeFrom:(OOGUIScreenID)fromScreen to:(OOGUIScreenID)toScreen;
- (void) noteViewDidChangeFrom:(OOViewID)fromView toView:(OOViewID)toView;

- (OOGUIScreenID) guiScreen;

- (void) buySelectedItem;
- (BOOL) marketFlooded:(OOCommodityType)type;
- (BOOL) tryBuyingCommodity:(OOCommodityType)type all:(BOOL)all;
- (BOOL) trySellingCommodity:(OOCommodityType)type all:(BOOL)all;

- (BOOL) isSpeechOn;

- (void) addEquipmentFromCollection:(id)equipment;	// equipment may be an array, a set, a dictionary whose values are all YES, or a string.
 
- (void) getFined;
- (void) adjustTradeInFactorBy:(int)value;
- (int) tradeInFactor;
- (double) renovationCosts;

- (void) setDefaultViewOffsets;
- (void) setDefaultCustomViews;
- (Vector) weaponViewOffset;

- (void) setUpTrumbles;
- (void) addTrumble:(OOTrumble *)papaTrumble;
- (void) removeTrumble:(OOTrumble *)deadTrumble;
- (OOTrumble **) trumbleArray;
- (OOUInteger) trumbleCount;
// loading and saving trumbleCount
- (id) trumbleValue;
- (void) setTrumbleValueFrom:(NSObject*) trumbleValue;

- (void) mungChecksumWithNSString:(NSString *)str;

- (NSString *)screenModeStringForWidth:(unsigned)inWidth height:(unsigned)inHeight refreshRate:(float)inRate;

- (void) suppressTargetLost;

- (void) setScoopsActive;

- (void) clearTargetMemory;
- (BOOL) moveTargetMemoryBy:(int)delta;

- (void) printIdentLockedOnForMissile:(BOOL)missile;

- (void) applyYaw:(GLfloat) yaw;

/* GILES custom viewpoints */

// custom view points
- (Quaternion)customViewQuaternion;
- (OOMatrix)customViewMatrix;
- (Vector)customViewOffset;
- (Vector)customViewForwardVector;
- (Vector)customViewUpVector;
- (Vector)customViewRightVector;
- (NSString *)customViewDescription;
- (void)resetCustomView;
- (void)setCustomViewDataFromDictionary:(NSDictionary*) viewDict;
- (Vector) viewpointPosition;
- (Vector) viewpointOffset;

- (NSDictionary *) missionOverlayDescriptor;
- (NSDictionary *) missionOverlayDescriptorOrDefault;
- (void) setMissionOverlayDescriptor:(NSDictionary *)descriptor;

- (NSDictionary *) missionBackgroundDescriptor;
- (NSDictionary *) missionBackgroundDescriptorOrDefault;
- (void) setMissionBackgroundDescriptor:(NSDictionary *)descriptor;

// Nasty hack to keep background textures around while on equip screens.
- (NSDictionary *) equipScreenBackgroundDescriptor;
- (void) setEquipScreenBackgroundDescriptor:(NSDictionary *)descriptor;

- (NSArray *) worldScriptNames;
- (NSDictionary *) worldScriptsByName;

// *** World script events.
// In general, script events should be sent through doScriptEvent:..., which
// will forward to the world scripts.
- (BOOL) doWorldEventUntilMissionScreen:(jsid)message;
- (void) doWorldScriptEvent:(jsid)message inContext:(JSContext *)context withArguments:(jsval *)argv count:(uintN)argc timeLimit:(OOTimeDelta)limit;

- (BOOL)showInfoFlag;

- (void) setGalacticHyperspaceBehaviour:(OOGalacticHyperspaceBehaviour) galacticHyperspaceBehaviour;
- (OOGalacticHyperspaceBehaviour) galacticHyperspaceBehaviour;
- (void) setGalacticHyperspaceFixedCoords:(NSPoint)point;
- (void) setGalacticHyperspaceFixedCoordsX:(unsigned char)x y:(unsigned char)y;
- (NSPoint) galacticHyperspaceFixedCoords;

- (BOOL) scoopOverride;
- (void) setScoopOverride:(BOOL)newValue;
- (void) setDockTarget:(ShipEntity *)entity;

- (BOOL) clearedToDock;
- (void) setDockingClearanceStatus:(OODockingClearanceStatus) newValue;
- (OODockingClearanceStatus) getDockingClearanceStatus;
- (void) penaltyForUnauthorizedDocking;

- (NSArray *) scannedWormholes;

- (WormholeEntity *) wormhole;
- (void) setWormhole:(WormholeEntity *)newWormhole;
- (void) addScannedWormhole:(WormholeEntity*)wormhole;

- (void) initialiseMissionDestinations:(NSDictionary *)destinations andLegacy:(NSArray *)legacy;
- (NSString *)markerKey:(NSDictionary*)marker;
- (void) addMissionDestinationMarker:(NSDictionary *)marker;
- (BOOL) removeMissionDestinationMarker:(NSDictionary *)marker;
- (NSMutableDictionary*) getMissionDestinations;

@end


/*	Use PLAYER to refer to the shared player object in cases where it is
	assumed to exist (i.e., except during early initialization).
*/
OOINLINE PlayerEntity *OOGetPlayer(void) INLINE_CONST_FUNC;
OOINLINE PlayerEntity *OOGetPlayer(void)
{
	extern PlayerEntity *gOOPlayer;
#if OO_DEBUG
	NSCAssert(gOOPlayer != nil, @"PLAYER used when [PlayerEntity sharedPlayer] has not been called.");
#endif
	return gOOPlayer;
}
#define PLAYER				OOGetPlayer()

#define KILOGRAMS_PER_POD		1000
#define MAX_KILOGRAMS_IN_SAFE	((KILOGRAMS_PER_POD / 2) - 1)
#define GRAMS_PER_POD			(KILOGRAMS_PER_POD * 1000)
#define MAX_GRAMS_IN_SAFE		((GRAMS_PER_POD / 2) - 1)


NSString *OODisplayRatingStringFromKillCount(unsigned kills);
NSString *KillCountToRatingAndKillString(unsigned kills);
NSString *OODisplayStringFromLegalStatus(int legalStatus);

NSString *OOStringFromGUIScreenID(OOGUIScreenID screen) CONST_FUNC;
OOGUIScreenID OOGUIScreenIDFromString(NSString *string) PURE_FUNC;

OOGalacticHyperspaceBehaviour OOGalacticHyperspaceBehaviourFromString(NSString *string) PURE_FUNC;
NSString *OOStringFromGalacticHyperspaceBehaviour(OOGalacticHyperspaceBehaviour behaviour) CONST_FUNC;
