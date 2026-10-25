/*

EntityHelpers.h

What the root entity facade's deletion (bead oo-dpyk8, oo-9ht.39 step 5k.4; proposed ADR-0056
amendment oo-dpyk8) kept of Entity+ObjCBridge.h: the questions the facade's methods and categories
answered for an entity's object, asked of the C++ entity, and the entity's property-list node.
Imported as the last line of Entity.h; do not import it directly.

An entity "has its object" (Entity::hasObject()) from the creator that made its facade until
its last release begins: what oo::ToObjC() answering non-nil was. Where an answer was nil's for an
entity without one, these answer as nil did.

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

#ifndef ENTITY_HELPERS_H
#define ENTITY_HELPERS_H

#include "oofnd/PList.hpp"
#include "OOEntityHold.h"
#include "EntityPListForeign.h"	// the entity's node, and whether it has its object

#include <optional>
#include <string>
#include <vector>

class OOHUDBeaconIcon;	// OOPolygonSprite.h


namespace oo {

/*	What oo::ShortDescriptionOf() of the entity's object printed: "<Entity 0x...>" (the facade's class,
	the short description has no components); "(null)" for null and for an entity without its object.
	callObjC()'s "does not respond" error prints it. The address is the C++ entity's (bead oo-dpyk8;
	it was the object's).
*/
std::string EntityShortDescription(Entity *entity);

// The Mac debug OXP's -inspect, sent by the console to an entity that answered it: the entity's
// virtual inspect() (empty unless a class overrides it); nothing for null or an entity without its
// object (bead oo-dpyk8).
void InspectEntity(Entity *entity);

// What oo::DescriptionOf() of the entity's object printed: "<C++ class 0x...>{components}"; "(null)"
// as above. The address is the C++ entity's (bead oo-dpyk8; it was the object's).
std::string EntityDescription(Entity *entity);

// The same, whether or not the entity has its object: its last release's log line, which the
// facade's -dealloc wrote describing itself (bead oo-dpyk8).
std::string EntityOwnDescription(Entity *entity);

/*	What the root's debug size method answered for an entity's object, which the live-entity
	memory count and the debug monitor's dump add up: the root facade's instance size (isa, the weak-reference root's weakSelf and
	its reference to the C++ entity; every entity's object was of the root facade's class). Kept as that
	size, so the debug output is unchanged (bead oo-dpyk8; oo-6e1.1 may make it the C++ entity's).
*/
inline size_t EntityObjectSize(Entity *)  { return 3 * sizeof(void *); }

// The live C++ entity a weak reference reads (what oo::WeakEntityObject() of it, +0, answered the
// part of): null once it has gone, and for an entity without its object.
inline Entity *LiveEntity(const WeakRef<Entity> &ref)  { return WithObject(ref.get()); }

// The entity's owner, null for none or once it has gone (Entity::owner()).
inline Entity *LiveOwner(Entity *entity)  { return entity != nullptr ? entity->owner() : nullptr; }

// The facade's -initWithCxxEntity: sent to an initialised entity (PlayerEntity's deferred
// initialisation): the -init body runs again over the same entity, which is counted again, as the
// facade counted it (bead oo-dpyk8). Answers the entity.
Entity *EntityInitAgain(Entity *entity);

// The class name "%@" and the debug dumps print: the C++ class's name ("cxx::" dropped).
std::string EntityClassName(Entity *entity);

/*	What the root facade's -isShip, -isSubEntity, -isPlayer, -isPlanet and -status answered for an
	entity's object (bead oo-9ht.39.16): the C++ member each forwarded to; nil's answer for none.
*/
inline bool EntityIsShip(Entity *entity)		{ return entity != nullptr && entity->getIsShip(); }
inline bool EntityIsSubEntity(Entity *entity)	{ return entity != nullptr && entity->getIsSubEntity(); }
inline bool EntityIsPlayer(Entity *entity)		{ return entity != nullptr && entity->getIsPlayer(); }
inline bool EntityIsPlanet(Entity *entity)		{ return entity != nullptr && entity->isPlanet(); }
inline OOEntityStatus EntityStatus(Entity *entity)	{ return entity != nullptr ? entity->status() : OOEntityStatus{}; }

// What the category SubEntityRelationship's -isShipWithSubEntityShip: answered (bead oo-w9pi2): the
// ship's or the visual effect's member, NO for anything else (and for none).
bool EntityIsShipWithSubEntityShip(Entity *entity, Entity *other);

// What the facade's -isBeacon answered (bead oo-9ht.39.26): the ship's, effect's or waypoint's
// member, NO for anything else.
bool EntityIsBeacon(Entity *entity);

/*	The beacon list's links and code (bead oo-9ht.39.26): what the protocol's messages to the entities'
	objects answered and did, the facade's category answering them with the ship's, the visual
	effect's or the waypoint's member (bead oo-dpyk8: asked of those members directly); nil's answer,
	and nothing, for none, for an entity without its object, and for any other entity.
*/
Entity *PrevBeacon(Entity *beacon);
Entity *NextBeacon(Entity *beacon);
void SetPrevBeacon(Entity *beacon, Entity *other);
void SetNextBeacon(Entity *beacon, Entity *other);
std::optional<std::string> BeaconCode(Entity *beacon);
void SetBeaconCode(Entity *beacon, const std::optional<std::string> &code);
OOComparisonResult CompareBeaconCodes(Entity *beacon, Entity *other);
bool BeaconIsJammingScanning(Entity *beacon);			// -isJammingScanning (bead oo-9ht.39.18)
OOHUDBeaconIcon *BeaconDrawable(Entity *beacon);		// -beaconDrawable (bead oo-w9pi2)
std::optional<std::string> BeaconLabel(Entity *beacon);	// -beaconLabel (bead oo-w9pi2)

}	// namespace oo

#endif	// ENTITY_HELPERS_H
