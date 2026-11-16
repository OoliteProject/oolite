/*

OOExhaustPlumeEntity+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, amendments oo-bj8, oo-0mxi and oo-2c6g): the Objective-C
OOExhaustPlumeEntity, the facade of a converted leaf entity over the C++
cxx::OOExhaustPlumeEntity (OOExhaustPlumeEntity.h), kept because the ships make it
(+exhaustForShip:withDefinition:andScale:) and message it (-resetPlume, OOSubEntity), and the
scripting binding finds it by its class and sends it its own selectors; the class is also the
graphics reset client of the plume texture. Its interface is the one OOExhaustPlumeEntity.h
declared before the conversion, copied exactly, and it has no ivars: the root's _cxxEntity holds
its C++ part. A plume is made in C++, and oo::NewEntityFacade picks this class for it. The
header's category of Entity, -isExhaust, is here too (amendment oo-2c6g item 1): it answers from
the C++ part. Imported as the last line of OOExhaustPlumeEntity.h; do not import it directly.
Never add to this file. Deleted by its deletion bead once its callers are C++.

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

#ifndef OOEXHAUSTPLUMEENTITY_OBJCBRIDGE_H
#define OOEXHAUSTPLUMEENTITY_OBJCBRIDGE_H

@interface OOExhaustPlumeEntity : Entity <OOSubEntity>

// definition: the exhaust's tokens (x y z scale_x scale_y scale_z), read as -oo_floatAtIndex: read them.
+ (id)exhaustForShip:(ShipEntity*)ship withDefinition:(const std::vector<std::string>&)definition andScale:(float)scale;
- (id)initForShip:(ShipEntity*)ship withDefinition:(const std::vector<std::string>&)definition andScale:(float)scale;

- (void)resetPlume;

- (Vector)scale;
- (void)setScale:(Vector)scale;

- (OOTexture*)texture;

+ (void)setUpTexture;
+ (OOTexture*)plumeTexture;
+ (void)resetGraphicsState;

@end

@interface Entity (OOExhaustPlume)

- (BOOL)isExhaust;

@end

namespace oo {

// The root's crossings, typed (amendment oo-up4b item 3).
inline cxx::OOExhaustPlumeEntity* ToCxx(::OOExhaustPlumeEntity* entity)
{
    return static_cast<cxx::OOExhaustPlumeEntity*>(ToCxx(static_cast<::Entity*>(entity)));
}
inline ::OOExhaustPlumeEntity* ToObjC(cxx::OOExhaustPlumeEntity* entity)
{
    return (::OOExhaustPlumeEntity*)ToObjC(static_cast<cxx::Entity*>(entity));
}

} // namespace oo

#endif // OOEXHAUSTPLUMEENTITY_OBJCBRIDGE_H
