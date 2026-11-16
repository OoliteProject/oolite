/*

OOLaserShotEntity+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, amendments oo-bj8 and oo-5zpq): the Objective-C OOLaserShotEntity
facade (see OOLaserShotEntity+ObjCBridge.h). Deleted with OOLaserShotEntity+ObjCBridge.h.

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
#import "OOLaserShotEntity.h"

@implementation OOLaserShotEntity

// The shot is made in C++, and this facade with it (oo::NewEntityFacade picks this class).
+ (instancetype)laserFromShip:(ShipEntity*)ship direction:(OOWeaponFacing)direction offset:(Vector)offset
{
    return (OOLaserShotEntity*)oo::NewEntityFacade(cxx::OOLaserShotEntity::laserFromShip(ship, direction, offset));
}

- (void)setColor:(OOColor*)color
{
    oo::ToCxx(self)->setColor(oo::ToCxx(color));
}
- (void)setRange:(GLfloat)range
{
    oo::ToCxx(self)->setRange(range);
}
- (OOTexture*)texture1
{
    return oo::ToCxx(self)->texture1();
}
- (OOTexture*)texture2
{
    return oo::ToCxx(self)->texture2();
}

+ (void)setUpTexture
{
    cxx::OOLaserShotEntity::setUpTexture();
}
+ (OOTexture*)innerTexture
{
    return cxx::OOLaserShotEntity::innerTexture();
}
+ (OOTexture*)outerTexture
{
    return cxx::OOLaserShotEntity::outerTexture();
}

// OOGraphicsResetClient: setUpTexture() registers this class.
+ (void)resetGraphicsState
{
    cxx::OOLaserShotEntity::resetGraphicsState();
}

@end
