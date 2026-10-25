/*

OOJSWaypoint.h

JavaScript proxy for OOWaypointEntities.

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


#ifdef __cplusplus
extern "C" {
#endif

void InitOOJSWaypoint(ooscript::Context context, ooscript::Object global);

#ifdef __cplusplus
}
#endif


/*	The bodies of OOWaypointEntity (OOJavaScriptExtensions), which the engine reaches through the
	root's JS members: the C++ class's overrides call these (the OOWaypointEntity facade forwarded
	to them from bead oo-9ht.50 until bead oo-9ht.108 deleted it; proposed ADR-0056 amendments
	oo-ppc, oo-ykoy, oo-6ia4 and oo-9ht.107).
*/
void OOJSWaypointGetJSClass(ooscript::ClassDef **outClass, ooscript::Object *outPrototype);
std::optional<std::string> OOJSWaypointJSClassName(void);
bool OOJSWaypointIsVisibleToScripts(void);
