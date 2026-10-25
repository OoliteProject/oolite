/*

Universe.h

Manages a lot of stuff that isn't managed somewhere else.

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
#include "OOOpenGL.h"
#include "OOShaderProgram.h"
#include "legacy_random.h"
#include "OOMaths.h"
#include "OOColor.h"
#include "OOTypes.h"
#include "OOSound.h"
#include "OOJSPropID.h"
#include "OOStellarBody.h"
#include "OOEntityWithDrawable.h"
#include "OOCommodities.h"
#include "OOSystemDescriptionManager.h"
#include "OOCommodityMarket.h"	// C++ since bead oo-9ht.21: the universe keeps its market (oo::Ref)
#include "OOCharacter.h"	// C++ since bead oo-9ht.10: the character pool is oo::Ref
#include "UniverseVirtualMembers.h"	// the test seams (bead oo-ql9rn)

#include "oofnd/StdLib.hpp"
#include "oofnd/PList.hpp"
#include "oofnd/Ref.hpp"

class OOMaterial;

#if OOLITE_ESPEAK
#include <espeak-ng/speak_lib.h>
#include <string_view>
#endif

class Entity;
namespace oo { class Exception; }	// handleOoliteException (was @class OOException, bead oo-rskgl.1)
class GameController;
class MyOpenGLView;
class OOVisualEffectEntity;	// C++ since bead oo-9ht.165
class ShipEntity;	// C++ since bead oo-9ht.144
class DockEntity;
class StationEntity;
class OOWaypointEntity;
class PlayerEntity;
#include "OOScript.h"	// oo::Ref<OOScript> members and results (bead oo-9ht.133)
class WormholeEntity;	// C++ since bead oo-9ht.112
class OOSunEntity;	// C++ since bead oo-9ht.111
class OOPlanetEntity;	// C++ since bead oo-9ht.129
#include "GuiDisplayGen.h"	// C++ since bead oo-9ht.143: the universe keeps its GUIs (oo::Ref)
class CollisionRegion;


typedef BOOL (*EntityFilterPredicate)(Entity *entity, void *parameter);	// the C++ entity since bead oo-9ht.39.23

#ifndef OO_SCANCLASS_TYPE
#define OO_SCANCLASS_TYPE
#ifndef __cplusplus
typedef enum OOScanClass OOScanClass;
#endif
#endif


#define CROSSHAIR_SIZE						32.0

enum
{
	MARKET_NAME							= 0,
	MARKET_QUANTITY						= 1,
	MARKET_PRICE							= 2,
	MARKET_BASE_PRICE						= 3,
	MARKET_ECO_ADJUST_PRICE				= 4,
	MARKET_ECO_ADJUST_QUANTITY  			= 5,
	MARKET_BASE_QUANTITY					= 6,
	MARKET_MASK_PRICE						= 7,
	MARKET_MASK_QUANTITY					= 8,
	MARKET_UNITS							= 9
};


enum
{
	EQUIPMENT_TECH_LEVEL_INDEX				= 0,
	EQUIPMENT_PRICE_INDEX					= 1,
	EQUIPMENT_SHORT_DESC_INDEX				= 2,
	EQUIPMENT_KEY_INDEX					= 3,
	EQUIPMENT_LONG_DESC_INDEX				= 4,
	EQUIPMENT_EXTRA_INFO_INDEX				= 5
};


enum
{
	OO_POSTFX_NONE						= 0,
	OO_POSTFX_COLORBLINDNESS_PROTAN,
	OO_POSTFX_COLORBLINDNESS_DEUTER,
	OO_POSTFX_COLORBLINDNESS_TRITAN,
	OO_POSTFX_CLOAK,
	OO_POSTFX_GRAYSCALE,
	OO_POSTFX_OLDMOVIE,
	OO_POSTFX_CRT,
	OO_POSTFX_CRTBADSIGNAL,
	OO_POSTFX_ENDOFLIST	// keep this for last
};


#define SHADERS_MIN SHADERS_OFF


#define MAX_MESSAGES						5

#define PROXIMITY_WARN_DISTANCE				4 // Eric 2010-10-17: old value was 20.0
#define PROXIMITY_WARN_DISTANCE2			(PROXIMITY_WARN_DISTANCE * PROXIMITY_WARN_DISTANCE)
#define PROXIMITY_AVOID_DISTANCE_FACTOR		10.0
#define SAFE_ADDITION_FACTOR2				800 // Eric 2010-10-17: used to be "2 * PROXIMITY_WARN_DISTANCE2"

#define SUN_SKIM_RADIUS_FACTOR				1.15470053838	// 2 sqrt(3) / 3. Why? I have no idea. -- Ahruman 2009-10-04
#define SUN_SPARKS_RADIUS_FACTOR			2.0

inline constexpr std::string_view KEY_TECHLEVEL						= "techlevel";
inline constexpr std::string_view KEY_ECONOMY							= "economy";
inline constexpr std::string_view KEY_ECONOMY_DESC					= "economy_description";
inline constexpr std::string_view KEY_GOVERNMENT						= "government";
inline constexpr std::string_view KEY_GOVERNMENT_DESC					= "government_description";
inline constexpr std::string_view KEY_POPULATION						= "population";
inline constexpr std::string_view KEY_POPULATION_DESC					= "population_description";
inline constexpr std::string_view KEY_PRODUCTIVITY					= "productivity";
inline constexpr std::string_view KEY_RADIUS							= "radius";
inline constexpr std::string_view KEY_NAME							= "name";
inline constexpr std::string_view KEY_INHABITANT						= "inhabitant";
inline constexpr std::string_view KEY_INHABITANTS						= "inhabitants";
inline constexpr std::string_view KEY_DESCRIPTION						= "description";
inline constexpr std::string_view KEY_SHORT_DESCRIPTION				= "short_description";
inline constexpr std::string_view KEY_PLANETNAME						= "planet_name";
inline constexpr std::string_view KEY_SUNNAME							= "sun_name";

inline constexpr std::string_view KEY_CHANCE							= "chance";
inline constexpr std::string_view KEY_PRICE							= "price";
inline constexpr std::string_view KEY_OPTIONAL_EQUIPMENT				= "optional_equipment";
inline constexpr std::string_view KEY_STANDARD_EQUIPMENT				= "standard_equipment";
inline constexpr std::string_view KEY_EQUIPMENT_MISSILES				= "missiles";
inline constexpr std::string_view KEY_EQUIPMENT_FORWARD_WEAPON		= "forward_weapon_type";
inline constexpr std::string_view KEY_EQUIPMENT_AFT_WEAPON			= "aft_weapon_type";
#define KEY_EQUIPMENT_PORT_WEAPON			"port_weapon_type"
#define KEY_EQUIPMENT_STARBOARD_WEAPON		"starboard_weapon_type"
inline constexpr std::string_view KEY_EQUIPMENT_EXTRAS				= "extras";
inline constexpr std::string_view KEY_WEAPON_FACINGS					= "weapon_facings";
inline constexpr std::string_view KEY_RENOVATION_MULTIPLIER					= "renovation_multiplier";

inline constexpr std::string_view SHIPYARD_KEY_ID						= "id";
inline constexpr std::string_view SHIPYARD_KEY_SHIPDATA_KEY			= "shipdata_key";
inline constexpr std::string_view SHIPYARD_KEY_SHIP					= "ship";
inline constexpr std::string_view SHIPYARD_KEY_PRICE					= "price";
inline constexpr std::string_view SHIPYARD_KEY_PERSONALITY			= "personality";
// default passenger berth required space
#define PASSENGER_BERTH_SPACE				5

inline constexpr std::string_view PLANETINFO_UNIVERSAL_KEY			= "universal";
inline constexpr std::string_view PLANETINFO_INTERSTELLAR_KEY			= "interstellar space";

#define OOLITE_EXCEPTION_LOOPING			"OoliteLoopingException"
#define OOLITE_EXCEPTION_DATA_NOT_FOUND		"OoliteDataNotFoundException"
#define OOLITE_EXCEPTION_FATAL				"OoliteFatalException"

// the distance the sky backdrop is from the camera
// though it appears at infinity
#define BILLBOARD_DEPTH						75000.0

#define TIME_ACCELERATION_FACTOR_MIN		0.0625f
#define TIME_ACCELERATION_FACTOR_DEFAULT	1.0f
#define TIME_ACCELERATION_FACTOR_MAX		16.0f

#define DEMO_LIGHT_POSITION 5000.0f, 25000.0f, -10000.0f

#define MIN_DISTANCE_TO_BUOY			750.0f // don't add ships within this distance
#define MIN_DISTANCE_TO_BUOY2			(MIN_DISTANCE_TO_BUOY * MIN_DISTANCE_TO_BUOY)

// if this is changed, also change oolite-populator.js
// once this number has been in a stable release, cannot easily be changed
#define SYSTEM_REPOPULATION_INTERVAL 20.0f;

#ifndef OO_LOCALIZATION_TOOLS
#define OO_LOCALIZATION_TOOLS	1
#endif

#ifndef MASS_DEPENDENT_FUEL_PRICES
#define MASS_DEPENDENT_FUEL_PRICES	1
#endif




/*	The universe (beads oo-riqmz, oo-pas; the Objective-C facade went with bead oo-ql9rn, ADR-0056
	amendment oo-ql9rn): the old @interface's ivars, by the same names and types, every one
	zero-initialised as the runtime zeroed them, and its methods as member functions. The game's
	one universe is gSharedUniverse, UNIVERSE (below), made by newUniverse() and released by the
	game controller. A message to nil answered zero, so callers that may run without a universe
	(start-up, tests) guard their calls (UNIVERSE != nullptr ? UNIVERSE->m() : zero).
	Objective-C classes are named ::X here where a C++ class of the same name is in namespace cxx.
*/
class Universe : public oo::RefCounted
{
public:
	Universe();
	~Universe();

