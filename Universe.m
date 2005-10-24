//
//  Universe.m
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

#ifdef LINUX
#include "oolite-linux.h"
#else
#import <OpenGL/gl.h>
#import <OpenGL/glu.h>
#endif

#import "Universe.h"

#import "entities.h"

#import "MyOpenGLView.h"
#import "GameController.h"
#import "ResourceManager.h"
#import "TextureStore.h"
#import "OpenGLSprite.h"
#import "AI.h"

#import "GuiDisplayGen.h"
#import "HeadUpDisplay.h"

#define MAX_NUMBER_OF_ENTITIES				200
#define MAX_NUMBER_OF_SOLAR_SYSTEM_ENTITIES 20


@implementation Universe

- (id) init
{	
    PlayerEntity	*player;
	int i;
	
	self = [super init];
	
	n_entities = 0;
	
	firstBeacon = NO_TARGET;
	lastBeacon = NO_TARGET;
	
	no_update = NO;
//	universe_lock = [[NSLock alloc] init];	// alloc retains
	
	// init the Resource Manager
//	NSLog(@"DEBUG Universe initialising ResourceManager...");
	[ResourceManager pathsUsingAddOns:YES];
	
	// set up the universal entity data store
	if (![Entity dataStore])
		[Entity setDataStore:self];
	//
	
	//set the universal planet edge thingy
	[PlanetEntity resetBaseVertexArray];
	
	reducedDetail = NO;

   // TODO: Speech, but I doubt we'll have it with GNUstep
#ifndef GNUSTEP   
	//// speech stuff
	//
//	speechChannel = nil;
	speechSynthesizer = [[NSSpeechSynthesizer alloc] init];
	//
	//Jester Speech Begin
	speechArray = [[ResourceManager arrayFromFilesNamed:@"speech_pronunciation_guide.plist" inFolder:@"Config" andMerge:YES] retain];
	//Jester Speech End
	//
	////
#endif   
	
 	dumpCollisionInfo = NO;
	next_universal_id = 100;	// start arbitrarily above zero
	for (i = 0; i < MAX_ENTITY_UID; i++)
		entity_for_uid[i] = nil;
	//
	preloadedDataFiles =   [[NSMutableDictionary dictionaryWithCapacity:16] retain];
	//
	entityRecyclePool =			[[NSMutableDictionary dictionaryWithCapacity:MAX_NUMBER_OF_ENTITIES] retain];
	recycleLock =				[[NSLock alloc] init];
	//
    entities =				[[NSMutableArray arrayWithCapacity:MAX_NUMBER_OF_ENTITIES] retain];
	//
	sun_center_position[0] = 4000000.0;
	sun_center_position[1] = 0.0;
	sun_center_position[2] = 0.0;
	sun_center_position[3] = 1.0;
    //
	textureStore = [[TextureStore alloc] init];	// alloc retains
	//
#ifndef WIN32
	cursorSprite = [[OpenGLSprite alloc]   initWithImage:[ResourceManager imageNamed:@"cursor.png" inFolder:@"Images"]
											cropRectangle:NSMakeRect(0, 0, 128, 128)
											size:NSMakeSize(32, 32)];	// alloc retains
#else
	cursorSprite = [[OpenGLSprite alloc]   initWithSurface:[ResourceManager surfaceNamed:@"cursor.png" inFolder:@"Images"]
											cropRectangle:NSMakeRect(0, 0, 128, 128)
											size:NSMakeSize(32, 32)];	// alloc retains
#endif
	//
    gui = [[GuiDisplayGen alloc] init]; // alloc retains
    displayGUI = NO;
	//
	message_gui = [[GuiDisplayGen alloc] initWithPixelSize:NSMakeSize( 480, 160) Columns:1 Rows:8 RowHeight:20 RowStart:20 Title:nil];
	[message_gui setCurrentRow:7];
	[message_gui setCharacterSize:NSMakeSize(16,20)];	// slightly narrower characters
	
//	// TEST
//	[message_gui setBackgroundColor:[NSColor colorWithCalibratedRed:0.0 green:0.1 blue:0.9 alpha:0.5]];
	
	//
	comm_log_gui = [[GuiDisplayGen alloc] initWithPixelSize:NSMakeSize( 360, 120) Columns:1 Rows:10 RowHeight:12 RowStart:12 Title:nil];
	[comm_log_gui setCurrentRow:9];
	[comm_log_gui setBackgroundColor:[NSColor colorWithCalibratedRed:0.0 green:0.05 blue:0.45 alpha:0.5]];
	[comm_log_gui setTextColor:[NSColor whiteColor]];
	[comm_log_gui setAlpha:0.0];
	[comm_log_gui printLongText:@"Communications Log" Align:GUI_ALIGN_CENTER Color:[NSColor yellowColor] FadeTime:0 Key:nil AddToArray:nil];
	//
	displayFPS = NO;
	//
	time_delta = 0.0;
	universal_time = 0.0;
	ai_think_time = AI_THINK_INTERVAL;				// one eighth of a second
	//
	shipdata = [[ResourceManager dictionaryFromFilesNamed:@"shipdata.plist" inFolder:@"Config" andMerge:YES] retain];
	//
	shipyard = [[ResourceManager dictionaryFromFilesNamed:@"shipyard.plist" inFolder:@"Config" andMerge:YES] retain];
	//
	commoditylists = [(NSDictionary *)[ResourceManager dictionaryFromFilesNamed:@"commodities.plist" inFolder:@"Config" andMerge:YES] retain];
	commoditydata = [[NSArray arrayWithArray:(NSArray *)[commoditylists objectForKey:@"default"]] retain];
	//
	illegal_goods = [[ResourceManager dictionaryFromFilesNamed:@"illegal_goods.plist" inFolder:@"Config" andMerge:YES] retain];
	//
	descriptions = [[ResourceManager dictionaryFromFilesNamed:@"descriptions.plist" inFolder:@"Config" andMerge:YES] retain];
	//
	planetinfo = [[ResourceManager dictionaryFromFilesNamed:@"planetinfo.plist" inFolder:@"Config" andMerge:YES] retain];
	//
	local_planetinfo_overrides = [[NSMutableDictionary alloc] initWithCapacity:8];
	//
	missiontext = [[ResourceManager dictionaryFromFilesNamed:@"missiontext.plist" inFolder:@"Config" andMerge:YES] retain];
	//
	equipmentdata = [[ResourceManager arrayFromFilesNamed:@"equipment.plist" inFolder:@"Config" andMerge:YES] retain];
	//
	demo_ships = [[ResourceManager arrayFromFilesNamed:@"demoships.plist" inFolder:@"Config" andMerge:YES] retain];
	demo_ship_index = 0;
	//
	breakPatternCounter = 0;
	//
	cachedSun = nil;
	cachedPlanet = nil;
	cachedStation = nil;
	cachedEntityZero = nil;
	//
	station = NO_TARGET;
	planet = NO_TARGET;
	sun = NO_TARGET;
	//
	player = [[PlayerEntity alloc] init];	// alloc retains!
	[self addEntity:player];
	[player set_up];
	
	[player setUpShipFromDictionary:[self getDictionaryForShip:[player ship_desc]]];	// ship desc is the standard cobra at this point

	[player setStatus:STATUS_DEMO];
	
	galaxy_seed = [player galaxy_seed];
	
	// systems
	Random_Seed g_seed = galaxy_seed;
	for (i = 0; i < 256; i++)
	{
		systems[i] = g_seed;
		system_names[i] = [[self getSystemName:g_seed] retain];
		rotate_seed(&g_seed);
		rotate_seed(&g_seed);
		rotate_seed(&g_seed);
		rotate_seed(&g_seed);
	}
	
	system_seed = [self findSystemAtCoords:[player galaxy_coordinates] withGalaxySeed:galaxy_seed];
	
//	NSLog(@"Galaxy coords are (%f, %f)", [player galaxy_coordinates].x, [player galaxy_coordinates].y);
	
//	NSLog(@"Well whaddayaknow - we're at %@", [self getSystemName:system_seed]);

	
	[self set_up_space];
	

	[player release];
	//
	[self setViewDirection:VIEW_DOCKED];
	//
	
	//NSLog(@"UNIVERSE INIT station %d, planet %d, sun %d",station,planet,sun);
	
	demo_ship = nil;
		
    return self;
}

- (void) dealloc
{
    if (currentMessage)			[currentMessage release];
    
	if (gui)					[gui release];
    if (message_gui)			[message_gui release];
    if (comm_log_gui)			[comm_log_gui release];
	
//    if (messageSprite)			[messageSprite release];
    if (cursorSprite)			[cursorSprite release];

    if (textureStore)			[textureStore release];
    if (preloadedDataFiles)		[preloadedDataFiles release];
	
    if (entityRecyclePool)		[entityRecyclePool release];
    if (recycleLock)			[recycleLock release];
	
    if (entities)				[entities release];
//    if (entsInDrawOrder)		[entsInDrawOrder release];
    if (shipdata)				[shipdata release];
    if (shipyard)				[shipyard release];
	
    if (commoditylists)			[commoditylists release];
    if (commoditydata)			[commoditydata release];
	
    if (illegal_goods)			[illegal_goods release];
    if (descriptions)			[descriptions release];
    if (planetinfo)				[planetinfo release];
    if (missiontext)			[missiontext release];
	if (equipmentdata)			[equipmentdata release];
    if (demo_ships)				[demo_ships release];
    if (gameView)				[gameView release];

#ifndef GNUSTEP
	//Jester Speech Begin
	if (speechArray)			[speechArray release];
	//Jester Speech End
#endif
	
	if (local_planetinfo_overrides)
								[local_planetinfo_overrides release];
	
//	if (universe_lock)			[universe_lock release];
	
	// reset/dealloc the universal planet edge thingy
	[PlanetEntity resetBaseVertexArray];
	
	int i;
	for (i = 0; i < 256; i++)
	{
		if (system_names[i])	[system_names[i] release];
	}
	
    [super dealloc];
}

- (BOOL) strict
{
	return strict;
}

- (void) setStrict:(BOOL) value
{
	if (strict == value)
		return;
	strict = value;
	// do other necessary stuff
	//
	[self reinit];
}

- (void) reinit
{	
    PlayerEntity* player = [(PlayerEntity*)[self entityZero] retain];
	Quaternion q0;
	quaternion_set_identity(&q0);
	int i;
	
	no_update = YES;
	
	[self removeAllEntitiesExceptPlayer:NO];
	
	[ResourceManager pathsUsingAddOns:!strict];
	
	// set up the universal entity data store
	if (![Entity dataStore])
		[Entity setDataStore:self];
	//
#ifndef GNUSTEP	
	//// speech stuff
	//
	if (speechArray)
		[speechArray release];
	speechArray = [[ResourceManager arrayFromFilesNamed:@"speech_pronunciation_guide.plist" inFolder:@"Config" andMerge:YES] retain];
	//
	////
#endif
	
	//
	firstBeacon = NO_TARGET;
	lastBeacon = NO_TARGET;
	
	next_universal_id = 100;	// start arbitrarily above zero
	for (i = 0; i < MAX_ENTITY_UID; i++)
		entity_for_uid[i] = nil;
	//
	if (preloadedDataFiles)
		[preloadedDataFiles release];
	preloadedDataFiles =   [[NSMutableDictionary dictionaryWithCapacity:16] retain];
	//
	if (entityRecyclePool)
		[entityRecyclePool release];
	entityRecyclePool =			[[NSMutableDictionary dictionaryWithCapacity:MAX_NUMBER_OF_ENTITIES] retain];
	if (recycleLock)
		[recycleLock release];
	recycleLock =				[[NSLock alloc] init];
	//
	sun_center_position[0] = 4000000.0;
	sun_center_position[1] = 0.0;
	sun_center_position[2] = 0.0;
	sun_center_position[3] = 1.0;
    //
	if (textureStore)
		[textureStore release];
	textureStore = [[TextureStore alloc] init];	// alloc retains
	//
	if (cursorSprite)
		[cursorSprite release];
#ifndef WIN32
	cursorSprite = [[OpenGLSprite alloc]   initWithImage:[ResourceManager imageNamed:@"cursor.png" inFolder:@"Images"]
											cropRectangle:NSMakeRect(0, 0, 128, 128)
											size:NSMakeSize(32, 32)];	// alloc retains
#else
	cursorSprite = [[OpenGLSprite alloc]   initWithSurface:[ResourceManager surfaceNamed:@"cursor.png" inFolder:@"Images"]
											cropRectangle:NSMakeRect(0, 0, 128, 128)
											size:NSMakeSize(32, 32)];	// alloc retains
#endif
	//
	if (gui)
		[gui release];
	gui = [[GuiDisplayGen alloc] init]; // alloc retains
	
	//
	if (message_gui)
		[message_gui release];
	message_gui = [[GuiDisplayGen alloc] initWithPixelSize:NSMakeSize( 480, 160) Columns:1 Rows:8 RowHeight:20 RowStart:20 Title:nil];
	[message_gui setCurrentRow:7];
	[message_gui setCharacterSize:NSMakeSize(16,20)];	// slightly narrower characters
	
	//
	if (comm_log_gui)
		[comm_log_gui release];
	comm_log_gui = [[GuiDisplayGen alloc] initWithPixelSize:NSMakeSize( 360, 120) Columns:1 Rows:10 RowHeight:12 RowStart:12 Title:nil];
	[comm_log_gui setCurrentRow:9];
	[comm_log_gui setBackgroundColor:[NSColor colorWithCalibratedRed:0.0 green:0.05 blue:0.45 alpha:0.5]];
	[comm_log_gui setTextColor:[NSColor whiteColor]];
	[comm_log_gui setAlpha:0.0];
	[comm_log_gui printLongText:@"Communications Log" Align:GUI_ALIGN_CENTER Color:[NSColor yellowColor] FadeTime:0 Key:nil AddToArray:nil];
	//
	time_delta = 0.0;
	universal_time = 0.0;
	ai_think_time = AI_THINK_INTERVAL;				// one eighth of a second
	//
	if (shipdata)
		[shipdata release];
	shipdata = [[ResourceManager dictionaryFromFilesNamed:@"shipdata.plist" inFolder:@"Config" andMerge:YES] retain];
	if (shipyard)
		[shipyard release];
	shipyard = [[ResourceManager dictionaryFromFilesNamed:@"shipyard.plist" inFolder:@"Config" andMerge:YES] retain];
	//
	if (commoditylists)
		[commoditylists release];
	commoditylists = [(NSDictionary *)[ResourceManager dictionaryFromFilesNamed:@"commodities.plist" inFolder:@"Config" andMerge:YES] retain];
	if (commoditydata)
		[commoditydata release];
	commoditydata = [[NSArray arrayWithArray:(NSArray *)[commoditylists objectForKey:@"default"]] retain];
	//
	if (illegal_goods)
		[illegal_goods release];
	illegal_goods = [[ResourceManager dictionaryFromFilesNamed:@"illegal_goods.plist" inFolder:@"Config" andMerge:YES] retain];
	//
	if (descriptions)
		[descriptions release];
	descriptions = [[ResourceManager dictionaryFromFilesNamed:@"descriptions.plist" inFolder:@"Config" andMerge:YES] retain];
	//
	if (planetinfo)
		[planetinfo release];
	planetinfo = [[ResourceManager dictionaryFromFilesNamed:@"planetinfo.plist" inFolder:@"Config" andMerge:YES] retain];
	//
	if (missiontext)
		[missiontext release];
	missiontext = [[ResourceManager dictionaryFromFilesNamed:@"missiontext.plist" inFolder:@"Config" andMerge:YES] retain];
	//
	if (equipmentdata)
		[equipmentdata release];
	equipmentdata = [[ResourceManager arrayFromFilesNamed:@"equipment.plist" inFolder:@"Config" andMerge:YES] retain];
	if (strict && ([equipmentdata count] > NUMBER_OF_STRICT_EQUIPMENT_ITEMS))
	{
		NSArray* strict_equipment = [equipmentdata subarrayWithRange:NSMakeRange(0, NUMBER_OF_STRICT_EQUIPMENT_ITEMS)];	// alloc retains
		[equipmentdata autorelease];
		equipmentdata = [strict_equipment retain];
	}
//	NSLog(@"DEBUG equipmentdata = %@", [equipmentdata description]);
	//
	if (demo_ships)
		[demo_ships release];
	demo_ships = [[ResourceManager arrayFromFilesNamed:@"demoships.plist" inFolder:@"Config" andMerge:YES] retain];
	demo_ship_index = 0;
	//
	breakPatternCounter = 0;
	//
	cachedSun = nil;
	cachedPlanet = nil;
	cachedStation = nil;
	cachedEntityZero = nil;
	//
	station = NO_TARGET;
	planet = NO_TARGET;
	sun = NO_TARGET;
	//
	if (player == nil)
		player = [[PlayerEntity alloc] init];
	[self addEntity:player];
	
	[[(MyOpenGLView*)gameView gameController] setPlayerFileToLoad:nil];		// reset Quicksave

	galaxy_seed = [player galaxy_seed];
	
	// systems
	Random_Seed g_seed = galaxy_seed;
	for (i = 0; i < 256; i++)
	{
		systems[i] = g_seed;
		system_names[i] = [[self getSystemName:g_seed] retain];
		rotate_seed(&g_seed);
		rotate_seed(&g_seed);
		rotate_seed(&g_seed);
		rotate_seed(&g_seed);
	}
	
	system_seed = [self findSystemAtCoords:[player galaxy_coordinates] withGalaxySeed:galaxy_seed];
	
//	NSLog(@"Galaxy coords are (%f, %f)", [player galaxy_coordinates].x, [player galaxy_coordinates].y);
	
//	NSLog(@"Well whaddayaknow - we're at %@", [self getSystemName:system_seed]);
	
	[self set_up_space];

	demo_ship = nil;
	
	//
	[player set_up];
	//
	[player setUpShipFromDictionary:[self getDictionaryForShip:[player ship_desc]]];	// ship_desc is the standard Cobra at this point
	//
	[player setStatus:STATUS_DOCKED];
	[self setViewDirection:VIEW_DOCKED];
	[player setPosition:0 :0 :0];
	[player setQRotation:q0];
	[player setGuiToIntro2Screen];
	[gui setText:(strict)? @"Strict Play Enabled":@"Unrestricted Play Enabled" forRow:1 align:GUI_ALIGN_CENTER];
	//
	
	[player release];
	
	no_update = NO;
	
	[local_planetinfo_overrides removeAllObjects];
}


- (int) obj_count
{
	return [entities count];
}

- (void) obj_dump
{
	NSLog(@"DEBUG ENTITY DUMP: [entities count] = %d,\tn_entities = %d", [entities count], n_entities);
	int i;
	for (i = 0; i < n_entities; i++)
	{
		ShipEntity* se = (sortedEntities[i]->isShip)? (ShipEntity*)sortedEntities[i]: nil;
		NSString* ai_status = [[se getAI] description];
		NSLog(@"-> Ent:%d\t\t%@ mass %.2f %@", i, sortedEntities[i], [sortedEntities[i] mass], ai_status);
	}
	if ([entities count] != n_entities)
		NSLog(@"entities = %@", [entities description]);
}

- (void) sleepytime: (id) thing
{
	// deal with the machine going to sleep
	//NSLog(@"DEBUG -- got a SLEEP notification.");
	PlayerEntity *player = (PlayerEntity *)[self entityZero];
	if ((player)&&(player->status == STATUS_IN_FLIGHT))
	{
		[self displayMessage:@" Paused (press 'p') " forCount:1.0];
		[[(MyOpenGLView *)gameView gameController] pause_game];
	}
}

