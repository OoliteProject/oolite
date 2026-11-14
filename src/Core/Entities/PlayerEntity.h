/*

PlayerEntity.h

Entity subclass nominally representing the player's ship, but also
implementing much of the interaction, menu system etc. Breaking it up into
ten or so different classes is a perennial to-do item.

The state is C++ since slice 1 of its slice plan (docs/phases/3-slices/PlayerEntity.md):
cxx::PlayerEntity holds the ivars, as public data members with the same names, while
PlayerEntity+ObjCBridge.h, imported at the end of this header, keeps the Objective-C PlayerEntity
and its methods (each moves to cxx::PlayerEntity in its own slice). The bridge's deletion moves
the class out of namespace cxx.

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

#pragma once

#import "GuiDisplayGen.h"
#import "OOCommodityMarket.h"
#import "OOFoundation.h"
#import "OOJSPropID.h"
#import "OOTypes.h"
#import "ShipEntity.h"
#import "WormholeEntity.h"

#include "oofnd/PList.hpp"
#include "oofnd/Ref.hpp"
#include "oofnd/StdLib.hpp"
#include "oofnd/objc/OOAssert.h"

@class PlayerEntity, GuiDisplayGen, OOTrumble, MyOpenGLView, HeadUpDisplay, ShipEntity;
@class OOSound, OOSoundSource;
@class OOJoystickManager, OOTexture, OOLaserShotEntity;
@class OOJSGuiScreenKeyDefinition, OOJSScript;
class StickProfileScreen; // C++ (PlayerEntityStickProfile.h, bead oo-movn)

#define ALLOW_CUSTOM_VIEWS_WHILE_PAUSED 1
#define SCRIPT_TIMER_INTERVAL 10.0

#ifndef OO_VARIABLE_TORUS_SPEED
#define OO_VARIABLE_TORUS_SPEED 1
#endif

#define GUI_ROW_INIT(GUI) /*int n_rows = [(GUI) rows]*/
#define GUI_FIRST_ROW(GROUP) ((GUI_DEFAULT_ROWS - GUI_ROW_##GROUP##OPTIONS_END_OF_LIST) / 2)
// reposition menu
#define GUI_ROW(GROUP, ITEM) (GUI_FIRST_ROW(GROUP) - 4 + GUI_ROW_##GROUP##OPTIONS_##ITEM)

#define CUSTOM_VIEW_MAX_ZOOM_IN 1.5
#define CUSTOM_VIEW_MAX_ZOOM_OUT 25

// OOGUIScreenID, OOGalacticHyperspaceBehaviour and their defaults (bead oo-9ht.64: plain header).
#include "OOEntityEnums.h"

typedef enum {
    OOPRIMEDEQUIP_ACTIVATED,
    OOPRIMEDEQUIP_MODE
} OOPrimedEquipmentMode;

typedef enum {
    OOSPEECHSETTINGS_OFF = 0,
    OOSPEECHSETTINGS_COMMS = 1,
    OOSPEECHSETTINGS_ALL = 2
} OOSpeechSettings;

// When fully zoomed in, chart shows area of galaxy that's 64x64 galaxy units.
#define CHART_WIDTH_AT_MAX_ZOOM 64.0
#define CHART_HEIGHT_AT_MAX_ZOOM 64.0
// Galaxy width / width of chart area at max zoom
#define CHART_MAX_ZOOM (256.0 / CHART_WIDTH_AT_MAX_ZOOM)
// start scrolling when cursor is this number of units away from centre
#define CHART_SCROLL_AT_X 25.0
#define CHART_SCROLL_AT_Y 31.0
#define CHART_CLIP_BORDER 10.0
#define CHART_SCREEN_VERTICAL_CENTRE (10 * MAIN_GUI_ROW_HEIGHT)
#define CHART_SCREEN_VERTICAL_CENTRE_COMPACT (7 * MAIN_GUI_ROW_HEIGHT)
#define CHART_ZOOM_SPEED_FACTOR 1.05

#define CHART_ZOOM_SHOW_LABELS 2.0

// OO_RESOLUTION_OPTION: true if full screen resolution can be changed.
#if OOLITE_MAC_OS_X && OOLITE_64_BIT
#define OO_RESOLUTION_OPTION 0
#else
#define OO_RESOLUTION_OPTION 1
#endif

