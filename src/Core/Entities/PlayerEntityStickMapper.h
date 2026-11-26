/*

PlayerEntityStickMapper.h

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

/* The category PlayerEntity (StickMapper) is members of PlayerEntity, declared
 * in PlayerEntity.h. This header stays for the files that include it.
 */
#include <algorithm>
#include <chrono>
#include <condition_variable>
#include <cstddef>
#include <cstdint>
#include <functional>
#include <map>
#include <memory>
#include <mutex>
#include <optional>
#include <set>
#include <string>
#include <string_view>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <vector>

#include "GuiDisplayGen.h"
#include "MyOpenGLView.h"
#include "Universe.h"
#include "oofnd/PList.hpp"

inline constexpr int MAX_ROWS_FUNCTIONS = 12;

inline constexpr int GUI_ROW_STICKNAME = 1;
// leave row 2 empty - we need it in case we have a
// second joystick connected. Also, we need a different way
// of listing joysticks, if we ever decide to support more
// than the current maximum of 2 - Nikos 20151103
inline constexpr int GUI_ROW_STICKPROFILE = 3;
inline constexpr int GUI_ROW_HEADING = 4;
inline constexpr int GUI_ROW_FUNCSTART = 5;
inline constexpr int GUI_ROW_FUNCEND =
    GUI_ROW_FUNCSTART + MAX_ROWS_FUNCTIONS - 1;
inline constexpr int GUI_ROW_INSTRUCT = 18;

// Dictionary keys (of the oo::PList function entries)
#define KEY_HEADER "header"
#define KEY_GUIDESC "guiDesc"
#define KEY_ALLOWABLE "allowable"
#define KEY_AXISFN "axisfunc"
#define KEY_BUTTONFN "buttonfunc"
