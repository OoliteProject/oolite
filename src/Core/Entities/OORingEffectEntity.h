/*

OORingEffectEntity.h

Entity subclass for expanding-ring effect, used for hyperspace entry and for
some large explosions.
C++20 since bead oo-peql, a leaf of the Entities seam (proposed ADR-0056, amendment oo-bj8 item
12). A global class over Entity, with no facade: nothing messages it by its own selectors.
Its callers (ShipEntity, Universe) make it with a factory and hand the universe the Entity facade
oo::NewEntityFacade makes, which is its Objective-C object from then on.


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

class OORingEffectEntity : public Entity {
public:
    // Null for a nil source (the Objective-C factories answered nil).
    static oo::Ref<OORingEffectEntity> ringFromEntity(Entity* sourceEntity);
    static oo::Ref<OORingEffectEntity> shrinkingRingFromEntity(Entity* sourceEntity);

    std::optional<std::string> descriptionComponents() const override;
    void update(OOTimeDelta delta_t) override;
    void drawImmediate(bool immediate, bool translucent) override;
    bool isEffect() override;
    bool canCollide() override;

private:
    static void initialize();
    bool initRingFromEntity(Entity* sourceEntity);

    GLfloat _timePassed = { };
    GLfloat _innerRadius = { },
            _outerRadius = { },
            _innerGrowthRate = { },
            _outerGrowthRate = { };
};