// dictionary keys - used in the custom key config for oxp equipment
inline constexpr std::string_view CUSTOMEQUIP_EQUIPKEY = "equipmentKey";
inline constexpr std::string_view CUSTOMEQUIP_EQUIPNAME = "equipmentName";
inline constexpr std::string_view CUSTOMEQUIP_KEYACTIVATE = "keyActivate";
inline constexpr std::string_view CUSTOMEQUIP_KEYMODE = "keyMode";
inline constexpr std::string_view CUSTOMEQUIP_BUTTONACTIVATE = "buttonActivate";
inline constexpr std::string_view CUSTOMEQUIP_BUTTONMODE = "buttonMode";
inline constexpr std::string_view KEYCONFIG_CUSTOMEQUIP = "CustomEquipActivation"; // preferences key (oo::Defaults)

enum {
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

    STATUS_EQUIPMENT_FIRST_ROW = 10,
    STATUS_EQUIPMENT_MAX_ROWS = 8,
    STATUS_EQUIPMENT_BIGGUI_EXTRA_ROWS = 6,

    GUI_ROW_EQUIPMENT_START = 3,
    GUI_MAX_ROWS_EQUIPMENT = 12,
    GUI_ROW_EQUIPMENT_DETAIL = GUI_ROW_EQUIPMENT_START + GUI_MAX_ROWS_EQUIPMENT + 1,
    GUI_ROW_EQUIPMENT_CASH = 1,
    GUI_ROW_MARKET_KEY = 1,
    GUI_ROW_MARKET_START = 2,
    GUI_ROW_MARKET_SCROLLUP = 4,
    GUI_ROW_MARKET_SCROLLDOWN = 16,
    GUI_ROW_MARKET_LAST = 18,
    GUI_ROW_MARKET_END = 19,
    GUI_ROW_MARKET_CASH = 20,
    GUI_ROW_INTERFACES_HEADING = 1,
    GUI_ROW_INTERFACES_START = 3,
    GUI_MAX_ROWS_INTERFACES = 12,
    GUI_ROW_INTERFACES_DETAIL = GUI_ROW_INTERFACES_START + GUI_MAX_ROWS_INTERFACES + 1,
    GUI_ROW_NO_INTERFACES = 3,
    GUI_ROW_SCENARIOS_START = 3,
    GUI_MAX_ROWS_SCENARIOS = 12,
    GUI_ROW_SCENARIOS_DETAIL = GUI_ROW_SCENARIOS_START + GUI_MAX_ROWS_SCENARIOS + 2,
    GUI_ROW_CHART_SYSTEM = 19,
    GUI_ROW_CHART_SYSTEM_COMPACT = 17,
    GUI_ROW_PLANET_FINDER = 20
};

#if GUI_FIRST_ROW() < 0
#error Too many items in OPTIONS list!
#endif

enum {
    GUI_ROW_GAMEOPTIONS_AUTOSAVE,
    GUI_ROW_GAMEOPTIONS_DOCKINGCLEARANCE,
    GUI_ROW_GAMEOPTIONS_SPACER1,
    GUI_ROW_GAMEOPTIONS_VOLUME,
#if OOLITE_SPEECH_SYNTH
    GUI_ROW_GAMEOPTIONS_SPEECH,
#if !OOLITE_MAC_COCOA_UI
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
    GUI_ROW_GAMEOPTIONS_SHADEREFFECTS,
    GUI_ROW_GAMEOPTIONS_FOV,
    GUI_ROW_GAMEOPTIONS_COLORBLINDMODE,
    GUI_ROW_GAMEOPTIONS_SPACER_STICKMAPPER,
    GUI_ROW_GAMEOPTIONS_STICKMAPPER,
    GUI_ROW_GAMEOPTIONS_KEYMAPPER,
    GUI_ROW_GAMEOPTIONS_SPACER3,
    GUI_ROW_GAMEOPTIONS_BACK,

    GUI_ROW_GAMEOPTIONS_END_OF_LIST
};
#if GUI_FIRST_ROW() < 0
#error Too many items in GAMEOPTIONS list!
#endif

enum {
    GUI_ROW_GAMEOPTIONS_HDRPAPERWHITE = GUI_ROW_GAMEOPTIONS_WIREFRAMEGRAPHICS,
    GUI_ROW_GAMEOPTIONS_HDRMAXBRIGHTNESS = GUI_ROW_GAMEOPTIONS_DETAIL
};

typedef enum {
    // Exposed to shaders.
    SCOOP_STATUS_NOT_INSTALLED = 0,
    SCOOP_STATUS_FULL_HOLD,
    SCOOP_STATUS_OKAY,
    SCOOP_STATUS_ACTIVE
} OOFuelScoopStatus;

