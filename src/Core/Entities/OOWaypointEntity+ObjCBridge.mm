/*

OOWaypointEntity+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, amendments oo-bj8 and oo-0mxi): the Objective-C
OOWaypointEntity facade (see OOWaypointEntity+ObjCBridge.h). Deleted with
OOWaypointEntity+ObjCBridge.h.

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

#import "OOJSWaypoint.h"
#import "OOWaypointEntity.h"

@implementation OOWaypointEntity

// The waypoint is made in C++, and this facade with it (oo::NewEntityFacade picks this class).
+ (instancetype)waypointWithDictionary:(const oo::PList&)info
{
    return (OOWaypointEntity*)oo::NewEntityFacade(cxx::OOWaypointEntity::waypointWithDictionary(info));
}

// [[OOWaypointEntity alloc] cxx_initWithDictionary:]: a C++ waypoint, then the initialiser's body
// (amendment oo-0mxi item 2). Sent again, it keeps its C++ part and runs the body again.
- (id)cxx_initWithDictionary:(const oo::PList&)info
{
    if (_cxxEntity != nullptr)
        self = [super initWithCxxEntity:_cxxEntity.get()];
    else
        self = [super initWithCxxEntity:oo::makeRef<cxx::OOWaypointEntity>().get()];
    if (self != nil)
        oo::ToCxx(self)->initWithDictionary(info);
    return self;
}

- (BOOL)oriented
{
    return oo::ToCxx(self)->getOriented();
}
- (OOScalar)size
{
    return oo::ToCxx(self)->size();
}
- (void)setSize:(OOScalar)newSize
{
    oo::ToCxx(self)->setSize(newSize);
}

// OOBeaconEntity

- (OOComparisonResult)compareBeaconCodeWith:(Entity<OOBeaconEntity>*)other
{
    return oo::ToCxx(self)->compareBeaconCodeWith(other);
}
- (std::optional<std::string>)beaconCode
{
    return oo::ToCxx(self)->beaconCode();
}
- (void)setBeaconCode:(const std::optional<std::string>&)bcode
{
    oo::ToCxx(self)->setBeaconCode(bcode);
}
- (std::optional<std::string>)beaconLabel
{
    return oo::ToCxx(self)->beaconLabel();
}
- (void)setBeaconLabel:(const std::optional<std::string>&)blabel
{
    oo::ToCxx(self)->setBeaconLabel(blabel);
}
- (BOOL)isBeacon
{
    return oo::ToCxx(self)->isBeacon();
}
- (id<OOHUDBeaconIcon>)beaconDrawable
{
    return oo::ToCxx(self)->beaconDrawable();
}
- (Entity<OOBeaconEntity>*)prevBeacon
{
    return oo::ToCxx(self)->prevBeacon();
}
- (Entity<OOBeaconEntity>*)nextBeacon
{
    return oo::ToCxx(self)->nextBeacon();
}
- (void)setPrevBeacon:(Entity<OOBeaconEntity>*)beaconShip
{
    oo::ToCxx(self)->setPrevBeacon(beaconShip);
}
- (void)setNextBeacon:(Entity<OOBeaconEntity>*)beaconShip
{
    oo::ToCxx(self)->setNextBeacon(beaconShip);
}
- (BOOL)isJammingScanning
{
    return oo::ToCxx(self)->isJammingScanning();
}

// The JS side, which the engine asks for by selector (Entity (OOJavaScriptExtensions)): the
// binding's category, moved here from the binding's bridge file, which it deletes (bead oo-9ht.50;
// ADR-0056 amendment oo-6ia4 item 3). Each forwards to the OOJSWaypoint.mm function that holds its
// old body; they become members of the C++ class with this facade's deletion (oo-9ht.108).
- (JSClassID)oo_jsClassID
{
    return ::JSWaypointClassID();
}
- (std::optional<std::string>)cxx_oo_jsClassName
{
    return ::OOJSWaypointJSClassName();
}
- (BOOL)isVisibleToScripts
{
    return ::OOJSWaypointIsVisibleToScripts();
}

@end
