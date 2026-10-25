/*

PlayerEntity.h

Entity subclass nominally representing the player's ship, but also
implementing much of the interaction, menu system etc. Breaking it up into
ten or so different classes is a perennial to-do item.

C++ since its slice plan (docs/phases/3-slices/PlayerEntity.md; proposed ADR-0056, amendments
oo-jx5np, oo-zn1vy and oo-lmdi8). Bead oo-9ht.177 deleted its Objective-C facade (amendment
oo-9ht.177): the player is made in C++ by PlayerEntity::sharedPlayer() and its Objective-C object
is a ship's (the root's facade answers the selectors the game still finds by name on the player,
legacy-script actions and queries, callObjC(), shader bindings, deferred calls, for the player's
C++ part only; the ship's facade did until bead oo-9ht.144).

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

#include "OOCocoa.h"
#include "ooscript/JSEngine.hpp"
#include "WormholeEntity.h"
#include "ShipEntity.h"
#include "OOLaserShotEntity.h"
#include "GuiDisplayGen.h"
#include "OOTypes.h"
#include "OOJSPropID.h"
#include "OOCommodityMarket.h"
#include "OOTrumble.h"

#include "oofnd/StdLib.hpp"
#include "oofnd/PList.hpp"
#include "oofnd/Ref.hpp"
#include "oofnd/objc/OOAssert.h"

class MyOpenGLView;
class ShipEntity;	// C++ since bead oo-9ht.144
class GuiDisplayGen;
#include "HeadUpDisplay.h"	// C++ since bead oo-mwd58: the player keeps its HUD (oo::Ref)
class OOSound;			// C++ since bead oo-9ht.68 deleted its facade
class OOSoundSource;	// C++ since bead oo-9ht.88 deleted its facade
class OOTexture;
#include "OOScript.h"	// oo::Ref<OOScript> members and results (bead oo-9ht.133)
#include "OOJSGuiScreenKeyDefinition.h"	// C++ since bead oo-9ht.62: extraGuiScreenKeys keeps it (oo::Ref)
class StickProfileScreen;	// C++ (PlayerEntityStickProfile.h, bead oo-movn)

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

// OOGUIScreenID, OOGalacticHyperspaceBehaviour and their defaults (bead oo-9ht.64: plain header).
#include "OOEntityEnums.h"

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

// The load / save macros, moved from PlayerEntityLoadSave.h: they condition the declarations of
// that file's members below (ADR-0056 amendment oo-lmdi8).
// Set to 1 to use custom load/save dialogs in windowed mode on Macs in debug builds. No effect on other platforms.
#define USE_CUSTOM_LOAD_SAVE_ON_MAC_DEBUG		0

// OOLITE_USE_APPKIT_LOAD_SAVE is true if we ever want AppKit dialogs.
#define OOLITE_USE_APPKIT_LOAD_SAVE				(OOLITE_MAC_OS_X && !USE_CUSTOM_LOAD_SAVE_ON_MAC_DEBUG)

// Mac 64-bit builds: never use custom load/save dialogs.
#define OO_USE_APPKIT_LOAD_SAVE_ALWAYS			(OOLITE_USE_APPKIT_LOAD_SAVE && OOLITE_64_BIT)

// OO_USE_CUSTOM_LOAD_SAVE is true if we will ever want custom dialogs.
#define OO_USE_CUSTOM_LOAD_SAVE					(!OO_USE_APPKIT_LOAD_SAVE_ALWAYS)

// dictionary keys - used in the custom key config for oxp equipment
inline constexpr std::string_view CUSTOMEQUIP_EQUIPKEY = "equipmentKey";
inline constexpr std::string_view CUSTOMEQUIP_EQUIPNAME = "equipmentName";
inline constexpr std::string_view CUSTOMEQUIP_KEYACTIVATE = "keyActivate";
inline constexpr std::string_view CUSTOMEQUIP_KEYMODE = "keyMode";
inline constexpr std::string_view CUSTOMEQUIP_BUTTONACTIVATE = "buttonActivate";
inline constexpr std::string_view CUSTOMEQUIP_BUTTONMODE = "buttonMode";
inline constexpr std::string_view KEYCONFIG_CUSTOMEQUIP = "CustomEquipActivation";  // preferences key (oo::Defaults)

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
# error Too many items in GAMEOPTIONS list!
#endif

enum
{
	GUI_ROW_GAMEOPTIONS_HDRPAPERWHITE = GUI_ROW_GAMEOPTIONS_WIREFRAMEGRAPHICS,
	GUI_ROW_GAMEOPTIONS_HDRMAXBRIGHTNESS = GUI_ROW_GAMEOPTIONS_DETAIL
};


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
#define HYPERSPEED_FACTOR				(PLAYER != nullptr ? PLAYER->getHyperspeedFactor() : 0.0f)
#define MIN_HYPERSPEED_FACTOR			32.0
#define MAX_HYPERSPEED_FACTOR			1024.0
#else
#define HYPERSPEED_FACTOR				32.0
#endif

inline constexpr std::string_view PLAYER_SHIP_DESC				= "cobra3-player";

#define ESCAPE_SEQUENCE_TIME			10.0

#define FORWARD_FACING_STRING			OO_DESC("forward-facing-string")
#define AFT_FACING_STRING				OO_DESC("aft-facing-string")
#define PORT_FACING_STRING				OO_DESC("port-facing-string")
#define STARBOARD_FACING_STRING			OO_DESC("starboard-facing-string")

#define KEY_REPEAT_INTERVAL				0.20

#define PLAYER_SHIP_CLOCK_START			(2084004 * 86400.0)
// adding or removing a player ship subentity increases or decreases the ship's trade-in factor respectively by this amount
#define PLAYER_SHIP_SUBENTITY_TRADE_IN_VALUE	3

inline constexpr std::string_view CONTRACTS_GOOD_KEY				= "contracts_fulfilled";
inline constexpr std::string_view CONTRACTS_BAD_KEY				= "contracts_expired";
inline constexpr std::string_view CONTRACTS_UNKNOWN_KEY			= "contracts_unknown";
inline constexpr std::string_view PASSAGE_GOOD_KEY				= "passage_fulfilled";
inline constexpr std::string_view PASSAGE_BAD_KEY					= "passage_expired";
inline constexpr std::string_view PASSAGE_UNKNOWN_KEY				= "passage_unknown";
inline constexpr std::string_view PARCEL_GOOD_KEY					= "parcels_fulfilled";
inline constexpr std::string_view PARCEL_BAD_KEY					= "parcels_expired";
inline constexpr std::string_view PARCEL_UNKNOWN_KEY				= "parcels_unknown";


#define SCANNER_ZOOM_RATE_UP			2.0
#define SCANNER_ZOOM_RATE_DOWN			-8.0
#define SCANNER_ECM_FUZZINESS			1.25

#define PLAYER_INTERNAL_DAMAGE_FACTOR	31

inline constexpr std::string_view PLAYER_DOCKING_AI_NAME			= "oolite-player-AI.plist";

#define	MANIFEST_SCREEN_ROW_BACK		1
#define	MANIFEST_SCREEN_ROW_NEXT		((PLAYER != nullptr && PLAYER->getHud() != nullptr && PLAYER->getHud()->isHidden())?27:20)	// a nil HUD answered NO

inline constexpr std::string_view MISSION_DEST_LEGACY				= "__oolite_legacy_destinations";


/*	The player (docs/phases/3-slices/PlayerEntity.md).

	The ivars are data members with the same names, every one zero-initialised as the runtime
	zeroed them (amendment oo-bj8 item 1), except three that shared a name with a member function
	the player overrides (alertConditionLevel, legalStatusValue, suppressTargetLostFlag; amendment
	oo-9ht.177). Pointers to other entities and to Objective-C objects keep their objects alive as
	before: oo::ObjCRef, or retained by hand where noted.
*/
class PlayerEntity : public ShipEntity
{
public:
	/*	The shared player, made on first use (amendment oo-9ht.177; it was +sharedPlayer): the C++
		player and its Objective-C object (a ship's), kept for the process as +alloc's was.
		Its initialiser ran nothing but the ship's part; deferredInit() sets up the ship.
	*/
	static PlayerEntity *sharedPlayer();
	// Out of line, where every member's class is complete (a test makes a player).
	PlayerEntity();
	~PlayerEntity() override;
	// [[PlayerEntity alloc] init]: a new player, its Objective-C object retained (+1), as the universe
	// makes one when its entity list is empty; sharedPlayer() keeps the first one (bead oo-9ht.144:
	// the object until then).
	static ::ShipEntity *newPlayerObject();
	void deferredInit();
	// What the facade's -dealloc did first, before the ship's: the root's facade calls it (the
	// ship's did until bead oo-9ht.144).
	void willDealloc();

	// What the facade answered for selectors whose C++ member is named for an ivar (amendment oo-9ht.177).
	OOAlertCondition alertCondition() override;
	int legalStatus() override;
	void suppressTargetLost() override;
	std::optional<std::string> jsClassName() override;

	// Slice 2: cargo pods, commodity data and credits, galaxy and chart coordinates, the current and previous system.
	void setName(const std::optional<std::string> &/*inName*/) override;
	GLfloat baseMass();
	void unloadAllCargoPodsForType(const std::string &type, ::OOCommodityMarket *manifest);
	void unloadCargoPodsForType(const std::string &type, OOCargoQuantity quantity);
	void unloadCargoPods();
	void createCargoPodWithType(const std::string &type, OOCargoQuantity amount);
	void loadCargoPodsForType(const std::string &type, ::OOCommodityMarket *manifest);
	void loadCargoPodsForType(const std::string &type, OOCargoQuantity quantity);
	void loadCargoPods();
	::OOCommodityMarket *getShipCommodityData();
	OOCreditsQuantity deciCredits();
	int random_factor();
	void setRandom_factor(int rf);
	virtual OOGalaxyID galaxyNumber();
	virtual NSPoint getGalaxy_coordinates();
	void setGalaxyCoordinates(NSPoint newPosition);
	virtual NSPoint getCursor_coordinates();
	NSPoint getChart_centre_coordinates();
	OOScalar getChart_zoom();
	OOScalar getCustom_chart_zoom();
	void setCustomChartZoom(OOScalar zoom);
	NSPoint getCustom_chart_centre_coordinates();
	void setCustomChartCentre(NSPoint coords);
	NSPoint adjusted_chart_centre();
	virtual OORouteType ANAMode();
	virtual OOSystemID systemID();
	void setSystemID(OOSystemID sid);
	virtual OOSystemID previousSystemID();
	void setPreviousSystemID(OOSystemID sid);

	// Slice 3: target, next-hop and info systems, the wormhole, the commander data dictionary (save).
	virtual OOSystemID targetSystemID();
	virtual void setTargetSystemID(OOSystemID sid);
	virtual OOSystemID nextHopTargetSystemID();
	virtual OOSystemID infoSystemID();
	virtual void setInfoSystemID(OOSystemID sid, bool moveChart);
	void nextInfoSystem();
	void previousInfoSystem();
	void homeInfoSystem();
	void targetInfoSystem();
	bool infoSystemOnRoute();
	::WormholeEntity *getWormhole();
	void setWormhole(::WormholeEntity *newWormhole);
	virtual oo::PList commanderDataDictionary();

