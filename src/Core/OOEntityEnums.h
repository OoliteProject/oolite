/*

OOEntityEnums.h

The entity enumerations:
OOEntityStatus and OOScanClass (Entities/Entity.h), OOGUIScreenID and
OOGalacticHyperspaceBehaviour (Entities/PlayerEntity.h), OOShipDamageType
(Entities/ShipEntity.h). They live here so a plain C or
C++ translation unit (OOConstToJSString) can name them without including those
headers. Those headers include this one back.


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

// From Entities/Entity.h.

#include "OOEntityStatus.h"
#include "OOScanClass.h"

// From Entities/PlayerEntity.h.

#define ENTRY(label, value) label,

typedef enum {
#include "OOGUIScreenID.tbl"
} OOGUIScreenID;

#undef ENTRY

#include "OOGalacticHyperspaceBehaviour.h"

enum {
  // Values used for unknown strings.
  kOOGUIScreenIDDefault = GUI_SCREEN_MAIN
};

// From Entities/ShipEntity.h.

#include "OOShipDamageType.h"