	/*	[[Universe alloc] initWithGameView:]: the new universe, +1 as +alloc gave (the game
		controller keeps it in gSharedUniverse and releases it). A second universe while one exists
		is released (its teardown runs, as the facade's -dealloc ran) and raises.
	*/
	static Universe *newUniverse(::MyOpenGLView *inGameView);

	// -initWithGameView:'s set-up, after [super init] (slice 1).
	void initWithGameView(::MyOpenGLView *inGameView);
	// -dealloc's body, run by the destructor (it was the facade's -dealloc before it released this part).
	void dealloc();

	// The test seams (ADR-0056 amendment oo-ql9rn item 4): the members a whole-game test's universe
	// overrides, declared once in UniverseVirtualMembers.h so that a narrow test's stand-in has the
	// same vtable. Each is named where it was declared, below.
	OO_UNIVERSE_VIRTUAL_MEMBERS(;, ;)

	// Slice 2: post-processing FX and colour-blind modes, the target framebuffer, start-up flags, add-ons, the entity list.
	bool bloom();
	void setBloom(bool newBloom);
	int currentPostFX();
	void setCurrentPostFX(int newCurrentPostFX);
	void terminatePostFX(int postFX);
	int nextColorblindMode(int index);
	int prevColorblindMode(int index);
	int colorblindMode();
	void initTargetFramebufferWithViewSize(NSSize viewSize);
	void deleteOpenGLObjects();
	void resizeTargetFramebufferWithViewSize(NSSize viewSize);
	void drawTargetTextureIntoDefaultFramebuffer();
	NSUInteger sessionID();
	bool doingStartUp();
	bool getDoProcedurallyTexturedPlanets();
	void setDoProcedurallyTexturedPlanets(bool value);
	std::optional<std::string> getUseAddOns();
	bool setUseAddOns(const std::string &newUse, bool saveGame);
	bool setUseAddOns(const std::string &newUse, bool saveGame, bool force);
	NSUInteger entityCount();
#ifndef NDEBUG
	void debugDumpEntities();
	std::vector<oo::EntityHold> entityList();
#endif

	Universe(const Universe &) = delete;
	Universe &operator=(const Universe &) = delete;

	// Formerly @public.
	// use a sorted list for drawing and other activities
	Entity				*sortedEntities[UNIVERSE_MAX_ENTITIES + 1] = {};	// One extra for padding; see -doRemoveEntity:. The C++ parts, borrowed (bead oo-9ht.39.4): entities owns their objects.
	unsigned				n_entities = 0;

	int						cursor_row = 0;

	// collision optimisation sorted lists
	Entity				*x_list_start = nullptr, *y_list_start = nullptr, *z_list_start = nullptr;	// C++ parts, borrowed (bead oo-9ht.39.4)

	GLfloat					stars_ambient[4] = {};

	// Formerly @private: public while the class is half converted, because the facade's
	// unconverted methods read them (amendment oo-60fwo item 2). Private once Universe is
	// converted (oo-pas).
	NSUInteger				_sessionID = 0;

	// colors
	GLfloat					sun_diffuse[4] = {};
	GLfloat					sun_specular[4] = {};

	OOViewID				viewDirection = {};

	OOMatrix				viewMatrix = {};

	GLfloat					airResistanceFactor = 0;