- (void) set_up_universe_from_station
{
	//NSLog(@"UNIVERSE set_up_universe_from_station station %d, planet %d, sun %d",station,planet,sun);
	if (station == NO_TARGET)
	{
		// we're in witchspace or this is the first launch...
		
		// save the player
		PlayerEntity*	player = (PlayerEntity*)[self entityZero];
		// save the docked craft
		Entity*			docked_station = [player docked_station];
		// jump to the nearest system
		Random_Seed s_seed = [self findSystemAtCoords:[player galaxy_coordinates] withGalaxySeed:[player galaxy_seed]];
		[player setSystem_seed:s_seed];
			
		// remove everything else
		if (docked_station)
		{
			int index = 0;
			while ([entities count] > 2)
			{
				Entity* ent = [entities objectAtIndex:index];
				if ((ent != player)&&(ent != docked_station))
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
			[self removeAllEntitiesExceptPlayer:NO];	// get rid of witchspace sky etc. if still extant
		}

		[self set_up_space];	// first launch
	}
	station = [[self station] universal_id];
	planet = [[self planet] universal_id];
	sun = [[self sun] universal_id];
	
	[self setViewDirection:VIEW_FORWARD];
	displayGUI = NO;
}

- (void) set_up_universe_from_witchspace
{
    PlayerEntity		*player;

    //
	// check the player is still around!
    //
	if ([entities count] == 0)
	{
		/*- the player ship -*/
		player = [[PlayerEntity alloc] init];	// alloc retains!
		//
		[self addEntity:player];
		//
		/*--*/
	}
	else
	{
		player = [(PlayerEntity *)[self entityZero] retain];	// retained here
	}
	//

	[self set_up_space];
	
	[player leaveWitchspace];
	[player release];											// released here
	
	[self setViewDirection:VIEW_FORWARD];
	
	[comm_log_gui printLongText:[NSString stringWithFormat:@"%@ %@", [self generateSystemName:system_seed], [player dial_clock_adjusted]]
		Align:GUI_ALIGN_CENTER Color:[NSColor whiteColor] FadeTime:0 Key:nil AddToArray:[player comm_log]];
	//
    //
	/* test stuff */
	displayGUI = NO;
	/* ends */
}

- (void) set_up_universe_from_misjump
{
    PlayerEntity		*player;

    //
	// check the player is still around!
    //
	if ([entities count] == 0)
	{
		/*- the player ship -*/
		player = [[PlayerEntity alloc] init];	// alloc retains!
		//
		[self addEntity:player];
		//
		/*--*/
	}
	else
	{
		player = [(PlayerEntity *)[self entityZero] retain];	// retained here
	}
	//

	[self set_up_witchspace];
	
	[player leaveWitchspace];
	[player release];											// released here
	
	[self setViewDirection:VIEW_FORWARD];
	//
    //
	/* test stuff */
	displayGUI = NO;
	/* ends */
}

- (void) set_up_witchspace
{
	// new system is hyper-centric : witchspace exit point is origin

    Entity				*thing;
	PlayerEntity*		player = (PlayerEntity*)[self entityZero];
	Quaternion			randomQ;
	
	NSMutableDictionary*	systeminfo = [NSMutableDictionary dictionaryWithCapacity:4];

	if (player)
	{
		Random_Seed		s1 = player->system_seed;
		Random_Seed		s2 = player->target_system_seed;
		NSString*		override_key = [self keyForInterstellarOverridesForSystemSeeds:s1 :s2 inGalaxySeed:galaxy_seed];
		
//		NSLog(@"DEBUG checking interstellar overrides for key '%@'", override_key);
		
		// check at this point
		// for scripted overrides for this insterstellar area
		if ([planetinfo objectForKey:PLANETINFO_UNIVERSAL_KEY])
			[systeminfo addEntriesFromDictionary:(NSDictionary *)[planetinfo objectForKey:PLANETINFO_UNIVERSAL_KEY]];
		if ([planetinfo objectForKey:override_key])
			[systeminfo addEntriesFromDictionary:(NSDictionary *)[planetinfo objectForKey:override_key]];
		if ([local_planetinfo_overrides objectForKey:override_key])
			[systeminfo addEntriesFromDictionary:(NSDictionary *)[local_planetinfo_overrides objectForKey:override_key]];
		
//		NSLog(@"DEBUGsysteminfo now:\n%@", systeminfo);
		
	}
	
	//
	// fixed entities (part of the graphics system really) come first...
	//
	
	/*- the sky backdrop -*/
	NSColor *col1 = [NSColor colorWithCalibratedRed:0.0 green:1.0 blue:0.5 alpha:1.0];
	NSColor *col2 = [NSColor colorWithCalibratedRed:0.0 green:1.0 blue:0.0 alpha:1.0];
//	thing = [[SkyEntity alloc] initAsWitchspace];	// alloc retains!
	thing = [[SkyEntity alloc] initWithColors:col1:col2 andSystemInfo: systeminfo];	// alloc retains!
	[thing setScanClass: CLASS_NO_DRAW];
	quaternion_set_random(&randomQ);
	[thing setQRotation:randomQ];
	[self addEntity:thing]; // [entities addObject:thing];
	[thing release];
	/*--*/
	
	/*- the dust particle system -*/
	thing = [[DustEntity alloc] init];	// alloc retains!
	[thing setScanClass: CLASS_NO_DRAW];
	[self addEntity:thing]; // [entities addObject:thing];
	[thing release];
	/*--*/
	
	sun = NO_TARGET;
	station = NO_TARGET;
	planet = NO_TARGET;
	sun_center_position[0] = 0.0;
	sun_center_position[1] = 0.0;
	sun_center_position[2] = 0.0;
	sun_center_position[3] = 1.0;
	
	ranrot_srand([[NSDate date] timeIntervalSince1970]);   // reset randomiser with current time
	
	[self setLighting];
		
	NSLog(@"Populating witchspace ...");
	
	//
	// actual thargoids and tharglets next...
	//
	int n_thargs = 2 + (ranrot_rand() & 3);
	if (n_thargs < 1)
		n_thargs = 2;   // just to be sure
	int i;
	int thargoid_group = NO_TARGET;

	Vector		tharg_start_pos = [self getWitchspaceExitPosition];
	ranrot_srand([[NSDate date] timeIntervalSince1970]);   // reset randomiser with current time

	NSLog(@"... adding %d Thargoid warships", n_thargs);
	
	for (i = 0; i < n_thargs; i++)
	{
		Quaternion  tharg_quaternion;
		ShipEntity  *thargoid = [self getShipWithRole:@"thargoid"]; // is retained
		if (thargoid)
		{
			Vector		tharg_pos = tharg_start_pos;
			
			tharg_pos.x += 1.5 * SCANNER_MAX_RANGE * (randf() - 0.5);
			tharg_pos.y += 1.5 * SCANNER_MAX_RANGE * (randf() - 0.5);
			tharg_pos.z += 1.5 * SCANNER_MAX_RANGE * (randf() - 0.5);
			[thargoid setPosition:tharg_pos];
			quaternion_set_random(&tharg_quaternion);
			[thargoid setQRotation:tharg_quaternion];
			[thargoid setScanClass: CLASS_THARGOID];
			[thargoid setBounty:100];
			[thargoid setStatus:STATUS_IN_FLIGHT];
	//		[thargoid setReportAImessages:YES];
			[self addEntity:thargoid];
			if (thargoid_group == NO_TARGET)
				thargoid_group = [thargoid universal_id];
			
			[thargoid setGroup_id:thargoid_group];
			
			[thargoid release];
		}
	}
	
	// NEW
	//
	// systeminfo might have a 'script_actions' resource we want to activate now...
	//
	if ([systeminfo objectForKey:KEY_SCRIPT_ACTIONS])
	{
//		NSLog(@"DEBUG executing systeminfo script_actions");
//		debug = YES;
		
		NSArray* script_actions = (NSArray *)[systeminfo objectForKey:KEY_SCRIPT_ACTIONS];
		int i;
		for (i = 0; i < [script_actions count]; i++)
		{
			if ([[script_actions objectAtIndex:i] isKindOfClass:[NSDictionary class]])
				[player checkCouplet:(NSDictionary *)[script_actions objectAtIndex:i] onEntity:nil];
			if ([[script_actions objectAtIndex:i] isKindOfClass:[NSString class]])
				[player scriptAction:(NSString *)[script_actions objectAtIndex:i] onEntity:nil];
		}
		
//		debug = NO;
	}
	
}

- (void) set_up_space
{
	// new system is hyper-centric : witchspace exit point is origin
	//
    Entity				*thing;
    ShipEntity			*nav_buoy;
    StationEntity		*a_station;
    PlanetEntity		*a_sun;
    PlanetEntity		*a_planet;
	
	Vector				stationPos;
//	double				stationRoll;
	
	Vector				vf;

	NSDictionary		*systeminfo = [self generateSystemData:system_seed];
	int					techlevel = [(NSNumber *)[systeminfo objectForKey:KEY_TECHLEVEL] intValue];
	NSString			*stationDesc;
	NSColor				*bgcolor;
	NSColor				*pale_bgcolor;
	
	BOOL				sun_gone_nova = NO;
	if ([systeminfo objectForKey:@"sun_gone_nova"])
		sun_gone_nova = YES;
	
//	NSLog(@"DEBUG systeminfo =\n%@", [systeminfo description]);
	
	//
	// fixed entities (part of the graphics system really) come first...
	//
	[self setSky_clear_color:0.0 :0.0 :0.0 :0.0];
	
	// set the system seed for random number generation
	seed_for_planet_description(system_seed);
	
	/*- the sky backdrop -*/
	// colors...
	float h1 = randf();
	float h2 = h1 + 1.0 / (1.0 + (ranrot_rand() % 5));
	while (h2 > 1.0)
		h2 -= 1.0;
	NSColor *col1 = [NSColor colorWithCalibratedHue:h1 saturation:randf() brightness:0.5 + randf()/2.0 alpha:1.0];
	NSColor *col2 = [NSColor colorWithCalibratedHue:h2 saturation:0.5 + randf()/2.0 brightness:0.5 + randf()/2.0 alpha:1.0];
	
	thing = [[SkyEntity alloc] initWithColors:col1:col2 andSystemInfo: systeminfo];	// alloc retains!
	[thing setScanClass: CLASS_NO_DRAW];
	[self addEntity:thing]; // [entities addObject:thing];
	bgcolor = [(SkyEntity *)thing sky_color];
	pale_bgcolor = [bgcolor blendedColorWithFraction:0.5 ofColor:[NSColor whiteColor]];
	[thing release];
	/*--*/
	
	[self setLighting];
	
	/*- the dust particle system -*/
	thing = [[DustEntity alloc] init];	// alloc retains!
	[thing setScanClass: CLASS_NO_DRAW];
	[self addEntity:thing]; // [entities addObject:thing];
	[(DustEntity *)thing setDustColor:pale_bgcolor]; 
	[thing release];
	/*--*/
	
	//
	// actual entities next...
	//
	
	// set the system seed for random number generation
	seed_for_planet_description(system_seed);
	
	/*- space planet -*/
	a_planet = [[PlanetEntity alloc] initWithSeed: system_seed fromUniverse: self];	// alloc retains!
	double planet_radius = [a_planet getRadius];
	
	[a_planet setPlanetType:PLANET_TYPE_GREEN];
	[a_planet setStatus:STATUS_ACTIVE];
	[a_planet setPosition:0.0:0.0:(12.0 + (ranrot_rand() & 3) - (ranrot_rand() & 3) ) * planet_radius]; // 10..14 pr (planet radii)  ahead
	[a_planet setScanClass: CLASS_NO_DRAW];
	[a_planet setEnergy:  1000000.0];
	[self addEntity:a_planet]; // [entities addObject:a_planet];
	
	planet = [a_planet universal_id];
	/*--*/
	
	// set the system seed for random number generation
	seed_for_planet_description(system_seed);
	
	/*- space sun -*/
	double		sun_distance = (20.0 + (ranrot_rand() % 5) - (ranrot_rand() % 5) ) * planet_radius;
	double		sun_radius = (2.5 + randf() - randf() ) * planet_radius;
	Quaternion  q_sun;
	Vector		sunPos = make_vector(0,0,0);
	
	// here we need to check if the sun collides with (or is too close to) the witchpoint
	// otherwise at (for example) Maregais in Galaxy 1 we go BANG!
	do {
		// show for debugging
//		if (magnitude2(sunPos))
//			NSLog(@"DEBUG looping to avoid sun-witchpoint collision!");
		
		sunPos = a_planet->position;
		
		quaternion_set_random(&q_sun);
		// set up planet's direction in space so it gets a proper day
		[a_planet setQRotation:q_sun];
		
		vf = vector_right_from_quaternion(q_sun);
		sunPos.x -= sun_distance * vf.x;	// back off from the planet by 16..24 pr
		sunPos.y -= sun_distance * vf.y;
		sunPos.z -= sun_distance * vf.z;
	
	} while (magnitude2(sunPos) < 16 * sun_radius * sun_radius);	// stay at least 4 radii away!
	
	a_sun = [[PlanetEntity alloc] initAsSunWithColor:pale_bgcolor];	// alloc retains!
	[a_sun setPlanetType:PLANET_TYPE_SUN];
	[a_sun setStatus:STATUS_ACTIVE];
	[a_sun setPosition:sunPos];
	sun_center_position[0] = sunPos.x;
	sun_center_position[1] = sunPos.y;
	sun_center_position[2] = sunPos.z;
	sun_center_position[3] = 1.0;
	[a_sun setRadius:sun_radius];			// 2.5 pr
	[a_sun setScanClass: CLASS_NO_DRAW];
	[a_sun setEnergy:  1000000.0];
	[self addEntity:a_sun];					// [entities addObject:a_sun];
	sun = [a_sun universal_id];
	
	if (sun_gone_nova)
	{
		[a_sun setRadius: sun_radius + 600000];
		[a_sun setThrowSparks:YES];
		[a_sun setVelocity:make_vector(0,0,0)];
	}
	/*--*/
		
	
	/*- space station -*/
	stationPos = a_planet->position;
	double  station_orbit = 2.0 * planet_radius;
	Quaternion  q_station;
	vf.z = -1;
	while (vf.z <= 0.0)						// keep station on the correct side of the planet
	{
		quaternion_set_random(&q_station);
		vf = vector_forward_from_quaternion(q_station);
	}
	stationPos.x -= station_orbit * vf.x;					// back away from the planet
	stationPos.y -= station_orbit * vf.y;
	stationPos.z -= station_orbit * vf.z;
	//NSLog(@"Station added at vector (%.1f,%.1f,%.1f) from planet",-vf.x,-vf.y,-vf.z);
	stationDesc = @"coriolis";
	if (techlevel > 10)
	{
		if (system_seed.f & 0x03)   // 3 out of 4 get this type
			stationDesc = @"dodecahedron";
		else
			stationDesc = @"icosahedron";
	}
	
	//// possibly systeminfo has an override for the station
	//
	if ([systeminfo objectForKey:@"station"])
		stationDesc = (NSString *)[systeminfo objectForKey:@"station"];
	
	//NSLog(@"* INFO *\t>>\tAdding %@ station for TL %d", stationDesc, techlevel);
	a_station = (StationEntity *)[self getShipWithRole:stationDesc];			   // retain count = 1
	if (a_station)
	{
		[a_station setStatus:STATUS_ACTIVE];
		[a_station setQRotation: q_station];
		[a_station setPosition: stationPos];
		[a_station setPitch: 0.0];
		[a_station setScanClass: CLASS_STATION];
		[a_station setPlanet:(PlanetEntity *)[self entityForUniversalID:planet]];
		[a_station set_equivalent_tech_level:techlevel];
		[self addEntity:a_station];
		station = [a_station universal_id];
	}

	cachedSun = a_sun;
	cachedPlanet = a_planet;
	cachedStation = a_station;
	
	ranrot_srand([[NSDate date] timeIntervalSince1970]);   // reset randomiser with current time
	[self populateSpaceFromHyperPoint:[self getWitchspaceExitPosition] toPlanetPosition: a_planet->position andSunPosition: a_sun->position];
	
	// log positions and info against debugging 
//	NSLog(@"DEBUG ** System :\t%@", [self generateSystemName:system_seed]);
//	NSLog(@"DEBUG ** Planet position\t( %.0f, %.0f, %.0f)",
//		a_planet->position.x, a_planet->position.y, a_planet->position.z);
//	NSLog(@"DEBUG ** Sun position\t( %.0f, %.0f, %.0f)",
//		a_sun->position.x, a_sun->position.y, a_sun->position.z);
//	NSLog(@"DEBUG ** Station position\t( %.0f, %.0f, %.0f)",
//		a_station->position.x, a_station->position.y, a_station->position.z);
//	NSLog(@"DEBUG **\n\n");
//	NSLog(@"DEBUG ** Sun q_sun\t( %.3f, %.3f, %.3f, %.3f)",
//		q_sun.w, q_sun.x, q_sun.y, q_sun.z);
//	NSLog(@"DEBUG ** Station q_station\t( %.3f, %.3f, %.3f, %.3f)",
//		q_station.w, q_station.x, q_station.y, q_station.z);
//	NSLog(@"DEBUG **\n\n");
	
	
	/*- nav beacon -*/
	nav_buoy = [self getShipWithRole:@"buoy"];	// retain count = 1
	if (nav_buoy)
	{
		[nav_buoy setRoll:	0.10];	// zero for debugging
		[nav_buoy setPitch:	0.15];	// zero for debugging
		[nav_buoy setPosition: [cachedStation getBeaconPosition]];
		[nav_buoy setScanClass: CLASS_BUOY];
		[self addEntity:nav_buoy];
		[nav_buoy setStatus:STATUS_IN_FLIGHT];
		[nav_buoy release];
	}
	/*--*/
	
	/*- nav beacon witchpoint -*/
	Vector witchpoint = [self getWitchspaceExitPosition];	// witchpoint
	nav_buoy = [self getShipWithRole:@"buoy-witchpoint"];	// retain count = 1
	if (nav_buoy)
	{
		[nav_buoy setRoll:	0.10];
		[nav_buoy setPitch:	0.15];
		[nav_buoy setPosition: witchpoint.x: witchpoint.y: witchpoint.z];
		[nav_buoy setScanClass: CLASS_BUOY];
		[self addEntity:nav_buoy];
		[nav_buoy setStatus:STATUS_IN_FLIGHT];
		[nav_buoy release];
	}
	/*--*/
	
	if (sun_gone_nova)
	{
		Vector v0 = make_vector(0,0,34567.89);
		Vector planetPos = a_planet->position;
		double min_safe_dist2 = 5000000.0 * 5000000.0;
//		NSLog(@"DEBUG checking sun-distance = %.1f", sqrt(magnitude2(a_sun->position)));
		while (magnitude2(a_sun->position) < min_safe_dist2)	// back off the planetary bodies
		{
			v0.z *= 2.0;
			planetPos = a_planet->position;
			[a_planet setPosition: planetPos.x + v0.x: planetPos.y + v0.y: planetPos.z + v0.z];
			[a_sun setPosition: sunPos.x + v0.x: sunPos.y + v0.y: sunPos.z + v0.z];
			sunPos = a_sun->position;
			[a_station setPosition: stationPos.x + v0.x: stationPos.y + v0.y: stationPos.z + v0.z];
			stationPos = a_station->position;
//			NSLog(@"DEBUG backing off sun-distance = %.1f", sqrt(magnitude2(a_sun->position)));
		}
		sun_center_position[0] = sunPos.x;
		sun_center_position[1] = sunPos.y;
		sun_center_position[2] = sunPos.z;
		sun_center_position[3] = 1.0;
				
		[self removeEntity:a_planet];	// and Poof! it's gone
		cachedPlanet = nil;
		int i;
		for (i = 0; i < 3; i++)
		{
			[self scatterAsteroidsAt:planetPos withVelocity:make_vector(0,0,0) includingRockHermit:NO];
			[self scatterAsteroidsAt:make_vector(0,0,0) withVelocity:make_vector(0,0,0) includingRockHermit:NO];
		}
		
	}
	
	[a_sun release];
	[a_station release];
	[a_planet release];
	
	// NEW
	//
	// systeminfo might have a 'script_actions' resource we want to activate now...
	//
	if ([systeminfo objectForKey:KEY_SCRIPT_ACTIONS])
	{
		PlayerEntity* player = (PlayerEntity*)[self entityZero];
		NSArray* script_actions = (NSArray *)[systeminfo objectForKey:KEY_SCRIPT_ACTIONS];
		int i;
		for (i = 0; i < [script_actions count]; i++)
		{
			if ([[script_actions objectAtIndex:i] isKindOfClass:[NSDictionary class]])
				[player checkCouplet:(NSDictionary *)[script_actions objectAtIndex:i] onEntity:nil];
			if ([[script_actions objectAtIndex:i] isKindOfClass:[NSString class]])
				[player scriptAction:(NSString *)[script_actions objectAtIndex:i] onEntity:nil];
		}
	}
	
}

- (void) setLighting
{
	PlanetEntity*	the_sun = [self sun];
	SkyEntity*		the_sky = nil;
	GLfloat			sun_pos[] = {4000000.0, 0.0, 0.0, 1.0};
	int i;
	for (i = n_entities - 1; i > 0; i--)
		if ((sortedEntities[i]) && ([sortedEntities[i] isKindOfClass:[SkyEntity class]]))
			the_sky = (SkyEntity*)sortedEntities[i];
	if (the_sun)
	{
		GLfloat	sun_ambient[] = { 0.0, 0.0, 0.0, 1.0};	// ambient light about 5%
		sun_diffuse[0] = the_sun->sun_diffuse[0];
		sun_diffuse[1] = the_sun->sun_diffuse[1];
		sun_diffuse[2] = the_sun->sun_diffuse[2];
		sun_diffuse[3] = the_sun->sun_diffuse[3];
		sun_specular[0] = the_sun->sun_specular[0];
		sun_specular[1] = the_sun->sun_specular[1];
		sun_specular[2] = the_sun->sun_specular[2];
		sun_specular[3] = the_sun->sun_specular[3];
		glLightfv(GL_LIGHT1, GL_AMBIENT, sun_ambient);
		glLightfv(GL_LIGHT1, GL_DIFFUSE, sun_diffuse);
		glLightfv(GL_LIGHT1, GL_SPECULAR, sun_specular);
		sun_pos[0] = the_sun->position.x;
		sun_pos[1] = the_sun->position.y;
		sun_pos[2] = the_sun->position.z;
	}
	else
	{
		// witchspace
		GLfloat	sun_ambient[] = { 0.0, 0.0, 0.0, 1.0};	// ambient light nil
		stars_ambient[0] = 0.05;	stars_ambient[1] = 0.20;	stars_ambient[2] = 0.05;	stars_ambient[3] = 1.0;
		sun_diffuse[0] = 0.85;	sun_diffuse[1] = 1.0;	sun_diffuse[2] = 0.85;	sun_diffuse[3] = 1.0;
		sun_specular[0] = 0.95;	sun_specular[1] = 1.0;	sun_specular[2] = 0.95;	sun_specular[3] = 1.0;
		glLightfv(GL_LIGHT1, GL_AMBIENT, sun_ambient);
		glLightfv(GL_LIGHT1, GL_DIFFUSE, sun_diffuse);
		glLightfv(GL_LIGHT1, GL_SPECULAR, sun_specular);
		glLightModelfv(GL_LIGHT_MODEL_AMBIENT, stars_ambient);
	}
	//
	glLightfv(GL_LIGHT1, GL_POSITION, sun_pos);
	//
	if (the_sky)
	{
		// ambient lighting!
		float r,g,b,a;
		[[the_sky sky_color] getRed:&r green:&g blue:&b alpha:&a];
		stars_ambient[0] = 0.0625 * (1.0 + r) * (1.0 + r);
		stars_ambient[1] = 0.0625 * (1.0 + g) * (1.0 + g);
		stars_ambient[2] = 0.0625 * (1.0 + b) * (1.0 + b);
		stars_ambient[3] = 1.0;
		glLightModelfv(GL_LIGHT_MODEL_AMBIENT, stars_ambient);
	}
	//
	// light for demo ships display..
	GLfloat	white[] = { 1.0, 1.0, 1.0, 1.0};	// white light
	glLightfv(GL_LIGHT0, GL_AMBIENT, white);
	glLightfv(GL_LIGHT0, GL_DIFFUSE, white);
	glLightfv(GL_LIGHT0, GL_SPECULAR, white);
			
}

- (void) populateSpaceFromHyperPoint:(Vector) h1_pos toPlanetPosition:(Vector) p1_pos andSunPosition:(Vector) s1_pos
{
	int i, r, escorts_added;
	NSDictionary		*systeminfo = [self generateSystemData:system_seed];

	BOOL				sun_gone_nova = NO;
	if ([systeminfo objectForKey:@"sun_gone_nova"])
		sun_gone_nova = YES;
	
	int techlevel =		[(NSNumber *)[systeminfo objectForKey:KEY_TECHLEVEL] intValue]; // 0 .. 13
	int government =	[(NSNumber *)[systeminfo objectForKey:KEY_GOVERNMENT] intValue]; // 0 .. 7 (0 anarchic .. 7 most stable)
	int economy =		[(NSNumber *)[systeminfo objectForKey:KEY_ECONOMY] intValue];	// 0 .. 7 (0 richest .. 7 poorest)
	int thargoidChance = (system_seed.e < 127) ? 10 : 3; // if Human Colonials live here, there's a greater % chance the Thargoids will attack!
	Vector  lastPiratePosition;
	int		wolfPackCounter = 0;
	int		wolfPackGroup_id = NO_TARGET;
	
	ranrot_srand([[NSDate date] timeIntervalSince1970]);   // reset randomiser with current time
	
	NSLog(@"Populating a system with economy %d, and government %d", economy, government);

	// traders
	int trading_parties = (9 - economy);			// 2 .. 9
	if (government == 0) trading_parties *= 1.25;	// 25% more trade where there are no laws!
	if (trading_parties > 0)
		trading_parties = 1 + trading_parties * (randf()+randf());   // randomize 0..2
	while (trading_parties > 15)
		trading_parties = 1 + (ranrot_rand() % trading_parties);   // reduce
	
	NSLog(@"... adding %d trading vessels", trading_parties);
	
	int skim_trading_parties = (ranrot_rand() & 3) + trading_parties * (ranrot_rand() & 31) / 120;	// about 12%
	
	NSLog(@"... adding %d sun skimming vessels", skim_trading_parties);
	
	// pirates
	int anarchy = (8 - government);
	int raiding_parties = (ranrot_rand() % anarchy) + (ranrot_rand() % anarchy) + anarchy * trading_parties / 3;	// boosted
	if (raiding_parties > 0)
		raiding_parties =  raiding_parties * (randf()+randf());   // randomize
	while (raiding_parties > 25)
		raiding_parties = 12 + (ranrot_rand() % raiding_parties);   // reduce
	
	NSLog(@"... adding %d pirate vessels", raiding_parties);

	int skim_raiding_parties = ((randf() < 0.14 * economy)? 1:0) + raiding_parties * (ranrot_rand() & 31) / 120;	// about 12%
	
	NSLog(@"... adding %d sun skim pirates", skim_raiding_parties);
	
	// bounty-hunters and the law
	int hunting_parties = (1 + government) * trading_parties / 8;
	if (government == 0) hunting_parties *= 1.25;   // 25% more bounty hunters in an anarchy
	if (hunting_parties > 0)
		hunting_parties = hunting_parties * (randf()+randf());   // randomize
	while (hunting_parties > 15)
		hunting_parties = 5 + (ranrot_rand() % hunting_parties);   // reduce
	
	//debug
	if (hunting_parties < 1)
		hunting_parties = 1;
	
	NSLog(@"... adding %d law/bounty-hunter vessels", hunting_parties);

	int skim_hunting_parties = ((randf() < 0.14 * government)? 1:0) + hunting_parties * (ranrot_rand() & 31) / 160;	// about 10%
	
	NSLog(@"... adding %d sun skim law/bounty hunter vessels", skim_hunting_parties);
	
	int thargoid_parties = 0;
	while ((ranrot_rand() % 100) < thargoidChance)
		thargoid_parties++;

	NSLog(@"... adding %d Thargoid warships", thargoid_parties);
	
	int rock_clusters = ranrot_rand() % 3;
	if (trading_parties + raiding_parties + hunting_parties < 10)
		rock_clusters += 1 + (ranrot_rand() % 3);

	rock_clusters *= 2;

	NSLog(@"... adding %d asteroid clusters", rock_clusters);

	int total_clicks = trading_parties + raiding_parties + hunting_parties + thargoid_parties + rock_clusters + skim_hunting_parties + skim_raiding_parties + skim_trading_parties;
	
	NSLog(@"... for a total of %d ships", total_clicks);
	
	Vector  v_route1 = p1_pos;
	v_route1.x -= h1_pos.x;	v_route1.y -= h1_pos.y;	v_route1.z -= h1_pos.z;
	double d_route1 = sqrt(v_route1.x*v_route1.x + v_route1.y*v_route1.y + v_route1.z*v_route1.z) - 60000.0; // -60km to avoid planet

	if (v_route1.x||v_route1.y||v_route1.z)
		v_route1 = unit_vector(&v_route1);
	else
		v_route1.z = 1.0;
	
	// add the traders to route1 (witchspace exit to space-station / planet)
	for (i = 0; (i < trading_parties)&&(!sun_gone_nova); i++)
	{
		ShipEntity  *trader_ship;
		Vector		launch_pos = h1_pos;
		if (total_clicks < 3)   total_clicks = 3;
		r = 2 + (ranrot_rand() % (total_clicks - 2));  // find an empty slot
		double ship_location = d_route1 * r / total_clicks;
		launch_pos.x += ship_location * v_route1.x + SCANNER_MAX_RANGE*((ranrot_rand() & 255)/256.0 - 0.5);
		launch_pos.y += ship_location * v_route1.y + SCANNER_MAX_RANGE*((ranrot_rand() & 255)/256.0 - 0.5);
		launch_pos.z += ship_location * v_route1.z + SCANNER_MAX_RANGE*((ranrot_rand() & 255)/256.0 - 0.5);
		trader_ship = [self getShipWithRole:@"trader"];   // retain count = 1
		if (trader_ship)
		{
			if (trader_ship->scan_class == CLASS_NOT_SET)
				[trader_ship setScanClass: CLASS_NEUTRAL];
			[trader_ship setPosition:launch_pos];
			[trader_ship setBounty:0];
			[trader_ship setCargoFlag:CARGO_FLAG_FULL_SCARCE];
			[trader_ship setStatus:STATUS_IN_FLIGHT];
			
			if (([trader_ship n_escorts] > 0)&&((ranrot_rand() % 7) < government))	// remove escorts if we feel safe
			{
				int nx = [trader_ship n_escorts] - 2 * (1 + ranrot_rand() & 3);	// remove 2,4,6, or 8 escorts
				[trader_ship setN_escorts:(nx > 0) ? nx : 0];
			}
			
			//[trader_ship setReportAImessages: (i == 0) ? YES:NO ]; // debug

			[self addEntity:trader_ship];
			[[trader_ship getAI] setStateMachine:@"route1traderAI.plist"];	// must happen after adding to the universe!
			[trader_ship release];
		}
	}
	
	// add the raiders to route1 (witchspace exit to space-station / planet)
	for (i = 0; (i < raiding_parties)&&(!sun_gone_nova); i++)
	{
		ShipEntity  *pirate_ship;
		Vector		launch_pos = h1_pos;
		if ((i > 0)&&((ranrot_rand() & 7) > wolfPackCounter))
		{
			// use last position
			launch_pos = lastPiratePosition;
			launch_pos.x += SCANNER_MAX_RANGE*((ranrot_rand() & 255)/256.0 - 0.5)*0.1; // pack them closer together
			launch_pos.y += SCANNER_MAX_RANGE*((ranrot_rand() & 255)/256.0 - 0.5)*0.1;
			launch_pos.z += SCANNER_MAX_RANGE*((ranrot_rand() & 255)/256.0 - 0.5)*0.1;
			wolfPackCounter++;
		}
		else
		{
			// random position along route1
			if (total_clicks < 3)   total_clicks = 3;
			r = 2 + (ranrot_rand() % (total_clicks - 2));  // find an empty slot
			double ship_location = d_route1 * r / total_clicks;
			launch_pos.x += ship_location * v_route1.x + SCANNER_MAX_RANGE*((ranrot_rand() & 255)/256.0 - 0.5);
			launch_pos.y += ship_location * v_route1.y + SCANNER_MAX_RANGE*((ranrot_rand() & 255)/256.0 - 0.5);
			launch_pos.z += ship_location * v_route1.z + SCANNER_MAX_RANGE*((ranrot_rand() & 255)/256.0 - 0.5);
			lastPiratePosition = launch_pos;
			wolfPackCounter = 0;
		}
		pirate_ship = [self getShipWithRole:@"pirate"];   // retain count = 1
		if (pirate_ship)
		{
			if (pirate_ship->scan_class == CLASS_NOT_SET)
				[pirate_ship setScanClass: CLASS_NEUTRAL];
			[pirate_ship setPosition:launch_pos];
			[pirate_ship setStatus:STATUS_IN_FLIGHT];
			[pirate_ship setBounty: 20 + government + wolfPackCounter + (ranrot_rand() & 7)];
			[pirate_ship setCargoFlag: CARGO_FLAG_PIRATE];

			//[pirate_ship setReportAImessages: (i == 0) ? YES:NO ]; // debug

			[self addEntity:pirate_ship];
			
			if (wolfPackCounter == 0)	// first ship
			{
				wolfPackGroup_id = [pirate_ship universal_id];
			}
			[pirate_ship setGroup_id:wolfPackGroup_id];
			
			[[pirate_ship getAI] setStateMachine:@"pirateAI.plist"];	// must happen after adding to the universe!
			[pirate_ship release];
		}
	}
	
	// add the hunters and police ships to route1 (witchspace exit to space-station / planet)
	for (i = 0; (i < hunting_parties)&&(!sun_gone_nova); i++)
	{
		ShipEntity  *hunter_ship;
		Vector		launch_pos = h1_pos;
		// random position along route1
		if (total_clicks < 3)   total_clicks = 3;
		r = 2 + (ranrot_rand() % (total_clicks - 2));  // find an empty slot
		double ship_location = d_route1 * r / total_clicks;
		launch_pos.x += ship_location * v_route1.x + SCANNER_MAX_RANGE*((ranrot_rand() & 255)/256.0 - 0.5);
		launch_pos.y += ship_location * v_route1.y + SCANNER_MAX_RANGE*((ranrot_rand() & 255)/256.0 - 0.5);
		launch_pos.z += ship_location * v_route1.z + SCANNER_MAX_RANGE*((ranrot_rand() & 255)/256.0 - 0.5);
		
		escorts_added = 0;
		
		if ((ranrot_rand() & 7) < government)
		{
			if ((ranrot_rand() & 7) + 6 <= techlevel)
				hunter_ship = [self getShipWithRole:@"interceptor"];   // retain count = 1
			else
				hunter_ship = [self getShipWithRole:@"police"];   // retain count = 1
			if (hunter_ship)
			{
				[hunter_ship setRoles:@"police"];
				if (hunter_ship->scan_class == CLASS_NOT_SET)
					[hunter_ship setScanClass: CLASS_POLICE];
				while (((ranrot_rand() & 7) < government - 2)&&([hunter_ship n_escorts] < 6))
				{
					[hunter_ship setN_escorts:[hunter_ship n_escorts] + 2];
				}
				escorts_added = [hunter_ship n_escorts];
			}
		}
		else
		{
			hunter_ship = [self getShipWithRole:@"hunter"];   // retain count = 1
			if ((hunter_ship)&&(hunter_ship->scan_class == CLASS_NOT_SET))
				[hunter_ship setScanClass: CLASS_NEUTRAL];
		}
		if (hunter_ship)
		{
			hunting_parties -= escorts_added / 2;	// reduce the number needed so we don't get huge swarms!
			
			[hunter_ship setPosition:launch_pos];
			[hunter_ship setStatus:STATUS_IN_FLIGHT];
			[hunter_ship setBounty:0];
			
			//[hunter_ship setReportAImessages: (i == 0) ? YES:NO ]; // debug

			[self addEntity:hunter_ship];
			[[hunter_ship getAI] setStateMachine:@"route1patrolAI.plist"];	// must happen after adding to the universe!

			//NSLog(@"DEBUG hunter ship %@ %@ %d has %d escorts", [hunter_ship roles], [hunter_ship name], [hunter_ship universal_id], escorts_added); 

			[hunter_ship release];
		}
	}
	
	// add the thargoids to route1 (witchspace exit to space-station / planet) clustered together
	if (total_clicks < 3)   total_clicks = 3;
	r = 2 + (ranrot_rand() % (total_clicks - 2));  // find an empty slot
	double thargoid_location = d_route1 * r / total_clicks;
	for (i = 0; (i < thargoid_parties)&&(!sun_gone_nova); i++)
	{
		ShipEntity  *thargoid_ship;
		Vector		launch_pos;
		launch_pos.x = h1_pos.x + thargoid_location * v_route1.x + SCANNER_MAX_RANGE*((ranrot_rand() & 255)/256.0 - 0.5);
		launch_pos.y = h1_pos.y + thargoid_location * v_route1.y + SCANNER_MAX_RANGE*((ranrot_rand() & 255)/256.0 - 0.5);
		launch_pos.z = h1_pos.z + thargoid_location * v_route1.z + SCANNER_MAX_RANGE*((ranrot_rand() & 255)/256.0 - 0.5);
		thargoid_ship = [self getShipWithRole:@"thargoid"];   // retain count = 1
		if (thargoid_ship)
		{
			if (thargoid_ship->scan_class == CLASS_NOT_SET)
				[thargoid_ship setScanClass: CLASS_THARGOID];
			[thargoid_ship setPosition:launch_pos];
			[thargoid_ship setBounty:100];
			[thargoid_ship setStatus:STATUS_IN_FLIGHT];
			[self addEntity:thargoid_ship];
			[[thargoid_ship getAI] setState:@"GLOBAL"];
			[thargoid_ship release];
		}
	}
	
	// add the asteroids to route1 (witchspace exit to space-station / planet) clustered together in a preset location.
	// set the system seed for random number generation
	int total_rocks = 0;
	seed_RNG_only_for_planet_description(system_seed);
	
	if (total_clicks < 3)   total_clicks = 3;
	for (i = 0; i < rock_clusters / 2 - 1; i++)
	{
		int cluster_size = 1 + (ranrot_rand() % 6) + (ranrot_rand() % 6);
		r = 2 + (gen_rnd_number() % (total_clicks - 2));  // find an empty slot
		double asteroid_location = d_route1 * r / total_clicks;
		
		Vector	launch_pos = make_vector( h1_pos.x + asteroid_location * v_route1.x, h1_pos.y + asteroid_location * v_route1.y, h1_pos.z + asteroid_location * v_route1.z);
		total_rocks += [self	scatterAsteroidsAt: launch_pos
								withVelocity: make_vector( 0, 0, 0)
								includingRockHermit: (((ranrot_rand() & 31) <= cluster_size)&&(r < total_clicks * 2 / 3)&&(!sun_gone_nova))];
	}
		
	//
	//	Now do route2 planet -> sun
	//
	
	Vector  v_route2 = s1_pos;
	v_route2.x -= p1_pos.x;	v_route2.y -= p1_pos.y;	v_route2.z -= p1_pos.z;
	double d_route2 = sqrt(magnitude2(v_route2));
	
	if (v_route2.x||v_route2.y||v_route2.z)
		v_route2 = unit_vector(&v_route1);
	else
		v_route2.x = 1.0;
	
	// add the traders to route2
	for (i = 0; (i < skim_trading_parties)&&(!sun_gone_nova); i++)
	{
		ShipEntity*	trader_ship;
		Vector		launch_pos = p1_pos;
		double		start = 4.0 * [[self planet] getRadius];
		double		end = 3.0 * [[self sun] getRadius];
		double		max_length = d_route2 - (start + end);
		double		ship_location = randf() * max_length + start;
		
//		NSLog(@"Planet: %@ \tSun: %@", [self planet], [self sun]);
//		NSLog(@"Planet collision radius: %.0fm \tSun collision radius: %.0fm \tRoute2 length: %.0fm", [[self planet] getRadius], [[self sun] getRadius], d_route2);
//		NSLog(@"start: %.0fm \tend: %.0fm", start, end);
//		NSLog(@"max length: %.0fm \tLocation is: %.0fm", max_length, ship_location);
//
		launch_pos.x += ship_location * v_route2.x + SCANNER_MAX_RANGE*((ranrot_rand() & 255)/256.0 - 0.5);
		launch_pos.y += ship_location * v_route2.y + SCANNER_MAX_RANGE*((ranrot_rand() & 255)/256.0 - 0.5);
		launch_pos.z += ship_location * v_route2.z + SCANNER_MAX_RANGE*((ranrot_rand() & 255)/256.0 - 0.5);
		trader_ship = [self getShipWithRole:@"sunskim-trader"];   // retain count = 1
		if (trader_ship)
		{
			[trader_ship setRoles:@"trader"];	// set this to allow escorts to pair with the ship
			if ((trader_ship)&&(trader_ship->scan_class == CLASS_NOT_SET))
				[trader_ship setScanClass: CLASS_NEUTRAL];
			[trader_ship setPosition:launch_pos];
			[trader_ship setBounty:0];
			[trader_ship setCargoFlag:CARGO_FLAG_FULL_PLENTIFUL];
			[trader_ship setStatus:STATUS_IN_FLIGHT];
			
			if (([trader_ship n_escorts] > 0)&&((ranrot_rand() % 7) < government))	// remove escorts if we feel safe
			{
				int nx = [trader_ship n_escorts] - 2 * (1 + ranrot_rand() & 3);	// remove 2,4,6, or 8 escorts
				[trader_ship setN_escorts:(nx > 0) ? nx : 0];
			}
			
			[self addEntity:trader_ship];
			[[trader_ship getAI] setStateMachine:@"route2sunskimAI.plist"];	// must happen after adding to the universe!

	//		[trader_ship setReportAImessages: (i == 0) ? YES:NO ]; // debug

			[trader_ship release];
		}
	}
	
	// add the raiders to route2
	for (i = 0; (i < skim_raiding_parties)&&(!sun_gone_nova); i++)
	{
		ShipEntity*	pirate_ship;
		Vector		launch_pos = p1_pos;
		if ((i > 0)&&((ranrot_rand() & 7) > wolfPackCounter))
		{
			// use last position
			launch_pos = lastPiratePosition;
			launch_pos.x += SCANNER_MAX_RANGE*((ranrot_rand() & 255)/256.0 - 0.5)*0.1; // pack them closer together
			launch_pos.y += SCANNER_MAX_RANGE*((ranrot_rand() & 255)/256.0 - 0.5)*0.1;
			launch_pos.z += SCANNER_MAX_RANGE*((ranrot_rand() & 255)/256.0 - 0.5)*0.1;
			wolfPackCounter++;
		}
		else
		{
			// random position along route2
			double		start = 4.0 * [[self planet] getRadius];
			double		end = 3.0 * [[self sun] getRadius];
			double		max_length = d_route2 - (start + end);
			double		ship_location = randf() * max_length + start;
			launch_pos.x += ship_location * v_route2.x + SCANNER_MAX_RANGE*((ranrot_rand() & 255)/256.0 - 0.5);
			launch_pos.y += ship_location * v_route2.y + SCANNER_MAX_RANGE*((ranrot_rand() & 255)/256.0 - 0.5);
			launch_pos.z += ship_location * v_route2.z + SCANNER_MAX_RANGE*((ranrot_rand() & 255)/256.0 - 0.5);
			lastPiratePosition = launch_pos;
			wolfPackCounter = 0;
		}
		pirate_ship = [self getShipWithRole:@"pirate"];   // retain count = 1
		if (pirate_ship)
		{
			if (pirate_ship->scan_class == CLASS_NOT_SET)
				[pirate_ship setScanClass: CLASS_NEUTRAL];
			[pirate_ship setPosition: launch_pos];
			[pirate_ship setStatus: STATUS_IN_FLIGHT];
			[pirate_ship setBounty: 20 + government + wolfPackCounter + (ranrot_rand() % 7)];
			[pirate_ship setCargoFlag: CARGO_FLAG_PIRATE];
			
	//		[pirate_ship setReportAImessages: (i == 0) ? YES:NO ]; // debug

			[self addEntity:pirate_ship];
			
			if (wolfPackCounter == 0)	// first ship
				wolfPackGroup_id = [pirate_ship universal_id];

			[pirate_ship setGroup_id:wolfPackGroup_id];
			
			[[pirate_ship getAI] setStateMachine:@"pirateAI.plist"];	// must happen after adding to the universe!
			[pirate_ship release];
		}
	}
	
	// add the hunters and police ships to route2
	for (i = 0; (i < skim_hunting_parties)&&(!sun_gone_nova); i++)
	{
		ShipEntity*	hunter_ship;
		Vector		launch_pos = p1_pos;
		double		start = 4.0 * [[self planet] getRadius];
		double		end = 3.0 * [[self sun] getRadius];
		double		max_length = d_route2 - (start + end);
		double		ship_location = randf() * max_length + start;

		launch_pos.x += ship_location * v_route2.x + SCANNER_MAX_RANGE*((ranrot_rand() & 255)/256.0 - 0.5);
		launch_pos.y += ship_location * v_route2.y + SCANNER_MAX_RANGE*((ranrot_rand() & 255)/256.0 - 0.5);
		launch_pos.z += ship_location * v_route2.z + SCANNER_MAX_RANGE*((ranrot_rand() & 255)/256.0 - 0.5);
		
		escorts_added = 0;
		
		if ((ranrot_rand() & 7) < government)
		{
			if ((ranrot_rand() & 7) + 6 <= techlevel)
				hunter_ship = [self getShipWithRole:@"interceptor"];   // retain count = 1
			else
				hunter_ship = [self getShipWithRole:@"police"];   // retain count = 1
			if (hunter_ship)
			{
				[hunter_ship setRoles:@"police"];
				if (hunter_ship->scan_class == CLASS_NOT_SET)
					[hunter_ship setScanClass: CLASS_POLICE];
				while (((ranrot_rand() & 7) < government - 2)&&([hunter_ship n_escorts] < 6))
				{
					[hunter_ship setN_escorts:[hunter_ship n_escorts] + 2];
				}
				escorts_added = [hunter_ship n_escorts];
			}
		}
		else
		{
			hunter_ship = [self getShipWithRole:@"hunter"];   // retain count = 1
			if ((hunter_ship)&&(hunter_ship->scan_class == CLASS_NOT_SET))
				[hunter_ship setScanClass: CLASS_NEUTRAL];
		}
		
		if (hunter_ship)
		{
			[hunter_ship setPosition:launch_pos];
			[hunter_ship setStatus:STATUS_IN_FLIGHT];
			[hunter_ship setBounty:0];
			
	//		[hunter_ship setReportAImessages: (i == 0) ? YES:NO ]; // debug

			[self addEntity:hunter_ship];
			[[hunter_ship getAI] setStateMachine:@"route2patrolAI.plist"];	// must happen after adding to the universe!
			
			if (randf() > 0.50)	// 50% chance
				[[hunter_ship getAI] setState:@"HEAD_FOR_PLANET"];
			else
				[[hunter_ship getAI] setState:@"HEAD_FOR_SUN"];
			
			[hunter_ship release];
		}
	}

	// add the asteroids to route2 clustered together in a preset location.
	seed_RNG_only_for_planet_description(system_seed);	// set the system seed for random number generation
	
	if (total_clicks < 3)   total_clicks = 3;
	for (i = 0; i < rock_clusters / 2 + 1; i++)
	{
		double	start = 6.0 * [[self planet] getRadius];
		double	end = 4.5 * [[self sun] getRadius];
		double	max_length = d_route2 - (start + end);
		double	asteroid_location = randf() * max_length + start;
		int cluster_size = 1 + (ranrot_rand() % 6) + (ranrot_rand() % 6);
		
		Vector	launch_pos = make_vector( p1_pos.x + asteroid_location * v_route2.x, p1_pos.y + asteroid_location * v_route2.y, p1_pos.z + asteroid_location * v_route2.z);
		total_rocks += [self	scatterAsteroidsAt: launch_pos
								withVelocity: make_vector( 0, 0, 0)
								includingRockHermit: (((ranrot_rand() & 31) <= cluster_size)&&(asteroid_location > 0.33 * max_length)&&(!sun_gone_nova))];
	}
	
}

- (int) scatterAsteroidsAt:(Vector) spawnPos withVelocity:(Vector) spawnVel includingRockHermit:(BOOL) spawnHermit
{
	int rocks = 0;
	Vector		launch_pos;
	int i;
	int cluster_size = 1 + (ranrot_rand() % 6) + (ranrot_rand() % 6);
	for (i = 0; i < cluster_size; i++)
	{
		ShipEntity*	asteroid;
		int n_rocks = 2 + (ranrot_rand() % 5);
		launch_pos.x = spawnPos.x + SCANNER_MAX_RANGE*(gen_rnd_number()/256.0 - 0.5);
		launch_pos.y = spawnPos.y + SCANNER_MAX_RANGE*(gen_rnd_number()/256.0 - 0.5);
		launch_pos.z = spawnPos.z + SCANNER_MAX_RANGE*(gen_rnd_number()/256.0 - 0.5);
		asteroid = [self getShipWithRole:@"asteroid"];   // retain count = 1
		if (asteroid)
		{
			if (asteroid->scan_class == CLASS_NOT_SET)
				[asteroid setScanClass: CLASS_ROCK];
			[asteroid setPosition:launch_pos];
			[asteroid setVelocity:spawnVel];
			[asteroid setStatus:STATUS_IN_FLIGHT];
			[asteroid setNumberOfMinedRocks: n_rocks];
			[self addEntity:asteroid];
			[[asteroid getAI] setState:@"GLOBAL"];
			[asteroid release];
			rocks++;
		}
	}
	// rock-hermit : chance is related to the number of asteroids
	// hermits are placed near to other asteroids for obvious reasons
	//
	// hermits should not be placed too near the planet-end of route2,
	// or ships will dock there rather than at the main station !
	//
	if (spawnHermit)
	{
		//debug
		//NSLog(@"DEBUG ... adding rock-hermit");
		StationEntity*	hermit;
		launch_pos.x = spawnPos.x + 0.5 * SCANNER_MAX_RANGE * ((ranrot_rand() & 255)/256.0 - 0.5);
		launch_pos.y = spawnPos.y + 0.5 * SCANNER_MAX_RANGE * ((ranrot_rand() & 255)/256.0 - 0.5);
		launch_pos.z = spawnPos.z + 0.5 * SCANNER_MAX_RANGE * ((ranrot_rand() & 255)/256.0 - 0.5);
		hermit = (StationEntity *)[self getShipWithRole:@"rockhermit"];   // retain count = 1
		if (hermit)
		{
			if (hermit->scan_class == CLASS_NOT_SET)
				[hermit setScanClass: CLASS_ROCK];
			[hermit setPosition:launch_pos];
			[hermit setVelocity:spawnVel];
			[hermit setStatus:STATUS_IN_FLIGHT];
			[self addEntity:hermit];
			[[hermit getAI] setState:@"GLOBAL"];
			[hermit release];
		}
	}
	return rocks;
}

- (void) addShipWithRole:(NSString *) desc nearRouteOneAt:(double) route_fraction
{
	// adds a ship within scanner range of a point on route 1
	//
	Entity* the_station = [self station];
	if (!the_station)
		return;
	Vector  h1_pos = [self getWitchspaceExitPosition];
	Vector  launch_pos = the_station->position;
	launch_pos.x -= h1_pos.x;		launch_pos.y -= h1_pos.y;		launch_pos.z -= h1_pos.z;
	launch_pos.x *= route_fraction; launch_pos.y *= route_fraction; launch_pos.z *= route_fraction;
	launch_pos.x += h1_pos.x;		launch_pos.y += h1_pos.y;		launch_pos.z += h1_pos.z;
	//
	launch_pos.x += SCANNER_MAX_RANGE*(randf() - randf());
	launch_pos.y += SCANNER_MAX_RANGE*(randf() - randf());
	launch_pos.z += SCANNER_MAX_RANGE*(randf() - randf());
	//
	ShipEntity  *ship;
	ship = [self getShipWithRole:desc];   // retain count = 1
	if (ship)
	{
		if ((ship->scan_class == CLASS_NO_DRAW)||(ship->scan_class == CLASS_NOT_SET))
			[ship setScanClass: CLASS_NEUTRAL];
		[ship setPosition:launch_pos];
		[self addEntity:ship];
		[[ship getAI] setState:@"GLOBAL"];	// must happen after adding to the universe!
		
		[ship setStatus:STATUS_IN_FLIGHT];	// or ships that were 'demo' ships become invisible!
		
	//	NSLog(@"DEBUG added %@ %@ %d to universe at (%.0f,%.0f,%.0f)", ship, [ship name], [ship universal_id],
	//		ship->position.x, ship->position.y, ship->position.z);
		
		[ship release];
	}
	//
}

- (Vector) coordinatesForPosition:(Vector) pos withCoordinateSystem:(NSString *) system returningScalar:(GLfloat*) my_scalar
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
		
		in witchspace (== no sun) coordinates are absolute irrespective of the system used
		
	*/
	//
	NSString* l_sys = [system lowercaseString];
	if ([l_sys length] != 3)
		return make_vector(0,0,0);
	PlanetEntity* the_planet = [self planet];
	PlanetEntity* the_sun = [self sun];
	if ((!the_planet)||(!the_sun))
	{
//		NSLog(@"NO ERROR - Universe coordinatesForPosition:withCoordinateSystem: in system with no sun or planet returned as an absolute position");
		*my_scalar = 1.0;
		return pos;
	}
	Vector  w_pos = [self getWitchspaceExitPosition];
	Vector  p_pos = the_planet->position;
	Vector  s_pos = the_sun->position;
	//
	const char* c_sys = [l_sys lossyCString];
	Vector p0 = make_vector(1,0,0);
	Vector p1 = make_vector(0,1,0);
	Vector p2 = make_vector(0,0,1);
	
//	NSLog(@"DEBUG addShipAt (system %s)", c_sys);
	
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
					return make_vector(0,0,0);
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
					return make_vector(0,0,0);
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
					return make_vector(0,0,0);
			}
			break;
		default:
			return make_vector(0,0,0);
	}
	Vector k = make_vector(p1.x - p0.x, p1.y - p0.y, p1.z - p0.z);
	if (k.x||k.y||k.z)
		k = unit_vector(&k);	//	'forward'
	else
		k.z = 1.0;
	Vector v = make_vector(p2.x - p0.x, p2.y - p0.y, p2.z - p0.z);
	if (v.x||v.y||v.z)
		v = unit_vector(&v);		//	temporary vector in plane of 'forward' and 'right'
	else
		v.x = 1.0;
	Vector j = cross_product( k, v);	// 'up'
	Vector i = cross_product( j, k);	// 'right'
	GLfloat scalar = 1.0;
	switch (c_sys[2])
	{
		case 'p':
			scalar = ([self planet])? [self planet]->collision_radius: 5000;	break;
		case 's':
			scalar = ([self sun])? [self sun]->collision_radius: 100000;	break;
		case 'u':
			scalar = sqrt(magnitude2(make_vector(p1.x - p0.x, p1.y - p0.y, p1.z - p0.z)));	break;
		case 'm':
			scalar = 1.0;	break;
		default:
			return make_vector(0,0,0);
	}
	*my_scalar = scalar;
	
	// result = p0 + ijk
	Vector result = p0;	// origin
	result.x += scalar * (pos.x * i.x + pos.y * j.x + pos.z * k.x);
	result.y += scalar * (pos.x * i.y + pos.y * j.y + pos.z * k.y);
	result.z += scalar * (pos.x * i.z + pos.y * j.z + pos.z * k.z);
	//
	return result;
}

