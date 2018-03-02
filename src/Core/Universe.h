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

#import "OOCocoa.h"
#import "OOOpenGL.h"
#import "legacy_random.h"
#import "OOMaths.h"
#import "OOColor.h"
#import "OOWeakReference.h"
#import "OOTypes.h"
#import "OOSound.h"
#import "OOJSPropID.h"
#import "OOStellarBody.h"
#import "OOEntityWithDrawable.h"
#import "OOCommodities.h"
#import "OOSystemDescriptionManager.h"

#if OOLITE_ESPEAK
#include <espeak/speak_lib.h>
#endif

@class	GameController, CollisionRegion, MyOpenGLView, GuiDisplayGen,
	Entity, ShipEntity, StationEntity, OOPlanetEntity, OOSunEntity,
	OOVisualEffectEntity, PlayerEntity, OORoleSet, WormholeEntity, 
	DockEntity, OOJSScript, OOWaypointEntity, OOSystemDescriptionManager;


typedef BOOL (*EntityFilterPredicate)(Entity *entity, void *parameter);

#ifndef OO_SCANCLASS_TYPE
#define OO_SCANCLASS_TYPE
typedef enum OOScanClass OOScanClass;
#endif


#define CROSSHAIR_SIZE						32.0

enum
{
	MARKET_NAME								= 0,
	MARKET_QUANTITY							= 1,
	MARKET_PRICE							= 2,
	MARKET_BASE_PRICE						= 3,
	MARKET_ECO_ADJUST_PRICE					= 4,
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
	EQUIPMENT_KEY_INDEX						= 3,
	EQUIPMENT_LONG_DESC_INDEX				= 4,
	EQUIPMENT_EXTRA_INFO_INDEX				= 5
};


#define SHADERS_MIN SHADERS_OFF


#define MAX_MESSAGES						5

#define PROXIMITY_WARN_DISTANCE				4 // Eric 2010-10-17: old value was 20.0
#define PROXIMITY_WARN_DISTANCE2			(PROXIMITY_WARN_DISTANCE * PROXIMITY_WARN_DISTANCE)
#define PROXIMITY_AVOID_DISTANCE_FACTOR		10.0
#define SAFE_ADDITION_FACTOR2				800 // Eric 2010-10-17: used to be "2 * PROXIMITY_WARN_DISTANCE2"

#define SUN_SKIM_RADIUS_FACTOR				1.15470053838	// 2 sqrt(3) / 3. Why? I have no idea. -- Ahruman 2009-10-04
#define SUN_SPARKS_RADIUS_FACTOR			2.0

#define KEY_TECHLEVEL						@"techlevel"
#define KEY_ECONOMY							@"economy"
#define KEY_ECONOMY_DESC					@"economy_description"
#define KEY_GOVERNMENT						@"government"
#define KEY_GOVERNMENT_DESC					@"government_description"
#define KEY_POPULATION						@"population"
#define KEY_POPULATION_DESC					@"population_description"
#define KEY_PRODUCTIVITY					@"productivity"
#define KEY_RADIUS							@"radius"
#define KEY_NAME							@"name"
#define KEY_INHABITANT						@"inhabitant"
#define KEY_INHABITANTS						@"inhabitants"
#define KEY_DESCRIPTION						@"description"
#define KEY_SHORT_DESCRIPTION				@"short_description"
#define KEY_PLANETNAME						@"planet_name"
#define KEY_SUNNAME							@"sun_name"

#define KEY_CHANCE							@"chance"
#define KEY_PRICE							@"price"
#define KEY_OPTIONAL_EQUIPMENT				@"optional_equipment"
#define KEY_STANDARD_EQUIPMENT				@"standard_equipment"
#define KEY_EQUIPMENT_MISSILES				@"missiles"
#define KEY_EQUIPMENT_FORWARD_WEAPON		@"forward_weapon_type"
#define KEY_EQUIPMENT_AFT_WEAPON			@"aft_weapon_type"
#define KEY_EQUIPMENT_PORT_WEAPON			@"port_weapon_type"
#define KEY_EQUIPMENT_STARBOARD_WEAPON		@"starboard_weapon_type"
#define KEY_EQUIPMENT_EXTRAS				@"extras"
#define KEY_WEAPON_FACINGS					@"weapon_facings"
#define KEY_RENOVATION_MULTIPLIER					@"renovation_multiplier"

#define SHIPYARD_KEY_ID						@"id"
#define SHIPYARD_KEY_SHIPDATA_KEY			@"shipdata_key"
#define SHIPYARD_KEY_SHIP					@"ship"
#define SHIPYARD_KEY_PRICE					@"price"
#define SHIPYARD_KEY_PERSONALITY			@"personality"
// default passenger berth required space
#define PASSENGER_BERTH_SPACE				5