	::MyOpenGLView			*gameView = nil;

	int						next_universal_id = 0;
	Entity				*entity_for_uid[MAX_ENTITY_UID] = {};	// C++ parts, borrowed (bead oo-9ht.39.4)

	std::vector<oo::EntityHold>	entities;	// owning: each entity's object (bead oo-9ht.39.26)

	oo::WeakRef<Entity>	_firstBeacon,	// the beacons' C++ parts (bead oo-9ht.39.5.2; were their objects' weak references)
							_lastBeacon;
	std::map<std::string, oo::EntityHold, std::less<>>	waypoints;	// by key: the waypoints (their objects held, bead oo-9ht.39.26)

	GLfloat					skyClearColor[4] = {};

	std::optional<std::string>	currentMessage;
	OOTimeAbsolute			messageRepeatTime = 0;
	OOTimeAbsolute			countdown_messageRepeatTime = 0; 	// Getafix(4/Aug/2010) - Quickfix countdown messages colliding with weapon overheat messages.
									//                       For proper handling of message dispatching, code refactoring is needed.
	oo::Ref<GuiDisplayGen>	gui;
	oo::Ref<GuiDisplayGen>	message_gui;
	oo::Ref<GuiDisplayGen>	comm_log_gui;
	// The GUIs setUpSettings() replaced, kept until it replaces them again: they were autoreleased,
	// and a caller may still be using one in the pass that reinitialised the universe (bead oo-9ht.143).
	std::vector<oo::Ref<GuiDisplayGen>>	replacedGuis;
	// The commodities, the system manager and the character pool setUpSettings() and
	// setUpInitialUniverse() replaced, kept until they replace them again: they were autoreleased
	// (beads oo-9ht.25, oo-9ht.32 and oo-9ht.10 deleted their facades).
	oo::Ref<OOCommodities>	replacedCommodities;
	oo::Ref<OOSystemDescriptionManager>	replacedSystemManager;
	std::vector<oo::Ref<OOCharacter>>	replacedCharacterPool;

	BOOL					displayGUI = NO;
	BOOL					wasDisplayGUI = NO;

	BOOL					autoSaveNow = NO;
	BOOL					autoSave = NO;
	BOOL					wireframeGraphics = NO;
	OOGraphicsDetail		detailLevel = {};
// Above entry replaces these two
//	BOOL					reducedDetail;
//	OOShaderSetting			shaderEffectsLevel;

	BOOL					displayFPS = NO;

	OOTimeAbsolute			universal_time = 0;
	OOTimeDelta				time_delta = 0;

	OOTimeAbsolute			demo_stage_time = 0;
	OOTimeAbsolute			demo_start_time = 0;
	GLfloat					demo_start_z = 0;
	int						demo_stage = 0;
	NSUInteger				demo_ship_index = 0;
	NSUInteger				demo_ship_subindex = 0;
	oo::PList				demo_ships;	// arrays (one per class) of demo ship dictionaries

	GLfloat					main_light_position[4] = {};

	BOOL					dumpCollisionInfo = NO;

	oo::Ref<OOCommodities>		commodities;
	oo::Ref<OOCommodityMarket>	commodityMarket;


	oo::PList				_descriptions;			// holds descriptive text for lots of stuff, loaded at initialisation (a dict; null until loaded)
	unsigned				_descriptionsGeneration = 0;	// changes whenever _descriptions is assigned (the bridged -descriptions caches per generation)
	oo::PList				customSounds;			// holds descriptive audio for lots of stuff, loaded at initialisation
	oo::PList				characters;				// holds descriptons of characters
	oo::PList				_scenarios;				// game start scenarios (an array)
	oo::PList				globalSettings;			// miscellaneous global game settings
	oo::Ref<OOSystemDescriptionManager>	systemManager; // planetinfo data manager
	oo::PList				missiontext;			// holds descriptive text for missions, loaded at initialisation
	oo::PList				equipmentData;			// holds data on available equipment, loaded at initialisation (an array)
	oo::PList				equipmentDataOutfitting;
//	std::set<std::string>	pirateVictimRoles;		// Roles listed in pirateVictimRoles.plist.
	oo::PList				roleCategories;			// Categories for roles from role-categories.plist, extending the old pirate-victim-roles.plist (category -> array of roles)
	oo::PList				autoAIMap;				// Default AIs for roles from autoAImap.plist.
	oo::PList				screenBackgrounds;		// holds filenames for various screens backgrounds, loaded at initialisation
	oo::PList				explosionSettings;		// explosion settings from explosions.plist

	std::map<std::string, oo::EntityHold, std::less<>>	cargoPods; // template cargo pods, by commodity key

	OOGalaxyID				galaxyID = 0;
	OOSystemID				systemID = 0;
	OOSystemID				targetSystemID = 0;

	std::optional<std::string>	system_names[256];	// hold pregenerated universe info (nullopt where the name was nil)
	BOOL					system_found[256] = {};		// holds matches for input strings

	int						breakPatternCounter = 0;

	::ShipEntity			*demo_ship = nil;

	::StationEntity			*cachedStation = nil;
	::OOPlanetEntity		*cachedPlanet = nil;
	::OOSunEntity			*cachedSun = nil;
	std::vector<oo::EntityHold>	allPlanets;	// the planets (their objects held, bead oo-9ht.39.26)
	std::vector<oo::EntityHold>	allStations;	// the stations (their objects held, bead oo-9ht.39.26), each once, in the order added

	float					ambientLightLevel = 0;

	oo::PList				populatorSettings;	// key -> populator block (a mixed configuration: each block's callbackObj is an Object node)
	OOTimeDelta		next_repopulation = 0;
	std::optional<std::string>	system_repopulator;
	BOOL			deterministic_population = NO;

	std::optional<std::vector<OOSystemID>>	closeSystems;	// the current system's neighbours; nullopt until cached

	std::string				useAddOns;

	BOOL					no_update = NO;

#ifndef NDEBUG
	double					timeAccelerationFactor = 0;
#endif

	BOOL					ECMVisualFXEnabled = NO;

	std::vector<oo::EntityHold>	activeWormholes;

	std::vector<oo::Ref<OOCharacter>>	characterPool;

	oo::Ref<::CollisionRegion>	universeRegion;

	// check and maintain linked lists occasionally
	BOOL					doLinkedListMaintenanceThisUpdate = NO;

