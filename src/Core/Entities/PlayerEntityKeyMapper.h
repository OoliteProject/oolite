/*

PlayerEntityKeyMapper.h

Joystick support for SDL implementation of Oolite.

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

#import "PlayerEntity.h"
#import "GuiDisplayGen.h"
#import "MyOpenGLView.h"
#import "Universe.h"

#define MAX_ROWS_KC_FUNCTIONS		   12

#define GUI_ROW_KC_SELECTKBD        1
#define GUI_ROW_KC_HEADING			   4
#define GUI_ROW_KC_FUNCSTART		   5
#define GUI_ROW_KC_FUNCEND			   (GUI_ROW_KC_FUNCSTART + MAX_ROWS_KC_FUNCTIONS - 1)
#define GUI_ROW_KC_ERROR            17
#define GUI_ROW_KC_INSTRUCT		   18


#define GUI_ROW_KC_CONFIRMCLEAR     5
#define GUI_ROW_KC_CONFIRMCLEAR_YES	8
#define GUI_ROW_KC_CONFIRMCLEAR_NO  9

#define GUI_ROW_KC_UPDATE_FUNCNAME  1
#define GUI_ROW_KC_KEY              3
#define GUI_ROW_KC_SHIFT            4
#define GUI_ROW_KC_MOD1             5
#define GUI_ROW_KC_MOD2             6
#define GUI_ROW_KC_UPDATE_INFO      13
#define GUI_ROW_KC_VALIDATION       16
#define GUI_ROW_KC_SAVE             17
#define GUI_ROW_KC_CANCEL           18

#define GUI_ROW_KC_ENTRY_INFO       2

// Dictionary keys
#define KEY_KC_GUIDESC  @"guiDesc"
#define KEY_KC_DEFINITION @"keyDef"
#define KEY_KC_HEADER @"header"

// Dictionary keys - used in the defaults file
#define KEYCONFIG_OVERRIDES @"KeyConfigOverrides"  // NSUserDefaults

@interface PlayerEntity (KeyMapper)
   - (void) resetKeyFunctions;
   - (void) initCheckingDictionary;

   - (void) setGuiToKeyMapperScreen:(unsigned)skip resetCurrentRow:(BOOL)resetCurrentRow;
   - (void) setGuiToKeyMapperScreen:(unsigned)skip;
   - (void) keyMapperInputHandler:(GuiDisplayGen *)gui view:(MyOpenGLView *)gameView;

   - (void) setGuiToKeyConfigScreen;
   - (void) setGuiToKeyConfigScreen:(BOOL) resetSelectedRow;
   - (void) handleKeyConfigKeys:(GuiDisplayGen *)gui view:(MyOpenGLView *)gameView;
   - (void) outputKeyDefinition:(NSString *)key shift:(NSString *)shift mod1:(NSString *)mod1 mod2:(NSString *)mod2 skiprows:(NSUInteger)skiprows;

   - (void) setGuiToKeyConfigEntryScreen;
   - (void) handleKeyConfigEntryKeys:(GuiDisplayGen *)gui view:(MyOpenGLView *)gameView;

   - (void) setGuiToConfirmClearScreen;
   - (void) handleKeyMapperConfirmClearKeys:(GuiDisplayGen *)gui view:(MyOpenGLView *)gameView;

   - (void) setGuiToKeyboardLayoutScreen:(unsigned)skip;
   - (void) setGuiToKeyboardLayoutScreen:(unsigned)skip resetCurrentRow:(BOOL)resetCurrentRow;
   - (void) handleKeyboardLayoutEntryKeys:(GuiDisplayGen *)gui view:(MyOpenGLView *)gameView;

   - (NSDictionary *)makeKeyGuiDict:(NSString *)what keyDef:(NSString *)keyDef;
   - (NSDictionary *)makeKeyGuiDictHeader:(NSString *)header;

@end