- (NSString *) expressPosition:(Vector) pos inCoordinateSystem:(NSString *) system
{
	//
	NSString* l_sys = [system lowercaseString];
	if ([l_sys length] != 3)
		return nil;
	PlanetEntity* the_planet = [self planet];
	PlanetEntity* the_sun = [self sun];
	if ((!the_planet)||(!the_sun))
	{
//		NSLog(@"NO ERROR - Universe coordinatesForPosition:withCoordinateSystem: in system with no sun or planet returned as an absolute position");
		return [NSString stringWithFormat:@"%@ %.2f %.2f %.2f", system, pos.x, pos.y, pos.z];
	}
	Vector  w_pos = [self getWitchspaceExitPosition];
	Vector  p_pos = the_planet->position;
	Vector  s_pos = the_sun->position;
	//
	const char* c_sys = [l_sys lossyCString];
	Vector p0 = make_vector(1,0,0);
	Vector p1 = make_vector(0,1,0);
	Vector p2 = make_vector(0,0,1);
	
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
					return nil;
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
					return nil;
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
					return nil;
			}
			break;
		default:
			return nil;
	}
	Vector k = make_vector(p1.x - p0.x, p1.y - p0.y, p1.z - p0.z);
	if (k.x||k.y||k.z)
		k = unit_vector(&k);			//	'z' axis in m
	else
		k.z = 1.0;
	Vector v = make_vector(p2.x - p0.x, p2.y - p0.y, p2.z - p0.z);
	if (v.x||v.y||v.z)
		v = unit_vector(&v);		//	temporary vector in plane of 'forward' and 'right'
	else
		v.x = 1.0;
	Vector j = cross_product( k, v);	// 'y' axis in m
	Vector i = cross_product( j, k);	// 'x' axis in m
	GLfloat scalar = 1.0;
	switch (c_sys[2])
	{
		case 'p':
			scalar = 1.0 / (([self planet])? [self planet]->collision_radius: 5000);	break;
		case 's':
			scalar = 1.0 / (([self sun])? [self sun]->collision_radius: 100000);	break;
		case 'u':
			scalar = 1.0 / sqrt(magnitude2(make_vector(p1.x - p0.x, p1.y - p0.y, p1.z - p0.z)));	break;
		case 'm':
			scalar = 1.0;	break;
		default:
			return nil;
	}
	
	// result = p0 + ijk
	Vector r_pos = make_vector( pos.x - p0.x, pos.y - p0.y, pos.z - p0.z);
	Vector result = make_vector(	scalar * (r_pos.x * i.x + r_pos.y * i.y + r_pos.z * i.z),
									scalar * (r_pos.x * j.x + r_pos.y * j.y + r_pos.z * j.z),
									scalar * (r_pos.x * k.x + r_pos.y * k.y + r_pos.z * k.z) ); // scalar * dot_products
	//
	return [NSString stringWithFormat:@"%@ %.2f %.2f %.2f", system, result.x, result.y, result.z];
}

- (BOOL) addShipWithRole:(NSString *) desc nearPosition:(Vector) pos withCoordinateSystem:(NSString *) system
{
	// initial position
	GLfloat scalar = 1.0;
	Vector launch_pos = [self coordinatesForPosition:pos withCoordinateSystem:system returningScalar:&scalar];
	//	randomise
	GLfloat rfactor = scalar;
	if (rfactor > SCANNER_MAX_RANGE)
		rfactor = SCANNER_MAX_RANGE;
	if (rfactor < 1000)
		rfactor = 1000;
	launch_pos.x += rfactor*(randf() - randf());
	launch_pos.y += rfactor*(randf() - randf());
	launch_pos.z += rfactor*(randf() - randf());
	
//	NSLog(@"DEBUG POSITION SET (%.1f, %.1f, %.1f)", launch_pos.x, launch_pos.y, launch_pos.z);
	
	//
	ShipEntity  *ship;
	ship = [self getShipWithRole:desc];   // retain count = 1
	if (ship)
	{
		if ((ship->scan_class == CLASS_NO_DRAW)||(ship->scan_class == CLASS_NOT_SET))
			[ship setScanClass: CLASS_NEUTRAL];
		[ship setPosition:launch_pos];
		[self addEntity:ship];
		[[ship getAI] setState:@"GLOBAL"];	// must happen after adding to the universe!
		[ship setStatus:STATUS_IN_FLIGHT];	// or ships that were 'demo' ships become invisible!
		[ship release];
		return YES;
	}
	//
	return NO;
}

- (BOOL) addShips:(int) howMany withRole:(NSString *) desc atPosition:(Vector) pos withCoordinateSystem:(NSString *) system
{
	// initial bounding box
	GLfloat scalar = 1.0;
	Vector launch_pos = [self coordinatesForPosition:pos withCoordinateSystem:system returningScalar:&scalar];
	GLfloat distance_from_center = 0.0;
	Vector v_from_center, ship_pos;
	Vector ship_positions[howMany];
	int i = 0;
	int	scale_up_after = 0;
	int	current_shell = 0;
	GLfloat	walk_factor = 2.0;
	while (i < howMany)
	{
		ShipEntity  *ship;
		ship = [self getShipWithRole:desc];   // retain count = 1
		if (!ship)
			return NO;
		//
		GLfloat safe_distance2 = 2.0 * ship->collision_radius * ship->collision_radius * PROXIMITY_WARN_DISTANCE2;
		//
		BOOL safe;
		//
		int limit_count = 8;
		//
		v_from_center = make_vector( 0, 0, 0);
		do
		{
			do
			{
				v_from_center.x += walk_factor * (randf() - 0.5);
				v_from_center.y += walk_factor * (randf() - 0.5);
				v_from_center.z += walk_factor * (randf() - 0.5);	// drunkards walk
			} while ((v_from_center.x == 0.0)&&(v_from_center.y == 0.0)&&(v_from_center.z == 0.0));
			v_from_center = unit_vector(&v_from_center);	// guaranteed non-zero
						
			ship_pos = make_vector(	launch_pos.x + distance_from_center * v_from_center.x,
									launch_pos.y + distance_from_center * v_from_center.y,
									launch_pos.z + distance_from_center * v_from_center.z);
			
			// check this position against previous ship positions in this shell
			safe = YES;
			int j = i - 1;
			while (safe && ( j >= current_shell))
			{
				safe = (safe && (distance2( ship_pos, ship_positions[j]) > safe_distance2));
				j--;
			}
			if (!safe)
			{
//				NSLog(@"DEBUG - AddShips %d/%d : proposed position clashed with ship %d", i, howMany, j + 1);
				limit_count--;
				if (!limit_count)	// give up and expand the shell
				{
//					NSLog(@"DEBUG - limit_count depleted, expanding area...");
					limit_count = 8;
					distance_from_center += sqrt(safe_distance2);	// expand to the next distance
				}
			}
			
			
		} while (!safe);
		//
		if ((ship->scan_class == CLASS_NO_DRAW)||(ship->scan_class == CLASS_NOT_SET))
			[ship setScanClass: CLASS_NEUTRAL];
		[ship setPosition:ship_pos];
		//
		Quaternion qr;
		quaternion_set_random(&qr);
		[ship setQRotation:qr];
		//
		[self addEntity:ship];
		[[ship getAI] setState:@"GLOBAL"];	// must happen after adding to the universe!
		[ship setStatus:STATUS_IN_FLIGHT];	// or ships that were 'demo' ships become invisible!
		[ship release];
		//
//		NSLog(@"DEBUG - AddShips %d/%d : ship added successfully %.1fm from the requested position",
//			i, howMany, distance_from_center);
		//
		ship_positions[i] = ship_pos;
		i++;
		if (i > scale_up_after)
		{
			current_shell = i;
			scale_up_after += 1 + 2 * i;
			distance_from_center += sqrt(safe_distance2);	// fill the next shell
			
//			NSLog(@"DEBUG - AddShips %d/%d : Filling a shell of radius %.2fm from the requested position with the next %d ships",
//				i, howMany, distance_from_center, 1 + scale_up_after - i);
		}
	}
	return YES;
}

- (BOOL) addShips:(int) howMany withRole:(NSString *) desc nearPosition:(Vector) pos withCoordinateSystem:(NSString *) system
{
	// initial bounding box
	GLfloat scalar = 1.0;
	Vector launch_pos = [self coordinatesForPosition:pos withCoordinateSystem:system returningScalar:&scalar];
	GLfloat rfactor = scalar;
	if (rfactor > SCANNER_MAX_RANGE)
		rfactor = SCANNER_MAX_RANGE;
	if (rfactor < 1000)
		rfactor = 1000;
	BoundingBox	launch_bbox;
	bounding_box_reset_to_vector( &launch_bbox, make_vector( launch_pos.x - rfactor, launch_pos.y - rfactor, launch_pos.z - rfactor));
	bounding_box_add_xyz( &launch_bbox, launch_pos.x + rfactor, launch_pos.y + rfactor, launch_pos.z + rfactor);
	
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
		GLfloat lx = bbox.max_x - bbox.min_x;
		GLfloat ly = bbox.max_y - bbox.min_y;
		GLfloat lz = bbox.max_z - bbox.min_z;
		BoundingBox bbox0 = bbox;
		BoundingBox bbox1 = bbox;
		if ((lx > lz)&&(lx > ly))	// longest dimension is x
		{
			bbox0.min_x += 0.5 * lx;
			bbox1.max_x -= 0.5 * lx;
		}
		else
		{
			if (ly > lz)	// longest dimension is y
			{
				bbox0.min_y += 0.5 * ly;
				bbox1.max_y -= 0.5 * ly;
			}
			else			// longest dimension is z
			{
				bbox0.min_z += 0.5 * lz;
				bbox1.max_z -= 0.5 * lz;
			}
		}
		// place half the ships into each bounding box
		return ([self addShips: h0 withRole: desc intoBoundingBox: bbox0] && [self addShips: h1 withRole: desc intoBoundingBox: bbox1]);
	}
	
	//	randomise within the bounding box (biased towards the center of the box)
	Vector pos = make_vector(bbox.min_x, bbox.min_y, bbox.min_z);
	pos.x += 0.5 * (randf() + randf()) * (bbox.max_x - bbox.min_x);
	pos.y += 0.5 * (randf() + randf()) * (bbox.max_y - bbox.min_y);
	pos.z += 0.5 * (randf() + randf()) * (bbox.max_z - bbox.min_z);
	
	//
	ShipEntity  *ship;
	ship = [self getShipWithRole:desc];   // retain count = 1
	if (ship)
	{
		if ((ship->scan_class == CLASS_NO_DRAW)||(ship->scan_class == CLASS_NOT_SET))
			[ship setScanClass: CLASS_NEUTRAL];
		[ship setPosition: pos];
		[self addEntity:ship];
		[[ship getAI] setState:@"GLOBAL"];	// must happen after adding to the universe!
		[ship setStatus:STATUS_IN_FLIGHT];	// or ships that were 'demo' ships become invisible!
		[ship release];
		//
		return YES;	// success at last!
	}
	return NO;
}

- (BOOL) spawnShip:(NSString *) shipdesc
{
	ShipEntity* ship;
	NSDictionary* shipdict = nil;
	
	NS_DURING	
		shipdict = [self getDictionaryForShip:shipdesc];	// handle OOLITE_EXCEPTION_SHIP_NOT_FOUND
	NS_HANDLER
		if ([[localException name] isEqual: OOLITE_EXCEPTION_SHIP_NOT_FOUND])
		{
			NSLog(@"***** Oolite Exception : '%@' in [Universe spawnShip: %@ ] *****", [localException reason], shipdesc);
			shipdict = nil;
		}
		else
			[localException raise];
	NS_ENDHANDLER
	
	if (!shipdict)
		return NO;
	
	ship = [self getShip:shipdesc];	// retain count is 1
	
	if (!ship)
		return NO;
	
	// set any spawning characteristics
	NSDictionary* spawndict = (NSDictionary*)[shipdict objectForKey:@"spawn"];
	// position
	if ([spawndict objectForKey:@"position"])
	{
		Vector pos = make_vector( 0, 0, 0);
		NSString* positionString = (NSString*)[spawndict objectForKey:@"position"];
		NSArray* positiontokens = [ResourceManager scanTokensFromString:positionString];
		if ([positiontokens count] == 4)
		{
			GLfloat scalar;
			pos = make_vector(	[[positiontokens objectAtIndex:1] floatValue],
								[[positiontokens objectAtIndex:2] floatValue],
								[[positiontokens objectAtIndex:3] floatValue]);
			pos = [self coordinatesForPosition:pos withCoordinateSystem:(NSString *)[positiontokens objectAtIndex:0] returningScalar:&scalar];
		}
		[ship setPosition:pos];
	}
	// facing_position
	if ([spawndict objectForKey:@"facing_position"])
	{
		Vector pos, rpos;
		Vector spos = [ship getPosition];
		Quaternion q1;
		NSString* positionString = (NSString*)[spawndict objectForKey:@"facing_position"];
		NSArray* positiontokens = [ResourceManager scanTokensFromString:positionString];
		if ([positiontokens count] == 4)
		{
			GLfloat scalar;
			pos = make_vector(	[[positiontokens objectAtIndex:1] floatValue],
								[[positiontokens objectAtIndex:2] floatValue],
								[[positiontokens objectAtIndex:3] floatValue]);
			rpos = [self coordinatesForPosition:pos withCoordinateSystem:(NSString *)[positiontokens objectAtIndex:0] returningScalar:&scalar];
		}
		rpos.x -= spos.x;	rpos.y -= spos.y;	rpos.z -= spos.z; // position relative to ship
		if (rpos.x || rpos.y || rpos.z)
		{
			rpos = unit_vector(&rpos);
			q1 = quaternion_rotation_between( make_vector(0,0,1), rpos);
			[ship setQRotation:q1];
		}
	}

	[self addEntity:ship];
	[[ship getAI] setState:@"GLOBAL"];	// must happen after adding to the universe!
	[ship setStatus:STATUS_IN_FLIGHT];	// or ships that were 'demo' ships become invisible!
	[ship release];

	return YES;
}


- (void) witchspaceShipWithRole:(NSString *) desc
{
	// adds a ship exiting witchspace (corollary of when ships leave the system)
	ShipEntity  *ship;
	ship = [self getShipWithRole:desc];   // retain count = 1
	if (ship)
	{
		if ((ship->scan_class == CLASS_NO_DRAW)||(ship->scan_class == CLASS_NOT_SET))
			[ship setScanClass: CLASS_NEUTRAL];
		if ([desc isEqual:@"trader"])
		{
			[ship setCargoFlag: CARGO_FLAG_FULL_SCARCE];
			if (randf() > 0.10)
				[[ship getAI] setStateMachine:@"route1traderAI.plist"];
			else
				[[ship getAI] setStateMachine:@"route2sunskimAI.plist"];	// route3 really, but the AI's the same
		}
		if ([desc isEqual:@"pirate"])
		{
			[ship setCargoFlag: CARGO_FLAG_PIRATE];
			[ship setBounty: (ranrot_rand() & 7) + (ranrot_rand() & 7) + ((randf() < 0.05)? 63 : 23)];	// they already have a price on their heads
		}
		[ship setUniverse:self];
		[ship leaveWitchspace];				// gets added to the universe here!
		[[ship getAI] setState:@"GLOBAL"];	// must happen after adding to the universe!
		[ship setStatus:STATUS_IN_FLIGHT];	// or ships may not werk rite d'uh!

		[ship release];
	}
}

- (void) spawnShipWithRole:(NSString *) desc near:(Entity *) entity
{
	// adds a ship within the collision radius of the other entity
	if (!entity)
		return;
	ShipEntity  *ship;
	Vector		spawn_pos = entity->position;
	Quaternion	spawn_q;	quaternion_set_random(&spawn_q);
	Vector		vf = vector_forward_from_quaternion(spawn_q);
	GLfloat		offset = (randf() + randf()) * entity->collision_radius;
	spawn_pos.x += offset * vf.x;	spawn_pos.y += offset * vf.y;	spawn_pos.z += offset * vf.z;
	ship = [self getShipWithRole:desc];   // retain count = 1
	if (ship)
	{
		if (ship->scan_class <= CLASS_NO_DRAW)
			[ship setScanClass: CLASS_NEUTRAL];
		[ship setPosition:spawn_pos];
		[ship setQRotation:spawn_q];
		[self addEntity:ship];
		[[ship getAI] setState:@"GLOBAL"];	// must happen after adding to the universe!
		[ship setStatus:STATUS_IN_FLIGHT];
		[ship release];
	}
}

- (void) set_up_break_pattern:(Vector) pos quaternion:(Quaternion) q
{
	int				i;
	RingEntity*		ring;
	
	[self setViewDirection:VIEW_FORWARD];
	
	q.w = -q.w;		// reverse the quaternion because this is from the player's viewpoint
	
	Vector			v = vector_forward_from_quaternion(q);
		
	for (i = 1; i < 11; i++)
	{
		ring = (RingEntity *)[self recycledOrNew:@"RingEntity"];	// alloc retains!
		[ring setPosition:pos.x+v.x*i*50.0:pos.y+v.y*i*50.0:pos.z+v.z*i*50.0]; // ahead of the player
		[ring setQRotation:q];
		[ring setVelocity:v];
		[ring setLifetime:i*50.0];
		[ring setScanClass: CLASS_NO_DRAW];
		[self addEntity:ring]; // [entities addObject:ring];
		breakPatternCounter++;
		[ring release];
    }
}

- (void) game_over
{
	PlayerEntity*   player = (PlayerEntity *)[[self entityZero] retain];
	int i;
	//
	[self removeAllEntitiesExceptPlayer:NO];	// don't want to restore afterwards
	//
	[player set_up];						//reset the player
	[player setUpShipFromDictionary:[self getDictionaryForShip:[player ship_desc]]];	// ship_desc is the standard Cobra at this point
	//
	[[(MyOpenGLView *)gameView gameController] loadPlayerIfRequired];
	//
	galaxy_seed = [player galaxy_seed];
	system_seed = [self findSystemAtCoords:[player galaxy_coordinates] withGalaxySeed:galaxy_seed];
	
	// systems
	Random_Seed g_seed = galaxy_seed;
	for (i = 0; i < 256; i++)
	{
		systems[i] = g_seed;
		if (system_names[i])	[system_names[i] release];
		system_names[i] = [[self getSystemName:g_seed] retain];
		rotate_seed(&g_seed);
		rotate_seed(&g_seed);
		rotate_seed(&g_seed);
		rotate_seed(&g_seed);
	}
	//
	if (![self station])
		[self set_up_space];
	//
	if (![[self station] localMarket])
		[[self station] initialiseLocalMarketWithSeed:system_seed andRandomFactor:[player random_factor]];
	//
	[player setStatus:STATUS_DOCKED];
	[player setGuiToStatusScreen];
	[self setViewDirection:VIEW_DOCKED];
	displayGUI = YES;
	//
	[player release];    
	//
}

- (void) set_up_intro1
{
	ShipEntity		*ship;
	Quaternion		q2;
	q2.x = 0.0;   q2.y = 0.0;   q2.z = 0.0; q2.w = 1.0;
	quaternion_rotate_about_y(&q2,PI);
	//
	// in status demo : draw ships and display text
	//
	[[self entityZero] setStatus:STATUS_DEMO];
	displayGUI = YES;
	//
	/*- cobra -*/
	ship = [self getShip:PLAYER_SHIP_DESC];   // retain count = 1   // shows the cobra-player ship
	if (ship)
	{
		[ship setStatus:STATUS_DEMO];
		[ship setQRotation:q2];
		[ship setPosition:0.0:0.0: 3.6 * ship->actual_radius];  // 250m ahead
		
		//NSLog(@"demo ship %@ has collision radius %.1f 250.0/cr = %.1f", [ship name], ship->collision_radius, 250.0/ship->collision_radius);
		
		[ship setScanClass: CLASS_NO_DRAW];
		[ship setRoll:PI/5.0];
		[ship setPitch:PI/10.0];
		[[ship getAI] setStateMachine:@"nullAI.plist"];
		[self addEntity:ship];
		
		demo_ship = ship;
		
		[ship release];
	}
	//
	[self setViewDirection:VIEW_DOCKED];
	displayGUI = YES;
	//
	//
}

