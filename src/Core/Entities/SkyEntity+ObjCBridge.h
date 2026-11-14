/*

SkyEntity+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, amendments oo-bj8 and oo-0mxi): the Objective-C SkyEntity, the
facade of a converted leaf entity over the C++ cxx::SkyEntity (SkyEntity.h), kept because the
universe makes it ([[SkyEntity alloc] initWithColors::andSystemInfo:]), finds it by its class and
sends it its own selectors (-skyColor, -changeProperty:withDictionary:). Its interface is the one
SkyEntity.h declared before the conversion, copied exactly, and it has no ivars: the root's
_cxxEntity holds its C++ part. Imported as the last line of SkyEntity.h; do not import it
directly. Never add to this file. Deleted by its deletion bead once the universe and the
environment cube map are C++.

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

#ifndef SKYENTITY_OBJCBRIDGE_H
#define SKYENTITY_OBJCBRIDGE_H

@class OOColor;

@interface SkyEntity : OOEntityWithDrawable

- (id)initWithColors:(OOColor*)col1 col2:(OOColor*)col2 andSystemInfo:(const oo::PList&)systemInfo;
- (BOOL)changeProperty:(const std::string&)key withDictionary:(const oo::PList&)dict;

- (OOColor*)skyColor;

@end

namespace oo {

// The root's crossings, typed (amendment oo-up4b item 3).
inline cxx::SkyEntity* ToCxx(::SkyEntity* entity)
{
    return static_cast<cxx::SkyEntity*>(ToCxx(static_cast<::Entity*>(entity)));
}
inline ::SkyEntity* ToObjC(cxx::SkyEntity* entity)
{
    return (::SkyEntity*)ToObjC(static_cast<cxx::Entity*>(entity));
}

} // namespace oo

#endif // SKYENTITY_OBJCBRIDGE_H