enum {
    ALERT_FLAG_DOCKED = 0x010,
    ALERT_FLAG_MASS_LOCK = 0x020,
    ALERT_FLAG_YELLOW_LIMIT = 0x03f,
    ALERT_FLAG_TEMP = 0x040,
    ALERT_FLAG_ALT = 0x080,
    ALERT_FLAG_ENERGY = 0x100,
    ALERT_FLAG_HOSTILES = 0x200
};
typedef uint16_t OOAlertFlags;

typedef enum {
    // Exposed to shaders.
    MISSILE_STATUS_SAFE,
    MISSILE_STATUS_ARMED,
    MISSILE_STATUS_TARGET_LOCKED
} OOMissileStatus;

typedef enum {
    PLAYER_FLEEING_UNLIKELY = -1,
    PLAYER_FLEEING_NONE = 0,
    PLAYER_FLEEING_MAYBE = 1,
    PLAYER_FLEEING_CARGO = 2,
    PLAYER_FLEEING_LIKELY = 3
} OOPlayerFleeingStatus;

typedef enum {
    MARKET_FILTER_MODE_OFF = 0,
    MARKET_FILTER_MODE_TRADE = 1,
    MARKET_FILTER_MODE_HOLD = 2,
    MARKET_FILTER_MODE_STOCK = 3,
    MARKET_FILTER_MODE_LEGAL = 4,
    MARKET_FILTER_MODE_RESTRICTED = 5, // import or export

    MARKET_FILTER_MODE_MAX = 5 // always equal to highest real mode
} OOMarketFilterMode;

typedef enum {
    MARKET_SORTER_MODE_OFF = 0,
    MARKET_SORTER_MODE_ALPHA = 1,
    MARKET_SORTER_MODE_PRICE = 2,
    MARKET_SORTER_MODE_STOCK = 3,
    MARKET_SORTER_MODE_HOLD = 4,
    MARKET_SORTER_MODE_UNIT = 5,

    MARKET_SORTER_MODE_MAX = 5 // always equal to highest real mode
} OOMarketSorterMode;

#define ECM_ENERGY_DRAIN_FACTOR 20.0f
#define ECM_DURATION 2.5f

#define ROLL_DAMPING_FACTOR 1.0f
#define PITCH_DAMPING_FACTOR 1.0f
#define YAW_DAMPING_FACTOR 1.0f

#define PLAYER_MAX_WEAPON_TEMP 256.0f
#ifdef OO_DUMP_PLANETINFO
// debugging
#define PLAYER_MAX_FUEL 7000
#else
#define PLAYER_MAX_FUEL 70
#endif
#define PLAYER_MAX_MISSILES 16
#define PLAYER_STARTING_MAX_MISSILES 4
#define PLAYER_STARTING_MISSILES 3
#define PLAYER_DIAL_MAX_ALTITUDE 40000.0
#define PLAYER_SUPER_ALTITUDE2 10000000000.0

#define PLAYER_MAX_TRUMBLES 24

#define PLAYER_TARGET_MEMORY_SIZE 16

#if OO_VARIABLE_TORUS_SPEED
#define HYPERSPEED_FACTOR [PLAYER hyperspeedFactor]
#define MIN_HYPERSPEED_FACTOR 32.0
#define MAX_HYPERSPEED_FACTOR 1024.0
#else
#define HYPERSPEED_FACTOR 32.0
#endif

inline constexpr std::string_view PLAYER_SHIP_DESC = "cobra3-player";

#define ESCAPE_SEQUENCE_TIME 10.0

#define FORWARD_FACING_STRING OO_DESC("forward-facing-string")
#define AFT_FACING_STRING OO_DESC("aft-facing-string")
#define PORT_FACING_STRING OO_DESC("port-facing-string")
#define STARBOARD_FACING_STRING OO_DESC("starboard-facing-string")

#define KEY_REPEAT_INTERVAL 0.20

#define PLAYER_SHIP_CLOCK_START (2084004 * 86400.0)
// adding or removing a player ship subentity increases or decreases the ship's trade-in factor respectively by this amount
#define PLAYER_SHIP_SUBENTITY_TRADE_IN_VALUE 3

inline constexpr std::string_view CONTRACTS_GOOD_KEY = "contracts_fulfilled";
inline constexpr std::string_view CONTRACTS_BAD_KEY = "contracts_expired";
inline constexpr std::string_view CONTRACTS_UNKNOWN_KEY = "contracts_unknown";
inline constexpr std::string_view PASSAGE_GOOD_KEY = "passage_fulfilled";
inline constexpr std::string_view PASSAGE_BAD_KEY = "passage_expired";
inline constexpr std::string_view PASSAGE_UNKNOWN_KEY = "passage_unknown";
inline constexpr std::string_view PARCEL_GOOD_KEY = "parcels_fulfilled";
inline constexpr std::string_view PARCEL_BAD_KEY = "parcels_expired";
inline constexpr std::string_view PARCEL_UNKNOWN_KEY = "parcels_unknown";

