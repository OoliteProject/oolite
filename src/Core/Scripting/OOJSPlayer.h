/*

OOJSPlayer.h

JavaScript proxy for the player.

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


void InitOOJSPlayer(JSContext *context, JSObject *global);

JSClass *JSPlayerClass(void);
JSObject *JSPlayerPrototype(void);
JSObject *JSPlayerObject(void);


/*	All JS functions which talk to the player entity should call
	OOOPlayerForScripting() to ensure that the script target (for the legacy
	system) is set correctly. Additionally, all such functions should _always_
	call OOPlayerForScripting(), even if they end up not using it, to ensure
	consistent state.
*/
PlayerEntity *OOPlayerForScripting(void);
