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

#pragma once

#include "PlayerEntity.h"

/* The category PlayerEntity (KeyMapper) is members of PlayerEntity, declared
 * in PlayerEntity.h. This header stays for the files that include it.
 */
#include <string_view>

#include "GuiDisplayGen.h"
#include "MyOpenGLView.h"
#include "Universe.h"
#include "oofnd/PList.hpp"
#include "oofnd/StdLib.hpp"

#define MAX_ROWS_KC_FUNCTIONS 12

#define GUI_ROW_KC_SELECTKBD 1
#define GUI_ROW_KC_HEADING 4
#define GUI_ROW_KC_FUNCSTART 5
#define GUI_ROW_KC_FUNCEND (GUI_ROW_KC_FUNCSTART + MAX_ROWS_KC_FUNCTIONS - 1)
#define GUI_ROW_KC_ERROR 17
#define GUI_ROW_KC_INSTRUCT 18

#define GUI_ROW_KC_CONFIRMCLEAR 5
#define GUI_ROW_KC_CONFIRMCLEAR_YES 8
#define GUI_ROW_KC_CONFIRMCLEAR_NO 9

#define GUI_ROW_KC_UPDATE_FUNCNAME 1
#define GUI_ROW_KC_KEY 3
#define GUI_ROW_KC_SHIFT 4
#define GUI_ROW_KC_MOD1 5
#define GUI_ROW_KC_MOD2 6
#define GUI_ROW_KC_UPDATE_INFO 13
#define GUI_ROW_KC_VALIDATION 16
#define GUI_ROW_KC_SAVE 17
#define GUI_ROW_KC_CANCEL 18

#define GUI_ROW_KC_ENTRY_INFO 2

// Dictionary keys
inline constexpr std::string_view KEY_KC_GUIDESC = "guiDesc";
inline constexpr std::string_view KEY_KC_DEFINITION = "keyDef";
inline constexpr std::string_view KEY_KC_HEADER = "header";

// Dictionary keys - used in the defaults file
inline constexpr std::string_view KEYCONFIG_OVERRIDES =
    "KeyConfigOverrides";  // preferences key (oo::Defaults)
