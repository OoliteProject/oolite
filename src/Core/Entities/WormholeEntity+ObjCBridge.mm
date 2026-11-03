/*

WormholeEntity+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, amendments oo-bj8 and oo-0mxi): the Objective-C WormholeEntity
facade (see WormholeEntity+ObjCBridge.h). Deleted with WormholeEntity+ObjCBridge.h.

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

#import "OOJSWormhole.h"
#import "WormholeEntity.h"

@implementation WormholeEntity

/*	[[WormholeEntity alloc] initWithDict:] and -initWormholeTo:fromShip: (the player and the ships):
        a C++ wormhole, then the initialiser's body (amendment oo-0mxi item 2). Sent again, it keeps its
        C++ part and runs the body again, as the Objective-C initialiser did.
*/
- (WormholeEntity*)initWithDict:(const oo::PList&)dict
{
    if (_cxxEntity != nullptr)
        self = [super initWithCxxEntity:_cxxEntity.get()];
    else
        self = [super initWithCxxEntity:oo::makeRef<cxx::WormholeEntity>().get()];
    if (self != nil)
        oo::ToCxx(self)->initWithDict(dict);
    return self;
}

- (WormholeEntity*)initWormholeTo:(OOSystemID)s fromShip:(ShipEntity*)ship
{
    if (_cxxEntity != nullptr)
        self = [super initWithCxxEntity:_cxxEntity.get()];
    else
        self = [super initWithCxxEntity:oo::makeRef<cxx::WormholeEntity>().get()];
    if (self != nil)
        oo::ToCxx(self)->initWormholeTo(s, ship);
    return self;
}

- (BOOL)suckInShip:(ShipEntity*)ship
{
    return oo::ToCxx(self)->suckInShip(ship);
}
- (void)disgorgeShips
{
    oo::ToCxx(self)->disgorgeShips();
}
- (void)setExitPosition:(HPVector)pos
{
    oo::ToCxx(self)->setExitPosition(pos);
}
- (OOSystemID)origin
{
    return oo::ToCxx(self)->getOrigin();
}
- (OOSystemID)destination
{
    return oo::ToCxx(self)->getDestination();
}
- (NSPoint)originCoordinates
{
    return oo::ToCxx(self)->originCoordinates();
}
- (NSPoint)destinationCoordinates
{
    return oo::ToCxx(self)->destinationCoordinates();
}
- (void)setMisjump
{
    oo::ToCxx(self)->setMisjump();
}
- (void)setMisjumpWithRange:(GLfloat)range
{
    oo::ToCxx(self)->setMisjumpWithRange(range);
}
- (BOOL)withMisjump
{
    return oo::ToCxx(self)->withMisjump();
}
- (GLfloat)misjumpRange
{
    return oo::ToCxx(self)->misjumpRange();
}
- (double)exitSpeed
{
    return oo::ToCxx(self)->exitSpeed();
}
- (void)setExitSpeed:(double)speed
{
    oo::ToCxx(self)->setExitSpeed(speed);
}
- (double)expiryTime
{
    return oo::ToCxx(self)->expiryTime();
}
- (double)arrivalTime
{
    return oo::ToCxx(self)->arrivalTime();
}
- (double)estimatedArrivalTime
{
    return oo::ToCxx(self)->estimatedArrivalTime();
}
- (double)travelTime
{
    return oo::ToCxx(self)->travelTime();
}
- (double)scanTime
{
    return oo::ToCxx(self)->scanTime();
}
- (void)setScannedAt:(double)time
{
    oo::ToCxx(self)->setScannedAt(time);
}
- (void)setContainsPlayer:(BOOL)val
{
    oo::ToCxx(self)->setContainsPlayer(val);
}
- (BOOL)isScanned
{
    return oo::ToCxx(self)->isScanned();
}
- (WORMHOLE_SCANINFO)scanInfo
{
    return oo::ToCxx(self)->scanInfo();
}
- (void)setScanInfo:(WORMHOLE_SCANINFO)scanInfo
{
    oo::ToCxx(self)->setScanInfo(scanInfo);
}
- (oo::PList)shipsInTransit
{
    return oo::ToCxx(self)->getShipsInTransit();
}
- (std::optional<std::string>)identFromShip:(ShipEntity*)ship
{
    return oo::ToCxx(self)->identFromShip(ship);
}
- (oo::PList)getDict
{
    return oo::ToCxx(self)->getDict();
}

// The JS side, which the engine asks for by selector (Entity (OOJavaScriptExtensions)): the
// binding's category, moved here from the binding's bridge file, which it deletes (bead oo-9ht.43;
// ADR-0056 amendment oo-6ia4 item 3). Each forwards to the OOJSWormhole.mm function that holds its
// old body; they become members of the C++ class with this facade's deletion (oo-9ht.112).
- (JSClassID)oo_jsClassID
{
    return ::JSWormholeClassID();
}
- (std::optional<std::string>)cxx_oo_jsClassName
{
    return ::OOJSWormholeJSClassName();
}
- (BOOL)isVisibleToScripts
{
    return ::OOJSWormholeIsVisibleToScripts();
}

@end
