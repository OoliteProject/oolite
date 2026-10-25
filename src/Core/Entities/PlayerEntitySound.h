/*

PlayerEntitySound.h

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

#include "oofnd/StdLib.hpp"


/*	Foundation sweep (proposed ADR-0043, bead oo-14c5): weapon identifiers and sound keys are
	std::strings.

	Bead oo-xowh: the sound methods are members of PlayerEntity (PlayerEntity.h), defined in
	PlayerEntitySound.mm. The Objective-C selectors (-playIdentOn, -cxx_playShieldHit:weaponIdentifier:
	and the rest) were the facade's category (OOSound) in PlayerEntity+ObjCBridge.h (deleted by bead oo-9ht.177). This header is
	kept so the files that import it keep compiling; it declares nothing.
*/
