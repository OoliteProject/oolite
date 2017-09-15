/*

PlayerEntity.h

Entity subclass nominally representing the player's ship, but also
implementing much of the interaction, menu system etc. Breaking it up into
ten or so different classes is a perennial to-do item.

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

#import <Foundation/Foundation.h>
#import "WormholeEntity.h"
#import "ShipEntity.h"
#import "GuiDisplayGen.h"
#import "OOTypes.h"
#import "OOJSPropID.h"
#import "OOCommodityMarket.h"

@class GuiDisplayGen, OOTrumble, MyOpenGLView, HeadUpDisplay, ShipEntity;
@class OOSound, OOSoundSource, OOSoundReferencePoint;
@class OOJoystickManager, OOTexture, OOLaserShotEntity;
@class StickProfileScreen;

#define ALLOW_CUSTOM_VIEWS_WHILE_PAUSED	1
#define SCRIPT_TIMER_INTERVAL			10.0

#ifndef OO_VARIABLE_TORUS_SPEED
#define OO_VARIABLE_TORUS_SPEED			1
#endif

#define GUI_ROW_INIT(GUI) /*int n_rows = [(GUI) rows]*/
#define GUI_FIRST_ROW(GROUP) ((GUI_DEFAULT_ROWS - GUI_ROW_##GROUP##OPTIONS_END_OF_LIST) / 2)
// reposition menu
#define GUI_ROW(GROUP,ITEM) (GUI_FIRST_ROW(GROUP) - 4 + GUI_ROW_##GROUP##OPTIONS_##ITEM)

#define CUSTOM_VIEW_MAX_ZOOM_IN		1.5
#define CUSTOM_VIEW_MAX_ZOOM_OUT	25

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

typedef enum
{
	OOPRIMEDEQUIP_ACTIVATED,
	OOPRIMEDEQUIP_MODE
} OOPrimedEquipmentMode;

typedef enum
{
	OOSPEECHSETTINGS_OFF = 0,
	OOSPEECHSETTINGS_COMMS = 1,
	OOSPEECHSETTINGS_ALL = 2
} OOSpeechSettings;


typedef enum
{
	OOLRC_MODE_NORMAL = 0,
	OOLRC_MODE_ECONOMY = 1,
	OOLRC_MODE_GOVERNMENT = 2,
	OOLRC_MODE_TECHLEVEL = 3
} OOLongRangeChartMode;

// When fully zoomed in, chart shows area of galaxy that's 64x64 galaxy units.
#define CHART_WIDTH_AT_MAX_ZOOM		64.0
#define CHART_HEIGHT_AT_MAX_ZOOM	64.0
// Galaxy width / width of chart area at max zoom
#define CHART_MAX_ZOOM			(256.0/CHART_WIDTH_AT_MAX_ZOOM)
//start scrolling when cursor is this number of units away from centre
#define CHART_SCROLL_AT_X		25.0
#define CHART_SCROLL_AT_Y		31.0
#define CHART_CLIP_BORDER		10.0
#define CHART_SCREEN_VERTICAL_CENTRE	(10*MAIN_GUI_ROW_HEIGHT)
#define CHART_SCREEN_VERTICAL_CENTRE_COMPACT	(7*MAIN_GUI_ROW_HEIGHT)
#define CHART_ZOOM_SPEED_FACTOR		1.05

#define CHART_ZOOM_SHOW_LABELS		2.0

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
	GUI_ROW_OPTIONS_SPACER1,
	GUI_ROW_OPTIONS_GAMEOPTIONS,
	GUI_ROW_OPTIONS_SPACER2,
	GUI_ROW_OPTIONS_BEGIN_NEW,
#if OOLITE_SDL
	GUI_ROW_OPTIONS_SPACER3,
	GUI_ROW_OPTIONS_QUIT,
#endif
	GUI_ROW_OPTIONS_END_OF_LIST,
	
	STATUS_EQUIPMENT_FIRST_ROW 			= 10,
	STATUS_EQUIPMENT_MAX_ROWS 			= 8,
	STATUS_EQUIPMENT_BIGGUI_EXTRA_ROWS	= 6,

	GUI_ROW_EQUIPMENT_START				= 3,
	GUI_MAX_ROWS_EQUIPMENT				= 12,
	GUI_ROW_EQUIPMENT_DETAIL			= GUI_ROW_EQUIPMENT_START + GUI_MAX_ROWS_EQUIPMENT + 1,
	GUI_ROW_EQUIPMENT_CASH				= 1,
	GUI_ROW_MARKET_KEY					= 1,
	GUI_ROW_MARKET_START				= 2,
	GUI_ROW_MARKET_SCROLLUP				= 4,
	GUI_ROW_MARKET_SCROLLDOWN			= 16,
	GUI_ROW_MARKET_LAST					= 18,
	GUI_ROW_MARKET_END					= 19,
	GUI_ROW_MARKET_CASH					= 20,
	GUI_ROW_INTERFACES_HEADING			= 1,
	GUI_ROW_INTERFACES_START			= 3,
	GUI_MAX_ROWS_INTERFACES				= 12,
	GUI_ROW_INTERFACES_DETAIL			= GUI_ROW_INTERFACES_START + GUI_MAX_ROWS_INTERFACES + 1,
	GUI_ROW_NO_INTERFACES				= 3,
	GUI_ROW_SCENARIOS_START				= 3,
	GUI_MAX_ROWS_SCENARIOS				= 12,
	GUI_ROW_SCENARIOS_DETAIL			= GUI_ROW_SCENARIOS_START + GUI_MAX_ROWS_SCENARIOS + 2,
	GUI_ROW_CHART_SYSTEM				= 19,
	GUI_ROW_CHART_SYSTEM_COMPACT		= 17,
	GUI_ROW_PLANET_FINDER				= 20
};