#define PLANETINFO_UNIVERSAL_KEY			@"universal"
#define PLANETINFO_INTERSTELLAR_KEY			@"interstellar space"

#define OOLITE_EXCEPTION_LOOPING			@"OoliteLoopingException"
#define OOLITE_EXCEPTION_DATA_NOT_FOUND		@"OoliteDataNotFoundException"
#define OOLITE_EXCEPTION_FATAL				@"OoliteFatalException"

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


@interface Universe: OOWeakRefObject
{
@public
	// use a sorted list for drawing and other activities
	Entity					*sortedEntities[UNIVERSE_MAX_ENTITIES + 1];	// One extra for padding; see -doRemoveEntity:.
	unsigned				n_entities;
	
	int						cursor_row;
	
	// collision optimisation sorted lists
	Entity					*x_list_start, *y_list_start, *z_list_start;
	
	GLfloat					stars_ambient[4];
	
@private
	NSUInteger				_sessionID;
	
	// colors
	GLfloat					sun_diffuse[4];
	GLfloat					sun_specular[4];

	OOViewID				viewDirection;
	
	OOMatrix				viewMatrix;
	
	GLfloat					airResistanceFactor;
	
	MyOpenGLView			*gameView;
	
	int						next_universal_id;
	Entity					*entity_for_uid[MAX_ENTITY_UID];

	NSMutableArray			*entities;
	
	OOWeakReference			*_firstBeacon,
							*_lastBeacon;
	NSMutableDictionary		*waypoints;

	GLfloat					skyClearColor[4];
	
	NSString				*currentMessage;
	OOTimeAbsolute			messageRepeatTime;
	OOTimeAbsolute			countdown_messageRepeatTime; 	// Getafix(4/Aug/2010) - Quickfix countdown messages colliding with weapon overheat messages.
									//                       For proper handling of message dispatching, code refactoring is needed.
	GuiDisplayGen			*gui;
	GuiDisplayGen			*message_gui;
	GuiDisplayGen			*comm_log_gui;
	
	BOOL					displayGUI;
	BOOL					wasDisplayGUI;
	
	BOOL					autoSaveNow;
	BOOL					autoSave;
	BOOL					wireframeGraphics;
	OOGraphicsDetail		detailLevel;
// Above entry replaces these two
//	BOOL					reducedDetail;
//	OOShaderSetting			shaderEffectsLevel;
	
	BOOL					displayFPS;		
			
	OOTimeAbsolute			universal_time;
	OOTimeDelta				time_delta;
	
	OOTimeAbsolute			demo_stage_time;
	OOTimeAbsolute			demo_start_time;
	GLfloat					demo_start_z;
	int						demo_stage;
	NSUInteger				demo_ship_index;
	NSUInteger				demo_ship_subindex;
	NSArray					*demo_ships;
	
	GLfloat					main_light_position[4];
	
	BOOL					dumpCollisionInfo;
	
	OOCommodities			*commodities;
	OOCommodityMarket		*commodityMarket;


	NSDictionary			*_descriptions;			// holds descriptive text for lots of stuff, loaded at initialisation
	NSDictionary			*customSounds;			// holds descriptive audio for lots of stuff, loaded at initialisation
	NSDictionary			*characters;			// holds descriptons of characters
	NSArray					*_scenarios;			// game start scenarios
	NSDictionary			*globalSettings;		// miscellaneous global game settings
	OOSystemDescriptionManager	*systemManager; // planetinfo data manager
	NSDictionary			*missiontext;			// holds descriptive text for missions, loaded at initialisation
	NSArray					*equipmentData;			// holds data on available equipment, loaded at initialisation
//	NSSet					*pirateVictimRoles;		// Roles listed in pirateVictimRoles.plist.
	NSDictionary			*roleCategories;		// Categories for roles from role-categories.plist, extending the old pirate-victim-roles.plist
	NSDictionary			*autoAIMap;				// Default AIs for roles from autoAImap.plist.
	NSDictionary			*screenBackgrounds;		// holds filenames for various screens backgrounds, loaded at initialisation
	NSDictionary			*explosionSettings;		// explosion settings from explosions.plist

	NSDictionary      *cargoPods; // template cargo pods

	OOGalaxyID				galaxyID;
	OOSystemID				systemID;
	OOSystemID				targetSystemID;
	
	NSString				*system_names[256];		// hold pregenerated universe info
	BOOL					system_found[256];		// holds matches for input strings
	
	int						breakPatternCounter;
	