- (void) set_up_intro2
{
	ShipEntity		*ship;
	Quaternion		q2;
	q2.x = 0.0;   q2.y = 0.0;   q2.z = 0.0; q2.w = 1.0;
	quaternion_rotate_about_y(&q2,PI);
	//
	// in status demo draw ships and display text
	//
	[self removeDemoShips];
	[[self entityZero] setStatus:STATUS_DEMO];
	displayGUI = YES;
	//
	/*- demo ships -*/
	demo_ship_index = 0;
	ship = [self getShip:[demo_ships objectAtIndex:0]];   // retain count = 1
	if (ship)
	{
		[ship setQRotation:q2];
		[ship setPosition:0.0:0.0: 3.6 * ship->actual_radius];
		
		//NSLog(@"demo ship %@ has collision radius %.1f 250.0/cr = %.1f", [ship name], ship->collision_radius, 250.0/ship->collision_radius);
		
		[ship setScanClass: CLASS_NO_DRAW];
		[ship setRoll:PI/5.0];
		[ship setPitch:PI/10.0];
		[[ship getAI] setStateMachine:@"nullAI.plist"];
		[self addEntity:ship];
		
		// set status here because addEntity may affect status
		[ship setStatus:STATUS_DEMO];
		
		demo_ship = ship;
		
		[gui setText:[ship name] forRow:19 align:GUI_ALIGN_CENTER];
		[gui setColor:[NSColor whiteColor] forRow:19];
		
		[ship release];
	}
	//
	[self setViewDirection:VIEW_DOCKED];
	displayGUI = YES;
	//
	demo_stage = DEMO_SHOW_THING;
	demo_stage_time = universal_time + 3.0;
	//
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

- (StationEntity *) station
{
	if (cachedStation)
		return cachedStation;
	
	if (![self entityForUniversalID:station])
	{
		int i;
		station = NO_TARGET;
		cachedStation = nil;
		int ent_count = n_entities;
		int station_count = 0;
		Entity* my_entities[ent_count];
		for (i = 0; i < ent_count; i++)
			if (sortedEntities[i]->isStation)
				my_entities[station_count++] = [sortedEntities[i] retain];
		for (i = 0; ((i < station_count)&&(station == NO_TARGET)) ; i++)
		{
			Entity* thing = my_entities[i];
			if (thing->scan_class == CLASS_STATION)
			{
				cachedStation = (StationEntity *)thing;
				station = [thing universal_id];
			}
		}
		for (i = 0; i < station_count; i++)
			[my_entities[i] release];
	}
	
	return cachedStation;
}

- (PlanetEntity *) planet
{
	if (cachedPlanet)
		return cachedPlanet;
	
	if (![self entityForUniversalID:planet])
	{
		int i;
		planet = NO_TARGET;
		cachedPlanet = nil;
		int ent_count = n_entities;
		int planet_count = 0;
		Entity* my_entities[ent_count];
		for (i = 0; i < ent_count; i++)
			if (sortedEntities[i]->isPlanet)
				my_entities[planet_count++] = [sortedEntities[i] retain];
		for (i = 0; ((i < planet_count)&&(planet == NO_TARGET)) ; i++)
		{
			PlanetEntity* thing = (PlanetEntity *)my_entities[i];
			if ([thing getPlanetType] == PLANET_TYPE_GREEN)
			{
				cachedPlanet = thing;
				planet = [cachedPlanet universal_id];
			}
		}
		for (i = 0; i < planet_count; i++)
			[my_entities[i] release];
	}
	return cachedPlanet;
}

- (PlanetEntity *) sun
{
	if (cachedSun)
		return cachedSun;
	
	if (![self entityForUniversalID:sun])
	{
		int i;
		sun = NO_TARGET;
		cachedSun = nil;
		int ent_count = n_entities;
		int planet_count = 0;
		Entity* my_entities[ent_count];
		for (i = 0; i < ent_count; i++)
			if (sortedEntities[i]->isPlanet)
				my_entities[planet_count++] = [sortedEntities[i] retain];
		for (i = 0; ((i < planet_count)&&(sun == NO_TARGET)) ; i++)
		{
			PlanetEntity* thing = (PlanetEntity *)my_entities[i];
			if ([thing getPlanetType] == PLANET_TYPE_SUN)
			{
				cachedSun = (PlanetEntity*)thing;
				sun = [cachedSun universal_id];
			}
		}
		for (i = 0; i < planet_count; i++)
			[my_entities[i] release];
	}
	return cachedSun;
}

- (void) resetBeacons
{
	ShipEntity* beaconShip = [self firstBeacon];
	while (beaconShip)
	{
		firstBeacon = [beaconShip nextBeaconID];
		[beaconShip setNextBeacon:nil];
		beaconShip = (ShipEntity *)[self entityForUniversalID:firstBeacon];
	}
	firstBeacon = NO_TARGET;
	lastBeacon = NO_TARGET;
}

- (ShipEntity *) firstBeacon
{
	return (ShipEntity *)[self entityForUniversalID:firstBeacon];
}

- (ShipEntity *) lastBeacon
{
	return (ShipEntity *)[self entityForUniversalID:lastBeacon];
}

- (void) setNextBeacon:(ShipEntity *) beaconShip
{
	if ([beaconShip isBeacon])
	{
		[beaconShip setNextBeacon:nil];
		if ([self lastBeacon])
			[[self lastBeacon] setNextBeacon:beaconShip];
		lastBeacon = [beaconShip universal_id];
		if (![self firstBeacon])
			firstBeacon = lastBeacon;
		
//		NSLog(@"DEBUG Universe Beacon Sequence:");
//		{
//			int bid = firstBeacon;
//			while (bid != NO_TARGET)
//			{
//				ShipEntity* beacon = (ShipEntity*)[self entityForUniversalID:bid];
////				NSLog(@"DEBUG >>>>> Beacon: %@", beacon);
//				bid = [beacon nextBeaconID];
//			}
//		}
	}
	else
	{
		NSLog(@"DEBUG ERROR! Universe setNextBeacon:%@ where the ship has no beaconChar set", beaconShip);
	}
}

- (GLfloat *) sky_clear_color
{
	return sky_clear_color;
}

- (void) setSky_clear_color:(GLfloat) red :(GLfloat) green :(GLfloat) blue :(GLfloat) alpha
{
	sky_clear_color[0] = red;
	sky_clear_color[1] = green;
	sky_clear_color[2] = blue;
	sky_clear_color[3] = alpha;
	air_resist_factor = alpha;
}  


- (BOOL) breakPatternOver
{
	return (breakPatternCounter == 0);
}

- (BOOL) breakPatternHide
{
	Entity* player = [self entityZero];
	return ((breakPatternCounter > 5)||(!player)||(player->status == STATUS_DOCKING));
}

- (id) recycleOrDiscard:(Entity *) entity
{
	NSMutableArray  *entlist;
	NSString		*classname = nil;
	
	if (!entity)
		return nil;
	
	// we're only interested in three types of entity currently
	//
	if (entity->isRing)
		classname = @"RingEntity";
	if (entity->isShip)
		classname = @"ShipEntity";
	if (entity->isStation)
		classname = @"StationEntity";
	
//	NSLog(@"Considering a used %@ with retainCount:%d for recycling",classname,[entity retainCount]);
	
	if (classname)
	{
		if (entity->status == STATUS_IN_HOLD)
			return entity;  // don't recycle scooped objects
		
		[recycleLock lock];
		if (![entityRecyclePool objectForKey:classname])
			[entityRecyclePool setObject:[NSMutableArray arrayWithCapacity:100] forKey:classname];   // add a new array
		entlist = (NSMutableArray *)[entityRecyclePool objectForKey:classname];
		
		[entity setScanClass: CLASS_NO_DRAW];   //  housekeeping, keeps glitches from appearing on scanner
		
		// reset a few flags
		entity->isSunlit = YES;
		entity->shadingEntityID = NO_TARGET;
		entity->position = make_vector(0,0,0);
		
		if (entity->isShip)
		{
			ShipEntity* ship = (ShipEntity*)entity;
			[[ship getAI] setOwner:nil];					//  save ai misreporting
		}
		
		if ([entlist count] < 100)		//  keep only up to 100 of each thing
			[entlist addObject:entity]; // add the entity to the array
		[recycleLock unlock];
	}
	return entity;																	// pass through
}

- (Entity *) recycledOrNew:(NSString *) classname
{
	Entity			*entity = nil;
	NSMutableArray  *entlist;
	if (classname)
	{
		if ([entityRecyclePool objectForKey:classname])
		{
			[recycleLock lock];
			entlist = (NSMutableArray *)[entityRecyclePool objectForKey:classname];
			if ([entlist count] > 0)
			{
//				NSLog(@"Recycling a used %@ from %@",classname,[entlist description]);
				entity = [[entlist objectAtIndex:0] retain];
				[entlist removeObjectAtIndex:0];
//				NSLog(@"Recycling a used %@",classname);
			}
			[recycleLock unlock];
		}
	}
	if (!entity)
	{
		Class   required_class = [[NSBundle mainBundle] classNamed:classname];
		entity = [[required_class alloc] init];
		[entity setUniverse:self];  // ensures access to preloaded data
//		NSLog(@"Generating a new %@",classname);
	}
	return entity;
}

- (NSMutableDictionary *) preloadedDataFiles
{
	return preloadedDataFiles;
}

- (ShipEntity *) getShipWithRole:(NSString *) desc
{
	int i, j, found;
	ShipEntity		*ship;
	NSMutableArray  *foundShips = [NSMutableArray arrayWithCapacity:16];
	NSMutableArray  *foundChance = [NSMutableArray arrayWithCapacity:16];
	NSArray			*shipKeys = [shipdata allKeys];
	float foundf = 0.0;
	float selectedf = randf();
	
//	NSLog(@"DEBUG [Universe getShipWithRole:] looking for %@ ...", desc);
	
	found = 0;
	for (i = 0; i < [shipKeys count]; i++)
	{
		NSDictionary*	shipDict = (NSDictionary *)[shipdata objectForKey:[shipKeys objectAtIndex:i]];
		NSArray*		shipRoles = [Entity scanTokensFromString:(NSString *)[shipDict objectForKey:@"roles"]];
		
//		NSLog(@"... checking if %@ contains a %@", [shipRoles description], desc);
		
		for (j = 0; j < [shipRoles count]; j++)
		{
			NSString* putative_roles = (NSString*)[shipRoles objectAtIndex:j];
		
//			NSLog(@"... %d putative_roles = %@", j, putative_roles);
		
			GLfloat chance = 1.0;
			if (putative_roles)
			{
				if ([putative_roles hasPrefix:desc] && ([putative_roles rangeOfString:@"("].location != NSNotFound))
				{
//					NSLog(@"DEBUG chance to be derived from '%@'", putative_roles);
					
					NSScanner* scanner = [NSScanner scannerWithString:putative_roles];	// scanner
					NSString* scanrole;
					[scanner scanUpToString:@"(" intoString:&scanrole];					// look for '('
					[scanner scanString:@"(" intoString:(NSString**)nil];				// skip over it
					if (![scanner scanFloat:&chance])	chance = 1.0;					// try to scan a float
					putative_roles = [NSString stringWithString:scanrole];				// ignore from '(' onwards (lazy)

//					NSLog(@"DEBUG chance derived from '%@' is %.3f", putative_roles, chance);
					
				}
		
//				NSLog(@"... ... putative_roles = '%@' desc = '%@' isEqual = %@", putative_roles, desc, ([putative_roles isEqual:desc])? @":YES:" : @":NO:");
		
				if ([putative_roles isEqual:desc])
				{
					[foundShips addObject:	[shipKeys objectAtIndex:i]];
					[foundChance addObject:	[NSNumber numberWithFloat:chance]];
					found++;
					foundf += chance;
				}
			}
		}
	}

	if (found == 0)
		return nil;
	
	i = 0;
	
	if (found > 1)
	{
		
//		NSLog(@"... candidates are: %d (%.3f) %@", found, foundf, [foundShips description]);
		
//		NSLog(@"... selection is: %.3f", selectedf * foundf);
		
		selectedf *= foundf;
		while (selectedf > [[foundChance objectAtIndex:i] floatValue])
		{
			selectedf -= [[foundChance objectAtIndex:i] floatValue];
			i++;
		}
		
		if (i >= found)	// sanity check
			i = 0;
//		NSLog(@"... we chose %@",(NSString *)[foundShips objectAtIndex:i]);
		
	}
	
	ship = [self getShip:(NSString *)[foundShips objectAtIndex:i]];	// may return nil if not found!
	[ship setRoles:desc];											// set its roles to this one particular chosen role
	return ship;
}


- (ShipEntity *) getShip:(NSString *) desc
{
	NSDictionary	*shipDict = nil;
	ShipEntity		*ship = nil;

	NS_DURING	
		shipDict = [self getDictionaryForShip: desc];	// handle OOLITE_EXCEPTION_SHIP_NOT_FOUND
	NS_HANDLER
		if ([[localException name] isEqual: OOLITE_EXCEPTION_SHIP_NOT_FOUND])
		{
			NSLog(@"***** Oolite Exception : '%@' in [Universe getShip: %@ ] *****", [localException reason], desc);
			shipDict = nil;
		}
		else
			[localException raise];
	NS_ENDHANDLER

	if (!shipDict)
		return nil;

	NSString	*shipRoles = (NSString *)[shipDict objectForKey:@"roles"];
	BOOL		isStation = ([shipRoles rangeOfString:@"station"].location != NSNotFound)||([shipRoles rangeOfString:@"carrier"].location != NSNotFound);

	if (isStation)
		ship = (StationEntity *)[self recycledOrNew:@"StationEntity"];
	else
		ship = (ShipEntity *)[self recycledOrNew:@"ShipEntity"];
	[ship setUniverse:self];
	[ship setUpShipFromDictionary:shipDict];

//	NSLog(@"DEBUG getShip:%@ returns %@", desc, ship);

	return ship;   // retain count = 1
}

- (NSDictionary *) getDictionaryForShip:(NSString *) desc
{
	if (![shipdata objectForKey:desc])
	{
		NSLog(@"***** Universe couldn't find a dictionary for a ship with description '%@'",desc);
		// throw an exception here...
		NSException* myException = [NSException
			exceptionWithName: OOLITE_EXCEPTION_SHIP_NOT_FOUND
			reason:[NSString stringWithFormat:@"No ship called '%@' could be found in the Oolite folder.", desc]
			userInfo:nil];
		[myException raise];
		return nil;
	}
	else
		return [NSDictionary dictionaryWithDictionary:(NSDictionary *)[shipdata objectForKey:desc]];	// is autoreleased
}

- (int) maxCargoForShip:(NSString *) desc
{
	int result = 0;
	if ([self getDictionaryForShip:desc])
	{
		NSDictionary* dict = [self getDictionaryForShip:desc];
		if ([dict objectForKey:@"max_cargo"])
			result = [(NSNumber *)[dict objectForKey:@"max_cargo"]   intValue];
	}
	return result;
}

- (int) getPriceForWeaponSystemWithKey:(NSString *)weapon_key
{
	int i;
	int price = 0;
	for (i = 0; ((i < [equipmentdata count])&&(price == 0)) ; i++)
	{
		int			price_per_unit  = [(NSNumber *)[(NSArray *)[equipmentdata objectAtIndex:i] objectAtIndex:1] intValue];
		NSString*   eq_type			= (NSString *)[(NSArray *)[equipmentdata objectAtIndex:i] objectAtIndex:3];
		if ([eq_type isEqual:weapon_key])
			price = price_per_unit;
	}
	return price;
}


- (int) legal_status_of_manifest:(NSArray *)manifest
{
	int i;
	int penalty = 0;
	for (i = 0 ; i < [manifest count] ; i++)
	{
		NSString *commodity = (NSString *)[(NSArray *)[manifest objectAtIndex:i] objectAtIndex:MARKET_NAME];
		int amount = [(NSNumber *)[(NSArray *)[manifest objectAtIndex:i] objectAtIndex:MARKET_QUANTITY] intValue];
		if ((amount > 0)&&([illegal_goods objectForKey:commodity]))
			penalty += amount * [(NSNumber *)[illegal_goods objectForKey:commodity] intValue];
	}
	return penalty;
}

- (NSArray *) getContainersOfPlentifulGoods:(int) how_many
{
	// build list of goods allocating 0..100 for each based on how
	// much of each quantity there is. Use a ratio of n x 100/64
	NSMutableArray  *accumulator = [NSMutableArray arrayWithCapacity:how_many];
	int quantities[[commoditydata count]];
	int total_quantity = 0;
	int i;
	for (i = 0; i < [commoditydata count]; i++)
	{
		int q = [(NSNumber *)[(NSArray *)[commoditydata objectAtIndex:i] objectAtIndex:MARKET_QUANTITY] intValue];
		if (q < 0)  q = 0;
		if (q > 64) q = 64;
		q *= 100;   q/= 64;
		quantities[i] = q;
		total_quantity += q;
	}
	// quantities is now used to determine which good get into the containers
	for (i = 0; i < how_many; i++)
	{
		ShipEntity* container = [self getShipWithRole:@"cargopod"];	// retained
		int co_type, co_amount, qr;
		
		// select a random point in the histogram
      // TODO: find out why total_quantity is sometimes zero.
      // oolite-linux: prevent the SIGFPE if total_quantity is zero
      if(total_quantity)
      {
		   qr = ranrot_rand() % total_quantity;
      }
      else
      {
         qr = 0;
      }

		co_type = 0;
		while (qr > 0)
		{
			qr -= quantities[co_type++];
		}
		co_type--;
		
		co_amount = [self getRandomAmountOfCommodity:co_type];
		
		//NSLog(@"... loading with plentiful %@",[self describeCommodity:co_type amount:co_amount]);
		
		// into the barrel it goes...
		if (container)
		{
			[container setUniverse:self];
			[container setScanClass: CLASS_CARGO];
			[container setCommodity:co_type andAmount:co_amount];
			[accumulator addObject:container];
			[container release];	// released
		}
	}
	return [NSArray arrayWithArray:accumulator];	
}

- (NSArray *) getContainersOfScarceGoods:(int) how_many
{
	// build list of goods allocating 0..100 for each based on how
	// much of each quantity there is. Use a ratio of (64 - n) x 100/64
	NSMutableArray  *accumulator = [NSMutableArray arrayWithCapacity:how_many];
	int quantities[[commoditydata count]];
	int total_quantity = 0;
	int i;
	for (i = 0; i < [commoditydata count]; i++)
	{
		int q = 64 - [(NSNumber *)[(NSArray *)[commoditydata objectAtIndex:i] objectAtIndex:MARKET_QUANTITY] intValue];
		if (q < 0)  q = 0;
		if (q > 64) q = 64;
		q *= 100;   q/= 64;
		quantities[i] = q;
		total_quantity += q;
	}
	// quantities is now used to determine which good get into the containers
	for (i = 0; i < how_many; i++)
	{
		ShipEntity* container = [self getShipWithRole:@"cargopod"];
		int co_type, co_amount, qr;
		
		// select a random point in the histogram
		qr = ranrot_rand() % total_quantity;
		co_type = 0;
		while (qr > 0)
		{
			qr -= quantities[co_type++];
		}
		co_type--;
		
		co_amount = [self getRandomAmountOfCommodity:co_type];
		
		//NSLog(@"... loading with scarce %@",[self describeCommodity:co_type amount:co_amount]);
		if (container)
		{
			[container setUniverse:self];
			[container setScanClass: CLASS_CARGO];
			[container setCommodity:co_type andAmount:co_amount];
			[accumulator addObject:container];
			[container release];
		}
	}
	return [NSArray arrayWithArray:accumulator];	
}

- (NSArray *) getContainersOfDrugs:(int) how_many
{
	return [self getContainersOfCommodity:@"Narcotics" :how_many];	
}

- (NSArray *) getContainersOfCommodity:(NSString*) commodity_name :(int) how_many
{
	NSMutableArray  *accumulator = [NSMutableArray arrayWithCapacity:how_many];
	int commodity_type = [self commodityForName: commodity_name];
	int commodity_units = [self unitsForCommodity:commodity_type];
	int how_much = how_many;
	while (how_much > 0)
	{
		ShipEntity* container = [self getShipWithRole:@"cargopod"];
		int amount = 1;
		if (commodity_units != 0)
			amount += ranrot_rand() & (15 * commodity_units);
		if (amount > how_much)
			amount = how_much;
		// into the barrel it goes...
		if (container)
		{
			[container setUniverse:self];
			[container setScanClass: CLASS_CARGO];
			[container setCommodity:commodity_type andAmount:amount];
			[accumulator addObject:container];
			[container release];
		}
		else
		{
			NSLog(@"***** ERROR failed to find a container to fill with %@ *****", commodity_name);
		}
		how_much -= amount;
	}
	return [NSArray arrayWithArray:accumulator];	
}

- (int) getRandomCommodity
{
	int cd = ranrot_rand() % [commoditydata count];
	return cd;
}

- (int) getRandomAmountOfCommodity:(int) co_type
{
	int units;
	if ((co_type < 0)||(co_type >= [commoditydata count]))
		return 0;
	units = [[[commoditydata objectAtIndex:co_type] objectAtIndex:MARKET_UNITS] intValue];
	switch (units)
	{
		case 0 :	// TONNES
			return 1;
			break;
		case 1 :	// KILOGRAMS
			return 1 + (ranrot_rand() % 6) + (ranrot_rand() % 6) + (ranrot_rand() % 6);
			break;
		case 2 :	// GRAMS
			return 1 + (ranrot_rand() % 6) + (ranrot_rand() % 6);
			break;
	}
	return 1;
}

- (int) commodityForName:(NSString *) co_name
{
	int i;
	for (i = 0; i < [commoditydata count]; i++)
	{
		if ([co_name isEqual:[[commoditydata objectAtIndex:i] objectAtIndex:MARKET_NAME]])
			return i;
	}
	return NSNotFound;
}

- (NSString *) nameForCommodity:(int) co_type
{
	if ((co_type < 0)||(co_type >= [commoditydata count]))
		return @"";
	return [NSString stringWithFormat:@"%@",[[commoditydata objectAtIndex:co_type] objectAtIndex:MARKET_NAME]];
}

- (int) unitsForCommodity:(int) co_type
{
	if ((co_type < 0)||(co_type >= [commoditydata count]))
		return NSNotFound;
	return [[[commoditydata objectAtIndex:co_type] objectAtIndex:MARKET_UNITS] intValue];
}



- (NSString *) describeCommodity:(int) co_type amount:(int) co_amount
{
	int units;
	NSString	*desc2, *desc3;
	if ((co_type < 0)||(co_type >= [commoditydata count])||(co_amount == 0))
		return @"";
	units = [[[commoditydata objectAtIndex:co_type] objectAtIndex:MARKET_UNITS] intValue];
	switch (units)
	{
		case UNITS_KILOGRAMS :	// KILOGRAMS
			desc2 = @"kilogram";
			break;
		case UNITS_GRAMS :	// GRAMS
			desc2 = @"gram";
			break;
		case UNITS_TONS :	// TONNES
		default :
			desc2 = @"ton";
			break;
	}
	if (co_amount > 1)
		desc2 = [NSString stringWithFormat:@"%@s",desc2];
	desc3 = [[commoditydata objectAtIndex:co_type] objectAtIndex:MARKET_NAME];
	
	return [NSString stringWithFormat:@"%d %@ %@",co_amount,desc2,desc3];
}

////////////////////////////////////////////////////

- (void) setGameView:(MyOpenGLView *)view
{
    if (gameView)	[gameView release];
    gameView = view;
    [gameView retain];
}

- (MyOpenGLView *) gameView
{
    return gameView;
}

- (GameController *) gameController
{
	return [(MyOpenGLView *)gameView gameController];
}


- (TextureStore *) textureStore
{
    return textureStore;
}

- (void) drawFromEntity:(int) n
{
	if (!no_update)
	{
		NS_DURING
			
			no_update = YES;	// block other attempts to draw
			
			int i, v_status;
			Vector	position, obj_position, view_dir;
			Matrix rotMatrix;
			BOOL playerDemo = NO;
			GLfloat	white[] = { 1.0, 1.0, 1.0, 1.0};	// white light
			
			//
			// use a non-mutable copy so this can't be changed under us.
			//
			int			ent_count =	n_entities;
			Entity*		my_entities[ent_count];
			int			draw_count = 0;
			for (i = 0; i < ent_count; i++)
			{
				/* LOOKING FOR THE HEISENBUG
				
				have I considered what may happen if sortedEntities changes during this loop ????
				
				*/
				
				// we check to see that we draw only the things that need to be drawn!
				Entity* e = sortedEntities[i]; // ordered NEAREST -> FURTHEST AWAY
				double	zd2 = e->zero_distance;
				if ((e->isSky)||(e->isPlanet))
				{
					my_entities[draw_count++] = [e retain];	// planets and sky are always drawn!
					continue;
				}
				if ((zd2 > ABSOLUTE_NO_DRAW_DISTANCE2)||((e->isShip)&&(zd2 > e->no_draw_distance)))
					continue;
				// it passed all drawing tests - and it's not a planet or the sky - we can add it to the list
				my_entities[draw_count++] = [e retain];		//	retained
			}
			
//			NSLog(@"DEBUG drawing %d entities", draw_count);
			
			Entity	*viewthing = nil;
			Entity	*drawthing = nil;
			
			position.x = 0.0;	position.y = 0.0;	position.z = 0.0;
			set_matrix_identity(rotMatrix);

			if (n < n_entities)
			{
				viewthing = [entities objectAtIndex:n];
			}
			
			if ((viewthing)&&(viewthing == sortedEntities[0]))
			{
				position = [viewthing getViewpointPosition];
				gl_matrix_into_matrix([viewthing rotationMatrix], rotMatrix);
				v_status = viewthing->status;
				playerDemo = [(PlayerEntity*)viewthing showDemoShips];
			}
			else
			{
				NSLog(@"***** Universe trying to draw from the view of an entity NOT the player");
				// throw an exception here...
				NSException* myException = [NSException
					exceptionWithName: @"OoliteException"
					reason: @"Universe cannot draw from a non-player entity."
					userInfo: nil];
				[myException raise];
				return; // don't draw if there's not a viewing entity!
			}
						
			//NSLog(@"Drawing from [%f,%f,%f]", position.x, position.y, position.z);
			//
			checkGLErrors(@"Universe before doing anything");
			//
			glEnable(GL_LIGHTING);
			glEnable(GL_DEPTH_TEST);
			glEnable(GL_CULL_FACE);			// face culling
			glDepthMask(GL_TRUE);	// restore write to depth buffer

			if (!displayGUI)
				glClearColor( sky_clear_color[0], sky_clear_color[1], sky_clear_color[2], sky_clear_color[3]);
			else
				glClearColor( 0.0, 0.0, 0.0, 0.0);

			glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
			glLoadIdentity();	// reset matrix                         

			gluLookAt(0.0, 0.0, 0.0,	0.0, 0.0, 1.0,	0.0, 1.0, 0.0);

			// HACK BUSTED
			glScalef(   -1.0,  1.0,	1.0);   // flip left and right

			glPushMatrix(); // save this flat viewpoint

			switch (viewDirection)
			{
				case VIEW_FORWARD :
					view_dir.x = 0.0;   view_dir.y = 0.0;   view_dir.z = -1.0;
					break;
				case VIEW_AFT :
					view_dir.x = 0.0;   view_dir.y = 0.0;   view_dir.z = 1.0;
					break;
				case VIEW_PORT :
					view_dir.x = 1.0;   view_dir.y = 0.0;   view_dir.z = 0.0;
					break;
				case VIEW_STARBOARD :
					view_dir.x = -1.0;   view_dir.y = 0.0;   view_dir.z = 0.0;
					break;
				
				case VIEW_DOCKED :
				case VIEW_BREAK_PATTERN :
				default :
					view_dir.x = 0.0;   view_dir.y = 0.0;   view_dir.z = -1.0;
					break;
			}

			gluLookAt(0.0, 0.0, 0.0,	view_dir.x, view_dir.y, view_dir.z,	0.0, 1.0, 0.0);

			if ((!displayGUI) || (playerDemo))
			{
				// set up the light for demo ships
				GLfloat origin[] = { 500.0f, 2500.0f, -1000.0f};
				glLightfv(GL_LIGHT0, GL_POSITION, origin);
				
				////
				//
				// rotate the view
				glMultMatrixf([viewthing rotationMatrix]);
				// translate the view
				glTranslatef( -position.x, -position.y, -position.z);
				//
				////
				
				// position the sun correctly
				glLightfv(GL_LIGHT1, GL_POSITION, sun_center_position);	// this is necessary or the sun will move with the player
				
				if (playerDemo)
				{
					// light for demo ships display.. 
					glLightfv(GL_LIGHT0, GL_AMBIENT, white);
					glLightfv(GL_LIGHT0, GL_DIFFUSE, white);
					glLightfv(GL_LIGHT0, GL_SPECULAR, white);
					//
					glEnable(GL_LIGHT0);		// switch on the light for demo ships
					glDisable(GL_LIGHT1);		// switch the sun off inside the space station
				}
				else
				{
					glDisable(GL_LIGHT0);		// switch off the demo-ship light
					glEnable(GL_LIGHT1);		// lighting up the sun
				}
				
				// turn on lighting
				glEnable(GL_LIGHTING);
				
				BOOL sunlit = YES;
				
				int		furthest = draw_count - 1;
				int		nearest = 0;

				//
				//		DRAW ALL THE OPAQUE ENTITIES
				//
				for (i = furthest; i > nearest; i--)
				{
					int d_status;
					drawthing = my_entities[i];
					d_status = drawthing->status;
					
					GLfloat flat_ambdiff[4]	= {1.0, 1.0, 1.0, 1.0};   // for alpha
					GLfloat mat_no[4]		= {0.0, 0.0, 0.0, 1.0};   // nothing
					
					if (((d_status == STATUS_DEMO)&&(playerDemo)) || ((d_status != STATUS_DEMO)&&(!playerDemo)))
					{
						// reset material properties
						glMaterialfv(GL_FRONT_AND_BACK, GL_AMBIENT_AND_DIFFUSE, flat_ambdiff);
						glMaterialfv(GL_FRONT_AND_BACK, GL_EMISSION, mat_no);

						// atmospheric fog
						BOOL fogging = ((air_resist_factor > 0.01)&&(drawthing != [self sun]));
						
						glPushMatrix();
						obj_position = drawthing->position;
						//translate the object
						glTranslatef(obj_position.x,obj_position.y,obj_position.z);
						//rotate the object
						glMultMatrixf([drawthing rotationMatrix]);

						// atmospheric fog
						if (fogging)
						{
							double fog_scale = 0.50 * BILLBOARD_DEPTH / air_resist_factor;
							double half_scale = fog_scale * 0.50;
							glEnable(GL_FOG);
							glFogi(GL_FOG_MODE, GL_LINEAR);
							glFogfv(GL_FOG_COLOR, sky_clear_color);
							glHint(GL_FOG_HINT, GL_NICEST);
							glFogf(GL_FOG_START, half_scale);
							glFogf(GL_FOG_END, fog_scale);
						}
						
						// lighting
						if (drawthing->isSunlit != sunlit)
						{
							if (drawthing->isSunlit)
							{
								glEnable(GL_LIGHT1);
								sunlit = YES;	// track the state of GL_LIGHT1
							}
							else
							{
								glDisable(GL_LIGHT1);
								sunlit = NO;	// track the state of GL_LIGHT1
							}
						}
						
						// draw the thing
						//
						[drawthing drawEntity:NO:NO];
						
						// atmospheric fog
						if (fogging)
							glDisable(GL_FOG);
						
						glPopMatrix();
						
					}
				}
				
				//
				//		DRAW ALL THE TRANSLUCENT entsInDrawOrder
				//
				glDepthMask(GL_FALSE);				// don't write to depth buffer
				glDisable(GL_LIGHTING);	// ++TEST++
				for (i = furthest; i > nearest; i--)
				{
					int d_status;
					drawthing = my_entities[i];
					d_status = drawthing->status;
					
					if (((d_status == STATUS_DEMO)&&(playerDemo)) || ((d_status != STATUS_DEMO)&&(!playerDemo)))
					{
						// experimental - atmospheric fog
						BOOL fogging = (air_resist_factor > 0.01);
						
						glPushMatrix();
						obj_position = drawthing->position;
						//translate the object
						glTranslatef(obj_position.x,obj_position.y,obj_position.z);
						//rotate the object
						glMultMatrixf([drawthing rotationMatrix]);
						
						// atmospheric fog
						if (fogging)
						{
							double fog_scale = 0.50 * BILLBOARD_DEPTH / air_resist_factor;
							double half_scale = fog_scale * 0.50;
							glEnable(GL_FOG);
							glFogi(GL_FOG_MODE, GL_LINEAR);
							glFogfv(GL_FOG_COLOR, sky_clear_color);
							glHint(GL_FOG_HINT, GL_NICEST);
							glFogf(GL_FOG_START, half_scale);
							glFogf(GL_FOG_END, fog_scale);
						}
						
						// draw the thing
						[drawthing drawEntity:NO:YES];
						
						// atmospheric fog
						if (fogging)
							glDisable(GL_FOG);
						
						glPopMatrix();
					}
				}
				glDepthMask(GL_TRUE);	// restore write to depth buffer
			}
			
			glPopMatrix(); //restore saved flat viewpoint

			glDisable(GL_LIGHTING);				// disable lighting ++TEST++
			glDisable(GL_DEPTH_TEST);			// disable depth test
			glDisable(GL_CULL_FACE);			// face culling
			glDepthMask(GL_FALSE);				// don't write to depth buffer

			GLfloat	line_width = [(MyOpenGLView *)gameView viewSize].width / 1024.0; // restore line size
			if (line_width < 1.0)
				line_width = 1.0;
			glLineWidth(line_width);

			[self drawMessage];

			if ((v_status != STATUS_DEAD)&&(v_status != STATUS_ESCAPE_SEQUENCE))
			{
				if (!displayGUI)
					[self drawCrosshairs];
				if ((viewthing->isPlayer)&&([(PlayerEntity *)viewthing hud]))
				{
					HeadUpDisplay *the_hud = [(PlayerEntity *)viewthing hud];
					[the_hud setLine_width:line_width];
					[the_hud drawLegends];
					[the_hud drawDials];
				}
			}
			
			glFlush();	// don't wait around for drawing to complete
			//
			// clear errors - and announce them
			checkGLErrors(@"Universe after all entity drawing is done.");
			//
			for (i = 0; i < draw_count; i++)
				[my_entities[i] release];		//	released
			
			no_update = NO;	// allow other attempts to draw
			
		NS_HANDLER
		
			if ([[localException name] hasPrefix:@"Oolite"])
				[self handleOoliteException:localException];
			else
			{
				NSLog(@"\n\n***** Handling localException: %@ : %@ *****\n\n",[localException name], [localException reason]);
#ifndef GNUSTEP
				if (![[self gameController] inFullScreenMode])
					NSRunAlertPanel(@"Unexpected Error!", @"Error during [universe update:]\n\n'%@'", @"QUIT", nil, nil,localException);
				else
#endif
				NSLog(@"\n\n***** Quitting Oolite *****\n\n");
				[[self gameController] exitApp];
			}
		
		NS_ENDHANDLER

	}
}


- (void) drawCrosshairs
{
    PlayerEntity*   playerShip = (PlayerEntity *)[self entityZero];
	int				weapon     = [playerShip weaponForView:viewDirection];
	if ((playerShip)&&((playerShip->status == STATUS_IN_FLIGHT)||(playerShip->status == STATUS_WITCHSPACE_COUNTDOWN)))
	{	
		GLfloat k0 = CROSSHAIR_SIZE;
		GLfloat k1 = CROSSHAIR_SIZE / 2.0;
		GLfloat k2 = CROSSHAIR_SIZE / 4.0;
		GLfloat k3 = 3.0 * CROSSHAIR_SIZE / 4.0;
		GLfloat z1 = [(MyOpenGLView *)gameView display_z];
		GLfloat cx_col0[4] = { 0.0, 1.0, 0.0, 0.25};
		GLfloat cx_col1[4] = { 0.0, 1.0, 0.0, 0.50};
		GLfloat cx_col2[4] = { 0.0, 1.0, 0.0, 0.75};
		glEnable(GL_LINE_SMOOTH);									// alpha blending
		glLineWidth(2.0);
		
		switch (weapon)
		{
			case WEAPON_NONE :
				glBegin(GL_LINES);
				glColor4fv(cx_col0);	glVertex3f(k3, 0.0, z1);	glColor4fv(cx_col2);	glVertex3f(k1, 0.0, z1);
				glColor4fv(cx_col0);	glVertex3f(-k3, 0.0, z1);   glColor4fv(cx_col2);	glVertex3f(-k1, 0.0, z1);
				glEnd();
				break;
			case WEAPON_MILITARY_LASER :
				glBegin(GL_LINES);
				glColor4fv(cx_col0);	glVertex3f(k2, k0, z1);		glColor4fv(cx_col1);	glVertex3f(0.0, k3, z1);
				glColor4fv(cx_col0);	glVertex3f(k2, -k0, z1);	glColor4fv(cx_col1);	glVertex3f(0.0, -k3, z1);
				glColor4fv(cx_col0);	glVertex3f(k0, k2, z1);		glColor4fv(cx_col1);	glVertex3f(k3, 0.0, z1);
				glColor4fv(cx_col0);	glVertex3f(-k0, k2, z1);	glColor4fv(cx_col1);	glVertex3f(-k3, 0.0, z1);
				glColor4fv(cx_col0);	glVertex3f(-k2, k0, z1);	glColor4fv(cx_col1);	glVertex3f(0.0, k3, z1);
				glColor4fv(cx_col0);	glVertex3f(-k2, -k0, z1);   glColor4fv(cx_col1);	glVertex3f(0.0, -k3, z1);
				glColor4fv(cx_col0);	glVertex3f(k0, -k2, z1);	glColor4fv(cx_col1);	glVertex3f(k3, 0.0, z1);
				glColor4fv(cx_col0);	glVertex3f(-k0, -k2, z1);   glColor4fv(cx_col1);	glVertex3f(-k3, 0.0, z1);
				
				glColor4fv(cx_col1);	glVertex3f(0.0, k3, z1);	glColor4fv(cx_col2);	glVertex3f(0.0, k1, z1);
				glColor4fv(cx_col1);	glVertex3f(0.0, -k3, z1);   glColor4fv(cx_col2);	glVertex3f(0.0, -k1, z1);
				glColor4fv(cx_col1);	glVertex3f(k3, 0.0, z1);	glColor4fv(cx_col2);	glVertex3f(k1, 0.0, z1);
				glColor4fv(cx_col1);	glVertex3f(-k3, 0.0, z1);   glColor4fv(cx_col2);	glVertex3f(-k1, 0.0, z1);
				glEnd();
				break;
			case WEAPON_MINING_LASER :
				glBegin(GL_LINES);
				glColor4fv(cx_col0);	glVertex3f(k1, k0, z1);		glColor4fv(cx_col2);	glVertex3f(k1, k1, z1);
				glColor4fv(cx_col0);	glVertex3f(k1, -k0, z1);	glColor4fv(cx_col2);	glVertex3f(k1, -k1, z1);
				glColor4fv(cx_col0);	glVertex3f(k0, k1, z1);		glColor4fv(cx_col2);	glVertex3f(k1, k1, z1);
				glColor4fv(cx_col0);	glVertex3f(-k0, k1, z1);	glColor4fv(cx_col2);	glVertex3f(-k1, k1, z1);
				glColor4fv(cx_col0);	glVertex3f(-k1, k0, z1);	glColor4fv(cx_col2);	glVertex3f(-k1, k1, z1);
				glColor4fv(cx_col0);	glVertex3f(-k1, -k0, z1);   glColor4fv(cx_col2);	glVertex3f(-k1, -k1, z1);
				glColor4fv(cx_col0);	glVertex3f(k0, -k1, z1);	glColor4fv(cx_col2);	glVertex3f(k1, -k1, z1);
				glColor4fv(cx_col0);	glVertex3f(-k0, -k1, z1);   glColor4fv(cx_col2);	glVertex3f(-k1, -k1, z1);
				glEnd();
				break;
			case WEAPON_BEAM_LASER :
				glBegin(GL_LINES);
				glColor4fv(cx_col0);	glVertex3f(k2, k0, z1);		glColor4fv(cx_col2);	glVertex3f(0.0, k1, z1);
				glColor4fv(cx_col0);	glVertex3f(k2, -k0, z1);	glColor4fv(cx_col2);	glVertex3f(0.0, -k1, z1);
				glColor4fv(cx_col0);	glVertex3f(k0, k2, z1);		glColor4fv(cx_col2);	glVertex3f(k1, 0.0, z1);
				glColor4fv(cx_col0);	glVertex3f(-k0, k2, z1);	glColor4fv(cx_col2);	glVertex3f(-k1, 0.0, z1);
				glColor4fv(cx_col0);	glVertex3f(-k2, k0, z1);	glColor4fv(cx_col2);	glVertex3f(0.0, k1, z1);
				glColor4fv(cx_col0);	glVertex3f(-k2, -k0, z1);   glColor4fv(cx_col2);	glVertex3f(0.0, -k1, z1);
				glColor4fv(cx_col0);	glVertex3f(k0, -k2, z1);	glColor4fv(cx_col2);	glVertex3f(k1, 0.0, z1);
				glColor4fv(cx_col0);	glVertex3f(-k0, -k2, z1);   glColor4fv(cx_col2);	glVertex3f(-k1, 0.0, z1);
				glEnd();
				break;
			case WEAPON_PULSE_LASER :
			default :
				glBegin(GL_LINES);
				glColor4fv(cx_col0);	glVertex3f(0.0, k0, z1);	glColor4fv(cx_col2);	glVertex3f(0.0, k1, z1);
				glColor4fv(cx_col0);	glVertex3f(0.0, -k0, z1);   glColor4fv(cx_col2);	glVertex3f(0.0, -k1, z1);
				glColor4fv(cx_col0);	glVertex3f(k0, 0.0, z1);	glColor4fv(cx_col2);	glVertex3f(k1, 0.0, z1);
				glColor4fv(cx_col0);	glVertex3f(-k0, 0.0, z1);   glColor4fv(cx_col2);	glVertex3f(-k1, 0.0, z1);
				glEnd();
				break;
		}
		
		glLineWidth(1.0);
	}
}

- (void) drawMessage
{
	GLfloat z1 = [(MyOpenGLView *)gameView display_z];

	if (message_gui)
	{
		[message_gui drawGUI:0.0 :-40.0 :z1 :1.0 forUniverse:self];
	}

	if (comm_log_gui)
	{
		[comm_log_gui drawGUI:0.0 :180.0 :z1 :[comm_log_gui alpha] forUniverse:self];
	}

	if (displayGUI)
	{
		[gui drawGUI:0.0 :0.0 :z1 :1.0 forUniverse:self];
	}
	
	if (displayCursor)
	{
		double cursor_x = MAIN_GUI_PIXEL_WIDTH * [(MyOpenGLView *)gameView virtualJoystickPosition].x;
		if (cursor_x < -MAIN_GUI_PIXEL_WIDTH * 0.5)  cursor_x = -MAIN_GUI_PIXEL_WIDTH * 0.5;
		if (cursor_x > MAIN_GUI_PIXEL_WIDTH * 0.5)   cursor_x = MAIN_GUI_PIXEL_WIDTH * 0.5;
		double cursor_y = -MAIN_GUI_PIXEL_HEIGHT * [(MyOpenGLView *)gameView virtualJoystickPosition].y;
		if (cursor_y < -MAIN_GUI_PIXEL_HEIGHT * 0.5)  cursor_y = -MAIN_GUI_PIXEL_HEIGHT * 0.5;
		if (cursor_y > MAIN_GUI_PIXEL_HEIGHT * 0.5)   cursor_y = MAIN_GUI_PIXEL_HEIGHT * 0.5;
		
		cursor_row = 1 + floor((0.5 * MAIN_GUI_PIXEL_HEIGHT - MAIN_GUI_PIXEL_ROW_START - cursor_y) / MAIN_GUI_ROW_HEIGHT);
//		int column = floor((cursor_x + 0.5 * MAIN_GUI_PIXEL_WIDTH) / MAIN_GUI_ROW_WIDTH);
		
//		NSLog(@"DEBUG text cursor position [ row %d ] %@", cursor_row, [gui objectForRow: cursor_row]);
		
		[cursorSprite blitCentredToX:cursor_x Y:cursor_y Z:z1 Alpha:1.0];
		[(MyOpenGLView *)gameView setVirtualJoystick:cursor_x/MAIN_GUI_PIXEL_WIDTH :-cursor_y/MAIN_GUI_PIXEL_HEIGHT];
	}
	
}

- (Entity *) entityZero
{
	if (cachedEntityZero)
		return cachedEntityZero;
	else
		return cachedEntityZero = [entities objectAtIndex:0];
}


- (Entity *) entityForUniversalID:(int)u_id
{
	if ((u_id == NO_TARGET)||(!entity_for_uid[u_id]))
		return nil;
	Entity* ent = entity_for_uid[u_id];
	if (ent->isParticle)	// particles SHOULD NOT HAVE U_IDs!
		return nil;
	int ent_status = ent->status;
	if (ent_status == STATUS_DEAD)
		return nil;
	if (ent_status == STATUS_DOCKED)
		return nil;

	return ent;
}

- (BOOL) addEntity:(Entity *) entity
{
	if (entity)
	{
		int index = n_entities;
		
		// don't add things twice!
		if ([entities containsObject:entity])
			return YES;
			
		if (n_entities >= UNIVERSE_MAX_ENTITIES - 1)
		{
			// throw an exception here...
			NSLog(@"***** Universe cannot addEntity:%@ Universe is full (%d entities out of %d)", entity, n_entities, UNIVERSE_MAX_ENTITIES);
			[self obj_dump];
			NSException* myException = [NSException
				exceptionWithName:@"OoliteException"
				reason:[NSString stringWithFormat:@"Maximum number of entities (%d) in Universe reached. Cannot add %@", UNIVERSE_MAX_ENTITIES, entity]
				userInfo:nil];
			[myException raise];
			return NO;
		}
		//
		if (!(entity->isParticle))
		{
			while (entity_for_uid[next_universal_id] != nil)	// skip allocated numbers
			{
				next_universal_id++;						// increment keeps idkeys unique
				if (next_universal_id >= MAX_ENTITY_UID)
					next_universal_id = 0;
				while (next_universal_id == NO_TARGET)		// these are the null values - avoid them!
					next_universal_id++;
			}
			[entity setUniversal_id:next_universal_id];
			entity_for_uid[next_universal_id] = entity;
			if (entity->isShip)
			{
				ShipEntity* se = (ShipEntity *)entity;
				[[se getAI] setOwner:se];
				[[se getAI] setState:@"GLOBAL"];
				if ([se isBeacon])
					[self setNextBeacon:se];
				if (se->isStation)
				{
					double stationRoll =   0.4;
					// check for ststion_roll override
					NSDictionary*	systeminfo = [self generateSystemData:system_seed];
					if ([systeminfo objectForKey:@"station_roll"])
						stationRoll = [(NSNumber *)[systeminfo objectForKey:@"station_roll"] doubleValue];
					// check if it is a proper rotating station (ie. roles contains the word "station")
					if ([(StationEntity*)se isRotatingStation])
					{
						[se setRoll: stationRoll];
						[(StationEntity*)se setPlanet:[self planet]];
						[se setStatus:STATUS_ACTIVE];
//						NSLog(@"DEBUG setting %@ roll to %.2f", se, stationRoll);
					}
					else
					{
						[se setRoll: 0.0];
						[(StationEntity*)se setPlanet:[self planet]];
						[se setStatus:STATUS_ACTIVE];
//						NSLog(@"DEBUG setting %@ roll to %.2f", se, 0.0);
					}
				}
			}
		}
		else
			[entity setUniversal_id:NO_TARGET];
		[entity setUniverse:self];
		[entities addObject:entity];
		
//		NSLog(@"DEBUG ++(%@)", entity);
		
		// maintain sorted list (and for the scanner relative position)
		Vector player_pos = [self entityZero]->position;
		Vector entity_pos = entity->position;
		Vector delta = make_vector( entity_pos.x - player_pos.x, entity_pos.y - player_pos.y, entity_pos.z - player_pos.z);
		double z_distance = magnitude2( delta);
		entity->zero_distance = z_distance;
		entity->relative_position = delta;
		index = n_entities;
		sortedEntities[index] = entity;
		entity->z_index = index;
		while ((index > 0)&&(z_distance < sortedEntities[index - 1]->zero_distance))	// bubble into place
		{
			sortedEntities[index] = sortedEntities[index - 1];
			sortedEntities[index]->z_index = index;
			index--;
			sortedEntities[index] = entity;
			entity->z_index = index;
		}
		n_entities++;
//		for (index = 0; index < n_entities; index++)
//			NSLog(@"+++++ %d %.0f %@", sortedEntities[index]->z_index, sortedEntities[index]->zero_distance, sortedEntities[index]);
		//
		
		return YES;
	}
	return NO;
}

- (BOOL) removeEntity:(Entity *) entity
{
	if (entity)
	{
//		NSLog(@"DEBUG --(%@) from %d", entity, entity->z_index);

		// moved forward ^^
		// remove from the reference dictionary
		int old_id = [entity universal_id];
		entity_for_uid[old_id] = nil;
		[entity setUniversal_id:NO_TARGET];
		[entity setUniverse:nil];
		
		// maintain sorted list
		int index = entity->z_index;
		int n = 1;
		if (index >= 0)
		{
			if (sortedEntities[index] != entity)
			{
				NSLog(@"DEBUG Universe removeEntity:%@ ENTITY IS NOT IN THE RIGHT PLACE IN THE SORTED LIST -- FIXING...", entity);
				int i;
				index = -1;
				for (i = 0; (i < n_entities)&&(index == -1); i++)
					if (sortedEntities[i] == entity)
						index = i;
				if (index == -1)
					 NSLog(@"DEBUG Universe removeEntity:%@ ENTITY IS NOT IN THE SORTED LIST -- CONTINUING...", entity);
			}
 			if (index != -1)
			{
				while (index < n_entities)
				{
					while ((index + n < n_entities)&&(sortedEntities[index + n] == entity))
						n++;	// ie there's a duplicate entry for this entity
					sortedEntities[index] = sortedEntities[index + n];	// copy entity[index + n] -> entity[index] (preserves sort order)
					if (sortedEntities[index])
						sortedEntities[index]->z_index = index;				// give it its correct position
					index++;
				}
				if (n > 1)
					 NSLog(@"DEBUG Universe removeEntity: REMOVED %d EXTRA COPIES OF %@ FROM THE SORTED LIST", n - 1, entity);
				while (n--)
				{
					n_entities--;
					sortedEntities[n_entities] = nil;
				}
			}
			entity->z_index = -1;	// it's GONE!
		}
//		for (index = 0; index < n_entities; index++)
//			NSLog(@"----- %d %.0f %@", sortedEntities[index]->z_index, sortedEntities[index]->zero_distance, sortedEntities[index]);
		//
		
		// remove from the definitive list
		if ([entities containsObject:entity])
		{
			if (entity->isRing)
				breakPatternCounter--;

			if (entity->isShip)
			{
				int bid = firstBeacon;
				ShipEntity* se = (ShipEntity*)entity;
				if ([se isBeacon])
				{
					if (bid == old_id)
						firstBeacon = [se nextBeaconID];
					else
					{
						ShipEntity* beacon = (ShipEntity*)[self entityForUniversalID:bid];
						while ((beacon != nil)&&([beacon nextBeaconID] != old_id))
							beacon = (ShipEntity*)[self entityForUniversalID:[beacon nextBeaconID]];
						//
						[beacon setNextBeacon:(ShipEntity*)[self entityForUniversalID:[se nextBeaconID]]];
						//
						while ([beacon nextBeaconID] != NO_TARGET)
							beacon = (ShipEntity*)[self entityForUniversalID:[beacon nextBeaconID]];
						lastBeacon = [beacon universal_id];
					}
				}
				[se setBeaconChar:0];
			}
			
			[entities removeObject:[self recycleOrDiscard:entity]];
			
			//NSLog(@"--(%@)\n%@", entity, [entities description]);
			
			return YES;
		}
	}
	return NO;
}

- (void) removeAllEntitiesExceptPlayer:(BOOL) restore
{
	BOOL updating = no_update;
	no_update = YES;			// no drawing while we do this!
	
	if (!(((Entity*)[entities objectAtIndex:0])->isPlayer))
	{
		NSLog(@"***** First entity is not the player in Universe.removeAllEntitiesExceptPlayer - exiting.");
		exit(1);
	}
	
	while ([entities count] > 1)
	{
		Entity* ent = [entities objectAtIndex:1];
		if (!(ent->isPlayer))
		{
			if (ent->isStation)  // clear out queues
				[(StationEntity *)ent clear];
			
			[self removeEntity:ent];
		}
	}
	
	// maintain sorted list
	n_entities = 1;
	
	cachedSun = nil;
	cachedPlanet = nil;
	cachedStation = nil;
	cachedEntityZero = nil;
	firstBeacon = NO_TARGET;
	lastBeacon = NO_TARGET;
	
	no_update = updating;	// restore drawing
}

- (void) removeDemoShips
{
	int i;
	int ent_count = n_entities;
	Entity* my_entities[ent_count];
	for (i = 0; i < ent_count; i++)
		my_entities[i] = [sortedEntities[i] retain];
	if (ent_count > 1)
	{
		for (i = 1; i < ent_count; i++)
		{
			Entity* ent = my_entities[i];
			if (ent->status == STATUS_DEMO)
				[self removeEntity:ent];
		}
	}
	for (i = 0; i < ent_count; i++)
		[my_entities[i] release];
	demo_ship = nil;
}

- (BOOL) isVectorClearFromEntity:(Entity *) e1 toDistance:(double)dist fromPoint:(Vector) p2
{
	if (!e1)
		return NO;

	Vector  f1;
	int i;
	int ent_count = n_entities;
	Entity* my_entities[ent_count];
	for (i = 0; i < ent_count; i++)
		my_entities[i] = [sortedEntities[i] retain]; //	retained
	Vector p1 = e1->position;
	Vector v1 = p2;
	v1.x -= p1.x;   v1.y -= p1.y;   v1.z -= p1.z;   // vector from entity to p2
	
	double  nearest = sqrt(v1.x*v1.x + v1.y*v1.y + v1.z*v1.z) - dist;  // length of vector
	
	if (nearest < 0.0)
		return YES;			// within range already!
	
	if (v1.x || v1.y || v1.z)
		f1 = unit_vector(&v1);   // unit vector in direction of p2 from p1
	else
		f1 = make_vector( 0, 0, 1);
	
	for (i = 0; i < ent_count ; i++)
	{
		Entity *e2 = my_entities[i];
		if ((e2 != e1)&&([e2 canCollide]))
		{
			Vector epos = e2->position;
			epos.x -= p1.x;	epos.y -= p1.y;	epos.z -= p1.z; // epos now holds vector from p1 to this entities position
			
			double d_forward = dot_product(epos,f1);	// distance along f1 which is nearest to e2's position
			
			if ((d_forward > 0)&&(d_forward < nearest))
			{
				double cr = 1.10 * (e2->collision_radius + e1->collision_radius); //  10% safety margin
				Vector p0 = e1->position;
				p0.x += d_forward * f1.x;	p0.y += d_forward * f1.y;	p0.z += d_forward * f1.z;
				// p0 holds nearest point on current course to center of incident object
				Vector epos = e2->position;
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


- (Vector) getSafeVectorFromEntity:(Entity *) e1 toDistance:(double)dist fromPoint:(Vector) p2
{
	//
	// heuristic three
	//
	if (!e1)
	{
		NSLog(@"ERROR ***** No entity set in Universe getSafeVectorFromEntity:toDistance:fromPoint:");
		NSBeep();
		return make_vector(0,0,0);
	}
	Vector  f1;
	Vector  result = p2;
	int i;
	int ent_count = n_entities;
	Entity* my_entities[ent_count];
	for (i = 0; i < ent_count; i++)
		my_entities[i] = [sortedEntities[i] retain];	// retained
	Vector p1 = e1->position;
	Vector v1 = p2;
	v1.x -= p1.x;   v1.y -= p1.y;   v1.z -= p1.z;   // vector from entity to p2
	
	double  nearest = sqrt(v1.x*v1.x + v1.y*v1.y + v1.z*v1.z) - dist;  // length of vector
	
	if (v1.x || v1.y || v1.z)
		f1 = unit_vector(&v1);   // unit vector in direction of p2 from p1
	else
		f1 = make_vector( 0, 0, 1);
		
	for (i = 0; i < ent_count; i++)
	{
		Entity *e2 = my_entities[i];
		if ((e2 != e1)&&([e2 canCollide]))
		{
			Vector epos = e2->position;
			epos.x -= p1.x;	epos.y -= p1.y;	epos.z -= p1.z;
			double d_forward = dot_product(epos,f1);
			if ((d_forward > 0)&&(d_forward < nearest))
			{
				double cr = 1.10 * (e2->collision_radius + e1->collision_radius); //  10% safety margin
					
				Vector p0 = e1->position;
				p0.x += d_forward * f1.x;	p0.y += d_forward * f1.y;	p0.z += d_forward * f1.z;
				// p0 holds nearest point on current course to center of incident object
								
				Vector epos = e2->position;
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
						result.x += ((ranrot_rand() % 1024) - 512)/512.0; //   -1.0 .. +1.0
						result.y += ((ranrot_rand() % 1024) - 512)/512.0; //   -1.0 .. +1.0
						result.z += ((ranrot_rand() % 1024) - 512)/512.0; //   -1.0 .. +1.0
					}
					
					Vector  nearest_point = p1;
					nearest_point.x += d_forward * f1.x;	nearest_point.y += d_forward * f1.y;	nearest_point.z += d_forward * f1.z;
					// nearest point now holds nearest point on line to center of incident object
					
					Vector outward = nearest_point;
					outward.x -= result.x;	outward.y -= result.y;	outward.z -= result.z;
					if (outward.x||outward.y||outward.z)
						outward = unit_vector(&outward);
					else
						outward.y = 1.0;
					// outward holds unit vector through the nearest point on the line from the center of incident object
					
					Vector backward = p1;
					backward.x -= result.x;	backward.y -= result.y;	backward.z -= result.z;
					if (backward.x||backward.y||backward.z)
						backward = unit_vector(&backward);
					else
						backward.z = -1.0;
					// backward holds unit vector from center of the incident object to the center of the ship
					
					Vector dd = result;
					dd.x -= p1.x; dd.y -= p1.y; dd.z -= p1.z;
					double current_distance = sqrt (dd.x*dd.x + dd.y*dd.y + dd.z*dd.z);
					
					// sanity check current_distance
					//NSLog(@"Current distance is %.1f CR", current_distance/cr);
					if (current_distance < cr * 1.25)	// 25% safety margin
						current_distance = cr * 1.25;
					if (current_distance > cr * 5.0)	// up to 2 diameters away 
						current_distance = cr * 5.0;
										
					// choose a point that's three parts backward and one part outward
					//
					result.x += 0.25 * (outward.x * current_distance) + 0.75 * (backward.x * current_distance);		// push 'out' by this amount
					result.y += 0.25 * (outward.y * current_distance) + 0.75 * (backward.y * current_distance);
					result.z += 0.25 * (outward.z * current_distance) + 0.75 * (backward.z * current_distance);

					//NSLog(@"Bypassing %@ by going from (%.1f,%.1f,%.1f) to (%.1f,%.1f,%.1f)",e2,p1.x,p1.y,p1.z,result.x,result.y,result.z);
					
				}
			}
		}
	}
	for (i = 0; i < ent_count; i++)
		[my_entities[i] release]; //	released
	return result;
}

- (int) getFirstEntityHitByLaserFromEntity:(Entity *) e1 inView:(int) viewdir
{
	BOOL isSubentity = NO;
	ShipEntity  *hit_entity = nil;
	ShipEntity  *hit_subentity = nil;
	
	Vector p0 = e1->position;
	Quaternion q1 = e1->q_rotation;
	if ((e1)&&(e1->isPlayer))
		q1.w = -q1.w;   //  reverse for player viewpoint
	
	ShipEntity* parent = (ShipEntity*)[e1 owner];
	if ((e1)&&(e1->isShip)&&(parent)&&(parent != e1)&&(parent->isShip)&&([parent->sub_entities containsObject:e1]))
	{	// we're a subentity!
		BoundingBox bbox = [e1 getBoundingBox];
		Vector midfrontplane = make_vector( 0.5 * (bbox.max_x + bbox.min_x), 0.5 * (bbox.max_y + bbox.min_y), bbox.max_z);
		p0 = [(ShipEntity*)e1 absolutePositionForSubentityOffset:midfrontplane];
		q1 = parent->q_rotation;
		if (parent->isPlayer)
			q1.w = -q1.w;
		isSubentity = YES;
	}
	
	int		result = NO_TARGET;
	double  nearest;
	if (!e1)
		return NO_TARGET;
	if (e1->isShip)
		nearest = [(ShipEntity *)e1 weapon_range];
	else
		nearest = PARTICLE_LASER_LENGTH;
//	NSLog(@"DEBUG LASER nearest = %.1f",nearest);
	
	int i;
	int ent_count = n_entities;
	int ship_count = 0;
	ShipEntity* my_entities[ent_count];
	for (i = 0; i < ent_count; i++)
	{
		Entity* ent = sortedEntities[i];
		if ((ent->isShip) && (ent != e1) && (ent != parent) && [ent canCollide])
			my_entities[ship_count++] = [ent retain];	// retained
	}
	
	Vector u1 = vector_up_from_quaternion(q1);
	switch (viewdir)
	{
		case VIEW_AFT :
			quaternion_rotate_about_axis(&q1, u1, PI);
			break;
		case VIEW_PORT :
			quaternion_rotate_about_axis(&q1, u1, PI/2.0);
			break;
		case VIEW_STARBOARD :
			quaternion_rotate_about_axis(&q1, u1, -PI/2.0);
			break;
	}
	Vector f1 = vector_forward_from_quaternion(q1);
	Vector r1 = vector_right_from_quaternion(q1);
	for (i = 0; i < ship_count; i++)
	{
		ShipEntity *e2 = my_entities[i];
		
//		if (debug_laser)
//			NSLog(@"DEBUG >>>>> %@", e2);
		
		// check outermost bounding sphere
		GLfloat cr = e2->collision_radius;
		Vector rpos = make_vector( e2->position.x - p0.x, e2->position.y - p0.y, e2->position.z - p0.z);
		Vector v_off = make_vector( dot_product( rpos, r1), dot_product( rpos, u1), dot_product( rpos, f1));
		if ((v_off.z > 0.0)&&(v_off.z < nearest + cr)								// ahead AND within range
			&&(v_off.x < cr)&&(v_off.x > -cr)&&(v_off.y < cr)&&(v_off.y > -cr)		// AND not off to one side or another
			&&(v_off.x*v_off.x + v_off.y*v_off.y < cr*cr))							// AND not off to both sides
		{
			//  within the bounding sphere - do further tests
//			if (debug_laser)
//				NSLog(@"DEBUG LASER within outermost bounding sphere of %@", e2);
			// find any subentities for later testing
			int n_subs = 0;
			NSArray* subs = e2->sub_entities;
			if (subs)
				n_subs = [subs count];
			// check bounding spheres of main model and subentities
			// main model
			GLfloat ar = e2->actual_radius;
			if ((v_off.z > 0.0)&&(v_off.z < nearest + ar)								// ahead AND within range
				&&(v_off.x < ar)&&(v_off.x > -ar)&&(v_off.y < ar)&&(v_off.y > -ar)		// AND not off to one side or another
				&&(v_off.x*v_off.x + v_off.y*v_off.y < ar*ar))							// AND not off to both sides
			{
//				if (debug_laser)
//					NSLog(@"DEBUG LASER within actual bounding sphere of %@", e2);
				// check bounding box of main model
				BoundingBox arbb = [e2 findBoundingBoxRelativeToPosition:p0 InVectors:r1 :u1 :f1];
				if ((arbb.min_x < 0.0)&&(arbb.max_x > 0.0)&&(arbb.min_y < 0.0)&&(arbb.max_y > 0.0)&&(arbb.min_z > 0.0)&&(arbb.min_z < nearest))
				{
					hit_subentity = nil;
					hit_entity = e2;
					nearest = arbb.min_z;
				}
			}
			if ((hit_entity != e2)&&(n_subs))	// didn't hit main body but there are subs to chcek
			{
//				if (debug_laser)
//					NSLog(@"DEBUG LASER checking subentities of %@", e2);
				// check subentity bounding spheres
				int si;
				for (si = 0; (hit_entity != e2)&&(si < n_subs); si++)
				{
					Entity* e3 = (Entity*)[subs objectAtIndex:si];
					if ([e3 canCollide]&&(e3->isShip))
					{
						ShipEntity* se3 = (ShipEntity*)e3;
						GLfloat sr = e3->actual_radius;
						Vector sepos = [se3 absolutePositionForSubentity];
						Vector rpos = make_vector( sepos.x - p0.x, sepos.y - p0.y, sepos.z - p0.z);
						Vector v_off = make_vector( dot_product( rpos, r1), dot_product( rpos, u1), dot_product( rpos, f1));
						if ((v_off.z > 0.0)&&(v_off.z < nearest + sr)								// ahead AND within range
							&&(v_off.x < sr)&&(v_off.x > -sr)&&(v_off.y < sr)&&(v_off.y > -sr)		// AND not off to one side or another
							&&(v_off.x*v_off.x + v_off.y*v_off.y < sr*sr))							// AND not off to both sides
						{
//							if (debug_laser)
//								NSLog(@"DEBUG LASER within actual bounding sphere of %@", se3);
							// check subentity bounding box
							BoundingBox sebb = [se3 findSubentityBoundingBoxRelativeToPosition:p0 inVectors:r1 :u1 :f1];
							if ((sebb.min_x < 0.0)&&(sebb.max_x > 0.0)&&(sebb.min_y < 0.0)&&(sebb.max_y > 0.0)&&(sebb.min_z > 0.0)&&(sebb.min_z < nearest))
							{
//								if (debug_laser)
//									NSLog(@"DEBUG Laser hits subentity %@ of %@", se3, e2);
								hit_subentity = se3;
								hit_entity = e2;
								nearest = sebb.min_z;
							}
						}
					}
				}
			}
		}
	}
	//
	if (hit_entity)
	{
		result = [hit_entity universal_id];
		if ((hit_subentity)&&[hit_entity->sub_entities containsObject:hit_subentity])
			hit_entity->subentity_taking_damage = hit_subentity;
			
	}
	//
//	if (debug_laser)
//		NSLog(@"DEBUG LASER hit %@ %d",[hit_entity name],result);
	//
	for (i = 0; i < ship_count; i++)
		[my_entities[i] release]; //	released
	//
	return result;
}

- (int) getFirstEntityHitByLaserFromEntity:(Entity *) e1 inView:(int) viewdir offset:(Vector) offset
{
	BOOL isSubentity = NO;
	ShipEntity  *hit_entity = nil;
	ShipEntity  *hit_subentity = nil;
	
	Vector p0 = e1->position;
	Quaternion q1 = e1->q_rotation;
	if ((e1)&&(e1->isPlayer))
		q1.w = -q1.w;   //  reverse for player viewpoint
	
	ShipEntity* parent = (ShipEntity*)[e1 owner];
	if ((e1)&&(e1->isShip)&&(parent)&&(parent != e1)&&(parent->isShip)&&([parent->sub_entities containsObject:e1]))
	{	// we're a subentity!
		BoundingBox bbox = [e1 getBoundingBox];
		Vector midfrontplane = make_vector( 0.5 * (bbox.max_x + bbox.min_x), 0.5 * (bbox.max_y + bbox.min_y), bbox.max_z);
		p0 = [(ShipEntity*)e1 absolutePositionForSubentityOffset:midfrontplane];
		q1 = parent->q_rotation;
		if (parent->isPlayer)
			q1.w = -q1.w;
		isSubentity = YES;
	}
	
	int		result = NO_TARGET;
	double  nearest;
	if (!e1)
		return NO_TARGET;
	if (e1->isShip)
		nearest = [(ShipEntity *)e1 weapon_range];
	else
		nearest = PARTICLE_LASER_LENGTH;
//	NSLog(@"DEBUG LASER nearest = %.1f",nearest);
	
	int i;
	int ent_count = n_entities;
	int ship_count = 0;
	ShipEntity* my_entities[ent_count];
	for (i = 0; i < ent_count; i++)
	{
		Entity* ent = sortedEntities[i];
		if ((ent->isShip) && (ent != e1) && (ent != parent) && [ent canCollide])
			my_entities[ship_count++] = [ent retain];	// retained
	}
	
	Vector u1 = vector_up_from_quaternion(q1);
	Vector f1 = vector_forward_from_quaternion(q1);
	Vector r1 = vector_right_from_quaternion(q1);
	p0.x += offset.x * r1.x + offset.y * u1.x + offset.z * f1.x;
	p0.y += offset.x * r1.y + offset.y * u1.y + offset.z * f1.y;
	p0.z += offset.x * r1.z + offset.y * u1.z + offset.z * f1.z;
	switch (viewdir)
	{
		case VIEW_AFT :
			quaternion_rotate_about_axis(&q1, u1, PI);
			break;
		case VIEW_PORT :
			quaternion_rotate_about_axis(&q1, u1, PI/2.0);
			break;
		case VIEW_STARBOARD :
			quaternion_rotate_about_axis(&q1, u1, -PI/2.0);
			break;
	}
	f1 = vector_forward_from_quaternion(q1);
	r1 = vector_right_from_quaternion(q1);
	for (i = 0; i < ship_count; i++)
	{
		ShipEntity *e2 = my_entities[i];
		
//		if (debug_laser)
//			NSLog(@"DEBUG >>>>> %@", e2);
		
		// check outermost bounding sphere
		GLfloat cr = e2->collision_radius;
		Vector rpos = make_vector( e2->position.x - p0.x, e2->position.y - p0.y, e2->position.z - p0.z);
		Vector v_off = make_vector( dot_product( rpos, r1), dot_product( rpos, u1), dot_product( rpos, f1));
		if ((v_off.z > 0.0)&&(v_off.z < nearest + cr)								// ahead AND within range
			&&(v_off.x < cr)&&(v_off.x > -cr)&&(v_off.y < cr)&&(v_off.y > -cr)		// AND not off to one side or another
			&&(v_off.x*v_off.x + v_off.y*v_off.y < cr*cr))							// AND not off to both sides
		{
			//  within the bounding sphere - do further tests
//			if (debug_laser)
//				NSLog(@"DEBUG LASER within outermost bounding sphere of %@", e2);
			// find any subentities for later testing
			int n_subs = 0;
			NSArray* subs = e2->sub_entities;
			if (subs)
				n_subs = [subs count];
			// check bounding spheres of main model and subentities
			// main model
			GLfloat ar = e2->actual_radius;
			if ((v_off.z > 0.0)&&(v_off.z < nearest + ar)								// ahead AND within range
				&&(v_off.x < ar)&&(v_off.x > -ar)&&(v_off.y < ar)&&(v_off.y > -ar)		// AND not off to one side or another
				&&(v_off.x*v_off.x + v_off.y*v_off.y < ar*ar))							// AND not off to both sides
			{
//				if (debug_laser)
//					NSLog(@"DEBUG LASER within actual bounding sphere of %@", e2);
				// check bounding box of main model
				BoundingBox arbb = [e2 findBoundingBoxRelativeToPosition:p0 InVectors:r1 :u1 :f1];
				if ((arbb.min_x < 0.0)&&(arbb.max_x > 0.0)&&(arbb.min_y < 0.0)&&(arbb.max_y > 0.0)&&(arbb.min_z > 0.0)&&(arbb.min_z < nearest))
				{
					hit_subentity = nil;
					hit_entity = e2;
					nearest = arbb.min_z;
				}
			}
			if ((hit_entity != e2)&&(n_subs))	// didn't hit main body but there are subs to chcek
			{
//				if (debug_laser)
//					NSLog(@"DEBUG LASER checking subentities of %@", e2);
				// check subentity bounding spheres
				int si;
				for (si = 0; (hit_entity != e2)&&(si < n_subs); si++)
				{
					Entity* e3 = (Entity*)[subs objectAtIndex:si];
					if ([e3 canCollide]&&(e3->isShip))
					{
						ShipEntity* se3 = (ShipEntity*)e3;
						GLfloat sr = e3->actual_radius;
						Vector sepos = [se3 absolutePositionForSubentity];
						Vector rpos = make_vector( sepos.x - p0.x, sepos.y - p0.y, sepos.z - p0.z);
						Vector v_off = make_vector( dot_product( rpos, r1), dot_product( rpos, u1), dot_product( rpos, f1));
						if ((v_off.z > 0.0)&&(v_off.z < nearest + sr)								// ahead AND within range
							&&(v_off.x < sr)&&(v_off.x > -sr)&&(v_off.y < sr)&&(v_off.y > -sr)		// AND not off to one side or another
							&&(v_off.x*v_off.x + v_off.y*v_off.y < sr*sr))							// AND not off to both sides
						{
//							if (debug_laser)
//								NSLog(@"DEBUG LASER within actual bounding sphere of %@", se3);
							// check subentity bounding box
							BoundingBox sebb = [se3 findSubentityBoundingBoxRelativeToPosition:p0 inVectors:r1 :u1 :f1];
							if ((sebb.min_x < 0.0)&&(sebb.max_x > 0.0)&&(sebb.min_y < 0.0)&&(sebb.max_y > 0.0)&&(sebb.min_z > 0.0)&&(sebb.min_z < nearest))
							{
//								if (debug_laser)
//									NSLog(@"DEBUG Laser hits subentity %@ of %@", se3, e2);
								hit_subentity = se3;
								hit_entity = e2;
								nearest = sebb.min_z;
							}
						}
					}
				}
			}
		}
	}
	//
	if (hit_entity)
	{
		result = [hit_entity universal_id];
		if ((hit_subentity)&&[hit_entity->sub_entities containsObject:hit_subentity])
			hit_entity->subentity_taking_damage = hit_subentity;
			
	}
	//
//	if (debug_laser)
//		NSLog(@"DEBUG LASER hit %@ %d",[hit_entity name],result);
	//
	for (i = 0; i < ship_count; i++)
		[my_entities[i] release]; //	released
	//
	return result;
}

- (int) getFirstEntityTargettedByPlayer:(PlayerEntity*) player
{
	if ((!player)||(!player->isPlayer))
		return NO_TARGET;
	
	ShipEntity*	hit_entity = nil;
	
	int		result = NO_TARGET;
	double  nearest = SCANNER_MAX_RANGE;
	int i;
	
	int ent_count = n_entities;
	int ship_count = 0;
	Entity* my_entities[ent_count];
	for (i = 0; i < ent_count; i++)
		if ((sortedEntities[i]->isShip)&&(sortedEntities[i] != player))
			my_entities[ship_count++] = [sortedEntities[i] retain];	// retained

	Vector p1 = player->position;
	Quaternion q1 = player->q_rotation;
	q1.w = -q1.w;   //  reverse for player viewpoint
	Vector u1 = vector_up_from_quaternion(q1);
	Vector f1 = vector_forward_from_quaternion(q1);
	Vector r1 = vector_right_from_quaternion(q1);
	Vector offset = [player viewOffset];
	p1.x += offset.x * r1.x + offset.y * u1.x + offset.z * f1.x;
	p1.y += offset.x * r1.y + offset.y * u1.y + offset.z * f1.y;
	p1.z += offset.x * r1.z + offset.y * u1.z + offset.z * f1.z;
	switch (viewDirection)
	{
		case VIEW_AFT :
			quaternion_rotate_about_axis(&q1, u1, PI);
			break;
		case VIEW_PORT :
			quaternion_rotate_about_axis(&q1, u1, 0.5 * PI);
			break;
		case VIEW_STARBOARD :
			quaternion_rotate_about_axis(&q1, u1, -0.5 * PI);
			break;
	}
	f1 = vector_forward_from_quaternion(q1);
	r1 = vector_right_from_quaternion(q1);
	for (i = 0; i < ship_count; i++)
	{
		ShipEntity *e2 = (ShipEntity *)my_entities[i];
		if ([e2 canCollide]&&(e2->scan_class != CLASS_NO_DRAW))
		{
			Vector rp = e2->position;
			rp.x -= p1.x;	rp.y -= p1.y;	rp.z -= p1.z;
			double dist2 = magnitude2(rp);
			if (dist2 < nearest * nearest)
			{
				double df = dot_product(f1,rp);
				if ((df > 0.0)&&(df < nearest))
				{
					double du = dot_product(u1,rp);
					double dr = dot_product(r1,rp);
					double cr = e2->actual_radius;
					if (du*du + dr*dr < cr*cr)
					{
						hit_entity = e2;
						nearest = sqrt(dist2);
					}
				}
			}
		}
	}
	// check for MASC'M
	if ((hit_entity) && [hit_entity isJammingScanning] && (![player hasMilitaryScannerFilter]))
		hit_entity = nil;
	//
	if (hit_entity)
		result = [hit_entity universal_id];
	//
	for (i = 0; i < ship_count; i++)
		[my_entities[i] release]; //	released
	//
	return result;
}

- (NSArray *) getEntitiesWithinRange:(double) range1 ofEntity:(Entity *) e1
{
	if (!e1)
		return nil;
	NSMutableArray *hitlist = [NSMutableArray arrayWithCapacity:4];
	int i;
	int ent_count = n_entities;
	Entity* my_entities[ent_count];
	for (i = 0; i < ent_count; i++)
		my_entities[i] = [sortedEntities[i] retain];	// retained

	Vector p1 = e1->position;
	for (i = 0; i < ent_count; i++)
	{
		Entity *e2 = my_entities[i];
		if ((e2 != e1)&&([e2 canCollide]))
		{
			Vector p2 = e2->position;
			p2.x -= p1.x;	p2.y -= p1.y;	p2.z -= p1.z;
			double cr = range1 + e2->collision_radius;
			double d2 = p2.x*p2.x + p2.y*p2.y + p2.z*p2.z - cr*cr;
			if (d2 < 0)
				[hitlist addObject:e2];
		}
	}
	for (i = 0; i < ent_count; i++)
		[my_entities[i] release]; //	released
	return  [NSArray arrayWithArray:hitlist];
}

- (int) countShipsWithRole:(NSString *) desc inRange:(double) range1 ofEntity:(Entity *)e1
{
	if (!e1)
		return 0;
	int i, found;
	int ent_count = n_entities;
	int ship_count = 0;
	Entity* my_entities[ent_count];
	for (i = 0; i < ent_count; i++)
		if (sortedEntities[i]->isShip)
			my_entities[ship_count++] = [sortedEntities[i] retain];	// retained

	found = 0;
	Vector p1 = e1->position;
	for (i = 0; i < ship_count; i++)
	{
		Entity *e2 = my_entities[i];
		if ((e2 != e1)&&([[(ShipEntity *)e2 roles] isEqual:desc]))
		{
			Vector p2 = e2->position;
			p2.x -= p1.x;	p2.y -= p1.y;	p2.z -= p1.z;
			double cr = range1 + e2->collision_radius;
			double d2 = p2.x*p2.x + p2.y*p2.y + p2.z*p2.z - cr*cr;
			if (d2 < 0)
				found++;
		}
	}
	for (i = 0; i < ship_count; i++)
		[my_entities[i] release]; //	released
	return  found;
}

- (int) countShipsWithRole:(NSString *) desc
{
	int i, found;
	int ent_count = n_entities;
	int ship_count = 0;
	Entity* my_entities[ent_count];
	for (i = 0; i < ent_count; i++)
		if (sortedEntities[i]->isShip)
			my_entities[ship_count++] = [sortedEntities[i] retain];	// retained

	found = 0;
	for (i = 0; i < ship_count; i++)
	{
		Entity *e2 = my_entities[i];
		if (([[(ShipEntity *)e2 roles] isEqual:desc]))
			found++;
	}
	for (i = 0; i < ship_count; i++)
		[my_entities[i] release]; //	released
	return  found;
}

- (void) sendShipsWithRole:(NSString *) desc messageToAI:(NSString *) ms
{
	int i, found;
	int ent_count = n_entities;
	int ship_count = 0;
	Entity* my_entities[ent_count];
	for (i = 0; i < ent_count; i++)
		if (sortedEntities[i]->isShip)
			my_entities[ship_count++] = [sortedEntities[i] retain];	// retained

	found = 0;
	for (i = 0; i < ship_count; i++)
	{
		Entity *e2 = my_entities[i];
		if ([[(ShipEntity *)e2 roles] isEqual:desc])
			[[(ShipEntity *)e2 getAI] reactToMessage:ms];
	}
	for (i = 0; i < ship_count; i++)
		[my_entities[i] release]; //	released
}


- (double) getTime
{
	return universal_time;
}

- (double) getTimeDelta
{
	return time_delta;
}

- (void) findCollisions
{
	//
	// According to Shark, this is where Oolite spends most time!
	//
	Entity *e1,*e2;
	Vector p1, p2;
	double dist, r1, r2, min_dist;
	int i,j;
	//
	// use a non-mutable copy so this can't be changed under us.
	//
	int			ent_count =		n_entities;
	int			n_test = 0;
	Entity*		my_entities[ent_count];
	for (i = 0; i < ent_count; i++)
	{
		if ([sortedEntities[i] canCollide])	// on Jens' suggestion only check collidables
			my_entities[n_test++] = [sortedEntities[i] retain];		//	retained
	}
	if (n_test <= 1)
		return;
	//
	//	clear collision vars
	for (i = 0; i < n_test; i++)
	{
		e1 = my_entities[i];
		if (e1->has_collided)
			[[e1 collisionArray] removeAllObjects];
		e1->has_collided = NO;
		if (e1->isShip)
			[(ShipEntity*)e1 setProximity_alert:nil];
		e1->collider = nil;
	}
	//
	// test each entity against the others
	for (i = 0; i < n_test; i++)
	{
		e1 = my_entities[i];
		p1 = e1->position;
		r1 = e1->collision_radius;
		for (j = i + 1; j < n_test; j++)	// was j = 1, which wasted time!
		{
			e2 = my_entities[j];
			p2 = e2->position;
			r2 = e2->collision_radius;
			p2.x -= p1.x;   p2.y -= p1.y;   p2.z -= p1.z;
			dist = p2.x*p2.x + p2.y*p2.y + p2.z*p2.z;
			min_dist = (r1 + r2) * (r1 + r2);
			if (e1->isShip && (e2 == cachedSun))
				[e1 setThrowSparks:(dist < SUN_SPARKS_RADIUS_FACTOR * min_dist)];
			if (e2->isShip && (e1 == cachedSun))
				[e2 setThrowSparks:(dist < SUN_SPARKS_RADIUS_FACTOR * min_dist)];
			if (dist < PROXIMITY_WARN_DISTANCE2 * min_dist)
			{
				if ((e1->isShip) && (e2->isShip))
				{
//					NSLog(@"PROXIMITY ALERT %@ VS %@", e1, e2);
					if (dist < PROXIMITY_WARN_DISTANCE2 * r2 * r2) [(ShipEntity*)e1 setProximity_alert:(ShipEntity*)e2];
					if (dist < PROXIMITY_WARN_DISTANCE2 * r1 * r1) [(ShipEntity*)e2 setProximity_alert:(ShipEntity*)e1];
				}
				if (dist < min_dist)
				{
					BOOL	coll1 = [e1 checkCloseCollisionWith:e2];
					BOOL	coll2 = [e2 checkCloseCollisionWith:e1];
//					NSLog(@"Checking close collision between entities [%@:%@] = :%@: :%@:",e1,e2, coll1? @"YES":@"NO ", coll2? @"YES":@"NO ");
					if ( coll1 && coll2 )
					{
						//NSLog(@"collision!");
						if (e1->collider)
							[[e1 collisionArray] addObject:e1->collider];
						else
							[[e1 collisionArray] addObject:e2];
						e1->has_collided = YES;
						//
						if (e2->collider)
							[[e2 collisionArray] addObject:e2->collider];
						else
							[[e2 collisionArray] addObject:e1];
						e2->has_collided = YES;
					}
				}
			}
//			if (dumpCollisionInfo)
//				NSLog(@"Entity %d (%.1f) to entity %d (%.1f)- distance  %.1f (%.1f,%.1f,%.1f)", i, r1, j, r2, sqrt(dist), p2.x, p2.y, p2.z);
		}
	}
//	if (dumpCollisionInfo)
//		dumpCollisionInfo = NO;
	//
	for (i = 0; i < n_test; i++)
		[my_entities[i] release];		//	released
}

- (void) dumpCollisions
{
	dumpCollisionInfo = YES;
}

- (void) setViewDirection:(int) vd
{
	NSString	*ms = nil;
	
	if ((viewDirection == vd)&&(!displayGUI))
		return;
	
	switch (vd)
	{
		case VIEW_FORWARD :
			ms = @"Forward View";
			displayGUI = NO;   // switch off any text displays
			break;
		case VIEW_AFT :
			ms = @"Aft View";
			displayGUI = NO;   // switch off any text displays
			break;
		case VIEW_PORT :
			ms = @"Port View";
			displayGUI = NO;   // switch off any text displays
			break;
		case VIEW_STARBOARD :
			ms = @"Starboard View";
			displayGUI = NO;   // switch off any text displays
			break;
		default :
			break;
	}
	if (viewDirection != vd)
	{
		viewDirection = vd;
		if (ms)
			[self addMessage:ms forCount:3];
	}
	//NSLog(@"Universe viewDir : %d %@",viewDirection,ms);
}

- (int) viewDir
{
	//NSLog(@"Universe viewDir : %d",viewDirection);
	return viewDirection;
}

- (void) clearPreviousMessage
{
	if (currentMessage)	[currentMessage release];
	currentMessage = nil;
}

- (void) setMessageGuiBackgroundColor:(NSColor *) some_color
{
	[message_gui setBackgroundColor:some_color];
}

- (void) displayMessage:(NSString *) text forCount:(int) count
{
	if (![currentMessage isEqual:text])
    {
		if (currentMessage)	[currentMessage release];
		currentMessage = [text retain];
		
		[message_gui printLongText:text Align:GUI_ALIGN_CENTER Color:[NSColor yellowColor] FadeTime:(float)count Key:nil AddToArray:nil];
    }
}

- (void) displayCountdownMessage:(NSString *) text forCount:(int) count
{
	if (![currentMessage isEqual:text])
    {
		if (currentMessage)	[currentMessage release];
		currentMessage = [text retain];
		
		[message_gui printLineNoScroll:text Align:GUI_ALIGN_CENTER Color:[NSColor yellowColor] FadeTime:(float)count Key:nil AddToArray:nil];
    }
}

- (void) addDelayedMessage:(NSString *) text forCount:(int) count afterDelay:(double) delay
{
	SEL _addDelayedMessageSelector = @selector(addDelayedMessage:);
	NSMutableDictionary *msgDict = [NSMutableDictionary dictionaryWithCapacity:2];
	[msgDict setObject:text forKey:@"message"];
	[msgDict setObject:[NSNumber numberWithInt:count] forKey:@"duration"];
	[self performSelector:_addDelayedMessageSelector withObject:msgDict afterDelay:delay];
}

- (void) addDelayedMessage:(NSDictionary *) textdict
{
	NSString *msg = (NSString *)[textdict objectForKey:@"message"];
	if (!msg)
		return;
	int msg_duration = 3;
	if ([textdict objectForKey:@"duration"])
		msg_duration = [(NSNumber *)[textdict objectForKey:@"duration"] intValue];
	[self addMessage:msg forCount:msg_duration];
}

- (void) addMessage:(NSString *) text forCount:(int) count
{
#ifndef GNUSTEP
	PlayerEntity* player = (PlayerEntity *)[self entityZero];
#endif   
	if (![currentMessage isEqual:text])
    {		
		//speech synthesis
#ifndef GNUSTEP      
		if ([player speech_on])
		{
			NSString* systemName = [self generateSystemName:system_seed];
			NSString* systemSaid = [self generatePhoneticSystemName:system_seed];
			NSString* h_systemName = [self generateSystemName:[player target_system_seed]];
			NSString* h_systemSaid = [self generatePhoneticSystemName:[player target_system_seed]];
			
			NSString *spoken_text = text;
			if(nil != speechArray)
			{
				NSEnumerator *speechEnumerator = [speechArray objectEnumerator];
				NSArray *thePair;
				while (nil != (thePair = (NSArray*) [speechEnumerator nextObject]))
				{
					NSString *original_phrase = (NSString*)[thePair objectAtIndex: 0];
					NSString *replacement_phrase = (NSString*)[thePair objectAtIndex: 1];
//					NSLog(@"Will replace %@ with %@", original_phrase, replacement_phrase);
					
					spoken_text = [[spoken_text componentsSeparatedByString: original_phrase] componentsJoinedByString: replacement_phrase];
					
//					NSLog(@"%@", spoken_text);
				}
				spoken_text = [[spoken_text componentsSeparatedByString: systemName] componentsJoinedByString: systemSaid];
				spoken_text = [[spoken_text componentsSeparatedByString: h_systemName] componentsJoinedByString: h_systemSaid];
			}
			else
				NSLog(@"***** ERROR No speechArray");

			if ([self isSpeaking])
				[self stopSpeaking];
			[self startSpeakingString:spoken_text];
			
		}
#endif // ifndef GNUSTEP...      
		
		[message_gui printLongText:text Align:GUI_ALIGN_CENTER Color:[NSColor yellowColor] FadeTime:(float)count Key:nil AddToArray:nil];
		
		if (currentMessage)	[currentMessage release];
		currentMessage = [text retain];
    }
}

- (void) addCommsMessage:(NSString *) text forCount:(int) count
{
	if (![currentMessage isEqual:text])
    {
		PlayerEntity* player = (PlayerEntity *)[self entityZero];
		
		if ([player speech_on])
		{
			if ([self isSpeaking])
				[self stopSpeaking];
			[self startSpeakingString:@"Incoming message."];
		}
		
		[message_gui printLongText:text Align:GUI_ALIGN_CENTER Color:[NSColor greenColor] FadeTime:(float)count Key:nil AddToArray:nil];
		
		[comm_log_gui printLongText:text Align:GUI_ALIGN_LEFT Color:nil FadeTime:0.0 Key:nil AddToArray:[player comm_log]];
		[comm_log_gui setAlpha:1.0];
		[comm_log_gui fadeOutFromTime:[self getTime] OverDuration:6.0];
		
		if (currentMessage)	[currentMessage release];
		currentMessage = [text retain];
    }
}

- (void) showCommsLog:(double) how_long
{
	[comm_log_gui setAlpha:1.0];
	[comm_log_gui fadeOutFromTime:[self getTime] OverDuration:how_long];
}

- (void) update:(double) delta_t
{
    if (!no_update)
	{
		NS_DURING
			int i;
			PlayerEntity*	player = (PlayerEntity *)[self entityZero];
			int				ent_count = n_entities;
			Entity*			my_entities[ent_count];
			BOOL			playerDemo = [player showDemoShips];
			
			// use a retained copy so this can't be changed under us.
			//
			for (i = 0; i < ent_count; i++)
				my_entities[i] = [sortedEntities[i] retain];	// explicitly retain each one
			//
			time_delta = delta_t;
			universal_time += delta_t;
			//
			if ((demo_stage)&&(player)&&(player->status == STATUS_DEMO)&&(universal_time > demo_stage_time)&&([player gui_screen] == GUI_SCREEN_INTRO2))
			{
				if (ent_count > 1)
				{
					Vector  vel;
					Quaternion		q2;
					q2.x = 0.0;   q2.y = 0.0;   q2.z = 0.0; q2.w = 1.0;
					quaternion_rotate_about_y(&q2,PI);
					switch (demo_stage)
					{
						case DEMO_FLY_IN :
							vel.x = 0.0;	vel.y = 0.0;	vel.z = 0.0;
							if (demo_ship)
								[demo_ship setVelocity:vel];
							demo_stage = DEMO_SHOW_THING;
							demo_stage_time = universal_time + 6.0;
							break;
						case DEMO_SHOW_THING :
							if (demo_ship)
							{
								vel.x = 0.0;	vel.y = 0.0;	vel.z = 3.6 * demo_ship->actual_radius * 100.0;
								[demo_ship setVelocity:vel];
							}
							demo_stage = DEMO_FLY_OUT;
							demo_stage_time = universal_time + 1.5;
							break;
						case DEMO_FLY_OUT :
							// change the demo_ship here
							demo_ship_index++;
							demo_ship_index %= [demo_ships count];
							if (demo_ship)
							{
								[demo_ship setUpShipFromDictionary:[self getDictionaryForShip:[demo_ships objectAtIndex:demo_ship_index]]];
								[[demo_ship getAI] setStateMachine:@"nullAI.plist"];
								[demo_ship setQRotation:q2];
								[demo_ship setPosition:0.0 :0.0 :3.6 * demo_ship->actual_radius * 100.0];
								vel.x = 0.0;	vel.y = 0.0;	vel.z = -3.6 * demo_ship->actual_radius * 100.0;
								[demo_ship setVelocity:vel];
								[demo_ship setScanClass: CLASS_NO_DRAW];
								[demo_ship setRoll:PI/5.0];
								[demo_ship setPitch:PI/10.0];
								[gui setText:[demo_ship name] forRow:19 align:GUI_ALIGN_CENTER];
							}
							demo_stage = DEMO_FLY_IN;
							demo_stage_time = universal_time + 1.5;
							break;
					}
				}
			}
						
			//
			for (i = 0; i < ent_count; i++)
			{
				Entity *thing = my_entities[i];
				
				[thing update:delta_t];
				
				// maintain sorted list
				int index = thing->z_index;
				double z_distance = thing->zero_distance;
				while ((index > 0)&&(z_distance < sortedEntities[index - 1]->zero_distance))
				{
					sortedEntities[index] = sortedEntities[index - 1];	// bubble up the list
					sortedEntities[index - 1 ] = thing;
					thing->z_index = index - 1;
					sortedEntities[index]->z_index = index;
					index--;
				}
								
				if (thing->isShip)
				{
					AI* theShipsAI = [(ShipEntity *)thing getAI];
					if ((universal_time > [theShipsAI nextThinkTime])||([theShipsAI nextThinkTime] == 0.0))
					{
						[theShipsAI setNextThinkTime:universal_time + [theShipsAI thinkTimeInterval]];
						[theShipsAI think];
					}
				}
			}
			//
			// lighting considerations..
			PlanetEntity* the_sun = cachedSun;
			if (the_sun)
			{
				for (i = 0; i < ent_count; i++)
				{
					Entity* e1 = my_entities[i];
					BOOL occluder_moved = NO;
					if (e1->isSunlit == NO)
					{
						Entity* occluder = [self entityForUniversalID:e1->shadingEntityID];
						if (occluder)
							occluder_moved = occluder->has_moved;
					}
					if (((e1->isShip)||(e1->isPlanet))&&((e1->has_moved)||occluder_moved))
					{
						int j;
//						if (e1->isPlayer)
//							NSLog(@"\nDEBUG checking occlusion for %@", e1);
						e1->isSunlit = YES;				// sunlit by default
						//
						// check demo mode here..
						if (playerDemo)
							continue;	// don't check shading in demo mode
						//
						e1->shadingEntityID = NO_TARGET;
						for (j = 0; (j < ent_count)&&(e1->isSunlit)&&(e1->status != STATUS_DEMO) ; j++)
						{
							Entity* e2 = my_entities[j];
							//
							// simple tests
							if (j == i)
								continue;	// you can't shade self
							//
							if (e2 == the_sun)
								continue;	// sun can't shade itself
							//
							if ((e2->isShip == NO)&&(e2->isPlanet == NO))
								continue;	// only ships and planets shade
							//
							if (e2->collision_radius < e1->collision_radius)
								continue;	// smaller can't shade bigger
							//
							if (e2->isSunlit == NO)
								continue;	// things already /in/ shade can't shade things more.
							//
//							//
//							if (e1->isPlayer)
//								NSLog(@"DEBUG checking DISTANCE for occlusion against %@", e2);
//							//
							// check projected sizes of discs
							GLfloat d2_sun = distance2( e1->position, the_sun->position);
							GLfloat d2_e2sun = distance2( e2->position, the_sun->position);
							if (d2_e2sun > d2_sun)
								continue;	// you are nearer the sun than the potential occluder, so it can't shade you
//							//
//							if (e1->isPlayer)
//								NSLog(@"DEBUG checking SIZE for occlusion against %@", e2);
//							//
							GLfloat d2_e2 = distance2( e1->position, e2->position);
							GLfloat cr_sun = the_sun->collision_radius;
							GLfloat cr_e2 = e2->actual_radius;
							if (e2->isShip)
								cr_e2 *= 0.90;	// 10% smaller shadow for ships
							if (e2->isPlanet)
								cr_e2 = e2->collision_radius;	// use collision radius for planets
//							//
//							if (e1->isPlayer)
//								NSLog(@"DEBUG checking cr_sun %.2fm vs cr_e2 %.2fm", cr_sun, cr_e2);
//							//
							GLfloat cr2_sun_scaled = cr_sun * cr_sun * d2_e2 / d2_sun;
							if (cr_e2 * cr_e2 < cr2_sun_scaled)
								continue;	// if solar disc projected to the distance of e2 > collision radius it can't be shaded by e2
							//
//							//
//							if (e1->isPlayer)
//								NSLog(@"DEBUG checking ANGLES for occlusion against %@", e2);
//							//
							// check angles subtended by sun and occluder
							double theta_sun = asin( cr_sun / sqrt(d2_sun));	// 1/2 angle subtended by sun
							double theta_e2 = asin( cr_e2 / sqrt(d2_e2));		// 1/2 angle subtended by e2
							Vector p_sun = the_sun->position;
							Vector p_e2 = e2->position;
							Vector p_e1 = e1->position;
							Vector v_sun = make_vector( p_sun.x - p_e1.x, p_sun.y - p_e1.y, p_sun.z - p_e1.z);
							if (v_sun.x||v_sun.y||v_sun.z)
								v_sun = unit_vector( &v_sun);
							else
								v_sun.z = 1.0;
							Vector v_e2 = make_vector( p_e2.x - p_e1.x, p_e2.y - p_e1.y, p_e2.z - p_e1.z);
							if (v_e2.x||v_e2.y||v_e2.z)
								v_e2 = unit_vector( &v_e2);
							else
								v_e2.x = 1.0;
							double phi = acos( dot_product( v_sun, v_e2));		// angle between sun and e2 from e1's viewpoint
							if (theta_sun + phi > theta_e2)
								continue;	// sun is not occluded
							// all tests done e1 is in shade!
//							if (e1->isPlayer)
//								NSLog(@"DEBUG %@ occluded by %@", e1, e2);
							e1->isSunlit = NO;
							e1->shadingEntityID = [e2 universal_id];
						}
					}
				}
			}
			//
			//
			[self findCollisions];
			//
			// dispose of the non-mutable copy and everything it references neatly
			//
			for (i = 0; i < ent_count; i++)
				[my_entities[i] release];	// explicitly release each one

		NS_HANDLER
		
			if ([[localException name] hasPrefix:@"Oolite"])
				[self handleOoliteException:localException];
			else
			{
				NSLog(@"\n\n***** Handling localException: %@ : %@ *****\n\n",[localException name], [localException reason]);
#ifndef GNUSTEP
				if (![[self gameController] inFullScreenMode])
					NSRunAlertPanel(@"Unexpected Error!", @"Error during [universe update:]\n\n'%@'", @"QUIT", nil, nil,localException);
				else
#endif
				NSLog(@"\n\n***** Quitting Oolite *****\n\n");
				[[self gameController] exitApp];
			}
		
		NS_ENDHANDLER
	}
}

- (void) setGalaxy_seed:(Random_Seed) gal_seed
{
	int i;
	galaxy_seed = gal_seed;
	
	// systems
	Random_Seed g_seed = galaxy_seed;
	for (i = 0; i < 256; i++)
	{
		systems[i] = g_seed;
		if (system_names[i])	[system_names[i] release];
		system_names[i] = [[self getSystemName:g_seed] retain];
		rotate_seed(&g_seed);
		rotate_seed(&g_seed);
		rotate_seed(&g_seed);
		rotate_seed(&g_seed);
	}
}

- (void) setSystemTo:(Random_Seed) s_seed
{
	NSDictionary*   systemData;
	PlayerEntity*   player = (PlayerEntity *)[self entityZero];
	int i;
	
	galaxy_seed = [player galaxy_seed];
	system_seed = s_seed;
	target_system_seed = s_seed;
	
	// systems
	Random_Seed g_seed = galaxy_seed;
	for (i = 0; i < 256; i++)
	{
		systems[i] = g_seed;
		if (system_names[i])	[system_names[i] release];
		system_names[i] = [[self getSystemName:g_seed] retain];
		rotate_seed(&g_seed);
		rotate_seed(&g_seed);
		rotate_seed(&g_seed);
		rotate_seed(&g_seed);
	}
	
	systemData =		[[self generateSystemData:target_system_seed] retain];  // retained
	int economy =		[(NSNumber *)[systemData objectForKey:KEY_ECONOMY] intValue];
	
	[self generateEconomicDataWithEconomy:economy andRandomFactor:([player random_factor] ^ station)&0xff];
	
	[systemData release];   // released
}

- (Random_Seed) systemSeed
{
	return system_seed;
}

- (Random_Seed) systemSeedForSystemNumber:(int) n
{
	return systems[n & 0xff];
}

- (NSDictionary *) shipyard
{
	return shipyard;
}

- (NSDictionary *) descriptions
{
	return descriptions;
}

- (NSDictionary *) missiontext
{
	return missiontext;
}

- (NSString *) keyForPlanetOverridesForSystemSeed:(Random_Seed) s_seed inGalaxySeed:(Random_Seed) g_seed
{
	Random_Seed g0 = {0x4a, 0x5a, 0x48, 0x02, 0x53, 0xb7};
	int pnum = [self findSystemNumberAtCoords:NSMakePoint(s_seed.d,s_seed.b) withGalaxySeed:g_seed];
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
	NSMutableDictionary* systemdata = [[NSMutableDictionary alloc] initWithCapacity:8];
		
	int government = (s_seed.c / 8) & 7;
	
	int economy = s_seed.b & 7;
	if (government < 2)
		economy = economy | 2;
	
	int techlevel = (economy ^ 7) + (s_seed.d & 3) + (government / 2) + (government & 1);
	
	int population = (techlevel * 4) + government + economy + 1;
	
	int productivity = ((economy ^ 7) + 3) * (government + 4) * population * 8;
	
	int radius = (((s_seed.f & 15) + 11) * 256) + s_seed.d;
	
	NSString *name = [self generateSystemName:s_seed];
	NSString *inhabitants = [self generateSystemInhabitants:s_seed];
	NSString *description = [self generateSystemDescription:s_seed];
	
	NSString *override_key = [self keyForPlanetOverridesForSystemSeed:s_seed inGalaxySeed:galaxy_seed];
	
	[systemdata setObject:[NSNumber numberWithInt:government]		forKey:KEY_GOVERNMENT];
	[systemdata setObject:[NSNumber numberWithInt:economy]			forKey:KEY_ECONOMY];
	[systemdata setObject:[NSNumber numberWithInt:techlevel]		forKey:KEY_TECHLEVEL];
	[systemdata setObject:[NSNumber numberWithInt:population]		forKey:KEY_POPULATION];
	[systemdata setObject:[NSNumber numberWithInt:productivity]		forKey:KEY_PRODUCTIVITY];
	[systemdata setObject:[NSNumber numberWithInt:radius]			forKey:KEY_RADIUS];
	[systemdata setObject:name			forKey:KEY_NAME];
	[systemdata setObject:inhabitants	forKey:KEY_INHABITANTS];
	[systemdata setObject:description	forKey:KEY_DESCRIPTION];
	
	// check at this point
	// for scripted overrides for this planet
	if ([planetinfo objectForKey:PLANETINFO_UNIVERSAL_KEY])
		[systemdata addEntriesFromDictionary:(NSDictionary *)[planetinfo objectForKey:PLANETINFO_UNIVERSAL_KEY]];
	if ([planetinfo objectForKey:override_key])
		[systemdata addEntriesFromDictionary:(NSDictionary *)[planetinfo objectForKey:override_key]];
	if ([local_planetinfo_overrides objectForKey:override_key])
		[systemdata addEntriesFromDictionary:(NSDictionary *)[local_planetinfo_overrides objectForKey:override_key]];
		
	//NSLog(@"Generated system data is :\n%@",[systemdata description]);
	
	return [NSDictionary dictionaryWithDictionary:[systemdata autorelease]];
}

- (NSDictionary *) currentSystemData
{
	return [self generateSystemData:system_seed];
}

- (void) setSystemDataKey:(NSString*) key value:(NSObject*) object
{
	NSString*	override_key = [self keyForPlanetOverridesForSystemSeed:system_seed inGalaxySeed:galaxy_seed];
	
	if ([local_planetinfo_overrides objectForKey:override_key] == nil)
		[local_planetinfo_overrides setObject:[NSMutableDictionary dictionaryWithCapacity:8] forKey:override_key];
	
	NSMutableDictionary*	local_overrides = (NSMutableDictionary*)[local_planetinfo_overrides objectForKey:override_key];
	[local_overrides setObject:object forKey:key];
}


- (NSString *) getSystemName:(Random_Seed) s_seed
{
	NSDictionary	*systemDic =	[self generateSystemData:s_seed];
	NSString		*name =			(NSString *)[systemDic objectForKey:KEY_NAME];
	return [NSString stringWithString:[name capitalizedString]];
}

- (NSString *) getSystemInhabitants:(Random_Seed) s_seed
{
	NSDictionary	*systemDic =	[self generateSystemData:s_seed];
	NSString		*inhabitants =  (NSString *)[systemDic objectForKey:KEY_INHABITANTS];
	return [NSString stringWithString:inhabitants];
}

- (NSString *) generateSystemName:(Random_Seed) s_seed
{
	int i;
		
//	NSString*			digrams = @"ABOUSEITILETSTONLONUTHNOALLEXEGEZACEBISOUSESARMAINDIREA'ERATENBERALAVETIEDORQUANTEISRION";
	NSString*			digrams = [descriptions objectForKey:@"digrams"];
	NSMutableString*	name = [NSMutableString stringWithCapacity:256];
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
			if (![c2 isEqual:@"'"])		[name appendString:c2];
		}
		rotate_seed(&s_seed);
	}
	
	return [NSString stringWithString:[name capitalizedString]];
}

- (NSString *) generatePhoneticSystemName:(Random_Seed) s_seed
{
	int i;
		
//	NSString*			digrams = @"ABOUSEITILETSTONLONUTHNOALLEXEGEZACEBISOUSESARMAINDIREA?ERATENBERALAVETIEDORQUANTEISRION";
//	NSString*			phonograms = @"AEb=UW==sEH=IHt=IHl=EHt=st==AAn=lOW=nUW=T===nOW=AEl=lEY=hEY=JEH=zEY=sEH=bIY=sOW=UHs=EHz=AEr=mAE=IHn=dIY=rEY=EH==UXr=AEt=EHn=bEH=rAX=lAX=vEH=tIY=EHd=AAr=kw==AXn=tEY=IHz=rIY=AAn=";
	NSString*			phonograms = [descriptions objectForKey:@"phonograms"];
	NSMutableString*	name = [NSMutableString stringWithCapacity:256];
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
	
	return [NSString stringWithFormat:@"[[inpt PHON]]%@[[inpt TEXT]]", name];
}

- (NSString *) generateSystemInhabitants:(Random_Seed) s_seed
{
	NSMutableString* inhabitants= [NSMutableString stringWithCapacity:256];

	if (s_seed.e < 127)
		[inhabitants appendString:@"Human Colonial"];
	else
	{
		int inhab = (s_seed.f / 4) & 7;
		if (inhab < 3)
			[inhabitants appendString:(NSString *)[(NSArray *)[(NSArray *)[descriptions objectForKey:KEY_INHABITANTS] objectAtIndex:0] objectAtIndex:inhab]];
		
		inhab = s_seed.f / 32;
		if (inhab < 6)
		{
			[inhabitants appendString:@" "];
			[inhabitants appendString:(NSString *)[(NSArray *)[(NSArray *)[descriptions objectForKey:KEY_INHABITANTS] objectAtIndex:1] objectAtIndex:inhab]];
		}

		inhab = (s_seed.d ^ s_seed.b) & 7;
		if (inhab < 6)
		{
			[inhabitants appendString:@" "];
			[inhabitants appendString:(NSString *)[(NSArray *)[(NSArray *)[descriptions objectForKey:KEY_INHABITANTS] objectAtIndex:2] objectAtIndex:inhab]];
		}

		inhab = (inhab + (s_seed.f & 3)) & 7;
		[inhabitants appendString:@" "];
		[inhabitants appendString:(NSString *)[(NSArray *)[(NSArray *)[descriptions objectForKey:KEY_INHABITANTS] objectAtIndex:3] objectAtIndex:inhab]];
	}
	[inhabitants appendString:@"s"];
	//	
	return [NSString stringWithString:inhabitants];
}


- (Random_Seed) findSystemAtCoords:(NSPoint) coords withGalaxySeed:(Random_Seed) gal_seed
{
	if (!equal_seeds( gal_seed, galaxy_seed))
		[self setGalaxy_seed:gal_seed];

	Random_Seed system = gal_seed;
	int distance, dx, dy;
	int i;
    int min_dist = 10000;

	for (i = 0; i < 256; i++)
	{
		dx = abs(coords.x - systems[i].d);
		dy = abs(coords.y - systems[i].b);

		if (dx > dy)
			distance = (dx + dx + dy) / 2;
		else
			distance = (dx + dy + dy) / 2;

		if (distance < min_dist)
		{
			min_dist = distance;
			system = systems[i];
		}
	}

	return system;
}

- (Random_Seed) findNeighbouringSystemToCoords:(NSPoint) coords withGalaxySeed:(Random_Seed) gal_seed
{
	if (!equal_seeds( gal_seed, galaxy_seed))
		[self setGalaxy_seed:gal_seed];

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
				if (dist <= 7.0)
				{
					connected[j] |= connected[i];
					connected[i] |= connected[j];
				}
			}
		}
	}
	
	for (i = 0; i < 256; i++)
	{
		distance = distanceBetweenPlanetPositions( (int)coords.x, (int)coords.y, systems[i].d, systems[i].b);
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
	if (!equal_seeds( gal_seed, galaxy_seed))
		[self setGalaxy_seed:gal_seed];

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
				if (dist <= 7.0)
				{
					connected[j] |= connected[i];
					connected[i] |= connected[j];
				}
			}
		}
	}
	
	for (i = 0; i < 256; i++)
	{
		distance = distanceBetweenPlanetPositions( (int)coords.x, (int)coords.y, systems[i].d, systems[i].b);
		if ((connected[i])&&(distance < min_dist))
		{
			min_dist = distance;
			system = systems[i];
		}
	}

	return system;
}

