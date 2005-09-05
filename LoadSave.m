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
   GameController *controller=[universe gameController];
   GuiDisplayGen *gui=[universe gui];

   gui_screen = GUI_SCREEN_LOAD;

   [gui clear];
   [gui setTitle:[NSString stringWithFormat:@"Select Commander"]];
   
   [self lsCommanders:gui  pageNumber:0];
   [gui setSelectedRow: STARTROW];
   [universe guiUpdated];
   [[universe gameView] supressKeysUntilKeyUp];
}

- (void) setGuiToSaveCommanderScreen: (NSString *)cdrName
{
   GameController *controller=[universe gameController];
   GuiDisplayGen *gui=[universe gui];
   MyOpenGLView *gameView=[universe gameView];

   gui_screen = GUI_SCREEN_SAVE;

   [gui clear];
   [gui setTitle:[NSString stringWithFormat:@"Save Commander"]];
   
   [self lsCommanders: gui  pageNumber:0];
   [gui setSelectedRow: STARTROW];
   [gui setText:@"Commander name: " forRow: INPUTROW];
   [gui setColor:[NSColor cyanColor] forRow:INPUTROW];
   [gui setShowTextCursor: YES];
   [gui setCurrentRow: INPUTROW];

   [gameView setTypedString: cdrName];
   [gameView supressKeysUntilKeyUp];
   [universe guiUpdated];
}

- (void) lsCommanders: (GuiDisplayGen *)gui
                       pageNumber: (int)page
{
   NSFileManager *cdrFileManager=[NSFileManager defaultManager];
   NSString *cdrName;
   int rangeStart=STARTROW;
   int firstIndex=page * NUMROWS;
   int lastIndex;
   int i;
   int row=STARTROW;
   
   // cdrArray defined in PlayerEntity.h
   cdrArray=[cdrFileManager commanderContents];
   if(![cdrArray count])
   {
      // Empty directory; tell the user and exit immediately.
      [gui setText:@"No commanders found" forRow:STARTROW align:GUI_ALIGN_CENTER];
      return;
   }

   if(page)
   {
      [gui setText:@"<- Back" forRow:STARTROW-1 align:GUI_ALIGN_CENTER];
      [gui setKey:GUI_KEY_OK forRow:STARTROW-1];
      rangeStart=STARTROW-1;
   }

   if(firstIndex + NUMROWS > [cdrArray count])
   {
      lastIndex=[cdrArray count];
      [gui setSelectableRange: NSMakeRange(rangeStart, lastIndex)];
   }
   else
   {
      lastIndex=(page * NUMROWS) + NUMROWS;
      [gui setText:@"More ->" forRow:ENDROW align:GUI_ALIGN_CENTER];
      [gui setKey:GUI_KEY_OK forRow:ENDROW];
      [gui setSelectableRange: NSMakeRange(rangeStart, NUMROWS+1)];
   }
  
   for(i=firstIndex; i < lastIndex; i++)
   { 
      [gui setText:[cdrArray objectAtIndex: i] forRow:row align:GUI_ALIGN_CENTER];
      [gui setKey:GUI_KEY_OK forRow:row];
      row++;
   }
   [gui setSelectedRow: rangeStart];

   // need this later, make sure it's not garbage collected.
   [cdrArray retain];
}

- (NSString *) commanderSelector
            : (GuiDisplayGen *)gui
            : (MyOpenGLView *)gameView
{
   int idx;
   [self handleGUIUpDownArrowKeys: gui :gameView];
   
   // Enter pressed - find the commander name underneath.
   if ([gameView isDown:13])
   {
      NSLog(@"Row = %d", [gui selectedRow]);
      switch ([gui selectedRow])
      {
         case BACKROW:
            currentPage--;
            [gui clear];
            [self lsCommanders: gui  pageNumber: currentPage];
            [gameView supressKeysUntilKeyUp];
            break;
         case MOREROW:
            NSLog(@"Plus one page");
            [gui clear];
            currentPage++;
            [self lsCommanders: gui  pageNumber: currentPage];
            [gameView supressKeysUntilKeyUp];
            break;
         default:
            idx=([gui selectedRow] - STARTROW) + (currentPage * NUMROWS);
            NSLog(@"Loading idx = %d", idx);
            NSString *cdr=[NSString stringWithString:[cdrArray objectAtIndex: idx]];

            [cdrArray release];
            return cdr; 
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

@end
