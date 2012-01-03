/*

OOJSPlayerShip.h

JavaScript proxy for the player's ship.
While the player and player's ship are not differentiated in Oolite, such a
separation makes more sense conceptually and design-wise, and we might want to
make it that way in the future. The scripting interface anticipates this by
using two separate objects for the player and player's ship.

The -javaScriptValue of the PlayerEntity is the player's ship.


Oolite
Copyright (C) 2004-2012 Giles C Williams and contributors

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
#include <jsapi.h>

@class PlayerEntity;


void InitOOJSPlayerShip(JSContext *context, JSObject *global);

JSClass *JSPlayerShipClass(void);
JSObject *JSPlayerShipPrototype(void);
JSObject *JSPlayerShipObject(void);
