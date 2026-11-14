/*

OOExhaustPlumeEntity+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, amendments oo-bj8, oo-0mxi and oo-2c6g): the Objective-C
OOExhaustPlumeEntity facade and Entity (OOExhaustPlume) (see OOExhaustPlumeEntity+ObjCBridge.h).
Deleted with OOExhaustPlumeEntity+ObjCBridge.h.

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

#import "OOExhaustPlumeEntity.h"

@implementation OOExhaustPlumeEntity

// The plume is made in C++, and this facade with it (oo::NewEntityFacade picks this class); nil for
// no tokens, as before.
+ (id)exhaustForShip:(ShipEntity*)ship withDefinition:(const std::vector<std::string>&)definition andScale:(float)scale
{
    return oo::NewEntityFacade(cxx::OOExhaustPlumeEntity::exhaustForShip(ship, definition, scale));
}

// [[OOExhaustPlumeEntity alloc] initForShip:...]: a C++ plume, then the initialiser's body
// (amendment oo-0mxi item 2); nil for no tokens.
- (id)initForShip:(ShipEntity*)ship withDefinition:(const std::vector<std::string>&)definition andScale:(float)scale
{
    if (_cxxEntity != nullptr)
        self = [super initWithCxxEntity:_cxxEntity.get()];
    else
        self = [super initWithCxxEntity:oo::makeRef<cxx::OOExhaustPlumeEntity>().get()];
    if (self != nil && !oo::ToCxx(self)->initForShip(ship, definition, scale)) {
        [self release];
        return nil;
    }
    return self;
}

- (void)resetPlume
{
    oo::ToCxx(self)->resetPlume();
}
- (Vector)scale
{
    return oo::ToCxx(self)->scale();
}
- (void)setScale:(Vector)scale
{
    oo::ToCxx(self)->setScale(scale);
}
- (OOTexture*)texture
{
    return oo::ToCxx(self)->texture();
}

+ (void)setUpTexture
{
    cxx::OOExhaustPlumeEntity::setUpTexture();
}
+ (OOTexture*)plumeTexture
{
    return cxx::OOExhaustPlumeEntity::plumeTexture();
}

// OOGraphicsResetClient: setUpTexture() registers this class.
+ (void)resetGraphicsState
{
    cxx::OOExhaustPlumeEntity::resetGraphicsState();
}

// OOSubEntity
- (void)rescaleBy:(GLfloat)factor
{
    oo::ToCxx(self)->rescaleBy(factor);
}
- (void)rescaleBy:(GLfloat)factor writeToCache:(BOOL)writeToCache
{
    oo::ToCxx(self)->rescaleBy(factor, writeToCache);
}
- (void)drawSubEntityImmediate:(bool)immediate translucent:(bool)translucent
{
    oo::ToCxx(self)->drawSubEntityImmediate(immediate, translucent);
}

@end

@implementation Entity (OOExhaustPlume)

// A C++ plume answers YES (amendment oo-2c6g item 1); every other entity NO, as before.
- (BOOL)isExhaust
{
    if (cxx::OOExhaustPlumeEntity* exhaust = dynamic_cast<cxx::OOExhaustPlumeEntity*>(_cxxEntity.get()))
        return exhaust->isExhaust();
    return NO;
}

@end