- (int) findSystemNumberAtCoords:(NSPoint) coords withGalaxySeed:(Random_Seed) gal_seed
{
	if (!equal_seeds( gal_seed, galaxy_seed))
		[self setGalaxy_seed:gal_seed];

	int system = NSNotFound;
	int distance, dx, dy;
	int i;
    int min_dist = 10000;

	for (i = 0; i < 256; i++)
	{
		dx = abs(coords.x - systems[i].d);
		dy = abs(coords.y - systems[i].b);

		if (dx > dy)
			distance = (dx + dx + dy) / 2;
		else
			distance = (dx + dy + dy) / 2;

		if (distance < min_dist)
		{
			min_dist = distance;
			system = i;
		}
	}
	return system;
}

- (NSPoint) findSystemCoordinatesWithPrefix:(NSString *) p_fix withGalaxySeed:(Random_Seed) gal_seed
{
	if (!equal_seeds( gal_seed, galaxy_seed))
		[self setGalaxy_seed:gal_seed];

	NSPoint system_coords = NSMakePoint(-1.0,-1.0);
	int i;
	int n_matches = 0;
	int result = -1;
	for (i = 0; i < 256; i++)
	{
		system_found[i] = NO;
		if ([[system_names[i] lowercaseString] hasPrefix:p_fix])
		{
			system_found[i] = ([p_fix length] > 2);
			if (result < 0)
			{
				system_coords.x = systems[i].d;
				system_coords.y = systems[i].b;
				result = i;
			}
			n_matches++;
		}
	}
	if (n_matches == 1)
		system_found[result] = YES;	// no matter how few letters
	
	return system_coords;
}

