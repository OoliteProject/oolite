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
   
   [self lsCommanders: gui];
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
   
   [self lsCommanders: gui];
   [gui setSelectedRow: STARTROW];
   [gui setText:@"Commander name: " forRow: INPUTROW];
   [gui setColor:[NSColor cyanColor] forRow:16];
   [gui setShowTextCursor: YES];
   [gui setCurrentRow: 16];

   [gameView setTypedString: cdrName];
   [gameView supressKeysUntilKeyUp];
   [universe guiUpdated];
}

- (void) lsCommanders: (GuiDisplayGen *)gui
{
   NSFileManager *cdrFileManager=[NSFileManager defaultManager];
   NSEnumerator *cdrEnum;
   NSString *cdrName;
   int row=STARTROW;

   // cdrArray defined in PlayerEntity.h
   cdrArray=[cdrFileManager commanderContents];

   cdrEnum=[cdrArray objectEnumerator];
   while((cdrName=[cdrEnum nextObject]) != nil)
   {   
      [gui setText:cdrName forRow:row align:GUI_ALIGN_CENTER];
      row++;
   }
   [gui setSelectableRange: 
                  NSMakeRange(STARTROW, [cdrArray count])];

   // need this later, make sure it's not garbage collected.
   [cdrArray retain];
}

- (NSString *) commanderSelector
            : (GuiDisplayGen *)gui
            : (MyOpenGLView *)gameView
{
   [self handleGUIUpDownArrowKeys: gui :gameView :-1];
   
   // Enter pressed - find the commander name underneath.
   if ([gameView isDown:13])
   {
      int idx=[gui selectedRow] - STARTROW;
      NSString *cdr=[NSString stringWithString:[cdrArray objectAtIndex: idx]];

      [cdrArray release];
      return cdr; 
   } 
}

- (void) saveCommanderInputHandler
            : (GuiDisplayGen *)gui
            : (MyOpenGLView *)gameView
{
   [self handleGUIUpDownArrowKeys: gui :gameView :-1];
   commanderNameString=[gameView typedString];
   if([commanderNameString length])
   {
      [gui setText:
         [NSString stringWithFormat:@"Commander name: %@", commanderNameString]
         forRow: INPUTROW];
   }
}

@end