#define SCANNER_ZOOM_RATE_UP 2.0
#define SCANNER_ZOOM_RATE_DOWN -8.0
#define SCANNER_ECM_FUZZINESS 1.25

#define PLAYER_INTERNAL_DAMAGE_FACTOR 31

inline constexpr std::string_view PLAYER_DOCKING_AI_NAME = "oolite-player-AI.plist";

#define MANIFEST_SCREEN_ROW_BACK 1
#define MANIFEST_SCREEN_ROW_NEXT ([[PLAYER hud] isHidden] ? 27 : 20)

inline constexpr std::string_view MISSION_DEST_LEGACY = "__oolite_legacy_destinations";

namespace cxx {

/*	The player's state, and the members its slices have moved (docs/phases/3-slices/PlayerEntity.md).

        The ivars are data members with the same names, every one zero-initialised as the runtime
        zeroed them. The facade's unconverted methods and its categories
        (PlayerEntityControls.mm and the others) reach them through the facade's _cxxPlayer, by the same
        names, so each slice gets its bodies back verbatim by deleting
        "_cxxPlayer->". Pointers to other entities and to Objective-C objects stay what they were,
        retained by hand where they were.
*/
class PlayerEntity : public ShipEntity {
public:
#ifndef NDEBUG
    /*	Names the members the analyser would call unused because only the categories read them
            (it was a method of the Objective-C class, built only into debug builds).
    */
    bool suppressClangStuff() const;
#endif

    // @private in Objective-C: private once PlayerEntity is converted; public while the
    // facade's unconverted methods and categories read them, since an Objective-C class cannot be a
    // C++ friend.
    OOSystemID system_id = { };
    OOSystemID target_system_id = { };
    OOSystemID info_system_id = { };
    OOSystemID previous_system_id = { };

    float occlusion_dial = { };

    OOSystemID found_system_id = { };
    int ship_trade_in_factor = { };

    std::vector<std::pair<std::string, oo::ObjCRef<::OOScript*>>> worldScripts; // in load order (+cxx_loadScripts)
    std::optional<std::vector<std::pair<std::string, oo::ObjCRef<::OOScript*>>>> worldScriptsRequiringTickle; // PlayerEntityLegacyScriptEngine's cache; nullopt: not built
    std::map<std::string, oo::ObjCRef<::OOScript*>, std::less<>> commodityScripts; // by script file name
    oo::PList mission_variables; // a Dict (saved as mission_variables); null before set-up
    std::map<std::string, oo::PList, std::less<>> localVariables; // mission key -> that mission's variables (a Dict)
    std::optional<std::string> _missionTitle; // nullopt: the mission screen falls back on its default
    NSInteger /*OOGUIRow*/ missionTextRow = { };
    std::optional<std::string> missionChoice;
    std::optional<std::string> missionKeyPress;
    BOOL _missionWithCallback = { };
    BOOL _missionAllowInterrupt = { };
    BOOL _missionTextEntry = { };
    OOGUIScreenID _missionExitScreen = { };

    std::optional<std::string> specialCargo;

    std::vector<std::string> commLog; // trimmed by -cxx_commLog

    std::vector<std::pair<std::string, oo::ObjCRef<::OOJSScript*>>> eqScripts; // (key, script), in insertion order

    oo::PList _missionOverlayDescriptor; // null = none (was nil)
    oo::PList _missionBackgroundDescriptor;
    OOGUIBackgroundSpecial _missionBackgroundSpecial = { };
    oo::PList _equipScreenBackgroundDescriptor;
    std::optional<std::string> _missionScreenID;

    BOOL found_equipment = { };

    oo::PList::Dict reputation; // signed integers by key (PlayerEntity (Contracts))

    unsigned max_passengers = { };
    oo::PList::Array passengers; // Dicts (PlayerEntity (Contracts))
    oo::PList::Dict passenger_record; // arrival time (double) by passenger name

    oo::PList::Array parcels; // Dicts (PlayerEntity (Contracts))
    oo::PList::Dict parcel_record; // arrival time (double) by sender name

    oo::PList::Array contracts; // cargo contract Dicts (PlayerEntity (Contracts))
    oo::PList::Dict contract_record; // arrival time (double) by cargo ID

    oo::PList::Dict shipyard_record; // shipdata key by shipyard ID of each ship bought