	// Slice 4: setting the commander data from a dictionary (load).
	bool setCommanderDataFromDictionary(const oo::PList &dict);

	// Slice 5: set-up and start-up, ship set-up from the dictionary, the session, warning about hostiles.
	virtual bool setUpAndConfirmOK(bool stopOnError);
	bool setUpAndConfirmOK(bool stopOnError, bool saveGame);
	void completeSetUp();
	void completeSetUpAndSetTarget(bool /*setTarget*/);
	void startUpComplete();
	bool setUpShipFromDictionary(const oo::PList &shipDict) override;
	NSUInteger sessionID() override;
	void warnAboutHostiles() override;
	bool canCollide() override;

	// Slice 6: sun glare, the atmosphere, update:.
	OOComparisonResult compareZeroDistance(Entity * /*otherEntity*/) override;
	bool validForAddToUniverse() override;
	GLfloat lookingAtSunWithThresholdAngleCos(GLfloat thresholdAngleCos) override;
	GLfloat insideAtmosphereFraction();
	void update(OOTimeDelta delta_t) override;

	// Slice 7: the bookkeeping tick (doBookkeeping:), movement flags.
	void doBookkeeping(double delta_t);
	void updateMovementFlags();

	// Slice 8: alert conditions, mass lock, fuel scoops, clocks, script and trumble ticks, the autopilot and docking requests.
	void updateAlertConditionForNearbyEntities();
	void setMaxFlightPitch(GLfloat newValue) override;
	void setMaxFlightRoll(GLfloat newValue) override;
	void setMaxFlightYaw(GLfloat newValue) override;
	bool checkEntityForMassLock(Entity *ent, int theirClass);
	void updateAlertCondition();
	void updateFuelScoops(OOTimeDelta delta_t);
	void updateClocks(OOTimeDelta delta_t);
	void checkScriptsIfAppropriate();
	void updateTrumbles(OOTimeDelta delta_t);
	void performAutopilotUpdates(OOTimeDelta delta_t);
	void performDockingRequest(::StationEntity *stationForDocking);
	virtual void requestDockingClearance(::StationEntity *stationForDocking);
	virtual void cancelDockingRequest(::StationEntity *stationForDocking);
	virtual bool engageAutopilotToStation(::StationEntity *stationForDocking);
	void disengageAutopilot() override;

	// Slice 9: the autopilot AI, hyperspeed, in-flight / witchspace / launch / docking / dead updates, game over, the ship model view, targeting.
	void resetAutopilotAI();
#if OO_VARIABLE_TORUS_SPEED
	virtual GLfloat getHyperspeedFactor();
#endif
	virtual bool injectorsEngaged();
	virtual bool hyperspeedEngaged();
	void performInFlightUpdates(OOTimeDelta delta_t);
	void performWitchspaceCountdownUpdates(OOTimeDelta delta_t);
	void performWitchspaceExitUpdates(OOTimeDelta delta_t);
	void performLaunchingUpdates(OOTimeDelta delta_t);
	void performDockingUpdates(OOTimeDelta /*delta_t*/);
	void performDeadUpdates(OOTimeDelta /*delta_t*/);
	void gameOverFadeToBW();
	bool isValidTarget(Entity *target) override;
	void showGameOver();
	void showShipModelWithKey(const std::string &shipKey, const oo::PList &shipDataIn, uint16_t personality, GLfloat factorX, GLfloat factorY, GLfloat factorZ, const std::optional<std::string> &context);
	void updateTargeting();

	// Slice 10: attitude, view matrices and viewpoints, drawing, mass lock, the docked station, the HUD and its custom dials, shield levels.
	void orientationChanged() override;
	void applyAttitudeChanges(double delta_t) override;
	using ShipEntity::applyRoll;	// the yaw overload, which the player does not override
	void applyRoll(GLfloat roll1, GLfloat climb1) override;
	void applyYaw(GLfloat yaw);
	OOMatrix drawRotationMatrix() override;
	OOMatrix drawTransformationMatrix() override;
	Quaternion normalOrientation() override;
	void setNormalOrientation(Quaternion quat) override;
	void moveForward(double amount) override;
	HPVector breakPatternPosition();
	Vector viewpointOffset();
	virtual Vector viewpointOffsetAft();
	virtual Vector viewpointOffsetForward();
	virtual Vector viewpointOffsetPort();
	virtual Vector viewpointOffsetStarboard();
	virtual HPVector viewpointPosition();
	void drawImmediate(bool immediate, bool translucent) override;
	virtual void setMassLockable(bool newValue);
	virtual bool getMassLockable();
	virtual bool massLocked();
	virtual bool atHyperspeed();
	float occlusionLevel();
	void setOcclusionLevel(float level);
	void setDockedAtMainStation();
	virtual ::StationEntity *dockedStation();
	void setDockedStation(::StationEntity *station);
	void setTargetDockStationTo(::StationEntity *value);
	virtual ::StationEntity *getTargetDockStation();
	virtual ::HeadUpDisplay *getHud();
	virtual void resetHud();
	virtual bool switchHudTo(const std::string &hudFileName);
	float dialCustomFloat(const std::string &dialKey);
	std::string dialCustomString(const std::string &dialKey);
	oo::Ref<OOColor> dialCustomColor(const std::string &dialKey);
	virtual void setDialCustom(const oo::PList &value, const std::string &dialKey);
	void setShowDemoShips(bool value);
	bool getShowDemoShips();
	float maxForwardShieldLevel() override;
	float maxAftShieldLevel() override;
	virtual float forwardShieldRechargeRate();
	virtual float aftShieldRechargeRate();
	virtual void setMaxForwardShieldLevel(float newValue);
	virtual void setMaxAftShieldLevel(float newValue);
	virtual void setForwardShieldRechargeRate(float newValue);
	virtual void setAftShieldRechargeRate(float newValue);
	virtual GLfloat forwardShieldLevel();
	virtual GLfloat aftShieldLevel();
	virtual void setForwardShieldLevel(GLfloat level);
	virtual void setAftShieldLevel(GLfloat level);
	oo::PList keyConfig();
	virtual bool isMouseControlOn();
	GLfloat dialRoll();
	GLfloat dialPitch();
	GLfloat dialYaw();
	GLfloat dialSpeed();
	GLfloat dialHyperSpeed();
	virtual GLfloat dialForwardShield();

	// Slice 11: the dials (shields, energy, fuel, heat, altitude, clock, missiles, scoop), fuel leak, the comm log, player roles, system memory, the compass target.
	virtual GLfloat dialAftShield();
	GLfloat dialEnergy();
	GLfloat dialMaxEnergy();
	GLfloat dialFuel();
	GLfloat dialHyperRange();
	GLfloat laserHeatLevel() override;
	GLfloat laserHeatLevelAft() override;
	GLfloat laserHeatLevelForward() override;
	GLfloat laserHeatLevelPort() override;
	GLfloat laserHeatLevelStarboard() override;
	GLfloat dialAltitude();
	virtual double clockTime();
	virtual double clockTimeAdjusted();
	bool clockAdjusting();
	void addToAdjustTime(double seconds);
	double escapePodRescueTime();
	void setEscapePodRescueTime(double seconds);
	std::string dial_clock();
	std::string dial_clock_adjusted();
	std::string dial_fpsinfo();
	std::string dial_objinfo();
	unsigned countMissiles();
	virtual OOMissileStatus dialMissileStatus();
	bool canScoop(::ShipEntity *other) override;
	virtual OOFuelScoopStatus dialFuelScoopStatus();
	virtual float fuelLeakRate();
	virtual void setFuelLeakRate(float value);
	std::vector<std::string> *getCommLog();
	std::vector<std::string> getRoleWeights();
	void addRoleForAggression(::ShipEntity *victim);
	void addRoleForMining();
	virtual void addRoleToPlayer(const std::string &role);
	void addRoleToPlayer(const std::string &role, NSUInteger slot);
	void clearRoleFromPlayer(bool includingLongRange);
	void clearRolesFromPlayer(float chance);
	NSUInteger maxPlayerRoles();
	void updateSystemMemory();
	virtual Entity *getCompassTargetEntity();	// the compass target's C++ entity, null for none or once its object has gone (the object-answering getCompassTarget() until bead oo-zwnvp)
	void setCompassTargetEntity(Entity *value);	// (setCompassTarget() of the entity's object until bead oo-zwnvp)
	virtual void validateCompassTarget();
	std::optional<std::string> compassTargetLabel();

	// Slice 12: compass mode, missiles and pylons, special cargo, the multi-function displays, alert flags.
	virtual OOCompassMode getCompassMode();
	virtual void setCompassMode(OOCompassMode value);
	void setPrevCompassMode();
	virtual void setNextCompassMode();
	virtual NSUInteger getActiveMissile();
	void setActiveMissile(NSUInteger value);
	NSUInteger dialMaxMissiles();
	virtual bool dialIdentEngaged();
	void setDialIdentEngaged(bool newValue);
	virtual std::optional<std::string> getSpecialCargo();
	std::optional<std::string> dialTargetName();
	virtual std::vector<std::optional<std::string>> multiFunctionDisplayList();
	std::optional<std::string> multiFunctionText(NSUInteger i);
	virtual void setMultiFunctionText(const std::optional<std::string> &text, const std::optional<std::string> &key);
	virtual bool setMultiFunctionDisplay(NSUInteger index, const std::optional<std::string> &key);
	void cycleNextMultiFunctionDisplay(NSUInteger index);
	void cyclePreviousMultiFunctionDisplay(NSUInteger index);
	void selectNextMultiFunctionDisplay();
	void selectPreviousMultiFunctionDisplay();
	NSUInteger getActiveMFD();
	::ShipEntity *missileForPylon(NSUInteger value);
	virtual void safeAllMissiles();
	void tidyMissilePylons();
	void selectNextMissile();
	void clearAlertFlags();
	int getAlertFlags();
	void setAlertFlag(int flag, bool value);
	OOAlertCondition realAlertCondition() override;

	// Slice 13: alert condition, AI messages, mounting and firing missiles and mines, the cloak, ECM, energy units, the main weapons.
	virtual OOAlertCondition getAlertCondition();
	virtual OOPlayerFleeingStatus fleeingStatus();
	void interpretAIMessage(const std::string &message) override;
	bool mountMissile(::ShipEntity *missile);
	bool mountMissileWithRole(const std::string &role);
	::ShipEntity *fireMissile() override;
	::ShipEntity *launchMine(::ShipEntity *mine);
	virtual bool assignToActivePylon(const std::string &equipmentKey);
	bool activateCloakingDevice() override;
	void deactivateCloakingDevice() override;
	double scannerFuzziness();
	void noticeECM() override;
	bool fireECM() override;
	OOEnergyUnitType installedEnergyUnitType();
	OOEnergyUnitType energyUnitType();
	void currentWeaponStats();
	virtual bool weaponsOnline();
	void setWeaponsOnline(bool newValue);
	std::vector<Vector> currentLaserOffset();
	using ShipEntity::fireMainWeapon;	// the ship's fireMainWeapon(range), another selector
	bool fireMainWeapon();
	OOWeaponType weaponForFacing(OOWeaponFacing facing);
	OOWeaponType currentWeapon();

