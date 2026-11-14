/*

OOEntityWithDrawable+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, amendment oo-bj8): the Objective-C OOEntityWithDrawable facade
(see OOEntityWithDrawable+ObjCBridge.h). Deleted with OOEntityWithDrawable+ObjCBridge.h.

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

#import "OOEntityWithDrawable.h"

@implementation OOEntityWithDrawable

// An Objective-C entity with a drawable: [[X alloc] init] of a subclass (or of this class).
- (id)init
{
    // -init sent again to an initialised entity keeps its C++ part (the root's -initWithCxxEntity:).
    if (_cxxEntity != nullptr)
        return [super initWithCxxEntity:_cxxEntity.get()];
    return [super initWithCxxEntity:oo::makeRef<oo::ObjCEntity<cxx::OOEntityWithDrawable>>(self).get()];
}

- (OODrawable*)drawable
{
    return oo::ToCxx(self)->getDrawable();
}
- (void)setDrawable:(OODrawable*)inDrawable
{
    oo::ToCxx(self)->setDrawable(inDrawable);
}

@end