    std::map<std::string, oo::PList, std::less<>> missionDestinations; // validated marker Dicts by -markerKey:
    std::vector<std::string> roleWeights;
    // temporary flags for role actions taking multiple steps, cleared on jump (signed integers)
    oo::PList::Dict roleWeightFlags;
    std::vector<OOSystemID> roleSystemList; // list of recently visited sysids

    double script_time = { };
    double script_time_check = { };
    double script_time_interval = { };
    std::optional<std::string> lastTextKey; // nullopt: none

    double ship_clock = { };
    double ship_clock_adjust = { };

    double escape_pod_rescue_time = { };

    double fps_check_time = { };
    int fps_counter = { };
    double last_fps_check_time = { };

    std::optional<std::string> planetSearchString; // the lower-cased typed prefix; nullopt: no search

    OOMatrix playerRotMatrix = { };

    BOOL showingLongRangeChart = { };

    // For OO-GUI based save screen
    std::string commanderNameString; // owned; the save screen refreshes it from the typed string each frame
    std::vector<oo::PList> cdrDetailArray; // the load/save screen's entries (PlayerEntity (LoadSave))
    int currentPage = { };
    BOOL pollControls = { };
    // ...end save screen

    NSInteger marketOffset = { };
    std::optional<std::string> marketSelectedCommodity;
    OOMarketFilterMode marketFilterMode = { };
    OOMarketSorterMode marketSorterMode = { };

    ::OOWeakReference* _dockedStation = { };

    /* Used by the DOCKING_CLEARANCE code to implement docking at non-main
     * stations. Could possibly overload use of 'dockedStation' instead
     * but that needs futher investigation to ensure it doesn't break anything. */
    ::StationEntity* targetDockStation = { };

    ::HeadUpDisplay* hud = { };
    std::map<std::string, std::string, std::less<>> multiFunctionDisplayText; // MFD key -> text
    std::vector<std::optional<std::string>> multiFunctionDisplaySettings; // one key per MFD; nullopt = inactive (was [OONull null])
    NSUInteger activeMFD = { };
    oo::PList::Dict customDialSettings; // a mixed configuration (proposed ADR-0043 item 11): whatever scripts set

    GLfloat roll_delta = { }, pitch_delta = { }, yaw_delta = { };
    GLfloat launchRoll = { };

    GLfloat forward_shield = { }, aft_shield = { };
    GLfloat max_forward_shield = { }, max_aft_shield = { }, forward_shield_recharge_rate = { }, aft_shield_recharge_rate = { };
    OOTimeDelta forward_shot_time = { }, aft_shot_time = { }, port_shot_time = { }, starboard_shot_time = { };

    OOWeaponFacing chosen_weapon_facing = { }; // for purchasing weapons

    double ecm_start_time = { };
    double last_ecm_time = { };

    OOGUIScreenID gui_screen = { };
    OOAlertFlags alertFlags = { };
    OOAlertCondition alertCondition = { };
    OOAlertCondition lastScriptAlertCondition = { };
    OOPlayerFleeingStatus fleeing_status = { };
    OOMissileStatus missile_status = { };
    NSUInteger activeMissile = { };
    NSUInteger primedEquipment = { };
    std::optional<std::string> _fastEquipmentA; // nullopt = never set (was nil)
    std::optional<std::string> _fastEquipmentB;

    OOCargoQuantity current_cargo = { };

    NSPoint cursor_coordinates = { };
    NSPoint chart_focus_coordinates = { };
    NSPoint chart_centre_coordinates = { };
    NSPoint custom_chart_centre_coordinates = { };
    // where we want the chart centre to be - used for smooth transitions
    NSPoint target_chart_centre = { };
    NSPoint target_chart_focus = { };
    // Chart zoom is 1.0 when fully zoomed in and increases as we zoom out.  The reason I've done it that way round
    // is because we might want to implement bigger galaxies one day, and thus may need to zoom out indefinitely.
    OOScalar chart_zoom = { };
    OOScalar custom_chart_zoom = { };
    OOScalar target_chart_zoom = { };
    OOScalar saved_chart_zoom = { };
    OORouteType ANA_mode = { };
    OOTimeDelta witchspaceCountdown = { };

    std::optional<std::string> _jumpCause;

    // player commander data
    std::optional<std::string> _commanderName;
    std::optional<std::string> _lastsaveName;
    NSPoint galaxy_coordinates = { };

    OOCreditsQuantity credits = { };
    OOGalaxyID galaxy_number = { };

    ::OOCommodityMarket* shipCommodityData = { };

