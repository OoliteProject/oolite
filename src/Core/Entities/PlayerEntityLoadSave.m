/*
 
 PlayerEntityLoadSave.m
 
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

#import "PlayerEntityLoadSave.h"
#import "PlayerEntityContracts.h"
#import "PlayerEntityControls.h"
#import "PlayerEntitySound.h"

#import "NSFileManagerOOExtensions.h"
#import "GameController.h"
#import "ResourceManager.h"
#import "OOStringExpander.h"
#import "PlayerEntityControls.h"
#import "ProxyPlayerEntity.h"
#import "ShipEntityAI.h"
#import "OOXMLExtensions.h"
#import "OOSound.h"
#import "OOColor.h"
#import "OOStringParsing.h"
#import "OOPListParsing.h"
#import "StationEntity.h"
#import "OOCollectionExtractors.h"
#import "OOConstToString.h"
#import "OOShipRegistry.h"
#import "OOTexture.h"
#import "NSStringOOExtensions.h"
#import "NSNumberOOExtensions.h"
#import "OOJavaScriptEngine.h"


// Name of modifier key used to issue commands. See also -isCommandModifierKeyDown.
#if OO_USE_CUSTOM_LOAD_SAVE
#define COMMAND_MODIFIER_KEY		"Ctrl"
#endif


static uint16_t PersonalityForCommanderDict(NSDictionary *dict);


#if OO_USE_CUSTOM_LOAD_SAVE

@interface MyOpenGLView (OOLoadSaveExtensions)

- (BOOL)isCommandModifierKeyDown;

@end

#endif


@interface PlayerEntity (OOLoadSavePrivate)

#if OOLITE_USE_APPKIT_LOAD_SAVE

- (BOOL) loadPlayerWithPanel;
- (void) savePlayerWithPanel;

#endif

#if OO_USE_CUSTOM_LOAD_SAVE

- (void) setGuiToLoadCommanderScreen;
- (void) setGuiToSaveCommanderScreen: (NSString *)cdrName;
- (void) setGuiToOverwriteScreen: (NSString *)cdrName;
- (void) lsCommanders: (GuiDisplayGen *)gui directory: (NSString*)directory pageNumber: (int)page highlightName: (NSString *)highlightName;
- (void) showCommanderShip: (int)cdrArrayIndex;
- (int) findIndexOfCommander: (NSString *)cdrName;
- (void) nativeSavePlayer: (NSString *)cdrName;
- (BOOL) existingNativeSave: (NSString *)cdrName;

#endif

- (void) writePlayerToPath:(NSString *)path;

@end


@implementation PlayerEntity (LoadSave)

- (BOOL)loadPlayer
{
	BOOL				OK = YES;
	
#if OO_USE_APPKIT_LOAD_SAVE_ALWAYS
	OK = [self loadPlayerWithPanel];
#elif OOLITE_USE_APPKIT_LOAD_SAVE
	// OS X: use system open/save dialogs in windowed mode, custom interface in full-screen.
	if ([[UNIVERSE gameController] inFullScreenMode])
	{
		[self setGuiToLoadCommanderScreen];
	}
	else
	{
		OK = [self loadPlayerWithPanel];
	}
#else
	// Other platforms: use custom interface all the time.
	[self setGuiToLoadCommanderScreen];
#endif
	return OK;
}


- (void)savePlayer
{
#if OO_USE_APPKIT_LOAD_SAVE_ALWAYS
	[self savePlayerWithPanel];
#elif OOLITE_USE_APPKIT_LOAD_SAVE
	// OS X: use system open/save dialogs in windowed mode, custom interface in full-screen.
	if ([[UNIVERSE gameController] inFullScreenMode])
	{
		[self setGuiToSaveCommanderScreen:self.lastsaveName];
	}
	else
	{
		[self savePlayerWithPanel];
	}
#else
	// Other platforms: use custom interface all the time.
	[self setGuiToSaveCommanderScreen:[self lastsaveName]];
#endif
}

- (void) autosavePlayer
{
	NSString		*tmp_path = nil;
	NSString		*tmp_name = nil;
	NSString		*dir = [[UNIVERSE gameController] playerFileDirectory];
	
	tmp_name = [self lastsaveName];
	tmp_path = save_path;
	
	ShipScriptEventNoCx(self, "playerWillSaveGame", OOJSSTR("AUTO_SAVE"));
	
	NSString *saveName = [self lastsaveName];
	NSString *autosaveSuffix = DESC(@"autosave-commander-suffix");
	
	if (![saveName hasSuffix:autosaveSuffix])
	{
		saveName = [saveName stringByAppendingString:autosaveSuffix];
	}
	NSString *savePath = [dir stringByAppendingPathComponent:[saveName stringByAppendingString:@".oolite-save"]];
	
	[self setLastsaveName:saveName];
	
	@try
	{
		[self writePlayerToPath:savePath];
	}
	@catch (id exception)
	{
		// Suppress exceptions silently. Warning the user about failed autosaves would be pretty unhelpful.
	}
	
	if (tmp_path != nil)
	{
		[save_path autorelease];
		save_path = [tmp_path copy];
	}
	[self setLastsaveName:tmp_name];
}


- (void) quicksavePlayer
{
	MyOpenGLView	*gameView = [UNIVERSE gameView];
	NSString		*path = nil;
	
	path = save_path;
	if (!path)  path = [[gameView gameController] playerFileToLoad];
	if (!path)
	{
		OOLog(@"quickSave.failed.noName", @"ERROR no file name returned by [[gameView gameController] playerFileToLoad]");
		[NSException raise:@"OoliteGameNotSavedException"
					format:@"ERROR no file name returned by [[gameView gameController] playerFileToLoad]"];
	}
	
	ShipScriptEventNoCx(self, "playerWillSaveGame", OOJSSTR("QUICK_SAVE"));
	
	[self writePlayerToPath:path];
	[[UNIVERSE gameView] supressKeysUntilKeyUp];
	[self setGuiToStatusScreen];
}


- (void) setGuiToScenarioScreen:(int)page
{
	NSArray *scenarios = [UNIVERSE scenarios];
	[UNIVERSE removeDemoShips];
	// GUI stuff
	{
		GuiDisplayGen	*gui = [UNIVERSE gui];
		OOGUIRow		start_row = GUI_ROW_SCENARIOS_START;
		OOGUIRow		row = start_row;
		BOOL			guiChanged = (gui_screen != GUI_SCREEN_NEWGAME);

		[gui clearAndKeepBackground:!guiChanged];
		[gui setTitle:DESC(@"oolite-newgame-title")];

		OOGUITabSettings tab_stops;
		tab_stops[0] = 0;
		tab_stops[1] = -480;
		[gui setTabStops:tab_stops];

		unsigned n_rows = GUI_MAX_ROWS_SCENARIOS;
		NSUInteger i, count = [scenarios count];

		NSDictionary *scenario = nil;

		[gui setArray:[NSArray arrayWithObjects:DESC(@"oolite-scenario-exit"), @" <----- ", nil] forRow:start_row - 2];
		[gui setColor:[OOColor redColor] forRow:start_row - 2];
		[gui setKey:@"exit" forRow:start_row - 2];
		

		if (page > 0)
		{
			[gui setArray:[NSArray arrayWithObjects:DESC(@"gui-back"), @" <-- ", nil] forRow:start_row - 1];
			[gui setColor:[OOColor greenColor] forRow:start_row - 1];
			[gui setKey:[NSString stringWithFormat:@"__page:%i",page-1] forRow:start_row - 1];
		}

		[self setShowDemoShips:NO];

		for (i = page*n_rows ; i < count && row < start_row + n_rows ; i++)
		{
			scenario = [[UNIVERSE scenarios] objectAtIndex:i];
			[gui setText:OOExpand([NSString stringWithFormat:@" %@ ",[scenario oo_stringForKey:@"name"]]) forRow:row];
			[gui setKey:[NSString stringWithFormat:@"Scenario:%lu", (unsigned long)i] forRow:row];
			++row;
		}

		if ((page+1) * n_rows < count)
		{
			[gui setArray:[NSArray arrayWithObjects:DESC(@"gui-more"), @" --> ", nil] forRow:row];
			[gui setColor:[OOColor greenColor] forRow:row];
			[gui setKey:[NSString stringWithFormat:@"__page:%i",page+1] forRow:row];
			++row;
		}
		
		[gui setSelectableRange:NSMakeRange(start_row - 2,3 + row - start_row)];
		[gui setSelectedRow:start_row];
		[self showScenarioDetails];

		gui_screen = GUI_SCREEN_NEWGAME;
	
		if (guiChanged)
		{
			[gui setBackgroundTextureKey:@"newgame"];
			[gui setForegroundTextureKey:@"newgame_overlay"];
		}
	}
	
	[UNIVERSE enterGUIViewModeWithMouseInteraction:YES];
}

- (void) addScenarioModel:(NSString *)shipKey
{
	[self showShipModelWithKey:shipKey shipData:nil personality:ENTITY_PERSONALITY_INVALID factorX:1.2 factorY:0.8 factorZ:6.4 inContext:@"scenario"];
}


- (void) showScenarioDetails
{
	GuiDisplayGen* gui = [UNIVERSE gui];
	NSString* key = [gui selectedRowKey];
	[UNIVERSE removeDemoShips];

	if ([key hasPrefix:@"Scenario"])
	{
		int item = [[key componentsSeparatedByString:@":"] oo_intAtIndex:1];
		NSDictionary *scenario = [[UNIVERSE scenarios] objectAtIndex:item];
		[self setShowDemoShips:NO];
		for (NSUInteger i=GUI_ROW_SCENARIOS_DETAIL;i<=27;i++)
		{
			[gui setText:@"" forRow:i];
		}
		if (scenario)
		{
			[gui addLongText:OOExpand([scenario oo_stringForKey:@"description"]) startingAtRow:GUI_ROW_SCENARIOS_DETAIL align:GUI_ALIGN_LEFT];
			NSString *shipKey = [scenario oo_stringForKey:@"model"];
			if (shipKey != nil)
			{
				[self addScenarioModel:shipKey];
				[self setShowDemoShips:YES];
			}
		}

	}
}


- (BOOL) startScenario
{
	GuiDisplayGen* gui = [UNIVERSE gui];
	NSString* key = [gui selectedRowKey];

	if ([key isEqualToString:@"exit"])
	{
		// intended to return to main menu
		return NO; 
	}
	if ([key hasPrefix:@"__page"])
	{
		int page = [[key componentsSeparatedByString:@":"] oo_intAtIndex:1];
		[self setGuiToScenarioScreen:page];
		return YES;
	}
	int selection = [[key componentsSeparatedByString:@":"] oo_intAtIndex:1];

	NSDictionary *scenario = [[UNIVERSE scenarios] objectAtIndex:selection];
	NSString *file = [scenario oo_stringForKey:@"file" defaultValue:nil];
	if (file == nil) 
	{
		OOLog(@"scenario.init.error",@"No file entry found for scenario");
		return NO;
	}
	NSString *path = [ResourceManager pathForFileNamed:file inFolder:@"Scenarios"];
	if (path == nil)
	{
		OOLog(@"scenario.init.error",@"Game file not found for scenario %@",file);
		return NO;
	}
	BOOL result = [self loadPlayerFromFile:path asNew:YES];
	if (!result)
	{
		return NO;
	}
	[scenarioKey release];
	scenarioKey = [[scenario oo_stringForKey:@"scenario" defaultValue:nil] retain];

	// don't drop the save game directory in
	return YES;
}




#if OO_USE_CUSTOM_LOAD_SAVE

- (NSString *)commanderSelector
{
	MyOpenGLView	*gameView = [UNIVERSE gameView];
	GuiDisplayGen	*gui = [UNIVERSE gui];
	NSString		*dir = [[UNIVERSE gameController] playerFileDirectory];
	
	int idx;
	if([self handleGUIUpDownArrowKeys])
	{
		int guiSelectedRow=[gui selectedRow];
		idx=(guiSelectedRow - STARTROW) + (currentPage * NUMROWS);
		if (guiSelectedRow != MOREROW && guiSelectedRow != BACKROW && guiSelectedRow != EXITROW)
		{
			[self showCommanderShip: idx];
		}
		else
		{
			[UNIVERSE removeDemoShips];
			[gui setText:@"" forRow:CDRDESCROW align:GUI_ALIGN_LEFT];
			[gui setText:@"" forRow:CDRDESCROW + 1 align:GUI_ALIGN_LEFT];
			[gui setText:@"" forRow:CDRDESCROW + 2 align:GUI_ALIGN_LEFT];
		}

	}
	else
	{
		idx=([gui selectedRow] - STARTROW) + (currentPage * NUMROWS);
	}
	
	// handle page <-- and page --> keys
	if ([gameView isDown:gvArrowKeyLeft] && [[gui keyForRow:BACKROW] isEqual: GUI_KEY_OK])
	{
		currentPage--;
		[self playMenuPagePrevious];
		[self lsCommanders: gui	directory: dir	pageNumber: currentPage  highlightName: nil];
		[gameView supressKeysUntilKeyUp];
	}
	//
	if ([gameView isDown:gvArrowKeyRight] && [[gui keyForRow:MOREROW] isEqual: GUI_KEY_OK])
	{
		currentPage++;
		[self playMenuPageNext];
		[self lsCommanders: gui	directory: dir	pageNumber: currentPage  highlightName: nil];
		[gameView supressKeysUntilKeyUp];
	}
	
	// Enter pressed - find the commander name underneath.
	if ([gameView isDown:13]||[gameView isDown:gvMouseDoubleClick])
	{
		NSDictionary *cdr;
		switch ([gui selectedRow])
		{
			case EXITROW:
				if ([self status] == STATUS_START_GAME)
				{
					[self setGuiToIntroFirstGo:YES];
					return nil;
				}
				break;
			case BACKROW:
				currentPage--;
				[self lsCommanders: gui	directory: dir	pageNumber: currentPage  highlightName: nil];
				[gameView supressKeysUntilKeyUp];
				break;
			case MOREROW:
				currentPage++;
				[self lsCommanders: gui	directory: dir	pageNumber: currentPage  highlightName: nil];
				[gameView supressKeysUntilKeyUp];
				break;
			default:
				cdr=[cdrDetailArray objectAtIndex: idx];
				if ([cdr oo_boolForKey:@"isSavedGame"])
					return [cdr oo_stringForKey:@"saved_game_path"];
				else
				{
					if ([gameView isCommandModifierKeyDown]||[gameView isDown:gvMouseDoubleClick])
					{
						// change directory to the selected path
						NSString* newDir = [cdr oo_stringForKey:@"saved_game_path"];
						[[UNIVERSE gameController] setPlayerFileDirectory: newDir];
						dir = newDir;
						currentPage = 0;
						[self lsCommanders: gui	directory: dir	pageNumber: currentPage  highlightName: nil];
						[gameView supressKeysUntilKeyUp];
					}
				}
		}
	}
	
	if([gameView isDown: 27]) // escape key
	{
		[self setGuiToStatusScreen];
	}
	return nil;
}


- (void) saveCommanderInputHandler
{
	MyOpenGLView	*gameView = [UNIVERSE gameView];
	GuiDisplayGen	*gui = [UNIVERSE gui];
	NSString		*dir = [[UNIVERSE gameController] playerFileDirectory];
	
	if ([self handleGUIUpDownArrowKeys])
	{
		int guiSelectedRow=[gui selectedRow];
		int	idx = (guiSelectedRow - STARTROW) + (currentPage * NUMROWS);
		if (guiSelectedRow != MOREROW && guiSelectedRow != BACKROW)
		{
			[self showCommanderShip: idx];
			if ([(NSDictionary *)[cdrDetailArray objectAtIndex:idx] oo_boolForKey:@"isSavedGame"])	// don't show things that aren't saved games
				commanderNameString = [[cdrDetailArray oo_dictionaryAtIndex:idx] oo_stringForKey:@"player_save_name" defaultValue:[[cdrDetailArray oo_dictionaryAtIndex:idx] oo_stringForKey:@"player_name"]];
			else
				commanderNameString = [gameView typedString];
		}
		else
		{
			[UNIVERSE removeDemoShips];
			[gui setText:@"" forRow:CDRDESCROW align:GUI_ALIGN_LEFT];
			[gui setText:@"" forRow:CDRDESCROW + 1 align:GUI_ALIGN_LEFT];
			[gui setText:@"" forRow:CDRDESCROW + 2 align:GUI_ALIGN_LEFT];
		}
	}
	else
	{
		commanderNameString = [gameView typedString];
	}
	
	[gameView setTypedString: commanderNameString];
	
	[gui setText:
		[NSString stringWithFormat:DESC(@"savescreen-commander-name-@"), commanderNameString]
		  forRow: INPUTROW];
	[gui setColor:[OOColor cyanColor] forRow:INPUTROW];
	
	// handle page <-- and page --> keys, and on-screen buttons
	if (((([gameView isDown:gvMouseDoubleClick] || [gameView isDown: 13]) && [gui selectedRow] == BACKROW) || [gameView isDown:gvArrowKeyLeft])
					&& [[gui keyForRow:BACKROW] isEqual: GUI_KEY_OK])
	{
		currentPage--;
		[self lsCommanders: gui	directory: dir	pageNumber: currentPage  highlightName: nil];
		[gameView supressKeysUntilKeyUp];
	}
	//
	if (((([gameView isDown:gvMouseDoubleClick] || [gameView isDown: 13]) && [gui selectedRow] == MOREROW) || [gameView isDown:gvArrowKeyRight])
					&& [[gui keyForRow:MOREROW] isEqual: GUI_KEY_OK])
	{
		currentPage++;
		[self lsCommanders: gui	directory: dir	pageNumber: currentPage  highlightName: nil];
		[gameView supressKeysUntilKeyUp];
	}
	
	if(([gameView isDown: 13]||[gameView isDown:gvMouseDoubleClick]) && [commanderNameString length])
	{
		if ([gameView isCommandModifierKeyDown]||[gameView isDown:gvMouseDoubleClick])
		{
			int guiSelectedRow=[gui selectedRow];
			int	idx = (guiSelectedRow - STARTROW) + (currentPage * NUMROWS);
			NSDictionary* cdr = [cdrDetailArray objectAtIndex:idx];
			
			if (![cdr oo_boolForKey:@"isSavedGame"])	// don't open saved games
			{
				// change directory to the selected path
				NSString* newDir = [cdr oo_stringForKey:@"saved_game_path"];
				[[UNIVERSE gameController] setPlayerFileDirectory: newDir];
				dir = newDir;
				currentPage = 0;
				[self lsCommanders: gui	directory: dir	pageNumber: currentPage  highlightName: nil];
				[gameView supressKeysUntilKeyUp];
			}
		}
		else
		{
			pollControls = YES;
			if ([self existingNativeSave: commanderNameString])
			{
				[gameView supressKeysUntilKeyUp];
				[self setGuiToOverwriteScreen: commanderNameString];
			}
			else
			{
				[self nativeSavePlayer: commanderNameString];
				[[UNIVERSE gameView] supressKeysUntilKeyUp];
				[self setGuiToStatusScreen];
			}
		}
	}
	
	if([gameView isDown: 27]) // escape key
	{
		// get out of here
		pollControls = YES;
		[[UNIVERSE gameView] resetTypedString];
		[self setGuiToStatusScreen];
	}
}


- (void) overwriteCommanderInputHandler
{
	MyOpenGLView	*gameView = [UNIVERSE gameView];
	GuiDisplayGen	*gui = [UNIVERSE gui];
	
	[self handleGUIUpDownArrowKeys];
	
	// Translation issue: we can't confidently use raw Y and N ascii as shortcuts. It's better to use the load-previous-commander keys.
	id valueYes = [[[UNIVERSE descriptions] oo_stringForKey:@"load-previous-commander-yes" defaultValue:@"y"] lowercaseString];
	id valueNo = [[[UNIVERSE descriptions] oo_stringForKey:@"load-previous-commander-no" defaultValue:@"n"] lowercaseString];
	unsigned char cYes, cNo;
	
	cYes = [valueYes characterAtIndex: 0] & 0x00ff;	// Use lower byte of unichar.
	cNo = [valueNo characterAtIndex: 0] & 0x00ff;	// Use lower byte of unichar.
	
	if (([gameView isDown:13] && ([gui selectedRow] == SAVE_OVERWRITE_YES_ROW))||[gameView isDown:cYes]||[gameView isDown:cYes - 32])
	{
		pollControls=YES;
		[self nativeSavePlayer: commanderNameString];
		[self playSaveOverwriteYes];
		[[UNIVERSE gameView] supressKeysUntilKeyUp];
		[self setGuiToStatusScreen];
	}
	
	if (([gameView isDown:13] && ([gui selectedRow] == SAVE_OVERWRITE_NO_ROW))||[gameView isDown:27]||[gameView isDown:cNo]||[gameView isDown:cNo - 32])
	{
		// esc or NO was pressed - get out of here
		pollControls=YES;
		[self playSaveOverwriteNo];
		[self setGuiToSaveCommanderScreen:@""];
	}
}

#endif


- (BOOL) loadPlayerFromFile:(NSString *)fileToOpen asNew:(BOOL)asNew
{
	/*	TODO: it would probably be better to load by creating a new
		PlayerEntity, verifying that's OK, then replacing the global player.
		
		Actually, it'd be better to separate PlayerEntity into OOPlayer and
		OOPlayerShipEntity. And then move most of OOPlayerShipEntity into
		ShipEntity, and make NPC ships behave more like player ships.
		-- Ahruman
	*/
	
	BOOL			loadedOK = YES;
	NSDictionary	*fileDic = nil;
	NSString		*fail_reason = nil;
	
	if (fileToOpen == nil)
	{
		fail_reason = DESC(@"loadfailed-no-file-specified");
		loadedOK = NO;
	}
	
	if (loadedOK)
	{
		fileDic = OODictionaryFromFile(fileToOpen);
		if (fileDic == nil)
		{
			fail_reason = DESC(@"loadfailed-could-not-load-file");
			loadedOK = NO;
		}
	}
	
	if (loadedOK)
	{
		NSString		*shipKey = nil;
		NSDictionary	*shipDict = nil;
		
		shipKey = [fileDic oo_stringForKey:@"ship_desc"];
		shipDict = [[OOShipRegistry sharedRegistry] shipInfoForKey:shipKey];
		
		if (shipDict == nil && [UNIVERSE strict] && shipKey != nil)
		{
			fail_reason = [NSString stringWithFormat:DESC(@"loadfailed-could-not-use-ship-type-@-please-switch-to-unrestricted"), shipKey];
			loadedOK = NO;
		}
	}	
		
	
	if (loadedOK)
	{
		// Check that player ship exists
		NSString		*shipKey = nil;
		NSDictionary	*shipDict = nil;
		
		shipKey = [fileDic oo_stringForKey:@"ship_desc"];
		shipDict = [[OOShipRegistry sharedRegistry] shipInfoForKey:shipKey];
		
		if (shipDict == nil)
		{
			loadedOK = NO;
			if (shipKey != nil)  fail_reason = [NSString stringWithFormat:DESC(@"loadfailed-could-not-find-ship-type-@-please-reinstall-the-appropriate-OXP"), shipKey];
			else  fail_reason = DESC(@"loadfailed-invalid-saved-game-no-ship-specified");
		}
	}
	
	if (loadedOK)
	{
		if (![self setUpAndConfirmOK:YES saveGame:YES])
		{
			fail_reason = DESC(@"loadfailed-could-not-reset-javascript");
			loadedOK = NO;
		}
	}
	
	if (loadedOK)
	{
		if (![self setCommanderDataFromDictionary:fileDic])
		{
			// this could still be a reset js issue, if switching from strict / unrestricted
			// TODO: use "could not reset js message" if that's the case.
			fail_reason = DESC(@"loadfailed-could-not-set-up-player-ship");
			loadedOK = NO;
		}
	}
	
	if (loadedOK)
	{
		if (!asNew)
		{
			[save_path autorelease];
			save_path = [fileToOpen retain];
		
			[[[UNIVERSE gameView] gameController] setPlayerFileToLoad:fileToOpen];
			[[[UNIVERSE gameView] gameController] setPlayerFileDirectory:fileToOpen];
		}
	}
	else
	{
		OOLog(@"load.failed", @"***** Failed to load saved game \"%@\": %@", [fileToOpen lastPathComponent], fail_reason ? fail_reason : (NSString *)@"unknown error");
		[[UNIVERSE gameController] setPlayerFileToLoad:nil];
		[UNIVERSE handleGameOver];
		[UNIVERSE clearPreviousMessage];
		[UNIVERSE addMessage:DESC(@"loadfailed-saved-game-failed-to-load") forCount: 9.0];
		if (fail_reason != nil)  [UNIVERSE addMessage: fail_reason forCount: 9.0];
		return NO;
	}
	
	[UNIVERSE setTimeAccelerationFactor:TIME_ACCELERATION_FACTOR_DEFAULT];
	[UNIVERSE setSystemTo:system_seed];
	[UNIVERSE removeAllEntitiesExceptPlayer];
	[UNIVERSE setGalaxySeed: galaxy_seed andReinit:YES]; // set overridden planet names on long range map
	[UNIVERSE setUpSpace];
	[UNIVERSE setAutoSaveNow:NO];
	
	[self setDockedAtMainStation];
	StationEntity *dockedStation = [self dockedStation];
	
	[UNIVERSE enterGUIViewModeWithMouseInteraction:NO];
	
	if (dockedStation)
	{
		position = [dockedStation position];
		[self setOrientation: kIdentityQuaternion];
		v_forward = vector_forward_from_quaternion(orientation);
		v_right = vector_right_from_quaternion(orientation);
		v_up = vector_up_from_quaternion(orientation);
	}
	
	flightRoll = 0.0;
	flightPitch = 0.0;
	flightYaw = 0.0;
	flightSpeed = 0.0;
	
	[self setEntityPersonalityInt:PersonalityForCommanderDict(fileDic)];
	
	// dockedStation is always the main station at this point;
	// "localMarket" save key always refers to the main station (system) market
	NSArray *market = [fileDic oo_arrayForKey:@"localMarket"];
	if (market != nil)  [dockedStation setLocalMarket:market];
	else  [dockedStation initialiseLocalMarketWithRandomFactor:market_rnd];

	[self calculateCurrentCargo];
	
	// set scenario key if the scenario allows saving and has one
	NSString *scenario = [fileDic oo_stringForKey:@"scenario_key" defaultValue:nil];
	DESTROY(scenarioKey);
	if (scenario != nil)
	{
		scenarioKey = [scenario retain];
	}

	// Remember the savegame target, run js startUp.
	[self completeSetUpAndSetTarget:NO];
	// run initial system population
	[UNIVERSE populateNormalSpace];

	// might as well start off with a collected JS environment
	[[OOJavaScriptEngine sharedEngine] garbageCollectionOpportunity:YES];
	
	// read saved position vector and primary role, check for an
	// appropriate station at those coordinates, if found, switch
	// docked station to that one.
	HPVector dockedPos = [fileDic oo_hpvectorForKey:@"docked_station_position"];
	NSString *dockedRole = [fileDic oo_stringForKey:@"docked_station_role" defaultValue:@""];
	StationEntity *saveStation = [UNIVERSE stationWithRole:dockedRole andPosition:dockedPos];
	if (saveStation != nil && [saveStation allowsSaving])
	{
		[self setDockedStation:saveStation];
		position = [saveStation position];
	}
	// and initialise markets for the secondary stations
	[UNIVERSE loadStationMarkets:[fileDic oo_arrayForKey:@"station_markets"]];

	[self startUpComplete];

	[[UNIVERSE gameView] supressKeysUntilKeyUp];
	[self setGuiToStatusScreen];
	if (loadedOK) [self doWorldEventUntilMissionScreen:OOJSID("missionScreenOpportunity")];  // trigger missionScreenOpportunity immediately after loading
	return loadedOK;
}

