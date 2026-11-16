/*

OOQuiriumCascadeEntity+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, amendments oo-bj8 and oo-2c6g): the category of the Objective-C
Entity that OOQuiriumCascadeEntity.mm implemented (amendment oo-ppc item 3). Deleted with
OOQuiriumCascadeEntity+ObjCBridge.h.

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

#import "OOQuiriumCascadeEntity.h"

@implementation Entity (OOQuiriumCascadeExtensions)

- (BOOL)isCascadeWeapon
{
    // NO, but for a cascade: the class overrode this, and it is C++ now, with no facade to override
    // it (amendment oo-2c6g). Objective-C classes that override it still do.
    OOQuiriumCascadeEntity* cascade = dynamic_cast<OOQuiriumCascadeEntity*>(oo::ToCxx(self));
    return cascade != nullptr ? cascade->isCascadeWeapon() : NO;
}

@end
