/*

OOBreakPatternEntity+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, amendments oo-bj8 and oo-a014): the Objective-C
OOBreakPatternEntity facade (see OOBreakPatternEntity+ObjCBridge.h), and the category of Entity
that OOBreakPatternEntity.mm implemented (amendment oo-ppc item 3). Deleted with
OOBreakPatternEntity+ObjCBridge.h.

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

#import "OOBreakPatternEntity.h"
#import "OOColor.h"

@implementation OOBreakPatternEntity

// The ring is made in C++, and this facade with it (oo::NewEntityFacade picks this class).
+ (instancetype)breakPatternWithPolygonSides:(NSUInteger)sides startAngle:(float)startAngleDegrees aspectRatio:(float)aspectRatio
{
    return (OOBreakPatternEntity*)oo::NewEntityFacade(cxx::OOBreakPatternEntity::breakPatternWithPolygonSides(sides, startAngleDegrees, aspectRatio));
}

- (void)setInnerColor:(OOColor*)color1 outerColor:(OOColor*)color2
{
    oo::ToCxx(self)->setInnerColor(oo::ToCxx(color1), oo::ToCxx(color2));
}
- (void)setLifetime:(double)lifetime
{
    oo::ToCxx(self)->setLifetime(lifetime);
}
- (BOOL)isBreakPattern
{
    return oo::ToCxx(self)->isBreakPattern();
}

@end

@implementation Entity (OOBreakPatternEntity)

- (BOOL)isBreakPattern
{
    return NO;
}

@end
