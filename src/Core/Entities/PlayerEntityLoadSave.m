/*
 
 PlayerEntityLoadSave.m
 
 Oolite
 Copyright (C) 2004-2008 Giles C Williams and contributors
 
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
#import "PlayerEntityControls.h"
#import "OOXMLExtensions.h"
#import "OOSound.h"
#import "OOColor.h"
#import "OOStringParsing.h"
#import "OOPListParsing.h"
#import "StationEntity.h"
#import "OOCollectionExtractors.h"
#import "OOConstToString.h"

#define kOOLogUnconvertedNSLog @"unclassified.PlayerEntityLoadSave"


// Set to 1 to use custom load/save dialogs in windowed mode on Macs in debug builds. No effect on other platforms.
#define USE_CUSTOM_LOAD_SAVE_ON_MAC_DEBUG		0

#if USE_CUSTOM_LOAD_SAVE_ON_MAC_DEBUG && OO_DEBUG && defined(OOLITE_USE_APPKIT_LOAD_SAVE)
#undef OOLITE_USE_APPKIT_LOAD_SAVE
#endif


// Name of modifier key used to issue commands. See also -isCommandModifierKeyDown.
#if OOLITE_MAC_OS_X
#define COMMAND_MODIFIER_KEY		"command"
#else
#define COMMAND_MODIFIER_KEY		"Ctrl"
#endif


@interface MyOpenGLView (OOLoadSaveExtensions)

- (BOOL)isCommandModifierKeyDown;

@end


@interface PlayerEntity (OOLoadSavePrivate)

#if OOLITE_USE_APPKIT_LOAD_SAVE

- (BOOL) loadPlayerWithPanel;
- (void) savePlayerWithPanel;

#endif

- (void) setGuiToLoadCommanderScreen;
- (void) setGuiToSaveCommanderScreen: (NSString *)cdrName;
- (void) setGuiToOverwriteScreen: (NSString *)cdrName;
- (void) lsCommanders: (GuiDisplayGen *)gui directory: (NSString*)directory pageNumber: (int)page highlightName: (NSString *)highlightName;
- (void) writePlayerToPath:(NSString *)path;
- (void) nativeSavePlayer: (NSString *)cdrName;
- (BOOL) existingNativeSave: (NSString *)cdrName;
- (void) showCommanderShip: (int)cdrArrayIndex;
- (int) findIndexOfCommander: (NSString *)cdrName;

@end


@implementation PlayerEntity (LoadSave)

- (BOOL)loadPlayer
{
	BOOL				OK = YES;
	
#if OOLITE_USE_APPKIT_LOAD_SAVE
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
#if OOLITE_USE_APPKIT_LOAD_SAVE
	// OS X: use system open/save dialogs in windowed mode, custom interface in full-screen.
	if ([[UNIVERSE gameController] inFullScreenMode])
	{
		[self setGuiToSaveCommanderScreen:player_name];
	}
	else
	{
		[self savePlayerWithPanel];
	}
#else
	// Other platforms: use custom interface all the time.
	[self setGuiToSaveCommanderScreen:player_name];
#endif
}

- (void) autosavePlayer
{
	NSString		*tmp_path = nil;
	NSString		*tmp_name = nil;
	NSString		*dir = [[UNIVERSE gameController] playerFileDirectory];
	if (!dir)  dir = [[NSFileManager defaultManager] defaultCommanderPath];
	
	tmp_name = [player_name copy];
	if (save_path) tmp_path = [save_path copy];
	
	NSString *saveName = DESC(@"autosave-commander-name");
	NSString *savePath = [dir stringByAppendingPathComponent:[saveName stringByAppendingString:@".oolite-save"]];
	
	[player_name autorelease];
	player_name = [saveName copy];

	[self writePlayerToPath:savePath];
	
	if(tmp_path)
	{
		[save_path autorelease];
		save_path = [[tmp_path copy] retain];
	}
	[player_name autorelease];
	player_name = [[tmp_name copy] retain];
}


- (void) quicksavePlayer
{
	NSString		*path = nil;
	
	path = save_path;
	if (!path)  path = [[[UNIVERSE gameView] gameController] playerFileToLoad];
	if (!path)
	{
		OOLog(@"quickSave.failed.noName", @"ERROR no file name returned by [[[UNIVERSE gameView] gameController] playerFileToLoad]");
		[NSException raise:@"OoliteGameNotSavedException"
					format:@"ERROR no file name returned by [[UNIVERSE gameView] gameController] playerFileToLoad]"];
	}
	
	[self writePlayerToPath:path];
	
	[self setGuiToStatusScreen];
}


- (NSString *)commanderSelector
{
	MyOpenGLView	*gameView = [UNIVERSE gameView];
	GuiDisplayGen	*gui = [UNIVERSE gui];
	NSString		*dir = [[UNIVERSE gameController] playerFileDirectory];
	if (!dir)  dir = [[NSFileManager defaultManager] defaultCommanderPath];
	
	int idx;
	if([self handleGUIUpDownArrowKeys])
	{
		int guiSelectedRow=[gui selectedRow];
		idx=(guiSelectedRow - STARTROW) + (currentPage * NUMROWS);
		if (guiSelectedRow != MOREROW && guiSelectedRow != BACKROW)
		{
			[self showCommanderShip: idx];
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
		[self lsCommanders: gui	directory: dir	pageNumber: currentPage  highlightName: nil];
		[gameView supressKeysUntilKeyUp];
	}
	//
	if ([gameView isDown:gvArrowKeyRight] && [[gui keyForRow:MOREROW] isEqual: GUI_KEY_OK])
	{
		currentPage++;
		[self lsCommanders: gui	directory: dir	pageNumber: currentPage  highlightName: nil];
		[gameView supressKeysUntilKeyUp];
	}
	
	// Enter pressed - find the commander name underneath.
	if ([gameView isDown:13]||[gameView isDown:gvMouseDoubleClick])
	{
		NSDictionary *cdr;
		switch ([gui selectedRow])
		{
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
				if ([cdr boolForKey:@"isSavedGame"])
					return [cdr stringForKey:@"saved_game_path"];
				else
				{
					if ([gameView isCommandModifierKeyDown]||[gameView isDown:gvMouseDoubleClick])
					{
						// change directory to the selected path
						NSString* newDir = [cdr stringForKey:@"saved_game_path"];
						[[UNIVERSE gameController] setPlayerFileDirectory: newDir];
						dir = newDir;
						currentPage = 0;
						[self lsCommanders: gui	directory: dir	pageNumber: currentPage  highlightName: nil];
						[gameView supressKeysUntilKeyUp];
					}
				}
		}
	}
	
	if([gameView isDown: 27])
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
	if (!dir)  dir = [[NSFileManager defaultManager] defaultCommanderPath];
	
	if ([self handleGUIUpDownArrowKeys])
	{
		int guiSelectedRow=[gui selectedRow];
		int	idx = (guiSelectedRow - STARTROW) + (currentPage * NUMROWS);
		if (guiSelectedRow != MOREROW && guiSelectedRow != BACKROW)
		{
			[self showCommanderShip: idx];
		}
		if ([(NSDictionary *)[cdrDetailArray objectAtIndex:idx] boolForKey:@"isSavedGame"])	// don't show things that aren't saved games
			commanderNameString = [[cdrDetailArray dictionaryAtIndex:idx] stringForKey:@"player_name"];
		else
			commanderNameString = [gameView typedString];
	}
	else
		commanderNameString = [gameView typedString];
	[gameView setTypedString: commanderNameString];
	
	[gui setText:
		[NSString stringWithFormat:DESC(@"savescreen-commander-name-@"), commanderNameString]
		  forRow: INPUTROW];
	[gui setColor:[OOColor cyanColor] forRow:INPUTROW];
	
	// handle page <-- and page --> keys
	if ([gameView isDown:gvArrowKeyLeft] && [[gui keyForRow:BACKROW] isEqual: GUI_KEY_OK])
	{
		currentPage--;
		[self lsCommanders: gui	directory: dir	pageNumber: currentPage  highlightName: nil];
		[gameView supressKeysUntilKeyUp];
	}
	//
	if ([gameView isDown:gvArrowKeyRight] && [[gui keyForRow:MOREROW] isEqual: GUI_KEY_OK])
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
			if (![cdr boolForKey:@"isSavedGame"])	// don't open saved games
			{
				// change directory to the selected path
				NSString* newDir = [cdr stringForKey:@"saved_game_path"];
				[[UNIVERSE gameController] setPlayerFileDirectory: newDir];
				dir = newDir;
				currentPage = 0;
				[self lsCommanders: gui	directory: dir	pageNumber: currentPage  highlightName: nil];
				[gameView supressKeysUntilKeyUp];
			}
		}
		else
		{
			pollControls=YES;
			if ([self existingNativeSave: commanderNameString])
			{
				[gameView supressKeysUntilKeyUp];
				[self setGuiToOverwriteScreen: commanderNameString];
			}
			else
			{
				[self nativeSavePlayer: commanderNameString];
				[self setGuiToStatusScreen];
			}
		}
		
	}
	
	if([gameView isDown: 27])
	{
		// esc was pressed - get out of here
		pollControls=YES;
		[self setGuiToStatusScreen];
	}
}


- (void) overwriteCommanderInputHandler
{
	MyOpenGLView	*gameView = [UNIVERSE gameView];
	GuiDisplayGen	*gui = [UNIVERSE gui];
	
	[self handleGUIUpDownArrowKeys];
	
	if (([gameView isDown: 13] && ([gui selectedRow] == SAVE_OVERWRITE_YES_ROW))||[gameView isDown: 121]||[gameView isDown: 89])
	{
		pollControls=YES;
		[self nativeSavePlayer: commanderNameString];
		[self setGuiToStatusScreen];
		
		[self playSaveOverwriteYes];
	}
	
	if (([gameView isDown: 13] && ([gui selectedRow] == SAVE_OVERWRITE_NO_ROW))||[gameView isDown: 27]||[gameView isDown: 110]||[gameView isDown: 78])
	{
		// esc or NO was pressed - get out of here
		// FIXME: should return to save screen instead.
		pollControls=YES;
		[self setGuiToStatusScreen];
		
		[self playSaveOverwriteNo];
	}
}


- (BOOL) loadPlayerFromFile:(NSString *)fileToOpen
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
		fail_reason = @"No file specified!";
		loadedOK = NO;
	}
	
	if (loadedOK)
	{
		fileDic = OODictionaryFromFile(fileToOpen);
		if (fileDic == nil)
		{
			fail_reason = @"Could not load file.";
			loadedOK = NO;
		}
	}
	
	if (loadedOK)
	{
		// Check that player ship exists
		NSString		*shipKey = nil;
		NSDictionary	*shipDict = nil;
		
		shipKey = [fileDic stringForKey:@"ship_desc"];
		shipDict = [UNIVERSE getDictionaryForShip:shipKey];
		
		if (![shipDict isKindOfClass:[NSDictionary class]])
		{
			loadedOK = NO;
			if (shipKey != nil)  fail_reason = [NSString stringWithFormat:@"Couldn't find ship type \"%@\" - please reinstall the appropriate OXP.", shipKey];
			else  fail_reason = @"Invalid saved game - no ship specified.";
		}
	}
	
	if (loadedOK)
	{
		[self set_up:NO]; //don't run reset yet
		if ([self setCommanderDataFromDictionary:fileDic])
		{
			[self doScriptEvent:@"reset"]; //after the mission variables are loaded from the save game
		}
		else
		{
			fail_reason = @"Could not set up player ship.";
			loadedOK = NO;
		}
	}
	
	if (loadedOK)
	{
		if (save_path)  [save_path autorelease];
		save_path = [fileToOpen retain];
		
		[[[UNIVERSE gameView] gameController] setPlayerFileToLoad:fileToOpen];
		[[[UNIVERSE gameView] gameController] setPlayerFileDirectory:fileToOpen];
	}
	else
	{
		OOLog(@"load.failed", @"***** FILE LOADING ERROR!! *****");
		[[UNIVERSE gameController] setPlayerFileToLoad:nil];
		[UNIVERSE game_over];
		[UNIVERSE clearPreviousMessage];
		[UNIVERSE addMessage:@"Saved game failed to load." forCount: 9.0];
		if (fail_reason != nil)  [UNIVERSE addMessage: fail_reason forCount: 9.0];
		return NO;
	}
	
	[UNIVERSE setSystemTo:system_seed];
	[UNIVERSE removeAllEntitiesExceptPlayer:NO];
	[UNIVERSE setUpSpace];
	[UNIVERSE setAutoSaveNow:NO];
	
	status = STATUS_DOCKED;
	[UNIVERSE setViewDirection:VIEW_GUI_DISPLAY];
	
	dockedStation = [UNIVERSE station];
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
	
	if (![dockedStation localMarket])
	{
		NSArray *market = [fileDic arrayForKey:@"localMarket"];
		if (market != nil)  [dockedStation setLocalMarket:market];
		else  [dockedStation initialiseLocalMarketWithSeed:system_seed andRandomFactor:market_rnd];
	}
	[self calculateCurrentCargo];
	[self setGuiToStatusScreen];
	return loadedOK;
}

@end


@implementation PlayerEntity (OOLoadSavePrivate)

#if OOLITE_USE_APPKIT_LOAD_SAVE

- (BOOL)loadPlayerWithPanel
{
	int				result;
	NSArray			*fileTypes = nil;
	NSOpenPanel		*oPanel = nil;
	
	fileTypes = [NSArray arrayWithObject:@"oolite-save"];
	oPanel = [NSOpenPanel openPanel];
	
	[oPanel setAllowsMultipleSelection:NO];
	result = [oPanel runModalForDirectory:nil file:nil types:fileTypes];
	if (result == NSOKButton)
	{
		return [self loadPlayerFromFile:[oPanel filename]];
	}
	else
	{
		return NO;
	}
}


- (void) savePlayerWithPanel
{
	NSSavePanel		*sp;
	int				runResult;
	
	sp = [NSSavePanel savePanel];
	[sp setRequiredFileType:@"oolite-save"];
	[sp setCanSelectHiddenExtension:YES];
	
	// display the NSSavePanel
	runResult = [sp runModalForDirectory:nil file:player_name];
	
	// if successful, save file under designated name
	// TODO: break actual writing into a separate method to avoid redundancy. -- Ahruman
	if (runResult == NSOKButton)
	{
		NSArray*	path_components = [[sp filename] pathComponents];
		NSString*   new_name = [[path_components objectAtIndex:[path_components count]-1] stringByDeletingPathExtension];
		
		[player_name release];
		player_name = [new_name copy];
		
		[self writePlayerToPath:[sp filename]];
	}
	[self setGuiToStatusScreen];
}

#endif


- (void) writePlayerToPath:(NSString *)path
{
	NSString		*errDesc = nil;
	NSDictionary	*dict = nil;
	BOOL			didSave = NO;
	
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
		[UNIVERSE addMessage:ExpandDescriptionForCurrentSystem(@"[game-saved]") forCount:2];
		[save_path autorelease];
		save_path = [path copy];
		[[UNIVERSE gameController] setPlayerFileToLoad:save_path];
		[[UNIVERSE gameController] setPlayerFileDirectory:save_path];
	}
	else
	{
		OOLog(@"save.failed", @"***** SAVE ERROR: %@", errDesc);
		[NSException raise:@"OoliteException"
					format:@"Attempt to save game to file '%@' failed: %@", errDesc];
	}
	
	[self setGuiToStatusScreen];
}


- (void)nativeSavePlayer:(NSString *)cdrName
{
	NSString*	dir = [[UNIVERSE gameController] playerFileDirectory];
	if (!dir)	dir = [[NSFileManager defaultManager] defaultCommanderPath];
	
	NSString *savePath = [dir stringByAppendingPathComponent:[cdrName stringByAppendingPathExtension:@"oolite-save"]];
	
	[player_name release];
	player_name = [cdrName copy];
	
	[self writePlayerToPath:savePath];
}



- (void) setGuiToLoadCommanderScreen
{
	GuiDisplayGen *gui=[UNIVERSE gui];
	NSString*	dir = [[UNIVERSE gameController] playerFileDirectory];
	if (!dir)	dir = [[NSFileManager defaultManager] defaultCommanderPath];
	
	
	gui_screen = GUI_SCREEN_LOAD;
	
	[gui clear];
	[gui setTitle:DESC(@"loadscreen-title")];
	
	currentPage = 0;
	[self lsCommanders:gui	directory:dir	pageNumber: currentPage	highlightName:nil];
	
	[(MyOpenGLView *)[UNIVERSE gameView] supressKeysUntilKeyUp];
	
	[self setShowDemoShips: YES];
	[UNIVERSE setDisplayText: YES];
	[UNIVERSE setDisplayCursor: YES];
	[UNIVERSE setViewDirection: VIEW_GUI_DISPLAY];
}


- (void) setGuiToSaveCommanderScreen: (NSString *)cdrName
{
	GuiDisplayGen *gui=[UNIVERSE gui];
	MyOpenGLView*	gameView = (MyOpenGLView*)[UNIVERSE gameView];
	NSString*	dir = [[UNIVERSE gameController] playerFileDirectory];
	if (!dir)	dir = [[NSFileManager defaultManager] defaultCommanderPath];
	
	
	// Don't poll controls
	pollControls=NO;
	
	gui_screen = GUI_SCREEN_SAVE;
	
	[gui clear];
	[gui setTitle:[NSString stringWithFormat:DESC(@"savescreen-title")]];
	
	currentPage = 0;
	[self lsCommanders:gui	directory:dir	pageNumber: currentPage	highlightName:nil];
	
	[gui setText:DESC(@"savescreen-commander-name") forRow: INPUTROW];
	[gui setColor:[OOColor cyanColor] forRow:INPUTROW];
	[gui setShowTextCursor: YES];
	[gui setCurrentRow: INPUTROW];
	
	[gameView setTypedString: cdrName];
	[gameView supressKeysUntilKeyUp];
	
	[self setShowDemoShips: YES];
	[UNIVERSE setDisplayText: YES];
	[UNIVERSE setDisplayCursor: YES];
	[UNIVERSE setViewDirection: VIEW_GUI_DISPLAY];
}


- (void) setGuiToOverwriteScreen: (NSString *)cdrName
{
	GuiDisplayGen *gui=[UNIVERSE gui];
	MyOpenGLView*	gameView = (MyOpenGLView*)[UNIVERSE gameView];
	
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
	
	[self setShowDemoShips: NO];
	[UNIVERSE setDisplayText: YES];
	[UNIVERSE setDisplayCursor: NO];
	[gameView setStringInput: gvStringInputNo];
	[UNIVERSE setViewDirection: VIEW_GUI_DISPLAY];
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
	[gui setColor: [OOColor greenColor] forRow: LABELROW];
	[gui setArray: [NSArray arrayWithObjects: DESC(@"loadsavescreen-commander-name"), DESC(@"loadsavescreen-rating"), nil]
		   forRow:LABELROW];
	
	// clear text lines here
	for (i = STARTROW - 1; i < ENDROW + 1; i++)
	{
		[gui setText:@"" forRow:i align:GUI_ALIGN_LEFT];
		[gui setColor: [OOColor yellowColor] forRow: i];
		[gui setKey:GUI_KEY_SKIP forRow:i];
	}
	
	if (page)
	{
		[gui setArray:[NSArray arrayWithObjects:DESC(@"gui-back"), @" <-- ", nil]
			   forRow:STARTROW-1];
		[gui setKey:GUI_KEY_OK forRow:STARTROW-1];
		rangeStart=STARTROW-1;
		if(!highlightIdx)
			highlightIdx=firstIndex;
	}
	
	if (firstIndex + NUMROWS >= [cdrDetailArray count])
	{
		lastIndex=[cdrDetailArray count];
		[gui setSelectableRange: NSMakeRange(rangeStart, lastIndex)];
	}
	else
	{
		lastIndex=(page * NUMROWS) + NUMROWS;
		[gui setArray:[NSArray arrayWithObjects:DESC(@"gui-more"), @" --> ", nil]
			   forRow:ENDROW];
		[gui setKey:GUI_KEY_OK forRow:ENDROW];
		[gui setSelectableRange: NSMakeRange(rangeStart, NUMROWS+1)];
	}
	
	for (i=firstIndex; i < lastIndex; i++)
	{
		NSDictionary *cdr=[cdrDetailArray objectAtIndex: i];
		if ([cdr boolForKey:@"isSavedGame"])
		{
			NSString *ratingDesc = KillCountToRatingString([cdr unsignedIntForKey:@"ship_kills"]);
			[gui setArray:[NSArray arrayWithObjects:
				[NSString stringWithFormat:@" %@ ",[cdr stringForKey:@"player_name"]],
				[NSString stringWithFormat:@" %@ ",ratingDesc],
				nil]
				   forRow:row];
			if ([player_name isEqualToString:[cdr stringForKey:@"player_name"]])
				highlightRowOnPage = row;
			
			[gui setKey:GUI_KEY_OK forRow:row];
			row++;
		}
		if ([cdr boolForKey:@"isParentFolder"])
		{
			[gui setArray:[NSArray arrayWithObjects:
				[NSString stringWithFormat:@" (..) %@ ", [[cdr stringForKey:@"saved_game_path"] lastPathComponent]],
				@"",
				nil]
				   forRow:row];
			[gui setColor: [OOColor orangeColor] forRow: row];
			[gui setKey:GUI_KEY_OK forRow:row];
			row++;
		}
		if ([cdr boolForKey:@"isFolder"])
		{
			[gui setArray:[NSArray arrayWithObjects:
				[NSString stringWithFormat:@" >> %@ ", [[cdr stringForKey:@"saved_game_path"] lastPathComponent]],
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
	if (!dir)	dir = [[NSFileManager defaultManager] defaultCommanderPath];
	
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
	
	if ([cdr boolForKey:@"isFolder"])
	{
		NSString *folderDesc=[NSString stringWithFormat: DESC(@"loadsavescreen-hold-@-and-press-return-to-open-folder-@"), @COMMAND_MODIFIER_KEY, [[cdr stringForKey:@"saved_game_path"] lastPathComponent]];
		
		[gui addLongText: folderDesc startingAtRow: CDRDESCROW align: GUI_ALIGN_LEFT];             
		
		return;
	}
	
	if ([cdr boolForKey:@"isParentFolder"])
	{
		NSString *folderDesc=[NSString stringWithFormat: DESC(@"loadsavescreen-hold-@-and-press-return-to-open-parent-folder-@"), @COMMAND_MODIFIER_KEY, [[cdr stringForKey:@"saved_game_path"] lastPathComponent]];
		
		[gui addLongText: folderDesc startingAtRow: CDRDESCROW align: GUI_ALIGN_LEFT];             
		
		return;
	}
	
	if (![cdr boolForKey:@"isSavedGame"])	// don't show things that aren't saved games
		return;
	
	if(!dockedStation)  dockedStation = [UNIVERSE station];
	
	// Display the commander's ship.
	NSString			*shipDesc = [cdr stringForKey:@"ship_desc"];
	NSString			*shipName = nil;
	NSDictionary		*shipDict = nil;
	NSString			*rating = nil;
	
	shipDict = [UNIVERSE getDictionaryForShip:shipDesc];
	if(shipDict != nil)
	{
		[self showShipyardModel:shipDict];
		shipName = [shipDict stringForKey:@"display_name"];
		if (shipName == nil) shipName = [shipDict stringForKey:KEY_NAME];
	}
	else
	{
		[self showShipyardModel:[UNIVERSE getDictionaryForShip:@"oolite-unknown-ship"]];
		shipName = [cdr stringForKey:@"ship_name" defaultValue:@"unknown"];
		shipName = [shipName stringByAppendingString:@" - OXP not installed"];
	}
	
	// Make a short description of the commander
	NSString			*legalDesc = nil;
	OOCreditsQuantity	money;
	
	legalDesc = LegalStatusToString([cdr intForKey:@"legal_status"]);
	
	rating = KillCountToRatingAndKillString([cdr unsignedIntForKey:@"ship_kills"]);
	money = [cdr unsignedLongLongForKey:@"credits"] / 10;
	
	// Nikos - Add some more information in the load game screen (current location, galaxy number and timestamp).
	//-------------------------------------------------------------------------------------------------------------------------
	
	// Store the current galaxy seed because findSystemNumberAtCoords may alter it in a while.
	PlayerEntity		*player = [PlayerEntity sharedPlayer];
	Random_Seed		player_galaxy_seed = [player galaxy_seed];	
	
	int			galNumber;
	NSString		*timeStamp  = nil;
	NSString 		*locationName = [cdr stringForKey:@"current_system_name"];
	
	// If there is no key containing the name of the current system in the savefile, fall back to
	// extracting the name from the galaxy seed and coordinates information.
	if (locationName == nil)
	{	
		Random_Seed		gal_seed;
		NSPoint			gal_coords;
		int			locationNumber;
		
		gal_coords = PointFromString([cdr stringForKey:@"galaxy_coordinates"]);
		gal_seed = RandomSeedFromString([cdr stringForKey:@"galaxy_seed"]);
		locationNumber = [UNIVERSE findSystemNumberAtCoords:gal_coords withGalaxySeed:gal_seed];
		locationName = [UNIVERSE systemNameIndex:locationNumber];
	}
	
	galNumber = [cdr intForKey:@"galaxy_number"] + 1;	// Galaxy numbering starts at 0.
	
	timeStamp = ClockToString([cdr doubleForKey:@"ship_clock" defaultValue:PLAYER_SHIP_CLOCK_START], NO);
	
	//-------------------------------------------------------------------------------------------------------------------------
	
	NSString		*cdrDesc = nil;
	
	cdrDesc = [NSString stringWithFormat:DESC(@"loadsavescreen-commander-@-rated-@-has-llu-Cr-legal-status-@-ship-@-location-@-g-@-timestamp-@"),
		[cdr stringForKey:@"player_name"],
		rating,
		money,
		legalDesc,
		shipName,
		locationName,
		galNumber,
		timeStamp];
	
	[gui addLongText:cdrDesc startingAtRow:CDRDESCROW align:GUI_ALIGN_LEFT];
	
	// Restore the seed of the galaxy the player is currently in.
	[UNIVERSE setGalaxy_seed: player_galaxy_seed];
}


- (int) findIndexOfCommander: (NSString *)cdrName
{
	unsigned i;
	for (i=0; i < [cdrDetailArray count]; i++)
	{
		NSString *currentName = [[cdrDetailArray dictionaryAtIndex: i] stringForKey:@"player_name"];
		if([cdrName compare: currentName] == NSOrderedSame)
		{
			return i;
		}
	}
	
	// not found!
	return -1;
}

@end


@implementation MyOpenGLView (OOLoadSaveExtensions)

- (BOOL)isCommandModifierKeyDown
{
#if OOLITE_MAC_OS_X
	return [self isCommandDown];
#else
	return [self isCtrlDown];
#endif
}

@end
