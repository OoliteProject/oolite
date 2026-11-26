/*

PlayerEntityScriptMethods.h

Methods for use by scripting mechanisms.


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

#include "PlayerEntity.h"

/* The category PlayerEntity (ScriptMethods) is members of PlayerEntity,
 * declared in PlayerEntity.h. This header stays for the files that include it.
 */

/*	OOGalacticCoordinatesFromInternal()
        Given internal coordinates ranging from 0 to 255 on each axis, return
        corresponding coordinates in user-meaningful coordinates by scaling by
        0.4 on the X axis and 0.2 on the Y axis.

        OOInternalCoordinatesFromGalactic()
        Inverse operation.

        For valid floating-point comparisons, it is imperative that the same
        calculation be used consistently.
 */
#ifdef __cplusplus
extern "C" {
#endif

Vector OOGalacticCoordinatesFromInternal(NSPoint internalCoordinates);
NSPoint OOInternalCoordinatesFromGalactic(Vector galacticCoordinates);

#ifdef __cplusplus
}
#endif