	ShipEntity				*demo_ship;
	
	StationEntity			*cachedStation;
	OOPlanetEntity			*cachedPlanet;
	OOSunEntity				*cachedSun;
	NSMutableArray			*allPlanets;
	NSMutableSet			*allStations;
	
	float					ambientLightLevel;
	
	NSMutableDictionary		*populatorSettings;
	OOTimeDelta		next_repopulation;
	NSString		*system_repopulator;
	BOOL			deterministic_population;

	NSArray					*closeSystems;
	
	NSString				*useAddOns;
	
	BOOL					no_update;
	
#ifndef NDEBUG
	double					timeAccelerationFactor;
#endif
	
	NSMutableArray			*activeWormholes;
	
	NSMutableArray			*characterPool;
	
	CollisionRegion			*universeRegion;
	
	// check and maintain linked lists occasionally
	BOOL					doLinkedListMaintenanceThisUpdate;
	
	NSMutableSet			*entitiesDeadThisUpdate;
	int						framesDoneThisUpdate;
	
#if OOLITE_SPEECH_SYNTH
#if OOLITE_MAC_OS_X
	NSSpeechSynthesizer		*speechSynthesizer;
#elif OOLITE_ESPEAK
	const espeak_VOICE		**espeak_voices;
	unsigned int			espeak_voice_count;
#endif
	NSArray					*speechArray;
#endif
	
#if NEW_PLANETS
	NSMutableArray			*_preloadingPlanetMaterials;
#endif
	BOOL					doProcedurallyTexturedPlanets;
	
	GLfloat					frustum[6][4];
	
	NSMutableDictionary		*conditionScripts;
	
	BOOL					_pauseMessage;
	BOOL					_autoCommLog;
	BOOL					_permanentCommLog;
	BOOL					_autoMessageLogBg;
	BOOL					_permanentMessageLog;
	BOOL					_witchspaceBreakPattern;
	BOOL					_dockingClearanceProtocolActive;
	BOOL					_doingStartUp;
}

- (id)initWithGameView:(MyOpenGLView *)gameView;

// SessionID: a value that's incremented when the game is reset.
- (NSUInteger) sessionID;

- (BOOL) doProcedurallyTexturedPlanets;
- (void) setDoProcedurallyTexturedPlanets:(BOOL) value;

- (NSString *) useAddOns;
- (BOOL) setUseAddOns:(NSString *)newUse fromSaveGame: (BOOL)saveGame;
- (BOOL) setUseAddOns:(NSString *) newUse fromSaveGame:(BOOL) saveGame forceReinit:(BOOL)force;

- (void) setUpSettings;

- (BOOL) reinitAndShowDemo:(BOOL)showDemo;

- (BOOL) doingStartUp;	// True during initial game startup (not reset).

- (NSUInteger) entityCount;
#ifndef NDEBUG
- (void) debugDumpEntities;
- (NSArray *) entityList;
#endif

- (void) pauseGame;

- (void) carryPlayerOn:(StationEntity*)carrier inWormhole:(WormholeEntity*)wormhole;
- (void) setUpUniverseFromStation;
- (void) setUpUniverseFromWitchspace;
- (void) setUpUniverseFromMisjump;
- (void) setUpWitchspace;
- (void) setUpWitchspaceBetweenSystem:(OOSystemID)s1 andSystem:(OOSystemID)s2;
- (void) setUpSpace;
- (void) populateNormalSpace;
- (void) clearSystemPopulator;
- (BOOL) deterministicPopulation;
- (void) populateSystemFromDictionariesWithSun:(OOSunEntity *)sun andPlanet:(OOPlanetEntity *)planet;
- (NSDictionary *) getPopulatorSettings;
- (void) setPopulatorSetting:(NSString *)key to:(NSDictionary *)setting;
- (HPVector) locationByCode:(NSString *)code withSun:(OOSunEntity *)sun andPlanet:(OOPlanetEntity *)planet;
- (void) setAmbientLightLevel:(float)newValue;
- (float) ambientLightLevel;
- (void) setLighting;
- (void) forceLightSwitch;
- (void) setMainLightPosition: (Vector) sunPos;
- (OOPlanetEntity *) setUpPlanet;

