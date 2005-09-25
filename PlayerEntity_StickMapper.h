// PlayerEntity_StickMapper.h
//
// Created for the Oolite-Linux project, but portable to other archs.
//
// Dylan Smith, 2005-09-24
//
// This category adds the GUI to handle player assignments of joystick
// things (axes, buttons) to game functions.
//
// oolite: (c) 2004 Giles C Williams.
// This work is licensed under the Creative Commons Attribution NonCommercial
// ShareAlike license.
//

#import "PlayerEntity.h"
#import "GuiDisplayGen.h"
#import "MyOpenGLView.h"
#import "Universe.h"

#define STICKNAME_ROW   1
#define HEADINGROW      3
#define FUNCSTART_ROW   4
#define INSTRUCT_ROW    20

// Dictionary keys
#define KEY_GUIDESC  @"guiDesc"
#define KEY_ALLOWABLE @"allowable"
#define KEY_AXISFN @"axisfunc"
#define KEY_BUTTONFN @"buttonfunc"

@interface PlayerEntity (StickMapper)

   - (void) setGuiToStickMapperScreen;
   - (void) stickMapperInputHandler: (GuiDisplayGen *)gui
                               view: (MyOpenGLView *)gameView;
   // Callback method
   - (void) updateFunction: (NSDictionary *)hwDict;

   // internal methods
   - (NSArray *)getStickFunctionList;
   - (void)displayFunctionList: (GuiDisplayGen *)gui;
   - (NSString *)describeStickDict: (NSDictionary *)stickDict;
   - (NSString *)hwToString: (int)hwFlags;

   // Future: populate via plist
   - (NSDictionary *)makeStickGuiDict: (NSString *)what 
                            allowable: (int)allowable
                               axisfn: (int)axisfn
                                butfn: (int)butfn;
                              
@end

