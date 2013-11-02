/*

OOJSEntity.h

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

#import <Foundation/Foundation.h>
#import "OOJavaScriptEngine.h"
#import "Universe.h"

@class Entity;


void InitOOJSEntity(JSContext *context, JSObject *global);

BOOL JSValueToEntity(JSContext *context, jsval value, Entity **outEntity);

extern JSClass gOOEntityJSClass;
extern JSObject *gOOEntityJSPrototype;
DEFINE_JS_OBJECT_GETTER(OOJSEntityGetEntity, &gOOEntityJSClass, gOOEntityJSPrototype, Entity)

OOINLINE JSClass *JSEntityClass(void)  { return &gOOEntityJSClass; }
OOINLINE JSObject *JSEntityPrototype(void)  { return gOOEntityJSPrototype; }


/*	EntityFromArgumentList()
	
	Construct a entity from an argument list containing a JS Entity object.
	The optional outConsumed argument can be used to find out how many
	parameters were used (currently, this will be 0 on failure, otherwise 1).
	
	On failure, it will return NO, annd the entity will be unaltered. If
	scriptClass and function are non-nil, a warning will be reported to the
	log.
*/
BOOL EntityFromArgumentList(JSContext *context, NSString *scriptClass, NSString *function, uintN argc, jsval *argv, Entity **outEntity, uintN *outConsumed);


/*
	For scripting purposes, a JS entity object is a stale reference if its
	underlying ObjC object is nil, or if it refers to the player and the
	blockJSPlayerShipProps flag is in effect (i.e., the escape pod sequence is
	active).
*/
OOINLINE BOOL OOIsPlayerStale(void)
{
	extern Entity *gOOJSPlayerIfStale;
	return gOOJSPlayerIfStale != nil;
}

OOINLINE BOOL OOIsStaleEntity(Entity *entity)
{
	extern Entity *gOOJSPlayerIfStale;
	return entity == nil || (entity == gOOJSPlayerIfStale);
}
