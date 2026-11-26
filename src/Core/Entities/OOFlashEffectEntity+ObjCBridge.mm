/*

OOFlashEffectEntity+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, amendments oo-bj8, oo-0otc and oo-0mxi): the Objective-C
OOFlashEffectEntity facade (see OOFlashEffectEntity+ObjCBridge.h). Deleted with
OOFlashEffectEntity+ObjCBridge.h.

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
#import "OOFlashEffectEntity.h"

@implementation OOFlashEffectEntity

// The flash is made in C++, and this facade with it (oo::NewEntityFacade picks this class).
+ (instancetype)explosionFlashFromEntity:(Entity*)entity
{
    return (OOFlashEffectEntity*)oo::NewEntityFacade(cxx::OOFlashEffectEntity::explosionFlashFromEntity(entity));
}

+ (instancetype)laserFlashWithPosition:(HPVector)pos velocity:(Vector)vel color:(OOColor*)color
{
    return (OOFlashEffectEntity*)oo::NewEntityFacade(cxx::OOFlashEffectEntity::laserFlashWithPosition(pos, vel, oo::ToCxx(color)));
}

+ (void)setUpTexture
{
    cxx::OOFlashEffectEntity::setUpTexture();
}

// OOGraphicsResetClient: setUpTexture() registers this class.
+ (void)resetGraphicsState
{
    cxx::OOFlashEffectEntity::resetGraphicsState();
}

@end
