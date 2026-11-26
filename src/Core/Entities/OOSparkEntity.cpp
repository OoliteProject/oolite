/*

OOSparkEntity.m


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

#include "OOSparkEntity.h"
#include "OOColor.h"
#include "PlayerEntity.h"
#include "Universe.h"

oo::Ref<OOSparkEntity> OOSparkEntity::sparkWithPosition(HPVector pos,
    Vector vel,
    OOTimeDelta duration,
    float size,
    OOColor* color)
{
    const oo::Ref<OOSparkEntity> spark = oo::makeRef<OOSparkEntity>();
    spark->initWithPosition(pos, vel, duration, size, color);
    return spark;
}

void OOSparkEntity::initWithPosition(HPVector pos,
    Vector vel,
    OOTimeDelta duration,
    float size,
    OOColor* color)
{
    OOLightParticleEntity::initWithDiameter(size);
    // [super initWithDiameter:] could not fail.
    {
        setPosition(pos);
        setVelocity(vel);
        _duration = _timeRemaining = duration;
        setCollisionRadius(2.0);

        // A message to a nil colour did nothing.
        if (color != nullptr)
            color->getRed(&_baseRGBA[0], &_baseRGBA[1], &_baseRGBA[2], &_baseRGBA[3]);
        performUpdate(0); // Handle colour mixing and such.
    }
}

void OOSparkEntity::update(OOTimeDelta delta_t)
{
    OOLightParticleEntity::update(delta_t);
    performUpdate(delta_t);
}

void OOSparkEntity::performUpdate(OOTimeDelta delta_t)
{
    _timeRemaining -= delta_t;

    float mix = OOClamp_0_1_f(_timeRemaining / _duration);

    // Fade towards red while fading out.
    _colorComponents[0] = mix * _baseRGBA[0] + (1.0f - mix);
    _colorComponents[1] = mix * _baseRGBA[1];
    _colorComponents[2] = mix * _baseRGBA[2];
    _colorComponents[3] = mix * _baseRGBA[3];

    // Disappear when gone.
    if (mix == 0) {
        if (UNIVERSE != nullptr)
            UNIVERSE->removeEntity(this);
    }
}