@end


@implementation PlayerEntity (OOLoadSavePrivate)

#if OOLITE_USE_APPKIT_LOAD_SAVE

- (BOOL)loadPlayerWithPanel
{
	NSOpenPanel *oPanel = [NSOpenPanel openPanel];
	
	oPanel.allowsMultipleSelection = NO;
	oPanel.allowedFileTypes = [NSArray arrayWithObject:@"oolite-save"];
	
	if ([oPanel runModal] == NSOKButton)
	{
		NSURL *url = oPanel.URL;
		if (url.isFileURL)
		{
			return [self loadPlayerFromFile:url.path asNew:NO];
		}
	}
	
	return NO;
}


- (void) savePlayerWithPanel
{
	NSSavePanel *sPanel = [NSSavePanel savePanel];
	
	sPanel.allowedFileTypes = [NSArray arrayWithObject:@"oolite-save"];
	sPanel.canSelectHiddenExtension = YES;
	sPanel.nameFieldStringValue = self.lastsaveName;
	
	if ([sPanel runModal] == NSOKButton)
	{
		NSURL *url = sPanel.URL;
		NSAssert(url.isFileURL, @"Save panel with default configuration should not provide non-file URLs.");
		
		NSString *path = url.path;
		NSString *newName = [path.lastPathComponent stringByDeletingPathExtension];
		
		ShipScriptEventNoCx(self, "playerWillSaveGame", OOJSSTR("STANDARD_SAVE"));
		
		self.lastsaveName = newName;
		[self writePlayerToPath:path];
	}
	[self setGuiToStatusScreen];
}