- (void) makeSunSkimmer:(ShipEntity *) ship andSetAI:(BOOL)setAI;
- (void) addShipWithRole:(NSString *) desc nearRouteOneAt:(double) route_fraction;
- (HPVector) coordinatesForPosition:(HPVector) pos withCoordinateSystem:(NSString *) system returningScalar:(GLfloat*) my_scalar;
- (NSString *) expressPosition:(HPVector) pos inCoordinateSystem:(NSString *) system;
- (HPVector) legacyPositionFrom:(HPVector) pos asCoordinateSystem:(NSString *) system;
- (HPVector) coordinatesFromCoordinateSystemString:(NSString *) system_x_y_z;
- (BOOL) addShipWithRole:(NSString *) desc nearPosition:(HPVector) pos withCoordinateSystem:(NSString *) system;
- (BOOL) addShips:(int) howMany withRole:(NSString *) desc atPosition:(HPVector) pos withCoordinateSystem:(NSString *) system;
- (BOOL) addShips:(int) howMany withRole:(NSString *) desc nearPosition:(HPVector) pos withCoordinateSystem:(NSString *) system;
- (BOOL) addShips:(int) howMany withRole:(NSString *) desc nearPosition:(HPVector) pos withCoordinateSystem:(NSString *) system withinRadius:(GLfloat) radius;
- (BOOL) addShips:(int) howMany withRole:(NSString *) desc intoBoundingBox:(BoundingBox) bbox;
- (BOOL) spawnShip:(NSString *) shipdesc;
- (void) witchspaceShipWithPrimaryRole:(NSString *)role;
- (ShipEntity *) spawnShipWithRole:(NSString *) desc near:(Entity *) entity;

- (OOVisualEffectEntity *) addVisualEffectAt:(HPVector)pos withKey:(NSString *)key;
- (ShipEntity *) addShipAt:(HPVector)pos withRole:(NSString *)role withinRadius:(GLfloat)radius;
- (NSArray *) addShipsAt:(HPVector)pos withRole:(NSString *)role quantity:(unsigned)count withinRadius:(GLfloat)radius asGroup:(BOOL)isGroup;
- (NSArray *) addShipsToRoute:(NSString *)route withRole:(NSString *)role quantity:(unsigned)count routeFraction:(double)routeFraction asGroup:(BOOL)isGroup;

- (BOOL) roleIsPirateVictim:(NSString *)role;
- (BOOL) role:(NSString *)role isInCategory:(NSString *)category;

- (void) forceWitchspaceEntries;
- (void) addWitchspaceJumpEffectForShip:(ShipEntity *)ship;
- (GLfloat) safeWitchspaceExitDistance;

- (void) setUpBreakPattern:(HPVector)pos orientation:(Quaternion)q forDocking:(BOOL)forDocking;
- (BOOL) witchspaceBreakPattern;
- (void) setWitchspaceBreakPattern:(BOOL)newValue;

- (BOOL) dockingClearanceProtocolActive;
- (void) setDockingClearanceProtocolActive:(BOOL)newValue;

- (void) handleGameOver;

- (void) setupIntroFirstGo:(BOOL)justCobra;
- (void) selectIntro2Previous;
- (void) selectIntro2Next;
- (void) selectIntro2PreviousCategory;
- (void) selectIntro2NextCategory;

- (StationEntity *) station;
- (OOPlanetEntity *) planet;
- (OOSunEntity *) sun;
- (NSArray *) planets;	// Note: does not include sun.
- (NSArray *) stations; // includes main station
- (NSArray *) wormholes; 
- (StationEntity *) stationWithRole:(NSString *)role andPosition:(HPVector)position;

// Turn main station into just another station, for blowUpStation.
- (void) unMagicMainStation;
// find a valid station in interstellar space
- (StationEntity *) stationFriendlyTo:(ShipEntity *) ship;

- (void) resetBeacons;
- (Entity <OOBeaconEntity> *) firstBeacon;
- (Entity <OOBeaconEntity> *) lastBeacon;
- (void) setNextBeacon:(Entity <OOBeaconEntity> *) beaconShip;
- (void) clearBeacon:(Entity <OOBeaconEntity> *) beaconShip;

- (NSDictionary *) currentWaypoints;
- (void) defineWaypoint:(NSDictionary *)definition forKey:(NSString *)key;

- (GLfloat *) skyClearColor;
// Note: the alpha value is also air resistance!
- (void) setSkyColorRed:(GLfloat)red green:(GLfloat)green blue:(GLfloat)blue alpha:(GLfloat)alpha;

- (BOOL) breakPatternOver;
- (BOOL) breakPatternHide;

