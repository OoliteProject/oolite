/*
OOShipGroup.h

A weak-referencing, mutable set of ships. Not thread safe.


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

#import "OOFoundation.h"
#import "OOWeakReference.h"

#include <quickjs.h>

#include "oofnd/StdLib.hpp"
#include "oofnd/objc/OOObjCRef.h"

@class ShipEntity;

@interface OOShipGroup : OOWeakRefObject {
@private
    NSUInteger _count, _capacity;
    unsigned long _updateCount;
    OOWeakReference** _members;
    OOWeakReference* _leader;
    std::optional<std::string> _name;

    JSValue _jsSelf; // Zero-filled (not an object) until created; test with JS_IsObject().
}

- (id)init;
- (id)initWithName:(id)name; // shared selector (Foundation declares -initWithName: too): -cxx_initWithName: with an Objective-C string, or nil
- (id)cxx_initWithName:(const std::optional<std::string>&)name OO_RETURNS_RETAINED; // (bead oo-3rb.289.11)
+ (instancetype)cxx_groupWithName:(const std::optional<std::string>&)name;
+ (instancetype)cxx_groupWithName:(const std::optional<std::string>&)name leader:(ShipEntity*)leader;

- (id)name; // shared selector (Foundation declares -name too): -cxx_name as an Objective-C string, or nil
- (std::optional<std::string>)cxx_name; // nullopt: unnamed (bead oo-3rb.289.11)
- (void)setName:(id)name; // shared selector (Foundation declares -setName: too): -cxx_setName: with an Objective-C string, or nil
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

/*	OOShipGroupCursor: steps through a group's live members in its internal order (the former
        OOShipGroupEnumerator, bead oo-5l4w). It raises if the group is mutated while it is in use,
        compacts dead references as it passes them, and unless told not to runs the group's clean-up
        at the end. It keeps the group alive.
*/
class OOShipGroupCursor {
public:
    explicit OOShipGroupCursor(OOShipGroup* group);

    ShipEntity* next(); // nil at the end
    NSUInteger index() const { return _index; }
    void setPerformCleanup(BOOL flag) { _considerCleanup = flag; }

    // Public so ShipGroupIterate() can peek at both these and OOShipGroup's ivars. Naughty!
    oo::ObjCRef<OOShipGroup*> _group;
    NSUInteger _index = 0, _updateCount = 0;
    BOOL _considerCleanup = YES, _cleanupNeeded = NO;
};