#if GUI_FIRST_ROW() < 0
# error Too many items in OPTIONS list!
#endif

enum
{
	GUI_ROW_GAMEOPTIONS_AUTOSAVE,
	GUI_ROW_GAMEOPTIONS_DOCKINGCLEARANCE,
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
#if !NEW_PLANETS
	GUI_ROW_GAMEOPTIONS_PROCEDURALLYTEXTUREDPLANETS,
#endif
	GUI_ROW_GAMEOPTIONS_SHADEREFFECTS,
#if OOLITE_SDL
	GUI_ROW_GAMEOPTIONS_GAMMA,
#endif
	GUI_ROW_GAMEOPTIONS_FOV,
	GUI_ROW_GAMEOPTIONS_SPACER_STICKMAPPER,
	GUI_ROW_GAMEOPTIONS_STICKMAPPER,
	GUI_ROW_GAMEOPTIONS_KEYMAPPER,
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


typedef enum
{
	PLAYER_FLEEING_UNLIKELY = -1,
	PLAYER_FLEEING_NONE = 0,
	PLAYER_FLEEING_MAYBE = 1,
	PLAYER_FLEEING_CARGO = 2,
	PLAYER_FLEEING_LIKELY = 3
} OOPlayerFleeingStatus;


typedef enum
{
	MARKET_FILTER_MODE_OFF = 0,
	MARKET_FILTER_MODE_TRADE = 1,
	MARKET_FILTER_MODE_HOLD = 2,
	MARKET_FILTER_MODE_STOCK = 3,
	MARKET_FILTER_MODE_LEGAL = 4,
	MARKET_FILTER_MODE_RESTRICTED = 5, // import or export


	MARKET_FILTER_MODE_MAX = 5 // always equal to highest real mode
} OOMarketFilterMode;


typedef enum
{
	MARKET_SORTER_MODE_OFF = 0,
	MARKET_SORTER_MODE_ALPHA = 1,
	MARKET_SORTER_MODE_PRICE = 2,
	MARKET_SORTER_MODE_STOCK = 3,
	MARKET_SORTER_MODE_HOLD = 4,
	MARKET_SORTER_MODE_UNIT = 5,

	MARKET_SORTER_MODE_MAX = 5 // always equal to highest real mode
} OOMarketSorterMode;


#define ECM_ENERGY_DRAIN_FACTOR			20.0f
#define ECM_DURATION					2.5f

#define ROLL_DAMPING_FACTOR				1.0f
#define PITCH_DAMPING_FACTOR			1.0f
#define YAW_DAMPING_FACTOR				1.0f

#define PLAYER_MAX_WEAPON_TEMP			256.0f
#ifdef OO_DUMP_PLANETINFO
// debugging
#define PLAYER_MAX_FUEL					7000
#else
#define PLAYER_MAX_FUEL					70
#endif
#define PLAYER_MAX_MISSILES				16
#define PLAYER_STARTING_MAX_MISSILES	4
#define PLAYER_STARTING_MISSILES		3
#define PLAYER_DIAL_MAX_ALTITUDE		40000.0
#define PLAYER_SUPER_ALTITUDE2			10000000000.0

#define PLAYER_MAX_TRUMBLES				24

#define	PLAYER_TARGET_MEMORY_SIZE		16

#if OO_VARIABLE_TORUS_SPEED
#define HYPERSPEED_FACTOR				[PLAYER hyperspeedFactor]
#define MIN_HYPERSPEED_FACTOR			32.0
#define MAX_HYPERSPEED_FACTOR			1024.0
#else
#define HYPERSPEED_FACTOR				32.0
#endif

#define PLAYER_SHIP_DESC				@"cobra3-player"

#define ESCAPE_SEQUENCE_TIME			10.0

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
#define PARCEL_GOOD_KEY					@"parcels_fulfilled"
#define PARCEL_BAD_KEY					@"parcels_expired"
#define PARCEL_UNKNOWN_KEY				@"parcels_unknown"


#define SCANNER_ZOOM_RATE_UP			2.0
#define SCANNER_ZOOM_RATE_DOWN			-8.0
#define SCANNER_ECM_FUZZINESS			1.25

#define PLAYER_INTERNAL_DAMAGE_FACTOR	31

#define PLAYER_DOCKING_AI_NAME			@"oolite-player-AI.plist"

#define	MANIFEST_SCREEN_ROW_BACK		1
#define	MANIFEST_SCREEN_ROW_NEXT		([[PLAYER hud] isHidden]?27:20)

#define MISSION_DEST_LEGACY				@"__oolite_legacy_destinations"


@interface PlayerEntity: ShipEntity
{
@private
	OOSystemID				system_id;
	OOSystemID				target_system_id;
	OOSystemID				info_system_id;

