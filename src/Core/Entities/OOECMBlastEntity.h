/*

OOECMBlastEntity.h

Invisible entity which radiates ECM blast energy.

C++20 since bead oo-ryhi, a leaf of the Entities seam (proposed ADR-0056, amendment oo-bj8 item
12). A global class over Entity, with no facade: nothing messages it by its own selectors.
ShipEntity's -fireECM makes it with initFromShip() and hands the universe the Entity facade
oo::NewEntityFacade makes, which is its Objective-C object from then on. The category of Entity
the header declared, -isECMBlast, which nothing sent, went with its bridge (bead oo-9ht.75): ask
the C++ part, dynamic_cast<OOECMBlastEntity *>(...)->isECMBlast().

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

class ShipEntity;	// C++ since bead oo-9ht.144


class OOECMBlastEntity : public Entity
{
public:
	// -initFromShip:, which answered nil for a nil ship: null then (amendment oo-novu item 1).
	static oo::Ref<OOECMBlastEntity> initFromShip(ShipEntity *ship);

	void update(OOTimeDelta delta_t) override;
	void drawImmediate(bool immediate, bool translucent) override;

	bool isECMBlast();

private:
	explicit OOECMBlastEntity(ShipEntity *ship);

	OOTimeDelta			_nextBlast = {};
	uint8_t		_blastsRemaining = {};
	oo::WeakRef<Entity>	_ship;	// the ship's C++ part (bead oo-9ht.39.5.2; was its object's weak reference, never released)
};
