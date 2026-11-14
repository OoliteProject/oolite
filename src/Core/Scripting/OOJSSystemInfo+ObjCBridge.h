/*

OOJSSystemInfo+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, bead oo-6ia4): the Objective-C OOSystemInfo, the facade of a
cxx::OOSystemInfo (OOJSSystemInfo.h). Nothing outside OOJSSystemInfo.mm names the class, but a
SystemInfo's JS private slot holds this facade retained (amendment oo-ppc item 5), and the engine
sends it the JS glue selectors (-oo_jsValueInContext:, -cxx_oo_jsClassName) and asks for its
description. Its interface is the one OOJSSystemInfo.mm declared before the conversion, copied
exactly (same root, OOObject; same selectors and types); each method forwards to its C++ member.
Imported as the last line of OOJSSystemInfo.h; do not import it directly. Deleted by its deletion
bead once the engine's object wrappers hold C++ objects (amendment oo-ppc item 5).


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

#ifndef OOJSSYSTEMINFO_OBJCBRIDGE_H
#define OOJSSYSTEMINFO_OBJCBRIDGE_H

#import "oofnd/objc/OOObject.h"

@interface OOSystemInfo : OOObject {
@private
    oo::Ref<cxx::OOSystemInfo> _cxxInfo;
}

- (id)initWithGalaxy:(OOGalaxyID)galaxy system:(OOSystemID)system;

- (oo::PList)cxx_valueForKey:(const std::optional<std::string>&)key; // null for none
- (void)cxx_setValue:(const oo::PList&)value forKey:(const std::string&)key; // a null value removes

- (std::vector<std::string>)cxx_allKeys;

- (void)setNullAssigned:(BOOL)flag forKey:(const std::string&)key;
- (BOOL)isNullAssignedForKey:(const std::string&)key;

- (OOGalaxyID)galaxy;
- (OOSystemID)system;
//- (Random_Seed) systemSeed;

@end

namespace oo {

// The system info's facade: its live one, else a new one; autoreleased. nil for null.
::OOSystemInfo* ToObjC(cxx::OOSystemInfo* info);

// The C++ system info behind a facade, borrowed (the facade retains it); null for nil.
cxx::OOSystemInfo* ToCxx(::OOSystemInfo* info);

} // namespace oo

#endif // OOJSSYSTEMINFO_OBJCBRIDGE_H
