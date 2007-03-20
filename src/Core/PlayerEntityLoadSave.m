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

#ifdef WIN32
#import "ResourceManager.h"
#endif

@implementation PlayerEntity (LoadSave)

- (void) setGuiToLoadCommanderScreen
{
	GuiDisplayGen *gui=[universe gui];
	NSString*	dir = [[universe gameController] playerFileDirectory];
	if (!dir)	dir = [[NSFileManager defaultManager] defaultCommanderPath];
	

	gui_screen = GUI_SCREEN_LOAD;

	[gui clear];
	[gui setTitle:@"Select Commander"];

	currentPage = 0;
	[self lsCommanders:gui	directory:dir	pageNumber: currentPage	highlightName:nil];
	
	[(MyOpenGLView *)[universe gameView] supressKeysUntilKeyUp];

	[self setShowDemoShips: YES];
	[universe setDisplayText: YES];
	[universe setDisplayCursor: YES];
	[universe setViewDirection: VIEW_GUI_DISPLAY];
}

- (void) setGuiToSaveCommanderScreen: (NSString *)cdrName
{
	GuiDisplayGen *gui=[universe gui];
	MyOpenGLView*	gameView = (MyOpenGLView*)[universe gameView];
	NSString*	dir = [[universe gameController] playerFileDirectory];
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
	[universe setDisplayText: YES];
	[universe setDisplayCursor: YES];
	[universe setViewDirection: VIEW_GUI_DISPLAY];
}

- (void) setGuiToOverwriteScreen: (NSString *)cdrName
{
	GuiDisplayGen *gui=[universe gui];
	MyOpenGLView*	gameView = (MyOpenGLView*)[universe gameView];

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
	[universe setDisplayText: YES];
	[universe setDisplayCursor: NO];
	[gameView setStringInput: gvStringInputNo];
	[universe setViewDirection: VIEW_GUI_DISPLAY];
}

