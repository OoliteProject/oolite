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

#include "Entity.h"
#include "OOPolygonSprite.h"	// OOHUDBeaconIcon (bead oo-7ae4p): the beacon drawable is oo::Ref

#include "oofnd/StdLib.hpp"
#include "oofnd/PList.hpp"


/*	Foundation sweep (proposed ADR-0043, bead oo-tmna): +waypointWithDictionary: takes an oo::PList;
	the beacon accessors are shared and keep id; the beacon strings are std::optional (nil stays
	nil). The initializer is -cxx_initWithDictionary: (bead oo-3rb.292.1; its id twin retired with
	oo-qps.44).
*/


/*	C++ only since bead oo-9ht.108 deleted its Objective-C facade (ADR-0056 amendments oo-9ht.23 and
	oo-9ht.106): the universe makes it with waypointWithDictionary() and hands it to Objective-C with
	oo::NewEntityFacade, whose object is the root Entity's facade. That object answers the
	OOBeaconEntity selectors the beacon list sends for a waypoint's part (the root's category
	Entity (OOWaypointBeacon), Entity+ObjCBridge.mm).
*/
class OOWaypointEntity : public Entity
{
public:
	// +waypointWithDictionary:: a new waypoint, initialised. Callers hand it to Objective-C with
	// oo::NewEntityFacade.
	static oo::Ref<OOWaypointEntity> waypointWithDictionary(const oo::PList &info);

	// -cxx_initWithDictionary:'s body after [super init] (the constructor ran Entity's), run once
	// right after construction (amendment oo-vl43 item 2): it calls members a subclass overrides.
	void initWithDictionary(const oo::PList &info);

	bool getOriented();		// -oriented (amendment oo-862e item 1: the ivar keeps the name)
	OOScalar size();
	void setSize(OOScalar newSize);

	void setOrientation(Quaternion q) override;
	bool isEffect() override;
	bool isWaypoint() override;
	void drawImmediate(bool immediate, bool translucent) override;

	// The binding's bodies (OOJSWaypoint.mm), which the facade forwarded to until bead oo-9ht.108.
	void getJSClass(ooscript::ClassDef **outClass, ooscript::Object *outPrototype) override;
	std::optional<std::string> jsClassName() override;
	bool isVisibleToScripts() override;

	// OOBeaconEntity, answered for the waypoint by the root facade's category (the facade's until
	// bead oo-9ht.108). Other beacons stay their Objective-C objects (amendment oo-bj8 item 4).
	OOComparisonResult compareBeaconCodeWith(Entity *other);
	std::optional<std::string> beaconCode();
	void setBeaconCode(const std::optional<std::string> &bcode);
	std::optional<std::string> beaconLabel();
	void setBeaconLabel(const std::optional<std::string> &blabel);
	bool isBeacon();
	OOHUDBeaconIcon *beaconDrawable();	// borrowed (the protocol type until bead oo-7ae4p)
	Entity *prevBeacon();	// the C++ entity since bead oo-9ht.39.24 (null once its object has gone, as before)
	Entity *nextBeacon();
	void setPrevBeacon(Entity *beaconShip);
	void setNextBeacon(Entity *beaconShip);
	bool isJammingScanning();

private:
	OOScalar				_size = {};

	std::optional<std::string>	_beaconCode;	// nullopt: nil
	std::optional<std::string>	_beaconLabel;
	oo::WeakRef<Entity>	_prevBeacon;	// the beacons' C++ parts (bead oo-9ht.39.5.2; were their objects' weak references)
	oo::WeakRef<Entity>	_nextBeacon;
	oo::Ref<OOHUDBeaconIcon>	_beaconDrawable;
	bool					oriented = {};
};
