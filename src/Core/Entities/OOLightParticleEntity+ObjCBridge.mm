/*

OOLightParticleEntity+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, amendments oo-bj8 and oo-0otc): the Objective-C
OOLightParticleEntity facade (see OOLightParticleEntity+ObjCBridge.h), and the adapter of its
Objective-C subclasses. Deleted with OOLightParticleEntity+ObjCBridge.h.

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

#import "OOColor.h"
#import "OOLightParticleEntity.h"

namespace {

/*	The C++ part of an Objective-C subclass (OOFlashEffectEntity, ...): the root's adapter over this
        class, plus the members this class added that the subclasses override, which message the
        Objective-C object (amendment oo-vl43 item 1). Their facade methods call this class's own
        member on such an object, which is what [super ...] (or not overriding) reached.
*/
class ObjCLightParticleEntity final : public oo::ObjCEntity<cxx::OOLightParticleEntity> {
public:
    explicit ObjCLightParticleEntity(::Entity* objcOwner)
        : oo::ObjCEntity<cxx::OOLightParticleEntity>(objcOwner)
    {
    }

    ::OOTexture* texture() override { return [(::OOLightParticleEntity*)_objcOwner texture]; }
    void drawSubEntityImmediate(bool immediate, bool translucent) override { [(::OOLightParticleEntity*)_objcOwner drawSubEntityImmediate:immediate translucent:translucent]; }
};

} // namespace

@implementation OOLightParticleEntity

// An Objective-C light particle: [[X alloc] initWithDiameter:] of a subclass (or of this class).
- (id)init
{
    // -init sent again to an initialised entity keeps its C++ part (the root's -initWithCxxEntity:).
    if (_cxxEntity != nullptr)
        return [super initWithCxxEntity:_cxxEntity.get()];
    return [super initWithCxxEntity:oo::makeRef<ObjCLightParticleEntity>(self).get()];
}

- (id)initWithDiameter:(float)diameter
{
    // [super init] is -init above (no subclass overrides it); the body is the C++ initialiser.
    self = [self init];
    if (self != nil)
        oo::ToCxx(self)->initWithDiameter(diameter);
    return self;
}

- (float)diameter
{
    return oo::ToCxx(self)->diameter();
}
- (void)setDiameter:(float)diameter
{
    oo::ToCxx(self)->setDiameter(diameter);
}
- (void)setColor:(OOColor*)color
{
    oo::ToCxx(self)->setColor(oo::ToCxx(color));
}
- (void)setColor:(OOColor*)color alpha:(GLfloat)alpha
{
    oo::ToCxx(self)->setColor(oo::ToCxx(color), alpha);
}

- (OOTexture*)texture
{
    if (oo::AsObjCEntity(_cxxEntity.get()) != nullptr)
        return oo::ToCxx(self)->cxx::OOLightParticleEntity::texture();
    return oo::ToCxx(self)->texture();
}

- (void)drawSubEntityImmediate:(bool)immediate translucent:(bool)translucent
{
    if (oo::AsObjCEntity(_cxxEntity.get()) != nullptr)
        oo::ToCxx(self)->cxx::OOLightParticleEntity::drawSubEntityImmediate(immediate, translucent);
    else
        oo::ToCxx(self)->drawSubEntityImmediate(immediate, translucent);
}

+ (void)setUpTexture
{
    cxx::OOLightParticleEntity::setUpTexture();
}
+ (OOTexture*)defaultParticleTexture
{
    return cxx::OOLightParticleEntity::defaultParticleTexture();
}

// OOGraphicsResetClient: setUpTexture() registers this class.
+ (void)resetGraphicsState
{
    cxx::OOLightParticleEntity::resetGraphicsState();
}

@end
