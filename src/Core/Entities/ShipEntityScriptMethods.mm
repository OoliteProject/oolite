/*

ShipEntityScriptMethods.m


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

#import "ShipEntityScriptMethods.h"
#import "Universe.h"
#include "oofnd/Log.hpp"

@implementation ShipEntity (ScriptMethods)

- (ShipEntity*)ejectShipOfType:(const std::optional<std::string>&)shipKey
{
    ShipEntity* item = nil;

    if (shipKey.has_value()) {
        item = [[UNIVERSE cxx_newShipWithName:*shipKey] autorelease];
        if (item != nil)
            [self dumpItem:item];
    }

    return item;
}

- (ShipEntity*)ejectShipOfRole:(const std::optional<std::string>&)role
{
    ShipEntity* item = nil;

    if (role.has_value()) {
        item = [[UNIVERSE cxx_newShipWithRole:*role] autorelease];
        if (item != nil)
            [self dumpItem:item];
    }

    return item;
}

- (std::vector<oo::ObjCRef<ShipEntity*>>)spawnShipsWithRole:(const std::string&)role count:(NSUInteger)count
{
    ShipEntity* ship = [self rootShipEntity]; // FIXME: (EMMSTRAN) implement an -absolutePosition method, use that in spawnShipWithRole:near:, and use self instead of root.
    ShipEntity* spawned = nil;
    std::vector<oo::ObjCRef<ShipEntity*>> result;

    if (count == 0)
        return result;

    OO_LOG("script.debug.note.addShips", "Spawning {} x '{}' near {} {}", count, role, oo::ShortDescriptionOf(self), [self universalID]);

    result.reserve(count);

    do {
        spawned = [UNIVERSE cxx_spawnShipWithRole:role near:ship];
        if (spawned != nil) {
            [spawned setTemperature:[self randomEjectaTemperature]];
            if ([self isMissileFlagSet] && [spawned cxx_shipInfoDictionary].get<bool>("is_submunition")) {
                [spawned setOwner:[self owner]];
                [spawned addTarget:[self primaryTarget]];
                [spawned setIsMissileFlag:YES];
            }
            if ([spawned isMine]) {
                [spawned setOwner:self];
            }
            result.emplace_back(spawned);
        }
    } while (--count);

    return result;
}

@end
