/*

OOJSDock.h

JavaScript proxy for DockEntities.

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
class DockEntity;

#ifdef __cplusplus
extern "C" {
#endif

void InitOOJSDock(ooscript::Context context, ooscript::Object global);

#ifdef __cplusplus
}
#endif


/*	The bodies of Entity (OOJavaScriptExtensions)'s class questions for a dock, which the C++
	DockEntity's overrides call (bead oo-9ht.47; proposed ADR-0056 amendments oo-ppc and oo-ykoy).
*/
void OOJSDockGetJSClass(ooscript::ClassDef **outClass, ooscript::Object *outPrototype);
std::optional<std::string> OOJSDockJSClassName(void);