#endif


- (void) writePlayerToPath:(NSString *)path
{
	NSString		*errDesc = nil;
	NSDictionary	*dict = nil;
	BOOL			didSave = NO;
	[[UNIVERSE gameView] resetTypedString];
	
	if (!path)
	{
		OOLog(@"save.failed", @"***** SAVE ERROR: %s called with nil path.", __PRETTY_FUNCTION__);
		return;
	}
	
	dict = [self commanderDataDictionary];
	if (dict == nil)  errDesc = @"could not construct commander data dictionary.";
	else  didSave = [dict writeOOXMLToFile:path atomically:YES errorDescription:&errDesc];
	if (didSave)
	{
		[UNIVERSE clearPreviousMessage];	// allow this to be given time and again
		[UNIVERSE addMessage:DESC(@"game-saved") forCount:2];
		[save_path autorelease];
		save_path = [path copy];
		[[UNIVERSE gameController] setPlayerFileToLoad:save_path];
		[[UNIVERSE gameController] setPlayerFileDirectory:save_path];
		// no duplicated autosave immediately after a save.
		[UNIVERSE setAutoSaveNow:NO];
	}
	else
	{
		OOLog(@"save.failed", @"***** SAVE ERROR: %@", errDesc);
		[NSException raise:@"OoliteException"
					format:@"Attempt to save game to file '%@' failed: %@", path, errDesc];
	}
	[[UNIVERSE gameView] supressKeysUntilKeyUp];
	[self setGuiToStatusScreen];
}


