/*

OOJSPlayer.h (QuickJS-ng)

JavaScript proxy for the player.

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

#import "PlayerEntity.h"
#import <Foundation/Foundation.h>
#include <quickjs.h>

@class PlayerEntity;

void InitOOJSPlayer(JSContext* context, JSValueConst global);

JSClassID JSPlayerClassID(void);

/*	The global player object. The returned value is owned by the caller, who
        must JS_FreeValue() it. (SpiderMonkey's JSPlayerPrototype() is no
        longer needed; use JS_GetClassProto(context, JSPlayerClassID()).)
*/
JSValue JSPlayerObject(void);

/*	All JS functions which talk to the player entity should call
        OOOPlayerForScripting() to ensure that the script target (for the legacy
        system) is set correctly. Additionally, all such functions should _always_
        call OOPlayerForScripting(), even if they end up not using it, to ensure
        consistent state.
*/
PlayerEntity* OOPlayerForScripting(void);
