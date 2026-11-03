/*

OOJSVisualEffect.h (QuickJS-ng)

JavaScript proxy for OOVisualEffectEntities.

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

#include "OOEntityHold.h"
#include "OOFoundation.h"
#include <quickjs.h>
#include <vector>

class Entity;
class OOVisualEffectEntity;

void InitOOJSVisualEffect(JSContext* context, JSValueConst global);

JSClassID JSVisualEffectClassID(void);

/*	The bodies of OOVisualEffectEntity (OOJavaScriptExtensions), which the engine reaches by
        selector: the effect's facade forwarded to these until it was deleted; the C++ effect's
        jsClassID()/jsClassName()/isVisibleToScripts() overrides call them now. Its JS class is
        JSVisualEffectClassID().
*/
std::optional<std::string> OOJSVisualEffectJSClassName(void);
bool OOJSVisualEffectIsVisibleToScripts(void);
std::vector<oo::EntityHold> OOJSVisualEffectSubEntitiesForScript(OOVisualEffectEntity* effect);
