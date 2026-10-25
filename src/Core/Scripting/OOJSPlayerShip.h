/*

OOJSPlayerShip.h

JavaScript proxy for the player's ship.
While the player and player's ship are not differentiated in Oolite, such a
separation makes more sense conceptually and design-wise, and we might want to
make it that way in the future. The scripting interface anticipates this by
using two separate objects for the player and player's ship.

The -javaScriptValue of the PlayerEntity is the player's ship.


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

#include "OOCocoa.h"
#include "ooscript/JSEngine.hpp"
#include "oofnd/Notification.hpp"
#include <optional>
#include <string>
class PlayerEntity;


#ifdef __cplusplus
extern "C" {
#endif

void InitOOJSPlayerShip(ooscript::Context context, ooscript::Object global);

ooscript::ClassDef *JSPlayerShipClass(void);
ooscript::Object JSPlayerShipPrototype(void);
ooscript::Object JSPlayerShipObject(void);

#ifdef __cplusplus
}
#endif


/*	PlayerEntity (OOJavaScriptExtensions), whose methods the engine and the player send by selector:
	the bodies, as free functions (ADR-0056 amendments oo-ppc item 3, oo-ykoy). The C++ player
	calls them (PlayerEntity::jsClassName(), bead oo-9ht.177).
*/
std::optional<std::string> OOJSPlayerShipJSClassName(void);
void OOJSPlayerShipSetJSSelf(PlayerEntity *player, ooscript::Object val, ooscript::Context context);
void OOJSPlayerShipJavaScriptEngineWillReset(PlayerEntity *player, const oo::Notification &notification);