- (BOOL*) systems_found
{
	return (BOOL*)system_found;
}

- (NSString*) systemNameIndex:(int) index;
{
	return system_names[index & 255];
}

- (NSDictionary *) routeFromSystem:(int) start ToSystem:(int) goal
{
	NSMutableArray*	route = [NSMutableArray arrayWithCapacity:255];
	
	// value checks
	if ((start < 0)||(start > 255)||(goal < 0)||(goal > 255))
		return nil;
	
//	NSLog(@"DEBUG determining route from %d (%d,%d) to %d (%d, %d)", start, systems[start].d, systems[start].b, goal, systems[goal].d, systems[goal].b);
	
	//
	// use A* algorithm to determine shortest route
	//
	// for this we need the neighbouring (<= 7LY distant) systems
	// listed for each system[]
	//
	NSMutableArray* neighbour_systems = [NSMutableArray arrayWithCapacity:256];
	int i;
	for (i = 0; i < 256; i++)
		[neighbour_systems addObject:[self neighboursToSystem:i]];	// each is retained as it goes in
	//
	// each node must store these values:
	// g(X) cost_from_start == distance from node to parent_node + g(parent node)
	// h(X) cost_to_goal (heuristic estimate) == distance from node to goal
	// f(X) total_cost_estimate == g(X) + h(X)
	// parent_node
	//
	// each node will be stored as a NSDictionary
	//
	// two lists of nodes are required:
	// open_nodes (yet to be explored) = a priority list where the next node always has the lowest f(X)
	// closed_nodes (explored)
	//
	// the open list will be stored as an NSMutableArray of indices to node_open with additions to the priority queue
	// being inserted into the correct position, a list of pointers also tracks each node
	//
	NSMutableArray* open_nodes = [NSMutableArray arrayWithCapacity:256];
	NSDictionary* node_open[256];
	//
	// the closed list is a simple array of flags
	//
	BOOL node_closed[256];
	//
	// initialise the lists:
	for (i = 0; i < 256; i++)
	{
		node_closed[i] = NO;
		node_open[i] = nil;
	}
	//
	// initialise the start node
	int location = start;
	double cost_from_start = 0.0;
	double cost_to_goal = distanceBetweenPlanetPositions(systems[start].d, systems[start].b, systems[goal].d, systems[goal].b);
	double total_cost_estimate = cost_from_start + cost_to_goal;
	NSDictionary* parent_node = nil;
	//
	NSDictionary* startNode = [NSDictionary dictionaryWithObjectsAndKeys:
		[NSNumber numberWithInt:location],					@"location",
		[NSNumber numberWithDouble:cost_from_start],		@"cost_from_start",
		[NSNumber numberWithDouble:cost_to_goal],			@"cost_to_goal",
		[NSNumber numberWithDouble:total_cost_estimate],	@"total_cost_estimate",
		NULL];
	//
	// push start node on open
	[open_nodes addObject:[NSNumber numberWithInt:start]];
	node_open[start] = startNode;
	//
	// process the list until success or failure
	while ([open_nodes count] > 0)
	{
		// pop the node from open list
		location = [(NSNumber*)[open_nodes objectAtIndex:0] intValue];
		
		NSDictionary* node = node_open[location];
		[open_nodes removeObjectAtIndex:0];
				
		cost_from_start =		[(NSNumber*)[node objectForKey:@"cost_from_start"]		doubleValue];
		cost_to_goal =			[(NSNumber*)[node objectForKey:@"cost_to_goal"]			doubleValue];
		total_cost_estimate =	[(NSNumber*)[node objectForKey:@"total_cost_estimate"]	doubleValue];
		parent_node =			(NSDictionary *)[node objectForKey:@"parent_node"];
				
//		NSLog(@"DEBUG examining location %d from list of %d ...", location, [open_nodes count]);
		
		// if at goal we're done!
		if (location == goal)
		{
			// construct route backwards from this location
			double total_cost = total_cost_estimate;
			while (parent_node)
			{
				[route insertObject:[node objectForKey:@"location"] atIndex:0];
				node = parent_node;
				location =				[(NSNumber*)[node objectForKey:@"location"]				intValue];
				cost_from_start =		[(NSNumber*)[node objectForKey:@"cost_from_start"]		doubleValue];
				cost_to_goal =			[(NSNumber*)[node objectForKey:@"cost_to_goal"]			doubleValue];
				total_cost_estimate =	[(NSNumber*)[node objectForKey:@"total_cost_estimate"]	doubleValue];
				parent_node =			(NSDictionary *)[node objectForKey:@"parent_node"];
			}
			[route insertObject:[NSNumber numberWithInt:start] atIndex:0];
			return [NSDictionary dictionaryWithObjectsAndKeys:
				route,									@"route",
				[NSNumber numberWithDouble:total_cost],	@"distance",
				NULL];	// we're done!
		}
		else
		{
			NSArray* neighbours = (NSArray *)[neighbour_systems objectAtIndex:location];
			
//			NSLog(@"DEBUG neighbours for %d = %@", location, [neighbours description]);
			
			for (i = 0; i < [neighbours count]; i++)
			{
				int newLocation = [(NSNumber *)[neighbours objectAtIndex:i] intValue];
				double newCostFromStart = cost_from_start + distanceBetweenPlanetPositions(systems[newLocation].d, systems[newLocation].b, systems[location].d, systems[location].b);
				double newCostToGoal = distanceBetweenPlanetPositions(systems[newLocation].d, systems[newLocation].b, systems[goal].d, systems[goal].b);
				double newTotalCostEstimate = newCostFromStart + newCostToGoal;
				//
				// ignore this node if it exists and there's no improvement
				BOOL ignore_node = node_closed[newLocation];
				if (node_open[newLocation])
				{
					if ([(NSNumber*)[node_open[newLocation] objectForKey:@"cost_from_start"] doubleValue] <= newCostFromStart)
						ignore_node = YES;
				}
				if (!ignore_node)
				{
					// store the new or improved information
					NSDictionary* newNode = [NSDictionary dictionaryWithObjectsAndKeys:
						[NSNumber numberWithInt:newLocation],				@"location",
						[NSNumber numberWithDouble:newCostFromStart],		@"cost_from_start",
						[NSNumber numberWithDouble:newCostToGoal],			@"cost_to_goal",
						[NSNumber numberWithDouble:newTotalCostEstimate],	@"total_cost_estimate",
						node,												@"parent_node",
						NULL];
					// remove node from closed list
					node_closed[newLocation] = NO;
					// add node to open list
					node_open[newLocation] = newNode;
					// add node to priority queue
					int p = 0;
					while (p < [open_nodes count])
					{
						NSDictionary* node_ref = node_open[[(NSNumber*)[open_nodes objectAtIndex:p] intValue]];
						if ([(NSNumber*)[node_ref objectForKey:@"total_cost_estimate"] doubleValue] > newTotalCostEstimate)
						{
							[open_nodes insertObject:[NSNumber numberWithInt:newLocation] atIndex:p];
							p = 99999;
						}
						p++;
					}
					if (p < 256)	// not found a place, add it on the end
						[open_nodes addObject:[NSNumber numberWithInt:newLocation]];
					//
				}
			}
		}
		node_closed[location] = YES;
	}
	//
	// if we get here, we've failed to find a route
	//
	return nil;
}