- (void)nativeSavePlayer:(NSString *)cdrName
{
	NSString*	dir = [[UNIVERSE gameController] playerFileDirectory];
	NSString *savePath = [dir stringByAppendingPathComponent:[cdrName stringByAppendingPathExtension:@"oolite-save"]];
	
	ShipScriptEventNoCx(self, "playerWillSaveGame", OOJSSTR("STANDARD_SAVE"));
	
	[self setLastsaveName:cdrName];
	
	[self writePlayerToPath:savePath];
}


#if OO_USE_CUSTOM_LOAD_SAVE

- (void) setGuiToLoadCommanderScreen
{
	GuiDisplayGen *gui=[UNIVERSE gui];
	NSString*	dir = [[UNIVERSE gameController] playerFileDirectory];
	
	gui_screen = GUI_SCREEN_LOAD;
	
	[gui clear];
	[gui setTitle:DESC(@"loadscreen-title")];
	
	currentPage = 0;
	[self lsCommanders:gui directory:dir pageNumber: currentPage highlightName:nil];
	
	[gui setForegroundTextureKey:@"docked_overlay"];
	[gui setBackgroundTextureKey:@"load_save"];
	
	[[UNIVERSE gameView] supressKeysUntilKeyUp];
	
	[self setShowDemoShips:YES];
	[UNIVERSE enterGUIViewModeWithMouseInteraction:YES];
}


