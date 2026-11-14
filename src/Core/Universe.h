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
#include "oofnd/Ref.hpp"
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

@class Universe;

/*	The universe's state (bead oo-riqmz, slice 1 of docs/phases/3-slices/Universe.md): the old
        @interface's ivars, by the same names and types, every one zero-initialised as the runtime
        zeroed them. The Objective-C Universe (Universe+ObjCBridge.h, imported at the end of this
        header) owns one and is the game's universe object; its unconverted methods, and the other
        classes that read the ivars directly, reach the members through its @public _cxxUniverse
        (UNIVERSE->_cxxUniverse->n_entities). Each later slice moves its methods here as member
        functions (ADR-0056 amendments oo-bj8 item 2, oo-60fwo, oo-riqmz).
        Objective-C classes are named ::X here: in namespace cxx the bare name may be the C++ twin.
*/
namespace cxx {

class Universe : public oo::RefCounted {
public:
    explicit Universe(::Universe* objcOwner);
    ~Universe();

    // -initWithGameView:'s set-up, after the facade's [super init] (slice 1).
    void initWithGameView(::MyOpenGLView* inGameView);
    // -dealloc's body: the facade sends it before it releases this part and sends [super dealloc].
    void dealloc();

    Universe(const Universe&) = delete;
    Universe& operator=(const Universe&) = delete;

    // The Objective-C object that owns this part; borrowed (oo::ToObjC answers it).
    ::Universe* _objcOwner = nil;

    // Formerly @public.
    // use a sorted list for drawing and other activities
    ::Entity* sortedEntities[UNIVERSE_MAX_ENTITIES + 1] = { }; // One extra for padding; see -doRemoveEntity:.
    unsigned n_entities = 0;

    int cursor_row = 0;

    // collision optimisation sorted lists
    ::Entity *x_list_start = nil, *y_list_start = nil, *z_list_start = nil;

    GLfloat stars_ambient[4] = { };

    // Formerly @private: public while the class is half converted, because the facade's
    // unconverted methods read them (amendment oo-60fwo item 2). Private once Universe is
    // converted (oo-pas).
    NSUInteger _sessionID = 0;

    // colors
    GLfloat sun_diffuse[4] = { };
    GLfloat sun_specular[4] = { };

    OOViewID viewDirection = { };

    OOMatrix viewMatrix = { };

    GLfloat airResistanceFactor = 0;

    ::MyOpenGLView* gameView = nil;

    int next_universal_id = 0;
    ::Entity* entity_for_uid[MAX_ENTITY_UID] = { };

    std::vector<oo::ObjCRef<::Entity*>> entities;

    ::OOWeakReference *_firstBeacon = nil,
                      *_lastBeacon = nil;
    std::map<std::string, oo::ObjCRef<::OOWaypointEntity*>, std::less<>> waypoints; // by key

    GLfloat skyClearColor[4] = { };

    std::optional<std::string> currentMessage;
    OOTimeAbsolute messageRepeatTime = 0;
    OOTimeAbsolute countdown_messageRepeatTime = 0; // Getafix(4/Aug/2010) - Quickfix countdown messages colliding with weapon overheat messages.
                                                    //                       For proper handling of message dispatching, code refactoring is needed.
    ::GuiDisplayGen* gui = nil;
    ::GuiDisplayGen* message_gui = nil;
    ::GuiDisplayGen* comm_log_gui = nil;

    BOOL displayGUI = NO;
    BOOL wasDisplayGUI = NO;

    BOOL autoSaveNow = NO;
    BOOL autoSave = NO;
    BOOL wireframeGraphics = NO;
    OOGraphicsDetail detailLevel = { };
    // Above entry replaces these two
    //	BOOL					reducedDetail;
    //	OOShaderSetting			shaderEffectsLevel;

    BOOL displayFPS = NO;

    OOTimeAbsolute universal_time = 0;
    OOTimeDelta time_delta = 0;

    OOTimeAbsolute demo_stage_time = 0;
    OOTimeAbsolute demo_start_time = 0;
    GLfloat demo_start_z = 0;
    int demo_stage = 0;
    NSUInteger demo_ship_index = 0;
    NSUInteger demo_ship_subindex = 0;
    oo::PList demo_ships; // arrays (one per class) of demo ship dictionaries

    GLfloat main_light_position[4] = { };

    BOOL dumpCollisionInfo = NO;

    ::OOCommodities* commodities = nil;
    ::OOCommodityMarket* commodityMarket = nil;

