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

/*	The category ShipEntity (ScriptMethods), bead oo-42dr: members of ShipEntity (ADR-0056
        amendments oo-o89 item 4 and oo-9fwb), forwarded by the category of the same name in
        ShipEntity+ObjCBridge.mm until bead oo-9ht.144 deleted the facade and its sends became member
        calls.
*/

::ShipEntity* ShipEntity::ejectShipOfType(const std::optional<std::string>& shipKey)
{
    ::ShipEntity* item = nil;

    if (shipKey.has_value()) {
        item = oo::ToShip([oo::ToObjC([UNIVERSE cxx_newShipWithName:*shipKey]) autorelease]);
        if (item != nil)
            dumpItem(item);
    }

    return item;
}

::ShipEntity* ShipEntity::ejectShipOfRole(const std::optional<std::string>& role)
{
    ::ShipEntity* item = nil;

    if (role.has_value()) {
        item = oo::ToShip([oo::ToObjC([UNIVERSE cxx_newShipWithRole:*role]) autorelease]);
        if (item != nil)
            dumpItem(item);
    }

    return item;
}

std::vector<oo::ObjCRef<::Entity*>> ShipEntity::spawnShipsWithRole(const std::string& role, NSUInteger count)
{
    ::ShipEntity* ship = oo::ToShip(rootShipEntity()); // FIXME: (EMMSTRAN) implement an -absolutePosition method, use that in spawnShipWithRole:near:, and use self instead of root.
    ::ShipEntity* spawned = nil;
    std::vector<oo::ObjCRef<::Entity*>> result;

    if (count == 0)
        return result;

    OO_LOG("script.debug.note.addShips", "Spawning {} x '{}' near {} {}", count, role, oo::ShortDescriptionOf(oo::ToObjC(this)), getUniversalID());

    result.reserve(count);

    do {
        spawned = [UNIVERSE cxx_spawnShipWithRole:role near:oo::ToObjC(ship)];
        if (spawned != nil) {
            if (spawned != nullptr)
                spawned->setTemperature(randomEjectaTemperature());
            if (isMissileFlagSet() && (spawned != nullptr ? spawned->shipInfoDictionary() : oo::PList()).get<bool>("is_submunition")) {
                if (spawned != nullptr)
                    spawned->setOwner(oo::ToCxx((::Entity*)owner()));
                if (spawned != nullptr)
                    spawned->addTarget(primaryTarget());
                if (spawned != nullptr)
                    spawned->setIsMissileFlag(YES);
            }
            if ((spawned != nullptr ? spawned->isMine() : false)) {
                if (spawned != nullptr)
                    spawned->setOwner(this);
            }
            result.emplace_back(oo::ToObjC(spawned));
        }
    } while (--count);

    return result;
}
