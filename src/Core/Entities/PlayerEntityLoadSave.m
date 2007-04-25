/*

PlayerEntityLoadSave.m

Oolite
Copyright (C) 2004-2007 Giles C Williams and contributors

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

#import "NSFileManagerOOExtensions.h"
#import "GameController.h"
#import "PlayerEntityControls.h"
#import "OOXMLExtensions.h"
#import "OOSound.h"
#import "OOColor.h"
#import "OOStringParsing.h"
#import "OOPListParsing.h"
#import "StationEntity.h"

#ifdef WIN32
#import "ResourceManager.h"
#endif

#define kOOLogUnconvertedNSLog @"unclassified.PlayerEntityLoadSave"


@interface PlayerEntity (OOLoadSavePrivate)

#if OOLITE_USE_APPKIT_LOAD_SAVE

- (void) loadPlayerWithPanel;
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

- (void)loadPlayer
{
#if OOLITE_USE_APPKIT_LOAD_SAVE
	// OS X: use system open/save dialogs in windowed mode, custom interface in full-screen.
    if ([[UNIVERSE gameController] inFullScreenMode])
	{
		[self setGuiToLoadCommanderScreen];
	}
	else
	{
		[self loadPlayerWithPanel];
	}
#else
	// Other platforms: use custom interface all the time.
	[self setGuiToLoadCommanderScreen];
#endif
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


- (void) quicksavePlayer
{
	NSString		*path = nil;
	
	path = save_path;
	if (!path)  path = [[[UNIVERSE gameView] gameController] playerFileToLoad];
	if (!path)
	{
		NSLog(@"ERROR no file name returned by [[[UNIVERSE gameView] gameController] playerFileToLoad]");
		[NSException raise:@"OoliteGameNotSavedException"
					format:@"ERROR no file name returned by [[UNIVERSE gameView] gameController] playerFileToLoad]"];
	}
	
	[self writePlayerToPath:path];
	
	[self setGuiToStatusScreen];
}


- (NSString *)commanderSelector:(GuiDisplayGen *)gui :(MyOpenGLView *)gameView
{
	NSString*	dir = [[UNIVERSE gameController] playerFileDirectory];
	if (!dir)	dir = [[NSFileManager defaultManager] defaultCommanderPath];

   int idx;
   if([self handleGUIUpDownArrowKeys: gui :gameView])
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
				if ([cdr objectForKey:@"isSavedGame"])
					return [cdr objectForKey:@"saved_game_path"];
				else
				{
#ifdef GNUSTEP              
					if ([gameView isCtrlDown]||[gameView isDown:gvMouseDoubleClick])
#else                 
					if ([gameView isCommandDown]||[gameView isDown:gvMouseDoubleClick])
#endif                 
					{
						// change directory to the selected path
						NSString* newDir = (NSString*)[cdr objectForKey:@"saved_game_path"];
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

- (void) saveCommanderInputHandler:(GuiDisplayGen *)gui :(MyOpenGLView *)gameView
{
	NSString*	dir = [[UNIVERSE gameController] playerFileDirectory];
	if (!dir)	dir = [[NSFileManager defaultManager] defaultCommanderPath];
	
	if ([self handleGUIUpDownArrowKeys: gui :gameView])
	{
		int guiSelectedRow=[gui selectedRow];
		int	idx = (guiSelectedRow - STARTROW) + (currentPage * NUMROWS);
		if (guiSelectedRow != MOREROW && guiSelectedRow != BACKROW)
		{
			[self showCommanderShip: idx];
		}
		if ([(NSDictionary *)[cdrDetailArray objectAtIndex:idx] objectForKey:@"isSavedGame"])	// don't show things that aren't saved games
			commanderNameString = [(NSDictionary *)[cdrDetailArray objectAtIndex:idx] objectForKey:@"player_name"];
		else
			commanderNameString = [gameView typedString];
	}
	else
		commanderNameString = [gameView typedString];
	[gameView setTypedString: commanderNameString];
	
	[gui setText:
		[NSString stringWithFormat:@"Commander name: %@", commanderNameString]
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
#ifdef GNUSTEP // Linux/Win32
      if ([gameView isCtrlDown]||[gameView isDown:gvMouseDoubleClick])
#else          // OS X
		if ([gameView isCommandDown]||[gameView isDown:gvMouseDoubleClick])
#endif        
		{
			int guiSelectedRow=[gui selectedRow];
			int	idx = (guiSelectedRow - STARTROW) + (currentPage * NUMROWS);
			NSDictionary* cdr = [cdrDetailArray objectAtIndex:idx];
			if (![cdr objectForKey:@"isSavedGame"])	// don't open saved games
			{
				// change directory to the selected path
				NSString* newDir = (NSString*)[cdr objectForKey:@"saved_game_path"];
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

- (void) overwriteCommanderInputHandler:(GuiDisplayGen *)gui :(MyOpenGLView *)gameView
{
	[self handleGUIUpDownArrowKeys: gui :gameView];
	
	if (([gameView isDown: 13] && ([gui selectedRow] == SAVE_OVERWRITE_YES_ROW))||[gameView isDown: 121]||[gameView isDown: 89])
	{
		pollControls=YES;
		[self nativeSavePlayer: commanderNameString];
		[self setGuiToStatusScreen];

		[beepSound play];
	}

	if (([gameView isDown: 13] && ([gui selectedRow] == SAVE_OVERWRITE_NO_ROW))||[gameView isDown: 27]||[gameView isDown: 110]||[gameView isDown: 78])
	{
		// esc or NO was pressed - get out of here
		pollControls=YES;
		[self setGuiToStatusScreen];

		[boopSound play];
	}
}


- (void) loadPlayerFromFile:(NSString *)fileToOpen
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
		
		shipKey = [fileDic objectForKey:@"ship_desc"];
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
		[self set_up];
		if (![self setCommanderDataFromDictionary:fileDic])
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
		NSLog(@"***** FILE LOADING ERROR!! *****");
		[[UNIVERSE gameController] setPlayerFileToLoad:nil];
		[UNIVERSE game_over];
		[UNIVERSE clearPreviousMessage];
		[UNIVERSE addMessage:@"Saved game failed to load." forCount: 9.0];
		if (fail_reason != nil)  [UNIVERSE addMessage: fail_reason forCount: 9.0];
		return;
	}

	[UNIVERSE setSystemTo:system_seed];
	[UNIVERSE removeAllEntitiesExceptPlayer:NO];
	[UNIVERSE setUpSpace];

	status = STATUS_DOCKED;
	[UNIVERSE setViewDirection:VIEW_GUI_DISPLAY];

	docked_station = [UNIVERSE station];
	if (docked_station)
	{
		position = [docked_station position];
		[self setQRotation: kIdentityQuaternion];
		v_forward = vector_forward_from_quaternion(q_rotation);
		v_right = vector_right_from_quaternion(q_rotation);
		v_up = vector_up_from_quaternion(q_rotation);
	}

	flight_roll = 0.0;
	flight_pitch = 0.0;
	flight_yaw = 0.0;
	flight_speed = 0.0;

	if (![docked_station localMarket])
	{
		if ([fileDic objectForKey:@"localMarket"])
		{
			[docked_station setLocalMarket:(NSArray *)[fileDic objectForKey:@"localMarket"]];
		}
		else
		{
			[docked_station initialiseLocalMarketWithSeed:system_seed andRandomFactor:market_rnd];
		}
	}
	[self setGuiToStatusScreen];
}

@end


@implementation PlayerEntity (OOLoadSavePrivate)

#if OOLITE_USE_APPKIT_LOAD_SAVE

- (void)loadPlayerWithPanel
{
    int				result;
    NSArray			*fileTypes = nil;
    NSOpenPanel		*oPanel = nil;
	
	fileTypes = [NSArray arrayWithObject:@"oolite-save"];
	oPanel = [NSOpenPanel openPanel];
	
    [oPanel setAllowsMultipleSelection:NO];
    result = [oPanel runModalForDirectory:nil file:nil types:fileTypes];
    if (result == NSOKButton)  [self loadPlayerFromFile:[oPanel filename]];
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

#endif


- (void) setGuiToLoadCommanderScreen
{
	GuiDisplayGen *gui=[UNIVERSE gui];
	NSString*	dir = [[UNIVERSE gameController] playerFileDirectory];
	if (!dir)	dir = [[NSFileManager defaultManager] defaultCommanderPath];
	

	gui_screen = GUI_SCREEN_LOAD;

	[gui clear];
	[gui setTitle:@"Select Commander"];

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
	[gui setTitle:[NSString stringWithFormat:@"Save Commander"]];

	currentPage = 0;
	[self lsCommanders:gui	directory:dir	pageNumber: currentPage	highlightName:nil];
	
	[gui setText:@"Commander name: " forRow: INPUTROW];
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
	[gui setTitle:[NSString stringWithFormat:@"Save Commander %@", cdrName]];

	[gui setText:[NSString stringWithFormat:@"Commander %@ already exists - overwrite this saved game?", cdrName] forRow:SAVE_OVERWRITE_WARN_ROW align: GUI_ALIGN_CENTER];

	[gui setText:@" YES " forRow: SAVE_OVERWRITE_YES_ROW align: GUI_ALIGN_CENTER];
	[gui setKey:GUI_KEY_OK forRow: SAVE_OVERWRITE_YES_ROW];

	[gui setText:@" NO " forRow: SAVE_OVERWRITE_NO_ROW align: GUI_ALIGN_CENTER];
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
   NSDictionary *descriptions=[UNIVERSE descriptions];
   int rangeStart=STARTROW;
   int lastIndex;
   int i;
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
		BOOL	pathIsDirectory = NO;
		if ([cdrFileManager fileExistsAtPath:path isDirectory:&pathIsDirectory] && (!pathIsDirectory))
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
		if (pathIsDirectory && ![[path lastPathComponent] hasPrefix:@"."])
			[cdrDetailArray addObject: [NSDictionary dictionaryWithObjectsAndKeys: @"YES", @"isFolder", path, @"saved_game_path", nil]];
	}

   if(![cdrDetailArray count])
   {
      // Empty directory; tell the user and exit immediately.
      [gui setText:@"No commanders found" forRow:STARTROW align:GUI_ALIGN_CENTER];
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
         NSLog(@"Commander %@ doesn't exist, very bad", highlightName);
         highlightIdx=0;
      }

      // figure out what page we need to be on
      page=highlightIdx/NUMROWS;
      highlightRowOnPage=highlightIdx % NUMROWS + STARTROW;
   }

   // We now know for certain what page we're on - 
   // set the first index of the first commander on this page.
   int firstIndex=page * NUMROWS;

   // Set up the GUI.
   int tabStop[GUI_MAX_COLUMNS];
   tabStop[0]=0;
   tabStop[1]=160;
   tabStop[2]=270;
   [gui setTabStops: tabStop];
   [gui setColor: [OOColor greenColor] forRow: LABELROW];
   [gui setArray: [NSArray arrayWithObjects: @"Commander Name", @"Rating", nil]
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
      [gui setArray:[NSArray arrayWithObjects:@" Back ", @" <-- ", nil]
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
      [gui setArray:[NSArray arrayWithObjects:@" More ", @" --> ", nil]
             forRow:ENDROW];
      [gui setKey:GUI_KEY_OK forRow:ENDROW];
      [gui setSelectableRange: NSMakeRange(rangeStart, NUMROWS+1)];
   }
  
	for (i=firstIndex; i < lastIndex; i++)
	{
		NSDictionary *cdr=[cdrDetailArray objectAtIndex: i];
		if ([cdr objectForKey:@"isSavedGame"])
		{
			int rating=[self getRatingFromKills:  [(NSNumber *)[cdr objectForKey:@"ship_kills"] intValue]];
			NSString *ratingDesc=[(NSArray *)[descriptions objectForKey:@"rating"] objectAtIndex:rating];
			[gui setArray:[NSArray arrayWithObjects:
					[NSString stringWithFormat:@" %@ ",[cdr objectForKey:@"player_name"]],
					[NSString stringWithFormat:@" %@ ",ratingDesc],
					nil]
				forRow:row];
			if ([player_name isEqual:[cdr objectForKey:@"player_name"]])
				highlightRowOnPage = row;
				
			[gui setKey:GUI_KEY_OK forRow:row];
			row++;
		}
		if ([cdr objectForKey:@"isParentFolder"])
		{
			[gui setArray:[NSArray arrayWithObjects:
					[NSString stringWithFormat:@" (..) %@ ", [(NSString*)[cdr objectForKey:@"saved_game_path"] lastPathComponent]],
					@"",
					nil]
				forRow:row];
			[gui setColor: [OOColor orangeColor] forRow: row];
			[gui setKey:GUI_KEY_OK forRow:row];
			row++;
		}
		if ([cdr objectForKey:@"isFolder"])
		{
			[gui setArray:[NSArray arrayWithObjects:
					[NSString stringWithFormat:@" >> %@ ", [(NSString*)[cdr objectForKey:@"saved_game_path"] lastPathComponent]],
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
	NSDictionary *descriptions = [UNIVERSE descriptions];
	GuiDisplayGen *gui=[UNIVERSE gui];
	[UNIVERSE removeDemoShips];
	NSDictionary *cdr=[cdrDetailArray objectAtIndex: cdrArrayIndex];
	
	[gui setText:@"" forRow: CDRDESCROW align: GUI_ALIGN_LEFT]; 
	[gui setText:@"" forRow: CDRDESCROW + 1 align: GUI_ALIGN_LEFT]; 
	
	if ([cdr objectForKey:@"isFolder"])
	{
#ifdef GNUSTEP
		NSString *folderDesc=[NSString stringWithFormat: @"Hold Ctrl and press return to open folder: %@", [(NSString *)[cdr objectForKey:@"saved_game_path"] lastPathComponent]];
#else     
		NSString *folderDesc=[NSString stringWithFormat: @"Hold command and press return to open folder: %@", [(NSString *)[cdr objectForKey:@"saved_game_path"] lastPathComponent]];
#endif
		
		[gui addLongText: folderDesc startingAtRow: CDRDESCROW align: GUI_ALIGN_LEFT];             
		
		return;
	}
	
	if ([cdr objectForKey:@"isParentFolder"])
	{
#ifdef GNUSTEP     
		NSString *folderDesc=[NSString stringWithFormat: @"Hold Ctrl and press return to open parent folder: %@", [(NSString *)[cdr objectForKey:@"saved_game_path"] lastPathComponent]];
#else      
		NSString *folderDesc=[NSString stringWithFormat: @"Hold command and press return to open parent folder: %@", [(NSString *)[cdr objectForKey:@"saved_game_path"] lastPathComponent]];
#endif
		
		[gui addLongText: folderDesc startingAtRow: CDRDESCROW align: GUI_ALIGN_LEFT];             
		
		return;
	}
	
	if (![cdr objectForKey:@"isSavedGame"])	// don't show things that aren't saved games
		return;
	
	if(!docked_station)  docked_station = [UNIVERSE station];
	
	// Display the commander's ship.
	NSString		*shipDesc = [cdr objectForKey:@"ship_desc"];
	NSString		*shipName = nil;
	NSDictionary	*shipDict = nil;
	
	shipDict = [UNIVERSE getDictionaryForShip:shipDesc];
	if(shipDict != nil)
	{
		[self showShipyardModel:shipDict];
		shipName = [shipDict objectForKey: KEY_NAME];
	}
	else  shipName = @"Unknown - missing OXP?";
	
	// Make a short description of the commander
	int legalStatus=[(NSNumber *)[cdr objectForKey: @"legal_status"] intValue];
	NSString *legalDesc;
	int legalIndex=0;
	if(legalStatus)
		legalIndex=(legalStatus <= 50) ? 1 : 2;
	switch (legalIndex)
	{
		case 0:
			legalDesc=@"clean";
			break;
		case 1:
			legalDesc=@"an offender";
			break;
		case 2:
			legalDesc=@"a fugitive";
			break;
		default:
			// never should get here
			legalDesc=@"an unperson";
	}
	
	int rating=[self getRatingFromKills: 
		[(NSNumber *)[cdr objectForKey:@"ship_kills"] intValue]];
	int money=[(NSNumber *)[cdr objectForKey:@"credits"] intValue];
	
	// it will suffice to display the balance to the nearest credit
	// instead of tenths of a credit.
	money /= 10;
	
	NSString *cdrDesc;
	cdrDesc = [NSString stringWithFormat:@"Commander %@ is rated %@ and is %@, with %d Cr in the bank. Ship: %@",
										 [cdr objectForKey:@"player_name"],
										 [[descriptions objectForKey:@"rating"] objectAtIndex: rating],
										 legalDesc, 
										 money, 
										 shipName];
	
	[gui addLongText:cdrDesc startingAtRow:CDRDESCROW align:GUI_ALIGN_LEFT];             
}


- (int) findIndexOfCommander: (NSString *)cdrName
{
   int i;
   for (i=0; i < [cdrDetailArray count]; i++)
   {
      NSString *currentName=[(NSDictionary *)[cdrDetailArray objectAtIndex: i] objectForKey:@"player_name"];
      if([cdrName compare: currentName] == NSOrderedSame)
      {
         return i;
      }
   }

   // not found!
   return -1;
}

@end
