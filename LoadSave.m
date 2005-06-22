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
}

- (void) setGuiToSaveCommanderScreen
{
   GameController *controller=[universe gameController];
   GuiDisplayGen *gui=[universe gui];

   gui_screen = GUI_SCREEN_SAVE;

   [gui clear];
   [gui setTitle:[NSString stringWithFormat:@"Save Commander"]];
   
   [self lsCommanders: gui];
   [gui setSelectedRow: STARTROW];
   if(commanderNameString)
   {
      [gui setText:[NSString stringWithFormat:@"Commander name: %@",
                  commanderNameString] forRow: INPUTROW];
   }
   else
   {
      [gui setText:@"Commander name: " forRow: INPUTROW];
   }
   [gui setColor:[NSColor cyanColor] forRow:16];
   [gui setShowTextCursor: YES];
   [gui setCurrentRow: 16];
   [universe guiUpdated];
}

- (void) lsCommanders: (GuiDisplayGen *)gui
{
   NSEnumerator *cdrEnum;
   NSArray *cdrArray=
      [NSArray arrayWithObjects: @"test one", @"test two", @"test three",
       nil];
   NSString *cdrName;
   int row=STARTROW;

   cdrEnum=[cdrArray objectEnumerator];
   while((cdrName=[cdrEnum nextObject]) != nil)
   {   
      [gui setText:cdrName forRow:row align:GUI_ALIGN_CENTER];
      row++;
   }
   [gui setSelectableRange: 
                  NSMakeRange(STARTROW, STARTROW + [cdrArray count])];
}

- (void) commanderSelector
            : (GuiDisplayGen *)gui
            : (MyOpenGLView *)gameView
{
   [self handleGUIUpDownArrowKeys: gui :gameView :-1];
}

- (void) saveCommanderInputHandler
            : (GuiDisplayGen *)gui
            : (MyOpenGLView *)gameView
{
   [self handleGUIUpDownArrowKeys: gui :gameView :-1];
   if([[gameView typedString] length])
      commanderNameString=[gameView typedString];
}

@end