	float					occlusion_dial;
	
	OOSystemID				found_system_id;
	int						ship_trade_in_factor;
	
	NSDictionary			*worldScripts;
	NSDictionary			*worldScriptsRequiringTickle;
	NSMutableDictionary		*commodityScripts;
	NSMutableDictionary		*mission_variables;
	NSMutableDictionary		*localVariables;
	NSString				*_missionTitle;
	NSInteger /*OOGUIRow*/	missionTextRow;
	NSString				*missionChoice;
	BOOL					_missionWithCallback;
	BOOL					_missionAllowInterrupt;
	BOOL					_missionTextEntry;
	OOGUIScreenID			_missionExitScreen;
	
	NSString				*specialCargo;
	
	NSMutableArray			*commLog;

	NSMutableArray			*eqScripts;
	
	NSDictionary			*_missionOverlayDescriptor;
	NSDictionary			*_missionBackgroundDescriptor;
	OOGUIBackgroundSpecial	_missionBackgroundSpecial;
	NSDictionary			*_equipScreenBackgroundDescriptor;
	NSString				*_missionScreenID;
	
	BOOL					found_equipment;
	
	NSMutableDictionary		*reputation;
	
	unsigned				max_passengers;
	NSMutableArray			*passengers;
	NSMutableDictionary		*passenger_record;

	NSMutableArray			*parcels;
	NSMutableDictionary		*parcel_record;
	
	NSMutableArray			*contracts;
	NSMutableDictionary		*contract_record;
	
	NSMutableDictionary		*shipyard_record;
	
	NSMutableDictionary		*missionDestinations;
	NSMutableArray			*roleWeights;
	// temporary flags for role actions taking multiple steps, cleared on jump
	NSMutableDictionary		*roleWeightFlags;
	NSMutableArray			*roleSystemList; // list of recently visited sysids
	
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

	NSInteger				marketOffset;
	OOCommodityType			marketSelectedCommodity;
	OOMarketFilterMode		marketFilterMode;
	OOMarketSorterMode		marketSorterMode;

	OOWeakReference			*_dockedStation;
	
/* Used by the DOCKING_CLEARANCE code to implement docking at non-main
 * stations. Could possibly overload use of 'dockedStation' instead
 * but that needs futher investigation to ensure it doesn't break anything. */
	StationEntity			*targetDockStation; 
	
	HeadUpDisplay			*hud;
	NSMutableDictionary		*multiFunctionDisplayText;
	NSMutableArray			*multiFunctionDisplaySettings;
	NSUInteger				activeMFD;
	NSMutableDictionary		*customDialSettings;

	GLfloat					roll_delta, pitch_delta, yaw_delta;
	GLfloat					launchRoll;
	
	GLfloat					forward_shield, aft_shield;
	GLfloat					max_forward_shield, max_aft_shield, forward_shield_recharge_rate, aft_shield_recharge_rate;
	OOTimeDelta				forward_shot_time, aft_shot_time, port_shot_time, starboard_shot_time;
	
	OOWeaponFacing			chosen_weapon_facing;   // for purchasing weapons
	
	double					ecm_start_time;
	double					last_ecm_time;	

	OOGUIScreenID			gui_screen;
	OOAlertFlags			alertFlags;
	OOAlertCondition		alertCondition;
	OOAlertCondition		lastScriptAlertCondition;
	OOPlayerFleeingStatus	fleeing_status;
	OOMissileStatus			missile_status;
	NSUInteger				activeMissile;
	NSUInteger				primedEquipment;
	NSString				*_fastEquipmentA;
	NSString				*_fastEquipmentB;

	OOCargoQuantity			current_cargo;
	
	NSPoint					cursor_coordinates;
	NSPoint					chart_focus_coordinates;
	NSPoint					chart_centre_coordinates;
	// where we want the chart centre to be - used for smooth transitions
	NSPoint					target_chart_centre;
	NSPoint					target_chart_focus;
	// Chart zoom is 1.0 when fully zoomed in and increases as we zoom out.  The reason I've done it that way round
	// is because we might want to implement bigger galaxies one day, and thus may need to zoom out indefinitely.
	OOScalar				chart_zoom;
	OOScalar				target_chart_zoom;
	OOScalar				saved_chart_zoom;
	OORouteType				ANA_mode;
	OOTimeDelta				witchspaceCountdown;
	