    ::ShipEntity* missile_entity[PLAYER_MAX_MISSILES] = { }; // holds the actual missile entities or equivalents
    OOUniversalID _dockTarget = { }; // used by the escape pod code

    int legalStatus = { }; // legalStatus both is and isn't an OOCreditsQuantity, because of quantum.
    int market_rnd = { };
    unsigned ship_kills = { };

    OOCompassMode compassMode = { };
    ::OOWeakReference* compassTarget = { };

    GLfloat fuel_leak_rate = { };

#if OO_VARIABLE_TORUS_SPEED
    GLfloat hyperspeedFactor = { };
#endif

    // keys!
    oo::PList::Dict keyconfig2_settings;
    std::map<std::string, uint16_t, std::less<>> keyCodeLookups; // lower-case key names -> key codes

    oo::PList n_key_roll_left;
    oo::PList n_key_roll_right;
    oo::PList n_key_pitch_forward;
    oo::PList n_key_pitch_back;
    oo::PList n_key_yaw_left;
    oo::PList n_key_yaw_right;

    oo::PList n_key_view_forward; // && undock
    oo::PList n_key_view_aft; // && options menu
    oo::PList n_key_view_port; // && equipment screen
    oo::PList n_key_view_starboard; // && interfaces screen

    oo::PList n_key_launch_ship;
    oo::PList n_key_gui_screen_options;
    oo::PList n_key_gui_screen_equipship;
    oo::PList n_key_gui_screen_interfaces;
    oo::PList n_key_gui_screen_status;
    oo::PList n_key_gui_chart_screens;
    oo::PList n_key_gui_system_data;
    oo::PList n_key_gui_market;

    oo::PList n_key_gui_arrow_left;
    oo::PList n_key_gui_arrow_right;
    oo::PList n_key_gui_arrow_up;
    oo::PList n_key_gui_arrow_down;
    oo::PList n_key_gui_page_up;
    oo::PList n_key_gui_page_down;
    oo::PList n_key_gui_select;

    oo::PList n_key_increase_speed;
    oo::PList n_key_decrease_speed;
    oo::PList n_key_inject_fuel;

    oo::PList n_key_fire_lasers;
    oo::PList n_key_launch_missile;
    oo::PList n_key_next_missile;
    oo::PList n_key_ecm;

    oo::PList n_key_prime_next_equipment;
    oo::PList n_key_prime_previous_equipment;
    oo::PList n_key_activate_equipment;
    oo::PList n_key_mode_equipment;
    oo::PList n_key_fastactivate_equipment_a;
    oo::PList n_key_fastactivate_equipment_b;

    oo::PList n_key_target_missile;
    oo::PList n_key_untarget_missile;
    oo::PList n_key_target_incoming_missile;
    oo::PList n_key_ident_system;

    oo::PList n_key_scanner_zoom;
    oo::PList n_key_scanner_unzoom;

    oo::PList n_key_launch_escapepod;

    oo::PList n_key_galactic_hyperspace;
    oo::PList n_key_hyperspace;
    oo::PList n_key_jumpdrive;

    oo::PList n_key_dump_cargo;
    oo::PList n_key_rotate_cargo;

    oo::PList n_key_autopilot;
    oo::PList n_key_autodock;

    oo::PList n_key_snapshot;
    oo::PList n_key_docking_music;

    oo::PList n_key_advanced_nav_array_next;
    oo::PList n_key_advanced_nav_array_previous;
    oo::PList n_key_info_next_system;
    oo::PList n_key_info_previous_system;
    oo::PList n_key_map_home;
    oo::PList n_key_map_end;
    oo::PList n_key_map_next_system;
    oo::PList n_key_map_previous_system;
    oo::PList n_key_map_info;
    oo::PList n_key_map_zoom_in;
    oo::PList n_key_map_zoom_out;

    oo::PList n_key_system_home;
    oo::PList n_key_system_end;
    oo::PList n_key_system_next_system;
    oo::PList n_key_system_previous_system;

    oo::PList n_key_pausebutton;
    oo::PList n_key_show_fps;
    oo::PList n_key_bloom_toggle;
    oo::PList n_key_mouse_control_roll;
    oo::PList n_key_mouse_control_yaw;
    oo::PList n_key_hud_toggle;

    oo::PList n_key_comms_log;
    oo::PList n_key_prev_compass_mode;
    oo::PList n_key_next_compass_mode;

    oo::PList n_key_chart_highlight;
    oo::PList n_key_market_filter_cycle;
    oo::PList n_key_market_sorter_cycle;
    oo::PList n_key_market_buy_one;
    oo::PList n_key_market_sell_one;
    oo::PList n_key_market_buy_max;
    oo::PList n_key_market_sell_max;

