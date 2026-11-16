/*

OOFlashEffectEntity+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, amendments oo-bj8, oo-0otc and oo-0mxi): the Objective-C
OOFlashEffectEntity, the facade of a converted leaf entity over the C++ cxx::OOFlashEffectEntity
(OOFlashEffectEntity.h), kept because the ship and the universe send the class its own selectors
(+explosionFlashFromEntity:, +laserFlashWithPosition:velocity:color:, +setUpTexture), and because
the class is the graphics reset client of the flash texture. Its interface is the one
OOFlashEffectEntity.h declared before the conversion, copied exactly, and it has no ivars: the
root's _cxxEntity holds its C++ part. A flash is made in C++, and oo::NewEntityFacade picks this
class for it. Imported as the last line of OOFlashEffectEntity.h; do not import it directly. Never
add to this file. Deleted by its deletion bead once the ship and the universe are C++.

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

#ifndef OOFLASHEFFECTENTITY_OBJCBRIDGE_H
#define OOFLASHEFFECTENTITY_OBJCBRIDGE_H

@interface OOFlashEffectEntity : OOLightParticleEntity

+ (instancetype)explosionFlashFromEntity:(Entity*)entity;
+ (instancetype)laserFlashWithPosition:(HPVector)position velocity:(Vector)vel color:(OOColor*)color;

+ (void)setUpTexture;

@end

namespace oo {

// The root's crossings, typed (amendment oo-up4b item 3).
inline cxx::OOFlashEffectEntity* ToCxx(::OOFlashEffectEntity* entity)
{
    return static_cast<cxx::OOFlashEffectEntity*>(ToCxx(static_cast<::Entity*>(entity)));
}
inline ::OOFlashEffectEntity* ToObjC(cxx::OOFlashEffectEntity* entity)
{
    return (::OOFlashEffectEntity*)ToObjC(static_cast<cxx::Entity*>(entity));
}

} // namespace oo

#endif // OOFLASHEFFECTENTITY_OBJCBRIDGE_H