	// player commander data
	NSString				*_commanderName;
	NSString				*_lastsaveName;
	NSPoint					galaxy_coordinates;
	
	OOCreditsQuantity		credits;	
	OOGalaxyID				galaxy_number;
	
	OOCommodityMarket		*shipCommodityData;
	
	ShipEntity				*missile_entity[PLAYER_MAX_MISSILES];	// holds the actual missile entities or equivalents
	OOUniversalID			_dockTarget;	// used by the escape pod code
	
	int						legalStatus;	// legalStatus both is and isn't an OOCreditsQuantity, because of quantum.
	int						market_rnd;
	unsigned				ship_kills;
	
	OOCompassMode			compassMode;
	OOWeakReference			*compassTarget;
	
	GLfloat					fuel_leak_rate;

#if OO_VARIABLE_TORUS_SPEED
	GLfloat					hyperspeedFactor;
#endif

	// keys!
	NSDictionary   *keyconfig_settings;

	OOKeyCode				key_roll_left;
	OOKeyCode				key_roll_right;
	OOKeyCode				key_pitch_forward;
	OOKeyCode				key_pitch_back;
	OOKeyCode				key_yaw_left;
	OOKeyCode				key_yaw_right;

	OOKeyCode				key_view_forward; 		// && undock
	OOKeyCode				key_view_aft;			// && options menu
	OOKeyCode				key_view_port;			// && equipment screen
	OOKeyCode				key_view_starboard;		// && interfaces screen

	OOKeyCode				key_gui_screen_status;
	OOKeyCode				key_gui_chart_screens;
	OOKeyCode				key_gui_system_data;
	OOKeyCode				key_gui_market;

	OOKeyCode				key_gui_arrow_left;
	OOKeyCode				key_gui_arrow_right;
	OOKeyCode				key_gui_arrow_up;
	OOKeyCode				key_gui_arrow_down;
	
	OOKeyCode				key_increase_speed;
	OOKeyCode				key_decrease_speed;
	OOKeyCode				key_inject_fuel;
	
	OOKeyCode				key_fire_lasers;
	OOKeyCode				key_launch_missile;
	OOKeyCode				key_next_missile;
	OOKeyCode				key_ecm;
	
	OOKeyCode				key_prime_equipment;
	OOKeyCode				key_activate_equipment;
	OOKeyCode				key_mode_equipment;
	OOKeyCode				key_fastactivate_equipment_a;
	OOKeyCode				key_fastactivate_equipment_b;
	
	OOKeyCode				key_target_missile;
	OOKeyCode				key_untarget_missile;
	OOKeyCode				key_target_incoming_missile;
	OOKeyCode				key_ident_system;
	
	OOKeyCode				key_scanner_zoom;
	OOKeyCode				key_scanner_unzoom;
	
	OOKeyCode				key_launch_escapepod;
	
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
	OOKeyCode				key_info_next_system;
	OOKeyCode				key_info_previous_system;
	OOKeyCode				key_map_home;
	OOKeyCode				key_map_info;
	
	OOKeyCode				key_pausebutton;
	OOKeyCode				key_show_fps;
	OOKeyCode				key_mouse_control;
	OOKeyCode				key_hud_toggle;
	
	OOKeyCode				key_comms_log;
	OOKeyCode				key_prev_compass_mode;
	OOKeyCode				key_next_compass_mode;
	
	OOKeyCode				key_chart_highlight;
	OOKeyCode				key_market_filter_cycle;
	OOKeyCode				key_market_sorter_cycle;
	
	OOKeyCode				key_next_target;
	OOKeyCode				key_previous_target;
	
	OOKeyCode				key_custom_view;
	
	OOKeyCode				key_docking_clearance_request;
	
#ifndef NDEBUG
	OOKeyCode				key_dump_target_state;
#endif

	OOKeyCode				key_weapons_online_toggle;

	OOKeyCode				key_cycle_mfd;
	OOKeyCode				key_switch_mfd;

	OOKeyCode				key_oxzmanager_setfilter;
	OOKeyCode				key_oxzmanager_showinfo;
	OOKeyCode				key_oxzmanager_extract;
	
	OOKeyCode				key_inc_field_of_view;
	OOKeyCode				key_dec_field_of_view;

	// save-file
	NSString				*save_path;
	NSString				*scenarioKey;
	
	// position of viewports
	Vector					forwardViewOffset, aftViewOffset, portViewOffset, starboardViewOffset;
	Vector					_sysInfoLight;
	
