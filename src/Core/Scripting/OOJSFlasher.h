/*

OOJSFlasher.h

JavaScript proxy for OOFlasherEntity.

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

void InitOOJSFlasher(ooscript::Context context, ooscript::Object global);

#ifdef __cplusplus
}
#endif


/*	The bodies of OOFlasherEntity (OOJavaScriptExtensions), which the engine reaches by selector
	through the root's JS members: the C++ OOFlasherEntity's overrides call these (bead
	oo-9ht.107; proposed ADR-0056 amendments oo-ppc, oo-ykoy, oo-6ia4 and oo-9ht.107).
*/
void OOJSFlasherGetJSClass(ooscript::ClassDef **outClass, ooscript::Object *outPrototype);
std::optional<std::string> OOJSFlasherJSClassName(void);
bool OOJSFlasherIsVisibleToScripts(void);
