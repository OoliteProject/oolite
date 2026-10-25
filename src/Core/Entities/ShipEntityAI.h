/*

ShipEntityAI.h

Additional methods relating to behaviour/artificial intelligence.


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

#include "ShipEntity.h"

class AI;	// C++ since bead oo-9ht.73 (AI.h)
class Universe;
class OOPlanetEntity;	// C++ since bead oo-9ht.129

/*	The category ShipEntity (AI) was declared in ShipEntity+ObjCBridge.h from slice 1 of
	docs/phases/3-slices/ShipEntityAI.md (bead oo-iebuz) until bead oo-9ht.144 deleted the facade:
	its methods are members of ShipEntity, defined in ShipEntityAI.mm (ADR-0056 amendment oo-42dr).
	This header stays for the files that import it.
*/

