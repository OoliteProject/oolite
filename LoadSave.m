#ifdef LOADSAVEGUI
//
// LoadSave.m
//
// Created for the Oolite-Linux project (but is portable)
//
// Dylan Smith, 2005-06-21
//
// LoadSave has been separated out into a separate category because
// PlayerEntity.m has gotten far too big and is in danger of becoming
// the whole general mish mash.
//
// oolite: (c) 2004 Giles C Williams.
// This work is licensed under the Creative Commons Attribution NonCommercial
// ShareAlike license.
//

#import "LoadSave.h"
#import "OOFileManager.h"

@implementation PlayerEntity (LoadSave)

- (void) setGuiToLoadCommanderScreen
{
   GuiDisplayGen *gui=[universe gui];

   gui_screen = GUI_SCREEN_LOAD;

   [gui clear];
   [gui setTitle:[NSString stringWithFormat:@"Select Commander"]];
   
   [self lsCommanders:gui  pageNumber:0 highlightName: nil];
   [universe guiUpdated];
   [[universe gameView] supressKeysUntilKeyUp];
   
   [self setShowDemoShips: YES];
   [universe setDisplayText: YES];
   [universe setViewDirection: VIEW_DOCKED];
}

- (void) setGuiToSaveCommanderScreen: (NSString *)cdrName
{
   GuiDisplayGen *gui=[universe gui];
   MyOpenGLView *gameView=[universe gameView];

   gui_screen = GUI_SCREEN_SAVE;

   [gui clear];
   [gui setTitle:[NSString stringWithFormat:@"Save Commander"]];
   
   [self lsCommanders: gui  pageNumber:0  highlightName: cdrName];
   [gui setText:@"Commander name: " forRow: INPUTROW];
   [gui setColor:[NSColor cyanColor] forRow:INPUTROW];
   [gui setShowTextCursor: YES];
   [gui setCurrentRow: INPUTROW];

   [gameView setTypedString: cdrName];
   [gameView supressKeysUntilKeyUp];
   [universe guiUpdated];
   
   [self setShowDemoShips: YES];
   [universe setDisplayText: YES];
   [universe setViewDirection: VIEW_DOCKED];
}