	std::vector<oo::EntityHold>	entitiesDeadThisUpdate;	// each once, in the order removed
	int						framesDoneThisUpdate = 0;
	NSUInteger				drawCounter = 0;

#if OOLITE_SPEECH_SYNTH
#if OOLITE_MAC_OS_X
	NSSpeechSynthesizer		*speechSynthesizer = nil;
#elif OOLITE_ESPEAK
	const espeak_VOICE		**espeak_voices = nullptr;
	unsigned int			espeak_voice_count = 0;
#endif
	oo::PList				speechArray;	// [original, replacement(, espeak replacement)] pairs
#endif

	std::vector<oo::Ref<::OOMaterial>>		_preloadingPlanetMaterials;
	BOOL					doProcedurallyTexturedPlanets = NO;

	GLfloat					frustum[6][4] = {};

	std::map<std::string, oo::Ref<OOScript>, std::less<>>	conditionScripts;

	BOOL					_pauseMessage = NO;
	BOOL					_autoCommLog = NO;
	BOOL					_permanentCommLog = NO;
	BOOL					_autoMessageLogBg = NO;
	BOOL					_permanentMessageLog = NO;
	BOOL					_witchspaceBreakPattern = NO;
	BOOL					_dockingClearanceProtocolActive = NO;
	BOOL					_doingStartUp = NO;

	GLuint					msaaTextureID = 0;
	GLuint					targetTextureID = 0;
	GLuint					passthroughTextureID[2] = {};
	NSSize					targetFramebufferSize = {};
	GLuint					msaaFramebufferID = 0;
	GLuint					msaaDepthBufferID = 0;
	GLuint					targetDepthBufferID = 0;
	GLuint					targetFramebufferID = 0;
	GLuint					passthroughFramebufferID = 0;
	oo::Ref<OOShaderProgram>	textureProgram = {};
	oo::Ref<OOShaderProgram>	blurProgram = {};
	oo::Ref<OOShaderProgram>	finalProgram = {};
	GLuint 					quadTextureVBO = 0, quadTextureVAO = 0, quadTextureEBO = 0;
	GLint 					defaultDrawFBO = 0;
	GLuint					pingpongFBO[2] = {};
    GLuint					pingpongColorbuffers[2] = {};
	BOOL					_bloom = NO;
	int					_currentPostFX = 0;
	int					_colorblindMode = 0;

	// Slice 3: pause and quit, carrying the player on, set-up from station / witchspace / misjump, witchspace and planet set-up.
	void pauseGame();
	void quitGame();
	void carryPlayerOn(::StationEntity *carrier, ::WormholeEntity *wormhole);
	void setUpUniverseFromStation();
	void setUpUniverseFromWitchspace();
	void setUpUniverseFromMisjump();
	void setUpWitchspace();
	void setUpWitchspaceBetweenSystem(OOSystemID s1, OOSystemID s2);
	::OOPlanetEntity *setUpPlanet();

	// Slice 4: setUpSpace, populating normal space, the system populator.
	void setUpSpace();
	void populateNormalSpace();
	void clearSystemPopulator();
	// getPopulatorSettings(): virtual, in OO_UNIVERSE_VIRTUAL_MEMBERS (UniverseVirtualMembers.h)
	// setPopulatorSetting(): virtual, in OO_UNIVERSE_VIRTUAL_MEMBERS (UniverseVirtualMembers.h)
	bool deterministicPopulation();
	void populateSystemFromDictionariesWithSun(::OOSunEntity *sun, ::OOPlanetEntity *planet);

	// Slice 5: locations by code, lighting, adding ships by role, coordinate systems.
	// locationByCode(): virtual, in OO_UNIVERSE_VIRTUAL_MEMBERS (UniverseVirtualMembers.h)
	// setAmbientLightLevel(): virtual, in OO_UNIVERSE_VIRTUAL_MEMBERS (UniverseVirtualMembers.h)
	// getAmbientLightLevel(): virtual, in OO_UNIVERSE_VIRTUAL_MEMBERS (UniverseVirtualMembers.h)
	// setLighting(): virtual, in OO_UNIVERSE_VIRTUAL_MEMBERS (UniverseVirtualMembers.h)
	void forceLightSwitch();
	// setMainLightPosition(): virtual, in OO_UNIVERSE_VIRTUAL_MEMBERS (UniverseVirtualMembers.h)
	::ShipEntity *addShipWithRole(const std::string &desc, HPVector launchPos, GLfloat rfactor);
	// addShipWithRole(): virtual, in OO_UNIVERSE_VIRTUAL_MEMBERS (UniverseVirtualMembers.h)
	HPVector coordinatesForPosition(HPVector pos, const std::string &system, GLfloat *my_scalar);
	std::optional<std::string> expressPosition(HPVector pos, const std::string &system);

	// Slice 6: legacy positions, adding ships at / near positions and in boxes, spawning, visual effects.
	HPVector legacyPositionFrom(HPVector pos, const std::string &system);
	HPVector coordinatesFromCoordinateSystemString(const std::string &system_x_y_z);
	bool addShipWithRole(const std::string &desc, HPVector pos, const std::string &system);
	bool addShipsAtPosition(int howMany, const std::string &desc, HPVector pos, const std::string &system);
	bool addShipsNearPosition(int howMany, const std::string &desc, HPVector pos, const std::string &system);
	bool addShipsNearPosition(int howMany, const std::string &desc, HPVector pos, const std::string &system, GLfloat radius);
	bool addShips(int howMany, const std::string &desc, BoundingBox bbox);
	// spawnShip(): virtual, in OO_UNIVERSE_VIRTUAL_MEMBERS (UniverseVirtualMembers.h)
	// witchspaceShipWithPrimaryRole(): virtual, in OO_UNIVERSE_VIRTUAL_MEMBERS (UniverseVirtualMembers.h)
	::ShipEntity *spawnShipWithRole(const std::string &desc, Entity *entity);	// the C++ entity since bead oo-9ht.39.23
	// addVisualEffectAt(): virtual, in OO_UNIVERSE_VIRTUAL_MEMBERS (UniverseVirtualMembers.h)	// the effect's object (bead oo-9ht.165)

	// Slice 7: adding ships within a radius and on routes, role categories, witchspace entries and effects, break patterns, the docking clearance protocol, game over.
	::ShipEntity *addShipAt(HPVector pos, const std::string &role, GLfloat radius);
	// addShipsAt(): virtual, in OO_UNIVERSE_VIRTUAL_MEMBERS (UniverseVirtualMembers.h)
	// addShipsToRoute(): virtual, in OO_UNIVERSE_VIRTUAL_MEMBERS (UniverseVirtualMembers.h)
	bool roleIsPirateVictim(const std::string &role);
	// role(): virtual, in OO_UNIVERSE_VIRTUAL_MEMBERS (UniverseVirtualMembers.h)
	void forceWitchspaceEntries();
	void addWitchspaceJumpEffectForShip(::ShipEntity *ship);
	GLfloat safeWitchspaceExitDistance();
	void setUpBreakPattern(HPVector pos, Quaternion q, bool forDocking);
	// witchspaceBreakPattern(): virtual, in OO_UNIVERSE_VIRTUAL_MEMBERS (UniverseVirtualMembers.h)
	// setWitchspaceBreakPattern(): virtual, in OO_UNIVERSE_VIRTUAL_MEMBERS (UniverseVirtualMembers.h)
	bool dockingClearanceProtocolActive();
	void setDockingClearanceProtocolActive(bool newValue);
	void handleGameOver();

