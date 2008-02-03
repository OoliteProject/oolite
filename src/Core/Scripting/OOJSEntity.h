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

BOOL JSValueToEntity(JSContext *context, jsval value, Entity **outEntity);	// Value may be Entity or integer (OOUniversalID).

BOOL JSEntityGetEntity(JSContext *context, JSObject *entityObj, Entity **outEntity);

JSClass *JSEntityClass(void);
JSObject *JSEntityPrototype(void);


/*	EntityFromArgumentList()
	
	Construct a entity from an argument list which is either a (JS) entity or
	an integer (a OOUniversalID). The optional outConsumed argument can be
	used to find out how many parameters were used (currently, this will be 0
	on failure, otherwise 1).
	
	On failure, it will return NO, annd the entity will be unaltered. If
	scriptClass and function are non-nil, a warning will be reported to the
	log.
*/
BOOL EntityFromArgumentList(JSContext *context, NSString *scriptClass, NSString *function, uintN argc, jsval *argv, Entity **outEntity, uintN *outConsumed);
