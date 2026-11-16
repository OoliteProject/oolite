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

#import "OOColor.h"
#import "OOCommodities.h"
#import "OOEntityWithDrawable.h"
#import "OOFoundation.h"
#import "OOJSPropID.h"
#import "OOMaths.h"
#import "OOOpenGL.h"
#import "OOShaderProgram.h"
#import "OOSound.h"
#import "OOStellarBody.h"
#import "OOSystemDescriptionManager.h"
#import "OOTypes.h"
#import "OOWeakReference.h"
#import "legacy_random.h"

#include "oofnd/PList.hpp"
#include "oofnd/StdLib.hpp"
#include "oofnd/objc/OOObjCRef.h"

@class OOMaterial;

#if OOLITE_ESPEAK
#include <espeak-ng/speak_lib.h>
#include <string_view>
#endif

@class GameController, CollisionRegion, MyOpenGLView, GuiDisplayGen,
    Entity, ShipEntity, StationEntity, OOPlanetEntity, OOSunEntity,
    OOVisualEffectEntity, PlayerEntity, OORoleSet, WormholeEntity,
    DockEntity, OOJSScript, OOWaypointEntity, OOSystemDescriptionManager,
    OOException, OOCharacter;

typedef BOOL (*EntityFilterPredicate)(Entity* entity, void* parameter);

#ifndef OO_SCANCLASS_TYPE
#define OO_SCANCLASS_TYPE
#ifndef __cplusplus
typedef enum OOScanClass OOScanClass;
#endif
#endif

#define CROSSHAIR_SIZE 32.0

enum {
    MARKET_NAME = 0,
    MARKET_QUANTITY = 1,
    MARKET_PRICE = 2,
    MARKET_BASE_PRICE = 3,
    MARKET_ECO_ADJUST_PRICE = 4,
    MARKET_ECO_ADJUST_QUANTITY = 5,
    MARKET_BASE_QUANTITY = 6,
    MARKET_MASK_PRICE = 7,
    MARKET_MASK_QUANTITY = 8,
    MARKET_UNITS = 9
};

enum {
    EQUIPMENT_TECH_LEVEL_INDEX = 0,
    EQUIPMENT_PRICE_INDEX = 1,
    EQUIPMENT_SHORT_DESC_INDEX = 2,
    EQUIPMENT_KEY_INDEX = 3,
    EQUIPMENT_LONG_DESC_INDEX = 4,
    EQUIPMENT_EXTRA_INFO_INDEX = 5
};

enum {
    OO_POSTFX_NONE = 0,
    OO_POSTFX_COLORBLINDNESS_PROTAN,
    OO_POSTFX_COLORBLINDNESS_DEUTER,
    OO_POSTFX_COLORBLINDNESS_TRITAN,
    OO_POSTFX_CLOAK,
    OO_POSTFX_GRAYSCALE,
    OO_POSTFX_OLDMOVIE,
    OO_POSTFX_CRT,
    OO_POSTFX_CRTBADSIGNAL,
    OO_POSTFX_ENDOFLIST // keep this for last
};

#define SHADERS_MIN SHADERS_OFF

#define MAX_MESSAGES 5

#define PROXIMITY_WARN_DISTANCE 4 // Eric 2010-10-17: old value was 20.0
#define PROXIMITY_WARN_DISTANCE2 (PROXIMITY_WARN_DISTANCE * PROXIMITY_WARN_DISTANCE)
#define PROXIMITY_AVOID_DISTANCE_FACTOR 10.0
#define SAFE_ADDITION_FACTOR2 800 // Eric 2010-10-17: used to be "2 * PROXIMITY_WARN_DISTANCE2"

#define SUN_SKIM_RADIUS_FACTOR 1.15470053838 // 2 sqrt(3) / 3. Why? I have no idea. -- Ahruman 2009-10-04
#define SUN_SPARKS_RADIUS_FACTOR 2.0

inline constexpr std::string_view KEY_TECHLEVEL = "techlevel";
inline constexpr std::string_view KEY_ECONOMY = "economy";
inline constexpr std::string_view KEY_ECONOMY_DESC = "economy_description";
inline constexpr std::string_view KEY_GOVERNMENT = "government";
inline constexpr std::string_view KEY_GOVERNMENT_DESC = "government_description";
inline constexpr std::string_view KEY_POPULATION = "population";
inline constexpr std::string_view KEY_POPULATION_DESC = "population_description";
inline constexpr std::string_view KEY_PRODUCTIVITY = "productivity";
inline constexpr std::string_view KEY_RADIUS = "radius";
inline constexpr std::string_view KEY_NAME = "name";
inline constexpr std::string_view KEY_INHABITANT = "inhabitant";
inline constexpr std::string_view KEY_INHABITANTS = "inhabitants";
inline constexpr std::string_view KEY_DESCRIPTION = "description";
inline constexpr std::string_view KEY_SHORT_DESCRIPTION = "short_description";
inline constexpr std::string_view KEY_PLANETNAME = "planet_name";
inline constexpr std::string_view KEY_SUNNAME = "sun_name";

inline constexpr std::string_view KEY_CHANCE = "chance";
inline constexpr std::string_view KEY_PRICE = "price";
inline constexpr std::string_view KEY_OPTIONAL_EQUIPMENT = "optional_equipment";
inline constexpr std::string_view KEY_STANDARD_EQUIPMENT = "standard_equipment";
inline constexpr std::string_view KEY_EQUIPMENT_MISSILES = "missiles";
inline constexpr std::string_view KEY_EQUIPMENT_FORWARD_WEAPON = "forward_weapon_type";
inline constexpr std::string_view KEY_EQUIPMENT_AFT_WEAPON = "aft_weapon_type";
#define KEY_EQUIPMENT_PORT_WEAPON @"port_weapon_type"
#define KEY_EQUIPMENT_STARBOARD_WEAPON @"starboard_weapon_type"
inline constexpr std::string_view KEY_EQUIPMENT_EXTRAS = "extras";
inline constexpr std::string_view KEY_WEAPON_FACINGS = "weapon_facings";
inline constexpr std::string_view KEY_RENOVATION_MULTIPLIER = "renovation_multiplier";