	// Slice 8: the intro and demo ships, the ship library text, station and planet look-ups.
	void setupIntroFirstGo(bool justCobra);
	oo::PList demoShipData();
	void setLibraryTextForDemoShip();
	void selectIntro2Previous();
	void selectIntro2PreviousCategory();
	void selectIntro2NextCategory();
	void selectIntro2Next();
	// station(): virtual, in OO_UNIVERSE_VIRTUAL_MEMBERS (UniverseVirtualMembers.h)
	::StationEntity *stationWithRole(const std::string &role, HPVector position);
	::StationEntity *stationFriendlyTo(::ShipEntity *ship);
	// planet(): virtual, in OO_UNIVERSE_VIRTUAL_MEMBERS (UniverseVirtualMembers.h)
	// sun(): virtual, in OO_UNIVERSE_VIRTUAL_MEMBERS (UniverseVirtualMembers.h)
	// planets(): virtual, in OO_UNIVERSE_VIRTUAL_MEMBERS (UniverseVirtualMembers.h)	// the planets' Objective-C objects
	// stations(): virtual, in OO_UNIVERSE_VIRTUAL_MEMBERS (UniverseVirtualMembers.h)

	// Slice 9: wormholes, the main station, beacons, waypoints, sky colour, the break pattern, making ships by role and name, default AIs, cargo capacity.
	// wormholes(): virtual, in OO_UNIVERSE_VIRTUAL_MEMBERS (UniverseVirtualMembers.h)
	// unMagicMainStation(): virtual, in OO_UNIVERSE_VIRTUAL_MEMBERS (UniverseVirtualMembers.h)
	void resetBeacons();
	Entity *firstBeacon();	// the C++ entities (bead oo-9ht.39.26)
	void setFirstBeacon(Entity *beacon);
	Entity *lastBeacon();
	void setLastBeacon(Entity *beacon);
	// setNextBeacon(): virtual, in OO_UNIVERSE_VIRTUAL_MEMBERS (UniverseVirtualMembers.h)
	// clearBeacon(): virtual, in OO_UNIVERSE_VIRTUAL_MEMBERS (UniverseVirtualMembers.h)
	// currentWaypoints(): virtual, in OO_UNIVERSE_VIRTUAL_MEMBERS (UniverseVirtualMembers.h)
	// defineWaypoint(): virtual, in OO_UNIVERSE_VIRTUAL_MEMBERS (UniverseVirtualMembers.h)
	GLfloat *getSkyClearColor();
	// setSkyColorRed(): virtual, in OO_UNIVERSE_VIRTUAL_MEMBERS (UniverseVirtualMembers.h)
	bool breakPatternOver();
	bool breakPatternHide();
	bool canInstantiateShip(const std::string &shipKey);
	std::optional<std::string> randomShipKeyForRoleRespectingConditions(const std::string &role);
	::ShipEntity *newShipWithRole(const std::string &role);
	// newVisualEffectWithName(): virtual, in OO_UNIVERSE_VIRTUAL_MEMBERS (UniverseVirtualMembers.h); the effect's object, +1 (bead oo-9ht.165)
	::ShipEntity *newSubentityWithName(const std::string &shipKey, float scale);
	::ShipEntity *newShipWithName(const std::string &shipKey, bool usePlayerProxy);
	::ShipEntity *newShipWithName(const std::string &shipKey, bool usePlayerProxy, bool isSubentity);
	::ShipEntity *newShipWithName(const std::string &shipKey, bool usePlayerProxy, bool isSubentity, float scale);	// its object +1 (a C++ ship since bead oo-9ht.144), as -newShipWithName:... was (the proxy is made in C++ since bead oo-9ht.183)
	::ShipEntity *newDockWithName(const std::string &shipDataKey, float scale);	// the dock, its object +1 (a C++ ship since bead oo-9ht.144)
	::ShipEntity *newShipWithName(const std::string &shipKey);
	bool isStationShipDictionary(const oo::PList &dict);	// -shipClassForShipDictionary: picked StationEntity until bead oo-9ht.175
	std::optional<std::string> defaultAIForRole(const std::string &role);
	OOCargoQuantity maxCargoForShip(const std::string &desc);

	// Slice 10: equipment prices, commodities and cargo pods, the game view and controller, settings, entity lighting, the active view matrix.
	OOCreditsQuantity getEquipmentPriceForKey(const std::string &eq_key);
	::OOCommodities *getCommodities();
	::ShipEntity *reifyCargoPod(::ShipEntity *cargoObj);
	::ShipEntity *cargoPodFromTemplate(::ShipEntity *cargoObj);
	std::vector<oo::EntityHold> getContainersOfGoods(OOCargoQuantity how_many, bool scarce, bool legal);
	// getContainersOfCommodity(): virtual, in OO_UNIVERSE_VIRTUAL_MEMBERS (UniverseVirtualMembers.h)
	void fillCargopodWithRandomCargo(::ShipEntity *cargopod);
	std::string getRandomCommodity();
	OOCargoQuantity getRandomAmountOfCommodity(const std::string &co_type);
	oo::PList commodityDataForType(const std::string &type);
	std::optional<std::string> displayNameForCommodity(const std::string &co_type);
	std::optional<std::string> describeCommodity(const std::string &co_type, OOCargoQuantity co_amount);
	void setGameView(::MyOpenGLView *view);
	// getGameView(): virtual, in OO_UNIVERSE_VIRTUAL_MEMBERS (UniverseVirtualMembers.h)
	::GameController *gameController();
	oo::PList gameSettings();
	void useGUILightSource(bool GUILight);
	void lightForEntity(bool isLit);
	void getActiveViewMatrix(OOMatrix *outMatrix, Vector *outForward, Vector *outUp);
	OOMatrix activeViewMatrix();

	// Slice 11: the view frustum.
	void defineFrustum();
	bool viewFrustumIntersectsSphereAt(Vector position, GLfloat radius);

