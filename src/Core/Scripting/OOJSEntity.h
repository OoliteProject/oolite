/*

OOJSEntity.h (QuickJS-ng)

JavaScript proxy for entities.

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
#pragma once

#include "Entity.h"
#include "OOFoundation.h"
#include "OOJSEntityHolder.h"
#include "OOJavaScriptEngine.h"
#include "Universe.h"
#include "oofnd/StdLib.hpp"

class Entity;

void InitOOJSEntity(JSContext* context, JSValueConst global);

// The C++ entity (the slot holds it; the facade before), or null for a stale one.
bool JSValueToEntity(JSContext* context, JSValueConst value, Entity** outEntity);

JSClassID JSEntityClassID(void);

/*	OOJSEntityGetEntity was DEFINE_JS_OBJECT_GETTER's getter of the Entity class until the slot
        held an OOJSEntityHolder: the getter is OOJSGetCxxPrivate's (the same JS class check and
        error) and answers the C++ entity, null for a stale one (or a prototype). The JS class fixes
        what the slot holds, so the Objective-C class check of the debug build has nothing left to
        check. A binding's own class (Ship, Planet, Sun) passes its JS class as
        DEFINE_JS_OBJECT_GETTER did.
*/
OOINLINE bool OOJSEntityGetEntityOfClass(JSContext* context, JSValueConst inObject, JSClassID jsClassID, Entity** outEntity)
{
    OOJSEntityHolder* holder = nullptr;
    if (!OOJSGetCxxPrivate(context, inObject, jsClassID, &holder))
        return false;
    *outEntity = (holder != nullptr) ? holder->entity() : nullptr;
    return true;
}

OOINLINE bool OOJSEntityGetEntity(JSContext* context, JSValueConst inObject, Entity** outEntity)
{
    return OOJSEntityGetEntityOfClass(context, inObject, JSEntityClassID(), outEntity);
}

/*	OOJSNativeObjectOfClassFromJSValue(context, value, <the root entity class>) for a C++ caller:
        the entity an entity's JS object holds, else null, with no error (another value, another
        object, a stale entity), as that answered nil.
*/
Entity* OOJSEntityFromJSValue(JSContext* context, JSValueConst value);

// The position and orientation of the C++ entity an entity's JS object (of any entity class) holds,
// zero for a stale one, for the conversions that take them (OOJSVector, OOJSQuaternion): its
// getPosition()/getOrientation(), which the object's -position/-orientation answered before (the
// object of OOJSEntityObjectFromJSObject, nil for a stale one). The object must be of the Entity
// class or a subclass.
HPVector OOJSEntityPositionOfJSObject(JSContext* context, JSValueConst object);
Quaternion OOJSEntityOrientationOfJSObject(JSContext* context, JSValueConst object);

// OOJSBasicPrivateObjectConverter for the entity classes (each registers it): the entity's object
// (its facade, which code converting a JS value still expects) as an Object node, a null PList
// once the entity has gone, as the slot's weak reference answered.
oo::PList OOJSEntityObjectConverter(JSContext* context, JSValueConst object);

// toString() of the entity classes: OOJSCxxObjectWrapperToString for the Entity class and its
// subclasses (the entity's jsDescription(), else "[object <JS class name>]").
JSValue OOJSEntityToString(OOJS_NATIVE_ARGS);

/*	EntityFromArgumentList()

        Construct a entity from an argument list containing a JS Entity object.
        The optional outConsumed argument can be used to find out how many
        parameters were used (currently, this will be 0 on failure, otherwise 1).

        On failure, it will return false, annd the entity will be unaltered. If
        scriptClass and function are non-nil, a warning will be reported to the
        log.
*/
// C++ parameters (proposed ADR-0043); nullopt class or function: no warning (was nil).
bool EntityFromArgumentList(JSContext* context, const std::optional<std::string>& scriptClass, const std::optional<std::string>& function, int argc, JSValueConst* argv, Entity** outEntity, int* outConsumed);

/*
        For scripting purposes, a JS entity object is a stale reference if its
        underlying ObjC object is nil, or if it refers to the player and the
        blockJSPlayerShipProps flag is in effect (i.e., the escape pod sequence is
        active).
*/
// The global holds the player's C++ entity while the flag is in effect (it held
// the player's object), else null.
OOINLINE bool OOIsPlayerStale(void)
{
    extern Entity* gOOJSPlayerIfStale;
    return gOOJSPlayerIfStale != nullptr;
}

// Of the C++ entity a getter answers.
OOINLINE bool OOIsStaleEntity(Entity* entity)
{
    extern Entity* gOOJSPlayerIfStale;
    return entity == nullptr || (gOOJSPlayerIfStale != nullptr && entity == gOOJSPlayerIfStale);
}
