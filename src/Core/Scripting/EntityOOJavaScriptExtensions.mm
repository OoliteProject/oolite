/*

EntityOOJavaScriptExtensions.m (QuickJS-ng)

C++20 since bead oo-g223 (proposed ADR-0056, amendments oo-ppc and oo-ykoy): the bodies of the
categories Entity (OOJavaScriptExtensions) and ShipEntity (OOJavaScriptExtensions) as free
functions (EntityOOJavaScriptExtensions.h). A method that used self takes the object as its first
parameter, and its messages to the object stay messages: the categories are overridden by
subclasses that are still Objective-C. The categories' forwarders are in
EntityOOJavaScriptExtensions+ObjCBridge.mm.

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

#import "EntityOOJavaScriptExtensions.h"
#import "DockEntity.h"
#import "OOJSDock.h"
#import "OOJSEntity.h"
#import "OOJSShip.h"
#import "OOJSStation.h"
#import "OOJSVisualEffect.h"
#import "OOJSWormhole.h"
#import "OOPlanetEntity.h"
#import "StationEntity.h"
#import "WormholeEntity.h"
#include "oofnd/Notification.hpp"

// MARK: Entity (OOJavaScriptExtensions)

bool EntityJSIsVisibleToScripts(void)
{
    return false;
}

std::optional<std::string> EntityJSClassName(void)
{
    return std::string("Entity");
}

JSValue EntityJSValueInContext(Entity* entity, JSContext* context)
{
    if (!JS_IsObject(entity->_cxxEntity->_jsSelf) && [entity isVisibleToScripts]) {
        // Create JS object. The entity keeps a reference to it for as long as the entity exists.
        entity->_cxxEntity->_jsSelf = JS_NewObjectClass(context, (int)[entity oo_jsClassID]);
        if (JS_IsException(entity->_cxxEntity->_jsSelf)) {
            JS_FreeValue(context, JS_GetException(context));
            entity->_cxxEntity->_jsSelf = JS_UNDEFINED;
        } else {
            JS_SetOpaque(entity->_cxxEntity->_jsSelf, OOConsumeReference([entity weakRetain]));

            oo::NotificationCenter::defaultCenter().addObserver(entity, kOOJavaScriptEngineWillResetNotificationName,
                [OOJavaScriptEngine sharedEngine],
                [entity](const oo::Notification&) { [entity deleteJSSelf]; });
        }
    }

    if (JS_IsObject(entity->_cxxEntity->_jsSelf))
        return JS_DupValue(context, entity->_cxxEntity->_jsSelf);

    return JS_NULL;
    // Analyzer: object leaked. [Expected, object is retained by JS object.]
}

JSClassID EntityJSClassID(void)
{
    return JSEntityClassID();
}

void EntityJSDeleteJSSelf(Entity* entity)
{
    if (JS_IsObject(entity->_cxxEntity->_jsSelf)) {
        /*	Scripts may still hold the JS object. Its private data is a weak
                reference, so it becomes stale (isValid false) when the entity is
                deallocated.
        */
        JS_FreeValue(OOJSAcquireContext(), entity->_cxxEntity->_jsSelf);
        entity->_cxxEntity->_jsSelf = JS_UNDEFINED;

        oo::NotificationCenter::defaultCenter().removeObserver(entity, kOOJavaScriptEngineWillResetNotificationName,
            [OOJavaScriptEngine sharedEngine]);
    }
}

// MARK: ShipEntity (OOJavaScriptExtensions)

bool ShipEntityJSIsVisibleToScripts(void)
{
    return true;
}

JSClassID ShipEntityJSClassID(void)
{
    return JSShipClassID();
}

std::optional<std::string> ShipEntityJSClassName(void)
{
    return std::string("Ship");
}

std::vector<oo::ObjCRef<Entity*>> ShipEntityJSSubEntitiesForScript(ShipEntity* ship)
{
    std::vector<oo::ObjCRef<Entity*>> result;
    for (const auto& sub : [ship cxx_shipSubEntities]) {
        result.emplace_back(sub.get());
    }
    return result;
}

void ShipEntityJSSetTargetForScript(ShipEntity* ship, ShipEntity* target)
{
    ShipEntity* me = ship;

    // Ensure coherence by not fiddling with subentities.
    while ([me isSubEntity]) {
        if (me == [me owner] || [me owner] == nil)
            break;
        me = (ShipEntity*)[me owner];
    }
    while ([target isSubEntity]) {
        if (target == [target owner] || [target owner] == nil)
            break;
        target = (ShipEntity*)[target owner];
    }
    if (![me isKindOfClass:[ShipEntity class]])
        return;
    if (target != nil) {
        [me addTarget:target];
    } else
        [me removeTarget:[me primaryTarget]];
}