- (void) setGuiToSaveCommanderScreen:(NSString *)cdrName
{
	GuiDisplayGen *gui=[UNIVERSE gui];
	MyOpenGLView *gameView = [UNIVERSE gameView];
	NSString *dir = [[UNIVERSE gameController] playerFileDirectory];
	
	pollControls = NO;
	gui_screen = GUI_SCREEN_SAVE;
	
	[gui clear];
	[gui setTitle:DESC(@"savescreen-title")];
	
	currentPage = 0;
	[self lsCommanders:gui directory:dir pageNumber: currentPage highlightName:nil];
	
	[gui setText:DESC(@"savescreen-commander-name") forRow: INPUTROW];
	[gui setColor:[OOColor cyanColor] forRow:INPUTROW];
	[gui setShowTextCursor: YES];
	[gui setCurrentRow: INPUTROW];
	
	[gui setForegroundTextureKey:@"docked_overlay"];
	[gui setBackgroundTextureKey:@"load_save"];
	
	[gameView setTypedString:cdrName];
	[gameView supressKeysUntilKeyUp];
	
	[self setShowDemoShips:YES];
	[UNIVERSE enterGUIViewModeWithMouseInteraction:YES];
}


- (void) setGuiToOverwriteScreen:(NSString *)cdrName
{
	GuiDisplayGen *gui=[UNIVERSE gui];
	MyOpenGLView*	gameView = [UNIVERSE gameView];
	
	// Don't poll controls
	pollControls=NO;
	
	gui_screen = GUI_SCREEN_SAVE_OVERWRITE;
	
	[gui clear];
	[gui setTitle:[NSString stringWithFormat:DESC(@"overwrite-save-commander-@"), cdrName]];
	
	[gui setText:[NSString stringWithFormat:DESC(@"overwritescreen-commander-@-already-exists-overwrite-query"), cdrName]
								forRow:SAVE_OVERWRITE_WARN_ROW align: GUI_ALIGN_CENTER];
	
	[gui setText:DESC(@"overwritescreen-yes") forRow: SAVE_OVERWRITE_YES_ROW align: GUI_ALIGN_CENTER];
	[gui setKey:GUI_KEY_OK forRow: SAVE_OVERWRITE_YES_ROW];
	
	[gui setText:DESC(@"overwritescreen-no") forRow: SAVE_OVERWRITE_NO_ROW align: GUI_ALIGN_CENTER];
	[gui setKey:GUI_KEY_OK forRow: SAVE_OVERWRITE_NO_ROW];
	
	[gui setSelectableRange: NSMakeRange(SAVE_OVERWRITE_YES_ROW, 2)];
	[gui setSelectedRow: SAVE_OVERWRITE_NO_ROW];
	
	// We can only leave this screen by answering yes or no, or esc. Therefore
	// use a specific overlay, to allow visual reminders of the available options.
	[gui setForegroundTextureKey:@"overwrite_overlay"];
	[gui setBackgroundTextureKey:@"load_save"];
	
	[self setShowDemoShips:NO];
	[gameView setStringInput:gvStringInputNo];
	[UNIVERSE enterGUIViewModeWithMouseInteraction:NO];	// FIXME: should be YES, but was NO before introducing new mouse mode stuff. If set to YES, choices can be selected but not activated.
}