inline constexpr std::string_view SHIPYARD_KEY_ID = "id";
inline constexpr std::string_view SHIPYARD_KEY_SHIPDATA_KEY = "shipdata_key";
inline constexpr std::string_view SHIPYARD_KEY_SHIP = "ship";
inline constexpr std::string_view SHIPYARD_KEY_PRICE = "price";
inline constexpr std::string_view SHIPYARD_KEY_PERSONALITY = "personality";
// default passenger berth required space
#define PASSENGER_BERTH_SPACE 5

inline constexpr std::string_view PLANETINFO_UNIVERSAL_KEY = "universal";
inline constexpr std::string_view PLANETINFO_INTERSTELLAR_KEY = "interstellar space";

#define OOLITE_EXCEPTION_LOOPING "OoliteLoopingException"
#define OOLITE_EXCEPTION_DATA_NOT_FOUND "OoliteDataNotFoundException"
#define OOLITE_EXCEPTION_FATAL "OoliteFatalException"

// the distance the sky backdrop is from the camera
// though it appears at infinity
#define BILLBOARD_DEPTH 75000.0

#define TIME_ACCELERATION_FACTOR_MIN 0.0625f
#define TIME_ACCELERATION_FACTOR_DEFAULT 1.0f
#define TIME_ACCELERATION_FACTOR_MAX 16.0f

#define DEMO_LIGHT_POSITION 5000.0f, 25000.0f, -10000.0f

#define MIN_DISTANCE_TO_BUOY 750.0f // don't add ships within this distance
#define MIN_DISTANCE_TO_BUOY2 (MIN_DISTANCE_TO_BUOY * MIN_DISTANCE_TO_BUOY)

// if this is changed, also change oolite-populator.js
// once this number has been in a stable release, cannot easily be changed
#define SYSTEM_REPOPULATION_INTERVAL 20.0f;

#ifndef OO_LOCALIZATION_TOOLS
#define OO_LOCALIZATION_TOOLS 1
#endif

#ifndef MASS_DEPENDENT_FUEL_PRICES
#define MASS_DEPENDENT_FUEL_PRICES 1
#endif

@interface Universe : OOWeakRefObject {
@public
    // use a sorted list for drawing and other activities
    Entity* sortedEntities[UNIVERSE_MAX_ENTITIES + 1]; // One extra for padding; see -doRemoveEntity:.
    unsigned n_entities;

    int cursor_row;

    // collision optimisation sorted lists
    Entity *x_list_start, *y_list_start, *z_list_start;

    GLfloat stars_ambient[4];

@private
    NSUInteger _sessionID;

    // colors
    GLfloat sun_diffuse[4];
    GLfloat sun_specular[4];

    OOViewID viewDirection;

    OOMatrix viewMatrix;

    GLfloat airResistanceFactor;

    MyOpenGLView* gameView;

    int next_universal_id;
    Entity* entity_for_uid[MAX_ENTITY_UID];

    std::vector<oo::ObjCRef<Entity*>> entities;

    OOWeakReference *_firstBeacon,
        *_lastBeacon;
    std::map<std::string, oo::ObjCRef<OOWaypointEntity*>, std::less<>> waypoints; // by key

    GLfloat skyClearColor[4];

    std::optional<std::string> currentMessage;
    OOTimeAbsolute messageRepeatTime;
    OOTimeAbsolute countdown_messageRepeatTime; // Getafix(4/Aug/2010) - Quickfix countdown messages colliding with weapon overheat messages.
                                                //                       For proper handling of message dispatching, code refactoring is needed.
    GuiDisplayGen* gui;
    GuiDisplayGen* message_gui;
    GuiDisplayGen* comm_log_gui;

    BOOL displayGUI;
    BOOL wasDisplayGUI;

    BOOL autoSaveNow;
    BOOL autoSave;
    BOOL wireframeGraphics;
    OOGraphicsDetail detailLevel;
    // Above entry replaces these two
    //	BOOL					reducedDetail;
    //	OOShaderSetting			shaderEffectsLevel;

    BOOL displayFPS;

    OOTimeAbsolute universal_time;
    OOTimeDelta time_delta;

    OOTimeAbsolute demo_stage_time;
    OOTimeAbsolute demo_start_time;
    GLfloat demo_start_z;
    int demo_stage;
    NSUInteger demo_ship_index;
    NSUInteger demo_ship_subindex;
    oo::PList demo_ships; // arrays (one per class) of demo ship dictionaries

    GLfloat main_light_position[4];

    BOOL dumpCollisionInfo;

    OOCommodities* commodities;
    OOCommodityMarket* commodityMarket;

    oo::PList _descriptions; // holds descriptive text for lots of stuff, loaded at initialisation (a dict; null until loaded)
    unsigned _descriptionsGeneration; // changes whenever _descriptions is assigned (the bridged -descriptions caches per generation)
    oo::PList customSounds; // holds descriptive audio for lots of stuff, loaded at initialisation
    oo::PList characters; // holds descriptons of characters
    oo::PList _scenarios; // game start scenarios (an array)
    oo::PList globalSettings; // miscellaneous global game settings
    OOSystemDescriptionManager* systemManager; // planetinfo data manager
    oo::PList missiontext; // holds descriptive text for missions, loaded at initialisation
    oo::PList equipmentData; // holds data on available equipment, loaded at initialisation (an array)
    oo::PList equipmentDataOutfitting;
    //	std::set<std::string>	pirateVictimRoles;		// Roles listed in pirateVictimRoles.plist.
    oo::PList roleCategories; // Categories for roles from role-categories.plist, extending the old pirate-victim-roles.plist (category -> array of roles)
    oo::PList autoAIMap; // Default AIs for roles from autoAImap.plist.
    oo::PList screenBackgrounds; // holds filenames for various screens backgrounds, loaded at initialisation
    oo::PList explosionSettings; // explosion settings from explosions.plist