	// Slice 14: hit testing, damage, the doppelganger, the escape capsule, dumping cargo, bounty.
	using ShipEntity::doesHitLine;	// the ship's other overloads, which the player does not override
	GLfloat doesHitLine(HPVector v0, HPVector v1, ::ShipEntity **hitEntity) override;
	void takeEnergyDamage(double amount, Entity *entPart, Entity *otherPart, const std::string &weaponIdentifier) override;
	void takeScrapeDamage(double amount, Entity *ent) override;
	void takeHeatDamage(double amount) override;
	::ShipEntity *createDoppelganger();	// the proxy (its object until bead oo-9ht.144)
	::ShipEntity *launchEscapeCapsule() override;
	void dumpCargo() override;
	void rotateCargo();
	void setBounty(OOCreditsQuantity amount) override;
	void setBounty(OOCreditsQuantity amount, OOLegalStatusReason reason) override;
	void setBounty(OOCreditsQuantity amount, const std::string &reason) override;

	// Slice 15: legal status, offences, bounties collected, internal damage, destruction, ending a scenario, docking and leaving dock.
	OOCreditsQuantity getBounty() override;
	int getLegalStatus();
	void markAsOffender(int offence_value) override;
	void markAsOffender(int offence_value, OOLegalStatusReason reason) override;
	void collectBountyFor(::ShipEntity *other) override;
	virtual bool takeInternalDamage();
	void getDestroyedBy(Entity *whom, OOShipDamageType type) override;
	void loseTargetStatus();
	bool endScenario(const std::string &key);
	void enterDock(::StationEntity *station) override;
	void docked();
	void leaveDock(::StationEntity *station) override;

	// Slice 16: witchspace: start, end, checklist, jump type and distance, fuel, galactic and wormhole jumps.
	void witchStart();
	void witchEnd();
	virtual bool witchJumpChecklist(bool isGalacticJump);
	virtual void setJumpType(bool isGalacticJump);
	double hyperspaceJumpDistance();
	virtual OOFuelQuantity fuelRequiredForJump();
	bool hasSufficientFuelForJump();
	void noteCompassLostTarget();
	void enterGalacticWitchspace();
	using ShipEntity::enterWormhole;	// the ship's other overloads, which the player does not override
	void enterWormhole(::WormholeEntity *w_hole) override;
	void enterWitchspace() override;
	void witchJumpTo(OOSystemID sTo, bool misjump);

	// Slice 17: leaving witchspace, the status screen, the equipment list, primed and fast equipment, weapon types.
	void leaveWitchspace() override;
	void setGuiToStatusScreen();
	std::vector<oo::PList> equipmentList();
	NSUInteger primedEquipmentCount();
	std::optional<std::string> primedEquipmentName(NSInteger offset);
	virtual std::string currentPrimedEquipment();
	virtual bool setPrimedEquipment(const std::string &eqKey, bool showMsg);
	void activatePrimableEquipment(NSUInteger index, OOPrimedEquipmentMode mode);
	virtual std::optional<std::string> fastEquipmentA();
	virtual std::optional<std::string> fastEquipmentB();
	virtual void setFastEquipmentA(const std::optional<std::string> &eqKey);
	virtual void setFastEquipmentB(const std::optional<std::string> &eqKey);
	::OOEquipmentType *weaponTypeForFacing(OOWeaponFacing facing, bool /*strict*/) override;

	// Slice 18: scripting lists (missiles, cargo, contracts), the system data screen, marked destinations, the chart screens.
	std::vector<oo::Ref<::OOEquipmentType>> missilesList() override;
	std::vector<std::string> cargoList();
	oo::PList cargoListForScripting() override;
	unsigned legalStatusOfCargoList();
	oo::PList::Array contractsListForScriptingFromArray(const oo::PList::Array &contracts_array, bool forCargo);
	oo::PList passengerListForScripting() override;
	oo::PList parcelListForScripting() override;
	oo::PList contractListForScripting() override;
	void setGuiToSystemDataScreen();
	virtual void setGuiToSystemDataScreenRefreshBackground(bool refreshBackground);
	std::optional<std::map<int, std::vector<oo::PList>>> markedDestinations();
	void setGuiToLongRangeChartScreen();
	void setGuiToShortRangeChartScreen();
	void setGuiToChartScreenFrom(OOGUIScreenID oldScreen);

	// Slice 19: the game options and load / save screens, equip-screen key highlight, available facings.
	void setGuiToGameOptionsScreen();
	void setGuiToLoadSaveScreen();
	void highlightEquipShipScreenKey(const std::string &highlightKey);
	virtual OOWeaponFacingSet availableFacings();

	// Slice 20: the equip-ship screen and upgrade information.
	virtual void setGuiToEquipShipScreen(int skipParam, const std::optional<std::string> &eqKeyForSelectFacing);
	void setGuiToEquipShipScreen(int skip);
	void showInformationForSelectedUpgrade();
	virtual void showInformationForSelectedUpgradeWithFormatString(const std::optional<std::string> &formatString);

	// Slice 21: the interfaces screen, the start screen and intro, the OXZ manager, GUI and view change notes.
	void setGuiToInterfacesScreen(int skip);
	void showInformationForSelectedInterface();
	void activateSelectedInterface();
	void setupStartScreenGui();
	void setGuiToIntroFirstGo(bool justCobra);
	void setGuiToOXZManager();
	void noteGUIWillChangeTo(OOGUIScreenID toScreen);
	void noteGUIDidChangeFrom(OOGUIScreenID fromScreen, OOGUIScreenID toScreen);
	virtual void noteGUIDidChangeFrom(OOGUIScreenID fromScreen, OOGUIScreenID toScreen, bool refresh);
	void noteViewDidChangeFrom(OOViewID fromView, OOViewID toView);

	// Slice 22: buying equipment, script price adjustment, weapon mounts, passenger berths, removing missiles, trade-in.
	void buySelectedItem();
	OOCreditsQuantity adjustPriceByScriptForEqKey(const std::string &eqKey, OOCreditsQuantity price);
	bool tryBuyingItem(const std::string &eqKey);
	bool setWeaponMount(OOWeaponFacing facing, const std::string &eqKey) override;
	virtual bool setWeaponMount(OOWeaponFacing facing, const std::string &eqKey, const std::optional<std::string> &context);
	bool changePassengerBerths(int addRemove);
	OOCreditsQuantity removeMissiles() override;
	void doTradeIn(OOCreditsQuantity tradeInValue, double priceFactor);

	// Slice 23: cargo quantities, the local market, market filters and sorters, market screen rows.
	OOCargoQuantity cargoQuantityForType(const std::string &type);
	OOCargoQuantity setCargoQuantityForType(const std::string &type, OOCargoQuantity amount);
	void calculateCurrentCargo();
	OOCargoQuantity cargoQuantityOnBoard() override;
	::OOCommodityMarket *localMarket();
	std::vector<std::string> applyMarketFilter(const std::vector<std::string> &goods, ::OOCommodityMarket *market);
	std::vector<std::string> applyMarketSorter(const std::vector<std::string> &goods, ::OOCommodityMarket *market);
	void showMarketScreenHeaders();
	void showMarketScreenDataLine(OOGUIRow row, const std::string &good, ::OOCommodityMarket *localMarket, OOCargoQuantity quantity);
	std::optional<std::string> marketScreenTitle();

	// Slice 24: the market screens, buying and selling commodities, mining and speech flags, adding equipment.
	void setGuiToMarketScreen();
	void setGuiToMarketInfoScreen();
	void showMarketCashAndLoadLine();
	OOGUIScreenID guiScreen();
	bool tryBuyingCommodity(const std::string &index, bool all);
	bool trySellingCommodity(const std::string &index, bool all);
	bool isMining() override;
	OOSpeechSettings getIsSpeechOn();
	bool canAddEquipment(const std::string &equipmentKey, const std::string &context) override;
	bool addEquipmentItem(const std::string &equipmentKey, const std::string &context) override;

	// Slice 25: adding / removing / custom-activated equipment, pylons, parcels and passengers, comms, fines, trade-in factor, renovation, view offsets, trumbles.
	bool addEquipmentItem(const std::string &equipmentKey, bool validateAddition, const std::string &context) override;
	std::vector<oo::PList> *customEquipmentActivation();
	void addEquipmentWithScriptToCustomKeyArray(const std::string &equipmentKey);
	void validateCustomEquipActivationArray();
	void removeEquipmentItem(const std::string &equipmentKey) override;
	void addEquipmentFromCollection(const oo::PList &equipment);
	using ShipEntity::hasOneEquipmentItem;	// the ship's (itemKey, includeWeapons, loading), another selector
	bool hasOneEquipmentItem(const std::string &itemKey, bool includeMissiles);
	bool hasPrimaryWeapon(OOWeaponType weaponType) override;
	bool removeExternalStore(::OOEquipmentType *eqType) override;
	bool removeFromPylon(NSUInteger pylon);
	NSUInteger parcelCount() override;
	NSUInteger passengerCount() override;
	NSUInteger passengerCapacity() override;
	bool hasHostileTarget() override;
	void receiveCommsMessage(const std::string &message_text, ::ShipEntity *other) override;
	void getFined();
	virtual void adjustTradeInFactorBy(int value);
	virtual int tradeInFactor();
	virtual double renovationCosts();
	virtual double renovationFactor();
	void setDefaultViewOffsets();
	void setDefaultCustomViews();
	Vector weaponViewOffset();
	void setUpTrumbles();
	void addTrumble(OOTrumble *papaTrumble);
	void removeTrumble(OOTrumble *deadTrumble);
	oo::Ref<OOTrumble> *trumbleArray();
	virtual NSUInteger getTrumbleCount();

	// Slice 26: trumble values, checksums, screen modes, target memory, missile ident, rotating and panning the custom view.
	oo::PList trumbleValue();
	void setTrumbleValueFrom(const oo::PList &trumbleValue);
	float trumbleAppetiteAccumulator();
	void setTrumbleAppetiteAccumulator(float value);
	void mungChecksumWithString(const std::optional<std::string> &str);
	std::optional<std::string> screenModeStringForWidth(unsigned width, unsigned height, float refreshRate);
	void getSuppressTargetLost();
	virtual void setScoopsActive();
	void setFoundTarget(Entity *targetEntity) override;
	void addTarget(Entity *targetEntity) override;
	void clearTargetMemory();
	std::vector<oo::WeakRef<Entity>> targetMemory();
	bool moveTargetMemoryBy(NSInteger delta);
	virtual void printIdentLockedOnForMissile(bool missile);
	Quaternion getCustomViewQuaternion();
	void setCustomViewQuaternion(Quaternion q);
	OOMatrix getCustomViewMatrix();
	Vector getCustomViewOffset();
	void setCustomViewOffset(Vector offset);
	Vector getCustomViewRotationCenter();
	void setCustomViewRotationCenter(Vector center);
	void customViewZoomIn(OOScalar rate);
	void customViewZoomOut(OOScalar rate);
	void customViewRotateLeft(OOScalar angle);
	void customViewRotateRight(OOScalar angle);
	void customViewRotateUp(OOScalar angle);
	void customViewRotateDown(OOScalar angle);
	void customViewRollRight(OOScalar angle);
	void customViewRollLeft(OOScalar angle);
	void customViewPanUp(OOScalar angle);
	void customViewPanDown(OOScalar angle);