	// trumbles
	NSUInteger				trumbleCount;
	OOTrumble				*trumble[PLAYER_MAX_TRUMBLES];
	float					_trumbleAppetiteAccumulator;
	
	// smart zoom
	GLfloat					scanner_zoom_rate;
	
	// target memory
	// TODO: this should use weakrefs
	NSMutableArray  		*target_memory;
	NSUInteger				target_memory_index;
	
	// custom view points
	Quaternion				customViewQuaternion;
	OOMatrix				customViewMatrix;
	Vector					customViewOffset, customViewForwardVector, customViewUpVector, customViewRightVector, customViewRotationCenter;
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
	
							keyboardRollOverride: 1,   // Handle keyboard roll...
							keyboardPitchOverride: 1,  // ...and pitch override separately - (fix for BUG #17490)  
							keyboardYawOverride: 1,
							waitingForStickCallback: 1,
							
							weapons_online: 1,
							
							launchingMissile: 1,
							replacingMissile: 1,
							
							massLockable: 1;
#if OOLITE_ESPEAK
	unsigned int			voice_no;
	BOOL					voice_gender_m;
#endif
	OOSpeechSettings		isSpeechOn;


	// For PlayerEntity (StickMapper)
	int						selFunctionIdx;
	NSArray					*stickFunctions; 
	
	OOGalacticHyperspaceBehaviour galacticHyperspaceBehaviour;
	NSPoint					galacticHyperspaceFixedCoords;
	
	OOLongRangeChartMode	longRangeChartMode;

	NSArray					*_customViews;
	NSUInteger				_customViewIndex;
	
	OODockingClearanceStatus dockingClearanceStatus;
	
	NSMutableArray			*scannedWormholes;
	WormholeEntity			*wormhole;

	ShipEntity				*demoShip; // Used while docked to maintain demo ship rotation.
	NSArray                 *lastShot; // used to correctly position laser shots on first frame of firing
	
	StickProfileScreen		*stickProfileScreen;

