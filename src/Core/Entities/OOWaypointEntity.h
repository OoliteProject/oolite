/*

OOWaypoint.h

A waypoint for the HUD


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

#pragma once

#import "Entity.h"

#include "oofnd/PList.hpp"
#include "oofnd/StdLib.hpp"
#include "oofnd/objc/OOObjCRef.h"

/*	Foundation sweep (proposed ADR-0043, bead oo-tmna): +waypointWithDictionary: takes an oo::PList;
        the beacon accessors are shared and keep id; the beacon strings are std::optional (nil stays
        nil). The initializer is -cxx_initWithDictionary: (bead oo-3rb.292.1; its id twin retired with
        oo-qps.44).
*/
// Another beacon, which stays its Objective-C object (amendment oo-bj8 item 4). Named at file
// scope: inside namespace cxx a protocol list cannot follow the qualified name ::Entity.
typedef Entity<OOBeaconEntity> OOBeaconEntityObject;

namespace cxx {

class OOWaypointEntity : public Entity {
public:
    // +waypointWithDictionary:: a new waypoint, initialised. The facade's class method hands it to
    // Objective-C (oo::NewEntityFacade).
    static oo::Ref<OOWaypointEntity> waypointWithDictionary(const oo::PList& info);

    // -cxx_initWithDictionary:'s body after [super init] (the constructor ran Entity's), run once
    // right after construction (amendment oo-vl43 item 2): it calls members a subclass overrides.
    void initWithDictionary(const oo::PList& info);

    bool getOriented(); // -oriented (amendment oo-862e item 1: the ivar keeps the name)
    OOScalar size();
    void setSize(OOScalar newSize);

    void setOrientation(Quaternion q) override;
    bool isEffect() override;
    bool isWaypoint() override;
    void drawImmediate(bool immediate, bool translucent) override;

    // OOBeaconEntity, answered by the facade. Other beacons stay their Objective-C objects
    // (amendment oo-bj8 item 4).
    OOComparisonResult compareBeaconCodeWith(OOBeaconEntityObject* other);
    std::optional<std::string> beaconCode();
    void setBeaconCode(const std::optional<std::string>& bcode);
    std::optional<std::string> beaconLabel();
    void setBeaconLabel(const std::optional<std::string>& blabel);
    bool isBeacon();
    id<OOHUDBeaconIcon> beaconDrawable();
    OOBeaconEntityObject* prevBeacon();
    OOBeaconEntityObject* nextBeacon();
    void setPrevBeacon(OOBeaconEntityObject* beaconShip);
    void setNextBeacon(OOBeaconEntityObject* beaconShip);
    bool isJammingScanning();

private:
    OOScalar _size = { };

    std::optional<std::string> _beaconCode; // nullopt: nil
    std::optional<std::string> _beaconLabel;
    oo::ObjCRef<::OOWeakReference*> _prevBeacon;
    oo::ObjCRef<::OOWeakReference*> _nextBeacon;
    oo::ObjCRef<id<OOHUDBeaconIcon>> _beaconDrawable;
    bool oriented = { };
};

} // namespace cxx

// Transitional: the Objective-C OOWaypointEntity, for the universe, the HUD and the scripting
// binding, which make it and message it. Deleted, with namespace cxx above, by the bridge's
// deletion bead.
#import "OOWaypointEntity+ObjCBridge.h"