	// Slice 27: custom view vectors and data, the mission overlay and background, world scripts and script events, galactic hyperspace, jump cause, commander and save names.
	void customViewPanLeft(OOScalar angle);
	void customViewPanRight(OOScalar angle);
	Vector getCustomViewForwardVector();
	Vector getCustomViewUpVector();
	Vector getCustomViewRightVector();
	std::optional<std::string> getCustomViewDescription();
	virtual void resetCustomView();
	void setCustomViewData();
	virtual void setCustomViewDataFromDictionary(const oo::PList &viewDict, bool withScaling);
	bool showInfoFlag();
	oo::PList missionOverlayDescriptor();
	oo::PList missionOverlayDescriptorOrDefault();
	void setMissionOverlayDescriptor(const oo::PList &descriptor);
	oo::PList missionBackgroundDescriptor();
	oo::PList missionBackgroundDescriptorOrDefault();
	void setMissionBackgroundDescriptor(const oo::PList &descriptor);
	OOGUIBackgroundSpecial missionBackgroundSpecial();
	void setMissionBackgroundSpecial(const std::string &special);
	void setMissionExitScreen(OOGUIScreenID screen);
	OOGUIScreenID missionExitScreen();
	oo::PList equipScreenBackgroundDescriptor();
	void setEquipScreenBackgroundDescriptor(const oo::PList &descriptor);
	bool scriptsLoaded();
	std::vector<std::string> worldScriptNames();
	std::vector<std::pair<std::string, oo::Ref<OOScript>>> worldScriptsByName();
	::OOScript *commodityScriptNamed(const std::optional<std::string> &scriptName);
	using ShipEntity::doScriptEvent;	// the ship's other overloads, which the player does not override
	void doScriptEvent(ooscript::PropertyId message, ooscript::Context context, ooscript::Value *argv, unsigned argc) override;
	bool doWorldEventUntilMissionScreen(ooscript::PropertyId message);
	void doWorldScriptEvent(ooscript::PropertyId message, ooscript::Context context, ooscript::Value *argv, unsigned argc, OOTimeDelta limit);
	virtual void setGalacticHyperspaceBehaviour(OOGalacticHyperspaceBehaviour inBehaviour);
	virtual OOGalacticHyperspaceBehaviour getGalacticHyperspaceBehaviour();
	virtual void setGalacticHyperspaceFixedCoords(NSPoint point);
	void setGalacticHyperspaceFixedCoordsX(unsigned char x, unsigned char y);
	virtual NSPoint getGalacticHyperspaceFixedCoords();
	virtual void setWitchspaceCountdown(int spin_time);
	virtual OOLongRangeChartMode getLongRangeChartMode();
	virtual void setLongRangeChartMode(OOLongRangeChartMode mode);
	virtual bool getScoopOverride();
	virtual void setScoopOverride(bool newValue);
	GLfloat fuelChargeRate() override;	// the ship's rate unless MASS_DEPENDENT_FUEL_PRICES (Universe.h, not seen here)
	void setDockTarget(::ShipEntity *entity);
	std::optional<std::string> jumpCause();
	void setJumpCause(const std::optional<std::string> &value);
	std::optional<std::string> commanderName();
	std::optional<std::string> lastsaveName();
	void setCommanderName(const std::optional<std::string> &value);
	void setLastsaveName(const std::optional<std::string> &value);

	// Slice 28: docking clearance, scanned wormholes, mission destinations, the shipyard record, extra mission and GUI-screen keys, the state dump.
	virtual bool isDocked();
	bool clearedToDock();
	void setDockingClearanceStatus(OODockingClearanceStatus newValue);
	OODockingClearanceStatus getDockingClearanceStatus();
	void penaltyForUnauthorizedDocking();
	void addScannedWormhole(::WormholeEntity *whole);
	void updateWormholes();
	std::vector<oo::EntityHold> getScannedWormholes();	// the wormholes, their objects held
	void initialiseMissionDestinations(const oo::PList &destinations, const oo::PList &legacy);
	std::optional<std::string> markerKey(const oo::PList &marker);
	void addMissionDestinationMarker(const oo::PList &marker);
	bool removeMissionDestinationMarker(const oo::PList &marker);
	oo::PList getMissionDestinations();
	oo::PList::Dict *shipyardRecord();
	void setLastShot(const std::vector<oo::Ref<OOLaserShotEntity>> &shot);
	void clearExtraMissionKeys();
	void setExtraMissionKeys(const oo::PList &keys);
	void clearExtraGuiScreenKeys(OOGUIScreenID gui, const std::string &key);
	bool setExtraGuiScreenKeys(OOGUIScreenID gui, ::OOJSGuiScreenKeyDefinition *definition);
#ifndef NDEBUG
	void dumpSelfState() override;
#endif
#if OO_DEBUG
	// The vector and quaternion conversion statistics the debug console reads by name
	// (PS.callObjC("reportJSVectorStatistics")): callObjC's name table (OOJSCall.mm) calls them.
	// They were the categories PlayerEntity (JSVectorStatistics) / (JSQuaternionStatistics),
	// deleted by bead oo-9ht.15 (ADR-0056 amendment oo-9ht.15); static, as they read no player state.
	static oo::PList reportJSVectorStatistics();
	static void clearJSVectorStatistics();
	static oo::PList reportJSQuaternionStatistics();
	static void clearJSQuaternionStatistics();
#endif

	// Category ScriptMethods (PlayerEntityScriptMethods.mm, bead oo-50zg): methods for use by scripting mechanisms.
	// std::nullopt is nil in the Foundation-typed forms (proposed ADR-0043, bead oo-8mxr).
	virtual unsigned score();
	void setScore(unsigned value);
	double creditBalance();
	void setCreditBalance(double value);
	std::optional<std::string> dockedStationName();
	std::optional<std::string> dockedStationDisplayName();
	bool dockedAtMainStation();
	void awardCommodityType(const std::string &type, OOCargoQuantity amount);
	virtual void resetScannerZoom();
	virtual OOGalaxyID currentGalaxyID();
	virtual OOSystemID currentSystemID();
	void setMissionChoice(const std::optional<std::string> &newChoice);
	void setMissionChoice(const std::optional<std::string> &newChoice, bool withEvent);
	void setMissionChoice(const std::optional<std::string> &newChoice, const std::optional<std::string> &keyPress);
	void setMissionChoice(const std::optional<std::string> &newChoice, const std::optional<std::string> &keyPress, bool withEvent);
	void allowMissionInterrupt();
	OOTimeDelta scriptTimer();
	virtual unsigned systemPseudoRandom100();
	virtual unsigned systemPseudoRandom256();
	virtual double systemPseudoRandomFloat();
	oo::PList passengerContractMarker(OOSystemID system);
	oo::PList parcelContractMarker(OOSystemID system);
	oo::PList cargoContractMarker(OOSystemID system);
	oo::PList defaultMarker(OOSystemID system);
	oo::PList validatedMarker(const oo::PList &marker);
	std::optional<std::string> keyBindingDescription2(const std::string &binding);
	std::optional<std::string> getKeyBindingDescription(const oo::PList &keyList);
	std::optional<std::string> keyCodeDescription(OOKeyCode code);
	std::optional<std::string> keyCodeDescriptionShort(OOKeyCode code);
	std::optional<std::string> commanderKillsAsString();
	std::optional<std::string> commanderBountyAsString();
	std::optional<std::string> creditsFormattedForSubstitution();
	std::optional<std::string> creditsFormattedForLegacySubstitution();

	// PlayerEntitySound.mm: the interface, warning, damage and weapon sounds, and the afterburner loop.
	void setUpSound();
	void setUpWeaponSounds();
	void destroySound();
	void playInterfaceBeep(const std::string &beepKey);
	bool isBeeping();
	void boop();
	virtual void playIdentOn();
	void playIdentOff();
	virtual void playIdentLockedOn();
	void playMissileArmed();
	void playMineArmed();
	void playMissileSafe();
	void playMissileLockedOn();
	void playNextEquipmentSelected();
	void playNextMissileSelected();
	void playWeaponsOnline();
	void playWeaponsOffline();
	void playCargoJettisioned();
	void playAutopilotOn();
	void playAutopilotOff();
	void playAutopilotOutOfRange();
	void playAutopilotCannotDockWithTarget();
	void playSaveOverwriteYes();
	void playSaveOverwriteNo();
	void playHoldFull();
	void playJumpMassLocked();
	void playTargetLost();
	void playNoTargetInMemory();
	void playTargetSwitched();
	void playHyperspaceNoTarget();
	void playHyperspaceNoFuel();
	void playHyperspaceBlocked();
	void playHyperspaceDistanceTooGreat();
	void playCloakingDeviceOn();
	void playCloakingDeviceOff();
	void playMenuNavigationUp();
	void playMenuNavigationDown();
	void playMenuNavigationNot();
	void playMenuPagePrevious();
	void playMenuPageNext();
	void playDismissedReportScreen();
	void playDismissedMissionScreen();
	void playChangedOption();
	void updateFuelScoopSoundWithInterval(OOTimeDelta delta_t);
	void updateAfterburnerSound();
	void startAfterburnerSound();
	void stopAfterburnerSound();
	void playCloakingDeviceInsufficientEnergy();
	void playBuyCommodity();
	void playBuyShip();
	void playSellCommodity();
	void playCantBuyCommodity();
	void playCantSellCommodity();
	void playCantBuyShip();
	void playStandardHyperspace();
	virtual void playGalacticHyperspace();
	void playHyperspaceAborted();
	void playHitByECMSound();
	void playFiredECMSound();
	void playLaunchFromStation();
	void playDockWithStation();
	void playExitWitchspace();
	void playHostileWarning();
	void playAlertConditionRed();
	void playIncomingMissile(Vector missileVector);
	void playEnergyLow();
	void playDockingDenied();
	void playWitchjumpFailure();
	void playWitchjumpMisjump();
	void playWitchjumpBlocked();
	void playWitchjumpDistanceTooGreat();
	void playWitchjumpInsufficientFuel();
	void playFuelLeak();
	void playShieldHit(Vector attackVector, const std::string &weaponIdentifier);
	void playDirectHit(Vector attackVector, const std::string &weaponIdentifier);
	void playScrapeDamage(Vector attackVector);
	void playLaserHit(bool hit, Vector weaponOffset, const std::string &weaponIdentifier);
	void playWeaponOverheated(Vector weaponOffset);
	void playMissileLaunched(Vector weaponOffset, const std::string &weaponIdentifier);
	void playMineLaunched(Vector weaponOffset, const std::string &weaponIdentifier);
	void playEscapePodScooped();
	void playAegisCloseToPlanet();
	void playAegisCloseToStation();
	void playGameOver();
	void playLegacyScriptSound(const std::string &key);

