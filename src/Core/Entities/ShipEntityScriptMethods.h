/*

ShipEntityScriptMethods.h

Methods for use by scripting mechanisms.


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

#import "ShipEntity.h"

#include "oofnd/StdLib.hpp"
#include "oofnd/objc/OOObjCRef.h"

@interface ShipEntity (ScriptMethods)

// Foundation sweep (proposed ADR-0043, bead oo-tm7d): std::nullopt ejects nothing, as nil did.
- (ShipEntity*)ejectShipOfType:(const std::optional<std::string>&)shipKey; // Note: ship type, not role.
- (ShipEntity*)ejectShipOfRole:(const std::optional<std::string>&)role;

- (std::vector<oo::ObjCRef<ShipEntity*>>)spawnShipsWithRole:(const std::string&)role count:(NSUInteger)count;

@end
