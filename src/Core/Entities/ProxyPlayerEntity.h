/*

ProxyPlayerEntity.h

Ship entity which, in some respects, emulates a PlayerShip. In particular, at
this time it implements the extra shader bindable methods of PlayerShip.

ProxyPlayerEntity holds the proxy's dials and their accessors. The universe and
the player make it with newProxyObject(). The shader bindings read its dials by
name.

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

/*	The proxy's state and methods. Its ship part is ShipEntity's.
        newProxyObject() makes it and its object, which answers the proxy's
        dials to the shaders by name.
*/
class ProxyPlayerEntity : public ShipEntity {
 public:
  /*	A new proxy, set up from its definition as a ship (oo::NewShipObject),
          then given the proxy's defaults. Answers the proxy, its object
          retained (+1) as +alloc/-init's was, or nullptr when the set-up
          fails.
  */
  static ::ShipEntity* newProxyObject(const std::string& key,
                                      const oo::PList& dict);

  // -cxx_initWithKey:definition:'s body after [super
  // cxx_initWithKey:definition:].
  void initProxyDefaults();

  void copyValuesFromPlayer(::PlayerEntity* player);

  // True for PlayerEntity or ProxyPlayerEntity.
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

  // Default: SCOOP_STATUS_NOT_INSTALLED or SCOOP_STATUS_OKAY depending on
  // equipment.
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
  std::size_t trumbleCount();
  void setTrumbleCount(std::size_t value);

  void setTradeInFactor(int tif);
  int tradeInFactor();

 private:
  float _fuelLeakRate = 0;
  GLfloat _dialForwardShield = 0;
  GLfloat _dialAftShield = 0;
  OOMissileStatus _missileStatus = {};
  OOFuelScoopStatus _fuelScoopStatus = {};
  OOCompassMode _compassMode = {};
  OOAlertCondition _alertCondition = {};
  std::size_t _trumbleCount = 0;
  int _tradeInFactor = 0;
  unsigned _massLocked : 1 = 0, _atHyperspeed : 1 = 0,
                         _dialIdentEngaged : 1 = 0;
};