	// Slice 12: drawUniverse, framebuffer preparation, frame counters, the view matrix.
	void drawUniverse();
	void prepareToRenderIntoDefaultFramebuffer();
	int getFramesDoneThisUpdate();
	void resetFramesDoneThisUpdate();
	OOMatrix getViewMatrix();

	// Slice 13: messages and the watermark, entity look-up, the linked lists, adding and removing entities, demo ships.
	void drawMessage();
	void drawWatermarkString(const std::string &watermarkString);
	Entity *entityForUniversalID(OOUniversalID u_id);
	// addEntity(): virtual, in OO_UNIVERSE_VIRTUAL_MEMBERS (UniverseVirtualMembers.h)
	// removeEntity(): virtual, in OO_UNIVERSE_VIRTUAL_MEMBERS (UniverseVirtualMembers.h)
	void ensureEntityReallyRemoved(Entity *entity);
	void removeAllEntitiesExceptPlayer();
	void removeDemoShips();

	// Slice 14: making demo ships, safe vectors, hazards on route, wreckage, laser hits.
	::ShipEntity *makeDemoShipWithRole(const std::string &role, bool spinning);
	bool isVectorClearFromEntity(Entity *e1, double dist, HPVector p2);
	// hazardOnRouteFromEntity(): virtual, in OO_UNIVERSE_VIRTUAL_MEMBERS (UniverseVirtualMembers.h)
	// getSafeVectorFromEntity(): virtual, in OO_UNIVERSE_VIRTUAL_MEMBERS (UniverseVirtualMembers.h)
	::ShipEntity *addWreckageFrom(::ShipEntity *ship, const std::string &wreckRole, HPVector rpos, GLfloat scale, GLfloat lifetime);
	void addLaserHitEffectsAt(HPVector pos, ::ShipEntity *target, float damage, ::OOColor *color);
	::ShipEntity *firstShipHitByLaserFromShip(::ShipEntity *srcEntity, OOWeaponFacing direction, Vector offset, GLfloat *range_ptr);

	// Slice 15: player targeting, entities in range, counting and finding ships by role and predicate, time, collisions, view direction.
	Entity *firstEntityTargetedByPlayer();
	Entity *firstEntityTargetedByPlayerPrecisely();
	std::vector<oo::EntityHold> entitiesWithinRange(double range, Entity *entity);
	// countShipsWithRole(): virtual, in OO_UNIVERSE_VIRTUAL_MEMBERS (UniverseVirtualMembers.h)
	unsigned countShipsWithRole(const std::string &role);
	// countShipsWithPrimaryRole(): virtual, in OO_UNIVERSE_VIRTUAL_MEMBERS (UniverseVirtualMembers.h)
	// countShipsWithScanClass(): virtual, in OO_UNIVERSE_VIRTUAL_MEMBERS (UniverseVirtualMembers.h)
	unsigned countShipsWithPrimaryRole(const std::string &role);
	unsigned countEntitiesMatchingPredicate(EntityFilterPredicate predicate, void *parameter, double range, Entity *e1);
	unsigned countShipsMatchingPredicate(EntityFilterPredicate predicate, void *parameter, double range, Entity *entity);
	// findEntitiesMatchingPredicate(): virtual, in OO_UNIVERSE_VIRTUAL_MEMBERS (UniverseVirtualMembers.h)
	Entity *findOneEntityMatchingPredicate(EntityFilterPredicate predicate, void *parameter);
	// findShipsMatchingPredicate(): virtual, in OO_UNIVERSE_VIRTUAL_MEMBERS (UniverseVirtualMembers.h)
	// findVisualEffectsMatchingPredicate(): virtual, in OO_UNIVERSE_VIRTUAL_MEMBERS (UniverseVirtualMembers.h)
	Entity *nearestEntityMatchingPredicate(EntityFilterPredicate predicate, void *parameter, Entity *entity);
	Entity *nearestShipMatchingPredicate(EntityFilterPredicate predicate, void *parameter, Entity *entity);
	OOTimeAbsolute getTime();
	OOTimeDelta getTimeDelta();
	void findCollisionsAndShadows();
	std::string collisionDescription();
	void dumpCollisions();
	// getViewDirection(): virtual, in OO_UNIVERSE_VIRTUAL_MEMBERS (UniverseVirtualMembers.h)

	// Slice 16: setting the view direction, GUI view mode, custom sounds, screen textures, messages and comms, delayed messages, repopulating.
	void setViewDirection(OOViewID vd);
	void enterGUIViewModeWithMouseInteraction(bool mouseInteraction);
	std::optional<std::string> soundNameForCustomSoundKey(const std::string &soundKey);
	oo::PList screenTextureDescriptorForKey(const std::string &key);
	void setScreenTextureDescriptorForKey(const std::string &key, const oo::PList &desc);
	void clearPreviousMessage();
	void setMessageGuiBackgroundColor(::OOColor *some_color);
	void displayMessage(const std::optional<std::string> &text, OOTimeDelta count);
	void displayCountdownMessage(const std::optional<std::string> &text, OOTimeDelta count);
	void addDelayedMessage(const std::optional<std::string> &text, OOTimeDelta count, double delay);
	void addDelayedMessage(const oo::PList &message);	// the deferred call's delivery (bead oo-pvhrh; the holder OOUniverseDelayedMessage's -deliverToUniverse before)
	// addMessage(): virtual, in OO_UNIVERSE_VIRTUAL_MEMBERS (UniverseVirtualMembers.h)
	void speakWithSubstitutions(const std::optional<std::string> &text);
	void addMessage(const std::optional<std::string> &text, OOTimeDelta count, bool forceDisplay);
	void addCommsMessage(const std::optional<std::string> &text, OOTimeDelta count);
	void addCommsMessage(const std::optional<std::string> &text, OOTimeDelta count, bool showComms, bool logOnly);
	void showCommsLog(OOTimeDelta how_long);
	void showGUIMessage(const std::optional<std::string> &text, bool scroll, ::OOColor *selectedColor, OOTimeDelta how_long);
	void repopulateSystem();

	// Slice 17: update:, time acceleration, ECM visual effects.
	void update(OOTimeDelta inDeltaT);
	bool getECMVisualFXEnabled();
	void setECMVisualFXEnabled(bool isEnabled);
	double getTimeAccelerationFactor();
	void setTimeAccelerationFactor(double newTimeAccelerationFactor);

	// Slice 18: filterSortedLists, setGalaxyTo:.
	void filterSortedLists();
	void setGalaxyTo(OOGalaxyID g);

