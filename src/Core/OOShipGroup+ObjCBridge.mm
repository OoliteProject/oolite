/*
OOShipGroup+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, bead oo-bwrq): the Objective-C OOShipGroup facade over
cxx::OOShipGroup. Every method forwards to its C++ member; groups that were OOShipGroup * come
back through oo::ToObjC. Deleted with OOShipGroup+ObjCBridge.h.

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

#import "OOShipGroup.h"

#include "oofnd/objc/OOObjCPeer.h"

namespace {

// Never destroyed: a facade may be released while the process exits.
oo::ObjCPeers& Peers()
{
    static oo::ObjCPeers* peers = new oo::ObjCPeers;
    return *peers;
}

} // namespace

@interface OOShipGroup (OOObjCBridgePrivate)

// For oo::ToObjC, under the peer table's lock: stores the C++ group.
- (id)initWithCxxGroup:(cxx::OOShipGroup*)group;

// For -cxx_initWithName:: adopts a new C++ group (nil if there is none, as a failed init was)
// and records the facade as its peer (amendment oo-bhb9 item 3).
- (id)initWithNewCxxGroup:(const oo::Ref<cxx::OOShipGroup>&)group;

@end

@implementation OOShipGroup

// Inside the @implementation for the private ivar.
OOShipGroup* oo::ToObjC(cxx::OOShipGroup* group)
{
    return Peers().peerFor(group, [group] { return [[OOShipGroup alloc] initWithCxxGroup:group]; });
}

cxx::OOShipGroup* oo::ToCxx(OOShipGroup* group)
{
    if (group == nil)
        return nullptr;
    return group->_cxxGroup.get();
}

- (id)initWithCxxGroup:(cxx::OOShipGroup*)group
{
    self = [super init];
    if (self != nil)
        _cxxGroup = oo::Ref<cxx::OOShipGroup>(group);
    return self;
}

- (id)initWithNewCxxGroup:(const oo::Ref<cxx::OOShipGroup>&)group
{
    if (group == nullptr) {
        [self release];
        return nil;
    }
    self = [super init];
    if (self != nil) {
        _cxxGroup = group;
        @autoreleasepool {
            Peers().peerFor(_cxxGroup.get(), [self] { return [self retain]; });
        }
    }
    return self;
}

- (id)init
{
    return [self cxx_initWithName:std::nullopt];
}

- (id)cxx_initWithName:(const std::optional<std::string>&)name
{
    return [self initWithNewCxxGroup:cxx::OOShipGroup::groupWithName(name)];
}

+ (instancetype)cxx_groupWithName:(const std::optional<std::string>&)name
{
    return oo::ToObjC(cxx::OOShipGroup::groupWithName(name));
}

+ (instancetype)cxx_groupWithName:(const std::optional<std::string>&)name leader:(ShipEntity*)leader
{
    return oo::ToObjC(cxx::OOShipGroup::groupWithName(name, leader));
}

- (void)dealloc
{
    Peers().forget(_cxxGroup.get());
    [super dealloc];
}

- (std::optional<std::string>)cxx_descriptionComponents
{
    return _cxxGroup->descriptionComponents();
}

- (std::optional<std::string>)cxx_name
{
    return _cxxGroup->name();
}
- (void)cxx_setName:(const std::optional<std::string>&)name
{
    _cxxGroup->setName(name);
}
- (ShipEntity*)leader
{
    return _cxxGroup->leader();
}
- (void)setLeader:(ShipEntity*)leader
{
    _cxxGroup->setLeader(leader);
}

- (std::vector<oo::ObjCRef<ShipEntity*>>)cxx_memberArray
{
    return _cxxGroup->memberArray();
}
- (std::vector<oo::ObjCRef<ShipEntity*>>)cxx_memberArrayExcludingLeader
{
    return _cxxGroup->memberArrayExcludingLeader();
}

- (BOOL)containsShip:(ShipEntity*)ship
{
    return _cxxGroup->containsShip(ship);
}
- (BOOL)addShip:(ShipEntity*)ship
{
    return _cxxGroup->addShip(ship);
}
- (BOOL)removeShip:(ShipEntity*)ship
{
    return _cxxGroup->removeShip(ship);
}
- (NSUInteger)count
{
    return _cxxGroup->count();
}
- (BOOL)isEmpty
{
    return _cxxGroup->isEmpty();
}

/*	This method exists purely to suppress Clang static analyzer warnings that
        this ivar is unused (but may be used by categories, which they are).
        FIXME: there must be a feature macro we can use to avoid actually building
        this into the app, but I can't find it in docs.
*/
- (BOOL)suppressClangStuff
{
    return !JS_IsObject(_jsSelf);
}

@end

OOShipGroupCursor::OOShipGroupCursor(OOShipGroup* group)
    : OOShipGroupCursor(oo::ToCxx(group))
{
}
