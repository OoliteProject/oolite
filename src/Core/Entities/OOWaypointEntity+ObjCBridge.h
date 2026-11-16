/*

OOWaypointEntity+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, amendments oo-bj8 and oo-0mxi): the Objective-C
OOWaypointEntity, the facade of a converted leaf entity over the C++ cxx::OOWaypointEntity
(OOWaypointEntity.h), kept because the universe makes it (+waypointWithDictionary:) and keeps it
in its beacon list, and the universe, the HUD and the scripting binding message it by its own
selectors and as an OOBeaconEntity. Its interface is the one OOWaypointEntity.h declared before
the conversion, copied exactly, and it has no ivars: the root's _cxxEntity holds its C++ part. A
waypoint is made in C++, and oo::NewEntityFacade picks this class for it. Imported as the last
line of OOWaypointEntity.h; do not import it directly. Never add to this file. Deleted by its
deletion bead once its callers are C++.

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

#ifndef OOWAYPOINTENTITY_OBJCBRIDGE_H
#define OOWAYPOINTENTITY_OBJCBRIDGE_H

@interface OOWaypointEntity : Entity <OOBeaconEntity>

+ (instancetype)waypointWithDictionary:(const oo::PList&)info;

- (id)cxx_initWithDictionary:(const oo::PList&)info OO_RETURNS_RETAINED;

- (BOOL)oriented;
- (OOScalar)size;
- (void)setSize:(OOScalar)newSize;

@end

namespace oo {

// The root's crossings, typed (amendment oo-up4b item 3).
inline cxx::OOWaypointEntity* ToCxx(::OOWaypointEntity* entity)
{
    return static_cast<cxx::OOWaypointEntity*>(ToCxx(static_cast<::Entity*>(entity)));
}
inline ::OOWaypointEntity* ToObjC(cxx::OOWaypointEntity* entity)
{
    return (::OOWaypointEntity*)ToObjC(static_cast<cxx::Entity*>(entity));
}

} // namespace oo

#endif // OOWAYPOINTENTITY_OBJCBRIDGE_H
