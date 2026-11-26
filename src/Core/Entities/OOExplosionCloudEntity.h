/*

OOExplosionCloudEntity.h

Cloud effect during explosions


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

#import "OOParticleSystem.h"

#include "oofnd/PList.hpp"

/*	Foundation sweep (proposed ADR-0043, bead oo-8sel): the explosion settings are an oo::PList (a
        Dict; an empty one where the settings were nil).
*/
@interface OOExplosionCloudEntity : OOParticleSystem {
@private
    float _growthRate;
    OOTimeDelta _cloudDuration;
    float _alpha;
    float _brightnessMult;
    OOTexture* _texture;
    oo::PList _settings;
}

+ (instancetype)explosionCloudFromEntity:(Entity*)entity withSettings:(const oo::PList&)settings;
+ (instancetype)explosionCloudFromEntity:(Entity*)entity withSize:(float)size andSettings:(const oo::PList&)settings;

@end