	// PlayerEntityStickMapper.mm, the categories StickMapper (ADR-0056 amendment oo-lmdi8): defined in that file.
	void resetStickFunctions();
	void setGuiToStickMapperScreen(unsigned skip);
	void setGuiToStickMapperScreen(unsigned skip, bool resetCurrentRow);
	void stickMapperInputHandler(::GuiDisplayGen *gui, ::MyOpenGLView *gameView);
	void updateFunction(const oo::PList &hwDict);
	void checkCustomEquipButtons(const oo::PList &stickFn, int idx);
	void removeFunction(int idx);
	void displayFunctionList(::GuiDisplayGen *gui, NSUInteger skip);
	std::optional<std::string> describeStickDict(const oo::PList *stickDict);
	std::string hwToString(int hwFlags);
	std::vector<oo::PList> stickFunctionList();
	oo::PList makeStickGuiDict(const std::string &what, int allowable, int axisfn, int butfn);
	oo::PList makeStickGuiDictHeader(const std::string &header);

	// PlayerEntityStickProfile.mm, the categories StickProfile (ADR-0056 amendment oo-lmdi8): defined in that file.
	void setGuiToStickProfileScreen(::GuiDisplayGen *gui);
	void stickProfileInputHandler(::GuiDisplayGen *gui, ::MyOpenGLView *gameView);
	void stickProfileGraphAxisProfile(GLfloat alpha, Vector screenAt, NSSize screenSize);

	// PlayerEntityControls.mm, the categories Controls, OOControlsPrivate (ADR-0056 amendment oo-lmdi8): defined in that file.
	// Slice 1 of docs/phases/3-slices/PlayerEntityControls.md.
	virtual void initControls();
	void initKeyConfigSettings();
	oo::PList processKeyCode(const oo::PList &key_def);
	bool checkNavKeyPress(const oo::PList &key_def);
	bool checkKeyPress(const oo::PList &key_def);
	bool checkKeyPress(const oo::PList &key_def, bool fKey_only);
	bool checkKeyPressIgnoreCtrl(const oo::PList &key_def, bool ignore_ctrl);
	bool checkKeyPress(const oo::PList &key_def, bool fKey_only, bool ignore_ctrl);
	int getFirstKeyCode(const oo::PList &key_def);
	void getPollControls(double delta_t);
	bool handleGUIUpDownArrowKeys();
	void targetNewSystem(int direction, bool whileTyping);
	void clearPlanetSearchString();
	void targetNewSystem(int direction);
	void switchToMainView();
	virtual void noteSwitchToView(OOViewID toView, OOViewID fromView);
	virtual void beginWitchspaceCountdown(int spin_time);
	void beginWitchspaceCountdown();
	virtual void cancelWitchspaceCountdown();
	// Slice 2 of docs/phases/3-slices/PlayerEntityControls.md.
	void pollApplicationControls();
	// Slice 3 of docs/phases/3-slices/PlayerEntityControls.md.
	void pollFlightControls(double delta_t);
	// Slice 4 of docs/phases/3-slices/PlayerEntityControls.md.
	void pollGuiArrowKeyControls(double delta_t);
	// Slice 5 of docs/phases/3-slices/PlayerEntityControls.md.
	void pollMarketScreenControls();
	void handleGameOptionsScreenKeys();
	// Slice 6 of docs/phases/3-slices/PlayerEntityControls.md.
	void handleKeyMapperScreenKeys();
	void handleKeyboardLayoutKeys();
	void handleStickMapperScreenKeys();
	// Slice 2 of docs/phases/3-slices/PlayerEntityControls.md.
	void pollCustomViewControls();
	void pollViewControls();
	void pollFlightArrowKeyControls(double delta_t);
	// Slice 6 of docs/phases/3-slices/PlayerEntityControls.md.
	void pollGuiScreenControls();
	void pollGuiScreenControlsWithFKeyAlias(bool fKeyAlias);
	void pollGameOverControls(double delta_t);
	void pollAutopilotControls(double delta_t);
	void pollDockedControls(double delta_t);
	void handleUndockControl();
	// Slice 7 of docs/phases/3-slices/PlayerEntityControls.md.
	void pollDemoControls(double delta_t);
	// Slice 6 of docs/phases/3-slices/PlayerEntityControls.md.
	void pollMissionInterruptControls();
	void handleMissionCallback();
	void setGuiToMissionEndScreen();
	// Slice 7 of docs/phases/3-slices/PlayerEntityControls.md.
	void switchToThisView(OOViewID viewDirection);
	void switchToThisView(OOViewID viewDirection, bool processWeaponFacing);
	void switchToThisView(OOViewID viewDirection, OOViewID oldViewDirection, bool processWeaponFacing, bool justNotify);
	void handleAutopilotOn(bool fastDocking);
	void handleButtonIdent();
	void handleButtonTargetMissile();

	// PlayerEntityKeyMapper.mm, the categories KeyMapper (ADR-0056 amendment oo-lmdi8): defined in that file.
	// Slice 1 of docs/phases/3-slices/PlayerEntityKeyMapper.md.
	void initCheckingDictionary();
	void resetKeyFunctions();
	void setGuiToKeyMapperScreen(unsigned skip);
	void setGuiToKeyMapperScreen(unsigned skip, bool resetCurrentRow);
	void keyMapperInputHandler(::GuiDisplayGen *gui, ::MyOpenGLView *gameView);
	// Slice 2 of docs/phases/3-slices/PlayerEntityKeyMapper.md.
	bool entryIsIndexCustomEquip(NSUInteger idx);
	bool entryIsDictCustomEquip(const oo::PList &dict);
	bool entryIsCustomEquip(const std::string &entry);
	oo::PList getCustomEquipArray(const std::string &key_def);
	NSUInteger getCustomEquipIndex(const std::string &key_def);
	std::optional<std::string> getCustomEquipKeyDefType(const std::string &key_def);
	void setGuiToKeyConfigScreen();
	void setGuiToKeyConfigScreen(bool resetSelectedRow);
	void outputKeyDefinition(const std::string &key, const std::string &shift, const std::string &mod1, const std::string &mod2, NSUInteger skiprows);
	void handleKeyConfigKeys(::GuiDisplayGen *gui, ::MyOpenGLView *gameView);
	void setGuiToKeyConfigEntryScreen();
	void handleKeyConfigEntryKeys(::GuiDisplayGen *gui, ::MyOpenGLView *gameView);
	void updateKeyDefinition(const std::string &keystring, NSUInteger index);
	void updateShiftKeyDefinition(const std::string &key, NSUInteger index);
	void setGuiToConfirmClearScreen();
	void handleKeyMapperConfirmClearKeys(::GuiDisplayGen *gui, ::MyOpenGLView *gameView);
	// Slice 1 of docs/phases/3-slices/PlayerEntityKeyMapper.md.
	void displayKeyFunctionList(::GuiDisplayGen *gui, NSUInteger skip);
	std::vector<oo::PList> keyFunctionList();
	oo::PList makeKeyGuiDict(const std::string &what, const std::string &key_def);
	oo::PList makeKeyGuiDictHeader(const std::string &header);
	// Slice 3 of docs/phases/3-slices/PlayerEntityKeyMapper.md.
	void setGuiToKeyboardLayoutScreen(unsigned skip);
	void setGuiToKeyboardLayoutScreen(unsigned skip, bool resetCurrentRow);
	void handleKeyboardLayoutEntryKeys(::GuiDisplayGen *gui, ::MyOpenGLView *gameView);
	std::optional<std::string> keyboardDescription(const std::string &kbd);
	std::vector<oo::PList> keyboardLayoutList();
	void displayKeyboardLayoutList(::GuiDisplayGen *gui, NSUInteger skip);
	std::vector<std::string> validateAllKeys();
	std::optional<std::string> validateKey(const std::string &key, const oo::PList &check_keys);
	std::optional<std::string> searchArrayForMatch(const std::vector<std::string> &search_list, const std::string &key, const oo::PList &check_keys);
	bool entryIsEqualToDefault(const std::string &key);
	bool compareKeyEntries(const oo::PList &first, const oo::PList &second);
	void saveKeySetting(const std::string &key);
	void unsetKeySetting(const std::string &key);
	void deleteKeySetting(const std::string &key);
	void deleteAllKeySettings();
	oo::PList loadKeySettings();
	// Slice 1 of docs/phases/3-slices/PlayerEntityKeyMapper.md.
	void reloadPage();

