/*

OOPlasmaShotEntity.h

C++20 since bead oo-z9md, a leaf of the Entities seam under OOLightParticleEntity (proposed
ADR-0056, amendments oo-bj8 item 12 and oo-peql), as OOPlasmaBurstEntity (oo-l2s5).


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

/*	A converted leaf (amendment oo-bj8 item 12): global, over OOLightParticleEntity, with no
        facade of its own. ShipEntity makes one with shotWithPosition() and hands it to Objective-C
        with oo::NewEntityFacade, whose object is an OOLightParticleEntity.
*/
class OOPlasmaShotEntity : public OOLightParticleEntity {
public:
    // [[OOPlasmaShotEntity alloc] initWithPosition:...]: a new shot, initialised.
    static oo::Ref<OOPlasmaShotEntity> shotWithPosition(HPVector position,
        Vector velocity,
        float energy,
        OOTimeDelta duration,
        OOColor* color);

    // -initWithPosition:...'s body, run once right after construction (amendment oo-vl43 item 2).
    void initWithPosition(HPVector position,
        Vector velocity,
        float energy,
        OOTimeDelta duration,
        OOColor* color);

    bool canCollide() override;
    bool checkCloseCollisionWith(Entity* other) override;
    void update(double delta_t) override;

private:
    OOTimeDelta _duration = { };
};