NSComparisonResult sortCommanders(id cdr1, id cdr2, void *context)
{
	return [[cdr1 objectForKey:@"saved_game_path"] localizedCompare:[cdr2 objectForKey:@"saved_game_path"]];
}

- (void) lsCommanders: (GuiDisplayGen *)gui
			directory: (NSString*) directory
		   pageNumber: (int)page
		highlightName: (NSString *)highlightName
{
	NSFileManager *cdrFileManager=[NSFileManager defaultManager];
	int rangeStart=STARTROW;
	unsigned lastIndex;
	unsigned i;
	int row=STARTROW;
	
	// cdrArray defined in PlayerEntity.h
	NSArray *cdrArray=[cdrFileManager commanderContentsOfPath: directory];
	
	// get commander details so a brief rundown of the commander's details may
	// be displayed.
	if (!cdrDetailArray)
		cdrDetailArray=[[NSMutableArray alloc] init];	// alloc retains this so the retain further on in the code was unnecessary
	else
		[cdrDetailArray removeAllObjects];
	
	[cdrDetailArray addObject:[NSMutableDictionary dictionaryWithObjectsAndKeys:
		@"YES", @"isParentFolder",
		[directory stringByDeletingLastPathComponent], @"saved_game_path", nil]];
	
	for(i = 0; i < [cdrArray count]; i++)
	{
		NSString*	path = [cdrArray objectAtIndex:i];
		BOOL		exists, isDirectory = NO;
		
		exists = [cdrFileManager fileExistsAtPath:path isDirectory:&isDirectory];
		
		if (exists)
		{
			if (!isDirectory && [[[path pathExtension] lowercaseString] isEqualToString:@"oolite-save"])
			{
				NSDictionary *cdr = OODictionaryFromFile(path);
				if(cdr)
				{
					// okay use the same dictionary but add a 'saved_game_path' attribute
					NSMutableDictionary* cdr1 = [NSMutableDictionary dictionaryWithDictionary:cdr];
					[cdr1 setObject: @"YES" forKey:@"isSavedGame"];
					[cdr1 setObject: path forKey:@"saved_game_path"];
					[cdrDetailArray addObject: cdr1];
				}
			}
			if (isDirectory && ![[path lastPathComponent] hasPrefix:@"."])
			{
				[cdrDetailArray addObject: [NSDictionary dictionaryWithObjectsAndKeys: @"YES", @"isFolder", path, @"saved_game_path", nil]];
			}
		}
	}
	
	if(![cdrDetailArray count])
	{
		// Empty directory; tell the user and exit immediately.
		[gui setText:DESC(@"loadsavescreen-no-commanders-found") forRow:STARTROW align:GUI_ALIGN_CENTER];
		return;
	}

	[cdrDetailArray sortUsingFunction:sortCommanders context:NULL];
	
	// Do we need to highlight a name?
	int highlightRowOnPage=STARTROW;
	int highlightIdx=0;
	if(highlightName)
	{
		highlightIdx=[self findIndexOfCommander: highlightName];
		if(highlightIdx < 0)
		{
			OOLog(@"save.list.commanders.commanderNotFound", @"Commander %@ doesn't exist, very bad", highlightName);
			highlightIdx=0;
		}
		
		// figure out what page we need to be on
		page=highlightIdx/NUMROWS;
		highlightRowOnPage=highlightIdx % NUMROWS + STARTROW;
	}
	
	// We now know for certain what page we're on - 
	// set the first index of the first commander on this page.
	unsigned firstIndex=page * NUMROWS;
	
	// Set up the GUI.
	OOGUITabSettings tabStop;
	tabStop[0]=0;
	tabStop[1]=160;
	tabStop[2]=270;
	[gui setTabStops: tabStop];
	
	// clear text lines here
	for (i = EXITROW ; i < ENDROW + 1; i++)
	{
		[gui setText:@"" forRow:i align:GUI_ALIGN_LEFT];
		[gui setColor: [OOColor yellowColor] forRow: i];
		[gui setKey:GUI_KEY_SKIP forRow:i];
	}

	[gui setColor: [OOColor greenColor] forRow: LABELROW];
	[gui setArray: [NSArray arrayWithObjects: DESC(@"loadsavescreen-commander-name"), DESC(@"loadsavescreen-rating"), nil]
		   forRow:LABELROW];

	if (page)
	{
		[gui setColor:[OOColor greenColor] forRow:STARTROW-1];
		[gui setArray:[NSArray arrayWithObjects:DESC(@"gui-back"), @" <-- ", nil]
			   forRow:STARTROW-1];
		[gui setKey:GUI_KEY_OK forRow:STARTROW-1];
		rangeStart=STARTROW-1;
	}

	if ([self status] == STATUS_START_GAME)
	{
		[gui setArray:[NSArray arrayWithObjects:DESC(@"oolite-loadsave-exit"), @" <----- ", nil] forRow:EXITROW];
		[gui setColor:[OOColor redColor] forRow:EXITROW];
		[gui setKey:GUI_KEY_OK forRow:EXITROW];
		rangeStart = EXITROW;
	}

	
	if (firstIndex + NUMROWS >= [cdrDetailArray count])
	{
		lastIndex=[cdrDetailArray count];
		[gui setSelectableRange: NSMakeRange(rangeStart, rangeStart + NUMROWS)];
	}
	else
	{
		lastIndex=(page * NUMROWS) + NUMROWS;
		[gui setColor:[OOColor greenColor] forRow:ENDROW];
		[gui setArray:[NSArray arrayWithObjects:DESC(@"gui-more"), @" --> ", nil]
			   forRow:ENDROW];
		[gui setKey:GUI_KEY_OK forRow:ENDROW];
		[gui setSelectableRange: NSMakeRange(rangeStart, MOREROW)];
	}
	
	for (i=firstIndex; i < lastIndex; i++)
	{
		NSDictionary *cdr=[cdrDetailArray objectAtIndex: i];
		if ([cdr oo_boolForKey:@"isSavedGame"])
		{
			NSString *ratingDesc = OODisplayRatingStringFromKillCount([cdr oo_unsignedIntForKey:@"ship_kills"]);
			[gui setArray:[NSArray arrayWithObjects:
				[NSString stringWithFormat:@" %@ ",[cdr oo_stringForKey:@"player_save_name" defaultValue:[cdr oo_stringForKey:@"player_name"]]],
				[NSString stringWithFormat:@" %@ ",ratingDesc],
				nil]
				   forRow:row];
			if ([[self lastsaveName] isEqualToString:[cdr oo_stringForKey:@"player_save_name" defaultValue:[cdr oo_stringForKey:@"player_name"]]])
			{
				highlightRowOnPage = row;
			}
			
			[gui setKey:GUI_KEY_OK forRow:row];
			row++;
		}
		if ([cdr oo_boolForKey:@"isParentFolder"])
		{
			[gui setArray:[NSArray arrayWithObjects:
				[NSString stringWithFormat:@" (..) %@ ", [[cdr oo_stringForKey:@"saved_game_path"] lastPathComponent]],
				@"",
				nil]
				   forRow:row];
			[gui setColor: [OOColor orangeColor] forRow: row];
			[gui setKey:GUI_KEY_OK forRow:row];
			row++;
		}
		if ([cdr oo_boolForKey:@"isFolder"])
		{
			[gui setArray:[NSArray arrayWithObjects:
				[NSString stringWithFormat:@" >> %@ ", [[cdr oo_stringForKey:@"saved_game_path"] lastPathComponent]],
				@"",
				nil]
				   forRow:row];
			[gui setColor: [OOColor orangeColor] forRow: row];
			[gui setKey:GUI_KEY_OK forRow:row];
			row++;
		}
	}
	[gui setSelectedRow: highlightRowOnPage];
	highlightIdx = (highlightRowOnPage - STARTROW) + (currentPage * NUMROWS);
	// show the first ship, this will be the selected row
	[self showCommanderShip: highlightIdx];
}


