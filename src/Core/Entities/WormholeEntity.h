/*

WormholeEntity.h

Entity subclass representing a wormhole between systems. (This is -- to use
technical terminology -- the blue blobby thing you see hanging in space. The
purple tunnel is RingEntity.)

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
#include "oofnd/PList.hpp"

#define WORMHOLE_EXPIRES_TIMEINTERVAL 900.0
#define WORMHOLE_SHRINK_RATE 4000.0
#define WORMHOLE_LEADER_SPEED_FACTOR 0.25

class Universe;
class ShipEntity;

typedef enum {
  WH_SCANINFO_NONE = 0,
  WH_SCANINFO_SCANNED,
  WH_SCANINFO_COLLAPSE_TIME,
  WH_SCANINFO_ARRIVAL_TIME,
  WH_SCANINFO_DESTINATION,
  WH_SCANINFO_SHIP,
} WORMHOLE_SCANINFO;

// The names the game writes for WORMHOLE_SCANINFO (saves, logs and plists).
constexpr std::string_view OOEnumName(WORMHOLE_SCANINFO value) noexcept {
  switch (value) {
    case WH_SCANINFO_NONE:
      return "WH_SCANINFO_NONE";
    case WH_SCANINFO_SCANNED:
      return "WH_SCANINFO_SCANNED";
    case WH_SCANINFO_COLLAPSE_TIME:
      return "WH_SCANINFO_COLLAPSE_TIME";
    case WH_SCANINFO_ARRIVAL_TIME:
      return "WH_SCANINFO_ARRIVAL_TIME";
    case WH_SCANINFO_DESTINATION:
      return "WH_SCANINFO_DESTINATION";
    case WH_SCANINFO_SHIP:
      return "WH_SCANINFO_SHIP";
  }
  return {};
}

// A ship in transit (the old entry dictionary's "ship", "time" and
// "shipBeacon").
struct OOWormholeTransit {
  oo::EntityHold ship;  // the ship, its object held
  double time;          // arrival relative to the wormhole's arrival_time
  std::optional<std::string>
      beacon;  // the ship's beacon code when it entered, if any
};

/*	The player and the ships make it with oo::makeRef<WormholeEntity>() and
   an initialiser, and find it again with dynamic_cast. The
   universe's and the player's lists keep the objects (held C++ entities).
*/
class WormholeEntity : public Entity {
 public:
  // The private -init's body (after [super init]: the constructor ran
  // Entity's). The initialisers below run it first, as they sent [self init].
  void init();

  /*	-initWithDict: and -initWormholeTo:fromShip:'s bodies, run on a new
   * wormhole (after init()).
   */
  void initWithDict(const oo::PList& dict);
  void initWormholeTo(OOSystemID s, ::ShipEntity* ship);

  bool suckInShip(::ShipEntity* ship);
  void disgorgeShips();
  void setExitPosition(HPVector pos);

  OOSystemID getOrigin();       // -origin (the ivar keeps the name)
  OOSystemID getDestination();  // -destination
  NSPoint originCoordinates();
  NSPoint destinationCoordinates();

  void setMisjump();                        // Flags up a wormhole as 'misjumpy'
  void setMisjumpWithRange(GLfloat range);  // Flags up a wormhole as 'misjumpy'
  bool withMisjump();
  GLfloat misjumpRange();

  double exitSpeed();               // exit speed from this wormhole
  void setExitSpeed(double speed);  // set exit speed from this wormhole

  double expiryTime();            // Time at which the wormholes entrance closes
  double arrivalTime();           // Time at which the wormholes exit opens
  double estimatedArrivalTime();  // Time when wormhole should open (different
                                  // from arrival_time for misjump wormholes)
  double travelTime();  // Time needed for a ship to traverse the wormhole
  double scanTime();    // Time when wormhole was scanned
  void setScannedAt(double time);
  void setContainsPlayer(
      bool val);  // mark the wormhole as waiting for player exit

  bool isScanned();  // True if the wormhole has been scanned by the player
  WORMHOLE_SCANINFO scanInfo();  // Stage of scanning
  void setScanInfo(WORMHOLE_SCANINFO scanInfo);

  oo::PList getShipsInTransit();  // -shipsInTransit (the ivar keeps the name).
                                  // Dicts: "ship" (an Object node), "time",
                                  // "shipBeacon" when set

  std::optional<std::string> identFromShip(::ShipEntity* ship);

  oo::PList getDict();

  std::optional<std::string> descriptionComponents() const override;
  bool canCollide() override;
  bool checkCloseCollisionWith(Entity* other) override;
  void update(OOTimeDelta delta_t) override;
  void drawImmediate(bool immediate, bool translucent) override;
  void dumpSelfState() override;

  // The binding's bodies (OOJSWormhole.cpp).
  JSClassID jsClassID() override;
  std::optional<std::string> jsClassName() override;
  bool isVisibleToScripts() override;

 private:
  const char* scanInfoString();

  double expiry_time = {};   // Time when wormhole entrance closes
  double travel_time = {};   // Time taken for a ship to traverse the wormhole
  double arrival_time = {};  // Time when wormhole exit opens
  double estimated_arrival_time =
      {};  // Time when wormhole should open (be different to arrival_time for
           // misjump wormholes)
  double scan_time = {};  // Time when wormhole was scanned

  OOSystemID origin = {};
  OOSystemID destination = {};

  NSPoint originCoords = {};  // May not equal our origin system if the wormhole
                              // opens from Interstellar Space
  NSPoint destinationCoords =
      {};  // May not equal the destination system if the wormhole misjumps

  std::vector<OOWormholeTransit> shipsInTransit;

  double witch_mass = {};
  double shrink_factor = {};  // used during nova mission
  // not used yet
  double exit_speed = {};  // exit speed of ships in this wormhole

  WORMHOLE_SCANINFO scan_info = {};
  bool hasExitPosition = {};
  bool _misjump = {};
  GLfloat _misjumpRange = {};
  bool containsPlayer = {};
};

// WormholeEntity::shipsInTransit() of a wormhole, for the debug monitor's dump;
// a null PList for null or another entity.
oo::PList WormholeEntityShipsInTransit(Entity* entity);
