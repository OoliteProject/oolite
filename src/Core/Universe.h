//
//  Universe.h
/*
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
#import "OOOpenGL.h"
#import "entities.h"
#import "GuiDisplayGen.h"

#define CROSSHAIR_SIZE			32.0

#define VIEW_FORWARD			0
#define VIEW_AFT				1
#define VIEW_PORT				2
#define VIEW_STARBOARD			3
#define VIEW_CUSTOM				7
#define VIEW_NONE				-1
#define VIEW_GUI_DISPLAY		100
#define VIEW_BREAK_PATTERN		200

#define UNITS_TONS			0
#define UNITS_KILOGRAMS		1
#define UNITS_GRAMS			2

#define DEMO_NO_DEMO		0
#define DEMO_FLY_IN			101
#define DEMO_SHOW_THING		102
#define DEMO_FLY_OUT		103

#define MARKET_NAME					0
#define MARKET_QUANTITY				1
#define MARKET_PRICE				2
#define MARKET_BASE_PRICE			3
#define MARKET_ECO_ADJUST_PRICE		4
#define MARKET_ECO_ADJUST_QUANTITY  5
#define MARKET_BASE_QUANTITY		6
#define MARKET_MASK_PRICE			7
#define MARKET_MASK_QUANTITY		8
#define MARKET_UNITS				9

#define EQUIPMENT_TECH_LEVEL_INDEX	0
#define EQUIPMENT_PRICE_INDEX		1
#define EQUIPMENT_SHORT_DESC_INDEX	2
#define EQUIPMENT_KEY_INDEX			3
#define EQUIPMENT_LONG_DESC_INDEX	4
#define EQUIPMENT_EXTRA_INFO_INDEX	5

#define MAX_MESSAGES		5

#define PROXIMITY_WARN_DISTANCE		10.0
#define PROXIMITY_WARN_DISTANCE2	100.0
#define PROXIMITY_AVOID_DISTANCE	10.0

#define SUN_SKIM_RADIUS_FACTOR		1.15470053838
#define SUN_SPARKS_RADIUS_FACTOR	2.0

#define KEY_TECHLEVEL				@"techlevel"
#define KEY_ECONOMY					@"economy"
#define KEY_GOVERNMENT				@"government"
#define KEY_POPULATION				@"population"
#define KEY_PRODUCTIVITY			@"productivity"
#define KEY_RADIUS					@"radius"
#define KEY_NAME					@"name"
#define KEY_INHABITANTS				@"inhabitants"
#define KEY_DESCRIPTION				@"description"
#define KEY_SHORT_DESCRIPTION		@"short_description"

#define KEY_CHANCE					@"chance"
#define KEY_PRICE					@"price"
#define KEY_OPTIONAL_EQUIPMENT		@"optional_equipment"
#define KEY_STANDARD_EQUIPMENT		@"standard_equipment"
#define KEY_EQUIPMENT_MISSILES			@"missiles"
#define KEY_EQUIPMENT_FORWARD_WEAPON	@"forward_weapon_type"
#define KEY_EQUIPMENT_EXTRAS			@"extras"
#define KEY_WEAPON_FACINGS			@"weapon_facings"

#define KEY_SCRIPT_ACTIONS			@"script_actions"
	// used by cargo-containers with CARGO_SCRIPT_ACTION when you scoop them, used by Stations when you dock with them, used during custom system set up too
#define KEY_LAUNCH_ACTIONS			@"launch_actions"
#define KEY_DEATH_ACTIONS			@"death_actions"
#define KEY_SETUP_ACTIONS			@"setup_actions"

#define SHIPYARD_KEY_ID				@"id"
#define SHIPYARD_KEY_SHIPDATA_KEY	@"shipdata_key"
#define SHIPYARD_KEY_SHIP			@"ship"
#define SHIPYARD_KEY_PRICE			@"price"
#define SHIPYARD_KEY_DESCRIPTION	@"description"

#define PLANETINFO_UNIVERSAL_KEY	@"universal"

#define MAX_ENTITY_UID				1000

#define	NUMBER_OF_STRICT_EQUIPMENT_ITEMS	16

#define	UNIVERSE_MAX_ENTITIES		2048

#define OOLITE_EXCEPTION_LOOPING		@"OoliteLoopingException"
#define OOLITE_EXCEPTION_SHIP_NOT_FOUND	@"OoliteShipNotFoundException"
#define OOLITE_EXCEPTION_FATAL			@"OoliteFatalException"

@class TextureStore, OpenGLSprite, GameController, ShipEntity, CollisionRegion;

extern int debug;

@interface Universe : NSObject
{
		@public
		// use a sorted list for drawing and other activities
		//
		Entity*					sortedEntities[UNIVERSE_MAX_ENTITIES];
		int						n_entities;
		int						cursor_row;
		
//		// collision optimisation sorted lists
		Entity					*x_list_start, *y_list_start, *z_list_start;
//		//
//		////
		
		// colors
		//
		GLfloat					sun_diffuse[4];
		GLfloat					sun_specular[4];
		GLfloat					stars_ambient[4];
		
		GLfloat					air_resist_factor;
	
		int						viewDirection;	// read only
		
		@protected
		MyOpenGLView			*gameView;
		TextureStore			*textureStore;
		
		#ifndef GNUSTEP
		NSSpeechSynthesizer*	speechSynthesizer;		// use this from OS X 10.3 onwards
		NSArray					*speechArray;
		#endif
		
		int						next_universal_id;
		Entity*					entity_for_uid[MAX_ENTITY_UID];
		
		//
		////
		
		NSLock					*recycleLock;
		NSMutableDictionary		*entityRecyclePool;

		NSMutableDictionary		*preloadedDataFiles;

		NSMutableArray			*entities;
				
		int						station;
		int						sun;
		int						planet;
		
		int						firstBeacon, lastBeacon;
		
		GLfloat					sky_clear_color[4];
		
		NSString				*currentMessage;
		
		GuiDisplayGen*			gui;
		GuiDisplayGen*			message_gui;
		GuiDisplayGen*			comm_log_gui;
		
		OpenGLSprite			*textDisplaySprite;
		BOOL					displayGUI;
		BOOL					displayCursor;
		
		BOOL					reducedDetail;
		
		BOOL					displayFPS;		
				
		double					universal_time;
		double					time_delta;
		double					ai_think_time;
		
		double					demo_stage_time;
		int						demo_stage;
		int						demo_ship_index;
		NSArray					*demo_ships;
		
		GLfloat					sun_center_position[4];
		
		BOOL					dumpCollisionInfo;
		
		NSDictionary			*shipdata;			// holds data on all ships available, loaded at initialisation
		NSDictionary			*shipyard;			// holds data on all ships for sale, loaded at initialisation
		
		NSDictionary			*commoditylists;	// holds data on commodities for various types of station, loaded at initialisation
		NSArray					*commoditydata;		// holds data on commodities extracted from commoditylists
		
		NSDictionary			*illegal_goods;		// holds the legal penalty for illicit commodities, loaded at initialisation
		NSDictionary			*descriptions;		// holds descriptive text for lots of stuff, loaded at initialisation
		NSDictionary			*customsounds;		// holds descriptive audio for lots of stuff, loaded at initialisation
		NSDictionary			*characters;		// holds descriptons of characters
		NSDictionary			*planetinfo;		// holds overrides for individual planets, keyed by "g# p#" where g# is the galaxy number 0..7 and p# the planet number 0..255
		NSDictionary			*missiontext;		// holds descriptive text for missions, loaded at initialisation
		NSArray					*equipmentdata;		// holds data on available equipment, loaded at initialisation
		
		Random_Seed				galaxy_seed;
		Random_Seed				system_seed;
		Random_Seed				target_system_seed;
		
		Random_Seed				systems[256];		// hold pregenerated universe info
		NSString*				system_names[256];		// hold pregenerated universe info
		BOOL					system_found[256];		// holds matches for input strings
		
		int						breakPatternCounter;
		
		ShipEntity				*demo_ship;
		
		StationEntity*			cachedStation;
		PlanetEntity*			cachedPlanet;
		PlanetEntity*			cachedSun;
		Entity*					cachedEntityZero;
		
		BOOL					strict;
		
		BOOL					no_update;
		
		NSMutableDictionary*	local_planetinfo_overrides;
		
		NSException*			exception;
		
		NSMutableArray*			activeWormholes;
		
		NSMutableArray*			characterPool;
		
		CollisionRegion*		universeRegion;

}

- (id) init;
- (void) dealloc;

- (BOOL) strict;
- (void) setStrict:(BOOL) value;

- (void) reinit;

- (int) obj_count;
- (void) obj_dump;

- (void) sleepytime: (id) thing;

- (void) set_up_universe_from_station;
- (void) set_up_universe_from_witchspace;
- (void) set_up_universe_from_misjump;
- (void) set_up_witchspace;
- (void) set_up_space;
- (void) setLighting;

- (void) populateSpaceFromActiveWormholes;
- (void) populateSpaceFromHyperPoint:(Vector) h1_pos toPlanetPosition:(Vector) p1_pos andSunPosition:(Vector) s1_pos;
- (int)	scatterAsteroidsAt:(Vector) spawnPos withVelocity:(Vector) spawnVel includingRockHermit:(BOOL) spawnHermit;
- (void) addShipWithRole:(NSString *) desc nearRouteOneAt:(double) route_fraction;
- (Vector) coordinatesForPosition:(Vector) pos withCoordinateSystem:(NSString *) system returningScalar:(GLfloat*) my_scalar;
- (NSString *) expressPosition:(Vector) pos inCoordinateSystem:(NSString *) system;
- (BOOL) addShipWithRole:(NSString *) desc nearPosition:(Vector) pos withCoordinateSystem:(NSString *) system;
- (BOOL) addShips:(int) howMany withRole:(NSString *) desc atPosition:(Vector) pos withCoordinateSystem:(NSString *) system;
- (BOOL) addShips:(int) howMany withRole:(NSString *) desc nearPosition:(Vector) pos withCoordinateSystem:(NSString *) system;
- (BOOL) addShips:(int) howMany withRole:(NSString *) desc nearPosition:(Vector) pos withCoordinateSystem:(NSString *) system withinRadius:(GLfloat) radius;
- (BOOL) addShips:(int) howMany withRole:(NSString *) desc intoBoundingBox:(BoundingBox) bbox;
- (BOOL) spawnShip:(NSString *) shipdesc;
- (void) witchspaceShipWithRole:(NSString *) desc;
- (void) spawnShipWithRole:(NSString *) desc near:(Entity *) entity;

- (void) set_up_break_pattern:(Vector) pos quaternion:(Quaternion) q;
- (void) game_over;

- (void) set_up_intro1;
- (void) set_up_intro2;
- (void) selectIntro2Previous;
- (void) selectIntro2Next;

- (StationEntity *) station;
- (PlanetEntity *) planet;
- (PlanetEntity *) sun;

- (void) resetBeacons;
- (ShipEntity *) firstBeacon;
- (ShipEntity *) lastBeacon;
- (void) setNextBeacon:(ShipEntity *) beaconShip;

- (GLfloat *) sky_clear_color;
- (void) setSky_clear_color:(GLfloat) red :(GLfloat) green :(GLfloat) blue :(GLfloat) alpha;

- (BOOL) breakPatternOver;
- (BOOL) breakPatternHide;

- (id) recycleOrDiscard:(Entity *) entity;
- (Entity *) recycledOrNew:(NSString *) classname;

- (NSMutableDictionary *) preloadedDataFiles;

- (ShipEntity *) getShipWithRole:(NSString *) desc;
- (ShipEntity *) getShip:(NSString *) desc;
- (NSDictionary *) getDictionaryForShip:(NSString *) desc;

- (int) maxCargoForShip:(NSString *) desc;

- (int) getPriceForWeaponSystemWithKey:(NSString *)weapon_key;

- (int) legal_status_of_manifest:(NSArray *)manifest;

- (NSArray *) getContainersOfPlentifulGoods:(int) how_many;
- (NSArray *) getContainersOfScarceGoods:(int) how_many;
- (NSArray *) getContainersOfDrugs:(int) how_many;
- (NSArray *) getContainersOfCommodity:(NSString*) commodity_name :(int) how_many;

- (int) getRandomCommodity;
- (int) getRandomAmountOfCommodity:(int) co_type;

- (int) commodityForName:(NSString *) co_name;
- (NSString *) nameForCommodity:(int) co_type;
- (int) unitsForCommodity:(int) co_type;
- (NSString *) describeCommodity:(int) co_type amount:(int) co_amount;

- (void) setGameView:(MyOpenGLView *)view;
- (MyOpenGLView *) gameView;
- (GameController *) gameController;

- (TextureStore *) textureStore;

- (void) drawFromEntity:(int) n;
- (void) drawCrosshairs;
- (void) drawMessage;

- (Entity *) entityZero;

- (Entity *) entityForUniversalID:(int)u_id;

BOOL maintainLinkedLists(Universe* uni);
- (BOOL) addEntity:(Entity *) entity;
- (BOOL) removeEntity:(Entity *) entity;
- (BOOL) removeWithoutRecyclingEntity:(Entity *) entity;
- (void) removeAllEntitiesExceptPlayer:(BOOL) restore;
- (void) removeDemoShips;

- (BOOL) isVectorClearFromEntity:(Entity *) e1 toDistance:(double)dist fromPoint:(Vector) p2;
- (Vector) getSafeVectorFromEntity:(Entity *) e1 toDistance:(double)dist fromPoint:(Vector) p2;

- (int) getFirstEntityHitByLaserFromEntity:(Entity *) e1 inView:(int) viewdir offset:(Vector) offset rangeFound:(GLfloat*)range_ptr;
- (int) getFirstEntityTargettedByPlayer:(PlayerEntity*) player;

- (NSArray *) getEntitiesWithinRange:(double) range1 ofEntity:(Entity *) e1;
- (int) countShipsWithRole:(NSString *) desc inRange:(double) range1 ofEntity:(Entity *)e1;
- (int) countShipsWithRole:(NSString *) desc;
- (void) sendShipsWithRole:(NSString *) desc messageToAI:(NSString *) ms;

- (double) getTime;
- (double) getTimeDelta;

- (void) findCollisionsAndShadows;
- (NSString*) collisionDescription;
- (void) dumpCollisions;

- (void) setViewDirection:(int) vd;
- (int) viewDir;

- (BOOL) playCustomSound:(NSString*)key;
- (BOOL) stopCustomSound:(NSString*)key;
- (BOOL) isPlayingCustomSound:(NSString*)key;

- (void) clearPreviousMessage;
- (void) setMessageGuiBackgroundColor:(OOColor *) some_color;
- (void) displayMessage:(NSString *) text forCount:(int) count;
- (void) displayCountdownMessage:(NSString *) text forCount:(int) count;
- (void) addDelayedMessage:(NSString *) text forCount:(int) count afterDelay:(double) delay;
- (void) addDelayedMessage:(NSDictionary *) textdict;
- (void) addMessage:(NSString *) text forCount:(int) count;
- (void) addCommsMessage:(NSString *) text forCount:(int) count;
- (void) showCommsLog:(double) how_long;

- (void) update:(double) delta_t;

- (void) filterSortedLists;

///////////////////////////////////////

- (void) setGalaxy_seed:(Random_Seed) gal_seed;

- (void) setSystemTo:(Random_Seed) s_seed;

- (Random_Seed) systemSeed;
- (Random_Seed) systemSeedForSystemNumber:(int) n;
- (Random_Seed) systemSeedForSystemName:(NSString*) sysname;

- (NSDictionary *) shipyard;
- (NSDictionary *) descriptions;
- (NSDictionary *) characters;
- (NSDictionary *) missiontext;

- (NSString *) keyForPlanetOverridesForSystemSeed:(Random_Seed) s_seed inGalaxySeed:(Random_Seed) g_seed;
- (NSString *) keyForInterstellarOverridesForSystemSeeds:(Random_Seed) s_seed1 :(Random_Seed) s_seed2 inGalaxySeed:(Random_Seed) g_seed;
- (NSDictionary *) generateSystemData:(Random_Seed) system_seed;
- (NSDictionary *) currentSystemData;
- (void) setSystemDataKey:(NSString*) key value:(NSObject*) object;
- (void) setSystemDataForGalaxy:(int) gnum planet:(int) pnum key:(NSString*) key value:(NSObject*) object;
- (NSString *) getSystemName:(Random_Seed) s_seed;
- (NSString *) getSystemInhabitants:(Random_Seed) s_seed;
- (NSString *) generateSystemName:(Random_Seed) system_seed;
- (NSString *) generatePhoneticSystemName:(Random_Seed) s_seed;
- (NSString *) generateSystemInhabitants:(Random_Seed) s_seed plural:(BOOL)plural;
- (Random_Seed) findSystemAtCoords:(NSPoint) coords withGalaxySeed:(Random_Seed) gal_seed;

+ (NSString*) systemSeedString:(Random_Seed) s;
- (NSArray*) nearbyDestinationsWithinRange:(double) range;
- (Random_Seed) findNeighbouringSystemToCoords:(NSPoint) coords withGalaxySeed:(Random_Seed) gal_seed;
- (Random_Seed) findConnectedSystemAtCoords:(NSPoint) coords withGalaxySeed:(Random_Seed) gal_seed;
- (int) findSystemNumberAtCoords:(NSPoint) coords withGalaxySeed:(Random_Seed) gal_seed;
- (NSPoint) findSystemCoordinatesWithPrefix:(NSString *) p_fix withGalaxySeed:(Random_Seed) gal_seed;
- (BOOL*) systems_found;
- (NSString*) systemNameIndex:(int) index;
- (NSDictionary *) routeFromSystem:(int) start ToSystem:(int) goal;
- (NSArray *) neighboursToSystem:(int) system_number;

- (NSMutableDictionary*) local_planetinfo_overrides;
- (void) setLocal_planetinfo_overrides:(NSDictionary*) dict;

- (NSDictionary*) planetinfo;

- (NSArray *) equipmentdata;
- (NSDictionary *) commoditylists;
- (NSArray *) commoditydata;

- (BOOL) generateEconomicDataWithEconomy:(int) economy andRandomFactor:(int) random_factor;
- (NSArray *) commodityDataForEconomy:(int) economy andStation:(StationEntity *)some_station andRandomFactor:(int) random_factor;

double estimatedTimeForJourney(double distance, int hops);

- (NSArray *) passengersForSystem:(Random_Seed) s_seed atTime:(double) current_time;
- (NSString *) timeDescription:(double) interval;
- (NSString *) shortTimeDescription:(double) interval;
- (NSArray *) contractsForSystem:(Random_Seed) s_seed atTime:(double) current_time;

- (NSArray *) shipsForSaleForSystem:(Random_Seed) s_seed atTime:(double) current_time;
NSComparisonResult compareName( id dict1, id dict2, void * context);
NSComparisonResult comparePrice( id dict1, id dict2, void * context);
- (int) tradeInValueForCommanderDictionary:(NSDictionary*) cmdr_dict;
- (int) weaponForEquipmentKey:(NSString*) weapon_string;
- (NSString*) equipmentKeyForWeapon:(int) weapon;
- (NSString*) brochureDescriptionWithDictionary:(NSDictionary*) dict standardEquipment:(NSArray*) extras optionalEquipment:(NSArray*) options;

- (NSString *) generateSystemDescription:(Random_Seed) s_seed;
- (NSString *) expandDescription:(NSString *) desc forSystem:(Random_Seed)s_seed;
- (NSString *) expandDescriptionWithLocals:(NSString *) desc forSystem:(Random_Seed)s_seed withLocalVariables:(NSDictionary *)locals;
- (NSString *) getRandomDigrams;

- (Vector) getWitchspaceExitPosition;
- (Quaternion) getWitchspaceExitRotation;

- (Vector) getSunSkimStartPositionForShip:(ShipEntity*) ship;
- (Vector) getSunSkimEndPositionForShip:(ShipEntity*) ship;

- (void) allShipAIsReactToMessage:(NSString*) message;

///////////////////////////////////////

- (void) clearGUIs;

- (GuiDisplayGen *) gui;
- (GuiDisplayGen *) comm_log_gui;

- (void) resetCommsLogColor;

- (void) setDisplayCursor:(BOOL) value;
- (BOOL) displayCursor;

- (void) setDisplayText:(BOOL) value;
- (BOOL) displayGUI;

- (void) setDisplayFPS:(BOOL) value;
- (BOOL) displayFPS;

- (void) setReducedDetail:(BOOL) value;
- (BOOL) reducedDetail;

- (void) handleOoliteException:(NSException*) ooliteException;

// speech routines
//
- (void) startSpeakingString:(NSString *) text;
//
- (void) stopSpeaking;
//
- (BOOL) isSpeaking;
//
////

@end
