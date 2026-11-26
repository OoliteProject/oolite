/*

WormholeEntity+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, amendments oo-bj8 and oo-0mxi): the Objective-C WormholeEntity,
the facade of a converted leaf entity over the C++ cxx::WormholeEntity (WormholeEntity.h), kept
because the player and the ships make it ([[WormholeEntity alloc] initWormholeTo:fromShip:],
-initWithDict:) and keep it, and the player, the ships, the universe, the HUD, the debug monitor
and the scripting bindings message it by its own selectors. Its interface is the one
WormholeEntity.h declared before the conversion, copied exactly, and it has no ivars: the root's
_cxxEntity holds its C++ part. Imported as the last line of WormholeEntity.h; do not import it
directly. Never add to this file. Deleted by its deletion bead once its callers are C++.

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

#ifndef WORMHOLEENTITY_OBJCBRIDGE_H
#define WORMHOLEENTITY_OBJCBRIDGE_H

@interface WormholeEntity : Entity

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

- (std::optional<std::string>)identFromShip:(ShipEntity*)ship; // flipped with its family (bead oo-3rb.279)

- (oo::PList)getDict;

@end

namespace oo {

// The root's crossings, typed (amendment oo-up4b item 3).
inline cxx::WormholeEntity* ToCxx(::WormholeEntity* entity)
{
    return static_cast<cxx::WormholeEntity*>(ToCxx(static_cast<::Entity*>(entity)));
}
inline ::WormholeEntity* ToObjC(cxx::WormholeEntity* entity)
{
    return (::WormholeEntity*)ToObjC(static_cast<cxx::Entity*>(entity));
}

} // namespace oo

#endif // WORMHOLEENTITY_OBJCBRIDGE_H