- (void) lsCommanders: (GuiDisplayGen *)gui
                       pageNumber: (int)page
                       highlightName: (NSString *)highlightName
{
   NSFileManager *cdrFileManager=[NSFileManager defaultManager];
   NSDictionary *descriptions=[universe descriptions];
   int rangeStart=STARTROW;
   int lastIndex;
   int i;
   int row=STARTROW;

   // release any prior instances
   if(cdrDetailArray) [cdrDetailArray release];
   
   // cdrArray defined in PlayerEntity.h
   NSArray *cdrArray=[cdrFileManager commanderContents];
   
   // get commander details so a brief rundown of the commander's details may
   // be displayed.
   cdrDetailArray=[[NSMutableArray alloc] init];
   for(i = 0; i < [cdrArray count]; i++)
   {
      NSDictionary *cdr=[NSDictionary dictionaryWithContentsOfFile:
                           [cdrArray objectAtIndex:i]]; 
#ifdef WIN32
      // untested... I don't have a Windows box to test this with.
      if(!cdr)
         cdr=(NSDictionary *)[ResourceManager parseXMLPropertyList:
                              [NSString stringWithContentsOfFile:[cdrArray count]]];
#endif
      if(cdr)
      {
         [cdrDetailArray addObject: cdr];
      }
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
      NSLog(@"Page=%d  Highlight=%d  Cdr index=%d", page, highlightRowOnPage, highlightIdx);
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
   [gui setColor: [NSColor greenColor] forRow: LABELROW];
   [gui setArray: [NSArray arrayWithObjects: @"Commander Name", @"Rating", nil]
         forRow:LABELROW];

   if(page)
   {
      [gui setArray:[NSArray arrayWithObjects:@" Back ", @" <-- ", nil]
             forRow:STARTROW-1];
      [gui setKey:GUI_KEY_OK forRow:STARTROW-1];
      rangeStart=STARTROW-1;
      if(!highlightIdx)
         highlightIdx=firstIndex;
   }

   if(firstIndex + NUMROWS > [cdrDetailArray count])
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
  
   for(i=firstIndex; i < lastIndex; i++)
   {
      NSDictionary *cdr=[cdrDetailArray objectAtIndex: i]; 
      int rating=[self getRatingFromKills: 
                     [(NSNumber *)[cdr objectForKey:@"ship_kills"] intValue]];
      NSString *ratingDesc=[(NSArray *)[descriptions objectForKey:@"rating"]
                            objectAtIndex:rating];
      [gui setArray:[NSArray arrayWithObjects:
                        [cdr objectForKey:@"player_name"],
                        ratingDesc,
                        nil]
             forRow:row];
      [gui setKey:GUI_KEY_OK forRow:row];
      row++;
   }
   [gui setSelectedRow: highlightRowOnPage];

   // show the first ship, this will be the selected row
   [self showCommanderShip: highlightIdx];

   // need this later, make sure it's not garbage collected.
   [cdrDetailArray retain];
}

- (NSString *) commanderSelector
            : (GuiDisplayGen *)gui
            : (MyOpenGLView *)gameView
{
   int idx;
   if([self handleGUIUpDownArrowKeys: gui :gameView])
   {
      int guiSelectedRow=[gui selectedRow];
      idx=(guiSelectedRow - STARTROW) + (currentPage * NUMROWS);
      NSLog(@"idx = %d", idx);
      if(guiSelectedRow != MOREROW && guiSelectedRow != BACKROW)
      {
         [self showCommanderShip: idx];
      }
      [universe guiUpdated];
   }
   else
   {
      idx=([gui selectedRow] - STARTROW) + (currentPage * NUMROWS);
   }
   
   // Enter pressed - find the commander name underneath.
   if ([gameView isDown:13])
   {
      NSLog(@"Row = %d", [gui selectedRow]);
      switch ([gui selectedRow])
      {
         case BACKROW:
            currentPage--;
            [gui clear];
            [self lsCommanders: gui  pageNumber: currentPage  highlightName: nil];
            [gameView supressKeysUntilKeyUp];
            break;
         case MOREROW:
            NSLog(@"Plus one page");
            [gui clear];
            currentPage++;
            [self lsCommanders: gui  pageNumber: currentPage  highlightName: nil];
            [gameView supressKeysUntilKeyUp];
            break;
         default:
            NSLog(@"Loading idx = %d", idx);
            NSDictionary *cdr=[cdrDetailArray objectAtIndex: idx];
            NSString *filename=[NSString stringWithFormat:
               @"%@.oolite-save", (NSString *)[cdr objectForKey:@"player_name"]];
            return filename;
      }
   } 
   return nil;
}

- (void) saveCommanderInputHandler
            : (GuiDisplayGen *)gui
            : (MyOpenGLView *)gameView
{
   [self handleGUIUpDownArrowKeys: gui :gameView];
   commanderNameString=[gameView typedString];
   [gui setText:
         [NSString stringWithFormat:@"Commander name: %@", commanderNameString]
         forRow: INPUTROW];
   
   if([gameView isDown: 13] && [commanderNameString length])
   {
      [self nativeSavePlayer: commanderNameString];
   }
}

// essentially the same as savePlayer but omitting all the AppKit dialog
// stuff and taking a string instead.
- (void) nativeSavePlayer
            : (NSString *)cdrName
{
   NSMutableString *saveString=[[NSMutableString alloc] initWithString: cdrName];
   [saveString appendString: @".oolite-save"];
   if (player_name) [player_name release];
   player_name=[cdrName retain];

   if(![[self commanderDataDictionary] writeToFile:saveString atomically:YES])
   {
      NSBeep();
      NSLog(@"***** ERROR: Save to %@ failed!", saveString);
      NSException *myException=
            [NSException exceptionWithName:@"ooliteException"
             reason:[NSString stringWithFormat:@"Attempt to save '%@' failed",
                  saveString]
             userInfo:nil];
      [myException raise];
      return;
   }      
   [self setGuiToStatusScreen];
}

// Get some brief details about the commander file.
- (void) showCommanderShip: (int)cdrArrayIndex
{
   NSDictionary *descriptions=[universe descriptions];
   GuiDisplayGen *gui=[universe gui];
   [universe removeDemoShips];
   NSDictionary *cdr=[cdrDetailArray objectAtIndex: cdrArrayIndex];
   if(!docked_station)
      docked_station=[universe station];

   // Display the commander's ship.
   NSString *shipDesc=[cdr objectForKey:@"ship_desc"];
   NSString *shipName;
   NSDictionary *shipDict=[universe getDictionaryForShip: shipDesc]; 
   if(shipDict)
   {
      [self showShipyardModel: shipDict];
      shipName=(NSString *)[shipDict objectForKey: KEY_NAME];
   }
   else
   {
      NSLog(@"Erk. No shipDict for %@", shipDesc);
      shipName=@"non-existent ship";
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
#endif
