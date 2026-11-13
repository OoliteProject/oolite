/*

OOEntityHold.h

How the universe and the entities' own lists (sub-entities, cargo, colliding
entities, the player's missiles, ...) own an entity. The C++ entity owns itself
(oo::RefCounted, its last release running willDispose()) and the holder is a
strong reference to it.

An entity that has no object (Entity::hasObject(): never made by a creator, or
in its last release) is held as null; the retain/release helpers do nothing for
it.

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

#include <algorithm>
#include <cstddef>
#include <memory>
#include <utility>
#include <vector>

#include "oofnd/Ref.hpp"

class Entity;

namespace oo {

namespace detail {

// EntityHelpers.cpp (a narrow test's stand-in defines its own): a retain or
// release of an entity that has its object, nothing otherwise; whether it has
// one.
bool EntityHasObject(const Entity* entity) noexcept;
void EntityRetain(Entity* entity) noexcept;
void EntityRelease(Entity* entity) noexcept;

}  // namespace detail

/*	The universe's +1 creators and the references the universe and the
   entities keep by hand (EntityHelpers.cpp): what -retain, -release and
   -autorelease of the entity's object did, on the entity's own count
   (-autorelease hands the reference to the innermost oo::AutoreleaseScope,
        oo::autorelease(), so it is released at the same drain, in the same
   order); nothing for null or an entity without its object. RetainEntity() and
   AutoreleaseEntity() answer their argument.
*/
Entity* RetainEntity(Entity* entity);
void ReleaseEntity(Entity* entity);
Entity* AutoreleaseEntity(Entity* entity);

// An owning reference to an entity; an entity without its object is held as
// null.
using EntityHold = std::shared_ptr<Entity>;

// An owning reference to e if it has its object (Entity::hasObject()), else
// null: what EntityHold(raw) did. (A template so that it is instantiated where
// the entity's class is complete.)
template <class E>
std::shared_ptr<E> Hold(E* e) {
  return (e != nullptr && detail::EntityHasObject(e)) ? oo::share(e) : nullptr;
}

// Takes over a +1 reference to the entity (oo::RetainEntity()'s): its owning
// reference, the +1 given back. Null, and nothing taken, for an entity without
// its object. (The manual references leave with the bridge, T095.)
template <class E>
std::shared_ptr<E> AdoptHold(E* e) {
  std::shared_ptr<E> hold = Hold(e);
  if (hold != nullptr) ReleaseEntity(e);
  return hold;
}

// The entity with a +1 its caller gives back (oo::ReleaseEntity()): what the
// +1 creators answered before they answered a std::shared_ptr. (Leaves with
// the manual references, T095.)
template <class E>
E* RetainedEntity(const std::shared_ptr<E>& entity) {
  (void)RetainEntity(entity.get());
  return entity.get();
}

// The first hold of entity in holds (by the entity; holds.end() for none), and
// every hold of it removed (the count): what finding and removing the object
// in the array did.
inline std::vector<EntityHold>::iterator FindHold(
    std::vector<EntityHold>& holds, const Entity* entity) noexcept {
  return std::ranges::find(holds, entity,
                           [](const EntityHold& hold) { return hold.get(); });
}

inline std::size_t EraseHold(std::vector<EntityHold>& holds,
                             const Entity* entity) {
  return std::erase_if(
      holds, [entity](const EntityHold& hold) { return hold.get() == entity; });
}

// Drops the reference without a release (the deliberate leaks): the entity
// keeps a +1 that is never given back. Null afterwards.
inline void LeakHold(EntityHold& hold) {
  (void)RetainEntity(hold.get());
  hold.reset();
}

/*	A C++ entity just made, given its object, as the creators make it (+1
   and autoreleased): from here it has its object, it is counted as a live
   entity, and the pool holds one reference until it drains. Answers the entity
   (null for null). Call it once, where it is made.
*/
Entity* MadeEntity(const Ref<Entity>& entity);

/*	The same without the autorelease: the creators that answered +1
   (oo::NewShipObject(), oo::NewVisualEffectObject(): +alloc's object). The
   caller owns the +1.
*/
std::shared_ptr<Entity> MadeEntityRetained(const Ref<Entity>& entity);

}  // namespace oo