// check for an existing saved game...
- (BOOL) existingNativeSave: (NSString *)cdrName
{
	NSString*	dir = [[UNIVERSE gameController] playerFileDirectory];
	
	NSString *savePath=[dir stringByAppendingPathComponent:[cdrName stringByAppendingPathExtension:@"oolite-save"]];
	return [[NSFileManager defaultManager] fileExistsAtPath:savePath];
}


// Get some brief details about the commander file.
- (void) showCommanderShip:(int)cdrArrayIndex
{
	GuiDisplayGen *gui=[UNIVERSE gui];
	[UNIVERSE removeDemoShips];
	NSDictionary *cdr=[cdrDetailArray objectAtIndex: cdrArrayIndex];
	
	[gui setText:@"" forRow:CDRDESCROW align:GUI_ALIGN_LEFT];
	[gui setText:@"" forRow:CDRDESCROW + 1 align:GUI_ALIGN_LEFT];
	[gui setText:@"" forRow:CDRDESCROW + 2 align:GUI_ALIGN_LEFT];
	
	if ([cdr oo_boolForKey:@"isFolder"])
	{
		NSString *folderDesc=[NSString stringWithFormat: DESC(@"loadsavescreen-hold-@-and-press-return-to-open-folder-@"), @COMMAND_MODIFIER_KEY, [[cdr oo_stringForKey:@"saved_game_path"] lastPathComponent]];
		[gui setColor: [OOColor orangeColor] forRow: CDRDESCROW];
		[gui addLongText: folderDesc startingAtRow: CDRDESCROW align: GUI_ALIGN_LEFT];
		return;
	}
	
	if ([cdr oo_boolForKey:@"isParentFolder"])
	{
		NSString *folderDesc=[NSString stringWithFormat: DESC(@"loadsavescreen-hold-@-and-press-return-to-open-parent-folder-@"), @COMMAND_MODIFIER_KEY, [[cdr oo_stringForKey:@"saved_game_path"] lastPathComponent]];
		[gui setColor: [OOColor orangeColor] forRow: CDRDESCROW];
		[gui addLongText: folderDesc startingAtRow: CDRDESCROW align: GUI_ALIGN_LEFT];
		return;
	}
	[gui setColor: [OOColor yellowColor] forRow: CDRDESCROW];

	if (![cdr oo_boolForKey:@"isSavedGame"])  return;	// don't show things that aren't saved games
	
	if ([self dockedStation] == nil)  [self setDockedAtMainStation];
	
	// Display the commander's ship.
	NSString			*shipDesc = [cdr oo_stringForKey:@"ship_desc"];
	NSString			*shipName = nil;
	NSDictionary		*shipDict = nil;
	NSString			*rating = nil;
	uint16_t			personality = PersonalityForCommanderDict(cdr);
	
	shipDict = [[OOShipRegistry sharedRegistry] shipInfoForKey:shipDesc];
	if(shipDict != nil)
	{
		NSMutableDictionary * dict = [[NSMutableDictionary alloc] initWithCapacity:[shipDict count] + 1];
		[dict setDictionary:shipDict];
		id subEntStatus = [cdr objectForKey:@"subentities_status"];
		// don't add it to the dictionary if there's no subentities_status key
		if (subEntStatus != nil) [dict setObject:subEntStatus forKey:@"subentities_status"];
		[self showShipyardModel:shipDesc shipData:dict personality:personality];
		[dict release];
		shipName = [shipDict oo_stringForKey:@"display_name"];
		if (shipName == nil) shipName = [shipDict oo_stringForKey:KEY_NAME];
	}
	else
	{
		[self showShipyardModel:@"oolite-unknown-ship" shipData:nil personality:personality];
		shipName = [cdr oo_stringForKey:@"ship_name" defaultValue:@"unknown"];
		if ([UNIVERSE strict])
		{
			shipName = [shipName stringByAppendingString:@" - OXPs disabled"];
		}
		else
		{
			shipName = [shipName stringByAppendingString:@" - OXP not installed"];
		}
	}
	
	// Make a short description of the commander
	NSString *legalDesc = OODisplayStringFromLegalStatus([cdr oo_intForKey:@"legal_status"]);
	
	rating = KillCountToRatingAndKillString([cdr oo_unsignedIntForKey:@"ship_kills"]);
	OOCreditsQuantity money = OODeciCreditsFromObject([cdr objectForKey:@"credits"]);
	
	// Nikos - Add some more information in the load game screen (current location, galaxy number and timestamp).
	//-------------------------------------------------------------------------------------------------------------------------
	
	// Store the current galaxy seed because findSystemNumberAtCoords may alter it in a while.
	PlayerEntity		*player = PLAYER;
	Random_Seed		player_galaxy_seed = [player galaxy_seed];	
	
	int			galNumber;
	NSString		*timeStamp  = nil;
	NSString 		*locationName = [cdr oo_stringForKey:@"current_system_name"];
	
	// If there is no key containing the name of the current system in the savefile, fall back to
	// extracting the name from the galaxy seed and coordinates information.
	if (locationName == nil)
	{	
		Random_Seed		gal_seed;
		NSPoint			gal_coords;
		int			locationNumber;
		
		gal_coords = PointFromString([cdr oo_stringForKey:@"galaxy_coordinates"]);
		gal_seed = RandomSeedFromString([cdr oo_stringForKey:@"galaxy_seed"]);
		locationNumber = [UNIVERSE findSystemNumberAtCoords:gal_coords withGalaxySeed:gal_seed];
		locationName = [UNIVERSE systemNameIndex:locationNumber];
	}
	
	galNumber = [cdr oo_intForKey:@"galaxy_number"] + 1;	// Galaxy numbering starts at 0.
	
	timeStamp = ClockToString([cdr oo_doubleForKey:@"ship_clock" defaultValue:PLAYER_SHIP_CLOCK_START], NO);
	
	//-------------------------------------------------------------------------------------------------------------------------
	
	NSString		*cdrDesc = nil;
	
	cdrDesc = [NSString stringWithFormat:DESC(@"loadsavescreen-commander-@-rated-@-has-@-legal-status-@-ship-@-location-@-g-@-timestamp-@"),
		[cdr oo_stringForKey:@"player_name"],
		rating,
		OOCredits(money),
		legalDesc,
		shipName,
		locationName,
		galNumber,
		timeStamp];
	
	[gui addLongText:cdrDesc startingAtRow:CDRDESCROW align:GUI_ALIGN_LEFT];
	
	// Restore the seed of the galaxy the player is currently in.
	[UNIVERSE setGalaxySeed: player_galaxy_seed];
}


