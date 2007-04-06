/*

OOJSEntity.h

JavaScript proxy for entities.

Oolite
Copyright (C) 2004-2007 Giles C Williams and contributors

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
#import <jsapi.h>

@class Entity;


void InitOOJSEntity(JSContext *context, JSObject *global);

JSObject *JSEntityWithEntity(JSContext *context, Entity *entity);

BOOL EntityToJSValue(JSContext *context, Entity *entity, jsval *outValue);
BOOL JSValueToEntity(JSContext *context, jsval value, Entity **outEntity);	// Value may be Entity or integer (UniversalID).

BOOL JSEntityGetEntity(JSContext *context, JSObject *entityObj, Entity **outEntity);

JSClass *EntityJSClass(void);
