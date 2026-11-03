/*

OOFlasherEntity+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, amendments oo-bj8, oo-0otc, oo-0mxi and oo-2c6g): the
Objective-C OOFlasherEntity facade and Entity (OOFlasherEntityExtensions) (see
OOFlasherEntity+ObjCBridge.h). Deleted with OOFlasherEntity+ObjCBridge.h.

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

#import "OOColor.h"
#import "OOFlasherEntity.h"
#import "OOJSFlasher.h"

@implementation OOFlasherEntity

// The flasher is made in C++, and this facade with it (oo::NewEntityFacade picks this class).
+ (instancetype)flasherWithDictionary:(const oo::PList&)dictionary
{
    return (OOFlasherEntity*)oo::NewEntityFacade(cxx::OOFlasherEntity::flasherWithDictionary(dictionary));
}

// [[OOFlasherEntity alloc] cxx_initWithDictionary:]: a C++ flasher, then the initialiser's body
// (amendment oo-0mxi item 2). Sent again, it keeps its C++ part and runs the body again.
- (id)cxx_initWithDictionary:(const oo::PList&)dictionary
{
    if (_cxxEntity != nullptr)
        self = [super initWithCxxEntity:_cxxEntity.get()];
    else
        self = [super initWithCxxEntity:oo::makeRef<cxx::OOFlasherEntity>().get()];
    if (self != nil)
        oo::ToCxx(self)->initWithDictionary(dictionary);
    return self;
}

- (BOOL)isActive
{
    return oo::ToCxx(self)->isActive();
}
- (void)setActive:(BOOL)active
{
    oo::ToCxx(self)->setActive(active);
}
- (OOColor*)color
{
    return oo::ToObjC(oo::ToCxx(self)->color());
}
- (float)frequency
{
    return oo::ToCxx(self)->frequency();
}
- (void)setFrequency:(float)frequency
{
    oo::ToCxx(self)->setFrequency(frequency);
}
- (float)phase
{
    return oo::ToCxx(self)->phase();
}
- (void)setPhase:(float)phase
{
    oo::ToCxx(self)->setPhase(phase);
}
- (float)fraction
{
    return oo::ToCxx(self)->fraction();
}
- (void)setFraction:(float)fraction
{
    oo::ToCxx(self)->setFraction(fraction);
}

// OOSubEntity (-drawSubEntityImmediate:translucent: is OOLightParticleEntity's).
- (void)rescaleBy:(GLfloat)factor
{
    oo::ToCxx(self)->rescaleBy(factor);
}
- (void)rescaleBy:(GLfloat)factor writeToCache:(BOOL)writeToCache
{
    oo::ToCxx(self)->rescaleBy(factor, writeToCache);
}

// The JS side, which the engine asks for by selector (Entity (OOJavaScriptExtensions)): the
// binding's category, moved here from the binding's bridge file, which it deletes (bead oo-9ht.49;
// ADR-0056 amendment oo-6ia4 item 3). Each forwards to the OOJSFlasher.mm function that holds its
// old body; they become members of the C++ class with this facade's deletion (oo-9ht.107).
- (JSClassID)oo_jsClassID
{
    return ::JSFlasherClassID();
}
- (std::optional<std::string>)cxx_oo_jsClassName
{
    return ::OOJSFlasherJSClassName();
}
- (BOOL)isVisibleToScripts
{
    return ::OOJSFlasherIsVisibleToScripts();
}

@end

@implementation Entity (OOFlasherEntityExtensions)

// A C++ flasher answers YES (amendment oo-2c6g item 1); every other entity NO, as before.
- (BOOL)isFlasher
{
    if (cxx::OOFlasherEntity* flasher = dynamic_cast<cxx::OOFlasherEntity*>(_cxxEntity.get()))
        return flasher->isFlasher();
    return NO;
}

@end