    std::map<std::string, oo::ObjCRef<ShipEntity*>, std::less<>> cargoPods; // template cargo pods, by commodity key

    OOGalaxyID galaxyID;
    OOSystemID systemID;
    OOSystemID targetSystemID;

    std::optional<std::string> system_names[256]; // hold pregenerated universe info (nullopt where the name was nil)
    BOOL system_found[256]; // holds matches for input strings

    int breakPatternCounter;

    ShipEntity* demo_ship;

    StationEntity* cachedStation;
    OOPlanetEntity* cachedPlanet;
    OOSunEntity* cachedSun;
    std::vector<oo::ObjCRef<OOPlanetEntity*>> allPlanets;
    std::vector<oo::ObjCRef<StationEntity*>> allStations; // each once, in the order added

    float ambientLightLevel;

    oo::PList populatorSettings; // key -> populator block (a mixed configuration: each block's callbackObj is an Object node)
    OOTimeDelta next_repopulation;
    std::optional<std::string> system_repopulator;
    BOOL deterministic_population;

    std::optional<std::vector<OOSystemID>> closeSystems; // the current system's neighbours; nullopt until cached

    std::string useAddOns;

    BOOL no_update;

#ifdef OO_DEBUG_MONITOR_ENABLED
    double timeAccelerationFactor;
#endif

    BOOL ECMVisualFXEnabled;

    std::vector<oo::ObjCRef<WormholeEntity*>> activeWormholes;

    std::vector<oo::ObjCRef<OOCharacter*>> characterPool;

    CollisionRegion* universeRegion;

    // check and maintain linked lists occasionally
    BOOL doLinkedListMaintenanceThisUpdate;

    std::vector<oo::ObjCRef<Entity*>> entitiesDeadThisUpdate; // each once, in the order removed
    int framesDoneThisUpdate;
    NSUInteger drawCounter;

#if OOLITE_SPEECH_SYNTH
#if OOLITE_MAC_COCOA_UI
    NSSpeechSynthesizer* speechSynthesizer;
#elif OOLITE_ESPEAK
    const espeak_VOICE** espeak_voices;
    unsigned int espeak_voice_count;
#endif
    oo::PList speechArray; // [original, replacement(, espeak replacement)] pairs
#endif

#if NEW_PLANETS
    std::vector<oo::ObjCRef<OOMaterial*>> _preloadingPlanetMaterials;
#endif
    BOOL doProcedurallyTexturedPlanets;

    GLfloat frustum[6][4];

    std::map<std::string, oo::ObjCRef<OOJSScript*>, std::less<>> conditionScripts;

    BOOL _pauseMessage;
    BOOL _autoCommLog;
    BOOL _permanentCommLog;
    BOOL _autoMessageLogBg;
    BOOL _permanentMessageLog;
    BOOL _witchspaceBreakPattern;
    BOOL _dockingClearanceProtocolActive;
    BOOL _doingStartUp;

    GLuint msaaTextureID;
    GLuint targetTextureID;
    GLuint passthroughTextureID[2];
    NSSize targetFramebufferSize;
    GLuint msaaFramebufferID;
    GLuint msaaDepthBufferID;
    GLuint targetDepthBufferID;
    GLuint targetFramebufferID;
    GLuint passthroughFramebufferID;
    OOShaderProgram* textureProgram;
    OOShaderProgram* blurProgram;
    OOShaderProgram* finalProgram;
    GLuint quadTextureVBO, quadTextureVAO, quadTextureEBO;
    GLint defaultDrawFBO;
    GLuint pingpongFBO[2];
    GLuint pingpongColorbuffers[2];
    BOOL _bloom;
    int _currentPostFX;
    int _colorblindMode;
}

- (BOOL)bloom;
- (void)setBloom:(BOOL)newBloom;

- (int)currentPostFX;
- (void)setCurrentPostFX:(int)newCurrentPostFX;
- (void)terminatePostFX:(int)postFX;

- (id)initWithGameView:(MyOpenGLView*)gameView;

// SessionID: a value that's incremented when the game is reset.
- (NSUInteger)sessionID;

- (BOOL)doProcedurallyTexturedPlanets;
- (void)setDoProcedurallyTexturedPlanets:(BOOL)value;

- (std::optional<std::string>)cxx_useAddOns;
- (BOOL)cxx_setUseAddOns:(const std::string&)newUse fromSaveGame:(BOOL)saveGame;
- (BOOL)cxx_setUseAddOns:(const std::string&)newUse fromSaveGame:(BOOL)saveGame forceReinit:(BOOL)force;

- (void)setUpSettings;

- (BOOL)reinitAndShowDemo:(BOOL)showDemo;

- (BOOL)doingStartUp; // True during initial game startup (not reset).

- (NSUInteger)entityCount;
#ifdef OO_DEBUG_MONITOR_ENABLED
- (void)debugDumpEntities;
- (std::vector<oo::ObjCRef<Entity*>>)cxx_entityList;
#endif

- (void)pauseGame;
- (void)quitGame;

