/*
OOShipGroup.h

A weak-referencing, mutable set of ships. Not thread safe.

C++20 since bead oo-bwrq (proposed ADR-0056). The class is cxx::OOShipGroup while
OOShipGroup+ObjCBridge.h, imported at the end of this header, keeps the Objective-C OOShipGroup
its unconverted callers message (ShipEntity, StationEntity, Universe, the JavaScript ShipGroup
binding, which keeps its category on the facade); the bridge's deletion bead moves it out of
namespace cxx.


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

#ifndef OOSHIPGROUP_H
#define OOSHIPGROUP_H

#import "OOFoundation.h"
#import "OOWeakReference.h"

#include <quickjs.h>

#include "oofnd/Ref.hpp"
#include "oofnd/StdLib.hpp"
#include "oofnd/objc/OOObjCRef.h"

@class ShipEntity;
@class OOShipGroup; // the Objective-C facade (OOShipGroup+ObjCBridge.h), for OOShipGroupCursor's transitional constructor

class OOShipGroupCursor;
class OOShipGroupMembers; // OOShipGroup.mm's range-for over the members

namespace cxx {

class OOShipGroup : public oo::RefCounted {
public:
    // Null if the member array cannot be allocated (-cxx_initWithName: returned nil).
    static oo::Ref<OOShipGroup> groupWithName(const std::optional<std::string>& name);
    static oo::Ref<OOShipGroup> groupWithName(const std::optional<std::string>& name, ShipEntity* leader);

    ~OOShipGroup() override;

    std::optional<std::string> name(); // nullopt: unnamed (bead oo-3rb.289.11)
    void setName(const std::optional<std::string>& name);

    ShipEntity* leader();
    void setLeader(ShipEntity* leader);

    // The members at the time this is called, even if the group is mutated later.
    std::vector<oo::ObjCRef<ShipEntity*>> memberArray(); // arbitrary order
    std::vector<oo::ObjCRef<ShipEntity*>> memberArrayExcludingLeader(); // arbitrary order

    bool containsShip(ShipEntity* ship);
    bool addShip(ShipEntity* ship);
    bool removeShip(ShipEntity* ship);

    NSUInteger count(); // NOTE: this is O(n).
    bool isEmpty();

    // What "%@" prints between the braces of <OOShipGroup 0x...>{...} (OODescription.h).
    std::optional<std::string> descriptionComponents() const;

private:
    // The ivars hold the Objective-C facade, ::OOWeakReference; inside namespace cxx the bare name
    // is cxx::OOWeakReference since bead oo-3kqi (ADR-0056 amendment oo-rmd7 item 3).
    using OOWeakReference = ::OOWeakReference;

    // The cursor and the range-for read the ivars, as they did from inside the Objective-C class.
    friend class ::OOShipGroupCursor;
    friend class ::OOShipGroupMembers;

    // -cxx_initWithName:, which could fail (proposed ADR-0056 amendment oo-bhb9 item 1).
    bool initWithName(const std::optional<std::string>& name);

    bool resizeTo(NSUInteger newCapacity);
    void cleanUp();

    NSUInteger updateCount();

    NSUInteger _count = { }, _capacity = { };
    unsigned long _updateCount = { };
    OOWeakReference** _members = { };
    OOWeakReference* _leader = { };
    std::optional<std::string> _name = { };
    // _jsSelf stays in the Objective-C facade: it is the facade's JavaScript wrapper, which the
    // category in OOJSShipGroup.mm makes and clears.
};

} // namespace cxx

/*	OOShipGroupCursor: steps through a group's live members in its internal order (the former
        OOShipGroupEnumerator, bead oo-5l4w). It raises if the group is mutated while it is in use,
        compacts dead references as it passes them, and unless told not to runs the group's clean-up
        at the end. It keeps the group alive.
*/
class OOShipGroupCursor {
public:
    explicit OOShipGroupCursor(cxx::OOShipGroup* group);
    // Transitional: the Objective-C facade's group (defined in OOShipGroup+ObjCBridge.mm; deleted
    // with it).
    explicit OOShipGroupCursor(OOShipGroup* group);

    ShipEntity* next(); // nil at the end
    NSUInteger index() const { return _index; }
    void setPerformCleanup(BOOL flag) { _considerCleanup = flag; }

    // Public so ShipGroupIterate() can peek at both these and OOShipGroup's ivars. Naughty!
    oo::Ref<cxx::OOShipGroup> _group;
    NSUInteger _index = 0, _updateCount = 0;
    BOOL _considerCleanup = YES, _cleanupNeeded = NO;
};

// Transitional: the Objective-C OOShipGroup, for callers not yet converted. Deleted, with
// namespace cxx above, by the bridge's deletion bead.
#import "OOShipGroup+ObjCBridge.h"

#endif // OOSHIPGROUP_H
