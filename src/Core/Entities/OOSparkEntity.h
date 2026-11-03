/*

OOSparkEntity.h


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
        facade of its own. Unconverted code makes one with sparkWithPosition() and hands it to
        Objective-C with oo::NewEntityFacade, whose object is an OOLightParticleEntity.
*/
class OOSparkEntity : public OOLightParticleEntity {
public:
    // [[OOSparkEntity alloc] initWithPosition:...]: a new spark, initialised.
    static oo::Ref<OOSparkEntity> sparkWithPosition(HPVector position,
        Vector velocity,
        OOTimeDelta duration,
        float size,
        OOColor* color);

    // -initWithPosition:...'s body, run once right after construction (amendment oo-vl43 item 2).
    void initWithPosition(HPVector position,
        Vector velocity,
        OOTimeDelta duration,
        float size,
        OOColor* color);

    void update(OOTimeDelta delta_t) override;

private:
    void performUpdate(OOTimeDelta delta_t);

    GLfloat _baseRGBA[4] = { };
    GLfloat _duration = { }, _timeRemaining = { };
};
