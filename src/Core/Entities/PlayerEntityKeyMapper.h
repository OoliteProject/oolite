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

#define MAX_ROWS_KC_FUNCTIONS		15

#define GUI_ROW_KC_HEADING			1
#define GUI_ROW_KC_FUNCSTART		2
#define GUI_ROW_KC_FUNCEND			(GUI_ROW_KC_FUNCSTART + MAX_ROWS_KC_FUNCTIONS - 1)
#define GUI_ROW_KC_INSTRUCT		18

// Dictionary keys
#define KEY_KC_GUIDESC  @"guiDesc"
#define KEY_KC_DEFINITION @"keyDefinition"

@interface PlayerEntity (KeyMapper)

   - (void) setGuiToKeyMapperScreen: (unsigned)skip resetCurrentRow: (BOOL) resetCurrentRow;
   - (void) setGuiToKeyMapperScreen: (unsigned)skip;
   - (void) keyMapperInputHandler: (GuiDisplayGen *)gui
							   view: (MyOpenGLView *)gameView;

   - (NSDictionary *)makeKeyGuiDict:(NSString *)what keyDef:(NSString *)keyDef;

@end