/*

OOJSExhaustPlume.h

JavaScript proxy for OOExhaustPlumeEntity.

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

void InitOOJSExhaustPlume(ooscript::Context context, ooscript::Object global);

#ifdef __cplusplus
}
#endif


/*	The bodies of OOExhaustPlumeEntity (OOJavaScriptExtensions), which the engine reaches by
	selector through the root's JS members: the C++ OOExhaustPlumeEntity's overrides call these
	(bead oo-9ht.110; proposed ADR-0056 amendments oo-ppc, oo-ykoy, oo-6ia4 and oo-9ht.107).
*/
void OOJSExhaustPlumeGetJSClass(ooscript::ClassDef **outClass, ooscript::Object *outPrototype);
std::optional<std::string> OOJSExhaustPlumeJSClassName(void);
bool OOJSExhaustPlumeIsVisibleToScripts(void);
