/*

OOSunEntity+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, amendments oo-bj8 and oo-0mxi): the Objective-C OOSunEntity, the
facade of a converted leaf entity over the C++ cxx::OOSunEntity (OOSunEntity.h), kept because the
universe makes it ([[OOSunEntity alloc] initSunWithColor:andDictionary:]) and hands it out
(-[Universe sun]), and the universe, the player, the ships, the HUD, the collision regions, the
environment cube map and the scripting bindings message it by its own selectors and as an
OOStellarBody. Its interface is the one OOSunEntity.h declared before the conversion, copied
exactly, and it has no ivars: the root's _cxxEntity holds its C++ part. Imported as the last line
of OOSunEntity.h; do not import it directly. Never add to this file. Deleted by its deletion bead
once its callers are C++.

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

#ifndef OOSUNENTITY_OBJCBRIDGE_H
#define OOSUNENTITY_OBJCBRIDGE_H

@interface OOSunEntity : Entity <OOStellarBody>

- (id)initSunWithColor:(OOColor*)sun_color andDictionary:(const oo::PList&)dict;
- (BOOL)setSunColor:(OOColor*)sun_color;
- (BOOL)changeSunProperty:(const std::string&)key withDictionary:(const oo::PList&)dict;

- (OOStellarBodyType)planetType;

- (void)getDiffuseComponents:(GLfloat[4])components;
- (void)getSpecularComponents:(GLfloat[4])components;

- (void)setRadius:(GLfloat)rad andCorona:(GLfloat)corona;

- (BOOL)willGoNova;
- (BOOL)goneNova;
- (void)setGoingNova:(BOOL)yesno inTime:(double)interval;

- (void)drawStarGlare;
- (void)drawDirectVisionSunGlare;
- (void)resetNova;

@end

namespace oo {

// The root's crossings, typed (amendment oo-up4b item 3).
inline cxx::OOSunEntity* ToCxx(::OOSunEntity* entity)
{
    return static_cast<cxx::OOSunEntity*>(ToCxx(static_cast<::Entity*>(entity)));
}
inline ::OOSunEntity* ToObjC(cxx::OOSunEntity* entity)
{
    return (::OOSunEntity*)ToObjC(static_cast<cxx::Entity*>(entity));
}

} // namespace oo

#endif // OOSUNENTITY_OBJCBRIDGE_H
