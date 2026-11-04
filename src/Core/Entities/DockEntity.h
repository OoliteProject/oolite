/*

DockEntity.h

ShipEntity subclass representing a dock.

A dock is made in C++ by DockEntity::newDockObject().

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
#include "StationEntity.h"  // For MAX_DOCKING_STAGES

/*	The dock's state and members.

        Every data member is zero-initialised.
*/
class DockEntity : public ShipEntity {
 public:
  /*	A new dock, set up from its definition as a ship (oo::NewShipObject),
     then given the dock's defaults. Answers the dock, its object retained (+1)
     as +alloc/-init's was, or nullptr when the set-up fails.
  */
  static ::ShipEntity* newDockObject(const std::string& key,
                                     const oo::PList& dict);

  // -cxx_initWithKey:definition:'s body after [super
  // cxx_initWithKey:definition:].
  void initDockDefaults();

  // Run first when a dock is destroyed, before the ship's own teardown.
  void willDealloc();

  // Class shell, flags, geometry and lifecycle.
  void clear();

  // Docking
  bool allowsDocking();
  void setAllowsDocking(bool allowed);
  bool disallowedDockingCollides();
  void setDisallowedDockingCollides(bool ddc);
  NSUInteger countOfShipsInDockingQueue();

  // Launching
  bool allowsLaunching();
  void setAllowsLaunching(bool allowed);
  NSUInteger countOfShipsInLaunchQueue();

  // Geometry
  void setDimensionsAndCorridor(bool docking, bool ddc, bool launching);
  Vector portUpVectorForShipsBoundingBox(BoundingBox bb);
  bool isOffCentre();
  void setVirtual();

  // The ID locks (the private category of DockEntity.mm).
  void clearIdLocks(::ShipEntity* ship);
  void clearAllIdLocks();

  // Docking guidance, the approach queue and docking instructions.
  oo::PList dockingInstructionsForShip(
      ::ShipEntity*
          ship);  // a dictionary (the station an Object node); null: none
  std::optional<std::string> canAcceptShipForDocking(::ShipEntity* ship);
  bool shipIsInDockingQueue(::ShipEntity* ship);
  void abortDockingForShip(::ShipEntity* ship);
  void abortAllDockings();
  void autoDockShipsOnApproach();
  NSUInteger pruneAndCountShipsOnApproach();
  void noteDockingForShip(::ShipEntity* ship);
  void autoDockShipsInQueue(
      std::map<unsigned short, std::vector<oo::PList>>& queue);
  void addShipToShipsOnApproach(::ShipEntity* ship);
  void pullInShipIfPermitted(::ShipEntity* ship);

  // The docking corridor and launching.
  bool shipIsInDockingCorridor(::ShipEntity* ship);
  void abortAllLaunches();
  void addShipToLaunchQueue(::ShipEntity* ship, bool priority);
  void launchShip(::ShipEntity* ship);
  NSUInteger countOfShipsInLaunchQueueWithPrimaryRole(const std::string& role);
  bool allowsLaunchingOf(::ShipEntity* ship);
  bool dockingCorridorIsEmpty();
  void clearDockingCorridor();

  // From the superclass.
  bool isDock() override;
  // Entity (OOJavaScriptExtensions): the binding's bodies (OOJSDock.h).
  JSClassID jsClassID() override;
  std::optional<std::string> jsClassName() override;
  // The ship's answer.
  bool isVisibleToScripts() override;
  bool setUpShipFromDictionary(const oo::PList& dict) override;
  void update(OOTimeDelta delta_t) override;
  void noteTakingDamage(double amount, Entity* entity,
                        OOShipDamageType type) override;
  void takeEnergyDamage(double amount, Entity* ent, Entity* other,
                        const std::string& weaponIdentifier) override;
  void drawImmediate(bool immediate, bool translucent) override;

  // Public so the tests read them.
  std::map<unsigned short, std::vector<oo::PList>>
      shipsOnApproach;  // coordinate stacks (Dicts) by ship ID
  std::vector<oo::EntityHold> launchQueue;  // the ships' objects held
  double last_launch_time = {};
  //	double					approach_spacing; // not needed
  //now holding pattern changed

  oo::WeakRef<Entity>
      id_lock[MAX_DOCKING_STAGES];  // weak references to a ship (its C++ part)

  Vector port_dimensions = {};
  double port_corridor = {};  // corridor length inside station.

  bool no_docking_while_launching = {};
  bool allow_launching = {};
  bool allow_docking = {};
  bool disallowed_docking_collides = {};
  bool virtual_dock = {};
};

namespace oo {

// The same of a C++ entity (what an entity's JS object holds).
inline ::DockEntity* ToDock(Entity* entity) {
  return dynamic_cast<::DockEntity*>(entity);
}

// The same question of a C++ ship: nullptr for null or another ship.
inline ::DockEntity* ToDock(::ShipEntity* ship) {
  return dynamic_cast<::DockEntity*>(ship);
}

}  // namespace oo
