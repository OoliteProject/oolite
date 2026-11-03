/*

OOSunEntity+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, amendments oo-bj8 and oo-0mxi): the Objective-C OOSunEntity
facade (see OOSunEntity+ObjCBridge.h). Deleted with OOSunEntity+ObjCBridge.h.

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
#import "OOSunEntity.h"

@implementation OOSunEntity

#ifndef NDEBUG
// Only -initSunWithColor:andDictionary: makes a sun.
- (id)init
{
    assert(0);
    return nil;
}
#endif

// [[OOSunEntity alloc] initSunWithColor:andDictionary:] (the universe): a C++ sun, then the
// initialiser's body (amendment oo-0mxi item 2). Sent again, it keeps its C++ part and runs the
// body again, as the Objective-C initialiser did.
- (id)initSunWithColor:(OOColor*)sun_color andDictionary:(const oo::PList&)dict
{
    if (_cxxEntity != nullptr)
        self = [super initWithCxxEntity:_cxxEntity.get()];
    else
        self = [super initWithCxxEntity:oo::makeRef<cxx::OOSunEntity>().get()];
    if (self != nil)
        oo::ToCxx(self)->initSunWithColor(oo::ToCxx(sun_color), dict);
    return self;
}

- (BOOL)setSunColor:(OOColor*)sun_color
{
    return oo::ToCxx(self)->setSunColor(oo::ToCxx(sun_color));
}
- (BOOL)changeSunProperty:(const std::string&)key withDictionary:(const oo::PList&)dict
{
    return oo::ToCxx(self)->changeSunProperty(key, dict);
}
- (OOStellarBodyType)planetType
{
    return oo::ToCxx(self)->planetType();
}
- (void)getDiffuseComponents:(GLfloat[4])components
{
    oo::ToCxx(self)->getDiffuseComponents(components);
}
- (void)getSpecularComponents:(GLfloat[4])components
{
    oo::ToCxx(self)->getSpecularComponents(components);
}
- (double)radius
{
    return oo::ToCxx(self)->radius();
}
- (void)setRadius:(GLfloat)rad andCorona:(GLfloat)corona
{
    oo::ToCxx(self)->setRadius(rad, corona);
}
- (BOOL)willGoNova
{
    return oo::ToCxx(self)->willGoNova();
}
- (BOOL)goneNova
{
    return oo::ToCxx(self)->goneNova();
}
- (void)setGoingNova:(BOOL)yesno inTime:(double)interval
{
    oo::ToCxx(self)->setGoingNova(yesno, interval);
}
- (void)drawStarGlare
{
    oo::ToCxx(self)->drawStarGlare();
}
- (void)drawDirectVisionSunGlare
{
    oo::ToCxx(self)->drawDirectVisionSunGlare();
}
- (void)resetNova
{
    oo::ToCxx(self)->resetNova();
}

// OOStellarBody
- (std::optional<std::string>)cxx_name
{
    return oo::ToCxx(self)->name();
}
- (void)cxx_setName:(const std::optional<std::string>&)name
{
    oo::ToCxx(self)->setName(name);
}

@end
