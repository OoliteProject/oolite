/*

PlayerEntityLoadSave.h

Created for the Oolite-Linux project (but is portable)

LoadSave has been separated out into a separate category because
PlayerEntity.m has gotten far too big and is in danger of becoming
the whole general mish mash.

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

/* The category PlayerEntity (LoadSave) is members of PlayerEntity, declared in
 * PlayerEntity.h. This header stays for the files that include it.
 */
#include "GuiDisplayGen.h"
#include "MyOpenGLView.h"
#include "Universe.h"

#define EXITROW 1
#define LABELROW 2
#define BACKROW 3
#define STARTROW 4
#define ENDROW 17
#define MOREROW 17
#define NUMROWS 13
#define COLUMNS 2
#define INPUTROW 21
#define CDRDESCROW 19
#define SAVE_OVERWRITE_WARN_ROW 5
#define SAVE_OVERWRITE_YES_ROW 8
#define SAVE_OVERWRITE_NO_ROW 9

// The load / save macros (USE_CUSTOM_LOAD_SAVE_ON_MAC_DEBUG,
// OOLITE_USE_APPKIT_LOAD_SAVE, OO_USE_APPKIT_LOAD_SAVE_ALWAYS,
// OO_USE_CUSTOM_LOAD_SAVE) are in PlayerEntity.h, whose member declarations of
// this file's categories they condition.

OOCreditsQuantity OODeciCreditsFromDouble(double doubleDeciCredits);

/*	Value is either a real or something that can be duck-typed to an integer
   as oo::plist_get::unsignedLongLongFrom() reads it (nullptr: 0).
*/
OOCreditsQuantity OODeciCreditsFromPList(const oo::PList* value);