- (NSArray *) neighboursToSystem: (int) system_number
{
	NSMutableArray *neighbours = [NSMutableArray arrayWithCapacity:32];
	double distance;
	int i;
	for (i = 0; i < 256; i++)
	{
		distance = distanceBetweenPlanetPositions( systems[system_number].d, systems[system_number].b, systems[i].d, systems[i].b);
		if ((distance <= 7.0)&&(i != system_number))
		{
			[neighbours addObject:[NSNumber numberWithInt:i]];
		}
	}
	return neighbours;
}

- (NSMutableDictionary*) local_planetinfo_overrides;
{
	return local_planetinfo_overrides;
}

- (void) setLocal_planetinfo_overrides:(NSDictionary*) dict
{
	if (local_planetinfo_overrides)
		[local_planetinfo_overrides release];
	local_planetinfo_overrides = [[NSMutableDictionary dictionaryWithDictionary:dict] retain];
}

- (NSArray *) equipmentdata
{
	return equipmentdata;
}

- (NSDictionary *) commoditylists
{
	return commoditylists;
}

- (NSArray *) commoditydata
{
	return commoditydata;
}

- (BOOL) generateEconomicDataWithEconomy:(int) economy andRandomFactor:(int) random_factor
{
	StationEntity *some_station = [self station];
	//NSLog(@">>>>> generateEconomicDataWithEconomy:andRandomFactor for System");
	NSString *station_roles = [some_station roles];
	if (![commoditylists objectForKey:station_roles])
		station_roles = @"default";

	NSArray *newcommoditydata = [[self commodityDataForEconomy:economy andStation:some_station andRandomFactor:random_factor] retain];
	[commoditydata release];
	commoditydata = newcommoditydata;
	return YES;
}

- (NSArray *) commodityDataForEconomy:(int) economy andStation:(StationEntity *)some_station andRandomFactor:(int) random_factor
{
	NSString *station_roles = [some_station roles];
	
	if ([[self currentSystemData] objectForKey:@"market"])
	{
		station_roles = (NSString*)[[self currentSystemData] objectForKey:@"market"];
	}
	
	//NSLog(@"///// station roles detected as '%@'", station_roles);
	
	if (![commoditylists objectForKey:station_roles])
	{
		//NSLog(@"///// using default economy");
		station_roles = @"default";
	}
	else
	{
		//NSLog(@"///// found a special economy");
	}
		
	NSMutableArray *ourEconomy = [NSMutableArray arrayWithArray:(NSArray *)[commoditylists objectForKey:station_roles]];
	int i;
	
	for (i = 0; i < [ourEconomy count]; i++)
	{
		NSMutableArray *commodityInfo = [[NSMutableArray arrayWithArray:[ourEconomy objectAtIndex:i]] retain];  // retain
		
		int base_price =			[(NSNumber *)[commodityInfo objectAtIndex:MARKET_BASE_PRICE] intValue];
		int eco_adjust_price =		[(NSNumber *)[commodityInfo objectAtIndex:MARKET_ECO_ADJUST_PRICE] intValue];
		int eco_adjust_quantity =	[(NSNumber *)[commodityInfo objectAtIndex:MARKET_ECO_ADJUST_QUANTITY] intValue];
		int base_quantity =			[(NSNumber *)[commodityInfo objectAtIndex:MARKET_BASE_QUANTITY] intValue];
		int mask_price =			[(NSNumber *)[commodityInfo objectAtIndex:MARKET_MASK_PRICE] intValue];
		int mask_quantity =			[(NSNumber *)[commodityInfo objectAtIndex:MARKET_MASK_QUANTITY] intValue];
		
		int price =		(base_price + (random_factor & mask_price) + (economy * eco_adjust_price)) & 255;
		int quantity =  (base_quantity  + (random_factor & mask_quantity) - (economy * eco_adjust_quantity)) & 255;
		
		if (quantity > 127) quantity = 0;
		quantity &= 63;
		
		[commodityInfo replaceObjectAtIndex:MARKET_PRICE withObject:[NSNumber numberWithInt:price * 4]];
		[commodityInfo replaceObjectAtIndex:MARKET_QUANTITY withObject:[NSNumber numberWithInt:quantity]];
		
		[ourEconomy replaceObjectAtIndex:i withObject:[NSArray arrayWithArray:commodityInfo]];
		[commodityInfo release];	// release, done
	}
		
	return [NSArray arrayWithArray:ourEconomy];
}

double estimatedTimeForJourney(double distance, int hops)
{
	int min_hops = (hops > 1)? (hops - 1) : 1;
	return 2000 * hops + 4000 * distance * distance / min_hops;
}

