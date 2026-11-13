/*

OOMeshToOctreeConverter.h

Class to manage the construction of octrees from triangle soups.


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

#include "OOFoundation.h"
#include "OOMaths.h"
#include "Octree.h"
#include "oofnd/Ref.hpp"
#include "oofnd/objc/OOObject.h"

class ShipEntity;

inline constexpr uint32_t kOOMeshToOctreeConverterSmallDataCapacity = 16;

struct OOMeshToOctreeConverterInternalData {
  Triangle* triangles;
  uint32_t count;
  uint32_t capacity;
  uint32_t pendingCapacity;
  Triangle smallData[kOOMeshToOctreeConverterSmallDataCapacity];
  std::vector<Triangle> heap;  // the storage once smallData is outgrown
};

class OOMeshToOctreeConverter : public oo::RefCounted {
 public:
  explicit OOMeshToOctreeConverter(std::size_t capacity);  // -initWithCapacity:
  static std::shared_ptr<OOMeshToOctreeConverter> converterWithCapacity(
      std::size_t capacity);
  ~OOMeshToOctreeConverter() override;

  void addTriangle(Triangle tri);

  std::shared_ptr<Octree> findOctreeToDepth(std::size_t depth);

  // What "%@" prints between the braces of <OOMeshToOctreeConverter 0x...>{...}
  // (OODescription.h).
  std::optional<std::string> descriptionComponents() const;

 private:
  struct OOMeshToOctreeConverterInternalData _data = {};
};
