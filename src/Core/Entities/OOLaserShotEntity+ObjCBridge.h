/*

OOLaserShotEntity+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, amendments oo-bj8 and oo-5zpq): the Objective-C OOLaserShotEntity,
the facade of a converted leaf entity over the C++ cxx::OOLaserShotEntity (OOLaserShotEntity.h),
kept because ShipEntity makes shots by its class method and messages them, and PlayerEntity keeps
its last shots by this type. Its interface is the one OOLaserShotEntity.h declared before the
conversion, copied exactly, and it has no ivars: the root's _cxxEntity holds its C++ part. Its class
is the graphics reset client of the shot textures. Imported as the last line of
OOLaserShotEntity.h; do not import it directly. Never add to this file. Deleted by its deletion
bead once ShipEntity and PlayerEntity are C++.

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

#ifndef OOLASERSHOTENTITY_OBJCBRIDGE_H
#define OOLASERSHOTENTITY_OBJCBRIDGE_H

@class OOColor;

@interface OOLaserShotEntity : Entity

+ (instancetype)laserFromShip:(ShipEntity*)ship direction:(OOWeaponFacing)direction offset:(Vector)offset;

- (void)setColor:(OOColor*)color;

- (void)setRange:(GLfloat)range;

- (OOTexture*)texture1;
- (OOTexture*)texture2;

+ (void)setUpTexture;
+ (OOTexture*)innerTexture;
+ (OOTexture*)outerTexture;

@end

namespace oo {

// The root's crossings, typed (amendment oo-up4b item 3).
inline cxx::OOLaserShotEntity* ToCxx(::OOLaserShotEntity* entity)
{
    return static_cast<cxx::OOLaserShotEntity*>(ToCxx(static_cast<::Entity*>(entity)));
}
inline ::OOLaserShotEntity* ToObjC(cxx::OOLaserShotEntity* entity)
{
    return (::OOLaserShotEntity*)ToObjC(static_cast<cxx::Entity*>(entity));
}

} // namespace oo

#endif // OOLASERSHOTENTITY_OBJCBRIDGE_H