- (NSArray *) passengersForSystem:(Random_Seed) s_seed atTime:(double) current_time
{
	PlayerEntity* player = (PlayerEntity*)[self entityZero];
	
	int player_repute = [player passengerReputation];
	
	int random_factor = current_time;
	random_factor = (random_factor >> 24) &0xff;
	
	// passenger departure time is generated by passenger_seed.a << 16 + passenger_seed.b << 8 + passenger_seed.c
	// added to (long)(current_time) & 0xffffffffff000000
	// to give a time somewhen in the 97 days before and after the current_time
	
	int start = [self findSystemNumberAtCoords:NSMakePoint(s_seed.d, s_seed.b) withGalaxySeed:galaxy_seed];
	NSString* native_species = [self generateSystemInhabitants:s_seed];
	native_species = [native_species substringToIndex:[native_species length] - 1];
	
	// adjust basic seed by market random factor
	Random_Seed passenger_seed = s_seed;
	passenger_seed.a ^= random_factor;		// XOR
	passenger_seed.b ^= passenger_seed.a;	// XOR
	passenger_seed.c ^= passenger_seed.b;	// XOR
	passenger_seed.d ^= passenger_seed.c;	// XOR
	passenger_seed.e ^= passenger_seed.d;	// XOR
	passenger_seed.f ^= passenger_seed.e;	// XOR
	
	NSMutableArray*	resultArray = [NSMutableArray arrayWithCapacity:255];
	int i = 0;
	
//	NSLog(@"DEBUG Passenger generator for reputation %d...\n", [player passengerReputation]);
	
	for (i = 0; i < 256; i++)
	{
		long long reference_time = 0x1000000 * floor( current_time / 0x1000000);

		long long passenger_time = passenger_seed.a * 0x10000 + passenger_seed.b * 0x100 + passenger_seed.c;
		double passenger_departure_time = reference_time + passenger_time;
		
		if (passenger_departure_time < 0)
			passenger_departure_time += 0x1000000;	// roll it around
		
		double days_until_departure = (passenger_departure_time - current_time) / 86400.0;
		
		
		int passenger_destination = passenger_seed.d;	// system number 0..255
		Random_Seed destination_seed = systems[passenger_destination];
		NSDictionary* destinationInfo = [self generateSystemData:destination_seed];
		int destination_government = [(NSNumber*)[destinationInfo objectForKey:KEY_GOVERNMENT] intValue];
		
		int pick_up_factor = destination_government + floor(days_until_departure) - 7;	// lower for anarchies (gov 0)
		
//		NSLog(@"DEBUG Passenger to %d pick-up %d repute %d", passenger_destination, pick_up_factor, player_repute);
				
		if ((days_until_departure > 0.0)&&(pick_up_factor <= player_repute)&&(passenger_seed.d != start))
		{
			// determine the passenger's species
			int passenger_species = passenger_seed.f & 3;	// 0-1 native, 2 human colonial, 3 other
			NSString* passenger_species_string = [NSString stringWithString:native_species];
			if (passenger_species == 2)
				passenger_species_string = @"Human Colonial";
			if (passenger_species == 3)
			{
				passenger_species_string = [self generateSystemInhabitants:passenger_seed];
				passenger_species_string = [passenger_species_string substringToIndex:[passenger_species_string length] - 1];
			}
			passenger_species_string = [[passenger_species_string lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
			
			// determine the passenger's name
//			seed_for_planet_description(passenger_seed);	// set the random number generator
			seed_RNG_only_for_planet_description(passenger_seed);
			NSString* passenger_name = [NSString stringWithFormat:@"%@ %@", [self expandDescription:@"%R" forSystem:passenger_seed], [self expandDescription:@"%R" forSystem:passenger_seed]];
			
			// determine information about the route...
			NSDictionary* routeInfo = [self routeFromSystem:start ToSystem:passenger_destination];
			
			// some routes are impossible!
			if (routeInfo)
			{
				NSString* destination_name = [self generateSystemName:destination_seed];
				
				double route_length = [(NSNumber *)[routeInfo objectForKey:@"distance"] doubleValue];
//				double distance_as_crow_flies = accurateDistanceBetweenPlanetPositions(s_seed.d,s_seed.b,destination_seed.d,destination_seed.b);
				int route_hops = [(NSArray *)[routeInfo objectForKey:@"route"] count] - 1;
				
				// 50 cr per hop + 8..15 cr per LY + bonus for low government level of destination
				int fee = route_hops * 50 + route_length * (8 + (passenger_seed.e & 7)) + 5 * (7 - destination_government) * (7 - destination_government);
				
				fee = cunningFee(fee);
				
				// premium = 20% of fee
				int premium = fee * 20 / 100;
				fee -= premium;
				
				// 1hr per LY*LY, + 30 mins per hop
//				double passenger_arrival_time = passenger_departure_time + 4000 * distance_as_crow_flies * distance_as_crow_flies + 2000 * route_hops; 
				double passenger_arrival_time = passenger_departure_time + estimatedTimeForJourney( route_length, route_hops); 
				
					
				NSString* long_description = [NSString stringWithFormat:
					@"%@, a %@, wishes to go to %@.",
					passenger_name, passenger_species_string, destination_name];
					
				long_description = [NSString stringWithFormat:
					@"%@ The route is %.1f light years long, a minimum of %d jumps.", long_description,
					route_length, route_hops];
					
				long_description = [NSString stringWithFormat:
					@"%@ You will need to depart within %@, in order to arrive within %@ time.", long_description,
					[self shortTimeDescription:(passenger_departure_time - current_time)], [self shortTimeDescription:(passenger_arrival_time - current_time)]];
				
				long_description = [NSString stringWithFormat:
					@"%@ Will pay %d Cr: %d Cr in advance, and %d Cr on arrival.", long_description,
					premium + fee, premium, fee];
					
//				NSLog(@"DEBUG Passenger %@:\n%@\n...", passenger_name, long_description);
				
				NSDictionary* passenger_info_dictionary = [NSDictionary dictionaryWithObjectsAndKeys:
					passenger_name,											PASSENGER_KEY_NAME,
					destination_name,										PASSENGER_KEY_DESTINATION_NAME,
					[NSNumber numberWithInt:start],							PASSENGER_KEY_START,
					[NSNumber numberWithInt:passenger_destination],			PASSENGER_KEY_DESTINATION,
					long_description,										PASSENGER_KEY_LONG_DESCRIPTION,
					[NSNumber numberWithDouble:passenger_departure_time],	PASSENGER_KEY_DEPARTURE_TIME,
					[NSNumber numberWithDouble:passenger_arrival_time],		PASSENGER_KEY_ARRIVAL_TIME,
					[NSNumber numberWithInt:fee],							PASSENGER_KEY_FEE,
					[NSNumber numberWithInt:premium],						PASSENGER_KEY_PREMIUM,
					NULL];
				
				[resultArray addObject:passenger_info_dictionary];
			}
		}
		
		// next passenger
		rotate_seed(&passenger_seed);
		rotate_seed(&passenger_seed);
		rotate_seed(&passenger_seed);
		rotate_seed(&passenger_seed);
	
	}
	
	return [NSArray arrayWithArray:resultArray];
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
	
	if ((parts < 2)&&(r_time > 86400))
	{
		int days = floor(r_time / 86400);
		r_time -= 86400 * days;
		result = [NSString stringWithFormat:@"%@ %d day%@", result, days, (days > 1) ? @"s" : @""];
		parts++;
	}
	if ((parts < 2)&&(r_time > 3600))
	{
		int hours = floor(r_time / 3600);
		r_time -= 3600 * hours;
		result = [NSString stringWithFormat:@"%@ %d hr%@", result, hours, (hours > 1) ? @"s" : @""];
		parts++;
	}
	if ((parts < 2)&&(r_time > 60))
	{
		int mins = floor(r_time / 60);
		r_time -= 60 * mins;
		result = [NSString stringWithFormat:@"%@ %d min%@", result, mins, (mins > 1) ? @"s" : @""];
		parts++;
	}
	if ((parts < 2)&&(r_time > 0))
	{
		int secs = floor(r_time);
		result = [NSString stringWithFormat:@"%@ %d sec%@", result, secs, (secs > 1) ? @"s" : @""];
		parts++;
	}
	return [result stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}

- (NSArray *) contractsForSystem:(Random_Seed) s_seed atTime:(double) current_time
{
	PlayerEntity* player = (PlayerEntity*)[self entityZero];
	
	int player_repute = [player contractReputation];
	
	int random_factor = current_time;
	random_factor = (random_factor >> 24) &0xff;
	
	// contract departure time is generated by contract_seed.a << 16 + contract_seed.b << 8 + contract_seed.c
	// added to (long)(current_time + 0x800000) & 0xffffffffff000000
	// to give a time somewhen in the 97 days before and after the current_time
	
	int start = [self findSystemNumberAtCoords:NSMakePoint(s_seed.d, s_seed.b) withGalaxySeed:galaxy_seed];
	
	// adjust basic seed by market random factor
	Random_Seed contract_seed = s_seed;
	contract_seed.f ^= random_factor;	// XOR back to front
	contract_seed.e ^= contract_seed.f;	// XOR
	contract_seed.d ^= contract_seed.e;	// XOR
	contract_seed.c ^= contract_seed.d;	// XOR
	contract_seed.b ^= contract_seed.c;	// XOR
	contract_seed.a	^= contract_seed.b;	// XOR
	
	NSMutableArray*	resultArray = [NSMutableArray arrayWithCapacity:255];
	int i = 0;
	
//	NSLog(@"DEBUG contract generator for reputation %d...\n", [player contractReputation]);
	
	NSArray* localMarket;
	if ([[self station] localMarket])
		localMarket = [[self station] localMarket];
	else
		localMarket = [[self station] initialiseLocalMarketWithSeed:s_seed andRandomFactor:random_factor];
	
	for (i = 0; i < 256; i++)
	{
		long long reference_time = 0x1000000 * floor( current_time / 0x1000000);
		
//		NSLog(@"DEBUG time = %lld (%.1f) reference time = %lld", now, current_time, reference_time);
		
		long long contract_time = contract_seed.a * 0x10000 + contract_seed.b * 0x100 + contract_seed.c;
		double contract_departure_time = reference_time + contract_time;
		
		if (contract_departure_time < 0)
			contract_departure_time += 0x1000000; //	wrap around
		
		double days_until_departure = (contract_departure_time - current_time) / 86400.0;
		
		// determine the destination
		int contract_destination = contract_seed.d;	// system number 0..255
		Random_Seed destination_seed = systems[contract_destination];
		
		NSDictionary* destinationInfo = [self generateSystemData:destination_seed];
		int destination_government = [(NSNumber*)[destinationInfo objectForKey:KEY_GOVERNMENT] intValue];
		
		int pick_up_factor = destination_government + floor(days_until_departure) - 7;	// lower for anarchies (gov 0)
						
		if ((days_until_departure > 0.0)&&(pick_up_factor <= player_repute)&&(contract_seed.d != start))
		{			
			int destination_economy = [(NSNumber*)[destinationInfo objectForKey:KEY_ECONOMY] intValue];
			NSArray* destinationMarket = [self commodityDataForEconomy:destination_economy andStation:[self station] andRandomFactor:random_factor];
			
//			NSLog(@"DEBUG local economy:\n%@\ndestination_economy:\n%@", [localMarket description], [destinationMarket description]);
			
			// now we need a commodity that's both plentiful here and scarce there...
			// build list of goods allocating 0..100 for each based on how
			// much of each quantity there is. Use a ratio of n x 100/64
			int quantities[[localMarket count]];
			int total_quantity = 0;
			int i;
			for (i = 0; i < [localMarket count]; i++)
			{
				// -- plentiful here
				int q = [(NSNumber *)[(NSArray *)[localMarket objectAtIndex:i] objectAtIndex:MARKET_QUANTITY] intValue];
				if (q < 0)  q = 0;
				if (q > 64) q = 64;
				quantities[i] = q;
				// -- and scarce there
				q = 64 - [(NSNumber *)[(NSArray *)[destinationMarket objectAtIndex:i] objectAtIndex:MARKET_QUANTITY] intValue];
				if (q < 0)  q = 0;
				if (q > 64) q = 64;
				quantities[i] *= q;	// multiply plentiful factor x scarce factor
				total_quantity += quantities[i];
			}
			int co_type, co_amount, qr, unit;
			
			// seed random number generator
			int super_rand1 = contract_seed.a * 256 * 256 + contract_seed.c * 256 + contract_seed.e;
			int super_rand2 = contract_seed.b * 256 * 256 + contract_seed.d * 256 + contract_seed.f;
			ranrot_srand(super_rand2);
			
			// select a random point in the histogram
			qr = super_rand2 % total_quantity;
						
			co_type = 0;
			while (qr > 0)
			{
				qr -= quantities[co_type++];
			}
			co_type--;
			
			// units
			unit = [self unitsForCommodity:co_type];
			
			if ((unit == UNITS_TONS)||([player contractReputation] == 7))	// only the best reputation gets to carry gold/platinum/jewels
			{
				// how much?...
				co_amount = 0;
				while (co_amount < 30)
					co_amount += (1 + (ranrot_rand() & 31)) * (1 + (ranrot_rand() & 15)) * [self getRandomAmountOfCommodity:co_type];
					
				// calculate a quantity discount
				int discount = 10 + floor (0.1 * co_amount);
				if (discount > 35)
					discount = 35;
				
				int price_per_unit = [(NSNumber *)[(NSArray *)[localMarket objectAtIndex:co_type] objectAtIndex:MARKET_PRICE] intValue] * (100 - discount) / 100 ;
				
				// what is that worth locally
				float local_cargo_value = 0.1 * co_amount * price_per_unit;
				
				// and the mark-up
				float destination_cargo_value = 0.1 * co_amount * [(NSNumber *)[(NSArray *)[destinationMarket objectAtIndex:co_type] objectAtIndex:MARKET_PRICE] intValue] * (200 + discount) / 200 ;
				
				// total profit
				float profit_for_trip = destination_cargo_value - local_cargo_value;
				
				if (profit_for_trip > 100.0)	// overheads!!
				{
					// determine information about the route...
					NSDictionary* routeInfo = [self routeFromSystem:start ToSystem:contract_destination];
					
					// some routes are impossible!
					if (routeInfo)
					{
						NSString* destination_name = [self generateSystemName:destination_seed];
						
						double route_length = [(NSNumber *)[routeInfo objectForKey:@"distance"] doubleValue];
						int route_hops = [(NSArray *)[routeInfo objectForKey:@"route"] count] - 1;
						
						// percentage taken by contracter
						int contractors_share = 90 + destination_government;
						// less 5% per op to a minimum of 10%
						contractors_share -= route_hops * 10;
						if (contractors_share < 10)
							contractors_share = 10;
						int contract_share = 100 - contractors_share;
						
						// what the contract pays
						float fee = profit_for_trip * contract_share / 100;
						
						fee = cunningFee(fee);

						// premium = local price
						float premium = local_cargo_value;
						
						// 1hr per LY*LY, + 30 mins per hop
						double contract_arrival_time = contract_departure_time + estimatedTimeForJourney( route_length, route_hops); 
						
						NSString* long_description = [NSString stringWithFormat:
							@"Deliver a cargo of %@ to %@.",
							[self describeCommodity:co_type amount:co_amount], destination_name];
							
						long_description = [NSString stringWithFormat:
							@"%@ The route is %.1f light years long, a minimum of %d jumps.", long_description,
							route_length, route_hops];
							
						long_description = [NSString stringWithFormat:
							@"%@ You will need to depart within %@, in order to arrive within %@ time.", long_description,
							[self shortTimeDescription:(contract_departure_time - current_time)], [self shortTimeDescription:(contract_arrival_time - current_time)]];
						
						long_description = [NSString stringWithFormat:
							@"%@ The contract will cost you %.1f Cr, and pay a total of %.1f Cr.", long_description,
							premium, premium + fee];
						
//						NSLog(@"DEBUG (%06x-%06x):\n%@\n...", super_rand1, super_rand2, long_description);

						NSDictionary* contract_info_dictionary = [NSDictionary dictionaryWithObjectsAndKeys:
							[NSString stringWithFormat:@"%06x-%06x", super_rand1, super_rand2 ],CONTRACT_KEY_ID,
							[NSNumber numberWithInt:start],										CONTRACT_KEY_START,
							[NSNumber numberWithInt:contract_destination],						CONTRACT_KEY_DESTINATION,
							destination_name,													CONTRACT_KEY_DESTINATION_NAME,
							[NSNumber numberWithInt:co_type],									CONTRACT_KEY_CARGO_TYPE,
							[NSNumber numberWithInt:co_amount],									CONTRACT_KEY_CARGO_AMOUNT,
							[self describeCommodity:co_type amount:co_amount],					CONTRACT_KEY_CARGO_DESCRIPTION,
							long_description,													CONTRACT_KEY_LONG_DESCRIPTION,
							[NSNumber numberWithDouble:contract_departure_time],				CONTRACT_KEY_DEPARTURE_TIME,
							[NSNumber numberWithDouble:contract_arrival_time],					CONTRACT_KEY_ARRIVAL_TIME,
							[NSNumber numberWithFloat:fee],										CONTRACT_KEY_FEE,
							[NSNumber numberWithFloat:premium],									CONTRACT_KEY_PREMIUM,
							NULL];
						
						[resultArray addObject:contract_info_dictionary];
					}
				}
			}
		}
		
		// next contract
		rotate_seed(&contract_seed);
		rotate_seed(&contract_seed);
		rotate_seed(&contract_seed);
		rotate_seed(&contract_seed);
	
	}
	
	return [NSArray arrayWithArray:resultArray];
}

- (NSArray *) shipsForSaleForSystem:(Random_Seed) s_seed atTime:(double) current_time
{
	int random_factor = current_time;
	random_factor = (random_factor >> 24) &0xff;
	
	// ship sold time is generated by ship_seed.a << 16 + ship_seed.b << 8 + ship_seed.c
	// added to (long)(current_time + 0x800000) & 0xffffffffff000000
	// to give a time somewhen in the 97 days before and after the current_time
		
	// adjust basic seed by market random factor
	Random_Seed ship_seed = s_seed;
	ship_seed.f ^= random_factor;	// XOR back to front
	ship_seed.e ^= ship_seed.f;	// XOR
	ship_seed.d ^= ship_seed.e;	// XOR
	ship_seed.c ^= ship_seed.d;	// XOR
	ship_seed.b ^= ship_seed.c;	// XOR
	ship_seed.a	^= ship_seed.b;	// XOR
	
	NSMutableArray*	resultArray = [NSMutableArray arrayWithCapacity:32];
	NSMutableDictionary* resultDictionary = [NSMutableDictionary dictionaryWithCapacity:32];
	
	float tech_price_boost = (ship_seed.a + ship_seed.b) / 256.0;
	int i = 0;
	
//	NSLog(@"DEBUG ships for sale generator...\n");
	
	for (i = 0; i < 256; i++)
	{
		long long reference_time = 0x1000000 * floor( current_time / 0x1000000);
		
//		NSLog(@"DEBUG time = %lld (%.1f) reference time = %lld", now, current_time, reference_time);
		
		long long c_time = ship_seed.a * 0x10000 + ship_seed.b * 0x100 + ship_seed.c;
		double ship_sold_time = reference_time + c_time;
		
		if (ship_sold_time < 0)
			ship_sold_time += 0x1000000;	// wraparound
		
		double days_until_sale = (ship_sold_time - current_time) / 86400.0;
		
		NSDictionary* systemInfo = [self generateSystemData:system_seed];
		int techlevel = [(NSNumber*)[systemInfo objectForKey:KEY_TECHLEVEL] intValue];
		
		int ship_index = (ship_seed.d * 0x100 + ship_seed.e) % [[shipyard allKeys] count];
		
		NSString* ship_key = [[shipyard allKeys] objectAtIndex:ship_index];
		NSDictionary* ship_info = (NSDictionary*)[shipyard objectForKey:ship_key];
		int ship_techlevel = [(NSNumber*)[ship_info objectForKey:KEY_TECHLEVEL] intValue];
		
		double chance = 1.0 - pow(1.0 - [(NSNumber*)[ship_info objectForKey:KEY_CHANCE] floatValue], techlevel - ship_techlevel);
		
		// seed random number generator
		int super_rand1 = ship_seed.a * 0x10000 + ship_seed.c * 0x100 + ship_seed.e;
		int super_rand2 = ship_seed.b * 0x10000 + ship_seed.d * 0x100 + ship_seed.f;
		ranrot_srand(super_rand2);
		
		if ((days_until_sale > 0.0) && (days_until_sale < 30.0) && (ship_techlevel < techlevel) && (randf() < chance))
		{			
			NSMutableDictionary* ship_dict = [NSMutableDictionary dictionaryWithDictionary:[self getDictionaryForShip:ship_key]];
			NSMutableString* description = [NSMutableString stringWithCapacity:256];
			NSMutableString* short_description = [NSMutableString stringWithCapacity:256];
			int price = [(NSNumber*)[ship_info objectForKey:KEY_PRICE] intValue];
			int base_price = price;
			NSMutableArray* extras = [NSMutableArray arrayWithArray:[(NSDictionary*)[ship_info objectForKey:KEY_STANDARD_EQUIPMENT] objectForKey:KEY_EQUIPMENT_EXTRAS]];
			NSString* fwd_weapon_string = (NSString*)[(NSDictionary*)[ship_info objectForKey:KEY_STANDARD_EQUIPMENT] objectForKey:KEY_EQUIPMENT_FORWARD_WEAPON];
			NSMutableArray* options = [NSMutableArray arrayWithArray:(NSArray*)[ship_info objectForKey:KEY_OPTIONAL_EQUIPMENT]];
			int max_cargo = 0;
			if ([ship_dict objectForKey:@"max_cargo"])
				max_cargo = [(NSNumber*)[ship_dict objectForKey:@"max_cargo"] intValue];
			
			
			[description appendFormat:@"%@:", [ship_dict objectForKey:KEY_NAME]];
			[short_description appendFormat:@"%@:", [ship_dict objectForKey:KEY_NAME]];
			
			
			int fwd_weapon = WEAPON_NONE;
			if ([fwd_weapon_string isEqual:@"EQ_WEAPON_PULSE_LASER"])
				fwd_weapon = WEAPON_PULSE_LASER;
			if ([fwd_weapon_string isEqual:@"EQ_WEAPON_BEAM_LASER"])
				fwd_weapon = WEAPON_BEAM_LASER;
			if ([fwd_weapon_string isEqual:@"EQ_WEAPON_MINING_LASER"])
				fwd_weapon = WEAPON_MINING_LASER;
			if ([fwd_weapon_string isEqual:@"EQ_WEAPON_MILITARY_LASER"])
				fwd_weapon = WEAPON_MILITARY_LASER;
			if ([fwd_weapon_string isEqual:@"EQ_WEAPON_THARGOID_LASER"])
				fwd_weapon = WEAPON_THARGOID_LASER;
			
			int passenger_berths = 0;
			BOOL customised = NO;
			BOOL weapon_customised = NO;
			NSString* fwd_weapon_desc = nil;
			
			NSString* short_extras_string = @" Plus %@.";
			
			// customise the ship
			while ((randf() < chance) && ([options count]))
			{
				chance *= chance;	//decrease the chance of a further customisation
				int option_index = ranrot_rand() % [options count];
				NSString* equipment = (NSString*)[options objectAtIndex:option_index];
				int eq_index = NSNotFound;
				int q;
				for (q = 0; (q < [equipmentdata count])&&(eq_index == NSNotFound) ; q++)
				{
					if ([equipment isEqual:[(NSArray*)[equipmentdata objectAtIndex:q] objectAtIndex:EQUIPMENT_KEY_INDEX]])
						eq_index = q;
				}
				if (eq_index != NSNotFound)
				{
					NSArray* equipment_info = (NSArray*)[equipmentdata objectAtIndex:eq_index];
					int eq_price = [(NSNumber*)[equipment_info objectAtIndex:EQUIPMENT_PRICE_INDEX] intValue] / 10;
					int eq_techlevel = [(NSNumber*)[equipment_info objectAtIndex:EQUIPMENT_TECH_LEVEL_INDEX] intValue];
					NSString* eq_short_desc = (NSString*)[equipment_info objectAtIndex:EQUIPMENT_SHORT_DESC_INDEX];
					NSString* eq_long_desc = (NSString*)[equipment_info objectAtIndex:EQUIPMENT_LONG_DESC_INDEX];
					//
					if (eq_techlevel > techlevel)
					{
						// cap maximum tech level
						if (eq_techlevel > 15)
							eq_techlevel = 15;
						// higher tech items are rarer!
						if (randf() * (eq_techlevel - techlevel) < 1.0)
						{
							eq_price *= tech_price_boost + eq_techlevel - techlevel;
						}
						else
						{
							eq_price = 0;	// bar this upgrade
						}
					}
					//
					if (eq_price > 0)
					{
						if (![equipment hasPrefix:@"EQ_WEAPON"])
						{
							if ([equipment isEqual:@"EQ_PASSENGER_BERTH"])
							{
								if ((max_cargo >= 5) && (randf() < chance))
								{
									max_cargo -= 5;
									price += eq_price * 90 / 100;
									[extras addObject:equipment];
									if (passenger_berths == 0)
									{
										[description appendFormat:@" Extra XX=NPB=XXPassenger BerthXX=PPB=XX (%@)", [eq_long_desc lowercaseString]];
										[short_description appendFormat:@" Extra XX=NPB=XXPassenger BerthXX=PPB=XX."];
									}
									passenger_berths++;
									customised = YES;
								}
								else
								{
									[options removeObject:equipment];	// remove the option if there's no space left
								}
							}
							else
							{
								price += eq_price * 90 / 100;
								[extras addObject:equipment];
								[description appendFormat:@" Extra %@ (%@)", eq_short_desc, [eq_long_desc lowercaseString]];
								[short_description appendFormat:short_extras_string, eq_short_desc];
								short_extras_string = @" %@.";
								customised = YES;
							}
						}
						else
						{
							int new_weapon = WEAPON_NONE;
							if ([equipment  isEqual:@"EQ_WEAPON_PULSE_LASER"])
								new_weapon = WEAPON_PULSE_LASER;
							if ([equipment  isEqual:@"EQ_WEAPON_BEAM_LASER"])
								new_weapon = WEAPON_BEAM_LASER;
							if ([equipment  isEqual:@"EQ_WEAPON_MINING_LASER"])
								new_weapon = WEAPON_MINING_LASER;
							if ([equipment  isEqual:@"EQ_WEAPON_MILITARY_LASER"])
								new_weapon = WEAPON_MILITARY_LASER;
							if ([equipment  isEqual:@"EQ_WEAPON_THARGOID_LASER"])
								new_weapon = WEAPON_THARGOID_LASER;
							if (new_weapon > fwd_weapon)
							{
								price -= [self getPriceForWeaponSystemWithKey:fwd_weapon_string] * 90 / 1000;	// 90% credits
								price += eq_price * 90 / 100;
								fwd_weapon_string = equipment;
								fwd_weapon = new_weapon;
								[ship_dict setObject:fwd_weapon_string forKey:@"forward_weapon_type"];
								weapon_customised = YES;
								fwd_weapon_desc = eq_short_desc;
							}
						}
					}
				}
				if ([equipment hasSuffix:@"ENERGY_UNIT"])	// remove ALL the energy unit add-ons
				{
					int q;
					for (q = 0; q < [options count]; q++)
					{
						if ([[options objectAtIndex:q] hasSuffix:@"ENERGY_UNIT"])
							[options removeObjectAtIndex:q--];
					}
				}
				else
				{
					if (![equipment isEqual:@"EQ_PASSENGER_BERTH"])	// let this get added multiple times
						[options removeObject:equipment];
				}
			}
			
			if (passenger_berths)
			{
				NSString* npb = (passenger_berths > 1)? [NSString stringWithFormat:@"%d ", passenger_berths] : @"";
				NSString* ppb = (passenger_berths > 1)? @"s" : @"";
				[description replaceOccurrencesOfString:@"XX=NPB=XX" withString:npb options:NSCaseInsensitiveSearch range:NSMakeRange(0, [description length])];
				[description replaceOccurrencesOfString:@"XX=PPB=XX" withString:ppb options:NSCaseInsensitiveSearch range:NSMakeRange(0, [description length])];
				[short_description replaceOccurrencesOfString:@"XX=NPB=XX" withString:npb options:NSCaseInsensitiveSearch range:NSMakeRange(0, [short_description length])];
				[short_description replaceOccurrencesOfString:@"XX=PPB=XX" withString:ppb options:NSCaseInsensitiveSearch range:NSMakeRange(0, [short_description length])];
			}
			
			if (!customised)
			{
				[description appendString:@" Standard customer model."];
				[short_description appendString:@" Standard customer model."];
			}
			
			if (weapon_customised)
			{
				[description appendFormat:@" Forward weapon has been upgraded to a %@.", [fwd_weapon_desc lowercaseString]];
				[short_description appendFormat:@" Forward weapon upgraded to %@.", [fwd_weapon_desc lowercaseString]];
			}
			
			price = base_price + cunningFee(price - base_price);
				
			[description appendFormat:@" Selling price %d Cr.", price];
			[short_description appendFormat:@" Price %d Cr.", price];

			NSString* ship_id = [NSString stringWithFormat:@"%06x-%06x", super_rand1, super_rand2];

			NSDictionary* ship_info_dictionary = [NSDictionary dictionaryWithObjectsAndKeys:
				ship_id,						SHIPYARD_KEY_ID,
				ship_key,						SHIPYARD_KEY_SHIPDATA_KEY,
				ship_dict,						SHIPYARD_KEY_SHIP,
				description,					SHIPYARD_KEY_DESCRIPTION,
				short_description,				KEY_SHORT_DESCRIPTION,
				[NSNumber numberWithInt:price],	SHIPYARD_KEY_PRICE,
				extras,							KEY_EQUIPMENT_EXTRAS,
				NULL];
			
//			[resultArray addObject:contract_info_dictionary];
			[resultDictionary setObject:ship_info_dictionary forKey:ship_id];	// should order them fairly randomly
		}
		
		// next contract
		rotate_seed(&ship_seed);
		rotate_seed(&ship_seed);
		rotate_seed(&ship_seed);
		rotate_seed(&ship_seed);
	
	}
	
	NSArray* shipsForSale = [resultDictionary allKeys];
	
	for (i = 0; (i < [shipsForSale count])/**&&(i < MAX_SHIPS_FOR_SALE)**/; i++)
		[resultArray addObject:[resultDictionary objectForKey:[shipsForSale objectAtIndex:i]]];
	
//	[resultArray sortUsingFunction:comparePrice context:nil];
	[resultArray sortUsingFunction:compareName context:nil];
	
	// remove identically priced ships of the same name
	i = 1;
	while (i < [resultArray count])
	{
		if (compareName( [resultArray objectAtIndex:i - 1], [resultArray objectAtIndex:i], nil) == NSOrderedSame )
			[resultArray removeObjectAtIndex: i];
		else
			i++;
	}
	
//	NSLog(@"Ships for sale:\n%@", [resultArray description]);
	
	return [NSArray arrayWithArray:resultArray];
}

NSComparisonResult compareName( id dict1, id dict2, void * context)
{	
	NSComparisonResult result = [(NSString*)[(NSDictionary*)[dict1 objectForKey:SHIPYARD_KEY_SHIP] objectForKey:KEY_NAME] compare:(NSString*)[(NSDictionary*)[dict2 objectForKey:SHIPYARD_KEY_SHIP] objectForKey:KEY_NAME]];
	if (result != NSOrderedSame)
		return result;
	else
		return comparePrice(dict1, dict2, context);
}

NSComparisonResult comparePrice( id dict1, id dict2, void * context)
{
	return [(NSNumber*)[(NSDictionary*)dict1 objectForKey:SHIPYARD_KEY_PRICE] compare:(NSNumber*)[(NSDictionary*)dict2 objectForKey:SHIPYARD_KEY_PRICE]];
}

- (int) tradeInValueForCommanderDictionary:(NSDictionary*) cmdr_dict
{
	int result = 0;
	
	// get basic information about the commander's craft
	//
	NSString* cmdr_ship_desc = (NSString*)[cmdr_dict objectForKey:@"ship_desc"];
	int cmdr_fwd_weapon = [(NSNumber*)[cmdr_dict objectForKey:@"forward_weapon"] intValue];
	int cmdr_fwd_weapon_value = 0;
	int cmdr_other_weapons_value = 0;
	int cmdr_aft_weapon = [(NSNumber*)[cmdr_dict objectForKey:@"aft_weapon"] intValue];
	int cmdr_port_weapon = [(NSNumber*)[cmdr_dict objectForKey:@"port_weapon"] intValue];
	int cmdr_starboard_weapon = [(NSNumber*)[cmdr_dict objectForKey:@"starboard_weapon"] intValue];
	int cmdr_missiles = [(NSNumber*)[cmdr_dict objectForKey:@"missiles"] intValue];
	int cmdr_missiles_value = cmdr_missiles * [self getPriceForWeaponSystemWithKey:@"EQ_MISSILE"] / 10;
	int cmdr_max_passengers = [(NSNumber*)[cmdr_dict objectForKey:@"max_passengers"] intValue];
	NSMutableArray* cmdr_extra_equipment = [NSMutableArray arrayWithArray:[(NSDictionary *)[cmdr_dict objectForKey:@"extra_equipment"] allKeys]];
	
	// given the ship model (from cmdr_ship_desc)
	// get the basic information about the standard customer model for that craft
	NSDictionary* shipyard_info = (NSDictionary*)[shipyard objectForKey:cmdr_ship_desc];
	NSDictionary* basic_info = (NSDictionary*)[shipyard_info objectForKey:KEY_STANDARD_EQUIPMENT];
	int base_price = [(NSNumber*)[shipyard_info objectForKey:SHIPYARD_KEY_PRICE] intValue];
	int base_missiles = [(NSNumber*)[basic_info objectForKey:KEY_EQUIPMENT_MISSILES] intValue];
	int base_missiles_value = base_missiles * [self getPriceForWeaponSystemWithKey:@"EQ_MISSILE"] / 10;
	NSString* base_fwd_weapon_key = (NSString*)[basic_info objectForKey:KEY_EQUIPMENT_FORWARD_WEAPON];
	int base_weapon_value = [self getPriceForWeaponSystemWithKey:base_fwd_weapon_key] / 10;
	NSArray* base_extra_equipment = (NSArray*)[basic_info objectForKey:KEY_EQUIPMENT_EXTRAS];
	
//	NSLog(@"DEBUG shipyard_info:\n%@\nbasic_info\n%@\n", [shipyard_info description], [basic_info description]);
	
	// work out weapon values
	if (cmdr_fwd_weapon)
	{
		NSString* weapon_key = [self equipmentKeyForWeapon:cmdr_fwd_weapon];
		cmdr_fwd_weapon_value = [self getPriceForWeaponSystemWithKey:weapon_key] / 10;
	}
	if (cmdr_aft_weapon)
	{
		NSString* weapon_key = [self equipmentKeyForWeapon:cmdr_aft_weapon];
		cmdr_other_weapons_value += [self getPriceForWeaponSystemWithKey:weapon_key] / 10;
	}
	if (cmdr_port_weapon)
	{
		NSString* weapon_key = [self equipmentKeyForWeapon:cmdr_port_weapon];
		cmdr_other_weapons_value += [self getPriceForWeaponSystemWithKey:weapon_key] / 10;
	}
	if (cmdr_starboard_weapon)
	{
		NSString* weapon_key = [self equipmentKeyForWeapon:cmdr_starboard_weapon];
		cmdr_other_weapons_value += [self getPriceForWeaponSystemWithKey:weapon_key] / 10;
	}
	
	// remove from cmdr_extra_equipment any items in base_extra_equipment
	int i,j;
	for (i = 0; i < [base_extra_equipment count]; i++)
	{
		NSString* standard_option = (NSString*)[base_extra_equipment objectAtIndex:i];
		for (j = 0; j < [cmdr_extra_equipment count]; j++)
		{
			if ([(NSString*)[cmdr_extra_equipment objectAtIndex:j] isEqual:standard_option])
				[cmdr_extra_equipment removeObjectAtIndex:j--];
			if ((j > 0)&&([(NSString*)[cmdr_extra_equipment objectAtIndex:j] isEqual:@"EQ_PASSENGER_BERTH"]))
				[cmdr_extra_equipment removeObjectAtIndex:j--];
		}
	}
	
	int extra_equipment_value = cmdr_max_passengers * [self getPriceForWeaponSystemWithKey:@"EQ_PASSENGER_BERTH"] / 10;
	for (j = 0; j < [cmdr_extra_equipment count]; j++)
		extra_equipment_value += [self getPriceForWeaponSystemWithKey:(NSString*)[cmdr_extra_equipment objectAtIndex:j]] / 10;
	
	// final reckoning
	//
//	NSLog(@"DEBUG base_price for %@ %d weapons_bonus %d equipment_bonus %d", cmdr_ship_desc, base_price,
//		cmdr_missiles_value + cmdr_other_weapons_value + cmdr_fwd_weapon_value - base_weapon_value - base_missiles_value,
//		extra_equipment_value);
	
	result = base_price;
	
	// add on extra weapons - base weapons
	result += cmdr_fwd_weapon_value - base_weapon_value;
	result += cmdr_other_weapons_value;
	
	// add on missile values
	result += cmdr_missiles_value - base_missiles_value;
	
	// add on equipment
	result += extra_equipment_value;
	
	return result;
}

- (int) weaponForEquipmentKey:(NSString*) weapon_string
{
	int result = WEAPON_NONE;
	if ([weapon_string  hasSuffix:@"PULSE_LASER"])
		result = WEAPON_PULSE_LASER;
	if ([weapon_string  hasSuffix:@"BEAM_LASER"])
		result = WEAPON_BEAM_LASER;
	if ([weapon_string  hasSuffix:@"MINING_LASER"])
		result = WEAPON_MINING_LASER;
	if ([weapon_string  hasSuffix:@"MILITARY_LASER"])
		result = WEAPON_MILITARY_LASER;
	if ([weapon_string  hasSuffix:@"THARGOID_LASER"])
		result = WEAPON_THARGOID_LASER;
	return result;
}

- (NSString*) equipmentKeyForWeapon:(int) weapon
{
	switch (weapon)
	{
		case WEAPON_PULSE_LASER :
			return [NSString stringWithString:@"EQ_WEAPON_PULSE_LASER"];
		case WEAPON_BEAM_LASER :
			return [NSString stringWithString:@"EQ_WEAPON_BEAM_LASER"];
		case WEAPON_MINING_LASER :
			return [NSString stringWithString:@"EQ_WEAPON_MINING_LASER"];
		case WEAPON_MILITARY_LASER :
			return [NSString stringWithString:@"EQ_WEAPON_MILITARY_LASER"];
		case WEAPON_THARGOID_LASER :
			return [NSString stringWithString:@"EQ_WEAPON_THARGOID_LASER"];
	}
	return nil;
}


- (NSString *) generateSystemDescription:(Random_Seed) s_seed
{
//	seed_for_planet_description (s_seed);
	seed_RNG_only_for_planet_description(s_seed);
	return [self expandDescription:@"[14] is [22]." forSystem:s_seed];
}

- (NSString *) expandDescription:(NSString *) desc forSystem:(Random_Seed)s_seed;
{
	NSMutableString*	partial = [NSMutableString stringWithString:desc];
	
	while ([partial rangeOfString:@"["].location != NSNotFound)
	{
		NSString	*part, *before, *after, *middle;
		int			sub, rnd, opt;
		int			p1 = [partial rangeOfString:@"["].location;
		int			p2 = [partial rangeOfString:@"]"].location + 1;
		
		before = [partial substringWithRange:NSMakeRange(0,p1)];
		after = [partial substringWithRange:NSMakeRange(p2,[partial length] - p2)];
		middle = [partial substringWithRange:NSMakeRange(p1 + 1 , p2 - p1 - 2)];
		
		// check descriptions for an array that's keyed to middle
		if ([[descriptions objectForKey:middle] isKindOfClass:[NSArray class]])
		{
			NSArray* choices = (NSArray*)[descriptions objectForKey:middle];
			rnd = gen_rnd_number() % [choices count];
			part = [NSString stringWithString:(NSString *)[choices objectAtIndex:rnd]];
		}
		else
		{
			// no value for that key so interpret it as a number...
			sub = [middle intValue];
			
			//NSLog(@"Expanding:\t%@",partial);
			rnd = gen_rnd_number();
			opt = 0;
			if (rnd >= 0x33) opt++;
			if (rnd >= 0x66) opt++;
			if (rnd >= 0x99) opt++;
			if (rnd >= 0xCC) opt++;
			
			part = (NSString *)[(NSArray *)[(NSArray *)[descriptions objectForKey:@"system_description"] objectAtIndex:sub] objectAtIndex:opt];
		}
		
		partial = [NSMutableString stringWithFormat:@"%@%@%@",before,part,after];
	}
		
	[partial	replaceOccurrencesOfString:@"%H"
				withString:[self generateSystemName:s_seed]
				options:NSLiteralSearch range:NSMakeRange(0, [partial length])];
	
	[partial	replaceOccurrencesOfString:@"%I"
				withString:[NSString stringWithFormat:@"%@ian",[self generateSystemName:s_seed]]
				options:NSLiteralSearch range:NSMakeRange(0, [partial length])];
				
	[partial	replaceOccurrencesOfString:@"%R"
				withString:[self getRandomDigrams]
				options:NSLiteralSearch range:NSMakeRange(0, [partial length])];

	return [NSString stringWithString:partial]; 
}

- (NSString *) getRandomDigrams
{
	int i;
	int len = gen_rnd_number() & 3;	
//	NSString*			digrams = @"ABOUSEITILETSTONLONUTHNOALLEXEGEZACEBISOUSESARMAINDIREA'ERATENBERALAVETIEDORQUANTEISRION";
	NSString*			digrams = [descriptions objectForKey:@"digrams"];
	NSMutableString*	name = [NSMutableString stringWithCapacity:256];
	for (i = 0; i <=len; i++)
	{
		int x =  gen_rnd_number() & 0x3e;
		[name appendString:[digrams substringWithRange:NSMakeRange(x,2)]];
	}
	return [NSString stringWithString:[name capitalizedString]]; 
}

- (Vector) getWitchspaceExitPosition
{
	Vector result;
	seed_RNG_only_for_planet_description(system_seed);

	// new system is hyper-centric : witchspace exit point is origin
	result.x = 0.0;
	result.y = 0.0;
	result.z = 0.0;
	//
	result.x += SCANNER_MAX_RANGE*(gen_rnd_number()/256.0 - 0.5);   // offset by a set amount, up to 12.8 km
	result.y += SCANNER_MAX_RANGE*(gen_rnd_number()/256.0 - 0.5);
	result.z += SCANNER_MAX_RANGE*(gen_rnd_number()/256.0 - 0.5);
	//
	return result;
}

- (Quaternion) getWitchspaceExitRotation
{
	// this should be fairly close to {0,0,0,1}
	Quaternion q_result;
	seed_RNG_only_for_planet_description(system_seed);

	//
	q_result.x = (gen_rnd_number() - 128)/1024.0;
	q_result.y = (gen_rnd_number() - 128)/1024.0;
	q_result.z = (gen_rnd_number() - 128)/1024.0;
	q_result.w = 1.0;
	quaternion_normalise(&q_result);
	//
	return q_result;
}

- (Vector) getSunSkimStartPositionForShip:(ShipEntity*) ship
{
	if (!ship)
	{
		NSLog(@"ERROR ***** No ship set in Universe getSunSkimStartPositionForShip:");
		NSBeep();
		return make_vector(0,0,0);
	}
	PlanetEntity* the_sun = [self sun];
	// get vector from sun position to ship
	if (!the_sun)
	{
		NSLog(@"ERROR ***** No sun set in Universe getSunSkimStartPositionForShip:");
		NSBeep();
		return make_vector(0,0,0);
	}
	Vector v0 = the_sun->position;
	Vector v1 = ship->position;
	v1.x -= v0.x;	v1.y -= v0.y;	v1.z -= v0.z;	// vector from sun to ship
	if (v1.x||v1.y||v1.z)
		v1 = unit_vector(&v1);
	else
		v1.z = 1.0;
	double radius = SUN_SKIM_RADIUS_FACTOR * the_sun->collision_radius - 250.0; // 250 m inside the skim radius
	v1.x *= radius;	v1.y *= radius;	v1.z *= radius;
	v1.x += v0.x;	v1.y += v0.y;	v1.z += v0.z;
	
	return v1;
}

- (Vector) getSunSkimEndPositionForShip:(ShipEntity*) ship
{
	PlanetEntity* the_sun = [self sun];
	if (!ship)
	{
		NSLog(@"ERROR ***** No ship set in Universe getSunSkimEndPositionForShip:");
		NSBeep();
		return make_vector(0,0,0);
	}
	// get vector from sun position to ship
	if (!the_sun)
	{
		NSLog(@"ERROR ***** No sun set in Universe getSunSkimEndPositionForShip:");
		NSBeep();
		return make_vector(0,0,0);
	}
	Vector v0 = the_sun->position;
	Vector v1 = ship->position;
	v1.x -= v0.x;	v1.y -= v0.y;	v1.z -= v0.z;
	if (v1.x||v1.y||v1.z)
		v1 = unit_vector(&v1);
	else
		v1.z = 1.0;
	Vector v2 = make_vector(randf()-0.5, randf()-0.5, randf()-0.5);	// random vector
	if (v2.x||v2.y||v2.z)
		v2 = unit_vector(&v2);
	else
		v2.x = 1.0;
	Vector v3 = cross_product( v1, v2);	// random vector at 90 degrees to v1 and v2 (random Vector)
	if (v3.x||v3.y||v3.z)
		v3 = unit_vector(&v3);
	else
		v3.y = 1.0;
	double radius = the_sun->collision_radius * SUN_SKIM_RADIUS_FACTOR - 250.0; // 250 m inside the skim radius
	v1.x *= radius;	v1.y *= radius;	v1.z *= radius;
	v1.x += v0.x;	v1.y += v0.y;	v1.z += v0.z;
	v1.x += 15000 * v3.x;	v1.y += 15000 * v3.y;	v1.z += 15000 * v3.z;	// point 15000m at a tangent to sun from v1
	v1.x -= v0.x;	v1.y -= v0.y;	v1.z -= v0.z;
	if (v1.x||v1.y||v1.z)
		v1 = unit_vector(&v1);
	else
		v1.z = 1.0;
	v1.x *= radius;	v1.y *= radius;	v1.z *= radius;
	v1.x += v0.x;	v1.y += v0.y;	v1.z += v0.z;
	
	return v1;
}

///////////////////////////////////////

- (GuiDisplayGen *) gui
{
	return gui;
}

- (GuiDisplayGen *) comm_log_gui
{
	return comm_log_gui;
}

- (void) clearGUIs
{
	[gui clear];
	[message_gui clear];
	[comm_log_gui clear];
	[comm_log_gui printLongText:@"Communications Log" Align:GUI_ALIGN_CENTER Color:[NSColor yellowColor] FadeTime:0 Key:nil AddToArray:nil];
}

- (void) resetCommsLogColor
{
	[comm_log_gui setTextColor:[NSColor whiteColor]];
}

- (void) setDisplayCursor:(BOOL) value
{
	displayCursor = value;
#ifdef GNUSTEP
	if ([gameView inFullScreenMode])
	{
		if (displayCursor == YES)
		{
			if (SDL_ShowCursor(SDL_QUERY) == SDL_DISABLE)
				SDL_ShowCursor(SDL_ENABLE);
		}
		else
		{
			if (SDL_ShowCursor(SDL_QUERY) == SDL_ENABLE)
				SDL_ShowCursor(SDL_DISABLE);
		}
	}
#endif
}

- (BOOL) displayCursor
{
	return displayCursor;
}

- (void) setDisplayText:(BOOL) value
{
	displayGUI = value;
}

- (BOOL) displayGUI
{
	return displayGUI;
}

- (void) setDisplayFPS:(BOOL) value
{
	displayFPS = value;
}

- (BOOL) displayFPS
{
	return displayFPS;
}

- (void) setReducedDetail:(BOOL) value
{
	reducedDetail = value;
}

- (BOOL) reducedDetail
{
	return reducedDetail;
}


- (void) handleOoliteException:(NSException*) ooliteException
{
	if (ooliteException)
	{
		if ([[ooliteException name] isEqual: OOLITE_EXCEPTION_FATAL])
		{
			exception = [ooliteException retain];
			
			PlayerEntity* player = (PlayerEntity*)[self entityZero];
			[player setStatus:STATUS_HANDLING_ERROR];
			
			NSLog(@"***** Handling Fatal : %@ : %@ *****",[exception name], [exception reason]);
			NSString* exception_msg = [NSString stringWithFormat:@"Exception : %@ : %@ Please take a screenshot and/or press esc or Q to quit.", [exception name], [exception reason]];
			[self addMessage:exception_msg forCount:30.0];
			[[self gameController] pause_game];
		}
		else
		{
			NSLog(@"***** Handling Non-fatal : %@ : %@ *****",[ooliteException name], [ooliteException reason]);
		}
	}
}



// speech routines
//
- (void) startSpeakingString:(NSString *) text
{
#ifndef GNUSTEP
//	if (speechChannel == nil)
//		NewSpeechChannel(NULL,&speechChannel);
//	SpeakText(speechChannel,[text UTF8String],[text length]);
	if ([OOSound respondsToSelector:@selector(masterVolume)])
		[speechSynthesizer startSpeakingString:[NSString stringWithFormat:@"[[volm %.3f]]%@", [OOSound masterVolume], text]];
	else
		[speechSynthesizer startSpeakingString:text];
#endif
}
//
- (void) stopSpeaking
{
#ifndef GNUSTEP
//	if (speechChannel == nil)
//		NewSpeechChannel(NULL,&speechChannel);
//	StopSpeech(speechChannel);
	[speechSynthesizer stopSpeaking];
#endif
}
//
- (BOOL) isSpeaking
{
#ifdef GNUSTEP
   return 0;
#else
	return [speechSynthesizer isSpeaking];
#endif
}
//
////

@end