- (NSString *) randomShipKeyForRoleRespectingConditions:(NSString *)role;
- (ShipEntity *) newShipWithRole:(NSString *)role OO_RETURNS_RETAINED;		// Selects ship using role weights, applies auto_ai, respects conditions
- (ShipEntity *) newShipWithName:(NSString *)shipKey OO_RETURNS_RETAINED;	// Does not apply auto_ai or respect conditions
- (ShipEntity *) newSubentityWithName:(NSString *)shipKey andScaleFactor:(float)scale OO_RETURNS_RETAINED;	// Does not apply auto_ai or respect conditions
- (OOVisualEffectEntity *) newVisualEffectWithName:(NSString *)effectKey OO_RETURNS_RETAINED;
- (DockEntity *) newDockWithName:(NSString *)shipKey andScaleFactor:(float)scale OO_RETURNS_RETAINED;	// Does not apply auto_ai or respect conditions
- (ShipEntity *) newShipWithName:(NSString *)shipKey usePlayerProxy:(BOOL)usePlayerProxy OO_RETURNS_RETAINED;	// If usePlayerProxy, non-carriers are instantiated as ProxyPlayerEntity.
- (ShipEntity *) newShipWithName:(NSString *)shipKey usePlayerProxy:(BOOL)usePlayerProxy isSubentity:(BOOL)isSubentity OO_RETURNS_RETAINED;
- (ShipEntity *) newShipWithName:(NSString *)shipKey usePlayerProxy:(BOOL)usePlayerProxy isSubentity:(BOOL)isSubentity andScaleFactor:(float)scale OO_RETURNS_RETAINED;

- (Class) shipClassForShipDictionary:(NSDictionary *)dict;

- (NSString *)defaultAIForRole:(NSString *)role;		// autoAImap.plist lookup

- (OOCargoQuantity) maxCargoForShip:(NSString *) desc;

- (OOCreditsQuantity) getEquipmentPriceForKey:(NSString *) eq_key;

- (OOCommodities *) commodities;

- (ShipEntity *) reifyCargoPod:(ShipEntity *)cargoObj;
- (ShipEntity *) cargoPodFromTemplate:(ShipEntity *)cargoObj;
- (NSArray *) getContainersOfGoods:(OOCargoQuantity)how_many scarce:(BOOL)scarce legal:(BOOL)legal;
- (NSArray *) getContainersOfCommodity:(OOCommodityType) commodity_name :(OOCargoQuantity) how_many;
- (void) fillCargopodWithRandomCargo:(ShipEntity *)cargopod;

- (NSString *) getRandomCommodity;
- (OOCargoQuantity) getRandomAmountOfCommodity:(OOCommodityType) co_type;

- (NSDictionary *) commodityDataForType:(OOCommodityType)type;
- (NSString *) displayNameForCommodity:(OOCommodityType)co_type;
- (NSString *) describeCommodity:(OOCommodityType)co_type amount:(OOCargoQuantity) co_amount;

- (void) setGameView:(MyOpenGLView *)view;
- (MyOpenGLView *) gameView;
- (GameController *) gameController;
- (NSDictionary *) gameSettings;

- (void) useGUILightSource:(BOOL)GUILight;

- (void) drawUniverse;

- (void) defineFrustum;
- (BOOL) viewFrustumIntersectsSphereAt:(Vector)position withRadius:(GLfloat)radius;

- (void) drawMessage;

- (void) drawWatermarkString:(NSString *)watermarkString;

// Used to draw subentities. Should be getting this from camera.
- (OOMatrix) viewMatrix;

- (id) entityForUniversalID:(OOUniversalID)u_id;

- (BOOL) addEntity:(Entity *) entity;
- (BOOL) removeEntity:(Entity *) entity;
- (void) ensureEntityReallyRemoved:(Entity *)entity;
- (void) removeAllEntitiesExceptPlayer;
- (void) removeDemoShips;

- (ShipEntity *) makeDemoShipWithRole:(NSString *)role spinning:(BOOL)spinning;

- (BOOL) isVectorClearFromEntity:(Entity *) e1 toDistance:(double)dist fromPoint:(HPVector) p2;
- (Entity*) hazardOnRouteFromEntity:(Entity *) e1 toDistance:(double)dist fromPoint:(HPVector) p2;
- (HPVector) getSafeVectorFromEntity:(Entity *) e1 toDistance:(double)dist fromPoint:(HPVector) p2;

- (ShipEntity *) addWreckageFrom:(ShipEntity *)ship withRole:(NSString *)wreckRole at:(HPVector)rpos scale:(GLfloat)scale lifetime:(GLfloat)lifetime;
- (void) addLaserHitEffectsAt:(HPVector)pos against:(ShipEntity *)target damage:(float)damage color:(OOColor *)color;
- (ShipEntity *) firstShipHitByLaserFromShip:(ShipEntity *)srcEntity inDirection:(OOWeaponFacing)direction offset:(Vector)offset gettingRangeFound:(GLfloat*)range_ptr;
- (Entity *) firstEntityTargetedByPlayer;
- (Entity *) firstEntityTargetedByPlayerPrecisely;

