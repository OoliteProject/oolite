/*

OOBreakPatternEntity+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, amendments oo-bj8 and oo-a014): the Objective-C
OOBreakPatternEntity, the facade of a converted leaf entity over the C++ cxx::OOBreakPatternEntity
(OOBreakPatternEntity.h), kept because the universe makes the rings by its class method and sends
them its own selectors. Its interface is the one OOBreakPatternEntity.h declared before the
conversion, copied exactly, and it has no ivars: the root's _cxxEntity holds its C++ part. The
category of Entity the header declared is here too, unchanged; the facade overrides it, as the
class did. Imported as the last line of OOBreakPatternEntity.h; do not import it directly. Never
add to this file. Deleted by its deletion bead once the universe is C++.

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

#ifndef OOBREAKPATTERNENTITY_OBJCBRIDGE_H
#define OOBREAKPATTERNENTITY_OBJCBRIDGE_H

@class OOColor;

@interface OOBreakPatternEntity : Entity

+ (instancetype)breakPatternWithPolygonSides:(NSUInteger)sides startAngle:(float)startAngleDegrees aspectRatio:(float)aspectRatio;

- (void)setInnerColor:(OOColor*)color1 outerColor:(OOColor*)color2;

- (void)setLifetime:(double)lifetime;

@end

@interface Entity (OOBreakPatternEntity)

- (BOOL)isBreakPattern;

@end

namespace oo {

// The root's crossings, typed (amendment oo-up4b item 3).
inline cxx::OOBreakPatternEntity* ToCxx(::OOBreakPatternEntity* entity)
{
    return static_cast<cxx::OOBreakPatternEntity*>(ToCxx(static_cast<::Entity*>(entity)));
}
inline ::OOBreakPatternEntity* ToObjC(cxx::OOBreakPatternEntity* entity)
{
    return (::OOBreakPatternEntity*)ToObjC(static_cast<cxx::Entity*>(entity));
}

} // namespace oo

#endif // OOBREAKPATTERNENTITY_OBJCBRIDGE_H
