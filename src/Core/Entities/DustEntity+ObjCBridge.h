/*

DustEntity+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, amendments oo-bj8 and oo-0mxi): the Objective-C DustEntity, the
facade of a converted leaf entity over the C++ cxx::DustEntity (DustEntity.h), kept because the
universe makes it ([[DustEntity alloc] init]), finds it by its class and sends it its own selector
(-setDustColor:). Its interface is the one DustEntity.h declared before the conversion, copied
exactly, and it has no ivars: the root's _cxxEntity holds its C++ part. It is also what the dust
shader's uniforms are bound to by selector (-warpVector, -offsetPlayerPosition) and the graphics
reset client, so it answers those too (DustEntity+ObjCBridge.mm). Imported as the last line of
DustEntity.h; do not import it directly. Never add to this file. Deleted by its deletion bead once
the universe is C++.

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

#ifndef DUSTENTITY_OBJCBRIDGE_H
#define DUSTENTITY_OBJCBRIDGE_H

@class OOColor;

@interface DustEntity : Entity

- (void)setDustColor:(OOColor*)color;
- (OOColor*)dustColor;

@end

namespace oo {

// The root's crossings, typed (amendment oo-up4b item 3).
inline cxx::DustEntity* ToCxx(::DustEntity* entity)
{
    return static_cast<cxx::DustEntity*>(ToCxx(static_cast<::Entity*>(entity)));
}
inline ::DustEntity* ToObjC(cxx::DustEntity* entity)
{
    return (::DustEntity*)ToObjC(static_cast<cxx::Entity*>(entity));
}

} // namespace oo

#endif // DUSTENTITY_OBJCBRIDGE_H
