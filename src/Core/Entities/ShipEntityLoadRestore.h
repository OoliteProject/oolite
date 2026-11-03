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

#import "ShipEntity.h"

#include "oofnd/PList.hpp"
#include "oofnd/StdLib.hpp"
#include "oofnd/objc/OOObjCRef.h"

@class OOShipGroup;

/*	Foundation sweep (proposed ADR-0043, bead oo-0s1h): a saved ship is an oo::PList (a Dict; null
        for no ship, as nil was), and the save/restore context, which was a mutable dictionary keyed by
        group pointers, is this struct. Both selectors are unique.
*/
struct OOShipSaveContext {
    std::map<OOShipGroup*, unsigned> groupIDs; // not retained, as the pointer-box keys were not
    unsigned nextGroupID = 0;
    std::vector<oo::ObjCRef<OOShipGroup*>> groups; // keeps the groups alive while they have IDs
    std::map<NSUInteger, oo::ObjCRef<OOShipGroup*>> groupsByID;
};

@interface ShipEntity (LoadRestore)

/*	Produces a property list representation of a specific ship. Intended for
        use with wormholes, but should probably generalize quite well.

        The optional "context" (nullptr for none) is used to synchronise certain
        state when saving multiple ships - currently, groups. It is not a property
        list and does not need to be saved alongside the ships.
*/
- (oo::PList)savedShipDictionaryWithContext:(OOShipSaveContext*)context;

/*	Restore a ship from a property list representation generated with
        -savedShipDictionary. If the ship can't be restored and fallback is YES,
        an attempt will be made to generate a new ship with the same primary role.
*/
+ (id)shipRestoredFromDictionary:(const oo::PList&)dictionary useFallback:(BOOL)fallback context:(OOShipSaveContext*)context;

@end