- (void) lsCommanders: (GuiDisplayGen *)gui
						directory: (NSString*) directory
						pageNumber: (int)page
						highlightName: (NSString *)highlightName
{
   NSFileManager *cdrFileManager=[NSFileManager defaultManager];
   NSDictionary *descriptions=[universe descriptions];
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
			NSDictionary*	cdr = [NSDictionary dictionaryWithContentsOfFile: path]; 
			#ifdef WIN32
			// untested... I don't have a Windows box to test this with.
			if(!cdr)
				cdr=(NSDictionary *)[ResourceManager parseXMLPropertyList:	[NSString stringWithContentsOfFile:path]];
			#endif
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

- (NSString *) commanderSelector
            : (GuiDisplayGen *)gui
            : (MyOpenGLView *)gameView
{
	NSString*	dir = [[universe gameController] playerFileDirectory];
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
						[[universe gameController] setPlayerFileDirectory: newDir];
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
            : (GuiDisplayGen *)gui
            : (MyOpenGLView *)gameView
{
	NSString*	dir = [[universe gameController] playerFileDirectory];
	if (!dir)	dir = [[NSFileManager defaultManager] defaultCommanderPath];
	
	if ([self handleGUIUpDownArrowKeys: gui :gameView])
	{
		int guiSelectedRow=[gui selectedRow];
		int	idx = (guiSelectedRow - STARTROW) + (currentPage * NUMROWS);
		if (guiSelectedRow != MOREROW && guiSelectedRow != BACKROW)
		{
			[self showCommanderShip: idx];
		}
		if ([[cdrDetailArray objectAtIndex:idx] objectForKey:@"isSavedGame"])	// don't show things that aren't saved games
			commanderNameString = [[cdrDetailArray objectAtIndex:idx] objectForKey:@"player_name"];
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
				[[universe gameController] setPlayerFileDirectory: newDir];
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
            : (GuiDisplayGen *)gui
            : (MyOpenGLView *)gameView
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

// essentially the same as savePlayer but omitting all the AppKit dialog
// stuff and taking a string instead.
- (void) nativeSavePlayer
            : (NSString *)cdrName
{
	NSString*	dir = [[universe gameController] playerFileDirectory];
	if (!dir)	dir = [[NSFileManager defaultManager] defaultCommanderPath];

	NSString *savePath=[dir stringByAppendingPathComponent:[cdrName stringByAppendingPathExtension:@"oolite-save"]];

	if (player_name)
		[player_name release];

   // use a copy of the passed value to ensure it never gets changed underneath us
	player_name=[[NSString alloc] initWithString: cdrName];

	if(![[self commanderDataDictionary] writeOOXMLToFile:savePath atomically:YES])
	{
		//NSBeep();	// appkit dependency
		NSLog(@"***** ERROR: Save to %@ failed!", savePath);
		NSException *myException = [NSException
			exceptionWithName:@"OoliteException"
			reason:[NSString stringWithFormat:@"Attempt to save '%@' failed",
			savePath]
			userInfo:nil];
		[myException raise];
		return;
	}
	
	// set this as the default file to load / save
	if (save_path)
		[save_path autorelease];
	save_path = [savePath retain];
	[[universe gameController] setPlayerFileToLoad:save_path];
	[[universe gameController] setPlayerFileDirectory:save_path];

	[universe clearPreviousMessage];	// allow this to be given time and again
	[universe addMessage:[universe expandDescription:@"[game-saved]" forSystem:system_seed] forCount:2];
}

// check for an existing saved game...
- (BOOL) existingNativeSave: (NSString *)cdrName
{
	NSString*	dir = [[universe gameController] playerFileDirectory];
	if (!dir)	dir = [[NSFileManager defaultManager] defaultCommanderPath];

	NSString *savePath=[dir stringByAppendingPathComponent:[cdrName stringByAppendingPathExtension:@"oolite-save"]];
	return [[NSFileManager defaultManager] fileExistsAtPath:savePath];
}

// Get some brief details about the commander file.
- (void) showCommanderShip: (int)cdrArrayIndex
{
   NSDictionary *descriptions=[universe descriptions];
   GuiDisplayGen *gui=[universe gui];
   [universe removeDemoShips];
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
   
   if(!docked_station)
      docked_station=[universe station];

   // Display the commander's ship.
   NSString *shipDesc=[cdr objectForKey:@"ship_desc"];
   NSString *shipName = @"non-existent ship";
   NSDictionary *shipDict = nil;
   
   NS_DURING
	   
	   shipDict=[universe getDictionaryForShip: shipDesc];
	   
	NS_HANDLER
		
		if ([[localException name] isEqual: OOLITE_EXCEPTION_SHIP_NOT_FOUND])
		{
			NSLog(@"DEBUG EXCEPTION: No shipDict for %@", shipDesc);
			shipName = @"ship not found.";
			[gui setKey: GUI_KEY_SKIP forRow:[gui selectedRow]];
			[gui setColor:[OOColor grayColor] forRow:[gui selectedRow]];
			[gui setText:[NSString stringWithFormat:@"%@ (ship not found)", [gui selectedRowText]] forRow:[gui selectedRow]];
			[boopSound play];
		}
		else
		{
			NSLog(@"\n\n***** Encountered localException in [PlayerEntity (LoadSave) showCommanderShip:] : %@ : %@ *****\n\n", [localException name], [localException reason]);
			[localException raise];
		}
		
	NS_ENDHANDLER
	
   if(shipDict)
   {
	  [self showShipyardModel: shipDict];
	  shipName=(NSString *)[shipDict objectForKey: KEY_NAME];
   }

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

   NSString *cdrDesc=[NSString stringWithFormat:
         @"Commander %@ is rated %@ and is %@, with %d Cr in the bank. Ship: %@",
            (NSString *)[cdr objectForKey:@"player_name"],
            [(NSArray *)[descriptions objectForKey:@"rating"] objectAtIndex: rating],
            legalDesc, 
            money, 
            shipName];
            
   [gui addLongText: cdrDesc startingAtRow: CDRDESCROW align: GUI_ALIGN_LEFT];             
}

- (int) findIndexOfCommander: (NSString *)cdrName
{
   int i;
   for (i=0; i < [cdrDetailArray count]; i++)
   {
      NSString *currentName=[[cdrDetailArray objectAtIndex: i] objectForKey:@"player_name"];
      if([cdrName compare: currentName] == NSOrderedSame)
      {
         return i;
      }
   }

   // not found!
   return -1;
}

@end

