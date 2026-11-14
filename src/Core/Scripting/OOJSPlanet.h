/*

OOJSPlanet.h (QuickJS-ng)

JavaScript proxy for PlanetEntities.


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

#import "OOFoundation.h"
#include <quickjs.h>

#include <optional>
#include <string>

class OOPlanetEntity;

void InitOOJSPlanet(JSContext* context, JSValueConst global);

JSClassID JSPlanetClassID(void);

/*	The bodies of OOPlanetEntity (OOJavaScriptExtensions), which the engine reaches through the root
        Entity's virtual members: the C++ planet's overrides call these (the OOPlanetEntity facade
        forwarded to them before). Its JS class is JSPlanetClassID().
*/
bool OOJSPlanetIsVisibleToScripts(OOPlanetEntity* planet);
std::optional<std::string> OOJSPlanetJSClassName(OOPlanetEntity* planet);
