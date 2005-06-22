//
// LoadSave.h
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
#import "PlayerEntity.h"
#import "GuiDisplayGen.h"
#import "MyOpenGLView.h"
#import "Universe.h"

#define STARTROW 2
#define ENDROW 14
#define COLUMNS 2
#define INPUTROW 16

@interface PlayerEntity (LoadSave)

   - (void) setGuiToLoadCommanderScreen;
   - (void) setGuiToSaveCommanderScreen;
   - (void) lsCommanders: (GuiDisplayGen *)gui;
   - (void) commanderSelector: (GuiDisplayGen *)gui
                             : (MyOpenGLView *)gameView;
   - (void) saveCommanderInputHandler: (GuiDisplayGen *)gui
                                     : (MyOpenGLView *)gameView;   
   
@end

