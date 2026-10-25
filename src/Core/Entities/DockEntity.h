/*

DockEntity.h

ShipEntity subclass representing a dock.

C++ since its slice plan (docs/phases/3-slices/DockEntity.md; proposed ADR-0056, amendments
oo-60fwo, oo-64ako and oo-ao2d). Bead oo-9ht.180 deleted its Objective-C facade (amendment
oo-9ht.180): a dock is made in C++ by DockEntity::newDockObject() and its Objective-C object was the
ship's facade, which answered the dock's selectors the game can still find by name for a dock's
C++ part only; since bead oo-9ht.144 (amendment oo-9ht.144) the object is OOEntityWithDrawable's
facade and the root's facade answers them.

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

#include "ShipEntity.h"
#include "StationEntity.h"	// For MAX_DOCKING_STAGES


/*	The dock's state and members (docs/phases/3-slices/DockEntity.md).

	The ivars are data members with the same names, every one zero-initialised as the runtime
	zeroed them (amendment oo-bj8 item 1). Pointers to Objective-C objects stay what they were,
	retained by hand where they were (amendment oo-bj8 item 4). C++ only since bead oo-9ht.180
	deleted its Objective-C facade (ADR-0056 amendment oo-9ht.180).
*/
class DockEntity : public ShipEntity
{
public:
	/*	[[DockEntity alloc] cxx_initWithKey:definition:] until bead oo-9ht.180: a new dock, set up from
		its definition as a ship (oo::NewShipObject), then given the dock's defaults. Answers the dock,
		its object retained (+1) as +alloc/-init's was, or nullptr when the set-up fails (bead
		oo-9ht.144: the object until then).
	*/
	static ::ShipEntity *newDockObject(const std::string &key, const oo::PList &dict);

	// -cxx_initWithKey:definition:'s body after [super cxx_initWithKey:definition:].
	void initDockDefaults();

	// The facade's -dealloc body, which -[ShipEntity dealloc] calls first for a dock's part, as the
	// subclass's -dealloc ran before its superclass's (bead oo-9ht.180).
	void willDealloc();

	// Slice 1: class shell, flags, geometry and lifecycle.
	void clear();

	// Docking
	bool allowsDocking();
	void setAllowsDocking(bool allowed);
	bool disallowedDockingCollides();
	void setDisallowedDockingCollides(bool ddc);
	NSUInteger countOfShipsInDockingQueue();

	// Launching
	bool allowsLaunching();
	void setAllowsLaunching(bool allowed);
	NSUInteger countOfShipsInLaunchQueue();

	// Geometry
	void setDimensionsAndCorridor(bool docking, bool ddc, bool launching);
	Vector portUpVectorForShipsBoundingBox(BoundingBox bb);
	bool isOffCentre();
	void setVirtual();

	// The ID locks (the private category of DockEntity.mm).
	void clearIdLocks(::ShipEntity *ship);
	void clearAllIdLocks();

	// Slice 2: docking guidance, the approach queue and docking instructions.
	oo::PList dockingInstructionsForShip(::ShipEntity *ship);	// a dictionary (the station an Object node); null: none (bead oo-3rb.262)
	std::optional<std::string> canAcceptShipForDocking(::ShipEntity *ship);
	bool shipIsInDockingQueue(::ShipEntity *ship);
	void abortDockingForShip(::ShipEntity *ship);
	void abortAllDockings();
	void autoDockShipsOnApproach();
	NSUInteger pruneAndCountShipsOnApproach();
	void noteDockingForShip(::ShipEntity *ship);
	void autoDockShipsInQueue(std::map<unsigned short, std::vector<oo::PList>> &queue);
	void addShipToShipsOnApproach(::ShipEntity *ship);
	void pullInShipIfPermitted(::ShipEntity *ship);

	// Slice 3: the docking corridor and launching.
	bool shipIsInDockingCorridor(::ShipEntity *ship);
	void abortAllLaunches();
	void addShipToLaunchQueue(::ShipEntity *ship, bool priority);
	void launchShip(::ShipEntity *ship);
	NSUInteger countOfShipsInLaunchQueueWithPrimaryRole(const std::string &role);
	bool allowsLaunchingOf(::ShipEntity *ship);
	bool dockingCorridorIsEmpty();
	void clearDockingCorridor();

	// From the superclass.
	bool isDock() override;
	// Entity (OOJavaScriptExtensions): the binding's bodies (OOJSDock.h).
	void getJSClass(ooscript::ClassDef **outClass, ooscript::Object *outPrototype) override;
	std::optional<std::string> jsClassName() override;
	// The ship's answer (ShipEntity (OOJavaScriptExtensions)), which the facade inherited; a C++ part
	// is asked since bead oo-9ht.180.
	bool isVisibleToScripts() override;
	bool setUpShipFromDictionary(const oo::PList &dict) override;
	void update(OOTimeDelta delta_t) override;
	void noteTakingDamage(double amount, Entity *entity, OOShipDamageType type) override;
	void takeEnergyDamage(double amount, Entity *ent, Entity *other, const std::string &weaponIdentifier) override;
	void drawImmediate(bool immediate, bool translucent) override;

	// @private in Objective-C; still public (the tests read them), as the player's were after its
	// facade went (ADR-0056 amendment oo-9ht.177 item 6)
	std::map<unsigned short, std::vector<oo::PList>>	shipsOnApproach;	// coordinate stacks (Dicts) by ship ID (the old +numberWithUnsignedShort: key)
	std::vector<oo::EntityHold>	launchQueue;	// the ships' objects held (bead oo-9ht.39.19)
	double					last_launch_time = {};
//	double					approach_spacing; // not needed now holding pattern changed
	
	oo::WeakRef<Entity>	id_lock[MAX_DOCKING_STAGES];	// weak references to a ship (its C++ part since bead oo-9ht.39.5.2; its object's before)
	
	Vector  				port_dimensions = {};
	double					port_corridor = {};				// corridor length inside station.
	
	BOOL					no_docking_while_launching = {};
	BOOL					allow_launching = {};
	BOOL					allow_docking = {};
	BOOL					disallowed_docking_collides = {}; 
	BOOL					virtual_dock = {};
};


namespace oo {

// The same of a C++ entity (what an entity's JS object holds since bead oo-9ht.39.3).
inline ::DockEntity *ToDock(Entity *entity)
{
	return dynamic_cast<::DockEntity *>(entity);
}

// The same question of a C++ ship (a ship is C++ since bead oo-9ht.144): nullptr for null or another ship.
inline ::DockEntity *ToDock(::ShipEntity *ship)
{
	return dynamic_cast<::DockEntity *>(ship);
}

}	// namespace oo