    oo::PList _descriptions; // holds descriptive text for lots of stuff, loaded at initialisation (a dict; null until loaded)
    unsigned _descriptionsGeneration = 0; // changes whenever _descriptions is assigned (the bridged -descriptions caches per generation)
    oo::PList customSounds; // holds descriptive audio for lots of stuff, loaded at initialisation
    oo::PList characters; // holds descriptons of characters
    oo::PList _scenarios; // game start scenarios (an array)
    oo::PList globalSettings; // miscellaneous global game settings
    ::OOSystemDescriptionManager* systemManager = nil; // planetinfo data manager
    oo::PList missiontext; // holds descriptive text for missions, loaded at initialisation
    oo::PList equipmentData; // holds data on available equipment, loaded at initialisation (an array)
    oo::PList equipmentDataOutfitting;
    //	std::set<std::string>	pirateVictimRoles;		// Roles listed in pirateVictimRoles.plist.
    oo::PList roleCategories; // Categories for roles from role-categories.plist, extending the old pirate-victim-roles.plist (category -> array of roles)
    oo::PList autoAIMap; // Default AIs for roles from autoAImap.plist.
    oo::PList screenBackgrounds; // holds filenames for various screens backgrounds, loaded at initialisation
    oo::PList explosionSettings; // explosion settings from explosions.plist

    std::map<std::string, oo::ObjCRef<::ShipEntity*>, std::less<>> cargoPods; // template cargo pods, by commodity key

    OOGalaxyID galaxyID = 0;
    OOSystemID systemID = 0;
    OOSystemID targetSystemID = 0;

    std::optional<std::string> system_names[256]; // hold pregenerated universe info (nullopt where the name was nil)
    BOOL system_found[256] = { }; // holds matches for input strings

    int breakPatternCounter = 0;

    ::ShipEntity* demo_ship = nil;

    ::StationEntity* cachedStation = nil;
    ::OOPlanetEntity* cachedPlanet = nil;
    ::OOSunEntity* cachedSun = nil;
    std::vector<oo::ObjCRef<::OOPlanetEntity*>> allPlanets;
    std::vector<oo::ObjCRef<::StationEntity*>> allStations; // each once, in the order added

    float ambientLightLevel = 0;

    oo::PList populatorSettings; // key -> populator block (a mixed configuration: each block's callbackObj is an Object node)
    OOTimeDelta next_repopulation = 0;
    std::optional<std::string> system_repopulator;
    BOOL deterministic_population = NO;

    std::optional<std::vector<OOSystemID>> closeSystems; // the current system's neighbours; nullopt until cached

    std::string useAddOns;

    BOOL no_update = NO;

#ifdef OO_DEBUG_MONITOR_ENABLED
    double timeAccelerationFactor = 0;
#endif

    BOOL ECMVisualFXEnabled = NO;

    std::vector<oo::ObjCRef<::WormholeEntity*>> activeWormholes;

    std::vector<oo::ObjCRef<::OOCharacter*>> characterPool;

    ::CollisionRegion* universeRegion = nil;

    // check and maintain linked lists occasionally
    BOOL doLinkedListMaintenanceThisUpdate = NO;

    std::vector<oo::ObjCRef<::Entity*>> entitiesDeadThisUpdate; // each once, in the order removed
    int framesDoneThisUpdate = 0;
    NSUInteger drawCounter = 0;

#if OOLITE_SPEECH_SYNTH
#if OOLITE_MAC_COCOA_UI
    NSSpeechSynthesizer* speechSynthesizer = nil;
#elif OOLITE_ESPEAK
    const espeak_VOICE** espeak_voices = nullptr;
    unsigned int espeak_voice_count = 0;
#endif
    oo::PList speechArray; // [original, replacement(, espeak replacement)] pairs
#endif

    std::vector<oo::ObjCRef<::OOMaterial*>> _preloadingPlanetMaterials;
    BOOL doProcedurallyTexturedPlanets = NO;

    GLfloat frustum[6][4] = { };

    std::map<std::string, oo::ObjCRef<::OOJSScript*>, std::less<>> conditionScripts;

    BOOL _pauseMessage = NO;
    BOOL _autoCommLog = NO;
    BOOL _permanentCommLog = NO;
    BOOL _autoMessageLogBg = NO;
    BOOL _permanentMessageLog = NO;
    BOOL _witchspaceBreakPattern = NO;
    BOOL _dockingClearanceProtocolActive = NO;
    BOOL _doingStartUp = NO;

    GLuint msaaTextureID = 0;
    GLuint targetTextureID = 0;
    GLuint passthroughTextureID[2] = { };
    NSSize targetFramebufferSize = { };
    GLuint msaaFramebufferID = 0;
    GLuint msaaDepthBufferID = 0;
    GLuint targetDepthBufferID = 0;
    GLuint targetFramebufferID = 0;
    GLuint passthroughFramebufferID = 0;
    ::OOShaderProgram* textureProgram = nil;
    ::OOShaderProgram* blurProgram = nil;
    ::OOShaderProgram* finalProgram = nil;
    GLuint quadTextureVBO = 0, quadTextureVAO = 0, quadTextureEBO = 0;
    GLint defaultDrawFBO = 0;
    GLuint pingpongFBO[2] = { };
    GLuint pingpongColorbuffers[2] = { };
    BOOL _bloom = NO;
    int _currentPostFX = 0;
    int _colorblindMode = 0;
};

} // namespace cxx

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

// The Objective-C Universe, the facade over cxx::Universe while the class converts slice by slice.
// Deleted, with namespace cxx above, by the bridge's deletion bead.
#import "Universe+ObjCBridge.h"
