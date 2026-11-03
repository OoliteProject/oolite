/*

OOWaypoint.h

A waypoint for the HUD


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

#import "Entity.h"

#include "oofnd/PList.hpp"
#include "oofnd/StdLib.hpp"

/*	Foundation sweep (proposed ADR-0043, bead oo-tmna): +waypointWithDictionary: takes an oo::PList;
        -initWithDictionary: and the beacon accessors are shared and keep id; the beacon strings are
        std::optional (nil stays nil). Foundation declares -initWithDictionary: too, so its typed form
        is the twin -cxx_initWithDictionary: (bead oo-3rb.292.1).
*/
@interface OOWaypointEntity : Entity <OOBeaconEntity> {
@private
    OOScalar _size;

    std::optional<std::string> _beaconCode; // nullopt: nil
    std::optional<std::string> _beaconLabel;
    OOWeakReference* _prevBeacon;
    OOWeakReference* _nextBeacon;
    id<OOHUDBeaconIcon> _beaconDrawable;
    BOOL oriented;
}

+ (instancetype)waypointWithDictionary:(const oo::PList&)info;

- (id)initWithDictionary:(id)info; // shared selector (Foundation declares -initWithDictionary: too): -cxx_initWithDictionary: with an Objective-C dictionary
- (id)cxx_initWithDictionary:(const oo::PList&)info OO_RETURNS_RETAINED;

- (BOOL)oriented;
- (OOScalar)size;
- (void)setSize:(OOScalar)newSize;

@end