- (void)carryPlayerOn:(StationEntity*)carrier inWormhole:(WormholeEntity*)wormhole;
- (void)setUpUniverseFromStation;
- (void)setUpUniverseFromWitchspace;
- (void)setUpUniverseFromMisjump;
- (void)setUpWitchspace;
- (void)setUpWitchspaceBetweenSystem:(OOSystemID)s1 andSystem:(OOSystemID)s2;
- (void)setUpSpace;
- (void)populateNormalSpace;
- (void)clearSystemPopulator;
- (BOOL)deterministicPopulation;
- (void)populateSystemFromDictionariesWithSun:(OOSunEntity*)sun andPlanet:(OOPlanetEntity*)planet;
- (oo::PList)cxx_getPopulatorSettings; // a copy
- (void)cxx_setPopulatorSetting:(const std::string&)key to:(const oo::PList&)setting; // a null setting removes
- (HPVector)cxx_locationByCode:(const std::string&)code withSun:(OOSunEntity*)sun andPlanet:(OOPlanetEntity*)planet;
- (void)setAmbientLightLevel:(float)newValue;
- (float)ambientLightLevel;
- (void)setLighting;
- (void)forceLightSwitch;
- (void)setMainLightPosition:(Vector)sunPos;
- (OOPlanetEntity*)setUpPlanet;

- (void)makeSunSkimmer:(ShipEntity*)ship andSetAI:(BOOL)setAI;
- (void)cxx_addShipWithRole:(const std::string&)desc nearRouteOneAt:(double)route_fraction;
- (HPVector)cxx_coordinatesForPosition:(HPVector)pos withCoordinateSystem:(const std::string&)system returningScalar:(GLfloat*)my_scalar;
- (std::optional<std::string>)cxx_expressPosition:(HPVector)pos inCoordinateSystem:(const std::string&)system;
- (HPVector)cxx_legacyPositionFrom:(HPVector)pos asCoordinateSystem:(const std::string&)system;
- (HPVector)cxx_coordinatesFromCoordinateSystemString:(const std::string&)system_x_y_z;
- (BOOL)cxx_addShipWithRole:(const std::string&)desc nearPosition:(HPVector)pos withCoordinateSystem:(const std::string&)system;
- (BOOL)cxx_addShips:(int)howMany withRole:(const std::string&)desc atPosition:(HPVector)pos withCoordinateSystem:(const std::string&)system;
- (BOOL)cxx_addShips:(int)howMany withRole:(const std::string&)desc nearPosition:(HPVector)pos withCoordinateSystem:(const std::string&)system;
- (BOOL)cxx_addShips:(int)howMany withRole:(const std::string&)desc nearPosition:(HPVector)pos withCoordinateSystem:(const std::string&)system withinRadius:(GLfloat)radius;
- (BOOL)cxx_addShips:(int)howMany withRole:(const std::string&)desc intoBoundingBox:(BoundingBox)bbox;
- (BOOL)spawnShip:(id)shipdesc; // shared selector (proposed ADR-0043): an Objective-C string
- (void)cxx_witchspaceShipWithPrimaryRole:(const std::string&)role;
- (ShipEntity*)cxx_spawnShipWithRole:(const std::string&)desc near:(Entity*)entity;

- (OOVisualEffectEntity*)cxx_addVisualEffectAt:(HPVector)pos withKey:(const std::string&)key;
- (ShipEntity*)addShipAt:(HPVector)pos withRole:(const std::string&)role withinRadius:(GLfloat)radius;
// Empty where the old methods returned nil (no ship added).
- (std::vector<oo::ObjCRef<ShipEntity*>>)cxx_addShipsAt:(HPVector)pos withRole:(const std::string&)role quantity:(unsigned)count withinRadius:(GLfloat)radius asGroup:(BOOL)isGroup;
- (std::vector<oo::ObjCRef<ShipEntity*>>)cxx_addShipsToRoute:(const std::string&)route withRole:(const std::string&)role quantity:(unsigned)count routeFraction:(double)routeFraction asGroup:(BOOL)isGroup;

- (BOOL)cxx_roleIsPirateVictim:(const std::string&)role;
- (BOOL)cxx_role:(const std::string&)role isInCategory:(const std::string&)category;

- (void)forceWitchspaceEntries;
- (void)addWitchspaceJumpEffectForShip:(ShipEntity*)ship;
- (GLfloat)safeWitchspaceExitDistance;

- (void)setUpBreakPattern:(HPVector)pos orientation:(Quaternion)q forDocking:(BOOL)forDocking;
- (BOOL)witchspaceBreakPattern;
- (void)setWitchspaceBreakPattern:(BOOL)newValue;

- (BOOL)dockingClearanceProtocolActive;
- (void)setDockingClearanceProtocolActive:(BOOL)newValue;

- (void)handleGameOver;

- (void)setupIntroFirstGo:(BOOL)justCobra;
- (void)selectIntro2Previous;
- (void)selectIntro2Next;
- (void)selectIntro2PreviousCategory;
- (void)selectIntro2NextCategory;

- (StationEntity*)station;
- (OOPlanetEntity*)planet;
- (OOSunEntity*)sun;
- (std::vector<oo::ObjCRef<OOPlanetEntity*>>)cxx_planets; // Note: does not include sun.
- (std::vector<oo::ObjCRef<StationEntity*>>)cxx_stations; // includes main station; in the order added
- (std::vector<oo::ObjCRef<WormholeEntity*>>)cxx_wormholes;
- (StationEntity*)cxx_stationWithRole:(const std::string&)role andPosition:(HPVector)position;

// Turn main station into just another station, for blowUpStation.
- (void)unMagicMainStation;
// find a valid station in interstellar space
- (StationEntity*)stationFriendlyTo:(ShipEntity*)ship;

- (void)resetBeacons;
- (Entity<OOBeaconEntity>*)firstBeacon;
- (Entity<OOBeaconEntity>*)lastBeacon;
- (void)setNextBeacon:(Entity<OOBeaconEntity>*)beaconShip;
- (void)clearBeacon:(Entity<OOBeaconEntity>*)beaconShip;

