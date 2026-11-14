/*

OOECMBlastEntity.h

Invisible entity which radiates ECM blast energy.

A global class over Entity. ShipEntity::fireECM() makes it with initFromShip()
and hands it to the universe. To ask whether an entity is an ECM blast, ask the
C++ part: dynamic_cast<OOECMBlastEntity *>(...)->isECMBlast().

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

#include "Entity.h"

class ShipEntity;

class OOECMBlastEntity : public Entity {
 public:
  // -initFromShip:, which answered nil for a nil ship: null then.
  static oo::Ref<OOECMBlastEntity> initFromShip(ShipEntity* ship);

  void update(OOTimeDelta delta_t) override;
  void drawImmediate(bool immediate, bool translucent) override;

  bool isECMBlast();

 private:
  explicit OOECMBlastEntity(ShipEntity* ship);

  OOTimeDelta _nextBlast = {};
  uint8_t _blastsRemaining = {};
  oo::WeakRef<Entity> _ship;  // the ship's C++ part
};