	// Slice 19: galaxy and system changes, descriptions, scenarios, characters, mission text, system data and names, finding systems.
	void setGalaxyTo(OOGalaxyID g, bool forced);
	void setSystemTo(OOSystemID s);
	OOSystemID currentSystemID();
	// descriptions(): virtual, in OO_UNIVERSE_VIRTUAL_MEMBERS (UniverseVirtualMembers.h)
	unsigned descriptionsGeneration();
	void verifyDescriptions();
	void loadDescriptions();
	oo::PList explosionSetting(const std::string &explosion);
	oo::PList scenarios();
	void loadScenarios();
	oo::PList getCharacters();
	oo::PList getMissiontext();
	// descriptionForKey(): virtual, in OO_UNIVERSE_VIRTUAL_MEMBERS (UniverseVirtualMembers.h)
	std::optional<std::string> descriptionForArrayKey(const std::string &key, unsigned index);
	bool descriptionBooleanForKey(const std::string &key);
	// getSystemManager(): virtual, in OO_UNIVERSE_VIRTUAL_MEMBERS (UniverseVirtualMembers.h)
	std::optional<std::string> keyForPlanetOverridesForSystem(OOSystemID s, OOGalaxyID g);
	std::optional<std::string> keyForInterstellarOverridesForSystems(OOSystemID s1, OOSystemID s2, OOGalaxyID g);
	oo::PList generateSystemData(OOSystemID s);
	// generateSystemData(s, useCache): virtual, in OO_UNIVERSE_VIRTUAL_MEMBERS (UniverseVirtualMembers.h)
	// currentSystemData(): virtual, in OO_UNIVERSE_VIRTUAL_MEMBERS (UniverseVirtualMembers.h)
	// inInterstellarSpace(): virtual, in OO_UNIVERSE_VIRTUAL_MEMBERS (UniverseVirtualMembers.h)
	// setSystemDataKey(): virtual, in OO_UNIVERSE_VIRTUAL_MEMBERS (UniverseVirtualMembers.h)
	// setSystemDataForGalaxy(): virtual, in OO_UNIVERSE_VIRTUAL_MEMBERS (UniverseVirtualMembers.h)
	oo::PList generateSystemDataForGalaxy(OOGalaxyID gnum, OOSystemID pnum);
	std::vector<std::string> systemDataKeysForGalaxy(OOGalaxyID gnum, OOSystemID pnum);
	oo::PList systemDataForGalaxy(OOGalaxyID gnum, OOSystemID pnum, const std::string &key);
	std::optional<std::string> getSystemName(OOSystemID sys);
	// getSystemName(sys, gnum): virtual, in OO_UNIVERSE_VIRTUAL_MEMBERS (UniverseVirtualMembers.h)
	OOGovernmentID getSystemGovernment(OOSystemID sys);
	std::optional<std::string> getSystemInhabitants(OOSystemID sys);
	std::optional<std::string> getSystemInhabitants(OOSystemID sys, bool plural);
	NSPoint coordinatesForSystem(OOSystemID s);
	// findSystemFromName(): virtual, in OO_UNIVERSE_VIRTUAL_MEMBERS (UniverseVirtualMembers.h)
	OOSystemID findSystemAtCoords(NSPoint coords, OOGalaxyID g);

	// Slice 20: neighbouring systems, system-name look-up, routes (with RouteElement), planet textures, global and equipment data, the commodity market, time descriptions.
	oo::PList nearbyDestinationsWithinRange(double range);
	OOSystemID findNeighbouringSystemToCoords(NSPoint coords, OOGalaxyID g);
	OOSystemID findConnectedSystemAtCoords(NSPoint coords, OOGalaxyID g);
	OOSystemID findSystemNumberAtCoords(NSPoint coords, OOGalaxyID g, bool hidden);
	NSPoint findSystemCoordinatesWithPrefix(const std::string &p_fix);
	NSPoint findSystemCoordinatesWithPrefix(const std::string &p_fix, bool exactMatch);
	BOOL *systemsFound();
	std::optional<std::string> systemNameIndex(OOSystemID index);
	oo::PList routeFromSystem(OOSystemID start, OOSystemID goal, OORouteType optimizeBy);
	std::vector<OOSystemID> neighboursToSystem(OOSystemID s);
	void preloadPlanetTexturesForSystem(OOSystemID /*s*/);
	oo::PList getGlobalSettings();
	oo::PList getEquipmentData();
	oo::PList getEquipmentDataOutfitting();
	::OOCommodityMarket *getCommodityMarket();
	std::optional<std::string> timeDescription(double interval);

	// Slice 21: short time descriptions, sun skimmers, station markets.
	std::optional<std::string> shortTimeDescription(double interval);
	void makeSunSkimmer(::ShipEntity *ship, bool setAI);
	Random_Seed marketSeed();
	void loadStationMarkets(const oo::PList &marketData);
	oo::PList getStationMarkets();

	// Slice 22: ships for sale (cxx_shipsForSaleForSystem:withTL:atTime:).
	oo::PList shipsForSaleForSystem(OOSystemID s, OOTechLevelID specialTL, OOTimeAbsolute current_time);

	// Slice 23: trade-in value, brochure descriptions, witchspace exit and sun-skim positions, beacons by code, script events to all ships, the GUIs, FPS and autosave.
	// tradeInValueForCommanderDictionary(): virtual, in OO_UNIVERSE_VIRTUAL_MEMBERS (UniverseVirtualMembers.h)
	std::optional<std::string> brochureDescriptionWithDictionary(const oo::PList &dict, const std::vector<std::string> &extras, const std::vector<std::string> &options);
	// getWitchspaceExitPosition(): virtual, in OO_UNIVERSE_VIRTUAL_MEMBERS (UniverseVirtualMembers.h)
	Quaternion getWitchspaceExitRotation();
	HPVector getSunSkimStartPositionForShip(::ShipEntity *ship);
	HPVector getSunSkimEndPositionForShip(::ShipEntity *ship);
	std::vector<oo::EntityHold> listBeaconsWithCode(const std::string &code);
	void allShipsDoScriptEvent(ooscript::PropertyId event, const std::optional<std::string> &message);
	// getGui(): virtual, in OO_UNIVERSE_VIRTUAL_MEMBERS (UniverseVirtualMembers.h)
	::GuiDisplayGen *commLogGUI();
	// messageGUI(): virtual, in OO_UNIVERSE_VIRTUAL_MEMBERS (UniverseVirtualMembers.h)
	void clearGUIs();
	void resetCommsLogColor();
	void setDisplayText(bool value);
	bool getDisplayGUI();
	void setDisplayFPS(bool value);
	bool getDisplayFPS();
	void setAutoSave(bool value);
	bool getAutoSave();
	void setAutoSaveNow(bool value);