- (NSArray *) entitiesWithinRange:(double)range ofEntity:(Entity *)entity;
- (unsigned) countShipsWithRole:(NSString *)role inRange:(double)range ofEntity:(Entity *)entity;
- (unsigned) countShipsWithRole:(NSString *)role;
- (unsigned) countShipsWithPrimaryRole:(NSString *)role inRange:(double)range ofEntity:(Entity *)entity;
- (unsigned) countShipsWithPrimaryRole:(NSString *)role;
- (unsigned) countShipsWithScanClass:(OOScanClass)scanClass inRange:(double)range ofEntity:(Entity *)entity;


// General count/search methods. Pass range of -1 and entity of nil to search all of system.
- (unsigned) countEntitiesMatchingPredicate:(EntityFilterPredicate)predicate
								  parameter:(void *)parameter
									inRange:(double)range
								   ofEntity:(Entity *)entity;
- (unsigned) countShipsMatchingPredicate:(EntityFilterPredicate)predicate
							   parameter:(void *)parameter
								 inRange:(double)range
								ofEntity:(Entity *)entity;
- (NSMutableArray *) findEntitiesMatchingPredicate:(EntityFilterPredicate)predicate
										 parameter:(void *)parameter
										   inRange:(double)range
										  ofEntity:(Entity *)entity;
- (id) findOneEntityMatchingPredicate:(EntityFilterPredicate)predicate
							parameter:(void *)parameter;
- (NSMutableArray *) findShipsMatchingPredicate:(EntityFilterPredicate)predicate
									  parameter:(void *)parameter
										inRange:(double)range
									   ofEntity:(Entity *)entity;
- (NSMutableArray *) findVisualEffectsMatchingPredicate:(EntityFilterPredicate)predicate
									  parameter:(void *)parameter
										inRange:(double)range
									   ofEntity:(Entity *)entity;
- (id) nearestEntityMatchingPredicate:(EntityFilterPredicate)predicate
							parameter:(void *)parameter
					 relativeToEntity:(Entity *)entity;
- (id) nearestShipMatchingPredicate:(EntityFilterPredicate)predicate
						  parameter:(void *)parameter
				   relativeToEntity:(Entity *)entity;


- (OOTimeAbsolute) getTime;
- (OOTimeDelta) getTimeDelta;

- (void) findCollisionsAndShadows;
- (NSString*) collisionDescription;
- (void) dumpCollisions;

- (OOViewID) viewDirection;
- (void) setViewDirection:(OOViewID)vd;
- (void) enterGUIViewModeWithMouseInteraction:(BOOL)mouseInteraction;	// Use instead of setViewDirection:VIEW_GUI_DISPLAY

- (NSString *) soundNameForCustomSoundKey:(NSString *)key;
- (NSDictionary *) screenTextureDescriptorForKey:(NSString *)key;
- (void) setScreenTextureDescriptorForKey:(NSString *) key descriptor:(NSDictionary *)desc;

- (void) clearPreviousMessage;
- (void) setMessageGuiBackgroundColor:(OOColor *) some_color;
- (void) displayMessage:(NSString *) text forCount:(OOTimeDelta) count;
- (void) displayCountdownMessage:(NSString *) text forCount:(OOTimeDelta) count;
- (void) addDelayedMessage:(NSString *) text forCount:(OOTimeDelta) count afterDelay:(OOTimeDelta) delay;
- (void) addDelayedMessage:(NSDictionary *) textdict;
- (void) addMessage:(NSString *) text forCount:(OOTimeDelta) count;
- (void) addMessage:(NSString *) text forCount:(OOTimeDelta) count forceDisplay:(BOOL) forceDisplay;
- (void) addCommsMessage:(NSString *) text forCount:(OOTimeDelta) count;
- (void) addCommsMessage:(NSString *) text forCount:(OOTimeDelta) count andShowComms:(BOOL)showComms logOnly:(BOOL)logOnly;
- (void) showCommsLog:(OOTimeDelta) how_long;
- (void) showGUIMessage:(NSString *)text withScroll:(BOOL)scroll andColor:(OOColor *)selectedColor overDuration:(OOTimeDelta)how_long;

- (void) update:(OOTimeDelta)delta_t;

// Time Acelleration Factor. In deployment builds, this is always 1.0 and -setTimeAccelerationFactor: does nothing.
- (double) timeAccelerationFactor;
- (void) setTimeAccelerationFactor:(double)newTimeAccelerationFactor;

- (void) filterSortedLists;

///////////////////////////////////////

