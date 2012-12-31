/*

OOJSEquipmentInfo.h

JavaScript equipment introspection class, wrapper for OOEquipmentType.


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

#include <jsapi.h>
#import "OOCocoa.h"

@class OOEquipmentType;


void InitOOJSEquipmentInfo(JSContext *context, JSObject *global);

/*	Given a jsval representing a string (equipment key) or a JS EquipmentInfo,
	return the corresponding EquipmentType or key. Note that
	JSValueToEquipmentKey() will not return arbitrary strings, only valid
	equipment keys.
	JSValueToEquipmentKeyRelaxed() will return any string that does not end
	with _DAMAGED.
 */
OOEquipmentType *JSValueToEquipmentType(JSContext *context, jsval value);
NSString *JSValueToEquipmentKey(JSContext *context, jsval value);

NSString *JSValueToEquipmentKeyRelaxed(JSContext *context, jsval value, BOOL *outExists);
