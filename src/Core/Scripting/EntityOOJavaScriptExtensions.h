/*

EntityOOJavaScriptExtensions.h (QuickJS-ng)

JavaScript support methods for entities.

The Entity and ShipEntity JavaScript extensions are the free functions below,
one per method, named after the class they extend and the selector's first
keyword. An entity's JS object holds the C++ entity (an OOJSEntityHolder,
OOJSEntity.h, in its private slot), and the functions that made and dropped it
take the C++ entity.

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

#include "Entity.h"
#include "OOJavaScriptEngine.h"

class ShipEntity;  // Entity extensions. The JS object's functions take the C++
                   // entity (Entity's
// JS glue members call them; the engine asks those members).
bool EntityJSIsVisibleToScripts(void);
std::optional<std::string> EntityJSClassName(void);
// The entity's JS object, owned by the caller (JS null for none).
JSValue EntityJSValueInContext(Entity* entity, JSContext* context);
// The JS class of the entity's wrapper object; subclasses override
// -oo_jsClassID.
JSClassID EntityJSClassID(void);
void EntityJSDeleteJSSelf(Entity* entity);
std::optional<std::string> EntityJSDescription(Entity* entity);

// The entity's answers to the class questions the engine asks about its object.
bool OOJSEntityIsVisibleToScripts(Entity* entity);
std::optional<std::string> OOJSEntityJSClassName(Entity* entity);
// The same for the JS class, and for the JS value (the entity's own JS object;
// null for no entity): what the engine asked an entity's object by
// -oo_jsClassID and -oo_jsValueInContext:. Entity's own class is
// EntityJSClassID(), ShipEntity's ShipEntityJSClassID().
JSClassID OOJSEntityJSClassID(Entity* entity);
// Owned by the caller.
JSValue OOJSEntityJSValue(Entity* entity, JSContext* context);

// ShipEntity (OOJavaScriptExtensions)
bool ShipEntityJSIsVisibleToScripts(void);
JSClassID ShipEntityJSClassID(void);
std::optional<std::string> ShipEntityJSClassName(void);
std::vector<oo::EntityHold> ShipEntityJSSubEntitiesForScript(ShipEntity* ship);
void ShipEntityJSSetTargetForScript(ShipEntity* ship, ShipEntity* target);