    oo::PList n_key_next_target;
    oo::PList n_key_previous_target;

    oo::PList n_key_custom_view;
    oo::PList n_key_custom_view_zoom_out;
    oo::PList n_key_custom_view_zoom_in;
    oo::PList n_key_custom_view_roll_left;
    oo::PList n_key_custom_view_pan_left;
    oo::PList n_key_custom_view_roll_right;
    oo::PList n_key_custom_view_pan_right;
    oo::PList n_key_custom_view_rotate_up;
    oo::PList n_key_custom_view_pan_up;
    oo::PList n_key_custom_view_rotate_down;
    oo::PList n_key_custom_view_pan_down;
    oo::PList n_key_custom_view_rotate_left;
    oo::PList n_key_custom_view_rotate_right;

    oo::PList n_key_docking_clearance_request;
    oo::PList n_key_weapons_online_toggle;

    oo::PList n_key_cycle_next_mfd;
    oo::PList n_key_cycle_previous_mfd;
    oo::PList n_key_switch_next_mfd;
    oo::PList n_key_switch_previous_mfd;

    oo::PList n_key_oxzmanager_setfilter;
    oo::PList n_key_oxzmanager_showinfo;
    oo::PList n_key_oxzmanager_copyurl;
    oo::PList n_key_oxzmanager_extract;

#if OO_FOV_INFLIGHT_CONTROL_ENABLED
    oo::PList n_key_inc_field_of_view;
    oo::PList n_key_dec_field_of_view;
#endif

#ifdef OO_DEBUG_MONITOR_ENABLED
    oo::PList n_key_dump_target_state;
    oo::PList n_key_dump_entity_list;
    oo::PList n_key_debug_full;
    oo::PList n_key_debug_collision;
    oo::PList n_key_debug_console_connect;
    oo::PList n_key_debug_bounding_boxes;
    oo::PList n_key_debug_shaders;
    oo::PList n_key_debug_off;
#endif

    // dict to hold custom key config for OXP equipment with activate/mode functions
    std::vector<oo::PList> customEquipActivation; // Dict entries, edited in place by KeyMapper/StickMapper/Controls
    std::vector<BOOL> customActivatePressed; // parallel to customEquipActivation
    std::vector<BOOL> customModePressed;

    // dict to hold extra keys for missions screen.
    std::map<std::string, oo::PList, std::less<>> extraMissionKeys; // key name -> processed key definitions

    std::map<int, std::vector<oo::ObjCRef<::OOJSGuiScreenKeyDefinition*>>> extraGuiScreenKeys; // by GUI screen ID

    // save-file
    std::optional<std::string> save_path;
    std::optional<std::string> scenarioKey;

    // position of viewports
    Vector forwardViewOffset = { }, aftViewOffset = { }, portViewOffset = { }, starboardViewOffset = { };
    Vector _sysInfoLight = { };

    // trumbles
    NSUInteger trumbleCount = { };
    ::OOTrumble* trumble[PLAYER_MAX_TRUMBLES] = { };
    float _trumbleAppetiteAccumulator = { };

    // smart zoom
    GLfloat scanner_zoom_rate = { };

    // target memory
    // TODO: this should use weakrefs
    std::vector<oo::ObjCRef<::OOWeakReference*>> target_memory; // a null ref = an empty slot (was [OONull null])
    NSUInteger target_memory_index = { };

    // custom view points
    Quaternion customViewQuaternion = { };
    OOMatrix customViewMatrix = { };
    Vector customViewOffset = { }, customViewForwardVector = { }, customViewUpVector = { }, customViewRightVector = { }, customViewRotationCenter = { };
    std::optional<std::string> customViewDescription;

    // docking reports
    std::string dockingReport;

    // Woo, flags.
    unsigned suppressTargetLost : 1 = 0, // smart target lst reports
        scoopsActive : 1 = 0, // smart fuelscoops

        scoopOverride : 1 = 0, // scripted to just be on, ignoring normal rules
        game_over : 1 = 0,
                                  finished : 1 = 0,
                                  bomb_detonated : 1 = 0,
                                  autopilot_engaged : 1 = 0,

                                  afterburner_engaged : 1 = 0,
                                  afterburnerSoundLooping : 1 = 0,

                                  hyperspeed_engaged : 1 = 0,
                                  travelling_at_hyperspeed : 1 = 0,
                                  hyperspeed_locked : 1 = 0,

                                  ident_engaged : 1 = 0,

                                  galactic_witchjump : 1 = 0,

                                  ecm_in_operation : 1 = 0,

                                  show_info_flag : 1 = 0,