- (std::map<std::string, oo::ObjCRef<OOWaypointEntity*>, std::less<>>)cxx_currentWaypoints;
- (void)cxx_defineWaypoint:(const oo::PList&)definition forKey:(const std::string&)key; // a null definition removes

- (GLfloat*)skyClearColor;
// Note: the alpha value is also air resistance!
- (void)setSkyColorRed:(GLfloat)red green:(GLfloat)green blue:(GLfloat)blue alpha:(GLfloat)alpha;

- (BOOL)breakPatternOver;
- (BOOL)breakPatternHide;

- (std::optional<std::string>)cxx_randomShipKeyForRoleRespectingConditions:(const std::string&)role; // nullopt: none
- (ShipEntity*)cxx_newShipWithRole:(const std::string&)role OO_RETURNS_RETAINED; // Selects ship using role weights, applies auto_ai, respects conditions
- (ShipEntity*)cxx_newShipWithName:(const std::string&)shipKey OO_RETURNS_RETAINED; // Does not apply auto_ai or respect conditions
- (ShipEntity*)cxx_newSubentityWithName:(const std::string&)shipKey andScaleFactor:(float)scale OO_RETURNS_RETAINED; // Does not apply auto_ai or respect conditions
- (OOVisualEffectEntity*)cxx_newVisualEffectWithName:(const std::string&)effectKey OO_RETURNS_RETAINED;
- (DockEntity*)cxx_newDockWithName:(const std::string&)shipKey andScaleFactor:(float)scale OO_RETURNS_RETAINED; // Does not apply auto_ai or respect conditions
- (ShipEntity*)cxx_newShipWithName:(const std::string&)shipKey usePlayerProxy:(BOOL)usePlayerProxy OO_RETURNS_RETAINED; // If usePlayerProxy, non-carriers are instantiated as ProxyPlayerEntity.
- (ShipEntity*)cxx_newShipWithName:(const std::string&)shipKey usePlayerProxy:(BOOL)usePlayerProxy isSubentity:(BOOL)isSubentity OO_RETURNS_RETAINED;
- (ShipEntity*)cxx_newShipWithName:(const std::string&)shipKey usePlayerProxy:(BOOL)usePlayerProxy isSubentity:(BOOL)isSubentity andScaleFactor:(float)scale OO_RETURNS_RETAINED;

- (Class)cxx_shipClassForShipDictionary:(const oo::PList&)dict; // Nil for a null PList

- (std::optional<std::string>)defaultAIForRole:(const std::string&)role; // autoAImap.plist lookup

- (OOCargoQuantity)cxx_maxCargoForShip:(const std::string&)desc;

- (OOCreditsQuantity)cxx_getEquipmentPriceForKey:(const std::string&)eq_key;

- (OOCommodities*)commodities;

- (ShipEntity*)reifyCargoPod:(ShipEntity*)cargoObj;
- (ShipEntity*)cargoPodFromTemplate:(ShipEntity*)cargoObj;
- (std::vector<oo::ObjCRef<ShipEntity*>>)cxx_getContainersOfGoods:(OOCargoQuantity)how_many scarce:(BOOL)scarce legal:(BOOL)legal;
- (std::vector<oo::ObjCRef<ShipEntity*>>)cxx_getContainersOfCommodity:(const std::string&)commodity_name how_much:(OOCargoQuantity)how_many;
- (void)fillCargopodWithRandomCargo:(ShipEntity*)cargopod;

- (std::string)getRandomCommodity; // a commodity key
- (OOCargoQuantity)cxx_getRandomAmountOfCommodity:(const std::string&)co_type;

- (oo::PList)commodityDataForType:(const std::string&)type; // null: no such good
- (std::optional<std::string>)cxx_displayNameForCommodity:(const std::string&)co_type;
- (std::optional<std::string>)cxx_describeCommodity:(const std::string&)co_type amount:(OOCargoQuantity)co_amount;

- (void)setGameView:(MyOpenGLView*)view;
- (MyOpenGLView*)gameView;
- (GameController*)gameController;
- (oo::PList)cxx_gameSettings;

- (void)useGUILightSource:(BOOL)GUILight;

- (void)drawUniverse;

- (void)defineFrustum;
- (BOOL)viewFrustumIntersectsSphereAt:(Vector)position withRadius:(GLfloat)radius;

- (void)drawMessage;

- (void)drawWatermarkString:(const std::string&)watermarkString;

// Used to draw subentities. Should be getting this from camera.
- (OOMatrix)viewMatrix;

- (id)entityForUniversalID:(OOUniversalID)u_id;

- (BOOL)addEntity:(Entity*)entity;
- (BOOL)removeEntity:(Entity*)entity;
- (void)ensureEntityReallyRemoved:(Entity*)entity;
- (void)removeAllEntitiesExceptPlayer;
- (void)removeDemoShips;

- (ShipEntity*)cxx_makeDemoShipWithRole:(const std::string&)role spinning:(BOOL)spinning;

- (BOOL)isVectorClearFromEntity:(Entity*)e1 toDistance:(double)dist fromPoint:(HPVector)p2;
- (Entity*)hazardOnRouteFromEntity:(Entity*)e1 toDistance:(double)dist fromPoint:(HPVector)p2;
- (HPVector)getSafeVectorFromEntity:(Entity*)e1 toDistance:(double)dist fromPoint:(HPVector)p2;

- (ShipEntity*)cxx_addWreckageFrom:(ShipEntity*)ship withRole:(const std::string&)wreckRole at:(HPVector)rpos scale:(GLfloat)scale lifetime:(GLfloat)lifetime;
- (void)addLaserHitEffectsAt:(HPVector)pos against:(ShipEntity*)target damage:(float)damage color:(OOColor*)color;
- (ShipEntity*)firstShipHitByLaserFromShip:(ShipEntity*)srcEntity inDirection:(OOWeaponFacing)direction offset:(Vector)offset gettingRangeFound:(GLfloat*)range_ptr;
- (Entity*)firstEntityTargetedByPlayer;
- (Entity*)firstEntityTargetedByPlayerPrecisely;