	// Slice 24: autosave, wireframe and detail levels, shaders, exceptions, air resistance, speech (eSpeak and none), message logs, settings, cargo pods, session IDs.
	bool getAutoSaveNow();
	void setWireframeGraphics(bool value);
	bool getWireframeGraphics();
	// reducedDetail(): virtual, in OO_UNIVERSE_VIRTUAL_MEMBERS (UniverseVirtualMembers.h)
	void setDetailLevelDirectly(OOGraphicsDetail value);
	void setDetailLevel(OOGraphicsDetail value);
	OOGraphicsDetail getDetailLevel();
	bool useShaders();
	void handleOoliteException(const oo::Exception *exception);	// was ::OOException * (bead oo-rskgl.1)
	GLfloat getAirResistanceFactor();
	void setAirResistanceFactor(GLfloat newFactor);
	bool pauseMessageVisible();
	void setPauseMessageVisible(bool value);
	bool permanentMessageLog();
	void setPermanentMessageLog(bool value);
	bool autoMessageLogBg();
	void setAutoMessageLogBg(bool value);
	bool permanentCommLog();
	void setPermanentCommLog(bool value);
	void setAutoCommLog(bool value);
	bool blockJSPlayerShipProps();
	void setBlockJSPlayerShipProps(bool value);
	void setUpSettings();
	void setUpCargoPods();
	void verifyEntitySessionIDs();
#if 1	// every platform's arm is a member since the facade went (bead oo-ql9rn); the Mac's is not built (docs/phases/3-slices/Universe.md "mac-only")
	void startSpeakingString(const std::string &text);
	void stopSpeaking();
	bool isSpeaking();
#endif
#if OOLITE_ESPEAK
	std::optional<std::string> voiceName(unsigned int index);
	unsigned int voiceNumber(const std::string &name);
	unsigned int nextVoice(unsigned int index);
	unsigned int prevVoice(unsigned int index);
	unsigned int setVoice(unsigned int index, bool isMale);
#endif

	// Slice 25: reinitialising and the demo, the initial universe, random positions, removing entities, preloading sounds, wormhole population, graph dumps.
	// reinitAndShowDemo(): virtual, in OO_UNIVERSE_VIRTUAL_MEMBERS (UniverseVirtualMembers.h)
	void setUpInitialUniverse();
	float randomDistanceWithinScanner();
	Vector randomPlaceWithinScannerFrom(Vector pos, Vector route, double offset);
	HPVector fractionalPositionFrom(HPVector point0, HPVector point1, double routeFraction);
	bool doRemoveEntity(Entity *entity);
	void preloadSounds();
	void populateSpaceFromActiveWormholes();
	std::optional<std::string> chooseStringForKey(const std::string &key, const oo::PList &dictionary);
#if OO_LOCALIZATION_TOOLS && DEBUG_GRAPHVIZ
	void dumpDebugGraphViz();
	void dumpSystemDescriptionGraphViz();
#endif

	// Slice 26: graph-viz references, localisation tools, planet-material pruning, condition scripts, the custom-sound categories of OOSound and OOSoundSource, description look-ups.
#if OO_LOCALIZATION_TOOLS
	void addNumericRefsInString(const std::string &string, std::string &graphViz, const std::string &fromNode, NSUInteger nodeCount);
	void runLocalizationTools();
#endif
	void prunePreloadingPlanetMaterials();
	void loadConditionScripts();
	void addConditionScripts(const std::vector<std::string> &scripts);
	::OOScript *getConditionScript(const std::string &scriptname);
};


/*	Use UNIVERSE to refer to the global universe object.
	The purpose of this is that it makes UNIVERSE essentially a read-only
	global with zero overhead.
*/
OOINLINE Universe *OOGetUniverse(void) INLINE_CONST_FUNC;
OOINLINE Universe *OOGetUniverse(void)
{
	extern Universe *gSharedUniverse;
	return gSharedUniverse;
}
#define UNIVERSE OOGetUniverse()


// Only for use with string literals, and only for looking up strings: the description, or the
// key itself when there is none (proposed ADR-0053). OO_DESC() is deprecated in favour of
// cxx_OOExpandKey() except in known performance-critical contexts.
#define OO_DESC(key)	(cxx_OOLookUpDescriptionPRIV(key ""))
#define OO_DESC_PLURAL(key,count)	(cxx_OOLookUpPluralDescriptionPRIV(key "", count))

// Not for direct use.
// The lookups behind OO_DESC() / OO_DESC_PLURAL(): the description, or the key itself when there is none.
std::string cxx_OOLookUpDescriptionPRIV(const std::string &key);
std::string cxx_OOLookUpPluralDescriptionPRIV(const std::string &key, NSInteger count);

/*	The bodies of the custom-sound categories of OOSound and OOSoundSource (slice 26), which went
	with the two facades (beads oo-9ht.68 and oo-9ht.88): the sound for a customsounds.plist key
	(borrowed: the resource manager's cache keeps it; null for none), and playing it on a source
	(nothing for a null source, as a message to nil did).
*/
::OOSound *OOSoundWithCustomSoundKey(const std::string &key);
void OOSoundSourcePlayCustomSoundWithKey(::OOSoundSource *source, const std::string &key);


#ifdef __cplusplus
#include "oofnd/StdLib.hpp"

// C++ forms, defined in OOConstToString.mm (bead oo-nts1, chunk oo-3rb.162): nullopt where the
// old Foundation forms gave nil.
std::optional<std::string> cxx_OODisplayStringFromGovernmentID(OOGovernmentID government);
std::optional<std::string> cxx_OODisplayStringFromEconomyID(OOEconomyID economy);
#endif


/*	The look-ups behind the description and custom-sound keys (slice 26): a call to the universe
	when there is one, else what the message to nil answered. Inline, so a test that stands in for
	the universe with a class of its own defines only the members it answers (amendment oo-rmd7
	item 3; ADR-0056 amendments oo-7jhs5 and oo-ql9rn).
*/
inline std::optional<std::string> OOUniverseDescriptionForKey(const std::string &key)	{ return UNIVERSE != nullptr ? UNIVERSE->descriptionForKey(key) : std::nullopt; }
inline const oo::PList *OOUniverseDescriptions()	{ return UNIVERSE != nullptr ? UNIVERSE->descriptions() : nullptr; }
inline std::optional<std::string> OOUniverseSoundNameForCustomSoundKey(const std::string &key)	{ return UNIVERSE != nullptr ? UNIVERSE->soundNameForCustomSoundKey(key) : std::nullopt; }