                                  showDemoShips : 1 = 0,

                                  rolling = { }, pitching = { }, yawing : 1 = 0,
                                  using_mining_laser : 1 = 0,

                                  mouse_control_on : 1 = 0,

                                  keyboardRollOverride : 1 = 0, // Handle keyboard roll...
        keyboardPitchOverride : 1 = 0, // ...and pitch override separately - (fix for BUG #17490)
        keyboardYawOverride : 1 = 0,
                                  waitingForStickCallback : 1 = 0,

                                  weapons_online : 1 = 0,

                                  launchingMissile : 1 = 0,
                                  replacingMissile : 1 = 0,

                                  massLockable : 1 = 0;
#if OOLITE_ESPEAK
    unsigned int voice_no = { };
    BOOL voice_gender_m = { };
#endif
    OOSpeechSettings isSpeechOn = { };

    // For PlayerEntity (StickMapper)
    int selFunctionIdx = { };
    std::vector<oo::PList> stickFunctions; // PlayerEntity (StickMapper)'s function list; empty until built
    std::vector<oo::PList> keyFunctions; // PlayerEntity (KeyMapper)'s function list; empty until built
    std::vector<oo::PList> kbdLayouts; // PlayerEntity (KeyMapper)'s keyboard layouts; empty until built
    std::string keyShiftText;
    std::string keyMod1Text;
    std::string keyMod2Text;

    OOGalacticHyperspaceBehaviour galacticHyperspaceBehaviour = { };
    NSPoint galacticHyperspaceFixedCoords = { };

    OOLongRangeChartMode longRangeChartMode = { };

    std::vector<oo::PList> _customViews; // the ship's custom view Dicts
    NSUInteger _customViewIndex = { };

    OODockingClearanceStatus dockingClearanceStatus = { };

    std::vector<oo::ObjCRef<::WormholeEntity*>> scannedWormholes;
    ::WormholeEntity* wormhole = { };

    ::ShipEntity* demoShip = { }; // Used while docked to maintain demo ship rotation.
    std::vector<oo::ObjCRef<::OOLaserShotEntity*>> lastShot; // used to correctly position laser shots on first frame of firing

    oo::Ref<::StickProfileScreen> stickProfileScreen;

    double maxFieldOfView = { };
    double fieldOfView = { };
#if OO_FOV_INFLIGHT_CONTROL_ENABLED
    double fov_delta = { };
#endif
};

} // namespace cxx

/*	Use PLAYER to refer to the shared player object in cases where it is
        assumed to exist (i.e., except during early initialization).
*/
OOINLINE PlayerEntity* OOGetPlayer(void) INLINE_CONST_FUNC;
OOINLINE PlayerEntity* OOGetPlayer(void)
{
    extern PlayerEntity* gOOPlayer;
#if OO_DEBUG
    OOCAssert(gOOPlayer != nil, "PLAYER used when [PlayerEntity sharedPlayer] has not been called.");
#endif
    return gOOPlayer;
}
#define PLAYER OOGetPlayer()

#define KILOGRAMS_PER_POD 1000
#define MAX_KILOGRAMS_IN_SAFE ((KILOGRAMS_PER_POD / 2) - 1)
#define GRAMS_PER_POD (KILOGRAMS_PER_POD * 1000)
#define MAX_GRAMS_IN_SAFE ((GRAMS_PER_POD / 2) - 1)

// C++ forms, defined in OOConstToString.mm (bead oo-nts1, chunk oo-3rb.161): std::string results
// (never nil), const std::string & parameters (nil arrived as "" and matched nothing: the defaults).
std::string cxx_OOStringFromGUIScreenID(OOGUIScreenID screen);
OOGUIScreenID cxx_OOGUIScreenIDFromString(const std::string& string);

OOGalacticHyperspaceBehaviour cxx_OOGalacticHyperspaceBehaviourFromString(const std::string& string);
std::string cxx_OOStringFromGalacticHyperspaceBehaviour(OOGalacticHyperspaceBehaviour behaviour);

// Rating and legal-status names from descriptions.plist (chunk oo-3rb.162); nullopt: missing (was nil).
std::optional<std::string> cxx_OODisplayRatingStringFromKillCount(unsigned kills);
std::string cxx_KillCountToRatingAndKillString(unsigned kills);
std::optional<std::string> cxx_OODisplayStringFromLegalStatus(int legalStatus);

// Transitional: the Objective-C PlayerEntity, for its unconverted methods, its categories and its
// callers. Deleted, with namespace cxx above, when the bridge is.
#import "PlayerEntity+ObjCBridge.h"
