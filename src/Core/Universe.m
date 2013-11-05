/*

Universe.m

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


#import "OOOpenGL.h"
#import "Universe.h"
#import "MyOpenGLView.h"
#import "GameController.h"
#import "ResourceManager.h"
#import "AI.h"
#import "GuiDisplayGen.h"
#import "HeadUpDisplay.h"
#import "OOSound.h"
#import "OOColor.h"
#import "OOCacheManager.h"
#import "OOStringExpander.h"
#import "OOStringParsing.h"
#import "OOCollectionExtractors.h"
#import "OOConstToString.h"
#import "OOOpenGLExtensionManager.h"
#import "OOCPUInfo.h"
#import "OOMaterial.h"
#import "OOTexture.h"
#import "OORoleSet.h"
#import "OOShipGroup.h"

#import "Octree.h"
#import "CollisionRegion.h"
#import "OOGraphicsResetManager.h"
#import "OODebugSupport.h"
#import "OOEntityFilterPredicate.h"

#import "OOCharacter.h"
#import "OOShipRegistry.h"
#import "OOProbabilitySet.h"
#import "OOEquipmentType.h"

#import "PlayerEntity.h"
#import "PlayerEntityContracts.h"
#import "PlayerEntityScriptMethods.h"
#import "StationEntity.h"
#import "DockEntity.h"
#import "SkyEntity.h"
#import "DustEntity.h"
#import "OOPlanetEntity.h"
#import "OOVisualEffectEntity.h"
#import "OOWaypointEntity.h"
#import "OOSunEntity.h"
#import "WormholeEntity.h"
#import "OOBreakPatternEntity.h"
#import "ShipEntityAI.h"
#import "ProxyPlayerEntity.h"
#import "OORingEffectEntity.h"
#import "OOLightParticleEntity.h"
#import "OOFlashEffectEntity.h"
#import "OOExplosionCloudEntity.h"

#import "OOMusicController.h"
#import "OOAsyncWorkManager.h"
#import "OODebugFlags.h"
#import "OOLoggingExtended.h"
#import "OOJSEngineTimeManagement.h"
#import "OOJoystickManager.h"
#import "OOScriptTimer.h"
#import "OOJSScript.h"
#import "OOJSFrameCallbacks.h"
#import "OOJSPopulatorDefinition.h"

#if OO_LOCALIZATION_TOOLS
#import "OOConvertSystemDescriptions.h"
#endif

#if OOLITE_ESPEAK
#include <espeak/speak_lib.h>
#endif


enum
{
	DEMO_FLY_IN			= 101,
	DEMO_SHOW_THING,
	DEMO_FLY_OUT
};


#define MAX_NUMBER_OF_ENTITIES				200
#define STANDARD_STATION_ROLL				0.4
// currently twice scanner radius
#define LANE_WIDTH			51200.0

static NSString * const kOOLogUniversePopulate				= @"universe.populate";
static NSString * const kOOLogUniversePopulateError			= @"universe.populate.error";
static NSString * const kOOLogUniversePopulateWitchspace	= @"universe.populate.witchspace";
static NSString * const kOOLogEntityVerificationError		= @"entity.linkedList.verify.error";
static NSString * const kOOLogEntityVerificationRebuild		= @"entity.linkedList.verify.rebuild";
static NSString * const kOOLogFoundBeacon					= @"beacon.list";


Universe *gSharedUniverse = nil;

extern Entity *gOOJSPlayerIfStale;
Entity *gOOJSPlayerIfStale = nil;


static BOOL MaintainLinkedLists(Universe* uni);
OOINLINE BOOL EntityInRange(HPVector p1, Entity *e2, float range);

static OOComparisonResult compareName(id dict1, id dict2, void * context);
static OOComparisonResult comparePrice(id dict1, id dict2, void * context);

/* TODO: route calculation is really slow - find a way to safely enable this */
#undef CACHE_ROUTE_FROM_SYSTEM_RESULTS

@interface RouteElement: NSObject
{
@private
	OOSystemID _location, _parent;
	double _cost, _distance, _time;
}

+ (instancetype) elementWithLocation:(OOSystemID) location parent:(OOSystemID)parent cost:(double) cost distance:(double) distance time:(double) time;
- (OOSystemID) parent;
- (OOSystemID) location;
- (double) cost;
- (double) distance;
- (double) time;

@end

@implementation RouteElement

+ (instancetype) elementWithLocation:(OOSystemID) location parent:(OOSystemID) parent cost:(double) cost distance:(double) distance time:(double) time
{
	RouteElement *r = [[RouteElement alloc] init];
	
	r->_location = location;
	r->_parent = parent;
	r->_cost = cost;
	r->_distance = distance;
	r->_time = time;
	
	return [r autorelease];
}

- (OOSystemID) parent { return _parent; }
- (OOSystemID) location { return _location; }
- (double) cost { return _cost; }
- (double) distance { return _distance; }
- (double) time { return _time; }

@end


@interface Universe (OOPrivate)

- (BOOL) doRemoveEntity:(Entity *)entity;
- (void) preloadSounds;
- (void) setUpSettings;
- (void) setUpCargoPods;
- (void) setUpInitialUniverse;
- (HPVector) fractionalPositionFrom:(HPVector)point0 to:(HPVector)point1 withFraction:(double)routeFraction;

- (void) populateSpaceFromActiveWormholes;

- (NSString *)chooseStringForKey:(NSString *)key inDictionary:(NSDictionary *)dictionary;

#if OO_LOCALIZATION_TOOLS
#if DEBUG_GRAPHVIZ
- (void) dumpDebugGraphViz;
- (void) dumpSystemDescriptionGraphViz;
#endif
- (void) addNumericRefsInString:(NSString *)string toGraphViz:(NSMutableString *)graphViz fromNode:(NSString *)fromNode nodeCount:(NSUInteger)nodeCount;
- (void) runLocalizationTools;
#endif

#if NEW_PLANETS
- (void) prunePreloadingPlanetMaterials;
#endif

- (BOOL) reinitAndShowDemo:(BOOL) showDemo strictChanged:(BOOL) strictChanged;

// Set shader effects level without logging or triggering a reset -- should only be used directly during startup.
- (void) setShaderEffectsLevelDirectly:(OOShaderSetting)value;

- (void) setFirstBeacon:(Entity <OOBeaconEntity> *)beacon;
- (void) setLastBeacon:(Entity <OOBeaconEntity> *)beacon;

- (void) verifyDescriptions;
- (void) loadDescriptions;

- (void) verifyEntitySessionIDs;
- (float) randomDistanceWithinScanner;
- (Vector) randomPlaceWithinScannerFrom:(Vector)pos alongRoute:(Vector)route withOffset:(double)offset;

@end


@implementation Universe

// Flags needed when JS reset fails.
static int JSResetFlags = 0;


// track the position and status of the lights
static BOOL		object_light_on = NO;
static BOOL		demo_light_on = NO;
static			GLfloat sun_off[4] = {0.0, 0.0, 0.0, 1.0};
static GLfloat	demo_light_position[4] = { DEMO_LIGHT_POSITION, 1.0 };

#define DOCKED_AMBIENT_LEVEL	0.2f	// Was 0.05, 'temporarily' set to 0.2.
#define DOCKED_ILLUM_LEVEL		0.7f
static GLfloat	docked_light_ambient[4]	= { DOCKED_AMBIENT_LEVEL, DOCKED_AMBIENT_LEVEL, DOCKED_AMBIENT_LEVEL, 1.0f };
static GLfloat	docked_light_diffuse[4]	= { DOCKED_ILLUM_LEVEL, DOCKED_ILLUM_LEVEL, DOCKED_ILLUM_LEVEL, 1.0f };	// white
static GLfloat	docked_light_specular[4]	= { DOCKED_ILLUM_LEVEL, DOCKED_ILLUM_LEVEL, DOCKED_ILLUM_LEVEL * 0.75f, (GLfloat) 1.0f };	// yellow-white

// Weight of sun in ambient light calculation. 1.0 means only sun's diffuse is used for ambient, 0.0 means only sky colour is used.
// TODO: considering the size of the sun and the number of background stars might be worthwhile. -- Ahruman 20080322
#define SUN_AMBIENT_INFLUENCE		0.75


- (id) initWithGameView:(MyOpenGLView *)inGameView
{	
	PlayerEntity	*player = nil;
	
	if (gSharedUniverse != nil)
	{
		[self release];
		[NSException raise:NSInternalInconsistencyException format:@"%s: expected only one Universe to exist at a time.", __PRETTY_FUNCTION__];
	}
	
	OO_DEBUG_PROGRESS(@"Universe initWithGameView:");
	
	self = [super init];
	if (self == nil)  return nil;
	
	_doingStartUp = YES;
	OOInitReallyRandom([NSDate timeIntervalSinceReferenceDate] * 1e9);
	
	NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
	
	strict = [prefs oo_boolForKey:@"strict-gameplay" defaultValue:NO];
	
	[self setGameView:inGameView];
	gSharedUniverse = self;
	
	allPlanets = [[NSMutableArray alloc] init];
	allStations = [[NSMutableSet alloc] init];
	
	OOCPUInfoInit();
	[OOJoystickManager sharedStickHandler];
	
	// init OpenGL extension manager (must be done before any other threads might use it)
	[OOOpenGLExtensionManager sharedManager];
	[self setShaderEffectsLevelDirectly:[prefs oo_intForKey:@"shader-mode"
											   defaultValue:[[OOOpenGLExtensionManager sharedManager] defaultShaderSetting]]];
	
	[OOMaterial setUp];
	
	// Preload cache
	[OOCacheManager sharedCache];
	
#if OOLITE_SPEECH_SYNTH
	OOLog(@"speech.synthesis", @"Spoken messages are %@.", ([prefs oo_boolForKey:@"speech_on" defaultValue:NO] ? @"on" :@"off"));
#endif
	
	// init the Resource Manager
	[ResourceManager setUseAddOns:!strict];	// also logs the paths if changed
	//[ResourceManager paths];	// called inside setUseAddOns...
	
	// Set up the internal game strings
	[self loadDescriptions];
	// DESC expansion is now possible!
	
	reducedDetail = [prefs oo_boolForKey:@"reduced-detail-graphics" defaultValue:NO];
	autoSave = [prefs oo_boolForKey:@"autosave" defaultValue:NO];
	wireframeGraphics = [prefs oo_boolForKey:@"wireframe-graphics" defaultValue:NO];
	doProcedurallyTexturedPlanets = [prefs oo_boolForKey:@"procedurally-textured-planets" defaultValue:YES];
	
	// Set up speech synthesizer.
#if OOLITE_SPEECH_SYNTH
#if OOLITE_MAC_OS_X
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0),
	^{
		/*
			NSSpeechSynthesizer can take over a second on an SSD and several
			seconds on an HDD for a cold start, and a third of a second upward
			for a warm start. There are no particular thread safety consider-
			ations documented for NSSpeechSynthesizer, so I'm assuming the
			default one-thread-at-a-time access rule applies.
			-- Ahruman 2012-09-13
		*/
		OOLog(@"speech.setup.begin", @"Starting to set up speech synthesizer.");
		NSSpeechSynthesizer *synth = [[NSSpeechSynthesizer alloc] init];
		OOLog(@"speech.setup.end", @"Finished setting up speech synthesizer.");
		speechSynthesizer = synth;
	});
#elif OOLITE_ESPEAK
	espeak_Initialize(AUDIO_OUTPUT_PLAYBACK, 100, NULL, 0);
	espeak_SetParameter(espeakPUNCTUATION, espeakPUNCT_NONE, 0);
	espeak_voices = espeak_ListVoices(NULL);
	for (espeak_voice_count = 0;
	     espeak_voices[espeak_voice_count];
	     ++espeak_voice_count)
		/**/;
#endif
#endif
	
	[[GameController sharedController] logProgress:DESC(@"loading-ships")];
	// Load ship data
	
	[OOShipRegistry sharedRegistry];
	
	entities = [[NSMutableArray arrayWithCapacity:MAX_NUMBER_OF_ENTITIES] retain];
	
	[[GameController sharedController] logProgress:OOExpandKeyRandomized(@"loading-miscellany")];
	
	// this MUST have the default no. of rows else the GUI_ROW macros in PlayerEntity.h need modification
	gui = [[GuiDisplayGen alloc] init]; // alloc retains
	comm_log_gui = [[GuiDisplayGen alloc] init]; // alloc retains
	
	localPlanetInfoOverrides = [[NSMutableDictionary alloc] initWithCapacity:8];	
	
	missiontext = [[ResourceManager dictionaryFromFilesNamed:@"missiontext.plist" inFolder:@"Config" andMerge:YES] retain];
	
	demo_ships = [[OOShipRegistry sharedRegistry] demoShipKeys];

	waypoints = [[NSMutableDictionary alloc] init];
	
	[self setUpSettings];
	
	[self preloadSounds];	// Must be after setUpSettings.
	
	// Preload particle effect textures:
	[OOLightParticleEntity setUpTexture];
	[OOFlashEffectEntity setUpTexture];
	[OOExplosionCloudEntity setUpTexture];
	
	// set up cargopod templates
	[self setUpCargoPods];

	player = [PlayerEntity sharedPlayer];
	[player deferredInit];
	[self addEntity:player];
	
	[player setStatus:STATUS_START_GAME];
	[player setShowDemoShips: YES];
	
	[self setUpInitialUniverse];
	
	universeRegion = [[CollisionRegion alloc] initAsUniverse];
	entitiesDeadThisUpdate = [[NSMutableSet alloc] init];
	framesDoneThisUpdate = 0;
	
	[[GameController sharedController] logProgress:DESC(@"initializing-debug-support")];
	OOInitDebugSupport();
	
	[[GameController sharedController] logProgress:DESC(@"running-scripts")];
	[player completeSetUp];
	[self populateNormalSpace];
	
#if OO_LOCALIZATION_TOOLS
	[self runLocalizationTools];
#if DEBUG_GRAPHVIZ
	[self dumpDebugGraphViz];
#endif
#endif
	
	[player startUpComplete];
	_doingStartUp = NO;
	
	return self;
}


- (void) dealloc
{
	gSharedUniverse = nil;
	
	[currentMessage release];
	
	[gui release];
	[message_gui release];
	[comm_log_gui release];
	
	[entities release];
	
	[commodityLists release];
	[commodityData release];
	
	[illegalGoods release];
	[_descriptions release];
	[characters release];
	[customSounds release];
	[planetInfo release];
	[missiontext release];
	[equipmentData release];
	[demo_ships release];
	[autoAIMap release];
	[screenBackgrounds release];
	[gameView release];
	[populatorSettings release];
	[system_repopulator release];
	[allPlanets release];
	[allStations release];
	
	[localPlanetInfoOverrides release];
	[activeWormholes release];				
	[characterPool release];
	[universeRegion release];
	[cargoPods release];

	DESTROY(_firstBeacon);
	DESTROY(_lastBeacon);
	DESTROY(waypoints);
	
	unsigned i;
	for (i = 0; i < 256; i++)  [system_names[i] release];
	
	[entitiesDeadThisUpdate release];
	
	[[OOCacheManager sharedCache] flush];
	
#if OOLITE_SPEECH_SYNTH
	[speechArray release];
#if OOLITE_MAC_OS_X
	[speechSynthesizer release];
#elif OOLITE_ESPEAK
	espeak_Cancel();
#endif
#endif
	[conditionScripts release];
	
	[super dealloc];
}


- (NSUInteger) sessionID
{
	return _sessionID;
}


- (BOOL) doingStartUp
{
	return _doingStartUp;
}


- (BOOL) doProcedurallyTexturedPlanets
{
	return doProcedurallyTexturedPlanets;
}


- (void) setDoProcedurallyTexturedPlanets:(BOOL) value
{
	doProcedurallyTexturedPlanets = !!value;	// ensure yes or no
	[[NSUserDefaults standardUserDefaults] setBool:doProcedurallyTexturedPlanets forKey:@"procedurally-textured-planets"];
}


/* From 1.79, "strict mode" is "no OXPs mode" as a useful debug tool,
 * nothing else */
- (BOOL) strict
{
	return strict;
}


- (BOOL) setStrict:(BOOL)value
{
	return [self setStrict:value fromSaveGame:NO];
}


- (BOOL) setStrict:(BOOL) value fromSaveGame:(BOOL) saveGame
{
	if (strict == value)  return YES;
	
	strict = !!value;
	[[NSUserDefaults standardUserDefaults] setBool:strict forKey:@"strict-gameplay"];
	return [self reinitAndShowDemo:!saveGame strictChanged:YES];
}


- (void) reinitAndShowDemo:(BOOL) showDemo
{
	[self reinitAndShowDemo:showDemo strictChanged:NO];
}


- (NSUInteger) entityCount
{
	return [entities count];
}


#ifndef NDEBUG
- (void) debugDumpEntities
{
	int				i;
	int				show_count = n_entities;
	
	if (!OOLogWillDisplayMessagesInClass(@"universe.objectDump"))  return;
	
	OOLog(@"universe.objectDump", @"DEBUG: Entity Dump - [entities count] = %lu,\tn_entities = %u", [entities count], n_entities);
	
	OOLogIndent();
	for (i = 0; i < show_count; i++)
	{
		OOLog(@"universe.objectDump", @"Ent:%4u  %@", i, [sortedEntities[i] descriptionForObjDump]);
	}
	OOLogOutdent();
	
	if ([entities count] != n_entities)
	{
		OOLog(@"universe.objectDump", @"entities = %@", [entities description]);
	}
}


- (NSArray *) entityList
{
	return [NSArray arrayWithArray:entities];
}
#endif


- (void) pauseGame
{
	// deal with the machine going to sleep, or player pressing 'p'.
	PlayerEntity 	*player = PLAYER;
	
	[self setPauseMessageVisible:NO];
	
	if ([player status] == STATUS_DOCKED)
	{
		if ([gui setForegroundTextureKey:@"paused_docked_overlay"])
		{
			[gui drawGUI:1.0 drawCursor:NO];
		}
		else
		{
			[self setPauseMessageVisible:YES];
			[self addMessage:[NSString stringWithFormat:DESC(@"game-paused-docked-@"),[PLAYER keyBindingDescription:@"key_pausebutton"]] forCount:1.0];
		}
	}
	else
	{
		if ([player guiScreen] != GUI_SCREEN_MAIN && [gui setForegroundTextureKey:@"paused_overlay"])
		{
			[gui drawGUI:1.0 drawCursor:NO];
		}
		else
		{
			[self setPauseMessageVisible:YES];
			[self addMessage:[NSString stringWithFormat:DESC(@"game-paused-@"),[PLAYER keyBindingDescription:@"key_pausebutton"]] forCount:1.0];
		}
	}
	
	[[self gameController] setGamePaused:YES];
}


- (void) carryPlayerOn:(StationEntity*)carrier inWormhole:(WormholeEntity*)wormhole
{
		PlayerEntity	*player = PLAYER;
		Random_Seed dest = [wormhole destination];

		[player setWormhole:wormhole];
		[player addScannedWormhole:wormhole];

		ShipScriptEventNoCx(player, "shipWillEnterWitchspace", OOJSSTR("carried"));
		
		[self allShipsDoScriptEvent:OOJSID("playerWillEnterWitchspace") andReactToAIMessage:@"PLAYER WITCHSPACE"];

		ranrot_srand((unsigned int)[[NSDate date] timeIntervalSince1970]);	// seed randomiser by time
		[player setRandom_factor:(ranrot_rand() & 255)];						// random factor for market values is reset

// misjump on wormhole sets correct travel time if needed
		[player addToAdjustTime:[wormhole travelTime]];
// clear old entities
		[self removeAllEntitiesExceptPlayer];

// should we add wear-and-tear to the player ship if they're not doing
// the jump themselves? Left out for now. - CIM

		if (![wormhole withMisjump])
		{
			[player setSystem_seed:dest];
			[self setSystemTo: dest];
			
			[self setUpSpace];
			[self populateNormalSpace];
			[player setBounty:([player legalStatus]/2) withReason:kOOLegalStatusReasonNewSystem];
			if ([player random_factor] < 8) [player erodeReputation];		// every 32 systems or so, dro
		}
		else
		{
			[player setGalaxyCoordinates:[wormhole destinationCoordinates]];

			[self setUpWitchspaceBetweenSystem:[wormhole origin] andSystem:[wormhole destination]];

			if (randf() < 0.1) [player erodeReputation];		// once every 10 misjumps - should be much rarer than successful jumps!
		}
		// which will kick the ship out of the wormhole with the
		// player still aboard
		[wormhole disgorgeShips];

		//reset atmospherics in case carrier was in atmosphere
		[UNIVERSE setSkyColorRed:0.0f		// back to black
											 green:0.0f
												blue:0.0f
											 alpha:0.0f];

		[self setWitchspaceBreakPattern:YES];
		[player doScriptEvent:OOJSID("shipWillExitWitchspace")];
		[player doScriptEvent:OOJSID("shipExitedWitchspace")];
		[player setWormhole:nil];

}


- (void) setUpUniverseFromStation
{
	if (![self sun])
	{
		// we're in witchspace...		
		
		PlayerEntity	*player = PLAYER;
		StationEntity	*dockedStation = [player dockedStation];
		NSPoint			coords = [player galaxy_coordinates];
		// check the nearest system
		Random_Seed s_seed = [self findSystemAtCoords:coords withGalaxySeed:[player galaxy_seed]];
		BOOL interstel =[dockedStation interstellarUndockingAllowed];// && (s_seed.d != coords.x || s_seed.b != coords.y); - Nikos 20110623: Do we really need the commented out check?
		
		// remove everything except the player and the docked station
		if (dockedStation && !interstel)
		{	// jump to the nearest system
			[player setSystem_seed:s_seed];
			closeSystems = nil;
			[self setSystemTo: s_seed];
			int index = 0;
			while ([entities count] > 2)
			{
				Entity *ent = [entities objectAtIndex:index];
				if ((ent != player)&&(ent != dockedStation))
				{
					if (ent->isStation)  // clear out queues
						[(StationEntity *)ent clear];
					[self removeEntity:ent];
				}
				else
				{
					index++;	// leave that one alone
				}
			}
		}
		else
		{
			if (dockedStation == nil)  [self removeAllEntitiesExceptPlayer];	// get rid of witchspace sky etc. if still extant
		}
		
		if (!dockedStation || !interstel) 
		{
			[self setUpSpace];	// launching from station that jumped from interstellar space to normal space.
			[self populateNormalSpace];
			if (dockedStation)
			{
				if ([dockedStation maxFlightSpeed] > 0) // we are a carrier: exit near the WitchspaceExitPosition
				{
					float		d1 = [self randomDistanceWithinScanner];
					HPVector		pos = [UNIVERSE getWitchspaceExitPosition];		// no need to reset the PRNG
					Quaternion	q1;
					
					quaternion_set_random(&q1);
					if (abs((int)d1) < 2750)	
					{
						d1 += ((d1 > 0.0)? 2750.0f: -2750.0f); // no closer than 2750m. Carriers are bigger than player ships.
					}
					Vector		v1 = vector_forward_from_quaternion(q1);
					pos.x += v1.x * d1; // randomise exit position
					pos.y += v1.y * d1;
					pos.z += v1.z * d1;
					
					[dockedStation setPosition: pos];
				}
				[self setWitchspaceBreakPattern:YES];
				[player doScriptEvent:OOJSID("shipWillExitWitchspace")];
				[player doScriptEvent:OOJSID("shipExitedWitchspace")];
			}
		}
	}
	
	if(!autoSaveNow) [self setViewDirection:VIEW_FORWARD];
	displayGUI = NO;
	
	//reset atmospherics in case we ejected while we were in the atmophere
	[UNIVERSE setSkyColorRed:0.0f		// back to black
					   green:0.0f
						blue:0.0f
					   alpha:0.0f];
}


- (void) setUpUniverseFromWitchspace
{
	PlayerEntity		*player;
	
	//
	// check the player is still around!
	//
	if ([entities count] == 0)
	{
		/*- the player ship -*/
		player = [[PlayerEntity alloc] init];	// alloc retains!
		
		[self addEntity:player];
		
		/*--*/
	}
	else
	{
		player = [PLAYER retain];	// retained here
	}
	
	[self setUpSpace];
	[self populateNormalSpace];
	
	[player leaveWitchspace];
	[player release];											// released here
	
	[self setViewDirection:VIEW_FORWARD];
	
	[comm_log_gui printLongText:[NSString stringWithFormat:@"%@ %@", [self getSystemName:system_seed], [player dial_clock_adjusted]]
		align:GUI_ALIGN_CENTER color:[OOColor whiteColor] fadeTime:0 key:nil addToArray:[player commLog]];
	
	displayGUI = NO;
}


- (void) setUpUniverseFromMisjump
{
	PlayerEntity		*player;
	
	//
	// check the player is still around!
	//
	if ([entities count] == 0)
	{
		/*- the player ship -*/
		player = [[PlayerEntity alloc] init];	// alloc retains!
		
		[self addEntity:player];
		
		/*--*/
	}
	else
	{
		player = [PLAYER retain];	// retained here
	}
	
	[self setUpWitchspace];
	
	[player leaveWitchspace];
	[player release];											// released here
	
	[self setViewDirection:VIEW_FORWARD];
	
	displayGUI = NO;
}


- (void) setUpWitchspace
{
	[self setUpWitchspaceBetweenSystem:[PLAYER system_seed] andSystem:[PLAYER target_system_seed]];
}


- (void) setUpWitchspaceBetweenSystem:(Random_Seed)s1 andSystem:(Random_Seed)s2
{
	// new system is hyper-centric : witchspace exit point is origin
	
	Entity				*thing;
	PlayerEntity*		player = PLAYER;
	Quaternion			randomQ;
	
	NSMutableDictionary *systeminfo = [NSMutableDictionary dictionaryWithCapacity:4];
	
	NSString*		override_key = [self keyForInterstellarOverridesForSystemSeeds:s1 :s2 inGalaxySeed:galaxy_seed];
	
	// check at this point
	// for scripted overrides for this insterstellar area
	[systeminfo addEntriesFromDictionary:[planetInfo oo_dictionaryForKey:PLANETINFO_UNIVERSAL_KEY]];
	[systeminfo addEntriesFromDictionary:[planetInfo oo_dictionaryForKey:@"interstellar space"]];
	[systeminfo addEntriesFromDictionary:[planetInfo oo_dictionaryForKey:override_key]];
	[systeminfo addEntriesFromDictionary:[localPlanetInfoOverrides oo_dictionaryForKey:override_key]];
	
	[universeRegion clearSubregions];
	
	// fixed entities (part of the graphics system really) come first...
	
	/*- the sky backdrop -*/
	OOColor *col1 = [OOColor colorWithRed:0.0 green:1.0 blue:0.5 alpha:1.0];
	OOColor *col2 = [OOColor colorWithRed:0.0 green:1.0 blue:0.0 alpha:1.0];
	thing = [[SkyEntity alloc] initWithColors:col1:col2 andSystemInfo: systeminfo];	// alloc retains!
	[thing setScanClass: CLASS_NO_DRAW];
	quaternion_set_random(&randomQ);
	[thing setOrientation:randomQ];
	[self addEntity:thing];
	[thing release];
	
	/*- the dust particle system -*/
	thing = [[DustEntity alloc] init];
	[thing setScanClass: CLASS_NO_DRAW];
	[self addEntity:thing];
	[thing release];
	
	[self setLighting];	// also sets initial lights positions.
	ranrot_srand([[NSDate date] timeIntervalSince1970]);   // reset randomiser with current time
	
	OOLog(kOOLogUniversePopulateWitchspace, @"Populating witchspace ...");
	OOLogIndentIf(kOOLogUniversePopulateWitchspace);
	
	[self clearSystemPopulator];
	NSString *populator = [systeminfo oo_stringForKey:@"populator" defaultValue:@"interstellarSpaceWillPopulate"];
	[system_repopulator release];
	system_repopulator = [[systeminfo oo_stringForKey:@"repopulator" defaultValue:@"interstellarSpaceWillRepopulate"] retain];
	JSContext *context = OOJSAcquireContext();
	[PLAYER doWorldScriptEvent:OOJSIDFromString(populator) inContext:context withArguments:NULL count:0 timeLimit:kOOJSLongTimeLimit];
	OOJSRelinquishContext(context);
	[self populateSystemFromDictionariesWithSun:nil andPlanet:nil];

	// systeminfo might have a 'script_actions' resource we want to activate now...
	NSArray *script_actions = [systeminfo oo_arrayForKey:@"script_actions"];
	if (script_actions != nil)
	{
		[player runUnsanitizedScriptActions:script_actions
						  allowingAIMethods:NO
							withContextName:@"<witchspace script_actions>"
								  forTarget:nil];
	}
	
	next_repopulation = randf() * SYSTEM_REPOPULATION_INTERVAL;

	OOLogOutdentIf(kOOLogUniversePopulateWitchspace);
}


- (OOPlanetEntity *) setUpPlanet
{
	// set the system seed for random number generation
	seed_for_planet_description(system_seed);
	
	Random_Seed systemSeed = [self systemSeed];
	NSMutableDictionary *planetDict = [NSMutableDictionary dictionaryWithDictionary:[self generateSystemData:systemSeed]];
	[planetDict oo_setBool:YES forKey:@"mainForLocalSystem"];
	OOPlanetEntity *a_planet = [[OOPlanetEntity alloc] initFromDictionary:planetDict withAtmosphere:YES andSeed:systemSeed];
	
	double planet_radius = [a_planet radius];
	double planet_zpos = (12.0 + (Ranrot() & 3) - (Ranrot() & 3) ) * planet_radius; // 9..15 pr (planet radii) ahead
	
	[a_planet setPosition:(HPVector){ 0, 0, planet_zpos }];
	[a_planet setEnergy:1000000.0];
	
	if ([allPlanets count]>0)	// F7 sets [UNIVERSE planet], which can lead to some trouble! TODO: track down where exactly that happens!
	{
		OOPlanetEntity *tmp=[allPlanets objectAtIndex:0];
		[self addEntity:a_planet];
		[allPlanets removeObject:a_planet];
		cachedPlanet=a_planet;
		[allPlanets replaceObjectAtIndex:0 withObject:a_planet];
		[self removeEntity:(Entity *)tmp];
	}
	else
	{
		[self addEntity:a_planet];
	}
	return [a_planet autorelease];
}

/* At any time other than game start, any call to this must be followed
 * by [self populateNormalSpace]. However, at game start, they need to be
 * separated to allow Javascript startUp routines to be run in-between */
- (void) setUpSpace
{
	Entity				*thing;
//	ShipEntity			*nav_buoy;
	StationEntity		*a_station;
	OOSunEntity			*a_sun;
	OOPlanetEntity		*a_planet;
	
	HPVector				stationPos;
	
	Vector				vf;
	id			dict_object;
	
	NSDictionary		*systeminfo = [self generateSystemData:system_seed useCache:NO];
	unsigned			techlevel = [systeminfo oo_unsignedIntForKey:KEY_TECHLEVEL];
	NSString			*stationDesc = nil, *defaultStationDesc = nil;
	OOColor				*bgcolor;
	OOColor				*pale_bgcolor;
	BOOL				sunGoneNova;
	
	[[GameController sharedController] logProgress:DESC(@"populating-space")];
	
	sunGoneNova = [systeminfo oo_boolForKey:@"sun_gone_nova"];
	
	OO_DEBUG_PUSH_PROGRESS(@"setUpSpace - clearSubRegions, sky, dust");
	[universeRegion clearSubregions];
	
	// fixed entities (part of the graphics system really) come first...
	[self setSkyColorRed:0.0f
				   green:0.0f
					blue:0.0f
				   alpha:0.0f];
	
	// set the system seed for random number generation
	seed_for_planet_description(system_seed);
	
	/*- the sky backdrop -*/
	// colors...
	float h1 = randf();
	float h2 = h1 + 1.0 / (1.0 + (Ranrot() % 5));
	while (h2 > 1.0)
		h2 -= 1.0;
	OOColor *col1 = [OOColor colorWithHue:h1 saturation:randf() brightness:0.5 + randf()/2.0 alpha:1.0];
	OOColor *col2 = [OOColor colorWithHue:h2 saturation:0.5 + randf()/2.0 brightness:0.5 + randf()/2.0 alpha:1.0];
	
	thing = [[SkyEntity alloc] initWithColors:col1:col2 andSystemInfo: systeminfo];	// alloc retains!
	[thing setScanClass: CLASS_NO_DRAW];
	[self addEntity:thing];
//	bgcolor = [(SkyEntity *)thing skyColor];
//
	h1 = randf()/3.0;
	if (h1 > 0.17)
	{
		h1 += 0.33;
	}
	// pick a main sequence colour

	dict_object=[systeminfo objectForKey:@"sun_color"];
	if (dict_object!=nil) 
	{
		bgcolor = [OOColor colorWithDescription:dict_object];
	}
	else
	{
		bgcolor = [OOColor colorWithHue:h1 saturation:0.75*randf() brightness:0.65+randf()/5.0 alpha:1.0];
	}

	pale_bgcolor = [bgcolor blendedColorWithFraction:0.5 ofColor:[OOColor whiteColor]];
	[thing release];
	/*--*/
	
	/*- the dust particle system -*/
	thing = [[DustEntity alloc] init];	// alloc retains!
	[thing setScanClass: CLASS_NO_DRAW];
	[self addEntity:thing];
	[(DustEntity *)thing setDustColor:pale_bgcolor]; 
	[thing release];
	/*--*/

	float defaultSunFlare = randf()*0.1;
	float defaultSunHues = 0.5+randf()*0.5;
	OO_DEBUG_POP_PROGRESS();
	
	// actual entities next...
	
	OO_DEBUG_PUSH_PROGRESS(@"setUpSpace - planet");
	a_planet=[self setUpPlanet]; // resets RNG when called
	double planet_radius = [a_planet radius];
	OO_DEBUG_POP_PROGRESS();
	
	// set the system seed for random number generation
	seed_for_planet_description(system_seed);
	
	OO_DEBUG_PUSH_PROGRESS(@"setUpSpace - sun");
	/*- space sun -*/
	double		sun_radius;
	double		sun_distance;
	double		sunDistanceModifier;
	double		safeDistance;
	int			posIterator=0;
	Quaternion  q_sun;
	HPVector		sunPos;
	
	sunDistanceModifier = [systeminfo oo_nonNegativeDoubleForKey:@"sun_distance_modifier" defaultValue:20.0];
	// Any smaller than 6, the main planet can end up inside the sun
	if (sunDistanceModifier < 6.0) sunDistanceModifier = 6.0;
	// Simplifying Ranrot() here would modify where the sun acutally goes, so let's avoid that!
	sun_distance = (sunDistanceModifier + (Ranrot() % 5) - (Ranrot() % 5) ) * planet_radius;
	
	sun_radius = [systeminfo oo_nonNegativeDoubleForKey:@"sun_radius" defaultValue:(2.5 + randf() - randf() ) * planet_radius];
	// clamp the sun radius
	if (sun_radius < 1000.0 || sun_radius > 1000000.0 ) 
	{
		sun_radius = sun_radius < 1000.0 ? 1000.0 : 1000000.0;
	}
	safeDistance=16 * sun_radius * sun_radius; // 4 times the sun radius
	
	// generated sun_distance/sun_radius ratios vary from 4.29 ( 15/3.5 ) to 16.67 ( 25/1.5 )
	// if ratio is less than 4 there's an OXP asking for an unusual system.
	if (sun_distance <= 4.2 * sun_radius)
	{
		// recalculate base distance: lowest  2.60 sun radii, highest  4.28 sun radii
		sun_distance= (2.6 + sun_distance /(2.5 * sun_radius)) * sun_radius;
		// decrease the safe distance, so we have a better chance to exit the loop normally
		safeDistance *= 0.6; // ~ 3 times the sun radius
	}
	
	// here we need to check if the sun collides with (or is too close to) the witchpoint
	// otherwise at (for example) Maregais in Galaxy 1 we go BANG!
	do
	{
		sunPos = [a_planet position];
		
		quaternion_set_random(&q_sun);
		// set up planet's direction in space so it gets a proper day
		[a_planet setOrientation:q_sun];
		
		vf = vector_right_from_quaternion(q_sun);
		sunPos = HPvector_subtract(sunPos, vectorToHPVector(vector_multiply_scalar(vf, sun_distance))); // back off from the planet by 15..25 planet radii
		posIterator++;
	} while (HPmagnitude2(sunPos) < safeDistance && posIterator <= 10);	// try 10 times before giving up
	
	if (posIterator>10)
	{
		OOLogWARN(@"universe.setup.badSun",@"Sun positioning: max iterations exceeded for '%@'. Adjust radius, sun_radius or sun_distance_modifier.",[systeminfo objectForKey: @"name"]);
	}
	
	NSMutableDictionary *sun_dict = [NSMutableDictionary dictionaryWithCapacity:4];
	[sun_dict setObject:[NSNumber numberWithDouble:sun_radius] forKey:@"sun_radius"];
	dict_object=[systeminfo objectForKey: @"corona_shimmer"];
	if (dict_object!=nil) [sun_dict setObject:dict_object forKey:@"corona_shimmer"];
	dict_object=[systeminfo objectForKey: @"corona_hues"];
	if (dict_object!=nil)
	{
		[sun_dict setObject:dict_object forKey:@"corona_hues"];
	}
	else
	{
		[sun_dict setObject:[NSNumber numberWithFloat:defaultSunHues] forKey:@"corona_hues"];
	}
	dict_object=[systeminfo objectForKey: @"corona_flare"];
	if (dict_object!=nil) 
	{
		[sun_dict setObject:dict_object forKey:@"corona_flare"];
	}
	else
	{
		[sun_dict setObject:[NSNumber numberWithFloat:defaultSunFlare] forKey:@"corona_flare"];
	}
	
	a_sun = [[OOSunEntity alloc] initSunWithColor:bgcolor andDictionary:sun_dict];	// alloc retains!
	
	[a_sun setStatus:STATUS_ACTIVE];
	[a_sun setPosition:sunPos]; // sets also light origin
	[a_sun setEnergy:1000000.0];
	[self addEntity:a_sun];
	
	if (sunGoneNova)
	{
		[a_sun setRadius: sun_radius + MAX_CORONAFLARE];
		[a_sun setThrowSparks:YES];
		[a_sun setVelocity: kZeroVector];
	}
	
	// set the lighting only after we know which sun we have.
	[self setLighting];
	OO_DEBUG_POP_PROGRESS();
	
	OO_DEBUG_PUSH_PROGRESS(@"setUpSpace - main station");
	/*- space station -*/
	stationPos = [a_planet position];
	Quaternion  q_station;
	do
	{
		quaternion_set_random(&q_station);
		vf = vector_forward_from_quaternion(q_station);
	}
	while (vf.z <= 0.0);						// keep station on the correct side of the planet
	
	stationPos = HPvector_subtract(stationPos, vectorToHPVector(vector_multiply_scalar(vf, 2.0 * planet_radius)));
	
	defaultStationDesc = @"coriolis";
	if (techlevel > 10)
	{
		if (system_seed.f & 0x03)   // 3 out of 4 get this type
		{
			defaultStationDesc = @"dodecahedron";
		}
		else
		{
			defaultStationDesc = @"icosahedron";
		}
	}
	
	//// possibly systeminfo has an override for the station
	stationDesc = [systeminfo oo_stringForKey:@"station" defaultValue:defaultStationDesc];
	
	a_station = (StationEntity *)[self newShipWithRole:stationDesc];			// retain count = 1
	
	/*	Sanity check: ensure that only stations are generated here. This is an
		attempt to fix exceptions of the form:
			NSInvalidArgumentException : *** -[ShipEntity setPlanet:]: selector
			not recognized [self = 0x19b7e000] *****
		which I presume to be originating here since all other uses of
		setPlanet: are guarded by isStation checks. This error could happen if
		a ship that is not a station has a station role, or equivalently if an
		OXP sets a system's station role to a role used by non-stations.
		-- Ahruman 20080303
	*/
	if (![a_station isStation] || ![a_station validForAddToUniverse])
	{
		if (a_station == nil)
		{
			// Should have had a more specific error already, just specify context
			OOLog(@"universe.setup.badStation", @"Failed to set up a ship for role \"%@\" as system station, trying again with \"%@\".", stationDesc, defaultStationDesc);
		}
		else
		{
			OOLog(@"universe.setup.badStation", @"***** ERROR: Attempt to use non-station ship of type \"%@\" for role \"%@\" as system station, trying again with \"%@\".", [a_station name], stationDesc, defaultStationDesc);
		}
		[a_station release];
		stationDesc = defaultStationDesc;
		a_station = (StationEntity *)[self newShipWithRole:stationDesc];		 // retain count = 1
		
		if (![a_station isStation] || ![a_station validForAddToUniverse])
		{
			if (a_station == nil)
			{
				OOLog(@"universe.setup.badStation", @"On retry, failed to set up a ship for role \"%@\" as system station. Trying to fall back to built-in Coriolis station.", stationDesc);
			}
			else
			{
				OOLog(@"universe.setup.badStation", @"***** ERROR: On retry, rolled non-station ship of type \"%@\" for role \"%@\". Non-station ships should not have this role! Trying to fall back to built-in Coriolis station.", [a_station name], stationDesc);
			}
			[a_station release];
			
			a_station = (StationEntity *)[self newShipWithName:@"coriolis-station"];
			if (![a_station isStation] || ![a_station validForAddToUniverse])
			{
				OOLog(@"universe.setup.badStation", @"Could not create built-in Coriolis station! Generating a stationless system.");
				DESTROY(a_station);
			}
		}
	}
	
	if (a_station != nil)
	{
		[a_station setOrientation:q_station];
		[a_station setPosition: stationPos];
		[a_station setPitch: 0.0];
		[a_station setScanClass: CLASS_STATION];
		//[a_station setPlanet:[self planet]];	// done inside addEntity.
		[a_station setEquivalentTechLevel:techlevel];
		[self addEntity:a_station];		// STATUS_IN_FLIGHT, AI state GLOBAL
		[a_station setStatus:STATUS_ACTIVE];	// For backward compatibility. Might not be needed.
		[a_station setAllowsFastDocking:true];	// Main stations always allow fast docking.
		[a_station setAllegiance:@"galcop"]; // Main station is galcop controlled
	}
	OO_DEBUG_POP_PROGRESS();
	
	cachedSun = a_sun;
	cachedPlanet = a_planet;
	cachedStation = a_station;
	closeSystems = nil;
	ranrot_srand([[NSDate date] timeIntervalSince1970]);   // reset randomiser with current time
	OO_DEBUG_POP_PROGRESS();
	
	
	OO_DEBUG_PUSH_PROGRESS(@"setUpSpace - populate from wormholes");
	[self populateSpaceFromActiveWormholes];
	OO_DEBUG_POP_PROGRESS();

	[a_sun release];
	[a_station release];
}


- (void) populateNormalSpace
{	
	/* Need to take a copy of this dictionary because the populator
	 * functions may ask for a different system info object, which
	 * will invalidate the cache, taking this object with it... 
	 * CIM: 6/8/2013 */
	NSDictionary		*systeminfo = [NSDictionary dictionaryWithDictionary:[self generateSystemData:system_seed useCache:NO]];
	BOOL sunGoneNova = [systeminfo oo_boolForKey:@"sun_gone_nova"];
	// check for nova
	if (sunGoneNova)
	{
	 	OO_DEBUG_PUSH_PROGRESS(@"setUpSpace - post-nova");
		
	 	HPVector v0 = make_HPvector(0,0,34567.89);
	 	double min_safe_dist2 = 6000000.0 * 6000000.0;
		HPVector sunPos = [cachedSun position];
	 	while (HPmagnitude2(cachedSun->position) < min_safe_dist2)	// back off the planetary bodies
	 	{
	 		v0.z *= 2.0;
			
	 		sunPos = HPvector_add(sunPos, v0);
	 		[cachedSun setPosition:sunPos];  // also sets light origin
			
	 	}
		
	 	[self removeEntity:cachedPlanet];	// and Poof! it's gone
	 	cachedPlanet = nil;	
	 	[self removeEntity:cachedStation];	// also remove main station
	 	cachedStation = nil;	
	}

	OO_DEBUG_PUSH_PROGRESS(@"setUpSpace - populate from hyperpoint");
//	[self populateSpaceFromHyperPoint:witchPos toPlanetPosition: a_planet->position andSunPosition: a_sun->position];
	[self clearSystemPopulator];
	
	NSString *populator = [systeminfo oo_stringForKey:@"populator" defaultValue:(sunGoneNova)?@"novaSystemWillPopulate":@"systemWillPopulate"];
	[system_repopulator release];
	system_repopulator = [[systeminfo oo_stringForKey:@"repopulator" defaultValue:(sunGoneNova)?@"novaSystemWillRepopulate":@"systemWillRepopulate"] retain];

	JSContext *context = OOJSAcquireContext();
	[PLAYER doWorldScriptEvent:OOJSIDFromString(populator) inContext:context withArguments:NULL count:0 timeLimit:kOOJSLongTimeLimit];
	OOJSRelinquishContext(context);
	[self populateSystemFromDictionariesWithSun:cachedSun andPlanet:cachedPlanet];

	OO_DEBUG_POP_PROGRESS();

	// systeminfo might have a 'script_actions' resource we want to activate now...
	NSArray *script_actions = [systeminfo oo_arrayForKey:@"script_actions"];
	if (script_actions != nil)
	{
		OO_DEBUG_PUSH_PROGRESS(@"setUpSpace - legacy script_actions");
		[PLAYER runUnsanitizedScriptActions:script_actions
											   allowingAIMethods:NO
												 withContextName:@"<system script_actions>"
													   forTarget:nil];
		OO_DEBUG_POP_PROGRESS();
	}

	next_repopulation = randf() * SYSTEM_REPOPULATION_INTERVAL;
}


- (void) clearSystemPopulator
{
	[populatorSettings release];
	populatorSettings = [[NSMutableDictionary alloc] initWithCapacity:128];
}


- (NSDictionary *) getPopulatorSettings
{
	return populatorSettings;
}


- (void) setPopulatorSetting:(NSString *)key to:(NSDictionary *)setting
{
	if (setting == nil)
	{
		[populatorSettings removeObjectForKey:key];
	} 
	else
	{
		[populatorSettings setObject:setting forKey:key];
	}
}


- (BOOL) deterministicPopulation
{
	return deterministic_population;
}


- (void) populateSystemFromDictionariesWithSun:(OOSunEntity *)sun andPlanet:(OOPlanetEntity *)planet
{
	NSArray *blocks = [populatorSettings allValues];
	NSEnumerator *enumerator = [[blocks sortedArrayUsingFunction:populatorPrioritySort context:nil] objectEnumerator];
	NSDictionary *populator = nil;
	HPVector location = kZeroHPVector;
	unsigned i, locationSeed, groupCount, rndvalue;
	RANROTSeed rndcache = RANROTGetFullSeed();
	RANROTSeed rndlocal = RANROTGetFullSeed();
	NSString *locationCode = nil;
	OOJSPopulatorDefinition *pdef = nil;
	while ((populator = [enumerator nextObject]))
	{
		deterministic_population = [populator oo_boolForKey:@"deterministic" defaultValue:NO];

		locationSeed = [populator oo_unsignedIntForKey:@"locationSeed" defaultValue:0];
		groupCount = [populator oo_unsignedIntForKey:@"groupCount" defaultValue:1];
		
		for (i = 0; i < groupCount; i++)
		{
			locationCode = [populator oo_stringForKey:@"location" defaultValue:@"COORDINATES"];
			if ([locationCode isEqualToString:@"COORDINATES"])
			{
				location = [populator oo_hpvectorForKey:@"coordinates" defaultValue:kZeroHPVector];
			}
			else
			{
				if (locationSeed != 0)
				{
					rndcache = RANROTGetFullSeed();
					// different place for each system
					rndlocal = RanrotSeedFromRandomSeed(system_seed);
					rndvalue = RanrotWithSeed(&rndlocal);
					// ...for location seed
					rndlocal = MakeRanrotSeed(rndvalue+locationSeed);
					rndvalue = RanrotWithSeed(&rndlocal);
					// ...for iteration (63647 is nothing special, just a largish prime)
					RANROTSetFullSeed(MakeRanrotSeed(rndvalue+(i*63647)));
				}
				else
				{
					// not fixed coordinates and not seeded RNG; can't
					// be deterministic
					deterministic_population = false;
				}
				if (sun == nil || planet == nil)
				{
					// all interstellar space and nova locations equal to WITCHPOINT
					location = [self locationByCode:@"WITCHPOINT" withSun:nil andPlanet:nil];
				}
				else
				{
					location = [self locationByCode:locationCode withSun:sun andPlanet:planet];
				}
				if(locationSeed != 0)
				{
					// go back to the main random sequence
					RANROTSetFullSeed(rndcache);
				}			
			}
			// location now contains a Vector coordinate, one way or another
			pdef = [populator objectForKey:@"callbackObj"];
			[pdef runCallback:location];
		}
	}
	// nothing is deterministic once the populator is done
	deterministic_population = NO;
}


/* Generates a position within one of the named regions:
 *
 * WITCHPOINT: within scanner of witchpoint
 * LANE_*: within two scanner of lane, not too near each end
 * STATION_AEGIS: within two scanner of main station, not in planet
 * *_ORBIT_*: around the object, in a shell relative to object radius
 * TRIANGLE: somewhere in the triangle defined by W, P, S
 * INNER_SYSTEM: closer to the sun than the planet is
 * OUTER_SYSTEM: further from the sun than the planet is
 * *_OFFPLANE: like the above, but not on the orbital plane
 *
 * Can be called with nil sun or planet, but if so the calling function
 * must make sure the location code is WITCHPOINT.
 */
- (HPVector) locationByCode:(NSString *)code withSun:(OOSunEntity *)sun andPlanet:(OOPlanetEntity *)planet
{
	HPVector result = kZeroHPVector;
	if ([code isEqualToString:@"WITCHPOINT"] || sun == nil || planet == nil)
	{
		result = OOHPVectorRandomSpatial(SCANNER_MAX_RANGE);
	}
	// past this point, can assume non-nil sun, planet
	else
	{ 
		if ([code isEqualToString:@"LANE_WPS"])
		{	
			// pick position on one of the lanes, weighted by lane length
			double l1 = HPmagnitude([planet position]);
			double l2 = HPmagnitude(HPvector_subtract([sun position],[planet position]));
			double l3 = HPmagnitude([sun position]);
			double total = l1+l2+l3;
			float choice = randf();
			if (choice < l1/total)
			{
				return [self locationByCode:@"LANE_WP" withSun:sun andPlanet:planet];
			}
			else if (choice < (l1+l2)/total)
			{
				return [self locationByCode:@"LANE_PS" withSun:sun andPlanet:planet];
			}
			else
			{
				return [self locationByCode:@"LANE_WS" withSun:sun andPlanet:planet];
			}
		}
		else if ([code isEqualToString:@"LANE_WP"])
		{
			result = OORandomPositionInCylinder(kZeroHPVector,SCANNER_MAX_RANGE,[planet position],[planet radius]*3,LANE_WIDTH);
		}
		else if ([code isEqualToString:@"LANE_WS"])
		{
			result = OORandomPositionInCylinder(kZeroHPVector,SCANNER_MAX_RANGE,[sun position],[sun radius]*3,LANE_WIDTH);
		}
		else if ([code isEqualToString:@"LANE_PS"])
		{
			result = OORandomPositionInCylinder([planet position],[planet radius]*3,[sun position],[sun radius]*3,LANE_WIDTH);
		}
		else if ([code isEqualToString:@"STATION_AEGIS"])
		{
			do 
			{
				result = OORandomPositionInShell([[self station] position],[[self station] collisionRadius]*1.2,SCANNER_MAX_RANGE*2.0);
			} while(HPdistance2(result,[planet position])<[planet radius]*[planet radius]*1.5);
			// loop to make sure not generated too close to the planet's surface
		}
		else if ([code isEqualToString:@"PLANET_ORBIT_LOW"])
		{
			result = OORandomPositionInShell([planet position],[planet radius]*1.1,[planet radius]*2.0);
		}
		else if ([code isEqualToString:@"PLANET_ORBIT"])
		{
			result = OORandomPositionInShell([planet position],[planet radius]*2.0,[planet radius]*4.0);
		}
		else if ([code isEqualToString:@"PLANET_ORBIT_HIGH"])
		{
			result = OORandomPositionInShell([planet position],[planet radius]*4.0,[planet radius]*8.0);
		}
		else if ([code isEqualToString:@"STAR_ORBIT_LOW"])
		{
			result = OORandomPositionInShell([sun position],[sun radius]*1.1,[sun radius]*2.0);
		}
		else if ([code isEqualToString:@"STAR_ORBIT"])
		{
			result = OORandomPositionInShell([sun position],[sun radius]*2.0,[sun radius]*4.0);
		}
		else if ([code isEqualToString:@"STAR_ORBIT_HIGH"])
		{
			result = OORandomPositionInShell([sun position],[sun radius]*4.0,[sun radius]*8.0);
		}
		else if ([code isEqualToString:@"TRIANGLE"])
		{
			do {
				// pick random point in triangle by algorithm at
				// http://adamswaab.wordpress.com/2009/12/11/random-point-in-a-triangle-barycentric-coordinates/
				// simplified by using the origin as A
				OOScalar r = randf();
				OOScalar s = randf();
				if (r+s >= 1)
				{
					r = 1-r;
					s = 1-s;
				}
				result = HPvector_add(HPvector_multiply_scalar([planet position],r),HPvector_multiply_scalar([sun position],s));
			}
			// make sure at least 3 radii from vertices
			while(HPdistance2(result,[sun position]) < [sun radius]*[sun radius]*9.0 || HPdistance2(result,[planet position]) < [planet radius]*[planet radius]*9.0 || HPmagnitude2(result) < SCANNER_MAX_RANGE2 * 9.0);
		}
		else if ([code isEqualToString:@"INNER_SYSTEM"])
		{
			do {
				result = OORandomPositionInShell([sun position],[sun radius]*3.0,HPdistance([sun position],[planet position]));
				result = OOProjectHPVectorToPlane(result,kZeroHPVector,HPcross_product([sun position],[planet position]));
				result = HPvector_add(result,OOHPVectorRandomSpatial([planet radius]));
				// projection to plane could bring back too close to sun
			} while (HPdistance2(result,[sun position]) < [sun radius]*[sun radius]*9.0);
		}
		else if ([code isEqualToString:@"INNER_SYSTEM_OFFPLANE"])
		{
			result = OORandomPositionInShell([sun position],[sun radius]*3.0,HPdistance([sun position],[planet position]));
		}
		else if ([code isEqualToString:@"OUTER_SYSTEM"])
		{
			result = OORandomPositionInShell([sun position],HPdistance([sun position],[planet position]),10000000); // no more than 10^7 metres from sun
			result = OOProjectHPVectorToPlane(result,kZeroHPVector,HPcross_product([sun position],[planet position]));
			result = HPvector_add(result,OOHPVectorRandomSpatial(0.01*HPdistance(result,[sun position]))); // within 1% of plane
		}
		else if ([code isEqualToString:@"OUTER_SYSTEM_OFFPLANE"])
		{
			result = OORandomPositionInShell([sun position],HPdistance([sun position],[planet position]),10000000); // no more than 10^7 metres from sun
		}
		else
		{
			OOLog(kOOLogUniversePopulateError,@"Named populator region %@ is not implemented, falling back to WITCHPOINT",code); 
			result = OOHPVectorRandomSpatial(SCANNER_MAX_RANGE);
		}
	}
	return result;
}


- (void) setLighting
{
	/*
	
	GL_LIGHT1 is the sun and is active while a sun exists in space
	where there is no sun (witch/interstellar space) this is placed at the origin
	
	Shaders: this light is also used inside the station and needs to have its position reset
	relative to the player whenever demo ships or background scenes are to be shown -- 20100111
	
	
	GL_LIGHT0 is the light for inside the station and needs to have its position reset
	relative to the player whenever demo ships or background scenes are to be shown
	
	Shaders: this light is not used.  -- 20100111
	
	*/
	
	NSDictionary	*systeminfo = [self generateSystemData:system_seed];
	OOSunEntity		*the_sun = [self sun];
	SkyEntity		*the_sky = nil;
	GLfloat			sun_pos[] = {0.0, 0.0, 0.0, 1.0};	// equivalent to kZeroVector - for interstellar space.
	GLfloat			sun_ambient[] = {0.0, 0.0, 0.0, 1.0};	// overridden later in code
	int i;
	
	for (i = n_entities - 1; i > 0; i--)
		if ((sortedEntities[i]) && ([sortedEntities[i] isKindOfClass:[SkyEntity class]]))
			the_sky = (SkyEntity*)sortedEntities[i];
	
	if (the_sun)
	{
		[the_sun getDiffuseComponents:sun_diffuse];
		[the_sun getSpecularComponents:sun_specular];
		OOGL(glLightfv(GL_LIGHT1, GL_AMBIENT, sun_ambient));
		OOGL(glLightfv(GL_LIGHT1, GL_DIFFUSE, sun_diffuse));
		OOGL(glLightfv(GL_LIGHT1, GL_SPECULAR, sun_specular));
		sun_pos[0] = the_sun->position.x;
		sun_pos[1] = the_sun->position.y;
		sun_pos[2] = the_sun->position.z;
	}
	else
	{
		// witchspace
		stars_ambient[0] = 0.05;	stars_ambient[1] = 0.20;	stars_ambient[2] = 0.05;	stars_ambient[3] = 1.0;
		sun_diffuse[0] = 0.85;	sun_diffuse[1] = 1.0;	sun_diffuse[2] = 0.85;	sun_diffuse[3] = 1.0;
		sun_specular[0] = 0.95;	sun_specular[1] = 1.0;	sun_specular[2] = 0.95;	sun_specular[3] = 1.0;
		OOGL(glLightfv(GL_LIGHT1, GL_AMBIENT, sun_ambient));
		OOGL(glLightfv(GL_LIGHT1, GL_DIFFUSE, sun_diffuse));
		OOGL(glLightfv(GL_LIGHT1, GL_SPECULAR, sun_specular));
	}
	
	OOGL(glLightfv(GL_LIGHT1, GL_POSITION, sun_pos));
	
	if (the_sky)
	{
		// ambient lighting!
		GLfloat r,g,b,a;
		[[the_sky skyColor] getRed:&r green:&g blue:&b alpha:&a];
		r = r * (1.0 - SUN_AMBIENT_INFLUENCE) + sun_diffuse[0] * SUN_AMBIENT_INFLUENCE;
		g = g * (1.0 - SUN_AMBIENT_INFLUENCE) + sun_diffuse[1] * SUN_AMBIENT_INFLUENCE;
		b = b * (1.0 - SUN_AMBIENT_INFLUENCE) + sun_diffuse[2] * SUN_AMBIENT_INFLUENCE;
		GLfloat ambient_level = [systeminfo oo_floatForKey:@"ambient_level" defaultValue:1.0];
		stars_ambient[0] = ambient_level * 0.0625 * (1.0 + r) * (1.0 + r);
		stars_ambient[1] = ambient_level * 0.0625 * (1.0 + g) * (1.0 + g);
		stars_ambient[2] = ambient_level * 0.0625 * (1.0 + b) * (1.0 + b);
		stars_ambient[3] = 1.0;
	}
	
	// light for demo ships display..
	OOGL(glLightfv(GL_LIGHT0, GL_AMBIENT, docked_light_ambient));
	OOGL(glLightfv(GL_LIGHT0, GL_DIFFUSE, docked_light_diffuse));
	OOGL(glLightfv(GL_LIGHT0, GL_SPECULAR, docked_light_specular));
	OOGL(glLightfv(GL_LIGHT0, GL_POSITION, demo_light_position));	
	OOGL(glLightModelfv(GL_LIGHT_MODEL_AMBIENT, stars_ambient));
}


// Call this method to avoid lighting glich after windowed/fullscreen transition on macs.
- (void) forceLightSwitch
{
	demo_light_on = !demo_light_on;
}


- (void) setMainLightPosition: (Vector) sunPos
{
	main_light_position[0] = sunPos.x;
	main_light_position[1] = sunPos.y;
	main_light_position[2] = sunPos.z;
	main_light_position[3] = 1.0;
}


- (ShipEntity *) addShipWithRole:(NSString *)desc launchPos:(HPVector)launchPos rfactor:(GLfloat)rfactor
{
	if (rfactor != 0.0)
	{
		// Calculate the position as soon as possible, to minimise 'lollipop flash'
	 	launchPos.x += 2 * rfactor * (randf() - 0.5);
		launchPos.y += 2 * rfactor * (randf() - 0.5);
		launchPos.z += 2 * rfactor * (randf() - 0.5);
	}
	
	ShipEntity  *ship = [self newShipWithRole:desc];   // retain count = 1
	
	if (ship)
	{
		[ship setPosition:launchPos];	// minimise 'lollipop flash'
		
		// Deal with scripted cargopods and ensure they are filled with something.
		if ([ship hasRole:@"cargopod"]) [self fillCargopodWithRandomCargo:ship];
		if (![ship crew] && ![ship isUnpiloted] && !([ship scanClass] == CLASS_CARGO || [ship scanClass] == CLASS_ROCK))
			[ship setCrew:[NSArray arrayWithObject:
						   [OOCharacter randomCharacterWithRole:desc
											  andOriginalSystem:systems[Ranrot() & 255]]]];
		
		if ([ship scanClass] == CLASS_NOT_SET)
		{
			[ship setScanClass: CLASS_NEUTRAL];
		}
		[self addEntity:ship];	// STATUS_IN_FLIGHT, AI state GLOBAL
		[ship release];
		return ship;
	}
	return nil;
}


- (void) addShipWithRole:(NSString *) desc nearRouteOneAt:(double) route_fraction
{
	// adds a ship within scanner range of a point on route 1
	
	Entity	*theStation = [self station];
	if (!theStation)
	{
		return;
	}
	
	HPVector	launchPos = OOHPVectorInterpolate([self getWitchspaceExitPosition], [theStation position], route_fraction);
	
	[self addShipWithRole:desc launchPos:launchPos rfactor:SCANNER_MAX_RANGE];
}


- (HPVector) coordinatesForPosition:(HPVector) pos withCoordinateSystem:(NSString *) system returningScalar:(GLfloat*) my_scalar
{
	/*	the point is described using a system selected by a string
		consisting of a three letter code.
		
		The first letter indicates the feature that is the origin of the coordinate system.
			w => witchpoint
			s => sun
			p => planet
			
		The next letter indicates the feature on the 'z' axis of the coordinate system.
			w => witchpoint
			s => sun
			p => planet
			
		Then the 'y' axis of the system is normal to the plane formed by the planet, sun and witchpoint.
		And the 'x' axis of the system is normal to the y and z axes.
		So:
			ps:		z axis = (planet -> sun)		y axis = normal to (planet - sun - witchpoint)	x axis = normal to y and z axes
			pw:		z axis = (planet -> witchpoint)	y axis = normal to (planet - witchpoint - sun)	x axis = normal to y and z axes
			sp:		z axis = (sun -> planet)		y axis = normal to (sun - planet - witchpoint)	x axis = normal to y and z axes
			sw:		z axis = (sun -> witchpoint)	y axis = normal to (sun - witchpoint - planet)	x axis = normal to y and z axes
			wp:		z axis = (witchpoint -> planet)	y axis = normal to (witchpoint - planet - sun)	x axis = normal to y and z axes
			ws:		z axis = (witchpoint -> sun)	y axis = normal to (witchpoint - sun - planet)	x axis = normal to y and z axes
			
		The third letter denotes the units used:
			m:		meters
			p:		planetary radii
			s:		solar radii
			u:		distance between first two features indicated (eg. spu means that u = distance from sun to the planet)
		
		in interstellar space (== no sun) coordinates are absolute irrespective of the system used.
		
		[1.71] The position code "abs" can also be used for absolute coordinates.
		
	*/
	
	NSString* l_sys = [system lowercaseString];
	if ([l_sys length] != 3)
		return kZeroHPVector;
	OOPlanetEntity* the_planet = [self planet];
	OOSunEntity* the_sun = [self sun];
	if (the_planet == nil || the_sun == nil || [l_sys isEqualToString:@"abs"])
	{
		if (my_scalar)  *my_scalar = 1.0;
		return pos;
	}
	HPVector  w_pos = [self getWitchspaceExitPosition];	// don't reset PRNG
	HPVector  p_pos = the_planet->position;
	HPVector  s_pos = the_sun->position;
	
	const char* c_sys = [l_sys UTF8String];
	HPVector p0, p1, p2;
	
	switch (c_sys[0])
	{
		case 'w':
			p0 = w_pos;
			switch (c_sys[1])
			{
				case 'p':
					p1 = p_pos;	p2 = s_pos;	break;
				case 's':
					p1 = s_pos;	p2 = p_pos;	break;
				default:
					return kZeroHPVector;
			}
			break;
		case 'p':		
			p0 = p_pos;
			switch (c_sys[1])
			{
				case 'w':
					p1 = w_pos;	p2 = s_pos;	break;
				case 's':
					p1 = s_pos;	p2 = w_pos;	break;
				default:
					return kZeroHPVector;
			}
			break;
		case 's':
			p0 = s_pos;
			switch (c_sys[1])
			{
				case 'w':
					p1 = w_pos;	p2 = p_pos;	break;
				case 'p':
					p1 = p_pos;	p2 = w_pos;	break;
				default:
					return kZeroHPVector;
			}
			break;
		default:
			return kZeroHPVector;
	}
	HPVector k = HPvector_normal_or_zbasis(HPvector_subtract(p1, p0));	// 'forward'
	HPVector v = HPvector_normal_or_xbasis(HPvector_subtract(p2, p0));	// temporary vector in plane of 'forward' and 'right'
	
	HPVector j = HPcross_product(k, v);	// 'up'
	HPVector i = HPcross_product(j, k);	// 'right'
	
	GLfloat scale = 1.0;
	switch (c_sys[2])
	{
		case 'p':
			scale = [the_planet radius];
			break;
			
		case 's':
			scale = [the_sun radius];
			break;
			
		case 'u':
			scale = HPmagnitude(HPvector_subtract(p1, p0));
			break;
			
		case 'm':
			scale = 1.0f;
			break;
			
		default:
			return kZeroHPVector;
	}
	if (my_scalar)
		*my_scalar = scale;
	
	// result = p0 + ijk
	HPVector result = p0;	// origin
	result.x += scale * (pos.x * i.x + pos.y * j.x + pos.z * k.x);
	result.y += scale * (pos.x * i.y + pos.y * j.y + pos.z * k.y);
	result.z += scale * (pos.x * i.z + pos.y * j.z + pos.z * k.z);
	
	return result;
}


- (NSString *) expressPosition:(HPVector) pos inCoordinateSystem:(NSString *) system
{
	HPVector result = [self legacyPositionFrom:pos asCoordinateSystem:system];
	return [NSString stringWithFormat:@"%@ %.2f %.2f %.2f", system, result.x, result.y, result.z];
}


- (HPVector) legacyPositionFrom:(HPVector) pos asCoordinateSystem:(NSString *) system
{
	NSString* l_sys = [system lowercaseString];
	if ([l_sys length] != 3)
		return kZeroHPVector;
	OOPlanetEntity* the_planet = [self planet];
	OOSunEntity* the_sun = [self sun];
	if (the_planet == nil || the_sun == nil || [l_sys isEqualToString:@"abs"])
	{
		return pos;
	}
	HPVector  w_pos = [self getWitchspaceExitPosition];	// don't reset PRNG
	HPVector  p_pos = the_planet->position;
	HPVector  s_pos = the_sun->position;
	
	const char* c_sys = [l_sys UTF8String];
	HPVector p0, p1, p2;
	
	switch (c_sys[0])
	{
		case 'w':
			p0 = w_pos;
			switch (c_sys[1])
			{
				case 'p':
					p1 = p_pos;	p2 = s_pos;	break;
				case 's':
					p1 = s_pos;	p2 = p_pos;	break;
				default:
					return kZeroHPVector;
			}
			break;
		case 'p':		
			p0 = p_pos;
			switch (c_sys[1])
			{
				case 'w':
					p1 = w_pos;	p2 = s_pos;	break;
				case 's':
					p1 = s_pos;	p2 = w_pos;	break;
				default:
					return kZeroHPVector;
			}
			break;
		case 's':
			p0 = s_pos;
			switch (c_sys[1])
			{
				case 'w':
					p1 = w_pos;	p2 = p_pos;	break;
				case 'p':
					p1 = p_pos;	p2 = w_pos;	break;
				default:
					return kZeroHPVector;
			}
			break;
		default:
			return kZeroHPVector;
	}
	HPVector k = HPvector_normal_or_zbasis(HPvector_subtract(p1, p0));	// 'z' axis in m
	HPVector v = HPvector_normal_or_xbasis(HPvector_subtract(p2, p0));	// temporary vector in plane of 'forward' and 'right'
	
	HPVector j = HPcross_product(k, v);	// 'y' axis in m
	HPVector i = HPcross_product(j, k);	// 'x' axis in m
	
	GLfloat scale = 1.0;
	switch (c_sys[2])
	{
		case 'p':
		{
			scale = 1.0f / [the_planet radius];
			break;
		}
		case 's':
		{
			scale = 1.0f / [the_sun radius];
			break;
		}
			
		case 'u':
			scale = 1.0f / HPdistance(p1, p0);
			break;
			
		case 'm':
			scale = 1.0f;
			break;
			
		default:
			return kZeroHPVector;
	}
	
	// result = p0 + ijk
	HPVector r_pos = HPvector_subtract(pos, p0);
	HPVector result = make_HPvector(scale * (r_pos.x * i.x + r_pos.y * i.y + r_pos.z * i.z),
								scale * (r_pos.x * j.x + r_pos.y * j.y + r_pos.z * j.z),
								scale * (r_pos.x * k.x + r_pos.y * k.y + r_pos.z * k.z) ); // scale * dot_products
	
	return result;
}


- (HPVector) coordinatesFromCoordinateSystemString:(NSString *) system_x_y_z
{
	NSArray* tokens = ScanTokensFromString(system_x_y_z);
	if ([tokens count] != 4)
	{
		// Not necessarily an error.
		return make_HPvector(0,0,0);
	}
	GLfloat dummy;
	return [self coordinatesForPosition:make_HPvector([tokens oo_floatAtIndex:1], [tokens oo_floatAtIndex:2], [tokens oo_floatAtIndex:3]) withCoordinateSystem:[tokens oo_stringAtIndex:0] returningScalar:&dummy];
}


- (BOOL) addShipWithRole:(NSString *) desc nearPosition:(HPVector) pos withCoordinateSystem:(NSString *) system
{
	// initial position
	GLfloat scalar = 1.0;
	HPVector launchPos = [self coordinatesForPosition:pos withCoordinateSystem:system returningScalar:&scalar];
	//	randomise
	GLfloat rfactor = scalar;
	if (rfactor > SCANNER_MAX_RANGE)
		rfactor = SCANNER_MAX_RANGE;
	if (rfactor < 1000)
		rfactor = 1000;
	
	return ([self addShipWithRole:desc launchPos:launchPos rfactor:rfactor] != nil);
}


- (BOOL) addShips:(int) howMany withRole:(NSString *) desc atPosition:(HPVector) pos withCoordinateSystem:(NSString *) system
{
	// initial bounding box
	GLfloat scalar = 1.0;
	HPVector launchPos = [self coordinatesForPosition:pos withCoordinateSystem:system returningScalar:&scalar];
	GLfloat distance_from_center = 0.0;
	HPVector v_from_center, ship_pos;
	HPVector ship_positions[howMany];
	int i = 0;
	int	scale_up_after = 0;
	int	current_shell = 0;
	GLfloat	walk_factor = 2.0;
	while (i < howMany)
	{
	 	ShipEntity  *ship = [self addShipWithRole:desc launchPos:launchPos rfactor:0.0];
		if (ship == nil) return NO;
		OOScanClass scanClass = [ship scanClass];
		[ship setScanClass:CLASS_NO_DRAW];	// avoid lollipop flash
		
		GLfloat		safe_distance2 = ship->collision_radius * ship->collision_radius * SAFE_ADDITION_FACTOR2;
		BOOL		safe;
		int			limit_count = 8;
		
		v_from_center = kZeroHPVector;
		do
		{
			do
			{
				v_from_center.x += walk_factor * (randf() - 0.5);
				v_from_center.y += walk_factor * (randf() - 0.5);
				v_from_center.z += walk_factor * (randf() - 0.5);	// drunkards walk
			} while ((v_from_center.x == 0.0)&&(v_from_center.y == 0.0)&&(v_from_center.z == 0.0));
			v_from_center = HPvector_normal(v_from_center);	// guaranteed non-zero
			
			ship_pos = make_HPvector(	launchPos.x + distance_from_center * v_from_center.x,
									launchPos.y + distance_from_center * v_from_center.y,
									launchPos.z + distance_from_center * v_from_center.z);
			
			// check this position against previous ship positions in this shell
			safe = YES;
			int j = i - 1;
			while (safe && (j >= current_shell))
			{
				safe = (safe && (HPdistance2(ship_pos, ship_positions[j]) > safe_distance2));
				j--;
			}
			if (!safe)
			{
				limit_count--;
				if (!limit_count)	// give up and expand the shell
				{
					limit_count = 8;
					distance_from_center += sqrt(safe_distance2);	// expand to the next distance
				}
			}
			
		} while (!safe);
		
		[ship setPosition:ship_pos];
		[ship setScanClass:scanClass == CLASS_NOT_SET ? CLASS_NEUTRAL : scanClass];
		
		Quaternion qr;
		quaternion_set_random(&qr);
		[ship setOrientation:qr];
		
		// [self addEntity:ship];	// STATUS_IN_FLIGHT, AI state GLOBAL
		
		ship_positions[i] = ship_pos;
		i++;
		if (i > scale_up_after)
		{
			current_shell = i;
			scale_up_after += 1 + 2 * i;
			distance_from_center += sqrt(safe_distance2);	// fill the next shell
		}
	}
	return YES;
}


- (BOOL) addShips:(int) howMany withRole:(NSString *) desc nearPosition:(HPVector) pos withCoordinateSystem:(NSString *) system
{
	// initial bounding box
	GLfloat scalar = 1.0;
	HPVector launchPos = [self coordinatesForPosition:pos withCoordinateSystem:system returningScalar:&scalar];
	GLfloat rfactor = scalar;
	if (rfactor > SCANNER_MAX_RANGE)
		rfactor = SCANNER_MAX_RANGE;
	if (rfactor < 1000)
		rfactor = 1000;
	BoundingBox	launch_bbox;
	bounding_box_reset_to_vector(&launch_bbox, make_vector(launchPos.x - rfactor, launchPos.y - rfactor, launchPos.z - rfactor));
	bounding_box_add_xyz(&launch_bbox, launchPos.x + rfactor, launchPos.y + rfactor, launchPos.z + rfactor);
	
	return [self addShips: howMany withRole: desc intoBoundingBox: launch_bbox];
}


- (BOOL) addShips:(int) howMany withRole:(NSString *) desc nearPosition:(HPVector) pos withCoordinateSystem:(NSString *) system withinRadius:(GLfloat) radius
{
	// initial bounding box
	GLfloat scalar = 1.0;
	HPVector launchPos = [self coordinatesForPosition:pos withCoordinateSystem:system returningScalar:&scalar];
	GLfloat rfactor = radius;
	if (rfactor < 1000)
		rfactor = 1000;
	BoundingBox	launch_bbox;
	bounding_box_reset_to_vector(&launch_bbox, make_vector(launchPos.x - rfactor, launchPos.y - rfactor, launchPos.z - rfactor));
	bounding_box_add_xyz(&launch_bbox, launchPos.x + rfactor, launchPos.y + rfactor, launchPos.z + rfactor);
	
	return [self addShips: howMany withRole: desc intoBoundingBox: launch_bbox];
}


- (BOOL) addShips:(int) howMany withRole:(NSString *) desc intoBoundingBox:(BoundingBox) bbox
{
	if (howMany < 1)
		return YES;
	if (howMany > 1)
	{
		// divide the number of ships in two
		int h0 = howMany / 2;
		int h1 = howMany - h0;
		// split the bounding box into two along its longest dimension
		GLfloat lx = bbox.max.x - bbox.min.x;
		GLfloat ly = bbox.max.y - bbox.min.y;
		GLfloat lz = bbox.max.z - bbox.min.z;
		BoundingBox bbox0 = bbox;
		BoundingBox bbox1 = bbox;
		if ((lx > lz)&&(lx > ly))	// longest dimension is x
		{
			bbox0.min.x += 0.5 * lx;
			bbox1.max.x -= 0.5 * lx;
		}
		else
		{
			if (ly > lz)	// longest dimension is y
			{
				bbox0.min.y += 0.5 * ly;
				bbox1.max.y -= 0.5 * ly;
			}
			else			// longest dimension is z
			{
				bbox0.min.z += 0.5 * lz;
				bbox1.max.z -= 0.5 * lz;
			}
		}
		// place half the ships into each bounding box
		return ([self addShips: h0 withRole: desc intoBoundingBox: bbox0] && [self addShips: h1 withRole: desc intoBoundingBox: bbox1]);
	}
	
	//	randomise within the bounding box (biased towards the center of the box)
	HPVector pos = make_HPvector(bbox.min.x, bbox.min.y, bbox.min.z);
	pos.x += 0.5 * (randf() + randf()) * (bbox.max.x - bbox.min.x);
	pos.y += 0.5 * (randf() + randf()) * (bbox.max.y - bbox.min.y);
	pos.z += 0.5 * (randf() + randf()) * (bbox.max.z - bbox.min.z);
	
	return ([self addShipWithRole:desc launchPos:pos rfactor:0.0] != nil);
}


- (BOOL) spawnShip:(NSString *) shipdesc
{
	ShipEntity		*ship;
	NSDictionary	*shipdict = nil;
	
	shipdict = [[OOShipRegistry sharedRegistry] shipInfoForKey:shipdesc];
	if (shipdict == nil)  return NO;
	
	ship = [self newShipWithName:shipdesc];	// retain count is 1
	
	if (ship == nil)  return NO;
	
	// set any spawning characteristics
	NSDictionary	*spawndict = [shipdict oo_dictionaryForKey:@"spawn"];
	HPVector			pos, rpos, spos;
	NSString		*positionString = nil;
	
	// position
	positionString = [spawndict oo_stringForKey:@"position"];
	if (positionString != nil)
	{
		if([positionString hasPrefix:@"abs "] && ([self planet] != nil || [self sun] !=nil))
		{
			OOLogWARN(@"script.deprecated", @"setting %@ for %@ '%@' in 'abs' inside .plists can cause compatibility issues across Oolite versions. Use coordinates relative to main system objects instead.",@"position",@"entity",shipdesc);
		}
		
		pos = [self coordinatesFromCoordinateSystemString:positionString];
	}
	else
	{
		// without position defined, the ship will be added on top of the witchpoint buoy.
		pos = OOHPVectorRandomRadial(SCANNER_MAX_RANGE);
		OOLogERR(@"universe.spawnShip.error", @"***** ERROR: failed to find a spawn position for ship %@.", shipdesc);
	}
	[ship setPosition:pos];
	
	// facing_position
	positionString = [spawndict oo_stringForKey:@"facing_position"];
	if (positionString != nil)
	{
		if([positionString hasPrefix:@"abs "] && ([self planet] != nil || [self sun] !=nil))
		{
			OOLogWARN(@"script.deprecated", @"setting %@ for %@ '%@' in 'abs' inside .plists can cause compatibility issues across Oolite versions. Use coordinates relative to main system objects instead.",@"facing_position",@"entity",shipdesc);
		}
		
		spos = [ship position];
		Quaternion q1;
		rpos = [self coordinatesFromCoordinateSystemString:positionString];
		rpos = HPvector_subtract(rpos, spos); // position relative to ship
		
		if (!HPvector_equal(rpos, kZeroHPVector))
		{
			rpos = HPvector_normal(rpos);
			
			if (!HPvector_equal(rpos, HPvector_flip(kBasisZHPVector)))
			{
				q1 = quaternion_rotation_between(HPVectorToVector(rpos), kBasisZVector);
			}
			else
			{
				// for the inverse of the kBasisZVector the rotation is undefined, so we select one.
				q1 = make_quaternion(0,1,0,0);
			}
			
						
			[ship setOrientation:q1];
		}
	}
	
	[self addEntity:ship];	// STATUS_IN_FLIGHT, AI state GLOBAL
	[ship release];
	
	return YES;
}


- (void) witchspaceShipWithPrimaryRole:(NSString *)role
{
	// adds a ship exiting witchspace (corollary of when ships leave the system)
	ShipEntity			*ship = nil;
	NSDictionary		*systeminfo = nil;
	OOGovernmentID		government;
	
	systeminfo = [self generateSystemData:system_seed];
 	government = [systeminfo oo_unsignedCharForKey:KEY_GOVERNMENT];
	
	ship = [self newShipWithRole:role];   // retain count = 1
	
	// Deal with scripted cargopods and ensure they are filled with something.
	if (ship && [ship hasRole:@"cargopod"])
	{		
		[self fillCargopodWithRandomCargo:ship];
	}
	
	if (ship)
	{
		if (([ship scanClass] == CLASS_NO_DRAW)||([ship scanClass] == CLASS_NOT_SET))
			[ship setScanClass: CLASS_NEUTRAL];
		if ([role isEqual:@"trader"])
		{
			[ship setCargoFlag: CARGO_FLAG_FULL_SCARCE];
			if ([ship hasRole:@"sunskim-trader"] && randf() < 0.25) // select 1/4 of the traders suitable for sunskimming.
			{
				[ship setCargoFlag: CARGO_FLAG_FULL_PLENTIFUL];
				[self makeSunSkimmer:ship andSetAI:YES];
			}
			else
			{
				[ship switchAITo:@"oolite-traderAI.js"];
			}
			
			if (([ship pendingEscortCount] > 0)&&((Ranrot() % 7) < government))	// remove escorts if we feel safe
			{
				int nx = [ship pendingEscortCount] - 2 * (1 + (Ranrot() & 3));	// remove 2,4,6, or 8 escorts
				[ship setPendingEscortCount:(nx > 0) ? nx : 0];
			}
		}
		if ([role isEqual:@"pirate"])
		{
			[ship setCargoFlag: CARGO_FLAG_PIRATE];
			[ship setBounty: (Ranrot() & 7) + (Ranrot() & 7) + ((randf() < 0.05)? 63 : 23) withReason:kOOLegalStatusReasonSetup];	// they already have a price on their heads
		}
		if (![ship crew] && ![ship isUnpiloted] && !([ship scanClass] == CLASS_CARGO || [ship scanClass] == CLASS_ROCK))
			[ship setCrew:[NSArray arrayWithObject:
				[OOCharacter randomCharacterWithRole:role
				andOriginalSystem: systems[Ranrot() & 255]]]];
		// The following is set inside leaveWitchspace: AI state GLOBAL, STATUS_EXITING_WITCHSPACE, ai message: EXITED_WITCHSPACE, then STATUS_IN_FLIGHT
		[ship leaveWitchspace];
		[ship release];
	}
}


// adds a ship within the collision radius of the other entity
- (ShipEntity *) spawnShipWithRole:(NSString *) desc near:(Entity *) entity
{
	if (entity == nil)  return nil;
	
	ShipEntity  *ship = nil;
	HPVector		spawn_pos;
	Quaternion	spawn_q;
	GLfloat		offset = (randf() + randf()) * entity->collision_radius;
	
	quaternion_set_random(&spawn_q);
	spawn_pos = HPvector_add([entity position], vectorToHPVector(vector_multiply_scalar(vector_forward_from_quaternion(spawn_q), offset)));
	
	ship = [self addShipWithRole:desc launchPos:spawn_pos rfactor:0.0];
	[ship setOrientation:spawn_q];
	
	return ship;
}


- (OOVisualEffectEntity *) addVisualEffectAt:(HPVector)pos withKey:(NSString *)key
{
	OOJS_PROFILE_ENTER
	
	// minimise the time between creating ship & assigning position.
	
	OOVisualEffectEntity  		*vis = [self newVisualEffectWithName:key]; // is retained
	BOOL				success = NO;
	if (vis != nil)
	{
		[vis setPosition:pos];
		[vis setOrientation:OORandomQuaternion()];
		
		success = [self addEntity:vis]; // retained globally now
		
		[vis release];
	}
	return success ? vis : (OOVisualEffectEntity *)nil;
	
	OOJS_PROFILE_EXIT
}


- (ShipEntity *) addShipAt:(HPVector)pos withRole:(NSString *)role withinRadius:(GLfloat)radius
{
	OOJS_PROFILE_ENTER
	
	// minimise the time between creating ship & assigning position.
	if (radius == NSNotFound)
	{
		GLfloat scalar = 1.0;
		[self coordinatesForPosition:pos withCoordinateSystem:@"abs" returningScalar:&scalar];
		//	randomise
		GLfloat rfactor = scalar;
		if (rfactor > SCANNER_MAX_RANGE)
			rfactor = SCANNER_MAX_RANGE;
		if (rfactor < 1000)
			rfactor = 1000;
		pos.x += rfactor*(randf() - randf());
		pos.y += rfactor*(randf() - randf());
		pos.z += rfactor*(randf() - randf());
	}
	else
	{
		pos = HPvector_add(pos, OOHPVectorRandomSpatial(radius));
	}
	
	ShipEntity  		*ship = [self newShipWithRole:role]; // is retained
	BOOL				success = NO;
	
	if (ship != nil)
	{
		[ship setPosition:pos];
		if ([ship hasRole:@"cargopod"]) [self fillCargopodWithRandomCargo:ship];
		OOScanClass scanClass = [ship scanClass];
		if (scanClass == CLASS_NOT_SET)
		{
			scanClass = CLASS_NEUTRAL;
			[ship setScanClass:scanClass];
		}
		
		if (!(scanClass == CLASS_CARGO || scanClass == CLASS_ROCK) && ![ship crew] && ![ship isUnpiloted])
		{
			[ship setCrew:[NSArray arrayWithObject:
				[OOCharacter randomCharacterWithRole:role
				andOriginalSystem:systems[Ranrot() & 255]]]];
		}
		
		[ship setOrientation:OORandomQuaternion()];
		
		BOOL trader = [role isEqualToString:@"trader"];
		if (trader)
		{
			// half of traders created anywhere will now have cargo. 
			if (randf() > 0.5f)
			{
				[ship setCargoFlag:(randf() < 0.66f ? CARGO_FLAG_FULL_PLENTIFUL : CARGO_FLAG_FULL_SCARCE)];	// most of them will carry the cargo produced in-system.
			}
			
			uint8_t pendingEscortCount = [ship pendingEscortCount];
			if (pendingEscortCount > 0)
			{
				OOGovernmentID government = [[self currentSystemData] oo_unsignedCharForKey:KEY_GOVERNMENT];
				if ((Ranrot() % 7) < government)	// remove escorts if we feel safe
				{
					int nx = pendingEscortCount - 2 * (1 + (Ranrot() & 3));	// remove 2,4,6, or 8 escorts
					[ship setPendingEscortCount:(nx > 0) ? nx : 0];
				}
			}
		}
		
		if (HPdistance([self getWitchspaceExitPosition], pos) > SCANNER_MAX_RANGE)
		{
			// nothing extra to do
			success = [self addEntity:ship];	// STATUS_IN_FLIGHT, AI state GLOBAL - ship is retained globally			
		}
		else	// witchspace incoming traders & pirates need extra settings.
		{
			if (trader)
			{
				[ship setCargoFlag:CARGO_FLAG_FULL_SCARCE];
				if ([ship hasRole:@"sunskim-trader"] && randf() < 0.25) 
				{
					[ship setCargoFlag:CARGO_FLAG_FULL_PLENTIFUL];
					[self makeSunSkimmer:ship andSetAI:YES];
				}
				else
				{
					[ship switchAITo:@"oolite-traderAI.js"];
				}
			}
			else if ([role isEqual:@"pirate"])
			{
				[ship setBounty:(Ranrot() & 7) + (Ranrot() & 7) + ((randf() < 0.05)? 63 : 23) withReason:kOOLegalStatusReasonSetup];	// they already have a price on their heads
			}
			
			// Status changes inside the following call: AI state GLOBAL, then STATUS_EXITING_WITCHSPACE, 
			// with the EXITED_WITCHSPACE message sent to the AI. At last we set STATUS_IN_FLIGHT.
			// Includes addEntity, so ship is retained globally.
			success = [ship witchspaceLeavingEffects];
		}
		
		[ship release];
	}
	return success ? ship : (ShipEntity *)nil;
	
	OOJS_PROFILE_EXIT
}


- (NSArray *) addShipsAt:(HPVector)pos withRole:(NSString *)role quantity:(unsigned)count withinRadius:(GLfloat)radius asGroup:(BOOL)isGroup
{
	OOJS_PROFILE_ENTER
	
	NSMutableArray		*ships = [NSMutableArray arrayWithCapacity:count];
	ShipEntity			*ship = nil;
	OOShipGroup			*group = nil;
	
	if (isGroup)
	{
		group = [OOShipGroup groupWithName:[NSString stringWithFormat:@"%@ group", role]];
	}
	
	while (count--)
	{
		ship = [self addShipAt:pos withRole:role withinRadius:radius];
		if (ship != nil)
		{
			// TODO: avoid collisions!!!
			if (isGroup) [ship setGroup:group];
			[ships addObject:ship];
		}
	}
	
	if ([ships count] == 0) return nil;
	
	return [[ships copy] autorelease];
	
	OOJS_PROFILE_EXIT
}


- (NSArray *) addShipsToRoute:(NSString *)route withRole:(NSString *)role quantity:(unsigned)count routeFraction:(double)routeFraction asGroup:(BOOL)isGroup
{
	NSMutableArray			*ships = [NSMutableArray arrayWithCapacity:count];
	ShipEntity				*ship = nil;
	Entity<OOStellarBody>	*entity = nil;
	HPVector					pos = kZeroHPVector, direction = kZeroHPVector, point0 = kZeroHPVector, point1 = kZeroHPVector;
	double					radius = 0;
	
	if ([route isEqualToString:@"pw"] || [route isEqualToString:@"sw"] || [route isEqualToString:@"ps"])
	{
		routeFraction = 1.0f - routeFraction; 
	}
	
	// which route is it?
	if ([route isEqualTo:@"wp"] || [route isEqualTo:@"pw"])
	{
		point0 = [self getWitchspaceExitPosition];
		entity = [self planet];
		if (entity == nil)  return nil;
		point1 = [entity position];
		radius = [entity radius];
	}
	else if ([route isEqualTo:@"ws"] || [route isEqualTo:@"sw"])
	{
		point0 = [self getWitchspaceExitPosition];
		entity = [self sun];
		if (entity == nil)  return nil;
		point1 = [entity position];
		radius = [entity radius];
	}
	else if ([route isEqualTo:@"sp"] || [route isEqualTo:@"ps"])
	{
		entity = [self sun];
		if (entity == nil)  return nil;
		point0 = [entity position];
		double radius0 = [entity radius];
		
		entity = [self planet];
		if (entity == nil)  return nil;
		point1 = [entity position];
		radius = [entity radius];
		
		// shorten the route by scanner range & sun radius, otherwise ships could be created inside it.
		direction = HPvector_normal(HPvector_subtract(point0, point1));
		point0 = HPvector_subtract(point0, HPvector_multiply_scalar(direction, radius0 + SCANNER_MAX_RANGE * 1.1f));
	}
	else if ([route isEqualTo:@"st"])
	{
		point0 = [self getWitchspaceExitPosition];
		if ([self station] == nil)  return nil;
		point1 = [[self station] position];
		radius = [[self station] collisionRadius];
	}
	else return nil;	// no route specifier? We shouldn't be here!
	
	// shorten the route by scanner range & radius, otherwise ships could be created inside the route destination.
	direction = HPvector_normal(HPvector_subtract(point1, point0));
	point1 = HPvector_subtract(point1, HPvector_multiply_scalar(direction, radius + SCANNER_MAX_RANGE * 1.1f));
	
	pos = [self fractionalPositionFrom:point0 to:point1 withFraction:routeFraction];
	if(isGroup)
	{	
		return [self addShipsAt:pos withRole:role quantity:count withinRadius:(SCANNER_MAX_RANGE / 10.0f) asGroup:YES];
	}
	else
	{
		while (count--)
		{
			ship = [self addShipAt:pos withRole:role withinRadius:0]; // no radius because pos is already randomised with SCANNER_MAX_RANGE.
			if (ship != nil) [ships addObject:ship];
			if (count > 0) pos = [self fractionalPositionFrom:point0 to:point1 withFraction:routeFraction];
		}
		
		if ([ships count] == 0) return nil;
	}
	
	return [[ships copy] autorelease];
}


- (BOOL) roleIsPirateVictim:(NSString *)role
{
	return [self role:role isInCategory:@"oolite-pirate-victim"];
}


- (BOOL) role:(NSString *)role isInCategory:(NSString *)category
{
	NSSet *categoryInfo = [roleCategories objectForKey:category];
	if (categoryInfo == nil)
	{
		return NO;
	}
	return [categoryInfo containsObject:role];
}


// used to avoid having lost escorts when player advances clock while docked
- (void) forceWitchspaceEntries
{
	unsigned i;
	for (i = 0; i < n_entities; i++)
	{
		if (sortedEntities[i]->isShip)
		{
			ShipEntity *my_ship = (ShipEntity*)sortedEntities[i];
			Entity* my_target = [my_ship primaryTarget];
			if ([my_target isWormhole])
			{
				[my_ship enterTargetWormhole];
			}
			else if ([[[my_ship getAI] state] isEqualToString:@"ENTER_WORMHOLE"])
			{
				[my_ship enterTargetWormhole];
			}
		}
	}
}


- (void) addWitchspaceJumpEffectForShip:(ShipEntity *)ship
{
	// don't add rings when system is being populated
	if ([PLAYER status] != STATUS_ENTERING_WITCHSPACE && [PLAYER status] != STATUS_EXITING_WITCHSPACE)
	{
		[self addEntity:[OORingEffectEntity ringFromEntity:ship]];
		[self addEntity:[OORingEffectEntity shrinkingRingFromEntity:ship]];
	}
}


- (GLfloat) safeWitchspaceExitDistance
{
	for (unsigned i = 0; i < n_entities; i++)
	{
		Entity *e2 = sortedEntities[i];
		if ([e2 isShip] && [(ShipEntity*)e2 hasPrimaryRole:@"buoy-witchpoint"])
		{
			return [(ShipEntity*)e2 collisionRadius] + MIN_DISTANCE_TO_BUOY;
		}
	}
	return MIN_DISTANCE_TO_BUOY;
}


- (void) setUpBreakPattern:(HPVector) pos orientation:(Quaternion) q forDocking:(BOOL) forDocking
{
	int						i;
	OOBreakPatternEntity	*ring = nil;
	id						colorDesc = nil;
	OOColor					*color = nil;
	
	[self setViewDirection:VIEW_FORWARD];
	
	q.w = -q.w;		// reverse the quaternion because this is from the player's viewpoint
	
	Vector			v = vector_forward_from_quaternion(q);
	Vector			vel = vector_multiply_scalar(v, -BREAK_PATTERN_RING_SPEED);
	
	// hyperspace colours
	
	OOColor *col1 = [OOColor colorWithRed:1.0 green:0.0 blue:0.0 alpha:0.5];	//standard tunnel colour
	OOColor *col2 = [OOColor colorWithRed:0.0 green:0.0 blue:1.0 alpha:0.25];	//standard tunnel colour
	
	colorDesc = [[self planetInfo] objectForKey:@"hyperspace_tunnel_color_1"];
	if (colorDesc != nil)
	{
		color = [OOColor colorWithDescription:colorDesc];
		if (color != nil)  col1 = color;
		else  OOLogWARN(@"hyperspaceTunnel.fromDict", @"could not interpret \"%@\" as a colour.", colorDesc);
	}
	colorDesc = [[self planetInfo] objectForKey:@"hyperspace_tunnel_color_2"];
	if (colorDesc != nil)
	{
		color = [OOColor colorWithDescription:colorDesc];
		if (color != nil)  col2 = color;
		else  OOLogWARN(@"hyperspaceTunnel.fromDict", @"could not interpret \"%@\" as a colour.", colorDesc);
	}
	
	unsigned	sides = kOOBreakPatternMaxSides;
	GLfloat		startAngle = 0;
	GLfloat		aspectRatio = 1;
	
	if (forDocking)
	{
		NSDictionary *info = [[PLAYER dockedStation] shipInfoDictionary];
		sides = [info oo_unsignedIntForKey:@"tunnel_corners" defaultValue:4];
		startAngle = [info oo_floatForKey:@"tunnel_start_angle" defaultValue:45.0f];
		aspectRatio = [info oo_floatForKey:@"tunnel_aspect_ratio" defaultValue:2.67f];
	}
	
	for (i = 1; i < 11; i++)
	{
		ring = [OOBreakPatternEntity breakPatternWithPolygonSides:sides startAngle:startAngle aspectRatio:aspectRatio];
		if (!forDocking)
		{
			[ring setInnerColor:col1 outerColor:col2];
		}
		
		Vector offset = vector_multiply_scalar(v, i * BREAK_PATTERN_RING_SPACING);
		[ring setPosition:HPvector_add(pos, vectorToHPVector(offset))];  // ahead of the player
		[ring setOrientation:q];
		[ring setVelocity:vel];
		[ring setLifetime:i * BREAK_PATTERN_RING_SPACING];
		
		// FIXME: better would be to have break pattern timing not depend on
		// these ring objects existing in the first place. - CIM
		if (forDocking && ![[PLAYER dockedStation] hasBreakPattern])
		{
			ring->isImmuneToBreakPatternHide = NO;
		}
		else if (!forDocking && ![self witchspaceBreakPattern])
		{
			ring->isImmuneToBreakPatternHide = NO;
		}
		[self addEntity:ring];
		breakPatternCounter++;
	}
}


- (BOOL) witchspaceBreakPattern
{
	return _witchspaceBreakPattern;
}


- (void) setWitchspaceBreakPattern:(BOOL)newValue
{
	_witchspaceBreakPattern = !!newValue;
}


- (BOOL) dockingClearanceProtocolActive
{
	return _dockingClearanceProtocolActive;
}


- (void) setDockingClearanceProtocolActive:(BOOL)newValue
{
	OOShipRegistry	*registry = [OOShipRegistry sharedRegistry];
	NSEnumerator	*statEnum = [allStations objectEnumerator]; 
	StationEntity	*station = nil;

	/* CIM: picking a random ship type which can take the same primary
	 * role as the station to determine whether it has no set docking
	 * clearance requirements seems unlikely to work entirely
	 * correctly. To be fixed. */
						   
	while ((station = [statEnum nextObject]))
	{
		NSString	*stationKey = [registry randomShipKeyForRole:[station primaryRole]];
		if (![[[registry shipInfoForKey:stationKey] allKeys] containsObject:@"requires_docking_clearance"])
		{
			[station setRequiresDockingClearance:!!newValue];
		}
	}
	
	_dockingClearanceProtocolActive = !!newValue;
}


- (void) handleGameOver
{
	if ([[self gameController] playerFileToLoad])
  {
    [[self gameController] loadPlayerIfRequired];
  }
  else
  {
    [self reinitAndShowDemo:NO];
  } 
}


- (void) setupIntroFirstGo:(BOOL)justCobra
{
	PlayerEntity	*player = PLAYER;
	ShipEntity		*ship = nil;
	Quaternion		q2 = { 0.0f, 0.0f, 1.0f, 0.0f }; // w,x,y,z
	
	// in status demo draw ships and display text
	if (!justCobra)
	{
		// Kaks - smooth transition from intro1 to intro2
		if (![[demo_ship shipDataKey] isEqualTo:PLAYER_SHIP_DESC])
		{
			[self removeDemoShips];
		}
	}
	[player setStatus: STATUS_START_GAME];
	[player setShowDemoShips: YES];
	displayGUI = YES;
	
	if (justCobra)
	{
		/*- cobra - intro1 -*/
		ship = [self newShipWithName:PLAYER_SHIP_DESC usePlayerProxy:YES];
	}
	else
	{
		/*- demo ships - intro2 -*/
		demo_ship_index = 0;
		if (!demo_ship) ship = [self newShipWithName:[demo_ships oo_stringAtIndex:0] usePlayerProxy:YES];
	}
	
	if (ship)
	{
		[ship setOrientation:q2];
		[ship setPositionX:0.0f y:0.0f z:3.6f * ship->collision_radius];
		if (!justCobra)
		{
			[ship setDestination: ship->position];	// ideal position
		}
		[ship setScanClass: CLASS_NO_DRAW];
		[ship setRoll:M_PI/5.0];
		[ship setPitch:M_PI/10.0];
		[ship switchAITo:@"nullAI.plist"];
		if([ship pendingEscortCount] > 0) [ship setPendingEscortCount:0];
		[self addEntity:ship];	// STATUS_IN_FLIGHT, AI state GLOBAL
		// now override status
		[ship setStatus:STATUS_COCKPIT_DISPLAY];
		demo_ship = ship;
		
		[ship release];
	}
	
	if (!justCobra)
	{
		[gui setText:[demo_ship displayName] forRow:19 align:GUI_ALIGN_CENTER];
		[gui setColor:[OOColor whiteColor] forRow:19];
	}
	
	[self enterGUIViewModeWithMouseInteraction:NO];
	if (!justCobra)
	{
		demo_stage = DEMO_SHOW_THING;
		demo_stage_time = universal_time + 6.0;
	}
}


- (void) selectIntro2Previous
{
	demo_stage = DEMO_SHOW_THING;
	demo_ship_index = (demo_ship_index + [demo_ships count] - 2) % [demo_ships count];
	demo_stage_time  = universal_time - 1.0;	// force change
}


- (void) selectIntro2Next
{
	demo_stage = DEMO_SHOW_THING;
	demo_stage_time  = universal_time - 1.0;	// force change
}


static BOOL IsCandidateMainStationPredicate(Entity *entity, void *parameter)
{
	return [entity isStation] && !entity->isExplicitlyNotMainStation;
}


static BOOL IsFriendlyStationPredicate(Entity *entity, void *parameter)
{
	return [entity isStation] && ![(ShipEntity *)entity isHostileTo:parameter];
}


- (StationEntity *) station
{
	if (cachedSun != nil && cachedStation == nil)
	{
		cachedStation = [self findOneEntityMatchingPredicate:IsCandidateMainStationPredicate
												   parameter:nil];
	}
	return cachedStation;
}


- (StationEntity *) stationWithRole:(NSString *)role andPosition:(HPVector)position
{
	if ([role isEqualToString:@""])
	{
		return nil;
	}

	float range = 1000000; // allow a little variation in position

	NSArray *stations = [self stations];
	StationEntity *station = nil;
	foreach (station, stations)
	{
		if (HPdistance2(position,[station position]) < range)
		{
			if ([[station primaryRole] isEqualToString:role])
			{
				return station;
			}
		}
	}
	return nil;
}


- (StationEntity *) stationFriendlyTo:(ShipEntity *) ship
{
	// In interstellar space we select a random friendly carrier as mainStation.
	// No caching: friendly status can change!
	return [self findOneEntityMatchingPredicate:IsFriendlyStationPredicate parameter:ship];
}


- (OOPlanetEntity *) planet
{
	if (cachedPlanet == nil && [allPlanets count] > 0)
	{
		cachedPlanet = [allPlanets objectAtIndex:0];
	}
	return cachedPlanet;
}


- (OOSunEntity *) sun
{
	if (cachedSun == nil)
	{
		cachedSun = [self findOneEntityMatchingPredicate:IsSunPredicate parameter:nil];
	}
	return cachedSun;
}


- (NSArray *) planets
{
	return allPlanets;
}


- (NSArray *) stations
{
	return [allStations allObjects];
}


- (NSArray *) wormholes
{
	return activeWormholes;
}


- (void) unMagicMainStation
{
	/*	During the demo screens, the player must remain docked in order for the
		UI to work. This means either enforcing invulnerability or launching
		the player when the station is destroyed even if on the "new game Y/N"
		screen.
		
		The latter is a) weirder and b) harder. If your OXP relies on being
		able to destroy the main station before the game has even started,
		your OXP sucks.
	*/
	OOEntityStatus playerStatus = [PLAYER status];
	if (playerStatus == STATUS_START_GAME)  return;
	
	StationEntity *theStation = [self station];
	if (theStation != nil)  theStation->isExplicitlyNotMainStation = YES;
	cachedStation = nil;
}


- (void) resetBeacons
{
	Entity <OOBeaconEntity> *beaconShip = [self firstBeacon], *next = nil;
	while (beaconShip)
	{
		next = [beaconShip nextBeacon];
		[beaconShip setPrevBeacon:nil];
		[beaconShip setNextBeacon:nil];
		beaconShip = next;
	}
	
	[self setFirstBeacon:nil];
	[self setLastBeacon:nil];
}


- (Entity <OOBeaconEntity> *) firstBeacon
{
	return [_firstBeacon weakRefUnderlyingObject];
}


- (void) setFirstBeacon:(Entity <OOBeaconEntity> *)beacon
{
	if (beacon != [self firstBeacon])
	{
		[beacon setPrevBeacon:nil];
		[beacon setNextBeacon:[self firstBeacon]];
		[[self firstBeacon] setPrevBeacon:beacon];
		[_firstBeacon release];
		_firstBeacon = [beacon weakRetain];
	}
}


- (Entity <OOBeaconEntity> *) lastBeacon
{
	return [_lastBeacon weakRefUnderlyingObject];
}


- (void) setLastBeacon:(Entity <OOBeaconEntity> *)beacon
{
	if (beacon != [self lastBeacon])
	{
		[beacon setNextBeacon:nil];
		[beacon setPrevBeacon:[self lastBeacon]];
		[[self lastBeacon] setNextBeacon:beacon];
		[_lastBeacon release];
		_lastBeacon = [beacon weakRetain];
	}
}


- (void) setNextBeacon:(Entity <OOBeaconEntity> *) beaconShip
{
	if ([beaconShip isBeacon])
	{
		[self setLastBeacon:beaconShip];
		if ([self firstBeacon] == nil)  [self setFirstBeacon:beaconShip];
	}
	else
	{
		OOLog(@"universe.beacon.error", @"***** ERROR: Universe setNextBeacon '%@'. The ship has no beacon code set.", beaconShip);
	}
}


- (void) clearBeacon:(Entity <OOBeaconEntity> *) beaconShip
{
	Entity <OOBeaconEntity>				*tmp = nil;

	if ([beaconShip isBeacon])
	{
		if ([self firstBeacon] == beaconShip)
		{
			tmp = [[beaconShip nextBeacon] nextBeacon];
			[self setFirstBeacon:[beaconShip nextBeacon]];
			[[beaconShip prevBeacon] setNextBeacon:tmp];
		}
		else if ([self lastBeacon] == beaconShip)
		{
			tmp = [[beaconShip prevBeacon] prevBeacon];
			[self setLastBeacon:[beaconShip prevBeacon]];
			[[beaconShip nextBeacon] setPrevBeacon:tmp];
		}
		else
		{
			[[beaconShip nextBeacon] setPrevBeacon:[beaconShip prevBeacon]];
			[[beaconShip prevBeacon] setNextBeacon:[beaconShip nextBeacon]];
		}
		[beaconShip setBeaconCode:nil];
	}
}


- (NSDictionary *) currentWaypoints
{
	return waypoints;
}


- (void) defineWaypoint:(NSDictionary *)definition forKey:(NSString *)key
{
	OOWaypointEntity *waypoint = nil;
	waypoint = [waypoints objectForKey:key];
	if (waypoint != nil)
	{
		[self removeEntity:waypoint];
		[waypoints removeObjectForKey:key];
	}
	if (definition != nil)
	{
		waypoint = [OOWaypointEntity waypointWithDictionary:definition];
		if (waypoint != nil)
		{
			[self addEntity:waypoint];
			[waypoints setObject:waypoint forKey:key];
		}
	}
}


- (GLfloat *) skyClearColor
{
	return skyClearColor;
}


- (void) setSkyColorRed:(GLfloat)red green:(GLfloat)green blue:(GLfloat)blue alpha:(GLfloat)alpha
{
	skyClearColor[0] = red;
	skyClearColor[1] = green;
	skyClearColor[2] = blue;
	skyClearColor[3] = alpha;
	airResistanceFactor = alpha;
}


- (BOOL) breakPatternOver
{
	return (breakPatternCounter == 0);
}


- (BOOL) breakPatternHide
{
	Entity* player = PLAYER;
	return ((breakPatternCounter > 5)||(!player)||([player status] == STATUS_DOCKING));
}


#define PROFILE_SHIP_SELECTION 0


- (BOOL) canInstantiateShip:(NSString *)shipKey
{
	NSDictionary			*shipInfo = nil;
	NSArray					*conditions = nil;
	NSString  *condition_script = nil;
	shipInfo = [[OOShipRegistry sharedRegistry] shipInfoForKey:shipKey];

	condition_script = [shipInfo oo_stringForKey:@"condition_script"];
	if (condition_script != nil)
	{
		OOJSScript *condScript = [self getConditionScript:condition_script];
		if (condScript != nil) // should always be non-nil, but just in case
		{
			JSContext			*context = OOJSAcquireContext();
			BOOL OK;
			JSBool allow_instantiation;
			jsval result;
			jsval args[] = { OOJSValueFromNativeObject(context, shipKey) };
			
			OOJSStartTimeLimiter();
			OK = [condScript callMethod:OOJSID("allowSpawnShip")
						  inContext:context
					  withArguments:args count:sizeof args / sizeof *args
							 result:&result];
			OOJSStopTimeLimiter();

			if (OK) OK = JS_ValueToBoolean(context, result, &allow_instantiation);
			
			OOJSRelinquishContext(context);

			if (OK && !allow_instantiation)
			{
				/* if the script exists, the function exists, the function
				 * returns a bool, and that bool is false, block
				 * instantiation. Otherwise allow it as default */
				return NO;
			}
		}
	}

	conditions = [shipInfo oo_arrayForKey:@"conditions"];
	if (conditions == nil)  return YES;
	
	// Check conditions
	return [PLAYER scriptTestConditions:conditions];
}


- (NSString *) randomShipKeyForRoleRespectingConditions:(NSString *)role
{
	OOJS_PROFILE_ENTER
	
	OOShipRegistry			*registry = [OOShipRegistry sharedRegistry];
	NSString				*shipKey = nil;
	OOMutableProbabilitySet	*pset = nil;
	
#if PROFILE_SHIP_SELECTION
	static unsigned long	profTotal = 0, profSlowPath = 0;
	++profTotal;
#endif
	
	// Select a ship, check conditions and return it if possible.
	shipKey = [registry randomShipKeyForRole:role];
	if ([self canInstantiateShip:shipKey])  return shipKey;
	
	/*	If we got here, condition check failed.
		We now need to keep trying until we either find an acceptable ship or
		run out of candidates.
		This is special-cased because it has more overhead than the more
		common conditionless lookup.
	*/
	
#if PROFILE_SHIP_SELECTION
	++profSlowPath;
	if ((profSlowPath % 10) == 0)	// Only print every tenth slow path, to reduce spamminess.
	{
		OOLog(@"shipRegistry.selection.profile", @"Hit slow path in ship selection for role \"%@\", having selected ship \"%@\". Now %lu of %lu on slow path (%f%%).", role, shipKey, profSlowPath, profTotal, ((double)profSlowPath)/((double)profTotal) * 100.0f);
	}
#endif
	
	pset = [[[registry probabilitySetForRole:role] mutableCopy] autorelease];
	
	while ([pset count] > 0)
	{
		// Select a ship, check conditions and return it if possible.
		shipKey = [pset randomObject];
		if ([self canInstantiateShip:shipKey])  return shipKey;
		
		// Condition failed -> remove ship from consideration.
		[pset removeObject:shipKey];
	}
	
	// If we got here, some ships existed but all failed conditions test.
	return nil;
	
	OOJS_PROFILE_EXIT
}


- (ShipEntity *) newShipWithRole:(NSString *)role
{
	OOJS_PROFILE_ENTER
	
	ShipEntity				*ship = nil;
	NSString				*shipKey = nil;
	NSDictionary			*shipInfo = nil;
	NSString				*autoAI = nil;
	
	shipKey = [self randomShipKeyForRoleRespectingConditions:role];
	if (shipKey != nil)
	{
		ship = [self newShipWithName:shipKey];
		if (ship != nil)
		{
			[ship setPrimaryRole:role];
			
			shipInfo = [[OOShipRegistry sharedRegistry] shipInfoForKey:shipKey];
			if ([shipInfo oo_fuzzyBooleanForKey:@"auto_ai" defaultValue:YES])
			{
				// Set AI based on role
				autoAI = [self defaultAIForRole:role];
				if (autoAI != nil)
				{
					[ship setAITo:autoAI];
					// Nikos 20090604
					// Pirate, trader or police with auto_ai? Follow populator rules for them.
					if ([role isEqualToString:@"pirate"]) [ship setBounty:20 + randf() * 50 withReason:kOOLegalStatusReasonSetup];
					if ([role isEqualToString:@"trader"]) [ship setBounty:0 withReason:kOOLegalStatusReasonSetup];
					if ([role isEqualToString:@"police"]) [ship setScanClass:CLASS_POLICE];
					if ([role isEqualToString:@"interceptor"])
					{
						[ship setScanClass: CLASS_POLICE];
						[ship setPrimaryRole:@"police"]; // to make sure interceptors get the correct pilot later on.
					}
				}
				if ([role isEqualToString:@"thargoid"]) [ship setScanClass: CLASS_THARGOID]; // thargoids are not on the autoAIMap
			}
		}
	}
	
	return ship;
	
	OOJS_PROFILE_EXIT
}


- (OOVisualEffectEntity *) newVisualEffectWithName:(NSString *)effectKey
{
	OOJS_PROFILE_ENTER
	
	NSDictionary			*effectDict = nil;
	OOVisualEffectEntity	*effect = nil;
	
	effectDict = [[OOShipRegistry sharedRegistry] effectInfoForKey:effectKey];
	if (effectDict == nil)  return nil;
	
	@try
	{
		effect = [[OOVisualEffectEntity alloc] initWithKey:effectKey definition:effectDict];
	}
	@catch (NSException *exception)
	{
		if ([[exception name] isEqual:OOLITE_EXCEPTION_DATA_NOT_FOUND])
		{
			OOLog(kOOLogException, @"***** Oolite Exception : '%@' in [Universe newVisualEffectWithName: %@ ] *****", [exception reason], effectKey);
		}
		else  @throw exception;
	}
	
	return effect;
	
	OOJS_PROFILE_EXIT
}


- (ShipEntity *) newSubentityWithName:(NSString *)shipKey
{
	return [self newShipWithName:shipKey usePlayerProxy:NO isSubentity:YES];
}


- (ShipEntity *) newShipWithName:(NSString *)shipKey usePlayerProxy:(BOOL)usePlayerProxy
{
	return [self newShipWithName:shipKey usePlayerProxy:usePlayerProxy isSubentity:NO];
}


- (ShipEntity *) newShipWithName:(NSString *)shipKey usePlayerProxy:(BOOL)usePlayerProxy isSubentity:(BOOL)isSubentity
{
	OOJS_PROFILE_ENTER
	
	NSDictionary	*shipDict = nil;
	ShipEntity		*ship = nil;
	
	shipDict = [[OOShipRegistry sharedRegistry] shipInfoForKey:shipKey];
	if (shipDict == nil)  return nil;
	
	volatile Class shipClass = nil;
	if (isSubentity)
	{
		shipClass = [ShipEntity class];
	}
	else
	{
		shipClass = [self shipClassForShipDictionary:shipDict];
		if (usePlayerProxy && shipClass == [ShipEntity class])
		{
			shipClass = [ProxyPlayerEntity class];
		}
	}
	
	@try
	{
		ship = [[shipClass alloc] initWithKey:shipKey definition:shipDict];
	}
	@catch (NSException *exception)
	{
		if ([[exception name] isEqual:OOLITE_EXCEPTION_DATA_NOT_FOUND])
		{
			OOLog(kOOLogException, @"***** Oolite Exception : '%@' in [Universe newShipWithName: %@ ] *****", [exception reason], shipKey);
		}
		else  @throw exception;
	}
	
	// Set primary role to same as ship name, if ship name is also a role.
	// Otherwise, if caller doesn't set a role, one will be selected randomly.
	if ([ship hasRole:shipKey])  [ship setPrimaryRole:shipKey];
	
	return ship;
	
	OOJS_PROFILE_EXIT
}


- (DockEntity *) newDockWithName:(NSString *)shipDataKey
{
	OOJS_PROFILE_ENTER
	
	NSDictionary	*shipDict = nil;
	DockEntity		*dock = nil;
	
	shipDict = [[OOShipRegistry sharedRegistry] shipInfoForKey:shipDataKey];
	if (shipDict == nil)  return nil;
	
	@try
	{
		dock = [[DockEntity alloc] initWithKey:shipDataKey definition:shipDict];
	}
	@catch (NSException *exception)
	{
		if ([[exception name] isEqual:OOLITE_EXCEPTION_DATA_NOT_FOUND])
		{
			OOLog(kOOLogException, @"***** Oolite Exception : '%@' in [Universe newDockWithName: %@ ] *****", [exception reason], shipDataKey);
		}
		else  @throw exception;
	}
	
	// Set primary role to same as name, if ship name is also a role.
	// Otherwise, if caller doesn't set a role, one will be selected randomly.
	if ([dock hasRole:shipDataKey])  [dock setPrimaryRole:shipDataKey];
	
	return dock;
	
	OOJS_PROFILE_EXIT
}


- (ShipEntity *) newShipWithName:(NSString *)shipKey
{
	return [self newShipWithName:shipKey usePlayerProxy:NO];
}


- (Class) shipClassForShipDictionary:(NSDictionary *)dict
{
	OOJS_PROFILE_ENTER
	
	if (dict == nil)  return Nil;
	
	BOOL		isStation = NO;
	NSString	*shipRoles = [dict oo_stringForKey:@"roles"];
	
	if (shipRoles != nil)
	{
		isStation = [shipRoles rangeOfString:@"station"].location != NSNotFound ||
		[shipRoles rangeOfString:@"carrier"].location != NSNotFound;
	}
	
	// Note priority here: is_carrier overrides isCarrier which overrides roles.
	isStation = [dict oo_boolForKey:@"isCarrier" defaultValue:isStation];
	isStation = [dict oo_boolForKey:@"is_carrier" defaultValue:isStation];
	

	return isStation ? [StationEntity class] : [ShipEntity class];
	
	OOJS_PROFILE_EXIT
}


- (NSString *)defaultAIForRole:(NSString *)role
{
	return [autoAIMap oo_stringForKey:role];
}


- (OOCargoQuantity) maxCargoForShip:(NSString *) desc
{
	return [[[OOShipRegistry sharedRegistry] shipInfoForKey:desc] oo_unsignedIntForKey:@"max_cargo" defaultValue:0];
}

/*
 * Price for an item expressed in 10ths of credits (divide by 10 to get credits)
 */
- (OOCreditsQuantity) getEquipmentPriceForKey:(NSString *)eq_key
{
	NSArray *itemData;
	foreach (itemData, equipmentData)
	{
		NSString *itemType = [itemData oo_stringAtIndex:EQUIPMENT_KEY_INDEX];
		
		if ([itemType isEqual:eq_key])
		{
			return [itemData oo_unsignedLongLongAtIndex:EQUIPMENT_PRICE_INDEX];
		}
	}
	return 0;
}


- (int) legalStatusOfCommodity:(NSString *)commodity
{
	return [illegalGoods oo_unsignedIntForKey:commodity defaultValue:0];
}


- (int) legalStatusOfManifest:(NSArray *)manifest
{
	unsigned				penalty = 0;
	NSString				*commodity = nil;
	OOCargoQuantity			amount;
	NSArray					*entry = nil;
	unsigned				penaltyPerUnit;
	
	foreach (entry, manifest)
	{
		commodity = [entry oo_stringAtIndex:MARKET_NAME];
		amount = [entry oo_unsignedIntAtIndex:MARKET_QUANTITY];
		
		penaltyPerUnit = [illegalGoods oo_unsignedIntForKey:commodity defaultValue:0];
		penalty += amount * penaltyPerUnit;
	}
	return penalty;
}


/* Converts template cargo pods to real ones */
- (ShipEntity *) reifyCargoPod:(ShipEntity *)cargoObj
{
	if ([cargoObj isTemplateCargoPod])
	{
		return [UNIVERSE cargoPodFromTemplate:cargoObj];
	}
	else
	{
		return cargoObj;
	}
}


- (ShipEntity *) cargoPodFromTemplate:(ShipEntity *)cargoObj
{
	ShipEntity *container = nil;
	// this is a template container, so we need to make a real one
	OOCommodityType co_type = [cargoObj commodityType];
	OOCargoQuantity co_amount = [UNIVERSE getRandomAmountOfCommodity:co_type];
	if (randf() < 0.5) // stops OXP monopolising pods for commodities
	{
		container = [UNIVERSE newShipWithRole: [UNIVERSE symbolicNameForCommodity:co_type]]; 
	}
	if (container == nil)
	{
		container = [UNIVERSE newShipWithRole:@"cargopod"]; 
	}
	[container setCommodity:co_type andAmount:co_amount];
	return container;
}


- (NSArray *) getContainersOfGoods:(OOCargoQuantity)how_many scarce:(BOOL)scarce legal:(BOOL)legal
{
	/*	build list of goods allocating 0..100 for each based on how much of
		each quantity there is. Use a ratio of n x 100/64 for plentiful goods;
		reverse the probabilities for scarce goods.
	*/
	NSMutableArray  *accumulator = [NSMutableArray arrayWithCapacity:how_many];
	NSUInteger		i, commodityCount = [commodityData count];
	OOCargoQuantity quantities[commodityCount];
	OOCargoQuantity total_quantity = 0;
	
	for (i = 0; i < commodityCount; i++)
	{
		/* NOTE: There's an oddity here in that commodityData is not
		 * actually used anywhere for trading - the main station market is
		 * [[UNIVERSE station] localMarket] and is accessed that way in
		 * flight. So the quantities generated by this function don't
		 * actually match the local visible market at all, but an
		 * invisible market with the same distribution. This is perhaps a
		 * good thing, since it stops the player manipulating cargo
		 * generation by selectively buying and selling at the main
		 * station, but it can give somewhat odd results, especially with
		 * the highly variable Narcotics. - CIM */
		OOCargoQuantity q = [[commodityData oo_arrayAtIndex:i] oo_unsignedIntAtIndex:MARKET_QUANTITY];
		if (scarce)
		{
			if (q < 64)  q = 64 - q;
			else  q = 0;
		}
		// legal YES restricts (almost) only to legal goods
		// legal NO allows illegal goods, but not necessarily a full hold
		if (legal && [self legalStatusOfCommodity:[[commodityData oo_arrayAtIndex:i] oo_stringAtIndex:MARKET_NAME]] > 0)
		{
			q &= 1; // keep a very small chance, sometimes
		}
		if (q > 64) q = 64;
		q *= 100;   q/= 64;
		quantities[i] = q;
		total_quantity += q;
	}
	// quantities is now used to determine which good get into the containers
	for (i = 0; i < how_many; i++)
	{
		OOCommodityType co_type = COMMODITY_FOOD;
		
		int qr=0;
		if(total_quantity)
		{
			qr = 1+(Ranrot() % total_quantity);
			co_type = COMMODITY_FOOD;
			while (qr > 0)
			{
				NSAssert((NSUInteger)co_type < commodityCount, @"Commodity type index out of range.");
				qr -= quantities[co_type++];
			}
			co_type--;
		}

		ShipEntity *container = [cargoPods objectForKey:[NSNumber numberWithInt:co_type]];
		
		if (container != nil)
		{
			[accumulator addObject:container];
		}
		else
		{
			OOLog(@"universe.createContainer.failed", @"***** ERROR: failed to find a container to fill with %ld.", co_type);

		}
	}
	return [NSArray arrayWithArray:accumulator];	
}


- (NSArray *) getContainersOfDrugs:(OOCargoQuantity)how_many
{
	return [self getContainersOfCommodity:@"Narcotics" :how_many];	
}


- (NSArray *) getContainersOfCommodity:(NSString *)commodity_name :(OOCargoQuantity)how_much
{
	NSMutableArray	*accumulator = [NSMutableArray arrayWithCapacity:how_much];
	OOCommodityType	commodity_type = [self commodityForName:commodity_name];
	if (commodity_type == COMMODITY_UNDEFINED)  return [NSArray array]; // empty array
	
	while (how_much > 0)
	{
		ShipEntity *container = [cargoPods objectForKey:[NSNumber numberWithInt:commodity_type]];
		if (container)
		{
			[accumulator addObject:container];
		}
		else
		{
			OOLog(@"universe.createContainer.failed", @"***** ERROR: failed to find a container to fill with %ld.", commodity_type);
		}

		how_much--;
	}
	return [NSArray arrayWithArray:accumulator];	
}


- (void) fillCargopodWithRandomCargo:(ShipEntity *)cargopod
{
	if (cargopod == nil || ![cargopod hasRole:@"cargopod"] || [cargopod cargoType] == CARGO_SCRIPTED_ITEM)  return;
	
	if ([cargopod commodityType] == COMMODITY_UNDEFINED || ![cargopod commodityAmount])
	{
		OOCommodityType aCommodity = [self getRandomCommodity];
		OOCargoQuantity aQuantity = [self getRandomAmountOfCommodity:aCommodity];
		[cargopod setCommodity:aCommodity andAmount:aQuantity];		
	}
}


- (OOCommodityType) getRandomCommodity
{
	return Ranrot() % [commodityData count];
}


- (OOCargoQuantity) getRandomAmountOfCommodity:(OOCommodityType)co_type
{
	OOMassUnit		units;
	unsigned		commodityIndex = (unsigned)co_type;
	
	if (co_type < 0 || [commodityData count] <= commodityIndex)  {
		return 0;
	}
	
	//TODO: further simplify the Ranrot()s below? Hmm, being only pseudo random, 3 Ranrots should be less likely to add up to 0 than just one Ranrot... 
	
	units = [self unitsForCommodity:commodityIndex];
	switch (units)
	{
		case 0 :	// TONNES
			return 1;
			break;
		case 1 :	// KILOGRAMS
			return 1 + (Ranrot() % 6) + (Ranrot() % 6) + (Ranrot() % 6);
			break;
		case 2 :	// GRAMS
			//return 4 + 3 * (Ranrot() % 6) + 2 * (Ranrot() % 6) + (Ranrot() % 6);
			return 4 + (Ranrot() % 16) + (Ranrot() % 11) + (Ranrot() % 6);
			break;
	}
	return 1;
}


- (NSArray *)commodityDataForType:(OOCommodityType)type
{
	if (type < 0 || [commodityData count] <= (unsigned)type)  return nil;
	
	return [commodityData oo_arrayAtIndex:type];
}


- (OOCommodityType) commodityForName:(NSString *)co_name
{
	OOCommodityType	i, count;
	NSString		*name;
	
	count = (OOCommodityType)[commodityData count];
	for (i = 0; i < count; i++)
	{
		/*	Bug: NSNotFound being returned for valid names.
			Analysis: Looking for name in commodityData rather than its element.
			Fix: look in [commodityData objectAtIndex:i].
			-- Ahruman 20070714
		*/
		name = [[commodityData oo_arrayAtIndex:i] oo_stringAtIndex:MARKET_NAME];
		// try display name
		if ([co_name caseInsensitiveCompare:name] == NSOrderedSame)
		{
			return i;
		}
		// or internal ID
		if ([co_name caseInsensitiveCompare:CommodityTypeToString(i)] == NSOrderedSame)
		{
			return i;
		}
	}
	return COMMODITY_UNDEFINED;
}


- (NSString *) symbolicNameForCommodity:(OOCommodityType)co_type
{
	NSArray			*commodity = [self commodityDataForType:co_type];
	
	if (commodity == nil)  return @"";
	
	return [commodity oo_stringAtIndex:MARKET_NAME];
}


- (NSString *) displayNameForCommodity:(OOCommodityType)co_type
{
	return CommodityDisplayNameForSymbolicName([self symbolicNameForCommodity:co_type]);
}


- (OOMassUnit) unitsForCommodity:(OOCommodityType)co_type
{	
	switch (co_type)
	{
		case COMMODITY_GEM_STONES:
			return UNITS_GRAMS;
		case COMMODITY_GOLD:
		case COMMODITY_PLATINUM:
			return UNITS_KILOGRAMS;
		default:
			break;
	}
	// default
	return UNITS_TONS;
}



- (NSString *) describeCommodity:(OOCommodityType)co_type amount:(OOCargoQuantity)co_amount
{
	int				units;
	NSString		*unitDesc = nil, *typeDesc = nil;
	NSArray			*commodity = [self commodityDataForType:co_type];
	
	if (commodity == nil) return @"";
	
	units = [self unitsForCommodity:co_type];
	if (co_amount == 1)
	{
		switch (units)
		{
			case UNITS_KILOGRAMS :	// KILOGRAM
				unitDesc = DESC(@"cargo-kilogram");
				break;
			case UNITS_GRAMS :	// GRAM
				unitDesc = DESC(@"cargo-gram");
				break;
			case UNITS_TONS :	// TONNE
			default :
				unitDesc = DESC(@"cargo-ton");
				break;
		}
	}
	else
	{
		switch (units)
		{
			case UNITS_KILOGRAMS :	// KILOGRAMS
				unitDesc = DESC(@"cargo-kilograms");
				break;
			case UNITS_GRAMS :	// GRAMS
				unitDesc = DESC(@"cargo-grams");
				break;
			case UNITS_TONS :	// TONNES
			default :
				unitDesc = DESC(@"cargo-tons");
				break;
		}
	}
	
	typeDesc = CommodityDisplayNameForCommodityArray(commodity);
	
	return [NSString stringWithFormat:@"%d %@ %@",co_amount, unitDesc, typeDesc];
}

////////////////////////////////////////////////////

- (void) setGameView:(MyOpenGLView *)view
{
	[gameView release];
	gameView = [view retain];
}


- (MyOpenGLView *) gameView
{
	return gameView;
}


- (GameController *) gameController
{
	return [[self gameView] gameController];
}


- (NSDictionary *) gameSettings
{
	NSMutableDictionary *result = [NSMutableDictionary dictionaryWithCapacity:9];
	
	[result oo_setBool:reducedDetail forKey:@"reducedDetailGraphics"];
	[result oo_setBool:[PLAYER isSpeechOn] forKey:@"speechOn"];
	[result oo_setBool:autoSave forKey:@"autosave"];
	[result oo_setBool:wireframeGraphics forKey:@"wireframeGraphics"];
	[result oo_setBool:doProcedurallyTexturedPlanets forKey:@"procedurallyTexturedPlanets"];
	
	[result setObject:OOStringFromShaderSetting([self shaderEffectsLevel]) forKey:@"shaderEffectsLevel"];
	
	NSString *desc = @"UNDEFINED";
	switch ([[OOMusicController sharedController] mode])
	{
		case kOOMusicOff:		desc = @"MUSIC_OFF"; break;
		case kOOMusicOn:		desc = @"MUSIC_ON"; break;
		case kOOMusicITunes:	desc = @"MUSIC_ITUNES"; break;
	}
	[result setObject:desc forKey:@"musicMode"];
	
	NSDictionary *gameWindow = [NSDictionary dictionaryWithObjectsAndKeys:
						[NSNumber numberWithFloat:[gameView viewSize].width], @"width",
						[NSNumber numberWithFloat:[gameView viewSize].height], @"height",
						[NSNumber numberWithBool:[[self gameController] inFullScreenMode]], @"fullScreen",
						nil];
	[result setObject:gameWindow forKey:@"gameWindow"];
	
	[result setObject:[PLAYER keyConfig] forKey:@"keyConfig"];

	return [[result copy] autorelease];
}


- (void) useGUILightSource:(BOOL)GUILight
{
	if (GUILight != demo_light_on)
	{
		if (![self useShaders])
		{
			if (GUILight) 
			{
				OOGL(glEnable(GL_LIGHT0));
				OOGL(glDisable(GL_LIGHT1));
			}
			else
			{
				OOGL(glEnable(GL_LIGHT1));
				OOGL(glDisable(GL_LIGHT0));
			}
		}
		// There should be nothing to do for shaders, they use the same (always on) light source
		// both in flight & in gui mode. According to the standard, shaders should treat lights as
		// always enabled. At least one non-standard shader implementation (windows' X3100 Intel
		// core with GM965 chipset and version 6.14.10.4990 driver) does _not_ use glDisabled lights,
		// making the following line necessary.
		
		else OOGL(glEnable(GL_LIGHT1)); // make sure we have a light, even with shaders (!)
		
		demo_light_on = GUILight;
	}
}


- (void) lightForEntity:(BOOL)isLit
{
	if (isLit != object_light_on)
	{
		if ([self useShaders])
		{
			if (isLit)
			{
				OOGL(glLightfv(GL_LIGHT1, GL_DIFFUSE, sun_diffuse));
				OOGL(glLightfv(GL_LIGHT1, GL_SPECULAR, sun_specular));
			}
			else
			{
				OOGL(glLightfv(GL_LIGHT1, GL_DIFFUSE, sun_off));
				OOGL(glLightfv(GL_LIGHT1, GL_SPECULAR, sun_off));
			}
		}
		else
		{
			if (!demo_light_on)
			{
				if (isLit) OOGL(glEnable(GL_LIGHT1));
				else OOGL(glDisable(GL_LIGHT1));
			}
			else
			{
				// If we're in demo/GUI mode we should always have a lit object.
				OOGL(glEnable(GL_LIGHT0));
				
				// Redundant, see above.
				//if (isLit)  OOGL(glEnable(GL_LIGHT0));
				//else  OOGL(glDisable(GL_LIGHT0));
			}
		}
		
		object_light_on = isLit;
	}
}


// global rotation matrix definitions
static const OOMatrix	fwd_matrix =
						{{
							{ 1.0f,  0.0f,  0.0f,  0.0f },
							{ 0.0f,  1.0f,  0.0f,  0.0f },
							{ 0.0f,  0.0f,  1.0f,  0.0f },
							{ 0.0f,  0.0f,  0.0f,  1.0f }
						}};
static const OOMatrix	aft_matrix =
						{{
							{-1.0f,  0.0f,  0.0f,  0.0f },
							{ 0.0f,  1.0f,  0.0f,  0.0f },
							{ 0.0f,  0.0f, -1.0f,  0.0f },
							{ 0.0f,  0.0f,  0.0f,  1.0f }
						}};
static const OOMatrix	port_matrix =
						{{
							{ 0.0f,  0.0f, -1.0f,  0.0f },
							{ 0.0f,  1.0f,  0.0f,  0.0f },
							{ 1.0f,  0.0f,  0.0f,  0.0f },
							{ 0.0f,  0.0f,  0.0f,  1.0f }
						}};
static const OOMatrix	starboard_matrix =
						{{
							{ 0.0f,  0.0f,  1.0f,  0.0f },
							{ 0.0f,  1.0f,  0.0f,  0.0f },
							{-1.0f,  0.0f,  0.0f,  0.0f },
							{ 0.0f,  0.0f,  0.0f,  1.0f }
						}};


- (void) getActiveViewMatrix:(OOMatrix *)outMatrix forwardVector:(Vector *)outForward upVector:(Vector *)outUp
{
	assert(outMatrix != NULL && outForward != NULL && outUp != NULL);
	
	PlayerEntity			*player = nil;
	
	switch (viewDirection)
	{
		case VIEW_AFT:
			*outMatrix = aft_matrix;
			*outForward = vector_flip(kBasisZVector);
			*outUp = kBasisYVector;
			return;
			
		case VIEW_PORT:
			*outMatrix = port_matrix;
			*outForward = vector_flip(kBasisXVector);
			*outUp = kBasisYVector;
			return;
			
		case VIEW_STARBOARD:
			*outMatrix = starboard_matrix;
			*outForward = kBasisXVector;
			*outUp = kBasisYVector;
			return;
			
		case VIEW_CUSTOM:
			player = PLAYER;
			*outMatrix = [player customViewMatrix];
			*outForward = [player customViewForwardVector];
			*outUp = [player customViewUpVector];
			return;
			
		case VIEW_FORWARD:
		case VIEW_NONE:
		case VIEW_GUI_DISPLAY:
		case VIEW_BREAK_PATTERN:
			;
	}
	
	*outMatrix = fwd_matrix;
	*outForward = kBasisZVector;
	*outUp = kBasisYVector;
}


- (OOMatrix) activeViewMatrix
{
	OOMatrix			m;
	Vector				f, u;
	
	[self getActiveViewMatrix:&m forwardVector:&f upVector:&u];
	return m;
}


/* Code adapted from http://www.crownandcutlass.com/features/technicaldetails/frustum.html
 * Original license is: "This page and its contents are Copyright 2000 by Mark Morley
 * Unless otherwise noted, you may use any and all code examples provided herein in any way you want."
*/

- (void) defineFrustum
{
	GLfloat   proj[16];
	GLfloat   modl[16];
	GLfloat   clip[16];
	GLfloat   rt;
	
	/* Get the current PROJECTION matrix from OpenGL */
	glGetFloatv( GL_PROJECTION_MATRIX, proj );
	
	/* Get the current MODELVIEW matrix from OpenGL */
	glGetFloatv( GL_MODELVIEW_MATRIX, modl );
	
	/* Combine the two matrices (multiply projection by modelview) */
	clip[ 0] = modl[ 0] * proj[ 0] + modl[ 1] * proj[ 4] + modl[ 2] * proj[ 8] + modl[ 3] * proj[12];
	clip[ 1] = modl[ 0] * proj[ 1] + modl[ 1] * proj[ 5] + modl[ 2] * proj[ 9] + modl[ 3] * proj[13];
	clip[ 2] = modl[ 0] * proj[ 2] + modl[ 1] * proj[ 6] + modl[ 2] * proj[10] + modl[ 3] * proj[14];
	clip[ 3] = modl[ 0] * proj[ 3] + modl[ 1] * proj[ 7] + modl[ 2] * proj[11] + modl[ 3] * proj[15];
	
	clip[ 4] = modl[ 4] * proj[ 0] + modl[ 5] * proj[ 4] + modl[ 6] * proj[ 8] + modl[ 7] * proj[12];
	clip[ 5] = modl[ 4] * proj[ 1] + modl[ 5] * proj[ 5] + modl[ 6] * proj[ 9] + modl[ 7] * proj[13];
	clip[ 6] = modl[ 4] * proj[ 2] + modl[ 5] * proj[ 6] + modl[ 6] * proj[10] + modl[ 7] * proj[14];
	clip[ 7] = modl[ 4] * proj[ 3] + modl[ 5] * proj[ 7] + modl[ 6] * proj[11] + modl[ 7] * proj[15];
	
	clip[ 8] = modl[ 8] * proj[ 0] + modl[ 9] * proj[ 4] + modl[10] * proj[ 8] + modl[11] * proj[12];
	clip[ 9] = modl[ 8] * proj[ 1] + modl[ 9] * proj[ 5] + modl[10] * proj[ 9] + modl[11] * proj[13];
	clip[10] = modl[ 8] * proj[ 2] + modl[ 9] * proj[ 6] + modl[10] * proj[10] + modl[11] * proj[14];
	clip[11] = modl[ 8] * proj[ 3] + modl[ 9] * proj[ 7] + modl[10] * proj[11] + modl[11] * proj[15];
	
	clip[12] = modl[12] * proj[ 0] + modl[13] * proj[ 4] + modl[14] * proj[ 8] + modl[15] * proj[12];
	clip[13] = modl[12] * proj[ 1] + modl[13] * proj[ 5] + modl[14] * proj[ 9] + modl[15] * proj[13];
	clip[14] = modl[12] * proj[ 2] + modl[13] * proj[ 6] + modl[14] * proj[10] + modl[15] * proj[14];
	clip[15] = modl[12] * proj[ 3] + modl[13] * proj[ 7] + modl[14] * proj[11] + modl[15] * proj[15];
	
	/* Extract the numbers for the RIGHT plane */
	frustum[0][0] = clip[ 3] - clip[ 0];
	frustum[0][1] = clip[ 7] - clip[ 4];
	frustum[0][2] = clip[11] - clip[ 8];
	frustum[0][3] = clip[15] - clip[12];
	
	/* Normalize the result */
	rt = 1.0f / sqrt(frustum[0][0] * frustum[0][0] + frustum[0][1] * frustum[0][1] + frustum[0][2] * frustum[0][2]);
	frustum[0][0] *= rt;
	frustum[0][1] *= rt;
	frustum[0][2] *= rt;
	frustum[0][3] *= rt;
	
	/* Extract the numbers for the LEFT plane */
	frustum[1][0] = clip[ 3] + clip[ 0];
	frustum[1][1] = clip[ 7] + clip[ 4];
	frustum[1][2] = clip[11] + clip[ 8];
	frustum[1][3] = clip[15] + clip[12];
	
	/* Normalize the result */
	rt = 1.0f / sqrt(frustum[1][0] * frustum[1][0] + frustum[1][1] * frustum[1][1] + frustum[1][2] * frustum[1][2]);
	frustum[1][0] *= rt;
	frustum[1][1] *= rt;
	frustum[1][2] *= rt;
	frustum[1][3] *= rt;

	/* Extract the BOTTOM plane */
	frustum[2][0] = clip[ 3] + clip[ 1];
	frustum[2][1] = clip[ 7] + clip[ 5];
	frustum[2][2] = clip[11] + clip[ 9];
	frustum[2][3] = clip[15] + clip[13];

	/* Normalize the result */
	rt = 1.0 / sqrt(frustum[2][0] * frustum[2][0] + frustum[2][1] * frustum[2][1] + frustum[2][2] * frustum[2][2]);
	frustum[2][0] *= rt;
	frustum[2][1] *= rt;
	frustum[2][2] *= rt;
	frustum[2][3] *= rt;

	/* Extract the TOP plane */
	frustum[3][0] = clip[ 3] - clip[ 1];
	frustum[3][1] = clip[ 7] - clip[ 5];
	frustum[3][2] = clip[11] - clip[ 9];
	frustum[3][3] = clip[15] - clip[13];

	/* Normalize the result */
	rt = 1.0 / sqrt(frustum[3][0] * frustum[3][0] + frustum[3][1] * frustum[3][1] + frustum[3][2] * frustum[3][2]);
	frustum[3][0] *= rt;
	frustum[3][1] *= rt;
	frustum[3][2] *= rt;
	frustum[3][3] *= rt;

	/* Extract the FAR plane */
	frustum[4][0] = clip[ 3] - clip[ 2];
	frustum[4][1] = clip[ 7] - clip[ 6];
	frustum[4][2] = clip[11] - clip[10];
	frustum[4][3] = clip[15] - clip[14];

	/* Normalize the result */
	rt = sqrt(frustum[4][0] * frustum[4][0] + frustum[4][1] * frustum[4][1] + frustum[4][2] * frustum[4][2]);
	frustum[4][0] *= rt;
	frustum[4][1] *= rt;
	frustum[4][2] *= rt;
	frustum[4][3] *= rt;

	/* Extract the NEAR plane */
	frustum[5][0] = clip[ 3] + clip[ 2];
	frustum[5][1] = clip[ 7] + clip[ 6];
	frustum[5][2] = clip[11] + clip[10];
	frustum[5][3] = clip[15] + clip[14];

	/* Normalize the result */
	rt = sqrt(frustum[5][0] * frustum[5][0] + frustum[5][1] * frustum[5][1] + frustum[5][2] * frustum[5][2]);
	frustum[5][0] *= rt;
	frustum[5][1] *= rt;
	frustum[5][2] *= rt;
	frustum[5][3] *= rt;
}


- (BOOL) viewFrustumIntersectsSphereAt:(Vector)position withRadius:(GLfloat)radius
{
	// position is the relative position between the camera and the object
	int p;
	for (p = 0; p < 6; p++)
	{
		if (frustum[p][0] * position.x + frustum[p][1] * position.y + frustum[p][2] * position.z + frustum[p][3] <= -radius)
		{
			return NO;
		}
	}
	return YES;
}


- (void) drawUniverse
{
	OOLog(@"universe.profile.draw",@"Begin draw");
	if (!no_update)
	{
		@try
		{
			no_update = YES;	// block other attempts to draw
			
			int				i, v_status;
			Vector			view_dir, view_up;
			OOMatrix		view_matrix;
			int				ent_count =	n_entities;
			Entity			*my_entities[ent_count];
			int				draw_count = 0;
			PlayerEntity	*player = PLAYER;
			Entity			*drawthing = nil;
			BOOL			demoShipMode = [player showDemoShips];
			
			if (!displayGUI && wasDisplayGUI)
			{
				// reset light1 position for the shaders
				if (cachedSun) [UNIVERSE setMainLightPosition:HPVectorToVector([cachedSun position])]; // the main light is the sun.
				else [UNIVERSE setMainLightPosition:kZeroVector];
			}
			wasDisplayGUI = displayGUI;
			
			// use a non-mutable copy so this can't be changed under us.
			for (i = 0; i < ent_count; i++)
			{
				Entity *e = sortedEntities[i]; // ordered NEAREST -> FURTHEST AWAY
				if ([e isVisible])
				{
					my_entities[draw_count++] = [[e retain] autorelease];
				}
			}
			
			v_status = [player status];
			
			[self getActiveViewMatrix:&view_matrix forwardVector:&view_dir upVector:&view_up];
			
			OOCheckOpenGLErrors(@"Universe before doing anything");
			
			OOSetOpenGLState(OPENGL_STATE_OPAQUE);  // FIXME: should be redundant.
			
			if (!displayGUI)
			{
				OOGL(glClearColor(skyClearColor[0], skyClearColor[1], skyClearColor[2], skyClearColor[3]));
			}
			else
			{
				OOGL(glClearColor(0.0, 0.0, 0.0, 0.0));
			}
			
			OOGL(glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT));
			OOGL(glLoadIdentity());	// reset matrix
			
			OOGL(gluLookAt(0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 1.0, 0.0));
			
			// HACK BUSTED
			OOGL(glScalef(-1.0, 1.0, 1.0));   // flip left and right
			OOGL(glPushMatrix()); // save this flat viewpoint
			
			/* OpenGL viewpoints: 
			 *
			 * Oolite used to transform the viewpoint by the inverse of the
			 * view position, and then transform the objects by the inverse
			 * of their position, to get the correct view. However, as
			 * OpenGL only uses single-precision floats, this causes
			 * noticeable display inaccuracies relatively close to the
			 * origin.
			 *
			 * Instead, we now calculate the difference between the view
			 * position and the object using high-precision vectors, convert
			 * the difference to a low-precision vector (since if you can
			 * see it, it's close enough for the loss of precision not to
			 * matter) and use that relative vector for the OpenGL transform
			 *
			 * Objects which reset the view matrix in their display need to be
			 * handled a little more carefully than before.
			 */

			// If set, display background GUI image. Must be done before enabling lights to avoid dim backgrounds
			if (displayGUI)  [gui drawGUIBackground];
			
			OOSetOpenGLState(OPENGL_STATE_OPAQUE);  // FIXME: should be redundant.
			
			// Set up view transformation matrix
			OOMatrix flipMatrix = kIdentityMatrix;
			flipMatrix.m[2][2] = -1;
			view_matrix = OOMatrixMultiply(view_matrix, flipMatrix);
			Vector viewOffset = [player viewpointOffset];
			
			OOGL(gluLookAt(view_dir.x, view_dir.y, view_dir.z, 0.0, 0.0, 0.0, view_up.x, view_up.y, view_up.z));
			
			if (EXPECT(!displayGUI || demoShipMode))
			{
				if (EXPECT(!demoShipMode))	// we're in flight
				{
					// rotate the view
					OOGL(GLMultOOMatrix([player rotationMatrix]));
					// translate the view
					// HPVect: camera-relative position
//					OOGL(GLTranslateOOVector(vector_flip(position)));
					OOGL(glLightModelfv(GL_LIGHT_MODEL_AMBIENT, stars_ambient));
					// main light position, no shaders, in-flight / shaders, in-flight and docked.
					if (cachedSun)
					{
						[self setMainLightPosition:[cachedSun cameraRelativePosition]];
					}
					OOGL(glLightfv(GL_LIGHT1, GL_POSITION, main_light_position));					
				}
				else
				{
					OOGL(glLightModelfv(GL_LIGHT_MODEL_AMBIENT, docked_light_ambient));
					// main_light_position no shaders, docked/GUI.
					OOGL(glLightfv(GL_LIGHT0, GL_POSITION, main_light_position));
					// main light position, no shaders, in-flight / shaders, in-flight and docked.		
					OOGL(glLightfv(GL_LIGHT1, GL_POSITION, main_light_position));
				}
				
				
				OOGL([self useGUILightSource:demoShipMode]);
				
				// HACK: store view matrix for absolute drawing of active subentities (i.e., turrets).
				OOGL(viewMatrix = OOMatrixLoadGLMatrix(GL_MODELVIEW_MATRIX));
				
				int			furthest = draw_count - 1;
				int			nearest = 0;
				BOOL		fogging, bpHide = [self breakPatternHide];
				BOOL		inAtmosphere = airResistanceFactor > 0.01;
				GLfloat		fogFactor = 0.5 / airResistanceFactor;
				double 		fog_scale, half_scale;
				GLfloat 	flat_ambdiff[4]	= {1.0, 1.0, 1.0, 1.0};   // for alpha
				GLfloat 	mat_no[4]		= {0.0, 0.0, 0.0, 1.0};   // nothing			
				
				OOGL(glHint(GL_FOG_HINT, [self reducedDetail] ? GL_FASTEST : GL_NICEST));
				
				[self defineFrustum]; // camera is set up for this frame
				
				OOVerifyOpenGLState();
				OOCheckOpenGLErrors(@"Universe after setting up for opaque pass");
				OOLog(@"universe.profile.draw",@"Begin opaque pass");

				
				//		DRAW ALL THE OPAQUE ENTITIES
				for (i = furthest; i >= nearest; i--)
				{
					drawthing = my_entities[i];
					OOEntityStatus d_status = [drawthing status];
					
					if (bpHide && !drawthing->isImmuneToBreakPatternHide)  continue;
					
					if (!((d_status == STATUS_COCKPIT_DISPLAY) ^ demoShipMode)) // either demo ship mode or in flight
					{
						// reset material properties
						// FIXME: should be part of SetState
						OOGL(glMaterialfv(GL_FRONT_AND_BACK, GL_AMBIENT_AND_DIFFUSE, flat_ambdiff));
						OOGL(glMaterialfv(GL_FRONT_AND_BACK, GL_EMISSION, mat_no));
						
						OOGL(glPushMatrix());
						if (EXPECT(drawthing != player))
						{
							//translate the object
							// HPVect: camera relative
							GLTranslateOOVector([drawthing cameraRelativePosition]);
							//rotate the object
							GLMultOOMatrix([drawthing drawRotationMatrix]);
						}
						else
						{
							// Load transformation matrix
							GLLoadOOMatrix(view_matrix);
							//translate the object  from the viewpoint
							GLTranslateOOVector(vector_flip(viewOffset));
						}
						
						// atmospheric fog
						fogging = (inAtmosphere && ![drawthing isStellarObject]);
						
						if (fogging)
						{
							fog_scale = BILLBOARD_DEPTH * fogFactor;
							half_scale = fog_scale * 0.50;
							OOGL(glEnable(GL_FOG));
							OOGL(glFogi(GL_FOG_MODE, GL_LINEAR));
							OOGL(glFogfv(GL_FOG_COLOR, skyClearColor));
							OOGL(glFogf(GL_FOG_START, half_scale));
							OOGL(glFogf(GL_FOG_END, fog_scale));
						}
						
						[self lightForEntity:demoShipMode || drawthing->isSunlit];
						
						// draw the thing
						[drawthing drawImmediate:false translucent:false];
						
						// atmospheric fog
						if (fogging)
						{
							OOGL(glDisable(GL_FOG));
						}
						
						OOGL(glPopMatrix());
					}
				}
				
				//		DRAW ALL THE TRANSLUCENT entsInDrawOrder
				
				OOSetOpenGLState(OPENGL_STATE_TRANSLUCENT_PASS);  // FIXME: should be redundant.
				
				OOCheckOpenGLErrors(@"Universe after setting up for translucent pass");
				OOLog(@"universe.profile.draw",@"Begin translucent pass");
				for (i = furthest; i >= nearest; i--)
				{
					drawthing = my_entities[i];
					OOEntityStatus d_status = [drawthing status];
					
					if (bpHide && !drawthing->isImmuneToBreakPatternHide)  continue;
					
					if (!((d_status == STATUS_COCKPIT_DISPLAY) ^ demoShipMode)) // either in flight or in demo ship mode
					{
						
						OOGL(glPushMatrix());
						if (EXPECT(drawthing != player))
						{
							//translate the object
							// HPVect: camera relative positions
							GLTranslateOOVector([drawthing cameraRelativePosition]);
							//rotate the object
							GLMultOOMatrix([drawthing drawRotationMatrix]);
						}
						else
						{
							// Load transformation matrix
							GLLoadOOMatrix(view_matrix);
							//translate the object  from the viewpoint
							GLTranslateOOVector(vector_flip(viewOffset));
						}
						
						// experimental - atmospheric fog
						fogging = (inAtmosphere && ![drawthing isStellarObject]);
						
						if (fogging)
						{
							fog_scale = BILLBOARD_DEPTH * fogFactor;
							half_scale = fog_scale * 0.50;
							OOGL(glEnable(GL_FOG));
							OOGL(glFogi(GL_FOG_MODE, GL_LINEAR));
							OOGL(glFogfv(GL_FOG_COLOR, skyClearColor));
							OOGL(glFogf(GL_FOG_START, half_scale));
							OOGL(glFogf(GL_FOG_END, fog_scale));
						}
						
						// draw the thing
						[drawthing drawImmediate:false translucent:true];
						
						// atmospheric fog
						if (fogging)
						{
							OOGL(glDisable(GL_FOG));
						}
						
						OOGL(glPopMatrix());
					}
				}
			}
			
			OOGL(glPopMatrix()); //restore saved flat viewpoint

			if (EXPECT(!displayGUI || demoShipMode))
			{
				if (cachedSun)
				{
					[cachedSun drawStarGlare];
				}
			}

			OOCheckOpenGLErrors(@"Universe after drawing entities");
			OOLog(@"universe.profile.draw",@"Begin HUD");
			OOSetOpenGLState(OPENGL_STATE_OVERLAY);  // FIXME: should be redundant.

			GLfloat	lineWidth = [gameView viewSize].width / 1024.0; // restore line size
			if (lineWidth < 1.0)  lineWidth = 1.0;
			OOGL(GLScaledLineWidth(lineWidth));

			[self drawMessage];
			
			HeadUpDisplay *theHUD = [player hud];
			
			// If the HUD has a non-nil deferred name string, it means that a HUD switch was requested while it was being rendered.
			// If so, execute the deferred HUD switch now - Nikos 20110628
			if ([theHUD deferredHudName] != nil)
			{
				NSString *deferredName = [[theHUD deferredHudName] retain];
				[player switchHudTo:deferredName];
				[deferredName release];
				theHUD = [player hud];	// HUD has been changed, so point to its new address
			}
			
			// Hiding HUD: has been a regular - non-debug - feature as of r2749, about 2 yrs ago! --Kaks 2011.10.14
			static float sPrevHudAlpha = -1.0f;
			if ([theHUD isHidden])
			{
				if (sPrevHudAlpha < 0.0f)
				{
					sPrevHudAlpha = [theHUD overallAlpha];
				}
				[theHUD setOverallAlpha:0.0f];
			}
			else if (sPrevHudAlpha >= 0.0f)
			{
				[theHUD setOverallAlpha:sPrevHudAlpha];
				sPrevHudAlpha = -1.0f;
			}
			
			if (v_status != STATUS_DEAD && v_status != STATUS_ESCAPE_SEQUENCE)
			{
				[theHUD setLineWidth:lineWidth];
				[theHUD renderHUD];
			}
			
#if (defined (SNAPSHOT_BUILD) && defined (OOLITE_SNAPSHOT_VERSION))
			[theHUD drawWatermarkString:@"Development version " @OOLITE_SNAPSHOT_VERSION];
#endif
			
			OOCheckOpenGLErrors(@"Universe after drawing HUD");
			
			OOGL(glFlush());	// don't wait around for drawing to complete
			
			no_update = NO;	// allow other attempts to draw
			
			// frame complete, when it is time to update the fps_counter, updateClocks:delta_t
			// in PlayerEntity.m will take care of resetting the processed frames number to 0.
			if (![[self gameController] isGamePaused])
			{
				framesDoneThisUpdate++;
			}
		}
		@catch (NSException *exception)
		{
			no_update = NO;	// make sure we don't get stuck in all subsequent frames.
			
			if ([[exception name] hasPrefix:@"Oolite"])
			{
				[self handleOoliteException:exception];
			}
			else
			{
				OOLog(kOOLogException, @"***** Exception: %@ : %@ *****",[exception name], [exception reason]);
				@throw exception;
			}
		}
	}
	OOLog(@"universe.profile.draw",@"End drawing");
}


- (int) framesDoneThisUpdate
{
	return framesDoneThisUpdate;
}


- (void) resetFramesDoneThisUpdate
{
	framesDoneThisUpdate = 0;
}


- (OOMatrix) viewMatrix
{
	return viewMatrix;
}


- (void) drawMessage
{
	OOSetOpenGLState(OPENGL_STATE_OVERLAY);
	
	OOGL(glDisable(GL_TEXTURE_2D));	// for background sheets
	
	float overallAlpha = [[PLAYER hud] overallAlpha];
	if (displayGUI)
	{
		if ([[self gameController] mouseInteractionMode] == MOUSE_MODE_UI_SCREEN_WITH_INTERACTION)
		{
			cursor_row = [gui drawGUI:1.0 drawCursor:YES];
		}
		else
		{
			[gui drawGUI:1.0 drawCursor:NO];
		}
	}
	
	[message_gui drawGUI:[message_gui alpha] * overallAlpha drawCursor:NO];
	[comm_log_gui drawGUI:[comm_log_gui alpha] * overallAlpha drawCursor:NO];
	
	OOVerifyOpenGLState();
}


- (id)entityForUniversalID:(OOUniversalID)u_id
{
	if (u_id == 100)
		return PLAYER;	// the player
	
	if (MAX_ENTITY_UID < u_id)
	{
		OOLog(@"universe.badUID", @"Attempt to retrieve entity for out-of-range UID %u. (This is an internal programming error, please report it.)", u_id);
		return nil;
	}
	
	if ((u_id == NO_TARGET)||(!entity_for_uid[u_id]))
		return nil;
	
	Entity *ent = entity_for_uid[u_id];
	if ([ent isEffect])	// effects SHOULD NOT HAVE U_IDs!
	{
		return nil;
	}
	
	if ([ent status] == STATUS_DEAD || [ent status] == STATUS_DOCKED)
	{
		return nil;
	}
	
	return ent;
}


static BOOL MaintainLinkedLists(Universe *uni)
{
	NSCParameterAssert(uni != NULL);
	BOOL result = YES;
	
	// DEBUG check for loops and short lists
	if (uni->n_entities > 0)
	{
		int n;
		Entity	*checkEnt, *last;
		
		last = nil;
		
		n = uni->n_entities;
		checkEnt = uni->x_list_start;
		while ((n--)&&(checkEnt))
		{
			last = checkEnt;
			checkEnt = checkEnt->x_next;
		}
		if ((checkEnt)||(n > 0))
		{
			OOExtraLog(kOOLogEntityVerificationError, @"Broken x_next %@ list (%d) ***", uni->x_list_start, n);
			result = NO;
		}
		
		n = uni->n_entities;
		checkEnt = last;
		while ((n--)&&(checkEnt))	checkEnt = checkEnt->x_previous;
		if ((checkEnt)||(n > 0))
		{
			OOExtraLog(kOOLogEntityVerificationError, @"Broken x_previous %@ list (%d) ***", uni->x_list_start, n);
			if (result)
			{
				OOExtraLog(kOOLogEntityVerificationRebuild, @"REBUILDING x_previous list from x_next list");
				checkEnt = uni->x_list_start;
				checkEnt->x_previous = nil;
				while (checkEnt->x_next)
				{
					last = checkEnt;
					checkEnt = checkEnt->x_next;
					checkEnt->x_previous = last;
				}
			}
		}
		
		n = uni->n_entities;
		checkEnt = uni->y_list_start;
		while ((n--)&&(checkEnt))
		{
			last = checkEnt;
			checkEnt = checkEnt->y_next;
		}
		if ((checkEnt)||(n > 0))
		{
			OOExtraLog(kOOLogEntityVerificationError, @"Broken *** broken y_next %@ list (%d) ***", uni->y_list_start, n);
			result = NO;
		}
		
		n = uni->n_entities;
		checkEnt = last;
		while ((n--)&&(checkEnt))	checkEnt = checkEnt->y_previous;
		if ((checkEnt)||(n > 0))
		{
			OOExtraLog(kOOLogEntityVerificationError, @"Broken y_previous %@ list (%d) ***", uni->y_list_start, n);
			if (result)
			{
				OOExtraLog(kOOLogEntityVerificationRebuild, @"REBUILDING y_previous list from y_next list");
				checkEnt = uni->y_list_start;
				checkEnt->y_previous = nil;
				while (checkEnt->y_next)
				{
					last = checkEnt;
					checkEnt = checkEnt->y_next;
					checkEnt->y_previous = last;
				}
			}
		}
		
		n = uni->n_entities;
		checkEnt = uni->z_list_start;
		while ((n--)&&(checkEnt))
		{
			last = checkEnt;
			checkEnt = checkEnt->z_next;
		}
		if ((checkEnt)||(n > 0))
		{
			OOExtraLog(kOOLogEntityVerificationError, @"Broken z_next %@ list (%d) ***", uni->z_list_start, n);
			result = NO;
		}
		
		n = uni->n_entities;
		checkEnt = last;
		while ((n--)&&(checkEnt))	checkEnt = checkEnt->z_previous;
		if ((checkEnt)||(n > 0))
		{
			OOExtraLog(kOOLogEntityVerificationError, @"Broken z_previous %@ list (%d) ***", uni->z_list_start, n);
			if (result)
			{
				OOExtraLog(kOOLogEntityVerificationRebuild, @"REBUILDING z_previous list from z_next list");
				checkEnt = uni->z_list_start;
				NSCAssert(checkEnt != nil, @"Expected z-list to be non-empty.");	// Previously an implicit assumption. -- Ahruman 2011-01-25
				checkEnt->z_previous = nil;
				while (checkEnt->z_next)
				{
					last = checkEnt;
					checkEnt = checkEnt->z_next;
					checkEnt->z_previous = last;
				}
			}
		}
	}
	
	if (!result)
	{
		OOExtraLog(kOOLogEntityVerificationRebuild, @"Rebuilding all linked lists from scratch");
		NSArray *allEntities = uni->entities;
		uni->x_list_start = nil;
		uni->y_list_start = nil;
		uni->z_list_start = nil;
		
		Entity *ent = nil;
		foreach (ent, allEntities)
		{
			ent->x_next = nil;
			ent->x_previous = nil;
			ent->y_next = nil;
			ent->y_previous = nil;
			ent->z_next = nil;
			ent->z_previous = nil;
			[ent addToLinkedLists];
		}
	}
	
	return result;
}


- (BOOL) addEntity:(Entity *) entity
{
	if (entity)
	{
		ShipEntity *se = nil;
		OOVisualEffectEntity *ve = nil;
		OOWaypointEntity *wp = nil;
		
		if (![entity validForAddToUniverse])  return NO;
		
		// don't add things twice!
		if ([entities containsObject:entity])
			return YES;
		
		if (n_entities >= UNIVERSE_MAX_ENTITIES - 1)
		{
			// throw an exception here...
			OOLog(@"universe.addEntity.failed", @"***** Universe cannot addEntity:%@ -- Universe is full (%d entities out of %d)", entity, n_entities, UNIVERSE_MAX_ENTITIES);
#ifndef NDEBUG
			if (OOLogWillDisplayMessagesInClass(@"universe.maxEntitiesDump")) [self debugDumpEntities];
#endif
			return NO;
		}
		
		if (![entity isEffect])
		{
			unsigned limiter = UNIVERSE_MAX_ENTITIES;
			while (entity_for_uid[next_universal_id] != nil)	// skip allocated numbers
			{
				next_universal_id++;						// increment keeps idkeys unique
				if (next_universal_id >= MAX_ENTITY_UID)
				{
					next_universal_id = MIN_ENTITY_UID;
				}
				if (limiter-- == 0)
				{
					// Every slot has been tried! This should not happen due to previous test, but there was a problem here in 1.70.
					OOLog(@"universe.addEntity.failed", @"***** Universe cannot addEntity:%@ -- Could not find free slot for entity.", entity);
					return NO;
				}
			}
			[entity setUniversalID:next_universal_id];
			entity_for_uid[next_universal_id] = entity;
			if ([entity isShip])
			{
				se = (ShipEntity *)entity;
				if ([se isBeacon])
				{
					[self setNextBeacon:se];
				}
				if ([se isStation])
				{
					// check if it is a proper rotating station (ie. roles contains the word "station")
					if ([(StationEntity*)se isRotatingStation])
					{
						double stationRoll = 0.0;
						// check for station_roll override
						id definedRoll = [[se shipInfoDictionary] objectForKey:@"station_roll"];
						
						if (definedRoll != nil)
						{
							stationRoll = OODoubleFromObject(definedRoll, stationRoll);
						}
						else
						{
							stationRoll = [[self generateSystemData:system_seed] oo_doubleForKey:@"station_roll" defaultValue:STANDARD_STATION_ROLL];
						}
						
						[se setRoll: stationRoll];
					}
					else
					{
						[se setRoll: 0.0];
					}
					[(StationEntity *)se setPlanet:[self planet]];
					if ([se maxFlightSpeed] > 0) se->isExplicitlyNotMainStation = YES; // we never want carriers to become main stations.
				}
				// stations used to have STATUS_ACTIVE, they're all STATUS_IN_FLIGHT now.
				if ([se status] != STATUS_COCKPIT_DISPLAY)
				{
					[se setStatus:STATUS_IN_FLIGHT];
				}
			}
		}
		else
		{
			[entity setUniversalID:NO_TARGET];
			if ([entity isVisualEffect])
			{
				ve = (OOVisualEffectEntity *)entity;
				if ([ve isBeacon])
				{
					[self setNextBeacon:ve];
				}
			}
			else if ([entity isWaypoint])
			{
				wp = (OOWaypointEntity *)entity;
				if ([wp isBeacon])
				{
					[self setNextBeacon:wp];
				}
			}
		}
		
		// lighting considerations
		entity->isSunlit = YES;
		entity->shadingEntityID = NO_TARGET;
		
		// add it to the universe
		[entities addObject:entity];
		[entity wasAddedToUniverse];
		
		// maintain sorted list (and for the scanner relative position)
		HPVector entity_pos = entity->position;
		HPVector delta = HPvector_between(entity_pos, PLAYER->position);
		double z_distance = HPmagnitude2(delta);
		entity->zero_distance = z_distance;
		unsigned index = n_entities;
		sortedEntities[index] = entity;
		entity->zero_index = index;
		while ((index > 0)&&(z_distance < sortedEntities[index - 1]->zero_distance))	// bubble into place
		{
			sortedEntities[index] = sortedEntities[index - 1];
			sortedEntities[index]->zero_index = index;
			index--;
			sortedEntities[index] = entity;
			entity->zero_index = index;
		}
		
		// increase n_entities...
		n_entities++;
		
		// add entity to linked lists
		[entity addToLinkedLists];	// position and universe have been set - so we can do this
		if ([entity canCollide])	// filter only collidables disappearing
		{
			doLinkedListMaintenanceThisUpdate = YES;
		}
		
		if ([entity isWormhole])
		{
			[activeWormholes addObject:entity];
		}
		else if ([entity isPlanet])
		{
			[allPlanets addObject:entity];
		}
		else if ([entity isShip])
		{
			[[se getAI] setOwner:se];
			[[se getAI] setState:@"GLOBAL"];
			if ([entity isStation])
			{
				[allStations addObject:entity];
			}
		}
		
		return YES;
	}
	return NO;
}


- (BOOL) removeEntity:(Entity *) entity
{
	if (entity != nil && ![entity isPlayer])
	{
		/*	Ensure entity won't actually be dealloced until the end of this
			update (or the next update if none is in progress), because
			there may be things pointing to it but not retaining it.
		*/
		[entitiesDeadThisUpdate addObject:entity];
		if ([entity isStation])
		{
			[allStations removeObject:entity];
		}
		return [self doRemoveEntity:entity];
	}
	return NO;
}


- (void) ensureEntityReallyRemoved:(Entity *)entity
{
	if ([entity universalID] != NO_TARGET)
	{
		OOLog(@"universe.unremovedEntity", @"Entity %@ dealloced without being removed from universe! (This is an internal programming error, please report it.)", entity);
		[self doRemoveEntity:entity];
	}
}


- (void) removeAllEntitiesExceptPlayer
{
	BOOL updating = no_update;
	no_update = YES;			// no drawing while we do this!
	
#ifndef NDEBUG
	Entity* p0 = [entities objectAtIndex:0];
	if (!(p0->isPlayer))
	{
		OOLog(kOOLogInconsistentState, @"***** First entity is not the player in Universe.removeAllEntitiesExceptPlayer - exiting.");
		exit(EXIT_FAILURE);
	}
#endif
	
	// preserve wormholes
	NSMutableArray *savedWormholes = [activeWormholes mutableCopy];
	
	while ([entities count] > 1)
	{
		Entity* ent = [entities objectAtIndex:1];
		if (ent->isStation)  // clear out queues
			[(StationEntity *)ent clear];
		[self removeEntity:ent];
	}
	
	[activeWormholes release];
	activeWormholes = savedWormholes;	// will be cleared out by populateSpaceFromActiveWormholes
	
	// maintain sorted list
	n_entities = 1;
	
	cachedSun = nil;
	cachedPlanet = nil;
	cachedStation = nil;
	[closeSystems release];
	closeSystems = nil;
	
	[self resetBeacons];
	[waypoints removeAllObjects];
	
	no_update = updating;	// restore drawing
}


- (void) removeDemoShips
{
	int i;
	int ent_count = n_entities;
	if (ent_count > 0)
	{
		Entity* ent;
		for (i = 0; i < ent_count; i++)
		{
			ent = sortedEntities[i];
			if ([ent status] == STATUS_COCKPIT_DISPLAY && ![ent isPlayer])
			{
				[self removeEntity:ent];
			}
		}
	}
	demo_ship = nil;
}


- (ShipEntity *) makeDemoShipWithRole:(NSString *)role spinning:(BOOL)spinning
{
	if ([PLAYER dockedStation] == nil)  return nil;
	
	[self removeDemoShips];	// get rid of any pre-existing models on display
	
	[PLAYER setShowDemoShips: YES];
	Quaternion q2 = { (GLfloat)M_SQRT1_2, (GLfloat)M_SQRT1_2, (GLfloat)0.0, (GLfloat)0.0 };
	
	ShipEntity *ship = [self newShipWithRole:role];   // retain count = 1
	if (ship)
	{
		double cr = [ship collisionRadius];
		[ship setOrientation:q2];
		[ship setPositionX:0.0f y:0.0f z:3.6f * cr];
		[ship setScanClass:CLASS_NO_DRAW];
		[ship switchAITo:@"nullAI.plist"];
		[ship setPendingEscortCount:0];
		
		[UNIVERSE addEntity:ship];		// STATUS_IN_FLIGHT, AI state GLOBAL
		
		if (spinning)
		{
			[ship setRoll:M_PI/5.0];	// roll must be set after addEntity or stations will not roll in demo.
			[ship setPitch:M_PI/10.0];
		}
		[ship setStatus:STATUS_COCKPIT_DISPLAY];
	}
	
	return [ship autorelease];
}


- (BOOL) isVectorClearFromEntity:(Entity *) e1 toDistance:(double)dist fromPoint:(HPVector) p2
{
	if (!e1)
		return NO;
	
	HPVector  f1;
	HPVector p1 = e1->position;
	HPVector v1 = p2;
	v1.x -= p1.x;   v1.y -= p1.y;   v1.z -= p1.z;   // vector from entity to p2
	
	double  nearest = sqrt(v1.x*v1.x + v1.y*v1.y + v1.z*v1.z) - dist;  // length of vector
	
	if (nearest < 0.0)
		return YES;			// within range already!
	
	int i;
	int ent_count = n_entities;
	Entity* my_entities[ent_count];
	for (i = 0; i < ent_count; i++)
		my_entities[i] = [sortedEntities[i] retain]; //	retained
	
	if (v1.x || v1.y || v1.z)
		f1 = HPvector_normal(v1);   // unit vector in direction of p2 from p1
	else
		f1 = make_HPvector(0, 0, 1);
	
	for (i = 0; i < ent_count ; i++)
	{
		Entity *e2 = my_entities[i];
		if ((e2 != e1)&&([e2 canCollide]))
		{
			HPVector epos = e2->position;
			epos.x -= p1.x;	epos.y -= p1.y;	epos.z -= p1.z; // epos now holds vector from p1 to this entities position
			
			double d_forward = HPdot_product(epos,f1);	// distance along f1 which is nearest to e2's position
			
			if ((d_forward > 0)&&(d_forward < nearest))
			{
				double cr = 1.10 * (e2->collision_radius + e1->collision_radius); //  10% safety margin
				HPVector p0 = e1->position;
				p0.x += d_forward * f1.x;	p0.y += d_forward * f1.y;	p0.z += d_forward * f1.z;
				// p0 holds nearest point on current course to center of incident object
				HPVector epos = e2->position;
				p0.x -= epos.x;	p0.y -= epos.y;	p0.z -= epos.z;
				// compare with center of incident object
				double  dist2 = p0.x * p0.x + p0.y * p0.y + p0.z * p0.z;
				if (dist2 < cr*cr)
				{
					for (i = 0; i < ent_count; i++)
						[my_entities[i] release]; //	released
					return NO;
				}
			}
		}
	}
	for (i = 0; i < ent_count; i++)
		[my_entities[i] release]; //	released
	return YES;
}


- (Entity*) hazardOnRouteFromEntity:(Entity *) e1 toDistance:(double)dist fromPoint:(HPVector) p2
{
	if (!e1)
		return nil;
	
	HPVector f1;
	HPVector p1 = e1->position;
	HPVector v1 = p2;
	v1.x -= p1.x;   v1.y -= p1.y;   v1.z -= p1.z;   // vector from entity to p2
	
	double  nearest = HPmagnitude(v1) - dist;  // length of vector
	
	if (nearest < 0.0)
		return nil;			// within range already!
	
	Entity* result = nil;
	int i;
	int ent_count = n_entities;
	Entity* my_entities[ent_count];
	for (i = 0; i < ent_count; i++)
		my_entities[i] = [sortedEntities[i] retain]; //	retained
	
	if (v1.x || v1.y || v1.z)
		f1 = HPvector_normal(v1);   // unit vector in direction of p2 from p1
	else
		f1 = make_HPvector(0, 0, 1);
	
	for (i = 0; (i < ent_count) && (!result) ; i++)
	{
		Entity *e2 = my_entities[i];
		if ((e2 != e1)&&([e2 canCollide]))
		{
			HPVector epos = e2->position;
			epos.x -= p1.x;	epos.y -= p1.y;	epos.z -= p1.z; // epos now holds vector from p1 to this entities position
			
			double d_forward = HPdot_product(epos,f1);	// distance along f1 which is nearest to e2's position
			
			if ((d_forward > 0)&&(d_forward < nearest))
			{
				double cr = 1.10 * (e2->collision_radius + e1->collision_radius); //  10% safety margin
				HPVector p0 = e1->position;
				p0.x += d_forward * f1.x;	p0.y += d_forward * f1.y;	p0.z += d_forward * f1.z;
				// p0 holds nearest point on current course to center of incident object
				HPVector epos = e2->position;
				p0.x -= epos.x;	p0.y -= epos.y;	p0.z -= epos.z;
				// compare with center of incident object
				double  dist2 = HPmagnitude2(p0);
				if (dist2 < cr*cr)
					result = e2;
			}
		}
	}
	for (i = 0; i < ent_count; i++)
		[my_entities[i] release]; //	released
	return result;
}


- (HPVector) getSafeVectorFromEntity:(Entity *) e1 toDistance:(double)dist fromPoint:(HPVector) p2
{
	// heuristic three
	
	if (!e1)
	{
		OOLog(kOOLogParameterError, @"***** No entity set in Universe getSafeVectorFromEntity:toDistance:fromPoint:");
		return kZeroHPVector;
	}
	
	HPVector  f1;
	HPVector  result = p2;
	int i;
	int ent_count = n_entities;
	Entity* my_entities[ent_count];
	for (i = 0; i < ent_count; i++)
		my_entities[i] = [sortedEntities[i] retain];	// retained
	HPVector p1 = e1->position;
	HPVector v1 = p2;
	v1.x -= p1.x;   v1.y -= p1.y;   v1.z -= p1.z;   // vector from entity to p2
	
	double  nearest = sqrt(v1.x*v1.x + v1.y*v1.y + v1.z*v1.z) - dist;  // length of vector
	
	if (v1.x || v1.y || v1.z)
		f1 = HPvector_normal(v1);   // unit vector in direction of p2 from p1
	else
		f1 = make_HPvector(0, 0, 1);
	
	for (i = 0; i < ent_count; i++)
	{
		Entity *e2 = my_entities[i];
		if ((e2 != e1)&&([e2 canCollide]))
		{
			HPVector epos = e2->position;
			epos.x -= p1.x;	epos.y -= p1.y;	epos.z -= p1.z;
			double d_forward = HPdot_product(epos,f1);
			if ((d_forward > 0)&&(d_forward < nearest))
			{
				double cr = 1.20 * (e2->collision_radius + e1->collision_radius); //  20% safety margin
				
				HPVector p0 = e1->position;
				p0.x += d_forward * f1.x;	p0.y += d_forward * f1.y;	p0.z += d_forward * f1.z;
				// p0 holds nearest point on current course to center of incident object
				
				HPVector epos = e2->position;
				p0.x -= epos.x;	p0.y -= epos.y;	p0.z -= epos.z;
				// compare with center of incident object
				
				double  dist2 = p0.x * p0.x + p0.y * p0.y + p0.z * p0.z;
				
				if (dist2 < cr*cr)
				{
					result = e2->position;			// center of incident object
					nearest = d_forward;
					
					if (dist2 == 0.0)
					{
						// ie. we're on a line through the object's center !
						// jitter the position somewhat!
						result.x += ((int)(Ranrot() % 1024) - 512)/512.0; //   -1.0 .. +1.0
						result.y += ((int)(Ranrot() % 1024) - 512)/512.0; //   -1.0 .. +1.0
						result.z += ((int)(Ranrot() % 1024) - 512)/512.0; //   -1.0 .. +1.0
					}
					
					HPVector  nearest_point = p1;
					nearest_point.x += d_forward * f1.x;	nearest_point.y += d_forward * f1.y;	nearest_point.z += d_forward * f1.z;
					// nearest point now holds nearest point on line to center of incident object
					
					HPVector outward = nearest_point;
					outward.x -= result.x;	outward.y -= result.y;	outward.z -= result.z;
					if (outward.x||outward.y||outward.z)
						outward = HPvector_normal(outward);
					else
						outward.y = 1.0;
					// outward holds unit vector through the nearest point on the line from the center of incident object
					
					HPVector backward = p1;
					backward.x -= result.x;	backward.y -= result.y;	backward.z -= result.z;
					if (backward.x||backward.y||backward.z)
						backward = HPvector_normal(backward);
					else
						backward.z = -1.0;
					// backward holds unit vector from center of the incident object to the center of the ship
					
					HPVector dd = result;
					dd.x -= p1.x; dd.y -= p1.y; dd.z -= p1.z;
					double current_distance = HPmagnitude(dd);
					
					// sanity check current_distance
					if (current_distance < cr * 1.25)	// 25% safety margin
						current_distance = cr * 1.25;
					if (current_distance > cr * 5.0)	// up to 2 diameters away 
						current_distance = cr * 5.0;
					
					// choose a point that's three parts backward and one part outward
					
					result.x += 0.25 * (outward.x * current_distance) + 0.75 * (backward.x * current_distance);		// push 'out' by this amount
					result.y += 0.25 * (outward.y * current_distance) + 0.75 * (backward.y * current_distance);
					result.z += 0.25 * (outward.z * current_distance) + 0.75 * (backward.z * current_distance);
					
				}
			}
		}
	}
	for (i = 0; i < ent_count; i++)
		[my_entities[i] release]; //	released
	return result;
}


- (ShipEntity *) firstShipHitByLaserFromShip:(ShipEntity *)srcEntity inDirection:(OOWeaponFacing)direction offset:(Vector)offset gettingRangeFound:(GLfloat *)range_ptr
{
	if (srcEntity == nil) return nil;
	
	ShipEntity		*hit_entity = nil;
	ShipEntity		*hit_subentity = nil;
	HPVector			p0 = [srcEntity position];
	Quaternion		q1 = [srcEntity normalOrientation];
	ShipEntity		*parent = [srcEntity parentEntity];
	
	if (parent)
	{
		// we're a subentity!
		BoundingBox bbox = [srcEntity boundingBox];
		HPVector midfrontplane = make_HPvector(0.5 * (bbox.max.x + bbox.min.x), 0.5 * (bbox.max.y + bbox.min.y), bbox.max.z);
		p0 = [srcEntity absolutePositionForSubentityOffset:midfrontplane];
		q1 = [parent orientation];
		if ([parent isPlayer])  q1.w = -q1.w;
	}
	
	double			nearest = [srcEntity weaponRange];
	int				i;
	int				ent_count = n_entities;
	int				ship_count = 0;
	ShipEntity		*my_entities[ent_count];
	
	for (i = 0; i < ent_count; i++)
	{
		Entity* ent = sortedEntities[i];
		if (ent != srcEntity && ent != parent && [ent isShip] && [ent canCollide])
		{
			my_entities[ship_count++] = [(ShipEntity *)ent retain];
		}
	}
	
	
	Vector u1, f1, r1;
	basis_vectors_from_quaternion(q1, &r1, &u1, &f1);
	p0 = HPvector_add(p0, vectorToHPVector(OOVectorMultiplyMatrix(offset, OOMatrixFromBasisVectors(r1, u1, f1))));
	
	switch (direction)
	{
		case WEAPON_FACING_FORWARD:
		case WEAPON_FACING_NONE:
			break;
			
		case WEAPON_FACING_AFT:
			quaternion_rotate_about_axis(&q1, u1, M_PI);
			break;
			
		case WEAPON_FACING_PORT:
			quaternion_rotate_about_axis(&q1, u1, M_PI/2.0);
			break;
			
		case WEAPON_FACING_STARBOARD:
			quaternion_rotate_about_axis(&q1, u1, -M_PI/2.0);
			break;
	}
	
	basis_vectors_from_quaternion(q1, &r1, NULL, &f1);
	HPVector p1 = HPvector_add(p0, vectorToHPVector(vector_multiply_scalar(f1, nearest)));	//endpoint
	
	for (i = 0; i < ship_count; i++)
	{
		ShipEntity *e2 = my_entities[i];
		
		// check outermost bounding sphere
		GLfloat cr = e2->collision_radius;
		Vector rpos = HPVectorToVector(HPvector_subtract(e2->position, p0));
		Vector v_off = make_vector(dot_product(rpos, r1), dot_product(rpos, u1), dot_product(rpos, f1));
		if (v_off.z > 0.0 && v_off.z < nearest + cr &&								// ahead AND within range
			v_off.x < cr && v_off.x > -cr && v_off.y < cr && v_off.y > -cr &&		// AND not off to one side or another
			v_off.x * v_off.x + v_off.y * v_off.y < cr * cr)						// AND not off to both sides
		{
			ShipEntity *entHit = nil;
			GLfloat hit = [(ShipEntity *)e2 doesHitLine:p0 :p1 :&entHit];	// octree detection
			
			if (hit > 0.0 && hit < nearest)
			{
				if ([entHit isSubEntity])
				{
					hit_subentity = entHit;
				}
				hit_entity = e2;
				nearest = hit;
				p1 = HPvector_add(p0, vectorToHPVector(vector_multiply_scalar(f1, nearest)));
			}
		}
	}
	
	if (hit_entity)
	{
		// I think the above code does not guarantee that the closest hit_subentity belongs to the closest hit_entity.
		if (hit_subentity && [hit_subentity owner] == hit_entity)  [hit_entity setSubEntityTakingDamage:hit_subentity];
		
		if (range_ptr != NULL)
		{
			*range_ptr = nearest;
		}
	}
	
	for (i = 0; i < ship_count; i++)  [my_entities[i] release]; //	released
	
	return hit_entity;
}


- (Entity *) firstEntityTargetedByPlayer
{
	PlayerEntity	*player = PLAYER;
	Entity			*hit_entity = nil;
	OOScalar		nearest2 = SCANNER_MAX_RANGE - 100;	// 100m shorter than range at which target is lost
	nearest2 *= nearest2;
	int				i;
	int				ent_count = n_entities;
	int				ship_count = 0;
	Entity			*my_entities[ent_count];
	
	for (i = 0; i < ent_count; i++)
	{
		if (([sortedEntities[i] isShip] && ![sortedEntities[i] isPlayer]) || [sortedEntities[i] isWormhole])
		{
			my_entities[ship_count++] = [sortedEntities[i] retain];
		}
	}
	
	Quaternion q1 = [player normalOrientation];
	Vector u1, f1, r1;
	basis_vectors_from_quaternion(q1, &r1, &u1, &f1);
	Vector offset = [player weaponViewOffset];
	
	HPVector p1 = HPvector_add([player position], vectorToHPVector(OOVectorMultiplyMatrix(offset, OOMatrixFromBasisVectors(r1, u1, f1))));
	
	// Note: deliberately tied to view direction, not weapon facing. All custom views count as forward for targeting.
	switch (viewDirection)
	{
		case VIEW_AFT :
			quaternion_rotate_about_axis(&q1, u1, M_PI);
			break;
		case VIEW_PORT :
			quaternion_rotate_about_axis(&q1, u1, 0.5 * M_PI);
			break;
		case VIEW_STARBOARD :
			quaternion_rotate_about_axis(&q1, u1, -0.5 * M_PI);
			break;
		default:
			break;
	}
	basis_vectors_from_quaternion(q1, &r1, NULL, &f1);
	
	for (i = 0; i < ship_count; i++)
	{
		Entity *e2 = my_entities[i];
		if ([e2 canCollide] && [e2 scanClass] != CLASS_NO_DRAW)
		{
			Vector rp = HPVectorToVector(HPvector_subtract([e2 position], p1));
			OOScalar dist2 = magnitude2(rp);
			if (dist2 < nearest2)
			{
				OOScalar df = dot_product(f1, rp);
				if (df > 0.0 && df * df < nearest2)
				{
					OOScalar du = dot_product(u1, rp);
					OOScalar dr = dot_product(r1, rp);
					OOScalar cr = [e2 collisionRadius];
					if (du * du + dr * dr < cr * cr)
					{
						hit_entity = e2;
						nearest2 = dist2;
					}
				}
			}
		}
	}
	// check for MASC'M
	if (hit_entity != nil && [hit_entity isShip])
	{
		ShipEntity* ship = (ShipEntity*)hit_entity;
		if ([ship isJammingScanning] && ![player hasMilitaryScannerFilter])
		{
			hit_entity = nil;
		}
	}
	
	for (i = 0; i < ship_count; i++)
	{
		[my_entities[i] release];
	}
	
	return hit_entity;
}


- (Entity *) firstEntityTargetedByPlayerPrecisely
{
	OOWeaponFacing targetFacing;
	
	switch (viewDirection)
	{
		case VIEW_FORWARD:
			targetFacing = WEAPON_FACING_FORWARD;
			break;
			
		case VIEW_AFT:
			targetFacing = WEAPON_FACING_AFT;
			break;
			
		case VIEW_PORT:
			targetFacing = WEAPON_FACING_PORT;
			break;
			
		case VIEW_STARBOARD:
			targetFacing = WEAPON_FACING_STARBOARD;
			break;
			
		default:
			// Match behaviour of -firstEntityTargetedByPlayer.
			targetFacing = WEAPON_FACING_FORWARD;
	}
	
	return [self firstShipHitByLaserFromShip:PLAYER inDirection:targetFacing offset:kZeroVector gettingRangeFound:NULL];
}


- (NSArray *) entitiesWithinRange:(double)range ofEntity:(Entity *)entity
{
	if (entity == nil)  return nil;
	
	return [self findShipsMatchingPredicate:YESPredicate
								  parameter:NULL
									inRange:range
								   ofEntity:entity];
}


- (unsigned) countShipsWithRole:(NSString *)role inRange:(double)range ofEntity:(Entity *)entity
{
	return [self countShipsMatchingPredicate:HasRolePredicate
							   parameter:role
								 inRange:range
								ofEntity:entity];
}


- (unsigned) countShipsWithRole:(NSString *)role
{
	return [self countShipsWithRole:role inRange:-1 ofEntity:nil];
}


- (unsigned) countShipsWithPrimaryRole:(NSString *)role inRange:(double)range ofEntity:(Entity *)entity
{
	return [self countShipsMatchingPredicate:HasPrimaryRolePredicate
							   parameter:role
								 inRange:range
								ofEntity:entity];
}


- (unsigned) countShipsWithScanClass:(OOScanClass)scanClass inRange:(double)range ofEntity:(Entity *)entity
{
	return [self countShipsMatchingPredicate:HasScanClassPredicate
							   parameter:[NSNumber numberWithInt:scanClass]
								 inRange:range
								ofEntity:entity];
}


- (unsigned) countShipsWithPrimaryRole:(NSString *)role
{
	return [self countShipsWithPrimaryRole:role inRange:-1 ofEntity:nil];
}


- (void) sendShipsWithPrimaryRole:(NSString *)role messageToAI:(NSString *)ms
{
	NSArray			*targets = nil;
	
	targets = [self findShipsMatchingPredicate:HasPrimaryRolePredicate
									 parameter:role
									   inRange:-1
									  ofEntity:nil];
	
	[targets makeObjectsPerformSelector:@selector(reactToMessage:) withObject:ms];
}


- (unsigned) countEntitiesMatchingPredicate:(EntityFilterPredicate)predicate
								  parameter:(void *)parameter
									inRange:(double)range
								   ofEntity:(Entity *)e1
{
	unsigned		i, found = 0;
	HPVector			p1;
	double			distance, cr;
	
	if (predicate == NULL)  predicate = YESPredicate;
	
	if (e1 != nil)  p1 = e1->position;
	else  p1 = kZeroHPVector;
	
	for (i = 0; i < n_entities; i++)
	{
		Entity *e2 = sortedEntities[i];
		if (e2 != e1 && predicate(e2, parameter))
		{
			if (range < 0)  distance = -1;	// Negative range means infinity
			else
			{
				cr = range + e2->collision_radius;
				distance = HPdistance2(e2->position, p1) - cr * cr;
			}
			if (distance < 0)
			{
				found++;
			}
		}
	}
	
	return found;
}


- (unsigned) countShipsMatchingPredicate:(EntityFilterPredicate)predicate
							   parameter:(void *)parameter
								 inRange:(double)range
								ofEntity:(Entity *)entity
{
	if (predicate != NULL)
	{
		BinaryOperationPredicateParameter param =
		{
			IsShipPredicate, NULL,
			predicate, parameter
		};
		
		return [self countEntitiesMatchingPredicate:ANDPredicate
										  parameter:&param
											inRange:range
										   ofEntity:entity];
	}
	else
	{
		return [self countEntitiesMatchingPredicate:IsShipPredicate
										  parameter:NULL
											inRange:range
										   ofEntity:entity];
	}
}


OOINLINE BOOL EntityInRange(HPVector p1, Entity *e2, float range)
{
	if (range < 0)  return YES;
	float cr = range + e2->collision_radius;
	return HPdistance2(e2->position,p1) < cr * cr;
}


// NOTE: OOJSSystem relies on this returning entities in distance-from-player order.
// This can be easily changed by removing the [reference isPlayer] conditions in FindJSVisibleEntities().
- (NSMutableArray *) findEntitiesMatchingPredicate:(EntityFilterPredicate)predicate
								  parameter:(void *)parameter
									inRange:(double)range
								   ofEntity:(Entity *)e1
{
	OOJS_PROFILE_ENTER
	
	unsigned		i;
	HPVector			p1;
	NSMutableArray	*result = nil;
	
	OOJSPauseTimeLimiter();
	
	if (predicate == NULL)  predicate = YESPredicate;
	
	result = [NSMutableArray arrayWithCapacity:n_entities];
	
	if (e1 != nil)  p1 = [e1 position];
	else  p1 = kZeroHPVector;
	
	for (i = 0; i < n_entities; i++)
	{
		Entity *e2 = sortedEntities[i];
		
		if (e1 != e2 &&
			EntityInRange(p1, e2, range) &&
			predicate(e2, parameter))
		{
			[result addObject:e2];
		}
	}
	
	OOJSResumeTimeLimiter();
	
	return result;
	
	OOJS_PROFILE_EXIT
}


- (id) findOneEntityMatchingPredicate:(EntityFilterPredicate)predicate
							parameter:(void *)parameter
{
	unsigned		i;
	Entity			*candidate = nil;
	
	OOJSPauseTimeLimiter();
	
	if (predicate == NULL)  predicate = YESPredicate;
	
	for (i = 0; i < n_entities; i++)
	{
		candidate = sortedEntities[i];
		if (predicate(candidate, parameter))  return candidate;
	}
	
	OOJSResumeTimeLimiter();
	
	return nil;
}


- (NSMutableArray *) findShipsMatchingPredicate:(EntityFilterPredicate)predicate
									  parameter:(void *)parameter
										inRange:(double)range
									   ofEntity:(Entity *)entity
{
	if (predicate != NULL)
	{
		BinaryOperationPredicateParameter param =
		{
			IsShipPredicate, NULL,
			predicate, parameter
		};
		
		return [self findEntitiesMatchingPredicate:ANDPredicate
										 parameter:&param
										   inRange:range
										  ofEntity:entity];
	}
	else
	{
		return [self findEntitiesMatchingPredicate:IsShipPredicate
										 parameter:NULL
										   inRange:range
										  ofEntity:entity];
	}
}


- (NSMutableArray *) findVisualEffectsMatchingPredicate:(EntityFilterPredicate)predicate
									  parameter:(void *)parameter
										inRange:(double)range
									   ofEntity:(Entity *)entity
{
	if (predicate != NULL)
	{
		BinaryOperationPredicateParameter param =
		{
			IsVisualEffectPredicate, NULL,
			predicate, parameter
		};
		
		return [self findEntitiesMatchingPredicate:ANDPredicate
										 parameter:&param
										   inRange:range
										  ofEntity:entity];
	}
	else
	{
		return [self findEntitiesMatchingPredicate:IsVisualEffectPredicate
										 parameter:NULL
										   inRange:range
										  ofEntity:entity];
	}
}


- (id) nearestEntityMatchingPredicate:(EntityFilterPredicate)predicate
							parameter:(void *)parameter
					 relativeToEntity:(Entity *)entity
{
	unsigned		i;
	HPVector			p1;
	float			rangeSq = INFINITY;
	id				result = nil;
	
	if (predicate == NULL)  predicate = YESPredicate;
	
	if (entity != nil)  p1 = [entity position];
	else  p1 = kZeroHPVector;
	
	for (i = 0; i < n_entities; i++)
	{
		Entity *e2 = sortedEntities[i];
		float distanceToReferenceEntitySquared = (float)HPdistance2(p1, [e2 position]);
		
		if (entity != e2 &&
			distanceToReferenceEntitySquared < rangeSq &&
			predicate(e2, parameter))
		{
			result = e2;
			rangeSq = distanceToReferenceEntitySquared;
		}
	}
	
	return [[result retain] autorelease];
}


- (id) nearestShipMatchingPredicate:(EntityFilterPredicate)predicate
						  parameter:(void *)parameter
				   relativeToEntity:(Entity *)entity
{
	if (predicate != NULL)
	{
		BinaryOperationPredicateParameter param =
		{
			IsShipPredicate, NULL,
			predicate, parameter
		};
		
		return [self nearestEntityMatchingPredicate:ANDPredicate
										  parameter:&param
								   relativeToEntity:entity];
	}
	else
	{
		return [self nearestEntityMatchingPredicate:IsShipPredicate
										  parameter:NULL
								   relativeToEntity:entity];
	}
}


- (OOTimeAbsolute) getTime
{
	return universal_time;
}


- (OOTimeDelta) getTimeDelta
{
	return time_delta;
}


- (void) findCollisionsAndShadows
{
	unsigned i;
	
	[universeRegion clearEntityList];
	
	for (i = 0; i < n_entities; i++)
	{
		[universeRegion checkEntity:sortedEntities[i]];	// sorts out which region it's in
	}
	
	if (![[self gameController] isGamePaused])
	{
		[universeRegion findCollisions];
	}
	
	// do check for entities that can't see the sun!
	[universeRegion findShadowedEntities];
}


- (NSString*) collisionDescription
{
	if (universeRegion != nil)  return [universeRegion collisionDescription];
	else  return @"-";
}


- (void) dumpCollisions
{
	dumpCollisionInfo = YES;
}


- (OOViewID) viewDirection
{
	return viewDirection;
}


- (void) setViewDirection:(OOViewID) vd
{
	NSString		*ms = nil;
	BOOL			guiSelected = NO;
	
	if ((viewDirection == vd) && (vd != VIEW_CUSTOM) && (!displayGUI))
		return;
	
	switch (vd)
	{
		case VIEW_FORWARD:
			ms = DESC(@"forward-view-string");
			break;
			
		case VIEW_AFT:
			ms = DESC(@"aft-view-string");
			break;
			
		case VIEW_PORT:
			ms = DESC(@"port-view-string");
			break;
			
		case VIEW_STARBOARD:
			ms = DESC(@"starboard-view-string");
			break;
			
		case VIEW_CUSTOM:
			ms = [PLAYER customViewDescription];
			break;
			
		case VIEW_GUI_DISPLAY:
			[self setDisplayText:YES];
			[self setMainLightPosition:(Vector){ DEMO_LIGHT_POSITION }];
			guiSelected = YES;
			break;
			
		default:
			guiSelected = YES;
			break;
	}
	
	if (guiSelected)
	{
		[[self gameController] setMouseInteractionModeForUIWithMouseInteraction:NO];
	}
	else
	{
		displayGUI = NO;   // switch off any text displays
		[[self gameController] setMouseInteractionModeForFlight];
	}
	
	if (viewDirection != vd || viewDirection == VIEW_CUSTOM)
	{
		#if (ALLOW_CUSTOM_VIEWS_WHILE_PAUSED)
		BOOL gamePaused = [[self gameController] isGamePaused];
		#else
		BOOL gamePaused = NO;
		#endif
		// view notifications for when the player switches to/from gui!
		//if (EXPECT(viewDirection == VIEW_GUI_DISPLAY || vd == VIEW_GUI_DISPLAY )) [PLAYER noteViewDidChangeFrom:viewDirection toView:vd];
		viewDirection = vd;
		if (ms && !gamePaused)
		{
			[self addMessage:ms forCount:3];
		}
		else if (gamePaused)
		{
			[message_gui clear];
		}
	}
}


- (void) enterGUIViewModeWithMouseInteraction:(BOOL)mouseInteraction
{
	[self setViewDirection:VIEW_GUI_DISPLAY];
	[[self gameController] setMouseInteractionModeForUIWithMouseInteraction:mouseInteraction];
}


- (NSString *) soundNameForCustomSoundKey:(NSString *)key
{
	NSString				*result = nil;
	NSMutableSet			*seen = nil;
	id object = [customSounds objectForKey:key];
	
	if ([object isKindOfClass:[NSArray class]] && [object count] > 0)
	{
		key = [object oo_stringAtIndex:Ranrot() % [object count]];
	}
	else
	{
		object=nil;
	}
	
	result = [[OOCacheManager sharedCache] objectForKey:key inCache:@"resolved custom sounds"];
	if (result == nil)
	{
		// Resolve sound, allowing indirection within customsounds.plist
		seen = [NSMutableSet set];
		result = key;
		if (object == nil || ([result hasPrefix:@"["] && [result hasSuffix:@"]"]))
		{
			for (;;)
			{
				[seen addObject:result];
				object = [customSounds objectForKey:result];
				if( [object isKindOfClass:[NSArray class]] && [object count] > 0)
				{
					result = [object oo_stringAtIndex:Ranrot() % [object count]];
					if ([key hasPrefix:@"["] && [key hasSuffix:@"]"]) key=result;
				}
				else
				{
					if ([object isKindOfClass:[NSString class]])
						result = object;
					else
						result = nil;
				}
				if (result == nil || ![result hasPrefix:@"["] || ![result hasSuffix:@"]"])  break;
				if ([seen containsObject:result])
				{
					OOLogERR(@"sound.customSounds.recursion", @"recursion in customsounds.plist for '%@' (at '%@'), no sound will be played.", key, result);
					result = nil;
					break;
				}
			}
		}
		
		if (result == nil)  result = @"__oolite-no-sound";
		[[OOCacheManager sharedCache] setObject:result forKey:key inCache:@"resolved custom sounds"];
	}
	
	if ([result isEqualToString:@"__oolite-no-sound"])
	{
		OOLog(@"sound.customSounds", @"Could not resolve sound name in customsounds.plist for '%@', no sound will be played.", key);
		result = nil;
	}
	return result;
}


- (NSDictionary *) screenTextureDescriptorForKey:(NSString *)key
{
	id value = [screenBackgrounds objectForKey:key];
	while ([value isKindOfClass:[NSArray class]])  value = [value objectAtIndex:Ranrot() % [value count]];
	
	if ([value isKindOfClass:[NSString class]])  value = [NSDictionary dictionaryWithObject:value forKey:@"name"];
	else if (![value isKindOfClass:[NSDictionary class]])  value = nil;
	
	// Start loading the texture, and return nil if it doesn't exist.
	if (![[self gui] preloadGUITexture:value])  value = nil;
	
	return value;
}


- (void) clearPreviousMessage
{
	if (currentMessage)	[currentMessage release];
	currentMessage = nil;
}


- (void) setMessageGuiBackgroundColor:(OOColor *)some_color
{
	[message_gui setBackgroundColor:some_color];
}


- (void) displayMessage:(NSString *) text forCount:(OOTimeDelta)count
{
	if (![currentMessage isEqual:text] || universal_time >= messageRepeatTime)
	{
		if (currentMessage)	[currentMessage release];
		currentMessage = [text retain];
		messageRepeatTime=universal_time + 6.0;
		[message_gui printLongText:text align:GUI_ALIGN_CENTER color:[OOColor yellowColor] fadeTime:count key:nil addToArray:nil];
	}
}


- (void) displayCountdownMessage:(NSString *) text forCount:(OOTimeDelta)count
{
	if (![currentMessage isEqual:text] && universal_time >= countdown_messageRepeatTime)
	{
		if (currentMessage)	[currentMessage release];
		currentMessage = [text retain];
		countdown_messageRepeatTime=universal_time + count;
		[message_gui printLineNoScroll:text align:GUI_ALIGN_CENTER color:[OOColor yellowColor] fadeTime:count key:nil addToArray:nil];
	}
}


- (void) addDelayedMessage:(NSString *)text forCount:(OOTimeDelta)count afterDelay:(double)delay
{
	NSMutableDictionary *msgDict = [NSMutableDictionary dictionaryWithCapacity:2];
	[msgDict setObject:text forKey:@"message"];
	[msgDict setObject:[NSNumber numberWithDouble:count] forKey:@"duration"];
	[self performSelector:@selector(addDelayedMessage:) withObject:msgDict afterDelay:delay];
}


- (void) addDelayedMessage:(NSDictionary *) textdict
{
	NSString		*msg = nil;
	OOTimeDelta		msg_duration;
	
	msg = [textdict oo_stringForKey:@"message"];
	if (msg == nil)  return;
	msg_duration = [textdict oo_nonNegativeDoubleForKey:@"duration" defaultValue:3.0];
	
	[self addMessage:msg forCount:msg_duration];
}


- (void) addMessage:(NSString *)text forCount:(OOTimeDelta)count
{
	[self addMessage:text forCount:count forceDisplay:NO];
}


- (void) speakWithSubstitutions:(NSString *)text
{
#if OOLITE_SPEECH_SYNTH
	//speech synthesis
	
	PlayerEntity* player = PLAYER;
	if ([player isSpeechOn])
	{
		BOOL		isStandard = NO;
		NSString	*systemSaid = nil;
		NSString	*h_systemSaid = nil;
		
		NSString	*systemName = [self getSystemName:system_seed];
		
		isStandard = [systemName isEqualToString:[self generateSystemName:system_seed]];
		//if the name is not the standard generated one, we can't  use the generated phonemes.
		systemSaid = isStandard ? [self generatePhoneticSystemName:system_seed] : systemName;
		
		NSString	*h_systemName = [self getSystemName:[player target_system_seed]];
		isStandard = [h_systemName isEqualToString: [self generateSystemName:[player target_system_seed]]];
		h_systemSaid = isStandard ? [self generatePhoneticSystemName:[player target_system_seed]] : h_systemName;
		
		NSString	*spokenText = text;
		if (speechArray != nil)
		{
			NSEnumerator	*speechEnumerator = nil;
			NSArray			*thePair = nil;
			
			for (speechEnumerator = [speechArray objectEnumerator]; (thePair = [speechEnumerator nextObject]); )
			{
				NSString *original_phrase = [thePair oo_stringAtIndex:0];
				
				NSUInteger replacementIndex;
#if OOLITE_MAC_OS_X
				replacementIndex = 1;
#elif OOLITE_ESPEAK
				replacementIndex = [thePair count] > 2 ? 2 : 1;
#endif
				
				NSString *replacement_phrase = [thePair oo_stringAtIndex:replacementIndex];
				if (![replacement_phrase isEqualToString:@"_"])
				{
					spokenText = [spokenText stringByReplacingOccurrencesOfString:original_phrase withString:replacement_phrase];
				}
			}
			spokenText = [spokenText stringByReplacingOccurrencesOfString:systemName withString:systemSaid];
			spokenText = [spokenText stringByReplacingOccurrencesOfString:h_systemName withString:h_systemSaid];
		}
		[self stopSpeaking];
		[self startSpeakingString:spokenText];
	}
#endif	// OOLITE_SPEECH_SYNTH
}


- (void) addMessage:(NSString *) text forCount:(OOTimeDelta) count forceDisplay:(BOOL) forceDisplay
{
	if (![currentMessage isEqual:text] || forceDisplay || universal_time >= messageRepeatTime)
	{
		[self speakWithSubstitutions:text];
		
		[message_gui printLongText:text align:GUI_ALIGN_CENTER color:[OOColor yellowColor] fadeTime:count key:nil addToArray:nil];
		
		[currentMessage release];
		currentMessage = [text retain];
		messageRepeatTime=universal_time + 6.0;
	}
}


- (void) addCommsMessage:(NSString *)text forCount:(OOTimeDelta)count
{
	[self addCommsMessage:text forCount:count andShowComms:_autoCommLog logOnly:NO];
}


- (void) addCommsMessage:(NSString *)text forCount:(OOTimeDelta)count andShowComms:(BOOL)showComms logOnly:(BOOL)logOnly
{
	if ([PLAYER showDemoShips]) return;
	
	if (![currentMessage isEqualToString:text] || universal_time >= messageRepeatTime)
	{
		PlayerEntity* player = PLAYER;
		
		if (!logOnly)
		{
			if ([player isSpeechOn])
			{
				// EMMSTRAN: should say "Incoming message from ..." when prefixed with sender name.
				NSString *format = OOExpandKey(@"speech-synthesis-incoming-message-@");
				[self speakWithSubstitutions:[NSString stringWithFormat:format, text]];
			}
			
			[message_gui printLongText:text align:GUI_ALIGN_CENTER color:[OOColor greenColor] fadeTime:count key:nil addToArray:nil];
			
			[currentMessage release];
			currentMessage = [text retain];
			messageRepeatTime=universal_time + 6.0;
		}
		
		[comm_log_gui printLongText:text align:GUI_ALIGN_LEFT color:nil fadeTime:0.0 key:nil addToArray:[player commLog]];
		
		if (showComms)  [self showCommsLog:6.0];
	}
}


- (void) showCommsLog:(OOTimeDelta)how_long
{
	[comm_log_gui setAlpha:1.0];
	if (![self permanentCommLog]) [comm_log_gui fadeOutFromTime:[self getTime] overDuration:how_long];
}


- (void) repopulateSystem
{
	JSContext			*context = OOJSAcquireContext();
	[PLAYER doWorldScriptEvent:OOJSIDFromString(system_repopulator) inContext:context withArguments:NULL count:0 timeLimit:kOOJSLongTimeLimit];
	OOJSRelinquishContext(context);
	next_repopulation = SYSTEM_REPOPULATION_INTERVAL;
}


- (void) update:(OOTimeDelta)inDeltaT
{
	volatile OOTimeDelta delta_t = inDeltaT * [self timeAccelerationFactor];
	NSUInteger sessionID = _sessionID;
	OOLog(@"universe.profile.update",@"Begin update");
	if (EXPECT(!no_update))
	{
		next_repopulation -= delta_t;
		if (next_repopulation < 0)
		{
			[self repopulateSystem];
		}

		unsigned	i, ent_count = n_entities;
		Entity		*my_entities[ent_count];
		
		[self verifyEntitySessionIDs];
		
		// use a retained copy so this can't be changed under us.
		for (i = 0; i < ent_count; i++)
		{
			my_entities[i] = [sortedEntities[i] retain];	// explicitly retain each one
		}
		
		NSString * volatile update_stage = @"initialisation";
#ifndef NDEBUG
		id volatile update_stage_param = nil;
#endif
		
		@try
		{
			PlayerEntity *player = PLAYER;
			
			skyClearColor[0] = 0.0;
			skyClearColor[1] = 0.0;
			skyClearColor[2] = 0.0;
			skyClearColor[3] = 0.0;
			
			time_delta = delta_t;
			universal_time += delta_t;
			
			if (EXPECT_NOT([player showDemoShips] && [player guiScreen] == GUI_SCREEN_INTRO2))
			{
				update_stage = @"demo management";
				
				if (universal_time >= demo_stage_time)
				{
					if (ent_count > 1)
					{
						Vector		vel;
						Quaternion	q2 = kIdentityQuaternion;
						
						quaternion_rotate_about_y(&q2,M_PI);
						
						#define DEMO2_VANISHING_DISTANCE	400.0
						#define DEMO2_FLY_IN_STAGE_TIME	1.5
						
						switch (demo_stage)
						{
							case DEMO_FLY_IN:
								[demo_ship setPosition:[demo_ship destination]];	// ideal position
								demo_stage = DEMO_SHOW_THING;
								demo_stage_time = universal_time + 6.0;
								break;
							case DEMO_SHOW_THING:
								vel = make_vector(0, 0, DEMO2_VANISHING_DISTANCE * demo_ship->collision_radius);
								[demo_ship setVelocity:vel];
								demo_stage = DEMO_FLY_OUT;
								demo_stage_time = universal_time + 1.5;
								break;
							case DEMO_FLY_OUT:
								// change the demo_ship here
								[self removeEntity:demo_ship];
								demo_ship = nil;
								
								NSString		*shipDesc = nil;
								NSString		*shipName = nil;
								NSDictionary	*shipDict = nil;
								
								demo_ship_index = (demo_ship_index + 1) % [demo_ships count];
								shipDesc = [demo_ships oo_stringAtIndex:demo_ship_index];
								shipDict = [[OOShipRegistry sharedRegistry] shipInfoForKey:shipDesc];
								
								// Failure means we don't change demo_stage, so we'll automatically try again.
								demo_ship = [[ShipEntity alloc] initWithKey:shipDesc definition:shipDict];
								
								if (demo_ship != nil)
								{
									[demo_ship switchAITo:@"nullAI.plist"];
									[demo_ship setOrientation:q2];
									[demo_ship setScanClass: CLASS_NO_DRAW];
									[demo_ship setStatus: STATUS_COCKPIT_DISPLAY]; // prevents it getting escorts on addition
									if ([self addEntity:demo_ship])
									{
										[demo_ship release];		// We now own a reference through the entity list.
										[demo_ship setStatus:STATUS_COCKPIT_DISPLAY];
										demo_start_z=DEMO2_VANISHING_DISTANCE * demo_ship->collision_radius;
										[demo_ship setPositionX:0.0f y:0.0f z:demo_start_z];
										[demo_ship setDestination: make_HPvector(0.0f, 0.0f, demo_start_z * 0.01f)];	// ideal position
										[demo_ship setVelocity:kZeroVector];
										[demo_ship setScanClass: CLASS_NO_DRAW];
										[demo_ship setRoll:M_PI/5.0];
										[demo_ship setPitch:M_PI/10.0];
										[gui setText:shipName != nil ? shipName : [demo_ship displayName] forRow:19 align:GUI_ALIGN_CENTER];
										
										demo_stage = DEMO_FLY_IN;
										demo_start_time=universal_time;
										demo_stage_time = demo_start_time + DEMO2_FLY_IN_STAGE_TIME;
									}
									else
									{
										demo_ship = nil;
									}
								}
								break;
						}
					}
				}
				else if (demo_stage == DEMO_FLY_IN)
				{
					GLfloat delta = (universal_time - demo_start_time) / DEMO2_FLY_IN_STAGE_TIME;
					[demo_ship setPositionX:0.0f y:[demo_ship destination].y * delta z:demo_start_z + ([demo_ship destination].z - demo_start_z) * delta ];
				}
			}
			
			update_stage = @"update:entity";
			NSMutableSet *zombies = nil;
			OOLog(@"universe.profile.update", @"%@", update_stage);
			for (i = 0; i < ent_count; i++)
			{
				Entity *thing = my_entities[i];
#ifndef NDEBUG
				update_stage_param = thing;
				update_stage = @"update:entity [%@]";
#endif
				// Game Over code depends on regular delta_t updates to the dead player entity. Ignore the player entity, even when dead.
				if (EXPECT_NOT([thing status] == STATUS_DEAD && ![entitiesDeadThisUpdate containsObject:thing] && ![thing isPlayer]))
				{
					if (zombies == nil)  zombies = [NSMutableSet set];
					[zombies addObject:thing];
					continue;
				}
				
				[thing update:delta_t];
				if (EXPECT_NOT(sessionID != _sessionID))
				{
					// Game was reset (in player update); end this update: cycle.
					break;
				}
				
#ifndef NDEBUG
				update_stage = @"update:list maintenance [%@]";
#endif
				
				// maintain distance-from-player list
				GLfloat z_distance = thing->zero_distance;
				
				int index = thing->zero_index;
				while (index > 0 && z_distance < sortedEntities[index - 1]->zero_distance)
				{
					sortedEntities[index] = sortedEntities[index - 1];	// bubble up the list, usually by just one position
					sortedEntities[index - 1] = thing;
					thing->zero_index = index - 1;
					sortedEntities[index]->zero_index = index;
					index--;
				}
				
				// update deterministic AI
				if ([thing isShip])
				{
#ifndef NDEBUG
					update_stage = @"update:think [%@]";
#endif
					AI* theShipsAI = [(ShipEntity *)thing getAI];
					if (theShipsAI)
					{
						double thinkTime = [theShipsAI nextThinkTime];
						if ((universal_time > thinkTime)||(thinkTime == 0.0))
						{
							[theShipsAI setNextThinkTime:universal_time + [theShipsAI thinkTimeInterval]];
							[theShipsAI think];
						}
					}
				}
			}
#ifndef NDEBUG
		update_stage_param = nil;
#endif
			
			if (zombies != nil)
			{
				update_stage = @"shootin' zombies";
				NSEnumerator *zombieEnum = nil;
				Entity *zombie = nil;
				for (zombieEnum = [zombies objectEnumerator]; (zombie = [zombieEnum nextObject]); )
				{
					OOLogERR(@"universe.zombie", @"Found dead entity %@ in active entity list, removing. This is an internal error, please report it.", zombie);
					[self removeEntity:zombie];
				}
			}
			
			// Maintain x/y/z order lists
			update_stage = @"updating linked lists";
			OOLog(@"universe.profile.update", @"%@", update_stage);
			for (i = 0; i < ent_count; i++)
			{
				[my_entities[i] updateLinkedLists];
			}
			
			// detect collisions and light ships that can see the sun
			
			update_stage = @"collision and shadow detection";
			OOLog(@"universe.profile.update", @"%@", update_stage);
			[self filterSortedLists];
			[self findCollisionsAndShadows];
			
			// do any required check and maintenance of linked lists
			
			if (doLinkedListMaintenanceThisUpdate)
			{
				MaintainLinkedLists(self);
				doLinkedListMaintenanceThisUpdate = NO;
			}
		}
		@catch (NSException *exception)
		{
			if ([[exception name] hasPrefix:@"Oolite"])
			{
				[self handleOoliteException:exception];
			}
			else
			{
#ifndef NDEBUG
				if (update_stage_param != nil)  update_stage = [NSString stringWithFormat:update_stage, update_stage_param];
#endif
				OOLog(kOOLogException, @"***** Exception during [%@] in [Universe update:] : %@ : %@ *****", update_stage, [exception name], [exception reason]);
				@throw exception;
			}
		}
		
		// dispose of the non-mutable copy and everything it references neatly
		update_stage = @"clean up";
		OOLog(@"universe.profile.update", @"%@", update_stage);
		for (i = 0; i < ent_count; i++)
		{
			[my_entities[i] release];	// explicitly release each one
		}
		/* Garbage collection is going to result in a significant
		 * pause when it happens. Doing it here is better than doing
		 * it in the middle of the update when it might slow a
		 * function into the timelimiter through no fault of its
		 * own. JS_MaybeGC will only run a GC when it's
		 * necessary. Merely checking is not significant in terms of
		 * time. - CIM: 4/8/2013
		 */
		update_stage = @"JS Garbage Collection";
		OOLog(@"universe.profile.update", @"%@", update_stage); 
#ifndef NDEBUG
		JSContext *context = OOJSAcquireContext(); 
		uint32 gcbytes1 = JS_GetGCParameter(JS_GetRuntime(context),JSGC_BYTES);
		OOJSRelinquishContext(context);
#endif
		[[OOJavaScriptEngine sharedEngine] garbageCollectionOpportunity:NO];
#ifndef NDEBUG
		context = OOJSAcquireContext(); 
		uint32 gcbytes2 = JS_GetGCParameter(JS_GetRuntime(context),JSGC_BYTES);
		OOJSRelinquishContext(context);
		if (gcbytes2 < gcbytes1)
		{
			OOLog(@"universe.profile.jsgc",@"Unplanned JS Garbage Collection from %d to %d",gcbytes1,gcbytes2);
		}
#endif


	}
	else
	{
		// always perform player's dead updates: allows deferred JS resets.
		if ([PLAYER status] == STATUS_DEAD)  [PLAYER update:delta_t];
	}
	
	[entitiesDeadThisUpdate autorelease];
	entitiesDeadThisUpdate = nil;
	entitiesDeadThisUpdate = [[NSMutableSet alloc] initWithCapacity:n_entities];
	
#if NEW_PLANETS
	[self prunePreloadingPlanetMaterials];
#endif

	OOLog(@"universe.profile.update",@"Update complete");
}


#ifndef NDEBUG
- (double) timeAccelerationFactor
{
	return timeAccelerationFactor;
}


- (void) setTimeAccelerationFactor:(double)newTimeAccelerationFactor
{
	if (newTimeAccelerationFactor < TIME_ACCELERATION_FACTOR_MIN || newTimeAccelerationFactor > TIME_ACCELERATION_FACTOR_MAX)
	{
		newTimeAccelerationFactor = TIME_ACCELERATION_FACTOR_DEFAULT;
	}
	timeAccelerationFactor = newTimeAccelerationFactor;
}
#else
- (double) timeAccelerationFactor
{
	return 1.0;
}


- (void) setTimeAccelerationFactor:(double)newTimeAccelerationFactor
{
}
#endif


- (void) filterSortedLists
{
	/*
	Eric, 17-10-2010: raised the area to be not filtered out, from the combined collision size to 2x this size.
	This allows this filtered list to be used also for proximity_alert and not only for collisions. Before the
	proximity_alert could only trigger when already very near a collision. To late for ships to react.
	This does raise the number of entities in the collision chain with as result that the number of pairs to compair
	becomes significant larger. However, almost all of these extra pairs are dealt with by a simple distance check.
	I currently see no noticeable negative effect while playing, but this change might still give some trouble I missed.
	*/
	Entity	*e0, *next, *prev;
	OOHPScalar start, finish, next_start, next_finish, prev_start, prev_finish;
	
	// using the z_list - set or clear collisionTestFilter and clear collision_chain
	e0 = z_list_start;
	while (e0)
	{
		e0->collisionTestFilter = [e0 canCollide]?0:3;
		e0->collision_chain = nil;
		e0 = e0->z_next;
	}
	// done.
	
	/* We need to check the lists in both ascending and descending order
	 * to catch some cases with interposition of entities. We set cTF =
	 * 1 on the way up, and |= 2 on the way down. Therefore it's only 3
	 * at the end of the list if it was caught both ways on the same
	 * list. - CIM: 7/11/2012 */

	// start with the z_list
	e0 = z_list_start;
	while (e0)
	{
		// here we are either at the start of the list or just past a gap
		start = e0->position.z - 2.0f * e0->collision_radius;
		finish = start + 4.0f * e0->collision_radius;
		next = e0->z_next;
		while ((next)&&(next->collisionTestFilter == 3))	// next has been eliminated from the list of possible colliders - so skip it
			next = next->z_next;
		if (next)
		{
			next_start = next->position.z - 2.0f * next->collision_radius;
			if (next_start < finish)
			{
				// e0 and next overlap
				while ((next)&&(next_start < finish))
				{
					// skip forward to the next gap or the end of the list
					next_finish = next_start + 4.0f * next->collision_radius;
					if (next_finish > finish)
						finish = next_finish;
					e0 = next;
					next = e0->z_next;
					while ((next)&&(next->collisionTestFilter==3))	// next has been eliminated - so skip it
						next = next->z_next;
					if (next)
						next_start = next->position.z - 2.0f * next->collision_radius;
				}
				// now either (next == nil) or (next_start >= finish)-which would imply a gap!
			}
			else
			{
				// e0 is a singleton
				e0->collisionTestFilter = 1;
			}
		}
		else // (next == nil)
		{
			// at the end of the list so e0 is a singleton
			e0->collisionTestFilter = 1;
		}
		e0 = next;
	}
	// list filtered upwards, now filter downwards
	// e0 currently = end of z list
	while (e0)
	{
		// here we are either at the start of the list or just past a gap
		start = e0->position.z + 2.0f * e0->collision_radius;
		finish = start - 4.0f * e0->collision_radius;
		prev = e0->z_previous;
		while ((prev)&&(prev->collisionTestFilter == 3))	// next has been eliminated from the list of possible colliders - so skip it
			prev = prev->z_previous;
		if (prev)
		{
			prev_start = prev->position.z + 2.0f * prev->collision_radius;
			if (prev_start > finish)
			{
				// e0 and next overlap
				while ((prev)&&(prev_start > finish))
				{
					// skip forward to the next gap or the end of the list
					prev_finish = prev_start - 4.0f * prev->collision_radius;
					if (prev_finish < finish)
						finish = prev_finish;
					e0 = prev;
					prev = e0->z_previous;
					while ((prev)&&(prev->collisionTestFilter==3))	// next has been eliminated - so skip it
						prev = prev->z_previous;
					if (prev)
						prev_start = prev->position.z + 2.0f * prev->collision_radius;
				}
				// now either (prev == nil) or (prev_start <= finish)-which would imply a gap!
			}
			else
			{
				// e0 is a singleton
				e0->collisionTestFilter |= 2;
			}
		}
		else // (prev == nil)
		{
			// at the end of the list so e0 is a singleton
			e0->collisionTestFilter |= 2;
		}
		e0 = prev;
	}
	// done! list filtered
	
	// then with the y_list, z_list singletons now create more gaps..
	e0 = y_list_start;
	while (e0)
	{
		// here we are either at the start of the list or just past a gap
		start = e0->position.y - 2.0f * e0->collision_radius;
		finish = start + 4.0f * e0->collision_radius;
		next = e0->y_next;
		while ((next)&&(next->collisionTestFilter==3))	// next has been eliminated from the list of possible colliders - so skip it
			next = next->y_next;
		if (next)
		{
			
			next_start = next->position.y - 2.0f * next->collision_radius;
			if (next_start < finish)
			{
				// e0 and next overlap
				while ((next)&&(next_start < finish))
				{
					// skip forward to the next gap or the end of the list
					next_finish = next_start + 4.0f * next->collision_radius;
					if (next_finish > finish)
						finish = next_finish;
					e0 = next;
					next = e0->y_next;
					while ((next)&&(next->collisionTestFilter==3))	// next has been eliminated - so skip it
						next = next->y_next;
					if (next)
						next_start = next->position.y - 2.0f * next->collision_radius;
				}
				// now either (next == nil) or (next_start >= finish)-which would imply a gap!
			}
			else
			{
				// e0 is a singleton
				e0->collisionTestFilter = 1;
			}
		}
		else // (next == nil)
		{
			// at the end of the list so e0 is a singleton
			e0->collisionTestFilter = 1;
		}
		e0 = next;
	}
	// list filtered upwards, now filter downwards
	// e0 currently = end of y list
	while (e0)
	{
		// here we are either at the start of the list or just past a gap
		start = e0->position.y + 2.0f * e0->collision_radius;
		finish = start - 4.0f * e0->collision_radius;
		prev = e0->y_previous;
		while ((prev)&&(prev->collisionTestFilter == 3))	// next has been eliminated from the list of possible colliders - so skip it
			prev = prev->y_previous;
		if (prev)
		{
			prev_start = prev->position.y + 2.0f * prev->collision_radius;
			if (prev_start > finish)
			{
				// e0 and next overlap
				while ((prev)&&(prev_start > finish))
				{
					// skip forward to the next gap or the end of the list
					prev_finish = prev_start - 4.0f * prev->collision_radius;
					if (prev_finish < finish)
						finish = prev_finish;
					e0 = prev;
					prev = e0->y_previous;
					while ((prev)&&(prev->collisionTestFilter==3))	// next has been eliminated - so skip it
						prev = prev->y_previous;
					if (prev)
						prev_start = prev->position.y + 2.0f * prev->collision_radius;
				}
				// now either (prev == nil) or (prev_start <= finish)-which would imply a gap!
			}
			else
			{
				// e0 is a singleton
				e0->collisionTestFilter |= 2;
			}
		}
		else // (prev == nil)
		{
			// at the end of the list so e0 is a singleton
			e0->collisionTestFilter |= 2;
		}
		e0 = prev;
	}
	// done! list filtered
	
	// finish with the x_list
	e0 = x_list_start;
	while (e0)
	{
		// here we are either at the start of the list or just past a gap
		start = e0->position.x - 2.0f * e0->collision_radius;
		finish = start + 4.0f * e0->collision_radius;
		next = e0->x_next;
		while ((next)&&(next->collisionTestFilter==3))	// next has been eliminated from the list of possible colliders - so skip it
			next = next->x_next;
		if (next)
		{
			next_start = next->position.x - 2.0f * next->collision_radius;
			if (next_start < finish)
			{
				// e0 and next overlap
				while ((next)&&(next_start < finish))
				{
					// skip forward to the next gap or the end of the list
					next_finish = next_start + 4.0f * next->collision_radius;
					if (next_finish > finish)
						finish = next_finish;
					e0 = next;
					next = e0->x_next;
					while ((next)&&(next->collisionTestFilter==3))	// next has been eliminated - so skip it
						next = next->x_next;
					if (next)
						next_start = next->position.x - 2.0f * next->collision_radius;
				}
				// now either (next == nil) or (next_start >= finish)-which would imply a gap!
			}
			else
			{
				// e0 is a singleton
				e0->collisionTestFilter = 1;
			}
		}
		else // (next == nil)
		{
			// at the end of the list so e0 is a singleton
			e0->collisionTestFilter = 1;
		}
		e0 = next;
	}
	// list filtered upwards, now filter downwards
	// e0 currently = end of x list
	while (e0)
	{
		// here we are either at the start of the list or just past a gap
		start = e0->position.x + 2.0f * e0->collision_radius;
		finish = start - 4.0f * e0->collision_radius;
		prev = e0->x_previous;
		while ((prev)&&(prev->collisionTestFilter == 3))	// next has been eliminated from the list of possible colliders - so skip it
			prev = prev->x_previous;
		if (prev)
		{
			prev_start = prev->position.x + 2.0f * prev->collision_radius;
			if (prev_start > finish)
			{
				// e0 and next overlap
				while ((prev)&&(prev_start > finish))
				{
					// skip forward to the next gap or the end of the list
					prev_finish = prev_start - 4.0f * prev->collision_radius;
					if (prev_finish < finish)
						finish = prev_finish;
					e0 = prev;
					prev = e0->x_previous;
					while ((prev)&&(prev->collisionTestFilter==3))	// next has been eliminated - so skip it
						prev = prev->x_previous;
					if (prev)
						prev_start = prev->position.x + 2.0f * prev->collision_radius;
				}
				// now either (prev == nil) or (prev_start <= finish)-which would imply a gap!
			}
			else
			{
				// e0 is a singleton
				e0->collisionTestFilter |= 2;
			}
		}
		else // (prev == nil)
		{
			// at the end of the list so e0 is a singleton
			e0->collisionTestFilter |= 2;
		}
		e0 = prev;
	}
	// done! list filtered
	
	// repeat the y_list - so gaps from the x_list influence singletons
	e0 = y_list_start;
	while (e0)
	{
		// here we are either at the start of the list or just past a gap
		start = e0->position.y - 2.0f * e0->collision_radius;
		finish = start + 4.0f * e0->collision_radius;
		next = e0->y_next;
		while ((next)&&(next->collisionTestFilter==3))	// next has been eliminated from the list of possible colliders - so skip it
			next = next->y_next;
		if (next)
		{
			next_start = next->position.y - 2.0f * next->collision_radius;
			if (next_start < finish)
			{
				// e0 and next overlap
				while ((next)&&(next_start < finish))
				{
					// skip forward to the next gap or the end of the list
					next_finish = next_start + 4.0f * next->collision_radius;
					if (next_finish > finish)
						finish = next_finish;
					e0 = next;
					next = e0->y_next;
					while ((next)&&(next->collisionTestFilter==3))	// next has been eliminated - so skip it
						next = next->y_next;
					if (next)
						next_start = next->position.y - 2.0f * next->collision_radius;
				}
				// now either (next == nil) or (next_start >= finish)-which would imply a gap!
			}
			else
			{
				// e0 is a singleton
				e0->collisionTestFilter = 1;
			}
		}
		else // (next == nil)
		{
			// at the end of the list so e0 is a singleton
			e0->collisionTestFilter = 1;
		}
		e0 = next;
	}
	// e0 currently = end of y list
	while (e0)
	{
		// here we are either at the start of the list or just past a gap
		start = e0->position.y + 2.0f * e0->collision_radius;
		finish = start - 4.0f * e0->collision_radius;
		prev = e0->y_previous;
		while ((prev)&&(prev->collisionTestFilter == 3))	// next has been eliminated from the list of possible colliders - so skip it
			prev = prev->y_previous;
		if (prev)
		{
			prev_start = prev->position.y + 2.0f * prev->collision_radius;
			if (prev_start > finish)
			{
				// e0 and next overlap
				while ((prev)&&(prev_start > finish))
				{
					// skip forward to the next gap or the end of the list
					prev_finish = prev_start - 4.0f * prev->collision_radius;
					if (prev_finish < finish)
						finish = prev_finish;
					e0 = prev;
					prev = e0->y_previous;
					while ((prev)&&(prev->collisionTestFilter==3))	// next has been eliminated - so skip it
						prev = prev->y_previous;
					if (prev)
						prev_start = prev->position.y + 2.0f * prev->collision_radius;
				}
				// now either (prev == nil) or (prev_start <= finish)-which would imply a gap!
			}
			else
			{
				// e0 is a singleton
				e0->collisionTestFilter |= 2;
			}
		}
		else // (prev == nil)
		{
			// at the end of the list so e0 is a singleton
			e0->collisionTestFilter |= 2;
		}
		e0 = prev;
	}
	// done! list filtered
	
	// finally, repeat the z_list - this time building collision chains...
	e0 = z_list_start;
	while (e0)
	{
		// here we are either at the start of the list or just past a gap
		start = e0->position.z - 2.0f * e0->collision_radius;
		finish = start + 4.0f * e0->collision_radius;
		next = e0->z_next;
		while ((next)&&(next->collisionTestFilter==3))	// next has been eliminated from the list of possible colliders - so skip it
			next = next->z_next;
		if (next)
		{
			next_start = next->position.z - 2.0f * next->collision_radius;
			if (next_start < finish)
			{
				// e0 and next overlap
				while ((next)&&(next_start < finish))
				{
					// chain e0 to next in collision
					e0->collision_chain = next;
					// skip forward to the next gap or the end of the list
					next_finish = next_start + 4.0f * next->collision_radius;
					if (next_finish > finish)
						finish = next_finish;
					e0 = next;
					next = e0->z_next;
					while ((next)&&(next->collisionTestFilter==3))	// next has been eliminated - so skip it
						next = next->z_next;
					if (next)
						next_start = next->position.z - 2.0f * next->collision_radius;
				}
				// now either (next == nil) or (next_start >= finish)-which would imply a gap!
				e0->collision_chain = nil;	// end the collision chain
			}
			else
			{
				// e0 is a singleton
				e0->collisionTestFilter = 1;
			}
		}
		else // (next == nil)
		{
			// at the end of the list so e0 is a singleton
			e0->collisionTestFilter = 1;
		}
		e0 = next;
	}
	// e0 currently = end of z list
	while (e0)
	{
		// here we are either at the start of the list or just past a gap
		start = e0->position.z + 2.0f * e0->collision_radius;
		finish = start - 4.0f * e0->collision_radius;
		prev = e0->z_previous;
		while ((prev)&&(prev->collisionTestFilter == 3))	// next has been eliminated from the list of possible colliders - so skip it
			prev = prev->z_previous;
		if (prev)
		{
			prev_start = prev->position.z + 2.0f * prev->collision_radius;
			if (prev_start > finish)
			{
				// e0 and next overlap
				while ((prev)&&(prev_start > finish))
				{
					// e0 probably already in collision chain at this point, but if it
					// isn't we have to insert it
					if (prev->collision_chain != e0)
					{
						if (prev->collision_chain == nil)
						{
							// easy, just add it onto the start of the chain
							prev->collision_chain = e0;
						}
						else
						{
							/* not nil and not e0 shouldn't be possible, I think.
							 * if it is, that implies that e0->collision_chain is nil, though
							 * so: */
							if (e0->collision_chain == nil)
							{
								e0->collision_chain = prev->collision_chain;
								prev->collision_chain = e0;
							}
							else
							{
								/* This shouldn't happen... If it does, we accept
								 * missing collision checks and move on */
								OOLog(@"general.error.inconsistentState",@"Unexpected state in collision chain builder prev=%@, prev->c=%@, e0=%@, e0->c=%@",prev,prev->collision_chain,e0,e0->collision_chain);
							}
						}
					}
					// skip forward to the next gap or the end of the list
					prev_finish = prev_start - 4.0f * prev->collision_radius;
					if (prev_finish < finish)
						finish = prev_finish;
					e0 = prev;
					prev = e0->z_previous;
					while ((prev)&&(prev->collisionTestFilter==3))	// next has been eliminated - so skip it
						prev = prev->z_previous;
					if (prev)
						prev_start = prev->position.z + 2.0f * prev->collision_radius;
				}
				// now either (prev == nil) or (prev_start <= finish)-which would imply a gap!

				// all the collision chains are already terminated somewhere
				// at this point so no need to set e0->collision_chain = nil
			}
			else
			{
				// e0 is a singleton
				e0->collisionTestFilter |= 2;
			}
		}
		else // (prev == nil)
		{
			// at the end of the list so e0 is a singleton
			e0->collisionTestFilter |= 2;
		}
		e0 = prev;
	}
	// done! list filtered
}


- (void) setGalaxySeed:(Random_Seed) gal_seed
{
	[self setGalaxySeed:gal_seed andReinit:NO];
}


- (void) setGalaxySeed:(Random_Seed) gal_seed andReinit:(BOOL) forced
{
	int						i;
	Random_Seed				g_seed = gal_seed;
	NSAutoreleasePool		*pool = nil;
	
	if (!equal_seeds(galaxy_seed, gal_seed) || forced) {
		galaxy_seed = gal_seed;
		
		// systems
		for (i = 0; i < 256; i++)
		{
			pool = [[NSAutoreleasePool alloc] init];
			
			systems[i] = g_seed;
			if (system_names[i])	[system_names[i] release];
			system_names[i] = [[self getSystemName:g_seed] retain];
			rotate_seed(&g_seed);
			rotate_seed(&g_seed);
			rotate_seed(&g_seed);
			rotate_seed(&g_seed);
			
			[pool release];
		}
	}
}


- (void) setSystemTo:(Random_Seed) s_seed
{
	NSDictionary	*systemData;
	PlayerEntity	*player = PLAYER;
	OOEconomyID		economy;
	
	[self setGalaxySeed: [player galaxy_seed]];
	
	system_seed = s_seed;
	target_system_seed = s_seed;
	
	systemData = [self generateSystemData:target_system_seed];
	economy = [systemData  oo_unsignedCharForKey:KEY_ECONOMY];
	
	[self generateEconomicDataWithEconomy:economy andRandomFactor:[player random_factor] & 0xff];
}


- (Random_Seed) systemSeed
{
	return system_seed;
}


- (Random_Seed) systemSeedForSystemNumber:(OOSystemID)n
{
	return systems[(unsigned)n & 0xFF];
}


- (Random_Seed) systemSeedForSystemName:(NSString *)sysname
{
	int i;
	NSString *pname = [[sysname lowercaseString] capitalizedString];
	for (i = 0; i < 256; i++)
	{
		if ([pname isEqualToString:[self getSystemName: systems[i]]])
			return systems[i];
	}
	
	return kNilRandomSeed;
}


- (OOSystemID) systemIDForSystemSeed:(Random_Seed)seed
{
	int i;
	for (i = 0; i < 256; i++)
	{
		if (equal_seeds(systems[i], seed))  return i;
	}
	
	return -1;
}


- (OOSystemID) currentSystemID
{
	return [self systemIDForSystemSeed:[self systemSeed]];
}


- (NSDictionary *) descriptions
{
	if (_descriptions == nil)
	{
		// Load internal descriptions.plist for use in early init, OXP verifier etc.
		// It will be replaced by merged version later if running the game normally.
		_descriptions = [NSDictionary dictionaryWithContentsOfFile:[[[ResourceManager builtInPath]
																	 stringByAppendingPathComponent:@"Config"]
																	stringByAppendingPathComponent:@"descriptions.plist"]];
		
		[self verifyDescriptions];
	}
	return _descriptions;
}


static void VerifyDesc(NSString *key, id desc);


static void VerifyDescString(NSString *key, NSString *desc)
{
	if ([desc rangeOfString:@"%n"].location != NSNotFound)
	{
		OOLog(@"descriptions.verify.percentN", @"***** FATAL: descriptions.plist entry \"%@\" contains the dangerous control sequence %%n.", key);
		exit(EXIT_FAILURE);
	}
}


static void VerifyDescArray(NSString *key, NSArray *desc)
{
	id subDesc = nil;
	foreach (subDesc, desc)
	{
		VerifyDesc(key, subDesc);
	}
}


static void VerifyDesc(NSString *key, id desc)
{
	if ([desc isKindOfClass:[NSString class]])
	{
		VerifyDescString(key, desc);
	}
	else if ([desc isKindOfClass:[NSArray class]])
	{
		VerifyDescArray(key, desc);
	}
	else if ([desc isKindOfClass:[NSNumber class]])
	{
		// No verification needed.
	}
	else
	{
		OOLogERR(@"descriptions.verify.badType", @"***** FATAL: descriptions.plist entry for \"%@\" is neither a string nor an array.", key);
		exit(EXIT_FAILURE);
	}
}


- (void) verifyDescriptions
{
	/*
		Ensure that no descriptions.plist entries contain the %n format code,
		which can be used to smash the stack and potentially call arbitrary
		functions.
		
		%n is deliberately not supported in Foundation/CoreFoundation under
		Mac OS X, but unfortunately GNUstep implements it.
		-- Ahruman 2011-05-05
	*/
	
	NSDictionary *descriptions = [self descriptions];
	NSString *key = nil;
	foreachkey (key, descriptions)
	{
		VerifyDesc(key, [descriptions objectForKey:key]);
	}
}


- (void) loadDescriptions
{
	[_descriptions autorelease];
	_descriptions = [[ResourceManager dictionaryFromFilesNamed:@"descriptions.plist" inFolder:@"Config" andMerge:YES] retain];
	[self verifyDescriptions];
}


- (NSDictionary *) characters
{
	return characters;
}


- (NSDictionary *) missiontext
{
	return missiontext;
}


- (NSString *)descriptionForKey:(NSString *)key
{
	return [self chooseStringForKey:key inDictionary:[self descriptions]];
}


- (NSString *)descriptionForArrayKey:(NSString *)key index:(unsigned)index
{
	NSArray *array = [[self descriptions] oo_arrayForKey:key];
	if ([array count] <= index)  return nil;	// Catches nil array
	return [array objectAtIndex:index];
}


- (BOOL) descriptionBooleanForKey:(NSString *)key
{
	return [[self descriptions] oo_boolForKey:key];
}


- (NSString *) keyForPlanetOverridesForSystemSeed:(Random_Seed) s_seed inGalaxySeed:(Random_Seed) g_seed
{
	Random_Seed g0 = {0x4a, 0x5a, 0x48, 0x02, 0x53, 0xb7};
	// do not call this function from g_seed != galaxy_seed
	// isn't called this way at the moment, and for what it's used for
	// there's no need to. - CIM 25/11/12
	int pnum = [self systemIDForSystemSeed:s_seed];
	int gnum = 0;
	while (((g_seed.a != g0.a)||(g_seed.b != g0.b)||(g_seed.c != g0.c)||(g_seed.d != g0.d)||(g_seed.e != g0.e)||(g_seed.f != g0.f))&&(gnum < 8))
	{
		gnum++;
		g0.a = rotate_byte_left(g0.a);
		g0.b = rotate_byte_left(g0.b);
		g0.c = rotate_byte_left(g0.c);
		g0.d = rotate_byte_left(g0.d);
		g0.e = rotate_byte_left(g0.e);
		g0.f = rotate_byte_left(g0.f);
	}
	return [NSString stringWithFormat:@"%d %d", gnum, pnum];
}


- (NSString *) keyForInterstellarOverridesForSystemSeeds:(Random_Seed) s_seed1 :(Random_Seed) s_seed2 inGalaxySeed:(Random_Seed) g_seed
{
	Random_Seed g0 = {0x4a, 0x5a, 0x48, 0x02, 0x53, 0xb7};
	int pnum1 = [self findSystemNumberAtCoords:NSMakePoint(s_seed1.d,s_seed1.b) withGalaxySeed:g_seed];
	int pnum2 = [self findSystemNumberAtCoords:NSMakePoint(s_seed2.d,s_seed2.b) withGalaxySeed:g_seed];
	if (pnum1 > pnum2)
	{	// swap them
		int t = pnum1;	pnum1 = pnum2;	pnum2 = t;
	}
	int gnum = 0;
	while (((g_seed.a != g0.a)||(g_seed.b != g0.b)||(g_seed.c != g0.c)||(g_seed.d != g0.d)||(g_seed.e != g0.e)||(g_seed.f != g0.f))&&(gnum < 8))
	{
		gnum++;
		g0.a = rotate_byte_left(g0.a);
		g0.b = rotate_byte_left(g0.b);
		g0.c = rotate_byte_left(g0.c);
		g0.d = rotate_byte_left(g0.d);
		g0.e = rotate_byte_left(g0.e);
		g0.f = rotate_byte_left(g0.f);
	}
	return [NSString stringWithFormat:@"interstellar: %d %d %d", gnum, pnum1, pnum2];
}


- (NSDictionary *) generateSystemData:(Random_Seed) s_seed
{
	return [self generateSystemData:s_seed useCache:YES];
}


static NSMutableDictionary	*sCachedSystemData = nil;


- (NSDictionary *) generateSystemData:(Random_Seed) s_seed useCache:(BOOL) useCache
{
	OOJS_PROFILE_ENTER
	
	/* This now caches data for all 256 systems if
	 * possible. System data is moderately expensive to generate
	 * and changes only rarely. */
	if (!useCache)
	{
		[self resetSystemDataCache];
	}
	else
	{
		
	}
	if (sCachedSystemData == nil)
	{
		sCachedSystemData = [[NSMutableDictionary alloc] initWithCapacity:256];
	}
	NSMutableDictionary *systemdata = [sCachedSystemData objectForKey:[NSNumber numberWithInt:[self systemIDForSystemSeed:s_seed]]];
	RNG_Seed saved_seed = currentRandomSeed();
	if (systemdata == nil)
	{
		systemdata = [[NSMutableDictionary alloc] init];
	
		OOGovernmentID government = (s_seed.c / 8) & 7;
	
		OOEconomyID economy = s_seed.b & 7;
		if (government < 2)
			economy = economy | 2;
	
		OOTechLevelID techlevel = (economy ^ 7) + (s_seed.d & 3) + (government / 2) + (government & 1);
	
		unsigned population = (unsigned)(techlevel * 4) + government + economy + 1;
	
		unsigned productivity = ((economy ^ 7) + 3) * (government + 4) * population * 8;
	
		unsigned radius = (((s_seed.f & 15) + 11) * 256) + s_seed.d;
	
		NSString *name = [self generateSystemName:s_seed];
		NSString *inhabitant = [self generateSystemInhabitants:s_seed plural:NO];
		NSString *inhabitants = [self generateSystemInhabitants:s_seed plural:YES];
		NSString *description = OOGenerateSystemDescription(s_seed, name);	// FIXME: is it necessary to generate this here? Can't we just generate a description if it's nil the second time (down below)? -- Ahrumn 2012-10-05
	
		NSString *override_key = [self keyForPlanetOverridesForSystemSeed:s_seed inGalaxySeed:galaxy_seed];
	
		[systemdata oo_setUnsignedInteger:government	forKey:KEY_GOVERNMENT];
		[systemdata oo_setUnsignedInteger:economy		forKey:KEY_ECONOMY];
		[systemdata oo_setUnsignedInteger:techlevel		forKey:KEY_TECHLEVEL];
		[systemdata oo_setUnsignedInteger:population	forKey:KEY_POPULATION];
		[systemdata oo_setUnsignedInteger:productivity	forKey:KEY_PRODUCTIVITY];
		[systemdata oo_setUnsignedInteger:radius		forKey:KEY_RADIUS];
		[systemdata setObject:name						forKey:KEY_NAME];
		[systemdata setObject:inhabitant				forKey:KEY_INHABITANT];
		[systemdata setObject:inhabitants				forKey:KEY_INHABITANTS];
		[systemdata setObject:description				forKey:KEY_DESCRIPTION];
	
		// check at this point
		// for scripted overrides for this planet
		NSDictionary *overrides = nil;
	
		overrides = [planetInfo oo_dictionaryForKey:PLANETINFO_UNIVERSAL_KEY];
		if (overrides != nil)  [systemdata addEntriesFromDictionary:overrides];
		overrides = [planetInfo oo_dictionaryForKey:override_key];
		if (overrides != nil)  [systemdata addEntriesFromDictionary:overrides];
		overrides = [localPlanetInfoOverrides oo_dictionaryForKey:override_key];
		if (overrides != nil)  [systemdata addEntriesFromDictionary:overrides];
	
		// check if the description needs to be recalculated
		if ([description isEqual:[systemdata oo_stringForKey:KEY_DESCRIPTION]] && ![name isEqual:[systemdata oo_stringForKey:KEY_NAME]])
		{
			[systemdata setObject:OOGenerateSystemDescription(s_seed, [systemdata oo_stringForKey:KEY_NAME]) forKey:KEY_DESCRIPTION];
		}

		[sCachedSystemData setObject:[systemdata autorelease] forKey:[NSNumber numberWithInt:[self systemIDForSystemSeed:s_seed]]];
	}
	if (useCache) setRandomSeed(saved_seed);
	
	return [[systemdata copy] autorelease];
	
	OOJS_PROFILE_EXIT
}


- (NSDictionary *) currentSystemData
{
	OOJS_PROFILE_ENTER
	
	if (![self inInterstellarSpace])
	{
		return [self generateSystemData:system_seed];
	}
	else
	{
		static NSDictionary *interstellarDict = nil;
		if (interstellarDict == nil)
		{
			NSString *interstellarName = DESC(@"interstellar-space");
			NSString *notApplicable = DESC(@"not-applicable");
			NSNumber *minusOne = [NSNumber numberWithInt:-1];
			NSNumber *zero = [NSNumber numberWithInt:0];
			interstellarDict = [[NSDictionary alloc] initWithObjectsAndKeys:
								interstellarName, KEY_NAME,
								minusOne, KEY_GOVERNMENT,
								minusOne, KEY_ECONOMY,
								minusOne, KEY_TECHLEVEL,
								zero, KEY_POPULATION,
								zero, KEY_PRODUCTIVITY,
								zero, KEY_RADIUS,
								notApplicable, KEY_INHABITANTS,
								notApplicable, KEY_DESCRIPTION,
								nil];
		}
		
		return interstellarDict;
	}
	
	OOJS_PROFILE_EXIT
}


- (BOOL) inInterstellarSpace
{
	return [self sun] == nil;
}


- (void)setObject:(id)object forKey:(NSString *)key forPlanetKey:(NSString *)planetKey
{
	NSMutableDictionary	*overrideDict = nil;
	
	if (key == nil || planetKey == nil)  return;
	
	overrideDict = [localPlanetInfoOverrides objectForKey:planetKey];
	if (EXPECT_NOT(overrideDict != nil && ![overrideDict isKindOfClass:[NSMutableDictionary class]]))
	{
		/*	
			LocalPlanetInfoOverrides sometimes contained immutable
			dictionaries. Changes to -setLocalPlanetInfoOverrides
			should have fixed it, but...
			-- Abridged note. Originally from Ahruman 20070729
		*/
		if ([overrideDict isKindOfClass:[NSDictionary class]])
		{
			overrideDict = [[overrideDict mutableCopy] autorelease];
		}
		else
		{
			overrideDict = nil;
		}
	}
	
	if (overrideDict == nil)  overrideDict = [NSMutableDictionary dictionary];
	
	if (object != nil)
	{
		[overrideDict setObject:object forKey:key];
	}
	else
	{
		[overrideDict removeObjectForKey:key];
	}
	
	if ([overrideDict count] > 0)
	{
		[localPlanetInfoOverrides setObject:overrideDict forKey:planetKey];
	}
	else
	{
		[localPlanetInfoOverrides removeObjectForKey:planetKey];
	}
}


- (void) setSystemDataKey:(NSString *)key value:(NSObject *)object
{
	NSString *overrideKey = [self keyForPlanetOverridesForSystemSeed:system_seed inGalaxySeed:galaxy_seed];
	[self setObject:object forKey:key forPlanetKey:overrideKey];
}


- (void) setSystemDataForGalaxy:(OOGalaxyID)gnum planet:(OOSystemID)pnum key:(NSString *)key value:(id)object
{
	static BOOL sysdataLocked = NO;
	if (sysdataLocked)
	{
		OOLogERR(@"script.error", @"System properties cannot be set during 'systemInformationChanged' events to avoid infinite loops.");
		return;
	}

	// trying to set  unsettable properties?  
	if ([key isEqualToString:KEY_RADIUS]) // buggy if we allow this key to be set
	{
		OOLogERR(@"script.error", @"System property '%@' cannot be set.",key);
		return;
	}
	
	NSString	*overrideKey = [NSString stringWithFormat:@"%u %u", gnum, pnum];
	Random_Seed s_seed = [self systemSeedForSystemNumber:pnum];
	BOOL sameGalaxy = (gnum == [PLAYER currentGalaxyID]);
	BOOL sameSystem = (sameGalaxy && equal_seeds([self systemSeed], s_seed));
	NSDictionary *sysInfo = nil;
	
	// short range map fix
	[gui refreshStarChart];
	
	// long range map fixes
	if ([key isEqualToString:KEY_NAME])
	{	
		object=(id)[[(NSString *)object lowercaseString] capitalizedString];
		if(sameGalaxy)
		{
			if (system_names[pnum]) [system_names[pnum] release];
			system_names[pnum] = [(NSString *)object retain];
		}
	}
	else if ([key isEqualToString:@"sun_radius"])
	{
		if ([object doubleValue] < 1000.0 || [object doubleValue] > 1000000.0 ) 
		{
			object = ([object doubleValue] < 1000.0 ? (id)@"1000.0" : (id)@"1000000.0"); // works!
		}
	}
	else if ([key hasPrefix:@"corona_"])
	{
		object = (id)[NSString stringWithFormat:@"%f",OOClamp_0_1_f([object floatValue])];
	}
	
	[self setObject:object forKey:key forPlanetKey:overrideKey];
	
	if (sameGalaxy) // refresh the current systemData cache!
		sysInfo=[self generateSystemData:system_seed useCache:NO]; // needed if sameSystem
	
	// Apply changes that can be effective immediately, issue warning if they can't be changed just now
	if (sameSystem)
	{
		OOSunEntity* the_sun = [self sun];
		if ([key isEqualToString:KEY_ECONOMY])
		{	
			if([self station]) [[self station] initialiseLocalMarketWithRandomFactor:[PLAYER random_factor]];
		}
		else if ([key isEqualToString:KEY_TECHLEVEL])
		{	
			if([self station]){
				[[self station] setEquivalentTechLevel:[object intValue]];
				[[self station] setLocalShipyard:[self shipsForSaleForSystem:system_seed
								withTL:[object intValue] atTime:[PLAYER clockTime]]];
			}
		}
		else if ([key isEqualToString:@"sun_color"] || [key isEqualToString:@"star_count_multiplier"] ||
				[key isEqualToString:@"nebula_count_multiplier"] || [key hasPrefix:@"sky_"])
		{
			SkyEntity	*the_sky = nil;
			int i;
			
			for (i = n_entities - 1; i > 0; i--)
				if ((sortedEntities[i]) && ([sortedEntities[i] isKindOfClass:[SkyEntity class]]))
					the_sky = (SkyEntity*)sortedEntities[i];
			
			if (the_sky != nil)
			{
				[the_sky changeProperty:key withDictionary:sysInfo];
				
				if ([key isEqualToString:@"sun_color"])
				{
					OOColor *color=[[the_sky skyColor] blendedColorWithFraction:0.5 ofColor:[OOColor whiteColor]];
					if (the_sun != nil)
					{
						[the_sun setSunColor:color];
						[the_sun getDiffuseComponents:sun_diffuse];
						[the_sun getSpecularComponents:sun_specular];
					}
					for (i = n_entities - 1; i > 0; i--)
						if ((sortedEntities[i]) && ([sortedEntities[i] isKindOfClass:[DustEntity class]]))
							[(DustEntity*)sortedEntities[i] setDustColor:color];
				}
			}
		}
		else if (the_sun != nil && ([key hasPrefix:@"sun_"] || [key hasPrefix:@"corona_"]))
		{
			[the_sun changeSunProperty:key withDictionary:sysInfo];
		}
		else if ([key isEqualToString:@"texture"])
		{
			[[self planet] setUpPlanetFromTexture:(NSString *)object];
		}
		else if ([key isEqualToString:@"texture_hsb_color"])
		{
			[[self planet] setUpPlanetFromTexture: [[self planet] textureFileName]];
		}
	}
	
	sysdataLocked = YES;
	[PLAYER doScriptEvent:OOJSID("systemInformationChanged") withArguments:[NSArray arrayWithObjects:[NSNumber numberWithInt:gnum],[NSNumber numberWithInt:pnum],key,object,nil]];
	sysdataLocked = NO;

}


- (NSDictionary *) generateSystemDataForGalaxy:(OOGalaxyID)gnum planet:(OOSystemID)pnum
{
	Random_Seed s_seed = [self systemSeedForSystemNumber:pnum];
	BOOL sameGalaxy = (gnum == [PLAYER currentGalaxyID]);
	
	if (sameGalaxy)
	{
		return [self generateSystemData:s_seed useCache:YES];
	}
	else
	{
		return nil;
	}
}


- (NSArray *) systemDataKeysForGalaxy:(OOGalaxyID)gnum planet:(OOSystemID)pnum
{
	return [[self generateSystemDataForGalaxy:gnum planet:pnum] allKeys];
}


- (id) systemDataForGalaxy:(OOGalaxyID)gnum planet:(OOSystemID)pnum key:(NSString *)key
{
	NSDictionary *data = [self generateSystemDataForGalaxy:gnum planet:pnum];
	
	if (data != nil)
	{
		// Same galaxy.
		return [data objectForKey:key];
	}
	else
	{
		// TODO: a safe way to retrieve other galaxies system data?
		
		// Retrieving data from other galaxies requires temporarily altering the present galaxy_seed.
		// Altering the galaxy seed might affect system populators, markets etc. Since each
		// galaxy is supposed to be a totally separate entity from the others, the usefulness
		// of reading other galaxies data is actually pretty marginal. Kaks 20090812
		
		return @"_OTHER_GALAXY_";
	}
}


- (NSString *) getSystemName:(Random_Seed)s_seed
{
	return [[self generateSystemData:s_seed] oo_stringForKey:KEY_NAME];
}


- (OOGovernmentID) getSystemGovernment:(Random_Seed)s_seed
{
	return [[self generateSystemData:s_seed] oo_unsignedCharForKey:KEY_GOVERNMENT];
}


- (NSString *) getSystemInhabitants:(Random_Seed) s_seed
{
	return [self getSystemInhabitants:s_seed plural:YES];
}


- (NSString *) getSystemInhabitants:(Random_Seed) s_seed plural:(BOOL)plural
{	
	NSString *ret = nil;
	if (!plural)
		ret = [[self generateSystemData:s_seed] oo_stringForKey:KEY_INHABITANT];
	if (ret != nil) // the singular form might be absent.
		return ret;
	else
		return [[self generateSystemData:s_seed] oo_stringForKey:KEY_INHABITANTS];
}


- (NSString *) generateSystemName:(Random_Seed) s_seed
{
	int i;
	
	NSString			*digrams = [self descriptionForKey:@"digrams"];
	NSString			*apostrophe = [self descriptionForKey:@"digrams-apostrophe"];
	NSMutableString		*name = [NSMutableString string];
	int size = 4;
	
	if ((s_seed.a & 0x40) == 0)
		size = 3;
	
	for (i = 0; i < size; i++)
	{
		NSString *c1, *c2;
		int x = s_seed.f & 0x1f;
		if (x != 0)
		{
			x += 12;	x *= 2;
			c1 = [digrams substringWithRange:NSMakeRange(x,1)];
			c2 = [digrams substringWithRange:NSMakeRange(x+1,1)];
			[name appendString:c1];
			if (![c2 isEqual:apostrophe])		[name appendString:c2];
		}
		rotate_seed(&s_seed);
	}
	
	return [name capitalizedString];
}


- (NSString *) generatePhoneticSystemName:(Random_Seed) s_seed
{
	int i;
#if OOLITE_MAC_OS_X
	NSString			*phonograms = [self descriptionForKey:@"phonograms"];
#else
	NSString			*phonograms = [self descriptionForKey:@"espkphonos"];
#endif
	NSMutableString		*name = [NSMutableString string];
	int size = 4;
	
	if ((s_seed.a & 0x40) == 0)
		size = 3;
	
	for (i = 0; i < size; i++)
	{
		NSString *c1;
		int x = s_seed.f & 0x1f;
		if (x != 0)
		{
			x += 12;	x *= 4;
			c1 = [phonograms substringWithRange:NSMakeRange(x,4)];
			[name appendString:c1];
		}
		rotate_seed(&s_seed);
	}
	
#if OOLITE_MAC_OS_X
	return [NSString stringWithFormat:@"[[inpt PHON]]%@[[inpt TEXT]]", name];
#else
	return [NSString stringWithFormat:@"[[%@]]", name];
#endif
}


- (NSString *) generateSystemInhabitants:(Random_Seed)s_seed plural:(BOOL)plural
{
	NSMutableString	*inhabitants = [NSMutableString string];
	NSArray			*inhabitantStrings = nil;
	//i18n: Some languages have different plural and singular forms for adjectives.
	BOOL			singularAdjectivesExist = NO;
	
	// getSystemInhabitants is now used in most cases, to enable plist overrides.
	if (s_seed.e < 127)
	{
		[inhabitants appendString:DESC_PLURAL(@"human-colonial-description", plural ? -1 : 1)];
	}
	else
	{
		inhabitantStrings = [[self descriptions] oo_arrayForKey:KEY_INHABITANTS];
		// The first 5 arrays in 'inhabitants' are the standard ones, anything else below is language specific
		// and will refer to the different singular forms for the particular language we are translating to.
		// If this is the case, three more arrays are expected, raising the total count of subarrays to 8.
		singularAdjectivesExist = [inhabitantStrings count] == 8;
		
		int inhab = (s_seed.f / 4) & 7;
		if (inhab < 3)
			[inhabitants appendString:[[inhabitantStrings oo_arrayAtIndex:plural ?
								0 : singularAdjectivesExist ? 5 : 0] oo_stringAtIndex:inhab]];
		
		inhab = s_seed.f / 32;
		if (inhab < 6)
		{
			[inhabitants appendString:@" "];
			[inhabitants appendString:[[inhabitantStrings oo_arrayAtIndex:plural ?
								1 : singularAdjectivesExist ? 6 : 1] oo_stringAtIndex:inhab]];
		}
		
		inhab = (s_seed.d ^ s_seed.b) & 7;
		if (inhab < 6)
		{
			[inhabitants appendString:@" "];
			[inhabitants appendString:[[inhabitantStrings oo_arrayAtIndex:plural ?
								2 : singularAdjectivesExist ? 7 : 2] oo_stringAtIndex:inhab]];
		}
		
		inhab = (inhab + (s_seed.f & 3)) & 7;
		[inhabitants appendString:@" "];
		[inhabitants appendString:[[inhabitantStrings oo_arrayAtIndex:plural ? 4 : 3] oo_stringAtIndex:inhab]];
	}
	
	return [inhabitants stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];	
}


- (NSPoint) coordinatesForSystem:(Random_Seed)s_seed
{
	return NSMakePoint(s_seed.d, s_seed.b);
}


- (Random_Seed) findSystemFromName:(NSString *) sysName
{
	if (sysName == nil) return kNilRandomSeed;	// no match found!
	
	NSString 	*system_name = nil;
	NSString	*match = [sysName lowercaseString];
	int i;
	for (i = 0; i < 256; i++)
	{
		system_name = [system_names[i] lowercaseString];
		if ([system_name isEqualToString:match])
		{
			return systems[i];
		}
	}
	return kNilRandomSeed;	// no match found!
}


- (Random_Seed) findSystemAtCoords:(NSPoint) coords withGalaxySeed:(Random_Seed) gal_seed
{
	return systems[[self findSystemNumberAtCoords:coords withGalaxySeed:gal_seed]];
}


- (NSMutableArray *) nearbyDestinationsWithinRange:(double)range
{
	NSMutableArray *result = [NSMutableArray arrayWithCapacity:16];
	
	range = OOClamp_0_max_d(range, MAX_JUMP_RANGE); // limit to systems within 7LY
	NSPoint here = [PLAYER galaxy_coordinates];
	
	Random_Seed hereSeed = [self systemSeed];
	for (unsigned short i = 0; i < 256; i++)
	{
		Random_Seed system = systems[i];
		double dist = distanceBetweenPlanetPositions(here.x, here.y, system.d, system.b);
		if (dist <= range && (!equal_seeds(system, hereSeed) || [self inInterstellarSpace])) // if we are in interstellar space, it's OK to include the system we (mis)jumped from
		{
			[result addObject: [NSDictionary dictionaryWithObjectsAndKeys:
								StringFromRandomSeed(system), @"system_seed",
								[NSNumber numberWithDouble:dist], @"distance",
								[NSNumber numberWithInt:i], @"sysID",
								[[self generateSystemData:system] oo_stringForKey:@"sun_gone_nova" defaultValue:@"0"], @"nova",
								nil]];
		}
	}
	
	return result;
}


- (Random_Seed) findNeighbouringSystemToCoords:(NSPoint) coords withGalaxySeed:(Random_Seed) gal_seed
{
	if (!equal_seeds(gal_seed, galaxy_seed))
	{
		[self setGalaxySeed:gal_seed];
	}
	
	Random_Seed system = gal_seed;
	double distance;
	int n,i,j;
	double min_dist = 10000.0;
	
	// make list of connected systems
	BOOL connected[256];
	for (i = 0; i < 256; i++)
		connected[i] = NO;
	connected[0] = YES;			// system zero is always connected (true for galaxies 0..7)
	for (n = 0; n < 3; n++)		//repeat three times for surety
	{
		for (i = 0; i < 256; i++)   // flood fill out from system zero
		{
			for (j = 0; j < 256; j++)
			{
				double dist = distanceBetweenPlanetPositions(systems[i].d, systems[i].b, systems[j].d, systems[j].b);
				if (dist <= MAX_JUMP_RANGE)
				{
					connected[j] |= connected[i];
					connected[i] |= connected[j];
				}
			}
		}
	}
	
	for (i = 0; i < 256; i++)
	{
		distance = distanceBetweenPlanetPositions((int)coords.x, (int)coords.y, systems[i].d, systems[i].b);
		if ((connected[i])&&(distance < min_dist)&&(distance != 0.0))
		{
			min_dist = distance;
			system = systems[i];
		}
	}
	
	return system;
}


- (Random_Seed) findConnectedSystemAtCoords:(NSPoint) coords withGalaxySeed:(Random_Seed) gal_seed
{
	if (!equal_seeds(gal_seed, galaxy_seed))
		[self setGalaxySeed:gal_seed];
	
	Random_Seed system = gal_seed;
	double distance;
	int n,i,j;
	double min_dist = 10000.0;
	
	// make list of connected systems
	BOOL connected[256];
	for (i = 0; i < 256; i++)
		connected[i] = NO;
	connected[0] = YES;			// system zero is always connected (true for galaxies 0..7)
	for (n = 0; n < 3; n++)		//repeat three times for surety
	{
		for (i = 0; i < 256; i++)   // flood fill out from system zero
		{
			for (j = 0; j < 256; j++)
			{
				double dist = distanceBetweenPlanetPositions(systems[i].d, systems[i].b, systems[j].d, systems[j].b);
				if (dist <= MAX_JUMP_RANGE)
				{
					connected[j] |= connected[i];
					connected[i] |= connected[j];
				}
			}
		}
	}
	
	for (i = 0; i < 256; i++)
	{
		distance = distanceBetweenPlanetPositions((int)coords.x, (int)coords.y, systems[i].d, systems[i].b);
		if ((connected[i])&&(distance < min_dist))
		{
			min_dist = distance;
			system = systems[i];
		}
	}
	
	return system;
}


- (OOSystemID) findSystemNumberAtCoords:(NSPoint) coords withGalaxySeed:(Random_Seed) gal_seed
{
	if (!equal_seeds(gal_seed, galaxy_seed))
		[self setGalaxySeed:gal_seed];
	
	/*
		NOTE: this previously used NSNotFound as the default value, but
		returned an int, which would truncate on 64-bit systems. I assume
		no-one was using it in a context where the default value was returned.
		-- Ahruman 2012-08-25
	*/
	OOSystemID	system = kOOMinimumSystemID;
	unsigned	distance, dx, dy;
	unsigned	i;
	unsigned	min_dist = 10000;
	
	for (i = 0; i < 256; i++)
	{
		dx = abs(coords.x - systems[i].d);
		dy = abs(coords.y - systems[i].b);
		
		if (dx > dy)	distance = (dx + dx + dy) / 2;
		else			distance = (dx + dy + dy) / 2;
		
		if (distance < min_dist)
		{
			min_dist = distance;
			system = i;
		}
		
		if ((distance == min_dist)&&(coords.y > systems[i].b))	// with coincident systems choose only if ABOVE
		{
			system = i;
		}
	}
	return system;
}


- (NSPoint) findSystemCoordinatesWithPrefix:(NSString *) p_fix
{
	return [self findSystemCoordinatesWithPrefix:p_fix exactMatch:NO];
}


- (NSPoint) findSystemCoordinatesWithPrefix:(NSString *) p_fix exactMatch:(BOOL) exactMatch
{
	NSString 	*system_name = nil;
	NSPoint 	system_coords = NSMakePoint(-1.0,-1.0);
	int i;
	int result = -1;
	for (i = 0; i < 256; i++)
	{
		system_found[i] = NO;
		system_name = [system_names[i] lowercaseString];
		if ((exactMatch && [system_name isEqualToString:p_fix]) || (!exactMatch && [system_name hasPrefix:p_fix]))
		{
			system_found[i] = YES;
			if (result < 0)
			{
				system_coords.x = systems[i].d;
				system_coords.y = systems[i].b;
				result = i;
			}
		}
	}
	return system_coords;
}


- (BOOL*) systemsFound
{
	return (BOOL*)system_found;
}


- (NSString*)systemNameIndex:(OOSystemID)index
{
	return system_names[index & 255];
}


- (NSDictionary *) routeFromSystem:(OOSystemID) start toSystem:(OOSystemID) goal optimizedBy:(OORouteType) optimizeBy
{
	/*
	 time_cost = distance * distance
	 jump_cost = jumps * max_total_distance + distance = max_total_tistance + distance
	 
	 max_total_distance is 7 * 256
	 
	 max_time_cost = max_planets * max_time_cost = 256 * (7 * 7)
	 max_jump_cost = max_planets * max_jump_cost = 256 * (7 * 256 + 7)
	 */
	
	// no interstellar space for start and/or goal please
	if (start == -1 || goal == -1)  return nil;
	
#ifdef CACHE_ROUTE_FROM_SYSTEM_RESULTS
	
	static NSDictionary *c_route = nil;
	static OOSystemID c_start, c_goal;
	static OORouteType c_optimizeBy;
	
	if (c_route != nil && c_start == start && c_goal == goal && c_optimizeBy == optimizeBy)
	{
		return c_route;
	}
	
#endif
	
	unsigned i, j;
	
	if (start > 255 || goal > 255) return nil;
	
	NSArray *neighbours[256];
	for (i = 0; i < 256; i++)
	{
		neighbours[i] = [self neighboursToSystem:i];
	}
	
	RouteElement *cheapest[256] = {0};
	
	double maxCost = optimizeBy == OPTIMIZED_BY_TIME ? 256 * (7 * 7) : 256 * (7 * 256 + 7);
	
	NSMutableArray *curr = [NSMutableArray arrayWithCapacity:256];
	[curr addObject:cheapest[start] = [RouteElement elementWithLocation:start parent:-1 cost:0 distance:0 time:0]];
	
	NSMutableArray *next = [NSMutableArray arrayWithCapacity:256];
	while ([curr count] != 0)
	{
		for (i = 0; i < [curr count]; i++) {
			RouteElement *elemI = [curr objectAtIndex:i];
			NSArray *ns = neighbours[[elemI location]];
			for (j = 0; j < [ns count]; j++)
			{
				RouteElement *ce = cheapest[[elemI location]];
				OOSystemID n = [ns oo_intAtIndex:j];
				OOSystemID c = [ce location];
				
				double lastDistance = distanceBetweenPlanetPositions(systems[c].d, systems[c].b, systems[n].d, systems[n].b);
				double lastTime = lastDistance * lastDistance;
				
				double distance = [ce distance] + lastDistance;
				double time = [ce time] + lastTime;
				double cost = [ce cost] + (optimizeBy == OPTIMIZED_BY_TIME ? lastTime : 7 * 256 + lastDistance);
				
				if (cost < maxCost && (cheapest[n] == nil || [cheapest[n] cost] > cost)) {
					RouteElement *e = [RouteElement elementWithLocation:n parent:c cost:cost distance:distance time:time];
					cheapest[n] = e;
					[next addObject:e];
					
					if (n == goal && cost < maxCost)
						maxCost = cost;					
				}
			}
		}
		[curr setArray:next];
		[next removeAllObjects];
	}
	
	
	if (!cheapest[goal]) return nil;
	
	NSMutableArray *route = [NSMutableArray arrayWithCapacity:256];
	RouteElement *e = cheapest[goal];
	for (;;)
	{
		[route insertObject:[NSNumber numberWithInt:[e location]] atIndex:0];
		if ([e parent] == -1) break;
		e = cheapest[[e parent]];
	}
	
#ifdef CACHE_ROUTE_FROM_SYSTEM_RESULTS
	c_start = start;
	c_goal = goal;
	c_optimizeBy = optimizeBy;
	[c_route release];
	c_route = [[NSDictionary alloc] initWithObjectsAndKeys: route, @"route", [NSNumber numberWithDouble:[cheapest[goal] distance]], @"distance", nil];
	
	return c_route;
#else
	return [NSDictionary dictionaryWithObjectsAndKeys:
			route, @"route",
			[NSNumber numberWithDouble:[cheapest[goal] distance]], @"distance",
			[NSNumber numberWithDouble:[cheapest[goal] time]], @"time",
			nil];
#endif
}


- (NSArray *) neighboursToRandomSeed: (Random_Seed) seed
{
	if (equal_seeds(system_seed, seed) && closeSystems != nil) 
	{
		return closeSystems;
	}
	NSMutableArray *neighbours = [NSMutableArray arrayWithCapacity:32];
	double distance;
	OOSystemID i;
	for (i = 0; i < 256; i++)
	{
		distance = distanceBetweenPlanetPositions(seed.d, seed.b, systems[i].d, systems[i].b);
		if ((distance <= MAX_JUMP_RANGE) && !(equal_seeds(seed, systems[i])))
		{		
			if (distance < 0)
			{
				OOLogWARN(@"universe.findSystems.badDistance", @"DEBUG: Universe neighboursToRandomSeed: found a system pair with a negative distance (%f).", distance);
				//i guess its still in range, but skip as it makes no sense
				continue;
			}
			[neighbours addObject:[NSNumber numberWithInt:i]];
		}
	}
	if (equal_seeds(system_seed, seed))
	{
		[closeSystems release];
		closeSystems = [neighbours copy];
		return closeSystems;
	}
	return neighbours;
}


- (NSArray *) neighboursToSystem: (OOSystemID) system_number
{
	return [self neighboursToRandomSeed: systems[system_number]];
}


- (NSMutableDictionary *) localPlanetInfoOverrides
{
	return localPlanetInfoOverrides;
}


- (void) setLocalPlanetInfoOverrides:(NSDictionary *)dict
{
	NSEnumerator				*keyEnum = nil;
	NSString					*key = nil;
	id							value = nil;
	
	/*	Bug: localPlanetInfoOverrides contains immutable dictionaries, rather
		than mutable dictionaries.
		Analysis: when loading a saved game, localPlanetInfoOverrides is
		restored using setLocalPlanetInfoOverrides:. This was using
		-[NSMutableDictionary dictionaryWithDictionary:] to copy the immutable
		dictionary from the saved game. This is a shallow copy, however,
		creating a mutable dictionary of immutable dictionaries.
		Fix: explicitly make mutable copies of member dictionaries. (The
		contents of those dictionaries, in turn, can be immutable.)
	*/
	[localPlanetInfoOverrides release];
	
	localPlanetInfoOverrides = [[NSMutableDictionary alloc] initWithCapacity:[dict count]];
	
	for (keyEnum = [dict keyEnumerator]; (key = [keyEnum nextObject]); )
	{
		value = [dict objectForKey:key];
		if (value != nil)
		{
			value = [value mutableCopy];
			[localPlanetInfoOverrides setObject:value forKey:key];
			[value release];
		}
	}
}


/*
	Planet texture preloading.
	
	In order to hide the cost of synthesizing textures, we want to start
	rendering them asynchronously as soon as there's a hint they may be needed
	soon: when a system is selected on one of the charts, and when beginning a
	jump. However, it would be a Bad Idea™ to allow an arbitrary number of
	planets to be queued, since you can click on lots of systems quite
	quickly on the long-range chart.
	
	To rate-limit this, we track the materials that are being preloaded and
	only queue the ones for a new system if there are no more than two in the
	queue. (Currently, each system will have at most two materials, the main
	planet and the main planet's atmosphere, but it may be worth adding the
	ability to declare planets in planetinfo.plist instead of using scripts so
	that they can also benefit from preloading.)
	
	The preloading materials list is pruned before preloading, and also once
	per frame so textures can fall out of the regular cache.
	-- Ahruman 2009-12-19
	
	DISABLED due to crashes on some Windows systems. Textures generated here
	remain in the sRecentTextures cache when released, suggesting a retain
	imbalance somewhere. Cannot reproduce under Mac OS X. Needs further
	analysis before reenabling.
	http://www.aegidian.org/bb/viewtopic.php?f=3&t=12109
	-- Ahruman 2012-06-29
*/
- (void) preloadPlanetTexturesForSystem:(Random_Seed)seed
{
#if 0 // NEW_PLANETS
	[self prunePreloadingPlanetMaterials];
	
	if ([_preloadingPlanetMaterials count] < 3)
	{
		if (_preloadingPlanetMaterials == nil)  _preloadingPlanetMaterials = [[NSMutableArray alloc] initWithCapacity:4];
		
		OOPlanetEntity *planet = [[OOPlanetEntity alloc] initAsMainPlanetForSystemSeed:seed];
		[_preloadingPlanetMaterials addObject:[planet material]];
		
		// In some instances (retextured planets atm), the main planet might not have an atmosphere defined.
		// Trying to add nil to _preloadingPlanetMaterials will prematurely terminate the calling function.(!) --Kaks 20100107
		OOMaterial *atmo = [planet atmosphereMaterial];
		if (atmo != nil)  [_preloadingPlanetMaterials addObject:atmo];
		
		[planet release];
	}
#endif
}


- (NSDictionary *) planetInfo
{
	return planetInfo;
}


- (NSArray *) equipmentData
{
	return equipmentData;
}


- (NSDictionary *) commodityLists
{
	return commodityLists;
}


- (NSArray *) commodityData
{
	return commodityData;
}


- (BOOL) generateEconomicDataWithEconomy:(OOEconomyID) economy andRandomFactor:(int) random_factor
{
	[commodityData release];
	commodityData = [[self commodityDataForEconomy:economy andStation:[self station] andRandomFactor:random_factor] retain];
	return YES;
}


- (NSArray *) commodityDataForEconomy:(OOEconomyID) economy andStation:(StationEntity *)some_station andRandomFactor:(int) random_factor
{
	NSString		*marketName = nil;
	NSArray			*market = nil;
	NSMutableArray	*ourEconomy = nil;
	unsigned		i;
	
	// 2010.06.16 - Micha
	// There can be manual market overrides for the system and/or for the 
	// station.  If there are no overrides, or they can't be loaded, we fall
	// back to the stations' primary role and, failing that, use the default 
	// market.
	// "some_station" is nil when we set up space immediately after a witch
	// jump or when loading a game.  This probably needs refactoring.
	
	if (some_station == nil || some_station == [UNIVERSE  station])
	{
		marketName = [[self currentSystemData] oo_stringForKey:@"market"];
	}
	if (marketName == nil )
		marketName = [some_station marketOverrideName];
	if (marketName != nil )
	{
		market = [commodityLists oo_arrayForKey:marketName];
		if( market == nil )
		{
			OOLogWARN(@"universe.setup.badMarket", @"System or station specified undefined market '%@'.", marketName);
		}
	}
	if( market == nil && some_station != nil )
	{
		market = [commodityLists oo_arrayForKey:[some_station primaryRole]];
	}
	if( market == nil)
	{
		market = [commodityLists oo_arrayForKey:@"default"];
	}

	ourEconomy = [NSMutableArray arrayWithArray:market];
	
	for (i = 0; i < [ourEconomy count]; i++)
	{
		NSMutableArray *commodityInfo = [[ourEconomy oo_arrayAtIndex:i] mutableCopy];
		
		int base_price =			[commodityInfo oo_intAtIndex:MARKET_BASE_PRICE];
		int eco_adjust_price =		[commodityInfo oo_intAtIndex:MARKET_ECO_ADJUST_PRICE];
		int eco_adjust_quantity =	[commodityInfo oo_intAtIndex:MARKET_ECO_ADJUST_QUANTITY];
		int base_quantity =			[commodityInfo oo_intAtIndex:MARKET_BASE_QUANTITY];
		int mask_price =			[commodityInfo oo_intAtIndex:MARKET_MASK_PRICE];
		int mask_quantity =			[commodityInfo oo_intAtIndex:MARKET_MASK_QUANTITY];
		
		int price =		(base_price + (random_factor & mask_price) + (economy * eco_adjust_price)) & 255;
		int quantity =  (base_quantity + (random_factor & mask_quantity) - (economy * eco_adjust_quantity)) & 255;
		
		if (quantity > 127) quantity = 0;
		quantity &= 63;
		
		[commodityInfo replaceObjectAtIndex:MARKET_PRICE withObject:[NSNumber numberWithInt:price * 4]];
		[commodityInfo replaceObjectAtIndex:MARKET_QUANTITY withObject:[NSNumber numberWithInt:quantity]];
		
		[ourEconomy replaceObjectAtIndex:i withObject:[NSArray arrayWithArray:commodityInfo]];
		[commodityInfo release];	// release, done
	}
	
	return [NSArray arrayWithArray:ourEconomy];
}


- (NSString *) timeDescription:(double) interval
{
	double r_time = interval;
	NSString* result = @"";
	
	if (r_time > 86400)
	{
		int days = floor(r_time / 86400);
		r_time -= 86400 * days;
		result = [NSString stringWithFormat:@"%@ %d day%@", result, days, (days > 1) ? @"s" : @""];
	}
	if (r_time > 3600)
	{
		int hours = floor(r_time / 3600);
		r_time -= 3600 * hours;
		result = [NSString stringWithFormat:@"%@ %d hour%@", result, hours, (hours > 1) ? @"s" : @""];
	}
	if (r_time > 60)
	{
		int mins = floor(r_time / 60);
		r_time -= 60 * mins;
		result = [NSString stringWithFormat:@"%@ %d minute%@", result, mins, (mins > 1) ? @"s" : @""];
	}
	if (r_time > 0)
	{
		int secs = floor(r_time);
		result = [NSString stringWithFormat:@"%@ %d second%@", result, secs, (secs > 1) ? @"s" : @""];
	}
	return [result stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}


- (NSString *) shortTimeDescription:(double) interval
{
	double r_time = interval;
	NSString* result = @"";
	int parts = 0;
	
	if (interval <= 0.0)
		return DESC(@"contracts-no-time");
	
	if (r_time > 86400)
	{
		int days = floor(r_time / 86400);
		r_time -= 86400 * days;
		result = [NSString stringWithFormat:@"%@ %d %@", result, days, DESC_PLURAL(@"contracts-day-word", days)];
		parts++;
	}
	if (r_time > 3600)
	{
		int hours = floor(r_time / 3600);
		r_time -= 3600 * hours;
		result = [NSString stringWithFormat:@"%@ %d %@", result, hours, DESC_PLURAL(@"contracts-hour-word", hours)];
		parts++;
	}
	if (parts < 2 && r_time > 60)
	{
		int mins = floor(r_time / 60);
		r_time -= 60 * mins;
		result = [NSString stringWithFormat:@"%@ %d %@", result, mins, DESC_PLURAL(@"contracts-minute-word", mins)];
		parts++;
	}
	if (parts < 2 && r_time > 0)
	{
		int secs = floor(r_time);
		result = [NSString stringWithFormat:@"%@ %d %@", result, secs, DESC_PLURAL(@"contracts-second-word", secs)];
	}
	return [result stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}


- (void) makeSunSkimmer:(ShipEntity *) ship andSetAI:(BOOL)setAI
{
	if (setAI) [ship switchAITo:@"oolite-traderAI.js"];	// perfectly acceptable for both route 2 & 3
	[ship setFuel:(Ranrot()&31)];
	// slow ships need extra insulation or they will burn up when sunskimming. (Tested at biggest sun in G3: Aenqute)
	float minInsulation = 1000 / [ship maxFlightSpeed] + 1;
	if ([ship heatInsulation] < minInsulation) [ship setHeatInsulation:minInsulation];
}


- (Random_Seed) marketSeed
{
	Random_Seed		ret = system_seed;
	int random_factor = [PLAYER clockTime];
	
	// ship sold time is generated by ship_seed.a << 16 + ship_seed.b << 8 + ship_seed.c
	// added to (long)(current_time + 0x800000) & 0xffffffffff000000
	// market changes more or less every 97 days.
	random_factor = (random_factor >> 24) &0xff;
	
	// adjust basic seed by market random factor
	ret.f ^= random_factor;	// XOR back to front
	ret.e ^= ret.f;	// XOR
	ret.d ^= ret.e;	// XOR
	ret.c ^= ret.d;	// XOR
	ret.b ^= ret.c;	// XOR
	ret.a ^= ret.b;	// XOR
	
	return ret;
}


- (void) loadStationMarkets:(NSArray *)marketData
{
	if (marketData == nil)
	{
		return;
	}

	NSArray *stations = [self stations];
	StationEntity *station = nil;
	NSDictionary *savedMarket = nil;

	foreach (savedMarket, marketData)
	{
		HPVector pos = [savedMarket oo_hpvectorForKey:@"position"];
		foreach (station, stations)
		{
			// must be deterministic and secondary
			if ([station allowsSaving] && station != [UNIVERSE station])
			{
				// allow a km of drift just in case
				if (HPdistance2(pos,[station position]) < 1000000)
				{
					[station setLocalMarket:[savedMarket oo_arrayForKey:@"market"]];
					break;
				}
			}
		}
	}

}


- (NSArray *) getStationMarkets
{
	NSMutableArray *markets = [[NSMutableArray alloc] init];
	NSArray *stations = [self stations];

	StationEntity *station = nil;
	NSMutableDictionary *savedMarket = nil;

	NSArray *stationMarket = nil;

	foreach (station, stations)
	{
		// must be deterministic and secondary
		if ([station allowsSaving] && station != [UNIVERSE station])
		{
			stationMarket = [station localMarket];
			if (stationMarket != nil)
			{
				savedMarket = [NSMutableDictionary dictionaryWithCapacity:2];
				[savedMarket setObject:[station localMarket] forKey:@"market"];
				[savedMarket setObject:ArrayFromHPVector([station position]) forKey:@"position"];
				[markets addObject:savedMarket];
			}
		}
	}

	return [markets autorelease];
}


- (NSArray *) shipsForSaleForSystem:(Random_Seed)s_seed withTL:(OOTechLevelID)specialTL atTime:(OOTimeAbsolute)current_time
{
	Random_Seed ship_seed = [self marketSeed];
	
	NSMutableDictionary		*resultDictionary = [NSMutableDictionary dictionary];
	
	float					tech_price_boost = (ship_seed.a + ship_seed.b) / 256.0;
	unsigned				i;
	PlayerEntity			*player = PLAYER;
	OOShipRegistry			*registry = [OOShipRegistry sharedRegistry];
	RANROTSeed				personalitySeed = RanrotSeedFromRandomSeed(ship_seed);
	
	for (i = 0; i < 256; i++)
	{
		long long reference_time = 0x1000000 * floor(current_time / 0x1000000);
		
		long long c_time = ship_seed.a * 0x10000 + ship_seed.b * 0x100 + ship_seed.c;
		double ship_sold_time = reference_time + c_time;
		
		if (ship_sold_time < 0)
			ship_sold_time += 0x1000000;	// wraparound
		
		double days_until_sale = (ship_sold_time - current_time) / 86400.0;
		
		NSMutableArray	*keysForShips = [NSMutableArray arrayWithArray:[registry playerShipKeys]];
		unsigned		si;
		for (si = 0; si < [keysForShips count]; si++)
		{
			//eliminate any ships that fail a 'conditions test'
			NSString		*key = [keysForShips oo_stringAtIndex:si];
			NSDictionary	*dict = [registry shipyardInfoForKey:key];
			NSArray			*conditions = [dict oo_arrayForKey:@"conditions"];
			
			if (![player scriptTestConditions:conditions])
			{
				[keysForShips removeObjectAtIndex:si--];
			}
			NSString *condition_script = [dict oo_stringForKey:@"condition_script"];
			if (condition_script != nil)
			{
				OOJSScript *condScript = [self getConditionScript:condition_script];
				if (condScript != nil) // should always be non-nil, but just in case
				{
					JSContext			*context = OOJSAcquireContext();
					BOOL OK;
					JSBool allow_purchase;
					jsval result;
					jsval args[] = { OOJSValueFromNativeObject(context, key) };
			
					OOJSStartTimeLimiter();
					OK = [condScript callMethod:OOJSID("allowOfferShip")
												inContext:context
										withArguments:args count:sizeof args / sizeof *args
													 result:&result];
					OOJSStopTimeLimiter();

					if (OK) OK = JS_ValueToBoolean(context, result, &allow_purchase);
			
					OOJSRelinquishContext(context);

					if (OK && !allow_purchase)
					{
						/* if the script exists, the function exists, the function
						 * returns a bool, and that bool is false, block
						 * purchase. Otherwise allow it as default */
						[keysForShips removeObjectAtIndex:si--];
					}
				}
			}

		}
		
		NSDictionary	*systemInfo = [self generateSystemData:system_seed];
		OOTechLevelID	techlevel;
		if (specialTL != NSNotFound)  
		{
			//if we are passed a tech level use that
			techlevel = specialTL;
		}
		else
		{
			//otherwise use default for system
			techlevel = [systemInfo oo_unsignedIntForKey:KEY_TECHLEVEL];
		}
		unsigned		ship_index = (ship_seed.d * 0x100 + ship_seed.e) % [keysForShips count];
		NSString		*ship_key = [keysForShips oo_stringAtIndex:ship_index];
		NSDictionary	*ship_info = [registry shipyardInfoForKey:ship_key];
		OOTechLevelID	ship_techlevel = [ship_info oo_intForKey:KEY_TECHLEVEL];
		
		double chance = 1.0 - pow(1.0 - [ship_info oo_doubleForKey:KEY_CHANCE], MAX((OOTechLevelID)1, techlevel - ship_techlevel));
		
		// seed random number generator
		int super_rand1 = ship_seed.a * 0x10000 + ship_seed.c * 0x100 + ship_seed.e;
		int super_rand2 = ship_seed.b * 0x10000 + ship_seed.d * 0x100 + ship_seed.f;
		ranrot_srand(super_rand2);
		
		NSDictionary* ship_base_dict = nil;
		
		ship_base_dict = [[OOShipRegistry sharedRegistry] shipInfoForKey:ship_key];
		
		if ((days_until_sale > 0.0) && (days_until_sale < 30.0) && (ship_techlevel <= techlevel) && (randf() < chance) && (ship_base_dict != nil))
		{			
			NSMutableDictionary* ship_dict = [NSMutableDictionary dictionaryWithDictionary:ship_base_dict];
			NSMutableString* description = [NSMutableString stringWithCapacity:256];
			NSMutableString* short_description = [NSMutableString stringWithCapacity:256];
			NSString *shipName = [ship_dict oo_stringForKey:@"display_name" defaultValue:[ship_dict oo_stringForKey:KEY_NAME]];
			OOCreditsQuantity price = [ship_info oo_unsignedIntForKey:KEY_PRICE];
			OOCreditsQuantity base_price = price;
			NSMutableArray* extras = [NSMutableArray arrayWithArray:[[ship_info oo_dictionaryForKey:KEY_STANDARD_EQUIPMENT] oo_arrayForKey:KEY_EQUIPMENT_EXTRAS]];
			NSString* fwd_weapon_string = [[ship_info oo_dictionaryForKey:KEY_STANDARD_EQUIPMENT] oo_stringForKey:KEY_EQUIPMENT_FORWARD_WEAPON];
			NSString* aft_weapon_string = [[ship_info oo_dictionaryForKey:KEY_STANDARD_EQUIPMENT] oo_stringForKey:KEY_EQUIPMENT_AFT_WEAPON];
			
			NSMutableArray* options = [NSMutableArray arrayWithArray:[ship_info oo_arrayForKey:KEY_OPTIONAL_EQUIPMENT]];
			OOCargoQuantity max_cargo = [ship_dict oo_unsignedIntForKey:@"max_cargo"];
			
			// more info for potential purchasers - how to reveal this I'm not yet sure...
			//NSString* brochure_desc = [self brochureDescriptionWithDictionary: ship_dict standardEquipment: extras optionalEquipment: options];
			//NSLog(@"%@ Brochure description : \"%@\"", [ship_dict objectForKey:KEY_NAME], brochure_desc);
			
			[description appendFormat:@"%@:", shipName];
			[short_description appendFormat:@"%@:", shipName];
			
			OOWeaponFacingSet available_facings = [ship_info oo_unsignedIntForKey:KEY_WEAPON_FACINGS defaultValue:VALID_WEAPON_FACINGS] & VALID_WEAPON_FACINGS;

			OOWeaponType fwd_weapon = OOWeaponTypeFromEquipmentIdentifierSloppy(fwd_weapon_string);
			OOWeaponType aft_weapon = OOWeaponTypeFromEquipmentIdentifierSloppy(aft_weapon_string);
			//port and starboard weapons are not modified in the shipyard
			
			int passenger_berths = 0;
			BOOL customised = NO;
			BOOL weapon_customised = NO;
			BOOL other_weapon_added = NO;
			
			NSString *fwd_weapon_desc = nil;
			NSString *aft_weapon_desc = nil;
			
			NSString *short_extras_string = DESC(@"plus-@");
			NSString *passengerBerthLongDesc = nil;
			
			// for testing condition scripts
			ShipEntity *testship = [[ProxyPlayerEntity alloc] initWithKey:ship_key definition:ship_dict];
			// customise the ship (if chance = 1, then ship will get all possible add ons)
			while ((randf() < chance) && ([options count]))
			{
				chance *= chance;	//decrease the chance of a further customisation (unless it is 1, which might be a bug)
				int				option_index = Ranrot() % [options count];
				NSString		*equipmentKey = [options oo_stringAtIndex:option_index];
				OOEquipmentType	*item = [OOEquipmentType equipmentTypeWithIdentifier:equipmentKey];
				
				if (item != nil)
				{
					OOTechLevelID		eqTechLevel = [item techLevel];
					OOCreditsQuantity	eqPrice = [item price] / 10;	// all amounts are x/10 due to being represented in tenths of credits.
					NSString			*eqShortDesc = [item name];
					NSString			*eqLongDesc = [item descriptiveText];
					
					if ([item techLevel] > techlevel)
					{
						// Cap maximum tech level.
						eqTechLevel = MIN(eqTechLevel, 15U);
						
						// Higher tech items are rarer!
						if (randf() * (eqTechLevel - techlevel) < 1.0)
						{
							// All included equip has a 10% discount.
							eqPrice *= (tech_price_boost + eqTechLevel - techlevel) * 90 / 100;
						}
						else
							break;	// Bar this upgrade.
					}
					
					if ([item incompatibleEquipment] != nil && extras != nil)
					{
						NSEnumerator				*keyEnum = nil;
						id							key = nil;
						BOOL						incompatible = NO;
						
						for (keyEnum = [[item incompatibleEquipment] objectEnumerator]; (key = [keyEnum nextObject]); )
						{
							if ([extras containsObject:key])
							{
								[options removeObject:equipmentKey];
								incompatible = YES;
								break;
							}
						}
						if (incompatible) break;
						
						// make sure the incompatible equipment is not choosen later on.
						for (keyEnum = [[item incompatibleEquipment] objectEnumerator]; (key = [keyEnum nextObject]); )
						{
							if ([options containsObject:key])
							{
								[options removeObject:key]; 
							}
						}
					}
					
					/* Check condition scripts */
					NSString *condition_script = [item conditionScript];
					if (condition_script != nil)
					{
						OOJSScript *condScript = [self getConditionScript:condition_script];
						if (condScript != nil) // should always be non-nil, but just in case
						{
							JSContext			*JScontext = OOJSAcquireContext();
							BOOL OK;
							JSBool allow_addition;
							jsval result;
							jsval args[] = { OOJSValueFromNativeObject(JScontext, equipmentKey) , OOJSValueFromNativeObject(JScontext, testship) , OOJSValueFromNativeObject(JScontext, @"newShip")};
				
							OOJSStartTimeLimiter();
							OK = [condScript callMethod:OOJSID("allowAwardEquipment")
																inContext:JScontext
														withArguments:args count:sizeof args / sizeof *args
																	 result:&result];
							OOJSStopTimeLimiter();

							if (OK) OK = JS_ValueToBoolean(JScontext, result, &allow_addition);
				
							OOJSRelinquishContext(JScontext);

							if (OK && !allow_addition)
							{
								/* if the script exists, the function exists, the function
								 * returns a bool, and that bool is false, block
								 * addition. Otherwise allow it as default */
								break;
							}
						}
					}


					if ([item requiresEquipment] != nil && extras != nil)
					{
						NSEnumerator				*keyEnum = nil;
						id							key = nil;
						BOOL						missing = NO;
						
						for (keyEnum = [[item requiresEquipment] objectEnumerator]; (key = [keyEnum nextObject]); )
						{
							if (![extras containsObject:key])
							{
								missing = YES;
							}
						}
						if (missing) break;
					}
					
					if ([item requiresAnyEquipment] != nil && extras != nil)
					{
						NSEnumerator				*keyEnum = nil;
						id							key = nil;
						BOOL						missing = YES;
						
						for (keyEnum = [[item requiresAnyEquipment] objectEnumerator]; (key = [keyEnum nextObject]); )
						{
							if ([extras containsObject:key])
							{
								missing = NO;
							}
						}
						if (missing) break;
					}
					
					// Special case, NEU has to be compatible with EEU inside equipment.plist
					// but we can only have either one or the other on board.
					if ([equipmentKey isEqualTo:@"EQ_NAVAL_ENERGY_UNIT"])
					{
						if ([extras containsObject:@"EQ_ENERGY_UNIT"])
						{
							[options removeObject:equipmentKey];
							break;
						}
					}
					
					if ([equipmentKey hasPrefix:@"EQ_WEAPON"])
					{
						OOWeaponType new_weapon = OOWeaponTypeFromEquipmentIdentifierSloppy(equipmentKey);
						//fit best weapon forward
						if (available_facings & WEAPON_FACING_FORWARD && new_weapon > fwd_weapon)
						{
							//again remember to divide price by 10 to get credits from tenths of credit
							price -= [self getEquipmentPriceForKey:fwd_weapon_string] * 90 / 1000;	// 90% credits
							price += eqPrice;
							fwd_weapon_string = equipmentKey;
							fwd_weapon = new_weapon;
							[ship_dict setObject:fwd_weapon_string forKey:KEY_EQUIPMENT_FORWARD_WEAPON];
							weapon_customised = YES;
							fwd_weapon_desc = eqShortDesc;
						}
						else 
						{
							//if less good than current forward, try fitting is to rear
							if (available_facings & WEAPON_FACING_AFT && (!aft_weapon || new_weapon > aft_weapon))
							{
								price -= [self getEquipmentPriceForKey:aft_weapon_string] * 90 / 1000;	// 90% credits
								price += eqPrice;
								aft_weapon_string = equipmentKey;
								aft_weapon = new_weapon;
								[ship_dict setObject:aft_weapon_string forKey:KEY_EQUIPMENT_AFT_WEAPON];
								other_weapon_added = YES;
								aft_weapon_desc = eqShortDesc;
							}
							else 
							{
								[options removeObject:equipmentKey]; //dont try again
							}				
						}
					
					}
					else
					{
						if ([equipmentKey isEqualToString:@"EQ_PASSENGER_BERTH"])
						{
							if ((max_cargo >= PASSENGER_BERTH_SPACE) && (randf() < chance))
							{
								max_cargo -= PASSENGER_BERTH_SPACE;
								price += eqPrice;
								[extras addObject:equipmentKey];
								if (passenger_berths == 0)
								{
									// This will be needed to construct the description for passenger berths.
									// Note: use of lowercaseString is bad from an i18n perspective,
									// but the string is never actually shown anyway...
									passengerBerthLongDesc = [NSString stringWithFormat:@"%@", [eqLongDesc lowercaseString]];
								}
								passenger_berths++;
								customised = YES;
							}
							else
							{
								// remove the option if there's no space left
								[options removeObject:equipmentKey];
							}
						}
						else
						{
							price += eqPrice;
							[extras addObject:equipmentKey];
							if ([item isVisible])
							{
								[description appendFormat:DESC(@"extra-@-@-(long-description)"), eqShortDesc, [eqLongDesc lowercaseString]];
								[short_description appendFormat:short_extras_string, eqShortDesc];
								short_extras_string = @" %@.";
							}
							customised = YES;
							[options removeObject:equipmentKey]; //dont add twice
						}
					}
				}
				else
				{
					[options removeObject:equipmentKey];
				}
			} // end adding optional equipment
			[testship release];
			// i18n: Some languages require that no conversion to lower case string takes place.
			BOOL lowercaseIgnore = [[self descriptions] oo_boolForKey:@"lowercase_ignore"];
			
			if (passenger_berths)
			{
				NSString* npb = (passenger_berths > 1)? [NSString stringWithFormat:@"%d ", passenger_berths] : (id)@"";
				NSString* ppb = DESC_PLURAL(@"passenger-berth", passenger_berths);
				NSString* extraPassengerBerthsDescription = [NSString stringWithFormat:DESC(@"extra-@-@-(passenger-berths)"), npb, ppb];
				[description appendFormat:DESC(@"extra-@-@-@-(passenger-berth-long-description)"), npb, ppb, passengerBerthLongDesc];
				[short_description appendFormat:short_extras_string, extraPassengerBerthsDescription];
			}
			
			if (!customised)
			{
				[description appendString:DESC(@"shipyard-standard-customer-model")];
				[short_description appendString:DESC(@"shipyard-standard-customer-model")];
			}
			
			if (weapon_customised)
			{
				[description appendFormat:DESC(@"shipyard-forward-weapon-has-been-upgraded-to-a-@"), 
								(lowercaseIgnore ? fwd_weapon_desc : [fwd_weapon_desc lowercaseString])];
				[short_description appendFormat:DESC(@"shipyard-forward-weapon-upgraded-to-@"),
								(lowercaseIgnore ? fwd_weapon_desc : [fwd_weapon_desc lowercaseString])];
			}
			if (other_weapon_added)
			{
				[description appendFormat:@"aft %@", (lowercaseIgnore ? aft_weapon_desc : [aft_weapon_desc lowercaseString])];
			}
			if (price > base_price)
			{
				price = base_price + cunningFee(price - base_price, 0.05);
			}
			
			[description appendFormat:DESC(@"shipyard-selling-price-@"), OOIntCredits(price)];
			[short_description appendFormat:DESC(@"shipyard-price-@"), OOIntCredits(price)];
			
			NSString* ship_id = [NSString stringWithFormat:@"%06x-%06x", super_rand1, super_rand2];
			
			uint16_t personality = RanrotWithSeed(&personalitySeed) & ENTITY_PERSONALITY_MAX;
			
			NSDictionary* ship_info_dictionary = [NSDictionary dictionaryWithObjectsAndKeys:
				ship_id,							SHIPYARD_KEY_ID,
				ship_key,							SHIPYARD_KEY_SHIPDATA_KEY,
				ship_dict,							SHIPYARD_KEY_SHIP,
				description,						SHIPYARD_KEY_DESCRIPTION,
				short_description,					KEY_SHORT_DESCRIPTION,
				[NSNumber numberWithUnsignedLongLong:price], SHIPYARD_KEY_PRICE,
				extras,								KEY_EQUIPMENT_EXTRAS,
				[NSNumber numberWithUnsignedShort:personality], SHIPYARD_KEY_PERSONALITY,								  
				NULL];
			
			[resultDictionary setObject:ship_info_dictionary forKey:ship_id];	// should order them fairly randomly
		}
		
		// next contract
		rotate_seed(&ship_seed);
		rotate_seed(&ship_seed);
		rotate_seed(&ship_seed);
		rotate_seed(&ship_seed);
	}
	
	NSMutableArray *resultArray = [[[resultDictionary allValues] mutableCopy] autorelease];
	[resultArray sortUsingFunction:compareName context:NULL];
	
	// remove identically priced ships of the same name
	i = 1;
	
	while (i < [resultArray count])
	{
		if (compareName([resultArray objectAtIndex:i - 1], [resultArray objectAtIndex:i], nil) == NSOrderedSame )
		{
			[resultArray removeObjectAtIndex: i];
		}
		else
		{
			i++;
		}
	}
	
	return [NSArray arrayWithArray:resultArray];
}


static OOComparisonResult compareName(id dict1, id dict2, void *context)
{
	NSDictionary	*ship1 = [(NSDictionary *)dict1 oo_dictionaryForKey:SHIPYARD_KEY_SHIP];
	NSDictionary	*ship2 = [(NSDictionary *)dict2 oo_dictionaryForKey:SHIPYARD_KEY_SHIP];
	NSString		*name1 = [ship1 oo_stringForKey:KEY_NAME];
	NSString		*name2 = [ship2 oo_stringForKey:KEY_NAME];
	
	NSComparisonResult result = [name1 compare:name2];
	if (result != NSOrderedSame)
		return result;
	else
		return comparePrice(dict1, dict2, context);
}


static OOComparisonResult comparePrice(id dict1, id dict2, void *context)
{
	NSNumber		*price1 = [(NSDictionary *)dict1 objectForKey:SHIPYARD_KEY_PRICE];
	NSNumber		*price2 = [(NSDictionary *)dict2 objectForKey:SHIPYARD_KEY_PRICE];
	
	return [price1 compare:price2];
}


- (OOCreditsQuantity) tradeInValueForCommanderDictionary:(NSDictionary *)dict
{
	// get basic information about the craft
	OOCreditsQuantity	base_price = 0ULL;
	NSString			*ship_desc = [dict oo_stringForKey:@"ship_desc"];
	NSDictionary		*shipyard_info = [[OOShipRegistry sharedRegistry] shipyardInfoForKey:ship_desc];
	// This checks a rare, but possible case. If the ship for which we are trying to calculate a trade in value
	// does not have a shipyard dictionary entry, report it and set its base price to 0 -- Nikos 20090613.
	if (shipyard_info == nil)
	{
		OOLogERR(@"universe.tradeInValueForCommanderDictionary.valueCalculationError",
			@"Shipyard dictionary entry for ship %@ required for trade in value calculation, but does not exist. Setting ship value to 0.", ship_desc);
	}
	else
	{
		base_price = [shipyard_info oo_unsignedLongLongForKey:SHIPYARD_KEY_PRICE defaultValue:0ULL];
	}
	
	if(base_price == 0ULL) return base_price;
	
	OOCreditsQuantity	scrap_value = 351; // translates to 250 cr.
	
	OOWeaponType		ship_fwd_weapon = [dict oo_unsignedIntForKey:@"forward_weapon"];
	OOWeaponType		ship_aft_weapon = [dict oo_unsignedIntForKey:@"aft_weapon"];
	OOWeaponType		ship_port_weapon = [dict oo_unsignedIntForKey:@"port_weapon"];
	OOWeaponType		ship_starboard_weapon = [dict oo_unsignedIntForKey:@"starboard_weapon"];
	unsigned			ship_missiles = [dict oo_unsignedIntForKey:@"missiles"];
	unsigned			ship_max_passengers = [dict oo_unsignedIntForKey:@"max_passengers"];
	NSMutableArray		*ship_extra_equipment = [NSMutableArray arrayWithArray:[[dict oo_dictionaryForKey:@"extra_equipment"] allKeys]];
	
	NSDictionary		*basic_info = [shipyard_info oo_dictionaryForKey:KEY_STANDARD_EQUIPMENT];
	unsigned			base_missiles = [basic_info oo_unsignedIntForKey:KEY_EQUIPMENT_MISSILES];
	OOCreditsQuantity	base_missiles_value = base_missiles * [UNIVERSE getEquipmentPriceForKey:@"EQ_MISSILE"] / 10;
	NSString			*base_weapon_key = [basic_info oo_stringForKey:KEY_EQUIPMENT_FORWARD_WEAPON];
	OOCreditsQuantity	base_weapons_value = [UNIVERSE getEquipmentPriceForKey:base_weapon_key] / 10;
	NSMutableArray		*base_extra_equipment = [NSMutableArray arrayWithArray:[basic_info oo_arrayForKey:KEY_EQUIPMENT_EXTRAS]];
	NSString			*weapon_key = nil;
	
	// was aft_weapon defined as standard equipment ?
	base_weapon_key = [basic_info oo_stringForKey:KEY_EQUIPMENT_AFT_WEAPON defaultValue:nil];
	if (base_weapon_key != nil)
		base_weapons_value += [UNIVERSE getEquipmentPriceForKey:base_weapon_key] / 10;
	
	OOCreditsQuantity	ship_main_weapons_value = 0;
	OOCreditsQuantity	ship_other_weapons_value = 0;
	OOCreditsQuantity	ship_missiles_value = 0;

	// calculate the actual value for the missiles present on board.
	NSArray *missileRoles = [dict oo_arrayForKey:@"missile_roles"];
	if (missileRoles != nil)
	{
		unsigned i;
		for (i = 0; i < ship_missiles; i++)
		{
			NSString *missile_desc = [missileRoles oo_stringAtIndex:i];
			if (missile_desc != nil && ![missile_desc isEqualToString:@"NONE"])
			{
				ship_missiles_value += [UNIVERSE getEquipmentPriceForKey:missile_desc] / 10;
			}
		}
	}
	else
		ship_missiles_value = ship_missiles * [UNIVERSE getEquipmentPriceForKey:@"EQ_MISSILE"] / 10;
	
	// needs to be a signed value, we can then subtract from the base price, if less than standard equipment.
	long long extra_equipment_value = ship_max_passengers * [UNIVERSE getEquipmentPriceForKey:@"EQ_PASSENGER_BERTH"]/10;
	
	// add on missile values
	extra_equipment_value += ship_missiles_value - base_missiles_value;
	
	// work out weapon values
	if (ship_fwd_weapon)
	{
		weapon_key = OOEquipmentIdentifierFromWeaponType(ship_fwd_weapon);
		ship_main_weapons_value = [UNIVERSE getEquipmentPriceForKey:weapon_key] / 10;
	}
	if (ship_aft_weapon)
	{
		weapon_key = OOEquipmentIdentifierFromWeaponType(ship_aft_weapon);
		if (base_weapon_key != nil) // aft weapon was defined as a base weapon
		{
			ship_main_weapons_value += [UNIVERSE getEquipmentPriceForKey:weapon_key] / 10;	//take weapon downgrades into account
		}
		else
		{
			ship_other_weapons_value += [UNIVERSE getEquipmentPriceForKey:weapon_key] / 10;
		}
	}
	if (ship_port_weapon)
	{
		weapon_key = OOEquipmentIdentifierFromWeaponType(ship_port_weapon);
		ship_other_weapons_value += [UNIVERSE getEquipmentPriceForKey:weapon_key] / 10;
	}
	if (ship_starboard_weapon)
	{
		weapon_key = OOEquipmentIdentifierFromWeaponType(ship_starboard_weapon);
		ship_other_weapons_value += [UNIVERSE getEquipmentPriceForKey:weapon_key] / 10;
	}
	
	// add on extra weapons, take away the value of the base weapons
	extra_equipment_value += ship_other_weapons_value;
	extra_equipment_value += ship_main_weapons_value - base_weapons_value;
	
	NSInteger i;
	NSString *eq_key = nil;
	
	// shipyard.plist settings might have duplicate keys.
	// cull possible duplicates from inside base equipment
	for (i = [base_extra_equipment count]-1; i > 0;i--)
	{
		eq_key = [base_extra_equipment oo_stringAtIndex:i];
		if ([base_extra_equipment indexOfObject:eq_key inRange:NSMakeRange(0, i-1)] != NSNotFound)
								[base_extra_equipment removeObjectAtIndex:i];
	}
	
	// do we at least have the same equipment as a standard ship? 
	for (i = [base_extra_equipment count]-1; i >= 0; i--)
	{
		eq_key = [base_extra_equipment oo_stringAtIndex:i];
		if ([ship_extra_equipment containsObject:eq_key])
				[ship_extra_equipment removeObject:eq_key];
		else // if the ship has less equipment than standard, deduct the missing equipent's price
				extra_equipment_value -= ([UNIVERSE getEquipmentPriceForKey:eq_key] / 10);
	}
	
	// remove portable equipment from the totals
	OOEquipmentType	*item = nil;
	
	for (i = [ship_extra_equipment count]-1; i >= 0; i--)
	{
		eq_key = [ship_extra_equipment oo_stringAtIndex:i];
		item = [OOEquipmentType equipmentTypeWithIdentifier:eq_key];
		if ([item isPortableBetweenShips]) [ship_extra_equipment removeObjectAtIndex:i];
	}
	
	// add up what we've got left.
	for (i = [ship_extra_equipment count]-1; i >= 0; i--)
		extra_equipment_value += ([UNIVERSE getEquipmentPriceForKey:[ship_extra_equipment oo_stringAtIndex:i]] / 10);		
	
	// 10% discount for second hand value, steeper reduction if worse than standard.
	extra_equipment_value *= extra_equipment_value < 0 ? 1.4 : 0.9;
	
	// we'll return at least the scrap value
	// TODO: calculate scrap value based on the size of the ship.
	if ((long long)scrap_value > (long long)base_price + extra_equipment_value) return scrap_value;
	
	return base_price + extra_equipment_value;
}


- (NSString *) brochureDescriptionWithDictionary:(NSDictionary *)dict standardEquipment:(NSArray *)extras optionalEquipment:(NSArray *)options
{
	NSMutableArray	*mut_extras = [NSMutableArray arrayWithArray:extras];
	NSString		*allOptions = [options componentsJoinedByString:@" "];
	
	NSMutableString	*desc = [NSMutableString stringWithFormat:@"The %@.", [dict oo_stringForKey: KEY_NAME]];
	
	// cargo capacity and expansion
	OOCargoQuantity	max_cargo = [dict oo_unsignedIntForKey:@"max_cargo"];
	if (max_cargo)
	{
		OOCargoQuantity	extra_cargo = [dict oo_unsignedIntForKey:@"extra_cargo" defaultValue:15];
		[desc appendFormat:@" Cargo capacity %dt", max_cargo];
		BOOL canExpand = ([allOptions rangeOfString:@"EQ_CARGO_BAY"].location != NSNotFound);
		if (canExpand)
			[desc appendFormat:@" (expandable to %dt at most starports)", max_cargo + extra_cargo];
		[desc appendString:@"."];
	}
	
	// speed
	float top_speed = [dict oo_intForKey:@"max_flight_speed"];
	[desc appendFormat:@" Top speed %.3fLS.", 0.001 * top_speed];
	
	// passenger berths
	if ([mut_extras count])
	{
		unsigned n_berths = 0;
		unsigned i;
		for (i = 0; i < [mut_extras count]; i++)
		{
			NSString* item_key = [mut_extras oo_stringAtIndex:i];
			if ([item_key isEqual:@"EQ_PASSENGER_BERTH"])
			{
				n_berths++;
				[mut_extras removeObjectAtIndex:i--];
			}
		}
		if (n_berths)
		{
			if (n_berths == 1)
				[desc appendString:@" Includes luxury accomodation for a single passenger."];
			else
				[desc appendFormat:@" Includes luxury accomodation for %d passengers.", n_berths];
		}
	}
	
	// standard fittings
	if ([mut_extras count])
	{
		[desc appendString:@"\nComes with"];
		unsigned i, j;
		for (i = 0; i < [mut_extras count]; i++)
		{
			NSString* item_key = [mut_extras oo_stringAtIndex:i];
			NSString* item_desc = nil;
			for (j = 0; ((j < [equipmentData count])&&(!item_desc)) ; j++)
			{
				NSString *eq_type = [[equipmentData oo_arrayAtIndex:j] oo_stringAtIndex:EQUIPMENT_KEY_INDEX];
				if ([eq_type isEqual:item_key])
					item_desc = [[equipmentData oo_arrayAtIndex:j] oo_stringAtIndex:EQUIPMENT_SHORT_DESC_INDEX];
			}
			if (item_desc)
			{
				switch ([mut_extras count] - i)
				{
					case 1:
						[desc appendFormat:@" %@ fitted as standard.", item_desc];
						break;
					case 2:
						[desc appendFormat:@" %@ and", item_desc];
						break;
					default:
						[desc appendFormat:@" %@,", item_desc];
						break;
				}
			}
		}
	}
	
	// optional fittings
	if ([options count])
	{
		[desc appendString:@"\nCan additionally be outfitted with"];
		unsigned i, j;
		for (i = 0; i < [options count]; i++)
		{
			NSString* item_key = [options oo_stringAtIndex:i];
			NSString* item_desc = nil;
			for (j = 0; ((j < [equipmentData count])&&(!item_desc)) ; j++)
			{
				NSString *eq_type = [[equipmentData oo_arrayAtIndex:j] oo_stringAtIndex:EQUIPMENT_KEY_INDEX];
				if ([eq_type isEqual:item_key])
					item_desc = [[equipmentData oo_arrayAtIndex:j] oo_stringAtIndex:EQUIPMENT_SHORT_DESC_INDEX];
			}
			if (item_desc)
			{
				switch ([options count] - i)
				{
					case 1:
						[desc appendFormat:@" %@ at suitably equipped starports.", item_desc];
						break;
					case 2:
						[desc appendFormat:@" %@ and/or", item_desc];
						break;
					default:
						[desc appendFormat:@" %@,", item_desc];
						break;
				}
			}
		}
	}
	
	return desc;
}


- (HPVector) getWitchspaceExitPosition
{
	return [self getWitchspaceExitPositionResettingRandomSeed:NO];
}

- (HPVector) randomizeFromSeedAndGetWitchspaceExitPosition
{
	return [self getWitchspaceExitPositionResettingRandomSeed:YES];
}

- (HPVector) getWitchspaceExitPositionResettingRandomSeed:(BOOL)resetSeed
{
	if (resetSeed)
	{
		// Generate three random numbers so that anything implicitly relying on PRNG state is unchanged...
		seed_RNG_only_for_planet_description(system_seed);
		gen_rnd_number();
		gen_rnd_number();
		gen_rnd_number();
	}
	
	return kZeroHPVector;
}


- (Quaternion) getWitchspaceExitRotation
{
	// this should be fairly close to {0,0,0,1}
	Quaternion q_result;
	seed_RNG_only_for_planet_description(system_seed);
	
	q_result.x = (gen_rnd_number() - 128)/1024.0;
	q_result.y = (gen_rnd_number() - 128)/1024.0;
	q_result.z = (gen_rnd_number() - 128)/1024.0;
	q_result.w = 1.0;
	quaternion_normalize(&q_result);
	
	return q_result;
}

// FIXME: should use vector functions
- (HPVector) getSunSkimStartPositionForShip:(ShipEntity*) ship
{
	if (!ship)
	{
		OOLog(kOOLogParameterError, @"***** No ship set in Universe getSunSkimStartPositionForShip:");
		return kZeroHPVector;
	}
	OOSunEntity* the_sun = [self sun];
	// get vector from sun position to ship
	if (!the_sun)
	{
		OOLog(kOOLogInconsistentState, @"***** No sun set in Universe getSunSkimStartPositionForShip:");
		return kZeroHPVector;
	}
	HPVector v0 = the_sun->position;
	HPVector v1 = ship->position;
	v1.x -= v0.x;	v1.y -= v0.y;	v1.z -= v0.z;	// vector from sun to ship
	if (v1.x||v1.y||v1.z)
		v1 = HPvector_normal(v1);
	else
		v1.z = 1.0;
	double radius = SUN_SKIM_RADIUS_FACTOR * the_sun->collision_radius - 250.0; // 250 m inside the skim radius
	v1.x *= radius;	v1.y *= radius;	v1.z *= radius;
	v1.x += v0.x;	v1.y += v0.y;	v1.z += v0.z;
	
	return v1;
}

// FIXME: should use vector functions
- (HPVector) getSunSkimEndPositionForShip:(ShipEntity*) ship
{
	OOSunEntity* the_sun = [self sun];
	if (!ship)
	{
		OOLog(kOOLogParameterError, @"***** No ship set in Universe getSunSkimEndPositionForShip:");
		return kZeroHPVector;
	}
	// get vector from sun position to ship
	if (!the_sun)
	{
		OOLog(kOOLogInconsistentState, @"***** No sun set in Universe getSunSkimEndPositionForShip:");
		return kZeroHPVector;
	}
	HPVector v0 = the_sun->position;
	HPVector v1 = ship->position;
	v1.x -= v0.x;	v1.y -= v0.y;	v1.z -= v0.z;
	if (v1.x||v1.y||v1.z)
		v1 = HPvector_normal(v1);
	else
		v1.z = 1.0;
	HPVector v2 = make_HPvector(randf()-0.5, randf()-0.5, randf()-0.5);	// random vector
	if (v2.x||v2.y||v2.z)
		v2 = HPvector_normal(v2);
	else
		v2.x = 1.0;
	HPVector v3 = HPcross_product(v1, v2);	// random vector at 90 degrees to v1 and v2 (random Vector)
	if (v3.x||v3.y||v3.z)
		v3 = HPvector_normal(v3);
	else
		v3.y = 1.0;
	double radius = SUN_SKIM_RADIUS_FACTOR * the_sun->collision_radius - 250.0; // 250 m inside the skim radius
	v1.x *= radius;	v1.y *= radius;	v1.z *= radius;
	v1.x += v0.x;	v1.y += v0.y;	v1.z += v0.z;
	v1.x += 15000 * v3.x;	v1.y += 15000 * v3.y;	v1.z += 15000 * v3.z;	// point 15000m at a tangent to sun from v1
	v1.x -= v0.x;	v1.y -= v0.y;	v1.z -= v0.z;
	if (v1.x||v1.y||v1.z)
		v1 = HPvector_normal(v1);
	else
		v1.z = 1.0;
	v1.x *= radius;	v1.y *= radius;	v1.z *= radius;
	v1.x += v0.x;	v1.y += v0.y;	v1.z += v0.z;
	
	return v1;
}


- (NSArray *) listBeaconsWithCode:(NSString *)code
{
	NSMutableArray	*result = [NSMutableArray array];
	Entity <OOBeaconEntity>		*beacon = [self firstBeacon];
	
	while (beacon != nil)
	{
		NSString *beaconCode = [beacon beaconCode];
		if ([beaconCode rangeOfString:code options: NSCaseInsensitiveSearch].location != NSNotFound)
		{
			[result addObject:beacon];
		}
		beacon = [beacon nextBeacon];
	}
	
	return [result sortedArrayUsingSelector:@selector(compareBeaconCodeWith:)];
}


- (void) allShipsDoScriptEvent:(jsid)event andReactToAIMessage:(NSString *)message
{
	int i;
	int ent_count = n_entities;
	int ship_count = 0;
	ShipEntity* my_ships[ent_count];
	for (i = 0; i < ent_count; i++)
	{
		if (sortedEntities[i]->isShip)
		{
			my_ships[ship_count++] = [(ShipEntity *)sortedEntities[i] retain];	// retained
		}
	}
	
	for (i = 0; i < ship_count; i++)
	{
		ShipEntity* se = my_ships[i];
		[se doScriptEvent:event];
		if (message != nil)  [[se getAI] reactToMessage:message context:@"global message"];
		[se release]; //	released
	}
}

///////////////////////////////////////

- (GuiDisplayGen *) gui
{
	return gui;
}


- (GuiDisplayGen *) commLogGUI
{
	return comm_log_gui;
}


- (GuiDisplayGen *) messageGUI
{
	return message_gui;
}


- (void) clearGUIs
{
	[gui clear];
	[message_gui clear];
	[comm_log_gui clear];
	[comm_log_gui printLongText:DESC(@"communications-log-string")
						  align:GUI_ALIGN_CENTER color:[OOColor yellowColor] fadeTime:0 key:nil addToArray:nil];
}


- (void) resetCommsLogColor
{
	[comm_log_gui setTextColor:[OOColor whiteColor]];
}


- (void) setDisplayText:(BOOL) value
{
	displayGUI = !!value;
}


- (BOOL) displayGUI
{
	return displayGUI;
}


- (void) setDisplayFPS:(BOOL) value
{
	displayFPS = !!value;
}


- (BOOL) displayFPS
{
	return displayFPS;
}


- (void) setAutoSave:(BOOL) value
{
	autoSave = !!value;
	[[NSUserDefaults standardUserDefaults] setBool:autoSave forKey:@"autosave"];
}


- (BOOL) autoSave
{
	return autoSave;
}


- (void) setAutoSaveNow:(BOOL) value
{
	autoSaveNow = !!value;
}


- (BOOL) autoSaveNow
{
	return autoSaveNow;
}


- (void) setWireframeGraphics:(BOOL) value
{
	wireframeGraphics = !!value;
	[[NSUserDefaults standardUserDefaults] setBool:wireframeGraphics forKey:@"wireframe-graphics"];
}


- (BOOL) wireframeGraphics
{
	return wireframeGraphics;
}


- (void) setReducedDetail:(BOOL) value
{
	[self setReducedDetail:value transiently:NO];
}


- (void) setReducedDetail:(BOOL) value transiently:(BOOL)transiently
{
	reducedDetail = !!value;
	if (!transiently)  [[NSUserDefaults standardUserDefaults] setBool:reducedDetail forKey:@"reduced-detail-graphics"];
}


- (BOOL) reducedDetail
{
	return reducedDetail;
}


- (void) setShaderEffectsLevel:(OOShaderSetting)value
{
	[self setShaderEffectsLevel:value transiently:NO];
}


- (void) setShaderEffectsLevel:(OOShaderSetting)value transiently:(BOOL)transiently
{
	OOShaderSetting old = [self shaderEffectsLevel];
	[self setShaderEffectsLevelDirectly:value];
	OOShaderSetting new = [self shaderEffectsLevel];
	
	if (old != new)
	{
		OOLog(@"rendering.opengl.shader.mode", @"Shader mode set to %@.", OOStringFromShaderSetting(value));
		if (!transiently)  [[NSUserDefaults standardUserDefaults] setInteger:shaderEffectsLevel forKey:@"shader-mode"];
		
		[[OOGraphicsResetManager sharedManager] resetGraphicsState];
	}
}


- (OOShaderSetting) shaderEffectsLevel
{
	if (![[OOOpenGLExtensionManager sharedManager] shadersSupported])  return SHADERS_NOT_SUPPORTED;
	return shaderEffectsLevel;
}


- (BOOL) useShaders
{
	return [self shaderEffectsLevel] > SHADERS_OFF;
}


- (void) handleOoliteException:(NSException *)exception
{
	if (exception != nil)
	{
		if ([[exception name] isEqual:OOLITE_EXCEPTION_FATAL])
		{
			PlayerEntity *player = PLAYER;
			[player setStatus:STATUS_HANDLING_ERROR];
			
			OOLog(kOOLogException, @"***** Handling Fatal : %@ : %@ *****",[exception name], [exception reason]);
			NSString* exception_msg = [NSString stringWithFormat:@"Exception : %@ : %@ Please take a screenshot and/or press esc or Q to quit.", [exception name], [exception reason]];
			[self addMessage:exception_msg forCount:30.0];
			[[self gameController] setGamePaused:YES];
		}
		else
		{
			OOLog(kOOLogException, @"***** Handling Non-fatal : %@ : %@ *****",[exception name], [exception reason]);
		}
	}
}


- (GLfloat)airResistanceFactor
{
	return airResistanceFactor;
}


// speech routines
#if OOLITE_MAC_OS_X

- (void) startSpeakingString:(NSString *) text
{
	[speechSynthesizer startSpeakingString:[NSString stringWithFormat:@"[[volm %.3f]]%@", 0.3333333f * [OOSound masterVolume], text]];
}


- (void) stopSpeaking
{
	if ([speechSynthesizer respondsToSelector:@selector(stopSpeakingAtBoundary:)])
	{
		[speechSynthesizer stopSpeakingAtBoundary:NSSpeechWordBoundary];
	}
	else
	{
		[speechSynthesizer stopSpeaking];
	}
}


- (BOOL) isSpeaking
{
	return [speechSynthesizer isSpeaking];
}

#elif OOLITE_ESPEAK

- (void) startSpeakingString:(NSString *) text
{
	NSData *utf8 = [text dataUsingEncoding:NSUTF8StringEncoding];
	
	if (utf8 != nil)	// we have a valid UTF-8 string
	{
		const char *stringToSay = [text UTF8String];
		espeak_Synth(stringToSay, strlen(stringToSay) + 1 /* inc. NULL */, 0, POS_CHARACTER, 0, espeakCHARS_UTF8 | espeakPHONEMES | espeakENDPAUSE, NULL, NULL);
	}
}


- (void) stopSpeaking
{
	espeak_Cancel();
}


- (BOOL) isSpeaking
{
	return espeak_IsPlaying();
}


- (NSString *) voiceName:(unsigned int) index
{
	if (index >= espeak_voice_count)
		return @"-";
	return [NSString stringWithCString: espeak_voices[index]->name];
}


- (unsigned int) voiceNumber:(NSString *) name
{
	if (name == nil)
		return UINT_MAX;
	
	const char *const label = [name UTF8String];
	if (!label)
		return UINT_MAX;
	
	unsigned int index = -1;
	while (espeak_voices[++index] && strcmp (espeak_voices[index]->name, label))
			/**/;
	return (index < espeak_voice_count) ? index : UINT_MAX;
}


- (unsigned int) nextVoice:(unsigned int) index
{
	if (++index >= espeak_voice_count)
		index = 0;
	return index;
}


- (unsigned int) prevVoice:(unsigned int) index
{
	if (--index >= espeak_voice_count)
		index = espeak_voice_count - 1;
	return index;
}


- (unsigned int) setVoice:(unsigned int) index withGenderM:(BOOL) isMale
{
	if (index == UINT_MAX)
		index = [self voiceNumber:DESC(@"espeak-default-voice")];
	
	if (index < espeak_voice_count)
	{
		espeak_VOICE voice = { espeak_voices[index]->name, NULL, NULL, isMale ? 1 : 2 };
		espeak_SetVoiceByProperties (&voice);
	}
	
	return index;
}

#else

- (void) startSpeakingString:(NSString *) text  {}

- (void) stopSpeaking {}

- (BOOL) isSpeaking
{
	return NO;
}
#endif


- (BOOL) pauseMessageVisible
{
	return _pauseMessage;
}


- (void) setPauseMessageVisible:(BOOL)value
{
	_pauseMessage = value;
}


- (BOOL) permanentCommLog
{
	return _permanentCommLog;
}


- (void) setPermanentCommLog:(BOOL)value
{
	_permanentCommLog = value;
}


- (void) setAutoCommLog:(BOOL)value
{
	_autoCommLog = value;
}


- (BOOL) blockJSPlayerShipProps
{
	return gOOJSPlayerIfStale != nil;
}


- (void) setBlockJSPlayerShipProps:(BOOL)value
{
	if (value)
	{
		gOOJSPlayerIfStale = PLAYER;
	}
	else
	{
		gOOJSPlayerIfStale = nil;
	}
}


- (void) setUpSettings
{
	[self resetBeacons];
	
	next_universal_id = 100;	// start arbitrarily above zero
	memset(entity_for_uid, 0, sizeof entity_for_uid);
	
	[self setMainLightPosition:kZeroVector];

	[gui autorelease];
	gui = [[GuiDisplayGen alloc] init];
	
	// message_gui and comm_log_gui defaults are set up inside [hud resetGuis:] ( via [player deferredInit], called from the code that calls this method). 
	[message_gui autorelease];
	message_gui = [[GuiDisplayGen alloc]
					initWithPixelSize:NSMakeSize(480, 160)
							  columns:1
								 rows:9
							rowHeight:19
							 rowStart:20
								title:nil];
	
	[comm_log_gui autorelease];
	comm_log_gui = [[GuiDisplayGen alloc]
					initWithPixelSize:NSMakeSize(360, 120)
							  columns:1
								 rows:10
							rowHeight:12
							 rowStart:12
								title:nil];
	
	//
	
	time_delta = 0.0;
#ifndef NDEBUG
	[self setTimeAccelerationFactor:TIME_ACCELERATION_FACTOR_DEFAULT];
#endif
	universal_time = 0.0;
	messageRepeatTime = 0.0;
	countdown_messageRepeatTime = 0.0;
	
#if OOLITE_SPEECH_SYNTH
	[speechArray autorelease];
	speechArray = [[ResourceManager arrayFromFilesNamed:@"speech_pronunciation_guide.plist" inFolder:@"Config" andMerge:YES] retain];
#endif
	
	[commodityLists autorelease];
	commodityLists = [[ResourceManager dictionaryFromFilesNamed:@"commodities.plist" inFolder:@"Config" andMerge:YES] retain];
	
	[commodityData autorelease];
	commodityData = [[NSArray arrayWithArray:[commodityLists oo_arrayForKey:@"default"]] retain];
	
	[illegalGoods autorelease];
	illegalGoods = [[ResourceManager dictionaryFromFilesNamed:@"illegal_goods.plist" inFolder:@"Config" andMerge:YES] retain];
	
	[self loadDescriptions];
	
	[characters autorelease];
	characters = [[ResourceManager dictionaryFromFilesNamed:@"characters.plist" inFolder:@"Config" andMerge:YES] retain];
	
	[customSounds autorelease];
	customSounds = [[ResourceManager dictionaryFromFilesNamed:@"customsounds.plist" inFolder:@"Config" andMerge:YES] retain];
	
	[planetInfo autorelease];
	planetInfo = [[ResourceManager dictionaryFromFilesNamed:@"planetinfo.plist" inFolder:@"Config" mergeMode:MERGE_SMART cache:YES] retain];
	
	[screenBackgrounds autorelease];
	screenBackgrounds = [[ResourceManager dictionaryFromFilesNamed:@"screenbackgrounds.plist" inFolder:@"Config" andMerge:YES] retain];

	// role-categories.plist and pirate-victim-roles.plist
	[roleCategories autorelease];
	roleCategories = [[ResourceManager roleCategoriesDictionary] retain];
	
	[autoAIMap autorelease];
	autoAIMap = [[ResourceManager dictionaryFromFilesNamed:@"autoAImap.plist" inFolder:@"Config" andMerge:YES] retain];
	
	[equipmentData autorelease];
	equipmentData = [[ResourceManager arrayFromFilesNamed:@"equipment.plist" inFolder:@"Config" andMerge:YES] retain];

	[OOEquipmentType loadEquipment];
}


- (void) setUpCargoPods
{
	NSMutableDictionary *tmp = [[NSMutableDictionary alloc] initWithCapacity:(1 + COMMODITY_ALIEN_ITEMS - COMMODITY_FOOD)];
	OOCommodityType type;
	for (type = COMMODITY_FOOD ; type <= COMMODITY_ALIEN_ITEMS ; type++)
	{
		ShipEntity *container = [self newShipWithRole:@"oolite-template-cargopod"];
		[container setScanClass:CLASS_CARGO];
		[container setCommodity:type andAmount:1];
		[tmp setObject:container forKey:[NSNumber numberWithInt:type]];
		[container release];
	}
	[cargoPods release];
	cargoPods = [[NSDictionary alloc] initWithDictionary:tmp];
	[tmp release];
}

- (void) verifyEntitySessionIDs
{
#ifndef NDEBUG
	NSMutableArray *badEntities = nil;
	Entity *entity = nil;
	
	unsigned i;
	for (i = 0; i < n_entities; i++)
	{
		entity = sortedEntities[i];
		if ([entity sessionID] != _sessionID)
		{
			OOLogERR(@"universe.sessionIDs.verify.failed", @"Invalid entity %@ (came from session %lu, current session is %lu).", [entity shortDescription], [entity sessionID], _sessionID);
			if (badEntities == nil)  badEntities = [NSMutableArray array];
			[badEntities addObject:entity];
		}
	}
	
	foreach (entity, badEntities)
	{
		[self removeEntity:entity];
	}
#endif
}


// FIXME: needs less redundancy?
- (BOOL) reinitAndShowDemo:(BOOL) showDemo strictChanged:(BOOL) strictChanged
{
	no_update = YES;
	PlayerEntity* player = PLAYER;
	assert(player != nil);
	
	if (JSResetFlags != 0)	// JS reset failed, remember previous settings 
	{
		showDemo = (JSResetFlags & 2) > 0;	// binary 10, a.k.a. 1 << 1
		strictChanged = (JSResetFlags & 1) > 0;	// binary 01
	}
	else
	{
		JSResetFlags = (showDemo << 1) | strictChanged;
	}
	
	[self removeAllEntitiesExceptPlayer];
	[OOTexture clearCache];
	[self resetSystemDataCache];
	
	_sessionID++;	// Must be after removing old entities and before adding new ones.
	
	[ResourceManager setUseAddOns:!strict];	// also logs the paths
	//[ResourceManager loadScripts]; // initialised inside [player setUp]!
	
	// NOTE: Anything in the sharedCache is now trashed and must be
	//       reloaded. Ideally anything using the sharedCache should
	//       be aware of cache flushes so it can automatically
	//       reinitialize itself - mwerle 20081107.
	[OOShipRegistry reload];
	[[self gameController] setGamePaused:NO];
	[[self gameController] setMouseInteractionModeForUIWithMouseInteraction:NO];
	[PLAYER setSpeed:0.0];
	
	if (strictChanged)
	{
		[self loadDescriptions];
		
		[missiontext autorelease];
		missiontext = [[ResourceManager dictionaryFromFilesNamed:@"missiontext.plist" inFolder:@"Config" andMerge:YES] retain];
	}
	
	if(showDemo)
	{
		[demo_ships release];
		demo_ships = [[OOShipRegistry sharedRegistry] demoShipKeys];
		demo_ship_index = 0;
	}
	
	breakPatternCounter = 0;
	
	cachedSun = nil;
	cachedPlanet = nil;
	cachedStation = nil;
	
	[self setUpSettings];
	
	if (![player setUpAndConfirmOK:YES]) 
	{
		// reinitAndShowDemo rescheduled inside setUpAndConfirmOK...
		return NO;	// Abort!
	}
	
	// we can forget the previous settings now.
	JSResetFlags = 0;
	
	[self addEntity:player];
	demo_ship = nil;
	[[self gameController] setPlayerFileToLoad:nil];		// reset Quicksave
	
	[self setUpInitialUniverse];
	autoSaveNow = NO;	// don't autosave immediately after restarting a game
	
	[[self station] initialiseLocalMarketWithRandomFactor:[player random_factor]];
	
	if(showDemo)
	{
		[player setGuiToIntroFirstGo:NO];
		[player setStatus:STATUS_START_GAME];
	}
	else
	{
		[player setDockedAtMainStation];
	}
	
	[player completeSetUp];
	[self populateNormalSpace];

	[player startUpComplete];

	if(!showDemo)
	{
		[player setGuiToStatusScreen];
		[player doWorldEventUntilMissionScreen:OOJSID("missionScreenOpportunity")];
	}
	
	[self verifyEntitySessionIDs];

	no_update = NO;
	return YES;
}


- (void) setUpInitialUniverse
{
	PlayerEntity* player = PLAYER;
	
	OO_DEBUG_PUSH_PROGRESS(@"Wormhole and character reset");
	if (activeWormholes) [activeWormholes autorelease];
	activeWormholes = [[NSMutableArray arrayWithCapacity:16] retain];
	if (characterPool) [characterPool autorelease];
	characterPool = [[NSMutableArray arrayWithCapacity:256] retain];
	OO_DEBUG_POP_PROGRESS();
	
	OO_DEBUG_PUSH_PROGRESS(@"localPlanetInfoOverrides reset");
	// these lines are needed here to reset systeminfo and long range chart properly
	[localPlanetInfoOverrides removeAllObjects];
	OO_DEBUG_POP_PROGRESS();
	
	OO_DEBUG_PUSH_PROGRESS(@"Galaxy reset");
	[self setGalaxySeed: [player galaxy_seed] andReinit:YES];
	system_seed = [self findSystemAtCoords:[player galaxy_coordinates] withGalaxySeed:galaxy_seed];
	OO_DEBUG_POP_PROGRESS();
	
	OO_DEBUG_PUSH_PROGRESS(@"Player init: setUpShipFromDictionary");
	[player setUpShipFromDictionary:[[OOShipRegistry sharedRegistry] shipInfoForKey:[player shipDataKey]]];	// the standard cobra at this point
	[player baseMass]; // bootstrap the base mass used in all fuel charge calculations.
	OO_DEBUG_POP_PROGRESS();
	
	// Player init above finishes initialising all standard player ship properties. Now that the base mass is set, we can run setUpSpace! 
	[self setUpSpace];
	
	[self setDockingClearanceProtocolActive:[[[self planetInfo] oo_dictionaryForKey:PLANETINFO_UNIVERSAL_KEY] 
											oo_boolForKey:@"stations_require_docking_clearance" defaultValue:NO]];

	[self enterGUIViewModeWithMouseInteraction:NO];
	[player setPosition:[[self station] position]];
	[player setOrientation:kIdentityQuaternion];
}


- (float) randomDistanceWithinScanner
{
	return SCANNER_MAX_RANGE * ((Ranrot() & 255) / 256.0 - 0.5);
}


- (Vector) randomPlaceWithinScannerFrom:(Vector)pos alongRoute:(Vector)route withOffset:(double)offset
{
	pos.x += offset * route.x + [self randomDistanceWithinScanner];
	pos.y += offset * route.y + [self randomDistanceWithinScanner];
	pos.z += offset * route.z + [self randomDistanceWithinScanner];
	
	return pos;
}


- (HPVector) fractionalPositionFrom:(HPVector)point0 to:(HPVector)point1 withFraction:(double)routeFraction
{
	if (routeFraction == NSNotFound) routeFraction = randf();
	
	point1 = OOHPVectorInterpolate(point0, point1, routeFraction);
	
	point1.x += 2 * SCANNER_MAX_RANGE * (randf() - 0.5);
	point1.y += 2 * SCANNER_MAX_RANGE * (randf() - 0.5);
	point1.z += 2 * SCANNER_MAX_RANGE * (randf() - 0.5);
	
	return point1;
}


- (BOOL)doRemoveEntity:(Entity *)entity
{
	// remove reference to entity in linked lists
	if ([entity canCollide])	// filter only collidables disappearing
	{
		doLinkedListMaintenanceThisUpdate = YES;
	}
	
	[entity removeFromLinkedLists];
	
	// moved forward ^^
	// remove from the reference dictionary
	int old_id = [entity universalID];
	entity_for_uid[old_id] = nil;
	[entity setUniversalID:NO_TARGET];
	[entity wasRemovedFromUniverse];
	
	// maintain sorted lists
	int index = entity->zero_index;
	
	int n = 1;
	if (index >= 0)
	{
		if (sortedEntities[index] != entity)
		{
			OOLog(kOOLogInconsistentState, @"DEBUG: Universe removeEntity:%@ ENTITY IS NOT IN THE RIGHT PLACE IN THE ZERO_DISTANCE SORTED LIST -- FIXING...", entity);
			unsigned i;
			index = -1;
			for (i = 0; (i < n_entities)&&(index == -1); i++)
				if (sortedEntities[i] == entity)
					index = i;
			if (index == -1)
				 OOLog(kOOLogInconsistentState, @"DEBUG: Universe removeEntity:%@ ENTITY IS NOT IN THE ZERO_DISTANCE SORTED LIST -- CONTINUING...", entity);
		}
		if (index != -1)
		{
			while ((unsigned)index < n_entities)
			{
				while (((unsigned)index + n < n_entities)&&(sortedEntities[index + n] == entity))
				{
					n++;	// ie there's a duplicate entry for this entity
				}
				
				/*
					BUG: when n_entities == UNIVERSE_MAX_ENTITIES, this read
					off the end of the array and copied (Entity *)n_entities =
					0x800 into the list. The subsequent update of zero_index
					derferenced 0x800 and crashed.
					FIX: add an extra unused slot to sortedEntities, which is
					always nil.
					EFFICIENCY CONCERNS: this could have been an alignment
					issue since UNIVERSE_MAX_ENTITIES == 2048, but it isn't
					really. sortedEntities is part of the object, not malloced,
					it isn't aligned, and the end of it is only live in
					degenerate cases.
					-- Ahruman 2012-07-11
				*/
				sortedEntities[index] = sortedEntities[index + n];	// copy entity[index + n] -> entity[index] (preserves sort order)
				if (sortedEntities[index])
				{
					sortedEntities[index]->zero_index = index;				// give it its correct position
				}
				index++;
			}
			if (n > 1)
				 OOLog(kOOLogInconsistentState, @"DEBUG: Universe removeEntity: REMOVED %d EXTRA COPIES OF %@ FROM THE ZERO_DISTANCE SORTED LIST", n - 1, entity);
			while (n--)
			{
				n_entities--;
				sortedEntities[n_entities] = nil;
			}
		}
		entity->zero_index = -1;	// it's GONE!
	}
	
	// remove from the definitive list
	if ([entities containsObject:entity])
	{
		// FIXME: better approach needed for core break patterns - CIM
		if ([entity isBreakPattern] && ![entity isVisualEffect])
		{
			breakPatternCounter--;
		}
		
		if ([entity isShip])
		{
			ShipEntity *se = (ShipEntity*)entity;
			[self clearBeacon:se];
		}
		if ([entity isWaypoint])
		{
			OOWaypointEntity *wp = (OOWaypointEntity*)entity;
			[self clearBeacon:wp];
		}
		if ([entity isVisualEffect])
		{
			OOVisualEffectEntity *ve = (OOVisualEffectEntity*)entity;
			[self clearBeacon:ve];
		}
		
		if ([entity isWormhole])
		{
			[activeWormholes removeObject:entity];
		}
		else if ([entity isPlanet])
		{
			[allPlanets removeObject:entity];
		}
		
		[entities removeObject:entity];
		return YES;
	}
	
	return NO;
}


static void PreloadOneSound(NSString *soundName)
{
	if (![soundName hasPrefix:@"["] && ![soundName hasSuffix:@"]"])
	{
		[ResourceManager ooSoundNamed:soundName inFolder:@"Sounds"];
	}
}


- (void) preloadSounds
{
	// Preload sounds to avoid loading stutter.
	NSString *key = nil;
	foreachkey (key, customSounds)
	{
		id object = [customSounds objectForKey:key];
		if([object isKindOfClass:[NSString class]])
		{
			PreloadOneSound(object);
		}
		else if([object isKindOfClass:[NSArray class]] && [object count] > 0)
		{
			NSString *soundName = nil;
			foreach (soundName, object)
			{
				if ([soundName isKindOfClass:[NSString class]])
				{
					PreloadOneSound(soundName);
				}
			}
		}
	}
	
	// Afterburner sound doesn't go through customsounds.plist.
	PreloadOneSound(@"afterburner1.ogg");
}


- (void) resetSystemDataCache
{
	[sCachedSystemData release];
	sCachedSystemData = nil;
}


- (void) populateSpaceFromActiveWormholes
{
	NSAutoreleasePool	*pool = nil;
	
	while ([activeWormholes count])
	{
		pool = [[NSAutoreleasePool alloc] init];
		@try
		{
			WormholeEntity* whole = [activeWormholes objectAtIndex:0];		
			// If the wormhole has been scanned by the player then the
			// PlayerEntity will take care of it
			if (![whole isScanned] &&
				NSEqualPoints([PLAYER galaxy_coordinates], [whole destinationCoordinates]) )
			{
				// this is a wormhole to this system
				[whole disgorgeShips];
			}
			[activeWormholes removeObjectAtIndex:0];	// empty it out
		}
		@catch (NSException *exception)
		{
			OOLog(kOOLogException, @"Squashing exception during wormhole unpickling (%@: %@).", [exception name], [exception reason]);
		}
		[pool release];
	}
}


- (NSString *)chooseStringForKey:(NSString *)key inDictionary:(NSDictionary *)dictionary
{
	id object = [dictionary objectForKey:key];
	if ([object isKindOfClass:[NSString class]])  return object;
	else if ([object isKindOfClass:[NSArray class]] && [object count] > 0)  return [object oo_stringAtIndex:Ranrot() % [object count]];
	return nil;
}


#if OO_LOCALIZATION_TOOLS

#if DEBUG_GRAPHVIZ
- (void) dumpDebugGraphViz
{
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"universe-dump-debug-graphviz"])
	{
		[self dumpSystemDescriptionGraphViz];
	}
}


- (void) dumpSystemDescriptionGraphViz
{
	NSMutableString				*graphViz = nil;
	NSArray						*systemDescriptions = nil;
	NSArray						*thisDesc = nil;
	NSUInteger					i, count, j, subCount;
	NSString					*descLine = nil;
	NSArray						*curses = nil;
	NSString					*label = nil;
	NSDictionary				*keyMap = nil;
	
	keyMap = [ResourceManager dictionaryFromFilesNamed:@"sysdesc_key_table.plist"
											  inFolder:@"Config"
											  andMerge:NO];
	
	graphViz = [NSMutableString stringWithString:
				@"// System description grammar:\n\n"
				"digraph system_descriptions\n"
				"{\n"
				"\tgraph [charset=\"UTF-8\", label=\"System description grammar\", labelloc=t, labeljust=l rankdir=LR compound=true nodesep=0.02 ranksep=1.5 concentrate=true fontname=Helvetica]\n"
				"\tedge [arrowhead=dot]\n"
				"\tnode [shape=none height=0.2 width=3 fontname=Helvetica]\n\t\n"];
	
	systemDescriptions = [[self descriptions] oo_arrayForKey:@"system_description"];
	count = [systemDescriptions count];
	
	// Add system-description-string as special node (it's the one thing that ties [14] to everything else).
	descLine = DESC(@"system-description-string");
	label = OOStringifySystemDescriptionLine(descLine, keyMap, NO);
	[graphViz appendFormat:@"\tsystem_description_string [label=\"%@\" shape=ellipse]\n", EscapedGraphVizString(label)];
	[self addNumericRefsInString:descLine
					  toGraphViz:graphViz
						fromNode:@"system_description_string"
					   nodeCount:count];
	[graphViz appendString:@"\t\n"];
	
	// Add special nodes for formatting codes
	[graphViz appendString:
	 @"\tpercent_I [label=\"%I\\nInhabitants\" shape=diamond]\n"
	 "\tpercent_H [label=\"%H\\nSystem name\" shape=diamond]\n"
	 "\tpercent_RN [label=\"%R/%N\\nRandom name\" shape=diamond]\n"
	 "\tpercent_J [label=\"%J\\nNumbered system name\" shape=diamond]\n\t\n"];
	
	// Toss in the Thargoid curses, too
	[graphViz appendString:@"\tsubgraph cluster_thargoid_curses\n\t{\n\t\tlabel = \"Thargoid curses\"\n"];
	curses = [[self descriptions] oo_arrayForKey:@"thargoid_curses"];
	subCount = [curses count];
	for (j = 0; j < subCount; ++j)
	{
		label = OOStringifySystemDescriptionLine([curses oo_stringAtIndex:j], keyMap, NO);
		[graphViz appendFormat:@"\t\tthargoid_curse_%lu [label=\"%@\"]\n", j, EscapedGraphVizString(label)];
	}
	[graphViz appendString:@"\t}\n"];
	for (j = 0; j < subCount; ++j)
	{
		[self addNumericRefsInString:[curses oo_stringAtIndex:j]
						  toGraphViz:graphViz
							fromNode:[NSString stringWithFormat:@"thargoid_curse_%lu", j]
						   nodeCount:count];
	}
	[graphViz appendString:@"\t\n"];
	
	// The main show: the bits of systemDescriptions itself.
	// Define the nodes
	for (i = 0; i < count; ++i)
	{
		// Build label, using sysdesc_key_table.plist if available
		label = [keyMap objectForKey:[NSString stringWithFormat:@"%lu", i]];
		if (label == nil)  label = [NSString stringWithFormat:@"[%lu]", i];
		else  label = [NSString stringWithFormat:@"[%lu] (%@)", i, label];
		
		[graphViz appendFormat:@"\tsubgraph cluster_%lu\n\t{\n\t\tlabel=\"%@\"\n", i, EscapedGraphVizString(label)];
		
		thisDesc = [systemDescriptions oo_arrayAtIndex:i];
		subCount = [thisDesc count];
		for (j = 0; j < subCount; ++j)
		{
			label = OOStringifySystemDescriptionLine([thisDesc oo_stringAtIndex:j], keyMap, NO);
			[graphViz appendFormat:@"\t\tn%lu_%lu [label=\"\\\"%@\\\"\"]\n", i, j, EscapedGraphVizString(label)];
		}
		
		[graphViz appendString:@"\t}\n"];
	}
	[graphViz appendString:@"\t\n"];
	
	// Define the edges
	for (i = 0; i != count; ++i)
	{
		thisDesc = [systemDescriptions oo_arrayAtIndex:i];
		subCount = [thisDesc count];
		for (j = 0; j != subCount; ++j)
		{
			descLine = [thisDesc oo_stringAtIndex:j];
			[self addNumericRefsInString:descLine
							  toGraphViz:graphViz
								fromNode:[NSString stringWithFormat:@"n%lu_%lu", i, j]
							   nodeCount:count];
		}
	}
	
	// Write file
	[graphViz appendString:@"\t}\n"];
	[ResourceManager writeDiagnosticData:[graphViz dataUsingEncoding:NSUTF8StringEncoding] toFileNamed:@"SystemDescription.dot"];
}
#endif	// DEBUG_GRAPHVIZ


- (void) addNumericRefsInString:(NSString *)string toGraphViz:(NSMutableString *)graphViz fromNode:(NSString *)fromNode nodeCount:(NSUInteger)nodeCount
{
	NSString					*index = nil;
	NSInteger					start, end;
	NSRange						remaining, subRange;
	unsigned					i;
	
	remaining = NSMakeRange(0, [string length]);
	
	for (;;)
	{
		subRange = [string rangeOfString:@"[" options:NSLiteralSearch range:remaining];
		if (subRange.location == NSNotFound)  break;
		start = subRange.location + subRange.length;
		remaining.length -= start - remaining.location;
		remaining.location = start;
		
		subRange = [string rangeOfString:@"]" options:NSLiteralSearch range:remaining];
		if (subRange.location == NSNotFound)  break;
		end = subRange.location;
		remaining.length -= end - remaining.location;
		remaining.location = end;
		
		index = [string substringWithRange:NSMakeRange(start, end - start)];
		i = [index intValue];
		
		// Each node gets a colour for its incoming edges. The multiplication and mod shuffle them to avoid adjacent nodes having similar colours.
		[graphViz appendFormat:@"\t%@ -> n%u_0 [color=\"%f,0.75,0.8\" lhead=cluster_%u]\n", fromNode, i, ((float)(i * 511 % nodeCount)) / ((float)nodeCount), i];
	}
	
	if ([string rangeOfString:@"%I"].location != NSNotFound)
	{
		[graphViz appendFormat:@"\t%@ -> percent_I [color=\"0,0,0.25\"]\n", fromNode];
	}
	if ([string rangeOfString:@"%H"].location != NSNotFound)
	{
		[graphViz appendFormat:@"\t%@ -> percent_H [color=\"0,0,0.45\"]\n", fromNode];
	}
	if ([string rangeOfString:@"%R"].location != NSNotFound || [string rangeOfString:@"%N"].location != NSNotFound)
	{
		[graphViz appendFormat:@"\t%@ -> percent_RN [color=\"0,0,0.65\"]\n", fromNode];
	}
	
	// TODO: test graphViz output for @"%Jxxx"
	if ([string rangeOfString:@"%J"].location != NSNotFound)
	{
		[graphViz appendFormat:@"\t%@ -> percent_J [color=\"0,0,0.75\"]\n", fromNode];
	}
}


- (void) runLocalizationTools
{
	// Handle command line options to transform system_description array for easier localization
	
	NSArray				*arguments = nil;
	NSEnumerator		*argEnum = nil;
	NSString			*arg = nil;
	BOOL				compileSysDesc = NO, exportSysDesc = NO, xml = NO;
	
	arguments = [[NSProcessInfo processInfo] arguments];
	
	for (argEnum = [arguments objectEnumerator]; (arg = [argEnum nextObject]); )
	{
		if ([arg isEqual:@"--compile-sysdesc"])  compileSysDesc = YES;
		else if ([arg isEqual:@"--export-sysdesc"])  exportSysDesc = YES;
		else if ([arg isEqual:@"--xml"])  xml = YES;
		else if ([arg isEqual:@"--openstep"])  xml = NO;
	}
	
	if (compileSysDesc)  CompileSystemDescriptions(xml);
	if (exportSysDesc)  ExportSystemDescriptions(xml);
}
#endif


#if NEW_PLANETS
// See notes at preloadPlanetTexturesForSystem:.
- (void) prunePreloadingPlanetMaterials
{
	[[OOAsyncWorkManager sharedAsyncWorkManager] completePendingTasks];
	
	NSUInteger i = [_preloadingPlanetMaterials count];
	while (i--)
	{
		if ([[_preloadingPlanetMaterials objectAtIndex:i] isFinishedLoading])
		{
			[_preloadingPlanetMaterials removeObjectAtIndex:i];
		}
	}
}
#endif


- (void) setShaderEffectsLevelDirectly:(OOShaderSetting)value
{
	OOShaderSetting max = [[OOOpenGLExtensionManager sharedManager] maximumShaderSetting];
	
	if (value < SHADERS_MIN)  value = SHADERS_MIN;
	if (max < value)  value = max;
	
	shaderEffectsLevel = value;
}


- (void) loadConditionScripts
{
	[conditionScripts autorelease];
	conditionScripts = [[NSMutableDictionary alloc] init];
	// get list of names from cache manager 
	[self addConditionScripts:[[[OOCacheManager sharedCache] objectForKey:@"equipment conditions" inCache:@"condition scripts"] objectEnumerator]];
	
	[self addConditionScripts:[[[OOCacheManager sharedCache] objectForKey:@"ship conditions" inCache:@"condition scripts"] objectEnumerator]];
}


- (void) addConditionScripts:(NSEnumerator *)scripts
{
	NSString *scriptname = nil;
	while ((scriptname = [scripts nextObject]))
	{
		if ([conditionScripts objectForKey:scriptname] == nil)
		{
			OOJSScript *script = [OOScript jsScriptFromFileNamed:scriptname properties:nil];
			if (script != nil)
			{
				[conditionScripts setObject:script forKey:scriptname];
			}
		}
	}
}


- (OOJSScript*) getConditionScript:(NSString *)scriptname
{
	return [conditionScripts objectForKey:scriptname];
}

@end


@implementation OOSound (OOCustomSounds)

+ (id) soundWithCustomSoundKey:(NSString *)key
{
	NSString *fileName = [UNIVERSE soundNameForCustomSoundKey:key];
	if (fileName == nil)  return nil;
	return [ResourceManager ooSoundNamed:fileName inFolder:@"Sounds"];
}


- (id) initWithCustomSoundKey:(NSString *)key
{
	[self release];
	return [[OOSound soundWithCustomSoundKey:key] retain];
}

@end


@implementation OOSoundSource (OOCustomSounds)

+ (id) sourceWithCustomSoundKey:(NSString *)key
{
	return [[[self alloc] initWithCustomSoundKey:key] autorelease];
}


- (id) initWithCustomSoundKey:(NSString *)key
{
	OOSound *theSound = [OOSound soundWithCustomSoundKey:key];
	if (theSound != nil)
	{
		self = [self initWithSound:theSound];
	}
	else
	{
		[self release];
		self = nil;
	}
	return self;
}


- (void) playCustomSoundWithKey:(NSString *)key
{
	OOSound *theSound = [OOSound soundWithCustomSoundKey:key];
	if (theSound != nil)  [self playSound:theSound];
}

@end

NSComparisonResult populatorPrioritySort(id a, id b, void *context)
{
	NSDictionary *one = (NSDictionary *)a;
	NSDictionary *two = (NSDictionary *)b;
	int pri_one = [one oo_intForKey:@"priority" defaultValue:100];
	int pri_two = [two oo_intForKey:@"priority" defaultValue:100];
	if (pri_one < pri_two) return NSOrderedAscending;
	if (pri_one > pri_two) return NSOrderedDescending;
	return NSOrderedSame;
}


NSString *OOLookUpDescriptionPRIV(NSString *key)
{
	NSString *result = [UNIVERSE descriptionForKey:key];
	if (result == nil)  result = key;
	return result;
}


// There's a hint of gettext about this...
NSString *OOLookUpPluralDescriptionPRIV(NSString *key, NSInteger count)
{
	NSArray *conditions = [[UNIVERSE descriptions] oo_arrayForKey:@"plural-rules"];
	
	// are we using an older descriptions.plist (1.72.x) ?
	NSString *tmp = [UNIVERSE descriptionForKey:key];
	if (tmp != nil)
	{
		static NSMutableSet *warned = nil;
		
		if (![warned containsObject:tmp])
		{
			OOLogWARN(@"localization.plurals", @"'%@' found in descriptions.plist, should be '%@%%0'. Localization data needs updating.",key,key);
			if (warned == nil)  warned = [[NSMutableSet alloc] init];
			[warned addObject:tmp];
		}
	}
	
	if (conditions == nil)
	{
		if (tmp == nil) // this should mean that descriptions.plist is from 1.73 or above.
			return OOLookUpDescriptionPRIV([NSString stringWithFormat:@"%@%%%d", key, count != 1]);
		// still using an older descriptions.plist
		return tmp;
	}
	int unsigned i;
	long int index;
	
	for (index = i = 0; i < [conditions count]; ++index, ++i)
	{
		const char *cond = [[conditions oo_stringAtIndex:i] UTF8String];
		if (!cond)
			break;
		
		long int input = count;
		BOOL flag = NO; // we XOR test results with this
		
		while (isspace (*cond))
			++cond;
		
		for (;;)
		{
			while (isspace (*cond))
				++cond;
			
			char command = *cond++;
			
			switch (command)
			{
				case 0:
					goto passed; // end of string
					
				case '~':
					flag = !flag;
					continue;
			}
			
			long int param = strtol (cond, (char **)&cond, 10);
			
			switch (command)
			{
				case '#':
					index = param;
					continue;
					
				case '%':
					if (param < 2)
						break; // ouch - fail this!
					input %= param;
					continue;
					
				case '=':
					if (flag ^ (input == param))
						continue;
					break;
				case '!':
					if (flag ^ (input != param))
						continue;
					break;
					
				case '<':
					if (flag ^ (input < param))
						continue;
					break;
				case '>':
					if (flag ^ (input > param))
						continue;
					break;
			}
			// if we arrive here, we have an unknown test or a test has failed
			break;
		}
	}
	
passed:
	return OOLookUpDescriptionPRIV([NSString stringWithFormat:@"%@%%%ld", key, index]);
}
