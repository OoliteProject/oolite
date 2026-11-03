/*

OOExplosionCloudEntity.h

Cloud effect during explosions

C++20 since bead oo-cenx, with its superclass (see OOParticleSystem.h; bead oo-ui7h's class). A
global class with no facade: ShipEntity and Universe make it with a factory and hand the universe
the Entity facade oo::NewEntityFacade makes.

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

#include "OOParticleSystem.h"

#include "oofnd/PList.hpp"

/*	Foundation sweep (proposed ADR-0043, bead oo-8sel): the explosion settings are an oo::PList (a
        Dict; an empty one where the settings were nil).
*/
class OOExplosionCloudEntity : public OOParticleSystem {
public:
    // Null where the texture is not found (the Objective-C factories answered nil).
    static oo::Ref<OOExplosionCloudEntity> explosionCloudFromEntity(Entity* entity, const oo::PList& settings);
    static oo::Ref<OOExplosionCloudEntity> explosionCloudFromEntity(Entity* entity, float size, const oo::PList& settings);

    void update(OOTimeDelta delta_t) override;
    OOTexture* texture() override;

private:
    bool initExplosionCloudWithEntity(Entity* entity, float size, const oo::PList& settings);

    float _growthRate = { };
    OOTimeDelta _cloudDuration = { };
    float _alpha = { };
    float _brightnessMult = { };
    oo::Ref<OOTexture> _texture;
    oo::PList _settings;
};