	double					maxFieldOfView;
	double					fieldOfView;
#if OO_FOV_INFLIGHT_CONTROL_ENABLED
	double					fov_delta;
#endif
}

+ (PlayerEntity *) sharedPlayer;
- (void) deferredInit;

- (BOOL) setUpAndConfirmOK:(BOOL)stopOnError;
- (BOOL) setUpAndConfirmOK:(BOOL)stopOnError saveGame:(BOOL)loadingGame;
- (void) completeSetUp;
- (void) completeSetUpAndSetTarget:(BOOL)setTarget;
- (void) startUpComplete;

- (NSString *) commanderName;
- (void) setCommanderName:(NSString *)value;
- (NSString *) lastsaveName;
- (void) setLastsaveName:(NSString *)value;

- (BOOL) isDocked;

- (void) warnAboutHostiles;

- (void) unloadCargoPods;
- (void) loadCargoPods;
- (void) unloadAllCargoPodsForType:(OOCommodityType)type toManifest:(OOCommodityMarket *) manifest;
- (void) unloadCargoPodsForType:(OOCommodityType)type amount:(OOCargoQuantity) quantity;
- (void) loadCargoPodsForType:(OOCommodityType)type fromManifest:(OOCommodityMarket *) manifest;
- (void) loadCargoPodsForType:(OOCommodityType)type amount:(OOCargoQuantity) quantity;
- (OOCommodityMarket *) shipCommodityData;

- (OOCreditsQuantity) deciCredits;

- (int) random_factor;
- (void) setRandom_factor:(int)rf;
- (OOGalaxyID) galaxyNumber;
- (NSPoint) galaxy_coordinates;
- (void) setGalaxyCoordinates:(NSPoint)newPosition;
- (NSPoint) cursor_coordinates;
- (NSPoint) chart_centre_coordinates;
- (OOScalar) chart_zoom;
- (NSPoint) adjusted_chart_centre;
- (OORouteType) ANAMode;


- (OOSystemID) systemID;
- (void) setSystemID:(OOSystemID) sid;
- (OOSystemID) targetSystemID;
- (void) setTargetSystemID:(OOSystemID) sid;
- (OOSystemID) nextHopTargetSystemID;
- (OOSystemID) infoSystemID;
- (void) setInfoSystemID: (OOSystemID) sid moveChart:(BOOL) moveChart;
- (void) nextInfoSystem;
- (void) previousInfoSystem;
- (void) homeInfoSystem;
- (void) targetInfoSystem;
- (BOOL) infoSystemOnRoute;


- (NSDictionary *) commanderDataDictionary;
- (BOOL)setCommanderDataFromDictionary:(NSDictionary *) dict;

- (void) doBookkeeping:(double) delta_t;
- (BOOL) isValidTarget:(Entity*)target;

- (void) setMassLockable:(BOOL)newValue;
- (BOOL) massLockable;
- (BOOL) massLocked;
- (BOOL) atHyperspeed;

- (float) occlusionLevel;
- (void) setOcclusionLevel:(float)level;

- (void) setDockedAtMainStation;
- (StationEntity *) dockedStation;
// Dumb setter; callers are responsible for sanity.
- (void) setDockedStation:(StationEntity *)station;

- (void) performDockingRequest:(StationEntity *)stationForDocking;
- (void) requestDockingClearance:(StationEntity *)stationForDocking;
- (void) cancelDockingRequest:(StationEntity *)stationForDocking;
- (BOOL) engageAutopilotToStation:(StationEntity *)stationForDocking;
- (void) disengageAutopilot;

- (void) resetAutopilotAI;

- (void) setTargetDockStationTo:(StationEntity *) value;
- (StationEntity *) getTargetDockStation;

- (HeadUpDisplay *) hud;
- (BOOL) switchHudTo:(NSString *)hudFileName;
- (void) resetHud;

- (float) dialCustomFloat:(NSString *)dialKey;
- (NSString *) dialCustomString:(NSString *)dialKey;
- (OOColor *) dialCustomColor:(NSString *)dialKey;
- (void) setDialCustom:(id)value forKey:(NSString *)key;


- (NSArray *) multiFunctionDisplayList;
- (NSString *) multiFunctionText:(NSUInteger) index;
- (void) setMultiFunctionText:(NSString *)text forKey:(NSString *)key;
- (BOOL) setMultiFunctionDisplay:(NSUInteger) index toKey:(NSString *)key;
- (void) cycleMultiFunctionDisplay:(NSUInteger) index;
- (void) selectNextMultiFunctionDisplay;
- (NSUInteger) activeMFD;

- (void) setShowDemoShips:(BOOL) value;
- (BOOL) showDemoShips;

- (GLfloat) forwardShieldLevel;
- (GLfloat) aftShieldLevel;
- (GLfloat) baseMass;

- (void) setForwardShieldLevel:(GLfloat)level;
- (void) setAftShieldLevel:(GLfloat)level;

- (float) forwardShieldRechargeRate;
- (float) aftShieldRechargeRate;

- (void) setMaxForwardShieldLevel:(float)new;
- (void) setMaxAftShieldLevel:(float)new;
- (void) setForwardShieldRechargeRate:(float)new;
- (void) setAftShieldRechargeRate:(float)new;

// return keyconfig.plist settings for scripting
- (NSDictionary *) keyConfig;
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

#if OO_VARIABLE_TORUS_SPEED
- (GLfloat) hyperspeedFactor;
#endif
- (BOOL) injectorsEngaged;
- (BOOL) hyperspeedEngaged;


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
- (void) validateCompassTarget;

- (NSString *) compassTargetLabel;

- (OOCompassMode) compassMode;
- (void) setCompassMode:(OOCompassMode)value;
- (void) setPrevCompassMode;
- (void) setNextCompassMode;

- (NSUInteger) activeMissile;
- (void) setActiveMissile:(NSUInteger)value;
- (NSUInteger) dialMaxMissiles;
- (BOOL) dialIdentEngaged;
- (void) setDialIdentEngaged:(BOOL)newValue;
- (NSString *) specialCargo;
- (NSString *) dialTargetName;
- (ShipEntity *) missileForPylon:(NSUInteger)value;
- (void) safeAllMissiles;
- (void) selectNextMissile;
- (void) tidyMissilePylons;
- (BOOL) removeFromPylon:(NSUInteger) pylon;
- (BOOL) assignToActivePylon:(NSString *)identifierKey;

- (void) clearAlertFlags;
- (int) alertFlags;
- (void) setAlertFlag:(int)flag to:(BOOL)value;
- (OOAlertCondition) alertCondition;
- (OOPlayerFleeingStatus) fleeingStatus;

- (BOOL) mountMissile:(ShipEntity *)missile;
- (BOOL) mountMissileWithRole:(NSString *)role;

- (OOEnergyUnitType) installedEnergyUnitType;
- (OOEnergyUnitType) energyUnitType;

- (ShipEntity *) launchMine:(ShipEntity *)mine;

- (BOOL) activateCloakingDevice;
- (void) deactivateCloakingDevice;

- (double) scannerFuzziness;

- (BOOL) weaponsOnline;
- (void) setWeaponsOnline:(BOOL)newValue;

- (BOOL) fireMainWeapon;

- (OOWeaponType) weaponForFacing:(OOWeaponFacing)facing;
- (OOWeaponType) currentWeapon;
- (NSArray *) currentLaserOffset;

- (void) rotateCargo;

- (BOOL) hasSufficientFuelForJump;

- (BOOL) witchJumpChecklist:(BOOL)isGalacticJump;
- (void) enterGalacticWitchspace;
- (void) setJumpType:(BOOL)isGalacticJump;

- (BOOL) takeInternalDamage;

- (BOOL) endScenario:(NSString *)key;

- (NSMutableArray *) roleWeights;
- (void) addRoleForAggression:(ShipEntity *)victim;
- (void) addRoleForMining;
- (void) addRoleToPlayer:(NSString *)role;
- (void) addRoleToPlayer:(NSString *)role inSlot:(NSUInteger)slot;
- (void) clearRoleFromPlayer:(BOOL)includingLongRange;
- (void) clearRolesFromPlayer:(float)chance;
- (NSUInteger) maxPlayerRoles;
- (void) updateSystemMemory;

- (void) loseTargetStatus;

- (void) docked;

- (void) setGuiToStatusScreen;
- (NSArray *) equipmentList;	// Each entry is an array with a string followed by a boolean indicating availability (NO = damaged), then a color (or nil for default color).
- (BOOL) setPrimedEquipment:(NSString *)eqKey showMessage:(BOOL)showMsg;
- (NSString *) primedEquipmentName:(NSInteger)offset;
- (NSString *) currentPrimedEquipment;
- (NSUInteger) primedEquipmentCount;
- (void) activatePrimableEquipment:(NSUInteger)index withMode:(OOPrimedEquipmentMode)mode;
- (NSString *) fastEquipmentA;
- (NSString *) fastEquipmentB;
- (void) setFastEquipmentA:(NSString *)eqKey;
- (void) setFastEquipmentB:(NSString *)eqKey;

- (NSArray *) cargoList;
//- (NSArray *) cargoListForScripting; // now in ShipEntity
- (unsigned) legalStatusOfCargoList;

- (void) setGuiToSystemDataScreen;
- (void) setGuiToSystemDataScreenRefreshBackground: (BOOL) refreshBackground;
- (NSDictionary *) markedDestinations;
- (void) setGuiToLongRangeChartScreen;
- (void) setGuiToShortRangeChartScreen;
- (void) setGuiToChartScreenFrom: (OOGUIScreenID) oldScreen;
- (void) setGuiToLoadSaveScreen;
- (void) setGuiToGameOptionsScreen;
- (OOWeaponFacingSet) availableFacings;
- (void) setGuiToEquipShipScreen:(int)skip selectingFacingFor:(NSString *)eqKeyForSelectFacing;
- (void) setGuiToEquipShipScreen:(int)skip;

- (void) setGuiToInterfacesScreen:(int)skip;
- (void) showInformationForSelectedInterface;
- (void) activateSelectedInterface;

- (void) highlightEquipShipScreenKey:(NSString *)key;
- (void) showInformationForSelectedUpgrade;
- (void) showInformationForSelectedUpgradeWithFormatString:(NSString *)extraString;
- (BOOL) setWeaponMount:(OOWeaponFacing)chosen_weapon_facing toWeapon:(NSString *)eqKey;
- (BOOL) setWeaponMount:(OOWeaponFacing)facing toWeapon:(NSString *)eqKey inContext:(NSString *) context;

- (BOOL) changePassengerBerths:(int) addRemove;
- (OOCargoQuantity) cargoQuantityForType:(OOCommodityType)type;
- (OOCargoQuantity) setCargoQuantityForType:(OOCommodityType)type amount:(OOCargoQuantity)amount;
- (void) calculateCurrentCargo;
- (void) setGuiToMarketScreen;
- (void) setGuiToMarketInfoScreen;
- (NSArray *) applyMarketFilter:(NSArray *)goods onMarket:(OOCommodityMarket *)market;
- (NSArray *) applyMarketSorter:(NSArray *)goods onMarket:(OOCommodityMarket *)market;
- (OOCommodityMarket *) localMarket;


- (void) setupStartScreenGui;
- (void) setGuiToIntroFirstGo:(BOOL)justCobra;
- (void) setGuiToKeySettingsScreen;
- (void) setGuiToOXZManager;

- (void) noteGUIWillChangeTo:(OOGUIScreenID)toScreen;
- (void) noteGUIDidChangeFrom:(OOGUIScreenID)fromScreen to:(OOGUIScreenID)toScreen refresh: (BOOL) refresh;
- (void) noteGUIDidChangeFrom:(OOGUIScreenID)fromScreen to:(OOGUIScreenID)toScreen;
- (void) noteViewDidChangeFrom:(OOViewID)fromView toView:(OOViewID)toView;

- (OOGUIScreenID) guiScreen;

- (void) buySelectedItem;

- (BOOL) tryBuyingCommodity:(OOCommodityType)type all:(BOOL)all;
- (BOOL) trySellingCommodity:(OOCommodityType)type all:(BOOL)all;

- (OOSpeechSettings) isSpeechOn;

- (void) addEquipmentFromCollection:(id)equipment;	// equipment may be an array, a set, a dictionary whose values are all YES, or a string.
 
- (void) getFined;
- (void) adjustTradeInFactorBy:(int)value;
- (int) tradeInFactor;
- (double) renovationCosts;
- (double) renovationFactor;


- (void) setDefaultViewOffsets;
- (void) setDefaultCustomViews;
- (Vector) weaponViewOffset;

- (void) setUpTrumbles;
- (void) addTrumble:(OOTrumble *)papaTrumble;
- (void) removeTrumble:(OOTrumble *)deadTrumble;
- (OOTrumble **) trumbleArray;
- (NSUInteger) trumbleCount;
// loading and saving trumbleCount
- (id) trumbleValue;
- (void) setTrumbleValueFrom:(NSObject *)trumbleValue;

- (float) trumbleAppetiteAccumulator;
- (void) setTrumbleAppetiteAccumulator:(float)value;

- (void) mungChecksumWithNSString:(NSString *)str;

- (NSString *)screenModeStringForWidth:(unsigned)inWidth height:(unsigned)inHeight refreshRate:(float)inRate;

- (void) suppressTargetLost;

- (void) setScoopsActive;

- (void) clearTargetMemory;
- (NSMutableArray *) targetMemory;
- (BOOL) moveTargetMemoryBy:(NSInteger)delta;

- (void) printIdentLockedOnForMissile:(BOOL)missile;

- (void) applyYaw:(GLfloat) yaw;

/* GILES custom viewpoints */

// custom view points
- (Quaternion)customViewQuaternion;
- (void)setCustomViewQuaternion:(Quaternion)q1;
- (OOMatrix)customViewMatrix;
- (Vector)customViewOffset;
- (void)setCustomViewOffset:(Vector)offset;
- (Vector)customViewRotationCenter;
- (void)setCustomViewRotationCenter:(Vector)center;
- (void)customViewZoomOut:(OOScalar) rate;
- (void)customViewZoomIn: (OOScalar) rate;
- (void)customViewRotateLeft:(OOScalar) angle;
- (void)customViewRotateRight:(OOScalar) angle;
- (void)customViewRotateUp:(OOScalar) angle;
- (void)customViewRotateDown:(OOScalar) angle;
- (void)customViewRollLeft:(OOScalar) angle;
- (void)customViewRollRight:(OOScalar) angle;
- (void)customViewPanUp:(OOScalar) angle;
- (void)customViewPanDown:(OOScalar) angle;
- (void)customViewPanLeft:(OOScalar) angle;
- (void)customViewPanRight:(OOScalar) angle;
- (Vector)customViewForwardVector;
- (Vector)customViewUpVector;
- (Vector)customViewRightVector;
- (NSString *)customViewDescription;
- (void)resetCustomView;
- (void)setCustomViewData;
- (void)setCustomViewDataFromDictionary:(NSDictionary*) viewDict withScaling:(BOOL)withScaling;
- (HPVector) viewpointPosition;
- (HPVector) breakPatternPosition;
- (Vector) viewpointOffset;
- (Vector) viewpointOffsetAft;
- (Vector) viewpointOffsetForward;
- (Vector) viewpointOffsetPort;
- (Vector) viewpointOffsetStarboard;


- (NSDictionary *) missionOverlayDescriptor;
- (NSDictionary *) missionOverlayDescriptorOrDefault;
- (void) setMissionOverlayDescriptor:(NSDictionary *)descriptor;

- (NSDictionary *) missionBackgroundDescriptor;
- (NSDictionary *) missionBackgroundDescriptorOrDefault;
- (void) setMissionBackgroundDescriptor:(NSDictionary *)descriptor;
- (OOGUIBackgroundSpecial) missionBackgroundSpecial;
- (void) setMissionBackgroundSpecial:(NSString *)special;
- (void) setMissionExitScreen:(OOGUIScreenID)screen;
- (OOGUIScreenID) missionExitScreen;

// Nasty hack to keep background textures around while on equip screens.
- (NSDictionary *) equipScreenBackgroundDescriptor;
- (void) setEquipScreenBackgroundDescriptor:(NSDictionary *)descriptor;

- (BOOL) scriptsLoaded;
- (NSArray *) worldScriptNames;
- (NSDictionary *) worldScriptsByName;

- (OOScript *) commodityScriptNamed:(NSString *)script;

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

- (OOLongRangeChartMode) longRangeChartMode;
- (void) setLongRangeChartMode:(OOLongRangeChartMode) mode;

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

- (void) setLastShot:(NSArray *)shot;

- (void) showShipModelWithKey:(NSString *)shipKey shipData:(NSDictionary *)shipData personality:(uint16_t)personality factorX:(GLfloat)factorX factorY:(GLfloat)factorY factorZ:(GLfloat)factorZ inContext:(NSString *)context;

- (void) doGuiScreenResizeUpdates;

/* Fractional expression of amount of entry inside a planet's atmosphere. 0.0f is out of atmosphere,
   1.0f is fully in and is normally associated with the point of ship destruct due to altitude.
*/
- (GLfloat) insideAtmosphereFraction;

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