- (void) setGalaxyTo:(OOGalaxyID) g;
- (void) setGalaxyTo:(OOGalaxyID) g andReinit:(BOOL) forced;

- (void) setSystemTo:(OOSystemID) s;

- (OOSystemID) currentSystemID;

- (NSDictionary *) descriptions;
- (NSDictionary *) characters;
- (NSDictionary *) missiontext;
- (NSArray *) scenarios;
- (NSDictionary *) explosionSetting:(NSString *)explosion;

- (OOSystemDescriptionManager *) systemManager;

- (NSString *)descriptionForKey:(NSString *)key;	// String, or random item from array
- (NSString *)descriptionForArrayKey:(NSString *)key index:(unsigned)index;	// Indexed item from array
- (BOOL) descriptionBooleanForKey:(NSString *)key;	// Boolean from descriptions.plist, for configuration.

- (NSString *) keyForPlanetOverridesForSystem:(OOSystemID) s inGalaxy:(OOGalaxyID) g;
- (NSString *) keyForInterstellarOverridesForSystems:(OOSystemID) s1 :(OOSystemID) s2 inGalaxy:(OOGalaxyID) g;
- (NSDictionary *) generateSystemData:(OOSystemID) s;
- (NSDictionary *) generateSystemData:(OOSystemID) s useCache:(BOOL) useCache;
- (NSDictionary *) currentSystemData;	// Same as generateSystemData:systemSeed unless in interstellar space.

- (BOOL) inInterstellarSpace;

- (void) setSystemDataKey:(NSString*) key value:(NSObject*) object fromManifest:(NSString *)manifest;
- (void) setSystemDataForGalaxy:(OOGalaxyID) gnum planet:(OOSystemID) pnum key:(NSString *)key value:(id)object fromManifest:(NSString *)manifest forLayer:(OOSystemLayer)layer;
- (id) systemDataForGalaxy:(OOGalaxyID) gnum planet:(OOSystemID) pnum key:(NSString *)key;
- (NSArray *) systemDataKeysForGalaxy:(OOGalaxyID)gnum planet:(OOSystemID)pnum;
- (NSString *) getSystemName:(OOSystemID) sys;
- (NSString *) getSystemName:(OOSystemID) sys forGalaxy:(OOGalaxyID) gnum;
- (OOGovernmentID) getSystemGovernment:(OOSystemID) sys;
- (NSString *) getSystemInhabitants:(OOSystemID) sys;
- (NSString *) getSystemInhabitants:(OOSystemID) sys plural:(BOOL)plural;

- (NSPoint) coordinatesForSystem:(OOSystemID)s;
- (OOSystemID) findSystemFromName:(NSString *) sysName;

/**
 * Finds systems within range.  If range is greater than 7.0LY then only look within 7.0LY.
 */
- (NSMutableArray *) nearbyDestinationsWithinRange:(double) range;

- (OOSystemID) findNeighbouringSystemToCoords:(NSPoint) coords withGalaxy:(OOGalaxyID) gal;
- (OOSystemID) findConnectedSystemAtCoords:(NSPoint) coords withGalaxy:(OOGalaxyID) gal;
// old alias for findSystemNumberAtCoords
- (OOSystemID) findSystemAtCoords:(NSPoint) coords withGalaxy:(OOGalaxyID) gal;
- (OOSystemID) findSystemNumberAtCoords:(NSPoint) coords withGalaxy:(OOGalaxyID) gal includingHidden:(BOOL)hidden;
- (NSPoint) findSystemCoordinatesWithPrefix:(NSString *) p_fix;
- (NSPoint) findSystemCoordinatesWithPrefix:(NSString *) p_fix exactMatch:(BOOL) exactMatch;
- (BOOL*) systemsFound;
- (NSString*) systemNameIndex:(OOSystemID) index;
- (NSDictionary *) routeFromSystem:(OOSystemID) start toSystem:(OOSystemID) goal optimizedBy:(OORouteType) optimizeBy;
- (NSArray *) neighboursToSystem:(OOSystemID) system_number;

- (void) preloadPlanetTexturesForSystem:(OOSystemID)system;
- (void) preloadSounds;

- (NSDictionary *) globalSettings;

- (NSArray *) equipmentData;
- (OOCommodityMarket *) commodityMarket;

- (NSString *) timeDescription:(OOTimeDelta) interval;
- (NSString *) shortTimeDescription:(OOTimeDelta) interval;

- (void) loadStationMarkets:(NSArray *)marketData;
- (NSArray *) getStationMarkets;

- (NSArray *) shipsForSaleForSystem:(OOSystemID) s withTL:(OOTechLevelID) specialTL atTime:(OOTimeAbsolute) current_time;

