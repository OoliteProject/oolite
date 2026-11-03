/*

OOECMBlastEntity+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, amendment oo-bj8 item 12): the category of the Objective-C Entity
that OOECMBlastEntity.h declared, moved here when the class became C++ (bead oo-ryhi), unchanged.
Imported as the last line of OOECMBlastEntity.h; do not import it directly. Deleted by its
deletion bead.

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

#ifndef OOECMBLASTENTITY_OBJCBRIDGE_H
#define OOECMBLASTENTITY_OBJCBRIDGE_H

@interface Entity (OOECMBlastEntity)

- (BOOL)isECMBlast;

@end

#endif // OOECMBLASTENTITY_OBJCBRIDGE_H
