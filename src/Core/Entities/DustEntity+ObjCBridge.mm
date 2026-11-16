/*

DustEntity+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, amendments oo-bj8 and oo-0mxi): the Objective-C DustEntity facade
(see DustEntity+ObjCBridge.h). Deleted with DustEntity+ObjCBridge.h.

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

#import "DustEntity.h"
#import "OOColor.h"
#import "OOGraphicsResetManager.h"

// What the shader's uniforms and the graphics reset manager send it.
@interface DustEntity (OOObjCBridgePrivate) <OOGraphicsResetClient>

- (Vector)warpVector;
#if OO_SHADERS
- (Vector)offsetPlayerPosition;
#endif

@end

@implementation DustEntity

// [[DustEntity alloc] init] (the universe): a C++ dust entity, then -init's body, which hands this
// object to the graphics reset manager. Sent -init again, it keeps its C++ part (the root's
// -initWithCxxEntity:) and runs the body again, as the Objective-C -init did.
- (id)init
{
    if (_cxxEntity != nullptr)
        self = [super initWithCxxEntity:_cxxEntity.get()];
    else
        self = [super initWithCxxEntity:oo::makeRef<cxx::DustEntity>().get()];
    if (self != nil)
        oo::ToCxx(self)->init();
    return self;
}

- (void)dealloc
{
    [[OOGraphicsResetManager sharedManager] unregisterClient:self];

    [super dealloc];
}

- (void)setDustColor:(OOColor*)color
{
    oo::ToCxx(self)->setDustColor(oo::ToCxx(color));
}
- (OOColor*)dustColor
{
    return oo::ToObjC(oo::ToCxx(self)->dustColor());
}

- (Vector)warpVector
{
    return oo::ToCxx(self)->warpVector();
}
#if OO_SHADERS
- (Vector)offsetPlayerPosition
{
    return oo::ToCxx(self)->offsetPlayerPosition();
}
#endif

- (void)resetGraphicsState
{
    oo::ToCxx(self)->resetGraphicsState();
}

@end
