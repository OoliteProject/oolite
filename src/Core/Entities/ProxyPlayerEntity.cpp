/*

ProxyPlayerEntity.m


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

#include "ProxyPlayerEntity.h"


::ShipEntity *ProxyPlayerEntity::newProxyObject(const std::string &key, const oo::PList &dict)
{
	const oo::Ref<ProxyPlayerEntity> proxy = oo::makeRef<ProxyPlayerEntity>();
	::ShipEntity *ship = oo::ToShip(oo::NewShipObject(proxy, key, dict));
	if (ship != nil)  proxy->initProxyDefaults();
	return ship;
}


/*	-cxx_initWithKey:definition:'s body after [super cxx_initWithKey:definition:], which the facade's
	initialiser sent until bead oo-9ht.183, and newProxyObject() runs now (the ship set-up may
	release the object and answer nil).
*/
void ProxyPlayerEntity::initProxyDefaults()
{
	setDialForwardShield(1.0f);
	setDialAftShield(1.0f);
	setDialFuelScoopStatus(hasScoop() ? SCOOP_STATUS_OKAY : SCOOP_STATUS_NOT_INSTALLED);
	setCompassMode(hasEquipmentItemProviding("EQ_ADVANCED_COMPASS") ? COMPASS_MODE_PLANET : COMPASS_MODE_BASIC);
	setTradeInFactor(95);
}


void ProxyPlayerEntity::copyValuesFromPlayer(::PlayerEntity *player)
{
	if (player == nil)  return;
	
	setFuelLeakRate((player != nullptr ? player->fuelLeakRate() : 0.0f));
	setMassLocked((player != nullptr ? player->massLocked() : false));
	setAtHyperspeed((player != nullptr ? player->atHyperspeed() : false));
	setDialForwardShield((player != nullptr ? player->dialForwardShield() : 0.0f));
	setDialAftShield((player != nullptr ? player->dialAftShield() : 0.0f));
	setDialMissileStatus((player != nullptr ? player->dialMissileStatus() : OOMissileStatus{}));
	setDialFuelScoopStatus((player != nullptr ? player->dialFuelScoopStatus() : OOFuelScoopStatus{}));
	setCompassMode((player != nullptr ? player->getCompassMode() : OOCompassMode{}));
	setDialIdentEngaged((player != nullptr ? player->dialIdentEngaged() : false));
	setAlertCondition((player != nullptr ? player->getAlertCondition() : OOAlertCondition{}));
	setTrumbleCount((player != nullptr ? player->getTrumbleCount() : 0));
	setTradeInFactor((player != nullptr ? player->tradeInFactor() : int{}));

}


bool ProxyPlayerEntity::isPlayerLikeShip()
{
	return YES;
}


float ProxyPlayerEntity::fuelLeakRate()
{
	return _fuelLeakRate;
}

void ProxyPlayerEntity::setFuelLeakRate(float value)
{
	_fuelLeakRate = fmax(value, 0.0f);
}


bool ProxyPlayerEntity::massLocked()
{
	return _massLocked;
}

void ProxyPlayerEntity::setMassLocked(bool value)
{
	_massLocked = !!value;
}


bool ProxyPlayerEntity::atHyperspeed()
{
	return _atHyperspeed;
}

void ProxyPlayerEntity::setAtHyperspeed(bool value)
{
	_atHyperspeed = !!value;
}


GLfloat ProxyPlayerEntity::dialForwardShield()
{
	return _dialForwardShield;
}

void ProxyPlayerEntity::setDialForwardShield(GLfloat value)
{
	_dialForwardShield = value;
}


GLfloat ProxyPlayerEntity::dialAftShield()
{
	return _dialAftShield;
}

void ProxyPlayerEntity::setDialAftShield(GLfloat value)
{
	_dialAftShield = value;
}


OOMissileStatus ProxyPlayerEntity::dialMissileStatus()
{
	return _missileStatus;
}

void ProxyPlayerEntity::setDialMissileStatus(OOMissileStatus value)
{
	_missileStatus = value;
}


OOFuelScoopStatus ProxyPlayerEntity::dialFuelScoopStatus()
{
	return _fuelScoopStatus;
}

void ProxyPlayerEntity::setDialFuelScoopStatus(OOFuelScoopStatus value)
{
	_fuelScoopStatus = value;
}


OOCompassMode ProxyPlayerEntity::compassMode()
{
	return _compassMode;
}

void ProxyPlayerEntity::setCompassMode(OOCompassMode value)
{
	_compassMode = value;
}


bool ProxyPlayerEntity::dialIdentEngaged()
{
	return _dialIdentEngaged;
}

void ProxyPlayerEntity::setDialIdentEngaged(bool value)
{
	_dialIdentEngaged = !!value;
}


OOAlertCondition ProxyPlayerEntity::alertCondition()
{
	return _alertCondition;
}

void ProxyPlayerEntity::setAlertCondition(OOAlertCondition value)
{
	_alertCondition = value;
}


NSUInteger ProxyPlayerEntity::trumbleCount()
{
	return _trumbleCount;
}


void ProxyPlayerEntity::setTrumbleCount(NSUInteger value)
{
	_trumbleCount = value;
}


void ProxyPlayerEntity::setTradeInFactor(int tif)
{
	_tradeInFactor = tif;
}


int ProxyPlayerEntity::tradeInFactor()
{
	return _tradeInFactor;
}



// If you're here to add more properties, don't forget to update copyValuesFromPlayer().

