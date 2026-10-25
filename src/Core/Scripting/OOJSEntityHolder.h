/*

OOJSEntityHolder.h

What an entity's JS object holds in its private slot (bead oo-9ht.39.3, proposed ADR-0056 amendment
oo-9ht.39.3, which applies amendment oo-6symp to the entities): a weak reference to the C++
entity. The slot held the root facade's weak reference proxy until then, so the JS object
did not keep the entity alive and read as a stale reference (nil) once it had gone; the holder
does the same with oo::WeakRef. The slot retains the holder (OOJSSetCxxPrivate) and the finalizer
releases it (OOJSCxxObjectWrapperFinalize). EntityJSValueInContext() makes one per JS object.

Include it after Entity's definition (Entity.h; a test's stand-in): oo::WeakRef needs the
complete class. The JS glue members are defined in OOJSEntity.mm (a narrow test that links a
binding without it defines them as stand-ins).

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

#ifndef OOJSENTITYHOLDER_H
#define OOJSENTITYHOLDER_H

#include "OOJSPrivateObject.h"
#include "oofnd/Ref.hpp"


class OOJSEntityHolder final : public oo::RefCounted, public OOJSPrivateObject
{
public:
	explicit OOJSEntityHolder(Entity *entity) : _entity(entity) {}

	// The entity, borrowed; null once it has gone (what the weak reference proxy's underlying object was: nil).
	Entity *entity() const  { return _entity.get(); }

	// The entity's own glue, as the engine sent its selectors to the slot's weak reference, which
	// forwarded them to the facade: its JS value, nothing on finalization (OOObject's
	// -oo_clearJSSelf:), its description; null, nothing and nullopt once it has gone.
	ooscript::Value jsValueInContext(ooscript::Context context) override;
	void clearJSSelf(ooscript::Object selfVal) override;
	std::optional<std::string> jsDescription() override;

private:
	oo::WeakRef<Entity>	_entity;
};

#endif	// OOJSENTITYHOLDER_H