/* Calculate base cost, before depreciation */
- (OOCreditsQuantity) tradeInValueForCommanderDictionary:(NSDictionary*) cmdr_dict;

- (NSString*) brochureDescriptionWithDictionary:(NSDictionary*) dict standardEquipment:(NSArray*) extras optionalEquipment:(NSArray*) options;

- (HPVector) getWitchspaceExitPosition;
- (Quaternion) getWitchspaceExitRotation;

- (HPVector) getSunSkimStartPositionForShip:(ShipEntity*) ship;
- (HPVector) getSunSkimEndPositionForShip:(ShipEntity*) ship;

- (NSArray*) listBeaconsWithCode:(NSString*) code;

- (void) allShipsDoScriptEvent:(jsid)event andReactToAIMessage:(NSString *)message;

///////////////////////////////////////

- (void) clearGUIs;

- (GuiDisplayGen *) gui;
- (GuiDisplayGen *) commLogGUI;
- (GuiDisplayGen *) messageGUI;

- (void) resetCommsLogColor;

- (void) setDisplayText:(BOOL) value;
- (BOOL) displayGUI;

- (void) setDisplayFPS:(BOOL) value;
- (BOOL) displayFPS;

- (void) setAutoSave:(BOOL) value;
- (BOOL) autoSave;

- (void) setWireframeGraphics:(BOOL) value;
- (BOOL) wireframeGraphics;

- (BOOL) reducedDetail;
- (void) setDetailLevel:(OOGraphicsDetail)value;
- (OOGraphicsDetail) detailLevel;
- (BOOL) useShaders;

- (void) handleOoliteException:(NSException *)ooliteException;

- (GLfloat)airResistanceFactor;
- (void) setAirResistanceFactor:(GLfloat)newFactor;

// speech routines
//
- (void) startSpeakingString:(NSString *) text;
//
- (void) stopSpeaking;
//
- (BOOL) isSpeaking;
//
#if OOLITE_ESPEAK
- (NSString *) voiceName:(unsigned int) index;
- (unsigned int) voiceNumber:(NSString *) name;
- (unsigned int) nextVoice:(unsigned int) index;
- (unsigned int) prevVoice:(unsigned int) index;
- (unsigned int) setVoice:(unsigned int) index withGenderM:(BOOL) isMale;
#endif
//
////

//autosave 
- (void) setAutoSaveNow:(BOOL) value;
- (BOOL) autoSaveNow;

- (int) framesDoneThisUpdate;
- (void) resetFramesDoneThisUpdate;

// True if textual pause message (as opposed to overlay) is being shown.
- (BOOL) pauseMessageVisible;
- (void) setPauseMessageVisible:(BOOL)value;

- (BOOL) permanentCommLog;
- (void) setPermanentCommLog:(BOOL)value;
- (void) setAutoCommLog:(BOOL)value;
- (BOOL) permanentMessageLog;
- (void) setPermanentMessageLog:(BOOL)value;
- (BOOL) autoMessageLogBg;
- (void) setAutoMessageLogBg:(BOOL)value;

- (BOOL) blockJSPlayerShipProps;
- (void) setBlockJSPlayerShipProps:(BOOL)value;

- (void) loadConditionScripts;
- (void) addConditionScripts:(NSEnumerator *)scripts;
- (OOJSScript *) getConditionScript:(NSString *)scriptname;

@end


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


// Only for use with string literals, and only for looking up strings.
// DESC() is deprecated in favour of OOExpandKey() except in known performance-
// critical contexts.
#define DESC(key)	(OOLookUpDescriptionPRIV(key ""))
#define DESC_PLURAL(key,count)	(OOLookUpPluralDescriptionPRIV(key "", count))

// Not for direct use.
NSComparisonResult populatorPrioritySort(id a, id b, void *context);
NSComparisonResult equipmentSort(id a, id b, void *context);
NSString *OOLookUpDescriptionPRIV(NSString *key);
NSString *OOLookUpPluralDescriptionPRIV(NSString *key, NSInteger count);


@interface OOSound (OOCustomSounds)

+ (id) soundWithCustomSoundKey:(NSString *)key;
- (id) initWithCustomSoundKey:(NSString *)key;

@end


@interface OOSoundSource (OOCustomSounds)

+ (id) sourceWithCustomSoundKey:(NSString *)key;
- (id) initWithCustomSoundKey:(NSString *)key;

- (void) playCustomSoundWithKey:(NSString *)key;

@end


NSString *OODisplayStringFromGovernmentID(OOGovernmentID government);
NSString *OODisplayStringFromEconomyID(OOEconomyID economy);
