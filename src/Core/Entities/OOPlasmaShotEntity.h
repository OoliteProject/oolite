/*

OOPlasmaShotEntity.h

A leaf under OOLightParticleEntity, as OOPlasmaBurstEntity.


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

#include "OOLightParticleEntity.h"

// A global class over OOLightParticleEntity. ShipEntity makes one with
// shotWithPosition().
class OOPlasmaShotEntity : public OOLightParticleEntity {
 public:
  // [[OOPlasmaShotEntity alloc] initWithPosition:...]: a new shot, initialised.
  static oo::Ref<OOPlasmaShotEntity> shotWithPosition(HPVector position,
                                                      Vector velocity,
                                                      float energy,
                                                      OOTimeDelta duration,
                                                      OOColor* color);

  // -initWithPosition:...'s body, run once right after construction.
  void initWithPosition(HPVector position, Vector velocity, float energy,
                        OOTimeDelta duration, OOColor* color);

  bool canCollide() override;
  bool checkCloseCollisionWith(Entity* other) override;
  void update(double delta_t) override;

 private:
  OOTimeDelta _duration = {};
};
