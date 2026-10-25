/*

ProxyPlayerEntity.h

Ship entity which, in some respects, emulates a PlayerShip. In particular, at
this time it implements the extra shader bindable methods of PlayerShip.

The class is C++ (bead oo-amwj; proposed ADR-0056, amendment oo-amwj): ProxyPlayerEntity holds the
proxy's dials and their accessors. Since bead oo-9ht.183 deleted its Objective-C facade (amendment
oo-9ht.183) the universe and the player make it with newProxyObject(), and its object is a
ship's, whose root facade answers its dials to the shader bindings by selector (the ship's
facade did until bead oo-9ht.144).

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

#include "PlayerEntity.h"


/*	The proxy's state and methods. Its ship part is ShipEntity's. C++ only since bead oo-9ht.183
	deleted its Objective-C facade (ADR-0056 amendment oo-9ht.183): newProxyObject() makes it and its
	object, which answers the proxy's dials to the shaders by name.
*/
class ProxyPlayerEntity : public ShipEntity
{
public:
	/*	[[ProxyPlayerEntity alloc] cxx_initWithKey:definition:] until bead oo-9ht.183: a new proxy,
		set up from its definition as a ship (oo::NewShipObject), then given the proxy's defaults.
		Answers the proxy, its object retained (+1) as +alloc/-init's was, or nullptr when the set-up
		fails (bead oo-9ht.144: the object until then).
	*/
	static ::ShipEntity *newProxyObject(const std::string &key, const oo::PList &dict);

	// -cxx_initWithKey:definition:'s body after [super cxx_initWithKey:definition:].
	void initProxyDefaults();

	void copyValuesFromPlayer(::PlayerEntity *player);

	// True for PlayerEntity or ProxyPlayerEntity (the category Entity (ProxyPlayer), which went with
	// the facade in bead oo-9ht.183).
	bool isPlayerLikeShip();

	// Default: 0
	float fuelLeakRate();
	void setFuelLeakRate(float value);

	// Default: NO
	bool massLocked();
	void setMassLocked(bool value);

	// Default: NO
	bool atHyperspeed();
	void setAtHyperspeed(bool value);

	// Default: 1
	GLfloat dialForwardShield();
	void setDialForwardShield(GLfloat value);

	// Default: 1
	GLfloat dialAftShield();
	void setDialAftShield(GLfloat value);

	// Default: MISSILE_STATUS_SAFE
	OOMissileStatus dialMissileStatus();
	void setDialMissileStatus(OOMissileStatus value);

	// Default: SCOOP_STATUS_NOT_INSTALLED or SCOOP_STATUS_OKAY depending on equipment.
	OOFuelScoopStatus dialFuelScoopStatus();
	void setDialFuelScoopStatus(OOFuelScoopStatus value);

	// Default: COMPASS_MODE_BASIC or COMPASS_MODE_PLANET depending on equipment.
	OOCompassMode compassMode();
	void setCompassMode(OOCompassMode value);

	// Default: NO
	bool dialIdentEngaged();
	void setDialIdentEngaged(bool value);

	// Default: ALERT_CONDITION_DOCKED
	OOAlertCondition alertCondition() override;
	void setAlertCondition(OOAlertCondition value);

	// Default: 0
	NSUInteger trumbleCount();
	void setTrumbleCount(NSUInteger value);

	void setTradeInFactor(int tif);
	int tradeInFactor();

private:
	float					_fuelLeakRate = 0;
	GLfloat					_dialForwardShield = 0;
	GLfloat					_dialAftShield = 0;
	OOMissileStatus			_missileStatus = {};
	OOFuelScoopStatus		_fuelScoopStatus = {};
	OOCompassMode			_compassMode = {};
	OOAlertCondition		_alertCondition = {};
	NSUInteger				_trumbleCount = 0;
	int						_tradeInFactor = 0;
	unsigned				_massLocked: 1 = 0,
							_atHyperspeed: 1 = 0,
							_dialIdentEngaged: 1 = 0;
};
