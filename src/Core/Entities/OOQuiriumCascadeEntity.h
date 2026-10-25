/*

OOQuiriumCascadeEntity.h

Droppings of a Q-mine, or one of its victims.


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


/*	A converted leaf (amendment oo-bj8 item 12): global, over Entity, with no facade of its own.
	Unconverted code makes one with quiriumCascadeFromShip() and hands it to Objective-C with
	oo::NewEntityFacade, whose object is an Entity; OOEntityIsCascadeWeapon() asks it.
*/
class OOQuiriumCascadeEntity : public Entity
{
public:
	// +quiriumCascadeFromShip:: a new cascade where the ship is, or null for a nil ship.
	static oo::Ref<OOQuiriumCascadeEntity> quiriumCascadeFromShip(ShipEntity *ship);

	std::optional<std::string> descriptionComponents() const override;

	void update(OOTimeDelta delta_t) override;
	void drawImmediate(bool immediate, bool translucent) override;
	bool isEffect() override;
	bool isCascadeWeapon();
	bool canCollide() override;
	bool checkCloseCollisionWith(Entity *other) override;

private:
	// -initQuiriumCascadeFromShip:'s body: false (no cascade) for a nil ship (amendment oo-novu).
	bool initQuiriumCascadeFromShip(ShipEntity *ship);

	OOTimeDelta			_timePassed = {};
	GLfloat				_color[4] = {};
};


// -isCascadeWeapon of the Objective-C Entity's category, deleted (bead oo-9ht.186): false for null
// and for every entity but a cascade, whose answer it is.
inline bool OOEntityIsCascadeWeapon(Entity *entity)
{
	OOQuiriumCascadeEntity *cascade = dynamic_cast<OOQuiriumCascadeEntity *>(entity);
	return cascade != nullptr ? cascade->isCascadeWeapon() : false;
}
