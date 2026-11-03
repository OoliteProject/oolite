/*

WormholeEntity.h

Entity subclass representing a wormhole between systems. (This is -- to use
technical terminology -- the blue blobby thing you see hanging in space. The
purple tunnel is RingEntity.)

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
#include "oofnd/objc/OOObjCRef.h"

#define WORMHOLE_EXPIRES_TIMEINTERVAL 900.0
#define WORMHOLE_SHRINK_RATE 4000.0
#define WORMHOLE_LEADER_SPEED_FACTOR 0.25

@class ShipEntity, Universe;

typedef enum {
    WH_SCANINFO_NONE = 0,
    WH_SCANINFO_SCANNED,
    WH_SCANINFO_COLLAPSE_TIME,
    WH_SCANINFO_ARRIVAL_TIME,
    WH_SCANINFO_DESTINATION,
    WH_SCANINFO_SHIP,
} WORMHOLE_SCANINFO;

// A ship in transit (the old entry dictionary's "ship", "time" and "shipBeacon").
struct OOWormholeTransit {
    oo::ObjCRef<ShipEntity*> ship;
    double time; // arrival relative to the wormhole's arrival_time
    std::optional<std::string> beacon; // the ship's beacon code when it entered, if any
};

@interface WormholeEntity : Entity {
@private
    double expiry_time; // Time when wormhole entrance closes
    double travel_time; // Time taken for a ship to traverse the wormhole
    double arrival_time; // Time when wormhole exit opens
    double estimated_arrival_time; // Time when wormhole should open (be different to arrival_time for misjump wormholes)
    double scan_time; // Time when wormhole was scanned

    OOSystemID origin;
    OOSystemID destination;

    NSPoint originCoords; // May not equal our origin system if the wormhole opens from Interstellar Space
    NSPoint destinationCoords; // May not equal the destination system if the wormhole misjumps

    std::vector<OOWormholeTransit> shipsInTransit;

    double witch_mass;
    double shrink_factor; // used during nova mission
    // not used yet
    double exit_speed; // exit speed of ships in this wormhole

    WORMHOLE_SCANINFO scan_info;
    BOOL hasExitPosition;
    BOOL _misjump;
    GLfloat _misjumpRange;
    BOOL containsPlayer;
}

- (WormholeEntity*)initWithDict:(const oo::PList&)dict;
- (WormholeEntity*)initWormholeTo:(OOSystemID)s fromShip:(ShipEntity*)ship;

- (BOOL)suckInShip:(ShipEntity*)ship;
- (void)disgorgeShips;
- (void)setExitPosition:(HPVector)pos;

- (OOSystemID)origin;
- (OOSystemID)destination;
- (NSPoint)originCoordinates;
- (NSPoint)destinationCoordinates;

- (void)setMisjump; // Flags up a wormhole as 'misjumpy'
- (void)setMisjumpWithRange:(GLfloat)range; // Flags up a wormhole as 'misjumpy'
- (BOOL)withMisjump;
- (GLfloat)misjumpRange;

- (double)exitSpeed; // exit speed from this wormhole
- (void)setExitSpeed:(double)speed; // set exit speed from this wormhole

- (double)expiryTime; // Time at which the wormholes entrance closes
- (double)arrivalTime; // Time at which the wormholes exit opens
- (double)estimatedArrivalTime; // Time when wormhole should open (different from arrival_time for misjump wormholes)
- (double)travelTime; // Time needed for a ship to traverse the wormhole
- (double)scanTime; // Time when wormhole was scanned
- (void)setScannedAt:(double)time;
- (void)setContainsPlayer:(BOOL)val; // mark the wormhole as waiting for player exit

- (BOOL)isScanned; // True if the wormhole has been scanned by the player
- (WORMHOLE_SCANINFO)scanInfo; // Stage of scanning
- (void)setScanInfo:(WORMHOLE_SCANINFO)scanInfo;

- (oo::PList)shipsInTransit; // Dicts: "ship" (an Object node), "time", "shipBeacon" when set

- (id)identFromShip:(ShipEntity*)ship; // shared selector (proposed ADR-0043): an Objective-C string

- (oo::PList)getDict;

@end
