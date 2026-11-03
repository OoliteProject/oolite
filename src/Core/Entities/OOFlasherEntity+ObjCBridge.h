/*

OOFlasherEntity+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, amendments oo-bj8, oo-0otc, oo-0mxi and oo-2c6g): the
Objective-C OOFlasherEntity, the facade of a converted leaf entity over the C++
cxx::OOFlasherEntity (OOFlasherEntity.h), kept because the ships and the visual effects make it
(+flasherWithDictionary:) and message it as a subentity (-setActive:, OOSubEntity), and the
scripting binding finds it by its class and sends it its own selectors. Its interface is the one
OOFlasherEntity.h declared before the conversion, copied exactly, and it has no ivars: the root's
_cxxEntity holds its C++ part. A flasher is made in C++, and oo::NewEntityFacade picks this class
for it. The header's category of Entity, -isFlasher, is here too (amendment oo-2c6g item 1): it
answers from the C++ part. Imported as the last line of OOFlasherEntity.h; do not import it
directly. Never add to this file. Deleted by its deletion bead once its callers are C++.

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

#ifndef OOFLASHERENTITY_OBJCBRIDGE_H
#define OOFLASHERENTITY_OBJCBRIDGE_H

@class OOColor;

@interface OOFlasherEntity : OOLightParticleEntity <OOSubEntity>

+ (instancetype)flasherWithDictionary:(const oo::PList&)dictionary;
- (id)cxx_initWithDictionary:(const oo::PList&)dictionary OO_RETURNS_RETAINED;

- (BOOL)isActive;
- (void)setActive:(BOOL)active;

- (OOColor*)color;
// setColor is defined by superclass

- (float)frequency;
- (void)setFrequency:(float)frequency;

- (float)phase;
- (void)setPhase:(float)phase;

- (float)fraction;
- (void)setFraction:(float)fraction;

@end

@interface Entity (OOFlasherEntityExtensions)

- (BOOL)isFlasher;

@end

namespace oo {

// The root's crossings, typed (amendment oo-up4b item 3).
inline cxx::OOFlasherEntity* ToCxx(::OOFlasherEntity* entity)
{
    return static_cast<cxx::OOFlasherEntity*>(ToCxx(static_cast<::Entity*>(entity)));
}
inline ::OOFlasherEntity* ToObjC(cxx::OOFlasherEntity* entity)
{
    return (::OOFlasherEntity*)ToObjC(static_cast<cxx::Entity*>(entity));
}

} // namespace oo

#endif // OOFLASHERENTITY_OBJCBRIDGE_H
