/*

EntityPListForeign.h

The entity's property-list node (bead oo-dpyk8; EntityHelpers.h, which imports this, has the rest):
an Object node that holds the entity, and the questions that make, read and list such nodes, with
whether an entity has its object. Needs only the class's name, so a narrow test whose stand-in is
its own Entity can carry its entities in nodes as the game does.

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

#ifndef ENTITY_PLIST_FOREIGN_H
#define ENTITY_PLIST_FOREIGN_H

#include "oofnd/PList.hpp"
#include "oofnd/Ref.hpp"
#include "OOEntityHold.h"

#include <string>
#include <vector>

class Entity;


namespace oo {

// The entity, where it has its object (what oo::ToObjC() answering non-nil was); else null.
Entity *WithObject(Entity *entity);	// EntityHelpers.mm (out of line: a narrow test's stand-in entity answers it)


/*	An entity carried through plist data as a PList::Object node (bead oo-9ht.39.5.3): the node holds
	the entity (it held the entity's object, which owned the entity, so the node keeps the entity
	alive as before) and answers it. Its class name is the facade's ("Entity"), its description the
	entity's (oo::EntityDescription()), its JS value the entity's (OOJSValueFromPList).
*/
std::string EntityDescription(Entity *entity);	// EntityHelpers.mm

class EntityPListForeign final : public PListForeign
{
public:
	explicit EntityPListForeign(Entity *entity) : _entity(entity) {}
	Entity *entity() const noexcept  { return _entity.get(); }
	std::string className() const override  { return "Entity"; }
	std::string description() const override  { return EntityDescription(_entity.get()); }

private:
	EntityHold	_entity;
};

// The entity's Object node (what PListObject(ToObjC(entity)) made); a null PList for null and for an
// entity without its object.
inline PList EntityObjectNode(Entity *entity)
{
	if (WithObject(entity) == nullptr)  return PList();
	return PList(PList::Object(makeRef<EntityPListForeign>(entity)));
}
inline PList EntityObjectNode(const Ref<Entity> &entity)  { return EntityObjectNode(entity.get()); }


// The C++ entity of an entity's Object node, borrowed; null for any other node.
inline Entity *EntityIn(const PList &plist)
{
	const PList::Object *node = plist.getIf<PList::Object>();
	if (node == nullptr)  return nullptr;
	const auto *payload = dynamic_cast<const EntityPListForeign *>(node->get());
	return payload != nullptr ? payload->entity() : nullptr;
}


// An array of held entities' Object nodes, one per non-null element, in order.
inline PList EntityNodesFrom(const std::vector<EntityHold> &entities)
{
	PList::Array result;
	result.reserve(entities.size());
	for (const EntityHold &entity : entities)
	{
		if (entity)  result.push_back(EntityObjectNode(entity.get()));
	}
	return PList(std::move(result));
}


// The C++ entities of an array's entity nodes, borrowed, in order; other elements are skipped.
inline std::vector<Entity *> EntitiesIn(const PList &plist)
{
	std::vector<Entity *> result;
	if (const PList::Array *array = plist.getIf<PList::Array>())
	{
		for (const PList &element : *array)
		{
			if (Entity *entity = EntityIn(element))  result.push_back(entity);
		}
	}
	return result;
}

}	// namespace oo

#endif	// ENTITY_PLIST_FOREIGN_H