- (int) findIndexOfCommander: (NSString *)cdrName
{
	unsigned i;
	for (i=0; i < [cdrDetailArray count]; i++)
	{
		NSString *currentName = [[cdrDetailArray oo_dictionaryAtIndex: i] oo_stringForKey:@"player_save_name" defaultValue:[[cdrDetailArray oo_dictionaryAtIndex: i] oo_stringForKey:@"player_name"]];
		if([cdrName compare: currentName] == NSOrderedSame)
		{
			return i;
		}
	}
	
	// not found!
	return -1;
}

#endif

@end


#if OO_USE_CUSTOM_LOAD_SAVE

@implementation MyOpenGLView (OOLoadSaveExtensions)

- (BOOL)isCommandModifierKeyDown
{
	return [self isCtrlDown];
}

@end

#endif


static uint16_t PersonalityForCommanderDict(NSDictionary *dict)
{
	uint16_t personality = [dict oo_unsignedShortForKey:@"entity_personality" defaultValue:ENTITY_PERSONALITY_INVALID];
	
	if (personality == ENTITY_PERSONALITY_INVALID)
	{
		// For pre-1.74 saved games, generate a default personality based on some hashes.
		personality = [[dict oo_stringForKey:@"ship_desc"] oo_hash] * [[dict oo_stringForKey:@"player_name"] oo_hash];
	}
	
	return personality & ENTITY_PERSONALITY_MAX;
}


OOCreditsQuantity OODeciCreditsFromDouble(double doubleDeciCredits)
{
	/*	Clamp value to 0..kOOMaxCredits.
		The important bit here is that kOOMaxCredits can't be represented
		exactly as a double, and casting it rounds it up; casting this value
		back to an OOCreditsQuantity truncates it. Comparing value directly to
		kOOMaxCredits promotes kOOMaxCredits to a double, giving us this
		problem.
		nextafter(kOOMaxCredits, -1) gives us the highest non-truncated
		credits value that's representable as a double (namely,
		18 446 744 073 709 549 568 decicredits, or 2047 less than kOOMaxCredits).
		-- Ahruman 2011-02-27
	*/
	if (doubleDeciCredits > 0)
	{
		doubleDeciCredits = round(doubleDeciCredits);
		double threshold = nextafter(kOOMaxCredits, -1);
		
		if (doubleDeciCredits <= threshold)
		{
			return doubleDeciCredits;
		}
		else
		{
			return kOOMaxCredits;
		}
	}
	else
	{
		return 0;
	}
}


OOCreditsQuantity OODeciCreditsFromObject(id object)
{
	if ([object isKindOfClass:[NSNumber class]] && [object oo_isFloatingPointNumber])
	{
		return OODeciCreditsFromDouble([object doubleValue]);
	}
	else
	{
		return OOUnsignedLongLongFromObject(object, 0);
	}
}