	// PlayerEntityLegacyScriptEngine.mm, the categories Scripting (ADR-0056 amendment oo-lmdi8): defined in that file.
	// Slice 1 of docs/phases/3-slices/PlayerEntityLegacyScriptEngine.md.
	virtual void setScriptTarget(::ShipEntity *ship);
	// The player its own script target, through the virtual member (OOPlayerForScripting(); bead
	// oo-9ht.177): not virtual, so the binding's narrow test stands in for it.
	void setScriptTargetToSelf();
	::ShipEntity *scriptTarget();
	std::vector<std::pair<std::string, oo::Ref<OOScript>>> getWorldScriptsRequiringTickle();
	void checkScript();
	void runScriptActions(const oo::PList &actions, const std::optional<std::string> &contextName, ::ShipEntity *target);
	virtual void runUnsanitizedScriptActions(const oo::PList &actions, bool allowAIMethods, const std::optional<std::string> &contextName, ::ShipEntity *target);
	bool scriptTestConditions(const oo::PList &array);
	bool scriptTestCondition(const oo::PList &scriptCondition);
	std::optional<std::string> expandScriptRightHandSide(const oo::PList &rhsComponents);
	oo::PList missionVariables();
	oo::PList missionVariableForKey(const std::string &key);
	void setMissionVariable(const oo::PList &value, const std::string &key);
	oo::PList localVariablesForMission(const std::optional<std::string> &missionKey);
	std::optional<std::string> localVariableForKey(const std::string &variableName, const std::optional<std::string> &missionKey);
	void setLocalVariable(const std::optional<std::string> &value, const std::string &variableName, const std::optional<std::string> &missionKey);
	oo::PList missionsList();
	std::optional<std::string> replaceVariablesInString(const std::string &args);
	void setMissionDescription(const std::string &textKey);
	void setMissionDescription(const std::string &textKey, const std::optional<std::string> &key);
	void setMissionInstructions(const std::string &text, const std::optional<std::string> &key);
	void setMissionInstructionsList(const oo::PList &list, const std::optional<std::string> &key);
	void clearMissionDescription();
	void clearMissionDescriptionForMission(const std::string &key);
	// Slice 2 of docs/phases/3-slices/PlayerEntityLegacyScriptEngine.md.
	oo::PList mission_string();
	oo::PList status_string();
	oo::PList gui_screen_string();
	oo::PList getGalaxy_number();
	oo::PList planet_number();
	oo::PList score_number();
	oo::PList credits_number();
	oo::PList scriptTimer_number();
	oo::PList shipsFound_number();
	oo::PList commanderLegalStatus_number();
	void setLegalStatus(const std::string &valueString);
	oo::PList commanderLegalStatus_string();
	oo::PList d100_number();
	oo::PList pseudoFixedD100_number();
	oo::PList d256_number();
	oo::PList pseudoFixedD256_number();
	oo::PList clock_number();
	oo::PList clock_secs_number();
	oo::PList clock_mins_number();
	oo::PList clock_hours_number();
	oo::PList clock_days_number();
	oo::PList fuelLevel_number();
	oo::PList dockedAtMainStation_bool();
	oo::PList foundEquipment_bool();
	oo::PList sunWillGoNova_bool();
	oo::PList sunGoneNova_bool();
	oo::PList missionChoice_string();
	oo::PList missionKeyPress_string();
	oo::PList dockedTechLevel_number();
	oo::PList dockedStationName_string();
	oo::PList systemGovernment_string();
	virtual oo::PList systemGovernment_number();
	oo::PList systemEconomy_string();
	virtual oo::PList systemEconomy_number();
	virtual oo::PList systemTechLevel_number();
	virtual oo::PList systemPopulation_number();
	virtual oo::PList systemProductivity_number();
	oo::PList commanderName_string();
	oo::PList commanderRank_string();
	oo::PList commanderShip_string();
	oo::PList commanderShipDisplayName_string();
	std::optional<std::string> expandMessage(const std::string &valueString);
	using ShipEntity::commsMessage;
	void commsMessage(const std::string &valueString) override;
	void commsMessageByUnpiloted(const std::string &valueString) override;
	void consoleMessage3s(const std::string &valueString);
	void consoleMessage6s(const std::string &valueString);
	void awardCredits(const std::string &valueString);
	void awardShipKills(const std::string &valueString);
	void awardEquipment(const std::string &equipString);
	void removeEquipment(const std::string &equipString);
	void setPlanetinfo(const std::string &key_valueString);
	void setSpecificPlanetInfo(const std::string &key_valueString);
	void awardCargo(const std::string &amount_typeString);
	virtual void removeAllCargo();
	void removeAllCargo(bool forceRemoval);
	virtual void useSpecialCargo(const std::string &descriptionString);
	void testForEquipment(const std::string &equipString);
	void awardFuel(const std::string &valueString);
	void messageShipAIs(const std::string &roles_message);
	void ejectItem(const std::string &itemKey);
	// Slice 3 of docs/phases/3-slices/PlayerEntityLegacyScriptEngine.md.
	void addShips(const std::string &roles_number);
	void addSystemShips(const std::string &roles_number_position);
	virtual void addShipsAt(const std::string &roles_number_system_x_y_z);
	virtual void addShipsAtPrecisely(const std::string &roles_number_system_x_y_z);
	virtual void addShipsWithinRadius(const std::string &roles_number_system_x_y_z_r);
	void spawnShip(const std::string &ship_key);
	void set(const std::string &missionvariable_value);
	void reset(const std::string &missionvariable);
	void increment(const std::string &missionVariableObject);
	void decrement(const std::string &missionVariableObject);
	void add(const std::string &missionVariableString_value);
	void subtract(const std::string &missionVariableString_value);
	void checkForShips(const std::string &roleString);
	void resetScriptTimer();
	void addMissionText(const std::string &textKey);
	void addLiteralMissionText(const std::string &text);
	void setMissionChoiceByTextEntry(bool enable);
	void setMissionChoices(const std::string &choicesKey);
	void setMissionChoicesDictionary(const oo::PList &choicesDict);
	void resetMissionChoice();
	void clearMissionScreen();
	void addMissionDestination(const std::string &destinations);
	void removeMissionDestination(const std::string &destinations);
	void showShipModel(const std::string &role);
	void setMissionMusic(const std::string &value);
	std::optional<std::string> missionTitle();
	void setMissionTitle(const std::optional<std::string> &value);
	void setMissionImage(const std::string &value);
	void setMissionBackground(const std::string &value);
	void setFuelLeak(const std::string &value);
	oo::PList fuelLeakRate_number();
	void setSunNovaIn(const std::string &time_value);
	virtual void launchFromStation();
	void blowUpStation();
	virtual void sendAllShipsAway();
	// Slice 4 of docs/phases/3-slices/PlayerEntityLegacyScriptEngine.md.
	void addPlanet(const std::string &planetKey);
	// Slice 2 of docs/phases/3-slices/PlayerEntityLegacyScriptEngine.md.
	virtual ::OOPlanetEntity *addPlanetEntity(const std::string &planetKey);
	// Slice 4 of docs/phases/3-slices/PlayerEntityLegacyScriptEngine.md.
	void addMoon(const std::string &moonKey);
	// Slice 2 of docs/phases/3-slices/PlayerEntityLegacyScriptEngine.md.
	virtual ::OOPlanetEntity *addMoonEntity(const std::string &moonKey);
	// Slice 4 of docs/phases/3-slices/PlayerEntityLegacyScriptEngine.md.
	void debugOn();
	void debugOff();
	void debugMessage(const std::string &args);
	void playSound(const std::string &soundName);
	void doMissionCallback();
	void clearMissionScreenID();
	void setMissionScreenID(const std::optional<std::string> &msid);
	std::optional<std::string> missionScreenID();
	void endMissionScreenAndNoteOpportunity();
	void setGuiToMissionScreen();
	void refreshMissionScreenTextEntry();
	void setGuiToMissionScreenWithCallback(bool callback);
	void setBackgroundFromDescriptionsKey(const std::string &d_key);
	void addScene(const oo::PList &items, Vector off);
	bool processSceneDictionary(const oo::PList &couplet, Vector off);
	bool processSceneString(const std::string &item, Vector off);
	bool addEqScriptForKey(const std::string &eq_key);
	void removeEqScriptForKey(const std::string &eq_key);
	NSUInteger eqScriptIndexForKey(const std::string &eq_key);
	void targetNearestHostile();
	void targetNearestIncomingMissile();
	void setGalacticHyperspaceBehaviourTo(const std::string &galacticHyperspaceBehaviourString);
	void setGalacticHyperspaceFixedCoordsTo(const std::string &galacticHyperspaceFixedCoordsString);

	// PlayerEntityContracts.mm, the categories Contracts (ADR-0056 amendment oo-lmdi8): defined in that file.
	// Slice 1 of docs/phases/3-slices/PlayerEntityContracts.md.
	std::optional<std::string> processEscapePods();
	std::optional<std::string> checkPassengerContracts();
	OOCargoQuantity contractedVolumeForGood(const std::string &good);
	void addMessageToReport(const std::string &report);
	// Slice 2 of docs/phases/3-slices/PlayerEntityContracts.md.
	oo::PList getReputation();
	int passengerReputation();
	void increasePassengerReputation(unsigned amount);
	void decreasePassengerReputation(unsigned amount);
	int parcelReputation();
	void increaseParcelReputation(unsigned amount);
	void decreaseParcelReputation(unsigned amount);
	int contractReputation();
	void increaseContractReputation(unsigned amount);
	void decreaseContractReputation(unsigned amount);
	void erodeReputation();
	void normaliseReputation();
	// Slice 1 of docs/phases/3-slices/PlayerEntityContracts.md.
	virtual bool addPassenger(const std::string &Name, unsigned start, unsigned Destination, double eta, double fee, double advance, unsigned risk);
	virtual bool removePassenger(const std::string &Name);
	virtual bool addParcel(const std::string &Name, unsigned start, unsigned Destination, double eta, double fee, double premium, unsigned risk);
	virtual bool removeParcel(const std::string &Name);
	virtual bool awardContract(unsigned qty, const std::string &type, unsigned start, unsigned Destination, double eta, double fee, double premium);
	virtual bool removeContract(const std::string &type, unsigned dest);
	std::vector<std::string> passengerList();
	std::vector<std::string> parcelList();
	std::vector<std::string> contractList();
	std::vector<std::string> contractsListFromEntries(const oo::PList::Array &contracts_array, bool forCargo, bool forParcels);
	// Slice 2 of docs/phases/3-slices/PlayerEntityContracts.md.
	void setGuiToManifestScreen();
	void setManifestScreenRow(const oo::PList &object, ::OOColor *color, OOGUIRow row, OOGUIRow max_rows, OOGUIRow offset, bool multi);
	void setGuiToDockingReportScreen();
	// Slice 3 of docs/phases/3-slices/PlayerEntityContracts.md.
	OOCreditsQuantity priceForShipKey(const std::string &key);
	void setGuiToShipyardScreen(NSUInteger skip);
	void showShipyardInfoForSelection();
	void showTradeInInformationFooter();
	void showShipyardModel(const std::string &shipKey, const oo::PList &shipData, uint16_t personality);
	NSInteger missingSubEntitiesAdjustment();
	OOCreditsQuantity tradeInValue();
	bool buySelectedShip();
	bool replaceShipWithNamedShip(const std::string &shipKey);
	void newShipCommonSetup(const std::string &shipKey, const oo::PList &ship_info, const oo::PList &ship_base_dict);

	// PlayerEntityLoadSave.mm, the categories LoadSave, OOLoadSavePrivate (ADR-0056 amendment oo-lmdi8): defined in that file.
	// Slice 1 of docs/phases/3-slices/PlayerEntityLoadSave.md.
	bool loadPlayer();
	void savePlayer();
	void autosavePlayer();
	void quicksavePlayer();
	void setGuiToScenarioScreen(int page);
	void addScenarioModel(const std::string &shipKey);
	void showScenarioDetails();
	bool startScenario();
#if OO_USE_CUSTOM_LOAD_SAVE
	std::optional<std::string> commanderSelector();
#endif
#if OO_USE_CUSTOM_LOAD_SAVE
	void saveCommanderInputHandler();
#endif
#if OO_USE_CUSTOM_LOAD_SAVE
	void overwriteCommanderInputHandler();
#endif
	bool loadPlayerFromFile(const std::string &fileToOpen, bool asNew);
	// Slice 2 of docs/phases/3-slices/PlayerEntityLoadSave.md.
#if OOLITE_USE_APPKIT_LOAD_SAVE
	bool loadPlayerWithPanel();
#endif
#if OOLITE_USE_APPKIT_LOAD_SAVE
	void savePlayerWithPanel();
#endif
	void writePlayerToPath(const std::string &path);
	void nativeSavePlayer(const std::string &cdrName);
#if OO_USE_CUSTOM_LOAD_SAVE
	void setGuiToLoadCommanderScreen();
#endif
#if OO_USE_CUSTOM_LOAD_SAVE
	void setGuiToSaveCommanderScreen(const std::string &cdrName);
#endif
#if OO_USE_CUSTOM_LOAD_SAVE
	void setGuiToOverwriteScreen(const std::string &cdrName);
#endif
#if OO_USE_CUSTOM_LOAD_SAVE
	void lsCommanders(::GuiDisplayGen *gui, const std::string &directory, int page, const std::optional<std::string> &highlightName);
#endif
#if OO_USE_CUSTOM_LOAD_SAVE
	bool existingNativeSave(const std::string &cdrName);
#endif
#if OO_USE_CUSTOM_LOAD_SAVE
	void showCommanderShip(int cdrArrayIndex);
#endif
#if OO_USE_CUSTOM_LOAD_SAVE
	int findIndexOfCommander(const std::string &cdrName);
#endif

#ifndef NDEBUG
	/*	Names the members the analyser would call unused because only the categories read them
		(it was a method of the Objective-C class, built only into debug builds).
	*/
	bool suppressClangStuff() const;
#endif

