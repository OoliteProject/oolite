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

#include <algorithm>
#include <chrono>
#include <condition_variable>
#include <cstddef>
#include <cstdint>
#include <functional>
#include <map>
#include <memory>
#include <mutex>
#include <optional>
#include <set>
#include <string>
#include <string_view>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <vector>

#include "OOEnumFlags.h"
#include "oofnd/PList.hpp"

class OOScript;

// A sanitized legacy condition stores both as plist unsigned integers
// (OOLegacyScriptWhitelist.h), so their numbers are pinned.
enum class OOComparisonType : unsigned {
  kEqual,
  kNotEqual,
  kLessThan,
  kGreaterThan,
  kOneOf,
  kUndefined
};
static_assert(oo::ToUnderlying(OOComparisonType::kEqual) == 0);
static_assert(oo::ToUnderlying(OOComparisonType::kNotEqual) == 1);
static_assert(oo::ToUnderlying(OOComparisonType::kLessThan) == 2);
static_assert(oo::ToUnderlying(OOComparisonType::kGreaterThan) == 3);
static_assert(oo::ToUnderlying(OOComparisonType::kOneOf) == 4);
static_assert(oo::ToUnderlying(OOComparisonType::kUndefined) == 5);

enum class OOOperationType : unsigned {
  kString,
  kNumber,
  kBool,
  kMissionVar,
  kLocalVar,
  kFalse,

  kInvalid  // Must be last.
};
static_assert(oo::ToUnderlying(OOOperationType::kString) == 0);
static_assert(oo::ToUnderlying(OOOperationType::kNumber) == 1);
static_assert(oo::ToUnderlying(OOOperationType::kBool) == 2);
static_assert(oo::ToUnderlying(OOOperationType::kMissionVar) == 3);
static_assert(oo::ToUnderlying(OOOperationType::kLocalVar) == 4);
static_assert(oo::ToUnderlying(OOOperationType::kFalse) == 5);
static_assert(oo::ToUnderlying(OOOperationType::kInvalid) == 6);

std::string cxx_OOComparisonTypeToString(OOComparisonType type);
