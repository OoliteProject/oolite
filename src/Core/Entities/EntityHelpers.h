/*

EntityHelpers.h

The questions asked of an entity's object, answered by the C++ entity, and the
entity's property-list node. Imported as the last line of Entity.h; do not
import it directly.

An entity "has its object" (Entity::hasObject()) from the creator that made it
until its last release begins. For an entity without one, these answer nil, NO
or nothing.

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

#include <optional>
#include <string>
#include <vector>

#include "Entity.h"  // also includes this file at its end; the guard above makes either order work
#include "EntityPListForeign.h"  // the entity's node, and whether it has its object
#include "OOEntityHold.h"
#include "oofnd/PList.hpp"

class OOHUDBeaconIcon;  // OOPolygonSprite.h

namespace oo {

/*	The entity's short description: "<Entity
   0x...>" (no components);
   "(null)" for null and for an entity without its object. callObjC()'s "does
   not respond" error prints it. The address is the C++ entity's.
*/
std::string EntityShortDescription(Entity* entity);

// The Mac debug OXP's -inspect, sent by the console to an entity that answered
// it: the entity's virtual inspect() (empty unless a class overrides it);
// nothing for null or an entity without its object.
void InspectEntity(Entity* entity);

// The entity's description: "<C++ class
// 0x...>{components}"; "(null)" as above. The address is the C++ entity's.
std::string EntityDescription(Entity* entity);

// The same, whether or not the entity has its object: its last release's log
// line, which describes itself.
std::string EntityOwnDescription(Entity* entity);

/*	The size the live-entity memory count and the debug monitor's dump add
   up for an entity's object: three pointers.
*/
inline size_t EntityObjectSize(Entity*) { return 3 * sizeof(void*); }

// The live C++ entity a weak reference reads: null once it has gone, and for an
// entity without its object.
inline Entity* LiveEntity(const std::weak_ptr<Entity>& ref) {
  return WithObject(ref.lock().get());
}

// The entity's owner, null for none or once it has gone (Entity::owner()).
inline Entity* LiveOwner(Entity* entity) {
  return entity != nullptr ? entity->owner() : nullptr;
}

// For an initialised entity (PlayerEntity's deferred initialisation): init()
// runs again over the same entity, which is counted again. Answers the entity.
Entity* EntityInitAgain(Entity* entity);

// The class name "%@" and the debug dumps print: the C++ class's name ("cxx::"
// dropped).
std::string EntityClassName(Entity* entity);

/*	The ship, sub-entity, player, planet and status questions: the C++
   member each forwards to; nil's answer for none.
*/
inline bool EntityIsShip(Entity* entity) {
  return entity != nullptr && entity->getIsShip();
}
inline bool EntityIsSubEntity(Entity* entity) {
  return entity != nullptr && entity->getIsSubEntity();
}
inline bool EntityIsPlayer(Entity* entity) {
  return entity != nullptr && entity->getIsPlayer();
}
inline bool EntityIsPlanet(Entity* entity) {
  return entity != nullptr && entity->isPlanet();
}
inline OOEntityStatus EntityStatus(Entity* entity) {
  return entity != nullptr ? entity->status() : OOEntityStatus{};
}

// What the category SubEntityRelationship's -isShipWithSubEntityShip: answered:
// the ship's or the visual effect's member, NO for anything
// else (and for none).
bool EntityIsShipWithSubEntityShip(Entity* entity, Entity* other);

// Whether the entity is a beacon: the ship's,
// effect's or waypoint's member, NO for anything else.
bool EntityIsBeacon(Entity* entity);

/*	The beacon list's links and code: answered with the ship's, the visual
   effect's or the waypoint's member (asked of those members directly); nil's
   answer, and nothing, for none, for an entity without its object, and for any
   other entity.
*/
Entity* PrevBeacon(Entity* beacon);
Entity* NextBeacon(Entity* beacon);
void SetPrevBeacon(Entity* beacon, Entity* other);
void SetNextBeacon(Entity* beacon, Entity* other);
std::optional<std::string> BeaconCode(Entity* beacon);
void SetBeaconCode(Entity* beacon, const std::optional<std::string>& code);
OOComparisonResult CompareBeaconCodes(Entity* beacon, Entity* other);
bool BeaconIsJammingScanning(Entity* beacon);            // -isJammingScanning
OOHUDBeaconIcon* BeaconDrawable(Entity* beacon);         // -beaconDrawable
std::optional<std::string> BeaconLabel(Entity* beacon);  // -beaconLabel

}  // namespace oo