	// @private in Objective-C, and private again since bead oo-4yscj (they were public while the
	// facade read them, bead oo-9ht.177): test_PlayerEntity reaches them through its
	// PlayerEntityTestAccess (ADR-0056 amendment oo-4yscj).
	friend struct PlayerEntityTestAccess;
private:
	OOSystemID				system_id = {};
	OOSystemID				target_system_id = {};
	OOSystemID				info_system_id = {};
	OOSystemID				previous_system_id = {};
	
	float					occlusion_dial = {};
	
	OOSystemID				found_system_id = {};
	int						ship_trade_in_factor = {};
	
	std::vector<std::pair<std::string, oo::Ref<OOScript>>>	worldScripts;	// in load order (+cxx_loadScripts)
	std::optional<std::vector<std::pair<std::string, oo::Ref<OOScript>>>>	worldScriptsRequiringTickle;	// PlayerEntityLegacyScriptEngine's cache; nullopt: not built
	std::map<std::string, oo::Ref<OOScript>, std::less<>>	commodityScripts;	// by script file name
	oo::PList				mission_variables;	// a Dict (saved as mission_variables); null before set-up
	std::map<std::string, oo::PList, std::less<>>	localVariables;	// mission key -> that mission's variables (a Dict)
	std::optional<std::string>	_missionTitle;	// nullopt: the mission screen falls back on its default
	NSInteger /*OOGUIRow*/	missionTextRow = {};
	std::optional<std::string>	missionChoice;
	std::optional<std::string>	missionKeyPress;
	BOOL					_missionWithCallback = {};
	BOOL					_missionAllowInterrupt = {};
	BOOL					_missionTextEntry = {};
	OOGUIScreenID			_missionExitScreen = {};
	
	std::optional<std::string>	specialCargo;
	
	std::vector<std::string>	commLog;	// trimmed by -cxx_commLog

	std::vector<std::pair<std::string, oo::Ref<OOScript>>>	eqScripts;	// (key, script), in insertion order
	
	oo::PList				_missionOverlayDescriptor;	// null = none (was nil)
	oo::PList				_missionBackgroundDescriptor;
	OOGUIBackgroundSpecial	_missionBackgroundSpecial = {};
	oo::PList				_equipScreenBackgroundDescriptor;
	std::optional<std::string>	_missionScreenID;
	
	BOOL					found_equipment = {};
	
	oo::PList::Dict			reputation;			// signed integers by key (PlayerEntity (Contracts))
	
	unsigned				max_passengers = {};
	oo::PList::Array		passengers;			// Dicts (PlayerEntity (Contracts))
	oo::PList::Dict			passenger_record;	// arrival time (double) by passenger name

	oo::PList::Array		parcels;			// Dicts (PlayerEntity (Contracts))
	oo::PList::Dict			parcel_record;		// arrival time (double) by sender name
	
	oo::PList::Array		contracts;			// cargo contract Dicts (PlayerEntity (Contracts))
	oo::PList::Dict			contract_record;	// arrival time (double) by cargo ID
	
	oo::PList::Dict			shipyard_record;	// shipdata key by shipyard ID of each ship bought
	
	std::map<std::string, oo::PList, std::less<>>	missionDestinations;	// validated marker Dicts by -markerKey:
	std::vector<std::string>	roleWeights;
	// temporary flags for role actions taking multiple steps, cleared on jump (signed integers)
	oo::PList::Dict			roleWeightFlags;
	std::vector<OOSystemID>	roleSystemList; // list of recently visited sysids
	
	double					script_time = {};
	double					script_time_check = {};
	double					script_time_interval = {};
	std::optional<std::string>	lastTextKey;	// nullopt: none
	
	double					ship_clock = {};
	double					ship_clock_adjust = {};
	
	double					escape_pod_rescue_time = {};

	double					fps_check_time = {};
	int						fps_counter = {};
	double					last_fps_check_time = {};
	
	std::optional<std::string>	planetSearchString;	// the lower-cased typed prefix; nullopt: no search
	
	OOMatrix				playerRotMatrix = {};
	
	BOOL					showingLongRangeChart = {};
	
	// For OO-GUI based save screen
	std::string				commanderNameString;	// owned; the save screen refreshes it from the typed string each frame
	std::vector<oo::PList>	cdrDetailArray;			// the load/save screen's entries (PlayerEntity (LoadSave))
	int						currentPage = {};
	BOOL					pollControls = {};
// ...end save screen   

	NSInteger				marketOffset = {};
	std::optional<std::string>	marketSelectedCommodity;
	OOMarketFilterMode		marketFilterMode = {};
	OOMarketSorterMode		marketSorterMode = {};

	oo::WeakRef<Entity>	_dockedStation;	// a weak reference to the station's C++ part (bead oo-9ht.39.5.2; its object's, held, before)
	
/* Used by the DOCKING_CLEARANCE code to implement docking at non-main
 * stations. Could possibly overload use of 'dockedStation' instead
 * but that needs futher investigation to ensure it doesn't break anything. */
	::StationEntity			*targetDockStation = {}; 
	
	oo::Ref<HeadUpDisplay>	hud;
	std::map<std::string, std::string, std::less<>>	multiFunctionDisplayText;	// MFD key -> text
	std::vector<std::optional<std::string>>	multiFunctionDisplaySettings;	// one key per MFD; nullopt = inactive (was [OONull null])
	NSUInteger				activeMFD = {};
	oo::PList::Dict			customDialSettings;	// a mixed configuration (proposed ADR-0043 item 11): whatever scripts set

	GLfloat					roll_delta = {}, pitch_delta = {}, yaw_delta = {};
	GLfloat					launchRoll = {};
	
	GLfloat					forward_shield = {}, aft_shield = {};
	GLfloat					max_forward_shield = {}, max_aft_shield = {}, forward_shield_recharge_rate = {}, aft_shield_recharge_rate = {};
	OOTimeDelta				forward_shot_time = {}, aft_shot_time = {}, port_shot_time = {}, starboard_shot_time = {};
	
	OOWeaponFacing			chosen_weapon_facing = {};   // for purchasing weapons
	
	double					ecm_start_time = {};
	double					last_ecm_time = {};	

	OOGUIScreenID			gui_screen = {};
	OOAlertFlags			alertFlags = {};
	OOAlertCondition		alertConditionLevel = {};	// the ivar alertCondition
	OOAlertCondition		lastScriptAlertCondition = {};
	OOPlayerFleeingStatus	fleeing_status = {};
	OOMissileStatus			missile_status = {};
	NSUInteger				activeMissile = {};
	NSUInteger				primedEquipment = {};
	std::optional<std::string>	_fastEquipmentA;	// nullopt = never set (was nil)
	std::optional<std::string>	_fastEquipmentB;

	OOCargoQuantity			current_cargo = {};
	
	NSPoint					cursor_coordinates = {};
	NSPoint					chart_focus_coordinates = {};
	NSPoint					chart_centre_coordinates = {};
	NSPoint					custom_chart_centre_coordinates = {};
	// where we want the chart centre to be - used for smooth transitions
	NSPoint					target_chart_centre = {};
	NSPoint					target_chart_focus = {};
	// Chart zoom is 1.0 when fully zoomed in and increases as we zoom out.  The reason I've done it that way round
	// is because we might want to implement bigger galaxies one day, and thus may need to zoom out indefinitely.
	OOScalar				chart_zoom = {};
	OOScalar				custom_chart_zoom = {};
	OOScalar				target_chart_zoom = {};
	OOScalar				saved_chart_zoom = {};
	OORouteType				ANA_mode = {};
	OOTimeDelta				witchspaceCountdown = {};
	
	std::optional<std::string>	_jumpCause;

	// player commander data
	std::optional<std::string>	_commanderName;
	std::optional<std::string>	_lastsaveName;
	NSPoint					galaxy_coordinates = {};
	
	OOCreditsQuantity		credits = {};	
	OOGalaxyID				galaxy_number = {};
	
	oo::Ref<OOCommodityMarket>	shipCommodityData;
	
	oo::EntityHold	missile_entity[PLAYER_MAX_MISSILES];	// holds the actual missile entities or equivalents (held; bead oo-5q11i; oo::EntityHold since bead oo-xn1j1)
	OOUniversalID			_dockTarget = {};	// used by the escape pod code
	
	int						legalStatusValue = {};	// the ivar legalStatus; it both is and isn't an OOCreditsQuantity, because of quantum.
	int						market_rnd = {};
	unsigned				ship_kills = {};
	
	OOCompassMode			compassMode = {};
	oo::WeakRef<Entity>	compassTarget;	// a weak reference to the target's C++ part (bead oo-9ht.39.5.2; its object's, held, before)
	
	GLfloat					fuel_leak_rate = {};

#if OO_VARIABLE_TORUS_SPEED
	GLfloat					hyperspeedFactor = {};
#endif

	// keys!
	oo::PList::Dict	keyconfig2_settings;
	std::map<std::string, uint16_t, std::less<>>	keyCodeLookups;	// lower-case key names -> key codes

	oo::PList					n_key_roll_left;
	oo::PList					n_key_roll_right;
	oo::PList					n_key_pitch_forward;
	oo::PList					n_key_pitch_back;
	oo::PList					n_key_yaw_left;
	oo::PList					n_key_yaw_right;

	oo::PList					n_key_view_forward; 		// && undock
	oo::PList					n_key_view_aft;			// && options menu
	oo::PList					n_key_view_port;			// && equipment screen
	oo::PList					n_key_view_starboard;		// && interfaces screen

	oo::PList					n_key_launch_ship;
	oo::PList					n_key_gui_screen_options;
	oo::PList					n_key_gui_screen_equipship;
	oo::PList					n_key_gui_screen_interfaces;
	oo::PList					n_key_gui_screen_status;
	oo::PList					n_key_gui_chart_screens;
	oo::PList					n_key_gui_system_data;
	oo::PList					n_key_gui_market;

	oo::PList					n_key_gui_arrow_left;
	oo::PList					n_key_gui_arrow_right;
	oo::PList					n_key_gui_arrow_up;
	oo::PList					n_key_gui_arrow_down;
	oo::PList					n_key_gui_page_up;
	oo::PList					n_key_gui_page_down;
	oo::PList					n_key_gui_select;
	
	oo::PList					n_key_increase_speed;
	oo::PList					n_key_decrease_speed;
	oo::PList					n_key_inject_fuel;
	
	oo::PList					n_key_fire_lasers;
	oo::PList					n_key_launch_missile;
	oo::PList					n_key_next_missile;
	oo::PList					n_key_ecm;
	
	oo::PList					n_key_prime_next_equipment;
	oo::PList					n_key_prime_previous_equipment;
	oo::PList					n_key_activate_equipment;
	oo::PList					n_key_mode_equipment;
	oo::PList					n_key_fastactivate_equipment_a;
	oo::PList					n_key_fastactivate_equipment_b;
	
	oo::PList					n_key_target_missile;
	oo::PList					n_key_untarget_missile;
	oo::PList					n_key_target_incoming_missile;
	oo::PList					n_key_ident_system;
	
	oo::PList					n_key_scanner_zoom;
	oo::PList					n_key_scanner_unzoom;
	
	oo::PList					n_key_launch_escapepod;
	
