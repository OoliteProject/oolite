/*

SkyEntity+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, amendments oo-bj8 and oo-0mxi): the Objective-C SkyEntity
facade (see SkyEntity+ObjCBridge.h). Deleted with SkyEntity+ObjCBridge.h.

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
#import "SkyEntity.h"

@implementation SkyEntity

// [[SkyEntity alloc] initWithColors::andSystemInfo:] (the universe): a C++ sky, then the
// initialiser's body (amendment oo-0mxi item 2). Sent again, it keeps its C++ part and runs the
// body again, as the Objective-C initialiser did.
- (id)initWithColors:(OOColor*)col1 col2:(OOColor*)col2 andSystemInfo:(const oo::PList&)systemInfo
{
    if (_cxxEntity != nullptr)
        self = [super initWithCxxEntity:_cxxEntity.get()];
    else
        self = [super initWithCxxEntity:oo::makeRef<cxx::SkyEntity>().get()];
    if (self != nil)
        oo::ToCxx(self)->initWithColors(oo::ToCxx(col1), oo::ToCxx(col2), systemInfo);
    return self;
}

- (BOOL)changeProperty:(const std::string&)key withDictionary:(const oo::PList&)dict
{
    return oo::ToCxx(self)->changeProperty(key, dict);
}
- (OOColor*)skyColor
{
    return oo::ToObjC(oo::ToCxx(self)->getSkyColor());
}

@end
