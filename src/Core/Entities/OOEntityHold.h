/*

OOEntityHold.h

How the universe and the entities' own lists (sub-entities, cargo, colliding entities, the player's
missiles, ...) own an entity (ADR-0056 amendments oo-9ht.39.26, oo-xn1j1). Until the root facade's
deletion the holder retained the entity's Objective-C object, which owned the C++ entity; since bead
oo-dpyk8 (oo-9ht.39 step 5k.4) the C++ entity owns itself (oo::RefCounted, its last release running
what the facade's -dealloc ran) and the holder is a strong reference to it, with the same counts.

An entity that has no object (Entity::hasObject(): never made by a creator, or in its last
release) is held as null, as a reference to oo::ToObjC()'s nil was; the retain/release helpers do
nothing for it, as the messages to nil did.

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

#ifndef OO_ENTITY_HOLD_H
#define OO_ENTITY_HOLD_H

#include "oofnd/Ref.hpp"

#include <cstddef>
#include <utility>

class Entity;


namespace oo {

namespace detail {

// EntityHelpers.mm (a narrow test's stand-in defines its own): a retain or release of an entity that
// has its object, nothing otherwise; whether it has one.
bool EntityHasObject(const Entity *entity) noexcept;
void EntityRetain(Entity *entity) noexcept;
void EntityRelease(Entity *entity) noexcept;

}	// namespace detail


/*	An owning reference to an entity (oo::Ref<Entity> with the facade's rule for an entity
	without its object: held as null). Copying retains, destroying releases, moving steals.
*/
class EntityHold
{
public:
	EntityHold() noexcept = default;
	EntityHold(std::nullptr_t) noexcept {}
	explicit EntityHold(Entity *entity) noexcept : _entity(detail::EntityHasObject(entity) ? entity : nullptr)  { detail::EntityRetain(_entity); }
	EntityHold(const EntityHold &other) noexcept : _entity(other._entity)  { detail::EntityRetain(_entity); }
	EntityHold(EntityHold &&other) noexcept : _entity(std::exchange(other._entity, nullptr)) {}
	~EntityHold()  { detail::EntityRelease(_entity); }

	EntityHold &operator=(const EntityHold &other) noexcept
	{
		EntityHold(other).swap(*this);
		return *this;
	}
	EntityHold &operator=(EntityHold &&other) noexcept
	{
		EntityHold(std::move(other)).swap(*this);
		return *this;
	}
	void swap(EntityHold &other) noexcept  { std::swap(_entity, other._entity); }

	// Takes over a +1 reference to the entity (oo::RetainEntity()'s; what oo::adoptObjC(oo::ToObjC(entity))
	// held, bead oo-xn1j1). Null, and nothing taken, for an entity without its object, as nil was.
	static EntityHold adopt(Entity *entity) noexcept
	{
		EntityHold result;
		if (detail::EntityHasObject(entity))  result._entity = entity;
		return result;
	}

	// Drops the reference without a release (the deliberate leaks; bead oo-xn1j1). Null afterwards.
	void leak() noexcept  { _entity = nullptr; }

	Entity *get() const noexcept  { return _entity; }
	Entity *operator->() const noexcept  { return _entity; }
	explicit operator bool() const noexcept  { return _entity != nullptr; }

	friend bool operator==(const EntityHold &a, const EntityHold &b) noexcept  { return a._entity == b._entity; }
	friend bool operator==(const EntityHold &a, const Entity *b) noexcept  { return a._entity == b; }

private:
	Entity	*_entity = nullptr;
};


/*	The universe's +1 creators and the references the universe and the entities keep by hand
	(EntityHelpers.mm): what -retain, -release and -autorelease of the entity's object did, on the
	entity's own count (-autorelease hands the reference to the innermost oo::AutoreleaseScope,
	oo::autorelease(), so it is released at the same drain, in the same order); nothing for
	null or an entity without its object. RetainEntity() and AutoreleaseEntity() answer their argument.
*/
Entity *RetainEntity(Entity *entity);
void ReleaseEntity(Entity *entity);
Entity *AutoreleaseEntity(Entity *entity);

/*	A C++ entity just made, given its object, as the creators made it (oo::NewEntityFacade(), +1 and
	autoreleased): from here it has its object, it is counted as a live entity, and the pool holds one
	reference until it drains. Answers the entity (null for null). Call it once, where it is made.
*/
Entity *MadeEntity(const Ref<Entity> &entity);

/*	The same without the autorelease: the creators that answered +1 (oo::NewShipObject(),
	oo::NewVisualEffectObject(): +alloc's object). The caller owns the +1.
*/
Entity *MadeEntityRetained(const Ref<Entity> &entity);

}	// namespace oo

#endif	// OO_ENTITY_HOLD_H
