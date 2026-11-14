/*
OOShipGroup+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, bead oo-bwrq): the Objective-C OOShipGroup, a facade over the
C++ cxx::OOShipGroup (OOShipGroup.h), for callers that are not converted yet. Its interface is the
one OOShipGroup.h declared before the conversion, copied exactly (same root, OOWeakRefObject; same
selectors and types), so those callers compile and behave unchanged; each method forwards to its
C++ member. Imported as the last line of OOShipGroup.h; do not import it directly.

        a caller that is                       holds / passes                  crosses with
        -------------------------------------  ------------------------------  ----------------------------
        still Objective-C                      OOShipGroup * (this facade)     nothing: messages as before
        converted (C++)                        oo::Ref<cxx::OOShipGroup>, cxx::OOShipGroup *
          handing a group to Objective-C                                        oo::ToObjC(group)
          taking one from Objective-C                                           oo::ToCxx(objcGroup)

Two ivars, not one: _jsSelf is the facade's JavaScript wrapper. The category
OOShipGroup (OOJavaScriptExtensions) in OOJSShipGroup.mm makes and clears it, and the wrapper
retains the facade, so it belongs to the Objective-C object; the category compiles unchanged.
oo::ToObjC gives the group's one live facade (oo::ObjCPeers), so identity (and so the JavaScript
wrapper) survives a round trip. Never add to this file; converted code does not message the
facade. Deleted by its deletion bead once no file outside OOShipGroup.* names the Objective-C
OOShipGroup.

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

#ifndef OOSHIPGROUP_OBJCBRIDGE_H
#define OOSHIPGROUP_OBJCBRIDGE_H

#import "OOFoundation.h"
#import "OOWeakReference.h"

#include <quickjs.h>

#include "oofnd/StdLib.hpp"
#include "oofnd/objc/OOObjCRef.h"

@interface OOShipGroup : OOWeakRefObject {
@private
    oo::Ref<cxx::OOShipGroup> _cxxGroup;

    JSValue _jsSelf; // Zero-filled (not an object) until created; test with JS_IsObject().
}

- (id)init;
- (id)cxx_initWithName:(const std::optional<std::string>&)name OO_RETURNS_RETAINED; // (bead oo-3rb.289.11)
+ (instancetype)cxx_groupWithName:(const std::optional<std::string>&)name;
+ (instancetype)cxx_groupWithName:(const std::optional<std::string>&)name leader:(ShipEntity*)leader;

- (std::optional<std::string>)cxx_name; // nullopt: unnamed (bead oo-3rb.289.11)
- (void)cxx_setName:(const std::optional<std::string>&)name;

- (ShipEntity*)leader;
- (void)setLeader:(ShipEntity*)leader;

// The members at the time this is called, even if the group is mutated later.
- (std::vector<oo::ObjCRef<ShipEntity*>>)cxx_memberArray; // arbitrary order
- (std::vector<oo::ObjCRef<ShipEntity*>>)cxx_memberArrayExcludingLeader; // arbitrary order

- (BOOL)containsShip:(ShipEntity*)ship;
- (BOOL)addShip:(ShipEntity*)ship;
- (BOOL)removeShip:(ShipEntity*)ship;

- (NSUInteger)count; // NOTE: this is O(n).
- (BOOL)isEmpty;

@end

namespace oo {

// The group's Objective-C facade: its live one, else a new one; autoreleased. nil for null.
OOShipGroup* ToObjC(cxx::OOShipGroup* group);
inline OOShipGroup* ToObjC(const Ref<cxx::OOShipGroup>& group) { return ToObjC(group.get()); }

// The C++ group behind a facade, borrowed (the facade retains it); null for nil.
cxx::OOShipGroup* ToCxx(OOShipGroup* group);

} // namespace oo

#endif // OOSHIPGROUP_OBJCBRIDGE_H
