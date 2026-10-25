/*

OOJSEquipmentInfo.h

JavaScript equipment introspection class, wrapper for OOEquipmentType.


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
#include "oofnd/StdLib.hpp"



#ifdef __cplusplus
extern "C" {
#endif

void InitOOJSEquipmentInfo(ooscript::Context context, ooscript::Object global);

#ifdef __cplusplus
}
#endif

/*	Given a ooscript::Value representing a string (equipment key) or a JS EquipmentInfo,
	return the corresponding EquipmentType or key. Note that
	JSValueToEquipmentKey() will not return arbitrary strings, only valid
	equipment keys.
	JSValueToEquipmentKeyRelaxed() will return any string that does not end
	with _DAMAGED.
 */
class OOEquipmentType;	// C++ since bead oo-9ht.28 (OOEquipmentType.h)

#ifdef __cplusplus
extern "C" {
#endif

OOEquipmentType *JSValueToEquipmentType(ooscript::Context context, ooscript::Value value);
extern "C++" {	// C++ results (proposed ADR-0043, bead oo-xcqk); nullopt where these returned nil
std::optional<std::string> JSValueToEquipmentKey(ooscript::Context context, ooscript::Value value);

// outExists stays BOOL *: its callers pass the address of a BOOL of their own (bead oo-supk).
std::optional<std::string> JSValueToEquipmentKeyRelaxed(ooscript::Context context, ooscript::Value value, BOOL *outExists);
}

#ifdef __cplusplus
}
#endif


/*	The JS class name of OOEquipmentType's OOJSPrivateObject members, defined in
	OOJSEquipmentInfo.mm (proposed ADR-0056 amendment oo-6symp).
*/
std::optional<std::string> OOJSEquipmentInfoJSClassName(void);