	oo::PList					n_key_galactic_hyperspace;
	oo::PList					n_key_hyperspace;
	oo::PList					n_key_jumpdrive;
	
	oo::PList					n_key_dump_cargo;
	oo::PList					n_key_rotate_cargo;
	
	oo::PList					n_key_autopilot;
	oo::PList					n_key_autodock;
	
	oo::PList					n_key_snapshot;
	oo::PList					n_key_docking_music;
	
	oo::PList					n_key_advanced_nav_array_next;
	oo::PList					n_key_advanced_nav_array_previous;
	oo::PList					n_key_info_next_system;
	oo::PList					n_key_info_previous_system;
	oo::PList					n_key_map_home;
	oo::PList					n_key_map_end;
	oo::PList					n_key_map_next_system;
	oo::PList					n_key_map_previous_system;
	oo::PList					n_key_map_info;
	oo::PList					n_key_map_zoom_in;
	oo::PList					n_key_map_zoom_out;

	oo::PList					n_key_system_home;
	oo::PList					n_key_system_end;
	oo::PList					n_key_system_next_system;
	oo::PList					n_key_system_previous_system;

	oo::PList					n_key_pausebutton;
	oo::PList					n_key_show_fps;
	oo::PList					n_key_bloom_toggle;
	oo::PList					n_key_mouse_control_roll;
	oo::PList					n_key_mouse_control_yaw;
	oo::PList					n_key_hud_toggle;
	
	oo::PList					n_key_comms_log;
	oo::PList					n_key_prev_compass_mode;
	oo::PList					n_key_next_compass_mode;
	
	oo::PList					n_key_chart_highlight;
	oo::PList					n_key_market_filter_cycle;
	oo::PList					n_key_market_sorter_cycle;
	oo::PList					n_key_market_buy_one;
	oo::PList					n_key_market_sell_one;
	oo::PList					n_key_market_buy_max;
	oo::PList					n_key_market_sell_max;

	oo::PList					n_key_next_target;
	oo::PList					n_key_previous_target;
	
	oo::PList					n_key_custom_view;
	oo::PList					n_key_custom_view_zoom_out;
	oo::PList					n_key_custom_view_zoom_in;
	oo::PList					n_key_custom_view_roll_left;
	oo::PList					n_key_custom_view_pan_left;
	oo::PList					n_key_custom_view_roll_right;
	oo::PList					n_key_custom_view_pan_right;
	oo::PList					n_key_custom_view_rotate_up;
	oo::PList					n_key_custom_view_pan_up;
	oo::PList					n_key_custom_view_rotate_down;
	oo::PList					n_key_custom_view_pan_down;
	oo::PList					n_key_custom_view_rotate_left;
	oo::PList					n_key_custom_view_rotate_right;
	
	oo::PList					n_key_docking_clearance_request;
	oo::PList					n_key_weapons_online_toggle;

	oo::PList					n_key_cycle_next_mfd;
	oo::PList					n_key_cycle_previous_mfd;
	oo::PList					n_key_switch_next_mfd;
	oo::PList					n_key_switch_previous_mfd;

	oo::PList					n_key_oxzmanager_setfilter;
	oo::PList					n_key_oxzmanager_showinfo;
	oo::PList					n_key_oxzmanager_extract;
	
#if OO_FOV_INFLIGHT_CONTROL_ENABLED
	oo::PList					n_key_inc_field_of_view;
	oo::PList					n_key_dec_field_of_view;
#endif
	
#ifndef NDEBUG
	oo::PList					n_key_dump_target_state;
	oo::PList					n_key_dump_entity_list;
	oo::PList					n_key_debug_full;
	oo::PList					n_key_debug_collision;
	oo::PList					n_key_debug_console_connect;
	oo::PList					n_key_debug_bounding_boxes;
	oo::PList					n_key_debug_shaders;
	oo::PList					n_key_debug_off;
#endif

	// dict to hold custom key config for OXP equipment with activate/mode functions
	std::vector<oo::PList>	customEquipActivation;	// Dict entries, edited in place by KeyMapper/StickMapper/Controls
	std::vector<BOOL>		customActivatePressed;	// parallel to customEquipActivation
	std::vector<BOOL>		customModePressed;

	// dict to hold extra keys for missions screen.
	std::map<std::string, oo::PList, std::less<>>	extraMissionKeys;	// key name -> processed key definitions

	std::map<int, std::vector<oo::Ref<::OOJSGuiScreenKeyDefinition>>>	extraGuiScreenKeys;	// by GUI screen ID

	// save-file
	std::optional<std::string>	save_path;
	std::optional<std::string>	scenarioKey;
	
	// position of viewports
	Vector					forwardViewOffset = {}, aftViewOffset = {}, portViewOffset = {}, starboardViewOffset = {};
	Vector					_sysInfoLight = {};
	
	// trumbles
	NSUInteger				trumbleCount = {};
	oo::Ref<OOTrumble>		trumble[PLAYER_MAX_TRUMBLES];
	float					_trumbleAppetiteAccumulator = {};
	
	// smart zoom
	GLfloat					scanner_zoom_rate = {};
	
	// target memory
	// TODO: this should use weakrefs
	std::vector<oo::WeakRef<Entity>>	target_memory;	// an empty ref = an empty slot (was [OONull null]); C++ parts since bead oo-9ht.39.5.2
	NSUInteger				target_memory_index = {};
	
	// custom view points
	Quaternion				customViewQuaternion = {};
	OOMatrix				customViewMatrix = {};
	Vector					customViewOffset = {}, customViewForwardVector = {}, customViewUpVector = {}, customViewRightVector = {}, customViewRotationCenter = {};
	std::optional<std::string>	customViewDescription;
	
	
	// docking reports
	std::string				dockingReport;
	
	// Woo, flags.
	unsigned				suppressTargetLostFlag: 1 = 0,	// the ivar suppressTargetLost: smart target lst reports
							scoopsActive: 1 = 0,			// smart fuelscoops
	
							scoopOverride: 1 = 0,			//scripted to just be on, ignoring normal rules
							game_over: 1 = 0,
							finished: 1 = 0,
							bomb_detonated: 1 = 0,
							autopilot_engaged: 1 = 0,
	
							afterburner_engaged: 1 = 0,
							afterburnerSoundLooping: 1 = 0,
	
							hyperspeed_engaged: 1 = 0,
							travelling_at_hyperspeed: 1 = 0,
							hyperspeed_locked: 1 = 0,
	
							ident_engaged: 1 = 0,
	
							galactic_witchjump: 1 = 0,
	
							ecm_in_operation: 1 = 0,
	
							show_info_flag: 1 = 0,
	
							showDemoShips: 1 = 0,
	
							rolling = {}, pitching = {}, yawing: 1 = 0,
							using_mining_laser: 1 = 0,
	
							mouse_control_on: 1 = 0,
	
							keyboardRollOverride: 1 = 0,   // Handle keyboard roll...
							keyboardPitchOverride: 1 = 0,  // ...and pitch override separately - (fix for BUG #17490)  
							keyboardYawOverride: 1 = 0,
							waitingForStickCallback: 1 = 0,
							
							weapons_online: 1 = 0,
							
							launchingMissile: 1 = 0,
							replacingMissile: 1 = 0,
							
							massLockable: 1 = 0;
#if OOLITE_ESPEAK
	unsigned int			voice_no = {};
	BOOL					voice_gender_m = {};
#endif
	OOSpeechSettings		isSpeechOn = {};


	// For PlayerEntity (StickMapper)
	int						selFunctionIdx = {};
	std::vector<oo::PList>	stickFunctions;	// PlayerEntity (StickMapper)'s function list; empty until built
	std::vector<oo::PList>	keyFunctions;	// PlayerEntity (KeyMapper)'s function list; empty until built
	std::vector<oo::PList>	kbdLayouts;		// PlayerEntity (KeyMapper)'s keyboard layouts; empty until built
	std::string				keyShiftText;
	std::string				keyMod1Text;
	std::string				keyMod2Text;
	
	OOGalacticHyperspaceBehaviour galacticHyperspaceBehaviour = {};
	NSPoint					galacticHyperspaceFixedCoords = {};
	
	OOLongRangeChartMode	longRangeChartMode = {};

	std::vector<oo::PList>	_customViews;	// the ship's custom view Dicts
	NSUInteger				_customViewIndex = {};
	
	OODockingClearanceStatus dockingClearanceStatus = {};
	
	std::vector<oo::EntityHold>	scannedWormholes;	// their objects held (bead oo-9ht.39.18)
	WormholeEntity				*wormhole = {};	// C++ since bead oo-9ht.112; wormholeObject holds it
	oo::EntityHold				wormholeObject;	// the wormhole, held (bead oo-5q11i; oo::EntityHold since bead oo-xn1j1)

	oo::EntityHold	demoShip; // Used while docked to maintain demo ship rotation. (held; bead oo-5q11i; oo::EntityHold since bead oo-xn1j1)
	std::vector<oo::Ref<OOLaserShotEntity>>	lastShot; // used to correctly position laser shots on first frame of firing
	
	oo::Ref<::StickProfileScreen>	stickProfileScreen;

	double					maxFieldOfView = {};
	double					fieldOfView = {};
#if OO_FOV_INFLIGHT_CONTROL_ENABLED
	double					fov_delta = {};
#endif
};


/*	Use PLAYER to refer to the shared player object in cases where it is
	assumed to exist (i.e., except during early initialization).
*/
OOINLINE PlayerEntity *OOGetPlayer(void) INLINE_CONST_FUNC;
OOINLINE PlayerEntity *OOGetPlayer(void)
{
	extern PlayerEntity *gOOPlayer;
#if OO_DEBUG
	OOCAssert(gOOPlayer != nullptr, "PLAYER used when PlayerEntity::sharedPlayer() has not been called.");
#endif
	return gOOPlayer;
}
#define PLAYER				OOGetPlayer()

#define KILOGRAMS_PER_POD		1000
#define MAX_KILOGRAMS_IN_SAFE	((KILOGRAMS_PER_POD / 2) - 1)
#define GRAMS_PER_POD			(KILOGRAMS_PER_POD * 1000)
#define MAX_GRAMS_IN_SAFE		((GRAMS_PER_POD / 2) - 1)


// C++ forms, defined in OOConstToString.mm (bead oo-nts1, chunk oo-3rb.161): std::string results
// (never nil), const std::string & parameters (nil arrived as "" and matched nothing: the defaults).
std::string cxx_OOStringFromGUIScreenID(OOGUIScreenID screen);
OOGUIScreenID cxx_OOGUIScreenIDFromString(const std::string &string);

OOGalacticHyperspaceBehaviour cxx_OOGalacticHyperspaceBehaviourFromString(const std::string &string);
std::string cxx_OOStringFromGalacticHyperspaceBehaviour(OOGalacticHyperspaceBehaviour behaviour);

// Rating and legal-status names from descriptions.plist (chunk oo-3rb.162); nullopt: missing (was nil).
std::optional<std::string> cxx_OODisplayRatingStringFromKillCount(unsigned kills);
std::string cxx_KillCountToRatingAndKillString(unsigned kills);
std::optional<std::string> cxx_OODisplayStringFromLegalStatus(int legalStatus);