- (std::vector<oo::ObjCRef<Entity*>>)cxx_entitiesWithinRange:(double)range ofEntity:(Entity*)entity;
- (unsigned)cxx_countShipsWithRole:(const std::string&)role inRange:(double)range ofEntity:(Entity*)entity;
- (unsigned)cxx_countShipsWithRole:(const std::string&)role;
- (unsigned)cxx_countShipsWithPrimaryRole:(const std::string&)role inRange:(double)range ofEntity:(Entity*)entity;
- (unsigned)cxx_countShipsWithPrimaryRole:(const std::string&)role;
- (unsigned)countShipsWithScanClass:(OOScanClass)scanClass inRange:(double)range ofEntity:(Entity*)entity;

// General count/search methods. Pass range of -1 and entity of nil to search all of system.
- (unsigned)countEntitiesMatchingPredicate:(EntityFilterPredicate)predicate
                                 parameter:(void*)parameter
                                   inRange:(double)range
                                  ofEntity:(Entity*)entity;
- (unsigned)countShipsMatchingPredicate:(EntityFilterPredicate)predicate
                              parameter:(void*)parameter
                                inRange:(double)range
                               ofEntity:(Entity*)entity;
- (std::vector<oo::ObjCRef<Entity*>>)cxx_findEntitiesMatchingPredicate:(EntityFilterPredicate)predicate
                                                             parameter:(void*)parameter
                                                               inRange:(double)range
                                                              ofEntity:(Entity*)entity;
- (id)findOneEntityMatchingPredicate:(EntityFilterPredicate)predicate
                           parameter:(void*)parameter;
- (std::vector<oo::ObjCRef<Entity*>>)cxx_findShipsMatchingPredicate:(EntityFilterPredicate)predicate
                                                          parameter:(void*)parameter
                                                            inRange:(double)range
                                                           ofEntity:(Entity*)entity;
- (std::vector<oo::ObjCRef<Entity*>>)cxx_findVisualEffectsMatchingPredicate:(EntityFilterPredicate)predicate
                                                                  parameter:(void*)parameter
                                                                    inRange:(double)range
                                                                   ofEntity:(Entity*)entity;
- (id)nearestEntityMatchingPredicate:(EntityFilterPredicate)predicate
                           parameter:(void*)parameter
                    relativeToEntity:(Entity*)entity;
- (id)nearestShipMatchingPredicate:(EntityFilterPredicate)predicate
                         parameter:(void*)parameter
                  relativeToEntity:(Entity*)entity;

- (OOTimeAbsolute)getTime;
- (OOTimeDelta)getTimeDelta;

- (void)findCollisionsAndShadows;
- (std::string)collisionDescription; // flipped with its family (bead oo-3rb.277)
- (void)dumpCollisions;

- (OOViewID)viewDirection;
- (void)setViewDirection:(OOViewID)vd;
- (void)enterGUIViewModeWithMouseInteraction:(BOOL)mouseInteraction; // Use instead of setViewDirection:VIEW_GUI_DISPLAY

- (std::optional<std::string>)soundNameForCustomSoundKey:(const std::string&)key; // nullopt: no sound
- (oo::PList)cxx_screenTextureDescriptorForKey:(const std::string&)key; // null: none
- (void)cxx_setScreenTextureDescriptorForKey:(const std::string&)key descriptor:(const oo::PList&)desc; // a null descriptor removes

// Message texts: nullopt where a nil text was passed (nothing is printed; it still counts as the message shown).
- (void)clearPreviousMessage;
- (void)setMessageGuiBackgroundColor:(OOColor*)some_color;
- (void)cxx_displayMessage:(const std::optional<std::string>&)text forCount:(OOTimeDelta)count;
- (void)cxx_displayCountdownMessage:(const std::optional<std::string>&)text forCount:(OOTimeDelta)count;
- (void)cxx_addDelayedMessage:(const std::optional<std::string>&)text forCount:(OOTimeDelta)count afterDelay:(OOTimeDelta)delay;
- (void)addDelayedMessage:(id)textdict; // called by name (ADR-0043 item 21): the deferred call's dictionary
- (void)cxx_addMessage:(const std::optional<std::string>&)text forCount:(OOTimeDelta)count;
- (void)cxx_addMessage:(const std::optional<std::string>&)text forCount:(OOTimeDelta)count forceDisplay:(BOOL)forceDisplay;
- (void)cxx_addCommsMessage:(const std::optional<std::string>&)text forCount:(OOTimeDelta)count;
- (void)cxx_addCommsMessage:(const std::optional<std::string>&)text forCount:(OOTimeDelta)count andShowComms:(BOOL)showComms logOnly:(BOOL)logOnly;
- (void)showCommsLog:(OOTimeDelta)how_long;
- (void)showGUIMessage:(const std::optional<std::string>&)text withScroll:(BOOL)scroll andColor:(OOColor*)selectedColor overDuration:(OOTimeDelta)how_long;

- (void)update:(OOTimeDelta)delta_t;

// Time Acelleration Factor. In deployment builds, this is always 1.0 and -setTimeAccelerationFactor: does nothing.
- (double)timeAccelerationFactor;
- (void)setTimeAccelerationFactor:(double)newTimeAccelerationFactor;

- (BOOL)ECMVisualFXEnabled;
- (void)setECMVisualFXEnabled:(BOOL)isEnabled;

- (void)filterSortedLists;

///////////////////////////////////////

