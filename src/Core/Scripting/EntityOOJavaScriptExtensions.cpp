/*

EntityOOJavaScriptExtensions.m (QuickJS-ng)

The Entity and ShipEntity JavaScript extensions as free functions
(EntityOOJavaScriptExtensions.h). A method that used self takes the object as
its first parameter.

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

#include "EntityOOJavaScriptExtensions.h"

#include <format>

#include "DockEntity.h"
#include "OOJSDock.h"
#include "OOJSEntity.h"
#include "OOJSPrivateObject.h"
#include "OOJSShip.h"
#include "OOJSStation.h"
#include "OOJSVisualEffect.h"
#include "OOJSWormhole.h"
#include "OOPlanetEntity.h"
#include "OOVisualEffectEntity.h"
#include "StationEntity.h"
#include "WormholeEntity.h"
#include "oofnd/Notification.hpp"
#include "oofnd/String.hpp"

// MARK: Entity (OOJavaScriptExtensions)

bool EntityJSIsVisibleToScripts() { return false; }

std::optional<std::string> EntityJSClassName() { return std::string("Entity"); }

/*	The entity's JS object: made on first use for an entity that scripts can
   see, of the class the entity names, its private slot an
   OOJSEntityHolder (a weak reference to the entity: the JS object does not keep
   the entity alive), held by
        the entity while it lives and dropped when the engine
   resets.
*/
/*	The class questions about an entity's JS object, answered by the C++
   entity's members. Used by the engine's generic paths that ask an entity's
   object (OOJSSystem's planets filter, callObjC()'s class name).
*/

bool OOJSEntityIsVisibleToScripts(Entity* entity) {
  if (entity == nullptr) return false;  // nil's answer
  return entity->isVisibleToScripts();
}

std::optional<std::string> OOJSEntityJSClassName(Entity* entity) {
  if (entity == nullptr) return std::nullopt;  // nil's answer
  return entity->jsClassName();
}

JSClassID OOJSEntityJSClassID(Entity* entity) { return entity->jsClassID(); }

JSValue OOJSEntityJSValue(Entity* entity, JSContext* context) {
  if (entity == nullptr)
    return JS_NULL;  // OOJSValueFromNativeObject()'s for nil
  return entity->jsValueInContext(context);
}

JSValue EntityJSValueInContext(Entity* entity, JSContext* context) {
  if (!JS_IsObject(entity->_jsSelf) && OOJSEntityIsVisibleToScripts(entity)) {
    // Create JS object. The entity keeps a reference to it for as long as the
    // entity exists.
    JSValue jsSelf = JS_NewObjectClass(
        context, static_cast<int>(OOJSEntityJSClassID(entity)));
    if (JS_IsException(jsSelf)) {
      JS_FreeValue(context, JS_GetException(context));
    } else {
      const std::shared_ptr<OOJSEntityHolder> holder =
          oo::makeShared<OOJSEntityHolder>(entity);
      if (!OOJSSetCxxPrivate(jsSelf, holder.get())) {
        JS_FreeValue(context, jsSelf);
      } else {
        entity->_jsSelf = jsSelf;
        oo::NotificationCenter::defaultCenter().addObserver(
            entity, kOOJavaScriptEngineWillResetNotificationName,
            OOJavaScriptEngine::sharedEngine(),
            [entity](const oo::Notification&) { entity->deleteJSSelf(); });
      }
    }
  }

  if (JS_IsObject(entity->_jsSelf))
    return JS_DupValue(context, entity->_jsSelf);

  return JS_NULL;
}

JSClassID EntityJSClassID() { return JSEntityClassID(); }

void EntityJSDeleteJSSelf(Entity* entity) {
  if (JS_IsObject(entity->_jsSelf)) {
    /*	Scripts may still hold the JS object. Its private data is a weak
            reference, so it becomes stale (isValid false) when the entity is
            deallocated.
    */
    JS_FreeValue(OOJSAcquireContext(), entity->_jsSelf);
    entity->_jsSelf = JS_UNDEFINED;

    oo::NotificationCenter::defaultCenter().removeObserver(
        entity, kOOJavaScriptEngineWillResetNotificationName,
        OOJavaScriptEngine::sharedEngine());
  }
}

/*	The entity's JS description: "[<JS class name> <components>]", or
   "[object <JS class name>]" with no components; the JS class name is the
   entity's jsClassName(), else "Entity".
*/
std::optional<std::string> EntityJSDescription(Entity* entity) {
  if (entity == nullptr)
    return std::nullopt;  // (the holder asks only a live entity)
  std::optional<std::string> name = entity->jsClassName();
  if (!name.has_value()) name = std::string("Entity");  // the root class
  if (const std::optional<std::string> components =
          entity->descriptionComponents()) {
    return std::format("[{} {}]", *name, *components);
  }
  return std::format("[object {}]", *name);
}

// MARK: ShipEntity (OOJavaScriptExtensions)

bool ShipEntityJSIsVisibleToScripts() { return true; }

JSClassID ShipEntityJSClassID() { return JSShipClassID(); }

std::optional<std::string> ShipEntityJSClassName() {
  return std::string("Ship");
}

std::vector<oo::EntityHold> ShipEntityJSSubEntitiesForScript(ShipEntity* ship) {
  std::vector<oo::EntityHold> result;
  for (const auto& sub : (ship != nullptr ? ship->shipSubEntities()
                                          : std::vector<oo::EntityHold>())) {
    result.emplace_back(sub.get());
  }
  return result;
}

void ShipEntityJSSetTargetForScript(ShipEntity* ship, ShipEntity* target) {
  ShipEntity* me = ship;

  // Ensure coherence by not fiddling with subentities.
  while ((me != nullptr ? me->getIsSubEntity() : false)) {
    if (me == oo::ToShip((me != nullptr ? me->owner() : nullptr)) ||
        (me != nullptr ? me->owner() : nullptr) == nullptr)
      break;  // its own object: the ship, not its object
    me = oo::ToShip((me != nullptr ? me->owner() : nullptr));
  }
  while ((target != nullptr ? target->getIsSubEntity() : false)) {
    if (target == oo::ToShip((target != nullptr ? target->owner() : nullptr)) ||
        (target != nullptr ? target->owner() : nullptr) == nullptr)
      break;  // its own object: the ship, not its object
    target = oo::ToShip((target != nullptr ? target->owner() : nullptr));
  }
  if (me == nullptr) return;  // not a ship
  if (target != nullptr) {
    if (me != nullptr) me->addTarget(target);
  } else {
    if (me != nullptr)
      me->removeTarget((me != nullptr ? me->primaryTarget()
                                      : static_cast<Entity*>(nullptr)));
  }
}
