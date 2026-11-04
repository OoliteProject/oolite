/*

PlayerEntityLegacyScriptEngine.h

Various utility methods used for scripting.

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

/* The category PlayerEntity (Scripting) is members of PlayerEntity, declared
 * in PlayerEntity.h. This header stays for the files that include it.
 */

#include "oofnd/PList.hpp"
#include "oofnd/StdLib.hpp"

class OOScript;

typedef enum {
  COMPARISON_EQUAL,
  COMPARISON_NOTEQUAL,
  COMPARISON_LESSTHAN,
  COMPARISON_GREATERTHAN,
  COMPARISON_ONEOF,
  COMPARISON_UNDEFINED
} OOComparisonType;

typedef enum {
  OP_STRING,
  OP_NUMBER,
  OP_BOOL,
  OP_MISSION_VAR,
  OP_LOCAL_VAR,
  OP_FALSE,

  OP_INVALID  // Must be last.
} OOOperationType;

std::string cxx_OOComparisonTypeToString(OOComparisonType type);