- (void)setGalaxyTo:(OOGalaxyID)g;
- (void)setGalaxyTo:(OOGalaxyID)g andReinit:(BOOL)forced;

- (void)setSystemTo:(OOSystemID)s;

- (OOSystemID)currentSystemID;

// The live descriptions dictionary (the built-in descriptions.plist until the merged one is loaded);
// nullptr only for a nil receiver. The generation changes whenever it is replaced.
- (const oo::PList*)cxx_descriptions;
- (unsigned)cxx_descriptionsGeneration;
- (oo::PList)cxx_characters;
- (oo::PList)cxx_missiontext;
- (oo::PList)cxx_scenarios;
- (oo::PList)cxx_explosionSetting:(const std::string&)explosion; // a null PList for none

- (OOSystemDescriptionManager*)systemManager;

- (std::optional<std::string>)cxx_descriptionForKey:(const std::string&)key; // String, or random item from array; nullopt for none
- (std::optional<std::string>)cxx_descriptionForArrayKey:(const std::string&)key index:(unsigned)index; // Indexed item from array; nullopt for none
- (BOOL)descriptionBooleanForKey:(const std::string&)key; // Boolean from descriptions.plist, for configuration.

- (std::optional<std::string>)cxx_keyForPlanetOverridesForSystem:(OOSystemID)s inGalaxy:(OOGalaxyID)g;
- (std::optional<std::string>)keyForInterstellarOverridesForSystems:(OOSystemID)s1 s2:(OOSystemID)s2 inGalaxy:(OOGalaxyID)g;
- (oo::PList)cxx_generateSystemData:(OOSystemID)s;
- (oo::PList)cxx_generateSystemData:(OOSystemID)s useCache:(BOOL)useCache;
- (oo::PList)cxx_currentSystemData; // Same as generateSystemData:systemSeed unless in interstellar space.

- (BOOL)inInterstellarSpace;

// value: a script value (an Objective-C object, nil to remove); manifest nullopt where nil was passed.
- (void)cxx_setSystemDataKey:(const std::string&)key value:(id)object fromManifest:(const std::optional<std::string>&)manifest;
- (void)cxx_setSystemDataForGalaxy:(OOGalaxyID)gnum planet:(OOSystemID)pnum key:(const std::string&)key value:(id)object fromManifest:(const std::optional<std::string>&)manifest forLayer:(OOSystemLayer)layer;
- (id)cxx_systemDataForGalaxy:(OOGalaxyID)gnum planet:(OOSystemID)pnum key:(const std::string&)key; // a script value
- (std::vector<std::string>)cxx_systemDataKeysForGalaxy:(OOGalaxyID)gnum planet:(OOSystemID)pnum; // byte order of the key
- (std::optional<std::string>)cxx_getSystemName:(OOSystemID)sys;
- (std::optional<std::string>)cxx_getSystemName:(OOSystemID)sys forGalaxy:(OOGalaxyID)gnum;
- (OOGovernmentID)getSystemGovernment:(OOSystemID)sys;
- (std::optional<std::string>)cxx_getSystemInhabitants:(OOSystemID)sys;
- (std::optional<std::string>)cxx_getSystemInhabitants:(OOSystemID)sys plural:(BOOL)plural;

- (NSPoint)coordinatesForSystem:(OOSystemID)s;
- (OOSystemID)cxx_findSystemFromName:(const std::string&)sysName;

/**
 * Finds systems within range.  If range is greater than 7.0LY then only look within 7.0LY.
 */
- (oo::PList)cxx_nearbyDestinationsWithinRange:(double)range; // an array of {distance, sysID, nova}

- (OOSystemID)findNeighbouringSystemToCoords:(NSPoint)coords withGalaxy:(OOGalaxyID)gal;
- (OOSystemID)findConnectedSystemAtCoords:(NSPoint)coords withGalaxy:(OOGalaxyID)gal;
// old alias for findSystemNumberAtCoords
- (OOSystemID)findSystemAtCoords:(NSPoint)coords withGalaxy:(OOGalaxyID)gal;
- (OOSystemID)findSystemNumberAtCoords:(NSPoint)coords withGalaxy:(OOGalaxyID)gal includingHidden:(BOOL)hidden;
- (NSPoint)cxx_findSystemCoordinatesWithPrefix:(const std::string&)p_fix;
- (NSPoint)cxx_findSystemCoordinatesWithPrefix:(const std::string&)p_fix exactMatch:(BOOL)exactMatch;
- (BOOL*)systemsFound;
- (std::optional<std::string>)cxx_systemNameIndex:(OOSystemID)index;
- (oo::PList)cxx_routeFromSystem:(OOSystemID)start toSystem:(OOSystemID)goal optimizedBy:(OORouteType)optimizeBy; // {route, distance, time, jumps}; null for no route
- (std::vector<OOSystemID>)neighboursToSystem:(OOSystemID)system_number;

- (void)preloadPlanetTexturesForSystem:(OOSystemID)system;
- (void)preloadSounds;

- (oo::PList)cxx_globalSettings;

- (oo::PList)cxx_equipmentData;
- (oo::PList)cxx_equipmentDataOutfitting;
- (OOCommodityMarket*)commodityMarket;
- (Random_Seed)marketSeed;

- (std::optional<std::string>)timeDescription:(OOTimeDelta)interval;
- (std::optional<std::string>)cxx_shortTimeDescription:(OOTimeDelta)interval;

- (void)cxx_loadStationMarkets:(const oo::PList&)marketData; // null: nothing to load
- (oo::PList)cxx_getStationMarkets; // [{market, position}, ...] as saved in the savegame

- (oo::PList)cxx_shipsForSaleForSystem:(OOSystemID)s withTL:(OOTechLevelID)specialTL atTime:(OOTimeAbsolute)current_time; // an array of offer dictionaries, by name and price

