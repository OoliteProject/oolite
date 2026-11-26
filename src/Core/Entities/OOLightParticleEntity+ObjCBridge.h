/*

OOLightParticleEntity+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, amendments oo-bj8 and oo-0otc): the Objective-C
OOLightParticleEntity, the facade of a converted intermediate class (amendment oo-up4b item 2) over
the C++ cxx::OOLightParticleEntity (OOLightParticleEntity.h). Its interface is the one
OOLightParticleEntity.h declared before the conversion, copied exactly, and it has no ivars: the
root's _cxxEntity holds its C++ part. Its -init makes an Objective-C subclass's adapter over
cxx::OOLightParticleEntity, so OOFlashEffectEntity, OOFlasherEntity and OOPlasmaShotEntity reach
this class's members by [super ...], and the C++ bodies reach their -texture and
-drawSubEntityImmediate:translucent: overrides. They read the ivars that were @protected through
the typed crossing below, oo::ToCxx(self)->_colorComponents. A converted subclass (OOSparkEntity,
OOPlasmaBurstEntity) gets this class as its facade from oo::NewEntityFacade. Its class is the
graphics reset client of the default texture. Imported as the last line of OOLightParticleEntity.h;
do not import it directly. Never add to this file. Deleted by its deletion bead once the
subclasses and callers are C++.

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

#ifndef OOLIGHTPARTICLEENTITY_OBJCBRIDGE_H
#define OOLIGHTPARTICLEENTITY_OBJCBRIDGE_H

@class OOColor;

@interface OOLightParticleEntity : Entity

- (id)initWithDiameter:(float)diameter;

- (float)diameter;
- (void)setDiameter:(float)diameter;

- (void)setColor:(OOColor*)color;
- (void)setColor:(OOColor*)color alpha:(GLfloat)alpha;

/*	For subclasses that don't want the default blur texture.
        NOTE: such subclasses must deal with the OOGraphicsResetManager. Also,
        OOLightParticleEntity assumes the texture is twice as big as the nominal
        size of the particle (with a black border for anti-aliasing purposes).
*/
- (OOTexture*)texture;

+ (void)setUpTexture;
+ (OOTexture*)defaultParticleTexture;

- (void)drawSubEntityImmediate:(bool)immediate translucent:(bool)translucent;

@end

namespace oo {

// The root's crossings, typed (amendment oo-up4b item 3).
inline cxx::OOLightParticleEntity* ToCxx(::OOLightParticleEntity* entity)
{
    return static_cast<cxx::OOLightParticleEntity*>(ToCxx(static_cast<::Entity*>(entity)));
}
inline ::OOLightParticleEntity* ToObjC(cxx::OOLightParticleEntity* entity)
{
    return (::OOLightParticleEntity*)ToObjC(static_cast<cxx::Entity*>(entity));
}

} // namespace oo

#endif // OOLIGHTPARTICLEENTITY_OBJCBRIDGE_H
