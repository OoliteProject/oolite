/*

OOEntityWithDrawable+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, amendment oo-bj8): the Objective-C OOEntityWithDrawable, the
facade of a converted intermediate class (amendment oo-up4b item 2) over the C++
cxx::OOEntityWithDrawable (OOEntityWithDrawable.h). Its interface is the one
OOEntityWithDrawable.h declared before the conversion, copied exactly, and it has no ivars: the
root's _cxxEntity holds its C++ part. Its -init makes an Objective-C subclass's adapter over
cxx::OOEntityWithDrawable (oo::ObjCEntity<cxx::OOEntityWithDrawable>), so ShipEntity, SkyEntity
and OOVisualEffectEntity reach this class's members by [super ...] and the root's through it. The
OOSubEntity protocol the header declared is here, unchanged. Imported as the last line of
OOEntityWithDrawable.h; do not import it directly. Never add to this file. Deleted by its
deletion bead once the subclasses are C++.

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

#ifndef OOENTITYWITHDRAWABLE_OBJCBRIDGE_H
#define OOENTITYWITHDRAWABLE_OBJCBRIDGE_H

// Methods that must be supported by subentities, regardless of type.
@protocol OOSubEntity

- (void)rescaleBy:(GLfloat)factor;
- (void)rescaleBy:(GLfloat)factor writeToCache:(BOOL)writeToCache;

// Separate drawing path for subentities of ships.
- (void)drawSubEntityImmediate:(bool)immediate translucent:(bool)translucent;

@end

@interface OOEntityWithDrawable : Entity

- (OODrawable*)drawable;
- (void)setDrawable:(OODrawable*)drawable;

@end

namespace oo {

// The root's crossings, typed (amendment oo-up4b item 3).
inline cxx::OOEntityWithDrawable* ToCxx(::OOEntityWithDrawable* entity)
{
    return static_cast<cxx::OOEntityWithDrawable*>(ToCxx(static_cast<::Entity*>(entity)));
}

inline ::OOEntityWithDrawable* ToObjC(cxx::OOEntityWithDrawable* entity)
{
    return (::OOEntityWithDrawable*)ToObjC(static_cast<cxx::Entity*>(entity));
}

} // namespace oo

#endif // OOENTITYWITHDRAWABLE_OBJCBRIDGE_H