/* Calculate base cost, before depreciation */
- (OOCreditsQuantity)cxx_tradeInValueForCommanderDictionary:(const oo::PList&)cmdr_dict;

- (std::optional<std::string>)brochureDescriptionWithDictionary:(const oo::PList&)dict standardEquipment:(const std::vector<std::string>&)extras optionalEquipment:(const std::vector<std::string>&)options;

- (HPVector)getWitchspaceExitPosition;
- (Quaternion)getWitchspaceExitRotation;

- (HPVector)getSunSkimStartPositionForShip:(ShipEntity*)ship;
- (HPVector)getSunSkimEndPositionForShip:(ShipEntity*)ship;

- (std::vector<oo::ObjCRef<Entity<OOBeaconEntity>*>>)cxx_listBeaconsWithCode:(const std::string&)code; // sorted by beacon code

- (void)cxx_allShipsDoScriptEvent:(OOJSPropID)event andReactToAIMessage:(const std::optional<std::string>&)message; // nullopt: no AI message

///////////////////////////////////////

- (void)clearGUIs;

- (GuiDisplayGen*)gui;
- (GuiDisplayGen*)commLogGUI;
- (GuiDisplayGen*)messageGUI;

- (void)resetCommsLogColor;

- (void)setDisplayText:(BOOL)value;
- (BOOL)displayGUI;

- (void)setDisplayFPS:(BOOL)value;
- (BOOL)displayFPS;

- (void)setAutoSave:(BOOL)value;
- (BOOL)autoSave;

- (void)setWireframeGraphics:(BOOL)value;
- (BOOL)wireframeGraphics;

- (BOOL)reducedDetail;
- (void)setDetailLevel:(OOGraphicsDetail)value;
- (OOGraphicsDetail)detailLevel;
- (BOOL)useShaders;

- (void)handleOoliteException:(OOException*)ooliteException;

- (GLfloat)airResistanceFactor;
- (void)setAirResistanceFactor:(GLfloat)newFactor;

// speech routines
//
- (void)cxx_startSpeakingString:(const std::string&)text;
//
- (void)stopSpeaking;
//
- (BOOL)isSpeaking;
//
#if OOLITE_ESPEAK
- (std::optional<std::string>)cxx_voiceName:(unsigned int)index;
- (unsigned int)cxx_voiceNumber:(const std::string&)name;
- (unsigned int)nextVoice:(unsigned int)index;
- (unsigned int)prevVoice:(unsigned int)index;
- (unsigned int)setVoice:(unsigned int)index withGenderM:(BOOL)isMale;
#endif
- (int)nextColorblindMode:(int)index;
- (int)prevColorblindMode:(int)index;
- (int)colorblindMode;
//
////

// autosave
- (void)setAutoSaveNow:(BOOL)value;
- (BOOL)autoSaveNow;

- (int)framesDoneThisUpdate;
- (void)resetFramesDoneThisUpdate;

// True if textual pause message (as opposed to overlay) is being shown.
- (BOOL)pauseMessageVisible;
- (void)setPauseMessageVisible:(BOOL)value;

- (BOOL)permanentCommLog;
- (void)setPermanentCommLog:(BOOL)value;
- (void)setAutoCommLog:(BOOL)value;
- (BOOL)permanentMessageLog;
- (void)setPermanentMessageLog:(BOOL)value;
- (BOOL)autoMessageLogBg;
- (void)setAutoMessageLogBg:(BOOL)value;

- (BOOL)blockJSPlayerShipProps;
- (void)setBlockJSPlayerShipProps:(BOOL)value;

- (void)loadConditionScripts;
- (void)addConditionScripts:(const std::vector<std::string>&)scripts;
- (OOJSScript*)cxx_getConditionScript:(const std::string&)scriptname;

@end

/*	Use UNIVERSE to refer to the global universe object.
        The purpose of this is that it makes UNIVERSE essentially a read-only
        global with zero overhead.
*/
OOINLINE Universe* OOGetUniverse(void) INLINE_CONST_FUNC;
OOINLINE Universe* OOGetUniverse(void)
{
    extern Universe* gSharedUniverse;
    return gSharedUniverse;
}
#define UNIVERSE OOGetUniverse()

// Only for use with string literals, and only for looking up strings: the description, or the
// key itself when there is none (proposed ADR-0053). OO_DESC() is deprecated in favour of
// cxx_OOExpandKey() except in known performance-critical contexts.
#define OO_DESC(key) (cxx_OOLookUpDescriptionPRIV(key ""))
#define OO_DESC_PLURAL(key, count) (cxx_OOLookUpPluralDescriptionPRIV(key "", count))

// Not for direct use.
// The lookups behind OO_DESC() / OO_DESC_PLURAL(): the description, or the key itself when there is none.
std::string cxx_OOLookUpDescriptionPRIV(const std::string& key);
std::string cxx_OOLookUpPluralDescriptionPRIV(const std::string& key, NSInteger count);

@interface OOSound (OOCustomSounds)

+ (id)cxx_soundWithCustomSoundKey:(const std::string&)key;
- (id)initWithCustomSoundKey:(const std::string&)key;

@end

@interface OOSoundSource (OOCustomSounds)

+ (id)sourceWithCustomSoundKey:(const std::string&)key;
- (id)initWithCustomSoundKey:(const std::string&)key;

- (void)cxx_playCustomSoundWithKey:(const std::string&)key;

@end

#ifdef __cplusplus
#include "oofnd/StdLib.hpp"

// C++ forms, defined in OOConstToString.mm (bead oo-nts1, chunk oo-3rb.162): nullopt where the
// old Foundation forms gave nil.
std::optional<std::string> cxx_OODisplayStringFromGovernmentID(OOGovernmentID government);
std::optional<std::string> cxx_OODisplayStringFromEconomyID(OOEconomyID economy);
#endif
