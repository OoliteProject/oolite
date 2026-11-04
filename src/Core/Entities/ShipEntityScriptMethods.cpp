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

#include "ShipEntityScriptMethods.h"

#include "Universe.h"
#include "oofnd/Log.hpp"

/*	The ShipEntity (ScriptMethods) members.
 */

::ShipEntity* ShipEntity::ejectShipOfType(
    const std::optional<std::string>& shipKey) {
  ::ShipEntity* item = nullptr;

  if (shipKey.has_value()) {
    item = oo::ToShip(oo::AutoreleaseEntity(
        (UNIVERSE != nullptr ? UNIVERSE->newShipWithName(*shipKey)
                             : (::ShipEntity*)nullptr)));
    if (item != nullptr) dumpItem(item);
  }

  return item;
}

::ShipEntity* ShipEntity::ejectShipOfRole(
    const std::optional<std::string>& role) {
  ::ShipEntity* item = nullptr;

  if (role.has_value()) {
    item = oo::ToShip(oo::AutoreleaseEntity(
        (UNIVERSE != nullptr ? UNIVERSE->newShipWithRole(*role)
                             : (::ShipEntity*)nullptr)));
    if (item != nullptr) dumpItem(item);
  }

  return item;
}

std::vector<oo::EntityHold> ShipEntity::spawnShipsWithRole(
    const std::string& role, NSUInteger count) {
  ::ShipEntity* ship = oo::ToShip(
      rootShipEntity());  // FIXME: (EMMSTRAN) implement an -absolutePosition
                          // method, use that in spawnShipWithRole:near:, and
                          // use self instead of root.
  ::ShipEntity* spawned = nullptr;
  std::vector<oo::EntityHold> result;

  if (count == 0) return result;

  OO_LOG("script.debug.note.addShips", "Spawning {} x '{}' near {} {}", count,
         role, oo::EntityShortDescription(this), getUniversalID());

  result.reserve(count);

  do {
    spawned = (UNIVERSE != nullptr ? UNIVERSE->spawnShipWithRole(role, ship)
                                   : (::ShipEntity*)nullptr);
    if (spawned != nullptr) {
      if (spawned != nullptr)
        spawned->setTemperature(randomEjectaTemperature());
      if (isMissileFlagSet() &&
          (spawned != nullptr ? spawned->shipInfoDictionary() : oo::PList())
              .get<bool>("is_submunition")) {
        if (spawned != nullptr)
          spawned->setOwner(ownerEntity());  // owner()'s C++ entity
        if (spawned != nullptr) spawned->addTarget(primaryTarget());
        if (spawned != nullptr) spawned->setIsMissileFlag(true);
      }
      if ((spawned != nullptr ? spawned->isMine() : false)) {
        if (spawned != nullptr) spawned->setOwner(this);
      }
      result.emplace_back(spawned);
    }
  } while (--count);

  return result;
}
