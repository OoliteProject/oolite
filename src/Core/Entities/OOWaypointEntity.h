/*

OOWaypoint.h

A waypoint for the HUD


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

#include "Entity.h"
#include "OOPolygonSprite.h"  // OOHUDBeaconIcon: the beacon drawable is std::shared_ptr
#include "oofnd/PList.hpp"

/*	+waypointWithDictionary: takes an oo::PList; the beacon accessors are
   shared and keep id; the beacon strings are std::optional (nil stays nil). The
   initializer is -cxx_initWithDictionary:.
*/

// The universe makes it with waypointWithDictionary(). It answers the
// OOBeaconEntity members the beacon list uses.
class OOWaypointEntity : public Entity {
 public:
  // A new waypoint, initialised.
  static std::shared_ptr<OOWaypointEntity> waypointWithDictionary(
      const oo::PList& info);

  // -cxx_initWithDictionary:'s body after [super init] (the constructor ran
  // Entity's), run once right after construction: it
  // calls members a subclass overrides.
  void initWithDictionary(const oo::PList& info);

  bool getOriented();  // -oriented (the ivar keeps the name)
  OOScalar size();
  void setSize(OOScalar newSize);

  void setOrientation(Quaternion q) override;
  bool isEffect() override;
  bool isWaypoint() override;
  void drawImmediate(bool immediate, bool translucent) override;

  // The binding's bodies (OOJSWaypoint.cpp).
  JSClassID jsClassID() override;
  std::optional<std::string> jsClassName() override;
  bool isVisibleToScripts() override;

  // OOBeaconEntity, answered for the waypoint.
  OOComparisonResult compareBeaconCodeWith(Entity* other);
  std::optional<std::string> beaconCode();
  void setBeaconCode(const std::optional<std::string>& bcode);
  std::optional<std::string> beaconLabel();
  void setBeaconLabel(const std::optional<std::string>& blabel);
  bool isBeacon();
  OOHUDBeaconIcon* beaconDrawable();  // borrowed
  Entity* prevBeacon();  // the C++ entity (null once its object has gone)
  Entity* nextBeacon();
  void setPrevBeacon(Entity* beaconShip);
  void setNextBeacon(Entity* beaconShip);
  bool isJammingScanning();

 private:
  OOScalar _size = {};

  std::optional<std::string> _beaconCode;  // nullopt: nil
  std::optional<std::string> _beaconLabel;
  std::weak_ptr<Entity> _prevBeacon;  // the beacons' C++ parts
  std::weak_ptr<Entity> _nextBeacon;
  std::shared_ptr<OOHUDBeaconIcon> _beaconDrawable;
  bool oriented = {};
};
