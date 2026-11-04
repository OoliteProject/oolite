/*

ShipEntityLoadRestore.h

Support for saving and restoring individual non-player ships.


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

#include "ShipEntity.h"
#include "oofnd/PList.hpp"
#include "oofnd/StdLib.hpp"

/*	A saved ship is an oo::PList (a Dict; null for no ship, as nil was), and
        the save/restore context, which was a mutable dictionary keyed by group
        pointers, is this struct. Both selectors are unique.
*/
struct OOShipSaveContext {
  std::map<OOShipGroup*, unsigned>
      groupIDs;  // not retained, as the pointer-box keys were not
  unsigned nextGroupID = 0;
  std::vector<oo::Ref<OOShipGroup>>
      groups;  // keeps the groups alive while they have IDs
  std::map<NSUInteger, oo::Ref<OOShipGroup>> groupsByID;
};

/*	The ShipEntity (LoadRestore) members are declared in ShipEntity.h and
        defined in ShipEntityLoadRestore.mm. This header stays for the files
        that import it, and for OOShipSaveContext.
*/
